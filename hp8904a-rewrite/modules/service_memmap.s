; ===========================================================================
; service_memmap.s - the Memory Map Access screen
;
; Direct read and write of the memory-mapped I/O the instrument uses. In the
; stock firmware this walks seven fixed elements and is reached only through
; the access-code gate; here it is a diagnostics entry like any other.
;
; The seven the stock screen offers, with the names it prints for them:
;
;   $0200  DDS programming port
;   $0400  remote interface
;   $0900  status LEDs and annunciators
;   $0B00  HOPLATCH
;   $0C00  Output 1
;   $0D00  Output 2
;   $1000  MC6840 timer
;
; DELIBERATELY I/O ONLY. RAM is not reachable from this screen, and that is a
; design decision rather than an accident of the original: $2000-$3FFF holds
; the serial number and the installed options - and whatever else is
; per-unit, since no calibration constant has been found there and the
; whole region is treated as per-unit for that reason - and a
; raw memory editor pointed at it is one keystroke away from destroying them
; with no way back. HP's own service note works around a flat battery by
; writing $3FFD with a memory editor on EARLIER firmware; this rewrite gives
; the serial its own screen with its own validation instead.
; ===========================================================================

; --- the display, character for character out of the stock ----------------
;
; show_memory_map_access_screen ($5298) paints three pieces:
;   $52A6  d41a0 at position 0, forty characters - 'Diagnostics -' and 27
;          spaces, which BLANKS line 1 before the next write
;   $52B4  d42ee at position $0E, twenty-six characters - 'Memory Map
;          Access  ', the softkey pair, ' Exit' - covering columns 14 to 39
;   $52CB  d4308 at position $40, forty characters - the field frame
;
; One forty-character line 1 here where the stock writes two overlapping
; pieces; the characters that reach the display are the same.
;
; The three run-time fields drop into the frame's gaps: the element's name at
; $48 (line 2 column 8, eight wide), the effective address at $5A (column 26,
; four hex digits, with the frame's 'H' at 30) and the data byte at $65
; (column 37, two characters, 'H' at 39).
;
; THE MAPPED PAGE IS NOT SHOWN, and was, in line 1 column 39. It cannot
; matter here: the paged window is $4000-$7FFF and not one of the seven
; elements is in it - the highest is $1000. The corner it used is the 't' of
; 'Exit' in the stock's line 1.
memmap_title    fcc     "Diagnostics - Memory Map Access  "
                fcb     $00,$04                 ; the softkey font's 'f' and
                                                ; '4'; see lcd_glyphs
                fcc     " Exit"
memmap_prompt   fcc     "Element           Address     H Data   H"
memmap_writeonly fcc    "**"                    ; the stock's $550F, shown in
                                                ; place of a read-back byte

MEMMAP_NAME_POS equ     LCD_LINE2+8     ; the stock's $48
MEMMAP_ADDR_POS equ     LCD_LINE2+26    ; its $5A - four hex digits
MEMMAP_DATA_POS equ     LCD_LINE2+37    ; and its $65, where the typed digits
                                        ; land too: the entry cursor is the
                                        ; same address, so what is being
                                        ; keyed covers the read-back in place

; The elements, in the order the screen steps through them, read out of the
; seven arms of the JMP [D,X] table at page 3 $50A3. Each carries four things
; and only the first two were here:
;
;   the base address        $3FAB, set by every arm
;   an eight-character name $3FAF, pointing at $54CF and up
;   the highest sub-address $3FAA - how many bytes of the element the UP and
;                           DOWN keys can reach. The stock's arms set 1, 7, 0,
;                           0, 0, 0 and 7
;   write-only              $3FAE, preset to 1 at $4FFA and CLEARED by two
;                           arms only. Non-zero means the data column shows
;                           '**' rather than a read-back byte
;
; THE NAMES ARE THE STOCK'S. They were 'DDS Prog', 'Remote', 'Status' and
; 'Timer' - descriptions of what the hardware does, which is useful and is
; not what the service manual or the engineer's memory has. HP's own eight
; characters are at $54CF, $54D8, $54E1, $54EA, $54F3, $54FC and $5505.
MEMMAP_RO       equ     $00             ; the read-back is worth showing
MEMMAP_WO       equ     $01             ; it is not: the port is write-only
memmap_table
                fdb     $0200
                fcc     "NSMIC   "
                fcb     $01,MEMMAP_WO
                fdb     $0400
                fcc     "HP-IB IC"
                fcb     $07,MEMMAP_RO
                fdb     $0900
                fcc     "FP LEDs "
                fcb     $00,MEMMAP_WO
                fdb     $0B00
                fcc     "HOPLATCH"
                fcb     $00,MEMMAP_WO
                fdb     $0C00
                fcc     "Output 1"
                fcb     $00,MEMMAP_WO
                fdb     $0D00
                fcc     "Output 2"
                fcb     $00,MEMMAP_WO
                fdb     $1000
                fcc     "Timer IC"
                fcb     $07,MEMMAP_RO

MEMMAP_COUNT    equ     7
MEMMAP_ENTRY    equ     12              ; two address bytes, eight name bytes,
                                        ; the highest sub-address and the
                                        ; write-only flag
MEMMAP_NAME_LEN equ     8
MEMMAP_MAXSUB   equ     10              ; offsets into a record
MEMMAP_FLAGS    equ     11
MEMMAP_STROBE   equ     $0800           ; the second write Output 1 and
                                        ; Output 2 need; see memmap_write
MEMMAP_COMMIT_MS equ    300             ; the stock's delay_ms($012C) after a
                                        ; commit, at $51A3
MEMMAP_OUTPUT1  equ     4               ; the two elements whose write needs
MEMMAP_OUTPUT2  equ     5               ; the $0800 strobe as well

; ---------------------------------------------------------------------------
; memmap_entry_address - the record for the selected element
;
;   entry: B = which element, 0 to MEMMAP_COUNT-1
;   exit:  X = the record
;   uses:  A, B, X
; ---------------------------------------------------------------------------
memmap_entry_address
                cmpb    #MEMMAP_COUNT           ; BOUND IT. The caller's
                blo     memmap_entry_ok         ; index reaches an address
                clrb                            ; this routine hands to a
memmap_entry_ok                                 ; store, so an out-of-range
                ldx     #memmap_table           ; one is a write through
                                                ; whatever two bytes follow
                                                ; the table
                tstb
                beq     memmap_entry_done
memmap_entry_step
                pshs    b
                ldb     #MEMMAP_ENTRY
                abx
                puls    b
                decb
                bne     memmap_entry_step
memmap_entry_done
                rts

; ---------------------------------------------------------------------------
; memmap_effective - the address the screen is pointed at
;
;   entry: B = which element
;   exit:  X = the element's base plus the current sub-address
;   uses:  A, B, X
;
; The stock's $51F4-$51FB: LDX $3FAB / LDB $3FAD / ABX. An element is not one
; byte - the HP-IB interface and the timer are eight registers each - and the
; up and down keys walk within it.
; ---------------------------------------------------------------------------
memmap_effective
                lbsr    memmap_entry_address
                ldx     ,x                      ; the base
                ldb     >memmap_sub
                abx
                rts

; ---------------------------------------------------------------------------
; memmap_read - read the selected element
;
;   entry: B = which element
;   exit:  A = what the port returned
;   uses:  A, B, X
;
; THE READ IS UNCONDITIONAL, as the stock's is at $51FD. The write-only flag
; suppresses the DISPLAY of the answer, not the bus cycle - so a port whose
; read has a side effect still gets one, and this says so rather than leaving
; a reader to assume the flag means the read is skipped.
; ---------------------------------------------------------------------------
memmap_read
                lbsr    memmap_effective
                lda     ,x
                rts

; ---------------------------------------------------------------------------
; memmap_writeonly_p - does this element's read-back mean anything?
;
;   entry: B = which element
;   exit:  Z clear if the port is write-only
;   uses:  A, B, X
; ---------------------------------------------------------------------------
memmap_writeonly_p
                lbsr    memmap_entry_address
                lda     MEMMAP_FLAGS,x
                anda    #MEMMAP_WO
                rts

; ---------------------------------------------------------------------------
; memmap_maxsub - the highest sub-address within this element
;
;   entry: B = which element
;   exit:  A = 0 to 7
;   uses:  A, B, X
; ---------------------------------------------------------------------------
memmap_maxsub
                lbsr    memmap_entry_address
                lda     MEMMAP_MAXSUB,x
                rts

; ---------------------------------------------------------------------------
; memmap_write - write the selected element
;
;   entry: B = which element, A = the byte
;   uses:  A, B, X
;
; No confirmation and no range check: this screen exists to poke hardware,
; and an engineer who has reached it wants exactly that. The RAM that cannot
; be regenerated is not on the list at all, which is where the safety comes
; from - not from asking twice.
;
; AND THE OUTPUT LATCHES NEED A SECOND WRITE. The stock's $5189-$51A0 tests
; the element index for 4 or 5 - Output 1 at $0C00 and Output 2 at $0D00 -
; and writes the same byte to $0800 as well. Without it a byte poked into
; either output latch does not reach the board.
; ---------------------------------------------------------------------------
memmap_write
                pshs    a,b
                lbsr    memmap_effective
                lda     ,s
                sta     ,x
                puls    a,b
                cmpb    #MEMMAP_OUTPUT1
                beq     memmap_write_strobe
                cmpb    #MEMMAP_OUTPUT2
                bne     memmap_write_done
memmap_write_strobe
                sta     >MEMMAP_STROBE
memmap_write_done
                rts

; ---------------------------------------------------------------------------
; memmap_open - the Memory Map Access screen, from a menu
;
;   uses:  A, B, X, Y
;
; THE ENTRY POINT A MENU USES. memmap_show takes the element index in B and
; does not write memmap_index, so a menu entry pointing straight at it opened
; on whatever B happened to hold and left memmap_index holding whatever the
; last visit had put there - the first NEXT press then stepped from the stale
; index rather than from the element on screen.
;
; B at that point is not arbitrary, it is misleading: menu_key_run reaches the
; handler through nav_push, which ends in `ldb #NAV_ENTRY / mul`, so B is the
; low byte of depth * 5 - 0, 5, 10 or 15 - and the screen opened on element 0
; or element 5 depending only on how deep the menu stack was.
;
; That was found once and fixed in main_menu.s, in the caller, with a comment
; describing it; the diagnostics menu pointed at memmap_show directly and
; missed the fix. One entry point now, so there is nowhere to miss it.
; ---------------------------------------------------------------------------
memmap_open
                clrb                            ; always the first element
                stb     >memmap_index
                lbsr    memmap_show
                lbra    memmap_arm              ; the $0000 posted at open re-arms

; ---------------------------------------------------------------------------
; memmap_show - paint the whole screen for one element
;
;   entry: B = which element
;   uses:  A, B, X
; ---------------------------------------------------------------------------
memmap_show
                pshs    b
                ldx     #memmap_key
                lbsr    screen_install

                lda     #LCD_LINE1              ; the two fixed lines
                ldx     #memmap_title
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write
                lda     #LCD_LINE2
                ldx     #memmap_prompt
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write

                ldb     ,s                      ; the element's name
                lbsr    memmap_entry_address
                leax    2,x
                lda     #MEMMAP_NAME_POS
                ldb     #MEMMAP_NAME_LEN
                lbsr    lcd_write

                ldb     ,s                      ; THE ELEMENT AGAIN. B held
                lbsr    memmap_fields           ; the name's LENGTH here, left
                                                ; by lcd_write - so every
                                                ; element painted element 0's
                                                ; address and its write-only
                                                ; flag under its own name
                puls    b
                rts

; ---------------------------------------------------------------------------
; memmap_fields - the address and the data column, without the frame
;
;   entry: B = which element
;   uses:  A, B, X
;
; Split out because every key redraws these two and only selecting an element
; redraws the name - which is the shape of the stock's screen: its handler
; ($50CE) writes the address and the data column and NOTHING else, and the
; name comes from memmap_select_element's tail at $50B1.
; ---------------------------------------------------------------------------
memmap_fields
                pshs    b
                lbsr    memmap_effective        ; the address, four hex digits
                tfr     x,d
                pshs    b
                ldx     #text_buffer
                tfr     a,b
                lbsr    byte_to_hex
                puls    b
                ldx     #text_buffer+2
                lbsr    byte_to_hex
                lda     #MEMMAP_ADDR_POS
                ldx     #text_buffer
                ldb     #$04
                lbsr    lcd_write

                ; AND THE DATA COLUMN. While digits are being typed it shows
                ; them - the stock's entry cursor is set to $65, the same
                ; address, so what is being keyed covers the read-back where
                ; it stands. With nothing typed it shows the port's own byte,
                ; or '**' where reading the port tells you nothing.
                ; entry_COUNT, not entry_active. entry_digit does not set
                ; entry_active - nothing on this screen does, and
                ; screen_install clears it - so the echo below never ran and
                ; the field showed the port's byte while digits were being
                ; typed into it. The count is the thing that says a byte is
                ; half entered.
                tst     >entry_count
                bne     memmap_fields_typed

                ldb     ,s
                lbsr    memmap_writeonly_p      ; Z clear: write-only
                bne     memmap_fields_starred
                ldb     ,s
                lbsr    memmap_read             ; A = the byte
                pshs    a
                ldx     #text_buffer
                puls    b
                lbsr    byte_to_hex
                ldx     #text_buffer
                bra     memmap_fields_put
memmap_fields_starred
                ldb     ,s
                lbsr    memmap_read             ; THE BUS CYCLE HAPPENS EITHER
                                                ; WAY, as the stock's does at
                                                ; $51FD - the flag suppresses
                                                ; the display, not the read
                ldx     #memmap_writeonly
                bra     memmap_fields_put
memmap_fields_typed
                ldx     #text_buffer            ; THE ECHO, to the glass only,
                lbsr    entry_render            ; as lcd_write_string_at ($D8A5)
                ldx     #text_buffer            ; writes the stock's: the stored
                lda     #MEMMAP_DATA_POS        ; byte stays in the shadow for
                ldb     #MEMMAP_HEX_DIGITS      ; entry_key_exit's repaint
                lbsr    lcd_write_raw           ; (docs/entry-exit-port.md)
                puls    b
                rts
memmap_fields_put
                lda     #MEMMAP_DATA_POS
                ldb     #MEMMAP_HEX_DIGITS
                lbsr    lcd_write
                puls    b
                rts

; ---------------------------------------------------------------------------
; memmap_key - the Memory Map Access screen's keys
;
;   entry: B = the key code
;   uses:  A, B, X, Y
;
; The stock's five, from the compare chain at $51C1:
;
;   NEXT ($0017) and LAST ($0018) step the element, CLAMPED at 6 and 0 - they
;     do not wrap, and they reselect even at the ends, which re-clears the
;     sub-address;
;   UP ($0020) and DOWN ($001F) step the sub-address within the element,
;     clamped at the element's own maximum and at 0;
;   f4 ($0016) leaves.
;
; Everything else beeps - the stock's default arm calls ptm_t1_output_pulse
; ($D6C8), which is what key_refuse does here.
;
; THE ELEMENTS ARE A LIST, NOT A TYPED ADDRESS. That is the safety, and it is
; the whole reason this screen can be on the menu without a code in front of
; it: the seven entries are hardware ports, and the RAM that cannot be
; regenerated is not among them. An operator on this screen cannot reach the
; serial number by mistyping, because there is no address to mistype.
;
; TWO HEX DIGITS COMMIT, AND THERE IS NO ENTER. The stock's field is units
; class 1, which check_entry_terminator ($B070) ends only when the field is
; FULL - so the second digit writes the byte and re-arms. ENTER cannot commit
; it: on a hex field ENTER is the letter D. This screen required ENTER, which
; no operator of the original would press and which types a digit instead.
;
; AND THE CURSOR IS RE-ARMED AFTER EVERY MESSAGE BUT f4. memmap_access_handler
; ($50CE) ends in p5265, whose LBSR $ac35 at $5290 re-arms the field for every
; request code it is sent except $16, so NEXT, LAST, the arrows, the commit and a
; refused key all leave the cursor on the data field at $65. A digit is not a
; message - numeric_entry_key_handler ($B3C2) keeps it - and only moves the
; display's address after the typed characters ($B567). memmap_key is that
; tail; memmap_key_body is the handler.
; ---------------------------------------------------------------------------
memmap_key
                pshs    b
                lbsr    memmap_key_body
                puls    b
                ldx     >screen_handler         ; a key that left the screen
                cmpx    #memmap_key             ; arms nothing: f4 is the stock's
                bne     memmap_key_done         ; $16, the one message not re-armed
                lda     #MEMMAP_DATA_POS        ; $23AD, $65
                adda    >entry_count            ; + $23A4
                lbsr    entry_key_is_mapped     ; a message re-arms ($5290); a key
                lbne    entry_cursor_on         ; $B3C2 kept only moves the address
                lbra    lcd_cursor              ; ($B567)
memmap_key_done
                rts

; ---------------------------------------------------------------------------
; memmap_arm - the data field armed: the cursor on its next cell
;
;   uses:  A
;
; $65, the column p5265 hands arm_numeric_entry_field at $5290, plus the
; digits typed.
; ---------------------------------------------------------------------------
memmap_arm
                lda     #MEMMAP_DATA_POS
                adda    >entry_count
                lbra    entry_cursor_on         ; $AC98, $ACA6

; ---------------------------------------------------------------------------
; memmap_key_body - the Memory Map keys, without the re-arm
;
;   entry: B = the key code
;   uses:  A, B, X, Y
; ---------------------------------------------------------------------------
memmap_key_body
                cmpb    #KEY_F4
                lbeq    service_back_handler
                                                ; f4 ALONE: the stock's own
                                                ; service screens leave on
                                                ; $0016, which posts request 3
                                                ; ($5A05), and LOCAL reaches no
                                                ; arm of theirs
                cmpb    #KEY_NEXT
                bne     memmap_key_last
                ldb     >memmap_index
                cmpb    #MEMMAP_COUNT-1         ; CLAMPED, not wrapped: the
                bhs     memmap_key_select       ; stock's $511C
                incb
                bra     memmap_key_select
memmap_key_last
                cmpb    #KEY_LAST
                bne     memmap_key_up
                ldb     >memmap_index
                beq     memmap_key_select       ; already at 0: the stock's
                decb                            ; $513A
memmap_key_select
                stb     >memmap_index
                clr     >memmap_sub             ; selecting an element clears
                                                ; the sub-address, which is
                                                ; memmap_select_element's own
                                                ; first act at $50B1
                lbsr    entry_begin_hex         ; a fresh byte for the new
                ldb     >memmap_index           ; element - and the index BACK
                lbra    memmap_show             ; into B, which entry_begin_hex
                                                ; leaves holding its own digit
                                                ; count. memmap_show takes the
                                                ; element in B, so NEXT and
                                                ; LAST repainted element 0
                                                ; whatever they had just
                                                ; selected.

memmap_key_up
                cmpb    #KEY_UP
                bne     memmap_key_down
                ldb     >memmap_index
                lbsr    memmap_maxsub           ; A = the element's highest
                cmpa    >memmap_sub
                beq     memmap_key_redraw       ; at the top: no change
                inc     >memmap_sub
                bra     memmap_key_redraw
memmap_key_down
                cmpb    #KEY_DOWN
                bne     memmap_key_backspace
                tst     >memmap_sub
                beq     memmap_key_redraw       ; at zero: no change
                dec     >memmap_sub
memmap_key_redraw
                lbsr    entry_begin_hex         ; a fresh byte for the new
                ldb     >memmap_index           ; sub-address
                lbra    memmap_show

memmap_key_backspace
                cmpb    #KEY_BACKSPACE
                bne     memmap_key_digit
                ; THE LAST DIGIT OUT AGAIN. The stock has this too, one level
                ; up: entry_backspace ($B2CD) consumes the key inside the
                ; entry state machine, so it never reaches its handler.
                lbsr    entry_backspace
                ldb     >memmap_index
                lbra    memmap_fields
memmap_key_digit
                lbsr    key_hex_digit           ; 0-9 AND A-F. key_digit maps
                                                ; only 0 to 9, so on the one
                                                ; screen whose subject is bit
                                                ; patterns half of every
                                                ; register's value could not
                                                ; be typed. The six letters
                                                ; are the stock's borrowed
                                                ; keys - kHz, Hz, deg, ENTER,
                                                ; minus, point.
                bcs     memmap_key_ignore
                lbsr    entry_digit
                lda     >entry_count            ; FULL COMMITS. Two digits and
                cmpa    #MEMMAP_HEX_DIGITS      ; the byte is written; there
                blo     memmap_key_echo         ; is no ENTER on this field
                lbsr    entry_cursor_off        ; $B586: class 1, width reached
                lbsr    entry_value
                bcs     memmap_key_echo
                lda     >entry_result+2         ; a byte, from the low eight
                ldb     >memmap_index           ; bits of what was typed
                lbsr    memmap_write
                lbsr    entry_begin_hex
                ldd     #MEMMAP_COMMIT_MS       ; the stock waits after a
                lbsr    delay_ms                ; commit, at $51A3, so the
                                                ; operator sees it land
                ldb     >memmap_index
                lbsr    memmap_fields
                lbra    memmap_arm              ; and request $23's re-arm
memmap_key_echo
                ldb     >memmap_index
                lbra    memmap_fields
memmap_key_ignore
                lbra    key_refuse          ; a key this screen cannot
                                                        ; use is REFUSED, not
                                                        ; ignored; see key_refuse

; ---------------------------------------------------------------------------
; entry_begin_hex - start a two-digit hexadecimal byte
;
;   uses:  A, B, X
;
; The one place the memory-map screen's field geometry is stated, so the
; three routines that restart the field cannot disagree about its width.
; ---------------------------------------------------------------------------
MEMMAP_HEX_DIGITS equ   2               ; a byte, in hex

entry_begin_hex
                lda     #ENTRY_HEX
                ldb     #MEMMAP_HEX_DIGITS
                lbra    entry_begin

; ---------------------------------------------------------------------------
; entry_begin_decimal - start a decimal field of the widest useful size
;
;   uses:  A, B, X
;
; The twin of entry_begin_hex, for the paged screens that take a number
; rather than a bit pattern. Eight digits, which is what the converter
; produces and what the widest field on any screen holds.
; ---------------------------------------------------------------------------
entry_begin_decimal
                lda     #ENTRY_DECIMAL
                ldb     #TEXT_DIGITS
                lbra    entry_begin


; ===========================================================================
; The Manual Memory Read/Write screen.
;
; manual_memory_screen_init ($61BB) and manual_memory_screen_handler ($5F96),
; A2U13 page 3. It was absent from this firmware entirely - docs/coverage-
; truth.md named it as one of the two of the stock's nine diagnostics with no
; counterpart anywhere - and the file above states why: a raw memory editor
; pointed at $2000-$3FFF is one keystroke away from destroying the serial
; number and the installed options.
;
; That is a reason to GUARD it, not a reason to drop it. Nothing in the ROMs
; is there by accident, and an engineer with a fault in the instrument's RAM
; wants to read and write it. So this is the stock's screen with one refusal
; added, and the refusal is the owner's own standing rule: $3FEE-$3FFF holds
; the serial number, the installed options and the revision signature, and
; HP's recovery refuses a serial that is not factory-virgin. Those four bytes
; are read here and written only by the Serial Number screen, which validates
; what it is given.
;
; WHAT THE STOCK DOES, read out of the instruction stream at $5F96-$616B:
;   $13/$14         select field 0 (address) or 1 (data)
;   $20/$1F         step the address up and down
;   $16             leave
;   $23 field 0     four hex digits through hex4_ascii_to_uint16 ($CCB5)
;                   into $3FC8
;   $23 field 1     two hex digits through parse_hex_digit_pair ($CC53).
;                   An address of EXACTLY $4000 sets $3FCB, the A2U13 page
;                   number, rather than writing memory; the byte reaches
;                   [$3FC8] only when the address is BELOW $4000, so the
;                   window and A2U12 are read-only.
;   the repaint     reads through read_byte_from_page ($C1E3) with page $3FCB
;                   when the address is in $4000-$7FFF and directly otherwise,
;                   and shows the address as four hex at $49 and the data as
;                   two at $58.
;
; The four-digit address field is armed by the init at LCD $49, which is
; line 2 column 9, and the data field at $58, column 24.
; ===========================================================================

MEMW_ADDR_W     equ     4               ; four hex digits of address
MEMW_DATA_W     equ     2               ; two of data
MEMW_ADDR_POS   equ     LCD_LINE2+9     ; the stock's $49
MEMW_DATA_POS   equ     LCD_LINE2+24    ; and its $58
MEMW_CHAR_POS   equ     LCD_LINE2+29    ; the byte as a character, between the
                                        ; two quotes the template carries
MEMW_FIELD_ADDR equ     0
MEMW_FIELD_DATA equ     1

memw_title      fcc     "Diagnostics - Manual Memory Read/Write  "
memw_prompt     fcb     $00,$01
                fcc     " Addr=       "
                fcb     $00,$02
                fcc     " Data=     "
                fcb     $22
                fcc     " "
                fcb     $22
                fcc     "  "
                fcb     $00,$04
                fcc     " Exit"
memw_unreadable fcc     "--"            ; the page would not map

; ---------------------------------------------------------------------------
; memw_open - the Manual Memory Read/Write screen
;
;   uses:  A, B, X, Y
; ---------------------------------------------------------------------------
memw_open
                ldx     #$0000
                stx     >memw_addr
                clr     >memw_field
                lbsr    page_current            ; the page A2U12 last
                cmpb    #PAGE_COUNT             ; selected, which is what the
                blo     memw_open_page          ; stock seeds $3FCB from
                clrb                            ; ($247B); an unknown page
memw_open_page                                  ; starts at 0 rather than
                stb     >memw_page              ; leaving the window unnamed
                lbsr    memw_field_begin
                lbsr    memw_show
                lbra    memw_arm                ; $622B: armed as it opens

; ---------------------------------------------------------------------------
; memw_field_begin - arm the entry field the selector names
;
;   uses:  A, B, X
; ---------------------------------------------------------------------------
memw_field_begin
                lda     >memw_field
                bne     memw_field_data
                lda     #ENTRY_HEX
                ldb     #MEMW_ADDR_W
                lbra    entry_begin
memw_field_data
                lda     #ENTRY_HEX
                ldb     #MEMW_DATA_W
                lbra    entry_begin

; ---------------------------------------------------------------------------
; memw_read - the byte the address names
;
;   exit:  A = the byte, carry CLEAR; carry SET if the page would not map
;   uses:  A, B, X
;
; Through the window on the page the screen names when the address is in
; $4000-$7FFF, directly otherwise - which is read_byte_from_page ($C1E3) in
; the stock. The page is left mapped: page_call selects and verifies before
; every paged call in this firmware, so nothing reads the window without
; having asked for it.
; ---------------------------------------------------------------------------
memw_read
                ldx     >memw_addr
                cmpx    #PAGE_WINDOW
                blo     memw_read_direct
                cmpx    #PAGE_WINDOW_END
                bhi     memw_read_direct
                ldb     >memw_page
                pshs    x
                lbsr    page_select_and_verify
                puls    x
                bcs     memw_read_failed
memw_read_direct
                lda     ,x
                andcc   #~CC_CARRY
                rts
memw_read_failed
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; memw_write - put a byte where the address names, if it may go there
;
;   entry: A = the byte
;   uses:  A, B, X
;
; Three answers, and the first two are the stock's:
;
;   the address is EXACTLY $4000  set the page number instead. That is what
;                                 the stock does, and it is how the window is
;                                 pointed at a page before it is read.
;   the address is $4001 or above the window and A2U12 are ROM: refused.
;   $3FEE-$3FFF                   the per-unit bytes: refused, and this one
;                                 is not the stock's. See the header.
;   $2000-$203B                   the trust signature: refused, and this one
;                                 is not the stock's either.
;   REGISTER_BASE-REGISTER_TOP    the twelve saved setups: the same.
;
; THE TWO SPANS BELOW $3FEE were open until 2026-09-12, and this screen is the
; only place in the firmware where an operator names an arbitrary RAM address
; and a byte to put in it. $3FEE upwards was guarded because the serial lives
; there; the two spans the owner's rules name in the same breath as the serial were
; not. One byte at $2000-$203B and selftest_signature fails at the next
; power-on, which is the instrument declaring its own serial and options
; untrustworthy; one byte inside the register array is a saved setup returning
; as a wrong marker or a wrong span length. Both are silent - the screen would
; have said the write went in, and the damage shows up a power cycle later.
; ---------------------------------------------------------------------------
;   exit:  carry SET if the write was refused, and the Error screen is up.
;          The caller must NOT repaint over it - that is what happened first,
;          and the refusal was painted and covered again in the same keystroke.
memw_write
                ldx     >memw_addr
                cmpx    #PAGE_WINDOW
                bne     memw_write_below
                anda    #PAGE_COUNT-1           ; the page number, bounded the
                sta     >memw_page              ; way page_select_and_verify
                andcc   #~CC_CARRY              ; bounds it
                rts
memw_write_below
                bhi     memw_write_refuse
                cmpx    #legacy_opts_20987a     ; $3FEE, the first per-unit
                bhs     memw_write_refuse       ; byte
                cmpx    #ram_signature          ; $2000
                blo     memw_write_registers    ; below the signature entirely
                cmpx    #STACK_BOTTOM           ; $203C, the first byte above
                blo     memw_write_refuse       ; the trust signature. This
                                                ; named register_seq_block,
                                                ; which happened to be declared
                                                ; at that address and is not a
                                                ; RAM cell at all any more:
                                                ; $203C-$21FF is stack, and
                                                ; boot.s names its lowest byte.
memw_write_registers
                cmpx    #REGISTER_BASE          ; $242B, which is where
                                                ; twelve 476-byte slots
                                                ; ending at REGISTER_TOP
                                                ; begin. The comment said
                                                ; $268F, which is the STOCK's
                                                ; base and was this
                                                ; firmware's until the slot
                                                ; grew; the symbol was right
                                                ; the whole time, so nothing
                                                ; was ever refused at the
                                                ; wrong address - the number
                                                ; beside it was just a lie to
                                                ; anyone reading
                blo     memw_write_do
                cmpx    #REGISTER_TOP           ; $3A7A, and the compare is
                bls     memw_write_refuse       ; INCLUSIVE - that byte is the
                bra     memw_write_do           ; last of register 11
memw_write_refuse
                ldb     #ERR_PROTECTED          ; the per-unit bytes, or ROM,
                lbsr    error_raise             ; or the paged window. The
                orcc    #CC_CARRY               ; stock simply drops a write
                rts                             ; above $4000 and says
                                                ; nothing, which leaves an
                                                ; operator believing a byte
                                                ; went in
memw_write_do
                sta     ,x
                andcc   #~CC_CARRY
                rts

; ---------------------------------------------------------------------------
; memw_show - paint the whole screen
;
;   uses:  A, B, X
; ---------------------------------------------------------------------------
memw_show
                ldx     #memw_key               ; the keys are taken HERE, as
                lbsr    screen_install          ; memmap_show above takes
                                                ; them: this is the routine
                                                ; that puts the screen up, and
                                                ; a screen that paints without
                                                ; installing leaves the last
                                                ; one's handler live over it
                lda     #LCD_LINE1
                ldx     #memw_title
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write
                lda     #LCD_LINE2
                ldx     #memw_prompt
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write
                lbra    memw_fields

; ---------------------------------------------------------------------------
; memw_fields - the address, the byte and the byte as a character
;
;   uses:  A, B, X
; ---------------------------------------------------------------------------
memw_fields
                lda     >memw_field             ; the address: what is being
                bne     memw_fields_addr_shown  ; typed while that field is
                tst     >entry_count            ; armed, the stored value
                beq     memw_fields_addr_shown  ; otherwise
                ldx     #text_buffer
                lbsr    entry_render
                lda     #MEMW_ADDR_POS
                ldx     #text_buffer
                ldb     #MEMW_ADDR_W
                lbsr    lcd_write_raw           ; the echo: glass only, as
                                                ; lcd_write_string_at ($D8A5)
                bra     memw_fields_data
memw_fields_addr_shown
                ldd     >memw_addr
                pshs    b
                ldx     #text_buffer
                tfr     a,b
                lbsr    byte_to_hex
                puls    b
                ldx     #text_buffer+2
                lbsr    byte_to_hex
                lda     #MEMW_ADDR_POS
                ldx     #text_buffer
                ldb     #MEMW_ADDR_W
                lbsr    lcd_write

memw_fields_data
                lda     >memw_field             ; and the byte, the same way
                beq     memw_fields_byte
                tst     >entry_count
                beq     memw_fields_byte
                ldx     #text_buffer
                lbsr    entry_render
                lda     #MEMW_DATA_POS
                ldx     #text_buffer
                ldb     #MEMW_DATA_W
                lbra    lcd_write_raw           ; the echo: glass only
memw_fields_byte
                lbsr    memw_read
                bcs     memw_fields_unreadable
                pshs    a
                ldx     #text_buffer
                puls    b
                pshs    b
                lbsr    byte_to_hex
                lda     #MEMW_DATA_POS
                ldx     #text_buffer
                ldb     #MEMW_DATA_W
                lbsr    lcd_write

                ; AND THE BYTE AS A CHARACTER, between the two quotes the
                ; template carries at columns 28 and 30. A byte outside the
                ; font's printable range is shown as a full cell rather than
                ; as whatever the controller has there, which is the same
                ; choice the Display Check makes above $7F.
                puls    a
                cmpa    #' '
                blo     memw_fields_solid
                cmpa    #$7F
                blo     memw_fields_char
memw_fields_solid
                lda     #$FF
memw_fields_char
                sta     >text_buffer
                lda     #MEMW_CHAR_POS
                ldx     #text_buffer
                ldb     #$01
                lbra    lcd_write
memw_fields_unreadable
                lda     #MEMW_DATA_POS
                ldx     #memw_unreadable
                ldb     #MEMW_DATA_W
                lbra    lcd_write

; ---------------------------------------------------------------------------
; memw_key - the Manual Memory screen's keys
;
;   entry: B = the key code
;   uses:  A, B, X, Y
;
; f1 and f2 select the two fields, which are the stock's requests $13 and
; $14; UP and DOWN step the address, its $20 and $1F; f4 leaves, its $16. A
; field commits when it is FULL, as every hex field in this firmware does -
; four digits for the address, two for the byte.
;
; AND THE CURSOR IS RE-ARMED AFTER EVERY MESSAGE BUT f4, on the field $3FB4
; names: manual_memory_screen_handler's tail arms $49 at $617C for the address
; and $58 at $61A0 for the byte, for every request code except $16. A digit
; only moves the display's address after the typed characters ($B567).
; memw_key is that tail and memw_key_body the handler.
; ---------------------------------------------------------------------------
memw_key
                pshs    b
                lbsr    memw_key_body
                puls    b
                ldx     >screen_handler         ; a key that left the screen
                cmpx    #memw_key               ; arms nothing
                bne     memw_key_done
                lbsr    memw_cell               ; A = $23AD + $23A4
                lbsr    entry_key_is_mapped     ; a message re-arms ($617C,
                lbne    entry_cursor_on         ; $61A0); a key $B3C2 kept only
                lbra    lcd_cursor              ; moves the address ($B567)
memw_key_done
                rts

; ---------------------------------------------------------------------------
; memw_arm  - the selected field armed: the cursor on its next cell
; memw_cell - that cell: A = the field's first column plus the digits typed
;
;   uses:  A
;
; $49 for the address ($617C) and $58 for the byte ($61A0), by memw_field.
; ---------------------------------------------------------------------------
memw_arm
                lbsr    memw_cell
                lbra    entry_cursor_on         ; $AC98, $ACA6
memw_cell
                lda     #MEMW_ADDR_POS          ; $617C: $49 for the address
                tst     >memw_field
                beq     memw_cell_count
                lda     #MEMW_DATA_POS          ; $61A0: $58 for the byte
memw_cell_count
                adda    >entry_count
                rts

; ---------------------------------------------------------------------------
; memw_key_body - the Manual Memory keys, without the re-arm
;
;   entry: B = the key code
;   uses:  A, B, X, Y
; ---------------------------------------------------------------------------
memw_key_body
                cmpb    #KEY_F4
                lbeq    service_back_handler
                cmpb    #KEY_F1
                bne     memw_key_f2
                clr     >memw_field
                bra     memw_key_refield
memw_key_f2
                cmpb    #KEY_F2
                bne     memw_key_up
                lda     #MEMW_FIELD_DATA
                sta     >memw_field
memw_key_refield
                lbsr    memw_field_begin
                lbra    memw_show
memw_key_up
                cmpb    #KEY_UP
                bne     memw_key_down
                ldx     >memw_addr
                leax    1,x
                stx     >memw_addr
                bra     memw_key_stepped
memw_key_down
                cmpb    #KEY_DOWN
                bne     memw_key_backspace
                ldx     >memw_addr
                leax    -1,x
                stx     >memw_addr
memw_key_stepped
                lbsr    memw_field_begin        ; a new address is a new byte
                lbra    memw_fields
memw_key_backspace
                cmpb    #KEY_BACKSPACE
                bne     memw_key_digit
                lbsr    entry_backspace
                lbra    memw_fields
memw_key_digit
                lbsr    key_hex_digit           ; 0-9 and A-F, the six letters
                bcs     memw_key_ignore         ; the stock borrows for a hex
                lbsr    entry_digit             ; field
                lda     >entry_count
                cmpa    >entry_width            ; FULL COMMITS, as on the
                blo     memw_key_echo           ; Memory Map screen
                lbsr    entry_cursor_off        ; $B586: class 1, width reached
                lbsr    entry_value
                bcs     memw_key_echo
                lda     >memw_field
                bne     memw_key_commit_data
                ldd     >entry_result+1         ; the low sixteen bits are the
                std     >memw_addr              ; address
                bra     memw_key_committed
memw_key_commit_data
                lda     >entry_result+2         ; and the low eight the byte
                lbsr    memw_write
                bcs     memw_key_refused        ; the Error screen is up: do
                                                ; not paint over it
memw_key_committed
                lbsr    memw_field_begin
                lbsr    memw_show
                lbra    memw_arm                ; and request $23's re-arm
memw_key_echo
                lbra    memw_fields
memw_key_refused
                rts
memw_key_ignore
                lbra    key_refuse
