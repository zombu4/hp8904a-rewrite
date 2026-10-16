; ===========================================================================
; lcd.s - the front-panel display, an HD44780 character LCD
;
; Two ports, both write-mostly:
;
;   lcd_instr ($0300)  command register when written; when READ, bit 7 is
;                      the controller's busy flag and bits 6-0 are its
;                      address counter
;   lcd_data  ($0301)  character data in and out
;
; THE BUSY FLAG IS NOT OPTIONAL. An HD44780 takes tens of microseconds to
; finish most commands and 1.5 ms to clear the display, and it ignores
; anything written while it is busy. At 2 MHz the CPU can issue a second
; write long before the first has landed, so every access here waits first.
; The stock firmware does the same, and the wait is the reason its display
; code is not full of arbitrary delay loops.
;
; The screen is two lines of forty characters. The controller's DDRAM is not
; contiguous across them - line 1 starts at $00 and line 2 at $40 - which is
; why LCD_LINE2 exists rather than a multiply.
; ===========================================================================

; (these constants are in common/display.inc, common/formats.inc)

; ---------------------------------------------------------------------------
; lcd_wait - block until the controller is ready
;
;   exit:  the controller is not busy
;   uses:  A
;
; Every other routine here goes through this. It is deliberately the only
; place that reads the busy flag, so there is one answer to "how do we know
; the display is ready" rather than one per call site.
;
; There is no timeout. A controller that never clears busy is a hardware
; fault, and spinning is the honest response: continuing would write into a
; part that is not listening and leave a display showing something that was
; never sent. The diagnostics menu's display test is where that fault is
; meant to be found.
; ---------------------------------------------------------------------------
lcd_wait
                lda     >lcd_instr
                bmi     lcd_wait                ; bit 7 set: still busy
                rts

; ---------------------------------------------------------------------------
; lcd_command - send one instruction byte
;
;   entry: A = the command
;   uses:  A
; ---------------------------------------------------------------------------
lcd_command
                pshs    a
                bsr     lcd_wait
                puls    a
                sta     >lcd_instr
                rts

; ---------------------------------------------------------------------------
; lcd_put - send one character
;
;   entry: A = the character
;   uses:  A
; ---------------------------------------------------------------------------
lcd_put
                pshs    a
                bsr     lcd_wait
                puls    a
                sta     >lcd_data
                rts

; ---------------------------------------------------------------------------
; READING THE PANEL BACK. lcd_get is the instrument's lcd_read_data ($D761)
; and it is live: service_diag.s:1291 uses it for the LCD Display Check.
;
; What this firmware does NOT do with it is what the stock's
; level_sign_right_justify ($4569) does - walk right from the field's first
; column reading each character back until one is not a blank, to find where
; the sign goes. That is computed here instead, in modules/page2_digital.s
; around line 1487, which is the one difference and is invisible on the glass:
; a first significant digit of '0' gets no sign on either firmware, which is
; why the instrument's Off Lev reads '     0 uV' with nothing in front of it.
;
; Recorded here rather than only in the ledger because a reader wondering
; whether this firmware can read the panel back will look in this file.
; ---------------------------------------------------------------------------
; lcd_get - read the character under the address counter
;
;   exit:  A = the character
;   uses:  A
; ---------------------------------------------------------------------------
lcd_get
                bsr     lcd_wait
                lda     >lcd_data
                rts

; ---------------------------------------------------------------------------
; lcd_address - read the controller's address counter
;
;   exit:  A = the current DDRAM or CGRAM address, 0-127
;   uses:  A
;
; The same read that carries the busy flag carries the address in bits 6-0.
; Used where a routine has to put the cursor back exactly where it found it -
; the sequencer does this so that a display update from an interrupt does not
; move the cursor out from under an entry field.
; ---------------------------------------------------------------------------
lcd_address
                bsr     lcd_wait
                lda     >lcd_instr
                anda    #LCD_BUSY^$FF           ; drop the busy bit, keep 6-0
                rts

; ---------------------------------------------------------------------------
; lcd_cursor - move the cursor
;
;   entry: A = DDRAM address; LCD_LINE1 or LCD_LINE2 plus a column
;   uses:  A
; ---------------------------------------------------------------------------
lcd_cursor
                ora     #LCD_SET_DDRAM
                bra     lcd_command             ; tail call: its RTS is ours

; ---------------------------------------------------------------------------
; lcd_clear - clear the display and home the cursor
;
;   uses:  A, B, Y - B and Y through lcd_shadow_fill, which puts them back
;
; This is the one command that takes milliseconds rather than microseconds.
; No delay is needed here because every routine waits on the busy flag before
; its own access - the cost is paid by whoever writes next, which is the
; right place for it.
; ---------------------------------------------------------------------------
lcd_clear
                pshs    a,b                     ; AND THE SHADOW WITH IT: an
                lda     #LCD_LINE1              ; empty display is eighty
                ldb     #LCD_SHADOW_LEN         ; spaces, and a cold machine
                lbsr    lcd_shadow_fill         ; must not repaint whatever the
                puls    a,b                     ; battery left in these cells
                lda     #LCD_CLEAR
                lbra    lcd_command

; ---------------------------------------------------------------------------
; lcd_shadow_at - which of the eighty cells a DDRAM address is
;
;   entry: A = a DDRAM address
;   exit:  Y = that cell in lcd_shadow and carry CLEAR; carry SET if the
;          address is not one of the eighty, and then Y means nothing
;   uses:  A, Y
;
; THE STOCK'S FOLD. lcd_write_clipped ($D8EA) does `CMPB #$27 / BLS` and
; otherwise `SUBB #$18`, so line 2's $40 becomes cell 40 and the two lines are
; one run. The addresses between them ($28-$3F) exist in the controller and
; are on neither line; a write there is refused rather than folded into
; somebody else's cell, which is what a plain subtraction would do.
; ---------------------------------------------------------------------------
lcd_shadow_at
                cmpa    #LCD_COLUMNS
                blo     lcd_shadow_at_cell      ; $00-$27: line 1, as it is
                cmpa    #LCD_LINE2
                blo     lcd_shadow_at_none      ; $28-$3F: on neither line
                suba    #LCD_LINE2-LCD_COLUMNS  ; $18, the stock's own constant
                cmpa    #LCD_SHADOW_LEN
                bhs     lcd_shadow_at_none      ; past line 2's last column
lcd_shadow_at_cell
                ldy     #lcd_shadow
                leay    a,y
                andcc   #~CC_CARRY
                rts
lcd_shadow_at_none
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; lcd_shadow_copy - mirror a counted string into the shadow
; lcd_shadow_fill - mirror a run of spaces into it
;
;   entry: A = the DDRAM address, B = how many characters,
;          and for lcd_shadow_copy X = the characters
;   uses:  nothing - every register is put back
;
; CLIPPED AT THE END, which is the stock's `LDA #$50 / LDB position /
; sub_bytes_to_word` at $D904: a caller that asks for more characters than are
; left gets the ones that fit. Without it a forty-character write at column 20
; would run off the end of the buffer and into whatever RAM follows.
; ---------------------------------------------------------------------------
lcd_shadow_copy
                pshs    a,b,x,y                 ; ,s A  1,s B  2,s X  4,s Y
                bsr     lcd_shadow_at
                bcs     lcd_shadow_copy_done
                nega                            ; A = 80 - position, 1 to 80:
                adda    #LCD_SHADOW_LEN         ; how many cells are left
                cmpa    1,s
                bhs     lcd_shadow_copy_len     ; the caller's count fits
                sta     1,s                     ; it does not: clip it
lcd_shadow_copy_len
                ldb     1,s
                beq     lcd_shadow_copy_done    ; a count of zero mirrors nothing
lcd_shadow_copy_next
                lda     ,x+
                sta     ,y+
                decb
                bne     lcd_shadow_copy_next
lcd_shadow_copy_done
                puls    a,b,x,y,pc

lcd_shadow_fill
                pshs    a,b,y                   ; ,s A  1,s B  2,s Y
                bsr     lcd_shadow_at
                bcs     lcd_shadow_fill_done
                nega
                adda    #LCD_SHADOW_LEN
                cmpa    1,s
                bhs     lcd_shadow_fill_len
                sta     1,s
lcd_shadow_fill_len
                ldb     1,s
                beq     lcd_shadow_fill_done
                lda     #' '
lcd_shadow_fill_next
                sta     ,y+
                decb
                bne     lcd_shadow_fill_next
lcd_shadow_fill_done
                puls    a,b,y,pc

; ---------------------------------------------------------------------------
; lcd_repaint - put the screen back from the shadow
;
;   uses:  A, B, X, Y
;
; The stock's lcd_repaint_shadow ($D9C6): clear the bit that held the glass,
; then lcd_repaint_both_lines ($D989) from the buffer - 40 characters at DDRAM
; $00 and 40 at $40. What was on the display before a flash went up is exactly
; what the shadow holds, values and all, because every painting routine mirrors
; into it.
; ---------------------------------------------------------------------------
lcd_repaint
                clr     >lcd_hold
                lda     #LCD_LINE1
                ldx     #lcd_shadow
                ldb     #LCD_COLUMNS
                lbsr    lcd_write_raw
                lda     #LCD_LINE2
                ldx     #lcd_shadow+LCD_COLUMNS
                ldb     #LCD_COLUMNS
                lbra    lcd_write_raw

; ---------------------------------------------------------------------------
; lcd_write - write a counted string at a position
;
;   entry: A = DDRAM address, X = the bytes, B = how many
;   exit:  the string is on the display
;   uses:  A, B, X
;
; Counted, not terminated. A terminator costs a byte per string and makes it
; impossible to write a string containing that byte; a count makes the length
; visible at the call site, which is what the callers want anyway since every
; field on this display has a fixed width.
;
; A count of zero writes nothing and still positions the cursor, which is
; what a caller clearing a field to nothing expects.
; ---------------------------------------------------------------------------
lcd_write
                pshs    a,b,x                   ; THE SHADOW FIRST AND ALWAYS,
                lbsr    lcd_shadow_copy         ; painted or not - the stock
                puls    a,b,x                   ; mirrors on both paths through
                                                ; $D8EA and only the painting is
                                                ; conditional
                tst     >lcd_hold
                bne     lcd_write_held          ; a flash owns the glass
lcd_write_raw
                lbsr    lcd_cursor              ; A is consumed here
lcd_write_next
                tstb
                beq     lcd_write_done
                lda     ,x+
                pshs    b
                lbsr    lcd_put
                puls    b
                decb
                bra     lcd_write_next
lcd_write_done
lcd_write_held
                rts

; ---------------------------------------------------------------------------
; lcd_blank - clear a field to spaces
;
;   entry: A = DDRAM address, B = how many characters
;   uses:  A, B
;
; Blanking a field is the commonest display operation in the whole firmware -
; every value that changes width has to erase what it used to be - so it is
; worth one routine rather than a loop at each site.
;
; An earlier version of this took the fill character from a RAM byte called
; lcd_pad. There is no such byte: it was invented, and the assembler caught
; it as an undefined symbol. Every caller wants spaces, so the character is
; simply a constant here. If something ever needs a different one it can have
; its own entry point rather than a location in the RAM map, which is fixed
; by data already in the instrument and is not somewhere to add scratch.
;
; A count of zero writes nothing and still positions the cursor.
; ---------------------------------------------------------------------------
lcd_blank
                pshs    a,b
                lbsr    lcd_shadow_fill         ; the blanked run is part of the
                puls    a,b                     ; screen, so it is part of the
                                                ; shadow
                tst     >lcd_hold
                bne     lcd_blank_held
lcd_blank_raw
                lbsr    lcd_cursor              ; A is consumed here
lcd_blank_next
                tstb
                beq     lcd_blank_done
                lda     #' '
                pshs    b
                lbsr    lcd_put
                puls    b
                decb
                bra     lcd_blank_next
lcd_blank_done
lcd_blank_held
                rts

; ---------------------------------------------------------------------------
; lcd_blank_line - clear one whole line
;
;   entry: A = LCD_LINE1 or LCD_LINE2
;   uses:  A, B
; ---------------------------------------------------------------------------
lcd_blank_line
                ldb     #LCD_COLUMNS
                bra     lcd_blank

; ---------------------------------------------------------------------------
; lcd_write_line - write a string and blank the rest of the line
;
;   entry: A = LCD_LINE1 or LCD_LINE2, X = the characters, B = how many
;   uses:  A, B, X, Y
;
; WHY THIS EXISTS. Five separate screens painted a short message onto line 2
; with lcd_write and left the rest of the line holding the previous screen's
; characters - an error number over the tail of a menu entry, a hop slot
; number over half a title, a "Sending:" prompt with somebody else's digits
; after it. Each was reported as its own defect; they are one shape, and a
; caller cannot get it right by remembering, because getting it right means
; knowing how long the LAST thing written was.
;
; So this takes what to write and blanks to the end of the line itself. A
; caller that genuinely wants to paint INTO an existing line - a field echo,
; a cursor - still uses lcd_write, which writes exactly what it is given.
; ---------------------------------------------------------------------------
lcd_write_line
                pshs    a,b                     ; the position and the length
                lbsr    lcd_write               ; the characters themselves

                ldb     #LCD_COLUMNS            ; then spaces to the end
                subb    1,s
                bls     lcd_write_line_done     ; it filled the line, or
                                                ; overran it - in which case
                                                ; blanking backwards would
                                                ; erase what was just written
                lda     ,s
                adda    1,s                     ; where the text ended
                lbsr    lcd_blank               ; AND THE SHADOW WITH IT. This
                                                ; was a cursor and a run of
                                                ; lcd_put, which paints the
                                                ; glass and nothing else - so
                                                ; every line written this way
                                                ; left the shadow holding the
                                                ; PREVIOUS screen's tail, and a
                                                ; repaint put that tail back.
lcd_write_line_done
                puls    a,b
                rts

; ---------------------------------------------------------------------------
; lcd_write_line_raw - the same line, painted over the shadow rather than into
; it
;
;   entry: A = LCD_LINE1 or LCD_LINE2, X = the characters, B = how many
;   uses:  A, B, X, Y
;
; The stock's lcd_write_string_at ($D8A5) - "the same routine without the
; clipping or the shadow copy". show_last_error_screen ($C418) paints with it,
; which is why the screen underneath survives the three seconds and comes back
; whole.
;
; It ignores lcd_hold as well: the flag exists to keep everything ELSE off the
; glass while a flash is up, and the flash itself must still be able to paint.
; ---------------------------------------------------------------------------
lcd_write_line_raw
                pshs    a,b
                lbsr    lcd_write_raw
                ldb     #LCD_COLUMNS
                subb    1,s
                bls     lcd_write_line_raw_done ; it filled the line or overran
                lda     ,s
                adda    1,s
                lbsr    lcd_blank_raw
lcd_write_line_raw_done
                puls    a,b
                rts

; ---------------------------------------------------------------------------
; lcd_define - load one user-definable character
;
;   entry: A = which character, 0 to 7; X = eight rows of pixels
;   uses:  A, B, X
;
; The HD44780 keeps eight 5x8 characters in CGRAM. The instrument uses them
; for the symbols its font has no room for. Writing CGRAM leaves the address
; counter pointing into CGRAM, so this puts it back to DDRAM afterwards -
; forgetting that is how a character definition ends up painted across the
; middle of the display.
; ---------------------------------------------------------------------------
lcd_define
                anda    #LCD_CGRAM_CHARS-1      ; 0-7, nothing wilder
                lsla                            ; eight rows per character
                lsla
                lsla
                ora     #LCD_SET_CGRAM
                lbsr    lcd_command
                ldb     #LCD_CGRAM_ROWS
lcd_define_row
                lda     ,x+
                pshs    b
                lbsr    lcd_put
                puls    b
                decb
                bne     lcd_define_row
                lda     #LCD_LINE1              ; back to DDRAM, or the next
                lbra    lcd_cursor              ; write lands in CGRAM

; ---------------------------------------------------------------------------
; The eight user-definable characters, copied byte for byte from the stock
; ROM at $EA15.
;
; The HD44780's font has no phi and no mu, and this firmware needs both: phi
; names the phase-modulation destination and mu is the microvolt unit. They
; are characters $05 and $06, which is where the stock firmware puts them and
; where common/labels.inc already expected to find them - lcd_define existed
; to load them and NOTHING CALLED IT, so every one of these was an undefined
; character and the destination column would have shown whatever the CGRAM
; happened to hold.
;
; Eight rows of five pixels each, the low five bits of each byte. The first
; five are the SOFTKEY font - an 'f' and the digits 1 to 4, each over a full
; rule, which is how the front panel draws f1 to f4 - and the last is a swept
; arrow. They were commented as "small digits" one out of step, the 'f' called
; a 1 and each digit called its successor; the bitmaps below are unchanged and
; were always right. A2U13 page 3's own strings use them: d41e2 reads
; `Press "` $00 $04 `" twice to exit this check.` - character $00 then
; character $04, which is this font's 'f' and its '4'.
; ---------------------------------------------------------------------------
lcd_glyphs
                fcb     $06,$09,$08,$1C,$08,$08,$00,$1F   ; 0  f, over a rule: the softkey prefix
                fcb     $04,$0C,$04,$04,$04,$0E,$00,$1F   ; 1  1, over a rule: f1
                fcb     $0C,$12,$04,$08,$10,$1E,$00,$1F   ; 2  2, over a rule: f2
                fcb     $1E,$02,$04,$02,$12,$0C,$00,$1F   ; 3  3, over a rule: f3
                fcb     $10,$14,$14,$1E,$04,$04,$00,$1F   ; 4  4, over a rule: f4
                fcb     $01,$0E,$13,$15,$19,$0E,$10,$00   ; 5  phi, for the phase-modulation destination
                fcb     $00,$00,$09,$09,$09,$0F,$11,$00   ; 6  mu, for the microvolt unit label
                fcb     $00,$10,$03,$14,$12,$11,$16,$00   ; 7  a swept-arrow glyph

; ---------------------------------------------------------------------------
; lcd_define_all - load every user-definable character
;
;   uses:  A, B, X, Y
;
; Called from the power-on path, after lcd_init and before anything paints.
; A screen drawn before these are loaded shows the controller's power-up
; CGRAM, which is undefined.
; ---------------------------------------------------------------------------
lcd_define_all
                clra                            ; A = which character
lcd_define_next
                pshs    a
                ldb     #LCD_CGRAM_ROWS
                mul                             ; D = character * 8
                ldx     #lcd_glyphs
                leax    d,x
                puls    a
                pshs    a
                lbsr    lcd_define
                puls    a
                inca
                cmpa    #LCD_CGRAM_CHARS
                blo     lcd_define_next
                rts


; ===========================================================================
; The display on/off control: display, cursor and blink
;
; ONE INSTRUCTION CARRIES ALL THREE - $08 plus 4 for the display, 2 for the
; cursor, 1 for the blink - and the HD44780 is write-only, so changing one
; means remembering the other two. This firmware wrote $0C once at boot and
; never touched it again, which is why an entry field had no visible cursor:
; there was no way to turn one on.
;
; The stock's lcd_display_control ($D7FE) is a six-arm dispatch over the same
; byte, shadowed at $242A: arm 0 cursor on, 1 cursor off, 2 blink on, 3 blink
; off, 4 display on, 5 display off. Each arm sets an AND mask and an OR mask
; and the shared tail at $D81D does `shadow AND mask OR mask` and writes it -
; which is how one bit changes without disturbing the others.
; ===========================================================================
LCD_DISPLAY_BIT equ     $04             ; the three the instruction carries,
LCD_CURSOR_BIT  equ     $02             ; in the order the data sheet gives
LCD_BLINK_BIT   equ     $01             ; them

; ---------------------------------------------------------------------------
; lcd_control_init - the shadow, and the display in a known state
;
;   uses:  A
;
; Display on, cursor off, blink off - which is what boot wrote as a literal.
; Writing the SHADOW as well is the point: without it the first change would
; have to guess what the other two bits were.
; ---------------------------------------------------------------------------
lcd_control_init
                lda     #LCD_ON_OFF|LCD_DISPLAY_BIT
                sta     >lcd_control
                lbra    lcd_command             ; tail call: its RTS is ours

; ---------------------------------------------------------------------------
; lcd_control_set - turn one of the three on
; lcd_control_clear - turn one of the three off
;
;   entry: A = LCD_DISPLAY_BIT, LCD_CURSOR_BIT or LCD_BLINK_BIT
;   uses:  A
;
; The shadow is updated before the write, so an interrupt that changed a
; different bit in between would still be building on the value the hardware
; actually holds.
; ---------------------------------------------------------------------------
; THE BASE BIT IS PART OF THE INSTRUCTION, NOT PART OF THE STATE, and it is
; ORed in on every write for that reason. Without it a shadow that had somehow
; reached zero turned "cursor on" into the byte $03 - and $03 is not a
; display-control instruction at all, it is HOME, which walks the cursor to
; position zero. A cosmetic call becoming a display-moving one is the worst
; shape this could take, so the instruction bit is not left to the shadow.
lcd_control_set
                ora     >lcd_control
                sta     >lcd_control
                ora     #LCD_ON_OFF
                lbra    lcd_command
lcd_control_clear
                coma                            ; the wanted bit becomes a
                anda    >lcd_control            ; zero in a mask of ones
                sta     >lcd_control
                ora     #LCD_ON_OFF
                lbra    lcd_command
