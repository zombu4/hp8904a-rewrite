; ===========================================================================
; service_serial.s - the serial number screen
;
; What the stock firmware does, and why this replaces it:
;
;   page 3 $7163 refuses the entry unless the CURRENT serial is $0AAE60, the
;   factory-virgin value. A flat battery leaves $000000, so the screen that
;   exists to restore a serial number refuses the one state in which it is
;   needed. HP's answer in the service manual is to replace the A2 Digital
;   Assembly.
;
; Here the serial is writable from any value to any value, always, with no
; codeword and no precondition. The screen shows what is stored, takes a new
; number, and writes it.
;
; The serial is a 24-bit big-endian value at $3FFD-$3FFF displayed as eight
; decimal digits - established from the stock banner routine, which passes
; serial_number and a buffer to a routine named for converting 24 bits to
; eight ASCII digits. 24 bits reaches 16,777,215, so eight digits covers it.
; ===========================================================================

; THE SCREEN HAS TWO LINES AND WAS PAINTING THREE THINGS INTO THEM. The title
; and the prompt were both forty characters at LCD_LINE1, written six
; instructions apart in the same routine, so serial_prompt - "Enter 8 digits:"
; - was overwritten before any key could be pressed and was never once
; visible. serial_stored, the label for the value, was defined and referenced
; nowhere, so the stored serial appeared on line 2 with nothing in front of
; it. And serial_entry_redraw echoed the digits at LCD_LINE2 column 0, on top
; of where that label should have been, rather than at the field position the
; screen declares.
;
; So: line 1 carries the title AND the prompt, line 2 carries the stored value
; and the field being typed, and both have a label.
SERIAL_STORED_POS equ   LCD_LINE2+8     ; the eight digits held now
SERIAL_FIELD_POS equ    LCD_LINE2+22    ; and the eight being typed
; SERIAL_DIGITS is in service_data.s, with the rest of the serial's own
; constants. Only the field's positions on THIS screen belong here.

serial_title    fcc     "Serial Number       Enter up to 8 digits"
serial_line2    fcc     "Stored:          New:                   "
serial_saved    fcc     "Saved.                                  "
serial_virgin   fcc     "Factory virgin                          "
serial_blank    fcc     "Not set (flat batt)                     "

; THE LIMIT IN THIS MESSAGE WAS NOT THE LIMIT THE FIRMWARE ENFORCES. It said
; 8,388,607, which is 2^23 - 1, and the serial is an UNSIGNED 24-bit value
; reaching 16,777,215 - which is what service_data.s and entry.s both say, and
; what the code does: serial_commit branches on entry_value's carry, and
; entry_value takes that from add24's carry out of bit 23. So every value from
; 8,388,608 upwards was accepted and stored while the screen told the operator
; it was too big, on the one screen whose purpose is restoring an identity
; that cannot be looked up anywhere else.
serial_toobig   fcc     "Too big: max 16777215                   "

; ---------------------------------------------------------------------------
; serial_show_armed - the serial screen up, and its field armed
;
;   uses:  A, B, X, Y, U
;
; The instrument's serial screen arms its field as it opens:
; serial_install_arm_key_hook ($7220), reached as serial_number_install_screen
; ($7163) opens, puts the cursor on the field and turns it on with the LBSR
; $ac35 at $722E, local only. This screen is not that one - it replaces it -
; and its field is SERIAL_FIELD_POS, so the cursor goes there: through
; screen_field_arm, the arm every screen on screen_numeric_key shares, after
; the paint.
; ---------------------------------------------------------------------------
serial_show_armed
                lbsr    serial_show
                lbra    screen_field_arm        ; $722E

; ---------------------------------------------------------------------------
; serial_show - display the serial the instrument currently holds
;
;   uses:  A, B, X, Y, U
;
; Says plainly which of the three states the machine is in, because "00000000"
; and "not set" are the same digits and very different situations, and the
; stock firmware's refusals turn on exactly that difference.
; ---------------------------------------------------------------------------
serial_show
                ldx     #screen_numeric_key     ; digits, backspace, ENTER
                lbsr    screen_install
                ldx     #serial_commit
                stx     >screen_commit
                lda     #SERIAL_FIELD_POS
                sta     >screen_field_pos
                lda     #SERIAL_DIGITS
                sta     >screen_field_width
                lbsr    serial_entry_begin      ; the eight-digit field this
                                                ; screen takes
                ldx     #serial_entry_redraw    ; f1 redraws it, which is the
                stx     >screen_f1              ; way back from a half-typed
                                                ; entry without leaving the
                                                ; screen
                ldx     #service_back_handler   ; f4 LEAVES, matching the
                stx     >screen_f4              ; stock's "f4 Exit" on this
                                                ; screen. Without it this
                                                ; screen could be entered and
                                                ; never left from the keypad.
                lda     #LCD_LINE1
                ldx     #serial_title
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write
                lda     #LCD_LINE2              ; the labels for both halves
                ldx     #serial_line2           ; of line 2, so neither value
                ldb     #SVC_LABEL_LEN          ; is a bare number
                lbsr    lcd_write

                lbsr    serial_is_zero
                beq     serial_show_flat

                ; THROUGH serial_read, which is the one routine that reads
                ; those three bytes with interrupts masked. This read them
                ; directly, three separate loads, so the serial could be
                ; caught half-changed - and serial_read, which exists to
                ; prevent exactly that, was never called by anything.
                lbsr    serial_read             ; A = bits 23-16, X = 15-0
                cmpa    #SERIAL_VIRGIN_H        ; is it factory virgin?
                bne     serial_show_value
                cmpx    #SERIAL_VIRGIN_LOW16
                bne     serial_show_value

                lda     #LCD_LINE2              ; a WHOLE-LINE answer: this
                ldx     #serial_virgin
                ldb     #SVC_LABEL_LEN          ; state has no digits to put in
                lbra    lcd_write_line          ; the field, so it replaces both
                                                ; labels rather than sitting next
                                                ; to an empty one

serial_show_flat
                lda     #LCD_LINE2              ; a WHOLE-LINE answer: this
                ldx     #serial_blank
                ldb     #SVC_LABEL_LEN          ; state has no digits to put in
                lbra    lcd_write_line          ; the field, so it replaces both
                                                ; labels rather than sitting next
                                                ; to an empty one

serial_show_value
                ldx     #serial_number
                lbsr    uint24_to_text          ; eight digits in text_buffer
                lda     #SERIAL_STORED_POS      ; INTO the "Stored:" field,
                ldx     #text_buffer            ; not over the label at the
                ldb     #TEXT_DIGITS            ; start of the line
                lbra    lcd_write

; ---------------------------------------------------------------------------
; serial_entry_begin - open the entry field
;
;   uses:  A, B, X
; ---------------------------------------------------------------------------
serial_entry_begin
                ; IT DOES NOT PAINT. It wrote serial_prompt across the whole
                ; of line 1, which serial_show then overwrote with the title
                ; six instructions later - the prompt is part of the title
                ; line now, and this opens the field and nothing else.
                lda     #ENTRY_DECIMAL
                ldb     #SERIAL_DIGITS
                lbra    entry_begin

; ---------------------------------------------------------------------------
; serial_entry_redraw - show the digits typed so far
;
;   uses:  A, B, X
; ---------------------------------------------------------------------------
serial_entry_redraw
                ldx     #text_buffer            ; borrow it as a render area
                lbsr    entry_render
                lda     #SERIAL_FIELD_POS       ; where the screen SAYS the
                ldx     #text_buffer            ; field is. This wrote at
                ldb     >entry_width            ; LCD_LINE2 column 0, over the
                lbra    lcd_write               ; label for the stored value

; ---------------------------------------------------------------------------
; serial_commit - store what was typed
;
;   exit:  the serial number holds the new value
;   uses:  A, B, X, Y, U
;
; NO GUARD. Not on the value being written, and not on the value being
; replaced. Zero is allowed: an operator who wants the machine to read zero
; may have it, and refusing zero is half of the stock deadlock.
; ---------------------------------------------------------------------------
serial_commit
                lbsr    entry_value             ; 24 bits at entry_result
                bcc     serial_commit_fits
                lda     #LCD_LINE2              ; too big - say so and store
                ldx     #serial_toobig          ; NOTHING, rather than store
                ldb     #SVC_LABEL_LEN          ; a different number quietly
                lbra    lcd_write
serial_commit_fits
                lda     >entry_result
                ldx     >entry_result+1
                lbsr    serial_write            ; masked, three stores

                ; RE-ARM THE FIELD. Without this the entry buffer kept the
                ; digits just stored, so the next keypress APPENDED to them:
                ; 12345 saved, then typing 16777216 gave 12345167 and ENTER
                ; stored that over a serial the operator had just got right.
                ; The only feedback was a second "Saved." serial_entry_begin
                ; opens the field and paints nothing, so the message below
                ; still lands on a clean line 2.
                lbsr    serial_entry_begin

                lda     #LCD_LINE2
                ldx     #serial_saved
                ldb     #SVC_LABEL_LEN
                lbra    lcd_write
