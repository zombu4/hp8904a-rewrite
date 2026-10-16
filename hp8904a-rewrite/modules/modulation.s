; ===========================================================================
; modulation.s - routing a channel to modulate Channel A
;
; THERE IS EXACTLY ONE MODULATION TARGET, and it is Channel A. Nothing in the
; firmware names the modulated channel because it never varies: a channel is
; made a MODULATOR by setting its own destination to one of the five
; modulation codes, and what it modulates is always channel 0.
;
; The instrument says so in its own words. Error $65 in the stock message
; table (a2u13_page3 $77D6, 33 bytes) reads:
;
;     Channel A can not modulate itself
;
; and set_channel_destination ($78BF, page0) raises it at $78EF when the
; channel being given a modulation destination IS channel 0. So channel 0 is
; Channel A, and a modulation destination means "modulate Channel A".
;
; This file previously did not exist, and destn_apply refused EVERY
; modulation destination on the grounds that nothing established which
; channel was modulated. That was wrong twice: the routing is established,
; and the answer was in the ROM's own error string.
;
; THE ROUTING IS ONE REGISTER PER MODULATION TYPE, holding the source
; channel. Established from route_source_selector ($C7B0), which funnels
; every routing write into dds_mode_param_set ($E69C), which switches on the
; destination code:
;
;   destination      register   value
;   AM      (7)      $19        source channel + $0C
;   FM      (8)      $1A        source channel + $0C
;   PhiM    (9)      $17        source channel + $0C
;   DSB     ($0A)    $19        source channel + $0C + $20
;   Pulse   ($0B)    $18        source channel + $0C
;   disconnected     as above   0
;
; DSB SHARES AM'S REGISTER and is distinguished by bit 5 of the value. That
; is why both codes reach the same arm at $E6AF in the stock switch.
;
; THE BIAS OF $0C IS NOT ARBITRARY: $0C to $0F are the port codes for Out1 to
; Out4, so a source is named by the same code space the output mux uses. A
; value of 0 means nothing is routed there.
;
; All four registers are width code 1 in the descriptor table at $DD73 - one
; 6-bit field - so each is a single staged write followed by its latch. The
; largest value used is $2F, which fits.
; ===========================================================================

MOD_SOURCE_BIAS equ     $0C             ; the source channel is biased by the
                                        ; port-code base, so a modulator is
                                        ; named the same way an output is
MOD_DSB_FLAG    equ     $20             ; DSB shares AM's register, set apart
                                        ; by this bit
MOD_DISCONNECT  equ     $00             ; nothing routed

DDS_MOD_PHIM    equ     $17             ; the four source-select registers
DDS_MOD_PULSE   equ     $18
DDS_MOD_AM      equ     $19             ; AM and DSB both
DDS_MOD_FM      equ     $1A

; ---------------------------------------------------------------------------
; mod_register - which source-select register a destination uses
;
;   entry: B = the destination code
;   exit:  B = the register id; carry SET if the code is not a modulation one
;   uses:  A, B
;
; A table would need five entries with four distinct values and a hole at the
; codes below seven; four comparisons are shorter and say which is which.
; ---------------------------------------------------------------------------
mod_register
                cmpb    #LBL_AM
                beq     mod_register_am
                cmpb    #LBL_DSB                ; DSB shares AM's register
                beq     mod_register_am
                cmpb    #LBL_FM
                beq     mod_register_fm
                cmpb    #LBL_PHIM
                beq     mod_register_phim
                cmpb    #LBL_PULSE
                beq     mod_register_pulse
                orcc    #CC_CARRY               ; not a modulation code
                rts
mod_register_am
                ldb     #DDS_MOD_AM
                bra     mod_register_done
mod_register_fm
                ldb     #DDS_MOD_FM
                bra     mod_register_done
mod_register_phim
                ldb     #DDS_MOD_PHIM
                bra     mod_register_done
mod_register_pulse
                ldb     #DDS_MOD_PULSE
mod_register_done
                andcc   #~CC_CARRY
                rts

; ---------------------------------------------------------------------------
; mod_program - the source-select register write route_source_selector makes
;
;   entry: A = the node, 0 to 3, or PORT_NONE (4) and above to disconnect
;          B = the destination code
;   exit:  carry CLEAR and the register is written; carry SET and nothing
;          written when the code is not a modulation one
;   uses:  A, B, X, Y
;
; route_source_selector ($C7B0) turns its value into the pair (value,
; value+$0C) when the value is below 4 ($C7E0-$C7ED) and into (4, 0) from 4
; to $0E ($C7CC-$C7DE); for a code port_code_to_channel ($C765) does not
; know - every code but Out1-Out4 - it hands the second half of the pair to
; dds_mode_param_set ($E69C) at $C84D, first adding $20 when the code is $0A
; and the value is not zero ($C81F-$C83C). dds_mode_param_set writes $19 for
; codes 7 and $0A, $1A for 8, $17 for 9 and $18 for $0B, and for any other
; code returns without acting ($E761-$E787, the fall-through at $E75B) - which
; is how a destination of Off routes nothing. The node is a channel when one
; source feeds the input and the node code sum_node_program picks when
; several do (sum_join and sum_leave below); both are named in the same code
; space, biased by $0C.
; ---------------------------------------------------------------------------
mod_program
                pshs    a,b                     ; 0,s the node, 1,s the code
                lbsr    mod_register            ; B = the register id
                bcs     mod_program_not_mod
                pshs    b                       ; 0,s the register, 1,s the
                lda     1,s                     ; node, 2,s the code
                cmpa    #CHANNEL_MAX
                blo     mod_program_source
                clra                            ; 4 and above is (4, 0), the
                bra     mod_program_value       ; disconnect encoding
mod_program_source
                adda    #MOD_SOURCE_BIAS        ; a source is named in the
                                                ; same code space as an
                                                ; output port
                ldb     2,s                     ; the code
                cmpb    #LBL_DSB
                bne     mod_program_value
                adda    #MOD_DSB_FLAG           ; DSB shares AM's register:
                                                ; $C838 ADDB #$20, and only
                                                ; for a value that is not
                                                ; zero
mod_program_value
                tfr     a,b
                clra
                tfr     d,x                     ; X = the value
                puls    b                       ; B = the register
                leas    2,s
                lbsr    dds_write
                andcc   #~CC_CARRY
                rts
mod_program_not_mod
                leas    2,s
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; mod_route - route a channel to modulate Channel A
;
;   entry: A = the source channel, 0 to 3; B = the destination code
;   exit:  carry CLEAR and the routing is programmed;
;          carry SET and nothing was written
;   uses:  A, B, X, Y
;
; CHANNEL A CANNOT MODULATE ITSELF, and that is the ROM's own wording rather
; than a rule invented here: error $65 in the stock message table reads
; "Channel A can not modulate itself", raised by set_channel_destination
; ($78BF) at $78EF when the channel taking a modulation destination is
; channel 0. A channel modulating itself is a feedback path with no defined
; output.
;
; The write itself is mod_program's, so that a single source and a summing
; node go through the one routine, as both go through dds_mode_param_set
; ($E69C) in the stock. This routine adds the two checks a caller that has
; not been through destn_check needs.
; ---------------------------------------------------------------------------
mod_route
                tsta                            ; the source is Channel A?
                beq     mod_route_itself
                cmpa    #CHANNEL_MAX            ; AND BOUND IT ABOVE. The only
                blo     mod_route_bounded       ; check here was for channel
                                                ; zero, so a source of 4 or
                                                ; more went straight into
                                                ; `adda #MOD_SOURCE_BIAS` and
                                                ; named a register field that
                                                ; is not a channel. The stock
                                                ; bounds it: route_source_
                                                ; selector ($C7B0) turns any
                                                ; value of 4 or more into the
                                                ; disconnect encoding rather
                                                ; than value+$0C, and
                                                ; mod_program does the same.
                                                ; Here it is refused instead,
                                                ; because a caller asking to
                                                ; ROUTE channel 4 has made an
                                                ; error, not a disconnect.
                orcc    #CC_CARRY               ; refused, and nothing written
                rts
mod_route_bounded
                ; THE REFUSALS THAT USED TO SIT HERE - AM while amplitude
                ; hop is on, reject_am_while_amptd_hop ($7C9F), and a pulse
                ; modulator above 50 kHz, reject_pulse_destination ($7D1D) -
                ; are arms of the $7D92 table, so they are in destn_join
                ; with the rest of that table, where the stock makes them:
                ; after the old routing is down, forcing the destination to
                ; Off rather than returning. destn_apply reaches this routine
                ; only through destn_check and destn_join, in that order.
                lbra    mod_program             ; carry set if the code is
                                                ; not a modulation one
mod_route_itself
                ldb     #ERR_MOD_SELF
                lbsr    error_raise
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; mod_disconnect - stop routing anything to one modulation input
;
;   entry: B = the destination code
;   exit:  carry SET if the code is not a modulation one
;   uses:  A, B, X, Y
;
; Writes zero, which is what the stock writes when a source is taken away:
; d7ac3 calls route_source_selector ($C7B0) with the value 4, and 4 is the
; (4, 0) encoding at $C7CC-$C7DE. It matters that this exists: changing a
; channel's destination from AM to Out2 leaves the AM register still naming
; that channel unless something clears it, and the modulator would go on
; modulating.
; ---------------------------------------------------------------------------
mod_disconnect
                lda     #PORT_NONE
                lbra    mod_program

; ===========================================================================
; THE OUTPUT SOURCE MUX - which channel feeds which socket.
;
; A modulation destination routes a channel to Channel A; an OUTPUT
; destination routes it to a socket, and that is a different register and a
; different shape. Both go through the same commit, which is why they are in
; the same file.
;
; Two registers, two three-bit fields each:
;
;   $22 bits 0-2   the source feeding Out1      $23 bits 0-2   Out3
;   $22 bits 3-5   the source feeding Out2      $23 bits 3-5   Out4
;
; The field holds the source CHANNEL, 0 to 3, and FOUR MEANS NOTHING ROUTED -
; the stock clamps anything above 3 to 4 at $E652, and the power-on default
; is $24 in both registers, which is field 4 in both halves. So an instrument
; comes up with no channel connected to any socket, which is the safe state
; and the one this firmware now reproduces.
;
; Established from set_dds_mux_field ($E5E8), whose one caller is
; route_source_selector ($C817) - the same funnel the modulation routing goes
; through.
;
; NOTHING HERE EXISTED. Setting a destination to Out1 stored the code, showed
; the name on the screen, and routed nothing: a channel could be given a
; frequency, an amplitude and a socket, and produce silence. That is the same
; shape of hole the modulation routing was, found the same way - by asking
; what actually reaches the hardware.
; ===========================================================================

; ---------------------------------------------------------------------------
; port_route - feed one output socket from one channel
;
;   entry: A = the source channel 0 to 3, the node code 1 to 3 when the
;          socket carries a summing group, or PORT_NONE to disconnect
;          B = the destination code, LBL_OUT1 to LBL_OUT4
;   exit:  carry SET if the code is not an output socket
;   uses:  A, B, X, Y
;
; set_dds_mux_field ($E5E8), instruction for instruction: the port index
; picks register $22 for 0 and 1, $23 for 2 and 3, and a shift of 0 or 3
; ($E5F5-$E637); the value is clamped to 4 when above 3 ($E64B-$E657); the
; register is read back through its descriptor ($E638-$E65C), ANDed with
; $38 shifted right by the shift ($E65E-$E66A), ORed with the value shifted
; left by it ($E66C-$E67F) and written back ($E681-$E692). A read-modify-
; write of the shadow, because each register carries two sockets and writing
; it whole would disconnect the other one.
;
; The four working bytes live on the stack. They were four scratch cells,
; port_source to port_reg, and those cells are routed_dest now.
; ---------------------------------------------------------------------------
port_route
                cmpb    #LBL_OUT1
                blo     port_route_bad
                cmpb    #LBL_OUT4
                bhi     port_route_bad

                ; AND THE READ-MODIFY-WRITE BELOW IS HELD AGAINST THE TICK.
                ; This routine reads the routing register's shadow, replaces
                ; one three-bit field and writes it back, and BOTH sides of the
                ; firmware call it: the foreground when a destination changes,
                ; and tone_advance - through the interrupt - on every step of a
                ; running sequence. dds_write raises dds_lock for its own
                ; accesses, which is no help here: the tick can land between
                ; the READ and the WRITE, change the register, and have the
                ; foreground put the stale value back over it. Out1 then feeds
                ; the wrong channel, audibly, until something writes it again.
                ; each player's body defers a step while this is up, which is what
                ; the flag is for.
                inc     >dds_lock
                subb    #LBL_OUT1               ; B = the port, 0 to 3, as
                                                ; port_code_to_channel ($C765)
                                                ; gives it
                pshs    a,b                     ; 0,s the source, 1,s the port
                cmpb    #$02
                blo     port_route_low
                ldb     #DDS_PORT_MUX_23        ; $E60B/$E615: ports 2 and 3
                bra     port_route_read
port_route_low
                ldb     #DDS_PORT_MUX_01        ; $E5F5/$E5FF: ports 0 and 1
port_route_read
                pshs    b                       ; 0,s the register, 1,s the
                                                ; source, 2,s the port
                lbsr    dds_read                ; X = the shadow's value, as
                                                ; $E659 LDB [<$07,S] reads it
                tfr     x,d                     ; B = the old value

                ; KEEP THE OTHER FIELD AND NOTHING ELSE.
                ;
                ; This built the field's own mask and complemented it, which
                ; keeps the other field AND bits 6 and 7. The stock does not:
                ; set_dds_mux_field ($E5E8) ANDs the old value with
                ; ($38 >> shift) - $38 for the low field, $07 for the high one
                ; - so the two spare bits are cleared on every write
                ; (a2u12.s:20146-20165). What they do is not established here;
                ; that the stock clears them is, and a register the firmware
                ; only ever writes should be written the way the firmware that
                ; runs on this hardware writes it.
                lda     2,s                     ; the port: the odd one sits
                anda    #$01                    ; in bits 3-5
                beq     port_route_even
                andb    #PORT_KEEP_ODD          ; $38 >> 3 = $07
                bra     port_route_masked
port_route_even
                andb    #PORT_KEEP_MASK         ; $38
port_route_masked
                lda     1,s                     ; the source, clamped: $E64B
                cmpa    #PORT_NONE              ; CMPX #$0003 / LBLS, else
                bls     port_route_place        ; LDD #$0004 - anything above
                lda     #PORT_NONE              ; a channel disconnects
port_route_place
                pshs    b                       ; 0,s the kept bits, 1,s the
                ldb     3,s                     ; register, 2,s the source,
                andb    #$01                    ; 3,s the port
                beq     port_route_placed
                lsla                            ; the odd field: $E66C
                lsla                            ; shift_signed by 3
                lsla
port_route_placed
                ora     ,s+                     ; the field into the kept
                                                ; bits: $E677-$E67F
                tfr     a,b
                clra
                tfr     d,x                     ; X = the new value
                puls    b                       ; B = the register
                leas    2,s
                lbsr    dds_write               ; $E681-$E692 dds_param_store
                dec     >dds_lock
                andcc   #~CC_CARRY
                rts
port_route_bad
                orcc    #CC_CARRY               ; NOT a lock release: the two
                rts                             ; branches here are taken
                                                ; before it is raised

; ---------------------------------------------------------------------------
; port_disconnect - stop feeding one socket
;
;   entry: B = the destination code
;   exit:  carry SET if the code is not an output socket
;   uses:  A, B, X, Y
; ---------------------------------------------------------------------------
port_disconnect
                lda     #PORT_NONE
                lbra    port_route

; ---------------------------------------------------------------------------
; route_select - route_source_selector ($C7B0), for the values $78BF passes
;
;   entry: A = the node: a channel 0 to 3, the node code of a summing group,
;          or PORT_NONE (4) to disconnect
;          B = the destination code
;   exit:  carry CLEAR; nothing is written for a code that is neither a
;          socket nor a modulation input, which is what Off is
;   uses:  A, B, X, Y
;
; The one funnel every destination write goes through in the stock. Its
; callers are set_channel_destination ($78BF) at d7ac3 with 4 (an emptied
; destination), at l7ddd with the channel (a destination taken alone),
; dds_mux_mask_add_source ($E029) at $E168 and dds_mux_mask_remove_source
; ($E185) at $E2A8 with the node code those two compute; every one of them
; passes a value below $0F, so the (4, 8) encoding at $C7BB-$C7CA for $0F
; and above - a paged caller's, sequence_mode_init on page 1 and
; digital_sequence_mode_setup on page 2 - is not this routine's.
; $C7EF-$C81C: port_code_to_channel ($C765) says whether the code is Out1-
; Out4 and set_dds_mux_field ($E5E8) writes that socket's field; $C81F-$C852
; hand everything else to dds_mode_param_set ($E69C).
; ---------------------------------------------------------------------------
route_select
                cmpb    #LBL_OUT1
                blo     route_select_mod
                cmpb    #LBL_OUT4
                bhi     route_select_mod
                lbra    port_route              ; a socket's field
route_select_mod
                lbsr    mod_program             ; a modulation register, or
                andcc   #~CC_CARRY              ; nothing for Off ($E75B)
                rts

; ===========================================================================
; THE SUMMING GROUP - several channels feeding one destination.
;
; The stock lets more than one channel take the same destination, and when
; a second one does the chip ADDS them: "Summing channels cannot be split"
; ($6A), "Amplitude sum exceeds limit" and "Only one DC sum permitted into
; an output" in its message table are all about this. The instrument's own
; DTMF is a two-tone sum on one socket.
;
; Two chip parameters carry it, established from the instruction stream of
; dds_mux_mask_add_source ($E029), dds_mux_mask_remove_source ($E185) and
; dds_reg20_program ($DF9F), and from executing the stock's
; set_channel_destination ($78BF) over the bus on the emulator
; (emulator/tests/test_summing_new.py holds the log):
;
;   $1F   the summing MASK: bit n set for each channel n in the group, and
;         $0F when both halves {A,B} and {C,D} are summed on two
;         destinations at once ($E116)
;   $20   the NODE that carries the sum: $08 when channel D is in the mask,
;         else $04 for C, else $02 - the highest channel of the group - or
;         $0A for the two-halves case and 0 for no group ($DFA5-$E00F)
;
; and the destination's OWN field or register then names the node - the
; highest channel of the group, 3, 2 or 1 - instead of a channel: that is
; the code dds_reg20_program returns ($E011-$E027) and route_source_selector
; ($C7B0) receives at $E168 and $E2A8.
;
; Joining, in the stock's order of writes ($E029): register $20, then the
; destination's field or register, then $1F. Leaving ($E185): the same three,
; the same order. Executed on the stock, B joining A on Out1 writes
; $2002 $2221 $1F03, and C joining them writes $2004 $2222 $1F07 - the log
; the gate compares against, word for word.
;
; TWO GROUPS AT ONCE are possible only as {A,B} and {C,D}: when the joiner
; would make a second pair beside a group whose mask is 3 or $0C, the mask
; becomes $0F, event_flags bit $1000 is set, $20 becomes $0A and the joiner's
; destination names node 1 for the low half or 3 for the high ($E10D-$E14F).
; Any other second pair is refused with $6A ($E152, $7C6E). Leaving such a
; pair undoes it ($E1BB-$E20D).
;
; sum_flags mirrors event_flags bits $0800 (SUM_ACTIVE) and $1000
; (SUM_SPLIT); routed_dest is the stock's record+$21, what each channel is
; routed to, and stands in for its per-destination counters $2408-$2411 -
; destn_count_others counts the other channels routed to a code, which is
; what set_channel_destination reads after it has decremented the old code's
; counter at $7AB2-$7AB9.
; ===========================================================================

; ---------------------------------------------------------------------------
; sum_bit - one bit for a channel: shift_signed ($FFA4)(1, n)
;
;   entry: B = n, 0 to 4
;   exit:  A = 1 << n
;   uses:  A, B
;
; $E095/$E0A1/$E0D1/$E219/$E274 all shift the constant 1 left by a channel
; index this way. The search at $E060 can leave the index at 4 when no
; record holds the code ($E07F CMPB #$04), and 1 << 4 is $10; the shift
; honours that rather than clamping, so the mask comes out as the stock's.
; ---------------------------------------------------------------------------
sum_bit
                lda     #$01
sum_bit_shift
                tstb
                beq     sum_bit_done
                lsla
                decb
                bra     sum_bit_shift
sum_bit_done
                rts

; ---------------------------------------------------------------------------
; sum_node_program - dds_reg20_program ($DF9F): register $20 from the mask
;
;   entry: B = the summing mask
;   exit:  A = the node code, 0 to 3, that the destination will be routed
;          to; register $20 written
;   uses:  A, B, X, Y
;
; $DFA5-$DFB8: with event_flags bit $0800 clear the value is 0 and the code
; 0. $DFBB-$DFD0: with bit $1000 set the value is $0A and the code 0.
; Otherwise the mask decides, highest channel first: $DFD3-$DFEB bit 3 gives
; $08 and code 3, $DFEE-$E006 bit 2 gives $04 and code 2, and $E009-$E00F
; anything else gives $02 and code 1. $E011-$E01D write the value to
; parameter $20 through dds_param_store ($DD9D) and $E01F-$E024 return the
; code in B.
; ---------------------------------------------------------------------------
sum_node_program
                pshs    b                       ; 0,s the mask
                lda     >sum_flags
                bita    #SUM_ACTIVE
                beq     sum_node_none
                bita    #SUM_SPLIT
                bne     sum_node_split
                ldb     ,s
                bitb    #$08                    ; channel D in the group
                bne     sum_node_d
                bitb    #$04                    ; channel C
                bne     sum_node_c
                ldb     #$02                    ; $E009: B, or A alone
                lda     #$01
                bra     sum_node_write
sum_node_d
                ldb     #$08                    ; $DFDE
                lda     #$03
                bra     sum_node_write
sum_node_c
                ldb     #$04                    ; $DFF9
                lda     #$02
                bra     sum_node_write
sum_node_split
                ldb     #SUM_NODE_SPLIT         ; $DFCB
                clra
                bra     sum_node_write
sum_node_none
                clrb                            ; $DFB2
                clra
sum_node_write
                leas    1,s                     ; the mask is used up
                pshs    a                       ; the code, kept over the write
                clra
                tfr     d,x                     ; X = the value
                ldb     #DDS_SUM_NODE
                lbsr    dds_write               ; $E011-$E01D
                puls    a
                rts

; ---------------------------------------------------------------------------
; sum_join - dds_mux_mask_add_source ($E029): a channel joins a destination
;            that another channel already holds
;
;   entry: A = the joining channel; B = the destination code, which at
;          least one other channel is routed to (destn_join has counted)
;   exit:  carry CLEAR: $20, the destination's field or register, and $1F
;          are written, in that order; carry SET: the $E152 refusal, and
;          nothing has been written
;   uses:  A, B, X, Y
;
; The stock is called from $7C4C with the new code's counter (the other
; channels holding it), the channel and the code. $E02F-$E043 read the mask
; from parameter $1F. Then:
;
;   bit $0800 clear ($E045)  - THE FIRST GROUP. $E054 sets the bit; $E060-
;       $E092 walk the four records for the first whose +$21 is the code
;       (the joiner's own still holds its old code, so it cannot match), and
;       the mask becomes (1 << that channel) + (1 << joiner) at $E095-$E0AF,
;       replacing whatever $1F held.
;   bit set, counter not 1 ($E0C7)  - A THIRD OR FOURTH CHANNEL joins the
;       group: $E0CE-$E0DE add 1 << joiner to the mask.
;   bit set, counter 1  - A SECOND PAIR. Admitted only when the standing mask
;       is 3 or $0C ($E0FA-$E10A), and then $E10D sets bit $1000, the mask
;       becomes $0F ($E116) and the code is 1 for a joiner of 0 or 1 and 3
;       for 2 or 3 ($E11D-$E13D), with dds_reg20_program's own return thrown
;       away ($E13F-$E14F). Any other pair returns 1 at $E152 and
;       set_channel_destination reports $6A.
;
; The first two arms keep dds_reg20_program's code ($E0C2, $E0F5). All
; three then route the code with route_source_selector ($E159-$E16D) and
; write the mask back to $1F ($E16F-$E17D).
; ---------------------------------------------------------------------------
sum_join
                pshs    a,b                     ; 0,s the channel, 1,s the code
                ldb     #DDS_SUM_MASK
                lbsr    dds_read                ; X = the shadow: $E040 LDB
                tfr     x,d                     ; [<$04,S]
                pshs    b                       ; 0,s the mask, 1,s the
                                                ; channel, 2,s the code
                lda     >sum_flags
                bita    #SUM_ACTIVE             ; $E045-$E04D
                bne     sum_join_active
                ora     #SUM_ACTIVE             ; $E054-$E05B
                sta     >sum_flags
                ldx     #routed_dest            ; $E060-$E092: the first
                clra                            ; channel routed to the code
sum_join_search
                ldb     ,x
                cmpb    2,s
                beq     sum_join_found
                leax    1,x
                inca
                cmpa    #CHANNEL_MAX            ; $E07F CMPB #$04: none found
                blo     sum_join_search         ; leaves 4, as there
sum_join_found
                tfr     a,b
                lbsr    sum_bit                 ; $E095-$E09D: the mask is
                sta     ,s                      ; 1 << that channel
                ldb     1,s
                lbsr    sum_bit                 ; $E09F-$E0AF: plus 1 << the
                adda    ,s                      ; joiner
                sta     ,s
                bra     sum_join_node
sum_join_active
                lda     1,s
                ldb     2,s
                lbsr    destn_count_others      ; B = the counter: arg1
                cmpb    #$01                    ; $E0C7 CMPX #$0001
                beq     sum_join_pair
                ldb     1,s                     ; $E0CE-$E0DE: the mask gains
                lbsr    sum_bit                 ; 1 << the joiner
                adda    ,s
                sta     ,s
sum_join_node
                ldb     ,s
                lbsr    sum_node_program        ; $E0B1-$E0C2 and $E0E0-
                bra     sum_join_route          ; $E0F7: A = the code
sum_join_pair
                lda     ,s
                cmpa    #SUM_MASK_LOW           ; $E0FA-$E10A: only {A,B}
                beq     sum_join_split          ; or {C,D} may stand beside
                cmpa    #SUM_MASK_HIGH          ; a second pair
                beq     sum_join_split
                leas    3,s                     ; $E152: return 1
                orcc    #CC_CARRY
                rts
sum_join_split
                lda     >sum_flags
                ora     #SUM_SPLIT              ; $E10D-$E114
                sta     >sum_flags
                lda     #SUM_MASK_ALL           ; $E116-$E118
                sta     ,s
                lda     1,s                     ; $E11D-$E13D: a joiner of 0
                cmpa    #$02                    ; or 1 names node 1, of 2 or
                blo     sum_join_split_low      ; 3 node 3
                lda     #$03
                bra     sum_join_split_node
sum_join_split_low
                lda     #$01
sum_join_split_node
                pshs    a                       ; the code, kept over the $20
                ldb     1,s                     ; write whose own return
                lbsr    sum_node_program        ; $E13F-$E14F discards
                puls    a
sum_join_route
                ldb     2,s                     ; $E159-$E16D route_source_
                lbsr    route_select            ; selector(code, node)
                ldb     ,s                      ; $E16F-$E17D parameter $1F
                clra                            ; takes the mask
                tfr     d,x
                ldb     #DDS_SUM_MASK
                lbsr    dds_write
                leas    3,s
                andcc   #~CC_CARRY
                rts

; ---------------------------------------------------------------------------
; sum_leave - dds_mux_mask_remove_source ($E185): a channel leaves a
;             destination that other channels still hold
;
;   entry: A = the leaving channel; B = the destination code it is routed
;          to, which at least one other channel is routed to as well
;          (destn_leave has counted)
;   exit:  $20, the destination's field or register, and $1F are written,
;          in that order
;   uses:  A, B, X, Y
;
; The stock is called from $7B16 with the old code's counter after the
; decrement (the other channels still holding it), the channel and the
; code. $E18B-$E19F read the mask from parameter $1F. Then:
;
;   counter not 1 ($E1A3)  - the group keeps two or more: $E274-$E288 take
;       1 << leaver out of the mask and dds_reg20_program's code is kept
;       ($E289-$E296).
;   counter 1, bit $1000 set ($E1AA)  - one of the two pairs breaks up:
;       $E1BB clears the bit and $E1F6-$E20D pick the pair that remains by
;       the leaver - channel 0 leaves mask $0C and code 1, 1 leaves $0C and
;       0, 2 leaves 3 and 3, 3 leaves 3 and 2 ($E1CC-$E1F3): the mask is
;       the OTHER half and the code is the leaver's own partner, which is
;       now alone on the destination.
;   counter 1, bit $1000 clear  - the last pair breaks up: $E210 clears bit
;       $0800, $E219-$E22E take the leaver's bit out, $E24C-$E25C turn the
;       one bit left into the partner's index (1, 2, 4, 8 give 0, 1, 2, 3)
;       and $E25F zeroes the mask.
;
; The last two arms discard dds_reg20_program's return ($E261-$E271), which
; with the mask zero and bit $0800 clear writes $20 <- 0. All three route
; the code with route_source_selector ($E299-$E2AB) and write the mask back
; to $1F ($E2AD-$E2BB).
;
; $E24C's chain leaves its local untouched when the remaining mask is not
; a single bit; frame_alloc does not clear the frame, so the stock would
; route whatever byte was there. A pair whose mask has more or fewer than
; two bits set cannot be built by sum_join, so the case does not arise;
; here it routes PORT_NONE, which disconnects the destination rather than
; naming a channel by accident, and the choice is this firmware's.
; ---------------------------------------------------------------------------
sum_leave
                pshs    a,b                     ; 0,s the channel, 1,s the code
                ldb     #DDS_SUM_MASK
                lbsr    dds_read                ; X = the shadow: $E19C LDB
                tfr     x,d                     ; [<$03,S]
                pshs    b                       ; 0,s the mask, 1,s the
                                                ; channel, 2,s the code
                lda     1,s
                ldb     2,s
                lbsr    destn_count_others      ; B = the counter: arg1
                cmpb    #$01                    ; $E1A3 CMPX #$0001
                bne     sum_leave_many
                lda     >sum_flags
                bita    #SUM_SPLIT              ; $E1AA-$E1B8
                beq     sum_leave_last
                anda    #~SUM_SPLIT             ; $E1BB-$E1C2
                sta     >sum_flags
                ldb     1,s                     ; the leaver
                cmpb    #$02
                blo     sum_leave_low_half
                lda     #SUM_MASK_LOW           ; $E1E0/$E1EB: 2 or 3 leaves,
                bra     sum_leave_pair          ; {A,B} remain
sum_leave_low_half
                lda     #SUM_MASK_HIGH          ; $E1CC/$E1D7: 0 or 1 leaves,
sum_leave_pair                                  ; {C,D} remain
                sta     ,s
                lda     1,s
                eora    #$01                    ; the partner left alone:
                                                ; 0 gives 1, 1 gives 0, 2
                                                ; gives 3, 3 gives 2 - the
                                                ; four codes of $E1CC-$E1F3
                pshs    a                       ; the code, kept over the $20
                ldb     1,s                     ; write whose return is
                lbsr    sum_node_program        ; discarded ($E261-$E271)
                puls    a
                bra     sum_leave_route
sum_leave_last
                anda    #~SUM_ACTIVE            ; $E210-$E217
                sta     >sum_flags
                ldb     1,s
                lbsr    sum_bit                 ; $E219-$E22E: the leaver's
                tfr     a,b                     ; bit out of the mask
                lda     ,s
                pshs    b
                suba    ,s+
                sta     ,s
                tfr     a,b
                lda     #PORT_NONE              ; see the header: the code
                cmpb    #$01                    ; when no single bit remains
                bne     sum_leave_not_a
                clra                            ; $E232
sum_leave_not_a
                cmpb    #$02
                bne     sum_leave_not_b
                lda     #$01                    ; $E237
sum_leave_not_b
                cmpb    #$04
                bne     sum_leave_not_c
                lda     #$02                    ; $E23E
sum_leave_not_c
                cmpb    #$08
                bne     sum_leave_not_d
                lda     #$03                    ; $E245
sum_leave_not_d
                clr     ,s                      ; $E25F: the mask is zero
                pshs    a                       ; the code, kept over the $20
                ldb     1,s                     ; write, which is 0 now that
                lbsr    sum_node_program        ; the bit is clear ($E261)
                puls    a
                bra     sum_leave_route
sum_leave_many
                ldb     1,s
                lbsr    sum_bit                 ; $E274-$E288: the leaver's
                tfr     a,b                     ; bit out of the mask
                lda     ,s
                pshs    b
                suba    ,s+
                sta     ,s
                tfr     a,b
                lbsr    sum_node_program        ; $E289-$E296: A = the code
sum_leave_route
                ldb     2,s                     ; $E299-$E2AB route_source_
                lbsr    route_select            ; selector(code, node)
                ldb     ,s                      ; $E2AD-$E2BB parameter $1F
                clra                            ; takes the mask
                tfr     d,x
                ldb     #DDS_SUM_MASK
                lbsr    dds_write
                leas    3,s
                rts

; ---------------------------------------------------------------------------
; destn_is_output - does this destination drive a socket?
;
; MOVED HERE FROM page0_destination.s, with destn_apply below it. Both
; were on page 0, and register_apply in the always-mapped image needs to
; route a recalled setup - a page cannot be called from A2U12 and only
; one page is mapped at a time, so the routing had to be in one place
; both can reach. The screen calls them through ABI slots 50 and 51.
;
;   entry: B = the code
;   exit:  carry CLEAR if it is one of the four output sockets
;   uses:  nothing
;
; The modulation destinations need a target channel and the sockets do not,
; so the screen asks this before deciding whether to offer one.
;
; Out1 to Out4 are codes 12 to 15, contiguous, so this is two comparisons.
; They are NOT codes 0 to 3: that was the invented numbering, and this test
; used to read "below Out4+1", which accepted every waveform code as an
; output socket.
; ---------------------------------------------------------------------------
destn_is_output
                cmpb    #LBL_OUT1
                blo     destn_is_output_no
                cmpb    #LBL_OUT4
                bhi     destn_is_output_no
                andcc   #~CC_CARRY
                rts
destn_is_output_no
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; destn_record - the record of one channel
;
;   entry: B = the channel, 0 to 3
;   exit:  X = its record in channel_records
;   uses:  A, B, X
;
; The stock indexes the same way: array_element_address ($FCEA) with the
; descriptor at $7FDF - stride $23 - from $24F5, so channel n's record is
; $24F5 + 35n and its waveform and destination sit at +$1F and +$21. Here a
; record is CHAN_RECORD bytes with the waveform at CHAN_WAVE and the
; destination at CHAN_DEST.
; ---------------------------------------------------------------------------
destn_record
                lda     #CHAN_RECORD
                mul
                ldx     #channel_records
                leax    d,x
                rts

; ---------------------------------------------------------------------------
; destn_dc_shared - does another dc channel already sum into this destination?
;
;   entry: A = the channel to leave out, B = the destination code
;   exit:  carry SET if some other channel is routed to that destination
;          with a dc waveform; A and B come back as they went in
;   uses:  X, Y
;
; dc_destination_conflict ($7736): $7740-$77A4 loops channels 0 to 3, skips
; the one named by its first argument ($774C CMPD >$0009,s), and returns 1
; when a record's destination word (+$21, $776C) equals the second argument
; and its waveform word (+$1F, $778C) is 4 - 'dc' in the $EE62 waveform
; table, LBL_DC here. set_channel_destination ($78BF) calls it at $797A only
; when the channel's own waveform is dc ($7963-$7972) and the destination is
; neither a modulation one nor Off, and beeps $99 when it returns non-zero.
; The destination read is routed_dest, which is what record+$21 is.
; ---------------------------------------------------------------------------
destn_dc_shared
                pshs    a,b                     ; 0,s the channel left out,
                ldx     #channel_records        ; 1,s the code
                ldy     #routed_dest
                clra                            ; A walks the channels
destn_dc_loop
                cmpa    ,s
                beq     destn_dc_next           ; the channel itself, $774C
                ldb     ,y
                cmpb    1,s
                bne     destn_dc_next           ; another destination, $7770
                ldb     CHAN_WAVE,x
                cmpb    #LBL_DC
                beq     destn_dc_found          ; the same one, and dc, $7790
destn_dc_next
                leax    CHAN_RECORD,x
                leay    1,y
                inca
                cmpa    #CHANNEL_MAX
                blo     destn_dc_loop
                puls    a,b
                andcc   #~CC_CARRY
                rts
destn_dc_found
                puls    a,b
                orcc    #CC_CARRY
                rts

; ---------------------------------------------------------------------------
; destn_count_others - how many OTHER channels are routed to a destination
;
;   entry: A = the channel to leave out, B = the destination code
;   exit:  B = how many of the other three are routed to that code;
;          A = the last one that is, meaningful when B is 1
;   uses:  A, B, X
;
; The stock keeps one counter per destination code - $240D AM, $240E DSB,
; $240F FM, $2410 PhiM, $2411 Plse, $2409-$240C Out1-Out4, $2408 Off,
; handed out by destination_use_count_addr ($782A) - which
; set_channel_destination ($78BF) decrements for the old code at $7AB2-$7AB9
; before it tests the new one, so every test it makes on a counter, and
; every count it hands to dds_mux_mask_add_source ($E029) at $7C4C and
; dds_mux_mask_remove_source ($E185) at $7B16, is a count of the OTHER
; channels. This firmware keeps no counters; routed_dest is the count, and
; leaving the channel out is the decrement.
; ---------------------------------------------------------------------------
destn_count_others
                pshs    a,b                     ; 2,s the channel left out,
                clra                            ; 3,s the code, once the
                clrb                            ; next push is on
                pshs    a,b                     ; 0,s the count, 1,s the last
                ldx     #routed_dest            ; channel that matched
                clra                            ; A walks the channels
destn_count_loop
                cmpa    2,s
                beq     destn_count_next        ; the channel itself
                ldb     ,x
                cmpb    3,s
                bne     destn_count_next
                inc     ,s                      ; one more
                sta     1,s                     ; and which
destn_count_next
                leax    1,x
                inca
                cmpa    #CHANNEL_MAX
                blo     destn_count_loop
                puls    a,b                     ; A = the count, B = the last
                exg     a,b                     ; B = the count, A = the last
                leas    2,s
                rts

; ---------------------------------------------------------------------------
; destn_check - the refusals the stock makes BEFORE it touches the routing
;
;   entry: A = the channel, B = the destination code
;   exit:  carry CLEAR and nothing raised, or carry SET with the error
;          recorded and sounded; A and B come back as they went in
;   uses:  X, Y
;
; THIS IS set_channel_destination ($78BF, a2u13_page0) FROM ITS ENTRY TO
; $79EE, in its order and with its precedence, and nothing else. Every
; refusal in that stretch ends the routine at l7fdb ($79DB LBRA l7fdb, and
; $7925-$793D and $7986-$7993 the same way) with nothing torn down and
; nothing written, which is all a routine that only checks can do.
;
; THE STOCK'S OTHER REFUSALS ARE NOT HERE, AND USED TO BE. $69 at $7BB3,
; $6A at $7C6E and $6B/$6C at $7DA4 all fire AFTER the old routing has been
; dismantled, and not one of them returns: each reports its error and then
; executes LDD #$0010 / STD >$001a,s - the destination argument forced to
; Off - and carries on through the rest of the routine, so the channel is
; left Off with the vacated socket's relay open. They are ported where they
; stand, in destn_route (E, $7B7F-$7BC7) and destn_join (F, $7C1B-$7C95, and
; G, the arms of the $7D92 table reported at $7DA4).
;
; Holding them here refused up front and left the standing destination
; alone, which the instrument does not do. Measured side by side with
; 'DEB OC1; DEA OC3; DEB OC4;': the stock ends with output latches
; (4,4,0,0) and answers 'DEB?;' with 00016, Off; this firmware ended with
; (0,4,0,0) and answered 00012, Out1 - the refused channel still on the
; socket it was told to leave.
;
; Each block names the instructions it stands for. Where the stock reads a
; record's destination word (+$21) or a destination's counter, this reads
; routed_dest - what the channel is routed to - and the counts are taken
; over it (destn_count_others).
;
; A. A MODULATION DESTINATION, $78D0-$793D. is_modulation_destination
;    ($77D9) says the code is 7 to $0B. Then three tests, each of which
;    stores its error into the same byte 9,s, so the LAST one that fires is
;    the one error_report_beep ($C3FE) gets at $7938: $78E1 the channel is
;    0 -> $65; $78F5 LDX >$2514 / CMPX #$0004, channel 0's waveform is dc
;    -> $66; $7903-$7922 the channel's own record+$1F is 4 -> $67. Any of
;    them ends the routine at $793D with nothing changed.
; B. A DC CHANNEL INTO A SHARED DESTINATION, $7943-$7993. For a code that
;    is not modulation and not Off ($7943 CMPX #$0010): when this channel's
;    waveform is dc ($7963-$7972), dc_destination_conflict ($7736) looks for
;    another dc channel on the same destination and $99 ends the routine.
; C. THE SAME CODE AGAIN, $7996-$79A0: a destination the channel is already
;    routed to returns at once, so D below is skipped for it and destn_route
;    makes the same test at its own head and does nothing either. (This used
;    to run the $7D92 arms for an unchanged code
;    because register recall re-applied each record's own code; the recall
;    goes through routed_dest now, and a recalled code is only "unchanged"
;    when the channel really is routed to it already.)
; D. AN OUTPUT THAT IS NOT FITTED, $79A3-$79EB. port_code_to_channel
;    ($C765) turns Out1-Out4 into 0-3 and anything else into $FF; for 0-3
;    the stock adds one with add_bytes_to_word ($FD80) and refuses with $68
;    when the installed count $23B2 is below the sum, so Out(n) exists
;    when n-1 is below installed_channels. $79DB reports $68 and LBRA
;    l7fdb: it is the LAST refusal the stock makes with the routing intact,
;    and that is why the routine ends here.
;
; Executed on the stock in the emulator, calling $78BF with the record
; pointer $23BF set to the channel: $65, $66, $67 (and $67 over $66 over
; $65 when several hold), $99 and $68 - and the same scenarios run through
; this routine give the same verdicts. The measurements behind $69, $6A,
; $6B and $6C are recorded beside those checks, in destn_route and
; destn_join.
; ---------------------------------------------------------------------------
destn_check
                pshs    a,b                     ; 0,s the channel, 1,s the code

                ; --- A. a modulation destination ---------------------------
                cmpb    #LBL_MOD_FIRST
                blo     destn_check_not_mod
                cmpb    #LBL_MOD_LAST
                bhi     destn_check_not_mod
                clrb                            ; the error byte, 9,s in the
                tsta                            ; stock: the last store wins
                bne     destn_check_a_cha
                ldb     #ERR_MOD_SELF           ; $78E1-$78F0: channel 0
destn_check_a_cha
                ldx     #channel_records        ; channel 0's record: $2514
                lda     CHAN_WAVE,x             ; is $24F5+$1F
                cmpa    #LBL_DC
                bne     destn_check_a_own
                ldb     #ERR_MOD_CHA_DC         ; $78F5-$7900
destn_check_a_own
                pshs    b
                ldb     1,s                     ; the channel, under the push
                lbsr    destn_record
                puls    b
                lda     CHAN_WAVE,x
                cmpa    #LBL_DC
                bne     destn_check_a_verdict
                ldb     #ERR_MOD_SRC_DC         ; $7903-$7922
destn_check_a_verdict
                tstb
                lbne    destn_check_refuse      ; $7925-$793D
                lbra    destn_check_same

                ; --- B. a dc channel into a shared destination -------------
destn_check_not_mod
                cmpb    #LBL_OFF                ; $7943: Off has no checks
                lbeq    destn_check_ok          ; at all
                ldb     ,s
                lbsr    destn_record            ; X = this channel's record
                lda     CHAN_WAVE,x
                cmpa    #LBL_DC                 ; $7963-$7972
                bne     destn_check_same
                lda     ,s
                ldb     1,s
                lbsr    destn_dc_shared         ; $797A
                bcc     destn_check_same
                ldb     #ERR_DC_SUM_DUP         ; $7986-$7993
                lbra    destn_check_refuse

                ; --- C. the same code again --------------------------------
destn_check_same
                ldb     ,s
                ldx     #routed_dest            ; what the channel is routed
                abx                             ; to: record+$21 at $78C5
                ldb     ,x
                cmpb    1,s                     ; $7996-$79A0
                lbeq    destn_check_ok

                ; --- D. an output that is not fitted -----------------------
                ldb     1,s
                lbsr    destn_is_output         ; $C765: 0-3 for Out1-Out4,
                bcs     destn_check_ok          ; $FF for the rest
                subb    #LBL_OUT1               ; B = 0 to 3
                cmpb    >installed_channels     ; $79CE CMPD <$10,s against
                blo     destn_check_ok          ; $23B2
                ldb     #ERR_NO_SUCH_CHANNEL    ; $79DB: $68, and LBRA l7fdb -
                lbra    destn_check_refuse      ; the last one that returns
destn_check_ok
                puls    a,b
                andcc   #~CC_CARRY
                rts
destn_check_refuse
                lbsr    error_report_beep       ; beep and record, as
                puls    a,b                     ; $C3FE does - and nothing on
                orcc    #CC_CARRY               ; the bus, which $C3FE never
                rts                             ; sends

; ---------------------------------------------------------------------------
; destn_leave - a channel gives up the destination it is routed to
;
;   entry: A = the channel, B = the destination code it is routed to
;   uses:  A, B, X, Y, U
;
; set_channel_destination ($78BF), $7AA9-$7B77. destination_use_count_addr
; ($782A) hands out the old code's counter, $7AB2-$7AB9 decrement it, and
; what is left decides:
;
;   zero ($7ABB-$7AC0)  - the channel was alone. d7ac3 calls
;       route_source_selector ($C7B0) with 4: the socket's field becomes
;       PORT_NONE, a modulation register becomes 0, Off writes nothing. Then
;       $7AD9-$7AEA: an old code of 8 (FM) has dds_write_reg16 ($E36F) send
;       0 to register $16, fm_rang - the shared range of a group that no
;       longer exists; and $7AED-$7B13, for AM ($7AF0 CMPX #$0007) and DSB
;       ($7AF8 CMPX #$000A), re-apply channel A through
;       dispatch_channel_function ($C069)(0, $24FF) - $24FF is channel 0's
;       record+10, so this is channel 0's own level put back by its own
;       unit, with the modulator gone: ampl_carrier_reapply, told that this
;       channel's counter is already down ($7AB2) while its record+$21 still
;       names the code.
;   not zero, and the code not Off ($7B16-$7B1C)  - others still hold it.
;       dds_mux_mask_remove_source ($E185) takes the channel out of the
;       group and re-routes what remains (sum_leave); then $7B3B-$7B46, for
;       FM, rescale_channels_to_common_exponent ($BAE3) puts the remaining
;       modulators on one range - ampl_fm_rescale, which is that routine -
;       and FM, being a modulation code, takes $7B5A-$7B65's LBRA over the
;       rest. $7B49-$7B74 then run channel_apply_and_propagate ($BE5C) on
;       this channel for DSB ($7B4C CMPX #$000A / LBEQ l7b68) and for any
;       code is_modulation_destination ($77D9) says no to - the sockets:
;       ampl_propagate, with this channel's counter down and its record+$21
;       still the old code, so it is recoded as a member (its level is zero
;       by now, $7A45) and not counted as a modulator.
;   not zero, Off  - $7B1C branches straight to l7b77: nothing at all.
; ---------------------------------------------------------------------------
destn_leave
                pshs    a,b                     ; 0,s the channel, 1,s the code
                lbsr    destn_count_others      ; B = the others still routed
                tstb                            ; to it: the counter after
                bne     destn_leave_sum         ; $7AB2's decrement
                lda     #PORT_NONE              ; d7ac3: route_source_
                ldb     1,s                     ; selector(code, 4)
                lbsr    route_select
                ldb     1,s
                cmpb    #LBL_FM
                bne     destn_leave_alone_mod
                ldx     #$0000                  ; $7AD9-$7AEA: fm_rang <- 0
                ldb     #DDS_FM_RANGE           ; when the last FM modulator
                lbsr    dds_write               ; goes
                bra     destn_leave_done
destn_leave_alone_mod
                cmpb    #LBL_AM                 ; $7AED-$7B13: the last AM or
                beq     destn_leave_carrier     ; DSB modulator gone, the
                cmpb    #LBL_DSB                ; carrier is re-applied
                bne     destn_leave_done
destn_leave_carrier
                lda     ,s                      ; this channel's counter is
                lbsr    ampl_carrier_reapply    ; already down: $C069(0,$24FF)
                bra     destn_leave_done
destn_leave_sum
                ldb     1,s
                cmpb    #LBL_OFF                ; $7B16-$7B1C: Off is never
                beq     destn_leave_done        ; a summing group
                lda     ,s
                lbsr    sum_leave               ; $7B1F-$7B33: $E185
                ldb     1,s
                cmpb    #LBL_FM
                bne     destn_leave_not_fm
                lbsr    ampl_fm_rescale         ; $7B3B-$7B46: $BAE3, the
                bra     destn_leave_done        ; remaining FM modulators on
                                                ; one range; $7B5A-$7B65
                                                ; skips $BE5C for FM
destn_leave_not_fm
                cmpb    #LBL_DSB                ; $7B4C: DSB propagates...
                beq     destn_leave_propagate
                lbsr    label_is_modulation     ; $7B5A: ...and so does any
                bcs     destn_leave_done        ; code that is not a
destn_leave_propagate                           ; modulation one
                lda     ,s                      ; $7B68-$7B74: $BE5C(channel),
                ldb     ,s                      ; the counter down, the record
                lbsr    ampl_propagate          ; still routed here
destn_leave_done
                puls    a,b
                rts

; ---------------------------------------------------------------------------
; destn_park_all - every channel gives up what it is routed to
;
;   uses:  A, B, X, Y, U
;
; clear_all_destinations ($5253, A2U13 page 0): $525C-$528A loop $23BE from
; 0 to 3, point $23BF at the record with cache_channel_record_ptr ($C21A)
; and call set_channel_destination ($78BF)(channel, $0010) - Off - so each
; channel goes through the whole of $78BF with Off as the new code:
; destn_route below, which zeroes the record's level ($7A45), writes the
; level register's zero ($7A8B), leaves ($7AA9-$7B77), joins nothing and
; writes zero again by Off's unit ($7EB8). It is the callback the stock
; installs at $2213 when Channel Config. is entered ($54D1-$54D4), and
; enter_handler_by_index ($F16A) runs it at $F1B1 BEFORE the recall's copy
; ($52B2) - register_restore keeps that order, so the zeroing lands on the
; old records and the copy brings the saved ones in over them. Executed
; over the bus, "RC 1;" on the stock with A summed onto C's Out3 writes
; $2000 $231A $1F00 for A, $231C for C and $2324 for D before its
; dds_params_reset flush and the re-application. Applying a saved setup on
; top of the live routing instead would put each channel's join through
; the summing checks against groups the saved setup does not have - and a
; setup saved with A beside B on Out2 was refused as a split pair ($6A) on
; recall while A stood beside C on Out3. CHAN_DEST is left alone by the
; route: it is the record, and here the record is either the live one that
; the copy is about to replace or - the keep-state boot, where routed_dest
; is already Off and nothing happens - the one to be applied.
; ---------------------------------------------------------------------------
destn_park_all
                clra                            ; channel 0 first, as $525C
destn_park_next
                pshs    a
                ldb     #LBL_OFF                ; $78BF(channel, $0010)
                lbsr    destn_route
                puls    a
                inca
                cmpa    #CHANNEL_MAX
                blo     destn_park_next
                rts

; ---------------------------------------------------------------------------
; destn_join - a channel takes a destination, and the two refusals that
;              happen while it does
;
;   entry: A = the channel, B = the new destination code
;   exit:  carry CLEAR and routed; carry SET when the join was REFUSED, with
;          the error already recorded and sounded and nothing routed. The
;          caller does not return on that: the stock forces the destination
;          to Off and carries on, and destn_route does the same
;   uses:  A, B, X, Y
;
; set_channel_destination ($78BF), $7C1B-$7DF0. destination_use_count_addr
; ($782A) hands out the new code's counter - the other channels holding it,
; this one not yet counted - and $7C36-$7C49 decide: not zero and not Off,
; and dds_mux_mask_add_source ($E029) joins the group ($7C4C-$7C5E); zero,
; or Off, and the code's arm in the $7D92 table runs and l7ddd calls
; route_source_selector ($C7B0) with the channel itself, which puts the
; channel in the socket's field, names it in the modulation register, or,
; for Off, writes nothing (dds_mode_param_set $E75B).
;
; BOTH OF THE STOCK'S REFUSALS HERE COME AFTER THE OLD ROUTING IS GONE, so
; both are here and not in destn_check, and neither returns to its caller:
;
; F. SUMMING CHANNELS, $7C4C-$7C95. $E029 refuses at $E0FA-$E152 - return 1,
;    $6A at $7C6E - when the counter is exactly 1 ($E0C7 CMPX #$0001),
;    event_flags bit $0800 is set ($E045: a group already exists) and the
;    mask in parameter $1F is neither 3 nor $0C: a second pair may stand
;    only beside {A,B} or {C,D}. sum_join is that routine and makes that
;    test over sum_flags and the $1F shadow it and sum_leave keep; here only
;    its verdict is turned into the error. Executed against the stock's
;    $78BF on the emulator: {0,2} summed and 3 alone refuses 1 with $6A,
;    {0,1} summed and 2 alone admits 3, {1,2} on FM refuses 0 joining 3 on
;    Out1, {2,3} on FM admits it, a third channel joining a pair is
;    admitted, and a channel that leaves a pair and joins a lone channel in
;    its own half is admitted.
;
;    THE OLD GROUP IS ALREADY GONE WHEN THIS RUNS, and that is the whole
;    reason it belongs here. $7AB2-$7AB9 decrements the OLD destination's
;    counter, $7B16-$7B34 calls dds_mux_mask_remove_source ($E185) unless
;    that counter hit zero, $7B77 parks the record at Off, and only then
;    does $7C1B read the NEW destination's counter. $E185's $E210 arm -
;    taken when one member survives and bit $1000 is clear - CLEARS bit
;    $0800 and zeroes the mask ($E25F CLR 2,s), so $E029 then takes its
;    no-sum-active path and accepts whatever it is given. Driven 2026-09-11:
;    channel B set to dc and walked Out1, Out2, Out3, Out4 from the panel,
;    and the instrument takes all four. Testing this before the teardown
;    refused the last step with $6A against a group that no longer exists,
;    and the pre-test that used to paper over that is gone with it.
;
; G. THE PER-DESTINATION ARMS of the table at $7D92, reached only when the
;    counter is zero or the code is Off ($7C49 LBRA l7c98, $7C98 LDX
;    >$001a,s / LBRA l7d7f, and the guard $7D7F CMPX #$000F / SUBD #$0007
;    sends Off and anything outside 7..15 to destn_accept_no_check):
;    reject_am_while_amptd_hop ($7C9F) AM against bit 6 of $2203 -> $6B;
;    check_pm_allowed ($7CBC) PhiM against bit 7 -> $6B; destn_check_dsb
;    ($7CD2) DSB against bit 6 -> $6B; reject_pulse_destination ($7D1D)
;    Plse against bit 5 -> $6B and, at $7D30-$7D5F, the channel's frequency
;    above $EA5F (500,000 tenths of a hertz) -> $6C, the second store
;    winning over the first ($7D2D, $7D5F), so a fast pulse modulator is
;    reported as too fast, not as a hop conflict. The bits are MODE_FLAG_AM,
;    MODE_FLAG_PHASE and MODE_FLAG_PULSE, which dds_mode_flag mirrors as
;    $E69C does. Each arm ends at $7DA4, which reads the selector 9,s and,
;    when it is not zero, adds it to $6A with $FD80, reports it, forces the
;    destination to $0010 and LBRA l7df0 - so route_source_selector at
;    l7ddd is skipped and nothing is routed.
;
;    PhiM AND DSB WERE ALSO REFUSED HERE while hop_running was set, and the
;    stock's arms make no such test: check_pm_allowed ($7CBC) reads bit 7 of
;    $2203 and destn_check_dsb ($7CD2) bit 6, and neither looks at a hop
;    switch. The argument for it was that this firmware hops frequency,
;    amplitude and phase per slot behind one switch, so that switch stands
;    for the hop bits the stock sets separately - and formats.inc called it
;    "the recorded departure destn_apply keeps". IT WAS NOT RECORDED:
;    the owner made no ruling for it, and the standard is the
;    instrument. An extra refusal is still a divergence - it is an operation
;    the instrument performs and this one would not - so the test is gone and
;    both codes now reach destn_join_route on the same terms as the stock's.
;
;    The arms' other work is not refusal and is not here: l7cb5 and $7D0F
;    set 10,s, the carrier re-apply flag, and $7CE8-$7D0D zero channel 0's
;    level and set its unit to $0E. destn_route does both after this
;    returns, and skips both when it returns carry set - which is what the
;    stock's cleared 10,s at $7C1B leaves behind on the refused leg.
; ---------------------------------------------------------------------------
destn_join
                pshs    a,b                     ; 0,s the channel, 1,s the code
                cmpb    #LBL_OFF                ; $7C3B-$7C49: Off never
                beq     destn_join_arms         ; joins a group - it takes the
                                                ; arms, which pass it through
                lbsr    destn_count_others      ; B = the others holding it:
                tstb                            ; $7C36 LDB [<$07,S]
                beq     destn_join_arms
                lda     ,s
                ldb     1,s
                lbsr    sum_join                ; $7C4C-$7C5E: $E029
                bcc     destn_join_ok
                ldb     #ERR_SUM_SPLIT          ; l7c6e: $E152's return of 1
                lbsr    error_report_beep       ; becomes $6A, through $C3FE
                bra     destn_join_refused
destn_join_ok
                puls    a,b
                andcc   #~CC_CARRY
                rts
destn_join_refused
                puls    a,b
                orcc    #CC_CARRY
                rts

                ; --- G. the per-destination arms of $7D92 ------------------
destn_join_arms
                ldb     1,s
                cmpb    #LBL_AM
                bne     destn_join_arm_pm
                lda     >mode_flags             ; $7C9F: bit 6 of $2203
                bita    #MODE_FLAG_AM
                bne     destn_join_hop_bad
                bra     destn_join_route
destn_join_arm_pm
                cmpb    #LBL_PHIM
                bne     destn_join_arm_dsb
                lda     >mode_flags             ; $7CBC: bit 7 of $2203
                bita    #MODE_FLAG_PHASE
                bne     destn_join_hop_bad
                bra     destn_join_route
destn_join_arm_dsb
                cmpb    #LBL_DSB
                bne     destn_join_arm_plse
                lda     >mode_flags             ; $7CD2: bit 6 of $2203
                bita    #MODE_FLAG_AM
                bne     destn_join_hop_bad
                bra     destn_join_route
destn_join_hop_bad
                ldb     #ERR_HOP_CONFLICT       ; $7DA4-$7DB6: $6A+1
                lbsr    error_report_beep       ; through $C3FE
                lbra    destn_join_refused
destn_join_arm_plse
                cmpb    #LBL_PULSE
                bne     destn_join_route        ; FM, Out1-Out4 and Off reach
                ldb     ,s                      ; an arm that refuses nothing
                lbsr    destn_record
                lda     ,x                      ; CHAN_FREQ is zero, and a
                                                ; symbolic zero offset is
                                                ; refused by the gate
                                                ; hp8904a-rewrite/tests/test_zero_offset.py
                cmpa    #PULSE_FREQ_HI          ; $7D30-$7D5F: the 24-bit
                blo     destn_join_plse_flag    ; frequency against $EA5F
                bhi     destn_join_plse_fast
                lda     CHAN_FREQ+1,x
                cmpa    #PULSE_FREQ_MID
                blo     destn_join_plse_flag
                bhi     destn_join_plse_fast
                lda     CHAN_FREQ+2,x
                cmpa    #PULSE_FREQ_LO
                bls     destn_join_plse_flag    ; exactly 50 kHz passes
destn_join_plse_fast
                ldb     #ERR_PULSE_FREQ         ; $7D5F: the second store
                lbsr    error_report_beep       ; wins, $6A+2, through $C3FE
                lbra    destn_join_refused
destn_join_plse_flag
                lda     >mode_flags             ; $7D1D: bit 5 of $2203
                bita    #MODE_FLAG_PULSE
                bne     destn_join_hop_bad
destn_join_route
                lda     ,s                      ; l7ddd: route_source_
                ldb     1,s                     ; selector(code, channel)
                lbsr    route_select
                lbra    destn_join_ok

; ---------------------------------------------------------------------------
; destn_route - move a channel from what it is routed to onto a destination
;
;   entry: A = the channel, B = the new destination code, already checked
;   exit:  carry CLEAR and the channel is routed, routed_dest holds the code
;          and CHAN_DEST holds it too when it is not Off; carry SET when one
;          of the three refusals that live inside the routing fired - E
;          below, or F or G in destn_join - and then the old routing has
;          been taken down all the same, routed_dest and CHAN_DEST both
;          read Off, and B comes back as Off because the stock's refusals
;          overwrite the destination argument itself ($7BC3, $7C7A, $7DCE
;          all STD #$0010 into >$001a,s). A comes back as given.
;   uses:  X, Y, U
;
; set_channel_destination ($78BF) from where its checks leave off, in its
; order, with the level side that used to be missing here - the routing
; words were the stock's and the level words that follow them in the stock
; were not written at all:
;
;   $79EE-$7A45  the LAST DSB modulator, leaving DSB ($79F1 CMPX #$000A,
;                $79F6 LDB >$240E / CMPB #$01), hands the carrier its level
;                and units: copy3 of record+10 to $24FF and record+15 to
;                $2504, record+13 to $2502 and record+$12 to $2507 - channel
;                0's record. The level is copied here; the units are what
;                ampl_unit_for_destn derives from channel 0's destination
;                once no DSB modulator is counted, and the amplitude step
;                (+15) has no per-channel home in this firmware.
;   $7A45-$7A8B  leaving any destination but Off zeroes the record's level
;                (+10) and step (+15) with the $EA58 zero constant and sets
;                both unit words to $0D. The level is zeroed here; the units
;                are derived.
;   $7A8B-$7AA9  $C069(channel, record+10): the level applied by the unit
;                word, which every path above has left as $0D - Off's
;                (destn_units_off_blank, $7E5F) when the channel was Off,
;                $7A6E's store otherwise - and arm [12] of the $C163 table,
;                chan_param_zero_no_apply, writes zero to the channel's
;                level register: ampl_program(channel, 0).
;   $7AA9-$7B77  destn_leave.
;   $7B7A-$7B7E  record+$21 <- $0010: routed_dest takes Off, so the join's
;                counts see this channel nowhere.
;   $7B7F-$7BC7  E, AM AGAINST DSB: the new code is 7 and $240E, the DSB
;                counter, is non-zero, or the new code is $0A and $240D, the
;                AM counter, is non-zero -> $69. The counters were
;                decremented for the old code at $7AB2, so they count the
;                other channels. l7bb3 reports it and then LDD #$0010 / STD
;                >$001a,s and FALLS THROUGH to l7bca: the destination
;                becomes Off and the rest of the routine runs on it.
;   $7BCA        recompute_channel_byte_24ec ($F7EC): filter_recompute_all,
;                which derives every channel's filter byte AND drives the
;                line, as $F7EC does through set_channel_byte_24ec ($F713)
;                and switch_channel_latch_bit0 ($F692). The stock makes this
;                call on every path through the routine, refused ones
;                included, and makes it again at $7ED8 with the new code;
;                that second one is the callers'. The evidence and what went
;                wrong without it are at the call site.
;   l7bca-l7c1b  THE VACATED SOCKET'S RELAY OPENS. With the old code's
;                counter at zero and port_code_to_channel ($C765) giving it a
;                socket, set_channel_latch_bit2 ($B67B)(socket, 0) sets bit 2
;                of that socket's latch - LATCH_OUTPUT, active low, so the
;                relay releases. destn_route_left below.
;   $7C1B-$7DF0  destn_join; the $7D92 arms on the way: AM without amplitude
;                hop ($7CB5) and DSB ($7D0F) set 10,s, the re-apply flag,
;                and DSB first zeroes channel 0's level and step ($7CE8-
;                $7D03 copy3 of $EA58 to $24FF and $2504) and sets its units
;                to $0E ($7D05-$7D0D) - the level is zeroed here, the unit is
;                derived from the DSB modulator being counted.
;   $7DF0-$7E01  the counter up and record+$21 <- the code: routed_dest, and
;                CHAN_DEST with it when the code is not Off - the level
;                re-apply below reads the unit from the record, and a caller
;                that stores CHAN_DEST itself afterwards stores the same
;                byte. Off leaves CHAN_DEST alone, for destn_park_all.
;   $7E8C-$7EB5  with the flag set, $C069(0, $24FF): ampl_carrier_reapply,
;                with no counter excluded - this channel is counted now.
;   $7EB8-$7EC5  $C069(channel, record+10) by the NEW unit: Off's $0D writes
;                zero (arm [12]); every other unit is ampl_reapply's
;                dispatch on the record - a depth, a deviation, degrees, the
;                pulse constant or a voltage through ampl_propagate - with
;                the sign the record carries in ampl_signs (+$14).
;
;   $7EC5-$7FD8  destn_tail: the tuning word re-sent as the new code wants
;                it, the modulator phase offset and the phase re-sent with
;                it, the $26 pulse, channels 1 and 2 re-derived when channel
;                3 changed, and program_channel_phase - on the refused leg
;                too, with Off, as the stock's l7c6e falls through to it.
;
; ALL THREE OF THE STOCK'S LATE REFUSALS ARE HERE, AND NONE OF THEM RETURNS.
; $69 at l7bb3, $6A at l7c6e and $6B/$6C at l7da4 each report the error and
; then execute LDD #$0010 / STD >$001a,s - the destination ARGUMENT is
; overwritten with Off - and carry on: l7bb3 falls through to l7bca, l7c95
; and l7dda both LBRA l7df0. So l7df0 stores $0010 into record+$21, the unit
; table at d7e78 gives Off's $0D, $7EB8's $C069 writes zero to the level
; register and $7EC5's tail runs with Off. The channel is left OFF, with the
; socket it was leaving already released by the l7bca block above, and never
; back on the destination it had.
;
; This routine used to be reached only after every check had passed, so a
; refused change left the standing destination on the socket. Measured with
; 'DEB OC1; DEA OC3; DEB OC4;': the stock's masked output latches are
; (4,4,0,0) and 'DEB?;' answers 00016 - Off; before this change they were
; (0,4,0,0) and 00012 - Out1, still driving the socket it had been told to
; leave. Only destn_check's own five refusals - $65, $66, $67, $99 and $68,
; every one of which the stock raises before $79EE - leave the routing
; alone, because the stock returns on those.
;
; The flag byte at 1,s is what turns a forced Off into carry for the
; caller. The stock needs no such byte: $78BF returns nothing at all
; ($7FDB LEAS $14,s / RTS) and the only record of a refusal is the error it
; reported and the channel sitting at Off.
; ---------------------------------------------------------------------------
destn_route
                pshs    a,b                     ; 0,s the channel, 1,s the code
                ldx     #routed_dest
                ldb     ,s
                abx
                ldb     ,x                      ; B = the old code, record+$21
                cmpb    1,s                     ; $7996: already routed there
                lbeq    destn_route_done        ; ($7998 CMPX / LBNE, then
                                                ; LBRA l7fdb - nothing at all)
                clra                            ; THE REFUSAL FLAG, zero until
                pshs    a                       ; one of the three late
                                                ; refusals forces the code to
                                                ; Off. Nothing in the stock
                                                ; corresponds to it: $78BF
                                                ; returns nothing and the
                                                ; refusal shows only as the
                                                ; channel being Off. The
                                                ; callers here read a carry,
                                                ; so it has to be remembered.
                pshs    b                       ; 0,s old  1,s the flag
                                                ; 2,s the channel  3,s the
                                                ; code - the stock's >$001a,s,
                                                ; and like it this cell is
                                                ; OVERWRITTEN with Off by a
                                                ; refusal, so everything below
                                                ; reads the destination that
                                                ; is actually being taken

                ; --- $79EE-$7A45: the last DSB modulator hands the carrier
                ;     its level ---------------------------------------------
                cmpb    #LBL_DSB
                bne     destn_route_keep
                lda     2,s
                lbsr    destn_count_others      ; $79F6: $240E == 1 before
                tstb                            ; the decrement is no OTHER
                bne     destn_route_keep        ; DSB modulator
                ldb     2,s
                lbsr    destn_record            ; X = this channel's record
                ldu     #channel_records        ; U = channel 0's
                ldd     CHAN_AMPL,x             ; $7A06-$7A1B copy3 to $24FF
                std     CHAN_AMPL,u
                lda     CHAN_AMPL+2,x
                sta     CHAN_AMPL+2,u
destn_route_keep
                ; --- $7A45-$7A8B: leaving a live destination zeroes the
                ;     level -------------------------------------------------
                ldb     ,s
                cmpb    #LBL_OFF                ; $7A45 CMPX #$0010 / LBEQ
                beq     destn_route_pre
                ldb     2,s
                lbsr    destn_record
                clr     CHAN_AMPL,x             ; $7A4E-$7A5D: copy3 of $EA58
                clr     CHAN_AMPL+1,x           ; into record+10
                clr     CHAN_AMPL+2,x
destn_route_pre
                ; --- $7A8B-$7AA9: $C069 by the unit word $0D - zero to the
                ;     level register ----------------------------------------
                ldx     #$0000
                ldb     2,s
                lbsr    ampl_program
                ; --- $7AA9-$7B77 -------------------------------------------
                lda     2,s
                ldb     ,s
                lbsr    destn_leave
                ; --- $7B7A-$7B7E: record+$21 <- Off ------------------------
                ldx     #routed_dest
                ldb     2,s
                abx
                lda     #LBL_OFF
                sta     ,x

                ; --- E. $7B7F-$7BC7: AM AGAINST DSB ------------------------
                ; AND IT DOES NOT RETURN. This test used to be made in
                ; destn_check, before anything moved, so a channel refused
                ; here kept the destination it had. The stock makes it HERE,
                ; three instructions after record+$21 has been set to Off and
                ; after destn_leave has already released the old routing, and
                ; l7bb3 does not end the routine: LDB #$69, error_report_beep
                ; ($C3FE), then LDD #$0010 / STD >$001a,s and straight on into
                ; l7bca. The channel finishes Off.
                ;
                ; $7B7F-$7B96 reads the new code and, for AM (7), the DSB
                ; counter $240E; $7B99-$7BAD reads it and, for DSB ($0A), the
                ; AM counter $240D. Either non-zero is $69. Both counters were
                ; decremented for the OLD code at $7AB2, so both count the
                ; other channels - which is what destn_count_others counts
                ; over routed_dest, and this channel's routed_dest is Off by
                ; now, so it excludes itself twice over and the answer is the
                ; same either way.
                ldb     3,s                     ; the new code
                cmpb    #LBL_AM
                bne     destn_route_e_dsb
                lda     2,s
                ldb     #LBL_DSB                ; $7B8B LDB >$240e
                lbsr    destn_count_others
                tstb
                bne     destn_route_e_refuse
                bra     destn_route_e_done
destn_route_e_dsb
                cmpb    #LBL_DSB
                bne     destn_route_e_done
                lda     2,s
                ldb     #LBL_AM                 ; $7BA2 LDB >$240d
                lbsr    destn_count_others
                tstb
                beq     destn_route_e_done
destn_route_e_refuse
                ldb     #ERR_AM_DSB_EXCL        ; $7BB3-$7BC1: $69, reported
                lbsr    error_report_beep       ; through $C3FE alone
                lda     #LBL_OFF                ; $7BC3: LDD #$0010 / STD
                sta     3,s                     ; >$001a,s
                inc     1,s                     ; and the flag the exit reads
destn_route_e_done

                ; --- $7BCA: THE FILTER LINE FOLLOWS THE RECORD ------------
                ; l7bca's first instruction group is
                ; recompute_channel_byte_24ec ($F7EC)(the OLD code), and it
                ; is not a bookkeeping call: its own tail, between the labels
                ; lf9bc and lf9d0, calls set_channel_byte_24ec ($F713), whose
                ; block from lf73a to lf76d calls switch_channel_latch_bit0
                ; ($F692) and DRIVES bit 0 of the channel latch.
                ; filter_recompute_all is that pair -
                ; filter_recompute derives the byte, filter_apply drives the
                ; line - so it is what belongs here. The argument is ignored:
                ; $F7EC walks all four records itself - its loop from lf85e
                ; to lf987 counts 8,s against 4 - and so does this.
                ;
                ; IT WAS LEFT TO THE CALLERS, and two things are wrong with
                ; that. A refusal changes the records, and every caller
                ; branches away on carry before its own call - so a refused
                ; change left the filter deriving from a destination the
                ; channel no longer has. And destn_park_all has no caller
                ; that makes the call at all: walking out of the channel
                ; screens parks four channels, and the stock recomputes on
                ; each one because $78BF is what it parks them with.
                ;
                ; WHAT IT RECOMPUTES FROM IS NOT YET WHAT THE STOCK READS,
                ; and that half is not in this file. $F7EC walks each
                ; record's +$21 - the LIVE routing, which is routed_dest
                ; here, and which $7B7A set to Off four instructions ago.
                ; filter_auto_bit, in the screens_main module, walks
                ; CHAN_DEST instead, and CHAN_DEST still holds the old code
                ; at this point, so today this call recomputes the same
                ; answer and drives nothing. It is $78BF's own instruction
                ; and it stands where $78BF has it; what it is waiting on is
                ; the field.
                ;
                ; The cost of that is measured. Seed 13 step 12 of the
                ; differential harness, Channel Config. to Digital Sequence
                ; with A..D on Out1..Out4: the stock's masked latches are
                ; (1,4,4,4) and this firmware's are (1,4,4,0). The park opens
                ; all four relays on both, but channel D's filter bit is left
                ; standing here where the stock clears it, so the next mode's
                ; entry has a filter change to make on D, blanks and UNBLANKS
                ; it, and the unblank closes the relay again with nothing
                ; behind it. Both ends of that are outside this file:
                ; filter_auto_bit reads the record, and the record is parked
                ; by channel_park_destinations AFTER destn_park_all has run,
                ; so no recompute follows it - measured, CHAN_DEST is
                ; [12,13,14,15] while this runs and [16,16,16,16] once the
                ; mode exit is done.
                lbsr    filter_recompute_all

                ; --- l7bca-l7c1b: THE VACATED SOCKET'S RELAY OPENS ---------
                ; THE OUTPUT THE CHANNEL WALKED AWAY FROM WENT ON DRIVING.
                ; Nothing here released it, so after 'DEA OC2;' with A on Out1
                ; the Out1 relay stayed closed with no channel behind it -
                ; whatever was connected to that socket kept whatever the
                ; hardware happened to leave on it. Measured on both
                ; firmwares through scripts/acceptance.py case 4.4: the four
                ; masked output latches came back (4,0,0,0) on the stock and
                ; (0,0,0,0) here.
                ;
                ; The stock's block, read out of a2u13_page0 between the
                ; labels l7bca and l7c1b - it follows $7B7A's record+$21 <-
                ; $0010 and the $69 check, and it runs before l7c1b's join.
                ; LDB [<$07,S] / CMPB #$00 / LBNE l7c1b reads the OLD code's
                ; counter through the pointer destination_use_count_addr
                ; ($782A) left at 7,s, already
                ; decremented at $7AB2, and only zero - no other channel left
                ; on it - reaches the rest. It then calls port_code_to_channel
                ; ($C765) with the old code, which gives 0 to 3 for Out1-Out4
                ; and $FF for anything else, and CMPD #$00FF / LBEQ l7c05 with
                ; CMPB #$03 / LBHI l7c05 send every other code straight past.
                ; l7c08 then calls set_channel_latch_bit2 ($B67B) with that
                ; socket and a second argument of ZERO, and zero is the arm at
                ; lb6c5: value $04 through mask $04, so bit 2 is SET, and
                ; LATCH_OUTPUT is active low (hardware.inc, "CLEAR IS ON") -
                ; the relay OPENS.
                ;
                ; lb6c5 reads $23C1 and returns without asserting when bit 4
                ; is set - special function 4, "Disable output blanking",
                ; SPECIAL_NO_BLANK here, the same veto ampl_blank honours.
                ; $B67B's own entry guard, CMPX #$0003 / LBLS lb68f with
                ; everything above 3 falling straight through to its exit, is
                ; the CMPB #$03 above by another route; ampl_partner is $C765
                ; and already answers $FF for everything that is not a socket.
                ldb     ,s                      ; the old code
                lbsr    ampl_partner            ; $C765: 0-3, or $FF
                cmpb    #$FF                    ; CMPD #$00FF, CMPB #$03
                beq     destn_route_left
                pshs    b                       ; 0,s socket  1,s old code
                                                ; 2,s the flag  3,s channel
                                                ; 4,s the code
                lda     3,s
                ldb     1,s
                lbsr    destn_count_others      ; LDB [<$07,S]: the counter
                tstb                            ; after $7AB2's decrement,
                bne     destn_route_left_done   ; the other channels on it
                lda     >special_flags          ; lb6c5: $23C1 bit 4
                bita    #SPECIAL_NO_BLANK
                bne     destn_route_left_done
                inc     >dds_lock               ; THE STORE AND THE CALL ARE
                                                ; ONE OPERATION. An NMI landing
                                                ; between them would leave this
                                                ; writing the sequence player's
                                                ; value into a channel latch;
                                                ; see channel_latch_rmw.
                lda     #LATCH_OUTPUT
                sta     >latch_bits             ; SET is off: lb6c5's value $04
                lda     #LATCH_OUTPUT           ; through lb6c5's mask $04
                ldb     ,s                      ; the socket
                lbsr    channel_latch_rmw
                dec     >dds_lock
destn_route_left_done
                leas    1,s                     ; the socket
destn_route_left
                ; --- $7C1B-$7DF0 -------------------------------------------
                lda     2,s
                ldb     3,s
                lbsr    destn_join
                bcs     destn_route_refused
                ldb     3,s                     ; $7CE8-$7D03: DSB zeroes the
                cmpb    #LBL_DSB                ; carrier's level
                bne     destn_route_joined
                ldx     #channel_records
                clr     CHAN_AMPL,x
                clr     CHAN_AMPL+1,x
                clr     CHAN_AMPL+2,x
                bra     destn_route_joined
destn_route_refused
                ; F AND G REFUSED, AND THE ROUTINE GOES ON. $7C6E's $6A and
                ; $7DA4's $6B/$6C are already reported by destn_join; what is
                ; left is the two instructions each of them runs next - LDD
                ; #$0010 / STD >$001a,s at $7C7A and $7DCE - and l7c95 /
                ; l7dda's LBRA l7df0, which is the fall-through below. It
                ; skips the DSB block above, which is right: those are arm
                ; [3]'s writes at $7CE8-$7D03 and the arm did not accept.
                lda     #LBL_OFF
                sta     3,s
                inc     1,s
destn_route_joined
                ; --- $7DF0-$7E01: the record follows the routing -----------
                ldx     #routed_dest
                ldb     2,s
                abx
                lda     3,s
                sta     ,x
                cmpa    #LBL_OFF
                bne     destn_route_dest_set
                tst     1,s                     ; A DESTINATION OF Off LEAVES
                beq     destn_route_flag        ; CHAN_DEST STANDING, for
                                                ; destn_park_all's account -
                                                ; but Off REACHED BY REFUSAL
                                                ; is a destination the channel
                                                ; now has, and l7df0 stores
                                                ; $0010 into record+$21 on
                                                ; that leg like any other. The
                                                ; stock has one field where
                                                ; this has two, so both take
                                                ; it: 'DEB?;' answers Off, and
                                                ; the DESTN column shows Off.
destn_route_dest_set
                ldb     2,s
                lbsr    destn_record
                lda     3,s
                sta     CHAN_DEST,x
destn_route_flag
                ; --- $7E8C-$7EB5: AM without amplitude hop, or DSB, re-apply
                ;     the carrier ($7C9F's 10,s at $7CB5, $7CD2's at $7D0F) -
                ldb     3,s
                cmpb    #LBL_DSB
                beq     destn_route_carrier
                cmpb    #LBL_AM
                bne     destn_route_post
                lda     >mode_flags             ; $7C9F: bit 6 of $2203 set
                bita    #MODE_FLAG_AM           ; is arm [0]'s own refusal in
                bne     destn_route_post        ; destn_join; clear sets 10,s.
                                                ; A refused code is Off by
                                                ; now and reaches neither arm
destn_route_carrier
                lda     #$FF                    ; every counter is up to date
                lbsr    ampl_carrier_reapply    ; $7EA6: $C069(0, $24FF)
destn_route_post
                ; --- $7EB8-$7EC5: $C069(channel, record+10) by the new unit
                ldb     3,s
                cmpb    #LBL_OFF
                bne     destn_route_post_set
                ldx     #$0000                  ; $0D: arm [12], zero - and
                ldb     2,s                     ; this is the leg a refusal
                lbsr    ampl_program            ; takes, the code being Off
                bra     destn_route_end
destn_route_post_set
                ldb     2,s
                lbsr    destn_record            ; X = the record
                ldb     2,s                     ; B = the channel
                lbsr    ampl_reapply            ; $C069: the unit's arm on
                                                ; the record's level, with
                                                ; no entry check - a Plse
                                                ; channel's $0555 goes out
                                                ; though nothing can be typed
destn_route_end
                lda     ,s                      ; --- $7EC5-$7FD8: the old
                ldb     2,s                     ; code and the channel, and
                lbsr    destn_tail              ; l7c6e falls into it too
                tst     1,s                     ; the flag: was the code
                bne     destn_route_bad         ; forced to Off?
                leas    2,s                     ; the old code and the flag
                puls    a,b
                andcc   #~CC_CARRY
                rts
destn_route_bad
                ; AND $7ED8's RECOMPUTE, WHICH NOTHING ELSE WILL MAKE FOR A
                ; REFUSAL. The stock runs recompute_channel_byte_24ec ($F7EC)
                ; twice inside $78BF and the refused legs reach both: l7bb3
                ; falls through to l7bca, and l7c95 and l7dda both LBRA
                ; l7df0, which runs on through $7ED8 - by which point l7df0
                ; has stored $0010 into record+$21, so the second call is the
                ; one that sees the channel Off. Here that second call
                ; belongs to the callers - page0_screen's
                ; chan_cycle_dest_store and remote.s's mode arm each make it
                ; once destn_apply has returned - and both branch away on
                ; carry, so for a refusal neither does. CHAN_DEST is Off by
                ; now (destn_route_dest_set, above), which is what
                ; filter_auto_bit reads, so this is the point where the
                ; recompute has the same input the stock's $7ED8 call has.
                lbsr    filter_recompute_all
                leas    2,s                     ; the old code and the flag
                puls    a,b                     ; B comes back Off, as the
                orcc    #CC_CARRY               ; stock's own argument slot
                rts                             ; does
destn_route_done
                puls    a,b
                andcc   #~CC_CARRY
                rts

; ---------------------------------------------------------------------------
; destn_tail - what set_channel_destination does after the level re-apply
;
;   entry: A = the destination code the channel was routed to before,
;          B = the channel; routed_dest already holds the new code
;   exit:  the chip's frequency and phase registers for the channel agree
;          with the new destination; A and B come back as given
;   uses:  X, Y, U
;
; set_channel_destination ($78BF), $7EC5-$7FD8, executed on the stock over
; the bus on 2026-09-02 and written from what it sent. 'DEB FM;' on channel
; B at 1 kHz, after the level words: $033F $023D $0123 $0030 $0900, $033F
; $0231 $1100, $2603 $260B, $033F $0231 $1100.
;
;   $7ECE-$7EDB  recompute_channel_byte_24ec ($F7EC) with the code: the
;                filter, which returns at $F7F2 for Off and otherwise
;                derives the line from the records. filter_apply, which
;                every caller of destn_apply runs once it has returned
;                (remote.s remote_mode_dest, page0_screen.s chan_cycle_dest_
;                store) - it writes a latch, not the chip, so its place in
;                the order leaves the chip's words as they are.
;   $7EDD-$7EEE  is_modulation_destination ($77D9) of the code chooses the
;                leg: label_is_modulation of routed_dest.
;   $7EF2-$7F02  copy_or_negate_to_channel_reg_08 ($E319)(channel, record):
;                the tuning word negated unless $23C1 bit 3 - the first five
;                words above; $7F31-$7F41 write_channel_reg_08 ($E2C1) sends
;                it as it is for a socket or Off. freq_program_routed, which
;                chooses on the same two facts.
;   $7F04-$7F22  scale_channel_value_by_6_or_7 ($E8A7)(channel) into
;                set_channel_word_24cd ($E5BF)(channel, D): the offset from
;                the word just sent - $FF15 here, 6 x $FFD8F0 >> 8 - stored
;                and register $11 re-sent from the fraction last programmed
;                plus it, $033F $0231: ($0000 + $FF15 + 8) >> 4 = $FF1.
;                $7F43-$7F54 store zero for the other leg. phase_offset_
;                compute, then phase_apply_as by the OLD code, which is the
;                fraction $24C5 holds (phase.s says why).
;   $7F24-$7F2C  dds_reg26_pulse_if_flag1_clear ($DEB6): $2603 $260B unless
;                $23C1 bit 1 - dds_phase_reset; $7F56-$7F5E on the other leg.
;   $7F60-$7FCA  when THIS channel is 3, channels 1 and 2 whose record+$21
;                is a modulation code get $E8A7/$E5BF again - their
;                multiplier depends on whether their code equals channel
;                3's, which has just changed. 'DED FM;' with B on AM: $033F
;                $022F $1300 for D, then $032F $0231 $1100 for B, then D's
;                $033F $022F $1300 again. Channel 0 is never a modulator and
;                the loop starts at 1 ($7F6B LDB #$01).
;   $7FCC-$7FD9  program_channel_phase ($6635)(channel): the phase negated
;                by the NEW code, through set_channel_phase - phase_apply.
;
; EVERY REFUSED DESTINATION REACHES ALL OF THIS WITH Off IN $1A,s, and that
; is not an exception to the routine - it is the routine's ordinary input.
; l7bb3, l7c6e and l7da4 each overwrite the destination argument with $0010
; and go on to l7df0, so $7EC5 is entered with Off exactly as a requested
; Off enters it, and destn_route's single call covers both.
; ---------------------------------------------------------------------------
destn_tail
                pshs    a,b                     ; 0,s the old code, 1,s the
                                                ; channel
                ; --- $7EDD-$7F02, $7F31-$7F41: the tuning word ------------
                ldb     1,s
                lbsr    freq_program_routed
                ; --- $7F04-$7F22, $7F43-$7F54: the offset, and the phase
                ;     as last sent with it --------------------------------
                ldb     1,s
                lbsr    phase_offset_compute
                lda     ,s
                ldb     1,s
                lbsr    phase_apply_as
                ; --- $7F24-$7F2C, $7F56-$7F5E: the pulse -------------------
                lbsr    dds_phase_reset
                ; --- $7F60-$7FCA: channel 3 changed ------------------------
                ldb     1,s
                cmpb    #$03
                bne     destn_tail_phase
                ldb     #$01                    ; $7F6B
destn_tail_others
                pshs    b
                ldx     #routed_dest
                abx
                ldb     ,x                      ; $7F89-$7F9F: record+$21 of
                lbsr    label_is_modulation     ; channel 1, then 2
                bcc     destn_tail_next
                ldb     ,s
                lbsr    phase_offset_compute    ; $7FA3-$7FC2: $E8A7/$E5BF,
                ldb     ,s                      ; the fraction that channel
                lbsr    phase_apply             ; last sent, under its own
                                                ; unchanged code
destn_tail_next
                puls    b
                incb                            ; $7FC4-$7FCA
                cmpb    #$03
                blo     destn_tail_others
destn_tail_phase
                ; --- $7FCC-$7FD9: program_channel_phase -------------------
                ldb     1,s
                lbsr    phase_apply
                puls    a,b
                rts

; ---------------------------------------------------------------------------
; destn_apply - route a channel to a destination
;
;   entry: A = the channel, B = the destination code
;   exit:  carry CLEAR and the channel is routed, routed_dest and CHAN_DEST
;          both holding the code. Carry SET means refused, and WHICH refusal
;          decides what is left: destn_check's five ($65, $66, $67, $99,
;          $68) leave the channel exactly as it stood, because the stock
;          returns on those; the three inside the routing ($69, $6A,
;          $6B/$6C) leave it Off, its socket released and both destination
;          fields reading Off, because the stock forces the argument to
;          $0010 and finishes the routine
;   uses:  A, B, X, Y, U
;
; set_channel_destination ($78BF): destn_check, then destn_route from where
; the checks leave off - the old destination gives the channel up
; (destn_leave, $7AA9-$7B77), the new one takes it (destn_join, $7C1B-
; $7DF0), the levels the stock re-applies around those go out in its order,
; and the record follows ($7DF9-$7E01 store the code into record+$21) -
; routed_dest, and CHAN_DEST with it so that a caller that stores CHAN_DEST
; itself afterwards stores the same byte, and a caller that does not (the
; bus) is not left with a record that disagrees with the sockets.
;
; A CHANNEL MAY NOT MODULATE ITSELF. The hardware would happily be told to,
; and the result is a feedback path with no defined output. Refusing is the
; only sensible answer and the stock firmware's own tables have no code for
; it either.
; ---------------------------------------------------------------------------
destn_apply
                pshs    a,b                     ; 0,s the channel, 1,s the code

                ; THE CHECKS THAT COME FIRST IN THE STOCK COME FIRST HERE,
                ; AND NO OTHERS. destn_check above is $78D0-$79EB: $65, $66,
                ; $67, $99 and $68, the five errors set_channel_destination
                ; raises before $79EE. Every one of them ends the stock's
                ; routine at l7fdb with the routing untouched, so this one
                ; records and sounds the error and returns carry set with
                ; nothing torn down and nothing written.
                ;
                ; THE OTHER THREE ARE NOT CHECKS AND ARE NOT HERE. $69 at
                ; l7bb3, $6A at l7c6e and $6B/$6C at l7da4 all fire after the
                ; old routing has gone, and each follows its
                ; error_report_beep ($C3FE) with LDD #$0010 / STD >$001a,s
                ; and carries on to the end of the routine, so the channel is
                ; left Off with the vacated socket released. They are in
                ; destn_route and destn_join, at the addresses they occupy,
                ; and destn_route brings the carry back for them.
                ;
                ; This header used to call the up-front refusal a recorded
                ; departure. It was not recorded: the owner made no
                ; ruling for it, and only the architect's own words in a
                ; file make a departure a departure. The standard is the
                ; instrument, and the instrument dismantles first.
                lbsr    destn_check
                bcs     destn_apply_refused

                ; THE OLD DESTINATION IS WHAT THE CHANNEL IS ROUTED TO,
                ; routed_dest - the stock's record+$21, read at $78C5 and
                ; written only after routing at $7DF9. It is not CHAN_DEST:
                ; a recall copies the saved block over CHAN_DEST before
                ; register_apply routes anything, so the record has already
                ; forgotten what the sockets carried - which is why the
                ; recall parks first (register_restore) and why destn_route
                ; reads routed_dest. (Before that it was destn_current, ONE
                ; GLOBAL BYTE holding whatever destination was set last on
                ; any channel, and a recalled setup came up with three of
                ; its four sockets silent.)
                lda     ,s
                ldb     1,s
                lbsr    destn_route             ; $79EE-$7EC5
                bcs     destn_apply_refused     ; l7bb3, l7c6e or l7da4: the
                                                ; error is already recorded
                                                ; and destn_route has already
                                                ; put Off in routed_dest and
                                                ; in CHAN_DEST, so there is
                                                ; nothing left to store
                ldb     ,s                      ; $7DF9-$7E01's record, for
                lbsr    destn_record            ; Off as well - destn_route
                lda     1,s                     ; leaves CHAN_DEST alone for
                sta     CHAN_DEST,x             ; Off, on destn_park_all's
                                                ; account
                puls    a,b
                andcc   #~CC_CARRY
                rts
destn_apply_refused
                puls    a,b
                orcc    #CC_CARRY
                rts
