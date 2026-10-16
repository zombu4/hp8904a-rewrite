; ===========================================================================
; math.s - the arithmetic the instrument needs
;
; The 6809 has an 8x8 unsigned MUL and nothing else: no divide, no 16-bit
; multiply, no 24-bit anything. Everything here is built from that.
;
; 24-BIT VALUES are the instrument's natural width. The serial number is one,
; and so is every frequency and phase the DDS is programmed with, because 16
; bits cannot express a frequency to the resolution this instrument offers
; and 32 would waste a byte in every table. They are stored big-endian, most
; significant byte first, the same order the CPU stores 16-bit values in.
;
; A 24-bit value does not fit a register pair, so the convention here is:
;
;   in memory   three bytes, pointed at by X or U
;   in flight   A holds bits 23-16 and X holds bits 15-0
;
; and routines say which they take. Mixing the two is the easiest mistake to
; make in this file, so no routine accepts both.
; ===========================================================================

; ---------------------------------------------------------------------------
; mul16 - unsigned 16 x 16 into 32 bits
;
;   entry: D and X = the two factors
;   exit:  the 32-bit product at math_product, most significant byte first
;   uses:  A, B, X, Y
;
; Four 8x8 partial products, summed with the carries propagated by hand,
; which is what MUL leaves for the caller to do:
;
;   D = dh:dl, X = xh:xl
;   product = dh*xh<<16 + (dh*xl + dl*xh)<<8 + dl*xl
;
; The middle two can each carry into the top, and both carries have to be
; added - dropping the second is the classic way this comes out almost right,
; wrong only for large operands, which is exactly the case nobody tests.
; ---------------------------------------------------------------------------
mul16
                std     >math_a                 ; keep both factors where the
                stx     >math_b                 ; partial products can reach

                ; CLEAR THE TOP HALF FIRST. The partial products below ADD
                ; into $math_product+0 and +1, so whatever those bytes held
                ; is carried into the answer - and they held the previous
                ; call's result, because only +2 and +3 were ever written
                ; outright.
                ;
                ; 300 x 300 gave 90000 from zeroed RAM and 2 x 3 immediately
                ; after gave 65542: the $0001 left over from the first.
                ; test_math.py could not see it because it called mul16 once,
                ; first, on a machine whose RAM the emulator had zeroed.
                clra
                clrb
                std     >math_product

                ; An LDD of math_a+1 stood here and was dead: the two loads
                ; below overwrite both halves of D before the MUL. Removed
                ; rather than left as a line a reader has to decide about.
                lda     >math_b+1               ; dl * xl
                ldb     >math_a+1
                mul
                std     >math_product+2         ; the low half, exactly

                lda     >math_a                 ; dh * xl
                ldb     >math_b+1
                mul
                addd    >math_product+1         ; into the middle
                std     >math_product+1
                bcc     mul16_no_carry_1
                inc     >math_product           ; the carry the ADDD made
mul16_no_carry_1
                lda     >math_a+1               ; dl * xh
                ldb     >math_b
                mul
                addd    >math_product+1
                std     >math_product+1
                bcc     mul16_no_carry_2
                inc     >math_product           ; and this one too - BOTH
mul16_no_carry_2                                ; middle products can carry
                lda     >math_a                 ; dh * xh
                ldb     >math_b
                mul
                addd    >math_product           ; into the top half
                std     >math_product
                rts

; ---------------------------------------------------------------------------
; THERE IS NO 8-BIT DIVIDE HERE, AND THE INSTRUMENT HAS ONE.
;
; divide_bytes ($FE5F) is 95 bytes of restoring 8-bit division: it returns
; B = 0 at once when A or B is zero, shifts the divisor left counting the
; shifts until the top bit falls out, RORBs it back, and runs that many
; subtract/restore steps. It has exactly two call sites in the five images,
; $CA26 and $CA7B, and both are inside format_three_digits ($C9D1), where it
; divides a weight of 100 by 10 between digits.
;
; This firmware renders those same three digits through uint24_to_text and a
; blank-leading-zeros pass - modules/errors.s, the error banner - so the byte
; divide has no caller to serve and is not here. Error 123 reads '123' and
; error 3 reads '  3' on both firmwares, which is the thing to check if that
; is ever in doubt.
;
; If a routine ever needs an 8-bit divide, div16 below takes the same operands
; zero-extended and costs a fixed sixteen iterations. Read this before adding
; a second one.
; ---------------------------------------------------------------------------
; div16 - unsigned 16 / 16
;
;   entry: X = dividend, D = divisor
;   exit:  X = quotient, D = remainder; carry set if the divisor was zero
;   uses:  A, B, X, Y
;
; Restoring division, one trial subtraction per bit. Sixteen iterations
; regardless of the operands, so it takes the same time every call - which a
; routine inside a timed display update wants.
;
; DIVISION BY ZERO returns with the carry set and does not trap. A synthesizer
; that stops because a scaling factor came out zero is worse than one that
; carries on with a value the caller can check for, and every caller here is
; a display or a register calculation where the sensible response is to leave
; the field alone.
; ---------------------------------------------------------------------------
div16
                cmpd    #$0000
                bne     div16_go
                orcc    #CC_CARRY               ; divisor zero: say so
                rts
div16_go
                std     >math_b                 ; the divisor
                stx     >math_a                 ; the dividend
                ldx     #$0000                  ; running remainder
                clr     >math_count
                lda     #16
                sta     >math_count
div16_bit
                asl     >math_a+1               ; shift the dividend left,
                rol     >math_a                 ; its top bit into the
                exg     x,d                     ; remainder
                rolb
                rola
                exg     x,d
                cmpx    >math_b                 ; does the divisor fit?
                blo     div16_no_fit
                pshs    d
                tfr     x,d
                subd    >math_b                 ; it fits: subtract it
                tfr     d,x
                puls    d
                inc     >math_a+1               ; and set the quotient bit
div16_no_fit
                dec     >math_count
                bne     div16_bit
                tfr     x,d                     ; D = remainder
                ldx     >math_a                 ; X = quotient
                andcc   #~CC_CARRY              ; no error
                rts

; ---------------------------------------------------------------------------
; add24 - three-byte addition
;
;   entry: X = the value to add to, U = the value to add
;   exit:  [X] = [X] + [U]; carry set on overflow out of bit 23
;   uses:  A, B
; ---------------------------------------------------------------------------
add24
                ldb     2,x                     ; least significant first
                addb    2,u
                stb     2,x
                ldb     1,x
                adcb    1,u
                stb     1,x
                ldb     ,x
                adcb    ,u
                stb     ,x
                rts                             ; carry is the overflow

; ---------------------------------------------------------------------------
; sub24 - three-byte subtraction
;
;   entry: X = the value to subtract from, U = the value to subtract
;   exit:  [X] = [X] - [U]; carry set if it went below zero
;   uses:  A, B
;
; The borrow out is what makes the decimal conversion below work: it subtracts
; a power of ten repeatedly until the borrow says it went too far.
; ---------------------------------------------------------------------------
sub24
                ldb     2,x
                subb    2,u
                stb     2,x
                ldb     1,x
                sbcb    1,u
                stb     1,x
                ldb     ,x
                sbcb    ,u
                stb     ,x
                rts

; ---------------------------------------------------------------------------
; copy24 - move three bytes
;
;   entry: X = destination, U = source
;   uses:  A
; ---------------------------------------------------------------------------
copy24
                lda     ,u
                sta     ,x
                lda     1,u
                sta     1,x
                lda     2,u
                sta     2,x
                rts

; ---------------------------------------------------------------------------
; is_zero24 - is a three-byte value zero?
;
;   entry: X = the value
;   exit:  Z set if all three bytes are zero
;   uses:  A
; ---------------------------------------------------------------------------
is_zero24
                lda     ,x
                ora     1,x
                ora     2,x                     ; Z is set only if all three
                rts                             ; contributed nothing
