; ===========================================================================
; service_diag.s - the diagnostic screens
;
; In the stock firmware these sit behind a six-digit access code, 092448,
; held as ASCII at page 3 $4466 and compared with mem_compare_bytes by
; diagnostic_access_code_handler ($4B85). There is no code here: the
; diagnostics menu is an ordinary entry on the service menu.
;
; A number you must already know is not a security measure on a signal
; generator. It is a way to lose access to your own instrument.
; ===========================================================================

; THE REPEATING ROM CHECK'S DISPLAY. Line 1 is a name and an address; line 2
; is the stock's own template, character for character - "Checksum   H s/b
; H  Pass      Fail    " at page 3 d426a - so the fields land in the columns
; an engineer who knows this instrument already looks at.
diag_rom_l1_main fcc    "Main ROM        "
diag_rom_l1_page fcc    "Opt ROM page    "
; THE EXIT LABEL IS THE STOCK'S GLYPH PAIR, not the words 'f4='. Its frame at
; page 3 $4252 reads '    @     H (     H) ' then $00,$04 then ' Exit', and
; $00,$04 renders as an underlined f4 from CGRAM - the same pair every menu
; record uses. Driven side by side 2026-09-11: the stock's line 1 ends
; '( 6A14H) f4 Exit' where this read '(07FEFH) f4=Exit'.
diag_rom_frame1 fcc     "@     H (     H) "
                fcb     $00,$04
                fcc     " Exit"
diag_rom_frame2 fcc     "Checksum   H s/b   H  Pass      Fail    "
diag_rom_unknown fcc    "??"
; The Repetitive Ram Check's two lines, the stock's own: d41a0 + d4292 make
; line 1 and d42ac is line 2, with the pass count five digits wide at column 7
; and the fail count five wide at column 27. $00 and $04 are the softkey
; font's 'f' and '4'; see lcd_glyphs in lcd.s.
diag_lcd_title  fcc     "Diagnostics - LCD Display Check  "
                fcb     $00,$04
                fcc     " Exit"
diag_ram_title  fcc     "Diagnostics - Repetitive Ram Check      "
diag_ram_line2  fcc     "Passed       times, failed       "
                fcb     $00,$04
                fcc     " Exit"
DIAG_PROBE_CHAR equ     $2A             ; '*', the cell the display check
DIAG_PROBE_POS  equ     LCD_LINE2+34    ; where the address counter is shown
                                        ; writes and reads back. A number
                                        ; because this assembler takes a
                                        ; character literal in an immediate
                                        ; but not in an equ.
; THE STOCK'S OWN COLUMNS. keyboard_check_screen_init ($4B1E) paints
; 'Diagnostics - ' at 0 and 'Manual Keyboard Check     ' at $0E, so line 1
; ends in five spaces; the shared tail at $4AAD writes the key's eight-
; character name over the first eight columns of line 2 and the running total
; as four digits at position $24 - line 1, column 36.
DIAG_KBD_NAME_POS equ  LCD_LINE2       ; the name, over the first eight
                                        ; columns of the sentence below it
DIAG_KBD_TOTAL_POS equ LCD_LINE1+36   ; and the running total, on line 1 in
                                      ; the four zeros the title leaves for
                                      ; it. It is on line 1 because line 2
                                      ; columns 16-23 are the key NAME, and
                                      ; the exit hint went there first - which
                                      ; would have painted over every name.

; THE RUNNING KEY TOTAL, and where every byte of it comes from.
;
; The stock's Keyboard Check keeps a sum: each of the 55 arms of its $4A3F
; dispatch stores a distinct byte, the shared tail at $4AAD does
; LDB 4,s / CLRA / ADDD >$3FA3 / STD >$3FA3, and $3FA3 is rendered as four
; digits at LCD position $24 - the last four columns of line 1.
;
; THIS WAS NOT REPRODUCED, and the reason given was that the constants' MEANING
; is not established: they are not the matrix positions in $EF4A, and the
; disassembly's own note calls them "a second, non-matching key numbering". All
; of that is true and NONE of it is a reason not to reproduce the number. An
; engineer checking a keyboard against a service procedure needs the SAME
; total, not an account of what it signifies. The constants are in the ROM.
;
; So they were read out of it: every arm of $4A3F, its own 8-bit immediate,
; 55 of them, 37 distinct, spanning $00 to $24. The table below is that
; extraction, indexed by key code exactly as the stock's dispatch is - which
; is why arm 7 is $17 and KEY_SHIFT is 7.
KBD_WEIGHTS     equ     55              ; codes 0 to 54 have one

diag_kbd_weight
                fcb     $00                     ;  0 nokey
                fcb     $20                     ;  1 local
                fcb     $01                     ;  2 f1
                fcb     $0D                     ;  3 phase
                fcb     $0E                     ;  4 waveform
                fcb     $05                     ;  5 ampl
                fcb     $04                     ;  6 freq
                fcb     $17                     ;  7 shift
                fcb     $0A                     ;  8 f2
                fcb     $1C                     ;  9 minus
                fcb     $13                     ; 10 digit_7
                fcb     $0F                     ; 11 4
                fcb     $06                     ; 12 digit_1
                fcb     $18                     ; 13 inc_set
                fcb     $0B                     ; 14 last
                fcb     $1D                     ; 15 digit_0
                fcb     $14                     ; 16 digit_8
                fcb     $10                     ; 17 5
                fcb     $07                     ; 18 digit_2
                fcb     $1A                     ; 19 up_arrow
                fcb     $02                     ; 20 next
                fcb     $1E                     ; 21 decimal_point
                fcb     $15                     ; 22 digit_9
                fcb     $11                     ; 23 6
                fcb     $08                     ; 24 digit_3
                fcb     $19                     ; 25 down_arrow
                fcb     $03                     ; 26 f3
                fcb     $1F                     ; 27 enter
                fcb     $16                     ; 28 degree
                fcb     $12                     ; 29 hz
                fcb     $09                     ; 30 khz
                fcb     $1B                     ; 31 backspace
                fcb     $0C                     ; 32 f4
                fcb     $21                     ; 33 spare0
                fcb     $22                     ; 34 spare1
                fcb     $23                     ; 35 spare2
                fcb     $24                     ; 36 spare3
                fcb     $04                     ; 37 freq
                fcb     $0D                     ; 38 phase
                fcb     $20                     ; 39 local
                fcb     $05                     ; 40 ampl
                fcb     $01                     ; 41 f1
                fcb     $0E                     ; 42 waveform
                fcb     $18                     ; 43 inc_set
                fcb     $02                     ; 44 next
                fcb     $19                     ; 45 down_arrow
                fcb     $0B                     ; 46 last
                fcb     $1A                     ; 47 up_arrow
                fcb     $1B                     ; 48 backspace
                fcb     $03                     ; 49 f3
                fcb     $0A                     ; 50 f2
                fcb     $0C                     ; 51 f4
                fcb     $1F                     ; 52 enter
                fcb     $00                     ; 53 invalid
                fcb     $00                     ; 54 double

; The stock's three strings, character for character: d41a0 + d41c8 make line
; 1, d41e2 is line 2 until a key is pressed, and d420a is line 2 from then on
; with the key's name written over its first eight columns.
;
; $00 and $04 are the softkey font's 'f' and '4' - two CGRAM characters, two
; columns, so each of these is forty columns wide. See lcd_glyphs in lcd.s.
; The stock spells its softkey labels this way and this firmware had been
; spelling them with ASCII letters, which is the same width and a different
; face from the one silkscreened on the panel.
diag_kbd_title  fcc     "Diagnostics - Manual Keyboard Check     "
diag_kbd_none   fcc     "Press "
                fcb     $22
                fcb     $00,$04
                fcb     $22
                fcc     " twice to exit this check.    "
diag_kbd_line2  fcc     "         key was pressed. Exit= "
                fcb     $22
                fcb     $00,$04
                fcb     $22
                fcc     " x 2"

; THE ONE-SHOT ALL-IMAGES CHECKSUM IS GONE, with its 'All five images PASS'
; and 'One or more FAIL' strings. It summed the five images once and printed
; a verdict, and the screen it served is now the stock's repeating one -
; diag_rom_span below sums ONE image per pass and diag_rom_one reports it
; with the address, the stored byte and a running count. Nothing called
; diag_rom_checksum but that screen, and COVERAGE.txt cites no arm against
; it. diag_sum_span stays: selftest.s uses it for the power-on ROM check.
;
; ---------------------------------------------------------------------------
; diag_sum_span - the ROM self-test's checksum over one span
;
;   entry: X = the first byte, Y = the LAST byte of the span
;   exit:  B = the checksum; Z set if it is zero
;   uses:  B, X (Y is restored)
;
; THE INSTRUMENT'S LOOP, not a sum with the carry chained. rom_checksum
; ($DCA9; firmware/a2u12.asm at file offsets 5ca9 and 5cd2) runs
;
;       LDX #span-1 / CLRB / LEAX $1,X / ADCB ,X / CMPX #span-end / BNE
;
; and CMPX WRITES THE CARRY. The carry each ADCB takes is therefore the
; borrow the previous compare left - 1 while X is below the limit - and never
; the carry out of the previous addition. The result is
;
;       B = (the plain byte sum of the span, minus one) mod 256
;
; which is why the limit, and not a count, is the parameter: the compare that
; ends the loop is the same instruction that supplies the carry, so the two
; cannot be separated. selftest_rom's header derives the arithmetic in full
; and names the measurements that confirm it.
;
; THE LIMIT GOES ON THE STACK because the 6809 has no register-to-register
; compare; `cmpx ,s` sets the carry exactly as `cmpx #immediate` does.
; ---------------------------------------------------------------------------
diag_sum_span
                pshs    y                       ; the limit, for the compare
                                                ; at the foot of the loop
                leax    -1,x                    ; one BELOW the first byte:
                                                ; the loop advances then reads
                clrb                            ; CLR clears the carry, so the
                                                ; first byte adds with none in
diag_sum_next
                leax    $1,x                    ; LEA touches Z only, never C
                adcb    ,x
                cmpx    ,s                      ; the limit AND the carry the
                bne     diag_sum_next           ; next ADCB will take
                puls    y                       ; PULS without CC in the list
                                                ; leaves the flags alone
                tstb                            ; Z set if the checksum is zero
                rts

DIAG_ROM_DWELL  equ     1500            ; ms one image stays up. The stock's
                                        ; delay_ms($05DC) at the foot of
                                        ; rom_check_loop, which is 1500
DIAG_ROM_SLICE  equ     5               ; ms between key polls inside that
                                        ; dwell. The stock reads key_code
                                        ; ($24DC) once per pass because its
                                        ; scan is interrupt-driven and the
                                        ; code is already in RAM; this
                                        ; firmware's keypad is POLLED, and
                                        ; keypad_read reports only what the
                                        ; matrix holds at the instant it runs.
                                        ; At 50 ms a press shorter than that
                                        ; fell between two polls and f4 did
                                        ; nothing at all - which is what the
                                        ; first version of this screen did in
                                        ; the emulator, where a press is
                                        ; 20,000 cycles. Five milliseconds is
                                        ; below any press a finger can make
DIAG_ROM_SLICES equ     DIAG_ROM_DWELL/DIAG_ROM_SLICE
DIAG_ROM_COMP12 equ     $FFEF           ; where balance_checksum puts A2U12's
                                        ; compensation byte: 17 below the top
                                        ; of the image, the last byte that is
                                        ; neither code nor a vector.
                                        ;
                                        ; NOT THE STOCK'S SPOT, which is
                                        ; $EA14: rom_check_screen_init at page
                                        ; 3 $4766 loads #$EA14 into $3F82 and
                                        ; reads the byte there into $3F86.
                                        ; That address is in the middle of the
                                        ; stock's code and belongs to nothing
                                        ; this rewrite has; the rewrite's own
                                        ; images are laid out freely
                                        ; (the owner's ruling, 2026-01-01)
                                        ; and $FFEF is in its padding.
; A page's own compensation byte sits at the same distance below the top of
; its 16K image: PAGE_WINDOW+$3FEF.
;
; THE INSTRUMENT PUTS A PAGE'S AT $4001 - rom_check_screen_init at page 3
; $4772 does `LDX #$4000 / LEAX $1,X / STX $3F84` and $47AC reads the byte
; through `LDU #$4001`, and the stock page images carry $74 $72 $41 $DF at
; offset 1 of pages 0 to 3, which are not code. This rewrite cannot use that
; byte: $4001 is its first page entry vector (`jmp channel_config_open` in
; hp8904a-rewrite/images/a2u13_page0.s), part of the free layout the
; architect allowed on 2026-01-01. $7FEF is safe instead because it lies in
; the $FF padding above every page's code - a page has no vector table, so
; nothing else claims the top of the image - and build.py refuses to place
; the byte if the spot is not still $FF when it gets there, so a page that
; ever grows into it fails the build rather than losing an instruction.
;
; The address is written out at each of its two uses rather
; than given a name here. asm6809.py resolves an `equ` in one pass and
; a2u12_all.inc includes this file BEFORE paging.s, so a name defined here in
; terms of PAGE_WINDOW or PAGE_COUNT is undefined when it is read - while the
; same symbols in an instruction's operand resolve on a later pass, which is
; how diag_rom_checksum above already uses them.
DIAG_ROM_NAME_LEN equ   16              ; the name field, columns 0 to 15
DIAG_ROM_FRAME1_LEN equ 24              ; and the rest of line 1
DIAG_ROM_COL_FRAME1 equ LCD_LINE1+16
DIAG_ROM_COL_PAGE equ   LCD_LINE1+13    ; 'Opt ROM page N': the digit
DIAG_ROM_COL_ADDR equ   LCD_LINE1+18    ; the CPU address, four digits
DIAG_ROM_COL_OFFS equ   LCD_LINE1+26    ; the burn-set offset's low four; its
                                        ; fifth digit is the column before
DIAG_ROM_COL_SUM equ    LCD_LINE2+9     ; the byte the image carries
DIAG_ROM_COL_SBH equ    LCD_LINE2+17    ; the byte it should carry
DIAG_ROM_COL_PASS equ   LCD_LINE2+27    ; and the two counts
DIAG_ROM_COL_FAIL equ   LCD_LINE2+37

; ---------------------------------------------------------------------------
; diag_rom_run - the repeating per-image ROM check
;
;   uses:  A, B, X, Y, U
;
; THE STOCK'S SCREEN, ported out of the instruction stream at page 3 $446C
; (rom_check_loop, set up by rom_check_screen_init $471C). What stood here
; was a single pass: sum all five images once, print PASS or FAIL, wait for a
; key. That is not the screen. The stock's runs until f4 is pressed and shows,
; one image per pass:
;
;   Main ROM        @ FFEFH (07FEFH) f4=Exit
;   Checksum 3C H s/b 3C H  Pass   7 Fail   0
;
;   * which image this pass looked at - 'Main ROM' (d4232) or 'Opt ROM page N'
;     (d4242, the digit at column 13);
;   * the CPU address of that image's compensation byte and its offset into
;     the burn set, because that is what somebody with a programmer in front
;     of them needs to know;
;   * the byte the image actually carries there, and the byte it would have
;     to carry for the image to sum right - equal when the device is good,
;     and the difference between them is the error;
;   * a pass and a fail count PER IMAGE, which is the point of a screen that
;     repeats: an intermittent device shows a fail count that climbs while the
;     other four stay at zero, and one pass/fail can never show that.
;
; WHAT THE TARGET CHECKSUM IS, and it is now the stock's. A2U12 must give
; zero and A2U13 page p must give p: rom_check_loop holds the expected value
; at 4,s and puts it there with `clr 4,s` for the main ROM at $44AD and with
; `LDB $3F80 / SUBB #$01 / STB 4,s` at $4530 for a page, then compares it
; against $2480+p at $461B-$461F. build.py's balance_checksum places each
; image's compensation byte for exactly those targets.
;
; THIS BUILD USED TO BALANCE EVERY IMAGE TO ZERO, which was an unrecorded
; divergence from the instrument and threw away the diagnostic that matters
; most on a four-page part: because the expected value encodes the page
; number, the stock's test catches a page burnt into the wrong socket, and a
; test that expects zero from every page cannot. See selftest_pages.
;
; The s/b field is the expected checksum plus the stored byte less the sum,
; which is the stock's own arithmetic at $45DB-$45E9 (4,s + $3F86[i] -
; $2480[i]).
;
; The counters SATURATE at 255 rather than wrapping. The stock's are bytes
; incremented with `addb #$01` and displayed in three digits, so its fail
; count goes 255 -> 000 and reads as a screen that has just been reset -
; exactly the wrong thing to show somebody watching for an intermittent
; fault. Recorded as a deliberate difference in READTHROUGH.md.
;
; HOW IT LEAVES, and why not service_back_handler. This runs inside the
; menu's `jsr ,x` (screen.s menu_key_run), which pushed the nav stack before
; the call and calls nav_undo_push after it if screen_handler is unchanged.
; service_back_handler POPS that stack, so calling it from in here would pop
; and then undo, leaving the depth one level too shallow. menu_reopen_current
; repaints the menu that is up and takes its keys back without touching the
; stack, so the menu's own bookkeeping is right either way.
; ---------------------------------------------------------------------------
diag_rom_run
                lbsr    screen_take_dismiss     ; the keys, before anything is
                                                ; painted. Nothing reaches
                                                ; this handler while the loop
                                                ; below runs - the loop reads
                                                ; the keypad itself, as the
                                                ; stock's does - but a screen
                                                ; that paints without taking
                                                ; them leaves the last one's
                                                ; handler live over the new
                                                ; display, and that is true of
                                                ; every path out of here

                clrb                            ; both counters, all five
                clra                            ; images, and the selection
diag_rom_zero                                   ; back to the first
                ldx     #diag_rom_passes
                stb     a,x
                ldx     #diag_rom_fails
                stb     a,x
                inca
                cmpa    #PAGE_COUNT+1   ; the four pages and A2U12
                blo     diag_rom_zero
                clr     >diag_rom_index

                lda     #DIAG_ROM_COL_FRAME1    ; the fixed half of the
                ldx     #diag_rom_frame1        ; display, painted once:
                ldb     #DIAG_ROM_FRAME1_LEN    ; only the numbers inside it
                lbsr    lcd_write               ; change from pass to pass
                lda     #LCD_LINE2
                ldx     #diag_rom_frame2
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write

diag_rom_pass_loop
                lbsr    diag_rom_one            ; sum this image and show it -
                bcs     diag_rom_leave          ; and it polls while it sums
                lbsr    diag_rom_dwell          ; carry set: f4 or LOCAL
                bcs     diag_rom_leave

                lda     >diag_rom_index         ; on to the next image,
                inca                            ; wrapping - the stock's
                cmpa    #PAGE_COUNT+1   ; the four pages and A2U12        ; $3F80 against $3F81 at
                blo     diag_rom_next_store     ; $46C4
                clra
diag_rom_next_store
                sta     >diag_rom_index
                bra     diag_rom_pass_loop

diag_rom_leave
                lbra    menu_reopen_current

; ---------------------------------------------------------------------------
; diag_rom_dwell - hold this image on the display, watching for the way out
;
;   exit:  carry SET if f4 or LOCAL was pressed
;   uses:  A, B, X
;
; f4 because that is the key the stock's loop leaves on: rom_check_loop
; compares key_code ($24DC) with $0020 at its head, and $20 is f4 in this
; firmware's table as well (common/keys.inc, KEY_F4 equ 32). LOCAL as well,
; because in this firmware LOCAL is the way out of anything and the foreground
; cannot offer it here - the foreground is not running, this loop is.
;
; Every other key is swallowed. The stock's loop ignores them too, and
; dismissing on any key would end a test that is meant to run for a while on
; the first mis-press.
; ---------------------------------------------------------------------------
diag_rom_dwell
                ldx     #DIAG_ROM_SLICES
diag_rom_dwell_slice
                pshs    x
                lbsr    diag_exit_poll           ; carry set: f4 or LOCAL
                bcs     diag_rom_dwell_out
                ldd     #DIAG_ROM_SLICE
                lbsr    delay_ms
                puls    x
                leax    -1,x
                bne     diag_rom_dwell_slice
                andcc   #~CC_CARRY
                rts
diag_rom_dwell_out
                puls    x
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; diag_exit_poll - has the operator asked to leave?
;
;   exit:  carry SET if f4 or LOCAL is down
;   uses:  A, B, X
;
; One routine, called from the dwell AND from inside the checksum, because a
; press that lands while an image is being summed has to count too. See
; diag_rom_span.
; ---------------------------------------------------------------------------
diag_exit_poll
                lbsr    keypad_read             ; Z set when nothing is new
                beq     diag_exit_poll_none
                cmpb    #KEY_F4
                beq     diag_exit_poll_out
                                                ; AND ONLY f4. rom_check_loop
                                                ; ($446C) compares key_code
                                                ; ($24DC) with $0020 at its
                                                ; head and tests nothing else,
                                                ; so LOCAL is not a way out of
                                                ; this loop on the instrument
diag_exit_poll_none
                andcc   #~CC_CARRY
                rts
diag_exit_poll_out
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; diag_rom_span - this screen's checksum over one span, polling as it goes
;
;   entry: X = the first byte, Y = the LAST byte of the span
;   exit:  B = the checksum; carry SET if the operator asked to leave, and
;          the checksum is then meaningless
;   uses:  A, B, X (Y is restored)
;
; THE SAME ARITHMETIC AS diag_sum_span, in chunks. Summing A2U12 is 32768
; byte reads, and this firmware's keypad is polled rather than latched by an
; interrupt the way the stock's key_code ($24DC) is - so with the poll only
; in the dwell, an f4 pressed and released while an image was being summed
; was never seen at all, and the screen ran on. That is not a hypothetical:
; it is what the first version of this screen did, and it is why the poll is
; in here.
;
; THE CARRY IS THE BORROW THE COMPARE LEFT, and it has to survive the poll -
; that is what the PSHS CC at each chunk boundary is for. Inside a chunk
; nothing disturbs it: LEAX sets Z alone and DECA sets N, Z and V but not the
; carry, so the only instruction that writes it is the CMPX that ends each
; iteration, which is exactly the instrument's arrangement. See
; diag_sum_span for the arithmetic and selftest_rom for its derivation.
; ---------------------------------------------------------------------------
DIAG_ROM_CHUNK  equ     256             ; bytes between polls. About 1.3 ms of
                                        ; 6809 at a megahertz, so no press a
                                        ; finger can make falls between two
diag_rom_span
                pshs    y                       ; the limit, for the compare at
                                                ; the foot of the loop. The
                                                ; chunk boundary's PSHS CC and
                                                ; PSHS B go on top of it and
                                                ; are both popped again before
                                                ; the branch back, so inside
                                                ; the loop ,s is the limit
                leax    -1,x                    ; one BELOW the first byte
                clrb                            ; CLR clears the carry
diag_rom_span_chunk
                lda     #DIAG_ROM_CHUNK-1       ; 255 more after this one
diag_rom_span_byte
                leax    $1,x
                adcb    ,x
                cmpx    ,s                      ; the whole span done? AND the
                beq     diag_rom_span_end       ; carry the next ADCB takes
                deca                            ; DEC leaves the CARRY alone
                bne     diag_rom_span_byte

                pshs    cc                      ; the borrow the compare left,
                pshs    b                       ; which the poll would destroy
                lbsr    diag_exit_poll
                bcc     diag_rom_span_go
                puls    b
                puls    cc
                puls    y                       ; the limit, off the stack
                orcc    #CC_CARRY               ; the operator's answer, not
                rts                             ; the checksum's carry
diag_rom_span_go
                puls    b
                puls    cc                      ; the carry chain, unbroken
                bra     diag_rom_span_chunk
diag_rom_span_end
                puls    y                       ; the limit; PULS without CC
                                                ; in the list leaves the flags
                tstb                            ; Z set if the checksum is
                andcc   #~CC_CARRY              ; zero, and nobody left
                rts

; ---------------------------------------------------------------------------
; diag_rom_expected - the checksum the selected image has to give
;
;   exit:  A = zero for A2U12, the page's own number for an A2U13 page
;   uses:  A
;
; The instrument's targets, and the reason this screen can tell a page in the
; wrong socket from a good one. rom_check_loop keeps the same value at 4,s:
; `clr 4,s` at $44AD for the main ROM, and `LDB $3F80 / SUBB #$01 / STB 4,s`
; at $4530 for a page, $3F80 being the image index with A2U12 at zero and the
; pages at one to four - the same numbering diag_rom_index uses.
; ---------------------------------------------------------------------------
diag_rom_expected
                lda     >diag_rom_index
                beq     diag_rom_expected_out   ; index 0 is A2U12: zero
                deca                            ; index 1 to 4 is page 0 to 3,
diag_rom_expected_out                           ; and a page must give its own
                rts                             ; number

; ---------------------------------------------------------------------------
; diag_rom_one - sum the selected image and paint the display for it
;
;   uses:  A, B, X, Y
;
; THE PAGE IS LEFT MAPPED when this returns, as the stock's screen leaves
; $247B set. Nothing in this firmware reads the window without selecting
; first: page_call (paging.s) runs page_select_and_verify and refuses to call
; at all if it fails, so a page left behind here is never read by anything
; that has not asked for it.
; ---------------------------------------------------------------------------
diag_rom_one
                lda     >diag_rom_index
                bne     diag_rom_one_page

                ldx     #$8000                  ; A2U12: the resident image,
                ldy     #$FFFF                  ; $8000 through its last byte,
                                                ; no page switch
                lbsr    diag_rom_span           ; B = the checksum
                bcs     diag_rom_one_leave      ; unless the operator left
                lda     >DIAG_ROM_COMP12        ; and the byte it carries
                bra     diag_rom_one_judge

diag_rom_one_page
                deca                            ; index 1 to 4 is page 0 to 3
                tfr     a,b
                lbsr    page_select_and_verify
                bcs     diag_rom_one_unmapped
                ldx     #PAGE_WINDOW
                ldy     #PAGE_WINDOW_END        ; through the window's last
                                                ; byte
                lbsr    diag_rom_span
                bcs     diag_rom_one_leave
                ldx     #PAGE_WINDOW+PAGE_SIZE-COMP_BYTE_BACK
                lda     ,x

diag_rom_one_judge
                pshs    a,b                     ; 0,s the stored byte,
                                                ; 1,s the sum
                lbsr    diag_rom_name           ; LINE 1 AFTER THE SUM, not
                                                ; before it. Painted first,
                                                ; the new image's name stood
                                                ; over the PREVIOUS image's
                                                ; checksum for as long as the
                                                ; sum took - 32768 byte reads
                                                ; for A2U12 - and a service
                                                ; screen that names one device
                                                ; beside another's number is
                                                ; worse than one that is slow.
                                                ; It clobbers A, B, X and Y,
                                                ; which is why the two values
                                                ; are on the stack across it
                lbsr    diag_rom_expected       ; A = the checksum this image
                                                ; must give
                adda    ,s                      ; the byte the image would have
                suba    1,s                     ; to carry for it to give that:
                                                ; expected + stored - sum. The
                                                ; stock's own arithmetic at
                                                ; $45DB-$45E9, 4,s + $3F86[i] -
                                                ; $2480[i]
                tfr     a,b
                lda     #DIAG_ROM_COL_SBH
                lbsr    diag_rom_put_hex2
                puls    a,b                     ; A stored, B the sum again

                pshs    b                       ; the sum, for the verdict
                tfr     a,b                     ; and the stored byte itself
                lda     #DIAG_ROM_COL_SUM
                lbsr    diag_rom_put_hex2
                puls    b
                lbsr    diag_rom_expected       ; A = zero for A2U12, the
                pshs    a                       ; page's own number for a page
                cmpb    ,s                      ; and THAT is the pass, not a
                puls    a                       ; sum of zero. PULS without CC
                                                ; in the list leaves the flags
                beq     diag_rom_one_pass
                ldx     #diag_rom_fails
                bra     diag_rom_one_count
diag_rom_one_pass
                ldx     #diag_rom_passes
diag_rom_one_count
                lda     >diag_rom_index
                ldb     a,x
                cmpb    #$FF                    ; SATURATE, do not wrap: see
                beq     diag_rom_one_show       ; the header
                incb
                stb     a,x
diag_rom_one_show
                lbsr    diag_rom_counts
                andcc   #~CC_CARRY              ; nobody asked to leave
                rts
diag_rom_one_leave
                orcc    #CC_CARRY
                rts

diag_rom_one_unmapped
                lbsr    diag_rom_name           ; the name, as above - here it
                                                ; is the only thing on line 1
                                                ; that can be trusted
                ; The page latch did not read back that page's own digit, so
                ; whatever is in the window is not the image asked for.
                ; Summing it would produce a number, and a number in this
                ; field is read as that image's checksum - so both fields say
                ; the byte could not be read instead, and the pass counts as a
                ; failure, because a device that cannot be mapped has failed.
                lda     #DIAG_ROM_COL_SUM
                lbsr    diag_rom_put_unknown
                lda     #DIAG_ROM_COL_SBH
                lbsr    diag_rom_put_unknown
                ldx     #diag_rom_fails
                lbra    diag_rom_one_count

; ---------------------------------------------------------------------------
; diag_rom_counts - the pass and fail counts for the selected image
;
;   uses:  A, B, X
; ---------------------------------------------------------------------------
diag_rom_counts
                lda     >diag_rom_index
                ldx     #diag_rom_passes
                ldb     a,x
                lbsr    diag_rom_dec3
                lda     #DIAG_ROM_COL_PASS
                ldx     #text_buffer
                ldb     #$03
                lbsr    lcd_write

                lda     >diag_rom_index
                ldx     #diag_rom_fails
                ldb     a,x
                lbsr    diag_rom_dec3
                lda     #DIAG_ROM_COL_FAIL
                ldx     #text_buffer
                ldb     #$03
                lbra    lcd_write

; ---------------------------------------------------------------------------
; diag_rom_name - line 1: the image's name and where its byte is
;
;   uses:  A, B, X, Y
;
; The columns are the stock's own, so an engineer who knows this screen finds
; the same fields in the same places: the name in the first sixteen columns
; with the page digit at column 13, the CPU address at 18 and the burn-set
; offset at 25 - five digits wide, because on a machine with more than four
; pages the offset does not fit in four.
; ---------------------------------------------------------------------------
diag_rom_name
                lda     >diag_rom_index
                bne     diag_rom_name_page

                lda     #LCD_LINE1              ; 'Main ROM'
                ldx     #diag_rom_l1_main
                ldb     #DIAG_ROM_NAME_LEN
                lbsr    lcd_write
                ldd     #DIAG_ROM_COMP12        ; the CPU address of its byte
                std     >diag_rom_addr_w
                ldd     #DIAG_ROM_COMP12-$8000  ; and the offset of that byte
                std     >diag_rom_offs_w        ; into the burn set: A2U12
                clra                            ; starts at $8000, so the
                sta     >diag_rom_offs_t        ; offset is the address less
                bra     diag_rom_name_paint     ; $8000 and never needs a
                                                ; fifth digit

diag_rom_name_page
                lda     #LCD_LINE1              ; 'Opt ROM page N'
                ldx     #diag_rom_l1_page
                ldb     #DIAG_ROM_NAME_LEN
                lbsr    lcd_write

                lda     >diag_rom_index
                deca                            ; the page number, 0 to 3
                pshs    a
                adda    #'0'
                sta     >text_buffer
                lda     #DIAG_ROM_COL_PAGE
                ldx     #text_buffer
                ldb     #$01
                lbsr    lcd_write

                ldd     #PAGE_WINDOW+PAGE_SIZE-COMP_BYTE_BACK
                                                ; the CPU address is the same
                std     >diag_rom_addr_w        ; for every page: the window
                                                ; is always at $4000

                lda     ,s                      ; the offset is that page's
                anda    #$03                    ; own 16K block plus $3FEF.
                asla                            ; One page is $4000, so the
                asla                            ; low two bits of the page
                asla                            ; number shift up 14 places -
                asla                            ; six in A, eight more because
                asla                            ; A is the high byte - and the
                asla                            ; bits above them become the
                clrb                            ; fifth digit. Written this way
                addd    #PAGE_SIZE-COMP_BYTE_BACK
                                                ; so a build with more than
                std     >diag_rom_offs_w        ; four pages still reads right
                puls    a
                lsra                            ; the fifth digit: page >> 2
                lsra
                sta     >diag_rom_offs_t

diag_rom_name_paint
                ldd     >diag_rom_addr_w
                ldx     #text_buffer
                lbsr    diag_rom_hex4
                lda     #DIAG_ROM_COL_ADDR
                ldx     #text_buffer
                ldb     #$04
                lbsr    lcd_write

                ldb     >diag_rom_offs_t        ; THE FIFTH DIGIT IS BLANK WHEN
                bne     diag_rom_offs_high      ; IT IS ZERO, which is every
                lda     #' '                    ; image of a four-page build:
                bra     diag_rom_offs_put       ; the stock shows '( 4001H)'
diag_rom_offs_high                              ; and this showed '(04001H)'.
                lbsr    nibble_to_hex           ; Driven side by side 2026-09-11
diag_rom_offs_put
                sta     >text_buffer
                lda     #DIAG_ROM_COL_OFFS-1
                ldx     #text_buffer
                ldb     #$01
                lbsr    lcd_write

                ldd     >diag_rom_offs_w
                ldx     #text_buffer
                lbsr    diag_rom_hex4
                lda     #DIAG_ROM_COL_OFFS
                ldx     #text_buffer
                ldb     #$04
                lbra    lcd_write

; ---------------------------------------------------------------------------
; diag_rom_put_hex2 - two hex digits at a column of line 2
;
;   entry: A = the DDRAM address, B = the byte
;   uses:  A, B, X
; ---------------------------------------------------------------------------
diag_rom_put_hex2
                pshs    a
                ldx     #text_buffer
                lbsr    byte_to_hex
                puls    a
                ldx     #text_buffer
                ldb     #$02
                lbra    lcd_write

; ---------------------------------------------------------------------------
; diag_rom_put_unknown - two question marks where a byte cannot be read
;
;   entry: A = the DDRAM address
;   uses:  A, B, X
; ---------------------------------------------------------------------------
diag_rom_put_unknown
                ldx     #diag_rom_unknown
                ldb     #$02
                lbra    lcd_write

; ---------------------------------------------------------------------------
; diag_rom_hex4 - four hex digits
;
;   entry: D = the value, X = where the four characters go
;   uses:  A, B, X
; ---------------------------------------------------------------------------
diag_rom_hex4
                pshs    b                       ; the low byte, while the
                tfr     a,b                     ; high one is written
                lbsr    byte_to_hex
                leax    2,x
                puls    b
                lbsr    byte_to_hex
                rts

; ---------------------------------------------------------------------------
; diag_rom_dec3 - a byte as three decimal characters, leading zeros blanked
;
;   entry: B = 0 to 255
;   exit:  text_buffer holds the three characters
;   uses:  A, B, X
;
; Blanked rather than zero-filled, which is what the stock does: it formats
; with format_three_digits ($C9D1) and then calls blank_leading_zeros ($CCFF)
; with a count of 2, leaving the last digit alone so a count of zero reads as
; '0' rather than as an empty field.
; ---------------------------------------------------------------------------
diag_rom_dec3
                ldx     #text_buffer
                lda     #'0'-1                  ; hundreds
diag_rom_dec3_h
                inca
                subb    #100
                bcc     diag_rom_dec3_h
                addb    #100                    ; one subtraction too many
                sta     ,x+
                lda     #'0'-1                  ; tens
diag_rom_dec3_t
                inca
                subb    #10
                bcc     diag_rom_dec3_t
                addb    #10
                sta     ,x+
                addb    #'0'                    ; and what is left is units
                stb     ,x

                ldx     #text_buffer            ; the two leading zeros go,
                lda     ,x                      ; the last digit stays
                cmpa    #'0'
                bne     diag_rom_dec3_done
                lda     #' '
                sta     ,x
                lda     1,x
                cmpa    #'0'
                bne     diag_rom_dec3_done
                lda     #' '
                sta     1,x
diag_rom_dec3_done
                rts

; ---------------------------------------------------------------------------
; diag_ram_run - walk a pattern through the scratch RAM
;
;   exit:  Z set if every byte read back what was written
;   uses:  A, B, X
;
; ONLY THE SCRATCH REGION. The stock firmware's RAM test is destructive over
; the whole of $2000-$3FFF, which includes the serial number, the installed
; options. Running it costs the instrument its
; identity, and it sits behind the same access code as everything else with
; nothing to say so.
;
; This walks the SCRATCH span only - SCRATCH_BASE to SCRATCH_END, which is
; $3A80-$3E3F as the symbols currently stand - so a RAM fault is still found
; and nothing that cannot be regenerated is touched. The menu still marks it
; destructive, because it destroys whatever the rewrite had in flight, and
; the routine now rebuilds scratch on both paths before returning.
;
; This paragraph said "$2600-$2FFF", which was true of an earlier layout and
; names bytes inside $268F-$3A7A, the twelve save/recall setups. The bounds
; below are symbols and were always right; only the sentence describing them
; had drifted, which is the more dangerous half - a reader checking whether
; this routine is safe reads the sentence.
; ---------------------------------------------------------------------------
DIAG_RAM_START  equ     SCRATCH_BASE
; The RAM test's span. It ran from SCRATCH_END up to $3000 and scratch moved
; to $3A80, so the start was ABOVE the end: the loop stored one byte, verified
; that byte, and reported PASS. Poisoning $3A80-$3D7F and running it changed
; exactly one byte.
;
; It walks the SCRATCH span and nothing else. $268F-$3A7A is the twelve
; save/recall setups and $3FEE-$3FFF is the serial and the options; a
; destructive walk of either is the fault the owner's standing rule exists to
; prevent, so the bounds are named against those symbols rather than written
; as literals that can drift out from under them again.
DIAG_RAM_END    equ     SCRATCH_END

; SIX BYTES ACROSS THE WALK, on the CPU stack. scratch_reset writes zero over
; SCRATCH_BASE..live_setting-1, and several cells in that span mean something
; other than "not set" when they read zero. The boot path knows this and sets
; three of them after its own resets (boot.s:186-231, with the reason at
; each); it runs once, at power-on, before anything is producing. THIS screen
; runs the same clear on a working instrument, over and over, and put none of
; them back:
;
;   latch_shadow  four bytes, one per channel, and the output relay is bit 2,
;                 ACTIVE LOW. A zeroed shadow is not merely stale: the next
;                 read-modify-write - chan_state_sync, filter_apply,
;                 channel_latch_rmw - takes the zero as the state the hardware
;                 is in and writes it back with its own bit added, which
;                 CLOSES the output relay on all four channels and un-floats
;                 them. The instrument starts driving whatever is connected to
;                 it, from a diagnostic screen, with nothing said.
;   current_page  zero is a VALID page number, so a cleared shadow claims page
;                 0 is mapped in a window that is in fact still pointing
;                 wherever it was. The next page_call for page 0 would skip
;                 the latch write and call into another page's bytes.
;   hop_index     the Hop Ram screen shows FIFTEEN MINUS this, so zero puts
;                 slot 15 on the glass; boot.s:205 has the driven evidence.
;
; THE VALUES THEY HELD, not a default. channel_latch_init would make shadow
; and hardware agree by writing both, and that is honest, but it would also
; open every output relay - a RAM test that silences the instrument it is
; running on. The bytes are read before the walk and put back after it, so
; nothing on the front panel moves. They are carried on the CPU stack, which
; is at $21xx and outside the span being walked.
;
; The display and backlight shadows are re-initialised rather than saved,
; exactly as boot does and for the reasons it records: a zeroed lcd shadow
; makes the next control write DISPLAY OFF, and a zeroed backlight_s leaves
; the lamp on for ever.
diag_ram_test
                ldd     >latch_shadow           ; channels 0 and 1
                pshs    d
                ldd     >latch_shadow+2         ; 2 and 3
                pshs    d
                lda     >current_page
                ldb     >hop_index
                pshs    d

                ldx     #DIAG_RAM_START
diag_ram_write
                tfr     x,d                     ; a different value per cell,
                stb     ,x+                     ; so a stuck address line
                cmpx    #DIAG_RAM_END           ; shows up as well as a stuck
                blo     diag_ram_write          ; data line

                ldx     #DIAG_RAM_START
diag_ram_verify
                tfr     x,d
                cmpb    ,x+
                bne     diag_ram_bad
                cmpx    #DIAG_RAM_END
                blo     diag_ram_verify
                clra                            ; zero: every byte read back
                bra     diag_ram_restore        ; what was written
diag_ram_bad
                lda     #$01                    ; non-zero: one did not
diag_ram_restore
                pshs    a                       ; THE ANSWER ON THE STACK too:
                                                ; every cell that could hold
                                                ; it is inside the span the
                                                ; next instruction clears
                lbsr    scratch_reset           ; PUT SCRATCH BACK. Neither
                                                ; path did, so the Diagnostics
                                                ; RAM Test left every scratch
                                                ; byte holding its own low
                                                ; address - screen_handler
                                                ; $F2F3, tick_callback $6768
                                                ; - and
                                                ; the screen it had just
                                                ; installed was then called
                                                ; through those. Its twin
                                                ; selftest_ram calls
                                                ; scratch_reset for this exact
                                                ; reason; this one was written
                                                ; without it, on both paths.
                lbsr    lcd_control_init        ; display on, cursor off
                lbsr    backlight_wake          ; lamp on, three minutes
                lda     1,s                     ; and the six bytes, in the
                sta     >current_page           ; order they went down: the
                lda     2,s                     ; answer at 0,s, current_page
                sta     >hop_index              ; at 1, hop_index at 2, the
                ldd     3,s                     ; four latch bytes at 3 to 6
                std     >latch_shadow+2
                ldd     5,s
                std     >latch_shadow
                lda     ,s                      ; the answer, and LDA sets Z
                leas    7,s                     ; from it: zero means passed.
                rts                             ; LEAS does not touch CC

; ---------------------------------------------------------------------------
; diag_ram_run - show the result
;
;   uses:  A, B, X
; ---------------------------------------------------------------------------
; The whole navigation stack, carried on the CPU stack while the RAM test
; walks the one it lives in. Written out at each of its three uses as
; NAV_DEPTH_MAX*NAV_ENTRY rather than given a name here: asm6809.py resolves
; an `equ` in one pass and a2u12_all.inc includes this file BEFORE
; service_nav.s, where both of those are defined - while the same symbols in
; an instruction's operand resolve on a later pass. The same reason
; PAGE_WINDOW is spelled out in diag_rom_one above.
DIAG_LCD_FIRST  equ     $20             ; the first character code the walk
                                        ; shows. The stock seeds $1F and
                                        ; steps before it writes
DIAG_LCD_LAST   equ     $CF             ; and the last: it wraps when the
                                        ; count reaches $D0
DIAG_LCD_SOLID  equ     $FF             ; what a code above $7F is shown as
DIAG_LCD_STEP_MS equ    100             ; one cell per delay_ms($64)
DIAG_PROBE_HOLD equ     1000            ; how long the read-back's answer
                                        ; stays up before the walk covers it
DIAG_RAM_PASS_POS equ  LCD_LINE2+7     ; the stock's $47 and $5B, which are
DIAG_RAM_FAIL_POS equ  LCD_LINE2+27    ; line 2 columns 7 and 27
DIAG_RAM_COUNT_W equ    5               ; five digits, four of them blanked
                                        ; while they are zero - the stock's
                                        ; u16_to_5_ascii_digits ($C912)
                                        ; followed by blank_leading_zeros
                                        ; ($CCFF) with a count of 4

diag_ram_run
                lbsr    screen_take_dismiss     ; as the ROM check does, and
                                                ; for the same reason: the
                                                ; loop below reads the keypad
                                                ; itself, but a screen that
                                                ; paints without taking the
                                                ; keys leaves the last one's
                                                ; handler live over it

                lda     #LCD_LINE1
                ldx     #diag_ram_title
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write
                lda     #LCD_LINE2
                ldx     #diag_ram_line2
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write

                ; EVERYTHING THIS SCREEN NEEDS GOES ON THE STACK, because the
                ; test below destroys the rest of it. diag_ram_test writes a
                ; pattern over SCRATCH_BASE to SCRATCH_END and then calls
                ; scratch_reset, which CLEARS that whole span - and the span
                ; holds menu_table (+$20), menu_count, menu_index, menu_top,
                ; nav_top (+$60), screen_handler (+$272) and menu_title
                ; (+$2E4). So after one pass there is no menu to go back to
                ; and no handler installed, and the version of this screen
                ; that ran the test once and returned left the foreground to
                ; call through a screen_handler of $0000 on the next key.
                ; Two counters in scratch went the same way - they were
                ; cleared every pass and the display sat at 1.
                ;
                ; AND THE NAVIGATION HISTORY WITH IT. nav_top and the four
                ; nav_stack entries are in the span too, so before this the
                ; RAM test cost the operator every level above the menu they
                ; ran it from - Back went to the Main Selection instead of the
                ; Service menu. The stock's ram_test ($DC82) complements each
                ; byte and puts it straight back, so it never loses its own
                ; state; this one writes a pattern over the whole span, which
                ; catches a stuck ADDRESS line that the stock's cannot, and
                ; pays for it by having to carry the state out of reach.
                ;
                ; The stack is the one place the test cannot reach. Five bytes
                ; of menu context, the navigation stack, and two counters, all
                ; restored on the way out.
                ; PUSHED BYTE BY BYTE, NOT LEAS'd. `leas -NAV_DEPTH_MAX*
                ; NAV_ENTRY,s` made the two assemblers produce different
                ; bytes: the offset is -20, which fits the 5-bit form, and
                ; a2u12_all.inc includes this file before service_nav.s
                ; defines those two symbols - so one assembler sized the
                ; instruction knowing the value and the other did not. An
                ; immediate and a 16-bit address are one size whatever the
                ; symbol turns out to be, so the copy walks backwards from the
                ; end of the block and pushes, which leaves it on the stack
                ; the right way round.
                ldx     #nav_stack+NAV_DEPTH_MAX*NAV_ENTRY
                ldb     #NAV_DEPTH_MAX*NAV_ENTRY
diag_ram_push
                lda     ,-x
                pshs    a
                decb
                bne     diag_ram_push
                lda     >nav_top
                pshs    a

                ldx     >menu_table
                pshs    x                       ; 9,s
                ldx     >menu_title
                pshs    x                       ; 7,s
                lda     >menu_count
                pshs    a                       ; 6,s
                lda     >menu_index
                pshs    a                       ; 5,s
                lda     >menu_top
                pshs    a                       ; 4,s
                ldx     #$0000
                pshs    x                       ; 2,s the fail count
                pshs    x                       ; 0,s the pass count

diag_ram_loop
                ldx     ,s                      ; the counts BEFORE the test,
                ldy     2,s                     ; which is the order the
                lbsr    diag_ram_counts         ; stock's loop uses at $4E23:
                                                ; the display shows what has
                                                ; been proved so far while the
                                                ; next pass runs
                lbsr    diag_exit_poll
                bcs     diag_ram_leave
                lbsr    diag_ram_test           ; Z set if every byte read
                bne     diag_ram_failed         ; back what was written
                ldx     ,s
                leax    1,x
                stx     ,s
                bra     diag_ram_loop
diag_ram_failed
                ldx     2,s
                leax    1,x
                stx     2,s
                bra     diag_ram_loop

diag_ram_leave
                leas    4,s                     ; the two counts
                puls    a
                sta     >menu_top
                puls    a
                sta     >menu_index
                puls    a
                sta     >menu_count
                puls    x
                stx     >menu_title
                puls    x
                stx     >menu_table
                puls    a
                sta     >nav_top
                ldy     #nav_stack              ; and the navigation stack
                ldb     #NAV_DEPTH_MAX*NAV_ENTRY
diag_ram_pull
                puls    a
                sta     ,y+
                decb
                bne     diag_ram_pull
                lbra    menu_reopen_current

; ---------------------------------------------------------------------------
; diag_ram_counts - the two counts, five digits each
;
;   entry: X = the pass count, Y = the fail count
;   uses:  A, B, X, Y
;
; IN REGISTERS, not in scratch: the caller keeps them on the stack because
; the RAM test clears every scratch byte. See diag_ram_run.
; ---------------------------------------------------------------------------
diag_ram_counts
                pshs    y                       ; the fail count, while the
                lbsr    diag_ram_count_text     ; pass count is drawn
                lda     #DIAG_RAM_PASS_POS
                ldx     #text_buffer+3          ; the last five of the eight
                ldb     #DIAG_RAM_COUNT_W
                lbsr    lcd_write

                puls    x                       ; the fail count
                lbsr    diag_ram_count_text
                lda     #DIAG_RAM_FAIL_POS
                ldx     #text_buffer+3
                ldb     #DIAG_RAM_COUNT_W
                lbra    lcd_write

; ---------------------------------------------------------------------------
; diag_ram_count_text - one 16-bit count as five digits, leading zeros blanked
;
;   entry: X = the count
;   exit:  text_buffer+3 holds the five characters
;   uses:  A, B, X
;
; uint24_to_text is the only formatter here and it produces eight digits, so
; the count is widened into diag_kbd_wide - which the Keyboard Check uses for
; exactly the same reason - and the last five taken. Four of the five are
; blanked while they are zero and the fifth is kept, so a count of nothing
; reads '0' rather than an empty field: the stock's blank_leading_zeros
; ($CCFF) with a count of 4.
; ---------------------------------------------------------------------------
diag_ram_count_text
                clr     >diag_kbd_wide
                stx     >diag_kbd_wide+1
                ldx     #diag_kbd_wide
                lbsr    uint24_to_text          ; eight digits in text_buffer
                ldx     #text_buffer+3
                ldb     #DIAG_RAM_COUNT_W-1     ; the last digit always stays
diag_ram_count_blank
                lda     ,x
                cmpa    #'0'
                bne     diag_ram_count_done
                lda     #' '
                sta     ,x+
                decb
                bne     diag_ram_count_blank
diag_ram_count_done
                rts

; ---------------------------------------------------------------------------
; diag_keyboard_run - report each key as it is pressed
;
;   uses:  A, B, X
;
; ONE PASS, AND NOBODY LOOPS. This said "the caller loops", and no caller
; does: diag_keyboard_run is reached once, from the menu's single `jsr ,x`,
; and its first act installs diag_keyboard_key as the screen's handler - so
; from then on it is the KEY HANDLER the foreground calls, once per key, not
; this routine. The screen follows the operator's finger because every press
; reaches the handler, which is a different mechanism from the one described
; and a working one.
; ---------------------------------------------------------------------------
diag_keyboard_run
                ldx     #$0000                  ; a fresh total each time the
                stx     >diag_kbd_total         ; screen is opened, as the
                                                ; stock's $4B1E does with its
                                                ; own CLRA/CLRB/STD >$3FA3
                clr     >diag_kbd_last          ; and no previous key, which
                                                ; is its CLRA/CLRB/STD >$3FA1
                                                ; - without it an f4 left over
                                                ; from the last time the
                                                ; screen was open would make
                                                ; the first f4 pressed this
                                                ; time the second of a pair

                ldx     #diag_keyboard_key      ; every key prints its own
                lbsr    screen_install          ; name, so this screen needs
                lda     #$01                    ; the LOCAL key too - the
                sta     >screen_keeps_local     ; stock's arm [1] names it and
                                                ; adds $20 to the total like
                                                ; any other key

                lda     #LCD_LINE1
                ldx     #diag_kbd_title
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write

                ; AND NOTHING IS SCANNED HERE. This read the keypad as it
                ; opened and reported whatever was down, which is the ENTER
                ; still under the operator's finger from the menu - so the
                ; screen opened claiming a key had been pressed that had not
                ; been pressed on it. keyboard_check_screen_init ($4B1E)
                ; paints its two lines, clears its two words and installs the
                ; handler; the first thing it reports is the first key pressed
                ; after that.
                lda     #LCD_LINE2
                ldx     #diag_kbd_none
                ldb     #SVC_LABEL_LEN
                lbra    lcd_write

; ---------------------------------------------------------------------------
; diag_display_run - light every cell so a dead segment shows
;
;   uses:  A, B, X
; ---------------------------------------------------------------------------
diag_display_run
                ; TAKE THE KEYS FIRST. This installed no handler at all, so
                ; every key pressed while the display was full of test cells
                ; went to whatever screen had been up before - the operator
                ; was looking at one screen and typing at another. Any key
                ; leaves, which is right for a screen that fills the display
                ; and cannot show anything else.
                lbsr    screen_take_dismiss

                ; BLANK BOTH LINES FIRST, so a cell that stays lit is a stuck
                ; cell rather than the last screen showing through.
                lda     #LCD_LINE1
                lbsr    lcd_blank_line
                lda     #LCD_LINE2
                lbsr    lcd_blank_line

                lda     #LCD_LINE1              ; then every pixel of every
                ldb     #LCD_COLUMNS            ; cell, which is what a person
                lbsr    diag_fill_line          ; looks at
                lda     #LCD_LINE2
                ldb     #LCD_COLUMNS
                lbsr    diag_fill_line

                ; AND READ ONE CELL BACK. Filling the display proves the bus
                ; works one way; reading a cell back proves the controller
                ; took what was sent, which is the half that catches a stuck
                ; data line - and a stuck line makes every cell wrong in the
                ; same way, which is exactly what a person does not notice.
                ;
                ; lcd_blank_line, lcd_get and lcd_address all existed and
                ; none was called, on the screen whose entire subject is
                ; whether the display works.
                lda     #LCD_LINE1
                lbsr    lcd_cursor
                lda     #DIAG_PROBE_CHAR        ; lcd_put TAKES A. This was
                lbsr    lcd_put                 ; `ldb`, so the character sent
                                                ; was whatever A happened to
                                                ; hold - LCD_LINE1, left by
                                                ; the lcd_cursor call two
                                                ; instructions above - and the
                                                ; comparison below then failed
                                                ; on every run. The Display
                                                ; Check reported a fault on
                                                ; working hardware, every
                                                ; time.
                lda     #LCD_LINE1
                lbsr    lcd_cursor
                lbsr    lcd_get                 ; A = what the cell holds
                cmpa    #DIAG_PROBE_CHAR
                beq     diag_display_ok
                ldb     #ERR_DISPLAY_FAULT      ; it did not take it. NOT
                                                ; ERR_RAM_FAULT, which was
                                                ; here and sends an engineer
                                                ; to the wrong board: nothing
                                                ; in this probe touches RAM.
                lbsr    error_raise
diag_display_ok
                ; AND SHOW WHERE THE COUNTER ENDED UP. This stored it "for the
                ; screen to show" and no screen showed it - grepping every
                ; source for diag_probe_address returned the declaration and
                ; this one store, with no load anywhere. A value computed,
                ; written to a variable and never read is a leftover; the
                ; number is worth having, so it is painted rather than the
                ; variable removed.
                lbsr    lcd_address             ; A = the DDRAM address
                sta     >diag_probe_address
                tfr     a,b
                ldx     #text_buffer
                lbsr    byte_to_hex
                lda     #DIAG_PROBE_POS
                ldx     #text_buffer
                ldb     #2
                lbsr    lcd_write
                ldd     #DIAG_PROBE_HOLD        ; long enough to be read,
                lbsr    delay_ms                ; because the walk below
                                                ; paints over it

                ; --- and then the stock's screen ---------------------------
                ;
                ; lcd_display_check ($4EF7) walks a rolling character pattern
                ; over every one of the eighty cells until f4: it steps the
                ; character code $20 to $CF ($4F2A: the count reaching $D0
                ; wraps to $20), steps the DDRAM position, jumps the gap the
                ; controller leaves between $27 and $40 ($4F52), and writes
                ; one cell per delay_ms($64).
                ;
                ; Every code above $7F is written as $FF, which is its test at
                ; $4F3F: the font is undefined up there and a solid cell is a
                ; shape a person can judge.
                ;
                ; It alternates, on the flag at 3,s. One sweep runs $00 to $67
                ; and paints over line 1 as well; the next repaints the header
                ; ($4F6B) and runs $40 to $67 only - so the instruction for
                ; leaving comes back between sweeps instead of the operator
                ; having to remember it.
                ;
                ; The fill and the read-back above stay in front of it. They
                ; prove every pixel of every cell and that the controller took
                ; what was sent, which a rolling character pattern cannot
                ; show; this is the other half, every CHARACTER in every cell,
                ; which is what finds a fault in the font.
                ;
                ; THE THREE COUNTERS ARE ON THE STACK. Every scratch byte is
                ; fair game for the RAM test two entries up the same menu, and
                ; nothing here needs to outlive the screen.
                ldb     #DIAG_LCD_FIRST-1       ; 2,s the character: the stock
                pshs    b                       ; seeds $1F and steps before
                                                ; it writes
                ldb     #LCD_LINE2+LCD_COLUMNS-1
                pshs    b                       ; 1,s the position, one below
                                                ; the end of line 2 so that
                                                ; the first step wraps
                ldb     #$01
                pshs    b                       ; 0,s which sweep this is

diag_display_step
                lbsr    diag_exit_poll          ; f4 or LOCAL
                bcs     diag_display_leave

                ldb     2,s                     ; the next character code,
                incb                            ; wrapping at the end of the
                cmpb    #DIAG_LCD_LAST+1        ; range the stock walks
                blo     diag_display_char_set
                ldb     #DIAG_LCD_FIRST
diag_display_char_set
                stb     2,s

                ldb     1,s                     ; the next cell, jumping the
                incb                            ; gap between the two lines
                cmpb    #LCD_COLUMNS
                bne     diag_display_pos_set
                ldb     #LCD_LINE2
diag_display_pos_set
                stb     1,s
                cmpb    #LCD_LINE2+LCD_COLUMNS
                bne     diag_display_put

                ldb     ,s                      ; a sweep has finished
                beq     diag_display_whole
                lbsr    diag_display_headers    ; put the header back and walk
                ldb     #LCD_LINE2              ; line 2 only
                stb     1,s
                clr     ,s
                bra     diag_display_put
diag_display_whole
                ldb     #$01                    ; and the sweep after that
                stb     ,s                      ; covers both lines, header
                clr     1,s                     ; and all

diag_display_put
                ldb     2,s
                cmpb    #$7F                    ; above the font: a solid cell
                bls     diag_display_put_cell
                ldb     #DIAG_LCD_SOLID
diag_display_put_cell
                pshs    b                       ; the character, while the
                lda     2,s                     ; cursor is placed - the frame
                lbsr    lcd_cursor              ; has moved down one byte
                puls    a                       ; and lcd_put takes A
                lbsr    lcd_put
                ldd     #DIAG_LCD_STEP_MS
                lbsr    delay_ms
                bra     diag_display_step

diag_display_leave
                leas    3,s
                lbra    menu_reopen_current

; ---------------------------------------------------------------------------
; diag_display_headers - the line the walk paints over and puts back
;
;   uses:  A, B, X
;
; One forty-character line where the stock writes two overlapping pieces -
; d41a0 'Diagnostics -' across the whole line at position 0 and d42d4 'LCD
; Display Check  f4 Exit' over its tail at $0E. The forty characters that
; reach the display are the same.
; ---------------------------------------------------------------------------
diag_display_headers
                lda     #LCD_LINE1
                ldx     #diag_lcd_title
                ldb     #SVC_LABEL_LEN
                lbra    lcd_write

; ---------------------------------------------------------------------------
; diag_fill_line - write one character across a whole display line
;
;   entry: A = the DDRAM address of the line, B = HOW MANY cells to fill
;
; B is the COUNT, not the character. The character is $FF, hardcoded in the
; body because every pixel of every cell is what a display check wants to
; show. Both callers pass LCD_COLUMNS and have always agreed with the code;
; only this line disagreed - and it is the same A-versus-B confusion that put
; the probe character in the wrong register twenty lines above.
;   uses:  A, B, X
;
; The Display Check screen's worker. It fills a line with one character so
; every cell can be seen to light: a dead segment shows as a gap in an
; otherwise solid row, and a dead cell shows as a hole. Doing it a character
; at a time rather than from a forty-byte constant costs nine instructions
; and saves eighty bytes of ROM per pattern.
; ---------------------------------------------------------------------------
diag_fill_line
                lbsr    lcd_cursor
diag_fill_next
                pshs    b
                lda     #$FF                    ; every pixel in the cell
                lbsr    lcd_put
                puls    b
                decb
                bne     diag_fill_next
                rts

; ---------------------------------------------------------------------------
; diag_keyboard_key - the Keyboard Check screen's keys
;
;   entry: B = the key code
;   uses:  A, B, X, Y
;
; EVERY key prints its own name, which is the whole point: an engineer works
; along the panel pressing each key and reads back what the firmware saw. A
; key that prints nothing is a key whose contacts have failed, and a key that
; prints its neighbour's name is a matrix fault.
;
; LEAVING. Because every key is consumed by the test, one key has to be the
; way out and it cannot be a key the test needs. It is the LOCAL key, pressed
; TWICE in succession: a single press prints "local" like any other key, so
; the key is still testable, and two in a row leaves. Nothing else on the
; panel has to be sacrificed.
;
; That is worth the extra state. The alternative - reserving a key that never
; prints - means one key on the panel can never be checked, on the screen
; whose only purpose is checking keys.
; ---------------------------------------------------------------------------
diag_keyboard_key
                ; TWO f4s IN A ROW IS THE WAY OUT, which is what the screen
                ; says: keyboard_check_key_handler ($4803) compares the
                ; PREVIOUS key $3FA1 with $0020 and then the current key_code
                ; $24DC with $0020, and only both together leave. This screen
                ; had used LOCAL twice instead, against a line of text that
                ; the stock puts on the display naming f4.
                ;
                ; LOCAL IS A KEY UNDER TEST HERE AND NOTHING MORE. This screen
                ; sets screen_keeps_local so LOCAL reaches the handler and is
                ; named and counted like any other key - the stock's arm [1]
                ; adds $20 to the total for it. Two f4s are the only way out,
                ; which is what keyboard_check_key_handler ($4803) does: it
                ; leaves only when the previous key $3FA1 AND key_code $24DC
                ; are both $0020. LOCAL twice used to leave here as well.
                cmpb    #KEY_F4
                bne     diag_keyboard_other
                cmpb    >diag_kbd_last          ; the same one twice running
                beq     diag_keyboard_leave
diag_keyboard_other
                stb     >diag_kbd_last

                ; THE SENTENCE FIRST, then the name over its first eight
                ; columns - the order the stock's tail uses at $4AAD, and the
                ; reason it repaints all forty characters every time: the name
                ; of the last key is sitting in those columns.
                pshs    b
                lda     #LCD_LINE2
                ldx     #diag_kbd_line2
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write
                puls    b

                pshs    b
                lbsr    key_name                ; X = eight characters
                lda     #DIAG_KBD_NAME_POS
                ldb     #KEY_NAME_LEN
                lbsr    lcd_write
                puls    b

                ; THE KEY CODE IS NOT SHOWN, and was. The stock's screen puts
                ; the name and the total on the display and nothing else, and
                ; its line 2 is forty columns of sentence with no room for a
                ; third field - showing one meant shortening the sentence the
                ; instrument's own manual quotes. The name identifies the key
                ; and the total is what proves the keyboard: press every key
                ; once and the total is a number that can be checked.

                ; AND THE RUNNING TOTAL, the same sum the stock keeps. Its
                ; shared tail at $4AAD does LDB 4,s / CLRA / ADDD >$3FA3 /
                ; STD >$3FA3 with the arm's own constant in B; this indexes
                ; the same constants by key code and adds them the same way.
                ; All 55 of those constants were read out of the arms of the
                ; table at $4A3F and are in diag_kbd_weight, index for index.
                ;
                ; A code past the table is added as zero rather than indexing
                ; off the end - key_decode cannot produce one today, and a
                ; bound here costs two instructions against a service screen
                ; reading a byte of whatever follows the table.
                cmpb    #KBD_WEIGHTS
                bhs     diag_keyboard_total_shown
                ldx     #diag_kbd_weight
                abx
                ldb     ,x                      ; this key's weight
                clra
                addd    >diag_kbd_total
                std     >diag_kbd_total

                ; RENDERED WITH THE 24-BIT FORMATTER, which is the only
                ; one here: the total is widened to three bytes and the last
                ; four of its eight digits are written. The stock renders four
                ; digits too, through u16_to_5_ascii_digits ($C912) at LCD
                ; position $24.
                clr     >diag_kbd_wide
                ldx     >diag_kbd_total
                stx     >diag_kbd_wide+1
                ldx     #diag_kbd_wide
                lbsr    uint24_to_text          ; eight digits in text_buffer
                lda     #DIAG_KBD_TOTAL_POS
                ldx     #text_buffer+4          ; the last four of the eight
                ldb     #4
                lbsr    lcd_write
diag_keyboard_total_shown
                rts
diag_keyboard_leave
                clr     >diag_kbd_last
                lbra    service_back_handler

; ---------------------------------------------------------------------------
; diag_relay - the relay exercise, on page 3
;
;   uses:  A, B, X, Y, U
;
; Page 3's fifth entry vector, relay_open (page3_screens.s). The screen is the
; architect's addition; docs/relay-exercise.md has the design.
; ---------------------------------------------------------------------------
diag_relay
                lda     #PAGE_MANUAL_COWCHIP    ; page 3
                lbra    page_enter_fifth

; ---------------------------------------------------------------------------
; relay_restore - the relay exercise, put back
;
;   uses:  A, X
;
; Reached through ABI slot 123 from the screen's stop key and its f4, and as
; the screen_leave vector - so it runs however the screen is left, from
; whatever page is mapped, which is why it lives here and not on page 3.
;
; A no-op unless a run is going. Otherwise, for every channel it cycled: the
; stored level back on the chip (ampl_reapply, from the channel record - the
; exercise wrote zero into the level register so the output relay would close
; on no signal), and THEN the latch byte recorded when the run started, every
; bit of it, so whatever the level path wrote to the latch is overwritten with
; exactly what was there.
; ---------------------------------------------------------------------------
relay_restore
                tst     >relay_running
                beq     relay_restore_done
                clr     >relay_running          ; first: no poll steps again
                pshs    b,y,u
                bsr     relay_count
                pshs    a                       ; 0,s the channels it cycled
                clrb
relay_restore_level
                cmpb    ,s
                bhs     relay_restore_latches
                pshs    b
                lda     #CHAN_RECORD
                mul                             ; D = channel * CHAN_RECORD
                addd    #channel_records
                tfr     d,x
                ldb     ,s
                lbsr    ampl_reapply            ; X = the record, B = channel
                puls    b
                incb
                bra     relay_restore_level
relay_restore_latches
                clrb
relay_restore_latch
                cmpb    ,s
                bhs     relay_restore_out
                ldx     #relay_saved
                lda     b,x                     ; the byte as it was
                inc     >dds_lock               ; THE STORE AND THE CALL ARE
                sta     >latch_bits             ; ONE OPERATION, as everywhere
                lda     #$FF                    ; every bit, exactly
                lbsr    channel_latch_rmw       ; A and B come back unchanged
                dec     >dds_lock
                incb
                bra     relay_restore_latch
relay_restore_out
                leas    1,s
                puls    b,y,u
relay_restore_done
                rts

; ---------------------------------------------------------------------------
; relay_count - how many channel latches the exercise cycles
;
;   exit:  A = the fitted count, and one when the probe found none: the
;          architect's ruling of 2026-09-18 - channel 1
;          always exists
;   uses:  A
; ---------------------------------------------------------------------------
relay_count
                lda     >installed_channels
                bne     relay_count_done
                inca
relay_count_done
                rts

