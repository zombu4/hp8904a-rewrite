; ===========================================================================
; service_info.s - the firmware information screen
;
; What the instrument is, on one screen: which firmware it is running, what
; it thinks its serial number is, which options are set, and how many output
; boards it found. Everything an engineer asks first, without stepping
; through four menus to assemble it.
;
; The stock firmware shows some of this on its power-on banner and the rest
; nowhere.
; ===========================================================================

info_title      fcc     "Firmware Information                    "
info_rev        fcc     "Rev:                                    "
info_serial     fcc     "S/N:                                    "
info_opts       fcc     "Opts:                                   "
info_chans      fcc     "Channels:                               "

; The revision this rewrite is. Stored as text rather than computed, and
; deliberately NOT the stock "27887A": this is different firmware and saying
; otherwise on a screen an engineer reads to identify a machine would be a
; lie with real consequences.
info_revision   fcc     "RW-0001 "
INFO_REV_LEN    equ     8

; ---------------------------------------------------------------------------
; id_banner_build - the two-line identification block, built at rmt_out
;
;   exit:  rmt_out holds ID_LINES characters, line 1 then line 2
;   uses:  A, B, X, Y
;
; build_id_banner ($8000), step for step and at the stock's own address:
; $2285 is where it builds the block, and hp8904a-rewrite/common/ram.inc puts
; rmt_out there.
;
;   line 1   forty bytes of 'HP 8904A Opts 02/01/03/  /  /  /  /  /  ' out of
;            page 0 at $4027. The '02/' at +$0E-+$10 ($2293-$2295) is blanked
;            when the channel count $23B2 is not above one; then the eight
;            bits of $3FFC are walked low bit first ($808F-$80CD) and every
;            ABSENT option's three-character field at +$10+3i gets three
;            spaces from $ED11. So bit 0 owns '/01', bit 1 '/03', and bits 2
;            to 7 own the empty fields after them - which is why the six
;            '/  ' in the template never show.
;   line 2   thirty-five bytes of 'Firmware Revision 27887A Serial No ' from
;            $EA99, then the serial's last five digits - uint24_to_ascii8
;            ($CA8F) renders eight at $22CD and $8066 moves the last five
;            into the last five columns.
;
; THE REVISION FIELD IS SIX CHARACTERS, and this firmware's name, RW-0001, is
; seven. The stock's layout is kept and the name is written RW0001 in it, so
; the serial keeps all five of its columns. The architect ruled it on
; 2026-09-17: this firmware carries a revision of its
; own and never HP's 27887A, because a controller has a right to know what it
; is talking to. RW0001 was kept over a name in 27887A's digits-and-suffix
; shape: it fills the same six columns, and it cannot be read as an HP part
; number.
;
; The field ORDER is the stock's, 02 01 03: driven on the stock 2026-09-11,
; options $03 on a four-channel instrument reads 'Opts 02/01/03'.
; ---------------------------------------------------------------------------
ID_LINE         equ     40                      ; one display line
ID_LINES        equ     80                      ; the whole block
ID_CHAN_FIELD   equ     $0E                     ; '02/', at $2293
ID_OPT_FIELD    equ     $10                     ; bit 0's field, at $2295
ID_SERIAL_AT    equ     ID_LINE+35              ; the last five columns
ID_SERIAL_W     equ     5

id_banner_text  fcc     "HP 8904A Opts 02/01/03/  /  /  /  /  /  "
                fcc     "Firmware Revision RW0001 Serial No "

id_banner_build
                ldx     #id_banner_text         ; both templates, seventy-five
                ldy     #rmt_out                ; bytes in one run
                ldb     #ID_SERIAL_AT
id_banner_copy
                lda     ,x+
                sta     ,y+
                decb
                bne     id_banner_copy

                lbsr    serial_read             ; A = bits 23-16, X = 15-0
                sta     >text_buffer+8          ; widened past the eight
                stx     >text_buffer+9          ; digits uint24_to_text writes
                ldx     #text_buffer+8
                lbsr    uint24_to_text
                ldx     #text_buffer+TEXT_DIGITS-ID_SERIAL_W
                ldy     #rmt_out+ID_SERIAL_AT
                ldb     #ID_SERIAL_W
id_banner_serial
                lda     ,x+
                sta     ,y+
                decb
                bne     id_banner_serial

                lda     >installed_channels     ; $807A: $23B2 above one, or
                cmpa    #$01                    ; '02/' goes
                bhi     id_banner_walk
                lda     #' '
                sta     >rmt_out+ID_CHAN_FIELD
                sta     >rmt_out+ID_CHAN_FIELD+1
                sta     >rmt_out+ID_CHAN_FIELD+2
id_banner_walk
                lda     >installed_options      ; read, never addressed
                ldx     #rmt_out+ID_OPT_FIELD
                ldb     #8                      ; every bit, as $808F does
id_banner_bit
                lsra                            ; carry = this option
                bcs     id_banner_next
                pshs    a
                lda     #' '                    ; absent: its field goes
                sta     ,x
                sta     1,x
                sta     2,x
                puls    a
id_banner_next
                leax    3,x
                decb
                bne     id_banner_bit
                rts

; ---------------------------------------------------------------------------
; id_banner_show - the banner for three seconds, then the Main Selection
;
;   uses:  A, B, X, Y, U
;
; The tail of show_id_screen_then_main_menu ($8DAD): show_id_screen ($80D2)
; builds the block and paints both lines from it, delay_ms ($D670) holds it
; for $0BB8 = 3000 milliseconds, and enter_paged_menu_mode ($8D23) opens the
; Main Selection Level. Driven on the stock 2026-09-11: shifted BACKSPACE
; shows the banner and the Main Selection is back without a key. This opened
; the Firmware Information screen and stayed there.
; ---------------------------------------------------------------------------
ID_HOLD_MS      equ     $0BB8                   ; three seconds

id_banner_show
                lbsr    id_banner_build
                lda     #LCD_LINE1
                ldx     #rmt_out
                ldb     #ID_LINE
                lbsr    lcd_write
                lda     #LCD_LINE2
                ldx     #rmt_out+ID_LINE
                ldb     #ID_LINE
                lbsr    lcd_write
                ldd     #ID_HOLD_MS
                lbsr    delay_ms
                lbra    main_menu_open

; ---------------------------------------------------------------------------
; info_option_text - the installed options, in HP's numbering
;
;   entry: X = at least INFO_OPTS_LEN bytes to write into
;   exit:  they hold "01/02/03" with any absent option's field blanked
;   uses:  A, B, X
;
; The same three fields the stock's banner carries, in the stock's order -
; 02, 01, 03, as id_banner_build lays them - blanked the same way. 02 comes
; from the channel count and the other two from bits 0 and 1 of $3FFC. It
; rendered them 01, 02, 03, which is not what the instrument shows.
; ---------------------------------------------------------------------------
INFO_OPTS_LEN   equ     8               ; "01/02/03"

info_option_text
                pshs    x
                ; OPTION 02 FIRST, AND IT IS THE CHANNEL COUNT, not a bit of
                ; $3FFC
                lda     >installed_channels
                cmpa    #$01
                bls     info_opt2_absent
                ldy     #info_opt_002
                bra     info_opt2_put
info_opt2_absent
                ldy     #info_opt_blank
info_opt2_put
                lbsr    info_opt_copy

                lda     #'/
                sta     ,x+
                ldb     #OPTION_001
                lbsr    option_test             ; Z clear when it is fitted
                beq     info_opt1_absent
                ldy     #info_opt_001
                bra     info_opt1_put
info_opt1_absent
                ldy     #info_opt_blank
info_opt1_put
                lbsr    info_opt_copy

                lda     #'/
                sta     ,x+
                ldb     #OPTION_003
                lbsr    option_test
                beq     info_opt3_absent
                ldy     #info_opt_003
                bra     info_opt3_put
info_opt3_absent
                ldy     #info_opt_blank
info_opt3_put
                lbsr    info_opt_copy
                puls    x
                rts

; two characters from Y to X, which is every field on this line
info_opt_copy
                lda     ,y+
                sta     ,x+
                lda     ,y+
                sta     ,x+
                rts

info_opt_001    fcc     "01"
info_opt_002    fcc     "02"
info_opt_003    fcc     "03"
info_opt_blank  fcc     "  "

; ---------------------------------------------------------------------------
; info_show - paint the whole screen
;
;   uses:  A, B, X, Y, U
;
; Two lines at a time, since the display holds two: the caller steps through
; the pages. This is the first.
; ---------------------------------------------------------------------------
info_show
                clr     >info_page              ; always open on the first
                ldx     #info_key               ; view
                lbsr    screen_install
                lda     #LCD_LINE1
                ldx     #info_title
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write

                lda     #LCD_LINE2
                ldx     #info_rev
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write
                lda     #LCD_LINE2+5
                ldx     #info_revision
                ldb     #INFO_REV_LEN
                lbra    lcd_write

; ---------------------------------------------------------------------------
; info_show_serial - the serial number page
;
;   uses:  A, B, X, Y, U
; ---------------------------------------------------------------------------
info_show_serial
                ldx     #info_key               ; NEXT and LAST page between
                lbsr    screen_install          ; the three views
                lda     #LCD_LINE1
                ldx     #info_serial
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write
                ldx     #serial_number
                lbsr    uint24_to_text
                lda     #LCD_LINE1+5
                ldx     #text_buffer
                ldb     #TEXT_DIGITS
                lbsr    lcd_write

                ; AND LINE 2 SAYS WHERE THE SERIAL IS KEPT.
                ;
                ; This view is one of three paged with NEXT and LAST, and it
                ; was the only one that never wrote line 2 - the other two
                ; paint a label and a value there. So paging from the revision
                ; view to this one left "Rev: ..." standing underneath
                ; "S/N: ...", a value shown under a label no longer on screen.
                ; It was blanked for that; now it carries the store.
                ;
                ; WHY IT IS WORTH A LINE. With a One ROM fitted the serial and
                ; the options live in the board's bank and outlive the battery;
                ; with the original part, or a board that has stopped
                ; answering, they are in battery RAM exactly as they always
                ; were. Both are correct and the instrument behaves the same
                ; either way, which is precisely why it has to be said: a board
                ; that quietly stopped persisting would look like one that
                ; never was fitted, and the first anyone would know is a flat
                ; battery and a lost serial.
                ;
                ; It was written, backed out when the image was full, and put
                ; back when cutting the options screen to "Opt 001  On" freed
                ; 203 bytes. Both halves are in the core, which is where
                ; service_info.s is and where those bytes landed.
                lda     #LCD_LINE2
                lbsr    lcd_blank_line
                lda     #LCD_LINE2
                ldx     #info_store
                ldb     #INFO_STORE_LEN
                lbsr    lcd_write

                lda     >bank_present
                cmpa    #BANK_PRESENT_MAGIC
                beq     info_store_bank
                ldx     #info_store_batt
                bra     info_store_show
info_store_bank
                ldx     #info_store_rom
info_store_show
                lda     #LCD_LINE2+INFO_STORE_LEN
                ldb     #INFO_STORE_VAL
                lbra    lcd_write

info_store      fcc     "Kept in: "
INFO_STORE_LEN  equ     9
info_store_rom  fcc     "ONE ROM bank"
info_store_batt fcc     "battery RAM "
INFO_STORE_VAL  equ     12


; ---------------------------------------------------------------------------
; info_show_options - the option bits and the channel count
;
;   uses:  A, B, X
;
; The options are shown as eight characters, bit 7 first, because that is
; what the operator needs to compare against a codeword label or another
; instrument. The channel count is what count_installed_channels found by
; probing the output latches, not what any option bit claims.
; ---------------------------------------------------------------------------
info_show_options
                ldx     #info_key               ; NEXT and LAST page between
                lbsr    screen_install          ; the three views
                lda     #LCD_LINE1
                ldx     #info_opts
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write
                ; HP'S OWN OPTION NUMBERS, not eight raw bits. The stock's
                ; banner reads "Opts 02/01/03/  /..." and blanks the field of
                ; any option that is absent, so an engineer sees the numbers
                ; printed on the instrument's own label. This printed
                ; "00000011", which carries the same information only to
                ; somebody who already knows that bit 0 is option 001 and bit
                ; 1 is option 003.
                ;
                ; AND 02 IS NOT A BIT. build_id_banner ($8000) blanks the "02"
                ; field on the CHANNEL COUNT - three spaces to $2293-$2295
                ; when $23B2 is not greater than one - and only the other two
                ; fields on bits of $3FFC. So the rewrite's screen could not
                ; show option 002 at all: it was not looking at the thing that
                ; decides it.
                ldx     #text_buffer
                lbsr    info_option_text
                lda     #LCD_LINE1+6
                ldx     #text_buffer
                ldb     #INFO_OPTS_LEN
                lbsr    lcd_write

                lda     #LCD_LINE2
                ldx     #info_chans
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write
                ldb     >installed_channels
                addb    #'0'                    ; 0 to 4 fits one digit
                stb     >text_buffer
                lda     #LCD_LINE2+10
                ldx     #text_buffer
                ldb     #1
                lbra    lcd_write

; ---------------------------------------------------------------------------
; info_key - the Firmware Information screen's keys
;
;   entry: B = the key code
;   uses:  A, B, X, Y
;
; NEXT and LAST page through the three views: the firmware revision, the
; serial number, and the installed options. Any other key leaves.
;
; The three existed as separate routines and only the first was reachable, so
; two thirds of what this screen was written to show could not be got to.
; Three menu entries would have worked too; paging is fewer keystrokes for
; what is one question - what is this instrument - asked three ways.
; ---------------------------------------------------------------------------
INFO_PAGES      equ     3

info_key
                cmpb    #KEY_NEXT
                bne     info_key_last
                lda     >info_page
                inca
                cmpa    #INFO_PAGES
                blo     info_key_select
                clra
                bra     info_key_select
info_key_last
                cmpb    #KEY_LAST
                bne     info_key_leave
                lda     >info_page
                bne     info_key_back
                lda     #INFO_PAGES
info_key_back
                deca
info_key_select
                sta     >info_page
                lbra    info_repaint
info_key_leave
                lbra    service_back_handler

; ---------------------------------------------------------------------------
; info_repaint - draw whichever view is selected
;
;   uses:  A, B, X, Y
; ---------------------------------------------------------------------------
info_repaint
                lda     >info_page
                beq     info_repaint_revision
                cmpa    #$01
                beq     info_repaint_serial
                lbra    info_show_options
info_repaint_serial
                lbra    info_show_serial
info_repaint_revision
                lbra    info_show

