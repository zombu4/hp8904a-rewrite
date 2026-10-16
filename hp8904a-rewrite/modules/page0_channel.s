; ===========================================================================
; page0_channel.s - the channel configuration screens
;
; One screen per output channel: its frequency, amplitude, phase and where it
; is routed. This is the screen the instrument spends most of its life on.
;
; Everything shared - the display, the maths, the entry field - is called
; through the jump table in A2U12, because only one page is mapped at a time
; and a page cannot call its neighbour. That is why abi.inc exists and why
; nothing here duplicates a routine that already lives in the main image.
; ===========================================================================

; THE SCREEN SHOWED NO VALUES AT ALL. Line 1 got a title and the channel
; digit, line 2 got the word "Freq", and nothing else reached the glass - no
; frequency, no amplitude, no phase - on a screen whose own header calls it
; "one screen per output channel: its frequency, amplitude, phase and where
; it is routed". chan_ampl_tag and chan_phase_tag were defined and referenced
; nowhere, and no converter was called anywhere in the file.
;
; Two lines of forty, so the labels and their values share them: the channel
; and its frequency above, the amplitude and the phase below.
chan_title      fcc     "Channel    Freq                         "
chan_line2      fcc     "Ampl              Phase                 "
chan_absent     fcc     "No such channel                         "

CHAN_DIGIT_POS  equ     LCD_LINE1+8     ; the channel number
CHAN_FREQ_POS   equ     LCD_LINE1+16    ; and the three values, each nine
CHAN_AMPL_POS   equ     LCD_LINE2+5     ; characters wide: eight digits with
CHAN_PHASE_POS  equ     LCD_LINE2+24    ; a decimal point among them
CHAN_SHOW_WIDTH equ     9

; ---------------------------------------------------------------------------
; page0_channel_show - paint the screen for the selected channel
;
;   entry: B = the channel number
;   uses:  A, B, X, Y, U
;
; Checks the channel is fitted BEFORE painting anything. A screen that draws
; itself and then says the channel does not exist has already told the
; operator it does.
; ---------------------------------------------------------------------------
page0_channel_show
                pshs    x
                ldx     #page0_channel_key
                lbsr    ABI_screen_install
                puls    x
                pshs    b
                lbsr    ABI_channel_valid
                lbcs    page0_channel_absent    ; LONG: the three fields and
                                                ; their hop markers below put
                                                ; the refusal past a short
                                                ; branch's reach
                puls    b
                stb     >page0_channel_number
                stb     >active_record          ; the summary's record, which
                                                ; a save and a power-off carry

                lda     #LCD_LINE1
                ldx     #chan_title
                ldb     #SVC_LABEL_LEN
                lbsr    ABI_lcd_write

                lda     #LCD_LINE2
                ldx     #chan_line2
                ldb     #SVC_LABEL_LEN
                lbsr    ABI_lcd_write

                ldb     >page0_channel_number   ; the number, in the title
                addb    #'0'
                stb     >page0_digit
                lda     #CHAN_DIGIT_POS
                ldx     #page0_digit
                ldb     #1
                lbsr    ABI_lcd_write

                ; --- the three values, from this channel's record ----------
                ; format_places renders a 24-bit value into chan_text with a
                ; decimal point the given number of places from the right. The
                ; Channel Configuration screen uses it with the same place
                ; counts, so a value reads identically on both screens.
                ;
                ; AND THE SAME '*Hop Ram*' FOR CHANNEL 0. The stock has one
                ; channel screen, whose three painters substitute d4384
                ; ($4384) for channel 0's field while its hop function is on -
                ; draw_channel_frequency ($54E6) at l5543 on bit 8 of $2202,
                ; paint_channel_amptd ($57B1) at l57fe on bit 6 of $2203,
                ; show_channel_phase_field ($5854) at l58b6 on bit 7. This
                ; summary shows the same three fields of the same record, so
                ; it carries the same marker, from the same flags: hop_running,
                ; MODE_FLAG_AM, MODE_FLAG_PHASE. A summary that printed a
                ; frequency the hop RAM is overriding would be showing a value
                ; the socket is not producing.
                ldb     >page0_channel_number
                andb    #$03
                bne     page0_channel_freq_own
                tst     >hop_running
                beq     page0_channel_freq_own
                lda     #CHAN_FREQ_POS
                ldb     #CHAN_SHOW_WIDTH
                lbsr    page0_channel_marker
                bra     page0_channel_ampl
page0_channel_freq_own
                lbsr    page0_channel_record    ; X = the record
                leau    ,x                      ; CHAN_FREQ is zero, and a
                                                ; SYMBOLIC zero offset is
                                                ; encoded differently by the
                                                ; two assemblers - both
                                                ; correctly
                ldb     #1                      ; tenths of a hertz
                lbsr    ABI_format_places
                lda     #CHAN_FREQ_POS
                ldx     #chan_text
                ldb     #CHAN_SHOW_WIDTH
                lbsr    ABI_lcd_write

page0_channel_ampl
                ; THE AMPTD FIELD IS NOT ALWAYS A VOLTAGE HERE EITHER. This
                ; asked for AMPL_MICRO places unconditionally, so a channel
                ; set to AM showed its depth - tenths of a percent - as a
                ; fraction of a volt, and with no unit beside it there was
                ; nothing on the screen to say which it was. ampl_text picks
                ; the places, the range and the label from the destination,
                ; and it is the same routine the other two screens showing
                ; this field use.
                ldb     >page0_channel_number
                andb    #$03
                bne     page0_channel_ampl_own
                lda     >mode_flags
                bita    #MODE_FLAG_AM
                beq     page0_channel_ampl_own
                lda     #CHAN_AMPL_POS          ; the marker covers the value
                ldb     #CHAN_SHOW_WIDTH+1+AMPL_TEXT_U ; and the unit after it,
                lbsr    page0_channel_marker    ; as $57B1's nine at $1F cover
                bra     page0_channel_phase     ; the unit at $25
page0_channel_ampl_own
                lbsr    page0_channel_record
                lbsr    ABI_ampl_text
                lda     #CHAN_AMPL_POS
                ldx     #chan_text
                ldb     #CHAN_SHOW_WIDTH
                lbsr    ABI_lcd_write

                lda     #CHAN_AMPL_POS+CHAN_SHOW_WIDTH+1
                ldx     #chan_text+AMPL_TEXT_W
                ldb     #AMPL_TEXT_U
                lbsr    ABI_lcd_write

page0_channel_phase
                ldb     >page0_channel_number
                andb    #$03
                bne     page0_channel_phase_own
                lda     >mode_flags
                bita    #MODE_FLAG_PHASE
                beq     page0_channel_phase_own
                lda     #CHAN_PHASE_POS
                ldb     #CHAN_SHOW_WIDTH
                lbra    page0_channel_marker
page0_channel_phase_own
                lbsr    page0_channel_record    ; the phase is sixteen bits,
                ldd     CHAN_PHASE,x            ; so it is widened into the
                std     >chan_work+1            ; shared 24-bit work area
                clr     >chan_work              ; before it is rendered
                ldu     #chan_work
                ldb     #1                      ; tenths of a degree
                lbsr    ABI_format_places
                lda     #CHAN_PHASE_POS
                ldx     #chan_text
                ldb     #CHAN_SHOW_WIDTH
                lbra    ABI_lcd_write

page0_channel_absent
                puls    b
                lda     #LCD_LINE1              ; BOTH LINES. This wrote only
                lbsr    ABI_lcd_blank_line      ; line 2, so "No such channel"
                lda     #LCD_LINE2              ; appeared under whatever line
                ldx     #chan_absent            ; 1 the previous screen had
                ldb     #SVC_LABEL_LEN          ; left - screen_install does
                lbra    ABI_lcd_write           ; not repaint

; ---------------------------------------------------------------------------
; page0_channel_record - the record of the channel this screen is showing
;
;   exit:  X = the record
;   uses:  A, B, X
;
; The same arithmetic chan_record does for the Channel Configuration screen,
; against this screen's own channel number rather than current_channel.
; ---------------------------------------------------------------------------
page0_channel_record
                ldb     >page0_channel_number
                andb    #$03                    ; a wild number must not index
                lda     #CHAN_RECORD            ; outside the four records
                mul
                ldx     #channel_records
                leax    d,x
                rts

; ---------------------------------------------------------------------------
; page0_channel_marker - '*Hop Ram*' over one of this screen's fields
;
;   entry: A = the field's DDRAM position, B = the columns to cover, 9 to 13
;   uses:  A, B, X
;
; The string is chan_hop_marker in page0_screen.s - the stock's d4384, nine
; characters and four blanks - shared because both screens are on this page.
; ---------------------------------------------------------------------------
page0_channel_marker
                ldx     #chan_hop_marker
                lbra    ABI_lcd_write

; ---------------------------------------------------------------------------
; page0_channel_set_frequency - apply a typed frequency to the channel
;
;   entry: B = the unit code the operator chose
;   exit:  carry SET if the value will not fit, and nothing was programmed
;   uses:  A, B, X, Y, U
;
; Scale first, check second, program third. Programming a partly-scaled value
; would put a frequency on the output that nobody asked for, and on a signal
; generator that is the whole failure.
; ---------------------------------------------------------------------------
page0_channel_set_frequency
                pshs    b
                lbsr    ABI_entry_value         ; the digits, as 24 bits
                bcs     page0_channel_too_big
                ldx     #entry_result
                puls    b
                lbsr    ABI_unit_apply          ; x1000 or x1000000
                bcs     page0_channel_over

                ; Through the setter that owns the frequency, not through a
                ; raw register write. It validates against this channel's
                ; ceiling, stores the record, and programs the chip as four
                ; 6-bit fields and a latch.
                ;
                ; This wrote the LOW SIXTEEN BITS of the entered value to
                ; register 0 - which is a BUFFER LATCH, not a frequency - so
                ; it staged a fragment and latched nothing. A frequency is
                ; twenty-four bits and the top eight were discarded, so every
                ; setting above 6553.5 Hz was wrong as well.
                ldb     >page0_channel_number
                andb    #$03                    ; MASKED, like its sibling
                                                ; thirty-seven lines below.
                                                ; mul is 16-bit, so n = 41
                                                ; puts X at $3FEC and freq_set
                                                ; writes three bytes through
                                                ; it - $3FEC to $3FEE, and
                                                ; $3FEE is per-unit. Bounded
                                                ; today by the writers of this
                                                ; variable; bounded here as
                                                ; well, because the guard
                                                ; belongs with the arithmetic.
                pshs    b
                lda     #CHAN_RECORD
                mul
                ldx     #channel_records
                leax    d,x                     ; X = the channel's record
                ldu     #entry_result
                puls    b
                lbsr    ABI_freq_set
                bcs     page0_channel_over
                lbsr    ABI_filter_apply        ; the filter follows the
                                                ; frequency, as the stock's
                                                ; commit runs $F7EC at $6514
                andcc   #~CC_CARRY
                rts

page0_channel_too_big
                puls    b
                ldb     #ERR_VALUE_TOO_BIG      ; the ENTRY overflowed: more
                bra     page0_channel_raise     ; than 24 bits was typed
page0_channel_over
                ldb     >last_error             ; FREQ_SET ALREADY DECIDED WHY.
                                                ; It records the code before
                                                ; returning carry -
                                                ; ERR_FREQ_RANGE, above this
                                                ; channel's ceiling - and this
                                                ; replaced it with
                                                ; ERR_VALUE_TOO_BIG, sending
                                                ; the operator to look for a
                                                ; number too big to store
                                                ; rather than one too high for
                                                ; the channel.
page0_channel_raise
                lbsr    ABI_error_raise
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; page0_channel_key - the single-channel summary screen's keys
;
;   entry: B = the key code
;   uses:  A, B, X, Y
;
; NEXT and LAST step to the next fitted channel; ENTER returns to the full
; Channel Configuration screen for whichever one is showing. Digits build a
; frequency, echoed over the FREQ column; BACKSPACE takes the last of them
; out again (page0_channel_key_backspace); Hz or kHz commits.
;
; STEPPING SKIPS CHANNELS THAT ARE NOT FITTED. Most instruments have fewer
; than four boards, and offering a channel that is not there means an
; operator sets a frequency, sees it accepted, and hears nothing. The skip
; is bounded by a count rather than by "keep going until one is fitted",
; because on an instrument with no boards at all that loop never ends.
; ---------------------------------------------------------------------------
page0_channel_key
                ; THE SAVE KEY AND WHAT ITS PROMPT LEAVES BEHIND, as
                ; stereo_key has them and for the same reason: without them no
                ; register could be saved on the Channel Summary, which the
                ; architect's ruling of 2026-09-16 recalls to.
                cmpb    #RMT_RQ+$21
                bne     page0_channel_key_not_save
                clr     >entry_active           ; the open entry closes
                lbra    ABI_save_prompt_open    ; $F331 with $0021
page0_channel_key_not_save
                cmpb    #KEY_ABANDON
                bne     page0_channel_key_not_abandon
                clr     >entry_active
                rts
page0_channel_key_not_abandon
                ; A DIGIT STARTS A FREQUENCY, and a unit key commits it.
                ; page0_channel_set_frequency takes the unit code and exists
                ; for exactly this, and nothing called it - so the summary
                ; screen could show four channels and change none of them.
                lbsr    ABI_key_digit           ; carry clear and B = 0 to 9
                bcs     page0_channel_key_unit
                lbsr    ABI_entry_digit
                lbcs    page0_channel_key_refuse ; a full field: refused
                lda     #$01                    ; $B521: a key has been
                sta     >entry_active           ; accepted into the field
                lbra    page0_channel_redraw    ; $B53D-$B56B: the entry
                                                ; echoed over the frequency.
                                                ; This repainted the STORED
                                                ; values only, so the digits
                                                ; typed here were never seen
page0_channel_key_unit
                cmpb    #KEY_HZ
                bne     page0_channel_key_khz
                ldb     #UNIT_HZ
                lbra    page0_channel_commit
page0_channel_key_khz
                cmpb    #KEY_KHZ
                bne     page0_channel_key_backspace
                ldb     #UNIT_KHZ
page0_channel_commit
                lbsr    ABI_entry_cursor_off    ; $B5BA: the units key ends it
                ; NOTHING TYPED, NOTHING STORED. The stock's enter_freq_value
                ; ($6BA5) converts the buffer with entry_to_scaled_digits
                ; ($CDE1), which returns $FF when there are no digits, and
                ; $6BB8 CMPB #$08 / $6BBA LBCC l6bf0 skips the conversion
                ; and commit_channel_frequency ($647B) on that count, going
                ; straight to the tail that stores the unit, repaints and
                ; re-arms. Executed on the stock (emulator: f1, NEXT, FREQ,
                ; "12", BACKSPACE, BACKSPACE, Hz): the glass still reads
                ; 1000.0 Hz. This committed whatever ABI_entry_value made of
                ; an empty field - zero - so a unit key on a fresh screen, or
                ; after BACKSPACE had emptied the entry, programmed 0 Hz that
                ; nobody typed.
                tst     >entry_count
                beq     page0_channel_commit_rearm
                lbsr    page0_channel_set_frequency
page0_channel_commit_rearm
                lbsr    page0_channel_entry_begin       ; a fresh field, so the
                                                        ; next value typed is
                                                        ; not appended to the
                                                        ; one just committed
                ldb     >page0_channel_number
                lbsr    page0_channel_show
                lbra    page0_channel_arm       ; and re-armed after the commit

page0_channel_key_backspace
                cmpb    #KEY_BACKSPACE
                bne     page0_channel_key_move
                ; THE LAST DIGIT OUT AGAIN. This screen is the rewrite's
                ; summary of the stock's Channel Configuration screen, and
                ; its one entry is that screen's FREQ field, which the stock
                ; arms through entry_cfg_freq ($4EE5): 8 digits, column $0B,
                ; units class 6, mode 3, handed to arm_numeric_entry_field
                ; ($AC35) by open_entry_field_from_locals ($512B) - which
                ; sets the armed flag $23A8 ($AC87-$AC89) and clears the
                ; first-key flag $23A7 ($AC84). numeric_entry_key_handler
                ; ($B3C2) hands BACKSPACE to entry_backspace ($B2CD) at
                ; $B4B9 - nothing before it claims $1F: $AE3D[30] is
                ; keymap_unmapped_return0 and keymap_menu_msgs_19_1d ($AEBB)
                ; names only 3-6 and $2A - and for mode 3 ($B379 CMPX
                ; #$0003 / $B37C LBEQ) it steps the head $23A4 back unless
                ; it is zero and blanks the vacated cell ($B2E9-$B31F),
                ; returning 1 either way ($B382). The handler then repaints
                ; the buffer at $23AD and puts the cursor after its last
                ; character ($B4D0-$B501) only if $23A7 says a key has been
                ; accepted since the field was armed ($B4C4); otherwise it
                ; leaves at $B4CD with the glass untouched.
                ;
                ; EXECUTED on the stock (emulator: f1, NEXT, FREQ): "12" then
                ; BACKSPACE reads "FREQ 1"; again, the field is blank; a
                ; third press changes nothing and beeps nothing - $23DE
                ; stayed 0. With NO field armed ($23A8 clear, before FREQ is
                ; pressed) the same key reaches error_report_beep ($C3FE)
                ; with code 1 ($B494-$B4AD: LDB #$01 at $B49D, LBSR at
                ; $B4A8) - executed: $23DE read 1 - but this screen arms its
                ; field as it opens and after every commit
                ; (page0_channel_entry_begin), so that case cannot arise
                ; here. entry_active is $23A7; ABI_entry_backspace is
                ; $B2E9-$B31F on this editor's buffer; page0_channel_redraw
                ; repaints the values and the entry over the frequency with
                ; the cursor after its last digit, as $B4D0-$B501 does.
                tst     >entry_active           ; $B4C4: no key accepted yet,
                lbeq    page0_channel_key_done  ; nothing to take out or show
                lbsr    ABI_entry_backspace     ; $B2E9-$B31F, slot 73
page0_channel_redraw
                ldb     >page0_channel_number   ; $B4D0-$B501: the stored
                lbsr    page0_channel_show      ; values, then the entry over
                lbra    page0_channel_entry_echo ; the frequency

; ---------------------------------------------------------------------------
; page0_channel_entry_begin - arm the shared entry field for a frequency
;
;   uses:  A, B, X
;
; NOTHING IN THIS FILE STARTED AN ENTRY. `grep -n "entry_begin"
; modules/page0_channel.s` returned nothing, and entry_digit refuses a digit
; whose value is not below entry_base - which is zero until somebody sets it.
; So on a cold boot every digit typed on this screen was rejected, and after
; another screen had used the field the digits went into whatever width and
; base that screen had left.
; ---------------------------------------------------------------------------
page0_channel_entry_begin
                clr     >entry_active           ; $AC84: a fresh field has had
                                                ; no key accepted into it
                lda     #ENTRY_DECIMAL
                ldb     #CHAN_W_FREQ            ; nine declared, and clamped
                                                ; to ENTRY_MAX = 8 by
                                                ; entry_begin: the ninth
                                                ; column of the value is its
                                                ; decimal point's
                lbra    ABI_entry_begin
page0_channel_key_move
                cmpb    #KEY_NEXT
                beq     page0_channel_forward
                cmpb    #KEY_LAST
                beq     page0_channel_backward
                cmpb    #KEY_ENTER
                bne     page0_channel_key_done
                lbra    ABI_mode_enter_channel_config ; the full screen for
                                                ; it: Channel Configuration,
                                                ; recorded as the active mode
                                                ; and entered as from the menu
page0_channel_forward
                lda     #$01
                bra     page0_channel_step
page0_channel_backward
                lda     #$FF
page0_channel_step
                sta     >page0_channel_delta
                ldb     #CHANNEL_MAX            ; at most four tries, so an
page0_channel_try                               ; instrument with no boards
                pshs    b                       ; fitted cannot spin here
                ldb     >page0_channel_number
                addb    >page0_channel_delta
                andb    #$03                    ; wrap within the four
                stb     >page0_channel_number
                lbsr    ABI_channel_valid
                puls    b
                bcc     page0_channel_key_show  ; fitted: show it
                decb
                bne     page0_channel_try
page0_channel_key_show
                ldb     >page0_channel_number
                lbra    page0_channel_show
page0_channel_key_done
                rts
page0_channel_key_refuse
                lbra    ABI_key_refuse          ; a key this screen cannot
                                                ; use is REFUSED, not
                                                ; ignored; see key_refuse

; ---------------------------------------------------------------------------
; page0_channel_entry_echo - the digits typed so far, over the frequency
;
;   uses:  A, B, X, Y - Y through ABI_entry_render
;
; Runs AFTER page0_channel_show, which paints the stored frequency into the
; same nine columns. The stock echoes the whole entry buffer at the field's
; column after every accepted key - lcd_write_string_at ($D8A5) of $239A,
; width $23A5, at $23AD ($B53D-$B555) - and then puts the cursor at the
; column plus the head $23A4 ($B556-$B56B). ABI_entry_render is that
; buffer's layout: the digits from the first cell, blanks to the width. The
; width is eight (entry_begin's clamp) and the value occupies nine, so the
; ninth cell is blanked here rather than left holding the last character of
; the value the field used to show - the defect chan_entry_echo records.
; ---------------------------------------------------------------------------
; ---------------------------------------------------------------------------
; page0_channel_arm - the summary's FREQ field armed: the cursor on it
;
;   uses:  A
;
; This screen is the rewrite's own summary and has no stock counterpart, but
; its one field is the channel screen's FREQ, which the stock arms through
; entry_cfg_freq ($4EE5) at $0B - on open and after every commit - and
; turns the cursor off at $B5BA when a units key ends it. It follows that
; field: the cursor on its first column plus the digits typed.
; ---------------------------------------------------------------------------
page0_channel_arm
                lda     #CHAN_FREQ_POS          ; $23AD
                adda    >entry_count            ; + $23A4
                lbra    ABI_entry_cursor_on     ; $AC98, $ACA6

page0_channel_entry_echo
                ldx     #chan_text
                lbsr    ABI_entry_render        ; $B53D-$B555: eight cells
                lda     #$20
                sta     >chan_text+TEXT_DIGITS  ; and the ninth, blank
                lda     #CHAN_FREQ_POS
                ldx     #chan_text
                ldb     #CHAN_SHOW_WIDTH
                lbsr    ABI_lcd_write_raw       ; the echo: glass only, as
                                                ; lcd_write_string_at ($D8A5)
                lda     #CHAN_FREQ_POS
                adda    >entry_count            ; $B556-$B56B: the cursor after
                lbra    ABI_lcd_cursor          ; the last digit

; ---------------------------------------------------------------------------
; page0_channel_open - the channel summary, reached through this page's $4007
;
;   entry: U = the entry reason: MODE_COLD, MODE_RECALL or MODE_KEEP
;   uses:  A, B, X, Y, U
;
; Opens on the first FITTED channel rather than on channel 0, so an
; instrument whose first board is missing does not greet the operator with a
; channel that is not there. page0_channel_key then steps between the fitted
; ones.
;
; A RECALL OR A KEEP-STATE POWER-ON OPENS ON THE CHANNEL IT WAS SHOWING, by
; the architect's ruling of 2026-09-16: this screen
; re-enters as the four stock modes do, and they come back on their saved
; record. A recall applies the register first, as each of them does on reason
; 1 - register_restore has run the preset and the copy and left the hardware
; to the mode - and a keep-state power-on has been applied by boot_keep_state.
; A saved channel past the last, or one no longer fitted, opens as a cold
; entry does.
; ---------------------------------------------------------------------------
page0_channel_open
                cmpu    #MODE_RECALL
                beq     page0_channel_open_recall
                cmpu    #MODE_KEEP
                beq     page0_channel_open_saved
                bra     page0_channel_open_cold
page0_channel_open_recall
                lbsr    ABI_register_apply
page0_channel_open_saved
                ldb     >active_record
                cmpb    #CHANNEL_MAX
                bhs     page0_channel_open_cold
                pshs    b
                lbsr    ABI_channel_valid       ; carry CLEAR when fitted
                puls    b
                bcs     page0_channel_open_cold
                pshs    b
                lbsr    page0_channel_entry_begin
                puls    b
                bra     page0_channel_open_show
page0_channel_open_cold
                lbsr    page0_channel_entry_begin
                clrb
page0_channel_open_try
                pshs    b
                lbsr    ABI_channel_valid       ; carry CLEAR when fitted
                puls    b
                bcc     page0_channel_open_show
                incb
                cmpb    #CHANNEL_MAX
                blo     page0_channel_open_try
                ldb     #ERR_NO_SUCH_CHANNEL    ; none fitted at all
                lbra    ABI_error_raise
page0_channel_open_show
                stb     >page0_channel_number
                lbsr    page0_channel_show
                lbra    page0_channel_arm       ; armed as it opens, as $4EE5 is

