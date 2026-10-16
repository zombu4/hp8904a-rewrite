; ===========================================================================
; menu.s - the menu engine
;
; One routine draws every menu in the instrument, and one routine handles the
; keys for every menu. A menu is DATA: a table of fixed-size records, each a
; forty-character label and the address of what to run.
;
; WHY DATA AND NOT CODE. The stock firmware's service screens are each their
; own routine with their own key dispatch, which is how it ends up with
; separate handlers for the diagnostics menu, the special-function screen and
; the option screen - all doing the same job in three different ways, one of
; them behind an access code. A table means adding a screen is adding a
; record.
;
; THE DISPLAY IS TWO LINES. Line 1 is the title, line 2 is the selected entry.
; Menus longer than one entry scroll: the up and down keys move the selection
; and the display follows it, so a menu of any length works on a two-line
; screen without paging logic in every caller.
;
; NOTHING IS GATED. No entry is hidden by an option bit, a serial-number
; state or an access code. The whole point of the rewrite's service menus is
; that everything the instrument can do is reachable, named, and reachable
; the same way.
; ===========================================================================

MENU_TITLE_LINE equ     LCD_LINE1
MENU_ENTRY_LINE equ     LCD_LINE2

; ---------------------------------------------------------------------------
; menu_open - start showing a menu
;
;   entry: X = the entry table, B = how many entries, Y = the title
;   exit:  the menu is on the display with entry 0 selected
;   uses:  A, B, X, Y
;
; The title is forty characters, like a label, so it fits the line by
; construction rather than by being truncated at run time.
;
; IT ALSO TAKES THE KEYS. Every menu in this firmware is driven by the same
; three keys, so menu_open installs the handler rather than leaving each
; caller to remember - and a caller that forgot would paint a menu the
; previous screen's handler was still reading, where every key does something
; the operator cannot predict.
; ---------------------------------------------------------------------------
menu_open
                sty     >menu_title             ; kept so Back can redraw this
                                                ; menu without the caller
                                                ; having to hold on to it.
                                                ; menu_open_no_push below
                                                ; stores it again, and THAT is
                                                ; the one that matters: the
                                                ; nav stack enters there, and
                                                ; while only this line existed
                                                ; a menu reopened by Back kept
                                                ; the previous screen's title.
                                                ; Kept here so this entry
                                                ; point has a body of its own
                                                ; rather than being a bare
                                                ; label over a fall-through
; menu_open_no_push - reopen a menu without recording where it came from
;
;   entry: X = the entry table, B = how many entries, Y = the title
;   uses:  A, B, X, Y
;
; The nav stack's own entry point. Going BACK to a menu must not push that
; menu onto the stack again - one press of Back would then need two to
; undo, and the stack would fill with copies of the same screen.
;
; Everything else calls menu_open, which records the title and falls in here.
; ---------------------------------------------------------------------------
menu_open_no_push
                ; AND THE TITLE IS STORED HERE TOO, not only in menu_open.
                ; This was menu_open's alone, and while menu_title only fed
                ; Back's redraw that was harmless - the paint below takes Y
                ; directly. menu_entry_line now derives the entry's ROW from
                ; the same cell, so a stale one is a stale LAYOUT: coming back
                ; from the Installed Options screen, which has no heading and
                ; leaves menu_title zero, brought the Service Menu up in the
                ; headingless shape and painted its first entry over its own
                ; title. Caught by test_recovery_new.py's 8c.
                ;
                ; Both callers already hold the right title in Y -
                ; service_back_handler reads it from the nav stack
                ; (service_nav.s) and menu_reopen_current from menu_title
                ; itself - so this stores what they meant and never invents
                ; one.
                sty     >menu_title
                clr     >menu_armed             ; ARMING IS FOR ONE ENTRY,
                                                ; ONCE. It survived both a
                                                ; change of selection and a
                                                ; change of menu, so arming a
                                                ; destructive entry, moving
                                                ; away, and pressing ENTER on
                                                ; a different one ran that one
                                                ; on a single press - the
                                                ; confirmation belonged to an
                                                ; entry the operator had left.
                pshs    x
                ldx     #menu_key
                lbsr    screen_install
                puls    x
                stx     >menu_table
                pshs    b,x                     ; AND THE MENU'S OWN HOOKS,
                lbsr    menu_hooks_apply        ; whichever way it was opened
                puls    b,x
                stb     >menu_count
                clr     >menu_index
                clr     >menu_top

                tfr     y,x                     ; draw the title once; what
                clr     >menu_line1             ; line 1 holds is remembered in
                                                ; menu_line1, so menu_draw
                                                ; repaints it only when it
                                                ; changes, and 0 is the title
                pshs    x                       ; ARMED FIRST, because
                lbsr    banner_arm              ; banner_arm uses A and B: if
                puls    x                       ; the title is one of ours its
                                                ; stars walk from here
                ; A ZERO TITLE POINTER CLEARS LINE 1 instead of writing forty
                ; bytes from address $0000, which is what this did the first
                ; time the Installed Options screen passed Y = 0 - the dump
                ; showed $DF in column 1 and zeros after it.
                cmpx    #0
                beq     menu_open_clear_line1
                lda     #MENU_TITLE_LINE
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write
                lbra    menu_draw
menu_open_clear_line1
                lda     #MENU_TITLE_LINE
                lbsr    lcd_blank_line
                lbra    menu_draw

; ---------------------------------------------------------------------------
; menu_draw - repaint the selected entry
;
;   uses:  A, B, X
;
; Only line 2 is redrawn. The title does not change, and repainting it would
; make the display flicker on every key press for no reason.
; ---------------------------------------------------------------------------

menu_draw
                lbsr    menu_entry_address      ; X = the selected record
                pshs    x
                lbsr    menu_entry_line         ; line 1 when this menu has no
                puls    x                       ; heading - see the tail
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write

                ; A MARKER IN THE LAST COLUMN for an entry that opens another
                ; menu. menu_is_submenu existed to answer that and nothing
                ; asked it, so on a two-line display - where one entry is
                ; visible at a time - an operator had no way to tell an entry
                ; that leads somewhere from one that acts the moment it is
                ; chosen.
                lbsr    menu_is_submenu         ; Z clear when it opens one
                beq     menu_draw_plain
                ldb     #'>'
                lbra    menu_draw_marker
menu_draw_plain
                ldb     #' '
menu_draw_marker
                stb     >menu_marker
                lbsr    menu_entry_line
                adda    #SVC_LABEL_LEN-1
                ldx     #menu_marker
                ldb     #$01
                lbsr    lcd_write

                ; AND THE ENTRY AFTER IT ON LINE 2, for a menu with no
                ; heading - see menu_draw_second_row, above the table.
                lbsr    menu_draw_second_row

                ; AND WHATEVER THE MENU ITSELF WANTS TO SAY ABOUT THE ENTRY.
                ; A menu whose entries have a state - the five preferences on
                ; the Special Functions screen, the eight option bits - has to
                ; show it, and an operator who cannot see whether a preference
                ; is on can only toggle it and watch for a change somewhere
                ; else. That was the Special Functions screen exactly: five
                ; entries that flipped a bit and reported nothing.
                ldx     >menu_annotate
                beq     menu_draw_line1
                ldb     >menu_index
                jsr     ,x

                ; AND LINE 1 SAYS WHAT THE ARMED PRESS WILL DO. The first
                ; press of a destructive entry arms it and repainted the same
                ; eighty characters, so on the bench it read as a dead key -
                ; the architect found it on the instrument 2026-09-17 and
                ; ruled that the confirmation stays and shows itself. The
                ; stock's own idiom for a destructive commit that waits is a
                ; whole line, "Press SHIFT \x02 to install S/N =      .  " on
                ; its serial-installation screen (a2u13_page3.bin $27D2), and
                ; this is that line: while menu_armed stands, the menu's
                ; prompt callback names the entry and the direction, and the
                ; title comes back the moment it is cancelled or run.
menu_draw_line1
                ldb     #$00                    ; what line 1 should hold: the
                lda     >menu_armed             ; title, or the armed entry's
                beq     menu_draw_line1_want    ; prompt, one-based so that
                ldx     >menu_prompt            ; zero can mean the title
                beq     menu_draw_line1_want
                ldb     >menu_index
                incb
menu_draw_line1_want
                cmpb    >menu_line1             ; already showing: leave it
                beq     menu_draw_done          ; rather than repaint it on
                stb     >menu_line1             ; every key
                tstb
                bne     menu_draw_line1_prompt
                ldx     >menu_title             ; nothing armed: the title
                ; AND A ZERO TITLE MEANS THERE IS NO TITLE, here as well as in
                ; menu_open. menu_open was taught it and this was not, so on the
                ; Installed Options screen - the one menu with no heading - the
                ; prompt going away wrote forty bytes from address $0000 over
                ; line 1. On a headingless menu line 1 is the ENTRY row, and the
                ; paint at the top of menu_draw already owns it, so there is
                ; nothing left to do: not the title, and not a blank either,
                ; which would erase the entry just painted.
                ;
                ; It fired on every option toggle (menu_key_run clears menu_armed
                ; then calls the handler, which comes back through menu_draw) and
                ; on every cancel (menu_key_ignore, screen.s).
                beq     menu_draw_done
                lda     #MENU_TITLE_LINE
                ldb     #SVC_LABEL_LEN
                lbra    lcd_write
menu_draw_line1_prompt
                decb                            ; B = the entry again, and the
                ldx     >menu_prompt            ; callback paints the line
                jmp     ,x                      ; itself: its RTS is ours
menu_draw_done
                rts

; ---------------------------------------------------------------------------
; menu_entry_line - which row the selected entry paints on
;
;   exit:  A = LCD_LINE1 when this menu has no heading, LCD_LINE2 when it has
;   uses:  A, X
;
; A menu with a heading keeps it on line 1 and shows one entry on line 2. A
; menu WITHOUT one moves up, and the entry takes line 1. Every menu in the tree
; has a heading since the Installed Options screen, the one that had none,
; became a screen of its own on page 3 (2026-09-19); menu_open still takes a
; zero title and this still answers for it.
;
; Derived from menu_title rather than stored: that cell already decides, and a
; second one saying the same is one more to keep in step.
;
; IN THE CORE, beside its only callers. It went above the table first and came
; back: the second-row routine is 39 bytes and the tail had 31, while the core
; had 32 - so the small one moved down and the big one took its place.
; ---------------------------------------------------------------------------
menu_entry_line
                ; X IS NOT TOUCHED. This tested the title with ldx once, and a
                ; caller that loaded X with its text before asking which row
                ; wrote the wrong bytes over the label.
                lda     >menu_title
                ora     >menu_title+1
                beq     menu_entry_line_top
                lda     #MENU_ENTRY_LINE
                rts
menu_entry_line_top
                lda     #MENU_TITLE_LINE
                rts

; ---------------------------------------------------------------------------
; menu_reopen_current - repaint the menu that is up, and take its keys back
;
;   uses:  A, B, X, Y
;
; For a menu entry that RUNS something and comes back rather than opening a
; screen of its own. screen.s menu_key_run pushes the nav stack before it
; calls the entry and calls nav_undo_push afterwards if screen_handler is
; unchanged - so an entry that returns with the menu's own handler installed
; needs the display repainted and NOTHING else touched.
;
; service_back_handler is the wrong routine for that: it POPS the nav stack,
; and menu_key_run would then undo the push as well, leaving the depth one
; level too shallow and Back going up two levels on the next press.
;
; The selection is kept. menu_open_no_push clears menu_index and menu_top,
; which would drop the operator back on the first entry of the menu rather
; than the one they just ran.
; ---------------------------------------------------------------------------
menu_reopen_current
                lda     >menu_index
                pshs    a
                lda     >menu_top
                pshs    a
                ldx     >menu_table
                ldb     >menu_count
                ldy     >menu_title
                lbsr    menu_open_no_push
                puls    a
                sta     >menu_top
                puls    a
                sta     >menu_index
                lbra    menu_draw

; ---------------------------------------------------------------------------
; menu_entry_address - where the selected record starts
;
;   exit:  X = the record, which begins with its forty-character label
;   uses:  A, B, X
; ---------------------------------------------------------------------------
menu_entry_address
                ldx     >menu_table
                lda     >menu_index
                beq     menu_entry_done         ; entry 0 needs no arithmetic
menu_entry_step
                ldb     #SVC_ENTRY_SIZE
                abx                             ; one record further on
                deca
                bne     menu_entry_step
menu_entry_done
                rts

; ---------------------------------------------------------------------------
; menu_next - move the selection down, wrapping
;
;   uses:  A, B, X
;
; It WRAPS. A menu that stops at the end makes the last entry harder to reach
; than the first, and on a two-line display where only one entry is visible
; there is nothing to be gained by refusing to move.
; ---------------------------------------------------------------------------
menu_next
                clr     >menu_armed             ; ARMING IS FOR ONE ENTRY,
                                                ; ONCE. It survived both a
                                                ; change of selection and a
                                                ; change of menu, so arming a
                                                ; destructive entry, moving
                                                ; away, and pressing ENTER on
                                                ; a different one ran that one
                                                ; on a single press - the
                                                ; confirmation belonged to an
                                                ; entry the operator had left.
                lda     >menu_index
                inca
                cmpa    >menu_count
                blo     menu_next_store
                clra                            ; past the end: back to 0
menu_next_store
                sta     >menu_index
                lbra    menu_draw

; ---------------------------------------------------------------------------
; menu_previous - move the selection up, wrapping
;
;   uses:  A, B, X
; ---------------------------------------------------------------------------
menu_previous
                clr     >menu_armed             ; ARMING IS FOR ONE ENTRY,
                                                ; ONCE. It survived both a
                                                ; change of selection and a
                                                ; change of menu, so arming a
                                                ; destructive entry, moving
                                                ; away, and pressing ENTER on
                                                ; a different one ran that one
                                                ; on a single press - the
                                                ; confirmation belonged to an
                                                ; entry the operator had left.
                lda     >menu_index
                bne     menu_previous_step
                lda     >menu_count             ; before the start: to the end
menu_previous_step
                deca
                sta     >menu_index
                lbra    menu_draw

; ---------------------------------------------------------------------------
; menu_handler - the address of what the selected entry runs
;
;   exit:  X = the handler address, B = the entry's flags
;   uses:  A, B, X
;
; The caller decides what to do with it. menu.s deliberately does not call
; the handler itself: a menu entry that opens a submenu and one that runs a
; test need different treatment, and the flags say which is which.
; ---------------------------------------------------------------------------
menu_handler
                lbsr    menu_entry_address
                ldb     SVC_LABEL_LEN+2,x       ; the flags byte
                pshs    b
                ldx     SVC_LABEL_LEN,x         ; the handler address
                puls    b
                rts

; ---------------------------------------------------------------------------
; menu_is_submenu - does the selected entry open another menu?
;
;   exit:  Z clear if it does
;   uses:  A, B, X
; ---------------------------------------------------------------------------
menu_is_submenu
                lbsr    menu_handler
                andb    #SVC_SUBMENU
                rts

; ---------------------------------------------------------------------------
; menu_is_destructive - does it change stored state or disturb the output?
;
;   exit:  Z clear if it does
;   uses:  A, B, X
;
; The renderer marks these so nobody walks into a destructive RAM test
; expecting a read-only one. A service menu that does not distinguish them is
; how an engineer loses a machine's calibration by pressing the wrong key.
; ---------------------------------------------------------------------------
menu_is_destructive
                lbsr    menu_handler
                andb    #SVC_DESTRUCTIVE
                rts
