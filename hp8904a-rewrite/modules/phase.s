; ===========================================================================
; phase.s - the phase of a channel relative to the others
;
; Phase is what makes this a multifunction synthesizer rather than four
; independent generators: two channels at the same frequency and a settable
; phase between them is the whole point of the instrument.
;
; THE STORED FORM is tenths of a degree, 0 to 3599. Sixteen bits, unsigned,
; with 3600 as the modulus - so 359.9 degrees is the largest setting and
; 360.0 does not exist, because it is 0.0.
;
; That is established rather than chosen: the stock commit path
; (a2u13_page0 $66B2) refuses anything above the constant at $EA5B, which is
; 3599, and keeps the value at record offset $15 in exactly these units.
;
; THE HARDWARE FORM is a twelve-bit count of 4096 per full turn, which is a
; resolution of 360/4096 = 0.0879 degrees. The stored value has 0.1 degree
; resolution, so the two are within a hair of each other and the conversion
; loses nothing an operator can see.
;
; WHY NOT RADIANS. The stock firmware keeps the phase TWICE - tenths of a
; degree at record +$15 and thousandths of a radian at +$17 - and converts
; between them with two fixed-point multiplies whenever either is set. That
; is two representations of one quantity, kept in step by hand, and the
; second is a rounded copy of the first: 0.001 radian is 0.0573 degrees, so
; the radian copy carries no information the degree copy lacks.
;
; This firmware keeps ONE. A phase keyed in radians is converted to tenths of
; a degree on the way in and never stored separately, so the two copies
; cannot disagree - which they can in the stock firmware, because each entry
; path writes its own field exactly and the other approximately.
; ===========================================================================

PHASE_MODULUS   equ     3600            ; tenths of a degree in a full turn
PHASE_MAX       equ     TOP_PHASE       ; the largest setting - 3599,
                                        ; declared in common/formats.inc so a
                                        ; paged screen can see it too
PHASE_DIV_STEPS equ     16              ; bits of quotient the division builds
PHASE_DDS_BITS  equ     12              ; counts per turn: 4096
PHASE_ROUND     equ     8               ; half of the 16 the shift discards

; ---------------------------------------------------------------------------
; phase_frac_3600 - the fraction of a turn, as a 16-bit binary fraction
;
;   entry: X = tenths of a degree, 0 to 3599
;   exit:  X = floor(value * 65536 / 3600)
;   uses:  A, B, X
;
; A sixteen-step restoring division. The result is the phase as a fraction of
; a full turn scaled to sixteen bits, so 0 is 0 degrees and $FFFF is one step
; short of 360.
;
; Why a division rather than a multiply by a reciprocal: 65536/3600 is
; 18.204..., not an integer, so a multiply by any fixed-point approximation
; carries an error that grows with the phase. At 359.9 degrees a Q8
; reciprocal is out by nearly a whole count of the hardware's resolution.
; The division is exact for every input in range and costs sixteen iterations
; of eight instructions, which at 2 MHz is under a tenth of a millisecond -
; against a six-millisecond range settle elsewhere in the same commit.
;
; The remainder can never overflow: it is below 3600 at the top of each
; iteration, so doubling it gives less than 7200, well inside sixteen bits.
; ---------------------------------------------------------------------------
phase_frac_3600
                stx     >phase_work
                clra
                clrb
                std     >phase_quotient
                clr     >phase_step
phase_div_loop
                lda     >phase_step
                cmpa    #PHASE_DIV_STEPS
                bhs     phase_div_done

                asl     >phase_work+1           ; remainder <<= 1
                rol     >phase_work
                asl     >phase_quotient+1       ; quotient <<= 1
                rol     >phase_quotient

                ldd     >phase_work
                cmpd    #PHASE_MODULUS
                blo     phase_div_next
                subd    #PHASE_MODULUS
                std     >phase_work
                ldd     >phase_quotient
                addd    #$0001
                std     >phase_quotient
phase_div_next
                inc     >phase_step
                bra     phase_div_loop
phase_div_done
                ldx     >phase_quotient
                rts

; ---------------------------------------------------------------------------
; phase_to_code - tenths of a degree to the chip's twelve-bit phase
;
;   entry: X = tenths of a degree, 0 to 3599
;   exit:  X = the twelve-bit code, 0 to 4095
;   uses:  A, B, X
;
; The sixteen-bit fraction, rounded to twelve bits. Adding eight before
; shifting right four rounds to nearest instead of truncating: without it
; every phase would sit up to one count low, and a pair of channels set to
; the same phase by different routes could differ by a count for no reason
; the operator could see.
;
; 4095 is the largest code the twelve bits hold, and the largest input, 3599
; tenths, gives 4095 - not 4094, as this said. 3599/3600 x 4096 is 4094.86 and
; the rounding takes it up, so the code is right and the sentence describing
; it was wrong:
;
;     python3 -c "q=(3599*65536)//3600; print((q+8)>>4)"   ->   4095
;
; AND THE CLAMP CANNOT FIRE, FOR ANY INPUT AT ALL. Four right shifts of a
; sixteen-bit pair leave at most $0FFF by construction, so `cmpd #$0FFF / bls`
; always takes the branch. It was kept on the grounds that "a phase code that
; overflowed into the bits above would be latched as part of a different
; field" - which this code does not protect against: for an input past a whole
; turn the `addd #PHASE_ROUND` WRAPS, and 3600 tenths comes out as code 0
; rather than as 4095.
;
;     python3 -c "q=(3600*65536)//3600; print(((q+8)&0xFFFF)>>4)"   ->   0
;
; It is left in place because it costs four bytes and its cost of being wrong
; is zero, while removing it would need a reader to re-derive the shift bound
; to be sure. What is NOT left in place is the claim that it protects
; anything. The protection is phase_set's phase_in_range check, which is
; where it belongs - before the arithmetic rather than after it.
; ---------------------------------------------------------------------------
phase_to_code
                lbsr    phase_frac_3600
                                                ; falls into phase_round_shift
phase_round_shift
                tfr     x,d
                addd    #PHASE_ROUND            ; round to nearest
                lsra                            ; and take the top twelve
                rorb                            ; bits: a four-place shift
                lsra                            ; right of the pair
                rorb
                lsra
                rorb
                lsra
                rorb
                cmpd    #$0FFF
                bls     phase_to_code_done
                ldd     #$0FFF
phase_to_code_done
                tfr     d,x
                rts

; ---------------------------------------------------------------------------
; phase_to_code_offset - the same, with the channel's modulator phase offset
;
;   entry: X = tenths of a degree, 0 to 3599; B = the channel, 0 to 3
;   exit:  X = the twelve-bit code
;   uses:  A, B, X, Y
;
; THE OFFSET IS ADDED AT SIXTEEN BITS, before the rounding, which is where the
; stock adds it. output_dac_update ($E4D0) loads the programmed phase from
; $24C5+2n, adds the offset at $24CD+2n, adds 8 and shifts right four - so an
; offset applied after the shift would lose its low four bits and round twice.
;
; The addition wraps at sixteen bits, and so does the stock's: $E51F does
; `STD [<$02,S]` into a 16-bit slot and $E4D0 adds two 16-bit words with ADDD.
; A phase plus its offset that goes past a whole turn comes out on the other
; side, which is what a phase should do.
; ---------------------------------------------------------------------------
phase_to_code_offset
                pshs    b                       ; the channel
                lbsr    phase_frac_3600         ; X = the sixteen-bit fraction
                ldb     ,s
                andb    #$03                    ; a wild channel must not
                aslb                            ; index outside the four words
                ldy     #phase_offset
                leay    b,y                     ; THE ADDRESS IS FIXED BEFORE
                                                ; D IS LOADED. This was
                                                ; `tfr x,d` followed by
                                                ; `addd b,y`, and TFR X,D
                                                ; overwrites B - so the index
                                                ; the two instructions above
                                                ; carefully masked to 0-3 was
                                                ; gone by the time it was
                                                ; used, and what indexed the
                                                ; array was the LOW BYTE OF
                                                ; THE PHASE FRACTION. Channel
                                                ; 0 with a fraction of zero
                                                ; came out right by accident,
                                                ; which is why it stood; every
                                                ; other channel read some
                                                ; other word of scratch, up to
                                                ; 255 bytes past the four the
                                                ; masking was there to keep it
                                                ; inside.
                tfr     x,d
                addd    ,y
                tfr     d,x
                puls    b
                lbra    phase_round_shift

; ---------------------------------------------------------------------------
; phase_offset_compute - work out the phase offset a channel carries
;
;   entry: B = the channel, 0 to 3
;   exit:  phase_offset for that channel holds it; nothing is sent
;   uses:  A, B, X, U
;
; NOTHING HERE HAD A PHASE OFFSET AT ALL, so a channel used as a modulator was
; programmed to the wrong phase. The stock keeps one per channel at $24CD+2n
; and sets it from four sites on a2u13_page0, all spelled as the bare address
; `lbsr $e5bf`: $6532 in commit_channel_frequency and $7F1F, $7F51 and $7FBF
; in set_channel_destination. When the channel's destination is a modulation
; one it stores scale_channel_value_by_6_or_7 ($E8A7)'s answer, and otherwise
; it stores zero.
;
; WHAT $E8A7 COMPUTES, read instruction by instruction and every input traced:
;
;   the value is THE WORD IN THE CHANNEL'S FREQUENCY REGISTER. $E8B4-$E8CC
;   select $2492, $2495, $2498 or $249B by channel, and those four addresses
;   are the register shadows: dds_register_descriptor ($DD3B) reads the
;   42-entry table at $DD73, whose entries for register ids $08-$0B are $C8,
;   $CB, $CE and $D1, giving shadow offsets $08, $0B, $0E and $11 from the
;   base $248A - which is $2492, $2495, $2498, $249B exactly. dds_param_store
;   ($DD9D) copies the three bytes it is handed into that slot at $DDD9-$DDEA
;   before it stages them, so the shadow is whatever was last SENT - and for
;   a modulator that is the frequency NEGATED, because both writers choose
;   copy_or_negate_to_channel_reg_08 ($E319) for a modulation code
;   (freq_as_sent in frequency.s names the sites). Executed on the stock,
;   2026-09-02: after 'DEB FM;' at 1 kHz, $2495 holds $FFD8F0 and $24CF
;   holds $FF15 - the top two bytes of 6 x $FFD8F0 = $5FF15A0 - not the
;   $00EA that 6 x $002710 would give. This routine used to multiply the
;   record's frequency; that was the wrong input for every modulator.
;
;   the multiplier is SEVEN when this channel's destination equals CHANNEL 3's,
;   and six otherwise. $E90C takes the record at $24F5 + 35*channel, reads the
;   16-bit field at +$21, and compares it with the word at $257F. The records
;   are 35 bytes: channel 3's is at $24F5 + 105 = $255E, and $255E + $21 is
;   $257F. So the comparison is against channel 3's own copy of the same field
;   - the destination code, which is what sum_channel_levels_for_dest ($BA2C)
;   reads from that offset. No instruction in any of the five images stores
;   to $257F, and that is because it is not a variable at all: it is a field
;   of channel 3's record, reached the way every other record field is. Here
;   that field is routed_dest, on both sides of the compare. After 'DED FM;'
;   on the stock channel 3's own offset $24D3 is $FEEE: 7 x $FFD8F0 =
;   $6FEEE90, and its top two bytes below the wrap.
;
;   the arithmetic is REPEATED ADDITION, six or seven times into a 24-bit
;   accumulator, and it wraps. $E935 primes a counter with the multiplier,
;   decrements, exits at zero and otherwise calls add24 ($D392) - so N gives
;   N-1 additions onto a copy that already holds one. $E955 then takes the TOP
;   TWO of the three bytes, which is the product shifted right eight.
;
; Reproduced with the wrap, because the wrap is the stock's answer and a
; wider multiply would give a different one.
;
; WHY six or seven, and why a frequency scales a phase, is NOT ESTABLISHED.
; The arithmetic is plain and every input is traced; the reason is not in the
; ROM, and inventing one would not make this more correct.
; ---------------------------------------------------------------------------
PHASE_MULT_SAME  equ    7               ; the multiplier when this channel's
PHASE_MULT_OTHER equ    6               ; destination matches channel 3's

phase_offset_compute
                pshs    b                       ; 0,s = the channel
                andb    #$03
                ldx     #routed_dest
                abx
                ldb     ,x                      ; B = record+$21
                lbsr    label_is_modulation     ; carry set for codes 7 to $0B
                bcc     phase_offset_none

                cmpb    >routed_dest+3          ; $E90C-$E927: seven when it
                bne     phase_offset_six        ; matches channel 3's
                lda     #PHASE_MULT_SAME
                bra     phase_offset_have
phase_offset_six
                lda     #PHASE_MULT_OTHER
phase_offset_have
                deca                            ; N gives N-1 additions onto
                pshs    a                       ; a copy that holds one
                leas    -3,s                    ; 0,s..2,s the word as sent;
                                                ; 3,s the count; 4,s the
                                                ; channel
                leax    ,s
                ldb     4,s
                lbsr    freq_as_sent            ; what the shadow holds
                ldd     ,s
                std     >phase_product          ; the copy that holds one
                lda     2,s
                sta     >phase_product+2
                leau    ,s
phase_offset_add
                ldx     #phase_product
                lbsr    add24                   ; wrapping at 24 bits, which
                dec     3,s                     ; is what the stock's six or
                bne     phase_offset_add        ; seven add24 calls do
                leas    4,s                     ; the word and the count
                ldd     >phase_product          ; the top two of three bytes
                bra     phase_offset_store      ; is the product >> 8
phase_offset_none
                clra                            ; not a modulator: no offset
                clrb
phase_offset_store
                pshs    d                       ; THE OFFSET GOES ON THE STACK
                                                ; FIRST. The index arithmetic
                                                ; below needs B, and reloading
                                                ; the low half from
                                                ; phase_product afterwards
                                                ; would read a stale byte on
                                                ; the not-a-modulator path,
                                                ; where D was cleared and
                                                ; phase_product never written.
                                                ; The channel is at 2,s now.
                ldx     #phase_offset
                ldb     2,s
                andb    #$03
                aslb
                abx
                puls    d
                std     ,x
                puls    b
                rts

; ---------------------------------------------------------------------------
; phase_offset_update - work out the offset a channel carries, and send it
;
;   entry: B = the channel, 0 to 3
;   uses:  A, B, X, Y, U
;
; set_channel_word_24cd ($E5BF) itself: it stores the word at $24CD+2n and
; calls output_dac_update ($E4D0), which re-sends register $10+n from
; $24C5+2n, the phase as it was last programmed, plus the new offset. The
; stock's four callers each hand it what $E8A7 returned, or zero.
; phase_apply sends the phase negated by the destination the channel is
; routed to NOW; a destination change, whose $E5BF write needs the phase as
; it stood under the old code, calls the two halves itself (modulation.s
; destn_tail), and commit_channel_frequency's $6532, where nothing has
; changed but the frequency, is this routine.
; ---------------------------------------------------------------------------
phase_offset_update
                pshs    b
                lbsr    phase_offset_compute
                puls    b
                lbra    phase_apply

; ---------------------------------------------------------------------------
; phase_offset_clear_all - no channel carries an offset, and all four resent
;
;   uses:  A, B, X, Y
;
; instrument_preset ($C6EA) does exactly this, looping channels 0-3 through
; set_channel_word_24cd ($E5BF) with zero. It is the whole of that routine's
; channel loop: not one instruction in $C6EA reaches a channel latch.
;
; AND $E5BF IS TWO HALVES, NOT ONE. It stores the word at $24CD+2n and then
; calls output_dac_update ($E4D0), which re-sends register $10+n. This stored
; the four words and sent nothing, so twelve of the instrument's 393
; cold-start DDS words were missing - three per channel, the two phase buffer
; latches and the commit. Measured with four channels fitted: the stock
; writes each of registers $10-$13 four times during its boot and this
; firmware wrote each of them three times, and the absent pass is this one.
;
; phase_apply is $E4D0 here. The stock re-sends the code it last programmed,
; from $24C5+2n plus the offset at $24CD+2n; this firmware keeps no
; last-programmed cell and derives the code from the record and the offset
; instead, which is the same phase - the writer of the stock's $24C5+2n is
; set_channel_phase ($E562), handed the record's phase by its callers.
;
; At a cold start every record's phase is zero and every destination is Off,
; so the twelve words are `03 00, 02 00, $10+n 00` per channel, exactly the
; instrument's. Away from one it is the offset that has just changed and the
; phase behind it is the record's either way.
; ---------------------------------------------------------------------------
phase_offset_clear_all
                clrb                            ; the channel: $C6EA's own
                                                ; loop counter, 0 to 3
phase_offset_clear_next
                pshs    b                       ; it does not survive the call
                ldx     #phase_offset
                aslb                            ; two bytes per channel, and
                abx                             ; ABX rather than an indexed
                                                ; store: B is the index AND
                                                ; would be the low half of the
                                                ; value, so `std b,x` would
                                                ; write the index into the
                                                ; cell it is indexing with
                clra
                clrb
                std     ,x                      ; $E5BF's store - the word at
                                                ; $24CD+2n, zero for all four
                                                ; of $C6EA's calls
                ldb     ,s                      ; the channel again
                lbsr    phase_apply             ; $E5BF's call to $E4D0: that
                                                ; channel's phase register
                                                ; sent again, with no offset
                                                ; in it now
                puls    b
                incb
                cmpb    #CHANNEL_MAX
                blo     phase_offset_clear_next
                rts

; ---------------------------------------------------------------------------
; phase_apply - send a channel's stored phase to the chip
;
;   entry: B = the channel, 0 to 3
;   uses:  A, B, X, Y
;
; program_channel_phase ($6635): the phase at record+$15, negated for the
; destination at record+$21 ($6674 LEAX <$21,X), then set_channel_phase
; ($E562). That destination is routed_dest - the stock's record+$21, which
; set_channel_destination stores only after routing ($7DF9) - and not
; CHAN_DEST: for a change to Off, CHAN_DEST still names the old code while
; the tail of that change runs, and a recall parks every channel with
; CHAN_DEST already holding the setup to come.
;
; Factored out of phase_set so that phase_offset_update can reach it. A
; changed offset has to be applied, and applying it by repeating phase_set's
; tail would have been the same transform written twice - including the
; modulation negation, which is exactly the kind of thing that gets copied
; once and then fixed in one place only.
; ---------------------------------------------------------------------------
phase_apply
                pshs    b
                andb    #$03
                ldx     #routed_dest
                abx
                lda     ,x                      ; A = record+$21
                puls    b
                                                ; falls into phase_apply_as

; ---------------------------------------------------------------------------
; phase_apply_as - send a channel's stored phase, negated for a given code
;
;   entry: A = the destination code the negation is decided by;
;          B = the channel, 0 to 3
;   uses:  A, B, X, Y
;
; WHY THE CODE IS AN ARGUMENT. The stock keeps the phase it last sent, as a
; sixteen-bit fraction, at $24C5+2n: set_channel_phase ($E562) stores
; frac_divide_3600 of its argument there at $E5A7 and output_dac_update
; ($E4D0) re-reads it at $E514. So when set_channel_word_24cd ($E5BF)
; re-sends the phase with a new offset in the middle of a destination change
; ($7F1F and $7F51), the fraction it sends is the one program_channel_phase
; stored LAST TIME - negated, or not, by the destination in force then - and
; only the final program_channel_phase at $7FD6 uses the new one. Executed
; on the stock, 2026-09-02: channel B at 90 degrees moved from FM to Out2
; writes $0330 $0200 $1100 - $C000, 270 degrees, the negated fraction, with
; the new offset of zero - and then $0310 $0200 $1100, $4000, 90 degrees
; un-negated. This firmware keeps no copy of the last fraction; it recomputes
; it from the record and the code the caller names, which is the same value
; whenever the phase was last sent under that code - and every path that
; sends a phase sends it under the routed code of the moment.
;
; CHANNEL 0 IS SENT AS ZERO WHILE PHASE HOP IS ON. The stock's
; set_channel_phase ($E562), the one routine that programs a channel's
; phase register, tests its channel argument for 0 at $E568-$E56F and bit 7
; of $2203 at $E573-$E57E - the bit dds_mode_param_set ($E69C) sets for
; control id 9, the Phase Hop enable, MODE_FLAG_PHASE here - and when both
; hold replaces the value argument with zero at $E588-$E58A (CLRB / CLRA /
; STD >$000A,s) before frac_divide_3600 and output_dac_update; the stored
; phase at record+$15 is not touched. The same here: the record keeps the
; operator's phase and the chip is told zero.
; ---------------------------------------------------------------------------
phase_apply_as
                pshs    a,b                     ; 0,s the code, 1,s the channel
                ldb     1,s
                andb    #$03
                lda     #CHAN_RECORD
                mul
                ldx     #channel_records
                leax    d,x
                ldy     CHAN_PHASE,x
                tst     1,s                     ; $E568-$E56F: channel 0...
                bne     phase_apply_own
                lda     >mode_flags             ; $E573-$E57E: ...while the
                bita    #MODE_FLAG_PHASE        ; Phase Hop bit is set...
                beq     phase_apply_own
                ldy     #$0000                  ; $E588-$E58A: ...is zero
phase_apply_own
                lda     ,s                      ; the code
                lbsr    phase_negate_if_modulator
                tfr     y,x
                ldb     1,s
                lbsr    phase_to_code_offset
                puls    a,b
                lbra    phase_program

; ---------------------------------------------------------------------------
; phase_negate_if_modulator - 3600 minus the phase, for a modulation dest
;
;   entry: A = the destination code, Y = the stored phase in tenths
;   exit:  Y = what the chip should be told
;   uses:  A, B, D
;
; A MODULATION DESTINATION NEGATES THE PHASE, modulo 360.
;
; That is the stock firmware's behaviour and it is established:
; program_channel_phase (a2u13_page0 $6635) calls is_modulation_destination on
; the record's destination and, for codes 7 to $0B, replaces a non-zero phase
; with 3600 minus it. Zero is left alone, which matters - 3600 minus zero is
; 3600, and 3600 is not a settable phase.
;
; WHY it negates is NOT ESTABLISHED. The arithmetic is plain and it is
; reproduced because this is the only description of what the hardware expects
; that exists; guessing a reason would not make the code more correct and
; might make it wrong.
;
; The STORED phase is what the operator keyed. Only the value sent to the chip
; is negated, so the screen shows what was asked for.
; ---------------------------------------------------------------------------
phase_negate_if_modulator
                tfr     a,b
                lbsr    label_is_modulation     ; carry set for 7 to $0B
                bcc     phase_negate_done
                lda     >special_flags          ; special function 3 reverses
                bita    #SPECIAL_REVERSE_MOD    ; the modulating waveform,
                bne     phase_negate_done       ; which is this negation not
                                                ; happening
                cmpy    #$0000
                beq     phase_negate_done       ; zero stays zero
                ldd     #PHASE_MODULUS
                pshs    y
                subd    ,s++
                tfr     d,y
phase_negate_done
                rts

; ---------------------------------------------------------------------------
; phase_in_range - is a phase settable?
;
;   entry: X = tenths of a degree
;   exit:  Z set if 0 to 3599, Z clear otherwise
;   uses:  none
;
; 3600 tenths is 360.0 degrees, which is 0.0 degrees, so it is refused rather
; than wrapped. Wrapping would be defensible arithmetic and poor instrument
; behaviour: an operator who keys 360 has made a mistake or misread a
; specification, and silently showing 0.0 hides both.
; ---------------------------------------------------------------------------
phase_in_range
                cmpx    #PHASE_MAX
                bhi     phase_in_range_no
                orcc    #CC_ZERO
                rts
phase_in_range_no
                andcc   #~CC_ZERO
                rts

; ---------------------------------------------------------------------------
; phase_program - write a channel's phase to the chip
;
;   entry: X = the twelve-bit code; B = the channel, 0 to 3
;   exit:  the chip holds it
;   uses:  A, B, X
;
; Two 6-bit fields and a latching write to $10+channel - the same SHAPE as
; the level path but NOT the same staging slots, which is the part that was
; wrong here.
;
; The chip's descriptor table at $DD73 gives each register id an offset and a
; width code: offset = byte & $3F, width = (byte >> 6) + 1. Ids $10-$13, the
; phase, carry $9C - width 3. Ids $0C-$0F, the level, carry $54 - width 2.
; And dds_param_store primes its descending slot counter to 3 for width 3 and
; to 1 for width 2, so a phase stages through buffer latches 3 and 2 while a
; level stages through 1 and 0.
;
; This used latches 1 and 0 for both. A phase written that way lands in the
; latches the level path uses, so the next level commit latched the phase's
; bits into the level register and the phase itself never arrived.
;
; Interrupts masked across all three writes, for the reason given in
; frequency.s: the staging latches are shared by every channel.
; ---------------------------------------------------------------------------
phase_program
                inc     >dds_lock               ; see nmi_handler: the
                                                ; sequence player defers a
                                                ; tick rather than writing
                                                ; into the middle of this
                pshs    b                       ; the channel. NOT "pshs
                DISABLE_INTERRUPTS              ; cc,b": DISABLE_INTERRUPTS
                                                ; pushes CC itself, so saving
                                                ; it here too left one byte on
                                                ; the stack and the RTS
                                                ; returned into I/O space.

                tfr     x,d
                anda    #$0F
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
                rorb
                andb    #$3F                    ; B = code[11:6]
                lda     #DDS_BUFLAT3
                std     >dds_prog

                tfr     x,d
                andb    #$3F                    ; B = code[5:0]
                lda     #DDS_BUFLAT2
                std     >dds_prog

                ldb     1,s
                andb    #$03
                addb    #DDS_PHASE_BASE
                tfr     b,a
                clrb
                std     >dds_prog

                RESTORE_INTERRUPTS              ; the CC the macro pushed
                puls    b
                dec     >dds_lock
                rts

; ---------------------------------------------------------------------------
; phase_set - validate a phase, store it, and apply it
;
;   entry: X = the channel record, Y = tenths of a degree, B = the channel
;   exit:  carry clear and the channel is at that phase;
;          carry set and NOTHING has changed, with last_error set
;   uses:  A, B, X, Y
;
; Check, store, apply - the same order as freq_set and ampl_set, for the same
; reason: a record that disagrees with the hardware is an invisible fault.
; ---------------------------------------------------------------------------
phase_set
                pshs    b,x,y
                tfr     y,x
                lbsr    phase_in_range
                bne     phase_set_refused

                ldx     1,s                     ; the channel record
                sty     CHAN_PHASE,x

                ; THE NEGATION AND THE PROGRAMMING ARE SHARED with
                ; phase_offset_update, which also has to send a stored phase
                ; after changing the offset it carries. Repeating this tail
                ; there would have been the same transform written twice, and
                ; the modulation negation is exactly the kind of thing that
                ; then gets corrected in one copy only.
                ldb     ,s                      ; the channel
                lbsr    phase_apply

                puls    b,x,y
                andcc   #~CC_CARRY
                rts
phase_set_refused                               ; l6749 ($6749): no store and
                puls    b,x,y                   ; no error number either
                orcc    #CC_CARRY
                rts
