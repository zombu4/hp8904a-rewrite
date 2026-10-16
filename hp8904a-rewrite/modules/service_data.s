; ===========================================================================
; service_data.s - reading and writing the instrument's identity
;
; The serial number and the installed-option bits live in battery-backed RAM.
; This file is the only place in the rewrite that writes either of them, so
; there is one route in and it can be reasoned about.
;
; ---------------------------------------------------------------------------
; WHAT THE STOCK FIRMWARE DOES, AND WHY IT IS REPLACED
; ---------------------------------------------------------------------------
;
; On revision 27887A a flat backup battery is unrecoverable from the front
; panel. Two guards on A2U13 page 3 make it so:
;
;   serial installation ($7163)  refuses unless the serial IS $0AAE60, the
;                                factory-virgin value
;   option installation ($6E81)  refuses if the serial IS $0AAE60, and also
;                                refuses if it is $000000
;
; A dead battery leaves the serial at $000000. The serial screen refuses it
; for not being virgin; the option screen refuses it for being zero. Neither
; can be reached from the other. HP's answer, in the service manual, is to
; replace the A2 Digital Assembly.
;
; There is a second half to the trap that is easy to miss. Even once the
; option screen IS reachable, it cannot turn an option OFF. Page 3 $6DD8 is:
;
;       ldb  >installed_options
;       orb  3,s                    ; only ever ORs a bit IN
;       stb  >installed_options
;
; so bits accumulate and never clear. An option enabled by mistake, or one
; that has to be moved to another unit, is permanent.
;
; This rewrite removes both. The serial is writable at any time, from any
; value to any value, and each option bit is independently settable AND
; clearable. There is no codeword: a codeword authenticates a purchase to a
; machine that cannot check it, and its only real effect here was to make a
; flat battery a board-replacement job.
;
; ---------------------------------------------------------------------------
; THE STORAGE, established from the ROM rather than assumed
; ---------------------------------------------------------------------------
;
; serial_number ($3FFD) is a 24-BIT BIG-ENDIAN UNSIGNED VALUE - three bytes,
; most significant first - not packed BCD and not ASCII. The stock banner
; routine at $8000 proves it:
;
;       $8010  ldu  #$22cd              ; destination buffer
;       $8013  ldy  #serial_number      ; source
;       $8017  ldx  #$0004              ; 4 bytes of arguments = two pointers
;       $801A  pshs x,y,u
;       $801C  lbsr uint24_to_ascii8    ; 24 bits in, 8 ASCII digits out
;
; 24 bits reaches 16,777,215, so eight digits covers the whole range. The
; factory-virgin value $0AAE60 is 699488 decimal.
;
; installed_options ($3FFC) is one byte of independent bits. Enumerated
; across all five stock images, fifteen references in total, only TWO bits
; are ever tested by this firmware revision:
;
;   bit 0  tested at a2u12 $893F and $8970, and page 0 $54A3, $5D72, $5FE6
;   bit 1  tested at page 0 $5495, $5D69 and $604E
;
; Bits 2 to 7 are stored and never read. They are still exposed by the menu,
; because they cost nothing to offer and a later firmware may use them, but
; the menu must say plainly that this firmware acts on two of them - offering
; a switch that does nothing without saying so would be a lie in the UI.
; ===========================================================================

; --- Layout constants ------------------------------------------------------

SERIAL_BYTES    equ     3               ; 24 bits, big-endian, at $3FFD
SERIAL_DIGITS   equ     8               ; how many decimal digits that needs
SERIAL_MAX_HI   equ     $FF             ; the largest value that fits, high
SERIAL_VIRGIN_H equ     $0A             ; the factory-virgin value $0AAE60,
SERIAL_VIRGIN_M equ     $AE             ;   kept only so the menu can SHOW
SERIAL_VIRGIN_L equ     $60             ;   that a unit is still virgin
SERIAL_VIRGIN_LOW16 equ $AE60           ; the middle and low bytes as one
                                        ; word, because this assembler
                                        ; takes a symbol or a number in an
                                        ; immediate, not an expression
OPTION_BITS     equ     8               ; installed_options is one byte

; The two bits that mean something to the hardware. Named because #$01 in a
; test says nothing about what is or is not fitted.
;
; Established from the identification banner, which prints "/01" and "/03"
; in exactly these two fields, and from the retrofit wording in the service
; manual. The other six bits are stored and read back but change nothing
; except the banner - which is why the options screen offers all eight and
; says so for the six.
OPTION_001      equ     0               ; modulation, summing, sequencing
OPTION_003      equ     1               ; fast hop and the digital output

; ---------------------------------------------------------------------------
; serial_read - fetch the instrument's serial number
;
;   exit:  A = bits 23-16, X = bits 15-0
;
; A 24-bit value does not fit one register pair, so it comes back as the high
; byte in A and the low word in X. Callers that only need to know whether it
; is zero use serial_is_zero instead.
;
; THE HEADER USED TO CARRY TWO exit: BLOCKS, one of them a note-to-self that
; described neither this routine nor any other - "U = high byte in B of D? no
; - see below". A contract with a question mark in it is not a contract, and
; the second block, which is the one below, was right all along.
;
;   exit:  A = bits 23-16, X = bits 15-0. CC reflects nothing; test with
;          serial_is_zero if that is what you want.
;   uses:  A, X
; ---------------------------------------------------------------------------
serial_read
                lda     >serial_number          ; bits 23-16
                ldx     >serial_number+1        ; bits 15-0, big-endian
                rts

; ---------------------------------------------------------------------------
; serial_write - store a new serial number, unconditionally
;
;   entry: A = bits 23-16, X = bits 15-0
;   exit:  the three bytes at serial_number hold it
;   uses:  nothing beyond the entry registers
;
; NO GUARD. This is the whole point of the rewrite: there is no check that
; the current value is factory-virgin, none that the new value is non-zero,
; and no codeword. The operator asked for a serial number and gets it.
;
; Interrupts are masked across the three stores. The value must never be seen
; half-written: an interrupt handler that read the serial between the high
; byte and the low word would see a number that never existed. Three stores
; is a handful of cycles, so the window is tiny, but "tiny" is not "none" and
; this costs nothing to get right.
; ---------------------------------------------------------------------------
; THE BANK FIRST, THEN THE SHADOW, and that order is the whole of the
; durability argument. If power fails between the two, the bank - which is what
; the next boot reads and copies back into $3FFC-$3FFF - already holds the new
; value. The other order would leave a boot repairing the shadow from a stale
; bank, which is to say silently undoing the write.
;
; With no bank fitted bank_serial_put returns carry set having done nothing,
; and what follows is exactly the routine that was here before.
serial_write
                pshs    a,x
                lbsr    bank_serial_put
                puls    a,x
                DISABLE_INTERRUPTS
                sta     >serial_number          ; bits 23-16
                stx     >serial_number+1        ; bits 15-0
                RESTORE_INTERRUPTS
                rts

; ---------------------------------------------------------------------------
; serial_is_zero - is the serial number all zeroes?
;
;   exit:  Z set if the serial is $000000, clear otherwise
;   uses:  A, X
;
; This is what a flat battery leaves behind, and the state the stock firmware
; could not recover from. Here it is simply a fact the menu can display.
; ---------------------------------------------------------------------------
serial_is_zero
                ; THROUGH is_zero24, the shared test. This had its own copy -
                ; a load, a branch, a second load - and hard-coded $04 for
                ; the Z bit where conventions.inc names it CC_ZERO. One
                ; twenty-four-bit zero test, used everywhere, is one place
                ; for it to be right.
                ldx     #serial_number
                lbra    is_zero24

; ---------------------------------------------------------------------------
; option_test - is one option bit set?
;
;   entry: B = bit number, 0 to 7
;   exit:  Z clear if the option is on, Z set if it is off
;   uses:  A, B
;
; The bit number is masked to 0-7 rather than range-checked and rejected. A
; caller asking for bit 9 has a bug, but returning "off" for it is safe,
; whereas shifting by 9 would produce a mask of zero and read as "off"
; anyway - so the masking makes the safe answer the defined one.
; ---------------------------------------------------------------------------
option_test
                bsr     option_mask             ; A = 1 << B, B preserved
                anda    >installed_options      ; Z set if that bit is clear
                rts

; ---------------------------------------------------------------------------
; option_set - turn one option ON
;
;   entry: B = bit number, 0 to 7
;   uses:  A, B
;
; Read, modify, write - and therefore masked. installed_options is not
; written by any interrupt handler in this rewrite, but the whole class of
; defect in the stock ROM was an unguarded read-modify-write, and making the
; guard the habit is cheaper than deciding case by case and being wrong once.
; ---------------------------------------------------------------------------
; THE BANK FIRST, as serial_write does, and the read-modify-write stays
; guarded. The value is computed under the mask, written to the bank, and only
; then stored to the shadow - so power lost between the two leaves the bank,
; which is what the next boot believes, holding the new byte. The first pass
; here had it the other way round, which would have let a boot undo a toggle.
;
; The read and the store are separate guarded accesses rather than one, which
; is the only thing this changes about the habit above. It is safe on the same
; ground that comment names: nothing in an interrupt handler writes
; installed_options. The guard is kept on each access because the habit is
; worth more than the two cycles.
option_set
                bsr     option_mask             ; A = 1 << B
                DISABLE_INTERRUPTS
                ora     >installed_options      ; A = what it is to become
                RESTORE_INTERRUPTS
                pshs    a
                lbsr    bank_options_put
                puls    a
                DISABLE_INTERRUPTS
                sta     >installed_options
                RESTORE_INTERRUPTS
                rts

; ---------------------------------------------------------------------------
; option_clear - turn one option OFF
;
;   entry: B = bit number, 0 to 7
;   uses:  A, B
;
; THE STOCK FIRMWARE CANNOT DO THIS AT ALL. Page 3 $6DD8 only ORs bits in, so
; every option ever enabled on a unit stays enabled. This is the missing half.
; ---------------------------------------------------------------------------
option_clear
                bsr     option_mask             ; A = 1 << B
                coma                            ; A = ~(1 << B)
                DISABLE_INTERRUPTS
                anda    >installed_options      ; A = what it is to become
                RESTORE_INTERRUPTS
                pshs    a
                lbsr    bank_options_put        ; the bank first, as above
                puls    a
                DISABLE_INTERRUPTS
                sta     >installed_options
                RESTORE_INTERRUPTS
                rts

; ---------------------------------------------------------------------------
; option_toggle - flip one option bit
;
;   entry: B = bit number, 0 to 7
;   uses:  A, B
;
; What the Installed Options screen calls, from page 3 through ABI slot 121.
; ---------------------------------------------------------------------------
option_toggle
                ; THROUGH set AND clear, rather than an EOR of its own. Those
                ; two exist, and nothing called either - so the one guarded,
                ; masked, interrupt-safe write to installed_options had a
                ; second implementation beside it doing the same job its own
                ; way. Two ways to write the option byte is one more than the
                ; owner's rule about that byte allows.
                ; option_test returns Z, NOT CARRY: Z set means the bit is
                ; clear. This branched on a carry option_test never touches,
                ; so the toggle went whichever way the caller's carry
                ; happened to be - and the old mode gate in main_menu.s had the same
                ; mistake, refusing or allowing a mode on a flag nobody set.
                pshs    b
                lbsr    option_test             ; Z set means NOT installed
                puls    b
                beq     option_toggle_on
                lbra    option_clear
option_toggle_on
                lbra    option_set

; ---------------------------------------------------------------------------
; options_clear_all - every option off, the bank first
;
;   uses:  A, B, X, Y, U
;
; The Installed Options screen's All Options Off, from page 3 through ABI slot
; 122. The whole byte, as the stock clears it on a failed RAM signature, and
; in the same order as option_set and option_clear: the bank - which is what
; the next boot believes - and only then the shadow, so power lost between the
; two cannot bring the options back. The old All Options Off cleared the shadow
; alone, and on an instrument with the bank the next power-on restored them.
; ---------------------------------------------------------------------------
options_clear_all
                clra
                lbsr    bank_options_put        ; carry set with no bank, and
                                                ; then there is nothing to keep
                                                ; in step
                DISABLE_INTERRUPTS
                clr     >installed_options
                RESTORE_INTERRUPTS
                rts

; ---------------------------------------------------------------------------
; option_mask - turn a bit number into a mask
;
; Defined after its callers on purpose: the four routines above are what a
; reader of this file wants first, and this is the shared primitive they all
; use. option_test used to carry its own copy of this loop - eight lines
; duplicated to save one BSR - which is the same shape of bloat this rewrite
; exists to remove, so it was removed here too.
;
;   entry: B = bit number
;   exit:  A = 1 << (B & 7), B preserved
;   uses:  A
; ---------------------------------------------------------------------------
option_mask
                pshs    b
                andb    #OPTION_BITS-1
                lda     #$01
option_mask_shift
                tstb
                beq     option_mask_done
                asla
                decb
                bra     option_mask_shift
option_mask_done
                puls    b
                rts
