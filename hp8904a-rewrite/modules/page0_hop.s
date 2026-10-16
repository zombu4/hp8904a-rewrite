; ===========================================================================
; page0_hop.s - the frequency, amplitude and phase hop tables
;
; Fast hop is Option 003. A hop table is a list of values the instrument
; steps through under the sequencer, so the output jumps between them without
; the firmware being in the loop - the whole point of the feature is that the
; step happens faster than software could do it.
;
; The table lives in RAM and the sequencer walks it. This file edits it.
;
; WHY THE OPTION BIT IS CHECKED HERE. Bit 1 of installed_options is what
; makes these screens reachable at all, and a screen that painted itself and
; then refused every key would be worse than one that says plainly the option
; is not installed.
; ===========================================================================

HOP_ENTRY       equ     HOP_ENTRY_SIZE  ; eight bytes each - frequency,
                                        ; amplitude, phase. The size is
                                        ; in common/formats.inc now, because
                                        ; hop_program in the always-mapped
                                        ; image walks the same table

; THE TWO MENU RECORDS, BYTE FOR BYTE OUT OF THE ROM. Record 5 of the table
; at $433E ($4370: text via429d, handler f1 request_hop_addr_entry, then three
; $C239) is the field screen; record 6 ($437A: text via42ed, all four handlers
; begin_entry_hop_address) is the On/Off page. Their text is at $429D and
; $42ED, spelled in firmware/src-generated/a2u13_page0.s lines 550-556 and
; 561-572, and docs/stock-hop-screen.md carries the whole reading with the
; column map. Record 5 is the four fcc pieces (67 bytes, $429D-$42DF) plus the
; thirteen spaces at $42E0-$42EC that bring it to 80 - the size of both its
; neighbours in the same table.
;
; THE RECORD CARRIES NO VALUES AND NO UNITS. Every digit, every unit label and
; every asterisk on this screen is written by one of the four painters; the
; record holds the labels and blanks. This firmware had the values baked into
; the record text ('Hop Ram Adrs  0  FREQ *      0.0  Hz*'), which is what the
; screen looks like at rest rather than what the ROM holds, and the columns
; were out by one in three places because they were counted off that picture
; instead of off the painters' own DDRAM arguments.
;
; Driven on the stock to confirm, 2026-09-10: f1 on Channel Config. then NEXT
; five times gives
;
;   '\x00\x01 Hop Ram Adrs  0  FREQ *      0.0  Hz*'
;   'AMPTD *     0 \x06V *  PHASE *   0.0 deg * '
;
; and NEXT once more gives
;
;   '\x00\x01 Digital Port Off \x00\x03 Freq Hop     Off '
;   '\x00\x02 Amptd Hop    Off \x00\x04 Phase Hop    Off '
;
; hop_page says which of the two is standing, 0 or 1. There is no count
; constant beside it any more: the two are records 5 and 6 of the seven-record
; Channel Configuration chain, chan_chain_show sets hop_page from chan_chain,
; and CHAN_CHAIN_LEN in page0_screen.s is the only length NEXT and LAST bound
; themselves against - see hop_key_next_t.

; THE FOUR ROWS OF RECORD 6, numbered as set_hop_function_enable ($4984)
; dispatches on $3B80 at $4BB2-$4BC8: 0 -> $49A1 Digital Port, 1 -> $49D0
; Freq Hop, 2 -> $4A71 Amptd Hop, 3 -> $4B65 Phase Hop. The softkey that
; arms each is the marker on its own line - f1 and f3 on line 1, f2 and f4
; on line 2 - so f2 is Amptd Hop and f3 is Freq Hop, not the other way round.
HOP_ROW_PORT    equ     0
HOP_ROW_FREQ    equ     1
HOP_ROW_AMPL    equ     2
HOP_ROW_PHASE   equ     3
HOP_ROWS        equ     4

hop_p0_l1       fcb     $00,$01                 ; $429D
                fcc     " Hop Ram Adrs  "       ; $429F, 15
                fcc     "   FREQ"               ; $42AE, the first 7 of 34
                fcc     "                "      ; and 16 of its spaces
hop_p0_l2       fcc     "AMPTD      "           ; the last 11 of that piece
                fcc     "         PHASE  "      ; $42D0, 16
                fcc     "             "         ; $42E0, 13
hop_p1_l1       fcb     $00,$01                 ; $42ED
                fcc     " Digital Port     "    ; 18; the state goes at $10
                fcb     $00,$03
                fcc     " Freq Hop         "    ; 18; and at $24
hop_p1_l2       fcb     $00,$02
                fcc     " Amptd Hop        "    ; 18; at $50
                fcb     $00,$04
                fcc     " Phase Hop        "    ; 18; at $64
hop_state_on    fcc     "On "
hop_state_off   fcc     "Off"

; THE FOUR FRAMES, the strings at $4384-$43BC, each written WHOLE by the
; $D8EA call that uses it - the lengths 4, $0F, $0C and $0D are that call's
; own Y argument, so an asterisk pair and the spaces between them go down in
; one write and the digits are written over the middle of it afterwards.
hop_frame_addr  fcc     "*  *"                  ; $4391, 4
hop_frame_freq  fcc     "*             *"       ; $4395, 15
hop_frame_ampl  fcc     "*          *"          ; $43A4, 12
hop_frame_phase fcc     "*           *"         ; $43B0, 13
hop_frame_blank fcc     "               "       ; 15, the longest of them:
HOP_FRAME_BLANK equ     15                      ; $ED11 in A2U12, which the
                                                ; four painters use as the
                                                ; blank form and which is
                                                ; longer than any length they
                                                ; ask of it
hop_blank       fcc     " "                     ; the AMPTD sign column when
                                                ; the waveform is not dc
hop_no_option   fcc     "Option 003 required                     "

; WHAT EACH ASTERISK PAIR MEANS, and it is not a cursor. The three value
; fields are framed while their hop function is OFF - paint_hop_value_field
; takes $4395 when bit 8 of $2202 is CLEAR ($451C-$4533), show_hop_amptd_field
; takes $43A4 when bit 6 of $2203 is clear ($461B-$4632) and
; draw_hop_phase_field takes $43B0 when bit 7 of $2203 is clear ($4769-$4780).
; Driven on the stock: with Freq, Amptd and Phase Hop all switched On the
; screen reads ' Hop Ram Adrs  0  FREQ        0.0  Hz ' with every asterisk
; gone. The address field is the other way round - draw_hop_ram_address takes
; $4391 when bit 13 of $2204 is SET ($4415-$4424) - and with Digital Port On
; the stock shows ' Hop Ram Adrs* 0* FR'.
;
; This firmware framed whichever field the cursor was on, which is a cursor
; the instrument does not have. The instrument's cursor is the hardware one
; the entry machinery turns on at the field's own column, plus the marker
; $C855 drops at $18, $45 or $59 while that field is being typed.

; --- record 5's columns, each one a painter's own DDRAM argument -----------
; docs/stock-hop-screen.md section 7 is the whole 80-column map.
HOP_FRAME_ADRS_W equ   4               ; $4442 writes four characters
HOP_FRAME_ADRS  equ     LCD_LINE1+$0F   ; $4442: 4 characters
HOP_ADRS_POS    equ     LCD_LINE1+$10   ; $4459: 2 digits, from the THIRD
HOP_ADRS_W      equ     2               ; character of a three-digit render

HOP_FRAME_FREQ  equ     LCD_LINE1+$19   ; $4549: 15 characters
HOP_FRAME_FREQ_W equ    15
HOP_F_FREQ      equ     LCD_LINE1+$1B   ; $4560: 8 digits, from the second
HOP_W_FREQ      equ     8               ; character of a nine-character
HOP_U_FREQ      equ     LCD_LINE1+$24   ; $4571: the unit label
HOP_MARK_FREQ   equ     $18             ; $4488: the edit marker's column

HOP_FRAME_AMPL  equ     LCD_LINE2+$06   ; $4648: 12 characters
HOP_FRAME_AMPL_W equ    12
HOP_S_AMPL      equ     LCD_LINE2+$07   ; $466F: one character - a space, or
HOP_F_AMPL      equ     LCD_LINE2+$08   ; the slot's sign when channel 0 is dc
HOP_W_AMPL      equ     5               ; $4686: 5 digits, from the FIRST
HOP_U_AMPL      equ     LCD_LINE2+$0E   ; $4659: the unit $D022 chose
HOP_MARK_AMPL   equ     $45             ; $45A0

HOP_FRAME_PHASE equ     LCD_LINE2+$1A   ; $4796: 13 characters
HOP_FRAME_PHASE_W equ   13
HOP_F_PHASE     equ     LCD_LINE2+$1C   ; $47AD: 5 digits, from the second
HOP_W_PHASE     equ     5
HOP_U_PHASE     equ     LCD_LINE2+$22   ; $47C1
HOP_MARK_PHASE  equ     $59             ; $46B5

HOP_UNITS_W_AMPL equ    2               ; the units class 4 width the arms at
                                        ; $AD3A give ($AD11 LDB #$02); the
                                        ; FREQ and PHASE fields are classes 6
                                        ; and 3, whose width is three

; record 6's four state cells, three characters each
HOP_PORT_STATE  equ     LCD_LINE1+$10
HOP_FREQ_STATE  equ     LCD_LINE1+$24
HOP_AMPL_STATE  equ     LCD_LINE2+$10
HOP_PHASE_STATE equ     LCD_LINE2+$24

; --- the four number forms, each measured on the stock ---------------------
; docs/stock-hop-screen.md section 9 lists the sweeps these came from.
HOP_FREQ_WHOLE_HZ  equ  6               ; '600000.0'
HOP_FREQ_FRAC_HZ   equ  1
HOP_FREQ_WHOLE_KHZ equ  3               ; '600.0000', trailing zero blanked
HOP_FREQ_FRAC_KHZ  equ  4
HOP_PHASE_WHOLE_DEG equ 3               ; '359.9'
HOP_PHASE_FRAC_DEG  equ 1
HOP_PHASE_WHOLE_RAD equ 1               ; '6.283'
HOP_PHASE_FRAC_RAD  equ 3

; HOP_PHASE_RAD and its two masks are in common/formats.inc beside
; HOP_PHASE itself, because dds.s and remote.s read the same bit.


HOP_VALUE_POS   equ     HOP_F_FREQ      ; where an entry echoes: the field the
HOP_ECHO_W      equ     TEXT_DIGITS+1   ; cursor is on is the one being typed,
                                        ; and hop_entry_field gives its column


; THE THREE FIELDS A SLOT NOW HAS. It held a frequency alone until the
; read-through reached the stock's hop record and found fifteen bytes with an
; amplitude at +7 and a phase at +11; HOP_ENTRY_SIZE in common/formats.inc
; names the four sites that establish them.
; The three codes themselves are in common/formats.inc, beside HOP_SLOTS:
; remote.s names them too, to tell this page which ceiling a bus-set value
; has to pass, and it is in the other image.

; THE FOURTH FIELD IS NOT IN THE SLOT. It is the hop RAM's STANDING ADDRESS,
; DDS register $15 - which slot the chip is sitting on between programming
; writes. The stock keeps it on its Hop Ram screen at $429D as the 'Hop Ram
; Adrs' row: selecting the row (request_hop_addr_entry $43BD posts request
; code $27) arms entry field 10, a two-digit decimal field
; (entry_cfg_hop_address $50E6 stores 2 digit positions); ENTER commits it
; through arm [17] of the $717A table, enter_hop_addr_value ($6F78), and the
; up/down arrows step it through arm [17] of the $7701 table, step_hop_addr
; ($7467). Both end in apply_hop_addr_and_repaint ($4803), which calls
; write_reg15_nibble ($E7C4) on A2U12; that routine masks its value argument
; to four bits, ORs in $10 when its flag argument is non-zero, and hands the
; byte to dds_param_store ($DD9D) for register $15 - a width-1 register in
; the descriptor table at $DD73 (entry $24, top two bits clear), so it is
; one STD to $0200 with the id in A and the byte in B. Here the same byte
; goes through ABI_dds_write, whose width-1 arm is that same single STD, and
; which keeps the shadow that hop_program in modules/dds.s reads back to
; restore $15 after it has selected and strobed a slot.
;
; THE NIBBLE IS THE COMPLEMENT OF WHAT THE OPERATOR TYPED. enter_hop_addr_value
; ($6F78) runs ascii3_to_byte ($CA36) over the digits, compares the result
; with $10 and, only when it is below, stores `COMB / ANDB #$0F` of it at
; $24F4; apply_hop_addr_and_repaint ($4803) then passes $24F4 to $E7C4
; unchanged. draw_hop_ram_address ($43D4) prints `COMB / ANDB #$0F` of $24F4
; again, so the operator sees the number they typed, and step_hop_addr
; ($7467) DEcrements $24F4 for direction 1 - the up arrow: $6311 passes 1
; for request $20, which key code 19 posts at $ADD2 - and INcrements it for
; direction 0 (the down arrow: $6338 passes 0 for request $1F, key code 25
; at $ADDA), each stopping at 0 and at $0F and applying the register write
; on the clamped path too. This file does the same: the number on the
; screen is the typed one, the arrows move it the way their names say, and
; the byte written to $15 carries its four-bit complement.
;
; A TYPED VALUE OF 16 OR MORE IS DROPPED WITHOUT A BEEP. The instruction
; stream of $6F78 after `CMPB #$10 / LBCC l6fae` calls nothing that reports
; an error: l6fae re-applies the standing $24F4 through $4803 and re-arms
; entry field 10 through the vector at $3B85. That is ported as it stands.
;
; BIT 4 OF REGISTER $15 IS NOT THIS FIELD'S. $E7C4 sets it from bit 13 of
; event_flags $2204 ($E7D4 LDX >$0007,s / CMPX #$0000 / $E7E1 ORB #$10),
; which set_hop_function_enable ($4984) raises and clears ($49AF ORA #$20 /
; $49BC ANDA #$DF on the high byte) for row 0 of its Digital Port / Freq
; Hop / Amptd Hop / Phase Hop menu, and apply_hop_addr_and_repaint ($4803)
; reads back at $480B-$481C to pass as $E7C4's flag argument. Here that
; flag is MODE_FLAG_DIGITAL in mode_flags, switched by hop_func_port on
; shift-f1, and hop_addr_put takes bit 4 from it as $4803 does - on every
; write of $15, so the typed address and the arrows carry the standing flag
; exactly as $E7C4 carries $2204's bit. scratch_reset clears mode_flags at
; power-on and dds_reset writes $15 as $00, the value dds_params_reset
; ($DF17) sends after zeroing $248A-$24C4, so both start clear together.
; HOP_FIELD_ADDR is in common/formats.inc with the other three.

; --- WHICH KEY ENDS AN ENTRY IN EACH FIELD --------------------------------
;
; The Hop Table's four fields are units-class fields, and this screen took no
; unit key at all: typing 1000 and pressing Hz stored NOTHING, and ENTER
; committed the digits raw - so 1000 Hz became 1000 tenths of a hertz, which
; is 100 Hz. On every other screen in the instrument a value is committed by
; its unit key and the unit scales the digits.
;
; The classes are the stock's, read out of the four arms of the table at
; $5115 that arm these fields:
;
;   arm_hop_frequency_editor  ($5024)  class 6   Hz, kHz
;   entry_cfg_hop_amptd       ($503D)  class 4   deg=uV, Hz=mV, kHz=V
;   entry_setup_hop_phase     ($5086)  class 3   ENTER=rad, deg=deg
;   entry_cfg_hop_address     ($50E6)  class 2   ENTER only
;
; and check_entry_terminator ($B070) is what makes a unit key the terminator:
; class 0 ends on any legal character, class 1 when the field is full, and
; every class above that only on a unit key.
;
; Four columns per field - ENTER, deg, Hz, kHz - so the row IS the field's
; class with its ENTER arm beside it. A cell of HOP_UNIT_NONE means the field
; refuses that key, which is $B0C1 returning zero and the beep that follows.
HOP_UNIT_NONE   equ     $FF
HOP_KEY_COLUMNS equ     4
hop_class_units
                fcb     HOP_UNIT_NONE,HOP_UNIT_NONE,UNIT_HZ,UNIT_KHZ   ; freq, class 6
                fcb     HOP_UNIT_NONE,UNIT_MICROVOLT,UNIT_MILLIVOLT,UNIT_VOLT ; ampl, class 4
                fcb     UNIT_RAD,UNIT_DEG,HOP_UNIT_NONE,HOP_UNIT_NONE  ; phase, class 3
                fcb     UNIT_NONE,HOP_UNIT_NONE,HOP_UNIT_NONE,HOP_UNIT_NONE ; address, class 2

; ---------------------------------------------------------------------------
; hop_unit_lookup - what this key means in the field that is selected
;
;   entry: B = the column: 0 ENTER, 1 deg, 2 Hz, 3 kHz
;   exit:  carry CLEAR and B = the UNIT_* code; carry SET if the field
;          refuses that key
;   uses:  A, B, X
; ---------------------------------------------------------------------------
hop_unit_lookup
                pshs    b                       ; the column
                lda     >hop_field
                ldb     #HOP_KEY_COLUMNS
                mul                             ; D = field * 4
                addb    ,s+
                adca    #0
                ldx     #hop_class_units
                leax    d,x
                ldb     ,x
                cmpb    #HOP_UNIT_NONE
                beq     hop_unit_refused
                andcc   #~CC_CARRY
                rts
hop_unit_refused
                orcc    #CC_CARRY
                rts

HOP_FIELDS      equ     4


HOP_ADDR_DIGITS equ     2               ; entry_cfg_hop_address ($50E6):
                                        ; `LDD #$0002 / STD 5,S`, two
                                        ; digit positions
HOP_ADDR_MAX    equ     $0F             ; $6F78 `CMPB #$10 / LBCC` refuses
                                        ; 16 and up; $7467 `CMPB #$0F` is
                                        ; the step's far stop
HOP_ADDR_MODE   equ     $10             ; the bit $E7C4 ORs in (`ORB #$10`)
                                        ; from its flag argument

; ---------------------------------------------------------------------------
; hop_available - is fast hop installed?
;
;   exit:  carry CLEAR if it is
;   uses:  A
;
; Reads the option bit directly rather than trusting a cached copy: the
; service menu can turn it off while the instrument is running, and a screen
; that believed a stale copy would keep working after the option was removed.
; ---------------------------------------------------------------------------
hop_available
                lda     >installed_options
                anda    #$02                    ; bit 1: Option 003
                bne     hop_available_yes
                orcc    #CC_CARRY
                rts
hop_available_yes
                andcc   #~CC_CARRY
                rts

; ---------------------------------------------------------------------------
; hop_slot_address - where one slot's value lives
;
;   entry: B = the slot, 0 to HOP_SLOTS-1
;   exit:  X = its eight bytes - HOP_FREQ at 0, HOP_AMPL at 3, HOP_PHASE
;          at 6; 'three bytes' stood here from before the slot grew
;   uses:  A, B, X
; ---------------------------------------------------------------------------
hop_slot_address
                ldx     #hop_table
                tstb
                beq     hop_slot_done
hop_slot_step
                pshs    b
                ldb     #HOP_ENTRY
                abx
                puls    b
                decb
                bne     hop_slot_step
hop_slot_done
                rts

; ---------------------------------------------------------------------------
; hop_slot_valid - is this a slot the table has?
;
;   entry: B = the slot
;   exit:  carry CLEAR if it exists
;   uses:  nothing
; ---------------------------------------------------------------------------
hop_slot_valid
                cmpb    #HOP_SLOTS
                blo     hop_slot_valid_yes
                orcc    #CC_CARRY
                rts
hop_slot_valid_yes
                andcc   #~CC_CARRY
                rts

; ---------------------------------------------------------------------------
; hop_store - put a value into a slot
;
;   entry: B = the slot, X = a POINTER to the 24-bit value
;   exit:  carry SET if the slot does not exist and nothing was written
;   uses:  A, B, X, U
;
; X IS A POINTER, not the value. The header said "the 24-bit value", and a
; 24-bit value does not fit a 16-bit register - the body hands X to copy24 as
; a source address, and its one caller passes `ldx #entry_result`. A caller
; who believed the header would pass a number and copy three bytes from
; wherever that number happened to point.
;
; Masked, because the sequencer reads this table from interrupt context. A
; three-byte value written while the sequencer steps past it would be read as
; half of the old value and half of the new, and the output would jump to a
; frequency that was never in the table.
; ---------------------------------------------------------------------------
; hop_incr_address - where the selected field's increment lives
;
;   exit:  X = its three bytes
;   uses:  A, X
; ---------------------------------------------------------------------------
hop_incr_address
                lda     >hop_field
                cmpa    #HOP_FIELD_AMPL
                beq     hop_incr_at_ampl
                cmpa    #HOP_FIELD_PHASE
                beq     hop_incr_at_phase
                ldx     #incr_hop_freq
                rts
hop_incr_at_ampl
                ldx     #incr_hop_ampl
                rts
hop_incr_at_phase
                ldx     #incr_hop_phase
                rts

; ---------------------------------------------------------------------------
; hop_incr_begin - the next ENTER stores this field's increment
;
;   uses:  A, B, X
;
; The same one-shot mode the Channel Configuration screen has: the operator
; types a number and presses ENTER exactly as for a value, and only where it
; lands differs. The stock separates the two with distinct field ids - $0F,
; $10 and $11 against $0C, $0D and $0E - and reaches them through the same
; entry machinery, which is the same arrangement said differently.
; ---------------------------------------------------------------------------
; ---------------------------------------------------------------------------
; hop_marker_show - the increment glyph, while a hop increment is armed
;
;   uses:  A
;
; set_field_marker_at_column ($C855) at the field's own column - $4488 at
; $18 for FREQ, $45A0 at $45 for AMPTD, $46B5 at $59 for PHASE, the columns
; HOP_MARK_FREQ, HOP_MARK_AMPL and HOP_MARK_PHASE carry. Measured 2026-09-17
; on the Hop Ram record: INC SET on each of the three shows glyph $07 there on
; the instrument, and it stayed through the digits typed after it; this
; firmware painted none. hop_show rewrites both line templates, so the glyph
; is drawn after them on every repaint rather than once.
; ---------------------------------------------------------------------------
hop_marker_show
                tst     >hop_incr_mode
                beq     hop_marker_show_done
                lda     >hop_field
                cmpa    #HOP_FIELD_AMPL
                beq     hop_marker_show_ampl
                cmpa    #HOP_FIELD_PHASE
                beq     hop_marker_show_phase
                cmpa    #HOP_FIELD_FREQ
                bne     hop_marker_show_done
                lda     #HOP_MARK_FREQ
                lbra    chan_marker_draw
hop_marker_show_ampl
                lda     #HOP_MARK_AMPL
                lbra    chan_marker_draw
hop_marker_show_phase
                lda     #HOP_MARK_PHASE
                lbra    chan_marker_draw
hop_marker_show_done
                rts

hop_incr_begin
                lda     #$01
                sta     >hop_incr_mode
                lbsr    hop_slot_entry_begin
                ldb     >hop_index
                lbsr    hop_show
                lbra    hop_field_arm           ; begin_hop_freq_entry
                                                ; ($623F), $626D and $629B end
                                                ; in [$3B85] - JSR ,X at $6260,
                                                ; $628E and $62BC - with the
                                                ; value's selector, 6, 7 or 8

; ---------------------------------------------------------------------------
; hop_step_field - move the selected field of the current slot
;
;   entry: B = $01 to step up, $FF to step down
;   uses:  A, B, X, Y, U
;
; The stock steps its three hop fields at $74BA, $7533 and $762A, and converts
; the increment between degrees and radians when its unit disagrees with the
; record's. NO CONVERSION IS NEEDED HERE: a phase is held in tenths of a
; degree everywhere in this firmware, and a radian entry is converted on the
; way in by unit_apply, so an increment and a record can never disagree about
; the unit they are in.
;
; THE ARROW RESELECTS THE VALUE FIELD. Three arms of the stock's step table
; d7701 are the hop increment fields, and each is two instructions long:
; step_hop_frequency_from_increment_field ($74B4) LDD #$000C / STD >$2215,
; step_hop_amptd ($752D) LDD #$000D / STD >$2215 and redirect_step_to_hop_phase
; ($7624) LDD #$000E / STD >$2215, each falling into the VALUE arm below it
; ($74BA, $7533, $762A). So an arrow while INCR SET is armed - $2215 = $0F,
; $10 or $11 - puts the value field's id back, steps the VALUE by its
; increment, repaints the value (paint_hop_value_field called at $7515,
; show_hop_amptd_field at $760C, draw_hop_phase_field at $76C0) and re-arms
; the value's entry through [$3B85] with selectors 6, 7 and 8 ($751A-$7527,
; $7611-$761E, $76C5-$76D2): arm_field_editor ($4ED8), whose numeric tail
; resets the buffer head and count ($ACE8-$ACF5), so digits typed before
; the arrow are gone. hop_incr_mode is this screen's $0F, $10 and $11, so it
; is cleared here, before the step, for all three fields at once; it used to
; survive the arrow, so the next number entered landed in the increment
; where the stock's lands in the value. The re-arm is at hop_step_done, on
; every path, as [$3B85] is reached from every path of the three arms.
; hop_addr_step does the same for the address stop, whose $7467 ends alike.
;
; A dc LEVEL IS SIGNED. step_hop_amplitude ($7533) caches hop record+10 into
; $241E, inverts the direction when $2514 is 4 and that sign is '-', and on
; a subtraction that borrows recomputes increment minus level and flips the
; sign ($75C4-$7602); hop_step_ampl_sign and hop_step_cross carry those, and
; hop_sign_store puts the sign where store_hop_amptd ($4CD5) puts it.
;
; The value goes back through hop_value_in_range and hop_store_field, so a
; stepped value meets the same ceiling a typed one meets - and is programmed
; to the chip the same way. Stepping below zero leaves the slot as it was -
; except a dc level, which crosses zero.
; ---------------------------------------------------------------------------
hop_step_field
                clr     >hop_incr_mode          ; $74B4/$752D/$7624: the value
                                                ; field is selected again
                pshs    b                       ; the direction
                lbsr    hop_incr_address
                pshs    x                       ; the increment
                clr     >hop_step_sign          ; unsigned, unless the AMPL
                                                ; branch below finds a dc
                                                ; level

                ldb     >hop_index              ; the field's value, widened
                lbsr    hop_field_address       ; U = it, X = the slot
                lda     >hop_field
                cmpa    #HOP_FIELD_PHASE
                beq     hop_step_load_word
                cmpa    #HOP_FIELD_AMPL
                bne     hop_step_load_wide
                lbsr    hop_step_ampl_sign      ; a dc level: its sign, and
                                                ; the direction inverted for
                                                ; a negative one ($7555)
hop_step_load_wide
                lda     ,u
                sta     >hop_step_work
                ldd     1,u
                std     >hop_step_work+1
                bra     hop_step_move
hop_step_load_word
                clr     >hop_step_work
                ldd     ,u                      ; the phase word

                ; THE UNIT RIDES IN BIT 15 AND IS NOT PART OF THE NUMBER.
                ; This stepped the raw word, so a slot keyed in radians began
                ; the arithmetic 32768 too high and hop_range_phase refused
                ; every press - the arrows could not move a radian phase at
                ; all. Taking the bit off is only half of it: hop_store_field
                ; puts the flag back from hop_entry_unit, the unit of the last
                ; ENTRY, so a step made after keying another field in degrees
                ; would have turned the slot's radians into degrees. The unit
                ; the step declares is the SLOT'S OWN, read out of the word it
                ; is about to move.
                clr     >hop_step_rad
                bita    #HOP_PHASE_RAD_HI
                beq     hop_step_load_word_deg
                inc     >hop_step_rad           ; remembered HERE and put back
                anda    #~HOP_PHASE_RAD_HI      ; below, because the entry
                                                ; layer's hop_entry_unit is the
                                                ; unit of the last thing TYPED
                                                ; and writing this one into it
                                                ; re-armed the entry in radians:
                                                ; unit_apply then scaled the
                                                ; field by RAD_DECADES, carried
                                                ; out of 24 bits and raised $13
                                                ; on a step that had already
                                                ; worked
hop_step_load_word_deg
                std     >hop_step_work+1

hop_step_move
                ldu     ,s                      ; the increment
                ldx     #hop_step_work
                lda     2,s                     ; the direction
                bmi     hop_step_subtract
                lbsr    ABI_add24               ; AND A STEP THAT WRAPS IS
                bcs     hop_step_overflow       ; NOT STORED, the same way the
                bra     hop_step_store          ; borrow below is not: the
                                                ; stock's own level step tests
                                                ; it at $7580/$7585 and skips
                                                ; store_hop_amptd at $7590.
                                                ; add24's carry is the overflow
                                                ; (math.s), and committing a
                                                ; wrapped 24-bit level puts a
                                                ; small number in the slot and
                                                ; on the chip when the operator
                                                ; asked for a large one.
hop_step_overflow
                leas    2,s                     ; the slot is left as it was
                lbra    hop_step_done
hop_step_subtract
                lbsr    ABI_sub24
                bcc     hop_step_store
                tst     >hop_step_sign          ; A dc LEVEL CROSSES ZERO
                bne     hop_step_cross          ; ($75C4); anything else
                leas    2,s                     ; BELOW ZERO: the slot is left
                lbra    hop_step_done           ; as it was. The stock's
                                                ; step_hop_freq ($74BA) tests
                                                ; sub24's borrow and skips the
                                                ; apply entirely; flooring to
                                                ; zero (a first draft) stored
                                                ; and programmed a value the
                                                ; stock never would

hop_step_cross
                ; BELOW ZERO ON A dc LEVEL: THE STEP CROSSES IT. The stock's
                ; $75C4-$75CD test $2514 for 4 again and abandon the step for
                ; anything else; for dc, $75CE-$75E3 run sub24 ($D3C6) the
                ; other way round - X = $2674, Y = record+7, U = $221C: the
                ; increment minus the level, which cannot borrow because the
                ; level was the smaller - and $75E4-$75FC set $241E from
                ; record+10: '+' when it was '-' ($75EA CMPB #$2D / $75F0 LDB
                ; #$2B) and '-' otherwise ($75F8 LDB #$2D), before
                ; store_hop_amptd stores both ($7602). The result is the
                ; same three-byte magnitude and the opposite sign, and here
                ; it goes on into hop_step_store as every step does.
                ldu     ,s                      ; the increment, into the
                lda     ,u                      ; working value
                sta     >hop_step_work
                ldd     1,u
                std     >hop_step_work+1
                ldb     >hop_index
                lbsr    hop_field_address       ; U = the level - the AMPL
                                                ; field, hop_step_sign being
                                                ; set for no other
                ldx     #hop_step_work          ; X = the increment, minus it
                lbsr    ABI_sub24
                lda     >hop_step_sign
                cmpa    #CHAN_SIGN_MINUS        ; $75EA CMPB #$2D
                beq     hop_step_cross_plus
                lda     #CHAN_SIGN_MINUS        ; $75F8 LDB #$2D
                bra     hop_step_cross_sign
hop_step_cross_plus
                lda     #CHAN_SIGN_PLUS         ; $75F0 LDB #$2B
hop_step_cross_sign
                sta     >hop_step_sign          ; and on into hop_step_store

hop_step_store
                leas    2,s                     ; drop the increment pointer
                ; THE CEILING, ON EVERY FIELD. The stock's step arms commit
                ; through the routines its ENTER arms commit through, and
                ; the ceiling is inside those routines, so a stepped value
                ; meets it exactly as a typed one does. step_hop_freq ($74BA)
                ; calls apply_hop_frequency_entry ($4BFE) at $74DF and $750B;
                ; $4BFE's sub24 ($D3C6, called at $4C37) takes $221C from
                ; $EA55 - 6,000,000 - and a borrow loads error $71 at $4C46
                ; for error_report_beep ($C3FE) at $4C51, storing nothing.
                ; step_hop_amplitude ($7533) calls store_hop_amptd ($4CD5)
                ; at $7590, $75BC and $7602; $4CD5's ref_value_below ($B8AD,
                ; called at $4D09) takes $221C from the value at [$23B7] -
                ; $EA62, $98 $96 $80 = 10,000,000, which entry_cfg_hop_amptd
                ; ($503D) stores there at $5041-$5046 - and a borrow loads
                ; error $7A at $4D18 for $C3FE at $4D23, storing nothing
                ; ($4D28 LBRA l4d93). step_hop_phase ($762A) calls
                ; set_hop_entry_phase ($4DC7) at $768F and $76B6; $4DC7
                ; compares $221A with $EA5B = 3599 at $4DF7-$4E03 (with $EA5D
                ; = 6282 for unit code 4, radians, at $4DD7-$4DE3) and above
                ; it leaves through l4e84 - nothing stored, and no error.
                ;
                ; This path checked the frequency alone, so an amplitude or
                ; phase step stored and programmed a value the ENTER path
                ; refuses (the audit's AMPL finding; the phase had the same
                ; shape). hop_value_in_range is the one check both paths
                ; use, and the refusal is hop_refusal_code's - the stock's
                ; frequency and amplitude refusals are errors on both of its
                ; paths, and its phase refusal is silent on both.
                ;
                ; store_hop_amptd runs channel_sum_exceeds_ref ($B8CC, called
                ; at $4CF6) in place of $B8AD while bit 6 of $2203 is set
                ; ($4CDB-$4CE9, amplitude hop on). hop_value_in_range's
                ; hop_range_ampl runs that check too, through ABI slot 74,
                ; so both paths meet it as both of the stock's do.
                ldx     #hop_step_work
                lbsr    hop_value_in_range
                bcc     hop_step_in_range
                lbsr    hop_refusal_code        ; the same three answers the
                bcc     hop_step_done           ; ENTER path gives
                lbsr    ABI_error_raise
                bra     hop_step_done
hop_step_in_range
                ; hop_store_field reads entry_result, so the moved value goes
                ; there - the one place a value enters a slot, ceiling and all
                ldu     #hop_step_work
                ldx     #entry_result
                lbsr    ABI_copy24
                ldb     >hop_index
                lbsr    hop_store_field
                bcs     hop_step_done

                lda     >hop_field              ; AND THE PHASE'S UNIT GOES
                cmpa    #HOP_FIELD_PHASE        ; BACK ON THE WORD ITSELF.
                bne     hop_step_unit_done      ; hop_store_field derives bit
                ldb     >hop_index              ; 15 from hop_entry_unit, so a
                lbsr    hop_field_address       ; step made after another field
                lda     ,u                      ; was keyed in degrees would
                anda    #~HOP_PHASE_RAD_HI      ; have turned the slot's radians
                tst     >hop_step_rad           ; into degrees. What the slot
                beq     hop_step_unit_off       ; was is what it stays.
                ora     #HOP_PHASE_RAD_HI
hop_step_unit_off
                sta     ,u
hop_step_unit_done
                lda     >hop_step_sign          ; a dc level's sign goes with
                beq     hop_step_program        ; it: $241E through
                lbsr    hop_sign_store          ; store_hop_amptd's $4D59-$4D71
                                                ; on each applying path of
                                                ; $7533 (the calls at $7590,
                                                ; $75BC and $7602)
hop_step_program
                ; AND WHAT THE STORE SENDS THE CHIP IS THE FIELD'S: $7533's
                ; three applying calls end in store_hop_amptd, which writes
                ; the chip only while amplitude hop is on, and the frequency
                ; and phase steppers in d4c26's and set_hop_entry_phase's
                ; dds_write_channel of the slot. hop_field_commit (dds.s) is
                ; all three; it sent the slot with a freshly coded level for
                ; every field, which the instrument never does.
                lda     >hop_field
                ldb     >hop_index
                lbsr    ABI_hop_field_commit    ; and out to the chip
                lda     >hop_field              ; AND THE FILTER FOLLOWS A HOP
                cmpa    #HOP_FIELD_FREQ         ; FREQUENCY: the arrows' steps
                bne     hop_step_done           ; ($74DF, $750B) apply through
                lbsr    ABI_filter_apply        ; apply_hop_frequency_entry
                                                ; ($4BFE), which ends with
                                                ; recompute_channel_byte_24ec
                                                ; ($F7EC) at $4C97 for
                                                ; channel 0's destination
hop_step_done
                puls    b
                lbsr    hop_slot_entry_begin    ; the value's entry re-armed,
                                                ; as [$3B85] re-arms it at
                                                ; $751A, $7611 and $76C5, so
                                                ; the digits typed before the
                                                ; arrow are gone, as the
                                                ; stock's are ($ACE8-$ACF5)
                ldb     >hop_index
                lbsr    hop_show
                lbra    hop_field_arm           ; and the cursor with it: each
                                                ; step_hop_* arm ends in that
                                                ; JSR on every path, whether
                                                ; or not the value moved

; ---------------------------------------------------------------------------
; hop_store_field - put the entered value into the selected field of a slot
;
;   entry: B = the slot
;   exit:  carry SET if the slot does not exist and nothing was written
;   uses:  A, B, X, Y, U
;
; The frequency and the amplitude are three bytes and the phase is two, which
; is the only reason this is not one copy. Both are masked, because the
; sequencer reads this table from interrupt context: a multi-byte value
; written while the player steps past it would be read as half the old value
; and half the new, and the output would jump to a setting that was never in
; the table.
; ---------------------------------------------------------------------------
hop_store_field
                lbsr    hop_slot_valid
                bcs     hop_store_field_bad
                lbsr    hop_field_address       ; U = the field
                lda     >hop_field
                cmpa    #HOP_FIELD_PHASE
                beq     hop_store_field_word
                cmpa    #HOP_FIELD_FREQ
                bne     hop_store_field_copy
                ldb     >hop_entry_unit         ; THE FREQ FIELD'S UNIT IS THE
                stb     >hop_freq_unit          ; SCREEN'S, not the slot's:
                                                ; enter_hop_freq_value ($6FE5)
                                                ; records the unit key in
                                                ; $2677 and
                                                ; paint_hop_value_field reads
                                                ; it there at $44B1 for
                                                ; whichever slot is showing
hop_store_field_copy
                tfr     u,x                     ; three bytes
                ldu     #entry_result
                DISABLE_INTERRUPTS
                lbsr    ABI_copy24
                RESTORE_INTERRUPTS
                andcc   #~CC_CARRY
                rts
hop_store_field_word
                ldd     >entry_result+1         ; two, and a phase is the low
                                                ; sixteen bits of what was
                                                ; typed
                pshs    a                       ; AND ITS UNIT RIDES IN BIT 15,
                lda     >hop_entry_unit         ; the stock's record+13
                cmpa    #UNIT_RAD
                puls    a
                bne     hop_store_field_deg
                ora     #HOP_PHASE_RAD_HI
hop_store_field_deg
                DISABLE_INTERRUPTS
                std     ,u
                RESTORE_INTERRUPTS
                andcc   #~CC_CARRY
                rts
hop_store_field_bad
                ldb     #ERR_VALUE_RANGE
                lbsr    ABI_error_raise
                orcc    #CC_CARRY
                rts


; ---------------------------------------------------------------------------
; hop_show - paint the hop screen for one slot
;
;   entry: B = the slot
;   uses:  A, B, X, Y, U
;
; A dc level on the AMPL field is painted with its sign in the column before
; its digits; hop_show_signed says where the stock puts it. While an entry
; is in progress (hop_entry_active) the value field carries the entry
; instead, through hop_entry_echo, and everything else is painted as it is
; when none is.
; ---------------------------------------------------------------------------
hop_show
                pshs    x
                ldx     #hop_key
                lbsr    ABI_screen_install
                puls    x
                lbsr    hop_available
                bcc     hop_show_ok
                lda     #LCD_LINE2              ; BOTH LINES. This wrote only
                lbsr    ABI_lcd_blank_line      ; line 1, so "Option 003
                lda     #LCD_LINE1              ; required" appeared above
                ldx     #hop_no_option          ; whatever line 2 the previous
                ldb     #SVC_LABEL_LEN          ; screen had left
                lbra    ABI_lcd_write
hop_show_ok
                tst     >hop_page
                bne     hop_show_functions

; --- record 5: the address and the three values, all four on the glass ------
                lda     #LCD_LINE1
                ldx     #hop_p0_l1
                ldb     #SVC_LABEL_LEN
                lbsr    ABI_lcd_write
                lda     #LCD_LINE2
                ldx     #hop_p0_l2
                ldb     #SVC_LABEL_LEN
                lbsr    ABI_lcd_write

                ; THEN THE FOUR PAINTERS, in the order repaint_hop_fields
                ; ($47C6) calls them - draw_hop_ram_address ($47DD),
                ; paint_hop_value_field ($47E7), show_hop_amptd_field ($47F1)
                ; and draw_hop_phase_field ($47FB). Each lays its own frame
                ; down first and writes its digits over the middle of it, so
                ; the order inside a painter matters and the order between
                ; them does not.
                lbsr    hop_show_addr
                ldb     #HOP_FIELD_FREQ
                lbsr    hop_show_one
                ldb     #HOP_FIELD_AMPL
                lbsr    hop_show_one
                ldb     #HOP_FIELD_PHASE
                lbsr    hop_show_one
                lbsr    hop_marker_show         ; the increment glyph, over the
                                                ; template's space
                tst     >hop_entry_active       ; an entry in progress shows
                lbne    hop_entry_echo          ; itself in its own field, as
                rts                             ; the stock's glass does from
                                                ; the first accepted key
                                                ; ($B53D-$B555) on


; --- record 1: the four functions, each with its own softkey ---------------
hop_show_functions
                lda     #LCD_LINE1
                ldx     #hop_p1_l1
                ldb     #SVC_LABEL_LEN
                lbsr    ABI_lcd_write
                lda     #LCD_LINE2
                ldx     #hop_p1_l2
                ldb     #SVC_LABEL_LEN
                lbsr    ABI_lcd_write

                ; draw_mode_on_off_column ($483F) paints these four from bit
                ; 13 of $2204 ($4851-$4868), bit 8 of $2202 ($486D-$4884) and
                ; bits 6 and 7 of $2203 ($4889-$48A0, $48A5-$48BC).
                lda     >mode_flags
                anda    #MODE_FLAG_DIGITAL
                tfr     a,b
                lda     #HOP_PORT_STATE
                lbsr    hop_show_onoff
                ldb     >hop_running
                lda     #HOP_FREQ_STATE
                lbsr    hop_show_onoff
                lda     >mode_flags
                anda    #MODE_FLAG_AM
                tfr     a,b
                lda     #HOP_AMPL_STATE
                lbsr    hop_show_onoff
                lda     >mode_flags
                anda    #MODE_FLAG_PHASE
                tfr     a,b
                lda     #HOP_PHASE_STATE
                lbra    hop_show_onoff

; ---------------------------------------------------------------------------
; hop_show_addr - the Hop Ram address field
;
;   uses:  A, B, X, U
;
; draw_hop_ram_address ($43D4), the whole of it. The value is the complement
; of DDS register $15's low nibble ($43E6-$43EF LDB >$24F4 / COMB / ANDB #$0F),
; which is what hop_addr_get returns here; enter_hop_addr_value ($6F78) stores
; it complemented, so the complement is undone for display.
;
; THREE DIGITS RENDERED, TWO WRITTEN. $43FE renders the value into $2414 with
; $C9D1, $4410 blanks two leading zeros with $CCFF ($0002), and $4459 writes
; TWO characters from $2415 - the second and third of the three - at DDRAM $10.
; So slot 0 reads ' 0' and slot 15 reads '15': decimal, right-justified in two
; columns, and no leading zero. This screen used to show one hex digit, which
; put an 'F' where the instrument shows '15'.
;
; AND ITS FRAME IS THE OTHER WAY ROUND from the three value fields. $4415-$4424
; takes the asterisks when bit 13 of event_flags $2204 is SET, where the value
; fields take theirs when their own bit is CLEAR. That bit is the Digital Port
; row of the $42ED page - MODE_FLAG_DIGITAL here - and driving the stock with
; Digital Port On gives ' Hop Ram Adrs* 0* FR'.
; ---------------------------------------------------------------------------
hop_show_addr
                ldx     #hop_frame_blank
                lda     >mode_flags
                bita    #MODE_FLAG_DIGITAL
                beq     hop_show_addr_frame
                ldx     #hop_frame_addr
hop_show_addr_frame
                lda     #HOP_FRAME_ADRS
                ldb     #HOP_FRAME_ADRS_W
                lbsr    ABI_lcd_write

                lbsr    hop_addr_get            ; B = the address, 0 to 15
                clra
                std     >math_work+1             ; widened to 24 bits for the
                clr     >math_work               ; converter
                ldx     #math_work
                lbsr    ABI_uint24_to_text      ; eight digits, zeros kept
                lda     >text_buffer+TEXT_DIGITS-2
                cmpa    #'0'                    ; the tens digit, blanked when
                bne     hop_show_addr_write     ; it is a leading zero - two
                lda     #' '                    ; of the three are blanked and
                sta     >text_buffer+TEXT_DIGITS-2   ; the units digit stays
hop_show_addr_write
                lda     #HOP_ADRS_POS
                ldx     #text_buffer+TEXT_DIGITS-2
                ldb     #HOP_ADRS_W
                lbra    ABI_lcd_write

; ---------------------------------------------------------------------------
; hop_number - a value as whole units, a point and a fraction
;
;   entry: X = a 24-bit value in memory, A = how many whole-unit columns,
;          B = how many fraction columns, format_trim non-zero to blank a
;          trailing zero
;   exit:  format_text holds A+1+B characters
;   uses:  A, B, X, Y, U
;
; THE FOUR FORMS THIS SCREEN SHOWS, each measured on the stock rather than
; modelled from the formatter's arguments - docs/stock-hop-screen.md section 9
; records the sweeps:
;
;   FREQ, ' Hz'   6 whole hertz, a point, one tenth      '600000.0'
;   FREQ, 'kHz'   3 whole kilohertz, a point, four       '600.0000'
;   PHASE, 'deg'  3 whole degrees, a point, one tenth    '359.9'
;   PHASE, 'rad'  1 whole radian, a point, three         '6.283'
;
; THE WORK IS format_fixed's, in text.s, which is the stock's own
; $CCFF-then-$CD50 pair: it takes a digit count, a blank count and a point
; index. This screen's four forms all want every leading zero of the whole part
; blanked except the units digit, which is a blank count of whole-1, and the
; digits it renders are whole+fraction with the point after the whole ones.
; ---------------------------------------------------------------------------
hop_number
                pshs    a,b                     ; 0,s whole, 1,s fraction
                sta     >format_point           ; the point falls after the
                adda    1,s                     ; whole columns, and the digits
                puls    b                       ; are both parts together
                leas    1,s
                decb                            ; the blank count: every
                                                ; leading zero of the whole
                                                ; part but its units digit
                lbra    ABI_format_fixed

; ---------------------------------------------------------------------------
; hop_show_one - one of a slot's three value fields, frame and all
;
;   entry: B = HOP_FIELD_FREQ, HOP_FIELD_AMPL or HOP_FIELD_PHASE
;   uses:  A, B, X, Y, U
;
; The three painters paint_hop_value_field ($4461), show_hop_amptd_field
; ($4579) and draw_hop_phase_field ($468E), each reached by its field code.
; Each one writes its frame whole - 15, 12 and 13 characters, the lengths the
; $D8EA calls at $4549, $4648 and $4796 pass - and then its digits and its
; unit label over the middle of it.
;
; THE FRAME MEANS THE FIELD IS INOPERATIVE, not that the cursor is on it. Each
; painter takes its asterisks when its own hop function is OFF ($451C-$4533 on
; bit 8 of $2202, $461B-$4632 on bit 6 of $2203, $4769-$4780 on bit 7) and
; blanks when it is on; driving the stock with all three switched On gives
; ' Hop Ram Adrs  0  FREQ        0.0  Hz ' with every asterisk gone.
; ---------------------------------------------------------------------------
hop_show_one
                cmpb    #HOP_FIELD_AMPL
                lbeq    hop_show_one_ampl
                cmpb    #HOP_FIELD_PHASE
                lbeq    hop_show_one_phase

                ; --- paint_hop_value_field ($4461), the FREQ field ---------
                ldx     #hop_frame_freq
                tst     >hop_running            ; frequency hop
                beq     hop_show_freq_frame
                ldx     #hop_frame_blank
hop_show_freq_frame
                lda     #HOP_FRAME_FREQ
                ldb     #HOP_FRAME_FREQ_W
                lbsr    ABI_lcd_write

                ; THE UNIT IS THE ONE LAST KEYED FOR THIS FIELD, not a
                ; per-slot one: $44B1 reads $2677, which enter_hop_freq_value
                ; ($6FE5) fills from the unit key when it commits a value.
                ; hop_freq_unit is that cell.
                ; ANYTHING THAT IS NOT kHz IS Hz, and the cell is put right
                ; here rather than in a power-on hook: scratch_reset leaves it
                ; zero, which would name no unit at all, and the stock's own
                ; screen reads ' FREQ *      0.0  Hz*' on a cold boot.
                clr     >format_trim
                ldb     >hop_freq_unit
                cmpb    #UNIT_KHZ
                beq     hop_show_freq_khz
                ldb     #UNIT_HZ
                stb     >hop_freq_unit
                lda     #HOP_FREQ_WHOLE_HZ
                ldb     #HOP_FREQ_FRAC_HZ
                bra     hop_show_freq_number
hop_show_freq_khz
                lda     #1
                sta     >format_trim
                lda     #HOP_FREQ_WHOLE_KHZ
                ldb     #HOP_FREQ_FRAC_KHZ
hop_show_freq_number
                pshs    a,b
                ldb     #HOP_FIELD_FREQ
                lbsr    hop_field_address_of    ; U = the slot's frequency
                tfr     u,x
                puls    a,b
                lbsr    hop_number
                lda     #HOP_F_FREQ
                ldx     #format_text
                ldb     #HOP_W_FREQ
                lbsr    ABI_lcd_write
                ldb     >hop_freq_unit
                lbsr    ABI_unit_label
                lda     #HOP_U_FREQ
                ldb     #UNIT_LABEL_LEN
                lbra    ABI_lcd_write

                ; --- show_hop_amptd_field ($4579), the AMPTD field ---------
hop_show_one_ampl
                ldx     #hop_frame_ampl
                lda     >mode_flags             ; amplitude hop
                bita    #MODE_FLAG_AM
                beq     hop_show_ampl_frame
                ldx     #hop_frame_blank
hop_show_ampl_frame
                lda     #HOP_FRAME_AMPL
                ldb     #HOP_FRAME_AMPL_W
                lbsr    ABI_lcd_write

                ; THE SIGN COLUMN, one character at $47 ($466F). It is a space
                ; ($45D4 LDB #$20) unless channel 0's waveform is dc and this
                ; is the value rather than the increment ($45D8-$45E5), when it
                ; is the slot's own sign byte - the stock's record+10, which
                ; store_hop_amptd ($4CD5) writes from $241E and which is
                ; hop_signs here.
                ;
                ; WHICH FIELD IS SELECTED DOES NOT COME INTO IT. $45E2's
                ; CMPX #$0010 asks whether the INCREMENT is what the field
                ; shows, not whether AMPTD is the selected field: driven on the
                ; stock 2026-09-11 on the hop record, $2215 reads $000C with
                ; FREQ selected, $000D with AMPTD, $000E with PHASE, and $0010
                ; only once INCR SET is armed on AMPTD. This screen keeps the
                ; LEVEL in the field while INCR SET is armed - the difference
                ; chan_ampl_show_sign in page0_screen.s sets out - so the only
                ; condition left is the dc one, and it is tested here.
                ldx     #hop_blank
                lda     >channel_records+CHAN_WAVE   ; channel 0's, which
                cmpa    #LBL_DC                      ; is the stock's $2514
                bne     hop_show_ampl_sign
                ldb     >hop_index
                andb    #HOP_SLOTS-1
                ldx     #hop_signs
                abx
hop_show_ampl_sign
                lda     #HOP_S_AMPL
                ldb     #1
                lbsr    ABI_lcd_write

                ; FIVE DIGITS AND THE UNIT THE MAGNITUDE CHOSE. $4614 hands
                ; the slot's 24-bit level to the auto-ranging formatter $D022
                ; and $4659 writes the unit index it returns at $4E, then
                ; $4686 writes FIVE characters from the buffer's first byte.
                ; ampl_autorange is that formatter; it takes the value's
                ; address in U, which is what a hop slot gives it, and leaves
                ; the characters in ampl_range_out with the unit code in B.
                ldb     #HOP_FIELD_AMPL
                lbsr    hop_field_address_of    ; U = the slot's level
                lbsr    ABI_ampl_autorange
                pshs    b                       ; the unit code
                lda     #HOP_F_AMPL
                ldx     #ampl_range_out
                ldb     #HOP_W_AMPL
                lbsr    ABI_lcd_write
                puls    b
                lbsr    ABI_unit_label
                lda     #HOP_U_AMPL
                ldb     #UNIT_LABEL_LEN
                lbra    ABI_lcd_write

                ; --- draw_hop_phase_field ($468E), the PHASE field ---------
hop_show_one_phase
                ldx     #hop_frame_phase
                lda     >mode_flags             ; phase hop
                bita    #MODE_FLAG_PHASE
                beq     hop_show_phase_frame
                ldx     #hop_frame_blank
hop_show_phase_frame
                lda     #HOP_FRAME_PHASE
                ldb     #HOP_FRAME_PHASE_W
                lbsr    ABI_lcd_write

                ; THE SLOT CARRIES ITS OWN UNIT, and it has to. $46C7-$46F6
                ; reads the phase from record+11 and its unit code from
                ; record+13, and the two scales are different: driven on the
                ; stock, 3 then ENTER stores 3000 with unit 4 and shows
                ; '3.000 rad', while 180 then deg stores 1800 with unit 3 and
                ; shows '180.0 deg'. So the stored word is thousandths of a
                ; radian or tenths of a degree depending on the key that
                ; committed it, and 6.283 rad - which the stock accepts - is
                ; 360.03 degrees and cannot be held as tenths of a degree at
                ; all.
                ;
                ; HOP_PHASE_RAD IS BIT 15 OF THAT WORD. The slot is eight
                ; bytes and scratch is packed solid, so there is no room for
                ; sixteen unit bytes; the value needs thirteen bits (6283
                ; thousandths of a radian, 3599 tenths of a degree) and the
                ; top bit is free. Every reader masks it: dds.s's hop_program,
                ; remote.s's HOPP query, hop_step_field and hop_store_field.
                ldb     #HOP_FIELD_PHASE
                lbsr    hop_field_address_of    ; U = the slot's phase word
                ldd     ,u
                clr     >format_trim
                clr     >math_work
                ; AND THE CONVERTER IS POINTED AT IT. hop_number takes the
                ; value's ADDRESS in X, as uint24_to_text does; this staged
                ; the widened phase into math_work and then called hop_number
                ; with whatever X hop_field_address_of had left, which is the
                ; SLOT'S BASE - so the PHASE column formatted the slot's
                ; FREQUENCY bytes in three-and-one and only looked right while
                ; the frequency was zero. Driving the reset above found it:
                ; slot 0 keyed to 123456.0 Hz painted ' PHASE * 456.0 deg *'
                ; where the stock painted ' PHASE *   0.0 deg *'.
                ldx     #math_work
                bita    #HOP_PHASE_RAD_HI
                bne     hop_show_phase_rad
                std     >math_work+1
                lda     #HOP_PHASE_WHOLE_DEG
                ldb     #HOP_PHASE_FRAC_DEG
                lbsr    hop_number
                ldb     #UNIT_DEG
                bra     hop_show_phase_write
hop_show_phase_rad
                anda    #~HOP_PHASE_RAD_HI
                std     >math_work+1
                lda     #HOP_PHASE_WHOLE_RAD
                ldb     #HOP_PHASE_FRAC_RAD
                lbsr    hop_number
                ldb     #UNIT_RAD
hop_show_phase_write
                pshs    b
                lda     #HOP_F_PHASE
                ldx     #format_text
                ldb     #HOP_W_PHASE
                lbsr    ABI_lcd_write
                puls    b
                lbsr    ABI_unit_label
                lda     #HOP_U_PHASE
                ldb     #UNIT_LABEL_LEN
                lbra    ABI_lcd_write


; ---------------------------------------------------------------------------
; hop_entry_echo - the entry in progress, painted in the value field
;
;   uses:  A, B, X, Y
;
; THE STOCK ECHOES EVERY ACCEPTED KEY. numeric_entry_key_handler ($B3C2),
; once keypad_char_column_select ($AF29, called at $B50B) has put the key's
; character into the entry buffer $239A - a digit appended at the head
; index $23A4 while that is below the width $23A5 ($B042-$B065, the store
; at $B055), or '-' written over $239A itself ($B030 CMPB #$2D / $B038 STB
; >$239A) - writes the WHOLE buffer to the glass: lcd_write_string_at
; ($D8A5, called at $B551) with $239A, the width $23A5 and the column $23AD
; ($B53D-$B555), then lcd_set_cursor ($D7A0, called at $B567) to $23AD plus
; $23A4 ($B556-$B56B), the cell after the last character. The buffer was
; filled with spaces as the field was armed ($ACC5-$ACE0) and, for the
; kind-2 layout, given '+' at its head ($ACE8-$ACF0), so the glass shows
; the sign, the digits typed so far and blanks out to the width, left-
; aligned from the column arm_numeric_entry_field ($AC35) stored at $AC52
; from its column argument: $47 for a dc hop level and $48 otherwise from
; entry_cfg_hop_amptd ($503D, $5066-$5082), $1B for the hop frequency from
; arm_hop_frequency_editor ($5024), $5C for the hop phase from
; entry_setup_hop_phase ($5086) and $10 for the hop RAM address from
; entry_cfg_hop_address ($50E6). The first accepted key also blanks the
; field's unit cell ($B516-$B53C, $23AE characters at $23AF) and sets the
; first-key flag $23A7 ($B521); this screen's value field has no unit cell
; to blank, and hop_entry_active is that flag.
;
; BACKSPACE, key $1F, is entry_backspace ($B2CD, $B2D7 CMPX #$001F): for
; kinds 0, 1 and 3 it steps $23A4 back unless it is already zero and puts a
; space at the new head ($B2E9-$B31F); for kind 2 it steps back only while
; $23A4 is above 1, and with only the sign left it puts '+' back at $239A
; with $23A4 = 1 ($B320-$B35D, the reset at $B351). The handler then
; repaints the buffer as above ($B4D0-$B501), but only once a first key has
; been accepted ($B4C4-$B4CC test $23A7). hop_backspace_key is that arm
; here, reaching the editor through ABI slot 73 (ABI_entry_backspace).
;
; HERE the digits are rendered by ABI_entry_render from the first cell of
; the value field with blanks after them to the width - the stock's
; left-aligned buffer - and a dc level's sign (hop_ampl_signed) takes that
; first cell with the digits from the second, the sign-then-digits
; arrangement $503D arms from $47 ($5066-$506D). The column is
; HOP_VALUE_POS for every stop, where hop_show paints the stored value; the
; stock has a column per field, listed above. Nine columns are written on
; every path, so the ninth is blanked again when an unsigned echo follows a
; signed one, and the cursor is then put after the last character -
; HOP_VALUE_POS plus the count, one more when the sign is there, because
; the stock's head $23A4 counts it ($B556-$B56B). This rendered the digits
; right-aligned in the eight columns, walking leftward as they were typed;
; entry_render in entry.s says what changed and where else.
; ---------------------------------------------------------------------------
hop_entry_echo
                lbsr    hop_entry_geometry      ; IN THE FIELD'S OWN CELLS
                pshs    a,b                     ; 0,s the column, 1,s the width
                ldx     #text_buffer            ; blanks first, then the entry
                ldb     1,s                     ; over them from the head
hop_entry_echo_pad
                lda     #$20
                sta     ,x+
                decb
                bne     hop_entry_echo_pad
                lbsr    hop_ampl_signed         ; carry set: a dc level's
                ldx     #text_buffer            ; AMPL entry (LDX leaves the
                bcc     hop_entry_echo_plain    ; carry)
                lda     >hop_entry_sign         ; $ACE8 / $B038: the sign at
                sta     ,x+                     ; the head, the digits after
hop_entry_echo_plain
                lbsr    ABI_entry_render        ; $B53D-$B555: the digits from
                                                ; the head, blanks to the
                                                ; width
                lda     ,s
                ldx     #text_buffer
                ldb     1,s
                lbsr    ABI_lcd_write_raw       ; the echo: glass only, as
                                                ; lcd_write_string_at ($D8A5)
                lda     ,s                      ; $B556-$B56B: the column plus
                adda    >entry_count            ; the head...
                pshs    a
                lbsr    hop_ampl_signed         ; ...which counts the sign
                puls    a                       ; (PULS leaves the carry)
                bcc     hop_entry_cursor
                inca
hop_entry_cursor
                leas    2,s
                lbra    ABI_lcd_cursor

; ---------------------------------------------------------------------------
; hop_entry_geometry - where the field being typed echoes, and how wide
;
;   exit:  A = the DDRAM column, B = how many columns
;   uses:  A, B
;
; The four arms of $5115 that arm these fields: arm_hop_frequency_editor
; ($5024) eight digits at $1B, entry_cfg_hop_amptd ($503D) SIX at $47 when
; channel 0's waveform is dc and the field is the value rather than the
; increment ($5063-$5083, the same $2514 test show_hop_amptd_field makes at
; $45D8-$45E5) and five at $48 otherwise, entry_setup_hop_phase ($5086) five at
; $5C, entry_cfg_hop_address ($50E6) two at $10.
;
; Every field echoed at the FREQ field's column, nine wide, so a level or a
; phase being typed appeared in the frequency's cells - driven on the stock, a
; level echoes at $48 and a phase at $5C, each in its own brackets.
; ---------------------------------------------------------------------------
hop_entry_geometry
                lda     >hop_field
                cmpa    #HOP_FIELD_AMPL
                beq     hop_geometry_ampl
                cmpa    #HOP_FIELD_PHASE
                beq     hop_geometry_phase
                cmpa    #HOP_FIELD_ADDR
                beq     hop_geometry_addr
                lda     #HOP_F_FREQ
                ldb     #HOP_W_FREQ
                rts
hop_geometry_phase
                lda     #HOP_F_PHASE
                ldb     #HOP_W_PHASE
                rts
hop_geometry_addr
                lda     #HOP_ADRS_POS
                ldb     #HOP_ADRS_W
                rts
hop_geometry_ampl
                lbsr    hop_ampl_signed         ; carry set: the sign column is
                bcc     hop_geometry_ampl_plain ; part of the field, as $47 is
                lda     #HOP_S_AMPL
                ldb     #HOP_W_AMPL+1
                rts
hop_geometry_ampl_plain
                lda     #HOP_F_AMPL
                ldb     #HOP_W_AMPL
                rts

; ---------------------------------------------------------------------------
; hop_field_arm - the hop record's field is armed: the cursor on it
;
;   uses:  A, B, X
;
; THE LCD HALF OF [$3B85] ON THE TWO HOP RECORDS. Every hop arm the stock makes
; is arm_field_editor ($4ED8) with a selector, and the value position it hands
; arm_numeric_entry_field ($AC35) as $23AD is the cursor's cell ($AC98):
;
;   record 5  sel 6  arm_hop_frequency_editor ($5024)  LDB #$1b / STB 3,s
;             sel 7  entry_cfg_hop_amptd ($503D)       $48 at l5076, or $47 at
;                    l5066 when $2514 = 4 (channel 0 dc) and $2215 is not $10
;                    (the increment) - hop_ampl_signed's own test
;             sel 8  entry_setup_hop_phase ($5086)     LDB #$5c / STB 3,s
;             sel 10 entry_cfg_hop_address ($50E6)     LDB #$10 / STB 3,s
;   record 6  sel 9  arm_mode_toggle_editor ($509F)    $10, $24, $50 or $64
;                    for $3B80 = 0, 1, 2 or 3 (l50b4, l50bb, l50c2, l50c9)
;
; hop_entry_geometry already answers record 5 with exactly those columns, and
; hop_row is $3B80 with the same four values (HOP_ROW_PORT 0 to HOP_ROW_PHASE
; 3), whose cells HOP_PORT_STATE to HOP_PHASE_STATE are the four above.
; ---------------------------------------------------------------------------
hop_field_arm
                tst     >hop_page
                bne     hop_field_arm_row
                lbsr    hop_entry_geometry      ; A = $23AD for this field
                lbra    ABI_entry_cursor_on     ; $AC98 and $ACA6, local only
hop_field_arm_row
                ldb     >hop_row
                andb    #HOP_ROWS-1             ; a wild row must not index
                ldx     #hop_row_cells          ; past the four
                lda     b,x
                lbra    ABI_entry_cursor_on

; hop_row_cells - the four On/Off cells of record 6, indexed by hop_row ($3B80)
hop_row_cells
                fcb     HOP_PORT_STATE          ; $3B80 = 0: $10
                fcb     HOP_FREQ_STATE          ; 1: $24
                fcb     HOP_AMPL_STATE          ; 2: $50
                fcb     HOP_PHASE_STATE         ; 3: $64


; ---------------------------------------------------------------------------
; hop_field_address - where the selected field of one slot lives
;
;   entry: B = the slot
;   exit:  U = the field, X = the slot
;   uses:  A, B, X, U
; ---------------------------------------------------------------------------
hop_field_address
                lbsr    hop_slot_address        ; X = the slot
                lda     >hop_field
                cmpa    #HOP_FIELD_AMPL
                beq     hop_field_at_ampl
                cmpa    #HOP_FIELD_PHASE
                beq     hop_field_at_phase
                leau    ,x                      ; HOP_FREQ is zero, and a
                                                ; symbolic zero offset is
                                                ; encoded differently by the
                                                ; two assemblers
                rts
hop_field_at_ampl
                leau    HOP_AMPL,x
                rts
hop_field_at_phase
                leau    HOP_PHASE,x
                rts

; ---------------------------------------------------------------------------
; hop_field_address_of - the same, for a NAMED field rather than the selected
;                        one
;
;   entry: B = HOP_FIELD_FREQ, _AMPL or _PHASE
;   exit:  U = that field of the slot the address selects, X = the slot
;   uses:  A, B, X, U
;
; ALL THREE FIELDS ARE ON THE GLASS AT ONCE on record 0, so the row being
; painted cannot be assumed to be the one the cursor is on - reading hop_field
; there would have painted the same value into all three columns.
; ---------------------------------------------------------------------------
hop_field_address_of
                pshs    b                       ; which field
                ldb     >hop_index              ; THE SLOT, NOT THE NUMBER ON
                                                ; THE GLASS. The stock's three
                                                ; value painters index the
                                                ; record array with the RAW
                                                ; $24F4 ($449D, $45B0, $46CA)
                                                ; while draw_hop_ram_address
                                                ; shows its complement, so the
                                                ; field the screen paints is
                                                ; fifteen minus the address it
                                                ; prints. This called
                                                ; hop_addr_get, and once that
                                                ; returned the printed number
                                                ; the three fields were reading
                                                ; the wrong slot.
                lbsr    hop_slot_address        ; X = the slot
                puls    b
                cmpb    #HOP_FIELD_AMPL
                beq     hop_field_of_ampl
                cmpb    #HOP_FIELD_PHASE
                beq     hop_field_of_phase
                leau    ,x
                rts
hop_field_of_ampl
                leau    HOP_AMPL,x
                rts
hop_field_of_phase
                leau    HOP_PHASE,x
                rts

; ---------------------------------------------------------------------------
; hop_key - the hop table screen's keys
;
;   entry: B = the key code
;   uses:  A, B, X, Y
;
; NEXT and LAST step through the table; digits build a value for the entry
; showing, echoed in the value field as they arrive (hop_entry_echo), and
; BACKSPACE takes the last of them out again (hop_backspace_key); ENTER
; stores it. On the fourth f2 stop, the standing
; hop-RAM address, the digits and ENTER set DDS register $15 and the arrows
; step it - the stock's $6F78 and $7467, see the HOP_FIELD_ADDR comment.
; MINUS on the AMPL field, while channel 0's waveform is dc, makes the entry
; negative: hop_sign_key, with the sign's paint, store and step in the
; routines after hop_addr_enter.
;
; A HOP ENTRY IS A FREQUENCY LIKE ANY OTHER, so it goes through the same
; setter and gets the same ceiling. The fast-hop hardware does not relax the
; 600 kHz limit, and letting the table hold a value the channel cannot
; produce would put the fault a long way from where it was entered.
; ---------------------------------------------------------------------------
hop_key
                ; A REPAINT FIRST, and there was none. Every value a bus
                ; command changes ends in remote_refresh, which delivers
                ; KEY_REFRESH to the installed screen - and this screen had no
                ; arm for it, so a hop slot programmed over the bus went into
                ; the table and into the chip while the glass kept showing the
                ; old one. That is the whole of the fault the hop subsystem
                ; looked like it had: driven 2026-09-13 on the Hop Ram record,
                ; 'FRH 5 KZ;' put 50000 in the slot on both firmwares and the
                ; stock's line 1 read '5.000 kHz' where this one still read
                ; '0.0 Hz'. chan_key answers KEY_REFRESH the same way and for
                ; the same reason; the two hop records are the last two of the
                ; same chain and were the ones left out.
                ;
                ; hop_show paints whichever of the two records hop_page names,
                ; so one arm covers both.
                cmpb    #KEY_REFRESH
                lbeq    hop_key_redraw

                ; GOING LOCAL LETS THE HOP CURSOR GO, as it lets a channel
                ; field go. dispatch_ui_event ($5D0C) is ONE handler for all
                ; seven records, and its $01 arm l5d33 clears $2215, ends the
                ; field edit and re-shows the record (select_menu_page $514D) -
                ; whichever record that is. Traced on the stock, seed 2 step 2:
                ; on Hop Ram with PHASE selected, 'DG;' and then a key, $2215
                ; goes $0E to 0, and INC SET afterwards draws $14 and arms
                ; nothing. This kept the hop field and armed its increment.
                cmpb    #KEY_GONE_LOCAL
                bne     hop_key_not_local
                clr     >hop_entry_active
                clr     >hop_incr_mode
                lbsr    chan_incr_end           ; end_field_edit ($5CE8)
                clr     >field_index            ; l5d33's STD >$2215
                clr     >field_is_hop
                lbra    chan_chain_select       ; select_menu_page ($514D)
hop_key_not_local
                cmpb    #RMT_RQ+$21             ; $21: l5dd9, on these records
                bne     hop_key_not_save        ; as on the other five - the
hop_key_save                                    ; field goes, $2215 = 9, and
                clr     >hop_entry_active       ; the Save prompt opens
                clr     >hop_incr_mode
                lbsr    chan_incr_end           ; end_field_edit ($5CE8)
                clr     >field_index
                clr     >field_is_hop
                lbra    ABI_save_prompt_open    ; $F331 with $0021
hop_key_not_save
                cmpb    #KEY_ABANDON            ; $3C: l5d22, on these records
                bne     hop_key_not_abandon     ; as on the other five
                clr     >hop_entry_active
                clr     >hop_incr_mode
                lbsr    chan_incr_end           ; end_field_edit ($5CE8)
                clr     >field_index
                clr     >field_is_hop
                rts
hop_key_not_abandon

                ; WHICH RECORD IS UP DECIDES WHAT THE SOFTKEYS DO. Record 5,
                ; the field screen, has ONE handler - `fdb request_hop_addr_
                ; entry` as handler word 1 of the record at $4370, with $C239
                ; in the other three - so f1 selects the Adrs row and f2, f3
                ; and f4 do nothing at all. Record 6, the On/Off page at
                ; $437A, has begin_entry_hop_address ($4908) in all four,
                ; which takes the row from the softkey into $3B80.
                ;
                ; This firmware had the four functions on record 5's f1, f3,
                ; f4 and shift-f1, and f2 cycling the fields - none of which
                ; the instrument does. Driven on the stock, 2026-09-10: on
                ; record 5 f2/f3/f4 do nothing and typing does nothing until a
                ; field is chosen; f1 chooses Adrs and the FREQ, AMPL and
                ; PHASE keys choose their own fields.
                ; THE CHAIN'S BUS FIELD SELECTS COME FIRST, on these two
                ; records as on the other five. The stock has ONE handler for
                ; all seven records of the Channel Configuration chain
                ; ($5D0C), and this firmware has two - hop_show installs
                ; hop_key on every repaint - so the hop records could not be
                ; reached by a field-select request at all and answered $2F
                ; where the instrument arms the field. Driven on the stock:
                ; the hop record answers $19-$1D as well as $28-$2A, and
                ; `FRH 100 KZ;` from a channel record reaches the hop slot
                ; because l604e takes bit 3 of event_flags OR $268E = 5.
                ;
                ; NO REPAINT ON THIS PATH: hop_show calls screen_install,
                ; which clears rmt_pend_kind and would throw the arm away
                ; again.
                lbsr    chan_bus_request
                bcs     hop_key_own_arms
                rts
hop_key_own_arms
                cmpb    #RMT_RQ                 ; A REQUEST NOTHING ANSWERED:
                blo     hop_key_panel           ; the chain's l6375 ($6375),
                ldb     #ERR_CHAIN_NO_FUNC      ; $18 through $9DD3 while
                lbra    ABI_error_record        ; remote - 'WSQ;' on the Hop
hop_key_panel                                   ; Ram record (seed 1 step 26)
                tst     >hop_page
                lbne    hop_key_page1

                ; --- record 5: the four field selectors --------------------
                ; f2, f3 AND f4 STILL LET THE FIELD GO: l5d4e clears $2215 and
                ; ends the field edit before dispatch_menu_action reaches this
                ; record's $C239 vectors, as on the channel records.
                cmpb    #KEY_F2
                beq     hop_key_softkey_clear
                cmpb    #KEY_F3
                beq     hop_key_softkey_clear
                cmpb    #KEY_F4
                bne     hop_key_not_softkey
hop_key_softkey_clear
                clr     >hop_entry_active
                clr     >hop_incr_mode
                lbra    chan_key_softkey_clear
hop_key_not_softkey
                ; THE THREE VALUE FIELDS ARE CHOSEN BY THEIR OWN HARD KEYS.
                ; Typing into each after choosing it echoes in that field's
                ; columns - ' FREQ * 1234567     *' at $1B, 'AMPTD * 12345  *'
                ; at $48 and 'PHASE * 12345    *' at $5C - which are the
                ; columns arm_hop_frequency_editor ($5024), entry_cfg_hop_amptd
                ; ($503D) and entry_setup_hop_phase ($5086) arm.
                cmpb    #KEY_F1
                bne     hop_key_sel_freq
                lda     #HOP_FIELD_ADDR
                bra     hop_key_sel_store
hop_key_sel_freq
                cmpb    #KEY_FREQ
                bne     hop_key_sel_ampl
                lda     #HOP_FIELD_FREQ
                bra     hop_key_sel_store
hop_key_sel_ampl
                cmpb    #KEY_AMPL
                bne     hop_key_sel_phase
                lda     #HOP_FIELD_AMPL
                bra     hop_key_sel_store
hop_key_sel_phase
                cmpb    #KEY_PHASE
                bne     hop_key_sel_wave
                lda     #HOP_FIELD_PHASE
hop_key_sel_store
                clr     >hop_incr_mode          ; A SELECT ENDS AN ARMED
                lbsr    chan_incr_end           ; INCREMENT, glyph and all:
                                                ; FREQ, INC SET, FREQ leaves no
                                                ; glyph on the instrument and
                                                ; left it here (measured
                                                ; 2026-09-17, all three fields)
                sta     >hop_field
                lda     #$01                    ; and the field id is this
                sta     >field_is_hop           ; cursor's, as $2215 = $0C, $0D
                                                ; or $0E is the stock's
                lbsr    hop_field_entry_begin   ; a fresh field: the digits
                ldb     >hop_index              ; typed for the last one are
                lbsr    hop_show                ; not this one's
                lbra    hop_field_arm           ; and ARMED: [$3B85] in l607e,
                                                ; l60a1, l60c4 and l60e7

                ; f2 IS NOT A KEY ON THIS RECORD and neither are f3 and f4.
                ; They fall through to the keys the screen does answer and
                ; out through hop_key_done, which is what $C239 does.
hop_key_sel_wave
                ; WAVE FORM IS NOT ANSWERED ON A HOP RECORD. dispatch_ui_event
                ; ($5D0C) sends $19-$1D to d6044 only from records 1 to 4
                ; ($5E9D) or while remote; with $268E = 5 it goes through l604e
                ; to l6161, whose arms are $19, $1A, $1C and $27-$2B and $36 -
                ; no $1B WAVE FORM and no $1D shift WAVE - so both fall to l61a3,
                ; l63b0 and l6375: $18, and nothing selected. $2215 keeps the hop
                ; field. The typed digits are already gone by then:
                ; numeric_entry_key_handler maps the key ($AEFD, $AF0C) and,
                ; with an entry open, entry_exit_restore_display ($B48C) puts
                ; the field back as it stood. Traced on the stock, seed 1 step
                ; 35: PHASE, '8', WAVE FORM - $2217 = $1B, $23DE = $18 from
                ; $63A5, $2215 still $0E, and ' 0.0 deg' back on the glass,
                ; where this selected WFORM and left the '8' showing.
                cmpb    #KEY_WAVEFORM
                beq     hop_key_unanswered
                cmpb    #KEY_S_WAVEFORM
                beq     hop_key_unanswered
                bra     hop_key_incr
hop_key_unanswered
                tst     >hop_entry_active       ; $B48C: only an OPEN entry is
                beq     hop_key_unanswered_err  ; put back
                clr     >hop_entry_active
                ldb     >hop_index
                lbsr    hop_show
hop_key_unanswered_err
                ldb     #ERR_CHAIN_NO_FUNC      ; l6375: $18, through $9DD3
                lbra    ABI_error_record        ; while remote
hop_key_incr
                cmpb    #KEY_INC_SET
                bne     hop_key_up
                tst     >field_is_hop           ; NO HOP FIELD SELECTED: the
                bne     hop_key_incr_hop        ; $62EC arms by $2215 decide,
                lbra    chan_incr_begin         ; which are the channel ones
hop_key_incr_hop
                lda     >hop_field              ; THE ADDRESS HAS NO INCREMENT.
                cmpa    #HOP_FIELD_ADDR         ; The stock's arrows on it go
                bne     hop_key_incr_go         ; through $7467, which adds
                lbra    ABI_key_refuse          ; and subtracts one and reads
                                                ; no increment cell; the
                                                ; $2671-$267D increments serve
                                                ; its FREQ, AMPTD and PHASE
                                                ; rows only
hop_key_incr_go
                lbra    hop_incr_begin
hop_key_up
                cmpb    #KEY_UP
                bne     hop_key_down
                ldb     #$01                    ; forward one increment
                bra     hop_key_step
hop_key_down
                cmpb    #KEY_DOWN
                bne     hop_key_next_t
                ldb     #$FF                    ; and back one
hop_key_step
                ; NO FIELD, NO STEP. The arrows reach step_selected_field
                ; ($71A3), whose guard refuses field id 0 with
                ; reject_step_error_4 through error_report_beep - and a
                ; softkey (l5d4e), $3C or going local leaves $2215 at 0 on a
                ; hop record as on a channel one. hop_field keeps the last
                ; field chosen, so it cannot say whether one is selected;
                ; field_is_hop can. Driven on the emulator, Hop Ram Adrs
                ; record: PHASE, f2, then UP records 4 on the instrument.
                tst     >field_is_hop
                bne     hop_key_step_field
                ldb     #ERR_NO_STEP_FIELD
                lbra    ABI_error_raise
hop_key_step_field
                lda     >hop_field
                cmpa    #HOP_FIELD_ADDR         ; the address steps by one,
                lbeq    hop_addr_step           ; not by an increment
                lbra    hop_step_field

                ; NEXT AND LAST WALK THE WHOLE CHANNEL CONFIGURATION CHAIN,
                ; and they do not change the slot. Driven on the stock,
                ; 2026-09-13, standing on the Hop Ram record: NEXT gives the
                ; hop On/Off page, then '**     Channel Configuration Mode
                ; **', then ch A, ch B, ch C, ch D and round to Hop Ram again;
                ; LAST from the same record gives ch D, ch C, ch B, ch A, the
                ; title, the On/Off page and round. Seven records with the two
                ; hop ones among them - chan_chain_show in page0_screen.s
                ; holds the list and CHAN_CHAIN_HOP is where these two sit in
                ; it - and $24F4 does not move through any of it.
                ;
                ; THESE TWO KEYS USED TO CYCLE THE PAIR OF HOP RECORDS ALONE:
                ; hop_page went 0, 1, 0, 1 while chan_chain stayed wherever
                ; the chain had parked it. So once the operator reached a hop
                ; screen THERE WAS NO KEY THAT LEFT IT - f4 Exit is on the
                ; title record and the title had become unreachable - which
                ; made Channel Configuration a trap on any instrument with
                ; Option 003 fitted. It was found driving the reset that
                ; hop_table_defaults (dds.s) ports: the drive could key a hop
                ; value in and then could not get back out to re-enter the
                ; mode. The chain's own cell is stepped now, exactly as
                ; chan_key_next_key steps it, and chan_chain_show sets
                ; hop_page from it again for records 5 and 6.
                ;
                ; The slot is changed only through the Adrs field, typed or
                ; arrowed. An earlier draft had these two stepping the slot,
                ; which is the chain's motion given to the wrong thing.
hop_key_next_t
                cmpb    #KEY_NEXT
                bne     hop_key_last
                lda     >chan_chain             ; the chain's own limit, as
                cmpa    >chan_chain_last        ; chan_key_next_key
                bhs     hop_key_page_first
                inca
                bra     hop_key_page_store
hop_key_page_first
                clra
                bra     hop_key_page_store
hop_key_last
                cmpb    #KEY_LAST
                lbne    hop_key_enter
                lda     >chan_chain
                bne     hop_key_page_back
                lda     >chan_chain_last
                bra     hop_key_page_store
hop_key_page_back
                deca
hop_key_page_store
                sta     >chan_chain
                sta     >active_record          ; $268E, as chan_key_chain_store
                clr     >hop_entry_active       ; a half-typed field does not
                                                ; follow the record it was on
                lbsr    chan_incr_end              ; nor a pending increment, as
                                                ; chan_key_chain_store cancels
                                                ; one on the same chain step
                ldx     #chan_key               ; AND THE CHAIN'S OWN KEYS GO
                lbsr    ABI_screen_install      ; BACK ON. hop_show installed
                                                ; hop_key when the chain
                                                ; reached record 5 or 6, and
                                                ; chan_chain_show's title and
                                                ; channel arms install nothing
                                                ; - they are only ever reached
                                                ; with chan_key already there.
                                                ; Without this the title
                                                ; painted and f4 Exit did
                                                ; nothing, because hop_key was
                                                ; still the handler and f4 is
                                                ; the Phase Hop row to it. The
                                                ; hop arm of chan_chain_show
                                                ; puts hop_key straight back.
                lbra    chan_chain_select

                ; --- record 6: a row, then ENTER for On or POINT for Off ----
                ; begin_entry_hop_address ($4908) puts the softkey's row in
                ; $3B80 and arms arm_mode_toggle_editor ($509F) - a kind-6
                ; field with no digits, whose choice $221F is set from the key
                ; through the sixteen-record key table at $AFC9-$B003 and
                ; committed straight away. apply_mode_toggle ($6FCB) hands it
                ; to set_hop_function_enable ($4984), which reads $0011 as On
                ; and anything else as Off.
                ;
                ; Driven on the stock: with a row armed, ENTER switches it On
                ; and POINT switches it Off, each on the key, and $2202 bit 8
                ; follows immediately - no second key. Every other key leaves
                ; the row as it was, digits included.
hop_key_page1
                cmpb    #KEY_F1
                bne     hop_key_p1_amptd
                lda     #HOP_ROW_PORT
                bra     hop_key_row_store
hop_key_p1_amptd
                cmpb    #KEY_F2
                bne     hop_key_p1_freq
                lda     #HOP_ROW_AMPL
                bra     hop_key_row_store
hop_key_p1_freq
                cmpb    #KEY_F3
                bne     hop_key_p1_phase
                lda     #HOP_ROW_FREQ
                bra     hop_key_row_store
hop_key_p1_phase
                cmpb    #KEY_F4
                bne     hop_key_p1_on
                lda     #HOP_ROW_PHASE
hop_key_row_store
                sta     >hop_row
                ; AND THE ROW IS ARMED. begin_entry_hop_address ($4908) stores
                ; the row in $3B80 for each of the four softkey requests and
                ; joins l4971, [$3B85] with selector 9 (JSR ,X at $497D):
                ; arm_mode_toggle_editor ($509F), whose value position is $10,
                ; $24, $50 or $64 by $3B80. hop_field_arm has those four.
                lbra    hop_field_arm
hop_key_p1_on
                cmpb    #KEY_ENTER
                bne     hop_key_p1_off
                lda     #LBL_ON
                bra     hop_key_row_apply
hop_key_p1_off
                cmpb    #KEY_POINT
                bne     hop_key_p1_page
                lda     #LBL_OFF
hop_key_row_apply
                ; ONLY ON AN ARMED ROW, AND THE ROW ENDS AND RE-ARMS. The row
                ; is a kind-6 field of units class 0 (arm_mode_toggle_editor
                ; LDD #$0006 / STD 7,s, CLRB / CLRA / STD 5,s), so ENTER and
                ; POINT are characters keypad_char_column_select takes - but
                ; only past lb494's $23A8 test, and with nothing armed $B49D
                ; beeps and takes nothing. Taken, class 0 ends the entry on
                ; the character: $B586 turns the cursor off and $B594 posts
                ; $23, whose arm apply_mode_toggle ($6FCB) calls
                ; set_hop_function_enable ($4984); every path of that routine,
                ; the refusals at l4b65 included, ends at l4bcb in [$3B85]
                ; with selector 9 again (JSR ,X at $4BF7).
                lbsr    ABI_entry_is_open       ; lb494 ($B494); A survives
                lbeq    hop_key_no_entry        ; $B49D: nothing armed, 1
                pshs    a                       ; LBL_ON or LBL_OFF
                lbsr    ABI_entry_cursor_off    ; $B586
                puls    a
                lbsr    hop_row_apply           ; request $23's commit
                lbra    hop_field_arm           ; and l4bcb's [$3B85]
hop_key_p1_page
                cmpb    #KEY_NEXT
                lbeq    hop_key_next_t          ; long: hop_key_page_store's
                                                ; active_record put it past
                                                ; a short branch's reach
                cmpb    #KEY_LAST
                beq     hop_key_last
                lbra    hop_key_done


hop_key_enter
                ; THE THREE UNIT KEYS AND ENTER, all through one lookup. Which
                ; of them this field takes is hop_class_units above, which is
                ; the stock's class for each field; a key the field refuses
                ; beeps rather than doing something else.
                cmpb    #KEY_ENTER
                bne     hop_key_unit_deg
                clrb                            ; column 0
                bra     hop_key_unit
hop_key_unit_deg
                cmpb    #KEY_DEG
                bne     hop_key_unit_hz
                ldb     #1
                bra     hop_key_unit
hop_key_unit_hz
                cmpb    #KEY_HZ
                bne     hop_key_unit_khz
                ldb     #2
                bra     hop_key_unit
hop_key_unit_khz
                cmpb    #KEY_KHZ
                lbne    hop_key_backspace
                ldb     #3
hop_key_unit
                ; A TERMINATOR NEEDS AN ARMED FIELD, and taken it ends the
                ; entry, commits and re-arms. lb494 ($B494) refuses every key
                ; it reaches with $23A8 clear - this screen took the unit keys
                ; whatever was armed, so ENTER after WAVE FORM, NEXT or the
                ; controller's REN committed into the field left behind. Past
                ; that, accept_units_key ($B0C1) returning 1 is $B5BA,
                ; entry_exit_restore_display with 0 - the cursor off - and
                ; request $23 at $B5C8, whose four hop arms each end in
                ; [$3B85] on every path: enter_hop_addr_value ($6F78) at
                ; $6FC4 after l6fae, enter_hop_freq_value ($6FE5) at $705C
                ; after l7040, commit_hop_amptd_entry ($7066) at $70CD after
                ; l70b1, hop_phase_entry ($70DD) at $7159 after l713d. So an
                ; overflow, an empty entry and a refused value re-arm as a
                ; stored one does. hop_key_commit is the body this label used
                ; to be, and every path of it ends in hop_show's RTS.
                lbsr    ABI_entry_is_open       ; lb494; A and B survive
                lbeq    hop_key_no_entry        ; $B49D: code 1
                lbsr    hop_unit_lookup
                lbcs    hop_key_unit_wrong
                stb     >hop_entry_unit
                lbsr    ABI_entry_cursor_off    ; $B5BA
                lbsr    hop_key_commit          ; request $23's commit
                lbra    hop_field_arm           ; and its [$3B85]
hop_key_commit
                lbsr    ABI_entry_value
                lbcs    hop_key_redraw
                lda     >hop_field              ; the address stop commits to
                cmpa    #HOP_FIELD_ADDR         ; register $15, never to a
                lbeq    hop_addr_enter          ; slot or an increment

                ; NOTHING TYPED STORES NOTHING. The stock's three slot arms
                ; convert the buffer with entry_to_scaled_digits ($CDE1),
                ; which returns $FF with no digits, and skip on it:
                ; enter_hop_freq_value ($6FE5) CMPB #$08 / LBCC l7030,
                ; commit_hop_amptd_entry CMPB #$09 / LBCC l70b1 before its
                ; $70AC call of store_hop_amptd, hop_phase_entry ($70DD)
                ; CMPB #$05 / LBCC l713d - and each of those tails puts the
                ; VALUE field's id back in $2215 ($000C, $000D, $000E),
                ; repaints the field and re-arms the entry through [$3B85].
                ; The address arm, enter_hop_addr_value ($6F78), has no such
                ; test and stores what the empty buffer converts to, which
                ; is why it is diverted above this. This stored the zero an
                ; empty buffer converts to, on ENTER with nothing typed and,
                ; now that BACKSPACE can empty an entry, after one was
                ; backspaced away.
                tst     >entry_count
                lbeq    hop_key_empty

                ; THE UNIT SCALES THE DIGITS, and it does so before ANYTHING
                ; else looks at them - before the increment is taken and
                ; before the ceiling is checked. An increment is scaled too:
                ; the stock's set_hop_freq_increment ($4C9F) and
                ; store_hop_amplitude_increment ($4D96) take the keyed
                ; accumulator $221C, which entry_to_scaled_digits ($CDE1) has
                ; already scaled by the unit in $2221. Put after the increment
                ; divert, a step of 1 kHz was stored as a step of 1.
                ; And before the ceiling, because 700 kHz has to be refused as
                ; 7,000,000 tenths of a hertz rather than accepted as the 700
                ; that was typed.
                ; A RADIAN PHASE IS THE ONE FIELD THE GENERIC SCALING CANNOT
                ; TAKE. unit_apply's UNIT_RAD arm converts milliradians into
                ; tenths of a degree, which is what a channel record holds;
                ; a hop slot holds what was typed, in the unit that committed
                ; it, because 6.282 rad is 359.98 degrees and the stock shows
                ; it back as '6.282' rather than as the 6281 a rebuild from
                ; 3599 tenths gives (page0_screen.s's chan_tenths_to_rad
                ; records that 2683 of the 6283 values do not survive the
                ; round trip). So the digits are scaled by a thousand and
                ; stored as they are.
                lda     >hop_field
                cmpa    #HOP_FIELD_PHASE
                bne     hop_key_scale
                lda     >hop_entry_unit
                cmpa    #UNIT_RAD
                bne     hop_key_scale
                lda     >entry_result           ; more than sixteen bits of
                lbne    hop_key_too_big         ; typed digits is far past 6282
                ldd     >entry_result+1
                ; THOUSANDTHS, LESS THE POINT'S FRACTION. unit_scale_decades
                ; takes RAD_DECADES off entry_frac, so '5' is 5000 and '3.1'
                ; is 3100, as the channel screen's chan_entry_scale does. This
                ; multiplied the digits by the ADDRESS of a word holding 1000
                ; (mul16 multiplies by the value in X), so every radian entry
                ; overflowed and was refused in silence, and then by 1000
                ; with the fraction ignored. Measured 2026-09-17 on the Hop
                ; Ram record: 'phase 5 ENTER' and 'phase 3 . 1 ENTER' read
                ; 5.000 rad and 3.100 rad on the instrument.
                ldx     #entry_result
                ldb     #RAD_DECADES
                lbsr    ABI_unit_scale_decades
                lbcs    hop_key_too_big         ; past 24 bits
                bra     hop_key_scaled
hop_key_scale
                ldx     #entry_result
                ldb     >hop_entry_unit
                lbsr    ABI_unit_apply
                lbcs    hop_key_too_big
hop_key_scaled

                ; THE INCREMENT MODE DIVERTS THE SAME ENTRY, one shot, exactly
                ; as on the Channel Configuration screen. An increment is not
                ; bounded by the field's ceiling: a step of 700 kHz is useless
                ; but not dangerous, and the value it produces is checked when
                ; it is stored.
                tst     >hop_incr_mode
                beq     hop_key_value
                clr     >hop_incr_mode
                lbsr    hop_incr_address
                ldu     #entry_result
                lbsr    ABI_copy24
                lbsr    hop_slot_entry_begin
                lbra    hop_key_redraw
hop_key_value

                ; THE CEILING, WHICH WAS NOT CHECKED AT ALL. A hop slot holds
                ; a frequency and the instrument's top frequency is 600 kHz,
                ; and this stored whatever was typed - so a slot could carry a
                ; tuning word the hardware cannot produce, and hop_program
                ; would send it.
                ;
                ; The stock refuses it: its hop entry subtracts the value from
                ; the constant at $EA55 - $5B8D80, six million, the same
                ; ceiling freq_set uses - and on a borrow loads error $71 and
                ; stores nothing.
                ; A FLAT CEILING, not freq_in_range's. That routine takes a
                ; channel record because a channel's top depends on its
                ; waveform and destination; a hop slot has neither, and the
                ; stock's own check here is a plain subtract against the
                ; instrument's top frequency.
                ; EACH FIELD HAS ITS OWN CEILING, and they are the ones the
                ; same values meet everywhere else here: the instrument's top
                ; frequency, the ten-million-microvolt level, and a whole turn
                ; less a tenth. All three are declared in common/formats.inc
                ; because this screen is on a page and cannot see amplitude.s
                ; or phase.s.
                ; THE CHECK ITSELF IS hop_value_in_range, so that the arrows
                ; (hop_step_store) meet the same one - as the stock's step
                ; arms meet the same routines as its ENTER arms.
                ldx     #entry_result
                lbsr    hop_value_in_range
                bcs     hop_key_too_big

hop_key_in_range
                ldb     >hop_index
                lbsr    hop_store_field
                lda     >hop_entry_sign         ; AND A dc LEVEL'S SIGN WITH
                lbsr    hop_sign_store          ; IT: store_hop_amptd ($4CD5)
                                                ; puts the entry sign $241E
                                                ; into hop record+10 at
                                                ; $4D59-$4D71 when $2514 is 4
                                                ; ($4D4F-$4D58), after the
                                                ; value copy at $4D2B-$4D4C
                                                ; and before the re-apply at
                                                ; $4D73
                lda     >hop_field              ; AND SEND THE CHIP WHAT THE
                ldb     >hop_index              ; FIELD'S OWN COMMIT SENDS IT.
                lbsr    ABI_hop_field_commit    ; The table was once written
                                                ; to RAM and never programmed,
                                                ; so the screen edited a list
                                                ; the hardware never saw; then
                                                ; it was programmed on every
                                                ; field with a freshly coded
                                                ; level. The stock's ENTER
                                                ; arms end in $4BFE's d4c26
                                                ; and $4DC7, which send the
                                                ; slot, and in $4CD5, whose
                                                ; re-apply at $4D73 runs only
                                                ; while amplitude hop is on -
                                                ; dds.s hop_field_commit.
                lda     >hop_field              ; AND THE FILTER FOLLOWS A HOP
                cmpa    #HOP_FIELD_FREQ         ; FREQUENCY: ENTER's $702B
                bne     hop_key_stored          ; applies through
                lbsr    ABI_filter_apply        ; apply_hop_frequency_entry
                                                ; ($4BFE), which ends with
                                                ; recompute_channel_byte_24ec
                                                ; ($F7EC) at $4C97 for
                                                ; channel 0's destination
hop_key_stored
                lbsr    hop_slot_entry_begin    ; a fresh field for the next
                                                ; entry, not the digits of the
                                                ; one just stored
                bra     hop_key_redraw          ; AND OUT. Without this the
                                                ; accepted entry fell straight
                                                ; into the refusal below and
                                                ; raised ERR_VALUE_TOO_BIG on
                                                ; every hop frequency the
                                                ; ceiling had just passed.
                                                ; Introduced by the change
                                                ; that added the ceiling.
hop_key_unit_wrong
                ldb     #ERR_KEY_ENTRY          ; the armed field's class has
                lbra    ABI_error_raise         ; no arm for this unit: $B5D0's
                                                ; 2. These went to key_refuse
                                                ; with B holding the COLUMN,
                                                ; not the key, and recorded
                                                ; $0F (seed 2 step 3)
hop_key_no_entry
                ldb     #ERR_NO_ENTRY_FIELD     ; lb494's LDB #$01 into
                lbra    ABI_error_raise         ; error_report_beep ($C3FE),
                                                ; which stores and beeps and
                                                ; reports nothing to the bus
hop_key_too_big
                lbsr    hop_refusal_code        ; carry clear: the field is
                bcc     hop_key_too_big_quiet   ; silent about it
                lbsr    ABI_error_raise
hop_key_too_big_quiet
                lbsr    hop_slot_entry_begin    ; a fresh field, so the
                                                ; refused digits do not linger
hop_key_redraw
                ldb     >hop_index
                lbra    hop_show
hop_key_empty
                lbsr    chan_incr_end           ; an increment's glyph comes
                                                ; down with it: 'phase INC SET
                                                ; ENTER' leaves no glyph on the
                                                ; instrument (measured
                                                ; 2026-09-17)
                clr     >hop_incr_mode          ; l7030/l70b1/l713d: the
                lbsr    hop_slot_entry_begin    ; value's id back, the field
                                                ; re-armed ([$3B85]) and
                bra     hop_key_redraw          ; repainted

hop_key_backspace
                cmpb    #KEY_BACKSPACE
                bne     hop_key_point
                ; THE REST OF THE KEYS NEED AN ARMED FIELD TOO - backspace,
                ; the point, the sign and the digits all reach
                ; entry_backspace ($B2CD) or keypad_char_column_select ($AF29)
                ; only past lb494's $23A8 test, and with it clear $B49D beeps
                ; error 1 and nothing moves.
                lbsr    ABI_entry_is_open       ; lb494
                lbeq    hop_key_no_entry        ; $B49D: code 1
                lbra    hop_backspace_key       ; the last character out of
                                                ; the entry: $B4B9
hop_key_point
                ; THE DECIMAL POINT, as every numeric field on the instrument
                ; takes one - column 7 of keypad_char_table ($EF94). Driven
                ; 2026-09-11: 1 . 5 then kHz is 1.5 kHz in a hop slot on the
                ; stock and was 15 kHz here, the key dropped and the digits run
                ; together.
                cmpb    #KEY_POINT
                bne     hop_key_minus
                lbsr    ABI_entry_is_open       ; lb494 ($B494): $23A8 clear,
                lbeq    hop_key_no_entry        ; code 1
                lbsr    ABI_entry_point
                bcs     hop_key_point_twice
                lbra    hop_entry_echo
hop_key_point_twice
                ldb     #ERR_KEY_ENTRY          ; a second point: $B5D0's 2
                lbra    ABI_error_raise

hop_key_minus
                cmpb    #KEY_MINUS
                bne     hop_key_digit
                lbsr    ABI_entry_is_open       ; lb494
                lbeq    hop_key_no_entry        ; $B49D: code 1
                lbra    hop_sign_key            ; the sign of a dc level's
                                                ; entry on the AMPL field; on
                                                ; any other field, or with
                                                ; channel 0 not dc, dropped
                                                ; as ABI_key_digit's carry
                                                ; dropped it before
hop_key_digit
                lbsr    ABI_key_digit
                bcs     hop_key_done
                lbsr    ABI_entry_is_open       ; NOTHING ARMED, NOTHING TAKEN:
                lbeq    hop_key_no_entry        ; numeric_entry_key_handler's
                                                ; lb494 ($B494) tests $23A8
                                                ; before any character, on
                                                ; every screen, and beeps code
                                                ; 1. A field the bus armed
                                                ; never set it, so after 'DG;'
                                                ; and REN released the
                                                ; instrument refuses '6' where
                                                ; this opened an entry (seed 2
                                                ; step 2)
                lbsr    ABI_entry_digit         ; into the buffer, as $B042-
                                                ; $B065 appends it - a digit
                                                ; past the width is dropped
                                                ; there as $B048's LBCC drops
                                                ; the stock's
                lda     #$01                    ; $B521: a key has been
                sta     >hop_entry_active       ; accepted
                lbra    hop_entry_echo          ; $B53D-$B56B: and the buffer
                                                ; shown. This repainted the
                                                ; stored value (hop_show)
                                                ; instead, so nothing typed
                                                ; appeared until ENTER
hop_key_done
                rts

; ---------------------------------------------------------------------------
; hop_show_onoff - 'ON ' or 'OFF' in one of the four function cells
;
;   entry: A = the LCD position; B = zero for OFF, anything else for ON
;   uses:  A, B, X
;
; draw_mode_on_off_column ($483F) picks name-table index $11 ('On ') or $10
; ('Off ') per row and writes it with $ABA9; the same pair, three
; characters wide, from this file's own strings.
; ---------------------------------------------------------------------------
hop_show_onoff
                ldx     #hop_state_off
                tstb
                beq     hop_show_onoff_write
                ldx     #hop_state_on
hop_show_onoff_write
                ldb     #3
                lbra    ABI_lcd_write

; ---------------------------------------------------------------------------
; hop_switch_freq - the Freq Hop row of set_hop_function_enable ($4984)
;
;   uses:  A, B, X, Y, U
;
; The switch itself - what f1 (hop_func_freq) runs before repainting, and
; what hop_reapply runs for a recalled or preserved snapshot.
;
; The arm at $49D0-$4A6E. SWITCHING ON ($49D0-$4A16): find_max_channel_field
; ($E962) with 6 ($49DB-$49E4) returns the largest frequency held by the
; sixteen hop records, and check_freq_limit ($63D2) is run on it for
; channel 0 ($49ED-$49F8: U = the pointer, Y = 0); a non-zero result is
; error $70, 'Hop Ram Frequencies are too high' in the page-3 message
; table, through error_report_beep ($C3FE) at $4A0E, and the arm leaves
; with nothing written ($4A13 LBRA l4bcb). SWITCHING OFF ($4A19-$4A40): the
; same check on $24F5 - channel 0's own frequency, record+0, where
; commit_channel_frequency ($647B) copies an accepted entry - and error
; $73, 'Last Ch A freq is too great for waveform', at $4A3B. Either way
; through, $4A43-$4A54 dds_mode_param_set ($E69C) with control id $15 and
; the value 8 (on) or 0 (off) writes register $1B - $E72C-$E756: zero and
; bit 8 of $2202 set for 8, $04 and the bit cleared otherwise - then $4A5F
; recompute_channel_byte_24ec ($F7EC) for channel 0's destination and $4A69
; draw_channel_frequency (0).
;
; check_freq_limit is freq_in_range through ABI slot 75, given channel 0's
; record, so the ceiling is the one that channel's waveform and destination
; select ($63D2's 6,000,000 or 500,000; freq_ceiling in frequency.s);
; hop_running is the $2202 bit and hop_enable writes $1B with the value
; $E72C forces. $F7EC is ABI_filter_apply, filter_apply's automatic arm in
; screens_main.s being that routine's derivation, and it runs on both paths
; as l4a43 is reached from both. draw_channel_frequency ($54E6) paints
; nothing unless $23BE equals the displayed page $3B81, which is 6 on this
; screen (draw_mode_on_off_column's guard, and select_menu_page's page 6),
; so the $4A69 repaint lands when channel A's page is next painted:
; chan_show_freq in page0_screen.s paints '*Hop Ram*' there for channel 0
; while hop_running is set, as $54E6 does at l5543 while bit 8 of $2202 is.
; Either way out, hop_snapshot is l4bcb's snapshot of the flags.
; ===========================================================================
; THE BUS'S THREE ENDS OF THE HOP INTERFACE
;
; chan_bus_request (page0_screen.s) is l6161: it arms a field for FRH, APH,
; PHH and HRA, arms a row for AHR/FHR/PHR/DPE, and answers QRE. Two of those
; then need a commit and one needs a reply, and all three belong on this page
; beside the state they touch. The arms themselves stay in the shared routine
; because the stock's are in the shared handler.
; ===========================================================================

; ---------------------------------------------------------------------------
; hop_bus_addr_commit - a number with a unit on the armed Hop Ram Adrs stop
;
;   entry: rmt_val holds the parsed number
;   uses:  A, B, X, Y, U
;
; enter_hop_addr_value ($6F78), arm [17] of commit_entry_to_field ($6B84).
; The stock converts the panel entry buffer with entry_to_scaled_digits
; ($CDE1) - a CONSTANT eight where a unit code would go, so which unit ended
; the entry is never read - and ascii3_to_byte ($CA36); below $10 it stores
; the complement of the result, masked to four bits, in $24F4. This takes the
; number from rmt_val instead, because on this firmware a bus number is
; parsed by remote.s rather than pushed through the panel's digit buffer, and
; hop_addr_put applies the same complement and writes the same DDS register.
;
; ABOVE FIFTEEN NOTHING IS STORED AND NOTHING IS SAID. l6fae is reached from
; both legs: the standing address is written to register $15 again and the
; fields are repainted, with no error on either path. Driven on the stock
; 2026-09-13, Hop Ram record: after 'HRA 3 HZ;' put $0C in $24F4, 'HRA 20 HZ;'
; left it at the value before it with $23DE = 00.
;
; The three-byte test is the same guard the stock's single byte gives it - a
; value that will not fit in a byte cannot be below $10 either.
; ---------------------------------------------------------------------------
hop_bus_addr_commit
                lda     >rmt_val                ; the top two bytes: $6F78 has
                ora     >rmt_val+1              ; only a byte to compare
                bne     hop_bus_addr_keep
                ldb     >rmt_val+2
                cmpb    #HOP_SLOTS              ; $6FA1: CMPB #$10 / LBCC l6fae
                blo     hop_bus_addr_put
hop_bus_addr_keep
                lbsr    hop_addr_get            ; l6fae with nothing stored:
                                                ; the standing address, which
                                                ; hop_addr_put re-complements
hop_bus_addr_put
                lbsr    hop_addr_put            ; $4803's write_reg15_nibble
                lbsr    chan_chain_show         ; and its repaint_hop_fields

                ; AND THE FIELD IS ARMED AGAIN. $6FB6 is `ldu #$000A / ldy
                ; #$0002 / jsr [$3B85]` AFTER the repaint - entry class 10,
                ; the address field, a second time - so the next number needs
                ; no second HRA. Driven on the stock 2026-09-13: 'HRA 3 HZ;'
                ; then a bare '5 KZ;' then a bare '7 DG;' walk $24F4 through
                ; $0C, $0A and $08 with $238F = 01 and $2215 = $0012 the whole
                ; way. Here the repaint is what takes the arm away -
                ; screen_install clears rmt_pend_kind on every screen change
                ; and hop_show calls it - so putting the arm back is not
                ; belt and braces, it is the difference between one address
                ; and a sequence of them.
                lda     #HOP_FIELD_ADDR
                sta     >hop_field
                sta     >field_is_hop           ; $2215 stays $0012 across the
                                                ; sequence, so the field id is
                                                ; this cursor's. A is
                                                ; HOP_FIELD_ADDR, which is 3
                lda     #RK_HOPADDR
                sta     >rmt_pend_kind
                rts

; ---------------------------------------------------------------------------
; hop_bus_row_commit - ON or OF on the armed row of the hop On/Off page
;
;   entry: hop_want holds LBL_ON or LBL_OFF
;   uses:  A, B, X, Y, U
;
; apply_mode_toggle ($6FCB), arm [18] of commit_entry_to_field: LDU >$221F /
; LBSR set_hop_function_enable. hop_want is $221F and hop_row is $3B80, so
; there is nothing to do here but hand the choice over.
; ---------------------------------------------------------------------------
hop_bus_row_commit
                lda     >hop_want
                lbsr    hop_row_apply

                ; THE ROW STAYS ARMED, as the address stop does and for the
                ; same reason: hop_row_apply repaints and the repaint clears
                ; rmt_pend_kind. Driven on the stock 2026-09-13, Hop Ram
                ; record: 'AHR;' then 'ON;' then 'OF;' then 'ON;' switches
                ; Amptd Hop four times - $2203 bit 6 following each one - with
                ; $238F = 01 and $2215 = $0013 throughout, so one AHR arms the
                ; row for every ON and OF that follows it.
                lda     #RK_HOPROW
                sta     >rmt_pend_kind
                rts

; ---------------------------------------------------------------------------
; hop_state_report - QRE: the four switches as one number
;
;   uses:  A, B, X, Y, U
;
; l610d ($610D), instruction for instruction over this firmware's own cells.
; The stock builds LDD #$01E0 / ANDA >event_flags2 / ANDB >$2203, shifts the
; pair right five with shift_signed ($FFA4, B = $FB - a LOGICAL shift, LSRA /
; RORB, with a signed count), and ORs in $10 when bit 5 of $2204 is set. Then
; format_three_digits ($C9D1) writes three zero-padded digits at $2285 and
; queue_gpib_output ($9FFE) sends them with the CR and LF it appends because
; the pointer is $2285.
;
; WHICH BIT IS WHICH, from the painter and the setter and then measured:
;
;   $2204 bit 5   Digital Port   $49AF ORA #$20      -> reported bit 4, 16
;   $2202 bit 0   Freq Hop       $E73E ORA #$01      -> reported bit 3, 8
;   $2203 bit 7   Phase Hop      $E70F ORB #$80      -> reported bit 2, 4
;   $2203 bit 6   Amptd Hop      $E6C1 ORB #$40      -> reported bit 1, 2
;   $2203 bit 5   NOT a hop row  $E6E8 ORB #$20      -> reported bit 0, 1
;
; draw_mode_on_off_column ($483F) tests those same four at $4851, $486D,
; $4889 and $48A5 and writes the four On/Off cells at DDRAM $10, $24, $50 and
; $64. The fifth bit is the Pulse destination - dds_mode_param_set's id $0B,
; which reject_pulse_destination ($7D1D) reads - so an odd reply means Plse is
; routed, not that a fifth switch is on. Driven on the stock 2026-09-13 with
; the reply read back: all off '000', Amptd Hop on '002', Phase Hop on '004',
; Freq Hop on '008', Digital Port on '016', Digital Port and Phase Hop '020'.
;
; mode_flags carries $2203's three bits at $2203's own bit positions, so the
; same five-place shift lands them in the same three places; hop_running is
; the Freq Hop switch; and MODE_FLAG_DIGITAL is $10, which is the weight the
; Digital Port bit has in the reply, so it is ORed in as it stands. That the
; two agree is checked here rather than assumed - test_hop_bus_new.py builds
; the expected number from the four states, not from these cells.
; ---------------------------------------------------------------------------
HOP_QRE_FREQ    equ     $08             ; the Freq Hop bit's weight in the
                                        ; reply: $2202 bit 0 is bit 8 of the
                                        ; word the stock shifts down five

hop_state_report
                lda     >mode_flags             ; ANDB >$2203 with $E0, then
                anda    #MODE_FLAG_PHASE|MODE_FLAG_AM|MODE_FLAG_PULSE
                lsra                            ; the five places $FFA4 moves
                lsra                            ; it with B = $FB
                lsra
                lsra
                lsra
                tst     >hop_running            ; ANDA >event_flags2 with $01,
                beq     hop_report_digital      ; which the same shift puts at
                ora     #HOP_QRE_FREQ           ; bit 3
hop_report_digital
                ldb     >mode_flags             ; $6132: ORB #$10 when bit 5 of
                andb    #MODE_FLAG_DIGITAL      ; $2204 is set
                pshs    b
                ora     ,s+

                clr     >chan_work              ; $C9D1 renders a byte in three
                clr     >chan_work+1            ; columns; uint24_to_text gives
                sta     >chan_work+2            ; eight and the last three are
                ldx     #chan_work              ; the same three, zero-padded
                lbsr    ABI_uint24_to_text      ; and never blanked
                ldx     #text_buffer+5
                ldb     #3
                lbra    ABI_remote_queue        ; $9FFE appends the CR and LF

; ---------------------------------------------------------------------------
; hop_row_apply - switch the armed row of record 6 on or off
;
;   entry: A = LBL_ON or LBL_OFF
;   uses:  A, B, X, Y, U
;
; set_hop_function_enable ($4984) with $3B80 as the row and $221F as the
; choice: $4BB2-$4BC8 dispatches 0 -> $49A1 Digital Port, 1 -> $49D0 Freq Hop,
; 2 -> $4A71 Amptd Hop, 3 -> $4B65 Phase Hop. hop_row is $3B80 and hop_want is
; $221F; each arm below is that arm, and each ends in the snapshot l4bcb
; ($4BCB-$4BDD) takes.
; ---------------------------------------------------------------------------
hop_row_apply
                sta     >hop_want
                lda     >hop_row
                cmpa    #HOP_ROW_FREQ
                beq     hop_row_freq
                cmpa    #HOP_ROW_AMPL
                beq     hop_row_ampl
                cmpa    #HOP_ROW_PHASE
                beq     hop_row_phase
                lbsr    hop_switch_port
                bra     hop_row_shown
hop_row_freq
                lbsr    hop_switch_freq
                bra     hop_row_shown
hop_row_ampl
                lbsr    hop_switch_amptd
                bra     hop_row_shown
hop_row_phase
                lbsr    hop_switch_phase
hop_row_shown
                ; l4BCB repaints the page the switch was made on, and that is
                ; not always this one. set_hop_function_enable's painters all
                ; guard on the DISPLAYED page - repaint_hop_fields ($47C6) and
                ; draw_mode_on_off_column ($483F) both test $3B81 - so from a
                ; channel record the switch repaints the channel record and
                ; leaves the hop page alone. Over the bus that is reachable:
                ; driven on the stock 2026-09-13 with ch A showing, 'AHR;' then
                ; 'ON;' set $2203 to $40 with the channel record still on the
                ; glass. hop_show has no such guard and would paint the hop
                ; page over ch A, so the repaint goes through the chain's own
                ; painter, whose hop arm is `ldb >hop_index / lbra hop_show`
                ; anyway - identical on the two records this key path can be
                ; reached from, and right on the other five.
                lbra    chan_chain_show

; ---------------------------------------------------------------------------
hop_switch_freq
                lda     >hop_want               ; THE DIRECTION IS THE KEY'S.
                cmpa    #LBL_ON                 ; set_hop_function_enable
                bne     hop_func_freq_off       ; ($4984) is told which way to
                                                ; go - $0011 On, anything else
                                                ; Off - and does not flip what
                                                ; it finds. These four read the
                                                ; choice the same way, so
                                                ; pressing ENTER twice leaves a
                                                ; row On, as the instrument
                                                ; does.
                lda     #HOP_FREQ               ; $49DB: field 6, the +4
                lbsr    ABI_hop_field_max       ; frequency of each record
                tfr     y,u                     ; U = the largest one
                ldx     #channel_records        ; $49EF-$49F1: channel 0
                lbsr    ABI_freq_in_range       ; $49F8; Z clear is $63D2
                bne     hop_func_freq_refuse    ; returning its error code
                bra     hop_func_freq_switch
hop_func_freq_off
                ldx     #channel_records        ; $4A19 LDU #$24F5: channel
                leau    ,x                      ; 0's own frequency, CHAN_FREQ
                lbsr    ABI_freq_in_range       ; being zero - $4A25
                bne     hop_func_freq_refuse
hop_func_freq_switch
                lda     >hop_want               ; $4A43-$4A54: the $2202 bit
                cmpa    #LBL_ON                 ; and register $1B
                beq     hop_func_freq_run
                clra
                sta     >hop_running
                bra     hop_func_freq_stop
hop_func_freq_run
                lda     #$01
                sta     >hop_running
                ldb     #HOP_ON
                bra     hop_func_freq_write
hop_func_freq_stop
                ldb     #HOP_OFF
hop_func_freq_write
                lbsr    ABI_hop_enable
                lbsr    ABI_filter_apply        ; $4A5F: $F7EC for channel
                                                ; 0's destination
                lbra    hop_snapshot            ; l4bcb: $267F/$2681
hop_func_freq_refuse
                ldb     #ERR_FREQ_RANGE         ; $70 on, $73 off
                lbsr    ABI_error_raise
                lbra    hop_snapshot

; ---------------------------------------------------------------------------
; hop_switch_amptd - the Amptd Hop row of set_hop_function_enable ($4984)
;
;   uses:  A, B, X, Y, U
;
; The switch itself - what f3 (hop_func_amptd) runs before repainting, and
; what hop_reapply runs for a recalled or preserved snapshot.
;
; The arm at $4A71-$4B62. FIRST, EITHER WAY: with the AM use count $240D or
; the DSB use count $240E non-zero ($4A71-$4A7F), error $6E - 'AM or DSB
; active' - at $4A91 and out. SWITCHING ON ($4A99-$4AF7):
; find_max_channel_field ($E962) with 4 ($4AA4-$4AAD) returns the largest
; level held by the sixteen hop records, channel_sum_exceeds_ref ($B8CC) is
; run on it for channel 0 ($4AB6-$4AC1), and a non-zero result is error
; $6F, 'Hop Ram Amplitudes are too high', at $4AD7 with nothing written;
; else $4ADF-$4AF0 dds_mode_param_set ($E69C) with control id 7 and the
; value 8 writes register $19 as 8 and sets bit 6 of $2203 ($E6AF-$E6C6),
; and 3,s takes the zero constant $EA58 ($4AF2). SWITCHING OFF
; ($4AFA-$4B46): $E69C with 7 and 0 writes $19 as 0 and clears the bit,
; 3,s takes $24FF - channel 0's own level, record+10 ($4B0D) - and $B8CC is
; run on THAT for channel 0 ($4B12-$4B1D): over the reference, copy3
; ($D37D) puts $EA58's zero over $24FF ($4B28-$4B33) and error $7C, 'Last
; Ch A amplitude is too large', is reported at $4B43 - and the arm carries
; on. BOTH then reach l4b48: dispatch_channel_function ($C069) with channel
; 0 and the pointer in 3,s ($4B48-$4B53), then paint_channel_amptd (0) at
; $4B5D. What $C069 does there is set out at ampl_hop_on in amplitude.s
; for the on case; off, its arm_no_action ($C11E) reaches $C1B4 and
; channel_apply_and_propagate ($BE5C) re-applies channel 0 from its record.
;
; Here: hop_destn_in_use is the two counters; ABI_ampl_sum_exceeds is $B8CC
; with hop_ampl_ceiling as the reference (the header at hop_value_in_range
; says why that value); ABI_dds_mode_set is $E69C's id-7 arm, recording
; MODE_FLAG_AM; the on case's $C069 is ABI_ampl_hop_on and the off case's
; is ABI_ampl_set_signed with the record's own level and sign, which
; checks, stores the same bytes and applies - ampl_level_apply, with the
; flag now clear, programming channel 0's own register as $BD8D onward
; does. paint_channel_amptd ($57B1) paints nothing while $3B81 is 6, so the
; $4B5D repaint lands when channel A's page is next painted, where
; chan_show_ampl (page0_screen.s) paints '*Hop Ram*' for channel 0 while
; MODE_FLAG_AM is set as $57B1 does at l57fe while bit 6 of $2203 is. Every
; way out ends in hop_snapshot, l4bcb's snapshot of the flags.
; ---------------------------------------------------------------------------
hop_switch_amptd
                ldb     #LBL_AM                 ; $4A71: $240D
                lbsr    hop_destn_in_use
                bcs     hop_func_amptd_busy
                ldb     #LBL_DSB                ; $4A7A: $240E
                lbsr    hop_destn_in_use
                bcs     hop_func_amptd_busy
                lda     >hop_want
                cmpa    #LBL_ON
                bne     hop_func_amptd_off
                lda     #HOP_AMPL               ; $4AA4: field 4, the +7 level
                lbsr    ABI_hop_field_max       ; Y = the largest one
                tfr     y,x                     ; X = the value
                ldu     #hop_ampl_ceiling       ; the reference
                clrb                            ; $4AB8-$4ABA: channel 0
                lbsr    ABI_ampl_sum_exceeds    ; $4AC1
                bcs     hop_func_amptd_over
                lda     #DDS_AM_CONT            ; $4ADF-$4AF0: $19 = 8, bit 6
                ldb     #DDS_MODE_ON
                lbsr    ABI_dds_mode_set
                lbsr    ABI_ampl_hop_on         ; $4B53 with $EA58
                lbra    hop_snapshot
hop_func_amptd_off
                lda     #DDS_AM_CONT            ; $4AFA-$4B0B: $19 = 0, bit 6
                clrb                            ; clear
                lbsr    ABI_dds_mode_set
                ldx     #channel_records        ; $4B0D: $24FF, channel 0's
                leax    CHAN_AMPL,x             ; own level
                ldu     #hop_ampl_ceiling
                clrb
                lbsr    ABI_ampl_sum_exceeds    ; $4B1D
                bcc     hop_func_amptd_apply
                ldx     #channel_records        ; $4B28-$4B33: zero over $24FF
                leax    CHAN_AMPL,x
                clr     ,x+
                clr     ,x+
                clr     ,x
                ldb     #ERR_AMPL_RANGE         ; $4B38-$4B43: error $7C, and
                lbsr    ABI_error_raise         ; on to the apply
hop_func_amptd_apply
                ldx     #channel_records        ; $4B48-$4B53: $C069 (0, $24FF)
                leau    CHAN_AMPL,x             ; U = the level in the record
                ldy     #ampl_signs
                lda     ,y                      ; channel 0's sign, record+$14
                clrb                            ; channel 0
                lbsr    ABI_ampl_set_signed
                lbra    hop_snapshot
hop_func_amptd_over
                ldb     #ERR_AMPL_RANGE         ; $6F
                lbsr    ABI_error_raise
                lbra    hop_snapshot
hop_func_amptd_busy
                ldb     #ERR_HOP_CONFLICT       ; $6E
                lbsr    ABI_error_raise
                lbra    hop_snapshot

; ---------------------------------------------------------------------------
; hop_switch_phase - the Phase Hop row of set_hop_function_enable ($4984)
;
;   uses:  A, B, X, Y, U
;
; The switch itself - what f4 (hop_func_phase) runs before repainting, and
; what hop_reapply runs for a recalled or preserved snapshot.
;
; The arm at $4B65-$4BAF. With the phase-modulation use count $2410
; non-zero ($4B65-$4B6A), error $72 - 'Phase mod is active' - at $4B79 and
; out. Otherwise $4B81-$4B92 dds_mode_param_set ($E69C) with control id 9
; and the value 8 (on) or 0 (off) writes register $17 and sets or clears
; bit 7 of $2203 ($E6FD-$E721), then $4B94-$4BA0 set_channel_phase ($E562)
; with channel 0 and the word at $250A - channel 0's stored phase, record+
; $15 - re-sends that phase, and $E562 sends ZERO for channel 0 while bit
; 7 is set ($E568-$E58A: channel 0, the bit, CLRB / CLRA / STD >$000A,s
; over the value argument). $4BAA show_channel_phase_field (0) repaints.
;
; Here: hop_destn_in_use for $2410, ABI_dds_mode_set for the id-9 arm
; (MODE_FLAG_PHASE), and ABI_phase_set with channel 0's record and its
; stored CHAN_PHASE - the same value stored again and applied through
; phase_apply, which carries $E568-$E58A's forced zero.
; show_channel_phase_field ($5854) paints nothing while $3B81 is 6, so the
; $4BAA repaint lands when channel A's page is next painted, where
; chan_show_phase (page0_screen.s) paints '*Hop Ram*' for channel 0 while
; MODE_FLAG_PHASE is set as $5854 does at l58b6 while bit 7 of $2203 is.
; Both ways out end in hop_snapshot, l4bcb's snapshot of the flags.
; ---------------------------------------------------------------------------
hop_switch_phase
                ldb     #LBL_PHIM               ; $4B65: $2410
                lbsr    hop_destn_in_use
                bcs     hop_func_phase_busy
                clra                            ; the new state: non-zero on
                ldb     >hop_want
                cmpb    #LBL_ON
                bne     hop_switch_phase_state
                lda     #MODE_FLAG_PHASE
hop_switch_phase_state
                tfr     a,b
                lda     #DDS_PHASE_CTL          ; $4B81-$4B92: $17, bit 7
                lbsr    ABI_dds_mode_set
                ldx     #channel_records        ; $4B94-$4BA0: $E562 (0,
                ldy     CHAN_PHASE,x            ; [$250A])
                clrb
                lbsr    ABI_phase_set
                lbra    hop_snapshot
hop_func_phase_busy
                ldb     #ERR_PHASE_ACTIVE       ; $72, 'Phase mod is active' -
                                                ; $4B79's own code. This named
                                                ; ERR_HOP_CONFLICT and said $72
                                                ; beside it, which is $6B
                lbsr    ABI_error_raise
                lbra    hop_snapshot

; ---------------------------------------------------------------------------
; hop_switch_port - the Digital Port row of set_hop_function_enable ($4984)
;
;   uses:  A, B, X, Y
;
; The switch itself - what shift-f1 (hop_func_port) runs before repainting,
; and what hop_reapply runs for a recalled or preserved snapshot.
;
; The arm at $49A1-$49CD, row 0: On sets bit 13 of event_flags $2204 ($49AC
; LDD >event_flags / $49AF ORA #$20 / $49B3 STD), Off clears it ($49B9 LDD
; / $49BC ANDA #$DF / $49C0 STD), and $49C8 apply_hop_addr_and_repaint
; ($4803) reads the bit back ($480B-$481C) and passes it with $24F4 to
; write_reg15_nibble ($E7C4), which rewrites register $15 as the address
; nibble with bit 4 set from it ($E7D4-$E7E3). No check and no error on
; this row. MODE_FLAG_DIGITAL is the bit here; hop_addr_get and
; hop_addr_put are $4803's read of $24F4 and its $E7C4 call. It falls into
; hop_snapshot, l4bcb's snapshot of the flags.
; ---------------------------------------------------------------------------
hop_switch_port
                lda     >mode_flags             ; $49AF / $49BC
                anda    #~MODE_FLAG_DIGITAL
                ldb     >hop_want
                cmpb    #LBL_ON
                bne     hop_switch_port_store
                ora     #MODE_FLAG_DIGITAL
hop_switch_port_store
                sta     >mode_flags
                lbsr    hop_addr_get            ; $481E: the standing $24F4
                lbsr    hop_addr_put            ; $482E: $E7C4 with the flag
                ; and into hop_snapshot

; ---------------------------------------------------------------------------
; hop_snapshot - record the four enables where a recall and a keep-state boot
;                re-apply them from
;
;   uses:  A, B
;
; The tail of set_hop_function_enable ($4984) at l4bcb ($4BCB), after its two
; repaints: LDD >$2204 / STD >$267F / LDD >$2202 / STD >$2681 - the live flag
; words copied into the snapshot pair every switch ends with, refused or not
; (the error paths reach l4bcb too). hop_saved_flags is that pair: byte 0
; mode_flags, byte 1 hop_running. registers.s carries it in every saved
; register as the stock's 425-byte copy carries $267F/$2681, and hop_reapply
; below is what reads it.
; ---------------------------------------------------------------------------
hop_snapshot
                lda     >mode_flags
                ldb     >hop_running
                std     >hop_saved_flags
                rts

; ---------------------------------------------------------------------------
; hop_reapply - switch the four hop functions to what the snapshot says
;
;   uses:  A, B, X, Y, U
;
; Page 0's fifth entry vector ($400D), run by register_hop_reapply in
; registers.s at the tail of register_apply - after a register recall and at
; a keep-state boot, which are the two paths on which the stock's
; enter_channel_config_mode ($528F) re-applies: past its $5301 LBEQ l53f7
; gate (argument 0, the cold entry, skips this) it copies $267F into 5,s and
; $2681 into 7,s, and l5372 to l53f4 tests four bits in turn and calls
; set_hop_function_enable ($4984) with $3B80 set to the row and $0011, On,
; for each that is set: $267F bit 13 (LDD 5,S / ANDA #$20 / ANDB #$00) -> row
; 0, Digital Port, at l5372; $2681 bit 8 (ANDA #$01) -> row 1, Freq Hop, at
; l5391; bit 6 of the low byte (ANDB #$40) -> row 2, Amptd Hop, at l53b2; bit
; 7 (ANDB #$80) -> row 3, Phase Hop, at l53d3. The snapshot is read into
; locals FIRST, because every $4984 call ends by overwriting $267F/$2681
; from the live words (l4bcb) - the same is done here, and for the same
; reason: hop_snapshot runs at the end of every switch below.
;
; TWO PASSES, where the stock has one. When l5372 runs every enable is
; already off: the recall path has run instrument_preset ($C6EA, $52A9) and
; the keep-state boot's power_on_init ($81AD) has zeroed $2202 and $2204, so
; an On call is all it ever needs. Here the live flags after a recall are
; whatever the operator had before it, so an enable that is on and absent
; from the snapshot is switched off first, through its own switch as its
; key would - then each enable the snapshot carries has its live flag
; cleared and its switch run, which is $4984's On path with its checks,
; its chip writes and its error, whether or not it was already on. At a
; keep-state boot scratch_reset has cleared the live flags, so the first
; pass finds nothing and the second is exactly the stock's.
;
; ORDER RELATIVE TO THE DESTINATIONS, named because it differs: the stock's
; l5372 runs with every record+$21 parked on $10 and the use counts zeroed
; (reapply_all_channels $C5B1 at $530F), and l5401 re-applies the saved
; destinations afterwards; register_apply here has applied the recalled
; destinations already, so a switch's own checks - $240D/$240E for Amptd
; Hop, $2410 for Phase Hop, the sum for Amptd Hop - see the recalled
; routing, and a conflict is refused with the error the key would give.
; ---------------------------------------------------------------------------
hop_reapply
                ldd     >hop_saved_flags        ; the snapshot into locals
                pshs    a,b                     ; first: 0,s mode_flags, 1,s
                                                ; hop_running, the stock's
                                                ; 5,s/7,s

                ; --- off: on now, and not in the snapshot -------------------
                ; EACH PASS DECLARES ITS DIRECTION. The four switches read it
                ; from hop_want, as $4984 reads $221F, rather than flipping
                ; what they find; the "live flag off first" lines in the ON
                ; pass below are what made a flip go the right way and are
                ; kept because the stock's l5372 rows clear the live bit too.
                lda     #LBL_OFF
                sta     >hop_want
                lda     >mode_flags
                bita    #MODE_FLAG_DIGITAL
                beq     hop_reapply_off_freq
                lda     ,s
                bita    #MODE_FLAG_DIGITAL
                bne     hop_reapply_off_freq
                lbsr    hop_switch_port
hop_reapply_off_freq
                tst     >hop_running
                beq     hop_reapply_off_amptd
                tst     1,s
                bne     hop_reapply_off_amptd
                lbsr    hop_switch_freq
hop_reapply_off_amptd
                lda     >mode_flags
                bita    #MODE_FLAG_AM
                beq     hop_reapply_off_phase
                lda     ,s
                bita    #MODE_FLAG_AM
                bne     hop_reapply_off_phase
                lbsr    hop_switch_amptd
hop_reapply_off_phase
                lda     >mode_flags
                bita    #MODE_FLAG_PHASE
                beq     hop_reapply_on
                lda     ,s
                bita    #MODE_FLAG_PHASE
                bne     hop_reapply_on
                lbsr    hop_switch_phase

                ; --- on: l5372's four rows, in its order --------------------
hop_reapply_on
                lda     #LBL_ON
                sta     >hop_want
                lda     ,s                      ; l5372: $267F bit 13, the
                bita    #MODE_FLAG_DIGITAL      ; Digital Port
                beq     hop_reapply_on_freq
                lda     >mode_flags
                anda    #~MODE_FLAG_DIGITAL     ; the live flag off, so the
                sta     >mode_flags             ; switch is the On path
                lbsr    hop_switch_port
hop_reapply_on_freq
                tst     1,s                     ; l5391: $2681 bit 8, Freq Hop
                beq     hop_reapply_on_amptd
                clr     >hop_running
                lbsr    hop_switch_freq
hop_reapply_on_amptd
                lda     ,s                      ; l53b2: bit 6, Amptd Hop
                bita    #MODE_FLAG_AM
                beq     hop_reapply_on_phase
                lda     >mode_flags
                anda    #~MODE_FLAG_AM
                sta     >mode_flags
                lbsr    hop_switch_amptd
hop_reapply_on_phase
                lda     ,s                      ; l53d3: bit 7, Phase Hop
                bita    #MODE_FLAG_PHASE
                beq     hop_reapply_done
                lda     >mode_flags
                anda    #~MODE_FLAG_PHASE
                sta     >mode_flags
                lbsr    hop_switch_phase
hop_reapply_done
                leas    2,s
                rts

; ---------------------------------------------------------------------------
; hop_destn_in_use - does any channel have this destination?
;
;   entry: B = the destination code
;   exit:  carry SET when at least one channel record holds it
;   uses:  A, X
;
; The stock keeps a use count per destination code: counter_addr_am
; ($7837) hands out $240D for code 7 (AM), counter_addr_dsb ($784F) $240E
; for $0A (DSB) and dest_count_addr_pm ($7847) $2410 for 9 (PhiM), all
; through destination_use_count_addr ($782A), and set_channel_destination
; ($78BF) - the writer of record+$21 - decrements the old code's counter
; and increments the new one. reapply_all_channels ($C5B1) zeroes all of
; them at $C601-$C619 after setting every record+$21 to $10 ($C5BB-$C5FA),
; then re-applies each saved destination through $78BF. So a counter is
; non-zero exactly when a record holds its code, and this firmware, which
; keeps no counters, walks the four CHAN_DEST bytes instead.
; ---------------------------------------------------------------------------
hop_destn_in_use
                ldx     #channel_records
                lda     #CHANNEL_MAX
                pshs    a
hop_destn_next
                cmpb    CHAN_DEST,x
                beq     hop_destn_found
                leax    CHAN_RECORD,x
                dec     ,s
                bne     hop_destn_next
                puls    a
                andcc   #~CC_CARRY
                rts
hop_destn_found
                puls    a
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; hop_value_in_range - is a value within the selected field's ceiling?
;
;   entry: X = the value, three bytes, most significant first
;   exit:  carry SET when it is above the ceiling, clear when it fits
;   uses:  A, B, U - and Y through ABI_ampl_sum_exceeds
;
; ONE CHECK FOR BOTH PATHS. ENTER (hop_key_value) and the arrows
; (hop_step_store) commit through it, as the stock's do through
; apply_hop_frequency_entry ($4BFE), store_hop_amptd ($4CD5) and
; set_hop_entry_phase ($4DC7) - each called from its ENTER arm and from its
; step arm, with the ceiling inside; hop_step_store names the call sites.
; The ceilings are the ones the same values meet everywhere else here: the
; instrument's top frequency (the stock's $EA55, 6,000,000, loaded at
; $4C2F), the ten-million-microvolt level (the stock's $EA62, $98 $96 $80,
; which $503D points $23B7 at) and a whole turn less a tenth (the stock's
; $EA5B, $0E $0F = 3599, compared at $4DFA). All three are declared in
; common/formats.inc because this screen is on a page and cannot see
; amplitude.s or phase.s.
;
; A FLAT CEILING, not freq_in_range's. That routine takes a channel record
; because a channel's top depends on its waveform and destination; a hop
; slot has neither, and the stock's own check at $4C29-$4C3D is a plain
; subtract against the instrument's top frequency.
;
; THE ADDRESS STOP NEVER ARRIVES HERE: hop_key_enter diverts it to
; hop_addr_enter and hop_key_step to hop_addr_step before either path is
; reached, and the stock's $6F78 and $7467 have their own stop at $10.
;
; AND THE LEVEL, WHILE AMPLITUDE HOP IS ON, IS CHECKED AS A SUM - the
; stock's $4CDB-$4CF6, set out at hop_range_ampl below.
; ---------------------------------------------------------------------------
; ---------------------------------------------------------------------------
; hop_refusal_code - what this field says when it will not take a value
;
;   exit:  carry SET and B = the error code, or carry CLEAR when the field
;          refuses in silence
;   uses:  A, B
;
; EACH FIELD HAS ITS OWN REFUSAL, AND ONE OF THEM IS SILENCE.
; apply_hop_frequency_entry ($4BFE) reports $71 for a frequency;
; store_hop_amptd ($4CD5) reports $7A for a level; and set_hop_entry_phase
; ($4DC7) reports NOTHING for a phase - over $EA5D (6282, in radians) or
; $EA5B (3599, in tenths of a degree) it branches to its own exit at $4E84,
; stores nothing and beeps nothing, there being no error_report_beep
; anywhere on that path.
;
; Both paths that can refuse a value use this: the ENTER commit and the
; arrows' step, as the stock's two paths both end in those same three
; routines. It raised 'Number too large' ($13) for all three, which the
; instrument raises for none of them.
; ---------------------------------------------------------------------------
hop_refusal_code
                lda     >hop_field
                cmpa    #HOP_FIELD_PHASE
                beq     hop_refusal_silent
                cmpa    #HOP_FIELD_AMPL
                beq     hop_refusal_ampl
                ldb     #ERR_HOP_WAVE_FREQ      ; $71, the frequency's own
                bra     hop_refusal_raise
hop_refusal_ampl
                ldb     #ERR_AMPL_RANGE         ; $7A, whichever of the two
                                                ; amplitude checks refused it
hop_refusal_raise
                orcc    #CC_CARRY
                rts
hop_refusal_silent
                andcc   #~CC_CARRY
                rts

hop_value_in_range
                lda     >hop_field
                cmpa    #HOP_FIELD_AMPL
                beq     hop_range_ampl
                cmpa    #HOP_FIELD_PHASE
                beq     hop_range_phase

                ; A FREQUENCY, AND THE CEILING DEPENDS ON WHETHER THE HOP IS
                ; RUNNING. apply_hop_frequency_entry ($4BFE) range-checks the
                ; entry with check_freq_limit ($63D2) when bit 8 of $2202 is
                ; set and against the flat $EA55 - $5B8D80, six million tenths,
                ; 600 kHz - when it is not; either refusal is error $71.
                ;
                ; The difference is real: $63D2 reads channel 0's own
                ; destination and waveform and drops the ceiling to $07A120
                ; (50 kHz) for a 'Plse' destination or a Ramp, Trngl or Sq
                ; waveform. While the hop is running those slots ARE channel
                ; A's frequency, one after another, so a slot the channel's
                ; own waveform cannot produce is refused as the channel would
                ; refuse it; while it is stopped the slot is only a number in
                ; a table and the flat top applies.
                ;
                ; hop_running is that bit, and ABI_freq_in_range is $63D2
                ; without its error code - hop_switch_freq already uses it the
                ; same way for the whole table.
                tst     >hop_running
                beq     hop_range_freq_flat
                tfr     x,u                     ; the value to test
                ldx     #channel_records        ; $49EF: channel 0's record
                lbsr    ABI_freq_in_range       ; Z clear is $63D2's non-zero
                tfr     u,x                     ; X back, for the callers that
                bne     hop_range_over          ; reuse it
                bra     hop_range_ok
hop_range_freq_flat
                lda     ,x
                cmpa    #TOP_FREQ_HI
                blo     hop_range_ok
                bhi     hop_range_over
                lda     1,x
                cmpa    #TOP_FREQ_MID
                blo     hop_range_ok
                bhi     hop_range_over
                lda     2,x
                cmpa    #TOP_FREQ_LO
                bhi     hop_range_over          ; exactly 600 kHz is fine
                bra     hop_range_ok

hop_range_ampl
                ; WHILE AMPLITUDE HOP IS ON, THE SUM. store_hop_amptd ($4CD5)
                ; tests bit 6 of $2203 at $4CDB-$4CE9 (LDD >event_flags2 /
                ; ANDA #$00 / ANDB #$40 / CMPD #$0000 / LBEQ l4d00 - the bit
                ; dds_mode_param_set mirrors from the amplitude-hop control
                ; register, MODE_FLAG_AM in mode_flags here) and with it set
                ; runs channel_sum_exceeds_ref ($B8CC) at $4CF6 with channel
                ; 0 and the entry $221C ($4CEA-$4CF5: LDU #$221C / CLRB / SEX
                ; / TFR D,Y / LDX #$0004 / PSHS X,Y,U) IN PLACE OF
                ; ref_value_below ($B8AD, the $4D09 call the clear bit
                ; takes); either result goes to 2,s and a non-zero one is
                ; error $7A ($4D10-$4D28). The reference is the same either
                ; way: $23B7 points at $EA62, 10,000,000, from
                ; entry_cfg_hop_amptd's $5041-$5046. So the entry plus the
                ; levels of channels 1 to 3 that go where channel 0 goes,
                ; or are DSB, must neither carry out of 24 bits nor exceed
                ; it - and channel 0 set to Off is never over, while phase
                ; modulation is the entry alone; ampl_sum_exceeds in
                ; amplitude.s is $B8CC line by line. Both paths meet it
                ; here, as the stock's four calls of $4CD5 ($70AC, $7590,
                ; $75BC, $7602) meet $4CF6.
                lda     >mode_flags
                bita    #MODE_FLAG_AM
                beq     hop_range_ampl_alone
                clrb                            ; $4CED: channel 0
                ldu     #hop_ampl_ceiling       ; $EA62, through $23B7
                lbsr    ABI_ampl_sum_exceeds    ; $4CF6; the carry is the
                rts                             ; answer
hop_range_ampl_alone
                lda     ,x                      ; microvolts
                cmpa    #TOP_AMPL_HI
                blo     hop_range_ok
                bhi     hop_range_over
                lda     1,x
                cmpa    #TOP_AMPL_MID
                blo     hop_range_ok
                bhi     hop_range_over
                lda     2,x
                cmpa    #TOP_AMPL_LO
                bhi     hop_range_over
                bra     hop_range_ok

hop_range_phase
                ; THE CEILING IS THE UNIT'S, because the two scales differ.
                ; set_hop_entry_phase ($4DC7) compares $221A with $EA5B = 3599
                ; at $4DF7-$4E03 and with $EA5D = 6282 for unit code 4 at
                ; $4DD7-$4DE3 - tenths of a degree against thousandths of a
                ; radian, which is why a slot has to remember which one it
                ; holds. Driven on the stock: 3 then ENTER stores 3000 and
                ; shows '3.000 rad'; 180 then deg stores 1800 and shows
                ; '180.0 deg'.
                lda     ,x                      ; either scale is sixteen bits
                bne     hop_range_over
                ldd     1,x
                cmpd    #TOP_PHASE
                bls     hop_range_ok
                lda     >hop_entry_unit
                cmpa    #UNIT_RAD
                bne     hop_range_over
                ldd     1,x                     ; AGAIN: A WAS THE UNIT. The
                                                ; compare below used D with the
                                                ; unit code in its high byte, so
                                                ; 7000 read as $0458 and 7 rad
                                                ; passed where the instrument
                                                ; refuses it (measured
                                                ; 2026-09-17: 'phase 7 ENTER'
                                                ; leaves 0.0 deg there)
                cmpd    #CHAN_RAD_MAX           ; 6282, the word at $EA5D
                bhi     hop_range_over
hop_range_ok
                andcc   #~CC_CARRY
                rts
hop_range_over
                orcc    #CC_CARRY
                rts

; hop_ampl_ceiling - the hop level's reference, 10,000,000 microvolts: the
; stock's $EA62 ($98 $96 $80), which entry_cfg_hop_amptd ($503D) points
; $23B7 at ($5041-$5046) for ref_value_below and channel_sum_exceeds_ref
; alike. Three bytes most significant first, as ampl_sum_exceeds takes U.
hop_ampl_ceiling
                fcb     TOP_AMPL_HI,TOP_AMPL_MID,TOP_AMPL_LO

; ---------------------------------------------------------------------------
; hop_open - the mode entry point, reached through this page's $4004 vector
;
;   uses:  A, B, X, Y
;
; The hop table is the fast-hop mode's list of frequencies. The chip steps
; through it in hardware, which is why it is programmed rather than clocked
; from the foreground - the foreground's tick has milliseconds of jitter and
; fast hop is the one thing here that cannot tolerate any.
;
; Option 003 gates it, and an instrument without that option says so instead
; of painting a screen whose every key would be refused.
; ---------------------------------------------------------------------------
hop_open
                lbsr    hop_available           ; carry CLEAR means fitted
                bcs     hop_open_refused

                ; NO FIELD IS ARMED AND THE STANDING SLOT IS KEPT. Driven on
                ; the stock, 2026-09-10: arriving at the screen and typing does
                ; nothing at all - digits go nowhere until f1 or one of the
                ; FREQ, AMPL and PHASE keys chooses a field - and the address
                ; the screen shows is the one $24F4 already held, which is
                ; battery RAM and survives leaving the screen.
                ;
                ; This armed an entry on arrival and cleared the slot to zero.
                ; The arming let a digit typed with no field chosen land in
                ; whichever field was last used, and the clear moved the
                ; standing hop-RAM address every time the screen was opened -
                ; the chip's playing position, which nothing on this screen is
                ; supposed to touch until the operator types one.
                ;
                ; Nothing arms the shared entry field here, and entry_digit
                ; refuses a digit that is not below entry_base - zero until
                ; somebody sets it - so a digit typed before a field is chosen
                ; is thrown away, which is what the instrument does with it.
                clr     >hop_entry_active

                ; AND ON THE FIELD RECORD, whichever record was up last time.
                ; Entering the Channel Configuration chain always lands on its
                ; head: f1 from the Main Selection gives the title screen and
                ; the hop records are five and six NEXTs along, every time. So
                ; the mode entry point opens record 5, not the record the
                ; operator left the mode on.
                clr     >hop_page
                ldb     >hop_index
                lbra    hop_show

; ---------------------------------------------------------------------------
; hop_entry_begin - arm the shared entry field for a hop frequency
;
;   uses:  A, B, X
;
; A hop frequency is a frequency: the same decimal base and the same width as
; the Channel Configuration screen's FREQ field, so a value typed here means
; the same thing as one typed there.
; ---------------------------------------------------------------------------
hop_entry_begin
                clr     >hop_entry_active       ; THE ENTRY ENDS HERE: the
                                                ; stock's $AC84 clears its
                                                ; first-key flag $23A7 as a
                                                ; field is armed, and the
                                                ; next hop_show paints the
                                                ; stored value again
                lda     #CHAN_SIGN_PLUS         ; A FRESH ENTRY IS POSITIVE:
                sta     >hop_entry_sign         ; the stock's kind-2 field
                                                ; pre-places '+' at the head
                                                ; of $239A as it is armed
                                                ; ($ACE8 LDB #$2B / $ACEA STB
                                                ; >$239A) and only MINUS
                                                ; ($B038) replaces it, so a
                                                ; level typed with no MINUS
                                                ; commits as '+'. hop_sign_key
                                                ; is the one writer of '-'
                ; AS MANY DIGITS AS THE FIELD HAS COLUMNS, not the frequency
                ; field's eight for all of them. The four arms of $5115 arm
                ; eight ($5024), five or six ($503D), five ($5086) and two
                ; ($50E6); this armed CHAN_W_FREQ for every one, so a level and
                ; a phase each took three digits more than the instrument lets
                ; them have.
                lbsr    hop_entry_geometry      ; B = the field's columns
                pshs    b
                lbsr    hop_ampl_signed         ; a dc level spends one of them
                puls    b                       ; on the sign
                bcc     hop_entry_begin_arm
                decb
hop_entry_begin_arm
                lda     #ENTRY_DECIMAL
                lbra    ABI_entry_begin
hop_open_refused
                ldb     #ERR_NO_OPTION
                lbra    ABI_error_raise

; ---------------------------------------------------------------------------
; hop_field_entry_begin - arm the shared entry field for the stop f2 is on
;
;   uses:  A, B, X
;
; The address stop takes two digits, as the stock's entry_cfg_hop_address
; ($50E6) arms for its field 10; the three slot fields keep the eight-digit
; decimal field hop_key_field_store and hop_key_select armed before this
; routine existed (hop_entry_begin and then ABI_entry_begin_dec - the second
; call is the one whose width stands, and both are kept so that path is
; unchanged).
; ---------------------------------------------------------------------------
hop_field_entry_begin
                lda     >hop_field
                cmpa    #HOP_FIELD_ADDR
                beq     hop_addr_entry_begin
                lbra    hop_slot_entry_begin

; ---------------------------------------------------------------------------
; hop_slot_entry_begin - re-arm the eight-digit field for a slot's value or
;                        increment, with its units
;
;   uses:  A, B, X
;
; EVERY RE-ARM IS A WHOLE ARM ON THE STOCK. Each time the instrument puts a
; hop field back after ENTER, an arrow, a refused or an empty entry, it goes
; through [$3B85] to arm_numeric_entry_field ($AC35) again, and $AC55-$AC59
; and the $AD3A arms store $23AF and $23AE afresh - so the first key of the
; NEXT entry blanks the units as the first key of the first one did. Five
; sites here re-armed with hop_entry_begin and ABI_entry_begin_dec alone,
; which zeroes the units width, and the next digit left the label standing:
; seed 2 step 132, PHASE '2' after a stored phase, the stock showing
; '2         ' and this firmware '2     deg'. entry_cfg_hop_amptd tests
; $2215 = $10 at $5056-$5059, which is the increment reaching the same arm with
; the same class; the units below are the value's and the increment's alike.
; On the address stop no units are named, as class 2 names none ($AD21).
; ---------------------------------------------------------------------------
hop_slot_entry_begin
                lbsr    hop_entry_begin
                lbsr    ABI_entry_begin_dec

                ; AND WHERE THIS FIELD'S UNITS ARE, so the first key typed
                ; blanks them - $B524-$B538's run, at the column the field was
                ; armed with and as wide as its units class says. The three
                ; classes here are the stock's: arm_hop_frequency_editor
                ; ($5024) class 6 -> three characters at $24, entry_cfg_hop_
                ; amptd ($503D) class 4 -> two at $4E, entry_setup_hop_phase
                ; ($5086) class 3 -> three at $62. The address field is class 2
                ; and has no units, which entry_begin's own zero covers.
                lda     >hop_field
                cmpa    #HOP_FIELD_AMPL
                beq     hop_field_units_ampl
                cmpa    #HOP_FIELD_PHASE
                beq     hop_field_units_phase
                cmpa    #HOP_FIELD_ADDR         ; class 2: entry_begin's zero
                beq     hop_field_units_none    ; stands
                lda     #HOP_U_FREQ
                ldb     #UNIT_LABEL_LEN
                lbra    ABI_entry_units
hop_field_units_ampl
                lda     #HOP_U_AMPL
                ldb     #HOP_UNITS_W_AMPL       ; $4E, two: 'uV ' leaves its
                                                ; trailing space standing, as
                lbra    ABI_entry_units         ; the stock's class 4 does
hop_field_units_phase
                lda     #HOP_U_PHASE
                ldb     #UNIT_LABEL_LEN
                lbra    ABI_entry_units
hop_field_units_none
                rts

; ---------------------------------------------------------------------------
; hop_addr_entry_begin - arm a two-digit decimal field for the address
;
;   uses:  A, B, X
; ---------------------------------------------------------------------------
hop_addr_entry_begin
                clr     >hop_entry_active       ; the entry ends, as in
                lda     #ENTRY_DECIMAL          ; hop_entry_begin
                ldb     #HOP_ADDR_DIGITS
                lbra    ABI_entry_begin

; ---------------------------------------------------------------------------
; hop_addr_get - the standing hop-RAM address, as the operator typed it
;
;   exit:  B = 0 to 15
;   uses:  A, B, X, Y - Y through ABI_dds_read
;
; Read back out of the register shadow rather than kept in a byte of its
; own: the stock keeps a copy at $24F4 and the chip's byte at $24AE (offset
; $24 of its $248A shadow, the byte dds_write_channel $DE2E restores into
; $15), and the two hold the same nibble because $4803 is the only path from
; one to the other. One copy here means they cannot disagree. The four-bit
; complement undoes the one enter_hop_addr_value ($6F78) applied, exactly as
; draw_hop_ram_address ($43D4) undoes it before printing.
; ---------------------------------------------------------------------------
hop_addr_get
                ; THE NUMBER ON THE GLASS IS FIFTEEN MINUS THE SLOT, and the
                ; slot is hop_index. Driven on the stock, 2026-09-10: typing 3
                ; into the Adrs field leaves $24F4 = $0C and writes register
                ; $15 = $0C, 7 leaves $08 and 0 leaves $0F; and the three value
                ; painters index the record array with that RAW $24F4
                ; ($449D, $45B0, $46CA), so the record the screen shows and the
                ; chip slot it is programmed into are both 15 minus the number
                ; the Adrs field displays. draw_hop_ram_address ($43D4) is the
                ; only place the complement is taken.
                ;
                ; THIS READ THE REGISTER BACK and complemented it, which left
                ; the Adrs field and the three value fields looking at
                ; different slots - the field said 15 on a cold boot, where the
                ; instrument says 0, and typing an address moved the field
                ; without moving the record underneath it.
                lda     #HOP_SLOTS-1
                suba    >hop_index
                tfr     a,b
                andb    #HOP_SLOTS-1
                rts

; ---------------------------------------------------------------------------
; hop_addr_put - make one address the standing one, in the chip and the shadow
;
;   entry: B = the address, 0 to 15
;   uses:  A, B, X, Y - Y through ABI_hop_addr_send
;
; This is $6F78's store followed by apply_hop_addr_and_repaint ($4803), and
; the byte itself is built by write_reg15_nibble ($E7C4) - which is in A2U12,
; because reapply_all_channels ($C5B1) ends with the same call at $C6BB. So
; the build lives there too, in hop_addr_send (dds.s), and this stores the
; standing address and calls it. It used to build the byte here as well, and
; a second copy of $E7C4 is exactly what the two callers of the real one do
; not have.
;
; The four bits are the complement of the typed number, because that is what
; $6F78 stores at $24F4 for $4803 to pass on. What hop_addr_send then adds -
; bit 4 from MODE_FLAG_DIGITAL, being bit 13 of event_flags $2204 as $4803
; reads it at $480B-$481C - is the same for both callers, so it reads that
; flag itself and this hands it nothing.
; ---------------------------------------------------------------------------
hop_addr_put
                negb                            ; the slot is fifteen minus the
                addb    #HOP_SLOTS-1            ; number that was typed, which
                andb    #HOP_SLOTS-1            ; is what $6F78 stores in $24F4
                stb     >hop_index              ; and what $E7C4 then writes
                lbra    ABI_hop_addr_send       ; into the register's low
                                                ; nibble

; ---------------------------------------------------------------------------
; hop_addr_step - the up and down arrows on the address stop
;
;   entry: B = $01 to step up, $FF to step down
;   uses:  A, B, X, Y
;
; step_hop_addr ($7467): the displayed number goes up by one and stops at
; $0F, or down by one and stops at 0, and apply_hop_addr_and_repaint ($4803)
; runs on every path including the clamped ones - the register is rewritten
; with the standing value even when nothing moved. Same here.
; ---------------------------------------------------------------------------
hop_addr_step
                pshs    b                       ; the direction
                lbsr    hop_addr_get            ; B = the standing address
                puls    a                       ; the direction back. PULS
                tsta                            ; sets no flags, so the sign
                bmi     hop_addr_step_down      ; test needs this TSTA - the
                                                ; flags at this point are the
                                                ; ANDB #$0F in hop_addr_get,
                                                ; whose N is always clear
                cmpb    #HOP_ADDR_MAX           ; $7467: CMPB #$0F / LBEQ
                beq     hop_addr_step_apply
                incb
                bra     hop_addr_step_apply
hop_addr_step_down
                tstb                            ; $7467: CMPB #$00 / LBEQ
                beq     hop_addr_step_apply
                decb
hop_addr_step_apply
                lbsr    hop_addr_put
                lbsr    hop_addr_entry_begin    ; and field 10 re-armed: every
                                                ; path of step_hop_addr
                                                ; ($7467) - clamped or not -
                                                ; reaches l7497, which calls
                                                ; apply_hop_addr_and_repaint
                                                ; and then [$3B85] with
                                                ; selector 10, so the digits
                                                ; typed before the arrow are
                                                ; gone, as on the three
                                                ; increment fields
                                                ; (hop_step_done)
                ldb     >hop_index
                lbsr    hop_show
                lbra    hop_field_arm           ; $74AD JSR ,X: the cursor
                                                ; on the address, local only

; ---------------------------------------------------------------------------
; hop_addr_enter - ENTER on the address stop
;
;   entry: entry_result holds the typed value, three bytes, high first
;   uses:  A, B, X, Y
;
; enter_hop_addr_value ($6F78): below 16 the value is stored and written to
; $15; 16 and above the store is skipped, the standing address is written to
; $15 again, and the field is re-armed - and no error is reported on either
; path, so none is here. The field is two digits wide, so the top byte test
; is the same guard $6F78's byte compare gives against a value that could
; never be typed.
;
; Reached from hop_key_enter before the increment-mode test, because the
; stock has no increment for this field ($7467 reads none) and an increment
; armed on a slot field and then carried across f2 to this stop would
; otherwise take the address as a frequency step. The one-shot is cleared
; rather than honoured.
; ---------------------------------------------------------------------------
hop_addr_enter
                clr     >hop_incr_mode
                ldx     #entry_result
                lda     ,x                      ; anything in the top byte is
                bne     hop_addr_enter_keep     ; 65536 and up
                ldd     1,x
                cmpd    #HOP_ADDR_MAX           ; $6F78: CMPB #$10 / LBCC
                bhi     hop_addr_enter_keep
                lbsr    hop_addr_put            ; B = the typed address
                bra     hop_addr_enter_rearm
hop_addr_enter_keep
                lbsr    hop_addr_get            ; l6fae: the standing value
                lbsr    hop_addr_put            ; is written again, unchanged
hop_addr_enter_rearm
                lbsr    hop_addr_entry_begin    ; and field 10 is re-armed
                lbra    hop_key_redraw

; ---------------------------------------------------------------------------
; hop_chan0_dc - is channel 0's waveform dc?
;
;   exit:  carry SET when it is
;   uses:  A, X
;
; THE HOP SCREEN'S SIGN TESTS ALL READ CHANNEL 0, not the channel the
; operator last edited: the stock's hop routines test $2514 - offset $1F of
; the first of the four 35-byte channel records at $24F5, the array $C21A
; and $FCEA index ($2514 - $24F5 = $1F, the waveform word the channel
; screen reads through $23BF) - at $4D4F-$4D58 in store_hop_amptd ($4CD5),
; $504C-$5055 in entry_cfg_hop_amptd ($503D), $45D8-$45E1 in
; show_hop_amptd_field ($4579) and $753C-$7545 in step_hop_amplitude
; ($7533), every one LDX >$2514 / CMPX #$0004. Channel 0 is the channel
; amplitude hop drives: the comment in modules/dds.s hop_program records
; scale_to_dds_code ($D3EC) being called for it at $BC8C. Here channel 0's
; record is the first CHAN_RECORD at channel_records, its waveform is
; CHAN_WAVE, and LBL_DC is the code chan_ampl_signed in page0_screen.s
; compares it against.
; ---------------------------------------------------------------------------
hop_chan0_dc
                ldx     #channel_records        ; channel 0's record
                lda     CHAN_WAVE,x
                cmpa    #LBL_DC                 ; $2514 = 4
                bne     hop_chan0_not_dc
                orcc    #CC_CARRY
                rts
hop_chan0_not_dc
                andcc   #~CC_CARRY
                rts

; ---------------------------------------------------------------------------
; hop_ampl_signed - is the AMPL entry in its signed layout?
;
;   exit:  carry SET when the AMPL field is selected, channel 0's waveform
;          is dc and no increment entry is armed; clear otherwise
;   uses:  A, X
;
; entry_cfg_hop_amptd ($503D), the hop counterpart of the channel screen's
; amptd_limit_volt_units ($4F6D): after the 10,000,000 ceiling ($EA62 into
; $23B7, $5041-$5046) it tests $2514 against 4 at $504C-$5055 and $2215
; against $10 at $5056-$505F, and only dc with the VALUE field selected
; arms the signed layout - kind 2, six characters from $47 ($5066-$5072) -
; in place of kind 3, five from $48 ($5076-$5082). Kind 2 is the layout
; whose MINUS is accepted ($B030 CMPB #$2D / $B038 STB >$239A; the
; kind-to-key-column selection at $AF29-$AF5F is set out at chan_sign_key
; in page0_screen.s); the increment field, $2215 = $10, stays kind 3 and
; refuses it. hop_incr_mode is that $10 here.
; ---------------------------------------------------------------------------
hop_ampl_signed
                lda     >hop_field
                cmpa    #HOP_FIELD_AMPL
                bne     hop_ampl_unsigned
                tst     >hop_incr_mode          ; $5056-$505F: the increment
                bne     hop_ampl_unsigned       ; is unsigned
                lbra    hop_chan0_dc            ; $504C-$5055, and its carry
                                                ; is the answer
hop_ampl_unsigned
                andcc   #~CC_CARRY
                rts


; ---------------------------------------------------------------------------
; hop_sign_store - a dc level's sign into its slot
;
;   entry: A = the sign, '+' or '-'
;   exit:  hop_signs[hop_index] = it, when the AMPL field is selected and
;          channel 0's waveform is dc; nothing written otherwise
;   uses:  A, B, X
;
; store_hop_amptd ($4CD5), after copying the accepted value into hop
; record+7 ($4D2B-$4D4C), tests $2514 against 4 at $4D4F-$4D58 and stores
; the entry sign $241E into hop record+10 at $4D59-$4D71 (STB ,X at $4D71)
; - and for any other waveform leaves that byte as it was. Both of its
; callers here commit the AMPL field: hop_key_value with hop_entry_sign
; (the stock's $70AC call, $241E from the entry) and hop_step_field with
; hop_step_sign (the $7590, $75BC and $7602 calls, $241E as
; step_hop_amplitude left it). hop_key_value serves every field, so the
; field is tested here, where the stock's routine is reached for the AMPTD
; field alone. A single byte, so no interrupt mask: the sequencer's read
; cannot see half of it.
; ---------------------------------------------------------------------------
hop_sign_store
                pshs    a                       ; the sign
                lda     >hop_field
                cmpa    #HOP_FIELD_AMPL
                bne     hop_sign_store_none
                lbsr    hop_chan0_dc            ; $4D4F-$4D58
                bcc     hop_sign_store_none
                ldb     >hop_index
                ldx     #hop_signs              ; hop record+10, $4D59-$4D71
                puls    a
                sta     b,x
                rts
hop_sign_store_none
                puls    a
                rts

; ---------------------------------------------------------------------------
; hop_step_ampl_sign - the sign an AMPL step carries, and the direction it
;                      really moves in
;
;   entry: hop_step_field's frame above the return address: 2,s the
;          increment pointer, 4,s the direction byte, +1 up or $FF down
;   exit:  hop_step_sign = the slot's sign when channel 0's waveform is dc,
;          zero for any other; 4,s negated when that sign is '-'
;   uses:  A, B, X
;
; step_hop_amplitude ($7533), instruction by instruction: $7533-$753B LDX
; 4,s / LEAX 10,x / LDB ,x / STB >$241E caches the hop record's sign
; character; $753C-$7545 LDX >$2514 / CMPX #$0004 / LBNE tests channel 0's
; waveform for dc, and $7546-$754E LDB >$241E / CMPB #$2D / LBNE the sign
; for '-'; only both together reach $7555-$7560 LDD >$000E,s / EORA #$00 /
; EORB #$01 / STD >$000E,s, which inverts the direction word in
; step_selected_field ($71A3)'s frame. So 'up' on a negative level moves it
; towards zero and 'down' away from it. The stock caches the sign for every
; waveform and stores it back only for dc ($4D4F); here a non-dc step
; leaves hop_step_sign zero and hop_sign_store stores nothing, exactly as
; the step did before this routine existed.
; ---------------------------------------------------------------------------
hop_step_ampl_sign
                lbsr    hop_chan0_dc            ; $753C-$7545
                bcc     hop_step_ampl_done
                ldb     >hop_index
                ldx     #hop_signs              ; hop record+10, $7533-$753B
                lda     b,x
                cmpa    #CHAN_SIGN_MINUS        ; $7549 CMPB #$2D
                beq     hop_step_ampl_neg
                lda     #CHAN_SIGN_PLUS         ; anything else is positive,
                bra     hop_step_ampl_keep      ; as it is to $D4E7
hop_step_ampl_neg
                neg     4,s                     ; $7555-$7560: the direction
                                                ; inverted in the caller's
                                                ; frame; +1 and $FF negate
hop_step_ampl_keep
                sta     >hop_step_sign
hop_step_ampl_done
                rts

; ---------------------------------------------------------------------------
; hop_sign_key - MINUS: the AMPL entry of a dc level goes negative
;
;   uses:  A, B, X, Y - B, X and Y through hop_entry_echo
;
; With the signed layout armed (hop_ampl_signed), the stock's entry key
; handler takes '-' at $B030 CMPB #$2D and puts it at the head of the
; buffer whatever has been typed so far ($B038 STB >$239A); only a fresh
; field ($ACE8) puts '+' back. entry_to_scaled_digits copies that head to
; $241E ($CE1B), and store_hop_amptd ($4CD5) stores $241E into the slot at
; commit. Here the head is hop_entry_sign: hop_entry_begin pre-places '+',
; this puts '-', and hop_sign_store stores it at ENTER.
;
; THE SIGN IS ECHOED AS A DIGIT IS. keypad_char_column_select returns 1
; for the '-' it stored ($B03B-$B03E), so numeric_entry_key_handler's
; first-key and buffer writes at $B516-$B56B run for it exactly as for a
; digit, and the glass shows '-' at the field's column followed by
; whatever digits were typed before it. Here that is hop_entry_active set
; and hop_entry_echo called, the two steps hop_key_digit takes. On every
; other field, and on the AMPL field with channel 0 not dc or an increment
; armed, the key is dropped as ABI_key_digit's carry dropped it before this
; routine existed (hop_sign_key_ignore is an RTS); the stock's kind-3
; layout rejects it at $AFD7 CMPB #$58.
; ---------------------------------------------------------------------------
hop_sign_key
                lbsr    hop_ampl_signed         ; carry set: a dc level's
                bcc     hop_sign_key_ignore     ; AMPL entry
                lda     #CHAN_SIGN_MINUS        ; $B038: '-' at the head of
                sta     >hop_entry_sign         ; the buffer
                lda     #$01                    ; $B521: a key has been
                sta     >hop_entry_active       ; accepted
                lbra    hop_entry_echo          ; $B53D: and the buffer shown
hop_sign_key_ignore
                ldb     #ERR_KEY_ENTRY          ; the armed field's column has
                lbra    ABI_error_raise         ; no '-': $B5D0's 2. This was
                                                ; silent (seed 1 step 24)

; ---------------------------------------------------------------------------
; hop_backspace_key - BACKSPACE: the last character of the entry comes out
;
;   uses:  A, B, X, Y - B, X and Y through hop_entry_echo
;
; entry_backspace ($B2CD), reached from numeric_entry_key_handler at $B4B9
; for every key that is not a mode key or a field select and acting on
; BACKSPACE alone ($B2D7 CMPX #$001F): for the kinds this screen's fields
; are armed in - 3 for the frequency ($5024), the phase ($5086) and an
; unsigned level ($5076-$5082), 0 for the address ($50E6: CLRB / CLRA / STD
; 7,s), 2 for a dc level ($5066-$5072) - it steps the head $23A4 back one
; unless it is zero and blanks the vacated cell ($B2E9-$B31F), except that
; kind 2 steps back only while a digit follows the sign ($B320 CMPB #$01 /
; LBLS) and otherwise puts '+' back at the head with the head at 1
; ($B351-$B35A). The handler repaints the buffer from the field's column
; with the cursor after its last character ($B4D0-$B501) only once a key
; has been accepted into it - $B4C4 tests the first-key flag $23A7 and
; leaves at $B4CD with it clear, the buffer it stepped being the one the
; arming had just filled with spaces ($ACC5-$ACE0) and, for kind 2, '+'
; ($ACE8).
;
; hop_entry_active is that flag here (hop_key_digit and hop_sign_key set
; it; hop_entry_begin and hop_addr_entry_begin clear it): clear, the key
; does nothing, as $B4CD does nothing. Set, a dc level's entry with no digit
; left takes the kind-2 reset, '+' into hop_entry_sign; every other entry
; loses its last digit through ABI_entry_backspace, the stock's $B2E9-$B31F
; on this editor's buffer. Either way hop_entry_echo repaints the value
; field and places the cursor, as $B4D0-$B501 does.
; ---------------------------------------------------------------------------
hop_backspace_key
                tst     >hop_entry_active       ; $B4C4: no key accepted yet,
                beq     hop_backspace_none      ; nothing to take out or show
                lbsr    hop_ampl_signed         ; carry set: the kind-2 layout
                bcc     hop_backspace_digit
                tst     >entry_count            ; $B320-$B325: a digit after
                bne     hop_backspace_digit     ; the sign comes out; with
                lda     #CHAN_SIGN_PLUS         ; none left the sign goes
                sta     >hop_entry_sign         ; back to '+' ($B351-$B35A)
                lbra    hop_entry_echo          ; $B4D0-$B501: repainted
hop_backspace_digit
                lbsr    ABI_entry_backspace     ; $B2E9-$B31F: the last digit
                lbra    hop_entry_echo          ; $B4D0-$B501
hop_backspace_none
                rts
