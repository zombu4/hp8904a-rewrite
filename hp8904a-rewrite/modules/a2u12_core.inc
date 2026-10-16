; ===========================================================================
; a2u12_core.inc - every A2U12 module that lives BELOW the ABI table
;
; Split out of a2u12_all.inc so a TEST HARNESS can put its own code in the
; gap below ABI_BASE rather than after the modules that live above it, where
; it lands past the end of the image. The product includes a2u12_all.inc,
; which is this file and a2u12_tail.inc in the same order as before, so the
; burnable image is byte for byte what it was.
; ===========================================================================

; ===========================================================================
; a2u12_all.inc - every module A2U12 carries, in dependency order
;
; The image and the test harnesses need the same set, and they each carried
; their own list. Those lists drifted constantly: a harness stopped
; assembling every time a module gained a dependency on another, and the
; symptom was always an undefined symbol in a file nobody had touched. It
; happened four times.
;
; So there is one list. A harness that wants A2U12 gets all of A2U12, which
; costs a second of assembly and removes the whole class of failure.
;
; THE ORDER IS DEPENDENCY ORDER, not alphabetical. scratch.inc declares the
; RAM everything uses; service_menu.inc declares the record shape the menus
; are built from; screen.s owns the key handler menu.s installs. A module
; added must go where what it needs is already declared.
; ===========================================================================

                include "../modules/scratch.inc"
                include "../modules/service_menu.inc"
                include "../modules/service_data.s"
                include "../modules/timer.s"
                include "../modules/lcd.s"
                include "../modules/math.s"
                include "../modules/text.s"
                include "../modules/keymap.s"
                include "../modules/keypad.s"
                include "../modules/panel_leds.s"
                include "../modules/screen.s"
                include "../modules/menu.s"
                include "../modules/service_serial.s"
                include "../modules/service_diag.s"
                include "../modules/service_info.s"
                include "../modules/service_memmap.s"
                include "../modules/service_dds.s"
                include "../modules/service_pll.s"
                include "../modules/service_nav.s"
; errors.s comes before service_screens.s: that menu's aliases resolve to
; error_open, and an equ needs its target defined first.
                include "../modules/errors.s"
                include "../modules/service_screens.s"
                include "../modules/screens_main.s"
                include "../modules/main_menu.s"
                include "../modules/entry.s"
                include "../modules/boot.s"
                include "../modules/paging.s"
                ; AFTER paging.s: bank.s calls page_select_and_verify and uses
                ; PAGE_WINDOW, PAGE_FIRST_BYTE and PAGE_UNKNOWN from it.
                include "../modules/bank.s"
                include "../modules/units.s"
                include "../modules/dds.s"
                include "../modules/channel.s"
                include "../modules/labels.s"
                include "../modules/frequency.s"
                include "../modules/amplitude.s"
                include "../modules/phase.s"
                include "../modules/modulation.s"
                include "../modules/selftest.s"
                include "../modules/remote.s"
