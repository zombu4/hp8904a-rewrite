; ===========================================================================
; frequency.s - the channel frequency: its representation, its limits, and
;               how it reaches the synthesis chip
;
; THIS IS THE SIMPLEST PART OF THE INSTRUMENT AND THE ONE MOST LIKELY TO BE
; OVER-ENGINEERED, so the central fact is stated first:
;
;   the number the operator keys, in units of 0.1 Hz, IS the tuning word.
;
; There is no multiply, no divide, no reference-clock constant and no scaling
; anywhere on the path from the keypad to the chip. That is established, not
; assumed, and it was established three independent ways:
;
;   1. The stock commit path (a2u13_page0 $647B) copies the entered 24-bit
;      value to the channel record with copy3 ($D37D) - a plain three-byte
;      move - and hands the same pointer to write_channel_reg_08 ($E2C1).
;      Nothing between them touches the value.
;
;   2. The stock DTMF frequency table (a2u13_page1 $43BC) is written by hand
;      and holds 697 Hz as $01,$2C,$34. Assembled as three 6-bit fields that
;      is 6964, and 6964 x 0.1 Hz = 696.4 Hz - the DTMF specification's 697 Hz
;      to the resolution the format allows. The other seven rows are exact:
;      770.0, 852.0, 941.0, 1209.0, 1336.0, 1477.0 and 1633.0 Hz.
;
;   3. The stock ceiling constant at $EA55 is $5B8D80 = 6,000,000, and
;      6,000,000 x 0.1 Hz = 600 kHz, which is the 8904A's published top
;      frequency. The front panel prints it as 600.0000 kHz - seven digits,
;      0.1 Hz resolution.
;
; So the reference clock does not appear here because the firmware never
; needs it. That is worth saying plainly: an earlier version of this work
; called the reference clock a prerequisite for the frequency path and it is
; not one. The chip's own accumulator does the scaling in hardware.
;
; THE HARDWARE FORMAT. The 24-bit word goes to the chip as four 6-bit fields
; through a staging port, most significant first, and is then latched into
; one channel by a fifth write:
;
;   select $03   data v[23:18]      buffer latch 3
;   select $02   data v[17:12]      buffer latch 2
;   select $01   data v[11:6]       buffer latch 1
;   select $00   data v[5:0]        buffer latch 0
;   select $08+n data (ignored)     latch buffer into channel n's frequency
;
; Each write is one 16-bit STD to $0200: the high byte selects, the low byte
; carries the data. Five stores, ten bytes.
; ===========================================================================

; --- the limits ------------------------------------------------------------
; Both are 24-bit counts of 0.1 Hz, and both are read straight off the stock
; firmware rather than converted from a data-sheet figure.
;
;   $5B8D80 = 6,000,000 = 600.0000 kHz    the instrument's top frequency
;   $07A120 =   500,000 =  50.0000 kHz    for the waveforms with hard edges
;
; There is NO lower limit. check_freq_limit (a2u13_page0 $63D2) tests only
; the ceiling, and zero is a legitimate setting - it is how a channel is
; parked without switching its output off.
FREQ_MAX_HI     equ     $5B             ; 6,000,000 = 600 kHz
FREQ_MAX_MID    equ     $8D
FREQ_MAX_LO     equ     $80
FREQ_MAX_LOW16  equ     $8D80           ; the middle and low bytes together

; FREQ_EDGED_HI, _MID, _LO and _LOW16 ARE IN common/formats.inc, beside the
; other limits: the channel screen is on A2U13 page 0 and its waveform
; validation needs the same ceiling, and a second copy in the other image is
; how the two would come to disagree about where 50 kHz is.

; The four 6-bit fields, the per-channel latches and the register ids are
; in common/formats.inc, read out of the chip's own descriptor table. They
; were declared here as well, which lwasm refused.

; ---------------------------------------------------------------------------
; freq_ceiling - the highest frequency this channel may be set to
;
;   entry: X = the channel record
;   exit:  X unchanged, freq_limit holds the 24-bit ceiling
;   uses:  A, B
;
; Two ceilings, and which one applies depends on what the channel is doing:
;
;   Ramp, Triangle and Square are built from hard edges, so their harmonic
;   content extends far above the fundamental. Above 50 kHz the harmonics
;   land outside the output filter and what comes out of the socket is no
;   longer the waveform on the screen. Sine, dc and Noise have no such
;   problem and take the full 600 kHz.
;
;   Pulse modulation - destination code 11 - takes the lower ceiling
;   whatever the waveform is, for the same reason: a pulse-modulated carrier
;   occupies bandwidth well beyond its own frequency.
;
; The rule is the stock firmware's, tested there against waveform codes 2, 3
; and 6 and destination code $0B. Those are exactly Ramp, Triangle, Square
; and Plse in the shared table in labels.s, which is what makes the rule
; legible rather than four arbitrary numbers.
; ---------------------------------------------------------------------------
freq_ceiling
                ldb     CHAN_DEST,x
                cmpb    #LBL_PULSE
                beq     freq_ceiling_low

                ldb     CHAN_WAVE,x
                cmpb    #LBL_RAMP
                beq     freq_ceiling_low
                cmpb    #LBL_TRIANGLE
                beq     freq_ceiling_low
                cmpb    #LBL_SQUARE
                beq     freq_ceiling_low

                lda     #FREQ_MAX_HI
                sta     >freq_limit
                ldd     #FREQ_MAX_LOW16
                std     >freq_limit+1
                rts
freq_ceiling_low
                lda     #FREQ_EDGED_HI
                sta     >freq_limit
                ldd     #FREQ_EDGED_LOW16
                std     >freq_limit+1
                rts

; ---------------------------------------------------------------------------
; freq_in_range - is a 24-bit frequency within this channel's ceiling?
;
;   entry: X = the channel record, U = the 24-bit value to test
;   exit:  Z set if it is acceptable, Z clear if it is too high
;   uses:  A, B
;
; An unsigned 24-bit comparison, done a byte at a time from the top. The
; early exits matter: once a higher byte differs the lower ones cannot change
; the answer, and continuing to compare them is how a correct routine becomes
; a wrong one when somebody later adds a case.
;
; Note what is NOT here: a lower bound. Zero is a valid frequency and the
; stock firmware accepts it.
; ---------------------------------------------------------------------------
freq_in_range
                pshs    x
                lbsr    freq_ceiling
                lda     ,u                      ; the high bytes
                cmpa    >freq_limit
                blo     freq_in_range_yes       ; strictly lower: accepted
                bhi     freq_in_range_no        ; strictly higher: refused
                lda     1,u                     ; equal so far: the middle
                cmpa    >freq_limit+1
                blo     freq_in_range_yes
                bhi     freq_in_range_no
                lda     2,u                     ; equal again: the low byte
                cmpa    >freq_limit+2
                bhi     freq_in_range_no        ; equal to the ceiling is
freq_in_range_yes                               ; accepted, above it is not
                puls    x
                orcc    #CC_ZERO                ; Z set: in range
                rts
freq_in_range_no
                puls    x
                andcc   #~CC_ZERO               ; Z clear: out of range
                rts

; ---------------------------------------------------------------------------
; freq_program - write a 24-bit frequency to one channel's DDS registers
;
;   entry: U = the 24-bit value, big-endian; B = the channel, 0 to 3
;   exit:  the chip's frequency register for that channel holds the value
;   uses:  A, B
;
; THE CONTRACT SAID "A, B, X, Y" AND THE BODY TOUCHES NEITHER X NOR Y. It is
; two instructions falling into dds_write_wide, and scanning that routine for
; every ldx/leax/abx, ldy/leay and ldu/leau finds none of them.
;
; Over-declaring is the safe direction - a caller saves more than it needs -
; so this was not producing wrong code. It was producing wrong REASONING:
; dtmf_send holds the high tone in Y across a call to this routine, and
; against a header claiming Y is destroyed that reads as a live bug. The
; header was the thing that was wrong.
;
; The five writes described in this file's header. Interrupts are masked
; across all five, for one specific reason: the first four writes fill a
; single set of staging latches that every channel shares. An interrupt
; handler that programmed a different channel in the middle would leave this
; channel latching a word half its own and half the other's - and nothing
; downstream could detect it, because the chip has no read path.
;
; The mask is therefore not defensive habit. It is the only thing that makes
; the staging latches safe to share.
;
; The field extraction is plain shifting and masking with no table:
;
;   field 3 = byte0 >> 2
;   field 2 = ((byte0 & $03) << 4) | (byte1 >> 4)
;   field 1 = ((byte1 & $0F) << 2) | (byte2 >> 6)
;   field 0 = byte2 & $3F
;
; Each is masked to six bits. The stock firmware reaches the same four values
; by shifting a 16-bit register pair, which zero-fills from the top and so
; masks field 2 implicitly rather than with an AND - the result is identical,
; and it is worth saying because reading that code quickly suggests two stray
; bits survive into field 2. They do not: for the DTMF row stored as
; $01,$2C,$34 the extraction here gives $01, $2C, $34 back, which is what the
; hand-built table holds.
; ---------------------------------------------------------------------------
freq_program
                andb    #$03                    ; 0 to 3, so a wild channel
                addb    #DDS_FREQ_BASE          ; number cannot select some
                                                ; other register entirely
                                                ; falls through

; ---------------------------------------------------------------------------
; dds_write_wide - write a 24-bit value to any width-4 DDS register
;
;   entry: B = the register id, U = a pointer to three bytes, high first
;   exit:  nothing; the register holds the value
;   uses:  A, B
;
; This was the body of freq_program, which computed its register id from a
; channel number and could therefore only ever reach $08-$0B. Register $27 is
; also width 4 - the descriptor table gives it byte $F6, and ($F6 >> 6) + 1 is
; 4 - and the power-on reset has to write it three bytes wide. There was no
; routine that could: dds_write refuses width 4 because a 24-bit value does
; not fit its 16-bit argument, and freq_program would have latched into
; $08 + ($27 & $03), which is channel 3's frequency.
;
; So the staging is general and the channel arithmetic is the caller's, which
; is what it always should have been. Extracted rather than copied: a second
; copy of the four-field split is the shape that has already gone wrong three
; times in this repository, each time fixed in one place and left in the next.
;
; INTERRUPTS ARE MASKED ACROSS THE WHOLE SEQUENCE. The four buffer latches are
; shared by every register on the chip, so anything that staged a value
; between the first field and the latch would be committed into this register
; instead of its own.
; ---------------------------------------------------------------------------
dds_write_wide
                inc     >dds_lock               ; see nmi_handler: the
                                                ; sequence player defers a
                                                ; tick rather than writing
                                                ; into the middle of this
                pshs    b                       ; the register id. NOT "pshs
                DISABLE_INTERRUPTS              ; cc,b": DISABLE_INTERRUPTS
                                                ; pushes CC itself, so saving
                                                ; it here too left one byte on
                                                ; the stack and the RTS
                                                ; returned into I/O space.

                ; --- field 3: the top six bits ------------------------------
                ldb     ,u                      ; byte 0 = v[23:16]
                lsrb
                lsrb                            ; B = v[23:18]
                lda     #DDS_BUFLAT3
                std     >dds_prog

                ; --- field 2 ------------------------------------------------
                ldb     ,u
                andb    #$03                    ; the two bits byte 0 keeps
                lslb
                lslb
                lslb
                lslb                            ; B = v[17:16] << 4
                lda     1,u                     ; byte 1 = v[15:8]
                lsra
                lsra
                lsra
                lsra                            ; A = v[15:12]
                pshs    a
                addb    ,s+
                lda     #DDS_BUFLAT2
                std     >dds_prog

                ; --- field 1 ------------------------------------------------
                ldb     1,u
                andb    #$0F                    ; B = v[11:8]
                lslb
                lslb                            ; B = v[11:8] << 2
                lda     2,u                     ; byte 2 = v[7:0]
                lsra
                lsra
                lsra
                lsra
                lsra
                lsra                            ; A = v[7:6]
                pshs    a
                addb    ,s+
                lda     #DDS_BUFLAT1
                std     >dds_prog

                ; --- field 0 ------------------------------------------------
                ldb     2,u
                andb    #$3F                    ; B = v[5:0]
                lda     #DDS_BUFLAT0
                std     >dds_prog

                ; --- latch the staged word into the register ---------------
                ldb     1,s                     ; the id, saved on entry. The
                tfr     b,a                     ; range check belongs to the
                clrb                            ; caller: freq_program masks a
                std     >dds_prog                ; channel to 0-3, and the
                                                ; reset table names its ids
                                                ; literally. The data byte is
                                                ; ignored on a latch.

                RESTORE_INTERRUPTS              ; the CC the macro pushed
                puls    b
                dec     >dds_lock
                rts

; ---------------------------------------------------------------------------
; freq_as_sent - the tuning word register $08+channel is given
;
;   entry: B = the channel, 0 to 3; X = a three-byte buffer
;   exit:  the buffer holds the word, high byte first; B and X as they came
;   uses:  A, U
;
; THE WORD ON THE CHIP IS NOT ALWAYS THE RECORD'S FREQUENCY. Both stock
; writers of a channel's frequency register choose between two routines on
; is_modulation_destination ($77D9) of record+$21: commit_channel_frequency
; ($647B) at $64DE-$650C and set_channel_destination ($78BF) at $7EE7-$7F41.
; A socket or Off takes write_channel_reg_08 ($E2C1), the value as it is; a
; modulation code takes copy_or_negate_to_channel_reg_08 ($E319), whose
; $E325 LDD >$23C1 / ANDB #$08 test keeps the value when the flag is set and
; otherwise, at $E347-$E358, computes zero minus it through sub24 ($D3C6) -
; the 24-bit two's complement. That flag is special function 3, "Reverse
; modulating waveforms", SPECIAL_REVERSE_MOD here, and program_channel_phase
; ($6635) reads the same bit at $6666 before it negates the phase.
;
; Executed on the stock over the bus, 2026-09-02: 'DEB FM;' on a channel at
; 1 kHz writes $033F $023D $0123 $0030 $0900 and leaves the register's shadow
; $2495 holding $FFD8F0 - 10000 negated - while the record at $24F5+35 still
; holds $002710; 'DEB OC2;' afterwards writes $0300 $0202 $011C $0010 $0900,
; the value as it is.
;
; ONE ROUTINE, because two things need the same answer: freq_program_routed
; sends it, and phase_offset_compute (phase.s) multiplies it - $E8A7 reads
; the register's shadow, so the offset a modulator carries is derived from
; the negated word, not from the record.
;
; The subtraction is 0 - v across all three bytes with the borrow carried:
; CLRA / CLRB / SUBD 1,u leaves the low sixteen bits and the borrow in C, STD
; does not touch C, and LDA #0 / SBCA ,u finishes the high byte. For $002710
; that is $D8F0 with a borrow, then $00 - $00 - 1 = $FF: $FFD8F0.
; ---------------------------------------------------------------------------
freq_as_sent
                pshs    b,x
                andb    #$03
                lda     #CHAN_RECORD
                mul
                ldu     #channel_records
                leau    d,u                     ; U = the record, the
                                                ; frequency at offset zero
                ldb     ,s
                andb    #$03
                ldx     #routed_dest
                abx
                ldb     ,x                      ; B = record+$21, the code
                ldx     1,s                     ; X = the buffer
                lbsr    label_is_modulation     ; carry set for 7 to $0B
                bcc     freq_as_sent_copy
                lda     >special_flags          ; $E325: bit 3 set keeps the
                bita    #SPECIAL_REVERSE_MOD    ; value
                bne     freq_as_sent_copy
                clra                            ; $E347-$E358: zero minus
                clrb                            ; the value, low two bytes
                subd    1,u
                std     1,x
                lda     #$00                    ; LDA leaves the borrow in C
                sbca    ,u
                sta     ,x
                puls    b,x
                rts
freq_as_sent_copy
                ldd     ,u                      ; $E334-$E342's copy3, or
                std     ,x                      ; $E2C1's pointer straight
                lda     2,u                     ; through
                sta     2,x
                puls    b,x
                rts

; ---------------------------------------------------------------------------
; freq_program_routed - send a channel's frequency as its destination wants it
;
;   entry: B = the channel, 0 to 3; the record holds the frequency
;   exit:  register $08+channel holds the word freq_as_sent describes
;   uses:  A, X, U
;
; $7EE7-$7F02 and $7F31-$7F41 of set_channel_destination, $64DE-$650C of
; commit_channel_frequency: the choice between $E319 and $E2C1, then the
; five staged writes of freq_program. The three bytes live on the stack for
; the length of the call; freq_program reads them through U and pushes
; below them.
; ---------------------------------------------------------------------------
freq_program_routed
                pshs    b
                leas    -3,s                    ; 0,s..2,s the word; 3,s B
                leax    ,s
                ldb     3,s
                lbsr    freq_as_sent
                leau    ,s
                ldb     3,s
                lbsr    freq_program
                leas    3,s
                puls    b
                rts

; ---------------------------------------------------------------------------
; freq_set - validate a frequency, store it in the record, and program it
;
;   entry: X = the channel record, U = the 24-bit value, B = the channel
;   exit:  carry clear and the channel is running at that frequency;
;          carry set and NOTHING has changed, with last_error set
;   uses:  A, B, Y
;
; The order is deliberate: check first, then store, then program. A routine
; that stored before checking would leave the record holding a value the
; instrument is not producing, and the screen would then show a frequency the
; socket does not have - which is the worst failure this instrument can have
; short of losing calibration, because it is invisible.
; ---------------------------------------------------------------------------
freq_set
                pshs    b,x,u
                lbsr    freq_in_range
                bne     freq_set_refused

                ; The frequency is at offset zero of the record - see the
                ; layout in scratch.inc, where that is deliberate so the DDS
                ; write path can take a record pointer directly. Written as
                ; ",x" rather than "CHAN_FREQ,x" because lwasm collapses a
                ; zero offset to the no-offset postbyte $84 while this
                ; project's own assembler keeps the 5-bit form $00 - which it
                ; must, or the stock ROMs stop round-tripping byte for byte.
                ; Two correct encodings, one byte apart, and the two-assembler
                ; check found it. tests/test_zero_offset.py refuses a
                ; symbolic zero offset anywhere in the tree so the next one
                ; cannot get in.
                ldd     ,u                      ; copy the three bytes into
                std     ,x                      ; the record, high two first
                lda     2,u
                sta     CHAN_FREQ+2,x

                ; THE WORD GOES OUT AS THE STOCK SENDS IT. commit_channel_
                ; frequency ($647B) copies the entry over record+0 at $64D2
                ; and then, on is_modulation_destination ($77D9) of
                ; record+$21, calls copy_or_negate_to_channel_reg_08 ($E319)
                ; at $64E3 - the two's complement unless $23C1 bit 3 is set -
                ; or write_channel_reg_08 ($E2C1) at $64FF. freq_program_
                ; routed makes the same choice from routed_dest and
                ; special_flags. Executed on the stock over the bus,
                ; 2026-09-02: 'DEB FM; FRB 3 KZ;' writes $033F $0238 $012B
                ; $0010 $0900 - $FF8AD0, 30000 negated - where 'FRB 2 KZ;'
                ; on a socket writes $0300 $0204 $0138 $0020 $0900.
                ldb     ,s                      ; the channel: PSHS pushes U,
                                                ; then X, then B, so B is
                                                ; lowest at 0,s
                lbsr    freq_program_routed
                ; $6519-$653F: FOR A MODULATOR THE PHASE OFFSET FOLLOWS,
                ; because it is derived from the word just sent -
                ; scale_channel_value_by_6_or_7 ($E8A7) into
                ; set_channel_word_24cd ($E5BF), which re-sends the phase
                ; with it. $6519 LDB 3,S / LBEQ skips both for a socket. The
                ; same 'FRB 3 KZ;' continues $033F $0214 $1100 before its
                ; pulse; 'FRB 2 KZ;' has no phase word.
                ldb     ,s
                andb    #$03
                ldx     #routed_dest
                abx
                ldb     ,x                      ; record+$21, the routed code
                lbsr    label_is_modulation
                bcc     freq_set_pulse
                ldb     ,s
                lbsr    phase_offset_update
freq_set_pulse
                lbsr    dds_phase_reset         ; AND THE AUTOMATIC PHASE
                                                ; RESET, which special
                                                ; function 1 turns off:
                                                ; dispatch_ui_event runs
                                                ; dds_reg26_pulse_if_flag1_
                                                ; clear ($DEB6) at $5E13 once
                                                ; commit_entry_to_field has
                                                ; returned with $2215 = 1,
                                                ; the frequency field - after
                                                ; the phase word, which is
                                                ; why it comes last here. The
                                                ; preference existed and was
                                                ; read nowhere, and the pulse
                                                ; it vetoes was not
                                                ; implemented - so the setting
                                                ; changed nothing in either
                                                ; position. dds_phase_reset
                                                ; makes the test itself.
                puls    b,x,u
                andcc   #~CC_CARRY              ; carry clear: accepted
                rts
freq_set_refused
                lda     #ERR_FREQ_RANGE
                sta     >last_error
                puls    b,x,u
                orcc    #CC_CARRY               ; carry set: refused, and the
                rts                             ; record is untouched
