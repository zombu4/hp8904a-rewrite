; ===========================================================================
; page1_tone.s - tone sequence mode
;
; A tone sequence is a list of frequencies and durations the instrument plays
; in order. It is Option 001, along with the other multi-channel features.
;
; THE SEQUENCE RUNS FROM INTERRUPT CONTEXT. The step timing has to be
; regular, so the timer advances it and the foreground only edits it. That
; splits every piece of state here in two: what the editor is doing, and what
; the player is doing, and they must not be the same bytes.
; ===========================================================================

; A TONE'S RECORD, not a step's. Ported 2026-09-07 from the stock's own two
; tables: a step is a four-bit tone number in the playlist, and everything a
; tone HAS lives here, so every step naming that tone shares it.
;
;   tone_freq   3 bytes a tone, the 24-bit tuning word   - the stock's $3C50
;   tone_times  4 bytes a tone, two 16-bit durations     - the stock's $3C10
TONE_FREQ_SIZE  equ     3               ; a tuning word, 24 bits
TONE_TIME_SIZE  equ     4               ; ON word then OFF word
TONE_ON         equ     0               ; offsets within a tone_times record
TONE_SCREEN_STEPS equ   16              ; HOW MANY PLAYLIST STEPS THE SCREEN
                                        ; CAN REACH, which is not how many the
                                        ; playlist holds. The playlist is
                                        ; TONE_PLAYLIST; NEXT and LAST walk
                                        ; sixteen of it until stage 3 gives
                                        ; this screen the stock's sixteen-cell
                                        ; window, its Seq Index field and its
                                        ; Insert and Delete keys.
TONE_PHASE_GAP  equ     1               ; tone_phase: a gap is running. A FLAG,
                                        ; not a count - the duration beside it
                                        ; is sixteen bits and its high byte is
                                        ; zero for every gap under 655 counts,
                                        ; so storing the count would end the
                                        ; gap immediately.
; THE DURATIONS ARE TIMER COUNTS, NOT MILLISECONDS, and that is the stock's own
; unit rather than a choice made here. load_current_step ($4268) puts the word
; it loads into $3D30, and blk42d1 at $4311-$4318 does LDX >$3D30 / LEAX -1,X /
; STX >ptm_timer2 - it writes the duration STRAIGHT INTO PTM timer 2. So the
; table holds counts of the timer's tick, which is ten microseconds, and the
; two decimal places on the stock's "On Time 500.00ms" are that resolution
; showing through.
;
; This firmware previously stored ONE BYTE OF MILLISECONDS, so it could not
; express its own default screen's 500 ms and stopped at 255. Sixteen bits of
; counts reaches 655.35 ms at 0.01 ms resolution, which is what the instrument
; does. An earlier report of mine said the stock's times ran to 65,535
; MILLISECONDS; they are 65,535 counts.
TONE_GATE_ON    equ     $20             ; DDS register $22 while a tone
TONE_GATE_OFF   equ     $21             ; sounds, and while it does not.
TONE_GATE_ON_DTMF equ   $22             ; AND $22 WHEN THE SEQUENCE IS A DIALLED
                                        ; ONE. dds_set_output_mode_reg22 ($6B92)
                                        ; answers $21 for a zero argument and
                                        ; otherwise $22 when $3C03 is set, $20
                                        ; when it is clear, so the mux code for
                                        ; a running DTMF sequence is $22 where a
                                        ; tone sequence's is $20. Measured in
                                        ; the stock's own stream by the gate
                                        ; named at tone_advance below.
TONE_LAST_GAP_COUNTS equ $00C8          ; THE LAST GAP OF A SINGLE PASS, fixed.
                                        ; load_current_step ($4268) at $4299-
                                        ; $42AB substitutes LDX #$00C8 for the
                                        ; step's own Off word on the off phase
                                        ; of the last step of a single pass, so
                                        ; the pass closes on two milliseconds
                                        ; whatever that step's Off Time says.
                                        ; $4331 in the stock's NMI body loads
                                        ; exactly these two off the phase bit.
; WHAT THE STOCK SENDS TO REGISTER $26 AT EVERY TONE AND GAP EDGE. The NMI
; body's write block at $4351-$4366 puts $2603 into $0200/$0201 (register $26
; <= $03) and then $0B into $0201 alone (register $26 <= $0B) between its two
; writes of register $22. $0B is the standing value of $26 - the stock's
; dds_params_reset ($DF17) seeds its shadow $24BF with $0B, and dds.s's reset
; table sends the same - and $03 is that value with PULSE_PHASE_RESET (bit 3,
; formats.inc) low: $0B AND NOT $08 = $03. So the pair is a low pulse on the
; phase-reset bit, written as the two constants the stock writes rather than
; read back from a shadow, because $4357 and $435D load them as immediates.
TONE_EDGE_PULSE_LOW  equ $03            ; $4357: LDX #$2603 / STX $0200
TONE_EDGE_PULSE_HIGH equ $0B            ; $435D: LDA #$0B / STA $0201
; THE HAND STEP'S VETO. dds_reg26_pulse_if_flag1_clear ($DEB6) does LDD >$23C1
; / ANDA #$00 / ANDB #$02 / CMPD #$0000 at $DEBC and, when the result is not
; zero, LBRA at $DECB straight to its epilogue - so the pulse below it is
; skipped when bit 1 of the low byte of the special-flag word, the byte at
; $23C2, is set. This firmware keeps that byte as special_flags (scratch.inc)
; and dds.s tests the bit, as SPECIAL_NO_PHASE_RESET, inside dds_phase_reset
; - the one routine that makes the pulse, reached from this page through ABI
; slot 72 - so this page tests nothing itself.
TONE_OFF        equ     2               ; AND THE SILENCE AFTER IT, in the
                                        ; same timer counts. Zero means no gap,
                                        ; so a tone written before this existed
                                        ; still runs the way it did.
                                        ;
                                        ; The stock has both: its step table
                                        ; at $3C10 has a stride of FOUR
                                        ; ($4285: ASLB / ASLB / ADDD #$3C10)
                                        ; and its player writes two words,
                                        ; [X] from $3C07 and [X+2] from $3C09.
                                        ; copy_time_to_all_tones ($4AED) names
                                        ; them: word 0 for request code $37,
                                        ; word 1 for $38 - the On Time and Off
                                        ; Time columns entry_field_on_off_time
                                        ; ($45A6) paints.

; HOW LONG A MILLISECOND IS, IN TIMER COUNTS. Established from the stock, and
; got wrong once in the other direction, so the evidence is written out.
;
; Both of the stock's sequence players reload MC6840 timer 2 with the current
; step's duration MINUS ONE - $431C in seq_step_advance ($42B1) on page 1,
; and the two sites in the bit clock at $4196 on page 2 - so a duration of N
; is N counts, which is the data sheet's N+1 form.
;
; What a count is worth was settled by RUNNING the stock's own renderer:
; display_period ($4864) called on a booted instrument prints ".10 ms" for 10,
; "1.00 ms" for 100 and "123.45 ms" for 12345. So one count is ten
; microseconds and a millisecond is a hundred of them.
;
; NOT from the screen template, which reads " Period   1.0  ms " and is static
; label text. Reading that as the rendered value gives 0.1 ms per count and a
; sequence that plays ten times too slow.
TONE_START_COUNTS equ   $00C8           ; start_sequence_timer ($6BD0): the
                                        ; raw start latch, 200 counts, before
                                        ; the first step's own time
TONE_CR2_STOP   equ     $91             ; THE STOP TICK'S OWN CR2 WRITE: both
                                        ; NMI bodies end a single pass with
                                        ; LDA #$91 / STA >$1001, $4377-$4379
                                        ; and $44DB-$44DD in the page-1 image,
                                        ; straight to the port and not through
                                        ; the shadow. It is PTM_SEQ_STOP in
                                        ; timer.s, which this page cannot see
; TONE_MS_COUNTS moved to common/formats.inc on 2026-09-07: the format 2 to
; 3 register conversion scales milliseconds into counts, and it runs from
; A2U12, which cannot see a constant declared on a paged image.

; WHICH CHANNEL PLAYS THE SEQUENCE. Channel 0, which every instrument with
; any output board has. That is a choice this firmware makes, not a fact read
; off the ROM.
TONE_CHANNEL    equ     0

; AND THE SECOND GENERATOR A DIALLED SEQUENCE USES. A DTMF digit is two tones
; summed into one socket: apply_amplitude ($5F70) writes the halved level to
; channel 0 at $5FCD and, on $3C03, sets $23BE = 2 at $5FE1 and writes it to
; channel 2 as well - so the pair is channels 0 and 2 and no others.
; page1_dtmf.s's DTMF_ROW_CHANNEL is this constant; it is declared here
; because page1_tone.s is included first and an equate must be behind its use,
; not in front of it.
TONE_DTMF_PAIR  equ     2

; THE FLOOR A NON-ZERO TIME HAS, from validate_gate_time ($6033): $0050 = 80
; counts = 0.80 ms, and $0064 = 100 counts = 1.00 ms while $3C03 says the DTMF
; screen is the one editing.
; TONE_TIME_MIN, TONE_TIME_MIN_DTMF and TONE_MS_MAX live in the shared
; hp8904a-rewrite/common/formats.inc now: remote.s commits a time from the bus
; and meets the same floor and the same ceiling.


TONE_STOPPED    equ     0
TONE_RUNNING    equ     1
; THE FOUR MENU RECORDS, which is the count byte $03 at $416A plus one.
TONE_PAGE_TITLE  equ    0               ; $4002, the mode's title
TONE_PAGE_TONE   equ    1               ; $4052, the tone and its two times
TONE_PAGE_SEQ    equ    2               ; $40A2, the sequence editor
TONE_PAGE_PLAYER equ    3               ; $40F2, the run controls and the level
TONE_PAGES      equ     4               ; softkey pages: tone, sequence,
                                        ; manual
TONE_MANUAL     equ     2               ; the stock's third run mode. Its
                                        ; seq_enter_manual_mode ($49C0) sets a
                                        ; flag, calls dds_set_output_mode_reg22
                                        ; ($6B92) to hold the output gate open,
                                        ; and repaints; key_manual ($4F5E)
                                        ; stops the timer first if it was
                                        ; running. The operator then advances
                                        ; the sequence a step at a time, which
                                        ; is what an engineer with a scope on
                                        ; the output wants.
TONE_PAUSED     equ     2

; "Commmand not permitted in this mode", the instrument's own spelling, at
; entry $3A of the error table in page3_errors.s (err_t778b, 35 characters).
; freq_key ($4D02) raises it at $4D3F for the FREQ key in DTMF mode and
; reject_key_error_3a ($5071) raises it for every key the mode has no arm for,
; the PHASE key among them. formats.inc has no equate for it, so it is named
; here beside its two users.
TONE_ERR_WRONG_MODE equ $3A

; AND $35, A TONE FREQUENCY PAST 600 kHz FROM THE BUS. validate_store_frequency
; ($612D) stores it into $3C02 when entry_to_scaled_digits returns eight
; digits or more, or the value passes the ceiling at $EA55 (6,000,000 tenths).
TONE_ERR_FREQ_LIMIT equ $35

; AND $37, THE SEQ INDEX RANGE ERROR. clamp_index_to_end ($73E2) records it at
; $7404 with LDB #$37 / STB >$3C02 when a move would put Seq Index past Seq
; End plus one, and report_seq_range_error ($7629) uses the same number for
; the same field. Named here beside its user, as TONE_ERR_WRONG_MODE is.
TONE_ERR_SEQ_INDEX  equ $37

; NOTHING COULD FILL A TONE STEP. The header said "digits go into the entry
; being edited" and there was no digit path at all - no key_digit, no
; entry_digit, no store into a step anywhere in the file - so TONE_FREQ and
; the durations were written by nothing. tone_advance then programmed
; frequency 0 with a duration of 0, and stepped the sequence once per tick
; whatever the durations said.
; The comment above tone_advance records that exact failure being fixed once;
; it had come back by a different route.
;
; f1 stores the typed value as this step's FREQUENCY and f2 as its DURATION.
; Two keys rather than a field cursor, because the two values are different
; widths and different units, and the screen has room to label both.
; THE FOUR MENU RECORDS, BYTE FOR BYTE OUT OF THE ROM. The table at $416B is
; four ten-byte records with the count byte $03 at $416A, and NEXT walks them in
; order - the title, the tone and its two times, the sequence editor, the player
; - as menu_item_next ($8A5B) does against $2242. docs/stock-tone-screens.md is
; the whole reading, with every painter's column.
;
; WHAT WAS HERE WAS INVENTED. One screen served every page: 'Tone Seq  ENTER=run
; f1=Hz f2=on f3=off ' over 'Tone    Freq          On     Off        ', with
; eight raw digits of tuning word, two hex digits of millisecond, and a title
; line naming key bindings the instrument does not have. No Tone Number field,
; no formatted frequency with its unit, no On Time or Off Time labels, no Seq
; Index, no sequence window, no Seq End, no AMPTD row. Driven side by side on
; 2026-09-10, the stock shows four records and this showed one.
tone_r0_l1      fcc     "**         Tone Sequence Mode       "
                fcc     "  **"
tone_r0_l2      fcc     "Pres"
                fcc     "s NEXT/LAST keys.    "
                fcb     $00,$04,$20,$45,$78
                fcc     "it        "
tone_r1_l1      fcb     $00,$01
                fcc     " Tone Number 9    FREQ  "
                fcc     "10005.5  Hz   "
tone_r1_l2      fcb     $00,$02
                fcc     " On Time 500  ms  "
                fcb     $00,$04
                fcc     " Off Time 100  ms "
tone_r2_l1      fcb     $00,$01
                fcc     " Seq I"
                fcc     "ndex  126   [1234567"
                fcc     "89ABCDEF0]  "
tone_r2_l2      fcb     $00,$02
                fcc     " Seq End  127     "
                fcb     $00,$04
                fcc     " Edit Sequence    "
tone_r3_l1      fcb     $00,$01
                fcc     " Seq "
                fcc     " 115  [E]       AMPTD  1.001 V   "
tone_r3_l2      fcb     $00,$02
                fcc     " Continuous     "
                fcb     $20,$20,$00,$03
                fcc     " Single  "
                fcb     $00,$04
                fcc     " Stop  "

; AND THE DTMF MODE'S OWN TWO RECORDS. It shares records 2 and 3 - the sequence
; editor and the player - and has its own title at $4193 and its own record 1 at
; $41E3, which carries ' Manual Dial' on f3 where the tone mode's carries the
; FREQ field and no f3 label at all. A dialled digit's two tones are fixed by
; the signalling standard, so there is no frequency to edit.
tone_d0_l1      fcc     "**         DTMF Sequence Mode       "
                fcc     "  **"
tone_d0_l2      fcc     "Pres"
                fcc     "s NEXT/LAST keys.    "
                fcb     $00,$04,$20,$45,$78
                fcc     "it        "
tone_d1_l1      fcb     $00,$01
                fcc     " Tone Number 9    "
                fcb     $00,$03
                fcc     " Man"
                fcc     "ual Dial      "
tone_d1_l2      fcb     $00,$02
                fcc     " On Time 500 ms   "
                fcb     $00,$04
                fcc     " Off Time 100 ms  "

; AND THE FOUR TWENTY-COLUMN BLOCKS THE PAINTERS SWAP IN. The first twenty
; bytes of d4142 ($4142) are the ' Manual' banner show_run_status_banner
; ($5C1B) writes over record 3's left half, and d4156 ($4156) is the
; Delete/Insert half-line repaint_sequence_page ($70C5) writes over record 2's
; line 2 from column 20. The two running banners are $69A6 and $69BB.
tone_manual     fcb     $00,$01
                fcc     " Manu"
                fcc     "al   "
                fcc     "        "
; The five blanks an AMPTD entry writes over the unit label: the echo covers
; the value columns and the label together, which is what the instrument
; leaves while a level is being typed.
tone_ampl_echo_pad
                fcc     "     "
tone_edit_keys  fcb     $00,$03
                fcc     " Delete  "
                fcb     $00,$04
                fcc     " Insert"
tone_run_single fcc     "** Running Single **"
tone_run_cont   fcc     "** Running Cont **  "
TONE_BANNER_LEN equ     20


; --- the columns, each one a painter's own DDRAM argument ------------------
; docs/stock-tone-screens.md section 3 has every call with its position and
; length. Record 1's two times are the stock's $4B/$51 and $60/$66, chosen by
; show_time_field ($5A7B) on $3D1C; record 3's AMPTD is $1E/$24, set by
; paint_amptd_digits_and_unit ($5896); the sequence window's base is $15, the
; value draw_sequence_window ($6FFC) puts in Y at both its call sites.
TONE_NUM_POS    equ     LCD_LINE1+$0F   ; record 1: one character, the tone
TONE_FREQ_POS   equ     LCD_LINE1+$19   ; eight of the nine format_fixed makes
TONE_FREQ_W     equ     8
TONE_FREQ_UNIT  equ     LCD_LINE1+$23   ; and its three-character label
TONE_FREQ_UNIT_W equ    3               ; $AD09's width for units class 6,
                                        ; which freq_entry_field_geometry
                                        ; ($4574) arms this field with
TONE_ON_POS     equ     LCD_LINE2+$0B   ; $4B, six characters of On Time
TONE_ON_UNIT    equ     LCD_LINE2+$11   ; $51, two of 'ms' or ' s'
TONE_OFF_POS    equ     LCD_LINE2+$20   ; $60, and the Off Time beside it
TONE_OFF_UNIT   equ     LCD_LINE2+$26   ; $66
TONE_TIME_W     equ     6
TONE_UNIT_W     equ     2               ; 'ms' and ' s' are two in the table
TONE_SEQ_IDX_POS equ    LCD_LINE1+$0E   ; record 2: Seq Index, four characters
TONE_SEQ_WIN_POS equ    LCD_LINE1+$15   ; the sixteen cells, inside the [ ]
TONE_SEQ_END_POS equ    LCD_LINE2+$0C   ; $4C, Seq End, four
TONE_EDIT_POS   equ     LCD_LINE2+$14   ; $54, the twenty columns that carry
                                        ; either ' Edit Sequence' or the
                                        ; Delete/Insert pair
TONE_NUM_W      equ     4               ; both number fields are four wide
TONE_NUM_DIGITS equ     3               ; the TONE NUMBER on the bus: $45D3's
                                        ; remote geometry, LDD #$0003 at $45E6,
                                        ; three decimal digits at the same
                                        ; column $0F the keyed character uses
TONE_SEQ_DIGITS equ     5               ; AND SEQ INDEX AND SEQ END ARE FIVE.
                                        ; hpib_query_sequence ($72B2)'s arm
                                        ; for $3D11 = 8 and $0A is $72BE: LDD
                                        ; [>$3D37] / ADDD #$0001 / u16_to_5_
                                        ; ascii_digits ($C912) into $2285 /
                                        ; LDB #$05 / STB 2,S, so the length is
                                        ; five and $C912 pads with zeros.
                                        ; Driven on the stock 2026-09-13:
                                        ; 'SEQE?;' on the tone screen answers
                                        ; '00250' where this answered '250'
TONE_WINDOW     equ     16              ; cells the window shows at once, the
                                        ; CMPX #$0010 at $700F
TONE_CELL_BLANK equ     $10             ; show_sequence_char's codes: $10 is a
TONE_CELL_DOT   equ     $11             ; space and $11 a dot, so unused steps
                                        ; inside the 250-step buffer show as
                                        ; dots and everything past it as blanks
TONE_PLAY_IDX_POS equ   LCD_LINE1+$08   ; record 3: the step, four characters
TONE_PLAY_VAL_POS equ   LCD_LINE1+$0E   ; and the tone it names, one
TONE_AMPL_POS   equ     LCD_LINE1+$1E   ; the level, five characters
TONE_MARKER_POS equ     LCD_LINE1+$1C   ; and the increment marker TWO columns
                                        ; left of the digits, which is what
                                        ; paint_amptd_digits_and_unit ($5896)
                                        ; passes: LDA >$3D25 / LDB #$02 /
                                        ; LBSR $FD8F, then page 3 into
                                        ; show_incr_marker_on_page ($56FA).
                                        ; $3D25 is the AMPTD digits column
                                        ; $1E, so the glyph is at $1C.
                                        ; Measured: the stock's lands at
                                        ; screen column 28 and $1D put this
                                        ; one at 29.
TONE_AMPL_UNIT_POS equ  LCD_LINE1+$24   ; and its three-character label
TONE_AMPL_W     equ     5
TONE_AMPL_ECHO_W equ    10              ; the five value columns, the gap and
                                        ; the three of the unit label: what an
                                        ; entry blanks, from $1E to the end of
                                        ; line 1

; --- the two number forms, as the stock's format calls set them up ---------
; show_freq_field ($571F): eight digits, six leading zeros blankable and the
; point after seven for ' Hz' ($5758-$5770), three and four with the trailing
; zero dropped for 'kHz' ($5776 onward). render_time_value ($59A5): five
; digits, three blankable and the point after three for 'ms' ($59E9 onward),
; the point at nought for ' s'.
TONE_FREQ_DIGITS equ    8
TONE_FREQ_BLANK_HZ equ  6
TONE_FREQ_POINT_HZ equ  7
TONE_FREQ_BLANK_KHZ equ 3
TONE_FREQ_POINT_KHZ equ 4
TONE_TIME_RENDER equ    5
TONE_TIME_BLANK  equ    3
TONE_TIME_POINT_MS equ  3
TONE_UNIT_ON    equ     0               ; tone_time_unit's two cells
TONE_UNIT_OFF   equ     1
TONE_TIME_POINT_S equ   0               ; seconds: every digit after the point,
TONE_TIME_BLANK_S equ   0               ; and nothing blanked - '.00500' is how
                                        ; render_time_value ($59A5) shows 500
                                        ; counts once $3C87 says seconds
TONE_SEC_COUNTS equ     100000          ; ten-microsecond counts in one second,
                                        ; which is why 2 s cannot be a time:
                                        ; 200000 will not fit in the word

; AND THE TIME ENTRY IS SIX DIGITS, which is what entry_field_on_off_time
; ($45A6) arms at $4B or $60 - `ldb #$06 / stb 2,s`. It was three, on the
; reading that a time is one byte; a time is a sixteen-bit count of hundredths
; of a millisecond and the instrument lets all six columns be typed.
TONE_TIME_DIGITS equ    6

; THERE IS NO 'Option 001 required' LINE ANY MORE. It was painted by tone_show
; on every repaint, and the instrument's painters never read the options byte
; at all - see the note over tone_show. The option is refused where the
; instrument refuses it: the mode is not offered on the Main Selection when
; Option 001 was absent at power-on, and nowhere else.

; THE KEYS $19 TO $1D ARE, for the translation at tone_key and dtmf_key. $1D
; is WAVE FORM's code here because both arms are reject_key_error_3a ($5071).
tone_rq_keys    fcb     KEY_FREQ                ; $19
                fcb     KEY_AMPL                ; $1A
                fcb     KEY_WAVEFORM            ; $1B
                fcb     KEY_PHASE               ; $1C
                fcb     KEY_WAVEFORM            ; $1D: the same $3A arm

; ---------------------------------------------------------------------------
; tone_freq_address - the tuning word of one TONE
;
;   entry: B = the tone number
;   exit:  X = its three bytes
;   uses:  A, B, X
;
; MASKED, AND THIS IS THE RULE THAT OUTRANKS THE OTHERS. An unmasked index
; walks out of the table and into battery RAM: the old five-byte walk reached
; $3FFF, the serial number's low byte, from a B of 243. There are now TWO
; indices that can be wrong - the playlist step and the tone number a step
; yields - so both are bounded, here and in tone_step_get.
;
; The TONE number is masked, because sixteen is a power of two. The PLAYLIST
; index is compared, because 250 is not.
; ---------------------------------------------------------------------------
tone_freq_address
                andb    #TONE_TONES-1
                lda     #TONE_FREQ_SIZE
                mul                             ; at most 15*3 = 45
                ldx     #tone_freq
                leax    d,x
                rts

; ---------------------------------------------------------------------------
; tone_times_address - the On and Off durations of one TONE
;
;   entry: B = the tone number
;   exit:  X = its four bytes, ON word then OFF word
;   uses:  A, B, X
; ---------------------------------------------------------------------------
tone_times_address
                andb    #TONE_TONES-1
                lda     #TONE_TIME_SIZE
                mul                             ; at most 15*4 = 60
                ldx     #tone_times
                leax    d,x
                rts

; ---------------------------------------------------------------------------
; tone_step_get - the tone number a playlist step names
;
;   entry: D = the step, 0 to TONE_PLAYLIST-1
;   exit:  B = the tone number, 0 to 15
;   uses:  A, B, X
;
; PORTED FROM l450f ($450F), instruction for instruction. The index is halved
; with LSRA/RORB so the shifted-out bit says which half of the byte this step
; is, and that bit is carried across the address arithmetic in CC because
; forming the address destroys it.
;
; EVEN steps are the HIGH nibble and ODD the LOW. The stock's writer at $452D
; and its reader at $450F agree on that, and getting it backwards gives a
; sequence of the right length playing the wrong tones.
;
; An out-of-range step reads as tone 0 rather than running off the table.
; ---------------------------------------------------------------------------
tone_step_get
                cmpd    #TONE_PLAYLIST
                blo     tone_step_get_ok
                clrb
                rts
tone_step_get_ok
                lsra
                rorb                            ; carry = the step's low bit
                pshs    cc
                addd    #tone_list
                tfr     d,x
                ldb     ,x
                puls    cc
                bcc     tone_step_get_high
                andb    #$0F                    ; odd: the low nibble
                rts
tone_step_get_high
                lsrb
                lsrb
                lsrb
                lsrb                            ; even: the high nibble
                rts

; ---------------------------------------------------------------------------
; tone_step_put - name a tone in one playlist step
;
;   entry: X = the step, 0 to TONE_PLAYLIST-1
;          B = the tone number
;   uses:  A, B, X, CC
;
; PORTED FROM seq_put_nibble ($452D). The other half of the byte is preserved
; by masking it out and adding the shifted value back, which is what the stock
; does at $4545-$4555 and $4556-$4565. Its bound is CMPD #$00FA and so is this.
;
; The tone number is masked as well as the step bounded: a five-bit value would
; spill into the neighbouring step and silently change a tone nobody touched.
; ---------------------------------------------------------------------------
tone_step_put
                cmpx    #TONE_PLAYLIST
                bhs     tone_step_put_done
                andb    #TONE_TONES-1
                pshs    b                       ; the value, four bits
                tfr     x,d
                lsra
                rorb                            ; carry = the step's low bit
                pshs    cc
                addd    #tone_list
                tfr     d,x
                puls    cc
                bcs     tone_step_put_low
                ldb     ,x                      ; even: this step is the HIGH
                andb    #$0F                    ; nibble, so keep the low one
                stb     ,x
                puls    a
                asla
                asla
                asla
                asla
                adda    ,x
                sta     ,x
                rts
tone_step_put_low
                ldb     ,x                      ; odd: keep the high nibble
                andb    #$F0
                stb     ,x
                puls    a
                anda    #$0F
                adda    ,x
                sta     ,x
tone_step_put_done
                rts


; ---------------------------------------------------------------------------
; tone_show_sequence - the sequence editor, the stock's window 2
;
;   uses:  A, B, X, Y, U
;
; Two rows of its own: Seq Index and the sixteen-cell window above, Seq End
; and the Delete and Insert softkeys below. That is the stock's screen $40A2,
; whose softkey label at $4156 reads " Delete  Insert".
; ---------------------------------------------------------------------------
tone_show_sequence
                lda     #LCD_LINE1              ; record 2, $40A2
                ldx     #tone_r2_l1
                ldb     #SVC_LABEL_LEN
                lbsr    ABI_lcd_write
                lda     #LCD_LINE2
                ldx     #tone_r2_l2
                ldb     #SVC_LABEL_LEN
                lbsr    ABI_lcd_write

                ; AND THE TWENTY COLUMNS FROM $54, which carry ' Edit Sequence'
                ; until an edit session opens and the Delete and Insert pair
                ; while one is: repaint_sequence_page ($70C5) writes $4156
                ; while $3D35 is set and $40DE - the record's own bytes -
                ; otherwise.
                tst     >tone_edit
                beq     tone_show_seq_fields
                lda     #TONE_EDIT_POS
                ldx     #tone_edit_keys
                ldb     #TONE_BANNER_LEN
                lbsr    ABI_lcd_write
tone_show_seq_fields

                ; BOTH OF THESE ARE 1-BASED ON THE INSTRUMENT and were shown
                ; 0-based here. Executed on the stock: a freshly booted Tone
                ; Sequence Mode reads "Seq Index 1" and "Seq End 250", and
                ; this firmware read 000 and 249 for the same empty machine.
                ; The STORED values are right and are not touched - tone_cursor
                ; is a 0-based step and tone_end a 0-based LAST INDEX, which is
                ; what tone_window_step, tone_seq_insert and tone_seq_delete
                ; all read and what the stock's own $6DA2 CMPX #$00F9 caps at
                ; 249. Only the two numbers the operator reads move, and they
                ; move here and in tone_commit_seq, which are the only two
                ; places the outside sees them.
                ldx     >tone_cursor            ; Seq Index, the cursor
                leax    1,x                     ; shown 1-based
                lda     #TONE_SEQ_IDX_POS
                lbsr    tone_show_number

                ldx     >tone_end               ; and how many steps play
                leax    1,x                     ; a LAST INDEX shown as a COUNT
                lda     #TONE_SEQ_END_POS
                lbsr    tone_show_number

                lbsr    tone_window_scroll      ; keep the cursor in view
                lbra    tone_window_show

; ---------------------------------------------------------------------------
; tone_show_number - a word as three decimal digits at a column
;
;   entry: A = the LCD column, X = the value
;   uses:  A, B, X, Y, U
;
; The column is pushed here rather than by the caller, for the reason
; tone_show_ms gives.
; ---------------------------------------------------------------------------
tone_show_number
                pshs    a                       ; the column, above the return
                tfr     x,d
                pshs    a,b                     ; high byte at the lower
                clr     ,-s                     ; address, zero above both
                tfr     s,x
                lbsr    ABI_uint24_to_text
                leas    3,s

                ; FOUR OF THE EIGHT, with the leading zeros blanked.
                ; show_seq_position_field ($6E71) renders five digits with
                ; u16_to_5_ascii_digits ($C912), blanks up to FOUR leading
                ; zeros with $CCFF and writes four from $2415 - so an index of
                ; 1 reads '   1' and 250 reads ' 250'. Blanking every leading
                ; zero of the eight but the last gives the same four characters
                ; for every value these two fields can hold, which is 1 to 250.
                ldx     #text_buffer
                ldb     #TEXT_DIGITS-1
tone_show_number_blank
                lda     ,x
                cmpa    #'0'
                bne     tone_show_number_write
                lda     #' '
                sta     ,x+
                decb
                bne     tone_show_number_blank
tone_show_number_write
                puls    a                       ; the column, kept across the
                                                ; blanking loop, which uses A
                ldx     #text_buffer+TEXT_DIGITS-TONE_NUM_W
                ldb     #TONE_NUM_W
                lbra    ABI_lcd_write

; ---------------------------------------------------------------------------
; tone_window_scroll - keep the cursor inside the sixteen cells
;
;   uses:  A, B, X, D
;
; The stock keeps the window origin in $3D39 and moves it with the cursor
; rather than recomputing it; clamp_index_to_end ($73E2) is where it repaints
; after a move. A cursor left of the origin drags it back; one sixteen or more
; past it pushes the origin up so the cursor sits in the last cell.
; ---------------------------------------------------------------------------
tone_window_scroll
                ldd     >tone_cursor
                cmpd    >tone_window
                blo     tone_window_scroll_back
                subd    >tone_window
                cmpd    #TONE_WINDOW
                blo     tone_window_scroll_done
                ldd     >tone_cursor            ; past the right-hand cell
                subd    #TONE_WINDOW-1
                std     >tone_window
                rts
tone_window_scroll_back
                ldd     >tone_cursor            ; left of the origin
                std     >tone_window
tone_window_scroll_done
                rts

; ---------------------------------------------------------------------------
; tone_slot_select - say which of the chip's sixteen tone slots comes out
;
;   entry: B = the tone, 0 to 15
;   exit:  B unchanged, so a caller can go on using it
;   uses:  A, X
;
; Y IS SAVED, AND THE FOUR BYTES ARE THE POINT. dds_write uses Y where
; freq_program - the call this replaced at tone_sound_at_cursor - does not,
; and tone_sound_at_cursor's contract says A, B, X, U. Preserving Y here
; keeps that true, and keeps it true for the DTMF-mode entry in page1_dtmf.s
; that calls it, rather than making a register contract change ripple across
; two files for a routine that runs once at a run start and once per cursor
; move.
;
; PORTED FROM write_reg15_nibble ($E7C4), which is the whole of output_tone's
; ($6A95) tone side. $E7C4 takes two arguments and does three things:
;
;     $E7CA  ANDA #$00 / ANDB #$0F   the tone's low nibble, and nothing else
;     $E7D2  LDX >$0007,s / CMPX #0  the run flag, $3C80 as every caller
;     $E7DE  ORB #$10                passes it - bit 4 when it is set
;     $E7E5  dds_param_store($15)    and out to register $15
;
; SO BIT 4 IS THE ENABLE AND THE NIBBLE IS THE ADDRESS. The sixteen tuning
; words are already in the chip - tone_download_all puts them there, as
; download_all_tone_frequencies ($6A57) does - and this is how one of them is
; chosen. No frequency travels with it.
;
; THE RUN FLAG IS tone_state = TONE_RUNNING, which is this firmware's $3C80.
; The stock's other run cell $3C82 is TONE_MANUAL here, and $3C80 is zero
; while that one is set - softkey_manual_dial ($49B5) reaches seq_output_stop
; ($4881), which clears it - so a hand-stepped tone is selected with bit 4
; clear, exactly as it is on the instrument. tone_sound_at_cursor already
; reads the same cell for the same flag, at the strobe.
; ---------------------------------------------------------------------------
tone_slot_select
                pshs    y,b                     ; the tone, for the caller, and
                                                ; Y because dds_write uses it
                andb    #$0F                    ; $E7CC ANDB #$0F: a slot
                                                ; address is four bits and a
                                                ; corrupt byte must not reach
                                                ; the enable bit
                lda     >tone_state
                cmpa    #TONE_RUNNING           ; $E7D6 CMPX #$0000 / LBEQ
                bne     tone_slot_select_send   ; past the ORB
                orb     #$10                    ; $E7DE: bit 4, the enable
tone_slot_select_send
                clra                            ; the value is eight bits
                tfr     d,x
                ldb     #DDS_HOP_ADDRESS        ; register $15
                lbsr    ABI_dds_write
                puls    y,b
                rts

; ---------------------------------------------------------------------------
; tone_sound_at_cursor - output_tone(tone_at_cursor(), $3C80)
;
;   uses:  A, B, X, Y, U
;
; THE STOCK MAKES THIS PAIR OF CALLS WHEREVER IT SOUNDS A STEP, with nothing
; between them. Among its eleven callers in docs/routine-index.txt:
; seq_output_set_running ($4702) twice in every run start, step_sequence_digit
; ($6931) when the editor's arrows move the cursor, sequence_mode_init at
; $556D/$5584, download_tone_frequency at $5F51/$5F68, exit_sequence_edit at
; $7180/$7197, enter_menu_page at $46CB/$46E2 and gpib_sequence_char_in at
; $7952. This is those two routines, in
; order, instruction for instruction where the stock's frame and argument
; plumbing allow:
;
;   tone_at_cursor ($6D66)
;     $6D6C  LDX >$3D0D / $6D6F CMPX >$3D0F / $6D72 LBHI $6D8C
;                          a cursor past Seq End answers $64, "nothing"
;     $6D7F  sequence_step_get($3D0D)   the step's nibble
;   output_tone ($6A95)
;     $6A9F  CMPX #$0010 / LBCC $6AE0   so $64 skips EVERYTHING below, the
;                                       strobe included
;     $6AA6  LDB >$3C03 / LBNE $6AC5    the dialled branch
;     $6ABD  write_reg15_nibble ($E7C4) with the tone and $3C80: register $15
;            gets the nibble, and bit 4 when the sequencer is running
;     $6AC5  STB >$3D27 / dtmf_program_digit ($441E): the pair
;     $6ADB  dds_update_strobe_if_idle ($4AD1): LDB >$3C80 / LBNE past, else
;            the register $26 pulse through $DEB6, which special function 1
;            can veto
;
; tone_cursor is $3D0D, tone_end is $3D0F - a 0-based last index, which is why
; the compare is BHI, as $6D72's LBHI - tone_state = TONE_RUNNING is $3C80 and
; tone_playing is $3D27.
;
; THREE THINGS THIS DID THAT THE INSTRUMENT DOES NOT, all taken out 2026-09-14:
;
;   - IT WROTE THE REAR HOP LATCH on the tone side, the tone number with $C0.
;     output_tone writes no latch: in docs/routine-index.txt only
;     instrument_preset ($C6EA) and the tone NMI body blk42d1 ($42D1) touch
;     $0B00, and neither $6A95, $E7C4 nor the dds_param_store ($DD9D) it calls
;     is among them. The latch is the player's, stored at $431C.
;   - IT HAD NO SEQ END TEST, so a cursor standing past the end sounded
;     whatever the packed playlist held there and pulsed the phase reset,
;     where the instrument sounds nothing and pulses nothing.
;   - IT WROTE tone_playing ON THE TONE SIDE, and not at all on the dialled
;     side while a run was going. $6AC9 stores $3D27 on the dialled side only,
;     and always. On the tone side the cell is the player's alone: tone_advance
;     stores it before every read.
; ---------------------------------------------------------------------------
tone_sound_at_cursor
                ldd     >tone_cursor            ; $6D6C: LDX >$3D0D
                cmpd    >tone_end               ; $6D6F: CMPX >$3D0F
                bhi     tone_sound_at_cursor_done ; $6D72 LBHI: $64, which
                                                ; output_tone's $6AA2 turns
                                                ; into no write at all
                lbsr    tone_step_get           ; $6D7F: B = the step's nibble
                tst     >tone_dtmf_mode         ; $6AA6: LDB >$3C03
                bne     tone_sound_cursor_pair

                ; THE SLOT, NOT THE FREQUENCY. output_tone's tone side is one
                ; call - write_reg15_nibble ($E7C4) at $6ABD - and $E7C4 sends
                ; the tone's low nibble to register $15 with bit 4 set when the
                ; run flag it was handed is non-zero. It sends no frequency at
                ; all: program_tone_frequency ($69DC) put all sixteen tuning
                ; words in the chip's own slots already, and $15 says which of
                ; them comes out.
                ;
                ; WHAT WAS HERE ONCE. tone_freq_address then ABI_freq_program
                ; with B = TONE_CHANNEL - DDS register $08, channel 0's
                ; frequency - which is what the instrument writes when it LOADS
                ; a slot and not what it writes when it sounds one; see
                ; tone_advance for the measurement that found the same
                ; substitution in the player.
                lbsr    tone_slot_select        ; $6ABD: register $15
                bra     tone_sound_cursor_strobe
tone_sound_cursor_pair
                ; THE PAIR, AND $3D27 WITH IT. $6AC5-$6AD4 is three
                ; instructions and a call: the nibble, STB >$3D27, and
                ; dtmf_program_digit, which reads that cell back. The foreground
                ; entry takes the nibble in B and holds dds_lock around the
                ; loaders; the store is kept because the stock makes it, and the
                ; player's stop path, tone_advance_dtmf_stop, programs the pair
                ; tone_playing names - on the instrument that is whatever the
                ; last output_tone or load_current_step put in $3D27. It writes
                ; neither register $15 nor the hop latch.
                stb     >tone_playing           ; $6AC9: STB >$3D27
                lbsr    dtmf_pair_program_nibble ; $6AD1
tone_sound_cursor_strobe
                lda     >tone_state             ; $4AD1's own condition: LDB
                cmpa    #TONE_RUNNING           ; >$3C80 / CMPB #$00 / LBNE -
                beq     tone_sound_at_cursor_done ; a running sequencer strobes
                lbsr    tone_hand_pulse         ; in its own body
tone_sound_at_cursor_done
                rts

; ---------------------------------------------------------------------------
; tone_download_all - all sixteen tone frequencies into the chip's own slots
;
;   uses:  A, B, X, Y, U
;
; PORTED FROM download_all_tone_frequencies ($6A57) and the
; program_tone_frequency ($69DC) it loops. $6A57 walks i = 0 to $0F ($6A5F
; LDB 2,S / CMPB #$10 / LBCC $6A92), takes &$3C50[i] through
; array_element_address ($FCEA) with the stride-3 descriptor at $6D5A, and
; calls $69DC with that index and that pointer.
;
; ONE SLOT IS FOUR WRITES, in this order and no other, read out of $69DC:
;
;     $24AE read              the standing value of register $15, kept
;     $15 <- i                write_reg15_nibble ($E7C4) with a zero flag
;                             argument, so bit 4 stays clear
;     $08 <- the tuning word  write_channel_reg_08 ($E2C1) called with
;                             CHANNEL 0, which $E2C1 maps to register $08
;     $14 <- $00              dds_write_pair ($DE6F)
;     $15 <- $24AE            dds_write_pair again: the address put back
;
; $15 is HP's ram_add and $14 its ram_wrt - which slot the next write lands
; in, and the strobe that lands it - so the sixteen tones are cached IN THE
; CHIP, and output_tone ($6A95) then sounds one by writing its index to $15
; with bit 4 set rather than by sending a frequency at all. The same four
; steps are what hop_program_send does by hand for a hop slot, and
; DDS_HOP_ADDRESS and DDS_HOP_WRITE are what those two registers are called
; here.
;
; THIS FIRMWARE PLAYS A TONE BY WRITING $08 DIRECTLY - tone_advance and
; tone_sound_at_cursor both go through freq_program - so it does not read a
; tone back out of the slots. They are the instrument's state all the same:
; the stock leaves all sixteen loaded at every entry to the mode, and this
; left channel 0's frequency register holding whatever the record reapply had
; just put there. Measured against the stock through the differential harness
; on 2026-09-13: opening Tone Sequence left the stock's channel 0 at tuning
; word 0 - tone 15's, the last one downloaded, and every tone is zero on a
; cold instrument - where this firmware's read 10000, the record's 1 kHz.
;
; The restore is not decoration. Leaving $15 sitting on slot 15 would move
; where the chip's next hop-RAM write lands.
; ---------------------------------------------------------------------------
tone_download_all
                clrb                            ; the tone
tone_download_next
                lbsr    tone_download_slot      ; which brings B back
                incb
                cmpb    #TONE_TONES
                blo     tone_download_next
                rts

; ---------------------------------------------------------------------------
; tone_download_slot - ONE tone into the chip's own slot
;
;   entry: B = the tone, 0 to 15
;   exit:  B unchanged, so a loop can count with it
;   uses:  A, X, Y, U
;
; program_tone_frequency ($69DC) with the tone as its first argument and that
; tone's own three bytes as its second - the four writes the header above
; sets out, in that order and no other. It is a routine of its own because
; the instrument has TWO callers for it: download_all_tone_frequencies
; ($6A57) loops it over all sixteen at a mode entry, and
; download_tone_frequency ($5F33) runs it for the SELECTED tone alone when a
; frequency is committed or stepped.
;
; THE STANDING SLOT ADDRESS IS READ PER TONE, not once for a loop, because
; the last of the four writes puts it back - so every call sees the same
; value and the word stream is the one the loop sent before this was a
; routine. $69DC reads $24AE itself, once per call, for the same reason.
;
; THE LAST WRITE IS RAW, AND MUST STAY RAW. $69DC's own last write is
; dds_write_pair ($DE6F) - `LDA 7,S / LDB 9,S / STD >dds_prog`, the port and
; nothing else - while its FIRST write, the select, goes through
; write_reg15_nibble ($E7C4) into dds_param_store ($DD9D), which also stores
; the byte into the settings shadow at $24AE (dds_register_descriptor gives
; register $15 offset $24 from $248A). So the stock's own $24AE is left
; holding THIS SLOT'S tone after every call, not the value that was put
; back on the chip.
;
; ABI_dds_write updates dds_shadow for every register it touches, with no
; equivalent to that split - it is the one primitive both write_reg15_nibble
; and dds_write_pair became. Sending the restore through it, as the SELECT
; correctly does, updated dds_shadow BACK to the saved value on every call,
; so the shadow this routine reads on the NEXT call never advanced past the
; value that stood before the whole download started - measured through the
; differential harness: sixteen calls left the chip's register $15 at that
; starting value (parked on the CURSOR'S SELECT, since it is written after
; the download loop) where the instrument's own $24AE bookkeeping, corrupted
; the same way, in fact left the chip ONE SLOT BEHIND the last one sent
; ($0E after slots 0-$0F, not $0F) - the two numbers this comment now gives
; are themselves the fault this ported.
; ---------------------------------------------------------------------------
tone_download_slot
                pshs    b                       ; 0,s the tone
                ldx     >dds_shadow+2*DDS_HOP_ADDRESS
                pshs    x                       ; $69DC's LDB >$24AE: 0-1,s
                                                ; the standing address, 2,s
                                                ; the tone
                ldb     2,s
                clra
                tfr     d,x                     ; X = the slot number, bit 4
                ldb     #DDS_HOP_ADDRESS        ; clear - $E7C4 ORs $10 in
                lbsr    ABI_dds_write           ; only for a non-zero flag
                                                ; argument and $69DC passes
                                                ; zero
                ldb     2,s                     ; the tone again
                lbsr    tone_freq_address       ; X = its three bytes
                leau    ,x                      ; TONE_FREQ is offset zero
                ldb     #TONE_CHANNEL
                lbsr    ABI_freq_program        ; $08 <- the tuning word
                ldx     #$0000
                ldb     #DDS_HOP_WRITE
                lbsr    ABI_dds_write           ; $14 <- $00, the strobe
                lda     #DDS_HOP_ADDRESS        ; and the slot address back,
                ldb     1,s                     ; RAW - dds_write_pair's own
                std     >dds_prog               ; STD, so dds_shadow is left
                                                ; exactly where the select
                                                ; above put it
                puls    x                       ; the standing address
                puls    b                       ; and the tone, for the loop
                rts

; ---------------------------------------------------------------------------
; tone_download_one - the SELECTED tone into its slot, and sound the cursor
;
;   uses:  A, B, X, Y, U
;
; PORTED FROM download_tone_frequency ($5F33), which is two calls and nothing
; else: program_tone_frequency ($69DC)($3D1B, [$23BF]) - the tone the screen
; is on, from the pointer select_tone_and_time_pointers ($561A) left in $23BF
; - and then tone_at_cursor ($6D66) into output_tone ($6A95)(tone, [$3C80]).
; tone_number is $3D1B and tone_sound_at_cursor is that second pair.
;
; ITS TWO CALLERS ARE THE COMMIT AND THE STEP. commit_freq_value ($628E)
; stores the entered value through validate_store_frequency ($612D) and calls
; this at $62A1; step_freq_value ($6683) adds the increment and calls it at
; $670A. Both are the FREQ field and nothing else does it - step_tone_number
; ($6879), for one, only re-aims the pointers and repaints.
;
; WITHOUT IT A COMMITTED FREQUENCY NEVER REACHED THE CHIP. The mode entry
; leaves register $08 holding the LAST slot the download wrote, tone 15's,
; which is zero on a cold instrument; committing 1 kHz into tone 0 then
; changed the slot in RAM and nothing else, so channel 0 stayed at 0 where
; the instrument's carries 10000. Measured against the stock 2026-09-13:
; open Tone Sequence, NEXT, FREQ 1 kHz - the instrument reads 10000 in
; register $08 and this firmware read 0.
; ---------------------------------------------------------------------------
tone_download_one
                ldb     >tone_number            ; $5F39: LDB >$3D1B
                lbsr    tone_download_slot
                lbra    tone_sound_at_cursor    ; $5F51 and $5F68

; ---------------------------------------------------------------------------
; tone_seq_insert - open a gap at the cursor and put a tone in it
;
;   uses:  A, B, X, Y, U
;
; PORTED FROM seq_insert_step ($6D95). Seq End grows by one unless it is
; already at the top; then a cursor walks DOWN from Seq End to the edit cursor
; plus one, copying each step's nibble from the one below it; then the new tone
; goes in at the cursor.
;
; IT SHIFTS ONE NIBBLE AT A TIME, THROUGH THE GENERAL ACCESSORS, and that is
; the stock's method rather than a byte-level shift. It looks wasteful - every
; single step re-derives its byte address and works out which half of the byte
; it is - and it is the right answer anyway: an insert moves each step by ONE
; nibble, so every step crosses the high/low boundary, and a byte-wise shift
; would have to special-case the parity of the cursor, the parity of the end
; and the odd byte at each end. Letting tone_step_get and tone_step_put decide
; the half, exactly as $452D and $450F do, means the boundary is handled in one
; place that is already proved.
;
; NO LOCK, WHICH IS WHAT THE INSTRUMENT DOES. seq_insert_step ($6D95),
; sequence_delete_at_cursor ($6E0C), seq_put_nibble ($452D) and the reader at
; $450F contain no ORCC, no SEI and no lock of any kind: the stock runs this
; same 250-step walk with its player free to fire in the middle of it.
;
; This held dds_lock across the whole walk, and that was worse than the
; instrument rather than safer. The walk is about 205 cycles a step and up to
; 248 steps - roughly 50,800 cycles, about 25 ms at the MC68B09P's rated 2 MHz
; - and tone_advance completes the timer-2 clear BEFORE it tests the lock, so
; every tick inside that window is LOST, not deferred. A sequence at its 1 ms
; floor lost about twenty-five steps to one keypress.
;
; Without the lock the player reads a half-shifted playlist and sounds ONE
; wrong tone, which is exactly what the instrument does. That is the trade the
; stock makes and this now makes it too.
;
; NOTHING HERE CAN BE READ TORN IN A WAY THE STOCK'S CANNOT. The shift touches
; two things: the packed playlist and Seq End. A playlist read is a single
; byte, so it is atomic on both. Seq End is a WORD on both - the stock's $3D0F
; is updated by an unlocked ldd/addd/std at $6DA5-$6DAB and read by its player
; with cmpd at $402 - so the torn-word exposure is identical, not new. And a
; torn value here cannot make a bad pointer: tone_step_get bounds the step
; against TONE_PLAYLIST and tone_freq_address masks the tone to four bits, so
; the worst a torn read produces is the wrong tone for one step.
; ---------------------------------------------------------------------------
tone_seq_insert
                pshs    b                       ; THE TONE THAT LANDS IN THE
                                                ; GAP, which is the digit the
                                                ; operator typed - the shift
                                                ; walk below uses B, so it is
                                                ; kept here
                ldd     >tone_cursor            ; nothing to do past the end
                cmpd    >tone_end
                bhi     tone_seq_insert_out

                ldd     >tone_end               ; Seq End grows unless it is
                cmpd    #TONE_PLAYLIST-1        ; already at the last step -
                bhs     tone_seq_insert_walk    ; $6DA2 CMPX #$00F9
                addd    #1
                std     >tone_end
                ; THE WALK COUNTER GOES ON THE STACK, not in tone_win_step.
                ; That cell is the WINDOW's step pointer, which the painter
                ; walks at the same time: using it here left the window's own
                ; state wherever the shift happened to stop, and the sixteen
                ; cells read as a run of blanks through the middle of the
                ; sequence. Driven on both firmwares, f4 f4 5 on a fresh
                ; playlist: the stock gives '[5 0123456789ABCD]' and this gave
                ; '[5012        BCDE]'.
tone_seq_insert_walk
                ldd     >tone_end               ; walk DOWN to cursor+1
                pshs    a,b                     ; 0,s the counter, 2,s the digit
tone_seq_insert_next
                ldd     ,s
                cmpd    >tone_cursor
                bls     tone_seq_insert_put
                subd    #1                      ; the step below this one
                lbsr    tone_step_get           ; B = what it names
                ldx     ,s
                lbsr    tone_step_put
                ldd     ,s
                subd    #1
                std     ,s
                bra     tone_seq_insert_next
tone_seq_insert_put
                leas    2,s                     ; the counter, done with
                ldb     ,s                      ; the digit that was typed
                ldx     >tone_cursor
                lbsr    tone_step_put
tone_seq_insert_out
                puls    b                       ; the digit, and out
                rts

; ---------------------------------------------------------------------------
; tone_seq_delete - close the gap at the cursor
;
;   uses:  A, B, X, Y, U
;
; PORTED FROM sequence_delete_at_cursor ($6E0C). A cursor walks UP from the
; edit cursor to Seq End, copying each step's nibble from the one above it,
; and then Seq End shrinks by one unless it is already zero. The same
; nibble-at-a-time method, for the same reason - and, like the stock, with no
; lock held across it. See tone_seq_insert for why that is the instrument's
; behaviour rather than a weakening of it.
; ---------------------------------------------------------------------------
tone_seq_delete
                ldd     >tone_cursor
                cmpd    >tone_end
                bhi     tone_seq_delete_done    ; $6E14: above the end, nothing

                ldd     >tone_cursor
                std     >tone_win_step
tone_seq_delete_next
                ldd     >tone_win_step
                cmpd    >tone_end
                bhs     tone_seq_delete_end     ; $6E27: stop AT the end
                addd    #1                      ; the step above this one
                lbsr    tone_step_get
                ldx     >tone_win_step
                lbsr    tone_step_put
                ldd     >tone_win_step
                addd    #1
                std     >tone_win_step
                bra     tone_seq_delete_next
tone_seq_delete_end
                ldd     >tone_end               ; and the sequence is one
                beq     tone_seq_delete_out     ; shorter, unless it was empty
                subd    #1
                std     >tone_end
tone_seq_delete_out
tone_seq_delete_done
                rts

; ---------------------------------------------------------------------------
; tone_window_show - the sixteen-cell window over the 250-step playlist
;
;   uses:  A, B, X, Y, U
;
; PORTED FROM draw_sequence_window ($6FFC). Sixteen cells from the window
; origin, each one of:
;
;   the step's tone number, when the step is at or below Seq End;
;   a DOT, when it is past Seq End but still inside the 250-step buffer;
;   a BLANK, when it is past the buffer altogether.
;
; That is the stock's own split - $7055 CMPX >$3D0F picks the first, and
; $7072 CMPX #$00FA the other two - and it is what makes the end of a sequence
; visible: dots to the right of the last step, blanks past 250.
;
; THE INSERT GAP. When tone_insert is set and the walk reaches the cursor, one
; extra BLANK cell is emitted before the step at that position, and the cell
; counter advances while the step number does not - so the window shifts right
; by one from the cursor on and the operator sees where the new step will go.
; The stock does exactly this at $7018-$704E with its flag $3D3E.
;
; The stock keeps two counters, the cell and the column, increments them on
; the same paths and tests both. They are always equal. This keeps one.
; ---------------------------------------------------------------------------
tone_window_show
                ldd     >tone_window
                std     >tone_win_step          ; the step being shown
                clr     >tone_win_cell          ; and which cell it lands in
tone_window_cell
                lda     >tone_win_cell
                cmpa    #TONE_WINDOW
                bhs     tone_window_done

                tst     >tone_insert            ; the gap, before the step it
                beq     tone_window_step        ; will push along
                ldd     >tone_win_step
                cmpd    >tone_cursor
                bne     tone_window_step
                lda     #TONE_CELL_BLANK
                lbsr    tone_window_put         ; a cell, but not a step
                lda     >tone_win_cell
                cmpa    #TONE_WINDOW
                bhs     tone_window_done

tone_window_step
                ldd     >tone_win_step
                cmpd    >tone_end
                bhi     tone_window_empty       ; past the end of the sequence
                lbsr    tone_step_get           ; B = the tone this step names
                tfr     b,a
                bra     tone_window_emit
tone_window_empty
                ldd     >tone_win_step
                cmpd    #TONE_PLAYLIST
                bhs     tone_window_blank
                lda     #TONE_CELL_DOT          ; inside the buffer, unused
                bra     tone_window_emit
tone_window_blank
                lda     #TONE_CELL_BLANK        ; past the buffer entirely
tone_window_emit
                lbsr    tone_window_put
                ldd     >tone_win_step          ; on to the next STEP, which
                addd    #1                      ; the gap deliberately skipped
                std     >tone_win_step
                bra     tone_window_cell
tone_window_done
                rts

; ---------------------------------------------------------------------------
; tone_hex_char - a tone number as the character the instrument shows for it
;
;   entry: A = 0 to 15
;   exit:  A = the character
;   uses:  A
;
; * AND # IN A DTMF SEQUENCE. The instrument does this substitution in
; dtmf_map_ef_to_star_hash ($5AF6), which hpib_query_sequence ($72B2) uses to
; render nibbles $0E and $0F and repaint_tone_dependent_fields ($5B60) uses
; for the tone number's own cell: the sixteen dialled digits are 123A 456B
; 789C *0#D, so the last two have no hex character that means anything to an
; operator. Only the two are special; $0A to $0D are already A to D and read
; correctly as they are.
;
; ONE ROUTINE FOR BOTH CELLS. The window and the Tone Number field show the
; same sixteen values, and the stock renders them the same way; they were two
; pieces of code here, and only the window's had the substitution.
; ---------------------------------------------------------------------------
tone_hex_char
                tst     >tone_dtmf_mode
                beq     tone_hex_char_plain
                cmpa    #$0E
                bne     tone_hex_char_hash
                lda     #$2A                    ; the asterisk. Written as its
                rts                             ; code rather than a character
tone_hex_char_hash                              ; literal: the star is the
                cmpa    #$0F                    ; assembler's own symbol for the
                bne     tone_hex_char_plain     ; program counter, so '*' does
                lda     #$23                    ; not parse - and the hash is
                rts                             ; written the same way beside it
tone_hex_char_plain
                cmpa    #$0A                    ; a tone number, as one hex
                blo     tone_hex_char_digit     ; digit - sixteen of them do
                adda    #'A'-$0A                ; not fit in decimal
                rts
tone_hex_char_digit
                adda    #'0'
                rts

; ---------------------------------------------------------------------------
; tone_window_put - one cell of the window
;
;   entry: A = the code: 0-15 a tone number, TONE_CELL_DOT, TONE_CELL_BLANK
;   uses:  A, B, X, Y, U
;
; show_sequence_char ($6F37) renders the same three cases; this is that
; routine's mapping, kept where the window can see it.
; ---------------------------------------------------------------------------
tone_window_put
                cmpa    #TONE_CELL_BLANK
                bne     tone_window_put_dot
                lda     #' '
                bra     tone_window_put_char
tone_window_put_dot
                cmpa    #TONE_CELL_DOT
                bne     tone_window_put_hex
                lda     #'.'
                bra     tone_window_put_char
tone_window_put_hex
                lbsr    tone_hex_char           ; the same sixteen characters
                                                ; the Tone Number field shows
tone_window_put_char
                sta     >text_buffer
                ldb     >tone_win_cell
                addb    #TONE_SEQ_WIN_POS
                tfr     b,a
                ldx     #text_buffer
                ldb     #1
                lbsr    ABI_lcd_write
                inc     >tone_win_cell
                rts

; ---------------------------------------------------------------------------
; tone_stream_put - one character of a WSQ stream, into the playlist
;
;   entry: B = the tone number, 0 to 15
;   uses:  A, B, X, Y, U
;
; PORTED FROM gpib_sequence_char_in ($7870), the per-character handler
; start_streamed_digit_entry ($79C3) installs. Its shape is: convert, write,
; echo, advance.
;
;   convert  $78CF-$78E2 builds "0<char>" at $2414/$2415 and runs
;            parse_hex_digit_pair ($CC53) over it. remote.s does that half -
;            it has already refused everything but a hex digit and folded '*'
;            and '#' onto E and F - so the value arrives here.
;   write    $78E5-$7905 calls seq_put_nibble ($452D) with the value and the
;            STREAM cursor $3D3F. The operator's cursor $3D0D is not touched.
;   echo     $7906-$794F, tone_stream_echo below.
;   advance  $799F-$79B7: $3D3F = $3D3F + 1, and if that is above $00F9 it is
;            put back to $00F9 - so a stream longer than the playlist keeps
;            overwriting the last step rather than running off the table.
; ---------------------------------------------------------------------------
tone_stream_put
                ldx     >tone_stream_at         ; $7900: the step it lands in
                lbsr    tone_step_put           ; $7905 seq_put_nibble
                lbsr    tone_stream_echo        ; the one cell, if it shows
                ldd     >tone_stream_at         ; $799F: on to the next step
                addd    #1
                cmpd    #TONE_PLAYLIST-1        ; $79AB: the ceiling is $00F9,
                bls     tone_stream_next        ; the last step of the 250
                ldd     #TONE_PLAYLIST-1
tone_stream_next
                std     >tone_stream_at
                rts

; ---------------------------------------------------------------------------
; tone_stream_echo - draw the cell a streamed character just filled
;
;   uses:  A, B, X, Y, U
;
; PORTED FROM the echo block of gpib_sequence_char_in ($7906-$794F). Three
; tests, all of which have to pass before anything is drawn:
;
;   $7906  the sequence editor is the record showing ($3C8F = 2);
;   $790E  the step is at or after the window origin $3D39;
;   $7916  it is at or below Seq End $3D0F - past the end the cell shows a
;          dot whatever the step holds, so there is nothing to redraw;
;   $791E  and the window's sixteenth cell has not been passed ($3D39 + $0F
;          is compared against the step).
;
; Then $7922-$794C works out the column as step - origin and calls
; show_sequence_char ($6F37) with it. There is no insert gap to allow for:
; the arm that opened the stream cleared tone_insert.
;
; The stock has a second echo, at $7952: with the MANUAL record showing
; ($3C8F = 3) and the manual flag $3C82 set, a character written AT the cursor
; is echoed into that record's single tone cell and the tone is re-routed
; through tone_at_cursor ($6D66)/output_tone ($6A95). That is the dial screen's
; echo and page1_dtmf.s owns the dial screen here, so it is not this routine's.
; ---------------------------------------------------------------------------
tone_stream_echo
                lda     >tone_page              ; $7906: only the editor's own
                cmpa    #TONE_PAGE_SEQ          ; record draws it
                bne     tone_stream_echo_out
                ldd     >tone_stream_at
                cmpd    >tone_window            ; $790E: before the window
                blo     tone_stream_echo_out
                cmpd    >tone_end               ; $7916: past Seq End
                bhi     tone_stream_echo_out
                subd    >tone_window            ; $7922: the cell it lands in
                cmpd    #TONE_WINDOW            ; $791E: past the sixteenth
                bhs     tone_stream_echo_out
                stb     >tone_win_cell          ; 0 to 15, so the low byte is
                                                ; the whole of it
                ldd     >tone_stream_at
                lbsr    tone_step_get           ; B = what the step now names
                tfr     b,a
                lbra    tone_window_put         ; the same painter the whole
                                                ; window uses, one cell of it
tone_stream_echo_out
                rts

; ---------------------------------------------------------------------------
; tone_show_ms - a duration in the screen's three decimal digits
;
;   entry: A = the LCD column, X = the timer counts
;   uses:  A, B, X, Y, U
;
; THE COLUMN IS PUSHED INSIDE, not by the caller. It was the caller's push at
; first, and that put it UNDER the return address lbsr had just stacked - so
; the puls below took the return address's high byte for a column and left the
; routine returning into nothing. Every key on the screen stopped working,
; because tone_show never came back.
;
; uint24_to_text renders eight digits with the leading zeros kept, so the last
; three are the value: a duration is at most 655 and cannot reach a fourth.
; ---------------------------------------------------------------------------
; tone_start - start the player: softkey_continuous_run and seq_run_single
;
; THE CALLER SETS tone_single FIRST, as the stock's two starts set $3C81 before
; anything else: softkey_continuous_run ($4A19) clears it at $4A27 and
; seq_run_single ($4A5F) sets it at $4A6A. Everything after that is shared,
; and is this, in the stock's order:
;
;   $4A2A  a RUNNING sequence's timer stopped: seq_timer_stop ($6C22)
;   $4702  seq_output_set_running(0)
;            $4796  report 3 to the bus, only if $3C80 is still set ($4771)
;            $479B  CLR >$3C80
;            $47A3  show_run_status_banner ($5C1B)
;            $47AD  seq_timer_stop ($6C22)
;            $47CE  output_tone(tone_at_cursor, 0) - the step at the cursor,
;                   with the phase-reset strobe, the run flag being clear
;   $4702  seq_output_set_running(1)
;            $4715  STB >$3C80 with 1
;            $4734  output_tone(tone_at_cursor, 1) - no strobe now
;            $473E  show_run_status_banner
;            $475F  report 2 to the bus
;            $4769  start_sequence_timer ($6BD0)
;
; WHAT THIS DID BEFORE 2026-09-14, and each is a difference on the chip:
;   - it started the timer and left the banner to tone_show afterwards, so the
;     first interrupt came two banners' worth of display writes earlier than
;     the instrument's. Measured on RUNC in DTMF Sequence: the stock's first
;     tick 5313 instructions after the command arrived and this firmware's
;     1880, with the stock's 42 LCD writes all ahead of its timer start.
;   - the dialled pair it programmed was STEP 0's, not the step at the cursor,
;     and a cursor past Seq End - where tone_at_cursor answers $64 and
;     output_tone writes nothing - still got a pair and a strobe.
;   - on the tone side it made only the running selection: no register $29
;     clear, no register $15 with the enable off and no strobe ahead of it.
;   - it did not stop a sequence that was already running, because RUNC and
;     RUNS only called it from TONE_STOPPED; see tone_key.
;
; THE CONTRACT, last, where hp8904a-rewrite/tests/test_carry_read.py reads it:
;
;   exit:  nothing to test. softkey_continuous_run ($4A19) and
;          seq_run_single ($4A5F) never read the options byte, so a run key
;          cannot be refused for want of one
;   uses:  A, B, X, Y, U
; ---------------------------------------------------------------------------
tone_start
                ; AND THE FIELD ID WITH IT, which this had dropped. The two
                ; stock arms named below open with CLRB / CLRA / STD >$3D11,
                ; and $3D11 is the FIELD ID, not the increment flag: the port
                ; read that store as the increment and cleared only the flag.
                ; So a run started with the data cursor selected left it
                ; selected here and let go on the instrument. Driven, seed 15
                ; step 7, 'RUNC 999 DG;': $3D11 goes 9 -> 0 on the stock while
                ; tone_field stayed 7 here, and the UP four steps later then
                ; moved this firmware's cursor where the instrument recorded 4.
                ; ONE CELL THERE, TWO HERE: the dialled record keeps its own
                ; dtmf_field, so the pair is what stands for $3D11 - the same
                ; pair every arm in page1_dtmf.s clears together.
                clr     >tone_manual_sel        ; $3D11 zeroed: not Manual's
                clr     >tone_field
                clr     >dtmf_field
                clr     >tone_incr_mode         ; EVERY RUN KEY CLEARS THE
                                                ; ARMED INCREMENT before it
                                                ; starts: softkey_continuous_run
                                                ; ($4A19) and softkey_single_
                                                ; sequence ($4AA2) both open
                                                ; with CLRB / CLRA / STD >$3D11

                ; A RUNNING SEQUENCE'S TIMER IS STOPPED BEFORE ANYTHING ELSE.
                ; $4A2A and $4A6D both test $3C80 and call seq_timer_stop; then
                ; seq_output_set_running(0) is the whole stopped half, and it
                ; tests $3C80 again for its bus report before clearing it.
                lda     >tone_state
                cmpa    #TONE_RUNNING
                bne     tone_start_idle
                lbsr    tone_timer_stop         ; $4A38: seq_timer_stop
tone_start_idle
                lbsr    tone_set_stopped        ; $4A47: set_running(0)

                ; AND THE RUNNING HALF. The flag goes up BEFORE output_tone,
                ; because the flag is its argument: register $15 takes bit 4
                ; and the strobe is skipped. The tick is not installed yet, so
                ; nothing reads the flag early.
                lda     #TONE_RUNNING           ; $4715: STB >$3C80
                sta     >tone_state
                lbsr    tone_sound_at_cursor    ; $4734: output_tone(cursor, 1)
                lbsr    tone_show_banner        ; $473E: the running banner

                ; THE BUS IS TOLD THE OUTPUT HAS STARTED, before the timer:
                ; $475F is seq_output_set_running's LBSR $9DD3 with index 2 and
                ; code $00FF, between show_run_status_banner ($5C1B) and
                ; start_sequence_timer ($6BD0). ABI_remote_srq_event makes the
                ; whole report - the remote gate, the status bit, the SRQ if the
                ; controller has enabled bit 2, and the release again.
                lda     #RMT_SRQ_SEQ_START
                lbsr    ABI_remote_srq_event

                ; START_SEQUENCE_TIMER ($6BD0): THE PLAYER'S STATE, THEN THE
                ; TIMER. dds_lock is raised across the state because it IS a
                ; flag the tick reads - tone_advance defers a step while it is
                ; up - though no tick is installed at this point.
                inc     >dds_lock
                ldd     #$0000                  ; SO THE FIRST INTERRUPT PLAYS
                std     >tone_position          ; STEP 0 rather than wherever
                                                ; the last sequence stopped.
                                                ; tone_position is a WORD, every
                                                ; other access is ldd/std, and
                                                ; the player indexes with B, the
                                                ; LOW byte; a clr here once wrote
                                                ; only the high one, and a
                                                ; sequence stopped on step 5
                                                ; began again at step 5.
                clr     >tone_pass_done         ; no pass has ended yet
                clr     >tone_phase             ; AND NOT IN A GAP. Nothing else
                                                ; clears it on a stop, so a tone
                                                ; sequence stopped during a gap
                                                ; used to start its next run in
                                                ; that gap, where $6BD0 always
                                                ; loads $3D32 fresh

                ; A DTMF RUN STARTS ONE HALF-STEP EARLIER, because the stock's
                ; does. start_sequence_timer ($6BD0) writes $3D2C = $FFFF and
                ; $3D32 = $02 - an EVEN phase - so the first interrupt is the
                ; gap-type tick: seq_step_advance ($42B1) carries the position
                ; on to 0 and load_current_step ($4268) loads step 0's ON word.
                ; The gate is therefore closed across the two hundred counts
                ; between the start and that first interrupt, and the first
                ; digit is heard for its own On Time and not a count more.
                ;
                ; A tone sequence keeps this file's own start - position 0,
                ; phase 0, so the first interrupt is a tone-on tick. $6BD0 has
                ; no $3C03 test, so that start is half a tick later than the
                ; instrument's; it is recorded, not altered, here.
                ; AND THE TONE TICK'S OWN CELLS, as start_sequence_timer ($6BD0)
                ; sets them for both players: $3D32 = 2, $3D2C = $FFFF, $3D34
                ; = $FF, $3D30 = $00C8. The first time-out then closes the
                ; gate and loads step 0, as blk42d1 does.
                ldd     #$FFFF
                std     >tone_position
                lda     #$02
                sta     >tone_phase_count
                lda     #$FF
                sta     >tone_once
                ldd     #TONE_START_COUNTS
                std     >tone_period
                tst     >tone_dtmf_mode
                beq     tone_start_gate
                lda     #TONE_PHASE_GAP
                sta     >tone_phase
tone_start_gate
                clr     >tone_gate              ; AND FORGET THE LAST GATE
                                                ; VALUE, so the first tone of
                                                ; this run is an edge and gets
                                                ; the full register stream.
                                                ; $6BD0 does CLR >$3D33 for the
                                                ; same reason: its NMI compares
                                                ; the new gate value with $3D33
                                                ; and writes nothing when they
                                                ; agree
                dec     >dds_lock

                ; THE START LATCH IS RAW AND FIXED: start_sequence_timer does
                ; LDD #$00C8 / STD >ptm_timer2 for every run, tone and DTMF
                ; alike, and the first NMI then loads step 0's own time.
                ; tick_install subtracts one (timer.s seq_timer_start), so one
                ; is added here to land $00C8 on the chip.
                ;
                ; THE OUTPUT RELAY IS NOT TOUCHED, because the instrument does
                ; not touch it: driven on the stock through Tone Sequence Mode -
                ; opened, paged to the run screen, run continuous, stopped -
                ; channel 0's latch reads $01 throughout and bit 2 never sets.
                ; The stock silences a sequence with register $22 alone.
                ldd     #TONE_START_COUNTS+1
                ldx     #tone_advance
                lbsr    ABI_tick_install
                rts

; ---------------------------------------------------------------------------
; tone_timer_stop - seq_timer_stop
;
;   uses:  A, B, X, Y
;
; seq_timer_stop ($6C22) is two things: $2422 and CR2 <- $91 at $6C28-$6C30,
; which stops timer 2 asking, and dds_write_reg29 ($6B4C) with zero at $6C3D.
; ABI_tick_remove is the first - seq_timer_stop in timer.s, with the callback
; disarmed before the pointer goes - and dtmf_sync_clear in page1_dtmf.s is
; the second. It has no $3C03 test, so a tone sequence clears register $29 as
; a dialled one does.
; ---------------------------------------------------------------------------
tone_timer_stop
                lbsr    ABI_tick_remove         ; CR2 <- $91
                lbra    dtmf_sync_clear         ; register $29 <- $00

; ---------------------------------------------------------------------------
; tone_set_stopped - seq_output_set_running(0)
;
;   uses:  A, B, X, Y, U
;
; The zero leg of $4702, in its order:
;
;   $4771  LDB >$3C80 / LBEQ: only a run that was going is reported
;   $4796  report_error_and_pulse_status_bit ($9DD3) with 3 and $00FF
;   $479B  CLR >$3C80
;   $47A3  show_run_status_banner ($5C1B)
;   $47AD  seq_timer_stop ($6C22)
;   $47CE  output_tone(tone_at_cursor, 0) - the pair or register $15 for the
;          step at the Seq Index, and the strobe, the flag being clear now
;
; ABI_remote_srq_event makes the whole of $9DD3's report, the event_flags
; gate included. TONE_MANUAL is $3C82 with $3C80 clear, so a hand-stepped
; sequence is not reported and ends STOPPED like any other.
;
; CALLED FROM THE TICK TOO, through tone_stop_from_isr, as the stock calls it
; from its NMI bodies. The banner is painted there as the stock paints it,
; with the display's address counter saved and put back around it.
; ---------------------------------------------------------------------------
tone_set_stopped
                lda     >tone_state             ; $4771: LDB >$3C80
                cmpa    #TONE_RUNNING
                bne     tone_set_stopped_quiet
                lda     #RMT_SRQ_SEQ_END        ; $4796: report 3
                lbsr    ABI_remote_srq_event
tone_set_stopped_quiet
                lda     #TONE_STOPPED           ; $479B: CLR >$3C80
                sta     >tone_state
                lbsr    tone_show_banner        ; $47A3
                lbsr    tone_timer_stop         ; $47AD
                lbra    tone_sound_at_cursor    ; $47CE: output_tone(cursor, 0)

; ---------------------------------------------------------------------------
; tone_output_stop - seq_output_stop
;
;   uses:  A, B, X, Y, U
;
; $4881, which softkey_stop ($4AB9), stop_key by way of it, halt_and_report_field
; ($4EA8) and sequence_stop_from_isr ($6C45) all reach:
;
;   $4887  CLR >$3C82                   manual off
;   $488A  LDB >$3C80 / LBEQ $48A5      not running: the banner alone ($48AA)
;   $489D  seq_output_set_running(0)    running: the whole stopped half
;   $48B9  dds_set_output_mode_reg22(0) either way, register $22 <- $21
;
; tone_stop did three things here the instrument does not: it reported a
; hand-stepped sequence as ending, it removed the tick when nothing was
; running, and it cleared the rear hop latch, which in the stock only
; instrument_preset ($C6EA) and the tone NMI body ($42D1) write. And it left
; out the banner, register $29 and output_tone.
; ---------------------------------------------------------------------------
tone_output_stop
                lda     >tone_state             ; $488A: LDB >$3C80
                cmpa    #TONE_RUNNING
                beq     tone_output_stop_running
                lda     #TONE_STOPPED           ; $4887: CLR >$3C82 - $3C80 is
                sta     >tone_state             ; clear already
                lbsr    tone_show_banner        ; $48AA
                bra     tone_output_stop_gate
tone_output_stop_running
                lbsr    tone_set_stopped        ; $489D
tone_output_stop_gate
                ldb     #TONE_GATE_OFF          ; $48B9: reg22(0) is $21
                lbra    tone_gate_write

; ---------------------------------------------------------------------------
; tone_stop_isr - the end of a single pass, from inside the tick
;
;   uses:  A, B, X, Y, U
;
; The first four instructions of both NMI bodies' stop paths, $436D and
; $44D1, which are the same bytes:
;
;   LDA #$22 / LDB #$21 / STB >$3D33 / STD >$0200     register $22 <- $21
;   LDA #$91 / STA >$1001                             CR2 <- $91, straight
;   JSR sequence_stop_from_isr ($6C45)
;
; tone_advance_dtmf_stop goes on to $44EE's pair and $44F1's latch. The tone
; body's $437F branches to $43B3, which sets bit 7 of its phase byte $3D32 -
; LDA >$3D32 / ORA #$80 / STA >$3D32 - and returns from the interrupt. This
; player's tone side keeps no two-interrupt phase byte (see tone_advance), so
; that store has no cell to land in here; it is recorded, not ported.
; ---------------------------------------------------------------------------
tone_stop_isr
                lda     #DDS_PORT_MUX_01        ; LDA #$22
                ldb     #TONE_GATE_OFF          ; LDB #$21
                stb     >tone_gate              ; STB >$3D33
                std     >dds_prog               ; STD >$0200
                lda     #TONE_CR2_STOP          ; LDA #$91
                sta     >ptm_status             ; STA >$1001
                lbra    tone_stop_from_isr      ; JSR $6C45

; ---------------------------------------------------------------------------
; tone_stop_from_isr - sequence_stop_from_isr
;
;   uses:  A, B, X, Y, U
;
; $6C45, called only from the two NMI bodies:
;
;   $6C50  lcd_read_address_counter ($D781): the busy flag waited out and the
;          counter kept, because the interrupt may have landed in the middle
;          of a foreground write to the glass
;   $6C5C  seq_output_stop ($4881)
;   $6C6F  blank_dial_echo ($5BF5), only with $3C04 set - the Manual Dial's
;          flag, which this player never sets: the dial is page1_dtmf.s's own
;          tick, and dtmf_tick_stop blanks its echo itself
;   $6C7F  lcd_set_cursor ($D7A0) with the counter kept
;   $6C89  lcd_read_address_counter again; $6C8E stores the byte in a frame
;          cell nothing reads, so only the busy wait and the read are kept
;   $6C9A  dds_write_reg29 ($6B4C) with zero
;
; tone_stop_isr ends in it.
; ---------------------------------------------------------------------------
tone_stop_from_isr
                lbsr    tone_lcd_address        ; $6C50
                pshs    a
                lbsr    tone_output_stop        ; $6C5C
                puls    a
                lbsr    ABI_lcd_cursor          ; $6C7F
                lbsr    tone_lcd_address        ; $6C89
                lbra    dtmf_sync_clear         ; $6C9A: $29 <- $00

; ---------------------------------------------------------------------------
; tone_lcd_address - lcd_read_address_counter
;
;   exit:  A = the display's address counter
;   uses:  A
;
; $D781: LDB >$0300, and round again while bit 7 - the busy flag - is set.
; The counter is the low seven bits, and ABI_lcd_cursor takes it back as it
; comes, which is how dtmf_echo_blank in page1_dtmf.s restores it.
; ---------------------------------------------------------------------------
tone_lcd_address
                lda     >lcd_instr              ; bit 7 set: still busy
                bmi     tone_lcd_address
                anda    #$7F                    ; the address counter
                rts

; ---------------------------------------------------------------------------
; tone_stop - stop playing, and silence the output
;
;   uses:  A, B, X, Y
;
; The state is cleared BEFORE the output is muted, so the player cannot
; advance one more step after the mute and leave a tone sounding on an
; instrument that says it is stopped.
; ---------------------------------------------------------------------------
tone_stop
                ; THE BUS IS TOLD FIRST, and only if a run was actually in
                ; progress. seq_output_set_running ($4702)'s zero leg opens
                ; LDB >$3C80 / CMPB #$00 / LBEQ past - the run flag, tested
                ; before the event_flags gate - and the LBSR $9DD3 with index
                ; 3 and code $00FF at firmware/src-generated/a2u13_page1.s
                ; line 1325 is inside both tests, ahead of the CLR >$3C80
                ; that follows. tone_state is this firmware's $3C80, so the
                ; same guard is the same guard: STOP pressed on a stopped
                ; screen, or mode entry coming through here, reports nothing.
                ;
                ; NOT FROM THE TICK ANY MORE. Both single-pass ends go through
                ; tone_stop_isr, and STOP, the stop softkey and '?' through
                ; tone_output_stop, which are the stock's routines. What is
                ; left calling this is mode entry (tone_sequence_open), manual
                ; entry (tone_key_page2_f1) and a hand-stepped pass that wraps
                ; (tone_advance_last), none of them read against its stock
                ; routine yet - so what this does beyond seq_output_stop, the
                ; report for a hand-stepped sequence and the hop latch clear,
                ; is kept for them and not claimed as the instrument's.
                ; THE FIELD ID IS NOT CLEARED HERE, and it was for one build:
                ; tone_stop is reached from the tick as well as by hand, and
                ; sequence_stop_from_isr ($6C45) touches $3C04 alone - only
                ; softkey_stop ($4AB9) clears $3D11. tests/test_shared_state.py
                ; caught it: tone_field and dtmf_field became cells the
                ; interrupt writes and the foreground writes. The clear lives
                ; in the two STOP arms instead, tone_rq_stop and tone_sk_stop.
                lda     >tone_state
                cmpa    #TONE_STOPPED
                beq     tone_stop_was_idle
                lda     #RMT_SRQ_SEQ_END
                lbsr    ABI_remote_srq_event
tone_stop_was_idle
                lbsr    ABI_tick_remove         ; nothing advances once
                                                ; the sequence is stopped
                lda     #TONE_STOPPED
                sta     >tone_state

                ; CLOSE THE GATE, PLAINLY. Every stop in the stock writes
                ; register $22 <= $21 with no pulse beside it: the ISR's
                ; single-shot end at $436D does LDA #$22 / LDB #$21 /
                ; STB $3D33 / STD $0200, and the foreground's seq_output_stop
                ; ($4881) finishes at $48AF with CLRB and a call to
                ; dds_set_output_mode_reg22 ($6B92), which turns a zero
                ; argument into $21 and hands it to dds_write_reg22 ($6B6F)
                ; for the one register. sequence_mode_init ($5380) makes the
                ; same zero-argument call at mode entry, which is the path
                ; tone_sequence_open takes through here. Before this the
                ; gate was left wherever the last edge put it, and only the
                ; output relay below muted the channel.
                ldb     #TONE_GATE_OFF
                lbsr    tone_gate_write
                ; AND THE RELAY IS LEFT ALONE, because the instrument leaves
                ; it alone. Measured on the stock: open the mode, page to the
                ; run screen, run continuous, press Stop - channel 0's latch is
                ; $01 at every one of those points and bit 2 never sets. The
                ; gate write above is the whole of the stock's silencing.
                ;
                ; This set bit 2, the output relay. Since mode entry reaches
                ; here, opening the Tone Sequence screen muted channel 0 and
                ; left it muted. See tone_start for the rest of the reasoning.

                rts

; ---------------------------------------------------------------------------
; tone_advance - play the next step
;
;   entry: through nmi_callback, which nmi_handler jumps through; the CPU
;          has stacked every register
;   exit:  RTI, on every path
;
; THE BODY IS THE CALLBACK, as blk42d1 ($42D1) and blk444c ($444C) are: it
; opens with the timer-2 clear the stock's bodies open with - LDA >ptm_status,
; then the counter read - and it owns the RTI, so nothing stands between the
; handler's jump and the work. Its tails into routines that end in RTS (the
; tone half-ticks, the two stops, the period load) are calls followed by RTI.
; The one thing it does that the stock's bodies do not is test dds_lock after
; the clear: the foreground here stages a register over several accesses, and
; a tick that lands inside one is taken one period late rather than written
; into the middle of it.
;
; CALLED FROM THE TIMER INTERRUPT, once per step, because timer 2 is loaded
; with the step's own duration and interrupts when it runs out. That is the
; stock's arrangement and it is the reason the duration is honoured exactly:
; nothing here counts, so nothing here can lose a count.
;
; What this replaced counted foreground passes. A pass is not a unit of time -
; it is however long the last screen repaint took - and the flag it watched is
; a level, so any pass longer than one period threw away the periods it slept
; through. delay_ms threw away all of them.
;
; It runs with the foreground halfway through whatever it was doing, so the
; ticks that play are short and paint nothing. The two that END a single pass
; paint the status banner, because the stock's do: tone_stop_isr reaches
; show_run_status_banner ($5C1B) as sequence_stop_from_isr ($6C45) does, with
; the display's address counter kept and put back around it.
; ---------------------------------------------------------------------------
; TWO INTERVALS PER STEP, not one. A tone step carries an ON time and an OFF
; time, and the stock alternates between them: seq_step_advance ($42B1) does
; INC $3D32 and acts only on the calls where bit 0 is now set, so the sequence
; position moves every SECOND phase, and load_current_step ($4268) picks word
; 0 of the step for the on phase and word 1 for the off phase - BCS at $4297
; taking the carry out of ASRA on that same bit.
;
; THE GAP IS SILENCED THROUGH DDS REGISTER $22, which is what the stock does
; and not something invented here to fill a hole. The NMI body at $4331 does
; ASRA on the phase byte and loads $20 for the on phase or $21 for the off,
; guards it with CMPB >$3D33 / BEQ so an unchanged value is not rewritten,
; and $4351-$4366 sends it to register $22 - the one common/formats.inc
; already names DDS_PORT_MUX_01 - inside a four-write stream that closes the
; gate, pulses register $26 and then writes the new value; tone_gate_edge is
; that stream, and both edges below go through it. Muting with the output
; relay instead would click a relay on every gap of every step.
tone_advance
                lda     >ptm_status             ; the clear: status, then the
                ldx     >ptm_timer2             ; counter ($42D1, $444C)
                tst     >dds_lock               ; the foreground mid-way
                lbne    tone_advance_done       ; through staging a register
                ; NO RUNNING TEST, AS blk42d1 AND blk444c HAVE NONE. The
                ; instrument's Stop clears its running flag, paints the status
                ; banner and only then turns the timer off
                ; (seq_output_set_running: flag, banner, seq_timer_stop), and
                ; every time-out in between runs the whole body - so the stop
                ; lands when the timer does. This returned on the flag, and the
                ; sequence went quiet on the first tick after the key. The
                ; architect's ruling of 2026-09-17: "D is testing the stop flag
                ; where the instrument tests it". Measured the same day: from
                ; the f4 press the instrument's ticks keep stepping for five
                ; time-outs. Manual is the one state that changes the path.
                lda     >tone_state
                cmpa    #TONE_MANUAL            ; the same body, one step at a
                beq     tone_advance_go         ; time, with no tick behind it
                lda     #TONE_RUNNING           ; any other state: the tick's
tone_advance_go                                 ; own body, as the stock's

                ; THE DTMF TICK OPENS WITH REGISTER $29, AND MAY NOT BE A TICK
                ; AT ALL. $444C reaches $448C - $29 <- $00 then $10 - only once
                ; it has decided the run is still going; when the once-through
                ; flag $3D34 is clear and the single-shot flag $3C81 is set it
                ; branches to $44D1 first and sends none of it. So the test of
                ; tone_pass_done comes before the sync pulse, exactly as
                ; $4487's does before $448C.
                ;
                ; A hand step is not an interrupt and gets neither: the stock
                ; steps a tone by hand through output_tone ($6A95), never
                ; through this body. A is still the state read above.
                ; A RUNNING TONE SEQUENCE IS blk42d1'S OWN BODY: tone_tick.
                tst     >tone_dtmf_mode
                bne     tone_advance_not_tone
                cmpa    #TONE_RUNNING
                lbeq    tone_advance_tick
tone_advance_not_tone
                tst     >tone_dtmf_mode
                beq     tone_advance_phase
                cmpa    #TONE_RUNNING
                bne     tone_advance_phase
                tst     >tone_pass_done
                lbne    tone_advance_dtmf_stop
                lbsr    dtmf_sync_pulse

                ; THE DIALLED EDGE COMES NEXT, BEFORE THE STEP IS READ, and both
                ; arms reach it in the same number of instructions. $4497-$44A6:
                ; LDA >$3D32 / ASRA / BCS, then LDB #$21 / BRA $44A6 on one arm
                ; and LDB #$22 / BRA $44A6 on the other, so the edge sits at the
                ; same point of every tick and the gate stands open for exactly
                ; the period plus the seven NOPs of the closing arm.
                ;
                ; It used to be written from the two paths below - the opening
                ; edge after tone_step_get and the closing one straight away -
                ; which put the opening edge 20 to 23 instructions later into
                ; its tick than the closing edge. Measured 2026-09-14 against
                ; the stock with On and Off at 1.00 ms, 1.50/4.00 and 10.00/2.50
                ; ms: the stock's gate stood open 429, 640 and 4227 instructions
                ; and this firmware's 399 or 402, 610 or 613 and 4197 or 4200 -
                ; a dialled tone 27 to 30 instructions short, alternating with
                ; the parity of the nibble tone_step_get read first.
                ;
                ; tone_phase is this player's form of $3D32's bit 0: clear, the
                ; tone is starting and the gate opens; TONE_PHASE_GAP, the gap
                ; is starting and it closes. Hand steps and the tone player are
                ; not interrupts timed against the stock's body and keep the
                ; path below.
                lda     >tone_phase
                bne     tone_advance_dtmf_off
                ldb     #TONE_GATE_ON_DTMF      ; $44A1: the tone starts
                bra     tone_advance_dtmf_edge
tone_advance_dtmf_off
                ldb     #TONE_GATE_OFF          ; $449D: the gap starts
                bra     tone_advance_dtmf_edge  ; NOT REDUNDANT: it makes this
                                                ; arm cost what the other does
tone_advance_dtmf_edge
                lbsr    tone_gate_edge_dtmf     ; $44A6-$44CF
                lda     >tone_phase
                lbne    tone_advance_gap_cleared ; the gap's edge is written
                ldd     >tone_position          ; the tone's is too: read the
                lbsr    tone_step_get           ; step, as the path below does,
                stb     >tone_playing           ; and time it. A running tick
                lbra    tone_advance_gap_check  ; is never a hand step, so the
                                                ; hand strobe is not reached
tone_advance_phase
                lda     >tone_phase
                bne     tone_advance_gap_over

                ; THE STEP NAMES A TONE; THE TONE HAS THE SETTINGS. This is
                ; the stock's own indirection, load_current_step ($4268): take
                ; the nibble at the playlist position, KEEP it, and index the
                ; tables with it. It is kept in tone_playing because the rear
                ; latch wants it later and the playlist may be edited between
                ; now and then - the stock keeps it in $3D27 for the same use.
                ldd     >tone_position
                lbsr    tone_step_get           ; B = the tone this step names
                stb     >tone_playing

                ; A DTMF STEP IS A PAIR; A TONE STEP IS ONE TONE. This is the
                ; whole of the difference between the two sequences the
                ; instrument reaches through one player: $3C03 decides whether
                ; load_current_step's nibble indexes the tone tables or names a
                ; dialled digit. NO LOCK IS TAKEN HERE and none is wanted - the
                ; stock holds none on this path, and tone_advance completes the
                ; timer-2 clear before it tests dds_lock, so a deferred tick is
                ; a LOST tick rather than a late one.
                ; THE HOP LATCH IS THE TICK'S, NOT THIS ROUTINE'S. The stock
                ; writes $0B00 in two places only: blk42d1's $431C, on the
                ; tone-on half-tick, which tone_tick is, and instrument_preset.
                ; A second store here also ran for a manual step, where the
                ; instrument writes nothing. Driven 2026-09-15, seed 3 step 80:
                ; UP in Manual left the stock's latch at 0 and set $C0 here.
                ; A dialled pair is written at the tail of this routine, where
                ; $44EE writes it.

                ldb     #TONE_GATE_ON           ; the tone is audible: the
                tst     >tone_dtmf_mode         ; stock's edge stream
                beq     tone_advance_gate_go
                ldb     #TONE_GATE_ON_DTMF      ; $449B loads $22 for the odd
                                                ; phase where blk42d1's $4331
                                                ; loads $20, which is
                                                ; dds_set_output_mode_reg22's
                                                ; ($6B92) split on $3C03
tone_advance_gate_go
                lbsr    tone_gate_edge

                ; BY HAND, THE STOCK STROBES THE TONE IT HAS JUST SELECTED.
                ; Every manual-mode step in the stock ends in output_tone
                ; ($6A95), whose last act at $6ADB is dds_update_strobe_if_idle
                ; ($4AD1): LDB >$3C80 / CMPB #$00 / LBNE skips it while the
                ; sequencer runs, otherwise $4AE5 calls the vetoed pulse
                ; $DEB6. Manual mode is always the $3C80 = 0 case, and the
                ; tick is always the running one - where the stock's NMI body
                ; has its own $26 pulse in the edge stream above - so this is
                ; the hand step's strobe and nothing else's.
                lda     >tone_state
                cmpa    #TONE_MANUAL
                bne     tone_advance_gap_check
                lbsr    tone_hand_pulse
tone_advance_gap_check

                ; AND IF THIS STEP HAS A GAP, the next interval is that gap
                ; rather than the next step's tone - so the position does NOT
                ; move yet and the period written is the off time.
                ldb     >tone_playing           ; the TONE's gap, not the
                lbsr    tone_times_address      ; step's - every step naming
                ldd     TONE_OFF,x              ; this tone shares it
                beq     tone_advance_no_gap     ; zero: no gap at all
                pshs    a
                lda     #TONE_PHASE_GAP
                sta     >tone_phase
                puls    a

                ; AND THE LAST GAP OF A SINGLE PASS IS TWO MILLISECONDS, not
                ; the step's own Off Time. load_current_step ($4268) makes the
                ; substitution at $4299-$42AB and only there: on the OFF phase,
                ; with the single-shot flag $3C81 set, and with the position
                ; $3D2C equal to Seq End $3D0F - LDX #$00C8 in place of the word
                ; it would otherwise read at $42AB. A single pass therefore runs
                ; its last digit for the full On Time and then closes on a fixed
                ; short gap, however long that digit's Off Time is; and since
                ; the run stops one tick later still, that gap is the whole of
                ; what is left of it.
                ;
                ; HELD TO THE DTMF BRANCH. The stock's substitution is in code
                ; both its players share, so a stock TONE sequence shortens its
                ; last gap too. This player's tone side does not, and that is
                ; recorded rather than changed here.
                tst     >tone_dtmf_mode
                beq     tone_advance_gap_time
                tst     >tone_single            ; $3C81
                beq     tone_advance_gap_time
                pshs    a,b                     ; the Off word, over the compare
                lbsr    tone_last_step
                puls    a,b                     ; PULS leaves the carry alone
                bcc     tone_advance_gap_time
                ldd     #TONE_LAST_GAP_COUNTS
tone_advance_gap_time
                lbra    tone_advance_timed      ; the pair, and then the latch

tone_advance_gap_over
                ; THE GAP IS STARTING NOW. Silence it, then move to the next
                ; step and time the tone that follows. The stock's stream is
                ; the same four writes at this edge as at the tone-on one:
                ; the only thing $4331 does differently for $21 is a CMPB #$21
                ; / BNE at $4347 around six NOPs at $434B-$4350.
                ldb     #TONE_GATE_OFF
                lbsr    tone_gate_edge

                ; THE PAIR IS NOT REPROGRAMMED HERE, though $44EE really is
                ; unconditional - on the straight path, on the loop path out of
                ; $44E6 and on the stop path that branches to it from $44D1.
                ; What matters is WHERE it sits: after seq_step_advance ($42B1)
                ; and load_current_step ($4268), so the nibble it programs is
                ; the one the position has just moved on to, not the one that
                ; has just finished. Programming it at this edge put the right
                ; pair one tick early. It is done at the tail instead.
                ;
                ; The re-programming is real and it is why the gap works at all:
                ; THE GAP IS MADE BY REGISTER $22, not by taking the tones away.
                ; $4331 and $449B load the mux code for the phase and the two
                ; tone generators keep whatever they were last given, so the
                ; program step can be unconditional and all the phase logic can
                ; live in $22.
tone_advance_gap_cleared                        ; a running dialled tick joins
                clr     >tone_phase             ; here with its edge written

tone_advance_no_gap
                ldd     >tone_position          ; on to the next, wrapping.
                addd    #1                      ; A WORD: 250 steps do not fit
                                                ; in a byte
                ; SIXTEEN, WHICH IS BOTH THE CAPACITY AND THE LENGTH HERE.
                ; The digital sequence has a sequence_length its editor
                ; maintains and its player wraps on; a tone sequence has no
                ; such variable - the screen edits all sixteen steps and every
                ; one is played. That is a design decision rather than an
                ; oversight, and it is written down because the two sequences
                ; look alike and their players now differ.
                ; WRAP ON SEQ END, not on the table's capacity. That is what
                ; seq_step_advance ($42B1) does with $3D0F, and without it a
                ; four-step sequence plays its four steps and then twelve
                ; slots the operator never filled - silence at a millisecond
                ; each, which is not what "four steps" means.
                ;
                ; SEQ END IS A 0-BASED LAST INDEX, so positions run 0 THROUGH
                ; tone_end INCLUSIVE and the wrap is above it, not at it. The
                ; stock settles it: seq_step_advance ($42B1) does LDX >$3d2c /
                ; LEAX 1,x / CMPX >$3d0f / BLS - it KEEPS the new position
                ; while it is less than or EQUAL to Seq End. This compared
                ; with BLO, which is the count reading, and a four-step
                ; sequence then played three.
                ;
                ; There is no "unset" case here. This substituted the whole
                ; playlist when tone_end was zero, and zero is a legitimate
                ; last index - a one-step sequence, which is what typing 1
                ; into Seq End asks for. Zero as "never initialised" belongs to
                ; tone_defaults and nowhere else: it is the port of
                ; seq_data_init ($79FE), it sets Seq End to $00F9 exactly as
                ; the stock does, and it runs once when the mode is first
                ; opened. By the time a player reads tone_end it has a real
                ; last index in it.
                ldx     >tone_end
                pshs    x
                cmpd    ,s++
                bls     tone_advance_store
                ldd     #0

                ; THE WRAP IS WHERE A SINGLE-SHOT RUN ENDS. The stock reaches
                ; the same point the same way: seq_step_advance ($42B1) clears
                ; the once-through flag $3D34 when the position passes Seq
                ; End, and the NMI body tests it at $4322 against the
                ; single-shot flag $3C81 and takes the stop path at $436D.
                ;
                ; Stopping HERE rather than at the top of the next tick means
                ; the last step of the sequence has already been programmed
                ; and timed - so it plays for its own duration and then the
                ; player stops, instead of being cut short by one step.
                ; AND A DTMF PASS TAKES ONE WHOLE TICK MORE. seq_step_advance
                ; ($42B1) clears $3D34 at the wrap and RETURNS: the interrupt it
                ; was called from carries on, load_current_step reads step 0
                ; again, $44EE programs step 0's pair and $44F1 loads step 0's
                ; On time. It is the NEXT interrupt that finds $3D34 clear at
                ; $4487 and takes the stop path at $44D1. So the instrument's
                ; sequence stops one whole interval later than this, with step
                ; 0's pair standing on the outputs. tone_pass_done carries that
                ; between the two ticks and the top of this routine reads it.
                tst     >tone_single
                beq     tone_advance_store
                tst     >tone_dtmf_mode
                beq     tone_advance_last
                inc     >tone_pass_done         ; wrapped: play this tick out,
                bra     tone_advance_store      ; and stop on the next one
tone_advance_last
                std     >tone_position          ; back to step 0, so the next
                                                ; run starts from the front
                lda     >tone_state             ; FROM THE TICK, the stock's
                cmpa    #TONE_MANUAL            ; stop: $436D is $44D1's bytes,
                bne     tone_advance_last_isr   ; and it ends at $43B3 - every
                                                ; state but Manual, as above
                lbsr    tone_stop               ; BY HAND, what it always did:
                                                ; the stock steps a manual
                                                ; sequence with the cursor and
                                                ; never reaches $436D, so this
                                                ; path has no stock twin to
                                                ; port - see tone_manual_forward
                rti
tone_advance_last_isr
                lbsr    tone_stop_isr
                rti
tone_advance_store
                std     >tone_position

                ; AND HOW LONG THE NEXT STEP LASTS - the next one, not the one
                ; just started, and that is the whole point.
                ;
                ; Timer 2 runs in a continuous mode where a write to the
                ; latches does NOT reinitialise the counter (Table 3: "Gate or
                ; Reset Causes Counter Initialization", and that row is the
                ; only one without "or Write to Latches"). At a time-out the
                ; counter has ALREADY reloaded itself from the latches. So a
                ; period written here cannot govern the interval that is
                ; already running - it governs the one after it.
                ;
                ; Writing the CURRENT step's duration therefore played every
                ; step for the PREVIOUS step's duration, and the first step for
                ; whatever tone_start had loaded. A sequence of equal steps
                ; sounded correct, which is why it survived being written; two
                ; steps of different lengths swap.
                ;
                ; So the invariant is: the latch always holds the duration of
                ; the step that will START at the next time-out. tone_start
                ; establishes it for step 0 and this maintains it.
                ldd     >tone_position
                lbsr    tone_step_get           ; the tone the NEXT step names

                ; AND IN A DIALLED SEQUENCE THAT IS ALSO THE PAIR TO PROGRAM.
                ; load_current_step ($4268) stores the nibble it read into $3D27
                ; at $4285 and dtmf_program_digit ($4438) reads $3D27 back, so
                ; the pair written at the end of this tick is the step the
                ; position has just moved to. The tone side leaves tone_playing
                ; alone here - its own tick writes it, and the screen reads it
                ; between the two.
                tst     >tone_dtmf_mode
                beq     tone_advance_store_times
                stb     >tone_playing
tone_advance_store_times
                lbsr    tone_times_address
                ldd     ,x                      ; its ON word, timer counts -
                                                ; no scaling, the table already
                                                ; holds what the latch takes
                bne     tone_advance_timed
                ldd     #$0001
tone_advance_timed
                ; THE PAIR BEFORE THE LATCH, and at the tail rather than beside
                ; the gate stream, because that is the stock's order: $444C ends
                ; `jsr dtmf_program_digit` at $44EE and only then writes timer 2
                ; at $44F1. Every path through the body that reaches a latch
                ; write comes through here.
                ;
                ; STRAIGHT TO THE PORT, as $441E and $43F4 are. This called
                ; dtmf_pair_program_nibble, whose two freq_program calls took
                ; dds_lock, masked, and split each word into fields at run time:
                ; about 135 instructions of a tick that measured 391-416 against
                ; a 422-instruction period at the default 1.00 ms, so one
                ; time-out in three found the tick still running and was lost.
                ; The tick holds the port to itself - tone_advance runs it only
                ; with dds_lock clear - so the direct loader is safe here.
                ; AND NOTHING IN THE FOREGROUND RUNS THIS BODY ANY MORE:
                ; manual stepping used to, holding dds_lock around it, and it
                ; now walks the cursor and sounds it through
                ; tone_sound_at_cursor as step_seq_index_manual ($68E2) does.
                ;
                ; A nibble cannot be out of range - the loader masks four bits
                ; and there are sixteen pairs - so there is no carry to test.
                tst     >tone_dtmf_mode
                beq     tone_advance_latch
                pshs    a,b                     ; the period, across the pair
                ldb     >tone_playing
                lbsr    dtmf_pair_write_nibble  ; $44EE: dtmf_program_digit
                puls    a,b
tone_advance_latch
                lbsr    ABI_seq_timer_period
tone_advance_done
                rti
tone_advance_tick
                lbsr    tone_tick               ; blk42d1's own time-out
                rti

; ---------------------------------------------------------------------------
; tone_last_step - is the player standing on the last step of the playlist?
;
;   exit:  carry SET when tone_position is the last step, CLEAR otherwise
;   uses:  A, B, X
;
; THE STOCK COMPARES AGAINST SEQ END, DIRECTLY. load_current_step ($4268) at
; $429F does LDD >$3D2C / CMPD >$3D0F and takes the substitution only when they
; are EQUAL - so $3D0F is the LAST INDEX, because a count could never equal the
; position of a step that exists.
;
; CORRECTED 2026-09-10. This said "tone_end is a COUNT" and subtracted one
; before comparing, which put the substitution on the step BEFORE the last one
; - and with the typed value and the display now one-based, that showed up as a
; four-step sequence playing three. tone_window_step, tone_seq_insert and
; tone_seq_delete always read it as a last index, and the stock's own $6DA2
; CMPX #$00F9 caps the cursor at 249, the last index of a 250-step playlist.
; The count reading was the odd one out and it is gone.
; ---------------------------------------------------------------------------
tone_last_step
                ldx     >tone_end
                pshs    x
                ldd     >tone_position
                cmpd    ,s++
                beq     tone_last_step_yes
                andcc   #~CC_CARRY
                rts
tone_last_step_yes
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; tone_advance_dtmf_stop - the interrupt after the wrap: the stock's $44D1
;
;   uses:  A, B, X, Y, U
;
; WHERE A SINGLE-SHOT DIALLED SEQUENCE ENDS. blk444c ($444C) tests the
; single-shot flag $3C81 against the once-through flag $3D34 at $4487 and
; branches to $44D1; seq_step_advance ($42B1) cleared $3D34 at the wrap, one
; interrupt earlier. Every write it makes, in order, and where each comes from:
;
;   $44D1  $3D33 = $21 and $22 <- $21, one STD with no compare
;   $44DB  CR2 <- $91 straight to the port, the timer interrupt off
;   $44E0  sequence_stop_from_isr ($6C45): the display counter kept,
;          seq_output_stop ($4881) - its seq_output_set_running(0) reports,
;          clears the run flag, paints the banner, runs seq_timer_stop ($6C22)
;          for CR2 <- $91 through the shadow and $29 <- $00, and calls
;          output_tone ($6A95) for the step at the Seq Index with its strobe;
;          then dds_set_output_mode_reg22 ($6B92) with 0, $22 <- $21 - the
;          counter put back, and dds_write_reg29 ($6B4C) with 0 once more.
;          tone_stop_isr and tone_stop_from_isr are those, in that order
;   $44EE  dtmf_program_digit ($441E): the pair $3D27 names
;   $44F1  timer 2 <- $3D30 - 1, and $3D30 still holds what the previous tick
;          put there - step 0's On word - with the interrupt already off
;
; UNTIL 2026-09-14 this stopped through tone_stop, which wrote CR2 once and
; after the gate where the stock writes it twice and before; programmed the
; pair of the step last played twice where output_tone programs the Seq
; Index's; painted no banner; and cleared the hop latch. The new gate
; emulator/tests/test_seq_run_new.py holds the stop tick of a RUNS pass to the
; stock's, write for write.
;
; ONE DIFFERENCE IS LEFT, AND BOUNDED. The stock's $44F1 reloads $3D30, a cell
; of its own; this reads the On word of tone_playing, which is what the wrap
; tick loaded - unless a cursor move in the foreground, in the one period
; between the wrap tick and this one, has put its step in tone_playing, as
; output_tone's $6AC9 puts it in $3D27. The latch is loaded with the interrupt
; already off, so nothing times from it; it is recorded rather than given a
; scratch cell of its own.
; ---------------------------------------------------------------------------
tone_advance_dtmf_stop
                ldb     >tone_playing           ; $3D30 AS THE WRAP TICK LEFT
                lbsr    tone_times_address      ; IT - step 0's On word - read
                ldd     ,x                      ; now, because output_tone is
                pshs    a,b                     ; about to move tone_playing
                lbsr    tone_stop_isr           ; $44D1-$44E3
                ldb     >tone_playing           ; $44EE: dtmf_program_digit
                lbsr    dtmf_pair_write_nibble  ; reads $3D27, which output_tone
                                                ; has just set to the Seq
                                                ; Index's step, or left alone
                                                ; if that is past Seq End
                puls    a,b                     ; $44F1: timer 2 <- $3D30 - 1,
                lbsr    ABI_seq_timer_period    ; the interrupt already off
                rti                             ; and $44F4's RTI

; ---------------------------------------------------------------------------
; tone_show - the sequence screen
;
;   uses:  A, B, X, Y, U
;
; Y JOINED THE LIST when the times began carrying their own unit: tone_show_time
; takes the count in Y, and the tone number's own cell is read through Y as
; well. A header that understates what it destroys is worse than none, because
; a caller believes it.
;
; NO OPTION CHECK HERE, BECAUSE THE INSTRUMENT'S PAINTERS MAKE NONE. The
; options byte is read by exactly nine stock routines - build_id_banner
; ($8000), build_option_dispatch_table ($8939), cmd_store_id ($A3C6), page0's
; p5370, dispatch_ui_event ($5D0C), key_destn ($5FE6), page0's d6044 and
; migrate_options_and_serial ($69FF), and page3's p6D70 - and not one of them
; paints this screen (docs/routine-index.txt, searched by symbol for
; installed_options). build_option_dispatch_table is where the gate lives: it
; builds the MAIN SELECTION list out of the options byte, so a mode the
; instrument has no option for is never offered. Once the mode is open the
; screen simply paints.
;
; THIS PAINTED 'Option 001 required' OVER A LIVE MODE. The bus command ST_ID
; clears the options byte as it stores a serial, and the next repaint -
; remote.s sends KEY_REFRESH after a bus command - put the refusal on the
; glass. Driven on both, 2026-09-13, inside Tone Sequence with 'ST_ID 190;':
; the instrument's '** Tone Sequence Mode **' is untouched and this firmware
; replaced line 1 with the refusal, after which a typed digit echoed into it.
; The differential harness reported it as seed 11, step 3.
;
; NOR ARE THE ENTRY AND THE RUN KEYS GATED, and they refused both until seed
; 11 step 13 showed the instrument opening Digital Sequence after ST_ID: no
; page-1 or page-2 stock routine reads installed_options. The one gate is the
; Main Selection's slot table, latched at power-on - main_menu.s.
; ---------------------------------------------------------------------------
tone_show
                ; FOUR RECORDS, IN THE INSTRUMENT'S ORDER: the title, the tone
                ; with its frequency and two times, the sequence editor, the
                ; player. The table at $416B carries them and the count byte
                ; $03 at $416A says how many; $268E is the index and
                ; enter_menu_page ($4689) mirrors it into $3C8F, which every
                ; painter is gated on.
                lda     >tone_page
                lbeq    tone_show_title
                cmpa    #TONE_PAGE_SEQ
                lbeq    tone_show_sequence
                cmpa    #TONE_PAGE_PLAYER
                lbeq    tone_show_player

                ; --- record 1, $4052 in a tone sequence and $41E3 in a
                ; dialled one ------------------------------------------------
                ldx     #tone_r1_l1
                tst     >tone_dtmf_mode
                beq     tone_show_r1_l1
                ldx     #tone_d1_l1
tone_show_r1_l1
                lda     #LCD_LINE1
                ldb     #SVC_LABEL_LEN
                lbsr    ABI_lcd_write
                ldx     #tone_r1_l2
                tst     >tone_dtmf_mode
                beq     tone_show_r1_l2
                ldx     #tone_d1_l2
tone_show_r1_l2
                lda     #LCD_LINE2
                ldb     #SVC_LABEL_LEN
                lbsr    ABI_lcd_write

                ; THE TONE NUMBER, one character at $0F.
                ; repaint_tone_dependent_fields ($5B60) renders $3D1B with
                ; byte_to_hex_digits ($CBA6), writes ONE character from $2415
                ; and passes it through dtmf_map_ef_to_star_hash ($5AF6)
                ; first - so a tone of 15 reads 'F' in a tone sequence and
                ; '#' in a dialled one, which is what the sequence window's
                ; cells read too. Driven on the stock 2026-09-11: on the DTMF
                ; settings record the minus key leaves ' Tone Number *' with
                ; $3D1B = 14 and the point key '#' with 15.
                lda     >tone_number
                lbsr    tone_hex_char
                sta     >text_buffer
                lda     #TONE_NUM_POS
                ldx     #text_buffer
                ldb     #1
                lbsr    ABI_lcd_write

                ; AND NO FREQUENCY IN A DIALLED SEQUENCE. The DTMF record has
                ; ' Manual Dial' in those columns, and a dialled digit's two
                ; tones are fixed by the signalling standard, so there is
                ; nothing to render there: show_freq_field ($571F) is reached
                ; only from repaint_page_fields' page-1 arm, and the DTMF
                ; record's own f3 label stands where the FREQ value would be.
                tst     >tone_dtmf_mode
                lbne    tone_show_r1_times

                ; THE FREQUENCY, eight of the nine characters the formatter
                ; makes. show_freq_field ($571F) renders the tuning word and
                ; then takes one of two forms on the unit code: ' Hz' blanks
                ; six leading zeros with the point after seven, 'kHz' blanks
                ; three with the point after four and the trailing zero
                ; dropped. Both leave one count a tenth of a hertz.
                ldb     >tone_number
                lbsr    tone_freq_address       ; X = its 24-bit tuning word
                lda     >tone_freq_unit
                cmpa    #UNIT_KHZ
                beq     tone_show_freq_khz
                lda     #UNIT_HZ                ; anything that is not kHz is
                sta     >tone_freq_unit         ; Hz, and the cell is put right
                clr     >format_trim            ; here: scratch_reset leaves it
                lda     #TONE_FREQ_POINT_HZ     ; zero, which names no unit
                sta     >format_point
                lda     #TONE_FREQ_DIGITS
                ldb     #TONE_FREQ_BLANK_HZ
                bra     tone_show_freq_number
tone_show_freq_khz
                lda     #$01
                sta     >format_trim
                lda     #TONE_FREQ_POINT_KHZ
                sta     >format_point
                lda     #TONE_FREQ_DIGITS
                ldb     #TONE_FREQ_BLANK_KHZ
tone_show_freq_number
                lbsr    ABI_format_fixed
                lda     #TONE_FREQ_POS
                ldx     #format_text+1
                ldb     #TONE_FREQ_W
                lbsr    ABI_lcd_write
                ldb     >tone_freq_unit
                lbsr    ABI_unit_label
                lda     #TONE_FREQ_UNIT
                ldb     #UNIT_LABEL_LEN
                lbsr    ABI_lcd_write

tone_show_r1_times
                ; AND BOTH TIMES, six characters each. render_time_value
                ; ($59A5) renders the sixteen-bit count as five digits, blanks
                ; three leading zeros and puts the point after three, so one
                ; count is a hundredth of a millisecond and the default 100
                ; reads '  1.00'.
                ldb     >tone_number
                lbsr    tone_times_address      ; X = the tone's pair
                pshs    x
                ldd     ,x                      ; TONE_ON is offset zero
                tfr     d,y                     ; THE COUNT IN Y, because the
                lda     #TONE_ON_POS            ; column goes in A and would
                ldb     #TONE_UNIT_ON           ; otherwise take its high byte
                lbsr    tone_show_time
                puls    x
                ldd     TONE_OFF,x
                tfr     d,y
                lda     #TONE_OFF_POS
                ldb     #TONE_UNIT_OFF
                lbsr    tone_show_time

                ; --- INCR SET: the field shows its STEP, not its value ------
                ; load_freq_step_field ($585F) puts record+5 and its unit in
                ; the display registers and renders them in the FREQ columns,
                ; and show_amptd_step_field ($596E) does the same with
                ; record+15 in the AMPTD columns, each registering a restore
                ; routine in $3C00. Doing it inside the repaint means any
                ; repaint keeps it, which is what that hook buys the long way
                ; round.
                tst     >tone_incr_mode
                lbeq    tone_show_done
                lbsr    tone_incr_address       ; X = the increment, B = width
                lbra    tone_show_incr_at

; ---------------------------------------------------------------------------
; tone_show_title - record 0, the mode's title screen
;
;   uses:  A, B, X
;
; No painter writes over it: every page-gated write in page 1 passes page 1, 2
; or 3, and repaint_page_fields ($5CCC) has no arm for page 0.
; ---------------------------------------------------------------------------
tone_show_title
                ldx     #tone_r0_l1
                tst     >tone_dtmf_mode
                beq     tone_show_title_l1
                ldx     #tone_d0_l1
tone_show_title_l1
                lda     #LCD_LINE1
                ldb     #SVC_LABEL_LEN
                lbsr    ABI_lcd_write
                ldx     #tone_r0_l2
                tst     >tone_dtmf_mode
                beq     tone_show_title_l2
                ldx     #tone_d0_l2
tone_show_title_l2
                lda     #LCD_LINE2
                ldb     #SVC_LABEL_LEN
                lbra    ABI_lcd_write

; ---------------------------------------------------------------------------
; tone_show_time - one of the two times, six characters and its unit
;
;   entry: A = the DDRAM column, Y = the count in hundredths of a millisecond
;   uses:  A, B, X, Y, U
;
; THE COUNT COMES IN Y, not in D. It was in D with the column in A, and `lda
; #TONE_ON_POS` then took the count's high byte with it - so a hundred counts
; rendered as $4B64, which the field read as 193.00 ms.
;
; The unit sits six columns along - $4B with $51, $60 with $66 - and is two
; characters, which is what the table's 'ms' and ' s' entries are.
; ---------------------------------------------------------------------------
tone_show_time
                pshs    a,b                     ; PSHS puts A at ,s and B at
                                                ; 1,s - the column, then which
                                                ; of the two times this is
                tfr     y,d                     ; the count
                clr     >math_work
                std     >math_work+1
                ldx     #math_work
                clr     >format_trim

                ; THE UNIT IT WAS KEYED IN, and the layout that goes with it.
                ; render_time_value ($59A5) is handed the unit through $3D17,
                ; which select_tone_and_time_pointers ($561A) points at $3C87
                ; for the On time and $3C89 for the Off, and the two forms are
                ; 'ddd.dd' and '.ddddd' - driven on the stock, 500 counts read
                ; '  5.00ms' and '.00500 s'. This showed milliseconds whatever
                ; had been keyed.
                ldx     #tone_time_unit
                ldb     1,s
                abx
                ldb     ,x
                cmpb    #UNIT_SECOND
                beq     tone_show_time_secs
                lda     #TONE_TIME_POINT_MS
                sta     >format_point
                lda     #TONE_TIME_RENDER
                ldb     #TONE_TIME_BLANK
                bra     tone_show_time_render
tone_show_time_secs
                lda     #TONE_TIME_POINT_S
                sta     >format_point
                lda     #TONE_TIME_RENDER
                ldb     #TONE_TIME_BLANK_S
tone_show_time_render
                ldx     #math_work
                lbsr    ABI_format_fixed
                lda     ,s                      ; the column
                ldx     #format_text
                ldb     #TONE_TIME_W
                lbsr    ABI_lcd_write
                ldx     #tone_time_unit
                ldb     1,s
                abx
                ldb     ,x
                lbsr    ABI_unit_label          ; X = its two characters
                puls    a,b                     ; the column, and which time
                adda    #TONE_TIME_W
                ldb     #TONE_UNIT_W
                lbra    ABI_lcd_write

; ---------------------------------------------------------------------------
; tone_show_banner - the player record's status slot: show_run_status_banner
;
;   uses:  A, B, X, Y, U
;
; $5C1B, which owns the left twenty columns of line 1 and writes nothing at
; all unless the player record is the one showing: its first test is LDB
; >$3C8F / CMPB #$03 / LBNE out, and every write it makes goes through
; lcd_write_field_if_page ($56A4) with page 3. Then one of four sources:
;
;   $3C80 set, $3C81 set     $69A6 '** Running Single **'
;   $3C80 set, $3C81 clear   $69BB '** Running Cont **  '
;   $3C80 clear, $3C82 set   the record's own first twenty bytes at $40F2,
;                            then show_seq_index ($6EF1) for the step at $08
;                            and show_manual_tone_char ($6FAC) for the tone it
;                            names at $0E
;   neither                  d4142's ' Manual'
;
; tone_page is $3C8F, TONE_RUNNING in tone_state is $3C80, TONE_MANUAL is
; $3C82 and tone_single is $3C81.
;
; A ROUTINE OF ITS OWN because the stock calls it from more places than the
; record's repaint: seq_output_set_running ($4702) paints it on BOTH halves of
; every run start, before start_sequence_timer ($6BD0) is reached, and
; tone_start does the same. It was inline in tone_show_player, so a run started
; the timer and painted afterwards.
; ---------------------------------------------------------------------------
tone_show_banner
                lda     >tone_page              ; $5C21: LDB >$3C8F
                cmpa    #TONE_PAGE_PLAYER       ; CMPB #$03 / LBNE out
                bne     tone_show_banner_done
                lda     >tone_state
                cmpa    #TONE_RUNNING
                bne     tone_show_banner_idle
                ldx     #tone_run_cont
                tst     >tone_single
                beq     tone_show_banner_paint
                ldx     #tone_run_single
                bra     tone_show_banner_paint
tone_show_banner_idle
                cmpa    #TONE_MANUAL
                beq     tone_show_banner_step
                ldx     #tone_manual
tone_show_banner_paint
                lda     #LCD_LINE1
                ldb     #TONE_BANNER_LEN
                lbra    ABI_lcd_write
tone_show_banner_step
                ; manual: the record's own twenty columns, and the step and
                ; the tone it names over them
                lda     #LCD_LINE1
                ldx     #tone_r3_l1             ; $40F2's first twenty
                ldb     #TONE_BANNER_LEN
                lbsr    ABI_lcd_write
                ldx     >tone_cursor
                leax    1,x                     ; shown one-based, as
                lda     #TONE_PLAY_IDX_POS      ; show_seq_position_field does
                lbsr    tone_show_number
                ldd     >tone_cursor            ; B = the tone this step
                lbsr    tone_step_get           ; names
                ldx     #text_buffer
                lbsr    ABI_byte_to_hex
                lda     #TONE_PLAY_VAL_POS
                ldx     #text_buffer+1
                ldb     #1
                lbra    ABI_lcd_write
tone_show_banner_done
                rts

; ---------------------------------------------------------------------------
; tone_show_player - record 3, the run controls and the level
;
;   uses:  A, B, X, Y, U
;
; Both lines of the record, then the status slot through tone_show_banner,
; then the level. In manual mode the slot's own repaint writes the record's
; first twenty columns a second time, which is what show_run_status_banner
; ($5C1B) itself does with $40F2.
; ---------------------------------------------------------------------------
tone_show_player
                lda     #LCD_LINE1
                ldx     #tone_r3_l1
                ldb     #SVC_LABEL_LEN
                lbsr    ABI_lcd_write
                lda     #LCD_LINE2
                ldx     #tone_r3_l2
                ldb     #SVC_LABEL_LEN
                lbsr    ABI_lcd_write
                lbsr    tone_show_banner

                ; THE LEVEL, five characters and the unit its magnitude chose.
                ; paint_amptd_digits_and_unit ($5896) hands the channel's
                ; 24-bit level to $D022 and writes five characters at $1E with
                ; the label at $24.
                lbsr    tone_channel_record     ; X = the channel's record
                leau    CHAN_AMPL,x
                lbsr    ABI_ampl_autorange
                pshs    b
                lda     #TONE_AMPL_POS
                ldx     #ampl_range_out
                ldb     #TONE_AMPL_W
                lbsr    ABI_lcd_write
                puls    b
                lbsr    ABI_unit_label
                lda     #TONE_AMPL_UNIT_POS
                ldb     #UNIT_LABEL_LEN
                lbsr    ABI_lcd_write

                ; --- AND INCR SET SHOWS THE STEP HERE TOO -------------------
                ; This record painted the level and stopped. The increment
                ; block at the end of record 1's path is unreachable from here,
                ; because tone_show branches away at `cmpa #TONE_PAGE_PLAYER /
                ; lbeq tone_show_player` long before it - so INCR SET armed the
                ; increment, tone_incr_mode went to 1, and the glass went on
                ; showing the value.
                ;
                ; THE INSTRUMENT PAINTS IT ON THIS RECORD. show_amptd_step_field
                ; ($596E) copies [$23BF]+15 into $3D1D, sets $3D24 = 1 so the
                ; marker glyph is drawn, and leaves the restore painter in
                ; $3C00. Traced on the stock at seed 39 step 30, six cells move
                ; across the INCR SET and they are exactly those: $3D12 $03 ->
                ; $04 (the AMPTD field id, value to step), $3D1F $64 -> $01 (100
                ; to the 1 uV step), $3D24 0 -> 1, $3C0D 0 -> 1 and $3C00 to
                ; $593A. The screen goes from 'AMPTD    100 V' to
                ; 'AMPTD<$07>     1 V'.
                tst     >tone_incr_mode
                beq     tone_show_done
                lda     >tone_field             ; only the AMPTD field has one
                cmpa    #TONE_FIELD_AMPL        ; on this record: the run
                bne     tone_show_done          ; controls are not steppable
                lda     #TONE_MARKER_POS        ; $C855's glyph
                ldx     #tone_incr_glyph
                ldb     #1
                lbsr    ABI_lcd_write

                ; AND THE STEP IN THE FIELD'S OWN GEOMETRY, not a second one.
                ; show_amptd_step_field ($596E) renders through
                ; render_amptd_field ($591D), which fixes the columns at $1E
                ; and $24 and writes the unit with the digits - so the step is
                ; laid out exactly as the level is, five characters right
                ; aligned with its label beside it. Rendering it through
                ; tone_show_incr_at instead wrote TEXT_DIGITS wide from
                ; TONE_AMPL_POS+1: measured, 'AMPTD \x07 00000001' with the
                ; digits unpadded and the run past the field eating the
                ; '\x06V' the instrument keeps.
                lbsr    tone_incr_address       ; X = the step
                tfr     x,u                     ; autorange reads it through U
                lbsr    ABI_ampl_autorange
                pshs    b
                lda     #TONE_AMPL_POS
                ldx     #ampl_range_out
                ldb     #TONE_AMPL_W
                lbsr    ABI_lcd_write
                puls    b
                lbsr    ABI_unit_label
                lda     #TONE_AMPL_UNIT_POS
                ldb     #UNIT_LABEL_LEN
                lbra    ABI_lcd_write

tone_incr_glyph
                fcb     $07                     ; the CGRAM increment marker

tone_show_done
                rts


; ---------------------------------------------------------------------------
; tone_show_incr_at - paint the selected field's increment over its value
;
;   entry: X = the increment, B = how wide it is in bytes
;   uses:  A, B, X, Y, U
; ---------------------------------------------------------------------------
tone_show_incr_at
                cmpb    #$01
                beq     tone_show_incr_byte
                pshs    x                       ; a 24-bit increment
                lbsr    ABI_uint24_to_text
                puls    x
                lda     >tone_field
                cmpa    #TONE_FIELD_AMPL
                beq     tone_show_incr_ampl
                lda     #TONE_FREQ_POS
                bra     tone_show_incr_wide
tone_show_incr_ampl
                lda     #TONE_AMPL_POS+1        ; eight digit columns, filled
                                                ; from the left ($B53D-$B555)
tone_show_incr_wide                             ; in the nine-column field
                ldx     #text_buffer
                ldb     #TEXT_DIGITS
                lbra    ABI_lcd_write
tone_show_incr_byte
                ldb     ,x                      ; a one-byte time
                ldx     #text_buffer
                lbsr    ABI_byte_to_hex
                lda     >tone_field
                cmpa    #TONE_FIELD_ON
                beq     tone_show_incr_on
                lda     #TONE_OFF_POS
                bra     tone_show_incr_short
tone_show_incr_on
                lda     #TONE_ON_POS
tone_show_incr_short
                ldx     #text_buffer
                ldb     #2
                lbra    ABI_lcd_write

; ---------------------------------------------------------------------------
; tone_query - the bus asked '?': queue the selected field's value
;
;   uses:  A, B, X, Y, U
;
; The stock's gpib_query_selected_field ($5D32) dispatches on its field
; cursor: hpib_query_freq for the frequency (eight digits, point at 7),
; gpib_report_on_off_time for the times. The same three fields here, plus
; the level, formatted with the shared formatters and queued through the
; ABI, because this screen is on page 1 and the talker is in A2U12.
; ---------------------------------------------------------------------------
tone_query
                tst     >tone_incr_mode         ; INCR SET armed: the stock's
                bne     tone_query_incr         ; gpib_report_freq_step and
                lda     >tone_field             ; gpib_report_time_step report
                cmpa    #TONE_FIELD_AMPL        ; the STEP of the selected
                beq     tone_query_ampl         ; field, not its value
                cmpa    #TONE_FIELD_TONE        ; THE TONE NUMBER is three
                beq     tone_query_small        ; characters of a single byte,
                cmpa    #TONE_FIELD_SEQIDX      ; as hpib_query_tone_number
                lbeq    tone_query_word         ; ($5E9B) reports $3D1B: LDB,
                cmpa    #TONE_FIELD_SEQEND      ; CLRA, render, LDB #$03
                lbeq    tone_query_word
                cmpa    #TONE_FIELD_SEQDATA     ; and the SEQUENCE ITSELF, which
                lbeq    tone_query_seq          ; is what $3D11 = 9 reports
                cmpa    #TONE_FIELD_FREQ
                lbne    tone_query_time
                lbsr    tone_field_address      ; X = the tuning word
                tfr     x,u
                ldb     #1                      ; tenths of a hertz
                lbsr    ABI_format_places
                ldx     #chan_text
                ldb     #AMPL_TEXT_W
                lbra    ABI_remote_queue
tone_query_ampl
                lbsr    tone_channel_record
                lbsr    ABI_ampl_text
                ldx     #chan_text
                ldb     #AMPL_TEXT_W+AMPL_TEXT_U
                lbra    ABI_remote_queue
tone_query_incr
                lbsr    tone_incr_address       ; X = the increment, B = width
                cmpb    #TONE_WIDTH_WORD        ; A TIME STEP IS A WORD, and it
                lbeq    tone_query_seconds      ; goes out in the SAME six
                                                ; characters the time itself
                                                ; does: gpib_report_time_step
                                                ; ($5E64) is
                                                ; gpib_report_on_off_time
                                                ; ($5E2B) instruction for
                                                ; instruction over the
                                                ; increment pointer $3D15
                                                ; instead of the value pointer
                                                ; $3D13 - the same $C912, the
                                                ; same $CD50 over five digits,
                                                ; the same LDB #$06 / STB 2,S
                                                ; and the same tail l5f1d.
                                                ;
                                                ; THE TEST WAS cmpb #$01 AND
                                                ; NOTHING ANSWERS 1 HERE:
                                                ; tone_incr_address returns 3
                                                ; or TONE_WIDTH_WORD, so a
                                                ; time step took the 24-bit
                                                ; path below - which read
                                                ; THREE bytes of a TWO-byte
                                                ; cell (scratch.inc:915
                                                ; declares incr_tone_on as 2
                                                ; at SCRATCH_BASE+$3A6) and
                                                ; rendered them as nine
                                                ; characters of tenths.
                tfr     x,u                     ; a 24-bit step, as the value
                ldb     #1                      ; would be shown
                lbsr    ABI_format_places
                ldx     #chan_text
                ldb     #AMPL_TEXT_W
                lbra    ABI_remote_queue
tone_query_small
                lbsr    tone_field_address      ; a plain byte: the tone number
                ldb     ,x
                bra     tone_query_byte

tone_query_seq
                ; THE SEQUENCE ITSELF, from the cursor to Seq End, one
                ; character a step. hpib_query_sequence ($72B2)'s arm for
                ; $3D11 = 9 walks from $3D0D up to $3D0F, reads each nibble
                ; with l450f - tone_step_get here - turns 0-9 into '0'-'9'
                ; and $0A-$0F into 'A'-'F' by adding $41 to the difference,
                ; and runs each through dtmf_map_ef_to_star_hash ($5AF6), so
                ; a DIALLED sequence reports '*' and '#' where a tone one
                ; reports 'E' and 'F'. tone_hex_char is that conversion and
                ; that substitution, and it is the same routine the window
                ; and the Tone Number field are painted with - so what the
                ; bus reads back is what the glass shows.
                ;
                ; THE WHOLE SEQUENCE FITS. rmt_out is the stock's own $2285,
                ; 252 bytes, and RMT_OUT_MAX is the 250 characters a full
                ; playlist needs - the cap is there so nothing can run off
                ; the buffer, not because the report is short. Driven against
                ; the stock: both firmwares report all 250 characters of a
                ; freshly initialised DTMF sequence.
                ;
                ; The stock queues whatever it accumulated, including nothing
                ; at all when the cursor is already past the end, and this
                ; queues nothing in that case rather than an empty response.
                ldy     #rmt_out
                ldx     >tone_cursor
tone_query_seq_step
                cmpx    >tone_end               ; the END IS INCLUDED: $3D0F is
                bhi     tone_query_seq_done     ; the last index, not the count
                cmpy    #rmt_out+RMT_OUT_MAX
                bhs     tone_query_seq_done
                pshs    x,y
                tfr     x,d                     ; D = the step
                lbsr    tone_step_get           ; B = its nibble
                puls    x,y
                tfr     b,a
                lbsr    tone_hex_char           ; A = the character shown for it
                sta     ,y+
                leax    1,x
                bra     tone_query_seq_step
tone_query_seq_done
                tfr     y,d
                subd    #rmt_out                ; the length built
                tstb
                beq     tone_query_seq_none
                ldx     #rmt_out
                lbra    ABI_remote_queue
tone_query_seq_none
                rts

tone_query_word
                ; SEQ INDEX AND SEQ END are plain step counts, 0 to 250, and
                ; the stock reports both through gpib_report_sequence ($5EA9),
                ; arms [7] [8] and [9] of the d5F07 table. They are words here
                ; because the playlist is 250 steps deep, so the byte path
                ; below would report the high half of one.
                ; FIVE DIGITS, ZERO-PADDED, which is TONE_SEQ_DIGITS. $72BE
                ; renders [$3D37]+1 with u16_to_5_ascii_digits ($C912) and
                ; sets the length to five with LDB #$05 / STB 2,S, so a Seq
                ; End of 250 goes out as '00250'. This queued THREE and
                ; answered '250' - the same number in a field two characters
                ; short of the instrument's, which a controller reading a
                ; fixed-width answer cannot parse. The five come out of
                ; uint24_to_text's eight zero-padded digits by taking the
                ; last five, which are the same five characters $C912 makes
                ; of a sixteen-bit value.
                ; format_places is not used because it cannot render ZERO
                ; decimal places - with places = 0 its chan_before equals
                ; TEXT_DIGITS, the point is stored after the eighth digit, and
                ; a step number would go out as "       5.".
                lbsr    tone_field_address      ; X = the word
                ldd     ,x
                addd    #1                      ; ONE-BASED OUT, as the glass
                                                ; and the stock both are:
                                                ; hpib_query_sequence's arm at
                                                ; $72BE is LDD [$3D37] / ADDD
                                                ; #$0001, the same pair
                                                ; show_seq_position_field
                                                ; ($6E71) uses at $6E7B-$6E7F,
                                                ; and the setter's $7776 SUBD
                                                ; #$0001 is its inverse. This
                                                ; reported the raw cell, so
                                                ; the bus answered 249 for the
                                                ; Seq End the panel shows as
                                                ; 250 and a set/query round
                                                ; trip walked the number down
                                                ; by one every pass
                clr     >chan_work              ; into the shared 24-bit cell
                std     >chan_work+1
                ldx     #chan_work
                lbsr    ABI_uint24_to_text      ; eight digits, zero-padded
                ldx     #text_buffer+TEXT_DIGITS-TONE_SEQ_DIGITS
                ldb     #TONE_SEQ_DIGITS        ; the last five of them
                lbra    ABI_remote_queue

tone_query_time
                ; THE ON AND OFF TIMES GO OUT IN SECONDS, six characters, and
                ; where the point falls is the whole of it.
                ; gpib_report_on_off_time ($5E2B) reads its value INDIRECTLY
                ; through $3D13 with LDY, renders sixteen bits with
                ; u16_to_5_ascii_digits ($C912) into $2285, then calls
                ; format_with_decimal_point ($CD50) with a digit count of five
                ; ($5E44 LDB #$05 / SEX / TFR D,X) and BOTH of its other two
                ; arguments cleared ($5E3C and $5E40, CLRB / SEX / TFR D,U and
                ; TFR D,Y) - no digit before the point and no trailing zero
                ; blanked - and sets the length to six ($5E5F LDB #$06 / STB
                ; 2,S) before joining l5f1d. So the point comes FIRST and all
                ; five digits follow it, which makes the reply the count in
                ; SECONDS: a count is ten microseconds, so five places after
                ; the point is exactly that.
                ;
                ; Measured on the stock through the differential harness on
                ; 2026-09-13: 100 counts answers '.00100', 500 counts
                ; '.00500', 25,000 counts '.25000' and 50,000 counts '.50000'
                ; while the glass beside it reads '500.00ms'. This answered
                ; nine characters of milliseconds - '     1.00' where the
                ; instrument sends '.00100' - so a controller reading the
                ; number back got it a hundredfold too large in a field three
                ; characters too wide.
                lbsr    tone_field_address      ; X = the time; B = its width
                cmpb    #$02
                bne     tone_query_time_byte
tone_query_seconds
                ; ENTERED WITH X ON A TWO-BYTE COUNT, by the increment arm as
                ; well as by the value one - $5E64 and $5E2B differ only in
                ; which pointer they read.
                ldd     ,x                      ; the count, into the shared
                clr     >chan_work              ; 24-bit cell format_fixed
                std     >chan_work+1            ; renders from
                clr     >format_trim            ; $5E40's cleared Y: nothing
                                                ; trailing is blanked
                lda     #TONE_TIME_POINT_S      ; the point before every digit,
                sta     >format_point           ; which is the same seconds
                                                ; form tone_show_time paints
                ldx     #chan_work
                lda     #TONE_TIME_RENDER       ; five digits, $5E44's #$05
                ldb     #TONE_TIME_BLANK_S      ; and $5E3C's cleared U: no
                lbsr    ABI_format_fixed        ; leading zero blanked either
                ldx     #format_text
                ldb     #TONE_TIME_W            ; six characters, $5E5F's #$06
                lbra    ABI_remote_queue
tone_query_time_byte
                ldb     ,x
tone_query_byte
                clr     >chan_work
                clr     >chan_work+1
                stb     >chan_work+2
tone_query_text
                ldx     #chan_work
                lbsr    ABI_uint24_to_text      ; eight digits
                ldx     #text_buffer+5          ; the last three: 0..255
                ldb     #3
                lbra    ABI_remote_queue

; ---------------------------------------------------------------------------
; tone_sequence_open - the mode entry point, reached through $4001
;
;   exit:  the sequence screen is showing, stopped, at step 0
;   uses:  A, B, X, Y, U
;
; Entering the mode always STOPS a running sequence and returns to step 0.
; That is deliberate: an operator arriving at this screen needs to know what
; the instrument is doing, and a sequence that carries on playing while the
; screen is being read means the display and the output disagree from the
; first moment. Stopping is also the safe direction - it silences the output
; rather than starting something.
;
; The option check comes first, so an instrument without Option 001 says so
; instead of painting a screen whose keys would all be refused.
; ---------------------------------------------------------------------------
; ---------------------------------------------------------------------------
; tone_defaults - the tables as a cold entry into the mode leaves them
;
;   uses:  A, B, X, Y
;
; PORTED FROM seq_data_init ($79FE) and seq_mode_defaults ($5224). The stock
; fills all 250 playlist steps with (index AND $0F) - so step i names tone
; i mod 16 - sets Seq End to $00F9, seeds BOTH words of every $3C10 record
; with $0064, which is 100 counts, one millisecond, copies $EA58's three zero
; bytes into every one of the sixteen frequencies at $3C50 ($52D0-$52F0), and
; clears the tone number $3D1B.
;
; ON EVERY ENTRY, because the stock's is. sequence_mode_init ($5380) runs
; seq_mode_defaults whenever its reason is 0 ($53DE LBNE), and the Main
; Selection passes 0 - the only way into this page (main_menu.s, page_enter
; and page_enter_second); a recall copies the tables back without coming
; through here. This ran once and kept whatever a previous visit left, and it
; never zeroed a frequency: traced on the emulator, seed 6, the instrument's
; tone 0 went to 000000 when DTMF Sequence was entered at step 96 and read
; '0.0 Hz' on the Tone Sequence entry at step 108, where this still had the
; 1 kHz typed in at step 48. The words seq_mode_defaults also sets to $000A
; at $3C83, $3C85, $3C8B and $3C8D have no cell named for them here yet.
; ---------------------------------------------------------------------------
tone_defaults
                clr     >tone_number            ; $3D1B
                ; AND THE FREQUENCY READS IN HERTZ AGAIN. The stock keeps this
                ; field's unit in the channel record's word at +3, which
                ; render_freq_field ($5826) copies into $3D22 at $5855, and
                ; seq_mode_defaults' init_channel_blocks ($C4F0) rewrites that
                ; record on every cold entry. Dumped on the stock on the
                ; emulator: $3D22 reads $000A after the entry and the field
                ; shows '0.0 Hz', 1 after 'FREQ 1 kHz' ('1.000 kHz') and 2
                ; after 'FREQ 5 Hz' - so anything but kHz paints hertz, which
                ; is the rule tone_show_r1_l2 paints by. This kept the unit a
                ; previous visit keyed: seed 6 step 109 read '0.000 kHz' where
                ; the instrument read '0.0 Hz'.
                lda     #UNIT_HZ
                sta     >tone_freq_unit
                ldb     #0                      ; every frequency to zero
tone_defaults_freq
                pshs    b
                lbsr    tone_freq_address
                puls    b
                clr     ,x
                clr     1,x
                clr     2,x
                incb
                cmpb    #TONE_TONES
                blo     tone_defaults_freq

                ; AND BOTH TIMES READ IN MILLISECONDS to start with, which
                ; is what the cold screen shows: seq_mode_defaults ($5224)
                ; leaves $3C87 and $3C89 at the millisecond code and the
                ; field reads '  1.00ms'.
                lda     #UNIT_MILLISEC
                sta     >tone_time_unit+TONE_UNIT_ON
                sta     >tone_time_unit+TONE_UNIT_OFF

                ldb     #0                      ; every tone: 1 ms on, 1 ms off
tone_defaults_tone
                pshs    b
                lbsr    tone_times_address
                puls    b
                ldy     #TONE_MS_COUNTS
                sty     ,x                      ; TONE_ON is offset zero
                sty     TONE_OFF,x
                incb
                cmpb    #TONE_TONES
                blo     tone_defaults_tone

                ldx     #0                      ; step i names tone i AND $0F
tone_defaults_step
                tfr     x,d
                andb    #TONE_TONES-1
                pshs    x                       ; tone_step_put CLOBBERS X -
                lbsr    tone_step_put           ; it walks the byte address in
                puls    x                       ; it - so the step counter is
                leax    1,x                     ; kept on the stack
                cmpx    #TONE_PLAYLIST
                blo     tone_defaults_step

                ldx     #TONE_PLAYLIST-1        ; the stock's $00F9
                stx     >tone_end
                ; AND NO LABEL ON THIS RETURN. One stood here with nothing
                ; branching to it, and a label nothing branches to is a
                ; ROUTINE BOUNDARY to every static tool in this tree - so
                ; the empty-routine check would read the rts below as a
                ; routine with no body, which this rule refuses. The rts is
                ; tone_defaults' own, reached by falling through.
                rts

tone_sequence_open
                ; THE ENTRY REASON arrives in U (MODE_COLD in scratch.inc) and
                ; is kept on the stack for the whole entry, because
                ; sequence_mode_init ($5380) reads its argument at $0009,s at
                ; five places and the steps it decides are spread through
                ; what follows: the preset, the defaults, the channel-1
                ; carrier, the apply, the filter line, the record and the
                ; cursor. Anything that is not a recall or a keep-state entry
                ; is taken as cold. It comes off at the one exit, above
                ; tone_show.
                tfr     u,d
                cmpd    #MODE_RECALL
                beq     tone_sequence_open_reason
                cmpd    #MODE_KEEP
                beq     tone_sequence_open_reason
                clrb                            ; cold
tone_sequence_open_reason
                pshs    b                       ; 0,s: the reason
                ; NO OPTION CHECK. The stock's page-1 and page-2 routines never
                ; read installed_options - docs/routine-index.txt lists every
                ; stock reader and none is on these pages. The option gates
                ; the Main Selection's slots, once, at power-on (main_menu.s,
                ; main_menu_latch). A gate here, read live, refused a mode the
                ; instrument opens after ST_ID clears $3FFC: seed 11 step 13.
                lda     #SEQKIND_TONE           ; AND THIS IS THE SEQUENCE A
                sta     >seq_kind_live          ; SAVE WILL CARRY. The register
                                                ; has one slot for whichever
                                                ; sequence was live, which is
                                                ; what the instrument has; see
                                                ; REGISTER_SEQBLOCK in
                                                ; hp8904a-rewrite/common/ram.inc
                clr     >tone_dtmf_mode         ; THE TONE READING of the shared
                                                ; playlist, as
                                                ; tone_sequence_mode_enter
                                                ; ($55C5) clears $3C03 at $55D9
                ; ON A COLD ENTRY ONLY, which is the stock's entry reason.
                ; sequence_mode_init ($5380) dispatches on the reason at
                ; $0009,s: reason 2 skips to l539e, reason 1 goes to
                ; recall_sequence_setup ($6D19), and only reason 0 falls
                ; through to seq_data_init ($79FE) and seq_mode_defaults
                ; ($5224). A recall or a keep-state entry leaves the stored
                ; sequence alone. This called tone_defaults unconditionally,
                ; so every re-entry rewrote the 250-step ramp - the harness
                ; saw it as seed 47 step 36, bus 'RUNC;': the instrument
                ; sounds the nibble at step 0, $0 from its own cold seed,
                ; column 1 at 13360, while this firmware had re-seeded at a
                ; different moment and sounded $D, column 3 at 16330.
                ; Channels 1-3 agree because only the sounded pair's column
                ; register moves.
                ;
                ; A RECALL OR A KEEP-STATE ENTRY NEVER SEEDS. Reason 1's
                ; sequence is the register's, which register_restore has just
                ; copied in as recall_sequence_setup ($6D19) copies it, and
                ; reason 2's is the one battery RAM kept.
                ;
                ; AND REASON 0 ALWAYS SEEDS. seq_data_init ($79FE) tests its
                ; argument with CMPX #$0000 / LBNE l7a51 and on zero refills
                ; the 250 nibbles whatever they hold, and l5483 calls it with
                ; the entry reason on every entry. This tested tone_end
                ; instead - the stand-in for a reason before one was passed -
                ; so a menu entry after an edit kept the edited playlist:
                ; measured 2026-09-16, harness seed 1 step 96, the block opens
                ; DTMF Sequence and the instrument sounds step 0's digit 0
                ; where this sounded 3.
                tst     ,s                      ; the reason
                bne     tone_sequence_open_seeded
                lbsr    tone_defaults           ; a usable sequence on a cold
                                                ; instrument, as the stock's
                                                ; seq_data_init ($79FE) gives
tone_sequence_open_seeded
                clr     >tone_incr_mode         ; a fresh screen has no
                                                ; increment armed: the stock's
                                                ; mode entry zeroes $3D11 with
                                                ; the rest of its state
                ; THE PRESET AND THE RECORD DEFAULTS ARE REASON 0'S. A recall
                ; was preset by register_restore ahead of its copy, as the
                ; handler presets ahead of recall_sequence_setup; a keep-state
                ; entry is not preset at all (CMPX #$0002 / LBEQ l539e);
                ; and init_channel_blocks belongs to seq_mode_defaults, which
                ; only reason 0 calls.
                tst     ,s                      ; the reason
                bne     tone_sequence_open_preset
                lbsr    ABI_instrument_preset   ; QUIESCE FIRST. Entering a
                                                ; sequence mode takes the
                                                ; channels over, so whatever
                                                ; the last mode left driving
                                                ; stops driving before this
                                                ; screen puts anything up.
                                                ; The stock presets at every
                                                ; one of its mode entries.
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

                ; AND EVERY DESTINATION OUT OF THE RECORDS BEFORE THE APPLY.
                ; This is the FIRST PASS of reapply_all_channels ($C5B1),
                ; $C5BB-$C5FA: for each of the four records it saves the
                ; destination word at +$21 into $24DE+2i and writes $0010 -
                ; Off - over it. The second pass then applies each record,
                ; and channel_apply_and_propagate ($BE5C) takes its Off
                ; branch ($BE82 CMPX #$0010) for every one of them, writing
                ; the level register with zero and returning at $C065 before
                ; any latch. So a sequence-mode entry leaves the levels at
                ; zero and the destinations parked until the Channel
                ; Configuration screen puts them back, which is what
                ; enter_channel_config_mode ($528F) does at $5404-$543D.
                ;
                ; This firmware's channel_reapply_all is only the SECOND
                ; pass, so without this call the apply found four records
                ; still routed and programmed 140 uV into channels 0, 2 and
                ; 3. Measured against the stock through the differential
                ; harness on 2026-09-13: opening Tone Sequence left the stock
                ; at level codes (1879, 0, 0, 0) and this firmware at (1879,
                ; 0, 1879, 1879).
tone_sequence_open_preset
                lbsr    ABI_channel_park_destinations

                ; AND THE TWO THINGS THE MODE DOES TO THE CHANNELS
                ; ITSELF, which the reapply above cannot know about.
                ;
                ; CHANNEL 1 CARRIES 200 kHz, from the constant at page 1's
                ; $425C: seq_mode_defaults ($5224) forces $23BE to 1 at
                ; $524A, re-caches the record pointer at $5252, copies the
                ; three bytes into it at $5280, programs register $09 at
                ; $5292, zeroes the record's level at $52A6 and programs that
                ; too at $52BC. Why the instrument wants a carrier there is
                ; not established by the ROM - the constant is a literal with
                ; no arithmetic behind it - but it is there on purpose, and
                ; leaving it out left this firmware's channel 1 at 1 kHz
                ; where the instrument's is at 200 kHz. The differential
                ; harness reported it against the stock on 2026-09-12.
                ;
                ; The record is written BEFORE the reapply rather than after
                ; it, so the values reach the chip through the one path that
                ; programs a record - which lands the same state in one pass
                ; where the stock takes two. The ORDER of the words on the
                ; bus differs by that much and the state does not.
                lbsr    ABI_channel_park_destinations
                                                ; AND OFF THEM ALL FIRST.
                                                ; reapply_all_channels ($C5B1)
                                                ; parks every record's
                                                ; destination at $C5E8-$C5F2
                                                ; BEFORE it applies anything,
                                                ; so a sequence mode's apply
                                                ; finds four Off channels and
                                                ; programs four zero levels -
                                                ; the mode is taking them
                                                ; over. Without it this
                                                ; firmware applied the sockets
                                                ; the record reset had just
                                                ; handed back and left 140 uV
                                                ; on three channels the
                                                ; instrument had silenced.
                tst     ,s                      ; THE CARRIER IS
                lbne    tone_sequence_open_kept ; seq_mode_defaults', reason 0
                ldx     #channel_records+CHAN_RECORD
                lda     #$1E
                sta     ,x                      ; CHAN_FREQ is offset zero,
                                                ; and the two assemblers spell
                                                ; a WRITTEN zero offset
                                                ; differently - $84 against
                                                ; $00, both one byte and both
                                                ; correct - so the no-offset
                                                ; form is the one that makes
                                                ; them agree
                lda     #$84
                sta     CHAN_FREQ+1,x
                lda     #$80
                sta     CHAN_FREQ+2,x
                clr     CHAN_AMPL,x             ; and no level on it: $52A6
                clr     CHAN_AMPL+1,x           ; copies $EA58's three zeros
                clr     CHAN_AMPL+2,x

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
                bra     tone_sequence_open_applied

                ; A RECALL OR A KEEP-STATE ENTRY APPLIES THE RECORDS IT HAS.
                ; sequence_mode_init's l53ee, on reasons 1 and 2: $C5B1, whose
                ; park pass is the call above, then on reason 1 alone the four
                ; output latches from the saved latch bytes at $24F0+n through
                ; port_latch_rmw ($DBA1) - register_apply, which does both.
tone_sequence_open_kept
                lda     ,s
                cmpa    #MODE_RECALL
                bne     tone_sequence_open_keep
                lbsr    ABI_register_apply      ; $C5B1 and the latch walk
                bra     tone_sequence_open_applied
tone_sequence_open_keep
                lbsr    ABI_channel_reapply_all ; $C5B1 alone
tone_sequence_open_applied

                ; AND CHANNEL 0 IS ROUTED BACK TO Out1, alone of the four.
                ; The park above took every destination out of the records;
                ; sequence_mode_init puts exactly one of them back and routes
                ; it, at $5483-$54AB - CLR >$23BE selects channel 0,
                ; cache_channel_record_ptr ($C21A) re-caches its pointer, LDX
                ; >$23BF / LEAX <$21,X / LDD #$000C / STD ,X writes $000C, the
                ; code for Out1, into the record's destination word, and
                ; route_source_selector ($C7B0) is then called with channel 0
                ; and that same $000C to put the socket's multiplexer field on
                ; the channel. That is why the instrument's channel 0 still
                ; carries a level after a sequence entry while its other three
                ; are silent - and why the tone comes out of Out1 at all.
                ;
                ; destn_apply is the routine that does BOTH here: it stores
                ; the code in routed_dest and CHAN_DEST and routes it, which
                ; is what channel_restore_destinations does with a parked one.
                ; Writing CHAN_DEST alone is not enough and was tried:
                ; ampl_propagate reads routed_dest, not the record, so the
                ; level went out as zero and nothing was on the socket.
                ; Nothing can refuse it - destn_check's refusals are a channel
                ; modulating itself, a dc conflict with another channel and a
                ; destination the options do not cover, and the park two
                ; blocks up has just left every socket free.
                lda     #TONE_CHANNEL
                ldb     #LBL_OUT1               ; $000C
                lbsr    ABI_destn_apply

                ; AND ITS LEVEL THEN GOES ON THE CHIP, which is
                ; apply_amplitude ($5F70) at $54E7: it hands the record's +10
                ; to dispatch_channel_function ($C069) for channel 0.
                ; ampl_reapply is that dispatch. It reads the unit from the
                ; DESTINATION, which is this firmware's own shape, so it has
                ; to follow the routing above and not precede it - with the
                ; record still parked Off it would take ampl_set_as_silent and
                ; put zero where the AMPTD field says 140 uV.
                lbsr    tone_channel_record     ; X = channel 0's record,
                                                ; B = TONE_CHANNEL
                lbsr    ABI_ampl_reapply

                ; AND THE SIXTEEN TONE SLOTS GO DOWN TO THE CHIP.
                ; sequence_mode_init ($5380) calls
                ; download_all_tone_frequencies ($6A57) at $53FD and
                ; seq_mode_defaults ($5224) again at the end of its own cold
                ; pass. See tone_download_all for what a slot costs and why
                ; the chip wants all sixteen.
                ;
                ; IT GOES LAST HERE AND NOT AT $53FD's PLACE, which is before
                ; the routing, and the reason is that the two routings are not
                ; the same size. The stock routes with route_source_selector
                ; ($C7B0), which writes the multiplexer and the mode
                ; parameters and NOTHING to a frequency register, so its
                ; channel 0 keeps the last word the download left in register
                ; $08 - tone 15's. destn_apply above is the port of the whole
                ; of set_channel_destination ($78BF), which re-applies the
                ; record's frequency as it joins the socket, so with the
                ; download first this firmware ended the entry with the
                ; record's 1 kHz in $08 where the instrument has tone 15's
                ; word. Measured on 2026-09-13, that order gave 10000 against
                ; the stock's 0. Running it last lands the state the stock
                ; ends in, slot for slot and register for register.
                lbsr    tone_download_all

                ; AND REGISTER $1C TO $02, the write $5500 makes on EITHER
                ; entry - see DDS_ZERO_LT and DTMF_ZERO_LT_RUN in
                ; page1_dtmf.s: "sequence_mode_init ($5380) calls it with 2
                ; at $5500, on the tone entry and the dialled one alike."
                ; dtmf_sequence_open carries this write and tone_sequence_open
                ; did not, so register $1C was left at whatever an earlier
                ; screen had put there - measured through the differential
                ; harness as this firmware's $0F against the stock's $02
                ; after a Tone Sequence entry.
                ldx     #DTMF_ZERO_LT_RUN
                ldb     #DDS_ZERO_LT
                lbsr    ABI_dds_write

                ; AND CHANNEL 0's FILTER LINE GOES IN. seq_mode_defaults
                ; loads #$01 at $536C and calls set_channel_byte_24ec ($F713)
                ; at $5378 with index 0, so a sequence mode forces channel
                ; 0's filter byte to 1 and drives the line from it. Measured
                ; against the stock: its channel 0 latch reads $01 after this
                ; entry and this firmware's read $00. That is seq_mode_defaults,
                ; so reason 0's alone.
                tst     ,s                      ; the reason
                bne     tone_sequence_open_filter
                lda     #LATCH_FILTER
                clrb                            ; channel 0
                lbsr    ABI_filter_force
tone_sequence_open_filter
                ldx     #tone_key
                lbsr    ABI_screen_install
                ; AND THE MODE OPENS ON ITS TITLE RECORD, whatever record the
                ; last visit left it on. menu_show ($8A08) installs the mode's
                ; record table and does CLR >$268E as it does so, and both
                ; entry points call it before sequence_mode_init ($5380) -
                ; tone_sequence_mode_enter ($55C5) with d416b and
                ; enter_dtmf_sequence_mode ($7A81) with $4234 - so a re-entry
                ; always comes up on record 0. sequence_mode_init itself does
                ; NOT write $268E on a cold entry: the LDB >$3C8F / STB >$268E
                ; at $5473 sits on the reason-non-zero branch that $53E8 jumps
                ; over.
                ;
                ; THE DIALLED SCREEN ALREADY DID THIS and this one did not, so
                ; the two chains paged out of step with each other and with the
                ; instrument: re-entering Tone Sequence after walking to record
                ; 2 came up on record 2, and the harness then compared a stock
                ; on the tone record against this firmware on the sequence
                ; editor. Measured 2026-09-13, opening the mode three times in
                ; a row with NEXT presses between.
                clr     >tone_manual_sel        ; $3D11 zeroed: not Manual's
                clr     >tone_field             ; $3D11, as $4C87 leaves it
                clr     >tone_edit              ; $3D35, as $7160 leaves it
                tst     ,s                      ; the reason
                bne     tone_sequence_open_record
                clr     >tone_page              ; $268E
                clr     >active_record          ; which a save carries

                ; AND THE CURSOR GOES BACK TO STEP 0, with the window on it.
                ; seq_data_init ($79FE), called from sequence_mode_init at
                ; $5535 with the entry reason, writes $3D0D = 0 at $7A46 on
                ; reason 0 - which is what both menu entries pass - and then
                ; at $7A51 copies $3D0D into the window origin $3D39.
                ldd     #$0000
                std     >tone_cursor            ; $7A46
                std     >tone_window            ; $7A51
                bra     tone_sequence_open_cursor

                ; ON A RECALL OR A KEEP-STATE ENTRY THE RECORD COMES BACK,
                ; and the cursor stays. l5473, on reasons 1 and 2: LDB >$3C8F
                ; / STB >$268E and menu_page_show ($89AA) - measured on the
                ; stock 2026-09-16, a register saved on record 1 recalls onto
                ; record 1. The stock takes the byte as it stands; here it is
                ; bounded first, because active_record can hold anything a
                ; battery or an older build left, and a record past the last
                ; would index the softkey tables beyond their end. seq_data_init
                ; skips its reason-0 fill and still lays the window on the
                ; cursor at $7A51.
tone_sequence_open_record
                lda     >active_record
                cmpa    #TONE_PAGES
                blo     tone_sequence_open_record_on
                clra                            ; past the last: the title
tone_sequence_open_record_on
                sta     >tone_page
                sta     >active_record
                ldd     >tone_cursor            ; $7A51: the window on the
                std     >tone_window            ; cursor that is kept
tone_sequence_open_cursor

                ; AND THE MODE OPENS WITH NOTHING ARMED, which is what the
                ; instrument does and the opposite of what this did. A field
                ; is armed by a FIELD KEY and by nothing else:
                ; numeric_entry_key_handler ($B3C2) calls
                ; entry_exit_restore_display at $B45C for a state key and at
                ; $B48C for FREQ, AMPTD, PHASE and WAVEFORM, and only the
                ; screen's own arm through $3C0E sets $23A8. A mode entry sets
                ; nothing.
                ;
                ; This armed the field on the way in, and the record the mode
                ; opens on is the TITLE - which has no fields at all. tone_field
                ; is zero there and zero is TONE_FIELD_FREQ, so a digit typed on
                ; the banner echoed into it at column $19. Driven on both,
                ; 2026-09-13, straight after the mode opens: the stock's $23A8
                ; reads 00 and this firmware's entry_armed read 01, and '0', '7'
                ; and '.' each painted themselves over '** Tone Sequence Mode
                ; **' while the instrument ignored all three.
                ;
                ; NEXT already left nothing armed - tone_entry_none is the port
                ; of that same $B45C call - so only the entry itself was out of
                ; step, and record 1 onwards behaved correctly the whole time.
                lbsr    tone_entry_none         ; $B394's CLR >$23A8
                lbsr    tone_stop               ; stop and silence, always
                ldd     #$0000                  ; back to the first step. A
                std     >tone_position          ; WORD, so both bytes: clr
                                                ; wrote only the high one and
                                                ; the player reads the low
                lda     #TONE_STOPPED
                sta     >tone_state

                ; AND REGISTER $1B TO ZERO, the tail of the stock's entry
                ; point and not of sequence_mode_init at all.
                ; tone_sequence_mode_enter ($55C5) calls sequence_mode_init
                ; and then, at $55E1-$55F2, dds_mode_param_set ($E69C) with
                ; control id $15 and value 8, which writes ZERO to register
                ; $1B - the same register hop_enable (formats.inc) switches
                ; for the Hop Ram screen's Freq Hop row.
                ; enter_dtmf_sequence_mode ($7A81) ends the same way at
                ; $7AA9-$7ABA, so dtmf_sequence_open carries the same call.
                ldb     #HOP_ON
                lbsr    ABI_hop_enable
                leas    1,s                     ; the reason off
                lbra    tone_show
; ---------------------------------------------------------------------------
; tone_key - the Tone Sequence screen's keys
;
;   entry: B = the key code
;   uses:  A, B, X, Y, U
;
; ENTER IS A TERMINATOR HERE AND NOT A RUN KEY, and this header used to say
; the opposite. NEXT and LAST page the mode's records; the field keys and the
; softkeys select a field; digits go into whichever field is armed; and the
; sequence is started and stopped by the player record's own four softkeys -
; Manual, Continuous, Single and Stop - and by the bus codes RUNC, RUNS, RUNM
; and STOP, which are answered at the head of this routine.
;
; Driven on the instrument, 2026-09-13, to settle it: on the tone settings
; record with nothing armed, ENTER left the stock at 924 DDS words written and
; 924 after six million cycles more, with its screen unchanged - nothing
; started. The same machine's f2 on the player record took it from 928 words
; to 16171 and put '** Running Cont **' on line 1, so the measurement can tell
; a run from no run. See the note at tone_key_enter for the ROM path.
; ---------------------------------------------------------------------------
tone_key
                ; A BUS FIELD SELECT IS THE KEY'S OWN MESSAGE. FRA-FRD, APA-APD
                ; and DAPH/DAPL, WFA-WFD, PHA-PHD and DEA-DED post $19 to $1D
                ; (set_channel_queue_19 $9BEB and its siblings), the same codes
                ; FREQ, AMPTD, WAVE FORM and PHASE post from the panel through
                ; keymap_menu_msgs_19_1d ($AEBB), into the same $508C arms of
                ; sequence_mode_message_handler ($4C01). So each is answered as
                ; its key; $1D has no key here and its arm is the same $3A
                ; refusal as WAVE FORM's. Driven 2026-09-15 on the DTMF Manual
                ; record: 'DAPL;' and 'APA;' leave $23DE = 0 on the instrument
                ; and 'FRA;', 'WFA;', 'PHA;', 'DEA;' leave $3A; this answered
                ; 15 to all six.
                ; AND THE BUS'S AMPTD SELECT ARMS THE FIELD FOR ITS NUMBER.
                ; remote_select clears rmt_pend_kind before it posts $1A, so a
                ; screen that does not name the field leaves the number with
                ; nowhere to go: 'DAPH 999 MV;' on the player record answered
                ; $2F here and set 999 mV on the instrument (seed 5 step 71),
                ; and a bare 'APC 222;' answered $2B where the instrument holds
                ; it (seed 1 step 63). $23 is the unit leg's commit.
                ; THE LOCAL EDGE DESELECTS THE MANUAL FIELD. Measured 2026-09-17
                ; on the Tone Sequence screen: after 'RUNM 250 HZ;' $3D11 reads
                ; $000B, releasing REN alone leaves it $0000, and up then records
                ; $04 where it walked the sequence here (seed 3 step 80). The
                ; request is otherwise unanswered on this page, as key_refuse
                ; says - so it is taken here and nothing is reported.
                cmpb    #KEY_GONE_LOCAL
                bne     tone_key_not_local
                clr     >tone_manual_sel
                rts
tone_key_not_local
                cmpb    #RMT_RQ+$36             ; QRE: arm [53] of d508c is
                lbeq    tone_key_wrong_mode     ; reject_key_error_3a - $3A,
                                                ; where this answered $0F
                cmpb    #RMT_RQ+$21             ; $21: key_save_register
                bne     tone_rq_not_save        ; ($508C) - $505F's close with
tone_rq_save                                    ; $3D11 = $0C rather than 0,
                lbsr    tone_entry_none         ; then $F331 with $0021. $0C
                clr     >tone_manual_sel        ; $3D11 zeroed: not Manual's
                clr     >tone_field             ; is enter_save_register's
                lbra    ABI_save_prompt_open    ; entry-complete arm, which
                                                ; the prompt's own $23 takes
                                                ; first; no tone field is
                                                ; selected by it
tone_rq_not_save
                cmpb    #KEY_ABANDON            ; $3C: key_clear_entry_state
                bne     tone_rq_not_abandon     ; ($505F), arm [59] - the entry
                lbsr    tone_entry_none         ; goes (cancel_pending_entry
                clr     >tone_manual_sel        ; $3D11 zeroed: not Manual's
                clr     >tone_field             ; $47D6) and $3D11 = 0
                rts
tone_rq_not_abandon
                ; FRH AND APH ARE THE FIELD SELECTS WITHOUT THE KEYS' GUARDS.
                ; d508c[39] key_freq_field ($28) and [40] key_amptd_field ($29)
                ; store $3D11 = 1 or 3, cancel the pending entry and arm the
                ; field through [$3C0E] - what freq_key and key_select_amptd do
                ; behind their $3A (DTMF) and $3B (not this record) tests, with
                ; neither test. Measured 2026-09-17, seed 6 step 26: 'APH 251
                ; KZ;' on the DTMF Tone Number record arms a field on the
                ; instrument ($238F 00 -> 01) and KZ is $2E; this armed nothing
                ; and answered $2F.
                cmpb    #RMT_RQ+$29             ; APH
                bne     tone_rq_not_aph
                lda     #TONE_FIELD_AMPL
                lbsr    tone_select_field
                lbra    tone_bus_ampl_arm       ; and the bus's kind with it
tone_rq_not_aph
                cmpb    #RMT_RQ+$28             ; FRH
                bne     tone_rq_not_frh
                lda     #TONE_FIELD_FREQ
                lbsr    tone_select_field
                lbra    tone_bus_freq_arm       ; and the bus's kind with it
tone_rq_not_frh
                cmpb    #RMT_RQ+$19             ; FRA-FRD: freq_key ($4D02),
                bne     tone_rq_not_freq        ; its guards and then the
                ldb     #KEY_FREQ               ; bus's kind
                lbra    tone_bus_freq_select
tone_rq_not_freq
                cmpb    #RMT_RQ+$1A
                bne     tone_rq_not_ampl
                ldb     #KEY_AMPL
                lbra    tone_bus_ampl_select
tone_rq_not_ampl
                cmpb    #RMT_RQ+$23
                bne     tone_rq_not_entry
                lbra    tone_bus_ampl_commit
tone_rq_not_entry
                cmpb    #RMT_RQ+$19
                blo     tone_rq_key_done
                cmpb    #RMT_RQ+$1D
                bhi     tone_rq_key_done
                subb    #RMT_RQ+$19
                pshs    x
                ldx     #tone_rq_keys
                ldb     b,x
                puls    x
tone_rq_key_done
                ; FRH, APH AND PHH ARE THE HOP SELECTS, arms [39] to [41] of
                ; $508C: key_freq_field ($4EED) and key_amptd_field are the
                ; FREQ and AMPTD selects WITHOUT the key's guards - $3D11 = 1
                ; or 3, cancel_pending_entry, [$3C0E] - and PHH is
                ; reject_key_error_3a. This refused all three with $0F.
                cmpb    #RMT_RQ+$28
                bne     tone_rq_aph
                lbsr    tone_entry_none         ; cancel_pending_entry ($47D6)
                lda     #TONE_FIELD_FREQ
                lbra    tone_select_field
tone_rq_aph
                cmpb    #RMT_RQ+$29
                bne     tone_rq_phh
                lbsr    tone_entry_none
                lda     #TONE_FIELD_AMPL
                lbra    tone_select_field
tone_rq_phh
                cmpb    #RMT_RQ+$2A
                lbeq    tone_key_wrong_mode
                ; THE BUS REQUESTS THIS SCREEN ANSWERS. remote.s delivers the
                ; stock's mode-handler request codes as RMT_RQ + code, and the
                ; stock's page-1 dispatch ($508C) answers these ones itself:
                ; arm [44] continuous_key (RUNC $2D), [45] key_single (RUNS
                ; $2E), [46] key_manual (RUNM $2F), [47] stop_key (STOP $30),
                ; [48] on_time_key (STON/SBP $31), [49] key_select_off_time
                ; (STOF $32), [50] key_seq_index (SEQP $33), [51] key_seq_end
                ; (SEQE $34) and [36] halt_and_report_field ('?' $25). Each
                ; is the same routine the softkey reaches, entered with the
                ; state check the key path already makes.
                ;
                ; RUNC AND RUNS CHECK NOTHING, because the stock's arms check
                ; nothing. continuous_key ($4F4D) and key_single ($4F98) are
                ; thirteen bytes each - the frame, one call to
                ; softkey_continuous_run ($4A19) or softkey_single_sequence
                ; ($4AA2), and out - and both of those stop a running timer and
                ; start again from the top. Driven on both firmwares 2026-09-14
                ; in DTMF Sequence: a second RUNC moved the stock's position
                ; from 64 back to 6 twelve thousand instructions later and left
                ; this firmware's going on from 68 to 82, because these arms ran
                ; tone_start only from TONE_STOPPED and called a repeat "not an
                ; error". A controller that restarts a sequence heard it restart
                ; on the instrument and not here.
tone_rq_seq_arms
                ; THE SHARED PAGE-1 SEQUENCE ARMS BEGIN HERE, and page1_dtmf.s
                ; delegates to THIS label rather than to anything above it.
                ; One handler serves both records - sequence_mode_init ($5629)
                ; installs $220F = sequence_mode_message_handler ($4C01) for
                ; tone_sequence_mode_enter ($55C5) and enter_dtmf_sequence_mode
                ; ($7A81) alike - so RUNC, RUNS, RUNM, STOP, STON, STOF, SEQP
                ; and SEQE are answered on the DTMF record by these same arms.
                ;
                ; THE ARMS ABOVE THIS POINT ARE NOT SHARABLE AS THEY STAND.
                ; $27 (tone number), $28 (FRH), $29 (APH) and $2A (PHH) act on
                ; tone-screen state, and this firmware splits page 1 into two
                ; modules where the instrument has one. Entering the chain at
                ; tone_rq_aph sent every DTMF bus request through the APH
                ; select on the way past: measured, seed 47 step 38 moved
                ; channel 0 from 13360 - which matched the instrument - to
                ; 14770, which does not. Whether those four can be delegated
                ; too is a separate question about what tone_select_field does
                ; to a screen that is not showing.
                cmpb    #RMT_RQ+$2D
                bne     tone_rq_single
                clr     >tone_single            ; RUNC: $4A27 CLR >$3C81
                lbsr    tone_start
                lbra    tone_show
tone_rq_single
                cmpb    #RMT_RQ+$2E
                bne     tone_rq_manual
                lda     #$01                    ; RUNS: $4A6A STB >$3C81
                sta     >tone_single
                lbsr    tone_start
                lbra    tone_show
tone_rq_manual
                cmpb    #RMT_RQ+$2F             ; RUNM: manual stepping, the
                lbne    tone_rq_stop            ; page-2 f1 path
                lbsr    tone_key_page2_f1
                ; AND THE SEQ INDEX FIELD IS ARMED FOR A NUMBER. key_manual
                ; ($4F5A) ends in seq_enter_manual_mode ($49C0), $3D11 = $0B,
                ; and [$3C0E](4) - the Seq Index entry, which while remote is
                ; begin_numeric_entry ($A415) and sets $238F. So 'RUNM 1 VL;'
                ; gives the number a field and leaves $23DE = 0 on the
                ; instrument (driven 2026-09-15); with nothing armed this
                ; answered $2F. The field is SEQP's.
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
                lda     #TONE_FIELD_SEQIDX
                lbsr    tone_rq_seq_own
                lda     #$01                    ; and $3D11 stays $0B: 'RUNM
                sta     >tone_manual_sel        ; 250 HZ;' leaves $000B on the
                rts                             ; instrument (measured)
tone_rq_stop
                cmpb    #RMT_RQ+$30
                bne     tone_rq_on
                ; $3D11 IS THE FIELD ID, and that IS now established: the page
                ; stores 7 there for the tone number (softkey_tone_number),
                ; $0B for the Manual field (seq_enter_manual_mode; this said
                ; Seq Index, and measured 2026-09-17 f1 on the Seq Index
                ; record leaves 8, as apply_seq_entry_manual's forced 8 is), 8
                ; for Seq Index and the data cursor
                ; (step_seq_index_manual) and 0 to let go. tone_incr_mode is a
                ; separate flag; reading the stock's CLR >$3D11 as that one is
                ; why a run left the cursor selected. Driven, seed 15: with it
                ; cleared here and in tone_start, the seed goes from seven
                ; divergences to none.
                clr     >tone_incr_mode         ; STOP: stop_key ($4FA5) is
                clr     >tone_manual_sel        ; $3D11 zeroed: not Manual's
                clr     >tone_field             ; softkey_stop ($4AB9), which
                clr     >dtmf_field             ; clears $3D11 and calls $4881
                lbsr    tone_output_stop
                lbra    tone_show
tone_rq_on
                cmpb    #RMT_RQ+$31             ; STON and SBP: the on-time
                bne     tone_rq_off             ; field
                lda     #TONE_FIELD_ON
                bra     tone_rq_time_own
tone_rq_off
                cmpb    #RMT_RQ+$32             ; STOF: the off-time field
                bne     tone_rq_seqp
                lda     #TONE_FIELD_OFF
tone_rq_time_own
                ; AND THE NUMBER THAT FOLLOWS IS THIS TIME'S. The stock arms
                ; the field and the bus number lands in it; only a unit
                ; mnemonic ends it, and only seconds or milliseconds are
                ; legal there. Driven on the stock 2026-09-11: 'STON 5 MS;'
                ; is 5.00 ms, 'STON 5;' alone stores nothing and says nothing,
                ; 'STON 5 HZ;' is error $2E, 'STON 2 SC;' is $32 and leaves
                ; the field reading in seconds, and 'STON 0.5 MS;' is $32 for
                ; the 80-count floor.
                pshs    a
                lda     >rmt_flags              ; an arm empties the entry
                anda    #~RF_HELD&$FF           ; ($A415): no number held
                sta     >rmt_flags              ; from before it survives
                lda     #0                      ; and has a field cursor
                sta     >rmt_field_gone         ; again (LDA leaves carry)
                lda     #RK_TIME
                sta     >rmt_pend_kind
                lda     #$01                    ; owner 1 = the tone screen
                sta     >rmt_seq_owner
                puls    a
                lbra    tone_select_field
tone_rq_seqp
                cmpb    #RMT_RQ+$33             ; SEQP: the next number is a
                bne     tone_rq_seqe            ; position in THIS sequence
                lda     >rmt_flags              ; an arm empties the entry
                anda    #~RF_HELD&$FF           ; ($A415): no number held
                sta     >rmt_flags              ; from before it survives
                lda     #0                      ; and has a field cursor
                sta     >rmt_field_gone         ; again (LDA leaves carry)
                lda     #RK_SEQPOS
                sta     >rmt_pend_kind
                lda     #TONE_FIELD_SEQIDX
                bra     tone_rq_seq_own
tone_rq_seqe
                cmpb    #RMT_RQ+$34             ; SEQE: ...or its end
                lbne    tone_rq_seqdata
                lda     >rmt_flags              ; an arm empties the entry
                anda    #~RF_HELD&$FF           ; ($A415): no number held
                sta     >rmt_flags              ; from before it survives
                lda     #0                      ; and has a field cursor
                sta     >rmt_field_gone         ; again (LDA leaves carry)
                lda     #RK_SEQEND
                sta     >rmt_pend_kind
                lda     #TONE_FIELD_SEQEND
tone_rq_seq_own
                ; AND THE FIELD IS SELECTED, which this did not do. The stock's
                ; SEQP and SEQE are field selectors and nothing else -
                ; cmd_seqp_post_33 ($9C5E) posts $33 to softkey_select_seq_index
                ; ($5B24), which writes the field id AND aims the pointer, and
                ; $9C64 posts $34 to softkey_select_seq_end ($5B4E) - so after
                ; either one the screen's own cursor is on that number and a
                ; '?' reports it. Here only rmt_pend_kind was written, so the
                ; field stayed wherever it was and 'SEQE 250; ?;' answered with
                ; the frequency or the level of whatever row was selected. The
                ; digital screen's own handler has always done this
                ; (page2_digital.s:digital_rq_seq_own); the tone screen's did
                ; not.
                pshs    a                       ; the field, over the owner
                lda     #$01                    ; owner 1 = the tone screen
                sta     >rmt_seq_owner
                puls    a
                lbra    tone_select_field
; THE EARLIER, TONE-ONLY WSQ ARM WAS HERE. Two parallel ports wrote this: one gave
; the tone sequence editor its own stream handler, the other found the stock
; has ONE handler for the whole page-1 mode - $508C is the message table of
; sequence_mode_message_handler ($4C01), so the tone sequence, the DTMF
; sequence, the player and Manual Dial are all served by
; gpib_sequence_char_in ($7870). The general arm further down supersedes this
; one, and the assembler found the pair as a multiply-defined tone_rq_wsq
; when the branches met. The SEQE arm above now falls to the next arm in the
; chain rather than branching over it.
tone_rq_seqdata
                ; ONE CHARACTER OF THAT STREAM. remote.s has already folded
                ; '*' and '#' onto E and F, refused everything that is not a
                ; hex digit, and delivered the value as RMT_RQ + $60 + value -
                ; the same shape the dial screen's characters arrive in.
                cmpb    #RMT_RQ+$60
                blo     tone_rq_query
                cmpb    #RMT_RQ+$6F
                bhi     tone_rq_query
                subb    #RMT_RQ+$60             ; B = the tone number, 0 to 15
                lbsr    tone_stream_put
                rts                             ; AND NO REPAINT. The stock
                                                ; draws the one cell it wrote
                                                ; and nothing else ($78E5-
                                                ; $794F); a repaint here would
                                                ; rewrite both lines for every
                                                ; character of a 250-character
                                                ; sequence
                ; (the two copy-time codes are answered below, after HRA)
tone_rq_query
                cmpb    #RMT_RQ+$25             ; '?': halt_and_report_field
                bne     tone_rq_hra             ; ($4EA8) tests $3C80 and
                lda     >tone_state             ; stops the run before it
                cmpa    #TONE_RUNNING           ; reports; so does this
                bne     tone_rq_report
                lbsr    tone_output_stop        ; $4881, as $4EA8 calls it
tone_rq_report
                lbra    tone_query
tone_rq_hra
                cmpb    #RMT_RQ+$27             ; HRA: the stock's arm [38]
                bne     tone_rq_copy_on         ; key_select_tone_number
                ; AND THE NUMBER THAT FOLLOWS IS THIS FIELD'S. softkey_tone_
                ; number arms the field through $3C0E, and with the remote bit
                ; set that is $45D3's three-digit geometry, so the bus number
                ; lands in it - and only a UNIT mnemonic terminates it. Driven
                ; on the stock 2026-09-11: 'HRA 5;' leaves $3D1B alone with no
                ; error, 'HRA 7 HZ;' selects tone 7, '9 KZ;' after it selects
                ; 9 with no second HRA, and 'HRA 20 HZ;' is error $36 with the
                ; tone unchanged. RK_TONE tells remote.s all of that.
                lda     >rmt_flags              ; an arm empties the entry
                anda    #~RF_HELD&$FF           ; ($A415): no number held
                sta     >rmt_flags              ; from before it survives
                lda     #0                      ; and has a field cursor
                sta     >rmt_field_gone         ; again (LDA leaves carry)
                lda     #RK_TONE
                sta     >rmt_pend_kind
                lda     #$01                    ; owner 1 = the tone screen
                sta     >rmt_seq_owner
                lda     #TONE_FIELD_TONE        ; ($4EE0) calls
                lbra    tone_select_field       ; softkey_tone_number ($47FA),
                                                ; which sets field id $0007 -
                                                ; the TONE NUMBER. It selected
                                                ; the frequency here while a
                                                ; step had no tone number to
                                                ; select, and now it has one
                ; THE TWO COPY-TIME CODES, each carrying ONE of the times.
                ; copy_time_to_all_tones ($4AED) reads $2217 itself: for $37 it
                ; sets source $3C10 and companion $3C12 and for anything else
                ; the other way round, then walks the sixteen records. Arms
                ; [54] and [55] of $508C reach it, and they refuse off the
                ; settings record - $3C8F must be 1 - by storing $3B, which is
                ; 'Commmand not available in present window'.
                ;
                ; NO KEY DOES THIS. Driven on the stock 2026-09-11: with the On
                ; Time set to 50 ms on tone 0, f1, f3 and f4 leave all sixteen
                ; records exactly as they were. This firmware had it on a
                ; softkey, copying BOTH times at once, and nothing on the
                ; instrument does that.
tone_rq_copy_on
                cmpb    #RMT_RQ+$37
                bne     tone_rq_copy_off
                clra                            ; 0 = the On time is the source
                bra     tone_rq_copy
tone_rq_copy_off
                cmpb    #RMT_RQ+$38
                bne     tone_rq_wsq
                lda     #$01                    ; 1 = the Off time
tone_rq_copy
                lbra    tone_copy_time_to_all

tone_rq_wsq
                ; WSQ: THE SEQUENCE ITSELF, ARRIVING AS CHARACTERS. Arm [43]
                ; of $508C is streamed_entry_key ($5048), and $508C is the
                ; message table of the WHOLE page-1 mode - so the instrument
                ; answers WSQ on the settings record, the sequence editor, the
                ; player and the Manual Dial screen alike, storing each
                ; character into the shared playlist. THIS ARM DID NOT EXIST:
                ; only page1_dtmf.s had one, and it dialled rather than
                ; stored, so on every tone and DTMF sequence record the
                ; command was refused with $30. Measured against the stock,
                ; 2026-09-13, on the sequence editor with 'WSQ 12AB;': the
                ; instrument's playlist read 1 2 10 11 and its window
                ; '[12AB456789ABCDEF]', and this firmware's read 0 1 2 3 with
                ; last_error $30.
                cmpb    #RMT_RQ+$2C
                bne     tone_key_hexfield
                lbsr    page1_stream_open       ; $79C3
                lda     #$01                    ; owner 1 = a sequence record
                sta     >rmt_seq_owner
                lbra    tone_show

                ; --- THE TITLE RECORD HAS NO FIELDS ON IT ------------------
                ; and the instrument keeps them off it with the field keys
                ; themselves, not with a guard over the whole record. Each of
                ; the three refuses on its own:
                ;
                ;   FREQ  ($4D02) LDB >$3C8F / CMPB #$01 / LBNE $4D37 -> $3B
                ;   AMPTD ($4D47) LDB >$3C8F / CMPB #$03 / LBNE $4D73 -> $3B
                ;   PHASE         d508c[27] at $50C2 is reject_key_error_3a
                ;                 ($5071), which stores $3A on every record
                ;
                ; and a digit with no field armed reaches $B494 in
                ; numeric_entry_key_handler ($B3C2), reads $23A8 clear and
                ; calls error_report_beep ($C3FE) with 1 at $B4A8 - no digit
                ; taken, no buffer touched, no message posted. Those two are
                ; tone_key_freq, tone_key_phase, tone_key_ampl and the
                ; entry_armed test further down; between them the banner is
                ; safe without refusing keys the instrument answers.
                ;
                ; THIS FIRMWARE ARMED THE FIELD AND PAINTED THE VALUE ACROSS
                ; THE MODE'S OWN BANNER. tone_field is zero at a fresh entry
                ; and zero IS TONE_FIELD_FREQ, so FREQ was selected on a record
                ; that has no FREQ cell and the eight echo columns at $19 sat
                ; on top of '** Tone Sequence Mode **'. Measured against the
                ; stock 2026-09-13: opening the mode and keying FREQ 1 kHz
                ; leaves the instrument's banner untouched and left this
                ; firmware showing '** Tone Sequence 1000 **'.
                ;
                ; A BLANKET GUARD OVER RECORD 0 WAS TRIED HERE AND IS WRONG,
                ; which is worth writing down because page0_screen.s's chan_key
                ; carries one for the Channel Configuration title. It answered
                ; the AMPTD key with $0F, 'Un-executable command', where $4D73
                ; answers $3B - test_sequences checks that very code - and it
                ; refused the arrows, which this mode's own gate uses from the
                ; title record to step tone 0's frequency by its increment.
                ;
                ; THE BUS IS NOT AFFECTED BY ANY OF IT: every RMT_RQ code is
                ; answered above this line, and the stock's own bus arms
                ; key_freq_field ($4EED) and key_amptd_field ($4F2A) carry no
                ; record test either.

tone_key_hexfield
                ; BUT NOT BEFORE THE ARMED-ENTRY GATE. numeric_entry_key_handler
                ; ($B3C2) reaches $B494 - LDB >$23A8 / CMPB #$00 / LBNE $B4B0 -
                ; BEFORE it reaches keypad_char_column_select at $B502, so a
                ; hex character with no entry armed takes the fall-through at
                ; $B49D: error_report_beep ($C3FE) and return, with the field
                ; id left alone and nothing written. The hex column is "first"
                ; only among the MEANINGS of a key, not ahead of that gate.
                ;
                ; It shows on the WSQ path, which is the one place this screen
                ; selects the data cursor WITHOUT arming an entry:
                ; start_streamed_digit_entry ($79C3) writes $3D11 = 9 and never
                ; calls arm_seq_edit_cursor ($7132), and remote.s clears
                ; entry_armed at the remote-to-local edge. Driven by the
                ; differential harness, seed 16 step 25: after 'WSQ 10 HZ;' the
                ; stock takes a keyed '0' and does nothing at all, leaving
                ; ' Seq Index     1  [1023456789ABCDEF]'; without this test the
                ; digit went into step 0 and moved the cursor, leaving
                ; ' Seq Index     2  [0023456789ABCDEF]'.
                lbsr    ABI_entry_is_open       ; $B494. Unarmed: on down the
                lbeq    tone_rq_refresh         ; chain to tone_key_entry, whose
                                                ; own $23A8 test refuses it
                ; THE TWO SINGLE-CHARACTER FIELDS, AND THEY TAKE THE KEY
                ; FIRST. The tone number and the sequence data cursor are
                ; entry mode 1 - column 5 of keypad_char_table ($EF94), which
                ; is the HEX column: the ten digits and then kHz, Hz, deg,
                ; ENTER, minus and point as A, B, C, D, E and F.
                ; tone_number_entry_field_geometry ($45D3) arms ONE character
                ; at column $0F for the tone number and arm_seq_edit_cursor
                ; ($7132) one at $15 + $3D3B for the cursor, and
                ; enter_tone_number ($640C) and enter_sequence_field ($7649)
                ; both convert what was keyed with parse_hex_digit_pair
                ; ($CC53). A character COMMITS ITSELF: the field is one wide,
                ; so the keystroke fills it and the entry ends on the spot.
                ;
                ; IT MUST COME BEFORE EVERY OTHER MEANING THESE KEYS HAVE.
                ; keypad_char_column_select ($AF29) runs ahead of
                ; check_entry_terminator ($B070) and accept_units_key ($B0C1)
                ; inside numeric_entry_key_handler ($B3C2), so with one of
                ; these fields selected ENTER is the letter D and not a
                ; terminator, and kHz, Hz and deg are A, B and C and not unit
                ; keys.
                ;
                ; Driven on the stock 2026-09-11, on the DTMF settings record
                ; with f1 pressed: kHz leaves ' Tone Number A' and $3D1B = 10,
                ; deg 'C' and 12, ENTER 'D' and 13, minus '*' and 14, point
                ; '#' and 15, and every digit lands with no ENTER behind it.
                ; This firmware typed into a decimal buffer that ENTER
                ; committed, so six of the sixteen tones could not be named
                ; from the panel at all and ENTER ran the sequence instead.
                lda     >tone_field
                cmpa    #TONE_FIELD_SEQDATA     ; THE CURSOR IS HEX WHOEVER IS
                beq     tone_key_hex_try        ; DRIVING: enter_sequence_field
                                                ; ($7649) arm 9 converts with
                                                ; parse_hex_digit_pair and has
                                                ; no second path
                cmpa    #TONE_FIELD_TONE
                bne     tone_rq_refresh

                ; THE TONE NUMBER HAS A SECOND GEOMETRY, and the bus is what
                ; reaches it. $45D3 arms THREE DECIMAL digits at the same
                ; column when bit 3 of event_flags ($2204) is set - the remote
                ; state, in which numeric_entry_key_handler ($B3C2) ignores
                ; every panel key but LOCAL - and enter_tone_number ($640C)
                ; then takes the entry_to_scaled_digits path and refuses $10
                ; and above with error $36. RF_REMOTE is that bit here, so a
                ; bus number goes on down the chain to the digit arm and the
                ; commit, and only the panel types hex.
                lda     >rmt_flags
                bita    #RF_REMOTE
                bne     tone_rq_refresh
tone_key_hex_try
                lbsr    ABI_key_hex_digit       ; B is left as it was when the
                bcs     tone_rq_refresh         ; key is not one of the sixteen
                ; A TAKEN CHARACTER ENDS THE ENTRY BEFORE IT IS STORED. Both
                ; one-character fields arm with units class 0 -
                ; tone_number_entry_field_geometry ($45D3) and
                ; arm_seq_edit_cursor ($7132) - and for class 0
                ; check_entry_terminator ($B070) answers 1 on every accepted
                ; key: $B586 turns the cursor off and $B594 posts $23, whose
                ; arm stores the character and re-arms (enter_tone_number
                ; $640C, enter_sequence_field $7649). The re-arm is the
                ; tone_show_armed each store below ends in. B survives.
                lbsr    ABI_entry_cursor_off    ; $B586
                lda     >tone_field
                cmpa    #TONE_FIELD_SEQDATA
                lbeq    tone_key_data_put       ; B = the nibble; the step
                                                ; under the cursor takes it
                stb     >tone_number            ; 0 to 15, and every value the
                                                ; column can produce is a tone
                lbsr    tone_entry_reset        ; AND THE FIELD STAYS ARMED, as
                                                ; enter_tone_number's tail
                                                ; re-arms field type 3 through
                                                ; $3C0E - the stock takes 3
                                                ; then 7 as two tones, not as
                                                ; one number 37
                lbra    tone_show_armed

tone_rq_refresh
                ; A REPAINT, AND NOTHING ELSE. KEY_REFRESH is the foreground's
                ; own "paint yourself again" code; remote.s posts it after a
                ; bus command and, at the remote/local edge, AFTER it has
                ; cleared entry_armed and entry_count on purpose - "the
                ; operator's half-typed value is not the controller's to
                ; commit". Arming the field here put that arm straight back.
                ;
                ; Driven on both, 2026-09-13, on the DTMF Sequence player
                ; record with the level committed and nothing typed: asserting
                ; REN leaves the stock's $23A8 at 0 and left this firmware's
                ; entry_armed at 1, so the next digit echoed '7' over
                ; 'AMPTD    100 uV' where the instrument ignores it - $B494
                ; reads $23A8 clear and calls error_report_beep. The
                ; differential harness reported it as seed 21, step 6.
                ;
                ; The bus's own field selects do not come through here: SEQP,
                ; SEQE, STON, STOF and HRA each call tone_select_field above,
                ; which arms the field it selects.
                cmpb    #KEY_REFRESH
                bne     tone_key_enter
                lbra    tone_show
tone_key_enter
                cmpb    #KEY_ENTER
                bne     tone_key_next

                ; AND IT NEEDS A FIELD ARMED UNDER IT, exactly as the digits
                ; and the unit keys below do. ENTER is a TERMINATOR: it reaches
                ; accept_units_key ($B0C1) at $B5A5 and posts message $23 at
                ; $B5C8, and both of those sit behind $B494's gate - LDB
                ; >$23A8 / CMPB #$00 - whose fall-through at $B49D-$B4AD calls
                ; error_report_beep ($C3FE) with 1 and returns with no message
                ; posted at all. page0_screen.s's chan_key_terminator carries
                ; the same test, on the same citation.
                ;
                ; SO AN UNARMED ENTER DOES NOT START THE SEQUENCE, and this
                ; firmware's did. The run keys are the output record's own
                ; softkeys - $416B record 3 is softkey_seq_output,
                ; softkey_continuous_run, softkey_single_sequence and
                ; softkey_stop - and nothing else on this screen starts a run.
                ;
                ; It was visible as a WRONG TONE PAIR, which is worth writing
                ; down because that is not what it is. Driven on both,
                ; 2026-09-13, on the DTMF title record with nothing armed: the
                ; pair reads 13360 and 9410 tenths on each, then ENTER leaves
                ; the instrument exactly there and left this firmware at 12090
                ; and 9410 and then 16330 and 8520 - the player walking the
                ; playlist, sampled twice. The differential harness reported it
                ; as seeds 15 and 18 disagreeing on the column tone.
                lbsr    ABI_entry_is_open
                lbeq    tone_key_ignore

                ; ENTER IS NOT A TERMINATOR ON EVERY FIELD. $B070 returns zero
                ; for classes 4, 5 and 6, so on FREQ, on the two times and on
                ; the level the instrument beeps at $B5D0 instead of
                ; committing. Only Seq Index and Seq End - class 2, the stock's
                ; $B0CD - take it. This screen used to commit every field on
                ; ENTER and refuse all three unit keys.
                ;
                ; AND ON THE TWO HEX FIELDS ENTER NEVER GETS HERE: it is the
                ; letter D, taken by tone_key_hexfield above. While remote the
                ; panel is locked (boot.s), and the bus ends a tone number
                ; with a unit mnemonic, in remote.s's remote_set_tone.

                ; DIGITS TYPED? THEN ENTER COMMITS THEM, to whichever field
                ; the softkeys selected. That is the stock's model: its
                ; sequence screens SELECT a field ($3C8F, moved by
                ; key_freq_field, key_amptd_field and key_select_off_time) and
                ; commit to whichever is selected. The softkeys here used to
                ; commit directly, which works with three fields and three
                ; keys but leaves INCR SET and the arrows nothing to act on.
                ;
                ; AND WITH NOTHING TYPED IT IS STILL THE FIELD'S ENTER, not a
                ; run key - the two arms below differ only in what an armed
                ; field with an empty buffer does with INCR SET, and neither
                ; of them starts anything. Driven on the instrument
                ; 2026-09-13: ENTER on the tone settings record with nothing
                ; armed left the DDS word count at 924 across six million
                ; cycles and the screen unchanged, where f2 on the player
                ; record took the same machine from 928 words to 16171 and
                ; painted '** Running Cont **'. An earlier reading of this
                ; screen had ENTER as the run key and said so in three places;
                ; that is what the measurement settles.
                tst     >entry_active
                beq     tone_key_enter_empty
                lbsr    tone_field_class_get
                cmpa    #TONE_CLASS_ENTER
                lbeq    tone_key_commit
                cmpa    #TONE_CLASS_NONE
                lbeq    tone_key_commit
                lbra    tone_key_ignore
tone_key_enter_empty
                tst     >tone_incr_mode         ; ENTER with nothing typed
                beq     tone_key_enter_none     ; while INCR SET is armed
                clr     >tone_incr_mode         ; CANCELS it - falling through
                lbsr    tone_entry_reset        ; here started the sequence
                lbra    tone_show               ; with the increment still on
                                                ; the screen, and left the
                                                ; next ENTER committing to a
                                                ; field the operator thought
                                                ; they had left. THE RESET
                                                ; ONLY, NOT AN ARM: ENTER on
                                                ; classes 4-6 is no terminator
                                                ; ($B0C1 answers 0, $B5D0
                                                ; beeps), so no $23 is posted
                                                ; and no cursor byte is sent
tone_key_enter_none
                ; AND AN ARMED FIELD WITH NOTHING TYPED IS STILL THE FIELD'S
                ; ENTER, not the sequence's. This ran the sequence, and the
                ; instrument has no such key: ENTER reaches accept_units_key
                ; ($B0C1) like the three unit keys, check_entry_terminator
                ; ($B070) answers zero for classes 4, 5 and 6 - the frequency,
                ; the two times and the level - so $B5D0 beeps, and only the
                ; class-2 fields Seq Index and Seq End take it and commit.
                ; Nothing on that path looks at $3C80 or starts a timer.
                ;
                ; THE RUN KEYS ARE THE OUTPUT RECORD'S SOFTKEYS, which is what
                ; record 3 of $416B says they are: softkey_seq_output,
                ; softkey_continuous_run ($4A19), softkey_single_sequence and
                ; softkey_stop ($4AB9). The bus reaches the same four through
                ; RUNC, RUNS, RUNM and STOP, answered at the head of this
                ; routine. Neither needed the arm that stood here and both
                ; still work without it, so it is gone rather than left
                ; unreachable.
                ;
                ; It cost a wrong tone pair, which is not what it looks like
                ; from outside: with a field armed by a bus command and no
                ; digits behind it, ENTER on the DTMF title record started the
                ; player, and the pair then read whatever step the player had
                ; walked to. Driven on both, 2026-09-13: the instrument stays
                ; at 13360 and 9410 tenths and this firmware moved to 12090 and
                ; 9410, then to 16330 and 8520. The differential harness
                ; reported it as seeds 15 and 18 disagreeing on the column tone.
                lbsr    tone_field_class_get
                cmpa    #TONE_CLASS_ENTER       ; $B0CD's class 2: Seq Index
                lbeq    tone_key_commit         ; and Seq End
                cmpa    #TONE_CLASS_NONE
                lbeq    tone_key_commit
                lbra    tone_key_ignore         ; $B5D0's beep
tone_key_next
                ; WHAT NEXT AND LAST MOVE DEPENDS ON THE SCREEN, as it does on
                ; the instrument: on the tone editor they step the TONE, on
                ; the sequence editor the CURSOR. They stepped a step number
                ; when a step carried its own settings, and a step has no
                ; settings to walk to any more.
                ; NEXT AND LAST PAGE THE RECORDS, on every one of them.
                ; Arms [22] and [23] of the $508C dispatch - the codes $17 and
                ; $18 that key20_post_event23 ($ADBA) and key_event_0018
                ; ($ADC2) post - are BOTH menu_page_key ($4C87), which cancels
                ; the pending entry, calls A2U12's $8A2F to step $268E against
                ; the record count, zeroes the field id $3D11 and calls
                ; enter_menu_page ($4689). Neither key touches the tone number,
                ; the cursor, the window origin or the insert flag.
                ;
                ; THE TONE NUMBER IS STEPPED BY THE ARROWS, once f1 has
                ; selected it: step_tone_number ($6879) is the $697F table's
                ; arm for $3D11 = 7. This had NEXT and LAST stepping the tone
                ; on three of the four records and paging only on the fourth,
                ; so the records after it were unreachable.
                cmpb    #KEY_NEXT
                bne     tone_key_last
                lda     >tone_page
                inca
                cmpa    #TONE_PAGES
                blo     tone_key_page_store
                clra
                bra     tone_key_page_store
tone_key_next_cursor
                ; ONE STEP UP, CLAMPED - the stock does not wrap. The arrow
                ; reaches step_seq_field ($744B) with $3D11 = 9, whose l7460
                ; arm does LDD $3D0D / ADDD #$0001 / STD $3D0D at $7485 and is
                ; blocked at $00F9 and blocked when $3D0D would pass Seq End
                ; ($3D0F), the guard at $7473. It wrapped here, which put the
                ; cursor on steps that do not play.
                ldd     >tone_cursor
                cmpd    >tone_end               ; at Seq End already: hold
                bhs     tone_key_cursor_hold
                cmpd    #TONE_PLAYLIST-1        ; and never past $00F9
                bhs     tone_key_cursor_hold
                addd    #1
                bra     tone_key_cursor_store
tone_key_cursor_hold
                lbsr    tone_show               ; AND STILL RE-ARMED: every
                lbra    tone_field_arm          ; path of step_seq_field
                                                ; ($744B) for $3D11 = 9 ends
                                                ; in arm_seq_edit_cursor at
                                                ; $752B, the cursor moved or
                                                ; held at an end
tone_key_last                                   ; press a key that does
                cmpb    #KEY_LAST               ; nothing
                bne     tone_key_f1
                lda     >tone_page
                bne     tone_key_page_back
                lda     #TONE_PAGES
tone_key_page_back
                deca
tone_key_page_store
                ; AND THE SEQUENCE EDITOR IS LEFT, on every record. The
                ; repaint hook repaint_hook_leave_editor ($5185), which
                ; sequence_mode_init ($5380) installs in $2211, calls
                ; exit_sequence_edit ($7160) for every posted code EXCEPT $15
                ; and $16 (f3 Delete, f4 Insert), $20 and $1F (the two
                ; arrows), $23 (ENTER) and $26 - and $17 and $18, the two
                ; codes these keys post, are not in that list. So the editor
                ; is torn down before the paging arm even runs:
                ; exit_sequence_edit clears the edit flag with CLR $3D35 at
                ; $716F, clears the insert flag $3D3E, and snaps the index to
                ; the top of the window with LDD $3D39 / STD $3D0D at $7175.
                ;
                ; ONLY IF AN EDIT WAS OPEN, and then it SOUNDS the step. $7166
                ; is LDB >$3D35 / CMPB #$00 / LBEQ out: with the edit flag clear
                ; exit_sequence_edit touches nothing, and with it set it goes on
                ; past the snap to tone_at_cursor ($6D66) and output_tone
                ; ($6A95) for the step the index has snapped to. This snapped
                ; the index on every record change and sounded nothing. Driven
                ; on both firmwares 2026-09-14 in DTMF Sequence, the index
                ; poked to step 5 (0-based) on the tone record with no edit
                ; open, NEXT to the player record and f2: the stock's run start
                ; programmed step 5's pair and this firmware's step 0's.
                sta     >tone_page
                sta     >active_record          ; $268E, which a save and a
                                                ; power-off carry
                clr     >tone_manual_sel        ; $3D11 zeroed: not Manual's
                clr     >tone_field             ; $3D11 = 0, as $4C87 does
                tst     >tone_edit              ; $7166: LDB >$3D35 / LBEQ
                beq     tone_key_page_left
                clr     >tone_edit              ; $716F: CLR $3D35
                clr     >tone_insert            ; $7172: CLR $3D3E
                ldd     >tone_window            ; $7175: the index snaps to
                std     >tone_cursor            ; the top of the window
                lbsr    tone_sound_at_cursor    ; $717B-$7195: and is heard
tone_key_page_left
                ; AND A RECORD CHANGE LEAVES NOTHING ARMED. NEXT and LAST are
                ; STATE keys, and numeric_entry_key_handler ($B3C2) calls
                ; entry_exit_restore_display ($B38B) with 1 at $B45C for a
                ; state key before the message is even posted, so $23A8 is
                ; clear by the time menu_page_key ($4C87) runs - and $4C87
                ; itself only zeroes the field id at $4C9D and calls
                ; cancel_pending_entry ($47D6). Nothing on that path re-arms.
                ;
                ; THIS CALLED the page's arm routine, and the field it
                ; armed was tone_field - just cleared to zero, which is
                ; TONE_FIELD_FREQ. So after every NEXT this screen had the
                ; frequency field live on whatever record it had landed on, and
                ; a digit typed there echoed into the FREQ columns at $19:
                ; across the sequence window on the editor record and across
                ; the mode's banner on the title. Measured against the stock
                ; 2026-09-13: NEXT then '1 0 0 0' leaves the instrument's
                ; window reading [0123456789ABCDEF] and left this one reading
                ; [01231000    CDEF].
                lbsr    tone_entry_none         ; $B45C, and $47D6 with it
                lbra    tone_show
tone_key_last_cursor
                ; ONE STEP DOWN, FLOORED AT ZERO. l7492 does LDD $3D0D /
                ; SUBD #$0001 at $74A2 and will not go below zero; this wrapped
                ; to the top of the buffer instead.
                ldd     >tone_cursor
                beq     tone_key_cursor_hold
                subd    #1
tone_key_cursor_store
                std     >tone_cursor
                clr     >tone_insert            ; a move cancels a pending gap
                lbsr    tone_sound_at_cursor    ; and the step it lands on is
                                                ; heard, as the stock's is
tone_key_moved
                lda     >tone_field             ; MOVING TO ANOTHER STEP PUTS
                cmpa    #TONE_FIELD_AMPL        ; THE STEP ROW BACK. The level
                bne     tone_key_position_armed ; is a channel setting and
                clra                            ; does not change with the
                clr     >tone_manual_sel
                sta     >tone_field             ; step, so stepping while its
tone_key_position_armed                         ; row was up moved a cursor
                lbsr    tone_entry_reset        ; the operator could not see
                lbra    tone_show_armed

; --- filling a step --------------------------------------------------------
; f1 takes the typed value as this step's FREQUENCY, f2 as its DURATION.
; Nothing could write either before: the header promised "digits go into the
; entry being edited" and there was no digit path in the file at all.
; --- THE SIXTEEN SOFTKEY ARMS, four to a record ----------------------------
; Each record's four handler words, from the table at $416B:
;
;   record 0  $C239, $C239, $C239, post_request_0b            (the Exit)
;   record 1  softkey_tone_number, softkey_on_time,
;             softkey_manual_dial, softkey_off_time
;   record 2  softkey_seq_index, key_select_seq_end,
;             softkey_delete_step, softkey_edit_sequence_insert
;   record 3  softkey_seq_output, softkey_continuous_run,
;             softkey_single_sequence, softkey_stop
;
; This firmware had f4 PAGING the softkeys and the other three meaning
; different things on each of its own pages, with the run keys spread over two
; of them. NEXT and LAST page the records now, as menu_page_key ($4C87) does,
; so all four keys are free for the arms the record names.
tone_key_f1
                cmpb    #KEY_F1
                bne     tone_key_f2
                clra
                bra     tone_softkey
tone_key_f2
                cmpb    #KEY_F2
                bne     tone_key_f3_sk
                lda     #1
                bra     tone_softkey
tone_key_f3_sk
                cmpb    #KEY_F3
                bne     tone_key_f4_sk
                lda     #2
                bra     tone_softkey
tone_key_f4_sk
                cmpb    #KEY_F4
                lbne    tone_key_f3
                lda     #3
tone_softkey
                pshs    a                       ; which key
                lda     >tone_page
                ldb     #4
                mul                             ; D = record * 4
                addb    ,s+
                adca    #0
                aslb                            ; two bytes an entry
                rola
                ldx     #tone_softkeys
                jmp     [d,x]

; ---------------------------------------------------------------------------
; tone_softkeys - the four softkeys of each of the four records
;
; Sixteen words, record by record: the arm each of f1 to f4 reaches on the
; title record, the settings record, the sequence editor and the player. It is
; the stock's own arrangement - the menu records at $4175, $417F and $4189 name
; their handlers the same way - and the table is indexed by record times four
; plus the key, which is what tone_key_softkey computes.
; ---------------------------------------------------------------------------
tone_softkeys
                fdb     tone_key_done           ; record 0 - the title: three
                fdb     tone_key_done           ; $C239 arms, which allocate a
                fdb     tone_key_done           ; frame and return, and the
                fdb     tone_sk_exit            ; Exit
                fdb     tone_sk_number          ; record 1 - the tone
                fdb     tone_sk_on
                fdb     tone_sk_dial            ; softkey_manual_dial ($492C)
                fdb     tone_sk_off
                fdb     tone_key_f1_seqidx      ; record 2 - the sequence
                fdb     tone_key_f2_seqend
                fdb     tone_key_f3_delete
                fdb     tone_key_f4_insert
                fdb     tone_key_page2_f1       ; record 3 - the player
                fdb     tone_sk_cont
                fdb     tone_key_page1_f1
                fdb     tone_sk_stop

; ---------------------------------------------------------------------------
; the arms this table needed that were not routines of their own
; ---------------------------------------------------------------------------
tone_sk_exit
                lbra    ABI_screen_back         ; post_request_0b -> $8E62

tone_sk_number
                lda     #TONE_FIELD_TONE        ; softkey_tone_number ($47FA):
                lbra    tone_select_field       ; $3D11 = 7 and the one-digit
                                                ; field at $0F
tone_sk_on
                lda     #TONE_FIELD_ON          ; softkey_on_time ($4842):
                lbra    tone_select_field       ; $3D1C = 0 and the field at
                                                ; $4B/$51
tone_sk_off
                lda     #TONE_FIELD_OFF         ; softkey_off_time ($4860):
                lbra    tone_select_field       ; $3D1C = 1 and $60/$66

tone_sk_dial
                ; softkey_manual_dial ($492C) returns at once unless $3C03 is
                ; set, so in a TONE sequence this key does nothing at all and
                ; the record prints no label beside it. In a DIALLED one it is
                ; the Manual Dial the record labels: the keypad's sixteen digits
                ; each sound their pair, which is page1_dtmf.s's own key
                ; handler, and the record stays on the glass while they do.
                tst     >tone_dtmf_mode
                beq     tone_sk_dial_none
                ldx     #dtmf_key
                lbsr    ABI_screen_install
                lbra    tone_show
tone_sk_dial_none
                lbra    tone_key_done

tone_sk_cont
                clr     >tone_single            ; softkey_continuous_run
                lbsr    tone_start              ; ($4A19): $3C81 = 0 and the
                lbra    tone_show               ; player restarted
tone_sk_stop
                clr     >tone_incr_mode         ; softkey_stop ($4AB9): STD
                clr     >tone_manual_sel        ; $3D11 zeroed: not Manual's
                clr     >tone_field             ; >$3D11 with zero - the FIELD
                clr     >dtmf_field             ; ID, two cells here - then
                lbsr    tone_output_stop        ; seq_output_stop ($4881); see
                lbra    tone_show               ; tone_rq_stop on the mapping

; ---------------------------------------------------------------------------
; tone_key_f1_seqidx, tone_key_f2_seqend - the editor record's two number fields
;
;   uses:  A, B, X, Y, U
;
; softkey_seq_index ($71B4) and key_select_seq_end ($71DE): each selects its
; field and clears the pending insert, because an insert is a state of the DATA
; cursor and choosing a number field leaves it.
; ---------------------------------------------------------------------------
tone_key_f1_seqidx
                lda     #TONE_FIELD_SEQIDX      ; softkey_seq_index ($71B4)
                clr     >tone_insert
                lbra    tone_select_field
tone_key_f2_seqend
                lda     #TONE_FIELD_SEQEND      ; key_select_seq_end ($71DE)
                clr     >tone_insert
                lbra    tone_select_field

tone_key_f4_insert
                ; TWO STAGES, which is what softkey_edit_sequence_insert
                ; ($7203) does: the FIRST press opens the edit session - $3D35
                ; set, $3D37 pointed at the cursor, $3D3B zeroed, $3D11 = 9 and
                ; the one-character data field armed - and a LATER press toggles
                ; the insert flag $3D3E. The record's f4 label follows: it reads
                ; ' Edit Sequence' until the session opens and ' Insert' after,
                ; which is repaint_sequence_page ($70C5) choosing between $40DE
                ; and $4156.
                ;
                ; This did the insert on the first press, so the session the
                ; instrument requires never existed and the label never changed.
                tst     >tone_edit
                bne     tone_key_f4_gap
                lda     #$01                    ; the session opens
                sta     >tone_edit
                clr     >tone_insert
                lda     #TONE_FIELD_SEQDATA     ; and the data cursor is armed
                lbra    tone_select_field
tone_key_f4_gap
                ; A LATER PRESS TOGGLES THE FLAG AND REPAINTS, and does not
                ; shift anything. $7203's second path sets or clears $3D3E and
                ; calls the repaint; draw_sequence_window ($6FFC) then emits one
                ; extra cell of code $10 - a blank - at the cursor and pushes
                ; the rest along, so the operator SEES the gap before any data
                ; moves. The move itself happens when a digit is typed into it.
                ;
                ; This did the shift on the press and cleared the flag again,
                ; so the window showed the data already moved and the cell at
                ; the cursor read as a duplicate of its neighbour instead of a
                ; space. Driven on the stock: a second f4 gives
                ; '[ 0123456789ABCDE]' and this gave '[00123456789ABCDE]'.
                lda     >tone_insert            ; ONE OR ZERO, not the
                bne     tone_key_f4_gap_off     ; complement: the stock's $3D3E
                lda     #$01                    ; is a flag other code indexes
                bra     tone_key_f4_gap_set     ; and compares against one
tone_key_f4_gap_off
                clra
tone_key_f4_gap_set
                sta     >tone_insert
                lbsr    tone_show
                lbra    tone_field_arm          ; $7235: the second path of
                                                ; softkey_edit_sequence_insert
                                                ; re-arms the data cursor too

; --- page 2: manual mode ---------------------------------------------------
tone_key_page2_f1
                ; ENTER MANUAL. Stop the timer if it is running - key_manual
                ; ($4F5E) calls seq_output_set_running(0) first for the same
                ; reason - then hold the output gate open and mark the state.
                ; Nothing advances until f2 is pressed.
                lbsr    tone_stop
                lda     #TONE_MANUAL
                sta     >tone_state
                ; AND THE MANUAL FIELD IS THE ONE SELECTED: seq_enter_manual_mode
                ; ($49C0) leaves $3D11 = $0B, arm [10] of the $697F up/down
                ; table, which is what makes the arrows walk the sequence.
                ; Measured 2026-09-17: f1 on the player record leaves $3D11 =
                ; $000B on the instrument.
                lda     #$01
                sta     >tone_manual_sel
                ; AND THE MUX CODE IS THE MODE'S, not always $20.
                ; seq_enter_manual_mode ($49C0) opens the gate through
                ; dds_set_output_mode_reg22 ($6B92) with a NON-ZERO argument,
                ; and that routine answers $22 when $3C03 is set and $20 when
                ; it is clear. A hand-stepped DTMF sequence therefore holds $22
                ; open, the same value its running ticks use; this wrote $20 for
                ; both and put a dialled pair through the tone mux.
                ldb     #TONE_GATE_ON
                tst     >tone_dtmf_mode
                beq     tone_key_page2_f1_gate
                ldb     #TONE_GATE_ON_DTMF
tone_key_page2_f1_gate
                lbsr    tone_gate_write
                lbra    tone_show


; --- page 1: the sequence's own keys ---------------------------------------
tone_key_page1_f1
                ; RUN IT ONCE AND STOP, which the stock calls SINGLE.
                ; seq_run_single ($4A6C) sets the single-shot flag $3C81 and
                ; starts the timer; the NMI body tests it at $4322 against the
                ; once-through flag $3D34, which seq_step_advance ($42B1)
                ; clears when the position wraps past Seq End, and takes the
                ; stop path at $436D. So a single-shot sequence plays through
                ; and stops itself.
                ;
                ; This firmware could only run continuously, so a sequence
                ; meant to be heard once had to be stopped by hand - and an
                ; operator watching for the end has to catch it.
                lda     #$01
                sta     >tone_single
                lbsr    tone_start
                lbra    tone_show


; ---------------------------------------------------------------------------
; tone_copy_time_to_all - one of the two times, from this tone to all sixteen
;
;   entry: A = 0 for the On time, 1 for the Off time
;   uses:  A, B, X, Y, U
;
; copy_time_to_all_tones ($4AED). It reads the request code itself and swaps
; its source and companion pointers - $3C10 and $3C12 for $37, the other way
; round for $38 - so the two codes copy the two times. THIS COPIED BOTH AT
; ONCE, from a softkey, and the instrument has no key for it at all: driven
; 2026-09-11, f1, f3 and f4 on the settings record leave all sixteen records
; alone. The bus reaches it and nothing else does.
;
; The refusal is the stock's: a record whose value and companion are both zero
; cannot be broadcast, error $33.
; ---------------------------------------------------------------------------
tone_copy_time_to_all
                pshs    a                       ; which time
                ldb     >tone_number
                lbsr    tone_times_address
                ldu     ,x                      ; the pair, TONE_ON first
                ldy     TONE_OFF,x
                cmpu    #0                      ; BOTH ZERO IS REFUSED, as
                bne     tone_copy_go            ; $4AED refuses a record whose
                cmpy    #0                      ; value and companion are both
                bne     tone_copy_go            ; zero, raising error $33
                ldb     #ERR_TIME_BOTH_ZERO     ; which IS $33, 'On & Off times
                                                ; cannot both be 0' - the comment
                                                ; beside it named the stock's
                                                ; number and the code raised a
                                                ; different one
                lbsr    ABI_error_raise
                puls    a
                lbra    tone_show
tone_copy_go
                clrb                            ; every tone, 0..15
tone_copy_next
                pshs    b                       ; the counter, while
                lbsr    tone_times_address      ; tone_times_address uses B
                puls    b
                tst     1,s                     ; ONE TIME, NOT BOTH: the code
                bne     tone_copy_off           ; chose which
                stu     ,x                      ; TONE_ON is offset zero
                bra     tone_copy_step
tone_copy_off
                sty     TONE_OFF,x
tone_copy_step
                incb
                cmpb    #TONE_TONES
                blo     tone_copy_next
                puls    a
                lbra    tone_show

; THE OLD f3 CHAIN IS GONE. It tested the key again and dispatched on the
; firmware's own softkey pages; f1 to f4 all go through tone_softkeys now, and
; what reaches here is a key that is none of them. tone_key_f3_delete below is
; record 2's f3 arm, called from that table.
tone_key_f3
                ; THE SHIFTED CHORD IS TESTED FIRST, and tone_key_error falls
                ; through to tone_key_incr by its own `bne`. This branched
                ; straight to tone_key_incr, which sits AFTER that arm, so the
                ; arm was unreachable: measured, shift then INC SET on the tone
                ; record left the instrument on '* Last reported error was no.
                ; 0 *' and this firmware on ' Tone Number 0 FREQ 0.0 Hz '
                ; with the arm assembled and never entered.
                lbra    tone_key_error

tone_key_f3_delete
                ; softkey_delete_step ($726A), all three of its paths. With the
                ; data cursor the field ($7270 LDX >$3d11 / $7273 CMPX #$0009):
                ; an insert gap showing is CLOSED and nothing is deleted
                ; ($727A LDB >$3d3e, $7283 CLR >$3d3e), otherwise the step at
                ; the cursor goes ($728E sequence_delete_at_cursor) - and
                ; either way the page is repainted ($7298) and
                ; arm_seq_edit_cursor re-arms at $72A2. With any other field
                ; l72aa ($72AC STD >$3d11) zeroes $3D11 and nothing else
                ; happens. This deleted a step whatever was selected and with
                ; the gap open, and armed nothing.
                ;
                ; tone_field is $3D11's field and entry_armed is its "a field
                ; at all" (tone_step_field's header), so zeroing $3D11 is
                ; clearing that, and the key is otherwise spent.
                lda     >tone_field
                cmpa    #TONE_FIELD_SEQDATA
                beq     tone_key_f3_data
                clr     >entry_armed            ; l72aa: $3D11 = 0
                lbra    tone_key_done
tone_key_f3_data
                tst     >tone_insert
                beq     tone_key_f3_cut
                clr     >tone_insert            ; the gap closes instead
                bra     tone_key_f3_shown
tone_key_f3_cut
                lbsr    tone_seq_delete         ; $728E
tone_key_f3_shown
                lbsr    tone_show               ; $7298 repaint_sequence_page
                lbra    tone_field_arm          ; $72A2
tone_key_error
                ; SHIFTED INC SET FLASHES THE LAST ERROR HERE TOO. Arm [15] of
                ; the page-1 dispatch d508c is key_show_last_error ($5052): a
                ; single no-argument call to show_last_error_screen ($C418),
                ; which sets bit 4 of event_flags, paints '* Last reported
                ; error was no. *', renders $23DE through format_three_digits
                ; ($C9D1) and blank_leading_zeros ($CCFF), calls the paged
                ; routine at $404F for line 2 and delays $0BB8 before restoring
                ; the display. It then falls through DELIBERATELY, with no
                ; branch, into key_clear_entry_state ($505F), which closes any
                ; open step edit with cancel_pending_entry ($47D6) and clears
                ; $3D11 - so: show the error, then return the mode to no
                ; selected field.
                ;
                ; ONE HANDLER SERVES BOTH PAGE-1 RECORDS, so the DTMF record
                ; answers it through this arm as well; $3D11 is tone_field and
                ; dtmf_field here, the pair every arm clears together.
                ;
                ; It was answered on the Main Selection, the channel screen and
                ; the digital screen and not on this one - page2_digital.s's
                ; digital_key_error says why in its own words: an operator who
                ; is refused ON THIS SCREEN is the one who wants the words.
                ; Measured at seed 44 step 28, shift then INC SET on the Tone
                ; Sequence record: the instrument paints '*  Last reported
                ; error was no.    1    *' and this firmware stayed on
                ; ' Tone Number 0    FREQ      0.0   Hz '.
                cmpb    #KEY_S_INC_SET
                bne     tone_key_incr
                lbsr    ABI_error_show
                lbsr    tone_entry_none         ; $505F: cancel_pending_entry
                clr     >tone_manual_sel        ; $3D11 zeroed: not Manual's
                clr     >tone_field             ; and $3D11 = 0, which is this
                clr     >dtmf_field             ; pair
                lbra    tone_show

tone_key_incr
                cmpb    #KEY_INC_SET
                bne     tone_key_freq

                ; AND IT NEEDS A FIELD UNDER IT, like the arrows. INC SET
                ; edits the increment OF THE SELECTED FIELD:
                ; incrset_edit_freq_step ($6866) and its siblings are arms of
                ; the $697F table that step_active_field ($666D) dispatches on
                ; $3D11, and with $3D11 zero - a fresh mode, or any record
                ; change, menu_page_key ($4C87) having cleared it - there is
                ; no arm and the key is spent. entry_armed tracks $3D11 here;
                ; see the note over tone_step_field.
                ;
                ; Driven on both, 2026-09-13, on the tone record with nothing
                ; selected: INC SET leaves the instrument's $23A8 at 00 and
                ; its screen at 'FREQ 0.0 Hz', and left this firmware armed
                ; with an increment view over the value - after which a keyed
                ; digit echoed where the instrument ignored it. The
                ; differential harness reported it as seed 21, step 16.
                ;
                ; AND IT IS REFUSED ALOUD, NOT SPENT, and only six fields have
                ; an increment. The request is key_incr_set ($4D7B): $4D7B
                ; LDX >$3d11 / $4D7E LBRA l4e13, whose guard $4E13 CMPX #$0006
                ; / BGT l4e0b and SUBD #$0001 / BLT l4e0b admits $3D11 = 1 to 6
                ; into the six-arm table d4e26 - the frequency, the level and
                ; the two times, each as a value and as its increment. Zero
                ; and every field above 6 - the tone number, Seq Index, Seq
                ; End, the data cursor - take l4e0b: $4E0B LDB #$14 / $4E0D
                ; STB >$3c02, which l5104 then beeps through $C3FE locally.
                ; No arm, and so no cursor. This returned in silence for no
                ; field and armed an increment for every other one.
                tst     >entry_armed
                beq     tone_key_incr_none
                lda     >tone_field
                cmpa    #TONE_FIELD_AMPL        ; FREQ, On, Off and AMPTD are
                bls     tone_key_incr_armed     ; TONE_FIELD_* 0 to 3
tone_key_incr_none
                ldb     #ERR_NOT_STEPPABLE      ; $14, 'Not an incrementable
                lbra    ABI_error_record        ; field', as $C3FE records it
tone_key_incr_armed
                lda     #$01                    ; the next ENTER stores this
                sta     >tone_incr_mode         ; field's INCREMENT
                lbsr    tone_entry_reset
                lbra    tone_show_armed

; --- THE FREQ KEY, WHICH THIS SCREEN NEVER ANSWERED ------------------------
; freq_key ($4D02), arm [24] of the $508C dispatch at $50BC, reached from key
; code 6 through message $0019. It is guarded TWICE and both guards matter:
;
;   $4D02  LDB >$3C03 / CMPB #$00 / LBNE $4D3F   DTMF mode  -> error $3A
;   $4D0B  LDB >$3C8F / CMPB #$01 / LBNE $4D37   not rec 1  -> error $3B
;   $4D14  LDD #$0001 / STD >$3D11               otherwise: field 1, and
;   $4D24  LDU #$0000 / JSR [$3C0E]              freq_entry_field_geometry
;                                                ($4574) arms eight digits
;
; The DTMF guard is the first one because a DIALLED sequence has no FREQ cell
; at all: record 1 of $4234 carries ' Manual Dial' where the tone record
; carries the field, which is why $4D07 refuses with 'Commmand not permitted
; in this mode' rather than 'not available in present window'.
;
; NOTHING ANSWERED THIS KEY HERE, so the field id simply stayed at whatever it
; was - and zero, its value at a fresh entry, IS TONE_FIELD_FREQ. The key was
; therefore a no-op that left FREQ selected on every record, and the digits
; after it echoed into the FREQ columns wherever the screen happened to be.
; ---------------------------------------------------------------------------
tone_key_freq
                cmpb    #KEY_FREQ
                bne     tone_key_wave
                tst     >tone_dtmf_mode         ; $4D02
                bne     tone_key_wrong_mode
                lda     >tone_page              ; $4D0B
                cmpa    #TONE_PAGE_TONE
                bne     tone_key_wrong_window
                lda     #TONE_FIELD_FREQ
                lbra    tone_select_field

; --- THE WAVEFORM KEY, WHICH THIS MODE ALSO HAS NO FIELD FOR ---------------
; Grepping the whole of a2u13_page1.s for the word turns up nothing: no arm
; anywhere in sequence_mode_message_handler ($4C01)'s $508C table names
; WAVEFORM, on any record of Tone Sequence or DTMF Sequence, so a keypress
; here falls to the SAME default reject_key_error_3a ($5071) the PHASE key
; below reaches - $3A, 'Commmand not permitted in this mode' - unconditional
; on the mode, exactly as PHASE is.
;
; THIS WAS MISSING ENTIRELY: the key fell through every branch to
; tone_key_ignore/ABI_key_refuse, which does not call tone_entry_none. An
; AMPTD entry armed on the sequence output record (TONE_PAGE_PLAYER) stayed
; armed after WAVEFORM. Found by the differential harness, seed 2 step 19:
; WAVEFORM pressed with AMPTD armed left the stock's $23A8 at 0 (disarmed,
; error $3A) and this firmware's entry_armed at 1, so the plain digit '4' at
; step 21 was taken as an AMPTD keystroke ('AMPTD  4') where the instrument,
; with nothing armed, ignored it and kept 'AMPTD 100 uV'.
; ---------------------------------------------------------------------------
tone_key_wave
                cmpb    #KEY_WAVEFORM
                bne     tone_key_phase
                bra     tone_key_wrong_mode

; --- THE PHASE KEY, WHICH THIS MODE HAS NO FIELD FOR -----------------------
; Key code 3 posts message $001C, and d508c[27] at $50C2 is
; reject_key_error_3a ($5071): LDB #$3A / STB >$3C02 and out. There is no
; PHASE handler in this mode on any record - it never writes a field id and
; never calls the arm vector - so the key refuses everywhere, and the shared
; epilogue $5104 clears $3D11 at $517F because $3A is one of the three codes
; it tests for at $515B.
; ---------------------------------------------------------------------------
tone_key_phase
                cmpb    #KEY_PHASE
                bne     tone_key_ampl
tone_key_wrong_mode
                clr     >tone_manual_sel        ; $517F zeroes $3D11 for $3A
                lbsr    tone_entry_none         ; $517F, and $B48C before it
                lda     #1                      ; AND THE ARMED FIELD COMMITS
                sta     >rmt_field_gone         ; NOTHING NOW: $238F stays set,
                                                ; but the $23 a later unit
                                                ; posts finds $3D11 zero.
                                                ; Driven 2026-09-17: 'STON 50;'
                                                ; 'BSB;' 'MS;' and 'STON;' 'BSB
                                                ; 50 MS;', and the same with
                                                ; APA, SEQP and SEQE, move
                                                ; nothing on the instrument and
                                                ; report only BSB's $3A
                ldb     #TONE_ERR_WRONG_MODE
                lbra    ABI_error_record        ; l5104: $9DD3 while remote,
                                                ; so the controller's SRQ lamp
                                                ; lights as the instrument's
                                                ; does after 'FRA;'
tone_key_wrong_window
                clr     >tone_manual_sel        ; and for $3B
                lbsr    tone_entry_none
                lda     #1                      ; the same zeroed $3D11
                sta     >rmt_field_gone
                ldb     #ERR_WRONG_WINDOW
                lbra    ABI_error_record

                ; THE AMPTD KEY, which is the stock's arm [25] of the $508C
                ; dispatch, key_select_amptd ($4D47): on the sequence output
                ; page it stores $0003 into the field cursor $3D11, calls
                ; cancel_pending_entry ($47D6) and arms the entry through
                ; [$3C0E](1) = entry_field_amptd ($458D); anywhere else it
                ; raises error $3B. Its screen at $40F2 reads
                ; ' Seq  115  [E]       AMPTD  1.001 V   ', so the level the
                ; sequence plays at is set from the sequence screen and the
                ; operator never leaves it to change how loud it is.
                ;
                ; The level belongs to the channel, not to a step: the player
                ; drives TONE_CHANNEL and the stock reads its record's +10 for
                ; this field too. So this is a fourth position of the same
                ; field cursor, and everything the cursor already does -
                ; ENTER commits, INCR SET diverts, the arrows step - works on
                ; it unchanged.
tone_key_ampl
                cmpb    #KEY_AMPL
                bne     tone_key_up
                lda     >tone_page              ; ON THE OUTPUT RECORD AND
                cmpa    #TONE_PAGE_PLAYER       ; NOWHERE ELSE, and that is
                bne     tone_key_ampl_window    ; the stock's own rule:
                lda     #TONE_FIELD_AMPL        ; key_select_amptd ($4D47)
                lbra    tone_select_field       ; stores $0003 into the field
                                                ; cursor $3D11 on the sequence
                                                ; output page and raises $3B
                                                ; anywhere else. This accepted
                                                ; it on every record, and the
                                                ; other three do not paint a
                                                ; level row - so the operator
                                                ; got an entry field with
                                                ; nothing on the screen to
                                                ; show it.
                                                ;
                                                ; AND IT IS ALLOWED WHILE THE
                                                ; SEQUENCE PLAYS. A tone_state
                                                ; test stood here refusing it
                                                ; then; $4D47 has no such
                                                ; test, and setting the level
                                                ; while listening is what the
                                                ; field is on this record for.
tone_key_ampl_window
                lbsr    tone_entry_none         ; AND THE FIELD GOES WITH IT.
                                                ; The shared error epilogue
                                                ; $5104 zeroes $3D11 at $517F
                                                ; for errors $3A, $3B and $14,
                                                ; and $B48C has already called
                                                ; entry_exit_restore_display
                                                ; ($B38B) - CLR >$23A8 - on the
                                                ; way in, because AMPTD is one
                                                ; of the five codes
                                                ; keymap_menu_msgs_19_1d
                                                ; ($AEBB) answers. So a refused
                                                ; field key leaves NOTHING
                                                ; armed and the digits after it
                                                ; are beeped away rather than
                                                ; typed into whatever was
                                                ; selected before.
                ldb     #ERR_WRONG_WINDOW       ; $3B, err_t77ae. A TAIL CALL:
                lbra    ABI_error_record        ; repainting the screen after
                                                ; it wipes the message the
                                                ; operator is meant to read.
                                                ; RECORD, NOT RAISE: the page's
                                                ; epilogue reports $3C02
                                                ; through $9DD3 while remote,
                                                ; SRQ and all, and beeps only
                                                ; when local; error_raise beeps
                                                ; in both. Seed 3 step 58,
                                                ; 'APC;' on the Tone Number
                                                ; record: the instrument's
                                                ; status LEDs read $46, this
                                                ; read $47
tone_key_up
                cmpb    #KEY_UP
                bne     tone_key_down
                lda     >tone_state             ; IN MANUAL MODE THE ARROWS
                cmpa    #TONE_MANUAL            ; WALK THE SEQUENCE, exactly
                bne     tone_key_up_field       ; as arm [10] of the stock's
                tst     >tone_manual_sel        ; - WITH THE MANUAL FIELD
                lbne    tone_manual_forward     ; SELECTED, $3D11 = $0B
tone_key_up_field
                lda     >tone_field             ; $697F up/down table does:
                cmpa    #TONE_FIELD_SEQDATA     ; step_seq_index_manual
                lbeq    tone_key_next_cursor
                ldb     #$01
                lbra    tone_step_field
tone_key_down                                   ; ($68E2) moves [$3D37] with
                cmpb    #KEY_DOWN               ; step_seq_field ($744B),
                bne     tone_key_endhere        ; reads the tone there with
                lda     >tone_state             ; tone_at_cursor ($6D66) and
                cmpa    #TONE_MANUAL            ; sounds it with output_tone
                bne     tone_key_down_field     ; ($6A95) - one step either
                tst     >tone_manual_sel        ; way; only with the Manual
                lbne    tone_manual_back        ; field selected (measured
tone_key_down_field                             ; 2026-09-17: after RUNM and
                                                ; the local edge, up is $04)
                lda     >tone_field             ; way, audibly.
                cmpa    #TONE_FIELD_SEQDATA     ;
                lbeq    tone_key_last_cursor    ; ON THE SEQUENCE EDITOR THE
                ldb     #$FF                    ; ARROWS MOVE THE CURSOR, and
                lbra    tone_step_field         ; NEXT and LAST leave: the
                                                ; edit screen posts $20 and $1F
                                                ; to step_up_key ($4E35) and
                                                ; key_step_down ($4E6F), the
                                                ; two codes repaint_hook_leave_
                                                ; editor ($5185) lets through.
                                                ; They were the wrong way round
                                                ; here - NEXT moved the cursor
                                                ; and the arrows stepped a
                                                ; field that is not on screen

; ---------------------------------------------------------------------------
; tone_manual_forward, tone_manual_back - walk the sequence by hand
;
;   uses:  A, B, X, Y, U
;
; THE ARROWS MOVE THE CURSOR AND SOUND WHAT THEY LAND ON. The stock walks a
; stopped sequence with arm [10] of the $697F up/down table -
; step_seq_index_manual ($68E2) - which sets $3D11 = 8, moves the field
; through step_seq_field ($744B), reads the tone the cursor landed on with
; tone_at_cursor ($6D66) and sounds it with output_tone ($6A95). The PLAYER's
; own position $3D2C is not touched by any of it: that cell belongs to
; seq_step_advance ($42B1) and the tick.
;
; THESE USED TO CALL tone_advance, THE TICK'S BODY, AND THAT COST A PRESS.
; tone_advance carries tone_phase - a tone step programs the tone and arms the
; gap, and only the NEXT entry closes the gap and advances the position - so
; the first arrow programmed a step and moved nothing, and the second did the
; moving. hp8904a-rewrite/tests/test_sequences.py drove exactly that and saw
; the number stand still. The note over the dialled edge in this file already
; said what the instrument does: "A hand step is not an interrupt and gets
; neither: the stock steps a tone by hand through output_tone ($6A95), never
; through this body."
;
; THE BOUNDS ARE $7533'S, NOT $7460'S. $3D11 = 8 dispatches at $760E to the
; l7533 arm, which moves [>$3D37] - the pointer to whichever of Seq Index
; ($3D0D) or Seq End ($3D0F) is selected - blocked at $00F9 going up and
; floored at $0000 going down, with NO WRAP either way. $3D11 = 9 is the
; sequence EDITOR's arm at l7460, which blocks on Seq End instead, and
; tone_key_next_cursor is the port of that one. Copying it here would have put
; the editor's bound on the player's arrows.
;
; AND NO dds_lock. It was held because the tick body writes the port directly;
; this walk never enters it. tone_sound_at_cursor is what the editor's own
; arrows already call with no lock, and step_seq_index_manual takes none
; either.
; ---------------------------------------------------------------------------
tone_manual_forward
                ldd     >tone_cursor            ; $7546: LDX [>$3D37] / CMPX
                cmpd    #TONE_PLAYLIST-1        ; #$00F9 / LBCC - at the last
                bhs     tone_manual_hold        ; step the arrow does nothing
                addd    #1                      ; $7554: ADDD #$0001
                bra     tone_manual_moved
tone_manual_back
                ldd     >tone_cursor            ; $7565: LDX [>$3D37] / CMPX
                beq     tone_manual_hold        ; #$0000 / LBLS - a FLOOR and
                subd    #1                      ; not a wrap: step 0 holds
tone_manual_moved
                ldx     >tone_cursor            ; the old value, which the
                std     >tone_cursor            ; clamp puts back when the new
                tfr     x,d                     ; one is out of range
                lbsr    tone_clamp_index        ; $7581: clamp_index_to_end

                ; THE ORIGIN FOLLOWS THE CURSOR ON THIS ARM, and it does not on
                ; the editor's. $75A2 stores $3D0D into the window origin $3D39
                ; when $3D37 is $3D0D, which is this arm; l7460 scrolls the
                ; window at $74AC instead, so an operator editing steps can
                ; look around inside it and come back to where they started.
                ldd     >tone_cursor
                std     >tone_window
                lbsr    tone_sound_at_cursor    ; $68F6 then $6905, in order
tone_manual_hold
                lbra    tone_show               ; $755D and $757B clear the
                                                ; changed flag, and the arm
                                                ; repaints on the way out
                                                ; either way

; ---------------------------------------------------------------------------
; tone_clamp_index - clamp_index_to_end ($73E2)
;
;   entry: D = the value the field held BEFORE the move
;   uses:  A, B, X
;
; $73EA: LDD >$3D0F / ADDD #$0001 / CMPD >$3D0D / LBCC - while Seq End plus
; one is at or above the cursor there is nothing to do, which is every move
; the arrows can make from a cursor that was already in range.
;
; PAST IT THE INDEX IS REFUSED AND PUT BACK. $73FE tests $3D37 against $3D0D
; and, when the field moved is the Seq Index, records error $37 and stores the
; saved old value back into $3D0D: the arrow does nothing and the fault line
; says why. error_record is the port of that STB >$3C02 - it records and
; sounds WITHOUT painting a number over the screen's own words.
;
; THE OTHER ARM BELONGS TO THE SEQ END FIELD. $740F - when $3D37 is $3D0F -
; sets $3D0D to $3D0F + 1, takes the window origin with it and repaints
; through show_seq_index ($6EFF) and draw_sequence_window when the edit
; session flag $3D3D is set. Moving Seq End is not what an arrow does in
; manual mode: tone_commit_word is where this firmware moves that field, and
; its note at the $77CB store is where the same window rule is written down.
; ---------------------------------------------------------------------------
tone_clamp_index
                pshs    a,b                     ; the old value, for the put-
                ldd     >tone_end               ; back below
                addd    #1                      ; $73EA: Seq End plus one
                cmpd    >tone_cursor
                bhs     tone_clamp_index_done   ; $73F6 LBCC: still in range
                ldb     #TONE_ERR_SEQ_INDEX     ; $7404: LDB #$37
                lbsr    ABI_error_record
                ldd     ,s                      ; $740A: the old value back
                std     >tone_cursor
tone_clamp_index_done
                puls    a,b
                rts

tone_key_endhere
                ; SHIFTED ENTER SETS THE SEQUENCE END AT THE CURSOR.
                ; set_seq_end_to_cursor is arm [37] of the $508C dispatch,
                ; reached by request code $26, and key 52 - shifted ENTER - is
                ; what posts it ($AE1A). It is one of the six codes
                ; repaint_hook_leave_editor ($5185) lets through, because
                ; setting the end is part of editing rather than a reason to
                ; leave it.
                ;
                ; THE CURSOR AS IT STANDS. Seq End is a 0-based LAST INDEX -
                ; seq_step_advance ($42B1) keeps a position while it is <=
                ; $3D0F and load_current_step ($4268) substitutes the short
                ; last gap when it EQUALS it - so 'end here' means the step
                ; the operator is on is the last one played, not the one
                ; after it. This firmware had the function on a softkey of its
                ; own, tone_key_page1_f2, where the instrument has f2 select
                ; the Seq End FIELD; the softkey is gone and the key that
                ; carries it here is the key that carries it there.
                cmpb    #KEY_S_ENTER
                bne     tone_key_entry          ; THE ENTRY KEYS START THERE,
                                                ; behind the armed guard - not
                                                ; at tone_key_backspace, which
                                                ; is past it
                ldd     >tone_cursor
                std     >tone_end
                ; AND ON THE EDITOR THE FIELD IS RE-ARMED. set_seq_end_to_cursor
                ; ($4EC8) passes 2 - $3C8F, and commit_seq_end_and_repaint
                ; ($7370) stores the end ($7376-$7379) and then, only for a
                ; zero argument ($7383 LBNE l73df), repaints and re-arms by
                ; $3D11: 8 is Seq Index through [$3C0E] with 4 ($73A7), $0A is
                ; Seq End with 5 ($73C4), 9 is the data cursor through
                ; arm_seq_edit_cursor ($73DA), and anything else arms nothing.
                ; tone_field names those three and entry_armed says a field is
                ; selected at all (tone_step_field's header).
                lda     >tone_page
                cmpa    #TONE_PAGE_SEQ          ; $3C8F = 2
                bne     tone_key_endhere_shown
                tst     >entry_armed            ; $3D11 = 0: nothing to arm
                beq     tone_key_endhere_shown
                lda     >tone_field
                cmpa    #TONE_FIELD_SEQIDX
                beq     tone_key_endhere_arm
                cmpa    #TONE_FIELD_SEQEND
                beq     tone_key_endhere_arm
                cmpa    #TONE_FIELD_SEQDATA
                bne     tone_key_endhere_shown
tone_key_endhere_arm
                lbsr    tone_show               ; $738C repaint_sequence_page
                lbra    tone_field_arm
tone_key_endhere_shown
                lbra    tone_show

                ; --- AND THE ENTRY KEYS NEED A FIELD UNDER THEM -----------
                ; The four keys below - BACKSPACE, the three unit keys, the
                ; decimal point and the ten digits - are exactly the group
                ; numeric_entry_key_handler ($B3C2) gates on $23A8 at
                ; $B494: LDB >$23A8 / CMPB #$00 / LBNE $B4B0 takes the armed
                ; path, and the fall-through at $B49D-$B4AD calls
                ; error_report_beep ($C3FE) with 1 and RETURNS - no digit is
                ; taken, no buffer is touched and no message is posted, so
                ; nothing on the screen moves.
                ;
                ; Without this the unit key was worse than the digit:
                ; tone_key_unit runs tone_commit whatever is armed, so 'kHz'
                ; after a record change committed the digits standing in the
                ; shared buffer into whichever field the cursor had last been
                ; left on.
                ;
                ; THE FLAG ASKED IS $23A8 ITSELF, through entry_is_open, which
                ; reads the cursor bit - written exactly where $23A8 is
                ; (entry.s). This read entry_armed, and on this page that cell
                ; stands in for $3D11 as well (tone_step_field says why), so it
                ; stayed set across exits that re-arm nothing - f2 or f4 on
                ; the output record, f3 on a tone sequence's settings record,
                ; INCR SET on a field with no increment. The instrument clears
                ; $23A8 at each
                ; of those ($B394) and takes no key after them; the same three
                ; gates on this page - here, tone_key_hexfield and
                ; tone_key_enter - now ask the same question it does.
tone_key_entry
                lbsr    ABI_entry_is_open
                lbeq    tone_key_ignore
tone_key_backspace
                cmpb    #KEY_BACKSPACE
                bne     tone_key_units
                ; THE LAST DIGIT OUT AGAIN. entry_backspace ($B2CD, reached
                ; at $B4B9 for key $1F, $B2D7) steps the head $23A4 back and
                ; blanks the vacated cell for kind 3 ($B2E9-$B31F), which
                ; every field of this screen is armed in - the stock's
                ; freq_entry_field_geometry, entry_field_amptd and
                ; entry_field_on_off_time each store 3 into 7,s of the l4667
                ; tail - and numeric_entry_key_handler repaints the buffer
                ; ($B4D0-$B501) once a key has been accepted ($B4C4). With
                ; nothing to take out (the carry) the glass is left as it
                ; is: that is what $B4CD leaves when no key was accepted, and
                ; what repainting an already-blank buffer leaves after one.
                lbsr    ABI_entry_backspace     ; $B2E9-$B31F, slot 73
                bcs     tone_key_done
                lbra    tone_key_redraw         ; $B4D0-$B501: the values and
                                                ; the entry over its field
tone_key_done
                ; A KEY THIS SCREEN DOES NOT USE REPAINTS AND SAYS NOTHING.
                ; Three of record 0's four handler words are $C239, which
                ; allocates a frame and returns into the dispatcher, and the
                ; dispatcher repaints - so the glass is rewritten and no error
                ; is recorded. Driven on the stock 2026-09-11: f1 to f4 on the
                ; settings record leave $23DE at zero and the screen as it was.
                lbra    tone_show
tone_key_units
                ; THE THREE UNIT KEYS. Which of them this field takes, and what
                ; each means, is tone_class_units - $B212 read out. A class that
                ; has no arm for the key beeps, which is $B0C1 returning zero.
                cmpb    #KEY_DEG
                bne     tone_key_unit_hz
                ldb     #0
                bra     tone_key_unit
tone_key_unit_hz
                cmpb    #KEY_HZ
                bne     tone_key_unit_khz
                ldb     #1
                bra     tone_key_unit
tone_key_unit_khz
                cmpb    #KEY_KHZ
                bne     tone_key_point
                ldb     #2
tone_key_unit
                lbsr    tone_key_unit_lookup
                lbcs    tone_key_ignore
                stb     >tone_entry_unit

                ; A UNIT KEY WITH NOTHING TYPED ENDS THE INCREMENT VIEW, which
                ; is what ENTER does eleven hundred lines up at
                ; tone_key_enter_empty - one behaviour, and the operator sees
                ; the same thing whichever terminator they reach for. The
                ; instrument goes back to the value: measured at seed 39 step
                ; 31, 'khz' takes the stock from 'AMPTD<$07>     1 V' to
                ; 'AMPTD    100 V' while this firmware kept the increment on
                ; the glass, so the next arrow would have stepped what the
                ; screen no longer claimed to be showing.
                ;
                ; ONLY WITH AN EMPTY BUFFER. A unit key AFTER digits is the
                ; terminator that stores the increment, and that path must
                ; still reach the commit below with tone_incr_mode standing -
                ; enter_amplitude_step ($634F) is the arm that writes
                ; record+15, and it is reached by exactly that key.
                tst     >tone_incr_mode
                beq     tone_key_unit_commit
                tst     >entry_active
                bne     tone_key_unit_commit
                clr     >tone_incr_mode
                lbsr    tone_entry_reset
                lbra    tone_show
tone_key_unit_commit
                lbra    tone_key_commit

tone_key_point
                ; THE DECIMAL POINT, on every numeric field this screen arms.
                ; Column 7 of keypad_char_table ($EF94) holds '.' beside the
                ; digits and entry_to_scaled_digits ($CDE1) takes the fraction
                ; off the unit's decades. Driven 2026-09-11: 2 . 5 then Hz is
                ; an On Time of 2.50 ms on the instrument and was 25.00 ms
                ; here, because the key was dropped and the digits ran
                ; together.
                cmpb    #KEY_POINT
                bne     tone_key_digit
                lbsr    ABI_entry_point
                bcs     tone_key_point_twice
                lda     #$01                    ; something has been typed
                sta     >entry_active
                lbra    tone_key_redraw
tone_key_point_twice
                ldb     #ERR_KEY_ENTRY          ; a second point: $B5D0's 2
                lbra    ABI_error_raise

tone_key_digit
                lbsr    ABI_key_digit
                bcs     tone_key_ignore
                lbsr    ABI_entry_digit
                lda     #$01                    ; SOMETHING HAS BEEN TYPED, so
                sta     >entry_active           ; ENTER commits it to the
                                                ; selected field rather than
                                                ; running the sequence. The
                                                ; digit path did not set this,
                                                ; because until the field
                                                ; cursor existed nothing read
                                                ; it on this screen.
                ; A DIGIT ON SEQ INDEX OR SEQ END IS ONLY ECHOED. Measured on
                ; the stock 2026-09-16, Tone Sequence on its Seq Index record
                ; with $24AE poked to $0C: f1 then '3' '9' shows 'Seq Index
                ; 39' and leaves $3D0D, the window $3D39 and $24AE exactly as
                ; they were; ENTER then stores $0026, snaps the window to it
                ; and puts tone 6 on register $15. f2 '5' leaves $3D0F at
                ; $00F9 until ENTER. This arm used to store on every digit, on
                ; the reading that these were class 0 fields terminating on
                ; any character - but what that reading saw on the glass was
                ; the echo, and the store is the $23 of the ENTER that
                ; follows (tone_commit_seq). A digit on the data cursor never
                ; reaches here: tone_key_hexfield takes it, and its store is
                ; tone_key_data_put below.
                bra     tone_key_redraw
tone_key_data_put
                ; A CHARACTER TYPED ON THE DATA CURSOR NAMES THE TONE IN THAT
                ; STEP, and it is what performs a pending insert. The stock's
                ; enter_sequence_field ($7649) reads the keyed character out of
                ; $239A and converts it with parse_hex_digit_pair, so A to F
                ; name steps $0A to $0F - the last two of them the '*' and '#'
                ; the window renders; with $3D3E set the walk opens the gap and
                ; pushes the rest along before the value lands, which is the
                ; same place page2_edit.s's edit_digit_typed consults
                ; digital_insert ($6172). f4 only shows the gap; this is where
                ; it closes on a value.
                ;
                ;   entry: B = the nibble, 0 to 15, from tone_key_hexfield
                tst     >tone_insert            ; with the gap showing, the
                beq     tone_key_digit_over     ; insert is the store
                lbsr    tone_seq_insert
                bra     tone_key_digit_step
tone_key_digit_over
                ldx     >tone_cursor            ; otherwise the step takes the
                lbsr    tone_step_put           ; digit where it stands - B is
                                                ; the digit, X the step
tone_key_digit_step
                ; AND THE CURSOR MOVES ON, with the gap still showing. Driven
                ; on the stock: f4 f4 5 leaves Seq Index reading 2 and the
                ; window '[5 0123456789ABCD]' - the '5' placed, the cursor one
                ; along and the gap still open, so a run of digits can be typed
                ; straight into it. This cleared the flag after one digit and
                ; left the cursor where it was.
                ldd     >tone_cursor
                cmpd    >tone_end
                bhs     tone_key_digit_armed
                addd    #1
                std     >tone_cursor
tone_key_digit_armed
                lbsr    tone_entry_reset        ; one digit a cell, as
                lbra    tone_show_armed         ; arm_seq_edit_cursor does
tone_key_redraw
                lbsr    tone_show               ; the stored values first, then
                lbsr    tone_entry_echo         ; the typed digits over the
                                                ; field being edited
                ; AND THE DISPLAY'S ADDRESS AFTER THE LAST ONE, as the stock
                ; leaves it after every accepted key: $B4E9 LDA >$23ad /
                ; $B4EC LDB >$23a4 / add_bytes_to_word / $B4FA lcd_set_cursor
                ; after a BACKSPACE, and $B556-$B567 the same after a
                ; character. With the cursor on that is where it shows; this
                ; screen left it wherever the echo's last blank went.
                lda     >tone_field
                cmpa    #TONE_FIELD_TONE        ; the two hex fields echo
                bhs     tone_key_redraw_done    ; nothing (tone_entry_echo)
                ldx     #tone_field_cells
                lda     a,x                     ; $23AD
                adda    >entry_count            ; + $23A4
                lbra    ABI_lcd_cursor
tone_key_redraw_done
                rts
tone_key_ignore
                ; THE SAME SPLIT AS page0_screen.s's chan_key_ignore. The
                ; page-1 dispatcher rejects twenty-three of its sixty codes
                ; through reject_key_error_3a ($5071), which stores $3A in
                ; $3C02; the epilogue l5104 reports it through $9DD3 while
                ; remote and clears $3D11 at $517F because $3A is one of the
                ; three codes it tests at $515B. tone_key_wrong_mode is that
                ; arm and it was already here - nothing reached it from the
                ; fallthrough, so an unanswered bus request was reported as a
                ; keystroke refusal instead. $39, $3A and $3B - arms [56],
                ; [57] and [58] - are three of the codes that land here.
                cmpb    #RMT_RQ                 ; a bus request, not a key
                lbhs    tone_key_wrong_mode
                lbra    ABI_key_refuse          ; a key this screen cannot
                                                        ; use is REFUSED, not
                                                        ; ignored; see key_refuse

; ---------------------------------------------------------------------------
; tone_key_commit - a terminator the field takes: the entry ends, then commits
;
;   uses:  whatever tone_commit uses
;
; accept_units_key ($B0C1, called at $B5A5) answering 1 is $B5BA,
; entry_exit_restore_display with 0 - the cursor off, no repaint - and then
; request $23 at $B5C8. On this page $23 is key_enter_value ($4CCE) into
; dispatch_entry_complete ($6282), whose arms commit by $3D11 and re-arm the
; field through [$3C0E] or arm_seq_edit_cursor: commit_freq_value ($628E),
; commit_amptd_value ($630C), apply_time_entry ($638F), enter_tone_number
; ($640C), enter_sequence_field ($7649) - on a refused value as on a stored
; one. tone_commit re-arms on each of its tails, so this is the exit in front
; of it and nothing more.
; ---------------------------------------------------------------------------
tone_key_commit
                lbsr    ABI_entry_cursor_off    ; $B5BA
                lbra    tone_commit             ; request $23, and its re-arm


; ---------------------------------------------------------------------------
; page1_stream_open - WSQ: the playlist takes the data path
;
;   uses:  A, B, X
;
; start_streamed_digit_entry ($79C3), which streamed_entry_key ($5048) - arm
; [43] of the page-1 message table $508C, request code $2C - calls with no
; argument at all. Three things and no more:
;
;   $79C3  an insert in progress is cancelled, and the window repainted
;          without its gap if it was showing one
;   $79DF  the field id becomes 9, the DATA CURSOR. It does NOT open the
;          softkey edit session - $3D35 is left alone, so f4 still reads
;          ' Edit Sequence'
;   $79DF  the write cursor $3D3F is seeded from the operator's own cursor
;          $3D0D, and from there the stream walks its own way up the playlist
;
; ONE OPENER FOR EVERY PAGE-1 RECORD, because the instrument has one. $508C is
; the message table of sequence_mode_message_handler ($4C01), which serves the
; whole mode - the settings record, the sequence editor, the player and the
; Manual Dial screen the DTMF record puts on softkey 3 - so WSQ is answered
; identically on all of them. This firmware splits that mode across two key
; handlers, tone_key and page1_dtmf.s's dtmf_key, so both call this.
;
; The caller names itself in rmt_seq_owner and repaints; page1_bus_stream
; reads that byte to decide what the character it takes is allowed to sound.
; ---------------------------------------------------------------------------
page1_stream_open
                clr     >tone_insert            ; $79C3: the gap closes. The
                                                ; repaint is the caller's -
                                                ; both of them do one - so
                                                ; its draw_sequence_window
                                                ; is not called twice
                lda     #TONE_FIELD_SEQDATA     ; $79DF: field id 9
                clr     >tone_manual_sel
                sta     >tone_field
                ldx     >tone_cursor            ; $79DF: the stream starts
                stx     >tone_stream_at         ; where the cursor stands
                lda     #$01
                sta     >rmt_stream
                rts

; ---------------------------------------------------------------------------
; page1_bus_stream - one character of a WSQ stream, into the playlist
;
;   entry: rmt_mode_code = the character's VALUE as a playlist nibble, 0 to 15
;   exit:  rmt_check_result = 0
;   uses:  A, B, X, Y, U
;
; gpib_sequence_char_in ($7870), the per-character handler $79C3 installs at
; $2283. Its accepting leg, $78CF onwards, is four steps:
;
;   $78CF  parse_hex_digit_pair turns the character into a nibble and
;          seq_put_nibble ($452D) writes it at $3D3F. THE PLAYLIST, not the
;          output: a WSQ is a bulk LOAD and the instrument stores every
;          character of it whatever record is showing.
;   $794F  with the sequence editor up ($3C8F = 2) and the index inside the
;          sixteen-cell window, show_sequence_char ($6F37) draws that cell
;   $7952  with the player record up ($3C8F = 3) in Manual mode ($3C82 set)
;          AND the stream cursor standing on the operator's own cursor
;          ($3D3F = $3D0D), show_manual_tone_char echoes it and
;          tone_at_cursor ($6D66)/output_tone ($6A95) put the step on the
;          generator. Only the FIRST character of a stream can satisfy that -
;          $3D3F is seeded from $3D0D and then walks away from it - so a
;          bulk load reprograms the pair once, not once per character.
;   $799F  the cursor advances, with a ceiling of $00F9
;
; WHAT THIS REPLACES, and it is the reason the DTMF screen is in this file's
; blast radius. There was no $2C arm on the tone screen at all, so WSQ was
; refused with $30 on every sequence record; and the DTMF screen's arm handed
; each character to its own DIAL path, so 'WSQ 5551234;' put seven live DTMF
; bursts on the output socket and stored nothing. Measured against the stock,
; 2026-09-13, on the Manual Dial screen: the instrument stored 5 5 5 1 2 3 4
; into the playlist and made THREE DDS writes, all of them the screen's own
; entry; this firmware stored nothing and made 770.
;
; $3C82 IS NOT SET ON THE MANUAL DIAL SCREEN. softkey_manual_dial ($492C)
; writes $3C04 and $3D11, not $3C82 - only seq_enter_manual_mode ($49C0) sets
; that - and $3C8F reads 1 there, not 3. Both halves of $7952's test therefore
; fail on that screen and the character is stored in silence, which is exactly
; what the measurement above shows. rmt_seq_owner 3 is that screen here.
; ---------------------------------------------------------------------------
; tone_tick - one time-out of a running Tone Sequence: blk42d1 ($42D1)
;
;   uses:  A, B, X
;
; THE STOCK SPENDS TWO TIME-OUTS ON EVERY PHASE, and this spent one. With bit 7
; of $3D32 set a time-out only reloads the timer with the loaded duration less
; one ($4306-$4311), remembers it in $3D2E and, on a tone phase, puts the
; tone's code on the hop latch ($4316-$431C); the next writes the gate edge
; ($433F-$4368), advances the phase and loads the next non-zero duration
; ($4381-$438C), trims the timer by $18 when the gate stays open across the
; boundary ($438E-$43B0) and sets bit 7 again ($43B3). Driven 2026-09-15,
; RUNS on Tone Number 0: the instrument took 1,003 time-outs for 1,004 writes
; of register $22 and this 500, so every step played in half the time and the
; frequency words the harness sampled belonged to a later step (seeds 2, 15).
; ---------------------------------------------------------------------------
tone_tick
                lda     >tone_phase_count
                bpl     tone_tick_edge
                anda    #$7F                    ; $4306: the half-tick
                sta     >tone_phase_count
                ldd     >tone_period            ; $430B: LDX >$3D30 / LEAX -1,X
                subd    #$0001
                std     >ptm_timer2             ; $430F
                std     >tone_period_last       ; $4312: STX >$3D2E
                lda     >tone_phase_count       ; $4315: ASRA / BCC
                lsra
                bcc     tone_tick_done
                lda     >tone_playing           ; $4317: LDA >$3D27 / ORA #$C0
                ora     #$C0
                sta     >hop_latch
tone_tick_done
                rts
tone_tick_edge
                tst     >tone_single            ; $4322: single and a pass
                beq     tone_tick_go            ; complete - $3D34 cleared -
                tst     >tone_once              ; is the stop ($436D)
                lbeq    tone_stop_isr
tone_tick_go
                lda     >tone_phase_count       ; $4331: ASRA
                lsra
                ldb     #TONE_GATE_OFF          ; bit 0 clear: $21
                bcc     tone_tick_gate
                ldb     #TONE_GATE_ON           ; bit 0 set: $20
tone_tick_gate
                lda     #$01                    ; $4333: A = 1, nothing written
                cmpb    >tone_gate              ; $433F
                beq     tone_tick_advance
                lbsr    tone_gate_edge          ; $4344-$4368
                clra                            ; $4369: CLRA
tone_tick_advance
                pshs    a                       ; $4381: PSHS A,B
tone_tick_load
                lbsr    tone_step_advance       ; $4383
                lbsr    tone_load_step          ; $4386
                beq     tone_tick_load          ; $4389: a zero duration skipped
                puls    a
                ldx     >tone_period_last       ; $438D: LDX >$3D2E
                ldb     >tone_gate
                cmpa    #$01                    ; $4390
                bne     tone_tick_wrote
                cmpb    #TONE_GATE_ON           ; nothing written, the gate
                bne     tone_tick_mark          ; open, and an OFF phase next:
                lda     >tone_phase_count       ; LEAX -$18,X
                lsra
                bcs     tone_tick_mark
                leax    -$18,x
                bra     tone_tick_timer
tone_tick_wrote
                cmpb    #TONE_GATE_ON           ; $43A3: written, the gate now
                bne     tone_tick_mark          ; open, and an ON phase next:
                lda     >tone_phase_count       ; LEAX $18,X
                lsra
                bcc     tone_tick_mark
                leax    $18,x
tone_tick_timer
                stx     >ptm_timer2             ; $43B0
tone_tick_mark
                lda     >tone_phase_count       ; $43B3: ORA #$80
                ora     #$80
                sta     >tone_phase_count
                rts

; tone_step_advance - seq_step_advance ($42B1): the phase, and every second
; phase the position, wrapping past Seq End with the once flag cleared
;   uses:  A, B
tone_step_advance
                inc     >tone_phase_count
                lda     >tone_phase_count
                lsra
                bcc     tone_step_advance_done
                ldd     >tone_position
                addd    #$0001
                std     >tone_position
                cmpd    >tone_end               ; $42C2: CMPX >$3D0F / BLS
                bls     tone_step_advance_done
                clr     >tone_position
                clr     >tone_position+1
                clr     >tone_once
tone_step_advance_done
                rts

; tone_load_step - load_current_step ($4268): the tone at the position into
; tone_playing and its ON or OFF word into tone_period by bit 0 of the phase
; count; $00C8 for the last step's OFF in a single run
;   exit:  Z set when the duration is zero
;   uses:  A, B, X
tone_load_step
                ldd     >tone_position
                lbsr    tone_step_get           ; B = the tone ($4285 STB $3D27)
                stb     >tone_playing
                lbsr    tone_times_address      ; X = its times ($428F)
                lda     >tone_phase_count
                lsra
                bcs     tone_load_step_word     ; bit 0 set: the ON word
                leax    TONE_OFF,x
                tst     >tone_single            ; $4299
                beq     tone_load_step_word
                ldd     >tone_position
                cmpd    >tone_end               ; $42A0
                bne     tone_load_step_word
                ldx     #TONE_START_COUNTS      ; $42A5: LDX #$00C8
                bra     tone_load_step_store
tone_load_step_word
                ldx     ,x
tone_load_step_store
                stx     >tone_period            ; $42AD: STX sets Z
                rts

; ---------------------------------------------------------------------------
; page1_mode_exit - leaving Tone or DTMF Sequence
;
;   uses:  A, B, X, Y, U
;
; seq_mode_exit ($51E3), which sequence_mode_init installs in $2213 and
; return_to_main_menu ($8E62) calls on the way out: seq_output_set_running
; ($4702)(0) - the sequence and its timer stopped, the tone at the cursor
; sounded with the run flag clear - and dds_set_output_mode_reg22 ($6B92)(0),
; $21 into register $22. This firmware left both modes with neither, so after
; 'EM;' register $15 still held the playing tone's nibble where the
; instrument's reads 0 (seed 5 step 8).
; ---------------------------------------------------------------------------
page1_mode_exit
                lbsr    tone_set_stopped        ; $4702(0), unconditionally
                ldb     #TONE_GATE_OFF          ; $6B92(0): $22 <= $21
                lbra    tone_gate_write

; ---------------------------------------------------------------------------
page1_bus_stream
                ldb     >rmt_mode_code          ; $78CF: the nibble, at the
                ldx     >tone_stream_at         ; STREAM's own cursor
                lbsr    tone_step_put

                lda     >rmt_seq_owner          ; $7952: the Manual Dial
                cmpa    #$03                    ; screen is not a record this
                beq     page1_stream_step       ; leg reaches - see above - so
                                                ; the character is stored and
                                                ; nothing else happens
                lda     >tone_state             ; $7952's $3C82: only the
                cmpa    #TONE_MANUAL            ; player record in Manual mode
                bne     page1_stream_draw       ; sounds a streamed step
                ldx     >tone_stream_at         ; $7952: and only while the
                cmpx    >tone_cursor            ; stream is standing on the
                bne     page1_stream_draw       ; operator's own cursor
                lbsr    tone_sound_at_cursor    ; $6D66 tone_at_cursor and
                                                ; output_tone, the pair or the
                                                ; tone as tone_dtmf_mode says
page1_stream_draw
                lbsr    tone_show               ; $6F37's show_sequence_char
                                                ; and its
                                                ; show_manual_tone_char are
                                                ; both one cell of the record
                                                ; that is up; this paints the
                                                ; record, which is what every
                                                ; other arm here does
page1_stream_step
                ldx     >tone_stream_at         ; $799F: one along...
                leax    1,x
                cmpx    #TONE_PLAYLIST-1        ; ...and no further than the
                bls     page1_stream_store      ; last step, $00F9
                ldx     #TONE_PLAYLIST-1
page1_stream_store
                stx     >tone_stream_at
                clr     >rmt_check_result       ; $79B8 returns 1: taken, and
                rts                             ; the transfer goes on


; ---------------------------------------------------------------------------
; tone_field_class_get - the units class of the field being edited
;
;   exit:  A = the TONE_CLASS_* of tone_field
;   uses:  A, X
;
; The stock keeps this in $23AB, written when the field is armed. These screens
; select a field with the softkeys rather than arming a fresh entry each time,
; so it is looked up from the field id instead of stored - the same answer, and
; no stored copy that can disagree with the field.
; ---------------------------------------------------------------------------
tone_field_class_get
                lda     >tone_field
                cmpa    #TONE_CLASS_FIELDS      ; a field id out of range would
                bhs     tone_field_class_none   ; index past the table
                ldx     #tone_field_class
                lda     a,x
                rts
tone_field_class_none
                lda     #TONE_CLASS_NONE
                rts

; ---------------------------------------------------------------------------
; tone_key_unit_lookup - what a unit key means on the field being edited
;
;   entry: B = 0 for deg, 1 for Hz, 2 for kHz - the column of tone_class_units
;   exit:  carry CLEAR and B = the UNIT_* code; carry SET if this class refuses
;          that key, B undefined
;   uses:  A, B, X
;
; tone_class_units is $B212 transposed: the stock reaches one arm per class and
; the arm compares the key; this reaches one row per class and indexes it by the
; key. Same table, same answers, and a refusal is the arm returning zero - which
; is what sends the instrument to error_report_beep(2) at $B5D0.
; ---------------------------------------------------------------------------
tone_key_unit_lookup
                pshs    b                       ; the column
                lbsr    tone_field_class_get    ; A = the class
                ldb     #TONE_CLASS_KEYS
                mul                             ; D = class * 3
                addb    ,s+
                adca    #0
                ldx     #tone_class_units
                leax    d,x
                ldb     ,x
                cmpb    #TONE_UNIT_NONE
                beq     tone_key_unit_refused
                andcc   #~CC_CARRY
                rts
tone_key_unit_refused
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; tone_entry_scale - apply the unit key's meaning to the digits just typed
;
;   exit:  carry SET, and last_error written, if the scaled value will not fit
;          or the unit has no decade; carry CLEAR otherwise
;   uses:  A, B, X, Y, U
;
; ABI_unit_apply is units.s's unit_apply: it indexes unit_decades with the code
; and multiplies by ten that many times, refusing on overflow. The code was put
; in tone_entry_unit by the key arm, which is the stock's $2221.
;
; A ZERO CODE MEANS NO UNIT KEY WAS PRESSED - Seq Index, Seq End, the tone
; number - and those must not be scaled. UNIT_BLANK is zero and unit_decades
; refuses it, so the test comes first rather than being left to unit_apply.
;
; FOR THE TIME FIELDS THIS LANDS MILLISECONDS, not counts: unit_decades gives
; s three decades and ms none. tone_commit's own millisecond ceiling and its
; multiply by TONE_MS_COUNTS both still follow, unchanged.
; ---------------------------------------------------------------------------
tone_entry_scale
                ; A TIME'S FRACTION IS TAKEN AFTER THE COUNTS CONVERSION, not
                ; before it. The instrument's time class carries the
                ; millisecond-to-counts factor in its own decade count, so
                ; entry_to_scaled_digits ($CDE1) applies (decades - fraction)
                ; in ONE step and 2 . 5 becomes 250 counts. Here the x100 is a
                ; separate multiply at tone_commit_not_word, so letting
                ; unit_apply take the fraction first truncated 25 to 2 and
                ; stored 2.00 ms. The fraction is put aside over the unit
                ; scaling and the commit's own divide spends it.
                ldb     >tone_field
                cmpb    #TONE_FIELD_ON
                beq     tone_entry_scale_hold
                cmpb    #TONE_FIELD_OFF
                bne     tone_entry_scale_unit
tone_entry_scale_hold
                lbsr    tone_time_unit_keep     ; WHICH UNIT IT WAS KEYED IN,
                                                ; before the scaling spends
                                                ; tone_entry_unit - the
                                                ; stock's $3C87/$3C89, set on
                                                ; the way to apply_time_entry
                                                ; ($638F) and kept whether the
                                                ; value is taken or refused
                lda     >entry_frac
                pshs    a
                clr     >entry_frac
                lbsr    tone_entry_scale_unit
                puls    a
                sta     >entry_frac
                rts
tone_entry_scale_unit
                lda     >tone_entry_unit
                beq     tone_entry_scale_none
                sta     >tone_unit_last         ; KEPT for the commit, which
                                                ; needs to know what the value
                                                ; was keyed in - see
                                                ; tone_commit_freq_ok. The
                                                ; clear below is right and is
                                                ; why there was nothing left
                                                ; to record.
                ldb     >tone_entry_unit
                ldx     #entry_result
                lbsr    ABI_unit_apply
                bcs     tone_entry_scale_bad
tone_entry_scale_none
                clr     >tone_entry_unit        ; one entry, one unit
                andcc   #~CC_CARRY
                rts
tone_entry_scale_bad
                clr     >tone_entry_unit
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; tone_entry_none - leave NO field armed
;
;   uses:  A
;
; entry_exit_restore_display ($B38B), whose two stores are CLR >$23A7 at $B391
; and CLR >$23A8 at $B394. $23A8 is the arm flag the digit path reads at $B494
; before it will take a key, and this firmware's entry_armed - $2199, declared
; with the rest of the shared entry state - is that flag: entry_begin sets it,
; and page0_screen.s's chan_key already gates its whole terminator-and-digit
; group on it with the same 'lb494' citation.
;
; numeric_entry_key_handler ($B3C2) calls it, with argument 1, for each of the
; five key codes keymap_menu_msgs_19_1d ($AEBB) answers - PHASE, WAVEFORM,
; AMPTD, FREQ and $2A - at $B48C, and for the state keys at $B45C, BEFORE the
; message is posted. NEXT and LAST are state keys, so the instrument leaves a
; record change with nothing armed, and the field key that follows is what
; arms the next field. That is why a number typed straight after NEXT does
; nothing on the instrument.
; ---------------------------------------------------------------------------
tone_entry_none
                clr     >entry_armed            ; $B394 CLR >$23A8
                clr     >entry_active           ; and nothing echoes either
                clr     >tone_entry_unit
                rts

; ---------------------------------------------------------------------------
; tone_entry_reset - the entry for the field in tone_field, at its own width
;
;   uses:  A, B, X
;
; THE ENTRY HALF OF AN ARM, WITHOUT THE CURSOR. Every place the stock arms a
; field calls this and then tone_show_armed below, which repaints and puts the
; cursor on; tone_key_enter_empty calls it alone, at the one moment this page
; empties the entry where the instrument arms nothing.
;
; THIS HEADER IS ALSO WHAT ENDS THE ROUTINE ABOVE IT. Without one, a bare
; label is read as an inner label of the previous routine and its body is
; scanned as part of it - tests/test_clobbers.py says so in its own comment,
; because that is how dds_reset's two undeclared `ldu` were missed. It
; reported tone_entry_none as destroying B while declaring only A, and the B
; was down here.
;
; The stock arms a field through begin_numeric_entry ($A415), and each of the
; six arms of the $465B table gives it that field's own width:
; freq_entry_field_geometry ($4574) eight digits, entry_field_amptd ($458D)
; five, entry_field_on_off_time ($45A6) six, tone_number_entry_field_geometry
; ($45D3) one for a keyed tone, entry_field_seq_index ($461B) and
; entry_field_seq_end ($4630) four - and the data cursor's own one, which
; arm_seq_edit_cursor ($7132) arms.
; ---------------------------------------------------------------------------
tone_entry_reset
                clr     >entry_active           ; a fresh field: nothing typed
                clr     >tone_entry_unit        ; and no unit key behind it yet
                ; EACH FIELD ITS OWN WIDTH, as the six arms of the $465B
                ; table set it: freq_entry_field_geometry ($4574) eight digits,
                ; entry_field_amptd ($458D) five, entry_field_on_off_time
                ; ($45A6) SIX, tone_number_entry_field_geometry ($45D3) one for
                ; a keyed tone, entry_field_seq_index ($461B) and
                ; entry_field_seq_end ($4630) FOUR - and the data cursor's own
                ; one, which arm_seq_edit_cursor ($7132) arms.
                lda     >tone_field
                cmpa    #TONE_FIELD_TONE
                beq     tone_entry_one
                cmpa    #TONE_FIELD_SEQDATA
                beq     tone_entry_one
                cmpa    #TONE_FIELD_SEQIDX
                beq     tone_entry_number
                cmpa    #TONE_FIELD_SEQEND
                beq     tone_entry_number
                cmpa    #TONE_FIELD_ON
                beq     tone_entry_time
                cmpa    #TONE_FIELD_OFF
                beq     tone_entry_time
                cmpa    #TONE_FIELD_AMPL
                beq     tone_entry_ampl
                ldb     #TONE_FREQ_DIGITS       ; the frequency's eight
                bra     tone_entry_armed
tone_entry_one
                ; ONE CHARACTER FROM THE PANEL, THREE DIGITS FROM THE BUS.
                ; $45D3 arms one at column $0F, or three at the same column
                ; when bit 3 of event_flags ($2204) - the remote state - is
                ; set; enter_tone_number ($640C) reads the same bit to choose
                ; between parse_hex_digit_pair on one keyed character and
                ; entry_to_scaled_digits on the typed number. RF_REMOTE is
                ; that bit here.
                ldb     #$01
                lda     >tone_field
                cmpa    #TONE_FIELD_SEQDATA     ; the cursor is one character
                beq     tone_entry_armed        ; whoever is driving
                lda     >rmt_flags
                bita    #RF_REMOTE
                beq     tone_entry_armed
                ldb     #TONE_NUM_DIGITS        ; three, and 15 needs two
                bra     tone_entry_armed
tone_entry_number
                ldb     #TONE_NUM_W             ; four, and 250 needs three of
                bra     tone_entry_armed        ; them
tone_entry_ampl
                ldb     #TONE_AMPL_W
                bra     tone_entry_armed
tone_entry_time
                ldb     #TONE_TIME_DIGITS       ; six, which is what $45A6 arms
tone_entry_armed
                lda     #ENTRY_DECIMAL
                lbsr    ABI_entry_begin

                ; AND A FIELD ARMED BY THE BUS IS NOT ARMED FOR THE PANEL.
                ; arm_numeric_entry_field ($AC35) has TWO paths and $AC5C
                ; chooses between them on bit 3 of event_flags ($2204), the
                ; remote state: SET takes $AC6B, which calls
                ; begin_numeric_entry ($A415) - the controller's own entry
                ; buffer - and never touches $23A8; CLEAR takes lac81 ($AC81),
                ; which is the one place in the ROM that stores 1 into it.
                ; So a bus field select opens a bus entry and leaves the
                ; PANEL's arm exactly as it found it.
                ;
                ; Driven on both, 2026-09-13, on the DTMF Sequence player
                ; record: 'SBP 999 MS;' leaves the stock's $23A8 at 00 and set
                ; this firmware's entry_armed to 01, and the next digit keyed
                ; after REN dropped echoed '0' over ' Continuous' where the
                ; instrument ignored it. The differential harness reported it
                ; as seed 21, step 17.
                ;
                ; The value still lands: the bus commits through remote.s's
                ; own pending-kind path and the request arms below, not
                ; through the panel's entry_armed gate.
                lda     >rmt_flags
                bita    #RF_REMOTE
                beq     tone_entry_panel
                clr     >entry_armed            ; $AC6B's path: no $23A8
tone_entry_panel
                rts

; ---------------------------------------------------------------------------
; tone_show_armed - the page repainted, then the field's cursor on
;
;   uses:  whatever tone_show uses, then A, B, X
;
; EVERY ARM ON THIS PAGE REACHES arm_numeric_entry_field ($AC35) BY ONE OF TWO
; ROUTES, and both end with the cursor on the field. select_entry_field
; ($4567), the vector at $3C0E, picks the field's locals out of the $465B
; table and joins the tail l4667, whose LBSR $ac35 is at $4681; the data
; cursor has its own, arm_seq_edit_cursor ($7132), LBSR at $7158. The third
; word each pushes is $23AD, the cell $AC98 puts the cursor on, and
; tone_field_arm has those cells. Neither route does anything to the cursor
; while remote ($AC5C-$AC67), and entry_cursor_on makes the same test.
;
; THE REPAINT COMES FIRST AND THE ARM LAST, because painting moves the
; display's address and the arm is what puts it back on the field: the stock's
; arms are called after their painters (commit_seq_end_and_repaint ($7370) is
; $738C repaint_sequence_page and then $73A7's [$3C0E]; softkey_delete_step
; is $7298 and then $72A2). This page's arms reset the entry and then painted,
; so the cursor, once it existed, came up wherever the last character went.
; Each arm is tone_entry_reset and then this.
; ---------------------------------------------------------------------------
tone_show_armed
                lbsr    tone_show
                lbra    tone_field_arm          ; $AC98 and $ACA6

; ---------------------------------------------------------------------------
; tone_field_arm - the cursor on the field in tone_field, where the stock's
;                  arm puts it
;
;   uses:  A, B, X
;
; The value positions, from the arms of $465B (the third word each pushes on
; its way to l4667): freq_entry_field_geometry ($4574) $19,
; entry_field_amptd ($458D) $1E, entry_field_on_off_time ($45A6) $4B with
; $3D1C = 0 and $60 with it set, tone_number_entry_field_geometry ($45D3)
; $0F, entry_field_seq_index ($461B) [$3D36] - $0E on the sequence editor -
; and entry_field_seq_end ($4630) $4C; and arm_seq_edit_cursor ($7132)
; pushes $15 + $3D3B, the cell of the window the cursor step occupies.
; TONE_FIELD_ON and TONE_FIELD_OFF are the two halves $3D1C chooses between,
; and the window cell is the cursor step less the window's first step, which
; is what $3D3B holds.
; ---------------------------------------------------------------------------
tone_field_arm
                lda     >tone_field
                cmpa    #TONE_FIELD_SEQDATA
                beq     tone_field_arm_cell
                cmpa    #TONE_FIELD_TONE
                bhi     tone_field_arm_none     ; no field past the table
                ldx     #tone_field_cells
                lda     a,x                     ; $23AD
                lbra    ABI_entry_cursor_on
tone_field_arm_cell
                ldd     >tone_cursor            ; $15 + $3D3B: the step less
                subd    >tone_window            ; the window origin
                tfr     b,a
                adda    #TONE_SEQ_WIN_POS
                lbra    ABI_entry_cursor_on
tone_field_arm_none
                rts

; the cell each field's arm hands $AC35, indexed by TONE_FIELD_*
tone_field_cells
                fcb     TONE_FREQ_POS           ; 0 FREQ     $4574: $19
                fcb     TONE_ON_POS             ; 1 On       $45A6: $4B
                fcb     TONE_OFF_POS            ; 2 Off      $45A6: $60
                fcb     TONE_AMPL_POS           ; 3 AMPTD    $458D: $1E
                fcb     TONE_SEQ_IDX_POS        ; 4 Seq Idx  $461B: $0E
                fcb     TONE_SEQ_END_POS        ; 5 Seq End  $4630: $4C
                fcb     TONE_NUM_POS            ; 6 Tone     $45D3: $0F

; ---------------------------------------------------------------------------
; tone_entry_echo - show the digits typed so far, in the selected field
;
;   uses:  A, B, X, Y, U
;
; NOTHING ECHOED AT ALL. tone_show paints the values that are STORED, and the
; digit path repainted with it - so an operator typing into this screen saw
; the old value sitting there until ENTER, with no way to check what they had
; keyed. The channel screen has had chan_entry_echo since it was written; this
; screen simply never got one, and the field cursor that made the softkeys
; select rather than commit is what made it matter.
;
; It runs AFTER tone_show, because tone_show rewrites the whole label row
; before it writes any value into it.
; ---------------------------------------------------------------------------
tone_entry_echo
                ; EVERY FIELD ECHOES IN ITS OWN CELLS. The four the stock
                ; arms are the FREQ eight at $19, the AMPTD five at $1E, the two
                ; times six at $4B and $60, the tone number one at $0F, Seq
                ; Index and Seq End four at $0E and $4C, and the data cursor ONE
                ; at $15 plus its offset in the window - arm_seq_edit_cursor
                ; ($7132) computes that column as $0015 + $3D3B.
                ;
                ; Everything but those first four fell to the FREQ arm here,
                ; eight characters at $19 - which lands on cells 4 to 11 of the
                ; sequence window, so typing in the editor blanked the middle of
                ; the sequence on the glass while the data underneath was right.
                ; AND TWO OF THEM HAVE NOTHING TO ECHO. The tone number and
                ; the data cursor are single HEX characters that store as they
                ; are keyed - tone_key_hexfield - so what tone_show has just
                ; painted in those cells IS what was typed. Rendering the
                ; entry buffer over them would blank the character, the buffer
                ; being empty.
                ; NOTHING TYPED, NOTHING ECHOED. The instrument's echo is
                ; written by numeric_entry_key_handler ($B3C2) at $B4D0 and
                ; $B53D - both of them on the path of a key it has ACCEPTED -
                ; so a field that is armed with an empty buffer shows the
                ; STORED value that its own painter has just put there. $23A7,
                ; the "an entry is under way" flag, is what tells the two
                ; apart, and entry_active is that flag here.
                ;
                ; This echoed an empty buffer as its own width in zeros.
                ; Driven on both, 2026-09-13, on the tone record: FREQ then
                ; INC SET leaves the instrument reading 'FREQ' plus its
                ; increment marker and '   100.0   Hz', and left this
                ; firmware reading 'FREQ 00000000   Hz' - eight rendered
                ; digits of an empty buffer over the increment tone_show had
                ; just painted.
                tst     >entry_active
                beq     tone_echo_none

                lda     >tone_field
                cmpa    #TONE_FIELD_TONE
                beq     tone_echo_none
                cmpa    #TONE_FIELD_SEQDATA
                beq     tone_echo_none
                cmpa    #TONE_FIELD_ON
                beq     tone_echo_on
                cmpa    #TONE_FIELD_OFF
                beq     tone_echo_off
                cmpa    #TONE_FIELD_AMPL
                beq     tone_echo_ampl
                cmpa    #TONE_FIELD_SEQIDX
                beq     tone_echo_seqidx
                cmpa    #TONE_FIELD_SEQEND
                beq     tone_echo_seqend
                lda     #TONE_FREQ_POS
                ldb     #TONE_FREQ_W
                lbsr    tone_echo_write
                lda     #TONE_FREQ_UNIT         ; and its 'kHz' with them
                ldb     #TONE_FREQ_UNIT_W
                bra     tone_echo_unit
tone_echo_none
                rts
tone_echo_seqidx
                lda     #TONE_SEQ_IDX_POS
                ldb     #TONE_NUM_W
                bra     tone_echo_write
tone_echo_seqend
                lda     #TONE_SEQ_END_POS
                ldb     #TONE_NUM_W
                bra     tone_echo_write
tone_echo_on
                lda     #TONE_ON_POS
                ldb     #TONE_TIME_DIGITS
                lbsr    tone_echo_write
                lda     #TONE_ON_UNIT           ; and the 'ms' beside it
                ldb     #TONE_UNIT_W
                bra     tone_echo_unit
tone_echo_off
                lda     #TONE_OFF_POS
                ldb     #TONE_TIME_DIGITS
                lbsr    tone_echo_write
                lda     #TONE_OFF_UNIT
                ldb     #TONE_UNIT_W
                bra     tone_echo_unit
tone_echo_ampl
                lda     #TONE_AMPL_POS          ; COLUMN $1E, AND EVERYTHING
                                                ; FROM IT TO THE END OF THE
                                                ; LINE. Driven on the stock
                                                ; 2026-09-12: with the level
                                                ; reading '   140 uV', typing 2
                                                ; leaves '2' at column 30 and
                                                ; columns 31 to 39 blank - the
                                                ; unit label wiped with the
                                                ; old digits, because the unit
                                                ; is what the next key will
                                                ; say. This wrote eight
                                                ; columns from 31, so the old
                                                ; value's '140' stood beside
                                                ; the typed digit and the
                                                ; operator read 2 and 140 at
                                                ; once.
                ldb     #TONE_AMPL_W            ; five rendered columns, and
                lbsr    tone_echo_write         ; then the unit's own five
                lda     #TONE_AMPL_POS+TONE_AMPL_W
                ldx     #tone_ampl_echo_pad     ; blanked - entry_render fills
                ldb     #TONE_AMPL_ECHO_W-TONE_AMPL_W
                lbra    ABI_lcd_write_raw       ; only entry_width characters
                                                ; and leaves the rest of the
                                                ; buffer as it found it, which
                                                ; put the old '140' and two
                                                ; NULs on the line beside the
                                                ; typed digit
; THE UNIT LABEL GOES BLANK WITH THE OLD VALUE, and this is the stock's own
; second geometry rather than a flourish. arm_numeric_entry_field ($AC35)
; keeps TWO pairs: the value column $23AD with its width $23A5, and a UNITS
; column $23AF with a width $23AE that the units-class argument sets - classes
; 0, 1 and 2 give 0 ($AD21 CLR >$23AE), 3 and 6 give 3 ($AD09 LDB #$03), 4 and
; 5 give 2 ($AD11) and 7 gives 1 ($AD19). numeric_entry_key_handler ($B3C2)
; writes that blank run ONCE, at $B524-$B538, on the first character of an
; entry - the $23A7 test at $B517 is what makes it once - because until a unit
; key ends the entry the old label is a lie about the digits on the line.
;
; This screen's arms give the columns: freq_entry_field_geometry ($4574) is
; class 6 with units column $23, entry_field_on_off_time ($45A6) class 5 with
; $51 or $66, entry_field_amptd ($458D) class 4 with $24, and the tone number,
; Seq Index and Seq End are classes 0 and 2 - width zero, no unit to blank.
;
; Driven on both, 2026-09-13, on the tone record with FREQ reading
; '1.000 kHz': typing 7 leaves the instrument at 'FREQ 7' with columns 26 to
; 39 blank and left this firmware at 'FREQ 7         kHz', the old unit
; standing over a value that was no longer in that unit. The differential
; harness reported it as seed 18, step 1, on the decimal point.
tone_echo_unit
                ldx     #tone_ampl_echo_pad     ; five blanks; three and two
                lbra    ABI_lcd_write_raw       ; are taken from the front -
                                                ; glass only, as $B524-$B538

tone_echo_write                                 ; the point's column among them
                pshs    a,b                     ; among them
                ldx     #text_buffer
                lbsr    ABI_entry_render        ; entry_width characters,
                puls    a,b                     ; left-aligned and blank
                ldx     #text_buffer            ; padded
                lbra    ABI_lcd_write_raw       ; the echo: glass only, as
                                                ; lcd_write_string_at ($D8A5)

; ---------------------------------------------------------------------------
; tone_gate_write - set the output gate plainly: one register, no pulse
;
;   entry: B = TONE_GATE_ON or TONE_GATE_OFF
;   uses:  A, B, X, Y
;
; DDS register $22, which common/formats.inc names DDS_PORT_MUX_01, written
; on its own. That is what the stock does everywhere EXCEPT at a tone or gap
; edge of a running sequence: dds_set_output_mode_reg22 ($6B92) turns a zero
; argument into $21 and a non-zero one into $20 when $3C03 is clear (tone
; mode) and hands the byte to dds_write_reg22 ($6B6F), which stores the
; shadow $24BB and calls $DE6F for register $22 alone. seq_output_stop
; ($4881), sequence_mode_init ($5380), seq_mode_exit ($51E3) and
; seq_mode_defaults ($5224) each CLRB before that call; seq_enter_manual_mode
; ($49C0) loads LDB #$01 at $49D1 before its call at $49DC - so a stop, a mode entry and a manual-mode entry
; are all this plain write. The ISR's single-shot end at $436D is the same
; write from interrupt context: LDA #$22 / LDB #$21 / STB $3D33 / STD $0200.
;
; No guard: none of those paths compares with $3D33 first, and a guard here
; would trust tone_gate against a register other modules also write.
; tone_output_stop calls this from the stop tick, through tone_stop_from_isr,
; so it stays one register write. The edge stream, which IS guarded, is
; tone_gate_edge below.
; ---------------------------------------------------------------------------
tone_gate_write
                stb     >tone_gate
                clra
                tfr     d,x                     ; X = the value
                ldb     #DDS_PORT_MUX_01
                lbra    ABI_dds_write

; ---------------------------------------------------------------------------
; tone_gate_edge - a tone or gap edge: the stock's register stream
;
;   entry: B = TONE_GATE_ON, TONE_GATE_ON_DTMF or TONE_GATE_OFF
;   uses:  A, X
;
; THE STOCK'S NMI BODY AT $4331-$436C, read from its instruction stream. ASRA
; on the phase byte $3D32 selects B = $20 (carry set: the on phase) or $21;
; CMPB >$3D33 / BEQ at $433F skips everything below when the value has not
; changed, so a run of steps without gaps sends nothing at all; STB >$3D33
; records it. Then, at $4351 and in this order:
;
;     $4351  LDX #$2221 / STX $0200      register $22 <= $21   gate closed
;     $4357  LDX #$2603 / STX $0200      register $26 <= $03   bit 3 low
;     $435D  LDA #$0B   / STA $0201      register $26 <= $0B   bit 3 high
;     $4362  LDA #$22   / STD $0200      register $22 <= B     the new value
;
; The third write reaches $0201 with $26 still selected by the second, and
; so does this one: one byte to the data port, no select. The sequence is
; identical for a tone-on edge and a gap edge: the CMPB #$21 / BNE at $4347
; steps over six NOPs at $434B-$4350 and nothing else. The dialled body at
; $44A6-$44CF is the same stream with $22 in place of $20.
;
; STRAIGHT TO THE PORT, as the stock's body writes it. These four words went
; through ABI_dds_write - lock, mask, width lookup, shadow - at about 41
; instructions each, 165 of a tick measured at 391-416 against a period of
; 422 at the default 1.00 ms, and the tick did not fit: one time-out in three
; found it still running and was dropped (seed 2 of the differential harness,
; 2026-09-14). dtmf_gate_write in page1_dtmf.s was put straight to the port
; for the same reason on 2026-09-13. The tick owns the port while it runs -
; tone_advance reaches it only with dds_lock clear, and the tick is now the
; body's ONLY caller: manual stepping used to run it from the foreground under
; dds_lock and no longer enters it at all.
;
; WHAT IS GIVEN UP IS WHAT THE STOCK GIVES UP: dds_shadow no longer follows
; registers $22 and $26 when a tick writes them. The stock's body does not
; touch its shadow bytes either, so a later foreground read of either
; register - port_route in modulation.s for $22, dds_phase_reset_now in dds.s
; for $26 - sees what the foreground last set, on both firmwares.
; The gate is therefore CLOSED while the phase-reset bit is pulsed and opened,
; or left closed, only afterwards - so the order is kept exactly.
;
; Unlike dds_phase_reset in dds.s this does not consult special function 1:
; there is no test of the special flags anywhere in $4331-$436C, and the
; stock's vetoed pulse ($DEB6) is what output_tone ($6A95) uses for a tone
; sounded OUTSIDE a run, through dds_update_strobe_if_idle ($4AD1).
;
; This runs from the tick, so it must not be slow and must not paint.
; ---------------------------------------------------------------------------
tone_gate_edge
                cmpb    >tone_gate              ; $433F: unchanged, no write
                beq     tone_gate_edge_done
                stb     >tone_gate              ; $4344: STB >$3D33 - and B
                                                ; STAYS LIVE to the last store
                ldx     #DDS_PORT_MUX_01*256+TONE_GATE_OFF
                stx     >dds_prog               ; $4351: $22 <= $21
                ldx     #DDS_PULSE*256+TONE_EDGE_PULSE_LOW
                stx     >dds_prog               ; $4357: $26 <= $03
                lda     #TONE_EDGE_PULSE_HIGH
                sta     >dds_prog_data          ; $435D: $26 <= $0B
                lda     #DDS_PORT_MUX_01
                std     >dds_prog               ; $4362: $22 <= the value
tone_gate_edge_done
                rts

; ---------------------------------------------------------------------------
; tone_gate_edge_dtmf - a dialled tone or gap edge: blk444c's own stream
;
;   entry: B = TONE_GATE_ON_DTMF or TONE_GATE_OFF
;   uses:  A, X
;
; $44A6-$44CF, instruction for instruction:
;
;     $44A6  CMPB >$3D33 / BEQ $44E6     unchanged: nothing is sent
;     $44AB  STB >$3D33
;     $44AE  CMPB #$21 / BNE $44B9       the SEVEN NOPs at $44B2-$44B8 are
;                                        taken only when the gate CLOSES
;     $44B9  LDX #$2221 / STX $0200      register $22 <= $21
;     $44BF  LDX #$2603 / STX $0200      register $26 <= $03
;     $44C5  LDA #$0B   / STA $0201      register $26 <= $0B, still selected
;     $44CA  LDA #$22   / STD $0200      register $22 <= B
;
; It is tone_gate_edge's stream with $22 for the tone and SEVEN NOPs where the
; tone body at $434B has six - the two bodies are two copies in the ROM, and
; they are two here so each keeps its own count. What the NOPs are for is not
; established; what they do is measurable: the closing edge lands seven
; instructions further into its tick than the opening edge, so the gate
; stands open for the period plus seven, which dtmf_gate_write in
; page1_dtmf.s already holds for the manual dial against the same body.
;
; The compare is against tone_gate, the sequence player's copy of $3D33, and
; not against dtmf_gate, which is the manual dial's: tone_start clears
; tone_gate and tone_gate_write sets it on every stop, and those are the
; writes this compare has to agree with.
;
; Straight to the port for the reason tone_gate_edge gives: this runs in the
; tick, which holds the port once tone_advance has found dds_lock clear.
; ---------------------------------------------------------------------------
tone_gate_edge_dtmf
                cmpb    >tone_gate              ; $44A6
                beq     tone_gate_edge_dtmf_done
                stb     >tone_gate              ; $44AB - B STAYS LIVE to the
                                                ; last store
                cmpb    #TONE_GATE_OFF          ; $44AE
                bne     tone_gate_edge_dtmf_stream
                nop                             ; $44B2-$44B8
                nop
                nop
                nop
                nop
                nop
                nop
tone_gate_edge_dtmf_stream
                ldx     #DDS_PORT_MUX_01*256+TONE_GATE_OFF
                stx     >dds_prog               ; $44B9: $22 <= $21
                ldx     #DDS_PULSE*256+TONE_EDGE_PULSE_LOW
                stx     >dds_prog               ; $44BF: $26 <= $03
                lda     #TONE_EDGE_PULSE_HIGH
                sta     >dds_prog_data          ; $44C5: $26 <= $0B
                lda     #DDS_PORT_MUX_01
                std     >dds_prog               ; $44CA: $22 <= the value
tone_gate_edge_dtmf_done
                rts

; ---------------------------------------------------------------------------
; tone_hand_pulse - the strobe a tone stepped by hand gets, unless vetoed
;
;   uses:  A, B, X, Y
;
; WHAT THE STOCK DOES WHEN THE OPERATOR STEPS A TONE BY HAND. In manual mode
; - $3D11 = $000B, which seq_enter_manual_mode ($49C0) stores - the up and
; down keys reach arm [10] of the $697F table step_active_field ($666D)
; dispatches through, step_seq_index_manual ($68E2), and a typed position
; plus ENTER reaches arm [10] of the $6650 table of dispatch_entry_complete
; ($6282), apply_seq_entry_manual ($64AC). Both end the same way: tone_at_cursor
; ($6D66) for the tone at the new position, then output_tone ($6A95)(tone,
; $3C80), the byte at $3C80 loaded into U and the tone into Y before PSHS
; X,Y,U. output_tone in tone mode ($3C03 zero) calls write_reg15_nibble
; ($E7C4) - the tone's low nibble into DDS register $15 through
; dds_param_store ($DD9D), bit 4 ORed in only when the $3C80 argument is
; non-zero - and then at $6ADB dds_update_strobe_if_idle ($4AD1). That does
; LDB >$3C80 / CMPB #$00 / LBNE past everything while the sequencer is
; running; otherwise $4AE5 calls dds_reg26_pulse_if_flag1_clear ($DEB6),
; which tests bit 1 of the special flags (SPECIAL_NO_PHASE_RESET, dds.s) and, when it
; is clear, calls dds_reg26_bit3_pulse ($DE7F): dds_write_pair ($DE6F) at
; $DE99 with register $26 and the shadow $24BF ANDed $F7, then at $DEAE with
; register $26 and the shadow untouched. A one-shot low pulse on bit 3 of
; register $26, after the tone has been selected.
;
; Manual mode implies $3C80 = 0. key_manual ($4F5A) tests $3C80 first and
; calls seq_output_set_running ($4702)(0) when it is set, which does CLR of
; the flag through its zero branch; softkey_seq_output ($49EE) enters manual
; mode only when $3C80 is zero. So a hand step always reaches the veto, and
; a running sequence never does - its strobe is the NMI body's own edge
; stream, tone_gate_edge. tone_advance keeps that split: it calls this only
; in TONE_MANUAL, never from the tick.
;
; The pulse is dds.s's dds_phase_reset - dds_reg26_bit3_pulse ($DE7F) behind
; the $DEBC veto - reached through ABI slot 72, the same routine the DTMF
; screen's dtmf_phase_pulse reaches. The rewrite's tone step is a tuning word
; programmed through ABI_freq_program rather than a slot number in register
; $15, so the $E7C4 half of output_tone has no register to write here; the
; strobe that follows it is what was missing.
; ---------------------------------------------------------------------------
tone_hand_pulse
                lbra    ABI_dds_phase_reset

; ---------------------------------------------------------------------------
; The selected field, and what the softkeys, INCR SET and the arrows do to it
;
; THE STOCK SELECTS, THEN COMMITS. $3C8F is its field cursor and
; key_freq_field, key_amptd_field and key_select_off_time are the arms that
; move it; every commit and every step then acts on whichever is selected.
; The softkeys here used to commit directly, which works with three fields and
; three keys but leaves INCR SET and the arrows nothing to act on - and those
; are the keys an operator uses to walk a frequency up while listening.
; ---------------------------------------------------------------------------
TONE_FIELD_FREQ equ     0
TONE_FIELD_ON   equ     1
TONE_FIELD_OFF  equ     2
TONE_FIELD_SEQIDX equ   4               ; Seq Index and Seq End, the sequence
TONE_FIELD_SEQEND equ   5               ; editor's two typed fields - the stock
                                        ; puts them on f1 and f2 of that screen
                                        ; (softkey_seq_index and
                                        ; key_select_seq_end, words [1] and [2]
                                        ; of the record at $417F)
; Indexed by TONE_FIELD_*: FREQ 0, ON 1, OFF 2, AMPL 3, SEQIDX 4, SEQEND 5,
; TONE 6.
tone_field_class
                fcb     TONE_CLASS_FREQ         ; 0 FREQ
                fcb     TONE_CLASS_TIME         ; 1 On Time
                fcb     TONE_CLASS_TIME         ; 2 Off Time
                fcb     TONE_CLASS_VOLTS        ; 3 AMPL
                fcb     TONE_CLASS_ENTER        ; 4 Seq Index
                fcb     TONE_CLASS_ENTER        ; 5 Seq End
                fcb     TONE_CLASS_NONE         ; 6 the tone number
TONE_CLASS_FIELDS equ   7               ; the class table's length

; $B212 TRANSPOSED: three bytes per class for deg, Hz and kHz in that order,
; TONE_UNIT_NONE where the class's arm returns zero and the key beeps.
tone_class_units
                fcb     TONE_UNIT_NONE,TONE_UNIT_NONE,TONE_UNIT_NONE ; 0 choice
                fcb     TONE_UNIT_NONE,TONE_UNIT_NONE,TONE_UNIT_NONE ; 1 unused
                fcb     TONE_UNIT_NONE,TONE_UNIT_NONE,TONE_UNIT_NONE ; 2 ENTER
                fcb     UNIT_DEG,TONE_UNIT_NONE,TONE_UNIT_NONE ; 3 $B0F3
                fcb     UNIT_MICROVOLT,UNIT_MILLIVOLT,UNIT_VOLT ; 4 $B127
                fcb     TONE_UNIT_NONE,UNIT_MILLISEC,UNIT_SECOND ; 5 $B169
                fcb     TONE_UNIT_NONE,UNIT_HZ,UNIT_KHZ ; 6 $B19D
                fcb     UNIT_PERCENT,TONE_UNIT_NONE,TONE_UNIT_NONE ; 7 $B1D1

TONE_FIELD_SEQDATA equ  7               ; THE DATA CURSOR inside the sequence
                                        ; window, which is the stock's $3D11 =
                                        ; 9: arm_seq_edit_cursor ($7132) arms a
                                        ; one-character field at $0015 + $3D3B
                                        ; and step_seq_field ($744B) is what the
                                        ; arrows reach with it
TONE_FIELD_TONE equ     6               ; the TONE NUMBER, which HRA selects:
                                        ; the stock's key_select_tone_number
                                        ; ($4EE0) is a call to
                                        ; softkey_tone_number ($47FA), which
                                        ; sets its field id to $0007
TONE_WIDTH_WORD equ     4               ; a field width meaning "a plain 16-bit
                                        ; number", as against 1 a byte, 2 a
                                        ; duration in timer counts and 3 a
                                        ; 24-bit tuning word
; --- THE UNITS CLASS OF EACH FIELD, which is the stock's $23AB -------------
; The channel screen's mechanism, applied to the sequence screens. On the
; instrument a numeric field is COMMITTED BY ITS UNIT KEY and the key says what
; the digits meant: arm_numeric_entry_field ($AC35) stores the class at $AC46,
; accept_units_key ($B0C1) dispatches on it through the table at $B212, and
; check_entry_terminator ($B070) returns 0 for every class but 0 - so nothing
; else ends the entry. The sequence screens' own field table is $465B:
;
;   FREQ         class 6   Hz and kHz            $612D, W=4
;   AMPTD        class 4   deg uV, Hz mV, kHz V  $61AA, W=6
;   On/Off time  class 5   Hz = ms, kHz = s      read_time_entry, W=$0A
;   Seq Index    class 2   ENTER alone
;   Seq End      class 2   ENTER alone
;   tone number  class 0   one keypress commits
;
; THE TIME FIELDS ARE THE ONE THAT NEEDS CARE. unit_decades lands a time in
; MILLISECONDS - s is three decades, ms is none - while these cells hold TIMER
; COUNTS at the 10 us tick. That is not a mismatch to work around: tone_commit
; already multiplies by TONE_MS_COUNTS after its millisecond ceiling, so the
; unit is applied BEFORE that ceiling and both the check and the conversion are
; left exactly as they were.
TONE_CLASS_NONE equ     0               ; a choice field: one keypress
TONE_CLASS_ENTER equ    2               ; ENTER alone, and no unit
TONE_CLASS_VOLTS equ    4               ; deg = uV, Hz = mV, kHz = V
TONE_CLASS_TIME equ     5               ; Hz = ms, kHz = s
TONE_CLASS_FREQ equ     6               ; Hz and kHz
TONE_CLASS_KEYS equ     3               ; deg, Hz, kHz - the table's width
; units.s declares UNIT_REFUSE for unit_decades' own use, but that is another
; image and its equates are not visible here; only the UNIT_* codes are shared.
; Same value, named where it is used.
TONE_UNIT_NONE  equ     $FF

TONE_FIELD_AMPL equ     3               ; the channel's output level, not the
                                        ; step's - see tone_key_ampl
TONE_FIELDS     equ     4

; ---------------------------------------------------------------------------
; tone_select_field - a softkey chose a field
;
;   entry: A = TONE_FIELD_FREQ, _ON or _OFF
;   uses:  A, B, X, Y, U
; ---------------------------------------------------------------------------
tone_select_field
                clr     >tone_manual_sel        ; another field: not Manual's
                sta     >tone_field
                clr     >tone_incr_mode         ; selecting a field cancels a
                                                ; pending INCR SET, so an
                                                ; armed increment cannot land
                                                ; on a field the operator has
                                                ; since moved away from
                lbsr    tone_entry_reset        ; a fresh field to type into
                lbra    tone_show_armed

; ---------------------------------------------------------------------------
; tone_incr_address - where the selected field's increment lives
;
;   exit:  X = it; B = how many bytes wide the FIELD is, 3 or 1
;   uses:  A, B, X
; ---------------------------------------------------------------------------
tone_incr_address
                lda     >tone_field
                cmpa    #TONE_FIELD_ON
                beq     tone_incr_on
                cmpa    #TONE_FIELD_OFF
                beq     tone_incr_off
                cmpa    #TONE_FIELD_AMPL
                beq     tone_incr_ampl
                ldx     #incr_tone_freq
                ldb     #3
                rts
tone_incr_ampl
                ldx     #incr_ampl_ch           ; TONE_CHANNEL is 0, so the
                                                ; first element - the SAME
                                                ; step the channel screen
                                                ; moves channel 0 by, which is
                                                ; one channel setting shown on
                                                ; two screens. It is no longer
                                                ; the step the OTHER three
                                                ; channels move by: the stock
                ldb     #3                      ; screen steps this level by:
                rts                             ; it is one channel setting
                                                ; shown on two screens, and
                                                ; two increments for it would
                                                ; step differently depending
                                                ; on which screen was up
tone_incr_on
                ldx     #incr_tone_on           ; A WORD of milliseconds, like
                ldb     #TONE_WIDTH_WORD        ; the time it steps
                rts
tone_incr_off
                ldx     #incr_tone_off
                ldb     #TONE_WIDTH_WORD
                rts

; ---------------------------------------------------------------------------
; tone_field_address - where the selected field of the current step lives
;
;   exit:  X = it; B = its width, 3 or 1
;   uses:  A, B, X
; ---------------------------------------------------------------------------
tone_field_address
                pshs    a
                lda     >tone_field             ; THE LEVEL IS NOT IN THE STEP
                cmpa    #TONE_FIELD_AMPL        ; TABLE, so its address is
                beq     tone_field_at_ampl      ; worked out before the step
                lda     >tone_field             ; address is
                cmpa    #TONE_FIELD_SEQIDX
                beq     tone_field_at_seqidx
                cmpa    #TONE_FIELD_SEQEND
                beq     tone_field_at_seqend
                cmpa    #TONE_FIELD_TONE
                beq     tone_field_at_tone
                cmpa    #TONE_FIELD_ON
                beq     tone_field_at_on
                cmpa    #TONE_FIELD_OFF
                beq     tone_field_at_off
                ldb     >tone_number            ; the FREQUENCY of the tone
                lbsr    tone_freq_address       ; this step names
                puls    a
                ldb     #3
                rts
tone_field_at_ampl
                lbsr    tone_channel_record     ; X = TONE_CHANNEL's record
                leax    CHAN_AMPL,x
                puls    a
                ldb     #3
                rts
tone_field_at_seqidx
                ldx     #tone_cursor
                puls    a
                ldb     #TONE_WIDTH_WORD
                rts
tone_field_at_seqend
                ldx     #tone_end
                puls    a
                ldb     #TONE_WIDTH_WORD
                rts
tone_field_at_tone
                ldx     #tone_number            ; one byte, 0..15
                puls    a
                ldb     #$01
                rts
tone_field_at_on
                ldb     >tone_number            ; the TONE's durations, shared
                lbsr    tone_times_address      ; by every step naming it.
                puls    a                       ; TONE_ON is offset zero, so
                                                ; X already points at it
                ldb     #2                      ; A WORD OF TIMER COUNTS, where
                rts                             ; it was one byte of ms
tone_field_at_off
                ldb     >tone_number
                lbsr    tone_times_address
                leax    TONE_OFF,x
                puls    a
                ldb     #2
                rts

; ---------------------------------------------------------------------------
; tone_time_accept - may this value go into the selected time cell?
;
;   entry: Y = the millisecond value about to be stored, X = the cell
;
;   IT TAKES A WORD, and used to take a byte in A. The value it guards runs to
;   TONE_MS_MAX = 655, so 256 and 512 are legal times whose LOW byte is zero -
;   and the entry path handed it that low byte. Typing 256 into a time whose
;   partner was zero was refused as 'On & Off times cannot both be 0', while
;   255 and 257 were accepted.
;
;   IN Y, NOT IN D, and that matters: the caller is holding the field's WIDTH
;   in B and stores through it afterwards. Passing the value in D put the
;   value's low byte there, so a 256 - low byte zero - gave a width of zero,
;   which is neither of the two the store knows, and the value went to the
;   wrong arm. Y is free at both call sites.
;   exit:  carry CLEAR to store it; carry SET, with the error raised, to
;          leave the stored value standing
;   uses:  A
;
; B and X are preserved across it - pshs/puls - because the caller is about to
; store through them. A is not: reading the partner word takes D, and A held
; only the value already tested on entry.
;
; THE STOCK'S FLOOR ON A TIME: validate_gate_time ($6033). It runs after every
; store into an On or Off time - apply_time_entry ($638F) calls it at $63B2
; for a typed value and step_on_off_time ($67F0) at $6854 for a stepped one,
; both passing the old value - and it does LDD #$0050 / STD 4,S, replaced by
; #$0064 when $3C03 (the DTMF flag) is set, then LDX [$3D13] / CMPX 4,S /
; LBCC: a time at or above 80 counts is accepted. Below that there are two
; refusals, each restoring the old value from $000A,S through [$3D13] and
; storing an error number in $3C02:
;     $60BB  error $32, when the value is non-zero;
;     $60AB  error $33, when it is zero AND the other word of the same $3C10
;            record is zero too. The record's other word is found by
;            comparing $3D13 with the record address ($6061-$6099), and a
;            zero with a non-zero partner is accepted by the LBNE at $60A0.
; Both callers then repaint through show_time_value_field ($5AAE), so the
; field shows the value that stood before, and the page-1 error byte reaches
; error_report_beep ($C3FE) at $514F like every other error on this page.
;
; WHAT A COUNT IS, so the floor can be stated in this file's milliseconds.
; The word validated is what the player loads straight into MC6840 timer 2:
; load_current_step ($4268) copies the record word to $3D30 at $42AD and the
; NMI body writes $3D30-1 to ptm_timer2 at $4309-$4310. Pages 1 and 2 arm
; that timer identically - start_sequence_timer ($6BD0) and page 2's
; start_sequence_clock both write $D1 to the CR2 shadow $2422 and out to
; $1001. read_time_entry ($6227) parses a time with decade class $0A (LDB
; #$0A at $622D), the class page 2's parse_entry_u16 ($4BF6) uses for its
; period, and page 2's display_period ($4864), executed, prints 100 as
; "1.00 ms" - the measurement TONE_MS_COUNTS records. So 80 counts is
; 0.80 ms, and 100 counts - the DTMF floor, and what seq_mode_defaults ($5224)
; seeds into both words of every record with LDD #$0064 - is 1.00 ms.
;
; TONE_ON and TONE_OFF hold TIMER COUNTS, a word each, and a
; millisecond is TONE_MS_COUNTS = 100 counts. The smallest non-zero time this
; screen can store is therefore 100 counts, above the 80-count floor, and the
; $32 refusal has no value here to fire on; it is not written out as a
; comparison whose outcome is fixed. What remains is the $33 arm, and this is
; it. The DTMF screen's floor is that screen's, in page1_dtmf.s.
;
; The number raised is ERR_TIME_BOTH_ZERO, $1A in common/formats.inc, this
; firmware's number for the stock's $33; this firmware's error numbers are its
; own (formats.inc), as they are for every other refusal in this file.
; ---------------------------------------------------------------------------
tone_time_accept
                cmpy    #0
                bne     tone_time_ok            ; non-zero: the floor is checked
                                                ; on the COUNTS, after the
                                                ; conversion - see
                                                ; tone_commit_time_floor
                pshs    b,x
                ldb     >tone_field
                cmpb    #TONE_FIELD_ON
                bne     tone_time_off_cell
                ldd     TONE_OFF-TONE_ON,x      ; X is the On word; the Off
                bra     tone_time_pair          ; word is TWO bytes after it,
                                                ; not one - both are sixteen
tone_time_off_cell                              ; bits of timer counts now
                ldd     TONE_ON-TONE_OFF,x      ; X is the Off word; the On
tone_time_pair                                  ; word is two bytes before it
                cmpd    #0
                bne     tone_time_pair_ok       ; a zero with a partner
                ldb     #ERR_TIME_BOTH_ZERO     ; $60AB: both zero
                lbsr    ABI_error_raise
                puls    b,x
                orcc    #CC_CARRY
                rts
tone_time_pair_ok
                puls    b,x
tone_time_ok
                andcc   #~CC_CARRY
                rts

; ---------------------------------------------------------------------------
; tone_commit - ENTER with digits typed: they belong to the selected field
;
;   uses:  A, B, X, Y, U
;
; INCR SET DIVERTS THE SAME ENTRY, one-shot, exactly as it does on the channel
; screen: the operator types a number and presses ENTER the same way, and only
; where it lands differs.
; ---------------------------------------------------------------------------
tone_commit
                tst     >entry_count            ; NO DIGITS - an entry emptied
                bne     tone_commit_digits      ; by BACKSPACE - stores nothing:
                ; EXCEPT ON SEQ INDEX AND SEQ END, where the empty parse is a
                ; refusal like any other. Measured 2026-09-17 on the Seq Index
                ; record: ENTER with nothing typed records $37 on Seq Index and
                ; $38 on Seq End and sounds the step at the cursor (register
                ; $15), also as the second ENTER after a commit; this did
                ; nothing (critique-6 finding A).
                lda     >tone_field
                cmpa    #TONE_FIELD_SEQIDX
                beq     tone_commit_seq_empty
                cmpa    #TONE_FIELD_SEQEND
                lbne    tone_commit_done
tone_commit_seq_empty
                orcc    #CC_CARRY               ; refused, as $7790 refuses it
                pshs    cc
                lbra    tone_commit_seq_checked
tone_commit_digits
                                                ; the stock's $CDE1 returns $FF
                                                ; and every arm skips on it
                lbsr    ABI_entry_value         ; carry set if it overflows
                lbcs    tone_commit_done        ; twenty-four bits

                ; THE DIGITS ARE IN THE UNIT THE KEY NAMED. Applied here, before
                ; every ceiling below, so those checks and the multiply by
                ; TONE_MS_COUNTS that follows them are left exactly as they
                ; were: a frequency arrives in 0.1 Hz, a level in microvolts,
                ; and a time in MILLISECONDS, which is the unit its ceiling is
                ; written in and the unit its conversion expects.
                ;
                ; This screen took the raw internal count on ENTER, so a typed
                ; 100 on the On Time meant one millisecond and there was no way
                ; to say seconds at all.
                lbsr    tone_entry_scale
                lbcs    tone_commit_done

                tst     >tone_incr_mode
                beq     tone_commit_value
                clr     >tone_incr_mode
                lbsr    tone_incr_address       ; X = the increment, B = width
                cmpb    #TONE_WIDTH_WORD
                lbne    tone_commit_store       ; the 24-bit ones are unchanged

                ; A TIME'S STEP IS BOUNDED LIKE A TIME. This went straight to
                ; tone_commit_store, which is reached BEFORE tone_commit_value
                ; and therefore before every ceiling on this screen - and its
                ; one-byte arm stored the low byte of what was typed. A step of
                ; 500 became 244, and 256, 512 and 768 became zero, so the
                ; arrow went dead while the field still showed the number. The
                ; cells are words now and the ceiling is the one the times
                ; themselves are held to.
                ldu     #entry_result
                lda     ,u                      ; the top byte of the entry
                lbne    tone_commit_incr_big
                ldd     1,u
                cmpd    #TONE_MS_MAX
                lbhi    tone_commit_incr_big
                std     ,x
                lbsr    tone_entry_reset        ; ITS OWN TAIL: this branched to
                lbra    tone_show_armed         ; tone_commit_stored, which
                                                ; opens with leas 1,s to drop
                                                ; the width byte
                                                ; tone_commit_store pushes -
                                                ; and this path never pushed
                                                ; one, so it took a byte of
                                                ; somebody else's frame with it
tone_commit_incr_big
                ldb     #ERR_TIME_RANGE         ; $32, the same refusal a time
                lbsr    ABI_error_raise         ; past the ceiling gets
                lbsr    tone_entry_reset
                lbra    tone_show_armed

tone_commit_value
                ; THE FREQUENCY CEILING, which the direct-commit path checked
                ; and this one must too. validate_store_frequency ($612D)
                ; rejects above $EA55 = 6,000,000 with error $35, and
                ; step_freq_value ($6683) re-checks the stepped result against
                ; the same constant.
                lda     >tone_field
                cmpa    #TONE_FIELD_AMPL        ; A LEVEL IS NOT STORED HERE.
                lbeq    tone_commit_ampl        ; ampl_set validates against
                                                ; the destination's own
                                                ; ceiling, stores it and
                                                ; programs the chip - three
                                                ; things a raw copy24 into the
                                                ; record does none of
                ; AND THE FREQUENCY IS THE ONLY FIELD THE CEILING BELOW IS FOR.
                ; This tested the AMPL comparison a SECOND time - lbeq above,
                ; bne here, off the same CMPA - so every field that was not
                ; AMPL went to the time path and the frequency block under it
                ; could not be reached at all. A tone frequency was then
                ; checked against TONE_MS_MAX: 50 Hz (500 in 0.1 Hz units)
                ; stored and 100 Hz (1000) was refused, so no step could be
                ; given a frequency at or above 65.6 Hz - on a screen whose
                ; whole subject is the frequency of each step.
                ; THE TONE NUMBER NEVER COMMITS HERE. From the panel it is a
                ; hex character that stores itself in tone_key_hexfield; from
                ; the bus a number and a unit, which remote.s's
                ; remote_set_tone bounds at $10 with error $36 as
                ; enter_tone_number ($640C) does at $6461. Neither reaches
                ; ENTER with digits typed on this field.
                cmpa    #TONE_FIELD_SEQIDX      ; the sequence editor's two
                lbeq    tone_commit_seq         ; fields are neither a time
                cmpa    #TONE_FIELD_SEQEND      ; nor a frequency
                lbeq    tone_commit_seq
                cmpa    #TONE_FIELD_FREQ
                lbne    tone_commit_time
                lbsr    tone_freq_in_range
                lbcs    tone_commit_big
tone_commit_freq_ok
                ; AND THE FIELD REMEMBERS THE UNIT IT WAS KEYED IN. The
                ; instrument keeps it: render_freq_field ($5826) takes the
                ; word at the record's +3 into $3D22 at $5855, and
                ; show_freq_field ($571F) renders SIX blanked zeros and a
                ; point after seven for $3D22 = 2, three blanked and a point
                ; after four for anything else - so one value reads
                ; '1000.0 Hz' or '1.000 kHz' depending on how it was typed.
                ;
                ; This firmware paints from tone_freq_unit and nothing wrote
                ; it, so the cell stayed at Hz and a frequency keyed in kHz
                ; came back in Hz. Driven on the emulator 2026-09-13: 'FREQ 1
                ; kHz' on the tone screen leaves the stock showing
                ; '1.000   kHz' and left this showing '1000.0   Hz'. Found by
                ; the differential harness on seed 1.
                ;
                ; tone_entry_unit is what the unit key just stored - see
                ; tone_key_unit - so the unit is in hand and only the value
                ; being IN RANGE decides whether it is kept. A refused entry
                ; leaves the field as it was, unit included.
                lda     >tone_unit_last
                sta     >tone_freq_unit
                lbra    tone_commit_field
tone_commit_time_big
                ; A TIME'S OWN REFUSAL, not the frequency's. validate_gate_time
                ; ($6033) reports $32, 'Time value out of range' - driven on
                ; the stock, 2 s and 50 s on a sequence time both answer it,
                ; where this answered $7B, 'Frequency exceeds limit'.
                ;
                ; AND THE TOP-BYTE ARM COMES HERE TOO. tone_commit_time's
                ; `lda >entry_result / bne` used to go to tone_commit_big -
                ; the tone FREQUENCY's refusal - so a time typed past sixteen
                ; bits was reported in the frequency's words. Driven
                ; 2026-09-13, f2 then the digits then the ms key:
                ;
                ;   typed      stock $23DE      this firmware before
                ;   70000      $32              $7B
                ;   99999      $32              $7B
                ;   123456     $32              $7B
                ;
                ; The value stands on both, so only the code was wrong; it is
                ; the code the operator reads off the glass.
                ldb     #ERR_TIME_RANGE
                lbsr    ABI_error_raise
                lbsr    tone_entry_reset
                lbra    tone_show_armed

; ---------------------------------------------------------------------------
; tone_time_unit_keep - remember which unit the time being committed was in
;
;   uses:  A, B, X
;
; tone_entry_unit is what the key arm put there, and the two cells are the
; stock's $3C87 and $3C89. A field that is neither time leaves them alone.
; ---------------------------------------------------------------------------
tone_time_unit_keep
                lda     >tone_field
                cmpa    #TONE_FIELD_ON
                beq     tone_time_unit_on
                cmpa    #TONE_FIELD_OFF
                bne     tone_time_unit_done
                ldb     #TONE_UNIT_OFF
                bra     tone_time_unit_put
tone_time_unit_on
                ldb     #TONE_UNIT_ON
tone_time_unit_put
                ldx     #tone_time_unit
                abx
                lda     >tone_entry_unit
                bne     tone_time_unit_store    ; ENTER with no unit key keeps
                lda     #UNIT_MILLISEC          ; the milliseconds default
tone_time_unit_store
                sta     ,x
tone_time_unit_done
                rts

tone_commit_big
                ldb     #ERR_FREQ_RANGE         ; this arm is the TONE FREQUENCY
                                                ; against TOP_FREQ, and the
                                                ; instrument's words for that are
                                                ; 'Frequency exceeds limit'
                lbsr    ABI_error_raise
                lbsr    tone_entry_reset
                lbra    tone_show_armed
tone_commit_seq
                ; SEQ INDEX AND SEQ END. They were reaching tone_commit_time,
                ; so a typed step was measured against TONE_MS_MAX - a time
                ; ceiling on a step number - and then handed to
                ; tone_time_accept, a gate-time validator.
                ;
                ; THIS IS WHERE THEY STORE. A typed Seq Index or Seq End is
                ; echoed digit by digit and committed only by the ENTER that
                ; reaches here - measured on the stock and set out at
                ; tone_key_digit. d6650's arms 7 and 9, commit_sequence_digit
                ; ($64FA), run enter_sequence_field ($7649) and then
                ; tone_at_cursor ($6D66) and output_tone ($6A95) whether the
                ; number was taken or refused: f1 '251' ENTER on the stock
                ; leaves the index at 1, pends $37 and still writes register
                ; $15.
                lbsr    tone_seq_store
                pshs    cc                      ; carry: refused
tone_commit_seq_checked
                ; AND ENTER SNAPS THE WINDOW ORIGIN TO THE INDEX. Measured
                ; on the stock: "f1 3" alone leaves the window at
                ; "[0123456789ABCDEF]" with Seq Index reading 3, and ENTER then
                ; moves it to "[23456789ABCDEF01]". That is
                ; enter_sequence_field ($7649) storing the index into $3D39 at
                ; $77CB, and it is what makes a TYPED index survive leaving the
                ; editor where a walked one does not - exit_sequence_edit
                ; ($7160) snaps the index back to the origin at $7175, so an
                ; origin that moved with it has nothing to undo. The snap is
                ; at l77a7, which the refusals at $7790 and $779D reach too,
                ; so a refused index puts the window back on the cursor that
                ; stands.
                lda     >tone_field
                cmpa    #TONE_FIELD_SEQIDX
                bne     tone_commit_seq_sound
                ldd     >tone_cursor
                std     >tone_window
tone_commit_seq_sound
                lbsr    tone_sound_at_cursor    ; $64FA: output_tone after
                puls    cc                      ; every commit, taken or not
                bcs     tone_commit_seq_refused
                lbsr    tone_entry_reset        ; TAKEN: the field is re-armed
                lbra    tone_commit_done        ; EMPTY, as $AC35's arm fills
                                                ; the buffer with spaces - so
                                                ; a second ENTER is refused
                                                ; $37 on the instrument
                                                ; (measured 2026-09-17: f1 3
                                                ; ENTER ENTER), where this
                                                ; committed the 3 again
tone_commit_seq_refused
                ; REFUSED: $37 for the index and $38 for the end, which is
                ; report_seq_range_error ($7629) choosing by $3D37 - pended
                ; in $3C02 and reported by the l5104 tail, after the sound.
                ; Measured on the stock: f1 '00005', f2 '251' and f2 '0'
                ; with ENTER give $37, $38 and $38. This raised $7B, the tone
                ; frequency's code, from the arm this path shared with it.
                ldb     #ERR_SEQ_INDEX
                lda     >tone_field
                cmpa    #TONE_FIELD_SEQIDX
                beq     tone_commit_seq_raise
                ldb     #ERR_SEQ_END
tone_commit_seq_raise
                lbsr    ABI_error_raise
                lbsr    tone_entry_reset
                lbra    tone_show_armed

; ---------------------------------------------------------------------------
; tone_seq_store - put a typed step number into Seq Index or Seq End
;
;   entry: entry_result holds the accumulated digits (ABI_entry_value has run)
;   exit:  carry SET and nothing stored if the number is not a step;
;          carry CLEAR and tone_cursor or tone_end updated otherwise
;   uses:  A, B, X, U - U through tone_field_address, which a caller that
;          believes this header would otherwise not save
;
; ONE-BASED IN, ZERO-BASED STORED. Executed on the stock: 3 into Seq Index
; leaves the window at "[23456789ABCDEF01]", so the third step is the one
; holding 0-based step 2; and 4 into Seq End leaves "[0123............]" -
; four steps, so the typed number is a COUNT and the cell under it is the last
; index. Both are therefore typed minus one, which is what the digital screen's
; $4E23 does with "a five-digit number minus one" for the same pair of fields.
;
; The stored values do not change meaning: tone_cursor stays a 0-based step and
; tone_end a 0-based LAST INDEX, which is what tone_window_step, tone_seq_insert
; and tone_seq_delete read and what the stock's own $6DA2 CMPX #$00F9 caps at
; 249. Only the number the operator types and reads is one-based - here and in
; tone_show, the two places the outside sees it.
; ---------------------------------------------------------------------------
tone_seq_store
                lda     >entry_result           ; the top byte of the 24-bit
                bne     tone_seq_store_no       ; entry: far past 250
                ldd     >entry_result+1
                beq     tone_seq_store_no       ; ZERO IS NOT A STEP: the
                                                ; instrument numbers from 1
                cmpd    #TONE_PLAYLIST          ; and 250 is the last one
                bhi     tone_seq_store_no
                subd    #1                      ; stored 0-based, as every
                pshs    d                       ; reader already expects.
                lbsr    tone_field_address      ; X = tone_cursor or tone_end;
                puls    d                       ; it returns a width in B, so
                std     ,x                      ; the value rides the stack
                andcc   #$FE                    ; carry clear: stored
                rts
tone_seq_store_no
                orcc    #$01                    ; carry set: not a step, and
                rts                             ; the previous value stands

tone_commit_time
                ; A TIME IS A WORD OF TIMER COUNTS since the model was
                ; ported, so the ceiling is the instrument's own 655.35 ms and
                ; not 255. This read the top TWO bytes and refused anything
                ; over 255 - correct while the cell was one byte, and the
                ; reason 300 ms was still being refused after the cell became
                ; a word. Anything past the real ceiling is refused rather
                ; than truncated, which is the part worth keeping.
                ;
                ; AND THE CEILING IS ON THE COUNTS, NOT ON THE TYPED DIGITS.
                ; This tested `cmpd #TONE_MS_MAX` against entry_result, which
                ; is the digit string BEFORE the typed decimal point is
                ; applied at tone_commit_time_frac below - so 6 5 4 . 9 9
                ; arrived here as 65,499 and was refused for being over 655.
                ; Every time typed with four or more digits and a point went
                ; the same way. Driven 2026-09-13, f2 then the digits then the
                ; ms key, stock images against this firmware before the fix:
                ;
                ;   typed      stock $3C10 / $23DE     this firmware
                ;   12.34      1,234    / 0            refused $32
                ;   65.53      6,553    / 0            refused $32
                ;   654.99    65,499    / 0            refused $32
                ;   655.35    65,535    / 0            refused $32
                ;   655       65,500    / 0            65,500 / 0
                ;   6553.5       -      / $32          refused $32
                ;
                ; The stock's own bound is check_entry_below_65536 ($60C3),
                ; called from read_time_entry ($6227) at $624F: it compares
                ; the SCALED entry against the ROM string '63556' at $2414 -
                ; 65536 backwards - and accepts on the final borrow at $6115.
                ; So the test belongs after the scaling, on the product, and
                ; it is tone_commit_time_range below. The top-byte test kept
                ; here is not that ceiling: it is what makes the 16-bit reads
                ; of entry_result+1 in this routine and in tone_commit_field
                ; safe, and 65,536 ms typed with no point overflows the
                ; product and is caught by the new test.
                lda     >entry_result           ; the top byte of the 24-bit
                lbne    tone_commit_time_big    ; entry - $32, not the tone
                                                ; frequency's $7B
; ---------------------------------------------------------------------------
; tone_commit_field - store the typed number in whichever field is selected
;
;   entry: entry_result holds the digits, already proved to be in range for
;          the field by the caller that branched here
;   uses:  A, B, X, Y, U - Y carries the time to tone_time_accept, which is
;          why it is named here and was not
;
; REACHED BY BRANCH from tone_commit_time and its two siblings above, and it
; is written out as a routine with a header for a reason that is not
; decoration: without one, asmscan folds a branched-to label into the routine
; that physically precedes it, which here is tone_seq_store - so the Y this
; destroys was reported against a routine that does not touch Y, and the only
; ways to silence that were to put a register in tone_seq_store's header that
; it does not destroy, or to weaken the gate. A header is the true answer:
; this IS a routine, it simply has no caller that uses LBSR.
; ---------------------------------------------------------------------------
tone_commit_field
                lbsr    tone_field_address      ; X = the field, B = width
                cmpb    #$02                    ; A TIME IS CHECKED BEFORE IT
                bne     tone_commit_store       ; IS STORED - the stock's
                ldu     #entry_result           ; apply_time_entry ($638F)
                ldy     1,u                     ; THE WHOLE VALUE, not its low
                                                ; byte: the top byte is already
                                                ; proved zero above and 256 and
                                                ; 512 are in range with a zero
                                                ; low one
                lbsr    tone_time_accept        ; through validate_gate_time
                bcc     tone_commit_store       ; ($6033) at $63B2; checking
                lbsr    tone_entry_reset        ; first leaves the same value
                lbra    tone_show_armed         ; standing, and the repaint
                                                ; here shows it, as its
                                                ; show_time_value_field
                                                ; ($5AAE) call does
tone_commit_store
                pshs    b                       ; the width
                ldu     #entry_result
                ldb     ,s
                cmpb    #$01
                bne     tone_commit_two
                lda     2,u                     ; a one-byte field takes the
                sta     ,x                      ; low byte
                lbra    tone_commit_stored
tone_commit_two
                cmpb    #TONE_WIDTH_WORD
                bne     tone_commit_not_word
                ; A PLAIN 16-BIT NUMBER: Seq Index or Seq End. Both are bounded
                ; at the playlist's length, and Seq End may EQUAL it where the
                ; index may not - an end of 250 means all 250 steps play, an
                ; index of 250 is past the last one. The stock bounds the same
                ; way: seq_put_nibble ($452D) refuses an index at or above
                ; $00FA and seq_data_init ($79FE) seeds an end of $00F9.
                lda     ,u                      ; the typed value, 24 bits
                bne     tone_commit_word_big
                ldd     1,u
                cmpd    #TONE_PLAYLIST
                bhi     tone_commit_word_big
                pshs    a
                lda     >tone_field
                cmpa    #TONE_FIELD_SEQEND
                puls    a
                beq     tone_commit_word_put    ; an end may equal the length
                cmpd    #TONE_PLAYLIST
                bhs     tone_commit_word_big    ; an index may not
tone_commit_word_put
                std     ,x

                ; A TYPED SEQ INDEX TAKES THE WINDOW WITH IT. The stock does
                ; this at $77CB, inside enter_sequence_field ($7649): when the
                ; field being committed is the index ($3D37 == $3D0D) it stores
                ; $3D0D into the window origin $3D39 as well, and
                ; clamp_index_to_end ($73E2) does the same at $741B.
                ;
                ; It matters because leaving the editor snaps the index BACK to
                ; the origin - exit_sequence_edit ($7160) does LDD $3D39 /
                ; STD $3D0D at $7175 - so without this a typed index is thrown
                ; away by the next key that leaves. Walking the cursor with the
                ; arrows deliberately does NOT move the origin, which is how
                ; the stock lets an operator look around inside the window and
                ; come back to where they started.
                pshs    a
                lda     >tone_field
                cmpa    #TONE_FIELD_SEQIDX
                puls    a
                bne     tone_commit_stored
                std     >tone_window
                bra     tone_commit_stored
tone_commit_word_big
                ldb     #ERR_VALUE_RANGE
                lbsr    ABI_error_raise
                leas    1,s
                lbsr    tone_entry_reset
                lbra    tone_show_armed
tone_commit_not_word
                cmpb    #$02
                bne     tone_commit_wide
                ; A TIME: TYPED IN WHOLE MILLISECONDS, STORED IN TIMER COUNTS.
                ; The table holds what the timer latch takes, which is the
                ; stock's own unit; the field is two hex digits of ms, so the
                ; conversion happens on the way in and tone_counts_to_ms
                ; undoes it on the way out. Stage 3 widens the field and this
                ; multiply goes away.
                ldd     1,u                     ; SIXTEEN BITS OF TYPED MS,
                                                ; not the low byte: a byte
                                                ; truncated 300 to 44. The
                                                ; ceiling was checked at
                                                ; tone_commit_time, above.
                ldx     #TONE_MS_COUNTS
                lbsr    ABI_mul16               ; math_product = ms x 100

                ; AND A TYPED DECIMAL POINT TAKES DECADES OFF IT. This field's
                ; scaling is its own - milliseconds into timer counts - so the
                ; unit table's decade path never sees it, and a typed 2 . 5
                ; stored 25 ms where the instrument stores 2.50. Driven
                ; 2026-09-11 against the stock.
                ldb     >entry_frac
                beq     tone_commit_time_scaled
tone_commit_time_frac
                ldx     #math_product+1         ; the 24 bits the product uses
                pshs    b
                lbsr    ABI_unit_div_ten
                puls    b
                decb
                bne     tone_commit_time_frac
tone_commit_time_scaled
                ; THE CEILING, ON THE SCALED COUNT. math_product is 32 bits
                ; and the widest this product can be is 65,535 x 100 =
                ; 6,553,500, so +0 is always zero and +1 carries bits 16-23:
                ; non-zero there is a count of 65,536 or more, which is what
                ; check_entry_below_65536 ($60C3) refuses with $32. Below,
                ; only math_product+2 is read, so without this the count was
                ; truncated to sixteen bits - 6553.5 ms would have stored
                ; 655,350 & $FFFF = 3,894 counts, 38.94 ms.
                lda     >math_product+1
                bne     tone_commit_time_range
                ; AND THE FLOOR IS ON THE COUNTS. validate_gate_time ($6033)
                ; loads $0050 = 80 counts, or $0064 = 100 when $3C03 says the
                ; DTMF screen is editing, and refuses anything below it with
                ; $32 - the value already in the cell stands. Driven on the
                ; stock 2026-09-11: 0 . 5 then Hz leaves 'On Time   1.00ms' and
                ; $23DE = $32, where 0 . 8 is taken as '.80ms'. This firmware
                ; took 0.50 and 0.70. Zero is not refused here: a zero time with
                ; a non-zero partner is legal, and tone_time_accept has already
                ; made that test.
                ldd     >math_product+2
                beq     tone_commit_time_floor_ok
                pshs    a,b
                ldd     #TONE_TIME_MIN
                tst     >tone_dtmf_mode
                beq     tone_commit_time_floor
                ldd     #TONE_TIME_MIN_DTMF
tone_commit_time_floor
                cmpd    ,s++                    ; floor - the counts
                bls     tone_commit_time_floor_ok
tone_commit_time_range
                ldb     #ERR_TIME_RANGE
                lbsr    ABI_error_raise
                leas    1,s                     ; the width tone_commit_store
                lbsr    tone_entry_reset        ; pushed
                lbra    tone_show_armed
tone_commit_time_floor_ok
                lbsr    tone_field_address      ; X = the cell again; mul16
                ldd     >math_product+2         ; used it. At most 65,500
                inc     >dds_lock               ; THE PLAYER READS THIS TABLE
                std     ,x                      ; FROM NMI, and
                dec     >dds_lock               ; DISABLE_INTERRUPTS does
                bra     tone_commit_stored      ; nothing whatever to NMI
tone_commit_wide
                inc     >dds_lock               ; the same, for the 24-bit
                lbsr    ABI_copy24              ; tuning word
                dec     >dds_lock
tone_commit_stored
                leas    1,s
                ; AND A COMMITTED FREQUENCY GOES DOWN TO THE CHIP. The stored
                ; value is one of sixteen slots the chip caches, and the slot
                ; only changes there when the firmware sends it:
                ; commit_freq_value ($628E) stores through
                ; validate_store_frequency ($612D) and then calls
                ; download_tone_frequency ($5F33) at $62A1, which reloads that
                ; slot and re-sounds the cursor. tone_download_one is that
                ; call. No other field on this screen has a slot behind it -
                ; the times are a table the player reads on its next tick, the
                ; level goes out through ampl_set, and the two sequence numbers
                ; are indices.
                lda     >tone_field
                cmpa    #TONE_FIELD_FREQ
                bne     tone_commit_no_slot
                lbsr    tone_download_one
tone_commit_no_slot
                lbsr    tone_entry_reset
                lbra    tone_show_armed
tone_commit_done
                ; NOTHING STORED IS STILL RE-ARMED. The paths that reach this
                ; label - nothing typed, a value past 24 bits, a scale the
                ; unit refuses, and the sequence numbers' own store - all
                ; stand for a $23 arm the stock runs to its end, and those
                ; arms re-arm on every path: commit_freq_value ($628E) runs
                ; straight through to its [$3C0E], and enter_sequence_field
                ; ($7649) re-arms Seq Index and Seq End whenever $3D3D is set,
                ; which softkey_seq_index leaves it. The cursor comes back on
                ; the field; the entry itself is left as this path left it.
                lbsr    tone_show
                lbra    tone_field_arm

; ---------------------------------------------------------------------------
; tone_freq_in_range - is entry_result at or under the top frequency?
;
;   exit:  carry CLEAR at or under 600 kHz ($5B8D80 tenths of a hertz, the
;          ceiling at $EA55); SET above it
;   uses:  A, X
; ---------------------------------------------------------------------------
tone_freq_in_range
                ldx     #entry_result
                lda     ,x
                cmpa    #TOP_FREQ_HI
                blo     tone_freq_in_range_ok
                bhi     tone_freq_in_range_no
                lda     1,x
                cmpa    #TOP_FREQ_MID
                blo     tone_freq_in_range_ok
                bhi     tone_freq_in_range_no
                lda     2,x
                cmpa    #TOP_FREQ_LO
                bls     tone_freq_in_range_ok
tone_freq_in_range_no
                orcc    #CC_CARRY
                rts
tone_freq_in_range_ok
                andcc   #~CC_CARRY
                rts

; ---------------------------------------------------------------------------
; tone_bus_freq_select - FRA-FRD on the tone screens: the FREQ key, then arm
;
;   entry: B = KEY_FREQ
;   uses:  A, B, X, Y, U
;
; freq_key ($4D02) refuses with $3A in DTMF mode and $3B off the tone record,
; and arms the FREQ entry otherwise; begin_numeric_entry sets $238F only on
; that last path. remote_select cleared last_error before delivering, so a
; refusal is the one code it finds there.
; ---------------------------------------------------------------------------
tone_bus_freq_select
                lbsr    tone_key                ; the key's own arm
                lda     >last_error
                cmpa    #TONE_ERR_WRONG_MODE
                beq     tone_bus_freq_done
                cmpa    #ERR_WRONG_WINDOW
                beq     tone_bus_freq_done
tone_bus_freq_arm
                lda     >tone_field
                cmpa    #TONE_FIELD_FREQ
                bne     tone_bus_freq_done
                lda     >rmt_flags              ; an arm empties the entry
                anda    #~RF_HELD&$FF           ; ($A415): no number held
                sta     >rmt_flags              ; from before it survives
                lda     #0                      ; and has a field cursor
                sta     >rmt_field_gone         ; again (LDA leaves carry)
                lda     #RK_TONEFREQ
                sta     >rmt_pend_kind
                lda     #$01                    ; owner 1 = the tone screens
                sta     >rmt_seq_owner
tone_bus_freq_done
                rts

; ---------------------------------------------------------------------------
; tone_bus_ampl_select - the bus's AMPTD select, and the field armed for it
; tone_bus_ampl_commit - the $23 that follows its unit
;
;   entry: B = KEY_AMPL (select)
;   uses:  A, B, X, Y, U
;
; key_select_amptd ($4D47) is arm [25] of d508c for the key and the bus alike;
; the bus's number then lands in the armed field and its unit posts $23, whose
; arm is commit_amptd_value ($630C). The key's own path does the selecting; the
; kind is named only if the AMPTD field is what it selected, and it is named
; again after the commit, since the repaint installs the screen afresh and the
; instrument's $238F still stands.
; ---------------------------------------------------------------------------
tone_bus_ampl_select
                lbsr    tone_key                ; the key's own arm
tone_bus_ampl_arm
                lda     >tone_field
                cmpa    #TONE_FIELD_AMPL
                bne     tone_bus_ampl_done
                lda     >rmt_flags              ; an arm empties the entry
                anda    #~RF_HELD&$FF           ; ($A415): no number held
                sta     >rmt_flags              ; from before it survives
                lda     #0                      ; and has a field cursor
                sta     >rmt_field_gone         ; again (LDA leaves carry)
                lda     #RK_TONEAMPL
                sta     >rmt_pend_kind
                lda     #$01                    ; owner 1 = the tone screens
                sta     >rmt_seq_owner
tone_bus_ampl_done
                rts
tone_bus_ampl_commit
                lda     >rmt_pend_kind
                cmpa    #RK_SEQPOS              ; A SEQ INDEX OR SEQ END TAKEN
                beq     tone_bus_commit_seq     ; FROM THE BUS SOUNDS THE STEP
                cmpa    #RK_SEQEND              ; AT THE CURSOR, in every run
                bne     tone_bus_commit_ampl    ; state. In Manual $3D11 = $0B
tone_bus_commit_seq                             ; reaches apply_seq_entry_manual
                lbra    tone_sound_at_cursor    ; ($64AC); otherwise SEQP leaves
                                                ; $3D11 = 8 and SEQE 10, arms 7
                                                ; and 9, commit_sequence_digit
                                                ; ($64FA) - and all three call
                                                ; tone_at_cursor ($6D66) and
                                                ; output_tone ($6A95) with no
                                                ; test. Seed 3 step 79 ('RUNM
                                                ; 250 HZ;') found Manual; seed
                                                ; 1 step 199 ('SEQP 10 DG;',
                                                ; stopped) found the rest:
                                                ; register $15 9 on the
                                                ; instrument and 14 here
tone_bus_commit_ampl
                cmpa    #RK_TONEFREQ            ; THE FREQUENCY: commit_entry_
                bne     tone_bus_commit_level   ; to_field on $3D11 = 1, the
                lda     >tone_field             ; panel's own range check and
                cmpa    #TONE_FIELD_FREQ        ; store, with the value and its
                bne     tone_bus_ampl_done      ; unit where the keyed entry
                lda     >rmt_unit               ; leaves them (remote.s
                sta     >tone_unit_last         ; remote_units_tonefreq). 'FRA
                lda     >rmt_flags              ; 500 HZ;' on the tone record
                bita    #RF_VALUE               ; sets 500.0 Hz on the
                beq     tone_bus_freq_empty     ; instrument (driven 2026-09-17)
                ldx     #entry_result
                ldu     #rmt_val
                lbsr    ABI_copy24
                lbsr    tone_freq_in_range
                lbcc    tone_commit_freq_ok
                ; PAST THE CEILING the bus's answer is validate_store_
                ; frequency's $35, reported by l5104 while remote, and
                ; commit_freq_value carries on: the value stands, the unit
                ; is stored and the tone is downloaded. 'FRA 999999.9 HZ;'
                ; records $35 with the SRQ lamp lit on the instrument.
                ldb     #TONE_ERR_FREQ_LIMIT
                lbsr    ABI_error_record
tone_bus_freq_empty
                ; A UNIT ON AN EMPTY ENTRY: commit_freq_value ($628E) runs
                ; all the same. validate_store_frequency leaves the value,
                ; $62A1 download_tone_frequency ($5F33) sends the tone again
                ; and $62AB stores the unit at +3. Driven 2026-09-17, 'FRA;'
                ; 'HZ;' on the tone record: DDS register $15 goes 14 to 0 on
                ; the instrument and the frequency reads as it did.
                lda     >rmt_unit
                sta     >tone_freq_unit
                lbsr    tone_download_one
                lbra    tone_show_armed
tone_bus_commit_level
                cmpa    #RK_TONEAMPL
                bne     tone_bus_ampl_done
                lda     >tone_field
                cmpa    #TONE_FIELD_AMPL
                bne     tone_bus_ampl_done
                ldx     #entry_result           ; the scaled microvolts where
                ldu     #rmt_val                ; the panel's entry leaves them
                lbsr    ABI_copy24
                lbsr    tone_commit_ampl
                bra     tone_bus_ampl_arm

; ---------------------------------------------------------------------------
; tone_commit_ampl - ENTER on the AMPTD field: set the channel's level
;
;   uses:  A, B, X, Y, U
;
; The stock commits this field through commit_amptd_value ($630C), which
; parses, checks the ceiling the unit dispatch installed at $23B7 and calls
; apply_amplitude ($5F70). ampl_set is all three, and it reports its own
; refusal, so a level past the channel's ceiling beeps and leaves the setting
; alone rather than being clamped into something the operator did not ask for.
; ---------------------------------------------------------------------------
tone_commit_ampl
                lbsr    tone_channel_record     ; X = the record, B = channel
                ldu     #entry_result
                lbsr    ABI_ampl_set
                bcs     tone_commit_ampl_no
                lbsr    tone_ampl_dtmf_half     ; and the pair's halving, which
                                                ; $630C reaches through $5F70
                lbsr    tone_entry_reset
                lbra    tone_show_armed
tone_commit_ampl_no
                lbsr    ABI_error_beep          ; ampl_set has already recorded
                lbsr    tone_entry_reset        ; which error it was and left
                lbra    tone_show_armed         ; the setting untouched

; ---------------------------------------------------------------------------
; tone_step_field - an arrow: move the selected field by its increment
;
;   entry: B = +1 up, $FF down
;   uses:  A, B, X, Y, U
;
; The stock has step_freq_value ($6683), step_amplitude and step_on_off_time
; on its own step dispatch, one per field, all acting on whichever field is
; selected. This is the same, with the field's width deciding whether it is a
; 24-bit add or a byte one.
;
; AND WITH NO FIELD SELECTED AN ARROW DOES NOTHING, which is the whole reason
; for the test below. step_active_field ($666D) loads X = $3D11 and dispatches
; 1 to 11 through d697f ($697F); $3D11 is ZERO until a field key or a softkey
; sets it, and menu_page_key ($4C87) puts it back to zero on every record
; change - so on the title record, and on any record before a field has been
; picked, the dispatch has no arm to take and the key is spent.
;
; THIS FIRMWARE HAD NO SUCH STATE. tone_field is zero at a record change and
; zero is TONE_FIELD_FREQ, so an arrow on the mode's own banner stepped tone
; 0's frequency by its increment and re-armed the entry behind it - and the
; digit that followed then echoed into the banner. The arm is the state that
; does exist here and it tracks $23A8 exactly: a field key sets both, a record
; change clears both.
;
; Driven on both, 2026-09-13, on the tone record with the increment set to
; 100 Hz and FREQ at 1.000 kHz: with the field armed, DOWN reads 0.900 then
; 0.800 kHz on the instrument and on this firmware alike; press PHASE first -
; which is refused there, and the refusal clears $23A8 - and DOWN leaves the
; instrument at 1.000 kHz while this firmware went to 0.900. The differential
; harness reported the banner case as seed 18, step 12.
; ---------------------------------------------------------------------------
tone_step_field
                tst     >entry_armed            ; no field armed, no field to
                bne     tone_step_armed         ; step: $3D11 = 0 and $697F
                ldb     #ERR_NO_STEP_FIELD      ; has no arm for it - and the
                lbra    ABI_error_record        ; guard's default records 4,
                                                ; reported through l5104
                                                ; ($9DD3 while remote). This
                                                ; returned in silence; driven
                                                ; 2026-09-15, UP on the tone
                                                ; and DTMF Manual records and
                                                ; on the Tone Number record
                                                ; leaves $23DE = 4 on the
                                                ; instrument, keyed and as
                                                ; 'UP;' alike
tone_step_armed
                pshs    b                       ; the direction
                ; THE ARROW RESELECTS THE VALUE FIELD. step_active_field
                ; ($666D) loads X = $3D11 and dispatches 1..11 through d697f
                ; ($697F); three of its arms are the increment ids and each
                ; is two instructions long: step_freq_from_step_field ($667D)
                ; LDD #$0001 / STD >$3D11 for id 2,
                ; step_amptd_from_increment_view ($672C) LDD #$0003 / STD
                ; >$3D11 for id 4 and step_time_from_step_field ($67EA) LDD
                ; #$0005 / STD >$3D11 for id 6, each falling into the VALUE
                ; arm below it ($6683, $6732, $67F0). So an arrow while INCR
                ; SET is armed puts the value's id back and steps the VALUE
                ; by its increment - record+5 onto the record base in
                ; step_freq_value, record+15 onto record+10 in
                ; step_amplitude, [$3D15] onto [$3D13] in step_on_off_time -
                ; repaints the VALUE (render_freq_field at l670f,
                ; show_amptd_field ($593A) at l67cd, show_time_value_field
                ; ($5AAE) at l685c) and re-arms the value's entry through
                ; [$3C0E] with 0, 1 or 2. tone_incr_mode is this screen's
                ; $3D11 = 2, 4 or 6, so it is cleared here, before the step,
                ; for all four fields at once: the id-6 arm covers On and Off
                ; alike because $3D13 already points at whichever was
                ; selected. It used to survive the arrow, so tone_show kept
                ; painting the increment over the value that had just moved,
                ; and the next number typed and entered landed in the
                ; increment where the stock's lands in the value.
                clr     >tone_incr_mode
                lbsr    tone_incr_address
                pshs    x                       ; the increment
                lbsr    tone_field_address      ; X = the field, B = width
                cmpb    #$02
                lbeq    tone_step_time          ; a WORD of timer counts
                cmpb    #$01
                lbne    tone_step_wide

                ; THE ONLY ONE-BYTE FIELD IS THE TONE NUMBER, and it steps by
                ; ONE. step_tone_number ($6879) is the stock's arm for it:
                ; $6884-$6892 is CMPB #$0F / ADDB #$01 capped at fifteen, and
                ; $689D-$68AB is CMPB #$00 / SUBB #$01 floored at zero. There
                ; is no increment cell in it anywhere.
                ;
                ; THIS WENT THROUGH THE GENERIC BYTE STEPPER, which reads the
                ; increment tone_incr_address returns - and that routine has no
                ; arm for this field, so it fell through to incr_tone_freq and
                ; the step was the TOP BYTE of a 24-bit frequency increment.
                ; At its default of zero the arrows did nothing at all; with it
                ; at the 6,000,000 ceiling one press moved the tone number from
                ; 0 to 91, against a declared 0..15. Then it handed the tone
                ; NUMBER to tone_time_accept, which is the On/Off time
                ; validator: not TONE_FIELD_ON, so that routine read
                ; -2,x - tone_position - as the partner time and refused with
                ; 'On & Off times cannot both be 0' about a tone number.
                lda     >tone_number
                tst     2,s                     ; the direction
                bmi     tone_step_number_down
                cmpa    #TONE_TONES-1
                bhs     tone_step_number_done   ; capped, as $6889 caps it
                inca
                bra     tone_step_number_store
tone_step_number_down
                tsta
                beq     tone_step_number_done   ; floored, as $68A2 floors it
                deca
tone_step_number_store
                sta     >tone_number
tone_step_number_done
                lbra    tone_step_moved

tone_step_time
                ldu     ,s                      ; the increment, a WORD of ms
                ldd     ,u
                ldx     #TONE_MS_COUNTS
                lbsr    ABI_mul16               ; math_product = ms x 100
                lbsr    tone_field_address      ; X back FIRST: mul16 took it,
                                                ; and this routine returns the
                                                ; width in B - so reading the
                                                ; product before it threw the
                                                ; product away and the arrow
                                                ; stepped by nothing
                ldd     >math_product+2         ; 655 x 100 is 65,500, inside
                pshs    d                       ; sixteen bits
                ldd     ,x                      ; the stored word
                tst     4,s                     ; the direction, two deeper now
                bmi     tone_step_time_down
                addd    ,s++
                bcc     tone_step_time_check
                ; OVERFLOW LEAVES THE VALUE ALONE, which is what the
                ; instrument does. add16_checked ($44FA) returns B=1 on carry
                ; WITHOUT storing, and its caller step_on_off_time ($67F0)
                ; commits $221A back into [$3D13] only when the call reported
                ; no overflow. This clamped to $FFFF instead - 65535 counts,
                ; which is past this screen's own TONE_MS_MAX ceiling of 655
                ; ms - so holding the up arrow at a large time jumped it to a
                ; value the keypad cannot type, where the stock simply stops.
                ;
                ; NOTHING IS DROPPED HERE, and a `leas 2,s` that did was the
                ; fault this arm shipped with. `addd ,s++` above has ALREADY
                ; taken the pushed increment off - the auto-increment is the
                ; release, which is why the down arm's `subd ,s++` needs no
                ; leas either - so releasing it again unwound two bytes that
                ; belonged to the caller. tone_step_moved's own `leas 3,s`
                ; then took three more of a frame that was already short, and
                ; the routine underneath returned to whatever the two extra
                ; bytes made of its address: an overflowing up-arrow on the
                ; TIME field ran off into whatever that word pointed at. The
                ; stack walk in test_stack_balance.py could not see it because
                ; this block sits behind a conditional and after an
                ; unconditional branch, so nothing ever walked it.
                lbra    tone_step_moved
tone_step_time_down
                subd    ,s++
                bcc     tone_step_time_check
                ldd     #0
tone_step_time_check
                ; EVERY STEPPED VALUE GOES THROUGH THE VALIDATOR, not only a
                ; zero. This asked tone_time_accept about zero alone, and that
                ; routine's other half is the FLOOR - eighty counts, or a
                ; hundred on the dialled screen - so the arrows could walk a
                ; time down to fifty counts, which both other routes into this
                ; cell refuse. The keypad's commit and the bus's setter both
                ; check it; the arrow is the third way in and was not checked.
                tfr     d,y                     ; the value, where the validator
                pshs    d,x                     ; reads it
                lbsr    tone_time_accept
                puls    d,x                     ; PULS does not touch the carry
                lbcs    tone_step_moved         ; refused: the old value stands
tone_step_time_put
                inc     >dds_lock               ; the player reads this from
                std     ,x                      ; NMI
                dec     >dds_lock
                lbra    tone_step_moved

                ; --- a 24-bit field: STEP INTO A TEMPORARY ------------------
                ; The stock steps into $221C, checks the result and only then
                ; copies it back: step_freq_value ($6683) tests the sum
                ; against $EA55 = 6,000,000 with a second sub24 and
                ; step_amplitude ($6732) against $EA62 = 10,000,000, and
                ; neither writes the record unless the check clears.
                ;
                ; This added into the record in place. A frequency stepped
                ; past 600 kHz was stored and played, and an amplitude the
                ; setter then refused had already overwritten the value it was
                ; refusing to replace - the stored setting was lost either
                ; way, which is the one thing a refusal exists to prevent.
                ;
                ; THE OFFSETS ARE NAMED, not counted in a comment. Counting
                ; them in a comment is exactly how the two off-by-twos in this
                ; file happened: pshs b then pshs x puts the byte at the HIGH
                ; offset, and both places that read them read as though it
                ; were at the low one.
TONE_STEP_TEMP  equ     0               ; three bytes of working value. It is
                                        ; written ",s" bare wherever the
                                        ; offset is zero: a SYMBOLIC zero
                                        ; offset is encoded differently by
                                        ; lwasm and asm6809.py, both correctly,
                                        ; and tests/test_zero_offset.py refuses
                                        ; one. Three instructions here had it.
TONE_STEP_FIELD equ     3               ; the field it came from
TONE_STEP_INCR  equ     5               ; the increment to apply
TONE_STEP_DIR   equ     7               ; +1 up, $FF down
TONE_STEP_FRAME equ     5               ; what the wide path itself pushed

tone_step_wide
                pshs    x                       ; the field pointer
                leas    -3,s                    ; and the temporary above it
                leau    TONE_STEP_FIELD,s
                ldu     ,u                      ; U = the field
                leax    ,s                      ; X = the temporary
                lbsr    ABI_copy24              ; temp = what is stored now

                ldu     TONE_STEP_INCR,s
                tst     TONE_STEP_DIR,s
                bmi     tone_step_wide_down
                lbsr    ABI_add24               ; INTO THE TEMPORARY
                bcs     tone_step_wide_no       ; past 24 bits
                bra     tone_step_wide_check
tone_step_wide_down
                lbsr    ABI_sub24
                bcs     tone_step_wide_no       ; below zero
tone_step_wide_check
                lda     >tone_field
                cmpa    #TONE_FIELD_FREQ
                bne     tone_step_wide_store    ; a level is checked by
                                                ; ampl_set, which is where its
                                                ; ceiling lives
                lda     ,s                      ; THE FREQUENCY CEILING, the
                cmpa    #TOP_FREQ_HI            ; same 6,000,000 the commit
                blo     tone_step_wide_store    ; path checks, from the same
                bhi     tone_step_wide_no       ; three constants $EA55 holds
                lda     TONE_STEP_TEMP+1,s
                cmpa    #TOP_FREQ_MID
                blo     tone_step_wide_store
                bhi     tone_step_wide_no
                lda     TONE_STEP_TEMP+2,s
                cmpa    #TOP_FREQ_LO
                bhi     tone_step_wide_no

tone_step_wide_store
                leau    ,s                      ; U = the temporary
                ldx     TONE_STEP_FIELD,s       ; X = the field
                DISABLE_INTERRUPTS              ; the player reads this table
                lbsr    ABI_copy24              ; from the tick
                RESTORE_INTERRUPTS
                leas    TONE_STEP_FRAME,s
                bra     tone_step_moved
tone_step_wide_no
                leas    TONE_STEP_FRAME,s       ; the stored value stands, and
                lbsr    ABI_error_beep          ; the operator is told the
                leas    3,s                     ; arrow did nothing rather
                lbra    tone_step_shown         ; than being left to wonder

tone_step_moved
                leas    3,s
                lda     >tone_field             ; AND A STEPPED FREQUENCY GOES
                cmpa    #TONE_FIELD_FREQ        ; DOWN TO ITS SLOT, exactly as
                bne     tone_step_moved_ampl    ; a committed one does:
                lbsr    tone_download_one       ; step_freq_value ($6683) ends
                bra     tone_step_shown         ; in download_tone_frequency
                                                ; ($5F33) at $670A, the same
                                                ; call commit_freq_value makes
                                                ; at $62A1
tone_step_moved_ampl
                lda     >tone_field             ; A LEVEL THAT MOVES HAS TO
                cmpa    #TONE_FIELD_AMPL        ; REACH THE HARDWARE. The step
                bne     tone_step_shown         ; fields above are table
                lbsr    tone_ampl_apply         ; entries the player reads on
tone_step_shown                                 ; its next tick; this one is a
                                                ; channel setting, and storing
                                                ; it without programming the
                                                ; chip changes the number on
                                                ; the screen and nothing else
                ; AND THE ENTRY IS RESTARTED, on every exit. Each of the
                ; stock's three value arms ends, stepped or refused, by
                ; re-arming the field through [$3C0E] - LDU #$0000 / LDY
                ; #$0002 / PSHS Y,U / LDX >$3C0E / JSR ,X after l670f, with
                ; LDU #$0001 after l67cd and LDU #$0002 after l685c - and
                ; select_entry_field ($4567)'s arms hand that frame to
                ; arm_numeric_entry_field ($AC35), which fills the buffer
                ; $239A with spaces ($ACC5-$ACE0) and zeroes the count $23A4
                ; ($ACF5): digits typed before the arrow are gone. Here
                ; tone_key_digit appends to the shared buffer without
                ; looking at entry_active, so clearing the flag alone would
                ; have left them to be committed by the next ENTER;
                ; tone_entry_reset and tone_show_armed are what this screen
                ; restarts an entry with everywhere else.
                lbsr    tone_entry_reset
                lbra    tone_show_armed

; ---------------------------------------------------------------------------
; tone_ampl_apply - push the channel record's level out to the hardware
;
;   uses:  A, B, X, Y, U
;
; The record has already been written, by the arrow step or by tone_commit,
; and ampl_set validates and stores as well as applying - so it is handed the
; value that is now in the record. A level it refuses cannot arise here: the
; commit path checks the range before storing, and the step path clamps.
; ---------------------------------------------------------------------------
tone_ampl_apply
                lbsr    tone_channel_record
                leau    CHAN_AMPL,x
                lbsr    ABI_ampl_set
                lbra    tone_ampl_dtmf_half     ; and the pair's halving, which
                                                ; $67C8 reaches through $5F70

; ---------------------------------------------------------------------------
; tone_ampl_dtmf_half - a stored level onto BOTH tones of a dialled pair
;
;   uses:  A, B, X, Y, U
;
; THE HALVING IS NOT ONLY THE MODE ENTRY'S. commit_amptd_value ($630C) at
; $6323 and step_amplitude ($6732) at $67C8 both finish by calling
; apply_amplitude ($5F70), the same routine sequence_mode_init calls at $54E7,
; and $5F70 reads $3C03 for itself: on the dialled screen it halves the stored
; level through halve_amplitude_221c ($4439) and dispatches the half to
; CHANNEL 0 AND CHANNEL 2, leaving the set level in channel 0's record and the
; half in channel 2's. In tone mode it dispatches channel 0 alone, which is
; exactly what ampl_set has already done, so this does nothing there.
;
; A PAIR IS TWO GENERATORS SUMMED INTO ONE SOCKET, so a level that is not
; halved per tone comes out at twice what the operator set. Only the entry
; halved here: keying AMPTD on the dialled screen put the WHOLE level on
; channel 0 and left channel 2 carrying whatever the entry had given it.
; Measured against the stock through the differential harness, seed 9 step 24,
; 2026-09-13: after AMPTD 100 uV on the dialled output record the instrument
; reads level code 671 on both generators and this firmware read 1342 on
; channel 0 - exactly twice - and 939 on channel 2, the entry's own default.
;
; ampl_program_half is apply_amplitude instruction for instruction; its header
; in amplitude.s carries the correspondence. It is given channel 0's record
; because that is the one the screen displays the set level from and the one
; $601D puts back.
; ---------------------------------------------------------------------------
tone_ampl_dtmf_half
                tst     >tone_dtmf_mode         ; $5F9E: LDB >$3C03 / CMPB #$00
                beq     tone_ampl_dtmf_done
                lbra    dtmf_pair_level         ; the whole of $5F70's DTMF
                                                ; branch, set level kept
tone_ampl_dtmf_done
                rts

; ---------------------------------------------------------------------------
; tone_channel_record - the record of the channel the sequence plays through
;
;   exit:  X = the record, B = the channel number
;   uses:  A, B, X
;
; TONE_CHANNEL, which is channel A. The stock reads the same record for this
; field: key_select_amptd ($4D47) selects field 3, and every later dispatch
; treats field 3 as the channel record's +10 - gpib_report_amptd ($5D77)
; reports it and commit_amptd_value ($630C) stores into it.
; ---------------------------------------------------------------------------
tone_channel_record
                ldb     #TONE_CHANNEL
                lda     #CHAN_RECORD
                mul
                ldx     #channel_records
                leax    d,x
                ldb     #TONE_CHANNEL           ; SET, not left to mul: ampl_set
                rts                             ; reads the channel number off
                                                ; the stack it pushed B onto,
                                                ; and B only happens to survive
                                                ; the multiply because
                                                ; TONE_CHANNEL is zero
