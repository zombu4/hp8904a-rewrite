; ===========================================================================
; formats.inc - the shapes a value can be entered and displayed in
;
; Constants the paged screens need in order to describe their own fields,
; without carrying the code that implements entry. See display.inc for why
; the split exists.
; ===========================================================================

; --- numeric entry ---------------------------------------------------------
ENTRY_MAX       equ     8               ; the widest field: eight decimal
                                        ; digits, which is a 24-bit value
ENTRY_DECIMAL   equ     10
ENTRY_HEX       equ     16

; --- a field on a screen ---------------------------------------------------
; A descriptor is four bytes: position, width, entry base, flags.
FIELD_SIZE      equ     4
FIELD_PLAIN     equ     $00             ; editable, nothing special
FIELD_READONLY  equ     $01             ; shown but not editable
FIELD_UNITS     equ     $02             ; a unit key applies to it

; --- how a typed number is scaled ------------------------------------------
UNIT_NONE       equ     0               ; store what was typed
UNIT_KILO       equ     1               ; x1000
UNIT_MEGA       equ     2               ; x1000000
UNIT_MILLI      equ     3               ; already in milli-units

; --- the unit codes, which are the instrument's own -----------------------
; Read out of the stock image: sixteen 16-bit pointers at $EEEE index sixteen
; length-prefixed labels at $EF0E. See modules/units.s for what each scales
; to and why there is no MHz and no dB.
;
; They were declared in units.s, which only A2U12 carries, so a paged screen
; comparing a key against UNIT_HZ could not name it.
UNIT_BLANK      equ     0
UNIT_KHZ        equ     1
UNIT_HZ         equ     2
UNIT_DEG        equ     3
UNIT_RAD        equ     4
UNIT_VOLT       equ     5
UNIT_MILLIVOLT  equ     6
UNIT_MICROVOLT  equ     7
UNIT_SECOND     equ     9
UNIT_MILLISEC   equ     10
UNIT_PERCENT    equ     11
UNIT_PULSE      equ     15              ; the blank entry the stock gives a
                                        ; channel whose destination is Plse
                                        ; ($7E2B writes $0F into record+13)
UNIT_OFF        equ     13              ; and the blank one it gives Off
                                        ; (destn_units_off_blank $7E5D, $0D).
                                        ;
                                        ; Both are BLANK in the label table at
                                        ; $EEEE, and that is not cosmetic: the
                                        ; units sub-table d4fbe sends codes
                                        ; $0D, $0E and $0F to entry_cfg_unsettable
                                        ; ($4F27), which skips the
                                        ; arm_numeric_entry_field call
                                        ; entirely. A channel on Plse or Off
                                        ; has no keyable amplitude at all.
UNIT_DSB        equ     14
UNIT_COUNT      equ     16

; --- eight decimal digits reach further than 24 bits -----------------------
TEXT_DIGITS     equ     8

; --- how the AMPTD field is laid out, wherever it is shown -----------------
; ampl_text in modules/amplitude.s renders it and two screens display it - the
; channel screen on A2U13 page 0 and the tone sequence screen on page 1 - so
; the shape has to be declared where both images can see it rather than inside
; the routine that fills it.
AMPL_TEXT_W     equ     TEXT_DIGITS+1   ; eight digits and a point
AMPL_TEXT_U     equ     2               ; the two columns a unit gets
AMPL_TEXT_RESULT equ    6               ; and how many characters an arm of
                                        ; the stock's format dispatch hands
                                        ; write_unit_label_and_digits ($576C):
                                        ; five digits and a point, of which it
                                        ; shows the first five
AMPL_MICRO      equ     6               ; decimal places in a microvolt value

; --- the DDS registers -----------------------------------------------------
;
; THESE ARE THE CHIP'S, READ OUT OF THE STOCK FIRMWARE. The descriptor table
; at $DD73 gives forty-two register ids, $00 to $29, each with a shadow
; address and a width code, and dds_param_store ($DD9D) writes them. The
; established ones are named below; the rest are not named because their
; purpose is not established, and naming them would be inventing.
;
; THE PREVIOUS SET WAS ENTIRELY INVENTED: DDS_FREQ_A=0, DDS_PHASE_B=1,
; DDS_LEVEL_C=2, DDS_FREQ_D=3, DDS_WAVEFORM=4, DDS_OUT_MUX=5, DDS_CLKDIV=6,
; DDS_SYNC_SEL=7, eight registers in all. The chip has forty-two, and
; register 0 is not channel A's frequency - it is a BUFFER LATCH, one of the
; four that stage a value before it is latched into a channel. So every write
; through the old names put a fragment of a value into a staging register and
; latched nothing, which is not a wrong frequency but no frequency at all.
;
; Three call sites used them: the tone sequence's step player, the DTMF tone
; pair, and the channel summary screen. All three are corrected.
;
; THE FOUR BUFFER LATCHES. A value is written into these most significant
; field first, and then a write to a channel's own register latches the
; staged word into it.
DDS_BUFLAT3     equ     $03             ; bits 23:18 of a 24-bit value
DDS_BUFLAT2     equ     $02             ; bits 17:12
DDS_BUFLAT1     equ     $01             ; bits 11:6
DDS_BUFLAT0     equ     $00             ; bits 5:0

; THE PER-CHANNEL LATCHES. Add the channel, 0 to 3.
DDS_FREQ_BASE   equ     $08             ; $08-$0B, a 24-bit tuning word
DDS_LEVEL_BASE  equ     $0C             ; $0C-$0F, a 12-bit amplitude
DDS_PHASE_BASE  equ     $10             ; $10-$13, a 12-bit phase

DDS_REGISTERS   equ     $2A             ; ids $00 to $29 exist

; The output source multiplexer. Two registers, each carrying two sockets in
; 3-bit fields: Out1 and Out3 in bits 2:0, Out2 and Out4 in bits 5:3. A field
; holds the channel feeding that socket, or PORT_NONE for nothing.
; Moved here from modulation.s because the power-on reset in dds.s needs them
; too, and a constant that two modules need does not belong inside one of
; them.
DDS_PORT_MUX_01 equ     $22             ; Out1 and Out2
DDS_PORT_MUX_23 equ     $23             ; Out3 and Out4
DDS_PULSE       equ     $26             ; HP CALLS IT configr, NOT pulse_c -
                                        ; the name here was wrong and the
                                        ; number was right.
                                        ;
                                        ; The 42 names come from a pointer
                                        ; table at $568F on A2U13 page 3, and
                                        ; reading it out gives $18 = pulse_c
                                        ; and $26 = configr. "pulse_c" had
                                        ; been attached to $26 because THIS
                                        ; firmware uses it to pulse, which is
                                        ; the same mistake as naming a thing
                                        ; after what you do with it and then
                                        ; citing somebody else for the name.
                                        ;
                                        ; The VALUE is confirmed:
                                        ; dds_reg26_bit3_pulse ($DE7F) does
                                        ; LDB #$26 twice, first with the
                                        ; shadow ANDed $F7 and then with the
                                        ; shadow restored - a one-shot LOW
                                        ; pulse on bit 3 of register $26,
                                        ; which is the instrument's automatic
                                        ; phase reset.
                                        ;
                                        ; The constant keeps its behavioural
                                        ; name, as DDS_PORT_MUX_01 does for
                                        ; $22 (HP: outclk1). What is fixed is
                                        ; the claim about what HP calls it.
PULSE_PHASE_RESET equ   $08             ; that bit. Established from
                                        ; dds_reg26_pulse_if_flag1_clear
                                        ; ($DEB6), which skips the pulse when
                                        ; bit 1 of the special flags is set,
                                        ; and the stock's own screen text for
                                        ; that bit reads "Disable automatic
                                        ; phase reset".
; THE INSTRUMENT'S TOP FREQUENCY, as three bytes, where every image can see
; it. frequency.s has the same number as FREQ_MAX_* but that file lands in
; A2U12 and the hop screen is on a page, so the constant is declared here
; rather than reached across the image boundary.
;
; $5B8D80 = 6,000,000, and 6,000,000 x 0.1 Hz = 600 kHz. It is the constant
; the stock keeps at $EA55 and subtracts against before accepting a hop
; frequency, raising error $71 on a borrow.
; AND THE PULSE MODULATOR'S OWN CEILING, which is a tenth of the instrument's
; top. $EA5F holds $07,$A1,$20 = 500,000, which in the same 0.1 Hz units is
; 50 kHz. reject_pulse_destination ($7D1D) subtracts a channel's frequency from
; it and, on a borrow, forces the destination back to Off with an error - so a
; channel above 50 kHz may not be made a pulse modulator.
PULSE_FREQ_HI   equ     $07
PULSE_FREQ_MID  equ     $A1
PULSE_FREQ_LO   equ     $20

; THE OTHER TWO CEILINGS, here for the same reason the frequency one is: the
; hop screen is on a page and amplitude.s and phase.s land in A2U12, so a page
; cannot see their constants. They are DEFINED here and those two files refer
; to them, rather than each holding its own copy - two copies of a limit is
; two chances to change one of them.
TOP_AMPL_HI     equ     $98             ; $989680 = 10,000,000 microvolts
TOP_AMPL_MID    equ     $96
TOP_AMPL_LO     equ     $80
TOP_PHASE       equ     3599            ; a whole turn less a tenth

TOP_FREQ_HI     equ     $5B
TOP_FREQ_MID    equ     $8D
TOP_FREQ_LO     equ     $80

HOP_FREQ        equ     0               ; offsets within a hop slot
HOP_AMPL        equ     3
HOP_PHASE       equ     6

; WHICH UNIT THAT PHASE IS IN, in the top bit of the word itself. The stock
; keeps it as a separate word at record+13 of a fifteen-byte record and the
; two scales differ - tenths of a degree for unit 3, thousandths of a radian
; for unit 4 - so a slot has to remember which one it holds; 6.282 rad is
; 359.98 degrees and comes back as 6281 thousandths if it is rebuilt from
; 3599 tenths. This slot is eight bytes and scratch has no room for sixteen
; more, and the value needs thirteen bits at most (6282, or 3599), so the bit
; rides on the value. page0_hop.s's hop_show_one and hop_store_field, dds.s's
; hop_program and remote.s's HOPP query are every reader, and each one masks
; it.
HOP_PHASE_RAD   equ     $8000
HOP_PHASE_RAD_HI equ    $80             ; the same bit, in A
HOP_PHASE_VALUE_HI equ  $7F

; The sign character a level is held with: one byte per channel in ampl_signs
; and one per slot in hop_signs. The two characters are the stock's own - the
; default record at $ED89 carries $2B at +$14, apply_amplitude_entry ($6547)
; stores $241E there at $6613, and scale_to_dds_code ($D3EC) tests it against
; $2D at $D4E7.
;
; They were page0_screen.s's own equs, which was right while page 0 was the
; only image naming them. dds_table_defaults ($E7F9) primes sixteen of these
; bytes - record+10 of every hop slot - and its port moved to the
; always-mapped image with the rest of the cold-start path, so both images
; name them now.
CHAN_SIGN_PLUS  equ     $2B
CHAN_SIGN_MINUS equ     $2D
HOP_ENTRY_SIZE  equ     8               ; a 24-bit tuning word, a 24-bit
                                        ; amplitude and a 16-bit phase.
                                        ;
                                        ; IT WAS THREE - the frequency alone -
                                        ; and dds.s called that "a design
                                        ; decision rather than something the
                                        ; ROM settles", ending with "widening
                                        ; it would mean two more screens to
                                        ; fill it". The ROM settles it. The
                                        ; stock's hop record is FIFTEEN bytes
                                        ; and four independent sites name its
                                        ; fields: apply_hop_frequency_entry
                                        ; ($4BFE) writes the frequency at +4,
                                        ; show_hop_amptd_field ($4579) formats
                                        ; the amplitude at +7,
                                        ; draw_hop_phase_field ($468E) reads
                                        ; the phase at +11 with its unit at
                                        ; +13, and the array descriptors at
                                        ; d4ec6 and d7eb7 both carry the
                                        ; stride $000F.
                                        ;
                                        ; The layout here is compact rather
                                        ; than a copy: this firmware has no
                                        ; use for the stock's sign byte or its
                                        ; per-slot unit code, and a phase is
                                        ; held in the same tenths of a degree
                                        ; every other phase here is.
; THE FOUR MODE-CONTROL REGISTERS, and the flag bit each one's state is
; mirrored into. Read out of dds_mode_param_set ($E69C), which maps a control
; id onto a parameter id, writes it, and records whether the value was 8:
;
;   $19 am_cont  -> bit 6 of $2203     (le6af)
;   $18 pulse_c  -> bit 5              (le6d6)
;   $17 phs_cnt  -> bit 7              (le6fd)
;   $1B freq_ct  -> bit 0 of the HIGH byte, and the value is forced (le72c)
;
; A VALUE OF 8 IS WHAT "ON" MEANS for the first three - set_hop_function_enable
; (page 0 $4984) produces 8 when its argument is $0011 and 0 otherwise - and
; the flag exists so other code can ask the question without reading back a
; write-only register.
;
; The interlock that made this worth finding: reject_am_while_amptd_hop
; ($7C9F) refuses the AM destination while bit 6 is set, with error selector 1.
DDS_AM_CONT     equ     $19             ; amplitude hop / AM control
DDS_PULSE_CTL   equ     $18             ; HP calls it pulse_c
DDS_PHASE_CTL   equ     $17             ; phs_cnt
DDS_MODE_ON     equ     $08             ; the value that turns one on
; THE EDGED-WAVEFORM CEILING, $07A120 = 500,000 tenths of a hertz = 50 kHz.
; Ramp, Triangle and Square are built from hard edges and their harmonics
; leave the output filter above it; check_freq_limit (page 0 $63D2) drops the
; ceiling to this for waveform codes 2, 3 and 6 and for a Plse destination,
; and apply_waveform_choice ($674C) refuses the waveform when the frequency is
; already past it. Both sides of that rule need the number.
RAD_DECADES     equ     3
CHAN_UNIT_DEG   equ     3               ; a channel's phase unit, record+$19
CHAN_UNIT_RAD   equ     4               ; in the stock: 3 deg, 4 rad
PHASE_MAX_MRAD  equ     6282            ; $EA5D, commit_channel_phase's radian
                                        ; ceiling               ; a radian is typed whole and stored
                                        ; in thousandths, so the digits are
                                        ; scaled by three decades less the
                                        ; fraction: 3 and 3.000 are both three
                                        ; radians on the instrument

FREQ_EDGED_HI   equ     $07
FREQ_EDGED_MID  equ     $A1
FREQ_EDGED_LO   equ     $20
FREQ_EDGED_LOW16 equ    $A120

MODE_FLAG_AM    equ     $40             ; bit 6 of the low byte of the flags
MODE_FLAG_PULSE equ     $20
MODE_FLAG_PHASE equ     $80

DDS_FM_RANGE    equ     $16             ; HP calls it fm_rang, and the
                                        ; stock writes the SHIFT COUNT that
                                        ; normalises the summed FM level here
                                        ; - rescale_channels_to_common_exponent
                                        ; ($BAE3) through dds_write_reg16
                                        ; ($E36F). It is a shared range, not a
                                        ; per-channel value.
DDS_FREQ_CT     equ     $1B             ; HP calls it freq_ct, and it is what
                                        ; the Freq Hop row of the stock's
                                        ; special-function screen writes -
                                        ; set_hop_function_enable (page 0
                                        ; $4984) reaches it through control id
                                        ; $15, which maps to parameter $1B at
                                        ; $E72C.
HOP_ON          equ     $00             ; ON writes ZERO and OFF writes $04.
HOP_OFF         equ     $04             ; That polarity is the opposite of what
                                        ; this file used to say, and it is the
                                        ; stock's: the enable path does `CLR
                                        ; 4,S` and the disable path `ORB #$04`.
                                        ; The power-on flush storing $04 is
                                        ; therefore hop OFF, which is right.
DDS_HOP_ADDRESS equ     $15             ; HP calls it ram_add: which slot of
                                        ; the chip's hop RAM the next write
                                        ; lands in
DDS_HOP_WRITE   equ     $14             ; and ram_wrt, which strobes it. That
                                        ; these two are address and strobe is
                                        ; an INFERENCE, marked as one in
                                        ; audit/hop_programming.md: what is
                                        ; established is that dds_write_channel
                                        ; ($DE2E) writes ($15, index), then
                                        ; ($14, $00), then restores $15, and
                                        ; that page 1's tone code does the same
                                        ; four steps by hand.
PORT_KEEP_MASK  equ     $38             ; the mask set_dds_mux_field ($E5E8)
                                        ; ANDs the old value with before
                                        ; inserting a new field: $38 for the
                                        ; low socket, $38>>3 = $07 for the
                                        ; high one. It keeps the OTHER socket
                                        ; and clears bits 6 and 7 as well.
                                        ; What those two bits do is NOT
                                        ; ESTABLISHED: every write to $22 and
                                        ; $23 in all five images was
                                        ; enumerated - set_dds_mux_field
                                        ; ($E5E8, a2u12.s:20146-20165), the
                                        ; power-on flush in dds_params_reset
                                        ; ($DF17), page 1's DTMF code and page
                                        ; 2's digital-sequence ISR - and none
                                        ; of them ever sets either bit. Only
                                        ; that the stock clears them is
                                        ; established.
PORT_FIELD_MASK equ     $07             ; three bits
PORT_ODD_SHIFT  equ     3               ; the odd port sits three up
PORT_KEEP_ODD   equ     $07             ; PORT_KEEP_MASK for the odd socket:
                                        ; $E65E-$E66A shift $38 right by the
                                        ; odd shift of 3, so bits 0-2 - the
                                        ; even socket's field - are what is
                                        ; kept. Written out because neither
                                        ; assembler is asked to shift here
PORT_NONE       equ     $04             ; no source routed to this port
; THE SUMMING GROUP. Several channels can feed one destination - a socket or
; a modulation input - and the chip adds them: DDS parameter $1F holds the
; mask of the channels in the group and register $20 the node that carries
; the sum, and the destination's own field or register then names that node
; rather than a channel. The stock builds both in dds_mux_mask_add_source
; ($E029) and dds_mux_mask_remove_source ($E185) through dds_reg20_program
; ($DF9F), which a2u12's route_source_selector ($C7B0) then routes; sum_join,
; sum_leave and sum_node_program in modules/modulation.s are the port. Both
; power on at zero: dds_params_reset ($DF17) wipes $248A-$24C4 and sets
; neither $24B8 ($1F, descriptor byte $2E at $DD73+$1F) nor $24B9 ($20,
; byte $2F) afterwards, and dds_reset_globals in dds.s seeds them so.
DDS_SUM_MASK    equ     $1F             ; one bit per channel in the group
DDS_SUM_NODE    equ     $20             ; the node code dds_reg20_program
                                        ; picks: $02, $04 or $08 for the
                                        ; highest channel in the mask, $0A
                                        ; for the split pair, 0 for no group
SUM_ACTIVE      equ     $08             ; a group exists: event_flags ($2204)
                                        ; bit $0800, set at $E054, cleared at
                                        ; $E210, tested at $E045/$DFA5
SUM_SPLIT       equ     $10             ; two groups, {A,B} and {C,D}, on two
                                        ; destinations: bit $1000, set at
                                        ; $E10D, cleared at $E1BB, tested at
                                        ; $E1AA/$DFBB
SUM_MASK_LOW    equ     $03             ; the only masks a second group may
SUM_MASK_HIGH   equ     $0C             ; form beside: $E0FA-$E10A, or the
                                        ; "Summing channels cannot be split"
                                        ; refusal, $6A
SUM_MASK_ALL    equ     $0F             ; both halves summed: $E116
SUM_NODE_SPLIT  equ     $0A             ; register $20 for that: $DFCB
PORT_MUX_IDLE   equ     $24             ; both fields holding PORT_NONE:
                                        ; ($04 << 3) | $04. Written as the
                                        ; constant because neither assembler
                                        ; takes a parenthesised expression in
                                        ; an immediate, and it is the byte the
                                        ; stock firmware stores at $24BB/$24BC


; THE REST OF THE MAP, established by enumerating every writer of every id
; against the descriptor table at $DD73. None of this is guessed and the
; routine that writes each is named, so a reader can check any line of it.
;
;   $15   the DDS slot/channel select, written by dds_write_channel ($DE2E)
;   $16   a common amplitude exponent, from
;         rescale_channels_to_common_exponent ($BB13)
;   $17   phase-modulation source select     } one byte each, holding the
;   $18   pulse-modulation source select     } modulating channel biased by
;   $19   AM and DSB source select           } $0C - see modules/modulation.s
;   $1A   FM source select                   }
;   $1B   HP calls it freq_ct. set_hop_function_enable (page0 $4984) writes
;         it through control id $15, which maps to parameter $1B at $E72C,
;         and the POLARITY IS THE OPPOSITE of what this line used to say:
;         Freq Hop ON writes $00 (`CLR 4,S`) and OFF writes $04 (`ORB #$04`).
;         The power-on flush storing $04 is therefore hop OFF, which is what
;         it should be. It is not exclusive to hop either -
;         tone_sequence_mode_enter ($55C5) writes it too - so "the hop enable"
;         was a name for one of its uses, not for the register.
;   $1D   WAVEFORM codes for channels 0 and 1, three bits each
;   $1E   WAVEFORM codes for channels 2 and 3
;   $1F   a bitmask of the channels feeding a destination, from
;         dds_mux_mask_add_source ($E029) and its remove twin ($E185)
;   $22   the output-port source mux for ports 0 and 1, three bits each,
;   $23   and for ports 2 and 3, from set_dds_mux_field ($E5E8)
;   $26   a one-shot low pulse on bit 3, from dds_reg26_bit3_pulse ($DE7F)
;
;   $04-$07, $14, $1C, $20, $21, $24, $25, $27-$29 are written only by the
;   power-on flush and by the Manual CowChip service screen, which writes an
;   arbitrary id.
;
;   THEY ARE NO LONGER NAMELESS. HP's own diagnostics print a name for every
;   one of the forty-two, and that table is in the ROM this repository has:
;   a 42-entry pointer table at $568F on A2U13 page 3, each pointer naming an
;   eight-byte arm that loads a string address, with the strings from $624D.
;   Read out, in id order:
;
;     $00-$07 buflat0..buflat7   $08-$0B freq_a..freq_d
;     $0C-$0F level_a..level_d   $10-$13 phase_a..phase_d
;     $14 ram_wrt   $15 ram_add   $16 fm_rang  $17 phs_cnt
;     $18 pulse_c   $19 am_cont   $1A fm_cont  $1B freq_ct
;     $1C zero_lt   $1D wavefm1   $1E wavefm2  $1F chanadd
;     $20 out_mux   $21 out_lat   $22 outclk1  $23 outclk2
;     $24 clkdiv1   $25 clkdiv2   $26 configr  $27 pll_div
;     $28 syncsel   $29 sync_rg
;
;   A NAME IS NOT A BEHAVIOUR, and the two must not be confused. This is what
;   HP called each register; what the firmware does with it is a separate
;   question answered by the writers enumerated above, and where the two
;   appear to disagree - $20 is called out_mux while $22 and $23 are the
;   registers set_dds_mux_field ($E5E8) writes - the disagreement is recorded
;   rather than resolved by preferring whichever is convenient. That one is
;   under investigation in audit/output_mux.md and nothing in this file has
;   been changed on the strength of the name alone.
;
;   What each of the twelve SELECTS is still not established; only what it is
;   called. The service screens now print these names, which is what they are
;   for - service_dds.s carries the table and page 3 calls it through the ABI,
;   because both screens had their own copy of an invented set naming the
;   eight buffer latches after frequencies and levels.
;
; This file used to say "which register selects a waveform" was not
; established. It is $1D and $1E, and the routine that writes them was in the
; symbol file under the name unit_code_select_head the whole time.

; --- the errors a screen can raise -----------------------------------------
;
; EVERY NUMBER HERE IS THE INSTRUMENT'S OWN, and the comment on each line is
; the message error_message_table ($7349, A2U13 page 3) carries for it - which
; is what the operator reads when the error flash puts it on line 2. They were
; a compact set of this firmware's own, 0 to $26, chosen before the table was
; read; with the table ported, a number that is not the instrument's prints
; somebody else's words. A refused 700 kHz raised 8, and 8 is the stock's "No
; Output Board 1".
;
; Four of them were DRIVEN on the stock rather than matched by text, 2026-09-11,
; each from the channel screen of a booted machine reading $23DE afterwards:
;
;   700000 then Hz            $7B   Frequency exceeds limit
;   20 then kHz (volts)       $7A   Amplitude sum exceeds limit
;   shift UP, 12, ENTER       $13   Number too large
;   INC SET with no step      $14   Not an incrementable field
;
; Two of this firmware's names share $13: the instrument has ONE message for a
; number it cannot take, and both "the field holds no more digits" and "the
; value is outside the field" are that. The names stay because the source
; reader wants the distinction; the operator does not get one because the
; instrument does not give one.
;
; THE NUMBERS FROM $C0 ARE THIS FIRMWARE'S OWN, for faults the instrument has
; no message for at all - a page that did not answer, a protected address, a
; display that did not take a character. They are above every code the stock
; table uses ($A0 is its highest below $FF), so no number can collide, and
; modules/page3_errors.s carries a message for each in the instrument's voice.
ERR_NONE            equ  $00    ; No Error
ERR_VALUE_RANGE     equ  $13    ; Number too large
ERR_VALUE_TOO_BIG   equ  $13    ; Number too large
ERR_NO_SUCH_CHANNEL equ  $68    ; Output selected does not exist
                                ; installed count. For a destination it is the
                                ; stock's $68: set_channel_destination ($78BF)
                                ; at $79A3-$79EB maps Out1-Out4 to 0-3 with
                                ; port_code_to_channel ($C765), adds one with
                                ; add_bytes_to_word ($FD80) and refuses when
                                ; $23B2 is below it. Its $16, $68 and $A0 all
                                ; print the one string at a2u13_page3 $7A79,
                                ; 'Output selected does not exist', so one
                                ; number serves here too.
ERR_OUTPUT_NUMBER   equ  $A0    ; the output screens' number past the fitted
                                ; count: output_onoff_key_handler ($F3F0)
                                ; beeps it through error_report_beep ($C3FE)
                                ; at $F4D6, and page 3's table prints it with
                                ; $68's words
ERR_NO_OPTION       equ  $C0    ; Option not installed
ERR_PAGE_FAILED     equ  $C1    ; Paged ROM did not answer
ERR_RAM_FAULT       equ  $C2    ; RAM fault detected
ERR_ROM_FAULT       equ  $0B    ; Hardware errors detected
ERR_FREQ_RANGE      equ  $7B    ; Frequency exceeds limit
                                ; 50 kHz for a hard-edged waveform or for
                                ; pulse modulation
ERR_AMPL_RANGE      equ  $7A    ; Amplitude sum exceeds limit
ERR_PHASE_RANGE     equ  $C3    ; Phase value out of range
ERR_DESTN_CODE      equ  $C4    ; Destination code not known
ERR_UNIT_UNKNOWN    equ  $C5    ; Unit code not known
ERR_REG_RANGE       equ  $13    ; Number too large
ERR_MOD_SELF        equ  $65    ; Channel A can not modulate itself
                                ; stock firmware's own error $65, in its own
                                ; words
ERR_DISPLAY_FAULT   equ  $C6    ; Display fault detected
                                ; character written to it. The Display Check
                                ; raised ERR_RAM_FAULT for this, which sends
                                ; an engineer to the wrong board: the probe
                                ; writes one cell through lcd_put and reads it
                                ; back with lcd_get, and nothing about that
                                ; test touches RAM.
ERR_FAULT_LINE      equ  $0D    ; Reverse power error detected
                                ; output. int_latch carries four of these
                                ; lines, one per output, and the foreground
                                ; raises this when the asserted set changes.
                                ;
                                ; WHICH BIT IS WHICH OUTPUT IS NOW
                                ; ESTABLISHED, and this entry used to say the
                                ; opposite. It said the paths guarding each
                                ; message in the stock's foreground "do not
                                ; settle the mapping" and that the message
                                ; writes "are not conditional on the bit tests
                                ; beside them". That was a reading of the
                                ; wrong stretch. foreground_main_loop ($83A0)
                                ; settles it at $8622-$8679, four tests in a
                                ; row on the same local, each storing an
                                ; output number AND its ASCII digit:
                                ;
                                ;   ANDB #$08 -> 4, '4' ($34)   at $8637
                                ;   ANDB #$04 -> 3, '3' ($33)   at $8646
                                ;   ANDB #$02 -> 2, '2' ($32)   at $8657
                                ;   ANDB #$01 -> 1, '1' ($31)   at $8668
                                ;
                                ; and $8679 then paints $EDF7, 'Reverse Power
                                ; Relay Tripped on Output', with that digit at
                                ; column $26. The local is int_latch EOR $0F,
                                ; computed at $84CA, so a CLEAR bit in the
                                ; port is the fault.
                                ;
                                ; The two messages are not two readings of one
                                ; ambiguous test after all: the reference-loop
                                ; one belongs to bit 5, which is a different
                                ; line and is not inverted. See ERR_REF_UNLOCK.
ERR_REF_UNLOCK      equ  $0C    ; PLL reference out of lock
                                ; of int_latch, tested at $84D4 on the same
                                ; local - and the EOR at $84CA only reaches the
                                ; low four bits, so this one is read as it
                                ; stands and a SET bit is the fault. The stock
                                ; paints $EDCF, '!! Reference Loop Reports Out
                                ; Of Lock !!', beeps its error $0C and waits
                                ; delay_ms($02EE).
                                ;
                                ; NOTHING HERE POLLED IT. pll_faults_asserted
                                ; masked $0F and stopped, so the four
                                ; reverse-power lines were watched and the one
                                ; that makes every frequency the instrument
                                ; produces wrong was not.
ERR_NO_CHANNELS     equ  $0A    ; No Output Board 1
                                ; probe found zero, so the instrument can
                                ; synthesise but cannot put anything out of a
                                ; socket, and nothing an operator does on any
                                ; channel screen can work.
                                ;
                                ; The stock raises this at power-on and it was
                                ; missing here: power_on_init ($81AD) at $8345
                                ; does LDB >$23B2 / CMPB #$00 and, when the
                                ; installed count is zero, calls
                                ; error_report_beep ($C3FE) with $0A - which
                                ; sounds timer 1 and records the code - rather
                                ; than clearing $23DE as it does on every other
                                ; path. $0A is the STOCK's number for it; this
                                ; firmware keeps its own catalogue and numbers
                                ; it here, which is why the two differ.
ERR_KEY_UNUSABLE    equ  $0F    ; Un-executable command
                                ; was silently ignored here, and the stock
                                ; refuses it audibly:
                                ; numeric_entry_key_handler ($B3C2) tries
                                ; key_to_state_code ($AD4D),
                                ; keymap_menu_msgs_19_1d ($AEBB),
                                ; entry_backspace ($B2CD),
                                ; keypad_char_column_select ($AF29) and
                                ; accept_units_key ($B0C1) in that order, and
                                ; what none of them claims reaches
                                ; error_report_beep ($C3FE) - at $B49A with
                                ; code 1 when no entry field is armed, and at
                                ; the fall-through with code 2.
                                ;
                                ; ONE CODE HERE, NOT TWO. The stock's two say
                                ; whether a field was armed, which an operator
                                ; can already see on the screen in front of
                                ; them; what they need to know is that the key
                                ; did nothing, and the beep is what tells them.
ERR_NO_STEP_FIELD   equ  $04    ; No incrementable field
                                ; The ARROWS on a field that cannot be
                                ; stepped: d7701's arms [3] and [4],
                                ; reject_step_error_4, which is what the
                                ; waveform and destination fields answer UP and
                                ; DOWN with. Its neighbour below is INC SET's
                                ; refusal on the same fields, a different code
                                ; and different words.
ERR_NO_ENTRY_FIELD  equ  $01    ; a key needing an armed field, none
                                ; armed: lb494 ($B494) LDB #$01 into
                                ; error_report_beep ($C3FE)
ERR_KEY_ENTRY       equ  $02    ; Invalid key entry
                                ; A key with no meaning on the field being
                                ; edited - $B5D0's error_report_beep(2). On a
                                ; choice field that is every key outside its
                                ; column of keypad_char_table ($EF94).
ERR_NOT_STEPPABLE   equ  $14    ; Not an incrementable field
                                ; increment. The WAVE, DEST and channel
                                ; fields are choices or selectors, not values,
                                ; so an arrow key and INCR SET have nothing to
                                ; act on.
                                ;
                                ; Silently ignored here, and the stock refuses
                                ; it: the 18-arm step dispatch at $7701 on
                                ; a2u13_page0 sends arms 3, 4, 8, 9, 10 and
                                ; its out-of-range guard to reject_step_error_4,
                                ; which is error_report_beep ($C3FE) with 4.
ERR_PHASE_ACTIVE    equ  $72    ; Phase mod is active
                                ; SWITCHING PHASE HOP ON while a channel
                                ; is routed to phi-M. set_hop_function_
                                ; enable's phase arm reads the phi-M
                                ; use-counter $2410 at $4B65 and, with it
                                ; non-zero, reports this at $4B79 and
                                ; switches nothing. Driven on the stock
                                ; 2026-09-11: with channel B on phi-M,
                                ; Phase Hop On answers $72.
ERR_HOP_CONFLICT    equ  $6B    ; Hop Ram enabled for this mod source
                                ; machinery is already driving. The stock's
                                ; error $6B, 'Hop Ram enabled for this mod
                                ; source' (a2u13_page3 $7884), from the four
                                ; checking arms of set_channel_destination's
                                ; table at $7D92: reject_am_while_amptd_hop
                                ; ($7C9F) AM against bit 6 of $2203,
                                ; check_pm_allowed ($7CBC) PhiM against bit 7,
                                ; destn_check_dsb ($7CD2) DSB against bit 6 and
                                ; reject_pulse_destination ($7D1D) Plse against
                                ; bit 5 - MODE_FLAG_AM, MODE_FLAG_PHASE and
                                ; MODE_FLAG_PULSE here. destn_check raises it
                                ; for all four. PhiM and DSB were also
                                ; refused here while the Freq Hop switch
                                ; hop_running was on, and this called that
                                ; "the recorded departure destn_apply keeps".
                                ; It was recorded nowhere - the
                                ; owner made no ruling - and the
                                ; stock's two arms test only bits 7 and 6 of
                                ; $2203, so the extra refusal was a
                                ; divergence. It is gone; both codes now
                                ; join on the stock's own terms.
ERR_RMT_SYNTAX      equ  $30    ; Invalid HP-IB token received
                                ; the stock's error $30
ERR_RMT_VALUE       equ  $29    ; HP-IB number in error
                                ; - the stock's $29 family
ERR_RMT_TERMINATOR  equ  $2E    ; Invalid terminator
ERR_ENTRY_LEVEL     equ  $34    ; a level past the $EA62 ceiling: what
                                ; parse_amplitude_entry ($61AA) and
                                ; accept_level_entry ($4C51) store in their
                                ; page's error cell
                                ; A UNIT THE FIELD'S CLASS DOES NOT TAKE.
                                ; unit_allowed_for_group ($A65A) tests the
                                ; code in $2221 against the class in $238B -
                                ; group 3 takes deg and rad, 4 the three
                                ; voltages, 5 seconds and milliseconds, 6 Hz
                                ; and kHz, 7 percent - and
                                ; pending_setting_service ($A73E) raises this
                                ; at $A939 when no row accepts. Driven on the
                                ; stock 2026-09-11: 'STON 5 HZ;' on a
                                ; sequence time answers $2E.
ERR_RMT_NOT_NUMBER  equ  $2A    ; a number for an armed field whose entry
                                ; takes none: $A833, the field closed
ERR_RMT_NO_FIELD    equ  $2B    ; Number received but not expected
                                ; it - the stock's $2B
ERR_TIME_RANGE      equ  $32    ; Time value out of range
                                ; stock's validate_gate_time ($6033) enforces:
                                ; its error $32 at $60BB
ERR_TIME_BOTH_ZERO  equ  $33    ; On & Off times cannot both be 0
                                ; stock's error $33 at $60AB
ERR_WRONG_MODE      equ  $3A    ; the sequence screens' reject arms, d508c and
                                ; d6e67 ($5071, $6E4F): a request the mode has
                                ; no arm for. page1_tone.s and page2_digital.s
                                ; name it locally too; remote.s's field select
                                ; reads it (remote_select)
ERR_WRONG_WINDOW    equ  $3B    ; "Commmand not available in present window",
                                ; the instrument's own spelling, err_t77ae in
                                ; page3_errors.s. key_select_amptd ($4D47)
                                ; raises it for the AMPTD key on any tone
                                ; record but the sequence output one, and
                                ; key_copy_time_to_all ($4C64) raises it for
                                ; a copy request off the tone-and-timing page
ERR_CHAIN_NO_FUNC   equ  $18    ; "No settable functions in this window",
                                ; docs/stock-error-messages.md line 61, the
                                ; text at $75A8. It is the DEFAULT arm of the
                                ; Channel Configuration chain's one handler:
                                ; l6375 (a2u13_page0 $6375) is reached from
                                ; l63b0 for every key and every bus request
                                ; code the chain has no arm for, and it takes
                                ; bit 3 of event_flags - REMOTE - to choose
                                ; between report_error_and_pulse_status_bit
                                ; ($9DD3) and error_report_beep ($C3FE), which
                                ; is what error_record does here. Driven on the
                                ; stock 2026-09-13 with installed_options $01:
                                ; FRH, APH, PHH, HRA, AHR and QRE each leave
                                ; $18 in $23DE, because l604e's option test
                                ; sends all six down l6075 -> l61a3 -> l63b0
ERR_OPTION_DESTN    equ  $1F    ; Option FW needed for DESTN control
                                ; the option firmware: the stock's key_destn
                                ; ($5FE6, a2u13_page0) opens with LDB
                                ; >installed_options / ANDB #$01 and, with bit
                                ; 0 clear, hands $1F to error_report_beep
                                ; ($C3FE) and selects nothing - 'Option FW
                                ; needed for DESTN control', a2u13_page3 $75CC
ERR_MOD_CHA_DC      equ  $66    ; Ch A's DC waveform can not be modulated
                                ; waveform is dc: set_channel_destination
                                ; ($78BF) at $78F5 LDX >$2514 / CMPX #$0004 -
                                ; $2514 is record 0's waveform, $24F5+$1F -
                                ; the stock's $66, "Ch A's DC waveform can not
                                ; be modulated", a2u13_page3 $77F7
ERR_MOD_SRC_DC      equ  $67    ; Modulation with DC waveform not allowed
                                ; own waveform is dc: $7903-$7922 reads the
                                ; channel's record+$1F and compares it with 4;
                                ; the stock's $67, 'Modulation with DC waveform
                                ; not allowed', a2u13_page3 $781E
ERR_AM_DSB_EXCL     equ  $69    ; AM & DSB are mutually exclusive
                                ; another is AM: $7B7F-$7BC7 tests the new code
                                ; against the counters $240E (DSB) and $240D
                                ; (AM); the stock's $69, 'AM & DSB are mutually
                                ; exclusive', a2u13_page3 $7845
ERR_SUM_SPLIT       equ  $6A    ; Summing channels cannot be split
                                ; one other channel holds while two others
                                ; already sum into a destination of their own
                                ; from both halves of the chip: $7C4C-$7C95
                                ; calls dds_mux_mask_add_source ($E029), whose
                                ; $E0FA-$E152 returns 1 when the summing mask
                                ; is neither 3 nor $0C; the stock's $6A,
                                ; 'Summing channels cannot be split',
                                ; a2u13_page3 $7864
ERR_PULSE_FREQ      equ  $6C    ; Frequency too great for pulse mod
                                ; reject_pulse_destination ($7D1D) at
                                ; $7D30-$7D5F subtracts the channel's frequency
                                ; from $EA5F (500,000 tenths of a hertz) with
                                ; sub24 ($D3C6); the stock's $6C, 'Frequency
                                ; too great for pulse mod', a2u13_page3 $78A7
ERR_DC_SUM_DUP      equ  $99    ; Only one DC sum permitted into an output
                                ; dc channel already sums into: $7943-$7993
                                ; through dc_destination_conflict ($7736); the
                                ; stock's $99, 'Only one DC sum permitted into
                                ; an output', a2u13_page3 $7A51
ERR_REG_EMPTY       equ  $0E    ; No recall setting in this register
                                ; saved into. The stock's enter_handler_by_index
                                ; ($F16A) compares the slot's first word with
                                ; the filler $C239 that power_on_reinit writes
                                ; into every slot ($F19E LDD #$C239 / CMPD 2,S) and
                                ; reports $0E through error_report_beep at
                                ; $F1AB; page 3's error_message_table pairs $0E
                                ; with 'No recall setting in this register'
                                ; (a2u13_page3 $7369: FCB $0E,$22 / FDB $74FC).
                                ; register_recall's marker test is that check.
ERR_PROTECTED       equ  $C7    ; Address is protected
                                ; of the per-unit bytes. $3FEE-$3FFF holds
                                ; the serial number, the installed options
                                ; and the revision signature, and HP's
                                ; recovery refuses a serial that is not
                                ; factory-virgin - so a mistyped address on
                                ; the Manual Memory screen would cost the
                                ; instrument its identity with no way back.
                                ; The Serial Number screen writes those bytes
                                ; through its own validation instead.
ERR_TONE_RANGE      equ  $36    ; Tone number out of range
                                ; THE BUS TYPING A TONE NUMBER. The panel
                                ; cannot reach this code at all: its Tone
                                ; Number field is one hex character and every
                                ; character the column yields is a tone. A
                                ; number arriving over the bus is a decimal
                                ; one of up to three digits, and
                                ; enter_tone_number ($640C) refuses $10 and
                                ; above with this code at $6461, leaving the
                                ; tone that was selected standing.
ERR_SEQ_INDEX       equ  $37    ; Sequence index out of range
                                ; reports $37 through report_index_range_error
                                ; ($605E) when the pointer $3CD0 is aiming at
                                ; $3CA2, and clamp_seq_index_to_end ($5D91)
                                ; raises the same code at $5DB8 when an
                                ; arrow would have taken the cursor past the
                                ; end - the move is undone, not accepted
ERR_SEQ_END         equ  $38    ; Sequence end out of range
                                ; ($605E's other arm). They are two codes on
                                ; the instrument and two here: an operator
                                ; reading the number needs to know which of
                                ; the two numbers was refused
ERR_SEQ_DIGIT       equ  $39    ; Invalid digit for this base
                                ; in binary, 8 in octal. validate_digit_for_base
                                ; ($607E) computes the limit as base<<3, or 2
                                ; when that is zero, and $6104 reports $39
ERR_HOP_WAVE_FREQ   equ  $71    ; Hop Ram frequency too great for waveform
                                ; A hard-edged waveform asked for on channel 0
                                ; while frequency hop is armed and a slot is
                                ; above the 50 kHz ceiling - apply_waveform_choice
                                ; ($674C) raises this instead of $96 there.
ERR_WAVE_FREQ       equ  $96    ; Frequency too great for this waveform
                                ; Ramp, Triangle or Square above $07A120 =
                                ; 500,000 tenths of a hertz, which is 50 kHz.
ERR_DC_DESTN        equ  $97    ; Outx or off destn required for DC
                                ; The dc waveform on a channel whose
                                ; destination is a modulation input.
ERR_DC_MOD_ACTIVE   equ  $98    ; DC not permitted while modulation active
                                ; dc asked for on channel 0 while some channel
                                ; is modulating it.
ERR_SPECIAL_ELSEWHERE equ $10  ; Go to Main Selection Level for SPECIAL
                                ; The instrument's own words for the shifted
                                ; LAST key pressed anywhere but the Main
                                ; Selection Level: invoke_page0_vector_4024
                                ; ($8EDB) compares $220F against $8C14 and
                                ; beeps this instead of opening the screen.
ERR_INTERNAL        equ  $C8    ; Firmware fault - withdrawn call
                                ; A call through a jump-table slot that no
                                ; longer has a routine. It is not an operator's
                                ; mistake and there is no instrument message
                                ; for it; abi_withdrawn raised the generic
                                ; value error, which reads as though the
                                ; operator typed something wrong.

; ERR_COUNT was here, equ $27, "how many are defined". It counted a numbering
; that ran 0 to $26 with no gaps; these numbers are the instrument's and are
; scattered from $00 to $C8, so a count of them means nothing and a bound
; built on one would be wrong. Nothing read it - the whole tree was searched.
;
; THESE NUMBERS ARE A FIRMWARE INTERFACE. The error screen shows the number
; and a service note or a bench engineer looks it up, so they are assigned
; once and never renumbered - inserting one in the middle would silently
; change what every older note means.
;
; They live here, in the file every image includes, and NOT in errors.s. A
; second set was written there once, with different names for six of the same
; conditions; lwasm refused the duplicate, which is the whole reason this
; project assembles everything twice.

; --- the remote-control interface, shared between the images ---------------
; What a parsed bus value commits to. remote.s (A2U12) sets and consumes
; these; the tone and digital screens (pages 1 and 2) set RK_SEQPOS/RK_SEQEND
; when they take SEQP/SEQE, so the codes have to be visible on both sides.
RK_NONE         equ     0
RK_FREQ         equ     1               ; FRA-FRD: freq_set on the channel
RK_AMPL         equ     2               ; APA-APD: ampl_set
RK_PHASE        equ     3               ; PHA-PHD: phase_set
RK_WAVE         equ     4               ; WFA-WFD: wave_program
RK_DEST         equ     5               ; DEA-DED: destn_apply
RK_HOPFREQ      equ     6               ; FRH: the hop slot's frequency
RK_HOPAMPL      equ     7               ; APH: its amplitude
RK_HOPPHASE     equ     8               ; PHH: its phase
RK_OUTPUT       equ     9               ; OO n: output on/off target
RK_SERIAL       equ     10              ; ST_ID: the serial number itself
RK_SEQPOS       equ     11              ; SEQP: a sequence position
RK_SEQEND       equ     12              ; SEQE: a sequence end
RK_OPTIONS      equ     13              ; ST_OP: the installed-options byte
RK_SAVE         equ     14              ; SV: the next number is the register
                                        ; to save the setting into (0-11)
RK_RECALL       equ     15              ; RC: the next number is the register
                                        ; to recall (0-11)
RK_TIME         equ     17              ; STON and STOF: the next number, with
                                        ; a unit, is the selected sequence
                                        ; time. Group 5 of
                                        ; unit_allowed_for_group ($A65A) -
                                        ; seconds and milliseconds and nothing
                                        ; else
RK_TONE         equ     16              ; HRA: the tone number field is armed.
                                        ; A bare number goes into it and is NOT
                                        ; committed; a number with any unit
                                        ; commits, 0-15, and the field stays
                                        ; armed for the next
RK_SREMASK      equ     18              ; SM: the next number is the
                                        ; service-request-enable mask, 0-255.
                                        ; The stock's SM ($9982 record ->
                                        ; cmd_sm_post_0e $9C79) posts request
                                        ; $0E; its arm key_arm_enter_a23f_mode
                                        ; ($8E81) arms a CLASS-0 numeric entry
                                        ; (start_numeric_entry_a23f $A2E4 ->
                                        ; begin_numeric_entry $A415 with both
                                        ; arguments 0, so $238D = $238B = 0) and
                                        ; installs entry_key_handler_addr_set
                                        ; ($A23F) at $220D. That handler hands
                                        ; the number to gpib_address_set
                                        ; ($9D73), which - despite its name -
                                        ; does STB >$227E. NOTHING ON THAT PATH
                                        ; TOUCHES THE DISPLAY
; TWO PARALLEL PORTS BOTH TOOK 18, from branches with different bases, and
; the assembler would not have said so - a duplicate equ is legal and
; the second wins. RK_SREMASK was landed first and its number is in a
; built image, so RK_HOPADDR moved to 20. RK_HOPROW is 19.
RK_HOPADDR      equ     20              ; HRA on the Channel Configuration
                                        ; chain, which is a DIFFERENT field
                                        ; from the tone screen's: request $27
                                        ; reaches l60e7 there ($2215 = $0012,
                                        ; the Hop Ram Adrs stop) and arm [38]
                                        ; on the tone screen. Same one-shot
                                        ; shape as RK_TONE - a bare number is
                                        ; held, a number with ANY unit commits,
                                        ; and the field stays armed. Driven on
                                        ; the stock 2026-09-13, Hop Ram record:
                                        ; 'HRA 3;' leaves $24F4 at $0F,
                                        ; 'HRA 3 HZ;' makes it $0C, a bare
                                        ; '5 KZ;' after it makes it $0A with no
                                        ; second HRA, and 'HRA 15 DG;' and
                                        ; 'HRA 0 VL;' both commit
RK_DIGBIT       equ     21              ; RUNM on Digital Sequence: the next
                                        ; number is the bit number, 1-based -
                                        ; msg_stop_and_select_bit ($6CF0) arms
                                        ; the Bit field and enter_bit_index
                                        ; ($4DE1) commits it
RK_TONEAMPL     equ     22              ; DAPH/DAPL and APA-APD on the tone
                                        ; screens: key_select_amptd ($4D47)
                                        ; arms the AMPTD field, a bare number
                                        ; is held, and a volts unit posts $23
                                        ; to commit_amptd_value ($630C)
RK_DIGLEVEL     equ     23              ; APA/APB and DAPH/DAPL on Digital
                                        ; Sequence: msg_select_level_by_index
                                        ; ($6C8D) arms the On or Off level and
                                        ; a volts unit posts $23 to
                                        ; enter_level_value ($4CDA)
RK_FILTER       equ     24              ; FS n: filter_screen_show's remote
                                        ; leg calls begin_numeric_entry (7, 0),
                                        ; and field kind 7 is the only one
                                        ; scale_table_f014 ($F014) lets SH, LO
                                        ; and AU ($12-$14) into
RK_TONEFREQ     equ     25              ; FRA-FRD and FRH on the tone record:
                                        ; freq_key ($4D02) and key_freq_field
                                        ; ($4EED) arm the FREQ entry, a bare
                                        ; number is held, and a Hz or kHz unit
                                        ; posts $23 to commit_entry_to_field
RK_HOPROW       equ     19              ; AHR FHR PHR DPE: one of the four rows
                                        ; of the hop On/Off page is armed and
                                        ; the next ON or OF switches it. The
                                        ; stock's $2B arm l6100 calls
                                        ; begin_entry_hop_address ($4908),
                                        ; which puts the sub-code $2219 in
                                        ; $3B80 and arms arm_mode_toggle_editor
                                        ; ($509F) - a field that takes no
                                        ; digits, only the choice $221F

; A bus-only request delivered to a screen handler: the stock's request code
; with bit 7 set, so it can never collide with a key code (1..55).
; --- rmt_flags bits, which remote.s sets and the paged screens read --------
; RF_REMOTE is the instrument's own remote state - bit 3 of event_flags
; ($2204), the bit numeric_entry_key_handler ($B3C2) tests when it ignores
; every panel key but LOCAL, and the bit tone_number_entry_field_geometry
; ($45D3) and enter_tone_number ($640C) read to arm three decimal digits
; instead of one hex character.
RF_REMOTE       equ     $01
RF_LOCKOUT      equ     $02
RF_VALUE        equ     $04             ; a parsed value is ready to commit
RF_NUMBER       equ     $08             ; digits are being collected
RF_MINUS        equ     $10
RF_OVER         equ     $20             ; the mantissa overflowed 24 bits
RF_CLOSING      equ     $40             ; the field was put back by a refused
                                        ; select: it takes the rest of this
                                        ; command's parse, commits nothing, and
                                        ; closes at the terminator (remote.s
                                        ; remote_select)
RF_HELD         equ     $80             ; a closed value outlived its command
                                        ; for a field that needs a unit: the
                                        ; stock's digits left in its entry
                                        ; buffer with $238F still set, which a
                                        ; unit in a later message commits
                                        ; (remote.s remote_commit_no_value)

RMT_RQ          equ     $80

; --- the five service-request weights, from the stock's table d929d ($929D) -
; The enumeration - which index each weight is, which stock site raises it and
; with what error code - is the block at the top of
; hp8904a-rewrite/modules/remote.s and is not repeated here. The EQUATES live
; in this shared file rather than beside that block because two of them are
; raised from PAGED images: the tone and the digital sequence screens report
; bits 2 and 3 through ABI_remote_srq_event, and a paged module cannot see a
; name declared in an A2U12 module.
RMT_SRQ_ERROR   equ     $01     ; any error code; eighteen sites in A2U12
RMT_SRQ_REF_UNLOCK equ  $02     ; the reference loop out of lock, error $0C
RMT_SRQ_SEQ_START equ   $04     ; a sequence output started, error $00FF
RMT_SRQ_SEQ_END equ     $08     ; and finished, error $00FF
RMT_SRQ_FAULT_LINE equ  $10     ; the reverse-power relay tripped, error $0D

; THE CODE BOTH SEQUENCE EVENTS CARRY. All four stock sites push #$00FF as
; report_error_and_pulse_status_bit ($9DD3)'s 16-bit code argument, and $9DD3
; skips its $23DE last-error store for exactly that value - CMPX #$00FF /
; LBEQ $9DEB - so the event IS the report and no error number is recorded on
; the error screen. gpib_set_condition ($9B60) then passes the LOW byte of
; that argument on, LDB 9,S, and the low byte is what status_bit_write
; ($9743) puts in the per-event value store. Hence $FF here, not $00FF.
RMT_SRQ_SEQ_CODE equ    $FF

; --- sequence and hop-table sizes, shared ----------------------------------
; These lived beside the screens that own the tables (page0_hop.s,
; page1_tone.s, page2_digital.s). remote.s in A2U12 bounds SEQP/SEQE and the
; hop-slot commands against them, so they moved here where every image sees
; one definition.
HOP_SLOTS       equ     16              ; how many steps a hop table holds

; WHICH FIELD OF A HOP SLOT, and these four live HERE rather than in
; page0_hop.s because both images name them now. remote.s tells page 0 which
; ceiling to apply to a bus-set value (FRH or APH) by writing one of these
; into rmt_mode_code, and remote.s is resident while page0_hop.s is page 0 -
; a symbol two images need is either duplicated or shared, and a duplicated
; field code is two numberings waiting to disagree.
;
; The first three are the fields a slot really has: the read-through of the
; stock's hop record found fifteen bytes with an amplitude at +7 and a phase
; at +11, and HOP_ENTRY_SIZE below names the four sites that establish them.
; The fourth is NOT in the slot - it is the hop RAM's standing address, DDS
; register $15, which slot the chip sits on between programming writes; the
; stock keeps it on the Hop Ram screen at $429D as the 'Hop Ram Adrs' row.
HOP_FIELD_FREQ  equ     0
HOP_FIELD_AMPL  equ     1
HOP_FIELD_PHASE equ     2
HOP_FIELD_ADDR  equ     3
; A TONE SEQUENCE IS TWO SIZES, not one, since the stock's model was ported on
; 2026-09-07. A sequence is a PLAYLIST of up to 250 steps, and each step names
; one of SIXTEEN TONES; the tone owns the frequency and both durations.
;
; They live here rather than in page1_tone.s because page 1 is not the only
; image that needs them: remote.s and registers.s are in A2U12 and cannot see
; a constant declared on a paged screen.
; THE SEQUENCE TIMES' OWN LIMITS, shared because the bus commits a time as
; well as the screen and both meet them. validate_gate_time ($6033) loads
; $0050 = 80 counts, or $0064 = 100 while $3C03 says the DTMF screen is
; editing, and refuses anything below it with error $32; the ceiling is the
; sixteen-bit count itself, 655.35 ms.
TONE_FIELD_ON_R equ     1               ; page1_tone.s's TONE_FIELD_ON and
TONE_FIELD_OFF_R equ    2               ; TONE_FIELD_OFF, which remote.s reads
                                        ; to see which time the bus armed
TONE_TIME_MIN   equ     80
TONE_TIME_MIN_DTMF equ  100
TONE_MS_MAX     equ     655
TONE_TIME_SIZE_R equ    4               ; bytes per tone in tone_times, the
                                        ; stock's $3C10 stride
TONE_ON_R       equ     0               ; the On time's offset in that record
TONE_OFF_R      equ     2               ; and the Off time's
TONE_MS_COUNTS  equ     100             ; ten-microsecond timer counts in one
                                        ; millisecond. The sequence timer's
                                        ; tick is 10 us, which is why the
                                        ; stock's own screen shows a time to
                                        ; two decimal places - "On Time
                                        ; 500.00ms" is 50,000 counts.
                                        ;
                                        ; Declared here rather than in
                                        ; page1_tone.s because the register
                                        ; conversion in registers.s needs it
                                        ; and A2U12 cannot see a paged image's
                                        ; equates.
TONE_TONES      equ     16              ; tones in the list, each with its own
                                        ; 24-bit frequency and On/Off times.
                                        ; Four bits a step, so this is what a
                                        ; nibble holds and it cannot grow.
TONE_PLAYLIST   equ     250             ; steps in the playlist. seq_put_nibble
                                        ; ($452D) refuses an index at or above
                                        ; $00FA, which is this, and
                                        ; seq_data_init ($79FE) sets its Seq
                                        ; End to $00F9.
                                        ;
                                        ; NOT A POWER OF TWO, so an index into
                                        ; the playlist is bounded with a
                                        ; compare, never masked. The tone
                                        ; NUMBER is masked, because sixteen is.
; THE SIXTEEN-STEP DIGITAL SEQUENCE IS GONE, and with it DIGITAL_BITS and
; DIGITAL_STEPS - eight bits per byte and sixteen bytes. That was the
; rewrite's own model. The instrument's is one 1000-bit stream in 125 bytes
; (DIGITAL_PATTERN_BYTES in common/ram.inc), cut into 1000, 333 or 250 digits
; by the base, which is what set_max_length_for_base ($56A3) installs.

; WHERE build.py PUTS EACH IMAGE'S COMPENSATION BYTE: seventeen below the top,
; the last byte that is neither code nor a vector. balance_checksum computes
; it as `spot = target - COMP_BYTE_BACK` for every one of the five, so A2U12's
; is at $FFEF and a page's at PAGE_WINDOW+PAGE_SIZE-COMP_BYTE_BACK.
;
; WHAT IT IS CHOSEN TO MAKE TRUE is the instrument's own test and not a
; uniform zero: the plain byte sum of A2U12 must come to 1 and the plain byte
; sum of page N to N+1, because rom_checksum ($DCA9) leaves the sum LESS ONE
; in B and compares it against zero for A2U12 and against the page index for a
; page. selftest_rom's header derives that from the six instructions and names
; the measurements. The stock's own spots are $EA14 for A2U12 and $4001 for
; each page; both are occupied in this rewrite, whose layout the architect
; freed on 2026-01-01, and build.py refuses to place the byte anywhere that is
; not still $FF padding when it gets there.
;
; Named rather than written as $3FEF because tests/test_ram_writers.py refuses
; a NUMBER in $2000-$3FFF anywhere in the source, and it is right to: every
; other guard on the per-unit bytes matches a symbol name, and a literal
; defeats all of them. This one is an offset into a ROM image and not a RAM
; address at all, but the gate cannot tell the two apart and should not have
; to.
PAGE_SIZE       equ     $4000           ; one A2U13 page
COMP_BYTE_BACK  equ     17              ; how far below the top it sits
