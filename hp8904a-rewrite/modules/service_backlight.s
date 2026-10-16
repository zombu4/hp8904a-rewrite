; ===========================================================================
; service_backlight.s - which display is fitted, and how long its lamp stays
;
; THE ARCHITECT'S ADDITION, 2026-09-17, in
; his words. The INSTRUMENT has a fixed idle timeout of about three minutes -
; foreground_main_loop reloads $0FDD on the keystroke path (a2u12.s:1168),
; counts eighteen wraps (CMPB #$12 at :1247) and drops the lamp through
; clear_lamp_and_flag (:1252), and the manual's printed page 8-41 says
; "approximately 3 minutes". What is added here is the CHOICE: an aftermarket
; backlit display that never times out, or the original with a timeout of 5 to
; 999 seconds, or Off.
;
; THE SETTING IS ANSWERED ONCE. backlight_set holds $5A when it has been, and
; nothing else does - 0 is a legitimate display kind and 0 seconds is a
; legitimate Off, so neither of those bytes can say "not chosen". A flat
; battery leaves $00 and unwritten RAM $FF, and both ask again.
;
; It sits above the ABI table with the prompts, where there is room.
; ===========================================================================

backlight_title fcc     "*****      DISPLAY BACKLIGHT       *****"

; --- the first-time screen IS the submenu ---------------------------------
; A WELCOME SCREEN OF ITS OWN DID NOT FIT. Two more entries and their handlers
; are 110 bytes and A2U12 was 21 over with them; the screen below says the
; same thing - which display, and how long - so a machine whose setting has
; never been answered opens on it at power-on and the operator answers it
; there. Reported to the architect 2026-09-17.

; --- the submenu, for changing it later ------------------------------------
backlight_menu_entries
                fcc     "Display                                 "
                fdb     backlight_toggle_kind
                fcb     SVC_PLAIN
                fcc     "Timeout                                 "
                fdb     backlight_secs_open
                fcb     SVC_PLAIN
                fcc     "Back                up one level        "
                fdb     service_back
                fcb     SVC_BACK
BL_MENU_ENTRIES equ     3

; THE FIELD IS BLANKED AND THEN WRITTEN, so these carry no padding: twenty
; columns of trailing spaces in five strings is a hundred bytes of ROM to say
; nothing, and A2U12 has none to spare.
bl_text_original fcc    "Original"
BL_LEN_ORIGINAL equ     8
bl_text_after   fcc     "Aftermarket"
BL_LEN_AFTER    equ     11
bl_text_nouse   fcc     "not used, lamp on"
BL_LEN_NOUSE    equ     17
bl_text_off     fcc     "Off"
BL_LEN_OFF      equ     3
bl_text_secs    fcc     "seconds"
BL_LEN_SECS     equ     7
BL_TEXT_LEN     equ     20
BL_VALUE_POS    equ     LCD_LINE2+20
BL_SECS_POS     equ     LCD_LINE2+36

BL_DEFAULT_SECS equ     180                     ; the instrument's own three
                                                ; minutes, which is in range and
                                                ; is what an unanswered machine
                                                ; runs on until it is answered

; ---------------------------------------------------------------------------
; backlight_menu_open - the setting, to change later
;
;   uses:  A, B, X, Y
; ---------------------------------------------------------------------------
backlight_menu_open
                ldx     #backlight_menu_entries
                ldb     #BL_MENU_ENTRIES
                ldy     #backlight_title
                lbra    menu_open               ; menu_hooks_apply installs
                                                ; backlight_annotate

; ---------------------------------------------------------------------------
; backlight_annotate - the entry's own value, beside it
;
;   entry: B = which entry
;   uses:  A, B, X
; ---------------------------------------------------------------------------
backlight_annotate
                tstb
                bne     backlight_annotate_secs
                ldx     #bl_text_original       ; entry 0: which display
                ldb     #BL_LEN_ORIGINAL
                lda     >backlight_kind
                cmpa    #BL_ORIGINAL
                beq     backlight_annotate_put
                ldx     #bl_text_after
                ldb     #BL_LEN_AFTER
                bra     backlight_annotate_put
backlight_annotate_secs
                cmpb    #$01
                bne     backlight_annotate_none ; Back has no value
                lda     >backlight_kind         ; AN AFTERMARKET DISPLAY HAS NO
                cmpa    #BL_ORIGINAL            ; TIMEOUT AT ALL, so the field
                beq     backlight_annotate_time ; is not offered as a number
                ldx     #bl_text_nouse
                ldb     #BL_LEN_NOUSE
                bra     backlight_annotate_put
backlight_annotate_time
                ldx     >backlight_secs
                bne     backlight_annotate_num
                ldx     #bl_text_off            ; 0 seconds is Off, and the
                ldb     #BL_LEN_OFF             ; field can still be set
                bra     backlight_annotate_put
backlight_annotate_num
                ldx     #bl_text_secs
                ldb     #BL_LEN_SECS
                lbsr    backlight_annotate_field
                clr     >rmt_tmp                ; the seconds, three digits
                ldx     >backlight_secs
                stx     >rmt_tmp+1
                ldx     #rmt_tmp
                lbsr    uint24_to_text
                lda     #BL_SECS_POS
                ldx     #text_buffer+5
                ldb     #$03
                lbra    lcd_write
backlight_annotate_put
                lbra    backlight_annotate_field

; backlight_annotate_field - blank the value field and write B bytes of X
;   entry: X = the text, B = its length
;   uses:  A, B, X
backlight_annotate_field
                pshs    b,x
                lda     #BL_VALUE_POS
                ldb     #BL_TEXT_LEN
                lbsr    lcd_blank
                puls    b,x
                lda     #BL_VALUE_POS
                lbra    lcd_write
backlight_annotate_none
                rts

; ---------------------------------------------------------------------------
; backlight_toggle_kind - the other display
;
;   uses:  A, B, X, Y
; ---------------------------------------------------------------------------
backlight_toggle_kind
                lda     >backlight_kind
                eora    #BL_AFTERMARKET         ; one bit, two kinds
                sta     >backlight_kind
                lda     #BACKLIGHT_MAGIC
                sta     >backlight_set
                lbsr    backlight_wake
                lbra    menu_draw

; ---------------------------------------------------------------------------
; backlight_secs_open - type a timeout, 5 to 999, or 0 for Off
;
;   uses:  A, B, X, Y
;
; The same shape as the bus address and SRQ mask screens: three digits into
; the panel's own entry, ENTER commits, f4 leaves.
; ---------------------------------------------------------------------------
bl_secs_title   fcc     "*****   TIMEOUT 5-999 s, 0 = OFF   *****"

backlight_secs_open
                ldx     #backlight_secs_commit
                ldy     #backlight_title
                ldb     #$03                    ; three digits: up to 999
                lbra    remote_screen_open

; ---------------------------------------------------------------------------
; backlight_secs_commit - take it if it is 0 or 5 to 999
;
;   uses:  A, B, X, Y, U
; ---------------------------------------------------------------------------
backlight_secs_commit
                lbsr    entry_value
                bcs     backlight_secs_bad
                lda     >entry_result           ; three digits cannot pass 999,
                bne     backlight_secs_bad      ; but a bus or a bug could
                ldx     >entry_result+1
                cmpx    #$0000                  ; 0 is Off
                beq     backlight_secs_take
                cmpx    #$0005                  ; and 5 is the floor
                blo     backlight_secs_bad
                cmpx    #999
                bhi     backlight_secs_bad
backlight_secs_take
                stx     >backlight_secs
                lda     #BACKLIGHT_MAGIC
                sta     >backlight_set
                lbsr    backlight_wake          ; the lamp and the new clock
                lbra    remote_screen_show      ; and the 'now =' field with it
backlight_secs_bad
                ldb     #ERR_VALUE_RANGE
                lbra    error_raise

; --- the top-level service menu's table, moved here for room ---------------
service_menu_title
                fcc     "*****         SERVICE MENU         *****"

service_menu_entries
                fcc     "Serial Number       view / re-enter     "
                fdb     serial_screen
                fcb     SVC_SUBMENU
                fcc     "Installed Options   view / toggle       "
                fdb     options_screen
                fcb     SVC_SUBMENU
                fcc     "Diagnostics         self-tests          "
                fdb     diagnostics_screen
                fcb     SVC_SUBMENU
                fcc     "Firmware Information  revision / build  "
                fdb     firmware_screen
                fcb     SVC_PLAIN
                fcc     "Display Backlight   which display, time "
                fdb     backlight_menu_open
                fcb     SVC_SUBMENU
                fcc     "Bus Address         remote, 0 to 30     "
                fdb     remote_address_open
                fcb     SVC_SUBMENU
                fcc     "Bus SRQ Mask        service request     "
                fdb     remote_sre_open
                fcb     SVC_SUBMENU
                fcc     "Last Error          what went wrong     "
                fdb     error_screen
                fcb     SVC_PLAIN
                fcc     "Exit                back to the menu    "
                fdb     service_exit
                fcb     SVC_PLAIN
; the two bus screens joined the six that were here
SERVICE_ENTRIES equ     9
