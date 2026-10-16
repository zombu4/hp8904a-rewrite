; ===========================================================================
; page2_edit.s - editing the digital pattern in place
;
; THIS FILE HELD A SCREEN THAT THE INSTRUMENT DOES NOT HAVE. It was an 'Edit
; Sequence' screen of its own, reached by f1, showing "Step: n of m Pattern"
; and typing one byte per step into a sixteen-byte table. The instrument has
; no such screen and no such table: the pattern is 125 bytes of one bit
; stream at $3C21 (digital_pattern_ram here), and it is edited ON the Digital
; Sequence screen, through the sixteen-cell window on softkey page 0.
;
; So what is here now is the edit SESSION - the operations f3, f4, ENTER and
; the arrows perform on that window, which is what page2_digital.s calls:
;
;   edit_delete_at_cursor   seq_delete_at_start_index ($558E)
;   edit_insert_at_cursor   seq_insert_at_cursor      ($5517)
;   edit_set_end_here       set_seq_end_to_index      ($5D08)
;   edit_clamp_index        clamp_seq_index_to_end    ($5D91)
;   edit_digit_valid        validate_digit_for_base   ($607E)
;   edit_digit_typed        the digit arm of enter_sequence_field_value ($60CC)
;   edit_index_typed        its index arm                              ($6215)
;
; THE PLAYER RUNS FROM AN INTERRUPT AND THE EDITOR FROM THE FOREGROUND, and
; that is still true of these: an operator tunes a pattern and listens to the
; result. The rule that keeps it safe is the same one the old file stated -
; the END is lowered before the digits it covers are disturbed and raised only
; after the new digits are in place - and it is the instrument's rule too:
; seq_insert_at_cursor raises $3CA4 BEFORE it shifts, because the shift writes
; into the slot the raise just made reachable, and seq_delete lowers it AFTER
; the shift, because until the shift is done the last slot still holds the
; only copy of its digit.
;
; The player reads digital_last_bit and nothing else, so a sequence never
; reaches a digit the shift has not yet moved, provided the recompute follows
; the shift. Every routine here ends with that recompute.
; ===========================================================================

; ---------------------------------------------------------------------------
; edit_delete_at_cursor - take the digit under the cursor out
;
;   uses:  A, B, X, Y, U
;
; seq_delete_at_start_index ($558E), reached from softkey_delete_element
; ($5BDA) at $5BF9. Every digit above the cursor moves down one and the end
; comes down with them - unless the end is already 0, in which case the
; sequence is one digit long and deleting it would leave a negative length.
; The instrument leaves that single digit in place rather than emptying the
; sequence, and so does this.
;
; THE CURSOR DOES NOT MOVE. $3CA2 is untouched, so the digit that shifted into
; the cursor's cell is now under it and a second press deletes that one too -
; which is what makes holding Delete walk a run of digits out.
; ---------------------------------------------------------------------------
edit_delete_at_cursor
                ldx     >digital_index          ; $5598: i from the cursor
edit_delete_next
                cmpx    >digital_end            ; up to the end, exclusive:
                bhs     edit_delete_end         ; the last slot has nothing
                                                ; above it to pull down
                pshs    x
                leax    1,x
                lbsr    digital_digit_at        ; B = the digit above
                puls    x
                tfr     b,a
                pshs    x
                lbsr    digital_digit_put       ; into this one
                puls    x
                leax    1,x
                bra     edit_delete_next
edit_delete_end
                ldx     >digital_end            ; $55E4: and the end comes
                beq     edit_delete_done        ; down, unless it is 0
                leax    -1,x
                stx     >digital_end
edit_delete_done
                lbra    digital_bits_end        ; $5C03: $3CA8 and $3CAA from
                                                ; the new end

; ---------------------------------------------------------------------------
; edit_insert_at_cursor - open a cell at the cursor and put a digit in it
;
;   entry: A = the digit
;   uses:  A, B, X, Y, U
;
; seq_insert_at_cursor ($5517). Three steps and the order of the first two is
; what makes it safe:
;
;   1  the end goes UP first ($5528), so the slot the shift is about to write
;      into is inside the sequence before anything is written there - unless
;      the end is already at the base's capacity, in which case the top digit
;      falls off instead of the sequence growing past what it can hold
;   2  a cursor past the end is not an insertion point at all ($5530 CMPX
;      $3CA4 / LBHI): nothing happens
;   3  the digits move up from the top towards the cursor ($553F), so each one
;      is read before the copy that would overwrite it
;
; THE BIT INDICES ARE NOT RECOMPUTED HERE. The instrument leaves that to its
; caller ($61A5 recomputes $3CA6 and the auto-extend at $6147 has already
; refreshed the end), and so does this: edit_digit_typed does both.
; ---------------------------------------------------------------------------
edit_insert_at_cursor
                pshs    a                       ; the digit, wanted last

                ldx     >digital_end            ; $551D: room to grow?
                cmpx    >digital_max
                bhs     edit_insert_placed
                leax    1,x
                stx     >digital_end
edit_insert_placed
                ldx     >digital_index          ; $5530: an insertion point
                cmpx    >digital_end            ; past the end is not one
                bhi     edit_insert_done

                ldx     >digital_end            ; $5539: from the top down
edit_insert_next
                cmpx    >digital_index          ; $553F: down to the cursor,
                bls     edit_insert_at          ; which is written last
                pshs    x
                leax    -1,x
                lbsr    digital_digit_at        ; B = the digit below
                puls    x
                tfr     b,a
                pshs    x
                lbsr    digital_digit_put       ; up into this slot
                puls    x
                leax    -1,x
                bra     edit_insert_next
edit_insert_at
                ldx     >digital_index          ; $5579: and the new digit in
                lda     ,s                      ; the cell that opened
                lbsr    digital_digit_put
edit_insert_done
                puls    a
                rts

; ---------------------------------------------------------------------------
; edit_set_end_here - the sequence ends at the cursor
;
;   uses:  A, B, X
;
; set_seq_end_to_index ($5D08), which key_set_seq_end_here ($6C75) calls. It
; copies the cursor into the end - BOTH as a digit index and as a bit index,
; $3CA4 := $3CA2 at $5D0E and $3CA8 := $3CA6 at $5D14 - and then recomputes
; the player's own end bit $3CAA from the new $3CA4.
;
; THE BIT INDEX IS COPIED, NOT RECOMPUTED, and the difference shows on a cold
; start: init_sequence_editor leaves $3CA6 at 0 where the arithmetic would
; give 3, so copying it and recomputing it are not the same thing. The
; instrument copies.
; ---------------------------------------------------------------------------
edit_set_end_here
                ldx     >digital_index
                stx     >digital_end
                ldx     >digital_index_bit
                stx     >digital_end_bit
                lbra    digital_bits_last       ; $5D1A: and $3CAA from $3CA4

; ---------------------------------------------------------------------------
; edit_clamp_index - a cursor left past the end after one of them moved
;
;   entry: X = what the moved index held before it moved
;   uses:  A, B, X
;
; clamp_seq_index_to_end ($5D91), and the asymmetry in it is deliberate:
;
;   the SEQ INDEX moving past the end is REFUSED - the previous value is put
;   back and error $37 recorded ($5DAC/$5DB8). The operator asked for a digit
;   that is not in the sequence and does not get it.
;
;   the SEQ END moving below the cursor DRAGS the cursor: $3CA2 becomes
;   $3CA4+1 and the window origin follows ($5DBE-$5DC8). Shortening a sequence
;   is a legitimate thing to do and it cannot be refused just because the
;   cursor happens to be standing in the part being cut off.
;
; Nothing happens at all while the cursor is still within end+1 ($5D97).
; ---------------------------------------------------------------------------
edit_clamp_index
                pshs    x                       ; the previous value
                ldd     >digital_end
                addd    #$0001
                cmpd    >digital_index          ; $5D97: end+1 >= index?
                bhs     edit_clamp_none

                ldx     >digital_field_ptr      ; $5DA3: which one moved
                cmpx    #digital_index
                bne     edit_clamp_drag
                puls    x                       ; the cursor's own move, and
                stx     >digital_index          ; it is undone
                ldb     #ERR_SEQ_INDEX
                lbra    ABI_error_raise
edit_clamp_drag
                leas    2,s                     ; the previous value is not
                ldd     >digital_end            ; wanted on this path
                addd    #$0001
                std     >digital_index          ; $5DBE: just past the end
                std     >digital_window         ; $5DC8: and the window with
                ldx     #$0000                  ; it
                stx     >digital_column
                lbra    digital_bits_index      ; $5DD8
edit_clamp_none
                puls    x
                rts

; ---------------------------------------------------------------------------
; edit_digit_valid - can this base express this digit?
;
;   entry: B = the digit
;   exit:  carry SET if it cannot
;   uses:  A, B
;
; validate_digit_for_base ($607E). The limit is the base shifted left three -
; 0, 8, 16 - and a limit of zero is corrected to 2 ($608F), which is how one
; shift covers all three bases: binary 2, octal 8, hexadecimal 16. A value at
; or above the limit is refused and NOTHING is stored ($60B1).
; ---------------------------------------------------------------------------
edit_digit_valid
                lda     >digital_base           ; $6084: base x 8
                lsla
                lsla
                lsla
                bne     edit_digit_limit
                lda     #$02                    ; $608F: and 0 means 2
edit_digit_limit
                pshs    a
                cmpb    ,s+                     ; $609A
                bhs     edit_digit_bad
                andcc   #~CC_CARRY
                rts
edit_digit_bad
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; edit_digit_typed - one digit typed into the data window
;
;   entry: B = the digit's value
;   uses:  A, B, X, Y, U
;
; The digit arm of enter_sequence_field_value ($60CC). Five things happen in
; this order and each of them is load-bearing:
;
;   1  the digit is validated against the base ($60E7). A refusal records
;      error $39 and stores nothing.
;   2  TYPING ONE PAST THE END EXTENDS THE SEQUENCE ($6120). If the cursor is
;      sitting at end+1 and there is capacity left, the end moves up to meet
;      it - which is how a sequence is lengthened at all. There is no
;      'append' key; you move the cursor past the end and type.
;   3  a cursor still past the end after that ($6168) stores nothing.
;   4  insert or overwrite, on digital_insert ($6172). The insert path undoes
;      step 2's extension first ($617B), because seq_insert_at_cursor raises
;      the end itself and the sequence must only grow by one in total.
;   5  the cursor advances one digit ($61F2), so a run of digits can be typed
;      without touching the arrows.
;
;   exit:  carry SET for step 3 alone - the cursor past the end, nothing
;          stored - and CLEAR after a refusal and after a store. The caller's
;          cursor depends on it: step 3 is $616E LBHI l6202, which skips the
;          step at $61FD whose arm_data_digit_entry_field re-arms the cell,
;          while the refusal re-arms at $6115 and the store at $61FD.
; ---------------------------------------------------------------------------
edit_digit_typed
                pshs    b                       ; the digit
                lbsr    edit_digit_valid
                bcc     edit_digit_ok
                puls    b
                ldb     #ERR_SEQ_DIGIT          ; $6104
                lbsr    ABI_error_raise
                andcc   #~CC_CARRY              ; refused, and re-armed ($6115)
                rts
edit_digit_ok
                clr     >edit_extended          ; $6120: one past the end?
                ldd     >digital_end
                addd    #$0001
                cmpd    >digital_index
                bne     edit_digit_placed
                ldx     >digital_end
                cmpx    >digital_max            ; and room to grow into
                bhs     edit_digit_placed
                leax    1,x
                stx     >digital_end            ; $6147
                inc     >edit_extended
                lbsr    digital_bits_end
edit_digit_placed
                ldx     >digital_index          ; $6168: still past the end?
                cmpx    >digital_end
                bls     edit_digit_store
                puls    b
                orcc    #CC_CARRY               ; $616E LBHI l6202: no store,
                rts                             ; no step, no arm
edit_digit_store
                tst     >digital_insert         ; $6172
                beq     edit_digit_over

                tst     >edit_extended          ; $617B: the insert raises the
                beq     edit_digit_insert       ; end itself, so an extension
                ldx     >digital_end            ; made just now is taken back
                beq     edit_digit_insert
                leax    -1,x
                stx     >digital_end
edit_digit_insert
                puls    a                       ; $6196
                lbsr    edit_insert_at_cursor
                lbsr    digital_bits_end        ; the end moved, so both its
                bra     edit_digit_advance      ; bit indices did
edit_digit_over
                puls    a                       ; $61C1
                ldx     >digital_index
                lbsr    digital_digit_put
edit_digit_advance
                ldb     #$01                    ; $61F2: one digit along
                lbsr    digital_cursor_step
                lbsr    digital_manual_drive    ; and in manual mode the bit
                                                ; now under the cursor is
                                                ; driven, as $6202's
                                                ; display_current_bit implies
                andcc   #~CC_CARRY              ; stored: $61FD re-arms
                rts

; ---------------------------------------------------------------------------
; edit_index_typed - a number typed into Seq Index or Seq End
;
;   entry: X = the number as typed, one-based
;   uses:  A, B, X, Y, U
;
; The index arm of enter_sequence_field_value ($6215). The number the operator
; types is one-based and the index is zero-based, so one is taken off ($6266);
; a number at or past the base's capacity is refused with $37 or $38 depending
; on which field is open ($605E), and the previous value stands.
;
; A TYPED ZERO IS AS FAR DOWN AS IT GOES. Taking one off zero would wrap to
; $FFFF, which is past the capacity, so it is refused by the same check that
; catches a number too large - which is what the instrument does with it.
; ---------------------------------------------------------------------------
; page2_bus_stream - one character of a WSQ stream, into the pattern
;
;   entry: rmt_mode_code = the digit's VALUE, 0 to 15
;   exit:  rmt_check_result = 0 if it went in, ERR_SEQ_DIGIT if the base
;          refuses it - which ends the stream, as it does on the instrument
;   uses:  A, B, X, Y, U
;
; THE STOCK'S OWN SHAPE. key_bulk_seq_entry ($6DDE) does not open the softkey
; edit session: it sets the field id to 9, installs a per-character handler
; (gpib_sequence_data_char $642E) and seeds a SEPARATE write cursor $3CD8 from
; $3CA2. Each character is validated against the base, written with
; seq_write_digit ($4340), and the cursor advances and is clamped to the
; base's capacity; the first character the base refuses returns zero, which
; uninstalls the handler and ends the transfer.
;
; THIS IS gpib_sequence_data_char ($642E), INSTRUCTION FOR INSTRUCTION, and it
; used to be edit_digit_typed with the two cursors swapped around the call.
; That borrowed the whole KEYED path - and the keyed path is not this one:
;
;   1  edit_digit_typed RAISES on a digit the base refuses - it is the digit
;      arm of enter_sequence_field_value ($60CC), which stores $39 itself,
;      because a KEYSTROKE is refused out loud. $6454's
;      is_valid_digit_char leg just returns zero, and $9F9D's caller ends the
;      transfer on a zero return without a word - so a bulk load into the
;      wrong base beeped and posted $39 here where the instrument is silent.
;      Measured against the stock, 2026-09-13, binary base, 'WSQ 012': the
;      instrument left $23DE at $00 and this firmware left last_error at $39.
;   2  worse, the raise made the refusal INVISIBLE to the caller. The tail
;      here cleared rmt_check_result unconditionally, so remote_page2_check
;      always answered carry clear, remote.s's refusal arm was unreachable
;      code, and the stream stayed open on a character the base had thrown
;      away.
;   3  edit_digit_typed ends in digital_cursor_step, whose own tail rewrites
;      digital_window, digital_column and digital_index_bit from
;      digital_index. Putting digital_index back afterwards put back ONE of
;      those four cells, so a stream left the other three pointing at its own
;      end. Measured the same day: after 'WSQ 012' the instrument's $3CA2,
;      $3CD2 and $3CA6 all read 0 and this firmware's digital_index_bit and
;      digital_column read 2.
;   4  and digital_cursor_step's caller ends in digital_manual_drive
;      unconditionally, so every streamed character re-drove the socket from
;      a bit index the stream had just moved. $64EE guards that: record 3,
;      AND the stream cursor equal to the manual cursor, AND $3C04 set.
;
; So none of the editor's cursor cells are touched here at all - the stock
; writes $3CD8 and the pattern and nothing else - and the three things it does
; do are the three $642E does: validate, write, and re-drive the bit only when
; the stream is standing on the operator's own cursor.
; ---------------------------------------------------------------------------
; page2_mode_exit - leaving Digital Sequence
;
;   uses:  A, B, X, Y, U
;
; leave_digital_sequence_mode ($6FBE), installed in $2213 at $735E:
; sequence_run_start_stop ($67A3)(0) stops the clock, reporting the end if it
; was running, and set_digital_output_bit ($51C8)(0) parks the output line.
; digital_key_stop's own steps, without its repaint.
; ---------------------------------------------------------------------------
page2_mode_exit
                lbsr    digital_report_end      ; $67A3 tests $3C02 first
                lbsr    ABI_tick_remove
                clr     >digital_running
                clr     >digital_manual
                lbra    digital_drive_idle      ; $51C8(0)

; ---------------------------------------------------------------------------
page2_bus_stream
                ldb     >rmt_mode_code
                lbsr    edit_digit_valid        ; $6454's is_valid_digit_char
                bcc     page2_stream_take
                ldb     #ERR_SEQ_DIGIT          ; $6558 RETURNS ZERO AND SAYS
                stb     >rmt_check_result       ; NOTHING. The code goes to
                rts                             ; the caller, which ends the
                                                ; transfer with it; it is not
                                                ; reported and not beeped
page2_stream_take
                tfr     b,a                     ; $6454's leg: the value,
                ldx     >digital_stream_at      ; at the STREAM's cursor
                lbsr    digital_digit_put       ; $4340 seq_write_digit

                ldx     >digital_stream_at      ; $64EE: the live output bit
                cmpx    >digital_index          ; is re-driven only when the
                bne     page2_stream_step       ; stream is standing ON the
                lbsr    digital_manual_drive    ; manual cursor - $51F6's own
                                                ; $3C04 test is inside it
page2_stream_step
                ldx     >digital_stream_at      ; $653B: one along...
                leax    1,x
                cmpx    >digital_max            ; ...and no further than the
                bls     page2_stream_store      ; base's capacity ($3CCE)
                ldx     >digital_max
page2_stream_store
                stx     >digital_stream_at
                lbsr    digital_show            ; $64EB's leg draws the cell
                                                ; the character landed in.
                                                ; The stock writes one cell
                                                ; and only when it is inside
                                                ; the window; this repaints
                                                ; the record, which is what
                                                ; every other arm of this
                                                ; screen does and comes to the
                                                ; same glass
                clr     >rmt_check_result
                rts

; ---------------------------------------------------------------------------
; page2_bus_index - SEQP or SEQE from the bus, through the panel's commit
;
;   entry: rmt_mode_code = 0 for Seq Index, anything else for Seq End
;          rmt_val+1 = the number as typed, one-based, sixteen bits
;   exit:  rmt_check_result = 0, or the error the panel would raise
;   uses:  A, B, X, Y, U
;
; THE BUS USED TO STORE THESE CELLS ITSELF and skipped three things the keypad
; does: edit_clamp_index, which undoes a cursor moved past the end and DRAGS
; the cursor down when the end moves below it; the window that follows the
; cursor; and the pair of error codes the panel answers with. 'SEQE 10;' with
; the cursor at digit 500 left the cursor 490 digits past the end of the
; sequence - a state the keypad cannot produce - and the editor then drew and
; edited from a window that was nowhere.
;
; So the bus takes the route the ENTER key takes, which is what the instrument
; does with every other number: on the stock there is no bus setter at all,
; only a field selector and the panel's own commit.
; ---------------------------------------------------------------------------
page2_bus_index
                ldu     #digital_index          ; which of the three, as
                lda     #DIGITAL_FIELD_INDEX    ; digital_sk_index,
                ldb     >rmt_mode_code          ; digital_sk_end and the Bit
                beq     page2_bus_index_at      ; softkey select them
                cmpb    #$02
                lbeq    page2_bus_index_bit
                ldu     #digital_end
                lda     #DIGITAL_FIELD_END
                bra     page2_bus_index_at
page2_bus_index_at
                sta     >digital_field
                stu     >digital_field_ptr
                ldx     >rmt_val+1              ; the number as typed
                lbsr    edit_index_typed        ; the panel's own commit, which
                bcs     page2_bus_index_bad     ; raises its own refusal
                clr     >rmt_check_result
                rts
page2_bus_index_bit
                ; THE BIT NUMBER, as enter_bit_index ($4DE1) commits it: l6215
                ; saves the base ($3C20 into 3,s), changes to binary, measures
                ; the index against the capacity IN BITS ($3CCC), changes the
                ; base back ($62BC), and then the bit under the cursor is
                ; driven whatever the commit said ($4E00 manual_output_drive_bit).
                ; Measured in the current base, 'RUNM 999 UV;' on a hex
                ; sequence was refused with $37 where the instrument takes it.
                lda     #DIGITAL_FIELD_BIT      ; $3CAC = $0B
                sta     >digital_field
                lda     >digital_base
                pshs    a
                lda     #DIGITAL_BASE_BIN
                lbsr    digital_base_change
                ldx     #digital_index          ; the bit index IS the cursor
                stx     >digital_field_ptr      ; while the base is binary
                ldx     >rmt_val+1
                tst     >rmt_val                ; past sixteen bits: the stock
                beq     page2_bus_index_bits    ; records the range refusal,
                ldx     #$FFFF                  ; $37 ('RUNM 99999 UV;')
page2_bus_index_bits
                lbsr    edit_index_typed
                pshs    cc,b                    ; the verdict and its code
                lda     2,s                     ; the base it had
                lbsr    digital_base_change
                lbsr    digital_manual_drive
                puls    cc,b
                leas    1,s
                bcs     page2_bus_index_bad
                clr     >rmt_check_result
                rts
page2_bus_index_bad
                stb     >rmt_check_result       ; B = the code it raised
                rts

; ---------------------------------------------------------------------------
edit_index_typed
                ldu     >digital_field_ptr      ; which of the two
                ldd     ,u                      ; $6233: what it held
                pshs    d

                cmpx    #$0000                  ; a typed 0 has no zero-based
                beq     edit_index_bad          ; form
                leax    -1,x                    ; $6266
                cmpx    >digital_count          ; $626C: the capacity, not the
                bhs     edit_index_bad          ; end - Seq End may be set
                                                ; anywhere the base can hold
                tfr     x,d
                std     ,u                      ; $6271

                puls    x                       ; the previous value, for the
                lbsr    edit_clamp_index        ; clamp $6291

                ldx     >digital_field_ptr      ; $629D: the bit index of
                cmpx    #digital_index          ; whichever one moved
                bne     edit_index_end_bits
                lbsr    digital_bits_index
                ldx     >digital_index          ; $62D0: and the window
                stx     >digital_window         ; follows the cursor
                ldx     #$0000
                stx     >digital_column
                andcc   #~CC_CARRY              ; STORED - and the carry says
                rts                             ; so, for the bus's sake: the
                                                ; panel ignores it, and
                                                ; page2_bus_index reports it to
                                                ; the controller
edit_index_end_bits
                lbsr    digital_bits_end
                andcc   #~CC_CARRY
                rts
edit_index_bad
                puls    x                       ; nothing is stored
                ldb     #ERR_SEQ_END            ; $605E: which number was
                ldu     >digital_field_ptr      ; refused decides the code
                cmpu    #digital_index
                bne     edit_index_raise
                ldb     #ERR_SEQ_INDEX
edit_index_raise
                pshs    b                       ; THE CODE SURVIVES THE REPORT.
                lbsr    ABI_error_raise         ; error_raise beeps and paints,
                puls    b                       ; and does not promise B back -
                                                ; so the bus wrapper stored
                                                ; whatever was left in it
                orcc    #CC_CARRY
                rts
