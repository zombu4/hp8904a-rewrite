; ===========================================================================
; a2u12_tail.inc - the ABI table and the modules above it
;
; The other half of the split described in a2u12_core.inc. abi_table.s fills
; to ABI_BASE, so everything here is at $F000 or above.
; ===========================================================================

                include "../modules/abi_table.s"
; AFTER THE TABLE, NOT BEFORE IT. Everything above abi_table.s has to fit under
; ABI_BASE ($F000), and the part holds 3,738 more bytes above the table's end
; that nothing could reach - docs/a2u12-space.md measured both. The bus
; command tables are data, remote.s already names them forward, and moving
; them here moves no ABI address; build.py still refuses code that reaches the
; checksum byte at $FFEF.
                include "../modules/remote_tables.s"
                ; registers.s ABOVE THE TABLE TOO, for the same reason
                ; remote_tables.s is: the space below ABI_BASE ran out when
                ; remote.s took the bus's entry-buffer rules, and the space
                ; above it was reachable only by include order. No equ
                ; anywhere names a label of registers.s, and every caller
                ; reaches it by lbsr or through its ABI slot, so nothing
                ; assembled before it needs its addresses first.
                include "../modules/registers.s"
                ; remote_lone_unit.s above the table as well: the bus's lone-unit
                ; leg outgrew the 127 bytes left below ABI_BASE (its header says
                ; why), and it is reached only by long branches
                include "../modules/remote_lone_unit.s"
                ; and the menus' armed-action prompts, eleven forty-column
                ; lines and their two callbacks, above the table for the same
                ; reason (its header says which)
                include "../modules/service_prompts.s"
                ; and the backlight setting's two screens, above the table
                ; with them for the same reason
                include "../modules/service_backlight.s"
