; ===========================================================================
; a2u12_tail_harness.inc - the tail a HARNESS image gets: everything in
; a2u12_tail.inc except abi_table.s
;
; WHY IT EXISTS. abi_table.s fills to ABI_BASE, so including it in a harness
; puts a hard floor under the harness's own test code - and a harness is the
; core plus its test code plus the tail, in that order, so its code sits in
; exactly the gap the fill claims. Lowering ABI_BASE from $F000 to $EF90 on
; 2026-09-18 moved that floor down 112 bytes and three harnesses stopped
; assembling at once, with "Invalid fill length": harness.s, harness_entry.s
; and harness_math.s. harness_modulation.s was not among them - its test code
; is copied to RAM and run there, so it includes a2u12_all.inc in the
; product's own order and the boundary is not its problem.
;
; Leaving the table out is correct rather than convenient: a harness build has
; no paged image, nothing in it calls through the ABI, and no harness names a
; table label. The table is the paging interface, and a harness does not page.
;
; The two lists must otherwise agree, module for module and in order, or a
; module added to the product tail would be silently missing from every
; harness image - so hp8904a-rewrite/tests/test_tail_lists.py checks exactly
; that.
; ===========================================================================

                include "../modules/remote_tables.s"
                include "../modules/registers.s"
                include "../modules/remote_lone_unit.s"
                include "../modules/service_prompts.s"
                include "../modules/service_backlight.s"
