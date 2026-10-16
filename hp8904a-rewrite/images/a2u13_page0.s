; ===========================================================================
; a2u13_page0.s - paged ROM page 0, 16,384 bytes at $4000-$7FFF
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

                fcc     "0"            ; this page's own number, read back
                                        ; after a page switch to confirm it


; --- THE PAGE ENTRY VECTORS ------------------------------------------------
; Two JMPs at fixed addresses, immediately after the page's own digit:
;
;   $4001   the mode this page carries
;   $4004   its second mode, where a page carries two
;   $4007   its third, which only page 0 has - it carries the channel
;           records, the hop table and the channel summary, all of which are
;           one subject and none of which is worth a page of its own
;   $400D   page 0's fifth, which is not a mode: hop_reapply, run by
;           registers.s through page_enter_fifth after a register recall and
;           at a keep-state boot, as the stock's enter_channel_config_mode
;           ($528F) re-applies the hop enables at l5372-l53f4 on its recall
;           and keep-state paths
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

                jmp     channel_config_open       ; $4001
                jmp     hop_open                ; $4004
                jmp     page0_channel_open      ; $4007
                jmp     stereo_open             ; $400A
                jmp     hop_reapply             ; $400D - not a mode: the
                                                ; re-apply of the four hop
                                                ; function enables from their
                                                ; snapshot, which registers.s
                                                ; runs after a recall and at
                                                ; a keep-state boot
                                                ; (page_enter_fifth)
                jmp     page0_wave_check        ; $4010 - not a mode: the
                                                ; waveform check remote.s
                                                ; runs before it stores a
                                                ; bus-set waveform, so the
                                                ; bus is refused what the
                                                ; panel is refused
                jmp     page0_hop_check         ; $4013 - and the hop
                                                ; frequency and amplitude
                                                ; ceilings, the same
                jmp     page0_destn_check       ; $4016 - and whether the
                                                ; destination option is fitted,
                                                ; which the keypad tests and
                                                ; the bus did not

                include "../common/all.inc"
                include "../modules/scratch.inc"
                include "../modules/service_menu.inc"
                include "../modules/page0_screen.s"
                include "../modules/page0_channel.s"
                include "../modules/page0_destination.s"
                include "../modules/page0_hop.s"
                include "../modules/page0_stereo.s"
