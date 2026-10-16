; ===========================================================================
; remote_tables.s - the bus command records, read out of the stock's own
; parser tables at $9780-$9A36 (firmware/remote_map.md section 3.3: all 124
; records, 100 terminals, no sampling)
;
; THE RECORD SHAPE IS THE STOCK'S. Its walker ($93EE-$9407) reads offset 0 as
; the character, offset 1 as the type, offsets 2-3 as a pointer and offset 4
; as an argument; a type-0 record is four bytes and descends into the list
; its pointer names, every other record is five bytes. remote.s walks these
; the same way, so a mnemonic that the stock accepts is accepted here letter
; for letter, and one it refuses is refused.
;
; What differs is only WHERE a record points: the stock's handlers post
; request codes into $2217 for its message table; these point at the
; handlers in remote.s that do the same thing to this firmware - the
; comment on each record names the stock's handler and its request code so
; the correspondence can be checked one row at a time.
; ===========================================================================

RT_LIST         equ     $00             ; descend into the sub-list
RT_NOW          equ     $01             ; call the handler at once
RT_DIGIT        equ     $02             ; park; call with the next digit in B

; The records are written out as plain fcb/fdb lines rather than through
; macros. Both assemblers have macros, but a label written on the same line
; as a macro invocation was defined by lwasm and left undefined by
; asm6809.py ('undefined symbol rmt_list_empty'), and the two must agree
; byte for byte - so the expansion is on the page where both read it the
; same way. The shape of every record is stated at the top of this file.


; ---------------------------------------------------------------------------
; The 26-way first-letter table, the stock's command_dispatch_az ($9780).
; C, J, X, Y and Z point at an empty list - a syntax error on the second
; character, as the stock's $97B4 record does.
; ---------------------------------------------------------------------------
remote_dispatch_az
                fdb     rmt_list_a        ; A
                fdb     rmt_list_b        ; B
                fdb     rmt_list_empty    ; C
                fdb     rmt_list_d        ; D
                fdb     rmt_list_e        ; E
                fdb     rmt_list_f        ; F
                fdb     rmt_list_g        ; G
                fdb     rmt_list_h        ; H
                fdb     rmt_list_i        ; I
                fdb     rmt_list_empty    ; J
                fdb     rmt_list_k        ; K
                fdb     rmt_list_l        ; L
                fdb     rmt_list_m        ; M
                fdb     rmt_list_n        ; N
                fdb     rmt_list_o        ; O
                fdb     rmt_list_p        ; P
                fdb     rmt_list_q        ; Q
                fdb     rmt_list_r        ; R
                fdb     rmt_list_s        ; S
                fdb     rmt_list_t        ; T
                fdb     rmt_list_u        ; U
                fdb     rmt_list_v        ; V
                fdb     rmt_list_w        ; W
                fdb     rmt_list_empty    ; X
                fdb     rmt_list_empty    ; Y
                fdb     rmt_list_empty    ; Z
rmt_list_empty  fcb     $00

; --- A: AM AU AHR APA-APD APH ---------------------------------------------
rmt_list_a
                fcb     'M',RT_NOW        ; AM  mode $07
                fdb     remote_mode_code
                fcb     LBL_AM
                fcb     'U',RT_NOW        ; AU  mode $14, into
                fdb     remote_mode_code
                fcb     $14
                                                              ; FS's field (kind 7) 
                fcb     'H',RT_LIST
                fdb     rmt_list_ah
                fcb     'P',RT_LIST
                fdb     rmt_list_ap
                fcb     $00
rmt_list_ah
                fcb     'R',RT_NOW        ; AHR $2B, $2219=2
                fdb     remote_cmd_rate
                fcb     2
                fcb     $00
rmt_list_ap
                fcb     'A',RT_NOW        ; APA chq $1A ch 0
                fdb     remote_sel_ampl
                fcb     0
                fcb     'B',RT_NOW        ; APB
                fdb     remote_sel_ampl
                fcb     1
                fcb     'C',RT_NOW        ; APC
                fdb     remote_sel_ampl
                fcb     2
                fcb     'D',RT_NOW        ; APD
                fdb     remote_sel_ampl
                fcb     3
                fcb     'H',RT_NOW        ; APH chq $29
                fdb     remote_sel_hopampl
                fcb     0
                fcb     $00

; --- B: BP BO BF BSB BSO BSH ----------------------------------------------
rmt_list_b
                fcb     'P',RT_NOW        ; BP  ptm beep
                fdb     remote_cmd_bp
                fcb     0
                fcb     'O',RT_NOW        ; BO  backlight on
                fdb     remote_cmd_bo
                fcb     0
                fcb     'F',RT_NOW        ; BF  backlight off
                fdb     remote_cmd_bf
                fcb     0
                fcb     'S',RT_LIST
                fdb     rmt_list_bs
                fcb     $00
rmt_list_bs
                fcb     'B',RT_NOW        ; BSB post $39
                fdb     remote_to_screen
                fcb     $39
                fcb     'O',RT_NOW        ; BSO post $3A
                fdb     remote_to_screen
                fcb     $3A
                fcb     'H',RT_NOW        ; BSH post $3B
                fdb     remote_to_screen
                fcb     $3B
                fcb     $00

; --- D: DN DG DC DS DEA-DED DPE DAPH DAPL ---------------------------------
rmt_list_d
                fcb     'N',RT_NOW        ; DN  post $1F = key 25
                fdb     remote_as_key
                fcb     KEY_DOWN
                fcb     'G',RT_NOW        ; DG  unit 3
                fdb     remote_unit_code
                fcb     UNIT_DEG
                fcb     'C',RT_NOW        ; DC  mode $04
                fdb     remote_mode_code
                fcb     LBL_DC
                fcb     'S',RT_NOW        ; DS  mode $0A
                fdb     remote_mode_code
                fcb     LBL_DSB
                fcb     'E',RT_LIST
                fdb     rmt_list_de
                fcb     'P',RT_LIST
                fdb     rmt_list_dp
                fcb     'A',RT_LIST
                fdb     rmt_list_da
                fcb     $00
rmt_list_de
                fcb     'A',RT_NOW        ; DEA chq $1D ch 0
                fdb     remote_sel_dest
                fcb     0
                fcb     'B',RT_NOW        ; DEB
                fdb     remote_sel_dest
                fcb     1
                fcb     'C',RT_NOW        ; DEC
                fdb     remote_sel_dest
                fcb     2
                fcb     'D',RT_NOW        ; DED
                fdb     remote_sel_dest
                fcb     3
                fcb     $00
rmt_list_dp
                fcb     'E',RT_NOW        ; DPE $2B, $2219=0
                fdb     remote_cmd_rate
                fcb     0
                fcb     $00
rmt_list_da
                fcb     'P',RT_LIST
                fdb     rmt_list_dap
                fcb     $00
rmt_list_dap
                fcb     'H',RT_NOW        ; DAPH chq $1A arg 0
                fdb     remote_sel_ampl
                fcb     0
                fcb     'L',RT_NOW        ; DAPL chq $1A arg 1
                fdb     remote_sel_ampl
                fcb     1
                fcb     $00

; --- E: EM EO ET ----------------------------------------------------------
rmt_list_e
                fcb     'M',RT_NOW        ; EM  post $0B
                fdb     remote_cmd_em
                fcb     0
                fcb     'O',RT_NOW        ; EO  ext-ref query
                fdb     remote_cmd_eo
                fcb     0
                fcb     'T',RT_NOW        ; ET  unit 8
                fdb     remote_unit_code
                fcb     8
                fcb     $00

; --- F: FC FS FM FHR FRA-FRD FRH ------------------------------------------
rmt_list_f
                fcb     'C',RT_DIGIT        ; FC n post $12
                fdb     remote_cmd_fc
                fcb     0
                fcb     'S',RT_DIGIT        ; FS n post $0C
                fdb     remote_cmd_fs
                fcb     0
                fcb     'M',RT_NOW        ; FM  mode $08
                fdb     remote_mode_code
                fcb     LBL_FM
                fcb     'H',RT_LIST
                fdb     rmt_list_fh
                fcb     'R',RT_LIST
                fdb     rmt_list_fr
                fcb     $00
rmt_list_fh
                fcb     'R',RT_NOW        ; FHR $2B, $2219=1
                fdb     remote_cmd_rate
                fcb     1
                fcb     $00
rmt_list_fr
                fcb     'A',RT_NOW        ; FRA chq $19 ch 0
                fdb     remote_sel_freq
                fcb     0
                fcb     'B',RT_NOW        ; FRB
                fdb     remote_sel_freq
                fcb     1
                fcb     'C',RT_NOW        ; FRC
                fdb     remote_sel_freq
                fcb     2
                fcb     'D',RT_NOW        ; FRD
                fdb     remote_sel_freq
                fcb     3
                fcb     'H',RT_NOW        ; FRH chq $28
                fdb     remote_sel_hopfreq
                fcb     0
                fcb     $00

; --- G: GM ----------------------------------------------------------------
rmt_list_g
                fcb     'M',RT_DIGIT        ; GM n post $0A
                fdb     remote_cmd_gm
                fcb     0
                fcb     $00

; --- H: HP HZ HRA ---------------------------------------------------------
rmt_list_h
                fcb     'P',RT_NOW        ; HP  last error
                fdb     remote_cmd_hp
                fcb     0
                fcb     'Z',RT_NOW        ; HZ  unit 2
                fdb     remote_unit_code
                fcb     UNIT_HZ
                fcb     'R',RT_LIST
                fdb     rmt_list_hr
                fcb     $00
rmt_list_hr
                fcb     'A',RT_NOW        ; HRA post $27
                fdb     remote_to_screen
                fcb     $27
                fcb     $00

; --- I: ID IS -------------------------------------------------------------
rmt_list_i
                fcb     'D',RT_NOW        ; ID  the banner
                fdb     remote_cmd_id
                fcb     0
                fcb     'S',RT_NOW        ; IS  post $1E = key 13
                fdb     remote_as_key
                fcb     KEY_INC_SET
                fcb     $00

; --- K: KZ ----------------------------------------------------------------
rmt_list_k
                fcb     'Z',RT_NOW        ; KZ  unit 1
                fdb     remote_unit_code
                fcb     UNIT_KHZ
                fcb     $00

; --- L: LO ----------------------------------------------------------------
rmt_list_l
                fcb     'O',RT_NOW        ; LO  mode $13, into
                fdb     remote_mode_code
                fcb     $13
                fcb     $00                        ; FS's field (kind 7) 

; --- M: MV MS -------------------------------------------------------------
rmt_list_m
                fcb     'V',RT_NOW        ; MV  unit 6
                fdb     remote_unit_code
                fcb     UNIT_MILLIVOLT
                fcb     'S',RT_NOW        ; MS  unit $0A
                fdb     remote_unit_code
                fcb     10
                fcb     $00

; --- N: NS ----------------------------------------------------------------
rmt_list_n
                fcb     'S',RT_NOW        ; NS  mode $05
                fdb     remote_mode_code
                fcb     LBL_NOISE
                fcb     $00

; --- O: OO OF ON OC -------------------------------------------------------
rmt_list_o
                fcb     'O',RT_DIGIT        ; OO n post $0F
                fdb     remote_cmd_oo
                fcb     0
                fcb     'F',RT_NOW        ; OF  mode $10
                fdb     remote_mode_code
                fcb     LBL_OFF
                fcb     'N',RT_NOW        ; ON  mode $11
                fdb     remote_mode_code
                fcb     LBL_ON
                fcb     'C',RT_DIGIT        ; OC n mode $0C-$0F
                fdb     remote_cmd_oc
                fcb     0
                fcb     $00

; --- P: PR PS PC PM PU PHA-PHD PHH PHR ------------------------------------
rmt_list_p
                fcb     'R',RT_NOW        ; PR  post $11
                fdb     remote_cmd_pr
                fcb     0
                fcb     'S',RT_NOW        ; PS  post $07
                fdb     remote_cmd_ps
                fcb     0
                fcb     'C',RT_NOW        ; PC  unit $0B
                fdb     remote_unit_code
                fcb     UNIT_PERCENT
                fcb     'M',RT_NOW        ; PM  mode $09
                fdb     remote_mode_code
                fcb     LBL_PHIM
                fcb     'U',RT_NOW        ; PU  mode $0B
                fdb     remote_mode_code
                fcb     LBL_PULSE
                fcb     'H',RT_LIST
                fdb     rmt_list_ph
                fcb     $00
rmt_list_ph
                fcb     'A',RT_NOW        ; PHA chq $1C ch 0
                fdb     remote_sel_phase
                fcb     0
                fcb     'B',RT_NOW        ; PHB
                fdb     remote_sel_phase
                fcb     1
                fcb     'C',RT_NOW        ; PHC
                fdb     remote_sel_phase
                fcb     2
                fcb     'D',RT_NOW        ; PHD
                fdb     remote_sel_phase
                fcb     3
                fcb     'H',RT_NOW        ; PHH chq $2A
                fdb     remote_sel_hopphase
                fcb     0
                fcb     'R',RT_NOW        ; PHR $2B, $2219=3
                fdb     remote_cmd_rate
                fcb     3
                fcb     $00

; --- Q: QRE ---------------------------------------------------------------
rmt_list_q
                fcb     'R',RT_LIST
                fdb     rmt_list_qr
                fcb     $00
rmt_list_qr
                fcb     'E',RT_NOW        ; QRE post $36
                fdb     remote_to_screen
                fcb     $36
                fcb     $00

; --- R: RM RP RC RD RA RUNC RUNM RUNS RSF ---------------------------------
rmt_list_r
                fcb     'M',RT_NOW        ; RM  SRQ mask query
                fdb     remote_cmd_rm
                fcb     0
                fcb     'P',RT_NOW        ; RP  post $08
                fdb     remote_cmd_rp
                fcb     0
                fcb     'C',RT_NOW        ; RC  post $22: the NEXT number
                fdb     remote_cmd_rc     ; is the register to recall - see
                fcb     0                 ; remote_cmd_rc
                fcb     'D',RT_NOW        ; RD  unit 4
                fdb     remote_unit_code
                fcb     UNIT_RAD
                fcb     'A',RT_NOW        ; RA  mode $02
                fdb     remote_mode_code
                fcb     LBL_RAMP
                fcb     'U',RT_LIST
                fdb     rmt_list_ru
                fcb     'S',RT_LIST
                fdb     rmt_list_rs
                fcb     $00
rmt_list_ru
                fcb     'N',RT_LIST
                fdb     rmt_list_run
                fcb     $00
rmt_list_run
                fcb     'C',RT_NOW        ; RUNC post $2D
                fdb     remote_to_screen
                fcb     $2D
                fcb     'M',RT_NOW        ; RUNM post $2F
                fdb     remote_to_screen
                fcb     $2F
                fcb     'S',RT_NOW        ; RUNS post $2E
                fdb     remote_to_screen
                fcb     $2E
                fcb     $00
rmt_list_rs
                fcb     'F',RT_NOW        ; RSF
                fdb     remote_cmd_rsf
                fcb     0
                fcb     $00

; --- S: SF SM SV SC SI SQ SH SEQP SEQE SBP ST_ID STOP STON STOF -----------
rmt_list_s
                fcb     'F',RT_NOW        ; SF  post $05 = key 46
                fdb     remote_as_key
                fcb     KEY_S_LAST
                fcb     'M',RT_NOW        ; SM  post $0E
                fdb     remote_cmd_sm
                fcb     0
                fcb     'V',RT_NOW        ; SV  post $21: the NEXT number
                fdb     remote_cmd_sv     ; is the register to save into -
                fcb     0                 ; see remote_cmd_sv
                fcb     'C',RT_NOW        ; SC  unit 9
                fdb     remote_unit_code
                fcb     9
                fcb     'I',RT_NOW        ; SI  mode $01
                fdb     remote_mode_code
                fcb     LBL_SINE
                fcb     'Q',RT_NOW        ; SQ  mode $06
                fdb     remote_mode_code
                fcb     LBL_SQUARE
                fcb     'H',RT_NOW        ; SH  mode $12, into
                fdb     remote_mode_code
                fcb     $12
                                                              ; FS's field (kind 7) 
                fcb     'E',RT_LIST
                fdb     rmt_list_se
                fcb     'B',RT_LIST
                fdb     rmt_list_sb
                fcb     'T',RT_LIST
                fdb     rmt_list_st
                fcb     $00
rmt_list_se
                fcb     'Q',RT_LIST
                fdb     rmt_list_seq
                fcb     $00
rmt_list_seq
                fcb     'P',RT_NOW        ; SEQP post $33
                fdb     remote_to_screen
                fcb     $33
                fcb     'E',RT_NOW        ; SEQE post $34
                fdb     remote_to_screen
                fcb     $34
                fcb     $00
rmt_list_sb
                fcb     'P',RT_NOW        ; SBP  post $31
                fdb     remote_to_screen
                fcb     $31
                fcb     $00
rmt_list_st
                fcb     'O',RT_LIST
                fdb     rmt_list_sto
                fcb     $5F,RT_LIST
                fdb     rmt_list_st_
                fcb     $00
rmt_list_sto
                fcb     'P',RT_NOW        ; STOP post $30
                fdb     remote_to_screen
                fcb     $30
                fcb     'N',RT_NOW        ; STON post $31
                fdb     remote_to_screen
                fcb     $31
                fcb     'F',RT_NOW        ; STOF post $32
                fdb     remote_to_screen
                fcb     $32
                fcb     $00
rmt_list_st_
                fcb     'I',RT_LIST
                fdb     rmt_list_st_i
                fcb     'O',RT_LIST                     ; ST_OP - the owner's
                fdb     rmt_list_st_o                   ; addition, not HP's
                fcb     $00
rmt_list_st_i
                fcb     'D',RT_NOW        ; ST_ID
                fdb     remote_cmd_stid
                fcb     0
rmt_list_st_o
                fcb     'P',RT_NOW        ; ST_OP: options from the bus
                fdb     remote_cmd_stop
                fcb     0
                fcb     $00

; --- T: TR ----------------------------------------------------------------
rmt_list_t
                fcb     'R',RT_NOW        ; TR  mode $03
                fdb     remote_mode_code
                fcb     LBL_TRIANGLE
                fcb     $00

; --- U: UP UV -------------------------------------------------------------
rmt_list_u
                fcb     'P',RT_NOW        ; UP  post $20 = key 19
                fdb     remote_as_key
                fcb     KEY_UP
                fcb     'V',RT_NOW        ; UV  unit 7
                fdb     remote_unit_code
                fcb     UNIT_MICROVOLT
                fcb     $00

; --- V: VL ----------------------------------------------------------------
rmt_list_v
                fcb     'L',RT_NOW        ; VL  unit 5
                fdb     remote_unit_code
                fcb     UNIT_VOLT
                fcb     $00

; --- W: WSQ WFA-WFD -------------------------------------------------------
rmt_list_w
                fcb     'S',RT_LIST
                fdb     rmt_list_ws
                fcb     'F',RT_LIST
                fdb     rmt_list_wf
                fcb     $00
rmt_list_ws
                fcb     'Q',RT_NOW        ; WSQ post $2C: sequence data follows
                fdb     remote_cmd_wsq
                fcb     $2C
                fcb     $00
rmt_list_wf
                fcb     'A',RT_NOW        ; WFA chq $1B ch 0
                fdb     remote_sel_wave
                fcb     0
                fcb     'B',RT_NOW        ; WFB
                fdb     remote_sel_wave
                fcb     1
                fcb     'C',RT_NOW        ; WFC
                fdb     remote_sel_wave
                fcb     2
                fcb     'D',RT_NOW        ; WFD
                fdb     remote_sel_wave
                fcb     3
                fcb     $00

; --- the four non-letter commands: > < % ? ($9A22) ------------------------
remote_list_symbols
                fcb     $3E,RT_NOW        ; post $17 = key 20
                fdb     remote_as_key
                fcb     KEY_NEXT
                fcb     $3C,RT_NOW        ; post $18 = key 14
                fdb     remote_as_key
                fcb     KEY_LAST
                fcb     $25,RT_NOW        ; unit $0B, as PC
                fdb     remote_unit_code
                fcb     UNIT_PERCENT
                fcb     $3F,RT_NOW        ; post $25: the query
                fdb     remote_cmd_query
                fcb     0
                fcb     $00



; ---------------------------------------------------------------------------
; menu_draw_second_row - the entry after the selected one, on line 2
;
;   uses:  A, B, X
;
; A menu with no heading uses both rows: the selection on line 1 and whatever
; follows it on line 2. For the Installed Options screen that puts each
; option's continuation directly under its label, which is what the
; continuation strings were written for.
;
; The list wraps, so the row after the last entry is the first one - the same
; rule menu_next already follows, and it costs less than clearing the row.
; ---------------------------------------------------------------------------
menu_draw_second_row
                ldx     >menu_title
                bne     menu_second_done
                ldb     >menu_index
                incb
                cmpb    >menu_count
                blo     menu_second_have
                clrb
menu_second_have
                ldx     >menu_table
menu_second_step
                tstb
                beq     menu_second_show
                pshs    b
                ldb     #SVC_ENTRY_SIZE
                abx
                puls    b
                decb
                bra     menu_second_step
menu_second_show
                lda     #MENU_ENTRY_LINE
                ldb     #SVC_LABEL_LEN
                lbra    lcd_write
menu_second_done
                rts

; ===========================================================================
; AND ONE CHANNEL ROUTINE, ABOVE THE TABLE FOR SPACE - the same reason
; menu_draw_second_row is here. channel_latches_preset belongs beside the rest
; of channel.s and would not fit: the core had fourteen bytes of margin under
; ABI_BASE and this is thirty, so adding it there overflowed the fill with
; "Invalid fill length". It is reached by lbsr from boot.s, which spans the
; whole image, and it names nothing that has to be assembled before it.
; ===========================================================================

; ---------------------------------------------------------------------------
; channel_latches_preset - output_latches_preset84 ($B81E), ported
;
;   uses:  A, B, X
;
; WHY THIS EXISTS AND WHY IT RUNS WHERE IT DOES. The architect heard no relay
; clicks at power-on. Measured from reset on both machines at 50-instruction
; resolution: the STOCK drives all four output relays OFF at ~44,350
; instructions and does not release them until ~685,950 - held open for
; 641,450 instructions, the whole of its power-on self-test. This firmware
; wrote its first latch value at ~582,150 and released it at ~589,800, a gap of
; 7,500. The relays were being commanded off and back on eighty-five times
; faster than the instrument does it, which is not long enough for an armature
; to move: the write is undone before the relay answers it.
;
; The gap is not a delay to insert. It is STRUCTURAL - the stock mutes the
; outputs at its channel probe, runs its self-test, and releases them after -
; and that is what is ported.
;
; IT IS ITS OWN ROUTINE, as the stock's is: output_latches_preset84 is a
; separate routine from count_installed_channels and carries no state. Since
; 2026-09-19 boot.s calls the two in the stock's order - channel_probe at the
; top of reset_entry, this straight after it - with the count carried across
; the scratch clears in the boot frame.
;
; THE VALUE IS THE STOCK'S, $84. $B826-$B84A calls port_latch_rmw(channel,
; mask $FF, value $0084) for channels 0 to 3 and writes the strobe once at
; $B84C. Bit 2 is the output relay, active low, so $84 is every output OFF;
; bit 7 is the probe enable, which the stock leaves set here and
; channel_latches_bit7_clear ($B646) takes down later, at $831C - this
; firmware's channel_latch_init, which writes LATCH_PRESET over it.
;
; It was $04 until the probe moved. With the preset running BEFORE the probe,
; $84 would have left the probe enable asserted on all four latches while the
; probe asserted it one channel at a time, so bit 7 was left out. The probe
; now runs first, as the stock's does, and that reason is gone.
LATCH_PRESET84  equ     LATCH_OUTPUT+CHANNEL_PROBE      ; $84
; AND THE RELEASE KEEPS BIT 7, NOT BIT 2 - corrected 2026-09-20 from the
; instrument. Measured per channel from reset, the distinct latch values are
;
;   stock    $80  $00  $84  $80  $00
;   this     $80  $00  $84  $04  $00     <- the fourth was the wrong one
;
; so the stock's third phase clears the OUTPUT RELAY and leaves the probe
; enable standing, and this cleared the probe enable and left the relay
; closed. The two are not interchangeable: bit 7 is not a relay, it is the
; CLOCK into A3 U2B (A2 U38 pin 19 to A3 U2 pin 11, Table 8-2), the
; reverse-power flip-flop whose D comes from A2 U24 pin 15 and whose output
; opens K402 and turns on Q33 - the bit the controller reads to print
; "Reverse Power Relay Tripped". A clock is an edge, so the question is what
; the flip-flop samples at that edge, and the instrument takes it 24 ms AFTER
; the output relay has released where this took it with the relay still
; closed.
LATCH_PRESET    equ     CHANNEL_PROBE

channel_latches_preset
                clrb
channel_latches_preset_next
                lda     #$FF                    ; this call owns every bit, as
                                                ; the stock's mask $FF does
                pshs    b
                ldb     #LATCH_PRESET84
                inc     >dds_lock               ; THE STORE AND THE CALL ARE
                                                ; ONE OPERATION, as everywhere
                                                ; else that stages latch_bits
                stb     >latch_bits
                puls    b
                lbsr    channel_latch_rmw
                dec     >dds_lock
                incb
                cmpb    #CHANNEL_MAX
                blo     channel_latches_preset_next
                ; AND THE STROBE ONCE, AFTER THE LOOP - the stock's
                ; `clr >output_latch_strobe` at $B84C. Every one of its
                ; whole-array latch passes ends that way.
                clr     >output_latch_strobe
                rts

; ===========================================================================
; AND channel_valid, above the table for space as well - every output screen
; and every bus command reaches it by lbsr or through its ABI slot, so where
; it sits costs nothing, and the core had no room left for the architect's
; channel-1 floor.
; ===========================================================================

; ---------------------------------------------------------------------------
; channel_valid - does this channel exist on this instrument?
;
;   entry: B = the channel number
;   exit:  carry CLEAR if it is fitted, SET if it is not
;   uses:  A
;
; Every screen that takes a channel number goes through here. The alternative
; is each screen checking for itself, which is how one of them ends up not
; checking.
; ---------------------------------------------------------------------------
channel_valid
                ; CHANNEL 0 IS ALWAYS VALID - the architect's ruling of
                ; 2026-09-18, in his words:
                ; "channel 1 always exists. A bare 8904A with no options has
                ; one output - that is the base configuration.
                ; installed_channels can never legitimately be 0, and refusing
                ; '1' is wrong whatever the probe returned."
                ;
                ; It is NOT the stock's behaviour and is not dressed up as it.
                ; count_installed_channels ($B852) clears $23B2 and increments
                ; only for a channel whose int_latch bit reads zero, so an
                ; absent channel 0 leaves its count at zero and its own screens
                ; then refuse every output number.
                ;
                ; WHAT IT COSTS IF THE PROBE IS RIGHT AND THE BOARD IS ABSENT:
                ; the operator can select output 1 on an instrument that has
                ; none, and the latch write goes to a socket with nothing in
                ; it. WHAT IT SAVES IF THE PROBE IS WRONG: an instrument that
                ; refuses every key on every output screen and cannot be used
                ; at all, which is what the architect had on the bench.
                tstb
                beq     channel_valid_yes
                cmpb    >installed_channels
                blo     channel_valid_yes
                orcc    #CC_CARRY
                rts
channel_valid_yes
                andcc   #~CC_CARRY
                rts

; ---------------------------------------------------------------------------
; special_screen_open - the Special Functions screen, as $726D opens it
;
;   uses:  A, B, X, Y, U
;
; Here rather than beside the rest of the screen in modules/screens_main.s
; because the core had no room left under ABI_BASE. It is reached by lbra
; from main_menu.s and names nothing assembled after it.
; ---------------------------------------------------------------------------
special_screen_open
                clr     >special_number         ; the instrument opens on # 0
                clr     >special_field          ; with the number field armed
                ldx     #special_key
                lbsr    screen_install
                lda     #1                      ; EVERY SHIFTED KEY COMES HERE:
                sta     >screen_takes_shift     ; $7320 stores the screen's own
                                                ; hook, $6A25, in $220D - see
                                                ; boot.s foreground_shifted
                lbsr    special_show
                lbra    special_arm             ; $731B: armed as it opens, local

; ---------------------------------------------------------------------------
; special_key_shifted - a shifted key on the Special Functions screen
;
;   entry: B = the key, KEY_S_FREQ or above
;
; What special_function_screen_handler ($6A25) does with a request while it
; is the $220D hook, driven on the stock from its Special Functions screen:
;
;   $0010, shift INC SET  show_last_error_screen ($C418), the three-second
;                         flash, and the screen comes back
;   $0026, shift ENTER    the Main Selection Level, with the special functions
;                         KEPT - $23C1 read $0008 before and after
;   every other one       nothing at all: the screen stays and $23DE is left
;                         alone, so there is no beep. The same run raised $0F
;                         for DOWN on the Main Selection, so a beep would have
;                         shown. shift f3's phase reset is among these.
;
; A code above the shifted half is not a key this screen knows, and gets
; key_refuse as every unknown key on it does.
; ---------------------------------------------------------------------------
special_key_shifted
                cmpb    #KEY_S_INC_SET
                lbeq    error_show
                cmpb    #KEY_S_ENTER
                lbeq    main_menu_open          ; the non-resetting return, as
                                                ; state_return_to_main_menu
                                                ; ($8E22) is
                lbhi    key_refuse
                rts                             ; the rest: stays, in silence

; ---------------------------------------------------------------------------
; panel_ports_reset - reset_panel_ports ($D524), ported
;
;   uses:  A
;
; The stock's first hardware act at power-on after the RAM signature check:
; status_leds_all_off ($9A37) writes $3F to the status/control port $0900 and
; its shadow, then $0600 (the digital port), the keypad column shadow $241F
; and the column drive $0A00 are cleared, and the row port $0000 is read.
; power_on_init discards what the read returns. Here, in the tail after the
; ABI table, for want of room in the core.
; ---------------------------------------------------------------------------
panel_ports_reset
                lbsr    led_init                ; $9A37: $3F to $0900 and its
                                                ; shadow
                clr     >digital_in             ; then the three clears
                clr     >kbd_col_shadow         ; the shadow first, as
                clr     >kbd_cols               ; everywhere it is written
                lda     >kbd_rows               ; and the read, not used
                rts
