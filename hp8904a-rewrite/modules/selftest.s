; ===========================================================================
; selftest.s - what the instrument checks about itself at power-on
;
; Three checks, in the order that a failure in one makes the next meaningless:
;
;   1. the ROM, because everything below is code from it
;   2. the working RAM, because everything below stores state there
;   3. the battery-backed RAM's signature, which says whether the serial
;      number and the options can be trusted
;
; THE THIRD ONE IS THE DANGEROUS ONE and it is why this file is careful.
; When the signature does not match, the stock firmware clears
; installed_options and reinstalls defaults - which is correct, because
; acting on option bits from memory that failed its own check is exactly what
; it must not do. But it means a marginal battery can cost an instrument its
; options on a single bad power-up.
;
; So this DOES NOT WRITE on a signature failure. It reports, and the operator
; decides from the service menu. An automatic repair that destroys the thing
; it is repairing is not a repair.
; ===========================================================================

SELFTEST_ROM    equ     $01             ; bit per check, in the result byte
SELFTEST_RAM    equ     $02
SELFTEST_SIG    equ     $04
SELFTEST_PAGE   equ     $08             ; the four A2U13 pages, each giving
                                        ; ITS OWN PAGE NUMBER - not zero. The
                                        ; expected value encodes which slot the
                                        ; page belongs in, which is what lets
                                        ; the check catch a page burnt into the
                                        ; wrong socket; see selftest_pages.
                                        ;
                                        ; THIS CHECK WAS NOT RUN AT POWER-ON.
                                        ; selftest_rom sums $8000-$FFFF and
                                        ; stops, so the paged ROM - two thirds
                                        ; of the firmware by byte count - was
                                        ; never looked at until somebody opened
                                        ; the Diagnostics screen. The stock
                                        ; checks it on every power-on:
                                        ; rom_checksum ($DCA9) sums each page
                                        ; over $4000-$7FFF, stores each result
                                        ; at $2481+page, and sets bit 4 of the
                                        ; event_flags2 high byte on a mismatch
                                        ; - a separate bit from the $20 it uses
                                        ; for A2U12, so a service engineer can
                                        ; tell which device is bad.

; ---------------------------------------------------------------------------
; selftest_rom - the ROM checksum, A2U12
;
;   exit:  Z set if the checksum is zero, which is what it must be
;          B = the checksum
;   uses:  B, X
;
; THE INSTRUMENT'S OWN ROUTINE, ported. rom_checksum ($DCA9; the disassembly
; is firmware/a2u12.asm at file offset 5ca9) is exactly these six
; instructions:
;
;       5ca9: 8e 7f ff        LDX    #$7FFF
;       5cac: 5f              CLRB
;       5cad: 30 01           LEAX   $1,X
;       5caf: e9 84           ADCB   ,X
;       5cb1: 8c ff ff        CMPX   #$FFFF
;       5cb4: 26 f7           BNE    $5CAD
;
; WHAT IT COMPUTES, AND IT IS NOT ADD-WITH-CARRY. CMPX WRITES THE CARRY, so
; the carry each ADCB consumes is the BORROW the previous CMPX left, never
; the carry out of the previous addition. CLRB clears the carry (MC6809 CLR
; leaves N=0 Z=1 V=0 C=0), so the first byte adds with none in; every byte
; after it adds with the borrow the compare leaves while X is still below
; $FFFF, which is 1. That is 32,767 extra counts over the 32,768 bytes, and
; 32767 mod 256 = 255 = -1. So in plain arithmetic:
;
;       B = (the sum of every byte of the image, minus one) mod 256
;
; and requiring B = 0 requires the image's PLAIN BYTE SUM to be 1. The stock
; a2u12.bin does sum to 1 - `python3 -c "print(sum(open('firmware/a2u12.bin',
; 'rb').read()) % 256)"` prints 1 - and booting it in this repository's
; emulator leaves $2480 = $00 and bit 5 of $2202 clear.
;
; THE PREVIOUS VERSION OF THIS ROUTINE COUNTED WITH LEAY so that the carry
; would chain, and its header argued that a `cmpx / bne` loop was "a
; different function, and one no compensation byte can satisfy". The
; instrument contradicts that: it runs exactly that loop and exactly one
; compensation byte satisfies it. A chained-carry sum is a different function
; from the one the hardware's own test computes, and this firmware is not
; free to invent one - build.py places the byte for the function below.
; ---------------------------------------------------------------------------
selftest_rom
                ldx     #$7FFF                  ; one BELOW the first byte:
                                                ; the loop advances before it
                                                ; reads, as the stock's does
                clrb                            ; and CLR clears the carry, so
                                                ; the first byte adds with none
selftest_rom_next
                leax    $1,x                    ; LEA touches Z only, never C
                adcb    ,x
                cmpx    #$FFFF                  ; the last byte of A2U12 - AND
                                                ; THE CARRY SOURCE. While X is
                                                ; below it this compare leaves
                                                ; a borrow, and that borrow is
                                                ; what the next ADCB adds
                bne     selftest_rom_next
                tstb                            ; Z set if the checksum is zero

                rts

; ---------------------------------------------------------------------------
; selftest_ram - can the working RAM hold what is written to it?
;
;   exit:  Z set if every cell read back
;   uses:  A, B, X
;
; Each cell gets a value derived from its own address, so a stuck ADDRESS
; line shows up as well as a stuck data line. Writing the same byte
; everywhere finds only the second kind, and an address fault is the one that
; corrupts data silently.
;
; SCRATCH ONLY, and the bounds are named against the scratch symbols rather
; than written as literals. They WERE literals - SCRATCH_END to $3000 - and
; when scratch moved to $3A80 the lower bound ended up ABOVE the upper one,
; so the loop stored one byte, verified that byte, and reported PASS.
; Poisoning the whole span and running it changed exactly one byte.
;
; What is deliberately NOT walked: $268F-$3A7A, the twelve save/recall
; setups, and $3FEE-$3FFF, the serial and the options. A destructive walk of
; either is the fault the owner's standing rule exists to prevent, which is
; why the bounds are symbols that move with the thing they describe.
;
; The walk destroys scratch by design, so it rebuilds it afterwards.
; ---------------------------------------------------------------------------
selftest_ram
                ldx     #SCRATCH_BASE
selftest_ram_write
                tfr     x,d
                stb     ,x+
                cmpx    #SCRATCH_END
                blo     selftest_ram_write

                ldx     #SCRATCH_BASE
selftest_ram_verify
                tfr     x,d
                cmpb    ,x+
                bne     selftest_ram_bad
                cmpx    #SCRATCH_END
                blo     selftest_ram_verify

                lbsr    scratch_reset           ; the walk overwrote every
                orcc    #CC_ZERO                ; scratch byte with its own
                rts                             ; low address; put them back
selftest_ram_bad
                lbsr    scratch_reset           ; ON THE FAILURE PATH TOO.
                andcc   #~CC_ZERO               ; This returned straight out,
                rts                             ; leaving all 896 bytes of
                                                ; scratch holding
                                                ; address-derived rubbish
                                                ; while the boot carried on
                                                ; into it - a garbage
                                                ; tick_callback in front of
                                                ; foreground_tick's `jmp ,x`.
                                                ; A failed RAM test is exactly
                                                ; when the firmware must not
                                                ; then jump through whatever
                                                ; the test left behind. The
                                                ; flag is set after the call
                                                ; on both paths, because
                                                ; scratch_reset does not
                                                ; preserve CC.

; ---------------------------------------------------------------------------
; selftest_signature - is the battery-backed data trustworthy?
;
;   exit:  Z set if the signature matches
;   uses:  A, B, X, Y
;
; Compares the bytes at ram_signature against the copy in ROM. A mismatch
; means the battery has been out, or the RAM has failed, and the serial and
; options in it cannot be relied on.
;
; IT DOES NOT REPAIR ANYTHING. See the note at the head of this file.
; ---------------------------------------------------------------------------
SIGNATURE_LEN   equ     54

selftest_signature
                ldx     #ram_signature
                ldy     #signature_rom
                ldb     #SIGNATURE_LEN
selftest_sig_next
                lda     ,x+
                cmpa    ,y+
                bne     selftest_sig_bad
                decb
                bne     selftest_sig_next
                orcc    #CC_ZERO
                rts
selftest_sig_bad
                andcc   #~CC_ZERO
                rts

; ---------------------------------------------------------------------------
; selftest_signature_write - make the battery-backed RAM trustworthy
;
;   uses:  A, B, X, Y
;
; Copies signature_rom over ram_signature, so that selftest_signature will
; match from now on.
;
; NOTHING WROTE THESE BYTES AT ALL. selftest_signature compared them and this
; file said, in capitals, that it does not repair anything - so a unit whose
; battery had been out failed the check on every power-on, forever, with no
; path back to a trusted state. That is the opposite of the goal this rewrite
; exists for: a flat battery must not be a board-replacement job.
;
; It is still not a repair of the DATA. The serial number, the installed
; options and the saved registers are not touched here and are not
; recoverable from ROM - the operator re-enters the serial and the options
; from their own screens, which is exactly what those screens are for. All
; this says is "this firmware has now initialised this RAM", which is the
; only thing the signature ever meant.
;
; The caller decides when. reset_entry calls it only when the check has just
; failed, and clears the live preferences in the same breath, because a byte
; of foreign battery RAM must not be read as a setting the operator chose.
; ---------------------------------------------------------------------------
selftest_signature_write
                ldx     #ram_signature
                ldy     #signature_rom
                ldb     #SIGNATURE_LEN
                DISABLE_INTERRUPTS
selftest_sig_write_next
                lda     ,y+
                sta     ,x+
                decb
                bne     selftest_sig_write_next
                RESTORE_INTERRUPTS
                rts

; The pattern the signature is compared against. Fifty-four bytes, matching
; what the check reads. Its content does not matter - only that it is the
; same here and in RAM - so it is a recognisable run rather than anything
; meaningful, which makes a partial match obvious in a memory dump.
signature_rom
                fcb     $A5,$5A,$C3,$3C,$0F,$F0,$69,$96
                fcb     $A5,$5A,$C3,$3C,$0F,$F0,$69,$96
                fcb     $A5,$5A,$C3,$3C,$0F,$F0,$69,$96
                fcb     $A5,$5A,$C3,$3C,$0F,$F0,$69,$96
                fcb     $A5,$5A,$C3,$3C,$0F,$F0,$69,$96
                fcb     $A5,$5A,$C3,$3C,$0F,$F0,$69,$96
                fcb     $A5,$5A,$C3,$3C,$0F,$F0

; ---------------------------------------------------------------------------
; selftest_run - all three, reporting what passed
;
;   exit:  B = a bit per check that PASSED; B = 0 means everything failed
;   uses:  A, B, X, Y
;
; Runs all three even if the first fails, because an engineer wants to know
; whether it is one fault or three. Reporting the passes rather than the
; failures means a zero is unambiguously bad, whichever way somebody reads it.
; ---------------------------------------------------------------------------
; THE ANSWER IS ACCUMULATED ON THE STACK, NOT IN SCRATCH.
;
; It was built up in selftest_result, which scratch.inc places at
; SCRATCH_BASE+$170 - $3BF0 - and that address is inside the span
; selftest_ram walks and scratch_reset then clears. So the ROM bit was set,
; the RAM test overwrote it with an address-derived byte, scratch_reset
; cleared it, and the routine reported that the ROM check had failed on every
; power-on of a perfectly good instrument. A result cannot be stored in the
; memory a test in the same sequence is about to destroy.
;
; The stack lives below $2200, nowhere near scratch, so it survives the walk.
; selftest_result is written once at the end, where it is a record of what
; happened rather than working storage.
selftest_run
                clrb
                pshs    b                       ; the accumulator

                lbsr    selftest_rom
                bne     selftest_run_ram
                lda     ,s
                ora     #SELFTEST_ROM
                sta     ,s
selftest_run_ram
                lbsr    selftest_ram
                bne     selftest_run_pages
                lda     ,s
                ora     #SELFTEST_RAM
                sta     ,s
selftest_run_pages
                lbsr    selftest_pages
                bne     selftest_run_sig
                lda     ,s
                ora     #SELFTEST_PAGE
                sta     ,s
selftest_run_sig
                lbsr    selftest_signature
                bne     selftest_run_done
                lda     ,s
                ora     #SELFTEST_SIG
                sta     ,s
selftest_run_done
                puls    b
                stb     >selftest_result        ; recorded only now, after the
                rts                             ; RAM test has finished with
                                                ; that region

; ---------------------------------------------------------------------------
; selftest_pages - the four A2U13 pages, each giving its own page number
;
;   exit:  Z set if every page gave its own number; Z clear if one did not,
;          and B is then the page that failed
;   uses:  A, B, X, Y
;
; The same sum the A2U12 check uses, run once per page with the window
; switched to it. The sum and the switch are both routines that already exist
; and are already commented - diag_sum_span for the arithmetic,
; page_select_and_verify for the switch, which confirms the switch took by
; reading back the page number the image carries at $4000. A page that fails
; to switch is a failed checksum rather than a sum of whatever was in the
; window, which is the only honest way to report it.
;
; THE EXPECTED VALUE IS THE PAGE NUMBER, NOT ZERO, and that is the point of
; the whole check. The stock's rom_checksum ($DCA9; firmware/a2u12.asm at
; file offset 5cd2) sums a page over $4000-$7FFF into B, stores it at
; $2481+page with `STB A,X` at 5ce5, and then at 5ce7 compares it against
; $247F - WHICH HOLDS THE PAGE INDEX, not zero:
;
;       5cdf: 8e 24 81        LDX    #$2481
;       5ce2: b6 24 7f        LDA    $247F       ; the page index
;       5ce5: e7 86           STB    A,X
;       5ce7: f1 24 7f        CMPB   $247F       ; against the page index
;       5cea: 27 08           BEQ    $5CF4
;
; (The generated comment above that routine in firmware/a2u12.asm reads "If
; nonzero -> sets $2202 bit 4". That comment is WRONG and the instructions
; are the source of truth.) Booting the stock in this repository's emulator
; leaves $2481=$00 $2482=$01 $2483=$02 $2484=$03 and $2202=$00, and the plain
; byte sums of the four stock page images are 1, 2, 3 and 4 - the checksum
; being the sum less one, exactly as selftest_rom's header derives.
;
; BECAUSE THE EXPECTED VALUE ENCODES THE SLOT, this test detects a page
; programmed into the WRONG SOCKET. A test that expects zero from every page
; cannot: every page balanced to zero sums to zero wherever it is plugged in.
; This firmware is about to burn a four-page part, so that is not an academic
; property, and it is why the compensation bytes are computed to the
; instrument's per-page targets rather than to a uniform zero.
;
; IT CATCHES A SWAPPED PART, NOT A RELABELLED ONE, and the digit read-back is
; the other half of the pair. Two parts exchanged in their sockets are caught
; twice over: the digit at $4000 is the wrong one, and the checksum is out by
; the difference of the two slot numbers. But an image whose IDENTITY DIGIT
; has been changed to match a different slot satisfies the checksum there,
; because the digits are consecutive ASCII and the targets are consecutive
; numbers, so relabelling moves the sum by exactly the amount the target
; moves - measured on the built pages, every one of them sums to $D1 with its
; digit byte left out. That case is what page_select_and_verify's read-back
; is for. Neither check subsumes the other and this firmware runs both.
;
; HOW MANY PAGES THERE ARE is the one part of $DCD2 not reproduced. The stock
; selects page 0, reads the count from $4002 and decrements it to get the
; last page index (5cc5-5ccc), and its page 0 image carries $04 there. This
; rewrite cannot: $4002 is inside the operand of page 0's first entry vector,
; `jmp channel_config_open` at $4001. PAGE_COUNT is assembled in instead,
; which is the same number by the same authority - the build makes exactly
; four page images - and is not a byte an operator can get wrong.
;
; WHY IT IS A SEPARATE BIT from SELFTEST_ROM. The stock uses two: bit 5 of
; the event_flags2 high byte for A2U12 and bit 4 for the pages, and
; foreground_main_loop ($83A0) weights them 2 and 1 in the number it puts on
; the display. An engineer holding that number needs to know which device to
; pull, and one bit for "some ROM is bad" does not say.
;
; THE WINDOW IS LEFT ON THE LAST PAGE CHECKED, and current_page says so
; because page_select_and_verify maintains it. That is better than the state
; this leaves without it: boot sets current_page to PAGE_UNKNOWN precisely
; because nothing had chosen a page, and after this something has.
; ---------------------------------------------------------------------------
selftest_pages
                clrb                            ; B = the page
selftest_page_next
                pshs    b
                lbsr    page_select_and_verify
                bcs     selftest_page_failed    ; the switch did not take
                ldx     #PAGE_WINDOW
                ldy     #PAGE_WINDOW_END        ; through the window's last
                                                ; byte: the stock's `cmpx
                                                ; #$7FFF` at 5cda
                lbsr    diag_sum_span           ; B = this page's checksum
                cmpb    ,s                      ; which must be the page's own
                bne     selftest_page_failed    ; number, and nothing else
                puls    b
                incb
                cmpb    #PAGE_COUNT
                blo     selftest_page_next
                orcc    #CC_ZERO                ; every page gave its own
                rts                             ; number
selftest_page_failed
                puls    b                       ; B = the page that failed, so
                andcc   #~CC_ZERO               ; a caller that wants to name
                rts                             ; it can
