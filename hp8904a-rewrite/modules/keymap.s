; ===========================================================================
; keymap.s - matrix position to key code, and what a key means
;
; The table below is the stock firmware's own, at $EF4A, verified byte for
; byte against the image. Two bytes per matrix position: the unshifted code
; and the shifted one. See common/keys.inc for the codes and for why they are
; kept identical to the instrument's.
;
; Position 0 is a pair of zeros and is never indexed. A scan that finds
; nothing reports KEY_NONE and stops before it gets here; the entry exists so
; that a position of zero reaching this table by mistake produces KEY_NONE
; rather than the first real key.
; ===========================================================================

key_action_table
                fcb     $00,$00         ; 0  never indexed
                fcb     $02,$29         ; 1  row 0 col 0   f1
                fcb     $12,$12         ; 2  row 0 col 1   2
                fcb     $08,$32         ; 3  row 0 col 2   f2
                fcb     $10,$10         ; 4  row 0 col 3   8
                fcb     $0A,$0A         ; 5  row 0 col 4   7
                fcb     $07,$07         ; 6  row 0 col 5   shift
                fcb     $14,$2C         ; 7  row 1 col 0   next
                fcb     $18,$18         ; 8  row 1 col 1   3
                fcb     $0E,$2E         ; 9  row 1 col 2   last
                fcb     $16,$16         ; 10 row 1 col 3   9
                fcb     $09,$09         ; 11 row 1 col 4   -
                fcb     $01,$27         ; 12 row 1 col 5   local
                fcb     $1A,$31         ; 13 row 2 col 0   f3
                fcb     $1E,$1E         ; 14 row 2 col 1   kHz
                fcb     $20,$33         ; 15 row 2 col 2   f4
                fcb     $1C,$1C         ; 16 row 2 col 3   deg
                fcb     $1F,$30         ; 17 row 2 col 4   backspace
                fcb     $21,$21         ; 18 row 2 col 5   spare 0
                fcb     $06,$25         ; 19 row 3 col 0   freq
                fcb     $11,$11         ; 20 row 3 col 1   5
                fcb     $03,$26         ; 21 row 3 col 2   phase
                fcb     $0F,$0F         ; 22 row 3 col 3   0
                fcb     $13,$2F         ; 23 row 3 col 4   up arrow
                fcb     $22,$22         ; 24 row 3 col 5   spare 1
                fcb     $05,$28         ; 25 row 4 col 0   ampl
                fcb     $17,$17         ; 26 row 4 col 1   6
                fcb     $04,$2A         ; 27 row 4 col 2   waveform
                fcb     $15,$15         ; 28 row 4 col 3   .
                fcb     $19,$2D         ; 29 row 4 col 4   down arrow
                fcb     $23,$23         ; 30 row 4 col 5   spare 2
                fcb     $0C,$0C         ; 31 row 5 col 0   1
                fcb     $1D,$1D         ; 32 row 5 col 1   Hz
                fcb     $0B,$0B         ; 33 row 5 col 2   4
                fcb     $1B,$34         ; 34 row 5 col 3   enter
                fcb     $0D,$2B         ; 35 row 5 col 4   inc set
                fcb     $24,$24         ; 36 row 5 col 5   spare 3

; --- which codes are digits, and what each is worth ------------------------
; A lookup, not a range test. The ten digit codes are 15, 12, 18, 24, 11, 17,
; 23, 10, 16 and 22 for 0 to 9 - scattered across the matrix in the order the
; panel lays the keys out, not the order they count in. A range test between
; the codes for 0 and 9 would accept eleven keys that are not digits and
; reject two that are. That test was written here once, before the table was
; read out of the ROM.
KEY_DIGIT_NONE  equ     $FF             ; this code is not a digit

key_digit_values
                fcb     KEY_DIGIT_NONE  ; 0  (no key)
                fcb     KEY_DIGIT_NONE  ; 1  local
                fcb     KEY_DIGIT_NONE  ; 2  f1
                fcb     KEY_DIGIT_NONE  ; 3  phase
                fcb     KEY_DIGIT_NONE  ; 4  waveform
                fcb     KEY_DIGIT_NONE  ; 5  ampl
                fcb     KEY_DIGIT_NONE  ; 6  freq
                fcb     KEY_DIGIT_NONE  ; 7  shift
                fcb     KEY_DIGIT_NONE  ; 8  f2
                fcb     KEY_DIGIT_NONE  ; 9  minus
                fcb     7               ; 10
                fcb     4               ; 11
                fcb     1               ; 12
                fcb     KEY_DIGIT_NONE  ; 13 inc set
                fcb     KEY_DIGIT_NONE  ; 14 last
                fcb     0               ; 15
                fcb     8               ; 16
                fcb     5               ; 17
                fcb     2               ; 18
                fcb     KEY_DIGIT_NONE  ; 19 up arrow
                fcb     KEY_DIGIT_NONE  ; 20 next
                fcb     KEY_DIGIT_NONE  ; 21 point
                fcb     9               ; 22
                fcb     6               ; 23
                fcb     3               ; 24
                fcb     KEY_DIGIT_NONE  ; 25 down arrow
                fcb     KEY_DIGIT_NONE  ; 26 f3
                fcb     KEY_DIGIT_NONE  ; 27 enter
                fcb     KEY_DIGIT_NONE  ; 28 deg
                fcb     KEY_DIGIT_NONE  ; 29 Hz
                fcb     KEY_DIGIT_NONE  ; 30 kHz
                fcb     KEY_DIGIT_NONE  ; 31 backspace
                fcb     KEY_DIGIT_NONE  ; 32 f4
                fcb     KEY_DIGIT_NONE  ; 33 spare 0
                fcb     KEY_DIGIT_NONE  ; 34 spare 1
                fcb     KEY_DIGIT_NONE  ; 35 spare 2
                fcb     KEY_DIGIT_NONE  ; 36 spare 3
KEY_DIGIT_TABLE equ     37              ; entries, 0 to 36

; ---------------------------------------------------------------------------
; key_decode - a matrix position to the key code it means
;
;   entry: B = the position, 1 to 36
;   exit:  B = the key code; KEY_NONE if the position is not one
;   uses:  A, B, X
;
; Applies the shift latch, and CONSUMES it: shift is one-shot, so the latch
; is cleared by the key that used it. Holding shift down and pressing three
; keys shifts the first only, which is what the stock firmware does and what
; the panel legends imply.
;
; The shift key itself sets the latch and reports KEY_NONE, so no screen ever
; sees it. A screen that had to ignore the shift key would be a screen that
; could forget to.
; ---------------------------------------------------------------------------
key_decode
                tstb
                beq     key_decode_none
                cmpb    #KEY_POS_GHOST          ; the scan's two fault
                beq     key_decode_ghost        ; sentinels, before the range
                cmpb    #KEY_POSITIONS          ; check that would swallow
                bhi     key_decode_double       ; them - kbd_decode ($AAE8)
                                                ; tests in the same order,
                                                ; $40 first, then above $24

                lda     #$02                    ; two bytes per position
                mul                             ; D = position * 2
                ldx     #key_action_table
                leax    d,x

                lda     >key_shift              ; the shifted half?
                beq     key_decode_unshifted
                clr     >key_shift              ; one-shot: consume it
                ldb     1,x
                bra     key_decode_check
key_decode_unshifted
                ldb     ,x
key_decode_check
                cmpb    #KEY_SHIFT
                beq     key_decode_shift
                rts
key_decode_shift
                ; ARM THE LATCH AND STILL REPORT THE KEY. This used to fall
                ; into key_decode_none and hand back KEY_NONE, on the reasoning
                ; that no screen has to know shift exists. One does: the
                ; Keyboard Check screen, whose whole purpose is proving every
                ; key on the panel works, and it could not prove this one.
                ;
                ; The stock does the same thing. kbd_decode ($AAE8) sets its
                ; shift latch at the CMPX #$0007 arm and then falls through to
                ; lab71, which RETURNS the code unchanged - which is how the
                ; stock's own Keyboard Check reaches arm [7] of $4A3F and
                ; prints " shift  ".
                ;
                ; No other screen is affected: KEY_SHIFT is 7 and nothing
                ; compares 7 except the diagnostics screen, so for everybody
                ; else an ignored key and an unreported one look identical.
                lda     #$01
                sta     >key_shift
                ldb     #KEY_SHIFT
                rts
key_decode_ghost
                ldb     #KEY_INVALID            ; 'INVALID ' on the Keyboard
                andcc   #~CC_ZERO               ; Check, dropped by the
                rts                             ; foreground everywhere else
key_decode_double
                ldb     #KEY_DOUBLE             ; ' DOUBLE ', likewise
                andcc   #~CC_ZERO
                rts

key_decode_none
                ldb     #KEY_NONE
                rts

; ---------------------------------------------------------------------------
; key_digit - is this key a digit, and which?
;
;   entry: B = the key code
;   exit:  carry CLEAR and B = 0 to 9 if it is a digit;
;          carry SET and B unchanged if it is not
;   uses:  A, B, X
; ---------------------------------------------------------------------------
key_digit
                cmpb    #KEY_DIGIT_TABLE
                bhs     key_digit_no
                ldx     #key_digit_values
                lda     b,x
                cmpa    #KEY_DIGIT_NONE
                beq     key_digit_no
                tfr     a,b
                andcc   #~CC_CARRY
                rts
key_digit_no
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; key_hex_digit - one key as a hexadecimal digit
;
;   entry: B = the key code
;   exit:  B = 0 to 15, carry clear; carry SET and B unchanged if the key is
;          not a hex digit
;   uses:  A, B, X
;
; THE SIX LETTERS, which key_digit cannot produce: it only maps 0 to 9, so
; the Memory Map Access screen - whose whole subject is bit patterns in
; hardware registers, and whose own header says the entry is hex - could not
; type A to F at all. Half of every register's value was unreachable.
;
; The panel has no letter keys, so the stock borrows six it does not need
; while a hex field is open. keypad_char_column_select ($AF29) maps entry
; mode 1 to column 5 of the 16x8 character table at $EF94, and that column,
; read out of a2u12.bin, gives:
;
;   A = kHz ($1E)   B = Hz ($1D)    C = deg ($1C)
;   D = ENTER ($1B) E = minus ($09) F = point ($15)
;
; Those six codes are this firmware's KEY_KHZ, KEY_HZ, KEY_DEG, KEY_ENTER,
; KEY_MINUS and KEY_POINT - 30, 29, 28, 27, 9 and 21 - the same numbers.
;
; ENTER therefore types the letter D on a hex field and does not commit
; anything, which is the stock's behaviour and is why the Memory Map screen
; commits on the second digit instead.
; ---------------------------------------------------------------------------
key_hex_digit
                lbsr    key_digit
                bcc     key_hex_digit_done      ; 0 to 9
                cmpb    #KEY_KHZ
                beq     key_hex_digit_a
                cmpb    #KEY_HZ
                beq     key_hex_digit_b
                cmpb    #KEY_DEG
                beq     key_hex_digit_c
                cmpb    #KEY_ENTER
                beq     key_hex_digit_d
                cmpb    #KEY_MINUS
                beq     key_hex_digit_e
                cmpb    #KEY_POINT
                beq     key_hex_digit_f
                orcc    #CC_CARRY               ; B is untouched: key_digit
                rts                             ; leaves it alone when it
                                                ; refuses
key_hex_digit_a
                ldb     #$0A
                bra     key_hex_digit_done
key_hex_digit_b
                ldb     #$0B
                bra     key_hex_digit_done
key_hex_digit_c
                ldb     #$0C
                bra     key_hex_digit_done
key_hex_digit_d
                ldb     #$0D
                bra     key_hex_digit_done
key_hex_digit_e
                ldb     #$0E
                bra     key_hex_digit_done
key_hex_digit_f
                ldb     #$0F
key_hex_digit_done
                andcc   #~CC_CARRY
                rts

; --- the key names, for the Keyboard Check screen --------------------------
; Eight characters each, indexed by key code. They are the stock firmware's
; own strings, which matter more than they look: this project has never seen
; the instrument's panel legends, so these names are the only written record
; of which key is which. An engineer comparing the screen with the panel is
; comparing against HP's own words.
;
; THESE ARE THE ROM'S NAMES, NOT THE PANEL LEGENDS, and they differ. The
; service manual's key table on printed page 8-39 gives the silkscreen as
; INCR SET (with an R), WAVE FORM (two words), AMPTD and LOCAL, against this
; table's "inc set ", "waveform" and "  local ". The firmware's Keyboard
; Check screen prints ITS strings, so these are what an engineer sees on the
; display - and the panel beside it says something slightly different.
;
; Both are kept as they are: these because they are what the ROM prints, and
; the difference recorded here because an engineer comparing the two should
; find it explained rather than wonder which is wrong.
;
; ALL 37 WERE CHECKED AGAINST THE ROM, not transcribed from a summary. The
; strings live in A2U13 page 3, reached through the 55-entry jump table at
; $4A3F: each arm loads a pointer and the pointer names eight characters.
; Following every arm and comparing gives 37 of 37 identical. That check was
; run because the first version of this table came from a report rather than
; from the image, and a name here that is wrong is wrong in the one place
; that records what a key is called.
;
; Codes 37 to 52 are the shifted forms of keys 1 to 32 and share their names,
; because the panel legend is the same key either way.
KEY_NAME_LEN    equ     8

key_name_nokey
                fcc     "  NOKEY "      ; 0
key_name_local
                fcc     "  local "      ; 1
key_name_f1
                fcc     "   f1   "      ; 2
key_name_phase
                fcc     "  phase "      ; 3
key_name_waveform
                fcc     "waveform"      ; 4
key_name_ampl
                fcc     "  ampl  "      ; 5
key_name_freq
                fcc     "  freq  "      ; 6
key_name_shift
                fcc     " shift  "      ; 7
key_name_f2
                fcc     "   f2   "      ; 8
key_name_minus
                fcc     "   -    "      ; 9
key_name_d7
                fcc     "   7    "      ; 10
key_name_d4
                fcc     "   4    "      ; 11
key_name_d1
                fcc     "   1    "      ; 12
key_name_inc_set
                fcc     "inc set "      ; 13
key_name_last
                fcc     "  last  "      ; 14
key_name_d0
                fcc     "   0    "      ; 15
key_name_d8
                fcc     "   8    "      ; 16
key_name_d5
                fcc     "   5    "      ; 17
key_name_d2
                fcc     "   2    "      ; 18
key_name_up
                fcc     "up arrow"      ; 19
key_name_next
                fcc     "  next  "      ; 20
key_name_point
                fcc     "   .    "      ; 21
key_name_d9
                fcc     "   9    "      ; 22
key_name_d6
                fcc     "   6    "      ; 23
key_name_d3
                fcc     "   3    "      ; 24
key_name_down
                fcc     "dn arrow"      ; 25
key_name_f3
                fcc     "   f3   "      ; 26
key_name_enter
                fcc     "  enter "      ; 27
key_name_deg
                fcc     "   deg  "      ; 28
key_name_hz
                fcc     "   Hz   "      ; 29
key_name_khz
                fcc     "   kHz  "      ; 30
key_name_bkspace
                fcc     "bkspace "      ; 31
key_name_f4
                fcc     "   f4   "      ; 32
key_name_spare0
                fcc     " SPARE0 "      ; 33
key_name_spare1
                fcc     " SPARE1 "      ; 34
key_name_spare2
                fcc     " SPARE2 "      ; 35
key_name_spare3
                fcc     " SPARE3 "      ; 36

; The table's own name as an equ, for the same reason the DDS register
; names carry one: every row has a label so a coverage row can cite the
; key it names, and a bare label with no instruction of its own reads to
; tests/test_no_stubs.py as a routine that returns having done nothing.
key_names        equ     key_name_nokey
KEY_NAMED       equ     37              ; codes 0 to 36 have their own name
key_name_bad    fcc     "INVALID "      ; the stock's own spellings, from
key_name_two    fcc     " DOUBLE "      ; its name table's arms 53 and 54

; ---------------------------------------------------------------------------
; key_name - the eight characters naming a key
;
;   entry: B = the key code, 0 to 52
;   exit:  X = the characters
;   uses:  A, B, X
;
; A shifted code, 37 to 52, is mapped back to the key it belongs to by
; searching the action table for it - the panel legend is the same key
; whether or not shift was held, so there is no second set of names and no
; second table to keep in step.
; ---------------------------------------------------------------------------
key_name
                cmpb    #KEY_INVALID
                beq     key_name_invalid
                cmpb    #KEY_DOUBLE
                beq     key_name_double
                cmpb    #KEY_NAMED
                blo     key_name_direct

                ; A SHIFTED CODE. Walk the action table looking for the
                ; position whose SHIFTED byte is this code, and use that
                ; position's UNSHIFTED byte instead - the panel legend is the
                ; same key either way, so there is one set of names and no
                ; second table to keep in step.
                ;
                ; Thirty-six positions at worst, and this runs once per key
                ; press on one diagnostic screen.
                pshs    b                       ; the code being looked for
                lda     #$01                    ; A = the position
key_name_search
                cmpa    #KEY_POSITIONS
                bhi     key_name_unknown
                pshs    a
                ldb     #$02
                mul                             ; D = position * 2
                ldx     #key_action_table
                leax    d,x                     ; X = this position's pair
                ldb     1,x                     ; its shifted code
                ; 1,s, NOT 2,s. The frame here is the saved position at 0,s
                ; and the code being looked for at 1,s; 2,s is the high byte
                ; of this routine's own RETURN ADDRESS. Return addresses are
                ; $80-$FF in this ROM and shifted codes are $25-$34, so the
                ; compare never matched for any input and every shifted key
                ; came back named "NOKEY" on the Keyboard Check screen.
                cmpb    1,s                     ; the one being looked for?
                beq     key_name_found
                puls    a
                inca
                bra     key_name_search
key_name_found
                leas    1,s                     ; drop the saved position
                ldb     ,x                      ; its UNSHIFTED code
                leas    1,s                     ; drop the code looked for
                bra     key_name_direct
key_name_unknown
                leas    1,s                     ; drop the code looked for
                clrb                            ; nothing matched: NOKEY
key_name_invalid
                ldx     #key_name_bad
                rts
key_name_double
                ldx     #key_name_two
                rts

key_name_direct
                lda     #KEY_NAME_LEN
                mul                             ; D = code * 8
                ldx     #key_names
                leax    d,x
                rts
