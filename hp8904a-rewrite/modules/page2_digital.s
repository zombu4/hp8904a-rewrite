; ===========================================================================
; page2_digital.s - the digital port and digital sequence mode
;
; Option 003 adds a digital output port alongside the analogue channels. A
; digital sequence is a list of byte patterns clocked out of it, the digital
; counterpart of the tone sequence on page 1.
;
; $0600 IS AN INPUT, AND THIS MODULE USED TO DRIVE IT. That was wrong, and it
; is the reason this file has been rewritten.
;
; The claim was that the port is an eight-bit output with a shadow. Nothing
; supports it. Across all five stock images $0600 is touched exactly three
; times - two `clr` and one `ldb` - and the disassembly's own memory map calls
; it "digital port input, rear 15-pin". A firmware that clears a port and
; reads it is not driving data out of it, and whether the pins can be driven
; at all is not established anywhere in this repository.
;
; SEARCH BY SYMBOL, NOT BY ADDRESS. Grepping the five listings for `$0600`
; returns nothing at all, because they spell it `digital_in`. The first pass
; of this enumeration found zero references and would have concluded the stock
; never touches the port; it touches it three times.
;
; WHAT THE STOCK ACTUALLY DRIVES is one bit at a time, through the output
; routing:
;
;   set_digital_output_bit ($51C8) writes DDS register $22 - $22 for a zero
;   bit and $20 for anything else, differing only in bit 1
;
;   seq_output_stop ($4881) puts $21 there through
;   dds_set_output_mode_reg22 ($6B92) when the sequence stops
;
; Register $22 is the Out1/Out2 source routing this firmware already models in
; modules/modulation.s: bits 2:0 select which channel feeds Out1, and 4 means
; nothing routed. So $20, $22 and $21 are Out1 fed from channel 0, channel 2
; and channel 1, with Out2 disconnected in all three. The digital output is
; the socket being switched between two channels carrying two different
; levels, which is also why the stock's digital screen edits an On level and
; an Off level and reprograms both from one routine, program_dds_levels
; ($5223).
;
; So the sequence here is clocked out SERIALLY, one bit per tick, most
; significant bit of each step's byte first. The editor still types a byte per
; step, because sixteen bytes are far easier to enter than a hundred and
; twenty-eight separate bits; only what reaches the hardware has changed.
;
; The routing is done through port_route rather than by writing the whole
; register, so Out2's field survives. The stock writes the byte whole and
; disconnects Out2 every time; preserving it contradicts no evidence and
; loses nothing.
; ===========================================================================

; --- WHERE EVERY FIELD SITS, and all of it is the instrument's ------------
; docs/stock-digital-screen.md carries the three DDRAM images character for
; character; these are the columns the live fields are written over. DDRAM
; $00-$27 is line 1 and $40-$67 is line 2, which is what LCD_LINE1 and
; LCD_LINE2 are.
;
; The screen this replaced was the rewrite's own invention - a 'Step:/Pat:'
; row over a sixteen-step model the instrument does not have. Everything here
; is read out of a2u13_page2's menu records at $4002, $411A and $4052.
DIGITAL_IX_POS  equ     LCD_LINE1+$0E   ; Seq Index, four characters, over the
                                        ; '126' of the record at $4002.
                                        ; draw_index_number_field ($57A5)
                                        ; writes four at $3CCB, and
                                        ; select_keypad_numeric_field ($6358)
                                        ; sets $3CCB to $0E for this page
DIGITAL_IX_W    equ     4
DIGITAL_END_POS equ     LCD_LINE2+$0C   ; Seq End, four, over the '127'. The
                                        ; same routine, at its other column
                                        ; ($5814 LDB #$4C)
DIGITAL_WIN_POS equ     LCD_LINE1+$15   ; the sixteen data cells, between the
                                        ; brackets at $14 and $25
DIGITAL_WINDOW  equ     16              ; how many cells there are ($5959
                                        ; CMPX #$0010)
DIGITAL_EDIT_POS equ    LCD_LINE2+$14   ; the f4 label, and in an edit session
DIGITAL_EDIT_LEN equ    20              ; the f3/f4 pair that replaces it
                                        ; ($5A3B/$5A6B write twenty at $54)
DIGITAL_BASE_POS equ    LCD_LINE1+$0C   ; 'Bin', 'Oct' or 'Hex' over the 'Hex'
                                        ; of ' Seq Base Hex' - display_base_name
                                        ; ($4959) writes three at $0C
DIGITAL_PER_POS equ     LCD_LINE1+$1E   ; the period, SIX columns from $1E -
DIGITAL_PER_W   equ     6               ; period_field_render ($4771) writes
DIGITAL_PER_DIGITS equ  5               ; five digits with the point at three
DIGITAL_PER_BLANK  equ  3               ; and at most three leading zeros
DIGITAL_PER_POINT  equ  3               ; blanked, which is count+1 = six
                                        ; characters. All three whole digits
                                        ; are blankable, which is why ten
                                        ; counts read '   .10' and not '  0.10'
DIGITAL_PER_UNIT equ    LCD_LINE1+$25   ; and 'ms' or 's ' beside it
; THE TWO LEVEL FIELDS ARE NOT THE SAME WIDTH, because the instrument's own
; two labels are not the same length. ' On Lev  5.00   V ' is seven characters
; of label and ' Off Lev     0  uV' is eight, so the room left over is eleven
; columns on the first row and ten on the second - and writing eleven at the
; second would have eaten the 'v' of 'Off Lev'.
;
; ampl_text renders nine characters of value and two of unit. The mark level
; gets all nine; the space level gets the last eight, and that costs nothing
; an operator can see: ampl_text right-justifies into its nine, so the first
; is a blank for every value the panel can express - the ceiling is
; 10,000,000 microvolts and that is eight characters with its point.
; THE TWO LEVEL FIELDS, at the columns render_level_value_field ($45EB) and
; level_sign_right_justify ($4569) write. set_level_columns_and_display ($467C)
; picks $4B/$51 for the On row ($469A/$469F) and $60/$66 for the Off row
; ($468D/$4692); the digit count is FIVE (X = 5 at $4640); the blank that
; clears the sign column goes one before the digits ($458E, from $ED11); and
; the unit label follows at the second column, three characters for the On row
; and two for the Off row, where the stock's own 80-column clamp cuts the
; third. This firmware wrote nine value characters from $09 and eight from
; $1E, which ran the value into the unit and left the field a column out.
DIGITAL_ON_POS  equ     LCD_LINE2+$0B   ; $4B, the On row's five digits
DIGITAL_ON_UNIT equ     LCD_LINE2+$11   ; $51, its unit label
DIGITAL_ON_UW   equ     3
DIGITAL_OFF_POS equ     LCD_LINE2+$20   ; $60, the Off row's five digits
DIGITAL_OFF_UNIT equ    LCD_LINE2+$26   ; $66, its unit, clipped to two by the
DIGITAL_OFF_UW  equ     2               ; end of the line
DIGITAL_LEV_W   equ     5               ; five digits either row
DIGITAL_BIT_POS equ     LCD_LINE1+$08   ; the player's bit number, four
                                        ; columns over the '115' of ' Bit
                                        ; 115  [1]'. $3CCB is 8 on this page
DIGITAL_VAL_POS equ     LCD_LINE1+$0E   ; and the bit itself, between the
                                        ; brackets - draw_seq_digit's other
                                        ; base column ($0E, page 3)
DIGITAL_STATUS_LEN equ  20              ; the run banner, twenty columns of
                                        ; line 1 ($48A8 draw_run_status_field)

; WHICH CHANNEL OUT1 IS FED FROM, for each state of the output bit. These are
; the stock's three values for DDS register $22 read as the routing field this
; firmware already models: $20, $22 and $21 are sources 0, 2 and 1.
; HOW LONG ONE BIT LASTS, in counts of the sequence timer. One count is ten
; microseconds - established by running the stock's display_period ($4864),
; which prints "1.00 ms" for 100 - so this is one millisecond a bit, a
; thousand bits a second.
;
; FIXED, AND THE STOCK'S IS NOT. Its Period field is operator-settable from
; $3C9E, with a floor of ten counts enforced by validate_period_minimum
; ($4B6D). This screen has no period field and no way to type one, so the rate
; is a constant here and that is a real limitation rather than a choice worth
; defending. What it is NOT any more is a count of foreground passes.
DIGITAL_START_COUNTS equ $00C8          ; THE FIRST PERIOD, and not the bit
                                        ; period: start_sequence_clock ($5398)
                                        ; stores #$00C8 straight into
                                        ; ptm_timer2 and lets the body swap the
                                        ; real one in on the first tick. The
                                        ; tone player's TONE_START_COUNTS and
                                        ; the dialler's DTMF_GAP_COUNTS are the
                                        ; same $00C8 for the same reason.
DIGITAL_BIT_COUNTS equ  100             ; the DEFAULT bit period, in timer
                                        ; counts: one millisecond. It used to
                                        ; be the only one - the rate was a
                                        ; constant and nothing could change
                                        ; it, while the stock keeps a settable
                                        ; period at $3C9E with its own entry
                                        ; and step keys.
DIGITAL_PAGES   equ     4               ; the four menu records, which is the
DIGITAL_PAGE_TITLE    equ 0             ; count byte $03 at $416A plus one
DIGITAL_PAGE_SETTINGS equ 1             ; $411A, the base, period and levels
DIGITAL_PAGE_EDITOR   equ 2             ; $4002, Seq Index, End and the window
DIGITAL_PAGE_PLAYER   equ 3             ; $4052, the Bit row and the run keys
DIGITAL_PERIOD_RESET equ 10             ; THE COLD PERIOD, ten counts - a
                                        ; tenth of a millisecond. mode_cold_init
                                        ; ($6FFF) writes $000A into $3C9E and
                                        ; into the step $3CA0 ($70E2-$70E9), and
                                        ; the stock's screen reads
                                        ; ' Period    .10 ms ' on a cold boot
DIGITAL_TENTH   equ     10              ; timer counts in a tenth of a
                                        ; millisecond, which is the stock's
                                        ; minimum of $000A exactly. It is the
                                        ; ARROW step's default and the arrow
                                        ; floor - NOT a unit the keypad can
                                        ; type, the Period being class 5 and
                                        ; class 5 offering only ms and s
DIGITAL_PERIOD_MAX_MS equ 655           ; 65535 counts is 655.35 ms, so 655 is
                                        ; the longest period the cell holds.
                                        ; MEASURED ON THE STOCK, not inferred:
                                        ; 655 then Hz gives $3C9E = 65500 and
                                        ; 656 then Hz restores the old value,
                                        ; which is check_entry_le_65536
                                        ; ($4B8C) refusing and then
                                        ; validate_period_minimum ($4B6D)
                                        ; putting the previous period back.
                                        ; The same 655 as TONE_MS_MAX and
                                        ; DTMF_ON_MAX_MS, for the same reason
DIGITAL_PERIOD_MIN equ  1               ; ONE MILLISECOND. The keypad entry is
                                        ; in milliseconds once the unit key
                                        ; has been applied, so this floor is
                                        ; compared in milliseconds and the
                                        ; smallest typeable period is 1 ms -
                                        ; ten times the stock's $000A arrow
                                        ; floor, and exactly where the stock's
                                        ; own keypad stops for the same reason

DIGITAL_MARK    equ     0               ; a one bit
DIGITAL_SPACE   equ     2               ; a zero bit
DIGITAL_CARRIER equ     1               ; and the channel neither of them uses,
                                        ; which the mode still programs:
                                        ; mode_cold_init ($6FFF) forces $23BE
                                        ; to 1 at $7040 and gives that channel
                                        ; the constant at d4193 - see
                                        ; digital_sequence_open

; REGISTER $1C, WRITTEN ONCE AT EVERY DIGITAL SEQUENCE ENTRY. dds_write_reg_1c
; ($5182) shadows its byte in $24B5 and sends it with dds_write_pair ($DE6F),
; exactly as page 1's dds_write_reg1c ($6AE3) does; digital_sequence_mode_setup
; ($7187) calls it with 2 at $72E1. formats.inc has no equate for it because
; this page and page 1 each name it independently - see DDS_ZERO_LT and
; DTMF_ZERO_LT_RUN in page1_dtmf.s for that copy.
DDS_ZERO_LT     equ     $1C
DTMF_ZERO_LT_RUN equ    $02             ; the value $72E1 sends

; AND THE WHOLE REGISTER BYTE FOR EACH, which is what the instrument writes.
; Bits 0-2 are Out1's source and bits 3-5 Out2's; the stock's three values all
; carry 4 - no source - in the upper field, so running a digital sequence
; leaves Out2 disconnected on the instrument and does so here.
; Written as the bytes rather than as DIGITAL_MARK|(PORT_NONE<<3): asm6809.py
; does not parse a parenthesised shift ("undefined symbol '(PORT_NONE<<3)'")
; and both assemblers have to read this file the same way. PORT_NONE is 4, so
; the upper field is 4<<3 = $20 and the two values are $20|0 and $20|2.
DIGITAL_MUX_MARK  equ   $20             ; the ISR's $41A1: Out1 <- channel 0
DIGITAL_MUX_SPACE equ   $22             ; its $41CA: Out1 <- channel 2
; and the same two as the ISR stores them: the register id in the high byte,
; the value in the low, one STD at $0200
DIGITAL_MUX_MARK_W  equ $2220
DIGITAL_MUX_SPACE_W equ $2222

; THE LEVEL FIELD, which is the stock's On/Off Level ported into this
; firmware's model. The stock arms it at $6653 - entry mode 3 (or 2, signed,
; when $3CDD is zero), width 6, columns $4A/$51 or $5F/$66 - commits it at
; $4CDA through accept_level_entry ($4C51) with the $EA62 = 10,000,000
; ceiling, steps it at $4EB0 with the sign flipped through zero, and
; reprograms the pair with program_dds_levels ($5223). Under this firmware's
; reading of the same hardware - the socket switched between two channels -
; the pair ARE the mark and space channels' amplitudes, so the one stock
; field becomes two, selected with the AMPTD key the way the tone screen's
; level is, and committed through ampl_set, which is the same
; validate-store-program the stock's three steps add up to.
;
; AND EACH OF THE TWO IS SIGNED, as the stock's is. The sign lives beside the
; magnitude - digital_sign_mark and digital_sign_space are the stock's $3C11
; and $3C12, which mode_cold_init ($6FFF) sets to '+' at $70D9 and $70DE -
; the MINUS key puts '-' on the entry in progress ($B02E), ENTER commits the
; entry's sign with its value ($4CF1), the arrows fold the magnitude through
; zero and flip it ($4EB0), and the display sets it against the first
; significant digit ($4569). AND THE SIGN REACHES THE CHIP: each level is
; committed through ampl_set_signed (ABI slot 71) with its sign in A, and
; amplitude.s's ampl_pair_common does to the mantissa what the stock does -
; scale_to_dds_code ($D3EC) on a record whose waveform word (+$1F) is 4 (dc)
; halves the code again and complements it against $1000 unless the sign at
; +$14 is '-' ($D4A3-$D4FB), and program_dds_levels folds and unfolds it at
; $5306-$5343. This screen makes both level channels dc at open, as
; digital_sequence_mode_setup does for channel 0 at $7274-$7277 and
; mode_cold_init ($6FFF) for channel 2, so that arm is the one taken.
; --- WHICH FIELD THE KEYPAD AND THE ARROWS REACH ---------------------------
; The stock's $3CAC, and the correspondence is one to one; only the numbers
; differ, because $3CAC's are indices into three jump tables ($4B45, $4E83 and
; $5122) that this firmware does not have - it dispatches on the value with
; compares. The numbers are internal and an operator cannot see them; the set
; of fields, and which key reaches each, is the instrument's.
;
;   here                  $3CAC   armed by
;   DIGITAL_FIELD_NONE      0     nothing selected
;   DIGITAL_FIELD_MARK      3     softkey_on_level ($6940), with $3CB8 = mark
;   DIGITAL_FIELD_SPACE     3     softkey_select_off_level ($6976), $3CB8 = space
;   DIGITAL_FIELD_BASE     $0E    softkey_seq_base ($689B)
;   DIGITAL_FIELD_PERIOD    5     softkey_period ($6917)
;   DIGITAL_FIELD_INDEX     8     softkey_select_seq_index ($5B24)
;   DIGITAL_FIELD_DATA      9     softkey_edit_sequence_or_insert ($5B73)
;   DIGITAL_FIELD_END      $0A    softkey_select_seq_end ($5B4E)
;   DIGITAL_FIELD_BIT      $0B    enter_manual_mode ($69AE)
;
; The stock's 4 and 6 - a level's increment and the period's - are one
; digital_incr_mode flag here, because the increment is armed by INCR SET on
; whichever field is already selected and there is nothing else to remember.
DIGITAL_FIELD_NONE  equ 0               ; nothing selected
DIGITAL_FIELD_STEPS equ 0               ; the older name for the same zero
DIGITAL_FIELD_MARK  equ 1
DIGITAL_FIELD_SPACE equ 2
DIGITAL_FIELD_BASE  equ 3
DIGITAL_FIELD_PERIOD equ 4
DIGITAL_FIELD_INDEX equ 5               ; Seq Index
DIGITAL_FIELD_DATA  equ 6               ; the data cursor, in the window
DIGITAL_FIELD_END   equ 7               ; Seq End
DIGITAL_FIELD_BIT   equ 8               ; the manual bit index
DIGITAL_SIGN_PLUS   equ $2B             ; '+' and '-', the two bytes the
DIGITAL_SIGN_MINUS  equ $2D             ; stock keeps in $3C11/$3C12 and
                                        ; tests at $4EB4 (CMPB #$2D)
DIGITAL_SIGN_FLIP   equ $06             ; $2B EOR $06 = $2D and back: one
                                        ; EOR toggles a sign byte between
                                        ; the two, which is what $4F1D-$4F35
                                        ; do with a compare and two stores

; --- this screen's own RAM ----------------------------------------------
; digital_manual, digital_sign_mark, digital_sign_space and
; digital_entry_sign are declared in modules/scratch.inc, where
; test_scratch_layout.py checks them.
DIGITAL_IDLE    equ     DIGITAL_SPACE   ; and between sequences - the SPACE
                                        ; state, which is the same thing.
                                        ;
                                        ; This was 1, giving register $22 the
                                        ; value $21. That is page 1's TONE
                                        ; mode idle, from seq_output_stop
                                        ; ($4881) through
                                        ; dds_set_output_mode_reg22 ($6B92);
                                        ; it is not this mode's.
                                        ;
                                        ; Page 2 has its own stop, and it ends
                                        ; clrb / sex / tfr d,u / lbsr
                                        ; set_digital_output_bit - the
                                        ; argument is ZERO, and
                                        ; set_digital_output_bit ($51C8) picks
                                        ; $22 for zero. So a stopped digital
                                        ; output rests at the space level,
                                        ; which is what a digital line at rest
                                        ; should read as, and borrowing the
                                        ; tone mode's value put a third source
                                        ; on the socket instead.

; --- THE THREE MENU RECORDS, character for character ----------------------
; The stock's page 2 has four records at $416B, and record 0 is a title whose
; f1 to f3 are null_handler_stub ($C239) - nothing but a way in. The three
; that carry the screen are $4175, $417F and $4189, and their text is here
; exactly as the ROM spells it.
;
; $00 IS THE SOFTKEY FONT'S 'f' AND $01-$04 ARE ITS DIGITS. The stock begins
; each label with the two bytes $00,$0n; lcd_glyphs in lcd.s loads the same
; eight CGRAM characters the instrument loads at $EA45, so `fcb $00,$02` here
; renders the 'f2' that is silkscreened on the panel. Each line below is
; exactly forty columns and test_menu_labels checks that.
;
; THE ORDER OF THE PAGES IS THE STOCK'S, and digital_page IS the record
; number: 0 the title, 1 the base, the period and the two levels, 2 the
; sequence editor, 3 the player - DIGITAL_PAGE_TITLE through
; DIGITAL_PAGE_PLAYER, walked in that ring by NEXT and LAST. They were three
; invented title strings with no title record at all, and this paragraph still
; described that arrangement after the four records went in.

; record 0 - the title, $416B -> $40CA. Its f1, f2 and f3 are $C239 and its f4
; is post_request_0b ($8B4C), the Exit.
digital_title_l1 fcc    "**    "
                fcc     "   Digital Sequence Mode      "
                fcc     "  **"
digital_title_l2 fcc    "Pres"
                fcc     "s NEXT/LAST Keys.    "
                fcb     $00,$04,$20,$45,$78
                fcc     "it        "

; record 2 - the sequence editor, $417F -> $4002
digital_p0_l1   fcb     $00,$01
                fcc     " Seq Index  126   [123456789ABCDEF0]  "
digital_p0_l2   fcb     $00,$02
                fcc     " Seq End  127     "
                fcb     $00,$04
                fcc     " Edit Sequence    "
; and the twenty columns that replace the f4 label inside an edit session,
; from $40B6
digital_p0_edit fcb     $00,$03
                fcc     " Delete  "
                fcb     $00,$04
                fcc     " Insert"

; page 1 - the base, the period and the two levels, record 1 ($4175 -> $411A)
digital_p1_l1   fcb     $00,$01
                fcc     " Seq Base Hex     "
                fcb     $00,$03
                fcc     " Period   1.0  ms "
digital_p1_l2   fcb     $00,$02
                fcc     " On Lev  5.00   V "
                fcb     $00,$04
                fcc     " Off Lev     0  uV"

; page 2 - the player, record 3 ($4189 -> $4052)
digital_p2_l1   fcb     $00,$01
                fcc     " Bit  115  [1]                        "
digital_p2_l2   fcb     $00,$02
                fcc     " Continuous       "
                fcb     $00,$03
                fcc     " Single  "
                fcb     $00,$04
                fcc     " Stop  "

; THE RUN BANNER, twenty columns over the left of line 1 on the player page.
; draw_run_status_field ($48A8) picks one of these or leaves the record's own
; first twenty bytes showing. ' Manual' carries its f1 marker because it
; replaces a label; the two running banners do not, because they replace one.
digital_run_single fcc  "** Running Single **"
digital_run_cont   fcc  "** Running Cont **  "
digital_run_manual fcb  $00,$01
                   fcc  " Manual           "

; THE PERIOD'S UNIT. The stock's display_period ($4864) shows milliseconds
; below a second and seconds above it; one timer count is ten microseconds, so
; the value is rendered in tenths of a millisecond and this is what it is in.
digital_blank   fcc     " "             ; the sign column, cleared before
                                        ; the sign is placed - $458E writes one
                                        ; character from $ED11
digital_unit_ms fcc     "ms"

; --- the three number bases, numbered as the stock numbers them ------------
; set_max_length_for_base ($56A3) takes 0, 1 and 2 and the names it prints
; sit at $516F, $5173 and $5177 in a2u13_page2.bin, which read 'Bin', 'Oct'
; and 'Hex'. Using the stock's own numbering means the arm and this dispatch
; can be compared without a translation table in between.
DIGITAL_ERR_WRONG_MODE equ $3A        ; key_reject_unhandled_code ($6E4F):
                                        ; 'Commmand not permitted in this mode'
DIGITAL_BASE_BIN equ    0
DIGITAL_BASE_OCT equ    1
DIGITAL_BASE_HEX equ    2
DIGITAL_BASES    equ    3
digital_base_bin fcc    "Bin"           ; the strings the stock prints from
digital_base_oct fcc    "Oct"           ; $516F, $5173 and $5177, spelled
digital_base_hex fcc    "Hex"           ; identically

; THERE IS NO 'Option 003 required' LINE ANY MORE. digital_show painted it on
; every repaint and the instrument's painters never read the options byte -
; see the note over digital_show, and page1_tone.s's tone_show, which carried
; the same fault and the same evidence. Nor does the entry refuse: see
; digital_sequence_open.

; ---------------------------------------------------------------------------
; digital_drive_bit - put one bit of the sequence on the output
;
;   entry: A = the bit; zero drives a SPACE, anything else a MARK
;   uses:  A, B, X, Y
;
; ONE WRITE OF THE WHOLE REGISTER, and that is not a shortcut - it is what
; the instrument does. set_digital_output_bit ($51C8) picks between $22 for a
; zero bit at $51D9 and $20 for a one at $51E0 and hands the WHOLE BYTE to
; $51A5, which stores it in the register's shadow $24BB and writes DDS
; register $22 through $DE6F. Its own bit clock does not even go that far: the
; ISR at $4196 writes the pair inline, LDX #$2220 / STX $0200 at $41A1-$41A4
; for a one and LDX #$2222 / STX $0200 at $41CA-$41CD for a zero - two
; instructions, register id then value, which is byte for byte what one
; dds_write of a width-1 register puts on the bus.
;
; THIS WENT THROUGH port_route, WHICH READ-MODIFY-WRITES. That preserves Out2's
; field, which the instrument does not bother to do - $20, $22 and $21 all
; carry 4, no source, in bits 3-5 - and it cost 170 instructions a bit against
; the stock's twelve, measured on the emulator 2026-09-12. The default bit
; period is TEN counts ($000A into $3C9E, mode_cold_init $6FFF), so a service
; that long cannot finish before the next time-out: frames piled up at the RTI
; twelve bytes at a time and the stack walked from $21FF down past the RAM
; signature at $203B. A firmware that locks up on its own default setting is
; not a port of one that does not.
;
; The bit is recorded before it is driven so the screen reports what was
; asked for even if the write refuses; a display that silently shows the
; previous bit is worse than one that shows an unexpected one.
; ---------------------------------------------------------------------------
digital_drive_bit
                sta     >digital_bit            ; what the screen reports
                tsta
                beq     digital_drive_space
                ldx     #DIGITAL_MUX_MARK       ; $41A1's $20: Out1 <- the mark
                bra     digital_drive_mux       ; channel, Out2 nothing
digital_drive_space
                ldx     #DIGITAL_MUX_SPACE      ; $41CA's $22: the space channel
digital_drive_mux
                ldb     #DDS_PORT_MUX_01        ; register $22, one byte wide
                lbra    ABI_dds_write

; ---------------------------------------------------------------------------
; digital_drive_idle - stop driving data, and say so
;
;   uses:  A, B, X, Y
;
; The third of the stock's three values. seq_output_stop ($4881) writes $21
; when a sequence stops, so stopping does not leave the last bit standing on
; the socket - it selects a third source instead.
;
; THIS IS WHY STOPPING NOW CHANGES THE OUTPUT, where the old parallel version
; deliberately left the port alone. That reasoning applied to eight lines an
; operator had wired to something; it does not apply here, because the thing
; being changed is which of this instrument's own channels feeds its own
; socket, and the stock does exactly this on every stop.
; ---------------------------------------------------------------------------
digital_drive_idle
                clr     >digital_bit
                lda     #DIGITAL_IDLE
                ldb     #LBL_OUT1
                lbra    ABI_port_route

; ---------------------------------------------------------------------------
; digital_manual_drive - in manual mode, drive the bit under the cursor
;
;   uses:  A, B, X, Y
;
; The stock does this after every cursor move and every typed index while its
; Manual flag $3C04 is set: step_manual_bit_position ($501F) and
; step_sequence_index_field ($5062) after step_sequence_field, enter_bit_index
; ($4DE1) after enter_sequence_field_value, and enter_manual_mode ($69AE)
; itself. Each reads the sequence element under the cursor with
; read_bit_at_cursor ($54DF) and passes it with $3C04 to
; manual_output_drive_bit ($51F6), which returns unless $3C04 is set and the
; bit is below 2, and otherwise drives DDS register $22 through
; set_digital_output_bit ($51C8) - the same write the sequence clock makes.
;
; The bound is the stock's: read_bit_at_cursor returns $64 when the cursor's
; bit index $3CA6 is past the end $3CA8, and $51F6 rejects it, so a cursor
; past the sequence's end drives nothing. Here the cursor is a bit index and
; the end is sequence_length in steps of eight bits.
; ---------------------------------------------------------------------------
digital_manual_drive
                tst     >digital_manual         ; $51F6: nothing unless manual
                beq     digital_manual_drive_done
                ldx     >digital_index_bit      ; $54DF reads at $3CA6 and
                cmpx    >digital_end_bit        ; bounds it with $3CA8 - the
                bhi     digital_manual_drive_done ; CURSOR, not the player's
                lbsr    digital_bit_at          ; counter: past the end it
                                                ; returns $64 and $51F6 drops
                                                ; it
                lbra    digital_drive_bit       ; $51C8: onto the socket
digital_manual_drive_done
                rts

; ---------------------------------------------------------------------------
; digital_bit_at - one bit of the pattern
;
;   entry: X = the bit index, 0 to DIGITAL_PATTERN_BITS-1
;   exit:  A = zero for a zero bit, non-zero for a one
;   uses:  A, B, X
;
; SIXTEEN BITS OF INDEX, because the pattern is 1000 bits. It was eight, over
; sixteen bytes.
;
; MOST SIGNIFICANT BIT FIRST, which is not a choice here any more - it is what
; the packing is. The instrument's player shifts the pattern out with `ASL
; $3CC9` at $419C, taking bit 7 of each byte first and walking the bytes
; upward, and every digit of every base is cut from that same order.
; ---------------------------------------------------------------------------
digital_bit_at
                lbsr    digital_byte_of         ; X = the byte, shift = place
                lda     ,x
                ldb     >digital_shift
                ldx     #digital_bit_masks      ; ONE AND, NOT UP TO SEVEN
                anda    b,x                     ; SHIFTS: the loop that stood
                rts                             ; here cost three instructions
                                                ; a place and this is on the
                                                ; interrupt's own path
; $80 >> place. The instrument does not index at all - its ISR keeps the byte
; in $3CC9 and ASLs it once a bit - so a table is the cheapest way to answer
; the same question for a caller that arrives with an index instead.
digital_bit_masks
                fcb     $80,$40,$20,$10,$08,$04,$02,$01

; ---------------------------------------------------------------------------
; digital_bits_of      - the last bit of digit X
; digital_bits_index   - and store it as the cursor's bit
; digital_bits_last    - and as the player's end bit only
; digital_bits_end     - and as both the editor's end bit and the player's
;
;   entry: digital_bits_of takes the digit in X; the other three take theirs
;          from digital_index or digital_end
;   exit:  X = the bit
;   uses:  A, B, X
;
; THE LAST BIT OF THE DIGIT, NOT THE FIRST, which is what
; element_index_to_bit_index ($55F3) returns: base 0 gives n, base 1
; (n+1)*3-1 and base 2 (n+1)*4-1. A digit of width w occupies bits w*n to
; w*n+w-1, so its last is w*(n+1)-1, and that is the bit the cursor's own
; readout shows - read_bit_at_cursor ($54DF) reads a one-bit digit at $3CA6.
;
; THREE ENTRIES BECAUSE THE INSTRUMENT HAS THREE. seq_recompute_bit_indices
; ($5646) is passed the address of the variable to fill: $3CA2 fills $3CA6
; alone, $3CAA fills $3CAA alone, and anything else fills $3CA8 and copies it
; to $3CAA. The middle one exists for the base change: it clamps the end digit
; to the new base's capacity and refreshes the PLAYER's end bit from it while
; leaving $3CA8 alone, because $3CA8 is the bit-stream fact the next base
; change reconstructs the digit indices from and clamping must not destroy it.
; ---------------------------------------------------------------------------
digital_bits_of
                leax    1,x                     ; digits, not the last index
                lbsr    digital_bit_of          ; X = (n+1) * w
                leax    -1,x                    ; and the last bit of them
                rts
digital_bits_index
                ldx     >digital_index
                bsr     digital_bits_of
                stx     >digital_index_bit
                rts
digital_bits_last
                ldx     >digital_end
                bsr     digital_bits_of
                stx     >digital_last_bit
                rts
digital_bits_end
                ldx     >digital_end
                bsr     digital_bits_of
                stx     >digital_end_bit
                stx     >digital_last_bit
                rts

; ---------------------------------------------------------------------------
; digital_width - how many bits a digit of the current base takes
;
;   exit:  B = 1, 3 or 4, and digital_wide holds it too
;   uses:  A, B
;
; The stock's three-way switch, in the shape every one of its routines uses:
; LDA $3C20 / BEQ base0 / DECA / BEQ base1 / fall through - so any value that
; is not 0 or 1 is hexadecimal. seq_read_digit ($4261) and seq_write_digit
; ($4344) both do exactly that.
; ---------------------------------------------------------------------------
digital_width
                lda     >digital_base
                beq     digital_width_bin
                deca
                beq     digital_width_oct
                ldb     #DIGITAL_W_HEX
                bra     digital_width_done
digital_width_bin
                ldb     #DIGITAL_W_BIN
                bra     digital_width_done
digital_width_oct
                ldb     #DIGITAL_W_OCT
digital_width_done
                stb     >digital_wide
                rts

; ---------------------------------------------------------------------------
; digital_digit_count - how many digits this base fits in the pattern
;
;   exit:  X = 1000, 333 or 250
;   uses:  A, B, X
;
; set_max_length_for_base ($56A3) writes these into $3CCC and then $3CCE =
; $3CCC-1. 250 x 4 and 1000 x 1 are exactly the 1000 bits; octal's 333 x 3 is
; 999 and wastes the last one, which is the instrument's own arithmetic.
; ---------------------------------------------------------------------------
digital_digit_count
                lda     >digital_base
                beq     digital_count_bin
                deca
                beq     digital_count_oct
                ldx     #DIGITAL_N_HEX
                rts
digital_count_bin
                ldx     #DIGITAL_N_BIN
                rts
digital_count_oct
                ldx     #DIGITAL_N_OCT
                rts

; ---------------------------------------------------------------------------
; digital_limits - reload the highest index this base allows
;
;   uses:  A, B, X
;
; set_max_length_for_base ($56A3), which change_sequence_base ($56E9) calls at
; $5769 and init_sequence_editor at $660F. The count goes in, one less comes
; out, and the cursor and the end are then clamped to it - which is what
; $576E-$578B does after a base change.
; ---------------------------------------------------------------------------
digital_limits
                lbsr    digital_digit_count
                stx     >digital_count          ; $3CCC, the capacity itself.
                                                ; redraw_sequence_window reads
                                                ; it at $59BA to tell a slot
                                                ; the sequence could grow into
                                                ; from one there is no room
                                                ; for, and
                                                ; enter_sequence_field_value
                                                ; bounds a typed index with it
                                                ; at $626C. NOTHING WROTE IT:
                                                ; only $3CCE was stored, so
                                                ; every slot past the end read
                                                ; as past the capacity and the
                                                ; dots between them never
                                                ; appeared
                leax    -1,x
                stx     >digital_max
                ldx     >digital_end            ; and neither index may sit
                cmpx    >digital_max            ; past it: a pattern read as
                bls     digital_limits_index    ; hex has 250 digits where the
                ldx     >digital_max            ; same bits read as binary
                stx     >digital_end            ; have 1000
digital_limits_index
                ldx     >digital_index
                cmpx    >digital_max
                bls     digital_limits_done
                ldx     >digital_max
                stx     >digital_index
digital_limits_done
                rts

; ---------------------------------------------------------------------------
; digital_bit_of - the first bit of a digit
;
;   entry: X = the digit index
;   exit:  X = the bit index, digital_wide = the width
;   uses:  A, B, X
;
; Digit i of width w starts at bit w*i. The instrument computes the LAST bit
; instead - element_index_to_bit_index ($55F3) returns (n+1)*w-1 - which is
; the same statement about the same packing, one bit further along.
; ---------------------------------------------------------------------------
digital_bit_of
                lbsr    digital_width           ; B = 1, 3 or 4
                cmpb    #DIGITAL_W_BIN
                beq     digital_bit_of_done     ; x1: the index IS the bit
                cmpb    #DIGITAL_W_HEX
                beq     digital_bit_of_hex
                tfr     x,d                     ; x3: two shifts and an add
                lslb
                rola
                leax    d,x
                rts
digital_bit_of_hex
                tfr     x,d                     ; x4
                lslb
                rola
                lslb
                rola
                tfr     d,x
digital_bit_of_done
                rts

; ---------------------------------------------------------------------------
; digital_byte_of - which byte a bit lives in, and how far into it
;
;   entry: X = the bit index
;   exit:  X = the byte, digital_shift = the bit's place in it, 0 the top
;   uses:  A, B, X
; ---------------------------------------------------------------------------
digital_byte_of
                tfr     x,d
                andb    #$07
                stb     >digital_shift
                tfr     x,d
                lsra                            ; the bit index over eight
                rorb
                lsra
                rorb
                lsra
                rorb
                addd    #digital_pattern_ram
                tfr     d,x
                rts

; ---------------------------------------------------------------------------
; digital_digit_at - one digit of the pattern, whatever the base
;
;   entry: X = the digit index
;   exit:  B = the digit, 0 to 1, 7 or 15
;   uses:  A, B, X, Y
;
; ONE EXTRACTOR WHERE THE INSTRUMENT HAS SIXTEEN ARMS. Its octal reader
; dispatches through the table at $4245 to eight hand-written arms ($42D3 to
; $4320), each shifting and masking one field of a three-byte group, and its
; hexadecimal and binary readers are two more special cases. The sixteen tile
; the group's 24 bits exactly once in MSB-first order - which is the proof
; that the packing is what this computes instead: a window of two bytes,
; shifted up by the digit's place in the first, with the top w bits taken.
;
; Two bytes is enough for every base here. The widest digit is four bits, so
; it can straddle at most one boundary.
;
; NO BOUNDS CHECK, which is the instrument's behaviour: seq_read_digit ($425D)
; has none at all - only its writer guards - and in octal an index past 332
; reads into the period word beyond the pattern. The callers here bound the
; index instead, which is where the stock's editor bounds it too.
; ---------------------------------------------------------------------------
digital_digit_at
                lbsr    digital_bit_of          ; X = the bit, wide = the width
                lbsr    digital_byte_of         ; X = the byte, shift = its place
                lda     ,x                      ; the two-byte window. For the
                ldb     1,x                     ; very last digit the second
                                                ; byte is one past the pattern
                                                ; - harmless, because a digit
                                                ; ending at bit 999 is shifted
                                                ; up by at most four and its
                                                ; four bits come entirely from
                                                ; the first byte
digital_digit_shift
                tst     >digital_shift          ; up to the digit's own place
                beq     digital_digit_take
                lslb
                rola
                dec     >digital_shift
                bra     digital_digit_shift
digital_digit_take
                ldb     >digital_wide           ; and down, leaving w bits
                negb
                addb    #8
digital_digit_down
                tstb
                beq     digital_digit_done
                lsra
                decb
                bra     digital_digit_down
digital_digit_done
                tfr     a,b
                rts

; ---------------------------------------------------------------------------
; digital_digit_put - write one digit of the pattern
;
;   entry: X = the digit index, A = the value
;   uses:  A, B, X
;
; The read above run backwards: a mask of w ones and the value, both moved
; into the digit's own place in a two-byte window, then the window read,
; cleared and rewritten.
;
; FOUR BYTES OF STACK, not scratch. They live for the length of one call and
; scratch has no run that size left below live_setting - and a temporary in
; scratch is a temporary another screen can be made to collide with.
;
; THE VALUE IS MASKED HERE, which the instrument does NOT do. Its put arms add
; the value in unmasked - $4490 is `ANDB #$F8 / ADDB $9,S` - so an octal value
; of 8 corrupts the field above it. Nothing in seq_write_digit ($4340) clamps;
; validate_digit_for_base ($607E) is supposed to have. One AND makes the
; routine safe on its own terms.
;
; The INDEX is the caller's to bound, as it is the instrument's: its writer
; refuses an index at or past 1000, 333 or 250 ($4388, $43C0, $434E) and does
; nothing at all.
; ---------------------------------------------------------------------------
digital_put_masks
                fcb     $00,$01,$03,$07,$0F     ; w ones, by the width

digital_digit_put
                pshs    a                       ; the value
                lbsr    digital_bit_of
                lbsr    digital_byte_of         ; X = the byte, shift = place
                puls    a

                pshs    x                       ; the mask for this width, and
                ldb     >digital_wide           ; the value clamped to it
                ldx     #digital_put_masks
                abx
                anda    ,x
                ldb     ,x
                puls    x

                leas    -4,s                    ; 0,s-1,s the value as a
                sta     ,s                      ; sixteen-bit window, 2,s-3,s
                clr     1,s                     ; the mask as another, both
                stb     2,s                     ; sitting at the top
                clr     3,s

                lda     #8                      ; up to the top of the byte
                suba    >digital_wide
                beq     digital_put_placed
digital_put_up
                asl     ,s
                asl     2,s
                deca
                bne     digital_put_up
digital_put_placed

digital_put_down                                ; and down to the digit's own
                tst     >digital_shift          ; place
                beq     digital_put_apply
                lsr     ,s
                ror     1,s
                lsr     2,s
                ror     3,s
                dec     >digital_shift
                bra     digital_put_down

digital_put_apply
                lda     2,s                     ; the digit's bits out
                coma
                anda    ,x
                ora     ,s                      ; and the value in
                sta     ,x
                lda     3,s
                coma
                anda    1,x
                ora     1,s
                sta     1,x
                leas    4,s
                rts

; ---------------------------------------------------------------------------
; digital_advance - clock the next BIT out
;
;   entry: through nmi_callback; the CPU has stacked every register
;   exit:  RTI, on every path
;
; THE BODY IS THE CALLBACK, as the stock's bit clock at $4196 is: LDA
; >ptm_status and LDA >ptm_timer2 clear the interrupt, and it ends in its own
; RTI (l422f).
;
; NOTHING ELSE UP FRONT, as $4196 has nothing else. dds_lock was tested here,
; and the zero-end guard below it; neither is in the stock's bit clock, and
; measured on 2026-09-19 at the stock's own .10 ms period - 169 E cycles - they
; were most of the 25 cycles a tick this firmware spent over the stock's 101,
; enough to push the byte-fetch tick past the period so the next time-out
; nested on top of it 1,736 times in 400,000 steps. The stock's never did.
; A tick is never deferred on the stock, so it is never deferred here.
;
; CALLED FROM THE TICK. One routing write and a counter, nothing else: it runs
; with the foreground halfway through whatever it was doing.
;
; A BIT PER TICK, NOT A BYTE. This wrote a whole eight-bit pattern to $0600 on
; every tick, which is neither what the hardware offers nor what the stock
; does; see the head of this file. Eight ticks now carry one step.
; ---------------------------------------------------------------------------
digital_advance
                lda     >ptm_status             ; the clear: status, then the
                ldx     >ptm_timer2             ; counter, $4196 and $4199
                ; NO RUNNING TEST, as $4196 has none. digital_advance is named
                ; once outside this body - `ldx #digital_advance` at the
                ; install - and tick_remove takes it out of nmi_callback before a stop,
                ; so a tick cannot arrive with the player stopped. That is the
                ; instrument's own reasoning for not testing.
                ; AND NO END-ZERO TEST. digital_last_bit is 999 from the moment
                ; the mode is entered - measured, and the stock's cold init at
                ; l65e7 stores the same $03E7 into $3CAA - and this tick is
                ; installed only from inside the mode, so it never meets a
                ; zero. It cost nine cycles on every tick for a case that
                ; cannot arise while it runs.
                                                ; nothing in the tree ever
                                                ; writes. This read it once
                                                ; and no line anywhere stored
                                                ; to it, so the branch was
                                                ; always taken and the digital
                                                ; sequence never clocked a
                                                ; pattern out - while ENTER
                                                ; set digital_running and
                                                ; installed the tick that
                                                ; calls this. Two names for
                                                ; one idea, and the tick
                                                ; tested the one with no
                                                ; writer.


                ; digital_shift IS THE FOREGROUND'S WORKING CELL, and this
                ; runs in the interrupt. digital_bit_at asks digital_byte_of
                ; for the byte, and digital_byte_of leaves the bit's place in
                ; digital_shift - the same cell digital_digit_shift and
                ; digital_put_down are using while they render or store a
                ; digit. A tick landing between their computation and their use
                ; sent the operator's digit to the wrong bit of the pattern.
                ; So the interrupt puts it back exactly as it found it and is
                ; invisible to whatever the foreground was doing.
                ; THE CARRY IS THE BIT. blk419c does ASL >$3CC9 and branches
                ; on the carry it shifts out; the byte was fetched once, eight
                ; ticks ago. This called digital_bit_at, which called
                ; digital_byte_of - thirteen instructions dividing the bit
                ; index by eight - on EVERY tick, and saved and restored
                ; digital_shift around it because the edit screen owns that
                ; cell. Measured 2026-09-16: 46.5 instructions a tick inside
                ; the callback against the instrument's 17.6.
                asl     >digital_play_byte      ; $419C
                bcc     digital_advance_space   ; $419F

                ; AND IT GOES STRAIGHT AT THE CHIP, as the instrument's own
                ; bit clock does: LDX #$2220 / STX $0200 at $41A1-$41A4 for a
                ; one and LDX #$2222 / STX $0200 at $41CA-$41CD for a zero -
                ; the register id and the byte, in one 16-bit store. The
                ; foreground's digital_drive_bit still goes through dds_write,
                ; which is the split the stock has too ($51C8 for the
                ; foreground, this for the ISR).
                ;
                ; EACH ARM STORES AND COUNTS FOR ITSELF, as $41A1-$41AA and
                ; $41CA onward do: the mark arm carries its own copy of the
                ; increment, so neither arm spends a branch on the path every
                ; tick takes.
                ldd     #DIGITAL_MUX_MARK_W     ; $41A1: Out1 <- the mark
                std     >dds_prog               ; $41A4
                ldx     >digital_bit_index      ; $41A7
                leax    1,x                     ; $41AA
                bne     digital_advance_end_test
                bra     digital_advance_wrap    ; once in 65,536 bits
digital_advance_space
                ldd     #DIGITAL_MUX_SPACE_W    ; $41CA: the space channel
                ; ONE STORE, AND NO SHADOW. $41A4 is STX >dds_prog and nothing
                ; else; the stock's ISR never updates its own $24BB shadow
                ; either, and nothing here reads the mux slot - dds.s walks the
                ; shadow for other registers and page1_tone.s:905 documents the
                ; same choice on the tone side.
                std     >dds_prog

                ; NO PERIOD RELOAD HERE, deliberately. Timer 2 runs in a
                ; continuous mode, so it reloads itself from the latches at
                ; every time-out and keeps the same period for ever without
                ; being told. The tone player DOES reload, because its steps
                ; have different durations; every bit here is the same length.

                ; WRAP ON THE SEQUENCE'S END, not on the pattern's capacity.
                ; It wrapped at sixteen bytes - the rewrite's own model - so a
                ; short sequence clocked out its own bits and then whatever
                ; was in the slots after it before starting again. The end is
                ; digital_last_bit, which is what the instrument's ISR
                ; compares its counter with at $41F3.
                ;
                ; THE COMPARISON IS ON BITS, and sixteen of them. It was on
                ; the STEP a bit fell in, one byte wide, which was enough for
                ; sixteen steps of eight and is not enough for a thousand
                ; bits. The stock's ISR compares its own bit counter with
                ; $3CAA at $41F3 and restarts at $41FD, which is this.
                ldx     >digital_bit_index
                leax    1,x

                ; THE PERIOD GOES IN WHEN THE COUNTER WRAPS TO ZERO, and that
                ; is the stock's own reload - the reason start_sequence_clock
                ; can arm a flat $00C8. $41AA onward, and the identical
                ; sequence on the space arm at $41D1, do LEAX 1,X / STX >$3CC4
                ; / BNE past / LDY >$3C9E / LEAY -1,Y / STY >ptm_timer2, so the
                ; reload fires only when the incremented sixteen-bit counter
                ; becomes $0000.
                ;
                ; digital_run primes that counter at $FFFF, so the FIRST tick
                ; is the wrap: the chip runs one $00C8 period and every period
                ; after it is the bit period less one. It fires again only on a
                ; 65,536-tick wrap, which is harmless - the latch auto-reloads
                ; in this mode and the value put back is the same one.
                ;
                ; THE TEST WAS FOLDED AWAY HERE. This went straight from LEAX
                ; 1,X to the end-of-sequence compare, so the counter-zero arm
                ; had nowhere to live and nothing ever reloaded the timer: the
                ; latch kept whatever the install put there for the whole run.
                bne     digital_advance_end_test
digital_advance_wrap
                ldd     >digital_period
                lbsr    ABI_seq_timer_period    ; SUBD #$0001 / STD >ptm_timer2,
                                                ; which is LEAY -1,Y / STY
                                                ; >ptm_timer2 instruction for
                                                ; instruction. X is untouched:
                                                ; its contract is A and B.
                ; AND A SINGLE RUN STOPS HERE, on the tick after the one that
                ; passed its end: $41B7-$41C5 test $3CC8 once the period is
                ; back in, write $91 to the timer and stop through
                ; stop_sequence_preserving_lcd_address. So the stock's single
                ; run clocks one more bit - the cleared byte's, a space -
                ; before it stops, and so does this.
                tst     >digital_once
                beq     digital_advance_end_test
                lda     #$91                    ; $41BA: LDA #$91 / STA
                sta     >ptm_status             ; >ptm_status - timer.s's
                                                ; PTM_SEQ_STOP, which this page
                                                ; cannot see; the stock writes
                                                ; the value, not the shadow
                lbsr    digital_report_end      ; $67A3(0): reported while the
                clr     >digital_running        ; running flag still says so
                lbsr    ABI_tick_remove         ; and the timer stopped again
                lbsr    digital_drive_idle      ; and the bit driven low
                rti
digital_advance_end_test
                cmpx    >digital_last_bit
                bls     digital_advance_store
                ; AND THE CARRIED PAIR GOES BACK WITH IT. l41f3 does exactly
                ; this on the wrap: LDX #$0000 / STX >$3CC4, then LDX #$3C21
                ; / STX >$3CC6 / LDA ,X / STA >$3CC9 - the base, not one
                ; below it, because the byte is fetched here rather than on
                ; the next tick. Without it a second pass would shift on
                ; from wherever the first one stopped.
                ;
                ; AND IT RETURNS FROM THERE. This reset the pair and then fell
                ; into digital_advance_store, whose byte boundary saw index 0
                ; and fetched the NEXT byte before a single bit of the first
                ; had gone out - so every repeat dropped the pattern's first
                ; byte, and the extra fetch was the long path that still ran
                ; a tick past the .10 ms period (2026-09-19). l41f3 ends in
                ; RTI at $420E; so does this.
                ;
                ; A SINGLE-SHOT RUN GOES TO l420f instead, before the reset:
                ; it does not stop on this tick, it parks the counter and
                ; sets the once-through flag, and the wrap tick after it
                ; stops (digital_advance_wrap).
                tst     >digital_single
                bne     digital_advance_single_end
                ldx     #$0000                  ; l41f3: back to the first bit
                stx     >digital_bit_index
                ldx     #digital_pattern_ram    ; the base, and its first byte
                stx     >digital_play_ptr
                lda     ,x
                sta     >digital_play_byte
                rti
digital_advance_single_end
                ldx     #$FFFF                  ; l420f: LDD #$FFFF / STD
                stx     >digital_bit_index      ; >$3CC4, so the next tick
                lda     #$FF                    ; wraps it to zero - and STA
                sta     >digital_once           ; >$3CC8, which that tick stops
                clr     >digital_play_byte      ; on - and CLR >$3CC9: the bit
                rti                             ; it clocks first is a space
digital_advance_store
                stx     >digital_bit_index

                ; AND THE NEXT BYTE ONLY EVERY EIGHTH BIT, which is l421c:
                ; TFR X,D / ANDB #$07 / BNE, then LDX >$3CC6 / LEAX 1,X /
                ; LDA ,X / STX >$3CC6 / STA >$3CC9. Seven ticks in eight end
                ; at the BNE.
                tfr     x,d
                andb    #$07
                bne     digital_advance_done
                ldx     >digital_play_ptr
                leax    1,x
                stx     >digital_play_ptr
                lda     ,x
                sta     >digital_play_byte
digital_advance_done
                rti

; ---------------------------------------------------------------------------
; digital_show - the Digital Sequence screen, one softkey page at a time
;
;   uses:  A, B, X, Y, U
;
; THREE RECORDS, NOT THREE TITLES. The stock's page 2 paints a whole 80-byte
; DDRAM image per softkey page through menu_page_show and then writes its live
; fields over it with repaint_page_live_fields ($49A5), which for this mode
; calls repaint_sequence_editor ($5A0F). This is the same thing: the record's
; two lines, then the fields that change.
;
; What was here painted one invented title line and a 'Step:  Pat:  Bit:  In:'
; row over a sixteen-step model. Nothing on the instrument's screen said any
; of that.
;
; NO OPTION CHECK HERE, BECAUSE THE INSTRUMENT'S PAINTERS MAKE NONE. Nine
; stock routines read the options byte and not one of them paints a screen in
; this mode; the gate is build_option_dispatch_table ($8939), which builds the
; Main Selection list out of that byte, so a mode without its option is never
; offered. page1_tone.s's tone_show carries the full citation and the
; measurement - inside a live mode 'ST_ID 190;' clears the options and the
; instrument's banner does not change, while this firmware replaced line 1
; with a refusal. Nor does the ENTRY refuse: the stock's is not gated either.
; ---------------------------------------------------------------------------
digital_show
                ; FOUR RECORDS, IN THE INSTRUMENT'S ORDER. The table at $416B
                ; is four ten-byte records with the count byte $03 at $416A,
                ; and NEXT walks 0 to 3 and round: the TITLE ($40CA), then the
                ; base, period and levels ($411A), then the sequence editor
                ; ($4002), then the player ($4052). This firmware had three
                ; records in the order editor, settings, player, and no title
                ; at all - so the mode opened on the editor where the
                ; instrument opens on its title, and NEXT walked a different
                ; ring.
                lda     >digital_page
                beq     digital_show_title
                cmpa    #DIGITAL_PAGE_SETTINGS
                lbeq    digital_show_settings
                cmpa    #DIGITAL_PAGE_EDITOR
                lbeq    digital_show_editor
                lbra    digital_show_player

; ---------------------------------------------------------------------------
; digital_show_title - record 0, the mode's title screen
;
;   uses:  A, B, X
;
; No painter writes over it: page 2 gates every write on $3C1F and nothing is
; ever passed page 0, so all eighty columns are the record's own text.
; ---------------------------------------------------------------------------
digital_show_title
                lda     #LCD_LINE1
                ldx     #digital_title_l1
                ldb     #SVC_LABEL_LEN
                lbsr    ABI_lcd_write
                lda     #LCD_LINE2
                ldx     #digital_title_l2
                ldb     #SVC_LABEL_LEN
                lbra    ABI_lcd_write

; ---------------------------------------------------------------------------
; digital_show_editor - softkey page 0, the stock's record 2
;
;   uses:  A, B, X, Y, U
;
; Seq Index, Seq End, the sixteen-cell window between its brackets, and the f4
; label - which becomes Delete and Insert while an edit session is open, as
; repaint_sequence_editor ($5A0F) chooses between $403E and $40B6 on $3CCA.
; ---------------------------------------------------------------------------
digital_show_editor
                lda     #LCD_LINE1
                ldx     #digital_p0_l1
                ldb     #SVC_LABEL_LEN
                lbsr    ABI_lcd_write
                lda     #LCD_LINE2
                ldx     #digital_p0_l2
                ldb     #SVC_LABEL_LEN
                lbsr    ABI_lcd_write

                tst     >digital_edit           ; $5A33: the session decides
                beq     digital_show_ed_fields  ; which labels f3 and f4 carry
                lda     #DIGITAL_EDIT_POS
                ldx     #digital_p0_edit
                ldb     #DIGITAL_EDIT_LEN
                lbsr    ABI_lcd_write

digital_show_ed_fields
                ldx     >digital_index          ; $583C, four characters over
                lbsr    digital_number          ; the record's '126'
                lda     #DIGITAL_IX_POS
                ldb     #DIGITAL_IX_W
                lbsr    ABI_lcd_write

                ldx     >digital_end            ; $585F, over its '127'
                lbsr    digital_number
                lda     #DIGITAL_END_POS
                ldb     #DIGITAL_IX_W
                lbsr    ABI_lcd_write

                lbsr    digital_show_window

                ; AND THE CURSOR ON WHICHEVER FIELD IS SELECTED. The stock
                ; arms a real entry field for each of them - $5B24 and $5B4E
                ; call [$3C00] with 4 and 5, and the data cursor is armed by
                ; arm_data_digit_entry_field ($5866) at column $15+$3CD4 -
                ; so the operator can see which number the keypad will reach.
                lda     >digital_field
                cmpa    #DIGITAL_FIELD_INDEX
                bne     digital_show_ed_end
                lda     #DIGITAL_IX_POS
                lbra    ABI_lcd_cursor
digital_show_ed_end
                cmpa    #DIGITAL_FIELD_END
                bne     digital_show_ed_data
                lda     #DIGITAL_END_POS
                lbra    ABI_lcd_cursor
digital_show_ed_data
                cmpa    #DIGITAL_FIELD_DATA
                lbne    digital_show_done
                ldb     >digital_column+1       ; $5866: $15 plus the cursor's
                addb    #DIGITAL_WIN_POS        ; own cell. The column is
                tfr     b,a                     ; never above 15, so its low
                lbra    ABI_lcd_cursor          ; byte is the whole of it

; ---------------------------------------------------------------------------
; digital_show_window - the sixteen data cells
;
;   uses:  A, B, X, Y, U
;
; redraw_sequence_window ($5946). Three kinds of cell, and the difference
; between the last two is the whole reason the screen is readable:
;
;   a digit          the slot is inside the sequence
;   '.'  ($11)       past the end but inside what this base can hold - the
;                    room the sequence could grow into
;   ' '  ($10)       past the base's capacity; there is no such digit
;
; INSERT MODE OPENS A CELL. With $3CD7 set the cursor's own cell is drawn
; blank and every cell after it shows the digit that will be pushed along
; ($5960-$599D), so the operator sees where the next digit lands before typing
; it. The slot does not advance for that cell, which is what makes it an
; insertion rather than a blanked digit.
; ---------------------------------------------------------------------------
digital_show_window
                leas    -3,s                    ; 0,s-1,s the slot, 2,s the
                ldx     >digital_window         ; column
                stx     ,s
                clr     2,s
digital_show_cell
                lda     2,s
                cmpa    #DIGITAL_WINDOW
                bhs     digital_show_win_done

                tst     >digital_insert         ; $5960: the opened cell
                beq     digital_show_cell_slot
                ldx     ,s
                cmpx    >digital_index
                bne     digital_show_cell_slot
                lda     #' '
                ldb     2,s
                bsr     digital_show_put
                inc     2,s
                lda     2,s                     ; and it may have been the
                cmpa    #DIGITAL_WINDOW         ; sixteenth
                bhs     digital_show_win_done

digital_show_cell_slot
                ldx     ,s                      ; $599F: which kind of cell
                cmpx    >digital_end
                bls     digital_show_cell_digit
                cmpx    >digital_count
                bhs     digital_show_cell_past
                lda     #'.'                    ; $11: room to grow into
                bra     digital_show_cell_write
digital_show_cell_past
                lda     #' '                    ; $10: no such digit
                bra     digital_show_cell_write
digital_show_cell_digit
                lbsr    digital_digit_at        ; B = 0 to 15
                ldx     #digital_work
                lbsr    ABI_byte_to_hex         ; two characters; the digit is
                lda     >digital_work+1         ; the low one
digital_show_cell_write
                ldb     2,s
                bsr     digital_show_put
                ldx     ,s                      ; the slot advances here and
                leax    1,x                     ; not in the insert arm above
                stx     ,s
                inc     2,s
                bra     digital_show_cell
digital_show_win_done
                leas    3,s
                rts

; ---------------------------------------------------------------------------
; digital_show_put - one character into one cell of the window
;
;   entry: A = the character, B = the cell, 0 to 15
;   uses:  A, B, X
; ---------------------------------------------------------------------------
digital_show_put
                sta     >digital_work
                addb    #DIGITAL_WIN_POS
                tfr     b,a
                ldx     #digital_work
                ldb     #1
                lbra    ABI_lcd_write

; ---------------------------------------------------------------------------
; digital_number - an index as four characters, one-based
;
;   entry: X = the index, zero-based
;   exit:  X = four characters, ready to write
;   uses:  A, B, X, Y, U
;
; draw_index_number_field ($57A5) adds one before rendering ($57B7 ADDD
; #$0001) - the display counts from 1 and the arithmetic from 0, which is why
; the record's own text reads '126' beside an editor whose $3CA2 would be 125.
; blank_leading_zeros ($CCFF) then blanks the leading zeros over a count of
; four, and the last digit is never blanked, so an index of 0 shows '   1'.
; ---------------------------------------------------------------------------
digital_number
                leax    1,x
                stx     >chan_work+1
                clr     >chan_work
                ldx     #chan_work
                lbsr    ABI_uint24_to_text      ; eight digits, zeros kept
                ldx     #text_buffer+TEXT_DIGITS-DIGITAL_IX_W
                ldb     #DIGITAL_IX_W-1         ; the last one always stays
digital_number_blank
                lda     ,x
                cmpa    #'0'
                bne     digital_number_done
                lda     #' '
                sta     ,x+
                decb
                bne     digital_number_blank
digital_number_done
                ldx     #text_buffer+TEXT_DIGITS-DIGITAL_IX_W
                rts

; ---------------------------------------------------------------------------
; digital_show_settings - softkey page 1, the stock's record 1
;
;   uses:  A, B, X, Y, U
;
; The number base by name, the bit period, and the two levels the port drives
; for a one and for a zero. All four are on the record; all four have a live
; field written over them.
; ---------------------------------------------------------------------------
digital_show_settings
                lda     #LCD_LINE1
                ldx     #digital_p1_l1
                ldb     #SVC_LABEL_LEN
                lbsr    ABI_lcd_write
                lda     #LCD_LINE2
                ldx     #digital_p1_l2
                ldb     #SVC_LABEL_LEN
                lbsr    ABI_lcd_write

                ; THE BASE, BY NAME. display_base_name ($4959) writes three
                ; characters at $0C from $516F, $5173 and $5177. Without it an
                ; operator reads 245 and cannot tell octal from a count.
                ;
                ; THE NAME NEVER READ 'Oct' ONCE. This was written as CMPA /
                ; BLO / LDX #digital_base_oct / BEQ, and LDX sets Z from the
                ; address it loads - never zero - so the BEQ was never taken
                ; and every base but binary was named 'Hex'. Each compare now
                ; follows its load.
                lda     >digital_base
                ldx     #digital_base_hex
                cmpa    #DIGITAL_BASE_HEX
                beq     digital_show_based
                ldx     #digital_base_oct
                cmpa    #DIGITAL_BASE_OCT
                beq     digital_show_based
                ldx     #digital_base_bin
digital_show_based
                lda     #DIGITAL_BASE_POS
                ldb     #3
                lbsr    ABI_lcd_write

                lbsr    digital_show_period
                lbsr    digital_show_levels

                ; AND THE CURSOR ON THE SELECTED FIELD.
                lda     >digital_field
                cmpa    #DIGITAL_FIELD_BASE
                bne     digital_show_set_per
                lda     #DIGITAL_BASE_POS
                lbra    ABI_lcd_cursor
digital_show_set_per
                cmpa    #DIGITAL_FIELD_PERIOD
                bne     digital_show_set_lvl
                lda     #DIGITAL_PER_POS
                lbra    ABI_lcd_cursor
digital_show_set_lvl
                cmpa    #DIGITAL_FIELD_MARK
                bne     digital_show_set_spc
                lda     #DIGITAL_ON_POS
                lbra    ABI_lcd_cursor
digital_show_set_spc
                cmpa    #DIGITAL_FIELD_SPACE
                lbne    digital_show_done
                lda     #DIGITAL_OFF_POS
                lbra    ABI_lcd_cursor

; ---------------------------------------------------------------------------
; digital_show_period - the bit period, in the unit that suits it
;
;   uses:  A, B, X, Y, U
;
; The period is held in timer counts of ten microseconds. display_period
; ($4864) shows milliseconds up to a second and seconds above it, which is
; what the record's own ' Period   1.0  ms ' spells; the value is rendered
; here to one decimal place of a millisecond, which is the resolution one
; count gives.
; ---------------------------------------------------------------------------
digital_show_period
                ; period_field_render ($4771): five digits from
                ; u16_to_5_ascii_digits ($C912), at most three leading zeros
                ; blanked ($CCFF with 3) and the point after three ($CD50 with
                ; count 5, point 3), giving SIX characters at DDRAM $1E. This
                ; wrote the last six of eight raw digits with no point at all,
                ; so the field read 'Period000000  ms'.
                ldd     >digital_period
                std     >chan_work+1
                clr     >chan_work
                ldx     #chan_work
                clr     >format_trim            ; the period keeps its trailing
                lda     #DIGITAL_PER_POINT      ; zero - the $CD50 flag is 0
                sta     >format_point           ; here
                lda     #DIGITAL_PER_DIGITS
                ldb     #DIGITAL_PER_BLANK
                lbsr    ABI_format_fixed
                lda     #DIGITAL_PER_POS
                ldx     #format_text
                ldb     #DIGITAL_PER_W
                lbsr    ABI_lcd_write
                lda     #DIGITAL_PER_UNIT
                ldx     #digital_unit_ms
                ldb     #2
                lbra    ABI_lcd_write

; ---------------------------------------------------------------------------
; digital_show_levels - both level rows at once
;
;   uses:  A, B, X, Y, U
;
; They share a record line, so they are drawn together rather than one at a
; time: the mark level at ' On Lev' and the space level at ' Off Lev'.
; ampl_text renders each from its own channel record, the same routine every
; screen showing an amplitude uses - so a level reads identically here, on the
; tone screen and on the channel screens.
; ---------------------------------------------------------------------------
digital_show_levels
                ldb     #DIGITAL_MARK
                lda     #DIGITAL_ON_POS
                ldy     #DIGITAL_ON_UNIT*256+DIGITAL_ON_UW
                bsr     digital_show_one_level
                ldb     #DIGITAL_SPACE
                lda     #DIGITAL_OFF_POS
                ldy     #DIGITAL_OFF_UNIT*256+DIGITAL_OFF_UW
digital_show_one_level
                ; entry: A = the field's five digit columns' first, B = the
                ;        channel, Y high = the unit column, Y low = how many
                ;        characters of the label to write
                pshs    a,b,y                   ; 0,s digits, 1,s channel,
                                                ; 2,s unit column, 3,s width
                lbsr    digital_level_chan      ; X = that channel's record
                leau    CHAN_AMPL,x             ; U = its 24-bit level
                lbsr    ABI_ampl_autorange      ; $D022: the characters in
                pshs    b                       ; ampl_range_out, the unit in B

                lda     1,s                     ; THE SIGN COLUMN, blanked
                deca                            ; first - $458E writes one
                ldx     #digital_blank          ; character from $ED11 at the
                ldb     #1                      ; column before the digits
                lbsr    ABI_lcd_write

                lda     1,s                     ; the five digits
                ldx     #ampl_range_out
                ldb     #DIGITAL_LEV_W
                lbsr    ABI_lcd_write

                puls    b                       ; the unit the magnitude chose
                lbsr    ABI_unit_label
                lda     2,s
                ldb     3,s
                lbsr    ABI_lcd_write

                ; THE SIGN, against the first significant digit - the stock's
                ; level_field_redraw ($46AF) takes [$3CB2] into $3CC0 at $46C6
                ; and render_level_value_field ($45EB) ends by handing it to
                ; level_sign_right_justify ($4569), which scans the written
                ; characters for the first that is not a blank and puts the
                ; sign one column before it. $45D4 CMPB #$30 / LBEQ l45E8 is
                ; the other half: a first significant digit of '0' gets NO
                ; sign at all, which is why the instrument's Off Lev reads
                ; '     0 uV' with nothing in front of it.
                ldb     1,s                     ; THIS row's sign, not the
                lbsr    digital_sign_cell_of    ; selected row's
                lda     ,x                      ; the sign character
                ldy     #DIGITAL_LEV_W          ; how many were written
                ldx     #ampl_range_out
                ldb     ,s                      ; the digits' first column
                leas    4,s
                lbra    digital_sign_place

; ---------------------------------------------------------------------------
; digital_show_player - softkey page 2, the stock's record 3
;
;   uses:  A, B, X, Y, U
;
; The bit the cursor is on, its value between the brackets, and - over the
; left twenty columns - what the player is doing. draw_run_status_field
; ($48A8) writes one of three banners there or leaves the record's own text
; showing, and this is the same choice.
; ---------------------------------------------------------------------------
digital_show_player
                lda     #LCD_LINE1
                ldx     #digital_p2_l1
                ldb     #SVC_LABEL_LEN
                lbsr    ABI_lcd_write
                lda     #LCD_LINE2
                ldx     #digital_p2_l2
                ldb     #SVC_LABEL_LEN
                lbsr    ABI_lcd_write

                ; THE TWENTY COLUMNS ON THE LEFT OF LINE 1, and this firmware
                ; had the two stopped states the wrong way round.
                ; draw_run_status_field ($48A8) is the whole of it:
                ;
                ;   running      $48F0 writes $5144 or $5159, the banner
                ;   MANUAL       $4918 writes THE RECORD'S OWN first twenty
                ;                bytes, ' Bit  115  [1]', and only then paints
                ;                the bit number at $3CCB = 8 ($4922) and the
                ;                bit itself at $0E ($4932)
                ;   neither      $493A writes $40A2, ' Manual'
                ;
                ; So the instrument shows ' Manual' when it is stopped and the
                ; Bit row only while manual mode is on; this showed the Bit row
                ; when stopped and ' Manual' when manual. And the bit number
                ; and the bit digit belong to the manual branch alone - they
                ; were painted on every one.
                tst     >digital_running        ; running beats manual, and
                beq     digital_show_stopped    ; single beats continuous
                ldx     #digital_run_cont
                tst     >digital_single
                beq     digital_show_banner
                ldx     #digital_run_single
                bra     digital_show_banner
digital_show_stopped
                tst     >digital_manual
                bne     digital_show_bitrow     ; manual: the record's own
                ldx     #digital_run_manual     ; twenty columns already stand
digital_show_banner
                lda     #LCD_LINE1
                ldb     #DIGITAL_STATUS_LEN
                lbsr    ABI_lcd_write
                lbra    digital_show_player_done

digital_show_bitrow
                ldx     >digital_index_bit      ; $57C4: on this page the
                lbsr    digital_number          ; number field shows $3CA6,
                lda     #DIGITAL_BIT_POS        ; the cursor's BIT, not a
                ldb     #DIGITAL_IX_W           ; digit index
                lbsr    ABI_lcd_write

                ; AND THE BIT ITSELF, between the brackets. read_bit_at_cursor
                ; ($54DF) returns $64 for a cursor past the end and $51F6
                ; drops it; here the cell shows a space instead, which is what
                ; draw_seq_digit does with a value it cannot render ($58A8
                ; turns $10 into $20).
                ldx     >digital_index_bit
                cmpx    >digital_end_bit
                bhi     digital_show_bit_none
                lbsr    digital_bit_at          ; A = zero or non-zero
                tsta
                beq     digital_show_bit_zero
                lda     #'1'
                bra     digital_show_bit_put
digital_show_bit_zero
                lda     #'0'
                bra     digital_show_bit_put
digital_show_bit_none
                lda     #' '
digital_show_bit_put
                sta     >digital_work
                lda     #DIGITAL_VAL_POS
                ldx     #digital_work
                ldb     #1
                lbsr    ABI_lcd_write

                lda     >digital_field          ; and the cursor on the bit
                cmpa    #DIGITAL_FIELD_BIT      ; number while it is selected
                bne     digital_show_player_done
                lda     #DIGITAL_BIT_POS
                lbra    ABI_lcd_cursor
digital_show_player_done
digital_show_done
                rts

; ---------------------------------------------------------------------------
; digital_sign_place - a sign, right against the first significant digit
;
;   entry: A = the sign character, X = the field's characters as shown,
;          B = the DDRAM address of the first of them, Y = how many
;          characters the field holds
;   uses:  A, B, X, Y
;
; The stock's level_sign_right_justify ($4569): once the digits are on the
; display it blanks the column left of the field, walks right from there
; reading the display back ($D7A0 then $D761) while it sees ' ', stops
; without writing when the first non-blank is '0', and otherwise writes the
; sign byte $3CC0 one column left of that character. This walks the same
; characters in the buffer they were written from instead of reading the
; display back. The '0' case is the stock's own and its reason is unsettled
; there; it is kept because it is what the instrument shows.
;
; Only the field's own characters are looked at, so a field that is blank end
; to end - an entry with a sign and no digits yet - signs nothing.
; ---------------------------------------------------------------------------
digital_sign_place
                pshs    a                       ; the sign
digital_sign_place_scan
                lda     ,x+
                cmpa    #' '
                bne     digital_sign_place_found
                incb
                leay    -1,y
                bne     digital_sign_place_scan
                bra     digital_sign_place_none ; blank throughout
digital_sign_place_found
                cmpa    #'0'
                beq     digital_sign_place_none ; $45E8: a leading '0' gets none
                decb                            ; one column to its left
                tfr     b,a                     ; A = that DDRAM address
                leax    ,s                      ; X = the sign character
                ldb     #1
                lbsr    ABI_lcd_write
digital_sign_place_none
                puls    a,pc

; ---------------------------------------------------------------------------
; digital_level_sign_cell - where the selected level keeps its sign
;
;   exit:  X = the byte, holding DIGITAL_SIGN_PLUS or DIGITAL_SIGN_MINUS
;   uses:  A, B, X
;
; The stock's $3C11 for the On level and $3C12 for the Off, which
; select_level_field_pointers ($449D) aims $3CB2 at according to $3CB8 - the
; same selector its callers use for the value. Here the selector is
; digital_field, as it is for the record.
; ---------------------------------------------------------------------------
digital_level_sign_cell
                ldb     #DIGITAL_MARK
                lda     >digital_field
                cmpa    #DIGITAL_FIELD_MARK
                beq     digital_sign_cell_of
                ldb     #DIGITAL_SPACE

; ---------------------------------------------------------------------------
; digital_sign_cell_of - the same, for a named channel rather than the
;                        selected one
;
;   entry: B = DIGITAL_MARK or DIGITAL_SPACE
;   exit:  X = the byte
;   uses:  X
;
; BOTH LEVELS ARE ON THE SCREEN AT ONCE, so the row being drawn cannot be
; assumed to be the one the cursor is on. digital_show_levels draws the mark
; and the space in turn and each needs its own sign; reading digital_field
; there would have signed both rows with the selected level's sign.
; ---------------------------------------------------------------------------
digital_sign_cell_of
                ldx     #digital_sign_mark
                cmpb    #DIGITAL_MARK
                beq     digital_level_sign_cell_is
                ldx     #digital_sign_space
digital_level_sign_cell_is
                rts

; ---------------------------------------------------------------------------
; digital_level_take_sign - the entry's sign becomes the selected level's
;
;   uses:  A, X
;
; The stock's $4CF1-$4CF4 in enter_level_value ($4CDA): LDB >$241E / STB
; [>$3CB2], the sign entry_to_scaled_digits ($CDE1) copied out of the head
; of the entry buffer at $CE1B, stored into the selected level's cell.
; ---------------------------------------------------------------------------
digital_level_take_sign
                lbsr    digital_level_sign_cell
                lda     >digital_entry_sign
                sta     ,x
                rts

; ---------------------------------------------------------------------------
; digital_level_record - the record of the selected level's channel
;
;   exit:  X = the record, B = the channel number
;   uses:  A, B, X
;
; The mark is DIGITAL_MARK's channel and the space DIGITAL_SPACE's - the two
; sources the routing register switches between, so the level being edited is
; by construction the level the port drives.
; ---------------------------------------------------------------------------
digital_level_record
                ldb     #DIGITAL_MARK
                lda     >digital_field
                cmpa    #DIGITAL_FIELD_MARK
                beq     digital_level_chan
                ldb     #DIGITAL_SPACE
digital_level_chan
                pshs    b
                lda     #CHAN_RECORD
                mul
                ldx     #channel_records
                leax    d,x
                puls    b
                rts

; ---------------------------------------------------------------------------
; digital_incr_ampl_addr - the selected level's channel's amplitude step
;
;   exit:  X = its three bytes
;   uses:  A, B, X
;
; digital_level_record already says which channel the selected level belongs
; to - the mark's or the space's - and the step belongs to that channel.
; ---------------------------------------------------------------------------
digital_incr_ampl_addr
                lbsr    digital_level_record    ; B = the channel
                lda     #3
                mul
                ldx     #incr_ampl_ch
                leax    d,x
                rts

; ---------------------------------------------------------------------------
; digital_level_partner - the other of the mark/space pair
;
;   entry: B = one of them
;   exit:  Y = the other, in its low byte; B and X are untouched
;   uses:  Y
;
; program_dds_levels ($5223) programs BOTH levels in one call and shifts the
; second code onto the first's exponent at $5326, so ampl_set_direct cannot
; be handed one channel on its own - see ampl_pair_common in amplitude.s.
; This is what it is handed the other in.
; ---------------------------------------------------------------------------
digital_level_partner
                ldy     #DIGITAL_SPACE
                cmpb    #DIGITAL_MARK
                beq     digital_level_partner_out
                ldy     #DIGITAL_MARK
digital_level_partner_out
                rts

; ---------------------------------------------------------------------------
; digital_wave_dc - make a level channel a dc source, record and chip alike
;
;   entry: B = the channel
;   uses:  A, B, X, Y
;
; The record first, so the screen and ampl_pair_common see the same waveform
; the chip has, then wave_program through the ABI - the same order
; digital_sequence_mode_setup uses at $7274-$728C: STD ,X into the record,
; then the field read back ($727F LDX ,X) for unit_code_select_head.
; ---------------------------------------------------------------------------
digital_wave_dc
                pshs    b
                lda     #CHAN_RECORD
                mul
                ldx     #channel_records
                leax    d,x
                lda     #LBL_DC
                sta     CHAN_WAVE,x
                puls    a                       ; A = the channel
                ldb     #LBL_DC
                lbra    ABI_wave_program

; ---------------------------------------------------------------------------
; digital_entry_level - a fresh entry field for the level cursor's target
;
;   uses:  A, B, X
; ---------------------------------------------------------------------------
digital_entry_level
                clr     >entry_active
                clr     >digital_incr_mode      ; selecting cancels a pending
                                                ; INCR SET, as everywhere
                lda     #DIGITAL_SIGN_PLUS      ; A FRESH FIELD IS POSITIVE:
                sta     >digital_entry_sign     ; arm_numeric_entry_field
                                                ; ($AC35) pre-places '+' at
                                                ; the head of $239A for entry
                                                ; mode 2 ($ACE8 LDB #$2B / STB
                                                ; >$239A), the mode
                                                ; arm_level_entry_field
                                                ; ($6653) arms for this field
                lda     #ENTRY_DECIMAL
                ; FIVE DIGITS, WHICH IS THE FIELD. This armed the whole text
                ; buffer, so a sixth digit went in and a level ten times the
                ; instrument's could be typed. Driven on the emulator
                ; 2026-09-12: the stock takes 100001 on the On Lev field and
                ; shows +10.00 mV, the same as 10000 - the sixth keystroke
                ; reaches a full field and is dropped. DIGITAL_LEV_W is the
                ; five the row renders.
                ldb     #DIGITAL_LEV_W
                lbra    ABI_entry_begin

; ---------------------------------------------------------------------------
; digital_commit_level - ENTER on a level field
;
;   uses:  A, B, X, Y, U
;
; The stock's $4CDA: accept_level_entry ($4C51) parses against the $EA62 =
; 10,000,000 ceiling and program_dds_levels ($5223) reprograms the pair.
; ampl_set is parse-check-store-program in one routine, against the
; destination's own ceiling, and it reports its own refusal - so a level
; past the channel's limit beeps and the setting stands, exactly as
; accept_level_entry restores on error $34. INCR SET diverts the same entry
; to incr_ampl, the shared step store, matching $4D26 - the stock's arm [1]
; for the step size instead of the value.
; ---------------------------------------------------------------------------
digital_commit_level
                tst     >entry_active
                beq     digital_level_sign_only ; nothing typed: the sign alone
                tst     >entry_count            ; or every digit taken back by
                beq     digital_level_sign_only ; BACKSPACE - the same case:
                                                ; $4CDA stores the sign for an
                                                ; empty entry and $CDE1's $FF
                                                ; skips the value
                lbsr    ABI_entry_value
                bcs     digital_level_refused
                ; THE DIGITS ARE IN THE UNIT THE KEY NAMED - microvolts,
                ; millivolts or volts - and ampl_set_direct below wants
                ; microvolts, which is what unit_decades lands.
                lbsr    digital_entry_scale
                bcs     digital_level_refused
digital_level_scaled
                tst     >digital_incr_mode
                beq     digital_level_value
                clr     >digital_incr_mode
                lbsr    digital_incr_ampl_addr  ; the step size, this
                ldu     #entry_result           ; every screen that steps a
                lbsr    ABI_copy24              ; level
                bra     digital_level_rearm

digital_level_value
                lbsr    digital_level_record    ; X = record, B = channel
                lbsr    digital_level_partner   ; Y = the other of the pair
                ldu     #entry_result
                lda     >digital_entry_sign     ; A = the entry's sign: what
                lbsr    ABI_ampl_set_direct     ; $4CF1 stores and
                                                ; program_dds_levels folds
                bcs     digital_level_refused
                lbsr    digital_level_take_sign ; THE SIGN GOES WITH THE VALUE,
                                                ; and only with an accepted
                                                ; one: $4CDA stores it at
                                                ; $4CF1 behind the $3CDC test
                                                ; at $4CE8, so a refused entry
                                                ; ($34) leaves both alone
digital_level_rearm
                lbsr    digital_entry_level
digital_level_shown
                lbra    digital_show_armed      ; every level $23 arm re-arms:
                                                ; [$3C00] at $4D1C and $4D54
digital_level_refused
                lbsr    ABI_error_beep          ; recorded by the setter; the
                bra     digital_level_rearm     ; setting stands
digital_level_sign_only
                ; ENTER WITH NO DIGITS COMMITS THE SIGN ALONE. accept_level_entry
                ; ($4C51) raises no error for a digit count of $FF - nothing
                ; typed - so enter_level_value ($4CDA) finds $3CDC clear at
                ; $4CE8 and still stores the entry's sign through [$3CB2] at
                ; $4CF1 before it redraws and re-arms; and the sign it stores
                ; is the '+' the field was armed with unless MINUS replaced it.
                ; That is how a '-' level is made positive again. With INCR
                ; SET armed the field is the unsigned increment - $4D26 stores
                ; no sign - and nothing is stored.
                tst     >digital_incr_mode
                bne     digital_level_shown
                lbsr    digital_level_take_sign
                ; AND THE CHIP FOLLOWS: $4CDA calls program_dds_levels at
                ; $4CF6 on this path too, right after the $4CF1 store, so a
                ; sign committed alone reprograms the level with it. The
                ; value is the record's own, which ampl_set copies back
                ; over itself and re-checks against the destination it has
                ; now.
                lbsr    digital_level_record    ; X = record, B = channel
                lbsr    digital_level_partner   ; Y = the other of the pair
                leau    CHAN_AMPL,x
                lda     >digital_entry_sign
                lbsr    ABI_ampl_set_direct
                bcs     digital_level_refused
                bra     digital_level_rearm

; ---------------------------------------------------------------------------
; digital_bus_level - the $23 a bus level's unit posts
;
;   uses:  A, B, X, Y, U
;
; enter_level_value ($4CDA) with the number the bus left: already scaled to
; microvolts by remote_units_page_level, so it joins digital_commit_level after
; its own scaling, and carries the sign the field was armed with. The level
; stays armed, as $238F does.
; ---------------------------------------------------------------------------
digital_bus_level
                lda     >rmt_pend_kind
                cmpa    #RK_DIGLEVEL
                bne     digital_bus_level_done
                lda     >digital_field
                cmpa    #DIGITAL_FIELD_MARK
                beq     digital_bus_level_go
                cmpa    #DIGITAL_FIELD_SPACE
                bne     digital_bus_level_done
digital_bus_level_go
                ldx     #entry_result
                ldu     #rmt_val
                lbsr    ABI_copy24
                lbsr    digital_level_scaled
                lda     #RK_DIGLEVEL
                sta     >rmt_pend_kind
                lda     #$02
                sta     >rmt_seq_owner
digital_bus_level_done
                rts

; ---------------------------------------------------------------------------
; digital_step_level - an arrow on a selected level
;
;   entry: the direction, +1 up or $FF down, is the byte digital_step
;          pushed before dispatching here; it is at DIG_STEP_DIR,s once
;          this routine's own temporaries are below it
;   uses:  A, B, X, Y, U
;
; The stock's step_level_by_increment ($4EB0), the $3CAC = 3 arm of the step
; dispatch, instruction by instruction:
;
;   $4EB0  LDB [>$3CB2] / CMPB #$2D - when the level's sign is '-' the
;          direction the caller passed is inverted in the caller's own slot
;          ($4EBA LDD >$000E,S / EORB #$01 / STD >$000E,S), so 'up' on a
;          negative level moves it towards zero
;   $4EC6  up: add24 ($D392) of the increment [$3CB0] into the level [$3CAE]
;          at $221C, and the carry clears the success flag the dispatcher
;          seeded with 1 at $4EA0 ($4EE7 zflag_to_bool)
;   $4EEF  down: sub24 ($D3C6) the same way round, and on a borrow ($4F09)
;          sub24 the OTHER way round - increment minus level - and toggle
;          [$3CB2] between '+' ($4F27-$4F29) and '-' ($4F30-$4F32). The success flag
;          is left standing on that path
;   $4F36  with the flag standing, check the result against the $EA62
;          ceiling, copy it into [$3CAE] and call program_dds_levels;
;          without it, only redraw and re-arm
;
; Here the level is a magnitude on a channel record and the ceiling check,
; store and programming are ampl_set's, so the arithmetic runs on a stack
; temporary and ampl_set takes it from there. ONE DEPARTURE, STATED: the
; stock toggles the sign cell before its ceiling check, which cannot fail on
; that path because both operands passed accept_level_entry's own $EA62
; check at $4C51; here the increment is stored unchecked by
; digital_commit_level, so the new sign is held beside the temporary and
; committed only when ampl_set accepts, and the screen, the cell and the chip
; never disagree.
; ---------------------------------------------------------------------------
digital_step_level
                leas    -4,s                    ; 0,s..2,s the stepped
                                                ; magnitude, 3,s the sign it
                                                ; will carry; the direction
                                                ; the caller pushed is now at
DIG_STEP_DIR    equ     4               ;       this offset
                lbsr    digital_level_sign_cell ; X = the level's sign byte
                lda     ,x
                sta     3,s                     ; carried through unchanged
                                                ; unless the step crosses zero
                cmpa    #DIGITAL_SIGN_MINUS     ; $4EB0 LDB [>$3CB2] / CMPB #$2D
                bne     digital_step_lvl_dir
                neg     DIG_STEP_DIR,s          ; $4EBA-$4EC2: the direction
                                                ; is inverted in the caller's
                                                ; slot; +1 and $FF negate
digital_step_lvl_dir
                lbsr    digital_level_record
                leau    CHAN_AMPL,x
                leax    ,s                      ; temp = the stored magnitude
                lbsr    ABI_copy24

                pshs    x                       ; the temp, over the call
                lbsr    digital_incr_ampl_addr
                tfr     x,u
                puls    x
                tst     DIG_STEP_DIR,s
                bmi     digital_step_lvl_down
                lbsr    ABI_add24               ; $4EC6: level + increment
                bcs     digital_step_lvl_no     ; the carry clears the success
                                                ; flag ($4EE5-$4EEA): nothing
                                                ; stored
                bra     digital_step_lvl_go
digital_step_lvl_down
                lbsr    ABI_sub24               ; $4EEF: level - increment
                bcc     digital_step_lvl_go

                ; BELOW ZERO: THE STEP CROSSES IT. $4F09-$4F1B sub24 the other
                ; way round, increment minus level, which cannot borrow because
                ; the level was the smaller; $4F1D-$4F35 toggle the sign.
                leax    ,s
                pshs    x                       ; the temp, over the call
                lbsr    digital_incr_ampl_addr
                tfr     x,u
                puls    x
                lbsr    ABI_copy24              ; temp = the increment
                lbsr    digital_level_record
                leau    CHAN_AMPL,x
                leax    ,s
                lbsr    ABI_sub24               ; temp = increment - level
                lda     3,s
                eora    #DIGITAL_SIGN_FLIP      ; '+' <-> '-'
                sta     3,s
digital_step_lvl_go
                lbsr    digital_level_record    ; X = record, B = channel
                lbsr    digital_level_partner   ; Y = the other of the pair
                leau    ,s                      ; U = the stepped magnitude
                lda     3,s                     ; A = the sign it will carry
                lbsr    ABI_ampl_set_direct     ; check, store, program
                bcs     digital_step_lvl_no     ; refused: the setting stands
                lbsr    digital_level_sign_cell ; and the sign is committed
                lda     3,s                     ; with the value it belongs to
                sta     ,x
digital_step_lvl_out
                leas    4+1,s                   ; the temporaries and the
                lbra    digital_show_armed      ; l4f72: re-armed on every path
digital_step_lvl_no
                lbsr    ABI_error_beep
                bra     digital_step_lvl_out

; ---------------------------------------------------------------------------
; digital_sequence_open - the mode entry point, reached through $4001
;
;   exit:  the digital port screen is showing, stopped, at step 0
;   uses:  A, B, X, Y, U
;
; THE INSTRUMENT IS PRESET ON ENTRY, like the tone modes and like the stock.
; This used to say the opposite - that the port is deliberately left alone
; because it "drives whatever the operator has wired to the rear connector"
; and clearing it might operate a relay nobody asked for. That reasoning was
; about eight parallel output lines, and there are none: $0600 is an input.
; What entering this mode actually takes over is the channels and the Out1
; routing, and leaving those driving from a previous mode is the hazard.
; ---------------------------------------------------------------------------
; ---------------------------------------------------------------------------
; digital_cursor_step - move the data cursor one digit
;
;   entry: B = $01 to move up the pattern, $FF to move down
;   exit:  carry SET if nothing moved
;   uses:  A, B, X
;
; step_sequence_field ($5E0F) with $3CAC = 9, its data-cursor arm at $5E1D.
; Three bounds, and they are not the same bound:
;
;   - AT THE CAPACITY the cursor does not move but the caller is still told it
;     changed ($5E2A CMPX >$3CCE / LBCC l5e4c, and l5e4c falls into the
;     changed path with the flag still 1). So holding the arrow at the top of
;     the pattern keeps repainting the same cell rather than going quiet.
;   - PAST THE END it reports nothing changed ($5E35 CMPX >$3CA4 / LBHI
;     l5e48, which clears the flag). The cursor may sit on the end digit and
;     go no further into digits that are not in the sequence.
;   - AT ZERO, going down, likewise nothing changed ($5E53 CMPX #$0000 /
;     LBLS l5e65).
;
; THE WINDOW FOLLOWS THE CURSOR AND NEVER JUMPS. Sixteen cells are shown; if
; the cursor has gone below the window the window starts at the cursor, and if
; it has gone above the sixteenth cell the window ends at the cursor
; ($5E76-$5EA1). Anywhere in between, the window does not move at all - which
; is what makes a held arrow scroll one cell at a time instead of paging.
; ---------------------------------------------------------------------------
digital_cursor_step
                tstb
                bmi     digital_cursor_down

                ldx     >digital_index          ; $5E2A: at the capacity it
                cmpx    >digital_max            ; stops, and still counts as a
                bhs     digital_cursor_moved    ; move
                cmpx    >digital_end            ; $5E35: but past the END it
                bhi     digital_cursor_stuck    ; does not
                leax    1,x
                stx     >digital_index
                bra     digital_cursor_moved
digital_cursor_down
                ldx     >digital_index          ; $5E53: and zero is the floor
                beq     digital_cursor_stuck
                leax    -1,x
                stx     >digital_index

digital_cursor_moved
                ldx     >digital_index          ; $5E76: the window follows,
                cmpx    >digital_window         ; and only when it has to
                blo     digital_cursor_left
                ldd     >digital_window         ; $5E8A: window+15 is the last
                addd    #DIGITAL_WINDOW-1       ; cell shown
                cmpd    >digital_index
                bhs     digital_cursor_column
                ldd     >digital_index          ; above it: the cursor becomes
                subd    #DIGITAL_WINDOW-1       ; the last cell
                std     >digital_window
                bra     digital_cursor_column
digital_cursor_left
                stx     >digital_window         ; below it: the first cell

digital_cursor_column
                ldd     >digital_index          ; $5E9B: which cell of the
                subd    >digital_window         ; sixteen the cursor is in
                std     >digital_column
                lbsr    digital_bits_index      ; $5ED4: and the bit it sits
                                                ; on, for the readout and for
                                                ; manual mode
                andcc   #~CC_CARRY
                rts
digital_cursor_stuck
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; digital_cold_init - the pattern and its indices as the instrument makes them
;
;   uses:  A, B, X, Y, U
;
; init_sequence_editor ($659A) with argument 0, instruction for instruction.
; It is reached on every front-panel entry to the mode:
; select_page2_digital_sequence ($41D8 in page 0) is called from
; option_feature_enter ($8AEA) item 4, which pushes ONE ZERO WORD at
; $8B39-$8B41 before its JSR, and enter_digital_sequence_mode ($7364) passes
; its own argument straight through to init_sequence_editor at $7303. So the
; front panel's entry is the cold one and it PRELOADS THE PATTERN. Only a
; register recall enters with 1, and that path restores the saved pattern
; instead (registers.s:register_seq_unstage_dig).
;
; THE 250 HEX DIGITS ARE 0123456789ABCDEF REPEATING. $65BB writes digit n as
; n AND $0F for every n below $00FA, with the base already set to 2 - so the
; instrument powers into its editor showing a ramp, not zeros, and an
; operator who has never typed a pattern still has something to clock out.
;
; THE CURSOR'S BIT IS SET TO ZERO AND NOT COMPUTED. $65E7 stores 0 into $3CA6
; where digital_bits_index would give 3 - the last bit of hex digit 0. That is
; the instrument's own initial value and it is copied rather than corrected:
; the first thing that moves the cursor recomputes it.
; ---------------------------------------------------------------------------
digital_cold_init
                ; THE PERIOD FIRST, and it is TEN counts. mode_cold_init
                ; ($6FFF) writes $000A into $3C9E at $70E2-$70E5 and $000A into
                ; the step $3CA0 at $70E6-$70E9, and one count is a hundredth
                ; of a millisecond, so the instrument comes up showing
                ; ' Period    .10 ms '. This firmware left the cell at zero
                ; until the first run, when a fallback put a whole millisecond
                ; in it, and the field read the raw digits of nothing.
                ldd     #DIGITAL_PERIOD_RESET
                std     >digital_period
                std     >incr_digital

                ; AND THE OFF LEVEL IS ZERO. mode_cold_init ($6FFF) copies the
                ; 24-bit zero at $EA58 into $3C08 at $7120-$7130, where the On
                ; level comes from channel 0's record+10 at $70F9-$711C - which
                ; is 140 microvolts, the level init_channel_blocks ($C4F0)
                ; leaves there. The instrument therefore comes up reading
                ; ' On Lev   +140 uV' and ' Off Lev      0 uV'. This firmware
                ; takes both rows straight from their channel records, and
                ; since those records now carry the stock's 140 the Off row
                ; read +140 as well.
                ldb     #DIGITAL_SPACE
                lbsr    digital_level_chan      ; X = the space channel's
                clr     CHAN_AMPL,x             ; record
                clr     CHAN_AMPL+1,x
                clr     CHAN_AMPL+2,x

                lda     #DIGITAL_BASE_HEX       ; $65B1: LDB #$02 / STB >$3C20
                sta     >digital_base           ; - the fill below is in hex,
                                                ; so the base goes first

                ldx     #$0000                  ; $65BB: 250 digits, n AND $0F
digital_cold_fill
                cmpx    #DIGITAL_N_HEX          ; $65BF: CMPX #$00FA / BCC out
                bhs     digital_cold_filled
                tfr     x,d
                andb    #$0F
                tfr     b,a                     ; the value in A, index in X
                pshs    x
                lbsr    digital_digit_put
                puls    x
                leax    1,x
                bra     digital_cold_fill
digital_cold_filled

                ldx     #$0000                  ; $65E7-$6602
                stx     >digital_index
                ldx     #DIGITAL_N_HEX-1        ; $00F9, the last hex digit
                stx     >digital_end
                ldx     #$0000                  ; and $3CA6 literally zero
                stx     >digital_index_bit
                ldx     #DIGITAL_PATTERN_BITS-1 ; $03E7 - every bit is in the
                stx     >digital_end_bit        ; sequence, which is what 250
                stx     >digital_last_bit       ; hex digits come to

; ---------------------------------------------------------------------------
; digital_editor_derive - the editor put back over the sequence that is there
;
;   uses:  A, B, X, and whatever digital_limits uses
;
; init_sequence_editor ($659A) from l6603, which EVERY reason reaches: the
; fill, the index and the end above are its reason-0 branch alone, and on 1
; and 2 it goes straight here - the capacity for the base, the field pointer,
; the window on the cursor and the first cell. digital_cold_init falls into
; it; a recall and a keep-state entry call it over the sequence they keep.
; ---------------------------------------------------------------------------
digital_editor_derive
                lbsr    digital_limits          ; $660F: the count and the
                                                ; highest index for the base

                ldx     #digital_index          ; $6619: $3CD0 points at
                stx     >digital_field_ptr      ; $3CA2, so the number field
                                                ; edits the index
                ldx     >digital_index          ; $6621: the window starts on
                stx     >digital_window         ; the cursor
                ldx     #$0000                  ; $6629: and the cursor is in
                stx     >digital_column         ; its first cell
                rts

digital_sequence_open
                ; NO OPTION CHECK. The stock's page-1 and page-2 routines never
                ; read installed_options - docs/routine-index.txt lists every
                ; stock reader and none is on these pages. The option gates
                ; the Main Selection's slots, once, at power-on (main_menu.s,
                ; main_menu_latch). A gate here, read live, refused a mode the
                ; instrument opens after ST_ID clears $3FFC: seed 11 step 13.
                ;
                ; THE ENTRY REASON arrives in U (MODE_COLD in scratch.inc).
                ; digital_sequence_mode_setup ($7187) tests it at $0008,s:
                ; unless it is 2, instrument_preset; if it is 1,
                ; recall_state_register; if it is 0, mode_cold_init and a
                ; jump to l7261, past the reapply and the saved record that
                ; reasons 1 and 2 take. Everything below down to
                ; digital_sequence_levels is the cold branch; anything that is
                ; not a recall or a keep-state entry is taken as cold.
                cmpu    #MODE_RECALL
                lbeq    digital_sequence_recall
                cmpu    #MODE_KEEP
                lbeq    digital_sequence_keep
                lbsr    ABI_instrument_preset   ; QUIESCE FIRST, as the stock
                                                ; does at every mode entry -
                                                ; and note this replaces the
                                                ; old "the port is NOT cleared
                                                ; on entry" rule below, which
                                                ; was reasoning about eight
                                                ; parallel lines that do not
                                                ; exist.
                lbsr    ABI_channel_records_init ; AND THE RECORDS BACK TO
                                                ; THEIR DEFAULTS FIRST. A
                                                ; sequence mode takes the
                                                ; channels over and starts
                                                ; them from the instrument's
                                                ; own defaults, not from what
                                                ; the last mode left:
                                                ; seq_mode_defaults ($5224)
                                                ; calls init_channel_blocks
                                                ; ($C4F0) at $5239, between
                                                ; its preset and its reapply.
                ; BOTH LEVEL CHANNELS ARE dc SOURCES, AND THE RECORD SAYS SO
                ; BEFORE ANYTHING IS APPLIED. digital_sequence_mode_setup
                ; ($7187) does $7261 CLR >$23BE / cache_channel_record_ptr(0),
                ; then $726E LDX >$23BF / $7271 LEAX <$1F,X / $7274 LDD #$0004
                ; / $7277 STD ,X - waveform 4, dc, into channel 0's record -
                ; and hands the word back to unit_code_select_head ($E38F),
                ; the chip's waveform writer; mode_cold_init ($6FFF) writes
                ; the same $0004 into channel 2's record+$1F before its own
                ; $E38F call. The waveform is what makes scale_to_dds_code
                ; take its signed dc arm ($D49E CMPX #$0004), so without it
                ; the sign would be stored and never reach the chip.
                ;
                ; IT USED TO RUN AFTER THE REAPPLY BELOW, which coded channel
                ; 0's 140 uV on the sine arm and then changed the waveform
                ; under it. Measured through the differential harness on
                ; 2026-09-13: opening this mode left the stock's channel 0 at
                ; level code 3156 and this firmware's at 1879.
                ldb     #DIGITAL_MARK
                lbsr    digital_wave_dc
                ldb     #DIGITAL_SPACE
                lbsr    digital_wave_dc

                ; AND CHANNEL 1 CARRIES 100 kHz. mode_cold_init ($6FFF) forces
                ; $23BE to 1 at $7040, re-caches the record pointer with
                ; cache_channel_record_ptr ($C21A), copies the three bytes of
                ; d4193 - $0F $42 $40, a million tenths of a hertz - into the
                ; record with copy3 ($D37D), applies them with
                ; write_channel_reg_08 ($E2C1), zeroes the record's level from
                ; the 24-bit zero at $EA58 and programs that with
                ; dispatch_channel_function ($C069). Why the instrument wants
                ; a carrier on a channel the mark/space pair never uses is not
                ; established by the ROM - d4193 is a literal with no
                ; arithmetic behind it - but it is there on purpose, and
                ; leaving it out left this firmware's channel 1 at 1 kHz where
                ; the instrument's is at 100 kHz. tone_sequence_open has the
                ; same block with page 1's own constant.
                ;
                ; The record is written BEFORE the reapply rather than after,
                ; so both values reach the chip through the one path that
                ; programs a record; the stock takes two passes and lands the
                ; same state.
                ldb     #DIGITAL_CARRIER        ; digital_level_chan is the
                lbsr    digital_level_chan      ; record lookup for any
                                                ; channel, not just the pair
                lda     #$0F                    ; d4193, byte for byte, into
                sta     ,x                      ; CHAN_FREQ - offset 0, so the
                lda     #$42                    ; zero offset is written bare
                sta     1,x
                lda     #$40
                sta     2,x
                clr     CHAN_AMPL,x             ; and no level on it, which is
                clr     CHAN_AMPL+1,x           ; what the copy from $EA58
                clr     CHAN_AMPL+2,x           ; leaves

                ; AND EVERY DESTINATION OFF BEFORE THE APPLY.
                ; reapply_all_channels ($C5B1) parks every record's
                ; destination at $C5E8-$C5F2 BEFORE it applies anything, so a
                ; sequence mode's apply finds four Off channels and programs
                ; the levels of none it has not been told to keep - the mode
                ; is taking the channels over. This firmware's
                ; channel_reapply_all is only the SECOND pass, so without this
                ; call the apply found four records still routed and put
                ; 140 uV on all four: measured on 2026-09-13, the stock came
                ; out of this entry at level codes (3156, 0, 0, 0) and this
                ; firmware at (1879, 1879, 1879, 1879).
                ; tone_sequence_open and dtmf_sequence_open carry the same
                ; call for the same reason.
                lbsr    ABI_channel_park_destinations

                lbsr    ABI_channel_reapply_all ; AND PUT THEM BACK. The
                                                ; preset above resets the
                                                ; synthesis chip, so without
                                                ; this every channel came out
                                                ; of a mode change silent -
                                                ; frequency, level and phase
                                                ; all zero - where the stock
                                                ; leaves them exactly as they
                                                ; were. It follows its own
                                                ; preset with
                                                ; reapply_all_channels
                                                ; ($C5B1) at every sequence
                                                ; mode entry, and the
                                                ; differential harness caught
                                                ; the difference on its first
                                                ; run: seed 1, the block that
                                                ; opens Tone Sequence with
                                                ; four channels at 1 kHz and
                                                ; 140 uV.
                ; AND CHANNEL 0's FILTER LINE GOES IN. mode_cold_init ($6FFF)
                ; finishes with set_digital_output_bit ($51C8)(0) and
                ; set_channel_byte_24ec ($F713)(0,1), and $F713 is the routine
                ; that OWNS the per-channel filter byte at $24EC+channel: it
                ; stores its argument there and falls into
                ; switch_channel_latch_bit0 ($F692), which drives the latch
                ; bit from the byte it has just stored. ampl_filter_force is
                ; that pair, so the 1 below is not a constant standing in for
                ; a stored byte - it is the literal second argument the stock
                ; passes, and the store is what makes it the stored byte.
                ; seq_mode_defaults ($5224) does the same at $5378 with the
                ; same index and the same value, which is why
                ; tone_sequence_open carries the identical call.
                ;
                ; Measured on 2026-09-13: after this entry the stock's channel
                ; 0 latch reads $81 and this firmware's read $00, and bit 7 is
                ; the probe bit the owner's ruling waives - bit 0 is not.
                lda     #LATCH_FILTER
                clrb                            ; channel 0
                lbsr    ABI_filter_force

                ldx     #digital_key
                lbsr    ABI_screen_install
                lda     #SEQKIND_DIGITAL        ; AND THIS IS THE SEQUENCE A
                sta     >seq_kind_live          ; SAVE WILL CARRY, the register
                                                ; having one slot for whichever
                                                ; was live
                ; AND THE MODE OPENS ON ITS TITLE RECORD, whatever record the
                ; last visit left it on. menu_show ($8A08) installs the mode's
                ; record table and does CLR >$268E as it does so, and
                ; enter_digital_sequence_mode ($7364) calls it before
                ; digital_sequence_mode_setup ($7187) - so a re-entry always
                ; comes up on record 0. tone_sequence_open carries the same
                ; CLR for the two page-1 modes and this one did not have it,
                ; so the three chains paged out of step with each other and
                ; with the instrument.
                ;
                ; Driven on both, 2026-09-13: walk two records into Digital
                ; Sequence, leave to the Main Selection and open it again -
                ; the instrument comes up on '** Digital Sequence Mode **' and
                ; this firmware came up on 'Seq Index'. Every NEXT after that
                ; landed on a different record on the two machines, which is
                ; what the differential harness reported as seed 23, step 13.
                clr     >digital_page           ; $268E
                clr     >active_record          ; which a save carries

                clr     >digital_running        ; stop the sequence and start
                ldx     #$0000                  ; the next run from the top -
                stx     >digital_bit_index      ; the counter is sixteen bits
                clr     >digital_manual         ; and out of manual mode:
                                                ; mode_cold_init ($6FFF) CLR
                                                ; >$3C04 at $70C8
                lda     #DIGITAL_SIGN_PLUS      ; BOTH LEVELS POSITIVE: $70D9
                sta     >digital_sign_mark      ; and $70DE store $2B into
                sta     >digital_sign_space     ; $3C11 and $3C12, six
                                                ; instructions after that CLR.
                                                ; ABI_instrument_preset has
                                                ; just reset the magnitudes
                                                ; these belong to, so the
                                                ; signs reset with them

                lbsr    digital_cold_init       ; THE WHOLE EDITOR STATE, not
                                                ; just the base: the 250 hex
                                                ; digits, the index, the end,
                                                ; the three bit indices, the
                                                ; capacity and the window.
                                                ; Entering the mode from the
                                                ; front panel is
                                                ; init_sequence_editor's
                                                ; argument 0 and that is what
                                                ; argument 0 does.

                ; AND THE MARK LEVEL GOES ON THE CHIP LAST.
                ; digital_sequence_mode_setup ($7187) clears $3CB8, calls
                ; select_level_field_pointers(0) and then program_dds_levels(0)
                ; at $72AE - after the reapply and the dc waveform, so the
                ; level is coded on the dc arm. The reapply above has just
                ; parked every destination and programmed four zero levels,
                ; and this is the one channel whose level survives a
                ; sequence-mode entry; without it the port had no mark level
                ; at all. Measured on 2026-09-13: the stock leaves channel 0
                ; at level code 3156 and this firmware left it at 0.
                ;
                ; The stock programs it BEFORE init_sequence_editor ($659A)
                ; and this after digital_cold_init, because the Off level the
                ; stock has already put in $3C08 lives in the space channel's
                ; own record here and digital_cold_init is what zeroes it. The
                ; order of the words on the bus differs by that much; the
                ; state the chip ends in does not.
                ; ampl_set_direct IS program_dds_levels ($5223) - it takes the
                ; pair and puts both codes on one exponent, which is why
                ; digital_level_value hands it the partner - and it is handed
                ; the level the record already holds, staged through
                ; pool_digital so the setter is not given a pointer into the
                ; record it writes. dispatch_channel_function was tried here
                ; first and programmed a zero: it honours the destination the
                ; park above cleared, and the mark level is not a routed
                ; destination's level.
                ;
                ; THE SPACE IS THE ONE HANDED IN, AND THE MARK IS THE PARTNER,
                ; because on this entry it is the MARK's code that goes
                ; through the fold and the unfold. Both levels range to
                ; exponent 15 - 140 microvolts and zero - so the shift between
                ; them is nothing, and a fold with a zero shift still costs
                ; one: $BDE6/$530C makes $1000-code and $BE2A/$5333 makes
                ; $FFF-that, which is code-1. scale_to_dds_code ($D3EC) codes
                ; +140 uV dc as $C55 and the stock programs $C54. Measured on
                ; 2026-09-13 with the mark handed in instead: channel 0 came
                ; out at 3157 against the instrument's 3156.
                ;
                ; FROM HERE TO THE END IS l7261, WHICH EVERY REASON RUNS, and
                ; the recall and keep-state entries below join it here.
digital_sequence_levels
                ldb     #DIGITAL_SPACE
                lbsr    digital_level_chan      ; X = the space's record
                leau    CHAN_AMPL,x             ; U = the level in it - zero,
                ldx     #pool_digital           ; digital_cold_init having
                lbsr    ABI_copy24              ; just cleared it
                ldb     #DIGITAL_SPACE
                lbsr    digital_level_chan      ; X = the record, B = channel
                lbsr    digital_level_partner   ; Y = the mark, the other of
                ldu     #pool_digital           ; the pair
                lda     >digital_sign_space     ; the '+' set above
                lbsr    ABI_ampl_set_direct

                ; AND REGISTER $22 TO $22, THE SPACE MUX CODE.
                ; digital_sequence_mode_setup ($7187) calls program_dds_levels
                ; ($5223) at $72C0 and set_digital_output_bit ($51C8) with 0
                ; at $72CF right after it - the same write digital_drive_bit's
                ; SPACE arm makes, since set_digital_output_bit(0) is `CMPX
                ; #0 / LBNE / LDB #$22` before it hands the whole byte to
                ; dds_write_reg_22 ($51A5). program_dds_levels' own $22 <- $23
                ; is a transient the routine restores before it returns (see
                ; its header), so $72CF's direct write is the one that stands
                ; once the entry finishes. This page had no writer for it at
                ; mode entry at all - digital_drive_bit only runs once the
                ; sequence is clocking - so register $22 came out of a
                ; Digital Sequence entry however an earlier screen had left
                ; it. Measured through the differential harness as this
                ; firmware's $24 against the stock's $22.
                ldx     #DIGITAL_MUX_SPACE
                ldb     #DDS_PORT_MUX_01
                lbsr    ABI_dds_write

                ; AND REGISTER $1C TO $02. digital_sequence_mode_setup
                ; ($7187) ends with `LDB #$02 / ... / LBSR dds_write_reg_1c`
                ; at $72E1-$72F0, the same write page 1's tone and dialled
                ; entries make - see DDS_ZERO_LT and DTMF_ZERO_LT_RUN in
                ; page1_dtmf.s. This page had no writer for it at all, so
                ; register $1C came out of a Digital Sequence entry however
                ; an earlier screen had left it rather than at $02 every
                ; time, as the instrument leaves it.
                ldx     #DTMF_ZERO_LT_RUN
                ldb     #DDS_ZERO_LT
                lbsr    ABI_dds_write

                ; AND A SEQUENCE THAT WAS RUNNING OR IN MANUAL GOES ON.
                ; $731E-$7351, on every reason: a single-shot sequence does
                ; not restart (LDB >$3C03 / LBEQ / CLR >$3C02), then after
                ; adopt_menu_page a running one restarts through
                ; softkey_run_continuous and a manual one through
                ; enter_manual_mode. A cold entry cleared both flags above,
                ; so it reaches digital_show as it always did; a recall
                ; brings digital_manual back with the register.
                tst     >digital_single
                beq     digital_sequence_resume
                clr     >digital_running        ; one pass is not resumed
digital_sequence_resume
                tst     >digital_running
                lbne    digital_sk_cont         ; softkey_run_continuous
                tst     >digital_manual
                lbne    digital_sk_bitmode      ; enter_manual_mode
                lbra    digital_show

; A REGISTER RECALLED INTO THE MODE. register_restore has torn the old mode
; down, run instrument_preset and copied the slot - the sequence with it,
; through register_seq_unstage_dig - which is $7187 on reason 1 as far as its
; recall_state_register. What is left before l7261 is l71d6: $C5B1 and the
; four output latches from the saved latch bytes, which is register_apply.
; Channel 0's dc waveform goes on first, for the reason digital_sequence_open
; gives: the level is coded on the arm the waveform selects.
digital_sequence_recall
                ldb     #DIGITAL_MARK
                lbsr    digital_wave_dc
                lbsr    ABI_channel_park_destinations   ; $C5B1 pass 1
                lbsr    ABI_register_apply              ; pass 2, and the
                bra     digital_sequence_kept           ; latches

; A KEEP-STATE POWER-ON. No preset and no copy: l71d6's $C5B1 without the
; latch walk, which is reason 1's alone.
digital_sequence_keep
                ldb     #DIGITAL_MARK
                lbsr    digital_wave_dc
                lbsr    ABI_channel_park_destinations   ; $C5B1 pass 1
                lbsr    ABI_channel_reapply_all         ; pass 2

; BOTH: the screen, the saved record, and the editor over the kept sequence.
; $7251 puts $268E back from $3C1F and menu_page_show shows it. The stock
; takes that byte as it stands; here it is bounded first, because a page past
; the last would index the record tables beyond their end and active_record
; can hold anything a battery or an older build left in it.
digital_sequence_kept
                ldx     #digital_key
                lbsr    ABI_screen_install
                lda     #SEQKIND_DIGITAL        ; the sequence a save carries
                sta     >seq_kind_live
                lda     >active_record
                cmpa    #DIGITAL_PAGES
                blo     digital_sequence_kept_page
                clra                            ; past the last: the title
digital_sequence_kept_page
                sta     >digital_page
                sta     >active_record
                lbsr    digital_editor_derive   ; init_sequence_editor l6603
                lbra    digital_sequence_levels
; ---------------------------------------------------------------------------
; digital_key - the Digital Sequence screen's keys
;
;   entry: B = the key code
;   uses:  A, B, X, Y, U
;
; ENTER starts and stops the sequence; NEXT and LAST step through it; f1
; opens the editor, where the patterns themselves are typed.
;
; The editor existed and nothing opened it - nine routines assembled into the
; ROM that no keystroke could reach, which is what tests/test_reachable.py
; is for.
;
; STOPPING PARKS THE OUTPUT AND ENDS MANUAL MODE. This paragraph used to say
; the opposite - that stopping leaves the port alone - which digital_key_stop
; below stopped doing when the head of this file was rewritten: it drives the
; idle routing, as stop_sequence_and_manual ($68D7) calls
; set_digital_output_bit(0) at $6905-$690F, and it clears digital_manual, as $68DD
; clears $3C04.
;
; MANUAL MODE is the stock's $3C04. f2 and f3 on the first page hold a mark
; or a space by hand and put the screen in it ($69BC); while it is on, every
; move of the bit cursor - the arrows and NEXT/LAST - re-drives the bit now
; under the cursor through digital_manual_drive, as $501F and $5062 do.
; ---------------------------------------------------------------------------
digital_key
                ; THE AMPTD KEY IS NOT ONE OF THIS SCREEN'S. It cycled
                ; digital_field through the mark level, the space level and
                ; back - borrowed from the tone screen, where AMPTD IS the
                ; level key. On the instrument key 5 has no arm in
                ; key_to_state_code's table at $AE3D: it lands on
                ; keymap_unmapped_return0 ($AE22), which posts nothing and
                ; returns 0, so AMPTD in Digital Sequence mode reaches the
                ; screen's dispatch with no request behind it and does
                ; nothing. The two levels are selected by softkey_on_level
                ; ($6940) and softkey_select_off_level ($6976) - f2 and f4 of
                ; record 1 - which is where digital_sk_onlev and
                ; digital_sk_offlev are, and an operator who wants a level
                ; presses the key labelled with it.
                ; THE BUS REQUESTS THIS SCREEN ANSWERS - the stock's page-2
                ; dispatch ($6E67) arms for RUNC/RUNS/STOP, SEQP/SEQE and the
                ; '?' report, delivered by remote.s as RMT_RQ + code. RUNC and
                ; STOP are the ENTER key's two halves, taken by state; RUNS is
                ; page 1's f1; SEQP/SEQE hand the next number to remote.s
                ; with this screen as its owner; '?' reports the bit period.
                ; THE BUS LETTING GO. Going local posts request $01 (the stack
                ; at the post runs back through $9F98, the HP-IB side), and arm
                ; [0] of this page's table d6e67 is key_close_entry_field
                ; ($6E3A): flush_pending_field_edit ($6877) - an increment
                ; shown for editing is redrawn as the value through [$3CDA] -
                ; and $3CAC = 0. Traced on the stock, seed 3 step 19: 'APB;'
                ; selected the level ($3CAC = 3), going local for the next key
                ; wrote 0 from $6E49, and INC SET then drew $14; this still had
                ; the level and armed its step.
                cmpb    #RMT_RQ+$36             ; QRE has no arm in d6e67:
                bne     digital_key_not_qre     ; key_reject_unhandled_code
                ldb     #DIGITAL_ERR_WRONG_MODE ; ($6E4C), $3A
                lbra    ABI_error_record
digital_key_not_qre
                cmpb    #RMT_RQ+$23             ; a bus level's unit: the
                bne     digital_key_not_entry   ; commit enter_level_value
                lbra    digital_bus_level       ; ($4CDA) makes
digital_key_not_entry
                cmpb    #KEY_GONE_LOCAL
                beq     digital_key_close
                cmpb    #RMT_RQ+$21             ; $21: key_save_prompt ($6B46),
                bne     digital_rq_not_save     ; $6E3A's close with $3CAC =
digital_rq_save                                 ; $0C rather than 0, then $F331
                lbsr    digital_key_close       ; with $0021
                lbra    ABI_save_prompt_open
digital_rq_not_save
                cmpb    #KEY_ABANDON            ; $3C is arm [59], the SAME
                bne     digital_key_not_local   ; routine as request 1's [0]
digital_key_close
                clr     >digital_field
                tst     >digital_incr_mode
                beq     digital_key_local_done
                clr     >digital_incr_mode
                lbra    digital_show
digital_key_local_done
                rts
digital_key_not_local
                cmpb    #RMT_RQ+$2D             ; RUNC: straight to the run,
                bne     digital_rq_stop         ; not through ENTER - ENTER
                lda     >digital_running        ; with a level row selected
                beq     digital_rq_runc         ; commits the level instead.
                lbsr    digital_report_end      ; ALREADY RUNNING: and the
                                                ; stop half of the stock's
                                                ; pair reports FINISHED before
                                                ; the start half reports
                                                ; STARTED, which is what
                                                ; $6A3C's two calls do
                lbsr    ABI_tick_remove         ; the stock's
                clr     >digital_running        ; softkey_run_continuous stops
                                                ; the clock and restarts from
                                                ; the first bit ($3CC4=$FFFF,
                                                ; $3CC6=$3C20); so does this
digital_rq_runc
                clr     >digital_single
                lbsr    digital_run
                lbra    digital_show
digital_rq_stop
                cmpb    #RMT_RQ+$30             ; STOP: likewise direct
                bne     digital_rq_single
                lda     >digital_running
                lbeq    digital_rq_shown        ; already stopped - LONG, since
                lbra    digital_key_stop        ; the WSQ arm moved the target
digital_rq_single
                cmpb    #RMT_RQ+$2E             ; RUNS: once through
                bne     digital_rq_seqp
                lda     >digital_running
                lbne    digital_rq_shown        ; LONG, as its neighbour is
                lbra    digital_sk_single
digital_rq_seqp
                cmpb    #RMT_RQ+$33
                bne     digital_rq_seqe
                ; AN ARM EMPTIES THE ENTRY. begin_numeric_entry ($A415) is
                ; what sets $238F, and it opens a fresh entry buffer, so a
                ; number an earlier message left waiting for its unit is
                ; gone: 'FRA 5;' 'FRA;' 'HZ;' sets nothing on the instrument
                ; (driven 2026-09-17) where 'FRA 5;' 'HZ;' sets 5 Hz.
                lda     >rmt_flags              ; an arm empties the entry
                anda    #~RF_HELD&$FF           ; ($A415): no number held
                sta     >rmt_flags              ; from before it survives
                lda     #0                      ; and has a field cursor
                sta     >rmt_field_gone         ; again (LDA leaves carry)
                lda     #RK_SEQPOS
                sta     >rmt_pend_kind
                ldx     #digital_index          ; msg_select_seq_index ($6D48)
                lda     #DIGITAL_FIELD_INDEX    ; calls softkey_select_seq_index
                bra     digital_rq_seq_own      ; ($5B24): the bus SELECTS the
                                                ; field, it does not only mark
                                                ; where the next number goes
digital_rq_seqe
                cmpb    #RMT_RQ+$34
                bne     digital_rq_query
                lda     >rmt_flags              ; an arm empties the entry
                anda    #~RF_HELD&$FF           ; ($A415): no number held
                sta     >rmt_flags              ; from before it survives
                lda     #0                      ; and has a field cursor
                sta     >rmt_field_gone         ; again (LDA leaves carry)
                lda     #RK_SEQEND
                sta     >rmt_pend_kind
                ldx     #digital_end            ; msg_select_seq_end ($6D9D)
                lda     #DIGITAL_FIELD_END      ; into softkey_select_seq_end
digital_rq_seq_own                              ; ($5B4E)
                sta     >digital_field
                stx     >digital_field_ptr      ; and the field pointer with
                                                ; it, which is what makes the
                                                ; arrows and ENTER reach the
                                                ; same number the bus just
                                                ; selected
                lda     #$02                    ; owner 2 = this screen
                sta     >rmt_seq_owner
                rts
digital_rq_query
                cmpb    #RMT_RQ+$25
                bne     digital_rq_stream
                lbra    digital_query
digital_rq_stream
                ; WSQ: THE PATTERN ITSELF, ARRIVING AS CHARACTERS. This arm did
                ; not exist. remote.s routes a stream to whichever screen set
                ; rmt_stream - its own comments name "the DTMF and digital
                ; screens" and "the digital screen ... SEQP SEQE WSQ" - and
                ; only page1_dtmf.s had the $2C arm, so a WSQ sent to this
                ; screen fell through the dispatch to key_refuse and the
                ; sentence in remote.s described an arm that was not there.
                ; remote_stream_char already knows what to do with the
                ; characters once the flag is up: for an owner that is not the
                ; DTMF screen it takes the digits '0' to '9' and hands each to
                ; remote_digit_key, which is this editor's own key path.
                cmpb    #RMT_RQ+$2C
                bne     digital_rq_level_test
                clr     >digital_insert         ; $656E: an insert in progress
                                                ; is cancelled
                lda     #DIGITAL_FIELD_DATA     ; $657B: field id 9, the data
                sta     >digital_field          ; cursor - and NOT the softkey
                                                ; edit session: $6DDE leaves
                                                ; $3CCA alone, so f4 still
                                                ; reads 'Edit Sequence'
                ldx     >digital_index          ; $6591: the stream starts
                stx     >digital_stream_at      ; where the cursor is standing
                lda     #$01
                sta     >rmt_stream
                lda     #$02                    ; owner 2 = this screen
                sta     >rmt_seq_owner
                lbra    digital_show
digital_rq_level_test
                cmpb    #RMT_RQ+$2F             ; RUNM: msg_stop_and_select_bit
                bne     digital_rq_level_code   ; ($6CF0) - any run stopped,
                lda     >digital_running        ; then softkey_bit_mode ($69ED),
                beq     digital_rq_bitmode      ; the bus's own Bit softkey
                lbsr    digital_report_end      ; sequence_run_start_stop(0)
                lbsr    ABI_tick_remove
                clr     >digital_running
digital_rq_bitmode
                lda     >rmt_flags              ; an arm empties the entry
                anda    #~RF_HELD&$FF           ; ($A415): no number held
                sta     >rmt_flags              ; from before it survives
                lda     #0                      ; and has a field cursor
                sta     >rmt_field_gone         ; again (LDA leaves carry)
                lda     #RK_DIGBIT              ; the Bit field takes the bus's
                sta     >rmt_pend_kind          ; number, as [$3C00](4) arms it
                lbra    digital_sk_bitmode
digital_rq_level_code
                cmpb    #RMT_RQ+$1A
                bne     digital_rq_refresh
digital_rq_level
                ; APA/APB AND DAPH/DAPL SELECT A LEVEL FROM THE BUS. Request $1A
                ; is arm [25] of $6E67, msg_select_level_by_index ($6C8D): with
                ; REMOTE set it takes the mnemonic's argument - key_dispatch
                ; saved $23BE - and 0 selects the On level through
                ; softkey_on_level ($6940), 1 the Off level through
                ; softkey_select_off_level ($6976), and anything else is $3A.
                ; Driven 2026-09-15 on the Seq Index record: 'APB;' leaves the
                ; instrument's $23DE untouched and its SRQ lamp dark; this
                ; refused it with $0F.
                lda     >rmt_pend_chan
                beq     digital_rq_level_on
                cmpa    #$01
                beq     digital_rq_level_off
                ldb     #DIGITAL_ERR_WRONG_MODE
                lbra    ABI_error_record
digital_rq_level_on
                lbsr    digital_sk_onlev
                bra     digital_rq_level_own
digital_rq_level_off
                lbsr    digital_sk_offlev
digital_rq_level_own
                ; AND THE LEVEL IS ARMED FOR THE BUS'S NUMBER. remote_select
                ; cleared the kind before posting $1A; with none named here,
                ; 'APB 5 UV;' answered $2F and the instrument set the Off
                ; level (seed 6 step 78). Its unit posts $23, below.
                lda     >rmt_flags              ; an arm empties the entry
                anda    #~RF_HELD&$FF           ; ($A415): no number held
                sta     >rmt_flags              ; from before it survives
                lda     #0                      ; and has a field cursor
                sta     >rmt_field_gone         ; again (LDA leaves carry)
                lda     #RK_DIGLEVEL
                sta     >rmt_pend_kind
                lda     #$02                    ; owner 2 = this screen
                sta     >rmt_seq_owner
                rts
digital_rq_refresh
                cmpb    #KEY_REFRESH            ; SEQP/SEQE from the bus moved
                bne     digital_rq_base         ; the position or the end
                lbra    digital_show
                ; THE THREE BASES, EACH BY ITS OWN CODE. msg_set_number_base
                ; ($6DEB) is arms [56], [57] and [58] of the $6E67 table -
                ; request codes $39, $3A and $3B, all above the $22 limit of
                ; the main ROM's own table, so they arrive from the command
                ; parser and not from a key. It sets 0 for $39, 1 for $3A and 2
                ; for anything else, and hands that to change_sequence_base
                ; ($56E9), which is digital_base_change here. The bus reached
                ; the base only through the softkey that CYCLES it, so a
                ; controller asking for Hex got whichever base was next.
digital_rq_base
                cmpb    #RMT_RQ+$39
                bne     digital_rq_base_oct
                lda     #DIGITAL_BASE_BIN
                bra     digital_rq_base_set
digital_rq_base_oct
                cmpb    #RMT_RQ+$3A
                bne     digital_rq_base_hex
                lda     #DIGITAL_BASE_OCT
                bra     digital_rq_base_set
digital_rq_base_hex
                cmpb    #RMT_RQ+$3B
                bne     digital_rq_period
                lda     #DIGITAL_BASE_HEX
digital_rq_base_set
                lbsr    digital_base_change
                lbra    digital_show

digital_rq_period
                ; REACHED BY THE bne ABOVE. This compare was written directly
                ; after digital_rq_base_set's `lbra digital_show`, with no
                ; label on it, so nothing could branch to it and the arm was
                ; dead code: measured, 'STON 687;' on this screen left
                ; digital_field 0 and still raised $2B.
                cmpb    #RMT_RQ+$31             ; STON: arm [48] of d6e67 is
                bne     digital_rq_stopsel      ; key_select_period_field
                ; AND THE NUMBER THAT FOLLOWS IS THIS FIELD'S. Selecting the
                ; field on the SCREEN is only half of it: remote.s decides what
                ; to do with the number after the mnemonic from rmt_pend_kind,
                ; and with nothing pending a bare 687 is refused at
                ; remote_number_commit with ERR_RMT_NO_FIELD ($2B). Its
                ; siblings on this screen already do this - digital_rq_seqp
                ; sets RK_SEQPOS with rmt_seq_owner 2 - and tone_rq_time_own is
                ; the same pair with owner 1 on the tone screen.
                ;
                ; RK_TIME IS THE KIND, so the units the field takes are the
                ; ones remote_units_time allows: seconds and milliseconds,
                ; unit_allowed_for_group ($A65A)'s set {9, $0A}, with anything
                ; else raising $2E as pending_setting_service ($A73E) does at
                ; $A939. A BARE number, no unit, is held and not reported:
                ; RK_TIME is a row of remote.s rmt_needs_unit, so the number
                ; waits for a unit. Measured on the stock, this screen, 'STON 687;'
                ; answers err 0 with the lamp dark; this firmware raised $2B
                ; and lit it - seed 35 step 21.
                lda     >rmt_flags              ; an arm empties the entry
                anda    #~RF_HELD&$FF           ; ($A415): no number held
                sta     >rmt_flags              ; from before it survives
                lda     #0                      ; and has a field cursor
                sta     >rmt_field_gone         ; again (LDA leaves carry)
                lda     #RK_TIME
                sta     >rmt_pend_kind
                lda     #$02                    ; owner 2 = this screen, as
                sta     >rmt_seq_owner          ; digital_rq_seqp sets it
                lbra    digital_sk_period       ; ($6CD6), a bare call to
                                                ; ($6CD6), a bare call to
                                                ; softkey_period ($6917) - so
                                                ; on THIS screen the on-time
                                                ; command selects the Period
                                                ; field, which is the field the
                                                ; record already shows. STOF
                                                ; ($32) is arm [49],
                                                ; key_reject_unhandled_code, so
                                                ; it stays with the catch-all.
                                                ; Measured: the stock answers
                                                ; 'STON 687;' here with err 0
                                                ; and this firmware raised $2B,
                                                ; because no arm armed a field
                                                ; and the NUMBER was then
                                                ; refused - seed 35 step 21.
digital_rq_stopsel
                cmpb    #RMT_RQ+$2F             ; msg_stop_and_select_bit
                bne     digital_key_hexdata     ; ($6CF0, arm [46]): stop the
                lda     #DIGITAL_FIELD_BIT      ; run and put the cursor on
                sta     >digital_field          ; the manual bit field, which
                lda     >digital_running        ; is what 'select_bit' means -
                beq     digital_rq_shown        ; $3CAC = $0B
                lbra    digital_key_stop        ; and it is the STOP softkey's
                                                ; own path now, not ENTER's:
                                                ; ENTER on this screen is a
                                                ; commit and stops nothing
digital_rq_shown
                lbra    digital_show

digital_key_hexdata
                ; THE DATA CURSOR IS ONE HEX CHARACTER, AND IT TAKES THE KEY
                ; BEFORE ENTER DOES. arm_data_digit_entry_field ($5866) arms
                ; one character at column $15 + $3CD4 in entry mode 1 - column
                ; 5 of keypad_char_table ($EF94), the hexadecimal column - and
                ; enter_sequence_field_value ($60BC)'s arm for $3CAC = 9 takes
                ; that single character from $239A and converts it with
                ; parse_hex_digit_pair ($CC53). There is no second path on this
                ; field: it is hex whoever is driving, and what the BASE allows
                ; is checked afterwards by validate_digit_for_base ($607E).
                ;
                ; So kHz, Hz, deg, ENTER, minus and point are A, B, C, D, E and
                ; F here, and the character commits itself, the field being one
                ; wide. Driven on the stock 2026-09-11 with the editor open on
                ; base Hex: kHz, minus, 5, point, deg, ENTER, Hz leave the
                ; window reading '[AE5FCDB789ABCDEF]' and the index at 8.
                ;
                ; This firmware typed into a decimal buffer that ENTER
                ; committed: kHz was refused with $0F, minus put a BLANK in the
                ; cell, point and deg raised $02, and ENTER stored the last
                ; digit - so ten of the sixteen values could not be typed into
                ; a hex sequence at all.
                lda     >digital_field
                cmpa    #DIGITAL_FIELD_DATA
                bne     digital_rq_enter
                lbsr    ABI_key_hex_digit       ; B is left as it was when the
                bcs     digital_rq_enter        ; key is not one of the sixteen
                lbsr    ABI_entry_is_open       ; lb494: nothing armed, no key
                lbeq    digital_key_ignore      ; $B49D
                bra     digital_data_put

digital_rq_enter
                cmpb    #KEY_ENTER
                lbne    digital_key_f1
                ; ONLY OVER AN ARMED FIELD, AND ONLY ON CLASS 2. ENTER reaches
                ; accept_units_key ($B0C1) past lb494's $23A8 test, and lb1ff's
                ; range test sends classes 0 and 1 to lb1f7 (zero, a beep); class
                ; 4's arm $B127 takes deg, Hz and kHz and class 5's $B169 Hz and
                ; kHz, and nothing else. So ENTER terminates Seq Index, Seq End
                ; and the bit index - class 2 - and beeps on a level, the period
                ; and the base; this committed the period and a level's sign.
                lbsr    ABI_entry_is_open       ; lb494
                lbeq    digital_key_ignore      ; $B49D

                ; ENTER IS A COMMIT AND NOTHING ELSE, which is what
                ; commit_entry_to_seq_field ($4CCE) is: a guarded dispatch on
                ; $3CAC over 3 to $0C ($4E6C CMPX #$000C / LBGT, SUBD #$0003 /
                ; LBLT), with $0E - the base - leaving through the silent
                ; epilogue at $4E97 and 0 refused by the guard.
                ;
                ; IT USED TO RUN AND STOP THE SEQUENCE. That was the rewrite
                ; making up for having no softkey to spare, because f4 was
                ; paging the menu; the instrument has Continuous, Single and
                ; Stop on record 3's f2, f3 and f4 and this screen has them
                ; now. An operator who presses ENTER on a screen where nothing
                ; is selected gets the same refusal every other screen gives.
                lda     >digital_field
                lbeq    digital_key_ignore      ; $4E6C's SUBD / LBLT
                cmpa    #DIGITAL_FIELD_BASE
                lbeq    digital_key_ignore      ; class 0: lb1f7
                cmpa    #DIGITAL_FIELD_INDEX
                beq     digital_enter_number
                cmpa    #DIGITAL_FIELD_END
                beq     digital_enter_number
                cmpa    #DIGITAL_FIELD_BIT
                beq     digital_enter_bit
                lbra    digital_key_ignore      ; classes 4 and 5: $B127, $B169

; ---------------------------------------------------------------------------
; digital_enter_number - ENTER on Seq Index or Seq End
;
;   uses:  A, B, X, Y, U
;
; commit_sequence_entry ($4E23) into the index arm of
; enter_sequence_field_value ($6215). The number is read out of the entry
; buffer as typed - one-based - and edit_index_typed does the rest.
; ---------------------------------------------------------------------------
digital_enter_number
                lbsr    ABI_entry_cursor_off    ; $B5BA, then request $23
                bsr     digital_enter_value
                lbra    digital_show_armed      ; and its [$3C00] at $6306/$6319

; ---------------------------------------------------------------------------
; digital_enter_value - commit the typed number to the selected index
;
;   uses:  A, B, X, Y, U
;
; SEPARATE FROM THE REPAINT because digital_enter_bit has work to do after it:
; it changes the base to binary for the duration of the entry and has to
; change it back. A commit that ended in the repaint could never return, and
; the base would be left in binary - which is the sort of thing that only
; shows on the next keystroke.
; ---------------------------------------------------------------------------
digital_enter_value
                tst     >entry_active           ; nothing typed: nothing to
                beq     digital_enter_rearm     ; commit, and no complaint
                lbsr    ABI_entry_value
                bcs     digital_enter_toobig
                lda     >entry_result           ; four digits fit in sixteen
                bne     digital_enter_toobig    ; bits and no more
                ldx     >entry_result+1
                lbsr    edit_index_typed
digital_enter_rearm
                lda     #ENTRY_DECIMAL
                ldb     #DIGITAL_IX_W
                lbsr    ABI_entry_begin
                clr     >entry_active
                rts
digital_enter_toobig
                ldb     #ERR_SEQ_INDEX
                lbsr    ABI_error_raise
                bra     digital_enter_rearm


; ---------------------------------------------------------------------------
digital_enter_bit
                lbsr    ABI_entry_cursor_off    ; $B5BA, then request $23
                lda     >digital_base
                pshs    a
                lda     #DIGITAL_BASE_BIN
                lbsr    digital_base_change
                ldx     #digital_index          ; the bit index IS the cursor
                stx     >digital_field_ptr      ; while the base is binary
                lbsr    digital_enter_value
                puls    a
                lbsr    digital_base_change
                lbra    digital_show_armed      ; and re-armed, [$3C00] at $4E19

; ---------------------------------------------------------------------------
; digital_data_put - one hex character typed into the data window
;
;   entry: B = the value, 0 to 15, from digital_key_hexdata
;   uses:  A, B, X, Y, U
;
; The digit arm of enter_sequence_field_value ($60BC). The typed CHARACTER is
; the digit - $60BC takes it from $239A and parses it with
; parse_hex_digit_pair - so one character is what is committed, not a
; multi-digit number, and the cursor moves on afterwards so the next one lands
; in the next cell. edit_digit_typed measures it against the base and reports
; $39 itself when the base cannot express it, which is where the refusal for a
; '9' in an octal sequence comes from.
; ---------------------------------------------------------------------------
digital_data_put
                lbsr    ABI_entry_cursor_off    ; $B586: class 0 ends on the key
                lbsr    edit_digit_typed        ; carry set: past the end, no store
                bcs     digital_data_past
                bsr     digital_data_fresh
                lbra    digital_show_armed      ; $6115 refused, $61FD stored
digital_data_past
                bsr     digital_data_fresh
                lbra    digital_show            ; $616E LBHI l6202: no step, no arm

; ---------------------------------------------------------------------------
; digital_data_fresh - a fresh one-character entry for the data cell
;
;   uses:  A, B, X
;
; One character a cell, as arm_data_digit_entry_field ($5A7C) arms it - the
; comment here named $5866, which is inside refresh_seq_end_readout ($585F).
; ---------------------------------------------------------------------------
digital_data_fresh
                lda     #ENTRY_DECIMAL
                ldb     #$01
                lbsr    ABI_entry_begin
                clr     >entry_active
                rts

; ---------------------------------------------------------------------------
; digital_query - the bus asked '?': queue the selected field's value
;
;   uses:  A, B, X, Y, U
;
; The stock's gpib_query_current_field ($4A00) dispatches on its field
; cursor: gpib_report_level for a level, gpib_report_level_increment for
; its step, gpib_query_period / gpib_report_period_increment for the
; period, gpib_report_bit_index for the bit, gpib_query_seq_field for the
; pattern itself. The same answers here: the bit row reports the pattern as
; '0'/'1' characters (the stock's base-2 walk) when nothing else is armed,
; a level row reports that channel's level through the shared renderer, and
; INCR SET armed reports the period's step.
; ---------------------------------------------------------------------------
digital_query
                tst     >digital_incr_mode
                bne     digital_query_incr
                lda     >digital_page           ; the period page: report the
                cmpa    #$02                    ; period itself, the stock's
                beq     digital_query_period    ; gpib_query_period ($4A85) -
                lda     >digital_field          ; five digits of $3C9E, here
                beq     digital_query_bits      ; in timer counts
                cmpa    #DIGITAL_FIELD_BASE     ; the base field reports as
                beq     digital_query_bits      ; the step row does: $0E falls
                                                ; out of the $4A00 dispatch's
                                                ; range guard at $4B3A the way
                                                ; 0 does at $4B31
                cmpa    #DIGITAL_FIELD_INDEX    ; SEQ INDEX AND SEQ END REPORT
                beq     digital_query_index     ; THEMSELVES, and reported a
                cmpa    #DIGITAL_FIELD_END      ; channel LEVEL: both fell past
                beq     digital_query_index     ; this dispatch into the level
                                                ; arm below, so 'SEQP; ?;' on
                                                ; this screen answered with a
                                                ; voltage. The stock has the
                                                ; arm - gpib_report_sequence_
                                                ; field ($5C30) is LDD [$3CD0]
                                                ; / ADDD #$0001 at $5C3C-$5C40
                                                ; - and it reports ONE-BASED,
                                                ; which is what the screen
                                                ; shows and the inverse of the
                                                ; SUBD the commit does
                lbsr    digital_level_record    ; X = the channel's record
                lbsr    ABI_ampl_text
                ldx     #chan_text
                ldb     #AMPL_TEXT_W+AMPL_TEXT_U
                lbra    ABI_remote_queue
digital_query_index
                ; THE FIELD ID CHOOSES THE CELL, not digital_field_ptr. The
                ; dispatch above tested digital_field and this fetched through
                ; a different cell, and the two are written together in only
                ; one place: digital_enter_bit repoints the pointer without
                ; touching the field id, and digital_sk_edit writes a third
                ; combination. No reaching path was found today, so this was
                ; not yet wrong - it was one edit away from being wrong, and
                ; the field id already selects the cell everywhere else on
                ; this screen.
                ldu     #digital_index
                cmpa    #DIGITAL_FIELD_INDEX
                beq     digital_query_index_at
                ldu     #digital_end
digital_query_index_at
                ldd     ,u
                addd    #1                      ; the stock's $3CD0 is
                bra     digital_query_word
digital_query_period
                ldd     >digital_period
                bra     digital_query_word
digital_query_incr
                ldd     >incr_digital
digital_query_word
                std     >chan_work+1
                clr     >chan_work
                ldx     #chan_work
                lbsr    ABI_uint24_to_text
                ldx     #text_buffer+3          ; five digits
                ldb     #5
                lbra    ABI_remote_queue
digital_query_bits
                ; THE PATTERN, ONE CHARACTER PER BIT, most significant bit
                ; first, up to the seventy characters the queue takes. Each
                ; bit is read through digital_bit_at, the routine the player
                ; itself uses, so the report is the pattern the port plays.
                ; Built in rmt_out, the bus's own buffer - common/ram.inc's
                ; $2285, the stock's own; the first version shifted one place
                ; short, reported position p-1's bit at p, and wrote into
                ; chan_text past its end.
                ;
                ; THE LENGTH IS A BIT COUNT AND SIXTEEN BITS WIDE. It was
                ; `sequence_length` steps times eight, which was the
                ; rewrite's sixteen-step model; the sequence is now
                ; digital_last_bit+1 bits of a 1000-bit stream, so a full
                ; pattern is 1000 characters and RMT_OUT_MAX - the 250 the
                ; bus buffer holds - is the cap, so a long pattern reports as
                ; a prefix, which is what it always was.
                ldx     >digital_last_bit
                bne     digital_query_have
                lbra    digital_query_none      ; nothing has set an end: no
                                                ; sequence, no report
digital_query_have
                leax    1,x                     ; bits, not the last index
                cmpx    #RMT_OUT_MAX
                bls     digital_query_count
                ldx     #RMT_OUT_MAX
digital_query_count
                tfr     x,d
                pshs    b                       ; 0,s = how many characters,
                                                ; and it is at most 70 so one
                                                ; byte holds it
                ldx     #$0000                  ; the bit position, sixteen
                ldy     #rmt_out                ; bits wide
digital_query_bit
                pshs    x
                lbsr    digital_bit_at          ; A = 0 or non-zero
                puls    x
                tsta
                beq     digital_query_zero
                lda     #'1'
                bra     digital_query_char
digital_query_zero
                lda     #'0'
digital_query_char
                sta     ,y+
                leax    1,x
                dec     ,s
                bne     digital_query_bit
                leas    1,s                     ; the count is done with
                tfr     y,d                     ; and the length is Y - rmt_out
                subd    #rmt_out
                ldx     #rmt_out
                lbra    ABI_remote_queue
digital_query_none
                rts

; ---------------------------------------------------------------------------
; digital_report_end - the FINISHED status bit, if a run was in progress
;
;   uses:  A, B
;
; sequence_run_start_stop ($67A3)'s zero leg opens LDB >$3C02 / CMPB #$00 /
; LBEQ past, so the report at firmware/src-generated/a2u13_page2.s line 7001
; - index 3, code $00FF - happens only where a run was actually going, and it
; happens BEFORE the CLR >$3C02 beneath it. digital_running is this
; firmware's $3C02, so the guard is the same guard and the ordering is the
; same ordering.
;
; It is a routine and not three lines repeated because the stock has three
; call sites for that zero leg and this firmware has the same three: the STOP
; softkey and bus STOP through digital_key_stop (the stock's
; stop_sequence_and_manual, $68D7), and the two run softkeys, which stop
; before they start (softkey_run_continuous at $6A3C and softkey_single_run
; call sequence_run_start_stop with 0 and then with 1).
;
; AND THE SINGLE-SHOT END IS ONE MORE. This said the stock's output ISR ends a
; single pass without going near $67A3, which is true of the ISR's own lines
; and false one call down: at $41C5 and $41EE it calls
; stop_sequence_preserving_lcd_address, which calls stop_sequence_and_manual
; ($68D7), which calls sequence_run_start_stop(0) while $3C02 is set - the
; report, then ptm_stop_sequence_clock's $91. That second $91 is in the
; stock's captured stream (emulator/tests/test_digital_tick.py), so
; digital_advance calls this at its single-shot stop, before it clears
; digital_running. And digital_run calls it too, as the stop half of the
; stock's stop-then-start pair.
; ---------------------------------------------------------------------------
digital_report_end
                tst     >digital_running        ; $67A3's own LDB >$3C02 test
                beq     digital_report_none
                lda     #RMT_SRQ_SEQ_END
                lbra    ABI_remote_srq_event
digital_report_none
                rts

; ---------------------------------------------------------------------------
; digital_run - start clocking the pattern out
;
;   uses:  A, B, X
;
; SHARED by ENTER and by page 1's run-once key, so the two cannot drift apart.
; The single-shot flag is set by the caller before this, not here.
; ---------------------------------------------------------------------------
digital_run
                ; STOP FIRST, as both run softkeys do: softkey_run_continuous
                ; and softkey_single_run call sequence_run_start_stop(0) -
                ; the end reported if a run was going, timer 2 stopped with
                ; $91 - before sequence_run_start_stop(1) starts it again.
                lbsr    digital_report_end
                clr     >digital_running
                lbsr    ABI_tick_remove
                clr     >digital_once           ; start_sequence_clock: CLR
                                                ; >$3CC8
                clr     >digital_manual         ; RUNNING ENDS MANUAL MODE:
                                                ; softkey_run_continuous
                                                ; clears $3C04 at $6A23 and
                                                ; softkey_single_run at $6A64
                ; PRIMED AS start_sequence_clock PRIMES IT. The instrument
                ; sets $3CC4 = $FFFF, $3CC6 one BELOW the pattern base and
                ; $3CC9 = 0, so the first tick shifts a zero out - one
                ; priming space - bumps the counter to 0, arms timer 2 from
                ; the period, and fetches the first byte. Bit 0 goes out on
                ; the tick after that. Starting the counter at 0 instead
                ; would fetch nothing and shift whatever the last run left.
                ldx     #$FFFF                  ; $3CC4
                stx     >digital_bit_index      ; is SIXTEEN BITS - a CLR
                ldx     #digital_pattern_ram-1  ; $3CC6, one below the base
                stx     >digital_play_ptr
                clr     >digital_play_byte      ; $3CC9
                                                ; zeroed the high byte and
                                                ; left the low one, so a run
                                                ; started wherever the last
                                                ; one had got to within its
                                                ; first 256 bits
                lda     #$01                    ; Set before the running flag,
                sta     >digital_running        ; so an interrupt landing
                                                ; between
                                                ; the two cannot clock out
                                                ; wherever the last run
                                                ; stopped
                ldd     >digital_period         ; how long each bit lasts, in
                bne     digital_run_timed       ; timer counts
                ldd     #DIGITAL_BIT_COUNTS     ; never set: one millisecond,
                std     >digital_period         ; which is what the constant
digital_run_timed                               ; always was
                ; AND THE BUS IS TOLD, before the clock starts, which is
                ; where sequence_run_start_stop ($67A3) tells it: the LBSR
                ; $9DD3 with index 2 and code $00FF at
                ; firmware/src-generated/a2u13_page2.s line 6978 sits between
                ; draw_run_status_field ($48A8) and start_sequence_clock
                ; ($5398). ABI_remote_srq_event carries the event_flags bit 3
                ; gate and the whole pulse; bit 2 is not in the power-on mask
                ; $13, so a controller has to ask for this one.
                lda     #RMT_SRQ_SEQ_START
                lbsr    ABI_remote_srq_event

                ; THE PERIOD IS LOADED HERE, AND IT USED TO BE LOADED ABOVE.
                ; ABI_tick_install takes D as the period and remote_srq_event
                ; does not preserve it: that routine opens LDB >rmt_flags and
                ; tail-branches into remote_srq_raise and remote_srq_release,
                ; so the D loaded from digital_period was gone by the time the
                ; install read it and the latch got whatever the SRQ path left
                ; behind.
                ;
                ; AND WHAT GOES IN IS $00C8, NOT THE BIT PERIOD.
                ; start_sequence_clock ($5398) stores #$00C8 straight into
                ; ptm_timer2; the body swaps the real period in on the first
                ; tick, which is what digital_advance does at the counter wrap
                ; now. seq_timer_start subtracts one from what it is handed
                ; (timer.s), so it is handed one more to land $00C8 on the
                ; chip - exactly as tone_timer_start and the dialler's install
                ; already do.
                ldd     #DIGITAL_START_COUNTS+1
                ldx     #digital_advance
                lbra    ABI_tick_install

digital_key_stop
                lbsr    digital_report_end      ; ahead of the clear, as the
                                                ; stock's zero leg is
                lbsr    ABI_tick_remove
                clr     >digital_running
                clr     >digital_manual         ; AND MANUAL MODE ENDS WITH
                                                ; IT: stop_sequence_and_manual
                                                ; ($68D7) CLR >$3C04 at $68DD
                                                ; before parking the output
                                                ; at $6905-$690F
                lbsr    digital_drive_idle      ; off the socket, which is
                lbra    digital_show            ; what seq_output_stop does
; ---------------------------------------------------------------------------
; digital_key_f1 to digital_key_f4 - the four softkeys of whichever record is up
;
;   entry: B = the key code
;   uses:  A, B, X, Y, U
;
; TWELVE FUNCTIONS, THREE PAGES OF FOUR, and the table below is the stock's
; three menu records read straight across:
;
;   record 2 ($417F)  Seq Index   Seq End      Delete      Edit Sequence
;   record 1 ($4175)  Seq Base    On Level     Period      Off Level
;   record 3 ($4189)  Bit         Continuous   Single      Stop
;
; f4 USED TO PAGE THE SOFTKEYS and there is no such key on the instrument -
; NEXT and LAST do that (key_menu_page_change, $6B20, on request codes $17 and
; $18), and f4 is a function on every page. Taking f4 for paging cost the
; screen one function per page and put Off Level, Edit Sequence and Stop
; nowhere at all.
; ---------------------------------------------------------------------------
digital_key_f1
                cmpb    #KEY_F1
                bne     digital_key_f2
                clra
                bra     digital_softkey
digital_key_f2
                cmpb    #KEY_F2
                bne     digital_key_f3
                lda     #$01
                bra     digital_softkey
digital_key_f3
                cmpb    #KEY_F3
                bne     digital_key_f4
                lda     #$02
                bra     digital_softkey
digital_key_f4
                cmpb    #KEY_F4
                lbne    digital_key_next
                lda     #$03
digital_softkey
                ldb     >digital_page           ; four softkeys a page
                lslb
                lslb
                pshs    a
                addb    ,s+                     ; and which of them
                lslb                            ; two bytes an entry
                ldx     #digital_softkeys
                abx
                ldx     ,x
                jmp     ,x
; FOUR RECORDS, SO FOUR ROWS. The order is the instrument's: record 0's four
; handler words are three $C239 and the Exit ($416B), record 1 is
; softkey_seq_base, softkey_on_level, softkey_period and
; softkey_select_off_level ($4175), record 2 is softkey_select_seq_index,
; softkey_select_seq_end, softkey_delete_element and
; softkey_edit_sequence_or_insert ($417F), and record 3 is softkey_bit_mode,
; softkey_run_continuous, softkey_single and softkey_stop_sequence ($4189).
digital_softkeys
                fdb     digital_sk_none         ; record 0 - the title: $C239,
                fdb     digital_sk_none         ; $C239, $C239 and the Exit
                fdb     digital_sk_none
                fdb     digital_sk_exit
                fdb     digital_sk_base         ; record 1 - base, period,
                fdb     digital_sk_onlev        ; levels
                fdb     digital_sk_period
                fdb     digital_sk_offlev
                fdb     digital_sk_index        ; record 2 - the editor
                fdb     digital_sk_end
                fdb     digital_sk_delete
                fdb     digital_sk_edit
                fdb     digital_sk_bitmode      ; record 3 - the player
                fdb     digital_sk_cont
                fdb     digital_sk_single
                fdb     digital_sk_stop

; ---------------------------------------------------------------------------
; digital_sk_none - a softkey the record does not use
;
; Three of record 0's four handler words are $C239, which allocates a frame and
; returns. A key that does nothing must still not beep: the instrument prints
; no label beside it and pressing it is not an error.
; ---------------------------------------------------------------------------
digital_sk_none
                lbra    digital_show            ; the dispatcher's own repaint,
                                                ; which is what follows a $C239
                                                ; arm on the instrument

; ---------------------------------------------------------------------------
; digital_sk_exit - record 0's f4, the Exit
;
; post_request_0b ($8B4C) puts $000B in $2217, which a2u12's own table turns
; into return_to_main_menu ($8E62): the mode's teardown vector runs and the
; Main Selection comes back. nav_pop is that here.
; ---------------------------------------------------------------------------
digital_sk_exit
                lbra    ABI_screen_back

; --- page 0: the sequence editor -------------------------------------------

; ---------------------------------------------------------------------------
; digital_sk_index / digital_sk_end - select one of the two number fields
;
;   uses:  A, B, X, Y, U
;
; softkey_select_seq_index ($5B24) and softkey_select_seq_end ($5B4E). Each
; sets $3CAC, aims the field pointer $3CD0 at its own index and arms a keypad
; field through [$3C00] - 4 for the index and 5 for the end. The pointer is
; what makes one set of field routines serve both: draw_index_number_field
; ($57A5) renders `[$3CD0]+1` and the arrows step `[$3CD0]`.
; ---------------------------------------------------------------------------
digital_sk_index
                ldx     #digital_index
                lda     #DIGITAL_FIELD_INDEX
                bra     digital_sk_number
digital_sk_end
                ldx     #digital_end
                lda     #DIGITAL_FIELD_END
digital_sk_number
                sta     >digital_field
                stx     >digital_field_ptr
                lbsr    digital_leave_edit      ; $6F6B: selecting another
                                                ; field closes the session
                lda     #ENTRY_DECIMAL
                ldb     #DIGITAL_IX_W
                lbsr    ABI_entry_begin
                clr     >entry_active
                clr     >digital_incr_mode
                lbra    digital_show_armed      ; [$3C00] at $5B44 and $5B69: armed

; ---------------------------------------------------------------------------
; digital_sk_edit - open an edit session, and open a space in it
;
;   uses:  A, B, X, Y, U
;
; softkey_edit_sequence_or_insert ($5B73). One key with two meanings, decided
; by whether a session is already open ($3CCA): the first press opens the
; session - $3CAC = 9, $3CD0 = $3CA2, $3CD4 = 0, $3CCA = 1 - and every press
; after it toggles INSERT ($5B8C clears $3CD7, $5B93 sets it). That is why f4
; is labelled 'Edit Sequence' until the session opens and 'Insert' after it.
; ---------------------------------------------------------------------------
digital_sk_edit
                tst     >digital_edit
                bne     digital_sk_insert
                lda     #$01                    ; $5BAD: the session
                sta     >digital_edit
                lda     #DIGITAL_FIELD_DATA     ; $5BBA: and the data cursor
                sta     >digital_field
                ldx     #digital_index          ; $5BB1
                stx     >digital_field_ptr
                ldx     >digital_index          ; the window starts under it
                stx     >digital_window
                ldx     #$0000                  ; $5BB6
                stx     >digital_column
                clr     >digital_insert
                lda     #ENTRY_DECIMAL          ; one digit a cell
                ldb     #$01
                lbsr    ABI_entry_begin
                clr     >entry_active
                bra     digital_sk_edit_shown
digital_sk_insert
                lda     >digital_insert         ; $5B84: a toggle
                coma
                sta     >digital_insert
digital_sk_edit_shown
                lbra    digital_show_armed      ; $5BD2 opening the session and $5BA5
                                                ; toggling the gap: both re-arm the cell

; ---------------------------------------------------------------------------
; digital_sk_delete - take the digit under the cursor out of the sequence
;
;   uses:  A, B, X, Y, U
;
; softkey_delete_element ($5BDA). With INSERT set it cancels the insert
; instead ($5BF5 CLR >$3CD7), which is the only way out of insert that does
; not type a digit. Off the data cursor it does nothing but deselect ($5C28
; stores 0 into $3CAC).
; ---------------------------------------------------------------------------
digital_sk_delete
                lda     >digital_field          ; $5BE0
                cmpa    #DIGITAL_FIELD_DATA
                beq     digital_sk_delete_armed
                clr     >digital_field          ; $5C28
                lbra    digital_show
digital_sk_delete_armed
                tst     >digital_insert         ; $5BEB
                beq     digital_sk_delete_go
                clr     >digital_insert
                lbra    digital_show_armed      ; l5c03: both paths repaint and
digital_sk_delete_go
                lbsr    edit_delete_at_cursor
                lbra    digital_show_armed      ; re-arm the data cell at $5C20

; --- page 1: the base, the period and the two levels ------------------------

; ---------------------------------------------------------------------------
; digital_sk_onlev / digital_sk_offlev - select a level to type into
;
;   uses:  A, B, X, Y, U
;
; softkey_on_level ($6940) and softkey_select_off_level ($6976), which set
; $3CAC = 3 and point $3CB8 at one of the two channels. Here the channel is
; the field number, so one store does both.
; ---------------------------------------------------------------------------
digital_sk_onlev
                lda     #DIGITAL_FIELD_MARK
                bra     digital_sk_level
digital_sk_offlev
                lda     #DIGITAL_FIELD_SPACE
digital_sk_level
                sta     >digital_field
                lbsr    digital_leave_edit
                lbsr    digital_entry_level     ; a fresh entry for it
                lbra    digital_show_armed      ; [$3C00] at $696C and $69A4

digital_sk_period
                ; softkey_period ($6917): it SELECTS the period field and arms
                ; its entry.
                ; AND WHATEVER WAS TYPED. $6917-$6936 is LDD #$0005 / STD >$3cac,
                ; flush_pending_field_edit ($6877) and [$3C00] with 2, with no
                ; test of the entry. This refused the key with digits standing,
                ; as if it were a terminator; it is a field key, and being mapped
                ; it has already ended the entry at $B45C.
                lda     #DIGITAL_FIELD_PERIOD
                sta     >digital_field
                lbsr    digital_leave_edit
                clr     >digital_incr_mode      ; $6877's CLR >$3cdd: no INCR SET view
                lda     #ENTRY_DECIMAL
                ldb     #TEXT_DIGITS
                lbsr    ABI_entry_begin
                clr     >entry_active
                lbra    digital_show_armed      ; [$3C00] with 2 at $6936

digital_sk_base
                ; THE NUMBER BASE a pattern is shown in. This is the stock's
                ; softkey_seq_base ($689B): while the base field is not the
                ; selected one it selects it ($68AB LDD #$000E / $68AE STD
                ; >$3CAC) and arms the zero-width field at column $0C through
                ; [$3C00](6); once it is, it calls seq_step_selected_field
                ; ($4E9A) with direction 1 at $68C4, which reaches
                ; cycle_sequence_base ($5095). So the first press selects and
                ; every press after it cycles upward, and the arrows cycle it
                ; in either direction while it is selected. This used to cycle
                ; on the first press and had no field to select, so the arrows
                ; could never reach it and it cycled one way only.
                lda     >digital_field
                cmpa    #DIGITAL_FIELD_BASE
                beq     digital_key_base_up
                lda     #DIGITAL_FIELD_BASE
                sta     >digital_field
                lbsr    digital_leave_edit
                clr     >entry_active           ; as selecting a level does
                clr     >digital_incr_mode
                lda     #ENTRY_DECIMAL          ; the zero-width field: $66D3
                clrb                            ; arms width 0, and a field
                lbsr    ABI_entry_begin         ; with no digits is a cursor
                lbra    digital_show_armed      ; [$3C00] with 6 at $68BA
digital_key_base_up
                ldb     #$01                    ; $68C4: direction 1, upward
                lbra    digital_cycle_base

; --- page 2: the player -----------------------------------------------------

; ---------------------------------------------------------------------------
; digital_sk_bitmode - drive the bit under the cursor by hand
;
;   uses:  A, B, X, Y, U
;
; softkey_bit_mode ($69ED) into enter_manual_mode ($69AE). It selects the
; manual bit index ($3CAC = $0B at $69B4), sets $3C04 at $69BC and drives the
; bit the cursor is on; from then on every move of the cursor re-drives it.
;
; IT DOES NOTHING WHILE THE SEQUENCE IS RUNNING - $69F3 LDB >$3C02 / $69F8
; LBNE - so a running sequence keeps the socket to itself.
;
; TWO KEYS USED TO HOLD A MARK OR A SPACE by hand, chosen by which softkey was
; pressed. That was the rewrite's own idea of manual mode; the instrument's
; drives whatever bit the cursor is sitting on, which is what makes the cursor
; worth moving.
; ---------------------------------------------------------------------------
digital_sk_bitmode
                tst     >digital_running
                lbne    digital_show
                lda     #DIGITAL_FIELD_BIT
                sta     >digital_field
                lda     #$01
                sta     >digital_manual
                lbsr    digital_manual_drive
                lbra    digital_show_armed      ; [$3C00] at $6A0E: the bit index

digital_sk_cont
                ; softkey_run_continuous ($6A18). Pressed while it is already
                ; running it restarts from the first bit rather than doing
                ; nothing: $3CC4 = $FFFF and $3CC6 = $3C20 put the shift
                ; register back to the head of the pattern.
                lbsr    digital_stop_if_running
                clr     >digital_single
                lbsr    digital_run
                lbra    digital_show
digital_sk_single
                ; softkey_single ($6AA1): one pass and then the output parks.
                lbsr    digital_stop_if_running
                lda     #$01
                sta     >digital_single
                lbsr    digital_run
                lbra    digital_show
digital_sk_stop
                lbra    digital_key_stop

; ---------------------------------------------------------------------------
; digital_stop_if_running - take the clock off before starting it again
;
;   uses:  A, B, X, Y, U
; ---------------------------------------------------------------------------
digital_stop_if_running
                tst     >digital_running
                beq     digital_stop_if_done
                lbsr    digital_report_end      ; the stock's stop-then-start
                                                ; pair: softkey_run_continuous
                                                ; calls sequence_run_start_stop
                                                ; (0) at $6A3C and (1) right
                                                ; after it, so a restart
                                                ; reports FINISHED and then
                                                ; STARTED
                lbsr    ABI_tick_remove
                clr     >digital_running
                ldx     #$0000                  ; and from the first bit
                stx     >digital_bit_index
digital_stop_if_done
                rts

; ---------------------------------------------------------------------------
; digital_leave_edit - close an edit session
;
;   uses:  A, B, X, Y
;
; leave_sequence_edit_mode ($5AAA), which screen_hook_leave_edit_mode ($6F60)
; calls for every request but the six that belong to editing - f2, f3, ENTER,
; the two arrows and set-end-here ($6F6B). Selecting any other field is one of
; the requests that closes it, so every arm that selects a field calls this.
;
; THIS USED TO BE TWO CLEARS AND AN RTS, and $5AAA does four more things. The
; read-through of 2026-09-20 found them; all four are visible on the glass or
; at the socket:
;
;   1 $5AC4-$5ACD note whether the cursor $3CA2 has moved away from the window
;     origin $3CD2, and $5ACF-$5AD2 force it BACK to the origin unconditionally
;     - leaving the editor puts the cursor at the left of the window it was
;     showing, so the next arrow starts from there and not from wherever the
;     editing wandered to;
;   2 $5AD4-$5AF1 re-read the element under that restored cursor and push it to
;     the output through read_bit_at_cursor ($54DF) and manual_output_drive_bit
;     ($51F6), so in Manual mode the socket follows the cursor out of the
;     session as it followed it inside;
;   3 $5AF3-$5B0A recompute the bit indices with seq_recompute_bit_indices
;     ($5646), but ONLY when the cursor had in fact moved;
;   4 $5B0C-$5B1F repaint when the argument is non-zero.
;
; THE ORDER OF 2 AND 3 IS THE PART THAT IS EASY TO GET WRONG, and the stock's
; is kept here: the drive at step 2 runs BEFORE the recompute at step 3, so it
; reads the bit index the editing left behind rather than one derived from the
; cursor it has just restored. Swapping them would drive a different bit.
;
; STEP 4 IS DELIBERATELY ABSENT. The stock reaches this from the $2211 hook
; after an entry field is torn down, where nothing else is painting; here all
; six callers - the three field selects, the base select, the page change and
; the refused-request arm - end in digital_show, digital_show_armed or
; ABI_entry_begin, so adding the repaint would paint the screen twice.
; ---------------------------------------------------------------------------
digital_leave_edit
                tst     >digital_edit           ; $5AB2: no session, nothing
                beq     digital_leave_edit_done ; to close
                clr     >digital_edit           ; $5ABE
                clr     >digital_insert         ; $5AC1
                ldx     >digital_index          ; $5AC4: whether it moved is
                cmpx    >digital_window         ; decided BEFORE the store, and
                pshs    cc                      ; the answer has to outlive the
                                                ; drive below
                ldd     >digital_window         ; $5ACF: unconditional
                std     >digital_index
                lbsr    digital_manual_drive    ; $5AD4-$5AF1, with the bit
                puls    cc                      ; index still the old one
                beq     digital_leave_edit_done ; $5AF3: only if it moved
                lbra    digital_bits_index      ; $5646($3CA2): its RTS is ours
digital_leave_edit_done
                rts

; --- page 2: the bit rate --------------------------------------------------
digital_key_page2_f1
                ; THE BIT PERIOD, typed in tenths of a millisecond. The stock
                ; keeps its own at $3C9E and commit_period_entry ($4D5E) hands
                ; the entry to validate_period_minimum ($4B6D), which refuses
                ; below $000A counts and RESTORES the previous value rather
                ; than storing a bad one. Ten counts is a tenth of a
                ; millisecond, so the minimum here is 1 and means the same
                ; interval.
                lbsr    ABI_entry_value         ; carry set if it overflows
                lbcs    digital_period_rearm    ; refused, and re-armed as every
                                                ; $23 arm for the period is
                ; THE DIGITS ARE MILLISECONDS NOW, NOT TENTHS OF ONE, and
                ; that is a change in what the operator types - not a x1
                ; substitution like the level fields. The stock's Period is
                ; class 5 ($B169): Hz means whole milliseconds and kHz seconds,
                ; and there is no key for a tenth. So the smallest period that
                ; can be TYPED goes from 0.1 ms to 1 ms.
                ;
                ; DIGITAL_PERIOD_MIN is unchanged and still means what it did -
                ; validate_period_minimum ($4B6D)'s $000A counts, a tenth of a
                ; millisecond - but it is now a floor the keypad cannot reach
                ; on either firmware, which is exactly the stock's position.
                ; The bus can still set below it and is still refused there.
                lbsr    digital_entry_scale     ; milliseconds from here on
                lbcs    digital_period_refuse
                ldd     >entry_result+1         ; the low sixteen
                tst     >entry_result           ; anything in the top eight is
                bne     digital_period_refuse   ; far past a sane bit rate
                cmpd    #DIGITAL_PERIOD_MIN
                blo     digital_period_refuse
                ; AND A CEILING, WHICH THIS PATH HAD NONE OF. The check above
                ; catches a number too big for sixteen bits of MILLISECONDS,
                ; but the multiply below turns milliseconds into counts by a
                ; hundred and it is the COUNTS that have to fit. 656 ms is
                ; 65,600 counts, and ABI_mul16's low word silently made that
                ; 64 - a 656 ms period keyed as the shortest one the screen
                ; can hold. The stock refuses it outright. Checked here, in
                ; milliseconds, before the multiply can wrap, and on the
                ; shared path so the INCR SET step below is covered too: its
                ; step takes the same x100 into the same sixteen bits.
                cmpd    #DIGITAL_PERIOD_MAX_MS
                bhi     digital_period_refuse

                tst     >digital_incr_mode      ; INCR SET diverts the same
                beq     digital_period_value    ; entry to the STEP
                clr     >digital_incr_mode
                ; THE STEP IS IN THE SAME UNIT AS THE VALUE IT STEPS, so it
                ; takes the same conversion: milliseconds to counts is a
                ; hundred, not ten. This was an inline x10 beside the value's
                ; own x10, and leaving it would have put the step in tenths
                ; while the value moved to milliseconds - which is the
                ; inconsistency the channel screen's increment already had to
                ; be taught out of.
                ldx     #TONE_MS_COUNTS
                lbsr    ABI_mul16
                ldd     >math_product+2
                std     >incr_digital
                lbra    digital_period_rearm
digital_period_value

                ; MILLISECONDS x 100 = TIMER COUNTS, converted ONCE here
                ; rather than on every run. digital_period holds COUNTS from
                ; here on, which is the unit the stock's $3C9E holds and the
                ; unit seq_timer_period wants.
                ; MILLISECONDS TO COUNTS, which is a hundred and not ten. This
                ; was an inline x10 because the field was typed in tenths; with
                ; the unit key naming milliseconds it is TONE_MS_COUNTS, the
                ; same constant the tone and DTMF times use.
                ldx     #TONE_MS_COUNTS
                lbsr    ABI_mul16
                ldd     >math_product+2
                std     >digital_period
digital_period_rearm
                ; A FRESH FIELD AFTER EVERY COMMIT, accepted or refused. The
                ; entry buffer kept its digits, so a second period typed after
                ; the first APPENDED to it - 20 then 0 became 200, which is
                ; ten times what was asked for and would have been ten times
                ; slower on the socket.
                lda     #ENTRY_DECIMAL
                ldb     #TEXT_DIGITS
                lbsr    ABI_entry_begin
                lbra    digital_show_armed      ; [$3C00] at $4DA0 and $4DD7
digital_period_refuse
                ldb     #ERR_TIME_RANGE          ; the bit period IS a time, and
                                                 ; $32 is 'Time value out of
                                                 ; range'. The previous value stands,
                lbsr    ABI_error_raise          ; as it does in the stock
                bra     digital_period_rearm

; ---------------------------------------------------------------------------
; digital_cycle_base - the base one step along, in either direction
;
;   entry: B = the direction, $01 up or $FF down
;   uses:  A, B
;
; The stock's cycle_sequence_base ($5095), arm [11] of the step dispatch, for
; $3CAC = $0E. It copies $3C20 to a local, tests the direction argument at
; $000E,S ($509E CMPX #$0000): non-zero adds one ($50A7 ADDB #$01), zero
; subtracts one ($50B0 SUBB #$01). Then two wraps in sequence whatever the
; direction was: $50B6 CMPB #$03 turns 3 into 0, and $50C4 CMPD #$00FF turns
; $FF into 2. Bin, Oct, Hex round one way; Hex, Oct, Bin round the other.
; It then calls change_sequence_base ($56E9), display_base_name ($4959),
; repaint_sequence_editor ($5A0F) and [$3C00](6) - here the whole screen is
; repainted by digital_show, and a step is one byte shown whole, so there is
; no digit capacity for change_sequence_base to rescale.
; ---------------------------------------------------------------------------
digital_cycle_base
                lda     >digital_base           ; $5095 LDB >$3C20
                tstb
                bmi     digital_cycle_base_down
                inca                            ; $50A7 ADDB #$01
                bra     digital_cycle_base_wrap
digital_cycle_base_down
                deca                            ; $50B0 SUBB #$01
digital_cycle_base_wrap
                cmpa    #DIGITAL_BASES          ; $50B6 CMPB #$03: 3 -> 0
                bne     digital_cycle_base_low
                clra
digital_cycle_base_low
                cmpa    #$FF                    ; $50C4 CMPD #$00FF: $FF -> 2
                bne     digital_cycle_base_set
                lda     #DIGITAL_BASE_HEX
digital_cycle_base_set
                lbsr    digital_base_change     ; $50CE hands the new base to
                lbra    digital_show_armed      ; cycle_sequence_base, $50FD


; ---------------------------------------------------------------------------
; digital_base_change - re-express the same bit stream in a different base
;
;   entry: A = the new base
;   uses:  A, B, X, Y, U
;
; change_sequence_base ($56E9). THE BIT STREAM IS THE FACT AND THE DIGIT
; INDICES ARE A VIEW OF IT: the cursor and the end are rebuilt by DIVIDING
; the bit indices $3CA6 and $3CA8 by the new width ($5709 copies them for
; binary, $5718 divides by 3, $5733 by 4), not by rescaling the digit numbers.
; The same 1000 bits are 1000 binary digits, 333 octal or 250 hexadecimal, so
; a cursor sitting on bit 400 stays on bit 400 whatever it is now called.
;
; THE BIT INDICES THEMSELVES ARE NOT RECOMPUTED, which is why they survive
; being clamped: the routine refreshes only the PLAYER's copy $3CAA ($578E
; passes $3CAA to seq_recompute_bit_indices), leaving $3CA8 as it was.
; Recompute $3CA8 here and a base change that clamped the end would shorten
; the sequence, and changing base back would not lengthen it again.
;
; A CHANGE TO THE BASE IT IS ALREADY IN DOES NOTHING ($56F1 CMPD / LBEQ).
; ---------------------------------------------------------------------------
digital_base_change
                cmpa    >digital_base
                beq     digital_base_same
                sta     >digital_base

                cmpa    #DIGITAL_BASE_BIN       ; $574E's three-way switch
                beq     digital_base_wide1
                cmpa    #DIGITAL_BASE_OCT
                beq     digital_base_wide3
                ldd     #DIGITAL_W_HEX          ; $5733: divide by 4
                bra     digital_base_divide
digital_base_wide3
                ldd     #DIGITAL_W_OCT          ; $5718: by 3
                bra     digital_base_divide
digital_base_wide1
                ldx     >digital_end_bit        ; $5709: a binary digit IS a
                stx     >digital_end            ; bit, so the indices copy
                ldx     >digital_index_bit
                stx     >digital_index
                bra     digital_base_limits
digital_base_divide
                pshs    d                       ; the width, wanted twice
                ldx     >digital_end_bit
                ldd     ,s
                lbsr    ABI_div16               ; X = the digit that bit is in
                stx     >digital_end
                ldx     >digital_index_bit
                ldd     ,s++
                lbsr    ABI_div16
                stx     >digital_index
digital_base_limits
                lbsr    digital_limits          ; $575D: the new capacity, and
                                                ; both indices clamped to it -
                                                ; digital_limits is
                                                ; set_max_length_for_base plus
                                                ; the two clamps at $576E and
                                                ; $577E
                lbsr    digital_bits_last       ; $578E: the PLAYER's end bit
                                                ; only
                ldx     >digital_index          ; $5799: and the window starts
                stx     >digital_window         ; on the cursor again, because
                ldx     #$0000                  ; the digit it sits in has a
                stx     >digital_column         ; different number now
digital_base_same
                rts


digital_key_next
                cmpb    #KEY_NEXT
                bne     digital_key_last
                lda     >digital_page
                inca
                cmpa    #DIGITAL_PAGES
                blo     digital_key_page_set
                clra
                bra     digital_key_page_set
digital_key_last
                cmpb    #KEY_LAST
                bne     digital_key_error
                lda     >digital_page
                bne     digital_key_page_back
                lda     #DIGITAL_PAGES
digital_key_page_back
                deca
digital_key_page_set
                ; NEXT AND LAST ARE THE MENU KEYS. key_menu_page_change
                ; ($6B20) is the arm for request codes $17 and $18: it flushes
                ; the open entry, hands the key to the main ROM's
                ; dispatch_menu_action, sets $3CAC = 0 and calls
                ; adopt_menu_page ($672A) to repaint the record. So changing
                ; page deselects whatever was selected - a field on the record
                ; that is no longer showing cannot be typed into.
                ;
                ; THEY USED TO STEP A POSITION IN A SIXTEEN-STEP SEQUENCE that
                ; the instrument does not have, and f4 paged the menu in their
                ; place.
                sta     >digital_page
                sta     >active_record          ; $268E, which a save and a
                                                ; power-off carry
                lbsr    digital_leave_edit
                clr     >digital_field
                clr     >entry_active
                clr     >digital_incr_mode

                ; AND THE PLAYER PAGE RE-DRIVES THE OUTPUT BIT. adopt_menu_page
                ; ($672A) splits on the page it has just adopted: page 2 calls
                ; select_keypad_numeric_field ($6358)(0) and stops, page 3
                ; calls it with 8 and then, at $675E and only when the Manual
                ; flag $3C04 is non-zero, re-reads the bit under the cursor and
                ; drives it. So walking onto the Bit row with Manual on puts
                ; the socket back on the cursor's bit; walking onto any other
                ; page does not.
                ;
                ; The $3C04 half of that test is inside digital_manual_drive
                ; already - it opens with TST >digital_manual - so only the
                ; page half belongs here. A is not the page any more: the call
                ; above clobbers it.
                lda     >digital_page
                cmpa    #DIGITAL_PAGE_PLAYER
                bne     digital_key_page_shown
                lbsr    digital_manual_drive    ; $675E
digital_key_page_shown
                lbra    digital_show

digital_key_error
                ; SHIFTED INC SET FLASHES THE LAST ERROR HERE TOO. Arm [15] of
                ; the page-2 dispatch at $6E67 is four instructions - a call to
                ; show_last_error_screen ($C418) with no argument, then a fall
                ; into key_close_entry_field ($6E3A) - so the screen answers
                ; message $0010 exactly as the Main Selection Level does and
                ; closes whatever was half-typed. It was answered on the Main
                ; Selection alone here, and an operator who is refused ON THIS
                ; SCREEN is the one who wants the words.
                cmpb    #KEY_S_INC_SET
                bne     digital_key_incr
                lbsr    ABI_error_show
                clr     >digital_field
                clr     >entry_active
                clr     >digital_incr_mode
                lbra    digital_show

digital_key_incr
                ; INCR SET on the period page: the next f1 stores the number
                ; as the period's STEP rather than as the period. One-shot,
                ; as everywhere else in this tree.
                cmpb    #KEY_INC_SET
                bne     digital_key_up
                ; ONLY A LEVEL AND THE PERIOD HAVE AN INCREMENT. key_increment_set
                ; ($6B87) dispatches on $3CAC at l6bf1: 3 and 4 display the level's
                ; increment and arm it through [$3C00] with 1 ($6BB1), 5 and 6 the
                ; period's with 2 ($6BDF), and every other value - nothing
                ; selected, the base, the indices, the data cell - is l6be9, LDB
                ; #$14 / STB >$3cdc, error $14 and no arm. This took INC SET with
                ; nothing selected on the editor and on every field but the base.
                lda     >digital_field
                cmpa    #DIGITAL_FIELD_MARK
                beq     digital_key_incr_arm
                cmpa    #DIGITAL_FIELD_SPACE
                beq     digital_key_incr_arm
                cmpa    #DIGITAL_FIELD_PERIOD
                beq     digital_key_incr_arm
                ldb     #ERR_NOT_STEPPABLE      ; l6be9: $14, 'Not an incrementable
                lbra    ABI_error_record        ; field', and nothing armed
digital_key_incr_arm
                lda     #$01
                sta     >digital_incr_mode
                lbra    digital_show_armed      ; $6BB1 / $6BDF

digital_key_up
                cmpb    #KEY_UP
                bne     digital_key_dn
                ldb     #$01
                lbra    digital_step
digital_key_dn
                cmpb    #KEY_DOWN
                lbne    digital_key_minus
                ldb     #$FF
                lbra    digital_step

; ---------------------------------------------------------------------------
; digital_step - an arrow: move the selected thing by its increment
;
;   entry: B = +1 up, $FF down
;   uses:  A, B, X, Y, U
;
; seq_step_selected_field ($4E9A): a guarded dispatch on $3CAC over 3 to $0E
; ($510F CMPX #$000E / SUBD #$0003), with a not-steppable arm ($5107) for the
; values inside the range that have nothing to step. Nothing selected is
; outside the range and is refused by the guard.
;
; IT USED TO STEP WHATEVER THE SOFTKEY PAGE SAID - the period on page 2 and a
; bit index everywhere else - because there were no selectable fields to
; dispatch on. There are now, and which one the arrows move is the one the
; operator selected, which is the whole point of selecting it.
; ---------------------------------------------------------------------------
digital_step
                pshs    b                       ; THE DIRECTION, and it has to
                                                ; be pushed: the first draft
                                                ; read `tst ,s` with nothing
                                                ; on the stack, so it tested
                                                ; the return address and every
                                                ; arrow stepped downward.
                lda     >digital_field
                beq     digital_step_none
                cmpa    #DIGITAL_FIELD_BASE
                lbeq    digital_step_base
                cmpa    #DIGITAL_FIELD_PERIOD
                lbeq    digital_step_period
                cmpa    #DIGITAL_FIELD_DATA
                beq     digital_step_cursor
                cmpa    #DIGITAL_FIELD_BIT
                beq     digital_step_cursor
                cmpa    #DIGITAL_FIELD_INDEX
                beq     digital_step_number
                cmpa    #DIGITAL_FIELD_END
                beq     digital_step_number
                lbra    digital_step_level
digital_step_none
                leas    1,s                     ; $510F's guard: there is
                ldb     #ERR_NO_STEP_FIELD      ; nothing to step, and
                lbra    ABI_error_record        ; seq_step_field_not_steppable
                                                ; ($5109) stores 4 in $3CDC -
                                                ; not $14 - and l513a reports
                                                ; it, $9DD3 while remote

; ---------------------------------------------------------------------------
; digital_step_cursor - an arrow on the data cursor or the manual bit
;
;   uses:  A, B, X, Y, U
;
; step_sequence_index_field ($5062) into step_sequence_field's $3CAC = 9 arm,
; and step_manual_bit_position ($501F), which is the same move followed by
; read_bit_at_cursor and manual_output_drive_bit - which is what
; digital_manual_drive is.
; ---------------------------------------------------------------------------
digital_step_cursor
                puls    b
                lbsr    digital_cursor_step
                lbsr    digital_manual_drive
                lbra    digital_show_armed      ; $5EF6, $5058: moved or not

; ---------------------------------------------------------------------------
; digital_step_number - an arrow on Seq Index or Seq End
;
;   uses:  A, B, X, Y, U
;
; step_sequence_field's $5EFE arm. It steps whichever index $3CD0 aims at,
; refuses to go above $3CCE or below zero ($5F1C-$5F64), and then puts the
; move through the same clamp a typed number goes through - so an arrow that
; walks the cursor off the end of the sequence is undone with error $37, and
; an arrow that shortens the sequence under the cursor drags the cursor with
; it.
; ---------------------------------------------------------------------------
digital_step_number
                ldu     >digital_field_ptr
                ldx     ,u                      ; $6233: keep the previous
                pshs    x                       ; value for the clamp
                tst     2,s                     ; the direction, behind it
                bmi     digital_step_num_down
                cmpx    >digital_max            ; $5F1C: not above the base's
                bhs     digital_step_num_stuck  ; capacity
                leax    1,x
                bra     digital_step_num_store
digital_step_num_down
                cmpx    #$0000                  ; $5F4B: and not below zero
                beq     digital_step_num_stuck
                leax    -1,x
digital_step_num_store
                tfr     x,d
                std     ,u
                puls    x                       ; the previous value
                leas    1,s                     ; and the direction
                lbsr    edit_clamp_index        ; $5F70

                ldx     >digital_field_ptr      ; $5F7E: the bit index of
                cmpx    #digital_index          ; whichever one moved
                bne     digital_step_num_end
                lbsr    digital_bits_index
                ldx     >digital_index          ; $5FB0: and the window
                stx     >digital_window         ; follows the cursor
                ldx     #$0000
                stx     >digital_column
                lbra    digital_show_armed      ; [$3C00] at $600C / $601F
digital_step_num_end
                lbsr    digital_bits_end
                lbra    digital_show_armed      ; [$3C00] at $600C / $601F
digital_step_num_stuck
                leas    3,s                     ; the previous value and the
                lbra    digital_show_armed      ; direction; $5F46 CLR 8,S
                                                ; leaves it unchanged and
                                                ; repaints

digital_step_period
                ldd     >incr_digital
                bne     digital_step_have
                ldd     #DIGITAL_TENTH          ; never set: one tenth of a
                std     >incr_digital           ; millisecond a press
digital_step_have
                pshs    d                       ; the increment; the direction
                ldd     >digital_period         ; is at 2,s behind it
                tst     2,s
                bmi     digital_step_period_down
                addd    ,s++                    ; pops the increment
                bcc     digital_step_period_set
                ldd     #$FFFF                  ; clamped, not wrapped
                bra     digital_step_period_set
digital_step_period_down
                subd    ,s++                    ; pops it too, on this path
                bcc     digital_step_period_min
                clra
                clrb
digital_step_period_min
                cmpd    #DIGITAL_TENTH          ; the stock's $000A counts
                bhs     digital_step_period_set
                ldd     #DIGITAL_TENTH
digital_step_period_set
                std     >digital_period
                leas    1,s                     ; the direction
                lbra    digital_show_armed      ; and re-armed ($5015)

digital_step_base
                puls    b                       ; the direction, $01 or $FF
                lbra    digital_cycle_base

digital_key_minus
                ; THE SIGN OF A LEVEL. A level field is signed:
                ; arm_level_entry_field ($6653) arms entry mode 2 while the
                ; increment is not live ($3CDD zero at $6653), and mode 2 is
                ; the one that reserves the head of the entry buffer $239A
                ; for a sign ($ACE8 stores '+' there and starts the digits at
                ; 1). The MINUS key puts '-' in that cell: at $B02E in
                ; entry_key_column7_decimal ($AF5F) the keyed character is
                ; compared with $2D and stored at $239A. Nothing restores '+'
                ; but a fresh field ($ACE8) or a backspace to empty ($B351),
                ; and this screen re-arms the field after every commit. The
                ; increment is unsigned - enter_level_increment ($4D26) stores
                ; no sign and $6653 arms mode 3 for it - so MINUS with INCR
                ; SET armed is refused, as it is on the period field (mode 3,
                ; $6691), the base field and the step row.
                cmpb    #KEY_MINUS
                bne     digital_key_endhere
                lbsr    ABI_entry_is_open       ; lb494
                lbeq    digital_key_ignore      ; $B49D
                lda     >digital_field
                lbeq    digital_key_ignore      ; long: the BACKSPACE arm
                cmpa    #DIGITAL_FIELD_BASE     ; below put the target
                lbeq    digital_key_ignore      ; out of a short branch's
                tst     >digital_incr_mode      ; reach
                lbne    digital_key_ignore
                lda     #DIGITAL_SIGN_MINUS
                sta     >digital_entry_sign
                lbsr    digital_show            ; the row again, and the entry
                lbra    digital_key_echo        ; over it with its sign

digital_key_endhere
                ; SHIFTED ENTER SETS THE SEQUENCE END AT THE CURSOR.
                ; key_set_seq_end_here ($6C75) is arm [37] of the stock's own
                ; dispatch, reached by request code $26, and key 52 - shifted
                ; ENTER - is the key that posts it ($AE1A). It is one of the
                ; six requests screen_hook_leave_edit_mode ($6F6B) does NOT
                ; close an edit session for, because setting the end is part
                ; of editing.
                cmpb    #KEY_S_ENTER
                bne     digital_key_backspace
                lbsr    edit_set_end_here
                ; AND ON THE EDITOR ITS FIELD IS RE-ARMED. key_set_seq_end_here
                ; ($6C75) passes 2 - $3C1F to set_seq_end_to_index ($5D08), which
                ; stores the end and then, only for a zero argument, repaints and
                ; re-arms by $3CAC: 8 is Seq Index ($5D53), $0A Seq End ($5D70), 9
                ; the data cell ($5D89), and anything else arms nothing.
                lda     >digital_page
                cmpa    #DIGITAL_PAGE_EDITOR    ; $3C1F = 2
                lbne    digital_show
                lda     >digital_field
                cmpa    #DIGITAL_FIELD_INDEX
                lbeq    digital_show_armed
                cmpa    #DIGITAL_FIELD_END
                lbeq    digital_show_armed
                cmpa    #DIGITAL_FIELD_DATA
                lbeq    digital_show_armed
                lbra    digital_show

digital_key_backspace
                cmpb    #KEY_BACKSPACE
                bne     digital_key_units
                lbsr    ABI_entry_is_open       ; lb494
                lbeq    digital_key_ignore      ; $B49D
                ; THE LAST CHARACTER OUT AGAIN. entry_backspace ($B2CD,
                ; reached at $B4B9 for key $1F) steps the head $23A4 back and
                ; blanks the vacated cell for kind 3 - the period field
                ; ($6691) and a level's increment ($6653 with $3CDD live) -
                ; at $B2E9-$B31F; for kind 2, a level ($6653: l6664 LDD
                ; #$0002 / STD 7,s), it steps back only while a digit follows
                ; the sign ($B320 CMPB #$01 / LBLS) and otherwise puts '+'
                ; back at the head ($B351-$B35A). The repaint ($B4D0-$B501)
                ; follows only once a key has been accepted ($B4C4 tests
                ; $23A7), which is entry_active here; the sign lives in
                ; digital_entry_sign, and which fields are signed is the
                ; MINUS arm's test above. The base field ($66D3, width 0)
                ; and the step row off page 2 take no entry: refused, as
                ; every key this screen cannot use is.
                lda     >digital_field
                lbeq    digital_key_ignore      ; nothing selected takes no
                cmpa    #DIGITAL_FIELD_BASE     ; entry, and neither does the
                lbeq    digital_key_ignore      ; zero-width base field
                tst     >entry_active           ; $B4C4: nothing accepted,
                lbeq    digital_key_no_echo     ; nothing to show ($B4CD)
                cmpa    #DIGITAL_FIELD_MARK     ; only the two LEVELS are
                beq     digital_backspace_sign  ; signed - kind 2. Every other
                cmpa    #DIGITAL_FIELD_SPACE    ; field here is kind 3 and
                bne     digital_backspace_digit ; unsigned
digital_backspace_sign
                tst     >digital_incr_mode      ; a level's increment: kind 3
                bne     digital_backspace_digit
                tst     >entry_count            ; a level, kind 2: a digit
                bne     digital_backspace_digit ; after the sign comes out;
                lda     #DIGITAL_SIGN_PLUS      ; with none left the sign
                sta     >digital_entry_sign     ; goes back to '+' ($B351)
                bra     digital_backspace_show
digital_backspace_digit
                lbsr    ABI_entry_backspace     ; $B2E9-$B31F, slot 73
digital_backspace_show
                lbsr    digital_show            ; $B4D0-$B501: the row again
                lda     >digital_field          ; and the entry over its
                lbeq    digital_key_no_echo     ; field, as after a digit
                lbra    digital_key_echo


; ---------------------------------------------------------------------------
; digital_entry_scale - apply the unit key's meaning to the digits just typed
;
;   exit:  carry SET, and last_error written, if the scaled value will not fit
;          or the unit has no decade; carry CLEAR otherwise
;   uses:  A, B, X, Y, U
;
; The same routine as page1_tone.s's tone_entry_scale, written again because
; that one is in a different image and only the ABI crosses between them.
; ABI_unit_apply does cross - it is slot 24 - so what is duplicated here is six
; instructions, not the arithmetic.
;
; A ZERO CODE MEANS NO UNIT KEY WAS PRESSED, which is every path that still
; commits on ENTER. UNIT_BLANK is zero and unit_decades refuses it, so the test
; comes first rather than being left to unit_apply.
; ---------------------------------------------------------------------------
digital_entry_scale
                lda     >tone_entry_unit
                beq     digital_entry_scale_none
                ldb     >tone_entry_unit
                ldx     #entry_result
                lbsr    ABI_unit_apply
                bcs     digital_entry_scale_bad
digital_entry_scale_none
                clr     >tone_entry_unit        ; one entry, one unit
                andcc   #~CC_CARRY
                rts
digital_entry_scale_bad
                clr     >tone_entry_unit
                orcc    #CC_CARRY
                rts

digital_key_units
                ; THE TWO CLASSES THIS SCREEN CARRIES. A mark or space level
                ; is class 4 ($B127): deg microvolts, Hz millivolts, kHz
                ; volts. The bit period is class 5 ($B169): Hz milliseconds,
                ; kHz seconds, deg refused. WHICH FIELD IS OPEN decides which
                ; applies - it used to be the softkey page, because the period
                ; had no field of its own to be selected into.
                ;
                ; The two indices and the data cursor are plain numbers with
                ; no unit at all, so a unit key on one of them is a key the
                ; field cannot use and falls through to the digits, which
                ; refuse it.
                ;
                ; AT THE END OF THE DISPATCH CHAIN, falling through to the
                ; digits, so no arm below it is orphaned.
                ; THE FIELD KEYS ARE NOT THIS MODE'S. FREQ, AMPL, WAVEFORM and
                ; PHASE post requests $19 to $1C, arms [24] to [27] of the
                ; $6E67 table, and from the panel every one of them ends at
                ; key_reject_unhandled_code ($6E4F), LDB #$3A into $3CDC -
                ; AMPL too, since msg_select_level_by_index ($6C8D) takes its
                ; level arms only from the bus ($6C91 bit 3 of event_flags).
                ; These fell through to digital_key_ignore and recorded $0F:
                ; driven, FREQ on Seq Base Hex leaves $23DE = $3A on the
                ; instrument and 15 here.
                cmpb    #KEY_FREQ
                beq     digital_key_wrong_mode
                cmpb    #KEY_AMPL
                beq     digital_key_wrong_mode
                cmpb    #KEY_WAVEFORM
                beq     digital_key_wrong_mode
                cmpb    #KEY_PHASE
                bne     digital_key_no_field
digital_key_wrong_mode
                ldb     #DIGITAL_ERR_WRONG_MODE ; l6edf reports $3CDC with
                lbra    ABI_error_record        ; error_report_beep: stored
                                                ; and beeped, nothing painted
digital_key_no_field
                ; A DIGIT OR A UNIT WITH NOTHING ARMED: numeric_entry_key_
                ; handler's lb494 ($B494) finds $23A8 clear and beeps code 1
                ; before any column lookup - driven, '8' with no field leaves
                ; $23DE = 1, where this recorded 15.
                lbsr    ABI_entry_is_open       ; the cursor bit is $23A8
                bne     digital_key_field_open
                cmpb    #KEY_DEG                ; the three unit keys, arms
                beq     digital_key_no_entry    ; [27] to [29] of dae3d, are
                cmpb    #KEY_HZ                 ; unclaimed and reach lb494
                beq     digital_key_no_entry    ; the same way
                cmpb    #KEY_KHZ
                beq     digital_key_no_entry
                cmpb    #KEY_ENTER
                beq     digital_key_no_entry
                pshs    b
                lbsr    ABI_key_digit           ; a digit? carry clear if so
                puls    b
                lbcs    digital_key_ignore
digital_key_no_entry
                ldb     #ERR_NO_ENTRY_FIELD     ; lb494 -> error_report_beep
                lbra    ABI_error_raise         ; ($C3FE): no bus report
digital_key_field_open
                lda     >digital_field
                lbeq    digital_key_ignore
                cmpa    #DIGITAL_FIELD_BASE
                lbeq    digital_key_ignore
                cmpa    #DIGITAL_FIELD_PERIOD
                beq     digital_key_unit_time
                cmpa    #DIGITAL_FIELD_MARK
                beq     digital_key_unit_level
                cmpa    #DIGITAL_FIELD_SPACE
                beq     digital_key_unit_level
                lbra    digital_key_digit
digital_key_unit_time
                cmpb    #KEY_HZ
                bne     digital_key_unit_s
                ldb     #UNIT_MILLISEC
                bra     digital_key_unit_period
digital_key_unit_s
                cmpb    #KEY_KHZ
                lbne    digital_key_digit       ; NOT A UNIT KEY AT ALL: fall
                                                ; through to the digits, which
                                                ; is how a digit typed into
                                                ; the period gets there. This
                                                ; refused instead, so every
                                                ; digit typed into the period
                                                ; field was thrown away and
                                                ; the commit that followed had
                                                ; nothing to commit. deg is
                                                ; the one key class 5 ($B169)
                                                ; really has no arm for, and
                                                ; the digit path refuses it.
                ldb     #UNIT_SECOND
digital_key_unit_period
                stb     >tone_entry_unit
                lbsr    ABI_entry_cursor_off    ; $B5BA, then request $23
                lbra    digital_key_page2_f1    ; PAST THE no-unit GUARD. The
                                                ; softkey refuses a commit
                                                ; with digits typed and no
                                                ; unit named, which is class
                                                ; 5's rule; the unit key IS
                                                ; the terminator, so it enters
                                                ; the commit below that test.
                                                ; Sending it to the softkey's
                                                ; own entry point would have
                                                ; refused every period ever
                                                ; typed
digital_key_unit_level
                cmpb    #KEY_DEG
                bne     digital_key_unit_mv
                ldb     #UNIT_MICROVOLT
                bra     digital_key_unit_go
digital_key_unit_mv
                cmpb    #KEY_HZ
                bne     digital_key_unit_v
                ldb     #UNIT_MILLIVOLT
                bra     digital_key_unit_go
digital_key_unit_v
                cmpb    #KEY_KHZ
                lbne    digital_key_digit
                ldb     #UNIT_VOLT
digital_key_unit_go
                stb     >tone_entry_unit
                lbsr    ABI_entry_cursor_off    ; $B5BA, then request $23
                lbra    digital_commit_level

digital_key_digit
                ; DIGITS GO TO WHICHEVER FIELD IS SELECTED, and the two that
                ; take none are the ones the instrument arms with no width:
                ; nothing selected at all, and the base ($66D3 arms width 0).
                ; This screen had no digit path whatever once - digits
                ; belonged to an editor screen that does not exist - so the
                ; period, the two indices and the pattern itself had nowhere
                ; to be keyed.
                lda     >digital_field
                lbeq    digital_key_ignore
                cmpa    #DIGITAL_FIELD_BASE
                lbeq    digital_key_ignore
                lbsr    ABI_key_digit
                lbcs    digital_key_ignore
                lbsr    ABI_entry_digit
                lda     #$01                    ; something has been typed:
                sta     >entry_active           ; ENTER commits rather than
                lbsr    digital_show            ; being refused

; ---------------------------------------------------------------------------
; digital_key_echo - the digits typed so far, over the field they are for
;
;   uses:  A, B, X, Y, U
;
; The main ROM's own repaint at $B4D0-$B501 does this on the instrument, over
; the field arm_numeric_entry_field ($AC35) armed - so the column and the
; width come from the field, not from a constant. They came from a constant
; here, DIGITAL_LVL_POS, because there was one field to type into.
;
; AND THE DISPLAY'S ADDRESS AFTER THE LAST CHARACTER, which is where the cursor
; shows while the field is armed. The stock follows every repaint of the
; buffer with lcd_set_cursor($23AD + $23A4) - $B4E9-$B4FA after a BACKSPACE,
; $B556-$B567 after a character - and $23A4 counts the level's sign, which
; entry mode 2 keeps at the head of $239A ($ACE8). This left the address after
; the field's last blank, so the cursor stood past the end of every number.
; ---------------------------------------------------------------------------
digital_key_echo
                lbsr    digital_echo_text
                ldx     #digital_field_pages    ; on the field's own page only,
                lda     >digital_field          ; as the text
                lda     a,x
                cmpa    >digital_page
                bne     digital_echo_cursor_none
                lbsr    digital_entry_field     ; A = $23AD
                adda    >entry_count            ; + $23A4's digits
                ldb     >digital_field
                cmpb    #DIGITAL_FIELD_MARK
                beq     digital_echo_cursor_level
                cmpb    #DIGITAL_FIELD_SPACE
                bne     digital_echo_cursor_put
digital_echo_cursor_level
                tst     >digital_incr_mode      ; a level, not its increment:
                bne     digital_echo_cursor_put ; mode 2, and $23A4 counts the
                inca                            ; sign as well
digital_echo_cursor_put
                lbra    ABI_lcd_cursor          ; $B4FA / $B567
digital_echo_cursor_none
                rts

; ---------------------------------------------------------------------------
; digital_echo_text - the characters of the entry, painted over the field
;
;   uses:  A, B, X, Y, U
; ---------------------------------------------------------------------------
digital_echo_text
                ; AND ONLY ON THE PAGE THE FIELD IS DRAWN ON. See
                ; digital_field_pages below for the stock's own rule and for
                ; what this painted without it.
                ldx     #digital_field_pages
                lda     >digital_field
                lda     a,x
                cmpa    >digital_page
                bne     digital_key_no_echo

                lbsr    digital_entry_field     ; A = the column, B = how wide
                pshs    a,b                     ; 0,s the column, 1,s the width
                ldx     #text_buffer            ; entry_render takes X and
                lbsr    ABI_entry_render        ; writes entry_width characters
                lda     ,s
                ldb     1,s
                ldx     #text_buffer
                lbsr    ABI_lcd_write_raw       ; the echo: glass only, as
                                                ; lcd_write_string_at ($D8A5)

                ; AND THE ENTRY'S SIGN AGAINST ITS FIRST DIGIT, the way the
                ; committed value's is set by level_sign_right_justify ($4569).
                ; Until a digit is typed there is nothing to set it against,
                ; so a MINUS on an empty field shows on the first digit that
                ; follows it. An increment carries no sign ($4D26), and ONLY
                ; THE TWO LEVEL FIELDS ARE SIGNED at all - the period, the two
                ; indices and the data cursor are unsigned numbers.
                tst     >digital_incr_mode
                bne     digital_key_echo_done
                lda     >digital_field
                cmpa    #DIGITAL_FIELD_MARK
                beq     digital_key_echo_sign
                cmpa    #DIGITAL_FIELD_SPACE
                bne     digital_key_echo_done
digital_key_echo_sign
                clra                            ; Y = the width, as a word
                ldb     1,s
                tfr     d,y
                lda     >digital_entry_sign
                ldx     #text_buffer
                ldb     ,s                      ; B = the field's first column
                leas    2,s
                lbra    digital_sign_place
digital_key_echo_done
                leas    2,s
digital_key_no_echo
                rts

; ---------------------------------------------------------------------------
; digital_field_pages - which softkey page each field is drawn on
;
; THE INSTRUMENT PAINTS NOTHING FOR A FIELD WHOSE PAGE IS NOT SHOWING.
; lcd_write_text_if_page ($44EE) is the painter every page-2 field goes
; through: it loads $3C1F - the current menu page, which adopt_menu_page
; ($672A) reloads from $268E - zero-extends it and CMPDs it against the
; caller's page argument, and only on a match does it call lcd_write_clipped
; ($D8EA). draw_unit_label_if_page ($451B) and
; show_entry_cursor_char_if_screen ($4544) make the same test before their
; own writes. Twelve call sites in the stock, and no page-2 field is written
; any other way.
;
; A FIELD CAN BE SELECTED FROM A PAGE IT IS NOT ON. The bus's SEQP and SEQE
; select Seq Index and Seq End wherever the operator is standing -
; msg_select_seq_index ($6D48) and msg_select_seq_end ($6D9D) set $3CAC and
; $3CD0 without looking at the page - and WSQ's key_bulk_seq_entry ($6DDE)
; selects the data cursor the same way. Driven on the stock 2026-09-13 with
; the settings record showing: 'SEQE 10;' followed by three digit keys leaves
; both lines exactly as they were.
;
; This firmware echoed the typed digits over whatever occupied those columns.
; Seq End's four are the On Level's digits on the settings record, so
; 'SEQE 10;' and three digits read ' On Lev   0000 V '; Seq Index's four are
; the 'x' of ' Seq Base Hex ', so 'WSQ;' 'SEQP?;' and three digits read
; ' Seq Base He0000 '. Both measured against the stock on 2026-09-13.
;
; One byte per DIGITAL_FIELD_*, in their own order. DIGITAL_PAGES is one past
; the last real page, so the unselected field matches nothing.
; ---------------------------------------------------------------------------
digital_field_pages
                fcb     DIGITAL_PAGES           ; FIELD_NONE: no page at all
                fcb     DIGITAL_PAGE_SETTINGS   ; FIELD_MARK, the On Level
                fcb     DIGITAL_PAGE_SETTINGS   ; FIELD_SPACE, the Off Level
                fcb     DIGITAL_PAGE_SETTINGS   ; FIELD_BASE
                fcb     DIGITAL_PAGE_SETTINGS   ; FIELD_PERIOD
                fcb     DIGITAL_PAGE_EDITOR     ; FIELD_INDEX
                fcb     DIGITAL_PAGE_EDITOR     ; FIELD_DATA, in the window
                fcb     DIGITAL_PAGE_EDITOR     ; FIELD_END
                fcb     DIGITAL_PAGE_PLAYER     ; FIELD_BIT

; ---------------------------------------------------------------------------
; digital_entry_field - where the selected field is, and how wide
;
;   exit:  A = the field's first DDRAM column, B = how many characters
;   uses:  A, B
;
; arm_entry_field_for_parameter ($6646), the vector every softkey on the
; instrument's page 2 JSRs through $3C00 to arm its own field. It is one
; routine there taking a field number and one routine here reading
; digital_field, which is the same number by another name.
;
; The data cursor's column MOVES with the cursor - $15 plus $3CD4, which is
; what arm_data_digit_entry_field ($5866) computes - so it cannot be a
; constant like the rest.
; ---------------------------------------------------------------------------
digital_entry_field
                lda     >digital_field
                cmpa    #DIGITAL_FIELD_MARK
                beq     digital_entry_f_on
                cmpa    #DIGITAL_FIELD_SPACE
                beq     digital_entry_f_off
                cmpa    #DIGITAL_FIELD_PERIOD
                beq     digital_entry_f_per
                cmpa    #DIGITAL_FIELD_INDEX
                beq     digital_entry_f_ix
                cmpa    #DIGITAL_FIELD_END
                beq     digital_entry_f_end
                cmpa    #DIGITAL_FIELD_BIT
                beq     digital_entry_f_bit
                ldb     >digital_column+1       ; the data cursor, one cell
                addb    #DIGITAL_WIN_POS        ; wide, wherever it is
                tfr     b,a
                ldb     #$01
                rts
                ; THE ENTRY FIELD IS SIX COLUMNS FROM THE SIGN COLUMN, not
                ; five from the digits: arm_level_entry_field ($6653) passes
                ; six digits at $4A for the On row and $5F for the Off row
                ; ($6672-$6690), which is one before each row's five display
                ; digits, and the units column it arms is $51 or $66 - the same
                ; two the painter writes the label at.
digital_entry_f_on
                lda     #DIGITAL_ON_POS-1
                ldb     #DIGITAL_LEV_W+1
                rts
digital_entry_f_off
                lda     #DIGITAL_OFF_POS-1
                ldb     #DIGITAL_LEV_W+1
                rts
digital_entry_f_per
                lda     #DIGITAL_PER_POS
                ldb     #DIGITAL_PER_W
                rts
digital_entry_f_ix
                lda     #DIGITAL_IX_POS
                ldb     #DIGITAL_IX_W
                rts
digital_entry_f_end
                lda     #DIGITAL_END_POS
                ldb     #DIGITAL_IX_W
                rts
digital_entry_f_bit
                lda     #DIGITAL_BIT_POS
                ldb     #DIGITAL_IX_W
                rts

; ---------------------------------------------------------------------------
; digital_show_armed - the screen repainted, then the selected field's cursor
; digital_field_arm  - the selected field's cursor alone
;
;   uses:  whatever digital_show uses, then A, B
;
; EVERY ARM ON PAGE 2 REACHES arm_numeric_entry_field ($AC35) BY ONE OF TWO
; TAILS, and each hands it the field's cell as $23AD, which $AC98 puts the
; cursor on. arm_entry_field_for_parameter ($6646), the vector at $3C00 that
; 26 sites JSR through, picks an arm of d66fc and joins arm_field_shared_tail
; ($6708), LBSR at $6722: arm_level_entry_field ($6653) $4A or $5F,
; arm_period_entry_field ($6691) $1E, the index arm $3CCB - $0E on the
; editor, $08 on the player - Seq End $4C, and the base's zero-width field
; $0C. arm_data_digit_entry_field ($5A7C), LBSR at $5AA2, arms the data cell
; at $15 + $3CD4. digital_entry_field already answers every one of those but
; the base, which it sends to the data cell; the base's $0C is taken here.
;
; THE REPAINT FIRST AND THE ARM AFTER IT, because painting moves the display's
; address: this screen reset its entries and then painted, so a cursor would
; have come up where the painter stopped. With no field selected ($3CAC = 0)
; nothing arms, as the stock's $3C00 table has no arm for 0.
; ---------------------------------------------------------------------------
digital_show_armed
                lbsr    digital_show
digital_field_arm
                lda     >digital_field
                beq     digital_field_arm_none  ; $3CAC = 0: nothing to arm
                cmpa    #DIGITAL_FIELD_BASE
                bne     digital_field_arm_cell
                lda     #DIGITAL_BASE_POS       ; the base's $0C
                lbra    ABI_entry_cursor_on
digital_field_arm_cell
                lbsr    digital_entry_field     ; A = $23AD
                lbra    ABI_entry_cursor_on     ; $AC98 and $ACA6
digital_field_arm_none
                rts

digital_key_ignore
                ; A BUS REQUEST NO ARM ANSWERS IS $3A, NOT A KEYSTROKE
                ; REFUSAL. key_dispatch ($6AD0) sends every code its table does
                ; not claim to key_reject_unhandled_code ($6E4F), which stores
                ; $3A - 'Commmand not permitted in this mode' - in $3CDC; the
                ; shared tail l6edf then reports it through $9DD3 while remote
                ; or beeps $C3FE when local, and clears $3CAC because $3A is
                ; one of the three codes it tests for. Twenty-seven of the
                ; sixty arms of d6e67 are that reject, $27 and $32 among them.
                ;
                ; A request byte is RMT_RQ+code = $80+code and the KEY_
                ; constants run 1 to 57, so an unanswered request could never
                ; match a key comparison: it fell through this whole chain to
                ; key_refuse, which reports the keystroke codes 1 or 2 and
                ; deselects nothing. This is page 0's split - chan_key_ignore -
                ; with page 2's code.
                cmpb    #RMT_RQ                 ; a bus request, not a key
                blo     digital_key_ignore_key
                lbsr    digital_leave_edit      ; $6F5A's CLR >$3cac: the
                clr     >digital_field          ; field goes with the refusal
                ldb     #DIGITAL_ERR_WRONG_MODE
                lbra    ABI_error_record        ; l6edf: $9DD3 while remote
digital_key_ignore_key
                lbra    ABI_key_refuse          ; a key this screen cannot
                                                        ; use is REFUSED, not
                                                        ; ignored; see key_refuse

