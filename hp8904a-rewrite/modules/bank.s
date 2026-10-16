; ===========================================================================
; bank.s - the read-write bank in the A2U13 socket, option (c)
;
; A One ROM fitted in place of the 27513 answers to a FIFTH bank. The four
; pages are selected by writing $30-$33 to page_select; the bank is selected by
; writing $34. It is SRAM, the board copies it to its own flash whenever the
; content changes, and it is read back at the board's boot - so what is kept
; there outlives both the battery and a power cut.
;
; WHAT LIVES THERE: the serial number, the installed options and the twelve
; save/recall registers. What stays in the HM6264: everything else, including
; the stack, and including the working copies of the serial and the options -
; rule 2's four addresses do not move, and the three paged readers of the
; options byte (hop_available, chan_destn_fitted, channel_config_open) cannot
; switch the window to read it because they would unmap themselves.
;
; So the bank holds the AUTHORITY and $3FFC-$3FFF hold the SHADOW. A write goes
; to the bank first and the shadow second; a boot copies the bank into the
; shadow. If power fails between the two writes the bank is the one that is
; right, and the next boot repairs the shadow from it.
;
; ON A GENUINE 27513 NONE OF THIS HAPPENS, and nothing was added to make that
; so. The part takes only D0 and D1 as inputs, so writing $34 presents
; D1:D0 = 00 and it selects page 0; the read-back then returns page 0's own
; first byte, $30, which is not $34, and bank_probe fails. One probe, no second
; test that could disagree with it.
;
; PAGE_COUNT STAYS 4. The bank is not a page: nothing that walks pages may
; reach it, and page_select_and_verify's mask still refuses anything above 3.
; The only way into the window here is bank_enter, which is deliberately not
; that routine.
; ===========================================================================

; ---------------------------------------------------------------------------
; bank_enter - map the bank, remembering what was mapped before
;
;   exit:  carry CLEAR and the bank mapped; carry SET and the window unchanged
;   uses:  A, B
;
; THE TICK IS HELD ACROSS THE WHOLE VISIT. page_select_and_verify holds it for
; a page switch because an NMI that jumps into a player on an unmapped page is
; how a paging fault becomes arbitrary execution. The bank is worse than an
; unmapped page - there is no code there at all - so the hold is taken here and
; released in bank_leave, not per switch.
;
; Refuses when bank_present says there is no bank, so a caller that forgets to
; test the flag cannot write into whatever page happens to be mapped.
; ---------------------------------------------------------------------------
bank_enter
                lda     >bank_present
                cmpa    #BANK_PRESENT_MAGIC
                bne     bank_enter_none

                lda     >current_page           ; what to put back afterwards,
                sta     >bank_saved_page        ; PAGE_UNKNOWN included

                lbsr    tick_hold               ; no player runs while the
                                                ; window holds no code
                lda     #PAGE_UNKNOWN           ; and no tick may match the
                sta     >current_page           ; window while it is the bank

                ldb     #BANK_NUMBER
                stb     >page_select
                lda     >PAGE_FIRST_BYTE
                cmpa    #BANK_MARK
                bne     bank_enter_failed
                andcc   #~CC_CARRY
                rts

bank_enter_failed
                ; The bank did not answer although the flag said it would - a
                ; board pulled mid-session, or a fault. Put the window back the
                ; way it was and say no, rather than leaving it on nothing.
                clra
                sta     >bank_present           ; and stop trusting it
                lbsr    bank_restore_page
                orcc    #CC_CARRY
                rts

bank_enter_none
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; bank_leave - put back the page that was mapped before bank_enter
;
;   uses:  A, B
; ---------------------------------------------------------------------------
bank_leave
                bsr     bank_restore_page
                rts

; Shared by bank_leave and the failure path above.
bank_restore_page
                ldb     >bank_saved_page
                cmpb    #PAGE_UNKNOWN
                beq     bank_restore_unknown
                lbsr    page_select_and_verify  ; re-arms the tick on success
                rts
bank_restore_unknown
                ; Nothing was mapped before, so nothing is mapped now. The tick
                ; stays held: tick_arm_update is page_select_and_verify's to
                ; call, and there is no page for it to arm.
                lda     #PAGE_UNKNOWN
                sta     >current_page
                rts

; ---------------------------------------------------------------------------
; WHAT SITS WHERE IN THE BANK
;
; Offset 0 is the board's, not ours. It reads $34 so that the instrument's own
; page-select read-back accepts the bank, and NOTHING HERE EVER WRITES IT - a
; write there would make the next boot's probe fail and the bank vanish.
;
; The signature says the bank has been seeded by this firmware. Without it a
; bank that has never been written holds whatever the board's SRAM powered up
; with, and copying that into the serial would be worse than having no bank at
; all.
; ---------------------------------------------------------------------------
BANK_SIG        equ     $0001           ; 4 bytes, "8904"
BANK_SIG_LEN    equ     4
BANK_SERIAL     equ     $0008           ; 3 bytes, the durable serial
BANK_OPTIONS    equ     $000B           ; 1 byte, the durable options
BANK_REGS       equ     $0010           ; the twelve save registers, from here

; ---------------------------------------------------------------------------
; bank_serial_put / bank_options_put - the durable copy of the per-unit bytes
;
;   bank_serial_put:  entry A = bits 23-16, X = bits 15-0
;   bank_options_put: entry A = the options byte
;   exit: carry SET if there is no bank and nothing was written
;   uses: A, B, X, Y, U
;
; Called by the wrapped writers in service_data.s BEFORE they touch the shadow,
; so that power lost between the two leaves the bank - the copy a boot believes
; - holding the new value rather than the old.
; ---------------------------------------------------------------------------
bank_serial_put
                stx     >bank_work+1
                sta     >bank_work
                ldx     #BANK_SERIAL
                ldu     #bank_work
                ldy     #3
                lbsr    bank_copy_in
                rts

bank_options_put
                sta     >bank_work
                ldx     #BANK_OPTIONS
                ldu     #bank_work
                ldy     #1
                lbsr    bank_copy_in
                rts

; ---------------------------------------------------------------------------
; bank_seed - stamp a bank that has never held anything, from the HM6264
;
;   uses:  A, B, X, Y, U
;
; The instrument's own serial and options are the authority the first time,
; which is the right direction: a board fitted to a working instrument takes
; what that instrument knows rather than overwriting it.
; ---------------------------------------------------------------------------
bank_seed
                lda     >serial_number
                ldx     >serial_number+1
                bsr     bank_serial_put
                bcs     bank_seed_none          ; no bank: writing the options
                lda     >installed_options      ; into one that is not there
                bsr     bank_options_put        ; would be the same refusal
                bcs     bank_seed_none          ; twice

                ; The signature last, so a power cut during the seed leaves the
                ; bank unsigned and the next boot seeds it again rather than
                ; believing half of one.
                ldx     #BANK_SIG
                ldu     #bank_sig_text
                ldy     #BANK_SIG_LEN
                lbsr    bank_copy_in
                rts
bank_seed_none
                rts

bank_sig_text   fcc     "8904"

; ---------------------------------------------------------------------------
; bank_load_shadow - the bank's per-unit bytes into $3FFC-$3FFF
;
;   uses:  A, B, X, Y, U
;
; Rule 2's addresses keep their values and their readers; this is what makes
; the bank the authority without moving them.
; ---------------------------------------------------------------------------
bank_load_shadow
                ldx     #BANK_SERIAL
                ldu     #bank_work
                ldy     #4                      ; serial's three and the
                lbsr    bank_copy_out           ; options byte, contiguous
                bcs     bank_load_done

                DISABLE_INTERRUPTS
                lda     >bank_work
                sta     >serial_number
                ldx     >bank_work+1
                stx     >serial_number+1
                lda     >bank_work+3
                sta     >installed_options
                RESTORE_INTERRUPTS
bank_load_done
                rts

; ---------------------------------------------------------------------------
; bank_probe - is there a bank, and does it hold what we left?
;
;   exit:  bank_present is $5A when the bank answered and was signed, and 0
;          otherwise. NO CARRY VERDICT: the flag is the answer.
;   uses:  A, B, X, Y, U
;
; It returned a carry as well, and two answers that can disagree is the fault
; this project keeps finding. Every caller reads the flag - bank_enter first
; of all - so the carry was a second copy of the same fact with nothing
; keeping it in step.
;
; Called once from the boot sequence, after the pages have been proved and
; BEFORE register_migrate, because the migration works on whichever store is
; the authority.
;
; The probe is the read-back and nothing else. On a One ROM the bank answers
; $34; on a 27513 the same write selects page 0 and answers $30; on a One ROM
; programmed with only four pages nothing answers $34 either. One test, three
; outcomes, all of them right.
; ---------------------------------------------------------------------------
bank_probe
                lda     #BANK_PRESENT_MAGIC     ; assume yes so bank_enter will
                sta     >bank_present           ; try; the read-back decides

                lbsr    bank_enter
                bcs     bank_probe_absent
                lbsr    bank_leave

                ; The bank answered. Has this firmware ever written it?
                ldx     #BANK_SIG
                ldu     #bank_work
                ldy     #BANK_SIG_LEN
                lbsr    bank_copy_out
                bcs     bank_probe_absent

                ldx     #bank_work
                ldu     #bank_sig_text
                ldb     #BANK_SIG_LEN
bank_probe_sig
                lda     ,x+
                cmpa    ,u+
                bne     bank_probe_seed
                decb
                bne     bank_probe_sig

                ; Signed, so the bank is the authority and the shadow is
                ; repaired from it. This is also what puts the serial back
                ; after a battery change: the HM6264 came up empty and the
                ; bank did not.
                lbsr    bank_load_shadow
                lbsr    bank_regs_load          ; and the twelve registers,
                rts                             ; before the migration reads
                                                ; them

bank_probe_seed
                ; It answers but this firmware has never written it - a board
                ; just fitted, or one whose SRAM came up unseeded. The
                ; instrument's own serial and options are the authority, which
                ; is the right direction on a first run.
                ;
                ; THE REGISTERS FIRST, BECAUSE bank_seed WRITES THE SIGNATURE.
                ; bank_seed puts the signature last of its own three writes, so
                ; that a power cut inside it leaves the bank unsigned and the
                ; next boot seeds it again rather than believing half of one -
                ; and that only holds if nothing is seeded AFTER it. This ran
                ; bank_seed first, so a power cut between the two left a SIGNED
                ; bank whose register block was still unwritten SRAM, and the
                ; next boot took the signed branch and let bank_regs_load copy
                ; that SRAM over the instrument's twelve working registers.
                ; The signature is the last byte written on this path now, which
                ; is what it was always meant to be.
                lbsr    bank_regs_seed          ; the array too: a board fitted
                                                ; to a working instrument keeps
                                                ; its twelve registers
                lbsr    bank_seed
                rts

bank_probe_absent
                clra
                sta     >bank_present
                rts

; ---------------------------------------------------------------------------
; THERE IS NO PER-BYTE ACCESSOR, deliberately.
;
; A bank_get/bank_put pair was written and then removed: nothing called either.
; Every user of the bank moves a block - the four per-unit bytes, or a 476-byte
; register slot - and a per-byte accessor is two page switches and a held tick
; for one byte. Anything that needs one byte can use bank_copy_out with a count
; of one.
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; bank_copy_out - bank to RAM
; bank_copy_in  - RAM to bank
;
;   entry: X = the offset within the bank
;          U = the RAM address
;          Y = how many bytes, 1 to $4000
;   exit:  carry SET if there is no bank and nothing was copied
;   uses:  A, B, X, Y, U
;
; ONE page switch for the whole block, which is what makes a 476-byte register
; slot affordable: bank_get per byte would be 952 switches and a held tick for
; all of them.
; ---------------------------------------------------------------------------
bank_copy_out
                lbsr    bank_enter
                bcs     bank_copy_none
                leax    PAGE_WINDOW,x
bank_copy_out_byte
                lda     ,x+
                sta     ,u+
                leay    -1,y
                bne     bank_copy_out_byte
                lbsr    bank_leave
                andcc   #~CC_CARRY
                rts

bank_copy_in
                lbsr    bank_enter
                bcs     bank_copy_none
                leax    PAGE_WINDOW,x
bank_copy_in_byte
                lda     ,u+
                sta     ,x+
                leay    -1,y
                bne     bank_copy_in_byte
                lbsr    bank_leave
                andcc   #~CC_CARRY
                rts

bank_copy_none
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; THE BANK'S COPY OF THE TWELVE REGISTERS
;
; The array in the HM6264 stays exactly where it is and keeps every reader and
; writer it has. It is the WORKING copy; the bank holds the DURABLE one.
;
; That shape rather than moving the array wholesale is what keeps this change
; small enough to trust on a running instrument: register_save, register_recall,
; register_probe and register_migrate are untouched inside, and the mirroring
; happens at their edges. A slot is copied out after it is saved, and the whole
; block is copied in at boot, before the migration reads it.
;
; WITH NO BANK every one of these returns having done nothing, and the array is
; what it has always been.
; ---------------------------------------------------------------------------

; bank_regs_put - one slot, RAM to bank
;
;   entry: B = the register number, 0 to REGISTER_COUNT-1
;   uses:  A, B, X, Y, U
; THE FLAG IS NOT TESTED HERE. bank_copy_in and bank_copy_out call
; bank_enter, which refuses when there is no bank and returns carry set, so a
; test here is the same question asked twice - and it cost 21 bytes of an image
; that was 16 over its part. The bounds test below stays: nothing else makes it.
bank_regs_put
                cmpb    #REGISTER_COUNT
                bhs     bank_regs_none

                lbsr    register_address        ; X = the slot in the HM6264
                tfr     x,u                     ; the copy's RAM side

                ; AND ITS OFFSET IN THE BANK IS A SUBTRACTION, not a walk.
                ; register_address has already done the multiply, and the two
                ; arrays have the same stride - so the bank offset is the RAM
                ; address less the distance between the two bases. The first
                ; version stepped a loop to arrive at the number it was already
                ; holding, and put the image 35 bytes over its part.
                tfr     x,d
                subd    #REGISTER_BASE-BANK_REGS
                tfr     d,x
                ldy     #REGISTER_SLOT
                lbra    bank_copy_in            ; its rts is this one's

bank_regs_none
                rts

; bank_regs_load - the whole block, bank to RAM
;
;   uses:  A, B, X, Y, U
;
; Called from the boot probe, before register_migrate: the migration converts
; whatever the array holds, so the array has to hold the bank's contents by
; then or the migration would convert the stale RAM and then be overwritten.
bank_regs_load
                ldx     #BANK_REGS
                ldu     #REGISTER_BASE
                ldy     #REGISTER_COUNT*REGISTER_SLOT
                lbra    bank_copy_out

; bank_regs_seed - the whole block, RAM to bank
;
;   uses:  A, B, X, Y, U
;
; For a bank that answers but has never been written by this firmware. What
; the instrument already has is the authority the first time.
bank_regs_seed
                ldx     #BANK_REGS
                ldu     #REGISTER_BASE
                ldy     #REGISTER_COUNT*REGISTER_SLOT
                lbra    bank_copy_in
