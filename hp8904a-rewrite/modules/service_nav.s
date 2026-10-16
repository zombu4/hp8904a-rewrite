; ===========================================================================
; service_nav.s - moving between menus, and leaving them
;
; A menu stack, so a submenu knows where it came from. Two entries deep,
; which is what the menu tree actually needs: service -> options, or
; service -> diagnostics. Deeper nesting is not offered, because a service
; menu a person gets lost in is a service menu they stop using.
;
; service_exit and service_back were the last two menu roles left without a
; routine behind them, and they are filled here. Every entry in every menu now
; reaches real code, and tests/test_menu_complete.py resolves each one through
; its alias chain to a label the tree defines, so an entry that stops pointing
; at anything is refused rather than merely pressed and ignored.
; ===========================================================================

NAV_DEPTH       equ     2               ; service -> one submenu

; ---------------------------------------------------------------------------
; nav_reset - start at the top with an empty stack
;
;   uses:  A
; ---------------------------------------------------------------------------
nav_reset
                clr     >nav_top
                rts

; ---------------------------------------------------------------------------
; THERE IS A NAV STACK AGAIN, and the reason is worth recording because it
; was deliberately deleted once.
;
; It went when the menu tree was two levels deep - service menu, one submenu -
; and with only one place "back" could go, a stack that could be wrong was
; worse than no stack at all. That reasoning was right for that tree.
;
; The tree is now three deep: Main Selection Level, then the service menu or
; a mode, then a submenu or a screen. service_back_handler went to the
; service menu unconditionally, so LOCAL from the Channel Configuration
; screen - which is reached from the MAIN menu and has nothing to do with
; service - landed the operator in the service menu. That is not a wrong
; screen so much as a wrong idea about where they were.
;
; A menu is three things: its table, its count and its title. The stack holds
; those, not a routine address, because reopening a menu means redrawing it
; from the same three values and a routine address would need one routine per
; menu to point at.
;
; FOUR DEEP, which is one more than the tree needs. Overflowing DROPS THE
; OLDEST entry rather than refusing to descend: an operator who somehow gets
; five deep should lose the memory of where they started, not the ability to
; go further. Nothing here can strand them either way - LOCAL at the bottom
; opens the Main Selection Level.
; ---------------------------------------------------------------------------
NAV_ENTRY       equ     5               ; table, title, count
NAV_DEPTH_MAX   equ     4
NAV_SHUFFLE     equ     15              ; (NAV_DEPTH_MAX-1) * NAV_ENTRY,
                                        ; spelled out because this
                                        ; assembler takes a symbol or a
                                        ; number in an immediate, not an
                                        ; expression in parentheses

; ---------------------------------------------------------------------------
; nav_undo_push - take back the most recent nav_push
;
;   uses:  A
;
; menu_key_run pushes the menu before running an entry's handler, because it
; cannot know in advance whether the handler will open something. An entry
; that only toggles a setting returns with the same screen still up, and the
; push it caused would otherwise be a copy of the menu the operator never
; left - four of them fill NAV_DEPTH_MAX and nav_drop_oldest then throws away
; the real ancestors, so the way back is lost rather than merely lengthened.
;
; Clamped at zero rather than decremented blindly. nav_top indexes the stack
; as nav_top * NAV_ENTRY with no bound, and this repository has already had
; one uncleared nav_top put a write onto the serial number.
; ---------------------------------------------------------------------------
nav_undo_push
                lda     >nav_top
                beq     nav_undo_push_done
                deca
                sta     >nav_top
nav_undo_push_done
                rts

; ---------------------------------------------------------------------------
; nav_push - remember the menu being left
;
;   uses:  A, B, X, Y
;
; Called by menu_key before it runs an entry's handler, so whatever that
; handler opens can come back here.
; ---------------------------------------------------------------------------
nav_push
                ; CLAMP, do not merely decrement.
                ;
                ; This tested for full and called nav_drop_oldest, which does
                ; ONE `dec nav_top` - so a depth that was already far past
                ; four came back one less and still past four, and the index
                ; below is nav_top * 5 with no bound. nav_top is a byte of
                ; battery-backed RAM that reset_entry never cleared, so a
                ; power-on with $8A in it put the write at
                ; $3D50 + 138*5 = $3FFD - THE SERIAL NUMBER - and the byte
                ; after it landed on $4000, the page-select register.
                ;
                ; It was reachable on the operator's first keystroke: ENTER
                ; on any menu entry pushes. It was reproduced on the emulator
                ; with nav_top = 138, and the three serial bytes came back
                ; holding the menu table pointer.
                ;
                ; So the depth is FORCED into range before it is used, and
                ; nav_reset now runs at power-on as well. Two guards for one
                ; fault, deliberately: this is the fault the owner's standing
                ; rule about the serial and the options exists to prevent.
                lda     >nav_top
                cmpa    #NAV_DEPTH_MAX
                blo     nav_push_room
                lda     #NAV_DEPTH_MAX          ; clamp to FULL, not to the
                sta     >nav_top                ; deepest usable slot:
                lbsr    nav_drop_oldest         ; nav_drop_oldest does its own
                lda     >nav_top                ; `deca` on the way out, so
                                                ; clamping to NAV_DEPTH_MAX-1
                                                ; first left nav_top at 2 and
                                                ; the stack one entry short of
                                                ; the four it holds. Clamping
                                                ; to four means the shuffle
                                                ; brings it to three, the
                                                ; deepest slot, which is what
                                                ; the line below then uses.
nav_push_room
                ldb     #NAV_ENTRY
                mul                             ; D = depth * 5
                ldx     #nav_stack
                leax    d,x

                ldy     >menu_table
                sty     ,x
                ldy     >menu_title
                sty     2,x
                lda     >menu_count
                sta     4,x

                inc     >nav_top
                rts

; ---------------------------------------------------------------------------
; nav_drop_oldest - discard the deepest ancestor to make room
;
;   uses:  A, B, X, Y
;
; Shuffles the stack down by one entry. It is called only when the stack is
; full, which the tree does not do - it exists so that overflowing loses
; history rather than losing the ability to descend.
; ---------------------------------------------------------------------------
nav_drop_oldest
                ldx     #nav_stack
                ldy     #nav_stack+NAV_ENTRY
                ldb     #NAV_SHUFFLE
nav_drop_byte
                lda     ,y+
                sta     ,x+
                decb
                bne     nav_drop_byte
                lda     >nav_top                ; leave room for one more,
                beq     nav_drop_done           ; and never below zero
                deca
                sta     >nav_top
nav_drop_done
                rts

; ---------------------------------------------------------------------------
; service_back_handler - go back one level
;
;   uses:  A, B, X, Y
;
; Pops the menu that was left and redraws it. With nothing on the stack it
; opens the Main Selection Level, which is the top of the tree and the one
; screen an operator can always get to.
;
; It is called from three places: the Back entry of every submenu, the LOCAL
; key on any screen (handled in the foreground so no screen can withhold it),
; and screen_dismiss.
; ---------------------------------------------------------------------------
service_back_handler
                lda     >nav_top
                beq     service_back_top
                deca
                sta     >nav_top

                ldb     #NAV_ENTRY
                mul                             ; D = depth * 5
                ldx     #nav_stack
                leax    d,x

                ldy     2,x                     ; the title
                ldb     4,x                     ; the count
                ldx     ,x                      ; the table
                lbra    menu_open_no_push
service_back_top
                lbra    main_menu_open

; ---------------------------------------------------------------------------
; service_exit_handler - leave the menus entirely
;
;   uses:  A, B, X
;
; Empties the stack and returns to the Main Selection Level. It is the Exit
; entry, and it differs from Back by going all the way up rather than one
; level.
; ---------------------------------------------------------------------------
service_exit_handler
                lbsr    nav_reset
                lbra    main_menu_open
