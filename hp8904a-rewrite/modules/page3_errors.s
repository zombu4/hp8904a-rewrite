; ===========================================================================
; page3_errors.s - the sixty-three error messages, and the line the flash
; paints from them
;
; WHERE THEY COME FROM. error_message_table in the stock's A2U13 page 3, at
; $7349, with the strings behind it in the same page. Every entry is four
; bytes - the code, the string's length, and its address - and the table and
; the strings below were EXTRACTED from firmware/a2u13_page3.bin rather than
; retyped, so the words, the spacing and the two spellings of "Commmand" are
; the instrument's own.
;
; HOW THE STOCK SEARCHES IT, hand-decoded from the bytes at $7AC3 which the
; disassembler emits as data:
;
;   $7AC3  LDA >$23DE        the error number
;   $7AC6  LDX #$7349        the table
;   $7AC9  LDB -1,X          $7348 = $3E: SIXTY-TWO, not sixty-three
;   $7ACB  CMPA ,X / BEQ     compare the code
;   $7ACF  LEAX 4,X / DECB / BNE $7ACB
;   $7AD4  LDA 1,X           the length
;   $7AD6  STA >$23DF
;   $7AD9  LDX 2,X           the string
;   $7ADB  LDY #$23E0 / LDB ,X+ / STB ,Y+ / DECA / BNE
;   $7AE6  RTS
;
; THE COUNT IS THE DESIGN. Sixty-two comparisons walk entries 0 to 61; when
; the last of them fails, LEAX has already moved X onto entry 62 and DECB has
; reached zero, so the fall-through reads entry 62 - code $FF, "Message not
; found." - as the answer. A code the table does not carry lands there. That
; is why the last two entries both say $FF and why the first of them is the
; one a real code $FF finds.
;
; This firmware writes the line straight from the page rather than copying it
; to $23E0 first: the string is in the window while page 3 is mapped, A2U12
; is always mapped, and the raw line writer is one call through the jump
; table. The stock needs the copy because A2U12 paints after switching back.
; ===========================================================================

ERROR_TEXT_ENTRY  equ   4               ; code, length, and a two-byte address
ERROR_TEXT_SEARCH equ   71              ; the stock's count byte at $7348 is 62,
                                        ; and nine of this firmware's own sit
                                        ; between the last searched entry and
                                        ; the fallback, which stays last

; ---------------------------------------------------------------------------
; error_text_show - put the message for the last error on line 2
;
;   entry: nothing - last_error is where the number lives, as $23DE is on the
;          stock. This is reached by page_call, which needs B for the page.
;   uses:  A, B, X, Y
;
; Reached through this page's third entry vector at $4007. The line is painted
; RAW - over the shadow, not into it - because the screen underneath has to
; survive the three seconds and come back whole.
; ---------------------------------------------------------------------------
error_text_show
                ldb     >last_error
                ldx     #error_text_table
                lda     #ERROR_TEXT_SEARCH
error_text_next
                cmpb    ,x
                beq     error_text_found
                leax    ERROR_TEXT_ENTRY,x
                deca
                bne     error_text_next         ; and when it runs out X is on
                                                ; the last entry, which is the
                                                ; fallback
error_text_found
                ldb     1,x                     ; the length
                ldx     2,x                     ; the characters
                lda     #LCD_LINE2
                lbsr    ABI_lcd_write_line_raw

                ; AND IT ANSWERS CARRY CLEAR, deliberately. page_call returns
                ; either "the page did not map and nothing was called" or the
                ; callee's own carry, and this routine had none - it ended in a
                ; tail call to lcd_write_line_raw and handed back whatever that
                ; happened to leave. Its caller could not then tell a failed
                ; page switch from a painted message, so it tested neither and
                ; a failed switch left the error NUMBER on line 1 beside
                ; whatever words were already on line 2.
                andcc   #~CC_CARRY
                rts

; ---------------------------------------------------------------------------
; error_text_table - sixty-three entries, the stock's own bytes
; ---------------------------------------------------------------------------
error_text_table
                fcb     $00,8
                fdb     err_t7445
                fcb     $01,21
                fdb     err_t744d
                fcb     $02,17
                fdb     err_t7462
                fcb     $03,21
                fdb     err_t7473
                fcb     $04,22
                fdb     err_t7488
                fcb     $0A,17
                fdb     err_t749e
                fcb     $0B,24
                fdb     err_t74af
                fcb     $0C,25
                fdb     err_t74c7
                fcb     $0D,28
                fdb     err_t74e0
                fcb     $0E,34
                fdb     err_t74fc
                fcb     $0F,21
                fdb     err_t751e
                fcb     $10,38
                fdb     err_t7533
                fcb     $11,17
                fdb     err_t7559
                fcb     $12,20
                fdb     err_t756a
                fcb     $13,16
                fdb     err_t757e
                fcb     $14,26
                fdb     err_t758e
                fcb     $16,30
                fdb     err_t7a79
                fcb     $18,36
                fdb     err_t75a8
                fcb     $1F,34
                fdb     err_t75cc
                fcb     $29,21
                fdb     err_t75ee
                fcb     $2A,21
                fdb     err_t75ee
                fcb     $2B,32
                fdb     err_t7603
                fcb     $2C,28
                fdb     err_t7623
                fcb     $2D,37
                fdb     err_t763f
                fcb     $2E,18
                fdb     err_t7664
                fcb     $2F,36
                fdb     err_t7676
                fcb     $30,28
                fdb     err_t769a
                fcb     $32,23
                fdb     err_t76b6
                fcb     $33,31
                fdb     err_t76cd
                fcb     $34,28
                fdb     err_t76ec
                fcb     $35,28
                fdb     err_t7708
                fcb     $36,24
                fdb     err_t7724
                fcb     $37,27
                fdb     err_t773c
                fcb     $38,25
                fdb     err_t7757
                fcb     $39,27
                fdb     err_t7770
                fcb     $3A,35
                fdb     err_t778b
                fcb     $3B,40
                fdb     err_t77ae
                fcb     $65,33
                fdb     err_t77d6
                fcb     $66,39
                fdb     err_t77f7
                fcb     $67,39
                fdb     err_t781e
                fcb     $68,30
                fdb     err_t7a79
                fcb     $69,31
                fdb     err_t7845
                fcb     $6A,32
                fdb     err_t7864
                fcb     $6B,35
                fdb     err_t7884
                fcb     $6C,33
                fdb     err_t78a7
                fcb     $6D,37
                fdb     err_t78c8
                fcb     $6E,16
                fdb     err_t78ed
                fcb     $6F,31
                fdb     err_t78fd
                fcb     $70,32
                fdb     err_t791c
                fcb     $71,40
                fdb     err_t793c
                fcb     $72,19
                fdb     err_t7964
                fcb     $73,40
                fdb     err_t7977
                fcb     $79,23
                fdb     err_t799f
                fcb     $7A,27
                fdb     err_t79b6
                fcb     $7B,23
                fdb     err_t79d1
                fcb     $7C,32
                fdb     err_t79e8
                fcb     $96,37
                fdb     err_t78c8
                fcb     $97,33
                fdb     err_t7a08
                fcb     $98,40
                fdb     err_t7a29
                fcb     $99,40
                fdb     err_t7a51
                fcb     $A0,30
                fdb     err_t7a79
                fcb     $FF,25
                fdb     err_t7a97

                ; THIS FIRMWARE'S OWN, from $C0 - above every code the stock
                ; table uses below $FF, so none of them can collide with an
                ; instrument code. They are faults the instrument has no
                ; message for: it has no paged-call check, no protected
                ; address, no display read-back and no option that can be
                ; asked for and refused, because it hides an uninstalled
                ; option's menu entry instead. common/formats.inc carries the
                ; same nine numbers with the same words.
                fcb     $C0,20
                fdb     err_own_option
                fcb     $C1,24
                fdb     err_own_page
                fcb     $C2,18
                fdb     err_own_ram
                fcb     $C3,24
                fdb     err_own_phase
                fcb     $C4,26
                fdb     err_own_destn
                fcb     $C5,19
                fdb     err_own_unit
                fcb     $C6,22
                fdb     err_own_display
                fcb     $C7,20
                fdb     err_own_protect
                fcb     $C8,31
                fdb     err_own_internal

                fcb     $FF,18
                fdb     err_t7ab0   ; the fallback: the search above stops one short of it

; ---------------------------------------------------------------------------
; the strings themselves, in the order the table first reaches them. Four are
; shared: $7A79 answers codes $16, $68 and $A0, $75EE answers $29 and $2A, and
; $78C8 answers $6D and $96 - so fifty-nine strings carry sixty-three codes.
; ---------------------------------------------------------------------------
err_t7445    fcc     "No Error"
err_t744d    fcc     "Key parser not active"
err_t7462    fcc     "Invalid key entry"
err_t7473    fcc     "Invalid HP-IB address"
err_t7488    fcc     "No incrementable field"
err_t749e    fcc     "No Output Board 1"
err_t74af    fcc     "Hardware errors detected"
err_t74c7    fcc     "PLL reference out of lock"
err_t74e0    fcc     "Reverse power error detected"
err_t74fc    fcc     "No recall setting in this register"
err_t751e    fcc     "Un-executable command"
err_t7533    fcc     "Go to Main Selection Level for SPECIAL"
err_t7559    fcc     "Only 0 - 15 valid"
err_t756a    fcc     "Only 0 - 65535 valid"
err_t757e    fcc     "Number too large"
err_t758e    fcc     "Not an incrementable field"
err_t7a79    fcc     "Output selected does not exist"
err_t75a8    fcc     "No settable functions in this window"
err_t75cc    fcc     "Option FW needed for DESTN control"
err_t75ee    fcc     "HP-IB number in error"
err_t7603    fcc     "Number received but not expected"
err_t7623    fcc     "Invalid Unique data received"
err_t763f    fcc     "Unique data received but not expected"
err_t7664    fcc     "Invalid terminator"
err_t7676    fcc     "Terminator received but not expected"
err_t769a    fcc     "Invalid HP-IB token received"
err_t76b6    fcc     "Time value out of range"
err_t76cd    fcc     "On & Off times cannot both be 0"
err_t76ec    fcc     "Amplitude value out of range"
err_t7708    fcc     "Frequency value out of range"
err_t7724    fcc     "Tone number out of range"
err_t773c    fcc     "Sequence index out of range"
err_t7757    fcc     "Sequence end out of range"
err_t7770    fcc     "Invalid digit for this base"
err_t778b    fcc     "Commmand not permitted in this mode"
err_t77ae    fcc     "Commmand not available in present window"
err_t77d6    fcc     "Channel A can not modulate itself"
err_t77f7    fcc     "Ch A's DC waveform can not be modulated"
err_t781e    fcc     "Modulation with DC waveform not allowed"
err_t7845    fcc     "AM & DSB are mutually exclusive"
err_t7864    fcc     "Summing channels cannot be split"
err_t7884    fcc     "Hop Ram enabled for this mod source"
err_t78a7    fcc     "Frequency too great for pulse mod"
err_t78c8    fcc     "Frequency too great for this waveform"
err_t78ed    fcc     "AM or DSB active"
err_t78fd    fcc     "Hop Ram Amplitudes are too high"
err_t791c    fcc     "Hop Ram Frequencies are too high"
err_t793c    fcc     "Hop Ram frequency too great for waveform"
err_t7964    fcc     "Phase mod is active"
err_t7977    fcc     "Last Ch A freq is too great for waveform"
err_t799f    fcc     "Amplitude exceeds limit"
err_t79b6    fcc     "Amplitude sum exceeds limit"
err_t79d1    fcc     "Frequency exceeds limit"
err_t79e8    fcc     "Last Ch A amplitude is too large"
err_t7a08    fcc     "Outx or off destn required for DC"
err_t7a29    fcc     "DC not permitted while modulation active"
err_t7a51    fcc     "Only one DC sum permitted into an output"
err_t7a97    fcc     "Function not implemented."
err_t7ab0    fcc     "Message not found."

; --- and this firmware's own, in the instrument's voice --------------------
err_own_option   fcc     "Option not installed"
err_own_page     fcc     "Paged ROM did not answer"
err_own_ram      fcc     "RAM fault detected"
err_own_phase    fcc     "Phase value out of range"
err_own_destn    fcc     "Destination code not known"
err_own_unit     fcc     "Unit code not known"
err_own_display  fcc     "Display fault detected"
err_own_protect  fcc     "Address is protected"
err_own_internal fcc     "Firmware fault - withdrawn call"
