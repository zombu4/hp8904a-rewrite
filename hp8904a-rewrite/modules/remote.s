; ===========================================================================
; remote.s - the remote-control interface at $0400-$0407
;
; The whole subsystem is ported from the stock's instruction stream, mapped
; register by register and record by record in firmware/remote_map.md. The
; ARCHITECTURE is the rewrite's: where the stock's parser posts request codes
; into $2217 for a 34-arm message table to route back to the mode handler,
; this firmware's foreground already routes KEYS to the installed screen -
; and the stock's bus commands are, almost to a one, keystroke equivalents
; (its own keymap posts the same codes its parser posts). So a bus command
; here either acts DIRECTLY through the same ABI the screens use - a
; frequency command calls freq_set exactly as ENTER does - or is delivered to
; the installed screen as a code the screen's own handler answers, which is
; the stock's "active mode handler" shape without the table in between.
;
; THE CHIP IS POLLED, NOT INTERRUPT-SERVICED, exactly as the stock does it:
; the stock's irq_body sets a flag and its foreground polls $0406 bit 7 once
; per pass; this foreground calls remote_poll once per pass with no interrupt
; at all, which reaches the same instructions strictly more often. The
; interrupt-handler notes at the end of boot.s carry the reasoning.
; ===========================================================================

; --- the chip's eight registers, as the stock uses them --------------------
; (firmware/remote_map.md section 1.3; the names are the stock's)
rmt_data        equ     $0400           ; byte in (read) / byte out (write)
rmt_isr1        equ     $0401           ; cleared on read: bit0 byte-in,
                                        ; bit1 byte-out ready, bit3 device
                                        ; clear, bit5 trigger, bit7 undecoded
rmt_isr2        equ     $0402           ; bit0 addressed-state change, bit1
                                        ; remote change, bit3 serial poll,
                                        ; bit4 the remote LEVEL
rmt_spstat      equ     $0403           ; the serial-poll status byte. The
                                        ; stock reads it back after a write
                                        ; and defers on mismatch; this port
                                        ; writes it and does not read it
rmt_adstat      equ     $0404           ; bit1 talk, bit2 listen, bit5 END
rmt_aux         equ     $0405           ; the auxiliary/command register
rmt_adr0        equ     $0406           ; bit7 mirrors the INT pin
rmt_adr1        equ     $0407           ; written once at init

RMT_AUX_RESET   equ     $02             ; the init writes, in the stock's
RMT_AUX_SRQ     equ     $09             ; order - see remote_init
RMT_AUX_GTL1    equ     $0D             ; the go-to-local pair
RMT_AUX_GTL2    equ     $05
RMT_AUX_EOI     equ     $06             ; the next data byte carries EOI

; BIT 6 OF THE SERIAL POLL MODE REGISTER, and it is not just another status
; bit: "Bit 6 of this register is reserved for the rsv (request service)
; local message. Setting this bit to 1 causes the 8291A to assert its SRQ
; line" - the datasheet, transcribed in firmware/datasheets/P8291A-NOTES.md.
; The chip clears it itself once the controller has read the byte, and
; reports that with the SPC interrupt, which is the ISR2 bit 3 the poll loop
; below services.
RMT_SP_RSV      equ     $40

; THE BIT THE POLL SETS AND NOBODY READS. post_flag_2281_b8 ($9A89) - LDD
; >$2281 / ORA #$01 / STD >$2281 - is the last call gpib_serial_poll_service
; makes, at $9309, so bit 8 of the stock's pending-action word is set once per
; serial poll. The note on rmt_poll_flag in hp8904a-rewrite/modules/scratch.inc
; carries the evidence that nothing on the instrument reads it.
RMT_POLL_TAKEN  equ     $01

; --- rmt_flags bits --------------------------------------------------------
; They are declared in common/formats.inc, not here: the tone screen reads
; RF_REMOTE to tell a bus entry from a keyed one, and it is assembled into a
; paged image that never sees this file.

; RK_* (what a value commits to) and RMT_RQ (the screen-delivery code base)
; are in common/formats.inc: the tone and digital screens test them too.

; --- the four annunciator lamps, the stock's own bit assignments -----------
; update_talk_listen_leds ($9170) lights each lamp from the address status
; bit of the same weight: $0404 bit 2 selects AND $FB or led_listen_off
; (OR $04), and bit 1 selects $9A4B's AND $FD or led_talk_off (OR $02). The
; 8291A's address status has TA at bit 1 and LA at bit 2, so TALK is lamp
; bit 1 and LISTEN lamp bit 2. This said bit 2 for talk and bit 1 for listen,
; and during a reply the rewrite lit bit 2 where the stock lit bit 1
; (acceptance 4.4, 2026-09-16). The SRQ annunciator is bit 0 (OR $01 into
; $2420) and REMOTE is bit 3 ($F7 mask) - remote_map.md sections 1.3 and 5.2.
RMT_LAMP_SRQ    equ     $01
RMT_LAMP_TALK   equ     $02
RMT_LAMP_LISTEN equ     $04
RMT_LAMP_REMOTE equ     $08

; --- WHICH EVENTS REQUEST SERVICE, AND ON WHICH BIT ------------------------
; The serial-poll status byte carries one bit per event, and the mask $2249
; carries one enable bit per event in the same positions. Both are indexed
; through the weight table d929d ($929D), which is $01,$02,$04,$08,$10,$20,
; $00,$80 - index 6 has weight $00, and status_bit_write ($9743) short-
; circuits it with CMPA #$06 / BEQ before it does anything, so index 6 is not
; an event at all.
;
; EVERY ASSERT IN THE STOCK COMES THROUGH ONE DOOR, and this is how that is
; known rather than assumed: gpib_assert_service_request ($91E2) has exactly
; one caller, status_bit_write ($9743); status_bit_write has exactly one
; caller, gpib_set_condition ($9B60); and gpib_set_condition has two,
; hpib_status_bit_release ($9DB7), which always passes the value zero and is
; therefore the release half, and report_error_and_pulse_status_bit ($9DD3).
; So the whole question is which index the 25 call sites of $9DD3 pass, and
; they pass five:
;
;   0  $01  the general error bit. Eighteen of the sites, every error code
;           the parser and the key handlers report, $2A among them - the
;           block at $A833 in pending_setting_service ($A73E), reported when
;           a field IS armed and gpib_number_to_entry_buffer refuses the
;           number.
;   1  $02  the reference loop reports out of lock, error $0C, raised in
;           foreground_main_loop in the block at $84EE when int_latch bit 5
;           is set and event_flags bit 5 was clear. ERR_REF_UNLOCK here.
;   2  $04  a sequence output STARTED, error $00FF - no number, the event is
;           the report. Two sites, one per sequence screen.
;   3  $08  a sequence output FINISHED, error $00FF, the same two screens.
;   4  $10  a reverse-power relay tripped, error $0D, raised in
;           foreground_main_loop in the block at $85D4 when the low nibble of
;           int_latch EOR $0F is non-zero and event_flags bit 6 was clear.
;           ERR_FAULT_LINE here.
;
; Bits 5 and 7 have weights in the table and no site that raises them.
; ALL FIVE ARE GATED ON REMOTE: the $0C, $0D and both sequence sites test
; event_flags bit 3 before they call, and the eighteen error sites sit inside
; handlers that test the same bit - the block at $8CAA in
; main_selection_level_handler, and the one reaching $F425 in
; output_onoff_key_handler. error_record's RF_REMOTE gate is that gate, and
; remote_srq_event below is the sequence screens' - they are in paged images
; and reach it through ABI_remote_srq_event.
;
; THE FIVE WEIGHTS THEMSELVES ARE DECLARED IN
; hp8904a-rewrite/common/formats.inc - RMT_SRQ_ERROR, RMT_SRQ_REF_UNLOCK,
; RMT_SRQ_SEQ_START, RMT_SRQ_SEQ_END and RMT_SRQ_FAULT_LINE - because bits 2
; and 3 are raised from page 1 and page 2, which cannot see a name declared
; here. The reasoning stays with the enumeration; only the numbers moved.

; --- THE THREE ERRORS A FIELD THAT WAS NEVER ARMED ANSWERS WITH -------------
; pending_setting_service ($A73E) gates three of its five legs on $238F being
; non-zero and reports a DIFFERENT code on each when it is clear: $A8D9 is
; $2D for a mode code (bit 4 of $2281), $A94F is $2F for a unit (bit 3) and
; $A853 is $2B for a bare number (bit 1) - the last being ERR_RMT_NO_FIELD,
; which the shared formats.inc already carries. The fourth code below, $2C,
; is the one $A8C3 reports when a field IS armed and scale_code_allowed
; ($A600) refuses the code for it.
;
; They are declared HERE rather than in the shared include because remote.s
; is the only file that raises any of them: the screens arm a field, and
; every refusal for a value that reached no field is written by this image.
; The text of each is in page3_errors.s, indexed by the same number - $2C
; err_t7623 'Invalid Unique data received', $2D err_t763f 'Unique data
; received but not expected', $2F err_t7676 'Terminator received but not
; expected'.
ERR_RMT_UNIQUE_BAD  equ $2C         ; a mode code the armed field cannot take
ERR_RMT_UNIQUE_NONE equ $2D         ; a mode code with no field armed
ERR_RMT_TERM_NONE   equ $2F         ; a unit with no field armed

; ---------------------------------------------------------------------------
; remote_init - program the chip exactly as the stock's gpib_chip_init does
;
;   uses:  A, B
;
; The thirteen writes, in the stock's order, with the shipped driver record
; {$80,$81,$BF,[$227E],[$227F]} folded to the values that record produces
; (remote_map.md section 1.1). The order is kept because the chip is real
; and the stock's order is the one known to program it.
; ---------------------------------------------------------------------------
remote_init
                lda     #RMT_AUX_RESET          ; 1: reset
                sta     >rmt_aux
                lda     #$01                    ; 2: $0404 <= $01. The shipped
                sta     >rmt_adstat             ; record byte $81 & $30 is
                                                ; zero, so gpib_chip_init
                                                ; takes l8fdc: INCA / STA
                                                ; >gpib_spoll on every power-
                                                ; up. A first draft left this
                                                ; out on a reading of the
                                                ; other leg; the critique read
                                                ; the branch.

                lda     >remote_address         ; 3: the address, masked; the
                anda    #$1F                    ; stock decrements a stored
                cmpa    #$1F                    ; $1F to $1E rather than pass
                bne     remote_init_addr        ; the all-ones value through
                deca
remote_init_addr
                sta     >rmt_adr0
                lda     #$E0                    ; 4: the second adr0 write
                sta     >rmt_adr0
                lda     #$21                    ; 5
                sta     >rmt_aux
                lda     #$80                    ; 6
                sta     >rmt_aux
                lda     #$AF                    ; 7: $A3 | $04 | $08 with the
                sta     >rmt_aux                ; shipped record byte $81
                clra
                sta     >rmt_spstat             ; 8: status byte clear
                sta     >rmt_adr1               ; 9
                lda     #$70                    ; 10
                sta     >rmt_aux
                ldd     #$AB0F                  ; 11: both interrupt enables
                std     >rmt_isr1               ; in one 16-bit store
                clra                            ; 13: the final auxiliary
                sta     >rmt_aux                ; write for record byte $80

                clr     >rmt_flags
                clr     >rmt_char_state
                clr     >rmt_pend_kind
                clr     >rmt_status
                clr     >rmt_srq_pending        ; gpib_chip_init ($8F9F) walks
                clr     >rmt_srq_release        ; $2246 upward clearing the
                                                ; block these two live in
                clr     >rmt_tx_len
                clr     >rmt_out                ; rmt_out is battery-backed RAM
                                                ; and its first byte is what
                                                ; remote_byte_out reads to see
                                                ; whether a reply is waiting, so
                                                ; a cold talker must not inherit
                                                ; one from whatever the battery
                                                ; held
                clr     >rmt_cpt
                lbsr    remote_parser_reset
                lda     #$0F                    ; all four bus lamps
                lbra    led_off

; ---------------------------------------------------------------------------
; remote_poll - service the chip; called once per foreground pass
;
;   uses:  A, B, X, Y, U
;
; The dispatch order is the stock's gpib_poll_and_service ($90D3): the INT
; mirror first, then the latched pair, then each bit in its order.
; ---------------------------------------------------------------------------
remote_poll
                lda     >rmt_adr0
                lbpl    remote_poll_done        ; INT clear: nothing pending

                ldd     >rmt_isr1               ; A = ISR1, B = ISR2, one LDD
                pshs    a,b                     ; as the stock latches them

                ; --- ISR2 bits 4 and 5 are LEVELS: remote and lockout -------
                ; The stock rewrites its shadow $2247 from the live ISR2 on
                ; every poll and tests bit 4 there before accepting a byte and
                ; bit 5 before honouring LOCAL. Following the change bit alone
                ; (a first draft) lost remote after remote_init re-ran from an
                ; address commit, and never set lockout at all.
                lda     >rmt_flags
                anda    #$FC                    ; ~(RF_REMOTE|RF_LOCKOUT)
                bitb    #$10
                beq     remote_poll_lvl_lock
                ora     #RF_REMOTE
remote_poll_lvl_lock
                bitb    #$20
                beq     remote_poll_lvl_done
                ora     #RF_LOCKOUT
remote_poll_lvl_done
                sta     >rmt_flags

                ; --- ISR2 bit 0: the addressed state changed ---------------
                ldb     1,s
                bitb    #$01
                beq     remote_poll_remote
                lda     >rmt_adstat
                bita    #$02                    ; talk-addressed?
                beq     remote_poll_talk_off
                lda     #RMT_LAMP_TALK
                lbsr    led_on
                lbsr    remote_prompt_message   ; TACS posts event 13 ($8E74)
                bra     remote_poll_listen
remote_poll_talk_off
                lda     #RMT_LAMP_TALK
                lbsr    led_off
remote_poll_listen
                lda     >rmt_adstat
                bita    #$04                    ; listen-addressed?
                beq     remote_poll_listen_off
                lda     #RMT_LAMP_LISTEN
                lbsr    led_on
                bra     remote_poll_remote
remote_poll_listen_off
                lda     #RMT_LAMP_LISTEN
                lbsr    led_off

                ; --- ISR2 bit 1: remote/local changed ----------------------
remote_poll_remote
                ldb     1,s
                bitb    #$02
                beq     remote_poll_spoll
                bitb    #$10                    ; the level, latched with the
                beq     remote_poll_local       ; same read
                clr     >entry_armed            ; AND THE EDIT IN PROGRESS ENDS.
                                                ; The operator's half-typed
                                                ; value is not the controller's
                                                ; to commit, and when the panel
                                                ; comes back a digit does
                                                ; nothing until a field key
                                                ; arms a field again - which is
                                                ; what the instrument does,
                                                ; driven 2026-09-12

                ; AND THE DIGITS COME OFF THE GLASS WITH IT. Ending the edit
                ; left the half-typed echo standing where the instrument puts
                ; the stored value back: driven 2026-09-13, PHASE armed and
                ; '4' typed, then one bus command - the stock's line 2 returns
                ; to 'PHASE   0.0 deg' and this firmware's stayed at
                ; 'PHASE 4'. Found by the differential harness on seed 1,
                ; step 14.
                ;
                ; The count is what the field painter asks: with digits
                ; pending it paints the echo, with none it paints the record.
                ; So the entry is emptied and the screen told to repaint
                ; itself, which is the one thing KEY_REFRESH is for.
                ;
                ; The hop screen's painter asks its own flag, not the count:
                ; hop_show echoes while hop_entry_active is set, which is the
                ; stock's first-key flag $23A7, and $B38B clears that too
                ; (CLR >$23A7 at $B391). Left set, the repaint echoed an empty
                ; buffer - seed 2 step 133, PHASE '2' on the Hop Ram record
                ; and then 'AHR 251 SC;': the stock shows '  0.0 deg' and this
                ; firmware showed '      deg'.
                clr     >entry_count
                clr     >hop_entry_active
                lbsr    remote_refresh

                ; AND THE CURSOR GOES OFF, EVERY TIME. enter_remote_state
                ; ($9EB9) calls entry_exit_restore_display ($B38B) with 1 at
                ; $9F1A, after its two status reports and before it clears
                ; $2202 bit 3, and that routine's tail is $B3BA
                ; lcd_display_control(1) with no test in front of it - so the
                ; instrument sends the cursor-off byte on every remote edge,
                ; entry open or not, after the repaint and the screen's hook.
                ; Measured on the stock in the emulator, seed 1 of the
                ; differential harness: a $0C at each REN assertion, where
                ; this firmware sent nothing and left an armed field's cursor
                ; showing through every bus command that followed.
                lbsr    entry_cursor_off

                ; AND A MODAL OVERLAY GOES WITH IT. entry_exit_restore_display
                ; ($B38B) repaints from the 80-byte shadow at $242B and then
                ; JSRs through the screen pointer, and the shadow holds the
                ; screen UNDERNEATH - save_recall_prompt ($F331) paints with
                ; lcd_write_string_at ($D8A5), which writes the controller and
                ; not the shadow. So the repaint at the remote edge is what
                ; takes the prompt off the glass on the instrument.
                ;
                ; TRACED ON BOTH MACHINES rather than reasoned. With the Save
                ; prompt up, a bus 'HZ;' on the stock runs enter_remote_state
                ; ($9EB9) -> entry_exit_restore_display -> lcd_repaint_shadow
                ; ($D9C6) and lands on 'ch A:'; here it ran remote_refresh ->
                ; remote_deliver -> remote_prompt_message -> register_prompt_key
                ; -> register_prompt_paint and REPAINTED THE PROMPT. Neither
                ; $F1D9 nor any unit arm is entered on either machine, so this
                ; is not the prompt handler's job on either.
                ;
                ; remote_prompt_message lets the prompt go only for a PENDING
                ; SV or RC - measured, rmt_pend_kind is 0 with the prompt up
                ; and stays 0 across a bare 'HZ;' - so nothing took it down.
                ; overlay_is_up makes this inert on every ordinary remote edge:
                ; it compares screen_handler against the three overlay handlers
                ; and register_prompt_dismiss itself does nothing when the
                ; prompt is not the installed one.
                lbsr    register_prompt_dismiss

                lda     #RMT_LAMP_REMOTE
                lbsr    led_on
                bra     remote_poll_spoll
remote_poll_local
                lbsr    remote_gone_local

                ; --- ISR2 bit 3: a serial poll was taken -------------------
remote_poll_spoll
                ldb     1,s
                bitb    #$08
                beq     remote_poll_bytein
                ; gpib_serial_poll_service ($92A5) and the block at $92AD it
                ; falls into. The controller has taken the byte, so rsv is
                ; spent and the deferred releases that were held back for it
                ; can finally be applied - and anything queued while it was
                ; outstanding goes into the next byte and, if the mask allows,
                ; requests service all over again.
                ;
                ; The rewrite used to do this with one ANDA #$BE, which is the
                ; right answer only while exactly one event exists and is
                ; always released the instant it is raised. With five events
                ; and a queue it is not, and a bit still legitimately raised
                ; would have been silently dropped by the poll.
                lda     #$01                    ; $92A5's first act
                sta     >rmt_aux
                lda     >rmt_status             ; $92AD: rsv is spent
                anda    #~RMT_SP_RSV
                sta     >rmt_status
                sta     >rmt_spstat
                lda     #RMT_LAMP_SRQ           ; $92B4 srq_annunciator_off
                lbsr    led_off

                lda     >rmt_srq_release        ; $92B7: the releases that
                coma                            ; were held back for this poll
                anda    >rmt_status
                clr     >rmt_srq_release        ; $92CF STB >$224e from $224F,
                                                ; and $224F is provably never
                                                ; set - see the scratch note
                ora     >rmt_srq_pending        ; $92CC: and what was queued
                ldb     >rmt_srq_pending        ; $92D8: does the mask ask for
                bitb    >remote_sre_mask        ; service over any of it?
                beq     remote_poll_spoll_byte
                ora     #RMT_SP_RSV
                ldb     #RMT_AUX_SRQ
                stb     >rmt_aux
remote_poll_spoll_byte
                sta     >rmt_status             ; $92E7: the byte, and the
                sta     >rmt_spstat             ; store is the SRQ line again
                bita    #RMT_SP_RSV             ; $92FC: and the lamp with it
                beq     remote_poll_spoll_done
                lda     #RMT_LAMP_SRQ
                lbsr    led_on
remote_poll_spoll_done
                clr     >rmt_srq_pending        ; $9303

                ; AND THE FLAG THE POLL LEAVES BEHIND, $9309's call to
                ; post_flag_2281_b8 ($9A89): LDD >$2281 / ORA #$01 / STD
                ; >$2281, bit 8 of the pending-action word, set at the end of
                ; every poll. It is here because the instrument does it on
                ; every poll and nothing in the five images reads it back -
                ; the evidence for that is on rmt_poll_flag in
                ; hp8904a-rewrite/modules/scratch.inc - so it is state kept
                ; and not behaviour anyone can see. Dropping it would be
                ; deciding that a write the instrument makes does not count.
                lda     >rmt_poll_flag
                ora     #RMT_POLL_TAKEN
                sta     >rmt_poll_flag

                ; --- ISR1 bit 0: a data byte is in -------------------------
remote_poll_bytein
                lda     ,s
                bita    #$01
                beq     remote_poll_byteout
                lbsr    remote_byte_in

                ; --- ISR1 bit 1: the chip can take an output byte ----------
remote_poll_byteout
                lda     ,s
                bita    #$02
                beq     remote_poll_clear
                lbsr    remote_byte_out

                ; --- ISR1 bit 3: device clear ------------------------------
remote_poll_clear
                lda     ,s
                bita    #$08
                beq     remote_poll_trigger
                lbsr    remote_parser_reset     ; the stock zeroes $2250/$2253
                clr     >rmt_pend_kind          ; - the whole parse state -
                clr     >rmt_tx_len             ; then posts request 7:
                clr     >rmt_out                ; a reply still waiting for the
                                                ; boundary goes with it
                lbsr    main_menu_open          ; back to the top level

                ; --- ISR1 bit 5: group execute trigger ---------------------
remote_poll_trigger
                lda     ,s
                bita    #$20
                beq     remote_poll_cpt
                ldb     #RMT_RQ+$24             ; the stock posts $24 to the
                lbsr    remote_deliver          ; mode handler; a screen with
                                                ; no use for it refuses, and
                                                ; the refusal reports over the
                                                ; bus exactly as the stock's
                                                ; default arms do

                ; --- ISR1 bit 7: an undecoded command --------------------
remote_poll_cpt
                lda     ,s
                bmi     remote_poll_cpt_go
                clr     >rmt_cpt                ; l9146: CLR >$224d on every
                bra     remote_poll_exit        ; poll without bit 7
remote_poll_cpt_go
                ; gpib_cpt_service ($91B4), instruction for instruction: read
                ; the command back with bit 7 off; $05 is remembered in
                ; rmt_cpt (the stock's $224D); while remembered, any command
                ; >= $60 is echoed to $0405; anything below $60 forgets, and
                ; $15 among them writes $70; every path ends in $0F. This is
                ; the parallel-poll configure / enable / unconfigure sequence
                ; being passed to the chip, and a first draft dropped it.
                lda     >rmt_aux
                anda    #$7F
                cmpa    #$05
                bne     remote_cpt_not5
                sta     >rmt_cpt
                bra     remote_cpt_finish
remote_cpt_not5
                cmpa    #$60
                blo     remote_cpt_low
                tst     >rmt_cpt
                beq     remote_cpt_finish
                sta     >rmt_aux
                bra     remote_cpt_finish
remote_cpt_low
                clr     >rmt_cpt
                cmpa    #$15
                bne     remote_cpt_finish
                lda     #$70
                sta     >rmt_aux
remote_cpt_finish
                lda     #$0F
                sta     >rmt_aux
remote_poll_exit
                puls    a,b
remote_poll_done
                rts

; ---------------------------------------------------------------------------
; remote_gone_local - the bus released remote, or go-to-local succeeded
;
;   uses:  A, B, X, Y, U - B carries KEY_GONE_LOCAL into remote_deliver at
;          the end, and the screen handler it jumps into takes the rest. A
;          callee's clobbers are the caller's.
; ---------------------------------------------------------------------------
remote_gone_local
                lda     >rmt_flags
                anda    #$FC                    ; ~(RF_REMOTE|RF_LOCKOUT)
                sta     >rmt_flags
                lbsr    remote_parser_reset     ; the parser resets when
                clr     >rmt_pend_kind          ; remote drops, as $918F's
                                                ; clear leg zeroes $2250/$2253
                ; AND THE SERVICE REQUEST IS CLEARED: annunciator_remote_off
                ; ($9A5B) first runs hpib_reset_and_repaint ($9F45), which
                ; calls clear_service_request ($9E0F) - the six status shadows
                ; zeroed, $0405 <= $01, $0403 <= $00, SRQ lamp off. A first
                ; draft left a pending SRQ and its lamp standing after LOCAL
                ; (the audit's finding).
                ;
                ; ALL THREE SHADOWS, not just the byte. gpib_clear_service_
                ; request ($9072) zeroes $224A, $224B, $224E, $224F, $226A and
                ; $226B before it writes the chip; the two of those that are
                ; live here are the queue and the deferred-release set, and a
                ; weight left in either would come back into the first status
                ; byte built after the instrument returned to remote.
                clr     >rmt_status
                clr     >rmt_srq_pending
                clr     >rmt_srq_release
                lda     #$01
                sta     >rmt_aux
                clra
                sta     >rmt_spstat
                lda     #RMT_LAMP_REMOTE|RMT_LAMP_SRQ
                lbsr    led_off

                ; AND THE GLASS GOES BACK TO THE STORED VALUES, which is the
                ; other half of what LOCAL does on the instrument.
                ; annunciator_remote_off ($9A5B) runs hpib_reset_and_repaint
                ; ($9F34) first, and that calls lcd_repaint_shadow ($D9C6) -
                ; both lines rewritten from the 80-byte shadow - and then
                ; post_request_code ($8AD0), whose code reaches the mode
                ; handler: on page 0 that is dispatch_ui_event ($5D0C)'s arm
                ; l5D33, which zeroes the field id $2215 and calls
                ; end_field_edit ($5CE8).
                ;
                ; DRIVEN ON BOTH 2026-09-13, the differential harness's own
                ; preamble on ch A: after INC SET the phase field shows the
                ; INCREMENT, 'PHASE^G  1.0 deg', on both; a bus 'FRD 250 UV;'
                ; leaves both at 1.0 with the marker gone; and then RELEASING
                ; REN returns the stock to 'PHASE   0.0 deg' with $2215 = 0000
                ; and $238F = 00 while this firmware stayed at 1.0 - and
                ; stayed there through the next arrow, which both machines
                ; refuse. That is seed 19, step 4, and the arrow was never the
                ; fault: the repaint was missing from the LOCAL transition.
                ;
                ; remote_poll_remote does the same thing on the way IN, for
                ; the same reason and with the same one call.
                lbsr    remote_refresh

                ; AND THEN REQUEST 1, WHICH IS NOT THE REPAINT. The paragraph
                ; above names both halves of $9F45 and only the first was
                ; here. hpib_reset_and_repaint ends LDU #$0001 / LDY #$0002 /
                ; post_request_code ($8AD0) at $9F8C, and that request reaches
                ; the installed mode handler: l5d33 zeroes the FIELD ID $2215
                ; and calls end_field_edit ($5CE8) before select_menu_page
                ; ($514D) repaints. The repaint alone put the stored value
                ; back on the glass and left the field still selected, and the
                ; field id is what the arrows and INCR SET read.
                ;
                ; MEASURED ON BOTH, 2026-09-13, ch A: PHASE, 0, deg, REN
                ; asserted, REN released - the stock's $2215 goes 3, 3, 0 and
                ; this firmware's field_index went 3, 3, 3. With or without a
                ; bus command in between; 'DC 1 VL;' changes neither reading.
                ; That third 3 is why the arrow guard could not be the field
                ; id until this call existed.
                ;
                ; THE OTHER WAY ROUND IS NOT SYMMETRIC and must not be made
                ; so: enter_remote_state ($9EB9) posts nothing at all - it
                ; calls entry_exit_restore_display ($B38B), whose only RAM is
                ; $2211, $23A7 and $23A8 - so going REMOTE clears the armed
                ; flag and leaves the field id standing. Same measurement, the
                ; middle column: $2215 = 3 with $23A8 = 00.
                ldb     #KEY_GONE_LOCAL
                lbra    remote_deliver

; ---------------------------------------------------------------------------
; remote_parser_reset - forget a command in progress, entirely
;
;   uses:  A
;
; The stock's $2250/$2253 zeroing: the mnemonic walk, a parked type-2 record,
; a number in progress and a closed-but-uncommitted value all go. A first
; draft cleared the walk and left the rest, so "FRA 12", device clear,
; "APA 3 VL" committed a stale 12 into no field and raised SRQ.
; ---------------------------------------------------------------------------
remote_parser_reset
                clr     >rmt_char_state
                clr     >rmt_stream
                clr     >rmt_defer
                clr     >rmt_defer+1
                clr     >rmt_in_exp
                clr     >rmt_frac_on
                lda     >rmt_flags
                anda    #$03                    ; ~(RF_NUMBER|RF_VALUE|RF_MINUS|RF_OVER|RF_CLOSING|RF_HELD)
                sta     >rmt_flags
                rts

; ---------------------------------------------------------------------------
; remote_local_key - the LOCAL key, offered by the foreground while remote
;
;   exit:  carry SET only under lockout, where the key does nothing at all
;   uses:  A
;
; hpib_return_to_local ($9095): only when lockout is clear and remote is set
; does it issue the AUXMR pair $0D then $05 and drop the state; under
; lockout the key does nothing at all.
; ---------------------------------------------------------------------------
remote_local_key
                lda     >rmt_flags
                bita    #RF_REMOTE
                beq     remote_local_no
                bita    #RF_LOCKOUT
                bne     remote_local_eaten      ; locked out: consumed, and
                                                ; deliberately does nothing
                lda     #RMT_AUX_GTL1
                sta     >rmt_aux
                lda     #RMT_AUX_GTL2
                sta     >rmt_aux
                lbsr    remote_gone_local
remote_local_no                                 ; and the key GOES ON to the
                andcc   #~CC_CARRY              ; screen: event_local_key
                rts                             ; ($8DE6) ends in LBRA
                                                ; call_installed_handler_220f
                                                ; in every state, so the
                                                ; panel's own LOCAL action
                                                ; follows the go-to-local
remote_local_eaten
                orcc    #CC_CARRY               ; only lockout consumes it
                rts

; ---------------------------------------------------------------------------
; remote_error - report a parser or value error over the bus
;
;   entry: B = the error code (this firmware's ERR_ numbering)
;   uses:  A, B
;
; report_error_and_pulse_status_bit ($9DD3), and the name is the whole of it:
; the number lands where the error screen reads it, and the status bit is SET
; AND RELEASED AGAIN in the same breath. $9DD3 calls gpib_set_condition
; ($9B60) with the error code as the value, which reaches status_bit_write
; ($9743) and, the value being non-zero, gpib_assert_service_request ($91E2);
; then it calls hpib_status_bit_release ($9DB7), which is gpib_set_condition
; with the value ZERO, which reaches status_bit_write again and this time
; hpib_status_bit_clear ($9237).
;
; This firmware set the bit and never released it, so with the event masked
; off the serial-poll byte read 1 where the instrument reads 0, and it stayed
; 1 for the rest of the session.
;
; WHICH BIT is the second argument at the stock's call site, and two error
; codes carry a bit of their own - see the RMT_SRQ_* block at the top of this
; file for the enumeration and where each is raised. Code and bit are one to
; one across all 25 sites, so choosing on the code here puts the same bit on
; the wire as the instrument does without threading a second argument through
; sixty call sites.
; ---------------------------------------------------------------------------
remote_error
                stb     >last_error
                lda     #RMT_SRQ_ERROR          ; bit 0 unless this is one of
                cmpb    #ERR_REF_UNLOCK         ; the two codes the stock
                bne     remote_error_relay      ; gives a bit of its own
                lda     #RMT_SRQ_REF_UNLOCK
                bra     remote_error_pulse
remote_error_relay
                cmpb    #ERR_FAULT_LINE
                bne     remote_error_pulse
                lda     #RMT_SRQ_FAULT_LINE
remote_error_pulse
                lbsr    remote_srq_raise        ; B is still the code, so the
                                                ; value store gets the number
                                                ; the stock puts there; A is
                                                ; preserved, so the release
                lbra    remote_srq_release      ; below has the same weight

; ---------------------------------------------------------------------------
; remote_srq_event - a sequence screen reports that its output started or
;                    finished
;
;   entry: A = RMT_SRQ_SEQ_START or RMT_SRQ_SEQ_END
;   uses:  A, B
;
; ABI SLOT 108, because both callers are in paged images. The stock has four
; sites, two per sequence screen, and each is the same eleven instructions:
;
;   LDD >event_flags / ANDA #$00 / ANDB #$08 / CMPD #$0000 / LBEQ past
;   LDU #$00ff / LDB #<index> / SEX / TFR D,Y / LDX #$0004 / PSHS X,Y,U
;   LBSR $9DD3 / LEAS 6,S
;
; - firmware/src-generated/a2u13_page1.s lines 1302 and 1325 inside
; seq_output_set_running ($4702), and a2u13_page2.s lines 6978 and 7001
; inside sequence_run_start_stop ($67A3). Index 2 on the start leg, index 3
; on the stop leg, code $00FF on all four.
;
; THE GATE IS event_flags BIT 3 - the instrument only reports these while it
; is remote, exactly as it only reports errors while it is remote - and
; rmt_flags RF_REMOTE is this firmware's cell for that bit
; (hp8904a-rewrite/common/formats.inc says so where RF_REMOTE is declared).
; A screen that called this from a local run would put a status bit on the
; wire that the instrument never puts there.
;
; NEITHER BIT IS IN THE POWER-ON MASK. power_on_reinit ($C2C4) seeds $227E
; with $13 - bits 0, 1 and 4 - so a controller has to enable bit 2 or bit 3
; itself before either event asks for service. Until it does, the weight
; still reaches the status byte on the chip (the masked leg of
; remote_srq_assert stores it anyway, as $91E2's BEQ at $9203 does) and the
; SRQ line stays down. That is why four missing reports were invisible on the
; bench.
;
; THE STOP LEG CAN ARRIVE FROM INTERRUPT CONTEXT, and it does so in the stock
; too: the tone player's single-shot end at $44E0 calls sequence_stop_from_isr
; ($6C45), which reaches seq_output_set_running ($4702) with zero and so
; reaches $9DD3 from the NMI. So this routine's writes to rmt_status,
; rmt_srq_pending and the chip can land between two instructions of
; remote_poll, and the stock's do too - $9743's PSHS CC,A,B,DP,X,Y saves
; registers, not the cells. It is recorded rather than guarded, because a
; guard here would be this firmware behaving differently from the instrument
; on a race the instrument has.
; ---------------------------------------------------------------------------
remote_srq_event
                ldb     >rmt_flags              ; the stock's LDD >event_flags
                bitb    #RF_REMOTE              ; / ANDB #$08 / CMPD #$0000
                beq     remote_srq_event_local
                ldb     #RMT_SRQ_SEQ_CODE       ; $9DD3's #$00FF, low byte
                lbsr    remote_srq_raise
                lbra    remote_srq_release      ; $9DD3 releases what it sets
remote_srq_event_local
                rts

; ---------------------------------------------------------------------------
; remote_srq_index - which of the eight status bits a weight is
;
;   entry: A = the weight, one bit of the table d929d ($929D)
;   exit:  B = its index, 0 to 7
;   uses:  A, B
;
; The stock indexes BY INDEX and looks the weight up: $01,$02,$04,$08,$10,
; $20,$00,$80 at $929D. This firmware carries the weight, because the weight
; is what goes into the status byte and one to one is one to one - so the
; index has to be recovered where the stock's array $226C+index is written.
; Eight shifts at most, once per service request, which is nothing beside the
; chip writes on either side of it.
;
; A ZERO WEIGHT IS INDEX 6 AND NOTHING ELSE: the sixth entry is the only zero
; in the table, and that hole is exactly where RQS sits in the byte. So a
; walk that finds no bit answers 6, and the caller's CMPB #$06 then refuses
; the store the way status_bit_write's own CMPA #$06 / BEQ $975B does. No
; caller passes zero; this is what keeps an impossible one inside the array.
; ---------------------------------------------------------------------------
remote_srq_index
                clrb
remote_srq_index_next
                lsra                            ; bit 0 out into the carry
                bcs     remote_srq_index_done
                incb
                cmpb    #$08
                blo     remote_srq_index_next
                ldb     #$06                    ; no bit at all: the hole
remote_srq_index_done
                rts

; ---------------------------------------------------------------------------
; remote_srq_raise - the value store, then the request: status_bit_write
;                    ($9743) with a non-zero value
;
;   entry: A = the event's weight, B = the error code it carries
;   exit:  A, B, X unchanged
;
; $9743 is two things, and only one of them was here. It stores the code -
; LDX #$226C / STB A,X - and then calls gpib_assert_service_request ($91E2).
; The store is what read_srq_event_value ($975E) reads back, and the note on
; rmt_srq_value in hp8904a-rewrite/modules/scratch.inc records that $975E's
; own caller is reached from nowhere in the five images, so the array is
; written on this instrument and never read on it. It is ported because the
; write is on the path every service request takes: leaving it out would mean
; this firmware's RAM differs from the instrument's after a fault, and the
; row that asks about it could never be closed by reading the code again.
;
; X IS PRESERVED because remote_error's header promises A and B only, and it
; is reached by LBRA from three dozen sites in the parser that are holding a
; record pointer in X.
; ---------------------------------------------------------------------------
remote_srq_raise
                pshs    a,b,x                   ; ,s = weight, 1,s = code
                lbsr    remote_srq_index        ; B = 0..7 for that weight
                cmpb    #$06                    ; $9743's own refusal: index 6
                beq     remote_srq_raise_ask    ; has weight $00 and is not an
                                                ; event, so nothing is stored
                ldx     #rmt_srq_value          ; ABX AND NOT B,X: the offset
                abx                             ; is unsigned either way for
                                                ; 0 to 7, and an operand
                                                ; spelled `b,x` reads to
                                                ; hp8904a-rewrite/tests/asmscan.py
                                                ; as a store to a cell called
                                                ; `b`, which put a symbol that
                                                ; does not exist on
                                                ; test_shared_state's list
                lda     1,s                     ; the code
                sta     ,x                      ; $226C+index
remote_srq_raise_ask
                lda     ,s                      ; the weight again
                lbsr    remote_srq_assert
                puls    a,b,x
                rts

; ---------------------------------------------------------------------------
; remote_srq_assert - raise one status bit and request service for it
;
;   entry: A = the event's weight, one bit
;   exit:  A unchanged
;   uses:  B
;
; gpib_assert_service_request ($91E2) has three legs, and each is here for a
; reason:
;
;   rsv ALREADY SET. A request is outstanding and the controller has not yet
;   read the byte it is asking about, so the byte on the chip may not change.
;   The stock ORs the new weight into $224B instead - LDA >$224b / ORA ,X /
;   STA >$224b - unless it is already in the byte, and the serial-poll
;   service merges it afterwards. Without this leg a second fault arriving
;   while the first is unanswered is lost.
;
;   rsv CLEAR, the event ENABLED. $91FC ORB ,X puts the weight in the byte,
;   $91FE LDA >$2249 / $9201 BITA ,X tests the mask, and on the enabled leg
;   $9204 JSR >annunciator0_on lights the panel's SRQ lamp, ORB #$40 sets rsv
;   and LDA #$09 / STA >$0405 is the auxiliary write that goes with it. Then
;   $9216 STB >$0403 puts the byte on the chip - and writing bit 6 of the
;   Serial Poll Mode register is what asserts the SRQ line, which is the
;   datasheet passage transcribed in firmware/datasheets/P8291A-NOTES.md.
;
;   rsv CLEAR, the event MASKED OFF. The same $9216 store happens: the BEQ at
;   $9203 jumps to the store, not to the exit. So the status bit reaches the
;   wire either way and only rsv, the lamp and the auxiliary write are
;   withheld - a controller polling a masked-off instrument still learns what
;   happened, it simply is not interrupted about it.
;
; The tail at $921C takes the weight back out of the deferred-release set,
; which is what lets a bit raised again after a release stay raised.
; ---------------------------------------------------------------------------
remote_srq_assert
                pshs    a                       ; the weight, wanted throughout
                ldb     >rmt_status
                bitb    #RMT_SP_RSV             ; is a request outstanding?
                beq     remote_srq_assert_idle

                bitb    ,s                      ; already in the byte the
                bne     remote_srq_assert_done  ; controller will read?
                lda     >rmt_srq_pending        ; no: queue it for the byte
                ora     ,s                      ; after the poll
                sta     >rmt_srq_pending
                bra     remote_srq_assert_done

remote_srq_assert_idle
                orb     ,s                      ; the weight into the byte
                lda     >remote_sre_mask        ; and the mask decides whether
                anda    ,s                      ; the instrument ASKS about it
                beq     remote_srq_assert_write
                lda     #RMT_LAMP_SRQ           ; the panel says so first
                lbsr    led_on                  ; (led_on touches A only)
                orb     #RMT_SP_RSV             ; rsv: the SRQ line itself
                lda     #RMT_AUX_SRQ
                sta     >rmt_aux
remote_srq_assert_write
                stb     >rmt_spstat             ; the byte, on both legs
                stb     >rmt_status

remote_srq_assert_done
                lda     ,s                      ; $921C: out of the deferred
                coma                            ; release set, so raising a
                anda    >rmt_srq_release        ; bit again after releasing it
                sta     >rmt_srq_release        ; keeps it raised
                puls    a
                rts

; ---------------------------------------------------------------------------
; remote_srq_release - let one status bit go again
;
;   entry: A = the event's weight, one bit
;   exit:  A unchanged
;   uses:  B
;
; hpib_status_bit_clear ($9237), the deassert half of the pair, reached from
; status_bit_write ($9743) whenever the value argument is zero. Two of its
; legs are live on this instrument:
;
;   rsv CLEAR. Nobody is waiting on a byte, so the bit goes now: LDA ,X /
;   COMA / ANDA >$224a / STA >$224a / STA >$0403. The stock reaches this
;   through $9243 LDA >$2248 / BITA ,X, and $2248 is always $BF - the note on
;   rmt_srq_pending in hp8904a-rewrite/modules/scratch.inc has the evidence -
;   so for every weight in the table this is the leg taken.
;
;   rsv SET. The controller is going to read the byte and must still find the
;   bit in it. BITB ,X / BNE $9294 records the weight in $224E instead, and
;   the serial-poll service applies it AFTER the poll. If the weight is not
;   in the byte but is sitting in the queue $224B, $9270 COMA / ANDA >$224b
;   takes it back out: an event raised and released while a request was
;   outstanding never reaches the wire at all.
; ---------------------------------------------------------------------------
remote_srq_release
                pshs    a
                ldb     >rmt_status
                bitb    #RMT_SP_RSV
                bne     remote_srq_release_defer

                coma                            ; A = the weight, inverted
                anda    >rmt_status
                sta     >rmt_status
                sta     >rmt_spstat
                puls    a
                rts

remote_srq_release_defer
                bitb    ,s                      ; in the byte being asked for?
                beq     remote_srq_release_queued
                lda     >rmt_srq_release        ; then after the poll, not now
                ora     ,s
                sta     >rmt_srq_release
                puls    a
                rts

remote_srq_release_queued
                ldb     >rmt_srq_pending        ; queued but never sent: take
                bitb    ,s                      ; it straight back out
                beq     remote_srq_release_out
                lda     ,s
                coma
                anda    >rmt_srq_pending
                sta     >rmt_srq_pending
remote_srq_release_out
                puls    a
                rts

; ---------------------------------------------------------------------------
; remote_deliver - hand a bus request to the installed screen handler
;
;   entry: B = RMT_RQ + the stock's request code
;   uses:  A, B, X, Y, U - X to fetch the handler, the rest whatever the
;          screen's handler uses
;
; The stock's call_installed_handler_220f, without the message table: the
; code goes to whichever screen is up, and a screen that has no arm for it
; falls to key_refuse - which records the error, beeps, and (while remote)
; reports over the bus, the same three things the stock's reject arms do.
; ---------------------------------------------------------------------------
remote_deliver
                lbsr    remote_prompt_message   ; the register prompt sees it
                ldx     >screen_handler         ; first, as $8D6B does
                beq     remote_deliver_none
                jmp     ,x
remote_deliver_none
                rts

; ---------------------------------------------------------------------------
; remote_incr_ampl_addr - the pending channel's amplitude step
;
;   exit:  X = its three bytes
;   uses:  A, B, X
;
; rmt_pend_chan is the channel every arm here works on, and remote_record
; masks it the same way.
; ---------------------------------------------------------------------------
remote_incr_ampl_addr
                ldb     >rmt_pend_chan
                andb    #$03
                lda     #3
                mul
                ldx     #incr_ampl_ch
                leax    d,x
                rts

; ---------------------------------------------------------------------------
; remote_minus_allowed - may this value carry a minus?
;
;   exit:  carry CLEAR if the pending field is a dc channel's AMPTD
;   uses:  A, B, X
; ---------------------------------------------------------------------------
remote_minus_allowed
                lda     >rmt_pend_kind
                cmpa    #RK_AMPL
                bne     remote_minus_no
                ldb     >rmt_pend_chan
                andb    #$03
                lda     #CHAN_RECORD
                mul
                ldx     #channel_records
                leax    d,x
                lda     CHAN_WAVE,x
                cmpa    #LBL_DC                 ; $4F7B: the waveform word 4
                bne     remote_minus_no
                andcc   #~CC_CARRY
                rts
remote_minus_no
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; remote_prompt_message - a message reaches a waiting register prompt
;
;   uses:  nothing - every register is kept
;
; A bare SV or RC leaves save_recall_prompt ($F331) armed, and while bit 3 of
; $2202 is set ui_message_dispatch ($8D60) hands EVERY message to
; register_entry_key_handler ($F1D9) before the screen's own dispatch
; ($8D6B-$8D7A). Anything but entry-complete ($23) reaches lf2ef ($F2EF):
; while remote, report_error_and_pulse_status_bit ($9DD3) with $0F -
; 'Un-executable command', recorded and sent as an SRQ - then bit 3 is
; cleared ($F31E), and the message goes on to the screen as usual. Being
; addressed to talk is such a message (event 13, $8E74). Driven: 'RC;' then a
; talk read leaves the instrument's $23DE = 15 and its SRQ lamp lit; this
; left both untouched (seeds 6, 13).
; ---------------------------------------------------------------------------
remote_prompt_message
                pshs    a,b,x
                lda     >rmt_pend_kind
                cmpa    #RK_SAVE
                beq     remote_prompt_refuse
                cmpa    #RK_RECALL
                bne     remote_prompt_done
remote_prompt_refuse
                clr     >rmt_pend_kind          ; $F31E: the prompt is let go
                ldb     #ERR_KEY_UNUSABLE       ; $F300 LDB #$0F
                lbsr    error_record            ; stored, and while remote the
                                                ; $9DD3 report and SRQ
remote_prompt_done
                puls    a,b,x
                rts

; ---------------------------------------------------------------------------
; remote_queue - stage a response for the talker
;
;   entry: X = the text, B = its length, 1 to 70; 0 queues nothing
;   uses:  A, B, X, Y
;
; The text is copied into rmt_out with CR LF appended - the stock appends
; them in queue_gpib_output for its shared buffer, and every response this
; firmware queues is its own, so the append is unconditional here. The pump
; sends EOI on the LF.
;
; A MESSAGE ALREADY GOING OUT IS FINISHED FIRST, and that is the stock's own
; shape rather than a courtesy. queue_gpib_output ($9FFE) copies nothing: it
; writes the caller's pointer to $2385 and its length to $2387 and sets bit 1
; of the event_flags high byte, and that is all. The LIVE descriptor the
; talker reads - the count $2265, the pointer $2266, the end flag $2268 - is
; loaded only by gpib_set_output_buffer ($9729), whose one caller is
; start_gpib_output ($9BC4), whose one caller is hpib_send_response ($A052),
; which the FOREGROUND reaches at $8E79 and only after gpib_send_next_byte
; ($96DA) has asked for a refill at $96E7 - the arm that runs when $2269 is
; $80, the state $9711 writes when the last byte of a message went out. So on
; the instrument a reply queued while the talker is mid-message cannot reach
; the talker until that message has ended.
;
; DRIVEN ON THE STOCK 2026-09-13, the Digital Sequence screen with
; 'SEQP 500;' 'SEQE 10;' 'SEQP?;' 'SEQE?;' and one message read between the
; two queries, so the second query arrives with the idle default one byte
; into the wire. The stock sent
;   '00001\r\n? No Data ?\r\n00250\r\n? No Data ?\r\n', EOI at 6, 19, 26, 39
; - the default finished whole, EOI on its own LF, and 00250 followed it as
; its own message. This firmware sent '? No Data00250' as ONE message with
; EOI at the end of it, because remote_queue overwrote rmt_out and reset
; rmt_tx_at under the message it was already sending: a controller reading
; one message got a value glued to the tail of the previous one.
;
; So the descriptor is installed here only when the talker is idle. When it
; is not, the reply waits in rmt_out and remote_byte_out installs it at the
; message boundary, which is where the stock's foreground installs it.
;
; ONE REPLY WAITS, NOT A QUEUE, which is the stock again: $2385/$2387 is a
; single descriptor and every reply is built in the one buffer $2285, so a
; second reply queued before the boundary replaces the first. The one place
; this cannot follow the instrument is a reply queued while ANOTHER REPLY -
; not the idle default - is going out: the stock overwrites $2285 under its
; own talker, sends the corrupted tail and then sends the new reply from the
; descriptor, and with a single buffer here the new reply overwrites the tail
; the same way but is not sent again afterwards. It takes a controller that
; stops reading part-way through a reply and then sends another query to see
; the difference, and the corruption is the stock's, not a behaviour to
; reproduce deliberately.
; ---------------------------------------------------------------------------
remote_queue
                tstb
                beq     remote_queue_none       ; nothing to say is not a reply
                cmpb    #RMT_OUT_MAX            ; 250: a full sequence report,
                bls     remote_queue_fits       ; which is the longest reply
                ldb     #RMT_OUT_MAX            ; the instrument makes. Never
                                                ; off the buffer's end
remote_queue_fits
                pshs    b
                ldy     #rmt_out
remote_queue_copy
                lda     ,x+
                sta     ,y+
                decb
                bne     remote_queue_copy
                lda     #$0D
                sta     ,y+
                lda     #$0A
                sta     ,y
                puls    b
                addb    #2                      ; the message, its CR LF in
                lda     >rmt_tx_len             ; MID-MESSAGE: the reply waits
                bne     remote_queue_none       ; in rmt_out, whose first byte
                stb     >rmt_tx_len             ; is now non-zero, and
                clr     >rmt_tx_at              ; remote_byte_out takes it at
                ldx     #rmt_out                ; the boundary
                stx     >rmt_tx_ptr
remote_queue_none
                rts

; ---------------------------------------------------------------------------
; remote_byte_out - the talker pump: one byte per byte-out event
;
;   uses:  A, B, X
;
; gpib_send_next_byte ($96DA)'s shape: nothing queued when the controller
; asks answers '? No Data ?'; the final byte goes out behind the $0405<=$06
; EOI command.
;
; THE REFILL IS DONE HERE AND NOT POSTED TO THE FOREGROUND, and the reason is
; the chip, not convenience. On the instrument $96DA opens LDA >$2269 / BMI
; $96E7, and $2269 is $80 exactly once - the byte-out event after the last
; byte went out, because $9711 STB >$2269 wrote it there with the count at
; zero. That arm sets $2269 = 1, calls post_event_0d ($9C88) - which stores
; $000D in $2389 and sets bit 0 of $2281, so hpib_send_response refills from
; the FOREGROUND at $A765 - and returns without writing $0400. So one byte-out
; event per message carries no byte on the instrument, and that is the whole
; of the stock's own message boundary.
;
; PORTING THAT SHAPE INTO THIS ROUTINE STALLS THE TALKER, tried and measured
; 2026-09-13: byte-out is consumed by the ISR1 read at the head of remote_poll
; and is raised again only by a write of $0400, so an event that returns
; without writing ends the stream - the reply went out and the eleven bytes
; stopped dead. The stock survives it because the refill happens in a
; DIFFERENT routine, one the foreground reaches, and that routine writes the
; first byte itself; there is no foreground refill hook in this firmware and
; adding one is boot.s's business, not this file's. So the buffer is refilled
; on the same event that finds it empty, which keeps every ask answered.
;
; WHAT THE BOUNDARY COSTS EACH FIRMWARE, stamping every write of $0400 with
; the emulator's step count while addressed to talk with nothing queued: the
; stock's bytes are 226 steps apart inside a message and 462 across the
; '? No Data ?' boundary - the one extra foreground pass the $0D round trip
; buys - and this firmware's are 123 and 190.
;
; THE 226-AGAINST-123 IS NOT THE BOUNDARY AND IS NOT THIS ROUTINE. Counted
; over one 12,000-step window: the stock read $0406 fifty times, read $0401
; fifty times and wrote $0400 fifty times; this firmware 93/93/93. One byte
; per poll on both, no poll skipped by either. gpib_chip_init writes LDD
; #$AB0F / STD >$0401 once at power-up ($9012) - the same pair remote_init
; writes - and nothing enables or disables BO around an output buffer, so
; there is no interrupt gate in the stock's byte-out path left to port. What
; differs is the length of one foreground pass, ~226 steps against ~123, and
; that is boot.s's loop.
; ---------------------------------------------------------------------------
remote_byte_out
                ldb     >rmt_tx_len
                bne     remote_byte_go
                lda     >rmt_out                ; IDLE. A reply that waited for
                beq     remote_byte_idle        ; the last message goes now -
                ldx     #rmt_out                ; see remote_queue - and its
remote_byte_scan                                ; length is where its LF is,
                lda     ,x+                     ; because every message this
                cmpa    #$0A                    ; firmware queues ends CR LF and
                beq     remote_byte_found       ; there is no scratch byte free
                cmpx    #rmt_out+RMT_OUT_MAX+2  ; to hold the length the stock
                blo     remote_byte_scan        ; keeps at $2387. The bound is
                clr     >rmt_out                ; the buffer: no LF inside it
                bra     remote_byte_idle        ; means no message is waiting
remote_byte_found
                tfr     x,d                     ; X is one past the LF, so
                subd    #rmt_out                ; D is the whole message and
                stb     >rmt_tx_len             ; 252 is the most it can be
                ldx     #rmt_out
                bra     remote_byte_install
remote_byte_idle
                ldx     #rmt_no_data            ; the stock's own default, from
                ldb     #RMT_NO_DATA_LEN        ; ROM $EAE4 - and it goes out
                stb     >rmt_tx_len             ; EVERY time the controller
remote_byte_install                             ; reads with nothing queued:
                stx     >rmt_tx_ptr             ; emulator/tests/test_remote.py
                clr     >rmt_tx_at              ; executes the stock doing
                                                ; exactly that. A chip only
                                                ; raises byte-out when the
                                                ; listener took the previous
                                                ; byte, so answering each ask
                                                ; is what keeps a controller's
                                                ; second read from hanging.
; THE DEFAULT IS SENT FROM ROM and is not copied into rmt_out, so a reply
; queued while it is going out has the whole buffer to wait in. The stock's
; default is the ROM string $EAE4 as well, handed to queue_gpib_output ($9FFE)
; by hpib_send_response ($A052) at $A06B, and that is exactly why a reply
; being built at $2285 cannot corrupt the default the way it can corrupt
; another reply.
remote_byte_go
                lda     >rmt_tx_at
                inca
                cmpa    >rmt_tx_len
                blo     remote_byte_mid
                lda     #RMT_AUX_EOI            ; the LAST byte carries EOI
                sta     >rmt_aux
remote_byte_mid
                ldx     >rmt_tx_ptr
                ldb     >rmt_tx_at
                abx
                lda     ,x
                sta     >rmt_data
                inc     >rmt_tx_at
                lda     >rmt_tx_at
                cmpa    >rmt_tx_len
                blo     remote_byte_done
                clr     >rmt_tx_len             ; drained; the next ask gets
                clr     >rmt_tx_at              ; whatever is waiting, or the
                ldx     >rmt_tx_ptr             ; default again. A reply that
                cmpx    #rmt_out                ; has gone out is spent, and its
                bne     remote_byte_done        ; first byte is the mark
                clr     >rmt_out                ; remote_byte_out reads, so it
remote_byte_done                                ; is cleared here and nowhere
                rts                             ; else in the pump

; The instrument's idle answer, and the message boundary is part of it: the
; stock's $EAE4 is followed at $EAEF/$EAF0 by $0D $0A and hpib_send_response
; ($A052) passes length 13, so the default is a whole message with EOI on its
; LF like any other. Held here with its terminator for the same reason.
rmt_no_data     fcc     "? No Data ?"
                fcb     $0D,$0A
RMT_NO_DATA_LEN equ     13

; ---------------------------------------------------------------------------
; remote_byte_in - a data byte arrived; discard while local, else parse
;
;   uses:  A, B, X, Y, U
; ---------------------------------------------------------------------------
remote_byte_in
                lda     >rmt_flags
                bita    #RF_REMOTE
                bne     remote_byte_take
                lda     >rmt_data               ; read and drop, releasing
                rts                             ; the handshake
remote_byte_take
                lda     >rmt_adstat             ; END travels with the byte:
                anda    #$20                    ; sample it BEFORE the data
                sta     >rmt_tmp+2              ; read releases the handshake,
                lda     >rmt_data               ; as $9318/$9321 do
                anda    #$7F
                tst     >rmt_stream
                bne     remote_stream_char
                lbra    remote_parse_char

; ---------------------------------------------------------------------------
; remote_stream_char - a byte of sequence data, after WSQ
;
;   entry: A = the character; rmt_tmp+2 = END, non-zero if it came with EOI
;   uses:  A, B, X, Y, U
;
; The stock's byte-stream handlers (gpib_sequence_char_in $7870 on page 1,
; gpib_sequence_data_char $642E on page 2) take over the data path after the
; sequence-entry request: a space is a no-op, a valid digit is written into
; the sequence at the cursor and echoed if it is on screen, anything else
; ends the transfer. Both are ported whole - page1_bus_stream and
; page2_bus_stream - and this routine is the classifier in front of them:
; which of the two owns the stream, and what nibble the character stands for.
;
; A CHARACTER THE HANDLER REFUSES ENDS THE TRANSFER AND IS THEN PARSED. That
; is not a choice: poll_pending_message ($9F9D) returns the handler's byte,
; gpib_deliver_rx_byte ($9A9B) turns a zero into Z clear, and $932C's `bne
; l9334` sets $224C and falls into the parser WITH THE SAME BYTE STILL IN A.
; So a refused character is neither swallowed nor re-offered to the stream.
;
; THE HEX LETTERS ARE THE INSTRUMENT'S. 'A' to 'F' are steps $0A to $0F of the
; playlist and digits $0A to $0F of a hexadecimal pattern, and in DTMF mode
; dtmf_star_hash_to_ef ($5B2B) folds '*' and '#' onto 'E' and 'F' BEFORE the
; range test at $78B9 - so those two arrive as nibbles $0E and $0F. This used
; to stop at 'D' on the DTMF side, so 'WSQ 12EF;' loaded four nibbles on the
; instrument and two here, with the 'E' re-parsed as the head of a mnemonic.
; ---------------------------------------------------------------------------
remote_stream_char
                cmpa    #$20                    ; space: nothing, keep going
                beq     remote_stream_end_check
                cmpa    #$0A
                beq     remote_stream_stop
                cmpa    #$0D
                beq     remote_stream_stop
                cmpa    #$3B                    ; ';'
                beq     remote_stream_stop
                cmpa    #$2C                    ; ','
                beq     remote_stream_stop
                pshs    a
                ldb     >rmt_seq_owner
                cmpb    #$02                    ; 2: the digital editor
                beq     remote_stream_page2
                ; PAGE 1'S PLAYLIST, whichever of its screens took the stream.
                ; The stock has ONE handler for the whole page-1 mode, so the
                ; tone sequence, the DTMF sequence and the Manual Dial screen
                ; are all served by gpib_sequence_char_in ($7870); owner 1 is
                ; the sequence records here and owner 3 the dial screen, and
                ; page1_bus_stream is what tells them apart.
                lda     ,s
                tst     >tone_dtmf_mode         ; $5B2B: '*' and '#' are the
                beq     remote_stream_page1_go  ; two DTMF symbols, and only
                cmpa    #$2A                    ; in DTMF mode
                bne     remote_stream_hash
                lda     #'E'                    ; $5B2B: '*' -> 'E'
                bra     remote_stream_page1_go
remote_stream_hash
                cmpa    #$23
                bne     remote_stream_page1_go
                lda     #'F'                    ; $5B4D: '#' -> 'F'
remote_stream_page1_go
                lbsr    remote_stream_value     ; $78A6-$78CC: B = 0 to 15
                bcs     remote_stream_other
                stb     >rmt_mode_code
                ldx     #PAGE1_BUS_STREAM
                lbsr    remote_page1_check
                bcs     remote_stream_other
                puls    a                       ; TAKEN: one pull for the one
                bra     remote_stream_done      ; push, and the stream stays
                                                ; open for the next character
remote_stream_page2
                ; THE DIGITAL EDITOR TAKES THE CHARACTER ITSELF, through the
                ; page 2 writer. It used to be delivered as a DIGIT KEY, and
                ; that screen's key handler refuses a digit unless the softkey
                ; edit session is open - which the stock's own $2C arm does NOT
                ; open ($6DDE leaves $3CCA alone). So every WSQ character was
                ; answered with ERR_KEY_UNUSABLE and nothing reached the
                ; pattern. page2_bus_stream writes it where the stock's
                ; gpib_sequence_data_char ($642E) writes it: at the stream's
                ; own cursor, through the editor's own validator.
                lda     ,s
                lbsr    remote_stream_value     ; B = 0 to 15
                lbcs    remote_stream_other
                stb     >rmt_mode_code
                ldx     #PAGE2_BUS_STREAM
                lbsr    remote_page2_check
                bcs     remote_stream_other     ; THE BASE REFUSED IT. That
                                                ; arm answered carry clear
                                                ; whatever happened, because
                                                ; page2_bus_stream cleared
                                                ; rmt_check_result on every
                                                ; path, so this branch could
                                                ; not be taken and the stream
                                                ; ran on past a character the
                                                ; instrument would have
                                                ; stopped at
                puls    a                       ; TAKEN: one pull for the one
                bra     remote_stream_done      ; push, and the stream stays
                                                ; open for the next character
                                                ;
                                                ; THIS BRANCH WAS MISSING and
                                                ; the accepted path fell
                                                ; through into the pull below
                                                ; - two pulls for one push. It
                                                ; unwound the return address,
                                                ; and any streamed digit after
                                                ; WSQ on the digital screen
                                                ; left the CPU spinning at
                                                ; $2140, in RAM, with the
                                                ; panel dead for good: RF_REMOTE
                                                ; still 01 after 2.4 million
                                                ; cycles. `WSQ 20;` on the DTMF
                                                ; screen and `WSQ;` alone were
                                                ; both fine, which is why it
                                                ; survived - only the accepted
                                                ; page 2 character reaches it.
remote_stream_end_check
                tst     >rmt_tmp+2              ; END: the block is complete
                beq     remote_stream_done
remote_stream_stop
                clr     >rmt_stream
remote_stream_done
                rts
; remote_stream_value - a streamed character as a digit value
;   entry: A = the character
;   exit:  carry CLEAR and B = 0 to 15; carry SET if it is not a hex digit
;   uses:  A, B, X - X through the page 2 call its caller makes, which the
;          gate counts against this routine because asmscan reads the two as
;          one body
;
; The stock's is_valid_digit_char ($6389) and parse_hex_digit_pair ($CC53) on
; page 2, and the $78A6-$78CC range chain on page 1. The letters are taken
; here too: on page 1 'A' to 'F' are steps $0A to $0F of the playlist and the
; instrument stores them without a second thought; on page 2 the digital
; editor's hex base accepts them and the BASE is what decides -
; edit_digit_valid refuses a value the base cannot hold, which is where that
; refusal belongs.
remote_stream_value
                cmpa    #'0'
                blo     remote_stream_value_no
                cmpa    #'9'
                bhi     remote_stream_value_letter
                suba    #'0'
                tfr     a,b
                andcc   #~CC_CARRY
                rts
remote_stream_value_letter
                anda    #$DF                    ; 'a' to 'f' as well
                cmpa    #'A'
                blo     remote_stream_value_no
                cmpa    #'F'
                bhi     remote_stream_value_no
                suba    #'A'-10
                tfr     a,b
                andcc   #~CC_CARRY
                rts
remote_stream_value_no
                orcc    #CC_CARRY
                rts

remote_stream_other
                ; A CHARACTER THE STREAM DOES NOT TAKE ENDS IT AND IS PARSED:
                ; the stock's handler returns 0, gpib_parse_input_byte
                ; re-enables the parser and the byte falls through to it
                ; (l9334). A first draft ate the byte, so 'WSQ123FRA 1000 HZ'
                ; lost its F.
                ;
                ; A DIGIT THE BASE REFUSES COMES HERE TOO, and for the same
                ; reason: $6465 and $78CC both return zero, and $9F9D's caller
                ; cannot tell one zero from another. There is no second exit
                ; for it - the refusal is silent and the byte is parsed,
                ; exactly as an unknown character is.
                ;
                ; A SEPARATE ARM USED TO STAND HERE for the DTMF screen: it
                ; mapped '0'-'9' and 'A'-'D' to that screen's keypad indices
                ; and posted each as RMT_RQ + $60 + index, which dialled it.
                ; The instrument does not dial a streamed character - $7870
                ; writes it into the playlist - so the mapping tables and the
                ; arm they fed are gone, and page1_bus_stream has the whole
                ; page-1 stream. It stopped at 'D' as well, which is fault 4:
                ; 'E' and 'F' are the '*' and '#' tones and the instrument
                ; takes both.
                puls    a
                clr     >rmt_stream
                lbra    remote_parse_char

; remote_cmd_wsq - WSQ: sequence data follows, byte by byte
;   uses:  A, B, X, Y, U
;
; THE SCREEN OWNS THE STREAM, as the stock's screens do by installing their
; handler: only a screen with a $2C arm sets rmt_stream (the DTMF and digital
; screens). A first draft set it here first, so a WSQ on the wrong screen
; beeped, raised SRQ, and then typed the data into whatever field was up.
remote_cmd_wsq
                lda     #$2C
                lbra    remote_to_screen

; ===========================================================================
; The parser. Character classes first, then the record walk. The record
; machine mirrors the stock's ($939E-$9439): type 0 descends, type 1 fires
; at once with A = the record argument, type 2 parks and fires when its one
; digit arrives with B = that digit.
; ===========================================================================

; ---------------------------------------------------------------------------
; remote_parse_char - one incoming character
;
;   entry: A = the character, bit 7 already stripped
;   uses:  A, B, X, Y, U
; ---------------------------------------------------------------------------
remote_parse_char
                cmpa    #$0A                    ; the five terminators the
                lbeq    remote_terminator       ; stock lists at $977B:
                cmpa    #$0D                    ; LF CR space comma semicolon
                lbeq    remote_terminator
                cmpa    #$20
                lbeq    remote_terminator
                cmpa    #$2C                    ; ','
                lbeq    remote_terminator
                cmpa    #$3B                    ; ';'
                lbeq    remote_terminator

                cmpa    #'0'                    ; digits, sign and point go
                blo     remote_parse_signs      ; to the number scanner
                cmpa    #'9'
                lbls    remote_parse_digit
                bra     remote_parse_letterish
remote_parse_signs
                cmpa    #$2B                    ; '+'
                lbeq    remote_parse_plus
                cmpa    #$2D                    ; '-'
                lbeq    remote_parse_minus
                cmpa    #$2E                    ; '.'
                lbeq    remote_parse_point
remote_parse_letterish
                cmpa    #'a'                    ; lower case folds up, as the
                blo     remote_parse_upper      ; stock's ANDA #$5F does
                cmpa    #'z'
                bhi     remote_parse_upper
                suba    #$20
remote_parse_upper
                cmpa    #'E'                    ; E inside a number is the
                bne     remote_parse_walk       ; exponent, not a mnemonic
                ldb     >rmt_flags
                bitb    #RF_NUMBER
                beq     remote_parse_walk
                lda     #$01
                sta     >rmt_in_exp
                rts

; --- the record walk -------------------------------------------------------
remote_parse_walk
                pshs    a
                lda     >rmt_char_state
                bne     remote_walk_list

                ; the first character of a command: a mnemonic starting
                ; letter indexes the A-Z table; the four non-letter commands
                ; share one list
                lda     >rmt_flags              ; a number left open by the
                bita    #RF_NUMBER              ; previous characters closes
                beq     remote_walk_first       ; now - the letters end it, as
                lbsr    remote_value_close      ; hpib_end_command does before
remote_walk_first                               ; the mnemonic is walked
                lda     ,s
                cmpa    #'A'
                blo     remote_walk_symbols
                cmpa    #'Z'
                bhi     remote_walk_symbols
                suba    #'A'
                asla
                ldx     #remote_dispatch_az
                ldx     a,x
                bra     remote_walk_enter
remote_walk_symbols
                ldx     #remote_list_symbols
remote_walk_enter
                tst     ,x
                beq     remote_walk_error       ; an empty list: C J X Y Z
                stx     >rmt_list
                lda     #$01
                sta     >rmt_char_state
                cmpx    #remote_list_symbols    ; > < % ? ARE their first
                beq     remote_walk_list        ; character: walk at once
                leas    1,s                     ; THE FIRST LETTER ONLY CHOOSES
                rts                             ; THE LIST. Its records are the
                                                ; SECOND letters ($93AA-$93D6
                                                ; stores the list and returns),
                                                ; and walking them with the
                                                ; first letter matched nothing
                                                ; - every command was a syntax
                                                ; error until the bus gate
                                                ; said so
remote_walk_list
                ldx     >rmt_list
remote_walk_next
                lda     ,x
                beq     remote_walk_error       ; end of list, no match
                cmpa    ,s
                beq     remote_walk_hit
                ldb     1,x                     ; step over the record: 4
                beq     remote_walk_skip4       ; bytes for type 0, 5 for
                leax    5,x                     ; the rest
                bra     remote_walk_next
remote_walk_skip4
                leax    4,x
                bra     remote_walk_next
remote_walk_hit
                ldb     1,x
                beq     remote_walk_descend
                ldy     2,x                     ; the handler
                lda     4,x                     ; its argument
                cmpb    #$02
                beq     remote_walk_defer
                leas    1,s                     ; type 1: fire now, and the
                clr     >rmt_char_state         ; command is complete
                cmpy    #remote_unit_code       ; a UNIT takes the closed
                beq     remote_walk_fire        ; value itself; any other
                pshs    a,y                     ; command first commits a value
                lbsr    remote_flush_default    ; still waiting, in its default
                puls    a,y                     ; unit - the stock's pending-
                                                ; parameter service does the
                                                ; same before the next request
remote_walk_fire
                jmp     ,y
remote_walk_defer
                sty     >rmt_defer              ; type 2: park until the one
                sta     >rmt_defer_arg          ; digit arrives
                leas    1,s
                clr     >rmt_char_state
                rts
remote_walk_descend
                ldy     2,x                     ; type 0: into the sub-list
                sty     >rmt_list
                leas    1,s
                rts
remote_walk_error
                leas    1,s
                clr     >rmt_char_state
                clr     >rmt_defer
                clr     >rmt_defer+1

                ; AND THE NUMBER IN FRONT OF THE BAD TOKEN GOES WITH IT. The
                ; stock's parser abort at $9439 clears its walk state ($2250,
                ; $2253) and calls flag_gpib_error_30 ($9A92), which sets bit 5
                ; of $2281; the foreground poll at $A962 tests that bit, clears
                ; it, calls clear_pending_param_flag ($A472) - whose whole body
                ; is CLR $238F, the "a value is waiting in the entry buffer"
                ; flag pending_setting_service ($A73E) tests at $A7EF, $A87F
                ; and $A905 - and only then reports error $30. So a value that
                ; was already closed is thrown away, unreported and uncommitted.
                ;
                ; Here remote_walk_first closes an open number before walking
                ; the mnemonic, so a bad token arrives with RF_VALUE standing
                ; and the terminator behind it committed the number in the
                ; field's default unit. Driven on the stock 2026-09-13, channel
                ; B's hop slot: 'FRH 1 MZ;' - MZ is no mnemonic of this
                ; instrument - answers $30 and leaves the slot at zero, where
                ; this stored 1.0 Hz and reported nothing.
                clr     >rmt_in_exp
                clr     >rmt_frac_on
                clr     >rmt_frac
                clr     >rmt_exp
                clr     >rmt_exp_neg
                lda     >rmt_flags
                anda    #$03                    ; ~(RF_NUMBER|RF_VALUE|RF_MINUS|RF_OVER|RF_CLOSING|RF_HELD)
                sta     >rmt_flags

                ldb     #ERR_RMT_SYNTAX
                lbra    remote_error

; --- the number scanner ----------------------------------------------------
remote_parse_digit
                ldx     >rmt_defer              ; a parked type-2 record takes
                beq     remote_digit_number     ; exactly one digit
                suba    #'0'
                tfr     a,b
                lda     >rmt_defer_arg
                clr     >rmt_defer
                clr     >rmt_defer+1
                jmp     ,x
remote_digit_number
                tst     >rmt_in_exp
                beq     remote_digit_mantissa
                suba    #'0'                    ; an exponent digit
                pshs    a
                lda     >rmt_exp
                ldb     #10
                mul
                addb    ,s+
                stb     >rmt_exp
                cmpb    #24                     ; 10^24 is past any 24-bit
                bls     remote_exp_ok           ; value; the stock refuses
                lda     >rmt_flags              ; |exp| >= 100 at $95E0, and an
                ora     #RF_OVER                ; 8-bit accumulator would wrap
                sta     >rmt_flags              ; 259 to 3 before that
remote_exp_ok
                rts
remote_digit_mantissa
                pshs    a
                lbsr    remote_number_begin     ; a fresh mantissa if this is
                ldx     #rmt_val                ; the first digit; then
                                                ; mantissa = mantissa * 10
                lbsr    unit_times_ten          ; + digit, 24 bits with the
                bcs     remote_digit_over       ; overflow refused loudly
                puls    a
                suba    #'0'
                adda    >rmt_val+2
                sta     >rmt_val+2
                bcc     remote_digit_frac
                inc     >rmt_val+1
                bne     remote_digit_frac
                inc     >rmt_val
                bne     remote_digit_frac       ; a carry out of the top byte
                lda     >rmt_flags              ; is an overflow the x10 did
                ora     #RF_OVER                ; not see: 16777219 wrapped to
                sta     >rmt_flags              ; 3 and programmed 3.0 Hz
remote_digit_frac
                lda     >rmt_flags              ; digits after the point
                bita    #RF_NUMBER              ; count toward the scale
                beq     remote_digit_done
                tst     >rmt_frac_on
                beq     remote_digit_done
                inc     >rmt_frac
remote_digit_done
                rts
remote_digit_over
                puls    a
                lda     >rmt_flags
                ora     #RF_OVER
                sta     >rmt_flags
                rts

remote_parse_plus
                rts                             ; a sign that changes nothing
remote_parse_minus
                lda     >rmt_flags
                bita    #RF_NUMBER
                beq     remote_minus_mantissa
                tst     >rmt_in_exp             ; a minus inside the exponent
                beq     remote_minus_mantissa
                lda     #$01
                sta     >rmt_exp_neg
                rts
remote_minus_mantissa
                lbsr    remote_number_begin
                lda     >rmt_flags
                ora     #RF_MINUS
                sta     >rmt_flags
                rts
remote_parse_point
                lbsr    remote_number_begin
                lda     #$01
                sta     >rmt_frac_on
                rts

; ---------------------------------------------------------------------------
; remote_number_begin - the first character of a number: start from zero
;
;   uses:  A
;
; The mantissa, the fraction count and the exponent are cleared when a number
; BEGINS, not when one ends: 'FRA 100 HZ' followed by 'FRA 1.5 KZ' stored
; 100015 because the second number's digits landed on the first's mantissa.
; The bus gate caught it on the second command it sent.
; ---------------------------------------------------------------------------
remote_number_begin
                lda     >rmt_flags
                bita    #RF_NUMBER
                bne     remote_number_going     ; already inside one
                ora     #RF_NUMBER              ; A NEW NUMBER REPLACES A HELD
                anda    #~RF_HELD&$FF           ; ONE: 'FRA 5;' '6;' 'HZ;'
                sta     >rmt_flags              ; commits 6 on the instrument
                clr     >rmt_val
                clr     >rmt_val+1
                clr     >rmt_val+2
                clr     >rmt_frac
                clr     >rmt_frac_on
                clr     >rmt_exp
                clr     >rmt_exp_neg
                clr     >rmt_in_exp
remote_number_going
                rts

; ---------------------------------------------------------------------------
; remote_terminator - LF, CR, space, comma or semicolon ends a command
;
;   uses:  A, B, X, Y, U
; ---------------------------------------------------------------------------
remote_terminator
                pshs    a                       ; which terminator, kept
                lda     >rmt_char_state         ; A TERMINATOR INSIDE A
                beq     remote_term_walk_ok     ; MNEMONIC is a syntax error:
                clr     >rmt_char_state         ; hpib_end_command ($9443) with
                lbra    remote_walk_error       ; $2250 set and no armed digit
                                                ; goes to l9439, error $30.
                                                ; 'FR;' errors on the stock.
                                                ; remote_walk_error pops the
                                                ; byte pushed above itself; a
                                                ; LEAS here as well popped the
                                                ; return address's high byte -
                                                ; a crash on 'FR;', found by
                                                ; the second review
remote_term_walk_ok
                ldx     >rmt_defer              ; a parked type-2 with no digit
                beq     remote_term_number      ; is the same error: the stock
                clr     >rmt_defer              ; resumes the callback only
                clr     >rmt_defer+1            ; when $2253 has bit 7 AND
                lbra    remote_walk_error       ; bit 0, a digit collected
remote_term_number
                puls    a
                cmpa    #$20                    ; A SPACE ENDS THE NUMBER BUT
                bne     remote_term_hard        ; DOES NOT COMMIT IT. Asked of
                lda     >rmt_flags              ; the stock in the emulator:
                bita    #RF_NUMBER              ; 'FRA 1.5 KZ;' latches 15000,
                beq     remote_term_done        ; so the unit after the space
                lbra    remote_value_close      ; is what commits, and the
                                                ; value waits for it. This
                                                ; firmware committed at the
                                                ; space in the default unit
                                                ; and stored 15.
remote_term_hard
                lda     >rmt_flags              ; CR, LF, ';' or ',': a number
                bita    #RF_NUMBER|RF_VALUE     ; still open, or closed and
                beq     remote_term_disarm      ; not yet committed, goes in
                lbsr    remote_flush_default    ; with the field's default unit
                                                ; - the stock's own answer for
                                                ; 'FRA 250;' is 2500. CALLED,
                                                ; not branched to, so the
                                                ; disarm below runs after it
remote_term_disarm
                lda     >rmt_flags              ; A REFUSED SELECT'S FIELD ENDS
                bita    #RF_CLOSING             ; WITH ITS COMMAND: the
                beq     remote_term_disarm_kinds ; instrument's $238F reads 0
                anda    #~RF_CLOSING&$FF        ; after 'APD 251 VL;' on the
                sta     >rmt_flags              ; Digital Sequence screen
                clr     >rmt_pend_kind
                rts
remote_term_disarm_kinds
                ; AN IDENTITY FIELD DOES NOT OUTLIVE ITS OWN COMMAND, and this
                ; branch exists for rule 2 alone. RK_SERIAL and RK_OPTIONS
                ; write serial_number ($3FFD) and installed_options ($3FFC) -
                ; the per-unit bytes HP's recovery refuses to reissue once they
                ; are wrong. Every other kind is a SCREEN field and stays armed
                ; on purpose: the stock's own pending-parameter cell $238F
                ; survives a terminator, which is how 'FRA 250;' and then
                ; '400 HZ;' both reach channel A. These two have no screen
                ; behind them and no stock behaviour to copy - the stock's
                ; ST_ID ($9D30 -> cmd_store_id $A3C6) takes no argument at all,
                ; it copies three bytes from $221C into $3FFD and clears $3FFC
                ; - so the arming the owner's bus form needs must last exactly
                ; one command and not one character longer.
                ;
                ; MEASURED ON THIS TREE before the fix, both firmwares driven
                ; from a settled battery with $3FFC-$3FFF = 03 00 2B 67:
                ; 'ST_ID 190;' left the rewrite's serial at 190, then
                ; 'BSB 911;' - a command that takes no argument on either
                ; firmware - made the serial 911, and a bare '77;' after that
                ; made it 77. The field stayed armed for the life of the
                ; session, so every later number on the bus was written into
                ; the instrument's identity. The stock answered $2B to all
                ; three and touched nothing.
                lda     >rmt_pend_kind
                cmpa    #RK_SERIAL
                beq     remote_term_serial
                cmpa    #RK_OPTIONS
                bne     remote_term_done
remote_term_close
                clr     >rmt_pend_kind
remote_term_done
                rts
remote_term_serial
                lda     >rmt_stid_prior         ; a bare 'ST_ID;': the field the
                sta     >rmt_pend_kind          ; stock never left is armed
                clr     >rmt_stid_prior         ; again
                rts

; ---------------------------------------------------------------------------
; remote_value_close - finish the mantissa: sign, overflow, exponent
;
;   exit:  carry SET if the value is unusable (reported); rmt_val holds the
;          mantissa and rmt_frac/rmt_exp the pending decimal scale
;   uses:  A, B, X
; ---------------------------------------------------------------------------
remote_value_close
                lda     >rmt_flags
                anda    #~RF_NUMBER&$FF
                sta     >rmt_flags
                clr     >rmt_in_exp
                clr     >rmt_frac_on
                ; A CHANNEL FIELD'S NUMBER MUST FIT THE ENTRY BUFFER.
                ; gpib_number_to_entry_buffer, called at $A7D6, refuses a
                ; number whose leading digit's exponent is outside -6..+5 and
                ; $A7D6 reports $2A and closes the field, so the unit after it
                ; finds none. Driven on the emulator, both firmwares, ch B:
                ; 'FRB 999999.9 HZ;' is taken, and 'FRB 9999999 HZ;',
                ; 'APB 16777215 UV;' and 'APB 100000000 UV;' leave $2F on the
                ; instrument, where this said $29 or $2B.
                ; AND A CHOICE FIELD HAS NO DIGIT COLUMN AT ALL, so its number
                ; is refused here, before any unit: $A7D6 reports $2A and
                ; closes $238F. Driven on the emulator, both firmwares, ch A:
                ; after 'WFA 100 VL;' the instrument records $2F for the unit
                ; and then $2D for 'FM;' and for 'DC;', leaving the waveform
                ; alone; this held WFORM open, answered $2E and $2C, and put
                ; dc on the channel (seed 6 step 128).
                lda     >rmt_pend_kind
                cmpa    #RK_WAVE
                lbeq    remote_value_refused
                cmpa    #RK_DEST
                lbeq    remote_value_refused
                cmpa    #RK_HOPROW              ; AND A HOP ON/OFF ROW IS A
                lbeq    remote_value_refused    ; CHOICE TOO. Measured
                                                ; 2026-09-17 (seeds 1 and 2):
                                                ; 'PHR 375;' and 'FHR 192;'
                                                ; record $2A on the instrument
                                                ; (pending_setting_service+110)
                                                ; and $2B here, and 'AHR 251
                                                ; SC;' $2A then $2F for the
                                                ; unit, where this gave $2E
                lbsr    remote_entry_kind
                bcs     remote_value_close_plain
                lbsr    remote_value_lead       ; carry: past 24 bits, which
                bcs     remote_value_refused    ; is seven digits or more
                tstb
                beq     remote_value_close_plain ; zero has no exponent
                cmpa    #5
                bgt     remote_value_refused
                cmpa    #-6
                blt     remote_value_refused
remote_value_close_plain
                lda     >rmt_flags
                bita    #RF_OVER
                bne     remote_value_bad
                bita    #RF_MINUS               ; A SIGN ONLY WHERE THE FIELD
                beq     remote_value_ok         ; TAKES ONE. The minus goes into
                lbsr    remote_minus_allowed    ; the entry buffer $239A as a
                bcc     remote_value_ok         ; character, and only entry mode
                                                ; 2 - a dc channel's AMPTD, armed
                                                ; by amptd_limit_volt_units
                                                ; ($4F6D) - has '-' in its column
                                                ; of $EF94; everywhere else the
                                                ; key is refused and the value
                                                ; with it. Driven 2026-09-15:
                                                ; 'APA -2 VL;' on a dc ch A reads
                                                ; '- 2.00 V' on the instrument,
                                                ; and this refused it
                ; AND ON A CHANNEL'S OWN FIELDS THE REFUSAL IS $A7D6's: $2A,
                ; with the field let go. Measured 2026-09-17 on ch A in Channel
                ; Configuration: the stock answers 'FRA -5;' with 42 and $238F
                ; cleared, so the 'HZ;' after it finds no field and records 47;
                ; 'APA -5 MV;' is 47 too. This answered $29 with the field
                ; kept, and the unit then recorded $2B. Fields outside
                ; remote_entry_kind were not driven and keep $29.
                lbsr    remote_entry_kind       ; carry clear: FREQ, AMPL or
                lbcc    remote_value_refused    ; PHASE
                lbra    remote_value_bad
remote_value_ok
                lda     #RF_VALUE
                ora     >rmt_flags
                sta     >rmt_flags
                andcc   #~CC_CARRY
                rts
remote_value_refused
                clr     >rmt_pend_kind          ; $A7D6: the field is let go
                lda     >rmt_flags
                anda    #$CB                    ; ~(RF_OVER|RF_MINUS|RF_VALUE)
                sta     >rmt_flags
                clr     >rmt_val
                clr     >rmt_val+1
                clr     >rmt_val+2
                clr     >rmt_frac
                clr     >rmt_exp
                clr     >rmt_exp_neg
                ldb     #ERR_RMT_NOT_NUMBER     ; $2A
                lbsr    remote_error
                orcc    #CC_CARRY
                rts
remote_value_bad
                lda     >rmt_flags
                anda    #$CB                    ; ~(RF_OVER|RF_MINUS|RF_VALUE)
                sta     >rmt_flags
                clr     >rmt_val
                clr     >rmt_val+1
                clr     >rmt_val+2
                clr     >rmt_frac
                clr     >rmt_exp
                clr     >rmt_exp_neg
                ldb     #ERR_RMT_VALUE
                lbsr    remote_error
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; remote_scale - apply the net decimal scale to rmt_val
;
;   entry: B = the unit's decade count (already includes rad's 3)
;   exit:  carry SET if the value cannot be represented (reported)
;   uses:  A, B, X
;
; net = decades - fractional digits + E exponent. Positive nets multiply by
; ten with the 24-bit overflow refused; negative nets divide by ten and
; refuse a remainder, because 1234.56 Hz is not a value this instrument can
; hold in tenths and rounding it silently would program a different
; frequency from the one asked for.
; ---------------------------------------------------------------------------
remote_scale
                pshs    b
                lda     >rmt_exp
                tst     >rmt_exp_neg
                beq     remote_scale_exp
                nega
remote_scale_exp
                adda    ,s                      ; + decades
                suba    >rmt_frac               ; - fraction digits
                leas    1,s
                clr     >rmt_frac
                clr     >rmt_exp
                clr     >rmt_exp_neg
                tsta
                beq     remote_scale_ok
                bmi     remote_scale_down
remote_scale_up
                pshs    a
                ldx     #rmt_val
                lbsr    unit_times_ten
                puls    a
                bcs     remote_scale_bad
                deca
                bne     remote_scale_up
remote_scale_ok
                andcc   #~CC_CARRY
                rts
remote_scale_down
                pshs    a
                lbsr    remote_div_ten
                puls    a
                bcs     remote_scale_bad
                inca
                bne     remote_scale_down
                bra     remote_scale_ok
remote_scale_bad
                ldb     #ERR_RMT_VALUE
                lbsr    remote_error
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; remote_entry_kind - is the pending field one of the channel's three?
;
;   exit:  carry CLEAR for RK_FREQ, RK_AMPL or RK_PHASE; SET for any other
;   uses:  A
;
; The fields whose bus numbers were driven through the stock's entry path
; below. The hop fields and the page screens' fields take the same stock path
; but were not driven, so they keep remote_scale.
; ---------------------------------------------------------------------------
remote_entry_kind
                lda     >rmt_pend_kind
                cmpa    #RK_TONEFREQ            ; and the tone record's FREQ:
                beq     remote_entry_kind_yes   ; 'FRA 99999999;', 'FRA -5;'
                                                ; and 'FRA 0.0000001;' there
                                                ; are $2A with the field let
                                                ; go (driven 2026-09-17)
                cmpa    #RK_FREQ
                beq     remote_entry_kind_yes
                cmpa    #RK_AMPL
                beq     remote_entry_kind_yes
                cmpa    #RK_PHASE
                beq     remote_entry_kind_yes
                orcc    #CC_CARRY
                rts
remote_entry_kind_yes
                andcc   #~CC_CARRY
                rts

; ---------------------------------------------------------------------------
; remote_value_lead - where the number's leading digit stands
;
;   exit:  carry SET when the mantissa overflowed 24 bits; otherwise
;          B = its decimal digits (0 for zero) and A = the leading digit's
;          exponent, digits - 1 - fraction digits + E, signed
;   uses:  A, B, X
; ---------------------------------------------------------------------------
remote_value_lead
                lda     >rmt_flags
                bita    #RF_OVER
                bne     remote_lead_over
                clr     ,-s                     ; 0,s = the digit count
                ldx     #remote_pow10
remote_lead_next
                cmpx    #remote_pow10+REMOTE_POW10_N*3
                bhs     remote_lead_counted
                lda     >rmt_val
                cmpa    ,x
                bhi     remote_lead_ge
                blo     remote_lead_counted
                ldd     >rmt_val+1
                cmpd    1,x
                blo     remote_lead_counted
remote_lead_ge
                inc     ,s
                leax    3,x
                bra     remote_lead_next
remote_lead_counted
                lda     >rmt_exp                ; E, signed
                tst     >rmt_exp_neg
                beq     remote_lead_e
                nega
remote_lead_e
                suba    >rmt_frac               ; less the fraction digits
                ldb     ,s+                     ; B = the digit count
                beq     remote_lead_done
                pshs    b
                adda    ,s+                     ; plus the digits
                deca                            ; less one
remote_lead_done
                andcc   #~CC_CARRY
                rts
remote_lead_over
                orcc    #CC_CARRY
                rts
remote_pow10    fcb     $00,$00,$01             ; 1
                fcb     $00,$00,$0A             ; 10
                fcb     $00,$00,$64             ; 100
                fcb     $00,$03,$E8             ; 1000
                fcb     $00,$27,$10             ; 10000
                fcb     $01,$86,$A0             ; 100000
                fcb     $0F,$42,$40             ; 1000000
                fcb     $98,$96,$80             ; 10000000
REMOTE_POW10_N  equ     8                       ; the eight rows above

; ---------------------------------------------------------------------------
; remote_field_limit - the digits a channel field's unit leaves room for
;
;   entry: B = the unit
;   exit:  A = the limit
;   uses:  A
;
; The count 3,s each arm of d6c93 hands commit_amplitude_units_entry ($6CA9):
; entry_scale_freq ($6C66) 8 for kHz and Hz, amptd_entry_params_volts
; ($6C5B) 9 for the three voltages, and 5 for entry_scale_deg ($6C3D),
; amptd_unit_key_rad ($6C4C) and amptd_unit_key_percent ($6C71).
; ---------------------------------------------------------------------------
remote_field_limit
                lda     #$09
                cmpb    #UNIT_VOLT
                beq     remote_field_limit_done
                cmpb    #UNIT_MILLIVOLT
                beq     remote_field_limit_done
                cmpb    #UNIT_MICROVOLT
                beq     remote_field_limit_done
                lda     #$08
                cmpb    #UNIT_KHZ
                beq     remote_field_limit_done
                cmpb    #UNIT_HZ
                beq     remote_field_limit_done
                lda     #$05
remote_field_limit_done
                rts

; ---------------------------------------------------------------------------
; remote_field_scale - a channel field's number, as its entry takes it
;
;   entry: A = the unit's digit limit, B = the unit's decades
;   exit:  carry SET when the number is dropped - the value spent, nothing
;          reported; carry CLEAR with rmt_val in the field's own units
;   uses:  A, B, X
;
; entry_to_scaled_digits ($CDE1) and ascii8_to_uint24 ($CB10), as
; enter_freq_value ($6BA5) and commit_amplitude_units_entry ($6CA9) use them:
; digits past the field's unit are dropped; an entry with no digits left
; ($CDE1's $FF) or with the limit's count or more is abandoned with nothing
; said ($6BE8 CMPB #$08 / LBCC, $6CC6 CMPB 3,S / LBCC); and a value past 24
; bits saturates to $FFFFFF ($CB70-$CB91), so the setter's own range check
; answers for it. Driven on the emulator, both firmwares, ch B: 'FRB 1234.56
; HZ;' stores 1234.5 Hz, 'APB 1.5 UV;' 1 uV and 'PHB 1.25 DG;' 1.2 deg with
; nothing recorded; 'FRB 9999 KZ;', 'APB 250 VL;', 'PHB 36000 DG;' and 'PHB
; 99999 RD;' change nothing and record nothing; 'APB 99 VL;' is $7A. This
; answered $29 to all of them but the last.
; ---------------------------------------------------------------------------
remote_field_scale
                pshs    a,b                     ; 0,s limit  1,s decades
                lbsr    remote_value_lead       ; A = lead, B = digits
                bcs     remote_field_drop
                tstb
                beq     remote_field_go         ; '0' is one digit, and taken
                adda    1,s                     ; the integer digits it will
                inca                            ; have in the field's units
                ble     remote_field_drop       ; none: $CDE1's $FF
                cmpa    ,s
                bge     remote_field_drop       ; the limit or more
remote_field_go
                lda     >rmt_exp
                tst     >rmt_exp_neg
                beq     remote_field_exp
                nega
remote_field_exp
                adda    1,s                     ; + decades
                suba    >rmt_frac               ; - fraction digits
                clr     >rmt_frac
                clr     >rmt_exp
                clr     >rmt_exp_neg
                tsta
                beq     remote_field_scaled
                bmi     remote_field_down
remote_field_up
                pshs    a
                ldx     #rmt_val
                lbsr    unit_times_ten
                puls    a
                bcs     remote_field_saturate
                deca
                bne     remote_field_up
                bra     remote_field_scaled
remote_field_saturate
                lda     #$FF                    ; $CB70-$CB91
                sta     >rmt_val
                sta     >rmt_val+1
                sta     >rmt_val+2
                bra     remote_field_scaled
remote_field_down
                pshs    a
                lbsr    remote_div_ten          ; the quotient stays; the
                puls    a                       ; remainder is the digit the
                inca                            ; entry drops
                bne     remote_field_down
remote_field_scaled
                leas    2,s
                andcc   #~CC_CARRY
                rts
remote_field_drop
                leas    2,s
                clr     >rmt_frac
                clr     >rmt_exp
                clr     >rmt_exp_neg
                lda     >rmt_flags
                anda    #~RF_VALUE&$FF
                sta     >rmt_flags
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; remote_div_ten - rmt_val = rmt_val / 10, in place, exact only
;
;   exit:  carry SET on a non-zero remainder
;   uses:  A, B, X
;
; Byte-wise long division, most significant byte first: the remainder from
; one byte (0..9) becomes the high half of the next. remainder*256 + byte is
; at most 2559, so the per-byte divide is a short subtract loop and no
; MUL/DIV is needed. Written in place; on a non-zero final remainder the
; caller discards the value, so the partial quotient left in rmt_val does no
; harm.
; ---------------------------------------------------------------------------
remote_div_ten
                clr     >rmt_rem                ; the running remainder, 0..9
                ldx     #rmt_val
                pshs    x                       ; 0,s = the byte pointer
                ldb     #3
remote_div_byte
                pshs    b                       ; 0,s = counter, 1,s/2,s = ptr
                lda     >rmt_rem                ; D = remainder:byte
                ldx     1,s
                ldb     ,x
                ldx     #$0000                  ; X counts the quotient
remote_div_sub
                cmpd    #10
                blo     remote_div_wrote
                subd    #10
                leax    1,x
                bra     remote_div_sub
remote_div_wrote
                stb     >rmt_rem                ; low byte of D = remainder
                tfr     x,d                     ; the quotient, 0..255
                ldx     1,s                     ; the byte pointer
                stb     ,x+
                stx     1,s
                puls    b
                decb
                bne     remote_div_byte
                leas    2,s                     ; drop the pointer
                lda     >rmt_rem
                bne     remote_div_rem
                andcc   #~CC_CARRY
                rts
remote_div_rem
                orcc    #CC_CARRY
                rts

; ===========================================================================
; Committing a value. The parser leaves a mantissa in rmt_val with its decimal
; scale pending; a unit mnemonic (or the terminator, for a bare number) scales
; it into the pending field's own units and hands it to the SAME setter the
; front panel uses - freq_set, ampl_set, phase_set - so a value from the bus
; is validated, stored and programmed exactly as a value from the keys.
; ===========================================================================

; The fields the stock's $238B gate refuses a bare number for, one byte each,
; with the units class and the arm it was read out of. The gate itself is
; select_mode_code_from_238b ($A5C1), described over remote_flush_default
; below. RK_SAVE and RK_RECALL are absent because save_recall_prompt ($F331)
; arms them with class 0 ($F368 LDU #$0000) and a bare register number is the
; only spelling SV and RC have. RK_SERIAL and RK_OPTIONS are absent because
; they never pass through this gate on the instrument at all: ST_ID is
; cmd_st_id_store_serial ($9D30), a type-1 record that calls cmd_store_id
; ($A3C6) and copies $221C straight into serial_number ($3FFD) with no entry
; field anywhere on the path, and ST_OP is the owner's addition spelled as its
; sibling. RK_WAVE, RK_DEST and RK_OUTPUT are absent because a number is not
; what they take. RK_TONE, RK_HOPADDR and RK_TIME were once held inside
; remote_commit_raw by an RTS that threw the number away; they are rows here
; because the number has to outlive its command, as the measurements over
; remote_commit_no_value show.
rmt_needs_unit  fcb     RK_FREQ                 ; class 6, entry_cfg_freq $4EE5
                fcb     RK_AMPL                 ; 3/4/6/7 by unit, $4F19-$4F6D
                fcb     RK_PHASE                ; 3, arm_phase_editor $4FDF
                fcb     RK_HOPFREQ              ; 6, $5024
                fcb     RK_HOPAMPL              ; 4, $503D
                fcb     RK_HOPPHASE             ; 3, $5086
                fcb     RK_SEQPOS               ; 2, $461B tone, $66AA digital
                fcb     RK_SEQEND               ; 2, $4630 tone, $66BF digital
                fcb     RK_DIGBIT               ; 2, the Bit field, as Seq Index
                fcb     RK_TONEAMPL             ; the tone AMPTD field, as RK_AMPL
                fcb     RK_DIGLEVEL             ; the On and Off levels, likewise
                fcb     RK_TONE                 ; HRA's tone number: 'HRA 3;'
                                                ; stores nothing, and 'HZ;'
                                                ; after it selects tone 3
                fcb     RK_HOPADDR              ; the Hop Ram Adrs stop: 'HRA
                                                ; 3;' leaves $24F4 alone with
                                                ; $238F = 01, and 'HZ;' after
                                                ; it commits
                fcb     RK_TIME                 ; STON and STOF: 'STON 5;'
                                                ; stores nothing, and 'MS;'
                                                ; after 'STON 50;' commits
                fcb     RK_TONEFREQ             ; the tone record's FREQ:
                                                ; 'FRA 500;' stores nothing,
                                                ; and 'HZ;' after it commits
RMT_NEEDS_UNIT  equ     15                      ; the fifteen rows above, counted
                                                ; here because the scan needs a
                                                ; length and a label after the
                                                ; last fcb would be a body-less
                                                ; one

; ---------------------------------------------------------------------------
; remote_flush_default - commit a value that has no unit of its own
;
;   uses:  A, B, X, Y, U
;
; Called when a new mnemonic begins or a terminator arrives with a number
; still open. A number with no unit commits in the field's native units -
; hertz, volts, degrees - but ONLY FOR THE FIELDS THAT TAKE ONE.
;
; A BARE NUMBER DOES NOT REACH EVERY FIELD ON THE INSTRUMENT. The bus number
; goes into the panel's own entry buffer and the commit is posted by
; pending_setting_service ($A73E). Its no-unit leg starts at $A7D6: clear bit
; 1 of $2281, refuse an empty entry with error $2B, validate the digits with
; gpib_number_to_entry_buffer ($A47E) - error $2A - and then, at $A80D, call
; select_mode_code_from_238b ($A5C1). THAT CALL IS THE GATE. $A5C1 reads
; $238B, the field's units class, and returns 1 only for 0 (storing $0010
; into $2221) or for 1 (storing $000C); for anything else it clears the
; return slot at $A5E7 and $A830 falls straight through to $A866 - no
; clear_pending_param_flag ($A472), no post_request_code ($8AD0) of $0023,
; which is the code the ENTER key posts. The number is therefore neither
; stored nor refused: the entry stays armed and the glass does not move. The
; unit leg at $A8EC has no such gate - it asks unit_allowed_for_group ($A65A)
; and commits - which is why a unit commits what a bare number does not.
;
; $238B is begin_numeric_entry ($A415)'s second argument, which
; arm_numeric_entry_field ($AC35) passes on from its own arg4. Read out of
; the arms that fill it: FREQ 6 ($4EE5), AMPTD 3/4/6/7 ($4F19, $4F43, $4F51,
; $4F5F, $4F6D), PHASE 3 ($4FDF), hop FREQ 6 ($5024), hop AMPTD 4 ($503D),
; hop PHASE 3 ($5086), the tone screen's Seq Index and Seq End 2 ($461B and
; $4630) and the digital screen's Seq Index 2 ($66AA) - not one of them 0 or
; 1. Against that, save_recall_prompt ($F331) arms SV and RC at $F368 with
; LDU #$0000, so $238B is 0 there and those two DO take a bare number.
;
; DRIVEN ON THE STOCK 2026-09-13. On the Digital Sequence Seq-Index page with
; the end reading 250, 'SEQE 10;' left the glass at 250 and reported nothing
; while 'SEQE 10 ET;' moved it to 10; on the tone sequence page 'SEQP 137;'
; left the Seq Index at 1 while 'SEQP 137 ET;' moved it to 137; 'FRA 400;'
; and 'APA 7;' left their fields alone while 'FRA 900 HZ;' and 'APA 9 VL;'
; committed. This firmware committed all of them, so a controller that sent a
; number without its unit programmed a channel the instrument would not have.
;
; A NUMBER STOPPED HERE IS HELD, NOT DROPPED. The stock leaves the digits in
; its entry buffer with $238F still set, and a unit sent as a later message
; commits them. Driven 2026-09-17 on both firmwares (scratch probes q1probe,
; q1show, q1kinds): on the Channel Configuration record 'FRA 5;' then 'HZ;'
; sets 5 Hz, 'FRA 5;' 'BSB;' 'HZ;' still does (BSB's $18 arms nothing),
; 'FRA 5;' '6;' 'HZ;' sets 6, and 'FRA 5;' 'FRA;' 'HZ;' sets nothing because
; the second FRA opened a fresh entry. So remote_flush_held keeps the value
; under RF_HELD, a new number or an arm empties it, and
; remote_commit_no_value is where a lone unit finds it.
; ---------------------------------------------------------------------------
remote_flush_default
                lda     >rmt_flags
                bita    #RF_NUMBER
                beq     remote_flush_value
                lbsr    remote_value_close
                bcs     remote_flush_done
remote_flush_value
                lda     >rmt_flags
                bita    #RF_VALUE
                beq     remote_flush_done
                lda     >rmt_pend_kind
                beq     remote_flush_none       ; A NUMBER WITH NO FIELD, which
                                                ; $A7EA answers before it looks
                                                ; at the digits: LDB >$238F /
                                                ; CMPB #$00 / LBEQ $A853, and
                                                ; $A853 is $2B. Driven on the
                                                ; stock 2026-09-13, Tone
                                                ; Sequence: 'FRB 922;' is $2B
                                                ; and channel B is untouched,
                                                ; where this firmware wrote
                                                ; 2,000,000 into it
                ldx     #rmt_needs_unit         ; $A5C1's gate: a field whose
                ldb     #RMT_NEEDS_UNIT         ; units class is neither 0 nor
remote_flush_gate                               ; 1 takes no bare number
                cmpa    ,x+
                beq     remote_flush_held
                decb
                bne     remote_flush_gate
                ldb     #UNIT_HZ
                cmpa    #RK_FREQ
                beq     remote_commit_units
                cmpa    #RK_HOPFREQ
                beq     remote_commit_units
                ldb     #UNIT_VOLT
                cmpa    #RK_AMPL
                beq     remote_commit_units
                cmpa    #RK_HOPAMPL
                beq     remote_commit_units
                ldb     #UNIT_DEG
                cmpa    #RK_PHASE
                beq     remote_commit_units
                cmpa    #RK_HOPPHASE
                beq     remote_commit_units
                ; counts, not quantities: a serial number, a sequence
                ; position, a sequence end. They scale by nothing but the
                ; fraction and exponent the number itself carried.
                clrb
                lbsr    remote_scale
                bcs     remote_flush_done
                lbra    remote_commit_raw
remote_flush_none
                lda     >rmt_flags              ; the digits go with the refusal
                anda    #~RF_VALUE&$FF
                sta     >rmt_flags
                ldb     #ERR_RMT_NO_FIELD       ; $2B, 'Number received but not
                lbra    remote_error            ; expected'
remote_flush_held
                lda     >rmt_flags              ; NOTHING STORED AND NOTHING
                anda    #~RF_VALUE&$FF          ; REPORTED: $A830 falls through
                ora     #RF_HELD                ; to $A866 in silence, and the
                sta     >rmt_flags              ; digits stay in the entry
                lda     >rmt_pend_kind          ; buffer for a later unit to
                sta     >rmt_held_kind          ; commit. rmt_pend_kind is left
                                                ; alone for the same reason -
                                                ; $A472 is not called on this
                                                ; leg, so the entry the
                                                ; mnemonic opened is still open
remote_flush_done
                rts

; ---------------------------------------------------------------------------
; remote_commit_units - scale the pending value by a unit and commit it
;
;   entry: B = the unit code (UNIT_*)
;   uses:  A, B, X, Y, U
;
; The stock validates the unit against the field's group first
; (unit_allowed_for_group $A65A: frequency takes kHz/Hz, phase deg/rad, a
; level V/mV/uV/%) and reports $2E for a mismatch; the same check is here,
; because a frequency in volts is a mistake on the controller's side that
; must not become a frequency.
;
; AND BEFORE ANY OF THAT, WHETHER THERE IS A FIELD AT ALL. The stock's unit
; leg is $A8EC: clear bit 3 of $2281, then LDB >$238F / CMPB #$00 / LBEQ
; $A94F, which reports $2F - 'Terminator received but not expected' - and
; never asks unit_allowed_for_group ($A65A) at all. The test is FIRST, ahead
; of the value's own, which is why a lone 'HZ;' on a screen that armed
; nothing answers $2F and not $2B. Driven on the stock 2026-09-13 on the
; Digital Sequence screen: 'FRD 251 UV;', 'ON 1000 VL;', 'PR 10 DG;',
; 'STOF 10 VL;' and 'PR 5639 HZ;' each end in $2F, and the last of them
; committed 56,390 into channel D here before this test existed.
; ---------------------------------------------------------------------------
remote_commit_units
                stb     >rmt_unit
                lda     >rmt_pend_kind          ; $A900: the field first
                lbeq    remote_units_none       ; RK_NONE - nothing armed
                tst     >rmt_field_gone         ; armed, but the tone screen
                lbne    remote_gone_unit        ; refused its cursor away
                lda     >rmt_flags
                bita    #RF_VALUE
                lbeq    remote_commit_no_value
                lda     >rmt_pend_kind
                cmpa    #RK_FREQ
                lbeq    remote_units_freq
                cmpa    #RK_HOPFREQ
                lbeq    remote_units_freq
                cmpa    #RK_AMPL
                lbeq    remote_units_level
                cmpa    #RK_HOPAMPL
                lbeq    remote_units_level
                cmpa    #RK_PHASE
                lbeq    remote_units_phase
                cmpa    #RK_HOPPHASE
                lbeq    remote_units_phase
                cmpa    #RK_TONE
                lbeq    remote_set_tone
                cmpa    #RK_TONEAMPL            ; the level fields the page
                lbeq    remote_units_page_level ; screens own
                cmpa    #RK_TONEFREQ            ; and the tone record's
                lbeq    remote_units_tonefreq   ; frequency
                cmpa    #RK_DIGLEVEL
                lbeq    remote_units_page_level
                cmpa    #RK_HOPADDR             ; the Hop Ram Adrs stop takes
                lbeq    remote_set_hopaddr      ; ANY unit, as the tone number
                                                ; does: enter_hop_addr_value
                                                ; ($6F78) hands
                                                ; entry_to_scaled_digits
                                                ; ($CDE1) a CONSTANT eight
                                                ; where the unit code would go,
                                                ; so the unit that ended the
                                                ; entry is not read at all.
                                                ; Driven on the stock
                                                ; 2026-09-13 on the Hop Ram
                                                ; record: 'HRA 3 HZ;',
                                                ; '5 KZ;', 'HRA 15 DG;' and
                                                ; 'HRA 0 VL;' each commit
                cmpa    #RK_TIME
                lbeq    remote_units_time
                cmpa    #RK_SEQPOS
                lbeq    remote_units_count
                cmpa    #RK_SEQEND
                lbeq    remote_units_count
                cmpa    #RK_DIGBIT
                lbeq    remote_units_count
                lbra    remote_units_bad        ; a unit on a field that has
                                                ; no units
remote_units_freq
                cmpb    #UNIT_KHZ
                beq     remote_units_scale
                cmpb    #UNIT_HZ
                beq     remote_units_scale
                lbra    remote_units_bad
remote_units_level
                ; THE AMPTD FIELD'S UNITS COME FROM THE DESTINATION, not from
                ; the mnemonic: an FM channel's level is a deviation in hertz,
                ; a phi-M channel's in degrees, an AM channel's a depth in
                ; percent, a socket's a voltage. The stock validates the unit
                ; against the field group the destination set ($238B ->
                ; unit_allowed_for_group $A65A) and reports $2E on a mismatch.
                ; A first draft admitted volts on every channel, so 'APA 10
                ; MV' on an FM channel programmed 1000.0 Hz of deviation.
                pshs    b
                lda     >rmt_pend_kind
                cmpa    #RK_HOPAMPL             ; a hop slot's level is a
                beq     remote_units_level_volts ; voltage
                lbsr    remote_record           ; X = the record
                ldb     CHAN_DEST,x
                lbsr    ampl_unit_for_destn     ; A = the destination's unit
                ldb     ,s
                cmpa    #UNIT_HZ
                beq     remote_units_level_hz
                cmpa    #UNIT_DEG
                beq     remote_units_level_deg
                cmpa    #UNIT_PERCENT
                beq     remote_units_level_pct
                cmpa    #UNIT_VOLT
                beq     remote_units_level_volts
                leas    1,s                     ; Off or Pulse: no level to
                lbra    remote_units_bad        ; take
remote_units_level_hz
                leas    1,s
                bra     remote_units_freq
remote_units_level_deg
                leas    1,s
                bra     remote_units_phase
remote_units_level_pct
                leas    1,s
                cmpb    #UNIT_PERCENT
                beq     remote_units_scale
                lbra    remote_units_bad        ; LONG: the count arm below sits
                                                ; between here and the refusal
remote_units_level_volts
                leas    1,s
                cmpb    #UNIT_VOLT
                beq     remote_units_scale
                cmpb    #UNIT_MILLIVOLT
                beq     remote_units_scale
                cmpb    #UNIT_MICROVOLT
                beq     remote_units_scale
                lbra    remote_units_bad
remote_units_phase
                ; THE UNIT IS STORED FIRST, value or no value. set_phase_units_
                ; and_apply ($6E46) writes the units key into record+$19 and
                ; only then commit_channel_phase ($66B2) checks the number, so
                ; 'PHA 7 RD;' leaves ch A reading '0.000 rad' on the instrument
                ; with nothing stored. Channel records only: the hop phase has
                ; no unit cell.
                cmpb    #UNIT_DEG
                beq     remote_units_phase_deg
                cmpb    #UNIT_RAD
                lbne    remote_units_bad
                lda     #CHAN_UNIT_RAD
                bra     remote_units_phase_keep
remote_units_phase_deg
                lda     #CHAN_UNIT_DEG
remote_units_phase_keep
                pshs    b
                ldb     >rmt_pend_kind
                cmpb    #RK_PHASE
                bne     remote_units_phase_go
                ldb     >rmt_pend_chan
                andb    #$03
                ldx     #chan_phase_unit
                abx
                sta     ,x
remote_units_phase_go
                puls    b
                cmpb    #UNIT_DEG
                beq     remote_units_scale
                bra     remote_units_radians

remote_units_scale
                lbsr    remote_entry_kind       ; a channel field: the entry's
                bcs     remote_units_scale_plain ; own digits decide
                lbsr    remote_field_limit      ; A = the unit's limit
                pshs    a
                ldx     #unit_decades
                abx
                ldb     ,x                      ; B = its decades
                puls    a
                lbsr    remote_field_scale
                lbcs    remote_commit_done      ; dropped, and nothing said
                lbra    remote_commit_raw
remote_units_scale_plain
                ldx     #unit_decades           ; the same table unit_apply
                abx                             ; reads for the panel's units
                ldb     ,x
                lbsr    remote_scale            ; mantissa * 10^(decades -
                lbcs    remote_commit_done      ; fraction + exponent)
                lbra    remote_commit_raw

remote_units_radians
                lbsr    remote_entry_kind
                bcs     remote_units_radians_plain
                lda     #$05                    ; amptd_unit_key_rad: 3, 5
                ldb     #RAD_DECADES
                lbsr    remote_field_scale
                lbcs    remote_commit_done
                bra     remote_units_radians_scaled
remote_units_radians_plain
                ldb     #RAD_DECADES            ; to thousandths of a radian,
                lbsr    remote_scale            ; which is what unit_apply's
                lbcs    remote_commit_done      ; radian arm converts from
remote_units_radians_scaled
                lda     >rmt_val                ; PAST 6282 NOTHING IS STORED
                lbne    remote_units_rad_over   ; AND NOTHING SAID ($66F7-$6701
                ldd     >rmt_val+1              ; into l6749)
                cmpd    #PHASE_MAX_MRAD
                lbhi     remote_units_rad_over
                lda     >rmt_pend_kind          ; and the typed milliradians
                cmpa    #RK_PHASE               ; kept beside the degrees, as
                bne     remote_units_rad_twin_done ; record+$17 is
                ldb     >rmt_pend_chan
                andb    #$03
                aslb
                ldx     #chan_phase_rad
                abx
                ldd     >rmt_val+1
                std     ,x
remote_units_rad_twin_done

                ; AND IT DECLARES THE FRACTION, like every other caller of that
                ; arm. unit_apply_radians runs unit_scale_decades, whose first
                ; instruction subtracts entry_frac - the PANEL's count of digits
                ; after the point - so this scaled the value by a thousand here
                ; and again by ten to the (3 - entry_frac) inside. From cold,
                ; with entry_frac at 0, 'PHA 3.14 RD;' was multiplied by a
                ; million, failed the whole-turn test and set nothing at all,
                ; and 'PHA 0.001 RD;' programmed 57.3 degrees instead of 0.06.
                ; The same command answered differently depending on what had
                ; last been typed on the keypad. This is the third site of the
                ; class: hop_program and the HOPP query were the other two.
                lda     >entry_frac
                pshs    a
                lda     #RAD_DECADES
                sta     >entry_frac
                ldx     #rmt_val
                ldb     #UNIT_RAD
                lbsr    unit_apply
                puls    a
                sta     >entry_frac
                lbcs    remote_units_value_bad
                lbra    remote_commit_raw

remote_units_time
                ; GROUP 5, AND THE TABLE IS THE STOCK'S.
                ; unit_allowed_for_group ($A65A) gives a sequence time the set
                ; {9, $0A} - seconds and milliseconds - and
                ; pending_setting_service ($A73E) raises $2E at $A939 for
                ; anything else. Driven on the stock: 'STON 5 HZ;' answers
                ; $2E and stores nothing. The scaling is unit_decades', the
                ; same table the panel's own unit keys go through, so a
                ; millisecond is a hundred counts here as it is there.
                cmpb    #UNIT_SECOND
                beq     remote_units_time_ok
                cmpb    #UNIT_MILLISEC
                beq     remote_units_time_ok
                lda     >rmt_flags
                anda    #~RF_VALUE&$FF
                sta     >rmt_flags
                ldb     #ERR_RMT_TERMINATOR
                lbra    remote_error
remote_units_time_ok
                lda     >rmt_flags              ; a refused select's field
                bita    #RF_CLOSING             ; takes the unit and commits
                lbne    remote_closing_drop     ; nothing (remote_select)
                ; THE DECADES ARE THE COUNTS', not unit_decades'. A sequence
                ; time is a count of ten microseconds, and unit_decades holds
                ; zero for both time units because the screen's own commit
                ; does the hundred separately (tone_entry_scale says so). Two
                ; decades for a millisecond and five for a second land the
                ; value in counts here, which is what apply_time_entry
                ; ($638F) stores.
                cmpb    #UNIT_SECOND
                bne     remote_units_time_ms
                ldb     #5
                bra     remote_units_time_scale
remote_units_time_ms
                ldb     #2
remote_units_time_scale
                lbsr    remote_scale
                lbcs    remote_time_too_long    ; 700 s is seventy million
                lbra    remote_set_time         ; counts: the time's own $32,
                                                ; not the parser's $29

; --- a count: EVERY unit mnemonic closes one --------------------------------
; The 'ET' record is unit code 8 (hp8904a-rewrite/modules/remote_tables.s,
; list rmt_list_e), and 8 is in none of the unit groups: it is not a quantity
; but the ENTER key itself, which is the key an operator closes a Seq Index or
; a Seq End with because those fields have no unit to name.
;
; BUT THE INSTRUMENT TAKES ANY OF THEM, and unscaled. This arm was ET-only and
; answered $2E to the rest, so 'SEQP 5 HZ;' - which is the shape the
; differential harness sends, a value command with a unit after it - moved
; nothing and the two firmwares parted on the Seq Index readout.
;
; Driven on the stock 2026-09-13, Tone Sequence on its sequence record with the
; Seq Index reading 1, one boot per command: 'SEQP 5 <u>;' leaves the readout
; at 5 with $3C02 zero for every one of the twelve mnemonics the record tables
; hold - ET KZ HZ DG RD VL MV UV SC MS PC and '%' - and 'SEQE 100 RD;' and
; 'SEQE 100 UV;' likewise put 100 on the Seq End. Not scaled by the mnemonic
; either: 'SEQP 5 KZ;' is index 5, not 5000. The Digital Sequence screen's own
; Seq Index answers ET, HZ, MS and VL the same way, which is the other screen
; that reaches here. A bare terminator does NOT close one - 'SEQP 5;' leaves
; the readout at 1 - so the unit mnemonic is doing the work, and that is why
; this arm exists at all rather than the number committing on the semicolon.
;
; WHY the instrument takes a unit on a field with no units is not established
; from the ROM here: arm_numeric_entry_field ($AC35) stores the field's units
; class at $23AB, accept_units_key ($B0C1) dispatches on it only over 2 to 7
; ($B1FF) and check_entry_terminator ($B070) answers 1 for class 0, so the
; class the two sequence fields are armed with decides it and this reading has
; not followed entry_field_seq_index ($461B) through $AC35 to that byte. The
; BEHAVIOUR above is measured across the whole mnemonic table; the mechanism
; behind it is not claimed.

; remote_units_count - a sequence position or end, closed by any unit mnemonic
;   entry: B = the unit code
;   uses:  A, B, X, Y, U
remote_units_count
                lda     >rmt_flags              ; a refused select's field
                bita    #RF_CLOSING             ; takes the unit and commits
                lbne    remote_closing_drop     ; nothing (remote_select)
                clrb                            ; a count scales by nothing but
                lbsr    remote_scale            ; the fraction and exponent the
                bcs     remote_units_count_done ; number itself carried
                lbra    remote_commit_raw
remote_units_count_done
                rts                             ; remote_scale has reported it

remote_units_bad
                ; A UNIT THE FIELD HAS NO PLACE FOR IS $2E. The stock's unit
                ; terminator (la8ec) asks unit_allowed_for_group with the
                ; pending parameter $238F standing and, refused, reports $2E at
                ; la939 through $9DD3; $2F is the same unit with no parameter
                ; at all (la94f). Driven on the emulator, seed 15 step 23:
                ; 'PHB 1 UV;' records $2E on the instrument, and $29 here.
                lda     >rmt_flags
                anda    #~RF_VALUE&$FF
                sta     >rmt_flags
                ldb     #ERR_RMT_TERMINATOR
                lbra    remote_error
remote_units_value_bad
                ; the unit was one the field takes and the value would not
                ; convert (unit_apply's carry): the number, not the unit
                lda     >rmt_flags
                anda    #~RF_VALUE&$FF
                sta     >rmt_flags
                ldb     #ERR_RMT_VALUE
                lbra    remote_error
; remote_unit_misfit - does the unit in B belong to the armed field's group?
;   entry: B = the unit code
;   exit:  carry SET when the field's units are fixed and B is not one of
;          them; CLEAR otherwise, including every kind not decided here
;   uses:  A
; The groups are the ones the commit legs below already test: frequency kHz
; and Hz, phase deg and rad, time s and ms, a page screen's level V, mV and
; uV. The channel AMPTD's units follow its destination (remote_units_level)
; and are not decided here.
remote_unit_misfit
                lda     >rmt_pend_kind
                cmpa    #RK_FREQ
                beq     remote_misfit_freq
                cmpa    #RK_HOPFREQ
                beq     remote_misfit_freq
                cmpa    #RK_TONEFREQ
                beq     remote_misfit_freq
                cmpa    #RK_PHASE
                beq     remote_misfit_phase
                cmpa    #RK_HOPPHASE
                beq     remote_misfit_phase
                cmpa    #RK_TIME
                beq     remote_misfit_time
                cmpa    #RK_TONEAMPL
                beq     remote_misfit_level
                cmpa    #RK_DIGLEVEL
                beq     remote_misfit_level
                cmpa    #RK_AMPL                ; A CHANNEL'S LEVEL takes its
                beq     remote_misfit_chan_level ; destination's units, which
                cmpa    #RK_HOPAMPL             ; are not decided here - but
                beq     remote_misfit_chan_level ; none of them is a time
remote_misfit_fits
                andcc   #~CC_CARRY
                rts
remote_misfit_freq
                cmpb    #UNIT_KHZ
                beq     remote_misfit_fits
                cmpb    #UNIT_HZ
                beq     remote_misfit_fits
                bra     remote_misfit_not
remote_misfit_phase
                cmpb    #UNIT_DEG
                beq     remote_misfit_fits
                cmpb    #UNIT_RAD
                beq     remote_misfit_fits
                bra     remote_misfit_not
remote_misfit_time
                cmpb    #UNIT_SECOND
                beq     remote_misfit_fits
                cmpb    #UNIT_MILLISEC
                beq     remote_misfit_fits
                bra     remote_misfit_not
remote_misfit_chan_level
                cmpb    #UNIT_SECOND            ; s and ms fit no destination:
                beq     remote_misfit_not       ; 'ST_ID 999 SC;' after 'DAPL
                cmpb    #UNIT_MILLISEC          ; 5 MV;' is $2E on the
                beq     remote_misfit_not       ; instrument (seed 6)
                bra     remote_misfit_fits
remote_misfit_level
                cmpb    #UNIT_VOLT
                beq     remote_misfit_fits
                cmpb    #UNIT_MILLIVOLT
                beq     remote_misfit_fits
                cmpb    #UNIT_MICROVOLT
                beq     remote_misfit_fits
remote_misfit_not
                orcc    #CC_CARRY
                rts
remote_commit_done
                rts
remote_units_rad_over
                lda     >rmt_flags              ; the number is spent, and
                anda    #~RF_VALUE&$FF          ; the unit already stored
                sta     >rmt_flags
                lbra    remote_refresh

; ---------------------------------------------------------------------------
; remote_closing_drop - a refused select's field would commit: it does not
;
;   uses:  A
;
; The field closes without a word; RF_CLOSING says why (remote_select).
; ---------------------------------------------------------------------------
remote_closing_drop
                lda     >rmt_flags
                anda    #$3B                    ; ~(RF_VALUE|RF_CLOSING|RF_HELD)
                sta     >rmt_flags
                clr     >rmt_pend_kind
                rts

; ---------------------------------------------------------------------------
; remote_units_none - the unit reached no field
; ---------------------------------------------------------------------------
remote_units_none
                ; THE UNIT REACHED NO FIELD. $A94F: report $2F and nothing
                ; else - the number in front of it goes with the refusal,
                ; since there is nowhere left to put it. It sits down here,
                ; past remote_units_bad, so that the short branches its
                ; neighbours make to that label keep their reach.
                lda     >rmt_flags
                anda    #~RF_VALUE&$FF
                sta     >rmt_flags
                ldb     #ERR_RMT_TERM_NONE
                lbra    remote_error

; ---------------------------------------------------------------------------
; remote_commit_raw - rmt_val is in the field's units: store and program it
;
;   uses:  A, B, X, Y, U
; ---------------------------------------------------------------------------
remote_commit_raw
                lda     >rmt_flags
                anda    #~RF_VALUE&$FF
                sta     >rmt_flags
                lda     >rmt_pend_kind
                cmpa    #RK_FREQ
                beq     remote_set_freq
                cmpa    #RK_AMPL
                beq     remote_set_ampl
                cmpa    #RK_PHASE
                lbeq    remote_set_phase
                cmpa    #RK_HOPFREQ
                lbeq    remote_set_hop
                cmpa    #RK_HOPAMPL
                lbeq    remote_set_hop
                cmpa    #RK_HOPPHASE
                lbeq    remote_set_hop
                cmpa    #RK_SERIAL
                lbeq    remote_set_serial
                cmpa    #RK_SEQPOS
                lbeq    remote_set_seqpos
                cmpa    #RK_SEQEND
                lbeq    remote_set_seqend
                cmpa    #RK_DIGBIT
                lbeq    remote_set_digbit
                cmpa    #RK_OPTIONS
                lbeq    remote_set_options
                cmpa    #RK_SAVE
                lbeq    remote_set_save
                cmpa    #RK_RECALL
                lbeq    remote_set_recall
                cmpa    #RK_SREMASK             ; SM n: the SRQ-enable mask
                lbeq    remote_set_sremask
                cmpa    #RK_WAVE                ; A NUMBER FOR A CHOICE FIELD:
                beq     remote_number_refused   ; gpib_number_to_entry_buffer
                cmpa    #RK_DEST                ; finds no digit column, and
                beq     remote_number_refused   ; $A833 closes $238F and says $2A
                ldb     #ERR_RMT_NO_FIELD       ; a number for a field that
                lbra    remote_error            ; takes none, or no field
remote_number_refused
                clr     >rmt_pend_kind          ; clear_pending_param_flag: the
                ldb     #ERR_RMT_NOT_NUMBER     ; field is let go, so a mode
                lbra    remote_error            ; code after it is $2D. Driven
                                                ; 2026-09-15 on ch C: 'WFB;'
                                                ; then 'TR 826;' leaves $2A and
                                                ; 'TR;' then $2D; this left
                                                ; $2B and applied the triangle

remote_set_freq
                lbsr    remote_record           ; X = the record, B = channel
                ; NO FITTED-CHANNEL REFUSAL HERE, BECAUSE THE INSTRUMENT
                ; MAKES NONE. Measured 2026-09-14 on a two-channel stock,
                ; Channel Configuration record 1, remote: 'FRC 1 KZ;',
                ; 'WFC SQ;' and 'PHC 90 DG;' all answer $00 and the record is
                ; written - 'PHC 90 DG;' even programs the chip, the third
                ; channel's phase word reading 1024 afterwards. This firmware
                ; answered $68 to all three and wrote nothing, which is an
                ; addition, and every divergence is a fault unless
                ; the owner rules otherwise. He has not ruled here.
                ldu     #rmt_val
                lbsr    freq_set
                bcs     remote_set_result       ; refused: nothing changed
                lbsr    filter_recompute_all            ; the filter follows the
                                                ; frequency: the stock's
                                                ; commit runs
                                                ; recompute_channel_byte_24ec
                                                ; ($F7EC) at $6514, and a
                                                ; frequency arriving over the
                                                ; bus is posted as a request
                                                ; code ($2389 through
                                                ; pending_setting_service
                                                ; $A791) to the same page-0
                                                ; arms
                andcc   #~CC_CARRY
                bra     remote_set_result
remote_set_ampl
                lbsr    remote_record
                ; AND NO FITTED-CHANNEL REFUSAL HERE EITHER, NOW THAT THE
                ; DIVERGENCE IS UNDERSTOOD. This arm used to answer $68 for a
                ; channel with no board, and the instrument answers $2F -
                ; which is not a refusal at all but the sound of a field that
                ; was never armed. Clearing rmt_pend_kind HERE was tried and
                ; gave $29, because by the time this runs the number and the
                ; unit have both been through; the arm has to decline earlier.
                ; It does now: chan_rq_ampl_armable (page0_screen.s) is
                ; entry_setup_channel_amptd ($4EFE)'s dispatch on the record's
                ; amplitude unit word, and it leaves rmt_pend_kind clear for a
                ; channel whose destination has no keyable unit, so the unit
                ; behind the number reaches remote_units_none and reports $2F.
                ;
                ; That leaves nothing for a test on the board to do, and such
                ; a test would now be WRONG: driven 2026-09-14 on a two-channel
                ; stock, 'DEC FM;' then 'APC 1 KZ;' answers $00 and arms - the
                ; instrument takes a deviation for a channel that has no
                ; output board, exactly as it takes the frequency, the
                ; waveform and the phase above.
                ldu     #rmt_val
                lda     >rmt_flags              ; the sign remote_value_close
                bita    #RF_MINUS               ; let through, committed as the
                beq     remote_set_ampl_plus    ; panel's own signed level is
                anda    #~RF_MINUS&$FF
                sta     >rmt_flags
                lda     #AMPL_SIGN_MINUS
                lbsr    ampl_set_signed
                bra     remote_set_result
remote_set_ampl_plus
                lbsr    ampl_set
                bra     remote_set_result
remote_set_phase
                lda     >rmt_val                ; sixteen bits only
                lbne    remote_set_too_big
                lbsr    remote_record
                ; As above: the instrument accepts this for a channel that is
                ; not fitted, and programs it.
                ldy     >rmt_val+1
                lbsr    phase_set
                lbcs    remote_refresh          ; past 3599: l6749, silent
remote_set_result
                bcs     remote_set_refused
                lbra    remote_refresh
remote_set_refused
                ldb     >last_error             ; the setter has said which;
                lbra    remote_error            ; report it over the bus too
; ---------------------------------------------------------------------------
; remote_set_tone - a number and a unit on the armed Tone Number field
;
;   uses:  A, B, X, Y, U
;
; enter_tone_number ($640C), its remote arm: with bit 3 of event_flags set it
; converts the buffer through entry_to_scaled_digits ($CDE1) with a CONSTANT
; eight where a unit code would go - the unit that ended the entry is not
; read at all, so 'KZ' means no more than 'HZ' - and ascii3_to_byte ($CA36),
; stores anything below $10 in $3D1B and records $36 for the rest at $6461.
; The tail re-arms the field, so the next number needs no second HRA. A
; leading zero is not a digit position: 'HRA 007 HZ;' selects tone 7.
; ---------------------------------------------------------------------------
remote_set_tone
                lda     >rmt_flags              ; the value is spent either
                anda    #~RF_VALUE&$FF          ; way
                sta     >rmt_flags
                lda     >rmt_val
                bne     remote_set_tone_bad
                lda     >rmt_val+1
                bne     remote_set_tone_bad
                ldb     >rmt_val+2
                cmpb    #16                     ; the sixteen tones
                bhs     remote_set_tone_bad
                stb     >tone_number
                lbra    remote_refresh          ; the screen repaints and
                                                ; re-arms its field
remote_set_tone_bad
                ldb     #ERR_TONE_RANGE         ; $36, and the tone selected
                lbra    remote_error            ; before stands

; ---------------------------------------------------------------------------
; remote_set_hopaddr - a number and a unit on the armed Hop Ram Adrs stop
;
;   uses:  A, B, X, Y, U
;
; THE COMMIT IS NOT HERE. The stock has no bus setter for this field either:
; pending_setting_service's unit leg ends by posting request $23 to the mode
; handler, whose arm for it is commit_entry_to_field ($6B84), and $2215 =
; $0012 picks arm [17], enter_hop_addr_value ($6F78). So the number is left in
; rmt_val and the code goes to the screen, where hop_bus_addr_commit
; (page0_hop.s) is that arm - on the page that owns hop_index, hop_addr_put
; and the repaint, none of which is reachable from this resident image.
;
; The field stays armed. Nothing clears rmt_pend_kind, which is what lets the
; stock take a second address with no second HRA: driven 2026-09-13,
; 'HRA 3 HZ;' then a bare '5 KZ;' moved $24F4 from $0C to $0A.
; ---------------------------------------------------------------------------
remote_set_hopaddr
                lda     >rmt_flags              ; the value is spent, whatever
                anda    #~RF_VALUE&$FF          ; the screen makes of it
                sta     >rmt_flags
                ldb     #RMT_RQ+$23
                lbra    remote_deliver

; ---------------------------------------------------------------------------
; remote_units_tonefreq - a unit on the tone record's armed FREQ field
;   entry: B = the unit code
;   uses:  A, B, X, Y, U
; unit_allowed_for_group takes Hz and kHz for the frequency group and $2E for
; the rest; the unit leg then posts $23, and the tone screen's arm for it
; commits the value through the same range check and store the panel's ENTER
; uses (tone_bus_ampl_commit, page1_tone.s). The value goes over in tenths of
; a hertz, as unit_decades scales a panel entry, with the unit in rmt_unit.
remote_units_tonefreq
                cmpb    #UNIT_KHZ
                beq     remote_units_tonefreq_ok
                cmpb    #UNIT_HZ
                lbne    remote_units_bad
remote_units_tonefreq_ok
                lda     >rmt_flags              ; a refused select's field
                bita    #RF_CLOSING             ; takes the unit and commits
                lbne    remote_closing_drop     ; nothing (remote_select)
                ldx     #unit_decades
                abx
                ldb     ,x
                lbsr    remote_scale            ; mantissa * 10^(decades -
                lbcs    remote_commit_done      ; fraction + exponent)
                ldb     #RMT_RQ+$23             ; RF_VALUE still set: the arm
                lbsr    remote_deliver          ; tells a value from an empty
                lda     >rmt_flags              ; entry by it
                anda    #~RF_VALUE&$FF
                sta     >rmt_flags
                rts

; ---------------------------------------------------------------------------
; remote_units_page_level - a volts unit on a level a page screen owns
;
;   entry: B = the unit
;   uses:  A, B, X, Y, U
;
; THE SAME SHAPE AS THE HOP ADDRESS. The tone screens' AMPTD field and Digital
; Sequence's two levels are committed on their own pages - commit_amptd_value
; ($630C) with apply_amplitude's DTMF halving, enter_level_value ($4CDA) with
; the level's sign - and pending_setting_service's unit leg reaches them by
; posting $23. So the value is scaled to microvolts here, as unit_decades
; scales the panel's, and the code goes to the screen. A unit that is not a
; voltage is refused with $2E, as for any field.
; ---------------------------------------------------------------------------
remote_units_page_level
                cmpb    #UNIT_VOLT
                beq     remote_units_page_level_ok
                cmpb    #UNIT_MILLIVOLT
                beq     remote_units_page_level_ok
                cmpb    #UNIT_MICROVOLT
                lbne    remote_units_bad
remote_units_page_level_ok
                lda     >rmt_flags              ; a refused select's field
                bita    #RF_CLOSING             ; takes the unit and commits
                lbne    remote_closing_drop     ; nothing (remote_select)
                ; THE PAGE'S OWN PARSE, NOT remote_scale's. Both stock parsers
                ; run entry_to_scaled_digits at scale 6 - which drops digits
                ; past the microvolt - then refuse nine digits or more ($CMPB
                ; #$09) and anything past $EA62 = 10,000,000 with $34. So a
                ; fraction is truncated where remote_scale refuses it, and
                ; every refusal is $34 where remote_scale and ampl_set said
                ; $29 and $7A. Driven on the emulator, both firmwares, the
                ; tone player record and Digital Sequence: 'DAPH 1.5 UV;' is
                ; 1 uV with nothing recorded, 'DAPH 10 VL;' is taken, and
                ; 'DAPH 10.000001 VL;', 'DAPH 15 VL;' and 'DAPH 250 VL;' are
                ; $34 on the instrument.
                ldx     #unit_decades
                abx
                ldb     ,x
                pshs    b
                lda     >rmt_exp
                tst     >rmt_exp_neg
                beq     remote_page_level_exp
                nega
remote_page_level_exp
                adda    ,s                      ; + decades
                suba    >rmt_frac               ; - fraction digits
                leas    1,s
                clr     >rmt_frac
                clr     >rmt_exp
                clr     >rmt_exp_neg
                tsta
                beq     remote_page_level_ceiling
                bmi     remote_page_level_down
remote_page_level_up
                pshs    a
                ldx     #rmt_val
                lbsr    unit_times_ten
                puls    a
                bcs     remote_page_level_over  ; past 24 bits is past $EA62
                deca
                bne     remote_page_level_up
                bra     remote_page_level_ceiling
remote_page_level_down
                pshs    a
                lbsr    remote_div_ten          ; the quotient stays; the
                puls    a                       ; remainder is the digit the
                inca                            ; scale drops
                bne     remote_page_level_down
remote_page_level_ceiling
                lda     >rmt_val                ; $989680, the $EA62 ceiling:
                cmpa    #$98                    ; equal is taken
                bhi     remote_page_level_over
                blo     remote_page_level_post
                ldd     >rmt_val+1
                cmpd    #$9680
                bhi     remote_page_level_over
remote_page_level_post
                lda     >rmt_flags
                anda    #~RF_VALUE&$FF
                sta     >rmt_flags
                ldb     #RMT_RQ+$23
                lbra    remote_deliver
remote_page_level_over
                lda     >rmt_flags
                anda    #~RF_VALUE&$FF
                sta     >rmt_flags
                ldb     #ERR_ENTRY_LEVEL
                lbra    remote_error

; ---------------------------------------------------------------------------
; remote_set_time - a number and a unit on the armed On or Off Time
;
;   uses:  A, B, X, Y, U
;
; apply_time_entry ($638F) stores the entry into the selected time word and
; validate_gate_time ($6033) then holds it to the same floor and ceiling the
; keys meet: below $0050 counts - $0064 while $3C03 says the DTMF screen is
; editing - or above the sixteen-bit count, error $32 and the value already
; in the cell stands. The UNIT is kept either way, in the stock's $3C87 or
; $3C89, so a refused '2 SC' still leaves the field reading in seconds.
;
; Driven on the stock 2026-09-11: 'STON 5 MS;' is 500 counts, 'STON 0.5 MS;'
; and 'STON 2 SC;' are both $32, and 'STON 0.9 MS;' is 90 counts - just over
; the floor.
; ---------------------------------------------------------------------------
; remote_time_too_long - a time whose scaling ran off twenty-four bits
;   uses:  A, B, X
remote_time_too_long
                lbsr    remote_time_unit_keep   ; the unit lands even so
                ldb     #ERR_TIME_RANGE
                lbra    remote_time_refused

; remote_time_unit_keep - the keyed unit into the twin of $3C87 or $3C89
;   exit:  B = the time's offset in the record, carry SET when neither time
;          is selected
;   uses:  A, B, X
remote_time_unit_keep
                lda     >tone_field             ; which of the two, and the
                cmpa    #TONE_FIELD_ON_R         ; unit cell that goes with it
                beq     remote_time_on
                cmpa    #TONE_FIELD_OFF_R
                bne     remote_time_none
                ldb     #TONE_OFF_R
                bra     remote_time_which
remote_time_on
                ldb     #TONE_ON_R
remote_time_which
                ldx     #tone_time_unit
                cmpb    #TONE_ON_R              ; the two unit cells are one
                beq     remote_time_unit_put    ; byte each, On then Off
                leax    1,x
remote_time_unit_put
                lda     >rmt_unit
                sta     ,x
                andcc   #~CC_CARRY
                rts
remote_time_none
                clrb
                orcc    #CC_CARRY
                rts

remote_set_time
                lda     >rmt_flags              ; the value is spent either
                anda    #~RF_VALUE&$FF          ; way
                sta     >rmt_flags
                lbsr    remote_time_unit_keep   ; B = the offset in the record
                bcs     remote_set_time_gone

                pshs    b
                lda     >rmt_val                ; a time is a sixteen-bit
                bne     remote_time_range       ; count of ten microseconds
                ldd     >rmt_val+1
                ; THE CEILING IS THE SIXTEEN-BIT COUNT ABOVE, AND NOTHING
                ; NARROWER. It used to be `cmpd #TONE_MS_MAX*TONE_MS_COUNTS /
                ; bhi remote_time_range` - 65,500 counts - put here on the
                ; reading that 65,501 to 65,535 were "reachable from the bus
                ; and from nowhere else". That reading was wrong, and the
                ; stock says so on both routes. Driven 2026-09-13, the Tone
                ; Sequence screen, stock images:
                ;
                ;   bus    'STON 655.01 MS;'  -> $3C10 = 65,501, $23DE = 0
                ;   bus    'STON 655.35 MS;'  -> $3C10 = 65,535, $23DE = 0
                ;   bus    'STON 656 MS;'     -> refused $32, the value stands
                ;   keypad f2 6 5 5 . 3 5 ms  -> $3C10 = 65,535, $23DE = 0
                ;   keypad f2 6 5 4 . 9 9 ms  -> $3C10 = 65,499, $23DE = 0
                ;
                ; The stock's bound is check_entry_below_65536 ($60C3), which
                ; compares the entry digit by digit against the ROM string at
                ; $2414 - '63556', which is 65536 written backwards - and
                ; accepts on the final borrow at $6115; $32 otherwise. So the
                ; last legal count is 65,535 = 655.35 ms, which the top-byte
                ; test two lines above already enforces exactly. There is no
                ; 655 ms ceiling on this instrument, and imposing one here
                ; refused thirty-five counts the instrument takes.
                cmpd    #$0000                  ; zero is a legal time, but
                beq     remote_time_zero        ; only if its partner is not
                cmpd    #TONE_TIME_MIN          ; the floor
                blo     remote_time_range
                ; AND THE DIALLED SCREEN'S FLOOR IS A HUNDRED, not eighty. The
                ; test below was reached only from ABOVE the floor because the
                ; compare that got here answered `beq remote_time_store` for
                ; exactly 80 - so a bus command could park a DTMF time on 80
                ; counts, which the keypad refuses with the same constants.
                tst     >tone_dtmf_mode
                beq     remote_time_store
                cmpd    #TONE_TIME_MIN_DTMF
                blo     remote_time_range
remote_time_store
                ldb     >tone_number            ; tone_times + 4 x tone, the
                andb    #TONE_TONES-1           ; stock's $3C10 + 4 x $3D1B
                lda     #TONE_TIME_SIZE_R
                mul
                ldx     #tone_times
                leax    d,x
                puls    b
                abx
                ldd     >rmt_val+1
                ; THE PLAYER READS THIS TABLE FROM THE NMI, so the write is
                ; bracketed by dds_lock exactly as the panel's commit brackets
                ; its own - DISABLE_INTERRUPTS does nothing to NMI, and a tick
                ; landing between the two bytes of this store reads half of an
                ; old time and half of a new one as the step's length.
                inc     >dds_lock
                std     ,x
                dec     >dds_lock
                lbra    remote_refresh          ; the screen repaints it

; A ZERO TIME IS LEGAL AND A PAIR OF THEM IS NOT, which is the panel's rule
; (tone_time_accept, ERR_TIME_BOTH_ZERO) and was not the bus's: 'STON 0;
; STOF 0;' left a tone with no on time and no off time, and what the player
; then does is a 655.36 ms step rather than an instant one. Traced rather
; than guessed: page1_tone.s's tone_advance_latch hands the loaded time to
; ABI_seq_timer_period, and timer.s's seq_timer_period opens with
; `subd #$0001` - so a period of zero is written to the latches as $FFFF and
; the step lasts 65,536 counts of ten microseconds. A pair of them is a
; sequence that appears to have stopped, which is why the keypad refuses it
; and why the bus does now.
remote_time_zero
                ldb     >tone_number
                andb    #TONE_TONES-1
                lda     #TONE_TIME_SIZE_R
                mul
                ldx     #tone_times
                leax    d,x                     ; X = this tone's record
                ldb     ,s                      ; the offset this command owns
                cmpb    #TONE_ON_R
                bne     remote_time_zero_off
                ldd     TONE_OFF_R,x            ; the partner is the Off time
                bra     remote_time_zero_test
remote_time_zero_off
                ldd     ,x                      ; or the On time, which is
                                                ; TONE_ON_R = offset zero - and
                                                ; written as the no-offset form
                                                ; because the two assemblers
                                                ; encode a written zero offset
                                                ; differently, lwasm $84 and
                                                ; asm6809 $00
remote_time_zero_test
                cmpd    #$0000
                bne     remote_time_store       ; the partner carries the tone
                leas    1,s
                ldb     #ERR_TIME_BOTH_ZERO
                bra     remote_time_refused
remote_time_range
                leas    1,s                     ; the offset is done with
                ldb     #ERR_TIME_RANGE         ; $32, the value standing
remote_time_refused
                ; AND THE FIELD IS REPAINTED ANYWAY, because the unit changed:
                ; apply_time_entry ($638F) calls show_time_value_field ($5AAE)
                ; after validate_gate_time ($6033) has refused, so a refused
                ; '2 SC' leaves the field reading '.00500 s' at once. Driven
                ; on the stock 2026-09-11.
                pshs    b
                lbsr    remote_refresh
                puls    b
                lbra    remote_error
remote_set_time_gone
                ldb     #ERR_RMT_NO_FIELD       ; neither time is selected
                lbra    remote_error

remote_set_too_big
                ldb     #ERR_RMT_VALUE
                lbra    remote_error

; ---------------------------------------------------------------------------
; remote_record - the record of the pending channel
;
;   exit:  X = the record, B = the channel
;   uses:  A, B, X
; ---------------------------------------------------------------------------
remote_record
                ldb     >rmt_pend_chan
                andb    #$03
                pshs    b
                lda     #CHAN_RECORD
                mul
                ldx     #channel_records
                leax    d,x
                puls    b
                ; AND NO FITTED TEST. This used to end `lbra channel_valid`,
                ; handing the caller a carry that said whether the board
                ; exists, and the four channel setters raised $68 on it. The
                ; instrument raises nothing: driven 2026-09-14 on a
                ; two-channel stock, 'FRC 1 KZ;', 'WFC SQ;' and 'PHC 90 DG;'
                ; all answer $00 and write channel C's record, and 'DEC FM;'
                ; then 'APC 1 KZ;' answers $00 as well. So the carry had no
                ; consumer left, and a result nothing reads is a result that
                ; will be read wrongly one day. The mask above stays - it is
                ; what keeps a wild channel number out of the other records -
                ; and installed_channels is still the KEYPAD's own bound,
                ; through channel_valid, which channel.s, page0_channel.s,
                ; page0_screen.s, page1_dtmf.s, modulation.s and
                ; screens_main.s all go through.
                rts

; ---------------------------------------------------------------------------
; remote_set_hop - a hop-slot field: into the table, then to the chip
;
;   uses:  A, B, X, Y, U
;
; The slot is the one the Hop screen is sitting on (hop_index), which is
; what the stock's FRH/APH/PHH act on too - its hop fields $2215 = 12..14
; edit the slot its screen shows. Frequency and amplitude are three bytes,
; the phase two, masked against the sequencer exactly as hop_store_field is.
; ---------------------------------------------------------------------------
remote_set_hop
                ldb     >hop_index
                cmpb    #HOP_SLOTS
                bhs     remote_set_too_big
                lda     #HOP_ENTRY_SIZE
                mul
                ldx     #hop_table
                leax    d,x
                lda     >rmt_pend_kind
                cmpa    #RK_HOPPHASE
                beq     remote_hop_phase
                cmpa    #RK_HOPAMPL
                bne     remote_hop_freq_check
                leax    HOP_AMPL,x
                lda     #HOP_FIELD_AMPL
                bra     remote_hop_checked
remote_hop_freq_check
                lda     #HOP_FIELD_FREQ
remote_hop_checked
                ; THE PANEL'S OWN CEILING FIRST, and there was none at all on
                ; this path: only the SLOT was bounded, so FRH could put any
                ; 24-bit number into a hop frequency and APH any into a hop
                ; level, while the same numbers typed on the Hop RAM screen
                ; are refused by hop_value_in_range - 600 kHz for a frequency,
                ; the amplitude ceiling and, with AM armed, the sum against
                ; the reference. On the instrument FRH and APH cannot skip it:
                ; they select the field ($607E, $60A1) and the value is
                ; committed by apply_hop_frequency_entry ($4BFE) and
                ; store_hop_amptd ($4CD5), the panel's own routines.
                sta     >rmt_mode_code          ; which field, for page 0
                pshs    x                       ; the slot's address
                ldx     #PAGE_ENTRY_7
                lbsr    remote_page0_check
                puls    x
                lbcs    remote_error            ; B = the code the panel raises
                ldu     #rmt_val
                DISABLE_INTERRUPTS
                lbsr    copy24
                RESTORE_INTERRUPTS
                bra     remote_hop_out
remote_hop_phase
                lda     >rmt_val
                bne     remote_set_too_big
                ldd     >rmt_val+1
                cmpd    #TOP_PHASE              ; A BUS SET IS IN TENTHS OF A
                bhi     remote_set_too_big      ; DEGREE, so the value has to
                                                ; be one - 3599 at most, which
                                                ; also keeps HOP_PHASE_RAD
                                                ; clear. Sixteen bits alone
                                                ; would have let $8000 up set
                                                ; the bit and the slot would
                                                ; have read back as radians.
                DISABLE_INTERRUPTS
                std     HOP_PHASE,x
                RESTORE_INTERRUPTS
remote_hop_out
                ; THE FILTER FOLLOWS A HOP FREQUENCY, which this did not do.
                ; The panel's own commit calls filter_apply after storing the
                ; FREQ field (hop_key_stored), because channel 0's output
                ; filter is chosen from the frequency it is producing - and
                ; this routine calls filter_apply after a channel frequency, a
                ; waveform and a destination, so the hop slot was the one
                ; commit that left the filter on the old frequency.
                lda     >rmt_pend_kind
                cmpa    #RK_HOPFREQ
                bne     remote_hop_programmed
                lbsr    filter_recompute_all
remote_hop_programmed
                ; AND THE CHIP GETS WHAT THE PANEL'S COMMIT OF THAT FIELD
                ; GIVES IT, because on the instrument it IS that commit: FRH,
                ; APH and PHH select the field ($607E, $60A1) and the value
                ; goes through $4BFE, store_hop_amptd ($4CD5) or $4DC7. So a
                ; level sends nothing while amplitude hop is off, and a
                ; frequency or phase sends the slot with the amplitude code it
                ; already had - hop_field_commit in dds.s. This used to code
                ; the slot's level afresh and send it for all three.
                lda     >rmt_pend_kind
                cmpa    #RK_HOPAMPL
                bne     remote_hop_not_level
                lda     #HOP_FIELD_AMPL
                bra     remote_hop_commit
remote_hop_not_level
                cmpa    #RK_HOPPHASE
                bne     remote_hop_freq_field
                lda     #HOP_FIELD_PHASE
                bra     remote_hop_commit
remote_hop_freq_field
                lda     #HOP_FIELD_FREQ         ; RK_HOPFREQ, the one left:
                                                ; remote_set_hop takes no
                                                ; other kind
remote_hop_commit
                ldb     >hop_index
                lbsr    hop_field_commit
                lbra    remote_refresh

; ---------------------------------------------------------------------------
; remote_set_serial - ST_ID: the serial number from the bus
;
;   uses:  A, B, X, U
;
; The stock's cmd_store_id ($A3C6) copies three bytes into serial_number
; ($3FFD) and clears installed_options ($3FFC) - HP's factory way of
; serialising a board: the serial goes in, the options start empty, and the
; codeword procedure installs them. Ported EXACTLY, on the owner's word ("i
; don't think we should drop anything"): the option clear that a first
; draft left out is here, and RAM_WRITERS.txt declares both writes with the
; owner's reason. Options wiped this way are put back from the Service
; screens, which have no lockout in either direction.
;
; THE FIELD CLOSES ON THE NUMBER IT TOOK. rmt_pend_kind is cleared before the
; value is even looked at, so the refusal legs below close it too. Without
; that, the arming this command made outlived it: 'ST_ID 190;' then
; 'BSB 911;' wrote 911 - the LATER command's argument - into serial_number
; ($3FFD), and every bare number after it did the same. The stock's own
; one-shot bus field does exactly this: enter_handler_by_index's commit at
; $F23E drops the register entry, which is what remote_set_save and
; remote_set_recall below reproduce with the same CLR.
; ---------------------------------------------------------------------------
remote_set_serial
                lda     >rmt_stid_prior         ; one number, then the field
                sta     >rmt_pend_kind          ; armed before ST_ID is back,
                clr     >rmt_stid_prior         ; as the stock never left it
                                                ; gone - see above, and rule 2
                lda     >rmt_val                ; a serial is five digits:
                cmpa    #$01                    ; nothing above 99999 = $01869F
                lbhi    remote_set_too_big      ; LONG: the hop check above
                blo     remote_set_serial_ok    ; pushed this past a byte
                ldd     >rmt_val+1
                cmpd    #$869F
                lbhi    remote_set_too_big
remote_set_serial_ok
                ldx     #serial_number
                ldu     #rmt_val
                DISABLE_INTERRUPTS
                lbsr    copy24
                clr     >installed_options      ; as the stock does; declared
                RESTORE_INTERRUPTS              ; in RAM_WRITERS.txt
                lbra    remote_refresh

; ---------------------------------------------------------------------------
; remote_set_options - ST_OP: the installed-options byte from the bus
;
;   uses:  A, B, X
;
; The owner's addition (see remote_cmd_stop). Any value 0..255 is taken:
; the byte is a bit per option and the Service screen shows what each bit
; is. The instrument reads the byte at boot, so, as the stock's own option
; screen says after a codeword install, the change takes effect at the next
; power-up.
;
; AND IT CLOSES ON THE NUMBER IT TOOK, for the reason written over
; remote_set_serial: installed_options ($3FFC) is per-unit RAM and an arming
; that outlives its command hands the next stray number on the bus the
; instrument's option word.
; ---------------------------------------------------------------------------
remote_set_options
                clr     >rmt_pend_kind          ; one number, then the field is
                                                ; gone - see remote_set_serial
                lda     >rmt_val
                ora     >rmt_val+1
                lbne    remote_set_too_big
                ldb     >rmt_val+2
                DISABLE_INTERRUPTS
                stb     >installed_options
                RESTORE_INTERRUPTS
                lbra    remote_refresh

; ---------------------------------------------------------------------------
; remote_set_sremask - SM n: the service-request-enable mask from the bus
;
;   uses:  A, B
;
; THE NUMBER SM ARMED. entry_key_handler_addr_set ($A23F) is the handler the
; SM arm installs, and it works only on the entry-complete code $0023 ($A245
; LDX >$2217 / $A248 CMPX #$0023); every other code falls to $A2BF and error
; $0F. On $0023 it runs entry_to_scaled_digits ($CDE1) with 6, refuses a
; returned code of 4 or more at $A262 with the same error $0F, parses the
; scaled field at $2414 with atoi5 ($C973), refuses anything above $00FF at
; $A289 with error $13, and passes the low byte to gpib_address_set ($9D73).
; It always clears bit 3 of $2202 at $A2D9 - the entry is gone once the
; number has been taken.
;
; THE THREE OUTCOMES, MEASURED ON THE STOCK from the Channel Configuration
; title, reading $23DE and $227E after each command:
;
;   'SM 0;' .. 'SM 255;'   $23DE = 00 and $227E takes the value. 'SM 0100;',
;                          'SM 00255;', 'SM 255.0;', 'SM 1E2;' and 'SM 2.55E2;'
;                          are 100, 255, 255, 100 and 255, so the refusal at
;                          $A262 is on the MAGNITUDE the digits scale to and
;                          not on how many characters were sent
;   'SM 256;' .. 'SM 999;' $23DE = $13, $227E untouched - atoi5's range check
;   'SM 1000;' and above   $23DE = $0F, $227E untouched - entry_to_scaled_
;                          digits' code of 4
;
; and NEITHER DISPLAY LINE MOVES on any of them, which is why this ends in an
; RTS and not in remote_refresh: the stock has no screen on this path to
; repaint. remote_sre_mask is $227E, the stock's own cell, and its consumers
; here - remote_error's bit 0 and RM's reply - are $2249's consumers on the
; instrument, where set_serial_poll_byte ($9B31) republishes $227E through
; set_srq_enable_mask ($9058).
; ---------------------------------------------------------------------------
remote_set_sremask
                clr     >rmt_pend_kind          ; $A2D9: the entry is gone
                                                ; whether the number is taken
                                                ; or refused
                lda     >rmt_val                ; four digits or more: $A262
                bne     remote_sremask_wide     ; refuses the scaled code
                ldd     >rmt_val+1
                cmpd    #999
                bhi     remote_sremask_wide
                cmpd    #255                    ; $A289 CMPX #$00FF
                bhi     remote_sremask_range
                stb     >remote_sre_mask        ; $9D73 STB >$227E
                rts
remote_sremask_range
                ldb     #ERR_VALUE_RANGE        ; $13, 'Number too large'
                lbra    remote_error
remote_sremask_wide
                ldb     #ERR_KEY_UNUSABLE       ; $0F, 'Un-executable command'
                lbra    remote_error

; ---------------------------------------------------------------------------
; remote_set_save / remote_set_recall - SV n / RC n: the register number
;
;   uses:  A, B, X, Y, U
;
; THE NUMBER. register_entry_key_handler ($F1D9) converts the typed field
; with ascii3_to_byte ($CA36) and refuses anything above 11 with CMPB #$0B
; at $F21A; while remote it reports the refusal as $13 through
; report_error_and_pulse_status_bit ($9DD3) at $F28A - the status bit and
; SRQ, which is remote_error here with ERR_REG_RANGE. An accepted number is
; stored at $2219 ($F222) and the field is torn down ($F23E clears bit 3 of
; $2202), so the pending kind is cleared here once the number is taken.
;
; SAVE. The page's entry-complete arm enter_save_register ($652C) passes
; $2219 to save_sequence_setup ($6CD7), which copies the setting into slot
; $268F + n*$01A9. register_save is that copy in this firmware's format.
;
; RECALL. enter_handler_by_index ($F16A) refuses the slot whose first word is
; still the filler $C239 with error_report_beep ($C3FE)($0E) at $F1AB - 'No
; recall setting in this register' - and otherwise runs the teardown vector
; [$2213] (clear_all_destinations $5253), selects page 0 and calls the mode
; handler saved in the slot with argument 1: enter_channel_config_mode
; ($528F) copies the slot to $24E6 ($52B2-$52F2) and re-applies it ($52FA-
; $5431). register_restore is that sequence - probe, park, copy, apply - and
; it is the same routine the panel's Save/Recall screen runs, so a recall
; from the bus and a recall from the keys are one path. The screen is not
; repainted here: the stock's remote prompt paints nothing either, and the
; recall's own words do not reach the display until the mode repaints. The
; installed screen is told to refresh (remote_refresh) so a screen showing a
; recalled field redraws it.
; ---------------------------------------------------------------------------
remote_set_save
                lbsr    remote_reg_number       ; B = the register, 0 to 11
                bcs     remote_reg_bad
                lbsr    register_save
                clr     >rmt_pend_kind          ; $F23E: the field is gone
                lbra    remote_refresh
remote_set_recall
                lbsr    remote_reg_number
                bcs     remote_reg_bad
                clr     >rmt_pend_kind          ; $F23E, before the recall
                lbsr    register_restore        ; probe, park, copy, apply;
                bcs     remote_reg_refused      ; carry: empty, ERR_REG_EMPTY
                lbra    remote_refresh          ; recorded, not reported
remote_reg_refused
                rts
remote_reg_bad
                clr     >rmt_pend_kind          ; $F29A clears bit 3 of $2202
                ; A THIRD DIGIT IS A KEY THE FIELD CANNOT TAKE, not a number
                ; too large. The register field is two digits wide, so the
                ; stock refuses a number of 100 or more as it arrives, with $0F
                ; from register_entry_key_handler, and keeps $13 for 12 to 99.
                ; Measured 2026-09-17 on Channel Configuration: RC 12, 13 and
                ; 99 and SV 99 record $13; RC 100 to 999 and SV 100 record $0F.
                ; Seeds 5 and 6 found it ('RC 256;', 'RC 890;').
                lda     >rmt_val                ; 100 or more: any high byte,
                ora     >rmt_val+1              ; or a low byte past 99
                bne     remote_reg_bad_digits
                lda     >rmt_val+2
                cmpa    #100
                bhs     remote_reg_bad_digits
                ldb     #ERR_REG_RANGE          ; on the refusal too
                lbra    remote_error            ; $F28A: $9DD3 while remote
remote_reg_bad_digits
                ldb     #ERR_KEY_UNUSABLE       ; $0F
                lbra    remote_error

; remote_reg_number - the parsed value as a register number
;   exit:  carry CLEAR and B = 0 to 11; carry SET when the value is not one
;   uses:  A, B
remote_reg_number
                lda     >rmt_val
                ora     >rmt_val+1
                bne     remote_reg_number_bad
                ldb     >rmt_val+2
                cmpb    #REGISTER_COUNT         ; $F21A CMPB #$0B / LBGT
                bhs     remote_reg_number_bad
                andcc   #~CC_CARRY
                rts
remote_reg_number_bad
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; remote_set_seqpos / remote_set_seqend - SEQP n / SEQE n
;
;   uses:  A, B, X
;
; The tone and digital screens both own a position and an end; which pair a
; number lands in is whichever screen took the SEQP/SEQE request
; (rmt_seq_owner). The bounds are the screens' own.
;
; BOTH NUMBERS ARE ONE-BASED ON THE WIRE, and both were stored raw here. That
; is not a judgement call - it is what the stock does, read out of its own
; instruction stream on 2026-09-12:
;
;   there is no separate HP-IB setter. SEQP and SEQE are type-1 records that
;   only SELECT the field - cmd_seqp_post_33 ($9C5E) posts $33 to
;   softkey_select_seq_index ($5B24), cmd_seqe_post_34 ($9C64) posts $34 to
;   softkey_select_seq_end ($5B4E) - and the number that follows is written
;   into the PANEL's own digit buffer $239A/$23A4 by
;   gpib_number_to_entry_buffer ($A47E), after which $A7FD posts request $23,
;   the entry-complete code the ENTER key posts. So the bus number is
;   committed by enter_sequence_field ($7649), whose $7776 is SUBD #$0001
;   before the $779A CMPX #$00FA and the $7789 STD [$3D37]. Page 2's
;   enter_sequence_field_value ($60BC) does the same at $6260.
;
;   the query side is the exact inverse: hpib_query_sequence's arm at $72BE
;   is LDD [$3D37] / ADDD #$0001, the same pair the LCD's own
;   show_seq_position_field ($6E71) uses at $6E7B-$6E7F. Page 2's
;   gpib_report_sequence_field ($5C30) adds one at $5C40.
;
; So 'SEQE 250' stores 249 and a query answers 250, and the number on the bus
; is the number on the glass. This stored 250 into a cell whose legal range
; ends at 249, and put SEQP's number into the PLAYER's position rather than
; into the Seq Index the stock's $3D0D is - so the bus set one cell and the
; bus query, which reads the field through tone_field_address, read another.
; ---------------------------------------------------------------------------
remote_set_seqpos
                lda     >rmt_seq_owner          ; THE OWNER DECIDES HOW WIDE
                cmpa    #$02                    ; THE NUMBER MAY BE, and this
                beq     remote_seqpos_digital_top ; narrowed it to eight bits
                                                ; before asking. The tone
                                                ; playlist is 250 steps and
                                                ; fits a byte; the digital
                                                ; cursor is a digit of a
                                                ; 1000-bit stream running to
                                                ; 999, 332 or 249 - so on a
                                                ; binary pattern every index
                                                ; above 255 was refused by a
                                                ; test belonging to the other
                                                ; screen
                lda     >rmt_val                ; the top two bytes of the
                ora     >rmt_val+1              ; three: nothing this wide is
                lbne    remote_seq_refused      ; a step
                ldb     >rmt_val+2
                tstb                            ; a typed 0 has no zero-based
                lbeq    remote_seq_refused      ; form: $7776's SUBD would
                                                ; wrap it to $FFFF and $779A
                                                ; refuses that
                cmpb    #TONE_PLAYLIST          ; 250 steps, not sixteen, and
                lbhi    remote_seq_refused      ; a COMPARE - 250 is not a
                clra                            ; power of two so it cannot be
                subd    #1                      ; masked. ONE-BASED IN,
                std     >tone_cursor            ; ZERO-BASED STORED, and into
                                                ; the Seq Index - the cursor -
                                                ; which is the cell the stock's
                                                ; $3D0D is and the cell this
                                                ; firmware's own bus query
                                                ; reads back
                std     >tone_window            ; AND THE WINDOW ORIGIN GOES
                                                ; WITH IT. enter_sequence_field
                                                ; ($7649) ends a typed Seq Index
                                                ; with $77C4 CMPX #$3D0D /
                                                ; $77CB STD >$3D39 - the origin
                                                ; is set to the cursor, so the
                                                ; sixteen cells start AT the
                                                ; index that was typed. Only
                                                ; the Seq Index does this; a
                                                ; Seq End leaves the origin
                                                ; alone, which is what the
                                                ; CMPX tests, and the arrows
                                                ; deliberately scroll instead.
                                                ; The panel's own commit already
                                                ; did this (tone_commit_seq);
                                                ; the bus stored the cell and
                                                ; skipped it, so 'SEQP 5 ET;'
                                                ; put 5 on the readout with the
                                                ; window still showing steps 1
                                                ; to 16. Driven on the stock
                                                ; 2026-09-13: Seq Index 5 shows
                                                ; '[456789ABCDEF0123]', 100
                                                ; '[3456789ABCDEF012]' and 250
                                                ; '[9               ]'
                ldb     #RMT_RQ+$23             ; AND THE SCREEN'S OWN $23: in
                lbsr    remote_deliver          ; Manual the stock's entry arm
                                                ; apply_seq_entry_manual ($64AC)
                                                ; plays the step it lands on
                lbra    remote_refresh

                ; A REFUSED STEP IS STILL THE SCREEN'S $23. The stock's bus
                ; number goes into the entry buffer and its unit posts $23
                ; like any other, so SEQP and SEQE land in
                ; enter_sequence_field ($7649) exactly as ENTER does: a
                ; refusal at $7790 or $779D pends $37 or $38 by $3D37
                ; (report_seq_range_error, $7629), l77a7 snaps the window to
                ; the index that stands, and commit_sequence_digit ($64FA)
                ; sounds the step at the cursor before the tail reports.
                ; Measured on the stock: 'SEQP 251 ET;' and 'SEQP 0 ET;' give
                ; $37, 'SEQE 0 ET;' $38. This answered all three with $29 and
                ; posted nothing. The kind in rmt_pend_kind says which field.
remote_seq_refused
                lda     >rmt_pend_kind
                cmpa    #RK_SEQPOS
                bne     remote_seq_refused_end
                ldd     >tone_cursor            ; l77a7: the index's window
                std     >tone_window
remote_seq_refused_end
                ldb     #RMT_RQ+$23             ; the sound, through the arm
                lbsr    remote_deliver          ; that makes it for a taken one
                ldb     #ERR_SEQ_INDEX
                lda     >rmt_pend_kind
                cmpa    #RK_SEQPOS
                lbeq    remote_error
                ldb     #ERR_SEQ_END
                lbra    remote_error
remote_seqpos_digital_top
                lda     >rmt_val                ; the top byte of the three:
                lbne    remote_set_too_big      ; nothing this wide is legal
remote_seqpos_digital
                ; A DIGIT INDEX, SIXTEEN BITS WIDE. It was a step number
                ; below sixteen, which was the rewrite's own model; the
                ; instrument's cursor $3CA2 is a digit of a 1000-bit stream
                ; and runs to 999, 332 or 249 depending on the base.
                ; THROUGH THE PANEL'S OWN COMMIT, on page 2. This stored
                ; the cell here and skipped edit_clamp_index, the window that
                ; follows the cursor, and the two error codes the keypad
                ; answers with - so a bus index past the end stayed past the
                ; end. page2_bus_index does the subtract, the limit, the store,
                ; the clamp and the bit indices, which is the one commit the
                ; instrument itself uses for both routes.
                clr     >rmt_mode_code          ; 0 = the Seq Index
                ldx     #PAGE2_BUS_INDEX
                lbsr    remote_page2_check
                lbcs    remote_error
                lbra    remote_refresh
remote_set_digbit
                ; THE BIT NUMBER RUNM ARMED. enter_bit_index ($4DE1) runs
                ; enter_sequence_field_value ($60BC) on $3CAC = $0B - the typed
                ; index less one, measured in bits and stored if below the
                ; capacity - then drives the bit under the cursor.
                ; page2_bus_index takes it with mode 2. A number past sixteen
                ; bits is a range refusal there, not an overflow here, so
                ; page2_bus_index sees every value. Driven on the emulator,
                ; stock and rewrite, 2026-09-15: 'RUNM 5 KZ;', 'RUNM 3;',
                ; 'RUNM 999 UV;', 'RUNM 10000;' and 'RUNM 7 HZ;' record 0,
                ; 'RUNM 0 KZ;' and 'RUNM 99999 UV;' record $37.
                lda     #$02                    ; 2 = the Bit field
                sta     >rmt_mode_code
                ldx     #PAGE2_BUS_INDEX
                lbsr    remote_page2_check
                lbcs    remote_error
                lbra    remote_refresh
remote_set_seqend
                lda     >rmt_seq_owner          ; the owner first, as above:
                cmpa    #$02                    ; the digital end is sixteen
                beq     remote_seqend_digital_top ; bits wide
                lda     >rmt_val                ; refused as remote_set_seqpos
                ora     >rmt_val+1              ; refuses: $38, the window
                lbne    remote_seq_refused      ; left, the step sounded
                ldb     >rmt_val+2
                lbeq    remote_seq_refused      ; an end of zero plays nothing
                cmpb    #TONE_PLAYLIST          ; an END may equal the length,
                lbhi    remote_seq_refused      ; so BHI not BHS
                clra
                subd    #1                      ; ONE-BASED IN, ZERO-BASED
                std     >tone_end               ; STORED: tone_end is a LAST
                                                ; INDEX, 0 to 249, and the
                                                ; screen shows it plus one
                                                ; (page1_tone.s:530). See the
                                                ; header: the stock's $7776
                ldb     #RMT_RQ+$23             ; AND THE SCREEN'S $23, as
                lbsr    remote_deliver          ; SEQP posts it: SEQE's arm is
                                                ; commit_sequence_digit ($64FA),
                                                ; which sounds the step at the
                                                ; cursor
                lbra    remote_refresh
remote_seqend_digital_top
                lda     >rmt_val
                lbne    remote_set_too_big
remote_seqend_digital
                ; through the same commit as the index arm above
                lda     #$01                    ; anything but 0 = the Seq End
                sta     >rmt_mode_code
                ldx     #PAGE2_BUS_INDEX
                lbsr    remote_page2_check
                lbcs    remote_error
                lbra    remote_refresh

; ===========================================================================
; THREE ROUTINES THAT WENT WITH THE FIX ABOVE, and are not coming back.
;
; remote_digital_limit, remote_digital_bits and remote_digital_last computed
; the digit ceiling, the bit indices and the last bit of a digit for the bus's
; own copy of the digital cursor. That copy is gone: remote_seqpos_digital now
; commits through PAGE2_BUS_INDEX, which is the panel's own edit_index_typed,
; and that does the subtract, the limit, the store, the clamp and the bit
; indices in one place for both routes - which was the whole point of the
; change. The three were left standing, called by nothing, and
; tests/test_reachable.py found them.
;
; Deleted rather than parked in UNREACHED: a routine kept for a caller the fix
; removed is not a deliberate absence, it is the fix half done.
; page2_digital.s:digital_digit_count still holds the same three-way switch
; for the screen, and tests/test_digital_pack.py drives it.
; ===========================================================================

; ---------------------------------------------------------------------------
; remote_refresh - a value changed under the screen: let it repaint
;
;   uses:  A, B, X, Y, U - B carries KEY_REFRESH, the rest is the screen's
;
; KEY_REFRESH is the foreground's own "repaint yourself" code, which every
; screen's ignore arm ends in - so a screen that shows the changed field
; redraws it and one that does not is untouched.
; ---------------------------------------------------------------------------
remote_refresh
                ldb     #KEY_REFRESH
                lbra    remote_deliver

; ===========================================================================
; The command handlers the records point at. Each is entered from the record
; walk with A = the record's argument byte (and, for a type-2 record, B = the
; digit that followed).
; ===========================================================================

; --- field selectors: FRx APx PHx WFx DEx, and the hop fields --------------
;
; A FIELD SELECT IS A REQUEST TO THE SHOWING SCREEN, NOT AN ARMING. This
; block used to write rmt_pend_kind itself, so the field was armed wherever
; the operator happened to be and the number behind the mnemonic committed on
; every screen in the tree. That is not what the instrument does, and the
; difference is one cell.
;
; set_channel_queue_1d ($9BFF) and its seven siblings ($9BDC-$9BFF) do TWO
; things and neither is arming a field: l9c04 stores the record's argument in
; $23BE, puts the request code in $2389 and sets bit 0 of $2281. The
; foreground's pending_setting_service ($A73E) then posts that code to the
; installed mode handler through post_request_code ($8AD0) at $A78C - and
; there it either finds an arm or it does not. Only an arm that reaches
; begin_numeric_entry ($A415) sets $238F, and EVERY later leg of
; pending_setting_service reads $238F before it will let a value through: the
; bare number at $A7EA, the mode code at $A87A and the unit at $A900, which
; answer $2B, $2D and $2F respectively when it is clear.
;
; DRIVEN ON THE STOCK 2026-09-13, with $238F watched throughout:
;
;   Channel Config. ch A     'FRA 900 HZ;' 9000 then 'HP 5 KZ;' 50000,
;                            $238F = 01 the whole time - the screen has the
;                            arm, so HP's trailing '5 KZ' lands in the field
;                            FRA left open
;   Channel Config. title    'FRA 900 HZ;' 9000, $238F = 01. The d6044 arms
;                            do not test which record of the chain is up
;   Channel Config. Hop Ram  'FRA 900 HZ;' 9000 and 'FRH 100 KZ;' into the
;                            slot, $238F = 01 for both
;   Channel Config. ch A     'FRH 100 KZ;' into the slot, $238F = 01: the hop
;                            leg at $604E takes bit 3 of event_flags - REMOTE
;                            - OR $268E = 5, so over the bus a hop field is
;                            reachable from any record of the chain
;   Tone Sequence            'FRB 922;' $2B, 'FRB 1670 MV;' $2F, 'HP 5 KZ;'
;                            $2F, $238F = 00 throughout and channel B's
;                            frequency untouched
;   Digital Sequence         'FRD 251 UV;', 'ON 1000 VL;', 'PR 10 DG;',
;                            'STOF 10 VL;' and 'PR 5639 HZ;' all $2F with
;                            $238F = 00 - including the two that do take a
;                            value, because the code each posts ($19 to arm
;                            [24] and $11 to arm [16] of the page-2 table
;                            $6E67) is not one that screen arms a field for
;
; This firmware committed every one of those: 2,000,000 into channel B for
; 'FRB 922;' on the Tone Sequence screen and 56,390 into channel D for
; 'PR 5639 HZ;' on the Digital Sequence one - a controller changing a channel
; from a screen where the instrument answers with an error number.
;
; So the code goes to the screen and the screen answers it. rmt_pend_kind is
; this firmware's $238F: screen_install (screen.s) clears it on every screen
; change, the page-0 chain's chan_bus_request (page0_screen.s) sets it for
; $19-$1D and $28-$2A, and the tone and digital screens already set it for
; the codes they answer. Clearing it HERE is what makes a screen with no arm
; leave it clear.
;
; remote_sel_freq .. remote_sel_hopphase - the field-select commands
;   entry: A = the channel (or 0 for a hop field)
;   uses:  A, B, X, Y, U - the screen's handler runs on this call
remote_sel_freq
                ldb     #$19                    ; set_channel_queue_19 ($9BEB)
                bra     remote_select
remote_sel_ampl
                ldb     #$1A                    ; set_channel_queue_1a ($9BF0)
                bra     remote_select
remote_sel_phase
                ldb     #$1C                    ; set_channel_queue_1c ($9BFA)
                bra     remote_select
remote_sel_wave
                ldb     #$1B                    ; set_channel_queue_1b ($9BF5)
                bra     remote_select
remote_sel_dest
                ldb     #$1D                    ; set_channel_queue_1d ($9BFF)
                bra     remote_select
remote_sel_hopfreq
                ldb     #$28                    ; set_channel_queue_28 ($9BDC)
                bra     remote_select
remote_sel_hopampl
                ldb     #$29                    ; set_channel_queue_29 ($9BE1)
                bra     remote_select
remote_sel_hopphase
                ldb     #$2A                    ; set_channel_queue_2a ($9BE6)
remote_select
                sta     >current_channel        ; l9c04's STA >$23BE: the
                                                ; channel the panel acts on
                                                ; moves too, the one on the
                                                ; glass does not - see
                                                ; shown_channel in ram.inc
                sta     >rmt_pend_chan          ; A = the channel from the
                                                ; record's argument, which
                                                ; l9c04 stores in $23BE before
                                                ; it queues anything. THE
                                                ; CHANNEL IS NOT TESTED HERE,
                                                ; and the reason is the stock:
                                                ; its own selector stores the
                                                ; argument and queues a request
                                                ; code without looking at it,
                                                ; and the refusal happens in
                                                ; the shared commit that the
                                                ; ENTER key reaches too.
                                                ; remote_record below carries
                                                ; that test, so one command
                                                ; answers with one error and a
                                                ; query on an absent channel
                                                ; still reports
                lda     >rmt_flags              ; a new select ends any field
                anda    #~RF_CLOSING&$FF        ; a refused one put back
                sta     >rmt_flags
                lda     >rmt_pend_kind          ; the field armed before this
                pshs    a                       ; select, 1,s below
                lda     >last_error             ; and the error standing, ,s
                pshs    a
                clr     >last_error             ; so a refusal can be seen
                clr     >rmt_pend_kind          ; NO FIELD IS ARMED UNTIL THE
                                                ; SCREEN SAYS SO. $238F is set
                                                ; by begin_numeric_entry
                                                ; ($A415) and by nothing on the
                                                ; parser's side of the machine
                orb     #RMT_RQ                 ; and the code goes to whichever
                lbsr    remote_deliver          ; screen is up, as $A78C posts
                                                ; it to the mode handler

                ; BUT A SELECT THE SCREEN REFUSES LEAVES THE OLD FIELD ARMED.
                ; The sequence screens' reject arms ($5071 on page 1, $6E4F on
                ; page 2) store $3A, or $3B for a window, and report it; none
                ; of them touches $238F, so the entry that was pending before
                ; the refused mnemonic is still pending after it. Measured
                ; 2026-09-17 on seeds 1 and 4: 'PHC 822;' on the Tone Sequence
                ; screen records $3A alone on the instrument and $3A then $2B
                ; here; 'APD 251 VL;' and 'DAPH 10 SC;' record only the
                ; refusal there, and the refusal then $2F here; 'WFA 1000 RD;'
                ; $3A then $2E there, $3A then $2F here. So when the screen
                ; armed nothing and recorded one of those two codes, the field
                ; goes back; otherwise the error standing before the select is
                ; put back if nothing new was recorded.
                tst     >rmt_pend_kind
                bne     remote_select_kept_error
                lda     >last_error
                cmpa    #ERR_WRONG_MODE
                beq     remote_select_refused
                cmpa    #ERR_WRONG_WINDOW
                bne     remote_select_kept_error
remote_select_refused
                lda     1,s                     ; the field armed before
                sta     >rmt_pend_kind
                beq     remote_select_refused_done
                lda     >last_error             ; A $3B REFUSAL CLOSES THE
                cmpa    #ERR_WRONG_WINDOW       ; ENTRY, AND SO DOES ANY ON THE
                beq     remote_select_closing   ; DIGITAL SEQUENCE SCREEN; a $3A
                lda     >current_page           ; on the Tone Sequence screen
                cmpa    #2                      ; does not. Measured 2026-09-17:
                bne     remote_select_refused_done ; there $238F stays 01 through
                                                ; 'WFA 1000 RD;' and 'PHC 822;'
                                                ; ($3A), and goes to 00 on
                                                ; 'DAPH 10 SC;' ($3B, 10 SC then
                                                ; committing nothing); on the
                                                ; digital screen 'APD 251 VL;'
                                                ; ($3A) closes it too
remote_select_closing
                lda     >rmt_flags              ; FOR THIS COMMAND ONLY, AND
                ora     #RF_CLOSING             ; COMMITTING NOTHING. Measured
                sta     >rmt_flags              ; 2026-09-17, Digital Sequence
                                                ; after 'DAPH 283;': 'APD 251
                                                ; VL;' records $3A alone on the
                                                ; instrument - the number and
                                                ; unit went to the old field, no
                                                ; $2B or $2F - yet commits
                                                ; nothing (no range error) and
                                                ; leaves $238F = 0, so 'FRA 251
                                                ; DG;' after it records $3A,
                                                ; $2B and $2F. A unit the old
                                                ; field does not take is still
                                                ; $2E ('WFA 1000 RD;' on the
                                                ; tone screen)
remote_select_refused_done
                leas    2,s
                rts
remote_select_kept_error
                tst     >last_error             ; nothing recorded by the
                bne     remote_select_done      ; select: the standing error
                lda     ,s                      ; is what it was
                sta     >last_error
remote_select_done
                leas    2,s
                rts

; ---------------------------------------------------------------------------
; remote_page0_check - run one of page 0's checks and put the page back
;
;   entry: X = the page 0 vector (PAGE_ENTRY_6 or PAGE_ENTRY_7), with the
;          check's own arguments already in RAM
;   exit:  carry SET and B = the error code if the value was refused
;   uses:  A, B, X, and whatever the check uses
;
; A BUS VALUE MUST FAIL THE SAME TEST A KEYED ONE FAILS, and on the instrument
; that is not a policy but the shape of the firmware: the bus mnemonics select
; a field and the number goes through the panel's own entry buffer and commit,
; so one validator serves both routes. This firmware answers those commands
; here, in the resident image, while the validators are on page 0 - so the two
; had to be joined explicitly. The evidence is written out over the routine
; page0_wave_check, in hp8904a-rewrite/modules/page0_screen.s.
;
; THE ANSWER COMES BACK IN RAM. page_call's carry says "this did not work" for
; two different events - the paged check refused the value, or the page switch
; itself failed - and those need different answers, so the sentinel below is
; written first and the check overwrites it. If it survives, page 0 never ran.
;
; The page that was mapped is put back, as register_hop_reapply does and for
; the same reason: leaving the window somewhere the caller did not choose is
; the kind of state that is harmless until it is not.
; ---------------------------------------------------------------------------
RMT_CHECK_PENDING equ   $FF             ; no answer written yet. Not a legal
                                        ; error code: the run in formats.inc
                                        ; stops well below it, and a zero
                                        ; would read as "accepted"

remote_page2_check
                ; THE SAME HANDSHAKE, for page 2. The digital editor's own
                ; commit lives there, and remote.s is resident.
                ldb     #PAGE_DIGITAL_SEQUENCE
                bra     remote_page_check_at

remote_page1_check
                ; AND FOR PAGE 1, whose playlist writer seq_put_nibble ($452D)
                ; and whose two sequence screens live there together. The
                ; stream's per-character handler is page1_bus_stream, reached
                ; through the vector at $400A.
                ldb     #PAGE_TONE_SEQUENCE
                bra     remote_page_check_at

remote_page0_check
                ldb     #PAGE_CHANNEL_CONFIG
remote_page_check_at
                pshs    b                       ; THE PAGE THE CALLER ASKED
                                                ; FOR. It was loaded into B and
                                                ; then loaded over with page 0
                                                ; four instructions later, so
                                                ; every page 2 call went to
                                                ; page 0, found no such
                                                ; routine at that offset and
                                                ; came back with the sentinel
                                                ; standing
                lda     #RMT_CHECK_PENDING
                sta     >rmt_check_result
                ldb     >current_page           ; the page that was mapped
                pshs    b
                ldb     1,s                     ; the page to call
                lbsr    page_call
                ldb     ,s                      ; put the window back first,
                cmpb    #PAGE_COUNT             ; while nothing is being held
                bhs     remote_page0_kept       ; in a register
                lbsr    page_select_and_verify
remote_page0_kept
                leas    2,s                     ; the saved page and the one
                                                ; that was asked for
                ldb     >rmt_check_result
                beq     remote_page0_ok         ; zero: the check passed
                cmpb    #RMT_CHECK_PENDING
                bne     remote_page0_refused    ; an error code: it refused
                ldb     #ERR_RMT_NO_FIELD       ; the sentinel still stands, so
                                                ; page 0 never ran - the switch
                                                ; failed. Refusing is the only
                                                ; honest answer: the value was
                                                ; not checked, so it may not be
                                                ; stored
remote_page0_refused
                orcc    #CC_CARRY
                rts
remote_page0_ok
                andcc   #~CC_CARRY
                rts

; --- mode codes: waveforms, destinations, on/off -----------------------------
; The stock's store_code_221f_flag_bit4 records carry the label code itself
; as their argument, and this firmware's LBL_* numbering IS the stock's
; ($EEEE/$EF0E), so A arrives already meaning what wave_program and
; destn_apply expect.
;
; AND THE SAME FIELD TEST THE OTHER TWO LEGS MAKE, with its own error. This
; is bit 4 of $2281, the stock's $A866 leg: clear the bit, then LDB >$238F /
; CMPB #$00 / LBEQ $A8D9, and $A8D9 reports $2D - 'Unique data received but
; not expected'. Only with a field armed does it call scale_code_allowed
; ($A600), and a code that routine refuses is $2C at $A8C3, 'Invalid Unique
; data received'. Both were $2B here, which is the BARE NUMBER's error and
; belongs to a different leg. Driven on the stock 2026-09-13 on the Digital
; Sequence screen, where nothing is armed: 'ON 1000 VL;' leaves $23DE at $2F
; - the unit's own refusal, raised after this one - with $238F reading 00
; throughout and no channel touched.
; remote_mode_code - a waveform, destination or on/off word
;   entry: A = the label code
;   uses:  A, B, X, Y, U
remote_mode_code
                pshs    a
                lda     >rmt_pend_kind
                lbeq    remote_mode_none        ; $A8D9: no field armed at all
                cmpa    #RK_WAVE
                beq     remote_mode_wave
                cmpa    #RK_DEST
                beq     remote_mode_dest
                cmpa    #RK_OUTPUT
                lbeq    remote_mode_output      ; LONG: the two option checks
                                                ; between here and there put it
                                                ; out of a byte's reach
                cmpa    #RK_HOPROW              ; AHR/FHR/PHR/DPE armed a row
                lbeq    remote_mode_hoprow      ; of the hop On/Off page
                cmpa    #RK_FILTER              ; FS n armed the filter field
                lbeq    remote_mode_filter
                puls    a                       ; A FIELD IS ARMED AND IT IS NOT
                ldb     #ERR_RMT_UNIQUE_BAD     ; a choice: $A8C3's $2C, which
                lbra    remote_error            ; is what scale_code_allowed
                                                ; ($A600) refusing the code for
                                                ; the armed field's class reads
                                                ; as
remote_mode_none
                puls    a                       ; NOTHING ARMED: $A8D9's $2D.
                ldb     #ERR_RMT_UNIQUE_NONE    ; The stock asks $A600 nothing
                lbra    remote_error            ; on this leg
remote_mode_wave
                puls    b                       ; B = the code
                cmpb    #LBL_SQUARE
                lbhi    remote_mode_bad         ; LONG: the checks below moved
                tstb                            ; the target out of reach
                lbeq    remote_mode_bad
                ; THE PANEL'S OWN RULE FIRST. chan_wave_allowed is on page 0
                ; with the channel screen; without this the bus could set Ramp,
                ; Triangle or Square on a channel above 50 kHz - error $96, or
                ; $71 while frequency hop is armed - or dc into a modulation
                ; destination ($97, $98, $99), every one of which the keypad
                ; refuses. The instrument refuses them on both routes because
                ; its bus command and its ENTER key reach one commit; this
                ; firmware answers the command here, so it has to ask.
                stb     >rmt_mode_code
                ldx     #PAGE_ENTRY_6
                lbsr    remote_page0_check
                lbcs    remote_error            ; B = the code the panel raises
                ldb     >rmt_mode_code
                pshs    b
                lbsr    remote_record           ; X = record, B = channel
                ; AND NO FITTED TEST, because the instrument makes none here
                ; either. Measured 2026-09-14 on a two-channel stock,
                ; 'WFC SQ;' answers $00 and the third channel's record takes
                ; the square wave; this firmware answered $68 and wrote
                ; nothing. Same reading as remote_set_freq and
                ; remote_set_phase above.
                puls    a                       ; A = the code
                sta     CHAN_WAVE,x             ; the record first, as the
                exg     a,b                     ; channel screen does; then
                lbsr    wave_program            ; A = channel, B = code
                lbcs    remote_mode_bad
                lbsr    filter_recompute_all            ; and the filter follows the
                                                ; waveform, $F7EC at $68B2

                ; AND THE LEVEL GOES BACK ON THE CHIP WITH IT, because the
                ; code a level is programmed as depends on the waveform.
                ; enter_wform_selection ($6ED7) is the stock's one waveform
                ; commit and the bus reaches it too - WFA-WFD select the
                ; field and the mode code goes through the panel's own entry
                ; buffer to request $0023, the ENTER code. It calls
                ; apply_waveform_choice ($674C) - the checks, the store into
                ; record+$1F, unit_code_select_head ($E38F) and the filter
                ; $F7EC - and then, at $6EE5: LDX >$23BF / LEAX 10,X / TFR
                ; X,U / LDB >$23BE / CLRA / TFR D,Y / LDX #$0004 / PSHS X,Y,U
                ; / LBSR $C069. That is dispatch_channel_function with the
                ; channel and the record's level at +10, which is
                ; ABI_ampl_reapply here: it re-derives the DDS code from the
                ; record as it now stands, with no range check and no store.
                ;
                ; MEASURED on the front panel 2026-09-13, both firmwares side
                ; by side: WAVE FORM + 6 on channel A moves the level
                ; register 1879 -> 3156, because ampl_raw's dc arm halves the
                ; code a second time and folds it through $0FFF
                ; ($D4A3-$D4FB). page0_screen.s does this for the keypad;
                ; over the bus the store and wave_program ran and the level
                ; did not, so the socket kept producing the sine's amplitude
                ; while the record said dc. It is done HERE and not in
                ; page0_wave_check because that check is a VALIDATOR - it runs
                ; before anything is stored, and the level has to be reapplied
                ; from the record AFTER the new waveform is in it, which is
                ; the order $6EE5 has ($674C stores, then $C069 reapplies).
                lbsr    remote_record           ; X = the record, B = the
                lbsr    ABI_ampl_reapply        ; channel, as $6EE5 has them
                lbra    remote_refresh
; remote_mode_absent WAS HERE, and remote_no_channel with it - both gone with
; their last caller. remote_mode_absent dropped the mode code the wave arm
; had pushed before refusing $68, and remote_no_channel was the $68 itself,
; reported by the freq, wave, phase and amplitude arms for a channel with no
; board. NONE OF THE FOUR REFUSES ANY MORE, because the instrument does not:
; the first three take the value and write the record (2026-09-14, 'FRC',
; 'WFC', 'PHC' on a two-channel stock, all $00), and the fourth declines to
; ARM when the destination has no keyable unit - chan_rq_ampl_armable in
; page0_screen.s - which is a different event with a different code, $2F. A
; label nothing branches to is dead code, which test_reachable refuses, and
; the byte the wave arm pushes is now always consumed by the puls after the
; call. ERR_NO_SUCH_CHANNEL is still the keypad's own answer and is still
; raised by channel.s, page0_channel.s, page0_screen.s, page1_dtmf.s,
; modulation.s and screens_main.s; what has gone is the BUS raising it.

remote_mode_dest
                puls    b
                cmpb    #LBL_AM
                lblo    remote_mode_bad
                cmpb    #LBL_OFF
                lbhi    remote_mode_bad
                ; AND THE OPTION, as the panel's own commit asks first: without
                ; Option FW the keypad answers ERR_OPTION_DESTN
                ; (chan_destn_allowed) and this routed the modulator anyway.
                pshs    b                       ; the mode code, over the call
                ldx     #PAGE_ENTRY_8
                lbsr    remote_page0_check
                bcs     remote_mode_dest_refused ; B IS THE ERROR CODE HERE, so
                                                ; the code is pulled only on the
                                                ; path that goes on - pulling it
                                                ; first put LBL_FM, 8, into
                                                ; last_error in place of the
                                                ; refusal $1F
                puls    b
                pshs    b                       ; the code, for the step test
                lda     >rmt_pend_chan          ; below - destn_apply does not
                anda    #$03                    ; promise B back
                lbsr    destn_apply             ; A = channel, B = code; it
                bcs     remote_mode_dest_bad    ; stores and routes
                ; AND THE STEP GOES BACK TO ZERO, which the panel does and this
                ; did not: chan_cycle_dest clears incr_ampl on every change to
                ; anything but Off (the stock's $7A62-$7A71), because the step
                ; is in the unit the OLD destination's level was keyed in - so
                ; after 'DEB OC1;' then 'DEB FM;' the INCR key applied a
                ; volts-sized count to a percentage.
                ldb     ,s+                     ; the code, and the stack back
                cmpb    #LBL_OFF
                beq     remote_dest_step_kept
                lbsr    remote_incr_ampl_addr   ; THIS channel's step: the
                clr     ,x                      ; stock zeroes record+15 for
                clr     1,x                     ; the record whose destination
                clr     2,x                     ; changed and no other
remote_dest_step_kept
                lbsr    filter_recompute_all            ; and the filter follows the
                                                ; destination, $F7EC at $7ED8
                lbra    remote_refresh
remote_mode_dest_bad
                ; THE REFUSAL IS ALREADY REPORTED, AND NOT AS $2C. destn_apply
                ; is carry set only after destn_check or destn_route has
                ; recorded and sounded its own code - $65 a channel
                ; modulating itself, $66-$68, $99, and $69-$6C inside the
                ; routing - as set_channel_destination ($78BF) does through
                ; error_report_beep ($C3FE), which raises no service request.
                ; This sent it on to remote_mode_bad, which put $2C over the
                ; code and pulled SRQ: measured 2026-09-16, 'DEA AM;' on ch A
                ; leaves $65 in the stock's $23DE with SRQ and every lamp
                ; unchanged, and left $2C here with SRQ up (acceptance 4.8).
                ; So the pushed code comes off and the tail the change takes
                ; runs - the filter and the refresh, which find nothing moved
                ; after a check refusal and the channel Off after a routing
                ; one - skipping only the step reset, since the destination
                ; asked for was not taken.
                leas    1,s                     ; the code this arm pushed
                bra     remote_dest_step_kept
remote_mode_dest_refused
                leas    1,s                     ; the code, with B already the
                lbra    remote_error            ; error the check answered
                ; --- the hop On/Off page's armed row -----------------------
                ; set_hop_function_enable ($4984) reads $0011 as On and
                ; anything else as Off, but nothing that is not On or Off
                ; reaches it: scale_code_allowed ($A600) is asked first and
                ; refuses with $2C. Driven on the stock 2026-09-13, Hop Ram
                ; record: 'AHR;' then 'ON;' sets $2203 to $40, 'AHR;' then
                ; 'OF;' clears it, and 'AHR;' then 'SI;' leaves $23DE = $2C
                ; with $2203 untouched. So the pair is tested here and the
                ; refusal is remote_mode_bad's, which is $2C.
                ;
                ; The choice goes to $221F and the code to the screen, exactly
                ; as the stock's mode leg does: store_code_221f_flag_bit4
                ; ($9CE3) writes $221F and pending_setting_service posts $23,
                ; whose arm is apply_mode_toggle ($6FCB). hop_want is $221F.
                ; The row stays armed afterwards - $238F was still 01 on the
                ; stock after the switch - so a second ON or OF needs no
                ; second AHR.
remote_mode_hoprow
                puls    b                       ; ON ($11) or OF ($10)
                cmpb    #LBL_ON
                beq     remote_hoprow_want
                cmpb    #LBL_OFF
                lbne    remote_mode_bad         ; $2C, as $A8C3 answers
remote_hoprow_want
                stb     >hop_want               ; $221F
                ldb     #RMT_RQ+$23
                lbra    remote_deliver
remote_mode_output
                puls    b                       ; ON ($11) or OF ($10)
                cmpb    #LBL_ON
                beq     remote_output_on
                cmpb    #LBL_OFF
                bne     remote_mode_bad
                clra                            ; off
                bra     remote_output_apply
remote_output_on
                lda     #$01
                bra     remote_output_apply
; remote_mode_filter - SH, LO or AU into the field FS n armed
;   entry: 0,s = the label code remote_mode_code pushed
;   uses:  A, B, X, Y, U
; filter_select_key_handler ($F9D4) takes the entry-complete while remote at
; $F9E8: $3A7C less one is the channel, the mode is 3 unless $221F is $12 (0)
; or $13 (1), set_output_enable_mode ($F770) stores and drives it - and does
; nothing for a channel that is not fitted - and $3A7F = 2 lets the overlay
; go, returning 1 so the screen underneath hears $3C. scale_code_allowed
; ($A600) admits only $12-$14 to this field. Driven on the stock 2026-09-15:
; 'FS2;' 'SH;' leaves $24E8+1 = 0, 'FS3LO;' $24E8+2 = 1 with the line
; following, 'FS2;' 'AU;' $24E8+1 = 3, 'FS9;' records nothing, and 'FRA;'
; 'SH;' records $2C.
remote_mode_filter
                puls    b
                cmpb    #$12                    ; SH
                blo     remote_mode_bad
                cmpb    #$14                    ; AU
                bhi     remote_mode_bad
                lda     #FILTER_SHARP           ; $12: mode 0
                cmpb    #$12
                beq     remote_filter_have
                lda     #FILTER_LOW_OVER        ; $13: mode 1
                cmpb    #$13
                beq     remote_filter_have
                lda     #FILTER_AUTOMATIC       ; $14: mode 3
remote_filter_have
                clr     >rmt_pend_kind          ; the field is used
                ldb     >output_channel
                pshs    a
                lbsr    channel_valid           ; carry set if not fitted
                puls    a
                bcs     remote_filter_close
                ldx     #filter_mode
                sta     b,x
                lbsr    filter_apply
remote_filter_close
                lbsr    register_prompt_dismiss ; $3A7F = 2
                ldb     #KEY_ABANDON            ; and $3C to the screen
                ldx     >screen_handler         ; underneath
                beq     remote_filter_done
                jmp     ,x
remote_filter_done
                rts

remote_mode_bad
                ; $2C, NOT $29. This is the ONE refusal the stock has for a
                ; mode code the armed field cannot take: pending_setting_
                ; service's bit-4 leg calls scale_code_allowed ($A600) and
                ; reports $2C at $A8C3 when it says no - 'Invalid Unique data
                ; received'. $29 is the number leg's error, raised at $A46E
                ; when a NUMBER overflows, and a mode code is not a number.
                ; The header over remote_mode_code already said $2C was the
                ; answer; this line did not give it.
                ;
                ; Driven on the stock 2026-09-13, Channel Configuration chain:
                ; 'DEA;' then 'SI;' leaves $2C in $23DE, and 'AHR;' then 'SI;'
                ; leaves $2C. ('WFA;' then 'SI;' is 00 - Sine IS a waveform
                ; code, so it commits, which is why the destination and the
                ; hop row are the two that show it.)
                ldb     #ERR_RMT_UNIQUE_BAD
                lbra    remote_error

; ---------------------------------------------------------------------------
; remote_output_apply - switch the pending output's relay
;
;   entry: A = 1 for on, 0 for off; rmt_pend_chan = the output
;   uses:  A, B, X
;
; The same sequence the Output On/Off screen's ENTER runs: the latch bit
; through channel_latch_rmw under the dds lock, then chan_state_sync so the
; record agrees with the relay. LATCH_OUTPUT is active low - clear is ON.
; ---------------------------------------------------------------------------
remote_output_apply
                pshs    a                       ; AN OUTPUT THAT IS NOT FITTED
                ldb     >rmt_pend_chan          ; HAS NO RELAY TO DRIVE. The
                lbsr    channel_valid           ; stock records nothing for
                puls    a                       ; 'OO9;' 'OF;'; this skips the
                bcs     remote_output_close     ; latch write as well
                inc     >dds_lock               ; THE STORE AND THE CALL ARE
                tsta                            ; ONE OPERATION under the lock,
                beq     remote_output_bit_off   ; as the panel's ENTER does it:
                clr     >latch_bits             ; an NMI between them would
                bra     remote_output_write     ; write the sequence player's
remote_output_bit_off                           ; latch_bits into this relay
                lda     >screen_bit             ; and its range bits
                sta     >latch_bits
remote_output_write
                lda     >screen_bit             ; OUTPUT for OO, FLOAT for FC
                ldb     >rmt_pend_chan
                andb    #$03
                lbsr    channel_latch_rmw
                dec     >dds_lock
                ldb     >rmt_pend_chan
                andb    #$03
                lbsr    chan_state_sync
                lbsr    led_output_refresh      ; the OUTPUT lamps say what
                lbsr    remote_refresh          ; the relays do
remote_output_close
                clr     >rmt_pend_kind          ; the field is used
                lbsr    register_prompt_dismiss ; the screen goes, returning
                ldb     #KEY_ABANDON            ; 1: $3C to the screen
                ldx     >screen_handler         ; underneath
                beq     remote_output_done
                jmp     ,x
remote_output_done
                rts

; --- unit codes: HZ KZ DG RD VL MV UV PC/% ET SC MS ------------------------
; remote_unit_code - a unit mnemonic: commit the pending value in it
;   entry: A = the UNIT_ code
;   uses:  A, B, X, Y, U
remote_unit_code
                tfr     a,b                     ; the record argument is the
                lda     >rmt_flags              ; unit code
                bita    #RF_NUMBER
                beq     remote_unit_closed
                pshs    b
                lbsr    remote_value_close
                puls    b
                bcs     remote_unit_done
remote_unit_closed
                pshs    b                       ; the unit code
                lbsr    remote_unit_close_field ; the number leg runs first
                puls    b
                lbra    remote_commit_units     ; refuses with no value
remote_unit_done
                rts

; ---------------------------------------------------------------------------
; remote_unit_close_field - the stock runs its NUMBER leg before its UNIT leg
;
;   uses:  A, B, X, Y, U
;
; pending_setting_service ($A73E) walks the bits of $2281 in a fixed order,
; and the no-unit leg at $A7D6 comes before the unit leg at $A8EC. So when a
; number and a unit are both waiting - 'SM 1 UV;', 'SV 3 VL;' - the number is
; offered to the field FIRST, and what happens next is decided by the field's
; units class in $238B:
;
;   class 2..7 (an armed FREQ, AMPTD or PHASE field)  $A5C1's gate holds the
;     number: $A830 falls through to $A866 in silence with $238F still set,
;     and the unit leg is what commits it. 'FRA 1.5 KZ;' latches 15000
;   class 0 or 1 (the entry SM and SV arm)  the number COMMITS and the entry
;     closes, so the unit leg then finds $238F = 0 and reports $2F,
;     'Terminator received but not expected'
;
; Measured on the stock, from the Channel Configuration title: 'SM 1 UV;',
; 'SM 7 VL;' and 'SM 1 HZ;' each leave $227E = 1, 7 and 1 AND $23DE = $2F,
; and 'SV 3 VL;' writes register 3 - slot $268F+3*$01A9 goes from $0000 to
; $528F, the same word a bare 'SV 3;' writes there - AND reports $2F.
;
; This firmware ran the unit leg alone: rmt_pend_kind was still RK_SREMASK or
; RK_SAVE when the unit arrived, remote_commit_units found no units arm for
; it and answered $2E with the number thrown away, so 'SM 1 UV;' set no mask
; and 'SV 3 VL;' saved no register. The fix is the stock's own ordering, for
; the kinds whose bare number commits.
;
; ONLY THOSE KINDS. The rows of rmt_needs_unit - RK_TONE and RK_TIME among
; them, 'STON 5;' storing nothing and reporting nothing on the stock - are
; held by $A5C1, so calling the flush for any of them would set the value
; aside where the unit in this same command still has to find it.
; ---------------------------------------------------------------------------
remote_unit_close_field
                lda     >rmt_flags
                bita    #RF_VALUE               ; nothing waiting: the unit
                beq     remote_unit_open        ; leg is on its own anyway
                lda     >rmt_pend_kind
                ldx     #rmt_bare_closes
                ldb     #RMT_BARE_CLOSES
remote_unit_close_scan
                cmpa    ,x+
                lbeq    remote_flush_default    ; commit it and close the
                decb                            ; field; its RTS is ours
                bne     remote_unit_close_scan
remote_unit_open
                rts

; The kinds whose entry the number leg closes, one byte each. Each was driven
; on the stock, and the reason is on its row.
rmt_bare_closes fcb     RK_SREMASK              ; SM: gpib_address_set ($9D73)
                fcb     RK_SAVE                 ; SV: $F222 then $F23E
                fcb     RK_RECALL               ; RC: driven 2026-09-15 with ch
                                                ; B's frequency keyed to 5 kHz
                                                ; after 'SV 2;' - 'RC 2 HZ;'
                                                ; puts 1 kHz back on the stock
                                                ; and reports $2F, while this
                                                ; recalled nothing and said $2E
                fcb     RK_SERIAL               ; ST_ID: 'ST_ID 999 SC;' reports
                                                ; $2F on the stock with the
                                                ; serial written (what it
                                                ; writes is docs/reach-open.md
                                                ; Q4), and reported $2E here
                fcb     RK_OPTIONS              ; ST_OP, the owner's addition:
                                                ; no stock mnemonic to measure,
                                                ; so it closes like ST_ID, the
                                                ; sibling it was spelled after
RMT_BARE_CLOSES equ     5                       ; the five rows above, counted
                                                ; here because the scan needs a
                                                ; length and a label after the
                                                ; last fcb would be a body-less
                                                ; one

; --- the type-2 (one digit) commands: FC FS GM OO OC -----------------------
; remote_cmd_fc / remote_cmd_fs - FC n / FS n: open the screen, key n
;   entry: B = the digit
;   uses:  A, B, X, Y, U
remote_cmd_fc                                   ; FC n: the Output Float
                pshs    b                       ; screen's remote leg
                lbsr    output_float_open
remote_output_armed
                ; show_output_onoff_screen ($F5A0) while remote: $3A7C = the
                ; digit in $2219 with no range test, begin_numeric_entry
                ; (6, 0) and $3A7D = 1 - stage two, waiting for ON or OF -
                ; with its handler at $220D, which refuses any other message
                ; with $18 and lets the screen go. Driven on the stock
                ; 2026-09-15: 'OO2;' 'OF;' sets bit 2 of $24F0+1 and 'OO2;'
                ; 'ON;' clears it, 'FC3;' 'OFF;' sets bit 1 of $24F0+2 and
                ; 'FC3;' 'ON;' clears it, 'OO9;' and 'OO0;' record nothing
                ; and nor does the OF after them, and 'OO2;' 'FRA;' records
                ; $18. This firmware had opened no screen for OO, fed FC's
                ; digit in as a key that nothing armed a field after, and
                ; refused 0 and 9 with $29.
                puls    b
                decb                            ; less one, as the stage-two
                stb     >output_channel         ; arm does
                stb     >rmt_pend_chan
                lda     #$01
                sta     >output_stage           ; $3A7D = 1
                ldb     #RK_OUTPUT
                lbra    remote_cmd_store_kind
remote_cmd_fs                                   ; FS n: filter_screen_show's
                pshs    b                       ; remote leg ($FC4C) - the
                lbsr    filter_screen_open      ; overlay, painting nothing
                puls    b                       ; while remote; $3A7C = the
                decb                            ; digit, less one here where
                stb     >output_channel         ; the stock subtracts at $23;
                ldb     #RK_FILTER              ; begin_numeric_entry (7, 0)
                lbra    remote_cmd_store_kind
; remote_cmd_gm - GM n: open entry n of the Main Selection Level
;   entry: B = the digit
;   uses:  A, B, X, Y, U
remote_cmd_gm                                   ; GM n: open entry n of the
                cmpb    #MAIN_SLOTS-1           ; Main Selection Level, COUNTED
                bhi     remote_gm_bad           ; FROM ZERO as the stock counts:
                                                ; GM n posts $0A with $2219 = n
                                                ; and option_feature_enter
                                                ; ($8AEA) indexes the ten slots
                                                ; at $2224 with it. THE SLOTS
                                                ; ARE THE STOCK'S NOW, two per
                                                ; record - 0 Channel Config., 2
                                                ; Tone, 3 DTMF, 4 Digital - so
                                                ; the digit means on the bus
                                                ; what it means on the panel.
                                                ; It indexed a fifteen-entry
                                                ; list of this firmware's own
                                                ; before, in an order the
                                                ; README had to explain.
                tfr     b,a
                lbra    main_menu_slot          ; an empty slot opens nothing
remote_gm_bad
                ldb     #ERR_RMT_VALUE
                lbra    remote_error
; remote_cmd_oo - OO n: the Output On/Off screen, waiting for ON or OF
;   entry: B = the digit
;   uses:  A, B, X, Y, U
remote_cmd_oo                                   ; OO n: the Output On/Off
                pshs    b                       ; screen's remote leg
                lbsr    output_onoff_open
                bra     remote_output_armed
; remote_cmd_oc - OC n: output n as a destination code
;   entry: B = the digit 1..4
;   uses:  A, B, X, Y, U
remote_cmd_oc                                   ; OC n: output n as a
                tstb                            ; destination code $0C-$0F,
                beq     remote_gm_bad           ; the one type-2 mode record
                cmpb    #CHANNEL_MAX
                bhi     remote_gm_bad
                addb    #LBL_OUT1-1
                tfr     b,a
                lbra    remote_mode_code

; --- key equivalents ---------------------------------------------------------
; Each stock request code below is one the stock's OWN keymap posts for a
; front-panel key ($AE3D and the compare chain at $AEBB), so the bus command
; and the key are the same event; the code is delivered to the same handler
; the key reaches. The record argument is the key code.
; remote_as_key - a bus command that is a key: deliver it as that key
;   entry: A = the key code
;   uses:  whatever the key's handler uses (A, B, X, Y, U)
remote_as_key
                tfr     a,b
                lbra    foreground_key

; --- direct actions (request codes no key produces) ------------------------
; remote_cmd_ps .. remote_cmd_stid - the direct actions
;   uses:  A, B, X, Y, U (each is a tail call into the routine named)
remote_cmd_ps
                ; PS: REQUEST 7, AND IT IS THE ARM THAT RESETS THE OUTPUTS.
                ; queue_action_7 ($9C7E) posts $0007 and $8F13 sends it to
                ; event7_return_to_main_menu ($8D8C), which JSRs the screen
                ; exit vector $2213, calls reset_all_channel_outputs ($80F3),
                ; zeroes $23C1 and only then enters the Main Selection Level.
                ; Driven on the stock 2026-09-11 with channel A at 1 V: 'PS;'
                ; writes 248 words to the synthesis port and comes back to the
                ; Main Selection. This returned to the top level and left every
                ; channel driving - the one bus command whose whole purpose is
                ; to put the instrument back to a known state.
                ;
                ; AND THE VECTOR RUNS FIRST. $8D8C's own order is `LDX >$2213
                ; / JSR ,x` and only then reset_all_channel_outputs. This
                ; called channel_reset_all first and let main_menu_open reach
                ; the vector afterwards, which is not the same thing:
                ; instrument_preset parks every routed_dest at LBL_OFF, so
                ; channel_mode_exit then found nothing routed and wrote not
                ; one word where the instrument writes eighty. Measured
                ; 2026-09-13 from Channel Configuration with an amplitude on
                ; channel A; the gate is test_reset_words_new.py, in
                ; emulator/tests. main_menu_open below finds the vector
                ; already cleared and does not run it a second time.
                lbsr    screen_exit_run
                lbsr    channel_reset_all
                clr     >special_flags          ; $8DBC's zeroing of $23C1
                lbra    main_menu_open
remote_cmd_em                                   ; EM: request $0B, arm [10]
                lbra    main_menu_open          ; return_to_main_menu
remote_cmd_rp                                   ; RP: request 8, arm [7]
                lbra    channel_probe_clear     ; arm_clear_output_latches
remote_cmd_pr                                   ; PR: request $11, arm [16]
                lbra    dds_phase_reset_now     ; the unvetoed phase pulse
remote_cmd_bp                                   ; BP: a beep from timer 1
                lbra    beep_now
remote_cmd_bo                                   ; BO: the backlight on
                lbra    backlight_wake
remote_cmd_bf                                   ; BF: the backlight off, now
                lbra    backlight_off
; remote_cmd_sm - SM: the NEXT number is the service-request-enable mask
;   uses:  A, B, X, Y, U
;
; SM OPENS NO SCREEN. This firmware sent it to remote_sre_open, which clears
; the glass and paints '*****    SERVICE REQUEST MASK 0-255 ****' over
; whatever the operator was looking at. The instrument does not: the whole
; stock path is
;
;   record $9982 (type 1, 'M' under 'S') -> cmd_sm_post_0e ($9C79) LDX #$000E,
;   BRA $9CD7, which parks the code in $2389 and raises bit 0 of $2282;
;   pending_setting_service's leg at $A765 clears that bit and hands $2389 to
;   post_request_code ($8AD0) -> $2217 = $000E, bit 2 of event_flags;
;   ui_message_dispatch takes arm [13] of the $8F2A table,
;   key_arm_enter_a23f_mode ($8E81) -> start_numeric_entry_a23f ($A2E4):
;   begin_numeric_entry ($A415)(0,0) - which writes $238D, $238B, the entry
;   buffer $239A, $23A4, $2281 and $238F and has NO display in its io list -
;   then STD $A23F into $220D and bit 3 of $2202.
;
; Not one instruction on it writes the LCD. Measured on the stock, from the
; Channel Configuration title: 'SM 1 UV;', 'SM 128;' and a bare 'SM;' all
; leave both display lines exactly as they were.
;
; What it leaves behind is an ARMED CLASS-0 ENTRY - $238F = 1 with $238B = 0 -
; so the number that follows is the mask. Measured on the stock: 'SM;' alone
; leaves $238F = 1 and $227E untouched, and a later bare '55;' then writes
; $227E = $37. That is exactly what rmt_pend_kind holds open here, so SM is a
; store-kind command like SV, RC and ST_ID and not a screen. The panel still
; reaches remote_sre_open from the Service menu, which is this firmware's own
; way in and the only caller of it that remains.
remote_cmd_sm                                   ; SM: the NEXT number is the
                ldb     #RK_SREMASK             ; service-request-enable mask
                bra     remote_cmd_store_kind
; remote_cmd_stid - ST_ID: empty the options, and arm the serial
;   uses:  A, B, X, Y, U
;
; THE STOCK DOES TWO THINGS HERE AND THIS FIRMWARE DOES ONE OF THEM.
; cmd_store_id ($A3C6) runs the moment ST_ID is parsed, with no number
; waited for: copy3 puts the three bytes at $221C into serial_number and
; then CLR >installed_options. The number that follows reaches no armed
; field and records $2B. Driven on the stock 2026-09-15: a bare 'ST_ID;'
; leaves $3FFC = 00 with the serial reading 000064, and 'ST_ID 999;' and
; 'ST_ID 12;' both record $2B and store that same 000064.
;
; THE CLEAR IS PORTED. It is HP's factory way of serialising a board -
; serial in, options empty until the codewords install them - and it is
; what the instrument does.
;
; THE COPY IS NOT, and that is the architect's ruling of 2026-09-15,
; in his words: "The stock copying work cell $221C
; into the serial is leftover arithmetic - the same class as the $CD stack
; leak you correctly refused to reproduce. Do NOT port a leak into the
; instrument's serial." $221C is the entry accumulator, so what the stock
; writes there is whatever the last entry left in it.
;
; WHAT THE NUMBER DOES INSTEAD is the owner's own addition, the same one
; ST_OP is: "serial and options programming over gbip would be nice to
; have can you implement that". RK_SERIAL stays armed so ST_ID n writes n,
; which is why this firmware records nothing where the instrument records
; $2B. hp8904a-rewrite/RAM_WRITERS.txt declares both writes.
remote_cmd_stid
                clr     >installed_options      ; cmd_store_id's CLR, at the
                                                ; moment the stock does it
                lda     >rmt_pend_kind          ; AND THE FIELD ARMED BEFORE IT
                sta     >rmt_stid_prior         ; IS KEPT: the stock's ST_ID
                                                ; takes no number and leaves
                                                ; $238F alone, so a unit after
                                                ; it is judged against that
                                                ; field - 'ST_ID 999 SC;' after
                                                ; 'DAPL 5 MV;' is $2E on the
                                                ; instrument (seed 6 step 141),
                                                ; $2F with nothing armed
                ldb     #RK_SERIAL              ; and the NEXT number is the
                bra     remote_cmd_store_kind   ; serial, which is ours
; remote_cmd_sv / remote_cmd_rc - SV and RC: the NEXT number is a register
;   uses:  A, B, X, Y, U
;
; The stock's SV posts request $21 ($9987 -> cmd_sv_post_action_21 $9CC7)
; and RC posts $22 ($994E -> cmd_rc_post_action_22 $9CD1). $21 reaches the
; installed mode handler through call_installed_handler_220f (arm [32] of
; the $8F2A table) - key_save_register ($4CAD) on page 1, key_save_prompt on
; page 2 - and $22 reaches state_open_recall_register ($8E9B, arm [33]).
; Both end in save_recall_prompt ($F331), which, while remote (event_flags
; bit 3 set, $F34D-$F36D), paints nothing and only arms the register-number
; entry: begin_numeric_entry ($A415), $220D = $F1D9, bit 3 of $2202. The
; number that follows is completed by register_entry_key_handler ($F1D9):
; ascii3_to_byte of the field, CMPB #$0B at $F21A, STB >$2219, and then
; either the page's entry-complete arm enter_save_register ($652C) for a
; save or enter_handler_by_index ($F16A) for a recall. So on the bus SV and
; RC are the ST_ID shape - a command that names what the next number is
; for - and they are recorded that way: RK_SAVE and RK_RECALL, committed by
; remote_set_save and remote_set_recall. Executed on the stock over the
; modelled bus (emulator/tests/test_bus_registers_new.py): 'SV 3;' writes
; slot 3, 'RC 3;' brings the setting back, a bare number afterwards is
; error $2B - the field is gone once the number has been taken, which is
; what clearing rmt_pend_kind after the commit reproduces.
remote_cmd_sv
                ; SV POSTS $21, as the Save key does, through the shared tail
                ; at $9CD7 that '?' uses for $25. Pages 0, 1 and 2 let their
                ; field go and reach register_screen_open, whose remote leg
                ; arms RK_SAVE; every other screen refuses it. Driven on both,
                ; 2026-09-15: 'SV;' on the Main Selection Level records $0F on
                ; the instrument, and 'SV 3;' there saves nothing and records
                ; $2B, where this had saved register 3.
                lda     #$21
                lbra    remote_to_screen
remote_cmd_rc
                ldb     #RK_RECALL
                bra     remote_cmd_store_kind
; remote_cmd_stop - ST_OP: the NEXT number is the installed-options byte
;   uses:  A, B, X, Y, U
;
; NOT IN THE STOCK. The stock can set the serial from the bus (ST_ID) but
; has no bus command for the options - they only ever came from the codeword
; screen. The owner asked for both to be programmable over the bus ("serial
; and options programming over gbip would be nice to have can you implement
; that"), so this is the one mnemonic added to HP's set, spelled as ST_ID's
; sibling. RAM_WRITERS.txt declares the write.
remote_cmd_stop
                ldb     #RK_OPTIONS
remote_cmd_store_kind
                lda     >rmt_flags              ; AN ARM EMPTIES THE ENTRY, as
                anda    #~RF_HELD&$FF           ; begin_numeric_entry ($A415)
                sta     >rmt_flags              ; does: no number held for
                                                ; another field reaches SV,
                                                ; RC, SM, ST_ID or ST_OP - the
                                                ; last two write $3FFD and
                                                ; $3FFC (rule 2)
                clr     >rmt_field_gone         ; and the field is a field
                stb     >rmt_pend_kind
                lda     >rmt_flags              ; a number already parsed goes
                bita    #RF_VALUE               ; straight in
                beq     remote_store_kind_done
                lbra    remote_flush_default
remote_store_kind_done
                rts

; --- requests delivered to the screen (the stock's mode-handler arms) -------
; Each goes to the installed screen as RMT_RQ + its request code. The tone
; screen answers RUNC RUNS RUNM STOP STON STOF SBP SEQP SEQE HRA and '?';
; the digital screen RUNC RUNS STOP SEQP SEQE WSQ and '?'; the DTMF screen
; WSQ and '?'. QRE, BSB, BSO, BSH, the four rate selects AHR FHR PHR DPE,
; and the trigger reach NO arm on any screen here
; - their stock consumers are the mode handlers' own tables and this
; firmware's screens have no such functions - so every one of them falls
; to key_refuse, which records the error, beeps and reports over the bus:
; the three things the stock's default arm (reject_key_error_3a, $5071)
; does for a code its screen does not use.
; remote_to_screen - deliver A as a bus request code to the screen
;   entry: A = the stock's request code
;   uses:  A, B, X, Y, U
remote_to_screen
                tfr     a,b                     ; A = the request code
                orb     #RMT_RQ
                lbra    remote_deliver
; remote_cmd_rate - AHR FHR PHR DPE: request $2B with a sub-code
;   entry: A = the sub-code 0..3
;   uses:  A, B, X, Y, U
remote_cmd_rate                                 ; AHR FHR PHR DPE: $2B with a
                sta     >rmt_tmp                ; sub-code the stock parks in
                lda     #$2B                    ; $2219; delivered as $2B, the
                bra     remote_to_screen        ; sub-code kept in rmt_tmp for
                                                ; a screen that wants it

; --- the direct-answer queries: ID HP RM RSF EO -----------------------------
; remote_cmd_id - ID: the identification banner, in the stock's words
;   uses:  A, B, X, Y, U
remote_cmd_id
                ; THE STOCK'S OWN BLOCK. cmd_id_send_banner ($9D2C) thunks to
                ; gpib_send_id_banner ($A3A0), which calls build_id_banner
                ; ($8000) at $A3AB - the same builder the banner on the glass
                ; uses - and queues all eighty characters from $2285, the
                ; forty-column padding included. Driven on the stock:
                ; 'HP 8904A Opts 02/01/03' and eighteen spaces, then
                ; 'Firmware Revision 27887A Serial No 11111'. This built a
                ; shorter reply of its own, with the padding left out and '02'
                ; present whatever the channel count.
                lbsr    id_banner_build         ; at rmt_out, as $8000 is at
                ldx     #rmt_out                ; $2285
                ldb     #ID_LINES
                lbra    remote_queue

; remote_cmd_hp - HP: the last error number, three digits
;   uses:  A, B, X, Y
remote_cmd_hp                                   ; HP: the last error, 3 digits
                ldb     >last_error
                bra     remote_reply_3
; remote_cmd_rm - RM: the service-request-enable mask, three digits
;   uses:  A, B, X, Y
;
; RM REPORTS THE PUBLISHED MASK, NOT THE TYPED ONE. cmd_rm_status_mask_query
; ($9D28) thunks to hpib_query_srq_mask ($A09A), which reads $2249 through
; gpib_status_byte_get ($9D8D) and hpib_sre_mask_get ($9B40) - and $2249 is
; not $227E. gpib_address_set ($9D73) stores the typed byte at $227E and then
; calls set_serial_poll_byte ($9B31), whose set_srq_enable_mask ($9058) ANDs
; it with $BF before storing it at $2249, so bit 6 - RQS in the status byte -
; can never be enabled. Measured on the stock: 'SM 255;' leaves $227E = $FF
; and $2249 = $BF, and 'SM 100;' leaves $64 and $24. This firmware keeps one
; cell at the stock's $227E and applies the mask where the stock's own
; consumers see it, which is here and in remote_error's bit-0 test.
remote_cmd_rm                                   ; RM: the SRQ mask, 3 digits
                ldb     >remote_sre_mask
                andb    #$BF                    ; $9058: RQS is never enabled
                bra     remote_reply_3
; remote_cmd_eo - EO: is an external reference connected? '1' or '0'
;   uses:  A, B, X, Y
remote_cmd_eo                                   ; EO: is the external
                lda     >kbd_rows               ; reference ABSENT? The stock's
                clrb                            ; external_ref_absent returns 1
                bita    #$40                    ; when bit 6 of $0000 is CLEAR
                bne     remote_reply_3          ; (LBEQ ldc2b: LDB #$01), and
                incb                            ; hpib_query_ext_ref formats
                                                ; that. A first draft answered
                                                ; the opposite for both states
; remote_reply_3 - queue the byte in B as three decimal digits
;   entry: B = the value, 0 to 255
;   uses:  A, B, X, Y, U
remote_reply_3
                lbsr    remote_reply_text
                ldx     #text_buffer+TEXT_DIGITS-3
                ldb     #3
                lbra    remote_queue
; remote_reply_5 - queue the byte in B as five decimal digits
;   entry: B = the value, 0 to 255
;   uses:  A, B, X, Y, U
;
; The stock's five-digit answers are sixteen bits wide - the {4,5,18} cascade
; of gpib_query_value_response ($7B7A) renders them with u16_to_5_ascii_digits
; ($C912) and sets the length to 5 - and every field answered this way here is
; a label code below 256, so the top three digits are the zeros $C912 writes
; too.
remote_reply_5
                lbsr    remote_reply_text
                ldx     #text_buffer+TEXT_DIGITS-5
                ldb     #5
                lbra    remote_queue
; remote_reply_text - render the byte in B as eight digits in text_buffer
;   entry: B = the value, 0 to 255
;   uses:  A, B, X
;
; The tail is a branch, not a call: uint24_to_text's RTS returns to whichever
; of the two routines above asked for the digits.
remote_reply_text
                clr     >rmt_tmp
                clr     >rmt_tmp+1
                stb     >rmt_tmp+2
                ldx     #rmt_tmp
                lbra    uint24_to_text          ; eight, leading zeros kept
; remote_cmd_rsf - RSF: the special-function register, five digits
;   uses:  A, B, X, Y, U
;
; cmd_rsf_display_number ($9D10) calls display_number_23c1 ($A373), which
; renders the WORD at $23C1 with u16_to_5_ascii_digits ($C912) into $2285 and
; queues five characters. So the reply is the live register, not a constant.
;
; THIS QUEUED THE CONSTANT "00000" UNTIL 2026-09-20, on the stated ground that
; this firmware has no code-locked special functions so the register would
; always be zero. That ground was false in this firmware's own code, and the
; read-through found it: special_flags IS $23C1. special_key_commit sets and
; clears its bits from the Special Functions screen's ENTER key, error_beep is
; gated on bit 2 of it, and the amplitude path reads bit 4. With any special
; function turned on the instrument answered a non-zero word here and this
; answered zero.
;
; ONE BYTE WHERE THE STOCK HAS A WORD, and the five digits come out the same.
; Every bit the five images read out of $23C1 is read out of its LOW byte -
; $8DBC clears the word, build_option_dispatch_table does LDD >$23C1 / ANDB
; #$01, copy_or_negate_to_channel_reg_08 ($E319) does ANDA #$00 / ANDB #$08,
; program_channel_phase ($6635) tests bit 3 the same way - so the high byte is
; a zero nobody sets, and special_flags is the low byte alone.
; remote_reply_5 renders a byte into the five digits $C912 would write for a
; word whose top eight bits are clear, which is that same word.
remote_cmd_rsf                                  ; RSF: the live register
                ldb     >special_flags          ; $A373's LDD >$23C1
                lbra    remote_reply_5          ; $C912 then queue_gpib_output

; --- $3F : report the selected field ---------------------------------------
; A QUERY GOES TO THE SCREEN AND NOWHERE ELSE. cmd_query_post_25 ($9C6F) is
; the whole of the stock's '?': LDX #$0025 then the shared tail at $9CD7,
; which parks the code in $2389 and raises bit 0 of $2281, and the foreground
; at $A765 hands it to post_request_code ($8AD0). The instrument has no
; bus-level answer to a query at all - request $25 is entry [36] of every
; mode table - so this command is the delivery and the arms below are what a
; page-0 screen reaches through ABI_remote_query_field.
;
; WHAT IT USED TO DO, AND WHY THAT WAS WRONG. This dispatched on
; rmt_pend_kind, which is this firmware's $238F - the cell that says a field
; is ARMED for a value. The stock's page-0 arm ($635E, which calls $DB2B with
; page 3 and entry $7B7A) dispatches on $2215, the cell that says which field
; is SELECTED. The two moved together until the AMPTD arm learned to select
; without arming, and then 'APC;' on a channel whose destination is Off left
; $2215 = $0002 with $238F = $00 - selected, not armed. Driven side by side
; 2026-09-14, two channels, Channel Configuration record 1, remote: the stock
; answered '?' with eight digits and this firmware with '? No Data ?' and
; last_error $0F, because RK_NONE fell through to a screen with no '?' arm.
;
; A screen with no arm for $25 still ends in key_refuse, which records $0F -
; and that is the instrument too. Driven 2026-09-13 on the Main Selection
; Level: the stock answers 'FRA?;' with '? No Data ?' and $23DE = $0F.
; remote_cmd_query - '?': hand request $25 to the installed screen
;   uses:  A, B, X, Y, U
remote_cmd_query
                lda     #$25
                lbra    remote_to_screen

; ---------------------------------------------------------------------------
; remote_query_field - answer a '?' from the field id the instrument uses
;
;   entry: A = the stock's $2215, the id of the SELECTED field
;   uses:  A, B, X, Y, U
;
; THE WHOLE OF gpib_query_value_response ($7B7A), which is what the page-0
; chain's request-$25 arm at $635E reaches: $635E loads $7B7A into U and 3
; into Y and calls call_routine_on_a2u13_page ($DB2B), which switches A2U13
; to page 3, calls that entry, and switches back. $7B7A then runs four
; cascades on $2215 and queues the one that matches through queue_gpib_output
; ($9FFE). Every arm and every length below was read out of that routine:
;
;   id   what it reports                          rendered as
;   $01  the record's frequency, 24 bits          8 digits, point at 7   (9)
;   $02  the record's level, 24 bits              point by destination   (9)
;   $03  the record's phase, 16 bits              5 digits, point at 4   (6)
;   $04  the record's waveform word               5 digits               (5)
;   $05  the record's destination word            5 digits               (5)
;   $06  the frequency INCREMENT, 24 bits         8 digits, point at 7   (9)
;   $07  the level increment, 24 bits             point by destination   (9)
;   $08  the phase increment, 16 bits             5 digits, point at 4   (6)
;   $0C  the hop slot's frequency                 8 digits, point at 7   (9)
;   $0D  the hop slot's level                     8 digits, point at 2   (9)
;   $0E  the hop slot's phase, 16 bits            5 digits, point at 4   (6)
;   $0F  the hop frequency increment              8 digits, point at 7   (9)
;   $10  the hop level increment                  8 digits, point at 2   (9)
;   $11  the hop phase increment, 16 bits         5 digits, point at 4   (6)
;   $12  the Hop Ram address stop                 3 digits               (3)
;
; $00 and $09 to $0B ARE NOT ARMS. The four cascades' last test falls to a
; `clr 3,s` and the tail at $7EB2 returns without calling $9FFE at all, so
; those ids queue NOTHING and the controller reads the idle '? No Data ?'.
; Driven on the stock 2026-09-14, Hop Ram record with no field selected:
; $2215 = $0000 and '?' answers '? No Data ?' with $23DE = $00 - silence, not
; an error. Every id above $12 does the same.
;
; THE RECORD IS THE COMMANDED CHANNEL'S, not the screen's. $7B7A reads the
; pointer at $23BF, which cache_channel_record_ptr ($C21A) moves, and a bus
; mnemonic moves it: driven on a two-channel stock with the screen on ch A,
; 'APA;' then '?' answers '00.000140' - ch A's 140 uV - and 'APC;' then '?'
; answers ch C's empty record. rmt_pend_chan is that pointer here, which is
; why every arm below goes through remote_record.
; ---------------------------------------------------------------------------
remote_query_field
                cmpa    #$01
                lbeq    remote_query_freq
                cmpa    #$02
                lbeq    remote_query_ampl
                cmpa    #$03
                lbeq    remote_query_phase
                cmpa    #$04
                lbeq    remote_query_wave
                cmpa    #$05
                lbeq    remote_query_dest
                cmpa    #$06
                lbeq    remote_query_freq_incr
                cmpa    #$07
                lbeq    remote_query_ampl_incr
                cmpa    #$08
                lbeq    remote_query_phase_incr
                cmpa    #$0C
                lbeq    remote_query_hopfreq
                cmpa    #$0D
                lbeq    remote_query_hopampl
                cmpa    #$0E
                lbeq    remote_query_hopphase
                cmpa    #$0F
                lbeq    remote_query_hopfreq_incr
                cmpa    #$10
                lbeq    remote_query_hopampl_incr
                cmpa    #$11
                lbeq    remote_query_hopphase_incr
                cmpa    #$12
                lbeq    remote_query_hopaddr
                rts                             ; not an arm: nothing queued,
                                                ; and the talker's idle default
                                                ; is what the controller reads
remote_query_freq
                lbsr    remote_record
                leau    ,x                      ; CHAN_FREQ is offset zero, and a
                                                ; SYMBOLIC zero offset is encoded
                                                ; differently by the two
                                                ; assemblers - both correctly
                ldb     #1                      ; tenths of a hertz
                lbsr    format_places_zeros     ; the BUS's rendering: zeros
                lbra    remote_query_9
remote_query_ampl
                ; THE LEVEL AS A CONTROLLER READS IT: eight digits and a point,
                ; no unit, and the point where the DESTINATION puts it.
                ; gpib_query_value_response ($7B7A) renders the record's
                ; 24-bit value with uint24_to_ascii8 ($CA8F) and places the
                ; point through format_with_decimal_point ($CD50), taking the
                ; position from channel_value_decimal_point ($7AE7) - which
                ; reads the destination at record+$21, range-checks 7 to 15
                ; and answers 7 for AM, FM and phi-M, 2 for DSB and the four
                ; outputs, and 8 for Plse and anything outside the range.
                ;
                ; Driven on the stock 2026-09-11, channel B over the bus
                ; ('APB;' then '?'): 5 V on Out1 is '05.000000', 50% on AM
                ; '0000050.0', 90 degrees on phi-M '0000090.0', 5 kHz on FM
                ; '0005000.0', and a Plse channel '00000000' - eight digits
                ; and no point, the point having nowhere to go.
                ;
                ; A RADIAN DEVIATION REPORTS IN DEGREES: 1 rad on phi-M is
                ; '0000057.3'. The stock stores the milliradians and scales
                ; them by 0.5729523 at $7AFF (scale_by_0p5730, $D2A9) before
                ; formatting; this firmware's record already holds the tenths
                ; of a degree, so the same digits come out with nothing to do.
                ;
                ; This queued ampl_text - the SCREEN's rendering, value and
                ; unit label together, '  5.00  V' - which is not what a
                ; controller parses and not what the instrument sends.
                lbsr    remote_record           ; X = the record, B = channel
                pshs    b
                ldb     CHAN_DEST,x
                lbsr    remote_ampl_point       ; A = where the point goes
                sta     >format_point
                pshs    a                       ; 0,s the point, 1,s channel
                lda     CHAN_WAVE,x
                pshs    a                       ; 0,s the waveform
                clr     >format_trim
                leax    CHAN_AMPL,x
                lda     #TEXT_DIGITS            ; eight, every one of them
                clrb                            ; shown: nothing is blanked
                lbsr    format_fixed            ; format_text, nine characters
                lda     1,s
                ldb     #TEXT_DIGITS+1          ; the digits and the point...
                cmpa    #TEXT_DIGITS
                bne     remote_ampl_length
                ldb     #TEXT_DIGITS            ; ...or the digits alone, when
remote_ampl_length                              ; the point falls past them
                lda     ,s
                cmpa    #LBL_DC
                beq     remote_ampl_signed
                leas    3,s
                ldx     #format_text
                lbra    remote_queue

remote_ampl_signed
                ; A dc LEVEL CARRIES ITS SIGN, ALWAYS. The $7B7A cascade
                ; writes the digits at $2286 and the record's sign character
                ; (+$14) at $2285 ahead of them, making the reply ten
                ; characters. Driven on the stock: a dc channel at +2 V is
                ; '+02.000000', at 0 V '+00.000000' and at -2 V '-02.000000';
                ; every other waveform's reply has no sign at all.
                ; ampl_signs is that byte here - '-' or, for anything else,
                ; the '+' the stock's own byte would hold.
                pshs    b                       ; 0,s the length, 1,s the
                ldb     3,s                     ; waveform, 2,s the point and
                                                ; 3,s the channel
                ldx     #ampl_signs
                lda     b,x
                cmpa    #$2D                    ; '-', as its code: asm6809
                beq     remote_ampl_sign_put    ; reads '-' inside quotes as
                lda     #$2B                    ; an operator. '+' likewise
remote_ampl_sign_put
                ldx     #chan_text
                sta     ,x+
                ldu     #format_text
                ldb     ,s
remote_ampl_sign_copy
                lda     ,u+
                sta     ,x+
                decb
                bne     remote_ampl_sign_copy
                puls    b
                incb                            ; and the sign's own column
                leas    3,s
                ldx     #chan_text
                lbra    remote_queue

; ---------------------------------------------------------------------------
; remote_ampl_point - where the point goes in a level reply
;
;   entry: B = the record's destination code
;   exit:  A = the point's index, every other register unchanged
;   uses:  A
;
; channel_value_decimal_point ($7AE7) reads the destination word at
; record+$21, sends anything outside 7..15 to channel_dp_arm_eight ($7B47)
; and dispatches value-7 through the nine-word table at $7B61: arms [0] and
; [1] (values 7 and 8) and gpib_decimal_arm_unit9 ($7AFF) (value 9) answer 7,
; channel_dp_arm_two ($7B40) (values 10 and 12-15) answers 2, and arm [4]
; (value 11, 'Plse') answers 8. That is this routine, once, for the level and
; for the level increment - $7B7A's id-2 and id-7 arms both call $7AE7.
; ---------------------------------------------------------------------------
remote_ampl_point
                cmpb    #LBL_AM                 ; below 7: the guard's own
                blo     remote_ampl_eight       ; out-of-range answer
                cmpb    #LBL_PHIM
                bls     remote_ampl_seven       ; AM, FM and phi-M
                cmpb    #LBL_PULSE
                beq     remote_ampl_eight
                cmpb    #LBL_OUT4
                bhi     remote_ampl_eight       ; Off, past the table's end
remote_ampl_two
                lda     #2                      ; DSB and the four outputs:
                rts                             ; volts, to the microvolt
remote_ampl_seven
                lda     #7                      ; a depth or a deviation, to
                rts                             ; the tenth
remote_ampl_eight
                lda     #TEXT_DIGITS            ; no point at all
                rts

; ---------------------------------------------------------------------------
; remote_query_ampl_incr - four more arms of remote_query_field
;
;   uses:  A, B, X, Y, U
;
; $2215 = 7, 6, 3 and 8, reached from the dispatch at the top of
; remote_query_field and each ending in a queue. One header serves the four
; because they share every register: the formatters below use all of them.
;
; $2215 = 7, THE LEVEL INCREMENT, and it is the level's arm WITHOUT the sign.
; $7B7A's id-7 arm (l7d65) points $3FD1 at [$23BF]+15, takes its point from
; channel_value_decimal_point ($7AE7) exactly as the id-2 arm does, and
; shortens the reply to eight characters when the destination is $0B - but it
; neither writes the record's sign byte to $2285 nor tests the waveform word,
; so the 5,s flag stays clear and the ten-character dc form cannot be reached
; from here. The reply is nine characters, or eight for a 'Plse' channel.
; ---------------------------------------------------------------------------
remote_query_ampl_incr
                lbsr    remote_record           ; X = the record
                ldb     CHAN_DEST,x
                lbsr    remote_ampl_point
                sta     >format_point
                pshs    a                       ; the point, for the length
                clr     >format_trim
                lbsr    remote_incr_ampl_addr
                lda     #TEXT_DIGITS            ; eight, every one of them
                clrb                            ; shown: nothing is blanked
                lbsr    format_fixed
                puls    a
                ldb     #TEXT_DIGITS+1          ; the digits and the point...
                cmpa    #TEXT_DIGITS
                bne     remote_ampl_incr_len
                ldb     #TEXT_DIGITS            ; ...or the digits alone, when
remote_ampl_incr_len                            ; the point falls past them
                ldx     #format_text
                lbra    remote_queue

remote_query_freq_incr
                ; $2215 = 6, THE FREQUENCY INCREMENT. The first cascade of
                ; $7B7A points $3FD1 at [$23BF]+5 for this id where it points
                ; at [$23BF]+0 for id 1, and renders both the same way - eight
                ; digits with the point at 7, nine characters. incr_freq_ch is
                ; that cell here, in tenths of a hertz as the record's own
                ; frequency is, ONE PER CHANNEL as [$23BF]+5 is - this said it
                ; belonged to the screen, and the stock's pointer is the
                ; record's.
                ldb     >current_channel
                andb    #$03
                lda     #3
                mul
                ldu     #incr_freq_ch
                leau    d,u
                ldb     #1
                lbsr    format_places_zeros
                lbra    remote_query_9

remote_query_phase
                ; A PHASE IS SIX CHARACTERS, NOT NINE. $7B7A's second cascade
                ; - ids 3, 8, $0E and $11 - renders a SIXTEEN-bit value with
                ; u16_to_5_ascii_digits ($C912) and puts the point at 4 with
                ; $CD50, then sets the length to 6 at l7caf. The frequency and
                ; the level go out as eight digits and a point; a phase does
                ; not. Driven side by side 2026-09-14, ch A on the Channel
                ; Configuration chain: the stock answers 'PHA;' then '?' with
                ; '0000.0' and this firmware answered '0000000.0' - the right
                ; number in the wrong field width, which a controller reading
                ; fixed-width fields parses as a different number.
                lbsr    remote_record
                ldd     CHAN_PHASE,x
                lbra    remote_reply_tenths
remote_query_phase_incr
                ; $2215 = 8, the phase increment, in the same six characters:
                ; the same cascade, [$23BF]+$1B instead of [$23BF]+$15.
                ; incr_phase is three bytes here where the stock's is two, and
                ; the low word is the whole of it - hop_range_phase and the
                ; panel both hold a phase inside 3599 tenths of a degree.
                ldd     >incr_phase+1
                lbra    remote_reply_tenths

; ---------------------------------------------------------------------------
; remote_reply_tenths - queue a 16-bit value as five digits and a point at 4
;
;   entry: D = the value
;   uses:  A, B, X, Y, U
;
; The second cascade of $7B7A: u16_to_5_ascii_digits ($C912) into $2285, then
; format_with_decimal_point ($CD50) over five digits with the point at index
; 4 and the length set to 6. $CD50 copies a source character for every
; destination column that is not the point's, so five digits with the point
; at 4 come out as four digits, '.', and the fifth - '0359.9' for 3599 tenths
; of a degree, and '0000.0' for nothing at all.
;
; uint24_to_text writes EIGHT digits, so the five are its last five: a phase
; cannot exceed 3599 and a 16-bit value cannot exceed 65535, so nothing is
; lost off the front that the stock's five digits would have kept.
; ---------------------------------------------------------------------------
remote_reply_tenths
                std     >rmt_tmp+1
                clr     >rmt_tmp
                ldx     #rmt_tmp
                lbsr    uint24_to_text          ; eight digits, zeros kept
                ldx     #text_buffer+TEXT_DIGITS-5
                ldu     #chan_text
                ldb     #4                      ; the four before the point
remote_reply_tenths_copy
                lda     ,x+
                sta     ,u+
                decb
                bne     remote_reply_tenths_copy
                lda     #'.'
                sta     ,u+
                lda     ,x                      ; and the tenth after it
                sta     ,u
                ldx     #chan_text
                ldb     #6
                lbra    remote_queue
remote_query_wave
                ; THE CODE, NOT THE NAME. The waveform and the destination are
                ; $2215 = 4 and 5, the fourth cascade of
                ; gpib_query_value_response ($7B7A): it takes [$23BF+$1F] and
                ; [$23BF+$21] - the record's waveform and destination words,
                ; the same record+$21 channel_value_decimal_point ($7AE7)
                ; reads - renders them with u16_to_5_ascii_digits ($C912) and
                ; queues five characters.
                ;
                ; Driven on the stock 2026-09-13, channel A with a dc waveform
                ; and Out2 for a destination: 'WFA?;' answers '00004' and
                ; 'DEA?;' answers '00013', which are LBL_DC and LBL_OUT2 - the
                ; codes themselves, zero-padded. This queued the label TEXT,
                ; 'dc   ' and 'Out2', which is what the glass shows and not
                ; what the instrument sends: a controller parses a number.
                lbsr    remote_record
                ldb     CHAN_WAVE,x
                lbra    remote_reply_5
remote_query_dest
                lbsr    remote_record
                ldb     CHAN_DEST,x
                lbra    remote_reply_5
; remote_query_output WAS HERE, on an RK_OUTPUT arm, and the instrument has
; no such answer. 'OO n' is not a field selector: driven on a two-channel
; stock 2026-09-14 on the Channel Configuration chain, 'OO 1;' leaves $2215
; at $0000 and records $2B in $23DE - 'no field' - and the '?' after it
; answers '? No Data ?' with no error. Nothing in $7B7A reports an output
; state, so there was nothing for this to be a port of.
remote_query_hopfreq
                lbsr    remote_hop_slot
                ldb     #1
                lbsr    format_places_zeros     ; zeros kept, as above
                lbra    remote_query_9
remote_query_hopfreq_incr
                ; $2215 = $0F, the hop FREQUENCY increment. The first cascade
                ; again, with $3FD1 = $2671 - a fixed cell rather than a
                ; record offset, because the hop increments belong to the
                ; screen and not to a slot. Eight digits, point at 7.
                ldu     #incr_hop_freq
                ldb     #1
                lbsr    format_places_zeros
                lbra    remote_query_9
remote_query_hopampl
                lbsr    remote_hop_slot
                leau    HOP_AMPL,u
                ldb     #AMPL_MICRO             ; microvolts, as volts
                lbsr    format_places_zeros     ; zeros kept, as above
                lbra    remote_query_9
remote_query_hopampl_incr
                ; $2215 = $10, the hop LEVEL increment, at $2674. Its arm
                ; (l7d8f) is the third cascade's shortest: it sets $3FD1 and
                ; nothing else, so the point stays at the 2 the routine's
                ; prologue put in 6,s and the length stays 9. No destination
                ; lookup and no sign - a hop level is volts, to the microvolt,
                ; whatever the channel is doing.
                ldu     #incr_hop_ampl
                ldb     #AMPL_MICRO
                lbsr    format_places_zeros
                lbra    remote_query_9
remote_query_hopaddr
                ; $2215 = $12, THE HOP RAM ADDRESS STOP, and it is the only
                ; three-character reply on the chain. l7e64 reads $24F4, takes
                ; `COMB / ANDB #$0F` of it and renders that with
                ; format_three_digits ($C9D1), length 3. hop_index is $24F4
                ; here - hop_addr_put stores the same four-bit complement -
                ; so the number the controller reads is the number on the
                ; glass. Driven on the stock 2026-09-14: 'HRA;' then '?' on a
                ; fresh Hop Ram screen answers '000', the screen reading
                ; 'Hop Ram Adrs  0' with $24F4 = $0F.
                ldb     >hop_index
                comb
                andb    #HOP_SLOTS-1
                lbra    remote_reply_3
remote_query_hopphase_incr
                ; $2215 = $11, the hop PHASE increment, at $267D - the second
                ; cascade, so five digits and a point at 4, six characters.
                ; incr_hop_phase is in tenths of a degree and carries no
                ; radian flag: hop_incr_begin stores what the unit key
                ; converted, and the flag belongs to a SLOT's stored word.
                ldd     >incr_hop_phase+1
                lbra    remote_reply_tenths
remote_query_hopphase
                lbsr    remote_hop_slot
                ldd     HOP_PHASE,u

                ; IN DEGREES, WHATEVER THE SLOT HOLDS. HOP_PHASE_RAD in the
                ; top bit says the word is thousandths of a radian, which is
                ; what a panel entry in radians stores
                ; (common/formats.inc); the bus answers this query in tenths
                ; of a degree with one place, so a radian slot is converted
                ; the way hop_program converts it.
                bita    #HOP_PHASE_RAD_HI
                beq     remote_hopphase_deg
                anda    #HOP_PHASE_VALUE_HI
                std     >chan_work+1
                clr     >chan_work

                ; AND IT SAYS WHAT THE STORED VALUE CARRIES, exactly as
                ; hop_program does. unit_apply's radian arm scales the digits
                ; by RAD_DECADES LESS entry_frac before converting, and
                ; entry_frac belongs to the panel's entry layer - it is
                ; whatever the last thing keyed left in it, and a bus query has
                ; nothing to do with an entry. With entry_frac at 0, which is
                ; what scratch_reset leaves, a slot holding the legal maximum
                ; of 6282 milliradians was scaled a thousandfold to 6,282,000;
                ; unit_apply then refused it as past 24 bits, recorded
                ; ERR_VALUE_TOO_BIG for a fault that never happened, and left
                ; the buffer holding $5FD650 - so the controller was answered
                ; 5486.4 where the right answer is 359.9, with no error sent.
                ; The carry is tested here as well: with the fraction declared
                ; it cannot be set for a slot inside CHAN_RAD_MAX, and a slot
                ; that is not is a corrupt one, which the bus is told about
                ; rather than answered from.
                lda     >entry_frac
                pshs    a
                lda     #RAD_DECADES
                sta     >entry_frac
                ldx     #chan_work
                ldb     #UNIT_RAD
                lbsr    ABI_unit_apply          ; milliradians to tenths, in
                puls    a                       ; place
                sta     >entry_frac
                bcs     remote_hopphase_bad
                ldd     >chan_work+1
remote_hopphase_deg
                ; AND SIX CHARACTERS, for the reason remote_query_phase gives:
                ; $2215 = $0E is the second cascade's third arm (l7c4c), which
                ; renders the slot's sixteen-bit word with $C912 and sets the
                ; length to 6. This queued nine through remote_query_9, and
                ; with the leading zeros BLANKED - format_places rather than
                ; format_places_zeros - which no bus reply does.
                lbra    remote_reply_tenths
remote_query_9
                ldx     #chan_text
                ldb     #AMPL_TEXT_W
                lbra    remote_queue
; remote_query_none was here, and it went with the label lookup above: it was
; the RTS the waveform and destination arms took when label_find refused a code
; it had no name for. Those arms answer with the code itself now, which needs
; no name and cannot fail, so nothing reaches it - and a routine kept for a
; caller a fix removed is dead weight, which
; hp8904a-rewrite/tests/test_reachable.py finds.
remote_hopphase_bad
                ; A SLOT THAT WILL NOT CONVERT IS REPORTED, NOT ANSWERED. With
                ; the fraction declared above, unit_apply can only refuse a
                ; word past CHAN_RAD_MAX - which hop_range_phase and the bus's
                ; own TOP_PHASE both refuse on the way in, so it means the slot
                ; has been corrupted. Sending a number for it would be worse
                ; than sending the fault.
                ldb     #ERR_VALUE_RANGE
                lbra    remote_error

; remote_hop_slot - U = the hop slot the screen is on
; remote_hop_slot - U = the hop slot the Hop screen is on
;   uses:  A, B, U
remote_hop_slot
                ldb     >hop_index
                andb    #HOP_SLOTS-1
                lda     #HOP_ENTRY_SIZE
                mul
                ldu     #hop_table
                leau    d,u
                rts

; ===========================================================================
; The two bus screens: the address and the service-request-enable mask.
; The stock reaches them as message codes 2 and $0E (arms [1] and [13] of
; its $8F2A table; key 39 posts the first). Here they are Service menu
; entries and bus commands alike, built on the shared numeric screen the
; Output On/Off screen uses: screen_numeric_key echoes the digits, ENTER
; runs screen_commit.
; ===========================================================================
remote_address_open
                ldx     #remote_address_commit
                ldy     #remote_address_title
                ldb     #2                      ; two digits: 0 to 30
                bra     remote_screen_open
remote_sre_open
                ldx     #remote_sre_commit
                ldy     #remote_sre_title
                ldb     #3                      ; three digits: 0 to 255
remote_screen_open
                pshs    b,x,y                   ; 0,s = B, 1,s = X, 3,s = Y
                ldx     #screen_numeric_key
                lbsr    screen_install
                ldx     1,s
                stx     >screen_commit
                ldx     #$0000
                stx     >screen_f1
                ldx     #service_back_handler   ; f4 LEAVES. Every screen
                stx     >screen_f4              ; built on screen_numeric_key
                                                ; needs one: the handler takes
                                                ; digits, BACKSPACE, ENTER, f1
                                                ; and f2 and ignores the rest,
                                                ; so without this the screen
                                                ; cannot be left from the
                                                ; keypad at all.
                lda     #RMT_FIELD_POS
                sta     >screen_field_pos
                lda     ,s
                sta     >screen_field_width
                lbsr    lcd_clear
                ldx     3,s                     ; ARMED BEFORE THE WRITE:
                pshs    x                       ; banner_arm uses A and B, and
                lbsr    banner_arm              ; these screens' titles are
                puls    x                       ; ours, so their stars walk
                lda     #SCREEN_LINE1            ; like the menus'
                ldb     #LCD_COLUMNS
                lbsr    lcd_write
                lda     #SCREEN_LINE2
                ldx     #remote_screen_prompt
                ldb     #LCD_COLUMNS
                lbsr    lcd_write
                lda     #ENTRY_DECIMAL
                puls    b,x,y
                lbsr    entry_begin
                lbsr    remote_screen_show
                lbra    screen_field_arm        ; $A227: armed as it opens

RMT_FIELD_POS   equ     SCREEN_LINE2+26 ; clear of 'now =' at 31
RMT_VALUE_POS   equ     SCREEN_LINE2+36

; remote_screen_show - the current value, right of the prompt
remote_screen_show
                ldx     >screen_commit
                cmpx    #remote_address_commit
                bne     remote_screen_show_bl
                ldb     >remote_address
                bra     remote_screen_show_3
remote_screen_show_bl
                cmpx    #backlight_secs_commit  ; THE THIRD SCREEN BUILT ON
                bne     remote_screen_show_sre  ; this one: the backlight's
                clr     >rmt_tmp                ; timeout, which is two bytes
                ldx     >backlight_secs         ; where the other two are one
                stx     >rmt_tmp+1
                bra     remote_screen_show_put
remote_screen_show_sre
                ldb     >remote_sre_mask
remote_screen_show_3
                clr     >rmt_tmp
                clr     >rmt_tmp+1
                stb     >rmt_tmp+2
remote_screen_show_put
                ldx     #rmt_tmp
                lbsr    uint24_to_text
                lda     #RMT_VALUE_POS
                ldx     #text_buffer+5
                ldb     #3
                lbra    lcd_write

remote_address_commit
                lbsr    entry_value
                bcs     remote_screen_bad
                lda     >entry_result
                ora     >entry_result+1
                bne     remote_screen_bad
                ldb     >entry_result+2
                cmpb    #30                     ; 0-30 are valid, the stock's
                bhi     remote_screen_bad       ; CMPB #$1E at $A0D4
                stb     >remote_address
                lbsr    remote_init             ; the chip learns it now, as
                bra     remote_screen_show      ; gpib_reset does after the
                                                ; store
remote_sre_commit
                lbsr    entry_value
                bcs     remote_screen_bad
                lda     >entry_result
                ora     >entry_result+1
                bne     remote_screen_bad
                ldb     >entry_result+2
                stb     >remote_sre_mask        ; any byte; bit 6 (RQS) is
                bra     remote_screen_show      ; ignored by the assert path
remote_screen_bad
                ldb     #ERR_VALUE_RANGE
                lbra    error_raise

remote_address_title  fcc "*****      BUS ADDRESS  0-30       *****"
remote_sre_title      fcc "*****  SERVICE REQUEST MASK 0-255  *****"
remote_screen_prompt  fcc "Type the value, ENTER          now =    "
