; ===========================================================================
; all.inc - every declaration file, in dependency order, in one include
;
; The five images and the test harnesses all need the same set of equates,
; and they each carried their own list of includes. Those lists drifted every
; time a file was added: the harnesses stopped assembling three times, each
; time because a new declaration file had been wired into the images and not
; into them, and each time the symptom was an undefined symbol in a module
; that had not changed.
;
; So there is one list, here, and everything includes it. A new declaration
; file is added in exactly one place.
;
; THE ORDER MATTERS. conventions.inc defines the CC bits that interrupts.inc
; builds its masks from, display.inc defines LCD_COLUMNS that service
; records are sized against, and labels.inc and keys.inc stand alone. A file
; that is added must go where its dependencies are already satisfied.
; ===========================================================================

                include "conventions.inc"
                include "hardware.inc"
                include "ram.inc"
                include "interrupts.inc"
                include "display.inc"
                include "labels.inc"
                include "keys.inc"
                include "formats.inc"
                include "abi.inc"
