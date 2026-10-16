; ===========================================================================
; a2u13_page3.s - paged ROM page 3, 16,384 bytes at $4000-$7FFF
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

                fcc     "3"            ; this page's own number, read back
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
;
; THE THIRD VECTOR IS THE ERROR MESSAGE LOOKUP, and it is not a mode: A2U12's
; error flash calls it with page_call to have the words for the last fault put
; on line 2, and it returns. That is the stock's own arrangement - the message
; table is on page 3 and show_last_error_screen ($C418) reaches it through a
; page-0 thunk named by the pointer word at $404F - a jump into this page, as
; the generated listings spell those.
;
; It repeated cowchip_open until then, because the convention wanted a
; harmless target for an unused vector. Nothing calls page_enter_third with
; this page - main_menu.s uses it for page 0's channel summary alone - so the
; repeat cost nothing and giving it a real caller costs nothing either. Until
; 2026-09-07 it pointed at p3_show, a screen that painted a title over a
; blanked line and did nothing else. See docs/coverage-truth.md.

                jmp     cowchip_open       ; $4001
                jmp     p3_hopram_open     ; $4004
                jmp     error_text_show    ; $4007 - see above
                jmp     opts_open          ; $400A - the Installed Options
                                           ; screen (docs/options-screen.md)
                jmp     relay_open         ; $400D - the relay exercise
                                           ; (docs/relay-exercise.md)

                include "../common/all.inc"
                include "../modules/scratch.inc"
                include "../modules/service_menu.inc"
                include "../modules/page3_cowchip.s"
                include "../modules/page3_screens.s"
                include "../modules/page3_errors.s"
