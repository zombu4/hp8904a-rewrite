; ===========================================================================
; a2u12_all.inc - the whole of A2U12, in two halves
;
; The halves exist for the test harnesses: each of them assembles the firmware
; and its own test code into one 32K image, and with the code appended after
; everything it landed past the end. A harness includes the core, then its own
; code, then the tail, which puts it in the gap below ABI_BASE. The product
; includes this file and gets exactly the order it always had.
; ===========================================================================

                include "../modules/a2u12_core.inc"
                include "../modules/a2u12_tail.inc"
