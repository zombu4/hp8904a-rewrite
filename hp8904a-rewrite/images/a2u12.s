; ===========================================================================
; a2u12.s - the always-mapped ROM, $8000-$FFFF, 32,768 bytes
;
; One of five images built from this tree. The instrument's firmware is a
; single program that happens to live in two devices:
;
;   A2U12   this image, always mapped at $8000-$FFFF
;   A2U13   64 KB in four 16 KB pages, one at a time at $4000-$7FFF,
;           selected by writing the page number to page_select ($4000)
;
; WHAT LIVES HERE, and why the split is a decision rather than an inheritance
;
; The stock firmware's split is HP's 1987 answer to a space problem, and it
; shows: helpers are duplicated across pages because a page could not reach
; its neighbour. This rewrite treats the split as a LAYOUT decision made at
; the end, against the real byte budget, not a constraint carried in from the
; start. What belongs here is what everything needs:
;
;   - the reset and interrupt entry points; the vector table is at $FFF0 and
;     the CPU fetches it from this image, so the handlers must be here
;   - anything a paged routine calls, since a page cannot call another page
;   - the service menus, which must work even when the paged ROM does not
;
; What belongs in a page is what only that page's screens need.
;
; BURN IT WITH ITS OWN A2U13 AND NO OTHER. This rewrite lays out code freely,
; so the entry points the STOCK A2U13 calls are not where it expects them, and
; this image does not run with the stock A2U13 nor the stock A2U12 with the
; rewritten one. make_roms.py writes the pair to roms/, and docs/burn.md is
; the page they are flashed from.
; ===========================================================================

                org     $8000

; --- Facts about the machine ----------------------------------------------
                include "../common/all.inc"
; --- Modules ---------------------------------------------------------------
                include "../modules/a2u12_all.inc"
