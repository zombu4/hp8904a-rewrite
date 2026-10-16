; ===========================================================================
; a2u13_page1.s - paged ROM page 1, 16,384 bytes at $4000-$7FFF
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

                fcc     "1"            ; this page's own number, read back
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

                jmp     tone_sequence_open       ; $4001
                jmp     dtmf_sequence_open     ; $4004
                jmp     tone_sequence_open       ; $4007
                jmp     page1_bus_stream        ; $400A - not a mode: one
                                                ; character of a WSQ stream,
                                                ; into the 250-step playlist
                                                ; the two modes share. Its
                                                ; header is in the tone
                                                ; module included below
                jmp     page1_mode_exit         ; $400D - the exit hook both
                                                ; tone modes install, the
                                                ; stock's seq_mode_exit ($51E3)

                include "../common/all.inc"
                include "../modules/scratch.inc"
                include "../modules/service_menu.inc"
                include "../modules/page1_tone.s"
                include "../modules/page1_dtmf.s"
