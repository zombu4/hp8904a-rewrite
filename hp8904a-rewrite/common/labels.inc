; ===========================================================================
; labels.inc - the shared waveform and destination CODES
;
; ONE TABLE, ONE NUMBERING. The waveform a channel produces and the place it
; is sent are two different fields on the Channel Configuration screen, and
; they share a single sequence of codes:
;
;    0  (blank)   no waveform chosen
;    1  Sine      6  Sq          12  Out1
;    2  Ramp      7  AM          13  Out2
;    3  Trngl     8  FM          14  Out3
;    4  dc        9  PhiM        15  Out4
;    5  Noise    10  DSB         16  Off
;                11  Plse        17  On
;
; A NOTE ON Out3 AND Out4. The codes exist in the ROM's table, but the
; service manual prints exactly TWO general-purpose output assemblies - A3
; and A10, the latter Option 002 - and the front-panel sockets are labelled
; OUTPUTS 1 HIGH / LOW and OUTPUTS 2 HIGH. So an instrument can carry four
; WAVEFORM channels and two output ports, and codes 14 and 15 name sockets
; that this manual does not describe. They are kept because the ROM has them
; and because destn_is_output would otherwise have to hard-code a smaller
; range on evidence that is about assemblies rather than about codes.
;
; That is not a convenience adopted here. It is the hardware's own numbering,
; read out of the stock image: the table at $EE88 is a run of length-prefixed
; strings walked by index, waveform codes take the first seven entries and
; destination codes carry straight on from seven.
;
; Knowing that explains two rules that look arbitrary otherwise:
;
;   check_freq_limit drops the ceiling from 600 kHz to 50 kHz for "waveform
;   2, 3 or 6" - Ramp, Triangle and Square, the three built from hard edges;
;
;   and for "destination $0B" - which is 11, Plse. Pulse modulation needs
;   bandwidth around the carrier for the same reason a square wave does.
;
; Both are the same physical rule, and it is only visible because the two
; fields share one numbering.
;
; THIS WAS WRONG BEFORE. The destinations were written here as Out1=0 through
; Off=9, invented rather than read. Every comparison against them would have
; matched the wrong thing, and the frequency ceiling would have been chosen
; by a code that meant something else entirely.
;
; ONLY THE CODES ARE HERE. The names, and the routine that walks them, live
; in modules/labels.s, which is in A2U12 and reached from the paged images
; through the ABI. The codes are needed by every image - a paged screen
; compares against them constantly - and a table of eighteen strings is not
; worth four copies of.
; ===========================================================================

; --- waveform codes: what the channel generates ----------------------------
LBL_NONE        equ     0               ; nothing chosen; the field is blank
LBL_SINE        equ     1
LBL_RAMP        equ     2
LBL_TRIANGLE    equ     3
LBL_DC          equ     4
LBL_NOISE       equ     5
LBL_SQUARE      equ     6

; --- destination codes: where it goes --------------------------------------
LBL_AM          equ     7               ; modulate another channel's level
LBL_FM          equ     8               ; ...its frequency
LBL_PHIM        equ     9               ; ...its phase
LBL_DSB         equ     10              ; double sideband, suppressed carrier
LBL_PULSE       equ     11              ; pulse modulation
LBL_OUT1        equ     12              ; the four physical output sockets
LBL_OUT2        equ     13
LBL_OUT3        equ     14
LBL_OUT4        equ     15
LBL_OFF         equ     16              ; generated but not routed anywhere
LBL_ON          equ     17
LBL_COUNT       equ     18

; The span that means "modulate another channel" rather than "go to a
; socket". Used by the phase path, which negates a modulation phase, and by
; the frequency ceiling.
LBL_MOD_FIRST   equ     LBL_AM
LBL_MOD_LAST    equ     LBL_PULSE

; The phi glyph is not in the HD44780's character generator, so it is one of
; the eight characters this firmware defines at power-on. display.inc names
; the slots; this is the one that makes PhiM readable.
CHAR_PHI        equ     $05
CHAR_MU         equ     $06             ; the microvolt sign, CGRAM slot 6.
                                        ; The stock's unit table at $EEEE
                                        ; carries it as entry 7, `fcb $03,$06,
                                        ; $56,$20` - the glyph, 'V' and a
                                        ; space - and lcd_glyphs in lcd.s
                                        ; loads slot 6 from the same eight
                                        ; bytes the stock loads at $EA45

; The unit labels are three characters each and there are sixteen of them -
; the stock's table at $EEEE. Declared HERE rather than beside the table in
; modules/labels.s because the paged screens write their own value fields and
; have to know how wide a label is; a paged image cannot see an equ in A2U12.
UNIT_LABEL_LEN  equ     3
UNIT_LABEL_COUNT equ    16
