; ---------------------------------------------------------------------------
; ram.inc - the battery-backed RAM map
;
; $2000-$3FFF is HM6264 static RAM held up by the backup battery. It survives
; power-down, and it holds the things this instrument cannot regenerate.
;
; WHAT THOSE THINGS ARE, exactly, because this file used to say "its serial
; number, which options are installed, and its calibration data" and the
; third of those is not supported by anything in this repository:
;
;   the serial number and the installed options   - established, at
;   $3FFC-$3FFF with the legacy copies at $3FEE-$3FF5, and the only data HP's
;   own failure narrative in the service manual names.
;
;   the twelve save/recall setups, ending at $3A7A  - established from the
;   stock save path, and per-unit user data even though it is not identity.
;   The STOCK's twelve start at $268F; this firmware's start lower, because
;   its slot is bigger, and REGISTER_BASE in registers.s is derived backwards
;   from that fixed top rather than being written out as a number.
;
;   CALIBRATION DATA: NOT ESTABLISHED, and probably not here at all.
;   Scanning all five images for calibration, cal, gain, offset, adjust and
;   trim finds nothing; the Special Function list and the Diagnostics menu
;   contain no calibration screen; a reference scan of $2000-$3FFF found 388
;   distinct addresses of which every read-only one resolves to a structure
;   base rather than a constant; and the four addresses this project's own
;   prose had called calibration-like were each disproved individually.
;   firmware/ramrefs.py says the same in its own docstring.
;
;   The published recovery procedure has no calibration step, and the
;   Operation and Calibration Manual that would settle it - 08904-90007 - is
;   not in this repository.
;
; AND THE MANUAL CORROBORATES THE PART THAT MATTERS. Printed page 8-29 states
; that the serial number and Options 001 and 003 live in battery-backed
; non-volatile memory on A2 and must be restored if that board is replaced,
; and names a battery-replacement procedure. It says nothing about
; calibration living there.
;
; A NOTE ON A CLAIM THIS FILE USED TO CARRY: that page 8-23 withholds the A2
; board as proprietary and exchange-only. It does not - 8-23 is ordinary A2
; overview prose. That was repeated here from a summary without the page
; being read, which is the same fault as the calibration claim it was
; supporting.
;
; NONE OF THAT WEAKENS THE RULE. The owner's instruction is that this data is
; never lost, and the protection is to treat the WHOLE region as per-unit
; rather than only the parts that have been named - which is what
; ramsafety.py does and what the service manual's own Figure 8-12.1 supports,
; showing the backed-up store as one undivided 8K x 8 device. Not knowing
; where calibration lives is a reason to protect all of it, not less of it.
;
; THESE ADDRESSES MAY NOT CHANGE. Not because the code cares - the code is
; being rewritten - but because the DATA ALREADY EXISTS in the instrument's
; RAM, written by the firmware that is in it now. Move serial_number and a
; machine that boots this ROM reads its serial from somewhere else and finds
; whatever was there. There is no way back: the value is not printed anywhere
; the firmware can reach, and HP's own recovery procedure refuses a serial
; that is not factory-virgin.
;
; firmware/ramsafety.py enforces this against any built image.
; ---------------------------------------------------------------------------


; A FIELD IS ARMED, OR NO KEY MAY TYPE INTO ONE. The stock ends the edit in
; progress when the controller takes the instrument remote, and a digit pressed
; after the operator gets it back does nothing until a field key arms one
; again: driven on both firmwares 2026-09-12 - PHASE, a value, a unit, then REN
; asserted, a command, REN released, then '0' - and the stock's field still
; reads '0.0 deg' where this firmware started a fresh entry and echoed '0'.
;
; entry_begin sets it, remote_gone_remote clears it, and each screen's
; start-an-entry helper refuses while it is clear.
;
; MOVED OUT OF THE STACK ON 2026-09-14 with its four neighbours. It was $2199,
; six bytes under STACK_TOP, and the banner at the head of the display shadow
; below has the whole argument.
entry_armed            equ     $2261

; decoded here: compared against 54 bytes at ROM $EC85 by $C36E
ram_signature          equ     $2000

; ===========================================================================
; $203C-$21FF IS STACK AND NOTHING ELSE. 452 bytes, and the reason they are
; empty is that this is the map the INSTRUMENT has.
;
; The stock initialises S with LDS #$21FF at $7D5F and keeps its scratch at
; $2600, so apart from the trust signature at $2000-$203B the whole of
; $203C-$21FF is stack on a real 8904A. It never checks how deep the stack
; is either: `grep -c cmps firmware/a2u12.asm firmware/src-generated/
; a2u13_page*.s` returns 0 in all five images, so there is no floor in the
; instrument and no equivalent of one.
;
; THIS FIRMWARE HAD PUT FIVE THINGS IN HERE and left the stack 102 bytes:
; register_seq_block ($203C, 257), the migration bookkeeping ($213D, 8),
; lcd_shadow ($2145, 80) and lcd_hold, main_menu_page, entry_dot, entry_frac
; and entry_armed ($2195-$2199). Then, having taken four fifths of the stack,
; it added two floors of its own invention - STACK_FLOOR and NMI_STACK_FLOOR
; in boot.s - to police what was left. docs/stack-depth-question.md measured
; the cost: an ordinary bus register recall reached $21BE, one byte above the
; floor that silences every timer interrupt, and twenty bytes further down the
; CPU's own twelve-byte interrupt frame lands on entry_frac and the tail of
; the display shadow, which no software floor can prevent.
;
; The architect's answer, 2026-09-14, was
; to put the map back rather than to raise a floor: "Option 1 - put the map
; back the way the instrument has it ... The floor is this firmware's
; invention and the stock has no such thing."
;
; So every one of those five moved out and both floors are gone. Where they
; went and why is on each declaration. Nothing may be declared in $203C-$21FF
; again: hp8904a-rewrite/tests/test_scratch_layout.py refuses the file if
; anything is, and hp8904a-rewrite/tests/test_stack_depth.py counts the
; deepest call chain against the 452 bytes rather than against a floor.
; ===========================================================================

; decoded here: bit 5 of the high byte is set at $DCBF when the
; ROM self-test fails; the FIRQ key decoder writes bit 0 of the
; low byte at $AB2E and $AB6E
event_flags2           equ     $2202

; decoded here: IRQ sets low bit 0 at $F161, FIRQ sets low bit 1
; at $F104 and high bit 2 at $F138
event_flags            equ     $2204

; decoded here: FIRQ reloads it with $1002 at $F13E; foreground
; decrements it at $8877
idle_timer             equ     $220B

; decoded here: the $FFCF helper stores the ISR pair here with STD
; at $FFD9 - the STOCK's address is $2246-$2247, and this pair is the one
; cell in this file that MOVED for a packing reason rather than a functional
; one. Nothing in this firmware reads or writes either byte (grep over
; hp8904a-rewrite/ finds only these two declarations), and sitting at $2246
; they split the 113-byte run $220D-$227D into 57 and 54 - neither of which
; holds the 80-byte display shadow that had to come out of the stack. They
; are kept rather than deleted because the decoded stock address above is
; worth keeping; they are two bytes higher so the run is whole.
gpib_isr1_saved        equ     $226A

; decoded here: low half of that STD
gpib_isr2_saved        equ     $226B

; THE BUS ADDRESS AND THE SERVICE-REQUEST-ENABLE MASK, at the STOCK'S OWN
; battery-backed addresses, deliberately: an instrument moving between this
; firmware and the stock keeps its configured address either way. The stock
; stores them from its two entry screens ($A0D4 stores the address with
; STB >$227F and gpib_address_set ($9D73) the mask with STB >$227E) and
; feeds both to the chip at every init (gpib_driver_init pushes them into
; the gpib_chip_init record).
remote_address         equ     $227F
remote_sre_mask        equ     $227E

; AND WHAT THEY HOLD ON A BOARD WHOSE BATTERY RAM CANNOT BE BELIEVED. Both are
; battery-backed, so a trusted boot keeps whatever the operator last set and
; nothing may overwrite them - but the untrusted boot has to put something
; there, and the stock puts these. power_on_reinit ($C2C4), which power_on_init
; reaches from $82B2 only when ram_signature_check ($C36E) has left $23DD
; non-zero, does LDB #$1A / STB >$227F then LDB #$13 / STB >$227E. The seeding
; is in boot.s, immediately before remote_init, because the chip is programmed
; from these cells and not the other way about.
;
; $13 IS BITS 0, 1 AND 4 of the service-request enable mask, one bit per event
; in the order of the stock's weight table d929d ($929D): bit 0 the general
; error, bit 1 the reference loop out of lock and bit 4 a reverse-power relay.
; Bits 2 and 3 - the sequence started and the sequence finished - are NOT
; enabled by default on the instrument, which is why a controller that wants
; them has to ask. The routine remote_event carries the per-event evidence.
BUS_ADDRESS_DEFAULT    equ     $1A
BUS_SRE_DEFAULT        equ     $13

; THE RESPONSE BUFFER, AT THE STOCK'S OWN ADDRESS AND THE STOCK'S OWN SIZE.
; hpib_query_sequence ($72B2) walks up to 250 sequence steps into $2285 and
; queue_gpib_output ($9FFE) hands that buffer and its length to the talker,
; so a controller reading a full sequence gets all 250 characters. This
; firmware built its replies in 72 bytes of scratch and truncated at 70,
; which is fine for a number and wrong for a sequence: a controller asking
; for the playlist got the first seventy steps of it.
;
; It is HERE rather than in scratch.inc because scratch ($3A80 upwards) has
; no 252-byte hole left, and because this is the stock's own cell for the
; same purpose - the same argument that puts the bus address and the LCD
; shadow at the stock's addresses. $2285 + 252 = $2381, clear of
; kbd_col_shadow ($241F) above it and of the stack ($21FF downwards) below.
rmt_out                equ     $2285
RMT_OUT_MAX            equ     250      ; characters, before the CR LF the
                                        ; queue appends: a full 250-step
                                        ; sequence is the longest reply the
                                        ; instrument makes

; decoded here: written alongside $0A00 by the FIRQ key scan at
; $AA23 and others
kbd_col_shadow         equ     $241F

; decoded here: NMI reads, masks and writes it at $DC4E-$DC53,
; then writes $1000
ptm_cr1_shadow         equ     $2421

; decoded here: NMI at $DC6C-$DC71, then $1001
ptm_cr2_shadow         equ     $2422

; decoded here: NMI at $DC61-$DC66, then $1000
ptm_cr3_shadow         equ     $2423

; MOVED DOWN ON 2026-09-07, and the reason is the save-register array.
;
; These cells sat at $2480-$24DF. REGISTER_BASE is derived backwards from
; REGISTER_TOP ($3A7A), so it walks DOWN as a slot grows - and once the tone
; sequence became the stock's sixteen-tone list plus a 250-step playlist, a
; slot reached 472 bytes and twelve of them start at $245B. That put every one
; of them INSIDE the array, where a register save would have written over the
; two interrupt callback vectors.
;
; They are now packed into $2424-$242D, immediately above ptm_cr3_shadow and
; well clear of the array. None is pinned by rule 2, and the owner's word
; covers the move (2026-09-07, "well since we are doing
; u12 and u13 we can move code around as we please").
;
; hp8904a-rewrite/tests/test_scratch_layout.py fails if the array ever lands on
; a cell declared here, and that is what caught this.
;
; The "decoded here" notes record where the STOCK firmware keeps each one. This
; firmware no longer agrees with it on these addresses; it still does on
; everything rule 2 pins.

; decoded here: STB $2480 at $DCB6 - one byte
rom_checksum_result    equ     $2424
; decoded here: the NMI handler dispatches through it with JMP
; [$24D8] at $DC42; registered at $F034
nmi_callback           equ     $2425
; decoded here: the FIRQ body loads it into X at $F0DC and calls
; JSR ,X; registered at $F04E
firq_callback          equ     $2427
; decoded here: FIRQ stores the decoded key with STD $24DC at
; $F117
key_code               equ     $2429
; THE SAVE-REGISTER FORMAT STAMP. Two bytes of battery RAM holding
; REGISTER_MARK once register_migrate has brought the array up to the current
; format. It is what stops a second boot migrating twice: the marker in a slot
; cannot answer that question, because an empty slot has no marker at all and a
; blank instrument would be migrated forever.
;
; It must be OUTSIDE scratch - scratch_reset would clear it on every boot and
; the migration would then run every time. It is at $2262, above the five
; display and entry cells and below the spare bytes that end the run.
;
; THIS CELL HAS NOW MOVED TWICE, AND THAT IS WHY register_migrate LOOKS IN TWO
; PLACES. It was $242B in the firmware that wrote FORMAT 3 (git show
; a9450c2^:hp8904a-rewrite/common/ram.inc line 155, with REGISTER_FORMAT equ 3
; in the same tree); a9450c2 on 2026-09-10 introduced format 4 and moved it to
; $213D in the same commit; and $213D is inside the 452 bytes of stack this
; firmware has just given back, so it moved again to here.
;
; THE INSTRUMENT IN THE FIELD CARRIES FORMAT 3. roms/README.md records the
; hardware run - the rewrite's four pages on a One ROM stand-in, "the
; instrument BOOTED and the serial and options survived register_migrate
; rewriting battery RAM into format 3" - and that build is the pre-a9450c2
; one, so its stamp is at $242B. No instrument carries format 4: roms/README.md
; says of the current images that "this exact image has not been on a chip".
;
; So register_migrate reads REGISTER_STAMP_V3 ($242B) first and this second,
; which is the architect's own instruction for the bootstrap, 2026-09-14: "a
; format-4 firmware looks for a format-3 stamp at the old address first, then
; its own at the new one."
;
; This is the rewrite's own cell; the stock has nothing here.
register_format_stamp  equ     $2262
; THE DISPLAY AS IT STANDS - eighty characters, line 1 then line 2, and the
; flag that says a flash is up over them.
;
; THE STOCK KEEPS EXACTLY THIS. lcd_write_clipped ($D8EA) folds its DDRAM
; address into a 0-79 position, clamps the length so it cannot run past $50,
; paints the characters unless bit 4 of event_flags ($2204) is set - and then
; ALWAYS mirrors them into the shadow buffer at $242B with mem_copy ($C285).
; lcd_repaint_both_lines ($D989) reads 40 characters from $242B at DDRAM $00
; and 40 from $242B+$28 at $40, and lcd_repaint_shadow ($D9C6) is that call
; with the bit cleared. Twenty call sites use it.
;
; It is what makes the last-error screen possible: show_last_error_screen
; ($C418) paints its banner and message over whatever is showing WITHOUT
; mirroring, waits 3000 ms, and repaints the screen underneath from here.
; Driven on the stock 2026-09-11: with channel A's screen up, SHIFT then INC
; SET gives '*  Last reported error was no.  123    *' over 'Frequency exceeds
; limit', and about two million cycles later the channel screen is back
; complete with its values - which only a character-for-character shadow can
; restore, and $242B was read back holding exactly those eighty characters.
;
; NOT IN SCRATCH, and not where the stock has it. $242B is inside this
; firmware's save-register array - REGISTER_BASE walks down from $3A7A as a
; slot grows and reaches $242B exactly - so the stock's address is not
; available, and scratch_reset would clear it on a screen change, which is the
; one thing a shadow that exists to repaint a screen may not do.
;
; AND IT IS AT $220D BECAUSE THAT IS WHERE EIGHTY CONTIGUOUS BYTES ARE. It was
; $2145, inside the stack; see the banner under ram_signature. Below $220D is
; idle_timer at the stock's own $220B-$220C, and $220D-$227D is the longest
; free run left in battery RAM outside the register array and scratch - 113
; bytes, once gpib_isr1_saved and gpib_isr2_saved moved out of the middle of
; it. The shadow takes the first 80, the five display and entry cells and the
; eight migration bytes take the next 21, main_menu_limit takes $226C, shown_channel
; $226D, chan_marker_col $226E and chan_chain_last $226F, the tone tick takes
; $2270-$2275, and $2276-$227D is spare. lcd_clear
; blanks the shadow, so a cold machine repaints spaces rather than whatever
; the battery held.
lcd_shadow             equ     $220D    ; 80 bytes, LCD_SHADOW_LEN
lcd_hold               equ     $225D    ; non-zero while a flash owns the glass:
                                        ; writes reach the shadow and stop there

; WHICH PAGE OF THE MAIN SELECTION LEVEL IS SHOWING - the stock's $2245, which
; enter_paged_menu_mode ($8D23) clears on every return to the screen and
; main_selection_level_handler ($8C14) steps with NEXT and LAST. The stock's
; own address is inside this firmware's save-register array, so it is here
; instead, beside the display shadow and for the same reason: scratch is packed
; solid up to live_setting and everything above that survives a keep-state
; power-on, which a menu cursor must not.
main_menu_page         equ     $225E    ; 0 to MAIN_PAGE_LAST

; HOW FAR THAT PAGE MAY GO - the stock's $2223, which
; build_option_dispatch_table ($8939) sets once at power-on: the page limit
; with Option 001 fitted, zero without, and zero also empties slots 2-9. Not
; battery state; main_menu_latch rewrites it on every boot. From the spare run
; $226C-$227D.
main_menu_limit        equ     $226C    ; MAIN_PAGE_LAST, or 0

; WHICH CHANNEL IS ON THE GLASS - the stock's $3B81, beside the channel the
; panel and the bus act on, which is current_channel and the stock's $23BE.
; The record-select arms of select_menu_page ($514D) - select_channel_a
; ($5161) and its three siblings - write both; a bus field select writes only
; $23BE (l9c04). Every channel painter on page 0 draws only when the two agree
; ($5306 draw_channel_frequency, $57B1 paint_channel_amptd, $5854, $5A1B,
; $5B13, $5B98 ... each opens LDB >$23BE / CMPB >$3B81). So after 'APA;' on
; the ch C record the instrument keeps showing ch C and paints nothing more
; into it until a record is selected again.
shown_channel          equ     $226D    ; 0-3 on a channel record, 4 or 5 not

; WHERE THE INCREMENT MARKER STANDS, or zero - the stock's $2412/$2413 pair.
; set_field_marker_at_column ($C855) writes glyph $07 at the column and keeps
; it; clear_field_marker ($C885) writes a space back there, once.
chan_marker_col        equ     $226E    ; a DDRAM address, never 0 when set

; THE LAST RECORD NEXT REACHES IN THE CHANNEL CONFIGURATION CHAIN - the
; stock's $2242 as enter_channel_config_mode ($528F) leaves it, from the
; options byte read at that moment ($5496-$54BA): Option 003 keeps menu_show's
; count, all seven records; Option 001 alone makes it 4, the title and four
; channels; neither makes it $23B2, the channels fitted.
chan_chain_last        equ     $226F    ; 6, 4, or installed_channels

; THE TONE PLAYER'S TICK STATE, the stock's own cells for blk42d1 ($42D1).
; $3D32 counts the on/off phases with bit 7 marking the half-tick that only
; reloads the timer; $3D34 is the once-through flag; $3D30 is the loaded
; phase's duration and $3D2E the timer value the last half-tick wrote. They
; drive the Tone Sequence tick alone - the DTMF tick keeps its own state -
; and tone_start sets all four as start_sequence_timer ($6BD0) does.
tone_phase_count       equ     $2270    ; $3D32
tone_once              equ     $2271    ; $3D34
tone_period            equ     $2272    ; $3D30, a word
tone_period_last       equ     $2274    ; $3D2E, a word

; A TYPED DECIMAL POINT. The instrument takes one in any numeric field -
; column 7 of keypad_char_table ($EF94), the unsigned-decimal column entry
; mode 3 selects, holds '.' as well as the ten digits - and
; entry_to_scaled_digits ($CDE1) scales what was typed by the unit's decades
; LESS the digits after the point. Driven on the stock 2026-09-11: 100 . 5
; then Hz is 100.5 Hz, 1 . 2345 then kHz is 1234.5 Hz, . 5 then Hz is 0.5 Hz,
; and 100 . 55 then Hz truncates to 100.5 Hz.
;
; THIS FIRMWARE DROPPED THE KEY. The same 100 . 5 then Hz put 1005.0 Hz on the
; chip - ten times what the operator asked for, from an ordinary keystroke,
; with nothing on the screen to say so. These two bytes are what it costs to
; take it: they are not in scratch because scratch is packed solid up to
; live_setting and this is not instrument state - entry_begin clears both.
entry_dot              equ     $225F    ; non-zero once the point is typed
entry_frac             equ     $2260    ; how many digits have followed it

; decoded here: written at $C37C
legacy_opts_20987a     equ     $3FEE

; decoded here: written at $C398
legacy_opts_22987a     equ     $3FF2

; decoded here: written by the reset path. It is NOT what the
; validity check compares - that reads $2036
revision_signature     equ     $3FF6

; decoded here: read at $800B; cleared at $A3DD on signature
; failure
installed_options      equ     $3FFC

; decoded here: read at $8010 and rendered as eight digits
serial_number          equ     $3FFD

; HOW MANY SAVED SETUPS THE LAST MIGRATION REFUSED. One byte, written by
; register_migrate at boot and read by the screen that reports it, so an
; operator is told rather than finding twelve empty registers and guessing.
; MOVED BELOW THE REGISTER ARRAY on 2026-09-10. These eight bytes sat at
; $242B-$2432, and REGISTER_BASE came down onto them when the aliased sequence
; slot took a register from 470 bytes to 474 - twelve of those reach $242B
; exactly. They are now at $213D, in the 197 bytes between the sequence block
; and event_flags2, which nothing else declares.
;
; Outside scratch for the same reason the stamp is.
register_refused       equ     $2264

; THE FORMAT 2 TO 3 CONVERSION'S WORKING BYTES. Five, used only by
; register_migrate at boot and dead afterwards. They are here rather than in
; scratch because the conversion USES the live tone tables as its staging area
; - at boot they hold nothing yet - and a temporary living in the same block it
; is staging into would be overwritten by the thing it is counting.
register_mig_slot      equ     $2265    ; the v3 slot being expanded, a word
register_mig_tones     equ     $2267    ; how many tones allocated so far
register_mig_step      equ     $2268    ; which of the sixteen v2 steps
register_mig_other     equ     $2269    ; the earlier step being compared

; ===========================================================================
; THE SAVED SEQUENCE BLOCK - one slot per register, holding whichever
; sequence was live when it was saved.
;
; HP'S OWN DESIGN, and this firmware had invented its way out of it.
; save_state_register ($544D) on page 2 copies 170 bytes from $3C02 to $2581
; and save_sequence_setup ($6CD7) on page 1 copies 257 bytes from $3C10 to
; the SAME $2581. One slot in the 425-byte record holds EITHER the digital
; pattern or the tone and DTMF sequence, whichever screen saved last. That is
; how the instrument fits both in 425 bytes where this firmware was spending
; 470 and still could not hold the digital pattern at full size.
;
; Separate spans were an invention the instrument never had, AND THEY DO NOT
; FIT: growing the digital span from 16 bytes to the stock's 125 costs 1,308
; bytes across twelve registers and only 1,055 are free between the trust
; signature and the register array. A saved digital pattern would have been
; truncated - a visible defect traded for an invisible feature.
;
; 257 bytes, which is the stock's own block size.
;
; IT IS NO LONGER A RAM CELL AT ALL. It was `register_seq_block equ $203C`,
; 257 bytes of battery RAM that held a COPY of whichever sequence was live
; while a register was being written or read - filled by register_seq_stage
; from the live model, then copied a second time into the register's slot.
; Two copies of one thing, and the buffer was the single biggest taker of the
; 452 bytes that belong to the stack: see the banner under ram_signature.
;
; register_seq_stage and register_seq_unstage now take the slot pointer in X,
; so register_save stages STRAIGHT INTO THE SLOT and register_recall_copy
; reads straight out of it. The slot's layout did not change by a byte - the
; sequence still occupies payload offset 192 through 448, which is what
; V4_KIND_OFF and V4_TAIL_OFF in hp8904a-rewrite/modules/registers.s say and
; what register_mig_v3 converts a format-3 slot into - so nothing saved by an
; earlier build reads differently. The intermediate buffer is simply gone.
;
; THAT IS ALSO WHAT THE INSTRUMENT DOES. save_state_register ($544D) on page 2
; copies its 170-byte block to $2581 and save_sequence_setup ($6CD7) on page 1
; copies its 257-byte one to the SAME $2581, which is inside the stock's own
; live-state block - the thing its register save then copies out wholesale.
; The stock has no separate staging buffer either.
;
; THE SIGNATURE IS 54 BYTES AND THE RESERVED RANGE IS 60. This file used to
; say the signature occupies $2000-$203B, and what this firmware writes and
; checks is SIGNATURE_LEN = 54 bytes at $2000-$2035
; (hp8904a-rewrite/modules/selftest.s). The stock's is the same 54 from $EC85
; plus six more from $ECBB at $2036-$203B, which this firmware does not use
; for anything: the per-unit RAM rule reserves the whole $2000-$203B, so the
; stack's first byte is $203C either way and the six bytes between stay empty
; on purpose.
;
; Byte 0 of the slot says WHICH sequence it holds; the 256 behind it are the
; payload. The stock needs no such byte because its two live models overlap
; in RAM - $3C02-$3CAB for the digital screen and $3C10-$3D10 for the tone
; and DTMF ones - so using one destroys the other and there is never a
; question of which is in the slot. This firmware keeps the two models apart,
; which is a real capability the instrument lacks, so the slot has to say.
REGISTER_SEQBLOCK      equ     257
SEQKIND_NONE           equ     0        ; nothing has been saved into it
SEQKIND_TONE           equ     1        ; tone_freq, tone_times and tone_list -
                                        ; the tone and DTMF screens. NOT
                                        ; tone_end, which this said and which
                                        ; the run never reached
SEQKIND_DIGITAL        equ     2        ; digital_sequence, digital_base and
                                        ; sequence_length
; A SLOT WRITTEN SINCE 2026-09-16 CARRIES WHAT THE INSTRUMENT'S BLOCK DOES
; AND THESE TWO DID NOT, and says so in this byte, so a slot written before
; reads back exactly as it always did. Measured on the stock: a recall puts
; back the tone cursor $3D0D and end $3D0F, both inside its 257-byte block,
; and restarts a digital sequence saved while running, $3C02 being inside its
; 170. register_seq_stage writes only these two; register_seq_unstage reads
; all four. seq_kind_live never holds them.
SEQKIND_TONE_KEPT      equ     3        ; SEQKIND_TONE, then tone_end and
                                        ; tone_cursor
SEQKIND_DIGITAL_KEPT   equ     4        ; SEQKIND_DIGITAL, then
                                        ; digital_running

; ===========================================================================
; THE DIGITAL SEQUENCE PATTERN - 125 bytes, one MSB-first bit stream.
;
; The instrument's, read out of A2U13 page 2: the pattern is at $3C21 and the
; base at $3C20, and the three bases are the SAME stream cut three ways -
; digit i of width w is bits w*i .. w*i+w-1, bit 0 being bit 7 of the first
; byte. element_index_to_bit_index ($55F3) computes (n+1)*w-1 for the last bit
; of digit n, which is only true if the digits are contiguous and MSB-first,
; and change_sequence_base ($56E9) never touches a pattern byte: it recomputes
; the indices and re-cuts the same bits.
;
; 1 bit a digit gives 1000 digits, 3 gives 333 and 4 gives 250, which is what
; set_max_length_for_base ($56A3) installs. 250 x 4 and 1000 x 1 are exactly
; 1000 bits; octal wastes the last one.
;
; This firmware held sixteen steps of eight bits - 128 bits where the
; instrument has 1000, and no octal at all.
;
; OUTSIDE SCRATCH, because the stock's is outside the region its own reset
; clears and it has to be: scratch_reset runs on a screen change, and a
; pattern that vanished when the operator looked at another screen would be
; useless.
;
; ABOVE THE BUS BUFFER, NOT UNDER IT. This was $2280, chosen as the start of
; "the 427 bytes between the bus state and the register array" - and rmt_out
; was put at $2285 for the same reason by a different change, so 120 of these
; 125 bytes were the reply buffer. Every bus query wrote over the operator's
; pattern from bit 40 on: a six-character frequency reply left ASCII digits in
; bits 40 to 103, and the sequence report at digital_query_bits corrupted
; itself, reporting the first forty bits correctly and its own characters
; after that. The pattern now starts where the buffer ends - rmt_out is $2285
; and 252 characters long, so $2381 - and runs to $23FD, clear of
; kbd_col_shadow ($241F) by 33 bytes. test_scratch_layout.py checks every
; declared cell in this file against every other now, which is the check that
; would have caught it.
DIGITAL_PATTERN_BYTES  equ     125
DIGITAL_PATTERN_BITS   equ     1000
digital_pattern_ram    equ     $2381

; The three bases' digit widths and their digit counts, which are the same
; 1000 bits divided three ways.
DIGITAL_W_BIN          equ     1
DIGITAL_W_OCT          equ     3
DIGITAL_W_HEX          equ     4
DIGITAL_N_BIN          equ     1000     ; $56B0: LDD #$03E8
DIGITAL_N_OCT          equ     333      ; $56B9: LDD #$014D
DIGITAL_N_HEX          equ     250      ; $56C2: LDD #$00FA
