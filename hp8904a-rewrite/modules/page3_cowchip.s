; ===========================================================================
; page3_cowchip.s - direct access to the synthesis chip's registers
;
; The service screen the stock firmware calls the cowchip screen. It writes
; the DDS registers by name, which is what an engineer with the chip's data
; sheet in front of them wants.
;
; It differs from the DDS screen on the service menu in one way that matters:
; this one shows the registers in the chip's own numbering and lets any value
; be written, including ones the front panel would never produce. That is the
; point of a service screen, and it is why the menu marks it destructive.
;
; THE VALUE FIELD IS THE STOCK'S: eight decimal digits, saturated to the
; register's width before the write. cowchip_enter_register_value ($5B08 on
; this page of the stock) right-justifies eight digits with
; right_shift_entry_digits ($B223), converts them with ascii8_to_uint24
; ($CB10) and hands the 24 bits to dds_register_write_clamped ($56FC), which
; clamps by the width dds_register_descriptor ($DD3B) returns. This screen
; took two hexadecimal digits, wrote a width-1 register unclamped and had no
; path at all for a width-4 register: dds_write refuses width 4 with carry,
; and the ENTER path did not test the carry, so a frequency register was
; refused without a sound. That was SUSPECTED DEFECTS 24 in
; hp8904a-rewrite/COVERAGE.txt.
; ===========================================================================

; ONE LINE CARRIES BOTH. cow_warn was defined and referenced nowhere - the
; screen that writes the synthesis chip's registers directly never told the
; operator that it does. The screen owns two lines and the second holds the
; register, its name and its value, so the warning shares the title.
cow_title       fcc     "DDS Register Access Changes the output  "

; LINE 2 IS THE STOCK'S. show_manual_cowchip_screen ($5EC8) paints the forty
; bytes at $43AC - "Register=     Data=" and blanks - over DDRAM $40, and
; cowchip_screen_handler ($5914) then puts the register number at $4A (l5ceb:
; two characters from $2417 at $4A), the value at $54 (dds_register_value_show
; $57C8 blanks eight columns at $54 first) and the name at $61 (l56e3: seven
; characters at $61). Painting the whole line first is what blanks the value
; field and everything the previous screen left.
cow_line2       fcc     "Register=     Data=                     "

COW_REG_POS     equ     LCD_LINE2+10    ; $4A: two decimal digits
COW_VALUE_POS   equ     LCD_LINE2+20    ; $54: eight columns
COW_NAME_POS    equ     LCD_LINE2+33    ; $61: seven characters
COW_FIELD_REG   equ     0               ; which field the digits go into
COW_FIELD_VALUE equ     1
COW_REG_ENTRY_W equ     5               ; cowchip_entry_arm_index ($5AAD)
                                        ; right-justifies FIVE digits and
                                        ; converts them with atoi5 ($C973)
COW_REG_DIGITS  equ     2               ; l5ceb writes two of the five $C912
                                        ; makes
COW_NAME_LEN    equ     7
COW_VALUE_LEN   equ     8               ; the field cowchip_cursor_arm_regdata
                                        ; ($5E57) arms: width $08 at $54
COW_SHORT_LEN   equ     5               ; widths 1 to 3: $57E6 and $5819 set
                                        ; length 4 and l5871 writes length+1

; THE SATURATION, from dds_register_write_clamped ($56FC).
COW_W1_LIMIT    equ     $40             ; width 1: CMPB #$40 / LBCC l5745
COW_SAT_W1      equ     $3F             ; l5745: LDB #$3F / STB 2,X
COW_W23_LIMIT   equ     $0F             ; widths 2, 3: CMPB #$0F / LBHI l5777
COW_SAT_W23     equ     $0FFF           ; l5777: $0F into byte 1, $FF into 2
COW_BLANK_W1    equ     3               ; $57E6 arm: blank_leading_zeros(3)
COW_BLANK_W23   equ     1               ; $5819 arm: blank_leading_zeros(1)
COW_ALL_ONES    equ     $FF             ; ascii8_to_uint24 ($CB10): $FF into
                                        ; all three bytes at $CB70-$CB91 when
                                        ; add24 carries out of bit 23

; THE REGISTER NAMES ARE NOT HERE ANY MORE. This file carried its own copy of
; an eight-entry table naming ids $00-$07 as FREQ A, PHASE B, LEVEL C, FREQ D,
; WAVEFM1, OUT MUX, CLKDIV1 and SYNCSEL. Those ids are the eight BUFFER
; LATCHES, and common/formats.inc had already recorded that whole set being
; withdrawn as invented - the correction was applied there and not here, which
; is one instance repaired and its sibling left.
;
; The real names were read out of the stock ROM's own pointer table at $568F
; on this very page, and there are forty-two of them, not eight. They live in
; service_dds.s in the always-mapped image and this screen calls
; ABI_dds_reg_name, so the two screens cannot disagree again.

; THE REGISTER WIDTHS, from the stock's descriptor table at $DD73 in A2U12,
; byte for byte. dds_register_descriptor ($DD3B) reads one byte per id and
; the width is the top two bits plus one (ANDA #$C0 / ASLA / ROLA / ROLA /
; INCA at $DD5A): 1 for the eight buffer latches $00-$07, for $14 and for
; $15-$26 and $28-$29; 2 for the levels $0C-$0F ($54,$56,$58,$5A); 3 for the
; phases $10-$13 ($9C,$9E,$A0,$A2); 4 for the frequencies $08-$0B
; ($C8,$CB,$CE,$D1) and for $27 ($F6). The low six bits are the offset in
; the stock's $248A shadow, which this page does not use. modules/dds.s
; carries the same bytes as dds_descriptors for the always-mapped image, and
; common/abi.inc has no slot for dds_width, so this page reads its own copy.
cow_descriptors
                fcb     $00,$01,$02,$03,$04,$05,$06,$07
                fcb     $C8,$CB,$CE,$D1                 ; $08-$0B frequency
                fcb     $54,$56,$58,$5A                 ; $0C-$0F level
                fcb     $9C,$9E,$A0,$A2                 ; $10-$13 phase
                fcb     $00                             ; $14
                fcb     $24,$25,$26,$27,$28,$29,$2A,$2B ; $15-$1C
                fcb     $2C,$2D,$2E,$2F,$30,$31,$32,$33 ; $1D-$24
                fcb     $34,$35                         ; $25-$26
                fcb     $F6                             ; $27
                fcb     $39,$3A                         ; $28-$29

; A value of zero, three bytes, for the display of a width-4 register this
; screen has never written; see cow_show_value.
cow_zero24      fcb     $00,$00,$00

; THE LAST WIDE WRITE. dds_read in modules/dds.s returns zero for every
; width-4 register - its header says so - because dds_write_wide stages them
; straight to the port and keeps no shadow, where the stock's dds_param_store
; ($DD9D) keeps three bytes at $248A+offset and dds_register_value_show
; ($57C8) prints them. So this page keeps the value it last wrote to a
; width-4 register, and which register that was, and shows the value while
; the screen is on that register. Four bytes between math_work (3 bytes at
; +$09) and text_buffer (+$10), which modules/scratch.inc leaves unnamed;
; scratch_reset in modules/boot.s clears them with the rest of the scratch,
; and id 0 is width 1, so a cleared cow_wide_reg matches nothing this
; consults. A frequency programmed from another screen since is not in it,
; which is the same shadow gap the DDS service screen has.
; cow_wide_reg and cow_wide_value are declared in modules/scratch.inc,
; where test_scratch_layout.py checks them.

; ---------------------------------------------------------------------------
; cow_name_address - the name of one register
;
;   entry: B = the register number
;   exit:  X = seven characters, carry CLEAR; carry SET and X untouched for a
;          number the chip does not have
;   uses:  A, B, X
;
; THE TABLE IT WALKED IS GONE and this is now three instructions through the
; ABI. It had its own copy of an invented eight-name set, and it bounded the
; number against DDS_REGISTERS - forty-two - while indexing a table of eight,
; so any id from 8 to 41 read up to two hundred and thirty-eight bytes past
; the end of it and displayed whatever followed as a register name. The
; comment above it said an out-of-range number "shows the first name rather
; than reading past the table", which is what the clrb does for ids at or
; above forty-two and not what happened for the thirty-four in between.
;
; The caller decides what to do with carry now, rather than being handed a
; wrong name it cannot tell from a right one.
; ---------------------------------------------------------------------------
cow_name_address
                lbra    ABI_dds_reg_name

; ---------------------------------------------------------------------------
; cow_width - how wide a register is
;
;   entry: B = the register number
;   exit:  A = the width code, 1 to 4, carry CLEAR; carry SET and A untouched
;          for a number the chip does not have. B is kept.
;   uses:  A, X
;
; The decode of dds_register_descriptor ($DD3B): the descriptor byte's top
; two bits, plus one. The stock's LDX 8,S / CMPX #$0029 / BHI clamps a bad id
; to 0 and returns width 1 for it; here a bad id is reported instead, and the
; two callers never make one because cow_register is wrapped at
; DDS_REGISTERS by cow_key.
; ---------------------------------------------------------------------------
cow_width
                cmpb    #DDS_REGISTERS
                bhs     cow_width_none
                ldx     #cow_descriptors
                lda     b,x
                lsra
                lsra
                lsra
                lsra
                lsra
                lsra
                inca
                andcc   #~CC_CARRY
                rts
cow_width_none
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; cow_show - paint the screen for the register it is showing
;
;   uses:  A, B, X, Y, U - Y and U through the ABI routines it calls
;
; IT READS cow_register ITSELF. The header said "entry: B = the register
; number" and not one of its four callers set it: one branched here after
; `clr >cow_register` with B holding whatever the screen's caller had left,
; two arrived straight out of entry_begin_hex with B at zero, and the fourth
; passed the digit that had just been typed. So the screen painted register 0,
; or the last digit keyed, or a leftover - never reliably the register
; cow_register says it is on.
;
; The variable exists for exactly this and every key handler already
; maintains it, so taking the number from a register as well was two sources
; of truth for one fact, and the callers disagreed with the variable rather
; than with each other.
;
; The order is the stock's l5ceb: the number, then the value through
; dds_register_value_show ($57C8), then the name through
; show_cowchip_register_name ($5517). Shows what was last WRITTEN, not what
; the chip holds - there is no read path.
; ---------------------------------------------------------------------------
cow_show
                lda     #LCD_LINE1
                ldx     #cow_title
                ldb     #SVC_LABEL_LEN
                lbsr    ABI_lcd_write

                lda     #LCD_LINE2              ; the labels first, over the
                ldx     #cow_line2              ; whole line, so nothing of
                ldb     #SVC_LABEL_LEN          ; the last screen survives
                lbsr    ABI_lcd_write

                ; The register number: l5ceb converts $3FB8 with
                ; u16_to_5_ascii_digits ($C912) and writes the last two of
                ; the five digits at $4A. uint24_to_text makes eight, and
                ; the last two of those are the same two.
                clra
                ldb     >cow_register
                pshs    a,b                     ; high byte at the lower
                clr     ,-s                     ; address, zero above both
                leax    ,s
                lbsr    ABI_uint24_to_text
                leas    3,s
                lda     #COW_REG_POS
                ldx     #text_buffer+6          ; the last two digits
                ldb     #COW_REG_DIGITS
                lbsr    ABI_lcd_write

                ldb     >cow_register
                lbsr    cow_show_value

                ldb     >cow_register
                lbsr    cow_name_address
                bcc     cow_show_named          ; carry set: the chip has no
                rts                             ; such register, so no name is
                                                ; painted rather than a wrong
cow_show_named                                  ; one
                lda     #COW_NAME_POS
                ldb     #COW_NAME_LEN
                lbra    ABI_lcd_write

; ---------------------------------------------------------------------------
; cow_show_value - the register's value, as the stock prints it
;
;   entry: B = the register number
;   uses:  A, B, X, Y, U - Y and U through uint24_to_text
;
; dds_register_value_show ($57C8) blanks eight columns at $54 and then prints
; by the width dds_register_descriptor ($DD3B) returns, switching at l585e:
; width 1 (l57e6) puts the byte through u16_to_5_ascii_digits ($C912) and
; blank_leading_zeros ($CCFF) with a count of 3, five characters; widths 2
; and 3 (l5819) put the sixteen-bit word through the same two with a count
; of 1, five characters; width 4 (l5847) puts the three bytes through
; uint24_to_ascii8 ($CA8F), eight characters. The eight columns are already
; blank here because cow_show paints the whole of cow_line2 first, so the
; five-character widths leave their last three columns blank the same way.
;
; Widths 1 to 3 come from dds_read, which returns the sixteen bits dds_write
; stored - the saturated value, which is what the stock's shadow holds after
; dds_register_write_clamped ($56FC). Width 4 comes from cow_wide_value when
; this screen wrote the register, and is zero otherwise - see the note at
; cow_wide_reg.
; ---------------------------------------------------------------------------
cow_show_value
                lbsr    cow_width               ; A = 1 to 4, B kept
                bcc     cow_show_value_known    ; carry: no such register, so
                rts                             ; no value is painted either
cow_show_value_known
                cmpa    #4
                beq     cow_show_wide
                pshs    a                       ; the width
                lbsr    ABI_dds_read            ; X = the sixteen-bit shadow
                tfr     x,d
                pshs    a,b                     ; high byte at the lower
                clr     ,-s                     ; address, zero above both
                leax    ,s
                lbsr    ABI_uint24_to_text
                leas    3,s
                puls    a                       ; the width
                ldb     #COW_BLANK_W23
                cmpa    #1
                bne     cow_show_short
                ldb     #COW_BLANK_W1
cow_show_short
                ldx     #text_buffer+3          ; the last five digits
                lbsr    cow_blank_zeros
                lda     #COW_VALUE_POS
                ldx     #text_buffer+3
                ldb     #COW_SHORT_LEN
                lbra    ABI_lcd_write
cow_show_wide
                ldx     #cow_wide_value
                cmpb    >cow_wide_reg
                beq     cow_show_wide_text
                ldx     #cow_zero24
cow_show_wide_text
                lbsr    ABI_uint24_to_text
                lda     #COW_VALUE_POS
                ldx     #text_buffer
                ldb     #COW_VALUE_LEN
                lbra    ABI_lcd_write

; ---------------------------------------------------------------------------
; cow_blank_zeros - suppress leading zeros in a fixed-width number
;
;   entry: X = the characters, B = how many may be blanked
;   uses:  A, B, X
;
; blank_leading_zeros ($CCFF), without the frame: from index 0, while the
; character is '0' ($30) or ' ' ($20) and fewer than the count have been
; passed, it becomes ' ', and the loop stops at the first character that is
; neither. The count is what keeps the last digit - three of five for width
; 1 and one of five for widths 2 and 3, so zero comes out as "   00" and
; " 0000" from those arms.
; ---------------------------------------------------------------------------
cow_blank_zeros
                tstb
                beq     cow_blank_done
                lda     ,x
                cmpa    #$30                    ; '0'
                beq     cow_blank_one
                cmpa    #$20                    ; ' '
                bne     cow_blank_done
cow_blank_one
                lda     #$20
                sta     ,x+
                decb
                bra     cow_blank_zeros
cow_blank_done
                rts

; ---------------------------------------------------------------------------
; cow_write - write the entered value to a register, saturated to its width
;
;   entry: B = the register number; entry_result = the value, 24 bits, most
;          significant byte first
;   exit:  carry SET if nothing was written
;   uses:  A, B, X, U
;
; dds_register_write_clamped ($56FC), arm by arm. It takes the width from
; dds_register_descriptor ($DD3B) and switches on it at l579f:
;
;   width 1 (l571a)    bytes 0 and 1 must be zero and byte 2 below $40, or
;                      byte 2 becomes $3F (l5745); the one byte is passed
;   widths 2, 3 (l575a) byte 0 must be zero and byte 1 at most $0F, or bytes
;                      1 and 2 become $0F,$FF (l5777); the two bytes are passed
;   width 4 (l5796)    the three bytes, unclamped
;
; and l57b4 hands the sized pointer to dds_param_store ($DD9D). Here widths 1
; to 3 go through dds_write, which sends the one data byte for width 1 and
; stages two six-bit fields through the width's own latch pair for 2 and 3,
; and the frequencies $08-$0B go through freq_program, the 24-bit staging
; every frequency in this firmware uses. The twelve-bit test is one CMPX:
; with byte 0 zero, the word of bytes 1 and 2 is at most $0FFF exactly when
; byte 1 is at most $0F.
;
; REGISTER $27 IS WIDTH 4 TOO. freq_program masks its register to $08-$0B,
; so it goes through ABI slot 70, dds_write_wide in modules/frequency.s -
; the four-field staging with the channel arithmetic left out - which is the
; stock's $56FC treating all five width-4 registers alike. Until that slot
; existed the ENTER path refused $27 with error_raise.
; ---------------------------------------------------------------------------
cow_write
                lbsr    cow_width               ; A = 1 to 4, B kept
                bcs     cow_write_bad
                cmpa    #4
                beq     cow_write_wide
                cmpa    #1
                beq     cow_write_one

                ; --- widths 2 and 3: twelve bits ---------------------------
                lda     >entry_result           ; byte 0 must be zero
                bne     cow_write_sat12
                ldx     >entry_result+1         ; bytes 1 and 2 as a word
                cmpx    #COW_SAT_W23
                bls     cow_write_send
cow_write_sat12
                ldx     #COW_SAT_W23
                bra     cow_write_send

                ; --- width 1: six bits -------------------------------------
cow_write_one
                lda     >entry_result
                ora     >entry_result+1         ; bytes 0 and 1 both zero
                bne     cow_write_sat6
                lda     >entry_result+2
                cmpa    #COW_W1_LIMIT           ; and byte 2 below $40
                blo     cow_write_byte
cow_write_sat6
                lda     #COW_SAT_W1
cow_write_byte
                pshs    b                       ; the id
                tfr     a,b
                clra
                tfr     d,x                     ; X = $00, the byte
                puls    b
cow_write_send
                lbra    ABI_dds_write           ; carry CLEAR on return: the
                                                ; id passed cow_width and the
                                                ; width is not 4, which are
                                                ; the two refusals dds_write
                                                ; has

                ; --- width 4: twenty-four bits -----------------------------
cow_write_wide
                stb     >cow_wide_reg           ; the display's copy
                ldx     #cow_wide_value
                ldu     #entry_result
                lbsr    ABI_copy24              ; X <- U, three bytes
                cmpb    #DDS_FREQ_BASE+4
                bhs     cow_write_pll
                subb    #DDS_FREQ_BASE          ; the channel, 0 to 3
                lbsr    ABI_freq_program        ; U = the value, still
                andcc   #~CC_CARRY
                rts
cow_write_pll
                ; $27, THE PLL DIVIDER, the fifth width-4 register in the
                ; descriptor table at $DD73 ($F6). The stock's $56FC writes
                ; it like the other four - three bytes unclamped, then
                ; dds_param_store ($DD9D) - and this screen refused it until
                ; ABI slot 70 exported dds_write_wide (frequency.s), the
                ; four-field staging freq_program uses with the channel
                ; arithmetic left out. B is still the id; U still points at
                ; the value.
                lbsr    ABI_dds_write_wide
                andcc   #~CC_CARRY
                rts
cow_write_bad
                ; AN ID OUTSIDE THE TABLE - cow_width found no descriptor for
                ; it. The stock's $56FC is only ever reached with an id its
                ; own descriptor lookup ($DD3B) accepts; here the refusal is
                ; heard, not silent.
                ldb     #ERR_VALUE_RANGE
                lbsr    ABI_error_raise         ; NOT lbra: error_raise makes
                orcc    #CC_CARRY               ; no promise about carry, so
                rts                             ; tail-calling it returned
                                                ; whatever it happened to
                                                ; leave - and this routine's
                                                ; header promises carry SET
                                                ; when nothing was written

; ---------------------------------------------------------------------------
; cowchip_open - the mode entry point, reached through $4001
;
;   exit:  the register screen is showing register 0, with an empty entry
;          field armed
;   uses:  A, B, X, Y, U
;
; This is the screen the stock firmware kept behind the six-digit code
; 092448. It writes the synthesis chip's registers directly, which is exactly
; why a bench engineer wants it and exactly why it is worth arriving at it
; deliberately: nothing here is validated against what the rest of the
; firmware believes, so a register written here and a screen elsewhere will
; disagree until the next full apply.
;
; It is on the Main Selection Level by name, marked SVC_DESTRUCTIVE, and the
; screen says what it does on its own second line. That is a better guard
; than a number nobody can look up, because it is a guard the operator can
; read.
;
; No option check. Every instrument has the synthesis chip - it is the
; instrument - so there is nothing here to gate.
;
; THE FIELD IS ARMED ON ENTRY. It was not: screen_install clears
; entry_active and nothing else, so the first digits typed here went into
; whatever base and width the previous screen had left in entry_base and
; entry_width. The stock arms its field at the end of every pass through
; cowchip_screen_handler ($5914), through the table at $5E9A.
; ---------------------------------------------------------------------------
cowchip_open
                ldx     #cow_key
                lbsr    ABI_screen_install
                clr     >cow_register           ; always open on register 0,
                                                ; so the screen never shows a
                                                ; register somebody else left
                                                ; selected
                lda     #COW_FIELD_VALUE        ; and on the value field,
                sta     >cow_field              ; which is the one an engineer
                                                ; who has chosen a register
                                                ; wants
                lbsr    cow_field_begin
                lbsr    cow_show
                lbra    cow_arm                 ; the $0000 posted at open re-arms

; ---------------------------------------------------------------------------
; cow_field_begin - arm the entry for whichever field is selected
;
;   uses:  A, B, X
;
; The value field is eight decimal digits at $54, which is what
; cowchip_cursor_arm_regdata ($5E57) arms. The register field is five, which
; is what cowchip_entry_arm_index ($5AAD) takes - it calls
; right_shift_entry_digits ($B223) with 5 and converts with atoi5 ($C973).
; ---------------------------------------------------------------------------
cow_field_begin
                lda     >cow_field
                beq     cow_field_begin_reg
                lbra    ABI_entry_begin_dec
cow_field_begin_reg
                lda     #ENTRY_DECIMAL
                ldb     #COW_REG_ENTRY_W
                lbra    ABI_entry_begin         ; slot 13: A the base, B the
                                                ; width

; ---------------------------------------------------------------------------
; cow_key - the direct register screen's keys
;
;   entry: B = the key code
;   uses:  A, B, X, Y, U - Y and U through the ABI routines it calls
;
; NEXT and LAST step through the chip's registers by name; digits build a
; decimal value; ENTER saturates it to the register's width and writes it.
;
; DECIMAL, EIGHT DIGITS, because that is the stock's field:
; cowchip_cursor_arm_regdata ($5E57) opens width $08 at $54, and
; cowchip_enter_register_value ($5B08) reads it back with ascii8_to_uint24
; ($CB10), which subtracts $30 from each character and adds the power of ten
; from table_ee4a ($EE4A) that many times. The two-digit hexadecimal field
; this screen had could reach 255 of the 16,777,216 values a frequency
; register takes.
;
; THERE IS NO CONFIRMATION and there deliberately is not. This screen exists
; to poke the synthesis chip, and an engineer who reached it by choosing an
; entry that says "write the DDS direct" has already said what they mean. The
; safety is that the chip is not where the serial number lives - nothing on
; this screen can reach $2000-$3FFF at all.
; ---------------------------------------------------------------------------
; ---------------------------------------------------------------------------
; cow_key - a key on the register screen, and the re-arm after it
;
;   entry: B = the key code
;   uses:  A, B, X, Y, U
;
; THE CURSOR IS RE-ARMED AFTER EVERY MESSAGE, with three exceptions. The
; stock's cowchip_screen_handler ($5914) ends every pass in the tail at
; l5ea4, which arms the field $3FB4 names through the table d5e9a at $5EC0;
; the passes that leave before it are f4 ($16, at $5A05) and, while the
; register half is up, the three field keys FREQ, AMPTD and PHASE ($19, $1A
; and $1C, at $5947, $5967 and $5987). A digit or a terminator is not a
; message - numeric_entry_key_handler ($B3C2) keeps it - and only moves the
; display's address after the typed characters ($B567), which a commit's
; own arm then follows (cow_key_enter). cow_key_body is the handler.
; ---------------------------------------------------------------------------
cow_key
                pshs    b
                lbsr    cow_key_body
                puls    b
                ldx     >screen_handler         ; a key that left the screen
                cmpx    #cow_key                ; arms nothing
                bne     cow_key_rearm_none
                cmpb    #KEY_FREQ               ; $5947, $5967, $5987: the
                beq     cow_key_rearm_none      ; three field keys leave
                cmpb    #KEY_AMPL               ; before l5ea4
                beq     cow_key_rearm_none
                cmpb    #KEY_PHASE
                beq     cow_key_rearm_none
                lbsr    cow_cell                ; A = $23AD + $23A4
                lbsr    ABI_entry_key_is_mapped ; a message: l5ea4 re-arms
                lbne    ABI_entry_cursor_on
                lbra    ABI_lcd_cursor          ; a key $B3C2 kept: $B567
cow_key_rearm_none
                rts

; ---------------------------------------------------------------------------
; cow_arm  - the selected field armed: the cursor on its next cell
; cow_cell - that cell: A = the field's first column plus the digits typed
;
;   uses:  A
;
; The register number at $4A and the value at $54, the first two columns of
; d5e9a's arms [0] and [1] ($5EC0 hands the one $3FB4 selects to $AC35).
; ---------------------------------------------------------------------------
cow_arm
                bsr     cow_cell
                lbra    ABI_entry_cursor_on     ; $AC98, $ACA6
cow_cell
                lda     #COW_REG_POS            ; [0] $4A
                tst     >cow_field
                beq     cow_cell_count
                lda     #COW_VALUE_POS          ; [1] $54
cow_cell_count
                adda    >entry_count            ; + $23A4
                rts

; ---------------------------------------------------------------------------
; cow_key_body - the register screen's keys, without the re-arm
;
;   entry: B = the key code
;   uses:  A, B, X, Y, U
; ---------------------------------------------------------------------------
cow_key_body
                ; f4 IS THE WAY OUT, and this screen had none once LOCAL
                ; stopped being one. cowchip_screen_handler ($5914) answers
                ; $0016 at l5a05 with post_request_code ($8AD0) and request
                ; $0003 - the same leave the Keyboard Check's exit posts -
                ; while its default arm l5c74 only beeps and repaints.
                cmpb    #KEY_F4
                lbeq    ABI_screen_back
                cmpb    #KEY_F1                 ; THE REGISTER BY NUMBER, not
                bne     cow_key_f2              ; by thirty-nine presses of
                clr     >cow_field              ; NEXT. cowchip_entry_arm_index
                bra     cow_key_refield         ; ($5AAD) is the stock's arm
cow_key_f2                                      ; for this, five digits into
                cmpb    #KEY_F2                 ; the register number, and it
                bne     cow_key_next            ; had no counterpart here
                lda     #COW_FIELD_VALUE
                sta     >cow_field
cow_key_refield
                lbsr    cow_field_begin
                lbra    cow_show
cow_key_next
                cmpb    #KEY_NEXT
                bne     cow_key_last
                ldb     >cow_register
                incb
                cmpb    #DDS_REGISTERS
                blo     cow_key_select
                clrb
                bra     cow_key_select
cow_key_last
                cmpb    #KEY_LAST
                bne     cow_key_enter
                ldb     >cow_register
                tstb
                bne     cow_key_back
                ldb     #DDS_REGISTERS
cow_key_back
                decb
cow_key_select
                stb     >cow_register
                lda     #COW_FIELD_VALUE        ; stepping the register leaves
                sta     >cow_field              ; the operator on its value
                lbsr    cow_field_begin         ; a new register is a new entry
                lbra    cow_show

cow_key_enter
                cmpb    #KEY_ENTER
                bne     cow_key_backspace
                lbsr    ABI_entry_cursor_off    ; $B5BA: class 2 takes ENTER, and
                lbsr    cow_key_commit          ; request $23 - then l5ea4's arm
                lbra    cow_arm
cow_key_commit
                lda     >cow_field              ; whichever field is armed
                bne     cow_key_enter_value
                tst     >entry_count            ; the register number: nothing
                beq     cow_key_redraw          ; typed changes nothing, which
                lbsr    ABI_entry_value         ; is what $5AAD does when
                bcs     cow_key_redraw          ; right_shift_entry_digits
                ldb     >entry_result+2         ; returns zero
                cmpb    #DDS_REGISTERS          ; BOUNDED, as the stock bounds
                bhs     cow_key_reg_bad         ; its RAM slot to $0F. A wild
                stb     >cow_register           ; id would index the name and
                lda     #COW_FIELD_VALUE        ; descriptor tables past their
                sta     >cow_field              ; ends
                lbsr    cow_field_begin
                lbra    cow_show
cow_key_reg_bad
                lbsr    ABI_key_refuse          ; and put the field back, so
                lbsr    cow_field_begin         ; the refused digits do not
                lbra    cow_show                ; sit on the display
cow_key_enter_value
                tst     >entry_count            ; NOTHING TYPED, NOTHING
                beq     cow_key_redraw          ; WRITTEN: $5B08 tests what
                                                ; right_shift_entry_digits
                                                ; ($B223) returns, which is
                                                ; the digit count $23A4
                                                ; (lb2c6: LDB 6,S from 4,S),
                                                ; and LBRA l5c71 skips the
                                                ; write when it is zero
                lbsr    ABI_entry_value         ; entry_result = 24 bits
                bcc     cow_key_fits
                lda     #COW_ALL_ONES           ; more than 24 bits: the
                sta     >entry_result           ; stock's converter saturates
                sta     >entry_result+1         ; at $FFFFFF ($CB70-$CB91)
                sta     >entry_result+2         ; and the width clamp takes
                                                ; it from there
cow_key_fits
                ldb     >cow_register
                lbsr    cow_write               ; saturated to the width and
                                                ; written - every register in
                                                ; the table, $27 included
                lbsr    ABI_entry_begin_dec     ; l5c71 falls into the repaint
                                                ; and the $5E9A arm re-arms
                                                ; the field: a fresh one here
cow_key_redraw
                lbra    cow_show

cow_key_backspace
                cmpb    #KEY_BACKSPACE
                bne     cow_key_digit
                ; THE LAST DIGIT OUT AGAIN. entry_backspace ($B2CD, reached
                ; at $B4B9 for key $1F) steps the head $23A4 back and blanks
                ; the vacated cell ($B2E9-$B31F); this screen's entry keeps
                ; no sign, so the kind-2 head reset to '+' ($B351-$B35A) has
                ; nothing to act on here. numeric_entry_key_handler repaints
                ; the buffer ($B4D0-$B501) once a key has been accepted
                ; ($B4C4); with nothing to take out (the carry) the glass is
                ; left as it is, which is what $B4CD leaves.
                lbsr    ABI_entry_backspace     ; $B2E9-$B31F, slot 73
                bcs     cow_key_done
                bra     cow_key_echo            ; $B4D0-$B501
cow_key_done
                rts
cow_key_digit
                lbsr    ABI_key_digit           ; THE DISPATCHER HANDS OVER A
                                                ; KEY CODE, not a character.
                                                ; This called hex_to_nibble,
                                                ; which decodes an ASCII digit
                                                ; out of A - and nothing on
                                                ; this path ever sets A, so no
                                                ; digit could be typed on this
                                                ; screen at all. key_digit is
                                                ; the routine that turns a key
                                                ; code in B into a value in B,
                                                ; which is what entry_digit
                                                ; below takes.
                bcs     cow_key_other
                lbsr    ABI_entry_digit         ; a ninth digit is dropped by
                                                ; entry_digit, whose header
                                                ; says so
cow_key_echo
                lbsr    cow_show                ; the stored value, then the
                ldx     #text_buffer            ; typed digits over it, right
                lbsr    ABI_entry_render        ; aligned in the field's
                lda     >cow_field              ; columns
                beq     cow_key_echo_reg
                lda     #COW_VALUE_POS
                ldx     #text_buffer
                ldb     #COW_VALUE_LEN
                lbra    ABI_lcd_write_raw       ; the echo: glass only, as
                                                ; lcd_write_string_at ($D8A5);
                                                ; cow_show above put the
                                                ; stored value in the shadow
cow_key_echo_reg
                lda     #COW_REG_POS            ; the register field is two
                ldx     #text_buffer            ; columns wide, and
                ldb     #COW_REG_DIGITS         ; entry_render pads to the
                lbra    ABI_lcd_write_raw       ; RIGHT - so the first two are
                                                ; the digits as they are
                                                ; typed. Taking the last two
                                                ; showed the padding, and the
                                                ; field looked empty while it
                                                ; was being filled
cow_key_other
                lbra    ABI_key_refuse          ; A KEY THIS SCREEN DOES NOT
                                                ; USE IS SAID SO. This was a
                                                ; bare rts, the shape
                                                ; key_refuse's header names
                                                ; in seven other screens.
