; ===========================================================================
; paging.s - selecting an A2U13 page, and calling into it
;
; A2U13 is 64 KB in four 16 KB pages, one at a time in the window
; $4000-$7FFF. Writing the page number to page_select ($4000) switches it.
;
; THE SWITCH IS CONFIRMED, NOT ASSUMED. Each page opens with the ASCII digit
; of its own number, so after writing the selector the firmware reads $4000
; back and compares. That costs one byte per page and it is the only way
; software can tell which page it is actually talking to - a failed switch
; otherwise means calling a routine at the right address in the wrong page,
; which is unbounded.
;
; A PAGE CANNOT CALL ANOTHER PAGE. Only one is mapped, so anything two pages
; both need lives in A2U12 instead. That is why the shared code - the maths,
; the display driver, the menu engine - is all in the always-mapped image.
; ===========================================================================

PAGE_COUNT      equ     4

; WHICH MODE LIVES ON WHICH PAGE.
;
; A mode is identified by its page and nothing else in this firmware: each
; page carries exactly one operating mode plus whatever screens belong to it,
; so entering a mode is selecting a page and calling its entry point.
;
; That is simpler than the stock arrangement, where two modes share page 1
; and the entry point is chosen by a code in RAM. Sharing saved space in
; 1987; there are 88 kilobytes unused here and no reason to reproduce it.
PAGE_CHANNEL_CONFIG   equ  0
PAGE_TONE_SEQUENCE    equ  1
PAGE_DTMF_SEQUENCE    equ  1            ; page 1 carries both tone modes,
                                        ; which do share their entry table
PAGE_DIGITAL_SEQUENCE equ  2
PAGE_MANUAL_COWCHIP   equ  3
PAGE_ERROR_TEXT       equ  3            ; and the 63 error messages, which the
                                        ; stock keeps on page 3 too - the
                                        ; strings are 1,600 bytes and nothing
                                        ; but the error flash reads them
PAGE_WINDOW     equ     $4000
PAGE_WINDOW_END equ     $7FFF           ; the last address the window covers.
                                        ; foreground_tick uses it to tell a
                                        ; callback in the always-mapped image
                                        ; from one that is only reachable
                                        ; while its own page is in.
PAGE_FIRST_BYTE equ     PAGE_WINDOW     ; where each page's own digit lives

PAGE_UNKNOWN    equ     $FF             ; current_page when no page has been
                                        ; chosen, or when a switch did not
                                        ; take. It was written as a bare $FF
                                        ; in one place and reset_entry left
                                        ; current_page at the zero
                                        ; scratch_reset produces - so before
                                        ; any page was selected the firmware
                                        ; reported "page 0 is mapped", which
                                        ; the Memory Map screen painted as a
                                        ; digit, while the window held
                                        ; whatever the hardware powered up
                                        ; with.

; ---------------------------------------------------------------------------
; page_select_and_verify - map a page and prove it took
;
;   entry: B = the page number, 0 to 3
;   exit:  carry CLEAR if the page is mapped and confirmed;
;          carry SET if it did not take, and the current page is unknown
;   uses:  A, B
;
; The read-back is the whole point. Returning a carry rather than trapping
; lets the caller decide: a service screen can report it, and a routine that
; needs the page can refuse to run rather than calling into the wrong one.
; ---------------------------------------------------------------------------
page_select_and_verify
                andb    #PAGE_COUNT-1           ; 0-3, nothing wilder

                ; UNKNOWN WHILE THE WINDOW IS IN MOTION, and that ordering is
                ; the whole guard. A tick is jumped into only while its page
                ; is the one mapped - compared in nmi_sequence until
                ; 2026-09-16, then by tick_armed, and now by what nmi_callback
                ; holds, as set below - and NMI cannot be masked, so the ORDER of these three stores
                ; is the only defence there is. This wrote the latch and then
                ; current_page, so between the two the window held the NEW page
                ; while current_page still named the OLD one: a tick installed
                ; on the old page passed the compare and jsr'd into whatever
                ; the new page has at that address. Writing current_page first
                ; only moves the window the other way. $FF belongs to no page,
                ; so no tick matches it, and the number goes in only once the
                ; read-back has proved the switch - which is where the stock
                ; puts its own store: select_a2u13_page writes the latch at
                ; $5AFF, reads back at $5B02, compares at $5B05 and stores the
                ; index into $247B at $5B0F, on the success path alone.
                ;
                ; AND THE TICK IS HELD WITH IT, which is where the page test
                ; lives. nmi_sequence used to compare tick_page with
                ; current_page on every tick, and tick_armed after it cost
                ; two more; now the handler jumps straight into the player
                ; (boot.s nmi_handler), so the comparison is made here, once
                ; per switch: tick_hold puts nmi_tick_hold in before the latch
                ; moves, and tick_arm_update puts the player back only once
                ; the read-back has proved a page, and only when that page is
                ; the player's. An NMI between any two of these finds either
                ; the old page still mapped with its player, or the hold.
                lbsr    tick_hold
                lda     #PAGE_UNKNOWN
                sta     >current_page

                ; THE LATCH TAKES THE ASCII DIGIT, WHICH IS WHAT THE
                ; INSTRUMENT WRITES. select_a2u13_page ($DAE0) renders the
                ; page with byte_to_hex_digits ($CBA6) into $2414/$2415 and
                ; writes the LOW DIGIT - $30 to $33 - to $4000, then reads
                ; $4000 back and compares. This wrote the binary number
                ; $00-$03 instead, and the read-back still compared against
                ; the digit, so on a 27513 - which latches D0 and D1 and
                ; ignores everything above them - both forms chose the same
                ; page and nothing showed.
                ;
                ; IT IS NOT A 27513 IN THE INSTRUMENT. The One ROM there was
                ; widened to eight banks for the RAM work and latches THREE
                ; bits, so a bit the real part drops, that board keeps. The
                ; four page numbers are safe either way - $00-$03 and
                ; $30-$33 agree in the low three bits - but the margin is one
                ; bit wide, and writing what the instrument writes costs an
                ; ADDA and removes the whole class.
                tfr     b,a                     ; each page opens with the
                adda    #'0'                    ; ASCII digit of its number
                sta     >page_select
                cmpa    >PAGE_FIRST_BYTE
                bne     page_select_failed
                stb     >current_page           ; proved, so now it is known
                lbsr    tick_arm_update         ; and the tick, if it is this
                andcc   #~CC_CARRY              ; page's
                rts
page_select_failed
                lda     #PAGE_UNKNOWN           ; the page is now unknown, and
                sta     >current_page           ; saying so is better than
                orcc    #CC_CARRY               ; leaving a stale number
                rts

; ---------------------------------------------------------------------------
; page_call - call a routine in a paged ROM
;
;   entry: B = the page number, X = the address in the window
;   exit:  carry SET if the page could not be selected and nothing was called
;   uses:  whatever the callee uses
;
; Selects, confirms, then calls. If the switch fails NOTHING IS CALLED - the
; alternative is jumping to an address in whichever page happens to be mapped,
; which is how a paging fault turns into arbitrary execution.
; ---------------------------------------------------------------------------
page_call
                pshs    x
                bsr     page_select_and_verify
                bcs     page_call_failed
                puls    x
                jsr     ,x                      ; AND THE CALLEE'S CARRY IS
                rts                             ; WHAT COMES BACK. This did
                                                ; `andcc #~CC_CARRY` first,
                                                ; overwriting whatever the
                                                ; paged routine had reported,
                                                ; so a mode that failed
                                                ; returned success. Two
                                                ; meanings shared the flag -
                                                ; the page switch's status and
                                                ; the callee's - and the
                                                ; callee's was silently the
                                                ; loser. A failed page switch
                                                ; returns above without ever
                                                ; reaching here, so carry
                                                ; still means "this did not
                                                ; work", whichever step it
                                                ; was.
page_call_failed
                puls    x
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; page_current - which page is mapped
;
;   exit:  B = the page number, or $FF if a switch failed and it is unknown
;   uses:  B
; ---------------------------------------------------------------------------
page_current
                ldb     >current_page
                rts

; ---------------------------------------------------------------------------
; page_enter - switch to a page and run the mode it carries
;
;   entry: A = the page number, 0 to 3
;   exit:  when the mode returns; carry SET if the page could not be selected
;   uses:  A, B, X, and then whatever the mode uses. The first three are
;          this routine's own - it loads the vector and the page number - and
;          are listed because "whatever the mode uses" is a statement about
;          the callee, not about this code, and a caller reading it learned
;          nothing about what happens before the mode is reached.
;
; The mode entry is at a fixed address in the window - see the entry-vector
; block at the top of each page image - so this needs to know nothing about
; the page's layout beyond that one number.
;
; A failed page switch does NOT call anything. That is the same rule
; page_call follows and for the same reason: with the window holding an
; unknown page, $4001 is whatever that page happens to have there, and
; calling it is arbitrary execution. The operator sees the error instead.
; ---------------------------------------------------------------------------
PAGE_ENTRY      equ     PAGE_WINDOW+1   ; the JMP each page opens with
PAGE_ENTRY_2    equ     PAGE_WINDOW+4   ; its second, where it has two
PAGE_ENTRY_3    equ     PAGE_WINDOW+7   ; and page 0's third
PAGE_ENTRY_4    equ     PAGE_WINDOW+10  ; and page 0's fourth, the stereo screen
PAGE_ENTRY_6    equ     PAGE_WINDOW+16  ; page 0's sixth and seventh, which are
PAGE_ENTRY_7    equ     PAGE_WINDOW+19  ; not modes either: the checks a bus
PAGE2_BUS_STREAM equ    PAGE_WINDOW+13  ; and its fifth: one character of a
                                        ; WSQ stream, into the pattern
PAGE1_MODE_EXIT equ     PAGE_WINDOW+13  ; page 1's exit hook, both tone modes
PAGE2_MODE_EXIT equ     PAGE_WINDOW+16  ; page 2's exit hook
PAGE1_BUS_STREAM equ    PAGE_WINDOW+10  ; PAGE 1's fourth vector, and the only
                                        ; one of its four that is not a mode:
                                        ; one character of a WSQ stream, into
                                        ; the 250-step playlist. The same
                                        ; offset as the two below by
                                        ; arithmetic and not by design - each
                                        ; page's vectors are its own, and the
                                        ; page is selected by name before any
                                        ; of them is called
PAGE2_BUS_INDEX equ     PAGE_WINDOW+10  ; PAGE 2's fourth vector, and the
                                        ; only one that is not a mode: the
                                        ; commit a bus SEQP or SEQE runs,
                                        ; so the digital editor's clamp and
                                        ; window are the panel's own. It is
                                        ; at the same offset as page 0's
                                        ; fourth by arithmetic, not by
                                        ; design - each page's vectors are
                                        ; its own, and the page is selected
                                        ; by name before either is called
PAGE_ENTRY_8    equ     PAGE_WINDOW+22  ; command has to pass before its
                                        ; value is stored: the waveform's
                                        ; rules, the hop ceilings, and whether
                                        ; the destination option is fitted. The
                                        ; validators live on page 0 with the
                                        ; fields they bound and remote.s is
                                        ; resident, so without a vector the bus
                                        ; path had no check at all - see the
                                        ; header over page0_wave_check. Only
                                        ; page 0 carries them; remote.s selects
                                        ; page 0 by name before it calls one,
                                        ; so no other page needs a JMP at these
                                        ; offsets
PAGE_ENTRY_5    equ     PAGE_WINDOW+13  ; and page 0's fifth: hop_reapply, which
                                        ; is not a mode but the re-apply of the
                                        ; four hop function enables that
                                        ; register_apply runs after a recall
                                        ; and at a keep-state boot

page_enter
                tfr     a,b
                ldx     #PAGE_ENTRY
                lbra    page_call

; ---------------------------------------------------------------------------
; page_enter_second - the same, for a page carrying two modes
;
;   entry: A = the page number
;   exit:  as page_enter
;   uses:  A, B, X, and then whatever the mode uses. The first three are
;          this routine's own - it loads the vector and the page number - and
;          are listed because "whatever the mode uses" is a statement about
;          the callee, not about this code, and a caller reading it learned
;          nothing about what happens before the mode is reached.
;
; Only page 1 has two, because the tone and DTMF sequence screens share
; almost all of their code. Every other page points both vectors at the same
; routine, so calling this on one of them is harmless rather than wrong.
; ---------------------------------------------------------------------------
page_enter_second
                tfr     a,b
                ldx     #PAGE_ENTRY_2
                lbra    page_call

; ---------------------------------------------------------------------------
; page_enter_third - the third mode on a page that carries three
;
;   entry: A = the page number
;   exit:  as page_enter
;   uses:  A, B, X, and then whatever the mode uses. The first three are
;          this routine's own - it loads the vector and the page number - and
;          are listed because "whatever the mode uses" is a statement about
;          the callee, not about this code, and a caller reading it learned
;          nothing about what happens before the mode is reached.
;
; Only page 0 has one: it carries the channel records, the hop table and the
; channel summary, which are one subject. Every other page points all three
; vectors at the same routine, so calling this on one of them is harmless
; rather than wrong.
; ---------------------------------------------------------------------------
page_enter_third
                tfr     a,b
                ldx     #PAGE_ENTRY_3
                lbra    page_call

page_enter_fourth
                tfr     a,b
                ldx     #PAGE_ENTRY_4
                lbra    page_call

; ---------------------------------------------------------------------------
; page_enter_fifth - page 0's fifth vector, the hop-enable re-apply
;
;   entry: A = the page number
;   exit:  as page_enter
;   uses:  A, B, X, and then whatever hop_reapply uses. The first three are
;          this routine's own - it loads the vector and the page number.
;
; Only page 0 has one. It is the way registers.s reaches hop_reapply
; (page0_hop.s) from the always-mapped image: the stock's re-apply is inside
; page 0's enter_channel_config_mode ($528F), at l5372-l53f4 ($5372-$53F4),
; and this firmware's four hop switches are on page 0 with the screen whose
; keys they are, so the routine that drives them is there too.
; ---------------------------------------------------------------------------
page_enter_fifth
                tfr     a,b
                ldx     #PAGE_ENTRY_5
                lbra    page_call

