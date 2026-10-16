; ===========================================================================
; entry.s - numeric entry fields
;
; Every screen that takes a number from the operator uses this: the serial
; number, an option bit, a memory address on the service screens, a register
; value. One field implementation rather than one per screen, which is what
; the stock firmware has.
;
; A field is: a buffer of digits, a maximum width, and a base. Decimal for
; the serial number and ordinary values, hexadecimal for the raw memory and
; register screens where the operator is reading a data sheet, not a display.
;
; NOTHING IS REFUSED WHILE IT IS BEING TYPED. Digits go in and can be taken
; out again; the value is only checked when ENTER is pressed, and by the
; caller, not here. A field that rejects keystrokes as they arrive cannot be
; corrected without starting again, and the stock firmware's serial screen -
; which refuses the whole entry unless the CURRENT value is factory-virgin -
; is what that thinking leads to.
; ===========================================================================

; (these constants are in common/display.inc, common/formats.inc)

; ---------------------------------------------------------------------------
; entry_begin - start a new field
;
;   entry: A = the base, ENTRY_DECIMAL or ENTRY_HEX
;          B = how many digits it holds, up to ENTRY_MAX
;   uses:  A, B, X
; ---------------------------------------------------------------------------
entry_begin
                ; NOT WHILE THE CONTROLLER HAS THE INSTRUMENT. arm_numeric_
                ; entry_field ($AC35) masks REMOTE out of event_flags at $AC44
                ; and, with it set, calls begin_numeric_entry ($A415) and
                ; LEAVES at $AC7E - past $AC87 STB >$23A8 and past the cursor
                ; at $ACA6. So a field armed over the bus takes no panel digit
                ; once the panel is back. This armed it anyway: 'IS;' on ch C,
                ; REN released, then '5' opened an entry the instrument
                ; refuses.
                pshs    a
                lda     >rmt_flags
                bita    #RF_REMOTE
                puls    a
                bne     entry_begin_buffer
                pshs    b                       ; THE WIDTH IS IN B and this
                ldb     #$01                    ; must not eat it.
                stb     >entry_armed            ; A FIELD IS ARMED FROM HERE:
                puls    b                       ; the controller taking the
                                                ; instrument remote ends the
                                                ; edit, and until a field key
                                                ; arms another one a digit does
                                                ; nothing - entry_armed in
                                                ; common/ram.inc carries the
                                                ; driven evidence
                ; THE CURSOR IS NOT THIS ROUTINE'S. It was turned on here, and
                ; this routine runs when a buffer is emptied - on the first
                ; digit on the channel screen, twice over on the hop screen,
                ; and while the instrument is remote - none of which is when
                ; the instrument shows one. entry_cursor_on below is the
                ; stock's moment, and every screen calls it where its own arm
                ; reaches arm_numeric_entry_field ($AC35).
entry_begin_buffer                              ; $A415's half: the buffer
                sta     >entry_base
                cmpb    #ENTRY_MAX
                bls     entry_begin_width
                ldb     #ENTRY_MAX              ; clamp rather than refuse
entry_begin_width
                stb     >entry_width
                clr     >entry_count
                ldx     #entry_buffer
                ldb     #ENTRY_MAX
entry_begin_clear
                clr     ,x+
                decb
                bne     entry_begin_clear

                ; AND NO UNITS FIELD UNLESS THE SCREEN DECLARES ONE. A field
                ; that says nothing blanks nothing, so a screen that has not
                ; been given its columns cannot blank a run it does not own.
                clr     >entry_units_w
                clr     >entry_dot              ; and no decimal point yet
                clr     >entry_frac
                rts

; ===========================================================================
; The cursor over an entry field: on when a field is armed, off when it ends
;
; THE INSTRUMENT HAS EXACTLY TWO MOMENTS AND THIS FIRMWARE HAS THE SAME TWO.
; lcd_display_control ($D7BE) is the only writer of the display-control
; shadow $242A after lcd_init's seed (lcd_init $D9E6, at $D9FC LDB #$0C /
; $D9FE STB >$242A), and it has two call sites in the whole of A2U12:
;
;   $ACA6  inside arm_numeric_entry_field ($AC35), passing 0 - arm [0] of the
;          table dd811 at $D811, arm_lcd_cursor_on, OR $02: CURSOR ON
;   $B3BA  inside entry_exit_restore_display ($B38B), passing 1 - arm [1],
;          lcd_cursor_off, AND $FD: CURSOR OFF
;
; Arms 2 to 5 (blink on and off, display on and off) are selected by nothing,
; so the byte is only ever $0C or $0E and the blink bit is never set.
;
; AND THE CURSOR BIT IS $23A8. The stock's "an entry field is armed" flag has
; exactly two writers as well - grep of firmware/src-generated/*.s for $23a8
; finds STB >$23a8 at $AC89 and CLR >$23a8 at $B394 and nothing else - and
; they sit in the same two routines: $AC89 on the same local path as $ACA6, and
; $B394 at the head of the routine whose tail is $B3BA. So on the instrument
; the cursor is on exactly when $23A8 is set, and numeric_entry_key_handler's
; tests of $23A8 at $B448 and $B478 are tests of the cursor bit. entry_key_exit
; reads the bit for that reason: it is the same state, and this firmware's own
; entry_armed does not track $23A8 at every exit - what it does track is
; written over its declaration in hp8904a-rewrite/common/ram.inc.
;
; WHERE THE STOCK TURNS IT OFF, all six, and where each is here:
;   $9F1A  enter_remote_state ($9EB9): the controller takes the instrument -
;          remote.s, at the remote edge
;   $B45C  numeric_entry_key_handler ($B3C2): a key key_to_state_code ($AD4D)
;          maps, while $23A8 is set - entry_key_exit, from the foreground
;   $B48C  the same for keymap_menu_msgs_19_1d ($AEBB) - entry_key_exit
;   $B586  a digit accepted that check_entry_terminator ($B070) says ends the
;          entry - the screen that commits it
;   $B5BA  a units key or ENTER accept_units_key ($B0C1) takes - the screen
;          that commits it
;   $4F3B  page 0's entry_cfg_unsettable ($4F27), an AMPTD whose unit takes
;          no value - page0_screen.s
; and it goes on wherever a screen's arm reaches $AC35 from the panel.
; ===========================================================================

; ---------------------------------------------------------------------------
; entry_cursor_on - the cursor comes on over a field armed from the panel
;
;   entry: A = the DDRAM address of the field's first digit
;   uses:  A
;
; arm_numeric_entry_field ($AC35) from $AC81: CLR >$23a6, CLR >$23a7, $AC87
; LDB #$01 / $AC89 STB >$23a8, then lcd_set_cursor ($D7A0) with $23AD - the
; value position each arm passes as its third word - at $AC98, then
; lcd_display_control ($D7BE) with 0 at $ACA6. lcd_set_cursor ORs its
; argument with $80 and writes it as an instruction, so $23AD is a DDRAM
; address and lcd_cursor is that routine.
;
; NOT WHILE REMOTE. $AC5C LDD >event_flags / $AC61 ANDB #$08 / $AC67 LBEQ
; lac81 takes the cursor path only with bit 3 clear; with it set the routine
; calls begin_numeric_entry ($A415) at $AC79 and leaves at $AC7E, so a field
; the controller selects moves no cursor and shows none. RF_REMOTE is that
; bit here (hp8904a-rewrite/common/formats.inc), which is how
; tone_entry_armed already decides the same thing about entry_armed.
; ---------------------------------------------------------------------------
entry_cursor_on
                pshs    a
                lda     >rmt_flags
                bita    #RF_REMOTE
                puls    a                       ; PULS leaves CC alone
                bne     entry_cursor_on_remote
                lbsr    lcd_cursor              ; $AC98 lcd_set_cursor($23AD)
                lda     #LCD_CURSOR_BIT         ; $ACA6 lcd_display_control(0)
                lbra    lcd_control_set         ; tail call: its RTS is ours
entry_cursor_on_remote
                rts

; ---------------------------------------------------------------------------
; entry_cursor_off - the entry has ended: the cursor goes off
;
;   uses:  A
;
; entry_exit_restore_display ($B38B) at $B3B1: LDU #$0001 / PSHS Y,U / $B3BA
; LBSR lcd_display_control, arm [1], $242A AND $FD. UNCONDITIONAL - nothing
; before it is tested, so a cursor already off is written off again, and
; enter_remote_state ($9EB9) calls the routine at $9F1A on every remote edge
; whether or not an entry was open. Measured on the stock in the emulator: a
; $0C goes out at every REN assertion, cursor showing or not.
; ---------------------------------------------------------------------------
entry_cursor_off
                lda     #LCD_CURSOR_BIT         ; $B3BA lcd_display_control(1)
                lbra    lcd_control_clear       ; tail call: its RTS is ours

; ---------------------------------------------------------------------------
; entry_is_open - is an entry field armed from the panel?
;
;   exit:  Z CLEAR when one is, Z SET when none is
;   uses:  nothing - A comes back as it went in, and so does every register
;          but CC
;
; The stock's $23A8 test, which numeric_entry_key_handler ($B3C2) makes three
; times: at $B448 and $B478 before it ends an entry for a mapped key, and at
; lb494 ($B494 LDB >$23a8 / CMPB #$00 / LBNE lb4b0) before it offers a key to
; entry_backspace, keypad_char_column_select and accept_units_key - with $23A8
; clear it beeps error 1 at $B49D and nothing is taken. So no digit, point,
; sign, BACKSPACE, units key or ENTER reaches a field that is not armed.
;
; THE CURSOR BIT IS THAT FLAG, as the banner above sets out: $23A8 and bit 1
; of $242A are written together and only together, so reading the shadow is
; reading $23A8. A screen that answers lb494 asks here, and then its answer
; and its cursor cannot disagree.
; ---------------------------------------------------------------------------
entry_is_open
                pshs    a
                lda     >lcd_control
                bita    #LCD_CURSOR_BIT
                puls    a                       ; PULS leaves CC alone
                rts

; ---------------------------------------------------------------------------
; entry_key_exit - a key the instrument's keymap maps ends the open entry
;
;   entry: B = the key code, as the panel produced it
;   uses:  A - B and X come back as they went in
;
; numeric_entry_key_handler ($B3C2), the routine every panel key goes through
; (the LBSR at $87AD), offers the key to key_to_state_code ($AD4D) at $B43D
; and then to keymap_menu_msgs_19_1d ($AEBB) at $B46D. Each POSTS its request
; and returns 1 for a key it maps, and on either 1 the handler tests $23A8
; ($B448 LDB >$23a8 / CMPB #$00 / LBEQ, and $B478 the same) and, set, calls
; entry_exit_restore_display ($B38B) with 1 ($B45C, $B48C) - BEFORE the
; posted request is serviced. $B38B repaints both lines from the shadow and
; then turns the cursor off (docs/entry-exit-port.md), and a screen that
; answers the request by arming a field turns it on again after: the $0C and
; then the $0E, which is what the instrument sends for a field key pressed
; over an open field.
;
; The caller is the foreground, for PANEL keys only: the bus's key
; equivalents post their requests without passing $B3C2, and the Keyboard
; Check's keys are handed to [$23B0] at the head of $B3C2 before either
; mapper is asked.
; ---------------------------------------------------------------------------
entry_key_exit
                lda     >lcd_control            ; $B448/$B478: $23A8, which is
                bita    #LCD_CURSOR_BIT         ; this bit - see the banner
                beq     entry_key_exit_done
                bsr     entry_key_is_mapped     ; $B434 / $B464
                beq     entry_key_exit_done
                pshs    b,x                     ; B IS THE KEY, and the caller
                                                ; acts on it after this
                                                ; returns (boot.s
                                                ; foreground_key_panel);
                                                ; lcd_repaint uses A, B and X
                lbsr    lcd_repaint             ; $B39F: lcd_repaint_shadow,
                                                ; both lines from the shadow -
                                                ; which the echo never entered
                                                ; - so an abandoned entry goes
                                                ; and the counter ends at $00
                puls    b,x
                bra     entry_cursor_off        ; $B45C / $B48C: $B3B1, cursor
                                                ; off
entry_key_exit_done
                rts

; ---------------------------------------------------------------------------
; entry_key_is_mapped - does key_to_state_code or keymap_menu_msgs_19_1d take
;                       this key?
;
;   entry: B = the key code
;   exit:  Z CLEAR when one of them maps it - the key posts a request and a
;          screen hears it as one; Z SET when neither does
;   uses:  nothing - every register but CC comes back as it went in
;
; The table below, and the two range tests in front of it: $AE2A CMPX #$0034
; / $AE2D BGT sends every code above $34 to keymap_unmapped_return0, and
; $AEF8-$AF11's compares name nothing above $2A. A screen whose stock handler
; re-arms after every message it is sent - the service screens do - asks this
; to tell a key that reached it as a message from one numeric_entry_key_handler
; ($B3C2) kept for itself.
; ---------------------------------------------------------------------------
entry_key_is_mapped
                cmpb    #KEY_CODE_MAX           ; $AE2A / $AE2D
                bhi     entry_key_is_mapped_no
                pshs    b,x
                ldx     #entry_key_mapped
                abx
                tst     ,x                      ; Z set for a zero byte
                puls    b,x                     ; PULS leaves CC alone
                rts
entry_key_is_mapped_no
                orcc    #CC_ZERO                ; above $34: not mapped
                rts

; WHICH CODES THE TWO MAPPERS TAKE, one byte per key code 0 to $34. Read out of
; the stock, not inferred from the key names: key_to_state_code ($AD4D)
; dispatches code-1 through the 52-word table dae3d at $AE3D ($AE31 SUBD
; #$0001 / $AE3B JMP [D,X]), and every arm but keymap_unmapped_return0
; ($AE22 CLR 4,S) loads a request, joins laea5 ($AEA5) - post_request_code,
; then LDB #$01 - and returns 1. The indices that are keymap_unmapped_return0
; are 2-6, 8-11, 14-17, 20-23, 26-30, 32-35 and 41: codes 3-7, 9-12, 15-18,
; 21-24, 27-31, 33-36 and $2A. Of those, keymap_menu_msgs_19_1d ($AEBB) maps
; 3, 4, 5, 6 and $2A ($AEF8-$AF0F) and joins laf13 ($AF13) to post and return
; 1. Codes 0, 7, $35 and $36 never reach either: $B406-$B42A send them to
; lb431 before $B434.
entry_key_mapped
                fcb     0               ; $00 KEY_NONE     dropped at $B416
                fcb     1               ; $01 LOCAL        dae3d[0]  request $01
                fcb     1               ; $02 f1           dae3d[1]  request $13
                fcb     1               ; $03 PHASE        $AEF8     request $1C
                fcb     1               ; $04 WAVE FORM    $AEFD     request $1B
                fcb     1               ; $05 AMPTD        $AF02     request $1A
                fcb     1               ; $06 FREQ         $AF07     request $19
                fcb     0               ; $07 shift        dropped at $B40C
                fcb     1               ; $08 f2           dae3d[7]  request $14
                fcb     0               ; $09 -            unmapped
                fcb     0               ; $0A 7            unmapped
                fcb     0               ; $0B 4            unmapped
                fcb     0               ; $0C 1            unmapped
                fcb     1               ; $0D INC SET      dae3d[12] request $1E
                fcb     1               ; $0E LAST         dae3d[13] request $18
                fcb     0               ; $0F 0            unmapped
                fcb     0               ; $10 8            unmapped
                fcb     0               ; $11 5            unmapped
                fcb     0               ; $12 2            unmapped
                fcb     1               ; $13 UP           dae3d[18] request $20
                fcb     1               ; $14 NEXT         dae3d[19] request $17
                fcb     0               ; $15 .            unmapped
                fcb     0               ; $16 9            unmapped
                fcb     0               ; $17 6            unmapped
                fcb     0               ; $18 3            unmapped
                fcb     1               ; $19 DOWN         dae3d[24] request $1F
                fcb     1               ; $1A f3           dae3d[25] request $15
                fcb     0               ; $1B ENTER        unmapped
                fcb     0               ; $1C deg          unmapped
                fcb     0               ; $1D Hz           unmapped
                fcb     0               ; $1E kHz          unmapped
                fcb     0               ; $1F BACKSPACE    unmapped
                fcb     1               ; $20 f4           dae3d[31] request $16
                fcb     0               ; $21 spare 0      unmapped
                fcb     0               ; $22 spare 1      unmapped
                fcb     0               ; $23 spare 2      unmapped
                fcb     0               ; $24 spare 3      unmapped
                fcb     1               ; $25 shift FREQ   dae3d[36] request $12
                fcb     1               ; $26 shift PHASE  dae3d[37] request $0F
                fcb     1               ; $27 shift LOCAL  dae3d[38] request $02
                fcb     1               ; $28 shift AMPTD  dae3d[39] request $0C
                fcb     1               ; $29 shift f1     dae3d[40] request $03
                fcb     1               ; $2A shift WAVE   $AF0C     request $1D
                fcb     1               ; $2B shift INC    dae3d[42] request $10
                fcb     1               ; $2C shift NEXT   dae3d[43] request $04
                fcb     1               ; $2D shift DOWN   dae3d[44] request $21
                fcb     1               ; $2E shift LAST   dae3d[45] request $05
                fcb     1               ; $2F shift UP     dae3d[46] request $22
                fcb     1               ; $30 shift BKSP   dae3d[47] request $06
                fcb     1               ; $31 shift f3     dae3d[48] request $11
                fcb     1               ; $32 shift f2     dae3d[49] request $37
                fcb     1               ; $33 shift f4     dae3d[50] request $38
                fcb     1               ; $34 shift ENTER  dae3d[51] request $26

; ---------------------------------------------------------------------------
; entry_point - the decimal point key
;
;   exit:  carry CLEAR if it was taken; carry SET if this field already has
;          one, which is the stock's rejected key
;   uses:  A
;
; Column 7 of keypad_char_table ($EF94) - the column entry mode 3 selects -
; holds '.' beside the ten digits, so any unsigned-decimal field takes one.
; What it does is not stored as a character: entry_to_scaled_digits ($CDE1)
; scales the digits by the unit's decades LESS the number that followed the
; point, which is what entry_frac counts. A second point is refused, as a
; second one has no meaning.
; ---------------------------------------------------------------------------
entry_point
                tst     >entry_dot
                bne     entry_point_refused
                lda     #$01
                sta     >entry_dot
                pshs    b                       ; B kept: this says A only
                lbsr    entry_units_blank       ; AN ACCEPTED KEY, so the units
                puls    b                       ; go now - $B516-$B538 run for
                andcc   #~CC_CARRY              ; the point as for a digit.
                rts
                                                ; Driven on the stock: point
                                                ; on PHASE turns 'PHASE   0.0
                                                ; deg' into 'PHASE .', and
                                                ; this left the 'deg' up
                                                ; until a digit came
entry_point_refused
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; entry_units - where this field's units label is, and how much of it goes
;
;   entry: A = the DDRAM column, B = how many characters
;   uses:  nothing
;
; THE FIRST ACCEPTED KEY BLANKS THE UNITS. That is what the instrument does:
; open_entry_field_from_locals ($AC35) takes the units column as argument 5
; into $23AF ($AC55) and the units class as argument 4 into $23AB ($AC42),
; and the eight arms of the switch at $AD3A turn that class into a width in
; $23AE - classes 0, 1 and 2 give zero ($AD21 CLR >$23AE), 3 and 6 give three
; ($AD09 LDB #$03), 4 and 5 give two ($AD11 LDB #$02) and 7 gives one ($AD19
; LDB #$01). $B524-$B538 then writes that many blanks from $ED11 at that
; column the FIRST time a key is accepted, guarded by the $23A7 flag tested at
; $B516.
;
; Driven on the stock, 2026-09-10: typing into the Hop Ram FREQ field turns
; ' FREQ *      0.0  Hz*' into ' FREQ * 1234567     *' - the three characters
; of ' Hz' at $24 gone - and typing into its AMPTD field blanks the two at
; $4E. This firmware left the old unit standing beside the new digits, so a
; frequency being typed in kHz was shown against the Hz label the last commit
; had left there.
;
; WIDTH ZERO AFTER THE BLANK, which is the $23A7 flag folded into the width:
; the run is written once and the screen's next arming declares it again.
; ---------------------------------------------------------------------------
entry_units
                sta     >entry_units_at
                stb     >entry_units_w
                rts

; ---------------------------------------------------------------------------
; entry_digit - add one digit
;
;   entry: B = the digit value, 0 to base-1
;   exit:  carry set if it was not accepted (field full, or out of range)
;   uses:  A, B, X
;
; A full field ignores further digits rather than scrolling. Scrolling would
; silently drop the most significant digit of a serial number the operator
; had just typed correctly.
; ---------------------------------------------------------------------------
entry_digit
                cmpb    >entry_base
                bhs     entry_digit_reject      ; not a digit in this base
                lda     >entry_count
                cmpa    >entry_width
                bhs     entry_digit_reject      ; full
                ldx     #entry_buffer
                lda     >entry_count
                leax    a,x
                stb     ,x
                inc     >entry_count
                tst     >entry_dot              ; AFTER THE POINT? then this
                beq     entry_digit_units       ; digit is a fraction of the
                inc     >entry_frac             ; unit, and the scaling owes it
                                                ; one decade
entry_digit_units
                lbsr    entry_units_blank
                andcc   #~CC_CARRY
                rts

; entry_units_blank - THE UNITS GO ON THE FIRST ACCEPTED KEY, $B524-$B538's
; blank run. Only on the first: the width is zeroed here, which is what the
; stock's $23A7 flag does.
;
;   uses:  A, B - X is kept
entry_units_blank
                ldb     >entry_units_w
                beq     entry_units_blank_done
                clr     >entry_units_w
                pshs    x
                lda     >entry_units_at
                ldx     #entry_units_blanks
                lbsr    lcd_write_raw           ; glass only: $B524-$B538
                                                ; write it with
                                                ; lcd_write_string_at, so the
                                                ; unit is still in the shadow
                                                ; for the exit's repaint
                puls    x
entry_units_blank_done
                rts

entry_units_blanks
                fcc     "    "                  ; FOUR, and the fourth is not
                                                ; spare. Three is the widest
                                                ; run the stock's units classes
                                                ; ask for ($AD09 LDB #$03), but
                                                ; the FM stereo screen the
                                                ; architect ordered has a
                                                ; four-character unit field of
                                                ; its own (STF_UNIT_LEN), and a
                                                ; run longer than this string
                                                ; would write whatever follows
                                                ; it onto the glass.
entry_digit_reject
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; entry_backspace - remove the last digit
;
;   exit:  carry set if there was nothing to remove
;   uses:  A, X
;
; THE STOCK'S entry_backspace ($B2CD), for its kinds 0, 1 and 3 ($B366-$B37E
; send all three to $B2E9): the head index $23A4 steps back one unless it is
; already zero ($B2E9-$B2FD), and the vacated cell of the buffer $239A takes
; a space ($B312-$B31F). The buffer here holds digit VALUES rather than
; characters and the count is the head, so the vacated cell is cleared. On
; an empty buffer the stock leaves the head at zero and returns 1 all the
; same ($B2FD CLR >$23A4, $B382); this leaves the count at zero and says so
; with the carry, which no caller needs - each repaints either way, as
; $B4D0-$B501 repaints.
;
; THE POINT IS A CELL TOO, and it is the last one when no digit has followed
; it. The stock's buffer holds the '.' as a character, so BACKSPACE after
; '.6' takes the 6 and leaves '.', and a second takes the point and clears
; its flag $23A6 ($B30C). Here the point is entry_dot and its place is
; entry_frac digits from the end: a digit after the point is removed with
; entry_frac, and with none after it the point itself goes. This removed a
; digit and left entry_frac counting it, so '.6' then BACKSPACE showed
; nothing at all where the instrument shows '.'.
;
; What is NOT here, because the sign is not in this buffer: the kind-2 rule
; ($B320-$B35D), under which a signed field steps back only while a digit
; follows the sign ($B320 CMPB #$01 / LBLS) and otherwise puts '+' back at
; the head ($B351-$B35A). A signed entry's sign lives with the screen that
; keeps it - chan_entry_sign, hop_entry_sign - so that rule is the screen's
; BACKSPACE arm's, applied before it calls here: chan_backspace_key in
; page0_screen.s, hop_backspace_key in page0_hop.s. Paged screens reach this
; through ABI slot 73.
; ---------------------------------------------------------------------------
entry_backspace
                tst     >entry_dot              ; a point with nothing after
                beq     entry_backspace_digit   ; it is the last cell
                tst     >entry_frac
                bne     entry_backspace_frac
                clr     >entry_dot              ; $B30C: the point goes
                andcc   #~CC_CARRY
                rts
entry_backspace_frac
                dec     >entry_frac             ; a fraction digit goes, and
entry_backspace_digit                           ; the point stays where it was
                lda     >entry_count
                beq     entry_backspace_empty
                deca
                sta     >entry_count
                ldx     #entry_buffer
                leax    a,x
                clr     ,x
                andcc   #~CC_CARRY
                rts
entry_backspace_empty
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; entry_value - the digits so far, as a 24-bit value
;
;   exit:  the value at entry_result, three bytes, most significant first;
;          CARRY SET if the digits do not fit 24 bits
;   uses:  A, B, X, Y, U
;
; result = result * base + digit, for each digit in turn. The multiply is a
; shift-and-add rather than a call to mul16, because the base is 10 or 16 and
; a 24-bit accumulator will not fit the 16-bit multiply anyway.
;
; OVERFLOW IS REPORTED, not wrapped. The field holds eight decimal digits and
; the storage holds 24 bits, which reaches 16,777,215 - so eight digits can
; express numbers that do not fit. Typing 98765432 used to store 14879352,
; the same value modulo 2^24, with nothing said. A serial number quietly
; becoming a different serial number is exactly the class of failure this
; instrument's battery-backed data cannot afford, so every add24 and every
; doubling now propagates its carry out to the caller.
; ---------------------------------------------------------------------------
entry_value
                ldx     #entry_result           ; start from zero
                clr     ,x
                clr     1,x
                clr     2,x
                clr     >entry_index
                clr     >entry_overflow
entry_value_next
                lda     >entry_index
                cmpa    >entry_count
                bhs     entry_value_done

                ; result = result * base, by adding it to itself base-1 times.
                ; Ten or sixteen additions of a three-byte value is small and
                ; obviously correct; a general 24x8 multiply here would be
                ; neither.
                ldx     #entry_scratch
                ldu     #entry_result
                lbsr    copy24                  ; scratch = result
                ldb     >entry_base
                decb                            ; already have one copy
entry_value_times
                pshs    b
                ldx     #entry_result
                ldu     #entry_scratch
                lbsr    add24
                bcc     entry_value_times_ok
                inc     >entry_overflow         ; carried out of bit 23
entry_value_times_ok
                puls    b
                decb
                bne     entry_value_times

                ; ...then add this digit
                ldx     #entry_buffer
                lda     >entry_index
                leax    a,x
                ldb     ,x
                clr     >entry_scratch
                clr     >entry_scratch+1
                stb     >entry_scratch+2
                ldx     #entry_result
                ldu     #entry_scratch
                lbsr    add24
                bcc     entry_value_digit_ok
                inc     >entry_overflow
entry_value_digit_ok

                inc     >entry_index
                bra     entry_value_next
entry_value_done
                lda     >entry_overflow
                beq     entry_value_fits
                orcc    #CC_CARRY               ; too big for 24 bits
                rts
entry_value_fits
                andcc   #~CC_CARRY
                rts

; ---------------------------------------------------------------------------
; entry_render - the field as characters, for the display
;
;   entry: X = where to put them
;   exit:  entry_width characters: the digits typed so far from the first
;          cell, blanks after them out to the width
;   uses:  A, B, X, Y
;
; LEFT-ALIGNED FROM THE FIELD'S FIRST CELL, which is the stock's layout for
; every entry field in the instrument. Its one keystroke handler,
; numeric_entry_key_handler ($B3C2), echoes the whole buffer $239A after each
; accepted key - lcd_write_string_at ($D8A5) with the buffer, the width $23A5
; and the field's column $23AD ($B53D-$B555) - and that buffer was filled
; with spaces as the field was armed ($ACC5-$ACE0) and takes each digit at
; the head index $23A4 ($B055), so the glass shows the digits from the column
; and blanks to the width. The cursor then goes to the cell after the last
; digit, lcd_set_cursor ($D7A0) of $23AD plus $23A4 ($B556-$B56B); that is
; the caller's to place, because only the caller knows the column -
; chan_entry_echo and hop_entry_echo do.
;
; This rendered right-aligned - blanks first, the digits ending in the last
; cell - so the digits walked leftward as they were typed and the field read
; as the stock's only once it was full. Every caller gets the stock's layout
; from this one change: chan_entry_echo (page0_screen.s), hop_entry_echo
; (page0_hop.s), tone_echo_write (page1_tone.s), dtmf_show_echo
; (page1_dtmf.s), digital_key_echo (page2_digital.s), p3_hopram_echo
; (page3_screens.s), cow_key_digit (page3_cowchip.s), screen_numeric_echo
; (screens_main.s), memmap_show (service_memmap.s) and serial_entry_redraw
; (service_serial.s).
; ---------------------------------------------------------------------------
entry_render
                clr     >entry_index
entry_render_next
                lda     >entry_index
                cmpa    >entry_count
                bhs     entry_render_pad

                ; THE POINT GOES WHERE IT WAS TYPED, which is entry_frac digits
                ; from the end of what has been typed so far. Without this the
                ; operator sees '1005' while typing 100 . 5 and has no way to
                ; tell the two apart.
                tst     >entry_dot
                beq     entry_render_digit
                pshs    a
                lda     >entry_count
                suba    >entry_frac
                cmpa    >entry_index
                puls    a
                bne     entry_render_digit
                pshs    a
                lda     #'.'
                sta     ,x+
                puls    a
entry_render_digit
                pshs    x
                ldx     #entry_buffer
                leax    a,x
                ldb     ,x
                puls    x
                lbsr    nibble_to_hex           ; 0-9 and A-F both come out
                sta     ,x+                     ; right for either base
                inc     >entry_index
                bra     entry_render_next
entry_render_pad
                tst     >entry_dot              ; a point typed after the last
                beq     entry_render_blanks     ; digit still shows
                lda     >entry_frac
                bne     entry_render_blanks
                lda     #'.'
                sta     ,x+
entry_render_blanks
                lda     >entry_width
                suba    >entry_count            ; how many blanks follow
                beq     entry_render_done
                tfr     a,b
entry_render_blank
                lda     #' '
                sta     ,x+
                decb
                bne     entry_render_blank
entry_render_done
                rts
