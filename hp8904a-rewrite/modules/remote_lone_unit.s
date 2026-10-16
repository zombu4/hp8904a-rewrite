; ===========================================================================
; remote_lone_unit.s - a unit mnemonic that arrives with no number in front
;
; Part of the bus parser in remote.s, which reaches it from
; remote_commit_units with LBEQ. It sits in its own file for one reason:
; the resident image below the ABI table at $F000 had 127 bytes left when
; the architect's Q1 ruling had this leg carry a
; number between messages, and the leg is larger than that. Included after
; registers.s in a2u12_all.inc, above the table, as remote_tables.s and
; registers.s are for the same reason. Every route in is LBEQ or LBRA and
; every route out is LBSR, LBCS or LBRA, so nothing here depends on where
; the assembler puts it.
; ===========================================================================

remote_commit_no_value
                ; A FIELD IS ARMED AND NO NUMBER CAME: THE UNIT IS ASKED FIRST.
                ; $A8EC tests $238F and then unit_allowed_for_group ($A65A)
                ; before it looks for any value, and a unit the field's group
                ; does not take is $2E there. Measured 2026-09-17, seed 5 step
                ; 127: PHASE armed on ch D, 'KZ 501;' - KZ ahead of its number
                ; - is $2E on the instrument, and was $2B here.
                ;
                ; A UNIT THE FIELD TAKES COMMITS WHAT THE ENTRY HOLDS. The unit
                ; leg never looks for a number: it clears $238F and posts $23,
                ; the ENTER key's own request, and the screen commits its entry
                ; buffer - a number left there by an earlier message, or an
                ; empty buffer. The architect ruled this ported (Q1,
                ; 2026-09-17). Measured 2026-09-17 on both firmwares,
                ; each field armed by its mnemonic and the unit sent alone:
                ;   held number  commits, on every kind below that holds one
                ;   empty, $2E   WFA DEA SM SV AHR - $A65A takes no unit there
                ;   empty, 0     SEQP SEQE (tone and digital), RUNM's Bit and
                ;                DAPH: the empty buffer reads as 0, so the Seq
                ;                fields answer $37/$38 and a level becomes 0 V
                ;   empty, $36   HRA on the Tone Sequence screen
                ;   empty, $23   FRA on the tone record: commit_freq_value
                ;                keeps the value and still downloads the tone
                ;   empty, quiet FRA APA PHA, FRH APH PHH, the tone APA, STON
                ;                on both sequence screens, HRA on the hop
                ;                record - nothing moves, no error, and the
                ;                field stays armed ('FRA;' 'HZ;' '5 HZ;' sets 5)
                ; OO, FS, ST_ID and ST_OP were not driven this way (the last two
                ; are the owner's, with no stock form) and keep $2B.
                lbsr    remote_unit_misfit      ; carry: not this field's unit
                lbcs    remote_units_bad        ; $2E
                lda     >rmt_flags
                bita    #RF_HELD
                beq     remote_empty_entry
                lda     >rmt_pend_kind          ; held for THIS field: another
                cmpa    >rmt_held_kind          ; field's number is never its
                bne     remote_empty_entry
                lda     >rmt_flags              ; RF_HELD is set and RF_VALUE
                eora    #RF_HELD|RF_VALUE       ; clear here: the value is
                sta     >rmt_flags              ; waiting again, as if it had
                ldb     >rmt_unit               ; come with this unit
                lbra    remote_commit_units
remote_empty_entry
                lda     >rmt_flags              ; a number held for a field no
                anda    #~RF_HELD&$FF           ; longer armed goes
                sta     >rmt_flags
                lda     >rmt_pend_kind
                ldx     #rmt_empty_refused
                ldb     #RMT_EMPTY_REFUSED
remote_empty_refused_scan
                cmpa    ,x+
                lbeq    remote_units_bad        ; $2E
                decb
                bne     remote_empty_refused_scan
                ldx     #rmt_empty_zero
                ldb     #RMT_EMPTY_ZERO
remote_empty_zero_scan
                cmpa    ,x+
                beq     remote_empty_as_zero
                decb
                bne     remote_empty_zero_scan
                ldx     #rmt_empty_quiet
                ldb     #RMT_EMPTY_QUIET
remote_empty_quiet_scan
                cmpa    ,x+
                beq     remote_empty_done
                decb
                bne     remote_empty_quiet_scan
                cmpa    #RK_TONE
                lbeq    remote_set_tone_bad     ; $36
                cmpa    #RK_TONEFREQ            ; $23 with nothing typed:
                bne     remote_empty_other      ; the tone screen's arm for
                ldb     #RMT_RQ+$23             ; it downloads the tone
                lbra    remote_deliver          ; (RF_VALUE is clear)
remote_empty_other
                ldb     #ERR_RMT_NO_FIELD       ; the kinds not driven
                lbra    remote_error
remote_empty_as_zero
                clr     >rmt_val
                clr     >rmt_val+1
                clr     >rmt_val+2
                clr     >rmt_frac
                clr     >rmt_exp
                clr     >rmt_exp_neg
                lda     >rmt_flags
                anda    #$CB                    ; ~(RF_OVER|RF_MINUS|RF_VALUE)
                ora     #RF_VALUE
                sta     >rmt_flags
                ldb     >rmt_unit
                lbra    remote_commit_units
remote_empty_done
                rts

; The three lists remote_empty_entry reads, one kind per byte.
rmt_empty_refused fcb   RK_WAVE                 ; WFA;  HZ;  $2E
                fcb     RK_DEST                 ; DEA;  HZ;  $2E
                fcb     RK_SREMASK              ; SM;   HZ;  $2E
                fcb     RK_SAVE                 ; SV;   ET;  $2E
                fcb     RK_RECALL               ; RC;   ET;  $2E
                fcb     RK_HOPROW               ; AHR;  HZ;  $2E
RMT_EMPTY_REFUSED equ   6
rmt_empty_zero  fcb     RK_SEQPOS               ; SEQP; ET;  $37
                fcb     RK_SEQEND               ; SEQE; ET;  $38
                fcb     RK_DIGBIT               ; RUNM; ET;  $37
                fcb     RK_DIGLEVEL             ; DAPH; VL;  On Lev 0
RMT_EMPTY_ZERO  equ     4
rmt_empty_quiet fcb     RK_FREQ
                fcb     RK_AMPL
                fcb     RK_PHASE
                fcb     RK_HOPFREQ
                fcb     RK_HOPAMPL
                fcb     RK_HOPPHASE
                fcb     RK_TONEAMPL
                fcb     RK_TIME
                fcb     RK_HOPADDR
RMT_EMPTY_QUIET equ     9

; ---------------------------------------------------------------------------
; remote_gone_unit - a unit for a field whose cursor the tone screen zeroed
;
;   entry: B = the unit code
;   uses:  A
;
; reject_key_error_3a ($5071) and the $3B arms end in l5104, which zeroes the
; field cursor $3D11 at $517F and leaves $238F alone. The unit leg then still
; asks unit_allowed_for_group ($A65A) - $2E for a unit the field does not
; take - and posts $23, and commit_entry_to_field finds cursor 0 and commits
; nothing. Any number waiting, held or in this command, goes with it.
; ---------------------------------------------------------------------------
remote_gone_unit
                lbsr    remote_unit_misfit      ; carry: not this field's unit
                lbcs    remote_units_bad        ; $2E
                lda     >rmt_flags
                anda    #$7B                    ; ~(RF_HELD|RF_VALUE)
                sta     >rmt_flags
                rts
