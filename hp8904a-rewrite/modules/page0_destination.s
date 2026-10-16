; ===========================================================================
; page0_destination.s - where a channel's signal goes
;
; A channel can drive an output socket, or modulate another channel, or be
; summed into one, or be switched off. That choice is the DESTN field, and it
; is what makes this a multifunction synthesiser rather than four separate
; generators.
;
; The destination codes are the ones the stock firmware's table names, kept
; because an engineer reading a service manual will look for these words.
; ===========================================================================

; The destination codes and their names are NOT here. They share one
; numbering and one table with the waveform field, in labels.s.
;
; This file defined its own set - DESTN_OUT1=0 through DESTN_OFF=9, with the
; names in a fixed-width four-character table. All ten were invented. The
; real codes start at 7, because 0 to 6 belong to the waveform field of the
; same table, and Out1 is 12 rather than 0. Nothing here compared correctly
; against anything, and the frequency ceiling - which keys off destination
; code 11 - would have been chosen by whatever happened to sit at 11 in a
; table that stopped at 9.
;
; The lesson is the one the rules already state: the answer was in the image
; the whole time, in a table this project had already extracted.


DESTN_FIELD_WIDTH equ   4               ; the DEST field is four columns and
                                        ; sits at the end of line 2, so a
                                        ; five-character waveform name would
                                        ; run off the display.

; ---------------------------------------------------------------------------
; destn_show - put the destination name in its field
;
;   entry: A = the DDRAM position, B = the destination code
;   uses:  A, B, X
;
; The name comes from label_find, and its LENGTH IS CLAMPED to the field's.
; The shared table is length-prefixed and a destination name is four
; characters where a waveform name is five - so a five-character name written
; into the four-column DEST field, which ends at the last cell of line 2,
; would put its fifth character past the end of the display. label_find's
; length is what the string is, not what the field is, and lcd_write clips
; nothing.
;
; A code label_find refuses is shown as "Off " rather than left blank: an
; empty column reads as "this field does not apply here", which is a
; different and wrong statement. The refusal is still recorded, so the fault
; is visible on the error screen rather than only in the wrong name.
; ---------------------------------------------------------------------------
destn_show
                pshs    a
                lbsr    ABI_label_find              ; X = characters, B = length
                bcc     destn_show_found

                lda     #ERR_DESTN_CODE
                sta     >last_error
                ldb     #LBL_OFF                ; something legible, and a
                lbsr    ABI_label_find              ; recorded fault behind it
destn_show_found
                cmpb    #DESTN_FIELD_WIDTH      ; never wider than the field
                bls     destn_show_write
                ldb     #DESTN_FIELD_WIDTH
destn_show_write
                puls    a
                lbra    ABI_lcd_write

