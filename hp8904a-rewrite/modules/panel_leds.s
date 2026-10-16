; ===========================================================================
; modules/panel_leds.s - the six front-panel lamps at $0900
;
; NOTHING IN THIS FIRMWARE LIT A LAMP. `grep -rn status_led modules/*.s`
; returned two hits, both of them comments in common/hardware.inc, and none
; at all in any module - so every front-panel lamp stayed in whatever state
; the hardware powers up in, for the life of the instrument. The stock drives
; six of them.
;
; THE MAP, read out of the stock's own lamp block at $9A37-$9A87 rather than
; from any document. Every routine there loads a constant and joins one of
; two tails: `l9a78 ORA >$2420` sets bits, `l9a7f ANDA >$2420` clears them,
; and both then write the shadow and $0900. So the port is ACTIVE LOW - a
; clear bit is a lit lamp - and the constants name the bits:
;
;   status_leds_all_off ($9A37)  LDA #$3F / STA >status_led   six lines, all off
;   status_leds_all_on  ($9A7D)  LDA #$C0 / AND              six lines, all on,
;                                                            bits 7:6 preserved
;   bit 0   on $FE   off $01
;   bit 1   on $FD   off $02
;   bit 2   on $FB   off $04
;   bit 3   on $F7   off $08
;   bit 4   on $EF   off $10     OUTPUT 1
;   bit 5   on $DF   off $20     OUTPUT 2
;
; `status_leds_all_on` masking with $C0 rather than $3F is the proof that
; there are exactly six lamps and that bits 7 and 6 are something else: an
; "all on" that deliberately preserves two bits is not treating them as
; lamps. common/hardware.inc records those two as NOT ESTABLISHED and this
; module never touches them - every routine here masks to LED_ALL.
;
; BITS 3:0 ARE NOT DRIVEN HERE. In the stock they are annunciators for the
; interface at $0400-$0407, which this firmware does not implement, so there
; is no state to show. They are defined below so that "all off" means all
; six and not just the two with a writer - a lamp left lit by the previous
; firmware has to be put out whether or not this one ever lights it again.
;
; WHICH BIT IS WHICH OUTPUT, established from the stock's use rather than
; from the constants: update_output_leds ($B72F) takes a channel argument of
; 0 or 1 and nothing else - "arguments above 1 do nothing" - and for 0 it
; drives bit 4 from the byte at $23B3, for 1 bit 5 from $23B4. $23B3+ch is
; written only by set_output_enable ($B79C), $FF when the output is switched
; on and $00 when it is switched off. So bit 4 follows channel 0's output
; relay and bit 5 follows channel 1's, and channels 2 and 3 have no lamp.
; ===========================================================================

LED_OUTPUT1     equ     $10             ; bit 4, channel 0's output lamp
LED_OUTPUT2     equ     $20             ; bit 5, channel 1's output lamp
LED_ALL         equ     $3F             ; the six lamp lines, and the mask
                                        ; that keeps bits 7:6 out of reach
LED_OUTPUT_LAMPS equ    2               ; only channels 0 and 1 have a lamp

; ---------------------------------------------------------------------------
; led_init - every lamp out, shadow and port agreeing
;
;   uses:  A
;
; THE PORT IS WRITE-ONLY like the channel latches, so the shadow is the only
; readable copy and it has to be made true rather than assumed. Writing both
; from one known constant is the only way to start out correct; reading the
; port back is not an option.
;
; This is the stock's status_leds_all_off ($9A37) exactly: LDA #$3F, store to
; the port and to the shadow.
; ---------------------------------------------------------------------------
led_init
                lda     #LED_ALL                ; every line high is every
                sta     >led_shadow             ; lamp dark, and the shadow
                sta     >status_led             ; must say so too
                rts

; ---------------------------------------------------------------------------
; led_on - light the lamps a mask names
;
;   entry: A = the lamps, one bit each (LED_OUTPUT1, LED_OUTPUT2, ...)
;   uses:  A
;
; The bits are cleared, because the port is active low. The mask is limited
; to LED_ALL first so that a caller cannot reach bits 7 and 6. Their meaning
; is not established: every value the five stock images write to $0900 was
; enumerated, and bits 7 and 6 are set and cleared INDIVIDUALLY - ORB #$40,
; ORB #$80, ANDB #$7F, ANDB #$BF - which is flag behaviour and not lamp
; behaviour, while status_leds_all_on ($9A7D) masks with $C0 rather than $3F
; and so refuses to touch them at all. common/hardware.inc carries the same
; finding. A lamp routine that can write an unknown control line is a lamp
; routine that will eventually be used to write one by accident.
; ---------------------------------------------------------------------------
led_on
                anda    #LED_ALL                ; bits 7:6 are not ours
                coma                            ; the wanted lamps become
                anda    >led_shadow             ; zeros in a mask of ones
                bra     led_write

; ---------------------------------------------------------------------------
; led_off - put out the lamps a mask names
;
;   entry: A = the lamps, one bit each
;   uses:  A
;
; The same routine with the sense reversed, and it falls into the same write.
; ---------------------------------------------------------------------------
led_off
                anda    #LED_ALL
                ora     >led_shadow
led_write
                sta     >led_shadow             ; shadow first, then the port,
                sta     >status_led             ; so the two can never differ
                rts                             ; by more than one instruction

; ---------------------------------------------------------------------------
; led_output_refresh - the two output lamps, from the channel records
;
;   uses:  A, B, X
;
; The stock keeps a per-channel byte at $23B3 that set_output_enable ($B79C)
; writes alongside the relay, and update_output_leds ($B72F) reads it back.
; This firmware already keeps that state, in CHAN_STATE bit 0 of each channel
; record, written by chan_state_sync from the latch itself - so the lamp is
; driven from the same place the relay is, and the two cannot drift.
;
; Channels 2 and 3 have no lamp on this front panel, which is why the loop
; stops at two rather than at CHANNEL_MAX. That is the stock's behaviour and
; not a shortcut: update_output_leds returns without acting for any argument
; above 1.
; ---------------------------------------------------------------------------
led_output_refresh
                clrb                            ; channel 0 drives bit 4
led_output_next
                pshs    b
                lda     #CHAN_RECORD
                mul                             ; D = channel * 12
                ldx     #channel_records
                leax    d,x
                lda     CHAN_STATE,x            ; bit 0 is "output on"
                anda    #CHAN_STATE_ON
                ldb     ,s                      ; the channel again
                pshs    a                       ; keep the on/off answer
                lda     #LED_OUTPUT1            ; channel 0's lamp, and
                tstb                            ; channel 1's is the next bit
                beq     led_output_have_mask
                lda     #LED_OUTPUT2
led_output_have_mask
                tst     ,s+                     ; on, or off?
                beq     led_output_dark
                lbsr    led_on
                bra     led_output_step
led_output_dark
                lbsr    led_off
led_output_step
                puls    b
                incb
                cmpb    #LED_OUTPUT_LAMPS
                blo     led_output_next
                rts

; ---------------------------------------------------------------------------
; led_all_on - every lamp lit, for the power-on lamp test
;
;   uses:  A
;
; The stock's status_leds_all_on ($9A7D): LDA #$C0 and AND into the shadow,
; which lights all six and leaves bits 7:6 exactly as they were. Reached here
; by handing led_on the whole lamp mask, which computes the same $C0.
;
; This is half of a LAMP TEST, and the other half is led_all_off. power_on_init
; ($81AD) lights them at $8296, runs lcd_init ($D9E6) and
; power_on_memory_selftest, waits delay_ms ($D670)($012C) - 300 ms - and puts
; them out again with lamp_test_off ($9A76) at $82AD. An operator watching the
; front panel sees every indicator come up and go out, which is how a dead
; lamp is found.
; ---------------------------------------------------------------------------
led_all_on
                lda     #LED_ALL
                bra     led_on

; ---------------------------------------------------------------------------
; led_all_off - every lamp out, WITHOUT disturbing bits 7:6
;
;   uses:  A
;
; The stock keeps these as two different routines and the difference is real.
; lamp_test_off ($9A76) loads $3F and joins the ORA tail, so bits 7 and 6 keep
; whatever they held; status_leds_all_off ($9A37) STORES $3F, which clears
; them. led_init is the storing one and this is the OR one, and the lamp test
; ends with this so that it cannot clear two lines whose meaning
; common/hardware.inc records as not established.
; ---------------------------------------------------------------------------
led_all_off
                lda     #LED_ALL
                bra     led_off

; ---------------------------------------------------------------------------
; led_line6_assert - put bit 6 of $0900 into the state a power-on leaves it in
;
;   uses:  A
;
; BIT 6 IS NOT A LAMP and this does not pretend to know what it is. What IS
; established is the state the stock leaves it in, and this firmware had the
; opposite one.
;
; The stock's sequence: reset_panel_ports ($D524) reaches status_leds_all_off
; ($9A37), which STORES $3F - clearing bits 7 and 6 - and then
; set_flag7_and_led6_off ($DB5C) ORs $40 back in at $827A, at $878D, and in
; instrument_preset ($C6EA) at $C738. The port is active low, so bit 6 ends
; HIGH at power-on and HIGH after every preset. led_init here stores $3F and
; nothing put it back, so this firmware came up with that line LOW - the
; other way round from every instrument HP shipped.
;
; Reproducing a state that was read is not guessing. Reproducing the TIMEOUT
; that releases it would be: clear_lamp_and_flag ($DB8B) ANDs $BF after
; foreground_main_loop ($83A0) has wrapped a $0FDD counter eighteen times
; ($8792, $882A, $8854 CMPB #$12), and that interval is in passes of a
; thirty-four arm event executive this firmware does not have. Passes are not
; a unit that converts - the same problem the arrow auto-repeat had, and there
; the ROM at least gave a rate to aim at. Here it does not, and what the line
; drives is not established either, so the idle release is left out and
; OPEN.txt says so.
;
; That is the conservative half: the stock spends almost all of its time in
; this state, and departs from it only after a long idle.
; ---------------------------------------------------------------------------
LED_LINE6       equ     $40             ; bit 6. NOT one of the six lamps -
                                        ; status_leds_all_on ($9A7D) masks
                                        ; with $C0 rather than $3F and so
                                        ; refuses to touch it or bit 7.

led_line6_assert
                lda     >led_shadow
                ora     #LED_LINE6
                sta     >led_shadow
                sta     >status_led
                rts

; ===========================================================================
; The display backlight, and its three-minute idle timeout
;
; WHAT BIT 6 OF $0900 IS. The service manual does not say - it has no A2
; schematic, no memory map and no register table at all, because HP withheld
; them: printed page 8-23 ends "Because some circuits on the assembly are
; proprietary and because the assembly is available as an exchange assembly,
; a schematic diagram with detailed theory and troubleshooting has not been
; provided." So no document in this repository maps a bit to a pin.
;
; It is identified here as the display backlight enable, and that is a
; READING rather than something either source states. Four things support it
; and they are independent:
;
;   1. The manual, printed page 8-41, verbatim: "The display backlighting
;      automatically turns off approximately 3 minutes after the last
;      keystroke. Pressing any key will turn the backlighting back on."
;
;   2. The stock's bit 6 has exactly that shape. foreground_main_loop ($83A0)
;      reloads a counter with $0FDD at $8792 whenever a key is serviced and
;      asserts the bit through set_flag7_and_led6_off ($DB5C); $882A
;      increments the counter and $8854 CMPB #$12 releases the bit through
;      clear_lamp_and_flag ($DB8B) after eighteen wraps.
;
;   3. The only other named A2 function that could be a spare bit is the
;      beeper, and the beeper is NOT a $0900 bit: ptm_t1_output_pulse ($D6C8)
;      ORs $80 into the MC6840 CR1 shadow, which is CRX7, timer 1's OUTPUT
;      ENABLE. That is established from the ROM, not from the manual.
;
;   4. The keyboard scan strobe is ruled out on the same part - the manual's
;      printed page 8-39 puts scan drive on U1 and the returns on U3, while
;      the six annunciators are U2 pins 12-17.
;
; THE POLARITY FALLS OUT OF IT. The stock ORs $40 on a keystroke and ANDs $BF
; after the idle, so bit 6 HIGH is the backlight ON - active high, opposite to
; the six lamp lines below it, which is consistent with status_leds_all_on
; ($9A7D) masking with $C0 and refusing to touch it.
;
; AND THE INTERVAL COMES FROM THE MANUAL, not from loop passes. The stock's
; eighteen wraps of $0FDD are 73,098 passes of a thirty-four arm event
; executive this firmware does not have, and passes do not convert - that is
; what left this unported for six rounds. Three minutes does convert, and it
; is counted here in milliseconds off timer 1.
;
; IF THE READING IS WRONG, what happens is that a line already driven by the
; stock is driven the same way on the stock's own schedule. The beeper is
; excluded on ROM evidence, so the failure mode is not a continuous tone. It
; is a bit that has always been asserted here becoming un-asserted after
; three idle minutes, which is what the instrument in the machine does.
; ===========================================================================
; THE TIMEOUT IS SETTABLE, AND THE SECOND IS A REAL ONE. The architect's
; addition of 2026-09-17: backlight_kind says whether
; the display is the original or an aftermarket backlit one, backlight_secs
; holds 5 to 999 seconds or 0 for Off, and an aftermarket display has no
; timeout at all.
;
; AND THE FLAG IS NOT A MILLISECOND. This counted timer 1's flag as one, which
; is why a labelled three minutes was about twenty-two seconds: the flag is
; 211 Enable clocks, 125 microseconds, and the foreground does not see every
; one of them. The half second the banner's star already steps by - measured
; at 507 ms, STAR_STEP_MS in service_prompts.s - is the unit here too, so a
; second is two of them and both counts come off the one flag read.
BL_HALVES_PER_S equ     2

; ---------------------------------------------------------------------------
; backlight_wake - a key was pressed: light it and restart the timeout
;
;   uses:  A, B, X - the foreground's key is in B when it calls this, so B is
;          saved
; ---------------------------------------------------------------------------
backlight_wake
                pshs    b
                lbsr    led_line6_assert        ; ON, and bit 6 high is on
                lbsr    backlight_reload        ; and its timeout starts again
                puls    b
                rts

; ---------------------------------------------------------------------------
; backlight_reload - put the setting's seconds back on the clock
;
;   uses:  A, B, X
;
; A machine whose setting has never been answered ($5A is not in
; backlight_set) has no timeout until it is: the first-time screen asks, and
; until then the lamp stays on rather than going dark on a number nobody
; chose.
; ---------------------------------------------------------------------------
backlight_reload
                clr     >backlight_left         ; no timeout unless the
                clr     >backlight_left+1       ; setting asks for one
                lda     #BL_HALVES_PER_S
                sta     >backlight_half
                ldd     #STAR_STEP_MS           ; AND THE HALF SECOND ITSELF,
                std     >star_ms                ; which banner_arm seeds only
                                                ; on a screen with stars: on
                                                ; the Main Selection Level it
                                                ; was zero and the timeout
                                                ; never counted at all
                lda     >backlight_set
                cmpa    #BACKLIGHT_MAGIC
                bne     backlight_reload_done   ; never answered
                lda     >backlight_kind
                cmpa    #BL_ORIGINAL            ; an aftermarket display
                bne     backlight_reload_done   ; never times out
                ldx     >backlight_secs
                stx     >backlight_left         ; 0 is Off, and that is the
backlight_reload_done                           ; same as no timeout here
                rts

; ---------------------------------------------------------------------------
; display_tick - one pass of the foreground, and the one place timer 1's flag
;                is consumed
;
;   uses:  A, B, X
;
; Two things are counted off it: the banner's walking star, half a second a
; step, and the backlight's idle seconds, two steps to the second.
; ---------------------------------------------------------------------------
display_tick
                lda     >ptm_status
                bita    #PTM_T1_FLAG
                beq     display_tick_done
                ldx     >ptm_timer1             ; the read completes the clear
                lbsr    banner_tick             ; carry SET when a half second
                bcc     display_tick_done       ; of it has just gone
                dec     >backlight_half
                bne     display_tick_done
                lda     #BL_HALVES_PER_S
                sta     >backlight_half
                ldx     >backlight_left         ; no timeout running
                beq     display_tick_done
                leax    -1,x
                stx     >backlight_left
                bne     display_tick_done
                bra     backlight_off           ; the idle time is up: OUT
display_tick_done
                rts

backlight_off
                clr     >backlight_s
                clr     >backlight_ms
                clr     >backlight_ms+1
                lda     >led_shadow
                anda    #~LED_LINE6
                sta     >led_shadow
                sta     >status_led
                rts
