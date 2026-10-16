; ===========================================================================
; labels.s - the shared waveform and destination NAME TABLE
;
; The codes themselves are in common/labels.inc, which every image includes.
; This file holds the eighteen names and the walk that finds one, and lives
; in A2U12 only: the paged images reach it through the ABI rather than
; carrying a fourth copy of the same strings.
;
; See common/labels.inc for why waveforms and destinations share a single
; numbering, and what that explains about the frequency ceiling.
; ===========================================================================

label_name_none
                fcb     5
                fcc     "     "                 ;  0 nothing chosen
label_name_sine
                fcb     5
                fcc     "Sine "                 ;  1
label_name_ramp
                fcb     5
                fcc     "Ramp "                 ;  2
label_name_triangle
                fcb     5
                fcc     "Trngl"                 ;  3
label_name_dc
                fcb     5
                fcc     "dc   "                 ;  4
label_name_noise
                fcb     5
                fcc     "Noise"                 ;  5
label_name_square
                fcb     5
                fcc     "Sq   "                 ;  6
label_name_am
                fcb     4
                fcc     "AM  "                  ;  7
label_name_fm
                fcb     4
                fcc     "FM  "                  ;  8
label_name_phim
                fcb     4
                fcb     CHAR_PHI                ;  9  the phi glyph, then
                fcc     "M  "                   ;     "M  "
label_name_dsb
                fcb     4
                fcc     "DSB "                  ; 10
label_name_pulse
                fcb     4
                fcc     "Plse"                  ; 11
label_name_out1
                fcb     4
                fcc     "Out1"                  ; 12
label_name_out2
                fcb     4
                fcc     "Out2"                  ; 13
label_name_out3
                fcb     4
                fcc     "Out3"                  ; 14
label_name_out4
                fcb     4
                fcc     "Out4"                  ; 15
label_name_off
                fcb     4
                fcc     "Off "                  ; 16
label_name_on
                fcb     4

; The table's own name as an equ. Each row carries a label so the
; coverage file can cite the waveform or destination it names.
label_table        equ     label_name_none
                fcc     "On  "                  ; 17

; ---------------------------------------------------------------------------
; label_find - the name for a waveform or destination code
;
;   entry: B = the code, 0 to 17
;   exit:  X = the characters, B = how many; carry SET if the code is unknown
;   uses:  A, B, X
;
; Walks the table from the start, stepping over each record by its own length
; byte. Eighteen steps at worst, each four instructions, which is nothing
; against the six milliseconds a range change already costs - and it removes
; the two stride constants a fixed-width table would need.
;
; An out-of-range code returns carry set rather than the blank entry. A field
; holding a code nobody defined is a fault in whatever wrote it, and blanking
; the display would hide it: the operator would see an empty column and no
; reason for it.
; ---------------------------------------------------------------------------
label_find
                cmpb    #LBL_COUNT
                bhs     label_find_unknown
                ldx     #label_table
label_find_step
                tstb
                beq     label_find_here
                lda     ,x+                     ; this record's length
                leax    a,x                     ; step over its characters
                decb
                bra     label_find_step
label_find_here
                ldb     ,x+                     ; B = length, X = characters
                andcc   #~CC_CARRY
                rts
label_find_unknown
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; label_is_modulation - does this destination modulate another channel?
;
;   entry: B = the destination code
;   exit:  carry SET if it is AM, FM, PhiM, DSB or Plse
;   uses:  A
;
; Five codes, contiguous, so this is two comparisons rather than five. The
; span is named in one place above, because it appears in the phase path and
; the frequency ceiling as well and three copies of "7 to 11" is three
; chances to update two of them.
; ---------------------------------------------------------------------------
label_is_modulation
                cmpb    #LBL_MOD_FIRST
                blo     label_is_modulation_no
                cmpb    #LBL_MOD_LAST
                bhi     label_is_modulation_no
                orcc    #CC_CARRY
                rts
label_is_modulation_no
                andcc   #~CC_CARRY
                rts

; ===========================================================================
; The UNIT labels - the stock's table at $EEEE, read out of a2u12.bin.
;
; lcd_write_unit_label ($ABEF) indexes sixteen pointers at $EEEE, each at a
; string with a length byte in front. THIRTEEN OF THE SIXTEEN ARE THREE
; CHARACTERS and the other three are two, and the width matters: the value
; beside them is written at a fixed column, so a label that is not the width
; the screen was laid out for moves nothing and simply leaves a stale
; character behind.
;
; They are held here at a fixed three characters each, which is what every
; entry this firmware's screens can select happens to be - entries 8, 9, 10
; and 12 are the two-character ones and no screen here names them. The three
; that are blank stay blank so an index out of a screen's own range paints
; nothing rather than the wrong unit.
;
; ' Hz' has a LEADING SPACE and 'kHz' does not, which is how the stock's FREQ
; field right-justifies both to the same column: the label is written at
; DDRAM $14 either way and both end at column 22.
unit_table
                fcc     "   "           ;  0
                fcc     "kHz"           ;  1
                fcc     " Hz"           ;  2
                fcc     "deg"           ;  3
                fcc     "rad"           ;  4
                fcc     " V "           ;  5
                fcc     "mV "           ;  6
                fcb     CHAR_MU         ;  7  microvolts
                fcc     "V "
                fcc     "   "           ;  8
                fcc     " s "           ;  9  two in the stock, ' s'
                fcc     "ms "           ; 10  two in the stock, 'ms'
                fcc     "%  "           ; 11
                fcc     "   "           ; 12
                fcc     "   "           ; 13
                fcc     "DSB"           ; 14
                fcc     "   "           ; 15

; HOW MUCH OF A UNITS FIELD THE FIRST TYPED KEY BLANKS, one entry a unit code.
;
; The stock does not carry this per unit: open_entry_field_from_locals ($AC35)
; takes a units CLASS as argument 4 and the eight arms of the switch at $AD3A
; turn it into the width $23AE - classes 0, 1 and 2 give zero ($AD21 CLR
; >$23AE), 3 and 6 give three ($AD09 LDB #$03), 4 and 5 give two ($AD11 LDB
; #$02) and 7 gives one ($AD19 LDB #$01) - and $B524-$B538 writes that many
; blanks from $ED11 at $23AF the first time a key is accepted.
;
; A class is a set of unit keys, so the class of a field and the unit it is
; showing agree: class 6 is Hz and kHz, 3 is deg and rad, 4 and 5 are the three
; voltages and the two times, 7 is per cent, and 2 is ENTER alone with no
; units at all. Indexing by the unit code gives the same width without every
; screen having to carry a class number as well, and each entry below is the
; run that covers its label's non-blank characters: 'kHz' and 'deg' need three,
; ' V ' and 'ms ' two, '%  ' one.
unit_blank_width
                fcb     0               ;  0 nothing chosen, class 2's zero
                fcb     3               ;  1 kHz, class 6
                fcb     3               ;  2 ' Hz', class 6
                fcb     3               ;  3 deg, class 3
                fcb     3               ;  4 rad, class 3
                fcb     2               ;  5 ' V ', classes 4 and 5
                fcb     2               ;  6 'mV '
                fcb     2               ;  7 microvolts
                fcb     0               ;  8 blank
                fcb     2               ;  9 ' s '
                fcb     2               ; 10 'ms '
                fcb     1               ; 11 '%  ', class 7
                fcb     0               ; 12 blank
                fcb     0               ; 13 blank
                fcb     0               ; 14 DSB, which is not a units field
                fcb     0               ; 15 blank

; ---------------------------------------------------------------------------
; unit_blank - how many characters of a unit label a typed key blanks
;
;   entry: B = the unit code, 0 to 15
;   exit:  B = the width, 0 to 3
;   uses:  A, B, X
;
; An index past the table gives entry 0, which blanks nothing - the same clamp
; unit_label makes, and the safe direction: a field that blanks nothing shows a
; stale unit, where one that blanks too much eats a neighbour's column.
; ---------------------------------------------------------------------------
unit_blank
                cmpb    #UNIT_LABEL_COUNT
                blo     unit_blank_ok
                clrb
unit_blank_ok
                ldx     #unit_blank_width
                abx
                ldb     ,x
                rts

; ---------------------------------------------------------------------------
; unit_label - the three characters naming a unit code
;
;   entry: B = the code, 0 to 15
;   exit:  X = the three characters
;   uses:  A, B, X
;
; An index past the table gives entry 0, three spaces, which is what $ABEF
; does with its own `CMPX #$000F / LBLS` guard: it clamps to zero rather than
; reading past the end.
; ---------------------------------------------------------------------------
unit_label
                cmpb    #UNIT_LABEL_COUNT
                blo     unit_label_ok
                clrb
unit_label_ok
                lda     #UNIT_LABEL_LEN
                mul
                ldx     #unit_table
                leax    d,x
                rts
