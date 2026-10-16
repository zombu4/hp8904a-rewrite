; ===========================================================================
; service_screens.s - the service menu, and the screens under it
;
; Everything the stock firmware hides is here, named and unlocked:
;
;   diagnostics       behind the six-digit access code 092448 in the stock
;                     firmware, held as ASCII at page 3 $4466 and compared
;                     with mem_compare_bytes. There is no code here.
;   serial number     SHIFT SPECIAL 87, undocumented outside the service
;                     manual, and refused unless the current value is
;                     factory-virgin
;   options           SHIFT SPECIAL 48, refused if the serial is virgin OR
;                     zero - the other half of the deadlock - and able only
;                     to turn options ON
;   option list       SHIFT SPECIAL 37, in no page of the service manual at
;                     all; found by reading the comparison at page 3 $6C53
;
; A number you have to already know is not a security measure on a signal
; generator. It is a way to lose access to your own instrument, and combined
; with the serial/option deadlock it is how a flat battery became a board
; replacement.
; ===========================================================================

; --- The top-level service menu -------------------------------------------
; Labels are exactly forty characters, checked by the test rather than by
; counting them here: a nineteen-character label shifts every following byte
; of the record and makes the handler address garbage.

; THE TOP-LEVEL MENU'S TABLE IS IN service_backlight.s, above the ABI table.
; It is data - menu_open is handed its address - and A2U12 below the table
; had no room for another forty-three-byte entry when the Display Backlight
; one was added. Nothing else moved with it.


; --- The options screen ------------------------------------------------------
; On page 3 since 2026-09-19: page3_screens.s opts_open, reached below through
; page 3's fourth entry vector. docs/options-screen.md has the design - the
; architect's layout, and the two bits the stock actually tests.

; --- The diagnostics submenu ----------------------------------------------
; NOT the stock's list. The claim that stood here until 2026-09-07 - "every
; screen the stock firmware puts behind its access code, plus nothing extra" -
; held of no version of this table; see docs/coverage-truth.md. What is here:
;
;   six that are the stock's own diagnostics entries - ROM Checksum, RAM Test,
;     Keyboard Check, Display Check, PLL Check, Memory Map Access;
;   Hop RAM, which is stock behaviour in a different place: on the instrument
;     it is the RAM half of Manual CowChip Check, reached by that screen's own
;     Ram/Reg softkey rather than by a menu entry of its own;
;   DDS Registers, which the stock has no counterpart for - a read-only view
;     of the shadow. The stock's register screen is Manual CowChip, ported
;     separately in page3_cowchip.s and reached from the Main Selection.
;
; Manual Memory Read/Write, which was absent - see the header of
;     service_memmap.s for the one refusal it carries that the stock's does
;     not, and why the answer to a dangerous screen is a guard rather than an
;     absence;
;
; One of the stock's nine is not on this menu: Manual CowChip, which is a Main
; Selection entry instead.
;
; Each is marked destructive where it is: the RAM test overwrites the memory it
; walks, and the register screens drive the output hardware.

diagnostics_menu_title
                fcc     "*****         DIAGNOSTICS          *****"

diagnostics_menu_entries
                fcc     "ROM Checksum        both devices        "
                fdb     diag_rom_check
                fcb     SVC_PLAIN
                fcc     "RAM Test    DESTROYS scratch, not cal.  "
                fdb     diag_ram_entry
                fcb     SVC_DESTRUCTIVE
                fcc     "Keyboard Check      press every key     "
                fdb     diag_keyboard
                fcb     SVC_PLAIN
                fcc     "Display Check       all 80 characters   "
                fdb     diag_display
                fcb     SVC_PLAIN
                fcc     "PLL Check    UP/DOWN sweeps the divider "
                fdb     diag_pll
                fcb     SVC_DESTRUCTIVE         ; it steps the reference
                                                ; divider, so every channel's
                                                ; frequency moves while it is
                                                ; up. The default goes back on
                                                ; the way out
                fcc     "Reference + Faults  ext ref, trips      "
                fdb     diag_pll_status
                fcb     SVC_PLAIN
                fcc     "Memory Map Access   read any address    "
                fdb     diag_memory_map
                fcb     SVC_DESTRUCTIVE
                fcc     "DDS Registers       live values         "
                fdb     diag_dds_registers
                fcb     SVC_DESTRUCTIVE
                fcc     "Hop RAM             what the chip holds "
                fdb     diag_hop_ram
                fcb     SVC_PLAIN
                fcc     "Manual Memory       read/write a byte   "
                fdb     diag_manual_memory
                fcb     SVC_DESTRUCTIVE
                fcc     "Manual CowChip      poke the DDS direct "
                fdb     mode_manual_cowchip
                fcb     SVC_DESTRUCTIVE         ; WHERE THE INSTRUMENT KEEPS
                                                ; IT: f3 of the diagnostics
                                                ; menu's hidden record 3
                                                ; ($4196 -> $5EC8), beside
                                                ; Manual Memory on f1. It was
                                                ; an entry on the Main
                                                ; Selection Level here, which
                                                ; put a screen that writes the
                                                ; synthesis chip directly one
                                                ; keypress from an operator
                fcc     "Relay Exercise      cycle every relay   "
                fdb     diag_relay              ; the architect's addition -
                fcb     SVC_PLAIN               ; docs/relay-exercise.md. It
                                                ; opens stopped: nothing moves
                                                ; until UP, DOWN or ENTER
                fcc     "Back                up one level        "
                fdb     service_back
                fcb     SVC_BACK
DIAG_ENTRIES    equ     13

; ---------------------------------------------------------------------------
; service_menu_open - put the service menu on the display
;
;   uses:  A, B, X, Y
;
; No access code, no special-function number, no gate. This is reachable from
; the ordinary menu system like anything else.
; ---------------------------------------------------------------------------
service_menu_open
                ldx     #service_menu_entries
                ldb     #SERVICE_ENTRIES
                ldy     #service_menu_title
                lbsr    menu_open
                rts

; ---------------------------------------------------------------------------
; options_open - the Installed Options screen, on page 3
;
;   uses:  A, B, X, Y
; ---------------------------------------------------------------------------
options_open
                lda     #PAGE_MANUAL_COWCHIP    ; page 3, its fourth vector:
                lbra    page_enter_fourth       ; opts_open

; ---------------------------------------------------------------------------
; diagnostics_open - the diagnostics menu, with no code to enter
;
;   uses:  A, B, X, Y
; ---------------------------------------------------------------------------
diagnostics_open
                ldx     #diagnostics_menu_entries
                ldb     #DIAG_ENTRIES
                ldy     #diagnostics_menu_title
                lbra    menu_open               ; menu_hooks_apply installs
                                                ; the prompt its six
                                                ; destructive entries need

; ---------------------------------------------------------------------------
; The menu records above name their handlers by the role the entry plays;
; these tie each role to the routine that fills it. Every one resolves to a
; real screen, and the assembler refuses the file if any does not.
;
; The indirection is worth its line count: a menu record that named
; serial_show directly would have to be edited whenever the screen behind it
; was replaced, and a menu whose entries are edited is a menu whose ordering
; drifts. hp8904a-rewrite/tests/test_menu_complete.py checks that every role here resolves.
; ---------------------------------------------------------------------------
serial_screen           equ     serial_show_armed
options_screen          equ     options_open
diagnostics_screen      equ     diagnostics_open
firmware_screen         equ     info_show
error_screen            equ     error_open
service_exit            equ     service_exit_handler
service_back            equ     service_back_handler
diag_rom_check          equ     diag_rom_run
diag_ram_entry          equ     diag_ram_run
diag_keyboard           equ     diag_keyboard_run
diag_display            equ     diag_display_run
diag_pll                equ     pll_check_run   ; the stock's PLL Check: the
                                                ; manual divider sweep at
                                                ; page 3 $530F
diag_pll_status         equ     pll_show        ; and the reference-and-faults
                                                ; report, which the stock has
                                                ; no screen for - the same
                                                ; lines its foreground polls
diag_memory_map equ     memmap_open     ; NOT memmap_show: that one takes
                                        ; an element index in B and this
                                        ; path has none to give it
diag_dds_registers      equ     dds_open        ; NOT dds_show: that one paints
                                                ; whatever register is selected
                                                ; and this path selects none
diag_manual_memory      equ     memw_open       ; service_memmap.s, which is
                                                ; assembled before this file
; diag_hop_ram is declared in main_menu.s, where its target is. An equ needs
; its target defined first and main_menu.s is assembled after this file,
; because it names service_menu_open from here. There was a second such alias,
; diag_page3, until the empty Page 3 Diagnostics screen was removed on
; 2026-09-07; see docs/coverage-truth.md.
