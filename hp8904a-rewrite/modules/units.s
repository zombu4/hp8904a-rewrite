; ===========================================================================
; units.s - scaling a typed number by the unit the operator chose
;
; The instrument stores one representation of each quantity. The unit key
; chooses which decade the typed digits land on, so a unit is a power of ten
; and applying it is repeated multiplication by ten.
;
; THE UNIT CODES ARE THE HARDWARE'S, NOT THIS FIRMWARE'S. They were read out
; of the stock image: sixteen 16-bit pointers at $EEEE index sixteen
; length-prefixed labels at $EF0E, and the table below is what those labels
; say. The codes are kept identical because they appear in the channel
; records, and a record written by one firmware and read by the other must
; mean the same thing.
;
;   0  (blank)   8  (blank)
;   1  kHz       9  s
;   2  Hz       10  ms
;   3  deg      11  %
;   4  rad      12  (blank)
;   5  V        13  (blank)
;   6  mV       14  DSB
;   7  uV       15  (blank)
;
; NOTE WHAT IS ABSENT: there is no MHz and no dB or dBm. This file offered
; MHz until the table was read - the instrument's top frequency is 600 kHz,
; so an MHz key would have had exactly one usable setting and no hardware
; behind it. Amplitude is volts, millivolts or microvolts and nothing else;
; scanning all five stock images for "dB" finds not one occurrence.
;
; THE INTERNAL UNITS, and where each comes from:
;
;   frequency   0.1 Hz     the value IS the tuning word; see frequency.s
;   amplitude   1 uV       the stock ceiling is 10,000,000 and the largest
;                          level the panel expresses is 10 V
;   phase       0.1 deg    the stock ceiling is 3599; see phase.s
;   time        1 ms       the delay timebase is one millisecond
;
; MULTIPLYING BY A POWER OF TEN IS ADDITION, NOT MULTIPLICATION. x10 is
; x8 + x2, both shifts, and the 6809 shifts a 24-bit value in three
; instructions. A general multiply would cost far more and buy nothing.
;
; OVERFLOW IS REPORTED, NEVER WRAPPED. 16,777,215 is the largest 24-bit
; value. Scaling past it silently would give a setting the operator did not
; ask for, on an instrument whose whole purpose is producing the setting that
; was asked for.
;
; AN UNKNOWN UNIT IS REFUSED. This routine used to leave the value alone and
; report success for any code it did not recognise, which turns a caller's
; bug into a wrong instrument setting with nothing to show for it. A code
; with no established decade now sets the carry like an overflow does.
; ===========================================================================

; The unit CODES are in common/formats.inc, where every image can see them.
; The paged screens compare against them and could not.

; How many times to multiply by ten, one entry per code. $FF means the code
; has no established internal scale and is refused rather than guessed at:
; codes 0, 8, 12, 13 and 15 are blank labels that no field uses, and code 14
; is a destination label rather than a unit.
;
; CODE 11 - THE PERCENT - WAS REFUSED HERE, AND SHOULD NOT HAVE BEEN. It is
; the modulation depth, and refusing it meant an AM depth could not be typed
; at all. The scale was called "not established"; it was established all
; along, and the enumeration that would have shown it was never run.
;
; It is tenths of a percent, and that is not inferred. The stock's own
; render_value_with_units ($564E) was CALLED on a booted instrument with the
; unit code set to 11:
;
;       digits 00000010  ->    1.0        digits 00001000  ->  100.0
;       digits 00000100  ->   10.0        digits 00012345  ->  234.5
;
; and set_channel_destination ($78BF)'s unit table gives AM the ceiling at
; $EA6E, which holds $0003E8 = 1000 - exactly 100.0 in those units.
;
; The reasoning that got this wrong is worth keeping. The percent shares its
; formatting arm with the sequence period, and the period had been shown by
; execution to render in HUNDREDTHS. From that it followed that 1000 would be
; a ceiling of 10.00%, which is absurd for an AM depth - and instead of
; treating the absurdity as a signal to go and run the renderer, it was used
; to argue the encoding was unknowable. One emulator call settled it.
UNIT_REFUSE     equ     $FF
UNIT_CONVERT    equ     $FE             ; not a decade count at all: this unit
                                        ; needs arithmetic rather than a power
                                        ; of ten, and unit_apply branches to
                                        ; it. Only radians use it.

; MILLIRADIANS TO TENTHS OF A DEGREE. One radian is 180/pi degrees, so one
; milliradian is 0.5729578 tenths of a degree, and 0.5729578 x 65536 is
; 37549 - which makes the conversion a 16x16 multiply and a shift of sixteen,
; i.e. the top half of the product.
;
; The stock does the same conversion: commit_channel_phase ($66B2) rejects
; above the constant at $EA5D, which reads $188A = 6282, and writes
; $D2A9($221A) - documented as x0.572958 - into the record. 6282 milliradians
; is one whole turn, and 6282 x 37549 >> 16 is 3599, which is 359.9 degrees.
;
; THE CONVERSION DID NOT EXIST. This entry was UNIT_REFUSE, so a phase keyed
; in radians was rejected with ERR_VALUE_TOO_BIG - while phase.s's header
; said "a phase keyed in radians is converted to tenths of a degree on the way
; in", and the table entry beside it said "converted not scaled". Two comments
; promising a conversion that no line performed.
RAD_TO_TENTHS   equ     37549
RAD_MAX         equ     6282            ; a full turn, and the limit the stock
                                        ; refuses above

unit_decades
                fcb     UNIT_REFUSE     ; 0  blank
                fcb     4               ; 1  kHz -> 0.1 Hz
                fcb     1               ; 2  Hz  -> 0.1 Hz
                fcb     1               ; 3  deg -> 0.1 deg
                fcb     UNIT_CONVERT    ; 4  rad, converted not scaled
                fcb     6               ; 5  V   -> uV
                fcb     3               ; 6  mV  -> uV
                fcb     0               ; 7  uV  -> uV
                fcb     0               ; 8  THE UNNAMED UNIT, which the bus
                                        ; mnemonic ET stores ($9862) and whose
                                        ; label at $EF0E is two spaces: the
                                        ; stock's arm for it installs $12/$0B,
                                        ; which is NO scaling - the number as
                                        ; typed. Group 2 of
                                        ; unit_allowed_for_group ($A65A) takes
                                        ; any unit, so a class-2 field can be
                                        ; ended with it. It said UNIT_REFUSE,
                                        ; which is an answer the instrument
                                        ; does not give
                fcb     3               ; 9  s   -> ms
                fcb     0               ; 10 ms  -> ms
                fcb     1               ; 11 %   -> tenths of a percent
                fcb     UNIT_REFUSE     ; 12 blank
                fcb     UNIT_REFUSE     ; 13 blank
                fcb     UNIT_REFUSE     ; 14 DSB
                fcb     UNIT_REFUSE     ; 15 blank



; ---------------------------------------------------------------------------
; unit_shift_left - double a 24-bit value in place
;
;   entry: X = the value
;   exit:  carry SET if it overflowed out of bit 23
;   uses:  A
;
; Least significant byte first, so each carry feeds the next.
; ---------------------------------------------------------------------------
unit_shift_left
                asl     2,x
                rol     1,x
                rol     ,x
                rts                             ; carry is the overflow out

; ---------------------------------------------------------------------------
; unit_times_ten - multiply a 24-bit value by ten
;
;   entry: X = the value
;   exit:  carry SET on overflow
;   uses:  A, B, U
;
; x10 = x8 + x2. Three doublings give x8; the x2 is kept aside first. Every
; step's carry is propagated, because an overflow in the middle is still an
; overflow.
; ---------------------------------------------------------------------------
unit_times_ten
                lbsr    unit_shift_left         ; x2
                bcs     unit_times_ten_over
                ldu     #unit_work              ; keep x2 aside
                pshs    x
                exg     x,u
                puls    u
                lbsr    copy24                  ; unit_work = value x2
                exg     x,u

                lbsr    unit_shift_left         ; x4
                bcs     unit_times_ten_over
                lbsr    unit_shift_left         ; x8
                bcs     unit_times_ten_over

                ldu     #unit_work
                lbsr    add24                   ; x8 + x2 = x10
                rts
unit_times_ten_over
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; unit_div_ten - the 24-bit value at X divided by ten, truncating
;
;   entry: X = the value, most significant byte first
;   exit:  the value is divided in place
;   uses:  A, B
;
; Long division, most significant bit first: the value shifts left out of its
; own top into a remainder, and the bit the shift frees at the bottom takes
; the quotient bit. Twenty-four passes leave the quotient where the dividend
; was. The remainder never exceeds nine, so it fits in A.
;
; It exists for the decimal point: a fraction longer than the unit's decades
; is truncated, which is what the instrument does with 100.55 typed into a
; field whose unit gives one decade.
; ---------------------------------------------------------------------------
unit_div_ten
                pshs    a,b
                clra                            ; the running remainder
                ldb     #24
unit_div_ten_bit
                lsl     2,x                     ; the value left one, its top
                rol     1,x                     ; bit into the carry
                rol     ,x
                rola                            ; and on into the remainder
                cmpa    #10
                blo     unit_div_ten_next
                suba    #10                     ; it fits: the quotient bit is
                inc     2,x                     ; one, and it goes in the place
                                                ; the shift just freed
unit_div_ten_next
                decb
                bne     unit_div_ten_bit
                puls    a,b,pc

; ---------------------------------------------------------------------------
; unit_apply - scale a value by the unit that was chosen
;
;   entry: X = the 24-bit value, B = one of the UNIT_ codes
;   exit:  the value is scaled in place; carry SET if it will not fit
;   uses:  A, B, X, U
;
; AN UNKNOWN UNIT IS REFUSED, with carry, like an overflow. This header used
; to say the opposite - that an unknown code "leaves the value alone and
; reports no error" - which was true of an earlier version and is the stale
; half of the edit the FILE header records deliberately two dozen lines above:
; "A code with no established decade now sets the carry like an overflow
; does." A caller reading the old sentence would have ignored the carry.
; ---------------------------------------------------------------------------
unit_apply
                cmpb    #UNIT_COUNT
                bhs     unit_apply_refused      ; outside the table entirely
                pshs    x
                ldx     #unit_decades
                abx
                ldb     ,x                      ; the decade count
                puls    x
                cmpb    #UNIT_REFUSE
                beq     unit_apply_refused
                cmpb    #UNIT_CONVERT
                beq     unit_apply_radians

                lbra    unit_scale_decades      ; the decades, less whatever a
                                                ; typed point took

; ---------------------------------------------------------------------------
; unit_scale_decades - a value scaled by ten to the power (B - entry_frac)
;
;   entry: X = the 24-bit value in memory, B = the decade count
;   exit:  scaled in place; carry SET and last_error set if it will not fit
;   uses:  A, B, U
;
; A TYPED DECIMAL POINT EATS DECADES. entry_to_scaled_digits ($CDE1) scales
; what was typed by the field's decades LESS the digits that followed the
; point, and when that goes negative it divides - driven on the stock
; 2026-09-11: 100 . 55 then Hz is 100.5 Hz, the second fraction digit
; truncated away, where 1 . 2345 then kHz keeps all four.
;
; It is a routine of its own because the RADIAN entries need it without a unit
; code: a phase typed as 3 and as 3.000 are both three radians on the
; instrument, so the digits are scaled by three decades less the fraction
; before anything converts them.
; ---------------------------------------------------------------------------
unit_scale_decades
                subb    >entry_frac
                beq     unit_scale_none         ; the point ate them all
                bpl     unit_scale_up
                negb                            ; more fraction than decades:
unit_scale_down                                 ; divide, truncating
                lbsr    unit_div_ten
                decb
                bne     unit_scale_down
unit_scale_none
                andcc   #~CC_CARRY
                rts
unit_scale_up
                pshs    b
                lbsr    unit_times_ten
                bcs     unit_apply_over
                puls    b
                decb
                bne     unit_scale_up
                andcc   #~CC_CARRY
                rts
                ; EACH REFUSAL RECORDS WHY. unit_apply set the carry and
                ; nothing else, and its callers report `last_error` - so a
                ; refusal here was reported as whatever had gone wrong last,
                ; which on a fresh instrument is nothing at all. The two
                ; reasons are different and an operator can act on the
                ; difference: a value that overflowed on scaling is too big,
                ; and a unit with no established scale is a fault in the
                ; firmware rather than in what was typed.
unit_apply_over
                puls    b                       ; the decade counter this arm
                                                ; is reached with still on the
                                                ; stack
unit_apply_radians_big
                orcc    #CC_CARRY               ; unit_scale_decades has already
                rts                             ; recorded why

unit_apply_too_big
                ; REACHED WITHOUT A PUSH from the radian path, which is why it
                ; is a separate label rather than a branch into the `puls`
                ; above. Branching there popped a frame that had never been
                ; pushed and the routine returned into whatever the stack held
                ; - the maths harness halted after 6,530 instructions.
                ldb     #ERR_VALUE_TOO_BIG      ; scaling carried out of 24
                stb     >last_error             ; bits, or more than a turn
                orcc    #CC_CARRY
                rts
unit_apply_refused
                ldb     #ERR_UNIT_UNKNOWN       ; no established decade, and
                stb     >last_error             ; guessing one is what this
                orcc    #CC_CARRY               ; tree refuses to do
                rts

; ---------------------------------------------------------------------------
; unit_apply_radians - milliradians in, tenths of a degree out
;
;   entry: X = the value, in milliradians
;   exit:  the value is tenths of a degree; carry SET if it was more than a
;          whole turn and nothing was changed
;   uses:  A, B, X, Y, U
;
; Reached only from unit_apply's UNIT_CONVERT arm. Sixteen bits is enough for
; the input: a whole turn is 6282 milliradians, so anything that does not fit
; is out of range before the multiply and is refused above.
; ---------------------------------------------------------------------------
unit_apply_radians
                ; RADIANS ARE TYPED WHOLE. Driven on the stock 2026-09-11: on
                ; the PHASE field 3 and 3.000 are both 3.000 rad, so the digits
                ; are milliradians only after three decades less whatever the
                ; point took.
                pshs    b
                ldb     #RAD_DECADES
                lbsr    unit_scale_decades
                puls    b
                bcs     unit_apply_radians_big
                ldd     ,x                      ; the top eight bits and the
                                                ; next eight: a value with
                                                ; anything in the top byte is
                                                ; far past a whole turn
                tsta
                bne     unit_apply_too_big
                ldd     1,x
                cmpd    #RAD_MAX
                bhi     unit_apply_too_big      ; MORE THAN A WHOLE TURN is a
                                                ; value that is too big, not a
                                                ; unit with no scale -
                                                ; unit_apply_refused records
                                                ; ERR_UNIT_UNKNOWN, which
                                                ; would send an operator
                                                ; looking for a firmware fault

                pshs    x                       ; the value's address
                ldx     #RAD_TO_TENTHS
                lbsr    mul16                   ; math_product, 32 bits
                puls    x
                clr     ,x                      ; the answer is at most 3599,
                ldd     >math_product           ; so the top byte is zero and
                                                ; the product's top half is
                                                ; the result of >> 16 -
                tst     >math_product+2         ; ROUNDED, as the stock's
                bpl     unit_apply_rad_store    ; fixmul_q16 ($D303) rounds:
                addd    #$0001                  ; $D33D-$D343 adds one when
unit_apply_rad_store                            ; bit 15 of the low word is
                std     1,x                     ; set. Truncating gave 572 for
                andcc   #~CC_CARRY              ; 1000 mrad where the stock
                rts                             ; gives 573; 6282 mrad has low
                                                ; word $4942, so nothing in
                                                ; range rounds up to 3600.
