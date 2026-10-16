; ===========================================================================
; page1_dtmf.s - DTMF digit generation
;
; A DTMF digit is two tones at once: one from a low group, one from a high
; group. The instrument has two channels it can sum, so a digit is a pair of
; frequencies written to two registers and then routed together.
;
; THE FREQUENCIES ARE THE STANDARD ONES and they are constants rather than a
; calculation, because they are defined by the signalling standard and not by
; anything this instrument computes. Getting one wrong produces a digit that
; sounds right and decodes as something else.
;
; HOW A DIGIT IS GATED AND TIMED IS TAKEN FROM THE STOCK, register for
; register. The stock plays a dialled digit as a one-step sequence through
; the NMI body at $444C on A2U13 page 1, which install_sequence_isr ($6CA2)
; installs when the DTMF flag $3C03 is set. The checked-in comparison is
; emulator/tests/test_dtmf_stream_new.py: it boots both firmwares, walks
; the stock to Manual Dial (Main Selection Level, NEXT, f3 for DTMF
; Sequence, NEXT, f3 for Manual Dial) and this screen to its dial, keys the
; digit 5 on each with the On Time at 5000 counts, logs every write to the
; DDS port, the timer control and the timer-2 latches, and holds this
; file's stream to the stock's. Every $22/$26/$29 word, both tones and the
; four tick latches match; the START latch does not - seq_timer_start in
; timer.s subtracts one before its STD to $1004 and loads $00C7 where
; start_sequence_timer ($6BD0) is LDD #$00C8 / STD >ptm_timer2 - and the
; gate fails on that word until it is fixed. What the body does, in the
; order it does it, is written at each routine below; the summary is:
;
;   start   $22 <- $21, CR2 <- $91, $29 <- $00, the pair, a phase-reset pulse
;           on $26, the pair again, timer 2 <- $00C8, CR2 <- $D1
;   tick 1  $29 <- $00 then $10; $22 <- $21, $26 <- $03, $26 <- $0B, $22 <- $21;
;           the pair; timer 2 <- On Time - 1
;   tick 2  the same with $22 <- $22 last; timer 2 <- $00C7
;   tick 3  the same with $22 <- $21 last; timer 2 <- On Time - 1
;   tick 4  $22 <- $21; CR2 <- $91; $29 <- $00; the pair; the $26 pulse;
;           $22 <- $21; the dial echo blanked; $29 <- $00; the pair;
;           timer 2 <- On Time - 1 with the interrupt already off
;
; THE OFF TIME IS $00C8, NOT $015E. manual_dial_digit ($6540) does write
; $015E into the borrowed tone slot's off-time word at $6732, but the value
; the timer sees for the off phase comes from load_current_step ($4268), and
; at $4299-$42AB that routine substitutes $00C8 for the off time of the last
; step of a single pass - which a dialled digit always is, seq_run_single
; ($4A5F) having set $3C81 and manual_dial_digit having set Seq End $3D0F to
; zero. The trace shows it: the second interrupt writes $00C7 to the latches,
; and $015E is never written to them. So a digit here is On Time of tone and
; two hundred counts of silence, and $015E is recorded below as what the
; borrowed slot holds, because that is all it is.
; ===========================================================================

DTMF_ROWS       equ     4
DTMF_COLUMNS    equ     4
DTMF_DIGITS     equ     16              ; 0-9, A-D, * and #

; WHICH TWO CHANNELS CARRY THE PAIR, AND WHICH TONE EACH ONE CARRIES.
;
; dtmf_program_digit ($441E) loads the two tones with
;
;       ldd   ,x                the (row, column) pair from $43D4: A = row,
;       pshs  a                 B = column
;       lda   #$08 / jsr dds_load_dtmf_tone_freq    group B = the column
;       puls  b
;       lda   #$0a / jsr dds_load_dtmf_tone_freq    group B = the row
;
; and $08 is DDS_FREQ_BASE, so registers $08 and $0A are channels 0 and 2 -
; channel 0 carrying the COLUMN tone (the high group) and channel 2 the ROW
; tone (the low group). The stock executing agrees: for the digit 5, which
; is the pair (1, 5) in the stock's table, register $08 took 13360 and
; register $0A took 7700, and emulator/tests/test_dtmf_stream_new.py holds
; this file's two tuning words to those, latch by latch. apply_amplitude ($5F70) agrees from the other side: it
; applies the level with the channel subscript $23BE at 0, then does LDB #$02
; / STB >$23BE for the second generator.
;
; These were named DTMF_LOW_CHANNEL = 0 and DTMF_HIGH_CHANNEL = 2 and the low
; tone was put on channel 0, which is the two tones swapped between the two
; generators. Both are summed into one socket, so the pair was still the
; pair; the registers now hold what the stock puts in them.
;
; An instrument with fewer than three boards cannot send DTMF, and dtmf_send
; refuses rather than half sending.
DTMF_COL_CHANNEL  equ   0               ; register $08: the column tone
DTMF_ROW_CHANNEL  equ   TONE_DTMF_PAIR  ; register $0A: the row tone. ONE
                                        ; DEFINITION: page1_tone.s declares it
                                        ; because its own level paths halve
                                        ; across the same two channels

; THE GATE, in DDS register $22, which common/formats.inc names
; DDS_PORT_MUX_01. The NMI body picks the value off bit 0 of the phase
; counter $3D32 at $449B-$44A3: LDB #$21 for an even phase and LDB #$22 for
; an odd one. dds_set_output_mode_reg22 ($6B92), the foreground's writer of
; the same register, chooses $21 for its argument 0, $22 when the argument is
; non-zero and $3C03 marks DTMF, and $20 in tone mode - so $21 is the idle
; code and $22 the two-tone one. What the codes physically select is not
; established by either ROM and is not claimed here.
DTMF_GATE_OFF   equ     $21
DTMF_GATE_ON    equ     $22

; THE PULSE THAT GOES WITH EVERY GATE CHANGE. $44B9-$44CB:
;
;       ldx   #$2221 / stx $0200        $22 <- $21
;       ldx   #$2603 / stx $0200        $26 <- $03
;       lda   #$0b   / sta $0201        $26 <- $0B
;       lda   #$22   / std $0200        $22 <- B, the new gate value
;
; $0B with bit 3 cleared is $03, and bit 3 of register $26 is
; PULSE_PHASE_RESET - so the middle pair is the phase-reset pulse
; dds_reg26_bit3_pulse ($DE7F) makes from the shadow, written here as
; literals. The stock sends the $0B as a second data byte without re-sending
; the register select; this firmware's dds_write sends both bytes each time,
; which is how $DE7F itself writes the same register twice.
DTMF_PULSE_LOW  equ     $03
DTMF_PULSE_HIGH equ     $0B

; REGISTER $29, WRITTEN AT THE TOP OF EVERY TICK. $448C-$4494:
;
;       ldx   #$2900 / stx $0200        $29 <- $00
;       lda   #$10   / sta $0201        $29 <- $10
;
; and dds_write_reg29 ($6B4C) writes it to $00 again whenever the timer is
; stopped - from seq_timer_stop ($6C22) and from sequence_stop_from_isr
; ($6C45). The page-3 name table at $568F calls the register sync_rg;
; formats.inc has no equate for it, so it is named here. What the two values
; do on the chip is not established.
DDS_SYNC_REG    equ     $29
DTMF_SYNC_CLEAR equ     $00
DTMF_SYNC_SET   equ     $10

; REGISTER $1C, WRITTEN ONCE AT EVERY SEQUENCE MODE ENTRY AND ROUND EVERY
; MESSAGE. dds_write_reg1c ($6AE3) shadows its byte in $24B5 and sends it with
; dds_write_pair ($DE6F); sequence_mode_init ($5380) calls it with 2 at $5500,
; on the tone entry and the dialled one alike, and
; sequence_mode_message_handler ($4C01) writes 0 on the way into every message
; ($4C14) and 2 on the way out ($510F). That LOOKS like an update hold and
; release and nothing in the instruction stream proves it, so only the writes
; are reproduced. The page-3 name table at $568F calls the register zero_lt -
; arm [28] loads the name pointer $632D - and formats.inc has no equate for
; it, so it is named here.
DDS_ZERO_LT     equ     $1C
DTMF_ZERO_LT_RUN equ    $02             ; the value $5500 sends

; THE TIMES, in counts of the sequence timer. TONE_MS_COUNTS in page1_tone.s
; is a hundred counts to the millisecond, settled by running the stock's own
; display_period ($4864).
DTMF_START_COUNTS equ   $00C8           ; start_sequence_timer ($6BD0): $3D30
                                        ; = $00C8 and timer 2 <- $00C8, so the
                                        ; first interrupt comes two hundred
                                        ; counts after the start
DTMF_GAP_COUNTS equ     $00C8           ; load_current_step ($42A5): LDX
                                        ; #$00C8 for the off phase of the last
                                        ; step of a single pass
DTMF_ON_DEFAULT equ     $0064           ; seq_mode_defaults ($5224) writes
                                        ; $0064 into both words of every
                                        ; $3C10 record at mode entry, and the
                                        ; screen renders it as 1.00ms
DTMF_ON_MIN     equ     $0064           ; validate_gate_time ($6033): the
                                        ; floor for a time in DTMF mode
DTMF_ON_MAX_MS  equ     655             ; 65535 counts is 655.35 ms, the most
                                        ; the stock's 16-bit word holds
DTMF_OFF_BORROW equ     $015E           ; manual_dial_digit ($6732): LDD
                                        ; #$015E / STD ,X into the borrowed
                                        ; slot's off-time word. Recorded, not
                                        ; used: see the file header
DTMF_TIME_PLACES equ    2               ; a count is a hundredth of a
                                        ; millisecond, so two places

; THE PHASE-RESET VETO. dds_reg26_pulse_if_flag1_clear ($DEB6) skips the
; pulse when bit 1 of the special flags $23C1 is set; the stock's screen text
; for that bit reads "Disable automatic phase reset". dds.s tests that bit,
; as SPECIAL_NO_PHASE_RESET, inside dds_phase_reset - the one routine that
; makes the pulse, reached from this page through ABI slot 72.

; THE TICK COUNTER. The stock's phase byte $3D32 starts at 2 and is
; incremented before each duration is loaded; this counts the interrupts
; from 0, so bit 0 has the same meaning - clear for the idle gate, set for
; the sounding one - and DTMF_TICKS is the interrupt that stops instead.
DTMF_TICK_IDLE  equ     $FF
DTMF_TICKS      equ     3

; SCRATCH.
; dtmf_tick, dtmf_gate, dtmf_field and dtmf_on_time are declared in
; modules/scratch.inc, where test_scratch_layout.py checks them.

; The low group, one per row, in units of 0.1 Hz like every other frequency
; here - written in whole hertz once, which is a factor of ten low.
;
; Checked against the ROM rather than against the comment: the stock table at
; a2u13_page1 $43BC holds eight three-byte groups, and unpacking them as
; three 6-bit fields gives 6964, 7700, 8520, 9410, 12090, 13360, 14770 and
; 16330.
;
; ALL EIGHT ARE THE STOCK'S. The first is worth a note because it is the one
; that does not agree with the published DTMF row: $01,$2C,$34 unpacks to
; 6964, which is 696.4 Hz, where the standard's low row is 697.0. The format
; resolves 0.1 Hz, so 6970 is available and exact - and this table held 6970
; for that reason, described in its own header as "a deliberate departure from
; the stock data and the only one".
;
; IT IS NOT A DEPARTURE, IT IS A FAULT, and it is put back. The architect's
; own words, 2026-09-12, are "the standard is the
; original, so every divergence is a fault unless the owner rules otherwise
; — except bit 7 of the output latch, already settled the other way and
; recorded", and that ledger has no entry for this table. Nothing but the
; ledger makes a departure a departure, however good the reason reads.
;
; It was measurable, not cosmetic: the row serves digits 1, 2, 3 and A, so
; every sequence containing one of them put 697.0 Hz on channel 2 where the
; instrument puts 696.4. Walked side by side through the sequence editor
; 2026-09-13, the stock read 6964 at steps 1, 2 and 3 and this firmware read
; 6970 at all three.
;
; THE STOCK'S OWN BYTES, dds_program_table ($43BC-$43D3), in the stock's own
; encoding: three bytes a tone, each byte one six-bit field of the 24-bit
; tuning word, top field first. dds_load_dtmf_tone_freq ($43F4) sends the
; three straight to buffer latches $02, $01 and $00, with $03 written as zero
; ahead of them, so no bit of arithmetic stands between this table and the
; chip. The low group is entries 0-3, one per row; the high group 4-7, one
; per column.
;
; THIS WAS A TABLE OF 24-BIT VALUES, 0 then 6964 as an FDB, which
; dtmf_frequencies found by MUL and freq_program split into fields at run
; time through the general, locked writer. Same words on the chip, three
; times the instructions: measured on the emulator 2026-09-14 the DTMF
; sequence player's tick ran 391-416 instructions, 270 of them in dds.s and
; frequency.s, against a period of 422 at the instrument's default and
; minimum 1.00 ms On Time - so with the NMI entry on top it did not fit, the
; next time-out found seq_in_player set, and ONE TICK IN THREE WAS DROPPED.
; The differential harness saw it as the wrong DTMF digit on the sockets:
; seed 2 step 23, channel 0 at 16330 where the instrument had 12090. The
; stock's tick is 136-147 instructions from $444C, and this is part of why.
;
; Each group checked by unpacking, t0*4096 + t1*64 + t2:
dtmf_tone_fields
                fcb     $01,$2C,$34             ; 0:  6964, row 0 - 1 2 3 A
                fcb     $01,$38,$14             ; 1:  7700, row 1 - 4 5 6 B
                fcb     $02,$05,$08             ; 2:  8520, row 2 - 7 8 9 C
                fcb     $02,$13,$02             ; 3:  9410, row 3 - * 0 # D
                fcb     $02,$3C,$3A             ; 4: 12090, column 0 - 1 4 7 *
                fcb     $03,$10,$30             ; 5: 13360, column 1 - 2 5 8 0
                fcb     $03,$26,$32             ; 6: 14770, column 2 - 3 6 9 #
                fcb     $03,$3F,$0A             ; 7: 16330, column 3 - A B C D

; What each position on the keypad is called, in row-major order. Sixteen
; characters, one per digit, so the screen can name what it is sending.
dtmf_names      fcc     "123A456B789C*0#D"

; Which entry of that table a digit KEY selects.
;
; dtmf_names is the standard DTMF keypad read left to right, top to bottom,
; so '1' is entry 0 and '0' is entry 13 - the value of the digit and its
; position in the table are only the same for none of the ten. This was
; indexed with key_digit's return straight out, so pressing 1 sent '2',
; pressing 4 sent '5', pressing 7 sent 'B', and pressing 0 sent '1'; seven of
; the ten digit keys sent the wrong tone pair and one sent a letter that is
; not on the panel at all.
;
;      key   0   1   2   3   4   5   6   7   8   9
;    entry  13   0   1   2   4   5   6   8   9  10
;
; A, B, C, D, * and # cannot be reached from the front panel, because it has
; no keys for them - the six entries 3, 7, 11, 12, 14 and 15 are addressable
; only by a caller that sets dtmf_position itself.
dtmf_digit_index
                fcb     13,0,1,2,4,5,6,8,9,10

dtmf_title      fcc     "DTMF Generator                          "

; Line 2, forty characters: the digit being sent at column 9 and the On Time
; readout at columns 20 to 26, both overlaid by dtmf_show.
dtmf_line2      fcc     "Sending:     On Time        ms   f4=seq "

; Four blanks, for clearing the digit cell and the front of the readout.
dtmf_spaces     fcb     $20,$20,$20,$20

DTMF_DIGIT_POS  equ     LCD_LINE2+9
DTMF_TIME_POS   equ     LCD_LINE2+20    ; seven characters, "nnn.nn" right
DTMF_TIME_W     equ     7               ; aligned with a blank in front
DTMF_ECHO_POS   equ     LCD_LINE2+24    ; the typed digits, over the readout
DTMF_ON_DIGITS  equ     3               ; up to 655 milliseconds

; ---------------------------------------------------------------------------
; dtmf_nibble_pairs - a PLAYLIST NIBBLE to its two tones: index_pair_table
;
; TWO NUMBERINGS, AND THEY ARE NOT THE SAME ONE. A step of the shared sequence
; holds a nibble that the instrument reads as a HEX CHARACTER: 0 to 9 are the
; digits, $0A to $0D are A to D, and $0E and $0F are * and #. That is why
; dtmf_map_ef_to_star_hash ($5AF6) rewrites the rendered characters 'E' and 'F'
; - $45 and $46 - rather than the nibbles: by the time it runs the nibble is
; already a hex character.
;
; This file's own index for a digit KEY is the KEYPAD MATRIX, row times four
; plus column, which is what dtmf_names spells "123A456B789C*0#D" and what
; dtmf_digit_index and dtmf_current carry.
;
; The stock translates a nibble with this table, $43D4-$43F3, sixteen byte
; pairs indexed by the nibble: the first byte is the ROW, 0-3, which is also
; the row tone's entry in dtmf_tone_fields; the second is the COLUMN's entry
; there, 4-7. So nibble 0 is (3,5), row 3 and column 1, which is '0', and
; nibbles $0E and $0F are (3,4) and (3,6), which are * and #.
;
; Passing the nibble straight through as a matrix index was wrong once and
; only three values hid it: 4, 5 and 6 mean the same digit in both
; numberings, and the manual-dial gate dials 5. This file held the same
; translation as a table of matrix indices, dtmf_seq_matrix, ahead of a
; divide-and-multiply lookup; the stock's bytes go straight to the loader.
; ---------------------------------------------------------------------------
dtmf_nibble_pairs
                fcb     $03,$05                 ; $0: 0
                fcb     $00,$04                 ; $1: 1
                fcb     $00,$05                 ; $2: 2
                fcb     $00,$06                 ; $3: 3
                fcb     $01,$04                 ; $4: 4
                fcb     $01,$05                 ; $5: 5
                fcb     $01,$06                 ; $6: 6
                fcb     $02,$04                 ; $7: 7
                fcb     $02,$05                 ; $8: 8
                fcb     $02,$06                 ; $9: 9
                fcb     $00,$07                 ; $A: A
                fcb     $01,$07                 ; $B: B
                fcb     $02,$07                 ; $C: C
                fcb     $03,$07                 ; $D: D
                fcb     $03,$04                 ; $E: *
                fcb     $03,$06                 ; $F: #

; ---------------------------------------------------------------------------
; dtmf_tone_load - one tone into one frequency register, straight to the port
;
;   entry: A = the register, DDS_FREQ_BASE + a channel; B = the tone, 0 to 7
;   uses:  A, B, X
;
; dds_load_dtmf_tone_freq ($43F4-$441D), instruction for instruction:
;
;   $43F4  PSHS A                    the register, for the last write
;   $43F6  TFR D,X / ASLB / ABX      X = A:B plus 2B, so the low byte of X is
;   $43FA  TFR X,D                   3 x the tone - at most 21, no carry out
;   $43FC  LDX #$43BC / ABX          X -> the tone's three fields
;   $4400  LDD #$0300 / STD >$0200   buffer latch $03 <- 0
;   $4406  DECA / LDB ,X / STD       buffer latch $02 <- the top field
;   $440C  DECA / LDB 1,X / STD      buffer latch $01 <- the middle one
;   $4412  DECA / LDB 2,X / STD      buffer latch $00 <- the low one
;   $4418  PULS A / STD >$0200       the register, with the low field still
;                                    in B as its data byte
;   $441D  RTS
;
; DECA walks $03, $02, $01, $00 because those ARE the four latch ids -
; DDS_BUFLAT3 down to DDS_BUFLAT0 in hp8904a-rewrite/common/formats.inc.
;
; NO LOCK AND NO MASK, AND THAT IS THE CONTRACT, NOT AN OMISSION. The four
; buffer latches are shared by every register on the chip, so a write that
; lands between this routine's first latch and its register would be committed
; into the wrong register. Callers are therefore of three kinds only:
;   - the sequence players' ticks, jumped to by nmi_handler in boot.s; each
;     body runs its step only when dds_lock is clear, so no foreground staging
;     can be half done underneath, and no second tick arrives on top because
;     every service measured shorter than its period (log, 2026-09-17: tone
;     at most 100 and DTMF 158 against 422, digital 38 against 42);
;   - no foreground run of a tick body at all any more: tone_manual_forward
;     and tone_manual_back in page1_tone.s used to be one, holding dds_lock,
;     and they now walk the cursor instead, as step_seq_index_manual ($68E2)
;     does;
;   - dtmf_pair_program and dtmf_pair_program_nibble below, the foreground's
;     entries, which raise dds_lock and mask around the call exactly as
;     dds_write_wide in frequency.s does.
; ---------------------------------------------------------------------------
dtmf_tone_load
                pshs    a                       ; $43F4: the register
                tfr     d,x
                aslb
                abx
                tfr     x,d                     ; B = 3 x the tone
                ldx     #dtmf_tone_fields
                abx                             ; X -> its three fields
                ldd     #DDS_BUFLAT3*256        ; $4400: $03 <- 0
                std     >dds_prog
                deca                            ; DDS_BUFLAT2
                ldb     ,x
                std     >dds_prog               ; $02 <- the top field
                deca                            ; DDS_BUFLAT1
                ldb     1,x
                std     >dds_prog               ; $01 <- the middle field
                deca                            ; DDS_BUFLAT0
                ldb     2,x
                std     >dds_prog               ; $00 <- the low field
                puls    a
                std     >dds_prog               ; $441A: the register latches
                rts

; ---------------------------------------------------------------------------
; dtmf_pair_write_nibble - the pair a PLAYLIST nibble names, straight to the port
;
;   entry: B = the nibble; only its low four bits are read
;   uses:  A, B, X
;
; dtmf_program_digit ($441E-$4438), instruction for instruction, except that
; the nibble arrives in B where the stock reads it from $3D27 - the player's
; tone_playing, which every tick caller loads into B first:
;
;   $441E  LDB >$3D27 / ANDB #$0F / ASLB
;   $4424  LDX #$43D4 / ABX / LDD ,X      A = the row, B = the column entry
;   $442A  PSHS A
;   $442C  LDA #$08 / JSR $43F4           register $08 <- the column tone
;   $4431  PULS B
;   $4433  LDA #$0A / JSR $43F4           register $0A <- the row tone
;   $4438  RTS
;
; FOR THE TICK ONLY, or for a caller holding dds_lock: see dtmf_tone_load.
; ---------------------------------------------------------------------------
dtmf_pair_write_nibble
                andb    #$0F
                aslb
                ldx     #dtmf_nibble_pairs
                abx
                ldd     ,x                      ; A = row, B = column entry
                pshs    a
                lda     #DDS_FREQ_BASE+DTMF_COL_CHANNEL
                lbsr    dtmf_tone_load          ; $08 <- the column tone
                puls    b
                lda     #DDS_FREQ_BASE+DTMF_ROW_CHANNEL
                lbsr    dtmf_tone_load          ; $0A <- the row tone
                rts

; ---------------------------------------------------------------------------
; dtmf_pair_write - the pair a KEYPAD MATRIX index names, straight to the port
;
;   entry: B = the matrix index; only its low four bits are read
;   uses:  A, B, X
;
; The same two loads as dtmf_pair_write_nibble, reached from the index the
; manual dial keeps rather than from a playlist nibble. The matrix is row times
; four plus column, so the row is the index shifted down twice - also the row
; tone's entry in dtmf_tone_fields - and the column tone's entry is the low two
; bits plus four, which is exactly the second byte index_pair_table holds for
; the same digit. The stock has no second numbering and so no such routine;
; this one exists because dtmf_current is a matrix index.
;
; MASKED, NOT REFUSED, as $4421's ANDB #$0F masks the stock's nibble: sixteen
; values are sixteen digits, so no index can reach past the tables. It refused
; anything above 15 with the carry once, and no caller read the carry -
; dtmf_current, the only index any caller passes, is written in one place, by
; dtmf_send after its own CMPB #DTMF_DIGITS / BHS refusal, and cleared to zero.
;
; FOR THE TICK ONLY, or for a caller holding dds_lock: see dtmf_tone_load.
; ---------------------------------------------------------------------------
dtmf_pair_write
                andb    #$0F                    ; as $4421's ANDB #$0F
                tfr     b,a
                lsra
                lsra                            ; A = the row, 0 to 3
                andb    #DTMF_COLUMNS-1
                addb    #DTMF_ROWS              ; B = the column entry, 4 to 7
                pshs    a
                lda     #DDS_FREQ_BASE+DTMF_COL_CHANNEL
                lbsr    dtmf_tone_load          ; $08 <- the column tone
                puls    b
                lda     #DDS_FREQ_BASE+DTMF_ROW_CHANNEL
                lbra    dtmf_tone_load          ; $0A <- the row tone

; ---------------------------------------------------------------------------
; THE FOREGROUND'S TWO ENTRIES, dtmf_pair_program_nibble and dtmf_pair_program.
;
; output_tone ($6A95) reaches dtmf_program_digit at $6AD1 from the
; foreground, and the stock guards that call with nothing. This firmware's
; foreground guards every DDS staging with dds_lock, which each tick body reads
; before it runs a tick, and masks IRQ and FIRQ as dds_write_wide does; these
; two keep that contract around the direct loaders, so a sequence running under
; a softkey cannot stage its own pair into the middle of this one.
; ---------------------------------------------------------------------------
; dtmf_pair_program_nibble - the pair a PLAYLIST nibble names, locked
;
;   entry: B = the nibble; only its low four bits are read
;   uses:  A, B, X
; ---------------------------------------------------------------------------
dtmf_pair_program_nibble
                inc     >dds_lock
                DISABLE_INTERRUPTS
                lbsr    dtmf_pair_write_nibble
                RESTORE_INTERRUPTS
                dec     >dds_lock
                rts

; ---------------------------------------------------------------------------
; dtmf_pair_program - the pair a KEYPAD MATRIX index names, locked
;
;   entry: B = the matrix index; only its low four bits are read
;   uses:  A, B, X
; ---------------------------------------------------------------------------
dtmf_pair_program
                inc     >dds_lock
                DISABLE_INTERRUPTS
                lbsr    dtmf_pair_write
                RESTORE_INTERRUPTS
                dec     >dds_lock
                rts

; ---------------------------------------------------------------------------
; dtmf_pair_level - the set level onto BOTH tones of the pair, each halved
;
;   uses:  A, B, X, Y, U
;
; apply_amplitude ($5F70) as a whole, which ampl_program_half now is. What is
; left here is the pair of channel numbers the DTMF screen passes it - the
; column into $08 and the row into $0A - and the record pointer it wants in X.
; Every caller of the halving is in this file or page1_tone.s, so the pair's
; level goes out through here and nowhere else.
;
; THE SET LEVEL IS KEPT BY ampl_program_half ITSELF, and this routine no
; longer keeps a second copy of it. $5F70 makes two copies - copy3 record+10
; into $221C at $5F76-$5F89 and copy3 $221C into the frame local at 5,S at
; $5F8B-$5F98 - halves only $221C in halve_amplitude_221c ($4439), writes the
; half into channels 0 and 2 at $5FAD and $5FF6, and at $601D-$602E copies the
; UNTOUCHED local back into channel 0's record. amplitude.s carries that whole
; shape now; it used to push the three bytes once and halve them in place, so
; its 'first record put back' wrote the HALF where the instrument writes what
; the operator set. This routine compensated for that by saving and restoring
; the record around the call, and with the halving fixed that compensation is
; a second writer of bytes ampl_program_half has already put back correctly -
; so it is gone rather than left standing as a duplicate.
;
; Measured against the stock, 2026-09-13: after DTMF Sequence is opened the
; instrument's channel 0 record holds 140 uV and channel 2's holds 70 - the
; set level and its half - where this firmware held 70 in both, and the AMPTD
; field on the mode's output record then read 50 uV after the operator keyed
; 100 where the instrument reads 100.
; ---------------------------------------------------------------------------
dtmf_pair_level
                ldb     #DTMF_COL_CHANNEL
                lbsr    dtmf_record             ; X = channel 0's record, the
                                                ; set level for the pair, which
                                                ; ampl_program_half reads and
                                                ; puts back itself
                lda     #DTMF_COL_CHANNEL       ; $5FCD: the column first
                ldb     #DTMF_ROW_CHANNEL       ; $600B: then the row
                lbra    ABI_ampl_program_half

; ---------------------------------------------------------------------------
; dtmf_gate_write - change the gate the way the stock's tick does
;
;   entry: B = DTMF_GATE_ON or DTMF_GATE_OFF
;   uses:  A, X - and B is READ ALL THE WAY THROUGH, so it is not free
;
; $44A6-$44CF, instruction for instruction. The value is compared with the last
; one written ($3D33 there, dtmf_gate here) and an unchanged value is not sent
; again. A changed one is stored and then written as the four-register stream
; in the constants' comment above: $22 <- $21, $26 <- $03, $26 <- $0B, $22 <-
; the value.
;
; STRAIGHT TO THE PORT, for the reason dtmf_sync_pulse gives above: four words
; through the general dds_write cost 137 instructions inside a period of 422,
; and the instrument sends them in seven. B is live from the compare to the
; last store, exactly as it is at $44A6-$44CF, so nothing is pushed.
;
; AND THE SEVEN NOPS AT $44B2 ARE PORTED WITH THE REST. The stock takes them
; only on the arm where the new value is $21 - the gate CLOSING - and the tone
; body has six of them in the same place, immediately before $4351. WHY HP PUT
; THEM THERE IS NOT ESTABLISHED and nothing in the ROM says. What they do is
; measurable and was measured: the closing edge lands seven instructions
; further into its tick than the opening edge does, so the stock's gate stands
; open for its programmed period PLUS SEVEN INSTRUCTIONS - 851 where the period
; is 844, 2117 where it is 2110, 4227 where it is 4220. Taken out again on
; purpose 2026-09-13 with everything else in place, this firmware's gate stood
; open for exactly seven fewer at all three, in the direction of a tone shorter
; than the instrument's.
;
; Runs from the timer interrupt, so it neither paints nor waits.
; ---------------------------------------------------------------------------
dtmf_gate_write
                cmpb    >dtmf_gate
                beq     dtmf_gate_same
                stb     >dtmf_gate              ; B STAYS LIVE to the last
                                                ; store, as $44A9's does
                cmpb    #DTMF_GATE_OFF          ; $44AE
                bne     dtmf_gate_stream
                nop                             ; $44B2-$44B8, and see above
                nop
                nop
                nop
                nop
                nop
                nop
dtmf_gate_stream
                ldx     #DDS_PORT_MUX_01*256+DTMF_GATE_OFF
                stx     >dds_prog               ; $22 <- $21
                ldx     #DDS_PULSE*256+DTMF_PULSE_LOW
                stx     >dds_prog               ; $26 <- $03
                lda     #DTMF_PULSE_HIGH
                sta     >dds_prog_data          ; $26 <- $0B, still selected
                lda     #DDS_PORT_MUX_01
                std     >dds_prog               ; $22 <- the value, still in B
dtmf_gate_same
                rts

; ---------------------------------------------------------------------------
; dtmf_gate_idle - register $22 back to the idle code, unconditionally
;
;   uses:  A, B, X, Y
;
; dds_set_output_mode_reg22 ($6B92) with argument 0, through dds_write_reg22
; ($6B6F): one write of $21 with no compare against $3D33. Every stop in the
; stock ends with it, and so does mode entry.
; ---------------------------------------------------------------------------
dtmf_gate_idle
                ldx     #DTMF_GATE_OFF
                ldb     #DDS_PORT_MUX_01
                lbra    ABI_dds_write

; ---------------------------------------------------------------------------
; dtmf_sync_pulse - register $29 <- $00 then $10, the top of every tick
;
;   uses:  A, X
;
; $448C-$4494, quoted at DDS_SYNC_REG above, PORTED AS THE PORT WRITES IT IS.
;
;       ldx   #$2900        the register select and the data, one store
;       stx   >dds_prog
;       lda   #$10          the register is still selected, so the second
;       sta   >dds_prog_data     word is one byte
;
; Four instructions, and it used to be two calls to the general dds_write -
; forty each, because that routine takes dds_lock, masks interrupts, looks the
; register's width up in dds_descriptors and maintains dds_shadow. NONE of
; that belongs inside an interrupt body: measured on the emulator 2026-09-13,
; the six words this tick sends cost 270 of its 457 instructions, and one
; period at the default On Time of 1.00 ms is 422. The instrument's own NMI
; body reaches the port directly for exactly this reason, and this is that
; body.
;
; WHAT IS GIVEN UP IS WHAT THE STOCK GIVES UP. dds_shadow no longer records
; register $29 from a tick; the stock's $448C does not touch its shadow either,
; and the only reader is the service screen that displays a register. The
; interrupt masking was already redundant - the CPU sets I and F when it takes
; the NMI - and dds_lock guards the foreground against this tick, which cannot
; interrupt itself.
; ---------------------------------------------------------------------------
dtmf_sync_pulse
                ldx     #DDS_SYNC_REG*256+DTMF_SYNC_CLEAR
                stx     >dds_prog
                lda     #DTMF_SYNC_SET
                sta     >dds_prog_data
                rts

; ---------------------------------------------------------------------------
; dtmf_sync_clear - register $29 <- $00, the stop's write
;
;   uses:  A, B, X, Y
;
; dds_write_reg29 ($6B4C) with 0, as seq_timer_stop ($6C22) and
; sequence_stop_from_isr ($6C45) both call it.
; ---------------------------------------------------------------------------
dtmf_sync_clear
                ldx     #DTMF_SYNC_CLEAR
                ldb     #DDS_SYNC_REG
                lbra    ABI_dds_write

; ---------------------------------------------------------------------------
; dtmf_phase_pulse - the automatic phase reset, unless the operator turned it off
;
;   uses:  A, B, X
;
; dds_update_strobe_if_idle ($4AD1) is what output_tone ($6A95) calls after
; programming a pair while the sequencer is not running, and with the special
; flag clear it reaches dds_reg26_bit3_pulse ($DE7F): register $26 written
; with its shadow ANDed $F7, then with the shadow as it stood. That is
; dds_phase_reset in dds.s, reached through ABI slot 72; this routine is the
; name the DTMF paths call it by.
; ---------------------------------------------------------------------------
dtmf_phase_pulse
                lbra    ABI_dds_phase_reset

; ---------------------------------------------------------------------------
; dtmf_send - put a digit on the output
;
;   entry: B = the digit index
;   exit:  carry SET if the index is out of range and nothing was programmed
;   uses:  A, B, X, Y, U
;
; THE START, as the stock executing shows it when a digit key arrives with
; Manual Dial armed (emulator/tests/test_dtmf_stream_new.py logs it and
; holds this routine's writes to it). sequence_mode_message_handler ($4C01) first undoes
; the borrow through manual_dial_end_restore ($48C1), whose seq_output_stop
; ($4881) ends in $22 <- $21; then manual_dial_digit ($6540) writes the digit
; into sequence step 0 and calls seq_run_single ($4A5F), which stops and
; restarts through seq_output_set_running ($4702): the stop is seq_timer_stop
; ($6C22) - CR2 <- $91 and $29 <- $00 - then output_tone ($6A95) programs the
; pair and, the running flag being clear, strobes register $26; the start
; programs the pair once more without the strobe and start_sequence_timer
; ($6BD0) loads two hundred counts and enables the interrupt. The level
; halving between the stop and the pair is this firmware's own placement:
; the stock halves at level entry through apply_amplitude ($5F70).
;
; Both tones are programmed BEFORE the gate opens, so the socket never
; carries one of the pair on its own.
; ---------------------------------------------------------------------------
dtmf_send
                pshs    b                       ; THE DIGIT INDEX, PUSHED
                                                ; FIRST. The guards below
                                                ; destroy B and branch to
                                                ; tails whose `puls b`
                                                ; matches this push

                ; THREE BOARDS OR NOTHING. installed_channels is a PROBED
                ; count, not a claim: count_installed_channels sets bit 7 of
                ; each latch, strobes $0800 and reads int_latch back.
                ldb     #DTMF_ROW_CHANNEL
                lbsr    ABI_channel_valid       ; carry CLEAR when fitted
                bcs     dtmf_send_no_board      ; NOT dtmf_send_bad, which
                                                ; reports ERR_VALUE_RANGE -
                                                ; the refusal there is about
                                                ; the digit typed, and this
                                                ; one is about the instrument
                                                ; not having the boards

                ldb     ,s                      ; and the digit back
                cmpb    #DTMF_DIGITS
                bhs     dtmf_send_bad

                lbsr    dtmf_silence            ; manual_dial_end_restore,
                                                ; with the digit it is still
                                                ; holding
                ldb     ,s
                stb     >dtmf_current           ; seq_put_nibble at $657D:
                                                ; the new digit is in step 0
                                                ; before anything sounds
                lbsr    dtmf_echo_show          ; and echoed before the
                                                ; sequence starts, as
                                                ; manual_dial_digit does at
                                                ; $6790, ahead of its
                                                ; seq_run_single at $67A0
                lbsr    ABI_tick_remove         ; seq_timer_stop: CR2 <- $91
                lbsr    dtmf_sync_clear         ; ... and $29 <- $00

                ; EACH GENERATOR AT HALF THE SET LEVEL, before either is
                ; let out. Two tones are summed into one output, so a pair
                ; programmed at the full level comes out at twice it.
                ;
                ; The stock's apply_amplitude ($5F70) does the same halving
                ; through halve_amplitude_221c ($4439), gated on its DTMF flag
                ; $3C03, and applies the result to both generators.
                ;
                ; The COLUMN channel's record carries the set level for the
                ; pair. That is this firmware's choice - the stock reads
                ; whichever record $23BF points at - and it is written down
                ; rather than left to be inferred.
                ;
                ; ONE CALL, NOT TWO. It was two, one per generator, and that
                ; cannot be right: apply_amplitude ($5F70) puts the halved
                ; level into BOTH records before its second $C069, so the
                ; sum that dispatch builds over the socket has half from each.
                ; Two calls that each put a record back give the second one a
                ; first channel already restored to the set level.
                lbsr    dtmf_pair_level         ; and the set level is kept
                                                ; across it, as $5F70 keeps it

                ldb     >dtmf_current
                lbsr    dtmf_pair_program       ; output_tone(tone, 0)
                lbsr    dtmf_phase_pulse        ; and its strobe
                ldb     >dtmf_current
                lbsr    dtmf_pair_program       ; output_tone(tone, 1): the
                                                ; same pair, no strobe

                ; THE OUTPUT RELAYS, bit 2 of each channel's latch, active
                ; low, through the shadow so the range field of each channel
                ; survives. This firmware's instrument_preset opens them at
                ; every mode entry, so they are closed here; the stock leaves
                ; them where its channel apply put them.
                ldb     #DTMF_COL_CHANNEL
                lbsr    dtmf_enable
                ldb     #DTMF_ROW_CHANNEL
                lbsr    dtmf_enable

                ; AND THE TIMER, as start_sequence_timer ($6BD0) seeds it:
                ; $3D33 = 0 so the first tick writes the gate stream whatever
                ; register $22 holds, $3D32 = 2 so the first phase is an even
                ; one, and two hundred counts to the first interrupt. The
                ; ticks from there are dtmf_tick_step.
                clr     >dtmf_gate
                clr     >dtmf_tick
                ldd     #DTMF_START_COUNTS+1    ; THE START LATCH IS RAW. $6BD0
                                                ; does LDD #$00C8 / STD >ptm_
                                                ; timer2 - no minus one - where
                                                ; the NMI's tick latches are
                                                ; $3D30-1 ($4309). tick_install
                                                ; subtracts one from every
                                                ; period (timer.s seq_timer_
                                                ; start), so the first period
                                                ; is handed over one high to
                                                ; land $00C8 on the chip, as
                                                ; test_dtmf_stream_new.py
                                                ; checks against the stock
                ldx     #dtmf_tick_step
                lbsr    ABI_tick_install        ; latches, CR1 reset pulse,
                                                ; CR2 <- $D1: the stock's
                                                ; order, in timer.s
                puls    b
                andcc   #~CC_CARRY
                rts

dtmf_send_no_board
                puls    b
                ldb     #ERR_NO_SUCH_CHANNEL    ; three boards are needed and
                bra     dtmf_send_raise         ; fewer are fitted
dtmf_send_bad
                puls    b
                ldb     #ERR_VALUE_RANGE
dtmf_send_raise
                lbsr    ABI_error_raise
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; dtmf_tick_step - one interrupt of the dial, the stock's $444C body
;
;   entry: through nmi_callback; the CPU has stacked every register
;   exit:  RTI, on every path
;
; RUNS FROM TIMER 2, jumped to by nmi_handler, once per interrupt while the
; dial is installed. It is the body at $444C, and like it it opens with the
; status and counter reads that clear the interrupt and owns its RTI; after
; them it tests dds_lock, as tone_advance does and for its reason. Then:
;
;   $447A  A = the phase $3D32; with the single-shot flag $3C81 set and the
;          once-through flag $3D34 clear, the stop path at $44D1 - which for
;          a dialled digit is the fourth interrupt, seq_step_advance ($42B1)
;          having cleared $3D34 when the position wrapped past Seq End 0
;   $448C  $29 <- $00, $29 <- $10
;   $449B  B = $21 for an even phase, $22 for an odd one
;   $44A6  compare with $3D33; if changed, store and write the gate stream
;   $44E6  seq_step_advance / load_current_step: the phase advances, and the
;          duration is the On Time for an odd phase and $00C8 for the even one
;   $44EE  dtmf_program_digit: the pair again
;   $44F1  timer 2 <- the duration minus one
;
; The order of the last two is kept: the pair is programmed before the
; latches are written.
; ---------------------------------------------------------------------------
dtmf_tick_step
                lda     >ptm_status             ; the clear: status, then the
                ldx     >ptm_timer2             ; counter
                tst     >dds_lock               ; the foreground mid-way
                bne     dtmf_tick_late          ; through staging a register
                lda     >dtmf_tick
                cmpa    #DTMF_TICKS
                blo     dtmf_tick_go
                lbsr    dtmf_tick_stop          ; the fourth interrupt
dtmf_tick_late
                rti
dtmf_tick_go

                lbsr    dtmf_sync_pulse         ; $29 <- $00, $29 <- $10

                ; BOTH ARMS COST THE SAME, which is why the second one ends in
                ; a branch to the instruction after it. $449B-$44A6 does
                ; LDA/ASRA/BCS, then LDB #$21 / BRA $44A6 on one arm and
                ; LDB #$22 / BRA $44A6 on the other, with one dead byte
                ; between the second BRA and its target. That BRA looks
                ; redundant and is not: without it the fall-through arm is one
                ; instruction shorter than the branching one, and the gate edge
                ; on that arm lands one instruction earlier in the tick.
                ; Measured 2026-09-13 with only this branch missing, the gate
                ; stood open for 428 instructions where the instrument holds it
                ; for 429, at every On Time. The dead byte is not reproduced -
                ; nothing executes it - but its BRA is.
                lda     >dtmf_tick
                anda    #$01
                beq     dtmf_tick_gate_off
                ldb     #DTMF_GATE_ON           ; an odd phase sounds
                bra     dtmf_tick_gate
dtmf_tick_gate_off
                ldb     #DTMF_GATE_OFF          ; an even one is idle
                bra     dtmf_tick_gate          ; and see above: not redundant
dtmf_tick_gate
                lbsr    dtmf_gate_write

                inc     >dtmf_tick              ; the phase advances
                ldb     >dtmf_current
                lbsr    dtmf_pair_write         ; dtmf_program_digit, direct

                lda     >dtmf_tick
                anda    #$01
                beq     dtmf_tick_gap
                lbsr    dtmf_time_now           ; the On Time for an odd
                bra     dtmf_tick_period        ; phase
dtmf_tick_gap
                ldd     #DTMF_GAP_COUNTS        ; and $00C8 for the even one
dtmf_tick_period
                lbsr    ABI_seq_timer_period    ; timer 2 <- D - 1
                rti

; ---------------------------------------------------------------------------
; dtmf_tick_stop - the fourth interrupt: the stop path at $44D1
;
;   uses:  A, B, X, Y, U
;
; Every write in the order the stock makes it:
;
;   $44D1  $3D33 = $21 and $22 <- $21, one STD with no compare
;   $44DB  CR2 <- $91
;   $44E0  sequence_stop_from_isr ($6C45): seq_output_stop ($4881), whose
;          seq_output_set_running ($4702) with 0 runs seq_timer_stop ($6C22)
;          - CR2 <- $91 through the shadow and $29 <- $00 - then output_tone
;          ($6A95), the pair and the strobe; then $22 <- $21; then, $3C04
;          being set, blank_dial_echo ($5BF5) with the display's address
;          counter saved around it; then $29 <- $00 once more
;   $44EE  dtmf_program_digit and timer 2 <- $3D30 - 1, the interrupt being
;          off by then
;
; tick_remove writes CR2 once where the stock writes it twice with the same
; value, the second time through the shadow; the register is left the same.
; ---------------------------------------------------------------------------
dtmf_tick_stop
                ldb     #DTMF_GATE_OFF
                stb     >dtmf_gate              ; $44D3 STB >$3D33
                lbsr    dtmf_gate_idle          ; $44D5: $22 <- $21
                lda     #DTMF_TICK_IDLE
                sta     >dtmf_tick
                lbsr    ABI_tick_remove         ; CR2 <- $91
                lbsr    dtmf_sync_clear         ; $29 <- $00
                ldb     >dtmf_current
                lbsr    dtmf_pair_write         ; output_tone(tone, 0), direct
                lbsr    dtmf_phase_pulse        ; dds_update_strobe_if_idle
                lbsr    dtmf_gate_idle          ; dds_set_output_mode_reg22(0)
                lbsr    dtmf_echo_blank         ; blank_dial_echo ($5BF5)
                lbsr    dtmf_sync_clear         ; the ISR's own $29 <- $00
                ldb     >dtmf_current
                lbsr    dtmf_pair_write         ; $44EE, direct
                lbsr    dtmf_time_now
                lbra    ABI_seq_timer_period    ; $44F1, with nothing left to
                                                ; hear it

; ---------------------------------------------------------------------------
; dtmf_echo_blank - blank the digit cell from inside the interrupt
;
;   uses:  A, B, X
;
; blank_dial_echo ($5BF5) writes one blank where the dialled character was
; echoed, and sequence_stop_from_isr ($6C45) brackets it with
; lcd_read_address_counter ($D781) before and lcd_set_cursor ($D7A0) after,
; so a foreground write the interrupt landed in the middle of carries on
; where it was. $D781 spins on bit 7 of $0300 - the busy flag - and returns
; the byte; the same read is made here through lcd_instr, and the counter
; is put back through ABI_lcd_cursor.
; ---------------------------------------------------------------------------
dtmf_echo_blank
                lda     >lcd_instr              ; bit 7 set: still busy
                bmi     dtmf_echo_blank
                anda    #$7F                    ; the address counter
                pshs    a
                lda     #DTMF_DIGIT_POS
                ldx     #dtmf_spaces
                ldb     #1
                lbsr    ABI_lcd_write
                puls    a
                lbra    ABI_lcd_cursor          ; back where the foreground was

; ---------------------------------------------------------------------------
; dtmf_echo_show - paint the digit being dialled
;
;   uses:  A, B, X
;
; manual_dial_digit ($6540) echoes the typed character at column $23 of the
; page-1 line through lcd_write_field_if_page ($56A4) at $6790, before it
; starts the sequence; the stop blanks the same cell. The cell here is
; DTMF_DIGIT_POS and the character is the digit's name.
; ---------------------------------------------------------------------------
dtmf_echo_show
                ldb     >dtmf_current
                cmpb    #DTMF_DIGITS
                bhs     dtmf_echo_show_done
                ldx     #dtmf_names
                leax    b,x
                lda     #DTMF_DIGIT_POS
                ldb     #1
                lbra    ABI_lcd_write
dtmf_echo_show_done
                rts

; ---------------------------------------------------------------------------
; dtmf_record - one channel's record
;
;   entry: B = the channel
;   exit:  X = its twelve-byte record
;   uses:  A, B, X
;
; The channel records are a flat array in the live state, CHAN_RECORD bytes
; apart. Masked to four, because a wild channel number here would index past
; the array and ampl_program_half would read a level out of whatever followed.
; ---------------------------------------------------------------------------
dtmf_record
                andb    #$03
                lda     #CHAN_RECORD
                mul                             ; D = channel * 12
                ldx     #channel_records
                leax    d,x
                rts

; ---------------------------------------------------------------------------
; dtmf_silence - stop sending, the way a key stops the stock's dial
;
;   uses:  A, B, X, Y, U
;
; manual_dial_end_restore ($48C1) calls seq_output_stop ($4881). With the
; running flag $3C80 set that is seq_output_set_running ($4702) with 0 -
; seq_timer_stop ($6C22), CR2 <- $91 and $29 <- $00, then output_tone
; ($6A95), the pair and its strobe - and in either case it ends in
; dds_set_output_mode_reg22 ($6B92) with 0, $22 <- $21. The trace shows
; exactly that pair of writes for the idle case, when the Manual Dial
; softkey is pressed.
;
; The tick is removed BEFORE the state says idle, so an interrupt cannot land
; between the two and run the stop path a second time.
; ---------------------------------------------------------------------------
dtmf_silence
                lda     >dtmf_tick
                cmpa    #DTMF_TICK_IDLE
                beq     dtmf_silence_idle
                lbsr    ABI_tick_remove         ; seq_timer_stop: CR2 <- $91
                lda     #DTMF_TICK_IDLE
                sta     >dtmf_tick
                lbsr    dtmf_sync_clear         ; ... and $29 <- $00
                ldb     >dtmf_current
                lbsr    dtmf_pair_program       ; output_tone(tone, 0)
                lbsr    dtmf_phase_pulse        ; and its strobe
dtmf_silence_idle
                lbra    dtmf_gate_idle          ; $22 <- $21

; ---------------------------------------------------------------------------
; dtmf_enable - close one of the pair's output relays
;
;   entry: B = the channel
;   uses:  A, B, X
;
; Bit 2 of the channel latch, through the shadow so the range field and the
; float bit of that channel are not disturbed. A direct write would clear
; them, and the range field is four bits of amplitude exponent - up to
; fifteen octaves. hardware.inc carries the evidence that the bit is active
; low, from set_output_enable ($B79C) writing $04 to switch a channel off.
; ---------------------------------------------------------------------------
dtmf_enable
                inc     >dds_lock               ; THE STORE AND THE CALL
                                                ; ARE ONE OPERATION. An
                                                ; NMI landing between
                                                ; them would leave this
                                                ; writing the sequence
                                                ; player's value into a
                                                ; channel latch; see
                                                ; channel_latch_rmw.
                clr     >latch_bits             ; CLEAR is on
                lda     #LATCH_OUTPUT
                lbsr    ABI_channel_latch_rmw
                dec     >dds_lock
                rts

; ---------------------------------------------------------------------------
; dtmf_time_now - the On time of the tone the screen is showing
;
;   exit:  D = it, in timer counts
;   uses:  A, B, X
;
; The stock keeps ONE set of times for both modes, four bytes a tone at $3C10,
; and select_tone_and_time_pointers ($561A) indexes it with the tone number for
; the tone screen and the dialler alike. This mode had a cell of its own, so a
; time typed on the shared screen went into the tone's record and the dialler
; went on using the other one.
; ---------------------------------------------------------------------------
dtmf_time_now
                ldb     >tone_number
                lbsr    tone_times_address      ; X = the tone's pair
                ldd     ,x                      ; TONE_ON is offset zero
                rts

; ---------------------------------------------------------------------------
; dtmf_show - the DTMF screen
;
;   uses:  A, B, X, Y, U
;
; Line 2 carries the digit while one is sounding - blank otherwise, which is
; what blank_dial_echo leaves - and the On Time as the stock's screen renders
; a time: the count divided by a hundred with two places, "1.00" for the
; default. While the On Time field is taking digits the readout gives way to
; the digits typed so far.
; ---------------------------------------------------------------------------
dtmf_show
                lda     #LCD_LINE1
                ldx     #dtmf_title
                ldb     #SVC_LABEL_LEN
                lbsr    ABI_lcd_write

                lda     #LCD_LINE2
                ldx     #dtmf_line2
                ldb     #SVC_LABEL_LEN
                lbsr    ABI_lcd_write

                lda     >dtmf_tick              ; the digit, while it sounds
                cmpa    #DTMF_TICK_IDLE
                beq     dtmf_show_time
                ldb     >dtmf_current           ; which digit, by name
                cmpb    #DTMF_DIGITS
                bhs     dtmf_show_time
                ldx     #dtmf_names
                leax    b,x
                lda     #DTMF_DIGIT_POS
                ldb     #1
                lbsr    ABI_lcd_write

dtmf_show_time
                tst     >dtmf_field
                bne     dtmf_show_echo
                clr     >dtmf_word              ; the count widened to the 24
                lbsr    dtmf_time_now           ; bits the formatter takes
                std     >dtmf_word+1
                ldu     #dtmf_word
                ldb     #DTMF_TIME_PLACES
                lbsr    ABI_format_places       ; chan_text = "   655.35"
                lda     #DTMF_TIME_POS
                ldx     #chan_text+2            ; the last seven of the nine
                ldb     #DTMF_TIME_W
                lbra    ABI_lcd_write

dtmf_show_echo
                lda     #DTMF_TIME_POS          ; the front of the readout
                ldx     #dtmf_spaces            ; blanked
                ldb     #4
                lbsr    ABI_lcd_write_raw       ; THE ECHO AND ITS BLANK go to
                ldx     #text_buffer            ; the glass only, as
                                                ; $B53D-$B555 writes them
                lbsr    ABI_entry_render        ; with lcd_write_string_at
                lda     #DTMF_ECHO_POS          ; ($D8A5); the readout stays
                ldx     #text_buffer            ; in the shadow
                ldb     #DTMF_ON_DIGITS
                lbra    ABI_lcd_write_raw

; ---------------------------------------------------------------------------
; dtmf_sequence_open - the mode entry point, reached through $4004
;
;   entry: U = the entry reason: MODE_COLD, MODE_RECALL or MODE_KEEP
;   exit:  the DTMF screen is showing with the output silent
;   uses:  A, B, X, Y, U
;
; Page 1 carries two modes and this is its second entry vector. Both stop
; whatever was playing before painting, for the reason given in
; tone_sequence_open: a screen that describes a state the instrument is not
; in is worse than no screen.
;
; The stock's mode entry, enter_dtmf_sequence_mode ($7A81) into
; sequence_mode_init ($5380) with reason 0, runs seq_mode_defaults ($5224):
; every On and Off Time to $0064 and register $22 to $21. The On Time here is
; reset the same way, so a value typed on the last visit does not carry over
; where the stock's would not.
; ---------------------------------------------------------------------------
dtmf_sequence_open
                ; THE ENTRY REASON, kept on the stack for the whole entry as
                ; tone_sequence_open keeps it, and for the same reason:
                ; sequence_mode_init reads it at five places spread through
                ; what follows. It comes off at the one exit.
                tfr     u,d
                cmpd    #MODE_RECALL
                beq     dtmf_sequence_open_reason
                cmpd    #MODE_KEEP
                beq     dtmf_sequence_open_reason
                clrb                            ; cold
dtmf_sequence_open_reason
                pshs    b                       ; 0,s: the reason
                ; NO OPTION CHECK. The stock's page-1 and page-2 routines never
                ; read installed_options - docs/routine-index.txt lists every
                ; stock reader and none is on these pages. The option gates
                ; the Main Selection's slots, once, at power-on (main_menu.s,
                ; main_menu_latch). A gate here, read live, refused a mode the
                ; instrument opens after ST_ID clears $3FFC: seed 11 step 13.
                lda     #$01                    ; THE DIGIT READING of the
                sta     >tone_dtmf_mode         ; shared playlist, as
                                                ; enter_dtmf_sequence_mode
                                                ; ($7A81) sets $3C03 at $7A97.
                                                ; One sequence, read two ways.
                tst     ,s                      ; THE PRESET AND THE RECORD
                bne     dtmf_sequence_open_preset ; DEFAULTS ARE REASON 0'S,
                                                ; as in tone_sequence_open
                lbsr    ABI_instrument_preset   ; QUIESCE FIRST, as the stock
                                                ; does at every mode entry:
                                                ; whatever the last mode left
                                                ; driving stops driving before
                                                ; this screen goes up - and
                                                ; instrument_preset removes
                                                ; the tick, so no dial is
                                                ; running past this line
                ; THE TONE MODE'S SCREEN LAYER, with the dialled flag set.
                ; The instrument's DTMF Sequence Mode is the SAME four records
                ; as its Tone Sequence Mode with two of its own - the title at
                ; $4193 and record 1 at $41E3, which carries ' Manual Dial' on
                ; f3 where the tone record carries the FREQ field - and the
                ; sequence window's E and F rendered as '*' and '#'. Its table
                ; is $4234, whose first word is $4193.
                ;
                ; This mode had a screen of its own: 'DTMF Generator' over
                ; 'Sending:     On Time   1.00 ms   f4=seq ', with no Tone
                ; Number field, no Seq Index, no window, no Seq End, no AMPTD
                ; row and no paging at all - NEXT did nothing on it. Walked
                ; side by side on 2026-09-11.
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
                ; AND THE TWO THINGS THE MODE DOES TO THE CHANNELS
                ; ITSELF, which the reapply above cannot know about.
                ;
                ; CHANNEL 1 CARRIES 100 kHz, from the constant at page 1's
                ; $425F: seq_mode_defaults ($5224) forces $23BE to 1 at
                ; $524A, re-caches the record pointer at $5252, copies the
                ; three bytes into it at $5280, programs register $09 at
                ; $5292, zeroes the record's level at $52A6 and programs that
                ; too at $52BC. Why the instrument wants a carrier there is
                ; not established by the ROM - the constant is a literal with
                ; no arithmetic behind it - but it is there on purpose, and
                ; leaving it out left this firmware's channel 1 at 1 kHz
                ; where the instrument's is at 100 kHz. The differential
                ; harness reported it against the stock on 2026-09-12.
                ;
                ; The record is written BEFORE the reapply rather than after
                ; it, so the values reach the chip through the one path that
                ; programs a record - which lands the same state in one pass
                ; where the stock takes two. The ORDER of the words on the
                ; bus differs by that much and the state does not.
dtmf_sequence_open_preset
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
                lbne    dtmf_sequence_open_kept ; seq_mode_defaults', reason 0
                ldx     #channel_records+CHAN_RECORD
                lda     #$0F
                sta     ,x                      ; CHAN_FREQ is offset zero,
                                                ; and the two assemblers spell
                                                ; a WRITTEN zero offset
                                                ; differently - $84 against
                                                ; $00, both one byte and both
                                                ; correct - so the no-offset
                                                ; form is the one that makes
                                                ; them agree
                lda     #$42
                sta     CHAN_FREQ+1,x
                lda     #$40
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
                bra     dtmf_sequence_open_applied

                ; A RECALL OR A KEEP-STATE ENTRY APPLIES THE RECORDS IT HAS:
                ; l53ee, as tone_sequence_open_kept describes - $C5B1, and on
                ; reason 1 alone the four output latches through $DBA1.
dtmf_sequence_open_kept
                lda     ,s
                cmpa    #MODE_RECALL
                bne     dtmf_sequence_open_keep
                lbsr    ABI_register_apply      ; $C5B1 and the latch walk
                bra     dtmf_sequence_open_applied
dtmf_sequence_open_keep
                lbsr    ABI_channel_reapply_all ; $C5B1 alone
dtmf_sequence_open_applied

                ; --- $5483-$54AB: CHANNEL 0 IS ROUTED BACK TO Out1 --------
                ; The park above took every destination out of the records;
                ; sequence_mode_init ($5380) puts exactly one of them back and
                ; routes it, and it does so on a DIALLED entry exactly as on a
                ; tone one - $5483-$54AB sits ABOVE the $3C03 test at $54AE,
                ; not inside it. CLR >$23BE selects channel 0,
                ; cache_channel_record_ptr ($C21A) re-caches its pointer, LDX
                ; >$23BF / LEAX <$21,X / LDD #$000C / STD ,X writes $000C - the
                ; code for Out1 - into the record's destination word, and
                ; route_source_selector ($C7B0) is then called with channel 0
                ; and that same $000C to put the socket's multiplexer field on
                ; the channel.
                ;
                ; NOTHING THIS MODE PROGRAMS IS AUDIBLE WITHOUT IT, and the
                ; level path refuses outright: ampl_propagate reads
                ; routed_dest, finds Off and programs zero ($BE8F-$BE9C), and
                ; ampl_set on an Off channel refuses the AMPTD the operator
                ; keys. Measured against the stock through the differential
                ; harness, 2026-09-13: opening DTMF Sequence left the
                ; instrument at level codes (939, 0, 939, 0) and this firmware
                ; at (0, 0, 0, 0), and keying AMPTD 100 uV on the mode's output
                ; record was taken by the instrument and refused here.
                ;
                ; destn_apply is the routine that does BOTH: it stores the code
                ; in routed_dest and CHAN_DEST and routes it. Writing CHAN_DEST
                ; alone is not enough - ampl_propagate reads routed_dest, not
                ; the record. Nothing can refuse it: destn_check's refusals are
                ; a channel modulating itself, a dc conflict with another
                ; channel and a destination the options do not cover, and the
                ; park above has just left every socket free.
                lda     #DTMF_COL_CHANNEL       ; channel 0
                ldb     #LBL_OUT1               ; $000C
                lbsr    ABI_destn_apply

                ; --- $54AE-$54E0: THE DIALLED ENTRY'S OWN FOUR WRITES -----
                ; sequence_mode_init tests $3C03 at $54AE and, only when it
                ; says DTMF, does these four things and no others:
                ;
                ;   $54BC  dds_write_reg1f ($6B0C) with 5  - register $1F <- 5
                ;   $54D2  dds_write_reg20 ($6B29) with 4  - register $20 <- 4
                ;   $54D8  LDD #$000C / STD >$255C
                ;   $54DE  LDD #$0005 / STD >$2548
                ;
                ; $255C AND $2548 ARE CHANNEL 2's RECORD, not two loose cells,
                ; and that is the whole of why the instrument's ROW tone is
                ; audible. The channel records are a 35-byte array based at
                ; $24F5 - array_descriptor_c8b4 ($C8B4) holds $0001, $0000,
                ; $0023 and cache_channel_record_ptr ($C21A) indexes it with
                ; $23BE - so record 2 begins at $24F5 + 2*$23 = $253B, its
                ; destination word at +$21 is $255C and its function selector
                ; at +13 is $2548. The dialled entry therefore gives CHANNEL 2
                ; THE SAME DESTINATION AND THE SAME LEVEL HANDLER AS CHANNEL 0:
                ; Out1, and arm 5 of the $C163 table that
                ; dispatch_channel_function ($C069) jumps through, which is the
                ; socket level path channel_apply_and_propagate ($BE5C). A pair
                ; is two generators summed into one socket and only one of them
                ; was on it.
                ;
                ; THIS FIRMWARE KEEPS THE STOCK'S ONE FIELD IN TWO CELLS, so
                ; the one stock write is two here: routed_dest IS record+$21,
                ; as ampl_propagate's own header quotes ($BE5C-$BE7B), and
                ; CHAN_DEST is the record's copy that ampl_reapply reads to
                ; pick the unit arm - which is the job record+13 does on the
                ; instrument. NOTHING ROUTES CHANNEL 2 ON THE CHIP, because the
                ; stock does not either: route_source_selector is called once,
                ; for channel 0, at $54A6.
                ldx     #$0005                  ; $1F, HP's 'chanadd' - arm
                ldb     #DDS_SUM_MASK           ; [31] of the register-name
                lbsr    ABI_dds_write           ; table at page 3's $568F
                ldx     #$0004                  ; $20, HP's 'out_mux' - arm
                ldb     #DDS_SUM_NODE           ; [32] of the same table
                lbsr    ABI_dds_write
                ldb     #DTMF_ROW_CHANNEL       ; channel 2
                lbsr    dtmf_record             ; X = its record
                lda     #LBL_OUT1
                sta     CHAN_DEST,x             ; $2548's job in this shape
                sta     >routed_dest+DTMF_ROW_CHANNEL   ; and $255C's

                ; --- $54E2: apply_amplitude ($5F70), WHICH HALVES ---------
                ; The entry's level call. In DTMF mode $5F70 halves the set
                ; level through halve_amplitude_221c ($4439), writes the half
                ; into channel 0's record and dispatches it, then into channel
                ; 2's record and dispatches that, and finally puts channel 0's
                ; record back to the level the operator set. ampl_program_half
                ; is that routine instruction for instruction; its header
                ; carries the correspondence.
                ;
                ; TWO GENERATORS SUMMED INTO ONE SOCKET need half the level
                ; each or the pair comes out at twice it, which is why the
                ; halving is here and not a property of the digit.
                lbsr    dtmf_pair_level

                ; AND THE SIXTEEN TONE SLOTS GO DOWN TO THE CHIP, on this
                ; entry as much as on the tone one: seq_mode_defaults ($5224)
                ; calls download_all_tone_frequencies ($6A57) at $5329 and the
                ; dialled entry runs seq_mode_defaults - $53D6 tests the reason
                ; and enter_dtmf_sequence_mode ($7A81) passes 0. See
                ; tone_download_all for what a slot costs and why the chip
                ; wants all sixteen.
                ;
                ; IT GOES AFTER THE ROUTING for the reason tone_sequence_open
                ; records: destn_apply is the port of the whole of
                ; set_channel_destination ($78BF) and re-applies the record's
                ; frequency as the channel joins the socket, so with the
                ; download first this firmware would end the entry with the
                ; record's 1 kHz in register $08. Here the pair overwrites $08
                ; and $0A a few lines further down in any case, but the order
                ; is the tone screen's so the two entries cannot drift apart.
                lbsr    tone_download_all

                ; AND CHANNEL 0's FILTER LINE GOES IN. seq_mode_defaults
                ; loads #$01 at $536C and calls set_channel_byte_24ec ($F713)
                ; at $5378 with index 0, so a sequence mode forces channel
                ; 0's filter byte to 1 and drives the line from it. Measured
                ; against the stock: its channel 0 latch reads $01 after this
                ; entry and this firmware's read $00. seq_mode_defaults, so
                ; reason 0's alone.
                tst     ,s                      ; the reason
                bne     dtmf_sequence_open_filter
                lda     #LATCH_FILTER
                clrb                            ; channel 0
                lbsr    ABI_filter_force
dtmf_sequence_open_filter
                ldx     #tone_key
                lbsr    ABI_screen_install
                lda     #SEQKIND_TONE           ; THE SAME SLOT AS THE TONE
                sta     >seq_kind_live          ; SCREEN: DTMF is the same
                                                ; playlist read differently,
                                                ; and the instrument saves
                                                ; both through save_sequence_setup
                                                ; ($6CD7)
                lda     #DTMF_TICK_IDLE
                sta     >dtmf_tick
                lbsr    dtmf_silence            ; $22 <- $21, the mode's
                                                ; dds_set_output_mode_reg22(0)
                                                ; at $54EC
                ldx     #DTMF_ZERO_LT_RUN       ; and $1C <- 2 behind it, which
                ldb     #DDS_ZERO_LT            ; is $5500 - the write that
                lbsr    ABI_dds_write           ; closes every mode entry
                ; THE TIMES ARE THE TONE SEQUENCE'S, one pair per tone at
                ; $3C10 - the stock keeps ONE set for both modes and
                ; seq_mode_defaults ($5224) fills them for either entry. This
                ; mode had a cell of its own, so a time typed on the shared
                ; screen went to the tone record and the dialler went on using
                ; its own.
                clr     >dtmf_field
                clr     >entry_active
                clr     >dtmf_current           ; THE BYTE THE SCREEN READS
                clr     >dtmf_position

                ; AND THE MODE'S OWN STATE, which is the tone sequence's state
                ; read differently. seq_data_init ($79FE) and seq_mode_defaults
                ; ($5224) run on a dialled entry exactly as they do on a tone
                ; one - the 250 steps as the repeating 0 to F the window shows
                ; with its last two as '*' and '#', both times a hundred counts
                ; - so the screen opens on the same sequence the instrument
                ; opens on, and not on an empty one.
                ;
                ; ON A COLD ENTRY. This said "both mode entries pass 0", which
                ; is true of the stock's two MENU entries and not of its three
                ; REASONS: sequence_mode_init ($5380) reads the reason at
                ; $0009,s and only 0 seeds - 1 recalls, 2 skips. Seeding on
                ; every entry is what the harness caught as seed 47.
                lda     #$01
                sta     >tone_dtmf_mode
                tst     ,s                      ; A RECALL OR A KEEP-STATE
                bne     dtmf_sequence_open_seeded ; ENTRY NEVER SEEDS, AND
                lbsr    tone_defaults           ; REASON 0 ALWAYS DOES - see
                                                ; tone_sequence_open
dtmf_sequence_open_seeded
                clr     >tone_manual_sel        ; and not the Manual field
                clr     >tone_field             ; what the mode opens on
                clr     >tone_edit
                tst     ,s                      ; the reason
                bne     dtmf_sequence_open_record
                clr     >tone_page              ; the title record
                clr     >active_record          ; $268E, which a save carries

                ; AND THE CURSOR GOES BACK TO STEP 0, with the window on it.
                ; seq_data_init ($79FE) is called from sequence_mode_init at
                ; $5535 and takes the entry reason; both menu entries pass 0,
                ; and on 0 it writes $3D0D = 0 at $7A46 and then, at $7A51,
                ; copies $3D0D into the window origin $3D39. So the screen
                ; opens on the first step however far the last visit walked -
                ; which is also what makes the pair below deterministic.
                ldd     #$0000
                std     >tone_cursor            ; $7A46
                std     >tone_window            ; $7A51
                bra     dtmf_sequence_open_cursor

                ; ON A RECALL OR A KEEP-STATE ENTRY THE RECORD COMES BACK AND
                ; THE CURSOR STAYS - l5473 and $7A51, bounded as
                ; tone_sequence_open_record bounds it.
dtmf_sequence_open_record
                lda     >active_record
                cmpa    #TONE_PAGES
                blo     dtmf_sequence_open_record_on
                clra                            ; past the last: the title
dtmf_sequence_open_record_on
                sta     >tone_page
                sta     >active_record
                ldd     >tone_cursor            ; $7A51: the window on the
                std     >tone_window            ; cursor that is kept
dtmf_sequence_open_cursor

                ; AND THE PAIR THE FIRST STEP NAMES GOES ON THE CHIP.
                ; $555F-$5587: after enter_menu_page ($4689), sequence_mode_init
                ; tests $3C03 once more and, only when it says DTMF, reads the
                ; step under the cursor with tone_at_cursor ($6D66) and sounds
                ; it with output_tone ($6A95)(tone, $3C80). In DTMF mode
                ; output_tone stores the nibble in $3D27 and calls
                ; dtmf_program_digit ($441E), so entering the mode leaves BOTH
                ; generators carrying the first step's digit - 1336 Hz in
                ; register $08 and 941 Hz in $0A for the '0' that step 0 names.
                ;
                ; tone_sound_at_cursor is tone_at_cursor and output_tone
                ; together, and it takes the dialled branch off tone_dtmf_mode
                ; exactly as $6AA6 takes it off $3C03. It goes here rather than
                ; where $555F sits because this firmware paints the screen from
                ; tone_show at the end; the chip state is the same either way.
                ;
                ; Measured against the stock, 2026-09-13: the instrument came
                ; out of this entry at ((13360, 939, 0), (1000000, 0, 0),
                ; (9410, 939, 0), (10000, 0, 0)) and this firmware at four
                ; silent channels with the 1 kHz default on three of them.
                lbsr    tone_sound_at_cursor

                ; AND NOTHING IS ARMED ON THE WAY IN, as tone_sequence_open's
                ; own note sets out: the instrument arms a field from a FIELD
                ; KEY and from nowhere else, and this mode opens on its title
                ; record, which has no fields. Driven on both, 2026-09-13,
                ; straight after DTMF Sequence opens: the stock's $23A8 reads
                ; 00 and this firmware's entry_armed read 01, so '0', '7' and
                ; '.' each painted themselves over '** DTMF Sequence Mode **'
                ; where the instrument ignored all three.
                lbsr    tone_entry_none         ; $B394's CLR >$23A8

                ; REGISTER $1B IS NOT TOUCHED HERE. enter_dtmf_sequence_mode
                ; ($7A81) is menu_show and sequence_mode_init and nothing
                ; else - $7A81-$7AA6, checked directly in
                ; firmware/src-generated/a2u13_page1.s, and it does NOT end
                ; with dds_mode_param_set ($E69C) the way its Tone Sequence
                ; twin does. See tone_sequence_open's own note: an earlier
                ; version of this port assumed the two entries ended alike
                ; and put the same call here, which forced register $1B to
                ; zero on a DTMF entry the instrument never touches it on -
                ; measured through the differential harness as stock $04
                ; against this firmware's $00 after a Hop Ram OFF switch
                ; survived a DTMF Sequence entry on the stock and did not
                ; here.
                leas    1,s                     ; the reason off
                lbra    tone_show
; ---------------------------------------------------------------------------
; dtmf_key - the DTMF Sequence screen's keys
;
;   entry: B = the key code
;   uses:  A, B, X, Y, U
;
; A digit SENDS that digit as a DTMF pair, immediately, and the pair stops on
; its own after the On Time and the stock's two hundred counts of gap - which
; is what "for as long as the key would have been held on a telephone" has to
; mean on an instrument with no key to hold. That is what this screen is for
; - an engineer checking a receiver wants to press 5 and hear 5 - and it is
; why the digits do not go into an entry buffer here unless the On Time field
; has been selected.
;
; f2 selects the On Time field, as the stock's ' On Time' softkey does on its
; DTMF screen at $41E3, whose record gives that label selector $02. While it
; is selected the digits type into it and ENTER commits; ENTER with nothing
; typed closes it with the value standing, so the digits dial again. That
; closing is this screen's choice - the stock's field stays selected until
; another softkey - and it is here because this screen has no other key to
; leave the field with.
;
; ENTER with no field selected silences the output. It is the panic key on
; this screen, and it works whether or not anything is being sent.
; ---------------------------------------------------------------------------
dtmf_key
                ; A BUS FIELD SELECT IS THE KEY'S OWN MESSAGE - see tone_key,
                ; which carries the stock addresses and the driven evidence.
                cmpb    #RMT_RQ+$23             ; the bus's commit, as on the
                lbeq    tone_bus_ampl_commit     ; tone screen
                cmpb    #RMT_RQ+$36             ; QRE: the same $3A arm [53]
                lbeq    tone_key_wrong_mode
                cmpb    #RMT_RQ+$21             ; $21: key_save_register, the
                bne     dtmf_rq_not_save        ; tone screen's arm [32] - the
                                                ; entry goes and the Save
                lbsr    tone_entry_none         ; prompt opens
                clr     >dtmf_field
                lbra    ABI_save_prompt_open
dtmf_rq_not_save
                cmpb    #KEY_ABANDON            ; $3C: the same arm [59] as the
                bne     dtmf_rq_not_abandon     ; tone screen's - one table
                lbsr    tone_entry_none         ; serves both
                clr     >dtmf_field
                rts
dtmf_rq_not_abandon
                cmpb    #RMT_RQ+$19
                blo     dtmf_rq_key_done
                cmpb    #RMT_RQ+$1D
                bhi     dtmf_rq_key_done
                subb    #RMT_RQ+$19
                pshs    x
                ldx     #tone_rq_keys
                ldb     b,x
                puls    x
dtmf_rq_key_done
                cmpb    #KEY_ENTER
                bne     dtmf_key_f2
                ; ENTER MEANS TWO THINGS HERE, and the field open is the one
                ; that decides which. With the On Time open there are digits to
                ; terminate, and $B070 returns zero for class 5 - the
                ; instrument beeps at $B5D0 and the operator reaches for Hz or
                ; kHz. With no field open nothing is being terminated and ENTER
                ; silences the dial, which is this screen's own action.
                ;
                ; The test of dtmf_field already came first, which is what the
                ; tone screen had to be taught: the class question only arises
                ; once there is an entry to end.
                tst     >dtmf_field
                beq     dtmf_key_enter_silence
                tst     >entry_active           ; A FIELD OPEN IS NOT THE SAME
                lbne    dtmf_key_ignore         ; AS DIGITS TYPED. Only a typed
                lbra    dtmf_ontime_commit      ; entry is a terminator
                                                ; question; ENTER on an empty
                                                ; field still closes it, which
                                                ; is what dtmf_ontime_commit
                                                ; does at its entry_active test.
dtmf_key_enter_silence
                lbsr    dtmf_silence
                lbra    dtmf_show
dtmf_key_f2
                cmpb    #KEY_F2
                bne     dtmf_key_f4
                lbra    dtmf_ontime_begin
dtmf_key_f4
                ; INTO THE SEQUENCE - THE SAME SEQUENCE THE TONE SCREEN EDITS.
                ; On the instrument these are one mode with two menu records
                ; over one set of cells: enter_dtmf_sequence_mode ($7A81) and
                ; tone_sequence_mode_enter ($55C5) differ only in the record
                ; they install and in $3C03, and the cursor $3D0D, Seq End
                ; $3D0F and the 250-nibble playlist at $3C90 are shared. This
                ; firmware keeps that: tone_dtmf_mode is $3C03, it was set by
                ; dtmf_sequence_open, and the screen this hands over to reads
                ; every nibble as a dialled digit because of it.
                ;
                ; MANUAL DIAL STAYS ITS OWN MODE, which is what the instrument
                ; does - softkey_manual_dial ($492C) is a key of the DTMF
                ; record, live only while $3C03 is set, and it is not the
                ; sequence. So this hands over rather than replacing: the dial
                ; screen is still what the mode opens on.
                cmpb    #KEY_F4
                bne     dtmf_key_rq_wsq
                lbsr    dtmf_silence            ; nothing left sounding across
                                                ; the handover
                ldx     #tone_key
                lbsr    ABI_screen_install
                clr     >tone_page              ; on its first softkey page,
                clr     >active_record          ; ($268E with it)
                lbsr    tone_entry_none         ; which is the title record and
                lbra    tone_show               ; has no field to arm - see the
                                                ; note in tone_sequence_open
dtmf_key_rq_wsq
                ; THE BUS. WSQ ($2C) IS A BULK LOAD OF THE PLAYLIST, NOT A
                ; DIAL. Arm [43] of the page-1 message table $508C is
                ; streamed_entry_key ($5048), and $508C is the table of
                ; sequence_mode_message_handler ($4C01), which serves the
                ; WHOLE mode - this screen included. The instrument therefore
                ; answers WSQ here by installing gpib_sequence_char_in ($7870)
                ; and writing every character into the shared sequence with
                ; seq_put_nibble ($452D). It sounds nothing while it does:
                ; $7952's echo leg wants $3C8F = 3 and $3C82 set, and
                ; softkey_manual_dial ($492C) leaves $3C8F at 1 and never
                ; writes $3C82 at all.
                ;
                ; THIS ARM USED TO DIAL EVERY CHARACTER. It set rmt_stream and
                ; remote.s handed each character back as RMT_RQ + $60 + index,
                ; which the arm that stood below this one turned into
                ; dtmf_send - so 'WSQ 5551234;' put seven live DTMF bursts on
                ; the output socket, into whatever was connected to it, and
                ; stored nothing. Measured against the stock, 2026-09-13, on
                ; this screen: the instrument stored 5 5 5 1 2 3 4 into the
                ; playlist and made THREE DDS writes, all of them the screen's
                ; own entry; this firmware stored nothing and made 770.
                ; page1_stream_open and page1_bus_stream in page1_tone.s are
                ; the stock's own $79C3 and $7870, and both screens of this
                ; mode reach the playlist through them.
                cmpb    #RMT_RQ+$2C
                bne     dtmf_key_rq_refresh
                lbsr    page1_stream_open       ; $79C3
                lda     #$03                    ; owner 3 = this screen, the
                sta     >rmt_seq_owner          ; one that stores in silence
                lbra    dtmf_show
dtmf_key_rq_refresh
                cmpb    #KEY_REFRESH
                bne     dtmf_key_backspace
                lbra    dtmf_show
dtmf_key_backspace
                cmpb    #KEY_BACKSPACE
                bne     dtmf_key_units
                ; THE LAST DIGIT OUT OF THE ON TIME. The field softkey_on_time
                ; ($4842) opens is entry_field_on_off_time, kind 3 (LDD #$0003
                ; / STD 7,s into the l4667 tail), so entry_backspace ($B2CD,
                ; reached at $B4B9 for key $1F) steps the head $23A4 back and
                ; blanks the vacated cell ($B2E9-$B31F), and the handler
                ; repaints the buffer ($B4D0-$B501) once a key has been
                ; accepted ($B4C4). With nothing to take out (the carry) the
                ; glass is left as it is, which is what $B4CD leaves. WITH NO
                ; FIELD OPEN - dtmf_field zero, the digits dialling tones -
                ; the key is refused exactly as it was before this arm
                ; existed; what the stock's dial mode does with $1F is not
                ; established here, and nothing about it is claimed.
                tst     >dtmf_field
                beq     dtmf_key_ignore
                lbsr    ABI_entry_backspace     ; $B2E9-$B31F, slot 73
                bcs     dtmf_key_done
                lbra    dtmf_show               ; $B4D0-$B501: repainted as
                                                ; dtmf_key_type repaints
                                                ; after a digit
dtmf_key_done
                rts
dtmf_key_units
                ; THE ON TIME IS CLASS 5, whose arm is $B169: Hz stores unit
                ; $0A (ms) and kHz unit 9 (s). deg has no arm there, so it
                ; falls past into the digit handler and is refused - which is
                ; $B0C1 returning zero.
                ;
                ; AT THE END OF THE DISPATCH CHAIN, falling through to the
                ; digits. Put in the middle it would orphan every arm below it,
                ; which is what test_reachable.py caught on the tone screen.
                cmpb    #KEY_HZ
                bne     dtmf_key_unit_khz
                ldb     #UNIT_MILLISEC
                bra     dtmf_key_unit_go
dtmf_key_unit_khz
                cmpb    #KEY_KHZ
                bne     dtmf_key_digit
                ldb     #UNIT_SECOND
dtmf_key_unit_go
                tst     >dtmf_field             ; no field open, nothing to end
                beq     dtmf_key_ignore
                stb     >tone_entry_unit
                lbra    dtmf_ontime_commit

dtmf_key_digit
                lbsr    ABI_key_digit           ; carry clear and B = 0 to 9
                bcs     dtmf_key_ignore
                tst     >dtmf_field
                bne     dtmf_key_type
                ldx     #dtmf_digit_index       ; THE DIGIT'S VALUE IS NOT ITS
                ldb     b,x                     ; INDEX - see the table above
                stb     >dtmf_position          ; the screen shows which
                lbsr    dtmf_send
                lbra    dtmf_show
dtmf_key_type
                lbsr    ABI_entry_digit         ; into the On Time field
                lda     #$01                    ; something has been typed:
                sta     >entry_active           ; ENTER commits it
                lbra    dtmf_show
dtmf_key_ignore
                ; ONE HANDLER SERVES BOTH PAGE-1 RECORDS, so this screen
                ; answers what the tone screen answers. sequence_mode_init
                ; ($5629) installs $220F = sequence_mode_message_handler
                ; ($4C01) for BOTH tone_sequence_mode_enter ($55C5) and
                ; enter_dtmf_sequence_mode ($7A81), and that handler dispatches
                ; through the one table d508c - so RUNC, RUNS, RUNM, STOP,
                ; STON, STOF, SEQP and SEQE are answered on the DTMF record by
                ; the same arms, which is why page1_tone.s's own note records
                ; them as driven 2026-09-14 IN DTMF SEQUENCE.
                ;
                ; This screen already delegates to the tone module by name -
                ; tone_bus_ampl_commit, tone_key_wrong_mode, tone_entry_none
                ; and tone_rq_keys - and the sequence those arms drive is one
                ; sequence: enter_dtmf_sequence_mode and
                ; tone_sequence_mode_enter differ only in the record they
                ; install and in $3C03, with the cursor $3D0D, Seq End $3D0F
                ; and the 250-nibble playlist at $3C90 shared. So the bus
                ; requests go to the same chain rather than to a copy of it.
                cmpb    #RMT_RQ                 ; a bus request, not a key
                blo     dtmf_key_ignore_key
                lbra    tone_rq_seq_arms        ; the shared page-1 sequence
                                                ; arms, and tone_key_wrong_mode's
                                                ; $3A for every code they do not
                                                ; claim. NOT tone_rq_aph: that
                                                ; is mid-chain and walks the
                                                ; hop selects on the way in.
dtmf_key_ignore_key
                lbra    ABI_key_refuse          ; a key this screen cannot
                                                ; use is REFUSED, not
                                                ; ignored; see key_refuse

; ---------------------------------------------------------------------------
; dtmf_ontime_begin - select the On Time field
;
;   uses:  A, B, X
;
; The stock's softkey_on_time ($4842): cancel any entry in progress, point
; the time pointers at word 0 of the tone's $3C10 record and open the
; numeric field. Here the field is three decimal digits of milliseconds.
; ---------------------------------------------------------------------------
dtmf_ontime_begin
                lda     #$01
                sta     >dtmf_field
                clr     >entry_active
                clr     >tone_entry_unit
                lda     #ENTRY_DECIMAL
                ldb     #DTMF_ON_DIGITS
                lbsr    ABI_entry_begin
                lbra    dtmf_show

; ---------------------------------------------------------------------------
; dtmf_ontime_commit - ENTER on the On Time field
;
;   uses:  A, B, X, Y, U
;
; The stock's apply_time_entry ($638F) parses the typed number into the
; selected time word and validate_gate_time ($6033) then refuses anything
; below $0064 counts in DTMF mode, restoring the previous value and raising
; error $32. The field here is typed in milliseconds and stored as counts -
; a hundred to the millisecond - so the floor is one millisecond, which is
; the stock's $0064, and the ceiling is 655, the most the 16-bit word holds.
; A refused value leaves the old one standing and re-opens the field, as the
; digital screen's period field does.
; ---------------------------------------------------------------------------
dtmf_ontime_commit
                tst     >entry_active
                beq     dtmf_ontime_close       ; nothing typed: the value
                                                ; stands and the field closes
                lbsr    ABI_entry_value         ; carry set past 24 bits
                bcs     dtmf_ontime_refuse
                ; THE DIGITS ARE IN THE UNIT THE KEY NAMED, and applied here -
                ; before the ceiling below, which is written in milliseconds,
                ; and before the multiply by TONE_MS_COUNTS that turns those
                ; into counts. Both are left exactly as they were.
                ;
                ; The kHz key is seconds, and on this field every whole second
                ; is past the 655 ms ceiling - so it always refuses. That is
                ; the stock's arithmetic too, not a limitation introduced here.
                lbsr    tone_entry_scale
                bcs     dtmf_ontime_refuse
                tst     >entry_result           ; three digits never reach
                bne     dtmf_ontime_refuse      ; the top byte; the test is
                                                ; the range check's shape
                ldd     >entry_result+1
                beq     dtmf_ontime_refuse      ; zero is below the floor
                cmpd    #DTMF_ON_MAX_MS
                bhi     dtmf_ontime_refuse
                ldx     #TONE_MS_COUNTS
                lbsr    ABI_mul16               ; math_product = ms x 100
                ldd     >math_product+2         ; the low sixteen bits: at
                pshs    a,b                     ; most 65500, into the tone the
                ldb     >tone_number            ; screen is showing - the
                lbsr    tone_times_address      ; shared $3C10 pair, not a cell
                puls    a,b                     ; of this mode's own
                std     ,x
dtmf_ontime_close
                clr     >dtmf_field
                clr     >entry_active
                clr     >tone_entry_unit
                lbra    dtmf_show
dtmf_ontime_refuse
                ldb     #ERR_TIME_RANGE         ; the previous value stands,
                lbsr    ABI_error_raise         ; as it does in the stock
                lbra    dtmf_ontime_begin       ; and the field re-opens
