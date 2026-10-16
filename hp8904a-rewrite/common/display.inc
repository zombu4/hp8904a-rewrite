; ===========================================================================
; display.inc - what the display IS, separate from how it is driven
;
; The paged ROM writes to the screen constantly, but the driver lives in
; A2U12 and is called through the jump table. What a page still needs is the
; geometry and the command set - facts about the part, not code.
;
; This is the same separation abi.inc makes for routines: an interface both
; images can include, and an implementation only one of them carries.
; ===========================================================================

; --- Controller commands, from the HD44780 data sheet ----------------------
LCD_CLEAR       equ     $01             ; clear and home; ~1.5 ms
LCD_HOME        equ     $02             ; cursor home, DDRAM unchanged
LCD_ENTRY_MODE  equ     $04             ; entry mode set
LCD_ENTRY_ADVANCE equ   $02             ; the bit boot.s passes with it to get
                                        ; "advance on write, do not shift".
                                        ;
                                        ; WHICH BIT IS WHICH IS NOT ESTABLISHED,
                                        ; and here is what was searched: the
                                        ; eight sheets in firmware/datasheets/
                                        ; were listed and none is an HD44780
                                        ; (AD565A, AM27C256, DS75160A, HM6264,
                                        ; Intel 27513, P8291A, MC6809, MC6840),
                                        ; and the stock's lcd_init - read at
                                        ; src-generated/a2u12.s:17870 - writes
                                        ; $38, $0C, $01 and $28 and no
                                        ; entry-mode command at all.
                                        ; This line used to annotate the
                                        ; command "+1 increment, +2 shift
                                        ; display", which makes $02 the SHIFT
                                        ; and contradicts the caller's own
                                        ; comment. There is no HD44780 data
                                        ; sheet in firmware/datasheets/ - the
                                        ; eight there are AD565A, AM27C256,
                                        ; DS75160A, HM6264, Intel 27513,
                                        ; P8291A, MC6809 and MC6840 - and the
                                        ; stock firmware never issues this
                                        ; command, so nothing in this
                                        ; repository settles it. The usual
                                        ; HD44780 assignment puts I/D at DB1
                                        ; and S at DB0, which would make $02
                                        ; increment-without-shift and the
                                        ; caller right; that is the reading
                                        ; this name records, and it is a
                                        ; reading, not a citation.
LCD_ON_OFF      equ     $08             ; +4 display, +2 cursor, +1 blink
LCD_SHIFT       equ     $10             ; cursor/display shift
LCD_FUNCTION    equ     $20             ; +$10 8-bit, +8 two-line, +4 5x10
LCD_SET_CGRAM   equ     $40             ; OR the character-generator address
LCD_SET_DDRAM   equ     $80             ; OR the display address
LCD_BUSY        equ     $80             ; bit 7 of a read from lcd_instr

; --- Geometry --------------------------------------------------------------
LCD_COLUMNS     equ     40              ; characters per line.
                                        ; ESTABLISHED, not assumed: the stock
                                        ; lcd_repaint_both_lines ($D989) writes
                                        ; $28 = 40 characters at DDRAM $00 and
                                        ; 40 more at $40, and lcd_write_clipped
                                        ; ($D8EA) folds $40 to linear 40 so the
                                        ; two lines form one 0-79 span. 26 of
                                        ; the stock display strings are exactly
                                        ; 40 characters and two are exactly 80.
                                        ; This read 20 until that was checked,
                                        ; which would have put every screen's
                                        ; second half on the floor.
LCD_LINE1       equ     $00             ; DDRAM address of the first line
LCD_LINE2       equ     $40             ; ...and of the second; NOT $14
LCD_CGRAM_CHARS equ     8               ; user-definable characters
LCD_SHADOW_LEN  equ     80              ; the two lines as one run of cells.
                                        ; lcd_shadow holds them: line 1 at 0
                                        ; and line 2 at 40, which is the stock's
                                        ; own fold - lcd_write_clipped ($D8EA)
                                        ; subtracts $18 from any address past
                                        ; $27, so DDRAM $40 becomes cell 40
LCD_CGRAM_ROWS  equ     8               ; pixel rows in each
