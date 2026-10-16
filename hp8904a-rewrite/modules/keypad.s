; ===========================================================================
; keypad.s - the front-panel key matrix
;
; Six columns driven at kbd_cols ($0A00), six rows read back at kbd_rows
; ($0000). Both are active low. Two extra bits arrive on the row port and
; have nothing to do with the matrix:
;
;   bit 6   the external-reference detect, HIGH when one is connected -
;           established from the stock external_ref_absent ($DC14), which
;           masks $40 and returns 1 when the bit is clear
;   bit 7   the any-key line - HIGH while any key is down, whatever column is
;           driven
;
; Bit 7 is what makes an idle scan cheap: with no column driven the port
; still says whether anything is pressed, so the foreground can skip the
; whole six-column sweep on the overwhelming majority of passes.
;
; DEBOUNCING is by edge, not by timer. A key is reported once, when it first
; appears, and not again until it has been released. A mechanical key bounces
; for a few milliseconds and the foreground scans far faster than that, so a
; level-triggered scan would report one press dozens of times.
; ===========================================================================

; KEY_COLUMNS, KEY_ROWS and KEY_NONE are in common/keys.inc, with the key
; codes themselves. KEY_NONE is ZERO there, not $FF: position 0 is the one
; matrix position that does not exist, so zero is the natural "nothing" and
; it is also what the action table's first entry decodes to.
KEY_IDLE_COLS   equ     $40             ; EVERY column driven, bit 6 high -
                                        ; the state the any-key line is read in

; ---------------------------------------------------------------------------
; keypad_init - put the matrix in its idle state
;
;   uses:  A
; ---------------------------------------------------------------------------
keypad_init
                lda     #KEY_IDLE_COLS
                sta     >kbd_col_shadow         ; the shadow first, so an
                sta     >kbd_cols               ; interrupt reading it agrees
                lda     #KEY_NONE
                sta     >key_last
                sta     >key_pending
                rts

; ---------------------------------------------------------------------------
; keypad_any - is any key down at all?
;
;   exit:  Z clear if a key is down, Z set if none is
;   uses:  A
;
; One port read, no sweep. The foreground calls this every pass and only
; sweeps when it says yes.
; ---------------------------------------------------------------------------
keypad_any
                lda     #KEY_IDLE_COLS
                sta     >kbd_col_shadow
                sta     >kbd_cols
                lda     >kbd_rows
                anda    #$80                    ; BIT 7 SET MEANS A KEY IS
                rts                             ; DOWN. This had an `eora
                                                ; #$80` after the mask, on the
                                                ; belief that the line is low
                                                ; while a key is held, and it
                                                ; inverted the answer: with a
                                                ; key held keypad_scan skipped
                                                ; the sweep and returned
                                                ; KEY_NONE, so on the
                                                ; instrument no key would ever
                                                ; have been reported.
                                                ;
                                                ; The stock settles it.
                                                ; kbd_matrix_scan ($A9A2) does
                                                ; `andb #$80 / cmpd #$0000 /
                                                ; lbne la9c5` - it goes and
                                                ; sweeps the matrix when the
                                                ; bit is SET, and returns
                                                ; position 0 when it is clear.

; ---------------------------------------------------------------------------
; keypad_scan - find which key is down
;
;   exit:  B = the matrix POSITION, 1 to 36, or KEY_NONE; Z set when nothing
;          is down
;   uses:  A, B - X is untouched; it was listed here from before the probe
;          was factored out, and a header that over-claims teaches callers
;          to save a register nothing disturbs
;
; Drives one column at a time and reads the rows. The position is
; row*6 + col + 1, which is the instrument's own numbering - the stock
; firmware's action table at $EF4A is indexed by exactly this, so keeping it
; means the table can be reproduced rather than re-derived.
;
; Note the +1. Position 0 does not exist, and that is not decoration: zero is
; what a failed scan reports, and if it were also a valid position a failed
; scan would report the first key on the panel. This computed column*6+row
; and started at zero until the stock table was read.
;
; TWO KEYS AT ONCE ARE REPORTED AS KEY_POS_DOUBLE, and a sweep that finds
; nothing while the any-key line is asserted as KEY_POS_GHOST - the stock's
; scan says the same with a value above $24 and with $40, which kbd_decode
; ($AAE8) turns into codes $36 and $35 and the Keyboard Check prints as
; ' DOUBLE ' and 'INVALID '. An earlier version let the first key found win,
; on the reasoning that two keys mean nothing to the instrument - true for
; every ordinary screen, and exactly wrong for the diagnostic whose job is
; finding the matrix short that makes two keys read at once. Ordinary
; screens never see either code: the foreground drops them unless the
; screen has claimed every key.
; ---------------------------------------------------------------------------
keypad_scan
                ; THE CHEAP CHECK FIRST. Bit 7 of the row port is HIGH while
                ; any key is down, whatever column is driven, so an idle
                ; instrument answers in five instructions instead of sweeping
                ; six columns. keypad_any exists for exactly this and nothing
                ; called it - the sweep ran on every pass of the foreground
                ; loop, which is most of what the foreground did.
                lbsr    keypad_any              ; Z set when nothing is down
                bne     keypad_scan_sweep
                lbsr    keypad_idle
                ldb     #KEY_NONE
                orcc    #CC_ZERO
                rts
keypad_scan_sweep
                clr     >key_column
keypad_scan_column
                lda     >key_column
                cmpa    #KEY_COLUMNS
                bhs     keypad_scan_ghost       ; swept them all - and the
                                                ; cheap check SAID a key was
                                                ; down, so an empty sweep is
                                                ; not "nothing pressed"

                bsr     keypad_scan_probe       ; A = this column's rows
                tsta
                beq     keypad_scan_next        ; nothing on this column

                clrb                            ; find the lowest set bit
keypad_scan_row
                lsra
                bcs     keypad_scan_found
                incb
                cmpb    #KEY_ROWS
                blo     keypad_scan_row
                bra     keypad_scan_next
keypad_scan_found
                ; TWO KEYS ARE NOT A KEY. The stock's decode turns a scan
                ; above $24 into code $36, which the Keyboard Check's arm
                ; [54] prints as ' DOUBLE ' - a matrix short reading as two
                ; keys is exactly what that screen exists to find, and
                ; "the first key found wins" hid it: a short looked like a
                ; working key. The rest of this column's rows are still in A
                ; after the shift loop, and the remaining columns are swept
                ; below once the position is known.
                tsta                            ; another row low here?
                bne     keypad_scan_two

                ; B holds the row. position = row*6 + column + 1.
                lda     #KEY_COLUMNS
                mul                             ; D = row * 6
                addb    >key_column
                incb                            ; positions count from one

                pshs    b                       ; and sweep the REMAINING
keypad_scan_rest                                ; columns for a second key
                inc     >key_column
                lda     >key_column
                cmpa    #KEY_COLUMNS
                bhs     keypad_scan_single
                bsr     keypad_scan_probe
                tsta
                beq     keypad_scan_rest
                leas    1,s                     ; a second key: the position
                bra     keypad_scan_two         ; is not reported
keypad_scan_single
                puls    b
; keypad_scan_add - the shared exit of a sweep that found a key
;
; B already holds the position. Stopping the column drive before returning is
; not optional: left driving, the row port keeps reporting that column's keys
; and the next cheap any-key check sees one that is not being pressed now.
keypad_scan_add
                bsr     keypad_idle             ; stop driving before leaving
                andcc   #~CC_ZERO               ; Z clear: a key was found
                rts
keypad_scan_next
                inc     >key_column
                bra     keypad_scan_column
keypad_scan_two
                bsr     keypad_idle
                ldb     #KEY_POS_DOUBLE         ; above every real position,
                andcc   #~CC_ZERO               ; which is how the stock's
                rts                             ; scan says it too

keypad_scan_ghost
                ; THE CHEAP CHECK AND THE SWEEP DISAGREE: keypad_any saw the
                ; any-key line asserted and six driven columns found no key.
                ; That is a fault - a stuck line, a failing diode - and the
                ; stock gives it its own answer: scan value $40, which
                ; kbd_decode turns into code $35 and the Keyboard Check
                ; prints as 'INVALID '. Reporting KEY_NONE here made the
                ; fault invisible on the one screen built to show it.
                ;
                ; BUT A KEY LET GO DURING THE SWEEP IS NOT A FAULT. keypad_any
                ; and the six probes are not one instant: release a key
                ; between them and the cheap check has already said yes while
                ; every column reads clear. That is an ordinary release, and
                ; it was being reported as a stuck line - so on the Keyboard
                ; Check, the one screen that shows this code, an ordinary
                ; press printed its name and then 'INVALID ' as the finger
                ; came off. A line that really is stuck is still asserted, so
                ; asking again separates the two.
                lbsr    keypad_any              ; still down?
                bne     keypad_scan_stuck
                bsr     keypad_idle
                ldb     #KEY_NONE
                orcc    #CC_ZERO
                rts
keypad_scan_stuck
                bsr     keypad_idle
                ldb     #KEY_POS_GHOST
                andcc   #~CC_ZERO
                rts

; ---------------------------------------------------------------------------
; keypad_scan_probe - drive one column and read its rows
;
;   entry: key_column = which column
;   exit:  A = the rows with a pressed key as a 1 bit, zero if none
;   uses:  A, B
;
; A DRIVEN COLUMN IS LOW, and bits 7:6 are not ours. An earlier version
; wrote `1 << column` straight out, which drives the five columns it does
; not want and leaves the one it does want undriven - every key would have
; been decoded onto the wrong column - and it cleared bit 7 and bit 6, which
; belong to the shadow and to the external-reference line. The stock does
; all three things right and this matches it instruction for instruction
; (a2u12.s:9260-9273):
;
;       ldb #$01 / shift_by_signed_count      1 << column
;       com 4,s                               the drive is LOW
;       andb #$3f                             six lines only
;       ldb kbd_col_shadow / andb #$c0        keep 7:6
; ---------------------------------------------------------------------------
keypad_scan_probe
                lda     >key_column
                ldb     #$01                    ; turn the column number into
keypad_scan_shift                               ; a single driven line
                tsta
                beq     keypad_scan_drive
                lslb
                deca
                bra     keypad_scan_shift
keypad_scan_drive
                comb                            ; the wanted column goes LOW
                andb    #$3F                    ; and only the six column
                pshs    b                       ; lines are ours to set
                lda     >kbd_col_shadow
                anda    #$C0                    ; bit 7 the shadow's own, bit
                ora     ,s+                     ; 6 the external reference
                sta     >kbd_col_shadow
                sta     >kbd_cols

                lda     >kbd_rows               ; which row came back low?
                coma                            ; active low: make a pressed
                anda    #$3F                    ; row read as a 1 bit
                rts

; ---------------------------------------------------------------------------
; keypad_idle - stop driving any column
;
;   uses:  A
;
; Left driving a column, the any-key line still works but the row port also
; reports that column's keys, so the next cheap check would see a key that is
; not being pressed now. Every exit from a sweep comes through here.
; ---------------------------------------------------------------------------
keypad_idle
                lda     #KEY_IDLE_COLS
                sta     >kbd_col_shadow
                sta     >kbd_cols
                rts

; ---------------------------------------------------------------------------
; keypad_read - one key press, once
;
;   exit:  B = the KEY CODE, or KEY_NONE; Z set when there is nothing new
;   uses:  A, B, X
;
; The edge detector, and the place the matrix position becomes a key code.
;
; The edge is detected on the POSITION and the decode happens after, which
; matters for the shift key: shift is a one-shot latch consumed by the next
; key, so decoding a held key repeatedly would consume the latch on the first
; pass and the key the operator actually shifted would arrive unshifted.
;
; A key that is still held is not reported again; releasing it re-arms the
; detector. The shift key decodes to KEY_NONE, so it never reaches a screen.
; ---------------------------------------------------------------------------
KEY_REPEAT_MS   equ     150             ; how long a held arrow waits before
                                        ; stepping again. SEE THE HEADER: the
                                        ; stock's number is in units of its
                                        ; own loop and cannot be converted.

keypad_read
                lbsr    keypad_scan
                bne     keypad_read_down

                lda     #KEY_NONE               ; nothing down: re-arm
                sta     >key_last
                sta     >key_repeat_code        ; and nothing is repeating
                ldb     #KEY_NONE
                orcc    #CC_ZERO
                rts
keypad_read_down
                cmpb    >key_last
                beq     keypad_read_held        ; still the same key held
                stb     >key_last               ; a new press: decode it
                lbsr    key_decode
                tstb                            ; shift decodes to KEY_NONE,
                beq     keypad_read_shift       ; and is not a press a screen
                stb     >key_repeat_code        ; should ever see
                andcc   #~CC_ZERO
                rts
keypad_read_shift
                clr     >key_repeat_code        ; a held SHIFT repeats nothing
                bra     keypad_read_same

; AUTO-REPEAT, on the two keys the stock repeats and no others.
;
; foreground_main_loop ($83A0) counts $026C down at $8874 while bit 2 of the
; event_flags high byte is set, and on reaching zero calls read_key ($AB9E)
; and posts a request code for exactly two decoded keys: $0013 gives request
; $20 at $88B0 and $0019 gives request $1F at $889F. Key code $13 is 19,
; KEY_UP, and $19 is 25, KEY_DOWN. Every other key falls to $88C1, which
; clears the flag - so a held anything-else repeats nothing.
;
; Holding an arrow steps a value repeatedly, which on an instrument where a
; frequency is set by stepping is the difference between an arrow that is
; useful and one that is not. Nothing here repeated at all.
;
; THE RATE IS NOT THE STOCK'S AND CANNOT BE. $026C is 620 passes of ITS
; foreground loop, and that loop is a thirty-four arm dispatch with an event
; executive around it while this one is a keypad scan and two polls. Passes
; are not a unit that converts, and nothing in the ROM gives the interval in
; time. So this is timed against the hardware instead - delay_ms is timer 3,
; one count per millisecond - and 150 ms is a choice, stated as a choice:
; between six and seven steps a second, fast enough to be worth holding the
; key and slow enough to stop where the operator meant to.
;
; THE DELAY IS TAKEN HERE rather than counted in the foreground because the
; foreground has nothing else to do while a key is held down, and a countdown
; in loop passes would be the unit that does not convert all over again. The
; key is re-checked after the wait, so releasing it during the delay does not
; produce one last step the operator did not ask for.
keypad_read_held
                ldb     >key_repeat_code
                cmpb    #KEY_UP
                beq     keypad_read_repeat
                cmpb    #KEY_DOWN
                bne     keypad_read_same
keypad_read_repeat
                ldd     #KEY_REPEAT_MS
                lbsr    delay_ms
                lbsr    keypad_scan             ; still down, and still the
                beq     keypad_read_same        ; same one? A release during
                cmpb    >key_last               ; the wait ends the repeat
                bne     keypad_read_same        ; rather than adding a step
                ldb     >key_repeat_code
                andcc   #~CC_ZERO
                rts
keypad_read_same
                ldb     #KEY_NONE
                orcc    #CC_ZERO
                rts
