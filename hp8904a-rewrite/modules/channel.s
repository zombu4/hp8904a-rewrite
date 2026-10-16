; ===========================================================================
; channel.s - the four output channels
;
; The instrument has up to four output boards. How many are FITTED is not a
; setting and not an option bit: the firmware finds out by probing, and this
; is the only thing that decides which channels the front panel offers.
;
; THE PROBE, which is hardware and not guesswork. For each channel in turn:
; set bit 7 of that channel's output latch, strobe $0800, and read int_latch.
; A channel whose bit reads back SET is absent, and the count stops there.
; The latches are $100 apart - $0C00, $0D00, $0E00, $0F00 - which is why they
; are addressed by arithmetic rather than as four named ports.
;
; The probe leaves bit 7 set on every latch it touched, so it clears them all
; afterwards. Leaving one set holds a channel in whatever state that bit
; means to the output board, which is not a state the operator asked for.
; ===========================================================================

; CHANNEL_MAX is in common/hardware.inc: the paged screens need it too, and
; how many output boards the instrument can hold is a fact about the machine
; rather than about this module.
CHANNEL_LATCH   equ     $0C00           ; channel 0; +$100 per channel
CHANNEL_PROBE   equ     LATCH_PROBE     ; bit 7, named in
                                        ; common/hardware.inc with the
                                        ; rest of the latch

; ---------------------------------------------------------------------------
; channel_latch_address - where a channel's latch lives
;
;   entry: B = the channel, 0 to 3
;   exit:  X = its latch address
;   uses:  A, B, X
; ---------------------------------------------------------------------------
channel_latch_address
                ldx     #CHANNEL_LATCH
                tstb
                beq     channel_latch_done
                pshs    b
channel_latch_step
                leax    $100,x
                decb
                bne     channel_latch_step
                puls    b
channel_latch_done
                rts

; ---------------------------------------------------------------------------
; channel_probe - how many output boards are fitted
;
;   exit:  B = the count, 0 to 4, and installed_channels holds it
;   uses:  A, B, X
;
; Stops at the first absent channel rather than counting all four. The boards
; are fitted in order, so a gap would mean a fault rather than a
; configuration - and counting past a gap would offer the operator a channel
; whose board is not there.
; ---------------------------------------------------------------------------
channel_probe
                clr     >installed_channels
                ; THE MASK IS READY BEFORE THE STROBE, AND THE READ FOLLOWS IT
                ; AT ONCE - count_installed_channels ($B852) exactly. The stock
                ; stores #$01 at 3,s before its loop ($B85E), strobes $0800 at
                ; $B87F, and reads on the very next instruction: `ldb 3,s /
                ; andb >int_latch` at $B882. Each fitted channel ASLs the mask
                ; for the next ($B893).
                ;
                ; THIS BUILT THE MASK AFTER THE STROBE, in a shift loop, so
                ; int_latch was read about seven instructions after the strobe
                ; for channel 0 and sixteen for channel 3. Whether the hardware
                ; holds the probe line that long is not established - there is
                ; no A2 schematic (service manual page 8-23) - and the emulator
                ; cannot tell: its probe_armed answers the next int_latch read
                ; however late it comes. So the instrument's timing is the one
                ; ported, rather than a delay nobody measured. It is NOT the
                ; cause of the architect's zero count: this loop is unchanged
                ; since before the burn he says worked.
                lda     #$01                    ; channel 0's int_latch bit
                pshs    a                       ; 0,s the mask, as the stock's
                clrb                            ; 3,s
channel_probe_next
                cmpb    #CHANNEL_MAX
                bhs     channel_probe_done

                pshs    b                       ; 0,s the channel, 1,s the mask
                ldb     #CHANNEL_PROBE          ; assert the probe line through
                inc     >dds_lock               ; the shadow. THE STORE AND THE
                                                ; CALL ARE ONE OPERATION. An
                                                ; NMI landing between them
                                                ; would leave this writing the
                                                ; sequence player's value into
                                                ; a channel latch; see
                                                ; channel_latch_rmw.
                stb     >latch_bits             ; range and output bits of
                lda     #CHANNEL_PROBE          ; this channel survive it
                ldb     ,s                      ; the channel again
                lbsr    channel_latch_rmw       ; A and B come back unchanged
                dec     >dds_lock
                clr     >output_latch_strobe    ; $B87F; the value never matters
                lda     1,s                     ; $B880 LDB 3,s: the mask
                anda    >int_latch              ; $B882: the NEXT instruction
                puls    b                       ; PULS leaves the flags alone
                bne     channel_probe_done      ; set means absent: stop

                inc     >installed_channels
                asl     ,s                      ; $B893: the next channel's bit
                incb
                bra     channel_probe_next

channel_probe_done
                leas    1,s                     ; the mask, which both ways out
                                                ; of the loop leave alone on
                                                ; the stack
                bsr     channel_probe_clear     ; put every probe line back
                ; THE COUNT IS LEFT TRUTHFUL, INCLUDING ZERO, and the
                ; architect's channel-1 floor is applied in channel_valid
                ; instead. It was floored here first and that HID A REAL FAULT:
                ; hp8904a-rewrite/tests/test_output_reset.py holds that an
                ; instrument which probes no output board at all raises error
                ; $0A, and with the count forced to one it never did. He needs
                ; output 1 usable whatever the probe returned AND he needs to
                ; be told when nothing was found; flooring the validation
                ; rather than the count gives both, and leaves the
                ; identification banner's Option 002 field reporting what is
                ; actually fitted.
                ldb     >installed_channels
                rts

; ---------------------------------------------------------------------------
; ---------------------------------------------------------------------------
; channel_latch_redrive - write every channel's latch back from its shadow
;
;   uses:  A, B, X
;
; THE INSTRUMENT DOES THIS ON A RECALL, and this firmware did not. Three mode
; entries carry the same loop - enter_channel_config_mode ($528F),
; sequence_mode_init ($5380) and digital_sequence_mode_setup ($7187) - each
; guarded by `CMPX #$0001 / LBNE` past it, so it runs when the mode argument
; is 1, the recall. The loop reads the SHADOW byte at $24F0+channel and hands
; it straight back to port_latch_rmw ($DBA1) with mask $00FF, the whole byte,
; then repaints the output lamps through update_output_leds ($B72F).
;
; WHAT IT CHANGES ON A HEALTHY MACHINE: nothing. port_latch_rmw maintains the
; shadow, so the byte written is the byte the latch was last given, and no bit
; moves. It is a re-drive, not a state change - and that is the point of
; porting it: the instrument puts the byte on the bus again at that moment,
; and a latch that did not take the first write takes this one.
;
; The lamps are NOT repainted here. register_apply has already written each
; channel's relay bits from the recalled record and the front panel follows
; that; repainting again would be a second write of the same state.
; ---------------------------------------------------------------------------
channel_latch_redrive
                clrb
channel_latch_redrive_next
                cmpb    #CHANNEL_MAX
                bhs     channel_latch_redrive_done
                ldx     #latch_shadow
                lda     b,x                     ; the byte the latch holds
                inc     >dds_lock               ; THE STORE AND THE CALL ARE
                                                ; ONE OPERATION, as everywhere
                                                ; else that writes a latch
                sta     >latch_bits
                lda     #$FF                    ; every bit, which is the
                pshs    b                       ; stock's mask $00FF
                lbsr    channel_latch_rmw
                dec     >dds_lock
                puls    b
                incb
                bra     channel_latch_redrive_next
channel_latch_redrive_done
                rts

; ---------------------------------------------------------------------------
; channel_probe_clear - drop the probe line on every channel
;
;   uses:  A, B, X
;
; Called by the probe on the way out, and worth a routine of its own because
; forgetting it leaves a board held in a state nobody chose.
; ---------------------------------------------------------------------------
channel_probe_clear
                clrb
channel_probe_clear_next
                cmpb    #CHANNEL_MAX
                bhs     channel_probe_clear_done
                inc     >dds_lock               ; THE STORE AND THE CALL
                                                ; ARE ONE OPERATION. An
                                                ; NMI landing between
                                                ; them would leave this
                                                ; writing the sequence
                                                ; player's value into a
                                                ; channel latch; see
                                                ; channel_latch_rmw.
                clr     >latch_bits             ; drop the probe line and
                lda     #CHANNEL_PROBE          ; nothing else: the range
                pshs    b                       ; field is not ours to clear
                lbsr    channel_latch_rmw
                dec     >dds_lock
                puls    b
                incb
                bra     channel_probe_clear_next
channel_probe_clear_done
                ; AND THE STROBE, once, after every probe line is down. This
                ; was missing entirely: $0800 was written only while the probe
                ; bit was being ASSERTED, inside channel_probe, and never
                ; after it was dropped.
                ;
                ; The stock's channel_latches_bit7_clear ($B646) - the routine
                ; arm [7] of the $8F2A dispatch calls - ends its own
                ; four-channel loop the same way, with CLR >output_latch_strobe
                ; at $B675. What writing $0800 does is clearest in the stock's
                ; count_installed_channels ($B852): it stages a latch through
                ; port_latch_rmw, writes $0800, and only then reads int_latch
                ; back. So the strobe is what transfers what the latch writes
                ; have staged, and dropping the probe lines without one leaves
                ; the drop staged and not transferred.
                ;
                ; The value written never matters; the write does.
                clr     >output_latch_strobe
                rts


; ---------------------------------------------------------------------------
; channel_select - point the DDS at one channel
;
;   entry: B = the channel
;   exit:  carry SET if the channel is not fitted, and nothing was written
;   uses:  A, B, X, Y
;
; Refuses rather than writing. Programming a channel that is not there sends
; the value to whichever board answers, and on an instrument where the boards
; are the output that is worse than doing nothing.
; ---------------------------------------------------------------------------
channel_select
                pshs    b
                lbsr    channel_valid
                bcs     channel_select_absent
                puls    b
                stb     >current_channel
                andcc   #~CC_CARRY
                rts
channel_select_absent
                puls    b
                ldb     #ERR_NO_SUCH_CHANNEL
                lbsr    error_raise
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; chan_state_sync - make a channel's record say what its latch is doing
;
;   entry: B = the channel, 0 to 3
;   exit:  that channel's CHAN_STATE byte matches its latch shadow
;   uses:  A, X
;
; CHAN_STATE bit 0 is "the output is on" and bit 1 is "the output is
; floating". Both of the latch bits they mirror are ACTIVE LOW - hardware.inc
; carries the evidence: set_output_enable ($B79C) writes $04 to switch a
; channel OFF, and output_latch_bit1_set ($B6EF) writes $02 when the
; requested float state is ZERO. So the record is the complement of the
; latch, in both bits.
;
; WHY THIS EXISTS. Nothing in the tree ever set CHAN_STATE bit 0. It was
; cleared once at power-on and read in exactly one place - ampl_unblank's
; gate, which releases the mute only if the channel was on. With the bit
; never set, that branch was never taken, so ampl_blank muted the channel and
; ampl_unblank left it muted: SETTING AN AMPLITUDE SWITCHED THE OUTPUT OFF
; AND NOTHING TURNED IT BACK ON. Both callers of the pair - ampl_set, and
; filter_apply in screens_main.s - did it.
;
; The stock has the same two-place design and works because set_output_enable
; writes $23B3+channel, which its release path reads back. The rewrite kept
; the read and lost the write. This is the write, in one routine rather than
; at each site, so the record and the relay cannot drift apart.
;
; It is deliberately NOT called from ampl_blank or ampl_unblank. Blanking is
; temporary and the record holds the operator's INTENT; if blanking rewrote
; it, unblanking would have nothing to restore, which is the same bug one
; level down.
; ---------------------------------------------------------------------------
chan_state_sync
                pshs    b                       ; the channel
                ldx     #latch_shadow
                andb    #$03
                abx
                lda     ,x                      ; the latch as it stands
                coma                            ; both bits are active low
                tfr     a,b
                andb    #LATCH_FLOAT            ; latch bit 1 clear: floating
                lsra
                lsra
                anda    #$01                    ; latch bit 2 clear: on
                pshs    b
                ora     ,s+                     ; the record's state byte
                pshs    a
                ldb     1,s                     ; the channel again
                andb    #$03                    ; AND MASKED HERE TOO. The
                                                ; latch index eighteen lines
                                                ; above is masked and this was
                                                ; not - the same asymmetry
                                                ; inside one routine. n = 41
                                                ; puts X at $3FF4 and the
                                                ; store below reaches $3FF7,
                                                ; which is revision_signature.
                lda     #CHAN_RECORD
                mul
                ldx     #channel_records
                leax    d,x
                puls    a
                sta     CHAN_STATE,x
                puls    b
                rts

; ---------------------------------------------------------------------------
; channel_latch_rmw - change some bits of a channel latch, leaving the rest
;
;   entry: A = the mask of bits this call owns
;          B = the channel, 0 to 3
;          latch_bits = the new value of those bits, already in position
;   exit:  the latch and its shadow both hold the result
;   uses:  A, B, X
;
; THE LATCHES ARE WRITE-ONLY. There is no way to read $0C00-$0F00 back, so
; "read, modify, write" here means "read the SHADOW, modify, write both". If
; the shadow is ever wrong the hardware is wrong with it and nothing can
; detect the difference - which is why every single change to these latches
; goes through this one routine, and why nothing else in this firmware may
; store to a latch address directly.
;
; That rule was not followed at first. channel_probe wrote bit 7 straight to
; the latch to strobe the presence line, which cleared the four range bits of
; whichever channel it was probing: the output level would jump by up to
; fifteen octaves, at power-on, with nothing on the screen to say so. It now
; goes through here like everything else.
;
; Interrupts are masked across the shadow update and the latch write. A
; handler that changed a different bit of the same latch in between would
; write the pre-change shadow and undo this call, and the shadow would then
; disagree with the hardware permanently.
; ---------------------------------------------------------------------------
channel_latch_rmw
                inc     >dds_lock               ; see nmi_handler. This masks
                                                ; the maskable interrupts
                                                ; below, which does nothing to
                                                ; NMI - and the sequence
                                                ; player reaches this routine
                                                ; too. Without the lock, a
                                                ; player firing between the
                                                ; shadow read and the latch
                                                ; write would have its own
                                                ; change undone and the shadow
                                                ; would disagree with the
                                                ; hardware permanently, which
                                                ; is exactly the failure this
                                                ; routine's own header warns
                                                ; about.
                pshs    a,b                     ; NOT "pshs cc,a,b":
                DISABLE_INTERRUPTS              ; DISABLE_INTERRUPTS pushes
                                                ; CC itself. Saving it here
                                                ; too left a byte on the stack
                                                ; and this routine's RTS
                                                ; returned into I/O space -
                                                ; found by running the
                                                ; firmware on the emulator,
                                                ; not by reading it.

                ldx     #latch_shadow
                andb    #$03                    ; a wild channel number must
                abx                             ; not index outside the four
                                                ; shadow bytes

                lda     ,x                      ; the shadow as it stands
                pshs    a
                lda     2,s                     ; the caller's mask: shadow
                                                ; at 0,s, CC at 1,s, the mask
                                                ; at 2,s, the channel at 3,s
                coma                            ; keep everything the caller
                anda    ,s+                     ; does not own
                ora     >latch_bits             ; and add what it does
                sta     ,x                      ; the shadow first, so an
                                                ; interrupt that reads it
                                                ; sees what the hardware is
                                                ; about to hold
                pshs    a
                ldb     3,s                     ; the channel again
                andb    #$03                    ; AND MASKED AGAIN. The shadow
                                                ; index above was masked and
                                                ; this was not, so the comment
                                                ; claiming a wild channel
                                                ; cannot index outside the
                                                ; four was half true: B=4
                                                ; would have written $1000,
                                                ; the MC6840 control register.
                lbsr    channel_latch_address   ; X = $0C00 + channel*$100
                puls    a
                sta     ,x                      ; and the hardware

                RESTORE_INTERRUPTS              ; the CC the macro pushed
                puls    a,b
                dec     >dds_lock
                rts

; ---------------------------------------------------------------------------
; channel_latch_init - put every latch into its quiescent state
;
;   exit:  all four latches and their shadows hold LATCH_QUIESCENT
;   uses:  A, B, X
;
; Called from the power-on path before anything else touches a latch. The
; shadow has to start out agreeing with the hardware, and the only way to
; make that true is to write both.
;
; The quiescent value switches every output OFF. It was zero in every bit,
; which with bit 2 active low is every output ON - so the instrument came up
; driving its sockets before a single screen had been painted.
; ---------------------------------------------------------------------------
; EVERY OUTPUT OFF, and that is what $00 did NOT do. Bit 2 is the output
; relay and it is ACTIVE LOW, so all-zeros is every output SWITCHED ON - an
; instrument that came up driving whatever the last setup left in its
; registers into whatever is connected.
;
; The quiescent value asserts bit 2 AND bit 1 on every channel: outputs off,
; and NOT floating - both of those relays are active low, so both bits have to
; be set to reach the state the words describe. Bit 0 stays clear, which is
; the sharp-cutoff filter, and the manual says that is the contact normally
; closed on power-up anyway. The range field is all zeros, which is all four
; attenuator pads switched IN - maximum attenuation, not "no attenuation" as
; this said - and it does not matter either way while the output relay is
; open, but the two readings are not interchangeable and one of them is
; wrong.
LATCH_QUIESCENT equ     LATCH_OUTPUT|LATCH_FLOAT

channel_latch_init
                clrb
channel_latch_init_next
                lda     #$FF                    ; this call owns every bit
                pshs    b
                ; THE VALUE THE PRESET ALREADY PUT THERE, not this firmware's
                ; own quiescent $06. This job is to make the shadow agree with
                ; the hardware, and by the time it runs channel_latches_preset
                ; has driven all four latches to $84 - so writing $06 here
                ; MOVED THE FLOAT RELAY, and moved it back 7,550 instructions
                ; later when channel_reset_all wrote $00. Measured: $84->$06 at
                ; ~582,350 and $06->$00 at ~590,000, the same too-fast flap the
                ; preset was added to cure, in miniature.
                ;
                ; The stock never touches bit 1 during power-on at all: its
                ; latches go $80, $00, $84, $80, $00 and the float bit is
                ; clear throughout. This is the fourth of those, and it is
                ; $80 - the output relay released, the probe enable left
                ; standing - which is the instrument's own two-phase shape:
                ; off at the probe, released after the self-test.
                ;
                ; IT WAS LATCH_OUTPUT, $04, UNTIL 2026-09-20, which is the
                ; same two bits the other way round: the relay left closed
                ; and the flip-flop clock dropped first. See LATCH_PRESET in
                ; remote_tables.s for why the order is not a free choice.
                ldb     #LATCH_PRESET
                inc     >dds_lock               ; THE STORE AND THE CALL
                                                ; ARE ONE OPERATION. An
                                                ; NMI landing between
                                                ; them would leave this
                                                ; writing the sequence
                                                ; player's value into a
                                                ; channel latch; see
                                                ; channel_latch_rmw.
                stb     >latch_bits
                puls    b
                lbsr    channel_latch_rmw
                dec     >dds_lock
                incb
                cmpb    #CHANNEL_MAX
                blo     channel_latch_init_next
                rts


; ---------------------------------------------------------------------------
; channel_records_init - put the four channel records into a known state
;
;   uses:  A, B, X, Y
;
; Called from the power-on path. Battery-backed RAM keeps whatever was last
; there, and scratch is not battery-backed at all, so without this the screen
; opens showing whatever the RAM happened to hold - which on a cold machine
; is noise. It showed a frequency of 943718.4 Hz on the first boot that was
; ever looked at, from a record whose first byte was $90.
;
; THE DEFAULTS, and why each:
;
;   frequency 1 kHz, phase zero. The frequency was zero here, reasoned out
;   as "a legitimate setting and the quietest one" - which is exactly the
;   kind of default rule 7 forbids inventing. The stock's is 1 kHz, read off
;   the stock itself: booted in the emulator with only its RAM signature
;   seeded, all four of its records at $24F5 hold $002710 = 10000 at
;   record+0, and 10000 x 0.1 Hz is 1000.0 Hz. emulator/tests/
;   test_summing_new.py caught it - it compares the tuning words a
;   destination change sends, and the stock staged 10000 into register $08
;   where this staged nothing.
;
;   amplitude zero, so nothing appears at a socket because the instrument was
;   switched on. An operator sets a level deliberately.
;
;   waveform Sine, because every waveform has to be something and Sine is the
;   only one whose harmonic content cannot surprise whatever is connected.
;
;   destination Out1 for channel 0, Out2 for channel 1, and so on - each
;   channel to its own socket, which is what the sockets are labelled and
;   what an operator expects before they have changed anything.
;
;   output OFF. The output enable is a separate bit and it starts clear, so
;   the defaults above describe a channel that is configured and silent.
; ---------------------------------------------------------------------------
FREQ_RESET_HI   equ     $0027           ; 10000 = $002710, split because
FREQ_RESET_LO   equ     $10             ; the frequency is 24 bits and one
                                        ; assembler here takes no expression
                                        ; in an immediate

; THE STOCK'S TWO DEFAULT RECORDS, read out of firmware/a2u12.bin at the
; addresses init_channel_blocks ($C4F0) copies from with mem_copy ($C285):
;
;   $ED89 configured  00 27 10 00 02 00 03 E8 00 02 00 00 8C 00 07 00 00 01
;                     00 07 2B 00 00 00 00 00 03 00 0A 00 12 00 01 00 10
;   $EDAC unused      the same, with the level 00 00 00 and its unit 00 0D
;
; field by field, at the offsets the stock's own 35-byte record uses:
;   +$00 frequency 10000 tenths of a hertz   +$03 its unit, 2 (' Hz')
;   +$05 its increment, 1000 tenths          +$08 that increment's unit, 2
;   +$0A level 140 microvolts                +$0D its unit, 7 (microvolts)
;   +$0F its increment, 1 microvolt          +$12 that increment's unit, 7
;   +$14 the level's sign, '+'               +$15 phase 0
;   +$19 its unit, 3 (deg)                   +$1B its increment, 10 tenths
;   +$1D the same increment in thousandths of a radian, 18
;   +$1F the waveform, 1 (Sine)              +$21 the destination, $10 (Off),
;                                            which init_channel_blocks then
;                                            overwrites with $000C+n for a
;                                            configured channel
CHAN_AMPL_RESET      equ $8C    ; 140 microvolts, $ED89+$0C
CHAN_INCR_FREQ_RESET equ 1000   ; $ED89+$05, tenths of a hertz
CHAN_INCR_AMPL_RESET equ 1      ; $ED89+$0F, microvolts
CHAN_INCR_PHASE_RESET equ 10    ; $ED89+$1B, tenths of a degree
CHAN_INCR_RAD_RESET  equ 18     ; $ED89+$1D, thousandths of a radian

channel_records_init
                clrb                            ; B = the channel
channel_records_next
                cmpb    #CHANNEL_MAX
                lbhs    channel_records_done    ; long: the per-channel steps

                pshs    b
                lda     #CHAN_RECORD
                mul                             ; D = channel * 12
                ldx     #channel_records
                leax    d,x                     ; X = this channel's record

                ldd     #FREQ_RESET_HI          ; the stock's 1 kHz: $002710
                std     ,x                      ; is 10000 at 0.1 Hz, and the
                lda     #FREQ_RESET_LO          ; record holds it at +0, the
                sta     CHAN_FREQ+2,x           ; same offset CHAN_FREQ names

                ; THE LEVEL IS 140 MICROVOLTS, not zero. init_channel_blocks
                ; ($C4F0) copies a 35-byte default record over each channel
                ; with mem_copy ($C285) - $ED89 for a CONFIGURED channel and
                ; $EDAC for one the configuration byte $23B2 does not cover -
                ; and $ED89 reads
                ;
                ;   00 27 10  00 02  00 03 E8  00 02  00 00 8C  00 07 ...
                ;
                ; which is 10000 tenths of a hertz at +0 with unit 2 (' Hz') at
                ; +3, an increment of 1000 tenths at +5 with the same unit at
                ; +8, and 140 MICROVOLTS at +$0A with unit 7 at +$0D. Driven on
                ; the stock with a cleared battery: channel A comes up reading
                ; 'ch A: FREQ   1000.0  Hz AMPTD    140 uV' and the model puts
                ; 140.03 microvolts on the socket. This firmware came up at
                ; zero, which is a different instrument on the glass and on the
                ; output.
                ;
                ; $EDAC differs in exactly two fields - the level is 0 and its
                ; unit is $0D - so a channel past the installed count starts
                ; silent, which is what installed_channels decides below.
                clra
                clrb
                std     CHAN_PHASE,x            ; the phase is zero in both
                std     CHAN_AMPL,x             ; templates, and the level's
                sta     CHAN_AMPL+2,x           ; top two bytes are zero in
                                                ; both
                ldb     ,s                      ; the channel
                cmpb    >installed_channels     ; $23B2: the configured count
                bhs     channel_records_wave    ; past it, $EDAC's zero level
                lda     #CHAN_AMPL_RESET        ; $ED89's 140 microvolts
                sta     CHAN_AMPL+2,x
channel_records_wave

                lda     #LBL_SINE               ; $ED89 +$1F = $0001
                sta     CHAN_WAVE,x

                ; THE DESTINATION IS ITS OWN SOCKET ONLY IF THE CHANNEL IS
                ; FITTED. init_channel_blocks ($C4F0) fills a four-entry
                ; local table with $0010 at $C4F8-$C514, then walks the
                ; installed count $23B2 at $C516-$C544 and overwrites entries
                ; 0 to count-1 with $000C, $000D, $000E, $000F. Each entry is
                ; then both the choice of default record - $EDAC when it is
                ; still $0010, $ED89 otherwise, $C56A-$C57E - and the value
                ; stored into record+$21 straight after the copy. So on a
                ; two-board instrument channels C and D come up Off, and this
                ; firmware gave them Out3 and Out4.
                ;
                ; It shows on the glass as well as at the socket, and the
                ; stock's is the blank one: with the destination Off the
                ; AMPTD field's unit is UNIT_OFF, which render_value_with_
                ; units ($564E) sends to field_format_blank_units - value and
                ; label both blank. Driven side by side on a two-board
                ; instrument, channel C: the stock reads
                ; 'ch C: FREQ   1000.0  Hz AMPTD           ' with DESTN Off,
                ; and this firmware read 'AMPTD      0 V ' with DESTN Out3.
                ; That is $EDAC's other two differing fields, +$0D and +$13,
                ; both $0D where $ED89 has 7 - and this firmware does not
                ; store them, because chan_ampl_unit is DERIVED from the
                ; destination rather than kept per channel, so putting the
                ; destination right puts the unit right with it.
                ldb     ,s                      ; the channel
                cmpb    >installed_channels     ; $23B2, as at $C533
                bhs     channel_records_unfitted
                addb    #LBL_OUT1               ; $000C + n: its own socket
                bra     channel_records_dest
channel_records_unfitted
                ldb     #LBL_OFF                ; $0010, the table's fill
channel_records_dest
                stb     CHAN_DEST,x

                clr     CHAN_MOD,x

                ; AND CHAN_STATE IS NOT TOUCHED HERE, which it used to be.
                ; The byte says whether the output relay is closed and
                ; whether the line is floating, and chan_state_sync derives
                ; it FROM THE LATCH so the two cannot disagree - that is why
                ; chan_state_sync exists. Clearing it here wrote the record's
                ; opinion over the hardware's.
                ;
                ; It did no harm on the cold boot, which is where this
                ; routine used to be called from: channel_reset_all runs
                ; straight after it, puts LATCH_QUIESCENT on every latch and
                ; syncs the byte to that, so a cold instrument comes up
                ; silent either way. It did harm at a SEQUENCE MODE ENTRY,
                ; which calls this to put the records back to their defaults
                ; as init_channel_blocks ($C4F0) does - and $C4F0 does not
                ; touch the stock's output-enable byte $23B3 either. With the
                ; clear here, entering a sequence mode told the record every
                ; output was off while the latches still had them on, and the
                ; next filter change muted channel 0 and then declined to
                ; unmute it, because ampl_unblank asks this byte. Measured
                ; against the stock: its channel 0 latch reads $01 after a
                ; tone entry and this firmware's read $04 - muted.

                ; AND THE FIELDS THIS FIRMWARE KEEPS OUTSIDE THE RECORD, LAST,
                ; because each one needs X for its own array and the record's
                ; pointer is in it until here. Written between the level and the
                ; waveform, these reloads left X on chan_phase_rad and the
                ; destination, the modulation and the state bytes went into the
                ; preserved block instead of into the record - DESTN painted
                ; blank and chan_incr_rad and chan_freq_unit were overwritten.
                ;
                ; They are the rest of that template: the frequency's unit at +3 and
                ; the phase's at +$19 are per channel here, the level's at +$0D
                ; is one cell because only one AMPTD field is ever being shown,
                ; the sign at +$14 is ampl_signs, and the three increments at
                ; +5, +$0F and +$1B are one each. All of them sit above
                ; live_setting where scratch_reset does not reach, so a cold
                ; boot that did not write them left them at whatever the
                ; battery held - and a zero unit code names no unit at all.
                ldb     ,s                      ; the channel
                ldx     #chan_freq_unit
                lda     #UNIT_HZ                ; +3 = $0002
                sta     b,x
                ldx     #chan_phase_unit
                lda     #UNIT_DEG               ; +$19 = $0003
                sta     b,x
                ldx     #ampl_signs
                lda     #AMPL_SIGN_PLUS         ; +$14 = $2B
                sta     b,x
                ldx     #chan_phase_rad         ; the milliradian twin, which
                aslb                            ; agrees with a phase of zero -
                clra                            ; two bytes a channel
                sta     b,x
                leax    1,x
                sta     b,x

                ; AND THIS CHANNEL'S AMPLITUDE STEP. One per channel now, as
                ; $ED89+$0F is one per record on the instrument.
                ;
                ; B IS RELOADED because the milliradian twin above doubled it
                ; with aslb for its two bytes a channel; using it as it stands
                ; would seed channel n's step at 2n.
                ldb     ,s                      ; the channel, undoubled
                lda     #3
                mul                             ; D = channel * 3
                ldx     #incr_ampl_ch
                leax    d,x
                clr     ,x
                clr     1,x
                lda     #CHAN_INCR_AMPL_RESET   ; one microvolt
                sta     2,x

                ; AND ITS FREQUENCY STEP AND THE UNIT THAT STEP IS SHOWN IN,
                ; $ED89's +5 (1000 tenths of a hertz) and +8 ($0002, Hz) - one
                ; per record on the instrument, and one per channel here.
                ldb     ,s                      ; the channel
                lda     #3
                mul                             ; D = channel * 3
                ldx     #incr_freq_ch
                leax    d,x
                clr     ,x
                ldd     #CHAN_INCR_FREQ_RESET
                std     1,x
                ldb     ,s
                ldx     #incr_freq_unit
                lda     #UNIT_HZ
                sta     b,x

                puls    b
                incb
                lbra    channel_records_next    ; long, for the same reason
channel_records_done

                ; THE PHASE INCREMENT AND THE AMPTD FIELD'S UNIT, once rather
                ; than per channel: this firmware keeps one of each where the
                ; stock keeps them in every record. $ED89 has ten tenths of a
                ; degree at +$1B and eighteen thousandths of a radian at +$1D -
                ; which is 1.0 degree in both units, rounded as the conversion
                ; rounds - and unit 7 at +$0D. The frequency and amplitude
                ; steps are per channel, above.
                clra
                clrb
                std     >incr_phase
                stb     >incr_phase+2
                ldb     #CHAN_INCR_PHASE_RESET
                stb     >incr_phase+2
                ldd     #CHAN_INCR_RAD_RESET
                std     >chan_incr_rad
                lda     #UNIT_MICROVOLT
                sta     >chan_ampl_unit
                ; AND THE HOP SCREEN OPENS ON THE LAST SLOT, which is the
                ; last thing init_channel_blocks ($C4F0) does: lc5a9 is
                ; LDB #$0F / STB >$24F4. $24F4 is the slot the Hop Ram screens
                ; show, and $0F is slot 15 - the one the stock labels address
                ; 0. Driven side by side, keying a frequency into a slot,
                ; leaving Channel Config. by f4 and coming back: the stock
                ; stands on 'Hop Ram Adrs  0' and this firmware stood on
                ; 'Hop Ram Adrs 15'. dds_table_defaults ($E7F9) never names
                ; $24F4, so it belongs here and not with the hop table's own
                ; reset - and $C4F0 is called on its own by seq_mode_defaults
                ; at $5239 as well, which is the other place it has to happen.
                ldb     #HOP_SLOTS-1
                stb     >hop_index

                clr     >current_channel        ; the screen opens on
                rts                             ; channel 1

; ---------------------------------------------------------------------------
; channel_reset_all - every channel output back to its defined reset state
;
;   uses:  A, B, X
;
; THIS IS THE STOCK'S reset_all_channel_outputs ($80F3), read instruction by
; instruction and brought across. Nothing in this firmware did it, and the
; consequence was not small: the stock calls $80F3 from three sites, and two
; of them are the paths back to the Main Selection Level - arm 5 and arm 6 of
; the event dispatch, at $8D96 and $8DB7. So on a real 8904A, leaving a
; screen puts every channel output back to a known state, and here it did
; not: the outputs stayed wherever the screen that was just abandoned had
; left them.
;
; WHAT THE STOCK ACTUALLY WRITES, bit by bit. Its loop runs channels 0 to 3
; with a "present" flag that starts at 1 and is cleared the first time the
; channel index is not below the installed count $23B2 - the channels ascend,
; so fitted ones get 1 and the rest 0 - and then calls five routines:
;
;   output_latch_level_set ($B5EF)(ch, $0F) clamps the level to $0F, COMs it
;   at $B607, shifts left three and writes it through mask $78. $0F complements
;   to $F0, which shifted left three and masked is ZERO - so the range field
;   ends at all-zeros, every attenuator pad switched in. It then waits 6 ms.
;
;   output_latch_bit1_set ($B6EF)(ch, present) writes value 0 through mask $02
;   when present and $02 when not, so bit 1 is CLEAR on a fitted channel.
;
;   set_output_enable ($B79C)(ch, present) writes $FF to $23B3+ch and value 0
;   through mask $04 when present, $00 and value $04 when not - bit 2 CLEAR on
;   a fitted channel - then calls update_output_leds ($B72F) for that channel.
;
;   set_channel_byte_24ec ($F713)(ch, 0) stores 0 at $24EC+ch, the recorded
;   filter state, and set_output_enable_mode ($F770)(ch, 3) stores 3 at
;   $24E8+ch and drives latch bit 0 from $24EC+ch. Both of those reach bit 0,
;   and both leave it at ZERO.
;
;   channel_latches_bit7_clear ($B65F) finishes by taking the probe lines down.
;
; So a FITTED channel's latch ends at $00 and an unfitted one at $06, and
; that is the whole of it. Bits 1 and 2 are active low, so $00 means the
; output relay CLOSED and the low line FLOATING.
;
; AN INSTRUMENT THAT COMES UP WITH ITS OUTPUTS CONNECTED, then. That is
; $80F3's behaviour and not an accident: the range field it writes is
; all-zeros (every attenuator pad in) and instrument_preset ($C6EA), which
; $80F3 calls at $8108 before the loop, has just run dds_params_reset ($DF17)
; and set every channel's level to zero, so nothing is driven. update_output_leds
; ($B72F) then lights the OUTPUT lamps, which is what an operator sees on a
; real one. This firmware used to open all four relays instead and leave the
; lamps dark - silent in the same way, but not what the instrument does, and
; not what the front panel then reports.
;
; The record follows the latch rather than being written beside it:
; chan_state_sync derives CHAN_STATE from the latch shadow, so the screen and
; the relay cannot disagree. That is the same reason chan_state_sync exists
; at all - the rewrite once kept the two apart and setting an amplitude
; switched the output off for good.
; ---------------------------------------------------------------------------
LATCH_RESET     equ     $00             ; fitted: filter through, low line
                                        ; floating, output relay closed,
                                        ; every attenuator pad in, probe down
LATCH_SETTLE_MS equ     6               ; the stock's delay_ms(6) after the
                                        ; range field changes, at $B61B

; ---------------------------------------------------------------------------
; channel_park_destinations - take every destination out of the records
;
;   exit:  each record's CHAN_DEST is LBL_OFF and chan_dest_parked holds what
;          it was
;   uses:  A, B, X
;
; THE COLD BRANCH ONLY. reapply_all_channels ($C5B1) does this at $C5E8-$C5F2
; before it applies anything, and it is why a cold instrument's DACs hold zero
; while its screen reads 140 uV: with $0010 in the record,
; channel_apply_and_propagate ($BE5C) takes the $BE85 branch, writes the level
; register with zero and returns before the latch's range field is touched.
;
; Nothing is lost by it - channel_config_open puts them back, as
; enter_channel_config_mode ($528F) does at $5404-$543D - and what is gained
; is that an instrument coming up on a fresh battery drives nothing into
; whatever is connected to it.
; ---------------------------------------------------------------------------
CHAN_DEST_NONE  equ     $FF             ; nothing parked for this channel

channel_park_destinations
                clrb
channel_park_next
                cmpb    #CHANNEL_MAX
                bhs     channel_park_done
                pshs    b
                lda     #CHAN_RECORD
                mul
                ldx     #channel_records
                leax    d,x                     ; X = the record
                ldb     ,s                      ; the channel again
                lda     CHAN_DEST,x
                pshs    a
                ldx     #chan_dest_parked
                abx
                puls    a
                sta     ,x                      ; parked
                puls    b
                pshs    b
                lda     #CHAN_RECORD
                mul
                ldx     #channel_records
                leax    d,x
                lda     #LBL_OFF                ; and the record says nothing
                sta     CHAN_DEST,x             ; is routed

                ; AND routed_dest WITH IT, which is the byte that decides
                ; anything. The stock parks record+$21, and record+$21 IS the
                ; destination channel_apply_and_propagate ($BE5C) reads at
                ; $BE74 and tests against $0010 at $BE82 - park it and $BE5C
                ; writes a zero level and returns at $C065 before it reaches
                ; the socket's range latch or its relay.
                ;
                ; Parking CHAN_DEST alone left routed_dest holding the old
                ; socket, so ampl_propagate took its ROUTED path, wrote the
                ; range field into all four latches and left it there: with
                ; the park in, a sequence-mode entry gave latches $79 $78 $78
                ; $78 where the instrument gives $01 $00 $00 $00. Driven
                ; 2026-09-13.
                puls    b
                pshs    b
                ldx     #routed_dest
                abx
                lda     #LBL_OFF
                sta     ,x
                puls    b
                incb
                bra     channel_park_next
channel_park_done
                rts

; ---------------------------------------------------------------------------
; channel_mode_exit - the Channel Configuration mode's exit callback
;
;   uses:  A, B, X, Y, U
;
; clear_all_destinations ($5253 on A2U13 page 0), which
; enter_channel_config_mode ($528F) installs as the callback at $2213 at
; $54D1/$54D4 and which every return to the Main Selection Level runs. It
; loops $23BE from 0 to 3 calling set_channel_destination ($78BF)(channel,
; $0010), so each channel goes through the whole of that routine with Off as
; the new code: the level zeroed, the level register written with zero, the
; old routing dismantled - which is where the vacated socket's relay opens -
; and record+$21 left holding $0010.
;
; Driven side by side, entering Channel Config. and leaving it by f4 Exit:
;
;   stock   in:  levels (1879,1879,1879,1879) dest 0C 0D 0E 0F latch (0,0,0,0)
;           out: levels (0,0,0,0)             dest 10 10 10 10 latch ($4 x 4)
;   this    in:  the same.  out: NOTHING CHANGED AT ALL
;
; So the instrument goes quiet and opens its relays when the operator walks
; out of the channel screens, and this firmware left four sockets driving.
; Found by the differential harness at seed 1 step 29, whose step is the bus
; command `EM 880;`: its request $0B reaches return_to_main_menu ($8E62),
; arm [10] of the $8F2A table, which calls the vector as every return arm
; does.
;
; Two routines rather than one, because this firmware splits what $78BF does
; in a single pass. destn_park_all is the teardown - destn_route leaves
; CHAN_DEST alone deliberately, see its header, because the register-recall
; path needs that - and channel_park_destinations is the record, which also
; keeps the old code in chan_dest_parked so channel_restore_destinations can
; put it back when the mode is opened again. The stock keeps its copy in
; $24DE instead, put there by reapply_all_channels ($C5B1) at $C5E8 on the
; way in.
; ---------------------------------------------------------------------------
channel_mode_exit
                lbsr    destn_park_all          ; the routing, the levels and
                                                ; the relays
                lbra    channel_park_destinations       ; then the records

; ---------------------------------------------------------------------------
; channel_restore_destinations - put them back, and route them
;
;   uses:  A, B, X, Y, U
;
; The other half: $5404-$543D calls set_channel_destination per channel as the
; Channel Configuration mode opens. Assigning the destination is what makes
; channel_apply_and_propagate program the real level, so this is the moment a
; cold instrument's DACs stop holding zero - which is the instrument's own
; answer to "when does it start producing".
;
; It runs once: each entry is set to CHAN_DEST_NONE as it is used, so opening
; the screen a second time restores nothing and cannot undo an operator's own
; choice of destination.
; ---------------------------------------------------------------------------
channel_restore_destinations
                clrb
channel_restore_next
                cmpb    #CHANNEL_MAX
                bhs     channel_restore_done
                ldx     #chan_dest_parked
                abx
                lda     ,x
                cmpa    #CHAN_DEST_NONE
                beq     channel_restore_step
                pshs    b
                ldb     #CHAN_DEST_NONE         ; used: not again
                stb     ,x
                puls    b
                pshs    a,b                     ; A at 0,s is the parked
                                                ; code, B at 1,s the channel
                tfr     b,a                     ; A = the channel
                ldb     ,s                      ; B = the code it parked
                lbsr    destn_apply             ; stores it and routes it
                puls    a,b
channel_restore_step
                incb
                bra     channel_restore_next
channel_restore_done
                rts

channel_reset_all
                lbsr    instrument_preset       ; FIRST, exactly as $80F3 does
                                                ; at $8108: the timers stop,
                                                ; the chip's parameter block
                                                ; is rebuilt and $0B00 and
                                                ; $0600 are cleared, and only
                                                ; then are the latches touched.
                                                ; The order matters - the loop
                                                ; below zeroes every channel's
                                                ; range field, which is the
                                                ; amplitude exponent, so the
                                                ; levels have to have been
                                                ; zeroed first or the hardware
                                                ; would sit at an attenuation
                                                ; that no level accounts for.
                clrb                            ; B = the channel
channel_reset_next
                cmpb    #CHANNEL_MAX
                bhs     channel_reset_done

                cmpb    >installed_channels     ; below the count is fitted,
                blo     channel_reset_fitted    ; and the count is ascending
                lda     #LATCH_QUIESCENT        ; absent: relay open, low line
                bra     channel_reset_have      ; grounded
channel_reset_fitted
                lda     #LATCH_RESET
channel_reset_have
                inc     >dds_lock               ; THE STORE AND THE CALL
                                                ; ARE ONE OPERATION. An
                                                ; NMI landing between
                                                ; them would leave this
                                                ; writing the sequence
                                                ; player's value into a
                                                ; channel latch; see
                                                ; channel_latch_rmw.
                sta     >latch_bits             ; the value
                lda     #$FF                    ; and every bit is this
                lbsr    channel_latch_rmw       ; call's to set
                dec     >dds_lock

                lbsr    chan_state_sync         ; the record follows the latch

                pshs    b                       ; delay_ms clobbers B
                ldd     #LATCH_SETTLE_MS        ; the attenuator relays are
                lbsr    delay_ms                ; mechanical; the stock waits
                puls    b

                incb
                bra     channel_reset_next
channel_reset_done
                ; AND EVERY FITTED OUTPUT BACK ON THE AUTOMATIC FILTER.
                ; reset_all_channel_outputs ($80F3) calls, for each channel,
                ; set_channel_byte_24ec (ch, 0) and set_output_enable_mode
                ; (ch, 3): $24EC+ch = 0, $24E8+ch = 3 and the line driven
                ; from that zero. Its callers are power_on_init,
                ; show_id_screen_then_main_menu and event7_return_to_main_menu,
                ; which is boot, the ID key and PS - this routine's callers.
                clrb
channel_reset_filter
                lbsr    channel_valid           ; carry set if not fitted
                bcs     channel_reset_filter_next
                ldx     #filter_mode
                clr     b,x                     ; FILTER_AUTOMATIC, the stock's 3
                ldx     #filter_auto
                clr     b,x                     ; $24EC+ch = 0
channel_reset_filter_next
                incb
                cmpb    #CHANNEL_MAX
                blo     channel_reset_filter
                lbsr    filter_apply            ; switch_channel_latch_bit0
                lbsr    channel_probe_clear     ; the probe lines down, as
                                                ; channel_latches_bit7_clear
                                                ; ($B65F) does at the end of
                                                ; $80F3
                lbra    led_output_refresh      ; and the two output lamps
                                                ; now say what the relays do
