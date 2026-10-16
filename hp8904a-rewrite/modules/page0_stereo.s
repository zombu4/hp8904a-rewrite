; ===========================================================================
; page0_stereo.s - the FM Stereo Composite screen, ported from HP's own
;
; HP part 08904-87011 carries this screen in bank 5. This is a port of it,
; read out of that ROM and written up in docs/stereo-trace.md,
; docs/stereo-abi.md and docs/stereo-exponent.md. It replaces an invented
; five-preset module that DSB-modulated a 38 kHz carrier; HP has no modulator
; anywhere in this screen, so that design was wrong at the root.
;
; HP'S ARCHITECTURE, in one line: four independent generators. The 38 kHz
; subcarrier is synthesised as two explicit sidebands at carrier+tone and
; carrier-tone, 90 and 270 degrees apart, alongside the 19 kHz pilot and the
; audio tone. They sum in the analogue domain.
;
; WHAT IS HERE AND WHAT IS OUTSTANDING. The screen, its parameter block and
; the commit are all here: editing a field or cycling a choice programs all
; four channels, and so does opening the screen. What is outstanding is the
; preemphasis scale - stereo_ladder marks the one point it attaches to, and
; until it exists the Off case is exactly right and the three time constants
; read Off's behaviour. HP behaves identically with its own field set to Off,
; so the gap is a missing scale rather than a wrong structure.
;
; THE PARAMETER BLOCK is HP's, at $3C01 in its RAM, 51 bytes. Ours holds the
; same values in scratch (scratch.inc, the st_* names), less HP's six
; step-size fields, which are a declared absence rather than an oversight.
; Every default below was read out of HP's ROM at $4174-$41A6, which is the
; block the screen entry at $42D2 copies on a cold open.
;
; THE LAYOUT DIFFERS FROM HP'S, deliberately and for one mechanical reason.
; format_places (text.s) always emits nine characters - eight digits and a
; point - so six numeric fields would need 54 of the 80 columns before a
; single label. HP's simultaneous nine-field layout cannot be drawn with this
; renderer. Instead the three choice fields, which change what the other six
; MEAN, are permanently on line 1, and the selected numeric field gets the
; full width of line 2.
;
; RANGES. The tone's 200 to 150000 is HP's own, from the limit pointers it
; loads at $5584 - $4171 holds 200 and $416E holds 150000. HP's limits for the
; pilot and carrier frequencies are NOT established, so those use this
; instrument's own ceiling through ABI_freq_in_range rather than a number
; invented to look like HP's.
;
; KEYS. UP and DOWN move between the nine fields, wrapping. NEXT and LAST
; cycle the selected field when it is a choice, and are refused on a numeric
; one. Digits go into the shared entry; ENTER commits, and on a frequency
; field so do Hz and kHz, and on the phase field so does deg. Shift NEXT
; leaves, which boot.s dispatches to main_menu_open before any screen sees it.
; ===========================================================================

; --- the fields -----------------------------------------------------------
;
; Ordered so that a single compare answers each question a routine asks:
; below STF_WIDE the value is 24 bits, below STF_NUMERIC it is a number at
; all, and at or above that it is a choice.
STF_TONE        equ     0               ; tone frequency, 0.1 Hz
STF_COMP        equ     1               ; composite amplitude, microvolts
STF_PFREQ       equ     2               ; pilot frequency, 0.1 Hz
STF_CFREQ       equ     3               ; carrier frequency, 0.1 Hz
STF_WIDE        equ     4               ; fields below here are 24-bit
STF_PAMPL       equ     4               ; pilot amplitude, tenths of a percent
STF_PPHASE      equ     5               ; pilot phase, tenths of a degree
STF_NUMERIC     equ     6               ; fields below here take digits
STF_MODE        equ     6               ; Off / R = L / R =-L / R only/L only
STF_PRE         equ     7               ; Off / 25 / 50 / 75
STF_PILOT       equ     8               ; the pilot on or off
STF_FIELDS      equ     9

STF_NAME_LEN    equ     9               ; the field name on line 2
STF_UNIT_LEN    equ     4               ; its unit, beside the value
STF_VALUE_LEN   equ     9               ; what format_places always writes
STF_ENTRY_LEN   equ     8               ; and what the shared entry holds

STF_NAME_POS    equ     LCD_LINE2+0
STF_VALUE_POS   equ     LCD_LINE2+10
STF_UNIT_POS    equ     LCD_LINE2+20

; HP's tone limits, from the pointers $5584 loads into $3C43 and $3C41.
STF_TONE_MIN_HI equ     $00             ; $4171 = 200 = 20.0 Hz
STF_TONE_MIN_MID equ    $00
STF_TONE_MIN_LO equ     $C8
STF_TONE_MAX_HI equ     $02             ; $416E = 150000 = 15000.0 Hz
STF_TONE_MAX_MID equ    $49
STF_TONE_MAX_LO equ     $F0

STF_PAMPL_MAX   equ     1000            ; tenths of a percent, HP's $03E8
                                        ; compare inside $BE6C

; The two sideband phases, in tenths of a degree, from the literals HP loads
; at $52CD and $52D2. Which sideband leads and which lags is the whole of the
; difference between R only and L only.
STF_PHASE_LEAD  equ     900             ; 90.0 degrees
STF_PHASE_LAG   equ     2700            ; 270.0 degrees

; The channels, fixed by what each generator is for.
STF_CH_UPPER    equ     0               ; carrier + tone
STF_CH_LOWER    equ     1               ; carrier - tone
STF_CH_PILOT    equ     2               ; the 19 kHz pilot
STF_CH_TONE     equ     3               ; the audio tone

; Which rung of the amplitude ladder a mode puts on the sidebands and on the
; tone. Indices into stereo_ladder_ptr: 0 silent, 1 full, 2 half, 3 quarter.
STF_MODE_OFF    equ     0
STF_MODE_RL     equ     1               ; R = L
STF_MODE_RNL    equ     2               ; R =-L
STF_MODE_RONLY  equ     3
STF_MODE_LONLY  equ     4
STF_MODES       equ     5

; ---------------------------------------------------------------------------
; stereo_open - the mode entry point, reached through this page's $400A vector
;
;   entry: U = the entry reason: MODE_COLD, MODE_RECALL or MODE_KEEP
;   uses:  A, B, X, Y, U
;
; HP's own entry at $42D2 takes an argument choosing between loading the ROM
; defaults at $4174 and restoring the last edits from its saved copy at $257C,
; which its save arm writes (bank 5 $5C46 -> $58D5) and every register carries.
; This is that. From the Main Selection the defaults go in, as argument 0 does.
; On a recall, register_stereo_unstage (registers.s) has already put the
; slot's nineteen parameters back; on a keep-state power-on reset_entry's
; frame has carried them through the boot; either way they stand.
;
; IT IS RE-ENTERED, by the architect's ruling of 2026-09-16
; - a register saved here recalls here, and a keep-state
; power-on comes back here. A recall applies the register first, as each
; stock mode does on reason 1 - register_restore has run the preset and the
; copy and left the hardware to the mode - and a keep-state power-on has been
; applied by boot_keep_state. The screen has no records, so the saved record
; is zero.
; ---------------------------------------------------------------------------
stereo_open
                cmpu    #MODE_RECALL
                beq     stereo_open_recall
                cmpu    #MODE_KEEP
                beq     stereo_open_kept
                bra     stereo_open_defaults
stereo_open_recall
                lbsr    ABI_register_apply
stereo_open_kept
                ; AND THE PARAMETERS STAND, as $42D2 restores them on 1 and
                ; leaves them on 2: register_stereo_unstage has put a recalled
                ; slot's back, and reset_entry's frame a kept power-on's. The
                ; three choices index tables, so each is held against its own
                ; count first; one past it means the bytes are not a setting
                ; this screen wrote, and the defaults go in instead.
                lda     >st_mode
                cmpa    >stereo_choice_count
                bhs     stereo_open_defaults
                lda     >st_preemph
                cmpa    >stereo_choice_count+1
                bhs     stereo_open_defaults
                lda     >st_pilot_on
                cmpa    >stereo_choice_count+2
                bhs     stereo_open_defaults
                bra     stereo_open_field
stereo_open_defaults
                lbsr    stereo_defaults
stereo_open_field
                clr     >active_record
                clr     >st_field               ; and on the first field, for
                                                ; the same reason
                lbsr    stereo_apply            ; the instrument matches what
                                                ; the screen says on entry, as
                                                ; HP's $42D2 does through
                                                ; $6021 and $5FF0
                lbra    stereo_show

; ---------------------------------------------------------------------------
; stereo_defaults - copy HP's ROM defaults into the parameter block
;
;   uses:  A, B, X, Y
;
; stereo_default_block below is HP's $4174-$41A6 with the step fields dropped,
; in this file's field order rather than HP's block order. Copied as bytes
; because the block is not word-aligned: four 24-bit values, then two 16-bit,
; then three single bytes.
; ---------------------------------------------------------------------------
stereo_defaults
                ldx     #stereo_default_block
                ldy     #st_tone
                ldb     #STF_BLOCK_LEN
stereo_defaults_byte
                lda     ,x+
                sta     ,y+
                decb
                bne     stereo_defaults_byte
                rts

; ---------------------------------------------------------------------------
; stereo_show - install the handler and paint both lines
;
;   uses:  A, B, X, Y, U
;
; screen_install first, as every screen does, so a key can never reach the
; previous screen's handler against this screen's display. It also clears
; entry_active, which is what makes an abandoned entry on another screen
; harmless here.
; ---------------------------------------------------------------------------
stereo_show
                ldx     #stereo_key
                lbsr    ABI_screen_install

                lda     #LCD_LINE1
                ldx     #stereo_line1
                ldb     #LCD_COLUMNS
                lbsr    ABI_lcd_write
                lda     #LCD_LINE2
                ldx     #stereo_line2
                ldb     #LCD_COLUMNS
                lbsr    ABI_lcd_write

                lbsr    stereo_entry_arm
                lbsr    stereo_choices_show
                lbsr    stereo_field_show
                lbra    stereo_cursor_arm       ; the field armed after the paint

; ---------------------------------------------------------------------------
; stereo_choices_show - the three choice fields on line 1
;
;   uses:  A, B, X, Y, U
;
; Written whenever any of them changes. Each is a fixed-width slot in the
; template, so the write is the slot's own width and never a whole line -
; which is also what keeps this routine outside test_screens_take_keys.py's
; definition of a screen, since it paints no full line.
; ---------------------------------------------------------------------------
stereo_choices_show
                ldb     #STF_MODE
                lbsr    stereo_choice_show
                ldb     #STF_PRE
                lbsr    stereo_choice_show
                ldb     #STF_PILOT
                lbra    stereo_choice_show

; ---------------------------------------------------------------------------
; stereo_choice_show - one choice field's text, in its slot on line 1
;
;   entry: B = the field, STF_MODE, STF_PRE or STF_PILOT
;   uses:  A, B, X, Y, U
;
; The parallel tables are indexed by the field's distance above STF_NUMERIC,
; so adding a fourth choice means adding one row to each of them.
; ---------------------------------------------------------------------------
stereo_choice_show
                subb    #STF_NUMERIC            ; 0, 1 or 2
                pshs    b                       ; the row, kept at 0,s

                aslb
                ldu     #stereo_choice_value
                ldu     b,u                     ; U -> where the index lives

                ldb     ,s                      ; the field's text table, into
                aslb                            ; Y, BEFORE the multiply: MUL
                ldy     #stereo_choice_text     ; leaves the product in D and
                ldy     b,y                     ; the row index is needed to
                                                ; find the table, so reading
                                                ; it back afterwards would
                                                ; overwrite the product's low
                                                ; byte - which it did, and
                                                ; showed as a garbled Pre and
                                                ; Pilot while Mode, at row
                                                ; zero, looked correct
                ldb     ,s
                ldx     #stereo_choice_len
                lda     b,x                     ; A = this field's text width
                ldb     ,u                      ; B = the chosen index
                mul                             ; D = index * width
                leay    d,y                     ; Y -> the chosen row

                ldb     ,s
                ldx     #stereo_choice_len
                ldb     b,x                     ; B = the width to write
                puls    a                       ; A = the row
                pshs    b
                ldx     #stereo_choice_pos
                lda     a,x                     ; A = the DDRAM address
                puls    b
                tfr     y,x                     ; X = the text to write
                lbra    ABI_lcd_write

; ---------------------------------------------------------------------------
; stereo_field_show - line 2: the selected field's name, value and unit
;
;   uses:  A, B, X, Y, U
;
; A choice field has no value to show, so the value and unit slots are blanked
; and the cursor goes to the choice's own slot on line 1. That is what makes
; the two lines one screen rather than two: the thing being edited is always
; the thing under the cursor.
; ---------------------------------------------------------------------------
stereo_field_show
                ldb     >st_field
                lda     #STF_NAME_LEN
                mul
                ldx     #stereo_name
                leax    d,x
                lda     #STF_NAME_POS
                ldb     #STF_NAME_LEN
                lbsr    ABI_lcd_write

                lbsr    stereo_mark_comp

                ldb     >st_field
                cmpb    #STF_NUMERIC
                bhs     stereo_field_show_choice

                lbsr    stereo_value_show
                lbsr    stereo_unit_show
                lda     #STF_VALUE_POS
                lbra    ABI_lcd_cursor

stereo_field_show_choice
                lda     #STF_VALUE_POS          ; nothing to show in the value
                ldb     #STF_VALUE_LEN          ; slot, and leaving the last
                lbsr    ABI_lcd_blank           ; field's digits there would
                lda     #STF_UNIT_POS           ; read as this field's
                ldb     #STF_UNIT_LEN
                lbsr    ABI_lcd_blank

                ldb     >st_field
                subb    #STF_NUMERIC
                ldx     #stereo_choice_pos
                lda     b,x
                lbra    ABI_lcd_cursor

; ---------------------------------------------------------------------------
; stereo_value_show - the selected numeric field's value, with its point
;
;   uses:  A, B, X, Y, U
;
; format_places wants a 24-bit value, so a 16-bit field is widened into
; st_work first - the same move page0_channel.s makes for CHAN_PHASE, and for
; the same reason.
; ---------------------------------------------------------------------------
stereo_value_show
                ldb     >st_field
                lbsr    stereo_field_pointer    ; U = the value
                cmpb    #STF_WIDE
                blo     stereo_value_wide

                ldd     ,u                      ; 16-bit: widen it into the
                std     >chan_work+1            ; shared 24-bit work area, the
                clr     >chan_work              ; same move page0_channel.s
                ldu     #chan_work              ; makes for CHAN_PHASE
stereo_value_wide
                ldb     >st_field
                ldx     #stereo_places
                ldb     b,x                     ; B = the decimal places
                lbsr    ABI_format_places
                lda     #STF_VALUE_POS
                ldx     #chan_text
                ldb     #STF_VALUE_LEN
                lbra    ABI_lcd_write

; ---------------------------------------------------------------------------
; stereo_unit_show - the unit beside the value
;
;   uses:  A, B, X, Y, U
; ---------------------------------------------------------------------------
stereo_unit_show
                ldb     >st_field
                lda     #STF_UNIT_LEN
                mul
                ldx     #stereo_unit
                leax    d,x
                lda     #STF_UNIT_POS
                ldb     #STF_UNIT_LEN
                lbra    ABI_lcd_write

; ---------------------------------------------------------------------------
; stereo_field_pointer - where a field's value lives
;
;   entry: B = the field
;   exit:  U = the value, B unchanged
;   uses:  A, U
; ---------------------------------------------------------------------------
stereo_field_pointer
                pshs    b
                aslb
                ldu     #stereo_value_ptr
                ldu     b,u
                puls    b
                rts

; ---------------------------------------------------------------------------
; stereo_key - the key handler
;
;   entry: B = the key code
;   uses:  A, B, X, Y, U
;
; UP and DOWN move between fields; NEXT and LAST cycle a choice. Moving ends
; any entry in progress, which is the defect chan_field_store exists to stop:
; typing 100 into one field, moving, and typing 5 gave 1005.
; ---------------------------------------------------------------------------
stereo_key
                ; THE SAVE KEY AND WHAT ITS PROMPT LEAVES BEHIND, as every
                ; mode the instrument has answers them - Channel
                ; Configuration's chan_key_save is l5dd9 and its abandon arm
                ; l5d22. This screen had neither, so SHIFT DOWN and the bus's
                ; SV were refused here ($2B) and no register could be saved on
                ; FM Stereo, which the architect's ruling of 2026-09-16 recalls
                ; to.
                cmpb    #RMT_RQ+$21
                bne     stereo_key_not_save
                clr     >entry_active           ; the open entry closes
                lbra    ABI_save_prompt_open    ; $F331 with $0021
stereo_key_not_save
                cmpb    #KEY_ABANDON
                bne     stereo_key_not_abandon
                clr     >entry_active
                rts
stereo_key_not_abandon
                cmpb    #KEY_DOWN
                beq     stereo_key_forward
                cmpb    #KEY_UP
                beq     stereo_key_back
                cmpb    #KEY_NEXT
                lbeq    stereo_key_cycle_up
                cmpb    #KEY_LAST
                lbeq    stereo_key_cycle_down
                cmpb    #KEY_ENTER
                lbeq    stereo_commit
                cmpb    #KEY_BACKSPACE
                beq     stereo_key_erase
                cmpb    #KEY_REFRESH
                lbeq    stereo_show
                lbra    stereo_key_unit

stereo_key_forward
                ldb     >st_field
                incb
                cmpb    #STF_FIELDS
                blo     stereo_key_store
                clrb
                bra     stereo_key_store
stereo_key_back
                ldb     >st_field
                tstb
                bne     stereo_key_back_one
                ldb     #STF_FIELDS
stereo_key_back_one
                decb
stereo_key_store
                stb     >st_field
                clr     >entry_active           ; MOVING ENDS THE ENTRY
                lbsr    stereo_entry_arm
                lbsr    stereo_field_show
                lbra    stereo_cursor_arm       ; the field armed after the paint

stereo_key_erase
                lbsr    ABI_entry_backspace
                lbra    stereo_echo

; ---------------------------------------------------------------------------
; stereo_key_cycle_up - step a choice field forward, wrapping
;
;   uses:  A, B, X, Y, U
;
; Refused on a numeric field rather than silently ignored: a key that does
; nothing and says nothing is how an operator concludes the instrument is
; broken.
; ---------------------------------------------------------------------------
stereo_key_cycle_up
                ldb     >st_field
                cmpb    #STF_NUMERIC
                blo     stereo_key_refuse
                lbsr    stereo_choice_pointer   ; U = the index byte
                ldb     >st_field
                subb    #STF_NUMERIC
                ldx     #stereo_choice_count
                ldb     b,x                     ; B = how many it has
                lda     ,u
                inca
                pshs    b
                cmpa    ,s
                blo     stereo_cycle_put
                clra
                bra     stereo_cycle_put

; ---------------------------------------------------------------------------
; stereo_key_cycle_down - step a choice field back, wrapping
;
;   uses:  A, B, X, Y, U
; ---------------------------------------------------------------------------
stereo_key_cycle_down
                ldb     >st_field
                cmpb    #STF_NUMERIC
                blo     stereo_key_refuse
                lbsr    stereo_choice_pointer
                ldb     >st_field
                subb    #STF_NUMERIC
                ldx     #stereo_choice_count
                ldb     b,x
                pshs    b
                lda     ,u
                tsta
                bne     stereo_cycle_down_one
                lda     ,s
stereo_cycle_down_one
                deca
stereo_cycle_put
                leas    1,s                     ; drop the count
                sta     ,u
                lbsr    stereo_apply            ; mode, preemphasis and the
                                                ; pilot each change what is
                                                ; programmed, not only what is
                                                ; shown
                ldb     >st_field
                lbsr    stereo_choice_show
                lbra    stereo_field_show

stereo_key_refuse
                lbra    ABI_key_refuse

; ---------------------------------------------------------------------------
; stereo_choice_pointer - where a choice field's index byte lives
;
;   entry: B = the field, at or above STF_NUMERIC
;   exit:  U = the byte
;   uses:  A, B, U
; ---------------------------------------------------------------------------
stereo_choice_pointer
                subb    #STF_NUMERIC
                aslb
                ldu     #stereo_choice_value
                ldu     b,u
                rts

; ---------------------------------------------------------------------------
; stereo_key_unit - digits, and the unit keys that terminate an entry
;
;   entry: B = the key code
;   uses:  A, B, X, Y, U
;
; Hz and kHz commit a frequency field, deg commits the phase field, and each
; is refused on a field it does not belong to rather than folding a decade
; into a value that has no decade. The other numeric fields commit on ENTER
; with the raw count, which is what page0_channel.s does and what
; test_parity_old_new.py records the rewrite doing.
; ---------------------------------------------------------------------------
stereo_key_unit
                cmpb    #KEY_HZ
                beq     stereo_unit_hz
                cmpb    #KEY_KHZ
                beq     stereo_unit_khz
                cmpb    #KEY_DEG
                beq     stereo_unit_deg

                lbsr    ABI_key_digit           ; carry clear and B = 0 to 9
                bcs     stereo_key_refuse
                pshs    b                       ; the digit
                ldb     >st_field
                cmpb    #STF_NUMERIC
                blo     stereo_key_digit_ok
                puls    b
                bra     stereo_key_refuse       ; a choice takes no digits
stereo_key_digit_ok
                puls    b
                lbsr    ABI_entry_digit
                bcs     stereo_key_full
                lda     #$01
                sta     >entry_active
                lbra    stereo_echo
stereo_key_full
                ldb     #ERR_VALUE_TOO_BIG
                lbra    ABI_error_record

stereo_unit_hz
                ldb     >st_field
                lbsr    stereo_is_frequency
                bcs     stereo_key_refuse
                ldb     #UNIT_HZ
                lbra    stereo_commit_unit
stereo_unit_khz
                ldb     >st_field
                lbsr    stereo_is_frequency
                bcs     stereo_key_refuse
                ldb     #UNIT_KHZ
                lbra    stereo_commit_unit
stereo_unit_deg
                ldb     >st_field
                cmpb    #STF_PPHASE
                bne     stereo_key_refuse
                ldb     #UNIT_DEG
                lbra    stereo_commit_unit

; ---------------------------------------------------------------------------
; stereo_is_frequency - is this field one of the three frequencies?
;
;   entry: B = the field
;   exit:  carry CLEAR if it is
;   uses:  none
; ---------------------------------------------------------------------------
stereo_is_frequency
                cmpb    #STF_TONE
                beq     stereo_is_frequency_yes
                cmpb    #STF_PFREQ
                beq     stereo_is_frequency_yes
                cmpb    #STF_CFREQ
                beq     stereo_is_frequency_yes
                orcc    #CC_CARRY
                rts
stereo_is_frequency_yes
                andcc   #~CC_CARRY
                rts

; ---------------------------------------------------------------------------
; stereo_echo - redraw the field being typed into
;
;   uses:  A, B, X, Y, U
;
; The typed digits, not the stored value: until ENTER the two differ, and
; showing the stored one would make the keypad look dead.
; ---------------------------------------------------------------------------
stereo_echo
                ldx     #chan_text
                lbsr    ABI_entry_render
                lda     #STF_VALUE_POS
                ldx     #chan_text
                ldb     #STF_ENTRY_LEN
                lbsr    ABI_lcd_write_raw       ; the echo: glass only, as
                                                ; lcd_write_string_at ($D8A5)
                lda     #STF_VALUE_POS
                lbra    ABI_lcd_cursor

; ---------------------------------------------------------------------------
; stereo_entry_arm - start a fresh entry on the selected field
;
;   uses:  A, B
; ---------------------------------------------------------------------------
; ---------------------------------------------------------------------------
; stereo_cursor_arm - a numeric field armed: the cursor on it
;
;   uses:  A, B
;
; The FM stereo screen is the architect's addition and has no stock
; counterpart, so its cursor follows the instrument's rule for every field it
; does have: on when a field is armed from the panel, after the painter
; ($AC98 lcd_set_cursor, $ACA6 lcd_display_control(0), local only), and off
; when a terminator ends the entry ($B5BA). The choice fields take no
; digits and arm nothing, as stereo_entry_arm arms nothing for them.
; ---------------------------------------------------------------------------
stereo_cursor_arm
                ldb     >st_field
                cmpb    #STF_NUMERIC            ; a choice field: no entry, no
                bhs     stereo_cursor_arm_none  ; cursor
                lda     #STF_VALUE_POS          ; $23AD
                lbra    ABI_entry_cursor_on     ; $AC98, $ACA6
stereo_cursor_arm_none
                rts

stereo_entry_arm
                ldb     >st_field
                cmpb    #STF_NUMERIC
                bhs     stereo_entry_arm_done
                lda     #ENTRY_DECIMAL
                ldb     #STF_ENTRY_LEN
                lbsr    ABI_entry_begin

                ; AND THE UNIT GOES WHEN TYPING STARTS, as it does in every
                ; numeric field the instrument has: $B524-$B538 writes blanks
                ; over the units label the first time a key is accepted, as
                ; wide as the units class says and at the column the field was
                ; armed with. This screen has no stock counterpart - it is the
                ; addition the architect ordered - so the width is its own
                ; STF_UNIT_LEN rather than one of the $AD3A classes, and the
                ; column is where stereo_show writes the unit.
                lda     #STF_UNIT_POS
                ldb     #STF_UNIT_LEN
                lbra    ABI_entry_units
stereo_entry_arm_done
                rts

; ---------------------------------------------------------------------------
; stereo_commit - ENTER on the selected field
;
;   uses:  A, B, X, Y, U
;
; A choice field has nothing to commit - it is already stored the moment it is
; cycled - so ENTER on one is not an error, it is a repaint.
; ---------------------------------------------------------------------------
stereo_commit
                ldb     >st_field
                cmpb    #STF_NUMERIC
                lbhs    stereo_field_show
                clrb                            ; no unit key: the raw count
                lbra    stereo_commit_unit

; ---------------------------------------------------------------------------
; stereo_commit_unit - validate the typed digits and store them
;
;   entry: B = a UNIT_ code, or zero for the field's own raw unit
;   uses:  A, B, X, Y, U
;
; IT STORES AND NOTHING ELSE. No channel is programmed here: that is pass 2.
; The order is the tree's - value, then unit, then range, then store - and a
; refusal at any step leaves the parameter block exactly as it was.
; ---------------------------------------------------------------------------
stereo_commit_unit
                lbsr    ABI_entry_cursor_off    ; $B5BA: the terminator ends it
                pshs    b
                tst     >entry_count            ; nothing typed: re-arm and
                beq     stereo_commit_rearm     ; repaint, as page0_channel
                                                ; does, so ENTER on an
                                                ; untouched field is harmless

                lbsr    ABI_entry_value
                bcs     stereo_commit_too_big

                puls    b
                tstb                            ; zero means the raw count
                beq     stereo_commit_ranged
                ldx     #entry_result
                lbsr    ABI_unit_apply
                bcs     stereo_commit_refused   ; unit_apply recorded why

stereo_commit_ranged
                lbsr    stereo_in_range
                bcs     stereo_commit_refused   ; and so did the checker
                lbsr    stereo_store
                lbsr    stereo_apply            ; and it reaches the chip
                lbsr    stereo_entry_arm
                lbsr    stereo_field_show
                lbra    stereo_cursor_arm       ; and re-armed after the commit

stereo_commit_rearm
                leas    1,s
                lbsr    stereo_entry_arm
                lbsr    stereo_field_show
                lbra    stereo_cursor_arm       ; and re-armed after the commit

stereo_commit_too_big
                leas    1,s
                ldb     #ERR_VALUE_TOO_BIG
                lbsr    ABI_error_record
                lbra    stereo_commit_drop

; ---------------------------------------------------------------------------
; stereo_commit_refused - a rejected entry, with the field left as it was
;
;   uses:  A, B, X, Y, U
;
; The checker has already recorded which error it was. This drops the digits
; and redraws what is ACTUALLY stored - not what was typed, because leaving
; the rejected digits on screen is how an operator walks away believing the
; instrument took them.
; ---------------------------------------------------------------------------
stereo_commit_refused
                lbsr    ABI_error_beep
stereo_commit_drop
                clr     >entry_active
                lbsr    stereo_entry_arm
                lbsr    stereo_field_show
                lbra    stereo_cursor_arm       ; and re-armed after the commit

; ---------------------------------------------------------------------------
; stereo_in_range - is entry_result acceptable for the selected field?
;
;   exit:  carry SET if it is not, and the error is recorded
;   uses:  A, B, X, Y, U
;
; The tone's bounds are HP's own. The pilot and carrier frequencies go through
; this instrument's ceiling instead, because HP's limits for those two are not
; established and inventing a pair that looked like HP's would be worse than
; using one that is real.
; ---------------------------------------------------------------------------
stereo_in_range
                ldb     >st_field
                cmpb    #STF_TONE
                lbeq    stereo_range_tone
                cmpb    #STF_COMP
                lbeq    stereo_range_comp
                cmpb    #STF_PAMPL
                lbeq    stereo_range_pampl
                cmpb    #STF_PPHASE
                lbeq    stereo_range_pphase
                lbra    stereo_range_freq       ; pilot and carrier

stereo_range_tone
                ldx     #entry_result
                ldu     #stereo_tone_min
                lbsr    stereo_below            ; below the floor?
                lbcs    stereo_range_freq_bad
                ldx     #stereo_tone_max
                ldu     #entry_result
                lbsr    stereo_below            ; above the ceiling?
                bcs     stereo_range_freq_bad
                ldx     #st_cfreq               ; and the sidebands this tone
                ldu     #entry_result           ; would put on the two channels
                bra     stereo_range_sides

stereo_range_freq
                ldx     #channel_records        ; channel 0's ceiling, on the
                ldu     #entry_result           ; typed frequency itself
                lbsr    ABI_freq_in_range
                bne     stereo_range_freq_bad
                ldb     >st_field               ; the PILOT is not a carrier
                cmpb    #STF_CFREQ              ; and produces no sidebands
                lbne    stereo_range_ok
                ldx     #entry_result           ; the carrier being typed,
                ldu     #st_tone                ; against the tone as it stands
                bra     stereo_range_sides
stereo_range_freq_bad
                ldb     #ERR_FREQ_RANGE
                lbsr    ABI_error_record
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; stereo_range_sides - would these two produce sidebands the chip can carry?
;
;   entry: X -> the carrier to test, U -> the tone to test, both 24-bit
;   exit:  carry CLEAR if both sidebands are inside channel 0's ceiling;
;          carry SET, with ERR_FREQ_RANGE recorded, if either is not
;   uses:  A, B, X, U
;
; WHAT REACHES THE CHIP IS THE SUM AND THE DIFFERENCE, not the number typed.
; stereo_sidebands programs carrier + tone on one channel and carrier - tone
; on the other, and neither was bounded by anything: 15000.0 Hz of tone on a
; 100.0 Hz carrier borrowed out of bit 23 and programmed 16,628,216 tenths -
; 1.66 MHz, nearly three times the instrument's top frequency - while a
; 600 kHz carrier with the same tone put 615 kHz on the upper channel. The
; typed value passing its own ceiling says nothing about either.
;
; There is no stock arm to read: this screen is an addition the owner ordered
; (see this file's header), so what it is held to is the instrument's own
; frequency ceiling, the one channel 0 carries and that every other frequency
; field is checked against. st_freq is the working cell stereo_sidebands
; rebuilds from st_cfreq on every apply, so using it here costs nothing.
; ---------------------------------------------------------------------------
stereo_range_sides
                pshs    u,x                     ; 0,s the carrier, 2,s the tone
                ldx     #st_freq
                ldu     ,s
                lbsr    ABI_copy24
                ldx     #st_freq
                ldu     2,s
                lbsr    ABI_add24               ; the upper sideband
                bcs     stereo_range_sides_bad  ; past 24 bits outright
                ldx     #channel_records
                ldu     #st_freq
                lbsr    ABI_freq_in_range
                bne     stereo_range_sides_bad

                ldx     #st_freq
                ldu     ,s
                lbsr    ABI_copy24
                ldx     #st_freq
                ldu     2,s
                lbsr    ABI_sub24               ; and the lower, which must not
                bcs     stereo_range_sides_bad  ; go below zero
                leas    4,s
                andcc   #~CC_CARRY
                rts
stereo_range_sides_bad
                leas    4,s
                bra     stereo_range_freq_bad

stereo_range_comp
                ldx     #stereo_ampl_max
                ldu     #entry_result
                lbsr    stereo_below
                bcc     stereo_range_ok
                ldb     #ERR_AMPL_RANGE
                lbsr    ABI_error_record
                orcc    #CC_CARRY
                rts

stereo_range_pampl
                lda     >entry_result           ; a 16-bit field: anything in
                bne     stereo_range_pampl_bad  ; the top byte is already out
                ldd     >entry_result+1
                cmpd    #STF_PAMPL_MAX
                bls     stereo_range_ok
stereo_range_pampl_bad
                ldb     #ERR_VALUE_RANGE
                lbsr    ABI_error_record
                orcc    #CC_CARRY
                rts

stereo_range_pphase
                lda     >entry_result
                bne     stereo_range_pphase_bad
                ldd     >entry_result+1
                cmpd    #TOP_PHASE
                bls     stereo_range_ok
stereo_range_pphase_bad
                ldb     #ERR_PHASE_RANGE
                lbsr    ABI_error_record
                orcc    #CC_CARRY
                rts

stereo_range_ok
                andcc   #~CC_CARRY
                rts

; ---------------------------------------------------------------------------
; stereo_below - is one 24-bit value below another?
;
;   entry: X = the smaller candidate, U = the larger
;   exit:  carry SET when [X] < [U]
;   uses:  A
;
; Byte-serial from the top, because the tree has no 24-bit compare and a
; subtract would need somewhere to put the answer.
; ---------------------------------------------------------------------------
stereo_below
                lda     ,x
                cmpa    ,u
                blo     stereo_below_yes
                bhi     stereo_below_no
                lda     1,x
                cmpa    1,u
                blo     stereo_below_yes
                bhi     stereo_below_no
                lda     2,x
                cmpa    2,u
                blo     stereo_below_yes
stereo_below_no
                andcc   #~CC_CARRY
                rts
stereo_below_yes
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; stereo_store - put the accepted value into the parameter block
;
;   uses:  A, B, X, Y, U
; ---------------------------------------------------------------------------
stereo_store
                ldb     >st_field
                lbsr    stereo_field_pointer    ; U = the destination
                cmpb    #STF_WIDE
                blo     stereo_store_wide
                ldd     >entry_result+1         ; 16-bit: the low two bytes
                std     ,u
                rts
stereo_store_wide
                lda     >entry_result
                sta     ,u
                ldd     >entry_result+1
                std     1,u
                rts

; ---------------------------------------------------------------------------
; stereo_apply - program all four channels from the parameter block
;
;   uses:  A, B, X, Y, U
;
; HP's order, and the steps are not interchangeable:
;
;   $B971(0,0)   mute Output 1 while the levels move
;   the four channels, in any order
;   $DF06()      ONE commit strobe, LAST
;   $B971(0,1)   unmute
;
; THE STROBE IS WHAT MAKES THE PHASES MEAN ANYTHING. Until it runs, phases
; programmed on different channels have no defined relation to each other, so
; it happens once and it happens last. dds_phase_reset_now rather than
; dds_phase_reset, because special function 1 vetoes the latter and a stereo
; composite whose two sidebands sit at an arbitrary relative phase is not a
; stereo composite.
;
; THE BURST DOES NOT HOLD dds_lock. Each leaf routine takes its own for the
; few instructions it spends staging a register. Holding it across the whole
; burst would silence the sequence player for the 11 ms of settles this
; carries, and each player's body clears the timer-2 flag BEFORE it tests the
; lock -
; so a tick deferred is a tick lost, not a tick delayed.
; ---------------------------------------------------------------------------
stereo_apply
                lbsr    stereo_ladder

                ldb     #STF_CH_UPPER
                lbsr    ABI_ampl_blank          ; HP's $B971(0, 0)

                lda     >st_exp                 ; ONE range for all four
                ldb     #STF_CH_UPPER           ; channels. ampl_level_apply
                lbsr    ABI_ampl_range_write    ; would write one per channel:
                                                ; four ranges and 24 ms of
                                                ; settle instead of 6

                lbsr    stereo_sidebands
                lbsr    stereo_pilot
                lbsr    stereo_tone

                lbsr    ABI_dds_phase_reset_now ; HP's $DF06, once and last
                ldb     #STF_CH_UPPER
                lbra    ABI_ampl_unblank

; ---------------------------------------------------------------------------
; stereo_ladder - split the composite the way HP's $6437 and $63E8 do
;
;   uses:  A, B, X, Y, U
;
;   st_mant, st_exp  the composite as a twelve-bit mantissa and a range
;   st_share         the pilot's share, mantissa * pilot percent / 1000
;   st_audio         what is left for the audio
;   st_pre           the audio after preemphasis
;   st_half          st_pre / 2
;   st_quarter       st_pre / 4, rounded up when the low two bits are both set
;
; WHERE PREEMPHASIS ATTACHES. st_pre takes the audio unscaled, which is
; exactly what HP does when the field reads Off - $63E8 copies $3C39 straight
; into $3C3B. So the Off case is already right, and what the three time
; constants need is a scale applied at this one point rather than any change
; to the structure around it.
; ---------------------------------------------------------------------------
stereo_ladder
                ldu     #st_comp
                lbsr    ABI_ampl_scale          ; X = mantissa, B = exponent
                stx     >st_mant
                stb     >st_exp

                ldd     >st_pampl
                cmpd    #STF_PAMPL_MAX
                beq     stereo_ladder_all       ; 100.0% is the whole of it,
                                                ; and q16_div1000 takes 0..999
                lbsr    ABI_ampl_q16_div1000    ; X = percent / 1000, Q16
                ldd     >st_mant
                lbsr    ABI_ampl_fixmul_hi      ; X = round(mantissa * that)
                bra     stereo_ladder_share
stereo_ladder_all
                ldx     >st_mant
stereo_ladder_share
                stx     >st_share

                ldd     >st_mant
                subd    >st_share
                std     >st_audio
                std     >st_pre
                lbsr    stereo_preemph          ; which scales st_pre, or
                                                ; leaves it alone when the
                                                ; field reads Off

                ldd     >st_pre                 ; RELOADED: the scale above
                lsra                            ; clobbers D, and the half and
                rorb                            ; quarter come off the SCALED
                std     >st_half                ; audio, not the raw one
                lsra
                rorb
                std     >st_quarter

                ldb     >st_pre+1               ; HP rounds the quarter up
                andb    #$03                    ; when the audio's low two
                cmpb    #$03                    ; bits are both set, at $6423
                bne     stereo_ladder_done
                ldd     >st_quarter
                addd    #$0001
                std     >st_quarter
stereo_ladder_done
                rts

; ---------------------------------------------------------------------------
; stereo_sidebands - channels 0 and 1, the subcarrier as two carriers
;
;   uses:  A, B, X, Y, U
;
; THERE IS NO MODULATOR. The 38 kHz subcarrier is carrier+tone and
; carrier-tone programmed as two independent generators 90 and 270 degrees
; apart, and the entire difference between R only and L only is which of the
; two gets which phase.
;
; freq_program returns B holding $08+channel rather than the channel, so the
; channel is reloaded before every call rather than carried across one.
; ---------------------------------------------------------------------------
stereo_sidebands
                ldx     #st_freq                ; the upper sideband
                ldu     #st_cfreq
                lbsr    ABI_copy24
                ldx     #st_freq
                ldu     #st_tone
                lbsr    ABI_add24
                ldu     #st_freq
                ldb     #STF_CH_UPPER
                lbsr    ABI_freq_program

                ldx     #st_freq                ; and the lower
                ldu     #st_cfreq
                lbsr    ABI_copy24
                ldx     #st_freq
                ldu     #st_tone
                lbsr    ABI_sub24
                ldu     #st_freq
                ldb     #STF_CH_LOWER
                lbsr    ABI_freq_program

                lbsr    stereo_side_ampl        ; both take the same rung
                pshs    x
                ldb     #STF_CH_UPPER
                lbsr    ABI_ampl_program
                puls    x
                ldb     #STF_CH_LOWER
                lbsr    ABI_ampl_program

                lda     >st_mode
                cmpa    #STF_MODE_LONLY
                beq     stereo_sidebands_swap
                ldx     #STF_PHASE_LEAD
                ldb     #STF_CH_UPPER
                lbsr    stereo_phase_put
                ldx     #STF_PHASE_LAG
                ldb     #STF_CH_LOWER
                lbra    stereo_phase_put
stereo_sidebands_swap
                ldx     #STF_PHASE_LAG          ; L only: the two exchange,
                ldb     #STF_CH_UPPER           ; and nothing else about the
                lbsr    stereo_phase_put        ; mode differs from R only
                ldx     #STF_PHASE_LEAD
                ldb     #STF_CH_LOWER
                lbra    stereo_phase_put

; ---------------------------------------------------------------------------
; stereo_pilot - channel 2, the 19 kHz pilot
;
;   uses:  A, B, X, Y, U
;
; Its amplitude is gated by the pilot field, which is SEPARATE from the mode:
; HP's $3C17 at $538B, not $3C15. A mode that silences the sidebands leaves
; the pilot alone, and switching the pilot off leaves the mode alone.
; ---------------------------------------------------------------------------
stereo_pilot
                ldu     #st_pfreq
                ldb     #STF_CH_PILOT
                lbsr    ABI_freq_program

                ldx     #$0000
                tst     >st_pilot_on
                beq     stereo_pilot_put
                ldx     >st_share
stereo_pilot_put
                ldb     #STF_CH_PILOT
                lbsr    ABI_ampl_program

                ldx     >st_pphase              ; the operator's own phase,
                ldb     #STF_CH_PILOT           ; HP's $52BF
                lbra    stereo_phase_put

; ---------------------------------------------------------------------------
; stereo_tone - channel 3, the audio tone
;
;   uses:  A, B, X, Y, U
;
; ITS PHASE IS NOT PROGRAMMED. HP does set channel 3's phase, from a
; per-channel record field, but no instruction anywhere in its 128K writes
; that field: the mechanism is established and the value is not. Putting
; something invented there would be worse than leaving it, so it is left.
; ---------------------------------------------------------------------------
stereo_tone
                ldu     #st_tone
                ldb     #STF_CH_TONE
                lbsr    ABI_freq_program
                lbsr    stereo_main_ampl
                ldb     #STF_CH_TONE
                lbra    ABI_ampl_program

; ---------------------------------------------------------------------------
; stereo_phase_put - one channel's phase, from tenths of a degree
;
;   entry: X = tenths of a degree, B = the channel
;   uses:  A, B, X, Y, U
;
; phase_to_code, not phase_to_code_offset and not phase_apply: this screen
; wants the literal 900 and 2700 on the chip, with no modulator offset added
; and no 3600-minus-phase negation applied.
; ---------------------------------------------------------------------------
stereo_phase_put
                pshs    b
                lbsr    ABI_phase_to_code
                puls    b
                lbra    ABI_phase_program

; ---------------------------------------------------------------------------
; stereo_side_ampl - what the two sidebands take, by mode
; stereo_main_ampl - and what the tone takes
;
;   exit:  X = the amplitude
;   uses:  A, B, X
;
; Both counterintuitive results live in these two tables, and neither is a
; mistake. R = L silences the SIDEBANDS, because the difference signal is zero
; and everything belongs in the main channel. R =-L silences the TONE, because
; the sum is zero. R only and L only silence nothing at all: they differ only
; in the sideband phases, which stereo_sidebands handles.
; ---------------------------------------------------------------------------
stereo_side_ampl
                ldx     #stereo_mode_side
                bra     stereo_ampl_pick
stereo_main_ampl
                ldx     #stereo_mode_main
stereo_ampl_pick
                ldb     >st_mode
                cmpb    #STF_MODES
                blo     stereo_ampl_ok
                clrb                            ; a wild mode reads as Off
stereo_ampl_ok
                ldb     b,x                     ; the ladder rung it names
                aslb
                ldx     #stereo_ladder_ptr
                ldx     b,x
                ldx     ,x
                rts

; ---------------------------------------------------------------------------
; stereo_preemph - scale the audio share by the preemphasis curve
;
;   uses:  A, B, X, Y, U
;
; st_pre arrives holding the unscaled audio share and leaves holding it scaled
; by g(tone frequency) for the selected time constant.
;
; WITH THE FIELD OFF IT IS LEFT EXACTLY AS IT CAME, which is what HP does: its
; $63E8 copies $3C39 into $3C3B unchanged when $3C16 is zero. So Off is not a
; special case bolted on here, it is the same behaviour arrived at the same
; way.
;
; g is read from a Q16 table indexed by the tone frequency shifted right nine,
; with the remaining nine bits interpolated linearly between one entry and the
; next. The product of the step and the fraction cannot reach 2^24 - the
; largest step is under 200 and the fraction is under 512 - so the shift right
; nine is taken as the product's middle two bytes and one further shift, with
; no 32-bit arithmetic, which this tree does not have.
; ---------------------------------------------------------------------------
stereo_preemph
                ldb     >st_preemph
                beq     stereo_preemph_off

                decb                            ; 1, 2, 3 -> 0, 1, 2
                aslb
                ldx     #stereo_pre_tabs
                ldx     b,x                     ; X = this tau's table

                ldd     >st_tone                ; the index is tone >> 9: the
                lsra                            ; top two bytes are tone >> 8,
                rorb                            ; and one more shift makes it
                aslb                            ; nine. Then two bytes per
                rola                            ; entry.
                leax    d,x                     ; X -> the entry below f

                ldd     2,x                     ; the step to the entry above
                subd    ,x
                std     >st_work
                ldd     ,x                      ; and g at the entry below
                pshs    d

                ldb     >st_tone+1              ; the fraction, tone & $1FF
                andb    #$01
                tfr     b,a
                ldb     >st_tone+2
                tfr     d,x                     ; X = the fraction
                ldd     >st_work                ; D = the step
                lbsr    ABI_mul16               ; into math_product

                ldd     >math_product+1         ; the product >> 8 ...
                lsra                            ; ... and once more is >> 9
                rorb
                addd    ,s++                    ; + g at the entry below
                tfr     d,x                     ; X = g, interpolated

                ldd     >st_pre                 ; and the audio takes it
                lbsr    ABI_ampl_fixmul_hi
                stx     >st_pre
stereo_preemph_off
                rts

; ---------------------------------------------------------------------------
; stereo_mark_comp - bracket the composite readout while preemphasis is on
;
;   uses:  A, B, X
;
; HP writes an asterisk either side of the Composite AMPTD figure whenever the
; preemphasis field is not Off - $44B5, taking the character from $4142. What
; it marks is that the number on show is no longer the number delivered: the
; audio has been scaled by the curve, so the composite the operator keyed is
; not what comes out.
;
; HP puts them at columns $50 and $59, which are its own layout's columns. Ours
; differs, for the reason the file header gives, so they go either side of this
; layout's value slot. The marking is the point; the column number is not.
;
; IT WRITES A BLANK WHEN IT DOES NOT WRITE AN ASTERISK, rather than returning
; early. The two columns sit outside the name, value and unit slots, so nothing
; else ever paints over them, and a mark left behind by a previous field would
; sit there claiming something untrue about this one.
; ---------------------------------------------------------------------------
stereo_mark_comp
                ldx     #stereo_mark_blank
                ldb     >st_field
                cmpb    #STF_COMP
                bne     stereo_mark_put
                tst     >st_preemph
                beq     stereo_mark_put
                ldx     #stereo_mark_star
stereo_mark_put
                pshs    x
                lda     #STF_VALUE_POS-1
                ldb     #$01
                lbsr    ABI_lcd_write
                puls    x
                lda     #STF_VALUE_POS+STF_VALUE_LEN
                ldb     #$01
                lbra    ABI_lcd_write

; --- the tables ------------------------------------------------------------

; HP's $4174-$41A6 defaults, its step fields dropped, in this file's field
; order: tone, composite, pilot frequency, carrier frequency, pilot amplitude,
; pilot phase, mode, preemphasis, pilot on. Read out of bank 5 rather than
; copied from a document.
stereo_default_block
                fcb     $00,$27,$10             ; tone      10000 = 1.0 kHz
                fcb     $0F,$42,$40             ; composite 1000000 uV = 1 V
                fcb     $02,$E6,$30             ; pilot     190000 = 19.0 kHz
                fcb     $05,$CC,$60             ; carrier   380000 = 38.0 kHz
                fdb     100                     ; pilot amplitude 10.0 %
                fdb     0                       ; pilot phase 0.0 degrees
                fcb     $00                     ; mode Off
                fcb     $00                     ; preemphasis Off
                fcb     $01                     ; pilot on
; 3+3+3+3 for the four frequencies and the composite, 2+2 for the two 16-bit
; fields, 1+1+1 for the three choices. Taken from the location counter rather
; than written out: this was the literal 19 while asm6809.py evaluated `*` in
; an equ one byte short, which docs/asm6809-star-fix.md records and fixes.
STF_BLOCK_LEN   equ     *-stereo_default_block

stereo_value_ptr
                fdb     st_tone,st_comp,st_pfreq,st_cfreq
                fdb     st_pampl,st_pphase
                fdb     st_mode,st_preemph,st_pilot_on

stereo_places   fcb     1,6,1,1                 ; 0.1 Hz, microvolts as volts
                fcb     1,1                     ; tenths of a percent, degree
                fcb     0,0,0                   ; the choices show no number

stereo_name     fcc     "Tone FREQ"
                fcc     "Comp AMPL"
                fcc     "Plt  FREQ"
                fcc     "Carr FREQ"
                fcc     "Plt  AMPL"
                fcc     "Plt PHASE"
                fcc     "Mode     "
                fcc     "Preemph  "
                fcc     "Pilot    "

stereo_unit     fcc     "Hz  "
                fcc     "V   "
                fcc     "Hz  "
                fcc     "Hz  "
                fcc     "%   "
                fcc     "deg "

; Which rung of the ladder each mode puts on the sidebands, and on the tone.
; From HP's $52C7: mode 0 leaves both silent, 1 gives the tone the lot, 2
; gives each sideband a half and silences the tone, 3 and 4 give each sideband
; a quarter and the tone a half.
stereo_mode_side
                fcb     0,0,2,3,3
stereo_mode_main
                fcb     0,1,0,2,2

; Rung 0 is silence, and it needs an address like the others so the lookup has
; no special case.
stereo_zero     fdb     $0000
stereo_ladder_ptr
                fdb     stereo_zero,st_pre,st_half,st_quarter

; HP's own character, from $4142, and the blank that unmarks it.
stereo_mark_star  fcb   $2A
stereo_mark_blank fcb   $20

stereo_tone_min fcb     STF_TONE_MIN_HI,STF_TONE_MIN_MID,STF_TONE_MIN_LO
stereo_tone_max fcb     STF_TONE_MAX_HI,STF_TONE_MAX_MID,STF_TONE_MAX_LO
stereo_ampl_max fcb     TOP_AMPL_HI,TOP_AMPL_MID,TOP_AMPL_LO

; The choice fields, indexed by field minus STF_NUMERIC.
stereo_choice_value
                fdb     st_mode,st_preemph,st_pilot_on
stereo_choice_count
                fcb     5,4,2
stereo_choice_len
                fcb     6,3,3
stereo_choice_pos
                fcb     LCD_LINE1+5,LCD_LINE1+16,LCD_LINE1+26
stereo_choice_text
                fdb     stereo_mode_text,stereo_pre_text,stereo_pilot_text

; HP's own wording, from the strings its screen indexes at $4F7C and $4F9F.
stereo_mode_text
                fcc     "Off   "
                fcc     "R = L "
                fcc     "R =-L "
                fcc     "R only"
                fcc     "L only"
stereo_pre_text
                fcc     "Off"
                fcc     " 25"
                fcc     " 50"
                fcc     " 75"
stereo_pilot_text
                fcc     "Off"
                fcc     "On "

; --- the preemphasis curves ---------------------------------------------------
;
; g(f) = sqrt(A + (1-A) * u^2), with u = f/15000 and A = 1/(1+(2*pi*15000*tau)^2).
; That is algebraically identical to HP's
;   sqrt(1 + (2*pi*f*tau)^2) / sqrt(1 + (2*pi*15000*tau)^2)
; and it needs no square root of a sum at run time, because the whole curve is
; tabulated. The derived normalisers reproduce the three IEEE-754 constants in
; HP's ROM at $5152, $5162 and $5172 to nine significant figures, which is what
; establishes that these are HP's curves and not merely plausible ones.
;
; Q16, indexed by the tone frequency shifted right 9, 294 entries each, with
; linear interpolation on the remaining 1ff. Worst error over all 149,801 legal
; tone frequencies is 0.54 counts of a 12-bit code - under one count, which is
; the hardware's own resolution. A finer table buys almost nothing: below this
; the floor is the entries' own Q16 rounding. The measurement is in
; docs/stereo-port-status.md and the precedent for stating it is
; ampl_deg_to_code in amplitude.s.
;
; g never exceeds 1, so the scaled audio can never exceed the unscaled audio
; and the ladder below it cannot overflow.
stereo_pre_tabs
                fdb     stereo_pre25_tab,stereo_pre50_tab,stereo_pre75_tab

stereo_pre25_tab
                fdb     $6404,$6405,$6407,$640B,$6411,$6418,$6422,$642C
                fdb     $6439,$6447,$6456,$6468,$647B,$648F,$64A6,$64BD
                fdb     $64D7,$64F2,$650F,$652D,$654D,$656E,$6591,$65B6
                fdb     $65DC,$6604,$662E,$6658,$6685,$66B3,$66E3,$6714
                fdb     $6746,$677A,$67B0,$67E7,$681F,$6859,$6895,$68D2
                fdb     $6910,$6950,$6991,$69D4,$6A18,$6A5D,$6AA4,$6AEC
                fdb     $6B35,$6B80,$6BCC,$6C1A,$6C69,$6CB9,$6D0A,$6D5D
                fdb     $6DB1,$6E06,$6E5C,$6EB4,$6F0D,$6F67,$6FC2,$701F
                fdb     $707C,$70DB,$713B,$719C,$71FF,$7262,$72C6,$732C
                fdb     $7393,$73FA,$7463,$74CD,$7538,$75A4,$7611,$767F
                fdb     $76EE,$775D,$77CE,$7840,$78B3,$7927,$799B,$7A11
                fdb     $7A87,$7AFF,$7B77,$7BF0,$7C6A,$7CE5,$7D61,$7DDE
                fdb     $7E5B,$7ED9,$7F58,$7FD8,$8059,$80DA,$815D,$81E0
                fdb     $8263,$82E8,$836D,$83F3,$847A,$8501,$8589,$8612
                fdb     $869B,$8726,$87B0,$883C,$88C8,$8955,$89E2,$8A70
                fdb     $8AFF,$8B8E,$8C1E,$8CAF,$8D40,$8DD2,$8E64,$8EF7
                fdb     $8F8A,$901E,$90B3,$9148,$91DD,$9273,$930A,$93A1
                fdb     $9439,$94D1,$956A,$9603,$969D,$9737,$97D2,$986D
                fdb     $9909,$99A5,$9A41,$9ADE,$9B7C,$9C1A,$9CB8,$9D57
                fdb     $9DF6,$9E95,$9F35,$9FD6,$A077,$A118,$A1B9,$A25C
                fdb     $A2FE,$A3A1,$A444,$A4E7,$A58B,$A630,$A6D4,$A779
                fdb     $A81F,$A8C4,$A96A,$AA11,$AAB7,$AB5E,$AC06,$ACAD
                fdb     $AD55,$ADFE,$AEA6,$AF4F,$AFF9,$B0A2,$B14C,$B1F6
                fdb     $B2A1,$B34C,$B3F7,$B4A2,$B54E,$B5F9,$B6A6,$B752
                fdb     $B7FF,$B8AC,$B959,$BA06,$BAB4,$BB62,$BC10,$BCBF
                fdb     $BD6E,$BE1D,$BECC,$BF7B,$C02B,$C0DB,$C18B,$C23C
                fdb     $C2EC,$C39D,$C44E,$C500,$C5B1,$C663,$C715,$C7C7
                fdb     $C879,$C92C,$C9DF,$CA92,$CB45,$CBF8,$CCAC,$CD5F
                fdb     $CE13,$CEC8,$CF7C,$D030,$D0E5,$D19A,$D24F,$D304
                fdb     $D3BA,$D46F,$D525,$D5DB,$D691,$D747,$D7FE,$D8B4
                fdb     $D96B,$DA22,$DAD9,$DB90,$DC48,$DCFF,$DDB7,$DE6F
                fdb     $DF27,$DFDF,$E097,$E150,$E208,$E2C1,$E37A,$E433
                fdb     $E4EC,$E5A5,$E65F,$E718,$E7D2,$E88C,$E946,$EA00
                fdb     $EABA,$EB74,$EC2F,$ECEA,$EDA4,$EE5F,$EF1A,$EFD5
                fdb     $F090,$F14C,$F207,$F2C3,$F37E,$F43A,$F4F6,$F5B2
                fdb     $F66E,$F72B,$F7E7,$F8A3,$F960,$FA1D,$FADA,$FB96
                fdb     $FC53,$FD10,$FDCE,$FE8B,$FF48,$FFFF

stereo_pre50_tab
                fdb     $3524,$3526,$352B,$3534,$3540,$3550,$3563,$357A
                fdb     $3594,$35B2,$35D3,$35F8,$361F,$364A,$3679,$36AB
                fdb     $36E0,$3718,$3753,$3791,$37D3,$3817,$385F,$38A9
                fdb     $38F7,$3947,$399A,$39F0,$3A48,$3AA4,$3B01,$3B62
                fdb     $3BC5,$3C2A,$3C92,$3CFC,$3D68,$3DD7,$3E48,$3EBB
                fdb     $3F31,$3FA8,$4022,$409D,$411B,$419A,$421B,$429E
                fdb     $4323,$43AA,$4432,$44BC,$4548,$45D5,$4664,$46F4
                fdb     $4786,$4819,$48AD,$4943,$49DB,$4A73,$4B0D,$4BA8
                fdb     $4C45,$4CE2,$4D81,$4E21,$4EC2,$4F64,$5007,$50AB
                fdb     $5150,$51F6,$529D,$5345,$53EE,$5498,$5543,$55EE
                fdb     $569A,$5748,$57F6,$58A4,$5954,$5A04,$5AB5,$5B67
                fdb     $5C19,$5CCC,$5D80,$5E34,$5EE9,$5F9F,$6055,$610C
                fdb     $61C3,$627B,$6334,$63ED,$64A6,$6561,$661B,$66D6
                fdb     $6792,$684E,$690A,$69C7,$6A85,$6B43,$6C01,$6CC0
                fdb     $6D7F,$6E3E,$6EFE,$6FBF,$707F,$7140,$7202,$72C4
                fdb     $7386,$7448,$750B,$75CE,$7692,$7755,$7819,$78DE
                fdb     $79A2,$7A67,$7B2D,$7BF2,$7CB8,$7D7E,$7E45,$7F0B
                fdb     $7FD2,$8099,$8161,$8228,$82F0,$83B8,$8481,$8549
                fdb     $8612,$86DB,$87A4,$886E,$8937,$8A01,$8ACB,$8B95
                fdb     $8C60,$8D2A,$8DF5,$8EC0,$8F8B,$9057,$9122,$91EE
                fdb     $92BA,$9386,$9452,$951F,$95EB,$96B8,$9785,$9852
                fdb     $991F,$99EC,$9ABA,$9B87,$9C55,$9D23,$9DF1,$9EBF
                fdb     $9F8D,$A05B,$A12A,$A1F9,$A2C7,$A396,$A465,$A534
                fdb     $A604,$A6D3,$A7A3,$A872,$A942,$AA12,$AAE2,$ABB2
                fdb     $AC82,$AD52,$AE22,$AEF3,$AFC3,$B094,$B165,$B235
                fdb     $B306,$B3D7,$B4A8,$B57A,$B64B,$B71C,$B7EE,$B8BF
                fdb     $B991,$BA63,$BB34,$BC06,$BCD8,$BDAA,$BE7C,$BF4E
                fdb     $C021,$C0F3,$C1C5,$C298,$C36A,$C43D,$C510,$C5E3
                fdb     $C6B5,$C788,$C85B,$C92E,$CA01,$CAD4,$CBA8,$CC7B
                fdb     $CD4E,$CE22,$CEF5,$CFC9,$D09C,$D170,$D244,$D317
                fdb     $D3EB,$D4BF,$D593,$D667,$D73B,$D80F,$D8E3,$D9B7
                fdb     $DA8B,$DB60,$DC34,$DD08,$DDDD,$DEB1,$DF86,$E05A
                fdb     $E12F,$E204,$E2D8,$E3AD,$E482,$E557,$E62C,$E701
                fdb     $E7D6,$E8AB,$E980,$EA55,$EB2A,$EBFF,$ECD4,$EDAA
                fdb     $EE7F,$EF54,$F02A,$F0FF,$F1D5,$F2AA,$F380,$F455
                fdb     $F52B,$F600,$F6D6,$F7AC,$F881,$F957,$FA2D,$FB03
                fdb     $FBD9,$FCAF,$FD85,$FE5B,$FF31,$FFFF

stereo_pre75_tab
                fdb     $23DC,$23DF,$23E7,$23F4,$2407,$241F,$243C,$245E
                fdb     $2485,$24B2,$24E3,$251A,$2555,$2595,$25DA,$2623
                fdb     $2670,$26C2,$2718,$2773,$27D1,$2833,$2899,$2903
                fdb     $2970,$29E1,$2A55,$2ACC,$2B47,$2BC4,$2C44,$2CC8
                fdb     $2D4E,$2DD6,$2E62,$2EEF,$2F7F,$3012,$30A6,$313D
                fdb     $31D6,$3271,$330D,$33AC,$344C,$34EE,$3592,$3638
                fdb     $36DE,$3787,$3831,$38DC,$3988,$3A36,$3AE5,$3B96
                fdb     $3C47,$3CFA,$3DAD,$3E62,$3F18,$3FCF,$4086,$413F
                fdb     $41F8,$42B3,$436E,$442A,$44E7,$45A4,$4662,$4721
                fdb     $47E1,$48A1,$4962,$4A24,$4AE6,$4BA9,$4C6C,$4D30
                fdb     $4DF4,$4EB9,$4F7E,$5044,$510B,$51D2,$5299,$5361
                fdb     $5429,$54F1,$55BA,$5684,$574E,$5818,$58E2,$59AD
                fdb     $5A78,$5B44,$5C10,$5CDC,$5DA8,$5E75,$5F42,$600F
                fdb     $60DD,$61AB,$6279,$6347,$6416,$64E5,$65B4,$6683
                fdb     $6753,$6823,$68F3,$69C3,$6A94,$6B64,$6C35,$6D06
                fdb     $6DD8,$6EA9,$6F7B,$704C,$711E,$71F1,$72C3,$7395
                fdb     $7468,$753B,$760E,$76E1,$77B4,$7888,$795B,$7A2F
                fdb     $7B03,$7BD6,$7CAB,$7D7F,$7E53,$7F27,$7FFC,$80D1
                fdb     $81A5,$827A,$834F,$8425,$84FA,$85CF,$86A5,$877A
                fdb     $8850,$8925,$89FB,$8AD1,$8BA7,$8C7D,$8D54,$8E2A
                fdb     $8F00,$8FD7,$90AD,$9184,$925B,$9331,$9408,$94DF
                fdb     $95B6,$968D,$9764,$983C,$9913,$99EA,$9AC2,$9B99
                fdb     $9C71,$9D48,$9E20,$9EF8,$9FD0,$A0A7,$A17F,$A257
                fdb     $A32F,$A408,$A4E0,$A5B8,$A690,$A768,$A841,$A919
                fdb     $A9F2,$AACA,$ABA3,$AC7C,$AD54,$AE2D,$AF06,$AFDE
                fdb     $B0B7,$B190,$B269,$B342,$B41B,$B4F4,$B5CD,$B6A7
                fdb     $B780,$B859,$B932,$BA0C,$BAE5,$BBBE,$BC98,$BD71
                fdb     $BE4B,$BF24,$BFFE,$C0D8,$C1B1,$C28B,$C365,$C43E
                fdb     $C518,$C5F2,$C6CC,$C7A6,$C87F,$C959,$CA33,$CB0D
                fdb     $CBE7,$CCC1,$CD9C,$CE76,$CF50,$D02A,$D104,$D1DE
                fdb     $D2B9,$D393,$D46D,$D548,$D622,$D6FC,$D7D7,$D8B1
                fdb     $D98C,$DA66,$DB40,$DC1B,$DCF6,$DDD0,$DEAB,$DF85
                fdb     $E060,$E13B,$E215,$E2F0,$E3CB,$E4A5,$E580,$E65B
                fdb     $E736,$E811,$E8EB,$E9C6,$EAA1,$EB7C,$EC57,$ED32
                fdb     $EE0D,$EEE8,$EFC3,$F09E,$F179,$F254,$F32F,$F40A
                fdb     $F4E5,$F5C0,$F69B,$F777,$F852,$F92D,$FA08,$FAE3
                fdb     $FBBF,$FC9A,$FD75,$FE50,$FF2C,$FFFF

; The two template lines. The choice slots and the value slot are spaces here
; and are written over; everything else is fixed.
;                         0123456789012345678901234567890123456789
stereo_line1    fcc     "Mode        Pre     Pilot               "
stereo_line2    fcc     "                              NEXT/LAST "
