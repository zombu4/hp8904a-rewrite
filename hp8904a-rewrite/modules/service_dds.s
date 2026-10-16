; ===========================================================================
; service_dds.s - direct access to the synthesis chip's registers
;
; The DDS is programmed through a 16-bit write-only port at $0200-$0201.
; Write-only means the firmware cannot read a register back, so this screen
; keeps a shadow of everything it has sent: what is displayed is what was
; last written from here, not what the chip holds - and the screen says so
; rather than letting an engineer believe otherwise.
;
; The stock firmware's equivalent sits behind the access code with the rest of
; the diagnostics. Here it is an ordinary entry, marked destructive in the
; menu because writing a DDS register changes the output the instrument is
; producing.
;
; The register names are read out of the stock ROM's own table - see
; dds_reg_names below - so an engineer moving between this screen and HP's
; is reading the same words for the same registers.
; ===========================================================================

; ONE LINE CARRIES BOTH. dds_shadow_note was defined and never referenced -
; the one thing this file's header promises the operator will be told, that
; what is shown is what was last written from here and not what the chip
; holds, was the one thing never put on the display.
dds_title       fcc     "DDS Registers       Shown: last written "
dds_template    fcc     "Reg    Name           Value             "

DDS_REG_POS     equ     LCD_LINE2+4     ; two hex digits of the id
DDS_NAME_POS    equ     LCD_LINE2+12    ; seven characters
DDS_VALUE_POS   equ     LCD_LINE2+22    ; four hex digits, all sixteen bits

; ---------------------------------------------------------------------------
; The chip's forty-two registers, by the names HP's own diagnostics print.
;
; READ OUT OF THE ROM, not transcribed from anywhere. The stock page 3 holds a
; 42-entry pointer table at $568F; each pointer names an eight-byte arm that
; loads a string address, and the strings run from $624D upwards. This is that
; list, in register-id order.
;
; THE SET THIS REPLACES WAS ENTIRELY INVENTED, and this file's own header
; claimed the opposite - "the register names are the ones the stock
; diagnostics screen prints". It listed eight registers as FREQ A, PHASE B,
; LEVEL C, FREQ D, WAVEFM1, OUT MUX, CLKDIV1, SYNCSEL against ids $00 to $07,
; and ids $00 to $07 are the eight BUFFER LATCHES. common/formats.inc already
; recorded that exact set being withdrawn, and the correction was applied
; there and to three call sites and not to this file or to
; page3_cowchip.s - one instance repaired and its siblings left, which is the
; shape the "fix the class" rule exists for. Both now come here.
;
; On a screen whose whole purpose is to let an engineer poke a register by
; name, a name pointing at the wrong register is the failure the screen exists
; to avoid.
;
; Seven characters each, no terminator: the lookup returns a fixed length so
; nothing has to scan for one.
DDS_NAME_LEN    equ     7
DDS_REG_COUNT   equ     42              ; ids $00 to $29

; ALIGNMENT MATTERS HERE, and four of these were wrong. The stock right-aligns
; the four frequency names with a LEADING space - $628D holds
; 20 66 72 65 71 5F 61 00, which is " freq_a" - while every other name fills
; all seven columns. These four had a TRAILING space, so on the same screen
; HP's firmware paints them one column further right than this one did.
; Read out of the ROM and compared name by name: 42 checked, 4 differed, and
; only these four.
dds_name_buflat0
                fcc     "buflat0"                 ; $00
dds_name_buflat1
                fcc     "buflat1"                 ; $01
dds_name_buflat2
                fcc     "buflat2"                 ; $02
dds_name_buflat3
                fcc     "buflat3"                 ; $03
dds_name_buflat4
                fcc     "buflat4"                 ; $04
dds_name_buflat5
                fcc     "buflat5"                 ; $05
dds_name_buflat6
                fcc     "buflat6"                 ; $06
dds_name_buflat7
                fcc     "buflat7"                 ; $07
dds_name_freq_a
                fcc     " freq_a"                 ; $08
dds_name_freq_b
                fcc     " freq_b"                 ; $09
dds_name_freq_c
                fcc     " freq_c"                 ; $0A
dds_name_freq_d
                fcc     " freq_d"                 ; $0B
dds_name_level_a
                fcc     "level_a"                 ; $0C
dds_name_level_b
                fcc     "level_b"                 ; $0D
dds_name_level_c
                fcc     "level_c"                 ; $0E
dds_name_level_d
                fcc     "level_d"                 ; $0F
dds_name_phase_a
                fcc     "phase_a"                 ; $10
dds_name_phase_b
                fcc     "phase_b"                 ; $11
dds_name_phase_c
                fcc     "phase_c"                 ; $12
dds_name_phase_d
                fcc     "phase_d"                 ; $13
dds_name_ram_wrt
                fcc     "ram_wrt"                 ; $14
dds_name_ram_add
                fcc     "ram_add"                 ; $15
dds_name_fm_rang
                fcc     "fm_rang"                 ; $16
dds_name_phs_cnt
                fcc     "phs_cnt"                 ; $17
dds_name_pulse_c
                fcc     "pulse_c"                 ; $18
dds_name_am_cont
                fcc     "am_cont"                 ; $19
dds_name_fm_cont
                fcc     "fm_cont"                 ; $1A
dds_name_freq_ct
                fcc     "freq_ct"                 ; $1B
dds_name_zero_lt
                fcc     "zero_lt"                 ; $1C
dds_name_wavefm1
                fcc     "wavefm1"                 ; $1D
dds_name_wavefm2
                fcc     "wavefm2"                 ; $1E
dds_name_chanadd
                fcc     "chanadd"                 ; $1F
dds_name_out_mux
                fcc     "out_mux"                 ; $20
dds_name_out_lat
                fcc     "out_lat"                 ; $21
dds_name_outclk1
                fcc     "outclk1"                 ; $22
dds_name_outclk2
                fcc     "outclk2"                 ; $23
dds_name_clkdiv1
                fcc     "clkdiv1"                 ; $24
dds_name_clkdiv2
                fcc     "clkdiv2"                 ; $25
dds_name_configr
                fcc     "configr"                 ; $26
dds_name_pll_div
                fcc     "pll_div"                 ; $27
dds_name_syncsel
                fcc     "syncsel"                 ; $28
dds_name_sync_rg
                fcc     "sync_rg"                 ; $29

; The table's own name, kept as an equ rather than a label on a line of
; its own: every row below carries a label now, so that the coverage file
; can cite the row for the arm it answers instead of citing the table for
; forty-two of them, and a bare label with nothing under it reads to
; tests/test_no_stubs.py as a routine that returns having done nothing.
dds_reg_names        equ     dds_name_buflat0

; ---------------------------------------------------------------------------
; dds_reg_name - the name of one register
;
;   entry: B = the register id, $00 to $29
;   exit:  X = seven characters, carry CLEAR; carry SET if the id is not one
;          the chip has, and X untouched
;   uses:  A, B, X
;
; One table and one lookup for both screens. page3_cowchip.s carried its own
; copy of the invented set; it calls this through the ABI now, so the two
; cannot disagree again.
; ---------------------------------------------------------------------------
dds_reg_name
                cmpb    #DDS_REG_COUNT
                bhs     dds_reg_name_bad
                pshs    b
                lda     #DDS_NAME_LEN
                mul
                ldx     #dds_reg_names
                leax    d,x
                puls    b
                andcc   #~CC_CARRY
                rts
dds_reg_name_bad
                orcc    #CC_CARRY
                rts


; ---------------------------------------------------------------------------
; This file used to carry its own dds_write_register and dds_read_shadow,
; duplicating what dds.s does - two writers of the same shadow, which is how
; a shadow stops matching the chip. The screen calls dds_write and dds_read
; directly now.
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; dds_open - the DDS register screen, from the diagnostics menu
;
;   uses:  A, B, X, Y
;
; THE SCREEN SHOWED WHICHEVER REGISTER MENU DEPTH CHOSE. dds_show takes the
; register in B and nothing set it: menu_key_run reaches a handler through
; nav_push, which ends in `ldb #NAV_ENTRY / mul`, so B was nav_top * 5 - 0, 5,
; 10 or 15. It then installed screen_take_dismiss, where ANY key leaves, so
; exactly one register was ever displayed and which one depended only on how
; deep the operator had gone to reach it.
;
; It opens on register 0 and NEXT and LAST walk all forty-two.
; ---------------------------------------------------------------------------
dds_open
                clrb
                stb     >dds_register
                lbra    dds_show

; ---------------------------------------------------------------------------
; dds_key - the screen's keys
;
;   entry: B = the key code
;   uses:  A, B, X, Y
;
; NEXT and LAST step the register and wrap; anything else leaves, which is
; what the screen did for every key before it had a selector. LOCAL leaves
; through the foreground, as on every screen.
; ---------------------------------------------------------------------------
dds_key
                cmpb    #KEY_NEXT
                beq     dds_key_next
                cmpb    #KEY_LAST
                beq     dds_key_last

                ; A MESSAGE IS NOT A KEY, and this screen leaves on any key it
                ; does not use. Request 1 - LOCAL, which the foreground now
                ; delivers as the instrument does - reaches no arm of a stock
                ; service screen and leaves it standing, so the codes above
                ; KEY_CODE_MAX are not what this arm is for.
                cmpb    #KEY_CODE_MAX
                bhi     dds_key_message
                lbra    service_back_handler
dds_key_message
                rts
dds_key_next
                ldb     >dds_register
                incb
                cmpb    #DDS_REG_COUNT
                blo     dds_key_store
                clrb
                bra     dds_key_store
dds_key_last
                ldb     >dds_register
                tstb
                bne     dds_key_back
                ldb     #DDS_REG_COUNT
dds_key_back
                decb
dds_key_store
                stb     >dds_register
                lbra    dds_show

; ---------------------------------------------------------------------------
; dds_show - paint the screen for the selected register
;
;   uses:  A, B, X, Y
; ---------------------------------------------------------------------------
dds_show
                ldx     #dds_key
                lbsr    screen_install

                lda     #LCD_LINE1
                ldx     #dds_title
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write
                lda     #LCD_LINE2
                ldx     #dds_template
                ldb     #SVC_LABEL_LEN
                lbsr    lcd_write

                ldb     >dds_register           ; the id, in hex
                ldx     #text_buffer
                lbsr    byte_to_hex
                lda     #DDS_REG_POS
                ldx     #text_buffer
                ldb     #2
                lbsr    lcd_write

                ldb     >dds_register           ; its name
                lbsr    dds_reg_name
                bcs     dds_show_value
                lda     #DDS_NAME_POS
                ldb     #DDS_NAME_LEN
                lbsr    lcd_write

dds_show_value
                ; ALL SIXTEEN BITS. This showed two hex digits of a sixteen-bit
                ; shadow - it did `tfr x,d` and then handed only B to
                ; byte_to_hex, discarding A - so a twelve-bit amplitude or
                ; phase read as a different, smaller number with nothing to
                ; say so, on the screen whose whole point is showing what was
                ; last written.
                ldb     >dds_register
                lbsr    dds_read                ; X = the shadow
                tfr     x,d
                pshs    b                       ; the low half
                tfr     a,b                     ; the high half first
                ldx     #text_buffer
                lbsr    byte_to_hex
                puls    b
                ldx     #text_buffer+2
                lbsr    byte_to_hex

                lda     #DDS_VALUE_POS
                ldx     #text_buffer
                ldb     #4
                lbra    lcd_write

