; ===========================================================================
; a2u13_page2.s - paged ROM page 2, 16,384 bytes at $4000-$7FFF
;
; One of the four pages of A2U13. Only one is mapped at a time; the page
; number is written to page_select ($4000) and read back to confirm the
; switch took. A page cannot call another page - the window holds one at a
; time - so anything two pages both need lives in A2U12 instead.
;
; The first byte of each page is the ASCII digit of its own number. The stock
; firmware uses that to confirm a page switch by reading $4000 back and
; comparing, and this rewrite keeps it: it costs one byte and it is the only
; way the software can tell which page it is actually talking to.
; ===========================================================================

                org     $4000

                fcc     "2"            ; this page's own number, read back
                                        ; after a page switch to confirm it


; --- THE PAGE ENTRY VECTORS ------------------------------------------------
; Two JMPs at fixed addresses, immediately after the page's own digit:
;
;   $4001   the mode this page carries
;   $4004   its second mode, where a page carries two
;
; A2U12 reaches a mode by selecting the page and calling $4001. It therefore
; needs to know nothing about where anything in the page actually is, and a
; page can be rearranged freely without touching A2U12 - which matters,
; because A2U12 holds the vectors and the checksum and is the harder of the
; two to reburn.
;
; A page with only one mode points both vectors at it rather than leaving the
; second unused. An unused vector is three bytes that eventually get called
; by mistake, and pointing it somewhere real makes that harmless.

                jmp     digital_sequence_open       ; $4001
                jmp     digital_sequence_open     ; $4004
                jmp     digital_sequence_open       ; $4007
                jmp     page2_bus_index         ; $400A - not a mode: the
                                                ; commit a bus SEQP or SEQE
                                                ; goes through, so the clamp,
                                                ; the window and the error
                                                ; codes are the panel's own.
                                                ; Its header is in
                                                ; modules/page2_edit.s
                jmp     page2_bus_stream        ; $400D - nor is this: one
                                                ; character of a WSQ stream,
                                                ; into the pattern
                jmp     page2_mode_exit         ; $4010 - the exit hook, the
                                                ; stock's leave_digital_
                                                ; sequence_mode ($6FBE)

                include "../common/all.inc"
                include "../modules/scratch.inc"
                include "../modules/service_menu.inc"
                include "../modules/page2_digital.s"
                include "../modules/page2_edit.s"
