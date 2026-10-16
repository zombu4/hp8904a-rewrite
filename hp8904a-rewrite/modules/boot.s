; ===========================================================================
; boot.s - reset, the interrupt handlers, and the foreground loop
;
; What happens when the instrument is switched on, in the order it happens
; and for reasons that are stated rather than inherited.
;
; THE ORDER MATTERS AND IS NOT ARBITRARY:
;
;   1. a stack, before anything can call anything
;   2. interrupts masked, before any handler can fire into hardware that has
;      not been programmed yet
;   3. the peripherals, in dependency order: the timer first, because the
;      display driver waits on it
;   4. the battery-backed RAM CHECKED and never modified - the serial number
;      and the options live in there, and this is the one moment where a
;      mistake destroys them silently
;   5. both interrupts MASKED, and left masked - the keypad is polled and the
;      tick is polled, because the FIRQ source cannot be acknowledged by
;      anything establishable from the stock firmware. This line used to read
;      "interrupts enabled, last", which the code at that step contradicts
;      six lines from its own comment saying the same thing as the code.
;
; The stock firmware does the same steps in a different order: it runs its RAM
; signature check FIRST, with IRQ and FIRQ still unmasked, and only masks them
; afterwards. That works because its handlers happen not to touch what the
; check reads, which is a property of the code rather than of the design.
; ===========================================================================

; THE STACK IS 452 BYTES AND THERE IS NO FLOOR, BECAUSE THAT IS THE MAP THE
; INSTRUMENT HAS.
;
; The stock does `LDS #$21FF` at $7D5F and keeps its scratch at $2600, so on a
; real 8904A everything from the top of the trust signature to the stack top -
; $203C-$21FF - is stack and nothing else. It never tests how deep the stack
; is: `grep -c cmps firmware/a2u12.asm firmware/src-generated/a2u13_page*.s`
; returns 0 in every one of the five images.
;
; THIS FIRMWARE HAD TWO FLOORS AND 102 BYTES. NMI_STACK_FLOOR ($21B0) made
; nmi_sequence silence every timer interrupt rather than push another frame,
; and STACK_FLOOR ($21AC) made the foreground reset S and reopen the top menu.
; Both existed only because five things had been declared in the stack's own
; 452 bytes - register_seq_block at $203C (257), the migration bytes at $213D
; (8), lcd_shadow at $2145 (80) and lcd_hold, main_menu_page, entry_dot,
; entry_frac and entry_armed at $2195-$2199 - leaving the stack 102.
;
; WHAT THE FLOOR COST, measured rather than argued, in
; docs/stack-depth-question.md: an ordinary warm boot, Channel Configuration,
; four channels routed, hop registers loaded, `SV 3;` then `RC 3;` over the
; bus took S to $21BE, ONE BYTE above NMI_STACK_FLOOR. Past it a tone or
; digital sequence stops dead with the screen still saying it is running and
; nothing re-arms the timer. Twenty bytes further and the twelve-byte frame
; the CPU pushes - before any handler exists, so no software floor can stop
; it - lands on entry_frac, whose value unit_scale_decades subtracts from a
; unit's decades, so a typed entry commits scaled by the wrong power of ten
; with nothing on the screen to say so.
;
; The architect chose the map over the floor, 2026-09-14, in his
; words: "Option 1 - put the map back the way the instrument
; has it ... The floor is this firmware's invention and the stock has no such
; thing." So all five cells moved out of $203C-$21FF, both floors are deleted,
; and the two `cmps` instructions that reached them went with them. The
; instrument's own worst case now has 452 bytes to fit in where it had 102,
; and hp8904a-rewrite/tests/test_stack_depth.py counts the deepest chain that
; exists against that, every run.
;
; nmi_silence STAYED, and it is not part of the invention. Two callers that
; have nothing to do with depth reach it: nmi_handler when no callback is
; armed, and nmi_tick_idle when no sequence is installed.
; It is a PORT - the stock's own nmi_handler at $DC3D does exactly this when
; bit 7 of event_flags2 is clear, clearing bit 6 of ptm_cr1_shadow,
; ptm_cr3_shadow and ptm_cr2_shadow and writing all three - and an interrupt
; returned to with its source still asserting is how an instrument locks up
; with a dead front panel.
STACK_TOP       equ     $21FF           ; the stack grows down from here,
                                        ; clear of the scratch, which is at
                                        ; $3A80 - this said $2600, which is
                                        ; where scratch used to be before it
                                        ; moved out of the save/recall array -
                                        ; and far clear of $3FFC
STACK_BOTTOM    equ     $203C           ; and down to here: the first byte
                                        ; above the trust signature that rule
                                        ; 2 reserves at $2000-$203B. 452 bytes.
                                        ; Nothing may be declared between this
                                        ; and STACK_TOP - the layout gate
                                        ; hp8904a-rewrite/tests/test_scratch_layout.py
                                        ; refuses the RAM map if anything is,
                                        ; and
                                        ; hp8904a-rewrite/modules/service_memmap.s
                                        ; refuses an operator write below it.

BOOT_SEQ_FRAME  equ     REGISTER_SEQBLOCK+ST_SAVED_WIDE+ST_SAVED_NARROW
                                        ; the live sequence and FM Stereo's
                                        ; nineteen parameters, carried through
                                        ; the boot's two scratch clears - see
                                        ; reset_entry
BOOT_CHANNELS   equ     BOOT_SEQ_FRAME  ; and the channel count, probed before
                                        ; both clears as the stock probes it,
                                        ; installed after them
BOOT_FRAME      equ     BOOT_CHANNELS+1 ; the whole frame
BOOT_SETTLE_MS  equ     250             ; the stock's delay_ms($00FA) at
                                        ; $8338, after the outputs are set up
                                        ; and before it looks at the installed
                                        ; count
LAMP_TEST_MS    equ     300             ; how long every indicator stays lit
                                        ; at power-on. The stock's
                                        ; delay_ms($012C) at $82A4, between
                                        ; status_leds_all_on ($9A7D) and
                                        ; lamp_test_off ($9A76).

; ---------------------------------------------------------------------------
; reset_entry - where the CPU arrives out of reset
;
; Never returns. If the foreground ever falls out of its loop, that is a bug
; and this stops rather than running into whatever follows.
; ---------------------------------------------------------------------------
reset_entry
                lds     #STACK_TOP              ; before any call
                MASK_IRQ                        ; before any handler can fire
                MASK_FIRQ

                ; THE SEQUENCE THE INSTRUMENT WAS HOLDING, CARRIED THROUGH THE
                ; TWO CLEARS BELOW. The instrument keeps its sequence block in
                ; battery RAM and a keep-state power-on re-enters the active
                ; mode on it: measured on the stock 2026-09-16, a Tone
                ; Sequence with a marker poked into tone 0's frequency came
                ; back reading that marker, not reseeded
                ; (docs/mode-reentry.md). This firmware keeps its sequence
                ; models in scratch, which scratch_reset clears here and
                ; selftest_ram walks and clears again, so on a keep-state
                ; power-on there would be nothing to re-enter on.
                ;
                ; So before anything runs, the live sequence goes onto the
                ; stack - the one battery RAM neither clear touches - exactly
                ; as a register save stages it, end, cursor and running state
                ; included (register_seq_stage). boot_keep_state puts it back
                ; once the battery signature has been believed; every other
                ; path just drops the frame. Nothing here is trusted yet and
                ; nothing needs to be: the copy is a fixed length between
                ; fixed addresses whatever seq_kind_live holds, and
                ; SEQKIND_NONE or any foreign value stages one byte.
                leas    -BOOT_FRAME,s
                leax    ,s
                lbsr    register_seq_stage
                ; AND FM STEREO'S NINETEEN PARAMETERS behind it, contiguous
                ; from st_tone in scratch: HP's $42D2 re-enters on argument 2
                ; with its live block as the battery kept it, and this
                ; firmware's is scratch too.
                leax    REGISTER_SEQBLOCK,s
                ldu     #st_tone
                ldb     #ST_SAVED_WIDE+ST_SAVED_NARROW
                lbsr    register_seq_copy

                ; THE PANEL PORTS BEFORE ANYTHING ELSE TOUCHES HARDWARE, as
                ; power_on_init calls reset_panel_ports ($D524) at $8225 ahead
                ; of its timer and its probe. $0900 and $0600 are latches and
                ; power up holding whatever they hold; the stock sets both
                ; before it probes the output boards, and this firmware
                ; probed with both still at their power-up state.
                lbsr    panel_ports_reset
                lbsr    ptm_init                ; the timer first: the
                                                ; display driver waits on it

                ; THE PROBE, WHERE THE STOCK PROBES: power_on_init ($81AD)
                ; calls count_installed_channels at $8252, straight after
                ; reset_panel_ports, the timer and the page select and before
                ; any latch has been written, and output_latches_preset84 at
                ; $8259 straight after it - before the lamps, lcd_init and the
                ; memory self-test. This firmware used to preset first and
                ; probe hundreds of lines later, after both scratch clears.
                ;
                ; SO EACH PROBE WRITE CARRIES THE BATTERY SHADOW, as the
                ; stock's does: port_latch_rmw ($DBA1) ORs bit 7 into the
                ; shadow at $24F0+n, which holds whatever the instrument was
                ; last doing, and channel_latch_rmw ORs it into latch_shadow,
                ; which holds the same thing here. Nothing is trusted from it;
                ; bit 7 is the only bit the probe sets, and every latch is
                ; muted two instructions after it returns.
                ;
                ; THE COUNT CANNOT STAY IN installed_channels, which is in
                ; scratch: scratch_reset below clears it and selftest_ram
                ; walks it and clears it again. It rides the boot frame, the
                ; one battery RAM neither clear touches, and is installed
                ; where the probe used to run.
                ; THE FIRST POWER-ON TONE, where the stock sounds it:
                ; power_on_init calls ptm_t1_output_pulse ($D6C8) at $8239,
                ; after ptm_timer_init and before count_installed_channels at
                ; $8252 - a hundred milliseconds of timer 1's output, gated on
                ; bit 2 of $23C1 as error_beep is gated on special function 2.
                ; The stock reads that bit from battery RAM it has not yet
                ; checked, and so does this; it decides a tone and nothing
                ; else. This firmware had dropped the tone, and with it the
                ; hundred milliseconds the stock spends between starting its
                ; timer and probing the output boards.
                lbsr    error_beep
                lbsr    channel_probe           ; B = boards fitted
                stb     BOOT_CHANNELS,s
                lbsr    channel_latches_preset  ; and every output OFF, as
                                                ; $8259 does

                ; THE LAMP TEST OPENS HERE. $0900 is write-only, so the shadow
                ; is the only readable copy of what the six indicators are
                ; doing and it has to be established rather than assumed -
                ; led_init stores $3F to both, which is the stock's
                ; status_leds_all_off ($9A37). Then every lamp comes on.
                ;
                ; NOTHING IN THIS FIRMWARE LIT A LAMP AT ALL before
                ; modules/panel_leds.s was written: `grep -rn status_led
                ; modules/*.s` returned two hits, both comments in
                ; common/hardware.inc. Every indicator held whatever the
                ; previous firmware left in it, for the life of the
                ; instrument.
                ;
                ; power_on_init ($81AD) brackets exactly this stretch: it
                ; lights them at $8296, runs lcd_init ($D9E6) and
                ; power_on_memory_selftest, waits 300 ms and puts them out at
                ; $82AD. An operator watching the front panel sees every
                ; indicator come up and go out, which is how a dead lamp is
                ; found - so the delay is the point of it and not padding.
                lbsr    led_init
                lbsr    led_all_on

                lbsr    lcd_init
                lbsr    lcd_define_all          ; the phi and mu the labels use;
                                                ; a screen painted before these
                                                ; are loaded shows undefined
                                                ; CGRAM
                ; EVERY SCRATCH VARIABLE THAT IS AN INDEX MUST BE CLEARED
                ; HERE. Scratch lives in battery-backed RAM - there is no
                ; other RAM on this board - so nothing in it is zero at
                ; power-on, it holds whatever the last firmware left.
                ;
                ; nav_top is the one that mattered: it indexes a four-entry
                ; stack with five bytes per entry, and an uncleared byte of
                ; $8A put the write on the serial number. It is clamped in
                ; nav_push as well; this is the other half.
                lbsr    nav_reset
                lbsr    scratch_reset

                ; THE SAVED SETUPS, BEFORE ANYTHING READS ONE. The array moved
                ; down and grew a span, so a slot written by the previous
                ; format is at the wrong address and the wrong shape.
                ; register_migrate converts them in place and stamps the
                ; format; it is a no-op once that stamp is set, and a no-op
                ; again on a slot already carrying the current marker.
                ;
                ; It has to run AFTER scratch_reset, because the stamp lives
                ; outside scratch on purpose but tone_end does not - and
                ; BEFORE the keep-state restore below, which recalls a slot.
                ; IS THERE A BANK? Asked here, before the migration, because
                ; the migration works on whichever store is the authority and
                ; the answer decides which that is.
                ;
                ; The probe is one write and one read-back: $34 to page_select,
                ; and byte 0 of the window must come back $34. A One ROM with
                ; the fifth bank answers; a genuine 27513 selects page 0 and
                ; answers $30; a One ROM carrying only four pages answers
                ; nothing. Every one of those is "no bank" except the first,
                ; and none of them needs a test of its own.
                ;
                ; NOTHING DOWNSTREAM MAY ASSUME IT SUCCEEDED. bank_present is
                ; the flag every wrapped accessor reads, and with it clear they
                ; are their old selves working out of the HM6264 - which is
                ; what an instrument with the original part in the socket has
                ; always done.
                lbsr    bank_probe

                lbsr    register_migrate

                ; AND THEN THE ONE VALUE WHOSE ZERO IS A LIE. current_page is
                ; inside the span scratch_reset clears, so it came out of the
                ; power-on path holding 0 - and nothing here writes
                ; page_select, so no page has been chosen and the window holds
                ; whatever the hardware powers up with. page_current then
                ; reported that as "page 0 is mapped", and the Memory Map
                ; screen painted the digit. $FF is the value paging.s already
                ; defines for "unknown", and it is the truth until a page is
                ; selected.
                lda     #PAGE_UNKNOWN
                sta     >current_page

                ; THE OUTPUTS STAY OFF THROUGH THE SELF-TEST. They went off
                ; right after the probe, above, and power_on_init does not
                ; release the relays until reset_all_channel_outputs much
                ; later - measured, 641,450 instructions with them held open.
                ; This firmware once wrote its first latch value and released
                ; it 7,500 instructions later, which is why the architect heard
                ; no clicks: the relay is told to open and told to close again
                ; before the armature has moved.

                lbsr    selftest_run            ; check before trusting
                stb     >selftest_result

                ldd     #LAMP_TEST_MS           ; AND THE LAMP TEST CLOSES.
                lbsr    delay_ms                ; The stock's delay_ms($012C)
                                                ; at $82A4, then lamp_test_off
                                                ; ($9A76) - which ORs $3F
                                                ; rather than storing it, so
                                                ; bits 7:6 keep whatever they
                                                ; held. led_all_off is the OR
                                                ; one for that reason.
                lbsr    led_all_off

                ; AND THE DISPLAY SHADOW, here rather than earlier. It lives
                ; below live_setting, which is the span scratch_reset clears,
                ; and scratch_reset runs TWICE on this path: once above, and
                ; again inside selftest_ram, which has to put scratch back
                ; after walking it. An init before the self-test is wiped by
                ; the self-test. Third time this trap has caught something -
                ; tick_armed, the backlight timeout, and now this.
                ;
                ; It matters more than a shadow usually would: a zeroed shadow
                ; made lcd_control_clear write $08, which is DISPLAY OFF, and
                ; the first screen change blanked the panel.
                lbsr    lcd_control_init

                ; AND THE HOP RAM'S STANDING SLOT, whose zero is a lie in the
                ; same way. The Hop Ram screen's Adrs field shows FIFTEEN MINUS
                ; the slot - driven on the stock, typing 3 leaves $24F4 = $0C
                ; and writes register $15 = $0C, and its three value painters
                ; index the record array with that raw $24F4 - so a cold $24F4
                ; of $0F is the address 0 the instrument shows on a fresh boot.
                ; scratch_reset leaves hop_index at zero, which put 15 on the
                ; glass. After the self-test, like the shadow above: the
                ; reset inside selftest_ram wipes anything set before it.
                lda     #HOP_SLOTS-1
                sta     >hop_index

                ; THE BUS ADDRESS AND THE SERVICE-REQUEST MASK, on a board
                ; whose battery-backed RAM cannot be believed. Both cells live
                ; at the stock's own battery-backed addresses, so on a trusted
                ; boot they carry what the operator last set and nothing here
                ; may touch them - but on an untrusted one they are foreign
                ; bytes, and a mask of zero is an instrument that can never
                ; request service for anything. That is what this firmware
                ; shipped: remote_sre_mask had exactly one writer, the Bus SRQ
                ; Mask service screen, so a battery-fresh instrument answered
                ; every bus error with a status bit and no SRQ, and a
                ; controller waiting on the line waited for ever.
                ;
                ; THE STOCK SEEDS THEM AND THIS IS ITS BRANCH. power_on_reinit
                ; ($C2C4) does LDB #$1A / STB >$227F then LDB #$13 / STB
                ; >$227E, and power_on_init reaches it from its one call site
                ; $82B2 only when $23DD is non-zero - the byte
                ; ram_signature_check ($C36E) clears, then sets to $02 when
                ; RAM $2000-$2035 does not match the ROM reference at $EC85,
                ; then increments when the six revision bytes $2036-$203B do
                ; not match $ECBB. That is the same question SELFTEST_SIG
                ; answers here.
                ;
                ; AND BEFORE remote_init, because the stock runs
                ; power_on_reinit first and gpib_reset ($9D34) afterwards, in
                ; that order inside power_on_init: the chip is programmed FROM
                ; these two cells, not the other way about. gpib_driver_init
                ; ($9AE2) pushes them into the record gpib_chip_init ($8F9F)
                ; reads, and that routine does LDD 2,U / ANDA #$BF / ANDB
                ; #$BF / STD >$2248, which puts $227E AND $BF into the live
                ; mask $2249 that gpib_assert_service_request ($91E2)
                ; bit-tests ($91FE LDA >$2249 / $9201 BITA ,X) before it sets
                ; rsv. Seeding after remote_init would leave the chip holding
                ; the old address for the rest of the session.
                ;
                ; $13 is bits 0, 1 and 4 - the general error bit, the
                ; reference-loop bit and the reverse-power bit. See
                ; remote_event for what each one is and where the stock
                ; raises it.
                lda     >selftest_result
                bita    #SELFTEST_SIG
                bne     boot_bus_defaults_kept
                lda     #BUS_ADDRESS_DEFAULT
                sta     >remote_address
                lda     #BUS_SRE_DEFAULT
                sta     >remote_sre_mask
boot_bus_defaults_kept

                lbsr    remote_init             ; the bus interface, after the
                                                ; LAST scratch_reset: the
                                                ; parser's state lives in
                                                ; scratch and a reset after
                                                ; init would wipe it, the same
                                                ; ordering lcd_control_init
                                                ; and backlight_wake needed
                lbsr    backlight_wake          ; the backlight ON and its
                                                ; three minutes started, which
                                                ; is bit 6 asserted plus the
                                                ; timeout the stock runs from
                                                ; the first keystroke onward.
                                                ;
                                                ; AFTER scratch_reset, not
                                                ; before it: backlight_s is
                                                ; inside the span that clears,
                                                ; so waking the backlight
                                                ; first left the timeout at
                                                ; zero and the lamp lit for
                                                ; ever. Caught by the gate.

                lbsr    boot_report_faults      ; and say so if any of the
                                                ; three checks failed

                ; THE BATTERY-BACKED DATA IS ONLY BELIEVABLE IF THE SIGNATURE
                ; MATCHED. special_flags lives in live_globals, which is in
                ; that RAM, and nothing anywhere initialised it - so on a
                ; board carrying another firmware's bytes, SPECIAL_KEEP_STATE
                ; could read as set and the "every channel starts silent"
                ; guarantee three paragraphs below would simply not hold.
                ;
                ; So: if the signature did not match, the preferences are not
                ; preferences, they are noise. Clear them - which selects the
                ; safe default, records initialised and outputs silent - and
                ; write the signature, so the instrument is trusted from now
                ; on instead of failing this check forever.
                ;
                ; THE VERDICT IS READ BACK FROM WHERE IT WAS STORED. This
                ; tested B, and B was never the verdict here: since
                ; boot_report_faults was put in front of this it has held that
                ; routine's fault count - zero on a healthy board, so every
                ; power-on took the untrusted branch, cleared the preferences
                ; and made keep-state impossible - and before that it held the
                ; low byte of LAMP_TEST_MS, $2C, whose bit 2 believed every
                ; board. Measured 2026-09-16: selftest_result $0F after a
                ; reboot, and special_flags read $00 with the keep-state bit
                ; set before the power cycle.
                ldb     >selftest_result
                bitb    #SELFTEST_SIG
                bne     boot_ram_trusted
                clr     >special_flags
                clr     >filter_mode            ; THE OTHER GLOBALS IN THE SAME
                clr     >filter_mode+1
                clr     >filter_mode+2
                clr     >filter_mode+3
                                                ; BLOCK. live_globals is
                                                ; battery-backed, so on a boot
                                                ; whose signature matches these
                                                ; hold the last session's
                                                ; choices, which is the point
                                                ; - but on the path where the
                                                ; signature did NOT match they
                                                ; are foreign bytes, and
                                                ; special_flags was cleared
                                                ; here while the filter modes,
                                                ; read by the filter screen,
                                                ; was not.
                clr     >active_mode            ; AND THE ACTIVE MODE AND ITS
                clr     >active_mode+1          ; RECORD, for the same reason:
                clr     >active_record          ; a save would carry them and
                                                ; a keep-state boot read them
                lbsr    selftest_signature_write
boot_ram_trusted

                ; THE NMI CALLBACK, before anything can arm the timer. The
                ; handler JUMPS through this pointer whenever the arm bit is
                ; set, so it gets a live target here, before the bit: the idle
                ; callback, which silences the timers. nmi_callback is battery
                ; RAM like the rest of this board's, so it is written before
                ; this store sets the bit rather than trusted. From here on it
                ; is written
                ; only by tick_install, tick_remove, tick_hold and
                ; tick_arm_update, each with one STX.
                ldx     #nmi_tick_idle
                stx     >nmi_callback
                lda     >event_flags
                ora     #NMI_CALLBACK_ARMED
                sta     >event_flags

                ; THE CHIP RESET IS NOT HERE ANY MORE, and it was. This
                ; called dds_reset before the probe, and instrument_preset
                ; calls it again further down the cold branch - so a cold
                ; start flushed the chip twice, which IS the instrument's
                ; count, out of two routines instead of one. That hid the
                ; other half of the same fault: dds_reset was doing one flush
                ; where dds_params_reset ($DF17) does two, and nothing showed
                ; it because there were two calls.
                ;
                ; power_on_init ($81AD) writes no chip register of its own.
                ; Its first DDS write comes from instrument_preset ($C6EA),
                ; which it reaches on BOTH arms of the keep-state test at
                ; $82BA - through reset_all_channel_outputs ($80F3) at $8108
                ; on the cold one and directly at $82CE on the other.
                ; Measured on the emulator with four channels fitted, by
                ; counting entries to each routine during the boot:
                ; instrument_preset once, dds_params_reset once,
                ; dds_write_all_registers twice.
                ;
                ; So the reset happens where the instrument does it, and this
                ; branch does the latch work alone.
                ;
                ; THE SHADOW IS PUT RIGHT HERE. The probe at the top of
                ; reset_entry wrote the battery shadow, bit 7 added, to every
                ; latch - as the stock's does - and scratch_reset has since
                ; cleared that shadow to zero, which is not what the latches
                ; hold. channel_latch_init writes the preset to both, so the
                ; two agree again before anything reads the shadow.
                ;
                ; channel.s says this routine has to run at power-on. It was
                ; not in the reset path at all.
                lbsr    channel_latch_init
                ldb     BOOT_CHANNELS,s         ; how many boards are FITTED,
                stb     >installed_channels     ; as the probe found them at
                                                ; the top of reset_entry,
                ; The live state lives in battery-backed RAM, so it survives
                ; being switched off. Special function 0 says whether to keep
                ; it: with the bit set the instrument comes back exactly as
                ; it was left, and with it clear every channel starts silent.
                ;
                ; CLEAR IS THE DEFAULT AND THE SAFE ONE. An instrument that
                ; powers up producing whatever it was producing last week can
                ; put a signal into something nobody expected; one that
                ; powers up silent cannot. An operator who wants the other
                ; behaviour asks for it by name on the Special Functions
                ; screen.
                ;
                ; The preference is itself part of the saved state, so it
                ; survives too - which is the only way this can work at all.
                lda     >special_flags
                bita    #SPECIAL_KEEP_STATE
                lbne    boot_keep_state
                leas    BOOT_FRAME,s        ; a cold power-on carries
                                                ; nothing: the staged
                                                ; sequence is dropped
                lbsr    channel_records_init    ; before anything paints a
                                                ; screen from them
                clr     >hop_saved_flags        ; AND NO HOP FUNCTION COMES
                clr     >hop_saved_flags+1      ; BACK ON. The stock's cold
                                                ; entry - argument 0 to
                                                ; enter_channel_config_mode
                                                ; ($528F), which its $5301
                                                ; LBEQ l53f7 sends past the
                                                ; re-apply - ends at l54bf
                                                ; by snapshotting the live
                                                ; $2204/$2202 into
                                                ; $267F/$2681, and
                                                ; power_on_init ($81AD) has
                                                ; zeroed both words, so the
                                                ; snapshot a cold boot
                                                ; leaves is all off. The
                                                ; keep-state branch keeps
                                                ; it, and register_apply's
                                                ; tail re-applies from it
                                                ; (register_hop_reapply)
                ; AND EVERY DESTINATION IS TAKEN OUT OF THE RECORD AND
                ; KEPT, which is what holds the DACs at zero until the
                ; operator asks for something. The stock's
                ; reapply_all_channels ($C5B1) saves each record's
                ; destination into $24DE at $C5E8 and writes $0010 - the code
                ; this firmware calls LBL_OFF - over it at $C5EF, and
                ; channel_apply_and_propagate ($BE5C) then sees $0010 at
                ; $BE82, programs the channel's level register with ZERO at
                ; $BE97 and returns before output_latch_level_set, leaving
                ; the latch's range field alone.
                ;
                ; So a cold instrument's screen says 140 uV and its DACs hold
                ; nothing. This firmware applied the record as it stood and
                ; drove 140 uV worth of code into all four channels from the
                ; first instruction - a difference the differential harness
                ; found, and one that decides whether a cold-started
                ; instrument's sockets are live.
                ;
                ; enter_channel_config_mode ($528F) puts them back at
                ; $5404-$543D, which is channel_config_open here.
                lbsr    channel_park_destinations
                lbsr    channel_reset_all       ; AND THE OUTPUTS THEMSELVES.
                                                ; This is the cold branch, and
                                                ; the stock's cold branch is
                                                ; exactly this: power_on_init
                                                ; ($81AD) restores the four
                                                ; latch shadows from
                                                ; $2206-$2209 when bit 0 of
                                                ; $23C1 is set, and otherwise
                                                ; calls
                                                ; reset_all_channel_outputs
                                                ; ($80F3). The keep-state
                                                ; branch below is the restore;
                                                ; this is the reset, and it was
                                                ; missing.

                ; AND THE HOP TABLE, WHICH REACHED THE CHIP AT NO POINT OF A
                ; COLD START. reinit_channel_tables ($C6C3) calls
                ; dds_table_defaults ($E7F9) FIRST of its three, and $E7F9's
                ; tail is dds_reload_all_slots ($E799): sixteen calls to
                ; dds_write_channel ($DE2E), one per slot, eleven words each.
                ; That is 176 of the instrument's 393 cold-start DDS words and
                ; this firmware wrote none of them - hop_table_defaults was
                ; reached only by entering Channel Configuration, so from
                ; power-on until an operator opened that screen the chip's own
                ; hop RAM held whatever it powered up with while the table on
                ; the screen said sixteen empty slots.
                ;
                ; AFTER channel_reset_all, exactly where $C6C3 sits relative
                ; to $80F3 at $8333: hop_program codes each slot against the
                ; range channel 0 stands at, and channel_reset_all is what
                ; puts that range where the instrument has it.
                lbsr    hop_table_defaults

                ; AND THE RECORDS ONTO THE CHIP WITHOUT THE RELAYS, because
                ; that is the routine the stock's cold path actually runs.
                ; power_on_init calls reinit_channel_tables ($C6C3) at $8333,
                ; and $C6C3 calls dds_table_defaults, init_channel_blocks and
                ; then reapply_all_channels ($C5B1) - which is
                ; channel_reapply_all here. $C5B1 moves no relay: the latches
                ; are reset_all_channel_outputs' job, done just above. This
                ; branch used to fall into register_apply below, whose extra
                ; work is the output and float relays from CHAN_STATE, so a
                ; cold instrument drove its relays from a record it had just
                ; defaulted.
                lbsr    channel_reapply_all
                bra     boot_channels_done
boot_keep_state
                ; THE SEQUENCE COMES BACK FIRST, out of the frame reset_entry
                ; staged it into. Only a believed battery gets here - the
                ; untrusted path clears special_flags - so this is the same
                ; trust a register recall extends to a slot, and the same
                ; routine: register_seq_unstage, whose kind byte decides
                ; which model is filled and fills neither for SEQKIND_NONE,
                ; and which bounds the tone end and cursor as they go back.
                leau    ,s
                lbsr    register_seq_unstage
                leau    REGISTER_SEQBLOCK,s     ; and FM Stereo's nineteen;
                ldx     #st_tone                ; stereo_open checks the
                ldb     #ST_SAVED_WIDE+ST_SAVED_NARROW ; choices before it
                lbsr    register_seq_copy       ; uses them
                leas    BOOT_FRAME,s

                ; THE PRESET RUNS ON THIS BRANCH TOO, and it did not. The
                ; stock's keep-state arm is $82CE: `LDU #$0000 / PSHS U /
                ; LBSR instrument_preset`, and only then does it restore the
                ; four latch shadows from $2206-$2209. So an instrument that
                ; comes back holding last week's setup still starts from a
                ; chip whose registers were written rather than assumed.
                ; While the reset lived at the top of this routine that
                ; happened by another road; with it gone this branch would
                ; have had no chip reset at all.
                lbsr    instrument_preset
                lbsr    register_apply          ; THE RESTORE, and this one
                                                ; does move the relays: the
                                                ; state byte came back with
                                                ; the records, so the screen
                                                ; and the output agree from
                                                ; the first moment
boot_channels_done
                ; NO OUTPUT BOARD AT ALL. The stock checks this at $8345,
                ; after the channel setup and a delay_ms($00FA), and raises
                ; error $0A rather than clearing $23DE as every other path
                ; does - so an instrument with no output board says so at
                ; power-on instead of looking healthy and refusing every
                ; channel operation later. This firmware did not check it.
                ;
                ; The delay is the stock's and comes first, because the relays
                ; the reset just moved are mechanical and the beep should not
                ; overlap them.
                ldd     #BOOT_SETTLE_MS
                lbsr    delay_ms
                lbsr    keypad_init             ; THE KEYPAD'S IDLE COLUMNS
                                                ; HERE, not at reset: the stock
                                                ; writes $0A00 <- $00 in
                                                ; reset_panel_ports and the
                                                ; idle pattern only near the end
                                                ; of power-on, in
                                                ; keypad_idle_and_read_rows
                                                ; ($837A)
                lda     >installed_channels
                bne     boot_have_channels
                ldb     #ERR_NO_CHANNELS
                lbsr    error_raise
                bra     boot_tone_done
boot_have_channels
                ; THE POWER-ON TONE. power_on_init ($81AD) calls
                ; ptm_t1_output_pulse ($D6C8) twice - once after
                ; ptm_timer_init at $8244 and once as the last thing it does
                ; at $839B - and that routine is the one error_report_beep
                ; ($C3FE) uses to make a fault audible: unless bit 2 of $23C1
                ; is set it ORs $80 into the CR1 shadow, waits delay_ms($64)
                ; and clears it again. error_beep here is the same thing with
                ; the CR1/CR3 selection got right, and special function 2 is
                ; this firmware's spelling of that $23C1 bit.
                ;
                ; THIS IS THE SECOND OF THE TWO. The first sounds at the top of
                ; reset_entry, before the probe, where $8239 sounds it. It was
                ; left out once on the ground that the stock reads the silence
                ; bit from unchecked RAM; the stock does, it costs a tone at
                ; worst, and dropping it also dropped the stock's hundred
                ; milliseconds before the probe. So both are sounded.
                lbsr    error_beep
boot_tone_done

                ; THE MAIN SELECTION LEVEL, AT ONCE. power_on_init ($81AD)
                ; ends in the Main Selection; the identification banner is arm
                ; [5]'s, shown for three seconds when shifted BACKSPACE asks
                ; for it (hp8904a-rewrite/modules/service_info.s,
                ; id_banner_show). Driven on the stock 2026-09-11: booted with
                ; its signature intact it is on the Main Selection by 0.75 M
                ; steps and stays there. This showed a banner of its own and
                ; waited for a key.
                lbsr    main_menu_latch         ; $8492, once, before the loop
                lbsr    boot_open_mode          ; the Main Selection, or the
                                                ; mode a keep-state power-on
                                                ; comes back to

                ; Both maskable interrupts stay MASKED. See the handler
                ; comments below: the FIRQ source cannot be acknowledged by
                ; anything establishable from the stock firmware, and the IRQ
                ; source is a peripheral this firmware does not service. The
                ; keypad is polled instead. NMI is not maskable and has a
                ; real handler.
                orcc    #BOTH_MASKS             ; last, when the hardware is
                                                ; ready for the handlers
                lbra    foreground

halt
                bra     halt                    ; a bug, not a resting state

; ---------------------------------------------------------------------------
; boot_open_mode - the first screen after power-on
;
;   uses:  A, B, X, Y, U, and whatever the mode or the Main Selection uses
;
; foreground_main_loop ($83A0) at l848d, right after
; build_option_dispatch_table: LDD >$23C1 / ANDB #$01 / CMPD #$0000 / LBEQ
; l84c0 - bit 0 of the word's low byte, the keep-state preference - and when
; it is set, LDB #$02 ... LDX >$24E6 / JSR ,X: the active mode entered again
; with reason 2, no preset and no defaults, on the record it was showing.
; Otherwise l84c0 calls enter_paged_menu_mode. Measured on the stock
; 2026-09-16 (docs/mode-reentry.md): with the preference set, each of Channel
; Configuration, Tone Sequence and Digital Sequence came back on record 1
; holding a marker poked into its data before the power cycle.
;
; mode_reenterable is asked first because a mode returns with whatever carry
; it last left, so mode_reenter's own refusal cannot be told from a mode that
; ran. A record it refuses - the Main Selection's own, this firmware's two
; additions, or anything a battery held - opens the Main Selection, which is
; what $8D23 does with reason 2 as well.
; ---------------------------------------------------------------------------
boot_open_mode
                lda     >special_flags
                bita    #SPECIAL_KEEP_STATE
                beq     boot_open_menu
                ldx     >active_mode
                lbsr    mode_reenterable
                bcs     boot_open_menu
                ldb     #MODE_KEEP
                lbra    mode_reenter            ; l848d: JSR through $24E6
boot_open_menu
                ; AND A MACHINE WHOSE BACKLIGHT SETTING HAS NEVER BEEN ANSWERED
                ; OPENS ON IT. backlight_set holds $5A once it has been, and
                ; the $00 a flat battery leaves and the $FF of RAM nobody has
                ; written both ask again - the architect's addition of
                ; 2026-09-17. Until it is answered the
                ; lamp stays on, because backlight_reload gives a machine with
                ; no answer no timeout at all.
                lda     >backlight_set
                cmpa    #BACKLIGHT_MAGIC
                lbne    backlight_menu_open
                lbra    main_menu_open          ; l84c0

; ---------------------------------------------------------------------------
; lcd_init - bring the display up
;
;   uses:  A
;
; The HD44780 needs its function set sent before it will accept anything
; else. Every command here goes through lcd_command, which waits on the busy
; flag, so no arbitrary delays are needed.
; ---------------------------------------------------------------------------
lcd_init
                lda     #LCD_FUNCTION|$10|$08   ; 8-bit interface, two lines
                lbsr    lcd_command
                lbsr    lcd_control_init        ; display on, cursor off, and
                                                ; the SHADOW set to match -
                                                ; this wrote the byte as a
                                                ; literal and kept no record,
                                                ; so nothing could change one
                                                ; of the three bits without
                                                ; guessing the other two
                ; AND NO ENTRY-MODE COMMAND, because the instrument
                ; sends none. This wrote LCD_ENTRY_MODE|LCD_ENTRY_ADVANCE
                ; here, and two things were wrong with it at once. The bit
                ; meanings are NOT ESTABLISHED from anything in this
                ; repository - there is no HD44780 data sheet in
                ; firmware/datasheets/ (AD565A, AM27C256, DS75160A, HM6264,
                ; Intel 27513, P8291A, MC6809 and MC6840 are what is there) -
                ; and the stock's own lcd_init, read at
                ; src-generated/a2u12.s:17870, writes $38, $0C, $01 and $28
                ; and no entry-mode command at all. So this firmware was
                ; sending the panel a byte whose meaning it could not state,
                ; where the instrument sends nothing and takes the
                ; controller's power-on default. The standard is the
                ; instrument. display.inc keeps the constants and what is and
                ; is not known about them, because a later reader with a data
                ; sheet in hand should find the question already asked.
                lbra    lcd_clear


; ---------------------------------------------------------------------------
; foreground - the main loop
;
;   never returns
;
; Scans the keypad and gives each new key to whichever screen is showing.
; That is the whole executive, and it is deliberately this small.
;
; WHY POLLING. The keypad can assert FIRQ, and this firmware does not use it
; - see the interrupt handlers below for why, and it is not a preference: the
; acknowledgement mechanism for that interrupt is not establishable from the
; stock firmware, and an interrupt that cannot be acknowledged locks the
; instrument up. Polling needs no acknowledgement. A key press is noticed
; within one pass of a loop that does almost nothing else, which is far
; faster than a key can bounce.
;
; WHY THE SCREEN OWNS THE KEY. Every screen installs its own key handler at
; screen_handler, and the loop calls it. The alternative - one big switch
; here that knows what every screen wants - is how the stock firmware ended
; up with a thirty-four arm dispatch table that no screen could be added to
; without editing.
;
; The handler is called with the key in B. It may repaint, it may change
; screens, it may ignore the key; the loop does not care and does not check.
; A handler that is somehow zero falls back to the Main Selection Level,
; because a machine with no screen installed is a machine an operator cannot
; get out of.
; ---------------------------------------------------------------------------
foreground
                ; NO DEPTH TEST HERE ANY MORE. This began `cmps #STACK_FLOOR`
                ; with a recovery arm that reset S, called nav_reset and
                ; reopened the top menu. The stock compares S nowhere in any of
                ; its five images, and the only reason this firmware needed to
                ; was that it had declared 350 bytes of live cells inside the
                ; stack's own 452 and had 102 left. Those cells are out, the
                ; stack has its room back, and the banner at the head of this
                ; file carries the architect's word for making the map right
                ; rather than policing a map that was wrong.
                ;
                ; It was also a LEAK detector and never a depth guard: it ran
                ; once a pass at the TOP of the loop, where the stack should be
                ; empty, so a routine that descended and returned between two
                ; passes was never seen by it at all. What a transient descent
                ; reaches is the interrupt, which cannot be masked, and the
                ; answer to that is room rather than a compare.
                ;
                ; foreground_depth_ok went with it: it was the branch target of
                ; the compare and had no other caller.
                ; THE FAULT LINES, EVERY PASS. int_latch carries four of them
                ; and nothing in the foreground looked: the decode existed in
                ; service_pll.s and only that screen called it, so an
                ; instrument that tripped a reverse-power relay said nothing
                ; until somebody thought to open the PLL screen. The stock
                ; polls this port on every pass of its own main loop.
                ;
                ; ON THE EDGE, not on the level. Raising an error every pass
                ; would beep continuously and repaint over whatever the
                ; operator was doing; raising it when the set of asserted
                ; lines CHANGES tells them once, and again if a second line
                ; goes.
                ; BOTH KINDS. pll_faults_asserted returns the four
                ; reverse-power lines, bits 3:0 and inverted; the reference
                ; loop is bit 5 of the same port and is NOT inverted, and
                ; nothing here read it at all - on an instrument whose loop
                ; losing lock makes every frequency it produces wrong. They
                ; share one edge memory because they share one port.
                ;
                ; ONE READ FOR THE WHOLE PASS, which is the instrument's own
                ; shape and was not this firmware's. foreground_main_loop
                ; ($83A0) reads the port ONCE, at $84CB LDB >int_latch /
                ; $84CD EORB #$0F / $84CF STB 5,S, and every test in the rest
                ; of its pass reads that one byte out of the frame: $84D4
                ; ANDB #$20 for the reference loop, $85D4 ANDB #$0F for the
                ; four reverse-power lines, $8622 ANDB #$0F again for the
                ; changed set and $88DF ANDB #$40 for the sixth line. This
                ; loop read the port FOUR separate times a pass - twice
                ; through service_pll.s and twice more below - so its four
                ; decisions were about four different instants of a port that
                ; carries four independent fault lines, and two of them could
                ; disagree about the same moment. The one snapshot ends that.
                ;
                ; THE EOR REACHES ONLY THE LOW FOUR BITS, which is why one
                ; byte can serve all of them: bits 3:0 are active low and come
                ; out of the EOR as "a 1 bit is a fault", exactly what
                ; pll_faults_asserted's own EOR produces, and bits 5, 6 and 7
                ; pass through untouched and keep the sense they are read in.
                ; The two service_pll.s routines still exist and are still
                ; called - pll_show and the reference-check screen read them -
                ; and what is dropped here is only their second and third read
                ; of a port this pass has already sampled.
                ;
                ; BIT 7 IS IN THE SNAPSHOT TOO, and the stock's is not: its
                ; rear-connector service lives in firq_body ($F0A1), which
                ; takes its own read at $F0AC because it runs at interrupt
                ; level and not in this pass. This firmware polls that line
                ; here instead - FIRQ is masked, see the interrupt section -
                ; so for it the pass IS the instant, and reading the port a
                ; second time for it would reintroduce the split this
                ; snapshot removes.
                lda     >int_latch              ; the stock's $84CB
                eora    #$0F                    ; and its $84CD
                pshs    a                       ; the pass's one snapshot,
                                                ; pulled at the digital-port
                                                ; test below, which is the
                                                ; last of the four to read it
                anda    #FAULT_OUTPUT_LINES|FAULT_REF_UNLOCK
                cmpa    >fault_lines
                beq     foreground_faults_known
                sta     >fault_lines
                tsta                            ; a fault CLEARING is a change
                beq     foreground_faults_known ; and is not an error
                lbsr    fault_report            ; and it says WHICH, in the
                                                ; stock's own words, rather
                                                ; than showing a number
foreground_faults_known

                ; BIT 6 OF THE SAME PORT, the stock's two-state machine at
                ; $88DA, ported at the architect's direction (poll and
                ; repaint, no per-screen vector). LDB 5,S / ANDB #$40 there
                ; reads the local holding int_latch EOR $0F, so bit 6 is NOT
                ; inverted and a SET bit is the line's normal state: while it
                ; is CLEAR the stock counts passes, past $C8 = 200 it arms a
                ; latch, and when the bit RETURNS with the latch armed it
                ; posts request code $2E - which no arm consumes; the guard
                ; at $8F13 hands it to the installed screen handler, i.e. it
                ; exists so the screen showing can refresh itself when the
                ; line recovers. What the line IS, the service manual does
                ; not print: its own page 8-23 says the A2 schematic is
                ; proprietary and not provided. The debounce and the edge are
                ; the ROM's; the answer here is the screen repainting itself,
                ; which is what every screen already knows how to do.
                lda     ,s                      ; the pass's snapshot, as the
                                                ; stock's own LDB 5,S reads
                                                ; the local rather than the
                                                ; port a second time
                bita    #$40
                bne     foreground_line6_high
                lda     >line6_count            ; clear: count the passes,
                inca                            ; saturating so the counter
                beq     foreground_line6_full   ; cannot wrap back past the
                sta     >line6_count            ; threshold
foreground_line6_full
                lda     >line6_count
                cmpa    #200                    ; the stock's $C8
                blo     foreground_line6_done

                lda     #$01
                sta     >line6_armed
                bra     foreground_line6_done
foreground_line6_high
                clr     >line6_count
                tst     >line6_armed            ; the RETURN, after a real
                beq     foreground_line6_done   ; absence: the event
                clr     >line6_armed
                ldx     >screen_handler         ; deliver the event to the
                beq     foreground_line6_done   ; screen showing, as the
                ldb     #KEY_REFRESH            ; stock's $2E goes to $220F.
                jsr     ,x                      ; KEY_NONE was the first
                                                ; draft, and menu_key refuses
                                                ; code 0 AUDIBLY - the
                                                ; recovery would have beeped
                                                ; at an operator on any menu.
                                                ; KEY_REFRESH is passed in
                                                ; silence by key_refuse, the
                                                ; tail every screen's ignore
                                                ; arm ends in, so the event
                                                ; reaches every screen and
                                                ; changes nothing for one
                                                ; that does not act on it
foreground_line6_done

                ; BIT 7 OF THE SAME PORT, THE REAR DIGITAL CONNECTOR.
                ; firq_body ($F0A1) reads int_latch AND $90 at $F0AC and, when
                ; bit 7 is set ($F0BC), reads digital_in ($0600) into a frame
                ; local and calls the callback at $24DA if bit 9 of
                ; event_flags2 is armed. THE READ IS THE SERVICE: it is what
                ; takes the line down, and nothing else in the stock touches
                ; $0600 except the two power-on clears.
                ;
                ; This firmware runs with FIRQ masked and polls in the
                ; foreground - see the head of the interrupt section - so the
                ; same service is done here, on the same latch, every pass.
                ;
                ; THE VALUE IS DISCARDED, AND SO IS THE STOCK'S. $F0DC passes
                ; it on only when that flag is armed and a callback is
                ; installed; with none armed - which is every path in this
                ; firmware - the local dies with the frame. What the read is
                ; FOR is the line, not the byte.
                ;
                ; IT WAS IN PAGE 2, as digital_input, and nothing called it
                ; once the Digital Sequence screen was rebuilt to the
                ; instrument's own three menu records, which carry no input
                ; field. A paged routine could not have been called from here
                ; in any case: the ABI runs the other way.
                puls    a                       ; the pass's snapshot, and the
                                                ; last use of it: the stack is
                                                ; level again from here on
                bita    #$80
                beq     foreground_digital_idle
                lda     >digital_in             ; the read IS the service
foreground_digital_idle

                lbsr    display_tick            ; and the backlight's
                                                ; idle minutes, counted in
                                                ; milliseconds off timer 1
                ldx     >screen_poll            ; A SCREEN THAT RUNS BETWEEN
                beq     foreground_polled       ; KEYS gets one call a pass -
                jsr     ,x                      ; the relay exercise counts its
foreground_polled                               ; time here and still answers
                                                ; every key
                lbsr    remote_poll             ; the bus interface: the stock
                                                ; polls its INT mirror once
                                                ; per IRQ tick from the same
                                                ; loop; this polls it every
                                                ; pass, no interrupt needed
                lbsr    foreground_tick         ; anything that has to happen
                                                ; on its own, rather than
                                                ; because a key was pressed
                lbsr    keypad_read             ; Z set when nothing is new
                beq     foreground

                pshs    b                       ; A KEY: light the backlight
                lbsr    backlight_wake          ; and restart its three
                puls    b                       ; minutes. 8-41: "Pressing any
                                                ; key will turn the
                                                ; backlighting back on."
                ; WHILE REMOTE, THE PANEL IS LOCKED BUT FOR LOCAL.
                ; numeric_entry_key_handler ($B3C2) - the one path every
                ; panel key takes - tests event_flags bit 3 at $B3DF and,
                ; with it set, lets key_code 1 through and leaves at lb5e0
                ; for every other: no beep, no error, no screen. Driven on
                ; the stock 2026-09-11: in remote, NEXT, f1 and 3 change
                ; nothing and record nothing, and LOCAL returns the
                ; instrument to local after which NEXT pages the Main
                ; Selection. This firmware acted on every key while remote.
                ;
                ; TWO EXCEPTIONS, both the stock's. The Keyboard Check goes
                ; first: keyboard_check_screen_init ($4B1E) sets bit 2 of
                ; $2202, which $B3C2 tests BEFORE the remote bit and hands
                ; every key to [$23B0] - screen_keeps_local is that flag.
                ; And only the PANEL is locked: the bus's own key
                ; equivalents come to foreground_key from remote.s, as the
                ; stock's post their request codes without passing $B3C2.
                ;
                ; The backlight wakes above this whatever the remote state;
                ; where the stock wakes it relative to $B3DF is not
                ; established here.
                tst     >screen_keeps_local
                bne     foreground_key_panel
                lda     >rmt_flags
                bita    #RF_REMOTE
                beq     foreground_key_panel
                cmpb    #KEY_LOCAL
                lbne    foreground              ; dropped, in silence
foreground_key_panel
                ; A MAPPED KEY ENDS THE OPEN ENTRY BEFORE ANYTHING ACTS ON IT.
                ; numeric_entry_key_handler ($B3C2) takes the cursor down at
                ; $B45C or $B48C for a key key_to_state_code ($AD4D) or
                ; keymap_menu_msgs_19_1d ($AEBB) maps while $23A8 is set, and
                ; only then does the posted request reach a screen - which may
                ; arm a field and put the cursor back. Here, for the panel's
                ; keys only: the bus's key equivalents do not pass $B3C2, and
                ; the Keyboard Check's keys are handed to [$23B0] at the head
                ; of $B3C2 before either mapper is asked. entry.s has the
                ; table of mapped codes and why the cursor bit is $23A8.
                tst     >screen_keeps_local
                bne     foreground_key_act
                lbsr    entry_key_exit          ; B comes back as it went in
foreground_key_act
                lbsr    foreground_key          ; and act on it - ONE routine,
                lbra    foreground              ; so the bus can deliver a key
                                                ; equivalent through exactly
                                                ; the same path a finger takes

; ---------------------------------------------------------------------------
; foreground_key - act on one key code, from the panel or from the bus
;
;   entry: B = the key code
;   uses:  B, X - and whatever the key's handler uses. B and X are this
;          routine's own: the LOCAL arm loads the installed handler into X and
;          the request code into B to deliver it, as event_local_key ($8DE6)
;          does through call_installed_handler_220f
;
; Everything below used to sit inline in the loop and end each arm with LBRA
; foreground. It is a routine now because remote.s delivers the stock's
; key-equivalent bus commands (UP DN IS SV RC SF > <, and the digit after FC
; FS) to it, so a command from the bus and a press on the panel cannot come
; to differ in what they do.
; ---------------------------------------------------------------------------
foreground_key


                ; LOCAL IS THE WAY OUT OF ANYTHING, and it is handled HERE
                ; rather than in each screen, so that no screen can trap an
                ; operator by forgetting to offer it. That is not a
                ; hypothetical: this firmware had six screens with no way
                ; back at all, and the only escape was switching the
                ; instrument off.
                ;
                ; One screen legitimately needs every key: the Keyboard
                ; Check, whose whole purpose is reporting what was pressed.
                ; It sets screen_keeps_local, and it takes LOCAL pressed
                ; TWICE to leave - so even the exception cannot strand
                ; anybody.
                ; THE SCAN'S TWO FAULT CODES GO ONLY WHERE THEY ARE WANTED.
                ; KEY_INVALID and KEY_DOUBLE are what keypad_scan reports for
                ; a ghost and for two keys at once, and the Keyboard Check -
                ; the screen that claims every key - prints them as
                ; 'INVALID ' and ' DOUBLE '. Everywhere else they are
                ; dropped without a beep, which is the stock's shape too:
                ; its keymap guard admits 1..$34 and returns 0 for $35/$36,
                ; so on an ordinary screen a chord is simply not a key.
                cmpb    #KEY_INVALID
                blo     foreground_key_sound
                tst     >screen_keeps_local
                lbne    foreground_dispatch
                rts               
foreground_key_sound
                ; THE SHIFT KEY IS NOT A MESSAGE. kbd_decode ($AAE8) sets the
                ; latch and returns code 7 so the Keyboard Check can name it,
                ; and key_to_state_code's arm for it posts NOTHING - driven on
                ; the stock 2026-09-11, SHIFT alone on the Main Selection Level
                ; leaves $23DE at zero while DOWN, which that screen does not
                ; use, puts $0F there. Here it reached the screen handler like
                ; any other key, so every screen that refuses what it cannot
                ; use recorded a fault for the FIRST HALF of every shifted
                ; combination: SHIFT then WAVE FORM left 'Invalid key entry'
                ; behind it on the channel screen.
                ;
                ; The Keyboard Check still gets it: it sets screen_keeps_local,
                ; which is the same flag that gives it LOCAL.
                cmpb    #KEY_SHIFT
                bne     foreground_key_local
                tst     >screen_keeps_local
                lbne    foreground_dispatch
                rts
foreground_key_local
                cmpb    #KEY_LOCAL
                bne     foreground_shifted
                lbsr    remote_local_key        ; WHILE REMOTE, LOCAL BELONGS
                lbcs    foreground_key_taken    ; TO THE BUS FIRST: the stock's
                                                ; event_local_key runs
                                                ; gpib_go_to_local before the
                                                ; screen sees the key, and
                                                ; under lockout the key does
                                                ; nothing at all
                tst     >screen_keeps_local
                lbne    foreground_dispatch

                ; LOCAL DOES NOT LEAVE A SCREEN ON THE INSTRUMENT.
                ; event_local_key ($8DE6) is arm [0] of the key table at
                ; $8F2A: gpib_go_to_local, then call_installed_handler_220f
                ; - so the screen hears request 1 and stays where it is.
                ; Driven on both, 2026-09-15: LOCAL on ch B, Tone, DTMF and
                ; Digital Sequence leaves the instrument on that screen with
                ; nothing recorded, and this firmware went back to the Main
                ; Selection Level. The escape was added when six screens had
                ; no way back; each has its own now, and the architect ruled
                ; on 2026-09-15 that the stock is the standard.
                ldx     >screen_handler
                beq     foreground_local_none
                ldb     #KEY_GONE_LOCAL
                jsr     ,x
foreground_local_none
                rts               

                ; THE SHIFTED KEYS, WHICH REACHED NOTHING AT ALL. key_decode
                ; produces KEY_S_FREQ (37) through KEY_S_F2 (50) for the
                ; shifted half of the action table, and grepping the whole
                ; tree for KEY_S_ outside keys.inc returned NOT ONE line - no
                ; handler compared one. So SHIFT followed by any of these
                ; consumed the latch and did nothing, on an instrument whose
                ; front panel is silkscreened with what they do.
                ;
                ; They are handled HERE, beside LOCAL, and for the same
                ; reason: they are global, and a screen that forgot them would
                ; trap the operator. The stock reaches them the long way round
                ; - its $AE3D arms post a request code into $2217 and the
                ; 34-way table at $8F2A acts on it - and each mapping below is
                ; that chain followed to its end. The request code is named in
                ; each comment so the chain can be walked again.
foreground_shifted
                ; A SCREEN MAY TAKE THEM ALL. ui_message_dispatch ($8D60) tests
                ; bit 3 of $2202 before its 34-way table and, when it is set,
                ; offers the waiting request to the hook in $220D first; a
                ; non-zero answer turns it into $3C, which the table sends to
                ; the installed screen instead of acting on it. The Special
                ; Functions screen installs special_function_screen_handler
                ; ($6A25) there (page 3, $7320), and driven on the stock every
                ; shifted key then stays on that screen, silently, except the
                ; two it answers itself. screen_takes_shift is that bit.
                tst     >screen_takes_shift
                lbne    foreground_dispatch
                cmpb    #KEY_S_LOCAL            ; posts $02 -> arm [1],
                bne     foreground_shift_special ; hpib_address_screen_arm:
                lbsr    remote_address_open     ; the bus address screen
                rts
foreground_shift_special
                ; SPECIAL FUNCTIONS IS THE MAIN SELECTION LEVEL'S KEY, not a
                ; global one, and this chain opened it from anywhere.
                ; invoke_page0_vector_4024 ($8EDB) does LDD #$8c14 / CMPD
                ; >$220F and calls page 0's $4024 only when the Main Selection
                ; handler is the one installed; on any other screen it beeps
                ; error $10, whose words in the stock's own table are 'Go to
                ; Main Selection Level for SPECIAL'. That message exists
                ; BECAUSE the key is refused elsewhere - carrying the message
                ; and not the refusal would have been half a port.
                ;
                ; It is answered in modules/main_menu.s:main_menu_key, where
                ; the instrument answers it. What is left here is the refusal.
                cmpb    #KEY_S_LAST             ; posts $05 -> arm [4]
                bne     foreground_shift_diag
                ldx     >screen_handler         ; $8EDB's LDD #$8c14 / CMPD
                cmpx    #main_menu_key          ; >$220F, in this firmware's
                lbeq    foreground_dispatch     ; own names: the Main Selection
                                                ; Level's handler answers it and
                                                ; every other screen gets the
                                                ; refusal below
                ldb     #ERR_SPECIAL_ELSEWHERE
                lbsr    error_raise
                rts
foreground_shift_diag
                cmpb    #KEY_S_F1               ; posts $03 -> arm [2],
                bne     foreground_shift_float  ; action3_call_paged_routine
                lbsr    service_menu_open       ; ($8E00), which reaches page
                rts                             ; 3's diagnostics menu through
                                                ; page 0's $4022. No $220F
                                                ; guard on that arm: the
                                                ; diagnostics open from every
                                                ; screen, and this key reached
                                                ; nothing at all before
foreground_shift_float
                cmpb    #KEY_S_FREQ             ; posts $12 -> arm [17]
                bne     foreground_shift_onoff
                lbsr    output_float_open
                rts               
foreground_shift_onoff
                cmpb    #KEY_S_PHASE            ; posts $0F -> arm [14]
                bne     foreground_shift_filter
                lbsr    output_onoff_open
                rts               
foreground_shift_filter
                cmpb    #KEY_S_AMPL             ; posts $0C -> arm [11]
                bne     foreground_shift_recall
                lbsr    filter_screen_open
                rts               
foreground_shift_recall
                ; BOTH SAVE AND RECALL REACH THE SAME SCREEN, and the shifted
                ; DOWN key reached nothing at all. In the stock they are two
                ; request codes and two prompts: key 45 posts $21, which is
                ; arm [32] and the Save prompt, and key 47 posts $22, which is
                ; arm [33], state_open_recall_register, and the Recall
                ; wording, and this firmware follows both.
                cmpb    #KEY_S_UP               ; posts $22 -> arm [33],
                bne     foreground_shift_save   ; state_open_recall_register
                lbsr    register_screen_open_recall ; ($8E9B): the RECALL
                rts                             ; and $3A7B = 0
foreground_shift_save
                cmpb    #KEY_S_DOWN             ; posts $21, which d8f2a has no
                bne     foreground_shift_id     ; arm for, so it goes on to
                ldx     >screen_handler         ; the mode's own handler. Pages
                beq     foreground_save_none    ; 0, 1 and 2 answer it with the
                ldb     #RMT_RQ+$21             ; Save prompt ($F331 with $0021)
                jsr     ,x                      ; after closing their field;
foreground_save_none                            ; every other screen refuses
                rts                             ; it - $0F on the Main Selection
                                                ; Level, driven 2026-09-15
foreground_shift_id
                cmpb    #KEY_S_BACKSPACE        ; posts $06 -> arm [5]
                bne     foreground_shift_reset

                ; AND THIS IS THE PATH THAT RESETS THE OUTPUTS, the only one
                ; the front panel has. Arm [5],
                ; show_id_screen_then_main_menu ($8DAD), calls the screen exit
                ; vector at $2213, then reset_all_channel_outputs ($80F3),
                ; then zeroes $23C1, then shows the identification banner.
                ;
                ; IT WAS PUT ON main_menu_open FIRST, WHICH WAS WRONG, and
                ; reading further is what found it. The stock has four ways
                ; back to the Main Selection Level and only two of them reset:
                ; arm [5] here and arm [6], event7_return_to_main_menu
                ; ($8D8C). Arm [3], state_return_to_main_menu ($8E22) - which
                ; is what shifted NEXT posts, request $04 - and
                ; return_to_main_menu ($8E62) both call the exit vector and
                ; enter_paged_menu_mode ($8D23) and touch nothing else.
                ;
                ; Hanging the reset on main_menu_open meant LOCAL, shifted
                ; NEXT, the fallback for a missing screen handler and leaving
                ; the power-on banner all wiped the operator's channel
                ; settings - far more often than the stock, and on the one key
                ; that exists so nobody can be trapped in a screen.
                ;
                ; Request $07 is not produced by any key: the 52-arm table at
                ; $AD4D was walked and the only arms posting one of these are
                ; arm[43], key 44 (shifted NEXT) with $04, and arm[47], key 48
                ; (shifted BACKSPACE) with $06.
                ;
                ; AND THE VECTOR RUNS FIRST, as $8DAD's own first two
                ; instructions do - `LDX >$2213 / JSR ,x`, then
                ; reset_all_channel_outputs. Running it afterwards, through
                ; id_banner_show's return to main_menu_open, is not the same
                ; thing: instrument_preset has parked every routed_dest by
                ; then and the mode's callback finds nothing left to
                ; dismantle. The same fault and the same fix as remote_cmd_ps;
                ; screen_exit_run's header carries the measurement.
                lbsr    screen_exit_run
                lbsr    channel_reset_all
                clr     >special_flags          ; $8DBC: $23C1 zeroed - every
                                                ; special function off
                lbra    id_banner_show          ; and the banner, three
                                                ; seconds, the Main Selection
foreground_shift_reset
                cmpb    #KEY_S_F3               ; posts $11 -> arm [16], the
                bne     foreground_shift_menu   ; UNVETOED phase reset - which
                lbsr    dds_phase_reset_now     ; is the only way to ask for
                rts                             ; one by hand with the special
                                                ; function set
foreground_shift_menu
                cmpb    #KEY_S_NEXT             ; posts $04 -> arm [3]
                bne     foreground_dispatch
                lbsr    main_menu_open          ; LBSR: same wild-rts defect
                rts                             ; as the depth recovery above,
                                                ; on a PLAIN KEYPRESS - every
                                                ; sibling arm here already
                                                ; does lbsr-then-lbra, and
                                                ; this one alone jumped
foreground_dispatch
                ldx     >screen_handler
                beq     foreground_recover
                jsr     ,x
                rts               
foreground_recover
                lbsr    main_menu_open
foreground_key_taken
                rts                             ; EVERY arm returns. Two of
                                                ; them ended in LBRA foreground
                                                ; and leaked the lbsr return -
                                                ; two bytes per LOCAL while
                                                ; remote, and remote_poll's
                                                ; whole frame from the bus -
                                                ; until the critique read it

; ---------------------------------------------------------------------------
; The interrupt handlers, and why this firmware runs with two of the three
; permanently masked.
;
; THE THREE SOURCES, as established from the stock firmware:
;
;   IRQ   comes from the bus interface peripheral, which this firmware does
;         not service. The stock handler does nothing but set a flag, and its
;         own wrapper re-masks I in the stacked CC before returning, so even
;         there IRQ stays off until a foreground routine deliberately enables
;         it.
;
;   FIRQ  comes from bit 4 (the keypad) and bit 7 (the rear digital port) of
;         the latch at $0100.
;
;   NMI   cannot be masked at all, so it must always have a working handler.
;
; WHY THE KEYPAD IS POLLED RATHER THAN INTERRUPT-DRIVEN. An interrupt has to
; be acknowledged or it re-enters forever, and for FIRQ the acknowledgement
; is NOT ESTABLISHED. Searching all five stock images by symbol and by
; address finds five reads of $0100 and NOT ONE WRITE, so the latch is
; cleared by external logic as a side effect of some access the handler
; happens to make - reading the digital port, or driving the keyboard columns
; - and which access clears which bit cannot be read off the instruction
; stream.
;
; Enabling an interrupt whose acknowledgement is a guess is how an instrument
; locks up with the front panel dead. The keypad is scanned in the foreground
; instead, which needs no acknowledgement at all, and the scan is far faster
; than a key can bounce. Nothing is lost: a key press is noticed within one
; pass of a loop that does little else.
;
; So both maskable interrupts stay masked, and the two handlers below exist
; for the case that should never happen. They are not decoration - a spurious
; interrupt is a real hardware fault worth seeing, and the Diagnostics screen
; shows the counts.
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; irq_handler - an IRQ arrived, which should be impossible
;
;   entry: from the IRQ vector; the CPU has stacked every register
;   exit:  RTI, with I set in the stacked CC so it cannot re-enter
;
; Counts the event and returns with IRQ masked in the CC the RTI will
; restore. That last part is what stops an unacknowledged source spinning the
; machine: whatever asserted the line is still asserting it, and returning
; with I clear would come straight back here forever.
; ---------------------------------------------------------------------------
irq_handler
                lda     >spurious_irq           ; saturating, so a storm
                inca                            ; reports "many" rather than
                beq     irq_handler_capped      ; wrapping back to none
                sta     >spurious_irq
irq_handler_capped
                lda     #CC_IRQ_MASK            ; set I in the STACKED CC:
                ora     ,s                      ; IRQ stacks the whole state
                sta     ,s                      ; with CC on top
                rti

; ---------------------------------------------------------------------------
; firq_handler - a FIRQ arrived, which should be impossible
;
;   entry: from the FIRQ vector; the CPU has stacked ONLY CC and PC
;   exit:  RTI, with F set in the stacked CC
;
; FIRQ stacks almost nothing, so everything this touches is saved by hand.
; The same re-masking applies and for the same reason - more sharply here,
; because the FIRQ source cannot be acknowledged at all by anything this
; firmware knows how to do.
; ---------------------------------------------------------------------------
firq_handler
                pshs    a
                lda     >spurious_firq
                inca
                beq     firq_handler_capped
                sta     >spurious_firq
firq_handler_capped
                ; THE STACKED CC IS AT 1,S, NOT 0,S - A IS ON TOP OF IT.
                ;
                ; This did `puls a` first and then `lda #CC_FIRQ_MASK`, which
                ; destroys the byte it had just restored: FIRQ stacks only CC
                ; and PC, so A belongs to whatever was interrupted, and it
                ; came back changed. The `puls a` was doing nothing except
                ; moving the stack pointer.
                ;
                ; Doing the CC work first means indexing past the saved A,
                ; and restoring it last means it survives.
                lda     #CC_FIRQ_MASK           ; set F in the stacked CC
                ora     1,s
                sta     1,s
                puls    a                       ; and only now put A back
                rti

; ---------------------------------------------------------------------------
; nmi_handler - the non-maskable interrupt
;
;   entry: from the NMI vector; the CPU has stacked every register
;   exit:  through nmi_callback, whose target owns the RTI; or RTI here
;
; THREE INSTRUCTIONS AND AN INDIRECT JUMP, which is the stock's handler at
; $DC3D exactly: LDA >event_flags2 / BPL / JMP [>$24d8]. The architect's words
; on 2026-09-17: "nmi_handler there is three instructions and an indirect JUMP,
; not a call - the installed body owns the flag clear, the work and its own
; rti." NMI_CALLBACK_ARMED is bit 7 of the byte, so BPL is its test.
;
; WHAT THE POINTER HOLDS. nmi_callback is never a stale or half-written
; address: boot puts nmi_tick_idle there before it sets the arm bit, and from
; then on it holds one of three things, each written with a single STX, which
; an interrupt cannot land inside -
;
;   nmi_tick_idle   no sequence installed: timer interrupts silenced
;   nmi_tick_hold   a sequence installed but its page switched out: the tick
;                   is acknowledged and dropped, and the timer runs on
;   the body        tone_advance, dtmf_tick_step or digital_advance, which
;                   acknowledges timer 2 itself, does the step and returns
;                   with RTI - the stock's $42D1, $444C and $4196 shape
;
; tick_install, tick_remove, tick_hold and tick_arm_update below are the only
; writers after boot.
;
; WHAT WENT, AND WHY IT COULD. nmi_sequence stood between this jump and the
; body: the timer-2 flag test and clear, seq_in_player in and out, dds_lock,
; tick_armed, the tick_callback load and test, a JSR, and the RTI after the
; body's RTS - about twenty instructions on every tick against the
; instrument's two (docs/interrupt-port.md), 37-38 a served tick against a
; 42-instruction period (log 2366). Each piece has a home now:
;
;   the timer-2 clear   in each body's first two instructions, status then
;                       counter, as the stock's bodies open
;   the flag test       gone: PTM_IRQ_ENABLE is set only by PTM_SEQ_RUN, on
;                       timer 2 (timer.s), so nothing else can be asking -
;                       and the stock's bodies make no such test either
;   dds_lock            in each body, after the clear: the foreground here
;                       stages registers across several accesses and NMI
;                       cannot be masked (docs/interrupt-port.md: REAL)
;   tick_armed and the  the pointer itself: a page switched out puts
;   page compare        nmi_tick_hold in, and the proved page puts the body
;                       back (paging.s)
;   seq_in_player       gone, on the condition recorded for it: the service
;                       fits inside the period (measured in the log for all
;                       three players with this change)
; ---------------------------------------------------------------------------
NMI_CALLBACK_ARMED  equ     $80         ; bit 7 of the high byte of event_flags

nmi_handler
                lda     >event_flags
                bpl     nmi_handler_silence     ; bit 7 clear: not armed
                jmp     [>nmi_callback]         ; the target owns the RTI
nmi_handler_silence
                lbsr    nmi_silence             ; RTS: the foreground calls it
                rti                             ; too, so the RTI is here

; ---------------------------------------------------------------------------
; nmi_tick_idle - the callback when no sequence is installed
; nmi_tick_hold - the callback while an installed sequence's page is away
;
;   entry: through nmi_callback; the CPU has stacked every register
;   exit:  RTI
;
; IDLE is the stock's unarmed arm: with bit 15 of $2202 clear its handler
; clears the interrupt enables on all three timers ($DC46 on), because an
; interrupt returned to with its source still asserting is taken again for
; ever. tick_remove stops timer 2 before it puts this in, so it runs only for
; an interrupt nothing asked for.
;
; HOLD is what tick_armed at zero did: a sequence stays installed while
; page_select_and_verify moves the window, or while a service screen holds
; another page, and the tick that lands then is cleared - status, then the
; counter, the two-step clear the bodies make - and dropped. Calling the body
; would execute whatever the other page has at its address. The timer is left
; running, so the sequence resumes on the tick after tick_arm_update puts the
; body back; foreground_tick removes a sequence whose page has gone for good.
; ---------------------------------------------------------------------------
nmi_tick_idle
                lbsr    nmi_silence
                rti
nmi_tick_hold
                lda     >ptm_status             ; step one of the clear
                ldx     >ptm_timer2             ; step two
                rti

; Silence every timer interrupt source. Each control register is write-only,
; so its shadow is the only readable copy: clear the bit in the shadow and
; write both, or the next writer restores what was just cleared.
;
; CR2 is written first and last. Bit 0 of CR2 selects whether the address
; CR1 shares with CR3 reaches CR1 or CR3, so reaching all three means passing
; through CR2 twice. That is not a workaround - it is how the MC6840 is
; addressed, and the stock handler does the same.
nmi_silence
                ; THE SELECTION AS IT WAS FOUND, kept on the stack across the
                ; whole routine. This left bit 0 of CR2 CLEAR whatever it had
                ; been, and NMI cannot be masked, so it can land in the middle
                ; of a foreground sequence that has selected CR1 and is about
                ; to write it - beep_now in errors.s is exactly that, with a
                ; BEEP_MS delay between the selection and the write. The
                ; foreground would then have put the beeper's control byte
                ; into CR3, which is the timebase for every delay_ms in the
                ; instrument, and ptm_cr3_shadow would have gone on claiming
                ; the value that was no longer there.
                ;
                ; One byte and four instructions, against a fault whose only
                ; symptom is that every settling delay in the instrument is
                ; the wrong length from then until power-off.
                lda     >ptm_cr2_shadow
                anda    #PTM_CR2_SELECT
                pshs    a

                ; TIMER 2 FIRST, BECAUSE TIMER 2 IS THE ONE INTERRUPTING. CR2
                ; sits at its own address whatever its select bit says, so
                ; this is one store and the line drops before the rest of the
                ; sequence runs. It used to be the LAST of the three, and a
                ; handler being re-entered every eighteen instructions never
                ; reached it: driven 2026-09-12 with the digital player's
                ; default period, CR1 and CR3 came back with bit 6 clear and
                ; CR2 still $D1 - the enable the sequence timer had set -
                ; while the stack walked down past $2000. The two writes below
                ; that clear it again are left where they are; writing a bit
                ; that is already clear costs nothing and the block still
                ; reads as "all three, in the order the chip is addressed".
                lda     >ptm_cr2_shadow
                anda    #~PTM_IRQ_ENABLE
                sta     >ptm_cr2_shadow
                sta     >ptm_status

                lda     >ptm_cr2_shadow
                ora     #PTM_CR2_SELECT         ; the shared address now
                sta     >ptm_cr2_shadow         ; reaches CR1
                sta     >ptm_status

                lda     >ptm_cr1_shadow
                anda    #~PTM_IRQ_ENABLE
                sta     >ptm_cr1_shadow
                sta     >ptm_cr

                lda     >ptm_cr2_shadow
                anda    #~PTM_CR2_SELECT        ; and now reaches CR3
                sta     >ptm_cr2_shadow
                sta     >ptm_status

                lda     >ptm_cr3_shadow
                anda    #~PTM_IRQ_ENABLE
                sta     >ptm_cr3_shadow
                sta     >ptm_cr

                lda     >ptm_cr2_shadow
                anda    #~PTM_IRQ_ENABLE
                ora     ,s+                     ; and the selection back as it
                sta     >ptm_cr2_shadow         ; was found, so an interrupted
                sta     >ptm_status             ; foreground writes the
                                                ; register it thinks it is
                                                ; writing

                lbsr    ptm_drain               ; read every status and
                rts                             ; counter so no flag survives.
                                                ; RTS because whoever called
                                                ; this owns the frame

; ---------------------------------------------------------------------------
; instrument_preset - put the outputs in a known, quiet state
;
;   uses:  A, B, X, Y, U
;
; NOTHING QUIESCED THE OUTPUTS. A mode could be entered or left with a
; sequence still clocking, a channel still driving its socket, and the hop
; latch still holding whatever the last sequence put there - and $0B00 had no
; writer in this firmware at all, so whatever the previous firmware left in it
; stayed on the rear connector until something else happened to change it.
;
; The stock has this and calls it from SEVEN sites: reset_all_channel_outputs
; ($80F3) and power_on_init ($81AD) in A2U12, and $52AD on page 0, $522F and
; $5396 on page 1, $700A and $719D on page 2 - which is to say, every entry
; into and every exit from a sequence mode.
;
; WHAT IT DOES HERE, AND WHAT IS DELIBERATELY LEFT OUT. instrument_preset
; ($C6EA) calls ptm_outputs_disable ($D5F1), rebuilds the DDS parameter block
; through dds_params_reset ($DF17), clears $0B00, clears bit 7 of the
; keypad-column shadow $241F and of the LED shadow $2420 and writes both out,
; clears $0600, clears bits in $2202 and $23DE, calls set_flag7_and_led6_off
; ($DB5C), and loops channels 0-3 calling set_channel_word_24cd ($E5BF) with
; zero.
;
; IT DOES NOT SWITCH THE OUTPUTS OFF, and this firmware used to. That was a
; defect and it is now gone. Reading $C6EA instruction by instruction: not
; one of them reaches a channel latch. Its channel loop calls
; set_channel_word_24cd ($E5BF), which stores a word at $24CD+2n and calls
; output_dac_update ($E4D0); output_dac_update maps the channel to parameter
; ids $10-$13 - the four PHASE registers - and adds $24C5+2n, the programmed
; phase, to $24CD+2n. So $24CD is a per-channel PHASE OFFSET and the loop
; zeroes it. The name output_dac_update is this project's own inference and
; is misleading: there is no DAC in it.
;
; What stood here instead opened all four output relays. The stock calls this
; routine from seven sites - every entry into and every exit from a sequence
; mode - so that killed the operator's outputs on every mode change, and
; clicked four relays doing it. A tone sequence entered and left would have
; left the instrument silent with no indication why.
;
; ptm_outputs_disable clears CRX6, the interrupt-enable bit, on all three
; timers, while tick_remove reaches only timer 2 through seq_timer_stop. That
; is enough here, and by enumeration rather than by luck: PTM_IRQ_ENABLE is
; set in exactly one place in this firmware, PTM_SEQ_RUN in modules/timer.s,
; which is timer 2. `grep -rn PTM_IRQ_ENABLE modules/*.s` returns four hits -
; that one, and the three clears in nmi_silence above. Timers 1 and 3 never
; have an interrupt armed, so there is nothing on them to silence.
;
; The rest is that firmware's bookkeeping in its own RAM, and copying a bit
; whose meaning is not established would be superstition rather than
; compatibility. Two of them are worth naming, because "left out" should not
; hide a fact:
;
;   bit 7 of the keypad-column shadow is CLEARED by $C6EA and set by nothing
;   in any of the five images - every store to kbd_col_shadow was scanned for
;   a preceding ORA/ORB of $80 or $C0 and there is none - so the clear has
;   nothing to clear, in the stock as much as here;
;
;   bits 6 and 7 of $0900 are the two common/hardware.inc records as NOT
;   ESTABLISHED, and this firmware does not write $0900 at all.
;
; THE PHASE OFFSET IS HERE NOW, and this paragraph used to say it was not:
; it read "this firmware has no phase offset ... and OPEN.txt carries it as
; outstanding work", and OPEN.txt carries no such row - `grep -n phase_offset
; hp8904a-rewrite/OPEN.txt` finds nothing. It went stale when phase.s grew
; phase_offset, phase_offset_compute and phase_offset_update, and a comment
; that names a file as holding a claim the file does not hold is worse than
; no comment. What is true is in phase_offset_clear_all's own header.
;
; $E5BF's four other callers in the stock are all on a2u13_page0, reached as
; the bare address `lbsr $e5bf`, and they set the offset from
; scale_channel_value_by_6_or_7 ($E8A7) for a channel whose destination is a
; modulation one and clear it otherwise - so a modulator carries a phase
; offset. $E8A7 builds it from the 3-byte slots at $2492-$249D and a compare
; against $257F, and what those hold is not established by this ROM.
;
; RESETTING THE CHIP LOSES THE OPERATOR'S CHANNEL SETTINGS. That is not an
; oversight and it is what the stock does: dds_params_reset ($DF17) rebuilds
; the whole parameter block. A sequence mode takes the channels over, so
; entering or leaving one is exactly where the instrument should go back to a
; state somebody can reason about.
; ---------------------------------------------------------------------------

instrument_preset
                lbsr    tick_remove             ; nothing advances any more,
                                                ; and the callback pointer is
                                                ; cleared with the arm
                lbsr    dds_reset               ; the chip back to the state
                                                ; power-on leaves it in

                clr     >hop_latch              ; THE HOP OUTPUT LATCH. Its
                                                ; only other writer is the
                                                ; tone player, which is the
                                                ; arrangement the stock has:
                                                ; seq_step_advance ($42B1)
                                                ; stores the step there and
                                                ; instrument_preset clears it.
                clr     >digital_in             ; and the digital port, which
                clr     >last_error             ; $C721 CLR >$23DE: a preset
                                                ; forgets the last error - the
                                                ; instrument's reads 0 after a
                                                ; mode entry (seed 13 step 24)
                                                ; the stock's preset also
                                                ; clears - the one write this
                                                ; firmware makes to $0600,
                                                ; and it is a clear rather
                                                ; than data

                lbsr    led_line6_assert        ; $C6EA does this too, at
                                                ; $C738 through
                                                ; set_flag7_and_led6_off
                                                ; ($DB5C)

                lbra    phase_offset_clear_all  ; AND THE FOUR PHASE OFFSETS,
                                                ; which is the whole of
                                                ; $C6EA's channel loop: it
                                                ; calls set_channel_word_24cd
                                                ; ($E5BF) with zero for each
                                                ; of channels 0-3, and $E5BF
                                                ; stores into $24CD+2n and
                                                ; re-applies the phase.


; ---------------------------------------------------------------------------
; foreground_tick - drop a sequence whose page has been switched away
;
;   uses:  A, B, X
;
; IT NO LONGER RUNS ANYTHING. The player runs from nmi_handler's jump into its
; own body, on timer 2,
; which is where the instrument's own sequence clock is. What is left here is
; the one job that must NOT happen at interrupt level.
;
; Both players live on A2U13 pages, and the window holds one page at a time.
; If the mapped page changes while a sequence is installed, the callback
; pointer addresses whatever now sits at that address - so the tick has to be
; given up. That is a change of state: it clears the arm, the pointer and the
; hardware enable, and doing it from an interrupt that can land between any
; two instructions of tick_install would leave the two disagreeing about
; whether a sequence is running.
;
; So the handler only SKIPS a tick whose page is not mapped, and this removes
; the tick properly, on the foreground's own stack, between operations.
; ---------------------------------------------------------------------------
foreground_tick
                ldx     >tick_callback          ; nothing installed, nothing
                beq     foreground_tick_done    ; to give up. NOT what
                                                ; nmi_callback holds, which a
                                                ; switched-out page turns to
                                                ; nmi_tick_hold - the case
                                                ; this is for

                cmpx    #$8000
                bhi     foreground_tick_done    ; above the window: A2U12,
                                                ; always mapped, never stale
                lda     >tick_page
                cmpa    >current_page
                beq     foreground_tick_done    ; still the right page
                lbsr    tick_remove             ; its page is gone; so is it
foreground_tick_done
                rts

; ---------------------------------------------------------------------------
; tick_install / tick_remove - start and stop a sequence
;
;   tick_install entry: X = the player, D = the first step's period in counts
;                       of ten microseconds
;   uses:  A, B, X
;
; A screen that starts a sequence installs; stopping removes. Two routines
; rather than one with a zero argument, because "remove" written as "install
; nothing" is the kind of call that gets read as a mistake and helpfully
; corrected.
;
; THE PERIOD IS AN ARGUMENT NOW, and has to be: timer 2 counts out one step
; and interrupts, so starting a sequence means saying how long its first step
; is. Every step after that is set by the player itself, which is how the
; stock does it - seq_step_advance ($42B1) reloads timer 2 from the step it
; has just started.
;
; THE POINTER GOES IN BEFORE THE HARDWARE IS STARTED. The other order leaves a
; window where the timer can time out with nothing installed to run. The
; player goes into nmi_callback itself - the handler jumps straight to it -
; and into tick_callback, which is the foreground's record of what is
; installed: tick_arm_update puts it back after a page switch and
; foreground_tick removes it when its page has gone.
; ---------------------------------------------------------------------------
tick_install
                stx     >tick_callback
                pshs    a,b                     ; the period, while the
                                                ; bookkeeping is done
                lda     >current_page           ; AND WHICH PAGE IT IS ON, so
                sta     >tick_page              ; a page switch can tell a
                                                ; player that is still mapped
                                                ; from one switched out
                stx     >nmi_callback           ; the body, jumped to from the
                                                ; next interrupt on
                puls    a,b
                lbra    seq_timer_start

; ---------------------------------------------------------------------------
; tick_hold - drop ticks while the page window moves
;
;   uses:  nothing - X is pushed and pulled, CC is not promised
;
; page_select_and_verify calls this before it writes the latch. Whatever was
; in nmi_callback, a tick landing from here until tick_arm_update is cleared
; and dropped by nmi_tick_hold instead of being jumped into a page that may no
; longer be the one mapped.
; ---------------------------------------------------------------------------
tick_hold
                pshs    x
                ldx     #nmi_tick_hold
                stx     >nmi_callback
                puls    x,pc

; ---------------------------------------------------------------------------
; tick_arm_update - put the installed player back if its page is the one mapped
;
;   uses:  A
;
; X is pushed and pulled and B is not touched, so page_select_and_verify's
; own contract stands. Three outcomes, each one STX into nmi_callback:
; nothing installed puts nmi_tick_idle there, a player whose page is not
; current_page leaves nmi_tick_hold, and a player whose page is mapped goes
; back in.
;
; A SINGLE-SHOT RUN REMOVES ITSELF FROM INSIDE THE INTERRUPT (digital_advance
; calls tick_remove), and that can land between the load of tick_callback
; here and the store. The store would then put back a body tick_remove had
; just taken out. So tick_callback is read again after the store: zero means
; tick_remove ran in between, and idle goes in over it. A removal after that
; second read writes idle itself.
; ---------------------------------------------------------------------------
tick_arm_update
                pshs    x
                ldx     >tick_callback
                beq     tick_arm_update_idle
                lda     >tick_page
                cmpa    >current_page
                bne     tick_arm_update_hold
                stx     >nmi_callback           ; the player, mapped
                ldx     >tick_callback          ; and still installed?
                bne     tick_arm_update_done
tick_arm_update_idle
                ldx     #nmi_tick_idle
                stx     >nmi_callback
tick_arm_update_done
                puls    x,pc
tick_arm_update_hold
                ldx     #nmi_tick_hold
                stx     >nmi_callback
                puls    x,pc

tick_remove
                lbsr    seq_timer_stop          ; the hardware stops asking
                ldx     #nmi_tick_idle          ; before the player goes, so
                stx     >nmi_callback           ; no tick is jumped into a
                ldx     #$0000                  ; player that has been taken
                stx     >tick_callback          ; out
                rts

; ---------------------------------------------------------------------------
; scratch_reset - clear the scratch variables that index something
;
;   uses:  A, B, X
;
; SCRATCH IS IN BATTERY-BACKED RAM because there is no other RAM on this
; board. Nothing in it is zero at power-on; it holds whatever the firmware
; before it left there, which after a ROM change is another firmware's data
; entirely.
;
; That is harmless for a variable that is written before it is read. It is
; NOT harmless for one that INDEXES something: nav_top indexes a four-entry
; stack and an uncleared $8A put a write on the serial number, on the
; operator's first keystroke.
;
; So every index is cleared here, and the list is the whole of scratch rather
; than the ones somebody thought of. Clearing all of it costs 896 stores at
; power-on - under a millisecond - and removes the entire class.
;
; live_setting is NOT cleared. It is the instrument's saved state and special
; function 0 exists to restore it across a power cycle;
; channel_records_init handles it, under the operator's own preference.
; ---------------------------------------------------------------------------
scratch_reset
                ldx     #SCRATCH_BASE
scratch_reset_byte
                clr     ,x+
                cmpx    #live_setting           ; up to the saved state, not
                blo     scratch_reset_byte      ; through it
                rts

; ---------------------------------------------------------------------------
; boot_report_faults - say what the power-on self-test found, and stop
;
;   entry: selftest_result holds a bit per check that PASSED
;   uses:  A, B, X, Y, U
;
; A FAULT WAS FOUND AND NEVER REPORTED. selftest_run stored its answer in
; selftest_result and the boot path read exactly one bit of it - SELFTEST_SIG,
; to decide whether the saved preferences could be trusted. A failed ROM
; checksum or a failed RAM test was recorded and then ignored, so an
; instrument with a bad EPROM or a dead battery booted to its banner and
; looked healthy.
;
; The stock does not let that happen. foreground_main_loop ($83A0) builds a
; number from three bits of the event_flags2 high byte the moment power_on_init
; returns - bit 6 (the RAM walk at $DC85) weighted 4, bit 5 (the A2U12 sum at
; $DCA9) weighted 2, bit 4 (the page sums at $DCD2) weighted 1 - and if it is
; not zero it calls error_report_beep ($C3FE) with $0B, paints
; hardware_error_banner_text ($EA72), 'Hardware error    reported on power
; up!', writes the number into the gap at column $10, paints $EE1F, 'Press any
; key to reset and continue.', and then LOOPS AT $8467 until a key arrives.
;
; THE SAME WEIGHTS, so that a number read off this display means what the
; service manual's table says it means. This firmware's result byte records
; passes rather than failures - a zero is then unambiguously bad, whichever
; way somebody reads it - so the bits are inverted here on the way out.
;
; SELFTEST_SIG IS NOT IN THE NUMBER, and the stock has no bit for it either.
; A signature that does not match is not a hardware fault: it means the
; battery-backed bytes are another firmware's or a fresh board's, which the
; path above already handles by clearing the preferences and writing the
; signature. Reporting it as a fault would send an engineer looking for a
; broken part.
;
; IT STOPS HERE. An instrument whose ROM does not sum or whose RAM does not
; hold a complement is not one to carry on booting: the next thing the boot
; path does is read that RAM for the serial, the options and the operator's
; saved state. Holding until a key is pressed is the stock's behaviour and it
; is also the safe one.
; ---------------------------------------------------------------------------
FAULT_RAM       equ     4               ; the weights foreground_main_loop
FAULT_ROM       equ     2               ; ($83A0) uses at $83C4, $83DA and
FAULT_PAGE      equ     1               ; $83F0
FAULT_COLUMN    equ     $10             ; where the stock writes the number
                                        ; into the banner's gap, from the
                                        ; lcd_write_clipped at $845B

boot_report_faults
                clrb                            ; B = the fault number
                lda     >selftest_result
                bita    #SELFTEST_RAM           ; a bit that is CLEAR is a
                bne     boot_fault_rom          ; check that FAILED
                addb    #FAULT_RAM
boot_fault_rom
                bita    #SELFTEST_ROM
                bne     boot_fault_page
                addb    #FAULT_ROM
boot_fault_page
                bita    #SELFTEST_PAGE
                bne     boot_fault_done
                addb    #FAULT_PAGE
boot_fault_done
                tstb
                bne     boot_fault_show
                rts                             ; everything passed

boot_fault_show
                pshs    b                       ; the number, for the digits
                lda     #LCD_LINE1
                ldx     #boot_fault_banner
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write
                lda     #LCD_LINE2
                ldx     #boot_fault_prompt
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write

                ; THE NUMBER INTO THE GAP, which is why the banner carries
                ; four spaces in the middle of a sentence: the stock's line is
                ; 'Hardware error    reported on power up!' and it writes two
                ; characters at column $10.
                clr     >math_work
                clr     >math_work+1
                puls    b
                stb     >math_work+2
                ldx     #math_work
                lbsr    uint24_to_text          ; X = the digits, B = how many
                lbsr    text_trim
                lda     #LCD_LINE1+FAULT_COLUMN
                lbsr    lcd_write

                lbsr    beep_now                ; AUDIBLE WHATEVER SPECIAL
                                                ; FUNCTION 2 SAYS. That
                                                ; preference lives in the RAM
                                                ; this may be reporting as
                                                ; broken; see beep_now in
                                                ; modules/errors.s.
boot_fault_wait
                lbsr    keypad_any              ; and hold. The stock loops at
                beq     boot_fault_wait         ; $8467 until a key arrives,
                rts                             ; and this is not an
                                                ; instrument to carry on
                                                ; booting quietly

boot_fault_banner
                fcc     "Hardware error    reported on power up! "
boot_fault_prompt
                fcc     "Press any key to reset and continue.    "
