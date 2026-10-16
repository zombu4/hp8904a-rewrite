; ---------------------------------------------------------------------------
; hardware.inc - the HP 8904A's memory-mapped registers
;
; These addresses are fixed by the A2 Digital Assembly, not by software. They
; are the one part of this rewrite that cannot be chosen: the address decode
; is wired on the board, so a wrong value here does not produce wrong code, it
; produces a machine that writes to the wrong chip.
;
; Every entry is transcribed from firmware/symbols.py, which carries the
; evidence for each - the instruction that touches it, or the service
; manual's own map. test/native_map_selftest.py compares this file against
; that table entry for entry and fails if either side gains, loses or moves
; one, so the two cannot drift.
; ---------------------------------------------------------------------------


; supplied map: keypad rows 5:0, bit 6 external ref, bit 7 any-key
kbd_rows               equ     $0000

; decoded here: read at $F0A7 in the FIRQ body and masked with
; #$90 to test bits 7 and 4
int_latch              equ     $0100

; supplied map: DDS synthesis chip programming
dds_prog               equ     $0200

; the low half of the 16-bit DDS programming port. Almost every
; write is an STD or STX to $0200, covering both bytes at once,
; but page 1 writes this half alone three times - $435F, $4494 and
; $44C7, in seq_step_advance ($42B1) and halve_amplitude_221c
; ($4439) - each after a full STX to $0200 has set the register
; number. So the pair reads as register-then-data, and this is the
; data byte being updated on its own when only the value changes.
; Previously undeclared.
dds_prog_data          equ     $0201

; supplied map: HD44780 instruction register, bit 7 busy
lcd_instr              equ     $0300

; supplied map: HD44780 data register
lcd_data               equ     $0301

; supplied map: Intel P8291A
gpib_data              equ     $0400

; decoded here: read by the $FFCF helper at $FFD6
gpib_isr1              equ     $0401

; decoded here: read by the $FFCF helper at $FFD3
gpib_isr2              equ     $0402

; supplied map
gpib_ie2               equ     $0403

; supplied map
gpib_spoll             equ     $0404

; supplied map
gpib_admode            equ     $0405

; decoded here: read at $90D5, bit 7 mirrors the INT pin, BMI at
; $90D8 branches on it
gpib_adr0              equ     $0406

; supplied map
gpib_adr1              equ     $0407

; decoded here: read at $F0C8 in the FIRQ body
digital_in             equ     $0600

; a write-only strobe. Four references in the whole firmware, and
; the value written never matters - A2U12 uses CLR three times and
; the Memory Map Access screen writes a data byte. What it does is
; clearest in count_installed_channels ($B852), which works out
; how many output boards are fitted: for each channel 0-3 it calls
; port_latch_rmw(i, $80, $80) to set bit 7 of that channel's
; output latch, writes $0800, then tests the corresponding bit of
; int_latch. A channel whose bit comes back is installed and
; increments $23B2 - the installed channel count that errors $16
; and $68, 'Output selected does not exist', are checked against.
; The other two A2U12 uses, at $B675 and $B84C, each follow a loop
; of port_latch_rmw calls, so the reading is that writing here
; transfers or clears what those calls staged. The service screen
; lists it as element 5 beside 'Output 2' ($0D00), consistent with
; it belonging to the output-latch path. Previously undeclared -
; found by listing every I/O address an instruction references and
; comparing against this table, the same sweep that turned up
; $0201 and would have caught $0B00.
output_latch_strobe    equ     $0800

; THE SUPPLIED MAP IS INCOMPLETE HERE, and this is what the
; firmware shows instead. The map names three lamps. The stock's
; own "all lamps off" routine does LDA #$3F / STA >status_led, so
; bits 5:0 are SIX lamp lines and SET is OFF - active low, as the
; map says, but six of them and not three.
;
; Bits 6 and 7 are something else. They are set and cleared
; INDIVIDUALLY - ORB #$40, ORB #$80, ANDB #$7F, ANDB #$BF - which
; is flag behaviour rather than lamp behaviour, and one site writes
; LDA #$C0, which under the same active-low reading would turn all
; six lamps ON. What they do is NOT ESTABLISHED.
;
; Found by enumerating every value the five stock images write to
; this port, after the sequence timebase turned out to have been
; taken from a document rather than from the firmware.
;
; THIS FIRMWARE DOES WRITE IT, from modules/panel_leds.s and
; nowhere else - four stores, which is how the lamps are lit and
; put out. The line here used to read "this firmware never writes
; $0900 at all, so nothing here depends on it", which was true
; when the entry was corrected and stopped being true when the
; lamps were given a driver. Bits 6 and 7 are still NOT
; ESTABLISHED, and panel_leds.s leaves them alone.
status_led             equ     $0900

; supplied map: keypad column drive, bits 5:0
kbd_cols               equ     $0A00

; the hop output latch. Written from TWO places in the five
; images, not one - the claim here said one until ramrefs.py was
; run over all five: $431C on page 1, and $C704 in
; instrument_preset ($C6EA) in A2U12, which does CLR >hop_latch.
; CLR is a write, and the sibling entry $0800 already counts CLR
; as one. The page-1 site, inside seq_step_advance ($42B1), which
; runs from the two NMI bodies, does LDA >$3D27 (the current
; step's tone number) / ORA #$C0 / STA >$0B00, so the latch
; carries six bits of step data with the top two lines held
; asserted, and it changes in real time as the sequencer advances.
; The service diagnostics name this address independently: it is
; element 3 of the Memory Map Access screen, whose name string at
; $54EA is 'HOPLATCH'. Identified when an owner observed that the
; hop feature drives the rear digital output on an instrument that
; has one - the code agrees, and this address was previously
; undeclared.
hop_latch              equ     $0B00

; element 4 of the Memory Map Access screen, which labels it
; 'Output 1' - a2u13_page3 $54F3 holds the string and $50B4 sets
; $3FAB=$0C00 for that arm. NO INSTRUCTION NAMES IT WITH AN
; EXTENDED OPERAND: the screen reaches it through [$3FAB], so it
; is declared from the firmware's own label for it and from its
; position in the table beside $0B00 HOPLATCH and $0D00 'Output
; 2', not from a reference. Declared because README.md said the
; screen's seven elements are 'every one of them I/O' while this
; table listed five of them.
output_1_latch         equ     $0C00

; element 5 of the Memory Map Access screen, labelled 'Output 2'
; (a2u13_page3 $54FC, arm at $50CE setting $3FAB=$0D00). The
; description of output_latch_strobe ($0800) already cited this
; address by that name. $519E special-cases elements 4 and 5:
; after storing the entered byte here it also stores it to $0800.
; Like $0C00, no extended operand names it - it is reached through
; [$3FAB].
output_2_latch         equ     $0D00

; decoded here: written at $DC56 and $DC69 by the NMI handler
ptm_cr                 equ     $1000

; decoded here: read at $F064 and $F090 in the PTM drain, tested
; for bits 0,1,2 and 7
ptm_status             equ     $1001

; decoded here: read at $F071 to clear timer 1
ptm_timer1             equ     $1002

; decoded here: read at $F07E to clear timer 2
ptm_timer2             equ     $1004

; decoded here: read at $F08B to clear timer 3
ptm_timer3             equ     $1006

; supplied map: A2U13 page select; the window $4000-$7FFF is the
; paged ROM
page_select            equ     $4000

; How many output boards the instrument can hold. Four channel latches exist
; at $0C00, $0D00, $0E00 and $0F00, and the presence probe walks exactly
; those four. Most instruments have fewer fitted; channel_probe finds how
; many.
CHANNEL_MAX     equ     4

; --- what each bit of a channel latch does ---------------------------------
; The latch at $0C00 + channel*$100 is WRITE-ONLY, so every change goes
; through channel_latch_rmw and the shadow. These are the bits whose meaning
; is established; the two that are not are named as unknown rather than
; guessed at, because a comment that confidently describes an unknown bit
; reads exactly like one that describes a known one.
;
; They were declared in two different modules and neither was visible to the
; paged images, so the sequence players could not gate their own outputs.
; THE THREE LOW BITS WERE ALL WRONG HERE, and they were wrong together
; because they were read off routine NAMES rather than off what the routines
; write. Two of those names - set_output_enable and switch_channel_latch_bit0
; - were assigned by this project's own disassembler and are inferences, not
; HP's words.
;
; What settled it: set_output_enable ($B79C) writes MASK $04, not bit 0, and
; set_output_enable_mode ($F770) - which the FILTER screen calls - is the one
; that reaches bit 0. Two different routines with confusingly similar names.
; The service manual then names the physical lines.

LATCH_FILTER    equ     $01             ; bit 0: the OUTPUT FILTER select,
                                        ; net FLC on J1-24.
                                        ;
                                        ; Manual page 8-27: "A high on FLC
                                        ; switches in the Low Overshoot
                                        ; Filter", so LOW is the Sharp Cutoff
                                        ; filter - an elliptic function
                                        ; filter, flat within 0.01 dB to
                                        ; 600 kHz with a 3 dB corner at
                                        ; 670 kHz - and HIGH is the Low
                                        ; Overshoot, a Gaussian filter that
                                        ; prevents ringing and "limits the
                                        ; useable frequency range to 50 kHz".
                                        ;
                                        ; THAT 50 kHz IS THE FREQUENCY
                                        ; CEILING. The ROM drops the limit
                                        ; from 600 kHz to 50 kHz for Ramp,
                                        ; Triangle, Square and Pulse, and the
                                        ; manual says the Low Overshoot
                                        ; filter is automatically selected
                                        ; "for most other waveforms" -
                                        ; Sharp Cutoff being "used for sine".
                                        ; The rule in frequency.s was
                                        ; implemented from the ROM without
                                        ; knowing why; this is why.
                                        ;
                                        ; The sharp-cutoff contact is
                                        ; annotated NORMALLY CLOSED ON
                                        ; POWER-UP.
LATCH_FLOAT     equ     $02             ; bit 1: the OUTPUT FLOAT relay,
                                        ; K404A, which manual page 8-28 says
                                        ; "controls the float or ground state
                                        ; of the low-output line". ACTIVE
                                        ; LOW: output_latch_bit1_set ($B6EF)
                                        ; writes $02 when the requested state
                                        ; is ZERO, so clear is floating.
LATCH_OUTPUT    equ     $04             ; bit 2: the OUTPUT ON/OFF relay, and
                                        ; it is ACTIVE LOW - CLEAR IS ON.
                                        ;
                                        ; set_output_enable ($B79C) at $B7B0:
                                        ; a non-zero state writes $FF to
                                        ; $23B3+channel and value 0 through
                                        ; mask $04; a zero state writes 0 to
                                        ; $23B3 and value $04. So set is off.
                                        ;
                                        ; IT IS ALSO THE BLANKING MUTE.
                                        ; switch_channel_latch_bit0 ($F692)
                                        ; asserts it, waits 5 ms, changes the
                                        ; filter, waits 5 ms, and releases it
                                        ; - and the release is gated on
                                        ; $23B3+channel, so a channel that was
                                        ; off stays off. There is no separate
                                        ; mute line; the output relay is the
                                        ; mute.
                                        ;
                                        ; $23C1 bit 4 vetoes asserting it,
                                        ; which is special function 4,
                                        ; "Disable output blanking".
LATCH_RANGE     equ     $78             ; bits 6:3: the amplitude exponent,
                                        ; COMPLEMENTED, driving four
                                        ; relay-switched attenuator pads of
                                        ; 6, 12, 24 and 48 dB on nets AT3 to
                                        ; AT0 - see modules/amplitude.s for
                                        ; the manual's own wording and for
                                        ; why the net numbering runs opposite
                                        ; to the weights.
LATCH_PROBE     equ     $80             ; bit 7: the board-presence probe.
                                        ; Set, strobe $0800, read int_latch.

