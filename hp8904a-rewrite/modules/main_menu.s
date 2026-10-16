; ===========================================================================
; main_menu.s - the Main Selection Level: every mode the instrument has
;
; THERE ARE NO ACCESS CODES AND NO SPECIAL-FUNCTION NUMBERS IN THIS FIRMWARE.
; Every entry below is reachable from a cold start by anyone who can read the
; screen, and every one says what it does.
;
; That is a deliberate departure from the stock firmware, and it is worth
; setting out exactly what was behind the locks, because "hidden menus"
; sounds like more than it was:
;
;   the six digits 092448, typed on the Special Functions screen, unlocked
;   ONE menu record - the fourth - carrying "Manual Memory" and "Manual
;   CowChip". Those are the two low-level hardware pokes, and they are the
;   two most useful things on a bench.
;
;   three more numbers were compared literally, with no table and no menu
;   entry anywhere: 48 opened option install, 37 listed the options, and 87
;   opened serial-number install. An operator with a replacement battery and
;   no service note could not find any of them, and the serial number is not
;   printed anywhere the firmware can reach.
;
; So the locks protected nothing an owner should not have, and they cost
; exactly what locks like that always cost: a flat battery turned into a
; board replacement, because the screen that re-enters the serial could not
; be found without a document nobody had.
;
; Nothing is destroyed by opening them. The entries that change stored state
; are marked SVC_DESTRUCTIVE and say so in their own label, which is a better
; guard than a number, because it is a guard the operator can read.
;
; THE MODE LIST IS THE STOCK ONE. It was not invented: the stock firmware
; installs a screen handler in eight places, and those eight are Main
; Selection Level, Channel Configuration, Tone Sequence, DTMF Sequence,
; Digital Sequence, Diagnostics, Memory Map Access and Manual CowChip, with
; four more screens installed on a second vector - Output On/Off, Output
; Float, Filter Select and Save/Recall. Every one of them appears below.
;
; WHAT IS OPTION-GATED, AND WHEN. build_option_dispatch_table ($8939) runs ONCE,
; from foreground_main_loop ($8492) after power_on_init: with bit 0 of
; installed_options set it copies the page limit into $2223 and the eight mode
; vectors into slots 2-9 of $2224; with it clear it zeroes $2223 and puts the
; the do-nothing routine $C239 in all eight. So the pager cannot leave record 0, and
; option_feature_enter ($8AEA) calls nothing for slots 2-9 - silently. And it
; is LATCHED: an options byte changed afterwards - ST_ID clears $3FFC - changes
; nothing until the next power-on. main_menu_latch is that routine here.
;
; THIS USED TO READ THE OPTIONS LIVE AT EVERY OPEN, gate Digital Sequence on
; Option 003 rather than bit 0, and refuse with an error and a repaint. The
; differential harness found it, seed 11 step 13: after `ST_ID 190;` the
; instrument still opened Digital Sequence and this firmware sat on the Main
; Selection Level.
; ===========================================================================

; ===========================================================================
; THE SCREEN ITSELF - the stock's pager, not a list
;
; The instrument's Main Selection Level is a BANNER and ONE RECORD, paged with
; NEXT and LAST and chosen with f1 and f3. It is not a scrolling list and it
; has no cursor: lcd_init sends display-control $0C, cursor and blink off, and
; nothing on this screen changes $242A. What the operator aims at is the
; softkey glyph printed in the record.
;
; The records are the stock's own forty bytes each, dumped from
; firmware/a2u13_page0.bin at $4053, $407B, $40A3, $40CB and $40F3 - five
; records of two twenty-byte halves, each half a glyph pair and eighteen
; characters. `fcb $00,$01` is not a marker: character $00 is a lower-case f
; and $01 to $04 are the digits, all with row 7 set, so the pair renders as an
; underlined f1 and $00,$03 as an underlined f3. lcd_init loads them into CGRAM
; from $EA15, and modules/lcd.s:lcd_glyphs carries the same eight patterns.
;
; THIS FIRMWARE HAD A FIFTEEN-ENTRY SCROLLING MENU with UP, DOWN and ENTER, and
; every service screen on it. That is not what the instrument does with any of
; them: Save and Recall are shifted UP and DOWN, Special Functions is shifted
; LAST, the diagnostics are shifted f1, Output On/Off, Output Float and Filter
; Select are shifted PHASE, FREQ and AMPL, and Memory Map and Manual CowChip
; are two softkeys inside the diagnostics menu. docs/stock-screen-routes.md
; carries the reading that established each one, key code by key code, out of
; key_action_table_head ($EF4A) and the message table d8f2a ($8F2A).
;
; TWO RECORDS ARE THIS FIRMWARE'S OWN, and they are the two the instrument
; leaves blank. $40CB and $40F3 exist in the stock ROM carrying nothing but
; their glyph pairs and thirty-six spaces, because build_option_dispatch_table
; ($8939) caps the page counter at the $4003 header byte, $02. Record 3 here
; carries the FM Stereo screen the architect ordered and the channel summary,
; neither of which the instrument has anywhere - so an operator sees four pages
; where the instrument shows three, and that difference is the price of
; reaching a screen the instrument has no key for. Record 4 stays blank and
; unreachable, as it is on the instrument.
; ===========================================================================

main_menu_banner
                fcc     "*    HP 8904A  Main Selection Level    *"

MAIN_RECORD     equ     40              ; forty characters, one LCD line
MAIN_PAGE_LAST  equ     3               ; the highest page NEXT reaches with
                                        ; Option 001 at power-on. The stock's
                                        ; is 2, from $4003; record 3 is the
                                        ; FM stereo the owner added
MAIN_SLOTS      equ     10              ; two per record, five records - the
                                        ; stock's $2224-$2237 exactly, which is
                                        ; what the bus's GM command indexes

main_menu_records
                fcb     $00,$01
                fcc     " Channel Config.                      "
                fcb     $00,$01
                fcc     " Tone Sequence    "
                fcb     $00,$03
                fcc     " DTMF Sequence    "
                fcb     $00,$01
                fcc     " Digital Sequence                     "
                fcb     $00,$01
                fcc     " FM Stereo        "
                fcb     $00,$03
                fcc     " Channel Summary  "
                fcb     $00,$01
                fcc     "                  "
                fcb     $00,$03
                fcc     "                  "

; The ten item vectors, in the stock's own order: f1 then f3 of each record.
; An EMPTY SLOT IS A ZERO and nothing is called - the stock keeps $C239 in one
; and option_feature_enter ($8AEA) refuses a slot still holding it, so f3 on
; the Channel Config. page does nothing at all rather than raising anything.
main_menu_vectors
                fdb     mode_channel_config     ; record 0, f1
                fdb     0                       ; record 0, f3 - empty
                fdb     mode_tone_sequence      ; record 1, f1
                fdb     mode_dtmf_sequence      ; record 1, f3
                fdb     mode_digital_sequence   ; record 2, f1
                fdb     0                       ; record 2, f3 - empty
                fdb     mode_stereo             ; record 3, f1 - this
                fdb     mode_channel_summary    ; record 3, f3 - firmware's own
                fdb     0                       ; record 4, blank on the
                fdb     0                       ; instrument and blank here

; ---------------------------------------------------------------------------
; main_menu_open - show the Main Selection Level from its first page
;
;   uses:  A, B, X, Y
;
; The screen the instrument returns to from everywhere else, and the one it
; shows after the identification banner at power-on. enter_paged_menu_mode
; ($8D23) clears the page counter every time, which is why NEXT-ing to Digital
; Sequence and leaving brings you back to Channel Config. rather than to where
; you were.
; ---------------------------------------------------------------------------
main_menu_open
                ; THE MODE BEING LEFT GETS ITS SAY FIRST. Every stock arm
                ; that returns here - [3] state_return_to_main_menu ($8E22),
                ; [5] show_id_screen_then_main_menu ($8DAD), [6]
                ; event7_return_to_main_menu ($8D8C) and [10]
                ; return_to_main_menu ($8E62) - calls
                ; call_installed_handler_220f on the vector at $2213 BEFORE
                ; enter_paged_menu_mode ($8D23). This firmware had no such
                ; vector at all, so a mode that has to undo something as the
                ; operator walks out of it could not: leaving Channel
                ; Configuration left all four channels routed and sounding
                ; where the instrument parks them. Driven side by side,
                ; leaving that mode: the stock reads levels (0,0,0,0),
                ; destinations (10,10,10,10) and latches ($04 on all four),
                ; and this firmware read 1879, 0C-0F and $00.
                ;
                ; It is cleared as it is called, so it fires once. A mode
                ; installs it as it opens; screen_install does not clear it,
                ; because a mode is a CHAIN of screens and stepping from the
                ; title record to ch A must not throw the mode's exit away.
                ;
                ; TWO ARMS CANNOT USE IT FROM HERE, and that is why the body
                ; is a routine of its own below. Arms [5] and [6] reset the
                ; outputs on the way back, and they run the vector BEFORE the
                ; reset, not after: calling it from here would run it after
                ; instrument_preset has parked every destination, and a
                ; callback whose whole job is to dismantle a routing finds
                ; none left to dismantle. Both of those call screen_exit_run
                ; themselves and reach here with the vector already cleared.
                lbsr    screen_exit_run
                ; AND THE MAIN SELECTION IS THE ACTIVE MODE NOW, which is what
                ; enter_paged_menu_mode ($8D23) records: LDD #$8D23 / STD
                ; >$24E6, its own address, beside the CLR $2245 below. After
                ; the teardown, in the stock's order, so a mode being left is
                ; torn down before anything names its successor.
                ldx     #main_menu_open
                stx     >active_mode
                clr     >main_menu_page         ; $8D23's CLR $2245
                ldx     #main_menu_key
                lbsr    screen_install
                lbra    main_menu_show

; ---------------------------------------------------------------------------
; screen_exit_run - give the mode being left its say, once
;
;   uses:  A, B, X, Y, U - whatever the installed callback uses
;
; call_installed_handler_220f ($8F6E), which is three instructions on the
; stock: LDX >$2213 / JSR ,x / RTS. The clearing is this firmware's, and it
; is what makes the callback fire once rather than on every return until a
; mode installs a different one.
;
; THE ORDER IT IS CALLED IN IS THE POINT. $8D8C and $8DAD - 'PS;' and shifted
; BACKSPACE, the two arms that reset the outputs - run it FIRST and
; reset_all_channel_outputs ($80F3) second. Driven on the stock 2026-09-13,
; 'PS;' from Channel Configuration with an amplitude on channel A: the vector
; wrote eighty words to the synthesis port before $80F3 wrote one, twenty a
; channel, tearing down each channel's routing. This firmware called
; channel_reset_all first and reached the vector through main_menu_open
; afterwards, by which time dds_reset had parked every routed_dest at LBL_OFF
; and channel_mode_exit had nothing to do: eighty words became none.
; ---------------------------------------------------------------------------
screen_exit_run
                ldx     >screen_exit
                beq     screen_exit_none
                clr     >screen_exit            ; once, and not again until a
                clr     >screen_exit+1          ; mode installs another
                jmp     ,x                      ; its RTS is this one's
screen_exit_none
                rts

; ---------------------------------------------------------------------------
; main_menu_show - the banner and the page's record
;
;   uses:  A, B, X
; ---------------------------------------------------------------------------
main_menu_show
                lda     #LCD_LINE1
                ldx     #main_menu_banner
                ldb     #MAIN_RECORD
                lbsr    lcd_write

                lda     >main_menu_page
                ldb     #MAIN_RECORD
                mul
                ldx     #main_menu_records
                leax    d,x
                lda     #LCD_LINE2
                ldb     #MAIN_RECORD
                lbra    lcd_write

; ---------------------------------------------------------------------------
; main_menu_key - the Main Selection Level's keys
;
;   entry: B = the key code
;   uses:  A, B, X, Y, U
;
; main_selection_level_handler ($8C14), arm for arm:
;
;   NEXT $0017   l8c5e: at the limit it wraps to 0, else +1, then repaint
;   LAST $0018   l8c83: at 0 it wraps to the limit, else -1, then repaint
;   f1   $0013   l8c2d: $2219 = $2243, post $000A
;   f3   $0015   l8c47: $2219 = $2244, post $000A
;   f2   $0014   l8c44, accepted and discarded, with f4 and $0001 and $003C
;   shift+INC SET $0010   l8c20: show_last_error_screen ($C418)
;   anything else         l8caa: error $0F, "Un-executable command"
;
; SHIFT ITSELF IS NOT A KEY HERE. kbd_decode returns its code so the Keyboard
; Check can name it, and the stock posts no message for it - driven 2026-09-11,
; SHIFT alone on the Main Selection leaves $23DE at zero while DOWN, which this
; screen does not use, puts $0F there.
;
; Shifted LAST is Special Functions, and it is ANSWERED HERE rather than in the
; foreground because the instrument answers it here: invoke_page0_vector_4024
; ($8EDB) compares $220F against $8C14 and refuses with error $10, "Go to Main
; Selection Level for SPECIAL", on any other screen.
; ---------------------------------------------------------------------------
main_menu_key
                cmpb    #KEY_NEXT
                beq     main_menu_key_next
                cmpb    #KEY_LAST
                beq     main_menu_key_last
                cmpb    #KEY_F1
                beq     main_menu_key_f1
                cmpb    #KEY_F3
                beq     main_menu_key_f3
                cmpb    #KEY_F2                 ; accepted and discarded, as
                beq     main_menu_key_none      ; l8c44 does
                cmpb    #KEY_F4
                beq     main_menu_key_none
                cmpb    #KEY_SHIFT              ; the latch, not a key
                beq     main_menu_key_none
                cmpb    #KEY_S_INC_SET
                lbeq    error_show              ; the three-second flash
                cmpb    #KEY_S_LAST
                beq     main_menu_key_special
                lbra    key_refuse              ; $0F
main_menu_key_none
                rts

main_menu_key_next
                lda     >main_menu_page         ; $8C5E: CMPB >$2223, the
                cmpa    >main_menu_limit        ; limit latched at power-on
                bhs     main_menu_key_first     ; at the limit: wrap
                inca
                bra     main_menu_key_page
main_menu_key_first
                clra
                bra     main_menu_key_page
main_menu_key_last
                lda     >main_menu_page
                bne     main_menu_key_back
                lda     >main_menu_limit        ; $8C8C: at 0, the limit
                bra     main_menu_key_page
main_menu_key_back
                deca
main_menu_key_page
                sta     >main_menu_page
                lbra    main_menu_show

main_menu_key_f1
                lda     >main_menu_page         ; slot = page * 2
                lsla
                bra     main_menu_enter
main_menu_key_f3
                lda     >main_menu_page
                lsla
                inca
main_menu_enter
                lbra    main_menu_slot

main_menu_key_special
                lbra    mode_special_functions

; ---------------------------------------------------------------------------
; main_menu_slot - open the item in one of the ten slots
;
;   entry: A = the slot, 0 to MAIN_SLOTS-1
;   uses:  A, B, X, Y, U
;
; option_feature_enter ($8AEA): bound the index, fetch the vector, and call
; nothing at all if the slot is empty - or if it is one of the eight
; build_option_dispatch_table ($8939) stubbed with $C239, which is slots 2-9
; when Option 001 was not fitted at power-on. main_menu_limit is zero exactly
; then. The bus's GM command reaches this with its own digit, which is why it
; takes a slot rather than a page and a softkey.
; ---------------------------------------------------------------------------
main_menu_slot
                cmpa    #MAIN_SLOTS
                bhs     main_menu_slot_none     ; out of the table
                cmpa    #2                      ; slots 0 and 1 are $4004 and
                blo     main_menu_slot_vector   ; $4006, copied unconditionally
                tst     >main_menu_limit        ; the other eight only with
                beq     main_menu_slot_none     ; Option 001 at power-on
main_menu_slot_vector
                lsla                            ; two bytes a vector
                ldx     #main_menu_vectors
                leax    a,x
                ldx     ,x
                beq     main_menu_slot_none     ; an empty slot calls nothing
                ; THE MODE BEING ENTERED IS RECORDED, as option_feature_enter
                ; records it at l8b1a: LDD 2,S / STD >$24E6, the incoming
                ; mode's entry routine, which is what a recall and a
                ; keep-state power-on call back through. Here and only here,
                ; because this is the one path every mode - panel or bus GM -
                ; is entered by.
                stx     >active_mode
                ldu     #MODE_COLD              ; AND ENTERED COLD: the entry
                jmp     ,x                      ; reason is 0 from the menu
main_menu_slot_none
                rts

; ---------------------------------------------------------------------------
; mode_reenterable - is this record a mode the instrument enters again
;
;   entry: X = a record: active_mode, or a register slot's copy of it
;   exit:  carry CLEAR if X is one of the four mode entries below,
;          carry SET if it is anything else
;   uses:  CC
;
; enter_handler_by_index ($F16A) and foreground_main_loop ($83A0) at l848d
; both call through the word as it stands. The instrument's only guard is the
; $C239 filler test at $F19E, which catches a slot never saved to. This
; firmware checks the word against the modes it has, because the word comes
; out of battery RAM: a register saved by a build before the record existed
; holds zero there, and so does a cold board.
;
; SIX. Four are the records measured on the instrument 2026-09-16 - Channel
; Configuration $528F, Tone Sequence $41CA, DTMF Sequence $41D1, Digital
; Sequence $41D8 (docs/mode-reentry.md). The other two are this firmware's
; own screens, FM Stereo and the Channel Summary, which the instrument has no
; record for; they re-enter by the architect's ruling of 2026-09-16
; - "a register saved on FM Stereo recalls to FM Stereo,
; same for Channel Summary". The Main Selection's own $8D23 is never a slot's
; record, because a save is refused there, and on a keep-state power-on the
; Main Selection is what boot.s opens when this refuses. ANYTHING ELSE - an
; older register with nothing recorded, a mode that no longer exists - is
; refused, and the operator stays where they are: the same ruling, and the
; instrument's own answer to a value it does not recognise.
; ---------------------------------------------------------------------------
mode_reenterable
                cmpx    #mode_channel_config
                beq     mode_reenterable_yes
                cmpx    #mode_tone_sequence
                beq     mode_reenterable_yes
                cmpx    #mode_dtmf_sequence
                beq     mode_reenterable_yes
                cmpx    #mode_digital_sequence
                beq     mode_reenterable_yes
                cmpx    #mode_stereo
                beq     mode_reenterable_yes
                cmpx    #mode_channel_summary
                beq     mode_reenterable_yes
                orcc    #CC_CARRY
                rts
mode_reenterable_yes
                andcc   #~CC_CARRY
                rts

; ---------------------------------------------------------------------------
; mode_reenter - enter the active mode again, for a reason
;
;   entry: B = MODE_RECALL or MODE_KEEP; the mode is active_mode
;   exit:  the mode has run, or nothing was called if active_mode is not a
;          mode mode_reenterable accepts. The caller decides that first with
;          mode_reenterable: on the entered path the flags are whatever the
;          mode left, so this returns no verdict of its own.
;   uses:  A, B, X, U, and then whatever the mode uses
;
; The instrument's two calls: enter_handler_by_index at $F1C3-$F1D6 selects
; page 0 and JSRs through the slot's word with argument 1, and
; foreground_main_loop at l848d does LDB #$02 ... LDX >$24E6 / JSR ,X. Each
; mode_* routine selects its own page through page_enter here, and the reason
; goes in U - see MODE_COLD in scratch.inc.
;
; THE CELL IS READ HERE, AND AGAIN RIGHT BEFORE THE JUMP. Both callers mean
; active_mode - a recall has just copied the slot's record into it - and a
; jump whose pointer is loaded from a named cell is one
; hp8904a-rewrite/tests/test_stack_depth.py can follow to every value any
; `stx >active_mode` stores, where a pointer handed in by the caller is not.
; The check stays even though both callers make it: a word out of battery RAM
; is never jumped to unchecked.
; ---------------------------------------------------------------------------
mode_reenter
                clra
                tfr     d,u                     ; U = the reason
                ldx     >active_mode
                bsr     mode_reenterable
                bcs     mode_reenter_refused
                ldx     >active_mode
                jmp     ,x
mode_reenter_refused
                rts

; ---------------------------------------------------------------------------
; main_menu_latch - decide once, at power-on, what the Main Selection Level offers
;
;   uses:  A, B
;
; build_option_dispatch_table ($8939), the one call foreground_main_loop makes
; at $8492 before its loop: $2223 gets the page limit when bit 0 of
; installed_options is set ($8942 ANDB #$01 / $8949 STB >$2223) and zero when
; it is not ($8951 CLR >$2223). Nothing re-runs it, so the menu an instrument
; boots with is the menu it keeps.
; ---------------------------------------------------------------------------
main_menu_latch
                ldb     #OPTION_001
                lbsr    option_test             ; Z set: the bit is clear
                beq     main_menu_latch_none
                lda     #MAIN_PAGE_LAST
                sta     >main_menu_limit
                rts
main_menu_latch_none
                clr     >main_menu_limit
                rts

; ---------------------------------------------------------------------------
; The mode entry points. None checks an option: the gate is the slot table,
; decided at power-on by main_menu_latch, exactly as the stock's vectors are.
; What a mode needs beyond that - a channel that is fitted, an option a single
; field depends on - is checked where it is used, in the paged screen.
; ---------------------------------------------------------------------------

; mode_tone_sequence - open the Tone Sequence mode
;
;   uses:  A, B, X, Y, U
; ---------------------------------------------------------------------------
mode_tone_sequence
                ldx     #mode_tone_exit         ; sequence_mode_init's
                stx     >screen_exit            ; LDD #$51E3 / STD >$2213
                lda     #PAGE_TONE_SEQUENCE
                lbra    page_enter

; mode_dtmf_sequence - open the DTMF Sequence mode
;
;   uses:  A, B, X, Y, U
; ---------------------------------------------------------------------------
mode_dtmf_sequence
                ldx     #mode_tone_exit         ; the same hook: both modes are
                stx     >screen_exit            ; sequence_mode_init's
                lda     #PAGE_DTMF_SEQUENCE     ; page 1's SECOND entry: it
                lbra    page_enter_second       ; carries both tone modes

; mode_digital_sequence - open the Digital Sequence mode
;
;   uses:  A, B, X, Y, U
; ---------------------------------------------------------------------------
mode_digital_sequence
                ldx     #mode_digital_exit      ; $735E's STD >$2213
                stx     >screen_exit
                lda     #PAGE_DIGITAL_SEQUENCE
                lbra    page_enter

; mode_tone_exit / mode_digital_exit - the exit hooks, run from A2U12
;
;   uses:  A, B, X, Y, U
;
; screen_exit_run calls these on the way back to the Main Selection, as
; return_to_main_menu ($8E62) calls $2213; each pages its mode in and runs the
; teardown there.
mode_tone_exit
                ldb     #PAGE_TONE_SEQUENCE     ; page_call takes the page in
                ldx     #PAGE1_MODE_EXIT        ; B - an A here called $400D on
                lbra    page_call               ; whatever page B last named
mode_digital_exit
                ldb     #PAGE_DIGITAL_SEQUENCE
                ldx     #PAGE2_MODE_EXIT
                lbra    page_call

; ---------------------------------------------------------------------------
; mode_enter_channel_config - Channel Configuration, opened from inside page 0
;
;   uses:  A, B, X, Y, U, and whatever the mode uses
;
; ABI slot 118. The Channel Summary's ENTER opens the full screen for the
; channel it shows, and that screen IS Channel Configuration, so it is entered
; the way the Main Selection enters it: recorded in active_mode as
; main_menu_slot records a mode, cold, and through mode_channel_config so its
; exit hook goes in. Without the record a register saved there carried the
; summary's, and since the summary re-enters by the architect's ruling of
; 2026-09-16 it would have recalled onto the summary.
; ---------------------------------------------------------------------------
mode_enter_channel_config
                ldx     #mode_channel_config
                stx     >active_mode
                ldu     #MODE_COLD
                lbra    mode_channel_config

; ---------------------------------------------------------------------------
; mode_channel_config - the instrument's main working screen
;
; No option check. A single-channel instrument still sets its channel's
; frequency, amplitude, phase and waveform on this screen, and refusing it
; for want of Option 001 would leave a working instrument with nothing to
; show. What the option actually gates is the DESTINATION field's modulation
; codes, and that is checked where the field is edited, in the paged screen.
; ---------------------------------------------------------------------------
mode_channel_config
                ; AND WHAT TO DO WHEN THE OPERATOR WALKS OUT AGAIN.
                ; enter_channel_config_mode ($528F) installs
                ; clear_all_destinations ($5253) as the exit callback at
                ; $2213 - LDD #$5253 / STD >$2213 at $54D1/$54D4 - and every
                ; return to the Main Selection Level runs it, which is how
                ; the instrument's four sockets go quiet and its relays open
                ; behind you. channel_mode_exit is that routine here.
                ldx     #channel_mode_exit
                stx     >screen_exit
                lda     #PAGE_CHANNEL_CONFIG
                lbra    page_enter

; ---------------------------------------------------------------------------
; mode_channel_summary - all four channels on one screen
;
;   uses:  A, B, X, Y, U
;
; The Channel Configuration screen shows one channel in full; this shows every
; channel's headline at once, which is the question an operator actually has
; when something is wrong: which of these is producing what.
; ---------------------------------------------------------------------------
mode_channel_summary
                lda     #PAGE_CHANNEL_CONFIG    ; page 0's third vector
                lbra    page_enter_third

; ---------------------------------------------------------------------------
; mode_stereo - open the FM stereo composite presets, page 0's fourth vector
;
;   uses:  A, B, X, Y, U
;
; An addition the owner ordered on 2026-09-02, not a port: see the header of
; page0_stereo.s.
; ---------------------------------------------------------------------------
mode_stereo
                lda     #PAGE_CHANNEL_CONFIG    ; page 0's fourth vector
                lbra    page_enter_fourth

; --- the modes A2U12 carries itself ---------------------------------------
;
; SIX ONE-LINE WRAPPERS ARE GONE FROM HERE, and what reaches each screen
; instead is the key the instrument reaches it with. They existed only to be
; menu entries, and the menu entries were this firmware's own:
;
;   mode_save_recall     -> register_screen_open, on shifted UP and shifted
;                           DOWN in modules/boot.s
;   mode_output_onoff    -> output_onoff_open, on shifted PHASE ($8EAC)
;   mode_output_float    -> output_float_open, on shifted FREQ ($8EBD)
;   mode_filter_select   -> filter_screen_open, on shifted AMPL ($8ECE)
;   mode_service         -> service_menu_open, on shifted f1 ($8E00)
;   mode_memory_map      -> memmap_open, which the diagnostics menu's own
;                           Memory Map Access entry already pointed at
;
; mode_hop_table went with them: the Hop Ram screens are records 5 and 6 of
; the Channel Configuration chain and NEXT walks onto them, which is where the
; instrument keeps them. Every one of these routes is read out of the ROM in
; docs/stock-screen-routes.md.
;
; mode_special_functions stays, because the Main Selection Level's own shifted
; LAST arm calls it and nothing else may - see main_menu_key.
;
; mode_special_functions - open Special Functions: the five preferences
;
;   uses:  A, B, X, Y, U
; ---------------------------------------------------------------------------
mode_special_functions
                lbra    special_screen_open

; mode_manual_cowchip - open Manual CowChip: write the synthesis chip directly
;
;   uses:  A, B, X, Y, U
; ---------------------------------------------------------------------------
mode_manual_cowchip
                lda     #PAGE_MANUAL_COWCHIP
                lbra    page_enter

; ---------------------------------------------------------------------------
; mode_hop_ram - what the synthesis chip's hop RAM actually holds
;
;   uses:  A, B, X, Y, U
;
; Page 3's second entry vector. The hop TABLE screen shows what the firmware
; believes; this shows what was last written to the chip. The two disagreeing
; is the fault an engineer comes to this screen to find.
; ---------------------------------------------------------------------------
mode_hop_ram
                lda     #PAGE_MANUAL_COWCHIP    ; page 3
                lbra    page_enter_second

; The diagnostics-menu role whose screen is a mode on page 3. It is declared
; here rather than beside the rest of the menu aliases because an equ needs
; its target defined first, and that target is above.
;
; There was a second, mode_page3, reaching a screen that painted a title and
; blanked line 2 by construction. It closed no dispatch arm, was cited by
; nothing, and existed only because page 3's third entry vector had nothing
; else to point at. Removed 2026-09-07 with the vector repointed at
; cowchip_open; see docs/coverage-truth.md.
diag_hop_ram    equ     mode_hop_ram

