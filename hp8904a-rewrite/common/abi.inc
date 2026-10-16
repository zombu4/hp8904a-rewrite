; ===========================================================================
; abi.inc - the interface between A2U12 and the paged ROM
;
; A2U13's pages call into A2U12 constantly - for the display, the maths, the
; keypad, the menus - because only one page is mapped at a time and anything
; two pages both need has to live in the always-mapped image.
;
; THE STOCK FIRMWARE HAS NO INTERFACE. A2U13 calls 108 scattered addresses in
; A2U12, each one wherever that routine happened to land when the ROM was
; built. Move any of them and the paged ROM calls into the middle of
; something else, which is why the stock A2U12 cannot be relaid out without
; reburning A2U13 as well.
;
; This is a JUMP TABLE at a fixed address. Every entry is three bytes - a JMP
; to wherever the routine actually is - so the pages call a stable address
; and A2U12's internals move freely underneath. Three bytes and a few cycles
; per call, and in exchange the two ROMs stop being welded together.
;
; RULES FOR THIS TABLE:
;   - entries are only ever APPENDED. An index, once given out, is permanent:
;     a page built against an old table would otherwise call the wrong thing.
;   - a routine that is withdrawn keeps its slot, redirected to the error
;     reporter so the call is refused out loud. Handing the slot to something
;     else is how a stale call becomes silent wrong behaviour rather than a
;     reported fault.
;   - the table's address is fixed and checked by a test, because moving it
;     breaks every page at once.
; ===========================================================================

; LOWERED FROM $F000 ON 2026-09-18, and the reason is which half of the image
; has the room.
;
; The image is two regions with a boundary at this address: the core below it,
; the ABI table and the modules above it growing up to $FFEF where the
; self-test's compensation byte lives. Fill between the core's end and the
; table is CORE space - lowering the boundary is the only way to give it to the
; tail, because the tail is anchored at the top and grows down.
;
; That mattered when the register work - all of it in registers.s, which is
; above the table - had nowhere to go while 191 bytes of fill sat below. Three
; separate pieces of work hit that wall.
;
; $EF90 rather than $EF82, which is where the core actually ends: fourteen
; bytes of margin, because a boundary with none is one edit from refusing the
; build again.
;
; EVERY A2U13 PAGE MOVES WITH IT. Paged code reaches A2U12 only through this
; table, and those are absolute addresses - so all five images must be rebuilt
; and burnt AS A SET. docs/a2u12-space.md dismissed this when the only way to
; program a 27513 was a UV eraser; with a One ROM in the socket all four pages
; reflash over USB in seconds, and they are reflashed whenever A2U13 changes
; anyway.
ABI_BASE        equ     $EF90           ; well clear of the vectors at $FFF0
ABI_SLOT        equ     3               ; one JMP each

; The slots, by index. A page calls `lbsr ABI_lcd_write` and neither knows
; nor cares where lcd_write really is.
ABI_lcd_write       equ  ABI_BASE+0*ABI_SLOT
ABI_lcd_blank       equ  ABI_BASE+1*ABI_SLOT
ABI_lcd_cursor      equ  ABI_BASE+2*ABI_SLOT
ABI_lcd_clear       equ  ABI_BASE+3*ABI_SLOT
ABI_keypad_read     equ  ABI_BASE+4*ABI_SLOT
ABI_uint24_to_text  equ  ABI_BASE+5*ABI_SLOT
ABI_text_trim       equ  ABI_BASE+6*ABI_SLOT
ABI_byte_to_hex     equ  ABI_BASE+7*ABI_SLOT
ABI_add24           equ  ABI_BASE+8*ABI_SLOT
ABI_sub24           equ  ABI_BASE+9*ABI_SLOT
ABI_copy24          equ  ABI_BASE+10*ABI_SLOT
ABI_mul16           equ  ABI_BASE+11*ABI_SLOT
ABI_div16           equ  ABI_BASE+12*ABI_SLOT
ABI_entry_begin     equ  ABI_BASE+13*ABI_SLOT
ABI_entry_digit     equ  ABI_BASE+14*ABI_SLOT
ABI_entry_value     equ  ABI_BASE+15*ABI_SLOT
ABI_entry_render    equ  ABI_BASE+16*ABI_SLOT
ABI_menu_open       equ  ABI_BASE+17*ABI_SLOT
ABI_menu_next       equ  ABI_BASE+18*ABI_SLOT
ABI_menu_previous   equ  ABI_BASE+19*ABI_SLOT
ABI_error_raise     equ  ABI_BASE+20*ABI_SLOT
ABI_dds_write       equ  ABI_BASE+21*ABI_SLOT
ABI_dds_read        equ  ABI_BASE+22*ABI_SLOT
ABI_channel_valid   equ  ABI_BASE+23*ABI_SLOT
ABI_unit_apply      equ  ABI_BASE+24*ABI_SLOT
ABI_event_post      equ  ABI_BASE+25*ABI_SLOT
ABI_delay_ms        equ  ABI_BASE+26*ABI_SLOT
ABI_label_find      equ  ABI_BASE+27*ABI_SLOT
ABI_label_is_mod    equ  ABI_BASE+28*ABI_SLOT
ABI_freq_set        equ  ABI_BASE+29*ABI_SLOT
ABI_ampl_set        equ  ABI_BASE+30*ABI_SLOT
ABI_phase_set       equ  ABI_BASE+31*ABI_SLOT
ABI_screen_install  equ  ABI_BASE+32*ABI_SLOT
ABI_key_digit       equ  ABI_BASE+33*ABI_SLOT
ABI_channel_valid_2 equ  ABI_BASE+34*ABI_SLOT
ABI_error_beep      equ  ABI_BASE+35*ABI_SLOT
ABI_screen_take_dismiss equ ABI_BASE+36*ABI_SLOT
ABI_entry_begin_hex equ  ABI_BASE+37*ABI_SLOT
ABI_entry_begin_dec equ  ABI_BASE+38*ABI_SLOT
ABI_hex_to_nibble   equ  ABI_BASE+39*ABI_SLOT
ABI_tick_install    equ  ABI_BASE+40*ABI_SLOT
ABI_tick_remove     equ  ABI_BASE+41*ABI_SLOT
ABI_freq_program    equ  ABI_BASE+42*ABI_SLOT
ABI_channel_latch_rmw equ ABI_BASE+43*ABI_SLOT
ABI_channel_select  equ  ABI_BASE+44*ABI_SLOT
ABI_mod_route       equ  ABI_BASE+45*ABI_SLOT
ABI_mod_disconnect  equ  ABI_BASE+46*ABI_SLOT
ABI_wave_program    equ  ABI_BASE+47*ABI_SLOT
ABI_port_route      equ  ABI_BASE+48*ABI_SLOT
ABI_port_disconnect equ  ABI_BASE+49*ABI_SLOT
ABI_COUNT           equ  50
ABI_destn_is_output equ  ABI_BASE+50*ABI_SLOT
ABI_destn_apply     equ  ABI_BASE+51*ABI_SLOT
ABI_dds_reg_name    equ  ABI_BASE+52*ABI_SLOT
ABI_lcd_write_line  equ  ABI_BASE+53*ABI_SLOT
ABI_hop_field_commit equ ABI_BASE+54*ABI_SLOT   ; A = HOP_FIELD_*, B = the slot: dds.s hop_field_commit
ABI_lcd_blank_line  equ  ABI_BASE+55*ABI_SLOT
ABI_hop_enable      equ  ABI_BASE+56*ABI_SLOT
ABI_instrument_preset equ ABI_BASE+57*ABI_SLOT
ABI_seq_timer_period equ ABI_BASE+58*ABI_SLOT
ABI_ampl_program_half equ ABI_BASE+59*ABI_SLOT
ABI_ampl_unit_for_destn equ ABI_BASE+60*ABI_SLOT
ABI_dds_mode_set    equ  ABI_BASE+61*ABI_SLOT
ABI_phase_offset_update equ ABI_BASE+62*ABI_SLOT
ABI_key_refuse      equ  ABI_BASE+63*ABI_SLOT
ABI_ampl_autorange  equ  ABI_BASE+64*ABI_SLOT
ABI_error_record    equ  ABI_BASE+65*ABI_SLOT
ABI_format_places   equ  ABI_BASE+66*ABI_SLOT
ABI_ampl_text       equ  ABI_BASE+67*ABI_SLOT
ABI_remote_queue    equ  ABI_BASE+69*ABI_SLOT
ABI_hop_program_raw equ  ABI_BASE+68*ABI_SLOT
ABI_dds_write_wide  equ  ABI_BASE+70*ABI_SLOT   ; a width-4 register, B = id, U -> 3 bytes
ABI_ampl_set_signed equ  ABI_BASE+71*ABI_SLOT   ; ampl_set with A = the level's sign, '+' ($2B) or '-' ($2D)
ABI_dds_phase_reset equ  ABI_BASE+72*ABI_SLOT   ; the automatic $26 pulse, vetoed by special_flags bit 1
ABI_entry_backspace equ  ABI_BASE+73*ABI_SLOT   ; the last digit out of the shared entry: the stock's entry_backspace ($B2CD)
ABI_ampl_sum_exceeds equ ABI_BASE+74*ABI_SLOT   ; the stock's channel_sum_exceeds_ref ($B8CC): B = channel, X -> value, U -> reference; carry = over
ABI_freq_in_range   equ  ABI_BASE+75*ABI_SLOT   ; the stock's check_freq_limit ($63D2) without its error code: X = channel record, U -> value; Z = within the ceiling
ABI_hop_field_max   equ  ABI_BASE+76*ABI_SLOT   ; the stock's find_max_channel_field ($E962): A = HOP_FREQ or HOP_AMPL; Y -> the largest slot's field
ABI_ampl_hop_on     equ  ABI_BASE+77*ABI_SLOT   ; channel 0's level path once amplitude hop is on: $4984's $C069 (0, $EA58) call at $4B53
ABI_filter_apply    equ  ABI_BASE+78*ABI_SLOT   ; the stock's recompute_channel_byte_24ec ($F7EC): every fitted channel's filter line re-derived from the records and the hop state, written where it changed
ABI_ampl_set_direct equ  ABI_BASE+79*ABI_SLOT   ; the digital screen's level: enter_level_value ($4CDA) into program_dds_levels ($5223), coded with no $BE5C - X = record, U -> value, B = channel, A = the sign, Y = the OTHER of the mark/space pair, because $5223 programs both and puts them on one exponent
ABI_phase_to_code   equ  ABI_BASE+80*ABI_SLOT   ; X = tenths of a degree, 0 to 3599; X = the twelve-bit code. No modulator offset and no negation - phase_to_code_offset and phase_apply are the transforming ones
ABI_phase_program   equ  ABI_BASE+81*ABI_SLOT   ; X = the twelve-bit code, B = the channel: BUFLAT3, BUFLAT2 and the $10+channel latch
ABI_ampl_program    equ  ABI_BASE+82*ABI_SLOT   ; X = a twelve-bit mantissa, B = the channel: the level register alone, leaving the attenuator where it is, which is what lets one range serve four channels
ABI_ampl_scale      equ  ABI_BASE+83*ABI_SLOT   ; U -> a 24-bit level in MICROVOLTS; X = the mantissa $800-$FFF, B = the exponent 0-15
ABI_ampl_range_write equ ABI_BASE+84*ABI_SLOT   ; A = the exponent 0-15, B = the channel: the attenuator, bits 6:3 of that channel's latch, complemented. Ends in a 6 ms settle, so a burst calls it once
ABI_dds_phase_reset_now equ ABI_BASE+85*ABI_SLOT ; the $26 bit 3 pulse with no special-function veto, which is HP's $DF06 ($DEBE). Until it runs, phases programmed on different channels have no defined relation
ABI_ampl_blank      equ  ABI_BASE+86*ABI_SLOT   ; B = the channel: mute through LATCH_OUTPUT, 5 ms settle. Vetoed by special function 3
ABI_ampl_unblank    equ  ABI_BASE+87*ABI_SLOT   ; B = the channel: 5 ms settle then release, but only where CHAN_STATE bit 0 says the operator has that output on
ABI_ampl_q16_div1000 equ ABI_BASE+88*ABI_SLOT   ; D = a figure in tenths of a percent, 0 to 999; X = that over 1000 as a Q16 fraction. The stereo screen's pilot share is HP's $3C37 * $3C11 / 1000 at $6437, and this is the half of it that cannot overflow
ABI_ampl_fixmul_hi  equ  ABI_BASE+89*ABI_SLOT   ; D and X = two factors; X = round(D * X / 65536). fixmul_q16 ($D303) - the other half of that product
ABI_unit_label      equ  ABI_BASE+90*ABI_SLOT   ; B = a unit code 0 to 15; X = the three characters naming it. HP's lcd_write_unit_label ($ABEF) over the table at $EEEE
ABI_entry_units     equ  ABI_BASE+91*ABI_SLOT   ; A = the DDRAM column of a numeric field's units label, B = how many characters the first accepted key blanks. The stock's $23AF and the $23AE its units class chooses at $AD3A; $B524-$B538 writes the run
ABI_unit_blank      equ  ABI_BASE+92*ABI_SLOT   ; B = a unit code 0 to 15; B = how many characters of its label a typed key blanks. The width the stock's units class chooses at $AD3A, indexed by unit instead of by class
ABI_format_fixed    equ  ABI_BASE+93*ABI_SLOT   ; X = a 24-bit value in memory, A = how many digits, B = how many leading zeros may be blanked, format_point = the point's index, format_trim non-zero to blank a trailing zero; format_text holds A+1 characters. The stock's blank_leading_zeros ($CCFF) and format_with_decimal_point ($CD50) as one call
ABI_remote_srq_event equ ABI_BASE+108*ABI_SLOT  ; A = RMT_SRQ_SEQ_START or RMT_SRQ_SEQ_END: that status bit set, service requested if the mask asks for it, and the bit released again - the whole of report_error_and_pulse_status_bit ($9DD3) with code $00FF, gated on the instrument being remote. The four stock sites are the sequence start and stop legs of seq_output_set_running ($4702) and sequence_run_start_stop ($67A3), and both screens are paged, which is why this slot exists
ABI_hop_addr_send   equ  ABI_BASE+109*ABI_SLOT  ; the standing hop-RAM address out to register $15, its low nibble from hop_index and bit 4 from MODE_FLAG_DIGITAL. The stock's write_reg15_nibble ($E7C4), which lives in A2U12 with its other caller - the tail of reapply_all_channels ($C5B1) at $C6BB - and which apply_hop_addr_and_repaint ($4803) on page 0 reaches from there
ABI_hop_table_defaults equ ABI_BASE+110*ABI_SLOT ; the sixteen hop slots emptied and all sixteen sent to the chip. The stock's dds_table_defaults ($E7F9), first of reinit_channel_tables' ($C6C3) three and in A2U12 as this is, called from the cold boot and from enter_channel_config_mode ($528F) at $53FC - which is page 0, and this is how it gets there
ABI_ampl_reapply    equ  ABI_BASE+107*ABI_SLOT  ; X = the channel record, B = the channel: its stored level onto the chip by the record's unit, with no range check and no store. The stock's dispatch_channel_function ($C069), which a sequence-mode entry runs for channel 0 through apply_amplitude ($5F70) at $54E7 - the one channel whose level survives the entry
ABI_channel_park_destinations equ ABI_BASE+106*ABI_SLOT ; every destination out of the records and kept, ready for channel_restore_destinations to put back. The first pass of reapply_all_channels ($C5B1), $C5E8-$C5F2, which a sequence-mode entry runs between the record reset and the apply so that the apply finds every channel Off
ABI_filter_force    equ  ABI_BASE+105*ABI_SLOT  ; A = LATCH_FILTER or zero, B = the channel: that channel's stored filter byte forced to A and the line driven from it. The stock's set_channel_byte_24ec ($F713) falling into switch_channel_latch_bit0 ($F692), which seq_mode_defaults ($5224) calls at $5378 with index 0 and value 1
ABI_channel_records_init equ ABI_BASE+104*ABI_SLOT ; the four channel records back to their power-on defaults. The stock's init_channel_blocks ($C4F0), which seq_mode_defaults ($5224) calls at $5239 between its preset and its reapply - a sequence mode takes the channels over and starts them from the instrument's defaults, not from what the last mode left
ABI_channel_reapply_all equ ABI_BASE+103*ABI_SLOT ; every channel's record put back on the hardware - frequency, phase, waveform and destination, and NOT the output relay. The stock's reapply_all_channels ($C5B1), which it calls after instrument_preset ($C6EA) at every sequence-mode entry: seq_mode_defaults ($5224) at $5243, sequence_mode_init ($5380) at $53F3, mode_cold_init ($6FFF) at $701E and digital_sequence_mode_setup ($7187) at $71DB
ABI_channel_restore_destinations equ ABI_BASE+102*ABI_SLOT ; put back the destinations a cold start parked, and route them. The Channel Configuration mode's own entry does it, as enter_channel_config_mode ($528F) does at $5404-$543D; until then the records say nothing is routed and the DACs hold zero
ABI_key_hex_digit   equ  ABI_BASE+101*ABI_SLOT  ; B = a key code: 0 to 15 with carry CLEAR when it is one of the sixteen characters of the hex column, carry SET and B untouched when it is not. The tone number and the sequence data cursor are single hex characters and are typed in a paged image
ABI_unit_scale_decades equ ABI_BASE+100*ABI_SLOT ; X = a 24-bit value, B = a decade count: scaled by ten to the power (B - entry_frac). The radian entries need it without a unit code - a phase typed 3 and 3.000 are both three radians
ABI_unit_div_ten    equ  ABI_BASE+99*ABI_SLOT   ; X = a 24-bit value in memory: divided by ten in place, truncating. What a typed decimal point costs a field whose own scaling is not the unit table's
ABI_entry_point     equ  ABI_BASE+98*ABI_SLOT   ; the decimal point key: carry CLEAR if the field took it, SET if it already has one. What follows it is counted in entry_frac and taken off the unit's decades when the value is scaled
ABI_destn_dc_shared equ  ABI_BASE+97*ABI_SLOT   ; A = the channel to leave out, B = a destination code; carry SET when another channel with the dc waveform is already routed there. dc_destination_conflict ($7736)
ABI_error_show      equ  ABI_BASE+96*ABI_SLOT   ; the last error flashed over whatever is showing for three seconds, then the screen underneath repainted - show_last_error_screen ($C418). The Main Selection Level and the digital sequence screen both answer shifted INC SET with it
ABI_lcd_write_line_raw equ ABI_BASE+95*ABI_SLOT ; A = LCD_LINE1 or LCD_LINE2, X = the characters, B = how many: the line painted over the shadow rather than into it, and painted even while lcd_hold is set. The stock's lcd_write_string_at ($D8A5), which is how a flash leaves the screen under it recoverable
ABI_screen_back     equ  ABI_BASE+94*ABI_SLOT   ; leave this screen for the one that opened it, which is what LOCAL does from the foreground and what the stock's Exit softkey reaches through return_to_main_menu ($8E62)
ABI_remote_query_field equ ABI_BASE+111*ABI_SLOT ; A = the stock's $2215, the id of the SELECTED field: that field's value rendered the way the bus renders it and queued for the talker. The whole of gpib_query_value_response ($7B7A), which the page-0 chain's request-$25 arm at $635E reaches through call_routine_on_a2u13_page ($DB2B) with page 3 and entry $7B7A. Ids $01-$08, $0C-$12 answer; $00 and $09-$0B queue nothing, which is what the four cascades' fall-through does
ABI_entry_cursor_on equ  ABI_BASE+112*ABI_SLOT  ; A = the DDRAM address of an armed field's first digit: the cursor moved there and turned on, unless the instrument is remote. arm_numeric_entry_field ($AC35) at $AC98 and $ACA6, which every paged arm reaches
ABI_entry_cursor_off equ ABI_BASE+113*ABI_SLOT  ; the cursor off, unconditionally. entry_exit_restore_display ($B38B) at $B3BA, which a paged screen reaches when a digit or units key commits its entry
ABI_entry_is_open   equ  ABI_BASE+114*ABI_SLOT  ; Z clear when an entry field is armed from the panel, Z set when none is; registers unchanged. numeric_entry_key_handler's $23A8 test at lb494 ($B494), answered by the cursor bit, which is written only where $23A8 is
ABI_entry_key_is_mapped equ ABI_BASE+115*ABI_SLOT ; B = a key code: Z clear when key_to_state_code ($AD4D) or keymap_menu_msgs_19_1d ($AEBB) maps it, every register kept. The service screens re-arm after every message and not after a key numeric_entry_key_handler keeps
ABI_save_prompt_open equ ABI_BASE+116*ABI_SLOT ; the Save prompt over the screen that is up (register_screen_open): request $21's answer on pages 0, 1 and 2, which each close their field and call save_recall_prompt ($F331) with $0021
ABI_register_apply  equ  ABI_BASE+117*ABI_SLOT  ; the live setting onto the hardware with the output relays (registers.s register_apply): a mode entry's reason-1 apply after register_restore has preset and copied - $52FA-$5431 in enter_channel_config_mode, l53ee in sequence_mode_init, l71d6 in digital_sequence_mode_setup
ABI_option_toggle   equ  ABI_BASE+121*ABI_SLOT  ; B = the option's bit number: flipped, the bank first (service_data.s option_toggle)
ABI_options_clear_all equ ABI_BASE+122*ABI_SLOT ; every option off, the bank first (service_data.s options_clear_all)
ABI_relay_restore   equ  ABI_BASE+123*ABI_SLOT  ; the relay exercise stopped: levels and every recorded latch byte back (service_diag.s relay_restore). Also the screen_leave vector, being always mapped
ABI_banner_arm      equ  ABI_BASE+120*ABI_SLOT  ; X = a forty-column title opening with five stars: the walking star, for a paged screen's banner (service_prompts.s banner_arm). Arm it AFTER screen_install, which stops the star
ABI_lcd_write_raw   equ  ABI_BASE+119*ABI_SLOT  ; A = the DDRAM address, X = the characters, B = how many: the GLASS only, as lcd_write_string_at ($D8A5) writes an entry's echo - the shadow is left alone so entry_key_exit's repaint takes an abandoned entry off (docs/entry-exit-port.md)
ABI_mode_enter_channel_config equ ABI_BASE+118*ABI_SLOT ; Channel Configuration opened from inside page 0 - the Channel Summary's ENTER - recorded in active_mode and entered cold through mode_channel_config (main_menu.s)
