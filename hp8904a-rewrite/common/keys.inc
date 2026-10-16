; ===========================================================================
; keys.inc - the front panel's keys, by the codes the hardware gives them
;
; THESE CODES ARE THE INSTRUMENT'S, NOT THIS FIRMWARE'S. They were read out
; of the stock image and verified against it byte for byte: the 74-byte
; table at $EF4A holds two bytes for each of the 36 matrix positions plus an
; unused position 0, the unshifted code and the shifted one, and the codes
; below are what that table contains.
;
; THIRTY-SIX POSITIONS, FIFTY-TWO CODES, and those are different numbers. The
; table is INDEXED by position, of which there are 36 because the matrix is
; six by six. It CONTAINS codes, of which there are 52 because sixteen keys
; give a different code when shift is held. Reading the bound on the index as
; a bound on the values is an easy mistake and it has been made once, so it
; is spelled out here.
;
; They are kept identical for one reason that matters and one that is merely
; convenient. The one that matters: the Keyboard Check screen prints a name
; for each code, and those names are the only written record of which key is
; which on an instrument whose panel legends this project has never seen. The
; convenient one: anyone comparing this firmware with the stock disassembly
; sees the same numbers.
;
; THE MATRIX. Six columns driven at $0A00, six rows read at $0000, both
; active low. The position is row*6 + col + 1, so position 1 is row 0 column
; 0 and position 36 is row 5 column 5. Position 0 does not exist - a scan
; that finds nothing reports no key rather than position zero, because zero
; would index the first table entry and report a real key.
;
; THE CODES ARE NOT THE POSITIONS AND ARE NOT CONTIGUOUS. Position 31 is the
; digit 1 and position 22 is the digit 0; the ten digits are scattered across
; the matrix in the order the panel lays them out, not the order they count
; in. Anything that wants "is this a digit" must use the table in keymap.s,
; and a range test between the codes for 0 and 9 would accept eleven other
; keys and reject two digits. That range test was written once here before
; the table was read.
;
; SHIFT IS ONE-SHOT. Pressing it sets a latch; the next key decodes through
; the shifted half of the table and clears it. Sixteen keys have a distinct
; shifted code; the other twenty - the digits, the point, minus, the three
; unit keys, shift itself and the four spares - give the same code either
; way, which is why holding shift and typing a number is harmless.
; ===========================================================================

; --- the unshifted codes, 1 to 36 ------------------------------------------
KEY_NONE        equ     0               ; no key: never a table index
KEY_LOCAL       equ     1
KEY_F1          equ     2
KEY_PHASE       equ     3
KEY_WAVEFORM    equ     4
KEY_AMPL        equ     5
KEY_FREQ        equ     6
KEY_SHIFT       equ     7
KEY_F2          equ     8
KEY_MINUS       equ     9
KEY_7           equ     10
KEY_4           equ     11
KEY_1           equ     12
KEY_INC_SET     equ     13
KEY_LAST        equ     14
KEY_0           equ     15
KEY_8           equ     16
KEY_5           equ     17
KEY_2           equ     18
KEY_UP          equ     19
KEY_NEXT        equ     20
KEY_POINT       equ     21
KEY_9           equ     22
KEY_6           equ     23
KEY_3           equ     24
KEY_DOWN        equ     25
KEY_F3          equ     26
KEY_ENTER       equ     27
KEY_DEG         equ     28
KEY_HZ          equ     29
KEY_KHZ         equ     30
KEY_BACKSPACE   equ     31
KEY_F4          equ     32
KEY_SPARE0      equ     33
KEY_SPARE1      equ     34
KEY_SPARE2      equ     35
KEY_SPARE3      equ     36

; --- the shifted codes that differ -----------------------------------------
; Only sixteen keys have one. They are named so a handler can test for the
; shifted key by name rather than by a number nobody can look up.
KEY_S_FREQ      equ     37
KEY_S_PHASE     equ     38
KEY_S_LOCAL     equ     39
KEY_S_AMPL      equ     40
KEY_S_F1        equ     41
KEY_S_WAVEFORM  equ     42
KEY_S_INC_SET   equ     43
KEY_S_NEXT      equ     44
KEY_S_DOWN      equ     45
KEY_S_LAST      equ     46
KEY_S_UP        equ     47
KEY_S_BACKSPACE equ     48
KEY_S_F3        equ     49
KEY_S_F2        equ     50
KEY_S_F4        equ     51
KEY_S_ENTER     equ     52

KEY_CODE_MAX    equ     52

; --- the two fault codes the scan itself can produce -----------------------
; The stock's kbd_decode ($AAE8) returns $0035 when the matrix scan gives
; $40 and $0036 for anything above $24, and the Keyboard Check's name table
; at $4A3F prints them as 'INVALID ' and ' DOUBLE ' (arms [53] and [54]).
; The same numbers are used here so the two firmwares' screens agree. No
; ordinary screen ever sees either: the foreground drops them unless the
; screen has claimed every key, which is also the stock's shape - its
; keymap guard admits 1..$34 and returns 0 for these.
KEY_INVALID     equ     53              ; any-key asserted, sweep empty: a
                                        ; stuck line or a failing scan
KEY_DOUBLE      equ     54              ; more than one key down at once: a
                                        ; short, or two fingers
KEY_REFRESH     equ     55              ; not a key at all: the foreground's
                                        ; line-6 recovery event, delivered
                                        ; through the installed handler the
                                        ; way the stock posts request $2E to
                                        ; $220F. A screen that wants to act
                                        ; on it compares this; every other
                                        ; screen's ignore arm ends in
                                        ; key_refuse, which passes it in
                                        ; silence - so the event reaches
                                        ; every screen and beeps at nobody.
KEY_GONE_LOCAL  equ     56              ; not a key at all either: the stock's
                                        ; REQUEST 1, which hpib_reset_and_repaint
                                        ; ($9F45) posts at $9F8C on its way out
                                        ; of remote - LDU #$0001 / LDY #$0002 /
                                        ; post_request_code ($8AD0) - and which
                                        ; annunciator_remote_off ($9A5B) is the
                                        ; only caller of. It reaches the
                                        ; installed mode handler, and page 0's
                                        ; dispatch_ui_event ($5D0C) answers it
                                        ; at l5d33 ($5D33): CLRB / CLRA / STD
                                        ; >$2215, end_field_edit ($5CE8),
                                        ; select_menu_page ($514D). PAGE 2
                                        ; ANSWERS IT TOO, through its table
                                        ; rather than a compare - arm [0] of
                                        ; d6e67 is key_close_entry_field ($6E3A)
                                        ; - which is why a search for `cmpx
                                        ; #$0001` found nothing there; pages 1
                                        ; and 3 do not. Every other screen
                                        ; ignores it, which is what key_refuse
                                        ; does with it.
KEY_ABANDON     equ     57              ; not a key either: the stock's
                                        ; REQUEST $3C, which ui_message_dispatch
                                        ; ($8D60) writes over $2217 at $8D7E
                                        ; whenever the modal handler at $220D
                                        ; reports it took the message, and
                                        ; which then reaches the mode: page 0's
                                        ; l5d22 clears $2215 and ends the field
                                        ; edit, page 1's arm [59]
                                        ; key_clear_entry_state ($505F) and
                                        ; page 2's arm [59]
                                        ; key_close_entry_field ($6E3A). The
                                        ; overlays send it (screens_main.s,
                                        ; overlay_abandon_held).
KEY_POSITIONS   equ     36              ; matrix positions, 1 to 36
KEY_POS_GHOST   equ     $40             ; the scan's own sentinel for the
                                        ; empty sweep, the stock's value
KEY_POS_DOUBLE  equ     KEY_POSITIONS+1 ; and for the second key - any
                                        ; position above $24 means it
KEY_COLUMNS     equ     6
KEY_ROWS        equ     6
