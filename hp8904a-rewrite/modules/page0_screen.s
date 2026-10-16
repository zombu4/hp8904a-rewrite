; ===========================================================================
; page0_screen.s - Channel Configuration: the instrument's main screen
;
; This is where the instrument is actually used. Everything else exists to
; get here or to store what was set here.
;
; THE LAYOUT, both lines, forty columns each:
;
;   Ch n  FREQ nnnnnn.nn Hz AMPL nn.nnnnnn V
;   PHASE nnn.nnnnn deg WAVE Trngl DEST Out1
;
; DRAWN FROM THE DECLARED POSITIONS below, not from memory. The version that
; was here put four fields in the wrong columns and two at the wrong width -
; it showed the frequency seven characters wide where CHAN_W_FREQ is nine,
; and put AMPL at column 25 where CHAN_F_AMPL is 29. A diagram a reader sizes
; a new field against is worth nothing if it disagrees with the equates
; fifty lines down.
;
; Six editable fields on one screen, so a channel can be set up without
; leaving it. The stock screen shows the same six and this keeps that, but
; every value is shown WITH ITS UNITS rather than as a bare number - a
; frequency of 6000 means nothing without knowing whether the field is in Hz
; or kHz, and the stock screen leaves the operator to remember which unit key
; they last pressed.
;
; THE COLUMN POSITIONS WERE COMPUTED, NOT COUNTED. Every position below comes
; from laying the two lines out once and reading the offsets off the result.
; Counting columns by eye is exactly how a menu label became twenty-one
; characters and shifted the handler address of its own record.
;
; NAVIGATION. NEXT and LAST move between the six fields and wrap. A field is
; edited by typing digits, or for WAVE and DEST by pressing NEXT/LAST while
; the field is selected, which cycles through the choices. ENTER commits the
; field. Nothing is written to the hardware until ENTER, and a refused value
; leaves both the record and the hardware exactly as they were.
;
; THE PHASE FIELD HAS TWO TERMINATORS, AND ENTER IS THE RADIAN ONE. That is
; the stock's key map, not a choice made here: arm_phase_editor ($4FDF) opens
; the PHASE field with units class 3 (LDD #$0003 / STD 5,s), and for class 3
; accept_units_key ($B0C1) dispatches to unit_key_class3 ($B0F3), whose whole
; body is CMPX #$001B / BEQ -> $2221 = 4 and CMPX #$001C / BEQ -> $2221 = 3.
; Code $1B is the key the Keyboard Check names ' enter ' (keycheck_arm_enter
; $4996, page 3) and $1C the one it names ' deg ' (key_name_arm_degree
; $49A2); unit 4 is 'rad' and unit 3 'deg' in the label table at $EEEE. So on
; the stock a phase typed and closed with ENTER is in radians and one closed
; with deg is in degrees, and this screen does the same: KEY_ENTER on PHASE
; goes to chan_commit_phase_rad, KEY_DEG on PHASE to chan_commit. Digits are
; typed in the unit's smallest count, so 3140 ENTER is 3.140 rad and 1800 deg
; is 180.0 degrees. The value is STORED in tenths of a degree either way
; (phase.s keeps one representation) and SHOWN in the unit last used, which
; is what the stock does: show_channel_phase_field ($5854) paints record+$15
; in degrees when record+$19 is 3 and record+$17 in radians otherwise, and
; set_phase_units_and_apply ($6E46) stores the terminator's unit code $2221
; into record+$19 before it looks at the digits. The twin this screen keeps
; in place of record+$17 is described at chan_phase_rad below.
;
; WHY NOTHING COMMITS EARLY. Committing each digit would put the output
; through every intermediate value on the way to the one that was wanted - so
; typing 600000 would pass through 6, 60, 600, 6000 and 60000 Hz, and an
; instrument feeding something sensitive would sweep across five decades on
; every entry.
; ===========================================================================

; --- the two template lines ------------------------------------------------
; The labels sit at their final columns and every value position holds a
; space, so writing a template erases whatever the previous screen had there
; and the values are then written over the gaps.
; THE STOCK'S OWN TWO LINES, from the screen template at page 0 $424D:
;
;     'ch  : FREQ              AMPTD           '
;     'PHASE            WFORM        DESTN     '
;
; This firmware had 'Ch 1  FREQ ... AMPL' and 'WAVE ... DEST', with every
; field in a different column and the channel as a NUMBER. Driven side by
; side, not one of the eighty characters agreed. It is the screen an operator
; spends the most time on.
;
; The unit labels are NOT part of the template here, as they were: the stock
; writes one beside each value through lcd_write_unit_label ($ABEF), because
; a frequency can read Hz or kHz and a level V, mV or microvolts.
; RECORD 0 OF THE CHAIN, menu_text_page0_config ($41FD), byte for byte.
chan_title_l1   fcc     "**     Channel Configuration Mode   "
                fcc     "  **"
chan_title_l2   fcc     "Pres"
                fcc     "s NEXT/LAST keys.    "
                fcb     $00,$04,$20,$45,$78
                fcc     "it        "
CHAN_CHAIN_HOP  equ     5               ; records 5 and 6 are the Hop Ram
CHAN_CHAIN_LEN  equ     7               ; fields and the hop On/Off page

; ---------------------------------------------------------------------------
; chan_screen_line1, chan_screen_line2 - the channel record's two lines
;
; The frame the values are written into, forty characters each, exactly as the
; instrument's own record at $4348 carries them: 'ch  :' with the channel
; letter going into column 3, then each field's label with its columns left
; blank for the value. Driven character for character against the stock in
; emulator/tests/test_parity_screens.py.
; ---------------------------------------------------------------------------
chan_screen_line1
                fcc     "ch  : FREQ              AMPTD           "
chan_screen_line2
                fcc     "PHASE            WFORM        DESTN     "

; --- where each field sits, as a DDRAM address and a width -----------------
;
; EVERY NUMERIC FIELD IS NINE CHARACTERS, because that is exactly what the
; formatter produces: eight digits from the shared converter plus the decimal
; point. Nothing is truncated, and the point therefore sits in a fixed column
; within each field whatever the value.
;
; They were eight, seven and five, which truncated. Truncating the END of a
; frequency drops the tenths - 600000.0 showed as 600000. - and truncating a
; five-character phase field left nothing but spaces, because a phase below
; 100 degrees has four leading spaces before its first digit. Both faults
; were visible on the emulated screen and neither was visible in the source.
;
; The unit labels are part of the TEMPLATE rather than written separately.
; They never change - a frequency is always in Hz here and an amplitude
; always in volts - so writing them on every repaint was three LCD writes and
; three routines' worth of code for a result that was already on the glass.
; Line 2's addresses carry LCD_LINE2 because the HD44780 puts the second line
; at DDRAM $40 rather than at 40 - the two lines are not contiguous in the
; controller's memory even though they are on the glass.
; The formatter always produces eight digits and one point, so every numeric
; field is that wide and nothing is ever cut.
; --- the stock's columns, read out of the instructions that write them ----
;
;   FREQ    draw_channel_frequency ($54E6) blanks twelve columns at DDRAM $0B
;           ($550E), writes EIGHT characters there ($561D) and the unit label
;           at $14 ($5634). $0B is line 1 column 11 and $14 is column 20.
;   AMPTD   paint_channel_amptd ($57B1) blanks nine at $1F ($57C9) and hands
;           $564E the value column $1F and the unit column $25 ($5837/$583C);
;           write_unit_label_and_digits ($576C) then writes the label at $25,
;           ONE character at $1F-1 and FIVE of the value at $1F.
;   PHASE   show_channel_phase_field ($5854) blanks ten at $46 ($5881), writes
;           FIVE at $46 ($5981) and the label at $4C ($5998). $46 is line 2
;           column 6 and $4C is column 12.
;   WFORM   draw_channel_waveform ($59B3) writes at $57, line 2 column 23.
;   DESTN   paint_channel_destn ($59E7) writes at $64, line 2 column 36.
;
; Every one of those positions is an immediate in the stock. Nothing on this
; screen has a computed column except the AMPTD sign, which is the value
; column less one ($5781 SUBD #$0001).
CHAN_F_CHAN     equ     LCD_LINE1+3     ; the channel LETTER, before the ':'
CHAN_W_CHAN     equ     1
CHAN_M_FREQ     equ     LCD_LINE1+$0A   ; the increment markers, the
CHAN_M_AMPL     equ     LCD_LINE1+$1D   ; columns set_field_marker_at_column
CHAN_M_PHASE    equ     LCD_LINE2+$05   ; ($C855) is handed by each painter
CHAN_F_FREQ     equ     LCD_LINE1+11
CHAN_W_FREQ     equ     8               ; the stock writes eight of the nine
                                        ; format_with_decimal_point makes,
                                        ; from $2415 - character 0 is dropped
CHAN_U_FREQ     equ     LCD_LINE1+20
CHAN_HOP_W_FREQ equ     12              ; columns 11-22, value and label
CHAN_F_AMPL     equ     LCD_LINE1+31
CHAN_W_AMPL     equ     5
CHAN_AMPL_FIELD_W equ   9               ; the whole field, which
                                        ; paint_channel_amptd ($57B1)
                                        ; blanks at $1F before it writes
CHAN_S_AMPL     equ     LCD_LINE1+30    ; the sign of a dc level, which the
                                        ; stock puts one column left of the
                                        ; value
CHAN_U_AMPL     equ     LCD_LINE1+37
CHAN_HOP_W_AMPL equ     9               ; columns 31-39
CHAN_F_PHASE    equ     LCD_LINE2+6
CHAN_W_PHASE    equ     5
CHAN_U_PHASE    equ     LCD_LINE2+12
CHAN_HOP_W_PHASE equ    10              ; columns 6-15
CHAN_F_WAVE     equ     LCD_LINE2+23
CHAN_W_WAVE     equ     5
CHAN_F_DEST     equ     LCD_LINE2+36
CHAN_W_DEST     equ     4

; --- the PHASE unit label, which the stock repaints with the value ---------
; show_channel_phase_field ($5854) ends by calling lcd_write_unit_label
; ($ABEF) with record+$19 as the unit code and DDRAM $4C as the position
; ($5996-$59AB), and $ABEF indexes the pointer table at $EEEE: entry 3 is
; `fcb $03,$64,$65,$67` ('deg', $EF1A) and entry 4 is `fcb $03,$72,$61,$64`
; ('rad', $EF1E), three characters each after the length byte. The labels are
; NOT in the template any more - the stock writes one beside each value
; through $ABEF, which is ABI_unit_label here, and their columns are declared
; with the rest of the geometry above.
CHAN_UW_PHASE   equ     UNIT_LABEL_LEN
CHAN_UW_FREQ    equ     UNIT_LABEL_LEN

; --- '*Hop Ram*' in a channel 0 field a hop function is driving -------------
; The stock's own string, d4384 ($4384): `fcc "*Hop Ram*    "`, nine
; characters and four blanks. draw_channel_frequency ($54E6) writes twelve of
; them at DDRAM $0B for channel 0 while bit 8 of $2202 is set (l550e blanks
; twelve at $0B; LDB >$23BE / CMPB #$00 / LBNE l5540, LDD >$2202 / ANDA #$01 /
; ANDB #$00 / CMPD #$0000 / LBEQ l5540; l5543 LDU #d4384 / lcd_write_clipped
; $D8EA twelve at $0B / LBRA l564b), paint_channel_amptd ($57B1) nine at $1F
; while bit 6 of $2203 is set (l57c9, l57fe) and show_channel_phase_field
; ($5854) ten at $46 while bit 7 is (l5881, l58b6) - in each the count covers
; the units column too ($14, $25, $4C), so the unit goes blank under it.
; Executed on the emulator (the stock booted, f1, NEXT, the three bits set in
; $2202/$2203, NEXT and LAST): channel A's page reads
;   'ch A: FREQ *Hop Ram*    AMPTD  *Hop Ram*'
;   'PHASE *Hop Ram*  WFORM Sine   DESTN Out1'
; and channel B's page is unchanged. Here hop_running is the $2202 bit and
; MODE_FLAG_AM/MODE_FLAG_PHASE the two $2203 bits; the widths cover the field
; and its unit as the stock's counts do - CHAN_HOP_W_FREQ, CHAN_HOP_W_AMPL and
; CHAN_HOP_W_PHASE are declared with the rest of the geometry above and are
; the stock's own twelve, nine and ten.
chan_hop_marker
                fcc     "*Hop Ram*    "

; ---------------------------------------------------------------------------
; chan_blank_limit - leading zeros to spaces, but not past a limit
;
;   entry: X = the buffer, B = how many characters may be blanked
;   uses:  A, B, X
;
; blank_leading_zeros ($CCFF). The LIMIT is what makes it different from
; blanking every leading zero, and the difference is visible: with the point
; four digits in, a value of 1000 tenths renders '   01000' - the zero at
; index 3 survives - so the field reads '0.1000' rather than '.1000'. A point
; with nothing in front of it is not a number.
; ---------------------------------------------------------------------------
chan_blank_limit
                tstb
                beq     chan_blank_done
chan_blank_next
                lda     ,x
                cmpa    #'0'
                beq     chan_blank_put
                cmpa    #' '
                bne     chan_blank_done
chan_blank_put
                lda     #' '
                sta     ,x+
                decb
                bne     chan_blank_next
chan_blank_done
                rts

; ---------------------------------------------------------------------------
; chan_point - n digits with a decimal point dropped in
;
;   entry: U = the digits, X = where the result goes, A = n, B = the index
;          the point takes in the OUTPUT
;   exit:  n+1 characters at the destination
;   uses:  A, B, X, U
;
; format_with_decimal_point ($CD50), which walks a source index and an output
; index and emits the point on the pass where the output index reaches dp,
; without advancing the source. Written here as two copies either side of the
; point, which is the same thing and shorter.
;
; The stock's callers then write from output character ONE, not zero: the
; ninth character is produced and dropped. That is not an accident of theirs -
; it is how a value that has grown a digit still ends in the same column.
; ---------------------------------------------------------------------------
chan_point
                pshs    a,b                     ; 0,s n, 1,s dp
                lda     1,s
                bsr     chan_point_copy         ; the digits before the point
                ldb     #'.'
                stb     ,x+
                lda     ,s
                suba    1,s
                bsr     chan_point_copy         ; and the ones after it
                leas    2,s
                rts
chan_point_copy
                tsta
                beq     chan_point_copy_done
chan_point_copy_next
                ldb     ,u+
                stb     ,x+
                deca
                bne     chan_point_copy_next
chan_point_copy_done
                rts

; The stock's two frequency layouts, from draw_channel_frequency ($54E6):
; unit code 2 (' Hz') blanks up to six leading zeros and puts the point after
; seven digits ($55B6/$55C9); anything else blanks up to three and puts it
; after four, and then blanks the last character if it is a zero
; ($55EC/$5600/$55FB).
CHAN_FREQ_BLANK_HZ equ  6
CHAN_FREQ_DP_HZ equ     7
CHAN_FREQ_BLANK_KHZ equ 3
CHAN_FREQ_DP_KHZ equ    4
; And the two phase layouts, from show_channel_phase_field ($5854): five
; digits either way, the point after four for degrees ($593F) and after two
; for radians ($595C).
;
; THE BLANKING IS NOT SHARED BETWEEN THEM, and reading it as if it were is
; what put ' . 00 rad' on the glass where the instrument puts '0.000 rad'.
; The stock's unit switch at l5909 ($5909) is `CMPX #$0003 / LBNE l5946`, and
; blank_leading_zeros ($CCFF) is called at $592D, which is INSIDE the equal
; arm - the DEGREE arm, $5909-$5945. The radian arm l5946 ($5946) runs
; u16_to_5_ascii_digits ($C912) over record+$17, stores the point position 2
; and falls into the shared tail l5960 ($5960) with the digits untouched, so
; a zero milliradian value keeps its leading '0' and reads '0.000'. Blanking
; three of five with the point two in eats that digit AND the first fraction
; digit, leaving ' . 00'. paint_phase_increment ($5B98) is built the same way:
; $CCFF at its degree arm only, and l5c02 ($5C02) - the radian arm - goes
; straight from $C912 to `LDB #$02 / STB 2,s`.
CHAN_PHASE_DIGITS equ   5
CHAN_PHASE_BLANK_DEG equ 3              ; '  0.0' for zero, '359.9' at the top
CHAN_PHASE_BLANK_RAD equ 0              ; '0.000' for zero, '6.282' at the top
CHAN_PHASE_DP_DEG equ   4
CHAN_PHASE_DP_RAD equ   2

; --- which unit each channel's phase was last entered in ------------------
; The codes are the stock's. unit_key_class3 ($B0F3) stores 4 in $2221 for
; key $1B (ENTER, 'rad') and 3 for key $1C (deg), and set_phase_units_and_apply
; ($6E46) copies $2221 to record+$19. The default record init_channel_blocks
; ($C4F0) copies into every channel with mem_copy ($C285) - 35 bytes from
; $ED89 for a configured channel and from $EDAC for an unused one - holds
; $0003 at +$19: `xxd -s 0x6da2 -l 2 firmware/a2u12.bin` prints 00 03 and
; `xxd -s 0x6dc5 -l 2 firmware/a2u12.bin` prints the same. So a fresh channel
; is in degrees. init_channel_blocks runs from reinit_channel_tables ($C6C3),
; which power_on_init ($81AD) calls on its cold path at $8333 and
; enter_channel_config_mode ($528F) calls at $53FC (`lbsr $c6c3` after
; l53f7). A milliradian value is shown with three decimal places, as 6282
; paints '6.282' through format_with_decimal_point ($CD50) with the point at
; position 2 of five digits.
; CHAN_UNIT_DEG and CHAN_UNIT_RAD are in common/formats.inc: the bus's phase
; commit in remote.s stores them too, as the stock's set_phase_units_and_apply
; ($6E46) does before the value is checked.
CHAN_MILLI      equ     3               ; decimal places in a milliradian value

; --- the milliradian twin, and where this screen keeps it -----------------
; The stock's record holds the phase twice: record+$15 in tenths of a degree
; and record+$17 in thousandths of a radian, and commit_channel_phase ($66B2)
; writes both on every commit - its unit-3 arm ($66D0-$66F4) stores $221A at
; +$15 and scale_by_1p7453($221A) at +$17, its unit-4 arm ($6704-$6728)
; stores $221A at +$17 and scale_by_0p5730($221A) at +$15. The display paints
; the twin of the unit last used, so a phase typed as 1001 milliradians shows
; 1.001 rad although the chip is programmed from its 574 tenths - and 574
; tenths convert back to 1002, which is why the entry itself has to be kept.
;
; CHAN_RECORD is twelve bytes with no spare, so the twin and the unit live
; in scratch, one per channel, declared in scratch.inc at +$2B0-$2BD in the
; run before nav_stack (+$2D0), where test_scratch_layout.py checks them
; against every other declaration.
; chan_phase_unit, chan_phase_rad and chan_incr_rad are declared in
; modules/scratch.inc, where test_scratch_layout.py checks them.

; --- the six fields, in the order NEXT walks them --------------------------
CHAN_FIELD_CHAN equ     0
CHAN_FIELD_FREQ equ     1
CHAN_FIELD_AMPL equ     2
CHAN_FIELD_PHAS equ     3
CHAN_FIELD_WAVE equ     4
CHAN_FIELD_DEST equ     5
CHAN_FIELDS     equ     6

; --- THE UNITS CLASS OF EACH FIELD, which is the stock's $23AB -------------
; ON THE INSTRUMENT A NUMERIC FIELD IS COMMITTED BY ITS UNIT KEY, not by
; ENTER, and which key is accepted depends on the field. arm_numeric_entry_field
; ($AC35) stores a UNITS CLASS into $23AB at $AC46 when a field is armed, and
; two routines then read it and nothing else:
;
;   accept_units_key ($B0C1)      $B1FF indexes the table at $B212 with
;                                 $23AB - 2 and the arm compares the raw key
;                                 code, storing a unit code into $2221
;   check_entry_terminator ($B070) class 0 terminates on ANY legal character;
;                                 every other class returns 0, so only a unit
;                                 key ends the entry
;
; The six arms of $B212, read out:
;
;   class 2  $B0CD  ENTER only, no unit          Ch, Hop address, save/recall
;   class 3  $B0F3  ENTER = rad, deg = deg       PHASE
;   class 4  $B127  deg = uV, Hz = mV, kHz = V   AMPTD in volts
;   class 5  $B169  Hz = ms, kHz = s             On/Off times
;   class 6  $B19D  Hz = Hz, kHz = kHz           FREQ
;   class 7  $B1D1  deg = %                      AM depth
;
; ENTER IS NOT A TERMINATOR ON CLASSES 4, 5, 6 AND 7. It is not intercepted
; earlier either - $AE3D[26..29] are all keymap_unmapped_return0 - so it falls
; through numeric_entry_key_handler ($B3C2) to error_report_beep(2) at $B5D0.
; This screen used to commit every field on ENTER and refuse all three unit
; keys, which is the wrong result on every field for anyone who has used the
; instrument.
CHAN_CLASS_NONE equ     0               ; a choice field: no numeric entry
CHAN_CLASS_ENTER equ    2               ; ENTER alone, and no unit
CHAN_CLASS_PHASE equ    3               ; deg, and ENTER meaning rad
CHAN_CLASS_VOLTS equ    4               ; deg = uV, Hz = mV, kHz = V
CHAN_CLASS_FREQ equ     6               ; Hz and kHz
CHAN_CLASS_PCT  equ     7               ; deg, meaning per cent - an AM
                                        ; depth, $B1D1

; Indexed by CHAN_FIELD_*, in the order NEXT walks them.
chan_field_class
                fcb     CHAN_CLASS_ENTER        ; Ch
                fcb     CHAN_CLASS_FREQ         ; FREQ
                fcb     CHAN_CLASS_VOLTS        ; AMPL
                fcb     CHAN_CLASS_PHASE        ; PHASE
                fcb     CHAN_CLASS_NONE         ; WAVEFORM
                fcb     CHAN_CLASS_NONE         ; DESTN

; $B212 TRANSPOSED: three bytes per class, for deg, Hz and kHz in that order,
; CHAN_UNIT_NONE where that class's arm returns zero and the key beeps. Classes 5
; and 7 are carried because the tone, DTMF and digital screens use them and
; this table is the one place the mapping should live.
CHAN_CLASS_KEYS equ     3               ; deg, Hz, kHz
; The refusal sentinel. units.s declares CHAN_UNIT_NONE as $FF for unit_decades'
; own use, but that file is a different image and its equates are not visible
; here - only the UNIT_* codes themselves live in common/formats.inc, which is
; shared. Same value, named where it is used, and it is not a unit code: the
; codes run 0 to 15.
CHAN_UNIT_NONE  equ     $FF
chan_class_units
                fcb     CHAN_UNIT_NONE,CHAN_UNIT_NONE,CHAN_UNIT_NONE ; 0 choice
                fcb     CHAN_UNIT_NONE,CHAN_UNIT_NONE,CHAN_UNIT_NONE ; 1 unused
                fcb     CHAN_UNIT_NONE,CHAN_UNIT_NONE,CHAN_UNIT_NONE ; 2 ENTER only
                fcb     UNIT_DEG,CHAN_UNIT_NONE,CHAN_UNIT_NONE ; 3 $B0F3
                fcb     UNIT_MICROVOLT,UNIT_MILLIVOLT,UNIT_VOLT ; 4 $B127
                fcb     CHAN_UNIT_NONE,UNIT_MILLISEC,UNIT_SECOND ; 5 $B169
                fcb     CHAN_UNIT_NONE,UNIT_HZ,UNIT_KHZ ; 6 $B19D
                fcb     UNIT_PERCENT,CHAN_UNIT_NONE,CHAN_UNIT_NONE ; 7 $B1D1

; --- the sign of a dc level -----------------------------------------------
; THE CHANNEL SCREEN'S AMPTD FIELD IS SIGNED WHEN THE WAVEFORM IS dc, and
; only then. Executing the stock in the emulator: with WFORM set to dc (key
; 6 on that field) the field paints as 'AMPTD +  140 V', the '+' at DDRAM
; $1E; MINUS then paints 'AMPTD -' there, '1' and the V terminator store
; 1,000,000 at record+10 with $2D at record+$14, and the field reads
; 'AMPTD -1.000  V'. On a Sine channel the same keys leave the record alone
; and MINUS paints nothing.
;
; The two characters are the stock's own: the default record at $ED89
; carries $2B at +$14 (`xxd -s 0x6d9d -l 1 firmware/a2u12.bin` prints 2b),
; apply_amplitude_entry ($6547) stores $241E there at $6613, and
; scale_to_dds_code tests it against $2D at $D4E7. In this firmware the byte
; is ampl_signs[channel], written by ampl_set_signed, and the sign of an
; entry in progress is chan_entry_sign.
;
; CHAN_SIGN_PLUS and CHAN_SIGN_MINUS were defined here, and are in
; hp8904a-rewrite/common/formats.inc now. That was right while page 0 was the
; only image that named them; hop_table_defaults primes sixteen of these
; bytes and moved to the always-mapped image with the rest of
; dds_table_defaults ($E7F9), so a second image names them.

; ---------------------------------------------------------------------------
; channel_config_open - paint the screen and start editing
;
;   entry: U = the entry reason: MODE_COLD, MODE_RECALL or MODE_KEEP
;   exit:  the screen shows the current channel; the first field is selected
;   uses:  A, B, X, Y, U
;
; Reached from A2U12 through this page's entry vector at $4001, and from the
; channel summary's ENTER.
;
; The channel it opens on is whichever was last selected, not always channel
; 1. An operator adjusting channel 3 leaves for the Output On/Off screen and
; comes back; returning them to channel 1 would make them navigate back every
; time. The commonest way to set the wrong channel is to be on a different
; one from the one you think you are on, which is what the Ch field - shown
; first and always - is there to prevent.
; ---------------------------------------------------------------------------
channel_config_open
                ; THE CHAIN'S LENGTH, FROM THE OPTIONS AS THEY ARE NOW. The
                ; stock tests installed_options at every entry, $5496 ANDB #$02
                ; then $54A5 ANDB #$01, and on a two-channel instrument with the
                ; byte cleared by ST_ID its NEXT goes title, ch A, ch B, title -
                ; driven on the emulator 2026-09-15 - where this walked all
                ; seven records (seed 15, block 24).
                lda     #CHAN_CHAIN_LEN-1       ; Option 003: menu_records_
                ldb     >installed_options      ; 433e's own count
                bitb    #$02
                bne     channel_config_last
                lda     #4                      ; Option 001 alone: the four
                bitb    #$01                    ; channel records ($54BA)
                bne     channel_config_last
                lda     >installed_channels     ; neither: $23B2 ($54AF)
channel_config_last
                sta     >chan_chain_last
                ; WHAT HAPPENS TO THE RECORDS DEPENDS ON WHY THE MODE IS
                ; ENTERED, and the reason arrives in U (MODE_COLD in
                ; scratch.inc). $528F tests its argument three times: unless
                ; it is 2, instrument_preset ($52A6-$52AD); if it is 1, the
                ; slot is copied in ($52B2-$52F2); unless it is 0, $C5B1 with
                ; the hop enables and, on 1 alone, the four output latches -
                ; where 0 runs reinit_channel_tables ($C6C3) instead. Anything
                ; that is not a recall or a keep-state entry is taken as cold,
                ; so a caller that loads nothing cannot skip the defaults.
                cmpu    #MODE_RECALL
                lbeq    channel_config_recall
                cmpu    #MODE_KEEP
                lbeq    channel_config_keep
                ; THE RECORDS GO BACK TO THEIR DEFAULTS FIRST, and that is
                ; not a judgement about what would be tidy - it is what the
                ; instrument does, driven on 2026-09-13.
                ;
                ; enter_channel_config_mode ($528F) calls reinit_channel_
                ; tables ($C6C3) at $53FC, and $C6C3 calls dds_table_defaults
                ; ($E7F9), init_channel_blocks ($C4F0) and reapply_all_
                ; channels ($C5B1) in turn, before the destination restore at
                ; $5404-$543D. $C4F0 rebuilds the four records from their
                ; power-on defaults and $C5B1 puts them on the hardware with
                ; every destination parked, which is channel_reapply_all here.
                ;
                ; Driven, keying 5 kHz into ch A's FREQ and 200 uV into its
                ; AMPTD, leaving by f4 Exit and coming straight back:
                ;
                ;   stock  after keying   FREQ   5.000  kHz  AMPTD    200 uV
                ;          after re-entry FREQ   1000.0  Hz  AMPTD    140 uV
                ;   this   after keying   the same as the stock
                ;          after re-entry the 5 kHz still standing, AMPTD 0
                ;
                ; So the instrument DISCARDS the channel settings when the
                ; operator walks back into the mode, and this firmware kept
                ; them and then showed a level of nothing - because
                ; channel_mode_exit has parked the destinations on the way
                ; out, which zeroes each record's level as the stock's $7A45
                ; does, and nothing put a level back. Keeping them looked
                ; kinder and was a different instrument.
                ; THE INSTRUMENT QUIESCES FIRST, and this entry was the
                ; only one in the firmware that did not. $528F opens with
                ; CMPX #$0002 / LBEQ l52b2 / LBSR $c6ea at $52A6-$52AD: unless
                ; the argument is 2 - the keep-state re-entry - it runs
                ; instrument_preset ($C6EA) BEFORE anything else. The three
                ; sequence-mode entries here already do it, each commented
                ; "QUIESCE FIRST, as the stock" (page1_dtmf.s, page1_tone.s,
                ; page2_digital.s); Channel Configuration did not, so it
                ; opened over whatever the timers and the chip's parameter
                ; block were left holding.
                lbsr    ABI_instrument_preset   ; $C6EA at $52AD

                lbsr    ABI_hop_table_defaults          ; $E7F9, first of $C6C3's
                                                        ; three, and in A2U12 as
                                                        ; $E7F9 is - the cold boot
                                                        ; runs it too and cannot
                                                        ; call into a page
                lbsr    ABI_channel_records_init        ; $C4F0

                ; AND EVERY DESTINATION OFF BETWEEN THE TWO, which is not an
                ; extra step - it is the FIRST OF reapply_all_channels'
                ; ($C5B1) OWN TWO PASSES, and this was the one entry in the
                ; firmware that skipped it.
                ;
                ; $C5B1 is two loops over the four records of $24F5. The first,
                ; $C5BB-$C5FB, copies each record's +$21 into $24DE+2i and
                ; writes $0010 - Off - over it; only then does the second,
                ; $C61E-$C697, program write_channel_reg_08, unit_code_select_
                ; head, set_channel_phase and dispatch_channel_function ($C069)
                ; for each channel. So the instrument's apply ALWAYS sees four
                ; parked channels, and $C069 takes channel_apply_and_propagate's
                ; ($BE5C) Off branch at $BE82/$BE85 - a zero level register and
                ; a return at $C065, before any socket's range latch. The
                ; restore below is what puts a real level on the hardware.
                ;
                ; This firmware splits that single routine in two, because
                ; record+$21 is two cells here - CHAN_DEST in the record and
                ; routed_dest beside it - and channel_park_destinations is the
                ; $C5BB-$C5FB pass, chan_dest_parked its $24DE. The three
                ; sequence-mode entries already run it between the record reset
                ; and the apply (page1_dtmf.s, page1_tone.s, page2_digital.s);
                ; channel_config_open ran the apply straight after the reset,
                ; so its apply saw whatever the mode before it had routed.
                ;
                ; THE FAULT THAT FOUND IT: after a DTMF Sequence block, channel
                ; C stayed silent. Driven on 2026-09-13, both firmwares through
                ; their own pagers - DTMF Sequence, back to the Main Selection
                ; Level, then Channel Config. - reading record+$21 on the stock
                ; and routed_dest here, and the level register code the model
                ; latched for each channel:
                ;
                ;   at the DTMF exit  both firmwares  0C 10 0C 10
                ;   Channel Config.   stock    levels 1879 1879 1879 1879
                ;                     this     levels 1879 1879    0 1879
                ;
                ; Channels A and C both hold Out1 ($0C) leaving the sequence -
                ; the stock does too, so that state is right - and the apply
                ; then found two channels on one socket. With the park in, the
                ; apply finds four Off, as $C5B1 guarantees, and channel C reads
                ; 1879 like the other three. Digital Sequence, which leaves only
                ; one channel routed, was already right and stays right.
                lbsr    ABI_channel_park_destinations   ; $C5B1 pass 1,
                                                        ; $C5BB-$C5FB
                lbsr    ABI_channel_reapply_all         ; $C5B1 pass 2,
                                                        ; $C61E-$C697, relay-free

                ; THE PARKED DESTINATIONS COME BACK HERE, which is where the
                ; instrument puts them back: enter_channel_config_mode
                ; ($528F) calls set_channel_destination per channel at
                ; $5404-$543D, from the $24DE the pass above has just filled.
                ; Assigning a destination is what makes the level real, so this
                ; is the moment a cold instrument starts producing.
                lbsr    ABI_channel_restore_destinations

                ; NO ENTRY IS IN PROGRESS when a screen opens. That is
                ; screen_install's job now, for every screen rather than for
                ; this one - see the note there. It was cleared here and
                ; nowhere else, which left the same defect on every other
                ; screen in the tree.
                ldx     #chan_key
                lbsr    ABI_screen_install
                clr     >chan_chain             ; THE CHAIN OPENS ON ITS TITLE,
                                                ; as menu_show ($8A08) opens
                                                ; every menu with $268E cleared
                clr     >active_record          ; - and $268E is the saved
                                                ; record too
channel_config_fields
                lbsr    chan_incr_end              ; AND NO INCREMENT IS ARMED.
                                                ; ui_message_dispatch ($8D60)
                                                ; stores $003C in $2217 when
                                                ; bit 3 of event_flags2
                                                ; ($2202) is set and the hook
                                                ; at $220D returns non-zero,
                                                ; and dispatch_ui_event
                                                ; ($5D0C) sends $3C (CMPX
                                                ; #$003C / LBEQ) to l5d22
                                                ; ($5D22): CLRB / CLRA / STD
                                                ; >$2215, then end_field_edit
                                                ; ($5CE8). incr_mode was
                                                ; cleared nowhere on a screen
                                                ; change, so this screen could
                                                ; reopen showing an increment
                                                ; and the next ENTER would
                                                ; have gone into it
                clr     >field_index            ; the Ch field, so the screen
                                                ; opens saying which channel
                                                ; it is about to change
                clr     >field_is_hop           ; and field_index is the live
                                                ; field id again, as $2215 is
                lbra    chan_chain_select

; A REGISTER RECALLED INTO THE MODE. register_restore has run the teardown,
; instrument_preset and the copy - $F1B1, then $528F's own $52A6-$52F2 - so
; the records are the saved ones and what is left is the apply: $C5B1, the
; hop enables and the four output latches from the saved latch bytes. That is
; register_apply, which was the whole of a recall before this port and whose
; routing words emulator/tests/test_bus_registers_new.py checks against the
; stock's.
channel_config_recall
                lbsr    ABI_register_apply
                bra     channel_config_saved

; A KEEP-STATE POWER-ON. No preset and no copy: boot_keep_state has run
; instrument_preset and register_apply over the records battery RAM kept.
; $528F then runs $C5B1 - its park pass and its apply pass - and the
; destination restore every reason reaches at $5404-$543D.
channel_config_keep
                lbsr    ABI_channel_park_destinations   ; $C5B1 pass 1
                lbsr    ABI_channel_reapply_all         ; $C5B1 pass 2
                lbsr    ABI_channel_restore_destinations

; AND THE RECORD THE MODE WAS ON. On any reason but 0, $528F puts $268E back
; through menu_page_show ($89AA) unless it is past $2242, the last record
; (CMPB >$2242 / LBHI l5479); past it, the chain opens on its title, as a cold
; entry does. Measured on the stock 2026-09-16: a register saved on ch B
; recalls onto ch B.
channel_config_saved
                ldx     #chan_key
                lbsr    ABI_screen_install
                lda     >active_record
                cmpa    >chan_chain_last
                bls     channel_config_saved_on
                clra                            ; past the last: the title
channel_config_saved_on
                sta     >chan_chain
                sta     >active_record
                lbra    channel_config_fields

; ---------------------------------------------------------------------------
; chan_chain_select - a record SELECTED, not repainted, then shown
;
;   uses:  A, B, X, Y, U
;
; select_menu_page ($514D) is what NEXT, LAST, the mode's entry and going
; local reach, and its record arms set the channel the panel acts on as well
; as the one on the glass: select_channel_a ($5161) CLR >$23BE, and B, C, D
; store 1, 2, 3; menu_page_hop_ram and select_mode_menu_page CLR it; the
; title arm leaves it. A repaint - KEY_REFRESH after a bus command, the hop
; screen redrawing itself - does not, which is what lets a bus select that
; named another channel stand.
; ---------------------------------------------------------------------------
chan_chain_select
                lda     >chan_chain
                beq     chan_chain_select_show  ; the title: $23BE untouched
                cmpa    #CHAN_CHAIN_HOP
                blo     chan_chain_select_chan
                clr     >current_channel        ; a hop record: CLR >$23BE
                bra     chan_chain_select_show
chan_chain_select_chan
                deca
                sta     >current_channel        ; ch A-D: 0 to 3
chan_chain_select_show
                lbra    chan_chain_show

; ---------------------------------------------------------------------------
; chan_on_glass - is the channel the panel acts on the one being shown?
;
;   exit:  Z set if it is; every register kept
;
; The guard every stock channel painter opens with: LDB >$23BE / CMPB >$3B81,
; and nothing is drawn when they differ.
; ---------------------------------------------------------------------------
chan_on_glass
                pshs    a
                lda     >current_channel
                cmpa    >shown_channel
                puls    a                       ; PULS leaves the flags
                rts

; ---------------------------------------------------------------------------
; chan_marker_draw - put the increment marker at one column
;
;   entry: A = the DDRAM address
;   uses:  nothing - every register kept
;
; set_field_marker_at_column ($C855): glyph $07 written at the column, which
; is remembered ($2412) and flagged ($2413) for clear_field_marker.
; ---------------------------------------------------------------------------
chan_marker_draw
                pshs    a,b,x,y,u
                sta     >chan_marker_col
                ldx     #chan_marker_glyph
                ldb     #1
                lbsr    ABI_lcd_write
                puls    a,b,x,y,u
                rts
chan_marker_glyph
                fcb     $07
chan_marker_space
                fcc     " "

; ---------------------------------------------------------------------------
; chan_incr_end - an armed increment let go, and its marker taken down
;
;   exit:  incr_mode clear, and the flags as its CLR leaves them
;   uses:  nothing else - every register kept
;
; end_field_edit ($5CE8) with $3B84 set: clear_field_marker ($C885) writes a
; space back at the marker's column if one is up ($C88E TST >$2413), and the
; flag goes. The repaint it then calls through $3B82 is guarded like every
; painter, and each caller here repaints or not exactly as it did.
; ---------------------------------------------------------------------------
chan_incr_end
                pshs    a,b,x,y,u
                lda     >chan_marker_col
                beq     chan_incr_end_flag
                clr     >chan_marker_col
                ldx     #chan_marker_space
                ldb     #1
                lbsr    ABI_lcd_write
chan_incr_end_flag
                puls    a,b,x,y,u
                clr     >incr_mode
                rts

; ---------------------------------------------------------------------------
; chan_chain_show - whichever record of the chain is standing
;
;   uses:  A, B, X, Y, U
;
; THE CHANNEL CONFIGURATION CHAIN IS ONE MENU OF SEVEN RECORDS, and NEXT and
; LAST walk it: the title, the four channel screens, the Hop Ram fields and the
; hop On/Off page. menu_records_433e ($433E) holds them - record 0 is
; menu_text_page0_config ($41FD), records 1 to 4 are all
; channel_config_screen_text ($424D), record 5 is via429d ($429D) and record 6
; via42ed ($42ED) - and menu_page_show ($89AA) indexes it with $268E, which
; menu_item_next ($8A5B) steps against the count byte before the table.
;
; Driven on the stock, 2026-09-10: f1 on Channel Config. gives the title, and
; NEXT walks ch A, ch B, ch C, ch D, the Hop Ram fields and the On/Off page
; before coming round again. This firmware had the four channel screens on one
; entry of its own Main Selection with NEXT and LAST moving the FIELD cursor
; inside them, and the two hop records on a separate entry - so the chain the
; instrument walks did not exist.
; ---------------------------------------------------------------------------
chan_chain_show
                lda     >chan_chain
                beq     chan_chain_title
                cmpa    #CHAN_CHAIN_HOP
                blo     chan_chain_channel
                ldb     #5                      ; menu_page_hop_ram: nor does
                stb     >shown_channel          ; a hop record's $3B81
                suba    #CHAN_CHAIN_HOP         ; 5 and 6 are the hop screens'
                sta     >hop_page               ; two records
                ldb     >hop_index
                lbra    hop_show
chan_chain_title
                lda     #4                      ; select_menu_page_none: $3B81
                sta     >shown_channel          ; names no channel
                lda     #LCD_LINE1
                ldx     #chan_title_l1
                ldb     #LCD_COLUMNS
                lbsr    ABI_lcd_write
                lda     #LCD_LINE2
                ldx     #chan_title_l2
                ldb     #LCD_COLUMNS
                lbra    ABI_lcd_write
chan_chain_channel
                deca                            ; records 1 to 4 are channels
                sta     >shown_channel          ; 0 to 3, the stock's $3B81
                cmpa    >current_channel        ; A REPAINT WHILE THE PANEL
                bne     chan_chain_kept         ; ACTS ON ANOTHER CHANNEL DRAWS
                lbsr    chan_screen_paint       ; NOTHING. A record select sets
                lbra    chan_cursor_show        ; both first (chan_chain_select),
chan_chain_kept                                 ; so this is the refresh after a
                rts                             ; bus command: 'DAPL 10 UV;' on
                                                ; ch C commits channel B and the
                                                ; instrument's glass keeps ch C's
                                                ; values - its painters are all
                                                ; guarded - where this repainted
                                                ; the blank template and then
                                                ; skipped every value (seed 6)


; ---------------------------------------------------------------------------
; chan_screen_paint - draw both template lines and every current value
;
;   uses:  A, B, X, Y, U
;
; The templates go down first and the values over them, rather than building
; an eighty-byte image in RAM and writing that. The display is written twice
; where the two overlap, which costs a few hundred microseconds and saves
; eighty bytes of RAM and the whole class of fault where the image in memory
; and the characters on the glass disagree.
; ---------------------------------------------------------------------------
chan_screen_paint
                lda     #LCD_LINE1
                ldx     #chan_screen_line1
                ldb     #LCD_COLUMNS
                lbsr    ABI_lcd_write
                lda     #LCD_LINE2
                ldx     #chan_screen_line2
                ldb     #LCD_COLUMNS
                lbsr    ABI_lcd_write
                ; fall through and fill every field in

; ---------------------------------------------------------------------------
; chan_values_show - write all six current values into their fields
;
;   uses:  A, B, X, Y, U
; ---------------------------------------------------------------------------
chan_values_show
                lbsr    chan_show_channel
                lbsr    chan_show_freq
                lbsr    chan_show_ampl
                lbsr    chan_show_phase
                lbsr    chan_show_wave
                lbsr    chan_show_dest
                ; AND THE CURSOR BACK ON THE SELECTED FIELD. Every tail on the
                ; stock's screen - a field select ($5ECA), INCR SET ($61E3), a
                ; commit ($6C11) and a step ($7240, $735F) - ends by re-arming
                ; the entry through [$3B85], and arm_numeric_entry_field
                ; ($AC35) puts the LCD cursor on the field's digit column
                ; ($AC8C-$AC98 lcd_set_cursor of $23AD). destn_show ends in
                ; lcd_write, so the blinking cursor entry_begin turns on was
                ; left after the DEST text by every repaint that came here.
                lbra    chan_cursor_show

; ---------------------------------------------------------------------------
; chan_record - the record of the channel being edited
;
;   exit:  X = the record, B = the channel number
;   uses:  A, B, X
;
; One routine, because every field needs it and computing it in six places is
; six chances to multiply by the wrong record size.
; ---------------------------------------------------------------------------
chan_record
                ldb     >current_channel
                andb    #$03                    ; a wild channel must not
                pshs    b                       ; index outside the four
                lda     #CHAN_RECORD            ; records
                mul                             ; D = channel * 12
                ldx     #channel_records
                leax    d,x
                puls    b
                rts

; ---------------------------------------------------------------------------
; chan_incr_ampl_addr - this channel's amplitude step
;
;   exit:  X = its three bytes
;   uses:  A, B, X
;
; The stock reaches it as [$23BF]+15, the record it is already holding. This
; firmware keeps the twelve bytes outside the record, so the channel has to be
; multiplied in - here, once, rather than at each of the three call sites.
; ---------------------------------------------------------------------------
chan_incr_ampl_addr
                ldb     >current_channel
                andb    #$03                    ; a wild channel must not index
                lda     #3                      ; outside the four
                mul
                ldx     #incr_ampl_ch
                leax    d,x
                rts

; ---------------------------------------------------------------------------
; chan_incr_freq_addr - this channel's frequency step
; chan_incr_freq_unit - and the unit that step is shown in
;
;   chan_incr_freq_addr exit: X = its three bytes
;   chan_incr_freq_unit exit: B = UNIT_HZ or UNIT_KHZ
;   uses:  A, B, X
;
; The stock's [$23BF]+5 and +8, one of each per record, as incr_ampl_ch is
; +15 - see incr_freq_ch in scratch.inc. The unit is folded to the two codes
; the frequency layouts know, as chan_freq_unit_get folds the value's.
; ---------------------------------------------------------------------------
chan_incr_freq_addr
                ldb     >current_channel
                andb    #$03
                lda     #3
                mul
                ldx     #incr_freq_ch
                leax    d,x
                rts
chan_incr_freq_unit
                ldx     #incr_freq_unit
                ldb     >current_channel
                andb    #$03
                abx
                ldb     ,x
                cmpb    #UNIT_KHZ
                beq     chan_incr_freq_unit_done
                ldb     #UNIT_HZ
chan_incr_freq_unit_done
                rts

; ---------------------------------------------------------------------------
; chan_show_channel - the channel digit
;
;   uses:  A, B, X
;
; Shown as 1 to 4, because that is what is printed beside the sockets. The
; records are indexed 0 to 3 and the conversion happens here, at the one
; place where a human reads the number.
; ---------------------------------------------------------------------------
chan_show_channel
                ldb     >shown_channel          ; A LETTER, not a number. The
                andb    #$03                    ; stock's screen reads 'ch A:'
                addb    #'A'                    ; and its four letters are the
                stb     >chan_text              ; bytes at $5CCE-$5CD4
                lda     #CHAN_F_CHAN
                ldx     #chan_text
                ldb     #CHAN_W_CHAN
                lbra    ABI_lcd_write

; ---------------------------------------------------------------------------
; chan_show_freq - the frequency and its unit
;
;   uses:  A, B, X, Y, U
;
; The stored value is in units of 0.1 Hz, so the decimal point goes one digit
; from the right and the unit is always Hz. There is no autoranging to kHz:
; a field that changes its own units while an operator reads it is a field
; that gets misread, and eight digits hold 600000.0 without needing to.
; ---------------------------------------------------------------------------
CHAN_TENTHS     equ     1               ; decimal places in a 0.1 unit value

chan_show_freq
                lbsr    chan_on_glass           ; LDB >$23BE / CMPB >$3B81
                lbne    chan_show_off_glass     ; first, as the stock's does
                ldb     >current_channel        ; CHANNEL 0 WHILE FREQ HOP IS
                andb    #$03                    ; ON SHOWS '*Hop Ram*', as
                bne     chan_show_freq_own      ; draw_channel_frequency
                tst     >hop_running            ; ($54E6) paints d4384 at
                beq     chan_show_freq_own      ; l5543 for $23BE = 0 with bit
                lda     #CHAN_F_FREQ            ; 8 of $2202 set, before its
                ldb     #CHAN_HOP_W_FREQ        ; waveform and value cases
                lbra    chan_show_hop_marker
chan_show_freq_own
                lbsr    chan_record
                leau    ,x                      ; CHAN_FREQ is zero; written
                                                ; ",x" because the two
                                                ; assemblers encode a zero
                                                ; offset differently and both
                                                ; are right. See
                                                ; tests/test_zero_offset.py.
                lda     #CHAN_FIELD_FREQ        ; INCR SET ARMED ON THIS FIELD:
                lbsr    chan_incr_shown         ; the field shows the INCREMENT.
                bcc     chan_show_freq_no_incr  ; The stock's
                                                ; show_freq_increment_field
                                                ; ($5A1B), called at $61BA by
                                                ; begin_freq_increment_entry
                                                ; ($61B5) once $2215 is 6,
                                                ; converts record+5 - LDX 2,s
                                                ; / LEAX 5,X at l5a48 ($5A48),
                                                ; the word
                                                ; step_channel_frequency
                                                ; ($71DD) adds to record+0 -
                                                ; and writes eight digits at
                                                ; DDRAM $0B through $D8EA
                                                ; after l5ad2 ($5AD2): the
                                                ; columns
                                                ; draw_channel_frequency
                                                ; ($54E6) paints the value in
                lda     #CHAN_M_FREQ            ; show_freq_increment_field
                lbsr    chan_marker_draw        ; marks column $0A first
                lbsr    chan_incr_freq_addr     ; this channel's step, [$23BF]+5
                leau    ,x
                lbsr    chan_incr_freq_unit     ; IN ITS OWN UNIT, +8 - not the
                                                ; value's +3: $5A1B tests +8
                bra     chan_show_freq_value

chan_show_freq_no_incr
                ; dc AND Noise SHOW NO FREQUENCY AT ALL, and this painted one.
                ; draw_channel_frequency ($54E6) blanks the field first (l550e
                ; $550E: 12 characters of the space string $ED11 at DDRAM $0B),
                ; and at l555d ($555D) it reads the waveform word at record+$1F
                ; twice - CMPX #$0004 / LBEQ l557c, CMPX #$0005 / LBEQ l557c -
                ; and for dc (4) or Noise (5) goes to l557c ($557C), which
                ; writes the same twelve blanks again and returns at l564b: no
                ; digits and no unit label. Only the l5596 path renders a
                ; number. Twelve columns is $0B..$16, which is CHAN_F_FREQ
                ; through the last column of the unit label at CHAN_U_FREQ -
                ; CHAN_HOP_W_FREQ, the width the '*Hop Ram*' marker covers for
                ; the same reason.
                ;
                ; MEASURED on 2026-09-13, both firmwares side by side after
                ; 'WFA DC;': the stock's line reads 'ch A: FREQ
                ; AMPTD +  140 V ' and this firmware's still read 'ch A: FREQ
                ; 1000.0  Hz AMPTD   +140 V '. A dc channel has no frequency to
                ; produce, so a number standing in that field is a reading of
                ; something the instrument is not doing.
                ;
                ; THE INCREMENT IS EXEMPT, which is why the test sits after the
                ; INCR SET branch and not before it:
                ; show_freq_increment_field ($5A1B) goes from its
                ; displayed-channel test straight to l5a48 ($5A48) and the
                ; render - it has no waveform test at all - so INCR SET on the
                ; FREQ field of a dc channel still shows the step.
                lda     CHAN_WAVE,x             ; X is still the record:
                cmpa    #LBL_DC                 ; chan_incr_shown uses A only
                beq     chan_show_freq_blank
                cmpa    #LBL_NOISE
                beq     chan_show_freq_blank
                lbsr    chan_freq_unit_get      ; B = the VALUE's unit, +3
                bra     chan_show_freq_value
chan_show_freq_blank
                lda     #CHAN_F_FREQ            ; $557C: the whole field and
                ldb     #CHAN_HOP_W_FREQ        ; its unit label, blanked
                lbra    ABI_lcd_blank
chan_show_freq_value
                ; THE STOCK'S OWN LAYOUT. draw_channel_frequency ($54E6) turns
                ; the 24-bit value into eight digits, blanks leading zeros up
                ; to a limit, drops the point in and writes EIGHT of the nine
                ; characters that makes - from $2415, so character zero is
                ; discarded - at DDRAM $0B, then the unit label at $14.
                ;
                ; U = the value, B = the unit to lay it out in. The caller
                ; chooses, because the instrument keeps two: the value's at
                ; +3, which draw_channel_frequency reads, and the increment's
                ; at +8, which show_freq_increment_field reads.
                pshs    b
                tfr     u,x
                lbsr    ABI_uint24_to_text      ; text_buffer, eight digits
                ldb     ,s                      ; the unit
                cmpb    #UNIT_HZ
                bne     chan_show_freq_khz

                ldx     #text_buffer            ; ' Hz': six leading zeros may
                ldb     #CHAN_FREQ_BLANK_HZ     ; go and the point falls after
                lbsr    chan_blank_limit        ; seven digits
                ldu     #text_buffer
                ldx     #chan_text
                lda     #TEXT_DIGITS
                ldb     #CHAN_FREQ_DP_HZ
                lbsr    chan_point
                bra     chan_show_freq_put
chan_show_freq_khz
                ldx     #text_buffer            ; 'kHz': three, the point
                ldb     #CHAN_FREQ_BLANK_KHZ    ; after four, and the last
                lbsr    chan_blank_limit        ; character blanked if it is
                ldu     #text_buffer            ; a zero - $55FB's flag
                ldx     #chan_text
                lda     #TEXT_DIGITS
                ldb     #CHAN_FREQ_DP_KHZ
                lbsr    chan_point
                lda     >chan_text+TEXT_DIGITS
                cmpa    #'0'
                bne     chan_show_freq_put
                lda     #' '
                sta     >chan_text+TEXT_DIGITS
chan_show_freq_put
                lda     #CHAN_F_FREQ
                ldx     #chan_text+1
                ldb     #CHAN_W_FREQ
                lbsr    ABI_lcd_write

                puls    b                       ; and its label, three columns
                lbsr    ABI_unit_label          ; wide with a leading space,
                lda     #CHAN_U_FREQ            ; which is how ' Hz' and 'kHz'
                ldb     #UNIT_LABEL_LEN         ; both end in column 22
                lbra    ABI_lcd_write

; ---------------------------------------------------------------------------
; chan_freq_unit_get - the unit this channel's frequency is shown in
;
;   exit:  B = UNIT_HZ or UNIT_KHZ
;   uses:  A, B, X
;
; A channel that has never had a frequency keyed into it shows Hz, which is
; what the stock's default record holds: init_channel_blocks ($C4F0) copies
; 35 bytes from $ED89 into every channel and the word at +3 is $0002.
; ---------------------------------------------------------------------------
chan_freq_unit_get
                ldx     #chan_freq_unit
                ldb     >current_channel
                andb    #$03
                abx
                ldb     ,x
                cmpb    #UNIT_KHZ
                beq     chan_freq_unit_done
                ldb     #UNIT_HZ
chan_freq_unit_done
                rts

; ---------------------------------------------------------------------------
; chan_show_hop_marker - '*Hop Ram*' over a field and its unit
;
;   entry: A = the field's DDRAM position, B = the columns to cover
;   uses:  A, B, X
; ---------------------------------------------------------------------------
chan_show_hop_marker
                ldx     #chan_hop_marker
                lbra    ABI_lcd_write
chan_show_off_glass                             ; another channel's field:
                rts                             ; nothing is drawn

; ---------------------------------------------------------------------------
; chan_show_ampl - the amplitude and its unit
;
;   uses:  A, B, X, Y, U
;
; Stored in microvolts and shown in volts, with six decimal places - so a
; microvolt reads as 0.000001 and nothing is lost.
;
; This used to say the field is "seven characters wide, so the last two
; decimal places fall off the end - which truncates rather than rounds, on
; purpose". The field is CHAN_W_AMPL, which is CHAN_NUMERIC, which is
; TEXT_DIGITS+1 = nine; format_places writes eight digits and a point, which is
; nine. Nothing falls off and nothing is truncated. The sentence described a
; narrower field than the one the code asks for, and a reader sizing a new
; field against it would have got it wrong by two. A displayed amplitude that read HIGHER than the value actually set
; would have an operator believe the output is larger than it is, and for a
; level that is the dangerous direction to be wrong in.
; ---------------------------------------------------------------------------

chan_show_ampl
                lbsr    chan_on_glass           ; LDB >$23BE / CMPB >$3B81
                lbne    chan_show_off_glass     ; first, as the stock's does
                ldb     >current_channel        ; CHANNEL 0 WHILE AMPTD HOP IS
                andb    #$03                    ; ON SHOWS '*Hop Ram*', as
                bne     chan_show_ampl_own      ; paint_channel_amptd ($57B1)
                lda     >mode_flags             ; paints d4384 at l57fe for
                bita    #MODE_FLAG_AM           ; $23BE = 0 with bit 6 of
                beq     chan_show_ampl_own      ; $2203 set, before its value
                lda     #CHAN_F_AMPL            ; case
                ldb     #CHAN_HOP_W_AMPL
                lbra    chan_show_hop_marker
chan_show_ampl_own
                lbsr    chan_record

                ; THE AMPTD FIELD IS NOT ALWAYS A VOLTAGE, and this drew it as
                ; one whatever the channel was doing. A channel set to AM
                ; carries a modulation depth in tenths of a percent, so a
                ; stored 500 - which amplitude.s itself calls 50.0% - came out
                ; as "0.000500" under a fixed "V".
                ;
                ; The whole of that - the unit for the destination, the
                ; decimal places, the autoranging for a level, the
                ; right-alignment and the label - is ampl_text in
                ; modules/amplitude.s, reached through the ABI because this
                ; screen is on page 0 and that is in A2U12. It used to be
                ; written out here, and the tone sequence screen on page 1
                ; shows the same field: two copies in two images is how they
                ; would come to disagree about what a stored 500 means.
                lda     #CHAN_FIELD_AMPL        ; INCR SET ARMED ON THIS FIELD:
                lbsr    chan_incr_shown         ; the field shows the INCREMENT
                bcc     chan_show_ampl_value    ; - chan_ampl_incr_text names
                lda     #CHAN_M_AMPL            ; draw_amplitude_increment
                lbsr    chan_marker_draw        ; ($5B13) marks column $1D
                lbsr    chan_ampl_incr_text     ; the stock instructions - and
                bra     chan_show_ampl_write    ; no sign, which is $567F's
                                                ; LDX >$2215 / CMPX #$0007
chan_show_ampl_value
                lbsr    ABI_ampl_text           ; chan_text = value, then the
                                                ; unit at +AMPL_TEXT_W
chan_show_ampl_write
                ; FIVE COLUMNS, and they are the FIRST five of the formatter's
                ; answer, not the last. write_unit_label_and_digits ($576C)
                ; writes `LDB #$05` from the buffer's START ($579B), and every
                ; arm hands it six characters - autorange_digits_v_mv_uv
                ; ($D022) makes '1.0000' for one volt and the stock shows
                ; '1.000'. Taking the last five showed '.0000': the leading
                ; digit fell off the front of a field that carries five
                ; significant figures. Driven on the stock: one volt reads
                ; 'AMPTD  1.000  V ', ten volts '10.00' and 2.5 volts ' 2.50'.
                ;
                ; ampl_text right-aligns its result in AMPL_TEXT_W, so the
                ; result's first character sits AMPL_TEXT_W less its own
                ; length in - six for every arm.
                ; THE FIELD IS BLANKED FIRST, which the instrument does and
                ; this did not. paint_channel_amptd ($57B1) writes NINE blanks
                ; at LCD $1F before anything else - the captured stream is
                ; CMD $9F, nine spaces, then the unit and the digits - where
                ; this wrote five cells at the same column and blanked
                ; nothing, so $24 to $27 of that field kept whatever the last
                ; paint left in them.
                ;
                ; On the bench, 2026-09-20, that field reads three f-hooks and
                ; no unit on both panels with this firmware and correctly with
                ; the original on the same two panels, so the display is not
                ; the cause. The model shows no difference at all - same
                ; DDRAM, same shadow, same CGRAM, no write dropped while the
                ; controller was busy - which is why this is ported as what
                ; the instrument does rather than as a fix for a fault the
                ; model can show.
                lda     #CHAN_F_AMPL
                ldb     #CHAN_AMPL_FIELD_W      ; the stock's nine
                lbsr    ABI_lcd_blank

                ldx     #chan_text              ; where the answer STARTS:
                lda     #AMPL_TEXT_W            ; ampl_text right-aligned it
                suba    >chan_ampl_len          ; and chan_ampl_len is how
                leax    a,x                     ; long it is
                lda     #CHAN_F_AMPL
                ldb     #CHAN_W_AMPL
                lbsr    ABI_lcd_write

                ; AND A dc LEVEL'S SIGN, ON THE GLASS. It used to be written
                ; into chan_text one cell left of the first non-blank there -
                ; and ampl_text right-aligns into nine while this field writes
                ; five, so the cell the sign went into was three columns in
                ; front of the first column written and never reached the
                ; display. A level stored NEGATIVE read positive, which is the
                ; dangerous direction for a level to be wrong in.
                ;
                ; level_sign_right_justify ($4569) writes it one column left of
                ; the first non-blank ON THE DISPLAY and writes nothing when
                ; that character is '0'; chan_ampl_sign_place is that, over the
                ; five characters this field actually wrote.
                lbsr    chan_ampl_sign_place

                ldb     >chan_ampl_unit         ; and the label, three columns
                lbsr    ABI_unit_label          ; at $25, which is where $576C
                lda     #CHAN_U_AMPL            ; puts it
                ldb     #UNIT_LABEL_LEN
                lbra    ABI_lcd_write

; ---------------------------------------------------------------------------
; chan_ampl_incr_text - the AMPL increment as characters, in the level's
;                       layout
;
;   exit:  chan_text holds incr_ampl rendered as ampl_text renders this
;          channel's level - value, unit and blanking decided by the
;          destination - or the blank field ampl_text gives a destination
;          with no keyable level
;   uses:  A, B, X, Y, U
;
; WHAT THE STOCK PAINTS. draw_amplitude_increment ($5B13), called at $61E8
; by select_amptd_increment_field ($61E3) once $2215 is 7: after l5b2b
; ($5B2B) it converts record+15 (LEAX 15,X, then $CA8F into $2414) - the
; word step_amptd_by_increment ($7259) adds to record+10 - takes the unit
; code at record+$12 (LEAX <$12,X / LDX ,X), plants the edit marker at $1D
; with $C855, and calls render_value_with_units ($564E) with the channel,
; DDRAM $1F and $25 and that unit: the same dispatch at $574E and the same
; columns paint_channel_amptd ($57B1) uses for the level. The unit at
; record+$12 is the level's unit at record+13, written together by
; set_channel_destination ($78BF): every arm of its d7e78 table joins
; l7e8c ($7E8C), LDD 4,s / STD ,X into +13 and again into +$12, and its
; path after l7a45 ($7A45) stores $000D into both. So the increment is
; shown as the level would be shown - autoranged in V, mV or uV for an
; output, one decimal place for a depth or a deviation, blank for Off,
; Pulse or the DSB carrier - and with no sign, which is format_amplitude_
; autorange's $567F LDX >$2215 / CMPX #$0007 / LBEQ.
;
; HOW THIS GETS THE SAME ANSWER. ampl_text (modules/amplitude.s) takes the
; channel record, decides the unit from CHAN_DEST and from whether channel
; 0 carries a DSB modulator, and formats CHAN_AMPL. It is called twice:
; once on the real record, which settles chan_ampl_unit including the
; carrier case, and - unless that answer is a blank field, which the
; increment then shares - once on a copy of the record built on the stack
; with incr_ampl in place of the level. The copy is not channel_records, so
; ampl_text's carrier scan does not run on it; that is why the real record
; goes first.
; ---------------------------------------------------------------------------
chan_ampl_incr_text
                lbsr    chan_record             ; X = the record
                lbsr    ABI_ampl_text           ; chan_ampl_unit, for THIS
                lda     >chan_ampl_unit         ; channel's destination
                cmpa    #UNIT_OFF               ; blank stays blank: the
                beq     chan_ampl_incr_done     ; stock's +$12 holds the same
                cmpa    #UNIT_PULSE             ; 13 or 15 as +13, and 14 is
                beq     chan_ampl_incr_done     ; the carrier case
                cmpa    #UNIT_DSB
                beq     chan_ampl_incr_done
                lbsr    chan_record             ; X = the record again
                leas    -CHAN_RECORD,s          ; a copy of it on the stack
                leau    ,s
                ldb     #CHAN_RECORD
chan_ampl_incr_copy
                lda     ,x+
                sta     ,u+
                decb
                bne     chan_ampl_incr_copy
                lbsr    chan_incr_ampl_addr     ; with the increment where
                leau    CHAN_AMPL,s             ; the level was
                lda     ,x
                sta     ,u
                ldd     1,x
                std     1,u
                leax    ,s                      ; X = the copy
                lbsr    ABI_ampl_text           ; rendered as a level
                leas    CHAN_RECORD,s
chan_ampl_incr_done
                rts

; ---------------------------------------------------------------------------
; chan_ampl_show_sign - a dc level's sign, into the field beside its value
;
;   uses:  A, B, X, Y
;
; THE STOCK SHOWS THE SIGN OF A dc LEVEL, and of nothing else.
; format_amplitude_autorange ($5670) is arms [4], [5] and [6] of the unit
; switch at $574E - V, mV and uV, the only unit codes that reach it - and it
; tests the record's waveform word: $5670 LDX >$23BF / LEAX <$1F,x / LDX ,x
; / CMPX #$0004 / LBNE, then $567F LDX >$2215 / CMPX #$0007 / LBEQ; a dc
; channel reaches $568F LDX >$23BF / LEAX <$14,x / LDB ,x / STB 2,s, which
; replaces the space $565F seeded with the record's sign character.
; write_unit_label_and_digits ($576C) then writes that one character at the
; field position minus one ($577D LDD >$000F,s / SUBD #$0001, $5784 LEAU
; 2,s, $5788 LDB #$01) - DDRAM $1E for the AMPTD field paint_channel_amptd
; ($57B1) paints at $1F. Executed, a dc channel reads 'AMPTD +  140 V' and
; after a negative entry 'AMPTD -1.000  V'.
;
; THE $2215 TEST IS MADE BY THE CALLER, and what it guards was executed
; rather than read: with $2215 = 7 - INCR SET pressed on AMPTD - the stock's
; field carries the INCREMENT, painted '  600 mV' with the sign column blank,
; because an increment has no sign ($4F94 arms it as mode 3). chan_show_ampl
; paints the increment through chan_ampl_incr_text while INCR SET is armed
; on this field and does not come here, which is $567F's LDX >$2215 / CMPX
; #$0007 / LBEQ skipping the sign; the level, whenever it is the thing
; shown, is shown with its sign or it is misread. The entry layout keeps the
; same test: chan_ampl_signed.
;
; The byte is '-' or it is positive. The default record at $ED89 carries
; '+' at +$14 and apply_amplitude_entry only ever stores $241E, which
; entry_to_scaled_digits fills with '+' or '-' ($CE02-$CE1B), so the stock
; never paints anything else there; and a zero left by scratch_reset is
; positive to scale_to_dds_code's $D4E7 CMPB #$2D, so it is shown as the
; '+' the chip is treating it as.
; ---------------------------------------------------------------------------
chan_ampl_show_sign
                lbsr    chan_record             ; X = the record, B = channel
                lda     CHAN_WAVE,x
                cmpa    #LBL_DC                 ; $5670-$567E: dc only
                bne     chan_ampl_show_unsigned
                lda     >chan_ampl_unit         ; V, mV or uV: the arms of
                cmpa    #UNIT_VOLT              ; $574E that reach $5670
                blo     chan_ampl_show_unsigned
                cmpa    #UNIT_MICROVOLT
                bhi     chan_ampl_show_unsigned
                ldy     #ampl_signs             ; record+$14, $568F-$5698
                lda     b,y
                cmpa    #CHAN_SIGN_MINUS
                beq     chan_ampl_show_place
                lda     #CHAN_SIGN_PLUS         ; anything else is positive
chan_ampl_show_place
                andcc   #~CC_CARRY              ; carry CLEAR: A is the sign
                rts
chan_ampl_show_unsigned
                orcc    #CC_CARRY               ; carry SET: this field has no
                rts                             ; sign at all

; ---------------------------------------------------------------------------
; chan_ampl_sign_place - a dc level's sign, in the column one left of the
;                        field, wherever the digits fall inside it
;
;   uses:  A, B, X
;
; A FIXED COLUMN, and it is the stock's. The sign has no routine of its own
; there: format_amplitude_autorange ($5670), arms [4], [5] and [6] of the unit
; switch at $574E, puts the record's sign character into the local at 2,s
; ($568F LDX >$23BF / LEAX <$14,x / LDB ,x / STB 2,s), which
; render_value_with_units ($564E) had seeded with a space ($565F LDB #$20 /
; STB 2,s), and the common tail write_unit_label_and_digits ($576C) writes
; that ONE character at the field position LESS ONE - $577D LDD >$000F,s /
; SUBD #$0001 / $5784 LEAU 2,s / $5788 LDB #$01 / $D8EA - before it writes the
; five characters of the number at the field position itself. The AMPTD field
; is painted at DDRAM $1F (paint_channel_amptd $57B1), so the sign column is
; $1E, which is CHAN_S_AMPL, and it stays there when the number gets shorter.
;
; MEASURED, driving both firmwares side by side on 2026-09-13 with 'WFA DC;'
; on a 140 uV channel: the stock's line reads 'ch A: FREQ              AMPTD +
; 140 V ' with the '+' at column 30 and '140' at columns 33-35. This walked
; the five characters the field wrote for the first non-blank and put the sign
; one column to ITS left - column 32 - and skipped it altogether when that
; character was '0'. Both of those belong to level_sign_right_justify ($4569),
; which is page 2's DIGITAL level: a different field with a different rule.
; The channel screen has neither, so the scan and the '0' test go with them.
;
; A FIELD WITH NO SIGN GETS A BLANK, which is $565F's seeded space reaching
; the same column: the stock puts that character on the glass at every paint,
; sign or no sign, so a minus does not survive the level going positive or the
; waveform leaving dc.
; ---------------------------------------------------------------------------
chan_ampl_sign_place
                lbsr    chan_ampl_show_sign     ; A = the sign, carry set if
                bcc     chan_ampl_place_put     ; this field has none
                lda     #' '                    ; $565F's space: clear whatever
chan_ampl_place_put                             ; a previous level left there
                sta     >chan_work
                lda     #CHAN_S_AMPL            ; $577D: the field less one
                ldx     #chan_work
                ldb     #1
                lbra    ABI_lcd_write



; ---------------------------------------------------------------------------
; chan_show_phase - the phase and its unit, in the unit it was last entered in
;
;   uses:  A, B, X, Y, U
;
; THE STOCK PAINTS THE UNIT LAST USED, and this does the same.
; show_channel_phase_field ($5854), after its hop and dc/Noise cases, tests
; record+$19 at $5909-$5917: `LDX 2,s / LEAX <$19,x / LDX ,x / CMPX #$0003 /
; LBNE l5946`. For 3 it runs u16_to_5_ascii_digits ($C912) over record+$15,
; blank_leading_zeros ($CCFF) with a count of 3, and sets the point position
; to 4; for anything else it runs $C912 over record+$17 with the point
; position 2 and no blanking. Both then go through format_with_decimal_point
; ($CD50) with a digit count of 5, lcd_write_clipped ($D8EA) writes five
; characters from $2415 at DDRAM $46 - so 3599 tenths paint as '359.9' and
; 6282 milliradians as '6.282' - and lcd_write_unit_label ($ABEF) writes the
; three-character label for record+$19 at $4C.
;
; Here the degree value is the record's CHAN_PHASE with one decimal place and
; the radian value is the milliradian twin with three, each right-aligned in
; the nine-character field the other numeric fields use, and the label goes
; where the template's fixed 'deg' was. chan_phase_render blanks as many
; leading zeros as the unit's own arm blanks and no more - three for degrees,
; which is $CCFF's count over five digits and leaves '  0.0' for zero and
; '359.9' at the top; NONE for radians, which leaves '0.000' and '6.282'.
;
; The test is for CHAN_UNIT_RAD, where the stock's is for 3. The record the
; stock reads only ever holds 3 or 4 - unit_key_class3 ($B0F3) stores
; nothing else in $2221 and the default record carries 3 - so the two tests
; agree in every state the stock can reach; and chan_phase_unit is zero after
; scratch_reset (boot.s clears SCRATCH_BASE up to live_setting), where the
; stock's default copy puts 3, so a zero has to read as degrees.
;
; The phase is sixteen bits where the formatter takes twenty-four, so it is
; widened here with a zero high byte rather than the formatter being given a
; second entry point. One conversion in one place beats two formatters that
; have to be kept agreeing.
; ---------------------------------------------------------------------------
chan_show_phase
                lbsr    chan_on_glass           ; LDB >$23BE / CMPB >$3B81
                lbne    chan_show_off_glass     ; first, as the stock's does
                ldb     >current_channel        ; CHANNEL 0 WHILE PHASE HOP IS
                andb    #$03                    ; ON SHOWS '*Hop Ram*', as
                bne     chan_show_phase_own     ; show_channel_phase_field
                lda     >mode_flags             ; ($5854) paints d4384 at
                bita    #MODE_FLAG_PHASE        ; l58b6 for $23BE = 0 with bit
                beq     chan_show_phase_own     ; 7 of $2203 set, before its
                lda     #CHAN_F_PHASE           ; dc/Noise and unit cases
                ldb     #CHAN_HOP_W_PHASE
                lbra    chan_show_hop_marker
chan_show_phase_own
                lbsr    chan_record             ; X = the record, B = channel
                ; dc AND Noise SHOW NO PHASE EITHER, and for the same reason a
                ; dc channel shows no frequency: there is no waveform for a
                ; phase to be an offset of. show_channel_phase_field ($5854)
                ; blanks ten characters at DDRAM $46 (l5881 $5881), and at
                ; l58d0 ($58D0) reads record+$1F twice - CMPX #$0004 / LBEQ
                ; l58ef, CMPX #$0005 / LBEQ l58ef - and for 4 or 5 goes to
                ; l58ef ($58EF), which writes nine more blanks at $46 and
                ; returns at l59b0 without reaching the record+$19 unit switch
                ; at l5909. $46 is CHAN_F_PHASE and ten columns is
                ; CHAN_HOP_W_PHASE, which covers the value and the unit label
                ; at CHAN_U_PHASE.
                ;
                ; MEASURED on 2026-09-13 after 'WFA DC;': the stock's line 2
                ; reads 'PHASE            WFORM dc     DESTN Out1' where this
                ; firmware's still read 'PHASE   0.0 deg  WFORM dc     DESTN
                ; Out1'.
                ;
                ; AND THE INCREMENT IS EXEMPT, as it is on the frequency:
                ; paint_phase_increment ($5B98) goes from its displayed-channel
                ; test straight to l5bc5 ($5BC5), the record+$19 unit test,
                ; with no waveform test between them. chan_incr_shown uses A
                ; and the carry only, so X and B survive it.
                lda     #CHAN_FIELD_PHAS
                lbsr    chan_incr_shown
                bcc     chan_show_phase_plain
                lda     #CHAN_M_PHASE           ; paint_phase_increment
                lbsr    chan_marker_draw        ; marks column $45
                bra     chan_show_phase_unit    ; INCR SET: painted regardless
chan_show_phase_plain
                lda     CHAN_WAVE,x
                cmpa    #LBL_DC
                beq     chan_show_phase_blank
                cmpa    #LBL_NOISE
                bne     chan_show_phase_unit
chan_show_phase_blank
                lda     #CHAN_F_PHASE           ; $58EF: the value and the
                ldb     #CHAN_HOP_W_PHASE       ; unit label together
                lbra    ABI_lcd_blank
chan_show_phase_unit
                ldy     #chan_phase_unit
                lda     b,y
                cmpa    #CHAN_UNIT_RAD
                beq     chan_show_phase_rad

                lda     #CHAN_FIELD_PHAS        ; INCR SET ARMED ON THIS FIELD:
                lbsr    chan_incr_shown         ; the field shows the INCREMENT
                bcc     chan_show_phase_value   ; in the display's unit. The
                                                ; stock's paint_phase_increment
                                                ; ($5B98), called at $6216 by
                                                ; incr_set_phase ($6211) once
                                                ; $2215 is 8, tests record+$19
                                                ; against 3 at l5bc5 ($5BC5)
                                                ; as show_channel_phase_field
                                                ; ($5854) does, and for 3
                                                ; renders record+$1B - LEAX
                                                ; <$1B,X, $C912, $CCFF with a
                                                ; count of 3, the point at 4 -
                                                ; in the phase field's own
                                                ; columns, $46 and $4C
                ldd     >incr_phase+1           ; the tenths, as record+$1B
                bra     chan_show_phase_deg
chan_show_phase_value
                ldd     CHAN_PHASE,x            ; degrees: the record itself
chan_show_phase_deg
                std     >chan_work+1
                clr     >chan_work              ; the high byte of 24 bits
                lda     #CHAN_PHASE_BLANK_DEG   ; $592D blanks three here
                ldb     #CHAN_PHASE_DP_DEG      ; the stock's point after four
                lbsr    chan_phase_render       ; of five digits
                ldb     #UNIT_DEG
                bra     chan_show_phase_label

chan_show_phase_rad
                lda     #CHAN_FIELD_PHAS        ; and the increment's radian
                lbsr    chan_incr_shown         ; twin while INCR SET is
                bcc     chan_show_phase_rad_val ; armed: paint_phase_increment's
                                                ; other arm at l5c02 ($5C02),
                                                ; LEAX <$1D,X / $C912 with the
                                                ; point at 2, '6.282'
                lbsr    chan_incr_rad_get       ; D = the increment in
                bra     chan_show_phase_rad_txt ; milliradians, agreeing with
                                                ; incr_phase as +$1D does with
                                                ; +$1B
chan_show_phase_rad_val
                lbsr    chan_phase_rad_get      ; D = milliradians, agreeing
chan_show_phase_rad_txt
                std     >chan_work+1            ; with the record
                clr     >chan_work
                lda     #CHAN_PHASE_BLANK_RAD   ; l5946 blanks NOTHING, so the
                ldb     #CHAN_PHASE_DP_RAD      ; digit before the point stands
                lbsr    chan_phase_render       ; and after two, 'd.ddd'
                ldb     #UNIT_RAD

chan_show_phase_label
                lbsr    ABI_unit_label          ; B = the code, X = its three
                lda     #CHAN_U_PHASE           ; characters. They were two
                ldb     #UNIT_LABEL_LEN         ; local strings; the table is
                lbra    ABI_lcd_write           ; the stock's $EEEE and every
                                                ; screen now reads the same one

; ---------------------------------------------------------------------------
; chan_phase_render - five digits with the point where the unit wants it
;
;   entry: chan_work holds the value, B = the point's index in the output,
;          A = how many leading zeros this unit's layout may blank
;   uses:  A, B, X, U
;
; show_channel_phase_field ($5854) renders with u16_to_5_ascii_digits ($C912)
; and writes FIVE characters from $2415 - the six format_with_decimal_point
; makes, less the first. uint24_to_text produces eight digits and the last
; five are the same five, which is why the source below is text_buffer+3.
;
; THE BLANK COUNT IS THE CALLER'S, not a constant here. It was
; CHAN_PHASE_BLANK for both units, and the stock only blanks in its degree
; arm - see the note beside CHAN_PHASE_BLANK_DEG above for the addresses. A
; count of zero leaves every digit standing, which chan_blank_limit answers
; with an immediate RTS.
; ---------------------------------------------------------------------------
chan_phase_render
                pshs    a,b                     ; 0,s the blank count, 1,s the
                ldx     #chan_work              ; point's index
                lbsr    ABI_uint24_to_text
                ldx     #text_buffer+TEXT_DIGITS-CHAN_PHASE_DIGITS
                ldb     ,s
                lbsr    chan_blank_limit
                ldu     #text_buffer+TEXT_DIGITS-CHAN_PHASE_DIGITS
                ldx     #chan_text
                ldb     1,s
                leas    2,s
                lda     #CHAN_PHASE_DIGITS
                lbsr    chan_point
                lda     #CHAN_F_PHASE
                ldx     #chan_text+1
                ldb     #CHAN_W_PHASE
                lbra    ABI_lcd_write

; ---------------------------------------------------------------------------
; chan_show_wave - the waveform name
;
;   uses:  A, B, X
;
; The name comes from the shared table through the ABI, so this screen and
; the destination field cannot disagree about what a code means.
;
; A code the table does not define blanks the field AND records the fault,
; rather than blanking it silently. A blank waveform column reads as "not
; set", which is a different statement from "set to something nobody
; defined", and only one of the two is true.
; ---------------------------------------------------------------------------
chan_show_wave
                lbsr    chan_on_glass           ; draw_channel_waveform's
                lbne    chan_show_off_glass     ; guard, the same compare
                lbsr    chan_record
                ldb     CHAN_WAVE,x
                lbsr    ABI_label_find
                bcs     chan_show_wave_bad
                cmpb    #CHAN_W_WAVE            ; never write more than the
                bls     chan_show_wave_ok       ; field holds
                ldb     #CHAN_W_WAVE
chan_show_wave_ok
                lda     #CHAN_F_WAVE
                lbra    ABI_lcd_write
chan_show_wave_bad
                ldb     #ERR_DESTN_CODE
                lbsr    ABI_error_raise
                lda     #CHAN_F_WAVE
                ldb     #CHAN_W_WAVE
                lbra    ABI_lcd_blank

; ---------------------------------------------------------------------------
; chan_show_dest - the destination name
;
;   uses:  A, B, X
; ---------------------------------------------------------------------------
chan_show_dest
                lbsr    chan_on_glass           ; paint_channel_destn's guard
                lbne    chan_show_off_glass     ; ($59E7)
                lbsr    chan_record
                ldb     CHAN_DEST,x
                lda     #CHAN_F_DEST            ; destn_show owns this field:
                lbra    destn_show              ; it looks the name up,
                                                ; clamps it, and records a
                                                ; fault for a code no table
                                                ; defines

; ---------------------------------------------------------------------------
; chan_cursor_show - put the cursor on the selected field
;
;   uses:  A, B, X
;
; The cursor is the only thing on the screen saying which of the six fields a
; keystroke will go to, so it is moved every time the selection changes and
; never left behind.
; ---------------------------------------------------------------------------
chan_field_positions
                fcb     CHAN_F_CHAN
                fcb     CHAN_F_FREQ
                fcb     CHAN_F_AMPL
                fcb     CHAN_F_PHASE
                fcb     CHAN_F_WAVE
                fcb     CHAN_F_DEST

chan_cursor_show
                ldb     >field_index
                cmpb    #CHAN_FIELDS
                blo     chan_cursor_ok
                clrb                            ; a wild index selects the
                stb     >field_index            ; first field rather than
chan_cursor_ok                                  ; reading past the table
                ldx     #chan_field_positions
                lda     b,x
                lbra    ABI_lcd_cursor

; chan_field_next AND chan_field_previous WERE HERE, wrapping a cursor through
; the six fields, and chan_move_forward and chan_move_back below called them
; for NEXT and LAST. NOTHING CALLS THEM NOW and nothing should: this screen has
; no field cursor to move. Every field is selected by its own key - FREQ, AMPTD
; and PHASE by the three hard keys, WFORM by WAVE FORM and DESTN by shifted
; WAVE FORM - and NEXT and LAST page the seven records of menu_records_433e
; ($433E), which is the only thing they do anywhere in the instrument.
;
; chan_field_store keeps its name because every one of those key arms ends in
; it.
chan_field_store
                ; THE ENTRY ALREADY ON THE GLASS GOES BACK TO ITS VALUE, and
                ; the test is "was an entry field open", not "were digits
                ; typed". The stock does not do this in the screen's own arm
                ; at all: numeric_entry_key_handler ($B3C2), the foreground
                ; handler that owns the keyboard while an entry is open, tries
                ; the key against key_to_state_code ($AD4D) at lb434 ($B434)
                ; and then against keymap_menu_msgs_19_1d ($AEBB) at lb464
                ; ($B464) - the routine that turns key codes 6, 5, 4, 3 and
                ; $2A into the field-select requests $19-$1D - and on EITHER
                ; match it tests $23A8 (LDB >$23a8 / CMPB #$00 at $B43F and
                ; $B46F) and, when it is set, calls
                ; entry_exit_restore_display ($B38B) with 1 before letting the
                ; posted request run. $B38B clears $23A7 and $23A8, calls
                ; lcd_repaint_shadow ($D9C6) - both LCD lines rewritten from
                ; the 80-byte buffer at $242B - JSRs the screen's handler at
                ; $2211 and turns the cursor off with lcd_display_control
                ; ($D7BE)(1). $23A8 is set by arm_numeric_entry_field ($AC35)
                ; at $AC87 (LDB #$01 / STB >$23a8) the moment a field is armed
                ; from the panel, so it means "an entry field is open", with
                ; or without a digit in it, and entry_exit_restore_display is
                ; the only thing that clears it.
                ;
                ; The echo never reached the shadow - numeric_entry_key_handler
                ; writes the buffer $239A straight to the glass with
                ; lcd_write_string_at ($D8A5) at $B53D-$B555 - so repainting
                ; from it is what puts the abandoned field's own value back.
                ;
                ; Driven on both, 2026-09-13, on ch A with 1 kHz / 100 V /
                ; 0 deg standing: PHASE, 0, '.' shows 'PHASE 0.' on both, and
                ; then AMPTD returns the stock to 'PHASE   0.0 deg' while this
                ; firmware left 'PHASE 0.' on the line; a further FREQ, 0 then
                ; left the stock showing 'FREQ 0' with PHASE restored and this
                ; firmware showing both half-typed fields at once. That is the
                ; differential harness's second finding - the stock showing
                ; 0.0 where this firmware showed 0 - and it is not an echo
                ; rule about the character: the two echo a typed digit
                ; identically. It is the abandoned field never being repainted.
                ;
                ; chan_values_show rather than a whole-screen repaint because
                ; the echo cannot reach anything else: chan_entry_echo writes
                ; chan_field_geometry's width at its column and
                ; chan_entry_start blanks UNIT_LABEL_LEN at CHAN_U_FREQ,
                ; CHAN_U_AMPL or CHAN_U_PHASE, and every one of those columns
                ; is inside a field that chan_show_freq, chan_show_ampl,
                ; chan_show_phase and chan_ampl_show_sign rewrite - value,
                ; sign cell and unit label alike. The template columns the
                ; shadow repaint would also restore were never touched.
                ;
                ; entry_armed is read BEFORE this key arms the new field,
                ; which is why it is saved: it is this firmware's $23A8, set
                ; here and cleared only by the controller taking the
                ; instrument (remote_poll_remote).
                lda     >entry_armed            ; $23A8 as it stood
                ora     >incr_mode              ; ...or an increment showing
                pshs    a
                stb     >field_index
                clr     >field_is_hop           ; a channel field key: this
                                                ; cursor is the field id now
                lda     #$01                    ; AND A FIELD IS NOW ARMED.
                sta     >entry_armed            ; This screen arms its entry
                                                ; lazily - chan_entry_start
                                                ; runs on the first digit, not
                                                ; here - so the field KEY is
                                                ; where "a field is armed"
                                                ; begins, and the controller
                                                ; taking the instrument remote
                                                ; is where it ends
                clr     >chan_entry_unit        ; an abandoned entry takes its
                                                ; unit key with it
                clr     >entry_active           ; MOVING ENDS THE ENTRY.
                                                ; entry_active says "digits
                                                ; have been typed into this
                                                ; field", and it was set by
                                                ; the first digit and cleared
                                                ; only by ENTER, BACK and the
                                                ; screen opening - never by
                                                ; moving. So typing 100 into
                                                ; FREQ, moving to AMPL and
                                                ; typing 5 appended to the
                                                ; frequency's digits and gave
                                                ; 1005, which is exactly the
                                                ; failure the comment on
                                                ; chan_digit_typed says this
                                                ; flag exists to prevent.
                ; AND ENDS AN INCREMENT ENTRY, with the value put back in the
                ; field. The stock's select arm stores the value's own id and
                ; then calls end_field_edit ($5CE8): key_select_freq_field
                ; ($5ECA) is LDD #$0001 / STD >$2215 at l5efa ($5EFA), then
                ; LBSR end_field_edit, and end_field_edit, when $3B84 says
                ; an increment is armed, erases the marker with $C885, clears
                ; $3B84 and JSRs through $3B82 - the VALUE painter the INCR
                ; SET arm stored there ($54E6, $57B1 or $5854); its header
                ; counts eight such call sites immediately before a field
                ; select. So the field the operator left shows its value
                ; again, and a number typed on the new field lands in the
                ; new field's value. incr_mode surviving a move would have
                ; shown the new field's increment and taken the next ENTER
                ; into it.
                lbsr    chan_incr_end              ; unconditional now: the ORA
                                                ; above already read it, and
                                                ; clearing a byte that is
                                                ; already zero costs one write
                puls    a                       ; PULS leaves CC alone
                tsta
                beq     chan_field_store_move
                lbsr    chan_values_show        ; every field from its
                                                ; record, cursor last
                lbra    chan_field_arm          ; and THE ARM: [$3B85]
chan_field_store_move
                lbsr    chan_cursor_show        ; nothing was open: the stock
                                                ; skips $B38B too, and the
                                                ; posted arm only re-places
                                                ; the cursor
                lbra    chan_field_arm          ; - and turns it on

; ---------------------------------------------------------------------------
; chan_field_arm - the selected field's entry is armed: the cursor on it
;
;   uses:  A, B, X
;
; EVERY ARM ON THIS SCREEN ENDS IN [$3B85]. The stock's field keys, its INCR
; SET arms, its request-$23 commits and its steps all finish with LDU #sel /
; LDY #$0002 / PSHS Y,U / LDX >$3b85 / JSR ,X - arm_field_editor ($4ED8),
; installed there at $54CB LDD #$4ed8 / $54CE STD >$3b85 - which picks the field's
; five locals by selector and hands them to arm_numeric_entry_field ($AC35)
; through open_entry_field_from_locals ($5145 LBSR $ac35). The third word is
; the value position, which $AC98 makes the cursor's DDRAM address:
;
;   sel 0 FREQ   entry_cfg_freq, arm [0] of d5115      LDB #$0b / STB 3,s
;   sel 1 AMPTD  entry_setup_channel_amptd             LDB #$1f / STB 3,s
;   sel 2 PHASE  arm_phase_editor                      LDB #$46 / STB 3,s
;   sel 3 WFORM  entry_cfg_wform                       LDB #$57 / STB 3,s
;   sel 4 DESTN  entry_setup_destn                     LDB #$64 / STB 3,s
;
; and chan_field_positions holds exactly those five - CHAN_F_FREQ is
; LCD_LINE1+11, CHAN_F_AMPL LCD_LINE1+31, CHAN_F_PHASE LCD_LINE2+6,
; CHAN_F_WAVE LCD_LINE2+23 and CHAN_F_DEST LCD_LINE2+36. The selector is the
; field the arm has just stored in $2215, which is field_index here.
;
; FIELD 0 ARMS NOTHING. $2215 = 0 is no field, and none of the stock's arms is
; reached with it: the INCR SET dispatch at l62d9 and the step dispatch at
; l76ee both send 0 to their refusals before any [$3B85].
;
; AN AMPTD WITH NOTHING TO TYPE IS NOT ARMED - IT IS ENDED. The AMPTD arm
; switches on the channel's stored amplitude unit at record+13 (l4fa7, table
; d4fbe) and units $0D, $0E and $0F go to entry_cfg_unsettable ($4F27), which
; calls clear_pending_param_flag ($A472) and then entry_exit_restore_display
; ($B38B) with 0 at $4F3B and leaves through l514a without reaching $AC35:
; $23A8 cleared and the cursor OFF. That call is not gated on the remote bit.
; This firmware keeps no unit byte in the record - chan_field_class_ampl says
; why - and ampl_unit_for_destn answers from the destination instead, giving
; UNIT_OFF (13) and UNIT_PULSE (15) for the two blank-label destinations;
; UNIT_DSB is 14, and the range test covers all three the stock does.
; ---------------------------------------------------------------------------
chan_field_arm
                ldb     >field_index
                beq     chan_field_arm_none     ; $2215 = 0: no field
                cmpb    #CHAN_FIELDS
                bhs     chan_field_arm_none     ; nothing past the table
                cmpb    #CHAN_FIELD_AMPL
                bne     chan_field_arm_on
                pshs    b
                lbsr    chan_record             ; X = the record
                ldb     CHAN_DEST,x
                lbsr    ABI_ampl_unit_for_destn ; A = the unit the field carries
                puls    b
                cmpa    #UNIT_OFF               ; $0D, $0E and $0F: arms [12]
                blo     chan_field_arm_on       ; to [14] of d4fbe, the range
                cmpa    #UNIT_PULSE             ; chan_rq_ampl_armable tests
                bhi     chan_field_arm_on       ; for the bus's arm
                clr     >entry_armed            ; $B394 CLR >$23a8, and the
                lbra    ABI_entry_cursor_off    ; cursor off at $B3BA
chan_field_arm_on
                ldx     #chan_field_positions
                lda     b,x                     ; $23AD, the value position
                lbra    ABI_entry_cursor_on     ; $AC98 and $ACA6, local only
chan_field_arm_none
                rts

; ---------------------------------------------------------------------------
; chan_field_hop_locked - is this field key locked out by a hop on channel A?
;
;   entry: B = CHAN_FIELD_FREQ, CHAN_FIELD_AMPL or CHAN_FIELD_PHAS
;   exit:  carry SET when the key must do nothing; B unchanged
;   uses:  A
;
; The head of key_select_freq_field ($5ECA), key_amptd ($5F1D) and
; select_phase_field ($5F70), in one place: channel A ($23BE = 0), that
; field's hop bit set (event_flags2 $0100, $0040, $0080), and the instrument
; LOCAL (event_flags bit 3 clear). All three true is l63cc with nothing done.
; chan_key_fields has the addresses of each test.
; ---------------------------------------------------------------------------
chan_field_hop_locked
                lda     >current_channel
                anda    #$03                    ; as chan_show_freq reads it
                bne     chan_field_hop_free     ; $5ECD CMPB #$00 / LBNE
                lda     >rmt_flags
                bita    #RF_REMOTE              ; $5EE7 ANDB #$08 / $5EED LBNE
                bne     chan_field_hop_free
                cmpb    #CHAN_FIELD_FREQ
                bne     chan_field_hop_ampl
                tst     >hop_running            ; $5ED6 ANDA #$01: Freq Hop
                bne     chan_field_hop_lock
                bra     chan_field_hop_free
chan_field_hop_ampl
                lda     >mode_flags
                cmpb    #CHAN_FIELD_AMPL
                bne     chan_field_hop_phase
                bita    #MODE_FLAG_AM           ; $5F2B ANDB #$40: Amptd Hop
                bne     chan_field_hop_lock
                bra     chan_field_hop_free
chan_field_hop_phase
                bita    #MODE_FLAG_PHASE        ; $5F7E ANDB #$80: Phase Hop
                bne     chan_field_hop_lock
chan_field_hop_free
                andcc   #~CC_CARRY
                rts
chan_field_hop_lock
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; chan_key_commit - a terminator the field's class takes: commit and re-arm
; chan_key_commit_rad - the same for ENTER on PHASE, which means radians
;
;   uses:  whatever chan_commit and chan_commit_phase_rad use, then A, B, X
;
; THE ENTRY ENDS, THE VALUE IS TAKEN, AND THE FIELD IS ARMED AGAIN - in that
; order, which is the instrument's. accept_units_key ($B0C1, called at $B5A5)
; returning 1 falls past $B5AC LBEQ lb5d0 to entry_exit_restore_display
; ($B38B) with 0 at $B5BA - no repaint, the cursor OFF - and then
; post_request_code ($8AD0) with $23 at $B5C8. The request reaches page 0's
; chain, whose $23 arm commits by the field in $2215 - enter_freq_value
; ($6BA5), commit_amplitude_units_entry ($6CA9), commit_phase_entry ($6E51) -
; and each of those ends, on every path, in the re-arm through [$3B85]: the
; JSR ,X at $6C30 after l6c11 for FREQ (l6bf0 is reached whether or not $CDE1
; took the digits), at $6E3F after l6e29 for AMPTD and at $6ED0 after l6eb1
; for PHASE. So a refused value re-arms exactly as an accepted one does, and
; so does the increment an INCR SET entry commits: l6c11 stores $0001 back
; into $2215 before it arms. Measured on the stock in the emulator, seed 1 of
; the differential harness: kHz on FREQ, deg on AMPTD and deg on PHASE each
; send $0C and then $0E, with the cursor back at $0B, $1F and $46.
;
; chan_commit and chan_commit_phase_rad were reached by LBRA and end in a
; painter's RTS on every path, so an LBSR returns here from each of them.
; ---------------------------------------------------------------------------
chan_key_commit
                lbsr    ABI_entry_cursor_off    ; $B5BA
                lbsr    chan_commit             ; request $23's commit
                lbra    chan_field_arm          ; and its [$3B85]
chan_key_commit_rad
                lbsr    ABI_entry_cursor_off    ; $B5BA
                lbsr    chan_commit_phase_rad   ; request $23's commit
                lbra    chan_field_arm          ; and its [$3B85]

; The unit labels are in the template lines above, not here. They never
; change, so painting them on every repaint cost three writes and three
; routines for something already on the glass.


; ---------------------------------------------------------------------------
; chan_destn_allowed - may a destination be edited on this instrument?
;
;   exit:  carry CLEAR if it may; carry SET with the error recorded if not
;   uses:  A, B
;
; The stock's key_destn ($5FE6), arm [4] of the key table at $6044, opens
; with LDB >installed_options / ANDB #$01 / CLRA / CMPD #$0000 and, with bit
; 0 of $3FFC clear, calls error_report_beep ($C3FE) with $1F - 'Option FW
; needed for DESTN control', a2u13_page3 $75CC - and leaves through l63cc
; having selected nothing. Only with the bit set does it end the edit, store
; 5 in $2215 and open entry on the DESTN column. So without that option bit
; the stock never edits a destination from the panel, and neither does this
; screen. Executed on the stock in the emulator: $5FE6 with bit 0 of $3FFC
; cleared hands $1F to $C3FE.
;
; Read from installed_options each time, as hop_available (page0_hop.s) and
; tone_available (page1_tone.s) read their bits, because the service screen
; can change the byte while the instrument runs. error_record rather than
; error_raise because the stock's $C3FE beeps and records without replacing
; the screen.
; ---------------------------------------------------------------------------
chan_destn_fitted
                ; THE TEST ALONE, with no reporting, because two callers need
                ; the answer and only one of them wants the panel's message:
                ; the bus path answers the controller through remote_error and
                ; would otherwise report the same refusal twice.
                lda     >installed_options
                anda    #$01                    ; bit 0: the bit $5FE6 tests
                bne     chan_destn_fitted_yes
                orcc    #CC_CARRY
                rts
chan_destn_fitted_yes
                andcc   #~CC_CARRY
                rts

chan_destn_allowed
                lbsr    chan_destn_fitted
                bcc     chan_destn_allowed_yes
                ldb     #ERR_OPTION_DESTN
                lbsr    ABI_error_record
                orcc    #CC_CARRY
chan_destn_allowed_yes
                rts

; ---------------------------------------------------------------------------
; chan_bus_request - the page-0 chain's answer to a bus field-select request
;
;   entry: B = the delivered code, RMT_RQ + the stock's request code
;   exit:  carry CLEAR if this was one of them and it has been answered;
;          carry SET with B untouched if it was not, so the caller carries on
;   uses:  A, B, and everything chan_field_store uses on the answered path
;
; A BUS VALUE REACHES A FIELD ONLY IF THE SHOWING SCREEN ARMED IT, and this is
; where the Channel Configuration chain arms one. remote.s no longer arms a
; field itself: remote_select clears rmt_pend_kind and hands the stock's
; request code to whichever screen is installed, and only an arm like this one
; puts a field back into it - this firmware's $238F.
;
; THE STOCK HAS ONE HANDLER FOR THE WHOLE CHAIN and this firmware has two, so
; this routine is shared. enter_channel_config_mode ($528F) installs
; dispatch_ui_event ($5D0C) at $220F at $54BF and it stays installed for all
; seven records of menu_records_433e ($433E) - the title, the four channels,
; the Hop Ram fields and the hop On/Off page. Here chan_key answers the first
; five records and hop_key (page0_hop.s) the last two, so both call this.
;
; WHICH CODES, AND WHERE EACH COMES FROM:
;
;   $19 FRA-FRD   $1A APA-APD, DAPH, DAPL   $1B WFA-WFD
;   $1C PHA-PHD   $1D DEA-DED
;   $27 HRA       $28 FRH                   $29 APH
;   $2A PHH       $2B AHR, FHR, PHR, DPE    $36 QRE
;   $23           the entry-complete code the parser posts once a number or a
;                 mode code has arrived for the field one of the above armed
;
; $6042's guard sends $19-$1D straight to the five-arm table d6044 -
; key_select_freq_field ($5ECA), key_amptd ($5F1D), key_select_wform_field
; ($5FC3), select_phase_field ($5F70), key_destn ($5FE6) - WITHOUT looking at
; which record is up, and each of those stores a field id in $2215 and arms
; the entry through [$3B85]. Everything else falls past that guard to l604e,
; which needs bit 1 of installed_options AND either bit 3 of event_flags - the
; REMOTE state - or $268E = 5, and then reaches l6161, whose arms are the whole
; hop bus interface:
;
;   $27 -> l60e7   $2215 = $0012 and entry class $0A - the Hop Ram Adrs stop
;   $28 -> l607e   $2215 = $000C, class 6 - the slot's FREQ
;   $29 -> l60a1   $2215 = $000D, class 7 - its AMPTD
;   $2A -> l60c4   $2215 = $000E, class 8 - its PHASE
;   $2B -> l6100   begin_entry_hop_address ($4908): $3B80 = $2219 when that is
;                  below 4, then entry class 9, the On/Off toggle
;   $36 -> l610d   the four switch states as one number, out over the bus
;
; l6161 compares $19, $1A and $1C as well, but l602d has already taken every
; code from $19 to $1D, so those three arms cannot be reached and nothing here
; reproduces them. Over the bus the REMOTE test is always satisfied, which is
; why a hop field is reachable from a channel record.
;
; DRIVEN ON THE STOCK 2026-09-13, watching $238F:
;
;   title record       'FRA 900 HZ;' commits 9000, $238F = 01
;   ch A               'FRA 900 HZ;' 9000 then 'HP 5 KZ;' 50000, $238F = 01
;   ch A               'FRH 100 KZ;' into the hop slot, $238F = 01
;   Hop Ram record     'FRA 900 HZ;' 9000 AND 'FRH 100 KZ;' into the slot
;
; So the answer is unconditional on the record, which is why rmt_pend_kind is
; written before the record is looked at. What the record decides is only
; whether there is a field cursor to move: the title record has no fields on
; it and the hop records show the hop ones, so chan_field_store is called for
; the channel records alone. Where the stock puts its entry cursor on the
; title record was not driven and nothing here claims to reproduce it.
;
; THE TWO OPTION GATES ARE THE STOCK'S OWN, and they differ in the CODE they
; report, not in whether they report one. key_destn ($5FE6) tests bit 0 of
; installed_options and, with it clear, hands $1F to error_report_beep
; ($C3FE). l604e tests bit 1 and, with it clear, leaves through l6075 to
; l61a3, which is `ldx >$2217 / lbra l63b0` - the chain's DEFAULT arm. l63b0
; answers $1E, $1F, $20 and $25 and sends everything else to l6375, and l6375
; reports $18, 'No settable functions in this window'.
;
; THIS WAS WRITTEN HERE AS SILENCE, and it is not. Driven on the stock
; 2026-09-13 with installed_options = $01 - Option 003 absent - on the Channel
; Configuration chain: 'FRH;', 'APH;', 'PHH;', 'HRA;', 'AHR;' and 'QRE;' each
; leave $18 in $23DE, while 'FRA;' and 'DEA;' leave $00 because l602d takes
; them before the gate. A controller asking an instrument without the option
; for a hop field is told so; it was told nothing here.
; ---------------------------------------------------------------------------
chan_bus_request
                cmpb    #RMT_RQ+$19             ; FRA-FRD, d6044 arm [0]
                bne     chan_rq_ampl
                lda     #RK_FREQ
                ldb     #CHAN_FIELD_FREQ
                bra     chan_rq_channel
chan_rq_ampl
                cmpb    #RMT_RQ+$1A             ; APA-APD and DAPH/DAPL, arm [1]
                bne     chan_rq_wave
                lbsr    chan_rq_ampl_armable    ; AND THE ONE ARM OF THE FIVE
                lda     #RK_AMPL                ; THAT CAN DECLINE TO ARM -
                ldb     #CHAN_FIELD_AMPL        ; chan_rq_ampl_armable below.
                bcc     chan_rq_channel         ; LDA and LDB leave the carry
                clra                            ; alone, so the flags survive
                bra     chan_rq_channel         ; the two loads
                                                ;
                                                ; RK_NONE, AND THE CURSOR
                                                ; STILL MOVES. key_amptd
                                                ; ($5F1D) stores the field id
                                                ; - $5F4D LDD #$0002 / STD
                                                ; >$2215 - and calls
                                                ; end_field_edit ($5CE8)
                                                ; BEFORE it reaches the arm
                                                ; that may decline, so the
                                                ; screen's cursor lands on
                                                ; AMPTD either way and only
                                                ; the entry is missing.
                                                ; Driven 2026-09-14 on a
                                                ; two-channel stock: after
                                                ; 'APC;' $2215 = $0002 and
                                                ; $238F = $00
chan_rq_wave
                cmpb    #RMT_RQ+$1B             ; WFA-WFD, arm [2]
                bne     chan_rq_phase
                lda     #RK_WAVE
                ldb     #CHAN_FIELD_WAVE
                bra     chan_rq_channel
chan_rq_phase
                cmpb    #RMT_RQ+$1C             ; PHA-PHD, arm [3]
                bne     chan_rq_dest
                lda     #RK_PHASE
                ldb     #CHAN_FIELD_PHAS
                bra     chan_rq_channel
chan_rq_dest
                cmpb    #RMT_RQ+$1D             ; DEA-DED, arm [4]
                bne     chan_rq_hopfreq
                lbsr    chan_destn_allowed      ; $5FE6's own first act, with
                bcs     chan_rq_taken           ; $1F recorded for the bus to
                                                ; read back
                lda     #RK_DEST
                ldb     #CHAN_FIELD_DEST
chan_rq_channel
                ; AN ARM EMPTIES THE ENTRY. begin_numeric_entry ($A415) is
                ; what sets $238F, and it opens a fresh entry buffer, so a
                ; number an earlier message left waiting for its unit is
                ; gone: 'FRA 5;' 'FRA;' 'HZ;' sets nothing on the instrument
                ; (driven 2026-09-17) where 'FRA 5;' 'HZ;' sets 5 Hz.
                pshs    a
                lda     >rmt_flags              ; an arm empties the entry
                anda    #~RF_HELD&$FF           ; ($A415): no number held
                sta     >rmt_flags              ; from before it survives
                lda     #0                      ; and has a field cursor
                sta     >rmt_field_gone         ; again (LDA leaves carry)
                puls    a
                sta     >rmt_pend_kind          ; THE FIELD IS ARMED. This is
                                                ; $A415's STB >$238F, reached
                                                ; through the arm the request
                                                ; found
                stb     >field_index            ; AND THE FIELD ID IS WRITTEN
                clr     >field_is_hop           ; ON EVERY RECORD, which is the
                                                ; $2215 half of the same arm.
                                                ; $6042's guard hands $19-$1D
                                                ; to d6044 without looking at
                                                ; $268E and each arm's STD
                                                ; >$2215 runs before anything
                                                ; else, so the title and the
                                                ; two hop records get it too.
                                                ; Driven on the stock
                                                ; 2026-09-14, remote, sitting
                                                ; on the HOP RAM record:
                                                ; 'FRA;' leaves $2215 = $0001
                                                ; and the '?' after it answers
                                                ; '0001000.0' - channel A's
                                                ; frequency, read out while a
                                                ; hop record is on the glass.
                                                ; With this store inside the
                                                ; guard below, field_index
                                                ; stayed 0 and the query
                                                ; answered '? No Data ?'
                lda     >chan_chain
                beq     chan_rq_taken           ; the title record carries no
                                                ; field to move a cursor to
                cmpa    #CHAN_CHAIN_HOP
                bhs     chan_rq_taken           ; nor does either hop record
                lbsr    chan_bus_field          ; and the cursor, on a record
                                                ; that has one
chan_rq_taken
                andcc   #~CC_CARRY
                rts
chan_rq_hopfreq
                cmpb    #RMT_RQ+$28             ; FRH, l607e
                bne     chan_rq_hopampl
                lda     #RK_HOPFREQ
                ldb     #HOP_FIELD_FREQ
                bra     chan_rq_hop
chan_rq_hopampl
                cmpb    #RMT_RQ+$29             ; APH, l60a1
                bne     chan_rq_hopphase
                lda     #RK_HOPAMPL
                ldb     #HOP_FIELD_AMPL
                bra     chan_rq_hop
chan_rq_hopphase
                cmpb    #RMT_RQ+$2A             ; PHH, l60c4
                bne     chan_rq_hopaddr
                lda     #RK_HOPPHASE
                ldb     #HOP_FIELD_PHASE
chan_rq_hop
                pshs    a,b
                lbsr    chan_hop_option         ; l604e's gate, and $18 when it
                puls    a,b                     ; refuses (PULS leaves CC alone)
                bcs     chan_rq_taken
                pshs    a
                lda     >rmt_flags              ; an arm empties the entry
                anda    #~RF_HELD&$FF           ; ($A415): no number held
                sta     >rmt_flags              ; from before it survives
                lda     #0                      ; and has a field cursor
                sta     >rmt_field_gone         ; again (LDA leaves carry)
                puls    a
                sta     >rmt_pend_kind
                stb     >hop_field              ; and the hop screen's own
                                                ; cursor, which is what $2215 =
                                                ; $0C, $0D or $0E is there
                lda     #$01                    ; ...and a '?' reports from THIS
                sta     >field_is_hop           ; cursor now, even while a
                                                ; CHANNEL record is on the
                                                ; glass, which is what one
                                                ; $2215 means. A held the
                                                ; RK_HOP* code and has just
                                                ; been stored
                clr     >hop_entry_active       ; l607e, l60a1 and l60c4 each
                lbsr    chan_incr_end              ; call end_field_edit ($5CE8)
                                                ; between the store and the
                                                ; arm, and the arm reaches
                                                ; begin_numeric_entry, which
                                                ; empties the entry buffer
                                                ; $239A and zeroes its count
                                                ; $23A4
                bra     chan_rq_taken

                ; --- HRA: the Hop Ram address stop -------------------------
                ; l60e7 is l607e's shape with two differences and both are
                ; kept: the field id is $0012 rather than $000C-$000E, and
                ; there is NO end_field_edit call between the store and the
                ; arm - so a standing increment is not cancelled by this one.
                ; The arm itself still reaches begin_numeric_entry, which is
                ; why the entry flag goes out here as it does above.
chan_rq_hopaddr
                cmpb    #RMT_RQ+$27             ; HRA, l60e7
                bne     chan_rq_hoprow
                lbsr    chan_hop_option
                bcs     chan_rq_taken
                lda     >rmt_flags              ; an arm empties the entry
                anda    #~RF_HELD&$FF           ; ($A415): no number held
                sta     >rmt_flags              ; from before it survives
                lda     #0                      ; and has a field cursor
                sta     >rmt_field_gone         ; again (LDA leaves carry)
                lda     #RK_HOPADDR
                sta     >rmt_pend_kind
                lda     #HOP_FIELD_ADDR
                sta     >hop_field
                sta     >field_is_hop           ; $2215 = $0012, so the hop
                                                ; cursor is the field id. A is
                                                ; HOP_FIELD_ADDR, which is 3
                clr     >hop_entry_active
                bra     chan_rq_taken

                ; --- AHR, FHR, PHR and DPE: one of the four On/Off rows ----
                ; begin_entry_hop_address ($4908) reached with $2217 = $2B
                ; takes l4938: LDB >$2219 / CMPB #$04 / LBCC l494a, and l494a
                ; is l4981 - the RETURN, with no arm made. Below four the
                ; sub-code IS the row ($3B80) and the toggle field is armed.
                ; remote_cmd_rate parks the sub-code in rmt_tmp, which is
                ; $2219 here; HOP_ROW_PORT/FREQ/AMPL/PHASE are 0/1/2/3, the
                ; same numbering l491a-l4930 give the four softkeys, so the
                ; sub-code needs no translation. Driven on the stock
                ; 2026-09-13: 'DPE;' leaves $3B80 = 00, 'FHR;' 01, 'AHR;' 02
                ; and 'PHR;' 03, each with $2215 = $0013 and $238F = 01.
chan_rq_hoprow
                cmpb    #RMT_RQ+$2B             ; AHR/FHR/PHR/DPE, l6100
                bne     chan_rq_hopquery
                lbsr    chan_hop_option
                bcs     chan_rq_taken
                lda     >rmt_tmp                ; the sub-code, the stock's
                cmpa    #HOP_ROWS               ; $2219
                lbhs    chan_rq_taken           ; l4938: four and above arms
                sta     >hop_row                ; nothing and says nothing
                lda     >rmt_flags              ; an arm empties the entry
                anda    #~RF_HELD&$FF           ; ($A415): no number held
                sta     >rmt_flags              ; from before it survives
                lda     #0                      ; and has a field cursor
                sta     >rmt_field_gone         ; again (LDA leaves carry)
                lda     #RK_HOPROW
                sta     >rmt_pend_kind
                lbra    chan_rq_taken

                ; --- QRE: the four switches, as one number -----------------
chan_rq_hopquery
                cmpb    #RMT_RQ+$36             ; QRE, l610d
                bne     chan_rq_query
                lbsr    chan_hop_option
                lbcs    chan_rq_taken
                lbsr    hop_state_report
                lbra    chan_rq_taken

                ; --- '?': the SELECTED field, whatever put the cursor on it -
                ; l63b0, the chain's default arm, answers $1E, $1F, $20 and
                ; $25, and its $25 arm is $635E: LDD #$7B7A / TFR D,U, LDB #$03
                ; / SEX / TFR D,Y, LDX #$0004 / PSHS X,Y,U and LBSR $DB2B - so
                ; A2U13 goes to page 3, gpib_query_value_response ($7B7A) runs,
                ; and the page comes back. That routine reads $2215 and nothing
                ; else to decide what to report.
                ;
                ; THE CURSOR, NOT THE ARM. remote.s used to answer this itself
                ; from rmt_pend_kind - $238F, which says a field is ARMED for a
                ; value - and the two cells part company the moment an arm
                ; declines. Driven side by side 2026-09-14 on a two-channel
                ; instrument, Channel Configuration record 1, remote: 'APC;'
                ; leaves $2215 = $0002 with $238F = $00 on the stock and
                ; field_index = 2 with rmt_pend_kind = RK_NONE here, and the
                ; stock still answers the '?' after it while this firmware
                ; answered '? No Data ?' and recorded $0F.
chan_rq_query
                cmpb    #RMT_RQ+$25
                bne     chan_rq_entry
                lbsr    chan_query_field        ; A = the stock's $2215
                lbsr    ABI_remote_query_field
                lbra    chan_rq_taken           ; LONG: the arms above put the
                                                ; shared tail out of reach

                ; --- $23: the value or the choice for whatever is armed ----
                ; The stock has no separate bus setter for these two fields.
                ; pending_setting_service's number leg and its mode-code leg
                ; both end by posting request $23 to the mode handler, and the
                ; chain's arm for $23 is commit_entry_to_field ($6B84), which
                ; dispatches on $2215: [17] is enter_hop_addr_value ($6F78) for
                ; $0012 and [18] is apply_mode_toggle ($6FCB) for $0013. So the
                ; commit happens HERE, on page 0, beside the routines that own
                ; the address and the four rows - remote.s parks the number in
                ; rmt_val or the choice in hop_want and posts the code.
                ;
                ; No other kind reaches this: remote.s posts $23 for RK_HOPADDR
                ; and RK_HOPROW alone, and every other field it commits itself.
chan_rq_entry
                cmpb    #RMT_RQ+$23
                bne     chan_rq_none
                lda     >rmt_pend_kind
                cmpa    #RK_HOPADDR
                bne     chan_rq_entry_row
                lbsr    hop_bus_addr_commit     ; $6F78, over rmt_val
                lbra    chan_rq_taken           ; LONG: the six arms above put
                                                ; the shared tail out of a
                                                ; short branch's reach
chan_rq_entry_row
                cmpa    #RK_HOPROW
                bne     chan_rq_none            ; nothing of ours is armed:
                                                ; the caller's arms get it
                lbsr    hop_bus_row_commit      ; $6FCB
                lbra    chan_rq_taken           ; LONG, for the same reason

chan_rq_none
                orcc    #CC_CARRY               ; not one of ours: B is
                rts                             ; untouched and the caller's
                                                ; own arms get the code

; ---------------------------------------------------------------------------
; chan_query_field - the chain's selected field, as the stock's $2215
;
;   exit:  A = the field id gpib_query_value_response ($7B7A) dispatches on
;   uses:  A
;
; ONE CELL ON THE INSTRUMENT, TWO CURSORS HERE. $2215 covers the whole
; Channel Configuration chain: 1 to 5 for a channel record's FREQ, AMPTD,
; PHASE, WFORM and DESTN, 6 to 8 for the first three fields' INCREMENTS, $0C
; to $0E for a hop slot's three, $0F to $11 for the hop increments and $12 for
; the Hop Ram address stop. 0 is "no field", and 9, 10 and 11 are not arms of
; $7B7A at all.
;
; This firmware keeps the channel screen's cursor in field_index (0 to 5) and
; the hop screen's in hop_field (0 to 3), with incr_mode and hop_incr_mode
; saying an increment is showing - page0_screen.s's chan_incr_shown and
; page0_hop.s both already say in their own words that those flags ARE the
; stock's 6-to-8 and $0F-to-$11. field_is_hop says which cursor was written
; last, which is the one thing two cells cannot say by themselves.
;
; THE INCREMENT FLAGS ONLY MOVE THE VALUE-BEARING FIELDS. $2215 has no
; increment id for WFORM or DESTN and neither has the screen: chan_incr_shown
; is asked with a field id and chan_incr_address answers only for FREQ, AMPTD
; and PHASE, so a WFORM cursor with incr_mode somehow set still reports the
; waveform code. The Hop Ram address is the same - $12 has no increment form.
; ---------------------------------------------------------------------------
chan_query_field
                tst     >field_is_hop
                bne     chan_query_hop
                lda     >field_index
                beq     chan_query_done         ; 0: the Ch field, which $7B7A
                                                ; has no arm for - and neither
                                                ; does the stock's own screen,
                                                ; where 0 means nothing is
                                                ; selected
                cmpa    #CHAN_FIELD_PHAS
                bhi     chan_query_done         ; WFORM and DESTN report as
                                                ; themselves: 4 and 5
                tst     >incr_mode
                beq     chan_query_done
                adda    #CHAN_FIELD_DEST        ; 1, 2, 3 -> 6, 7, 8: the
                                                ; increment ids sit five above
                                                ; the value ids
chan_query_done
                rts
chan_query_hop
                lda     >hop_field
                cmpa    #HOP_FIELD_ADDR
                beq     chan_query_hop_addr
                tst     >hop_incr_mode
                bne     chan_query_hop_incr
                adda    #$0C                    ; FREQ, AMPL, PHASE -> $0C,
                rts                             ; $0D, $0E
chan_query_hop_incr
                adda    #$0F                    ; and their increments ->
                rts                             ; $0F, $10, $11
chan_query_hop_addr
                lda     #$12                    ; the Hop Ram address stop
                rts

; ---------------------------------------------------------------------------
; chan_rq_ampl_armable - has the commanded channel's AMPTD anything to type?
;
;   entry: rmt_pend_chan = the channel the AP mnemonic named
;   exit:  carry CLEAR when the field arms; carry SET when it does not, with
;          nothing written and nothing reported
;   uses:  A, B, X
;
; THE AMPTD ARM IS THE ONLY ONE OF THE FIVE THAT CAN DECLINE, and it is not
; about whether a board is fitted. The other four arms of d6044 -
; key_select_freq_field ($5ECA), key_select_wform_field ($5FC3),
; select_phase_field ($5F70) and key_destn ($5FE6) - reach
; arm_numeric_entry_field ($AC35) unconditionally, so $238F is always set and
; the value behind the mnemonic lands. key_amptd ($5F1D) reaches
; arm_field_editor ($4ED8) with selector 1, which is entry_setup_channel_amptd
; ($4EFE), and THAT routine reads the channel record's amplitude unit word -
; $4F0F LDX >$23BF / LEAX 13,X / $4F14 LDX ,X - and dispatches it through the
; guard at $4FA7 into the fifteen-word table d4fbe ($4FBE). Arms [12], [13]
; and [14] - unit codes $0D, $0E and $0F - are entry_cfg_unsettable ($4F27),
; which calls clear_pending_param_flag ($A472) and entry_exit_restore_display
; ($B38B) and branches to l514a, SKIPPING the $AC35 call entirely. $238F is
; never set, so the unit that follows the number finds no field armed and
; pending_setting_service's unit leg at $A900 answers $2F, 'Terminator
; received but not expected'.
;
; set_channel_destination ($78BF) is what puts those codes in the record:
; $7E5D writes $0D for Off and $7E2B writes $0F for Plse. A channel on either
; has no keyable amplitude - which is why ampl_unit_for_destn (amplitude.s)
; already returns UNIT_OFF and UNIT_PULSE for them, and why this needs no new
; table: the rewrite derives the unit from CHAN_DEST instead of storing a
; thirteenth record byte, as chan_field_class_ampl below explains.
;
; DRIVEN ON THE STOCK 2026-09-14, panel.boot_stock, Channel Configuration:
;
;   two channels, ch C has no board, record+13 = $000D, dest $0010 (Off)
;     'APC 1 VL;'   $23DE = $2F, $238F = 00, the record untouched
;     'APA 1 VL;'   $23DE = $00, $238F = 01, channel 0 takes the level
;   two channels, ch C given a unit first
;     'DEC FM;'     $23DE = $00, record+13 becomes $0002, dest $0008
;     'APC 1 KZ;'   $23DE = $00, $238F = 01 - A CHANNEL WITH NO BOARD TAKES
;                   IT, so the refusal is not about the board at all
;   four channels, ch C parked on Off with 'DEC OFF;' (record+13 = $000D)
;     'APC 1 VL;'   $23DE = $2F, $238F = 00 - A FITTED CHANNEL IS DECLINED
;                   when its destination has no unit
;
; So the test is the unit, in both directions, and installed_channels is not
; in it. The three codes are tested as the range $0D-$0F because that is what
; d4fbe spells - three adjacent arms, with $4FA7's own guard sending anything
; above $0F to entry_limits_none ($4FDC), which arms. ampl_unit_for_destn
; returns only 2, 3, 5, 11, 13 and 15 today; $0E (DSB) is in the range
; because the table puts it there, not because this firmware produces it -
; the $7E33 case that would is written up in ampl_unit_for_destn's header as
; not reproduced.
; ---------------------------------------------------------------------------
chan_rq_ampl_armable
                ldb     >rmt_pend_chan          ; THE COMMANDED CHANNEL, not
                andb    #$03                    ; the screen's - the stock's
                lda     #CHAN_RECORD            ; l9c04 stores the mnemonic's
                mul                             ; argument in $23BE and
                ldx     #channel_records        ; cache_channel_record_ptr
                leax    d,x                     ; ($C21A) points $23BF at that
                                                ; record before the arm runs.
                                                ; The mask is chan_record's,
                                                ; for the same reason: a wild
                                                ; channel number must not index
                                                ; outside the four records
                ldb     CHAN_DEST,x
                lbsr    ABI_ampl_unit_for_destn ; A = the unit the field carries
                cmpa    #UNIT_OFF               ; d4fbe [12], $0D
                blo     chan_rq_ampl_arms
                cmpa    #UNIT_PULSE             ; d4fbe [14], $0F
                bhi     chan_rq_ampl_arms
                orcc    #CC_CARRY               ; $4F27: no field, no error
                rts
chan_rq_ampl_arms
                andcc   #~CC_CARRY
                rts

; ---------------------------------------------------------------------------
; chan_hop_option - Option 003's gate on the chain's six hop requests
;
;   exit:  carry CLEAR when the option is fitted; carry SET when it is not,
;          with $18 recorded and reported
;   uses:  A, B, X
;
; l604e ($604E): LDB >installed_options / ANDB #$02 / LBEQ l6075, and l6075 is
; the branch to l61a3 - the chain's default arm, which reports $18. See the
; header above for the run that established the error code; hop_available
; (page0_hop.s) is the same option test the screen itself uses, read fresh
; from the byte rather than from a cached copy.
; ---------------------------------------------------------------------------
chan_hop_option
                lbsr    hop_available
                bcc     chan_hop_option_yes
                ldb     #ERR_CHAIN_NO_FUNC      ; l6375, through $9DD3 while
                lbsr    ABI_error_record        ; REMOTE and $C3FE otherwise -
                orcc    #CC_CARRY               ; which is what error_record
                rts                             ; chooses between
chan_hop_option_yes
                andcc   #~CC_CARRY
                rts

; ---------------------------------------------------------------------------
; chan_bus_field - take a bus-selected field's entry state down
;
;   uses:  A
;
; THE FIELD ID IS ALREADY STORED when this runs - chan_rq_channel writes it on
; every record, because the stock's arms do - and this is the REST of the
; stock's arm: end_field_edit ($5CE8) taking an armed increment down, and
; begin_numeric_entry emptying the entry. It is reached only on a record that
; has a field cursor, which is why the store is not here.
;
; A FIELD ARMED OVER THE BUS IS NOT A FIELD ARMED FROM THE PANEL, and the
; instrument makes the distinction in one place. arm_numeric_entry_field
; ($AC35) reads event_flags at $AC44, masks bit 3 - the REMOTE state - and
; when it is SET calls begin_numeric_entry ($A415) and LEAVES at $AC7E,
; jumping past $AC81 altogether. $AC81 is where CLR >$23A6, CLR >$23A7, LDB
; #$01 / STB >$23A8, lcd_set_cursor ($D7A0) and lcd_display_control ($D7BE)
; live. So a bus arm sets $238F, empties the entry buffer $239A and zeroes
; its count $23A4 - and does NOT set $23A8, does NOT move the cursor and
; does NOT turn the blink on.
;
; THAT IS WHY chan_field_store IS NOT USED HERE. It sets entry_armed, which
; is this firmware's $23A8, and the FOUR TERMINATOR KEYS read exactly that:
; ENTER, deg, Hz and kHz are key codes $1B, $1C, $1D and $1E, arms [26] to
; [29] of dae3d, and all four are keymap_unmapped_return0 - so
; key_to_state_code ($AD4D) returns 0 for them, keymap_menu_msgs_19_1d
; returns 0, and numeric_entry_key_handler ($B3C2) falls to lb494 ($B494),
; which beeps error 1 and returns when $23A8 is clear.
;
; NOT THE ARROWS, AND THAT SENTENCE USED TO SAY THE ARROWS. UP and DOWN are
; key codes $13 and $19, arms [18] and [24] of the same table -
; key19_state_20 and arm_post_request_1f - and each POSTS its request from
; inside key_to_state_code and returns 1, so lb494 is never reached and
; $23A8 never asked. Their guard is $2215, in step_selected_field ($71A3),
; and this firmware's is field_index in chan_step_field. Reading the wrong
; cell there cost seed 23 its phase register; the note is on that guard.
;
; DRIVEN ON THE STOCK 2026-09-13, on ch A with the option byte $03:
; 'DEA AM;' leaves $2215 = 0005 and $238F = 01 with $23A8 = 00, 'APA 5 PC;'
; leaves $2215 = 0002 and $238F = 01 with $23A8 STILL 00, and UP after them
; leaves AMPTD at 140 uV. With chan_field_store here this firmware stepped it
; to 141. scripts/acceptance.py case 4.8 is that pair of keystrokes and the
; differential harness reports the same thing on seed 19, step 4, where
; 'inc set' then a bus 'FRD 250 UV;' then UP moves PHASE on this firmware and
; not on the instrument. THAT UP IS PRESSED BACK IN LOCAL, and what refuses
; it on the instrument is $2215 = 0000: releasing REN posts request 1 and
; l5d33 zeroes the field id. Measured the same way 2026-09-13 - ch A, PHASE,
; 0, deg, REN asserted, REN released - the stock's $2215 reads 3, 3, 0. So
; not arming the entry here is still right, and it is not what refuses the
; arrow.
;
; What it DOES do is the rest of the stock's arm: $2215 gets the field id,
; end_field_edit ($5CE8) - which every d6044 arm calls between the store and
; the arm - takes the armed increment down, and begin_numeric_entry empties
; the entry buffer.
;
; AND IT REPAINTS NOTHING, which is not an economy but the measurement. The
; same run, with the harness's own preamble on ch A and the phase increment
; showing: after INC SET the stock has $2215 = 0008, $3B84 = 01 and line 2
; reading 'PHASE^G  1.0 deg' - the marker glyph and the INCREMENT in the
; value's columns - and after 'FRD 250 UV;' it has $2215 = 0001, $3B84 = 00,
; $238F = 01 and line 2 reading 'PHASE   1.0 deg'. The MARKER is gone and the
; 1.0 IS STILL THERE: end_field_edit clears the flag and erases the marker
; and does not put the phase value back. Repainting here through
; chan_values_show turned that 1.0 into 0.0, which is the differential
; harness's seed 19 divergence with the two machines the other way round.
;
; Nothing is left half-drawn by that. A half-typed panel entry cannot survive
; into a bus command - the panel is locked out while REN is asserted, and the
; transition itself runs remote_poll_remote, which empties the entry and
; sends KEY_REFRESH - so the only thing standing on the glass when this runs
; is a value or an increment, and the instrument leaves either where it is.
; ---------------------------------------------------------------------------
chan_bus_field
                                                ; THE FIELD ID IS THE CALLER'S,
                                                ; not this routine's: $2215 is
                                                ; written on every record and
                                                ; this runs only where there is
                                                ; a cursor, so the store lives
                                                ; in chan_rq_channel
                clr     >chan_entry_unit        ; the abandoned entry's unit
                clr     >entry_active           ; $23A4 = 0 and $239A spaces
                lbsr    chan_incr_end              ; $3B84 = 00, $5CE8's own job
                rts                             ; and no cursor: $AC81 is the
                                                ; branch the remote arm skips

; ---------------------------------------------------------------------------
; chan_key - act on one key press on the Channel Configuration screen
;
;   entry: B = the key code
;   uses:  A, B, X, Y, U
;
; Six fields. NEXT and LAST move between fields; on the two CHOICE fields -
; waveform and destination - they cycle the choice instead, because a field
; with eighteen possible values and no digits to type has nothing else for
; those keys to mean. ENTER commits. BACKSPACE takes the last character out
; of an entry in progress (chan_backspace_key).
;
; A key this screen does not use is IGNORED, not refused. A screen that beeps
; at every unrecognised key beeps constantly while somebody looks for the one
; that works.
; ---------------------------------------------------------------------------
chan_key
                ; A REPAINT FIRST, because this screen could not be told to do
                ; one. Every other screen in the tree answers KEY_REFRESH -
                ; the tone, DTMF, digital and stereo ones all do - and this
                ; one fell through to chan_key_ignore, which BEEPS. So a bus
                ; command that changed a channel field left the glass showing
                ; whatever was on it, and a half-typed entry the bus had just
                ; cancelled stayed on the line: driven 2026-09-13, PHASE armed
                ; and '4' typed, then one bus command - the stock's line 2
                ; returns to 'PHASE   0.0 deg' and this firmware's stayed at
                ; 'PHASE 4'. The differential harness found it on seed 1,
                ; step 14, as the stock having a number on screen that this
                ; firmware did not.
                cmpb    #KEY_REFRESH
                lbeq    chan_chain_show

                ; AND THE CONTROLLER GIVING THE INSTRUMENT BACK, which is a
                ; different event from the repaint above and does a different
                ; thing. hpib_reset_and_repaint ($9F45) posts request 1 at
                ; $9F8C and page 0 answers it at l5d33 ($5D33) with three
                ; steps: CLRB / CLRA / STD >$2215 - the FIELD ID goes - then
                ; end_field_edit ($5CE8), which takes an armed increment's
                ; marker down when $3B84 is set, and then select_menu_page
                ; ($514D), which repaints whichever record of the chain is
                ; standing. The three lines below are those three steps.
                ;
                ; WHY IT MATTERS HERE AND NOT ONLY ON THE GLASS: $2215 is what
                ; the arrows and INCR SET read, and nothing else clears it on
                ; the way back from remote. Measured on both, 2026-09-13, ch
                ; A: PHASE, 0, deg, REN asserted, REN released - the stock's
                ; $2215 reads 3, 3, 0 and this firmware's field_index read
                ; 3, 3, 3, so a panel arrow afterwards stepped a field the
                ; instrument had already let go of.
                cmpb    #KEY_GONE_LOCAL
                bne     chan_key_not_local
                lbsr    chan_incr_end              ; end_field_edit ($5CE8)
                clr     >field_index            ; l5d33's STD >$2215
                clr     >field_is_hop           ; - and $2215 is ONE cell, so
                                                ; the hop cursor is let go of
                                                ; here too
                lbra    chan_chain_select        ; select_menu_page ($514D)
chan_key_not_local
                ; AND $3C, THE REQUEST AN OVERLAY LEAVES BEHIND, is l5d22: the
                ; field id goes and the field edit ends, and nothing repaints.
                ; Driven on the stock, ch B with PHASE selected: shifted PHASE
                ; and '1' leave $2215 at 0, so an arrow afterwards records 4.
                ; $21, THE SAVE KEY, is l5dd9: end_field_edit, $2215 = 9, then
                ; save_recall_prompt ($F331) with $0021. No reader of $2215
                ; has an arm for 9: page 0 compares it with 1, 7 and $0F to
                ; $11, l62d9 refuses it with $20 as it refuses 0, and $7B7A
                ; has no arm for either. So the closed cursor stands for it.
                ; Driven, ch B with PHASE selected: shifted DOWN then UP
                ; records 4 on the stock.
                cmpb    #RMT_RQ+$21
                bne     chan_key_not_save
chan_key_save
                lbsr    chan_incr_end           ; end_field_edit ($5CE8)
                clr     >field_index            ; l5dd9's STD >$2215
                clr     >field_is_hop
                lbra    ABI_save_prompt_open    ; $F331 with $0021
chan_key_not_save
                cmpb    #KEY_ABANDON
                bne     chan_key_not_abandon
                lbsr    chan_incr_end           ; end_field_edit ($5CE8)
                clr     >field_index            ; l5d22's STD >$2215
                clr     >field_is_hop
                rts
chan_key_not_abandon

                ; THE BUS'S FIELD SELECTS, BEFORE THE RECORD IS LOOKED AT.
                ; $6042's guard hands $19-$1D to d6044 whatever $268E holds,
                ; so a bus select is answered on the title record too - driven
                ; on the stock 2026-09-13, 'FRA 900 HZ;' on the title commits
                ; 9000 with $238F = 01 - while the title record's own key arm
                ; below refuses every key but NEXT, LAST and f4. Putting this
                ; ahead of that test is what keeps the two apart.
                lbsr    chan_bus_request
                bcs     chan_key_not_bus
                rts
chan_key_not_bus

                ; THE TITLE PAGE HAS NO FIELDS ON IT, and the instrument
                ; answers a field key there with nothing at all. Driven on
                ; both, 2026-09-12: with the Channel Configuration mode just
                ; opened on 'Press NEXT/LAST keys.', FREQ then 5 then kHz
                ; leaves the stock's screen exactly as it was and channel 0
                ; still at 1 kHz - while this firmware armed the field,
                ; committed 5 kHz and painted '5.000 kHz' INTO THE TITLE LINE,
                ; over the mode's own banner.
                ;
                ; Found by the differential harness rather than by reading,
                ; which is what it is for. Only the page keys act here; every
                ; other key is refused as it is on any screen that has no use
                ; for it.
                lda     >chan_chain
                bne     chan_key_fields
                cmpb    #KEY_NEXT
                lbeq    chan_key_next_key
                cmpb    #KEY_LAST
                lbeq    chan_key_last

                ; AND F4 IS EXIT, which the record says in its own text -
                ; 'Press NEXT/LAST keys.    f4 Exit' - and which this refused
                ; along with everything else when the page keys were made the
                ; only ones that act here. Driven on the emulator 2026-09-12:
                ; f4 on this record returns the stock to the Main Selection
                ; Level and left this firmware on the title for ever, so a
                ; mode an operator opened could only be left by opening
                ; another one from a screen they could no longer reach. The
                ; page keys are the only ones that act on the FIELDS; the
                ; softkey the record labels is not one of those.
                cmpb    #KEY_F4
                lbeq    chan_key_title_exit
                lbsr    chan_key_is_softkey     ; f1 to f3: l5d4e, and the
                lbeq    chan_key_softkey_clear  ; record's vectors are $C239

                ; A KEY THAT POSTS A REQUEST IS $18 HERE, NOT $0F. Every code
                ; dispatch_ui_event's cascade does not claim goes to l5e6c,
                ; which with the panel local and $268E = 0 - this record - is
                ; l5e8a: LDB #$18 and error_report_beep ($C3FE). Driven on
                ; both, 2026-09-15: UP, DOWN, FREQ, AMPL, PHASE, WAVE FORM and
                ; INC SET on this record record $18 on the stock and recorded
                ; $0F here. Digits, the units, '.', MINUS, BACKSPACE and ENTER
                ; post no request - numeric_entry_key_handler keeps them - and
                ; record 1 on both, which chan_key_ignore already answers.
                lbsr    ABI_entry_key_is_mapped ; every register kept
                lbeq    chan_key_ignore
                ldb     #ERR_CHAIN_NO_FUNC      ; $18, 'No settable functions
                lbra    ABI_error_raise         ; in this window'
chan_key_title_exit
                lbsr    chan_key_softkey_clear  ; l5d4e first, then $8B4C
                lbra    ABI_screen_back         ; as tone_sk_exit leaves the
                                                ; sequence modes: the stock's
                                                ; post_request_0b -> $8E62
chan_key_fields
                ; THE FOUR SOFTKEYS ON A CHANNEL RECORD LET THE FIELD GO AND DO
                ; NOTHING ELSE. dispatch_ui_event ($5D0C) sends codes $13-$16
                ; to l5d4e - CLRB / CLRA / STD >$2215, end_field_edit ($5CE8),
                ; dispatch_menu_action ($8A2F) - and the vectors that calls
                ; for ch A to ch D in the record table at $433E are $C239,
                ; four times over. Driven on the emulator, both firmwares, ch
                ; B with PHASE selected: f4 leaves the instrument's $2215 at
                ; 0 with nothing recorded, so an arrow after it records 4;
                ; this refused f4 with $0F and the arrow stepped the phase.
                lbsr    chan_key_is_softkey
                lbeq    chan_key_softkey_clear
                ; THE FIELD-SELECT KEYS FIRST, because they are the only way
                ; ONTO some fields. NEXT walks Ch, FREQ, AMPL, PHASE, WAVE -
                ; and on WAVE it cycles the waveform, which is right and also
                ; means the walk ENDS there: DEST could only be reached by
                ; LAST wrapping backward from Ch, and once on either choice
                ; field the cursor could not leave except by leaving the
                ; screen. The stock does not have the trap because it has
                ; these keys: keymap_menu_msgs_19_1d ($AEBB) turns key codes
                ; 6, 5, 4, 3 and $2A into requests $19, $1A, $1B, $1C and
                ; $1D, and the d6044 arms select the field - $5ECA FREQ,
                ; $5F1D AMPTD, $5FC3 WAVE, $5F70 PHASE, $5FE6 DESTN - each
                ; ending any edit in progress and re-arming the entry, which
                ; is chan_field_store. (This comment once swapped keys 3 and
                ; 4 and mis-listed four of the five arm addresses; the
                ; listing's own headers are the source.)
                ;
                ; AND ON CHANNEL A THREE OF THEM CAN BE LOCKED BY A HOP. Each
                ; of the three opens with the same test before it selects
                ; anything: key_select_freq_field at $5ECA LDB >$23be / CMPB
                ; #$00 / LBNE, $5ED3 LDD >event_flags2 / ANDA #$01 (bit 8,
                ; Freq Hop) / LBEQ, $5EE2 LDD >event_flags / ANDB #$08 (the
                ; remote bit) / LBNE - and with channel A showing, the hop on
                ; and the instrument local, $5EF7 LBRA l63cc leaves with no
                ; field stored, no end_field_edit and no arm. key_amptd tests
                ; ANDB #$40 at $5F2B (Amptd Hop) and select_phase_field ANDB
                ; #$80 at $5F7E (Phase Hop) the same way. Those are the three
                ; fields chan_show_freq, chan_show_ampl and chan_show_phase
                ; paint as the hop marker, and hop_running, MODE_FLAG_AM and
                ; MODE_FLAG_PHASE are the same three bits here. The mapped key
                ; has already ended any open entry (entry_key_exit), so the
                ; key is spent and the cursor stays off - which is where the
                ; instrument leaves it.
                cmpb    #KEY_FREQ
                bne     chan_key_try_ampl
                ldb     #CHAN_FIELD_FREQ
                lbsr    chan_field_hop_locked   ; carry set: locked
                lbcc    chan_field_store
                rts
chan_key_try_ampl
                cmpb    #KEY_AMPL
                bne     chan_key_try_phase
                ldb     #CHAN_FIELD_AMPL
                lbsr    chan_field_hop_locked
                lbcc    chan_field_store
                rts
chan_key_try_phase
                cmpb    #KEY_PHASE
                bne     chan_key_try_wave
                ldb     #CHAN_FIELD_PHAS
                lbsr    chan_field_hop_locked
                lbcc    chan_field_store
                rts
chan_key_try_wave
                cmpb    #KEY_WAVEFORM
                bne     chan_key_try_dest
                ldb     #CHAN_FIELD_WAVE
                lbra    chan_field_store
chan_key_try_dest
                cmpb    #KEY_S_WAVEFORM         ; the stock's DESTN request,
                bne     chan_key_next_key       ; $1D, comes from key $2A -
                lbsr    chan_destn_allowed      ; shift and the WAVEFORM key.
                bcc     chan_key_dest_ok        ; key_destn ($5FE6) tests the
                rts                             ; option bit before anything
                                                ; else and, refused, selects
                                                ; nothing: LBRA l63cc, the
                                                ; dispatcher's LEAS 5,S / RTS
chan_key_dest_ok
                ldb     #CHAN_FIELD_DEST
                lbra    chan_field_store
                ; NEXT AND LAST WALK THE CHAIN, on every record of it. They
                ; moved the FIELD cursor here, and cycled a choice field when
                ; the cursor was on one - which is what the arrows do on the
                ; instrument ($697F's table), not these two. menu_page_key
                ; ($4C87) is both codes' arm everywhere else in the ROM.
chan_key_next_key
                cmpb    #KEY_NEXT
                bne     chan_key_last
                lda     >chan_chain             ; menu_item_next ($8A5B):
                cmpa    >chan_chain_last        ; at the limit, back to 0
                bhs     chan_key_chain_first
                inca
                bra     chan_key_chain_store
chan_key_chain_first
                clra
                bra     chan_key_chain_store
chan_key_last
                cmpb    #KEY_LAST
                bne     chan_key_enter
                lda     >chan_chain             ; menu_line_prev ($8A80): at
                bne     chan_key_chain_back     ; 0, the limit
                lda     >chan_chain_last
                bra     chan_key_chain_store
chan_key_chain_back
                deca
chan_key_chain_store
                sta     >chan_chain
                sta     >active_record          ; $89AA's $268E, which a save
                                                ; and a power-off carry
                lbsr    chan_incr_end              ; a record change cancels a
                lbra    chan_chain_select        ; pending increment
chan_key_enter
                ; THE FOUR TERMINATOR KEYS NEED AN ARMED FIELD, and this is
                ; the one test that decides it for all four at once - ENTER,
                ; Hz, kHz and deg. numeric_entry_key_handler ($B3C2) offers
                ; every key first to key_to_state_code ($AD4D) and then to
                ; keymap_menu_msgs_19_1d ($AEBB); arms [26] to [30] of the
                ; $AE3D table - key codes 27, 28, 29, 30 and 31, which are
                ; ENTER, deg, Hz, kHz and BACKSPACE - are all
                ; keymap_unmapped_return0 ($AE22), and $AEF8's chain claims
                ; only 3, 4, 5, 6 and $2A. So none of the four is claimed, and
                ; every one of them falls to lb494 ($B494): LDB >$23a8 / CMPB
                ; #$00 / LBNE lb4b0, and with it clear error_report_beep
                ; ($C3FE) is called with 1 and the handler returns - the
                ; column lookup, check_entry_terminator ($B070) and
                ; accept_units_key ($B0C1) are never reached.
                ;
                ; $23A8 is set by arm_numeric_entry_field ($AC35) at $AC87
                ; when a field is armed from the panel, and cleared by
                ; entry_exit_restore_display ($B38B), which enter_remote_state
                ; ($9EB9) calls the moment the controller asserts REN. So a
                ; bus command ENDS the panel's edit and the terminator keys
                ; that follow it fall on a screen with no armed field. The
                ; digit, point, sign, backspace and choice paths below all ask
                ; this already; the four terminators did not.
                ;
                ; Driven on both, 2026-09-13, ch A with 1 kHz / 100 V / 0 deg
                ; standing: 'DC 1 VL;' then 'EO 999 RD;' over the bus, then
                ; '.', then 'BSB 777;' and 'PHH 933;', then '1', then
                ; 'BF 1 HZ;', then ENTER - the stock's line 2 stays
                ; 'PHASE   0.0 deg' and this firmware's read 'PHASE  . 00 rad'
                ; because ENTER took the radian arm on an empty buffer and
                ; wrote CHAN_UNIT_RAD into chan_phase_unit. The differential
                ; harness found it on seed 8, step 7.
                cmpb    #KEY_ENTER
                beq     chan_key_terminator
                cmpb    #KEY_HZ
                beq     chan_key_terminator
                cmpb    #KEY_KHZ
                beq     chan_key_terminator
                cmpb    #KEY_DEG
                lbne    chan_key_error          ; SHIFTED INC SET, INC SET,
                                                ; the arrows and the entry
                                                ; keys are below, and each
                                                ; answers for itself
chan_key_terminator
                lbsr    ABI_entry_is_open       ; lb494: no armed field, no
                lbeq    chan_key_ignore         ; terminator
                cmpb    #KEY_ENTER
                bne     chan_key_units
                lda     >field_index            ; ON PHASE, ENTER IS THE
                cmpa    #CHAN_FIELD_PHAS        ; RADIAN TERMINATOR: key $1B
                lbeq    chan_key_commit_rad     ; is unit 4 in unit_key_class3
                                                ; ($B0F3), see the file header
                ; AND ON A FIELD WHOSE CLASS TAKES A UNIT KEY, ENTER IS NOT A
                ; TERMINATOR AT ALL - it beeps, exactly as $B5D0 does when
                ; accept_units_key ($B0C1) has returned zero. Only class 2 (the
                ; Ch field, the stock's $B0CD) commits on it. This screen used
                ; to commit everything on ENTER.
                ;
                ; NOR ON THE CHOICE FIELDS, which this committed. WFORM and
                ; DESTN arm with units class 0 - entry_cfg_wform and
                ; entry_setup_destn both CLRB / CLRA / STD 5,s, the word
                ; open_entry_field_from_locals ($512B) passes as $23AB - and
                ; accept_units_key's range test at lb1ff (CMPX #$0007 / BGT,
                ; SUBD #$0002 / BLT lb1f7) sends classes 0 and 1 to lb1f7, CLR
                ; 2,S: zero, so $B3C2 beeps at $B5D0 and posts no $23. No
                ; commit, no exit at $B5BA, no re-arm. A choice field commits
                ; on its own keys, through chan_choice_key.
                lbsr    chan_field_class_get    ; A = this field's class
                cmpa    #CHAN_CLASS_ENTER
                lbeq    chan_key_commit

                ; AND ON A PHASE DEVIATION, ENTER IS RADIANS. amptd_unit_key_rad
                ; ($6C4C) is arm 3 of the AMPTD field's unit table, unit key 4 -
                ; which is ENTER, the key unit_key_class3 ($B0F3) calls unit 4.
                ; Driven on the stock 2026-09-11 on a phi-M channel: 1 ENTER
                ; reads '1.000 rad', 3 ENTER '3.000 rad' and 4 ENTER is refused
                ; with $7A, which is the 179.9-degree ceiling in radians. The
                ; level field had no radian path at all, so a deviation could be
                ; typed in degrees and not in radians.
                cmpa    #CHAN_CLASS_PHASE
                lbne    chan_key_ignore
                ldb     #UNIT_RAD
                stb     >chan_entry_unit
                lbra    chan_key_commit
chan_key_units
                ; THE THREE UNIT KEYS, TOGETHER. Which of them this field takes,
                ; and what each means, is chan_class_units - the stock's $B212
                ; read out. deg keeps its own arm below because on PHASE it also
                ; records the unit into the record before committing.
                cmpb    #KEY_HZ
                beq     chan_key_unit_hz
                cmpb    #KEY_KHZ
                bne     chan_key_deg            ; the four terminators are all
                                                ; that reach here, so what is
                                                ; left is deg
                ldb     #2                      ; the kHz column
                bra     chan_key_unit
chan_key_unit_hz
                ldb     #1                      ; the Hz column
chan_key_unit
                lbsr    chan_key_unit_lookup    ; B = the UNIT_* code, or carry
                lbcs    chan_key_unit_wrong     ; set if this class beeps here
                stb     >chan_entry_unit
                lbra    chan_key_commit

chan_key_deg
                lda     >field_index            ; and deg, key $1C, is unit 3
                cmpa    #CHAN_FIELD_PHAS        ; there - the degree
                bne     chan_key_deg_other      ; terminator, which is what
                                                ; chan_commit_phase takes.
                ; THE UNIT IS RECORDED FIRST, empty entry or not: on the
                ; stock, key $1C makes unit_key_class3 ($B0F3) store 3 in
                ; $2221 and set_phase_units_and_apply ($6E46) copies it to
                ; record+$19 before commit_phase_entry ($6E51) looks at the
                ; digits. An INCR SET commit goes to arm [7] of d717a
                ; instead, which is $6E51 itself, and leaves record+$19
                ; alone - so the increment's unit never changes the display.
                tst     >incr_mode
                bne     chan_key_deg_commit
                lbsr    chan_record             ; B = the channel
                ldx     #chan_phase_unit
                abx
                lda     #CHAN_UNIT_DEG
                sta     ,x
                lda     #UNIT_DEG               ; AND THE DIGITS ARE DEGREES,
                sta     >chan_entry_unit        ; not tenths: $6E51 hands $CDE1
                                                ; a window of 7 against the deg
                                                ; decade $12, one power of ten -
                                                ; unit_decades deg. A typed 90
                                                ; is 900 tenths.
chan_key_deg_commit
                lbra    chan_key_commit
chan_key_deg_other
                ; deg ON A FIELD THAT IS NOT PHASE. On the AMPL field it is the
                ; microvolt terminator - $B127's deg arm stores unit 7 - and on
                ; anything else its class refuses it and it beeps.
                ldb     #0                      ; the deg column
                lbsr    chan_key_unit_lookup
                lbcs    chan_key_unit_wrong     ; pushed out of short-branch
                                                ; range by chan_key_error
                stb     >chan_entry_unit
                lbra    chan_key_commit
                                                ; On any other field the stock
                                                ; either maps it to another
                                                ; unit (uV, class 4 at $B127)
                                                ; or beeps code 2 at $B5D0;
                                                ; here it is refused like any
                                                ; other key this screen does
                                                ; not use
chan_key_error
                ; SHIFTED INC SET FLASHES THE LAST ERROR HERE TOO. dispatch_ui_
                ; event ($5D0C) answers message $01 - SHIFT then INC SET,
                ; posted the same way on every screen - at l5d18 ($5D18):
                ; LBSR $C418 (show_last_error_screen) and fall into l5d22
                ; ($5D22), which zeroes the field id $2215 and calls
                ; end_field_edit ($5CE8) - the same three-instruction clear
                ; and close the GONE LOCAL arm above uses, because $2215 is
                ; the one cell both answer.
                ;
                ; main_menu_key (main_menu.s) and digital_key_error
                ; (page2_digital.s) already answer this key; Channel
                ; Configuration did not, so pressing it here fell through to
                ; chan_key_ignore and left the channel record standing with
                ; no flash at all. Found by the differential harness, seed 3
                ; step 28: with ch B on screen, SHIFT then INC SET left the
                ; stock showing '* Last reported error was no.  47 *' and
                ; this firmware unchanged.
                cmpb    #KEY_S_INC_SET
                bne     chan_key_incr
                lbsr    ABI_error_show
                lbsr    chan_incr_end              ; end_field_edit ($5CE8)
                clr     >field_index            ; l5d22's STD >$2215
                clr     >field_is_hop           ; - and $2215 is ONE cell, as
                                                ; the GONE LOCAL arm above
                lbra    chan_chain_select        ; notes
chan_key_incr
                cmpb    #KEY_INC_SET
                bne     chan_key_up
                lbra    chan_incr_begin
                ; THE ARROWS STEP WHATEVER THE CURSOR IS ON, and on a CHOICE
                ; field that means walking its list. The stock's up and down
                ; codes reach the eleven-arm table at $697F, whose arm for the
                ; field in $3D11 does the stepping - a numeric field by its
                ; increment, the waveform and destination fields through their
                ; lists. This firmware cycled a choice field with NEXT and LAST
                ; instead, which are the two keys that page the chain.
chan_key_up
                cmpb    #KEY_UP
                bne     chan_key_down
                lbsr    chan_field_is_choice
                bcs     chan_key_no_step
                ldb     #$01                    ; forward one increment
                lbra    chan_step_field
chan_key_down
                cmpb    #KEY_DOWN
                bne     chan_key_choice
                lbsr    chan_field_is_choice
                bcs     chan_key_no_step
                ldb     #$FF                    ; and back one
                lbra    chan_step_field
chan_key_no_step
                ; A CHOICE FIELD CANNOT BE STEPPED. step_selected_field
                ; ($71A3) reaches its arms through d7701, whose [3] and [4] -
                ; the waveform and destination field ids - are
                ; reject_step_error_4: error 4, 'No incrementable field'. The
                ; arrows cycled the list here, which is not a thing the
                ; instrument does with them.
                ;
                ; AND THROUGH error_raise, as chan_step_none does:
                ; reject_step_error_4 ($76D8) is a call to error_report_beep
                ; ($C3FE), which stores $23DE and pulses timer 1 and nothing
                ; else ($C3FE-$C417) - no report_error_and_pulse_status_bit,
                ; so no SRQ. error_record's bus report put the SRQ lamp on
                ; after 'DN;' where the instrument's stays off (seed 20).
                ldb     #ERR_NO_STEP_FIELD
                lbra    ABI_error_raise

chan_key_choice
                ; AND EVERY OTHER KEY GOES THROUGH THE FIELD'S OWN COLUMN
                ; while a choice field is selected, which is what entry modes
                ; 4 and 5 do: the key is looked up in a column of
                ; keypad_char_table ($EF94) and the code it finds is committed
                ; on that same press. A key with no code there is error 2,
                ; 'Invalid key entry', at $B5D0 - which is why ENTER, the unit
                ; keys, BACKSPACE and, on DESTN, 5 and 6 all beep.
                ;
                ; AND THE FIELD HAS TO BE ARMED, exactly as the digit, point,
                ; sign and backspace paths below require. The column lookup is
                ; not reached at all on an unarmed field:
                ; numeric_entry_key_handler ($B3C2) tests $23A8 at lb494
                ; ($B494) - LDB >$23a8 / CMPB #$00 / LBNE lb4b0 - and with it
                ; clear calls error_report_beep ($C3FE) with 1 and returns, so
                ; keypad_char_column_select ($AF29) never runs and the mode-5
                ; column of keypad_char_table ($EF94) is never read. $23A8 is
                ; set by arm_numeric_entry_field ($AC35) at $AC87 when a field
                ; is armed from the panel and cleared by
                ; entry_exit_restore_display ($B38B), which enter_remote_state
                ; ($9EB9) calls when the controller asserts REN - so a bus
                ; command ENDS the panel's edit, and the keys that follow it
                ; fall on a screen with no armed field.
                ;
                ; The choice fields were the one path here that never asked.
                ; Driven on both, 2026-09-13, ch A: WAVE FORM, then 'DG;' over
                ; the bus, then 6 - the stock's line 2 stays 'WFORM Sine' and
                ; this firmware's read 'WFORM dc'; then 2, and the stock is
                ; still 'WFORM Sine' while this firmware read 'WFORM Ramp'.
                ; That is the differential harness's seed 2, first divergence
                ; at step 4, and its visible end is a relay: a waveform of 2
                ; is 'any' in recompute_channel_byte_24ec's rule ($F7EC), so
                ; the channel's filter line went in on an instrument whose
                ; waveform had not changed.
                ;
                ; With the field armed by its key and no bus command between,
                ; the two agree key for key - driven the same session: 2 gives
                ; 'WFORM Ramp' on both, 3 'WFORM Trngl' on both, 1 'WFORM
                ; Sine' on both, and 0 is refused by both, which is the $58
                ; ('X') that column 3 of $EF94 carries for key $0F.
                ;
                ; chan_key_ignore rather than error 1: key_refuse (errors.s)
                ; records $0F 'Un-executable command' where $B49A records 1,
                ; and no name for 1 is declared among the ERR_ constants. The
                ; refusal is right; the number is one this file cannot reach.
                lbsr    chan_field_is_choice
                bcc     chan_key_backspace
                lbsr    ABI_entry_is_open
                lbeq    chan_key_ignore
                lbra    chan_choice_key
chan_key_backspace
                cmpb    #KEY_BACKSPACE
                bne     chan_key_point
                lbra    chan_backspace_key      ; the last character out of
                                                ; the entry: $B4B9
chan_key_point
                ; THE DECIMAL POINT. Column 7 of keypad_char_table ($EF94) -
                ; entry mode 3's column, which every numeric field on this
                ; screen arms - holds '.' beside the ten digits, and
                ; entry_to_scaled_digits ($CDE1) scales the digits by the
                ; unit's decades less the ones that followed it. Driven on the
                ; stock 2026-09-11: 100 . 5 then Hz is 100.5 Hz, and this
                ; firmware put 1005.0 Hz on the chip because the key was
                ; dropped and the digits ran together.
                cmpb    #KEY_POINT
                bne     chan_key_minus
                lbsr    chan_field_is_choice
                lbcs    chan_key_ignore         ; a list takes no point
                lbsr    ABI_entry_is_open       ; as the digit path, and in the
                lbeq    chan_key_ignore         ; same order: an unarmed field
                                                ; takes no key at all, whether
                                                ; or not entry_active is still
                                                ; standing from an entry the
                                                ; controller ended
                tst     >entry_active
                bne     chan_key_point_take
                lbsr    chan_entry_start        ; '.5' opens the entry, as the
                lda     #$01                    ; stock's already-armed field
                sta     >entry_active           ; takes it as its first key
chan_key_point_take
                lbsr    ABI_entry_point
                bcs     chan_key_point_twice
                lbra    chan_entry_echo
chan_key_point_twice
                ldb     #ERR_KEY_ENTRY          ; a second point: $B5D0's 2
                lbra    ABI_error_raise

chan_key_minus
                cmpb    #KEY_MINUS
                bne     chan_key_digit
                lbra    chan_sign_key           ; the sign of a dc level's
                                                ; entry; refused on any other
                                                ; field, as before
chan_key_digit
                ; A LOOKUP, NOT A RANGE TEST. The ten digit codes are 15, 12,
                ; 18, 24, 11, 17, 23, 10, 16 and 22 for 0 to 9 - scattered
                ; across the matrix in the order the panel lays the keys out.
                ; This was written as "between the code for 0 and the code
                ; for 9", which accepts eleven keys that are not digits and
                ; rejects two that are.
                lbsr    ABI_key_digit           ; carry clear and B = 0 to 9
                bcs     chan_key_ignore
                lbra    chan_digit_typed
chan_key_unit_wrong
                ldb     #ERR_KEY_ENTRY          ; A UNIT THE ARMED FIELD'S CLASS
                lbra    ABI_error_raise         ; HAS NO ARM FOR: $B5D0's 2
                                                ; through $C3FE. B was already
                                                ; the lookup's answer, not the
                                                ; key, so key_refuse could not
                                                ; tell - driven, FREQ then deg
                                                ; on ch A leaves 2 on the
                                                ; instrument and left 15 here
chan_key_ignore
                ; A BUS REQUEST NO ARM ANSWERS IS $18, NOT $0F. dispatch_ui_event
                ; ($5D0C) sends every code its chain does not claim to l6375
                ; ($6375), 'No settable functions in this window', reported
                ; through $9DD3 while remote. Driven 2026-09-15 on ch A and the
                ; Channel Configuration title: RUNM, RUNC, STOP, WSQ and SEQP
                ; each leave $23DE = $18 on the instrument, and left $0F here.
                cmpb    #RMT_RQ
                blo     chan_key_ignore_key
                ldb     #ERR_CHAIN_NO_FUNC
                lbra    ABI_error_record
chan_key_ignore_key
                lbra    ABI_key_refuse          ; a key this screen cannot
                                                        ; use is REFUSED, not
                                                        ; ignored; see key_refuse


; ---------------------------------------------------------------------------
; chan_key_is_softkey    - is B one of f1 to f4?
; chan_key_softkey_clear - l5d4e ($5D4E): the field id goes and its edit ends
;
;   exit (is):     Z SET for f1, f2, f3 or f4
;   uses (clear):  A, B, X, Y, U
; ---------------------------------------------------------------------------
chan_key_is_softkey
                cmpb    #KEY_F1
                beq     chan_key_is_softkey_done
                cmpb    #KEY_F2
                beq     chan_key_is_softkey_done
                cmpb    #KEY_F3
                beq     chan_key_is_softkey_done
                cmpb    #KEY_F4
chan_key_is_softkey_done
                rts
chan_key_softkey_clear
                lbsr    chan_incr_end           ; end_field_edit ($5CE8)
                clr     >field_index            ; STD >$2215
                clr     >field_is_hop           ; one cell for both cursors
                rts

; ---------------------------------------------------------------------------
; chan_incr_begin - the next ENTER stores this field's INCREMENT
;
;   uses:  A, B, X
;
; INCR SET, and it is a MODE rather than a screen of its own: the operator
; types a number and presses ENTER exactly as they would to set a value, and
; the only difference is where it lands. The stock works the same way - $62EC
; selects which field an increment belongs to and $717A commits it through the
; same entry machinery as a value.
;
; THE FIELD SHOWS THE INCREMENT WHILE THE MODE IS ARMED, as the stock's does.
; Each arm of the $62EC table paints it before arming the entry:
; begin_freq_increment_entry ($61B5) with show_freq_increment_field ($5A1B),
; select_amptd_increment_field ($61E3) with draw_amplitude_increment ($5B13),
; incr_set_phase ($6211) with paint_phase_increment ($5B98) - and arms [5],
; [6] and [7], taken when $2215 already is 6, 7 or 8, are those same three
; routines, so a second INCR SET repaints and re-arms. The painting is in
; chan_show_freq, chan_show_ampl and chan_show_phase, each asking
; chan_incr_shown, so every repaint keeps it; digits typed then echo over it
; and ENTER stores them (chan_commit). ENTER, TYPED OR NOT, PUTS THE VALUE
; BACK: enter_freq_value ($6BA5) reaches l6c11 ($6C11) from both sides of
; its CMPB #$08 - LDD #$0001 / STD >$2215 / CLR >$3B84 /
; draw_channel_frequency - commit_amplitude_units_entry ($6CA9) reaches
; l6cfa ($6CFA), LDD #$0002 / STD >$2215, from its CMPB 3,s / LBCC and from
; both sides of the CMPD #$0000 after store_amplitude_increment ($690F),
; and commit_phase_entry ($6E51) reaches l6eb1 ($6EB1), LDD #$0003 / STD
; >$2215 / show_channel_phase_field, past its CMPB #$05 / LBCC as well as
; after set_phase_increment ($697B). Here incr_mode is cleared on every
; ENTER exit - chan_commit_incr_store, chan_commit_choice,
; chan_commit_refused and chan_commit_rad_too_big - so the next repaint is
; the value. It was cleared only by a typed commit, so ENTER with nothing
; typed, or with a refused entry, left the increment armed and showing.
;
; A field with no increment REFUSES the key rather than arming a mode the
; commit would then have to unpick - and refusing means saying so. This
; returned silently, which is the same key-that-does-nothing-and-says-nothing
; the seven screen dispatches used to have.
; ---------------------------------------------------------------------------
chan_incr_begin
                ; AND INC SET NEEDS A SELECTED FIELD, exactly as the arrows do
                ; and with the OTHER error number. Event $1E reaches the
                ; seventeen-arm table d62ec through the guard at $62D9 - CMPX
                ; #$0011 / $62DC BGT reject_event_error_20 ($62C3), $62E0 SUBD
                ; #$0001 / $62E3 BLT it - so $2215 = 0, which is what the
                ; screen carries when no field is selected, lands on
                ; error_report_beep ($C3FE) with $14, 'Not an incrementable
                ; field'. That is a different code from the arrows' 4, which
                ; is why the two refusals here are separate.
                ;
                ; AND IT IS THE FIELD ID THAT DECIDES, not $23A8, for the same
                ; reason the arrows' guard gives above: INC SET is key code
                ; $0D and arm [12] of dae3d is keymap_0d_to_msg_1e, which
                ; posts event $1E from inside key_to_state_code ($AD4D) before
                ; numeric_entry_key_handler ($B3C2) ever reaches lb494's
                ; $23A8 test. The guard the instrument applies is $62D9's, and
                ; $62D9 reads $2215.
                tst     >field_index
                beq     chan_incr_refused
                lbsr    chan_incr_address
                bcc     chan_incr_refused
                lda     #$01
                sta     >incr_mode
                ; THE ENTRY IS RESTARTED, as the stock's INCR SET arm restarts
                ; it: select_amptd_increment_field ($61E3) ends in
                ; arm_field_editor ($4ED8) through [$3B85] with selector 1,
                ; the same arm_numeric_entry_field ($AC35) restart an arrow
                ; makes (chan_step_field). Digits typed before the key are
                ; wiped and, entry_active being clear, ENTER with nothing
                ; typed takes chan_commit's entry_active test to
                ; chan_commit_choice, a redraw. This called chan_entry_begin
                ; with B still holding the key code, 13, as the width -
                ; clamped to ENTRY_MAX, so it showed nothing - and left
                ; entry_active standing over the emptied buffer, so that
                ; ENTER went on to ABI_entry_value. chan_entry_start loads
                ; the field's own width, as chan_digit_typed does.
                clr     >entry_active
                lbsr    chan_entry_start
                ; ONLY THE ARMED FIELD IS PAINTED. Each arm of $62EC calls its
                ; own field's increment painter - $61B5 show_freq_increment_
                ; field, $61E3 draw_amplitude_increment, $6211 paint_phase_
                ; increment - and nothing else, so whatever the other two
                ; fields show stays. This repainted all five, which put a
                ; value back over an increment a bus select had left standing
                ; (driven: IS; APA; IS; APC; IS; on ch C - the stock keeps
                ; 'PHASE   1.0', this firmware repainted 'PHASE   0.0').
                lda     >field_index
                cmpa    #CHAN_FIELD_FREQ
                bne     chan_incr_begin_ampl
                lbsr    chan_show_freq
                lbra    chan_field_arm
chan_incr_begin_ampl
                cmpa    #CHAN_FIELD_AMPL
                bne     chan_incr_begin_phase
                lbsr    chan_show_ampl
                lbra    chan_field_arm
chan_incr_begin_phase                           ; chan_incr_address admitted
                lbsr    chan_show_phase         ; only these three
                lbra    chan_field_arm
                ; AND THE CURSOR COMES ON OVER THE VALUE'S COLUMNS, where the
                ; increment now shows: that [$3B85] is JSR ,X at $61D6, $6204
                ; and $6232 in the three arms, with the selector of the VALUE
                ; field (0, 1, 2), so $23AD is the value position - which is
                ; why each arm above leaves through chan_field_arm.
chan_incr_refused
                ldb     #ERR_NOT_STEPPABLE
                lbra    ABI_error_record

; ---------------------------------------------------------------------------
; chan_incr_address - where the selected field's increment lives
;
;   exit:  X = its three bytes, carry SET if this field has one
;   uses:  A, X
;
; The channel field takes a typed number too, but it selects which channel the
; screen edits rather than holding a value, so it has no increment either.
; ---------------------------------------------------------------------------
chan_incr_address
                lda     >field_index
                cmpa    #CHAN_FIELD_FREQ
                bne     chan_incr_try_ampl
                pshs    b                       ; B IS KEPT, as uses: says -
                lbsr    chan_incr_freq_addr     ; this channel's, [$23BF]+5
                puls    b                       ; the address arms multiply
                orcc    #CC_CARRY               ; the channel in through it
                rts
chan_incr_try_ampl
                cmpa    #CHAN_FIELD_AMPL
                bne     chan_incr_try_phase
                pshs    b
                lbsr    chan_incr_ampl_addr     ; this channel's, not a shared
                puls    b
                orcc    #CC_CARRY
                rts
chan_incr_try_phase
                cmpa    #CHAN_FIELD_PHAS
                bne     chan_incr_none
                ldx     #incr_phase
                orcc    #CC_CARRY
                rts
chan_incr_none
                andcc   #~CC_CARRY
                rts

; ---------------------------------------------------------------------------
; chan_incr_shown - is INCR SET armed on a given field?
;
;   entry: A = a CHAN_FIELD_* id
;   exit:  carry SET when incr_mode is set and that field is the selected
;          one; every register unchanged
;   uses:  none
;
; The three painters ask this so the selected field shows its increment while
; the mode is armed and every other field shows its value: the stock's $2215
; is one of 6, 7 or 8 while an increment is armed, and each increment painter
; is reached only through the arm for its own id ($61B5, $61E3, $6211).
; ---------------------------------------------------------------------------
chan_incr_shown
                tst     >incr_mode
                beq     chan_incr_shown_no
                cmpa    >field_index
                bne     chan_incr_shown_no
                orcc    #CC_CARRY
                rts
chan_incr_shown_no
                andcc   #~CC_CARRY
                rts

; ---------------------------------------------------------------------------
; chan_step_field - move the selected field by its increment
;
;   entry: B = $01 to step up, $FF to step down
;   uses:  A, B, X, Y, U
;
; THE ARROWS, which did nothing on this screen at all. An operator could type
; a frequency but not nudge one, on an instrument whose front panel carries
; the arrows and an INCR SET key for exactly that.
;
; The value is widened to three bytes so one piece of arithmetic serves the
; two 24-bit fields and the 16-bit phase alike, moved, and then handed to the
; SAME SETTER a typed value goes to - so a stepped value meets every ceiling a
; typed one meets. The stock does this too: step_freq_value ($6683) re-checks
; the stepped result against $EA55 before storing, which is the check its
; ENTER path makes as well.
;
; Stepping below zero FLOORS at zero rather than wrapping. sub24 reports the
; borrow, and without that a single press of the down arrow on a zero field
; would set it to sixteen million.
;
; A PHASE LAST ENTERED IN RADIANS IS STEPPED IN RADIANS. step_channel_phase
; ($7378) switches on record+$19 at $743B: for 3 it adds record+$1B to
; record+$15 or subtracts it ($7383-$73DB), skipping the commit when the
; difference is negative (`CMPX #$0000 / LBLT l73dc` at $73C6); for 4 it does
; the same with record+$1D and record+$17 ($73DF-$7437, the below-zero skip
; at $7422), and commit_channel_phase ($66B2)'s radian arm then refuses
; above $EA5D and programs scale_by_0p5730 of the sum. That arithmetic is in
; milliradians and its result is what the screen shows, so the tenths path
; cannot stand in for it: 1001 plus 1001 milliradians is 2002, which rounds
; to 1147 tenths, where 574 plus 574 tenths is 1148. chan_step_phase_rad
; steps the twin and programs its rounded tenths, as the stock's commit does.
; ---------------------------------------------------------------------------
chan_step_field
                pshs    b                       ; the direction
                ; NO SELECTED FIELD, NO STEP. step_selected_field ($71A3)
                ; dispatches on the field id $2215 and its guard at $76EE is
                ; CMPX #$0012 / BGT reject_step_error_4 ($76D8), TFR X,D /
                ; SUBD #$0001 / BLT reject_step_error_4 - so id 0, the value
                ; the screen carries when nothing is selected, is refused
                ; before any arm runs. $2215 is set to 0 by
                ; enter_channel_config_mode ($528F) at $5440 and by
                ; dispatch_ui_event's arms l5d22, l5d33 and l5d4e (events $3C,
                ; $01 and $13-$16), each of which also calls end_field_edit
                ; ($5CE8); it is set to a field id by the d6044 field-select
                ; arms, which arm the entry in the same breath. field_index is
                ; this firmware's $2215 and it is what the guard reads.
                ;
                ; IT READ entry_armed - $23A8 - AND THAT IS A DIFFERENT CELL
                ; WITH A DIFFERENT LIFETIME. $23A8 gates the DIGITS, not the
                ; arrows: a key goes through numeric_entry_key_handler
                ; ($B3C2), which calls key_to_state_code ($AD4D) FIRST, at
                ; $B43D, and that dispatches the 52-arm table dae3d by key
                ; code minus one. Arm [18] is key19_state_20, arm [24] is
                ; arm_post_request_1f - the UP and DOWN arrows - and each
                ; posts its request through post_request_code ($8AD0) and
                ; returns 1, so $B441's LBEQ to lb464 is not taken and lb494's
                ; LDB >$23a8 / error 1 is never reached. The event is already
                ; posted; $23A8 only decides whether
                ; entry_exit_restore_display ($B38B) runs after it. So the
                ; instrument steps an arrow with $23A8 clear, and the two
                ; cells part company the moment the controller asserts REN:
                ; enter_remote_state ($9EB9) clears $23A8 and touches $2215
                ; nowhere.
                ;
                ; MEASURED ON BOTH, 2026-09-13, ch A: PHASE, 0, deg, then REN
                ; asserted - the stock and this firmware both read field 3
                ; with armed 00 - and then 'UP 1000 MV;'. The stock writes
                ; $0300 $020B $1000 to the synthesis port, its line 2 reads
                ; 'PHASE   1.0 deg' and channel 0's phase register holds 11;
                ; this firmware wrote nothing and stayed at 0.0 deg, because
                ; of this one test. A second 'UP;' takes the stock to 2.0 deg
                ; and register 23; 'DN;' back to 1.0 and 11. That is the
                ; differential harness's seed 23, step 36.
                ;
                ; The case the entry_armed test was standing in for is real
                ; and is still refused, by the right cell: after the
                ; controller RELEASES remote, request 1 reaches chan_key,
                ; which clears field_index exactly as l5d33 clears $2215, so
                ; the arrow that follows finds no selected field. Same
                ; session: PHASE, 0, deg, REN on, REN off, then a panel UP
                ; leaves both machines at 0.0 deg.
                tst     >field_index
                lbeq    chan_step_none
                lbsr    chan_incr_address
                lbcc    chan_step_none          ; long: the radian step now
                                                ; sits between here and it
                ; THE ARROW RESELECTS THE VALUE FIELD. Three arms of the
                ; stock's step table d7701 are its three increment fields,
                ; and each is two instructions long: step_freq_by_increment
                ; ($71D7) LDD #$0001 / STD >$2215, redirect_step_to_amptd
                ; ($7253) LDD #$0002 / STD >$2215 and
                ; step_phase_from_increment_field ($7372) LDD #$0003 / STD
                ; >$2215, each falling into the VALUE arm below it ($71DD,
                ; $7259, $7378). So an arrow while INCR SET is armed - $2215
                ; = 6, 7 or 8 - puts the value field's id back and steps the
                ; VALUE by its increment ($729E-$72B9 LDX >$23BF / LEAX 15,x
                ; / LDU >$23BF / LEAU 10,u ... LBSR $D392: record+15 onto
                ; record+10), repaints the VALUE ($7236 draw_channel_frequency,
                ; $7355 paint_channel_amptd, show_channel_phase_field $5854
                ; in the phase arm) and re-arms the value's entry through
                ; [$3B85] ($7240-$724C LDU #$0000 / LDY #$0002 / PSHS Y,U /
                ; LDX >$3B85 / JSR ,X for FREQ, $735F-$736B with LDU #$0001
                ; for AMPTD, LDU #$0002 in the phase arm) - arm_field_editor
                ; ($4ED8), whose AMPTD descriptor re-reads $2215 at $4F87
                ; LDX >$2215 / CMPX #$0007 and so lays the dc level's signed
                ; field out again. incr_mode is this screen's $2215 = 6, 7
                ; or 8, so it is cleared here, before the step, for all
                ; three fields at once. It used to survive the arrow, so the
                ; next number typed and entered landed in the increment
                ; where the stock's lands in the value. $71A3-$71D1 stores
                ; nothing to $3B84 and this screen draws no marker for $C885
                ; to erase, so there is nothing else to undo.
                ;
                ; AND RESTARTS THE ENTRY. [$3B85] ends in
                ; arm_numeric_entry_field ($AC35), which fills the buffer
                ; $239A with spaces ($ACC5-$ACE0) and zeroes the count $23A4
                ; ($ACF5 CLR >$23A4, or 1 behind a '+' for mode 2 at
                ; $ACE8-$ACEF): digits typed before the arrow are gone. They
                ; can be there, because the entry key handler ($B3C2) tries
                ; key_to_state_code ($AD4D) before the buffer and its $AE3D
                ; map posts keys 19 and 25 as the events $20 and $1F that
                ; dispatch_ui_event ($5D0C) hands to step_selected_field.
                ; Here the first digit after the arrow starts a fresh entry
                ; through chan_digit_typed's entry_active test.
                lbsr    chan_incr_end
                clr     >entry_active
                pshs    x                       ; the increment
                clr     >chan_step_sign         ; unsigned, unless the AMPL
                                                ; branch below finds a dc
                                                ; level

                lbsr    chan_record             ; the value out of the record
                lda     >field_index
                cmpa    #CHAN_FIELD_PHAS
                beq     chan_step_load_phase
                cmpa    #CHAN_FIELD_FREQ
                beq     chan_step_load_freq
                leau    CHAN_AMPL,x
                lbsr    chan_step_ampl_sign     ; a dc level: its sign, and
                                                ; the direction inverted for
                                                ; a negative one ($7287)
                bra     chan_step_copy
chan_step_load_freq
                leau    ,x                      ; CHAN_FREQ is zero
                bra     chan_step_copy
chan_step_load_phase
                ldy     #chan_phase_unit        ; B = the channel, from
                lda     b,y                     ; chan_record
                cmpa    #CHAN_UNIT_RAD
                lbeq    chan_step_phase_rad
                clr     >chan_step_work         ; a phase is sixteen bits
                ldd     CHAN_PHASE,x
                std     >chan_step_work+1
                bra     chan_step_move
chan_step_copy
                lda     ,u
                sta     >chan_step_work
                ldd     1,u
                std     >chan_step_work+1

chan_step_move
                ; X IS THE DESTINATION AND U THE OPERAND, which is the reverse
                ; of the order these arguments read in. add24's contract is
                ; "X = the value to add TO, U = the value to add", and having
                ; them the other way round added the working value into the
                ; INCREMENT - so the arrows appeared to do nothing, and the
                ; second press subtracted a corrupted increment and floored
                ; the field at zero. Caught by walking the front panel, not by
                ; reading the code.
                ldu     ,s                      ; the increment
                ldx     #chan_step_work         ; the value being moved
                lda     2,s                     ; the direction
                bmi     chan_step_subtract
                lbsr    ABI_add24               ; AND A STEP THAT WRAPS IS
                bcs     chan_step_overflow      ; NOT COMMITTED. add24 returns
                bra     chan_step_commit        ; the overflow in the carry
                                                ; (math.s), and the stock tests
                                                ; the same thing in B: $72B9
                                                ; LBSR $D392 / $72BE CMPB #$00 /
                                                ; $72C0 LBNE $72CE, which jumps
                                                ; OVER the commit at $72C9 and
                                                ; leaves the field standing.
                                                ; This committed the wrapped
                                                ; value: with a level at 1 V
                                                ; and INCR SET at 16 V - the
                                                ; increment is copied in with
                                                ; no range check of its own -
                                                ; one press of UP asked for
                                                ; more output and dropped the
                                                ; socket by volts, because
                                                ; ampl_in_range saw only the
                                                ; small wrapped number.
                                                ; The subtract arm below has
                                                ; always tested its carry.
chan_step_overflow
                leas    2,s                     ; drop the increment pointer,
                puls    b                       ; the channel, and repaint what
                lbra    chan_step_rearm         ; is still stored, and re-arm
chan_step_subtract
                lbsr    ABI_sub24               ; carry set: it went below
                bcc     chan_step_commit        ; zero
                tst     >chan_step_sign         ; A dc LEVEL CROSSES ZERO
                bne     chan_step_cross         ; ($7304); anything else
                clr     >chan_step_work         ; floors there
                clr     >chan_step_work+1
                clr     >chan_step_work+2

chan_step_commit
                leas    2,s                     ; drop the increment pointer
                lbsr    chan_record             ; X = the record
                ldb     >current_channel
                lda     >field_index
                cmpa    #CHAN_FIELD_FREQ
                bne     chan_step_try_ampl
                ldu     #chan_step_work
                lbsr    ABI_freq_set
                bra     chan_step_shown
chan_step_try_ampl
                cmpa    #CHAN_FIELD_AMPL
                bne     chan_step_try_phase
                ldu     #chan_step_work
                lda     >chan_step_sign         ; a dc level goes with its
                beq     chan_step_ampl_unsigned ; sign, which is what $72C9,
                lbsr    ABI_ampl_set_signed     ; $72FC and $7350 commit
                bra     chan_step_shown         ; through $241E
chan_step_ampl_unsigned
                lbsr    ABI_ampl_set            ; every other waveform, as
                bra     chan_step_shown         ; before
chan_step_try_phase
                ldy     >chan_step_work+1       ; a phase is sixteen bits
                lbsr    ABI_phase_set
chan_step_shown
                ; AND A REFUSED STEP SAYS SO. All four setters above return
                ; their verdict in the carry and record the code themselves -
                ; freq_set_refused stores ERR_FREQ_RANGE, phase_set_refused
                ; ERR_PHASE_RANGE, ampl_set_refused ERR_AMPL_RANGE - and this
                ; tail walked past every one of them into the repaint. So an
                ; arrow on a field whose stepped value clears 24 bits but
                ; exceeds the channel's own ceiling put the old number back
                ; with no beep and no message: the key looked unregistered.
                ; The ENTER path through this same setter does raise it
                ; (page0_channel_over reads last_error and calls
                ; ABI_error_raise), so the two ways into one routine disagreed.
                ; The stock's arrow arm ignores its callee's return for the
                ; same reason the ENTER path here does not have to: its
                ; apply_amplitude_entry ($6547) reports for itself at
                ; $65D2-$65DD through error_report_beep ($C3FE).
                bcc     chan_step_quiet
                ldb     >last_error
                lbsr    ABI_error_raise
chan_step_quiet
                puls    b
                lbra    chan_step_rearm

chan_step_cross
                ; BELOW ZERO ON A dc LEVEL: THE STEP CROSSES IT. The stock's
                ; $7304-$7312 test the waveform word again and abandon the
                ; step for anything but 4; for dc, $7313-$732F run sub24
                ; ($D3C6) the other way round - X = record+15, Y = record+10,
                ; increment minus level, which cannot borrow because the
                ; level was the smaller - and $7330-$734A set $241E from
                ; record+$14: '+' when it was '-' ($7338 CMPB #$2D / $733E
                ; LDB #$2B) and '-' otherwise ($7346 LDB #$2D), before
                ; apply_amplitude_entry stores both at $734B. Executed: up
                ; from -200 mV with a 600 mV increment paints '+  400 mV'.
                ; The result is the same three-byte magnitude and the
                ; opposite sign, and here it goes to ampl_set_signed as the
                ; stock's goes to $6547.
                ldu     ,s                      ; the increment, into the
                lda     ,u                      ; working value
                sta     >chan_step_work
                ldd     1,u
                std     >chan_step_work+1
                lbsr    chan_record             ; X = the record
                leau    CHAN_AMPL,x             ; U = the level
                ldx     #chan_step_work         ; X = the increment, minus it
                lbsr    ABI_sub24
                lda     >chan_step_sign
                cmpa    #CHAN_SIGN_MINUS        ; $7338 CMPB #$2D
                beq     chan_step_cross_plus
                lda     #CHAN_SIGN_MINUS        ; $7346 LDB #$2D
                bra     chan_step_cross_sign
chan_step_cross_plus
                lda     #CHAN_SIGN_PLUS         ; $733E LDB #$2B
chan_step_cross_sign
                sta     >chan_step_sign
                lbra    chan_step_commit

chan_step_phase_rad
                ; THE RADIAN STEP. On entry X is the record, B the channel,
                ; 0,s the increment pointer and 2,s the direction.
                pshs    b,x                     ; 0,s the channel, 1,s the
                                                ; record, 3,s the increment
                                                ; pointer, 5,s the direction
                lbsr    chan_incr_rad_get       ; D = the increment in mrad
                std     >chan_step_work+1
                ldb     ,s
                ldx     1,s
                lbsr    chan_phase_rad_get      ; D = the phase in mrad
                tst     5,s                     ; the direction
                bmi     chan_step_rad_down
                addd    >chan_step_work+1
                bcs     chan_step_rad_big
                cmpd    #CHAN_RAD_MAX           ; the radian arm's CMPX
                bhi     chan_step_rad_big       ; >$EA5D / LBLS at $66FA
                bra     chan_step_rad_apply
chan_step_rad_down
                subd    >chan_step_work+1
                bcs     chan_step_rad_unchanged ; below zero: nothing is
                                                ; stored and the field is
                                                ; repainted, which is the
                                                ; stock's LBLT at $7426 - a
                                                ; signed test, the same as
                                                ; the borrow for two values
                                                ; that are each at most 6282
chan_step_rad_apply
                std     >chan_step_work+1       ; the new milliradians
                lbsr    chan_rad_to_tenths      ; and the tenths the chip
                tfr     d,y                     ; takes, rounded as $D2A9
                ldb     ,s                      ; rounds
                ldx     1,s
                lbsr    ABI_phase_set
                bcs     chan_step_rad_unchanged ; unreachable past the
                                                ; ceiling, kept because the
                                                ; setter's contract says to
                                                ; test its carry
                ldb     ,s
                aslb
                ldx     #chan_phase_rad
                abx
                ldd     >chan_step_work+1       ; the twin, as stepped
                std     ,x
chan_step_rad_unchanged
                leas    5,s                     ; channel, record, increment
                puls    b                       ; pointer; then the direction
                lbra    chan_step_rearm
chan_step_rad_big
                leas    5,s
                puls    b
                lbsr    chan_commit_rad_too_big ; recorded and sounded where
                                                ; the stock's $6749 is silent,
                                                ; as the typed radian entry is
                lbra    chan_field_arm          ; - and re-armed, see below
; A STEP THAT WAS MADE RE-ARMS THE FIELD, whether or not the value moved.
; step_selected_field ($71A3) dispatches through d7701 on $2215, and each arm
; it reaches ends in [$3B85] on every path: step_channel_frequency ($71DD) at
; l7236, whose JSR ,X at $724C follows both the add and the subtract whatever
; $D3C6 answered; step_amptd_by_increment ($7259), all of whose paths join
; l7355 and its JSR ,X at $736B; step_channel_phase ($7378), whose p7420
; joins l744a and its JSR ,X at $7460. Arms [5] to [7] store the value's own
; id in $2215 and fall into those three. The arms that refuse -
; reject_step_error_4 for $2215 = 0, 4, 5 and 9-11 - reach no [$3B85], and
; neither does chan_step_none here.
chan_step_rearm
                lbsr    chan_values_show
                lbra    chan_field_arm
chan_step_none
                puls    b
                ; REFUSED, not ignored. The stock's 18-arm step dispatch at
                ; $7701 sends arms 3, 4, 8, 9, 10 and everything outside its
                ; range to reject_step_error_4, which is error_report_beep
                ; ($C3FE) with code 4 - so an arrow on the WAVE, DEST or
                ; channel field says it did nothing rather than looking like a
                ; dead key.
                ;
                ; AND CODE 4 IS THE ONE IT SENDS. This raised
                ; ERR_NOT_STEPPABLE, $14, which is reject_event_error_20
                ; ($62C3) - INC SET's refusal on the same fields, a different
                ; message from a different dispatcher. The arrows' arm is
                ; reject_step_error_4 ($76D8): LDB #$04 / SEX / TFR D,U / LDY
                ; #$0002 / PSHS Y,U / LBSR $C3FE. chan_incr_refused keeps $14,
                ; which is its own.
                ldb     #ERR_NO_STEP_FIELD
                lbra    ABI_error_raise

; ---------------------------------------------------------------------------
; chan_step_ampl_sign - the sign an AMPL step carries, and the direction it
;                       really moves in
;
;   entry: X = the channel record, B = the channel, and chan_step_field's
;          frame above the return address: 2,s the increment pointer, 4,s
;          the direction byte, +1 up or $FF down
;   exit:  chan_step_sign = the level's sign for a dc waveform, zero for
;          any other; 4,s negated when that sign is '-'
;   uses:  A, Y
;
; step_amptd_by_increment ($7259), instruction by instruction: $7259-$7263
; LDX >$23BF / LEAX <$14,x / LDB ,x / STB >$241E caches the record's sign
; character; $7264-$7272 LDX >$23BF / LEAX <$1F,x / LDX ,x / CMPX #$0004 /
; LBNE tests the waveform for dc, and $7273-$7280 LEAX <$14,x / LDB ,x /
; CMPB #$2D / LBNE the sign for '-'; only both together reach $7287 LDD
; >$000E,s / EORA #$00 / EORB #$01 / STD >$000E,s, which inverts the
; direction word in the caller's frame. So 'up' on a negative level moves
; it towards zero and 'down' away from it: executed, down on -2.00 V with
; a 600 mV increment paints '- 2.60  V' and up paints '- 2.00  V'. The
; stock caches the sign for every waveform and stores it back only for dc
; ($6603); here a non-dc step leaves chan_step_sign zero and commits
; through ampl_set, exactly as it did before this routine existed.
; ---------------------------------------------------------------------------
chan_step_ampl_sign
                lda     CHAN_WAVE,x
                cmpa    #LBL_DC                 ; $726C CMPX #$0004
                bne     chan_step_ampl_done
                ldy     #ampl_signs             ; record+$14, cached at $7261
                lda     b,y
                cmpa    #CHAN_SIGN_MINUS        ; $727B CMPB #$2D
                beq     chan_step_ampl_neg
                lda     #CHAN_SIGN_PLUS         ; anything else is positive,
                bra     chan_step_ampl_keep     ; as it is to $D4E7
chan_step_ampl_neg
                neg     4,s                     ; $7287-$7292: the direction
                                                ; inverted in the caller's
                                                ; frame; +1 and $FF negate
chan_step_ampl_keep
                sta     >chan_step_sign
chan_step_ampl_done
                rts

; chan_move_forward AND chan_move_back WERE HERE - NEXT and LAST, cycling a
; choice field when the cursor was on one and moving the cursor otherwise. Both
; halves were this firmware's own: the arrows are refused on a choice field
; (error 4) and NEXT and LAST page the chain. Nothing calls them.

; ---------------------------------------------------------------------------
; chan_field_is_choice - is the selected field a list rather than a number?
;
;   exit:  carry SET for the waveform and destination fields
;   uses:  A
; ---------------------------------------------------------------------------
chan_field_is_choice
                lda     >field_index
                cmpa    #CHAN_FIELD_WAVE
                beq     chan_field_is_choice_yes
                cmpa    #CHAN_FIELD_DEST
                beq     chan_field_is_choice_yes
                andcc   #~CC_CARRY
                rts
chan_field_is_choice_yes
                orcc    #CC_CARRY
                rts

; THE TWO COLUMNS OF keypad_char_table ($EF94) THAT MATTER HERE, as key-code
; and code pairs rather than as a sixteen-row table with six columns this
; firmware does not use. Read out of firmware/a2u12.bin at $EF94, one row of
; eight per key code, column 2 for the destination and column 3 for the
; waveform; docs/stock-choice-fields.md lists both in full.
;
; The waveform mapping is deliberately not monotonic - key 4 gives Sq, 5 Noise
; and 6 dc - because the panel's legend order is not the code order.
CHAN_WAVE_KEYS  equ     6
chan_wave_keys
                fcb     KEY_1,LBL_SINE
                fcb     KEY_2,LBL_RAMP
                fcb     KEY_3,LBL_TRIANGLE
                fcb     KEY_4,LBL_SQUARE
                fcb     KEY_5,LBL_NOISE
                fcb     KEY_6,LBL_DC

CHAN_DEST_KEYS  equ     10
; ---------------------------------------------------------------------------
; chan_dest_keys - the DESTN field's column of keypad_char_table ($EF94)
;
; Column 2 of the sixteen eight-byte records: a key code and the destination
; code it names. 1 to 4 are Out1 to Out4, 0 is Plse, 7 AM, 8 FM, 9 phi-M,
; minus DSB and point Off - and 5 and 6 hold 'X', which is why they change
; nothing. CHAN_DEST_KEYS is the count. Driven key by key against the stock in
; emulator/tests/test_choice_fields_new.py.
; ---------------------------------------------------------------------------
chan_dest_keys
                fcb     KEY_7,LBL_AM
                fcb     KEY_8,LBL_FM
                fcb     KEY_9,LBL_PHIM
                fcb     KEY_MINUS,LBL_DSB
                fcb     KEY_0,LBL_PULSE
                fcb     KEY_1,LBL_OUT1
                fcb     KEY_2,LBL_OUT2
                fcb     KEY_3,LBL_OUT3
                fcb     KEY_4,LBL_OUT4
                fcb     KEY_POINT,LBL_OFF

; ---------------------------------------------------------------------------
; chan_choice_key - a key pressed while a choice field is selected
;
;   entry: B = the key code
;   uses:  A, B, X, Y, U
;
; The field's column decides what the key means. Nothing in the column is
; error 2, as $B5D0 raises it.
; ---------------------------------------------------------------------------
chan_choice_key
                lda     >field_index
                cmpa    #CHAN_FIELD_WAVE
                bne     chan_choice_key_dest
                ldx     #chan_wave_keys
                lda     #CHAN_WAVE_KEYS
                bra     chan_choice_key_look
chan_choice_key_dest
                ldx     #chan_dest_keys
                lda     #CHAN_DEST_KEYS
chan_choice_key_look
                cmpb    ,x
                beq     chan_choice_key_found
                leax    2,x
                deca
                bne     chan_choice_key_look
                ldb     #ERR_KEY_ENTRY
                lbra    ABI_error_raise
chan_choice_key_found
                ; A TAKEN CHOICE ENDS THE ENTRY, IS COMMITTED AND RE-ARMS. The
                ; two choice fields arm with units class 0 (entry_cfg_wform and
                ; entry_setup_destn, CLRB / CLRA / STD 5,s), and for class 0
                ; check_entry_terminator ($B070) returns 1 on every character
                ; keypad_char_column_select accepts: $B571 LBSR, then
                ; entry_exit_restore_display ($B38B) with 0 at $B586 - the
                ; cursor OFF - and request $23 at $B594. Its arm is
                ; enter_wform_selection ($6ED7) or apply_destination_entry
                ; ($6F33), and both end in the re-arm through [$3B85], at
                ; $6F2C and $6F5D, whatever apply_waveform_choice refused. A
                ; key the column does not hold is not accepted, so there is no
                ; exit and no arm - the error below.
                ldb     1,x                     ; the code the column holds
                lbsr    ABI_entry_cursor_off    ; $B586
                lbsr    chan_choice_set         ; request $23's commit
                lbra    chan_field_arm          ; and its [$3B85]
; ===========================================================================
; THE BUS'S TWO CHECKS, and why they are entry vectors of this page
;
; A value set over HP-IB has to be refused by the SAME rule that refuses it
; from the keypad. On the instrument that is not a policy, it is the
; architecture: the bus mnemonics WFA-WFD, FRH and APH do not store anything
; at all - they post a request code that SELECTS a field
; (key_select_wform_field $5FC3, and $607E / $60A1 for the two hop fields),
; the number or mode code that follows goes into the panel's own entry buffer
; through gpib_number_to_entry_buffer ($A47E), and $A7FD then posts request
; $0023, the code the ENTER key posts. commit_entry_to_field ($6B84) does the
; rest, so apply_waveform_choice ($674C), apply_hop_frequency_entry ($4BFE)
; and store_hop_amptd ($4CD5) each run once, for both routes. Read out of the
; stock's own instruction stream on 2026-09-12.
;
; This firmware answers those commands in remote.s, which is resident, and the
; two validators live here on page 0 - so the bus path had NO check at all: a
; ramp at 600 kHz, or a hop slot above the 600 kHz ceiling, went straight into
; the record while the panel refused the same value with error $96 or $71.
;
; ARGUMENTS TRAVEL IN RAM, not in registers: page_call owns B and X for the
; page number and the vector and clobbers A inside page_select_and_verify.
; And the ANSWER travels in RAM too - rmt_check_result - because carry cannot
; distinguish "the check refused it" from "the page switch failed", and those
; are not the same event.
; ---------------------------------------------------------------------------
; page0_wave_check - may this channel take the waveform the bus named?
;
;   entry: rmt_mode_code = the label code, rmt_pend_chan = the channel
;   exit:  rmt_check_result = 0, or the error code the panel would raise
;   uses:  A, B, X, Y, U
; ---------------------------------------------------------------------------
page0_wave_check
                ldb     >rmt_pend_chan          ; THE RECORD, worked out here
                andb    #$03                    ; rather than through
                lda     #CHAN_RECORD            ; chan_record: that one reads
                mul                             ; current_channel, which is the
                ldx     #channel_records        ; SCREEN's channel, and the bus
                leax    d,x                     ; names its own. The mask is
                                                ; chan_record's, for the same
                                                ; reason - a wild channel
                                                ; number must not index outside
                                                ; the four records
                lda     >rmt_pend_chan          ; THE COMMANDED CHANNEL, not
                anda    #$03                    ; the screen's: the validator
                                                ; takes it in A now, for the
                                                ; reason written in its header
                ldb     >rmt_mode_code
                lbsr    chan_wave_allowed       ; carry set: B = the refusal
                bcs     page0_wave_refused
                clr     >rmt_check_result
                rts
page0_wave_refused
                stb     >rmt_check_result
                rts

; ---------------------------------------------------------------------------
; page0_hop_check - is the bus's hop value inside the panel's own ceiling?
;
;   entry: rmt_mode_code = the hop field (HOP_FIELD_FREQ or HOP_FIELD_AMPL),
;          the value in rmt_val, three bytes
;   exit:  rmt_check_result = 0, or the error code the panel would raise
;   uses:  A, B, X, Y, U
;
; THE FIELD IS SELECTED, not merely consulted, because that is what FRH and
; APH do on the instrument - $607E writes $2215 = $000C and $60A1 writes
; $000D, which is the same cell the panel's FREQ and AMPTD keys write. So the
; screen's cursor following a bus command is the instrument's behaviour and
; not a side effect of this check.
; ---------------------------------------------------------------------------
page0_destn_check
                ; THE DESTINATION OPTION, which the bus never tested. The
                ; panel's own commit calls chan_destn_allowed before it routes
                ; anything (chan_cycle_dest), and without Option FW the
                ; keypad answers ERR_OPTION_DESTN - while 'DEB FM;' over the
                ; bus routed a modulator on an instrument that does not have
                ; the option fitted.
                clr     >rmt_check_result
                lbsr    chan_destn_fitted
                bcc     page0_destn_done
                lda     #ERR_OPTION_DESTN
                sta     >rmt_check_result
page0_destn_done
                rts

page0_hop_check
                ; AND THE HOP OPTION, on the same footing. hop_open refuses to
                ; put the screen up at all without Option 003 (hop_available,
                ; ERR_NO_OPTION), so there is no keypad route to a hop slot on
                ; an instrument without it - and FRH and APH rewrote the table
                ; anyway.
                lbsr    hop_available
                bcc     page0_hop_option_ok
                lda     #ERR_NO_OPTION
                sta     >rmt_check_result
                rts
page0_hop_option_ok
                lda     >rmt_mode_code
                sta     >hop_field
                lda     #$01                    ; $607E and $60A1 write $2215,
                sta     >field_is_hop           ; so the field id is the hop
                                                ; cursor's from here
                ldx     #rmt_val
                lbsr    hop_value_in_range
                bcs     page0_hop_refused
                ; AND THE SLOT'S SIGN, which the bus could not write at all.
                ; A dc hop level carries its sign in hop_signs[slot] - the hop
                ; record's +10 byte - and dds.s reads it whenever amplitude
                ; hop is armed. The bus refuses a minus anywhere (remote.s
                ; rejects RF_MINUS, as the stock rejects the sign at
                ; validation with error $29), so a bus level is always
                ; positive; but a level KEYED as -5 V leaves '-' in that byte,
                ; and a later 'APH 5 VL' then played -5 V while the screen and
                ; the readback both said +5 V.
                ;
                ; hop_sign_store is the panel's own writer and it applies the
                ; panel's own rule - it stores nothing unless the AMPL field is
                ; selected and channel 0 is dc - so calling it here cannot
                ; touch a byte the keypad would have left alone.
                lda     #CHAN_SIGN_PLUS
                lbsr    hop_sign_store
                ; AND THE UNIT THE SCREEN WILL SHOW IT IN. hop_store_field
                ; copies hop_entry_unit into hop_freq_unit for the FREQ field,
                ; because the Hop RAM screen renders whichever slot is showing
                ; in the unit the operator last keyed - so a slot set to 100
                ; kHz over the bus was drawn in whatever unit the last KEYED
                ; entry had used. Both cells hold UNIT_* codes: hop_unit_lookup
                ; returns them from hop_class_units and remote_commit_units
                ; stores the same constants in rmt_unit.
                lda     >rmt_mode_code
                cmpa    #HOP_FIELD_FREQ
                bne     page0_hop_unit_done
                ldb     >rmt_unit
                stb     >hop_freq_unit
page0_hop_unit_done
                clr     >rmt_check_result
                rts
page0_hop_refused
                lbsr    hop_refusal_code        ; B = which refusal it was;
                bcc     page0_hop_silent        ; carry clear means the field
                stb     >rmt_check_result       ; refuses without a message
                rts
page0_hop_silent
                ; A REFUSAL THE PANEL MAKES SILENTLY IS STILL A REFUSAL HERE.
                ; hop_refusal_code answers carry clear for the PHASE field,
                ; whose screen refuses without a message - and this stored
                ; zero, which remote_page0_check reads as "the check passed",
                ; so the value would have been copied into the slot after
                ; hop_value_in_range had just rejected it. Unreachable today,
                ; because remote_set_hop diverts RK_HOPPHASE before the check;
                ; it would have become reachable the moment PHH was routed
                ; through this vector, and a latent trap that turns a refusal
                ; into an acceptance is not one to leave armed. The bus must
                ; say something to the controller, and ERR_RMT_VALUE is what
                ; remote_hop_phase's own bound answers.
                lda     #ERR_RMT_VALUE
                sta     >rmt_check_result
                rts


; ---------------------------------------------------------------------------
; chan_wave_allowed - may this channel carry this waveform?
;
;   entry: B = the waveform code, X = the channel record, A = its channel
;          NUMBER - which the caller must supply, because two of the checks
;          below are about the OTHER channels and need to know which one to
;          leave out
;   exit:  carry CLEAR if it may; carry SET and B = the error if it may not.
;          X and A are unchanged either way
;   uses:  B, Y, U
;
; apply_waveform_choice ($674C) validates before it writes, and none of that
; was here - a typed Square went into the record whatever the channel's
; frequency was, and the output then carried harmonics the filter does not
; reach. Its refusals, from the instruction stream:
;
;   Ramp, Triangle or Square with the frequency above $EA5F = $07A120, which
;   is 500,000 tenths = 50 kHz - error $96, or $71 when this is channel 0 and
;   frequency hop is armed, because then the offending frequency is a slot's
;   and not the field's
;
;   dc with a modulation destination - error $97; dc on channel 0 while a
;   channel is modulating it - $98; dc joining an output another dc already
;   sums into - $99, which is dc_destination_conflict ($7736) and is
;   destn_dc_shared here
;
; Sine and Noise have no edges and no ceiling of their own: freq_ceiling in
; frequency.s carries the same rule for the frequency field, tested there
; against the waveform instead of the other way round.
; ---------------------------------------------------------------------------
chan_wave_allowed
                pshs    a,x                     ; THE CHANNEL, IN A, AND THE
                                                ; RECORD. The channel used to
                                                ; be read out of
                                                ; current_channel at the two
                                                ; sites below, which is the
                                                ; SCREEN's channel: the same
                                                ; thing when the keypad commits
                                                ; a waveform and a different
                                                ; one when the BUS does, since
                                                ; page0_wave_check builds the
                                                ; record from rmt_pend_chan. So
                                                ; the dc-conflict walk left out
                                                ; the channel the screen
                                                ; happened to show and included
                                                ; the one being commanded: a dc
                                                ; into an output another channel
                                                ; already sums into was accepted
                                                ; over the bus, and re-sending
                                                ; dc to a channel that already
                                                ; had it was refused.
                                                ;
                                                ; AND THE RECORD, over two helpers
                                                ; that clobber it: destn_dc_shared
                                                ; declares X among what it uses,
                                                ; and with X gone the caller's
                                                ; `stb CHAN_WAVE,x` wrote the
                                                ; waveform into whatever the
                                                ; helper left there - the field
                                                ; simply did not change and no
                                                ; error was raised, which is how
                                                ; this was found
                cmpb    #LBL_DC
                beq     chan_wave_dc
                cmpb    #LBL_RAMP
                beq     chan_wave_edged
                cmpb    #LBL_TRIANGLE
                beq     chan_wave_edged
                cmpb    #LBL_SQUARE
                beq     chan_wave_edged
chan_wave_ok
                andcc   #~CC_CARRY              ; Sine and Noise take any
                puls    a,x,pc                    ; frequency this channel has

chan_wave_edged
                ; THE FREQUENCY IN THE RECORD against the edged ceiling, most
                ; significant byte first - a 24-bit compare, not a 16-bit one.
                lda     ,x                      ; CHAN_FREQ is offset zero,
                                                ; and the two assemblers encode
                                                ; a written zero offset
                                                ; differently - lwasm $84,
                                                ; asm6809 $00 - so it is
                                                ; written as the no-offset form
                                                ; every other site in this tree
                                                ; uses
                cmpa    #FREQ_EDGED_HI
                blo     chan_wave_ok
                bhi     chan_wave_too_fast
                lda     CHAN_FREQ+1,x
                cmpa    #FREQ_EDGED_MID
                blo     chan_wave_ok
                bhi     chan_wave_too_fast
                lda     CHAN_FREQ+2,x
                cmpa    #FREQ_EDGED_LO
                bls     chan_wave_ok            ; exactly 50 kHz is allowed
chan_wave_too_fast
                lda     ,s                      ; channel 0 with frequency hop
                bne     chan_wave_freq_error    ; switched on names the hop's
                tst     >hop_running            ; own error instead - the flag
                beq     chan_wave_freq_error    ; hop_switch_freq sets
                ldb     #ERR_HOP_WAVE_FREQ
                orcc    #CC_CARRY
                puls    a,x,pc
chan_wave_freq_error
                ldb     #ERR_WAVE_FREQ
                orcc    #CC_CARRY
                puls    a,x,pc

chan_wave_dc
                ldb     CHAN_DEST,x             ; a modulation input cannot
                lbsr    ABI_label_is_mod        ; carry dc
                bcc     chan_wave_dc_output
                ldb     #ERR_DC_DESTN
                orcc    #CC_CARRY
                puls    a,x,pc
chan_wave_dc_output
                ; AND NO SECOND dc INTO THE SAME OUTPUT. destn_dc_shared is
                ; dc_destination_conflict ($7736): it walks the other three
                ; records for one whose destination is this one and whose
                ; waveform is dc.
                ldb     CHAN_DEST,x
                cmpb    #LBL_OFF
                lbeq    chan_wave_ok            ; parked: nothing to clash with
                lda     ,s                      ; the CALLER's channel: the
                                                ; one to leave out of the walk
                lbsr    ABI_destn_dc_shared
                lbcc    chan_wave_ok
                ldb     #ERR_DC_SUM_DUP
                orcc    #CC_CARRY
                puls    a,x,pc

; ---------------------------------------------------------------------------
; chan_choice_set - put a typed code into the waveform or destination field
;
;   entry: B = the code, from the field's own key table
;   uses:  A, B, X, Y, U
;
; THE INSTRUMENT TYPES A CHOICE, it does not step one. entry_cfg_wform ($4FF8)
; and entry_setup_destn ($500E) arm entry MODES 5 and 4, which make
; keymap_column2_select and keychar_column_3 ($AF81 arms [4] and [5]) read the
; key through columns 2 and 3 of keypad_char_table ($EF94) and store the CODE
; in $221F rather than an ASCII digit; the units class is 0, so
; check_entry_terminator ($B070) returns 1 on that same key and the commit runs
; at once through enter_wform_selection ($6ED7) or apply_destination_entry
; ($6F33), which re-arm the field so the next digit takes as well.
;
; This routine took a DIRECTION and walked the list, because the arrows drove
; it. They do not: d7701's arms [3] and [4] are reject_step_error_4, so UP and
; DOWN on either field beep error 4, 'No incrementable field', and INC SET
; beeps error 20 through d62ec. docs/stock-choice-fields.md carries the whole
; reading, key by key.
; ---------------------------------------------------------------------------
chan_choice_set
                pshs    b                       ; the code
                lbsr    chan_record
                lda     >field_index
                cmpa    #CHAN_FIELD_WAVE
                bne     chan_cycle_dest

                ldb     ,s                      ; the waveform, as typed
                lda     >current_channel        ; and the SCREEN's channel,
                                                ; which is this caller's
                lbsr    chan_wave_allowed       ; and REFUSED if the channel
                bcc     chan_choice_wave_store  ; cannot carry it: B = the
                lbsr    ABI_error_raise         ; instrument's own code
                leas    1,s
                lbra    chan_show_wave          ; repaint what is still there
chan_choice_wave_store
                ldb     ,s
                stb     CHAN_WAVE,x
                ; AND PUT IT ON THE CHIP. The waveform was stored in the
                ; record and shown on the screen and written nowhere, because
                ; this tree said which register selects a waveform was not
                ; established. It is $1D for channels 0 and 1 and $1E for
                ; channels 2 and 3, three bits each, and the label code is
                ; not the chip code - see the table in dds.s.
                lda     >current_channel
                lbsr    ABI_wave_program
                lbsr    ABI_filter_apply        ; AND THE FILTER FOLLOWS THE
                                                ; WAVEFORM: the stock's
                                                ; waveform change runs $F7EC
                                                ; at $68B2, after
                                                ; unit_code_select_head
                                                ; ($E38F)
                leas    1,s                     ; the typed code

                ; AND THE LEVEL GOES BACK ON THE CHIP WITH IT, because the
                ; code a level is programmed as depends on the waveform.
                ; enter_wform_selection ($6ED7), the stock's one waveform
                ; commit, calls apply_waveform_choice ($674C) - the checks,
                ; the store into record+$1F, unit_code_select_head ($E38F)
                ; and the filter $F7EC - and then, at $6EE5, LDX >$23BF /
                ; LEAX 10,X / TFR X,U / LDB >$23BE / CLRA / TFR D,Y / LDX
                ; #$0004 / PSHS X,Y,U / LBSR $C069: dispatch_channel_function
                ; with the channel and the record's level at +10, which is
                ; ABI_ampl_reapply here. It re-derives the DDS code from the
                ; record as it now stands.
                ;
                ; A dc CODE IS NOT THE ac CODE FOR THE SAME LEVEL:
                ; ampl_raw's dc arm halves the code a second time and folds it
                ; through $0FFF ($D4A3-$D4FB). MEASURED on 2026-09-13, both
                ; firmwares side by side, a 140 uV channel taking 'WFB DC;':
                ; the stock's level register for that channel goes from 1879
                ; to 3156 and this firmware's stayed at 1879 - the socket kept
                ; producing the sine's amplitude while the screen said dc.
                lbsr    chan_record             ; X = the record, B = the
                lbsr    ABI_ampl_reapply        ; channel; no store, no check

                ; AND THE FOUR FIELDS THE CHANGE TOUCHES, in the stock's own
                ; order: $6EEE draw_channel_waveform ($59B3), $6EF7
                ; draw_channel_frequency ($54E6), $6F00 paint_channel_amptd
                ; ($57B1), $6F09 show_channel_phase_field ($5854). Only the
                ; waveform was repainted here, so the FREQ and PHASE fields
                ; kept their numbers when the channel went dc and the AMPTD
                ; field kept its blank sign column when it left dc.
                lbsr    chan_show_wave
                lbsr    chan_show_freq
                lbsr    chan_show_ampl
                lbra    chan_show_phase

chan_cycle_dest
                lbsr    chan_destn_allowed      ; THE OPTION TEST HERE TOO.
                bcs     chan_cycle_dest_refused ; The stock's fields are
                                                ; reached only through their
                                                ; keys, so key_destn's
                                                ; ($5FE6) test is the only
                                                ; gate a destination edit
                                                ; has to pass; this screen's
                                                ; NEXT and LAST also walk
                                                ; onto DEST, so the same
                                                ; test guards the edit
                                                ; itself. X, the record, is
                                                ; kept: the test uses A and B
                ldb     CHAN_DEST,x
                pshs    b                       ; THE OLD CODE, kept for the
                                                ; step below: destn_apply
                                                ; stores the new code into
                                                ; CHAN_DEST itself ($7DF0-
                                                ; $7E01), so after it the
                                                ; record no longer says where
                                                ; the channel came from.
                                                ; 0,s the old code, 1,s the
                                                ; typed code
                ldb     1,s                     ; and the typed code is what
                                                ; goes in. The codes a key can
                                                ; produce are $07 to $10 -
                                                ; is_modulation_destination
                                                ; ($77D9) names $07 to $0B and
                                                ; $0C-$0F are the outputs with
                                                ; $10 Off - so nothing outside
                                                ; that range can arrive here.
chan_cycle_dest_store
                ; THROUGH destn_apply, which is what refuses a destination
                ; the channel cannot have. This wrote CHAN_DEST directly, so
                ; the whole destination module - the refusal, the name lookup
                ; and the output test - was assembled into the ROM and never
                ; reached.
                pshs    b
                lda     ,s                      ; the code
                ldb     >current_channel
                exg     a,b                     ; A = channel, B = code
                lbsr    ABI_destn_apply
                puls    b
                bcs     chan_cycle_dest_kept
                pshs    b                       ; chan_record RETURNS B = THE
                lbsr    chan_record             ; CHANNEL, so calling it
                puls    b                       ; between the code and the
                stb     CHAN_DEST,x             ; store wrote the channel
                                                ; number - 0 to 3 - into the
                                                ; destination field instead of
                                                ; the 7-to-16 code. Its own
                                                ; header says so; the call was
                                                ; simply put in the wrong
                                                ; place.
                lbsr    ABI_filter_apply        ; AND THE FILTER FOLLOWS THE
                                                ; DESTINATION: the stock's
                                                ; destination change runs
                                                ; $F7EC at $7ED8, after its
                                                ; dispatch_channel_function
                                                ; ($C069) call, and at $7BD2
                                                ; for a destination refused
                                                ; and forced to Off
                                                ; AFTER THE STORE, twice
                                                ; over: filter_apply derives
                                                ; the line from the records,
                                                ; so the record must already
                                                ; hold the new code, and it
                                                ; destroys B - placed between
                                                ; `puls b` and `stb CHAN_DEST,x`
                                                ; it stored 4 in the record
                                                ; for a NEXT from Out1
                                                ; (traced on the emulator:
                                                ; the STB at $4585 wrote 4)
                ; THE PHASE OFFSET A MODULATOR CARRIES IS NOT RECOMPUTED
                ; HERE. It was, on the argument that "all four of the stock's
                ; `lbsr $e5bf` sites on a2u13_page0 are destination changes" -
                ; which is true and is not a reason to put the call in a key
                ; handler. Three of those four ($7EB8, $7F31, $7F6F) are
                ; INSIDE set_channel_destination ($78BF), which ABI_destn_apply
                ; above already runs through destn_tail, and the fourth
                ; ($650C) is inside commit_channel_frequency ($647B), which
                ; freq_set already runs. So this call was a second recompute
                ; the stock does not make, and it put a third write of
                ; register $10+n on the bus after destn_tail's two.
                ; emulator/tests/test_summing_new.py compares those words
                ; against the stock executing and caught it.

                ; --- THE AMPLITUDE STEP GOES WITH THE LEVEL. $7A45 LDX 2,s /
                ; CMPX #$0010 / LBEQ l7a8b tests the OLD code - 2,s is
                ; record+$21 loaded at $78C5-$78CD - and, for any old code
                ; but Off, $7A4E-$7A5D copy the $EA58 zero over the record's
                ; level (+10, which destn_route zeroes) and $7A62-$7A71 copy
                ; it over the record's amplitude step (+15, the word
                ; step_amptd_by_increment $7259 adds to +10). The stock keeps
                ; one step per channel; this firmware keeps one, incr_ampl
                ; (scratch.inc), and that one is the step this channel would
                ; move by next, so it is what the zeroing reaches. It is a
                ; raw 24-bit count that chan_ampl_incr_text renders in the
                ; channel's unit, so a volts-sized step carried into a
                ; channel that has just become AM would read as thousands of
                ; percent - which is what the stock's zeroing prevents.
                lda     ,s                      ; the old code
                cmpa    #LBL_OFF
                beq     chan_cycle_dest_kept    ; Off -> anything: l7a8b,
                lbsr    chan_incr_ampl_addr     ; THIS channel's step, and
                clr     ,x                      ; only this one: the stock
                clr     1,x                     ; zeroes record+15 for the
                clr     2,x                     ; record whose destination
                                                ; changed and no other
chan_cycle_dest_kept
                leas    1,s                     ; the old code
chan_cycle_dest_refused
                leas    1,s                     ; the typed code
                ; --- BOTH FIELDS ARE REPAINTED, as apply_destination_entry
                ; ($6F33) repaints them: $6F42 paint_channel_destn ($59E7),
                ; then $6F4C paint_channel_amptd ($57B1), whatever
                ; set_channel_destination did. The level shown must be the
                ; record's, and the record's level is what destn_route has
                ; just zeroed ($7A45) or, for channel 0 when a DSB modulator
                ; joins, what $7CE8-$7D03 zeroed and ampl_text now blanks
                ; under 'DSB'. Repainting DESTN alone left the old level on
                ; the glass until the next full repaint.
                lbsr    chan_show_dest
                lbra    chan_show_ampl
; ---------------------------------------------------------------------------
; chan_digit_typed - a digit key on a numeric field
;
;   entry: B = the digit, 0 to 9
;   uses:  A, B, X, Y, U
;
; Digits go into the shared entry buffer and are echoed into the field as
; they are typed, so the operator sees what they have keyed. NOTHING reaches
; the record or the hardware until ENTER.
;
; The first digit typed on a field STARTS a new entry rather than appending
; to whatever the last field left, which is why entry_active exists: without
; it, moving from FREQ to AMPL and typing 5 would give the frequency's digits
; with a 5 on the end.
;
; A digit on a choice field is ignored rather than refused. WAVE and DEST are
; stepped with NEXT and LAST and there is nothing sensible for 7 to mean on
; them; beeping would train the operator to ignore the beep.
; ---------------------------------------------------------------------------
chan_digit_typed
                pshs    b
                lbsr    chan_field_is_choice
                bcs     chan_digit_ignore       ; a list, not a number

                ; NOTHING ARMED, NOTHING TAKEN - AND THE ARMED TEST COMES
                ; FIRST. A digit opens or extends an entry only on a field a
                ; KEY has armed. After the controller has had the instrument
                ; the panel starts again with a field key, which is what the
                ; stock does - driven 2026-09-12, where this firmware opened a
                ; fresh entry on whatever field was last selected.
                ;
                ; entry_active was tested first, and it is this screen's own
                ; "digits have been typed into this field" flag - the stock's
                ; first-key flag $23A7. It is set by the first digit and
                ; cleared by chan_field_store, chan_commit and the screen
                ; opening; the controller taking the instrument clears
                ; entry_armed and entry_count in remote_poll_remote and cannot
                ; reach it, so a half-typed field left entry_active standing
                ; with no field armed and the NEXT digit appended to it.
                ; Driven 2026-09-13, PHASE armed and '4' typed, then one bus
                ; command and '2': the stock's line 2 stays 'PHASE   0.0 deg'
                ; and this firmware's read 'PHASE 2     deg'. Asking the armed
                ; flag first is the whole fix - an entry cannot legitimately be
                ; active on a field nothing has armed.
                ;
                ; AND THE FLAG ASKED IS $23A8 ITSELF, which this screen's six
                ; lb494 gates now read through entry_is_open. They read
                ; entry_armed, which is set by a field key and cleared only by
                ; the remote edge - but the instrument clears $23A8 at every
                ; exit ($B394), so after NEXT, LAST, an arrow on a choice
                ; field or any other mapped key that re-arms nothing it takes
                ; no digit and no units key, where this screen took both and
                ; committed into the field left behind. entry_is_open reads
                ; the cursor bit, which is written exactly where $23A8 is
                ; (entry.s), so what the screen accepts and what the glass
                ; shows cannot part company.
                lbsr    ABI_entry_is_open
                beq     chan_digit_unarmed
                tst     >entry_active
                bne     chan_digit_append
                lbsr    chan_entry_start        ; the first digit of a new
                lda     #$01                    ; entry: set the field up
                sta     >entry_active
chan_digit_append
                puls    b
                lbsr    ABI_entry_digit         ; carry set if the field is
                bcs     chan_digit_full         ; already full
                lbra    chan_entry_echo
chan_digit_unarmed
                puls    b                       ; the digit this arm pushed -
                ldb     #ERR_NO_ENTRY_FIELD     ; and lb494's error 1 through
                lbra    ABI_error_raise         ; error_report_beep ($B49D):
                                                ; nothing on the glass changes,
                                                ; but $23DE does. Seed 15 step
                                                ; 22, '5' on ch B with no field
                                                ; armed: 1 on the instrument,
                                                ; nothing recorded here

chan_digit_full
                ldb     #ERR_VALUE_TOO_BIG      ; the field holds no more:
                lbra    ABI_error_raise         ; say so rather than dropping
chan_digit_ignore                               ; the digit in silence
                puls    b
                rts

; ---------------------------------------------------------------------------
; chan_sign_key - MINUS: the AMPL entry of a dc channel goes negative
;
;   uses:  A, B, X, Y
;
; amptd_limit_volt_units ($4F6D), the V/mV/uV arm of
; entry_setup_channel_amptd ($4EFE), tests the record's waveform word +$1F
; against 4 at $4F7B-$4F86 and $2215 against 7 at $4F87-$4F90 and, for dc
; with the value field selected, arms entry mode 2 in place of mode 3
; ($4F97-$4FA3: LDB #$06 / STB 2,s, LDB #$1E / STB 3,s, LDD #$0002 / STD
; 7,s). Mode 2 is the one whose MINUS key is accepted: keypad_char_column_select
; ($AF29) sends mode 2 to arm_select_key_column_6 ($AF58), whose column of
; the $EF94 key table holds '-', and mode 3 to entry_key_column7_decimal
; ($AF5F), whose column holds 'X' for that row so the key is rejected at
; $AFD7 CMPB #$58. The accepted '-' lands at the head of the entry buffer
; whatever has been typed so far - $B02E LDB 2,s / CMPB #$2D, $B038 STB
; >$239A, $B03B LDB #$01 for the accepted-key return - and only a fresh
; field ($ACE8) or a backspace to empty ($B351) puts '+' back. Executed: on
; a Sine channel MINUS changes nothing on the glass or in the buffer; on a
; dc channel it paints 'AMPTD -'. So a Sine channel, an increment entry
; (mode 3, $4F94) and every other field refuse MINUS here exactly as they
; did, and only a dc channel's AMPL value takes it.
;
; A MINUS BEFORE ANY DIGIT OPENS THE ENTRY, as the stock's already-armed
; field takes it as its first accepted key and redraws. The sign then rides
; with the digits that follow and is committed with them by
; chan_commit_ampl; with no digits it commits nothing, which is also the
; stock's (chan_commit_ampl says where).
; ---------------------------------------------------------------------------
chan_sign_key
                pshs    b                       ; THE KEY, KEPT: chan_ampl_signed
                lbsr    chan_ampl_signed        ; carry set: a dc AMPL value.
                puls    b                       ; It reaches chan_record, which
                                                ; leaves the channel in B, and
                                                ; the refusal below hands B to
                                                ; key_refuse - on ch B that was
                                                ; 1, a mapped code, so the minus
                                                ; answered $0F where the
                                                ; instrument answers $02 (seed
                                                ; 1 step 18). PULS leaves the
                                                ; carry alone
                lbcc    chan_key_ignore         ; anything else: refused, as
                                                ; before
                lbsr    ABI_entry_is_open       ; and an unarmed field takes no
                lbeq    chan_key_ignore         ; key, as the digit path: the
                                                ; controller ending the edit
                                                ; leaves entry_active standing
                tst     >entry_active
                bne     chan_sign_key_set
                lbsr    chan_entry_start        ; a fresh field, '+' ($ACE8)
                lda     #$01
                sta     >entry_active
chan_sign_key_set
                lda     #CHAN_SIGN_MINUS        ; $B038: '-' at the head of
                sta     >chan_entry_sign        ; the buffer
                lbra    chan_entry_echo         ; and the field redrawn with it

; ---------------------------------------------------------------------------
; chan_backspace_key - BACKSPACE: the last character of the entry comes out
;
;   uses:  A, B, X, Y - B, X and Y through chan_entry_echo
;
; numeric_entry_key_handler ($B3C2) hands every key that is not a mode key
; or a field select to entry_backspace ($B2CD) at $B4B9, and $B2D7 CMPX
; #$001F makes BACKSPACE the one it acts on. What it does to the buffer
; $239A depends on the kind $23A9 ($B366-$B37E): kinds 0, 1 and 3 step the
; head $23A4 back one unless it is zero and blank the vacated cell
; ($B2E9-$B31F); kind 2, the signed layout amptd_limit_volt_units ($4F6D)
; arms for a dc level ($4F97-$4FA3), steps back only while a digit follows
; the sign ($B320 CMPB #$01 / LBLS) and otherwise puts '+' back at the head
; with the head at 1 ($B351-$B35A). The handler then repaints the whole
; buffer from the field's column with the cursor after its last character
; ($B4D0-$B501) - but only once a key has been accepted into it: $B4C4
; tests the first-key flag $23A7, which $B521 sets and $AC84 clears as a
; field is armed, and with it clear the handler leaves at $B4CD with nothing
; to show, the buffer it stepped being the one the arming had just filled
; with spaces ($ACC5-$ACE0) and, for kind 2, '+' ($ACE8).
;
; HERE. entry_active is that first-key flag (chan_digit_typed and
; chan_sign_key set it; chan_field_store, chan_commit and the screen's
; opening clear it): clear, the key does nothing, as $B4CD does nothing.
; Set, a dc level's entry with no digit left - only its sign, the stock's
; head at 1 - takes the kind-2 reset, '+' into chan_entry_sign; every other
; entry loses its last digit through ABI_entry_backspace, the stock's
; $B2E9-$B31F on this editor's buffer. Either way chan_entry_echo repaints
; the field and places the cursor, as $B4D0-$B501 does.
;
; ON THE TWO CHOICE FIELDS THE STOCK BEEPS. Their selects arm a zero-width
; entry of kind 5 (key_select_wform_field $5FC3 through entry_cfg_wform) or
; 4 (key_destn $5FE6 through entry_setup_destn $500E), kinds entry_backspace
; returns 0 for ($B35E), so the handler goes on to keypad_char_column_select
; ($AF29) - whose sixteen-row key table at $EF94 has no row whose first byte
; is $1F (the ROM's bytes, read: the sixteen first bytes are $0F, $0C, $12,
; $18, $0B, $11, $17, $0A, $10, $16, $1E, $1D, $1C, $1B, $09, $15), so
; lafbc ($AFBC: CMPB #$10 / CLR 7,s) returns 0 - and then accept_units_key
; ($B0C1), whose switch on the units class $23AB covers 2 to 7 while both
; fields arm class 0 (entry_cfg_wform and $500E both store zero into the
; class local), so it returns 0 too, and error_report_beep ($C3FE) gets
; code 2 at $B5D0-$B5DD. Refused here as every other key this screen
; cannot use is - ABI_key_refuse records ERR_KEY_UNUSABLE the way
; error_report_beep records its code.
; ---------------------------------------------------------------------------
chan_backspace_key
                lbsr    chan_field_is_choice    ; carry set: WAVE or DEST
                bcs     chan_backspace_refuse   ; $B5D0: the stock beeps
                lbsr    ABI_entry_is_open       ; AND THE FIELD HAS TO BE
                beq     chan_backspace_none     ; ARMED. $23A7 is cleared as a
                                                ; field is armed ($AC84) and
                                                ; set by the first key ($B521),
                                                ; so it cannot outlive the
                                                ; arming on the stock; here
                                                ; entry_active can, because the
                                                ; controller ending the edit
                                                ; clears entry_armed and not
                                                ; this screen's flag
                tst     >entry_active           ; $B4C4: no key accepted yet,
                beq     chan_backspace_none     ; nothing to take out or show
                lbsr    chan_ampl_signed        ; carry set: the kind-2 layout
                bcc     chan_backspace_digit
                tst     >entry_count            ; $B320-$B325: a digit after
                bne     chan_backspace_digit    ; the sign comes out; with
                lda     #CHAN_SIGN_PLUS         ; none left the sign goes
                sta     >chan_entry_sign        ; back to '+' ($B351-$B35A)
                lbra    chan_entry_echo         ; $B4D0-$B501: and the field
                                                ; repainted
chan_backspace_digit
                lbsr    ABI_entry_backspace     ; $B2E9-$B31F: the last digit
                lbra    chan_entry_echo         ; $B4D0-$B501
chan_backspace_refuse
                lbra    ABI_key_refuse
chan_backspace_none
                rts

; ---------------------------------------------------------------------------
; chan_ampl_signed - is the AMPL field in its signed entry layout?
;
;   exit:  carry SET when the selected field is AMPL, the channel's waveform
;          is dc and no increment entry is armed; clear otherwise
;   uses:  A, B, X
;
; The stock's test at $4F7B-$4F90: LDX >$23BF / LEAX <$1F,x / LDX ,x / CMPX
; #$0004 for the waveform, then LDX >$2215 / CMPX #$0007 for the increment
; field. $2215 = 7 is the AMPTD increment selected, which is what incr_mode
; records here; with it armed the field is the unsigned increment - $4F94
; leaves the mode-3 layout standing, and commit_amplitude_units_entry's
; $2215 = 7 path ($6CA9-$6CFA) stores through store_amplitude_increment
; ($690F), which is not among the page's $241E writers (those are $4CD5,
; $6547, $7259 and $7F4D, by symbol and by address).
; ---------------------------------------------------------------------------
chan_ampl_signed
                lda     >field_index
                cmpa    #CHAN_FIELD_AMPL
                bne     chan_ampl_unsigned
                tst     >incr_mode
                bne     chan_ampl_unsigned
                lbsr    chan_record             ; X = the record
                lda     CHAN_WAVE,x
                cmpa    #LBL_DC
                bne     chan_ampl_unsigned
                orcc    #CC_CARRY
                rts
chan_ampl_unsigned
                andcc   #~CC_CARRY
                rts

; ---------------------------------------------------------------------------
; chan_entry_start - set the entry buffer up for the selected field
;
;   uses:  A, B, X
;
; Each field has its own width, and the width is what stops an operator
; keying eight digits into a five-character phase field and wondering where
; they went.
; ---------------------------------------------------------------------------
chan_entry_start
                lda     >field_index
                cmpa    #CHAN_FIELD_CHAN
                bne     chan_entry_freq
                ldb     #CHAN_W_CHAN
                bra     chan_entry_begin
chan_entry_freq
                cmpa    #CHAN_FIELD_FREQ
                bne     chan_entry_ampl
                ldb     #CHAN_W_FREQ
                bra     chan_entry_begin
chan_entry_ampl
                cmpa    #CHAN_FIELD_AMPL
                bne     chan_entry_phase
                lda     #CHAN_SIGN_PLUS         ; A FRESH AMPL ENTRY IS
                sta     >chan_entry_sign        ; POSITIVE: mode 2 pre-places
                                                ; '+' at the head of $239A
                                                ; ($ACE8 LDB #$2B / $ACEA STB
                                                ; >$239A), so a value typed
                                                ; with no MINUS commits as '+'
                ldb     #CHAN_W_AMPL
                bra     chan_entry_begin
chan_entry_phase
                ldb     #CHAN_W_PHASE
chan_entry_begin
                lda     #ENTRY_DECIMAL
                lbsr    ABI_entry_begin

                ; AND WHERE THIS FIELD'S UNITS ARE, so the first key typed
                ; blanks them. The three arms of $5115 that arm this screen put
                ; the units column in argument 5 - entry_cfg_freq ($4EE5) $14,
                ; entry_setup_channel_amptd ($4EFE) $25, arm_phase_editor
                ; ($4FF0) $4C, which are CHAN_U_FREQ, CHAN_U_AMPL and
                ; CHAN_U_PHASE here - and the width follows the units class:
                ; class 6 for the frequency and class 3 for the phase are three
                ; characters, and the AMPTD field's class is chosen from the
                ; unit it is showing through the sub-table at $4FBE, so its
                ; width comes from that unit.
                lda     >field_index
                cmpa    #CHAN_FIELD_FREQ
                beq     chan_entry_units_freq
                cmpa    #CHAN_FIELD_AMPL
                beq     chan_entry_units_ampl
                cmpa    #CHAN_FIELD_PHAS
                beq     chan_entry_units_phase
                rts                             ; the channel selector is class
                                                ; 2 and has no units field;
                                                ; entry_begin's own zero covers
                                                ; it
chan_entry_units_phase
                lda     #CHAN_U_PHASE
                ldb     #UNIT_LABEL_LEN
                lbra    ABI_entry_units
chan_entry_units_freq
                lda     #CHAN_U_FREQ
                ldb     #UNIT_LABEL_LEN
                lbra    ABI_entry_units
chan_entry_units_ampl
                ldb     >chan_ampl_unit
                lbsr    ABI_unit_blank
                lda     #CHAN_U_AMPL
                lbra    ABI_entry_units

; ---------------------------------------------------------------------------
; chan_entry_echo - show what has been typed so far, in the field
;
;   uses:  A, B, X, Y
;
; THE STOCK'S LAYOUT. numeric_entry_key_handler ($B3C2) echoes every accepted
; key by writing the whole buffer $239A to the glass - lcd_write_string_at
; ($D8A5) with the buffer, its width $23A5 and the field's column $23AD
; ($B53D-$B555) - and then puts the cursor after the last character,
; lcd_set_cursor ($D7A0) of $23AD plus the head $23A4 ($B556-$B56B). The
; buffer was filled with spaces as the field was armed ($ACC5-$ACE0), so the
; glass shows the digits from the field's column and blanks to the width -
; left-aligned - and in the kind-2 layout the sign at the head ('+' from
; $ACE8, '-' from $B038) with the digits after it: executed, 'AMPTD -1'
; while typing, the field being armed six wide from $1E for a dc level
; ($4F97-$4FA3) against five from $1F otherwise.
;
; This rendered the digits right-aligned in the field and put the sign in
; the cell before the first digit by scanning for it. Now the field's cells
; are blanked, ABI_entry_render puts the digits from the first cell with
; blanks after them, and a dc level's sign takes the first cell with the
; digits from the second - the stock's arrangement, inside the field's nine
; columns (CHAN_NUMERIC: eight digits and one more, which the sign uses).
; The value that was there before is overwritten as the first key arrives -
; the operator is replacing it, and showing the old one alongside the new
; digits would read as one long number. The cursor is placed last, at the
; field's column plus the count, one further on when the sign is there,
; because the stock's head counts it.
;
; BLANK THE FIELD FIRST. entry_render writes entry_width characters, and
; entry_begin clamps that to ENTRY_MAX = 8, while chan_field_geometry
; returns the field's declared width of 9 - so lcd_write sent one character
; more than had been rendered. The ninth was chan_text+8, left there by the
; last format_places, which fills all nine. While a value was typed the
; field showed eight digits followed by one stale character of the value it
; used to show.
; ---------------------------------------------------------------------------
chan_entry_echo
                lbsr    chan_field_geometry     ; A = position, B = width
                pshs    a,b
                ldx     #chan_text
                lda     #' '
chan_entry_echo_pad
                sta     ,x+
                decb
                bne     chan_entry_echo_pad

                lbsr    chan_ampl_signed        ; carry set: a dc AMPL value
                ldx     #chan_text              ; the field's first cell (LDX
                bcc     chan_entry_echo_plain   ; leaves the carry)
                lda     >chan_entry_sign        ; $ACE8 / $B038: the sign at
                sta     ,x+                     ; the head, the digits after
chan_entry_echo_plain
                lbsr    ABI_entry_render        ; $B53D-$B555: the digits from
                                                ; the head, blanks to the
                                                ; width
                puls    a,b
                pshs    a                       ; the column, for the cursor
                ldx     #chan_text
                lbsr    ABI_lcd_write_raw       ; the echo: glass only, as
                                                ; lcd_write_string_at ($D8A5)
                puls    a
                adda    >entry_count            ; $B556-$B56B: the column plus
                pshs    a                       ; the head...
                lbsr    chan_ampl_signed        ; ...which counts the sign
                puls    a                       ; (PULS leaves the carry)
                bcc     chan_entry_cursor
                inca
chan_entry_cursor
                lbra    ABI_lcd_cursor

; ---------------------------------------------------------------------------
; chan_field_geometry - where the selected field is and how wide
;
;   exit:  A = the DDRAM position, B = the width
;   uses:  A, B, X
; ---------------------------------------------------------------------------
chan_field_widths
                fcb     CHAN_W_CHAN
                fcb     CHAN_W_FREQ
                fcb     CHAN_W_AMPL
                fcb     CHAN_W_PHASE
                fcb     CHAN_W_WAVE
                fcb     CHAN_W_DEST

chan_field_geometry
                ldb     >field_index
                cmpb    #CHAN_FIELDS
                blo     chan_field_geometry_ok
                clrb
chan_field_geometry_ok
                ldx     #chan_field_positions
                lda     b,x                     ; A = the DDRAM position
                ldx     #chan_field_widths
                ldb     b,x                     ; B = the width
                rts

; ---------------------------------------------------------------------------
; chan_commit - ENTER: apply what was typed to the selected field
;
;   uses:  A, B, X, Y, U
;
; The three numeric fields go through the setter that owns them - freq_set,
; ampl_set, phase_set - and each of those validates, stores and applies, in
; that order, refusing without changing anything. So a value out of range
; leaves the record and the hardware exactly as they were and the screen
; redraws what is actually set, which is the only honest thing to show.
;
; ENTER on a field with nothing typed REDRAWS it rather than committing a
; blank. Pressing ENTER twice is not a request to set the frequency to zero.
;
; ENTER on a choice field applies the code the operator stepped to. Those are
; not typed, so there is nothing to validate beyond what the cycling already
; guarantees.
;
; ON THE PHASE FIELD THIS IS REACHED BY THE deg KEY, NOT BY ENTER. chan_key
; sends ENTER on PHASE to chan_commit_phase_rad, because in the stock's
; unit_key_class3 ($B0F3) key $1B closes a class-3 entry as radians and $1C
; as degrees. The digits are therefore tenths of a degree when they arrive
; here, which is the unit chan_commit_phase and the increment slot take.
; ---------------------------------------------------------------------------
chan_commit
                tst     >entry_active
                beq     chan_commit_choice      ; nothing typed
                ; EMPTIED BY BACKSPACE, NOTHING IS STORED. The stock's three
                ; numeric arms convert the buffer with entry_to_scaled_digits
                ; ($CDE1), which returns $FF when there are no digits, and
                ; each skips its store on that count: enter_freq_value
                ; ($6BA5) CMPB #$08 / LBCC l6bf0, commit_amplitude_units_entry
                ; at $6D19 CMPB 3,s / LBCC l6d5f, commit_phase_entry ($6E51)
                ; CMPB #$05 / LBCC l6eb1 - and each tail puts the value's id
                ; back in $2215, repaints and re-arms, which is
                ; chan_commit_choice. Before chan_backspace_key existed the
                ; only way here with nothing typed was MINUS on a dc level,
                ; which chan_commit_ampl covers; a FREQ or PHASE entry
                ; backspaced to nothing would have committed zero.
                tst     >entry_count
                beq     chan_commit_choice

                lbsr    ABI_entry_value         ; carry set if it overflows
                lbcs    chan_commit_refused     ; twenty-four bits

                ; INCR SET DIVERTS THE SAME ENTRY. The operator typed a number
                ; and pressed ENTER exactly as for a value; only where it
                ; lands differs, and the mode is one-shot so the next ENTER is
                ; a value again.
                tst     >incr_mode
                beq     chan_commit_value
                lbsr    chan_incr_end
                ; AND AN INCREMENT IS SCALED BY ITS UNIT KEY TOO. The stock's
                ; INCR SET arms the SAME-SHAPED entry field - d62ec's arms
                ; ($61AF, $61DD, $620B) re-arm through [$3B85] with the value
                ; field's own class - and d717a sends both the value and the
                ; increment to the same commit routine, $6BA5 for arms 1 and 6
                ; alike. So an increment is entered in the same units as the
                ; value it steps, and 5 with the Hz key is fifty counts.
                lbsr    chan_entry_scale_incr   ; the unit to +8, not +3
                lbcs    chan_commit_refused
                lbsr    chan_incr_address       ; X = this field's increment
                bcc     chan_commit_choice
                ; A PHASE INCREMENT HAS THE STOCK'S CEILING. set_phase_increment
                ; ($697B)'s degree arm is `LDX >$221A / CMPX >$EA5B / LBLS
                ; l6994 / LBRA l69fc` at $6987-$6991: above 3599 nothing is
                ; stored. The slot took any twenty-four bits here, and
                ; chan_incr_rad_get needs the tenths to fit the conversion
                ; that keeps record+$1D's twin. Refused out loud, as the
                ; radian increment already is in chan_commit_phase_rad.
                lda     >field_index
                cmpa    #CHAN_FIELD_PHAS
                bne     chan_commit_incr_store
                lda     >entry_result
                lbne    chan_commit_rad_too_big
                ldd     >entry_result+1
                cmpd    #CHAN_DEG_MAX
                lbhi    chan_commit_rad_too_big
chan_commit_incr_store
                ldu     #entry_result
                lbsr    ABI_copy24              ; from the entry into it
                clr     >entry_active
                lbra    chan_values_show
chan_commit_value

                lda     >field_index
                cmpa    #CHAN_FIELD_CHAN
                beq     chan_commit_channel
                cmpa    #CHAN_FIELD_FREQ
                lbeq    chan_commit_freq
                cmpa    #CHAN_FIELD_AMPL
                lbeq    chan_commit_ampl
                cmpa    #CHAN_FIELD_PHAS
                lbeq    chan_commit_phase
chan_commit_choice
                clr     >entry_active
                lbsr    chan_incr_end              ; ENTER with nothing typed on
                                                ; an increment field puts the
                                                ; value back: l6c11 ($6C11),
                                                ; l6cfa ($6CFA) and l6eb1
                                                ; ($6EB1) store the value's id
                                                ; in $2215 whatever the digit
                                                ; count was - chan_incr_begin
                                                ; says how each is reached
                lbra    chan_values_show

; --- the channel field: choose which channel this screen edits -------------
chan_commit_channel
                ldb     >entry_result+2
                decb                            ; the panel counts from one
                lbsr    ABI_channel_select      ; validates AND selects, in
                bcs     chan_commit_absent      ; one place. This tested with
                                                ; channel_valid and then
                                                ; stored current_channel
                                                ; itself, so the routine that
                                                ; does both was dead and the
                                                ; check could drift from the
                                                ; store.
                clr     >entry_active
                lbra    chan_screen_paint       ; every field belongs to the
                                                ; new channel now
chan_commit_absent
                ldb     #ERR_NO_SUCH_CHANNEL
                lbsr    ABI_error_raise
                clr     >entry_active
                lbra    chan_show_channel

; ---------------------------------------------------------------------------
; chan_entry_scale - apply the unit key's meaning to the digits just typed
;
;   exit:  carry SET, and last_error written, if the scaled value will not fit
;          or the unit has no decade; carry CLEAR otherwise
;   uses:  A, B, X, Y, U
;
; ABI_unit_apply is units.s's unit_apply: it indexes
; unit_decades with the code and multiplies by ten that many times, refusing on
; overflow. The code was put in chan_entry_unit by the key arm, which is the
; stock's $2221.
;
; A ZERO CODE MEANS NO UNIT KEY WAS PRESSED - the Ch field, or a choice field -
; and those must not be scaled. UNIT_BLANK is
; zero and unit_decades refuses it, so the test has to come first rather than
; being left to unit_apply.
;
; chan_entry_scale_incr IS THE SAME FOR AN INCREMENT, and differs only in where
; a frequency's unit key goes: enter_freq_value ($6BA5) takes both, and after
; the store puts [$2221] into record+8 when $2215 is 6 - the increment - and
; into record+3 otherwise (l6bf0-l6c07). Storing an increment's kHz into +3
; changed how the VALUE was shown.
; ---------------------------------------------------------------------------
chan_entry_scale
                ldu     #chan_freq_unit         ; the value's unit, +3
                bra     chan_entry_scale_go
chan_entry_scale_incr
                ldu     #incr_freq_unit         ; the increment's unit, +8
chan_entry_scale_go
                lda     >chan_entry_unit
                beq     chan_entry_scale_none

                ; AND WHICH UNIT A FREQUENCY WAS KEYED IN IS KEPT, per
                ; channel, because the stock's screen shows it back in that
                ; unit: draw_channel_frequency ($54E6) reads the record's own
                ; code at +3 and picks the layout from it, so 25000 Hz and
                ; 25 kHz are the same frequency and two different displays.
                ldb     >field_index
                cmpb    #CHAN_FIELD_AMPL
                beq     chan_entry_scale_ampl
                cmpb    #CHAN_FIELD_FREQ
                bne     chan_entry_scale_apply
                tfr     u,x                     ; +3 or +8, as entered
                ldb     >current_channel
                andb    #$03
                abx
                sta     ,x
                bra     chan_entry_scale_apply

chan_entry_scale_ampl
                ; AND WHICH UNIT A LEVEL WAS KEYED IN, for the same reason:
                ; the stock writes $2221 into the record's +13 and
                ; render_value_with_units ($564E) picks the layout from it, so
                ; a phase deviation keyed in radians comes back in radians.
                ; Every other unit this field takes is the destination's own,
                ; and storing the code here is what makes the next unit key
                ; replace it.
                ldx     #chan_ampl_keyed
                ldb     >current_channel
                andb    #$03
                abx
                sta     ,x
                cmpa    #UNIT_RAD
                bne     chan_entry_scale_apply

                ; THE TWIN IS THE ENTRY ITSELF, in milliradians, kept before
                ; unit_apply converts it to the tenths of a degree the record
                ; holds - the stock stores the keyed number and its unit and
                ; reconverts nothing, which is why 3 comes back as '3.000'
                ; and not as 2.999.
                lda     >entry_result           ; a copy, so the scaling below
                sta     >chan_work              ; leaves the entry alone for
                ldd     >entry_result+1         ; unit_apply
                std     >chan_work+1
                ldb     #RAD_DECADES
                ldx     #chan_work
                lbsr    ABI_unit_scale_decades
                bcs     chan_entry_scale_apply  ; too wide to be a deviation:
                                                ; unit_apply refuses it below
                ldb     >current_channel
                andb    #$03
                aslb                            ; a word each
                ldx     #chan_ampl_rad
                abx
                ldd     >chan_work+1
                std     ,x
chan_entry_scale_apply
                ldb     >chan_entry_unit
                ldx     #entry_result
                lbsr    ABI_unit_apply
                bcs     chan_entry_scale_bad
chan_entry_scale_none
                clr     >chan_entry_unit        ; one entry, one unit
                andcc   #~CC_CARRY
                rts
chan_entry_scale_bad
                clr     >chan_entry_unit
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; chan_field_class_get - the units class of the field being edited
;
;   exit:  A = the CHAN_CLASS_* of field_index
;   uses:  A, B, X, Y, U
;
; The stock keeps this in $23AB, written once when the field is armed by
; arm_numeric_entry_field ($AC35) at $AC46. This firmware selects fields with a
; cursor rather than by arming a fresh entry each time, so the class is looked
; up from the field id instead of being stored - the same answer, one cell
; fewer, and no way for the stored copy to disagree with the field.
; ---------------------------------------------------------------------------
chan_field_class_get
                lda     >field_index
                cmpa    #CHAN_FIELDS            ; a field id out of range would
                bhs     chan_field_class_none   ; otherwise index past the table
                cmpa    #CHAN_FIELD_AMPL        ; the level's class is not fixed
                beq     chan_field_class_ampl
                ldx     #chan_field_class
                lda     a,x
                rts
chan_field_class_none
                lda     #CHAN_CLASS_NONE
                rts

; THE LEVEL FIELD'S CLASS FOLLOWS THE DESTINATION, which is what $4FBE does on
; the stock. There the selector is the record's stored amplitude unit at
; [$23BF]+13 and the fifteen-word table swings the class to 6 for an FM
; deviation, 3 for a phase deviation, 7 for an AM depth and 4 for a level in
; volts. This firmware keeps no stored unit byte - the record is twelve bytes
; and adding a thirteenth would change every saved register - but it does not
; need one: ampl_unit_for_destn already answers the same question from the
; destination code, returning UNIT_HZ for FM, UNIT_DEG for PhiM, UNIT_PERCENT
; for AM and UNIT_VOLT otherwise. The class is that answer, mapped.
;
; So the unit keys on the AMPTD field change meaning with the destination,
; exactly as they do on the instrument: kHz is volts on an output channel and
; kilohertz of deviation on one modulating another channel's frequency.
chan_field_class_ampl
                lbsr    chan_record             ; X = the record
                ldb     CHAN_DEST,x
                lbsr    ABI_ampl_unit_for_destn ; A = the unit the field carries
                cmpa    #UNIT_HZ
                beq     chan_field_class_freq
                cmpa    #UNIT_DEG
                beq     chan_field_class_phase
                cmpa    #UNIT_PERCENT
                beq     chan_field_class_pct
                lda     #CHAN_CLASS_VOLTS       ; a level, and the blank codes
                rts                             ; UNIT_PULSE and UNIT_OFF, which
                                                ; have nothing to type anyway
chan_field_class_freq
                lda     #CHAN_CLASS_FREQ
                rts
chan_field_class_phase
                lda     #CHAN_CLASS_PHASE
                rts
chan_field_class_pct
                lda     #CHAN_CLASS_PCT
                rts

; ---------------------------------------------------------------------------
; chan_key_unit_lookup - what a unit key means on the field being edited
;
;   entry: B = 0 for deg, 1 for Hz, 2 for kHz - the column of chan_class_units
;   exit:  carry CLEAR and B = the UNIT_* code; carry SET if this class
;          refuses that key, B undefined
;   uses:  A, B, X
;
; chan_class_units is $B212 transposed: the stock reaches one arm per class and
; the arm compares the key, this reaches one row per class and indexes it by the
; key. Same table, same answers, and a refusal here is the arm returning zero -
; which is what sends the stock to error_report_beep(2) at $B5D0.
; ---------------------------------------------------------------------------
chan_key_unit_lookup
                pshs    b                       ; the column
                lbsr    chan_field_class_get    ; A = the class
                ldb     #CHAN_CLASS_KEYS
                mul                             ; D = class * 3
                addb    ,s+
                adca    #0
                ldx     #chan_class_units
                leax    d,x
                ldb     ,x
                cmpb    #CHAN_UNIT_NONE
                beq     chan_key_unit_refused
                andcc   #~CC_CARRY
                rts
chan_key_unit_refused
                orcc    #CC_CARRY
                rts

; --- the three numeric fields ---------------------------------------------
chan_commit_freq
                ; THE TYPED DIGITS ARE IN THE UNIT THE KEY NAMED, not in the
                ; instrument's internal 0.1 Hz. entry_to_scaled_digits ($CDE1)
                ; does this on the stock by choosing a decade offset from the
                ; table at $CF9A - kHz lands the units digit three places
                ; higher than Hz - and unit_decades in units.s is that table
                ; with the offsets already subtracted: kHz 4, Hz 1. So 100 with
                ; the Hz key is 1000 counts and with the kHz key 1000000.
                ;
                ; This field used to take the raw 0.1 Hz count on ENTER, so a
                ; typed 100 meant 10.0 Hz and there was no way to say kHz at all.
                lbsr    chan_entry_scale
                lbcs    chan_commit_refused
                lbsr    chan_record
                ldu     #entry_result
                lbsr    ABI_freq_set
                lbcs    chan_commit_refused     ; long: chan_commit_phase_rad
                                                ; sits between here and it
                lbsr    ABI_filter_apply        ; THE FILTER FOLLOWS THE
                                                ; FREQUENCY: the stock's
                                                ; frequency commit runs
                                                ; recompute_channel_byte_24ec
                                                ; ($F7EC) at $6514, after
                                                ; write_channel_reg_08
                                                ; ($E2C1), with the record's
                                                ; destination
                clr     >entry_active
                lbra    chan_show_freq

chan_commit_ampl
                ; A SIGN WITH NO DIGITS REDRAWS. The only way to ENTER here
                ; with nothing typed is MINUS on a dc level, which opens the
                ; entry (chan_sign_key). The stock's terminator on an empty
                ; dc field stores nothing: executed, AMPL / MINUS / V on a
                ; -1.000 V channel leaves record+10 and +$14 as they were and
                ; writes no DDS word, and AMPL / V alone does the same. That
                ; is commit_amplitude_units_entry's $6D19 CMPB 3,s / LBCC
                ; l6d5f skipping apply_amplitude_entry on the count
                ; entry_to_scaled_digits ($CDE1) returns for an empty
                ; buffer, and chan_commit_choice is the repaint at l6db7.
                tst     >entry_count
                lbeq    chan_commit_choice
                ; AND THE SAME FOR THE LEVEL, whose class is 4: the deg key is
                ; microvolts, Hz is millivolts and kHz is volts ($B127). The
                ; decades are 0, 3 and 6 - unit_decades again - so a typed 1
                ; with the kHz key is 1000000 uV, which is the 10 V ceiling's
                ; own units. This field used to take raw microvolts on ENTER.
                lbsr    chan_entry_scale
                lbcs    chan_commit_refused
                lbsr    chan_record             ; X = the record, B = channel
                ldu     #entry_result
                lda     CHAN_WAVE,x             ; $65FB-$6609: only a dc
                cmpa    #LBL_DC                 ; level has a sign to store
                bne     chan_commit_ampl_plain
                lda     >chan_entry_sign        ; $660A-$6614: $241E into
                lbsr    ABI_ampl_set_signed     ; record+$14, once the value
                bra     chan_commit_ampl_set    ; has been accepted ($65CA)
chan_commit_ampl_plain
                lbsr    ABI_ampl_set            ; every other waveform, as
chan_commit_ampl_set                            ; before
                lbcs    chan_commit_refused     ; long, as above
                clr     >entry_active
                lbra    chan_show_ampl

chan_commit_phase
                lbsr    chan_entry_scale        ; tenths of a degree from here on
                lbcs    chan_commit_refused
                lda     >entry_result           ; a phase is sixteen bits, so
                lbne    chan_commit_refused     ; the top byte must be zero:
                                                ; 65636 keyed here became
                                                ; $0064 and was accepted as
                                                ; 10.0 degrees (the audit's
                                                ; finding); phase_set compares
                                                ; sixteen bits and cannot see
                                                ; what was dropped
                lbsr    chan_record
                ldy     >entry_result+1
                lbsr    ABI_phase_set
                lbcs    chan_commit_phase_quiet ; long: chan_commit_phase_rad
                                                ; now sits between here and
                                                ; the refusal
                clr     >entry_active
                lbra    chan_show_phase

; --- the phase field closed with ENTER: the digits are milliradians ------
; Two constants the stock keeps in A2U12, cited by address because a paged
; screen cannot see units.s, which declares the same two for A2U12's own use:
;
; CHAN_RAD_MAX is the word at $EA5D. `xxd -s 0x6a5d -l 2 firmware/a2u12.bin`
; prints 18 8a, and the listing frames it as `extea5d: fcb $18,$8A`. It is
; the ceiling every radian arm on page 0 compares against - CMPX >$EA5D at
; $66FA in commit_channel_phase ($66B2), at $69BE in set_phase_increment
; ($697B), and in the two hop-phase siblings set_hop_entry_phase ($4DC7) and
; store_hop_phase_increment ($4E87). 6282 milliradians is a whole turn, and
; 6282 x 37549 / 65536 is 3599.29, so the ceiling in degrees is the same
; 359.9 the degree arm enforces with $EA5B = 3599.
;
; CHAN_RAD_SCALE is the immediate scale_by_0p5730 ($D2A9) pushes to
; fixmul_q16 ($D303): `LDU #d92ad`, and build/a2u12_stock.sym places d92ad at
; $92AD, which is 37549 = 0.5729523 x 65536. 180/pi/100 is 0.5729578, so one
; milliradian is 0.0573 degrees, or 0.573 tenths, and a 16x16 multiply with
; the top half kept is the division by 65536.
;
; CHAN_DEG_SCALE is scale_by_1p7453 ($D2C6)'s immediate, `LDU #$bece` at
; $D2CC, and CHAN_DEG_MAX is the word at $EA5B: `xxd -s 0x6a5b -l 2
; firmware/a2u12.bin` prints 0e 0f and the listing frames it as `extea5b: fcb
; $0E,$0F`. It is the ceiling the degree arms compare against - CMPX >$EA5B
; at $66C6 in commit_channel_phase ($66B2) and at $698A in
; set_phase_increment ($697B).
CHAN_RAD_MAX    equ     6282
CHAN_RAD_SCALE  equ     $92AD
CHAN_DEG_MAX    equ     3599
CHAN_DEG_SCALE  equ     $BECE

; ---------------------------------------------------------------------------
; chan_commit_phase_rad - ENTER on the PHASE field: commit the digits as
;                         milliradians
;
;   uses:  A, B, X, Y, U
;
; THE STOCK PATH THIS FOLLOWS, arm by arm. Key $1B on a class-3 field makes
; unit_key_class3 ($B0F3) store 4 in $2221, and the handler that called it at
; $B5A5 posts request $23 through post_request_code ($8AD0), which
; commit_entry_to_field ($6B84) sends to arm [2] of
; d717a, set_phase_units_and_apply ($6E46): it stores $2221 into record+$19
; and falls into commit_phase_entry ($6E51), which picks decade selector 6
; for any unit but 3 (so the digits are thousandths - milliradians, where
; the deg arm's selector 7 makes them tenths), converts them through
; entry_to_scaled_digits ($CDE1) and atoi5 ($C973) into $221A, and calls
; commit_channel_phase ($66B2) - or set_phase_increment ($697B) when $2215 is
; 8, the increment field. Both have the same unit-4 arm: CMPX >$EA5D / LBLS
; store / LBRA return; the store writes $221A to record+$17 (or +$1D) and
; scale_by_0p5730($221A) to record+$15 (or +$1B), and the value path then
; programs the chip with program_channel_phase ($6635).
;
; THE ARITHMETIC IS fixmul_q16's, ROUNDED, in chan_rad_to_tenths, which
; says why this screen multiplies for itself rather than calling
; ABI_unit_apply.
;
; THE UNIT IS RECORDED BEFORE THE DIGITS ARE LOOKED AT. The stock's
; set_phase_units_and_apply ($6E46) is four instructions - LDX >$23BF / LEAX
; <$19,x / LDD >$2221 / STD ,x - and then falls into commit_phase_entry
; ($6E51), so record+$19 becomes 4 whether the entry is empty, refused or
; taken, and the repaint at $6EB1 shows the radian twin of whatever phase is
; set. An INCR SET commit does not pass through it: that is arm [7] of d717a,
; commit_phase_entry itself, and it leaves record+$19 alone.
;
; THE TWIN IS THE ENTRY ITSELF. The radian arm at $6704 stores $221A - the
; milliradians as typed - at record+$17 and only its scaled copy at +$15, so
; what the field shows afterwards is the number the operator keyed, not a
; reconversion of the tenths: chan_phase_rad takes the typed value here, and
; chan_incr_rad the typed increment, as $69C8 does for record+$1D.
;
; A REFUSAL IS REPORTED, WHICH THE STOCK DOES NOT DO. Above $EA5D both
; stock arms LBRA to the routine's LEAS/RTS ($6749, $69FC) and nothing is
; stored, beeped or recorded; commit_phase_entry then repaints the old
; value. The degree path here already beeps through chan_commit_refused
; where the stock is equally silent ($66C3 -> $6749), and this arm does the
; same, recording ERR_PHASE_RANGE - 6282 mrad IS 359.9 degrees, so a value
; above it is the fault that code names. An entry too wide for 24 bits, or
; with anything in its top byte, is above the ceiling by construction and is
; refused the same way.
;
; NOTHING TYPED REDRAWS. The stock's commit_phase_entry gets $FF back from
; $CDE1 for an empty entry and its CMPB #$05 / LBCC $6EB1 skips the store,
; which is chan_commit_choice's redraw.
; ---------------------------------------------------------------------------
chan_commit_phase_rad
                tst     >incr_mode
                bne     chan_commit_rad_entry   ; the increment's unit is
                                                ; not the display's
                lbsr    chan_record             ; B = the channel
                ldx     #chan_phase_unit
                abx
                lda     #CHAN_UNIT_RAD
                sta     ,x
chan_commit_rad_entry
                tst     >entry_active
                lbeq    chan_commit_choice      ; nothing typed

                lbsr    ABI_entry_value         ; carry set if it overflows
                lbcs    chan_commit_rad_too_big ; twenty-four bits

                ; RADIANS ARE TYPED WHOLE. Driven on the stock 2026-09-11: on
                ; this field 3 and 3.000 both read '3.000 rad', so the digits
                ; are milliradians only after three decades less whatever a
                ; typed point took. This path took them raw, so a typed 3 was
                ; three THOUSANDTHS of a radian - 0.2 degrees where the
                ; instrument sets 171.9.
                ldb     #RAD_DECADES
                ldx     #entry_result
                lbsr    ABI_unit_scale_decades
                lbcs    chan_commit_rad_too_big

                lda     >entry_result           ; anything in the top byte is
                lbne    chan_commit_rad_too_big ; more than 65535 mrad
                ldd     >entry_result+1
                cmpd    #CHAN_RAD_MAX           ; CMPX >$EA5D / LBLS
                lbhi    chan_commit_rad_too_big
                std     >chan_work+1            ; the milliradians as typed,
                                                ; kept for the twin
                lbsr    chan_rad_to_tenths
                ; D = tenths of a degree, 0 to 3599

                ; INCR SET DIVERTS THE SAME ENTRY, exactly as chan_commit
                ; does for the degree terminator: the stock's $6E93 CMPX
                ; #$0008 sends the increment field to set_phase_increment,
                ; whose unit-4 arm at $69BB has the ceiling and conversion
                ; above and writes the degree copy to record+$1B. incr_phase
                ; is in tenths of a degree, so the converted value goes in.
                tst     >incr_mode
                beq     chan_commit_rad_value
                lbsr    chan_incr_end
                tfr     d,y
                lbsr    chan_incr_address       ; X = incr_phase: this is the
                                                ; PHASE field, so the carry
                                                ; is set and needs no test
                clr     ,x                      ; the 24-bit slot's top byte
                sty     1,x
                ldd     >chan_work+1            ; and record+$1D's twin, as
                std     >chan_incr_rad          ; typed
                clr     >entry_active
                lbra    chan_values_show

chan_commit_rad_value
                tfr     d,y                     ; Y = tenths, for phase_set
                lbsr    chan_record             ; X = the record, B = channel;
                                                ; it does not touch Y
                lbsr    ABI_phase_set           ; store and program, refusing
                lbcs    chan_commit_phase_quiet ; without change past 3599 -
                                                ; unreachable after the
                                                ; ceiling above, kept because
                                                ; the setter's contract says
                                                ; to test its carry
                lbsr    chan_record             ; B = the channel again;
                aslb                            ; phase_set uses B
                ldx     #chan_phase_rad
                abx
                ldd     >chan_work+1            ; record+$17's twin, as typed
                std     ,x
                clr     >entry_active
                lbra    chan_show_phase

chan_commit_phase_quiet
                ; A PHASE PAST ITS LIMIT IS NOT STORED AND NOT REPORTED.
                ; commit_channel_phase ($66B2) compares with 3599 or 6282 and
                ; leaves through l6749 ($6749) - LEAS / RTS, no beep and no
                ; error number - and commit_phase_entry's l6eb1 then puts the
                ; field back. This beeped through chan_commit_refused.
                clr     >entry_active
                lbsr    chan_incr_end
                lbra    chan_values_show
chan_commit_rad_too_big
                ldb     #ERR_PHASE_RANGE        ; recorded and sounded, and
                lbsr    ABI_error_record        ; the screen shows what is
                clr     >entry_active           ; actually set, as
                lbsr    chan_incr_end              ; chan_commit_refused does.
                lbra    chan_values_show        ; set_phase_increment's
                                                ; ceiling exit returns into
                                                ; commit_phase_entry, whose
                                                ; l6eb1 stores $2215 = 3, so
                                                ; a refused increment shows
                                                ; the value again

; ---------------------------------------------------------------------------
; chan_commit_refused - the value was not acceptable
;
;   uses:  A, B, X, Y, U
;
; The setter has already recorded which error it was and left everything
; untouched. This beeps, drops the entry, and redraws the field with what is
; ACTUALLY set - not with what was typed, because leaving the rejected digits
; on screen is how an operator walks away believing the instrument took them.
; ---------------------------------------------------------------------------
chan_commit_refused
                lbsr    ABI_error_beep
                clr     >entry_active
                lbsr    chan_incr_end              ; an entry too wide for
                                                ; twenty-four bits is refused
                                                ; before chan_commit tests the
                                                ; mode; the stock's l6c11,
                                                ; l6cfa and l6eb1 tails reset
                                                ; $2215 on a refused entry too
                lbra    chan_values_show

; ---------------------------------------------------------------------------
; chan_rad_to_tenths - milliradians to tenths of a degree, the stock's way
;
;   entry: D = milliradians
;   exit:  D = tenths of a degree
;   uses:  A, B, X, Y
;
; THE ARITHMETIC IS scale_by_0p5730's ($D2A9): `LDU #d92ad` and a call to
; fixmul_q16 ($D303), whose result is the 32-bit product's high word plus one
; when bit 15 of the low word is set - `LDD 2,s / TST 4,s / BPL / ADDD
; #$0001` at $D33D-$D343. So 1000 milliradians is 573 tenths (1000 x 37549 =
; 37,549,000: high word 572, low word $F3C8 with bit 15 set), where keeping
; the high word alone gives 572. units.s's unit_apply_radians keeps the high
; word alone, and that one-count truncation is why this screen does its own
; multiply rather than calling ABI_unit_apply: the stock rounds, so this
; rounds. The boundary is safe - 6282 gives 3599 with a low word of $4942,
; bit 15 clear, so nothing in range can round up to 3600.
; ---------------------------------------------------------------------------
chan_rad_to_tenths
                ldx     #CHAN_RAD_SCALE         ; scale_by_0p5730: D x $92AD
                lbsr    ABI_mul16               ; into math_product, 32 bits
                ldd     >math_product           ; the high word...
                tst     >math_product+2         ; ...plus one when bit 15 of
                bpl     chan_rad_to_tenths_done ; the low word is set, which
                addd    #1                      ; is $D33F's TST 4,s / BPL
chan_rad_to_tenths_done
                rts

; ---------------------------------------------------------------------------
; chan_tenths_to_rad - tenths of a degree to milliradians, the stock's way
;
;   entry: D = tenths of a degree, at most CHAN_DEG_MAX
;   exit:  D = milliradians
;   uses:  A, B, X, Y
;
; scale_by_1p7453 ($D2C6) is the same fixmul_q16 call with `LDU #$bece` -
; $BECE is 48846, and 48846/65536 is 0.7453308 - followed by `ADDD >$0008,s`
; at $D2DE, which adds the argument back: round(n x 0.7453308) + n, a scaling
; by 1.7453308. commit_channel_phase ($66B2)'s degree arm calls it at $66EC
; to write record+$17 from a degree entry, and set_phase_increment ($697B)'s
; at $69B0 to write record+$1D. 3599 gives 6281, so an in-range argument's
; result fits sixteen bits.
;
; EVERY VALUE 0 TO 3599 CONVERTS BACK TO ITSELF through chan_rad_to_tenths:
; enumerated in python3 with both roundings as fixmul_q16 rounds them,
; round(t x $BECE) + t and then round(m x $92AD), and all 3600 return t. That
; is what lets chan_phase_rad_get tell a twin it computed from a twin that
; was typed with one test. The other direction is not exact - 1001 becomes
; 574 becomes 1002, and 2683 of the 6283 milliradian values do the same -
; which is why the typed value is kept rather than recomputed.
; ---------------------------------------------------------------------------
chan_tenths_to_rad
                pshs    a,b                     ; the argument, added back
                ldx     #CHAN_DEG_SCALE         ; D x $BECE
                lbsr    ABI_mul16
                ldd     >math_product           ; the high word, rounded as
                tst     >math_product+2         ; fixmul_q16 rounds
                bpl     chan_tenths_to_rad_add
                addd    #1
chan_tenths_to_rad_add
                addd    ,s                      ; $D2DE's ADDD >$0008,s
                leas    2,s
                rts

; ---------------------------------------------------------------------------
; chan_phase_rad_get - the phase in milliradians, agreeing with the record
;
;   entry: X = the channel record, B = the channel
;   exit:  D = milliradians; X and Y preserved
;   uses:  A, B
;
; The twin is authoritative only while it agrees with CHAN_PHASE: if
; converting it with chan_rad_to_tenths gives the record's value, it is what
; phase_set stored from and it is returned as typed. Otherwise the phase was
; written by a path that does not keep the twin - a degree entry on this
; screen, a bus command, a register recall, channel_records_init - and it is
; rebuilt from the record with chan_tenths_to_rad and stored, which is what
; commit_channel_phase ($66B2)'s degree arm does to record+$17 at $66EC-$66F4.
; A twin rebuilt that way passes the same test next time, so a repaint costs
; one multiply and never rewrites it.
; ---------------------------------------------------------------------------
chan_phase_rad_get
                aslb                            ; two bytes of twin a channel
                ldy     #chan_phase_rad
                leay    b,y                     ; Y = this channel's twin
                pshs    x,y                     ; 0,s the record, 2,s the twin
                ldd     ,y
                lbsr    chan_rad_to_tenths      ; D = what phase_set stored,
                ldx     ,s                      ; if this twin was the entry
                cmpd    CHAN_PHASE,x
                beq     chan_phase_rad_fresh

                ldd     CHAN_PHASE,x            ; stale: rebuild it from the
                lbsr    chan_tenths_to_rad      ; record, as $66EC does
                ldx     2,s
                std     ,x
                bra     chan_phase_rad_done
chan_phase_rad_fresh
                ldx     2,s
                ldd     ,x
chan_phase_rad_done
                puls    x,y
                rts

; ---------------------------------------------------------------------------
; chan_incr_rad_get - the phase increment in milliradians, agreeing with
;                     incr_phase
;
;   exit:  D = milliradians
;   uses:  A, B, X, Y
;
; The same test as chan_phase_rad_get, for record+$1D's twin: the stock's
; set_phase_increment ($697B) keeps record+$1B and +$1D in step exactly as
; commit_channel_phase keeps +$15 and +$17. incr_phase is the tenths and is
; at most CHAN_DEG_MAX - chan_commit refuses more, and the radian path stores
; a converted value - so its top byte is zero and the conversion fits.
; ---------------------------------------------------------------------------
chan_incr_rad_get
                ldd     >chan_incr_rad
                lbsr    chan_rad_to_tenths
                cmpd    >incr_phase+1
                beq     chan_incr_rad_fresh
                ldd     >incr_phase+1           ; stale: rebuild it, as
                lbsr    chan_tenths_to_rad      ; $69B0 does for +$1D
                std     >chan_incr_rad
                rts
chan_incr_rad_fresh
                ldd     >chan_incr_rad
                rts
