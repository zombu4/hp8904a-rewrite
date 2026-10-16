; ===========================================================================
; amplitude.s - the channel output level, from volts to the hardware
;
; The amplitude path is the only one in this instrument where the number the
; operator keys is NOT what reaches the chip. Frequency is written verbatim;
; amplitude is converted, and the conversion is reproduced here exactly,
; because it is the only established mapping from volts to hardware that
; exists anywhere.
;
; WHAT THE FOUR-BIT FIELD DRIVES IS ESTABLISHED, and this file said it was
; not. The service manual names it on printed page 8-21, in the Analog
; Waveform Processing section:
;
;     "Attenuator 1 can be programmed for 0, 6, 12, or 24 dB attenuation."
;     "Attenuator 2 can be programmed for 0 or 48 dB."
;
; Four relay-switched pi-section attenuators of 6, 12, 24 and 48 dB, one per
; bit, binary-weighted in 6 dB units - so the field is an attenuation in
; steps of 6 dB from 0 to 90, and the exponent this code computes IS that
; attenuation. Service Sheets 3 and 4 name the four control nets AT3, AT2,
; AT1 and AT0 on J1 pins 25, 23, 21 and 19, and page 8-35's troubleshooting
; table gives a driver pin for each and its own key sequences that confirm
; the weights: 10 V to 625 mV is 24.08 dB, to 2.5 V is 12.04, to 5 V is
; 6.02, to 39 mV is 48.16.
;
; THE NETS ARE ACTIVE LOW - a logic low inserts a pad - which is why the
; firmware writes the field complemented, and it is worth knowing that the
; NET NUMBERING RUNS OPPOSITE TO THE WEIGHTS: AT0 is the 48 dB pad, not the
; 6 dB one. Nothing here indexes them individually, so that costs nothing;
; it would cost a great deal to anybody who assumed otherwise while probing.
;
; That does not change a byte of the arithmetic below, and it is worth being
; clear why it is still taken from the stock firmware rather than derived:
; the manual gives the attenuator VALUES, not the mapping from a keyed
; voltage to a mantissa and an exponent. The stock scale_to_dds_code ($D3EC)
; and output_latch_level_set ($B5EF) are the only statement of that mapping
; that exists, so the algorithm below is theirs, rewritten as legible code
; with the same arithmetic and not approximated.
;
; Knowing it is 6 dB a step does explain the shape: each step of the exponent
; halves the output, which is exactly what one binary place of a mantissa
; means, so the mantissa and the attenuator are one number split across two
; devices.
;
; THE REPRESENTATION. An amplitude leaves here as two pieces:
;
;   a 12-bit MANTISSA to the synthesis chip, DDS parameter $0C+channel
;   a  4-bit EXPONENT to the channel latch, bits 6:3, complemented
;
; which is a fifteen-bit floating-point level with an implied leading one.
; The mantissa always lands in $800-$FFF, so the leading bit carries no
; information and the useful precision is eleven bits - about one part in
; 2048, or 0.05%, which is finer than the four significant digits the front
; panel accepts.
;
; THE CONSTANT. $4C5005 = 5,001,221 is the normalisation reference, read from
; the stock image at $EE47. What physical quantity it represents is NOT
; ESTABLISHED; it behaves as full scale for the mantissa, and the entered
; value is expressed as a fraction of it.
;
; UNITS. Amplitude is entered in volts, millivolts or microvolts and in
; nothing else - there is no dB or dBm anywhere in the stock firmware, which
; was checked by scanning all five images for the strings. The keypad
; produces a 24-bit unsigned integer and the unit key chooses which decade
; the digits land on, so by the time a value arrives here the unit has
; already been folded in by unit_apply and the value is in MICROVOLTS.
;
; THERE IS NO UNIT BYTE ON THIS PATH. A scratch byte used to be stored by
; ampl_set, register_apply and hop_program - always UNIT_MICROVOLT, because
; that is what the record holds - and read by ampl_scale to skip the rounding
; "for radians", which was a misreading of the stock's test at $D473-$D47E:
; that loads the WORD AT +$1F of the channel record and compares it with 4,
; and +$1F is the record's WAVEFORM - the field digital_sequence_mode_setup
; writes 4 (dc) into at $7274-$7277 and page 0 tests for dc at $6603 and
; $726C - not the unit, which is the word at +13 that apply_amplitude_entry
; ($6547) reads for the ceiling. UNIT_RAD being 4 in this firmware's own
; numbering was a coincidence. The condition travels in ampl_wave_dc, set and
; cleared by ampl_level_raw around its ampl_scale call, so a caller that
; scales without a record gets the rounding it always had - and the byte
; that three routines stored and nothing read is gone from scratch.inc.
;
; THE WAVEFORM CHANGES THE CODE, and this file did not know it. The whole of
; scale_to_dds_code ($D3EC) after the division is arms on that +$1F word:
; for 4 (dc) it skips the rounding, halves the code a second time,
; complements it against $1000 unless the record's sign character at +$14 is
; '-', and masks it to twelve bits ($D47A-$D4FB); for 5 (Noise) it multiplies
; the code by $B6C9/65536 with fixmul_q16 ($D505-$D517). Every A2U12 path
; that then programs a socket level folds a dc code through
; rescale_channel_dacs ($BDD0-$BE3E) or its twin in reprogram_all_channels
; ($BCAA/$BCCE), and the digital sequence screen through program_dds_levels
; ($5306-$5343). All of that is ampl_level_raw and ampl_level_range below,
; run back to back by ampl_pair_common and ampl_rescale_dest, and the sign
; they need is ampl_signs -
; one byte per channel, the stock's record+$14, written by ampl_set_signed
; and brought back by a recalled register.
; ===========================================================================

; The normalisation reference, $4C5005 = 5,001,221, one byte at a time
; because every use of it is a 24-bit operation done in 8- and 16-bit pieces.
AMPL_REF_HI     equ     $4C
AMPL_REF_MID    equ     $50
AMPL_REF_LO     equ     $05
AMPL_REF_LOW16  equ     $5005            ; the middle and low bytes together

AMPL_MAX_HI     equ     TOP_AMPL_HI      ; $989680 = 10,000,000, the entry
AMPL_MAX_MID    equ     TOP_AMPL_MID     ; ceiling the stock firmware enforces
AMPL_MAX_LO     equ     TOP_AMPL_LO      ; at $EA62, for a channel going to a
                                         ; socket, in microvolts. Declared in
                                         ; common/formats.inc so the hop
                                         ; screen, which is on a page, can see
                                         ; the same number.

; THE AMPTD FIELD IS NOT ALWAYS A VOLTAGE. Which unit it carries, and so what
; its ceiling is, depends on where the channel is going - and this firmware
; used one ceiling for all of them, which is why a modulation depth had
; nowhere to go.
;
; The stock decides it in set_channel_destination ($78BF), whose unit table
; writes the AMPTD unit into the channel record every time the destination
; changes. Read off its arms: AM (code 7) gets unit $0B = '%'
; (destn_units_am $7E0B), FM (8) unit 2 = ' Hz', phase modulation (9) unit
; 3 = 'deg' (default_units_pm_deg $7E1B), DSB ($0A) unit 5 = ' V '
; (destn_units_dsb $7E23), and the four sockets unit 5 as well
; (default_units_output $7E33).
;
; So the depth never goes near the chip's own modulation-control registers -
; it IS the modulating channel's amplitude, in a different unit. That is the
; thing this firmware had wrong: it was claimed that a depth could not be
; implemented because nothing establishes the encoding of am_cont ($19) and
; fm_cont ($1A). Those registers are indeed only ever written by the power-on
; flush - but the depth does not travel through them, and one look at the
; destination's unit table says so.
PULSE_LEVEL     equ     $0555            ; what a Plse channel's level
                                         ; register is given, from the stock's
                                         ; level_constant_0555 ($C092)

AMPL_PCT_MAX    equ     1000             ; 100.0% in tenths, the constant at
                                         ; $EA6E that entry_limits_percent
                                         ; ($4F1F) installs as the ceiling
AMPL_HZ_MAX_HI  equ     $5B              ; $5B8D80 = 6,000,000 = 600 kHz in
AMPL_HZ_MAX_MID equ     $8D              ; 0.1 Hz units, the deviation
AMPL_HZ_MAX_LO  equ     $80              ; ceiling, from $EA55/$EA65
AMPL_DEG_MAX    equ     1799             ; 179.9 degrees, and NOT 3599.
                                         ;
                                         ; 3599 is a whole turn less a tenth,
                                         ; which is the ceiling on a channel's
                                         ; PHASE - a different field. A phase
                                         ; MODULATION deviation is bounded at
                                         ; half that, and the stock says so:
                                         ; entry_limits_degrees installs the
                                         ; constant at $EA68, which holds
                                         ; $000707 = 1799, as the entry
                                         ; ceiling whenever the unit code is
                                         ; 3 ('deg'), and three other sites
                                         ; install the same constant for the
                                         ; same unit.
                                         ;
                                         ; Taking the phase field's limit for
                                         ; the deviation field's is the same
                                         ; mistake as taking the tone mode's
                                         ; idle value for the digital mode's:
                                         ; a number that is right somewhere
                                         ; else.

AMPL_NORM_MAX   equ     15               ; the most normalising shifts allowed
AMPL_DIV_STEPS  equ     13               ; quotient bits built by the division
AMPL_CODE_MAX   equ     $0FFF            ; twelve bits and no more

; LATCH_RANGE is in common/hardware.inc with the other latch bits.

; ---------------------------------------------------------------------------
; ampl_scale - a 24-bit level to a 12-bit mantissa and a 4-bit exponent
;
;   entry: U = the 24-bit value, big-endian
;          ampl_wave_dc = non-zero when the value belongs to a dc
;          waveform, which skips the rounding. ampl_level_raw sets
;          it from the record and clears it again after this returns;
;          nothing else writes it (grep ampl_wave_dc modules/*.s), and
;          scratch_reset in boot.s clears SCRATCH_BASE up to live_setting
;          at power-on, +$29D included, so every other caller scales
;          with the rounding
;   exit:  X = the mantissa, $800 to $FFF
;          B = the exponent, 0 to 15
;   uses:  A, B, X
;
; Three stages, and each is worth understanding separately.
;
; NORMALISE. Shift the value left until it is at least the reference, or
; until fifteen shifts have been used. Each shift doubles the value and
; increments the exponent, so the pair (value, exponent) always represents
; the same quantity. The fifteen-shift limit is not arbitrary: the exponent
; field is four bits, so a sixteenth shift could not be recorded and the
; level would come out sixteen times too large.
;
; DIVIDE. Thirteen steps of restoring division by the reference. The first
; step always succeeds - the value is at least the reference by construction -
; so the quotient's top bit is always one and the result is in $1000 to $1FFF.
;
; ROUND AND HALVE. Add two if the low bit is set, then shift right, which
; rounds to nearest rather than truncating; then clamp. The result is in
; $800 to $FFF.
;
; THE ROUNDING IS SKIPPED FOR A dc WAVEFORM: $D47A CMPX #$0004 / $D47D BEQ
; on the record's +$1F word jumps over the ADDD #$0002 at $D487. This said
; "for values keyed in radians"; the head of this file says how that
; misreading arose. Why the stock does not round a dc code is NOT
; ESTABLISHED - it is reproduced, not explained.
; ---------------------------------------------------------------------------
ampl_scale
                ; --- take a working copy --------------------------------
                lda     ,u
                sta     >ampl_work
                ldd     1,u
                std     >ampl_work+1
                clr     >ampl_shift

                ; --- normalise ------------------------------------------
ampl_norm_loop
                lda     >ampl_shift
                cmpa    #AMPL_NORM_MAX
                bhs     ampl_norm_done          ; no exponent left to spend

                lda     >ampl_work              ; compare 24 bits against the
                cmpa    #AMPL_REF_HI            ; reference, high byte first,
                bhi     ampl_norm_done          ; stopping as soon as the
                blo     ampl_norm_shift         ; answer is settled
                lda     >ampl_work+1
                cmpa    #AMPL_REF_MID
                bhi     ampl_norm_done
                blo     ampl_norm_shift
                lda     >ampl_work+2
                cmpa    #AMPL_REF_LO
                bhs     ampl_norm_done          ; equal counts as normalised

ampl_norm_shift
                asl     >ampl_work+2            ; a 24-bit shift left, low
                rol     >ampl_work+1            ; byte first so each carry
                rol     >ampl_work              ; feeds the next
                inc     >ampl_shift
                bra     ampl_norm_loop
ampl_norm_done

                ; --- divide ---------------------------------------------
                clra
                clrb
                std     >ampl_quotient
                clr     >ampl_step
ampl_div_loop
                lda     >ampl_step
                cmpa    #AMPL_DIV_STEPS
                bhs     ampl_div_done

                asl     >ampl_quotient+1        ; make room for this bit
                rol     >ampl_quotient

                ldd     >ampl_work+1            ; trial subtraction, low 16
                subd    #AMPL_REF_LOW16         ; bits first so the borrow
                std     >ampl_trial+1           ; reaches the high byte
                lda     >ampl_work
                sbca    #AMPL_REF_HI
                sta     >ampl_trial
                bcs     ampl_div_next           ; it did not fit: bit stays 0

                sta     >ampl_work              ; it fitted: keep the
                ldd     >ampl_trial+1           ; difference and set the bit
                std     >ampl_work+1
                ldd     >ampl_quotient
                addd    #$0001
                std     >ampl_quotient

ampl_div_next
                asl     >ampl_work+2            ; bring down the next bit
                rol     >ampl_work+1
                rol     >ampl_work
                inc     >ampl_step
                bra     ampl_div_loop
ampl_div_done

                ; --- round to nearest, then halve -----------------------
                ; A dc CODE IS NOT ROUNDED. $D47A CMPX #$0004 / $D47D BEQ
                ; ld48c skips $D47F-$D48B - the test of the quotient's low
                ; bit and the ADDD #$0002 - when the record's waveform word
                ; is 4. This once tested a unit byte against UNIT_RAD
                ; instead, a branch no caller could take; the head of this
                ; file says how that came about. ampl_wave_dc is written by
                ; ampl_level_raw alone, set before and cleared after its
                ; ampl_scale call; scratch_reset in modules/boot.s clears
                ; SCRATCH_BASE up to live_setting (+$3B2) at power-on and
                ; ampl_wave_dc is at +$29D, below it. So it cannot be left
                ; standing for a caller that scales without a record.
                tst     >ampl_wave_dc
                bne     ampl_no_round
                lda     >ampl_quotient+1
                anda    #$01                    ; the bit about to be shifted
                beq     ampl_no_round           ; out; set means round up
                ldd     >ampl_quotient
                addd    #$0002
                std     >ampl_quotient
ampl_no_round
                lsr     >ampl_quotient
                ror     >ampl_quotient+1

                ; --- clamp to twelve bits -------------------------------
                ; An unsigned compare. The stock uses a signed one, which
                ; happens to agree because the quotient can never exceed
                ; $1FFF - but only by accident of the range, and an unsigned
                ; compare is right for an unsigned quantity whatever the
                ; range.
                ldd     >ampl_quotient
                cmpd    #AMPL_CODE_MAX
                bls     ampl_scale_done
                ldd     #AMPL_CODE_MAX
                std     >ampl_quotient
ampl_scale_done
                ldx     >ampl_quotient
                ldb     >ampl_shift
                rts

; ---------------------------------------------------------------------------
; THE LEVEL CODE - what the stock does to a voltage on its way to the chip
;
;
; ampl_scale gives the mantissa and the exponent of a voltage. This is what
; the stock does to that mantissa AFTER the division, read off the two
; routines every socket level passes through, in their order. The two
; stages are ampl_level_raw and ampl_level_range below, and
; ampl_rescale_dest runs them for every channel of a destination:
;
; scale_to_dds_code ($D3EC), on the record's waveform word at +$1F:
;   dc (4)     no rounding ($D47A-$D48B, done inside ampl_scale); a SECOND
;              halving, $D4A3 LSR 4,S / $D4A5 ROR 5,S, so the code is $400
;              to $7FF; then the record's sign character at +$14 ($D4DE
;              LEAX <$14,X / $D4E1 LDB ,X) is compared with '-' at $D4E7 and
;              unless it IS '-' the code becomes $1000 minus itself ($D4ED
;              LDD #$1000 / SUBD 4,S / STD 4,S); then ANDA #$0F / ANDB #$FF
;              at $D4F6-$D4F9 keep twelve bits. So a positive dc level is
;              $801-$C00, a negative one $400-$7FF, and zero is zero.
;   Noise (5)  fixmul_q16 ($D303) of the code and $B6C9 ($D505-$D517):
;              round(code x $B6C9 / 65536), the high word of the product
;              plus one when bit 15 of the low word is set ($D341 TST 4,S /
;              BPL / ADDD #$0001). $B6C9/65536 = 0.7140; what that scales
;              for is NOT ESTABLISHED and it is reproduced, not explained.
;   any other  the mantissa as it is.
;
; rescale_channel_dacs ($BD20), which channel_apply_and_propagate ($BE5C)
; runs for every channel of the destination after a level changes:
;   fold       when +$1F is 4 ($BDD0 CMPX #$0004) and the code is $800 or
;              more ($BDD9 CMPX #$0800 / LBLT), $1000 minus it, and a flag
;              ($BDE6-$BDF0). The positive dc code from above is thereby
;              taken back to $400-$7FF.
;   shift      by the difference between the destination's exponent and
;              this channel's ($BDF1-$BE01: sub_bytes_to_word, negate16,
;              shift_signed) - the exponent of the SUM of the levels sharing
;              the destination, which ampl_propagate computes and hands to
;              ampl_rescale_dest. The FM set shares its range through
;              register $16 instead and is ranged by ampl_fm_rescale; the
;              hop table, whose codes are applied against channel 0's
;              standing range, is shifted by hop_program in dds.s.
;   AM halve   for channel 0 ($BE02 LDB 2,S / CMPB #$00 / LBNE) while the
;              AM count $240D is not zero ($BE0A-$BE12): $BE1E LSR 5,S /
;              $BE20 ROR 6,S. The unhalved code is also stored as the
;              depth's full scale at $23BC ($BE19-$BE1D), and because that
;              store is after the shift above, the full scale is the code on
;              the COMMON exponent - not what scale_to_dds_code returned.
;              ampl_level_range writes ampl_carrier_code there and
;              ampl_depth_to_code reads it.
;   unfold     when the flag stands ($BE22-$BE29), $0FFF minus the code
;              ($BE2A LDD #$0FFF / SUBD 5,S / STD 5,S), and a result of
;              exactly $0800 becomes $0801 ($BE31-$BE3E).
;
; program_dds_levels ($5223), the digital sequence screen's own copy of the
; second routine, does the same fold at $5306-$5318, the same shift at
; $5326, the same unfold at $5333 and the same clamp at $5343 - without the
; AM halving - and passes channel 0 to both of its scale_to_dds_code calls
; (CLRB / SEX / TFR D,X before each), so both of its levels are scaled as
; dc against channel 0's record, which digital_sequence_mode_setup made dc
; at $7274-$7277 and mode_cold_init ($6FFF) made dc for channel 2 as well.
; The reprogram_all_channels ($BC3E) twin for the hop table folds at $BCAA
; and unfolds at $BCCE the same way.
;
; So for a positive dc level the code that reaches the chip is $0FFF minus
; the halved mantissa, never below $0801, and for a negative one it is the
; halved mantissa itself, $400 to $7FF: the register is offset binary about
; $800, and the polarity is the chip's convention, taken from the firmware.
; The one-count difference between $1000-c (what program_dds_levels writes
; for its LARGER level, the raw scale_to_dds_code output at $5361-$5371)
; and $0FFF-c (what every fold-and-unfold path writes) is the stock's own.
;
; THE TWO STAGES ARE TWO ROUTINES, because the hop table needs them apart.
; ampl_level_raw is scale_to_dds_code - the division, the dc arm and the
; Noise arm - and returns the code and the exponent as the stock returns
; them through [$0018,S] and B. ampl_level_range is the fold, the shift, the
; AM halving and the unfold of rescale_channel_dacs from $BDD0.
; ampl_rescale_dest runs them back to back with the shift $BDF1 computes
; and the carrier halving decided from the counted AM modulators.
; hop_program runs them with the shift reprogram_all_channels applies at
; $BCB5-$BCC1 and with the halving off, which is what that routine's
; instruction stream has: $BC3E-$BD1F contains no test of $240D.
;
; The sign is ampl_signs[channel], the stock's record+$14, and anything but
; '-' counts as positive - exactly the $D4E7 test. scratch_reset in boot.s
; clears SCRATCH_BASE up to live_setting (+$3B2) at power-on, so the array
; at +$298 starts as zeros, and zero is not '-'; register_recall_copy puts a
; saved register's four bytes back over it, as the stock's 425-byte copy at
; page 0 $52B2 brings back +$14 with the rest of the record.
; ---------------------------------------------------------------------------
AMPL_SIGN_PLUS  equ     $2B             ; '+' and '-', the two characters
AMPL_SIGN_MINUS equ     $2D             ; the stock keeps in record+$14 and
                                        ; tests at $D4E7 (CMPB #$2D)
AMPL_NOISE_SCALE equ    $B6C9           ; the Noise multiplier at $D505
AMPL_CODE_FULL  equ     $1000           ; the complement base at $D4ED/$BDE6
AMPL_CODE_HALF  equ     $0800           ; the fold threshold at $BDD9
AMPL_CODE_HALF1 equ     $0801           ; what an unfolded $0800 becomes


; ---------------------------------------------------------------------------
; ampl_pair_raw - one channel's level as scale_to_dds_code returns it
;
;   entry: B = the channel, 0 to 3
;   exit:  X = the twelve-bit code, B = the exponent, 0 to 15
;   uses:  A, B, X, Y, U
;
; The record, its sign and ampl_level_raw, which is all $5223's two $D3EC
; calls are ($52A7 and $52E5): NO fold, NO shift and NO unfold. Those come
; after, and in the stock they are applied to the SECOND code only.
;
; This replaced ampl_level_code, which ran ampl_level_range behind
; ampl_level_raw with a shift of zero. That is not the same routine: with a
; shift of zero the fold and the unfold do not cancel - a dc code of $0800 or
; more becomes $1000-c and then $0FFF-($1000-c), which is c-1 - and the
; digital screen's levels are dc. $5223's first code goes from $D3EC to
; $E478 untouched, so this does too. Its other caller, ampl_program_half, now
; goes through $C069 like the stock, so nothing was left needing the old one.
; ---------------------------------------------------------------------------
ampl_pair_raw
                pshs    b                       ; the channel
                lbsr    ampl_fm_record          ; X = its record
                pshs    x                       ; 0-1,s record 2,s channel
                leau    CHAN_AMPL,x             ; U = its 24-bit level
                ldy     #ampl_signs
                ldb     2,s
                lda     b,y                     ; A = its sign, record+$14
                ldx     ,s                      ; X = the record again
                lbsr    ampl_level_raw          ; X = the code, B = exponent
                leas    3,s
                rts

; ---------------------------------------------------------------------------
; ampl_pair_common - the digital screen's two levels, as program_dds_levels
;                    ($5223) codes and writes them
;
;   entry: A = one channel, B = the other; the lower is the On level
;          ($5223's parameter 0) and the higher the Off level (parameter 2)
;   exit:  both level registers hold $5223's codes, and channel 0's range
;          latch stands at the first level's exponent
;   uses:  A, B, X, Y, U
;
; READ OUT OF $5223 AND THEN EXECUTED, because the reading this replaced was
; wrong in two places and it produced a level one count off. Logged at
; $531A, $5348 and $E478 on the emulator, 'APB 5 UV;' against a +140 uV On
; level: the stock writes $0C54 to parameter 0 and $0FDE to parameter 2,
; where this wrote $0C54 and $0FDF; 'APA 100 MV;' gave $0AE1 where this gave
; $0AE2.
;
;   WHICH LEVEL IS FIRST. $5238-$5267: sub24 of the two magnitudes sets $3CB8
;   to 1 only on a borrow, so the LARGER magnitude is first and a tie is the
;   On level. This used the smaller exponent, which agrees except at a tie.
;
;   THE FIRST LEVEL GOES THROUGH $C069. $52A2 calls it for channel 0 with the
;   first level copied into channel 0's record, before either $D3EC - and
;   for a dc record that is the fold and the unfold at no shift, which is not
;   the raw code: $0C55 goes out as $0C54. When the SECOND level is the On
;   level, $5361 (LDD 9,S / STD 7,S) sends the first code raw to parameter 2
;   instead, and parameter 0 takes the shifted second.
;
;   THE SECOND LEVEL is folded with no waveform test, shifted onto the first's
;   exponent - $531A LDA 4,S / $531C LDB 3,S / sub_bytes_to_word / negate16,
;   first minus second - and unfolded ($52F1-$5347).
;
; Channel 0's register is written before channel 2's, as $C069 and then the
; $E478 calls write them.
; ---------------------------------------------------------------------------
ampl_pair_common
                pshs    a,b                     ; 0,s one  1,s the other
                cmpa    1,s                     ; the lower channel is On
                bls     ampl_pair_ordered
                ldb     ,s
                lda     1,s
                sta     ,s
                stb     1,s
ampl_pair_ordered
                ldb     1,s                     ; 0,s On  1,s Off
                lbsr    ampl_fm_record
                tfr     x,y                     ; Y = the Off record
                ldb     ,s
                lbsr    ampl_fm_record          ; X = the On record; Y kept
                lda     CHAN_AMPL,x             ; $5238's sub24: the larger
                cmpa    CHAN_AMPL,y             ; magnitude first
                bhi     ampl_pair_on_first
                blo     ampl_pair_off_first
                ldd     CHAN_AMPL+1,x
                cmpd    CHAN_AMPL+1,y
                bhs     ampl_pair_on_first      ; a tie is the On level
ampl_pair_off_first
                ldb     ,s                      ; 0,s first  1,s second
                lda     1,s
                sta     ,s
                stb     1,s
                lda     #$01                    ; the second is the On level
                bra     ampl_pair_codes
ampl_pair_on_first
                clra                            ; the second is the Off level
ampl_pair_codes
                pshs    a                       ; 0,s flag  1,s first  2,s second
                ldb     1,s
                lbsr    ampl_pair_raw           ; $52E5's first $D3EC
                pshs    b
                pshs    x                       ; 0-1,s code1  2,s exp1
                                                ; 3,s flag 4,s first 5,s second
                ldb     5,s
                lbsr    ampl_pair_raw           ; the second $D3EC
                pshs    b
                pshs    x                       ; 0-1,s code2  2,s exp2
                                                ; 3-4,s code1  5,s exp1
                                                ; 6,s flag 7,s first 8,s second
                lda     5,s                     ; first minus second: $531A
                suba    2,s
                clrb                            ; no halving: $5223 has no
                ldx     ,s                      ; test of $240D
                lbsr    ampl_level_range_fold   ; $52F1-$5347
                stx     ,s
                tst     6,s
                bne     ampl_pair_write_on_second
                ; --- the second is Off: the first goes out through $C069 ---
                ldb     7,s
                lbsr    ampl_fm_record
                tfr     x,y                     ; its record gates the fold
                clra                            ; at no shift
                clrb
                ldx     3,s
                lbsr    ampl_level_range
                stx     3,s
                lda     5,s                     ; On (the first), then Off
                ldb     7,s
                ldx     3,s
                lbsr    ampl_pair_apply
                lda     5,s
                ldb     8,s
                ldx     ,s
                lbsr    ampl_pair_apply
                leas    9,s
                rts
ampl_pair_write_on_second
                ; --- the second is On: it takes the shifted code, and the
                ; first goes to parameter 2 raw ($5361) -------------------
                lda     5,s                     ; On (the second), then Off
                ldb     8,s
                ldx     ,s
                lbsr    ampl_pair_apply
                lda     5,s
                ldb     7,s
                ldx     3,s
                lbsr    ampl_pair_apply
                leas    9,s
                rts

; ampl_pair_apply - one level of the pair onto the chip, as $5223 puts it there
;   entry: A = the exponent, B = the channel, X = the code
;   uses:  A, B, X, Y, U
; Channel 0 goes through $C069 ($52A2), which writes its range latch at $C04C
; and its register; the other goes through dds_write_chan_param ($E478)
; alone, a register write and no latch. Driven 2026-09-17, 'DAPH 3 VL;' on
; the Digital Sequence screen: the instrument writes $0C00 and never $0E00,
; where ampl_level_apply for both put the exponent into channel 2's latch.
ampl_pair_apply
                tstb
                lbeq    ampl_level_apply        ; channel 0: $C069
                lbra    ampl_program            ; the other: $E478

; ---------------------------------------------------------------------------
; ampl_level_raw - scale_to_dds_code ($D3EC): the mantissa with its waveform arm
;
;   entry: U = the 24-bit level, X = the channel record, A = the sign
;          character, '-' ($2D) or anything else for positive
;   exit:  X = the twelve-bit code, B = the exponent, 0 to 15
;   uses:  A, B, X, Y
;
; What the stock's $D3EC returns before any caller folds it, arm by arm as
; the header above lists them: ampl_scale with the rounding skipped for dc,
; then the dc halving, sign and mask of $D4A3-$D4FB, or the Noise multiply
; of $D505-$D517, or neither. The record supplies the waveform word (+$1F,
; CHAN_WAVE here) and the caller supplies the sign, because the stock
; chooses the sign's source at $D4A7-$D4E2 - the hop record's +10 for
; channel 0 while amplitude hop is on, the channel record's +$14 otherwise -
; and that choice belongs to the caller that knows which path it is on.
; ---------------------------------------------------------------------------
ampl_level_raw
                pshs    a,x                     ; 0,s the sign, 1,s the record
                clr     >ampl_wave_dc
                lda     CHAN_WAVE,x
                cmpa    #LBL_DC
                bne     ampl_raw_scale
                inc     >ampl_wave_dc           ; dc: ampl_scale will not round
ampl_raw_scale
                lbsr    ampl_scale              ; X = mantissa, B = exponent
                clr     >ampl_wave_dc           ; consumed; see ampl_scale
                pshs    b                       ; the exponent
                pshs    x                       ; the code
                                                ; 0,s code  2,s exponent
                                                ; 3,s sign  4,s record
                ldy     4,s
                lda     CHAN_WAVE,y
                cmpa    #LBL_DC
                bne     ampl_raw_not_dc

                ; --- dc: halve again, sign, mask ($D4A3-$D4FB) -----------
                lsr     ,s                      ; $D4A3 LSR 4,S / $D4A5 ROR 5,S
                ror     1,s
                lda     3,s                     ; the sign the caller chose
                cmpa    #AMPL_SIGN_MINUS        ; $D4E7 CMPB #$2D / LBEQ ld4f4
                beq     ampl_raw_dc_mask
                ldd     #AMPL_CODE_FULL         ; $D4ED LDD #$1000 / SUBD 4,S
                subd    ,s                      ; / STD 4,S
                std     ,s
ampl_raw_dc_mask
                lda     ,s                      ; $D4F4-$D4FB: ANDA #$0F /
                anda    #$0F                    ; ANDB #$FF, twelve bits
                sta     ,s
                bra     ampl_raw_done

ampl_raw_not_dc
                cmpa    #LBL_NOISE
                bne     ampl_raw_done
                ; --- Noise: round(code x $B6C9 / 65536) ($D505-$D517) ------
                ldx     ,s
                ldd     #AMPL_NOISE_SCALE
                lbsr    mul16                   ; the 32-bit product
                ldd     >math_product           ; its high word...
                tst     >math_product+2         ; ...plus one when bit 15 of
                bpl     ampl_raw_noise_store    ; the low word is set: $D341
                addd    #$0001                  ; TST 4,S / BPL / ADDD #$0001
ampl_raw_noise_store
                std     ,s
ampl_raw_done
                puls    x                       ; X = the code
                puls    b                       ; B = the exponent
                leas    3,s                     ; the sign and the record
                rts

; ---------------------------------------------------------------------------
; ampl_level_range_fold - ampl_level_range with the fold taken on any waveform
;
;   entry, exit and uses: as ampl_level_range; Y is not read
;
; program_dds_levels ($5223) folds its second code with no waveform test -
; $52F1 LDX 7,S / CMPX #$0800 / LBLT l531a, $1000 minus it, the shift at
; $5326, $0FFF minus the result and $0800 clamped to $0801 - where
; rescale_channel_dacs ($BDD0) and reprogram_all_channels ($BC49) fold only a
; dc record's. ampl_pair_common is $5223's, so its second code takes this.
; ---------------------------------------------------------------------------
ampl_level_range_fold
                pshs    a,b
                pshs    x
                clra
                pshs    a                       ; ampl_level_range's frame,
                bra     ampl_range_fold         ; and straight to the fold

; ---------------------------------------------------------------------------
; ampl_level_range - fold, shift, halve and unfold a code for the chip
;
;   entry: X = the code from ampl_level_raw, Y = the channel record whose
;              waveform word gates the fold;
;          A = the signed shift count, the common exponent minus this
;              level's own - what the stock hands shift_signed ($FFA4) at
;              $BDFD and $BCC1, after negate16;
;          B = non-zero to halve the code, the carrier's while a modulator
;              is counted ($BE02-$BE21, on $240D - decided by the caller,
;              ampl_rescale_dest, which knows whose counter is down);
;              zero to skip it as $BC3E does
;   exit:  X = the code the level register takes; ampl_carrier_code holds the
;              pre-halving code when B was non-zero
;   uses:  A, B, X
;
; THE DEPTH'S FULL SCALE IS TAKEN HERE. $BE19 LDD 5,S / $BE1B STD >$23BC sits
; between the shift and the halving, inside the arm reached only for channel 0
; with the AM count up - so the word a modulation depth is a fraction of is
; the carrier's code ON ITS DESTINATION'S COMMON EXPONENT, not the code
; scale_to_dds_code returned. ampl_depth_to_code cannot recompute it from the
; record for that reason, and does not try: it reads ampl_carrier_code.
;
; rescale_channel_dacs ($BD20) from $BDD0 and reprogram_all_channels ($BC3E)
; from $BCA0, which are the same four steps: fold a dc code of $800 or more
; to $1000 minus itself and remember that ($BDD0-$BDF0, $BC93-$BCB4); shift
; it by the count ($BDFD, $BCC1 - shift_signed: zero does nothing, $FFAC
; CMPX #$0000 / BEQ; positive is ASLB / ROLA at $FFB8 that many times;
; negative is LSRA / RORB at $FFB0); halve the carrier while a modulator is
; present ($BE02-$BE21, absent from $BC3E); and if it was folded, $0FFF
; minus the code with $0800 clamped to $0801 ($BE22-$BE3E, $BCC6-$BCE3).
; ---------------------------------------------------------------------------
ampl_level_range
                pshs    a,b                     ; 0,s the shift  1,s carrier
                pshs    x                       ; 0,s code  2,s shift
                                                ; 3,s carrier
                clra
                pshs    a                       ; 0,s the fold flag, clear
                                                ; 1,s code  3,s shift
                                                ; 4,s carrier

                ; --- fold ($BDD0-$BDF0, $BC93-$BCB4) ------------------------
                lda     CHAN_WAVE,y             ; $BDD0 CMPX #$0004 on +$1F;
                cmpa    #LBL_DC                 ; $BC49 CMPX #$0004 on $2514
                bne     ampl_range_shift
ampl_range_fold
                ldd     1,s
                cmpd    #AMPL_CODE_HALF         ; $BDD9 CMPX #$0800 / LBLT:
                blt     ampl_range_shift        ; signed, as the stock's is
                ldd     #AMPL_CODE_FULL         ; $BDE6 LDD #$1000 / SUBD 5,S
                subd    1,s                     ; / STD 5,S
                std     1,s
                inc     ,s                      ; $BDED LDB #$01 / STB 3,S

                ; --- shift ($BDFD, $BCC1: shift_signed) ---------------------
ampl_range_shift
                lda     3,s                     ; the count: zero does nothing
                beq     ampl_range_shifted
                bmi     ampl_range_right
ampl_range_left                                 ; $FFB8 ASLB / ROLA
                asl     2,s
                rol     1,s
                dec     3,s
                bne     ampl_range_left
                bra     ampl_range_shifted
ampl_range_right                                ; $FFB0 LSRA / RORB
                lsr     1,s
                ror     2,s
                inc     3,s
                bne     ampl_range_right
ampl_range_shifted

                ; --- AM: the carrier's code is halved ($BE02-$BE21) ---------
                tst     4,s                     ; the carrier, while a
                beq     ampl_range_unfold       ; modulator is counted
                ldd     1,s                     ; $BE19 LDD 5,S / $BE1B STD
                std     >ampl_carrier_code      ; >$23BC - the depth's full
                                                ; scale, taken HERE: after the
                                                ; shift and before the halving,
                                                ; in the one arm the stock
                                                ; reaches only for channel 0
                                                ; with $240D counted, which is
                                                ; the same condition this
                                                ; flag carries
                lsr     1,s                     ; $BE1E LSR 5,S / $BE20 ROR 6,S
                ror     2,s

                ; --- unfold ($BE22-$BE3E, $BCC6-$BCE3) ---------------------
ampl_range_unfold
                tst     ,s
                beq     ampl_range_done
                ldd     #AMPL_CODE_MAX          ; $BE2A LDD #$0FFF / SUBD 5,S
                subd    1,s                     ; / STD 5,S
                std     1,s
                cmpd    #AMPL_CODE_HALF         ; $BE33 CMPX #$0800 / LBNE
                bne     ampl_range_done
                ldd     #AMPL_CODE_HALF1        ; $BE3A LDD #$0801 / STD 5,S
                std     1,s
ampl_range_done
                leas    1,s                     ; the flag
                puls    x                       ; X = the code
                leas    2,s                     ; the shift and the carrier
                rts

; ---------------------------------------------------------------------------
; ampl_unit_for_destn - which unit the AMPTD field carries
;
;   entry: B = the destination code
;   exit:  A = the unit code the field is in
;   uses:  A
;
; Straight from set_channel_destination ($78BF)'s unit table d7e78, arm by arm.
;
; THE COMMENT HERE USED TO SAY "everything that is not a modulation destination
; is a voltage, which covers the four sockets and Off". That was wrong about
; two of the six outcomes, and wrong in a way that had a consequence rather
; than being merely untidy. The stock writes $0F for Plse ($7E2B) and $0D for
; Off ($7E5D), and both are BLANK entries in the label table - the units
; sub-table d4fbe sends $0D, $0E and $0F to entry_cfg_unsettable ($4F27),
; which skips arming the entry field altogether. A channel on Plse or Off has
; no keyable amplitude. Calling them volts gave them the ten-million ceiling
; and let a level be typed for a destination the instrument refuses to arm.
;
; Not reproduced here: the stock gives Out1-Out4 unit $0E instead of 5 when the
; channel index is 0 AND the DSB counter $240E is non-zero ($7E33). That is a
; third blank code for a case this firmware has no counterpart to yet, and it
; is left alone rather than guessed at.
; ---------------------------------------------------------------------------
ampl_unit_for_destn
                cmpb    #LBL_AM
                bne     ampl_unit_try_fm
                lda     #UNIT_PERCENT           ; a depth
                rts
ampl_unit_try_fm
                cmpb    #LBL_FM
                bne     ampl_unit_try_phim
                lda     #UNIT_HZ                ; a deviation
                rts
ampl_unit_try_phim
                cmpb    #LBL_PHIM
                bne     ampl_unit_try_pulse
                lda     #UNIT_DEG               ; a phase deviation
                rts
ampl_unit_try_pulse
                cmpb    #LBL_PULSE
                bne     ampl_unit_try_off
                lda     #UNIT_PULSE             ; blank: nothing to type
                rts
ampl_unit_try_off
                cmpb    #LBL_OFF
                bne     ampl_unit_volts
                lda     #UNIT_OFF               ; blank as well
                rts
ampl_unit_volts
                lda     #UNIT_VOLT              ; a level, in microvolts
                rts

; ---------------------------------------------------------------------------
; ampl_in_range - is a 24-bit level within what this channel will accept?
;
;   entry: U = the 24-bit value, B = the destination code
;   exit:  Z set if acceptable, Z clear if too large
;   uses:  A, B, X
;
; THE CEILING DEPENDS ON THE UNIT, and this used to be a single constant. A
; channel set to AM carries a depth in tenths of a percent, and comparing that
; against ten million accepted 4,000% and everything below it.
;
; There is no floor in any unit: zero is a legitimate amplitude, and is how a
; channel is silenced without switching its output off.
; ---------------------------------------------------------------------------
ampl_in_range
                pshs    x                       ; THE CALLER'S X SURVIVES THIS.
                                                ; The percent and degree arms
                                                ; below load their ceiling into
                                                ; X, and ampl_set_store calls
                                                ; this between `ldx 3,s` and
                                                ; `std CHAN_AMPL,x` - so a
                                                ; depth or a phase deviation
                                                ; stored itself through
                                                ; AMPL_DEG_MAX, $0707, writing
                                                ; $070A and leaving the record
                                                ; untouched. The level never
                                                ; changed, nothing was raised,
                                                ; and a hardware address took
                                                ; the value. Found 2026-09-11
                                                ; by tracing every write of the
                                                ; commit: the sign landed and
                                                ; the value did not.
                lbsr    ampl_unit_for_destn     ; A = the unit
                cmpa    #UNIT_PULSE             ; a blank unit has no keyable
                beq     ampl_in_range_no        ; value at all: the stock does
                cmpa    #UNIT_OFF               ; not even arm the field
                beq     ampl_in_range_no
                cmpa    #UNIT_PERCENT
                beq     ampl_range_percent
                cmpa    #UNIT_HZ
                beq     ampl_range_hertz
                cmpa    #UNIT_DEG
                beq     ampl_range_degrees
                bra     ampl_range_volts

; ---------------------------------------------------------------------------
; ampl_in_range_uv - the same ceiling, without asking the destination
;
;   entry: U = the 24-bit value
;   exit:  Z set when it fits
;   uses:  A
;
; THE DIGITAL SEQUENCE'S TWO LEVELS COME IN HERE. They are microvolts by the
; screen they are on and not by the routing of the channel that carries them,
; which is what ampl_set_direct's header already says about the instrument's
; own path: enter_level_value ($4CDA) stores the value and the sign and runs
; program_dds_levels ($5223), and record+$21 is not read anywhere in it.
;
; Driven on the emulator 2026-09-12, both firmwares cold and every channel
; therefore routed Off: the stock takes +12345 uV on the On Lev field and
; shows +12.34 mV, and this firmware refused it with ERR_AMPL_RANGE - because
; ampl_unit_for_destn turned an Off destination into UNIT_OFF, which has no
; keyable value on the Channel Configuration screen and is not the question
; this screen is asking.
; ---------------------------------------------------------------------------
ampl_in_range_uv
                pshs    x                       ; the exits below pull it
ampl_range_volts
                lda     ,u                      ; microvolts
                cmpa    #AMPL_MAX_HI
                blo     ampl_in_range_yes
                bhi     ampl_in_range_no
                lda     1,u
                cmpa    #AMPL_MAX_MID
                blo     ampl_in_range_yes
                bhi     ampl_in_range_no
                lda     2,u
                cmpa    #AMPL_MAX_LO
                bhi     ampl_in_range_no        ; exactly the ceiling is fine
                bra     ampl_in_range_yes

                ; THE THREE MODULATION UNITS ALL FIT IN SIXTEEN BITS, so the
                ; top byte deciding it on its own is not a shortcut - a value
                ; with anything in bits 23:16 is already past every one of
                ; them and the 16-bit compare below would wrap.
ampl_range_percent
                ldx     #AMPL_PCT_MAX
                bra     ampl_range_16
ampl_range_degrees
                ldx     #AMPL_DEG_MAX
ampl_range_16
                lda     ,u
                bne     ampl_in_range_no        ; anything above 65535
                ldd     1,u
                pshs    x
                cmpd    ,s++
                bhi     ampl_in_range_no
                bra     ampl_in_range_yes

ampl_range_hertz
                lda     ,u                      ; 600 kHz in 0.1 Hz units
                cmpa    #AMPL_HZ_MAX_HI         ; needs all twenty-four
                blo     ampl_in_range_yes
                bhi     ampl_in_range_no
                lda     1,u
                cmpa    #AMPL_HZ_MAX_MID
                blo     ampl_in_range_yes
                bhi     ampl_in_range_no
                lda     2,u
                cmpa    #AMPL_HZ_MAX_LO
                bhi     ampl_in_range_no
ampl_in_range_yes
                orcc    #CC_ZERO
                puls    x,pc
ampl_in_range_no
                andcc   #~CC_ZERO
                puls    x,pc

; ---------------------------------------------------------------------------
; ampl_range_write - put the exponent into a channel's latch
;
;   entry: A = the exponent, 0 to 15; B = the channel, 0 to 3
;   exit:  the latch holds it in bits 6:3 and the range has settled
;   uses:  A, B, X
;
; The field is stored COMPLEMENTED. That is the hardware's convention, not a
; choice made here: the stock routine complements before shifting, and the
; shutdown path writes $0F - which, complemented, puts zeros in the field.
;
; ONE VALUE, ONE MEANING. This paragraph used to call the same written value
; "no attenuation" and "maximum attenuation, 90 dB" two clauses apart, and
; both cannot hold. The body settles it: the field is written as
; (15 - shift) << 3, where the shift is the normalising count from
; ampl_scale, so a SMALLER keyed value gives a LARGER shift and a SMALLER
; field. The field is therefore active low - a zero bit switches a pad IN -
; which is what this file already says at its head: "THE NETS ARE ACTIVE LOW".
;
; So $0F written, giving zeros in the field, is all four pads IN: maximum
; attenuation, which is what a shutdown path wants. "No attenuation" was the
; wrong half of the sentence.
;
; The six-millisecond delay afterwards is the range settling. It is timed by
; the MC6840, not by a loop, so it does not change with code layout - and it
; must not be removed: an amplitude written to the chip before the range has
; settled produces a transient at the output of up to full scale.
; ---------------------------------------------------------------------------
AMPL_SETTLE_MS  equ     6

ampl_range_write
                cmpa    #$0F                    ; clamp before complementing:
                bls     ampl_range_ok           ; a value above 15 would
                lda     #$0F                    ; otherwise wrap into the
ampl_range_ok                                   ; bits above the field
                ; AND THE VALUE IS NOT MASKED, because the instrument's is
                ; not. output_latch_level_set ($B5EF) clamps to $0F, COMs the
                ; whole 16-bit local at $B607 and shifts it left three - no
                ; mask anywhere - so for a level of $0F it passes $80 and for
                ; 0 it passes $F8: BIT 7 IS SET FOR EVERY LEVEL 0 to 15,
                ; because bit 4 of the complement is always 1 below 16 and
                ; three shifts put it at bit 7. port_latch_rmw ($DBA1) then
                ; ORs the value in WHOLE - LDB [<$04,s] / ANDA 6,s / ANDB 7,s
                ; / ORA >$0010,s / ORB >$0011,s - against the mask $78, so
                ; the bit lands in the latch and nothing clears it.
                ;
                ; MEASURED 2026-09-19, the two firmwares side by side on the
                ; path the operator takes - f1 into Channel Configuration,
                ; SHIFT+DOWN 3 ENTER, SHIFT+UP 3 ENTER: the instrument ends
                ; every output latch at $80 and this firmware ended every one
                ; at $00. An ANDA #$0F here kept the field tidy and left bit 7
                ; low for the whole run, where the instrument holds it high
                ; from the first level it programs.
                ;
                ; Bit 7 is one of the eight A2 U38 outputs that Table 8-2 puts
                ; on the output board - seven on the ULN2003A coil drivers and
                ; one on A3 U2 pin 11, the reverse-power flip-flop's clock,
                ; whose documented steady state on page 8-35 is HIGH. Which
                ; output carries this bit is not established; that it should
                ; carry what the instrument puts there is not in doubt.
                coma
                lsla                            ; the four bits to 6:3, and
                lsla                            ; bit 4 of the complement to
                lsla                            ; bit 7, as $B5EF does

                inc     >dds_lock               ; THE STORE AND THE CALL
                                                ; ARE ONE OPERATION. An
                                                ; NMI landing between
                                                ; them would leave this
                                                ; writing the sequence
                                                ; player's value into a
                                                ; channel latch; see
                                                ; channel_latch_rmw.
                sta     >latch_bits             ; the bits to write
                lda     #LATCH_RANGE            ; the bits this call owns
                lbsr    channel_latch_rmw
                dec     >dds_lock

                ldd     #AMPL_SETTLE_MS
                lbra    delay_ms

; ---------------------------------------------------------------------------
; ampl_set - validate a level, store it, and put it on the output
; ampl_set_signed - the same, with the level's sign
;
;   entry: X = the channel record, U = the 24-bit value, B = the channel;
;          ampl_set_signed also takes A = the sign character, '+' ($2B)
;          or '-' ($2D). ampl_set is ampl_set_signed with '+'.
;   exit:  carry clear and the channel is at that level, with its sign in
;          ampl_signs;
;          carry set and NOTHING has changed, with last_error set
;   uses:  A, B, Y
;
; THE SIGN IS PART OF A dc LEVEL. The stock keeps it as a character in the
; channel record at +$14: apply_amplitude_entry ($6547) stores the entry's
; sign $241E there at $6613 when the waveform is dc, enter_level_value
; ($4CDA) stores it through [$3CB2] at $4CF1 for the digital sequence's two
; levels, and program_dds_levels copies that into [$23BF]+$14 before each
; of its scale_to_dds_code calls. Both stores happen only once the value
; has been accepted - $6613 is past the error exit tested at $65CA, and
; $4CF1 is behind the $3CDC test at $4CE8 - which is why the sign waits in
; ampl_sign_req until the range check here has passed. What it does to the
; code is in ampl_level_raw. Every caller but the digital sequence screen
; commits through ampl_set, so their levels are positive, as they were.
;
; The order matters and is the same as freq_set's: check, store, then apply.
; A record holding a level the socket is not producing is worse than a
; refused entry, because nothing on the screen shows it.
;
; THE APPLY IS THE STOCK'S dispatch_channel_function ($C069), ampl_reapply
; below, which the destination change runs on its own: the record's unit
; word at +13 picks an arm of the $C163 table, and the arms there are
; those arms - the percent's apply_scaled_param_to_channel ($C0A7), the
; hertz's rescale_channels_to_common_exponent ($BAE3), the degrees'
; phase_units_to_dds ($C0DD), the blanks' zero, the pulse constant $0555,
; and for the volts arm_no_action ($C11E) into the shared tail lc181-lc1c3:
; channel 0 with amplitude hop on writes zero to its own register ($C1A1-
; $C1B2) and every voltage then goes through channel_apply_and_propagate
; ($BE5C) at $C1B4 - ampl_propagate, which sums the destination's levels,
; recodes every channel sharing it against the common exponent and writes
; the socket's range latch. The output blanking around a range change is
; inside that routine, on the socket's own relay ($BED2 and $C058), and the
; other arms write a mantissa without it, as the stock's do.
; ---------------------------------------------------------------------------
ampl_set_signed
                sta     >ampl_sign_req          ; the sign, committed below
                bra     ampl_set_go             ; once the value is accepted
ampl_set
                lda     #AMPL_SIGN_PLUS         ; no sign argument: positive
                sta     >ampl_sign_req
ampl_set_go
                pshs    b,x,u
                lbsr    ampl_set_store          ; check, store, sign
                bcs     ampl_set_refused
                ldb     ,s                      ; B = the channel, X = the
                lbsr    ampl_reapply            ; record: $C069's dispatch
                puls    b,x,u
                andcc   #~CC_CARRY
                rts
ampl_set_refused
                lda     #ERR_AMPL_RANGE
                sta     >last_error
                puls    b,x,u
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; ampl_set_direct - the digital sequence screen's level: checked, stored, and
;                   coded on its own, as program_dds_levels codes it
;
;   entry: X = the channel record, U = the 24-bit value, B = the channel,
;          A = the sign character, '+' ($2B) or '-' ($2D)
;   exit:  as ampl_set_signed
;   uses:  A, B, Y
;
; THE DIGITAL SCREEN'S LEVELS DO NOT GO THROUGH $C069. Its mark and space
; are enter_level_value ($4CDA) on page 2, which stores the value and the
; sign ($4CF1) and runs program_dds_levels ($5223) - the screen's own copy
; of the level arithmetic: scale_to_dds_code ($D3EC) against channel 0's
; record for each level, the dc fold at $5306-$5318, the unfold at $5333
; with the clamp at $5343, and dds_write_chan_param for each. Its one
; $C069 call ($52A2) is for channel 0 with the first level, which
; ampl_pair_common reproduces as that call's code rather than as a summing
; pass over the destinations. That matters because the digital mode's
; instrument_preset has every channel routed Off (the stock's $C5B1 sets
; each record+$21 to $10), and $BE5C for an Off channel writes zero ($BE8B):
; the mark keyed on this screen never reached the chip through ampl_set once
; ampl_set became $C069. This is the screen's own path: ampl_pair_common,
; which codes both of its levels against one exponent and applies both -
; ampl_set_signed being what every caller used before the $C069 dispatch was
; ported.
; $5326's shift count is settled - see ampl_pair_common, which is where the
; two levels are put on one exponent. ABI slot 79 for page 2, and it takes
; the OTHER of the pair in Y, because $5223 programs both in one call and the
; second code's shift needs the first's exponent.
; ---------------------------------------------------------------------------
ampl_set_direct
                sta     >ampl_sign_req
                pshs    y                       ; the other of the pair, BELOW
                                                ; the frame ampl_set_store
                                                ; reads at 3,s and 5,s - it
                                                ; clobbers Y, so this cannot
                                                ; wait, and it cannot go on
                                                ; top either
                pshs    b,x,u                   ; 0,s channel 1-2,s record
                                                ; 3-4,s value 5-6,s partner
                lbsr    ampl_set_store_uv       ; check, store, sign
                bcs     ampl_set_direct_refused
                lda     ,s                      ; A = the channel just set
                ldb     6,s                     ; B = the other of the pair
                lbsr    ampl_pair_common        ; BOTH, against one exponent
                puls    b,x,u
                leas    2,s                     ; the partner
                andcc   #~CC_CARRY
                rts
ampl_set_direct_refused
                lda     #ERR_AMPL_RANGE         ; ampl_set_refused's body,
                sta     >last_error             ; with the partner to drop
                puls    b,x,u
                leas    2,s                     ; LEAS leaves CC alone, and
                orcc    #CC_CARRY               ; the carry is set after it
                rts

; ---------------------------------------------------------------------------
; ampl_set_store - ampl_set's check and store, shared with ampl_set_direct
;
;   entry: the caller's frame: 0,s the channel, 1-2,s the record, 3-4,s the
;          value pointer, below this call's return address; ampl_sign_req
;          holds the sign
;   exit:  carry SET when the value is out of range for the destination,
;          nothing stored; carry CLEAR with the level in the record and the
;          sign in ampl_signs
;   uses:  A, B, X, Y, U
; ---------------------------------------------------------------------------
ampl_set_store
                ldx     3,s                     ; X = the record
                ldu     5,s                     ; U = the value

                ; THE CEILING COMES FROM THE DESTINATION, which is in the
                ; record this call already has in X. A channel set to AM
                ; carries a depth in tenths of a percent and a channel going
                ; to a socket carries microvolts; one ceiling cannot serve
                ; both, and using the microvolt one for all of them let a
                ; depth of 4,000% through.
                ldb     CHAN_DEST,x
                lbsr    ampl_in_range
                bne     ampl_set_store_refused
                bra     ampl_set_store_commit

; ---------------------------------------------------------------------------
; ampl_set_store_uv - the same check and store, in microvolts
;
; The digital sequence screen's entry. Its field is microvolts whatever the
; channel is routed to - see ampl_in_range_uv, which carries the comparison
; against the stock that settles it.
; ---------------------------------------------------------------------------
ampl_set_store_uv
                ldx     3,s                     ; X = the record
                ldu     5,s                     ; U = the value
                lbsr    ampl_in_range_uv
                bne     ampl_set_store_refused
ampl_set_store_commit
                ldd     ,u                      ; into the record first, so
                std     CHAN_AMPL,x             ; the screen and the hardware
                lda     2,u                     ; agree from here on
                sta     CHAN_AMPL+2,x
                ldb     2,s                     ; and the sign beside it -
                ldy     #ampl_signs             ; the stock's record+$14,
                lda     >ampl_sign_req          ; stored at $6613 and $4CF1
                sta     b,y                     ; once the value is accepted
                andcc   #~CC_CARRY
                rts
ampl_set_store_refused
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; ampl_reapply - a channel's stored level onto the chip, by its unit
;
;   entry: X = the channel record, B = the channel
;   uses:  A, B, X, Y, U
;
; dispatch_channel_function ($C069), given the channel and its record+10:
; the unit word at record+13 - derived here from the destination through
; ampl_unit_for_destn, as $78BF's $7E65 table derived it - picks an arm of
; the $C163 table, and the arms are below. No range check and no store:
; $C069 makes neither, and its callers on a destination change ($7A8B,
; $7B02, $7EA6, $7EB8) apply a level the record already holds - a Plse
; channel's, for one, which the entry path refuses to TAKE ($C163[14]'s
; constant is not typed) but which the change puts on the chip as $0555.
; ampl_set is the entry path: its check and store, then this.
;
; A DEPTH IS NOT A LEVEL, and this once scaled every unit as microvolts. See
; ampl_depth_to_code: the stock dispatches on the record's unit and sends a
; percent through its own arm, which scales it as a fraction of full scale
; and never writes the range latch.
; ---------------------------------------------------------------------------
ampl_reapply
                pshs    b,x                     ; 0,s the channel, 1-2,s the
                                                ; record
                leau    CHAN_AMPL,x             ; U = the level, record+10
                pshs    u                       ; 0-1,s the level 2,s the
                                                ; channel 3-4,s the record
                ldb     CHAN_DEST,x
                lbsr    ampl_unit_for_destn     ; A = the unit
                cmpa    #UNIT_PERCENT
                beq     ampl_set_as_depth
                cmpa    #UNIT_PULSE
                beq     ampl_set_as_pulse
                cmpa    #UNIT_OFF
                beq     ampl_set_as_silent
                cmpa    #UNIT_HZ
                beq     ampl_set_as_deviation
                cmpa    #UNIT_DEG
                bne     ampl_set_as_level

                ldu     ,s                      ; a phase deviation
                lbsr    ampl_deg_to_code
                ldb     2,s
                lbsr    ampl_program
                bra     ampl_reapply_done

ampl_set_as_silent
                ; A CHANNEL GOING NOWHERE IS PROGRAMMED TO ZERO, not to
                ; whatever was typed. Arm [12] of the $C163 table - index =
                ; unit - 1, so this is unit $0D, the blank an Off destination
                ; carries - is chan_param_zero_no_apply ($C0??), which calls
                ; dds_write_chan_param with ZERO and nothing else. The same
                ; is true of arms [7], [8], [9], [11] and [13], every one of
                ; which writes zero; only the volts arm, [4] arm_no_action,
                ; writes nothing at all, because the voltage path programs the
                ; level and its range separately.
                ;
                ; This fell through to ampl_set_as_level and programmed the
                ; typed value. The channel is not routed, so nothing came out
                ; of it - but the level register kept that value, and a
                ; destination changed afterwards would have started from it
                ; rather than from silence.
                ldx     #$0000
                ldb     2,s                     ; the channel
                lbsr    ampl_program
                bra     ampl_reapply_done

ampl_set_as_pulse
                ; A PULSE MODULATOR HAS A FIXED LEVEL. Arm [14] of the $C163
                ; table - level_constant_0555 ($C092), the handler for the
                ; blank unit a Plse destination carries - calls
                ; dds_write_chan_param with the constant $0555 and nothing
                ; else. So the channel is not silent and its level is not
                ; typed: it is that value.
                ldx     #PULSE_LEVEL
                ldb     2,s                     ; the channel
                lbsr    ampl_program
                bra     ampl_reapply_done

ampl_set_as_deviation
                ; AN FM DEVIATION RANGES EVERY FM CHANNEL AT ONCE. It is not
                ; this channel's value that decides its mantissa - it is this
                ; channel's value against the sum of all of them, because they
                ; share one exponent in DDS register $16. So the whole set is
                ; rescaled rather than this one programmed.
                lbsr    ampl_fm_rescale
                bra     ampl_reapply_done

ampl_set_as_depth
                ldu     ,s                      ; U = the depth
                ldx     3,s                     ; X = this channel's record -
                                                ; it is the MODULATOR, and
                                                ; ampl_depth_to_code needs its
                                                ; waveform for $BC17's Noise arm
                lbsr    ampl_depth_to_code      ; X = the twelve-bit code
                ldb     2,s                     ; B = the channel
                lbsr    ampl_program            ; the mantissa alone
                bra     ampl_reapply_done

ampl_set_as_level
                ; THE VOLTS ARMS' SHARED TAIL, lc181-lc1c3. arm_no_action
                ; ($C11E) is one LBRA to $C181, which tests the channel
                ; ($C181 LDX >$0008,S / CMPX #$0000) and bit 6 of $2203
                ; ($C189-$C194, amplitude hop) and, both holding, writes zero
                ; to channel 0's level register ($C1A1-$C1B2) - the chip
                ; takes channel 0's level from the hop RAM then - and in
                ; every case calls channel_apply_and_propagate ($BE5C) at
                ; $C1B4. This used to code the level against the channel's
                ; own exponent and write the channel's own latch; the stock
                ; codes every channel of the destination against the
                ; exponent of their SUM and writes the SOCKET's latch, and
                ; ampl_propagate is that routine. No counter is excluded: a
                ; level change is not a destination change ($7AB2).
                ldb     2,s
                bne     ampl_set_propagate
                lda     >mode_flags
                bita    #MODE_FLAG_AM
                beq     ampl_set_propagate
                ldx     #$0000                  ; $C1A1-$C1B2
                lbsr    ampl_program            ; B = 0, channel 0
ampl_set_propagate
                lda     #$FF                    ; no channel's counter is down
                ldb     2,s                     ; the channel
                lbsr    ampl_propagate          ; $C1B4: $BE5C(channel)
ampl_reapply_done
                leas    2,s                     ; the level pointer
                puls    b,x
                rts

; ---------------------------------------------------------------------------
; ampl_level_apply - range a channel, then put its code where the chip reads it
;
;   entry: X = the twelve-bit code, A = the exponent, B = the channel
;   exit:  the channel's latch holds the exponent, and either its level
;          register holds the code or - channel 0 while amplitude hop is on -
;          the sixteen hop slots have been rewritten against the new range
;   uses:  A, B, X, Y, U
;
; The tail of ampl_set_direct, the digital screen's own level path; a
; record's own level goes through ampl_propagate, whose member loop makes the
; same channel-0 test. rescale_channel_dacs ($BD20), which
; channel_apply_and_propagate ($BE5C) calls at $BF64, $BF75 and $BFAC, tests
; for each channel it rescales whether it is channel 0 ($BD5A LDB 2,S / CMPB
; #$00 / LBNE lbd74) and whether bit 6 of $2203 is set ($BD62 LDD
; >event_flags2 / ANDA #$00 / ANDB #$40 / CMPD #$0000 / LBEQ lbd74 - the LOW
; byte of the word at $2202, the bit dds_mode_param_set mirrors from the
; amplitude-hop control register, which MODE_FLAG_AM in mode_flags keeps
; here). When both hold, $BD77-$BD80 pass the common exponent and $BD82 LBSR
; reprogram_all_channels ($BC3E) rewrites the sixteen slots; then $BD87
; LBRA lbe50 goes to the loop step, so channel 0's OWN level register is not
; written on that path - the dds_write_chan_param call at $BE4B is skipped -
; because with amplitude hop on the chip takes channel 0's level from the
; hop RAM. Every other channel, and channel 0 with the bit clear, takes
; $BD74 LBRA lbd8d and is programmed as before.
;
; The stock reaches that test from every voltage path that goes through
; $C069 - its volt arms call $BE5C at $C1BE, and the DTMF apply_amplitude
; (page 1 $5F70) calls $C069 for channel 0 at $5FCD and for channel 2 at
; $600B. Those all reach it here through ampl_propagate. What reaches it
; HERE is the one path the stock also keeps outside $C069: the digital
; screen's, program_dds_levels ($5223), which has no $BE5C in it.
;
; THE RANGE GOES OUT FIRST here, as ampl_set says it must, and the exponent
; is then HANDED to hop_reprogram_all rather than left in the latch for it to
; read back. The stock writes its latch afterwards, at $C04C, from the same
; exponent it handed $BC3E at $BD77, and the end state is the same either way
; - the latch at the new range, the slots coded against it, channel 0's
; register untouched. What has changed is that the ordering is no longer
; load-bearing: nothing downstream reads the latch to find this number.
; ---------------------------------------------------------------------------
ampl_level_apply
                pshs    a,b,x                   ; 0,s the exponent, kept to be
                                                ; handed down; 1,s the channel
                                                ; 2-3,s the code
                lbsr    ampl_range_write        ; A = exponent, B = channel
                tst     1,s                     ; $BD5A-$BD5E: channel 0?
                bne     ampl_level_own
                lda     >mode_flags             ; $BD62-$BD6D: bit 6 of $2203
                bita    #MODE_FLAG_AM
                beq     ampl_level_own
                lda     ,s                      ; $BD77: the common exponent
                leas    4,s                     ; the channel and the code are
                                                ; not needed: $BD87 skips the
                                                ; register write
                lbra    hop_reprogram_all       ; $BD82
ampl_level_own
                leas    1,s                     ; the exponent, done with
                puls    b,x                     ; B = the channel, X = the code
                lbra    ampl_program            ; $BD8D onward, $BE4B

; ---------------------------------------------------------------------------
; ampl_program - write a 12-bit mantissa to a channel's level register
;
;   entry: X = the mantissa, 0 to $FFF; B = the channel, 0 to 3
;   exit:  the chip holds it
;   uses:  A, B, X
;
; Two 6-bit fields and a latching write, the same staging the frequency path
; uses but two fields instead of four, because the value is twelve bits
; rather than twenty-four:
;
;   select $01   data v[11:6]
;   select $00   data v[5:0]
;   select $0C+n data (ignored)   latch into channel n's level
;
; Interrupts are masked across all three for the reason given in
; frequency.s: the staging latches are shared by every channel, so a write
; that interleaves with another channel's produces a level belonging to
; neither, and the chip cannot be read back to detect it.
; ---------------------------------------------------------------------------

ampl_program
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

                tfr     x,d                     ; D = the twelve-bit value
                anda    #$0F                    ; only twelve bits are real
                lsra                            ; a six-place right shift of
                rorb                            ; the pair, done two bits at
                lsra                            ; a time
                rorb
                lsra
                rorb
                lsra
                rorb
                lsra
                rorb
                lsra
                rorb
                andb    #$3F                    ; B = v[11:6]
                lda     #DDS_BUFLAT1
                std     >dds_prog

                tfr     x,d
                andb    #$3F                    ; B = v[5:0]
                lda     #DDS_BUFLAT0
                std     >dds_prog

                ldb     1,s                     ; the channel
                andb    #$03
                addb    #DDS_LEVEL_BASE
                tfr     b,a
                clrb
                std     >dds_prog

                RESTORE_INTERRUPTS              ; the CC the macro pushed
                puls    b
                dec     >dds_lock
                rts

; ---------------------------------------------------------------------------
; ampl_depth_to_code - a modulation depth as a level-register code
;
;   entry: U = the 24-bit depth, in tenths of a percent, 0 to 1000
;          X = the MODULATING channel's record, for its waveform
;   exit:  X = the twelve-bit code, 0 to AMPL_CODE_MAX
;   uses:  A, B, X, Y, U
;
; WHAT THE STOCK DOES, read rather than guessed. dispatch_channel_function
; ($C069) reads the unit code out of the channel record at +13 and dispatches
; through the fifteen-entry table at $C163, index = code - 1. The voltages
; (5, 6, 7) land on arm_no_action ($C11E), which does nothing at all - a level
; in microvolts goes to the chip unscaled. Unit 11, the percent, lands on
; apply_scaled_param_to_channel ($C0A7), which calls level_scale_by_cal
; ($BB98): that DIVIDES THE VALUE BY 1000 with a sixteen-step shift-and-
; subtract, multiplies the fraction by the full-scale word at $23BC with
; fixmul_q16 ($D303), and writes the product to the channel's level register
; through dds_write_chan_param ($E478).
;
; So a depth is a FRACTION OF FULL SCALE with 1000 meaning 100.0%, which is
; exactly what the tenths-of-a-percent unit and its ceiling of 1000 imply.
;
; $23BC IS NOT CALIBRATION DATA, which had to be checked before relying on it -
; the routine's name says "by_cal". `grep 23bc firmware/src-generated/*.s`
; gives three lines in all five images: one write, in rescale_channel_dacs,
; and the two reads below. It is computed at run time starting from LDD #$1000
; - 4096, the twelve-bit DAC's full scale. Nothing reads it out of a
; calibration table.
;
; THE FULL SCALE IS THE CARRIER'S CODE, NOT 4095. That is the whole of
; $BB98 and it was got wrong here: the routine scaled by a flat 4095, so a
; depth on a carrier coded below full scale came out too large by
; 4095 / carrier_code. $BB98 reads:
;
;   depth >= 1000 ($3E8)   -> code = $23BC as it stands ($BBB1)
;   otherwise              -> code = fixmul_q16(depth/1000, $23BC) ($BBF7),
;                             the sixteen-step restoring divide at
;                             $BBB9-$BBF3
;   modulator is Noise (5) -> code = fixmul_q16(code, $B6C9) at $BC25-$BC35,
;                             read from the MODULATING channel's record,
;                             which is why that record is an argument here
;
; $23BC IS NOT RECOMPUTABLE FROM A RECORD, which is why it is a stored word
; here as it is in the stock rather than derived on the spot. The store is
; $BE19 LDD 5,S / $BE1B STD >$23BC in rescale_channel_dacs, and it sits AFTER
; the shift_signed at $BDF1-$BDFD - so the value is channel 0's code shifted
; onto its destination's COMMON exponent, which scale_to_dds_code alone does
; not produce and which nothing in a channel record determines. It sits
; BEFORE the halving at $BE1E, so it is the unhalved code. ampl_level_range
; writes ampl_carrier_code at exactly that point.
;
; THE ARITHMETIC, in sixteen bits throughout. depth x carrier is 22 bits and
; div16 takes a 16-bit dividend, so the stock's own shape is used: divide
; depth by 1000 into a Q16 fraction first - the numerator never exceeds 2000
; inside that loop, so every intermediate fits a word - then fixed-point
; multiply by the carrier's code and keep the high word.
;
; THE RANGE LATCH IS NOT TOUCHED. apply_scaled_param_to_channel writes the
; level register and nothing else - no attenuator write anywhere in it - so a
; depth is expressed entirely in the mantissa.
DEPTH_FULL_SCALE equ    1000            ; tenths of a percent for 100.0%

ampl_depth_to_code
                pshs    x                       ; the modulator's record, for
                                                ; the Noise arm below
                ldd     1,u                     ; the low sixteen bits; the
                                                ; ceiling is 1000 so the top
                                                ; byte cannot be significant
                cmpd    #DEPTH_FULL_SCALE       ; $BBAA CMPX #$03E8
                blo     ampl_depth_scale        ; $BBAD LBCS lbbb9
                ldx     >ampl_carrier_code      ; $BBB1: 100.0% is the carrier
                bra     ampl_depth_noise        ; itself, unscaled
ampl_depth_scale
                lbsr    ampl_q16_div1000        ; X = depth x 65536 / 1000
                tfr     x,d
                ldx     >ampl_carrier_code      ; $BBF7 LDY >$23BC
                lbsr    ampl_fixmul_hi          ; X = round(depth*carrier/1000)
ampl_depth_noise
                ldy     ,s                      ; the modulator's record
                lda     CHAN_WAVE,y             ; $BC1E CMPX #$0005
                cmpa    #LBL_NOISE
                bne     ampl_depth_done
                tfr     x,d                     ; $BC25: one more fixmul, by
                ldx     #AMPL_NOISE_SCALE       ; $B6C9
                lbsr    ampl_fixmul_hi
ampl_depth_done
                leas    2,s                     ; the record
                rts

; ---------------------------------------------------------------------------
; ampl_q16_div1000 - a depth as a Q16 fraction of full scale
;
;   entry: D = the depth, 0 to 999
;   exit:  X = depth x 65536 / 1000
;   uses:  A, B, X
;
; The stock's restoring divide at $BBB9-$BBF3, ported in its own shape: test
; and subtract, then shift the numerator and the quotient, sixteen times.
; The numerator starts below 1000 and each pass leaves it below 1000 before
; the shift, so nothing here exceeds sixteen bits - which is the reason the
; stock does it this way instead of dividing a 32-bit product.
; ---------------------------------------------------------------------------
ampl_q16_div1000
                pshs    a,b                     ; the numerator
                ldd     #$0000
                pshs    a,b                     ; the quotient
                lda     #16
                pshs    a                       ; 0,s count 1,s quo 3,s num
ampl_q16_step
                ldx     3,s
                cmpx    #DEPTH_FULL_SCALE       ; $BBD1 CMPX 6,S
                bls     ampl_q16_shift          ; $BBD3 LBLS: no subtract
                ldd     3,s
                subd    #DEPTH_FULL_SCALE
                std     3,s
                ldd     1,s
                addd    #$0001
                std     1,s
ampl_q16_shift
                asl     4,s                     ; $BBE4: numerator left
                rol     3,s
                asl     2,s                     ; $BBE8: quotient left
                rol     1,s
                dec     ,s
                bne     ampl_q16_step
                ldx     1,s
                leas    5,s
                rts

; ---------------------------------------------------------------------------
; ampl_fixmul_hi - fixmul_q16 ($D303)
;
;   entry: D and X = the two factors
;   exit:  X = round(D x X / 65536)
;   uses:  A, B, X, Y
;
; The high word of the product plus one when bit 15 of the low word is set,
; which is what $D33F-$D345 does with TST 4,S / BPL / ADDD #$0001. The same
; rounding ampl_level_raw's Noise arm already uses.
; ---------------------------------------------------------------------------
ampl_fixmul_hi
                lbsr    mul16                   ; 32 bits at math_product
                ldd     >math_product           ; the high word...
                tst     >math_product+2         ; ...plus one when bit 15 of
                bpl     ampl_fixmul_keep        ; the low word is set
                addd    #$0001
ampl_fixmul_keep
                tfr     d,x
                rts

; ---------------------------------------------------------------------------
; ampl_deg_to_code - a phase-modulation deviation as a level-register code
;
;   entry: U = the 24-bit deviation, in tenths of a degree, 0 to 1799
;   exit:  X = the twelve-bit code
;   uses:  A, B, X, Y
;
; THE STOCK'S ARITHMETIC, read off phase_units_to_dds ($C0DD), which is arm [2]
; of the $C163 table and so the handler for unit code 3, 'deg':
;
;       frac_divide_3600        value x 65536 / 3600
;       addd  #$0004            round
;       lsra/rorb three times   divide by eight
;       dds_write_chan_param    to the channel's level register
;
; It corroborates the deviation ceiling from the other side: 1799 tenths of a
; degree comes out as 4094, one short of the twelve-bit full scale of 4095. A
; ceiling of 3599 - which this firmware had until today - would have run the
; code past full scale and wrapped.
;
; IN SIXTEEN BITS. value x 65536 overflows a word, and 65536/3600 is exactly
; 4096/225, so with q and rem from value/225:
;
;       t    = q*4096 + rem*18 + (rem*46)/225
;       code = (t + 4) >> 3
;
; because 4096/225 = 18 + 46/225. The widest intermediate is q<<12 at 28,672,
; and rem*46 at 10,304. Checked against the stock's formula for every legal
; value, 0 to 1799: 0 differ.
DEG_SPLIT       equ     225             ; 65536/3600 = 4096/225
DEG_WHOLE       equ     18              ; 4096/225 = 18 + 46/225
DEG_FRAC        equ     46

ampl_deg_to_code
                ldx     1,u                     ; the low sixteen bits; the
                                                ; ceiling is 1799
                ldd     #DEG_SPLIT
                lbsr    div16                   ; X = q, D = rem
                pshs    b,a                     ; the remainder
                tfr     x,d                     ; q
                lslb                            ; q*4096, and q is at most 7
                rola                            ; so twelve shifts cannot
                lslb                            ; lose a bit
                rola
                lslb
                rola
                lslb
                rola
                lslb
                rola
                lslb
                rola
                lslb
                rola
                lslb
                rola
                lslb
                rola
                lslb
                rola
                lslb
                rola
                lslb
                rola
                pshs    b,a                     ; q*4096

                ldx     2,s                     ; the remainder again
                ldd     #DEG_WHOLE
                lbsr    mul16                   ; rem*18
                ldd     >math_product+2
                addd    ,s                      ; + q*4096
                std     ,s

                ldx     2,s                     ; the remainder
                ldd     #DEG_FRAC
                lbsr    mul16                   ; rem*46
                ldx     >math_product+2
                ldd     #DEG_SPLIT
                lbsr    div16                   ; X = (rem*46)/225
                tfr     x,d
                addd    ,s                      ; the whole of t
                leas    4,s                     ; drop both saved words

                addd    #$0004                  ; round, then divide by eight
                lsra
                rorb
                lsra
                rorb
                lsra
                rorb
                tfr     d,x
                rts

; ---------------------------------------------------------------------------
; ampl_norm_down - shift a 24-bit value right until it fits twelve bits
;
;   entry: U = the 24-bit value, big-endian
;   exit:  X = the twelve-bit mantissa, B = how many places it was shifted
;   uses:  A, B, X, U
;
; The stock's normalize_24bit ($D34B): load the value, count down from $0B,
; shift right (LSR/ROR/ROR) until the top sixteen bits are no greater than
; $000F - which is to say until the whole thing fits in twelve - and return
; the remaining count. This returns the SHIFTS MADE, which is $0B less that
; count: ampl_fm_rescale needs the shifts for its differences and subtracts
; them from FM_NORM_MAX for the register the stock writes the count to.
;
; This is NOT ampl_scale. That one normalises UPWARD, shifting left until the
; mantissa sits between $800 and $FFF, because a level wants all twelve bits
; of resolution. This one shifts DOWN, because what matters here is expressing
; several channels against ONE exponent and the largest of them decides it.
; ---------------------------------------------------------------------------
FM_NORM_MAX     equ     11              ; $0B, the stock's counter

ampl_norm_down
                lda     ,u                      ; a private copy: the caller's
                sta     >fm_work                ; value is not ours to shift
                ldd     1,u
                std     >fm_work+1
                clrb                            ; the shift count
ampl_norm_down_step
                cmpb    #FM_NORM_MAX
                bhs     ampl_norm_down_done
                lda     >fm_work                ; anything above twelve bits?
                bne     ampl_norm_down_shift
                lda     >fm_work+1
                cmpa    #$0F
                bls     ampl_norm_down_done
ampl_norm_down_shift
                lsr     >fm_work
                ror     >fm_work+1
                ror     >fm_work+2
                incb
                bra     ampl_norm_down_step
ampl_norm_down_done
                ldx     >fm_work+1              ; the low sixteen bits are the
                rts                             ; mantissa now

; ---------------------------------------------------------------------------
; ampl_fm_rescale - put every FM modulator on one shared range
;
;   uses:  A, B, X, Y, U
;
; AN FM DEVIATION IS NOT A PER-VALUE CONVERSION, which is why it outlasted the
; percent and the degree. The stock's arm for unit 2 is
; rescale_channels_to_common_exponent ($BAE3), and what it does is:
;
;   1. sum_channel_levels_for_dest ($BA2C) adds the 24-bit level of every
;      channel whose destination is 8 (FM) into a single accumulator
;   2. normalize_24bit ($D34B) reduces that sum to twelve bits and returns the
;      shift count it took
;   3. dds_write_reg16 ($E36F) sends normalize_24bit's return - its counter
;      $0B less the shifts it made ($D362-$D371) - to DDS register $16, which
;      the chip's own name table calls fm_rang - so the RANGE is shared
;   4. each FM channel is then normalised on its own, and its mantissa shifted
;      by the difference between its exponent and the common one, before going
;      to that channel's level register
;
; THE DIFFERENCE IS ALWAYS A RIGHT SHIFT, and that is worth stating because the
; stock reaches it through sub_bytes_to_word / negate16 / shift_signed and so
; looks as though it could go either way. It cannot: the sum includes every
; channel, so the sum is at least as large as any one of them, so its exponent
; is at least as large. common - own is never negative.
;
; THE LOOP STARTS AT CHANNEL 1, as the stock's does with LDB #$01. Channel 0 is
; the carrier - the thing being modulated - and is never one of the modulators
; being ranged.
;
; NO dc FOLD HERE, BECAUSE THE STOCK'S FM PATH HAS NONE. The fold - $BDD0's
; CMPX #$0004 on +$1F and what follows it - is in rescale_channel_dacs
; ($BD20), whose only callers are the three inside channel_apply_and_propagate
; ($BE5C) at $BF64, $BF75 and $BFAC, and an FM level never reaches it:
;
;   - the unit-2 arm of dispatch_channel_function's table at $C163,
;     arm_call_extbae3 ($C111), calls $BAE3 at $C116 and then LBRA lc1c3 at
;     $C11B - to the LEAS 4,S / RTS at $C1C3, past the $C1B4 call of
;     channel_apply_and_propagate that the volt arms reach through $C181;
;   - the destination path, set_channel_destination ($78BF) on page 0, calls
;     $BAE3 directly when the new destination is 8 and, for the $BE5C call at
;     $7B72, first asks is_modulation_destination ($77D9) at $7B5A - which
;     returns 1 for 8 ($77F9 CMPX #$0008 / LBEQ) - and takes the LBRA at
;     $7B65 to $7B77 over it.
;
; $BAE3-$BB97 itself reads the record's +$21 (the destination, CMPX #$0008)
; and +10 (the level) and nothing else: normalize_24bit ($D34B),
; sub_bytes_to_word ($FD8F), negate16 ($FE59), shift_signed ($FFA4) at $BB77
; and dds_write_chan_param ($E478). No +$1F, no +$14, no scale_to_dds_code.
; So the loop below shifts an FM level exactly as $BB45-$BB8D does and folds
; nothing, and adding a fold here would be inventing behaviour.
;
; What is NOT established: whether channel 0 can carry destination 8, which
; is the one way the DSB branch of $BE5C - its second rescale_channel_dacs
; call at $BF75 takes $2516, channel 0's destination, as the type - could
; hand the FM channels to $BDD0.
; ---------------------------------------------------------------------------
ampl_fm_rescale
                clr     >fm_sum                 ; sum every FM channel's level
                clr     >fm_sum+1
                clr     >fm_sum+2
                clrb
ampl_fm_sum_next
                cmpb    #CHANNEL_MAX
                bhs     ampl_fm_summed
                pshs    b
                lbsr    ampl_fm_record          ; X = the record
                ldb     CHAN_DEST,x
                cmpb    #LBL_FM
                bne     ampl_fm_sum_skip
                ldu     #fm_sum                 ; add its level in
                leay    CHAN_AMPL,x
                lbsr    ampl_add24
                bcc     ampl_fm_sum_skip
                ; THE SUM DID NOT FIT, and the carry out was thrown away here
                ; while the other caller of ampl_add24 - ampl_sum_add_in, forty
                ; lines below - has always read it. Three channels at the FM
                ; ceiling do it: ampl_range_hertz passes 6,000,000 per channel
                ; (AMPL_HZ_MAX_HI, 600 kHz in 0.1 Hz units) and three of those
                ; is 18,000,000 against $FFFFFF = 16,777,215.
                ;
                ; A WRAP IS THE WORST OF THE THREE ANSWERS. 18,000,000 wraps to
                ; 1,222,785, which is SMALLER than one channel's deviation, so
                ; ampl_norm_down returns a small shared exponent, every FM
                ; channel's mantissa is shifted down by too little, and the
                ; deviations come out far LARGER than the operator asked for.
                ; Saturating sends the exponent the other way: the mantissas
                ; are shifted down as far as this can express and the
                ; deviations come out smaller than asked, which is the safe
                ; direction for a signal going to somebody's equipment.
                ;
                ; IT DOES NOT MAKE THE CASE REPRESENTABLE, and nothing here
                ; can. The chip carries one 4-bit shared range and a 12-bit
                ; mantissa per channel, so the largest total this pair can
                ; express is $FFF shifted by FM_NORM_MAX = 8,386,560 - below
                ; three channels at the ceiling however the sum is computed.
                ; What this fixes is the wrap; the expressible limit is the
                ; instrument's and the stock has it too.
                lda     #$FF
                sta     >fm_sum
                sta     >fm_sum+1
                sta     >fm_sum+2
ampl_fm_sum_skip
                puls    b
                incb
                bra     ampl_fm_sum_next
ampl_fm_summed
                ldu     #fm_sum                 ; the shared exponent
                lbsr    ampl_norm_down
                stb     >fm_common

                lda     #FM_NORM_MAX            ; and out to the chip, once:
                suba    >fm_common              ; normalize_24bit ($D34B)
                tfr     a,b                     ; returns its counter, $0B
                clra                            ; less the shifts it made,
                tfr     d,x                     ; and $BB0D-$BB16 send THAT -
                ldb     #DDS_FM_RANGE           ; $0B for a sum already within
                lbsr    dds_write               ; twelve bits, 8 for one that
                                                ; took three shifts. The
                                                ; shifts themselves stay in
                                                ; fm_common for the arithmetic
                                                ; below, whose difference is
                                                ; the same either way round

                ldb     #$01                    ; the modulators, not the
ampl_fm_next                                    ; carrier
                cmpb    #CHANNEL_MAX
                bhs     ampl_fm_done
                pshs    b
                lbsr    ampl_fm_record
                ldb     CHAN_DEST,x
                cmpb    #LBL_FM
                bne     ampl_fm_skip

                leau    CHAN_AMPL,x
                lbsr    ampl_norm_down          ; X = mantissa, B = its own
                                                ; exponent
                negb                            ; B = common - own. There is
                addb    >fm_common              ; no SBA on this CPU, and it
                                                ; is never negative anyway -
                                                ; see the header.
                pshs    b                       ; the shift, then the channel
                tfr     x,d                     ; below it
                tst     ,s                      ; TESTED FIRST: a count of
                beq     ampl_fm_shifted         ; zero would spin the loop
ampl_fm_shift                                   ; below 255 times
                lsra
                rorb
                dec     ,s
                bne     ampl_fm_shift
ampl_fm_shifted
                leas    1,s
                tfr     d,x                     ; X = the ranged mantissa
                ldb     ,s                      ; the channel
                lbsr    ampl_program
ampl_fm_skip
                puls    b
                incb
                bra     ampl_fm_next
ampl_fm_done
                rts

; ---------------------------------------------------------------------------
; ampl_fm_record - one channel's record
;
;   entry: B = the channel
;   exit:  X = the record
;   uses:  A, B, X
; ---------------------------------------------------------------------------
ampl_fm_record
                andb    #$03
                lda     #CHAN_RECORD
                mul
                ldx     #channel_records
                leax    d,x
                rts

; ---------------------------------------------------------------------------
; ampl_add24 - add a 24-bit value into a 24-bit accumulator
;
;   entry: U = the accumulator, Y = the addend
;   exit:  the accumulator holds the sum, and CARRY IS SET if it did not fit
;   uses:  A, B
;
; Least significant byte first, so each carry feeds the next.
;
; THE CARRY OUT IS PART OF THE CONTRACT, not an accident of the last
; instruction. The final ADCA leaves it and the STA after it does not touch
; the C flag, so it reaches the caller - and both callers now read it:
; ampl_sum_add_in treats a carry as "over the reference" ($BA01 does the same)
; and ampl_fm_rescale saturates on it. Anything added here that changes C
; between that ADCA and the RTS breaks both.
; ---------------------------------------------------------------------------
ampl_add24
                lda     2,y
                adda    2,u
                sta     2,u
                lda     1,y
                adca    1,u
                sta     1,u
                lda     ,y
                adca    ,u
                sta     ,u
                rts

; ---------------------------------------------------------------------------
; ampl_sum_exceeds - a level, plus the levels it will share an output with,
;                    against a reference: the stock's channel_sum_exceeds_ref
; ampl_dest_sum    - the same sum, handed back instead of compared: what
;                    sum_channel_levels_for_dest ($BA2C) leaves at $23B9
;
;   entry: B = the channel whose destination is the type being summed for
;              (the stock's arg1, the record subscript at $B8D2-$B8E4)
;          X = a 24-bit value, most significant first (arg2, copied at $B905)
;          U = ampl_sum_exceeds: the 24-bit reference, most significant
;              first - the value the stock's $23B7 points at when
;              ref_value_below ($B8AD) runs;
;              ampl_dest_sum: three bytes the sum is written to
;   exit:  ampl_sum_exceeds: carry SET when the stock's routine returns
;          non-zero: the value plus the matching levels carried out of 24
;          bits, or came to more than the reference; clear when it returns 0.
;          ampl_dest_sum: [U] holds the sum, most significant first; carry
;          SET when it carried out of 24 bits (and [U] holds the wrapped sum)
;   uses:  A, X, Y - B and U come back as they went in
;
; ampl_dest_sum exists for channel_apply_and_propagate ($BE5C), which ranges
; channel 0 by the SUM of the levels sharing its destination: $BA2C walks
; the four records (lba45 CMPB #$04 / LBCC lbae0) and adds the +10 level of
; each whose +$21 equals its argument (CMPX >$0007,S / LBEQ lba6f; lbab1
; LEAX 10,X / add24 into $23B9), channel 0 with bit 6 of $2203 set adding
; find_max_channel_field ($E962)(4) instead (lba6f to lba8c). For channel 0
; as subject with the largest hop level as X, that is this walk: the subject
; is left out ($B934) and X stands in for it, and the matches are the same
; set - $BE5C's lbf07 arm adds the DSB-destined levels (its second $BA2C
; call at $BF2C with $000A) exactly when $B96A-$B972 would count them here.
;
; channel_sum_exceeds_ref ($B8CC), instruction by instruction:
;   - the type is the record's destination word, +33 of the 35-byte record
;     ($B8D2-$B8E4, array_element_address then LEAX <$21,x / LDX ,x). A
;     destination of $10 - Off, LBL_OFF here - returns 0 at once ($B8EB CMPX
;     #$0010 / $B8F1 CLR 12,s): a channel going nowhere is never over.
;   - the value is copied into a local ($B905 copy3) and, for destination 9
;     (phase modulation, LBL_PHIM), compared alone ($B915 CMPX #$0009 / $B91F
;     ref_value_below).
;   - otherwise ($B928-$BA17) every OTHER channel ($B934 CMPD >$0013,s skips
;     the subscript itself) is a match when its destination equals the type
;     ($B95E), or is $0A - DSB, LBL_DSB - while the type is channel 0's
;     destination ($B96A, $B972; 7,s holds $2516, channel 0's +33), or equals
;     channel 0's destination while the type is $0A ($B979, $B981). A match
;     adds its 24-bit level, +10 of its record ($B9DC-$B9EE, add24 at $B9F9),
;     except channel 0 while bit 6 of $2203 is set - amplitude hop on,
;     MODE_FLAG_AM here - which contributes the largest of the sixteen hop
;     levels instead ($B98D-$B9AA: find_max_channel_field ($E962) with 4,
;     the +7 field of the $2581 hop records, seeded from zero at $E971).
;     add24's carry out ends it with 1 ($B9CC, $BA01).
;   - the sum then goes through ref_value_below ($BA18-$BA25): sub24 ($D3C6)
;     of the reference minus the sum, whose borrow is the result.
;
; Its four call sites are $4AC1 and $4B1D in set_hop_function_enable ($4984),
; $4CF6 in store_hop_amptd ($4CD5) - channel 0 and the entry $221C, run in
; place of the plain ceiling while amplitude hop is on ($4CDB-$4CE9) - and
; $65C3 in apply_amplitude_entry ($6547). hop_value_in_range in page0_hop.s
; is the $4CF6 site, through ABI slot 74.
;
; THE FRAME, on the stack as the stock's is (its locals at 2,s-$0E,s):
;   0,s     the channel being walked
;   1,s     the type
;   2,s-4,s the sum, seeded with the value
;   5,s     which entry: 0 compares, 1 hands the sum back
;   6,s     B as given, the subscript
;   7,s-8,s U as given, the reference or the sum's home
; ---------------------------------------------------------------------------
ampl_dest_sum
                lda     #$01                    ; the sum goes back in [U]
                bra     ampl_sum_frame
ampl_sum_exceeds
                clra                            ; the sum is compared with [U]
ampl_sum_frame
                pshs    b,u                     ; the subscript and U
                pshs    a                       ; which entry
                leas    -5,s                    ; then the three locals above
                                                ; them
                lda     ,x                      ; $B905: the value seeds the
                sta     2,s                     ; sum
                lda     1,x
                sta     3,s
                lda     2,x
                sta     4,s
                ldx     #routed_dest            ; $B8D2-$B8E4: the subscript's
                ldb     6,s                     ; record+$21, routed_dest
                lda     b,x                     ; here, is the type
                sta     1,s
                cmpa    #LBL_OFF                ; $B8EB: Off is never over -
                bne     ampl_sum_not_off        ; and $BE5C never sums for it
                tst     5,s                     ; ($BE8B CMPX #$0010 writes the
                bne     ampl_sum_copy           ; zero and leaves), so the sum
                bra     ampl_sum_no             ; handed back is the value
ampl_sum_not_off                                ; alone
                cmpa    #LBL_PHIM               ; $B915: phase modulation is
                beq     ampl_sum_compare        ; the value alone
                clr     ,s                      ; $B928: channel 0 first
ampl_sum_next
                ldb     ,s
                cmpb    #CHANNEL_MAX            ; $B92C CMPB #$04
                bhs     ampl_sum_compare
                cmpb    6,s                     ; $B934: not the subscript
                beq     ampl_sum_skip           ; itself
                lbsr    ampl_fm_record          ; X = this channel's record;
                                                ; its MUL leaves B = channel
                                                ; times CHAN_RECORD, so
                ldb     ,s                      ; the channel is reloaded
                ldy     #routed_dest            ; $B955-$B95C: its +$21,
                lda     b,y                     ; routed_dest
                cmpa    1,s                     ; $B95E: the type itself
                beq     ampl_sum_add
                cmpa    #LBL_DSB                ; channel 0's +$21 is the
                bne     ampl_sum_other          ; 7,s. $B96A: DSB here...
                lda     1,s
                cmpa    >routed_dest            ; $B972: ...with the type
                beq     ampl_sum_add            ; channel 0's destination
                bra     ampl_sum_skip
ampl_sum_other
                cmpa    >routed_dest            ; $B979: channel 0's
                bne     ampl_sum_skip           ; destination here...
                lda     1,s
                cmpa    #LBL_DSB                ; $B981: ...with the type DSB
                bne     ampl_sum_skip
ampl_sum_add
                tst     ,s                      ; $B98D: channel 0...
                bne     ampl_sum_add_level
                lda     >mode_flags             ; $B992-$B99C: ...while
                bita    #MODE_FLAG_AM           ; amplitude hop is on...
                beq     ampl_sum_add_level
                lbsr    hop_ampl_max            ; $B9AA: ...adds the largest
                bra     ampl_sum_add_in         ; hop level
ampl_sum_add_level
                leay    CHAN_AMPL,x             ; $B9DC-$B9EE: its own level
ampl_sum_add_in
                leau    2,s                     ; the sum
                lbsr    ampl_add24              ; $B9F9 add24; ampl_add24's
                bcs     ampl_sum_yes            ; last ADCA leaves the carry
                                                ; out and its STA keeps it -
                                                ; $BA01: a carry out is over
ampl_sum_skip
                inc     ,s                      ; $BA0F: the next channel
                bra     ampl_sum_next
ampl_sum_compare
                tst     5,s                     ; ampl_dest_sum: no compare,
                bne     ampl_sum_copy           ; the sum goes home
                ldu     7,s                     ; $BA18 ref_value_below: the
                lda     2,u                     ; reference minus the sum,
                suba    4,s                     ; least significant first,
                lda     1,u                     ; and the borrow out is the
                sbca    3,s                     ; answer ($D3C6 returns $FF
                lda     ,u                      ; on a borrow)
                sbca    2,s
                bcs     ampl_sum_yes
ampl_sum_no
                leas    6,s
                puls    b,u                     ; neither touches the carry
                andcc   #~CC_CARRY
                rts
ampl_sum_copy
                ldu     7,s                     ; the caller's three bytes,
                lda     2,s                     ; most significant first, as
                sta     ,u                      ; $BA2C leaves $23B9
                lda     3,s
                sta     1,u
                lda     4,s
                sta     2,u
                bra     ampl_sum_no
ampl_sum_yes
                tst     5,s                     ; ampl_dest_sum: the wrapped
                beq     ampl_sum_over           ; sum still goes home, with
                ldu     7,s                     ; the carry saying so
                lda     2,s
                sta     ,u
                lda     3,s
                sta     1,u
                lda     4,s
                sta     2,u
ampl_sum_over
                leas    6,s
                puls    b,u
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; hop_ampl_max - the largest level in the hop table
; hop_field_max - the largest value one field holds across the sixteen slots
;
;   entry: hop_field_max: A = the field's offset in a slot, HOP_FREQ or
;          HOP_AMPL; hop_ampl_max is hop_field_max with HOP_AMPL
;   exit:  Y = that field of the slot holding the largest value, three
;          bytes most significant first
;   uses:  A, B, X, Y
;
; $E962's one argument selects the field: 6 is the +4 frequency ($E98E CMPX
; #$0006 / $E9A4 LEAX 4,x) and anything else the +7 level ($E9BA LEAX 7,x).
; set_hop_function_enable ($4984) calls it both ways - with 6 at $49E4 for
; the Freq Hop row and with 4 at $4AAD for the Amptd Hop row - and the hop
; screen on page 0 reaches hop_field_max through ABI slot 76 for both.
;
; find_max_channel_field ($E962) with its argument 4: the accumulator $24D5
; is seeded from the zero constant at $EA58 ($E96E-$E978 copy3), and for
; each of the sixteen $2581 records ($E97B-$E9ED, CMPB #$10) the +7 field
; ($E9A7-$E9BC, LEAX 7,x - the amplitude, which store_hop_amptd ($4CD5)
; fills at $4D2B-$4D4C) is subtracted from the accumulator with sub24
; ($E9BD-$E9CB) and copied over it on a borrow ($E9D2-$E9E5). Nothing is
; below zero, so slot 0's level stands in for the seed here: the walk starts
; with it as the largest and the first comparison, slot 0 against itself,
; keeps it. A pointer rather than a copy, because the largest level is in
; the table already and a copy would need three bytes of RAM.
; ---------------------------------------------------------------------------
hop_ampl_max
                lda     #HOP_AMPL               ; $E9BA LEAX 7,x: the level
hop_field_max
                tfr     a,b
                ldx     #hop_table
                abx                             ; slot 0's field, the largest
                leay    ,x                      ; so far
                ldb     #HOP_SLOTS              ; $E97D: sixteen
hop_ampl_max_next
                lda     2,y                     ; $E9BD-$E9CB: largest minus
                suba    2,x                     ; this slot, least
                lda     1,y                     ; significant first
                sbca    1,x
                lda     ,y
                sbca    ,x
                bcc     hop_ampl_max_keep       ; no borrow: not larger
                leay    ,x                      ; $E9D2-$E9E5: it is
hop_ampl_max_keep
                leax    HOP_ENTRY_SIZE,x        ; the next slot
                decb
                bne     hop_ampl_max_next
                rts

; ---------------------------------------------------------------------------
; ampl_hop_on - channel 0's level path once amplitude hop has been switched on
;   entry: mode_flags has MODE_FLAG_AM set
;   exit:  channel 0's level register holds zero and, unless its destination
;          is Off, the socket's range latch holds the exponent of the
;          destination's summed level - the largest hop level standing in
;          for channel 0 - and the sixteen slots are coded against it
;   uses:  A, B, X, Y, U
;
; set_hop_function_enable ($4984)'s Amptd Hop arm, once dds_mode_param_set
; has written $19 and set bit 6 of $2203 ($4ADF-$4AF0), calls
; dispatch_channel_function ($C069) at $4B53 with channel 0 and the zero
; constant $EA58 ($4AF2-$4AF5, $4B48-$4B51). Channel 0 cannot hold a
; modulation destination - set_channel_destination ($78BF) refuses one for
; it, error $65 - so its unit word at record+13 is a volts code, and arms
; [4]-[6] of the $C163 table are arm_no_action ($C11E), one LBRA to the
; shared tail lc181: channel 0 with the bit set writes zero to its own level
; register ($C1A1-$C1B2, dds_write_chan_param(0, 0)) and lc1b4 calls
; channel_apply_and_propagate ($BE5C) for channel 0 - ampl_propagate, whose
; member loop diverts channel 0 to the sixteen slots ($BD77-$BD87) exactly
; as rescale_channel_dacs does. Every counter stands as it is: nothing is
; leaving a destination here.
; ---------------------------------------------------------------------------
ampl_hop_on
                ldx     #$0000                  ; $C1A1-$C1B2: its own
                clrb                            ; register, zero
                lbsr    ampl_program
                lda     #$FF                    ; no counter excluded
                clrb                            ; channel 0
                lbra    ampl_propagate          ; $C1B4: $BE5C(0)

; ---------------------------------------------------------------------------
; ampl_present - is a destination held by any channel but one?
;
;   entry: A = the channel to leave out of the count, $FF for none;
;          B = the destination code
;   exit:  Z CLEAR when some channel other than A is routed to that code,
;          Z SET when none is; A and B come back as given
;   uses:  X
;
; THE STOCK'S PER-DESTINATION COUNTERS, read rather than kept. $2408-$2411
; hold one count per destination code - $240D AM, $240E DSB, $240F FM,
; $2410 PhiM, $2411 Plse, $2409-$240C Out1-Out4, $2408 Off - handed out by
; destination_use_count_addr ($782A); each is the number of records whose
; +$21 names the code, because set_channel_destination ($78BF) moves a
; channel's count with its +$21 ($7AB2 down for the old code, $7DF0 up for
; the new), with one interval between: from $7AB2 to $7B7A the old code's
; count is already down while the record still names it. This firmware
; keeps no counters - routed_dest IS +$21 - so a count is a scan of
; routed_dest, and that interval is the channel named in A: every level-side
; reader of a counter inside a destination change - rescale_channel_dacs'
; $240D test at $BE0A, channel_apply_and_propagate's $240E test at $BEED and
; its $240D test at $BFB9 - is called from the leave path with the leaving
; channel here, and from everywhere else with $FF.
;
; CHANNEL 0 IS INCLUDED IN THE SCAN. It cannot in practice be AM - the ROM's
; own error string says "Channel A can not modulate itself" - but excluding
; it would be a guard that depends on that refusal still working, and the
; sum in ampl_fm_rescale does not exclude it either.
;
; There was an ampl_am_present beside this: three instructions that called it
; with $FF and LBL_AM. Its one caller was ampl_level_code, which went when the
; digital screen's two levels stopped being coded one at a time - see
; ampl_pair_common - and a wrapper nothing reaches is a leftover.
; ---------------------------------------------------------------------------
ampl_present
                pshs    a,b                     ; 0,s the channel left out,
                ldx     #routed_dest            ; 1,s the code
                clra                            ; A walks the channels
ampl_present_next
                cmpa    ,s
                beq     ampl_present_skip       ; the one left out
                ldb     ,x
                cmpb    1,s
                beq     ampl_present_yes
ampl_present_skip
                leax    1,x
                inca
                cmpa    #CHANNEL_MAX
                blo     ampl_present_next
                puls    a,b                     ; PULS leaves CC alone
                orcc    #CC_ZERO                ; none: Z set
                rts
ampl_present_yes
                puls    a,b
                andcc   #~CC_ZERO               ; at least one: Z clear
                rts

; ---------------------------------------------------------------------------
; ampl_partner - which output board a destination code drives
;
;   entry: B = a destination code
;   exit:  B = 0 to 3 for Out1 to Out4, $FF for any other code
;   uses:  B
;
; port_code_to_channel ($C765): $000C, $000D, $000E and $000F give 0, 1, 2
; and 3, anything else $FF - the inverse of dds_write_chan_param's map from
; a channel to its register. channel_apply_and_propagate ($BE5C) asks it
; for the socket whose relay it mutes and whose range latch it writes; a
; modulation code has none, and DSB is asked with channel 0's code instead
; ($BEA2-$BEB4, $2516).
; ---------------------------------------------------------------------------
ampl_partner
                cmpb    #LBL_OUT1
                blo     ampl_partner_none
                cmpb    #LBL_OUT4
                bhi     ampl_partner_none
                subb    #LBL_OUT1
                rts
ampl_partner_none
                ldb     #$FF
                rts

; ---------------------------------------------------------------------------
; ampl_rescale_dest - recode every channel of a destination against one exponent
;
;   entry: A = the common exponent, B = the destination code, X = non-zero
;          when the carrier's code is to be halved (the stock's $240D not
;          zero, counted by the caller)
;   uses:  A, B, X, Y, U
;
; rescale_channel_dacs ($BD20), the routine channel_apply_and_propagate
; ($BE5C) runs at $BF64, $BF75 and $BFAC. It walks channels 0 to 3 ($BD2B
; CLR 2,S ... $BD30 CMPB #$04) and for each whose +$21 equals the code
; ($BD4D CMPX >$000F,S):
;
;   channel 0 with bit 6 of $2203 set ($BD5A-$BD6D) is diverted to
;   reprogram_all_channels ($BC3E) with the exponent ($BD77-$BD82) and its
;   own register is left unwritten ($BD87 LBRA lbe50). That is
;   hop_reprogram_all here, and the exponent is HANDED TO IT exactly as
;   $BD82 hands it. It used to be read back out of channel 0's latch shadow
;   instead, which meant writing that latch here first to put it there -
;   and the stock writes no latch at $BD77-$BD82 at all. It writes the
;   SOCKET's at $C04C afterwards, which is the same latch only while channel
;   0 sits on Out1; channel 0 routed to another socket with amplitude hop on
;   was the arrangement where the extra write showed, and there is no extra
;   write now.
;
;   every other member is scale_to_dds_code ($D3EC) of its own level ($BD8D-
;   $BDB6) - ampl_level_raw with the record's sign, record+$14 - and then the
;   four steps ampl_level_range carries: the dc fold ($BDD0-$BDF0), the
;   shift by the common exponent minus its own ($BDF1-$BDFD: the difference
;   negated, shift_signed - a right shift by however many places the sum's
;   exponent is below this level's, and never a left one, since the sum is
;   at least any one of its terms), the carrier's halving while AM is
;   counted ($BE02-$BE21, channel 0 only, on $240D), and the unfold ($BE22-
;   $BE3E), then dds_write_chan_param ($BE3F-$BE4B) - ampl_program.
;
; THE CARRIER'S CODE IS STORED, as the stock stores it. $BE19-$BE1D put the
; shifted, unhalved code into $23BC - the full scale level_scale_by_cal
; ($BB98) multiplies an AM depth by - and ampl_level_range does that at the
; same point, into ampl_carrier_code. It cannot be derived from a record
; instead: the shift at $BDF1-$BDFD has already been applied to it, and that
; count comes from the SUM of the destination's levels, which no single
; record holds.
; ---------------------------------------------------------------------------
ampl_rescale_dest
                pshs    a,b,x                   ; 0,s exponent  1,s code
                                                ; 2-3,s the halve flag
                clrb                            ; $BD2B: channel 0 first
ampl_rescale_next
                pshs    b                       ; 0,s the channel; 1,s the
                                                ; exponent 2,s the code
                                                ; 3-4,s the halve flag
                ldx     #routed_dest
                lda     b,x
                cmpa    2,s                     ; $BD4D: a member?
                bne     ampl_rescale_skip
                tstb                            ; $BD5A: channel 0...
                bne     ampl_rescale_own
                lda     >mode_flags             ; $BD62-$BD6D: ...with
                bita    #MODE_FLAG_AM           ; amplitude hop on
                beq     ampl_rescale_own
                lda     1,s                     ; $BD77-$BD82: the slots at
                lbsr    hop_reprogram_all       ; the common exponent, HANDED
                                                ; DOWN - $BD82 passes $BC3E
                                                ; the number, and writes no
                                                ; latch of its own to be read
                                                ; back from
                bra     ampl_rescale_skip       ; $BD87: no register write
ampl_rescale_own
                ldb     ,s
                lbsr    ampl_fm_record          ; $BD8D-$BDA2: the record
                pshs    x                       ; 0-1,s the record 2,s the
                                                ; channel 3,s the exponent
                                                ; 4,s the code 5-6,s halve
                ldy     #ampl_signs
                ldb     2,s
                lda     b,y                     ; A = the sign, record+$14
                leau    CHAN_AMPL,x             ; U = the level, record+10
                lbsr    ampl_level_raw          ; $BDA4-$BDB6: X = the code,
                                                ; B = its own exponent
                negb                            ; $BDF1-$BDFD: common minus
                addb    3,s                     ; own, shift_signed's count
                tfr     b,a
                clrb                            ; $BE02-$BE12: channel 0 halves
                tst     2,s                     ; while AM is counted
                bne     ampl_rescale_ranged
                ldb     6,s
ampl_rescale_ranged
                puls    y                       ; Y = the record: its waveform
                                                ; word gates the fold
                lbsr    ampl_level_range        ; fold, shift, halve, unfold
                ldb     ,s
                lbsr    ampl_program            ; $BE3F-$BE4B
ampl_rescale_skip
                puls    b
                incb                            ; $BE50-$BE56
                cmpb    #CHANNEL_MAX            ; $BD30
                blo     ampl_rescale_next
                puls    a,b,x
                rts

; ---------------------------------------------------------------------------
; ampl_propagate - a channel's level onto the chip, with everything it sums with
;
;   entry: B = the channel whose level is to reach the chip;
;          A = the channel whose destination counter is already down
;              ($7AB2) while its record still names the code - the leaving
;              channel when called from destn_leave - or $FF
;   uses:  A, B, X, Y, U
;
; channel_apply_and_propagate ($BE5C), instruction by instruction:
;
;   $BE5C-$BE7B  the type is the channel's record+$21 (routed_dest), and
;                $2516 - channel 0's +$21 - is kept beside it.
;   $BE8B-$BE9C  a type of $0010, Off: dds_write_chan_param(channel, 0)
;                and nothing else.
;   $BE9F-$BEC6  the partner: port_code_to_channel ($C765) of the type, or
;                of $2516 when the type is DSB - ampl_partner.
;   $BEC9-$BEE4  with a partner, set_channel_latch_bit2(partner, 0): the
;                socket's relay opened across the change - ampl_blank, which
;                carries the stock's special-function-4 veto.
;   lbee7        with the type DSB, or $240E not zero and the type equal to
;                $2516, lbf07: sum_channel_levels_for_dest ($BA2C) of $2516
;                and of $000A, added ($BF0F-$BF48); otherwise lbf7d: the
;                sum of the type alone ($BF85). ampl_dest_sum is that sum
;                for the type of the channel given, seeded with the channel's
;                own level - or the largest hop level while amplitude hop is
;                on, which is what $BA2C adds for channel 0 (lba8c) - and it
;                counts the DSB levels, and the carrier's socket for DSB,
;                under the same conditions lbee7 tests.
;   $BF50/$BF99  scale_to_dds_code ($D3EC) of the sum against THIS channel's
;                record, for its exponent alone (STB 7,S) - ampl_level_raw.
;   $BF64/$BF75  in the lbf07 case rescale_channel_dacs of $000A and then of
;   $BFAC        $2516; in the lbf7d case of the type - ampl_rescale_dest.
;   lbfb1-lc02a  with the type equal to $2516 and $240D not zero, every
;                channel 1 to 3 whose +$21 is 7 (AM) has its depth re-derived
;                with level_scale_by_cal ($BB98) and written - the carrier's
;                code changed, so the depths that are fractions of it change
;                with it. ampl_depth_to_code IS $BB98 - the divide by 1000,
;                the fixmul against the carrier's code, and the Noise arm.
;   lc032-lc062  with a partner, output_latch_level_set ($B5EF)(partner,
;                exponent) and set_channel_latch_bit2(partner, 1) - the
;                socket's range latch and its relay closed again:
;                ampl_range_write and ampl_unblank, whose release is gated on
;                the record's output state as $B67B's is on $23B3+partner.
;
; THE FRAME, once A and B are pushed and eleven bytes are opened below them:
;   0,s      the type              1,s      the partner, or $FF
;   2-3,s    the halve flag        4,s      the common exponent
;   5-7,s    the sum               8-10,s   spare, kept for the frame's shape
;   11,s     the excluded channel  12,s     the channel
; ---------------------------------------------------------------------------
ampl_propagate
                pshs    a,b
                leas    -11,s
                ldx     #routed_dest
                ldb     12,s
                lda     b,x                     ; $BE5C-$BE7B: record+$21
                sta     ,s
                cmpa    #LBL_OFF                ; $BE8B CMPX #$0010
                bne     ampl_prop_routed
                ldx     #$0000                  ; $BE8F-$BE9C: zero, and out
                lbsr    ampl_program            ; B = the channel
                lbra    ampl_prop_done
ampl_prop_routed
                cmpa    #LBL_DSB                ; $BEA2: DSB is asked with
                bne     ampl_prop_partner       ; channel 0's code ($2516)
                lda     >routed_dest
ampl_prop_partner
                tfr     a,b
                lbsr    ampl_partner            ; $BEB0/$BEC2: $C765
                stb     1,s
                cmpb    #$FF                    ; $BEC9-$BECF: none for a
                beq     ampl_prop_counts        ; modulation code
                lbsr    ampl_blank              ; $BED2-$BEE4: the relay open
ampl_prop_counts
                clr     2,s                     ; $240D, as rescale_channel_
                clr     3,s                     ; dacs reads it at $BE0A:
                lda     11,s                    ; does the carrier halve?
                ldb     #LBL_AM
                lbsr    ampl_present
                beq     ampl_prop_which
                inc     3,s
ampl_prop_which
                ldb     ,s
                cmpb    #LBL_DSB                ; $BEE7 CMPX #$000A
                beq     ampl_prop_two
                cmpb    >routed_dest            ; $BEF9: the type is channel
                bne     ampl_prop_one           ; 0's...
                lda     11,s
                ldb     #LBL_DSB
                lbsr    ampl_present            ; $BEED: ...and DSB is
                bne     ampl_prop_two           ; counted
ampl_prop_one
                ; --- lbf7d: the destination's own levels -----------------
                leau    5,s
                lbsr    ampl_prop_sum           ; $BF85: the sum
                lbsr    ampl_prop_exponent      ; $BF99: A = its exponent
                sta     4,s
                ldb     ,s                      ; $BFAC: rescale(exponent,
                ldx     2,s                     ; type), the halve flag
                lbsr    ampl_rescale_dest
                bra     ampl_prop_am
ampl_prop_two
                ; --- lbf07: the carrier's socket and the DSB levels -------
                leau    5,s
                lbsr    ampl_prop_sum           ; $BF0F + $BF2C + $BF3E:
                                                ; ampl_dest_sum counts both
                lbsr    ampl_prop_exponent      ; $BF50: A = the exponent
                sta     4,s
                ldb     #LBL_DSB                ; $BF64: rescale(exponent,
                ldx     2,s                     ; $0A)
                lbsr    ampl_rescale_dest
                lda     4,s
                ldb     >routed_dest            ; $BF75: rescale(exponent,
                ldx     2,s                     ; $2516)
                lbsr    ampl_rescale_dest
ampl_prop_am
                ; --- lbfb1-lc02a: the AM depths follow the carrier --------
                ldb     ,s
                cmpb    >routed_dest            ; $BFB4: the type is channel
                bne     ampl_prop_latch         ; 0's...
                lda     11,s
                ldb     #LBL_AM
                lbsr    ampl_present            ; $BFB9: ...and AM is counted
                beq     ampl_prop_latch
                ldb     #$01                    ; $BFC8: channels 1 to 3
ampl_prop_am_next
                pshs    b
                ldx     #routed_dest
                lda     b,x
                cmpa    #LBL_AM                 ; $BFE9 CMPX #$0007
                bne     ampl_prop_am_skip
                lbsr    ampl_fm_record          ; X = its record
                leau    CHAN_AMPL,x             ; $BFF7: its depth, +10
                lbsr    ampl_depth_to_code      ; $C00F level_scale_by_cal
                ldb     ,s
                lbsr    ampl_program            ; $C020 dds_write_chan_param
ampl_prop_am_skip
                puls    b
                incb
                cmpb    #CHANNEL_MAX            ; $BFD0 CMPB #$04
                blo     ampl_prop_am_next
ampl_prop_latch
                ; --- lc032-lc062: the socket's range latch and relay -------
                ldb     1,s
                cmpb    #$FF                    ; $C032-$C038
                beq     ampl_prop_done
                lda     4,s                     ; $C03A-$C04C: output_latch_
                lbsr    ampl_range_write        ; level_set(partner, exponent)
                ldb     1,s
                lbsr    ampl_unblank            ; $C04E-$C062: the relay
                                                ; closed, if the output is on
ampl_prop_done
                leas    11,s
                puls    a,b
                rts

; ampl_prop_sum - the sum of the levels the channel's destination carries
;   entry: U = where the three bytes go; the propagate frame is below the
;          return address: 14,s the channel
;   uses:  A, B, X, Y
;
; $BA2C's total through ampl_dest_sum: the channel's own level seeds it
; (or the largest hop level for channel 0 with amplitude hop on, lba8c), and
; the walk adds the other channels of the type - with the DSB levels for
; the carrier's socket and the carrier's socket for DSB, as lbf07 does.
ampl_prop_sum
                ldb     14,s                    ; the channel
                tstb
                bne     ampl_prop_sum_own
                lda     >mode_flags
                bita    #MODE_FLAG_AM
                beq     ampl_prop_sum_own
                lbsr    hop_ampl_max            ; Y -> the largest hop level
                tfr     y,x                     ; X = the seed
                bra     ampl_prop_sum_go
ampl_prop_sum_own
                lbsr    ampl_fm_record          ; X = the record
                leax    CHAN_AMPL,x             ; X -> its own level
ampl_prop_sum_go
                ldb     14,s                    ; B = the channel, the type's
                lbra    ampl_dest_sum           ; owner; [U] = the sum

; ampl_prop_exponent - the exponent scale_to_dds_code gives the sum
;   entry: the propagate frame below the return address: 7-9,s the sum,
;          14,s the channel
;   exit:  A = the exponent
;   uses:  A, B, X, Y, U
ampl_prop_exponent
                ldb     14,s
                lbsr    ampl_fm_record          ; X = the channel's record
                leau    7,s                     ; U = the sum
                lda     #AMPL_SIGN_PLUS
                lbsr    ampl_level_raw          ; $BF50/$BF99: B = exponent
                tfr     b,a
                rts

; ---------------------------------------------------------------------------
; ampl_carrier_reapply - channel 0's level put back by its own unit
;
;   entry: A = the channel whose destination counter is already down, or $FF
;   uses:  A, B, X, Y, U
;
; set_channel_destination ($78BF)'s dispatch_channel_function ($C069) call
; with channel 0 and $24FF - channel 0's record+10 - made at $7B02-$7B10
; when the last AM or DSB modulator leaves and at $7EA6-$7EB5 when one
; arrives. $C069 dispatches on channel 0's unit word (+13, $2502):
;
;   $0D, Off's (destn_units_off_blank $7E5F)  arm [12], chan_param_zero_
;        no_apply: zero to its register, no propagation.
;   $0E, while a DSB modulator is counted (default_units_output $7E33-$7E4D
;        on $240E, and destn_check_dsb's own store at $7D05)  arm [13],
;        param_arm13_zero: zero to its register, then the lc181 tail.
;   $05, a socket otherwise  arm [4], arm_no_action: the lc181 tail.
;
; The lc181 tail: channel 0 with amplitude hop on writes zero to its own
; register ($C1A1-$C1B2), and channel_apply_and_propagate ($BE5C) runs for
; channel 0 ($C1B4) - ampl_propagate, with the caller's counter exclusion.
; The unit is derived here from channel 0's destination and the counted
; DSB modulators, which are the two inputs the stock's stores were made
; from; channel 0 cannot carry a modulation code ($78BF refuses it, $65).
; ---------------------------------------------------------------------------
ampl_carrier_reapply
                pshs    a                       ; the excluded channel
                ldb     >channel_records+CHAN_DEST
                cmpb    #LBL_OFF
                bne     ampl_carrier_live
                ldx     #$0000                  ; $0D: arm [12], zero only
                clrb
                lbsr    ampl_program
                puls    a
                rts
ampl_carrier_live
                lda     ,s
                ldb     #LBL_DSB
                lbsr    ampl_present            ; $0E while DSB is counted
                beq     ampl_carrier_volts
                ldx     #$0000                  ; arm [13]: zero, then the
                clrb                            ; tail
                lbsr    ampl_program
ampl_carrier_volts
                lda     >mode_flags             ; lc181-lc1b2: channel 0 with
                bita    #MODE_FLAG_AM           ; amplitude hop on writes zero
                beq     ampl_carrier_propagate  ; to its own register first
                ldx     #$0000
                clrb
                lbsr    ampl_program
ampl_carrier_propagate
                puls    a                       ; the excluded channel
                clrb                            ; channel 0
                lbra    ampl_propagate          ; lc1b4: $BE5C(0)

; ---------------------------------------------------------------------------
; ampl_program_half - the DTMF pair, each generator at half the set level
;
;   entry: X = the record carrying the pair's set level, A = the first
;          channel, B = the second
;   exit:  both generators are on the chip at half the set level; the FIRST
;          channel's record holds the set level again and the SECOND's is
;          left holding the half, which is what $5F70 leaves behind
;   uses:  A, B, X, Y, U
;
; FOR THE DTMF PAIR, and the reason is arithmetic rather than taste: two
; generators are summed into one output, so each has to be given half the
; level the operator set or the pair comes out at twice it.
;
; apply_amplitude ($5F70) INSTRUCTION BY INSTRUCTION, because the shape of it
; is the whole point and this routine used to have a different one:
;
;   $5F78-$5F8A  the record's 24-bit level at +10 to $221C, and a second copy
;                of it to a stack local at 5,S - the original, kept
;   $5F9E-$5FA8  on the DTMF flag $3C03, halve_amplitude_221c ($4439): an
;                unsigned 24-bit right shift, LSRA then two RORAs
;   $5FAD-$5FC1  $221C back INTO THE RECORD at +10
;   $5FCD        dispatch_channel_function ($C069) for channel 0
;   $5FE1-$5FF1  $23BE <- 2 and cache_channel_record_ptr ($C21A), so $23BF
;                now points at channel 2's record
;   $5FF6-$6009  $221C into THAT record at +10 as well
;   $600B        $C069 for channel 2
;   $6011-$601A  $23BE <- 0 and $C21A: $23BF back to channel 0's record
;   $601D-$6030  the saved original from 5,S back into it
;
; SO IT GOES THROUGH $C069, and that is what this did not do. It called what
; were then ampl_level_code and ampl_level_apply, coding the halved level
; against the channel's OWN exponent and writing the channel's OWN latch. $C069
; on a socket unit reaches channel_apply_and_propagate ($BE5C), which sums
; every level on the destination SOCKET, codes each against the exponent of
; that sum, and writes the SOCKET's latch. The two agree while each DTMF
; channel is alone on its socket and differ the moment one is not.
;
; AND THE HALVED VALUE HAS TO BE IN THE RECORD, which is why the stock writes
; it there rather than passing it: $BE5C builds its sum out of the records, so
; a halved level held anywhere else is not in the sum. Both records therefore
; hold the half by the time the SECOND dispatch runs - which is why the pair
; is done here in one routine rather than by two calls that each put a record
; back. Two such calls give the second dispatch a first channel that has
; already been restored, and its sum is then set level plus half.
;
; ONLY THE FIRST IS PUT BACK, at $601D, and the second is left holding the
; half. That is not an oversight in the stock: the first channel's record is
; the one the screen displays the set level from, and the second's genuinely
; is at half.
;
; TWO COPIES, AND THE KEPT ONE IS NOT THE WORKING ONE. This routine used to
; push the three bytes ONCE, halve those same three slots in place, and then
; read them again at the $601D restore - so it wrote the HALF back into the
; first channel's record, where $601D writes the level the operator set. The
; header above already said "the original, kept"; there was no second copy to
; keep it in. The stock cannot make that mistake because its two copies are in
; different places: $221C, which halve_amplitude_221c ($4439) shifts, and the
; frame local at 5,S, which nothing between $5F8A and $601D touches. Both are
; on the stack here, the working copy on top so ampl_half_store's fixed
; offsets do not move, and the kept copy three bytes under it.
;
; DRIVEN, 2026-09-13, both firmwares from the same set level of 200 with the
; DTMF flag set and channel 0's record selected: the instrument's $5F70 leaves
; channel 0's record at 200 and channel 2's at 100, and the chip at level code
; 1342 on each. Before this change ampl_program_half left BOTH records at 100
; - the chip codes already agreed, because the halved value reaches the chip
; through the records and both did hold the half at each dispatch. It is only
; what is left behind afterwards that was wrong, which is the value the screen
; reads and the value the next apply halves again.
;
; STA does not disturb the carry on this CPU, so the store between each shift
; and the next rotate is safe - LSRA leaves bit 0 in carry and the RORA below
; rotates it into the next byte.
; ---------------------------------------------------------------------------
ampl_program_half
                pshs    a,b,x                   ; 0,s first 1,s second
                                                ; 2-3,s the set-level record

                ; --- $5F8A: the second copy, the one nothing touches -------
                ; The stock's local at 5,S. It gets there by way of $221C -
                ; $5F78 copies the record into $221C and $5F8A copies $221C
                ; into the local - so the local holds the record's three
                ; bytes, which is what reading the record a second time here
                ; gives: nothing has written it in between.
                lda     CHAN_AMPL,x
                pshs    a                       ; high
                lda     CHAN_AMPL+1,x
                pshs    a                       ; mid
                lda     CHAN_AMPL+2,x
                pshs    a                       ; low

                ; --- $5F78: the working copy, the stock's $221C ------------
                lda     CHAN_AMPL,x
                pshs    a
                lda     CHAN_AMPL+1,x
                pshs    a
                lda     CHAN_AMPL+2,x
                pshs    a                       ; 0,s low 1,s mid 2,s high
                                                ; 3,s low 4,s mid 5,s high of
                                                ; the kept copy
                                                ; 6,s first 7,s second
                                                ; 8-9,s the record

                ; --- $5FA8 halve_amplitude_221c: LSRA then two RORAs -------
                ; $4439 shifts $221C and nothing else, so only the working
                ; copy at 0-2,S moves here.
                lda     2,s                     ; most significant byte first,
                lsra                            ; so each shift feeds the next
                sta     2,s
                lda     1,s
                rora
                sta     1,s
                lda     ,s
                rora
                sta     ,s

                ; --- $5FAD-$5FCD: into the first record, and dispatch ------
                ldb     6,s
                lbsr    ampl_fm_record          ; X = the first channel's own
                lbsr    ampl_half_store         ; record, and the half into it
                ldb     6,s
                lbsr    ampl_reapply            ; $C069 -> $C181 -> $BE5C

                ; --- $5FF6-$600B: into the second record, and dispatch -----
                ; BOTH now hold the half, which is what makes the sum this
                ; dispatch builds the right one.
                ldb     7,s
                lbsr    ampl_fm_record
                lbsr    ampl_half_store
                ldb     7,s
                lbsr    ampl_reapply

                ; --- $601D-$6030: the KEPT COPY into the first record ------
                ; The set level, not the half. 3-5,S, which the shift above
                ; could not reach, exactly as $601D reads the local the shift
                ; at $5FA8 could not reach.
                ldx     8,s                     ; the set-level record, which
                lda     5,s                     ; is the first channel's
                sta     CHAN_AMPL,x
                lda     4,s
                sta     CHAN_AMPL+1,x
                lda     3,s
                sta     CHAN_AMPL+2,x

                leas    10,s
                rts

; ---------------------------------------------------------------------------
; ampl_half_store - the halved level on the stack into a record
;
;   entry: X = the record, 0,s/1,s/2,s = low, middle, high UNDER the return
;          address this call pushes - so 2,s/3,s/4,s here
;   uses:  A
;
; The $5FAD and $5FF6 copies, which are the same three bytes twice. It is a
; subroutine rather than written out twice because the second copy differing
; from the first by a byte is exactly the fault that would not show: both
; generators would still be programmed, one of them wrongly.
; ---------------------------------------------------------------------------
ampl_half_store
                lda     4,s                     ; high
                sta     CHAN_AMPL,x
                lda     3,s                     ; middle
                sta     CHAN_AMPL+1,x
                lda     2,s                     ; low
                sta     CHAN_AMPL+2,x
                rts

; ---------------------------------------------------------------------------
; ampl_blank / ampl_unblank - mute a channel while its level changes
;
;   entry: B = the channel, 0 to 3
;   uses:  A, B, X
;
; BIT 2 IS THE OUTPUT RELAY AND IT IS THE MUTE. There is no separate blanking
; line: hardware.inc declares bit 2 "the OUTPUT ON/OFF relay, ACTIVE LOW -
; CLEAR IS ON", from set_output_enable ($B79C) writing $04 to switch a channel
; off, and it says in the same place that the relay is also what blanking
; asserts.
;
; This header used to say bit 0 was the enable and that blanking and the
; enable were different bits, so "a channel the operator switched off stays
; off, because nothing here writes the bit that decides that". Both halves
; are wrong: bit 0 is the filter select on net FLC, and this routine writes
; the very relay that switches the output. What actually keeps a channel the
; operator switched off switched off is ampl_unblank's gate on CHAN_STATE -
; the record of what the operator asked for - which is a different mechanism
; and a real one.
;
; That is the whole reason to use the right bit. The earlier version blanked
; by clearing the ENABLE and then restored it from the record - which works
; only as long as the record and the latch agree, and puts the enable
; briefly in a state the operator did not ask for.
;
; FIVE MILLISECONDS EITHER SIDE, which is what the stock
; switch_channel_latch_bit0 ($F692) waits around its own output change.
; ---------------------------------------------------------------------------
CHAN_STATE_ON   equ     $01             ; bit 0 of the record's state byte
BLANK_SETTLE_MS equ     5               ; what the stock waits either side
                                        ; of an output change

ampl_blank
                ; THE VETO LIVES HERE, so no call site can forget it.
                ;
                ; Special function 4, "Disable output blanking", turns the
                ; mute off - the mute is itself a discontinuity, and a
                ; measurement that cares more about continuity than about
                ; overshoot may prefer the transient. The check was in
                ; ampl_set and nowhere else, and ampl_set is not the only
                ; caller: filter_apply in screens_main.s blanks and unblanks
                ; across a filter change unconditionally, so an operator who
                ; had turned blanking off still got the output muted there.
                ;
                ; The stock puts it inside the routine for exactly this
                ; reason - set_channel_latch_bit2 ($B672) tests $23C1 bit 4 on
                ; its assert path and returns without asserting - and
                ; hardware.inc already recorded that. Note it vetoes only the
                ; ASSERT: ampl_unblank still releases, because a release that
                ; is skipped leaves an output muted with nothing to unmute it.
                lda     >special_flags
                bita    #SPECIAL_NO_BLANK
                bne     ampl_blank_vetoed

                ; BIT 2 IS THE OUTPUT RELAY and it is the mute: there is no
                ; separate blanking line, and the stock
                ; switch_channel_latch_bit0 ($F692) uses this same relay the
                ; same way. SET is off.
                lda     #LATCH_OUTPUT
                inc     >dds_lock               ; THE STORE AND THE CALL
                                                ; ARE ONE OPERATION. An
                                                ; NMI landing between
                                                ; them would leave this
                                                ; writing the sequence
                                                ; player's value into a
                                                ; channel latch; see
                                                ; channel_latch_rmw.
                sta     >latch_bits
                lda     #LATCH_OUTPUT
                lbsr    channel_latch_rmw
                dec     >dds_lock
                ldd     #BLANK_SETTLE_MS        ; the stock waits this long
                lbra    delay_ms                ; either side of the change
ampl_blank_vetoed
                rts

ampl_unblank
                pshs    b
                ldd     #BLANK_SETTLE_MS        ; let the new level settle
                lbsr    delay_ms                ; before letting it out
                puls    b

                ; RELEASE ONLY IF THE CHANNEL WAS ON. The stock gates its own
                ; release on $23B3+channel for this reason: the relay that
                ; mutes is the relay that switches the output, so releasing
                ; unconditionally would switch on a channel the operator had
                ; deliberately switched off.
                pshs    b
                lda     #CHAN_RECORD
                mul
                ldx     #channel_records
                leax    d,x
                lda     CHAN_STATE,x
                anda    #CHAN_STATE_ON
                bne     ampl_unblank_on
                puls    b                       ; it was off: leave it off
                rts
ampl_unblank_on
                puls    b
                inc     >dds_lock               ; THE STORE AND THE CALL
                                                ; ARE ONE OPERATION. An
                                                ; NMI landing between
                                                ; them would leave this
                                                ; writing the sequence
                                                ; player's value into a
                                                ; channel latch; see
                                                ; channel_latch_rmw.
                clr     >latch_bits             ; CLEAR is on
                lda     #LATCH_OUTPUT
                lbsr    channel_latch_rmw
                dec     >dds_lock
                rts


; ===========================================================================
; ampl_autorange - show a level in V, mV or uV according to its magnitude
;
;   entry: U = the 24-bit level, in microvolts
;   exit:  B = the unit code, one of UNIT_VOLT, UNIT_MILLIVOLT, UNIT_MICROVOLT
;          ampl_range_text holds the formatted characters
;          A = how many of them there are, 5 or 6
;   uses:  A, B, X, Y, U
;
; THE DISPLAY DID NOT AUTORANGE. chan_ampl_places returned CHAN_MICRO places
; for a voltage destination and chan_ampl_label returned 'V' unconditionally,
; so 500 microvolts was shown as a fraction of a volt instead of as 500 uV.
;
; THE STOCK'S RULE, and it is not a guess in any part. autorange_digits_v_mv_uv
; ($D022) renders the value as eight characters, blanks the leading zeros with
; blank_leading_zeros ($D035), appends two '0' characters, and scans for the
; first non-blank with a limit of ten. That index - plus ten when the character
; found is '1', which is the extra significant figure a leading one allows -
; selects one of nineteen arms at $D124, each setting a unit code, a
; decimal-point position and a source offset. numfmt_common_tail ($D14A) then
; calls format_with_decimal_point ($CD50) with a digit count of five: it walks
; the destination, writing '.' where the DESTINATION index equals the decimal
; position and otherwise copying a source character, until five source
; characters have been taken.
;
; So a decimal position of 5 means NO POINT AT ALL - the destination index
; never reaches five, because only the point makes it outrun the source - and
; the field is five characters wide instead of six.
;
; VERIFIED BY EXECUTION, not by reading. $D022 was run on the stock a2u12.bin
; with seven known inputs and the returned unit code and characters read back:
;
;     10000000 -> unit 5, '10.000'      1000000 -> unit 5, '1.0000'
;         1000 -> unit 6, '1.0000'        12345 -> unit 6, '12.345'
;       999999 -> unit 6, '  999'           500 -> unit 7, '  500'
;            0 -> unit 7, '    0'
;
; Every one of those matches the table below. The 999999 case is not a defect
; and is reproduced deliberately: 999.999 mV needs seven characters and the
; field is six, so the stock shows three significant figures there and the
; full five everywhere the point fits.
;
; ARMS 9 AND 18 CANNOT BE REACHED and the table still carries them, so the
; lookup stays a plain index. Index 9 would need the ninth character blank
; when it is one of the two appended '0's, and index 18 would need that
; character to be '1'.
;
; THE STOCK EMITS A SIXTH CHARACTER THAT IT NEVER WROTE. format_with_decimal_point
; copies count+1 = 6 bytes whatever happens, and with a decimal position of 5
; the sixth is whatever frame_alloc left on the stack - the execution above
; shows a non-printing byte there. This emits five in that case and six when
; the point lands, which is every character the stock defines and none of the
; one it does not.
; ===========================================================================
AMPL_DP3_DIGITS equ     4               ; format_dp3_blank6 ($56AC): four
AMPL_DP3_POINT  equ     3               ; digits with the point after three,
AMPL_DP3_BLANKS equ     2               ; two leading zeros blankable, and the
AMPL_DP3_WIDTH  equ     5               ; five characters that makes
AMPL_RAD_POINT  equ     1               ; a radian deviation: 'd.ddd', the
AMPL_RAD_BLANKS equ     0               ; point after ONE and no blanking -
                                        ; $4DD7's ceiling is 6282 mrad, so the
                                        ; whole part is one digit, never blank

AMPL_RANGE_DIGITS equ   5               ; the digit count $D14A passes to $CD50
AMPL_RANGE_WIDE   equ   8               ; characters uint24_to_text produces
AMPL_RANGE_SCAN   equ   10              ; the scan limit, CMPB #$0A at $D05B
AMPL_RANGE_NOPOINT equ  5               ; a decimal position the loop cannot
                                        ; reach, so no point is written

; NINETEEN TRIPLES FOR A DEVIATION, the counterpart of the volts table below.
; The stock has two autorangers of one shape - autorange_digits_v_mv_uv ($D022)
; for a level and autorange_digits_khz_hz ($D17D) for a frequency - and they
; differ only in these numbers, so this firmware has one routine and two
; tables.
;
; DRIVEN, not decoded. $D17D formats out of an eleven-character local whose
; frame this reading could not settle, so the triples below were taken from
; what the instrument PUTS ON THE GLASS: channel B routed to FM on a booted
; stock, twenty-seven deviations sent over the bus, and the AMPTD field read
; back each time (2026-09-11). The field it produces:
;
;       1 Hz     '   1.0  Hz'        1000 Hz  ' 1.000 kHz'
;       9 Hz     '   9.0  Hz'        1999 Hz  ' 1.999 kHz'
;      10 Hz     '  10.0  Hz'        2000 Hz  '  2.00 kHz'
;      99 Hz     '  99.0  Hz'        9999 Hz  '  9.99 kHz'
;     100 Hz     ' 100.0  Hz'       10000 Hz  ' 10.00 kHz'
;     199 Hz     ' 199.0  Hz'       19999 Hz  ' 19.99 kHz'
;     200 Hz     '   200  Hz'       20000 Hz  '  20.0 kHz'
;     999 Hz     '   999  Hz'       99999 Hz  '  99.9 kHz'
;                                  100000 Hz  ' 100.0 kHz'
;
; which is a THREE significant digit display extended to FOUR whenever the
; leading digit is a 1 - the same 3.5-digit rule the volts table follows, and
; the reason the scan below adds ten for a leading '1'. The unit turns over at
; 1000.0 Hz, which is the fifth digit of a count in tenths.
;
; THE FIELD IS FIVE COLUMNS and this routine emits six, the sixth dropped by
; the caller - which is the volts path's shape too ('1.0000' for one volt,
; '1.000' on the glass). So each triple below was SOLVED against the five
; columns the instrument writes at DDRAM $1F, not against the six: the pair
; (point, offset) that reproduces every driven value at its scan index is
; unique, and it is what the table holds.
ampl_freq_table
                fcb     UNIT_KHZ,5,0     ; [0]  eight digits, leading 2-9: not
                                         ;      driven - a deviation that large
                                         ;      cannot be set
                fcb     UNIT_KHZ,4,0     ; [1]  seven, likewise
                fcb     UNIT_KHZ,3,1     ; [2]  six:   ' 20.0', ' 99.9'
                fcb     UNIT_KHZ,2,2     ; [3]  five:  '  2.00', ' 9.99'
                fcb     UNIT_HZ,5,2      ; [4]  four:  '  200', '  999' - no
                                         ;      point, and the field's fifth
                                         ;      column is the last digit
                fcb     UNIT_HZ,3,4      ; [5]  three: ' 20.0', ' 99.0'
                fcb     UNIT_HZ,3,4      ; [6]  two:   '  2.0', '  9.0'
                fcb     UNIT_HZ,3,5      ; [7]  one, and a deviation of zero:
                                         ;      '  0.0'
                fcb     UNIT_HZ,3,5      ; [8]  the appended zeros: the scan
                fcb     UNIT_HZ,3,5      ; [9]  cannot reach these, since only
                                         ;      seven of the eight digits blank
                fcb     UNIT_KHZ,5,0     ; [10] eight, leading 1: not driven
                fcb     UNIT_KHZ,3,1     ; [11] seven, leading 1: '100.0'
                fcb     UNIT_KHZ,2,2     ; [12] six,   leading 1: '10.00', '19.99'
                fcb     UNIT_KHZ,1,3     ; [13] five,  leading 1: '1.000', '1.999'
                fcb     UNIT_HZ,3,4      ; [14] four,  leading 1: '100.0', '199.0'
                fcb     UNIT_HZ,3,4      ; [15] three, leading 1: ' 10.0', ' 19.0'
                fcb     UNIT_HZ,3,4      ; [16] two,   leading 1: '  1.0'
                fcb     UNIT_HZ,3,5      ; [17] one,   leading 1
                fcb     UNIT_HZ,3,5      ; [18]

; nineteen entries of (unit, decimal position, source offset), read off the
; arms at $D124 one at a time
ampl_range_table
                fcb     UNIT_VOLT,2,0    ; [0]  eight digits
                fcb     UNIT_VOLT,2,0    ; [1]  seven
                fcb     UNIT_MILLIVOLT,5,0    ; [2]  six
                fcb     UNIT_MILLIVOLT,3,2    ; [3]  five
                fcb     UNIT_MILLIVOLT,2,3    ; [4]  four
                fcb     UNIT_MICROVOLT,5,3    ; [5]  three
                fcb     UNIT_MICROVOLT,5,3    ; [6]  two
                fcb     UNIT_MICROVOLT,5,3    ; [7]  one
                fcb     UNIT_MICROVOLT,5,4    ; [8]  zero
                fcb     UNIT_MICROVOLT,5,4    ; [9]  unreachable
                fcb     UNIT_VOLT,2,0    ; [10] eight, leading 1
                fcb     UNIT_VOLT,1,1    ; [11] seven, leading 1
                fcb     UNIT_MILLIVOLT,3,2    ; [12] six, leading 1
                fcb     UNIT_MILLIVOLT,2,3    ; [13] five, leading 1
                fcb     UNIT_MILLIVOLT,1,4    ; [14] four, leading 1
                fcb     UNIT_MICROVOLT,5,3    ; [15] three, leading 1
                fcb     UNIT_MICROVOLT,5,3    ; [16] two, leading 1
                fcb     UNIT_MICROVOLT,5,3    ; [17] one, leading 1
                fcb     UNIT_MICROVOLT,5,4    ; [18] unreachable

ampl_autorange
                ldy     #ampl_range_table       ; a level: volts, millivolts,
                bra     ampl_range_body         ; microvolts

; ---------------------------------------------------------------------------
; ampl_freq_autorange - the same, for a deviation in tenths of a hertz
;
;   entry: U = a 24-bit count in units of 0.1 Hz
;   exit:  as ampl_autorange, with UNIT_HZ or UNIT_KHZ in B
;   uses:  A, B, X, Y, U
; ---------------------------------------------------------------------------
ampl_freq_autorange
                ldy     #ampl_freq_table

ampl_range_body
                pshs    y                       ; THE TABLE, until the index is
                                                ; worked out. Everything from
                                                ; here to that lookup is the
                                                ; same for both: the stock's
                                                ; two autorangers differ in
                                                ; nineteen triples and in
                                                ; nothing else.
                pshs    u
                tfr     u,x
                lbsr    ABI_uint24_to_text      ; eight digits, leading zeros
                puls    u                       ; kept

                ; --- the eight characters, and the two appended '0's --------
                ldx     #text_buffer
                ldy     #ampl_range_text
                ldb     #AMPL_RANGE_WIDE
ampl_range_copy
                lda     ,x+
                sta     ,y+
                decb
                bne     ampl_range_copy
                lda     #'0'
                sta     ,y+
                sta     ,y

                ; --- leading zeros become spaces ----------------------------
                ; ALL BUT THE LAST DIGIT. blank_leading_zeros ($D035) leaves
                ; one, which is what makes a value of zero scan to index 8 -
                ; hmm, no: it blanks every one, and the scan finds the FIRST
                ; APPENDED '0' at index 8. Either reading gives index 8 for
                ; zero; this stops at the last digit so that a zero shows as
                ; '0' and not as an empty field.
                ldx     #ampl_range_text
                ldb     #AMPL_RANGE_WIDE-1
ampl_range_blank
                lda     ,x
                cmpa    #'0'
                bne     ampl_range_blanked
                lda     #' '
                sta     ,x+
                decb
                bne     ampl_range_blank
ampl_range_blanked

                ; --- the first non-blank, plus ten for a leading one --------
                ldx     #ampl_range_text
                clrb
ampl_range_scan
                lda     b,x
                cmpa    #' '
                bne     ampl_range_found
                incb
                cmpb    #AMPL_RANGE_SCAN
                blo     ampl_range_scan
ampl_range_found
                cmpa    #'1'
                bne     ampl_range_index
                addb    #10
ampl_range_index
                lda     #3
                mul                             ; D = index * 3
                ldy     ,s                      ; the caller's table
                leay    d,y                     ; Y = unit, position, offset

                ldb     2,y                     ; U = the first source
                ldu     #ampl_range_text        ; character
                leau    b,u

                ; --- five source characters, with the point where it falls --
                ; INTO A SEPARATE BUFFER, which is not a nicety. The stock
                ; formats into a local and mem_copies it out; formatting in
                ; place would overwrite a source character before it is read -
                ; with a source offset of 0 and the point at destination index
                ; 2, writing the point lands exactly on the third source
                ; character, and every value from ten volts down would lose a
                ; digit.
                clra                            ; A = the source index
                clrb                            ; B = the destination index
                pshs    a,b                     ; 0,s = A = src, 1,s = B = dst
ampl_range_emit
                ldb     1,s
                cmpb    1,y                     ; the decimal position
                beq     ampl_range_point
                lda     ,s
                ldb     a,u                     ; the next source character
                inc     ,s
                bra     ampl_range_put
ampl_range_point
                ldb     #'.'
ampl_range_put
                lda     1,s
                ldx     #ampl_range_out
                stb     a,x
                inc     1,s
                lda     ,s
                cmpa    #AMPL_RANGE_DIGITS
                blo     ampl_range_emit

                lda     1,s                     ; how many were written: five
                leas    2,s                     ; when no point fell, six when
                ldb     ,y                      ; one did
                puls    y                       ; and the table pointer goes
                rts                             ; back off the stack


; ===========================================================================
; ampl_text - a channel's AMPTD field as characters, value and unit together
;
;   entry: X = the channel record
;   exit:  chan_text holds AMPL_TEXT_W value characters, right-aligned and
;          blank-padded, followed at chan_text+AMPL_TEXT_W by AMPL_TEXT_U
;          characters naming the unit. chan_ampl_unit holds the unit code.
;   uses:  A, B, X, Y, U
;
; ONE RENDERER, because the AMPTD field is now shown on two screens. It was
; written inside the channel screen on A2U13 page 0 - the unit lookup, the
; three voltage labels, the decimal places and the right-alignment, all of it
; - and the tone sequence screen on page 1 needs the same field. A second
; copy in the other image is how the two would start disagreeing about what a
; stored 500 means, which is the defect the unit dispatch was written to end.
;
; WHAT DECIDES THE PUNCTUATION IS THE DESTINATION, not the number. A channel
; set to AM carries a depth in tenths of a percent, one set to FM a deviation
; in tenths of a hertz, one set to phi-M tenths of a degree, and an output a
; level in microvolts. The stock reaches the same four layouts through
; render_value_with_units ($564E), which dispatches the record's unit code
; through the table at $574E - '%' and 'deg' to format_dp3_blank6 ($56AC) and
; the voltages to the autoranging arm at $D022.
; ===========================================================================

ampl_text
                pshs    x                       ; the record
                ldb     CHAN_DEST,x
                lbsr    ampl_unit_for_destn     ; A = the unit code
                sta     >chan_ampl_unit
                puls    x

                ; --- THE CARRIER UNDER DSB -------------------------------
                ; default_units_output ($7E33) writes unit code 14 into
                ; CHANNEL 0's record while the DSB counter $240E is
                ; non-zero, and 14 renders blank under the label 'DSB': a
                ; suppressed carrier's level is not a level, so the stock
                ; blanks the field the moment a DSB modulator exists. The
                ; adversarial read of the $7E78 table found this arm - the
                ; earlier enumeration had waved it through as 'the output
                ; default'. This firmware keeps no unit codes in the
                ; record, so the same condition is: this is channel 0's
                ; record, and some channel's destination is DSB.
                cmpx    #channel_records        ; channel 0's record?
                bne     ampl_text_units
                pshs    x
                ldx     #channel_records
                ldb     #4
ampl_text_dsb_scan
                lda     CHAN_DEST,x
                cmpa    #LBL_DSB
                beq     ampl_text_carrier_dsb
                leax    CHAN_RECORD,x
                decb
                bne     ampl_text_dsb_scan
                puls    x
                lda     >chan_ampl_unit         ; no DSB modulator: carry on
                bra     ampl_text_units         ; with the destination's unit
ampl_text_carrier_dsb
                puls    x
                lda     #UNIT_DSB
                sta     >chan_ampl_unit
ampl_text_units
                ; --- A DEVIATION TYPED IN RADIANS SHOWS WHAT WAS TYPED -----
                ; The stock keeps the keyed unit in record+13 and the keyed
                ; NUMBER in record+10, so a phi-M channel given 1 ENTER reads
                ; '1.000 rad' where this firmware read '57.3 deg' - the same
                ; deviation, reconverted. Driven side by side 2026-09-11.
                ; chan_ampl_keyed is that unit byte and chan_ampl_rad the
                ; milliradians, both per channel, as chan_phase_unit and
                ; chan_phase_rad are for the PHASE field.
                cmpa    #UNIT_DEG
                bne     ampl_text_units_plain
                pshs    a
                lbsr    ampl_channel_of         ; B = the channel, X kept
                pshs    x
                ldx     #chan_ampl_keyed
                abx
                lda     ,x
                puls    x
                cmpa    #UNIT_RAD
                puls    a
                lbeq    ampl_text_rad
ampl_text_units_plain

                ; --- a destination with no keyable value: BLANK ------------
                ; UNIT_OFF (13) and UNIT_PULSE (15) are the codes
                ; destn_units_off_blank ($7E5D) and dest_units_pulse_blank
                ; ($7E2B) write into the record's +13, and the stock renders
                ; both through field_format_blank_units ($5668) - arms [12]
                ; and [14] of the format dispatch at $574E - whose whole body
                ; is LDD #$ED11 / STD 3,s, pointing the numeric buffer at the
                ; forty-space string so the field comes out empty. Their
                ; labels at $EEEE are blank and 'DSB'.
                ;
                ; This printed the raw number to one decimal place with a 'V'
                ; beside it, because the label lookup falls through to volts:
                ; a channel switched Off showed a level it was not producing.
                cmpa    #UNIT_OFF
                lbeq    ampl_text_blank_field
                cmpa    #UNIT_PULSE
                lbeq    ampl_text_blank_field
                cmpa    #UNIT_DSB               ; the carrier case above:
                lbeq    ampl_text_blank_field   ; blank value, its own label

                cmpa    #UNIT_VOLT
                lbeq    ampl_text_ranged

                ; --- A DEVIATION AUTORANGES, as a level does ---------------
                ; The stock dispatches unit codes 1 and 2 through arms [0] and
                ; [1] of $574E to autorange_digits_khz_hz ($D17D), which picks
                ; between ' Hz' and 'kHz' and the point with them. This
                ; firmware printed one decimal place and a fixed label, so a
                ; 20 kHz deviation read '200000.0' with 'Hz' beside it where
                ; the instrument shows ' 20.0 kHz' - driven on the stock over
                ; twenty-seven deviations, 2026-09-11, and the table
                ; ampl_freq_table carries what it printed.
                cmpa    #UNIT_HZ
                lbeq    ampl_text_deviation
                cmpa    #UNIT_KHZ
                lbeq    ampl_text_deviation

                ; --- a depth or a phase: THREE DIGITS, A POINT AND ONE ----
                ; format_dp3_blank6 ($56AC), the arm the percent and degree
                ; unit codes reach through $574E: five characters, 'ddd.d',
                ; with the leading zeros of the whole part blanked. This
                ; rendered nine characters through format_places and let the
                ; field take five from the middle of them, so a phase deviation
                ; of 100.0 degrees showed ' 100.' and a cold field showed
                ; '   0.' - the tenth lost off the end. Driven against the
                ; stock 2026-09-11, which shows '100.0 deg' and '  0.0 deg'.
                leau    CHAN_AMPL,x
                pshs    x                       ; the record, over the format
                lbsr    ampl_text_clear
                lda     #AMPL_DP3_POINT         ; the point after three
                sta     >format_point
                clr     >format_trim
                tfr     u,x
                lda     #AMPL_DP3_DIGITS
                ldb     #AMPL_DP3_BLANKS
                lbsr    format_fixed            ; format_text: five characters
                puls    x

                ldu     #format_text            ; right-aligned in the nine,
                ldy     #chan_text+AMPL_TEXT_W-AMPL_DP3_WIDTH
                ldb     #AMPL_DP3_WIDTH
ampl_text_dp3_copy
                lda     ,u+
                sta     ,y+
                decb
                bne     ampl_text_dp3_copy
                ldb     #AMPL_DP3_WIDTH
                stb     >chan_ampl_len
                lbra    ampl_text_label

                ; --- the radian twin, 'd.ddd', the number as it was keyed --
ampl_text_rad
                lda     #UNIT_RAD               ; and the label with it: the
                sta     >chan_ampl_unit         ; screen writes three columns
                                                ; from this code
                lbsr    ampl_channel_of         ; B = the channel
                aslb                            ; a word each
                pshs    x
                ldx     #chan_ampl_rad
                abx
                ldd     ,x
                std     >chan_work+1            ; widened: the formatter takes
                clr     >chan_work              ; twenty-four bits
                lbsr    ampl_text_clear
                lda     #AMPL_RAD_POINT
                sta     >format_point
                clr     >format_trim
                ldx     #chan_work
                lda     #AMPL_DP3_DIGITS
                ldb     #AMPL_RAD_BLANKS
                lbsr    format_fixed
                puls    x
                ldu     #format_text
                ldy     #chan_text+AMPL_TEXT_W-AMPL_DP3_WIDTH
                ldb     #AMPL_DP3_WIDTH
ampl_text_rad_copy
                lda     ,u+
                sta     ,y+
                decb
                bne     ampl_text_rad_copy
                ldb     #AMPL_DP3_WIDTH
                stb     >chan_ampl_len
                lbra    ampl_text_label

; ---------------------------------------------------------------------------
; ampl_channel_of - which channel a record belongs to
;
;   entry: X = a channel record
;   exit:  B = 0 to CHANNEL_MAX-1, and 0 for a pointer that is none of them
;   uses:  B
;
; The stock indexes its records by $24F4 and never needs this; here ampl_text
; is handed a record pointer and the per-channel cells beside it - the keyed
; unit and the radian twin - are indexed by number.
; ---------------------------------------------------------------------------
ampl_channel_of
                pshs    u,x
                ldu     #channel_records
                clrb
ampl_channel_next
                cmpu    ,s                      ; the record wanted, as pushed
                beq     ampl_channel_found
                leau    CHAN_RECORD,u
                incb
                cmpb    #CHANNEL_MAX
                blo     ampl_channel_next
                clrb
ampl_channel_found
                puls    x,u,pc

                ; --- a level: the range moves with the number --------------
ampl_text_deviation
                leau    CHAN_AMPL,x
                lbsr    ampl_freq_autorange     ; the same shape, the other
                bra     ampl_text_ranged_tail   ; table
ampl_text_ranged
                leau    CHAN_AMPL,x
                lbsr    ampl_autorange          ; B = the unit it CHOSE,
ampl_text_ranged_tail
                stb     >chan_ampl_unit         ; A = how many characters -
                pshs    a                       ; and the label follows the
                                                ; same answer, so the two can
                                                ; never disagree

                lbsr    ampl_text_clear         ; blank the field first: the
                                                ; answer is five or six
                                                ; characters in a field of
                                                ; nine, and what was there
                                                ; before must not show

                ldb     ,s                      ; AND HOW LONG IT IS, for a
                stb     >chan_ampl_len          ; caller that shows part of
                                                ; the field: five or six, and
                                                ; the difference is where the
                                                ; answer starts
                ldb     #AMPL_TEXT_W            ; RIGHT-ALIGNED, which is
                subb    ,s                      ; where a number belongs and
                ldx     #chan_text              ; what the stock's own leading
                abx                             ; blanks already assume
                ldu     #ampl_range_out
                ldb     ,s+
ampl_text_copy
                lda     ,u+
                sta     ,x+
                decb
                bne     ampl_text_copy

                ; --- and the label, in the two columns beside it -----------
                ; THE RANGED PATH FALLS INTO THIS, so nothing that writes to
                ; the field may sit between the copy loop above and the label
                ; below. ampl_text_blank_field was put here once and the
                ; autoranged value was blanked by the routine it fell into -
                ; the screen showed an empty field with a 'V' beside it, and
                ; tests/test_sequences.py caught it on the next run.
ampl_text_label
                lbsr    ampl_text_unit          ; X = two characters
                ldu     #chan_text+AMPL_TEXT_W
                lda     ,x+
                sta     ,u+
                lda     ,x
                sta     ,u
                rts

ampl_text_blank_field
                lbsr    ampl_text_clear         ; nothing is written over it,
                bra     ampl_text_label         ; so the field stays empty

; ---------------------------------------------------------------------------
; ampl_text_clear - blank the value field
;
;   exit:  X = chan_text
;   uses:  A, B, X
;
; ONE LOOP, not two. The ranged path blanks before right-aligning its five or
; six characters into nine, and the Off/Pulse path blanks and writes nothing
; at all - the same nine bytes either way.
; ---------------------------------------------------------------------------
ampl_text_clear
                ldx     #chan_text
                ldb     #AMPL_TEXT_W
ampl_text_clear_next
                lda     #' '
                sta     ,x+
                decb
                bne     ampl_text_clear_next
                ldx     #chan_text
                rts

; ---------------------------------------------------------------------------
; ampl_text_unit - the two characters that name the AMPTD field's unit
;
;   entry: chan_ampl_unit holds the unit code
;   exit:  X = two characters
;   uses:  A, X
;
; THE THREE VOLTAGE LABELS, not one. ampl_autorange stores the unit it CHOSE
; into chan_ampl_unit before this runs, so the label and the number come from
; the same answer and cannot disagree - which is the whole point of setting it
; there rather than working it out twice.
; ---------------------------------------------------------------------------
ampl_text_unit
                pshs    a
                lda     >chan_ampl_unit
                cmpa    #UNIT_OFF               ; the blank ones first, so
                beq     ampl_unit_blank_label   ; none can fall through to
                cmpa    #UNIT_PULSE             ; the volts label at the end
                beq     ampl_unit_blank_label
                cmpa    #UNIT_DSB               ; the suppressed carrier: the
                bne     ampl_unit_try_ds        ; stock prints 'DSB', and two
                ldx     #ampl_unit_ds           ; columns hold 'DS' - the
                puls    a                       ; same trim 'deg' already
                rts                             ; takes to 'dg'
ampl_unit_try_ds
                cmpa    #UNIT_PERCENT
                bne     ampl_unit_try_rad       ; ON TO THE RADIAN TEST, not
                ldx     #ampl_unit_pct          ; past it: this branch went
                puls    a                       ; straight to the Hz label and
                rts                             ; the arm below could not run
ampl_unit_try_rad
                cmpa    #UNIT_RAD               ; the radian twin's own two
                bne     ampl_unit_try_hz_label  ; columns, beside 'dg'
                ldx     #ampl_unit_rad
                puls    a
                rts
ampl_unit_try_hz_label
                cmpa    #UNIT_HZ
                bne     ampl_unit_try_deg_label
                ldx     #ampl_unit_hz
                puls    a
                rts
ampl_unit_try_deg_label
                cmpa    #UNIT_DEG
                bne     ampl_unit_try_mv_label
                ldx     #ampl_unit_deg
                puls    a
                rts
ampl_unit_try_mv_label
                cmpa    #UNIT_MILLIVOLT
                bne     ampl_unit_try_uv_label
                ldx     #ampl_unit_mv
                puls    a
                rts
ampl_unit_try_uv_label
                cmpa    #UNIT_MICROVOLT
                bne     ampl_unit_volts_label
                ldx     #ampl_unit_uv
                puls    a
                rts
ampl_unit_volts_label
                ldx     #ampl_unit_v
                puls    a
                rts
ampl_unit_blank_label
                ldx     #ampl_unit_none
                puls    a
                rts

ampl_unit_pct   fcc     "% "
ampl_unit_hz    fcc     "Hz"
ampl_unit_deg   fcc     "dg"
ampl_unit_rad   fcc     "rd"
ampl_unit_v     fcc     "V "
ampl_unit_mv    fcc     "mV"
ampl_unit_uv    fcc     "uV"
ampl_unit_none  fcc     "  "        ; Off and Pulse name no unit
ampl_unit_ds    fcc     "DS"        ; the suppressed carrier
