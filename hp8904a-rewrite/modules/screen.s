; ===========================================================================
; screen.s - which screen has the keys, and the keys a menu uses
;
; Two things that were in boot.s and belong here.
;
; screen_install was there because the foreground was its only caller. That
; made boot.s a dependency of menu.s, and menu.s is used by test harnesses
; that have no reason to carry a power-on sequence - so the harnesses stopped
; assembling the moment menu_open started installing a key handler. A
; routine's home is where its callers are, not where its first caller
; happened to be.
;
; menu_key was there for the same reason and is worse placed: it is menu
; behaviour, it reads menu state, and it belongs beside the menu.
; ===========================================================================

; ---------------------------------------------------------------------------
; screen_install - make a screen the one that gets the keys
;
;   entry: X = its key handler
;   uses:  A, X - and X IS ITS ARGUMENT. It clears screen_commit,
;          screen_f1 and screen_f4 through X, so a caller cannot pass the
;          handler and then go on using X for something else. That was true
;          the moment those three were added and this header still said
;          "nothing".
;
; Every screen calls this as it paints. One place, so that a screen cannot
; paint itself and forget to take the keys - which leaves the previous
; screen's handler running against the new screen's display, and every key
; then does something the operator cannot predict.
;
; THE CURSOR IS NOT TOUCHED HERE, and it used to be turned off on every
; install. The instrument has no such moment: its display-control byte is
; written at $ACA6 and $B3BA and nowhere else (entry.s, over entry_cursor_on),
; and installing a screen handler reaches neither. A screen replacing one with
; an entry open is reached through a key the keymap maps, and entry_key_exit
; has already taken the cursor down at $B45C's moment; with no entry open it
; is already off. Measured on the stock in the emulator: NEXT, LAST, LOCAL and
; the REN release write no display-control byte at all, and this wrote one on
; each.
; ---------------------------------------------------------------------------
screen_install
                ; THE OUTGOING SCREEN'S LEAVE RUNS FIRST, whichever way it is
                ; being left - f4, Back, LOCAL, a shifted key, the bus all
                ; end here. The relay exercise puts every relay it moved back
                ; this way (docs/relay-exercise.md). The vector is cleared
                ; before it is called, so a leave that installs a screen of
                ; its own cannot run twice, and it is always an A2U12 address:
                ; this may be running from any page, and page_call does not
                ; put the caller's page back.
                pshs    b,x,y,u
                ldx     >screen_leave
                beq     screen_install_left
                clr     >screen_leave
                clr     >screen_leave+1
                jsr     ,x
screen_install_left
                puls    b,x,y,u
                clr     >screen_poll            ; and the new screen polls only
                clr     >screen_poll+1          ; if it asks to

                ; THE GLASS IS RELEASED. lcd_hold - bit 4 of event_flags
                ; on the instrument - keeps every other painter off the
                ; display while something owns it, and the error banner sets
                ; it (errors.s). A screen that installs itself IS the new
                ; owner, so a hold left standing by whatever it replaced would
                ; outlive its owner and blank the new screen.
                ;
                ; This is what let the Save / Recall overlay be written
                ; without taking $F370's hold: the port that wrote it
                ; declined the bit because LOCAL and the shifted keys are
                ; answered in boot.s without consulting the screen handler,
                ; so a held glass could survive the prompt - and
                ; tests/test_screens_take_keys.py refuses, correctly, any
                ; screen but the Keyboard Check taking LOCAL for itself.
                ; Clearing it here makes the hold safe to take: it can never
                ; last past the next screen.
                clr     >lcd_hold

                stx     >screen_handler

                ; AND ANY HALF-TYPED ENTRY DIES WITH THE OLD SCREEN. This is
                ; the stock's request code $3C, ported: ui_message_dispatch
                ; ($8D60) rewrites $2217 to $003C when the modal handler at
                ; $220D reports it has finished ($8D7E LDD #$003C / STD
                ; >$2217), $3C is above the 34-arm table's range ($8F13 CMPX
                ; #$0022 / LBGT) so it is handed to the screen underneath, and
                ; every screen answers it identically - page 1's arm [59]
                ; key_clear_entry_state ($505F) calls cancel_pending_entry
                ; ($47D6) and zeroes $3D11, page 2's arm [59]
                ; key_close_entry_field ($6E3A) calls
                ; flush_pending_field_edit ($6877) and zeroes $3CAC, page 0's
                ; chain sends $003C to l5D22, which zeroes $2215 and calls
                ; end_field_edit. Three independent handlers, one meaning: a
                ; screen change abandons the entry in progress.
                ;
                ; Without it the flag outlives the screen, and because
                ; chan_digit_typed APPENDS when it is set, the first digit
                ; typed on the new screen lands on the end of the old
                ; screen's half-typed number. That was fixed once, in
                ; channel_config_open alone - the instance, not the class,
                ; and every other screen still had it.
                clr     >entry_active
                clr     >rmt_stream             ; AND THE BUS'S PER-SCREEN
                clr     >rmt_pend_kind          ; STATE: a sequence-data
                clr     >rmt_seq_owner          ; stream, the field a bus value
                                                ; would commit to, and which
                                                ; screen took SEQP/SEQE all
                                                ; belong to the screen that
                                                ; was up; the stock's field
                                                ; cursor is per mode too

                clr     >banner_stars           ; AND THE WALKING STAR STOPS:
                                                ; the screen coming up says
                                                ; whether it has a banner of
                                                ; ours, and until it does there
                                                ; is nothing to animate
                ldx     #$0000                  ; AND THE MENU'S PROMPT with it:
                stx     >menu_prompt            ; the line that names an armed
                                                ; entry's action belongs to the
                                                ; menu that set it
                ldx     #$0000                  ; AND THE MENU ANNOTATION,
                stx     >menu_annotate          ; for the same reason as the
                                                ; three vectors below: a menu
                                                ; that does not set one would
                                                ; otherwise paint the last
                                                ; menu's state beside its own
                                                ; entries

                clr     >screen_takes_shift     ; and the shifted keys, the
                                                ; same way and for the same
                                                ; reason
                clr     >screen_keeps_local     ; a screen that wants the
                                                ; LOCAL key must say so AFTER
                                                ; installing, every time. The
                                                ; default is that LOCAL goes
                                                ; back, so a screen cannot
                                                ; trap anybody by forgetting
                                                ; to clear a flag somebody
                                                ; else set.

                ; AND THE SAME FOR THE VECTORS, for exactly the same reason.
                ; screen_keeps_local was cleared here and screen_commit,
                ; screen_f1 and screen_f2 were not - so a screen that does not
                ; set them inherited whatever the last screen left, and ENTER
                ; or f1 on the new screen ran the old screen's handler against
                ; the new screen's display. Every screen in the tree installs
                ; its handler before setting its vectors, checked across all
                ; of modules/, so clearing them here cannot erase one that has
                ; already been set.
                ldx     #$0000
                stx     >screen_commit
                stx     >screen_f1
                stx     >screen_f4
                rts

; ---------------------------------------------------------------------------
; menu_key - act on one key press
;
;   entry: B = the key code
;   uses:  A, B, X, Y, U - U through the handler it jumps into, several
;          of which declare it. A callee's clobbers are the caller's, and
;          test_clobbers.py cannot see them: it says so in its own text.
;
; Three keys move and choose; everything else is ignored rather than beeping.
; A service menu that complains about keys it does not use is a service menu
; that beeps constantly while somebody looks for the one that works.
; ---------------------------------------------------------------------------
; The three keys a menu uses. Their codes are in common/keys.inc, read out of
; the instrument's own action table and verified against it byte for byte.
; They were $12, $13 and $14 here, which are the codes for the digit 2, the
; up arrow and the NEXT key - so two of the three menu keys were wrong, and
; the third moved the selection when the operator pressed a number.
;
; The up and down arrows move; ENTER chooses. NEXT and LAST are deliberately
; not used: the screens that edit fields use those to move between fields,
; and a key meaning "next field" on one screen and "next menu entry" on
; another is a key an operator has to stop and think about.
KEY_MENU_UP     equ     KEY_UP
KEY_MENU_DOWN   equ     KEY_DOWN
KEY_MENU_SELECT equ     KEY_ENTER

menu_key
                ; F4 LEAVES, and it had to be added. This handler took UP,
                ; DOWN and SELECT and refused everything else, so a menu could
                ; only be left through an entry that goes somewhere - and the
                ; INSTALLED OPTIONS menu has no such entry: its ten records are
                ; eight bit toggles and "All Options Off". An operator who
                ; opened it was stuck there until the power was cycled, which
                ; during a flat-battery recovery means losing the serial just
                ; entered. service_back_handler pops one level, or reopens the
                ; Main Selection at the top, so f4 is safe on every menu
                ; including the Main Selection itself.
                cmpb    #KEY_F4
                lbeq    service_back_handler
                cmpb    #KEY_MENU_UP
                bne     menu_key_down
                lbra    menu_previous
menu_key_down
                cmpb    #KEY_MENU_DOWN
                bne     menu_key_select
                lbra    menu_next
menu_key_select
                cmpb    #KEY_MENU_SELECT
                bne     menu_key_ignore

                ; A DESTRUCTIVE ENTRY IS CONFIRMED. The flag is in every menu
                ; record and menu_is_destructive existed to read it, and
                ; nothing called either - so "RAM Test DESTROYS scratch" and
                ; "Memory Map Access" opened on one press exactly like
                ; "Firmware Information".
                ;
                ; The confirmation is a SECOND press of the same key, not a
                ; yes/no screen: the operator has already chosen the entry
                ; and the screen already says what it does, so what is needed
                ; is a moment, not a question. Any other key cancels, which
                ; means a mis-press cannot arm it.
                lbsr    menu_is_destructive     ; Z set when it is not
                beq     menu_key_run
                lda     >menu_armed
                bne     menu_key_run            ; already asked: go
                lda     #$01
                sta     >menu_armed
                lbra    menu_draw               ; repaint, which shows the
                                                ; entry again under a screen
                                                ; that is now waiting
; RUNNING AN ENTRY, AND REMEMBERING THE MENU ONLY IF IT IS LEFT.
;
; This pushed the current menu for EVERY entry, unconditionally. Two things
; went wrong with that:
;
;   the Back entry is an ordinary record, so pressing it wrote the menu now
;   showing into slot N and stepped nav_top to N+1, and service_back_handler
;   then decremented to N and read back the entry just written - reopening
;   the menu the operator was trying to leave, first press, any depth;
;
;   an entry that only toggles a setting returns with the same screen still
;   up, and its push is a copy of a menu nobody left. Four of those reach
;   NAV_DEPTH_MAX and nav_drop_oldest discards the genuine ancestors.
;
; menu.s already said the flags decide - "a menu entry that opens a submenu
; and one that runs a test need different treatment, and the flags say which
; is which" - and menu_handler already returned them in B, which this
; discarded.
;
; So: an entry flagged SVC_BACK is never pushed for, because it exists to
; pop. Everything else is pushed for and the push is TAKEN BACK if the
; handler left the same screen up, which is the mechanical test for "nothing
; was opened" and needs no flag on every screen-opening entry in the tree.
menu_key_run
                clr     >menu_armed
                lbsr    menu_handler            ; X = the handler, B = flags
                pshs    x                       ; 3,s from here on
                bitb    #SVC_BACK
                bne     menu_key_run_leave

                pshs    b                       ; 2,s the flags, which the
                                                ; call below does not preserve
                ldx     >screen_handler         ; the screen showing now
                pshs    x                       ; 0,s
                lbsr    nav_push                ; remember this menu, so
                ldx     3,s                     ; whatever the handler opens
                jsr     ,x                      ; can come back to it

                ; A SUBMENU ALWAYS OPENED, and the handler comparison below
                ; cannot see it: every menu in this firmware installs
                ; menu_key, so screen_handler is the SAME address before and
                ; after one opens - the push was undone every time and the
                ; level was lost. Service -> Diagnostics left nav_top at zero,
                ; so Back from Diagnostics went to the Main Selection instead
                ; of the Service menu, skipping the level the operator came
                ; through. menu.s already said the flags decide; SVC_SUBMENU
                ; is the flag, and menu_draw already marks these entries with
                ; a '>' on the strength of it.
                ldb     2,s
                bitb    #SVC_SUBMENU
                bne     menu_key_run_opened

                ldx     >screen_handler
                cmpx    ,s                      ; did anything else open?
                bne     menu_key_run_opened
                lbsr    nav_undo_push           ; no: the operator never left
menu_key_run_opened
                leas    3,s
                puls    x
                rts

menu_key_run_leave
                puls    x                       ; Back: no push at all
                jsr     ,x
                rts
menu_key_ignore
                clr     >menu_armed             ; any other key cancels, so a
                                                ; mis-press cannot leave it
                                                ; armed for the next one
                pshs    b                       ; and the title goes back over
                lbsr    menu_draw               ; the prompt, which is how the
                puls    b                       ; operator sees it was cancelled
                lbra    key_refuse              ; AND IT IS REFUSED, not
                                                ; silently swallowed. A key
                                                ; that does nothing on this
                                                ; menu is indistinguishable
                                                ; from a key whose contact has
                                                ; failed unless something
                                                ; says so; the stock beeps
                                                ; through error_report_beep
                                                ; ($C3FE). See key_refuse.


; ---------------------------------------------------------------------------
; screen_dismiss - the key handler for a screen that only reports
;
;   entry: B = the key code
;   uses:  A, B, X, Y
;
; ANY key returns to the menu the screen was opened from. That is the whole
; behaviour, and it is right for every screen that shows something and takes
; no input: a ROM checksum result, an options list, a firmware revision.
;
; Any key, not a particular one. An operator who has read a result presses
; something to get on with their work, and a screen that answers only to one
; key they have to find is a screen they get stuck on. There is nothing to
; lose by leaving - the screen holds no unsaved state, or it would not be
; using this handler.
;
; One routine rather than one per screen. Fifteen screens report and take no
; input; fifteen copies of "any key goes back" is fifteen chances for one of
; them to answer only to ENTER and strand somebody.
; ---------------------------------------------------------------------------
screen_dismiss
                lbra    service_back_handler

; ---------------------------------------------------------------------------
; screen_take_dismiss - install screen_dismiss, for a reporting screen
;
;   uses:  X
;
; A single call a reporting screen makes as it paints. It exists so the screen
; does not carry the two lines - load the address, call install - which is
; exactly the kind of pair one screen eventually writes only half of.
; ---------------------------------------------------------------------------
screen_take_dismiss
                ldx     #screen_dismiss
                lbra    screen_install
