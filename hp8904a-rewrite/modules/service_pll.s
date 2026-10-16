; ===========================================================================
; service_pll.s - the reference and PLL check screen
;
; Reports whether the instrument is locked to an external reference and
; whether any of the four fault lines are asserted. Both come from ports the
; foreground already polls; this screen simply shows them instead of only
; acting on them.
;
; THE POLARITY IS THE WHOLE POINT, and it is easy to get backwards:
;
;   kbd_rows ($0000) bit 6: the RETURN SENSE is established and the MEANING
;   is not, and they are separated here because their evidence differs.
;     Established - external_ref_absent ($DC14) is `ldb >kbd_rows / andb #$40
;     / lbeq`, returning 1 when the bit is CLEAR, so SET means present.
;     NOT ESTABLISHED - that the bit means "external reference detect" at
;     all. firmware/symbols.py hedges it twice and says in its own words that
;     the supplied map calls bit 6 that, and it is "the map's word, not
;     anything this ROM names"; grepping all five images for another reader
;     of $0000 bit 6 finds none that names it either. The sense is a fact and
;     the name is a document's claim, and this file used to state both as the
;     ROM's.
;   int_latch ($0100) carries four fault lines, and the foreground reads it
;   and EORs with $0F before testing - so a CLEAR bit there is a fault that
;   IS asserted, and $0F is a healthy instrument
;
; That second one was established by measurement rather than by reading: with
; the port pinned at $00 the firmware stops on "Reverse Power Relay"; pinned
; at $0F it boots. A screen that inverted it would report a healthy machine
; as faulty and send an engineer looking for a problem that is not there.
; ===========================================================================

pll_title       fcc     "Reference and PLL                       "
pll_locked      fcc     "Ext ref: PRESENT                        "
pll_unlocked    fcc     "Ext ref: none                           "
pll_faults      fcc     "Faults:                                 "
pll_none        fcc     "Faults: none                            "

; ---------------------------------------------------------------------------
; pll_reference_present - is an external reference connected?
;
;   exit:  Z clear if a reference is present
;   uses:  A
;
; Bit 6 of the row port. SET means a reference is connected.
;
; That sense is established rather than assumed, and this had it backwards.
; The stock routine at $DC14 is named external_ref_absent, it masks $40, and
; it returns 1 when the bit is CLEAR - so clear is absent and set is present.
; This read "active low, so LOW is present", which would have reported a
; reference on every instrument with nothing plugged into the socket, and
; none on every instrument that had one.
;
; The keypad columns are left idle first so the matrix cannot pull the same
; port about while it is being read.
; ---------------------------------------------------------------------------
REFERENCE_PRESENT equ   $40             ; bit 6, high when one is connected

pll_reference_present
                lbsr    keypad_idle
                lda     >kbd_rows
                anda    #REFERENCE_PRESENT      ; Z clear when the bit is SET,
                rts                             ; which is "present"

; ---------------------------------------------------------------------------
; pll_faults_asserted - which fault lines are active?
;
;   exit:  A = a mask of the asserted faults, bit per line; Z set if none
;   uses:  A
;
; The EOR is what turns "a clear bit means a fault" into a mask that reads
; the way a caller expects: a 1 bit is a fault.
; ---------------------------------------------------------------------------
pll_faults_asserted
                lda     >int_latch
                eora    #$0F                    ; now a 1 bit IS a fault
                anda    #FAULT_OUTPUT_LINES
                rts

; ---------------------------------------------------------------------------
; pll_reference_unlocked - is the reference loop reporting out of lock?
;
;   exit:  Z clear if the loop is unlocked; A = the bit
;   uses:  A
;
; A FIFTH LINE ON THE SAME PORT, and nothing here read it. pll_faults_asserted
; masks $0F and stops, so the four reverse-power lines were polled and this
; one was not - on an instrument whose reference loop losing lock makes every
; frequency it produces wrong.
;
; It is bit 5, and it is NOT inverted. foreground_main_loop ($83A0) computes
; int_latch EOR $0F once into a local at $84CA and then tests that local with
; ANDB #$20 at $84D4 - the EOR only reaches the low four bits, so bit 5 comes
; through as it is read and a SET bit is the fault. On taking it the stock
; paints $EDCF, '!! Reference Loop Reports Out Of Lock !!', beeps its error
; $0C and waits delay_ms($02EE).
; ---------------------------------------------------------------------------
FAULT_OUTPUT_LINES equ  $0F             ; bits 3:0, one per output, and
                                        ; INVERTED: a clear bit is a tripped
                                        ; reverse-power relay, which is why
                                        ; the EOR above comes first. Which
                                        ; bit is which output is settled by
                                        ; foreground_main_loop ($83A0) at
                                        ; $8622-$8679: it tests $08 and puts
                                        ; the ASCII $34 on the screen, $04
                                        ; gives $33, $02 gives $32 and $01
                                        ; gives $31 - so bit 3 is Output 4
                                        ; down to bit 0 for Output 1.
FAULT_REF_UNLOCK equ    $20             ; bit 5, uninverted: SET is unlocked

pll_reference_unlocked
                lda     >int_latch
                anda    #FAULT_REF_UNLOCK
                rts

; ---------------------------------------------------------------------------
; pll_show - paint the screen
;
;   uses:  A, B, X
; ---------------------------------------------------------------------------
pll_show
                lbsr    screen_take_dismiss     ; it reports and takes no
                                                ; input: any key goes back
                lda     #LCD_LINE1
                ldx     #pll_title
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write

                lbsr    pll_reference_present
                beq     pll_show_no_ref
                lda     #LCD_LINE2
                ldx     #pll_locked
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write
                bra     pll_show_faults
pll_show_no_ref
                lda     #LCD_LINE2
                ldx     #pll_unlocked
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write

pll_show_faults
                lbsr    pll_faults_asserted
                bne     pll_show_bad

                ; HEALTHY IS ALSO A RESULT, and it has to be said. This
                ; returned without writing anything, so on a good instrument
                ; the fault half of the screen reported nothing at all - line
                ; 2 kept the reference line and the operator could not tell
                ; "no faults" from "this screen did not look". pll_none, the
                ; sentence that closes exactly that gap, was written and
                ; referenced nowhere.
                lda     #LCD_LINE2
                ldx     #pll_none
                ldb     #SVC_LABEL_LEN
                lbra    lcd_write_line
pll_show_bad
                pshs    a
                lda     #LCD_LINE1
                ldx     #pll_faults
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write
                puls    b                       ; the mask, as two hex digits
                ldx     #text_buffer
                lbsr    byte_to_hex
                lda     #LCD_LINE1+8
                ldx     #text_buffer
                ldb     #2
                lbra    lcd_write

; ---------------------------------------------------------------------------
; The two hardware faults the foreground watches for, in the stock's own
; words. Both strings are read out of a2u12.bin - $EDCF and $EDF7 - and the
; dismissal line is $EE1F, the same one the power-on fault report uses.
; ---------------------------------------------------------------------------
pll_ref_unlock  fcc     "!! Reference Loop Reports Out Of Lock !!"
pll_relay_trip  fcc     "Reverse Power Relay Tripped on Output   "
pll_dismiss     fcc     "Press any key to reset and continue.    "

RELAY_DIGIT_POS equ     $26             ; where the stock writes the output
                                        ; number into that line, from the
                                        ; lcd_write_string_at at $8695

; ---------------------------------------------------------------------------
; fault_report - say which hardware fault has just appeared
;
;   entry: A = the asserted set: bit 5 the reference loop, bits 3:0 the
;          outputs, exactly as pll_reference_unlocked and
;          pll_faults_asserted return them
;   uses:  B, X - A is pushed at entry and pulled at exit, so it survives;
;          it was listed here as clobbered, which teaches callers to save a
;          register this routine already saves
;
; THE MESSAGE SAYS WHICH, which is the whole point and is what this firmware
; did not do. It raised ERR_FAULT_LINE, whose text was a number, on the
; grounds that the mapping from bit to output was not established - and it is
; established, four tests in a row at $8622-$8679 that each store an output
; number and its ASCII digit. See ERR_FAULT_LINE in common/formats.inc for
; the addresses.
;
; THE REFERENCE LOOP WINS when both are asserted. It is the more serious of
; the two: a tripped relay means one output is disconnected, while a loop out
; of lock means every frequency the instrument is producing is wrong. The
; stock reports the loop first as well, at $84D4, before it looks at the low
; nibble at $85D4.
;
; IT INSTALLS THE DISMISS HANDLER, so any key puts the operator back on the
; menu that was showing. The stock paints 'Press any key to reset and
; continue.' and then carries on round its loop, leaving the message up until
; something else repaints - which on an instrument whose screens paint once
; when they open would leave no way to clear it. Saying the same words and
; meaning them is the better half of that.
; ---------------------------------------------------------------------------
fault_report
                pshs    a
                lbsr    screen_take_dismiss     ; any key goes back
                lda     ,s
                bita    #FAULT_REF_UNLOCK
                beq     fault_report_relay

                lda     #LCD_LINE1              ; the loop, and it wins
                ldx     #pll_ref_unlock
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write
                ldb     #ERR_REF_UNLOCK
                bra     fault_report_tail

fault_report_relay
                lda     #LCD_LINE1
                ldx     #pll_relay_trip
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write

                ; WHICH OUTPUT. Highest bit first, so that with more than one
                ; relay down the number shown is the same one the stock shows:
                ; its four tests run $08, $04, $02, $01 in that order and each
                ; overwrites the last, so the LOWEST bit set is what survives
                ; onto its display.
                lda     ,s
                ldb     #'1'
                bita    #$01
                bne     fault_report_digit
                incb
                bita    #$02
                bne     fault_report_digit
                incb
                bita    #$04
                bne     fault_report_digit
                incb                            ; bit 3, Output 4
fault_report_digit
                stb     >text_buffer
                lda     #LCD_LINE1+RELAY_DIGIT_POS
                ldx     #text_buffer
                ldb     #$01
                lbsr    lcd_write
                ldb     #ERR_FAULT_LINE

fault_report_tail
                pshs    b                       ; the error number
                lda     #LCD_LINE2
                ldx     #pll_dismiss
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write
                puls    b
                lbsr    error_record            ; recorded and sounded; the
                                                ; message above stays, which
                                                ; is why it is not error_raise
                puls    a
                rts

; ===========================================================================
; The PLL Check, as the stock's diagnostics menu means it.
;
; pll_check_screen ($530F, A2U13 page 3) is not a status report. It is a
; MANUAL SWEEP of the reference divider: it seeds DDS register $27 with
; $5F5E10, shows the value, and steps it by 100 on the up and down keys while
; a lock indicator on the same line follows the hardware - so an engineer
; finds the value at which the loop locks and reads it off the display. On the
; way out it puts the default back.
;
; Read out of the instruction stream at $530F-$54B5:
;   $531D  d4330 at position 0, 40 characters:
;          'PLL Check - Use UP/DOWN keys.    ' + the softkey pair + ' Exit'
;   $5333  $4358 at position $40, 40 characters:
;          'Loop is unlocked with a value of 123456.'
;   $53A9  int_latch ($0100) AND $20; SET writes 'un' ($5513), clear writes
;          two spaces ($54D5), both 2 characters at position $48 - line 2
;          column 8, over the 'un' of 'unlocked'
;   $53D8  delay_ms($32) = 50 ms per pass
;   $53FF  key $0013 (up) adds the three bytes at $4383 = $000064 = 100 to
;          $3FB1 with add24 ($D392); $541F key $0019 (down) subtracts with
;          sub24 ($D3C6)
;   $5433  dds_param_store($3FB1, $27) - register $27 is 'pll_div', index 39
;          of the name table this file's neighbour service_dds.s carries
;   $5450  uint24_to_ascii8 ($CA8F) renders EIGHT digits at $2414 and
;   $5468  six of them are written at position $61 - line 2 column 33, over
;          the '123456'. The first six: $CA8F writes most significant first
;          and does not blank, so 6,250,000 reads '062500' and a step of 100
;          moves the last digit shown. The two digits it drops are always
;          '00', because the seed ends in two zeros and the step is 100.
;   $5478  delay_ms($96) = 150 ms after a change
;   $5490  f4 restores $4380 into register $27, waits 150 ms and leaves
;
; The seed and the step are the same three bytes this firmware already has:
; dds.s dds_reset_reg27 is $5F,$5E,$10, which is the stock's $4380 exactly,
; so the default comes from the one place that already owns it rather than
; from a second copy that could drift.
;
; THE OUTPUT MOVES WHILE THIS SCREEN IS UP. Register $27 is the reference
; divider and every channel's frequency follows it, which is why the menu
; entry is marked destructive and why the default goes back on the way out.
; ===========================================================================

PLL_REG         equ     $27             ; pll_div, and it is width 4 - three
                                        ; bytes - so dds_write_wide is the
                                        ; routine, not dds_write
PLL_DIGITS      equ     6               ; of the eight uint24_to_text makes
PLL_VALUE_POS   equ     LCD_LINE2+33    ; the stock's $61
PLL_LOCK_POS    equ     LCD_LINE2+8     ; and its $48
PLL_POLL_MS     equ     50              ; its delay_ms($32) per pass
PLL_REDRAW_MS   equ     150             ; and its delay_ms($96) after a change

pll_check_title fcc     "PLL Check - Use UP/DOWN keys.    "
                fcb     $00,$04                 ; the softkey font's 'f' and
                                                ; '4'; see lcd_glyphs
                fcc     " Exit"
pll_check_line  fcc     "Loop is unlocked with a value of 123456."
pll_check_un    fcc     "un"                    ; over the 'un' of 'unlocked'
pll_check_lock_ok fcc   "  "                    ; and what covers it again
pll_check_step  fcb     $00,$00,$64             ; 100, the stock's $4383

; ---------------------------------------------------------------------------
; pll_check_run - the manual reference sweep
;
;   uses:  A, B, X, Y, U
;
; The value lives on the CPU stack for the life of the screen. It is three
; bytes that nothing else needs and that nothing else may clear - the RAM test
; two entries up the same menu clears every scratch byte there is.
; ---------------------------------------------------------------------------
pll_check_run
                lbsr    screen_take_dismiss     ; the loop below reads the
                                                ; keypad itself; this stops
                                                ; the previous screen's
                                                ; handler sitting live under
                                                ; the new display
                lda     #LCD_LINE1
                ldx     #pll_check_title
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write
                lda     #LCD_LINE2
                ldx     #pll_check_line
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write

                leas    -3,s                    ; the divider value
                leax    ,s
                ldu     #dds_reset_reg27        ; the default the power-on
                lbsr    copy24                  ; reset writes, which is the
                                                ; stock's $4380
                leau    ,s
                lbsr    pll_check_program

pll_check_loop
                lbsr    pll_check_lock          ; the indicator follows the
                                                ; hardware every pass, not
                                                ; only when a key is pressed
                ldd     #PLL_POLL_MS
                lbsr    delay_ms
                lbsr    keypad_read             ; Z set when nothing is new
                beq     pll_check_loop
                cmpb    #KEY_F4
                beq     pll_check_leave
                                                ; f4 ALONE, as the stock's
                                                ; check loops do: LOCAL was
                                                ; this firmware's own and the
                                                ; comment here said so
                cmpb    #KEY_UP
                beq     pll_check_up
                cmpb    #KEY_DOWN
                bne     pll_check_loop

                leax    ,s                      ; down: one step less
                ldu     #pll_check_step
                lbsr    sub24
                bra     pll_check_changed
pll_check_up
                leax    ,s
                ldu     #pll_check_step
                lbsr    add24
pll_check_changed
                leau    ,s
                lbsr    pll_check_program
                ldd     #PLL_REDRAW_MS
                lbsr    delay_ms
                bra     pll_check_loop

pll_check_leave
                ldu     #dds_reset_reg27        ; THE DEFAULT GOES BACK. The
                ldb     #PLL_REG                ; stock does it at $5490, and
                lbsr    dds_write_wide          ; without it the instrument is
                ldd     #PLL_REDRAW_MS          ; left with whatever divider
                lbsr    delay_ms                ; the operator stopped on and
                leas    3,s                     ; every frequency it makes is
                lbra    menu_reopen_current     ; wrong

; ---------------------------------------------------------------------------
; pll_check_program - write the value to the divider and show it
;
;   entry: U = the three bytes, high first
;   uses:  A, B, X, U
; ---------------------------------------------------------------------------
pll_check_program
                pshs    u
                ldb     #PLL_REG
                lbsr    dds_write_wide
                ldx     ,s                      ; the same three bytes, for
                leas    2,s                     ; the display
                lbsr    uint24_to_text          ; eight digits in text_buffer

                ; AND THE LEADING ZERO IS BLANKED. Driven side by side
                ; 2026-09-11: the stock's line reads 'a value of  62500.' and
                ; this read 'a value of 062500.' - the same six digits of the
                ; same 6,250,000, with the stock blanking the first. The
                ; header above says $CA8F does not blank, and that is true of
                ; $CA8F; something on the way to the glass does, and the glass
                ; is what an engineer reads.
                ldx     #text_buffer
                ldb     #PLL_DIGITS-1           ; never the last: a value of
pll_check_blank                                 ; zero must show as '0'
                lda     ,x
                cmpa    #'0'
                bne     pll_check_value
                lda     #' '
                sta     ,x+
                decb
                bne     pll_check_blank
pll_check_value
                lda     #PLL_VALUE_POS
                ldx     #text_buffer            ; the FIRST six, which is what
                ldb     #PLL_DIGITS             ; the stock shows
                lbra    lcd_write

; ---------------------------------------------------------------------------
; pll_check_lock - the two characters that make 'locked' read 'unlocked'
;
;   uses:  A, B, X
; ---------------------------------------------------------------------------
pll_check_lock
                lbsr    pll_reference_unlocked  ; Z clear when bit 5 is set,
                bne     pll_check_lock_un       ; which is out of lock
                ldx     #pll_check_lock_ok
                bra     pll_check_lock_put
pll_check_lock_un
                ldx     #pll_check_un
pll_check_lock_put
                lda     #PLL_LOCK_POS
                ldb     #$02
                lbra    lcd_write
