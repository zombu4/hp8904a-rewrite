; ===========================================================================
; abi_table.s - the jump table itself
;
; Sits at ABI_BASE and must stay there: every paged ROM is built against
; these addresses. The order here IS the interface, and it matches abi.inc
; slot for slot - hp8904a-rewrite/tests/test_abi_table.py checks that they agree,
; because a table and a header that drift apart send every paged call one
; routine sideways.
; ===========================================================================

; Padded up to ABI_BASE rather than ORG'd there. An `org` starts a new
; section, and a raw output format concatenates sections rather than placing
; them - so the table landed immediately after the code instead of at $F000,
; and the two assemblers disagreed by 162 bytes about where everything was.
; Filling keeps the image one linear span, which is what a ROM image is.
                fill    $FF,ABI_BASE-*

                jmp     lcd_write
                jmp     lcd_blank
                jmp     lcd_cursor
                jmp     lcd_clear
                jmp     keypad_read
                jmp     uint24_to_text
                jmp     text_trim
                jmp     byte_to_hex
                jmp     add24
                jmp     sub24
                jmp     copy24
                jmp     mul16
                jmp     div16
                jmp     entry_begin
                jmp     entry_digit
                jmp     entry_value
                jmp     entry_render
                jmp     menu_open
                jmp     menu_next
                jmp     menu_previous
                jmp     error_raise
                jmp     dds_write
                jmp     dds_read
                jmp     channel_valid
                jmp     unit_apply
                jmp     abi_withdrawn           ; was event_post. The queue had
                                                ; no producer and no consumer and
                                                ; is gone; the slot stays, because
                                                ; an index once given out is
                                                ; permanent.
                jmp     delay_ms
                jmp     label_find              ; 27 the shared name table,
                                                ;    which lives here so the
                                                ;    four pages need not each
                                                ;    carry the eighteen names
                jmp     label_is_modulation     ; 28
                jmp     freq_set                ; 29 the three settings a
                jmp     ampl_set                ; 30 channel screen commits.
                jmp     phase_set               ; 31 Each validates, stores
                                                ;    and applies, so a page
                                                ;    cannot store a value the
                                                ;    hardware never received.
                jmp     screen_install          ; 32 a paged screen takes the
                                                ;    keys the same way an
                                                ;    A2U12 one does
                jmp     key_digit               ; 33 the digit lookup, which
                                                ;    is a table and not a
                                                ;    range test
                jmp     channel_valid           ; 34 a second slot for the
                                                ;    same routine: slot 23
                                                ;    already reaches it, and
                                                ;    an index once given out
                                                ;    is permanent, so this is
                                                ;    an alias rather than a
                                                ;    renumbering
                jmp     error_beep              ; 35
                jmp     screen_take_dismiss     ; 36 a paged reporting screen
                                                ;    takes the keys the same
                                                ;    way an A2U12 one does
                jmp     entry_begin_hex         ; 37 the paged editors take
                jmp     entry_begin_decimal     ; 38 hex or decimal fields,
                jmp     hex_to_nibble           ; 39 and need the same entry.
                                                ; NO SCREEN CALLS THIS. The
                                                ; three that did were handing
                                                ; it a key code where it wants
                                                ; an ASCII character, so no
                                                ; digit could be typed on any
                                                ; of them; they call
                                                ; ABI_key_digit now. The slot
                                                ; stays because this table's
                                                ; own rule is that an index,
                                                ; once given out, is permanent
                                                ; - renumbering it would make
                                                ; every paged image call the
                                                ; wrong routine.
                                                ;    buffer A2U12's screens
                                                ;    use - one buffer, so a
                                                ;    field cannot be half in
                                                ;    each
                jmp     tick_install            ; 40 a running sequence asks
                jmp     tick_remove             ; 41 the foreground for the
                                                ;    timebase, and gives it
                                                ;    back when it stops. Both
                                                ;    sequence modes live in
                                                ;    paged ROM and the tick
                                                ;    is polled in A2U12.
                jmp     freq_program            ; 42 the DTMF and tone players
                                                ;    program a frequency
                                                ;    without validating it -
                                                ;    the values come from
                                                ;    tables, not from a keypad
                jmp     channel_latch_rmw       ; 43 and gate the output
                                                ;    through the latch shadow,
                                                ;    which is the only safe
                                                ;    way to touch a write-only
                                                ;    latch
                jmp     channel_select          ; 44 validates a channel AND
                                                ;    selects it, so the check
                                                ;    and the store cannot
                                                ;    drift apart

                jmp     mod_route               ; 45 the destination field on
                jmp     mod_disconnect          ; 46 the channel screen is
                                                ;    what routes a modulator
                                                ;    to Channel A, and it
                                                ;    lives in a paged image

                jmp     wave_program            ; 47 the waveform field on the
                                                ;    channel screen, which is
                                                ;    in a paged image

                jmp     port_route              ; 48 which channel feeds which
                jmp     port_disconnect         ; 49 socket - the other half
                                                ;    of what a destination
                                                ;    means, and the half that
                                                ;    was doing nothing

; ---------------------------------------------------------------------------
; abi_withdrawn - what a retired slot points at
;
;   uses:  A, B, X
;
; Raises an error and returns. A page built against an older table that calls
; a withdrawn slot gets a reported fault instead of whatever now occupies the
; address, which is the whole reason indices here are never reused.
; ---------------------------------------------------------------------------
                jmp     destn_is_output         ; 50 the routing pair, moved
                jmp     destn_apply             ; 51 into the always-mapped
                                                ; image so register_apply can
                                                ; put a recalled setup's
                                                ; destination back on the
                                                ; hardware. A page cannot be
                                                ; called from A2U12, and only
                                                ; one page is mapped at a
                                                ; time, so the logic had to
                                                ; live where both callers
                                                ; reach it. APPENDED, never
                                                ; inserted - this table's
                                                ; indexes are permanent.
                jmp     dds_reg_name            ; 52 the chip's forty-two
                                                ; register names, read out of
                                                ; the stock ROM's own table.
                                                ; Page 3's screen had its own
                                                ; copy of an invented eight,
                                                ; and bounded its index
                                                ; against forty-two while
                                                ; indexing eight.
                jmp     lcd_write_line          ; 53 write a line and blank
                                                ; the rest of it, so a short
                                                ; message cannot leave the
                                                ; previous screen's text
                                                ; behind it
                jmp     hop_field_commit        ; 54 what one stored field of
                                                ; a hop slot sends the chip:
                                                ; A = the field, B = the slot.
                                                ; The slot for a frequency or
                                                ; a phase, and for a level
                                                ; nothing unless amplitude hop
                                                ; is on - the stock's three
                                                ; commit tails. It lives in
                                                ; the always-mapped image
                                                ; because it needs
                                                ; phase_to_code and
                                                ; ampl_hop_on, which do.
                jmp     lcd_blank_line          ; 55 clear one whole line. A
                                                ; paged screen that reports a
                                                ; refusal has to clear the
                                                ; line above it, or its
                                                ; message appears under
                                                ; whatever the last screen
                                                ; left there.
                jmp     hop_enable              ; 56 switch fast hop on or
                                                ; off. Nothing turned it on:
                                                ; the table could be edited
                                                ; and programmed, and register
                                                ; $1B was written exactly once
                                                ; - by the power-on reset,
                                                ; with the value that means
                                                ; OFF.
                jmp     instrument_preset       ; 57 quiesce the outputs.
                                                ; Every entry into and exit
                                                ; from a sequence mode calls
                                                ; it, which is where the stock
                                                ; calls its own from, and it
                                                ; is the only writer of the
                                                ; hop latch besides the tone
                                                ; player.
                jmp     seq_timer_period        ; 58 how long the step just
                                                ; started should last. The
                                                ; player is on a page and the
                                                ; timer is in A2U12, and this
                                                ; is called from inside the
                                                ; interrupt, so it has to be a
                                                ; jump table entry like
                                                ; everything else a page
                                                ; reaches.
                jmp     ampl_program_half       ; 59 the DTMF PAIR, each
                                                ; generator at half the set
                                                ; level: X = the record
                                                ; carrying it, A and B the two
                                                ; channels. Both, not one -
                                                ; apply_amplitude ($5F70) has
                                                ; the half in BOTH records
                                                ; before its second $C069, and
                                                ; $BE5C sums the socket out of
                                                ; the records, so the pair
                                                ; cannot be done a channel at
                                                ; a time.
                jmp     ampl_unit_for_destn     ; 60 which unit the AMPTD
                                                ; field carries, from the
                                                ; channel's destination - the
                                                ; screen needs it to choose
                                                ; the decimal places and the
                                                ; label.
                jmp     dds_mode_set            ; 61 turn one of the chip's
                                                ; modulation modes on or off,
                                                ; recording it in mode_flags
                                                ; because the control
                                                ; registers are write-only.
                jmp     phase_offset_update     ; 62 recompute the phase
                                                ; offset a modulator carries
                                                ; and re-send the phase. The
                                                ; destination decides whether
                                                ; there is one at all, and the
                                                ; destination is chosen on a
                                                ; page-0 screen, so this has
                                                ; to be reachable from there.

                jmp     key_refuse              ; 63 a key this screen cannot
                                                ; use, refused audibly. Four
                                                ; of the seven screens that
                                                ; used to ignore one are on
                                                ; A2U13 pages.

                jmp     ampl_autorange          ; 64 a level in V, mV or uV by
                                                ; magnitude, with the
                                                ; characters to show. The
                                                ; channel screen is on page 0.

                jmp     error_record            ; 65 record a fault and sound
                                                ; it without painting over the
                                                ; screen the operator is on.

                jmp     format_places           ; 66 a 24-bit value with a
                                                ; decimal point after N of its
                                                ; eight digits. It was the
                                                ; channel screen's own routine
                                                ; on page 0 until amplitude.s
                                                ; needed it.

                jmp     ampl_text               ; 67 the AMPTD field as
                                                ; characters, value and unit
                                                ; from one answer. Two screens
                                                ; show that field and only one
                                                ; of them is in this image.

                jmp     hop_program_raw         ; 68 one hop slot to the chip
                                                ; with the 12-bit codes given
                                                ; raw - the Manual CowChip
                                                ; screen's service write,
                                                ; which conversion would
                                                ; defeat.

                jmp     remote_queue            ; 69 stage a reply for the bus
                                                ; talker: X = text, B = length.
                                                ; The tone and digital screens
                                                ; answer '?' from their pages
                                                ; through this.
                jmp     dds_write_wide          ; 70 a width-4 register whole:
                                                ; B = the id, U -> three bytes
                                                ; high first (frequency.s).
                                                ; The Manual CowChip screen
                                                ; writes $27, the PLL divider,
                                                ; through this - freq_program
                                                ; masks ids to $08-$0B and
                                                ; the stock's $56FC writes
                                                ; every width-4 register.
                jmp     ampl_set_signed         ; 71 ampl_set with A = the
                                                ; level's sign, '+' or '-'
                                                ; (amplitude.s). The digital
                                                ; sequence screen's two dc
                                                ; levels carry one, as the
                                                ; stock's do through [$3CB2]
                                                ; at $4CF1, and a '-' level
                                                ; reaches the chip as the
                                                ; stock's scale_to_dds_code
                                                ; ($D4E7) and program_dds_levels
                                                ; ($5306-$5343) fold it.
                jmp     dds_phase_reset         ; 72 the automatic phase-reset
                                                ; pulse on register $26 -
                                                ; dds_reg26_bit3_pulse ($DE7F)
                                                ; behind the special-function
                                                ; veto of $DEB6 (dds.s). The
                                                ; tone and DTMF screens' hand
                                                ; steps reach it here; each
                                                ; had grown its own copy of
                                                ; the pulse because no slot
                                                ; existed, and three copies of
                                                ; one register sequence is the
                                                ; shape that drifts.
                jmp     entry_backspace         ; 73 the last digit out of the
                                                ; shared entry field
                                                ; (entry.s): the stock's
                                                ; entry_backspace ($B2CD),
                                                ; which every entry's
                                                ; BACKSPACE reaches through
                                                ; numeric_entry_key_handler
                                                ; at $B4B9. No slot reached
                                                ; it, so no paged screen
                                                ; could take the key.
                jmp     ampl_sum_exceeds        ; 74 the stock's
                                                ; channel_sum_exceeds_ref
                                                ; ($B8CC), in amplitude.s:
                                                ; B = the channel, X -> a
                                                ; 24-bit value, U -> the
                                                ; 24-bit reference; carry
                                                ; set when the value plus
                                                ; the levels of the channels
                                                ; sharing that channel's
                                                ; destination is over it.
                                                ; store_hop_amptd ($4CD5)
                                                ; runs it at $4CF6 while
                                                ; amplitude hop is on, and
                                                ; the hop screen is on page
                                                ; 0.
                jmp     freq_in_range           ; 75 the stock's
                                                ; check_freq_limit ($63D2)
                                                ; without its error code
                                                ; (frequency.s): X = the
                                                ; channel record, U -> a
                                                ; 24-bit value; Z set when
                                                ; the value is within that
                                                ; channel's ceiling.
                                                ; set_hop_function_enable
                                                ; ($4984) runs it for
                                                ; channel 0 at $49F8 and
                                                ; $4A25, and the hop screen
                                                ; is on page 0.
                jmp     hop_field_max           ; 76 the stock's
                                                ; find_max_channel_field
                                                ; ($E962) (amplitude.s): A =
                                                ; HOP_FREQ or HOP_AMPL, Y ->
                                                ; that field of the slot
                                                ; holding the largest value.
                                                ; $4984 calls $E962 at $49E4
                                                ; with 6 and at $4AAD with
                                                ; 4.
                jmp     ampl_hop_on             ; 77 channel 0's level path
                                                ; once amplitude hop is on
                                                ; (amplitude.s): $4984's
                                                ; dispatch_channel_function
                                                ; ($C069) call at $4B53 with
                                                ; channel 0 and $EA58, as
                                                ; its header sets out.
                jmp     filter_recompute_all    ; 78 the stock's
                                                ; recompute_channel_byte_24ec
                                                ; ($F7EC) (screens_main.s):
                                                ; every fitted channel's
                                                ; filter line re-derived from
                                                ; the records and the hop
                                                ; state and written only
                                                ; where it changed, as $F692
                                                ; writes only on a change.
                                                ; Page 0 calls it where the
                                                ; stock calls $F7EC: the
                                                ; Freq Hop switch ($4A5F), a
                                                ; hop frequency applied
                                                ; ($4C97), a frequency
                                                ; committed ($6514), a
                                                ; waveform ($68B2) and a
                                                ; destination ($7BD2, $7ED8).
                jmp     ampl_set_direct         ; 79 the digital sequence
                                                ; screen's level
                                                ; (amplitude.s): the stock's
                                                ; enter_level_value ($4CDA)
                                                ; stores and runs
                                                ; program_dds_levels ($5223),
                                                ; which codes BOTH levels
                                                ; against ONE exponent
                                                ; ($5326) and never calls
                                                ; channel_apply_and_propagate
                                                ; ($BE5C). Y carries the
                                                ; other of the pair;
                                                ; ampl_set_signed
                                                ; became that $C069 path,
                                                ; which writes zero for a
                                                ; channel the digital mode's
                                                ; preset has routed Off.

; --- 80-87: the raw programming path, for the FM stereo composite screen ---
;
; A paged screen could already reach freq_program (42) and dds_write_wide
; (70), but not the phase or level equivalents, so it could set a frequency
; and nothing else. These eight close that.
;
; They are the RAW tier deliberately. The set tier transforms for a
; modulation destination - freq_set sends the two's complement and phase_set
; sends 3600-phase - and the stereo composite has no modulator: it wants the
; literal carrier+tone, carrier-tone, and the literal 900 and 2700 tenths of
; a degree. See docs/stereo-abi.md.
                jmp     phase_to_code           ; 80 tenths of a degree to the
                                                ; chip's twelve-bit phase,
                                                ; with NO modulator offset
                                                ; and no negation: X in, X out
                jmp     phase_program           ; 81 X = the twelve-bit code,
                                                ; B = the channel. Writes
                                                ; BUFLAT3, BUFLAT2 and the
                                                ; $10+channel latch
                jmp     ampl_program            ; 82 X = a twelve-bit
                                                ; mantissa, B = the channel.
                                                ; The level register alone -
                                                ; it does not touch the
                                                ; attenuator, which is what
                                                ; lets one range serve four
                                                ; channels
                jmp     ampl_scale              ; 83 U -> a 24-bit level in
                                                ; microvolts; X = the
                                                ; mantissa, B = the exponent
                jmp     ampl_range_write        ; 84 A = the exponent, B = the
                                                ; channel. Ends in a 6 ms
                                                ; settle, so a burst calls it
                                                ; ONCE
                jmp     dds_phase_reset_now     ; 85 the $26 bit 3 pulse with
                                                ; no special-function veto -
                                                ; HP's $DF06. Until it runs,
                                                ; the phases programmed above
                                                ; have no defined relation
                jmp     ampl_blank              ; 86 B = the channel: mute,
                                                ; 5 ms settle
                jmp     ampl_unblank            ; 87 B = the channel: 5 ms
                                                ; settle, then release, but
                                                ; only if CHAN_STATE bit 0
                                                ; says the operator has that
                                                ; output on
                jmp     ampl_q16_div1000        ; 88 D = tenths of a percent,
                                                ; 0 to 999; X = that over
                                                ; 1000 as a Q16 fraction
                jmp     ampl_fixmul_hi          ; 89 D and X = two factors;
                                                ; X = round(D * X / 65536).
                                                ; With 88 above it, this is
                                                ; how the stereo screen takes
                                                ; the pilot's share of the
                                                ; composite without forming a
                                                ; product that overflows
                                                ; sixteen bits
                jmp     unit_label              ; 90 B = a unit code 0 to 15;
                                                ; X = the three characters
                                                ; naming it. The stock's
                                                ; lcd_write_unit_label
                                                ; ($ABEF) and its table at
                                                ; $EEEE, which every value
                                                ; field on a paged screen
                                                ; needs and none could reach
                jmp     entry_units             ; 91 A = the DDRAM column of a
                                                ; numeric field's units label,
                                                ; B = how many characters the
                                                ; first accepted key blanks.
                                                ; The stock's $23AF and the
                                                ; width its units class picks
                                                ; at $AD3A, written as blanks
                                                ; by $B524-$B538 the first time
                                                ; a key is taken
                jmp     unit_blank              ; 92 B = a unit code 0 to 15;
                                                ; B = how many characters of
                                                ; its label a typed key blanks.
                                                ; The width the stock's units
                                                ; class chooses at $AD3A,
                                                ; indexed by unit rather than
                                                ; by class
                jmp     format_fixed            ; 93 X = a 24-bit value in
                                                ; memory, A = how many digits,
                                                ; B = how many leading zeros
                                                ; may go, format_point = the
                                                ; point's index, format_trim
                                                ; to blank a trailing zero;
                                                ; format_text holds A+1
                                                ; characters. The stock's
                                                ; $CCFF and $CD50 as one call
                jmp     service_back_handler    ; 94 leave this screen for the
                                                ; one that opened it - what
                                                ; LOCAL does from the
                                                ; foreground, and what the
                                                ; stock's Exit softkey reaches
                                                ; through return_to_main_menu
                                                ; ($8E62)
                jmp     lcd_write_line_raw      ; 95 a whole line painted OVER
                                                ; the shadow instead of into
                                                ; it, for a flash that has to
                                                ; leave the screen underneath
                                                ; recoverable - the stock's
                                                ; lcd_write_string_at ($D8A5)
                jmp     error_show              ; 96 the last error flashed for
                                                ; three seconds over whatever
                                                ; is showing, then the screen
                                                ; underneath put back -
                                                ; show_last_error_screen
                                                ; ($C418). The digital sequence
                                                ; screen answers shifted INC
                                                ; SET with it, as arm [15] of
                                                ; $6E67 does
                jmp     destn_dc_shared         ; 97 A = the channel to leave
                                                ; out, B = a destination code;
                                                ; carry SET when another dc
                                                ; channel is already routed
                                                ; there. dc_destination_conflict
                                                ; ($7736), which the waveform
                                                ; validation on page 0 needs
                jmp     entry_point             ; 98 the decimal point key, for
                                                ; the screens in the paged
                                                ; images - the entry layer is
                                                ; in A2U12
                jmp     unit_div_ten            ; 99 a 24-bit value divided by
                                                ; ten, for a screen whose own
                                                ; scaling is not the unit
                                                ; table's and which still has
                                                ; to honour a typed point
                jmp     unit_scale_decades      ; 100 a value scaled by ten to
                                                ; the power (B - entry_frac),
                                                ; which the radian entries need
                                                ; without a unit code
                jmp     key_hex_digit           ; 101 B = a key code: 0 to 15
                                                ; and carry clear if it is one
                                                ; of the sixteen characters of
                                                ; column 5 of keypad_char_table
                                                ; ($EF94), carry set and B
                                                ; untouched if it is not. The
                                                ; sequence screens' two
                                                ; single-character fields are
                                                ; hexadecimal and live in a
                                                ; paged image
                jmp     channel_restore_destinations ; 102 the destinations
                                                ; a cold start parked, put back
                                                ; and routed
                jmp     channel_reapply_all     ; 103 every channel's record
                                                ; put back on the hardware.
                                                ; The sequence modes need it
                                                ; from a paged image: entering
                                                ; one presets the chip, and
                                                ; the stock follows its preset
                                                ; with reapply_all_channels
                                                ; ($C5B1) at every one of
                                                ; those entries
                jmp     channel_records_init    ; 104 the four channel
                                                ; records back to their
                                                ; power-on defaults, which is
                                                ; what a sequence mode entry
                                                ; does before it reapplies:
                                                ; init_channel_blocks ($C4F0),
                                                ; called from seq_mode_defaults
                                                ; ($5224) at $5239
                jmp     filter_force            ; 105 A = LATCH_FILTER or
                                                ; zero, B = the channel: that
                                                ; channel's filter byte forced
                                                ; and the line driven from it.
                                                ; set_channel_byte_24ec
                                                ; ($F713), which
                                                ; seq_mode_defaults ($5224)
                                                ; calls at $5378 with index 0
                                                ; and value 1
                jmp     channel_park_destinations ; 106 every destination
                                                ; out of the records and kept,
                                                ; which is the first pass of
                                                ; reapply_all_channels ($C5B1)
                                                ; at $C5E8-$C5F2. A sequence
                                                ; mode entry does it between
                                                ; the record reset and the
                                                ; apply, so the apply finds
                                                ; every channel Off
                jmp     ampl_reapply            ; 107 X = the record, B = the
                                                ; channel: that channel's
                                                ; stored level onto the chip
                                                ; by its unit, with no range
                                                ; check and no store -
                                                ; dispatch_channel_function
                                                ; ($C069), which the entry
                                                ; runs for channel 0 through
                                                ; apply_amplitude ($5F70) at
                                                ; $54E7
                jmp     remote_srq_event        ; 108 A = RMT_SRQ_SEQ_START
                                                ; or RMT_SRQ_SEQ_END: one of
                                                ; the two sequence status
                                                ; bits pulsed over the bus,
                                                ; gated on the instrument
                                                ; being remote. The stock's
                                                ; four sites are inside
                                                ; seq_output_set_running
                                                ; ($4702) and
                                                ; sequence_run_start_stop
                                                ; ($67A3), one start and one
                                                ; stop each, and both of
                                                ; those screens live in a
                                                ; paged image - so there was
                                                ; no way to reach remote.s
                                                ; and these four reports were
                                                ; the tail of the service
                                                ; request that was left out
                jmp     hop_addr_send           ; 109 the standing hop-RAM
                                                ; address out to register $15
                                                ; - write_reg15_nibble
                                                ; ($E7C4), an A2U12 routine
                                                ; with two callers in the
                                                ; instrument: the tail of
                                                ; reapply_all_channels
                                                ; ($C5B1) at $C6BB, which is
                                                ; resident, and
                                                ; apply_hop_addr_and_repaint
                                                ; ($4803), which is page 0
                jmp     hop_table_defaults      ; 110 the sixteen hop slots
                                                ; emptied and every one of
                                                ; them sent to the chip -
                                                ; dds_table_defaults ($E7F9).
                                                ; It is in A2U12 in the
                                                ; instrument and is here for
                                                ; the same reason: the cold
                                                ; boot runs it and boot code
                                                ; cannot call into a paged
                                                ; image. Channel
                                                ; Configuration's own entry
                                                ; ($528F at $53FC) is on page
                                                ; 0 and reaches it through
                                                ; this slot
                jmp     remote_query_field      ; 111 A = the stock's $2215:
                                                ; that field's value queued for
                                                ; the bus. The whole of
                                                ; gpib_query_value_response
                                                ; ($7B7A), which the page-0
                                                ; chain's request-$25 arm
                                                ; ($635E) reaches by asking
                                                ; call_routine_on_a2u13_page
                                                ; ($DB2B) for page 3. Here the
                                                ; renderers are in A2U12 beside
                                                ; the talker, and page 0 hands
                                                ; them the field id
                jmp     entry_cursor_on         ; 112 A = the DDRAM address of
                                                ; the armed field's first digit:
                                                ; the cursor there and on, unless
                                                ; remote. The LCD half of
                                                ; arm_numeric_entry_field ($AC35)
                                                ; at $AC98 and $ACA6, which page
                                                ; 0, 1, 2 and 3 all reach by LBSR
                jmp     entry_cursor_off        ; 113 the cursor off: $B3BA in
                                                ; entry_exit_restore_display
                                                ; ($B38B), which a paged screen
                                                ; reaches when it commits a
                                                ; digit or units key ($B586,
                                                ; $B5BA) or, on page 0, at
                                                ; entry_cfg_unsettable ($4F3B)
                jmp     entry_is_open           ; 114 Z clear when a field is
                                                ; armed: the $23A8 test at lb494
                                                ; ($B494), which the cursor bit
                                                ; answers - see entry.s
                jmp     entry_key_is_mapped     ; 115 B = a key code: Z clear
                                                ; when key_to_state_code or
                                                ; keymap_menu_msgs_19_1d maps
                                                ; it, which is when a service
                                                ; screen's handler hears it as a
                                                ; message and re-arms
                jmp     register_screen_open    ; 116 the Save prompt, for
                                                ; the pages' request-$21
                                                ; arms: l5dd9, $508C, $6B46
                jmp     register_apply          ; 117 a recalled register onto
                                                ; the hardware, relays and
                                                ; all: what each mode entry
                                                ; runs after its copy on
                                                ; reason 1 - $52FA-$5431 in
                                                ; enter_channel_config_mode,
                                                ; l53ee in sequence_mode_init,
                                                ; l71d6 in
                                                ; digital_sequence_mode_setup
                jmp     mode_enter_channel_config ; 118 Channel Configuration
                                                ; from the Channel Summary's
                                                ; ENTER, recorded as the
                                                ; active mode
                jmp     lcd_write_raw           ; 119 an entry's echo, to the
                                                ; glass and not the shadow, as
                                                ; lcd_write_string_at ($D8A5)
                                                ; writes the stock's
                jmp     banner_arm              ; 120 the walking star, for the
                                                ; Installed Options screen on
                                                ; page 3
                jmp     option_toggle           ; 121 one option flipped, the
                                                ; bank copy first
                jmp     options_clear_all       ; 122 every option off, the
                                                ; bank copy first
                jmp     relay_restore           ; 123 the relay exercise put
                                                ; back, however it is left

; THE TABLE ENDS ABOVE. What follows is BODY, not a slot, and a jmp appended
; after it would sit past those five bytes - which is the exact defect
; hp8904a-rewrite/tests/test_abi_table.py was written for. A new entry goes
; ABOVE this line.
abi_withdrawn
                ldb     #ERR_INTERNAL           ; not the operator's doing, and
                                                ; the generic value error said
                                                ; it was
                lbra    error_raise
