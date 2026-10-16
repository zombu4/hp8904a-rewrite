; ===========================================================================
; registers.s - the save and recall registers
;
; Twelve numbered registers holding a complete instrument setting each. The
; front panel's SAVE and RECALL keys write and read them; the stock firmware
; offers 0 to 11 and says so on its own screen ('0 - 11 Are Valid').
;
; THEY LIVE IN BATTERY-BACKED RAM, which makes them the second thing in this
; instrument that survives a power cycle and cannot be regenerated. They are
; NOT in the region ram.inc protects - that holds the serial number, the
; options and the calibration - but losing a bench setup somebody spent an
; afternoon on is still losing something, so a register write is an
; all-or-nothing copy rather than a field-by-field update that can be
; interrupted halfway.
; ===========================================================================

REGISTER_COUNT  equ     12              ; 0 to 11, as the panel says
; WHAT A REGISTER HOLDS, and it is no longer only the channels.
;
; It saved live_setting and nothing else - the four channel records and the
; globals - so recalling a register brought the channels back and left the
; tone sequence, the digital patterns and the hop table exactly as they were.
; The stock does not: save_sequence_setup ($6CD7) and recall_sequence_setup
; ($6D19) move TWO blocks per slot, 425 bytes to $24E6 and 257 bytes to
; $3C10, the second of those being the sixteen time records and what follows.
;
; I once wrote this down as blocked, on the grounds that widening a slot makes
; every register an instrument already holds unreadable. That was wrong, and
; wrong in a way worth keeping: this firmware's slots already differ
; from the stock's 425 bytes, in the same span, so a register written by the
; firmware in the instrument is ALREADY unreadable here. Widening breaks
; nothing that was not broken, and there is room - the span $268F-$3A7A is
; 5,100 bytes, which is twelve of the stock's 425.
;
; The blocks are listed in a table rather than copied twice, because two
; copy loops drift and the recall half has to walk exactly what the save half
; wrote.
REGISTER_LIVE   equ     64              ; the channel records and the globals
REGISTER_HOP    equ     128             ; the sixteen hop slots
REGISTER_TONE   equ     237             ; THE TONE SEQUENCE AS THE INSTRUMENT
                                        ; HAS IT, one contiguous run: sixteen
                                        ; tones of 3 bytes of tuning word (48),
                                        ; sixteen of 4 bytes of On/Off timer
                                        ; counts (64), and the 250-step
                                        ; playlist packed two steps to a byte
                                        ; (125). It was 80 - sixteen
                                        ; self-contained five-byte steps.
                                        ;
                                        ; IT FITS IN ONE SPAN. A span's length
                                        ; is one byte (register_save does
                                        ; `ldb ,u+` then `decb`), and I said in
                                        ; docs/tone-port-stage2.md that 237
                                        ; could not be expressed that way.
                                        ; That was wrong: 237 is under 256. No
                                        ; span here reaches 255, so neither the
                                        ; count nor the block needed splitting.
REGISTER_SIGNS  equ     4               ; ampl_signs: the four channel level
                                        ; signs, the stock's record+$14, which
                                        ; its 425-byte copy carries inside the
                                        ; record and this 12-byte record has
                                        ; no room for
REGISTER_HOPSIGNS equ   16              ; hop_signs: the sixteen hop level
                                        ; signs, the stock's hop record+10,
                                        ; likewise inside its $24E6-$268E image
REGISTER_SEQ    equ     16              ; A FORMAT-2 CONSTANT AND NOTHING ELSE
                                        ; NOW. It was the sixteen bytes of
                                        ; `digital_sequence`, the rewrite's own
                                        ; sixteen-step digital model, and that
                                        ; model is gone: the instrument's
                                        ; pattern is 125 bytes of one bit
                                        ; stream (digital_pattern_ram, and
                                        ; register_seq_stage_dig below saves
                                        ; it). The number survives because
                                        ; MIG_TAIL_BYTES measures a format-2
                                        ; and format-3 slot, and what those
                                        ; slots hold on a battery-backed board
                                        ; today cannot be changed by deciding
                                        ; the model was wrong.
REGISTER_HOPFLAGS equ   2               ; hop_saved_flags: the snapshot of
                                        ; the four hop function enables -
                                        ; mode_flags and hop_running as last
                                        ; snapshotted. The stock's $267F/$2681
                                        ; lie inside the $24E6-$268E block its
                                        ; recall copies ($52B2-$52F2), and
                                        ; l5372-l53f4 ($5372-$53F4) re-applies
                                        ; the enables from them once the copy
                                        ; is in; see hop_saved_flags in
                                        ; scratch.inc and hop_reapply in
                                        ; page0_hop.s
REGISTER_SEQLEN equ     1               ; ONE RESERVED BYTE. It was
                                        ; sequence_length, the digital
                                        ; sequence's step count; that model is
                                        ; gone and the span is kept rather
                                        ; than moving every register by a
                                        ; byte. See register_pad in
                                        ; scratch.inc
                                        ; still: the aliased slot replaces the
                                        ; two SEQUENCE spans and nothing else
REGISTER_TONEEND equ    2               ; tone_end: HOW MANY OF THE STEPS PLAY.
                                        ; It was not saved at all until
                                        ; 2026-09-07, while the digital
                                        ; sequence's sequence_length was - so a
                                        ; four-step tone sequence recalled as
                                        ; four steps of data with whatever
                                        ; tone_end happened to hold. The stock
                                        ; keeps its Seq End ($3D0F) inside the
                                        ; 257-byte block save_sequence_setup
                                        ; ($6CD7) copies, so this is the stock's
                                        ; own behaviour, restored.
REGISTER_SEQ_STEREO equ REGISTER_SEQBLOCK-ST_SAVED_WIDE ; 245: FM Stereo's
                                        ; four wide values sit in the LAST
                                        ; twelve bytes of the sequence span.
                                        ; The longest model staged there is a
                                        ; kept tone slot, 1+237+4 = 242 bytes,
                                        ; and a kept digital one is 1+154+1, so
                                        ; both end below 245 and nothing
                                        ; register_seq_stage writes reaches
                                        ; them. A slot saved by an earlier
                                        ; build holds whatever was there, and
                                        ; is never read: only a slot whose
                                        ; record is mode_stereo, which no
                                        ; earlier build wrote, is unstaged
REGISTER_SIZE   equ     REGISTER_LIVE+REGISTER_HOP+REGISTER_SEQBLOCK+REGISTER_SEQLEN+REGISTER_SIGNS+REGISTER_HOPSIGNS+REGISTER_HOPFLAGS+REGISTER_TONEEND
                                        ; channel records of 12 bytes plus
                                        ; 16 for the settings that are not
                                        ; per-channel, the hop table, the
                                        ; two sequences, the sequence length,
                                        ; the twenty sign bytes, the two
                                        ; hop-enable snapshot bytes and
                                        ; tone_end: 470, and 472 with the
                                        ; marker. It was 311 before tone_end
                                        ; joined the spans, 313 after, and 470
                                        ; once the tone span grew from 80 to
                                        ; 237 for the ported model.

; WHERE THE REGISTERS LIVE, AND WHY IT IS NOT SCRATCH.
;
; The stock array is twelve slots of 425 bytes running $268F-$3A7A. That was
; established by reading its save path: save_state_register (a2u13_page2
; $544D) walks it with a descriptor whose stride word is $01A9 = 425, and
; $268F + 12*425 - 1 = $3A7A, which is exactly where the next variable in use
; begins. Neither ramrefs.py nor ramsafety.py declares that span, so nothing
; in this project would have complained.
;
; THIS ARRAY NO LONGER STARTS AT $268F. It used to, deliberately, so that a
; span already spoken for on every instrument was not left holding something
; else. It now ENDS at $3A7A instead and grows downwards from there, because a
; slot has to reach about 472 bytes once the tone sequence is the stock's 250
; steps and twelve of those do not fit above $268F. The owner's word,
; 2026-09-07: "well since we are doing u12 and u13
; we can move code around as we please".
;
; THE FORMAT CHANGED, AND OLD SETUPS ARE CONVERTED RATHER THAN LOST.
; register_migrate runs once at boot, finds format 1 slots at $268F, and
; rewrites them at the new base in the new shape - his instruction the same
; day: "it could also do a ram migration and on first start check if it got
; the new ram config or the old one then migrate the data to the right spot".
; A slot it cannot account for is left reading as empty rather than recalled
; with the wrong layout, and register_valid still checks the marker before
; anything is recalled.
; THE MARKER CARRIES A FORMAT NUMBER, so a slot written by an older ROM is
; REFUSED rather than read with the wrong layout. Before 2026-09-07 it was the
; single constant $8904 with no version in it, so any future change to the
; spans would have been silently misread: the marker still matched, the payload
; no longer meant the same thing.
;
; Bump REGISTER_FORMAT whenever a span is added, removed, resized or reordered,
; or whenever REGISTER_BASE moves. The high byte is $8A and never changes, so a
; version can never collide with the retired $8904 - that value is format 1 and
; must not be reused.
;
;   format 1  $8904  base $268F, 8 spans, 313 bytes a slot. Retired.
;   format 2  $8A02  base derived, 9 spans - tone_end joined them. Retired.
;   format 3  $8A03  the same 9 spans, with the tone span grown from 80 to
;                    237 when the sixteen-tone list and the 250-step playlist
;                    replaced sixteen self-contained steps. A format 2 slot is
;                    CONVERTED into it, not discarded - see register_migrate.
;   format 4  $8A04  NINE spans, and the indentation of this row was wrong
;                    with the count. The tone sequence's 237, the digital one's
;                    16 became ONE aliased 257-byte slot holding whichever
;                    sequence was live, which is what the instrument does and
;                    what lets a saved digital pattern be the stock's full
;                    size; it takes TWO of the nine entries, because 257 will
;                    not fit in a one-byte length. sequence_length and
;                    tone_end keep their own spans, so the count did not fall.
;                    A format 3 slot is CONVERTED into it - see
;                    register_migrate. Counted from register_blocks itself:
;                    nine fdb/fcb pairs, and REGISTER_BLOCKS is 9.
REGISTER_FORMAT equ     4
REGISTER_MARK   equ     $8A00+REGISTER_FORMAT
REGISTER_MARK_V1 equ    $8904           ; what format 1 wrote, recognised by
                                        ; register_migrate and by nothing else
REGISTER_BASE_V1 equ    $268F           ; and where it wrote it
REGISTER_SIZE_V1 equ    311             ; its payload: the eight spans, which
                                        ; are the first eight of this format's
                                        ; nine, at the same offsets
REGISTER_SLOT_V1 equ    REGISTER_SIZE_V1+2 ; plus its own marker
REGISTER_MARK_V2 equ    $8A02           ; format 2: the same nine spans with a
REGISTER_BASE_V2 equ    $2BB7           ; tone span of 80 rather than 237, and
REGISTER_SLOT_V2 equ    315             ; a base derived from the smaller slot
REGISTER_MARK_V3 equ    $8A03           ; format 3: nine spans, the tone one
REGISTER_SIZE_V3 equ    470             ; 237 and the digital one 16, kept
REGISTER_SLOT_V3 equ    REGISTER_SIZE_V3+2 ; apart. 472 with its marker
REGISTER_BASE_V3 equ    $245B           ; and where twelve of those started

; WHERE THE FORMAT-3 FIRMWARE KEPT ITS STAMP, which is not where this one
; keeps its own. `git show a9450c2^:hp8904a-rewrite/common/ram.inc` line 155
; reads `register_format_stamp equ $242B` in the tree whose REGISTER_FORMAT
; was 3, and roms/README.md records that build running on hardware and
; "rewriting battery RAM into format 3". So the instrument in the field has
; $8A03 at $242B, and register_migrate has to look there.
;
; IT IS AN EQUATE HERE RATHER THAN A CELL IN ram.inc BECAUSE IT IS INSIDE THE
; ARRAY. $242B is REGISTER_BASE - slot 0's marker in this format - and
; hp8904a-rewrite/tests/test_scratch_layout.py refuses any ram.inc cell that
; lands in REGISTER_BASE..REGISTER_TOP, correctly. Nothing writes through this
; name; it is read once, at boot, by register_migrate.
REGISTER_STAMP_V3 equ   $242B

REGISTER_BLOCKS equ     7               ; how many spans the TABLE carries.
                                        ; SEVEN, not nine: the aliased
                                        ; 257-byte sequence slot is not a
                                        ; table entry any more. It was two
                                        ; entries of 128 and 129 - 257 will
                                        ; not fit in a one-byte length - both
                                        ; copying out of a register_seq_block
                                        ; that register_seq_stage had just
                                        ; filled from the live model. That
                                        ; buffer is gone and the staging goes
                                        ; straight into the slot, so the slot
                                        ; still holds nine spans and the table
                                        ; describes seven of them.
                                        ; sequence_length and tone_end keep
                                        ; their own spans.
REGISTER_BLOCKS_BELOW equ 2             ; live_setting and hop_table, the two
                                        ; spans in front of the aliased slot.
                                        ; 64+128 = 192 = V4_KIND_OFF, which is
                                        ; what makes the split exact rather
                                        ; than a place the code happens to
                                        ; stop.
REGISTER_BLOCKS_ABOVE equ REGISTER_BLOCKS-REGISTER_BLOCKS_BELOW
                                        ; register_pad, the two sign arrays,
                                        ; the hop flags and tone_end: 25
                                        ; bytes, which is V3_TAIL_LEN and
                                        ; lands at V4_TAIL_OFF = 449.
                                        ; FIVE once the tone sequence grew to
                                        ; five bytes a step and the digital
                                        ; one moved out of its way, so the two
                                        ; were no longer one contiguous span;
                                        ; SEVEN with the two sign arrays,
                                        ; which live ABOVE live_setting so
                                        ; a keep-state power-on preserves
                                        ; them, as the stock preserves the
                                        ; sign inside its channel record;
                                        ; EIGHT with the hop-enable snapshot,
                                        ; which lives there for the same
                                        ; reason (hop_saved_flags);
                                        ; NINE with tone_end, which was not
                                        ; saved at all before 2026-09-07.

REGISTER_SLOT   equ     REGISTER_SIZE+2 ; THE MARKER NEEDS ITS OWN TWO BYTES.
                                        ; The stride was REGISTER_SIZE, and
                                        ; REGISTER_SIZE is exactly the
                                        ; live_setting block a slot holds - so
                                        ; there was no room for the marker at
                                        ; all. register_save wrote it at the
                                        ; slot base and then began its 64-byte
                                        ; copy at that same base, destroying it
                                        ; on the first two iterations, and
                                        ; register_recall's `cmpu
                                        ; #REGISTER_MARK` therefore refused
                                        ; every saved register with
                                        ; ERR_VALUE_RANGE. Nothing could ever
                                        ; be recalled.
                                        ;
                                        ; 12 slots x REGISTER_SLOT = 313
                                        ; bytes is 3,756, so the array runs
                                        ; $268F-$353A and stays inside the
                                        ; battery-backed region; the serial
                                        ; and options at $3FEE-$3FFF are
                                        ; 2,740 bytes above the last byte
                                        ; written. This comment once held
                                        ; three stale numbers at once - 66,
                                        ; 792 and 22,088 - from a layout two
                                        ; growths of the slot ago, and 291,
                                        ; 3,492 and $3432 from the growth
                                        ; before the sign arrays.

; WHERE THE ARRAY SITS, DERIVED RATHER THAN WRITTEN DOWN.
;
; The top is pinned: rule 2 names $268F-$3A7A as the twelve save/recall
; registers, and $3A7A is the last byte of battery RAM the array may use. The
; BASE is now computed backwards from that top, so the array always ends
; exactly at $3A7A and the base moves on its own when a slot grows. Every
; earlier growth of the slot needed the comment above rewritten with new
; numbers, and three of them were wrong at once.
;
; It moves DOWN, below the $268F rule 2 quotes, on the owner's recorded word:
; 2026-09-07, "well since we are doing u12 and u13 we can
; move code around as we please" - to fit twelve full-size registers once the
; tone sequence is the stock's 250 steps. Rule 2's per-unit bytes at
; $3FEE-$3FFF and the trust signature at $2000-$203B do not move, and all
; twelve registers stay.
;
; Nothing may be declared inside REGISTER_BASE..REGISTER_TOP. The layout gate
; in hp8904a-rewrite/tests/test_scratch_layout.py checks that, because a
; collision here would be a save writing over a live variable.
REGISTER_TOP    equ     $3A7A
REGISTER_BASE   equ     REGISTER_TOP+1-REGISTER_COUNT*REGISTER_SLOT

; The highest slot of each format, which is where register_migrate starts.
; Written as three equates rather than one bracketed expression because
; firmware/asm6809.py has no parentheses - it honours * over + correctly, so
; these are exact, but it cannot parse a grouped sub-expression. That gap is
; real and is written up in docs/tone-port-stage1.md; these names also read
; better than the arithmetic did.
REGISTER_LAST   equ     REGISTER_COUNT-1
REGISTER_TOPSLOT equ    REGISTER_BASE+REGISTER_LAST*REGISTER_SLOT
REGISTER_TOPSLOT_V1 equ REGISTER_BASE_V1+REGISTER_LAST*REGISTER_SLOT_V1

; ---------------------------------------------------------------------------
; register_address - where a register's bytes live
;
;   entry: B = the register number
;   exit:  X = its first byte
;   uses:  A, B, X
; ---------------------------------------------------------------------------
register_address
                ; SIXTEEN-BIT STEPPING, because a slot no longer fits a byte.
                ; This did `ldb #REGISTER_SLOT / abx`, which is right while a
                ; slot is under 256 bytes and silently wrong the moment it is
                ; not - and widening a register to carry the hop table took it
                ; to 275. lwasm refused the immediate and asm6809.py took it,
                ; so the two-assembler rule is what caught it.
                ldx     #REGISTER_BASE
                tstb
                beq     register_address_done
                pshs    b
register_address_step
                pshs    b
                tfr     x,d
                addd    #REGISTER_SLOT          ; the SLOT, not the payload:
                tfr     d,x                     ; each slot carries its marker
                puls    b
                decb
                bne     register_address_step
                puls    b
register_address_done
                rts

; ---------------------------------------------------------------------------
; register_valid - is this a register the instrument has?
;
;   entry: B = the register number
;   exit:  carry CLEAR if it is valid
;   uses:  nothing
; ---------------------------------------------------------------------------
register_valid
                cmpb    #REGISTER_COUNT
                blo     register_valid_yes
                orcc    #CC_CARRY
                rts
register_valid_yes
                andcc   #~CC_CARRY
                rts

; The spans a register carries, each an address and a byte count. Save walks
; it one way and recall the other, so the two cannot disagree about what a
; slot contains.
;
; THE TWO SIGN ARRAYS ARE SPANS OF THEIR OWN because the stock keeps them
; inside the records its register copies: page 0's enter_channel_config_mode
; ($528F) recalls a register by copying $01A9 bytes from $268F+425n to $24E6
; at $52B2-$52F2, which is the four 35-byte channel records at $24F5 with
; their sign character at +$14 and the sixteen 15-byte hop records at $2581
; with theirs at +10, and then re-applies every channel's destination
; ($5372 onward, set_channel_destination $78BF) so the levels are programmed
; with the recalled signs. This firmware's 12-byte record has no sign byte -
; ampl_signs and hop_signs hold them, below live_setting - so a register
; that did not carry them recalled every dc level as positive.
;
; sequence_length is its own one-byte span rather than being swept up with the
; block above it, because the bytes between them are PLAYER state - tone_state,
; the positions, the bit index. Restoring those would recall a sequence that
; believes it is running with no tick installed.
register_blocks
                fdb     live_setting
                fcb     REGISTER_LIVE
                fdb     hop_table
                fcb     REGISTER_HOP
                ; ONE SLOT FOR WHICHEVER SEQUENCE WAS LIVE, which is what
                ; the instrument does - see register_seq_block in
                ; common/ram.inc. It replaces two spans, the tone sequence's
                ; 237 and the digital one's 16, and nothing else: 253 becomes
                ; 257, which is +4 a register and +48 across the twelve.
                ; TWO ENTRIES because a span's length is ONE BYTE -
                ; register_save does `ldb ,u+` then `decb` - and 257 does not
                ; fit in one.
                ;
                ; AND IT IS NO LONGER IN THIS TABLE AT ALL. It was two entries
                ; here, 128 and 129 - 257 will not fit in a one-byte length -
                ; copying 257 bytes out of register_seq_block, a buffer
                ; register_seq_stage had filled from the live model one
                ; instruction earlier. The same bytes twice, through 257 bytes
                ; of battery RAM standing in the stack's way.
                ;
                ; register_save now calls register_seq_stage with X already
                ; pointing at the slot's own sequence span - payload offset
                ; REGISTER_LIVE+REGISTER_HOP = 192, which is what V4_KIND_OFF
                ; says - and steps X on by REGISTER_SEQBLOCK afterwards;
                ; register_recall_copy calls register_seq_unstage the same way.
                ; THE SLOT'S LAYOUT IS UNCHANGED, so a register written by an
                ; earlier build reads back exactly as it did and register_mig_v3
                ; converts a format-3 slot into the same shape as before.
                fdb     register_pad
                fcb     REGISTER_SEQLEN
                fdb     ampl_signs              ; the four level signs, the
                fcb     REGISTER_SIGNS          ; stock's record+$14
                fdb     hop_signs               ; the sixteen hop level
                fcb     REGISTER_HOPSIGNS       ; signs, hop record+10
                fdb     hop_saved_flags         ; the hop-enable snapshot,
                fcb     REGISTER_HOPFLAGS       ; the stock's $267F/$2681
                fdb     tone_end                ; HOW MANY STEPS PLAY. Its own
                fcb     REGISTER_TONEEND        ; span still: the aliased slot
                                                ; replaces the two SEQUENCE
                                                ; spans and nothing else
                                                ; sequence_length is: the bytes
                                                ; around it are player state -
                                                ; tone_state, tone_position -
                                                ; and restoring those recalls a
                                                ; sequence that believes it is
                                                ; running with no tick installed

; ---------------------------------------------------------------------------
; register_seq_stage - fill the aliased slot from whichever sequence is live
;
;   entry: X = the slot's sequence span, payload offset V4_KIND_OFF
;   exit:  X somewhere inside that span - the CALLER steps it on by
;          REGISTER_SEQBLOCK, because how far this walks depends on which
;          model was live and SEQKIND_NONE walks one byte
;   uses:  A, B, X, U
;
; The instrument's two sequence screens copy their own block to one address
; before the record is written - $3C02 for 170 bytes on page 2, $3C10 for 257
; on page 1, both to $2581 - so the record's slot holds whichever screen saved
; last. This is that, with byte 0 saying which, because this firmware's two
; models do not overlap in RAM the way the instrument's do.
;
; X IS THE CALLER'S NOW. This used to load X with #register_seq_block and
; write into 257 bytes of battery RAM that register_save then copied into the
; slot - two copies of one thing, and the buffer was the biggest single taker
; of the stack's 452 bytes. register_save passes the slot itself.
;
; NEITHER MODEL FILLS ALL 257. The tone run is 1+237+4 and the digital runs
; come to 1+154+1, so the bytes above them keep whatever the slot already
; held - which is what they did when the buffer was there, and nothing reads
; them: register_seq_unstage walks exactly the same runs in the same order.
;
; AND THE KIND WRITTEN IS THE KEPT ONE. A tone slot carries tone_end and
; tone_cursor after its run and a digital slot digital_running after its
; runs, because the instrument's recall puts all three back - measured on the
; stock 2026-09-16 (docs/mode-reentry.md) - and the byte says so, so a slot
; written before these were added still reads as SEQKIND_TONE or
; SEQKIND_DIGITAL and restores what it always did.
;
; A register saved before either screen has been opened carries SEQKIND_NONE
; and its payload is not read back.
; ---------------------------------------------------------------------------
register_seq_stage
                lda     >seq_kind_live
                cmpa    #SEQKIND_TONE
                beq     register_seq_stage_tone
                cmpa    #SEQKIND_DIGITAL
                beq     register_seq_stage_dig
                sta     ,x+                     ; anything else: that byte
                rts                             ; and no payload
register_seq_stage_tone
                lda     #SEQKIND_TONE_KEPT
                sta     ,x+
                ldu     #tone_freq              ; the tuning words, the timer
                ldb     #REGISTER_TONE          ; counts and the playlist, one
                lbsr    register_seq_copy       ; contiguous run
                ldu     #tone_end               ; $3D0F, the playlist's end
                ldb     #$02
                lbsr    register_seq_copy
                ldu     #tone_cursor            ; $3D0D, the step the cursor
                ldb     #$02                    ; is on
                lbra    register_seq_copy
; THE DIGITAL BLOCK IS THE STOCK'S $3C02-$3CAB, 170 bytes, which
; save_state_register ($544D) copies out whole. Those bytes are one contiguous
; run on the instrument and five runs here, because this firmware groups its
; scratch by screen rather than by mode; the CONTENTS are the same set:
;
;   $3C21..$3C9D  the 125-byte pattern          digital_pattern_ram
;   $3C20         the base                      digital_base
;   $3CA2,$3CA4   the cursor and the end        digital_index..digital_window
;   $3CA6,$3CA8   their bit indices             digital_index_bit..
;   $3CAA         the player's end bit          digital_last_bit
;   $3C9E         the bit period                digital_period
;   $3C03,$3C04   single-shot and manual        digital_single, digital_manual
;   $3C11,$3C12   the two level signs           digital_sign_mark/_space
;
; digital_max and digital_count are derived from the base and are saved with
; the indices they sit beside rather than being recomputed on recall: they are
; inside the run, and leaving a hole to skip them would cost more bytes than
; they take.
;
;   $3C02         whether it is running         digital_running, after the
;                                               rest, in a SEQKIND_DIGITAL_KEPT
;                                               slot
register_seq_stage_dig
                lda     #SEQKIND_DIGITAL_KEPT
                sta     ,x+
                ldu     #digital_pattern_ram
                ldb     #DIGITAL_PATTERN_BYTES
                lbsr    register_seq_copy
                ldu     #digital_base
                ldb     #$01
                lbsr    register_seq_copy
                ldu     #digital_index          ; index, end, max, window
                ldb     #$08
                lbsr    register_seq_copy
                ldu     #digital_bit_index      ; the player's counter, both
                ldb     #$0C                    ; bit indices, the count, the
                lbsr    register_seq_copy       ; column and the field pointer
                ldu     #digital_last_bit
                ldb     #$02
                lbsr    register_seq_copy
                ldu     #digital_period
                ldb     #$02
                lbsr    register_seq_copy
                ldu     #digital_single
                ldb     #$01
                lbsr    register_seq_copy
                ldu     #digital_manual
                ldb     #$01
                lbsr    register_seq_copy
                ldu     #digital_sign_mark      ; and digital_sign_space, the
                ldb     #$02                    ; byte after it
                lbsr    register_seq_copy
                ldu     #digital_running        ; $3C02
                ldb     #$01
                lbra    register_seq_copy

; ---------------------------------------------------------------------------
; register_seq_unstage - put the slot back into the model it came from
;
;   entry: U = the slot's sequence span, payload offset V4_KIND_OFF
;   exit:  U somewhere inside that span, as register_seq_stage leaves X
;   uses:  A, B, X, U
;
; The kind byte decides, so a register holding a tone sequence never lands in
; the digital model or the other way about. A slot that was never saved -
; SEQKIND_NONE - leaves both models alone rather than filling one with
; whatever the battery RAM held.
;
; U IS THE CALLER'S NOW, for the reason register_seq_stage's X is: this read
; out of register_seq_block, which register_recall_copy had just filled from
; the slot. It reads the slot.
; ---------------------------------------------------------------------------
register_seq_unstage
                lda     ,u+
                cmpa    #SEQKIND_TONE
                beq     register_seq_unstage_tone
                cmpa    #SEQKIND_TONE_KEPT
                beq     register_seq_unstage_kept
                cmpa    #SEQKIND_DIGITAL
                beq     register_seq_unstage_dig
                cmpa    #SEQKIND_DIGITAL_KEPT
                lbeq    register_seq_unstage_dig_kept
                rts
; AND THE MODEL IT FILLS IS THE LIVE ONE FROM THEN ON, on every path below:
; the instrument has one block and cannot disagree with itself, and a
; seq_kind_live left naming the other model - or nothing, after a keep-state
; power-on - made the next save stage the wrong one.
register_seq_unstage_tone
                ldb     #SEQKIND_TONE
                stb     >seq_kind_live
                ldx     #tone_freq
                ldb     #REGISTER_TONE
                lbra    register_seq_back
; A KEPT TONE SLOT: the same run, then the end and the cursor. The tone
; player and the window index with both, and a slot is battery RAM, so each
; is checked as it goes back - an end past the playlist's last step is not
; one this firmware writes and becomes that last step, and a cursor past the
; end becomes step 0.
register_seq_unstage_kept
                ldb     #SEQKIND_TONE
                stb     >seq_kind_live
                ldx     #tone_freq
                ldb     #REGISTER_TONE
                lbsr    register_seq_back
                ldd     ,u++                    ; tone_end
                cmpd    #TONE_PLAYLIST-1
                bls     register_seq_unstage_end
                ldd     #TONE_PLAYLIST-1
register_seq_unstage_end
                std     >tone_end
                ldd     ,u++                    ; tone_cursor
                cmpd    >tone_end
                bls     register_seq_unstage_cursor
                ldd     #$0000
register_seq_unstage_cursor
                std     >tone_cursor
                rts
; THE SAME RUNS IN THE SAME ORDER, which is the only thing that makes the
; block readable: register_seq_copy walks U forward through the slot and this
; walks it forward again, so a run added above without a run added here would
; misalign every run after it.
register_seq_unstage_dig
                ldb     #SEQKIND_DIGITAL
                stb     >seq_kind_live
                ldx     #digital_pattern_ram
                ldb     #DIGITAL_PATTERN_BYTES
                lbsr    register_seq_back
                ldx     #digital_base
                ldb     #$01
                lbsr    register_seq_back
                ldx     #digital_index
                ldb     #$08
                lbsr    register_seq_back
                ldx     #digital_bit_index
                ldb     #$0C
                lbsr    register_seq_back
                ldx     #digital_last_bit
                ldb     #$02
                lbsr    register_seq_back
                ldx     #digital_period
                ldb     #$02
                lbsr    register_seq_back
                ldx     #digital_single
                ldb     #$01
                lbsr    register_seq_back
                ldx     #digital_manual
                ldb     #$01
                lbsr    register_seq_back
                ldx     #digital_sign_mark
                ldb     #$02
                lbra    register_seq_back
; A KEPT DIGITAL SLOT: the same runs, then whether the sequence was running,
; which the mode entry restarts as $7187 restarts it from $3C02. Only the one
; value digital_run stores goes back.
register_seq_unstage_dig_kept
                lbsr    register_seq_unstage_dig
                lda     ,u+                     ; digital_running
                beq     register_seq_unstage_run
                lda     #$01
register_seq_unstage_run
                sta     >digital_running
                rts

; ---------------------------------------------------------------------------
; register_seq_copy - B bytes from U into X, both advancing
; register_seq_back - the same, and it is the same loop: the caller decides
;                     which way round the two pointers are
;
;   uses:  A, B, X, U
; ---------------------------------------------------------------------------
register_seq_copy
                lda     ,u+
                sta     ,x+
                decb
                bne     register_seq_copy
                rts

; THE SECOND NAME IS AN EQU, NOT A SECOND LABEL. Two labels on one line of
; code read to tests/test_no_stubs.py as a routine that returns having done
; nothing, because the first has no instruction of its own before the next
; label begins. The equ says the same thing and says it after the body, which
; is where asm6809.py - one pass over the equs - needs the name it references
; to be already defined.
register_seq_back equ   register_seq_copy

; ---------------------------------------------------------------------------
; register_save - copy the live setting into a register
;
;   entry: B = the register number
;   exit:  carry SET if the number is out of range and nothing was written
;   uses:  A, B, X, Y, U, U, U
;
; Interrupts are masked across the copy. A handler that read the register
; halfway through would see a setting that never existed - half the old one
; and half the new - and RECALL would then load it.
; ---------------------------------------------------------------------------
register_save
                pshs    b
                lbsr    register_valid
                bcs     register_save_bad
                puls    b

                lbsr    register_address        ; X = the destination
                DISABLE_INTERRUPTS
                ; AND dds_lock, BECAUSE DISABLE_INTERRUPTS DOES NOT STOP THE
                ; PLAYER. The sequence player runs from NMI, and boot.s says
                ; so in its own words: DISABLE_INTERRUPTS "masks the MASKABLE
                ; interrupts and does nothing whatever to NMI". So the mask
                ; above keeps IRQ and FIRQ out of this copy and the player
                ; walked straight through it - reading a tone step from a
                ; block that was half-written, or writing one into a block
                ; being read.
                ;
                ; dds_lock is what the NMI path actually tests: it finds the
                ; lock held and defers its step to the next time-out, one
                ; period late and correct. inc/dec rather than a flag, so it
                ; nests with any caller already holding it.
                ;
                ; The window is 313 bytes today and grows to about 472 once a
                ; slot carries the sixteen-tone list and a 250-step playlist,
                ; so this gets worse, not better, if it is left.
                inc     >dds_lock
                ; THE MARKER, so an unwritten slot can be told from a written
                ; one. REGISTER_MARK was declared and nothing ever wrote or
                ; read it, so register_recall could not fail, the caller's
                ; "empty" branch was dead, and recalling a slot nobody had
                ; saved copied 64 bytes of uninitialised battery RAM into the
                ; live state - which register_apply then programmed onto the
                ; chip.
                ldu     #REGISTER_MARK
                stu     ,x++                    ; the marker, and STEP PAST IT.

                ; FM STEREO'S PARAMETERS GO IN WITH IT, as HP 08904-87011's
                ; save arm copies its block to $257C before the slot is
                ; written (bank 5 $5C46 -> $58D5). The seven narrow ones first,
                ; into live_stereo, so the live_setting span below carries
                ; them; the four wide ones follow the sequence. Every save
                ; carries them, whichever screen is up, as HP's block is
                ; carried by every save; only a recall into FM Stereo reads
                ; them back.
                pshs    x
                ldu     #st_pampl
                ldx     #live_stereo
                ldb     #ST_SAVED_NARROW
                lbsr    register_seq_copy
                puls    x

                ; THE SPANS BELOW THE ALIASED SLOT - live_setting and the hop
                ; table, 192 bytes, which is V4_KIND_OFF exactly.
                ldu     #register_blocks
                lda     #REGISTER_BLOCKS_BELOW
                lbsr    register_save_group

                ; THEN THE ALIASED SLOT, STAGED STRAIGHT INTO THE REGISTER
                ; from whichever sequence is live. The instrument copies its
                ; own block to $2581 before the record goes out and this is
                ; that; what it no longer is, is a copy into a 257-byte buffer
                ; that a table entry then copied again.
                ;
                ; X IS STEPPED ON HERE, not by the stage: SEQKIND_NONE writes
                ; one byte and the two models write 238 and 155, so the only
                ; number that is always right is the span's own length.
                pshs    u                       ; the table pointer
                pshs    x
                lbsr    register_seq_stage
                ldx     ,s                      ; AND FM STEREO'S FOUR WIDE
                leax    REGISTER_SEQ_STEREO,x   ; VALUES at the span's tail,
                ldu     #st_tone                ; past what either model
                ldb     #ST_SAVED_WIDE          ; stages
                lbsr    register_seq_copy
                puls    x
                leax    REGISTER_SEQBLOCK,x
                puls    u

                ; AND THE SPANS ABOVE IT.
                lda     #REGISTER_BLOCKS_ABOVE
                lbsr    register_save_group
                dec     >dds_lock
                RESTORE_INTERRUPTS

                ; AND THE DURABLE COPY, OUTSIDE THE GUARD.
                ;
                ; The slot in the HM6264 is the working copy and is finished;
                ; this mirrors it into the bank, which is what survives the
                ; battery.
                ;
                ; WHAT THE GUARD WOULD AND WOULD NOT BUY, corrected 2026-09-18.
                ; This said the copy was left outside DISABLE_INTERRUPTS because
                ; holding interrupts off for 476 bytes "would drop ticks the
                ; player needs", and that was wrong both ways round. The tick
                ; arrives on the NON-MASKABLE interrupt (nmi_handler in boot.s),
                ; and DISABLE_INTERRUPTS sets I and F only (interrupts.inc) - so
                ; the guard could not drop a tick if it tried. And the ticks ARE
                ; dropped here anyway: bank_regs_put reaches the bank through
                ; bank_copy_in, which calls bank_enter, which holds the tick
                ; across the whole visit because the window holds no code while
                ; the bank is mapped. That hold is unavoidable - a player on a
                ; paged page cannot run while the window is somewhere else - and
                ; it lasts the length of the copy.
                ;
                ; So the guard is absent because it would protect nothing: no IRQ
                ; or FIRQ handler touches the register array or the bank. It is
                ; not absent to save ticks that were never at risk from it.
                ;
                ; It is safe to be late. A boot reads the bank, so the worst a
                ; power cut here costs is the newest save.
                lbsr    bank_regs_put

                andcc   #~CC_CARRY
                rts
register_save_bad
                puls    b
                ldb     #ERR_VALUE_RANGE
                lbsr    error_raise
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; register_save_group - copy A spans of the table at U into the slot at X
;
;   entry: A = how many spans, U = the next table entry, X = where in the slot
;   exit:  U past the spans consumed, X past the bytes written
;   uses:  A, B, X, Y, U
;
; The loop register_save ran inline until the aliased sequence slot stopped
; being a table entry. It runs twice now - once for the spans below the slot
; and once for those above it - and it is one routine rather than two copies
; of a loop because a copy that drifts from its twin writes a register whose
; halves were laid out by different rules.
;
; This was `stu ,x` with X restored afterwards, so the copy started on top of
; the marker and wiped it.
; ---------------------------------------------------------------------------
register_save_group
                pshs    a                       ; spans left to copy
register_save_span
                ldy     ,u++                    ; where this span lives
                ldb     ,u+                     ; and how long it is
register_save_byte
                lda     ,y+
                sta     ,x+
                decb
                bne     register_save_byte
                dec     ,s
                bne     register_save_span
                puls    a
                rts

; ---------------------------------------------------------------------------
; register_probe - is this register one that can be recalled?
;
;   entry: B = the register number
;   exit:  carry CLEAR and B intact when the slot holds a saved setting;
;          carry SET, with the error recorded, when the number is out of
;          range (ERR_VALUE_RANGE, painted) or the slot is empty
;          (ERR_REG_EMPTY, recorded and sounded, not painted)
;   uses:  A, X, U
;
; The check the stock makes BEFORE it touches anything: enter_handler_by_index
; ($F16A) rejects an index above $000B at $F175, then reads the slot's first
; word and compares it with $C239, the filler power_on_reinit ($C2C4) writes
; into every slot ($F19E LDD #$C239 / CMPD 2,S); that filler means nothing
; was ever saved there, and error_report_beep ($C3FE)($0E) at $F1AB reports
; 'No recall setting in this register' (a2u13_page3's error_message_table,
; $7369) - recorded and sounded, nothing painted, which is error_record
; here. Only a slot that passes reaches the teardown at $F1B1 and the copy
; behind it.
;
; AN UNWRITTEN SLOT IS REFUSED. Each saved slot opens with REGISTER_MARK, and
; a slot that does not is either empty or was written by a different
; firmware - the stock format is 425 bytes a slot against this one's, so
; every stock-saved register reads as empty here, which is what should happen
; and is said in this file's header.
; ---------------------------------------------------------------------------
register_probe
                pshs    b
                lbsr    register_valid
                bcs     register_probe_bad
                ldb     ,s
                lbsr    register_address        ; X = the slot
                ldu     ,x                      ; its marker word
                cmpu    #REGISTER_MARK
                bne     register_probe_empty    ; empty, or another
                puls    b                       ; firmware's format
                andcc   #~CC_CARRY
                rts
register_probe_bad
                puls    b
                ldb     #ERR_VALUE_RANGE
                lbsr    error_raise
                orcc    #CC_CARRY
                rts
register_probe_empty
                puls    b
                ldb     #ERR_REG_EMPTY          ; $F1AB: error_report_beep
                lbsr    error_report_beep       ; ($0E), nothing painted and
                                                ; NOTHING ON THE BUS: $F1AB
                                                ; calls $C3FE alone, so 'RC 3;'
                                                ; on an empty register leaves
                                                ; the instrument's SRQ lamp
                                                ; dark (driven 2026-09-17)
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; register_recall_copy - load a probed register into the live setting
;
;   entry: B = the register number, passed by register_probe
;   uses:  A, B, X, Y, U
;
; The copy alone - $52B2-$52F2 of enter_channel_config_mode ($528F), the
; slot brought into $24E6 - with no check of its own: register_probe has
; refused a bad number or an empty slot before anything is parked, and
; register_restore below runs the three in the stock's order. The park comes
; between the probe and this, so the levels this copy brings in are the
; ones register_apply programs.
; ---------------------------------------------------------------------------
register_recall_copy
                lbsr    register_address        ; X = the slot
                leax    2,x                     ; past the marker, to the
                                                ; payload the save wrote
                DISABLE_INTERRUPTS
                ; AND dds_lock, BECAUSE DISABLE_INTERRUPTS DOES NOT STOP THE
                ; PLAYER. The sequence player runs from NMI, and boot.s says
                ; so in its own words: DISABLE_INTERRUPTS "masks the MASKABLE
                ; interrupts and does nothing whatever to NMI". So the mask
                ; above keeps IRQ and FIRQ out of this copy and the player
                ; walked straight through it - reading a tone step from a
                ; block that was half-written, or writing one into a block
                ; being read.
                ;
                ; dds_lock is what the NMI path actually tests: it finds the
                ; lock held and defers its step to the next time-out, one
                ; period late and correct. inc/dec rather than a flag, so it
                ; nests with any caller already holding it.
                ;
                ; The window is 313 bytes today and grows to about 472 once a
                ; slot carries the sixteen-tone list and a 250-step playlist,
                ; so this gets worse, not better, if it is left.
                inc     >dds_lock
                ldu     #register_blocks        ; the same spans, the same
                lda     #REGISTER_BLOCKS_BELOW  ; order, in the same two
                lbsr    register_recall_group   ; groups register_save writes

                ; AND THE ALIASED SLOT BACK INTO THE MODEL IT CAME FROM, which
                ; its own byte 0 names - read STRAIGHT OUT OF THE SLOT now,
                ; where the table's two entries used to copy it into
                ; register_seq_block for the unstage to read a second time.
                ; Inside the lock, because the player walks the tone list this
                ; may be rewriting.
                ;
                ; The screen follows the register - a recalled tone setup
                ; leaves the tone model live, so saving again puts the same
                ; kind back - and register_seq_unstage is what says so now,
                ; for each model it fills. This copied byte 0 into
                ; seq_kind_live raw, which put a kept kind (3 or 4) where
                ; register_seq_stage looks for 1 or 2, and set NONE over a
                ; model a never-saved slot had not touched.
                pshs    u                       ; the table pointer
                tfr     x,u                     ; the slot is the SOURCE here
                pshs    x
                lbsr    register_seq_unstage
                puls    x
                leax    REGISTER_SEQBLOCK,x
                puls    u

                lda     #REGISTER_BLOCKS_ABOVE
                lbsr    register_recall_group

                dec     >dds_lock
                RESTORE_INTERRUPTS
                rts

; ---------------------------------------------------------------------------
; register_recall_group - copy A spans out of the slot at X into the live cells
;                         the table at U names
;
;   entry: A = how many spans, U = the next table entry, X = where in the slot
;   exit:  U past the spans consumed, X past the bytes read
;   uses:  A, B, X, Y, U
;
; register_save_group with the two pointers the other way round, and split out
; for the same reason: the aliased sequence slot sits between two groups of
; spans and is not a table entry, so the walk runs twice.
; ---------------------------------------------------------------------------
register_recall_group
                pshs    a
register_recall_span
                ldy     ,u++
                ldb     ,u+
register_recall_byte
                lda     ,x+
                sta     ,y+
                decb
                bne     register_recall_byte
                dec     ,s
                bne     register_recall_span
                puls    a
                rts

; ---------------------------------------------------------------------------
; register_restore - recall a register, and enter the mode it was saved in
;
;   entry: B = the register number
;   exit:  carry SET if the number is out of range or the slot is empty -
;          the error recorded, nothing parked, copied or applied
;   uses:  A, B, X, Y, U
;
; THE STOCK'S ORDER, from enter_handler_by_index ($F16A): the slot is checked
; first ($F175 CMPX #$000B, $F19E CMPD #$C239 - register_probe); then the
; teardown vector [$2213] runs ($F1B1 LDX >$2213 / JSR ,X); then page 0 is
; selected and the slot's own first word is called as the handler with
; argument 1 ($F1C3-$F1D6). The handler presets, copies the slot and applies
; it: enter_channel_config_mode ($528F) runs instrument_preset, copies the
; slot into $24E6 ($52B2-$52F2) and re-applies it ($52FA-$5431);
; sequence_mode_init ($5380) runs instrument_preset and recall_sequence_setup
; ($6D19); digital_sequence_mode_setup ($7187) runs instrument_preset and
; recall_state_register.
;
; SO A RECALL IS A MODE ENTRY. Measured on the stock 2026-09-16
; (docs/mode-reentry.md): a register saved in any of the four modes, recalled
; from another screen - the Main Selection included - puts that mode up on
; the record it was saved on. This routine used to copy and apply and leave
; the screen where it was, which the instrument never does.
;
; A SLOT WITH NO RECORD THE INSTRUMENT HAS - saved by a build before the
; record existed, or in this firmware's own stereo or channel summary screens
; - is recalled the old way: the park, the copy and register_apply, onto the
; screen that is up. Executed over the bus on both firmwares
; (emulator/tests/test_bus_registers_new.py): 'RC 3;' after 'SV 3;' brings
; the saved frequency back, 'RC 12;' is refused as $13 and a recall of an
; unsaved slot is refused as $0E with nothing written to the chip.
; ---------------------------------------------------------------------------
register_restore
                lbsr    register_probe          ; $F175 / $F19E: refused
                bcs     register_restore_bad    ; before anything is touched
                pshs    b
                ; WHICH MODE THE SLOT WAS SAVED IN, read before anything
                ; moves. $F16A reads the slot's first word through
                ; array_element_address ($FCEA); here the record is the
                ; slot's copy of active_mode, inside the live_setting span
                ; that register_recall_copy reaches at 2,x - past the mark, as
                ; register_blocks' first span.
                lbsr    register_address        ; X = the slot; B is kept
                ldx     2+active_mode-live_setting,x
                lbsr    mode_reenterable
                bcs     register_restore_stay
                lbsr    screen_exit_run         ; $F1B1: the teardown of the
                                                ; mode that is up, [$2213]
                lbsr    instrument_preset       ; the handler's own $C6EA,
                                                ; which comes before its copy
                puls    b
                pshs    b
                lbsr    register_recall_copy    ; the handler's copy - and
                                                ; active_mode and
                                                ; active_record come in with it
                puls    b
                lbsr    register_stereo_unstage ; FM Stereo's own, when the
                                                ; slot was saved there
                ldb     #MODE_RECALL            ; $F1C3-$F1D6: the handler,
                lbsr    mode_reenter            ; argument 1 - it applies,
                andcc   #~CC_CARRY              ; installs its screen and
                rts                             ; shows the saved record
register_restore_stay
                ldx     >active_mode            ; AND THE LIVE RECORD STAYS:
                lda     >active_record          ; the screen does not change,
                pshs    a,x                     ; so the copy must not leave
                                                ; active_mode naming a mode
                                                ; that is not up
                lbsr    destn_park_all          ; the teardown, which zeroes
                                                ; the OLD levels as $7A45 does
                ldb     3,s                     ; the register number
                lbsr    register_recall_copy    ; $52B2-$52F2: the slot in
                puls    a,x
                stx     >active_mode
                sta     >active_record
                leas    1,s                     ; and the number off
                lbsr    register_apply          ; $52FA-$5431: onto the chip
                andcc   #~CC_CARRY
                rts
register_restore_bad
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; register_stereo_unstage - FM Stereo's parameters back out of a recalled slot
;
;   entry: B = the register just copied in by register_recall_copy
;   uses:  A, B, X, U
;
; HP 08904-87011's stereo entry $42D2 with argument 1 copies 51 bytes from
; $257C - the copy its save arm left inside the saved block - back into its
; live block $3C01. This is that, for the nineteen parameters this port keeps
; (ST_SAVED_WIDE and ST_SAVED_NARROW in scratch.inc): the seven narrow ones
; from live_stereo, which the copy has just brought in, and the four wide ones
; from the tail of the slot's sequence span.
;
; ONLY WHEN THE SLOT WAS SAVED ON FM STEREO. active_mode has just come in
; with the copy, so it names the screen the register was saved on. Any other
; slot - and every slot an earlier build wrote - leaves the live parameters
; alone, because nothing re-enters FM Stereo from it.
; ---------------------------------------------------------------------------
register_stereo_unstage
                ldx     >active_mode
                cmpx    #mode_stereo
                bne     register_stereo_unstage_none
                pshs    b
                ldu     #live_stereo
                ldx     #st_pampl
                ldb     #ST_SAVED_NARROW
                lbsr    register_seq_copy
                puls    b
                lbsr    register_address        ; X = the slot
                leau    2+REGISTER_LIVE+REGISTER_HOP+REGISTER_SEQ_STEREO,x
                ldx     #st_tone                ; past the mark, to the span,
                ldb     #ST_SAVED_WIDE          ; to its tail
                lbra    register_seq_copy
register_stereo_unstage_none
                rts

; ---------------------------------------------------------------------------
; register_migrate - bring saved setups up to the current format
;
;   uses:  A, B, X, Y, U, CC
;
; Called once from the boot path, before anything reads a register.
;
; WHY THIS EXISTS. The array moved down and grew a span, so a slot written by
; format 1 is at the wrong address AND the wrong shape. The owner's word,
; 2026-09-07: "it could also do a ram migration and on
; first start check if it got the new ram config or the old one then migrate
; the data to the right spot". Discarding them was the earlier instruction and
; was superseded the same day.
;
; WHAT MAKES IT CONVERTIBLE WITHOUT LOSS. tone_end is the LAST span, so the
; eight spans of format 1 keep their offsets exactly - the payload maps one to
; one and only the marker and the two new bytes are new. Nothing is
; interpreted, so nothing can be interpreted wrongly.
;
; tone_end migrates as ZERO, and that is faithful rather than a guess: a
; format-1 slot never carried it, so recalling one left tone_end at whatever it
; held, and the player already treats zero as "run all of the steps". Writing
; zero reproduces what a format-1 recall did.
;
; THE COPY RUNS DOWNWARDS, from slot 11 to slot 0. Every destination is above
; its source - the gap is 1320+2n bytes - so with the array moving UP, taking
; the highest slot first means nothing is written over a slot not yet read.
; Ascending would destroy slot 5's source while writing slot 0's destination:
; slot 0's destination is $2BB7-$2CF5 and slot 5's source begins at $2CAC.
;
; IT CANNOT MIGRATE TWICE, and does not rely on the stamp alone to promise it.
; A slot already carrying the current marker is left untouched, so a re-run
; over migrated data is a no-op even if the stamp were lost. The stamp is the
; fast path: with it set the whole routine is four instructions.
; ---------------------------------------------------------------------------
; --- what a slot looks like in each format, as byte offsets from its base ---
; Both carry the same nine spans in the same order; only the tone span differs,
; 80 bytes against 237, so everything before it keeps its offset and everything
; after it shifts by the difference.
MIG_TONE_AT     equ     2+REGISTER_LIVE+REGISTER_HOP    ; 194, both formats
MIG_V2_TONE     equ     80              ; sixteen five-byte steps
MIG_V2_TAIL     equ     MIG_TONE_AT+MIG_V2_TONE         ; 274
MIG_V3_TAIL     equ     MIG_TONE_AT+REGISTER_TONE       ; 431
MIG_TAIL_BYTES  equ     REGISTER_SEQ+1+REGISTER_SIGNS+REGISTER_HOPSIGNS+REGISTER_HOPFLAGS+REGISTER_TONEEND
MIG_V2_STEP     equ     5               ; a v2 step: 3 of tuning word, then
MIG_V2_ON       equ     3               ; ONE BYTE OF MILLISECONDS each
MIG_V2_OFF      equ     4

register_migrate
                ; --- THE FORMAT-3 STAMP, AT THE FORMAT-3 FIRMWARE'S OWN
                ;     ADDRESS, AND THIS IS LOOKED AT FIRST ------------------
                ; THE STAMP HAS MOVED TWICE AND THIS IS WHAT PAYS FOR IT. The
                ; firmware that wrote format 3 kept its stamp at $242B
                ; (REGISTER_STAMP_V3 above, with the git citation); a9450c2
                ; moved it to $213D with format 4; and $213D was inside the 452
                ; bytes of stack this firmware has given back, so it is now at
                ; register_format_stamp. An instrument carrying format 3 has
                ; NOTHING at the new address - whatever the stack last left
                ; there - so reading our own stamp first would answer a
                ; question about a machine we have not identified yet.
                ;
                ; The architect's instruction, 2026-09-14: "a format-4 firmware
                ; looks for a format-3 stamp at the old address first, then its
                ; own at the new one."
                ;
                ; AND IT CANNOT MIGRATE TWICE, which is the thing this order
                ; has to earn. $242B is REGISTER_BASE - slot 0's MARKER in this
                ; format - so after a conversion it holds whatever
                ; register_mig_v3 put there: REGISTER_MARK ($8A04) if v3 slot 0
                ; carried a setup, and v3 slot 0's own empty marker if it did
                ; not. Neither is $8A03: a v3 slot whose marker was $8A03 was
                ; not empty, and register_mig_v3_expand rewrites exactly that
                ; marker to $8A04. So the second boot falls through to the
                ; stamp below and stops there.
                ;
                ; WHAT IS NOT RULED OUT, said plainly: a battery that has never
                ; been migrated and happens to hold $8A03 in the two bytes at
                ; $242B is read as format 3 and its register array rewritten.
                ; That is one value in 65,536 of uninitialised RAM and it costs
                ; saved setups, not identity - the serial and the options are
                ; at $3FFC-$3FFF, 7,633 bytes above the highest byte this
                ; routine writes.
                ;
                ; NOTHING CLEARS THE ARRAY BEFORE THIS RUNS, and an earlier
                ; draft of this comment said an untrusted boot did.
                ; This firmware has no routine that empties it (its own
                ; register_clear_all was an invention and is gone). reset_entry does
                ; nav_reset, scratch_reset, then register_migrate. So the
                ; exposure above is the real one and is not covered by
                ; anything else.
                ldd     >REGISTER_STAMP_V3
                cmpd    #REGISTER_MARK_V3
                lbeq    register_mig_v3

                ; --- THEN OUR OWN, AT ITS OWN ADDRESS -------------------
                ldd     >register_format_stamp
                cmpd    #REGISTER_MARK
                lbeq    register_migrate_ret    ; already current

                ; --- AND OTHERWISE IT IS FORMAT 1 OR 2 ------------------
                ; THERE IS NO THIRD STAMP TEST HERE, and there was one for a
                ; moment while this was being written: `cmpd #REGISTER_MARK_V3`
                ; against register_format_stamp, on the theory that a build
                ; between a9450c2 and 2026-09-14 might have left $8A03
                ; somewhere this firmware reads. It cannot have. That build
                ; stamped $213D, and $213D is not register_format_stamp any
                ; more either - it is stack. A compare against a state no
                ; firmware ever wrote is a guess with an instruction attached,
                ; and it would have made the emulator's negative control pass
                ; for the wrong reason.
                ;
                ; A v3 array is twelve 472-byte slots at $245B and a v4 one is
                ; twelve 476-byte slots at $242B, so a v3 destination is always
                ; between 48 and 4 bytes BELOW its source and a forward move is
                ; safe. Each slot is then converted where it now sits; the v1
                ; and v2 arrays below reach format 4 through that same pass.
                ;
                ; FORMAT 1 IS COUNTED AND THEN LOST. Its slots are at a
                ; different base with a different stride, and its payload has
                ; eight spans where this has nine - there is no tone_end in it
                ; to bring across. Count them here, at their own positions,
                ; before pass A writes over that region.
                clr     >register_refused
                ldx     #REGISTER_BASE_V1
                ldu     #REGISTER_MARK_V1
                ldb     #REGISTER_COUNT
                lbsr    register_count_old

                ; --- PASS A: move every v2 payload down, raw ---------------
                ; The v3 array is at $245B and the v2 array at $2BB7, so a
                ; destination is always BELOW its source and a forward copy is
                ; safe however far the two overlap. That is what makes this
                ; pass possible at all: a v3 slot is 472 bytes against v2's
                ; 315, and for slots 9, 10 and 11 the expanded payload would
                ; overrun its own source if it were expanded in one go.
                ;
                ; Nothing is interpreted here. The marker moves with the
                ; payload, so pass B can still tell a v2 setup from anything
                ; else sitting at that address.
                ; TO THE v3 BASE, NOT THIS ONE. Pass B expands a v2 payload
                ; into a v3 one, and the v3 -> v4 pass below then relocates and
                ; converts it - so a v2 array goes 2 -> 3 -> 4 through the two
                ; conversions that already exist rather than through a third
                ; that would have to do both jobs at once. Sending pass A
                ; straight to the v4 base put v3 CONTENT in v4 SLOTS and every
                ; check in emulator/tests/test_register_migrate_new.py failed.
                ldx     #REGISTER_BASE_V3
                ldu     #REGISTER_BASE_V2
                ldb     #REGISTER_COUNT
register_mig_move
                pshs    b
                pshs    x,u
                ldy     #REGISTER_SLOT_V2
register_mig_move_byte
                lda     ,u+
                sta     ,x+
                leay    -1,y
                bne     register_mig_move_byte
                puls    x,u
                leax    REGISTER_SLOT_V3,x
                leau    REGISTER_SLOT_V2,u
                puls    b
                decb
                bne     register_mig_move

                ; --- PASS B: expand each slot where it now sits ------------
                ldx     #REGISTER_BASE_V3
                ldb     #REGISTER_COUNT
register_mig_expand_slot
                pshs    b
                stx     >register_mig_slot
                lbsr    register_expand
                ldx     >register_mig_slot
                leax    REGISTER_SLOT_V3,x
                puls    b
                decb
                bne     register_mig_expand_slot

                ; THE STAGING TABLES HELD THE LAST SLOT CONVERTED, and they
                ; are the LIVE tone sequence. scratch_reset ran before this,
                ; so leaving them full would boot the instrument with whatever
                ; register 11 happened to hold.
                ldx     #tone_freq
                ldy     #REGISTER_TONE
register_mig_clear_live
                clr     ,x+
                leay    -1,y
                bne     register_mig_clear_live

                ; THERE ARE NO VACATED BYTES TO WIPE ANY MORE, and a loop
                ; that assumed there were is worse than none. Format 2's array
                ; began at $2BB7 and format 1's at $268F; this one begins at
                ; $245B, BELOW both, so the older arrays lie INSIDE it and pass
                ; B has already rewritten every byte of them that matters.
                ;
                ; The loop that stood here ran from $268F while X was below
                ; $245B - a condition already false on the first test - so it
                ; cleared exactly ONE byte, at $268F, which is 90 bytes into
                ; slot 1's hop table. An emulator check on the spans that must
                ; survive a conversion untouched is what found it.

                ; AND ON INTO THE v3 -> v4 CONVERSION, which relocates what
                ; pass B has just built and turns its two sequence spans into
                ; the aliased slot. It writes the stamp itself, so a v2 array
                ; reaches format 4 through the two conversions that exist
                ; rather than through a third doing both jobs at once.
                lbra    register_mig_v3

; ---------------------------------------------------------------------------
; register_mig_v3 - twelve format 3 slots into format 4
;
;   uses:  A, B, X, Y, U
;
; The only thing that changed is the sequence spans: v3 kept the tone
; sequence's 237 bytes and the digital one's 16 apart, and v4 has one aliased
; 257-byte slot holding whichever sequence was live. So a payload's first 192
; bytes do not move, its last 25 move up four, and the tone sequence moves up
; one to sit behind the slot's kind byte.
;
; THE DIGITAL PATTERN IN A v3 SLOT IS LOST, and it has to be: v3 has no byte
; saying which sequence the operator meant, both spans are always present, and
; only one fits the aliased slot. The tone sequence is what is kept - it is
; the larger model, and a tone or DTMF sequence recalled empty is the more
; visible loss. A v3 register's digital pattern was sixteen bytes, which is
; not the instrument's sequence either.
; ---------------------------------------------------------------------------
V3_TONE_OFF     equ     192             ; where the tone span sat in a v3
V3_TONE_LEN     equ     237             ; payload, and how long it is
V4_TONE_OFF     equ     193             ; and where it sits behind the kind
V3_TAIL_OFF     equ     445             ; sequence_length, the two sign arrays,
V3_TAIL_LEN     equ     25              ; the hop flags and tone_end: the run
V4_TAIL_OFF     equ     449             ; after the sequence spans
V4_KIND_OFF     equ     192             ; the aliased slot's first byte

register_mig_v3
                ldx     #REGISTER_BASE
                ldu     #REGISTER_BASE_V3
                ldb     #REGISTER_COUNT
register_mig_v3_slot
                pshs    b
                pshs    x,u
                ldy     #REGISTER_SLOT_V3       ; the whole slot down first,
register_mig_v3_move                            ; marker and all
                lda     ,u+
                sta     ,x+
                leay    -1,y
                bne     register_mig_v3_move
                puls    x,u
                pshs    x,u
                lbsr    register_mig_v3_expand
                puls    x,u
                leax    REGISTER_SLOT,x
                leau    REGISTER_SLOT_V3,u
                puls    b
                decb
                bne     register_mig_v3_slot

                ldd     #REGISTER_MARK          ; and the array is v4 now
                std     >register_format_stamp
                rts

; ---------------------------------------------------------------------------
; register_mig_v3_expand - one moved v3 slot, converted where it sits
;
;   entry: X = the slot base
;   uses:  A, B, X, U
;
; Both moves run BACKWARD, from the top down, because each writes above what
; it reads. The tail moves first: it reads 445-469 and writes 449-473, and the
; tone move that follows writes 193-429, so neither touches the other's
; source. 429-444 held the v3 digital span and is dead by then.
; ---------------------------------------------------------------------------
register_mig_v3_expand
                ldd     ,x
                cmpd    #REGISTER_MARK_V3
                beq     register_mig_v3_conv
                rts                             ; an empty or foreign slot is
                                                ; left exactly as it is
register_mig_v3_conv
                ldd     #REGISTER_MARK
                std     ,x
                leax    2,x                     ; the payload

                pshs    x                       ; the tail, up four
                leau    V3_TAIL_OFF+V3_TAIL_LEN,x
                leax    V4_TAIL_OFF+V3_TAIL_LEN,x
                ldb     #V3_TAIL_LEN
                bsr     register_mig_back
                puls    x

                pshs    x                       ; the tone sequence, up one
                leau    V3_TONE_OFF+V3_TONE_LEN,x
                leax    V4_TONE_OFF+V3_TONE_LEN,x
                ldb     #V3_TONE_LEN
                bsr     register_mig_back
                puls    x

                lda     #SEQKIND_TONE           ; and the slot says what it is
                sta     V4_KIND_OFF,x
                rts

; ---------------------------------------------------------------------------
; register_mig_back - B bytes from the top down, U to X
;
;   uses:  A, B, X, U
; ---------------------------------------------------------------------------
register_mig_back
                lda     ,-u
                sta     ,-x
                decb
                bne     register_mig_back
                rts

register_migrate_ret
                rts

; ---------------------------------------------------------------------------
; register_expand - turn one moved v2 slot into a v3 one
;
;   entry: register_mig_slot = the slot's base
;   uses:  A, B, X, Y, U
;
; A slot that is not a v2 setup is REFUSED: its marker is cleared so it reads
; as empty rather than being recalled with a layout it was never written in.
; That covers a format 1 slot whose bytes happen to have landed here, an empty
; slot, and anything else.
; ---------------------------------------------------------------------------
register_expand
                ldx     >register_mig_slot
                ldd     ,x
                cmpd    #REGISTER_MARK_V2
                bne     register_expand_empty

                lbsr    register_regroup        ; carry SET = unconvertible
                bcs     register_expand_refuse

                ; THE TAIL MOVES FIRST, and it has to: the 237 bytes about to
                ; be written over the tone block reach past where the tail is
                ; sitting. Source 274..314 and destination 431..471 do not
                ; overlap, so a forward copy is right.
                ldx     >register_mig_slot
                leau    MIG_V2_TAIL,x
                leax    MIG_V3_TAIL,x
                ldy     #MIG_TAIL_BYTES
register_expand_tail
                lda     ,u+
                sta     ,x+
                leay    -1,y
                bne     register_expand_tail

                ; AND THEN THE CONVERTED TONE BLOCK, out of the staging tables
                ldx     >register_mig_slot
                leax    MIG_TONE_AT,x
                ldu     #tone_freq
                ldy     #REGISTER_TONE
register_expand_tone
                lda     ,u+
                sta     ,x+
                leay    -1,y
                bne     register_expand_tone

                ldx     >register_mig_slot      ; LAST, so a slot is never
                ldd     #REGISTER_MARK_V3       ; marked mid-expansion - and
                std     ,x                      ; V3 IS WHAT THIS ROUTINE
                rts                             ; PRODUCES, which is what its
                                                ; own header says. It stamped
                                                ; REGISTER_MARK, the CURRENT
                                                ; format: register_mig_v3_expand
                                                ; then compared the slot against
                                                ; REGISTER_MARK_V3, found a v4
                                                ; marker and returned unchanged,
                                                ; so the second half of the
                                                ; migration never ran. Twelve
                                                ; slots passed register_probe as
                                                ; good saved settings while laid
                                                ; out as v3: the byte the recall
                                                ; reads as the sequence KIND is
                                                ; tone 0's tuning-word high byte,
                                                ; and the tail - ampl_signs and
                                                ; hop_saved_flags - is four bytes
                                                ; out of register.
register_expand_refuse
                inc     >register_refused       ; a setup that existed and
register_expand_empty                           ; cannot be brought across
                ldx     >register_mig_slot
                ldd     #0
                std     ,x
                rts

; ---------------------------------------------------------------------------
; register_regroup - sixteen self-contained steps into a tone list and playlist
;
;   entry: register_mig_slot = the slot's base
;   exit:  carry CLEAR and the staging tables filled; carry SET if the slot
;          cannot be expressed in the instrument's model
;   uses:  A, B, X, Y, U
;
; THE RULE. Walk the sixteen steps in order. If an earlier step has the same
; frequency AND the same two times, this step names that step's tone. If an
; earlier step has the same frequency with DIFFERENT times, the slot is
; UNCONVERTIBLE - the instrument's model cannot express it, because a tone owns
; its times and every step naming that tone shares them. Otherwise allocate the
; next tone number.
;
; OVERFLOW CANNOT ARISE: sixteen steps yield at most sixteen distinct
; frequencies and the list holds exactly sixteen.
;
; THE DURATIONS ARE SCALED. A v2 step held ONE BYTE OF MILLISECONDS and its
; player multiplied by TONE_MS_COUNTS to reach the timer; a v3 tone holds the
; TIMER COUNTS themselves. Copying the byte across unscaled would give a
; sequence that plays a hundred times too fast, and nothing downstream would
; notice - the value would be perfectly valid, just wrong.
; ---------------------------------------------------------------------------
register_regroup
                ldx     #tone_freq              ; the staging area, cleared so
                ldy     #REGISTER_TONE          ; unused tones and the 234
register_regroup_clear                          ; unused playlist steps are 0
                clr     ,x+
                leay    -1,y
                bne     register_regroup_clear

                clr     >register_mig_tones
                clr     >register_mig_step
register_regroup_step
                clr     >register_mig_other
register_regroup_other
                lda     >register_mig_other
                cmpa    >register_mig_step
                beq     register_regroup_new    ; no earlier step matched

                lbsr    register_step_addr      ; U = this step, X = the other
                ldb     #3                      ; the frequencies first
register_regroup_freq
                lda     ,u+
                cmpa    ,x+
                bne     register_regroup_next
                decb
                bne     register_regroup_freq

                ; SAME FREQUENCY. The times decide: equal reuses that tone,
                ; different makes the whole slot unconvertible.
                lda     ,u                      ; MIG_V2_ON-3 is zero, and a
                cmpa    ,x                      ; zero offset must be bare: the
                                                ; two assemblers encode 0,X
                                                ; differently ($84 against $00)
                                                ; and the images then differ
                bne     register_regroup_clash
                lda     MIG_V2_OFF-3,u          ; one past the ON byte
                cmpa    MIG_V2_OFF-3,x
                bne     register_regroup_clash

                ldb     >register_mig_other     ; reuse the tone that earlier
                lbsr    register_playlist_read  ; step was given
                bra     register_regroup_assign
register_regroup_clash
                orcc    #CC_CARRY               ; the model cannot hold this
                rts
register_regroup_next
                inc     >register_mig_other
                bra     register_regroup_other

register_regroup_new
                ldb     >register_mig_tones     ; allocate the next tone and
                pshs    b                       ; fill it from this step
                lbsr    register_tone_fill
                puls    b
                inc     >register_mig_tones
register_regroup_assign
                lbsr    register_playlist_write ; B = the tone for this step
                inc     >register_mig_step
                lda     >register_mig_step
                cmpa    #TONE_TONES
                lblo    register_regroup_step
                andcc   #~CC_CARRY
                rts

; ---------------------------------------------------------------------------
; register_step_addr - the two v2 steps a comparison needs
;
;   exit:  U = step register_mig_step, X = step register_mig_other
;   uses:  A, B, X, U
; ---------------------------------------------------------------------------
register_step_addr
                ldb     >register_mig_step
                lda     #MIG_V2_STEP
                mul
                addd    >register_mig_slot
                addd    #MIG_TONE_AT
                tfr     d,u
                ldb     >register_mig_other
                lda     #MIG_V2_STEP
                mul
                addd    >register_mig_slot
                addd    #MIG_TONE_AT
                tfr     d,x
                rts

; ---------------------------------------------------------------------------
; register_tone_fill - put one v2 step's settings into a staged tone
;
;   entry: B = the tone number, register_mig_step = the source step
;   uses:  A, B, X, Y, U
; ---------------------------------------------------------------------------
register_tone_fill
                pshs    b
                lbsr    register_step_addr      ; U = the source step
                puls    b
                pshs    u
                pshs    b
                lda     #3                      ; the tuning word, as it is
                mul
                addd    #tone_freq
                tfr     d,x
                ldu     1,s                     ; the source step, saved under
                                                ; the tone number: pshs u put
                                                ; two bytes down and pshs b one
                                                ; on top, so it is at 1,s. At
                                                ; 2,s this read the low half of
                                                ; the pointer and the byte
                                                ; above it, and every tuning
                                                ; word came out garbage while
                                                ; the times - which take the
                                                ; pointer back with puls - were
                                                ; perfectly correct.
                lda     ,u+
                sta     ,x+
                lda     ,u+
                sta     ,x+
                lda     ,u
                sta     ,x
                puls    b
                lda     #4                      ; and both times, SCALED from
                mul                             ; milliseconds into counts
                addd    #tone_times
                tfr     d,x
                puls    u
                lda     MIG_V2_ON,u
                ldb     #TONE_MS_COUNTS
                mul
                std     ,x
                lda     MIG_V2_OFF,u
                ldb     #TONE_MS_COUNTS
                mul
                std     2,x
                rts

; ---------------------------------------------------------------------------
; register_playlist_write - name a tone in the staged playlist
;
;   entry: B = the tone, register_mig_step = the step
;   uses:  A, B, X
;
; The same packing as tone_step_put on page 1, which is seq_put_nibble ($452D):
; EVEN steps are the HIGH nibble. It is written again here rather than called
; because that routine lives on a paged image and this runs from A2U12.
; ---------------------------------------------------------------------------
register_playlist_write
                andb    #TONE_TONES-1
                pshs    b
                lda     >register_mig_step
                lsra                            ; the byte, and carry = the
                tfr     a,b                     ; step's low bit
                clra
                addd    #tone_list
                tfr     d,x
                lda     >register_mig_step
                anda    #$01
                bne     register_playlist_low
                ldb     ,x                      ; even: the HIGH nibble
                andb    #$0F
                stb     ,x
                puls    a
                asla
                asla
                asla
                asla
                adda    ,x
                sta     ,x
                rts
register_playlist_low
                ldb     ,x
                andb    #$F0
                stb     ,x
                puls    a
                anda    #$0F
                adda    ,x
                sta     ,x
                rts

; ---------------------------------------------------------------------------
; register_playlist_read - which tone a staged step already names
;
;   entry: B = the step
;   exit:  B = the tone
;   uses:  A, B, X
; ---------------------------------------------------------------------------
register_playlist_read
                pshs    b
                clra
                lsrb
                addd    #tone_list
                tfr     d,x
                ldb     ,x
                lda     ,s+
                anda    #$01
                bne     register_playlist_read_low
                lsrb
                lsrb
                lsrb
                lsrb
                rts
register_playlist_read_low
                andb    #$0F
                rts

; ---------------------------------------------------------------------------
; register_count_old - how many slots of an older format hold a setup
;
;   entry: X = that format's base, U = its marker, B = how many slots
;   uses:  A, B, X, U
;
; Each one counted is a saved setup this firmware is about to stop being able
; to read. Only format 1 goes through here now: format 2 slots are counted as
; they are refused, one at a time, in register_expand.
; ---------------------------------------------------------------------------
register_count_old
                pshs    b
                cmpu    ,x
                bne     register_count_next
                inc     >register_refused
register_count_next
                leax    REGISTER_SLOT_V1,x
                puls    b
                decb
                bne     register_count_old
                rts

; ---------------------------------------------------------------------------
; register_apply - put the live setting onto the hardware
;
;   uses:  A, B, X, Y, U
;
; Called after a recall, with the old routing already parked. Recalling loads
; the RECORDS; this is what makes the instrument produce them.
;
; THE CALLER PARKS FIRST. The stock's recall runs the teardown vector [$2213]
; - clear_all_destinations ($5253) - from enter_handler_by_index ($F16A) at
; $F1B1 BEFORE the mode handler copies the slot into $24E6 ($528F, $52B2-
; $52F2), so the teardown zeroes the OLD records' levels ($7A45-$7A6E) and
; the copy then brings the saved ones in. register_restore keeps that order:
; probe, destn_park_all, copy, this. Parking here, after the copy, would zero
; the recalled levels - which is what happened when the park lived in this
; routine and destn_route began zeroing the record as $7A45 does. The
; keep-state boot (boot.s boot_keep_state) calls this without a park: at
; power-on routed_dest is all Off (scratch_reset), so there is nothing to
; park, as the stock's $C5B1 finds every counter zero on that path.
;
; THE ORDER IS DELIBERATE and it is the same order a single channel's commit
; uses, for the same reason: the range goes out before the mantissa, so the
; worst transient is the old level at the new range rather than the new level
; at the old one - and the range spans fifteen octaves, so getting that
; backwards can be enormously louder than either setting.
;
; Every channel is programmed even if its record has not changed. Comparing
; first would save a few hundred microseconds and cost the guarantee that the
; hardware matches the records afterwards, which is the only thing this
; routine is for.
;
; A channel whose board is not fitted is skipped rather than programmed. The
; writes would go to a latch nothing is listening to, and the screen would
; then show a setting the instrument is not producing.
; ---------------------------------------------------------------------------
; ---------------------------------------------------------------------------
; channel_reapply_all - the same, WITHOUT the output relays
;
; What a sequence mode entry wants. The stock's reapply_all_channels ($C5B1)
; reaches a channel latch only through channel_apply_and_propagate ($BE5C),
; and $BE5C's Off path ($BE82 CMPX #$0010 / $BE85) writes the level register
; with zero and returns at $C065 BEFORE the latch writes - so with every
; destination parked, which is what $C5B1 has just done, it touches no latch
; at all. Entering a sequence mode with the relays reasserted showed up in
; the differential harness as (4, 0, 0, 0) against the stock's untouched
; latches.
;
; The recall path still wants them: a register carries the output state and
; restoring it is the whole point. So the two share everything below and
; differ in one byte, which is pushed here and tested at the latch.
; ---------------------------------------------------------------------------
channel_reapply_all
                clra                            ; the relays stay as they are
                bra     register_apply_go
register_apply
                lda     #$FF                    ; and the relays too
register_apply_go
                pshs    a                       ; ONE BELOW the channel each
                                                ; iteration pushes, so it is
                                                ; 1,s wherever the loop reads
                                                ; the channel at 0,s
                clrb
register_apply_next
                cmpb    #CHANNEL_MAX
                lbhs    register_apply_done     ; LONG: this routine grew past
                                                ; the 127-byte reach of a short
                                                ; branch when it started
                                                ; programming the whole record

                pshs    b

                ; THE RELAY-FREE PASS PROGRAMS ALL FOUR, FITTED OR NOT, and
                ; that is not an oversight in the stock: reapply_all_channels
                ; ($C5B1) walks 0 to 3 with no installed-count test in either
                ; of its two loops - lc5bb `CMPB #$04 / LBCC lc5fc` for the
                ; destination park and lc61e `CMPB #$04 / LBCC lc698` for the
                ; apply. Only the RECALL path tests, so the flag pushed at
                ; entry decides here as it does at the latch below.
                ;
                ; It matters because dds_params_reset zeroes every channel
                ; register, ids $08-$13 included, and nothing else puts them
                ; back. With the test on both paths, a preset left an
                ; unfitted channel's registers at zero for good: differential
                ; harness seeds 3, 6 and 8, where the stock reads 10000 on
                ; channels 2 and 3 and this read 0.
                tst     1,s
                beq     register_apply_fitted   ; the relay-free pass: no test
                lbsr    channel_valid           ; carry set if not fitted
                bcs     register_apply_skip
register_apply_fitted

                ldb     ,s
                lda     #CHAN_RECORD
                mul                             ; D = channel * 12
                ldx     #channel_records
                leax    d,x                     ; X = this channel's record

                leau    ,x                      ; the frequency is at offset
                ldb     ,s                      ; zero of the record
                lbsr    freq_program

                ; THE WAVEFORM IS SECOND, not fifth, and that is the order
                ; the routine this one ports writes the chip in. $C5B1's
                ; second loop calls write_channel_reg_08 ($E2C1),
                ; unit_code_select_head ($E38F), set_channel_phase ($E562)
                ; and dispatch_channel_function ($C069) in that order at
                ; $C635-$C68A, and $E38F is the waveform select - register
                ; $1D for channels 0 and 1, $1E for 2 and 3. This called
                ; wave_program after the phase and the level instead, so the
                ; cold start put the same four words on the chip in an order
                ; the instrument does not use: on a real part a channel is
                ; told what shape to make before it is told the phase and
                ; amplitude to make it at.
                ;
                ; The record pointer is in X and wave_program does not keep
                ; it, so it is pushed across the call the way the later
                ; field writes push it.
                lda     ,s                      ; the channel
                ldb     CHAN_WAVE,x
                pshs    x
                lbsr    wave_program            ; carry set on a code that is
                puls    x                       ; not a waveform; the record
                                                ; is the only writer of that
                                                ; field and writes it from a
                                                ; validated cycle

                ; THE LEVEL IS PROGRAMMED BY THE DESTINATION RE-APPLY, not
                ; here. The stock's recall programs each channel's level
                ; inside set_channel_destination ($78BF) - the $C069 call at
                ; $7EB8 dispatches the record's level by its unit after the
                ; routing - and destn_apply below carries that call
                ; (modulation.s destn_route, the post-apply through
                ; ampl_set_signed with the sign the register brought back
                ; in ampl_signs). This used to call ampl_set_signed here as
                ; well, so a recalled level reached the chip twice; once is
                ; the stock's count.

                ldx     CHAN_PHASE,x
                ldb     ,s                      ; THE CHANNEL FIRST: the code
                lbsr    phase_to_code_offset    ; now depends on which channel
                ldb     ,s                      ; it is, because the modulator
                lbsr    phase_program           ; phase offset is per channel

                ; AND THE LEVEL BY ITS UNIT, which is the fourth call of
                ; reapply_all_channels' second pass: $C5B1 does
                ; write_channel_reg_08, unit_code_select_head,
                ; set_channel_phase and then dispatch_channel_function
                ; ($C069) on record+10 at $C68A. With the destination parked
                ; to $0010 by its own first pass, $C069 reaches
                ; channel_apply_and_propagate ($BE5C), which programs the
                ; level register with ZERO at $BE97 and returns at $C065
                ; before the socket's range latch and relay.
                ;
                ; That zero is the instrument's cold-start state and this
                ; firmware had no writer for it. The per-channel loop in
                ; dds_reset was writing it as a side effect; when that loop
                ; went - it is not in the stock's chip reset, see modules/
                ; dds.s - the four level registers were never written at all
                ; and read back as untouched where the stock reads 0.
                ;
                ; ONLY ON THE RELAY-FREE PATH, which is the one that IS
                ; $C5B1. The recall path below reaches destn_apply with a
                ; real destination, and the stock's recall programs the level
                ; inside set_channel_destination ($78BF) - the $C069 call at
                ; $7EB8 - so calling it here as well would put a recalled
                ; level on the chip twice where the stock puts it once.
                tst     1,s
                bne     register_apply_no_level
                ldb     ,s
                lda     #CHAN_RECORD
                mul
                ldx     #channel_records
                leax    d,x
                ldb     ,s                      ; X = the record, B = the
                lbsr    ampl_reapply            ; channel
register_apply_no_level

                ; --- AND THE OTHER FIELDS OF THE RECORD --------------------
                ;
                ; This programmed the frequency, the amplitude and the phase
                ; and stopped. CHAN_WAVE, CHAN_DEST, CHAN_MOD and CHAN_STATE
                ; were left as they were, so a recall put three of a channel's
                ; eight fields on the hardware and the screen then showed a
                ; setup the instrument was not producing - the waveform, the
                ; socket it comes out of and whether the output is on at all
                ; belonging to whatever was set before. The front panel
                ; programs all of them, through wave_program, destn_apply and
                ; the output latch; this is the same three, from the record.
                ;
                ; THE WAVEFORM IS NO LONGER ONE OF THEM: it moved up beside
                ; the frequency, where $C5B1's own second call puts it.
                ;
                ; CHAN_MOD needs no separate step: destn_apply routes a
                ; modulation destination through mod_route, and the modulation
                ; code is what CHAN_DEST holds for those destinations.
                ldb     ,s
                lda     #CHAN_RECORD
                mul
                ldx     #channel_records
                leax    d,x

                lda     ,s
                ldb     CHAN_DEST,x
                pshs    x
                lbsr    destn_apply             ; refusal raises an error and
                puls    x                       ; returns; it does not block,
                                                ; and at power-on the banner
                                                ; repaints over it

                ; The output relay and the float relay, from the record's own
                ; state byte. Both latch bits are ACTIVE LOW - hardware.inc
                ; carries the evidence - so the latch value is the complement
                ; of the record: state bit 0 "output on" becomes latch bit 2
                ; clear, and state bit 1 "floating" becomes latch bit 1 clear.
                tst     1,s                     ; the relays, or not - see
                lbeq    register_apply_skip     ; channel_reapply_all
                lda     CHAN_STATE,x
                coma
                pshs    a
                anda    #$01                    ; "on" -> latch bit 2
                lsla
                lsla
                ldb     ,s+
                andb    #LATCH_FLOAT            ; "floating" -> latch bit 1
                pshs    b
                ora     ,s+
                inc     >dds_lock               ; THE STORE AND THE CALL
                                                ; ARE ONE OPERATION. An
                                                ; NMI landing between
                                                ; them would leave this
                                                ; writing the sequence
                                                ; player's value into a
                                                ; channel latch; see
                                                ; channel_latch_rmw.
                sta     >latch_bits
                lda     #LATCH_OUTPUT|LATCH_FLOAT
                ldb     ,s                      ; the channel
                lbsr    channel_latch_rmw
                dec     >dds_lock
register_apply_skip
                puls    b
                incb
                lbra    register_apply_next     ; LONG, for the same reason as
                                                ; the exit test above
register_apply_done
                ; AND THE STANDING HOP-RAM ADDRESS, which is the last thing
                ; reapply_all_channels ($C5B1) does and the last DDS word of
                ; the instrument's cold start. $C698-$C6BB reads bit 5 of the
                ; high byte of event_flags and the byte at $24F4 and calls
                ; write_reg15_nibble ($E7C4); hop_addr_send (dds.s) is that
                ; routine and reads both for itself. Nothing here wrote
                ; register $15 after the chip reset, so the chip's hop-RAM
                ; address pointer sat at $00 where the instrument leaves it
                ; at $0F - which is slot 15, the one the Hop Ram screen opens
                ; on, and the slot the chip reads next.
                ;
                ; ON THE RELAY-FREE PASS ONLY, because that pass is what
                ; $C5B1 is. The recall path through here is the register
                ; restore, whose stock is the copy at $52B2-$52F2 and not
                ; $C5B1, so it gets no write the instrument does not make.
                ; The flag is still on the stack at this point, which is why
                ; the drop below moved under it.
                tst     ,s
                bne     register_apply_no_hop_addr
                lbsr    hop_addr_send
register_apply_no_hop_addr
                ; AND THE LATCHES GO BACK ON THE BUS, which the instrument
                ; does on this path and this firmware did not. The three mode
                ; entries - $528F, $5380 and $7187 - each re-drive every
                ; channel's latch from the shadow with mask $00FF when their
                ; argument is 1, the recall, and this is that argument: the
                ; relay pass is the register restore, and the relay-free pass
                ; is $C5B1, which has no such loop.
                ;
                ; It changes no bit on a machine whose latch holds what it was
                ; given - see channel_latch_redrive - so it is the bus write
                ; the instrument makes, put back where the instrument makes
                ; it, and nothing more.
                tst     ,s                      ; the relay flag, still pushed
                beq     register_apply_no_redrive
                lbsr    channel_latch_redrive
register_apply_no_redrive
                leas    1,s                     ; the relay flag pushed at the
                                                ; entry above
                ; AND THE FILTER. filter_mode, one byte a channel, lives in
                ; live_globals, so a recall restored
                ; it into the record and nothing put it on the latches -
                ; filter_apply's only caller was the filter screen itself. So
                ; a recalled setup came back with every channel's frequency,
                ; amplitude, phase, waveform, destination and output state
                ; right, and its filter whatever the last screen had chosen.
                lbsr    filter_recompute_all
                ; AND THE FOUR HOP FUNCTION ENABLES, from the snapshot the
                ; register brought back. The stock's recall path re-applies
                ; them after the copy: enter_channel_config_mode ($528F) with
                ; argument 1 copies the register ($52B2-$52F2), reads the
                ; snapshots $267F/$2681 it just copied into 5,s/7,s, and
                ; l5372-l53f4 ($5372-$53F4) calls set_hop_function_enable
                ; ($4984) with $0011 for each set bit - and its argument-2
                ; path, the keep-state boot (foreground_main_loop $83A0,
                ; l848d: bit 0 of $23C1, LDB #$02 / LDX >$24E6 / JSR ,X),
                ; does the same from the preserved snapshot. Both of those
                ; moments come through here: register_screen_recall calls
                ; register_restore, and boot_keep_state calls this.
                ; The stock runs its re-apply with every destination parked
                ; on Off ($C5B1 at $530F sets each record+$21 to $10 and
                ; zeroes the use counts, and l5401 restores them afterwards);
                ; here the destinations are already applied, so the enables'
                ; own checks see the recalled routing.
                lbra    register_hop_reapply    ; a tail call: the rts that
                                                ; was here became unreachable

; ---------------------------------------------------------------------------
; register_hop_reapply - run page 0's hop_reapply and put the page back
;
;   uses:  A, B, X, and whatever hop_reapply uses (A, B, X, Y, U)
;
; hop_reapply lives on page 0 with the four hop switches it drives, and this
; image reaches it through page 0's fifth entry vector ($400D, page_enter_fifth
; in paging.s), the way it reaches every mode. The page that was mapped is
; re-selected afterwards when one was: register_apply runs from the
; Save/Recall screen and from boot, neither of which has a paged screen live,
; but leaving the window on a page the caller did not choose is the kind of
; state that is harmless until the day it is not. An unknown page
; (PAGE_UNKNOWN, or scratch's zero before any select) is left as page 0.
; ---------------------------------------------------------------------------
register_hop_reapply
                ldb     >current_page           ; the page that was mapped
                pshs    b
                lda     #PAGE_CHANNEL_CONFIG    ; page 0 carries hop_reapply
                lbsr    page_enter_fifth
                puls    b
                cmpb    #PAGE_COUNT
                bhs     register_hop_page_done  ; none was mapped: page 0
                lbsr    page_select_and_verify  ; stays
register_hop_page_done
                rts
