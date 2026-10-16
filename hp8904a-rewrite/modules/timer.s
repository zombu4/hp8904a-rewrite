; ===========================================================================
; timer.s - the MC6840 Programmable Timer Module, and timed delays
;
; The 6840 carries three 16-bit counters at $1000-$1006. Two things in this
; instrument depend on it: the periodic interrupt that drives the foreground,
; and every millisecond delay the firmware takes.
;
; WHY THE DELAYS ARE HARDWARE-TIMED, and why that must not change
;
; A software delay loop counts instructions, so its duration is a property of
; the code around it. Shorten a branch, and the delay shortens with it. This
; firmware does not do that: delay_ms loads a count into timer 3 and spins on
; the timer's own status bit, so a delay is the same length whatever the code
; looks like.
;
; That is worth stating because the stock ROM was rebuilt once with branch
; relaxation, which shortens 871 branches, and none of its delays moved. If
; these were software loops, relaxation would silently have sped up every
; settling delay in the instrument.
;
; THE REGISTER MAP, from the data sheet and confirmed by what the ROM writes:
;
;   $1000  CR1 or CR3, selected by bit 0 of CR2
;   $1001  CR2, and reading it gives the status byte
;   $1002  timer 1 counter, written high byte then low
;   $1004  timer 2 counter
;   $1006  timer 3 counter
;
; The control registers are write-only, so the firmware keeps a shadow of
; each in RAM and writes both together. Losing a shadow means losing the
; ability to change one bit without disturbing the others.
; ===========================================================================

; --- Control-register bits -------------------------------------------------
; Named rather than written as numbers. #$27 tells a reader nothing about
; which three bits are being set or why.

; Every one of these is Table 2 of the MC6840 data sheet, which is in this
; repository at firmware/datasheets/. Two of them were wrong, and both were
; wrong in the way that is hardest to notice: the VALUES were right, because
; they were copied from the byte the stock firmware writes, and only the
; NAMES were invented to explain it.
;
;   PTM_16BIT was $04 and described as "16-bit counter, not dual 8-bit".
;   Table 2: CRX2 = 0 is normal 16-bit, CRX2 = 1 is DUAL 8-BIT. Setting the
;   bit selects the mode the name denies.
;
;   PTM_PRESCALE was $20 and described as timer 3's divide-by-eight. The
;   prescaler is CR30 - BIT 0 - and bit 5 is part of the three-bit operating
;   mode field. So the name pointed at the wrong bit and the bit it pointed
;   at meant something else.
;
; The byte CR3 receives is unchanged at $27, which is what the stock firmware
; writes and what the hardware was built around. Only the account of what it
; means is corrected.
PTM_CR2_SELECT  equ     $01             ; CR20: 0 selects CR3 at $1000,
                                        ;       1 selects CR1
PTM_RESET_ALL   equ     $01             ; CR10: hold all three in preset
PTM_T3_PRESCALE equ     $01             ; CR30: divide timer 3's clock by 8
PTM_INTERNAL    equ     $02             ; CRX1: 1 uses the Enable clock, 0
                                        ; the external CX input
PTM_DUAL_8BIT   equ     $04             ; CRX2: 1 is dual 8-bit, 0 is the
                                        ; normal 16-bit counting mode
PTM_MODE_SINGLE equ     $20             ; CRX5:4:3 = 100, which Table 3 calls
                                        ; Single Shot Mode: a write to the
                                        ; latches initialises the counter
PTM_MODE_CONTIN equ     $10             ; CRX3=0, CRX4=1, CRX5=0 - Table 3 as
                                        ; read off page 8 of the data sheet:
                                        ; "Continuous Operating Mode: Gate or
                                        ; Reset Causes Counter Initialization".
                                        ;
                                        ; NOTE WHAT IS ABSENT FROM THAT ROW. The
                                        ; other continuous row (CRX3=0, CRX4=0)
                                        ; also initialises on a WRITE TO
                                        ; LATCHES; this one does not. So loading
                                        ; the counter in this mode does not
                                        ; restart it, and starting it means
                                        ; pulsing the internal reset - which is
                                        ; exactly the dance the stock's
                                        ; start_sequence_timer ($6BD0) does and
                                        ; which looks arbitrary until this row
                                        ; is read.
                                        ;
                                        ; It is also what lets the stock change
                                        ; the period of a RUNNING sequence by
                                        ; storing to the latches and nothing
                                        ; else, in commit_period_entry ($4D5E)
                                        ; and step_period_by_increment ($4F95).

PTM_IRQ_ENABLE  equ     $40             ; CRX6: let this timer assert IRQ
PTM_OUTPUT_EN   equ     $80             ; CRX7: let it drive its output pin,
                                        ; which is how the sounder is driven

; The status bit for each timer, read from $1001.
PTM_T1_FLAG     equ     $01             ; status bit per timer, as the
PTM_T2_FLAG     equ     $02             ; MC6840 data sheet gives them. Set
PTM_T3_FLAG     equ     $04             ; when that counter has expired

; The two bytes the stock writes to CR2 to run and to stop its sequence
; timebase, spelled out as the bits they are rather than copied as numbers.
; $D1 and $91 differ in exactly one bit, the interrupt enable.
PTM_SEQ_RUN     equ     PTM_OUTPUT_EN|PTM_IRQ_ENABLE|PTM_MODE_CONTIN|PTM_CR2_SELECT
PTM_SEQ_STOP    equ     PTM_OUTPUT_EN|PTM_MODE_CONTIN|PTM_CR2_SELECT

; --- Preload values --------------------------------------------------------
; What each counter is loaded with at power-on. These come from the stock
; firmware and are kept: they set the interrupt rate the whole foreground is
; written around, and changing one changes how often every key is scanned.

PTM_T1_PRELOAD  equ     $00D2           ; timer 1, exactly as the stock
                                        ; programs it. It is NOT the sequence
                                        ; timebase and nothing here depends on
                                        ; its period: timer 2 is the timebase,
                                        ; for the reasons set out at
                                        ; seq_timer_start below.
                                        ;
                                        ; This was briefly changed to $0697 on
                                        ; the theory that a millisecond tick
                                        ; could be derived from the Enable
                                        ; clock. The theory was sound and the
                                        ; premise was wrong: the instrument
                                        ; already has a sequence timebase, it
                                        ; is timer 2, and inventing a second
                                        ; one from a different clock would have
                                        ; put two answers in the firmware for a
                                        ; question the hardware answers once.
PTM_T2_PRELOAD  equ     $0000
PTM_T3_PRELOAD  equ     $00D2           ; the delay timebase: ONE millisecond.
                                        ;
                                        ; This was $01D2, which is the stock's
                                        ; value for TWO, so every delay in the
                                        ; instrument ran about twice as long
                                        ; as its call site said - the settling
                                        ; waits either side of an output
                                        ; change, the error message hold, and
                                        ; every paged image's use of ABI slot
                                        ; 26.
                                        ;
                                        ; The stock settles it. timer3_busy_delay
                                        ; ($D63D) computes `(argument << 8) +
                                        ; $00D2` and loads that into
                                        ; ptm_timer3, and delay_ms ($D670)
                                        ; subtracts one from its count before
                                        ; splitting it - so an argument of
                                        ; zero, one unit of delay, loads
                                        ; exactly $00D2. Same chip, same
                                        ; control registers: ptm_timer_init
                                        ; writes $01,$01,$02,$00,$27, which is
                                        ; byte for byte what ptm_init writes
                                        ; below.
                                        ;
                                        ; The factor of two rests on that
                                        ; instruction stream, not on the data
                                        ; sheet: firmware/datasheets/ holds the
                                        ; MC6840 as an image-only scan, and the
                                        ; reading rules forbid OCR. That $01D2
                                        ; is strictly longer than the stock's
                                        ; millisecond needs no model at all.

; ---------------------------------------------------------------------------
; ptm_init - program the timer module from cold
;
;   entry: nothing
;   exit:  all three counters preloaded, CR1 and CR3 configured, shadows in
;          step with the hardware
;   uses:  A, B, X
;
; Called once, from the power-on path, before interrupts are enabled. The
; order matters and is not arbitrary:
;
;   1. preload the counters while everything is still in reset, so no timer
;      counts from a value nobody chose
;   2. write CR1 with RESET_ALL to hold them
;   3. select CR1 through CR2, configure it
;   4. select CR3 through CR2, configure it
;
; Selecting a control register is done by writing CR2, which is why CR2's
; shadow is touched twice here.
; ---------------------------------------------------------------------------
ptm_init
                ; --- counters, while held in reset -------------------------
                ; The stock firmware also kept a RAM copy of each preload, at
                ; $2424, $2426 and $2428. Those are dropped here: a shadow
                ; exists so software can read back a write-only register, and
                ; these three values are compile-time constants that never
                ; change. The compiler shadowed them because it stored what
                ; it was about to write; a person writes the constant twice
                ; or, as here, once into D and then out. Six bytes of RAM and
                ; nine of ROM, and three fewer locations in the RAM map.
                ldd     #PTM_T1_PRELOAD
                std     >ptm_timer1
                ldd     #PTM_T2_PRELOAD
                std     >ptm_timer2
                ldd     #PTM_T3_PRELOAD
                std     >ptm_timer3

                ; --- hold all three in reset ------------------------------
                lda     #PTM_RESET_ALL
                sta     >ptm_status             ; CR2: select CR1, and reset
                sta     >ptm_cr

                ; --- CR1: the periodic tick -------------------------------
                ; Continuous mode, clocked from the system clock, and its
                ; interrupt-enable bit LEFT CLEAR: the flag still sets when
                ; the counter expires, and the foreground reads it. Setting
                ; the enable bit would assert IRQ, which this firmware masks
                ; and does not service, so the flag would be all that
                ; happened anyway - with an interrupt line held low for ever
                ; as well.
                lda     #PTM_INTERNAL
                sta     >ptm_cr1_shadow
                sta     >ptm_cr

                ; --- select CR3 by clearing bit 0 of CR2 ------------------
                clra
                sta     >ptm_cr2_shadow
                sta     >ptm_status

                ; --- CR3: the delay timebase ------------------------------
                ; $27: the Enable clock divided by eight, counted as two
                ; 8-bit halves, in single-shot mode - a write to the latches
                ; starts it and it runs down once. That is exactly what a
                ; polled delay wants, and it is the byte the stock firmware
                ; writes here.
                lda     #PTM_T3_PRESCALE|PTM_INTERNAL|PTM_DUAL_8BIT|PTM_MODE_SINGLE
                sta     >ptm_cr3_shadow
                sta     >ptm_cr
                rts

; ===========================================================================
; THE SEQUENCE TIMEBASE - MC6840 TIMER 2
;
; WHAT ONE COUNT IS WORTH, established by RUNNING the stock firmware rather
; than by reading it. The Digital Sequence screen has a Period field; its
; value lives at $3C9E, and commit_period_entry ($4D5E) and
; step_period_by_increment ($4F95) both write $3C9E MINUS ONE into ptm_timer2
; ($1004). So the period is (N+1) counts, which is the data sheet's 16-bit
; formula, and the field's value IS the count.
;
; The stock's own display_period ($4864) was then called on a booted
; instrument in the emulator, with the page mapped and $3C9E set by hand:
;
;       $3C9E = 10       renders    .10 ms
;       $3C9E = 100      renders   1.00 ms
;       $3C9E = 1000     renders  10.00 ms
;       $3C9E = 12345    renders 123.45 ms
;
; So one count is 0.01 ms - ten microseconds - and the field carries hundredths
; of a millisecond.
;
; THAT NUMBER WAS NEARLY WRONG BY A FACTOR OF TEN, and the way it was nearly
; wrong is worth keeping. Page 2's screen template contains the text
; " Period   1.0  ms ", and $3C9E is initialised to 10 at mode entry. Reading
; those two together gives "10 counts renders as 1.0 ms", one count = 0.1 ms,
; and every sequence in this instrument running ten times too slow. The
; template is STATIC LABEL TEXT and not the rendered value; only executing the
; renderer distinguishes them, and executing it is what the rule about running
; the tool rather than reasoning about it is for.
;
; This does not claim a frequency for the C2 input. It does not need to: the
; claim is that N counts take N x 10 us, which is what the instrument's own
; firmware prints for the periods it produces.
; ===========================================================================

; ---------------------------------------------------------------------------
; seq_timer_start - start the sequence timebase at a given period
;
;   entry: D = the period in counts of ten microseconds, 1 to 65535
;   uses:  A, B
;
; The order is the stock's start_sequence_timer ($6BD0), and every step of it
; is needed:
;
;   1. the latches get N-1, because the counter times out after N+1 counts
;   2. CR2 is set to select CR1 at the shared address
;   3. CR1's reset bit is pulsed, set then clear, which is the Counter
;      Initialization that loads the latches into the counter - a write to the
;      latches does NOT do it in this mode, see PTM_MODE_CONTIN above
;   4. CR2 gets $D1, which enables timer 2 and its interrupt
;
; The pulse goes through a REGISTER, not through ptm_cr1_shadow, so the
; shadow still describes CR1 afterwards. The stock uses a stack local for the
; same reason.
; ---------------------------------------------------------------------------
seq_timer_start
                subd    #$0001                  ; the counter times out after
                std     >ptm_timer2             ; N+1 counts

                lda     #PTM_CR2_SELECT         ; the shared address reaches
                sta     >ptm_cr2_shadow         ; CR1 while this happens
                sta     >ptm_status

                lda     >ptm_cr1_shadow         ; pulse the internal reset:
                ora     #PTM_RESET_ALL          ; this is what loads the
                sta     >ptm_cr                 ; counter from the latches
                lda     >ptm_cr1_shadow
                anda    #~PTM_RESET_ALL
                sta     >ptm_cr

                lda     #PTM_SEQ_RUN            ; and now it counts, and
                sta     >ptm_cr2_shadow         ; interrupts when it times out
                sta     >ptm_status
                rts

; ---------------------------------------------------------------------------
; seq_timer_period - change the period of a RUNNING sequence
;
;   entry: D = the new period in counts of ten microseconds
;   uses:  A, B
;
; A store and nothing else. In this operating mode a write to the latches does
; not reinitialise the counter, so the new period takes effect at the next
; time-out rather than truncating the interval already in progress. That is
; not a limitation being worked around - it is the behaviour the stock relies
; on to let an operator retune a sequence while it plays.
; ---------------------------------------------------------------------------
seq_timer_period
                subd    #$0001
                std     >ptm_timer2
                rts

; ---------------------------------------------------------------------------
; seq_timer_stop - stop the sequence timebase
;
;   uses:  A
;
; One byte, differing from the running one only in bit 6, the interrupt
; enable - which is exactly how the stock's seq_timer_stop ($6C22) and
; ptm_stop_sequence_clock ($53E5) stop theirs.
;
; The counter keeps counting; only the interrupt stops. That is the stock's
; behaviour and it is harmless, because nothing reads timer 2 except the
; handler that is no longer being entered.
; ---------------------------------------------------------------------------
seq_timer_stop
                lda     #PTM_SEQ_STOP
                sta     >ptm_cr2_shadow
                sta     >ptm_status
                rts

; ---------------------------------------------------------------------------
; ptm_cr2_change - change bits of CR2 in a way an interrupt cannot undo
;
;   entry: A = the bits to SET, B = the bits to KEEP (an AND mask)
;   exit:  CR2 and its shadow both hold the new value
;   uses:  A, B
;
; CR2 IS READ-MODIFY-WRITTEN FROM BOTH SIDES. The register is write-only, so
; ptm_cr2_shadow is the only readable copy and every change is a read, a
; modify and two writes. NMI cannot be masked, and two routines the interrupt
; reaches write that same pair: nmi_silence (boot.s), which clears the
; interrupt enables on any source that is not timer 2, and seq_timer_stop
; (below), reached from every player's end-of-run through tick_remove.
;
; So a foreground change could be preempted between its read and its write and
; then put the OLD byte back. PTM_SEQ_RUN carries PTM_IRQ_ENABLE, so the byte
; put back re-enables timer 2's interrupt after the abort path or tick_remove
; has just disabled it - with the player already taken out by then. When this
; was written the instrument was left taking an NMI at the last period for
; ever, doing nothing, until power-off; nmi_tick_idle would now silence it at
; the next time-out, but the shadow and the chip would still disagree.
;
; THE ANSWER IS TO NOTICE AND REDO IT, because an atomic read-modify-write
; against NMI does not exist on this part. The value written is compared with
; the shadow immediately afterwards; if an interrupt has been through, they
; differ and the whole change is made again from the shadow as it now stands.
; Each retry reads fresh state, so this converges, and it cannot leave the
; shadow disagreeing with the chip - which is the state that is unrecoverable,
; because nothing can read the chip back.
; ---------------------------------------------------------------------------
ptm_cr2_change
                pshs    a,b                     ; A at 0,s, B at 1,s
ptm_cr2_retry
                lda     >ptm_cr2_shadow
                anda    1,s                     ; the bits to keep
                ora     ,s                      ; and the bits to set
                sta     >ptm_cr2_shadow         ; the shadow first, so an
                sta     >ptm_status             ; interrupt reading it sees
                                                ; what the chip is about to
                                                ; hold
                cmpa    >ptm_cr2_shadow         ; still ours?
                bne     ptm_cr2_retry           ; no: an interrupt wrote its
                puls    a,b,pc                  ; own value, so do it again

; ---------------------------------------------------------------------------
; delay_ticks - spin until timer 3 has counted down once
;
;   entry: D = the value to load into timer 3
;   exit:  the timer has expired
;   uses:  A, B
;
; The 6840 sets its status flag when the counter reaches zero. Writing the
; counter restarts it, so the sequence is: load, then watch.
;
; This spins. It does not sleep and it does not service anything, because
; every caller is a settling delay where the instrument must do nothing at
; all - and because a delay that ran the foreground would let a key press
; change the very state the caller is waiting to settle.
; ---------------------------------------------------------------------------
delay_ticks
                std     >ptm_timer3             ; load and start
delay_ticks_wait
                lda     >ptm_status
                anda    #PTM_T3_FLAG
                beq     delay_ticks_wait                   ; not expired yet
                rts

; ---------------------------------------------------------------------------
; delay_ms - wait for a number of milliseconds
;
;   entry: D = milliseconds, 0 to 65535
;   exit:  at least that long has passed
;   uses:  A, B, X
;
; Timer 3 is preloaded so that one full count is one millisecond, so this is
; simply that many counts. A count of zero returns at once rather than
; waiting 65536 times, which is what a naive decrement-and-test would do.
; ---------------------------------------------------------------------------
delay_ms
                cmpd    #$0000
                beq     delay_ms_done                   ; nothing asked for
                tfr     d,x                     ; X is the loop count
delay_ms_tick
                ldd     #PTM_T3_PRELOAD
                bsr     delay_ticks
                leax    -1,x
                bne     delay_ms_tick
delay_ms_done
                rts

; ---------------------------------------------------------------------------
; ptm_drain - clear every pending MC6840 timer flag
;
;   entry: nothing
;   exit:  no timer flag remains set in the status register
;   uses:  A, B, X
;
; The MC6840 clears a timer's interrupt flag on a two-step sequence: read the
; status register, then read that timer's counter. Reading the status alone
; arms the clear and does not complete it, which is why a handler that only
; peeks at the status sees the same interrupt again immediately.
;
; It loops rather than sweeping once. A timer can expire between the status
; read and the counter read, and a single sweep would leave that flag set
; while the caller believed the module was quiet - the exact fault that makes
; an instrument hang after minutes rather than at once. The loop ends when a
; whole pass finds no flag at all.
;
; The bound is real, not a hope: with the interrupt-enable bits already
; cleared by the caller, a timer can set its flag at most once more per pass,
; and the passes are far shorter than the shortest counter reload.
;
; Modelled on the stock routine at $F05E, which the stock NMI handler calls
; for the same purpose and which tests the same three status bits.
; ---------------------------------------------------------------------------
PTM_ANY_FLAG    equ     PTM_T1_FLAG|PTM_T2_FLAG|PTM_T3_FLAG

ptm_drain
                ldb     >ptm_status             ; one read serves all three
                bitb    #PTM_ANY_FLAG           ; tests below
                beq     ptm_drain_done          ; a clean pass: finished

                bitb    #PTM_T1_FLAG
                beq     ptm_drain_t2
                ldx     >ptm_timer1             ; the counter read completes
ptm_drain_t2                                    ; the clear
                bitb    #PTM_T2_FLAG
                beq     ptm_drain_t3
                ldx     >ptm_timer2
ptm_drain_t3
                bitb    #PTM_T3_FLAG
                beq     ptm_drain
                ldx     >ptm_timer3
                bra     ptm_drain               ; sweep again until quiet
ptm_drain_done
                rts
