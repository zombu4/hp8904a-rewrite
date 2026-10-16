; ===========================================================================
; service_prompts.s - what line 1 says while a destructive menu entry is armed
;
; The first press of a destructive entry arms it and the second runs it, and
; the arming press used to repaint the same eighty characters: on the
; instrument it read as a key that did nothing. The architect found it on the
; bench 2026-09-17 and ruled that the confirmation stays and shows itself.
;
; THE SHAPE IS THE STOCK'S. Its serial-installation screen says what the next
; press will do on a line of its own - "Press SHIFT \x02 to install S/N =
; .  " at a2u13_page3.bin $27D2 - so a whole line, not the field marker glyph
; $07 that set_field_marker_at_column ($C855) writes, which marks an armed
; FIELD where this is an armed ACTION.
;
; THE LINE IS BUILT, NOT STORED. Eleven forty-column lines are 440 bytes and
; the modulation harness - this firmware plus its own test code in one 32K
; image - overflowed by 132 when they were. The pieces below are 73 bytes and
; the entry supplies its own name: what the operator reads is the same, and
; the name cannot drift from the entry it belongs to.
;
; A menu with destructive entries points menu_prompt at its callback - the
; diagnostics menu's, since the options menu left for page 3; menu.s menu_draw calls it with B = the selected entry when
; menu_armed is set, and the callback paints line 1.
; ===========================================================================

PROMPT_VERB     equ     MENU_TITLE_LINE+15      ; after "Press ENTER to "
PROMPT_NAME     equ     MENU_TITLE_LINE+19      ; after "run "

prompt_lead     fcc     "Press ENTER to "
PROMPT_LEAD_LEN equ     15
prompt_run      fcc     "run "
PROMPT_RUN_LEN  equ     4

; ---------------------------------------------------------------------------
; prompt_lead_out - blank line 1 and write "Press ENTER to "
;
;   uses:  A, B, X
; ---------------------------------------------------------------------------
prompt_lead_out
                lda     #MENU_TITLE_LINE
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_blank
                lda     #MENU_TITLE_LINE
                ldx     #prompt_lead
                ldb     #PROMPT_LEAD_LEN
                lbra    lcd_write

; ---------------------------------------------------------------------------
; diag_prompt - the Diagnostics menu's armed line
;
;   entry: B = the selected entry
;   uses:  A, B, X
;
; "Press ENTER to run " and then the entry's own name, which is the label up
; to the two spaces that end its first column - "RAM Test", "Memory Map
; Access", "Manual CowChip". The five plain entries and Back never reach
; here: menu_draw only asks while menu_armed is set, and only a destructive
; entry can set it.
; ---------------------------------------------------------------------------
diag_prompt
                lbsr    prompt_lead_out
                lda     #PROMPT_VERB
                ldx     #prompt_run
                ldb     #PROMPT_RUN_LEN
                lbsr    lcd_write
                lbsr    menu_entry_address      ; X = the selected record
                pshs    x
                lbsr    prompt_name_len         ; B = its name's length
                puls    x
                lda     #PROMPT_NAME
                lbra    lcd_write

; ---------------------------------------------------------------------------
; prompt_name_len - how much of a label is the entry's name
;
;   entry: X = the label
;   exit:  B = the characters before its first two spaces, at most 20
;   uses:  A, B
;
; The labels are one column of name and one of description, two spaces apart:
; "RAM Test    DESTROYS scratch, not cal.  ". A single space is part of the
; name, which is why the test is for two.
; ---------------------------------------------------------------------------
prompt_name_len
                clrb
prompt_name_next
                cmpb    #20
                bhs     prompt_name_done
                lda     b,x
                cmpa    #' '
                bne     prompt_name_step
                pshs    b
                incb
                lda     b,x
                puls    b
                cmpa    #' '
                beq     prompt_name_done
prompt_name_step
                incb
                bra     prompt_name_next
prompt_name_done
                rts


; ===========================================================================
; The banner's walking star. The architect asked for it on the instrument
; 2026-09-17: the stars stay in their columns and ONE of them goes dark, the
; dark one stepping inward from both ends together, half a second a step.
;
; IT IS AN ADDITION, NOT A PORT. No stock screen animates, and it is on this
; firmware's OWN banners only - SERVICE MENU, DIAGNOSTICS, BUS ADDRESS and
; SERVICE REQUEST MASK, five stars each end. The two banners the instrument
; itself owns, its Main Selection Level and its last-error screen, are left
; exactly as the ROM has them: the differential harness compares the display
; against the instrument's, and those two lines are the instrument's.
;
; THE TIME COMES OFF TIMER 1's FLAG, the same millisecond backlight_tick
; counts, and it is counted in the same place so the flag is consumed once.
; ===========================================================================

; HALF A SECOND, IN TIMER 1's FLAGS, WHICH ARE NOT MILLISECONDS. Its latch is
; $00D2 with no divide-by-eight, so a flag is 211 Enable clocks - an eighth of
; the millisecond timer 3 counts with the prescaler, 125 microseconds - and
; four thousand of them are the half second. Measured 2026-09-17: at 500 the
; star stepped every 60 ms.
; AND THE LOOP DOES NOT SEE EVERY FLAG. It is polled once a pass, so a pass
; longer than 125 us misses one: four thousand flags measured 673 ms rather
; than 500. Three thousand lands at about a half second with the foreground
; doing what it does on a menu; it is a display effect, and the jitter is not
; something an operator can see.
STAR_STEP_MS    equ     3000
banner_star_ch  fcc     "*"
banner_gap_ch   fcc     " "

; ---------------------------------------------------------------------------
; banner_arm - this screen's line 1 is one of ours: animate its stars
;
;   entry: X = the forty-column title
;   uses:  A, B
;
; Counts the stars the title opens with and takes them as the count at each
; end; a title that does not open with one is not animated, which is how any
; line that is not one of ours opts out by construction.
; ---------------------------------------------------------------------------
banner_arm
                clr     >banner_stars
                clrb
banner_arm_count
                lda     b,x
                cmpa    #$2A                    ; '*', as a number: the two
                                                ; assemblers do not agree on a
                                                ; star in quotes
                bne     banner_arm_done
                incb
                cmpb    #6                      ; ours are five; anything
                blo     banner_arm_count        ; longer is not one of ours
                rts
banner_arm_done
                cmpb    #$05                    ; FIVE AND NO OTHER COUNT. The
                bne     banner_arm_out          ; instrument's own banners open
                stb     >banner_stars           ; with one or two stars and are
                clr     >star_frame             ; left alone
                ldd     #STAR_STEP_MS
                std     >star_ms
banner_arm_out
                rts

; ---------------------------------------------------------------------------
; banner_tick - one flag of the banner's step
;
;   exit:  carry SET when half a second has just gone, which display_tick
;          counts the backlight's seconds by
;   uses:  A, B, X
;
; Called from the one place timer 1's flag is consumed. Two characters are
; written when the step comes round - the star coming back on and the next
; one going off - and nothing at all in between.
; ---------------------------------------------------------------------------
banner_tick
                ldx     >star_ms                ; THE HALF SECOND IS COUNTED
                leax    -1,x                    ; WHETHER OR NOT A BANNER IS
                stx     >star_ms                ; UP, because display_tick
                bne     banner_tick_none        ; counts the backlight's
                ldd     #STAR_STEP_MS           ; seconds by it
                std     >star_ms
                lda     >banner_stars
                beq     banner_tick_half        ; no banner of ours up
                lda     >menu_line1             ; an armed entry's prompt has
                bne     banner_tick_half        ; taken line 1: leave it alone
                lda     >star_frame             ; the one that was dark comes
                cmpa    >banner_stars           ; back, unless the frame just
                beq     banner_tick_step        ; gone was the all-lit one
                ldx     #banner_star_ch
                lbsr    banner_put
banner_tick_step
                lda     >star_frame
                inca
                cmpa    >banner_stars
                bls     banner_tick_set
                clra                            ; past the innermost: round
banner_tick_set                                 ; again from the outside
                sta     >star_frame
                cmpa    >banner_stars
                beq     banner_tick_done        ; the all-lit frame
                ldx     #banner_gap_ch
                lbsr    banner_put
banner_tick_half
                orcc    #CC_CARRY               ; a half second has gone
                rts
banner_tick_none
                andcc   #~CC_CARRY
                rts
banner_tick_done
                orcc    #CC_CARRY               ; the star moved, so it has
                rts

; ---------------------------------------------------------------------------
; banner_put - write one character at star_frame's two columns
;
;   entry: X = the character
;   uses:  A, B, X
; ---------------------------------------------------------------------------
banner_put
                pshs    x
                lda     >star_frame             ; the left one
                adda    #MENU_TITLE_LINE
                ldb     #$01
                lbsr    lcd_write
                puls    x
                lda     #39                     ; and its mirror
                suba    >star_frame
                adda    #MENU_TITLE_LINE
                ldb     #$01
                lbra    lcd_write

; ---------------------------------------------------------------------------
; menu_hooks_apply - a menu's annotate and prompt callbacks, from its table
;
;   entry: X = the entry table menu_open was given
;   uses:  A, B, X, Y
;
; THEY BELONG TO THE MENU, NOT TO THE ROUTE IN. Each opener used to install
; its own after menu_open, which works until the operator goes down into a
; screen and comes back: service_back_handler reopens the menu from the nav
; stack, which carries the table, the title and the count and nothing else, so
; the callbacks were lost and the Display Backlight menu came back with its
; value column blank (driven 2026-09-17). Looking them up from the table fixes
; every route in at once, including that one.
; ---------------------------------------------------------------------------
menu_hooks_apply
                ; WRITTEN OUT RATHER THAN TABLE-DRIVEN, so the stack scanner
                ; can see what these cells hold: it resolves an indirect call
                ; by walking back to an `ldx #name` and a `stx >cell`, and a
                ; table of fdb rows read with `ldd 2,y` tells it nothing.
                cmpx    #diagnostics_menu_entries
                beq     menu_hooks_diag
                cmpx    #backlight_menu_entries
                beq     menu_hooks_backlight
                rts                             ; a menu with neither
menu_hooks_diag
                pshs    x
                ldx     #diag_prompt
                stx     >menu_prompt
                puls    x
                rts
menu_hooks_backlight
                pshs    x
                ldx     #backlight_annotate
                stx     >menu_annotate
                puls    x
                rts
                fdb     $0000
