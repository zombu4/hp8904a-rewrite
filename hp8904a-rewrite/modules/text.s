; ===========================================================================
; text.s - turning numbers into something a person can read
;
; The display is characters, so every value the instrument shows passes
; through here. Two conversions matter: a 24-bit value to decimal, which is
; how the serial number and every frequency are shown, and a byte to hex,
; which the service screens use for raw memory and register values.
;
; NO DIVISION IS USED. The 6809 has none, div16 above is sixteen iterations
; per call, and a decimal conversion would need eight of those. Repeated
; subtraction of a power of ten is both smaller and faster here: at most nine
; subtractions per digit, and the powers are a table rather than a
; calculation.
; ===========================================================================

; Powers of ten as 24-bit values, most significant first. Eight of them,
; because a 24-bit value reaches 16,777,215 and that is eight digits.
text_powers
                fcb     $98,$96,$80   ; 10,000,000
                fcb     $0F,$42,$40   ;  1,000,000
                fcb     $01,$86,$A0   ;    100,000
                fcb     $00,$27,$10   ;     10,000
                fcb     $00,$03,$E8   ;      1,000
                fcb     $00,$00,$64   ;        100
                fcb     $00,$00,$0A   ;         10
                fcb     $00,$00,$01   ;          1
; (these constants are in common/display.inc, common/formats.inc)

; ---------------------------------------------------------------------------
; format_fixed - n digits with leading zeros blanked and a point dropped in
;
;   entry: X = a 24-bit value in memory, A = how many of its digits to render,
;          B = how many LEADING ZEROS to blank, format_point = the point's
;          index in the output, format_trim non-zero to blank a trailing zero
;   exit:  format_text holds A+1 characters
;   uses:  A, B, X, Y, U
;
; THE STOCK'S OWN PAIR, in one routine. Every value field in the instrument is
; drawn the same way: uint24_to_ascii8 ($CA8F) or u16_to_5_ascii_digits ($C912)
; renders the digits into $2414, blank_leading_zeros ($CCFF) is told HOW MANY
; leading zeros may go, and format_with_decimal_point ($CD50) is told the digit
; count and where the point falls - and it emits count+1 characters, the point
; shifting everything after it along by one. The caller then writes as many of
; those characters as its field is wide, from $2414 or from $2415.
;
; THE BLANK COUNT IS NOT "ALL BUT THE UNITS DIGIT". That was this firmware's
; rule and it is wrong for two fields: the digital screen's period is five
; digits with a blank count of THREE and the point at three, so a period of ten
; counts reads '   .10' with the units place blank, where a rule that always
; kept the units digit would read '  0.10'. The hop screen's Hz frequency is
; eight digits with a blank count of six and the point at seven, so the units
; digit survives there. One count per field, as the stock passes it.
;
; THE TRAILING ZERO is the fifth argument of $CD50, which is 1 for the hop
; screen's kHz form and 0 for its Hz form: measured on the stock over nine
; values, 100 counts reads '  0.010 ' and 1 count reads '  0.0001', so the last
; column is blanked exactly when it is a zero and only in that form.
; ---------------------------------------------------------------------------
format_fixed
                pshs    a,b                     ; 0,s digits, 1,s blanks
                lbsr    uint24_to_text          ; eight, leading zeros kept

                ; THE LAST n OF THE EIGHT are this field's; anything in front
                ; of them is above its range.
                lda     #TEXT_DIGITS
                suba    ,s
                ldx     #text_buffer
                leax    a,x                     ; X = the first digit rendered
                pshs    x                       ; and it is needed again after
                                                ; the blanking, which walks X
                                                ; forward: 0,s X, 2,s digits,
                                                ; 3,s blanks

                ; the leading zeros, at most as many as the caller allows,
                ; blanked IN PLACE - they are part of the field, not skipped
                ldb     3,s
                beq     format_fixed_body
format_fixed_lead
                lda     ,x
                cmpa    #'0'
                bne     format_fixed_body
                lda     #' '
                sta     ,x+
                decb
                bne     format_fixed_lead
format_fixed_body
                puls    x                       ; back to the first of them
                ldu     #format_text

                ; n characters with the point dropped in at its index: the
                ; ones before it, then the point, then the rest
                lda     >format_point
                beq     format_fixed_point      ; a point at nought comes first
                tfr     a,b
format_fixed_whole
                lda     ,x+
                sta     ,u+
                decb
                bne     format_fixed_whole
format_fixed_point
                lda     #'.'
                sta     ,u+
                ldb     ,s                      ; the digits after it
                subb    >format_point
                beq     format_fixed_done
format_fixed_frac
                lda     ,x+
                sta     ,u+
                decb
                bne     format_fixed_frac
                tst     >format_trim
                beq     format_fixed_done
                lda     -1,u
                cmpa    #'0'
                bne     format_fixed_done
                lda     #' '
                sta     -1,u
format_fixed_done
                leas    2,s
                rts

; ---------------------------------------------------------------------------
; uint24_to_text - eight decimal digits, most significant first
;
;   entry: X = a 24-bit value in memory
;   exit:  text_buffer holds eight ASCII digits, leading zeros included
;   uses:  A, B, X, Y, U
;
; Leading zeros are KEPT. A fixed-width field is what every caller wants -
; the display has a fixed number of character cells and a number that changes
; width leaves the old digits behind. text_trim below removes them for the
; callers that want a number rather than a field.
; ---------------------------------------------------------------------------
uint24_to_text
                pshs    x
                ldx     #math_work              ; work on a copy; the caller's
                puls    u                       ; value is not ours to destroy
                pshs    u
                lbsr     copy24
                puls    u

                ldy     #text_powers
                clra                            ; A counts digits emitted
                sta     >text_length
uint24_digit
                ; The digit is built in B and stored at its own position at
                ; the end of the loop. An earlier draft also wrote '0' to
                ; text_buffer here "to be fixed up below", which clobbered
                ; position 0 on EVERY iteration - so the first digit was
                ; correct until the second digit overwrote it, and 16777215
                ; came out as 06777215. Only values needing all eight digits
                ; showed it.
                pshs    a,y
                ldb     #'0'
uint24_subtract
                ldx     #math_work
                pshs    b
                tfr     y,u                     ; U = this power of ten
                lbsr     sub24
                bcc     uint24_fits             ; no borrow: it fitted
                ; it went negative - put it back and stop
                ldx     #math_work
                tfr     y,u
                lbsr     add24
                puls    b
                bra     uint24_digit_done
uint24_fits
                puls    b
                incb                            ; one more of this power
                bra     uint24_subtract
uint24_digit_done
                puls    a,y
                pshs    b                       ; the digit character
                ldx     #text_buffer
                ldb     >text_length
                abx
                puls    b
                stb     ,x                      ; store it in place
                inc     >text_length
                leay    3,y                     ; the next power of ten
                lda     >text_length
                cmpa    #TEXT_DIGITS
                blo     uint24_digit
                rts

; ---------------------------------------------------------------------------
; text_trim - find the first significant digit
;
;   exit:  X = the first non-zero digit in text_buffer, B = how many remain
;   uses:  A, B, X
;
; A value of zero trims to a single "0" rather than to nothing, which is what
; a reader expects and what an empty field does not say.
; ---------------------------------------------------------------------------
text_trim
                ldx     #text_buffer
                ldb     #TEXT_DIGITS
text_trim_next
                cmpb    #1                      ; always keep the last digit
                beq     text_trim_done
                lda     ,x
                cmpa    #'0'
                bne     text_trim_done
                leax    1,x
                decb
                bra     text_trim_next
text_trim_done
                rts

; ---------------------------------------------------------------------------
; nibble_to_hex - one hex digit
;
;   entry: B = a value, only the low four bits are used
;   exit:  A = '0'-'9' or 'A'-'F'
;   uses:  A, B
; ---------------------------------------------------------------------------
nibble_to_hex
                andb    #$0F
                cmpb    #10
                blo     nibble_to_hex_digit
                addb    #'A'-10                 ; $41 - 10: 10 becomes 'A'
                tfr     b,a
                rts
nibble_to_hex_digit
                addb    #'0'
                tfr     b,a
                rts

; ---------------------------------------------------------------------------
; AND THERE IS NO WORD-TO-FOUR-HEX-DIGITS ROUTINE, DELIBERATELY.
;
; uint16_to_hex4_ascii ($CC09) is the instrument's: shift_signed with $F8
; lifts the high byte, byte_to_hex_digits writes two characters, the
; destination pointer is advanced by two IN THE CALLER'S OWN FRAME SLOT
; (LDX >$000A,S / LEAX 2,X / STX >$000A,S) and the low byte follows. Its four
; call sites are all page 3's memory screens.
;
; Here those screens call byte_to_hex below twice instead - see
; modules/service_memmap.s, which renders the address at lines 319 and 322 -
; so the word-level wrapper has nothing left to do. Same four characters, one
; less level of indirection, and no frame slot written behind a caller's back.
; ---------------------------------------------------------------------------
; byte_to_hex - two hex digits
;
;   entry: B = the byte, X = where to put the two characters
;   exit:  [X] and [X+1] hold them, high nibble first
;   uses:  A, B, X
; ---------------------------------------------------------------------------
byte_to_hex
                pshs    b
                lsrb                            ; the high nibble
                lsrb
                lsrb
                lsrb
                bsr     nibble_to_hex
                sta     ,x
                puls    b
                bsr     nibble_to_hex           ; and the low one
                sta     1,x
                rts

; ---------------------------------------------------------------------------
; hex_to_nibble - one ASCII hex digit back to a value
;
;   entry: A = the character
;   exit:  B = 0-15, carry clear; carry SET if it was not a hex digit
;   uses:  A, B
;
; The carry is the caller's only way to tell a bad keystroke from a valid
; zero, and every caller here is an entry field where the difference matters.
; ---------------------------------------------------------------------------
hex_to_nibble
                cmpa    #'0'
                blo     hex_to_nibble_bad
                cmpa    #'9'
                bhi     hex_to_nibble_letter
                suba    #'0'
                tfr     a,b
                andcc   #~CC_CARRY
                rts
hex_to_nibble_letter
                cmpa    #'A'
                blo     hex_to_nibble_bad
                cmpa    #'F'
                bhi     hex_to_nibble_bad
                suba    #'A'-10
                tfr     a,b
                andcc   #~CC_CARRY
                rts
hex_to_nibble_bad
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; format_places - render a 24-bit value into chan_text with a decimal point
;
;   entry: U = the value, B = how many decimal places
;   exit:  chan_text holds the characters
;   uses:  A, B, X, Y, U
;
; The digits come from the shared 24-bit decimal converter, which writes
; eight ASCII digits with leading zeros into text_buffer; this inserts the
; point and turns the leading zeros into spaces. Doing it here rather than in
; the converter keeps the converter usable by the service screens, which want
; a fixed-width integer and no point at all.
;
; IT LIVED ON A2U13 PAGE 0, as chan_format, where only the channel screen
; could reach it. ampl_text in amplitude.s needs exactly this for the units
; that do not autorange, and amplitude.s is in A2U12 - so the choice was to
; write the point insertion a second time or to move the one that already
; existed. It moved, and the channel screen reaches it through
; ABI_format_places.
; ---------------------------------------------------------------------------
; ---------------------------------------------------------------------------
; format_places_zeros - the same, with the leading zeros KEPT
;
; THE BUS AND THE GLASS FORMAT THE SAME NUMBER DIFFERENTLY. Blanking a leading
; zero to a space is right on a forty-column display and wrong on the bus: the
; stock answers 'FRA?' with 0001234.0 and this firmware answered '   1234.0',
; so a controller reading fixed-width fields got different bytes. Measured
; against the stock 2026-09-13 with channel A at 1234.0 Hz.
;
; It is the same routine with the "a real digit has passed" flag pre-set, so
; the blanking test below never fires - which is what "no leading zero is
; blanked" means, expressed once instead of twice.
; ---------------------------------------------------------------------------
format_places_zeros
                stb     >chan_places
                lda     #$01
                sta     >format_keep_zeros
                bra     format_places_go

format_places
                stb     >chan_places
                clr     >format_keep_zeros      ; the screen blanks them
format_places_go
                tfr     u,x                     ; the shared converter takes
                lbsr    uint24_to_text          ; a pointer in X and fills
                                                ; text_buffer with eight
                                                ; ASCII digits, zeros and all

                ; Walk those eight digits out to chan_text, dropping the
                ; point in after (8 - places) of them and turning the leading
                ; zeros into spaces.
                ;
                ; The counters are in scratch rather than on the stack. An
                ; earlier version kept the digit count on the stack, popped
                ; it, and then read it back with "suba ,s" - by which point
                ; ,s was the return address. It assembled, it ran, and the
                ; decimal point landed wherever the high byte of the return
                ; address happened to put it. tests/test_stack_balance.py
                ; found it.
                lda     #TEXT_DIGITS
                suba    >chan_places
                sta     >chan_before            ; how many come before it
                clr     >chan_seen              ; no real digit passed yet
                clr     >chan_index

                ldx     #text_buffer
                ldy     #chan_text
format_places_next
                lda     >chan_index
                cmpa    #TEXT_DIGITS
                bhs     format_places_done
                ldb     a,x                     ; this digit, as ASCII

                cmpb    #'0'
                bne     format_places_keep        ; a real digit: always kept
                tst     >chan_seen
                bne     format_places_keep        ; a zero after a real digit
                tst     >format_keep_zeros        ; and every one of them when
                bne     format_places_keep        ; the caller is the bus
                lda     >chan_index             ; a LEADING zero: keep it only
                inca                            ; if it is the last one before
                cmpa    >chan_before            ; the point, so a value below
                bhs     format_places_keep        ; one reads 0.5 and not .5
                ldb     #' '
                bra     format_places_store
format_places_keep
                lda     #$01
                sta     >chan_seen
format_places_store
                stb     ,y+
                lda     >chan_index
                inca
                sta     >chan_index
                cmpa    >chan_before
                bne     format_places_next
                ldb     #'.'                    ; that was the last digit
                stb     ,y+                     ; before the point
                bra     format_places_next
format_places_done
                rts
