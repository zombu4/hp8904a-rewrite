; ===========================================================================
; dds.s - programming the synthesis chip
;
; The DDS is the instrument. Everything else on the front panel exists to
; decide what to write here.
;
; The port at $0200-$0201 is sixteen bits wide and WRITE-ONLY. There is no
; read path, so the firmware keeps a shadow of the registers it writes THROUGH
; dds_write: without one, changing a single bit of a register would mean
; guessing the other fifteen.
;
; IT IS NOT A SHADOW OF EVERY REGISTER, and this used to say it was. The
; shadow is two bytes per id, so a 24-bit value cannot fit in it at all, and
; the routines that stage those write the port directly and touch nothing -
; dds_write_wide for the four frequencies and register $27, phase_program for
; $10-$13, ampl_program for $0C-$0F. Widening it to three bytes an id would
; cost 42 more bytes of battery-backed RAM; that is a decision for whoever
; needs the service screens to read those registers true, and until then the
; limitation is stated here and at dds_read rather than left to be found.
;
; EVERY WRITE IS A SINGLE 16-BIT STORE WITH INTERRUPTS MASKED. Two 8-bit
; stores leave a window in which a handler can write the port, and the chip
; would then latch half of one word and half of another with nothing to
; notice. The stock firmware writes STD or STX almost everywhere for the same
; reason.
;
; The register numbers are the chip's own, as the service screens name them.
; ===========================================================================

; (these constants are in common/display.inc, common/formats.inc)

; The waveform codes the chip takes, in the order the front panel offers
; them. Named because #$03 in a register write says nothing about what comes
; out of the socket.
; The waveform and destination codes are NOT defined here. They share one
; numbering with the destination field and one name table, and both live in
; labels.s - see the header there for why they are one sequence and what
; that explains about the frequency ceiling.
;
; This file used to define six WAVE_ constants of its own: SINE=0,
; TRIANGLE=1, SQUARE=2, RAMP=3, NOISE=4, DC=5. Every one of the six was
; wrong, and nothing in the source recorded where they came from, because
; they came from nowhere. Reading the ROM's own table settled it.

; ---------------------------------------------------------------------------
; dds_reset - put every register into a known state
;
;   uses:  A, B, X, Y, U
;
; Called from the power-on path. The chip's own state after power-up is not
; specified anywhere this project has, so it is written rather than assumed -
; and the shadow is filled at the same time, so the two agree from the first
; instruction.
;
; ---------------------------------------------------------------------------
; THERE IS NO PER-CHANNEL LOOP HERE, and there was one.
;
; It walked channels 0 to 3 and wrote each one a zero level, exponent 0 into
; the attenuator field of its output latch, a zero frequency and a zero
; phase. THE STOCK'S CHIP RESET DOES NONE OF THAT. dds_params_reset ($DF17,
; firmware/src-generated/a2u12.s:18938) clears the parameter block
; $248A-$24C4, stores eleven named bytes into it, and calls
; dds_write_all_registers ($DEDA) twice, once with $24BB/$24BC clear and once
; with $24 in both. $DEDA walks register ids 0 to $29 through
; dds_register_descriptor and dds_param_store - the chip's own global
; registers, addressed by id. Neither routine takes a channel, neither writes
; an output latch, and docs/routine-index.txt records the measured hardware
; footprint of both: line 662, dds_params_reset `io=$0000,$0001`, and line
; 661, dds_write_all_registers `io=$0001,$0004,$002A`.
;
; TWO DIVERGENCES CAME OUT OF THAT LOOP, both found by driving the two
; firmwares side by side rather than by reading:
;
;   - THE ATTENUATOR. Exponent 0 complements to $0F, which lands as $78 in
;     bits 6:3, so every preset put $78 into all four output latches.
;     Entering Tone or DTMF Sequence gave (121, 120, 120, 120) here where the
;     instrument gives (1, 0, 0, 0). Traced on the stock: it writes exactly
;     ONE latch on that entry, channel 0's, and leaves 1 to 3 at whatever the
;     boot probe left them.
;   - THE FREQUENCY. The loop zeroed all four, and register_apply
;     (modules/registers.s) reprograms only the channels channel_valid says
;     are FITTED, so on a two-channel instrument channels 2 and 3 stayed at
;     zero for good. Differential harness seed 3, which draws two fitted
;     channels: the stock reads 10000 on both of them and this read 0.
;
; The chip is still left in a known state, because the global table below is
; what puts it there, and every fitted channel's frequency, waveform, phase
; and level are programmed straight afterwards by register_apply - which is
; the stock's own order: reinit_channel_tables ($C6C3) calls dds_params_reset
; and then reapply_all_channels ($C5B1).
;
; ---------------------------------------------------------------------------
; TWO FLUSHES, NOT ONE, AND THE MUX IN ITS OWN PLACE IN THE WALK.
;
; This wrote the table once and then put $22 and $23 out on their own,
; twice each, at the end - $22,$00 $23,$00 $22,$24 $23,$24 in a row. The
; instrument does something different and the difference is four words per
; reset. dds_params_reset ($DF17, firmware/src-generated/a2u12.s:18938)
; clears its shadow, stores the constants, CLEARS $24BB/$24BC and calls
; dds_write_all_registers ($DEDA); then stores $24 into both and calls
; $DEDA again. $DEDA walks ids 0 to $29 in ascending order and sends each
; one from the shadow, so $22 and $23 go out ONCE PER FLUSH, in their
; ascending place between $21 and $24, carrying whatever the shadow holds -
; $00 on the first walk and $24 on the second.
;
; Measured on the emulator at a cold start with four channels fitted: the
; stock's boot puts 393 words on $0200/$0201 and each of its two flushes is
; 78 of them; this firmware's single flush was 80, the two extra being the
; repeated mux pair. Register $27 was out of place for the same reason -
; the walk had it after $29 rather than between $26 and $28.
;
; So dds_reset IS $DF17 now: A carries the mux byte a flush is to send, the
; table has rows for $22, $23 and $27 in their ascending places, and the two
; flushes differ only in that byte. The shadow the stock keeps at
; $248A-$24C4 is dds_shadow here, written by dds_write on every one of these
; sends, so the two firmwares agree about what the chip was last told.
; ---------------------------------------------------------------------------
dds_reset
                clra                            ; $DF17's first flush: $24BB
                lbsr    dds_reset_flush         ; and $24BC clear
                lda     #PORT_MUX_IDLE          ; and its second, with $24 in
                                                ; both - both 3-bit fields
                                                ; holding PORT_NONE, so the
                                                ; instrument settles with all
                                                ; four sockets disconnected
                ; WHY THE CHIP IS SHOWN $00 FIRST IS NOT ESTABLISHED.
                ; Searched: $DF17's own instruction stream,
                ; firmware/src-generated/a2u12.s:18971-18984 - CLR >$24BB /
                ; CLR >$24BC, the first $DEDA call, LDB #$24 / STB >$24BB /
                ; LDB #$24 / STB >$24BC, the second - with nothing between
                ; the two but each call's argument push, no comparison and no
                ; delay; and every other writer of those two shadow bytes in
                ; the five images, which is dds_write_reg22 on page 1
                ; (a2u13_page1.s:7673) and dds_write_reg_22 ($51A5) on page 2
                ; (a2u13_page2.s:3504), each of them the operator changing a
                ; socket. None of them says what the $00 pass is for. It is
                ; done because the instrument does it.
                bsr     dds_reset_flush

                ; AND NOTHING IS ROUTED. dds_params_reset ($DF17) ends by
                ; clearing bits $0800 and $1000 of event_flags ($2204) at
                ; $DF8E-$DF95 (ANDA #$C7) - the summing group's two flags,
                ; SUM_ACTIVE and SUM_SPLIT - and its $248A-$24C4 wipe has
                ; already zeroed $24B8 and $24B9, the shadows of parameters
                ; $1F and $20, which the table above sends as $1F,$00 and
                ; $20,$00. sum_flags mirrors the two bits and routed_dest
                ; what each channel is routed to: after this every socket
                ; field is PORT_NONE and every modulation register is 0, so
                ; no channel is routed anywhere, which is LBL_OFF - and what
                ; the stock's records hold at its main menu (executed on the
                ; emulator: $24F5+35n+$21 reads $0010 for all four before
                ; Channel Config. is entered).
                ;
                ; AFTER BOTH FLUSHES, because $DF17 does it after both of its
                ; $DEDA calls and because a flush reads none of it.
                clr     >sum_flags
                ldx     #routed_dest
                lda     #LBL_OFF
                sta     ,x+
                sta     ,x+
                sta     ,x+
                sta     ,x
                rts

; ---------------------------------------------------------------------------
; dds_reset_flush - one walk of every register id, 0 to $29
;
;   entry: A = the byte registers $22 and $23 are to be sent
;   exit:  every id on the chip holds its power-on value, and dds_shadow
;          holds what was sent
;   uses:  A, B, X, Y, U
;
; dds_write_all_registers ($DEDA): ids 0 to $29 ascending, each through
; dds_register_descriptor ($DD3B) for its width and dds_param_store ($DD9D)
; for the staging. The table below is walked in that same ascending order and
; dds_write does the width lookup, so the word order on the port is $DEDA's.
; ---------------------------------------------------------------------------
dds_reset_flush
                pshs    a                       ; 0,s = this flush's mux byte
                ldy     #dds_reset_globals
dds_reset_global
                ldb     ,y+                     ; the register id, with its
                cmpb    #$FF                    ; two markers. $FF ends the
                beq     dds_reset_done          ; table and is not a register:
                                                ; ids stop at $29
                lda     ,y+                     ; its power-on value - or, for
                                                ; a wide row, the offset of
                                                ; its three bytes
                bitb    #$80                    ; BIT 7 MARKS A WIDE ONE.
                bne     dds_reset_wide          ; Ids stop at $29 so bits 7
                                                ; and 6 are free, and they
                                                ; keep the table in the
                                                ; ascending order $DEDA walks
                                                ; in - the four frequency
                                                ; registers and $27 sit inside
                                                ; the range and are the only
                                                ; ones in it that dds_write
                                                ; cannot take.
                bitb    #$40                    ; AND BIT 6 MARKS THE OUTPUT
                beq     dds_reset_narrow        ; MULTIPLEXER, whose value is
                andb    #$3F                    ; not the table's but this
                lda     ,s                      ; flush's - $24BB and $24BC,
                                                ; clear for the first walk and
                                                ; $24 for the second
dds_reset_narrow
                pshs    y,b                     ; dds_write uses Y, so the
                tfr     a,b                     ; table pointer does not
                clra                            ; survive it; and B has to be
                tfr     d,x                     ; free to carry the id
                puls    b                       ; B = the id again
                lbsr    dds_write
                puls    y                       ; the table pointer back
                bra     dds_reset_global

                ; A WIDE ROW'S VALUE BYTE IS AN OFFSET into the pair of
                ; 24-bit constants below: 0 for the zero the four frequency
                ; registers take and 3 for register $27's own three bytes.
                ; $27 is width 4 - descriptor byte $F6, and ($F6 >> 6) + 1 is
                ; 4 - so it takes three bytes and cannot go through dds_write
                ; at all, which refuses width 4 rather than truncate a 24-bit
                ; value into a 16-bit argument.
dds_reset_wide
                andb    #$7F                    ; the id itself
                ldu     #dds_reset_zero24
                leau    a,u                     ; A is 0 or 3, so the sign
                                                ; extension LEAU does costs
                                                ; nothing
                pshs    y,b                     ; Y across the call for the
                puls    b                       ; same reason as above
                lbsr    dds_write_wide
                puls    y
                bra     dds_reset_global
dds_reset_done
                puls    a                       ; the mux byte
                rts

; ---------------------------------------------------------------------------
; The chip's global registers and what they hold at power-on.
;
; Pairs of (register id, value), ended by $FF, in the ascending order
; dds_write_all_registers ($DEDA) walks: EVERY id from $00 to $29 is here,
; because $DEDA's loop is `CMPX #$002A / LBCC` and skips none of them. Two
; marker bits ride on the id, which can carry them because ids stop at $29:
; bit 7 says the register is width 4 and its value byte is an offset into the
; pair of 24-bit constants at the end, and bit 6 says the value is the output
; multiplexer's, which the flush carries rather than the table.
;
; This paragraph used to say that $00-$07 and $08-$13 were absent, and both
; halves stopped being true when the rows were added back - see the note at
; the staging registers and the one at the twelve per-channel registers.
;
; ESTABLISHED, not chosen. The stock firmware's dds_params_reset ($DF17)
; zeroes its 59-byte register shadow at $248A-$24C4 and then writes exactly
; ten constants into it before flushing the lot to the chip. The shadow is
; not one byte per id - firmware/src-generated/a2u12.s shows the descriptor
; table at $DD73 giving each id an offset as `byte AND $3F` from $248A - so
; each store below was mapped back through that table:
;
;     $24B4 = $04   offset $2A   id $1B
;     $24B5 = $0F   offset $2B   id $1C
;     $24B6 = $36   offset $2C   id $1D
;     $24B7 = $36   offset $2D   id $1E
;     $24BA = $1F   offset $30   id $21
;     $24BB = $00   offset $31   id $22   then $24 before the second flush
;     $24BC = $00   offset $32   id $23   then $24 before the second flush
;     $24BF = $0B   offset $35   id $26
;     $24C0 = $5F   offset $36   id $27, which is three bytes wide
;     $24C1 = $5E   offset $37
;     $24C2 = $10   offset $38
;
; Every other id is zero because the shadow was cleared and nothing wrote it.
; That is why the zeros below are here rather than left out: a register the
; stock firmware demonstrably sends $00 to is not the same thing as a
; register nobody has looked at, and leaving it out would make those two
; cases indistinguishable in this table.
;
; The listing was read with:
;   awk '/^dds_params_reset/,0' firmware/src-generated/a2u12.s | head -60
; ---------------------------------------------------------------------------
dds_reset_globals
                ; THE STAGING REGISTERS TOO. Running the stock against the
                ; emulator side by side with this firmware
                ; (emulator/tests/test_parity_old_new.py) showed the stock's
                ; boot touching $04-$07 - its power-on clocks its channel
                ; records out through dds_write_channel ($DE2E), which walks
                ; the staging registers $07 down to $00 - while this reset
                ; left them at the chip's unspecified power-up state. Zeros
                ; are staged here for the same reason the other zeros in this
                ; table are written rather than left out. No commit strobe
                ; follows, so no hop slot changes; and hop_program_send, the
                ; one sender every slot write goes through, rewrites
                ; all eight before its own commit, so a staged zero cannot
                ; leak into a slot.
                ; THE FOUR STAGING BYTES $00-$03, which the walk covers
                ; because $DEDA starts at id 0 and this table started at $04.
                fcb     $00,$00
                fcb     $01,$00
                fcb     $02,$00
                fcb     $03,$00
                fcb     $04,$00
                fcb     $05,$00
                fcb     $06,$00
                fcb     $07,$00

                ; AND THE TWELVE PER-CHANNEL REGISTERS, which are inside the
                ; walk and were left out of this table when the per-channel
                ; loop above it was removed. That removal was right about the
                ; attenuator latch and wrong about these: $DEDA walks ids 0 to
                ; $29 and $08-$13 are in that range, so the stock's chip reset
                ; DOES clear the four frequencies, the four levels and the
                ; four phases - from a parameter block dds_params_reset has
                ; just zeroed.
                ;
                ; Driven, and this is what showed it: `PS;` posts request 7,
                ; whose arm event7_return_to_main_menu ($8D8C) calls
                ; reset_all_channel_outputs ($80F3) and does NOT re-apply the
                ; records afterwards. From a Tone Sequence block the stock
                ; goes to ((0,0),(0,0),(0,0),(0,0)) and this firmware stayed
                ; at ((0,1879),(2000000,0),(10000,0),(10000,0)) - every
                ; channel still sounding after the one bus command whose whole
                ; purpose is to put the instrument back to a known state.
                ;
                ; $08-$0B are width 4 by their descriptors ($C8,$CB,$CE,$D1,
                ; and ($C8 >> 6) + 1 is 4), so they carry the bit-7 marker and
                ; go through dds_write_wide with the 24-bit zero below.
                ; $0C-$0F are width 2 and $10-$13 width 3, both of which
                ; dds_write takes.
                fcb     $88,$00                 ; $08-$0B, the frequencies
                fcb     $89,$00
                fcb     $8A,$00
                fcb     $8B,$00
                fcb     $0C,$00                 ; $0C-$0F, the levels
                fcb     $0D,$00
                fcb     $0E,$00
                fcb     $0F,$00
                fcb     $10,$00                 ; $10-$13, the phases
                fcb     $11,$00
                fcb     $12,$00
                fcb     $13,$00
                fcb     $14,$00                 ; }
                fcb     $15,$00                 ; } cleared by the shadow
                fcb     $16,$00                 ; } wipe and never written
                fcb     $17,$00                 ; }
                fcb     $18,$00                 ; }
                fcb     $19,$00                 ; }
                fcb     $1A,$00                 ; }
                fcb     $1B,$04                 ; stored at $24B4
                fcb     $1C,$0F                 ; stored at $24B5
                fcb     $1D,$36                 ; stored at $24B6
                fcb     $1E,$36                 ; stored at $24B7
                fcb     $1F,$00                 ; the summing mask, $24B8:
                                                ; in the wipe, never set
                fcb     $20,$00                 ; the summing node, $24B9:
                                                ; in the wipe, never set
                fcb     $21,$1F                 ; stored at $24BA
                fcb     $62,$00                 ; $22 | $40: the output mux's
                                                ; low pair, $24BB. Bit 6 says
                                                ; the value comes from the
                                                ; flush and not from here, so
                                                ; the byte beside it is unused
                fcb     $63,$00                 ; $23 | $40: the high pair,
                                                ; $24BC, the same way
                fcb     $24,$00
                fcb     $25,$00
                fcb     $26,$0B                 ; stored at $24BF
                fcb     $A7,$03                 ; $27 | $80: width 4, and its
                                                ; three bytes are at offset 3
                                                ; of the pair below
                fcb     $28,$00
                fcb     $29,$00
                fcb     $FF                     ; end of the walk: $DEDA's
                                                ; `CMPX #$002A / LBCC`

; The two 24-bit constants the wide rows point at, addressed as one block so
; a wide row can name its own with a one-byte offset. They are adjacent on
; purpose and nothing may be put between them.
;
; The 24-bit zero the four frequency registers are reset with went out with
; the per-channel loop and came back with the table rows for $08-$0B:
; dds_write_wide takes a pointer, and three bytes of ROM are cheaper than a
; scratch cell that would have to be cleared before every use.
dds_reset_zero24 fcb    $00,$00,$00             ; offset 0

; The three bytes of register $27, high first, from $24C0-$24C2. service_pll.s
; loads this label directly for the Manual PLL screen's default, so it keeps
; its own name rather than being reached only as an offset.
dds_reset_reg27 fcb     $5F,$5E,$10             ; offset 3

; ---------------------------------------------------------------------------
; dds_mode_set - turn one of the chip's modulation modes on or off
;
;   entry: A = the control register - DDS_AM_CONT, DDS_PULSE_CTL or
;             DDS_PHASE_CTL; B = zero for off, non-zero for on
;   uses:  A, B, X
;
; The stock's dds_mode_param_set ($E69C) maps a control id onto one of five
; DDS parameters, writes it, and for three of them MIRRORS whether the value
; it wrote was 8 into a flag bit. "On" is the value 8: set_hop_function_enable
; (page 0 $4984) produces 8 when its argument is $0011 and 0 otherwise.
;
; The mirror is not bookkeeping for its own sake. These registers are
; write-only, so nothing can ask the chip whether amplitude hop is on, and one
; thing needs to know - reject_am_while_amptd_hop ($7C9F) refuses the AM
; destination while the amplitude-hop bit is set.
;
; The fifth parameter, freq_ct ($1B), is deliberately not handled here: its
; value is forced rather than taken from the caller - le72c sets a flag and
; writes 0, or clears it and ORs $04 - and hop_enable already does that.
; ---------------------------------------------------------------------------
dds_mode_set
                pshs    a                       ; the register
                tstb
                beq     dds_mode_off
                ldb     #DDS_MODE_ON
                bra     dds_mode_write
dds_mode_off
                clrb
dds_mode_write
                pshs    b                       ; the value, over the register
                lda     1,s                     ; the register again: 0,s is
                                                ; the value just pushed, 1,s
                                                ; the register pushed at
                                                ; entry. This read 2,s - the
                                                ; high byte of the return
                                                ; address - so dds_mode_flag
                                                ; was handed a code that names
                                                ; no register, returned zero,
                                                ; and no caller's flag was ever
                                                ; recorded in mode_flags; the
                                                ; one caller then on the hop
                                                ; screen toggled the byte
                                                ; itself before calling, which
                                                ; hid it. Found by executing
                                                ; the Phase Hop key on the
                                                ; emulator: $1708 went out and
                                                ; mode_flags stayed $00.
                lbsr    dds_mode_flag           ; A = its flag bit
                tst     ,s
                beq     dds_mode_clear
                ora     >mode_flags
                sta     >mode_flags
                bra     dds_mode_send
dds_mode_clear
                coma
                anda    >mode_flags
                sta     >mode_flags
dds_mode_send
                puls    b                       ; the value
                clra
                tfr     d,x                     ; X = it, for dds_write
                puls    b                       ; the register
                lbra    dds_write

; ---------------------------------------------------------------------------
; dds_mode_flag - which flag bit records a control register's state
;
;   entry: A = the register
;   exit:  A = the bit, or zero for a register that has none
;   uses:  A
;
; From dds_mode_param_set: $19 mirrors into bit 6, $18 into bit 5 and $17 into
; bit 7 of the byte the stock keeps at $2203.
; ---------------------------------------------------------------------------
dds_mode_flag
                cmpa    #DDS_AM_CONT
                bne     dds_mode_flag_pulse
                lda     #MODE_FLAG_AM
                rts
dds_mode_flag_pulse
                cmpa    #DDS_PULSE_CTL
                bne     dds_mode_flag_phase
                lda     #MODE_FLAG_PULSE
                rts
dds_mode_flag_phase
                cmpa    #DDS_PHASE_CTL
                bne     dds_mode_flag_none
                lda     #MODE_FLAG_PHASE
                rts
dds_mode_flag_none
                clra
                rts

; ---------------------------------------------------------------------------
; dds_phase_reset - the automatic phase reset, unless the operator turned it off
;
;   uses:  A, B, X, Y
;
; A one-shot LOW pulse on bit 3 of register $26. The stock issues it after a
; frequency change so that every channel starts the new frequency from a known
; phase, and special function 1 - "Disable automatic phase reset" - vetoes it
; for a measurement that cares more about phase continuity.
;
; NEITHER HALF EXISTED HERE. SPECIAL_NO_PHASE_RESET was declared and read
; nowhere, and the pulse it vetoes was not implemented either - so the
; preference could be toggled on the Special Functions screen and changed
; nothing, in both positions, because there was nothing to disable.
;
; Established from dds_reg26_bit3_pulse ($DE7F), which reads the shadow of
; $26, ANDs $F7, writes it, and then writes the standing value back; and from
; dds_reg26_pulse_if_flag1_clear ($DEB6), which skips exactly that when bit 1
; of the special flags is set. The stock's own screen text for bit 1 reads
; "Disable automatic phase reset", which is what ties the bit to the pulse.
;
; The standing value is captured BEFORE the low write, because dds_write
; maintains the shadow - reading it back afterwards would return the pulsed
; value and the bit would stay low.
; ---------------------------------------------------------------------------
dds_phase_reset
                lda     >special_flags
                bita    #SPECIAL_NO_PHASE_RESET
                bne     dds_phase_reset_done
                ; falls into the unvetoed pulse below

; ---------------------------------------------------------------------------
; dds_phase_reset_now - pulse it whatever the special function says
;
;   uses:  A, B, X
;
; THE STOCK HAS BOTH ENTRIES AND THIS FIRMWARE HAD ONLY THE VETOED ONE.
; dds_reg26_bit3_pulse ($DE7F) pulses unconditionally and
; dds_reg26_pulse_if_flag1_clear ($DEB6) wraps it in the special-function
; test; the arm at $8DF3, reached by key code 49, calls the unvetoed one.
;
; So an operator who has turned "Disable automatic phase reset" on still has a
; way to ask for one by hand - and here there was none at all, which is the
; opposite of what that special function says. It disables the AUTOMATIC
; reset; it was disabling every reset.
; ---------------------------------------------------------------------------
dds_phase_reset_now
                ; HELD AGAINST THE TICK, like port_route's. This reads the
                ; pulse register, writes bit 3 low, and writes it high again -
                ; three accesses that mean nothing unless they are the only
                ; ones. dds_phase_reset is reachable from the interrupt through
                ; tone_advance, and the foreground reaches it from the phase
                ; screens; dds_write's own lock covers each access and not the
                ; sequence, so a step landing between the read and either write
                ; leaves the register holding whatever the other side had.
                inc     >dds_lock
                ldb     #DDS_PULSE
                lbsr    dds_read                ; X = the standing value
                pshs    x
                tfr     x,d
                andb    #~PULSE_PHASE_RESET     ; bit 3 low
                clra
                tfr     d,x
                ldb     #DDS_PULSE
                lbsr    dds_write
                puls    x                       ; and back up again, which is
                ldb     #DDS_PULSE              ; what makes it a pulse rather
                lbsr    dds_write               ; than a level
                dec     >dds_lock
dds_phase_reset_done
                rts

; ---------------------------------------------------------------------------
; hop_enable - switch the fast-hop function on or off
;
;   entry: B = HOP_ON or HOP_OFF
;   uses:  A, B, X, Y
;
; NOTHING TURNED HOP ON. The table could be edited and, once hop_program was
; written, programmed into the chip's own RAM - and register $1B was written
; exactly once, by the power-on reset, with the value that means OFF. So the
; whole feature was reachable, storable, programmable and switched off, with
; no way to switch it on.
;
; The polarity is the stock's and it is the opposite way round from what this
; project used to record: set_hop_function_enable's Freq Hop arm does `CLR
; 4,S` to enable and `ORB #$04` to disable, so ON is zero.
; ---------------------------------------------------------------------------
hop_enable
                tfr     b,a                     ; the value, into X's low half
                clrb
                exg     a,b
                tfr     d,x
                ldb     #DDS_FREQ_CT
                lbra    dds_write

; ---------------------------------------------------------------------------
; hop_program - recode one slot's amplitude and put the slot into the chip
;
;   entry: B = the slot, 0 to 15; A = the COMMON EXPONENT this slot's code is
;          to be relative to - what $BC3E reads at $000E,S.
;          ONLY hop_reprogram_all calls it, as only rescale_channel_dacs
;          calls $BC3E. A caller that is not rescaling wants hop_write_slot
;          below, which is dds_write_channel ($DE2E) and codes nothing.
;   exit:  the chip's hop RAM holds this slot's step, and hop_ampl_codes
;          holds the amplitude code it was given
;   uses:  A, B, X, Y, U
;
; THE HOP TABLE REACHED NOTHING BEFORE THIS. hop_store wrote a frequency into
; sixteen slots of battery-backed RAM and no routine anywhere sent them to the
; chip, so the fast-hop screen edited a list the hardware never saw.
;
; The sequence is the stock's, read out of dds_write_channel ($DE2E) and
; recorded with the instructions in audit/hop_programming.md. Eleven writes to
; $0200/$0201:
;
;     $07 <- phase[11:6]      $06 <- phase[5:0]
;     $05 <- ampl[11:6]       $04 <- ampl[5:0]
;     $03 <- freq[23:18]      $02 <- freq[17:12]
;     $01 <- freq[11:6]       $00 <- freq[5:0]
;     $15 <- the slot number, masked to four bits
;     $14 <- $00
;     $15 <- the standing value of $15
;
; Read as one 48-bit word it is phase, then amplitude, then frequency, most
; significant first, six bits at a time into descending register ids.
;
; $15 is HP's ram_add and $14 its ram_wrt - the chip's hop RAM is addressed by
; one and strobed by the other. That reading is an INFERENCE and is marked as
; one in the audit file: what is established is the order of the writes and
; that page 1's tone code does the identical save, select, strobe and restore
; by hand. The restore matters either way - $15 carries the standing hop-RAM
; address, and leaving it pointing at the slot just written would move where
; the chip reads next.
;
; THESE EIGHT GO STRAIGHT TO THE PORT, not through dds_write, exactly as the
; stock does - so registers $00-$07 are written without their shadows being
; updated. That is a real consequence and it is why dds_reset does not write
; them: a flush of the shadows would push stale values over a staged word.
;
; PHASE AND AMPLITUDE COME FROM THE SLOT, like the frequency: a slot is
; HOP_ENTRY_SIZE = 8 bytes - HOP_FREQ, HOP_AMPL, HOP_PHASE - and the hop
; screen's f2 cycles those three fields. An earlier version of this header
; said the slot was three bytes of frequency with phase and amplitude taken
; from the selected channel; that stopped being true when the read-through
; reached the stock's fifteen-byte record and the slot grew its own fields,
; and the paragraph outlived the code it described - two later coverage
; verdicts cited it as fact. The body below reads HOP_PHASE and HOP_AMPL
; from the slot. What it reads of CHANNEL 0 - the record's waveform, its
; sign while amplitude hop is off, and the exponent in its range latch - is
; what the stock's reprogram_all_channels ($BC3E) reads of it, and the
; comments at the amplitude code say where.
;
; THE AMPLITUDE CODE IS NOT ampl_scale's MANTISSA. It was, and the exponent
; came back in B and was dropped - so a 10 mV slot and a 1 V slot put the
; same $800-$FFF into the chip. The hop RAM word carries no range: the
; eleven writes below are phase, amplitude and frequency, and the range
; latch is not among them, so the code is applied against whatever range
; channel 0 stands at. The stock therefore shifts each slot's mantissa by
; the difference between its own exponent and the channel's common one
; ($BCB5-$BCC1) and folds a dc level around that shift ($BC93-$BCB4,
; $BCC6-$BCE3), and that is what the amplitude code below does.
;
; AND THE CODE IS KEPT, which is what makes it the stock's. $BCF6-$BCFA
; (LEAX 2,X / LDD 6,S / STD ,X) store it at record+2 before $BD08 sends the
; slot, and record+2 is what every other send of that slot reads back rather
; than recomputes - hop_ampl_codes, and hop_write_slot below.
; ---------------------------------------------------------------------------
; ---------------------------------------------------------------------------
; hop_write_slot - one slot to the chip, with the amplitude code it last had
;
;   entry: B = the slot, 0 to 15
;   exit:  the chip's hop RAM holds this slot's step
;   uses:  A, B, X, Y, U
;
; dds_write_channel ($DE2E) for every caller that is not rescaling. $DE2E
; codes nothing: $DE39-$DE46 index the $2581 record by the slot ANDed $0F,
; and $DE48-$DE55 shift out record+0, record+2 and record+4 as they stand.
; Its callers besides reprogram_all_channels ($BC3E) are the frequency
; commit's d4c26 at $4C89, set_hop_entry_phase at $4E7F, dds_reload_all_slots
; ($E799) and store_hop_ram_slot ($58A6) - and the first three store nothing
; at record+2, so the amplitude code they send is whichever $BC3E, $58A6 or
; the $E7F9 clear left there last. hop_ampl_codes is that word here.
;
; THIS WAS hop_program_standing, AND IT CODED THE LEVEL. It read channel 0's
; range out of latch_shadow[0] and fell into hop_program, so every frequency,
; phase or level commit of a slot put a freshly computed amplitude code into
; the chip. The instrument writes no such code: measured with
; emulator/tests/test_differential.py, seed 1, the Hop Ram Adrs record took
; 1 kHz, 100 uV and 0 deg, and registers $05/$04 then held $14/$3E here and
; $00/$00 on the stock - whose frequency and phase commits re-sent record+2's
; zero, and whose level commit sent nothing at all (hop_field_commit below).
;
; THE PHASE CODE IS STILL WORKED OUT FROM THE SLOT, where $DE2E sends
; record+0 as stored. set_hop_entry_phase ($4DC7) stores record+0 from the
; same typed value this slot's HOP_PHASE keeps, so the two agree - except
; after the raw service screen, whose $58A6 stores record+0 unconverted and
; whose code hop_program_raw sends once and does not keep. Keeping it needs a
; second sixteen-word array, and the 26 bytes left between hop_ampl_codes
; and $3FEE cannot hold one.
; ---------------------------------------------------------------------------
hop_write_slot
                inc     >dds_lock               ; as hop_program: the sequence
                                                ; player defers a tick rather
                                                ; than write into this
                pshs    b                       ; the slot, at 0,s, where
                                                ; hop_program_send expects it
                lbsr    hop_phase_code          ; hop_phase, record+0's stand-in
                ldb     ,s                      ; $DE39-$DE40: the slot,
                andb    #$0F                    ; ANDB #$0F
                lslb                            ; two bytes a slot
                ldx     #hop_ampl_codes
                abx                             ; X = this slot's code
                ldd     ,x                      ; record+2 as it stands, sent
                std     >hop_ampl               ; by $DE4C uncoded
                lbra    hop_program_send

hop_program
                inc     >dds_lock               ; see nmi_handler: the
                                                ; sequence player defers a
                                                ; tick rather than writing
                                                ; into the middle of this
                pshs    b                       ; the slot
                pshs    a                       ; the common exponent, on top
                                                ; of it until the amplitude
                                                ; code is staged - so the slot
                                                ; is at 1,s through this
                                                ; routine and at 0,s where
                                                ; hop_program_send expects it

                ; --- the phase code, FROM THE SLOT ------------------------
                ldb     1,s                     ; the slot
                lbsr    hop_phase_code          ; hop_phase; X = the slot's
                                                ; eight bytes

                ; --- and the amplitude code -------------------------------
                ; scale_to_dds_code ($D3EC) as reprogram_all_channels calls
                ; it at $BC8C: CLRB / SEX / TFR D,X - CHANNEL 0 - so the
                ; waveform arm reads channel 0's record ($2514, its +$1F),
                ; and the sign is chosen at $D4A7-$D4E2: channel 0 ($D4A7
                ; LDB <$15,S / BNE) with amplitude hop on ($D4AB LDD >$2202
                ; / ANDB #$40 / BEQ) takes the hop record's own byte at +10
                ; ($D4B2-$D4C8, the $2581 record indexed by $24F4, which
                ; $BC3E sets to the slot it is on); otherwise channel 0's
                ; record+$14 ($D4CC-$D4E2). MODE_FLAG_AM is that bit here,
                ; hop_signs the sixteen +10 bytes, ampl_signs the +$14 bytes.
                leau    HOP_AMPL,x              ; U = its 24-bit level
                ldb     1,s                     ; the slot number
                andb    #$0F
                lda     >mode_flags
                bita    #MODE_FLAG_AM
                beq     hop_sign_channel
                ldx     #hop_signs
                lda     b,x                     ; the slot's own sign
                bra     hop_sign_chosen
hop_sign_channel
                lda     >ampl_signs             ; channel 0's
hop_sign_chosen
                ldx     #channel_records        ; channel 0's record
                lbsr    ampl_level_raw          ; X = the code, B = the
                                                ; slot's own exponent

                ; --- the fold, shift and unfold of $BC93-$BCE3 ------------
                ; The shift count is the common exponent minus this one:
                ; $BCB5 LDB 3,S / CLRA / SUBD >$000E,S, negate16, then
                ; shift_signed at $BCC1. That argument is the exponent
                ; channel_apply_and_propagate ($BE5C) computed for the
                ; destination's summed level and handed down through
                ; rescale_channel_dacs ($BD82), and it is the SAME value
                ; $BE5C writes into the output channel's range latch at
                ; $C04C through output_latch_level_set ($B5EF) - so a hop
                ; code is relative to the range the channel stands at.
                ; 
                ; IT IS HANDED IN, and used to be read back out of
                ; latch_shadow[0]. That worked only while channel 0 sat
                ; on Out1: $C04C writes the SOCKET's latch, so with
                ; channel 0 routed anywhere else the number was not
                ; there, and ampl_rescale_dest had to write channel 0's
                ; own latch first to put it there - a latch write the
                ; stock makes in no arrangement. Passing it removes the
                ; read and that write together.
                lda     ,s                      ; the common exponent, where
                                                ; $BC3E reads $000E,S
                pshs    b                       ; the slot's own exponent
                suba    ,s+                     ; A = common - own, signed
                clrb                            ; no carrier halving: $BC3E
                                                ; tests $240D nowhere
                ldy     #channel_records        ; channel 0's waveform gates
                lbsr    ampl_level_range        ; the fold. X = the code
                stx     >hop_ampl

                ; --- $BCE3-$BCFA: and into the slot's record+2 -----------
                ; LDU #$2581 / ... / array_element_address on the slot at
                ; $24F4, LEAX 2,X / LDD 6,S / STD ,X - the code kept where
                ; hop_write_slot reads it, before $BD08 sends the slot.
                ldb     1,s                     ; the slot, under the exponent
                andb    #$0F
                lslb                            ; two bytes a slot
                ldx     #hop_ampl_codes
                abx
                ldd     >hop_ampl
                std     ,x                      ; $BCFA STD ,X
                puls    a                       ; done with the exponent, and
                                                ; the slot is at 0,s again -
                                                ; 1,s under the sender's own
                                                ; CC push

                ; and fall into the sender with the codes staged

; ---------------------------------------------------------------------------
; hop_program_send - clock one slot into the chip from staged codes
;
;   entry: the slot is on the stack under the caller's B (see below);
;          hop_phase and hop_ampl hold the two 12-bit codes;
;          hop_table[slot] holds the 24 frequency bits;
;          dds_lock is already raised
;   uses:  A, B, X, U
;
; SPLIT OUT so the Manual CowChip screen's raw half has an entry that skips
; the two conversions. The stock's store_hop_ram_slot ($58A6) takes the two
; 12-bit words and the 24-bit field EXACTLY as typed - its slot records at
; $2581 hold codes, and the manual screen's atoi5/$0FFF clamp feeds them
; straight in - so a raw service write cannot go through unit conversion
; without ceasing to be raw. The frequency needs no second path: the staged
; 24 bits ARE the 0.1 Hz count, the same encoding the unit table stores.
;
; It is entered by falling in from hop_program above, or by LBRA from
; hop_write_slot above and hop_program_raw below, never called directly - and
; each of the three raises the lock and pushes the slot first, so the stack
; shape at 1,s is identical on all three paths.
hop_program_send
                DISABLE_INTERRUPTS              ; the eight staged writes and
                                                ; the three that commit them
                                                ; are one transaction: a write
                                                ; to any other register in the
                                                ; middle would be latched into
                                                ; this slot. The stock does
                                                ; NOT mask, and its own tone
                                                ; sequencer writes this port
                                                ; from an interrupt - which is
                                                ; a race, not a licence.

                ldx     >hop_phase
                ldb     #$07
                lbsr    hop_send_high           ; $07 <- bits 11:6
                ldx     >hop_phase
                ldb     #$06
                lbsr    hop_send_low            ; $06 <- bits 5:0

                ldx     >hop_ampl
                ldb     #$05
                lbsr    hop_send_high
                ldx     >hop_ampl
                ldb     #$04
                lbsr    hop_send_low

                ; --- the frequency, twenty-four bits in four fields --------
                ; The slot's HOP_FREQ bytes, at offset 0 of its eight.
                ; Computed here rather than by
                ; calling hop_slot_address, which lives on page 0 - only one
                ; page is mapped at a time and this is the always-mapped
                ; image, so that call could not work.
                ldb     1,s                     ; THE SLOT IS AT 1,S HERE,
                                                ; not at 0,s: DISABLE_INTERRUPTS
                                                ; pushes CC and that CC is on
                                                ; top of it for the whole
                                                ; masked region.
                andb    #$0F                    ; sixteen slots
                lda     #HOP_ENTRY_SIZE
                mul
                ldu     #hop_table
                leau    d,u

                ldb     ,u                      ; byte 0 = bits 23:16
                lsrb
                lsrb                            ; bits 23:18
                lda     #DDS_BUFLAT3
                std     >dds_prog

                ldb     ,u                      ; bits 17:16, then 15:12
                andb    #$03
                lslb
                lslb
                lslb
                lslb
                lda     1,u
                lsra
                lsra
                lsra
                lsra
                pshs    a
                addb    ,s+
                andb    #$3F
                lda     #DDS_BUFLAT2
                std     >dds_prog

                ldb     1,u                     ; bits 11:8, then 7:6
                andb    #$0F
                lslb
                lslb
                lda     2,u
                lsra
                lsra
                lsra
                lsra
                lsra
                lsra
                pshs    a
                addb    ,s+
                andb    #$3F
                lda     #DDS_BUFLAT1
                std     >dds_prog

                ldb     2,u                     ; bits 5:0
                andb    #$3F
                lda     #DDS_BUFLAT0
                std     >dds_prog

                ; --- select the slot, strobe, and put the address back -----
                ldb     1,s                     ; the slot, under the CC
                andb    #$0F
                lda     #DDS_HOP_ADDRESS
                std     >dds_prog
                clrb
                lda     #DDS_HOP_WRITE
                std     >dds_prog
                ldb     #DDS_HOP_ADDRESS        ; the standing value, from the
                lbsr    dds_read                ; shadow dds_write maintains -
                tfr     x,d                     ; the two writes above are
                lda     #DDS_HOP_ADDRESS        ; direct and do not touch it
                std     >dds_prog

                RESTORE_INTERRUPTS
                puls    b
                dec     >dds_lock
                rts

; ---------------------------------------------------------------------------
; hop_program_raw - clock one slot in with the codes given raw
;
;   entry: B = the slot, hop_phase and hop_ampl = the 12-bit codes,
;          hop_table[slot]'s frequency bytes already written
;   uses:  A, B, X, U
;
; The service path: what the operator typed goes to the chip unconverted,
; which is the point of a manual check screen - a conversion in the way would
; make the codes it is exercising unreachable. 3600 of the 4096 phase codes
; are expressible as tenths of a degree and the rest only exist raw.
;
; THE AMPLITUDE CODE IS KEPT, as store_hop_ram_slot ($58A6) keeps it: its
; second array_element_address walk ends LEAX 2,X / LDD >$000A,S / STD ,X,
; the typed word into record+2, before $DE2E sends the record. So a later
; frequency or phase commit of the same slot re-sends this code, which
; hop_write_slot does by reading hop_ampl_codes.
; ---------------------------------------------------------------------------
hop_program_raw
                inc     >dds_lock
                pshs    b                       ; the slot, where 1,s finds it
                                                ; under the CC push inside
                andb    #$0F                    ; the record the slot names,
                lslb                            ; two bytes a slot
                ldx     #hop_ampl_codes
                abx
                ldd     >hop_ampl               ; $58A6's STD at element+2
                std     ,x
                lbra    hop_program_send

; ---------------------------------------------------------------------------
; hop_phase_code - one slot's phase as the chip's 12-bit phase code
;
;   entry: B = the slot, 0 to 15
;   exit:  hop_phase = the code, unless the slot's radian word fails to
;          convert (below); X = the slot's HOP_ENTRY_SIZE bytes
;   uses:  A, B, X, Y, U
;
; The phase half of what hop_program used to do inline, out on its own so
; hop_write_slot and hop_program share one conversion. The stock does this
; work once, at entry: set_hop_entry_phase ($4DC7) codes the typed value and
; stores it at record+0, and $DE2E sends record+0 as it stands. This slot
; keeps the typed value instead, so the code is worked out on every send -
; which gives the same code for a slot the panel or the bus filled.
; ---------------------------------------------------------------------------
hop_phase_code
                andb    #$0F                    ; sixteen of them
                lda     #HOP_ENTRY_SIZE
                mul
                ldx     #hop_table
                leax    d,x                     ; X = this slot's eight bytes
                pshs    x
                ldd     HOP_PHASE,x

                ; A RADIAN SLOT IS CONVERTED FIRST. HOP_PHASE_RAD in the top
                ; bit says the word is thousandths of a radian rather than
                ; tenths of a degree (hp8904a-rewrite/common/formats.inc), and
                ; unit_apply's UNIT_RAD arm is the conversion the whole
                ; firmware uses, rounded as the stock's fixmul_q16 ($D303)
                ; rounds. The stock does the same work at entry time instead,
                ; into its record's own phase code at +0.
                bita    #HOP_PHASE_RAD_HI
                beq     dds_hop_phase_deg
                anda    #HOP_PHASE_VALUE_HI
                std     >dds_phase_work+1
                clr     >dds_phase_work

                ; AND IT MUST SAY WHAT THE STORED VALUE CARRIES. unit_apply's
                ; radian arm scales the digits by RAD_DECADES LESS entry_frac
                ; before converting - that is how a typed '3.140' and a typed
                ; '3140' both mean 3.140 radians - and entry_frac belongs to
                ; the entry layer, which has nothing to do with a slot being
                ; programmed. With whatever the last entry left in it, this
                ; call scaled a stored 1100 milliradians by a thousand, carried
                ; out of 24 bits and recorded $13 while the arrows were
                ; stepping the field. The slot holds milliradians, three places
                ; after the point, so it says so - and puts back what it found,
                ; because the entry it belongs to may still be open.
                lda     >entry_frac
                pshs    a
                lda     #RAD_DECADES
                sta     >entry_frac
                ldx     #dds_phase_work
                ldb     #UNIT_RAD
                lbsr    unit_apply              ; milliradians to tenths
                puls    a
                sta     >entry_frac

                ; AND THE VERDICT IS READ. With the fraction declared above
                ; the carry cannot be set for a slot inside CHAN_RAD_MAX, which
                ; is the only thing hop_range_phase and the bus's own limit let
                ; in - so a carry here means the slot has been corrupted, and
                ; the failed conversion's buffer is not turned into a code.
                ; hop_phase is left holding the code staged before it, and the
                ; caller still sends the slot with that - this used to say the
                ; slot was left unprogrammed, and the send after it was never
                ; skipped. The comment before that said the carry could not be
                ; set and then did not test it, which is two different claims.
                bcs     dds_hop_phase_done
                ldd     >dds_phase_work+1       ; in place
dds_hop_phase_deg
                tfr     d,x
                lbsr    phase_to_code           ; X = 0 to 4095
                stx     >hop_phase
dds_hop_phase_done
                puls    x                       ; the slot's eight bytes
                rts

; ---------------------------------------------------------------------------
; hop_reprogram_all - every slot of the hop table, against a common range
;
;   entry: A = the common exponent, the value rescale_channel_dacs hands
;          $BC3E at $BD77-$BD82
;   exit:  the chip's hop RAM holds all sixteen slots, coded against it
;   uses:  A, B, X, Y, U
;
; reprogram_all_channels ($BC3E). The hop RAM word carries no range - see
; hop_program above - so once channel 0's range moves, every slot's amplitude
; code in the chip is stale. The stock rewrites all sixteen: $BC54 LDB >$24F4
; / STB 2,S saves the slot index global, $BC59 CLR >$24F4 starts it at zero,
; and from $BC5C while it is below sixteen ($BC5F CMPB #$10 / LBCC lbd18) it
; scales the slot's 24-bit level at record+7 through scale_to_dds_code
; ($BC8C, with channel 0 in X), folds a dc code, shifts it by the common
; exponent minus the slot's own and unfolds it ($BC93-$BCE3), stores the code
; at record+2 ($BCF6 LEAX 2,X / $BCF8 LDD 6,S / $BCFA STD ,X), sends the
; whole slot with dds_write_channel ($BD08) and steps the index ($BD0D LDB
; >$24F4 / ADDB #$01 / STB >$24F4, $BD15 LBRA lbc5c). $BD18 restores the
; saved index and $BD1F returns. Its one caller in all five images is
; rescale_channel_dacs at $BD82, and ampl_level_apply in amplitude.s is that
; call.
;
; hop_program is the per-slot body, $BC8C to $BD0C: it scales, folds, shifts
; and unfolds one slot and sends it. The common exponent is passed down to it
; the way $BC3E takes its argument at $000E,S, rather than read back out of
; channel 0's latch shadow - which only held it while channel 0 sat on Out1,
; because $C04C writes the SOCKET's latch. The slot index is kept on the
; stack here rather than in a global the way $24F4 is, which is why there is
; nothing to save at entry or restore at exit.
; ---------------------------------------------------------------------------
hop_reprogram_all
                pshs    a                       ; the common exponent, for
                                                ; every slot
                clrb                            ; $BC59 CLR >$24F4
hop_reprogram_next
                pshs    b                       ; the slot, across the call
                lda     1,s                     ; the common exponent again
                lbsr    hop_program             ; $BC8C-$BD0C for this slot
                puls    b
                incb                            ; $BD0D-$BD12 ADDB #$01
                cmpb    #HOP_SLOTS              ; $BC5F CMPB #$10 / LBCC
                blo     hop_reprogram_next      ; $BD15 LBRA lbc5c
                puls    a                       ; the common exponent
                rts                             ; $BD1F

; ---------------------------------------------------------------------------
; hop_field_commit - what reaches the chip once one field of a slot is stored
;
;   entry: A = the field just stored - HOP_FIELD_FREQ, HOP_FIELD_AMPL or
;          HOP_FIELD_PHASE; B = the slot, 0 to 15
;   uses:  A, B, X, Y, U
;
; The tails of the stock's three slot commits, which are NOT one tail:
;
;   FREQ   apply_hop_frequency_entry ($4BFE) copies the value into record+4
;          and d4c26 calls dds_write_channel ($DE2E) at $4C89.
;   PHASE  set_hop_entry_phase ($4DC7) codes the value into record+0 and
;          calls $DE2E at $4E7F.
;   AMPL   store_hop_amptd ($4CD5) copies the level into record+7
;          ($4D2B-$4D4C) and a dc sign into record+10 ($4D59-$4D71), and
;          then reaches the chip ONLY while bit 6 of $2203 - amplitude hop -
;          is set: $4D73 LDD >$2202 / ANDA #$00 / ANDB #$40 / CMPD #$0000 /
;          $4D7E LBEQ l4d93. With it set, $4D82-$4D90 push channel 0 and
;          $221C and $4D8E calls dispatch_channel_function ($C069), whose
;          volts arm reaches channel_apply_and_propagate for channel 0 and so
;          reprogram_all_channels ($BC3E) - all sixteen slots recoded against
;          the destination's range. That call is ampl_hop_on here, the port
;          of set_hop_function_enable's own $C069 (0, $EA58) at $4B53. The
;          two calls differ only in the value pointer, and the arms
;          ampl_hop_on's header gives for channel 0 - [4]-[6], arm_no_action
;          ($C11E), one LBRA to lc181 - never read it: lc181-lc1c3 read the
;          channel at $0008,S and nothing else of the frame. That channel
;          0's record+13 selects those arms is ampl_hop_on's premise, taken
;          from its header and not re-derived here.
;
; SO A LEVEL TYPED WITH AMPLITUDE HOP OFF WRITES NOTHING TO THE CHIP, and
; this firmware's three commits all sent the slot with a code computed from
; the new level - the $05/$04 values emulator/tests/test_differential.py
; found in five of its first twelve seeds. The panel's ENTER and arrows
; (page0_hop.s, through ABI slot 54) and the bus's FRH, APH and PHH
; (remote.s remote_set_hop) all end here, as the stock's all end in these
; three routines.
; ---------------------------------------------------------------------------
hop_field_commit
                cmpa    #HOP_FIELD_AMPL
                lbne    hop_write_slot          ; FREQ at $4C89, PHASE at
                                                ; $4E7F: $DE2E of the slot
                lda     >mode_flags
                bita    #MODE_FLAG_AM           ; $4D73-$4D81: amplitude hop?
                beq     hop_field_commit_done   ; $4D7E LBEQ l4d93
                lbra    ampl_hop_on             ; $4D8E: $C069 for channel 0
hop_field_commit_done
                rts                             ; l4d93: nothing to the chip

; ---------------------------------------------------------------------------
; hop_table_defaults - the sixteen hop slots back to an empty table
;
;   uses:  A, B, X, Y, U
;
; dds_table_defaults ($E7F9). reinit_channel_tables ($C6C3) calls it FIRST,
; ahead of init_channel_blocks ($C4F0) and reapply_all_channels ($C5B1), and
; $C6C3 is reached from two places - power_on_init's cold branch at $8333 and
; enter_channel_config_mode ($528F) at $53FC. So WALKING INTO CHANNEL
; CONFIGURATION EMPTIES THE HOP TABLE on the instrument, and this firmware
; walked in and left it standing.
;
; AND SO DOES POWERING ON, which is the other of those two callers and the one
; this firmware never made. This routine was in page0_hop.s, reachable only by
; entering Channel Configuration, so from power-on until an operator opened
; that screen the chip's own hop RAM held whatever it powered up with while
; the Hop Ram screen showed sixteen empty slots. $E7F9 is in A2U12 on the
; instrument for the same reason it is in this file now: the boot runs it, and
; boot code cannot call into a paged image. Page 0 reaches it through ABI slot
; 108. It is 176 of the instrument's 393 cold-start DDS words - sixteen slots
; of eleven - and dds-cold-trace.md, in docs/, has that trace beside the
; stock's.
;
; DRIVEN, not read, on 2026-09-13: a booted stock at the Main Selection Level
; had $2581-$2670 and $2671-$267E filled with $A5 and then Channel Config. was
; opened through the pager. All sixteen fifteen-byte records came back
;
;       00 00 00 00 00 00 00 00 00 00 2B 00 00 00 03
;
; and the block behind them, $2671-$267E, came back
;
;       00 00 00   00 00 00   00 02   00 03   00 02   00 00
;
; $E7F9 is exactly that and nothing more. le809 clears $2581 up to but not
; including $2671 - 240 bytes, sixteen records of fifteen. le820 walks the
; sixteen through array_element_address ($FCEA) on the descriptor at $EA0A
; (FCB $00,$01,$00,$00,$00,$0F - one subscript, bounds 0 to 15, and the $000F
; stride the d4ec6 and d7eb7 descriptors carry too), storing $2B at record+10
; and the word $0003 at record+13. le861 calls dds_reload_all_slots ($E799),
; which pushes all sixteen at the chip with dds_write_channel ($DE2E). The
; tail copies the 24-bit zero at $EA58 into $2671 and $2674 with copy3 ($D37D)
; and stores $0002, $0003, $0002 and $0000 into $2677, $2679, $267B and
; $267D. Nothing in it touches $24F4 - the $0F the stock's hop slot index
; carries afterwards is init_channel_blocks' last instruction, not this one's.
;
; WHAT THE TWO PRIMED OFFSETS ARE, out of the instruction stream:
;
;   record+10 is the SIGN CHARACTER of that slot's level. store_hop_amptd
;   ($4CD5) writes the entry sign $241E there at $4D59-$4D71 when $2514 is 4,
;   channel 0's waveform being dc; show_hop_amptd_field ($4579) reads it back
;   at l45f2-l460b and draws it as the one leading character at LCD $47;
;   step_hop_amplitude ($7533) caches it at $7533-$753B to decide which way
;   an arrow moves a negative level; and scale_to_dds_code ($D3EC) reads it
;   at $D4B2-$D4C8 for channel 0 while amplitude hop is on. hop_signs is that
;   byte here - one per slot, same sixteen - and $2B is '+', CHAN_SIGN_PLUS.
;
;   record+13 is the UNIT that slot's phase is held in. set_hop_entry_phase
;   ($4DC7) stores $2221 there and the value at record+11, having bounded the
;   value against $EA5D (6282) for unit 4 and $EA5B (3599) for anything else;
;   draw_hop_phase_field ($468E) reads the pair back at l46c7-l46f9 and places
;   the point two columns in for 4 and four columns in otherwise. So 4 is
;   radians and the $0003 default is degrees.
;
;   THAT SECOND ONE NEEDS NO STORE HERE, and this is the one place the two
;   layouts differ rather than merely being packed differently. This slot is
;   eight bytes, not fifteen, and its phase unit rides in bit 15 of the phase
;   word itself - HOP_PHASE_RAD in hp8904a-rewrite/common/formats.inc, set for
;   radians and clear for degrees, which page0_hop.s's hop_store_field writes
;   and hop_show_one, hop_phase_code in this file and remote.s's HOPP query
;   all mask off.
;   Clearing the slot therefore already says degrees: the stock's fourteenth
;   and fifteenth bytes are stored by the same instruction that clears the
;   phase, not skipped.
;
; $2677 AND $267B ARE ONE CELL HERE. $2677 is the unit every slot's FREQ field
; is drawn in - paint_hop_value_field ($4461) reads it at $44B1 and its l44b6
; arm takes the six-whole one-fraction Hz form when it is 2, l44dc the
; three-and-four kHz form otherwise - and $267B is the same for the FREQ
; increment. Both default to 2, which is UNIT_HZ, and hop_freq_unit is the one
; cell this firmware keeps for the pair. $2679, the phase increment's unit,
; has no cell at all and needs none: every phase here is in tenths of a
; degree, a radian entry being converted on the way in by unit_apply, which is
; the reason hop_step_field converts nothing where the stock's three steppers
; do.
;
; NO INTERRUPT MASK, unlike hop_store_field (page0_hop.s). Nothing reads
; hop_table from interrupt context - grepping the rewrite's modules for
; hop_table finds it in this file, amplitude.s, remote.s, registers.s,
; page3_screens.s and page0_hop.s, every one of them foreground - and the
; stock's own wipe at le809 is a
; bare CLR ,X loop with no masking either. The reload that follows takes the
; DDS lock one slot at a time inside hop_write_slot, the way every other
; caller of it does, rather than holding it across all sixteen.
; ---------------------------------------------------------------------------
hop_table_defaults
                ; --- le809: every byte of the table, cleared --------------
                ldx     #hop_table
                ldb     #HOP_SLOTS*HOP_ENTRY_SIZE ; 128, where the stock's
hop_defaults_clear                                ; 240 is sixteen fifteens
                clr     ,x+
                decb
                bne     hop_defaults_clear

                ; --- le809 again: record+2 of all sixteen ---------------
                ; The stock's 240 bytes include every record's amplitude
                ; code, which this firmware keeps apart in hop_ampl_codes,
                ; so it is cleared with the table and not after it: the
                ; reload below sends it.
                ldx     #hop_ampl_codes
                ldb     #HOP_SLOTS*2            ; a word a slot
hop_defaults_codes
                clr     ,x+
                decb
                bne     hop_defaults_codes

                ; --- le820: record+10, the level's sign character ---------
                ldx     #hop_signs
                ldb     #HOP_SLOTS
                lda     #CHAN_SIGN_PLUS         ; $2B, driven above
hop_defaults_sign
                sta     ,x+
                decb
                bne     hop_defaults_sign

                ; --- $2677 and $267B: the FREQ column's unit --------------
                lda     #UNIT_HZ                ; the 2 both of them default
                sta     >hop_freq_unit          ; to

                ; --- $2671, $2674 and $267D: the three increments ---------
                ; copy3 ($D37D) of the zero at $EA58 into the first two, and
                ; CLRB / CLRA / STD into the third. Cleared one at a time
                ; rather than as a run: they are adjacent in scratch today and
                ; a walk of nine bytes would be a silent bug the day something
                ; is put between them.
                ldx     #incr_hop_freq
                bsr     hop_defaults_zero3
                ldx     #incr_hop_ampl
                bsr     hop_defaults_zero3
                ldx     #incr_hop_phase
                bsr     hop_defaults_zero3

                ; --- le861: dds_reload_all_slots ($E799) ------------------
                ; Sixteen calls to dds_write_channel ($DE2E), one per record,
                ; so the chip's own hop RAM holds the emptied table rather
                ; than the one that was there before. hop_write_slot is
                ; dds_write_channel here, and it codes nothing: each slot goes
                ; out with the zero amplitude code cleared just above, as
                ; $E799's sixteen $DE2E calls send the zero record+2 le809
                ; left. This used to code each slot's level against channel
                ; 0's standing range, which for an emptied table gave the
                ; same zero by arithmetic rather than by being the stock's.
                clrb                            ; le7a1: i = 0
hop_defaults_send
                pshs    b                       ; the index, across the call
                lbsr    hop_write_slot
                puls    b
                incb
                cmpb    #HOP_SLOTS              ; le7a3 CMPB #$10 / LBCC
                blo     hop_defaults_send
                rts

; ---------------------------------------------------------------------------
; hop_defaults_zero3 - one 24-bit increment cleared
;
;   entry: X = the three bytes
;   exit:  X advanced past them
;   uses:  X
;
; The tail of hop_table_defaults above, and nothing else calls it. A routine
; rather than three inline clears written out three times, because the three
; increments are three separate cells and not one run.
; ---------------------------------------------------------------------------
hop_defaults_zero3
                clr     ,x+
                clr     ,x+
                clr     ,x+
                rts

; ---------------------------------------------------------------------------
; hop_addr_send - the standing hop-RAM address out to the chip
;
;   uses:  A, B, X, Y
;
; write_reg15_nibble ($E7C4), and it was not in this image at all. The byte
; is the low four bits of the standing address ($E7CA-$E7D2 ANDA #$00 /
; ANDB #$0F) with bit 4 set when its flag argument is non-zero ($E7D4-$E7E3
; LDX >$0007,s / CMPX #$0000 / LBEQ / ORB #$10), written to register $15
; through dds_param_store ($DD9D) - one word, $15 being width 1.
;
; BOTH OF THE STOCK'S CALLERS PASS THE SAME TWO THINGS, which is why this
; reads them rather than taking arguments. reapply_all_channels ($C5B1) ends
; with `LDB >$24F4 / ... / LBSR write_reg15_nibble` at $C6AB-$C6BB, the flag
; being bit 5 of the high byte of event_flags ($2204) - bit 13 - tested at
; $C698-$C6AA; apply_hop_addr_and_repaint ($4803) on page 0 reads the same
; $24F4 and takes the same bit 13 at $480B-$481C. $24F4 is hop_index here and
; bit 13 of $2204 is MODE_FLAG_DIGITAL in mode_flags, which hop_func_port
; switches as $4984's row 0 switches $2204's.
;
; THE ADDRESS IS THE STORED ONE, NOT A TYPED ONE. What $24F4 holds is already
; the four-bit complement of the number on the screen - $6F78 stores it that
; way and hop_addr_put does the same arithmetic before calling here - so this
; masks and sends it and does not touch it.
;
; A COLD START SENDS $0F. channel_records_init ends with `LDB #$0F / STB
; >$24F4` ($C4F0's last instruction, lc5a9), mode_flags is clear, and
; channel_reapply_all's tail is this routine: one word, $15 <- $0F, the last
; of the instrument's 393 cold-start DDS words. This firmware sent none.
; ---------------------------------------------------------------------------
hop_addr_send
                ldb     >hop_index              ; $C6AB LDB >$24F4
                andb    #HOP_SLOTS-1            ; $E7D2 ANDB #$0F
                pshs    b
                lda     >mode_flags             ; $E7D4-$E7E3: bit 4 from the
                anda    #MODE_FLAG_DIGITAL      ; Digital Port flag, whose
                ora     ,s+                     ; value IS that $10, so it is
                                                ; ORed in as it stands
                tfr     a,b
                clra
                tfr     d,x                     ; X = the byte, as dds_write
                ldb     #DDS_HOP_ADDRESS        ; takes its value
                lbra    dds_write

; ---------------------------------------------------------------------------
; hop_send_high / hop_send_low - one six-bit field of a twelve-bit code
;
;   entry: X = the code, B = the register id
;   uses:  A, B
; ---------------------------------------------------------------------------
hop_send_high
                pshs    b                       ; the register id
                tfr     x,d                     ; D = the twelve-bit code
                lsra
                rorb
                lsra
                rorb
                lsra
                rorb
                lsra
                rorb
                lsra
                rorb
                lsra
                rorb                            ; D = code >> 6
                andb    #$3F
                puls    a                       ; A = the register id
                std     >dds_prog
                rts
hop_send_low
                pshs    b                       ; the register id
                tfr     x,d
                andb    #$3F                    ; bits 5:0
                puls    a
                std     >dds_prog
                rts


; ---------------------------------------------------------------------------
; The chip's register descriptor table, copied from the stock ROM at $DD73.
;
; One byte per register id, $00 to $29. The low six bits are the register's
; offset in the settings shadow; the top two, plus one, are its WIDTH CODE,
; which decides how many 6-bit fields the value is staged as and through
; which buffer latches:
;
;   width 1   one field
;   width 2   two fields, through latches 1 and 0
;   width 3   two fields, through latches 3 and 2
;   width 4   four fields, through latches 3, 2, 1 and 0
;
; The width is not cosmetic. A phase is width 3 and a level is width 2, so
; they stage through DIFFERENT latches, and writing a phase through the
; level's pair leaves the phase in the latches the next level commit will
; latch into the level register.
; ---------------------------------------------------------------------------
dds_descriptors
                fcb     $00,$01,$02,$03,$04,$05,$06,$07
                fcb     $C8,$CB,$CE,$D1                 ; $08-$0B frequency
                fcb     $54,$56,$58,$5A                 ; $0C-$0F level
                fcb     $9C,$9E,$A0,$A2                 ; $10-$13 phase
                fcb     $00
                fcb     $24,$25,$26,$27,$28,$29,$2A,$2B
                fcb     $2C,$2D,$2E,$2F,$30,$31,$32,$33
                fcb     $34,$35
                fcb     $F6                             ; $27
                fcb     $39,$3A                         ; $28-$29

; ---------------------------------------------------------------------------
; dds_width - how a register is staged
;
;   entry: B = the register id
;   exit:  A = the width code, 1 to 4; carry SET if the id does not exist
;   uses:  A, B, X
; ---------------------------------------------------------------------------
dds_width
                cmpb    #DDS_REGISTERS
                bhs     dds_width_unknown
                ldx     #dds_descriptors
                lda     b,x
                lsra                            ; the top two bits, plus one
                lsra
                lsra
                lsra
                lsra
                lsra
                inca
                andcc   #~CC_CARRY
                rts
dds_width_unknown
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; dds_write - send a value to one register, staged as the chip expects
;
;   entry: B = the register id, X = the value, up to sixteen bits
;   exit:  the register holds it; carry SET if the id does not exist and
;          nothing was written
;   uses:  A, B, X, Y
;
; THIS WAS BADLY WRONG and the comment above it stated the reason it was
; wrong as a fact. It did `STX >dds_prog`, which puts the VALUE'S HIGH BYTE
; into $0200 - the register-select port - and the value's low byte into
; $0201. The register number in B was used only to index the shadow and was
; never sent. The header said "the port has no addressing of its own here",
; which is false: $0200 IS the register select, and the same source already
; had three routines doing it correctly.
;
; Every write through here was therefore a malformed transaction that
; selected whatever register the value's high byte happened to name, and left
; the shared staging latches holding junk for the next legitimate commit to
; latch.
;
; Widths 1 to 3 are handled. Width 4 is a 24-bit value and does not fit a
; 16-bit argument; freq_program is the routine for those, and asking for one
; here is refused rather than silently truncated.
; ---------------------------------------------------------------------------
dds_write
                inc     >dds_lock               ; the player defers rather
                                                ; than writing into the middle
                                                ; of this staging sequence
                pshs    x,b                     ; the value and the id. X is
                                                ; saved because dds_width
                                                ; loads the descriptor table
                                                ; into it - which this did not
                                                ; do, so the value was gone
                                                ; before it was used and the
                                                ; fields came out of a table
                                                ; address.
                lbsr    dds_width               ; A = 1 to 4
                bcs     dds_write_unknown
                cmpa    #$04
                beq     dds_write_unknown       ; 24 bits: use freq_program

                ; The width decides the staging pair. It is in A - this
                ; tested B, which still held the register id, so the pair was
                ; chosen by the id and matched only by luck.
                pshs    a                       ; the width, at 0,s
                ; PSHS pushes X BEFORE B, so B lands lower: after "pshs x,b"
                ; B is at 0,s and X at 1,s-2,s, and this second push shifts
                ; both by one. The value is therefore at 2,s, not 3,s.
                ldx     2,s                     ; the value back
                DISABLE_INTERRUPTS              ; now: CC 0, width 1, id 2,
                                                ; value 3-4

                lda     1,s                     ; the width
                cmpa    #$01
                beq     dds_write_one

                lda     #DDS_BUFLAT1            ; width 2
                ldb     1,s
                cmpb    #$03
                bne     dds_write_pair
                lda     #DDS_BUFLAT3            ; width 3
dds_write_pair
                pshs    a                       ; the high slot, at 0,s
                tfr     x,d
                anda    #$0F                    ; twelve bits is all a
                lsra                            ; two-field register holds
                rorb
                lsra
                rorb
                lsra
                rorb
                lsra
                rorb
                lsra
                rorb
                lsra
                rorb
                andb    #$3F                    ; bits 11:6
                lda     ,s
                std     >dds_prog

                tfr     x,d
                andb    #$3F                    ; bits 5:0
                lda     ,s+
                deca                            ; the slot below it
                std     >dds_prog
                bra     dds_write_latch

; A WIDTH-1 REGISTER IS NOT STAGED. This staged the value into buffer latch
; 0 and then committed with clrb, so every width-1 register on the chip
; received $00 and the value never arrived - all eleven of dds_reset's global
; writes, both output mux registers, both waveform registers, and every
; dds_write in modulation.s.
;
; The stock settles it. dds_param_store's width-1 arm at $DDC3 is
;
;       ldb   ,x                the value
;       stb   [<$02,s]          into the shadow
;       bra   lddf0
;   lddf0:
;       lda   9,s               the register id
;       bsr   dds_write_word    ... with B STILL HOLDING THE VALUE
;
; while the width 2, 3 and 4 arms all reach that same tail through `clrb`.
; So the chip takes the DATA BYTE for a one-field register and the buffer
; latches for a wide one, and a width-1 value sent through the latches is
; simply thrown away.
dds_write_one
                tfr     x,d                     ; the value; a width-1
                lda     2,s                     ; register holds six bits, so
                std     >dds_prog               ; only B matters. Id in A,
                bra     dds_write_stored        ; VALUE in B, one write.

dds_write_latch
                lda     2,s                     ; the register id
                clrb                            ; the data byte IS ignored
                std     >dds_prog               ; here - the value arrived
                                                ; through the buffer latches,
                                                ; which is exactly why width 1
                                                ; must not come this way
dds_write_stored
                RESTORE_INTERRUPTS

                leas    1,s                     ; drop the width
                ldb     ,s                      ; the id, for the shadow
                lslb                            ; two bytes per register
                ldy     #dds_shadow
                leay    b,y
                stx     ,y
                puls    x,b
                dec     >dds_lock
                andcc   #~CC_CARRY
                rts
dds_write_unknown
                puls    x,b
                dec     >dds_lock               ; BOTH exits release it. Only
                                                ; releasing on the success
                                                ; path would leave the lock
                                                ; held for ever the first time
                                                ; a bad register id was asked
                                                ; for, and the sequence player
                                                ; would never run again.
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; dds_read - what a register was last set to
;
;   entry: B = the register number
;   exit:  X = the shadowed value; $0000 for a number out of range AND for
;          every register the shadow does not cover
;   uses:  A, B, X, Y
;
; The shadow, not the chip. There is no read path, and a routine that claimed
; to read the hardware would be lying to every caller.
;
; ONLY THE REGISTERS dds_write MAINTAINS ARE IN IT. The frequencies $08-$0B,
; the levels $0C-$0F, the phases $10-$13 and register $27 are staged straight
; to the port by dds_write_wide, ampl_program and phase_program, none of which
; touches the shadow - so this returns $0000 for all of them whatever the chip
; holds. The two service screens that display a register call this, so they
; show zero for those thirteen. Stated because a screen reading zero looks
; like a register that is zero.
; ---------------------------------------------------------------------------
dds_read
                cmpb    #DDS_REGISTERS
                bhs     dds_read_none
                lslb
                ldy     #dds_shadow
                leay    b,y
                ldx     ,y
                rts
dds_read_none
                ldx     #$0000
                rts

; ---------------------------------------------------------------------------
; WHAT WAS REMOVED FROM HERE, and why.
;
; dds_set_bits and dds_clear_bits read the shadow, masked, and wrote back.
; Nothing called either, and there is no register in the established map that
; wants a single bit changed - every one of them takes a whole value.
;
; dds_output_on and dds_output_off gated a channel's output through a chip
; register called DDS_OUT_MUX. No register of that name exists: the constant
; was invented and its value, 5, is one of the ids written only by the
; power-on flush.
;
; There IS an output source mux, and it is not one register but two: $22
; holds a three-bit source field for output ports 0 and 1 and $23 for ports 2
; and 3, written by set_dds_mux_field ($E5E8), with a field value of 4
; meaning nothing routed. That is routing, though - which channel feeds which
; socket - and not gating, which is BIT 2 of the channel
; latch, active low; hardware.inc carries the evidence.
;
; So the invented register was standing in for two real things at once and
; doing neither. Gating is the latch, and ampl_blank and ampl_unblank in
; amplitude.s do it correctly and are called.
;
; Four routines, no callers, and two of them describing hardware that is not
; there. The rule this tree states about leftovers is what removed them.
; ---------------------------------------------------------------------------

; ===========================================================================
; The waveform registers.
;
; A channel's waveform reaches the chip as a THREE-BIT FIELD, two channels to
; a register: $1D holds channels 0 and 1, $1E holds channels 2 and 3, the
; even channel in bits 0-2 and the odd one in bits 3-5.
;
; THE CHIP CODE IS NOT THE LABEL CODE. unit_code_select_head ($E38F)
; dispatches label codes 1 to 6 through the table at $E3DB to six arms that
; leave 3, 0, 2, 6, 5 and 1 respectively, so:
;
;   1 Sine  -> 3        4 dc    -> 6
;   2 Ramp  -> 0        5 Noise -> 5
;   3 Trngl -> 2        6 Sq    -> 1
;
; The reset default for both registers is $36, which is field 6 in both
; halves - dc on every channel, and dc is silent. That corroborates the
; mapping rather than merely being consistent with it.
;
; This firmware stored the waveform in the record, showed it on the screen,
; and wrote it nowhere, because common/formats.inc said which register
; selects a waveform was not established. It is $1D and $1E, and the writer
; was named unit_code_select_head in the symbol file the whole time.
; ===========================================================================

DDS_WAVE_01     equ     $1D             ; channels 0 and 1
DDS_WAVE_23     equ     $1E             ; channels 2 and 3
WAVE_FIELD_MASK equ     $07             ; three bits
WAVE_ODD_SHIFT  equ     3               ; the odd channel sits three up

wave_chip_codes                         ; indexed by label code 0 to 6
                fcb     $06             ; 0  no waveform: dc, which is silent
                fcb     $03             ; 1  Sine
                fcb     $00             ; 2  Ramp
                fcb     $02             ; 3  Trngl
                fcb     $06             ; 4  dc
                fcb     $05             ; 5  Noise
                fcb     $01             ; 6  Sq

; ---------------------------------------------------------------------------
; wave_program - put a channel's waveform on the chip
;
;   entry: A = the channel, 0 to 3; B = the label code, 0 to 6
;   exit:  carry SET if the code is not a waveform and nothing was written
;   uses:  A, B, X, Y
;
; A read-modify-write of the shadow, because the register holds two channels
; and writing it whole would set the other channel's waveform to whatever
; this one is.
; ---------------------------------------------------------------------------
wave_program
                cmpb    #LBL_SQUARE
                bhi     wave_program_bad        ; not a waveform code
                sta     >wave_channel

                ldx     #wave_chip_codes
                lda     b,x                     ; A = the chip's own code
                sta     >wave_code

                ldb     >wave_channel           ; which register, and which
                andb    #$01                    ; half of it
                beq     wave_program_even
                lda     #WAVE_ODD_SHIFT
                bra     wave_program_shift
wave_program_even
                clra
wave_program_shift
                sta     >wave_shift

                ldb     >wave_channel
                cmpb    #$02
                blo     wave_program_low
                ldb     #DDS_WAVE_23
                bra     wave_program_read
wave_program_low
                ldb     #DDS_WAVE_01
wave_program_read
                stb     >wave_reg
                lbsr    dds_read                ; X = the shadow's value

                ; Clear this channel's three bits, then put the code in.
                lda     #WAVE_FIELD_MASK
                ldb     >wave_shift
                beq     wave_program_masked
                lsla
                lsla
                lsla
wave_program_masked
                coma                            ; the bits to KEEP
                pshs    a
                tfr     x,d
                andb    ,s+

                lda     >wave_code
                pshs    b
                ldb     >wave_shift
                beq     wave_program_placed
                lsla
                lsla
                lsla
wave_program_placed
                adda    ,s+                     ; the other channel's bits
                tfr     a,b
                clra
                tfr     d,x

                ldb     >wave_reg
                lbsr    dds_write
                andcc   #~CC_CARRY
                rts
wave_program_bad
                orcc    #CC_CARRY
                rts

