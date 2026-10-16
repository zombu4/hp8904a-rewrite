; ===========================================================================
; errors.s - reporting a fault to the operator
;
; One place that raises an error, one place that remembers the last one, and
; one screen that shows it. The stock firmware spreads this across a beep
; routine, a code byte, and a screen that has to be reached before the code
; is overwritten.
;
; THE BEEP IS A TIMER OUTPUT, not a software loop. MC6840 timer 1 drives the
; sounder: setting bit 7 of the CR1 shadow starts it, clearing it stops. That
; is why an error beep has the same pitch and length however busy the
; instrument is - and why it must not be "fixed" into a delay loop.
; ===========================================================================

; The errors this firmware can raise. Numbered rather than named on screen,
; because the display is forty characters and an engineer with the manual
; wants the number; the name is here for whoever reads the source.
; (these constants are in common/display.inc, common/formats.inc)

; The error NUMBERS are in common/formats.inc, which every image includes.

BEEP_ENABLE     equ     $80             ; bit 7 of the MC6840 CR1 shadow
BEEP_MS         equ     100             ; how long an error beep lasts

; THE BANNER IS THE STOCK'S OWN FORTY BYTES, ded61 at $ED61, dumped from
; firmware/a2u12.bin: the number goes into the gap at columns 32-34, which is
; where show_last_error_screen ($C418) writes it. It read "Error" and then
; thirty-five spaces, with the number on line 2 and no message at all.
;
; There is no "no error recorded" line any more. Code 0 is a MESSAGE like any
; other - entry 0 of the stock's table is "No Error" - so the screen has one
; shape and the table answers every code.
error_banner    fcc     "*  Last reported error was no.         *"

ERROR_NUM_POS   equ     LCD_LINE1+$20   ; the three digits, at DDRAM $20
ERROR_NUM_W     equ     3               ; format_three_digits ($C9D1) makes
ERROR_NUM_BLANK equ     2               ; three and blank_leading_zeros ($CCFF)
                                        ; may blank the first two of them
ERROR_FLASH_MS  equ     3000            ; $0BB8 through delay_ms ($D670)

; ---------------------------------------------------------------------------
; error_raise - record a fault, tell the operator, and sound it
;
;   entry: B = the error number
;   uses:  A, B, X, Y, U - Y and U through error_show, which calls
;          uint24_to_text; a callee's clobbers are the caller's
;
; The number is kept so the screen can show it later; the beep happens now,
; because an error the operator does not notice is an error they act on.
;
; error_record below is the same thing without the painting, for a caller
; that has chosen its own words.
; ---------------------------------------------------------------------------
error_raise
                stb     >last_error
                bra     error_beep              ; A REFUSAL IS A BEEP, and the
                                                ; operator asks for the words.
                                                ; Driven on the stock
                                                ; 2026-09-11: typing 700000
                                                ; into channel A's FREQ field
                                                ; and pressing Hz leaves the
                                                ; channel screen exactly as it
                                                ; was and puts $7B in $23DE -
                                                ; nothing is painted until
                                                ; SHIFT then INC SET asks for
                                                ; it. This called error_show,
                                                ; which put a number over the
                                                ; screen the operator was
                                                ; still working on.

; ---------------------------------------------------------------------------
; error_report_beep - record a fault and sound it, and nothing on the bus
;
;   entry: B = the error number
;   uses:  A, B, X
;
; The stock's error_report_beep ($C3FE), which is ptm_t1_output_pulse and
; STB >$23DE and nothing else - no status bit, no service request, remote or
; not. Whether an error ALSO goes out over the bus is decided at each stock
; call site, by testing event_flags bit 3 and calling
; report_error_and_pulse_status_bit ($9DD3); error_record below makes that
; choice for every caller. A site that calls $C3FE alone calls this.
; Measured 2026-09-16: 'DEA AM;' on channel A, refused in
; set_channel_destination ($78BF) through $C3FE, leaves $65 in $23DE with no
; SRQ on the stock (acceptance 4.8).
; ---------------------------------------------------------------------------
error_report_beep
                stb     >last_error
                bra     error_beep

; ---------------------------------------------------------------------------
; error_record - record a fault and sound it, WITHOUT painting the number
;
;   entry: B = the error number
;   uses:  A, B, X
;
; For a caller that has painted its own message and would have that message
; overwritten by the Error screen. The fault-line report is the one: the stock
; paints '!! Reference Loop Reports Out Of Lock !!' or 'Reverse Power Relay
; Tripped on Output 3' - which says far more than a number does - and there is
; no reason to lose that and show a code instead.
;
; The number is still recorded, so the last-error screen and anything that
; reads it are not left behind by a screen that chose its own words.
; ---------------------------------------------------------------------------
error_record
                stb     >last_error
                pshs    b
                lda     >rmt_flags              ; WHILE REMOTE, EVERY ERROR IS
                bita    #RF_REMOTE              ; ALSO REPORTED OVER THE BUS -
                beq     error_record_local      ; the stock tests event_flags
                ldb     ,s                      ; bit 3 before each error and
                lbsr    remote_error            ; calls
error_record_local                              ; report_error_and_pulse_status_bit
                puls    b                       ; ($9DD3) as well as beeping;
                bra     error_beep              ; the status-bit pulse and SRQ
                                                ; are what a controller sees


; ---------------------------------------------------------------------------
; error_beep - a short tone from timer 1
;
;   uses:  A, B, X
;
; Sets bit 7 of the CR1 shadow, writes the shadow to the chip, waits, and
; clears it again. The shadow is written first so that an interrupt reading
; it between the two sees the state the hardware is actually in.
; ---------------------------------------------------------------------------
error_beep
                lbsr    special_beeper_enabled  ; special function 2 silences
                bcc     error_beep_silent       ; it, for a bench where the
                                                ; beep is the annoying part
                                                ; - and beep_now below is the
                                                ; same tone WITHOUT the gate,
                                                ; for the one caller that must
                                                ; not read a preference

; ---------------------------------------------------------------------------
; beep_now - the tone itself, with no preference consulted
;
;   uses:  A, B, X
;
; SPLIT OUT RATHER THAN COPIED. The power-on self-test failure report has to
; be audible whatever special function 2 says, because the preference lives in
; battery-backed RAM and the thing being reported may be that battery-backed
; RAM has just failed its test - reading a flag out of the memory whose fault
; you are announcing is not a check, it is a coin toss. Every other caller
; goes through error_beep and is silenced normally.
;
; error_beep falls straight into this, so there is one implementation of the
; tone and not two.
; ---------------------------------------------------------------------------
beep_now
                ; $1000 IS CR1 OR CR3 DEPENDING ON BIT 0 OF CR2, and ptm_init
                ; leaves that bit CLEAR - so $1000 addresses CR3, not CR1.
                ;
                ; This wrote the CR1 shadow to $1000 twice. The beep never
                ; reached the sounder, and CR3 was overwritten with CR1's
                ; value: timer 3 lost its 16-bit mode and its prescaler while
                ; ptm_cr3_shadow went on claiming $27. Timer 3 is the
                ; timebase for every delay_ms, including the six-millisecond
                ; amplitude range settle that bounds the output transient, so
                ; after the first error every one of them ran on a
                ; misconfigured counter - and the shadow that exists to
                ; mirror the hardware permanently disagreed with it.
                ;
                ; Select CR1 first, write it, and put the selection back.
                ; nmi_silence in boot.s does the same and got it right.
                lda     #PTM_CR2_SELECT         ; $1000 now reaches CR1, and
                ldb     #$FF                    ; through ptm_cr2_change so an
                lbsr    ptm_cr2_change          ; interrupt landing inside the
                                                ; read-modify-write cannot put
                                                ; the old byte back - see its
                                                ; header in timer.s

                lda     >ptm_cr1_shadow
                ora     #BEEP_ENABLE
                sta     >ptm_cr1_shadow
                sta     >ptm_cr

                ldd     #BEEP_MS
                lbsr    delay_ms

                ; AND SELECT CR1 AGAIN, because the selection did not survive
                ; the call above. $1000 is CR1 or CR3 depending on bit 0 of
                ; CR2, and this routine set that bit once, before a delay of
                ; BEEP_MS milliseconds, and then wrote $1000 again afterwards
                ; as though nothing could have moved it.
                ;
                ; SOMETHING CAN. nmi_silence (boot.s:1191) walks CR1 and CR3
                ; and used to leave the selection CLEAR - it is the NMI's own
                ; path and NMI cannot be masked, so it can land anywhere
                ; inside delay_ms. seq_timer_start and seq_timer_stop
                ; (timer.s:285, :335) also write CR2 whole, from PTM_SEQ_RUN
                ; and PTM_SEQ_STOP, but both of those carry PTM_CR2_SELECT
                ; (timer.s:102-103) and so leave CR1 selected - which is what
                ; this routine wants, by luck rather than by contract.
                ; After the interrupt, the store below would have gone to CR3:
                ; timer 3 reprogrammed with the beeper's control byte while
                ; ptm_cr3_shadow went on claiming $27. Timer 3 is the timebase
                ; for every delay_ms in the instrument, including the six
                ; millisecond amplitude-range settle that bounds the output
                ; transient.
                ;
                ; That is the same fault the note above describes, one level
                ; further along: it was fixed for the write BEFORE the delay
                ; and left in place for the write after it. nmi_silence now
                ; puts the selection back as it found it, which closes the
                ; interrupt half; this closes the half that any call can open.
                lda     #PTM_CR2_SELECT
                ldb     #$FF
                lbsr    ptm_cr2_change

                lda     >ptm_cr1_shadow
                anda    #~BEEP_ENABLE
                sta     >ptm_cr1_shadow
                sta     >ptm_cr

                clra                            ; and back to CR3, which is
                ldb     #~PTM_CR2_SELECT        ; what the rest of this
                lbsr    ptm_cr2_change          ; firmware expects $1000 to
                                                ; address
error_beep_silent
                rts

; ---------------------------------------------------------------------------
; key_refuse - a key this screen cannot use
;
;   uses:  A, B, X
;
; SEVEN SCREENS SILENTLY IGNORED ONE. Each ended its key dispatch with a bare
; RTS - chan_key_ignore, dtmf_key_ignore, tone_key_ignore,
; digital_key_ignore, screen_numeric_ignore, menu_key_ignore,
; memmap_key_ignore - so pressing a key that does nothing here gave no
; indication at all, and an operator could not tell a key that is not used on
; this screen from one whose contact has failed.
;
; The stock does not do that. numeric_entry_key_handler ($B3C2) offers each
; key to key_to_state_code ($AD4D), keymap_menu_msgs_19_1d ($AEBB),
; entry_backspace ($B2CD), keypad_char_column_select ($AF29) and
; accept_units_key ($B0C1) in turn, and what none of them claims reaches
; error_report_beep ($C3FE): code 1 at $B49A when no entry field is armed, and
; code 2 at the fall-through. That routine stores the code and pulses timer 1;
; it paints nothing, which is why this uses error_record rather than
; error_raise - a refused keystroke must not wipe the screen the operator is
; working on.
; ---------------------------------------------------------------------------
key_refuse
                cmpb    #KEY_REFRESH            ; THE LINE-6 RECOVERY EVENT IS
                beq     key_refuse_event        ; NOT A KEY. It is delivered
                                                ; through every screen's
                                                ; handler and lands here on
                                                ; the ones that do not act on
                                                ; it - which today is all of
                                                ; them - and an event beeping
                                                ; the refusal tone at an
                                                ; operator who pressed
                                                ; nothing would read as a
                                                ; broken key.
                cmpb    #KEY_ABANDON            ; nor the stock's $3C, which
                beq     key_refuse_event        ; a screen without an arm for
                                                ; it simply does not answer
                cmpb    #KEY_GONE_LOCAL         ; AND NEITHER IS THE STOCK'S
                bne     key_refuse_real         ; REQUEST 1, which
                                                ; hpib_reset_and_repaint
                                                ; ($9F45) posts at $9F8C when
                                                ; the controller releases the
                                                ; instrument. Only page 0
                                                ; answers it, at l5d33
                                                ; ($5D33); the other three
                                                ; pages carry no comparison
                                                ; against $0001 at all, so on
                                                ; their screens the request
                                                ; goes by unanswered rather
                                                ; than refused. Falling into
                                                ; error_record here left $0F,
                                                ; 'Un-executable command', in
                                                ; the last-error cell after
                                                ; every LOCAL - measured on
                                                ; the Main Selection, the
                                                ; stock 0 and this firmware
                                                ; 15, by the gate
                                                ; emulator/tests/test_remote_new.py
key_refuse_event
                rts
key_refuse_real
                ; A KEY REFUSED DURING AN ENTRY IS A DIFFERENT FAULT from a key
                ; the screen has no use for at all, and the instrument says so:
                ; numeric_entry_key_handler beeps error 2 at $B5D0, 'Invalid
                ; key entry', for a key the armed field's own column does not
                ; hold, where main_selection_level_handler's l8caa beeps $0F,
                ; 'Un-executable command', for a key its screen does not use.
                ; Driven side by side 2026-09-11: with digits typed into the
                ; FREQ field, deg leaves $23DE at $02 on the stock and left
                ; $0F here; DOWN on the Main Selection leaves $0F on both.
                ;
                ; AND AN UNMAPPED KEY WITH NO FIELD ARMED IS CODE 1, on every
                ; screen, because numeric_entry_key_handler ($B3C2) sees it
                ; before any screen does: key_to_state_code ($AD4D) and
                ; keymap_menu_msgs_19_1d ($AEBB) do not claim it, and lb494
                ; ($B494) finds $23A8 clear and hands 1 to error_report_beep
                ; ($C3FE) - stored and beeped, nothing sent to the bus. Driven
                ; 2026-09-15 on the Main Selection and the Tone Sequence
                ; title: 5, point, minus, BACKSPACE, ENTER and Hz each leave
                ; $23DE = 1 on the instrument, and left 15 here.
                cmpb    #RMT_RQ                 ; a bus request is not a key
                bhs     key_refuse_keyed
                lbsr    entry_key_is_mapped     ; Z set: nothing maps it
                bne     key_refuse_keyed
                ldb     #ERR_NO_ENTRY_FIELD     ; unmapped: lb494's 1 with no
                lbsr    entry_is_open           ; field armed, and $B5D0's 2
                beq     key_refuse_beep         ; when one is - the column the
                ldb     #ERR_KEY_ENTRY          ; armed field selected has no
key_refuse_beep                                 ; such key. Driven 2026-09-15:
                lbra    error_raise             ; FREQ then deg on ch A leaves
                                                ; 2 on the instrument, and a
                                                ; record change then deg 1.
                                                ; Both through $C3FE, so no
                                                ; bus report.
key_refuse_keyed
                ldb     #ERR_KEY_UNUSABLE       ; a key the screen maps and
                lbra    error_record            ; does not use: $0F

; THE TWO ROUTINES THAT WERE HERE ARE GONE, and what replaced each is named
; so nothing is merely dropped.
;
; error_last returned last_error in B with Z set when it was zero. Its only
; caller was the old error screen, deciding whether to print "No error
; recorded" instead of a number. The instrument does not decide: code 0 is
; entry 0 of the message table, "No Error", so error_show reads the cell
; directly and the table answers.
;
; error_clear zeroed last_error for an f1 on that screen. The instrument has
; no such key and no such clear - $23DE is only ever overwritten by the next
; fault, and the one CLR in sequence_mode_message_handler ($4C01) is `clr
; >$3c02`, the tone mode's own cell, not the error number. A fault stays
; readable until another one replaces it.

; ---------------------------------------------------------------------------
; error_show - the last error, flashed over whatever is showing
;
;   uses:  A, B, X, Y, U - Y and U through uint24_to_text and the paged call
;
; THE STOCK'S show_last_error_screen ($C418), step for step:
;
;   set bit 4 of event_flags ($2204)     lcd_hold: everything else that paints
;                                        now goes to the shadow and stops there
;   the banner ded61 over line 1         error_banner, written raw
;   line 2 blanked with ded11            the raw line writer pads it
;   the number at DDRAM $20              three digits, two leading zeros blanked
;   the message on line 2                the table on A2U13 page 3
;   delay_ms($0BB8)                      ERROR_FLASH_MS
;   lcd_repaint_shadow ($D9C6)           lcd_repaint, which clears lcd_hold
;
; So it is a THREE-SECOND FLASH, not a screen. Nothing is dismissed and no
; keys are taken: the screen underneath comes back by itself, values and all,
; because every other painting routine mirrors into lcd_shadow and this one
; deliberately does not. Driven on the stock 2026-09-11 from the channel
; screen, and the channel screen is back afterwards with its 1000.0 Hz and its
; 140 uV still on it.
;
; Reading does not clear the number. An engineer who walks away and comes back
; asks again and gets the same fault.
; ---------------------------------------------------------------------------
error_show
                lda     #1                      ; the glass is the flash's now
                sta     >lcd_hold

                lda     #LCD_LINE1
                ldx     #error_banner
                ldb     #LCD_COLUMNS
                lbsr    lcd_write_line_raw

                ; THE NUMBER, three digits with at most two leading zeros
                ; blanked - which is what the stock's format_three_digits
                ; ($C9D1) and blank_leading_zeros ($CCFF) pair does, and why
                ; error 123 reads '123' and error 3 reads '  3'.
                clr     >math_work              ; the shared converter takes a
                clr     >math_work+1            ; 24-bit value in memory
                ldb     >last_error
                stb     >math_work+2
                ldx     #math_work
                lbsr    uint24_to_text          ; eight digits, zeros kept
                ldx     #text_buffer+TEXT_DIGITS-ERROR_NUM_W
                ldb     #ERROR_NUM_BLANK
error_show_lead
                lda     ,x
                cmpa    #'0'
                bne     error_show_number
                lda     #' '
                sta     ,x+
                decb
                bne     error_show_lead
error_show_number
                ldx     #text_buffer+TEXT_DIGITS-ERROR_NUM_W
                lda     #ERROR_NUM_POS
                ldb     #ERROR_NUM_W
                lbsr    lcd_write_raw

                ; THE WORDS, which live with the table on page 3. The page is
                ; put back afterwards: the stock only ever reaches this from
                ; the Main Selection Level, where A2U12 is running and nothing
                ; cares what is in the window, but the service menu reaches it
                ; here too and a screen on another page would come back to an
                ; address that is no longer its own.
                lbsr    page_current
                pshs    b
                ldb     #PAGE_ERROR_TEXT
                ldx     #PAGE_ENTRY_3
                lbsr    page_call
                bcc     error_show_painted

                ; THE WORDS DID NOT GET PAINTED. page_call's carry says the
                ; page did not map and nothing was called - error_text_show
                ; answers carry clear when it has written line 2 - so line 2
                ; still holds whatever was on it: a message from an earlier
                ; fault, or the screen underneath, beside this error's number
                ; on line 1. Leaving that standing tells the operator the wrong
                ; thing with authority. The line is blanked instead, and the
                ; number keeps its meaning on its own.
                ;
                ; The same read-back fault on the way BACK is treated as
                ; unrecoverable below, because by then there is a paged caller
                ; to return into and no page to return it to. Here there is
                ; nothing wrong with the instrument except that one lookup did
                ; not happen.
                lda     #LCD_LINE2              ; ON THE GLASS ONLY. This used
                ldb     #LCD_COLUMNS            ; lcd_write_line, and every
                lbsr    lcd_blank_raw           ; writer but the raw ones
                                                ; mirrors into lcd_shadow
                                                ; FIRST - so blanking that way
                                                ; blanked line 2 of the screen
                                                ; UNDERNEATH, which
                                                ; lcd_repaint then restored
                                                ; blank when the flash ended.
                                                ; The channel screen would have
                                                ; come back without its
                                                ; frequency and level. The
                                                ; whole of this routine paints
                                                ; raw for that reason, and the
                                                ; one branch added for a failed
                                                ; page switch did not.
error_show_painted
                puls    b
                cmpb    #PAGE_UNKNOWN
                beq     error_show_wait         ; there was no page to go back
                lbsr    page_select_and_verify  ; to, so do not guess at one
                bcc     error_show_wait

                ; AND IF IT DID NOT COME BACK, THERE IS NOTHING TO RETURN TO.
                ; This is reached by lbsr from screens on the paged images -
                ; page2_digital.s does it for a refused key - so the return
                ; address below belongs to a page that is not mapped, and
                ; running lcd_repaint's rts into it would execute whatever
                ; sits at that address in whatever page IS mapped. The carry
                ; was ignored here, which made that reachable from a paged
                ; frame; page_select_and_verify sets it and leaves
                ; current_page unknown, and there is no honest way to return.
                ;
                ; The stack-floor path in boot.s answers the same question the
                ; same way: reset the stack, drop the navigation, open the
                ; Main Selection Level with A2U12 mapped, and re-enter the
                ; foreground. An instrument the operator can still drive is
                ; worth more than the screen that was up. It takes a latch
                ; read-back to fail one it passed seconds earlier, so this is
                ; a hardware fault's landing place rather than a path anybody
                ; walks.
                lds     #STACK_TOP
                lbsr    nav_reset
                lbsr    main_menu_open
                lbra    foreground
error_show_wait
                clr     >last_error             ; show_last_error_screen $C4D3:
                                                ; CLR >$23DE once the number is
                                                ; painted, before the delay
                ldd     #ERROR_FLASH_MS
                lbsr    delay_ms
                lbra    lcd_repaint             ; and the screen underneath is
                                                ; back, lcd_hold cleared with it

; ---------------------------------------------------------------------------
; error_open - the same flash, asked for rather than stumbled into
;
;   uses:  A, B, X, Y, U - through error_show
;
; The stock reaches error_show from ONE place: arm l8c20 of
; main_selection_level_handler ($8C14), which is message $0010 - SHIFT then
; INC SET. This firmware also lists it on the service menu, so an engineer
; already in the diagnostics does not have to leave them to read the fault.
;
; IT INSTALLED A KEY HANDLER AND CALLED ITSELF A SCREEN. It is not one: the
; stock paints over what is showing and puts it back three seconds later, and
; a handler taking the keys meant the display returned but the keys did not -
; the next press went to a screen that was no longer on the glass. The service
; menu is still underneath and still has them.
; ---------------------------------------------------------------------------
error_open
                lbra    error_show
