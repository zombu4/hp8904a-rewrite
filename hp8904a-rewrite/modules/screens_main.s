; ===========================================================================
; screens_main.s - the five screens A2U12 carries itself
;
; Save/Recall, Output On/Off, Output Float, Filter Select and Special
; Functions. They live in A2U12 rather than a page because every one of them
; is reachable from every mode: a screen that can be entered from anywhere
; must not depend on which page happens to be mapped.
;
; ALL FIVE ARE REACHED BY NAME FROM THE MAIN SELECTION LEVEL. In the stock
; firmware three of them were not on any menu at all - they were entered by
; typing a number on the Special Functions screen, and the numbers appear
; nowhere on the instrument.
;
; EVERY SCREEN HERE FOLLOWS THE SAME SHAPE, so that an operator who has used
; one has used all five:
;
;   line 1 says what the screen is and what the field accepts;
;   line 2 is the field, with the current value shown before anything is
;   typed;
;   ENTER commits, and nothing is committed until it does;
;   an out-of-range entry is refused with a beep and the field is left as it
;   was, rather than being cleared.
;
; That last point is the difference between a screen an engineer can use with
; the manual shut and one they cannot. A field that clears itself on a
; mistake makes the operator retype a value they got right except for one
; digit.
;
; THE SAVE / RECALL PROMPT IS THE ONE EXCEPTION TO THAT LAST LINE, because the
; instrument is the exception: register_entry_key_handler ($F1D9) blanks the
; two digits at $F2A0-$F2E5 and re-arms the field. It is a two-digit number,
; not a value with a decimal point and a unit, so there is nothing worth
; keeping in it - and the register screen is ported, not designed.
; ===========================================================================

SCREEN_LINE1    equ     LCD_LINE1       ; DDRAM $00
SCREEN_LINE2    equ     LCD_LINE2       ; DDRAM $40

; ---------------------------------------------------------------------------
; Save and Recall.
;
; Twelve registers, 0 to 11, held in battery-backed RAM at the address the
; stock firmware used for the same purpose - see registers.s for why that
; address and why a setup stored by the stock firmware is not readable here.
; ---------------------------------------------------------------------------
; THE INSTRUMENT'S OWN WORDS, $EB41 and $EB69 over $EB91, which
; save_recall_prompt ($F331) paints with lcd_write_string_at ($D8A5). The '?' at
; DDRAM $12 is the two-digit field arm_numeric_entry_field ($AC35) is given at
; $F3C6. What stood here was this firmware's own 'SAVE / RECALL' screen with a
; clear-every-register f1, a save/recall toggle on f2 and a line of report
; after the commit, none of which the instrument has (driven on the emulator,
; both firmwares, 2026-09-15, ch B: shifted DOWN and shifted UP).
register_save_title
                fcc     "  Save Register   ?   0 - 11 Are Valid  "
register_recall_title
                fcc     "  Recall Register ?   0 - 11 Are Valid  "
register_enter_prompt
                fcc     "  Enter register number and/or  ENTER   "

REG_FIELD_POS   equ     SCREEN_LINE1+18 ; $12: where the two digits go
REG_FIELD_WIDTH equ     2

; ===========================================================================
; THE PROMPT IS AN OVERLAY ON THE INSTRUMENT, NOT A SCREEN.
;
; Read out of the stock and driven on it, 2026-09-13, from ch A of Channel
; Configuration with SHIFT DOWN, 1, ENTER:
;
;   channel screen     $220D=0000 $220F=5D0C  ef=0080 ef2=0000  display on
;   after SHIFT DOWN   $220D=F1D9 $220F=5D0C  ef=0090 ef2=0008  cursor on
;   after 1            $220D=F1D9 $220F=5D0C  ef=0090 ef2=0008
;   after ENTER        $220D=F1D9 $220F=5D0C  ef=0080 ef2=0000  cursor off
;
; $220F - the installed screen/mode handler, this firmware's screen_handler -
; holds dispatch_ui_event ($5D0C) THROUGHOUT. save_recall_prompt ($F331) never
; writes it. What it writes is $220D, the modal entry handler, plus bit 3 of
; event_flags2 ($2202); ui_message_dispatch ($8D60) tests that bit at $8D66,
; calls [$220D] FIRST, and only then dispatches the message through the 34-arm
; table and on to [$220F]. So the mode keeps the keys and the bus while the
; register number is typed, and the glass comes back the moment it is taken:
; register_entry_key_handler ($F1D9) clears bit 3 on every exit and, when
; local, calls lcd_repaint_shadow ($D9C6) at $F236.
;
; THE GLASS IS NOT PART OF THE SHADOW WHILE THE PROMPT IS UP. $F331 paints
; with lcd_write_string_at ($D8A5), which writes the controller and NOT the
; 80-byte shadow at $242B - the generated source's own note calls it "the same
; routine without the clipping or the shadow copy" - so the shadow still holds
; the channel screen, and $D9C6 puts it back whole. lcd_write_line_raw and
; lcd_write_raw are that routine here, and lcd_repaint is $D9C6.
;
; WHAT THIS FIRMWARE HAD INSTEAD: register_screen_open called screen_install,
; which REPLACED screen_handler and never put it back. After a save from the
; channel screen the bus was answered by a screen the instrument was never on -
; 'DEA OC3;' was refused, and emulator/tests/test_summing_new.py failed
; sixteen checks on it (4c, 4d, 4e and the three whole-run aggregates).
;
; THE ONE SLOT. This firmware dispatches keys (boot.s foreground_dispatch) and
; bus requests (remote.s remote_deliver) through the single screen_handler,
; where the stock has $220D and $220F. So the prompt SAVES the covered
; screen's slot and its four key vectors in reg_prompt_save and puts them back
; when it is dismissed, which is the same observable behaviour: the screen
; underneath has the keys and the bus again, with its own commit and f-keys,
; the instant the number is taken.
;
; WHAT IS NOT TAKEN: bit 4 of event_flags, which $F370 sets and $D9C6 clears.
; On the instrument that bit makes every OTHER painter write the shadow and
; not the glass, so nothing can scribble over the prompt. It is lcd_hold here,
; and holding it across keystrokes is not safe in this firmware: LOCAL and the
; shifted keys are answered by the foreground WITHOUT consulting the screen
; handler (boot.s foreground_key and foreground_shifted), and
; hp8904a-rewrite/tests/test_screens_take_keys.py refuses - correctly - any
; screen but the Keyboard Check taking LOCAL for itself. A held glass could
; therefore outlive the prompt and leave the operator reading a screen that no
; longer has the keys, which is worse than what the bit prevents. The restore
; does not depend on it: the prompt paints raw, so the shadow is the screen
; underneath either way. The one painter that could reach the glass while the
; prompt is up is dtmf_echo_show, from the DTMF tick, and it repaints itself.
; ===========================================================================

; The four cells the prompt takes over, in the order reg_prompt_save holds
; them. A table rather than twelve loads and twelve stores, so the save and
; the restore cannot come to disagree about which cells they cover.
REG_PROMPT_CELLS equ    4
register_prompt_cells
                fdb     screen_handler
                fdb     screen_commit
                fdb     screen_f1
                fdb     screen_f4

; ---------------------------------------------------------------------------
; register_screen_open - the Save / Recall prompt, on its save half
; register_screen_open_recall - the same prompt, on its recall half
;
;   uses:  A, B, X, Y, U
;
; TWO KEYS, TWO PROMPTS. Shifted UP posts $0022 to state_open_recall_register
; ($8E9B), which calls save_recall_prompt ($F331) with the Recall wording and
; $3A7B = 0; shifted DOWN posts $0021, which reaches the mode's own handler and
; prompts to SAVE. Both keys opened this on its save half once, so the operator
; who pressed the Recall key was one f2 away from overwriting the register.
;
; screen_mode is this firmware's $3A7B, with the sense the commit below reads:
; 0 saving, 1 recalling.
; ---------------------------------------------------------------------------
register_screen_open
                lda     >rmt_flags              ; WHILE REMOTE $F331 PAINTS
                bita    #RF_REMOTE              ; NOTHING ($F34D-$F36D): it arms
                beq     register_screen_local   ; the number and installs $F1D9,
                ldb     #RK_SAVE                ; which here is the pending kind
                lbra    remote_cmd_store_kind   ; remote_prompt_message and
                                                ; remote_set_save answer
register_screen_local
                clr     >screen_mode            ; 0 = saving, the stock's
                bra     register_prompt_arm     ; $3A7B = 1 at $F348
register_screen_open_recall
                lda     #$01                    ; 1 = recalling, $3A7B = 0 at
                sta     >screen_mode            ; $F344
register_prompt_arm
                lbsr    register_prompt_cover   ; the screen underneath, kept

                ldx     #register_prompt_key    ; the stock's $220D = $F1D9;
                stx     >screen_handler         ; here the one slot, saved above
                ldx     #register_screen_commit
                stx     >screen_commit
                ldx     #$0000                  ; NO SOFTKEYS: $F1D9 takes the
                stx     >screen_f1              ; entry-complete code alone; any
                stx     >screen_f4              ; other message dismisses it ($F2EF)

                lda     #REG_FIELD_POS
                sta     >screen_field_pos
                lda     #REG_FIELD_WIDTH
                sta     >screen_field_width

                ; NO lcd_clear: it fills the SHADOW with spaces as well as the
                ; glass, and the shadow is the screen underneath. The two raw
                ; lines below cover all eighty characters anyway, which is what
                ; $F390-$F3C0 writes.
                lda     #ENTRY_DECIMAL
                ldb     #REG_FIELD_WIDTH
                lbsr    entry_begin             ; arm_numeric_entry_field
                                                ; ($AC35) at $F3D3, cursor and
                                                ; all
                lbsr    register_prompt_paint
                lbra    screen_field_arm        ; $F3D8: armed as it opens, local

; ---------------------------------------------------------------------------
; register_prompt_cover - remember the screen the prompt is going over
;
;   uses:  A, B, X, Y, U
;
; Nothing is saved when the prompt is ALREADY up - shifted UP with the Save
; prompt showing turns it round rather than opening a second one - or the
; second arm would record the prompt's own handler as the screen underneath
; and dismissing it would strand the operator on a dead overlay.
; ---------------------------------------------------------------------------
register_prompt_cover
                lbsr    overlay_is_up           ; an overlay over an overlay
                beq     register_prompt_cover_done ; keeps the first's cover
                ldy     #register_prompt_cells
                ldu     #reg_prompt_save
register_prompt_cover_next
                ldx     ,y++                    ; the cell's address
                ldd     ,x                      ; what is in it
                std     ,u++
                cmpy    #register_prompt_cells+REG_PROMPT_CELLS*2
                blo     register_prompt_cover_next
                lda     >screen_field_pos       ; and the field geometry, which
                sta     >reg_prompt_field       ; the Output and Filter screens
                lda     >screen_field_width     ; keep their own copy of
                sta     >reg_prompt_field+1
register_prompt_cover_done
                rts

; ---------------------------------------------------------------------------
; overlay_is_up - is one of the $220D overlays the installed handler?
;
;   exit:  Z SET when the Save / Recall prompt or the output screens are
;   uses:  X
; ---------------------------------------------------------------------------
overlay_is_up
                ldx     >screen_handler
                cmpx    #register_prompt_key
                beq     overlay_is_up_done
                cmpx    #output_prompt_key
                beq     overlay_is_up_done
                cmpx    #filter_select_key
overlay_is_up_done
                rts

; ---------------------------------------------------------------------------
; overlay_abandon_held - $3C to the screen an overlay is still covering
;
;   uses:  A, B, X, Y, U
;
; ui_message_dispatch ($8D60) writes $3C over $2217 when the $220D handler
; returns non-zero, and the mode answers it with the overlay still up. The
; stock's painters are writing only the shadow then - bit 4 of $2204, set by
; the screen that opened the overlay - so a field edit ended there changes the
; shadow and not the glass. lcd_hold is that bit: lcd_write keeps the shadow
; and skips the glass while it is set. The covered handler is put in the one
; slot for the call and the overlay's own put back after it.
; ---------------------------------------------------------------------------
overlay_abandon_held
                ldx     >screen_handler         ; the overlay's own
                pshs    x
                ldx     >reg_prompt_save        ; the covered screen's, first
                stx     >screen_handler         ; of the saved cells
                lda     #$01
                sta     >lcd_hold
                ldb     #KEY_ABANDON
                ldx     >screen_handler
                jsr     ,x
                clr     >lcd_hold
                puls    x
                stx     >screen_handler
                rts

; ---------------------------------------------------------------------------
; register_prompt_dismiss - give the instrument back
;
;   uses:  A, B, X, Y, U
;
; $F1D9's common tail: bit 3 of $2202 cleared, and while local
; lcd_repaint_shadow ($D9C6) at $F236. Does nothing when the prompt is not the
; installed handler, so a caller cannot dismiss twice and put a stale handler
; back over a screen that opened since.
; ---------------------------------------------------------------------------
register_prompt_dismiss
                lbsr    overlay_is_up
                bne     register_prompt_dismiss_done
                ldy     #register_prompt_cells
                ldu     #reg_prompt_save
register_prompt_dismiss_next
                ldx     ,y++                    ; the cell's address
                ldd     ,u++                    ; what it held
                std     ,x
                cmpy    #register_prompt_cells+REG_PROMPT_CELLS*2
                blo     register_prompt_dismiss_next
                lda     >reg_prompt_field
                sta     >screen_field_pos
                lda     >reg_prompt_field+1
                sta     >screen_field_width

                ; AND THE ENTRY IN PROGRESS DIES WITH THE PROMPT, which is the
                ; stock's request code $3C: ui_message_dispatch rewrites $2217
                ; to $003C when the handler at $220D reports it has finished
                ; ($8D7E), $3C is past the table's range so it reaches the
                ; screen underneath, and every screen answers it by abandoning
                ; the entry it was collecting. screen_install clears the same
                ; two flags for the same reason.
                clr     >entry_active
                clr     >entry_armed


                ; THE CURSOR IS NOT THIS ROUTINE'S. It was turned off here, and the
                ; instrument's off moments for this prompt are elsewhere: ENTER
                ; reaches $B5BA before the commit (register_prompt_enter), a mapped
                ; key reaches $B45C or $B48C before the prompt hears it
                ; (entry_key_exit), and the controller's REN reaches $9F1A
                ; (remote.s). A second off here wrote a byte the instrument does not.
                lbra    lcd_repaint             ; $D9C6: the screen underneath,
                                                ; values and all, out of the
                                                ; shadow the prompt never wrote
register_prompt_dismiss_done
                rts


; ---------------------------------------------------------------------------
; register_prompt_key - the prompt's own key handler, the stock's $F1D9
;
;   entry: B = the key code, or RMT_RQ + the stock's request code
;   uses:  A, B, X, Y, U
;
; The keys it uses are the ones $F1D9 uses - digits, BACKSPACE and ENTER - plus
; the three softkeys this screen has always had. EVERYTHING ELSE DISMISSES THE
; PROMPT AND IS THEN ACTED ON BY THE SCREEN UNDERNEATH, which is $F2EF: any
; message that is not $0023 tears the entry down and RETURNS ZERO, so
; ui_message_dispatch passes the original message on to [$220F] rather than
; rewriting it to $3C. Pressing FREQ over the Save prompt therefore selects the
; channel screen's frequency field, exactly as it does on the instrument, and a
; bus command that arrives while the prompt is up is obeyed.
; ---------------------------------------------------------------------------
register_prompt_key
                cmpb    #RMT_RQ                 ; a bus request, never a key
                bhs     register_prompt_foreign
                cmpb    #KEY_REFRESH            ; 'repaint yourself' - and the
                beq     register_prompt_paint   ; prompt is what is showing.
                                                ; Tested before KEY_INVALID
                                                ; below because 55 is above it
                cmpb    #KEY_ENTER
                beq     register_prompt_enter
                cmpb    #KEY_BACKSPACE
                beq     register_prompt_back
                ; A UNIT KEY IS REFUSED, NOT FOREIGN. This prompt arms
                ; UNITS CLASS 2, measured on the stock - accept_units_key
                ; ($B0C1) does LDX >$23AB, a WORD, and range-checks it 2-7,
                ; and the Save / Recall prompt reads 2 there against 3 for
                ; phase, 4 for amplitude and 6 for frequency. Class 2 is
                ; unit_key_class2_check, which accepts $1B - ENTER - and
                ; nothing else.
                ;
                ; So deg, Hz and kHz are keys this field CANNOT take, and the
                ; instrument treats that as a refusal: driven with the prompt
                ; up, kHz reaches error_report_beep ($C3FE) once, leaves 2 in
                ; $23DE and LEAVES THE PROMPT STANDING. $2221 never changes and
                ; the LCD shadow never moves.
                ;
                ; They fell through to register_prompt_foreign here, which
                ; dismissed the prompt and handed the key to the screen
                ; underneath - seed 26 step 31 of the differential harness,
                ; where the stock keeps 'Save Register ?' under kHz and this
                ; firmware fell back to the channel screen. THIS ARM IS THE
                ; PANEL'S ONLY: measured with the prompt up, a panel kHz leaves
                ; both machines on the prompt with 2 recorded. What a BUS unit
                ; does is not decided here - see the note below.
                ;
                ; AND THE REFUSAL IS KEYED ON THE CLASS, NOT ON THE KEY. An
                ; earlier attempt absorbed a unit key wherever a field was
                ; armed, which swallowed the TERMINATOR every other field
                ; commits on: on a class 4 or 6 field the same key ends the
                ; entry. Those screens answer for themselves; this one refuses,
                ; because its class does.
                cmpb    #KEY_DEG                ; 28, 29, 30 - and nothing
                blo     register_prompt_not_unit ; either side: ENTER is 27,
                cmpb    #KEY_KHZ                ; which class 2 DOES take and
                bhi     register_prompt_not_unit ; which is handled above

                ; THE BUS DOES NOT COME THROUGH HERE, and an origin test that
                ; stood here has been removed rather than left looking useful.
                ; It read rmt_flags, which is $00 at the moment this routine
                ; runs on the panel path and only becomes $01 afterwards, so it
                ; was dead; and the bus never reaches this routine by this
                ; route at all. Traced on both machines: a bus unit with the
                ; prompt up goes remote_poll_remote -> remote_refresh ->
                ; remote_deliver -> remote_prompt_message, and on the stock the
                ; prompt is taken down at the REMOTE EDGE by
                ; enter_remote_state ($9EB9) -> entry_exit_restore_display
                ; ($B38B) -> lcd_repaint_shadow ($D9C6), not by this handler.
                ; That is ported at remote_poll_remote in remote.s.
                ldb     #ERR_KEY_ENTRY          ; $C3FE with 2, which is what
                lbsr    error_record            ; the stock leaves in $23DE
                rts                             ; and the prompt stands
register_prompt_not_unit
                cmpb    #KEY_INVALID            ; a sweep that found nothing and
                bhs     register_prompt_ignore  ; two keys at once are decode
                                                ; faults, not something the
                                                ; operator asked for: they must
                                                ; not tear the prompt down
                pshs    b
                lbsr    key_digit               ; carry clear and B = 0 to 9
                bcc     register_prompt_digit
                puls    b                       ; not a digit and not ours
                bra     register_prompt_foreign
register_prompt_digit
                leas    1,s                     ; the key code is done with
                lbsr    entry_digit
                bcs     register_prompt_full
                bra     register_prompt_echo
register_prompt_full
                ldb     #ERR_VALUE_TOO_BIG
                lbra    error_raise
register_prompt_back
                lbsr    entry_backspace
                bra     register_prompt_echo
register_prompt_ignore
                rts

; The four softkeys go through the vectors the arm above filled, so that what
; each key does is declared once, beside the prompt, and so that the covered
; screen's own vectors - saved and restored with the handler - cannot be
; reached by a key pressed on the prompt.
register_prompt_enter
                ldx     >screen_commit
                beq     register_prompt_ignore
                lbsr    entry_cursor_off        ; $B5BA, then request $23
                jmp     ,x
; $F2EF, both halves of it: while remote the stock reports error $0F with
; report_error_and_pulse_status_bit ($9DD3) and does not repaint, because
; nothing was painted; here the prompt is on the glass however the instrument
; is being driven - it can only be opened from the panel - so the dismiss
; always puts the screen underneath back, and the error is recorded on top of
; that while remote.
register_prompt_foreign
                pshs    b
                lbsr    register_prompt_dismiss
                lda     >rmt_flags
                bita    #RF_REMOTE
                beq     register_prompt_hand
                ldb     #ERR_KEY_UNUSABLE       ; $0F, 'Un-executable command',
                lbsr    error_record            ; the number $F2FB reports
register_prompt_hand
                puls    b
                ldx     >screen_handler         ; and on to the screen the
                beq     register_prompt_ignore  ; prompt was covering, with the
                jmp     ,x                      ; message unchanged

; ---------------------------------------------------------------------------
; register_prompt_paint - both lines of the prompt, and the field
;
;   uses:  A, B, X, Y
;
; RAW, which is $F390-$F3D3: lcd_write_string_at ($D8A5) twice and then the
; field. Raw is not a shortcut here - it is the whole mechanism. The shadow
; keeps holding the screen underneath, and that is what register_prompt_dismiss
; puts back.
; ---------------------------------------------------------------------------
register_prompt_paint
                ldx     #register_save_title    ; $3A7B non-zero: $EB41
                tst     >screen_mode
                beq     register_prompt_line1
                ldx     #register_recall_title  ; $EB69
register_prompt_line1
                lda     #SCREEN_LINE1
                ldb     #LCD_COLUMNS
                lbsr    lcd_write_line_raw
                lda     #SCREEN_LINE2           ; $EB91
                ldx     #register_enter_prompt
                ldb     #LCD_COLUMNS
                lbsr    lcd_write_line_raw
                tst     >entry_active           ; nothing typed: the '?' stands
                lbeq    screen_field_cursor
                ; and into the echo, which puts the digits typed so far back

; ---------------------------------------------------------------------------
; register_prompt_echo - show the digits typed so far, raw
;
;   uses:  A, B, X, Y
;
; screen_numeric_echo with lcd_write_raw in place of lcd_write, for the same
; reason: the stock echoes the register digit with lcd_write_string_at - driven
; above, '1' appears in the prompt while the shadow still holds the channel
; screen - and an echo that mirrored would leave a stray digit at column 18 of
; the line the dismiss repaints.
; ---------------------------------------------------------------------------
register_prompt_echo
                ldx     #chan_text
                lbsr    entry_render
                lda     >screen_field_pos
                ldb     >screen_field_width
                ldx     #chan_text
                lbsr    lcd_write_raw
                lbra    screen_field_cursor     ; $B567: after the last digit

; ---------------------------------------------------------------------------
; register_screen_commit - act on the number that was typed
;
;   exit:  carry SET if the register number was refused
;   uses:  A, B, X, Y, U
;
; The number is checked before either direction is taken, so a bad register
; number cannot half-save.
; ---------------------------------------------------------------------------
register_screen_commit
                lbsr    entry_value
                bcs     register_screen_bad     ; more than 24 bits typed
                lda     >entry_result           ; a register number is one
                ora     >entry_result+1         ; byte
                bne     register_screen_bad
                ldb     >entry_result+2
                lbsr    register_valid          ; $F21A CMPB #$0B
                bcs     register_screen_bad
                ; THE PROMPT GOES FIRST, and then the register is acted on.
                ; $F1D9 repaints the shadow at $F236 and clears bit 3 of
                ; $2202 at $F23E, and only then saves or calls
                ; enter_handler_by_index at $F262. The order matters now that
                ; a recall enters a mode: the dismiss puts back the covered
                ; screen's handler and vectors (register_prompt_cells), and
                ; run after the recall it would lay the OLD mode's handler
                ; over the mode just entered.
                pshs    b
                lbsr    register_prompt_dismiss ; $F236: the glass back
                puls    b
                tst     >screen_mode
                bne     register_screen_recall
                lbsr    register_save
                bra     register_screen_back
register_screen_recall
                lbsr    register_restore        ; the mode it was saved in
register_screen_back
                tst     >screen_mode            ; a recall repaints what it
                beq     register_screen_abandon ; brought back
                ldb     #KEY_REFRESH
                ldx     >screen_handler
                beq     register_screen_abandon
                jsr     ,x
register_screen_abandon
                ldb     #KEY_ABANDON            ; AND $3C TO THE MODE, as $8D7E
                ldx     >screen_handler         ; writes it when $F1D9 returns
                beq     register_screen_quiet   ; non-zero: the field underneath
                jsr     ,x                      ; goes (seed-free drive: SAVE 1
register_screen_quiet                           ; then UP records 4 on the stock)
                andcc   #~CC_CARRY
                rts
register_screen_bad
                ldb     #ERR_REG_RANGE          ; $13 through $9DD3 while
                lbsr    error_record            ; remote, a beep when not

                ; AND THE TWO DIGITS GO, WHICH IS WHAT THE INSTRUMENT DOES.
                ; $F2A0-$F2E5: error_report_beep ($C3FE) with $13, two spaces
                ; from ram_invalid_message_padding ($ED11) written at DDRAM
                ; $12 - the field - and arm_numeric_entry_field ($AC35) again.
                ; The prompt STAYS UP: that arm leaves bit 3 of $2202 set,
                ; unlike every other exit from $F1D9, so the operator retypes
                ; into an empty field without pressing anything to get back.
                lda     #ENTRY_DECIMAL
                ldb     #REG_FIELD_WIDTH
                lbsr    entry_begin
                lbsr    register_prompt_echo
                lbsr    screen_field_arm        ; $F2E3: and armed again
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; Output On / Off, and Output Float.
;
; Two screens over one body: both pick an output and set one bit of that
; channel's latch. The bit differs and the wording differs; nothing else
; does, and two copies of this would be two places to fix a latch bug.
;
; WHICH BIT DOES WHAT, corrected against common/hardware.inc, which carries
; the manual citations and the stock addresses for all three:
;
;   bit 0  the OUTPUT FILTER select, net FLC - manual page 8-27
;   bit 1  the OUTPUT FLOAT relay K404A, active low - manual page 8-28
;   bit 2  the OUTPUT ON/OFF relay, active low, CLEAR IS ON - from
;          set_output_enable ($B79C), which writes $FF to $23B3+channel and
;          value 0 through mask $04
;
; This header used to say bit 0 was the output enable, that what bit 2 does
; was "NOT ESTABLISHED", and that the Output Float screen was the only screen
; writing it. All three are contradicted inside this repository: hardware.inc
; declares bit 0 the filter and filter_apply's own header agrees; the
; $23B3+channel boolean this attributed to an unidentified bit is
; hardware.inc's EVIDENCE that bit 2 is the output enable; and
; output_onoff_open writes bit 2 twenty-nine lines below the sentence, as
; does ampl_blank. Nothing miscomputed, because the code loads LATCH_OUTPUT
; and LATCH_FLOAT by name - but this header is what a reader consults before
; changing a latch write, and it named the wrong relay., so this firmware treats it as the float control and
; says here that the identification rests on that and nothing else.
; ---------------------------------------------------------------------------
; The latch bits are in common/hardware.inc, where every image can see them -
; the sequence players in the paged ROMs gate their own outputs and could
; not, because these were declared here.

; THE OUTPUT ON/OFF AND OUTPUT FLOAT SCREENS ARE AN OVERLAY, like the Save /
; Recall prompt. show_output_onoff_screen ($F5A0) writes $220D and bit 3 of
; $2202 and never $220F, so the mode keeps the bus and the keys it does not
; take, and the glass comes back from the shadow when it goes. What stood here
; was a screen of this firmware's own - 'OUTPUT ON / OFF     channel 1 to 4'
; over 'Channel:    State:  ENTER commits' - that replaced the handler, set
; the bit on every fitted channel on ENTER and left for the Main Selection.
; Driven on the stock on the emulator, 2026-09-15 (docs/output-screens-port.md):
; shifted PHASE, '1', '.' switches output 1 off and returns to the channel
; screen; '1' then ENTER switches it on; '0' or a number past the fitted count
; is $A0 and the screen stays; an arrow or f1 dismisses it and reaches the
; screen underneath.
; ---------------------------------------------------------------------------
output_onoff_title
                fcc     "Output On/Off Control"         ; $EBB9
output_float_title
                fcc     "Output Float Control "         ; $EBCE
OUT_TITLE_W     equ     21
output_enter_prompt
                fcc     "   Enter output number =   and ON/OFF   " ; $EBE3
output_blank_line
                fcc     "                                        " ; $ED11

OUT_TITLE_POS   equ     SCREEN_LINE1+9          ; $F616: position 9
OUT_FIELD1_POS  equ     SCREEN_LINE2+25         ; $59, the number's one digit
OUT_FIELD2_POS  equ     SCREEN_LINE2+31         ; $5F, the ON or OFF field

; ---------------------------------------------------------------------------
; output_onoff_open / output_float_open - show_output_onoff_screen ($F5A0)
;
;   uses:  A, B, X, Y, U
;
; One routine and two entries, as $8EB5 and $8EC6 call $F5A0 with $000F and
; with anything else. screen_bit is the stock's $3A7E: the latch bit this
; screen switches, bit 2 for On/Off and bit 1 for Float.
; ---------------------------------------------------------------------------
output_onoff_open
                ldb     #LATCH_OUTPUT
                bra     output_prompt_open
output_float_open
                ldb     #LATCH_FLOAT
output_prompt_open
                stb     >screen_bit
                lbsr    register_prompt_cover   ; the screen underneath, kept
                ldx     #output_prompt_key      ; $F67F: $220D = $F3F0
                stx     >screen_handler
                ldx     #$0000                  ; the overlay answers its own
                stx     >screen_commit          ; keys; the covered screen's
                stx     >screen_f1              ; vectors are kept aside, not
                stx     >screen_f4              ; reachable through it
                clr     >output_stage           ; $3A7D = 0
                lda     #OUT_FIELD1_POS
                sta     >screen_field_pos
                lda     #$01
                sta     >screen_field_width
                lda     #ENTRY_DECIMAL
                ldb     #$01
                lbsr    entry_begin
                lbsr    output_prompt_paint     ; local only, as $F5BC tests
                lbra    screen_field_arm        ; $AC35: armed as it opens

; ---------------------------------------------------------------------------
; Filter Select - filter_screen_show ($FC39) and filter_select_key_handler
; ($F9D4)
;
; An overlay, as the Output screens are: the covered screen's handler and
; vectors wait in reg_prompt_save and it hears $3C for every message this one
; takes. Stage 0 is a one-digit output number at $07. Stage 1 shows that
; output's present filter at $1A and its mode at $53, and f1 steps the mode
; Sharp Cutoff, Low Overshoot, Automatic ($FAC1-$FB06). f4 leaves ($FB09); any
; other message leaves and goes on to the screen underneath unrecorded ($FB11,
; which returns 0). output_stage is the stock's $3A7F here and output_channel
; its $3A7C: one overlay is up at a time, and opening this one replaces the
; other's handler.
;
; Driven on the stock 2026-09-15, ch B: shifted AMPL then 2 shows 'Output 2
; Present Filter = Sharp Cutoff' over 'Filter Select = Automatic'; f1 three
; times writes $24E8+1 = 0, 1 and 3, with bit 0 of $24F0+1 following; f4 then
; UP records 4. At stage 0 ENTER, '.' and Hz record 2, 0 and 5 record $A0 and
; BACKSPACE nothing. At stage 1 a digit, ENTER, '.' and BACKSPACE record 1, f2
; leaves with nothing recorded and UP leaves with 4.
;
; The three names are the stock's own strings at $EC5B, $EC69 and $EC77. What
; the setting does to the output stage is not decidable from the ROM, so the
; words are reproduced exactly for an operator comparing the manual.
; ---------------------------------------------------------------------------
FILTER_AUTOMATIC equ    0               ; the stock's mode 3
FILTER_SHARP     equ    1               ; its mode 0
FILTER_LOW_OVER  equ    2               ; its mode 1
FILTER_COUNT     equ    3
FLT_FIELD_POS   equ     SCREEN_LINE1+7          ; $07, the output's digit
FLT_PRESENT_POS equ     SCREEN_LINE1+26         ; $1A, the filter it has now
FLT_MODE_POS    equ     SCREEN_LINE2+19         ; $53, the mode chosen
FLT_NAME_W      equ     14

filter_line1    fcc     "Output   Present Filter =               " ; $EC0B
filter_line2    fcb     $00,$01                 ; $EC33, with the f1 and f4
                fcc     " Filter Select =               " ; glyphs
                fcb     $00,$04
                fcc     " Exit"
filter_names    fcc     "Automatic     "        ; $EC5B, FILTER_AUTOMATIC
                fcc     "Sharp Cutoff  "        ; $EC69, FILTER_SHARP
                fcc     "Low Overshoot "        ; $EC77, FILTER_LOW_OVER

filter_screen_open
                lbsr    register_prompt_cover   ; the screen underneath, kept
                ldx     #filter_select_key      ; $220D = $F9D4
                stx     >screen_handler
                ldx     #$0000                  ; the overlay answers its own
                stx     >screen_commit          ; keys; the covered screen's
                stx     >screen_f1              ; vectors are kept aside
                stx     >screen_f4
                clr     >output_stage           ; $FCC0: $3A7F = 0
filter_arm
                lda     #FLT_FIELD_POS          ; THE $3A7F = 0 TAIL ($FB33):
                sta     >screen_field_pos       ; both lines, and the one-digit
                lda     #$01                    ; field at $07 armed again
                sta     >screen_field_width
                lda     #ENTRY_DECIMAL
                ldb     #$01
                lbsr    entry_begin             ; arm_numeric_entry_field
                lbsr    filter_paint_lines
                lbra    screen_field_arm

filter_select_key
                cmpb    #RMT_RQ
                bhs     filter_key_foreign      ; a bus request: $FB11
                cmpb    #KEY_REFRESH            ; $2E and request 1 are
                beq     filter_key_foreign      ; messages like any other
                cmpb    #KEY_GONE_LOCAL
                beq     filter_key_foreign
                cmpb    #KEY_INVALID
                lbhs    filter_key_ignore
                cmpb    #KEY_F1
                lbeq    filter_key_f1           ; $13: $FAC1
                cmpb    #KEY_F4
                lbeq    filter_key_f4           ; $16: $FB09
                tst     >output_stage
                bne     filter_key_second
                cmpb    #KEY_BACKSPACE
                lbeq    filter_key_ignore
                cmpb    #KEY_ENTER
                beq     filter_key_no_arm
                cmpb    #KEY_DEG
                beq     filter_key_no_arm
                cmpb    #KEY_HZ
                beq     filter_key_no_arm
                cmpb    #KEY_KHZ
                beq     filter_key_no_arm
                cmpb    #KEY_POINT
                beq     filter_key_no_arm
                cmpb    #KEY_MINUS
                beq     filter_key_no_arm
                pshs    b
                lbsr    key_digit               ; carry clear and B = 0 to 9
                bcc     filter_key_digit
                puls    b
                bra     filter_key_foreign
filter_key_second
                cmpb    #KEY_ENTER              ; NO FIELD IS ARMED AT STAGE 1,
                beq     filter_key_no_field     ; so the keys numeric entry
                cmpb    #KEY_POINT              ; keeps are refused by it
                beq     filter_key_no_field
                cmpb    #KEY_BACKSPACE
                beq     filter_key_no_field
                cmpb    #KEY_MINUS
                beq     filter_key_no_field
                cmpb    #KEY_DEG
                beq     filter_key_no_field
                cmpb    #KEY_HZ
                beq     filter_key_no_field
                cmpb    #KEY_KHZ
                beq     filter_key_no_field
                pshs    b
                lbsr    key_digit
                puls    b
                bcc     filter_key_no_field
filter_key_foreign
                pshs    b                       ; $FB11: $3A7F = 2 and 0 back,
                lbsr    register_prompt_dismiss ; so the message goes on to the
                puls    b                       ; screen underneath, with
                ldx     >screen_handler         ; nothing recorded
                beq     filter_key_ignore
                jmp     ,x
filter_key_no_arm
                ldb     #ERR_KEY_ENTRY          ; 2
                lbra    error_raise
filter_key_no_field
                ldb     #ERR_NO_ENTRY_FIELD     ; 1
                lbra    error_raise
filter_key_digit
                leas    1,s
                tstb                            ; $FA5A: 1 to the fitted count
                beq     filter_key_bad
                decb
                lbsr    channel_valid           ; carry set if not fitted
                bcs     filter_key_bad
                stb     >output_channel         ; $FAA3: $3A7C less one
                lda     #$01
                sta     >output_stage           ; $3A7F = 1
                addb    #'1'
                stb     >chan_text
                lda     #FLT_FIELD_POS          ; the digit echoed at $07
                ldb     #$01
                ldx     #chan_text
                lbsr    output_prompt_raw
                clr     >entry_active           ; the field is complete and
                clr     >entry_armed            ; nothing is armed after it
                lbsr    entry_cursor_off
                lbsr    filter_paint_names      ; the $3A7F = 1 tail
                lbra    overlay_abandon_held    ; and $3C underneath
filter_key_bad
                ldb     #ERR_OUTPUT_NUMBER      ; $FAB0: error_report_beep, $A0
                lbsr    error_raise
                lbsr    filter_arm              ; $3A7F still 0
                lbra    overlay_abandon_held
filter_key_f1
                tst     >output_stage           ; $FAC1: only with an output
                beq     filter_key_f1_none      ; chosen
                ldb     >output_channel
                ldx     #filter_mode
                lda     b,x
                inca                            ; Automatic, Sharp Cutoff, Low
                cmpa    #FILTER_COUNT           ; Overshoot and round: the
                blo     filter_key_f1_store     ; stock's 3 -> 0, 0 -> 1 and
                clra                            ; 1 -> 3
filter_key_f1_store
                sta     b,x                     ; set_output_enable_mode ($F770):
                lbsr    filter_apply            ; the mode, and the line from it
                lbsr    filter_paint_names
                lbra    overlay_abandon_held
filter_key_f1_none
                lbsr    filter_arm
                lbra    overlay_abandon_held
filter_key_f4
                lbsr    register_prompt_dismiss ; $FB09: $3A7F = 2, the shadow
                ldb     #KEY_ABANDON            ; repainted, and 1 back - so $3C
                ldx     >screen_handler         ; to the screen underneath
                beq     filter_key_ignore
                jmp     ,x
filter_key_ignore
                rts

; filter_paint_lines - both lines of stage 0 ($FB33-$FB82), local only
; filter_paint_names - stage 1's two names ($FB85-$FC03), local only
;   uses:  A, B, X
filter_paint_lines
                lda     >rmt_flags
                bita    #RF_REMOTE
                bne     filter_paint_done
                lda     #SCREEN_LINE1
                ldx     #filter_line1
                ldb     #LCD_COLUMNS
                lbsr    lcd_write_line_raw
                lda     #SCREEN_LINE2
                ldx     #filter_line2
                ldb     #LCD_COLUMNS
                lbra    lcd_write_line_raw
filter_paint_names
                lda     >rmt_flags
                bita    #RF_REMOTE
                bne     filter_paint_done
                ldb     >output_channel         ; the mode's name at $53
                ldx     #filter_mode
                ldb     b,x
                lda     #FLT_NAME_W
                mul
                ldx     #filter_names
                leax    d,x
                lda     #FLT_MODE_POS
                ldb     #FLT_NAME_W
                lbsr    lcd_write_raw
                ldb     >output_channel         ; and at $1A the filter the
                ldx     #latch_shadow           ; line has now: bit 0 of
                lda     b,x                     ; $24F0+ch, set for Low
                anda    #LATCH_FILTER           ; Overshoot
                ldx     #filter_names+FLT_NAME_W
                tsta
                beq     filter_paint_present
                ldx     #filter_names+2*FLT_NAME_W
filter_paint_present
                lda     #FLT_PRESENT_POS
                ldb     #FLT_NAME_W
                lbra    lcd_write_raw
filter_paint_done
                rts

; ---------------------------------------------------------------------------
; filter_apply - put the right filter on every fitted channel
;
;   uses:  A, B, X, Y, U
;
; Bit 0 of each channel latch is the filter line. Which level selects which
; filter is read off the stock's own filter screen: filter_select_key_handler
; ($F9D4) names the stored mode byte $24E8+ch 'Sharp Cutoff' ($EC69) for 0,
; 'Low Overshoot' ($EC77) for 1 and 'Automatic' ($EC5B) otherwise; its arm at
; lf9e8 hands set_output_enable_mode ($F770) 0 for key $12, 1 for key $13 and
; 3 for any other; and $F770's lf79f takes a request of 0 or 1 as the line's
; new state itself and drives it through switch_channel_latch_bit0 ($F692).
; So the line HIGH is Low Overshoot and LOW is Sharp Cutoff, from the
; firmware; hardware.inc's LATCH_FILTER note quotes the manual saying the same
; of net FLC.
;
; Automatic is request 3, for which lf7a8 takes the state from $24EC+ch - the
; byte recompute_channel_byte_24ec ($F7EC) derives from the channel records
; and the hop state. That derivation is filter_auto_bit below, and this
; routine runs wherever the stock runs $F7EC: after a frequency commit
; ($6514), a waveform ($68B2) or destination ($7BD2, $7ED8) change, a hop
; frequency applied ($4C97) and the Freq Hop switch ($4A5F) - page 0 reaches
; it through ABI slot 78, the bus handlers in remote.s directly - and from
; register_apply after a recall. The choice used to be stored in one byte and
; written nowhere; it is a per-channel line, so it is applied per channel.
;
; ONLY A LINE THAT CHANGES IS WRITTEN, AND ONLY A CHANGE MUTES. $F692 reads
; bit 0 of the shadow $24F0+chan (LDX #$24F0 / LEAX D,X / LDB ,X / ANDB #$01)
; and compares it with the request (CLRA / CMPD >$0008,S / LBNE lf6b2): equal
; returns at lf710 with nothing written; a change is bracketed by
; set_channel_latch_bit2 ($B67B) at $F6C0 and $F70B with delay_ms ($D670)(5)
; either side - the filter relays switch, and switching a filter under a live
; output puts the transient straight out of the socket. Here that is
; ampl_blank and ampl_unblank around channel_latch_rmw, and the compare in
; front of them is what lets every commit run this without muting an output
; whose filter has not moved.
; ---------------------------------------------------------------------------
; ---------------------------------------------------------------------------
; filter_recompute_all - derive every channel's byte, then drive the lines
;
;   uses:  A, B, X, Y, U
;
; WHAT THE SIX SITES CALL. recompute_channel_byte_24ec ($F7EC) is the WRITER
; of $24EC and switch_channel_latch_bit0 ($F692) is what drives the line from
; it; the two are separate on the instrument and are separate here, because a
; value FORCED into the byte has to survive being driven. A sequence-mode
; entry forces channel 0's (seq_mode_defaults $5224 at $5378) and then wants
; it driven, which is filter_apply alone; a frequency or waveform commit wants
; it derived first, which is this.
; ---------------------------------------------------------------------------
filter_recompute_all
                clrb
filter_recompute_next
                cmpb    #CHANNEL_MAX
                bhs     filter_apply
                pshs    b
                lbsr    channel_valid           ; carry set if not fitted
                bcs     filter_recompute_step
                ldb     ,s
                lbsr    filter_recompute
filter_recompute_step
                puls    b
                incb
                bra     filter_recompute_next

filter_apply
                clrb
filter_apply_next
                cmpb    #CHANNEL_MAX
                lbhs    filter_apply_done
                pshs    b
                lbsr    channel_valid           ; carry set if not fitted
                bcs     filter_apply_skip

                lbsr    filter_bit_for_channel  ; A = the bit's value
                pshs    a                       ; $F692's compare: bit 0 of
                ldb     1,s                     ; the shadow against the
                ldx     #latch_shadow           ; request, and equal means
                lda     b,x                     ; nothing to do
                anda    #LATCH_FILTER
                cmpa    ,s
                puls    a                       ; A = the wanted bit; a PULS
                beq     filter_apply_skip       ; that does not pull CC
                                                ; leaves CMPA's result

                pshs    a
                ldb     1,s
                lbsr    ampl_blank              ; mute across the change,
                puls    a                       ; $F6C0

                inc     >dds_lock               ; THE STORE AND THE CALL
                                                ; ARE ONE OPERATION. An
                                                ; NMI landing between
                                                ; them would leave this
                                                ; writing the sequence
                                                ; player's value into a
                                                ; channel latch; see
                                                ; channel_latch_rmw.
                sta     >latch_bits
                lda     #LATCH_FILTER
                ldb     ,s
                lbsr    channel_latch_rmw
                dec     >dds_lock

                ldb     ,s
                lbsr    ampl_unblank            ; and back, if it was on:
                                                ; $F70B
filter_apply_skip
                puls    b
                incb
                bra     filter_apply_next
filter_apply_done
                rts

; ---------------------------------------------------------------------------
; filter_bit_for_channel - which filter this channel should have
;
;   entry: 0,s = the channel (the caller's saved copy)
;   exit:  A = LATCH_FILTER for Low Overshoot, 0 for Sharp Cutoff
;   uses:  A, B, X, Y, U
;
; Sharp Cutoff and Low Overshoot are the stock's modes 0 and 1, which
; set_output_enable_mode ($F770) writes to the line as they are (lf79f);
; Automatic is its mode 3, the byte recompute_channel_byte_24ec ($F7EC) keeps
; at $24EC+ch, derived in filter_auto_bit. This firmware keeps one setting
; for all four channels where the stock keeps $24E8 per channel (the filter
; screen, filter_store above); the derivation is per channel either way.
; ---------------------------------------------------------------------------
filter_bit_for_channel
                ldb     2,s                     ; the channel it is asked for
                ldx     #filter_mode            ; and that channel's mode, the
                lda     b,x                     ; stock's $24E8+ch
                cmpa    #FILTER_SHARP
                beq     filter_bit_sharp
                cmpa    #FILTER_LOW_OVER
                beq     filter_bit_low

                ; AUTOMATIC READS THE STORED BYTE, which is what the stock
                ; does: $24EC+ch holds the answer and recompute_channel_byte
                ; _24ec ($F7EC) is what writes it. This called the derivation
                ; every time and kept nothing, so a value FORCED into the byte
                ; - which a sequence-mode entry does to channel 0 at $5378 -
                ; had nowhere to live and was undone by the next caller.
                ; filter_recompute below is the writer, and it runs at the six
                ; sites $F7EC runs at.
                ldb     2,s
                ldx     #filter_auto
                abx
                lda     ,x
                rts

; ---------------------------------------------------------------------------
; filter_recompute - derive one channel's filter byte and store it
;
;   entry: B = the channel, 0 to 3
;   uses:  A, B, X, Y, U
;
; recompute_channel_byte_24ec ($F7EC). Its six callers hand it the channel
; whose frequency, waveform, destination or hop state has just changed, and
; every reader takes the byte from then on.
; ---------------------------------------------------------------------------
filter_recompute
                pshs    b
                lbsr    filter_auto_bit         ; A = what it should be
                puls    b
                ldx     #filter_auto
                abx
                sta     ,x
                rts

; ---------------------------------------------------------------------------
; filter_force - drive one channel's filter byte to a chosen value
;
;   entry: A = LATCH_FILTER or zero, B = the channel
;   uses:  B, X
;
; set_channel_byte_24ec ($F713), which seq_mode_defaults ($5224) calls at
; $5378 with index 0 and value 1. The line itself follows on the next
; filter_apply, which the caller runs.
; ---------------------------------------------------------------------------
filter_force
                ldx     #filter_auto
                abx
                sta     ,x
                lbra    filter_apply            ; and the line follows it, as
                                                ; $F713 falls into $F692
filter_bit_low
                lda     #LATCH_FILTER           ; HIGH is Low Overshoot
                rts
filter_bit_sharp
                clra                            ; LOW is Sharp Cutoff
                rts

; ---------------------------------------------------------------------------
; filter_auto_bit - the automatic filter for one channel's socket: $F7EC
;
;   entry: B = the channel, 0 to 3
;   exit:  A = LATCH_FILTER when the stock's byte would be 1, 0 when 0
;   uses:  A, B, X, Y, U
;
; recompute_channel_byte_24ec ($F7EC) takes a destination code and writes one
; byte, $24EC+channel, for the socket that code names. Its six callers -
; $4A5F, $4C97, $6514, $68B2, $7BD2, $7ED8, all on page 0 - hand it the
; changed channel's destination; filter_apply calls this for every fitted
; channel with the channel's own socket code, LBL_OUT1+channel, which
; port_code_to_channel ($C765, called at $F811) maps straight back to the
; channel, so the $FF substitution that exits at $F84B never arises. From
; lf800, instruction by instruction:
;
;   - local 10,s (the byte) starts at 1; local 11,s ('same') is set when the
;     socket equals channel 0's destination $2516 (lf84e LDX 4,S / CMPX 2,S /
;     LDB #$01 / STB 11,S); local 12,s ('any') starts clear (lf85a).
;   - lf85e walks records 0-3 (CMPB #$04 / LBCC lf987). A record whose
;     destination +$21 is $10, Off, is skipped (CMPX #$0010 / LBNE lf88f /
;     LBRA lf97e). One whose destination is the socket counts (lf88f: CMPX
;     4,S / LBEQ lf8d8). Any other is skipped unless port_code_to_channel
;     returns $FF for it - a modulation code, not a socket - AND 'same' is
;     set (CMPD #$00FF / LBNE lf8d5, LDB 11,S / CMPB #$00 / LBEQ lf8d5, LBRA
;     lf8d8): a channel modulating channel 0 counts towards channel 0's
;     socket.
;   - the frequency compared is the record's +0 (lf929, array_element_address
;     with the $FCE0 descriptor), except record 0 while bit 8 of $2202 is set
;     - Freq Hop on, hop_running here - which takes find_max_channel_field
;     ($E962) with 6, the largest hop frequency (lf8d8 to lf8f2, lf8f5).
;     sub24 ($D3C6) of the constant at $EA5F - `xxd -s 0x6a5f -l 3
;     firmware/a2u12.bin` prints 07 a1 20: 500,000 tenths, 50 kHz - minus it
;     returns $FF on a borrow (CMPB #$00 / LBEQ lf926, lf95c): a frequency
;     above 50 kHz clears the byte and ends the walk (CLR 10,S / LBRA lf987).
;   - otherwise a waveform +$1F of 2, 3 or 6 - LBL_RAMP, LBL_TRIANGLE,
;     LBL_SQUARE - sets 'any' (lf95c to lf97a).
;   - lf987: the byte survives as 1 only if 'any' is set, or 'same' is set
;     and $2411 is non-zero - the use count usecount_addr_pulse ($7857) hands
;     out for destination code $0B, Plse, which this firmware, keeping no
;     counters, reads by walking the four CHAN_DEST bytes for LBL_PULSE
;     (lf987 to lf9ba).
;   - $F9BC set_channel_byte_24ec ($F713)(channel, byte) stores it and, when
;     the mode $24E8+channel is 3, drives bit 0 from it through $F692.
;
; The frame here is the stock's locals, pushed: 0,s the record walked (its
; 8,s), 1,s the byte (10,s), 2,s 'any' (12,s), 3,s 'same' (11,s), 4,s the
; socket code (4,s), 5,s the channel asked for (9,s).
; ---------------------------------------------------------------------------
FILTER_FREQ_HI  equ     $07             ; $07A120 = 500,000 tenths of a hertz,
FILTER_FREQ_MID equ     $A1             ; the constant at $EA5F that $F7EC
FILTER_FREQ_LO  equ     $20             ; subtracts each counted frequency from

filter_auto_bit
                pshs    b                       ; the channel
                addb    #LBL_OUT1               ; its socket code, the $F7EC
                pshs    b                       ; argument
                ; THE LIVE ROUTING, NOT THE RECORD. $F7EC reads record+$21
                ; at lf84e and lf881, and record+$21 is the field
                ; set_channel_destination ($78BF) writes as it routes - the
                ; stock keeps the routing and the record in one place. This
                ; firmware splits them: destn_route writes routed_dest and
                ; leaves CHAN_DEST to the caller, deliberately, because the
                ; register-recall path needs the record left alone. Reading
                ; CHAN_DEST here therefore asked a question about a record
                ; that had not been parked yet.
                ;
                ; Measured: at a sequence-mode takeover the park opens all
                ; four relays on both firmwares, but channel D's filter line
                ; stayed in here - latch 5 against the stock's 4 - because
                ; routed_dest already said Off while CHAN_DEST still named
                ; Out4, so the rule counted D as routed to its own socket
                ; and kept the byte at 1. The Digital Sequence entry then
                ; found a filter change to make on D alone, and
                ; filter_apply's ampl_blank / ampl_unblank pair CLOSED the
                ; relay again: differential harness seed 13 step 12,
                ; stock (1,4,4,4) against (1,4,4,0).
                ldx     #routed_dest
                clra
                cmpb    ,x                      ; lf84e: the socket is channel
                bne     filter_auto_frame       ; 0's destination?
                inca
filter_auto_frame
                pshs    a                       ; 'same'
                lda     #$01                    ; the byte starts at 1, 'any'
                clrb                            ; clear
                pshs    a,b
                clrb                            ; record 0 first
                pshs    b
filter_auto_next
                ldb     ,s
                cmpb    #CHANNEL_MAX            ; lf85e CMPB #$04 / LBCC lf987
                bhs     filter_auto_end
                lda     #CHAN_RECORD
                mul
                ldx     #channel_records
                leax    d,x                     ; X = this record, for its
                                                ; frequency and waveform
                pshs    b
                ldb     1,s                     ; and the LIVE routing for
                                                ; its destination, as lf881
                                                ; reads record+$21 - see the
                                                ; note at lf84e above
                lda     #$00
                pshs    x
                ldx     #routed_dest
                abx
                lda     ,x
                puls    x
                puls    b
                cmpa    #LBL_OFF                ; Off: skipped
                beq     filter_auto_step
                cmpa    4,s                     ; lf88f CMPX 4,S: the socket
                beq     filter_auto_count       ; itself counts
                cmpa    #LBL_OUT1               ; port_code_to_channel: $0C to
                blo     filter_auto_mod         ; $0F are sockets, anything
                cmpa    #LBL_OUT4               ; else is $FF
                bls     filter_auto_step        ; another socket: skipped
filter_auto_mod
                tst     3,s                     ; a modulation code counts only
                beq     filter_auto_step        ; while 'same' is set
filter_auto_count
                tst     ,s                      ; lf8d8: record 0 while Freq
                bne     filter_auto_own         ; Hop is on compares the
                tst     >hop_running            ; largest hop frequency
                beq     filter_auto_own
                pshs    x
                lda     #HOP_FREQ               ; lf8f5 $E962 with 6
                lbsr    hop_field_max           ; Y = the largest one
                puls    x
                bra     filter_auto_compare
filter_auto_own
                leay    ,x                      ; lf929: its own +0, CHAN_FREQ
filter_auto_compare                             ; being zero
                lda     #FILTER_FREQ_LO         ; $EA5F minus the frequency,
                suba    2,y                     ; least significant first; a
                lda     #FILTER_FREQ_MID        ; borrow is a frequency above
                sbca    1,y                     ; 50 kHz
                lda     #FILTER_FREQ_HI
                sbca    ,y
                bcs     filter_auto_too_high
                lda     CHAN_WAVE,x             ; lf95c to lf97a: +$1F of 2, 3
                cmpa    #LBL_RAMP               ; or 6 sets 'any'
                beq     filter_auto_any
                cmpa    #LBL_TRIANGLE
                beq     filter_auto_any
                cmpa    #LBL_SQUARE
                bne     filter_auto_step
filter_auto_any
                lda     #$01
                sta     2,s
filter_auto_step
                inc     ,s                      ; lf97e: the next record
                bra     filter_auto_next
filter_auto_too_high
                clr     1,s                     ; CLR 10,S / LBRA lf987
filter_auto_end
                tst     1,s                     ; lf987: a cleared byte stays
                beq     filter_auto_result      ; cleared;
                tst     2,s                     ; 'any' keeps it;
                bne     filter_auto_result
                tst     3,s                     ; so does 'same' with a pulse
                beq     filter_auto_clear       ; modulator present ($2411)
                ldb     #LBL_PULSE
                lbsr    filter_dest_in_use
                bcs     filter_auto_result
filter_auto_clear
                clr     1,s                     ; lf9ba CLR 10,S
filter_auto_result
                lda     1,s                     ; $F9BC $F713: the byte, and
                leas    6,s                     ; the line from it
                tsta
                beq     filter_auto_sharp
                lda     #LATCH_FILTER           ; 1: Low Overshoot
filter_auto_sharp
                rts

; ---------------------------------------------------------------------------
; filter_dest_in_use - does any channel have this destination?
;
;   entry: B = the destination code
;   exit:  carry SET when at least one channel record holds it
;   uses:  A, X
;
; The stock keeps a use count per destination code - usecount_addr_pulse
; ($7857) hands out $2411 for code $0B, Plse - which set_channel_destination
; ($78BF) steps as it writes record+$21, so a count is non-zero exactly when a
; record holds its code. This firmware keeps no counters and walks the four
; CHAN_DEST bytes instead. hop_destn_in_use in page0_hop.s is the same walk
; for the hop screen's three counters; it is on page 0 and this is in the
; always-mapped image, and neither can call the other.
; ---------------------------------------------------------------------------
filter_dest_in_use
                ldx     #channel_records
                lda     #CHANNEL_MAX
                pshs    a
filter_dest_next
                cmpb    CHAN_DEST,x
                beq     filter_dest_found
                leax    CHAN_RECORD,x
                dec     ,s
                bne     filter_dest_next
                puls    a
                andcc   #~CC_CARRY
                rts
filter_dest_found
                puls    a
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; Special Functions.
;
; Fifteen preferences in the stock firmware, of which five are used and ten
; are blank. The five are reproduced here BY NAME rather than by number: the
; stock screen shows "Special Function 0" and the operator needs the manual
; to learn what 0 is.
;
; The names are the stock firmware's own text, read out of page 3.
;
; The three numbers that were NOT preferences - 37, 48 and 87, which opened
; the option list, option install and serial install - are not here. They are
; entries on the Main Selection Level and in the Service menu, where they
; belong, because they are not preferences at all.
; ---------------------------------------------------------------------------
; THE MENU THAT STOOD HERE IS GONE - its title banner, its six records, the
; annotate hook that painted On/Off beside the selected one, and the five
; toggle entry points that hung off them. The instrument's Special Functions
; screen is a NUMBERED ROW and not a scrolling list, so a menu record naming
; one preference each had nothing left to feed. Deleted rather than parked in
; UNREACHED: a record whose screen no longer exists is not a deliberate
; absence, it is the change half done. tests/test_reachable.py found them.

; special_state_show - paint the selected preference's On/Off
;
;   entry: B = which entry
;   uses:  A, B, X
;
; The stock's screen says so in as many words: special_function_screen_render
; ($6966) computes 1 << $3FCD, ANDs it with the flag word $23C1 and writes
; 'On' ($7339) or 'Off' ($733D) beside 'Status ='. This menu had five entries
; that flipped a bit and reported nothing, so the only way to read a
; preference was to toggle it and look for a change somewhere else.
;
; The Back entry has no state, and painting one for it would be a lie.
; ---------------------------------------------------------------------------
SPECIAL_STATE_POS equ   LCD_LINE2+SVC_LABEL_LEN-3
special_state_on  fcc   "On "
special_state_off fcc   "Off"

; THE ROW, forty characters, exactly as the instrument paints it - driven on
; the stock 2026-09-13 and copied character for character, softkey markers
; included: f1 on the number, f2 on the status, f4 on Exit.
special_row     fcb     $00,$01
                fcc     " Special # 0  "
                fcb     $00,$02
                fcc     " Status = Off  "
                fcb     $00,$04
                fcc     " Exit"

; AND THE TEN DESCRIPTIONS, forty characters each, read out of the stock's
; own text block at page 3's d63da and reassembled. Five are named and five
; are blank - the instrument has ten numbers and five functions.
special_texts
                fcc     "# 0  Last state recalled on power up    "
                fcc     "# 1  Disable automatic phase reset      "
                fcc     "# 2  Disable beeper                     "
                fcc     "# 3  Reverse modulating waveform        "
                fcc     "# 4  Disable output blanking            "
                fcc     "# 5                                     "
                fcc     "# 6                                     "
                fcc     "# 7                                     "
                fcc     "# 8                                     "
                fcc     "# 9                                     "

; ===========================================================================
; THE SPECIAL FUNCTIONS SCREEN, and it is not a menu.
;
; This was a scrolling menu with a banner - '*****  SPECIAL FUNCTIONS  *****'
; over one preference at a time - and the instrument's is a NUMBERED ROW.
; Driven on the stock 2026-09-13, shift+LAST from the Main Selection Level:
;
;   line 1  f1 ' Special # 0  '  f2 ' Status = Off  '  f4 ' Exit'
;   line 2  '# 0  Last state recalled on power up    '
;
; NEXT, LAST, UP and DOWN all step the number, and it wraps; f1 selects the
; number field and f2 the status field; with the status field selected, '1'
; then ENTER turns the function ON and '0' then ENTER turns it off - driven,
; the row then reads ' Status = On   '. f2 alone changes nothing, which is
; what a field SELECT does.
;
; The ten descriptions are the stock's own, read out of the text block at
; page 3's d63da and reassembled: forty characters each, five of them named
; and five blank. They are the instrument's words, not this project's - the
; menu that stood here said 'Recall last state on power up' where the
; instrument says '# 0  Last state recalled on power up'.
; ===========================================================================
SPECIAL_COUNT   equ     10              ; # 0 to # 9, as the stock's block has
SPECIAL_NAMED   equ     5               ; and five of them name a function.
                                        ; # 5 to # 9 are numbers with no
                                        ; description and no bit behind them,
                                        ; which is what the instrument's own
                                        ; text block has - five descriptions
                                        ; and five blanks. They show Off and
                                        ; take no value, so nothing has to be
                                        ; invented for them.
SPECIAL_NUM_COL equ     LCD_LINE1+13    ; where the digit sits in the row
SPECIAL_STAT_COL equ    LCD_LINE1+28    ; and where 'Off' / 'On ' does
SPECIAL_FIELD_NUM equ   0
SPECIAL_FIELD_STAT equ  1

; special_screen_open is in modules/remote_tables.s, in the tail after the
; ABI table: the core had no room left under ABI_BASE.

; ---------------------------------------------------------------------------
; special_show - paint both lines
;
;   uses:  A, B, X, Y, U
; ---------------------------------------------------------------------------
special_show
                lda     #LCD_LINE1              ; the row, as a template
                ldx     #special_row
                ldb     #LCD_COLUMNS
                lbsr    lcd_write

                ldb     >special_number         ; the digit into it
                addb    #'0'
                stb     >lcd_shadow+13
                lda     #SPECIAL_NUM_COL
                ldx     #lcd_shadow+13
                ldb     #$01
                lbsr    lcd_write

                lbsr    special_state_now       ; 'On ' or 'Off'
                lda     #SPECIAL_STAT_COL
                ldb     #$03
                lbsr    lcd_write

                ldb     >special_number         ; and the description
                lda     #LCD_COLUMNS
                mul
                ldx     #special_texts
                leax    d,x
                lda     #LCD_LINE2
                ldb     #LCD_COLUMNS
                lbra    lcd_write

; ---------------------------------------------------------------------------
; special_state_now - X = 'On ' or 'Off' for the function showing
;
;   exit:  X = three characters
;   uses:  A, B, X
; ---------------------------------------------------------------------------
special_state_now
                ldb     >special_number
                cmpb    #SPECIAL_NAMED          ; the five that have a bit;
                bhs     special_state_blank     ; # 5 to # 9 have none and the
                lda     #$01                    ; instrument shows them Off
special_state_now_shift
                tstb
                beq     special_state_now_test
                lsla
                decb
                bra     special_state_now_shift
special_state_now_test
                anda    >special_flags
                beq     special_state_blank
                ldx     #special_state_on
                rts
special_state_blank
                ldx     #special_state_off
                rts

; ---------------------------------------------------------------------------
; special_key - the Special Functions screen's keys
;
;   entry: B = the key code
;   uses:  A, B, X, Y, U
;
; Everything is the menu's except the point key, which turns the selected
; preference OFF - entry mode 6's second key. ENTER reaches the entry's own
; handler through menu_key and turns it on.
; ---------------------------------------------------------------------------
; ---------------------------------------------------------------------------
; special_key - a key on the Special Functions screen, and the re-arm after it
;
;   entry: B = the key code
;   uses:  A, B, X
;
; THE CURSOR IS RE-ARMED AFTER EVERY MESSAGE BUT TWO. The tail of
; special_function_screen_handler ($6A25) arms the field $3FCC names -
; the number at $0C (arm at $6CCE) or the state at $1C ($6D01) - for every
; local request code except $16, f4, which leaves, and $26, shifted ENTER.
; A key numeric_entry_key_handler ($B3C2) keeps is not a message and only
; moves the display's address ($B567). special_key_body is the handler.
;
; The number's cell is $0C where this screen paints its one digit at $0D:
; the stock's field is two wide and this row shows the second of them.
; ---------------------------------------------------------------------------
special_key
                pshs    b
                lbsr    special_key_body
                puls    b
                ldx     >screen_handler         ; a key that left the screen
                cmpx    #special_key            ; arms nothing
                bne     special_key_rearm_none
                cmpb    #KEY_S_ENTER            ; $26 leaves before the tail
                beq     special_key_rearm_none
                bsr     special_cell            ; A = $23AD + $23A4
                lbsr    entry_key_is_mapped     ; a message: the tail re-arms
                lbne    entry_cursor_on
                lbra    lcd_cursor              ; a key $B3C2 kept: $B567
special_key_rearm_none
                rts
special_arm
                bsr     special_cell
                lbra    entry_cursor_on         ; $AC98, $ACA6
special_cell
                lda     #SPECIAL_NUM_COL-1      ; $6CCE: $0C
                tst     >special_field
                beq     special_cell_count
                lda     #SPECIAL_STAT_COL       ; $6D01: $1C
special_cell_count
                adda    >entry_count            ; + $23A4
                rts

; ---------------------------------------------------------------------------
; special_key_body - the Special Functions keys, without the re-arm
;
;   entry: B = the key code
;   uses:  A, B, X
; ---------------------------------------------------------------------------
special_key_body
                cmpb    #KEY_NEXT               ; ALL FOUR STEP THE NUMBER, and
                beq     special_key_up          ; they wrap. Driven on the
                cmpb    #KEY_UP                 ; stock: NEXT and UP go 0 -> 1,
                beq     special_key_up          ; LAST and DOWN go back, and
                cmpb    #KEY_LAST               ; from # 0 LAST reaches # 9
                beq     special_key_down
                cmpb    #KEY_DOWN
                beq     special_key_down

                cmpb    #KEY_F1                 ; f1 SELECTS the number field
                beq     special_key_pick_num    ; and f2 the status field.
                cmpb    #KEY_F2                 ; Neither changes a value -
                beq     special_key_pick_stat   ; driven, f2 alone leaves the
                                                ; row exactly as it was
                cmpb    #KEY_F4                 ; Exit, which pops one level
                lbeq    service_back_handler    ; or reopens the Main Selection

                cmpb    #KEY_ENTER              ; and ENTER commits what was
                beq     special_key_enter       ; typed into the status field
                cmpb    #KEY_0                  ; - '1' then ENTER turns the
                beq     special_key_digit       ; function on, '0' then ENTER
                cmpb    #KEY_1                  ; turns it off, which is what
                beq     special_key_digit       ; the instrument does
                cmpb    #KEY_REFRESH
                lbeq    special_show

                cmpb    #KEY_S_FREQ             ; THE SHIFTED KEYS, which
                lbhs    special_key_shifted     ; screen_takes_shift sends
                lbra    key_refuse              ; here: remote_tables.s

special_key_up
                lda     >special_number
                inca
                cmpa    #SPECIAL_COUNT
                blo     special_key_store
                clra
                bra     special_key_store
special_key_down
                lda     >special_number
                bne     special_key_down_one
                lda     #SPECIAL_COUNT
special_key_down_one
                deca
special_key_store
                sta     >special_number
                lbra    special_show

special_key_pick_num
                clr     >special_field
                lbra    special_show
special_key_pick_stat
                lda     #SPECIAL_FIELD_STAT
                sta     >special_field
                lbra    special_show

; THE TYPED DIGIT IS HELD UNTIL ENTER, which is what the instrument does: '1'
; alone leaves the row reading Off and the ENTER after it turns the function
; on. The digit goes in the entry buffer the rest of the tree already uses.
special_key_digit
                lda     >special_field
                cmpa    #SPECIAL_FIELD_STAT
                bne     special_key_ignore      ; the number field takes no
                lda     #ENTRY_DECIMAL          ; digits: f1 selects it and
                pshs    b                       ; the page keys step it
                ldb     #$01
                lbsr    entry_begin
                puls    b
                lbsr    key_digit               ; THE DIGIT, NOT THE KEY CODE.
                bcs     special_key_ignore      ; entry_digit takes 0 to
                lbsr    entry_digit             ; base-1, and the key codes are
                bcs     special_key_refused     ; not the digits - KEY_0 is 15
                lbra    special_show            ; and KEY_1 is 12, so they are
                                                ; not even contiguous
special_key_refused
                ; AND THE REFUSAL IS THE CALLER'S TO ANSWER. entry_digit sets
                ; the carry when the buffer is full or the digit is not one
                ; the field takes, and this threw that away and repainted as
                ; though it had gone in - so a refused key looked accepted
                ; and the operator's next ENTER committed something else.
                ; key_refuse is what every other screen in this tree does
                ; with it, and it is $C3FE's beep and record.
                lbra    key_refuse
special_key_ignore
                rts

special_key_enter
                lbsr    entry_is_open           ; lb494: nothing armed, no ENTER
                beq     special_key_ignore
                lbsr    entry_cursor_off        ; $B5BA, then request $23
                lbsr    special_key_commit      ; and the tail's re-arm
                lbra    special_arm
special_key_commit
                lda     >special_field
                cmpa    #SPECIAL_FIELD_STAT
                bne     special_key_ignore
                tst     >entry_count            ; nothing typed commits nothing
                beq     special_key_ignore
                ldb     >special_number
                cmpb    #SPECIAL_NAMED          ; # 5 to # 9 have no bit
                bhs     special_key_enter_done
                lda     #$01
special_key_enter_shift
                tstb
                beq     special_key_enter_apply
                lsla
                decb
                bra     special_key_enter_shift
special_key_enter_apply
                ldb     >entry_buffer           ; the digit typed, as ASCII
                cmpb    #'0'
                beq     special_key_enter_off
                ora     >special_flags          ; anything else is ON, as the
                sta     >special_flags          ; instrument takes '1'
                bra     special_key_enter_done
special_key_enter_off
                coma
                anda    >special_flags
                sta     >special_flags
special_key_enter_done
                clr     >entry_count
                lbra    special_show

; ---------------------------------------------------------------------------
; special_beeper_enabled - may the instrument beep?
;
;   exit:  carry SET if beeping is allowed
;   uses:  A
;
; Read by error_beep. Preference 2 is "disable the beeper", so the sense is
; inverted here rather than at each call site - one negation in one place
; instead of one per caller, which is one chance to get it backwards instead
; of several.
; ---------------------------------------------------------------------------
; The five preferences, as bit masks. Every one of them controls a behaviour
; this firmware actually has - a switch that changes nothing is the fault
; this rewrite calls out in the stock option bits, and it would be no better
; here.
SPECIAL_KEEP_STATE equ  $01             ; bit 0: recall last state at power on
SPECIAL_NO_PHASE_RESET equ $02          ; bit 1: leave phase alone when the
                                        ;        frequency changes
SPECIAL_NO_BEEP equ     $04             ; bit 2: silence the error beep
SPECIAL_REVERSE_MOD equ $08             ; bit 3: reverse modulating waveforms
SPECIAL_NO_BLANK equ    $10             ; bit 4: do not mute the output while
                                        ;        a parameter is changing

special_beeper_enabled
                lda     >special_flags
                bita    #SPECIAL_NO_BEEP
                bne     special_beeper_off
                orcc    #CC_CARRY
                rts
special_beeper_off
                andcc   #~CC_CARRY
                rts

; ---------------------------------------------------------------------------
; screen_numeric_key - the key handler for a screen with one number on it
;
;   entry: B = the key code
;   uses:  A, B, X, Y, U
;
; Save/Recall, Output On/Off and Output Float all have the same shape: one
; small number is typed and ENTER acts on it. They share this handler and
; differ only in the routine it calls on ENTER, which each screen leaves in
; screen_commit as it paints.
;
; Sharing is worth it because the awkward parts are identical and easy to get
; subtly different: digits have to echo, ENTER with nothing typed must not
; commit a blank, backspace has to work, and any key that means nothing here
; must be ignored rather than beeped at.
;
; BACKSPACE MATTERS on these screens more than most. A register number is two
; digits and an output number is one, so a mis-key is half the entry; without
; a backspace the operator's only recourse is to type past it, which on a
; one-digit field is impossible.
; ---------------------------------------------------------------------------
screen_numeric_key
                cmpb    #KEY_F1                 ; the screen's own extra key,
                bne     screen_numeric_f4       ; where it has one
                ldx     >screen_f1
                beq     screen_numeric_ignore
                jmp     ,x

screen_numeric_f4
                ; F4 IS THE WAY OUT, and it was missing. This handler took
                ; digits, BACKSPACE, ENTER, f1 and f2 and ignored everything
                ; else, so a screen that bound neither softkey to an exit
                ; could be entered and never left from the keypad - only a
                ; power cycle. The serial screen was one, which made the
                ; flat-battery recovery this firmware exists for impossible
                ; to finish: an operator could set the serial and then could
                ; not reach the options screen. The stock puts "f4 Exit" on
                ; both of those screens, so f4 is the key the operator's
                ; fingers already know (firmware/recovery/README.md).
                ;
                ; A screen that wants to stay put leaves screen_f4 zero, so
                ; this costs nothing where an exit would be wrong - the
                ; keyboard diagnostic keeps its LOCAL-twice exit.
                cmpb    #KEY_F4
                bne     screen_numeric_enter_t
                ldx     >screen_f4
                beq     screen_numeric_ignore
                jmp     ,x
                ; NO '.' ARM ANY MORE. The two output screens were the only
                ; screens with a meaning for it, and they are the overlay
                ; output_prompt_key now, which answers '.' itself as the
                ; instrument's OFF (output_onoff_key_handler, $F3F0).
screen_numeric_enter_t
                cmpb    #KEY_ENTER
                beq     screen_numeric_enter
                cmpb    #KEY_BACKSPACE
                beq     screen_numeric_back
                lbsr    key_digit               ; carry clear and B = 0 to 9
                bcs     screen_numeric_ignore
                lbsr    entry_digit
                bcs     screen_numeric_full
                lbra    screen_numeric_echo
screen_numeric_full
                ldb     #ERR_VALUE_TOO_BIG
                lbra    error_raise
screen_numeric_back
                lbsr    entry_backspace
                lbra    screen_numeric_echo
screen_numeric_enter
                ldx     >screen_commit          ; whichever screen is up left
                beq     screen_numeric_ignore   ; its own commit here
                ; A COMMIT ENDS THE ENTRY FIRST AND RE-ARMS IT AFTER. The
                ; instrument's screens built on arm_numeric_entry_field reach
                ; $B5BA (a terminator) or $B586 (a one-character field) before
                ; request $23, and their $23 arms arm the field again when the
                ; screen stays - address_entry_key_handler ($A0D4) at $A17B,
                ; output_onoff_key_handler ($F3F0) at $F4CE and $F517. A commit
                ; that leaves for another screen arms nothing, which is the
                ; installed handler's test below.
                lbsr    entry_cursor_off        ; $B5BA / $B586
                ldx     >screen_commit          ; request $23's commit
                jsr     ,x
screen_numeric_rearm
                ldx     >screen_handler
                cmpx    #screen_numeric_key     ; still this screen?
                bne     screen_numeric_left
                lbra    screen_field_arm        ; and its re-arm
screen_numeric_left
                rts
screen_numeric_ignore
                lbra    key_refuse          ; a key this screen cannot
                                                        ; use is REFUSED, not
                                                        ; ignored; see key_refuse


; ---------------------------------------------------------------------------
; screen_numeric_echo - show the digits typed so far
;
;   uses:  A, B, X, Y
;
; The field's position and width are left in screen_field_pos and
; screen_field_width by the screen that painted it, for the same reason the
; commit routine is: this handler serves three screens and must not know
; which.
; ---------------------------------------------------------------------------
screen_numeric_echo
                ldx     #chan_text
                lbsr    entry_render
                lda     >screen_field_pos
                ldb     >screen_field_width
                ldx     #chan_text
                lbsr    lcd_write_raw           ; the echo: glass only, as
                                                ; lcd_write_string_at ($D8A5)
                lbra    screen_field_cursor     ; $B567: after the last digit

; ---------------------------------------------------------------------------
; screen_field_arm    - the shared field is armed: the cursor on its next cell
; screen_field_cursor - the display's address on that cell, cursor as it is
;
;   uses:  A
;
; The screens on screen_numeric_key and the Save / Recall prompt keep their
; field's first column in screen_field_pos. arm_numeric_entry_field ($AC35)
; puts the cursor on its $23AD at $AC98 and turns it on at $ACA6, local only;
; numeric_entry_key_handler puts it after the typed characters at $B567
; ($23AD + $23A4) after every accepted key. entry_count is $23A4 here, so a
; freshly armed field is its first column and a typed one the column after its
; last digit.
; ---------------------------------------------------------------------------
screen_field_arm
                lda     >screen_field_pos       ; $23AD
                adda    >entry_count            ; + $23A4
                lbra    entry_cursor_on         ; $AC98, $ACA6
screen_field_cursor
                lda     >screen_field_pos       ; $23AD
                adda    >entry_count            ; + $23A4
                lbra    lcd_cursor              ; $B567

; ---------------------------------------------------------------------------
; output_prompt_key - output_onoff_key_handler ($F3F0)
;
;   entry: B = the key code, or RMT_RQ + a request code
;   uses:  A, B, X, Y, U
;
; STAGE ONE is the number, one digit wide, so the digit itself completes the
; entry and posts $23: 1 to the fitted count is echoed at $59 and the ON/OFF
; field armed at $5F ($F484-$F4D3); anything else is $A0 through
; error_report_beep, the digit blanked and the field armed again ($F4D6).
; ENTER or a unit key on it has no arm in accept_units_key ($B0C1) and is
; $B5D0's 2; BACKSPACE has nothing to take back.
;
; STAGE TWO: ENTER is ON and '.' is OFF - the key the entry ends with is
; $221F, ON $11 ($F523) - through set_output_enable ($B79C) or
; output_latch_bit1_set ($B6EF), and the overlay goes ($F574-$F59B). A unit
; key is 2 again; a digit, BACKSPACE or MINUS finds a field with no digits and
; is dropped.
;
; ANY OTHER KEY OR REQUEST dismisses the overlay and goes on to the screen
; underneath, with $18 recorded while remote ($F3FC-$F43B).
;
; Driven on the stock: ENTER, the unit keys, '.' and MINUS on stage one were
; not all separately exercised - ENTER is 2 and BACKSPACE nothing, which is
; what the arms above give the rest.
; ---------------------------------------------------------------------------
output_prompt_key
                cmpb    #RMT_RQ
                bhs     output_prompt_foreign
                cmpb    #KEY_REFRESH
                lbeq    output_prompt_paint
                cmpb    #KEY_INVALID
                bhs     output_prompt_ignore
                tst     >output_stage
                bne     output_prompt_second
                cmpb    #KEY_BACKSPACE
                beq     output_prompt_ignore
                cmpb    #KEY_ENTER
                beq     output_prompt_no_arm
                cmpb    #KEY_DEG
                beq     output_prompt_no_arm
                cmpb    #KEY_HZ
                beq     output_prompt_no_arm
                cmpb    #KEY_KHZ
                beq     output_prompt_no_arm
                cmpb    #KEY_POINT
                beq     output_prompt_no_arm
                cmpb    #KEY_MINUS
                beq     output_prompt_no_arm
                pshs    b
                lbsr    key_digit               ; carry clear and B = 0 to 9
                bcc     output_prompt_digit
                puls    b
                bra     output_prompt_foreign
output_prompt_second
                cmpb    #KEY_ENTER
                lbeq    output_prompt_on
                cmpb    #KEY_POINT
                lbeq    output_prompt_off
                cmpb    #KEY_DEG
                beq     output_prompt_no_arm
                cmpb    #KEY_HZ
                beq     output_prompt_no_arm
                cmpb    #KEY_KHZ
                beq     output_prompt_no_arm
                cmpb    #KEY_BACKSPACE
                beq     output_prompt_ignore
                cmpb    #KEY_MINUS
                beq     output_prompt_ignore
                pshs    b
                lbsr    key_digit
                puls    b                       ; PULS leaves CC alone
                bcc     output_prompt_ignore    ; no digits in this field
output_prompt_foreign
                pshs    b
                lbsr    register_prompt_dismiss
                lda     >rmt_flags
                bita    #RF_REMOTE
                beq     output_prompt_hand
                ldb     #ERR_CHAIN_NO_FUNC      ; $F407: $18 through $9DD3
                lbsr    error_record
output_prompt_hand
                puls    b
                ldx     >screen_handler         ; and on, unchanged, to the
                beq     output_prompt_ignore    ; screen underneath
                jmp     ,x
output_prompt_no_arm
                ldb     #ERR_KEY_ENTRY          ; $B5D0's 2
                lbra    error_raise
output_prompt_ignore
                rts
output_prompt_digit
                leas    1,s                     ; the key code is done with
                tstb
                beq     output_prompt_bad       ; output 0
                decb
                lbsr    channel_valid           ; $F477 CMPB >$23B2
                bcs     output_prompt_bad
                stb     >output_channel
                lda     #$01                    ; $F4B1: $3A7D = 1
                sta     >output_stage
                addb    #'1'
                stb     >chan_text
                lda     #OUT_FIELD1_POS         ; $F49E: the digit at $59
                ldb     #$01
                ldx     #chan_text
                lbsr    output_prompt_raw
                lda     #OUT_FIELD2_POS         ; $F4B6: the second field
                sta     >screen_field_pos
                clr     >screen_field_width
                lda     #ENTRY_DECIMAL
                clrb
                lbsr    entry_begin
                lbsr    screen_field_arm
                lbra    overlay_abandon_held    ; $F4D3 returns 1: $3C
output_prompt_bad
                ldb     #ERR_OUTPUT_NUMBER      ; $F4D6: $A0 through $C3FE
                lbsr    error_raise
                lda     #' '                    ; $F4E4: $59 blanked
                sta     >chan_text
                lda     #OUT_FIELD1_POS
                ldb     #$01
                ldx     #chan_text
                lbsr    output_prompt_raw
                lda     #ENTRY_DECIMAL          ; $F517: the field again
                ldb     #$01
                lbsr    entry_begin
                lbsr    screen_field_arm
                lbra    overlay_abandon_held    ; $F51C returns 1: $3C
output_prompt_on
                clra                            ; CLEAR IS ON: both relays are
                bra     output_prompt_switch    ; active low
output_prompt_off
                lda     >screen_bit
output_prompt_switch
                pshs    a
                lbsr    entry_cursor_off        ; $B5BA before the $23
                puls    a
                inc     >dds_lock               ; THE STORE AND THE CALL ARE
                sta     >latch_bits             ; ONE OPERATION: an NMI between
                lda     >screen_bit             ; them would write the sequence
                ldb     >output_channel         ; player's value into this latch
                lbsr    channel_latch_rmw
                dec     >dds_lock
                ldb     >output_channel
                lbsr    chan_state_sync         ; the record agrees with the
                lbsr    led_output_refresh      ; relay, and the lamps with it
                lbsr    register_prompt_dismiss ; $F585: the glass back
                ldb     #KEY_ABANDON            ; $F597 returns 1: $3C to the
                ldx     >screen_handler         ; screen that is back
                lbeq     output_prompt_ignore
                jmp     ,x

; ---------------------------------------------------------------------------
; output_prompt_paint - both lines and the digit taken, raw, local only
; output_prompt_raw   - lcd_write_raw, local only
;
;   entry (raw): A = the position, B = how many, X = the characters
;   uses:  A, B, X, Y
;
; RAW, as $F5F4-$F658 writes with lcd_write_string_at ($D8A5): the shadow keeps
; the screen underneath for register_prompt_dismiss to put back. While remote
; $F5BC skips the painting altogether.
; ---------------------------------------------------------------------------
output_prompt_paint
                lda     >rmt_flags
                bita    #RF_REMOTE
                lbne     output_prompt_ignore
                lda     #SCREEN_LINE1           ; $F5F4: forty spaces
                ldx     #output_blank_line
                ldb     #LCD_COLUMNS
                lbsr    lcd_write_line_raw
                ldx     #output_onoff_title
                lda     >screen_bit
                cmpa    #LATCH_OUTPUT
                beq     output_prompt_paint_title
                ldx     #output_float_title
output_prompt_paint_title
                lda     #OUT_TITLE_POS
                ldb     #OUT_TITLE_W
                lbsr    lcd_write_raw
                lda     #SCREEN_LINE2           ; $F644
                ldx     #output_enter_prompt
                ldb     #LCD_COLUMNS
                lbsr    lcd_write_line_raw
                tst     >output_stage
                beq     output_prompt_paint_done
                lda     >output_channel         ; a repaint keeps the digit
                adda    #'1'
                sta     >chan_text
                lda     #OUT_FIELD1_POS
                ldb     #$01
                ldx     #chan_text
                lbsr    lcd_write_raw
output_prompt_paint_done
                lbra    screen_field_cursor
output_prompt_raw
                pshs    a
                lda     >rmt_flags
                bita    #RF_REMOTE
                puls    a                       ; PULS leaves CC alone
                lbne     output_prompt_ignore
                lbra    lcd_write_raw

