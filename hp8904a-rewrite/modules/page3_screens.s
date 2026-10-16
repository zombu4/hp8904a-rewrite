; ===========================================================================
; page3_screens.s - the remaining service screens that live on page 3
;
; Page 3 is where the stock firmware keeps its diagnostics, behind an access
; code. Most of that work is now in A2U12, where it is reachable from an
; ordinary menu; what stays here is what only page 3 needs - screens too
; large to be worth space in the always-mapped image.
;
; Everything shared is called through the jump table. Nothing in this file
; duplicates a routine that already lives in A2U12.
; ===========================================================================

; THE HOP-RAM SCREEN IS THE STOCK'S "Ram Addr" MODE OF THE MANUAL COWCHIP
; CHECK, made writable again. It was a read-only viewer here, which kept half
; of what the stock does: $5B46 and its siblings stage a RAM address ($3FBA),
; two 12-bit words ($3FBC, $3FBE, each atoi5-parsed and clamped to $0FFF) and
; a 24-bit field ($3FC2), and ENTER on ANY field calls store_hop_ram_slot
; ($58A6) with all four - writing the slot record and clocking it into the
; chip with dds_write_channel ($DE2E). The values go in AS TYPED, raw codes,
; because a service screen that converts is not exercising the codes it
; exists to exercise: 3600 of the 4096 phase codes are expressible as tenths
; of a degree and the rest only exist raw.
;
; Word 1 is the phase code and word 2 the amplitude code - dds_write_channel
; sends element+0 first, at registers $07/$06, which is where hop_program
; puts the phase, then element+2 at $05/$04, the amplitude's pair.
;
; ONE HONEST DIFFERENCE from the stock, stated rather than smoothed over: the
; stock's slot records at $2581 HOLD codes, so a raw write stays in the record
; and every later dds_write_channel ($DE2E) of that slot re-sends it. The
; AMPLITUDE word now does the same here - hop_program_raw keeps it in
; hop_ampl_codes, which dds.s's hop_write_slot sends, as $58A6 keeps it at
; record+2. The PHASE word does not: this firmware's hop_table holds the
; phase in engineering units and converts it on every send, so the next
; frequency or phase commit of the slot on page 0 replaces the raw phase code
; with the converted one, where the stock would re-send the raw one. There is
; no room left in scratch for a second array of codes. The 24-bit field has
; no gap at all: the staged bits ARE the 0.1 Hz count, so it is written
; straight into the slot's HOP_FREQ bytes.
p3_hopram_tag   fcc     "Hop RAM raw  f2 selects field:          "
p3_addr_tag     fcc     "Slot:   W1:     W2:     F:              "

P3_FIELD_POS    equ     LCD_LINE1+31    ; the selected field's name, 4 chars
P3_SLOT_POS     equ     LCD_LINE2+5     ; two hex digits, after "Slot:"
P3_W1_POS       equ     LCD_LINE2+11    ; four decimal digits
P3_W2_POS       equ     LCD_LINE2+19
P3_FREQ_POS     equ     LCD_LINE2+26    ; eight decimal digits

P3_FIELD_SLOT   equ     3               ; THE SLOT ITSELF IS A FIELD, and the
                                        ; number goes into it: the stock's
                                        ; cowchip_entry_arm_index ($5AAD) arms
                                        ; digits over the index and, in RAM
                                        ; mode ($3FB6 = 1), clamps what is
                                        ; typed to $000F as the slot. f1 picks
                                        ; it here; NEXT and LAST still step
P3_FIELD_W1     equ     0
P3_FIELD_W2     equ     1
P3_FIELD_FREQ   equ     2
P3_FIELDS       equ     3
P3_WORD_MAX     equ     $0FFF           ; the stock's clamp on both words
P3_WORD_DIGITS  equ     4
P3_SLOT_DIGITS  equ     2               ; two over the slot's own two columns

p3_name_w1      fcc     "Wrd1"
p3_name_w2      fcc     "Wrd2"
p3_name_freq    fcc     "Freq"

; ---------------------------------------------------------------------------
; p3_hopram_open - the mode entry point, reached through this page's $4004
;
;   uses:  A, B, X, Y, U
;
; The staged words and the slot survive leaving and returning - the stock's
; $3FBA/$3FBC/$3FBE/$3FC2 do the same - and scratch_reset zeroes them at
; power-on, so the first visit starts at slot 0 with zero words.
; ---------------------------------------------------------------------------
p3_hopram_open
                ldx     #p3_hopram_key          ; INSTALLED HERE, ONCE - not
                lbsr    ABI_screen_install      ; in the repaint. screen_install
                                                ; abandons the entry in
                                                ; progress (the $3C message's
                                                ; port), and the digit path
                                                ; repaints through
                                                ; p3_hopram_show - so a repaint
                                                ; that installed would wipe
                                                ; entry_active the moment a
                                                ; digit set it, and ENTER
                                                ; would commit zeros. It did,
                                                ; on this screen's first run.
                lbsr    p3_hopram_entry         ; a fresh entry field sized
                lbsr    p3_hopram_show          ; for the selected field
                lbra    p3_hopram_arm           ; armed as it opens, as l5ea4 is

; ---------------------------------------------------------------------------
; p3_hopram_show - paint the whole screen from the staged state
;
;   uses:  A, B, X, Y, U
;
; It does NOT re-arm the entry: the digit path repaints through here, and a
; repaint that reset the entry would wipe the digits being typed.
; ---------------------------------------------------------------------------
p3_hopram_show
                lda     #LCD_LINE1
                ldx     #p3_hopram_tag
                ldb     #SVC_LABEL_LEN
                lbsr    ABI_lcd_write

                lda     >p3_field               ; which field f2 has selected
                ldx     #p3_name_w1
                cmpa    #P3_FIELD_W2
                blo     p3_hopram_named
                ldx     #p3_name_w2
                beq     p3_hopram_named
                ldx     #p3_name_freq
p3_hopram_named
                lda     #P3_FIELD_POS
                ldb     #4
                lbsr    ABI_lcd_write

                lda     #LCD_LINE2              ; the labels, whole line, so
                ldx     #p3_addr_tag            ; nothing of the previous
                ldb     #SVC_LABEL_LEN          ; screen survives in the gaps
                lbsr    ABI_lcd_write

                ldb     >p3_slot                ; the slot, in hex
                ldx     #text_buffer
                lbsr    ABI_byte_to_hex
                lda     #P3_SLOT_POS
                ldx     #text_buffer
                ldb     #2
                lbsr    ABI_lcd_write

                ldx     #p3_w1                  ; the two staged words,
                lda     #P3_W1_POS              ; decimal
                lbsr    p3_show_word
                ldx     #p3_w2
                lda     #P3_W2_POS
                lbsr    p3_show_word

                ldb     >p3_slot                ; and the slot's 24 frequency
                lbsr    p3_hop_slot_address     ; bits, decimal
                lbsr    ABI_uint24_to_text
                lda     #P3_FREQ_POS
                ldx     #text_buffer
                ldb     #TEXT_DIGITS
                lbra    ABI_lcd_write

; ---------------------------------------------------------------------------
; p3_show_word - a staged 16-bit word as four decimal digits
;
;   entry: X = the word's two bytes, A = the LCD position
;   uses:  A, B, X, Y, U - Y through uint24_to_text, whose subtraction
;          table walk leaves it on the powers of ten
;
; uint24_to_text wants three bytes in memory, most significant first. The
; word is widened on the stack: PSHS A,B leaves A at the lower address, so
; pushing D and then CLR ,-S gives [0, high, low] ascending - and a word
; clamped to $0FFF is at most 4095, so the first four of the eight digits
; are always zeros and only the last four are shown.
; ---------------------------------------------------------------------------
p3_show_word
                pshs    a                       ; the position
                ldd     ,x
                pshs    a,b                     ; high byte at the lower
                clr     ,-s                     ; address, zero above both
                leax    ,s
                lbsr    ABI_uint24_to_text
                leas    3,s
                puls    a
                ldx     #text_buffer+4          ; the last four digits
                ldb     #P3_WORD_DIGITS
                lbra    ABI_lcd_write

; ---------------------------------------------------------------------------
; p3_hopram_entry - arm the shared entry field for the selected field
;
;   uses:  A, B, X
; ---------------------------------------------------------------------------
p3_hopram_entry
                clr     >entry_active
                lda     >p3_field
                cmpa    #P3_FIELD_SLOT
                beq     p3_hopram_entry_slot
                cmpa    #P3_FIELD_FREQ
                beq     p3_hopram_entry_wide
                ldb     #P3_WORD_DIGITS
                bra     p3_hopram_entry_armed
p3_hopram_entry_slot
                ldb     #P3_SLOT_DIGITS
                bra     p3_hopram_entry_armed
p3_hopram_entry_wide
                ldb     #TEXT_DIGITS
p3_hopram_entry_armed
                lda     #ENTRY_DECIMAL
                lbra    ABI_entry_begin

; ---------------------------------------------------------------------------
; p3_hopram_key - the raw screen's keys
;
;   entry: B = the key code
;   uses:  A, B, X, Y, U
;
; NEXT and LAST move the slot; f2 cycles the field; digits build a value;
; ENTER stages it and writes the WHOLE slot raw, which is the stock's shape -
; its three commit arms all call store_hop_ram_slot with all four staged
; values, so committing one field re-sends the other two as they stand.
; ---------------------------------------------------------------------------
; ---------------------------------------------------------------------------
; p3_hopram_key - a key on the hop RAM screen, and the re-arm after it
;
;   entry: B = the key code
;   uses:  A, B, X, Y, U
;
; THE CURSOR IS RE-ARMED AFTER EVERY MESSAGE BUT f4. This is the RAM half of
; cowchip_screen_handler ($5914), whose every pass but f4's ($16, at $5A05)
; ends in l5ea4 and the arm of d5e9a at $5EC0 - the FREQ, AMPTD and PHASE
; exceptions belong to the register half only. A digit or ENTER is not a
; message; it moves the display's address after the typed characters
; ($B567), and a commit's own arm follows it. p3_hopram_key_body is the
; handler.
; ---------------------------------------------------------------------------
p3_hopram_key
                pshs    b
                lbsr    p3_hopram_key_body
                puls    b
                ldx     >screen_handler         ; a key that left the screen
                cmpx    #p3_hopram_key          ; arms nothing
                bne     p3_hopram_rearm_none
                lbsr    p3_hopram_cell          ; A = $23AD + $23A4
                lbsr    ABI_entry_key_is_mapped ; a message: l5ea4 re-arms
                lbne    ABI_entry_cursor_on
                lbra    ABI_lcd_cursor          ; a key $B3C2 kept: $B567
p3_hopram_rearm_none
                rts

; ---------------------------------------------------------------------------
; p3_hopram_arm  - the selected field armed: the cursor on its next cell
; p3_hopram_cell - that cell: the field's first column plus the digits typed
;
;   uses:  A
;
; This screen's own four columns, which are not the stock's: its RAM half
; arms d5e9a's [2] at $54, [3] at $5A and [4] at $60 over a different layout.
; The cursor goes where this screen's digits go.
; ---------------------------------------------------------------------------
p3_hopram_arm
                bsr     p3_hopram_cell
                lbra    ABI_entry_cursor_on     ; $AC98, $ACA6
p3_hopram_cell
                lda     >p3_field
                cmpa    #P3_FIELD_SLOT
                beq     p3_hopram_cell_slot
                cmpa    #P3_FIELD_W2
                blo     p3_hopram_cell_w1
                beq     p3_hopram_cell_w2
                lda     #P3_FREQ_POS
                bra     p3_hopram_cell_count
p3_hopram_cell_slot
                lda     #P3_SLOT_POS
                bra     p3_hopram_cell_count
p3_hopram_cell_w1
                lda     #P3_W1_POS
                bra     p3_hopram_cell_count
p3_hopram_cell_w2
                lda     #P3_W2_POS
p3_hopram_cell_count
                adda    >entry_count            ; + $23A4
                rts

; ---------------------------------------------------------------------------
; p3_hopram_key_body - the hop RAM screen's keys, without the re-arm
;
;   entry: B = the key code
;   uses:  A, B, X, Y, U
; ---------------------------------------------------------------------------
p3_hopram_key_body
                ; f4 IS THE WAY OUT. This is the Ram Addr mode of the same
                ; manual cowchip screen, and cowchip_screen_handler ($5914)
                ; leaves on $0016 at l5a05 through request $0003. Without it
                ; the screen had no exit of its own at all.
                cmpb    #KEY_F4
                lbeq    ABI_screen_back
                cmpb    #KEY_F1                 ; the slot BY NUMBER, which is
                bne     p3_hopram_try_next      ; what $5AAD arms
                lda     #P3_FIELD_SLOT
                sta     >p3_field
                lbsr    p3_hopram_entry
                lbra    p3_hopram_show
p3_hopram_try_next
                cmpb    #KEY_NEXT
                bne     p3_hopram_try_last
                lda     >p3_slot
                inca
                anda    #$0F
p3_hopram_slot
                sta     >p3_slot
                lbsr    p3_hopram_entry         ; a new slot is a new entry
                lbra    p3_hopram_show
p3_hopram_try_last
                cmpb    #KEY_LAST
                bne     p3_hopram_try_f2
                lda     >p3_slot
                deca
                anda    #$0F
                bra     p3_hopram_slot
p3_hopram_try_f2
                cmpb    #KEY_F2
                bne     p3_hopram_try_enter
                lda     >p3_field
                inca
                cmpa    #P3_FIELDS
                blo     p3_hopram_field
                clra
p3_hopram_field
                sta     >p3_field
                lbsr    p3_hopram_entry
                lbra    p3_hopram_show
p3_hopram_try_enter
                cmpb    #KEY_ENTER
                lbne    p3_hopram_try_backspace
                lbsr    ABI_entry_cursor_off    ; $B5BA: the terminator, and
                lbsr    p3_hopram_commit        ; request $23 - then l5ea4's arm
                lbra    p3_hopram_arm
p3_hopram_commit
                tst     >entry_active
                beq     p3_hopram_program       ; nothing typed: re-send the
                                                ; slot as it stands, which the
                                                ; stock's commit does with its
                                                ; other two fields every time
                tst     >entry_count            ; every digit taken back by
                beq     p3_hopram_program       ; BACKSPACE is the same case:
                                                ; $CDE1 returns $FF for it and
                                                ; the stock's arms skip
                lda     >p3_field
                cmpa    #P3_FIELD_SLOT
                beq     p3_hopram_enter_slot
                cmpa    #P3_FIELD_FREQ
                beq     p3_hopram_enter_freq

                ; --- a word: parse, clamp to $0FFF, stage ------------------
                lbsr    ABI_entry_value
                bcs     p3_hopram_clamped       ; the stock CLAMPS, never
                lda     >entry_result           ; refuses: atoi5's result
                bne     p3_hopram_clamped       ; goes through the $0FFF
                ldd     >entry_result+1         ; clamp on both words
                cmpd    #P3_WORD_MAX
                bls     p3_hopram_take_word
p3_hopram_clamped
                ldd     #P3_WORD_MAX
p3_hopram_take_word
                ldx     #p3_w1
                tst     >p3_field               ; P3_FIELD_W1 is zero
                beq     p3_hopram_stage
                ldx     #p3_w2
p3_hopram_stage
                std     ,x
                bra     p3_hopram_program

p3_hopram_enter_slot
                ; THE STOCK CLAMPS, IT DOES NOT REFUSE: $5AAD's RAM half ANDs
                ; the converted number with $000F and uses that as the index
                ; into the sixteen records at $2581, so 20 is slot 4 and
                ; nothing is reported. The field goes back to the first word,
                ; which is where an operator wants to be once the slot is
                ; chosen.
                lbsr    ABI_entry_value
                bcs     p3_hopram_slot_taken    ; past 24 bits: the low nibble
                ldb     >entry_result+2         ; of it is still a slot
p3_hopram_slot_taken
                andb    #$0F
                stb     >p3_slot
                clr     >p3_field               ; P3_FIELD_W1
                lbsr    p3_hopram_entry
                lbra    p3_hopram_show

p3_hopram_enter_freq
                lbsr    ABI_entry_value         ; carry: past 24 bits, and a
                bcs     p3_hopram_too_big       ; frequency clamped to $0FFF
                                                ; would be nonsense - refuse
                ldb     >p3_slot
                lbsr    p3_hop_slot_address     ; X = the slot's HOP_FREQ
                ldu     #entry_result
                lbsr    ABI_copy24

p3_hopram_program
                ldd     >p3_w1                  ; the staged codes go to the
                std     >hop_phase              ; sender raw - hop_program_raw
                ldd     >p3_w2                  ; skips the two unit
                std     >hop_ampl               ; conversions
                ldb     >p3_slot
                lbsr    ABI_hop_program_raw
                lbsr    p3_hopram_entry
                lbra    p3_hopram_show

p3_hopram_too_big
                ldb     #ERR_VALUE_TOO_BIG
                lbsr    ABI_error_raise
                lbsr    p3_hopram_entry
                lbra    p3_hopram_show

p3_hopram_try_backspace
                cmpb    #KEY_BACKSPACE
                bne     p3_hopram_try_digit
                ; THE LAST DIGIT OUT AGAIN. entry_backspace ($B2CD, reached
                ; at $B4B9 for key $1F) steps the head $23A4 back and blanks
                ; the vacated cell ($B2E9-$B31F); this screen's entries keep
                ; no sign, so the kind-2 head reset to '+' ($B351-$B35A) has
                ; nothing to act on here. numeric_entry_key_handler repaints
                ; the buffer ($B4D0-$B501) once a key has been accepted
                ; ($B4C4); with nothing to take out (the carry) the glass is
                ; left as it is, which is what $B4CD leaves.
                lbsr    ABI_entry_backspace     ; $B2E9-$B31F, slot 73
                bcs     p3_hopram_done
                lbsr    p3_hopram_show          ; $B4D0-$B501: the values,
                bra     p3_hopram_echo_field    ; then the entry over its
                                                ; field, as after a digit
p3_hopram_done
                rts
p3_hopram_try_digit
                lbsr    ABI_key_digit           ; carry clear: B is a digit
                bcs     p3_hopram_ignore
                lbsr    ABI_entry_digit
                lda     #$01
                sta     >entry_active
                lbsr    p3_hopram_show          ; the stored values, then the
                                                ; typed digits over the
                                                ; selected field
p3_hopram_echo_field
                lda     >p3_field
                cmpa    #P3_FIELD_SLOT          ; THE SLOT ECHOES IN ITS OWN TWO
                beq     p3_hopram_echo_slot     ; columns: 3 is above W2 and fell
                cmpa    #P3_FIELD_W2
                blo     p3_hopram_echo_w1
                beq     p3_hopram_echo_w2
                lda     #P3_FREQ_POS
                ldb     #TEXT_DIGITS
                bra     p3_hopram_echo
p3_hopram_echo_slot
                lda     #P3_SLOT_POS            ; to the FREQ arm, eight columns
                ldb     #P3_SLOT_DIGITS         ; further right
                bra     p3_hopram_echo
p3_hopram_echo_w1
                lda     #P3_W1_POS
                ldb     #P3_WORD_DIGITS
                bra     p3_hopram_echo
p3_hopram_echo_w2
                lda     #P3_W2_POS
                ldb     #P3_WORD_DIGITS
p3_hopram_echo
                pshs    a,b
                ldx     #text_buffer
                lbsr    ABI_entry_render
                puls    a,b
                ldx     #text_buffer
                lbra    ABI_lcd_write_raw       ; the echo: glass only, as
                                                ; lcd_write_string_at ($D8A5)

p3_hopram_ignore
                lbra    ABI_key_refuse

; ---------------------------------------------------------------------------
; p3_hop_slot_address - where a hop slot's frequency bytes live
;
;   entry: B = the slot
;   exit:  X = its three frequency bytes
;   uses:  A, B, X
;
; The same arithmetic as page 0's hop_slot_address, and deliberately its own
; copy: only one page is mapped at a time, so a call across pages cannot
; work - the assembler refuses it. The TABLE is shared, in RAM; only the
; arithmetic is duplicated.
;
; THE STRIDE WAS STALE AND WRONG. This walked the table in steps of 3, from
; when a slot held a frequency alone - while the table has had 8-byte slots
; since the hop screen grew its three fields. For every slot past 0 the
; viewer showed bytes from the middle of OTHER slots. HOP_ENTRY_SIZE is the
; one declaration both pages now read, and the slot's frequency is at
; HOP_FREQ = 0, so no offset is added after the multiply.
; ---------------------------------------------------------------------------
p3_hop_slot_address
                andb    #$0F
                lda     #HOP_ENTRY_SIZE
                mul
                ldx     #hop_table
                leax    d,x
                rts

; ===========================================================================
; opts_open - the Installed Options screen
;
;   uses:  A, B, X, Y, U
;
; Page 3's fourth entry vector, reached from the service menu through
; options_open (service_screens.s). Rebuilt 2026-09-19; docs/options-screen.md
; has the design and why each choice is what it is.
;
; THE LAYOUT IS THE ARCHITECT'S, in his words:
; the star banner with the title centred on line 1, the page's name left and
; its state right on line 2, UP or DOWN acts, NEXT moves on, one page each for
; Option 001, Option 003, All Options Off and Back, no descriptions.
;
; THE CONTENT IS THE ORIGINAL FIRMWARE'S. Every instruction in the five stock
; images that touches installed_options ($3FFC) was read: bit 0 is tested at
; five sites - key_destn ($5FE6), build_option_dispatch_table ($8939, twice),
; enter_channel_config_mode ($528F) and dispatch_ui_event ($5D0C) - and bit 1
; at four - $528F, $5D0C and page 0's l604e. Bits 2 to 7 are tested nowhere, so
; they have no page. build_id_banner ($8000) prints bit 0 as "01" and bit 1 as
; "03", which is where the two names come from.
;
; ALL OPTIONS OFF TAKES A SECOND PRESS. The first puts "press again" at the
; right of line 2 and any other key takes it down. It is the preference logged
; for the architect in his own terms; until he answers, one stray arrow press
; cannot switch both options off.
; ===========================================================================
OPTS_PAGES      equ     4
OPTS_PAGE_ALL   equ     2               ; All Options Off
OPTS_NAME_W     equ     15              ; the widest name, "All Options Off"
OPTS_STATE_POS  equ     LCD_LINE2+37    ; On / Off in the last three columns
OPTS_AGAIN_POS  equ     LCD_LINE2+29    ; "press again", ending at column 39
OPTS_AGAIN_W    equ     11

opts_title      fcc     "*****      INSTALLED OPTIONS       *****"
opts_names      fcc     "Option 001     "
                fcc     "Option 003     "
                fcc     "All Options Off"
                fcc     "Back           "
opts_bit        fcb     $01             ; Option 001 - the banner's "01"
                fcb     $02             ; Option 003 - the banner's "03"
opts_on         fcc     " On"           ; the instrument's own words - "On "
opts_off        fcc     "Off"           ; and "Off" are strings in the stock
                                        ; image (a2u13_page3.bin $3339) -
                                        ; with On set right, flush with Off
opts_again      fcc     "press again"

opts_open
                ldx     #opts_key
                lbsr    ABI_screen_install      ; which stops any walking star
                clr     >opts_page              ; always opens on Option 001
                clr     >opts_armed
                lbsr    ABI_entry_cursor_off    ; no entry on this screen
                lbsr    opts_title_show
                ldx     #opts_title
                lbsr    ABI_banner_arm          ; after the install, which
                                                ; clears it
                lbra    opts_show

opts_title_show
                lda     #LCD_LINE1
                ldx     #opts_title
                ldb     #40
                lbra    ABI_lcd_write

; ---------------------------------------------------------------------------
; opts_show - line 2: this page's name, and its state
;
;   uses:  A, B, X
; ---------------------------------------------------------------------------
opts_show
                lda     #LCD_LINE2
                lbsr    ABI_lcd_blank_line
                ldb     >opts_page
                lda     #OPTS_NAME_W
                mul
                ldx     #opts_names
                leax    d,x
                lda     #LCD_LINE2
                ldb     #OPTS_NAME_W
                lbsr    ABI_lcd_write
                ldb     >opts_page
                cmpb    #OPTS_PAGE_ALL
                blo     opts_show_state         ; an option: On or Off
                bne     opts_show_done          ; Back: nothing to show
                tst     >opts_armed             ; All Options Off: only the
                beq     opts_show_done          ; second-press prompt
                lda     #OPTS_AGAIN_POS
                ldx     #opts_again
                ldb     #OPTS_AGAIN_W
                lbra    ABI_lcd_write
opts_show_state
                ldx     #opts_bit
                lda     b,x
                anda    >installed_options      ; read, never addressed
                beq     opts_show_off
                ldx     #opts_on
                bra     opts_show_put
opts_show_off
                ldx     #opts_off
opts_show_put
                lda     #OPTS_STATE_POS
                ldb     #3
                lbra    ABI_lcd_write
opts_show_done
                rts

; ---------------------------------------------------------------------------
; opts_key - the screen's keys
;
;   entry: B = the key code
;   uses:  A, B, X, Y, U
;
; NEXT and LAST page round in both directions, as the Main Selection Level
; does with its own pages; UP or DOWN acts; f4 leaves, as every service screen
; in this firmware leaves. Anything else is refused, and takes down a waiting
; All Options Off.
; ---------------------------------------------------------------------------
opts_key
                cmpb    #KEY_NEXT
                beq     opts_key_next
                cmpb    #KEY_LAST
                beq     opts_key_last
                cmpb    #KEY_UP
                beq     opts_key_act
                cmpb    #KEY_DOWN
                beq     opts_key_act
                cmpb    #KEY_F4
                lbeq    ABI_screen_back
                cmpb    #KEY_REFRESH
                beq     opts_key_refresh
                tst     >opts_armed             ; A KEY THAT DOES NOTHING HERE
                beq     opts_key_refuse         ; still cancels the second
                clr     >opts_armed             ; press, and says so
                pshs    b
                lbsr    opts_show
                puls    b
opts_key_refuse
                lbra    ABI_key_refuse

opts_key_refresh
                lbsr    opts_title_show
                lbra    opts_show

opts_key_next
                clr     >opts_armed
                lda     >opts_page
                inca
                cmpa    #OPTS_PAGES
                blo     opts_key_page
                clra                            ; past Back: Option 001
                bra     opts_key_page
opts_key_last
                clr     >opts_armed
                lda     >opts_page
                bne     opts_key_last_one
                lda     #OPTS_PAGES             ; before Option 001: Back
opts_key_last_one
                deca
opts_key_page
                sta     >opts_page
                lbra    opts_show

opts_key_act
                ldb     >opts_page
                cmpb    #OPTS_PAGE_ALL
                blo     opts_key_toggle
                lbhi    ABI_screen_back         ; Back
                tst     >opts_armed             ; All Options Off: the first
                bne     opts_key_clear          ; press asks, the second acts
                inc     >opts_armed
                lbra    opts_show
opts_key_clear
                clr     >opts_armed
                lbsr    ABI_options_clear_all   ; the whole byte, as the stock
                                                ; clears it - and the bank copy
                                                ; first, which is what the next
                                                ; boot believes
                lbra    opts_show
opts_key_toggle
                lbsr    ABI_option_toggle       ; B = the page = the bit number:
                                                ; Option 001 is bit 0, Option
                                                ; 003 bit 1. The bank copy
                                                ; first, as option_set and
                                                ; option_clear write it
                lbra    opts_show

; ===========================================================================
; relay_open - the relay exercise
;
;   uses:  A, B, X, Y, U
;
; Page 3's fifth entry vector, reached from the Diagnostics menu through
; diag_relay (service_diag.s). The architect's addition, to his spec of
; 2026-09-18; docs/relay-exercise.md has the design and the reasons.
;
; WHAT IT MOVES: one of two sets, stepped by NEXT and LAST.
;
;   Cycle every relay   bits 0 to 6 of every cycled channel latch - the filter
;                       pair (FLC, K10 and K11), the float relay (K404A), the
;                       output relay and the four attenuator pads. The default.
;   Cycle 48 dB (K8)    bit 6 alone - A3K8, part 0490-1190, the ONLY relay on
;                       the board that is not a reed. Bits 0 to 5 are left
;                       exactly as they were found.
;
; NOT bit 7 in either mode: it is the probe enable for the channel-count read
; and the clock of the reverse-power flip-flop, not a relay, and every write
; masks it out.
;
; WHY TWO SETS. Cycling restores a contact best where there is mechanical wipe,
; and K8 is the only contact here that has any. The reeds are worth cycling -
; they oxidise and pit from their OWN switching, not from room air getting past
; the seal - but a reed has almost no lateral movement, so what it gets is the
; blades striking each other, which shifts a light film and does not undo
; arc pitting. The strongest method, a wetting current through the contacts
; while they cycle, is one this instrument cannot supply at signal levels:
; every cycled channel's level register is zero while it runs, deliberately.
; docs/relay-exercise-what-it-does.md has the whole of it.
;
; HOW FAST: one step every RELAY_STEP_MS, counted in one-millisecond delay_ms
; slices, one per foreground pass, so it can run slower than that and never
; faster.
;
; THE RATE CHANGED ON 2026-09-20 AND THE REASON IS A CHANGE OF INTENT, not a
; correction. It was 1,499 ms - the stock's own power-on relay hold - which
; gave about three seconds a cycle, and the architect at the instrument:
; "that's not exercising it, it should be rapid to knock all the corrosion and
; grime off". The stock's hold is what the instrument uses to SETTLE a relay
; before it trusts the output; wiping wants the fastest rate the relays will
; actually follow, which is a different question.
;
; WHERE 20 MS COMES FROM, and what is not established. The operate and release
; times of the parts fitted - 0490-1608 and 0490-1501 reeds, 0490-1190 for the
; armature K8 - are NOT in this repository: there is no relay data sheet under
; firmware/datasheets and the service manual's parts list gives only ratings.
; So the floor is taken from the best figure that IS here, which is HP's own.
;
; Measured on the stock 2026-09-20, changing channel A's amplitude from 10 V
; to 39 mV with the manual's own key sequence: the firmware sets latch bit 2
; (mute), changes the attenuator bits 11,203 E cycles later, and clears bit 2
; another 11,203 E after that - 6.64 ms at 1,688 E to the millisecond. That
; gap is the time the instrument's designer allows an attenuator relay to
; complete its travel before the output is trusted again, and the 48 dB pad
; K8, the one mechanical relay on the board, is among the relays it covers.
;
; 20 ms is three times that allowance. One state every 20 ms is a full cycle
; every 40 ms, twenty-five cycles a second - a steady buzz, not a click - and
; every relay still has three times the instrument's own settling allowance to
; finish moving. A relay driven faster than it can move does nothing at all,
; which is what the silent boot taught.
;
; WHAT IT MAY NOT DO: leave a relay moved (relay_restore, A2U12, runs on the
; stop key, on f4, and as screen_leave however else the screen is left); hang
; (it works one slice per foreground pass, so every key is answered within a
; millisecond and a pass); drive a signal (every cycled channel's level register
; is zero while it runs, so the output relay closes on nothing).
; ===========================================================================
RELAY_STEP_MS   equ     20              ; 3 x the instrument's own 6.64 ms
                                        ; allowance for an attenuator relay
RELAY_BITS      equ     $7F             ; bits 0-6: the relays. Bit 7 is the
                                        ; probe enable, not a relay
RELAY_BITS_K8   equ     $40             ; bit 6 alone: the 48 dB pad, A3K8,
                                        ; part 0490-1190 and the only relay on
                                        ; the board that is not a reed
RELAY_MODE_ALL  equ     0
RELAY_MODE_K8   equ     1
RELAY_MODES     equ     2
RELAY_STATE_POS equ     LCD_LINE2+28
RELAY_STATE_W   equ     12
RELAY_WHAT_POS  equ     LCD_LINE2       ; the left of line 2 names the set,
RELAY_WHAT_W    equ     18              ; as the Memory Map screen names its
                                        ; element there

relay_title     fcc     "*****        RELAY EXERCISE        *****"
relay_line2     fcc     "                                        "
relay_what_all  fcc     "Cycle every relay "
relay_what_k8   fcc     "Cycle 48 dB (K8)  "
relay_on        fcc     "Status = On "  ; the stock's own words for a toggling
relay_off       fcc     "Status = Off"  ; control: the Special Functions row
                                        ; reads "Status = Off"

relay_open
                ldx     #relay_key
                lbsr    ABI_screen_install      ; runs any previous leave, and
                                                ; clears both hooks
                ldx     #relay_poll
                stx     >screen_poll
                ldx     #ABI_relay_restore      ; always mapped - see screen.s
                stx     >screen_leave
                clr     >relay_running          ; it opens STOPPED: nothing
                clr     >relay_phase            ; moves until a key asks
                clr     >relay_mode             ; and on every relay, which is
                                                ; the default: the set that
                                                ; wants exercising most is the
                                                ; one nobody can hear
                lbsr    ABI_entry_cursor_off    ; no entry on this screen
                lbsr    relay_title_show
                ldx     #relay_title
                lbsr    ABI_banner_arm          ; after the install
                lbra    relay_show

relay_title_show
                lda     #LCD_LINE1
                ldx     #relay_title
                ldb     #40
                lbra    ABI_lcd_write

relay_show
                lda     #LCD_LINE2
                ldx     #relay_line2
                ldb     #40
                lbsr    ABI_lcd_write
                ldx     #relay_what_all         ; WHICH SET, on the left
                tst     >relay_mode
                beq     relay_show_what
                ldx     #relay_what_k8
relay_show_what
                lda     #RELAY_WHAT_POS
                ldb     #RELAY_WHAT_W
                lbsr    ABI_lcd_write
                ldx     #relay_off
                tst     >relay_running
                beq     relay_show_state
                ldx     #relay_on
relay_show_state
                lda     #RELAY_STATE_POS
                ldb     #RELAY_STATE_W
                lbra    ABI_lcd_write

; ---------------------------------------------------------------------------
; relay_mask - the latch bits the current mode cycles
;
;   exit:  A = $7F for every relay, $40 for the 48 dB pad alone
;   uses:  A
; ---------------------------------------------------------------------------
relay_mask
                lda     #RELAY_BITS
                tst     >relay_mode
                beq     relay_mask_done
                lda     #RELAY_BITS_K8
relay_mask_done
                rts

; ---------------------------------------------------------------------------
; relay_key - UP, DOWN or ENTER start and stop it; f4 puts it back and leaves
;
;   entry: B = the key code
; ---------------------------------------------------------------------------
relay_key
                cmpb    #KEY_NEXT               ; THE SELECTION, in the
                beq     relay_key_mode          ; instrument's own idiom:
                cmpb    #KEY_LAST               ; request codes $17 and $18
                beq     relay_key_mode          ; step a choice on a service
                                                ; screen, which is what
                                                ; memmap_select_element ($4FF4)
                                                ; and msg_set_number_base
                                                ; ($6DEB) are stepped by. No
                                                ; new widget: the left of line
                                                ; 2 names the set, exactly as
                                                ; the Memory Map Access screen
                                                ; names its element there
                cmpb    #KEY_UP
                beq     relay_key_toggle
                cmpb    #KEY_DOWN
                beq     relay_key_toggle
                cmpb    #KEY_ENTER
                beq     relay_key_toggle
                cmpb    #KEY_F4
                beq     relay_key_leave
                cmpb    #KEY_REFRESH            ; not a key: no stop
                beq     relay_key_refresh
                ; ANY OTHER KEY STOPS IT - "It must stop on a keypress, not
                ; only on leaving." LOCAL is one of them: it does not leave a
                ; screen on this instrument, it arrives here as
                ; KEY_GONE_LOCAL, and a gate saw the relays keep cycling
                ; behind it before this line. Stopped, the key is refused as
                ; on any other screen.
                tst     >relay_running
                beq     relay_key_refuse
                lbsr    ABI_relay_restore
                lbra    relay_show
relay_key_refuse
                lbra    ABI_key_refuse
relay_key_refresh
                lbsr    relay_title_show
                lbra    relay_show
relay_key_mode
                ; CHANGING THE SET STOPS IT FIRST. Switching what is cycled
                ; under a running exercise would leave the relays of the set
                ; being left behind wherever the last step put them, and the
                ; one promise this screen makes is that everything goes back.
                ; Stopping restores from relay_saved, and the restore is of
                ; the whole byte, so it is right whichever set was running.
                tst     >relay_running
                beq     relay_key_mode_step
                lbsr    ABI_relay_restore
relay_key_mode_step
                lda     >relay_mode
                inca
                cmpa    #RELAY_MODES
                blo     relay_key_mode_store
                clra                            ; NEXT and LAST both step it,
relay_key_mode_store                            ; and with two modes they are
                sta     >relay_mode             ; the same step
                lbra    relay_show
relay_key_leave
                lbsr    ABI_relay_restore       ; everything back first
                lbra    ABI_screen_back
relay_key_toggle
                tst     >relay_running
                beq     relay_key_start
                lbsr    ABI_relay_restore       ; A KEY STOPS IT, mid-step or
                lbra    relay_show              ; not, and puts it all back
relay_key_start
                ; RECORD, THEN SILENCE, THEN RUN. The latch bytes as they
                ; stand now are what every way out puts back; latch_shadow is
                ; the firmware's copy of them, held equal to the hardware by
                ; every write (channel_latch_rmw).
                ldx     #latch_shadow
                ldy     #relay_saved
                ldb     #4
relay_key_record
                lda     ,x+
                sta     ,y+
                decb
                bne     relay_key_record
                bsr     relay_cycled            ; A = the channels it cycles
                clrb
relay_key_mute
                pshs    a,b
                ldx     #$0000                  ; the level register alone, at
                lbsr    ABI_ampl_program        ; zero: B = the channel
                puls    a,b
                incb
                pshs    a
                cmpb    ,s+
                blo     relay_key_mute
                clr     >relay_phase
                ldx     #1                      ; the first step on the next
                stx     >relay_ms               ; pass, so the press is heard
                lda     #$01
                sta     >relay_running
                lbra    relay_show

; ---------------------------------------------------------------------------
; relay_cycled - the channels it cycles: the fitted count, and one when the
;                probe found none (channel 1 always exists - the architect's
;                ruling of 2026-09-18). relay_count in service_diag.s answers
;                the same for the restore; the two read one cell.
;
;   exit:  A = the count
; ---------------------------------------------------------------------------
relay_cycled
                lda     >installed_channels
                bne     relay_cycled_done
                inca
relay_cycled_done
                rts

; ---------------------------------------------------------------------------
; relay_poll - one foreground pass of the exercise
;
; screen_poll's call. Nothing at all while it is stopped. Running, it spends
; one millisecond and counts it; when RELAY_STEP_MS of them have gone it flips
; bits 0-6 of every cycled channel against the recorded byte - all the relays
; together, one click - and starts the next count. It returns every pass, so
; the foreground reads the keypad between any two slices.
; ---------------------------------------------------------------------------
relay_poll
                tst     >relay_running
                beq     relay_poll_done
                ; THE WHOLE STEP IN ONE DELAY, and it used to be one
                ; millisecond per foreground pass with a countdown in
                ; relay_ms. That was right while a step was 1,499 ms - a
                ; blocking wait that long would have made the screen deaf -
                ; and it is wrong now the step is 20: a foreground pass costs
                ; about eight milliseconds of its own, so twenty one-
                ; millisecond slices came to 179 ms and the constant no longer
                ; meant what it said. Measured 2026-09-20, the widest gap
                ; between steps was 302,600 E where 20 ms is 33,760.
                ;
                ; Delaying the step in one call makes the rate exactly the
                ; constant, whatever a pass costs. The screen answers a key
                ; within one step and a pass - 20 ms, where it used to be 1 ms
                ; and a pass - which is still immediate to a hand on the
                ; keypad, and relay_ms is kept as the slice counter for a step
                ; that is ever made long enough to need slicing again.
                ldd     #RELAY_STEP_MS
                lbsr    ABI_delay_ms
                ldx     #RELAY_STEP_MS
                stx     >relay_ms
                com     >relay_phase            ; $00 <-> $FF
                bsr     relay_cycled
                pshs    a                       ; 0,s the count
                clrb
relay_poll_channel
                cmpb    ,s
                bhs     relay_poll_out
                ldx     #relay_saved
                pshs    b
                lbsr    relay_mask              ; A = $7F or $40, by the mode
                puls    b
                pshs    a                       ; 0,s the mask, wanted twice
                anda    >relay_phase
                eora    b,x                     ; the recorded byte, its relay
                inc     >dds_lock               ; bits flipped or not
                sta     >latch_bits
                puls    a                       ; the mask again: bit 7 is
                lbsr    ABI_channel_latch_rmw   ; never written, and in K8
                                                ; mode bits 0-5 are not
                                                ; either - the RMW leaves
                                                ; every bit outside A alone
                dec     >dds_lock
                incb
                bra     relay_poll_channel
relay_poll_out
                leas    1,s
relay_poll_done
                rts
