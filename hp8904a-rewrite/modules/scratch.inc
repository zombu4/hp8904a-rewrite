; ===========================================================================
; scratch.inc - working storage for the rewrite
;
; $2000-$3FFF is battery-backed RAM. Part of it is untouchable: the serial
; number and the installed options are already in the
; instrument and ram.inc says where. The rest is ordinary read/write memory
; and this is where the rewrite's own working variables live.
;
; Everything here is scratch. Nothing in this file needs to survive a power
; cycle, and nothing in it may ever be given an address inside the ranges
; ram.inc protects.
;
; The block starts at $2600, clear of the stack ($21FF downward) and clear of
; the areas the stock firmware used, so that a partly-rewritten ROM running
; beside stock code cannot have the two fighting over the same byte.
; ===========================================================================

; WHERE THIS LIVES, AND WHY IT MOVED.
;
; Working scratch sits at $3A80-$3E93, between the save/recall register array
; and the per-unit identity data. It was at $2600, and $2600 IS INSIDE THE
; SAVE/RECALL ARRAY - twelve stored instrument setups that the stock firmware
; keeps at $268F-$3A7A, 425 bytes each. Scratch there would have overwritten
; them from the first keypress.
;
; That array was found by reading the stock save path rather than by any gate:
; save_state_register (a2u13_page2 $544D) walks it with the descriptor at
; page2 $54D9, whose stride word is $01A9 = 425, and $268F + 12*425 - 1 =
; $3A7A, which is exactly where the next variable in use begins. Neither
; ramrefs.py nor ramsafety.py declared it, so nothing would have complained.
;
; The three regions of battery-backed RAM this firmware recognises:
;
;   $2000-$203B   the signature the power-on check compares against ROM
;   $268F-$3A7A   the twelve save/recall registers   (registers.s)
;   $3A80-$3E93   working scratch, this file          - rebuilt at power-on
;                 up to live_setting; live_setting and the block above it
;                 survive a keep-state power-on
;   $3FEE-$3FFF   serial, options and the revision signature - NEVER written
;                 except by the two screens that exist to write them
;
; Everything in THIS file is scratch: it is rebuilt at power-on and losing it
; costs nothing. Nothing here may be relied on across a power cycle, and
; nothing here may sit outside the span above. tests/test_scratch_layout.py
; refuses both.

SCRATCH_BASE    equ     $3A80

; --- math.s ----------------------------------------------------------------
math_a          equ     SCRATCH_BASE+$00        ; first operand, 2 bytes
math_b          equ     SCRATCH_BASE+$02        ; second operand, 2 bytes
math_product    equ     SCRATCH_BASE+$04        ; 32-bit result, 4 bytes
math_count      equ     SCRATCH_BASE+$08        ; loop counter for div16
math_work       equ     SCRATCH_BASE+$09        ; 24-bit scratch, 3 bytes

; --- text.s ----------------------------------------------------------------
text_buffer     equ     SCRATCH_BASE+$10        ; digits built here, 12 bytes
text_length     equ     SCRATCH_BASE+$1C        ; how many are significant

; --- menu.s ----------------------------------------------------------------
menu_table      equ     SCRATCH_BASE+$20        ; the menu being shown
menu_count      equ     SCRATCH_BASE+$22        ; how many entries it has
menu_index      equ     SCRATCH_BASE+$23        ; which one is selected
menu_top        equ     SCRATCH_BASE+$24        ; the first one displayed
menu_marker     equ     SCRATCH_BASE+$26        ; the one character that says
                                                ; whether this entry opens a menu
menu_armed      equ     SCRATCH_BASE+$25        ; a destructive entry has been
                                                ; chosen once and is waiting
                                                ; for the second press

; --- keypad.s --------------------------------------------------------------
key_column      equ     SCRATCH_BASE+$28        ; the column being driven
key_last        equ     SCRATCH_BASE+$29        ; the last key seen, for
                                                ; edge detection
key_pending     equ     SCRATCH_BASE+$2A        ; a decoded key waiting to be
                                                ; read, or KEY_NONE

; --- entry.s ---------------------------------------------------------------
entry_buffer    equ     SCRATCH_BASE+$30        ; one digit per byte, 8 bytes
entry_count     equ     SCRATCH_BASE+$38        ; how many are typed
entry_width     equ     SCRATCH_BASE+$39        ; how many the field holds
entry_base      equ     SCRATCH_BASE+$3A        ; 10 or 16
entry_index     equ     SCRATCH_BASE+$3B        ; loop position
entry_result    equ     SCRATCH_BASE+$3C        ; the 24-bit value, 3 bytes
entry_scratch   equ     SCRATCH_BASE+$40        ; 24-bit working copy, 3 bytes
entry_overflow  equ     SCRATCH_BASE+$43        ; set if the digits exceed 24 bits

; --- how many output boards the probe found -------------------------------
; Not an option bit: count_installed_channels sets bit 7 of each channel
; latch, strobes $0800 and reads int_latch back, so this is what is really
; fitted rather than what anything claims.
installed_channels equ  SCRATCH_BASE+$48       ; 1 bytes, and the size is
                                                ; STATED so the free bytes
                                                ; after it are visible to the
                                                ; layout gate, which derives
                                                ; an unstated size from the
                                                ; next declaration and so
                                                ; reads a hole as occupied.
                                                ; Every access is a byte: one
                                                ; clr, one inc, one sta, three
                                                ; lda, two ldb, four cmpb

; --- three bytes that had nowhere to go ------------------------------------
; The scratch span has no run of free bytes left below live_setting - every
; declaration without a stated size is scored up to the next one, so a real
; hole reads as occupied - and these three had to go somewhere real. They sit
; in the gap after installed_channels, whose true size is one byte.
incr_tone_off   equ     SCRATCH_BASE+$49        ; 2 bytes: the Off time's
                                                ; step, as incr_tone_on is.
                                                ;
                                                ; MOVED OFF +$3A8, WHICH IS
                                                ; backlight_ms. Widening the
                                                ; On step to a word pushed
                                                ; this one from a byte to a
                                                ; word and it kept the offset
                                                ; that followed the old byte -
                                                ; which was already the
                                                ; backlight's 16-bit
                                                ; countdown, so the two owned
                                                ; $3E28 together. The
                                                ; backlight ticks that word
                                                ; down a thousand times a
                                                ; second, so an Off step typed
                                                ; on INCR SET was eaten within
                                                ; the second and the backlight
                                                ; timeout became whatever step
                                                ; was typed last
rmt_mode_code   equ     SCRATCH_BASE+$4B        ; 1 bytes: the label code a
                                                ; mode mnemonic carried, the
                                                ; stock's $221F. A bus command
                                                ; that sets a waveform has to
                                                ; be checked by the routine
                                                ; the PANEL checks it with,
                                                ; and that routine is on page
                                                ; 0 while remote.s is
                                                ; resident: page_call clobbers
                                                ; A and owns B and X, so the
                                                ; argument travels in RAM
chan_dest_parked equ    SCRATCH_BASE+$4F        ; 4 bytes, one a channel:
                                                ; the destination a COLD start
                                                ; takes out of the record and
                                                ; keeps until the channel
                                                ; screen is opened. The stock's
                                                ; $24DE, filled by
                                                ; reapply_all_channels ($C5B1)
                                                ; at $C5E8 and read back by
                                                ; enter_channel_config_mode
                                                ; ($528F) at $5404-$543D.
                                                ; CHAN_DEST_NONE means nothing
                                                ; is parked

; --- what the Save / Recall prompt is covering -----------------------------
; The prompt is an OVERLAY, not a screen: save_recall_prompt ($F331) installs
; its key handler in $220D and leaves $220F - the screen underneath - exactly
; as it found it, so the mode still has the keys and the bus the moment the
; register number is taken. This firmware has ONE handler slot, so the prompt
; puts the covered screen's slot and vectors here and puts them back when it
; is dismissed. Four words, in the order register_prompt_cells lists them:
; screen_handler, screen_commit, screen_f1 and screen_f4.
reg_prompt_save equ     SCRATCH_BASE+$053       ; 6 x 2 = 12 bytes
                                                ; +$53 to +$5E, between
                                                ; chan_dest_parked's four and
                                                ; nav_top at +$60, and below
                                                ; live_setting so scratch_reset
                                                ; clears it at power-on
digital_stream_at equ   SCRATCH_BASE+$4D        ; 2 bytes: where the NEXT
                                                ; character of a WSQ stream
                                                ; goes. The stock keeps this
                                                ; apart from the editor's own
                                                ; cursor - $3CD8 against $3CA2,
                                                ; seeded from it at $6591 and
                                                ; advanced and clamped at
                                                ; $653B-$6551 - so a streamed
                                                ; pattern does not drag the
                                                ; cursor the operator left on
                                                ; the screen
rmt_check_result equ    SCRATCH_BASE+$4C        ; 1 bytes: 0, an error code,
                                                ; or RMT_CHECK_PENDING. A
                                                ; carry cannot say which of
                                                ; two things happened -
                                                ; page_call sets it both when
                                                ; the paged check refused the
                                                ; value and when the page
                                                ; switch itself failed - so
                                                ; the resident side writes the
                                                ; sentinel here, calls the
                                                ; page, and reads it back

; --- service_dds.s ---------------------------------------------------------
; What was last written to each DDS register. The port is write-only, so this
; is the firmware's own record and not the chip's state - they can disagree.
; THE CHIP HAS 42 REGISTERS, ids $00 to $29, and dds_write indexes this by
; register * 2. It was sized for EIGHT - sixteen bytes - so any write to a
; register above $07 stored past the end of it and into whatever followed.
; The waveform registers are $1D and $1E, which land 44 bytes past where the
; shadow stopped.
;
; That was invisible while the only registers written were the per-channel
; frequency, level and phase, which are $08-$13 - already past the end, but
; the bytes they landed on were themselves scratch nobody read.
dds_shadow      equ     SCRATCH_BASE+$2F8       ; DDS_REGISTERS x 2 = 84 bytes.
                                        ; Moved out of the crowded low
                                        ; region: at +$50 it was sized for
                                        ; eight registers and nav_top sat
                                        ; sixteen bytes above it.

; --- service_nav.s ---------------------------------------------------------
nav_top         equ     SCRATCH_BASE+$60        ; how deep the menu stack is

; --- paging.s --------------------------------------------------------------
; Which A2U13 page is mapped, or $FF when a switch failed and it is not
; known. A stale number here would send a call into the wrong page.
current_page    equ     SCRATCH_BASE+$64        ; 1 bytes

; --- page0_stereo.s --------------------------------------------------------
; The FM Stereo Composite screen's live parameter block, which is HP's
; $3C01 block in 08904-87011 bank 5 (docs/stereo-trace.md). HP keeps 51 bytes
; there because it carries a step size beside every numeric field; this holds
; the values only - the step fields are a declared absence, not an oversight,
; and hp8904a-rewrite/COVERAGE.txt records it.
;
; The six derived bytes below the values are the amplitude ladder HP builds
; at $6437 and $63E8: the composite splits into the pilot's share and the
; audio's, preemphasis scales the audio, and the mode arms take it at full,
; half or quarter.
st_tone         equ     SCRATCH_BASE+$65        ; 3 bytes, tone frequency in
                                                ; 0.1 Hz. HP's $3C07
st_comp         equ     SCRATCH_BASE+$68        ; 3 bytes, composite amplitude
                                                ; in microvolts. HP's $3C01
st_pfreq        equ     SCRATCH_BASE+$6B        ; 3 bytes, pilot frequency in
                                                ; 0.1 Hz. HP's $3C18
st_cfreq        equ     SCRATCH_BASE+$6E        ; 3 bytes, carrier frequency
                                                ; in 0.1 Hz. HP's $3C2A
st_pampl        equ     SCRATCH_BASE+$71        ; 2 bytes, the pilot's share
                                                ; in tenths of a percent,
                                                ; 0 to 1000. HP's $3C11
st_pphase       equ     SCRATCH_BASE+$73        ; 2 bytes, pilot phase in
                                                ; tenths of a degree. $3C22
st_mode         equ     SCRATCH_BASE+$75        ; 1 bytes, 0 Off, 1 R=L,
                                                ; 2 R=-L, 3 R only, 4 L only.
                                                ; HP's $3C15 - NOT $3C17
st_preemph      equ     SCRATCH_BASE+$76        ; 1 bytes, 0 Off, 1 25us,
                                                ; 2 50us, 3 75us. HP's $3C16
st_pilot_on     equ     SCRATCH_BASE+$77        ; 1 bytes, non-zero when the
                                                ; pilot is on. HP's $3C17,
                                                ; which gates channel 2's
                                                ; amplitude at $538B and is
                                                ; independent of the mode
; THE NINETEEN BYTES ABOVE ARE WHAT A REGISTER CARRIES OF THIS SCREEN. HP's
; 08904-87011 copies its 51-byte block $3C01 into $257C, inside the block a
; register saves, from the screen's save arm (bank 5 $5C46 -> $58D5), and back
; out on its entry $42D2 with argument 1. Its 51 hold the six step fields this
; port declares absent and the working cells stereo_apply derives; what is left
; is these nineteen. A slot here has no nineteen contiguous bytes to spare, so
; they go in two pieces: the four wide values into the tail of the sequence
; span and the rest into live_globals - see live_stereo and register_save.
ST_SAVED_WIDE   equ     st_pampl-st_tone        ; 12: the four 24-bit values
ST_SAVED_NARROW equ     st_pilot_on+1-st_pampl  ; 7: the two words, three bytes
st_field        equ     SCRATCH_BASE+$78        ; 1 bytes, the selected field
st_mant         equ     SCRATCH_BASE+$79        ; 2 bytes, the composite's
                                                ; twelve-bit mantissa. $3C37
st_exp          equ     SCRATCH_BASE+$7B        ; 1 bytes, its exponent, which
                                                ; is the attenuator range and
                                                ; is written ONCE per commit
st_share        equ     SCRATCH_BASE+$7C        ; 2 bytes, the pilot's share
                                                ; of the mantissa. HP's $3C35
st_audio        equ     SCRATCH_BASE+$7E        ; 2 bytes, what is left for
                                                ; the audio. HP's $3C39
st_pre          equ     SCRATCH_BASE+$80        ; 2 bytes, the audio after
                                                ; preemphasis. HP's $3C3B
st_half         equ     SCRATCH_BASE+$82        ; 2 bytes, that halved. $3C3D
st_quarter      equ     SCRATCH_BASE+$84        ; 2 bytes, quartered. $3C3F
st_work         equ     SCRATCH_BASE+$86        ; 2 bytes, the interpolation's
                                                ; working word
st_freq         equ     SCRATCH_BASE+$2A2       ; 3 bytes, the sideband
                                                ; frequency being computed:
                                                ; carrier plus tone, then
                                                ; carrier minus tone. Not
                                                ; chan_work, which page0_screen,
                                                ; page0_channel, page1_tone,
                                                ; page2_digital and remote all
                                                ; share - a burst that calls
                                                ; a dozen routines has no
                                                ; business holding somebody
                                                ; else's scratch across them

; --- events.s --------------------------------------------------------------
; THE EVENT QUEUE IS GONE. Nothing posted to it and nothing read it: the
; screen-handler design replaced it before it had a caller, and it survived
; as eight entries of RAM, five routines and an ABI slot that between them
; did nothing. tests/test_reachable.py is what found it.
;
; Its ABI slot is redirected to the error reporter rather than reused, which
; is the rule common/abi.inc states for a withdrawn entry: an index once
; given out is permanent, and handing it to something else is how a stale
; call becomes silent wrong behaviour instead of a reported fault.
;
; What it used to say:
;
; A ring of pending requests. Two bytes each: the event code and one
; argument. head is where the next one goes, tail where the next comes from,
; and head == tail means empty - which is why one slot is never used and the
; queue holds seven of its eight entries.

; --- errors.s --------------------------------------------------------------
last_error      equ     SCRATCH_BASE+$88        ; the last fault raised

; --- units.s ---------------------------------------------------------------
unit_work       equ     SCRATCH_BASE+$8C        ; 24-bit scratch for x10

; --- fields.s --------------------------------------------------------------
field_index     equ     SCRATCH_BASE+$90        ; which field has the cursor

; --- page0_hop.s, in the space fields.s and dds.s gave back ---------------
; field_count and field_tries (+$91, +$92) and dds_mask and dds_value (+$94,
; +$96) were declared for drafts that no longer exist - fields.s walks its
; table to the terminator without a count, and dds.s composes a register
; value in D. Nothing in modules/, images/ or common/ names any of the four.
; Nine contiguous bytes, and the Hop Ram screen's widest field is nine
; columns: scratch is otherwise packed solid from +$000 up to live_setting
; with no gap anywhere in it.
format_text     equ     SCRATCH_BASE+$91        ; 9 bytes: one field's
                                                ; characters with its decimal
                                                ; point dropped in, which is
                                                ; the window the stock builds
                                                ; at $2414 before writing it
                                                ; to the glass

; --- channel.s -------------------------------------------------------------
current_channel equ     SCRATCH_BASE+$9A        ; 1 byte: which channel the
                                                ; panel edits
chan_chain      equ     SCRATCH_BASE+$9B        ; 1 byte: where the Channel
                                                ; Configuration chain stands -
                                                ; 0 its title, 1 to 4 the four
                                                ; channel screens, 5 the Hop Ram
                                                ; fields, 6 the hop On/Off page.
                                                ; The stock's $268E for the
                                                ; seven-record table at $433E,
                                                ; which menu_page_show ($89AA)
                                                ; indexes and menu_item_next
                                                ; ($8A5B) steps against the
                                                ; count byte before it.
output_stage    equ     SCRATCH_BASE+$9C        ; 1 byte: the output screens'
                                                ; stage, the stock's $3A7D - 0
                                                ; the number, 1 ON or OFF
output_channel  equ     SCRATCH_BASE+$9D        ; 1 byte: the output taken, 0 to
                                                ; 3 - the stock's $3A7C less one
                                                ; +$9F is free.
relay_mode      equ     SCRATCH_BASE+$9E        ; 1 byte: which set the relay
                                                ; exercise cycles - 0 every
                                                ; relay, 1 the 48 dB pad K8
                                                ; alone, the only relay on the
                                                ; board with a mechanical
                                                ; armature. NEXT and LAST step
                                                ; it, the instrument's own
                                                ; idiom for a selection on a
                                                ; service screen ($17 and $18,
                                                ; the codes memmap_select_
                                                ; element and msg_set_number_
                                                ; base are stepped by).
                                                ;
                                                ; IT WAS AT +$56A FOR ONE
                                                ; ASSEMBLY, which is ABOVE
                                                ; live_setting where
                                                ; scratch_reset stops, so it
                                                ; would have survived a power
                                                ; cycle holding whatever the
                                                ; last firmware left there -
                                                ; including a value outside
                                                ; 0 and 1. test_scratch_layout
                                                ; caught it before the build
                                                ; wrote an image.

; --- registers.s -----------------------------------------------------------
; The live setting, and the twelve saved ones. These survive a power cycle -
; they are the second thing in the instrument that does, after the serial and
; the options - so they sit above the working scratch and are not cleared at
; boot.
; live_setting is NOT a separate block. It is the name for the whole of the
; live instrument state, and that state IS the four channel records followed
; by the globals that are not per-channel - laid out contiguously below so a
; save is one copy and a recall is one copy back.
;
; It was sixteen bytes here while REGISTER_SIZE was sixty-four, so
; register_save read forty-eight bytes past the end of it and register_recall
; wrote forty-eight bytes past the end. Whatever followed was saved into
; every register and written back out of it.
; register_store is NOT here. Stored setups must survive power-down and
; everything in this file is rebuilt at power-on, so it lives in
; registers.s at its own battery-backed address.

; --- selftest.s ------------------------------------------------------------
selftest_result equ     SCRATCH_BASE+$170       ; a bit per check that passed

; --- the paged screens -----------------------------------------------------
page0_channel_number equ SCRATCH_BASE+$174      ; which channel is on screen
page0_digit     equ     SCRATCH_BASE+$175       ; one character, for the title
; destn_current is GONE. It was one global byte holding whatever destination
; was set last, on any channel, and destn_apply read it to decide what to
; disconnect - so applying four channels in a loop made each one disconnect
; the socket the channel before had just been given. The previous destination
; is per-channel and lives in CHAN_DEST, where it always was; once destn_apply
; read it from there, nothing read this byte at all, and a variable written
; and never read is a leftover.
; destn_target is gone: it was read by destn_apply and written by nobody.

; --- the paged sequence and hop state --------------------------------------
; Split deliberately: the PLAYER runs from a timer interrupt and the EDITOR
; from the foreground, so the position each uses is its own byte. Sharing one
; makes the edit cursor jump about as the sequence plays.
hop_table       equ     SCRATCH_BASE+$0A0       ; 16 slots x HOP_ENTRY_SIZE
                                                ; = 128 bytes, moved here from
                                                ; +$180 when the slot grew
                                                ; from three bytes to eight.
                                                ; The gap between
                                                ; current_channel and the old
                                                ; hop table was the only free
                                                ; run long enough, and putting
                                                ; it there leaves the tone and
                                                ; digital sequences where they
                                                ; are rather than moving three
                                                ; things to move one.
; SIXTEEN STEPS OF FIVE BYTES, not four. A tone step in the stock carries an
; ON TIME and an OFF TIME, not one duration: its step table at $3C10 has a
; stride of FOUR - $4285 does ASLB / ASLB / ADDD #$3C10 on the step number in
; $3D27, and the player writes both words, [X] from $3C07 and [X+2] from
; $3C09 - and copy_time_to_all_tones ($4AED) confirms which is which, taking
; word 0 for request code $37 and word 1 for $38, the On Time and Off Time
; columns entry_field_on_off_time ($45A6) paints.
;
; Without the second one every step runs straight into the next and a tone
; sequence cannot put a GAP between tones, which is most of what a tone
; sequence is for.
;
; The stock's two times are 16-bit and these are one byte of milliseconds
; each, which is the same choice already made and written down for the single
; duration: a tick is a millisecond, so a byte is a quarter of a second, and
; the entry path takes the low byte. That is a limit worth stating rather
; than a difference worth hiding.
; MOVED 2026-09-07, OFF THE TOP OF THE REMOTE RESPONSE BUFFER.
;
; It was at +$1B0 and claimed "+$1B0 to +$1FF inclusive" - eighty bytes. Only
; the first FIVE of those were free. rmt_out takes +$1B5 for 72 bytes and the
; three hop-entry bytes take +$1FD to +$1FF, so the run from +$1B5 to +$1FF is
; packed with no slack at all.
;
; tone_step_address computes tone_sequence+5*step, so STEP 1 BEGAN AT +$1B5 -
; exactly rmt_out's first byte - and steps 1 to 15 lay on top of the remote
; response buffer and those three hop bytes. A tone sequence and a bus
; response destroyed each other, in shipping firmware.
;
; THE TONE SEQUENCE IS THE ONE THAT MOVED, because it is the one that was
; wrong about its own extent and the only one with anywhere to go: rmt_out and
; the hop bytes fit their region exactly, and moving them would have meant
; finding 75 bytes for them instead of 80 for this.
;
; It goes where live_setting was; live_setting and the six names above it moved
; up by $50 to make room, which is the same operation performed when the step
; grew to five bytes. Nothing below +$3B2 moved.
;
; The overlap gate could not see any of it: it reads a block's size out of this
; comment, and the old wording "16 steps x 5 bytes" matched only its
; bare-number rule, so eighty bytes scored as five and the gate printed "ok".
; That hole is closed in hp8904a-rewrite/tests/test_scratch_layout.py, which
; now refuses a size it cannot fully parse.
; THE TONE SEQUENCE, AS THE INSTRUMENT HAS IT. Ported 2026-09-07 from the
; stock's own three tables; before that a step was five self-contained bytes
; and there were sixteen of them, which nobody had asked for.
;
; TWO SEPARATE THINGS, which is the whole shape of the model:
;
;   A LIST OF SIXTEEN TONES. Each owns a 24-bit tuning word and its own On and
;   Off durations. The stock keeps these at $3C50 (16 x 3) and $3C10 (16 x 4).
;
;   A PLAYLIST OF 250 STEPS, each a four-bit tone number packed two to a byte,
;   the stock's $3C90-$3D0C. seq_put_nibble ($452D) refuses an index at or
;   above $00FA, which is 250, and seq_data_init ($79FE) sets Seq End $00F9.
;
; So one tone's settings serve every step that names it, and retuning tone 3
; retunes it everywhere - the capability the per-step model could not express.
;
; THE DURATIONS ARE TIMER COUNTS, NOT MILLISECONDS. load_current_step ($4268)
; puts the word it loads into $3D30, and blk42d1 at $4311 does LDX >$3D30 /
; LEAX -1,X / STX >ptm_timer2 - straight into the timer latch. The tick is ten
; microseconds, so the range is 655.35 ms at 0.01 ms resolution. An earlier
; report of mine said 65,535 milliseconds; it is 65,535 counts.
;
; ONE CONTIGUOUS RUN, +$3B2 to +$49E, so a saved register carries all three as
; a single span the way the stock's 257-byte block does.
tone_freq       equ     SCRATCH_BASE+$3B2       ; 16 x 3 bytes
tone_times      equ     SCRATCH_BASE+$3E2       ; 16 x 4 bytes
tone_list       equ     SCRATCH_BASE+$422       ; 125 bytes, 250 nibbles
; THE ONCE-THROUGH FLAG OF A SINGLE PASS, which is the stock's $3D34. It is not
; the same thing as tone_single: $3C81 says the run is single-shot and is set
; before it starts, $3D34 says the pass has not finished yet and is CLEARED by
; seq_step_advance ($42B1) when the position passes Seq End. The DTMF body tests
; the two together at $4487 and takes the stop path at $44D1 on the FOLLOWING
; interrupt, which is why the instrument plays one whole tick more after the
; wrap. This byte is that flag with the sense inverted - non-zero once the pass
; is over - so a run that has never wrapped needs nothing but the CLR tone_start
; makes. It sits in the one-byte gap the contiguous run +$3B2 to +$49E leaves
; before tone_cursor.
tone_pass_done  equ     SCRATCH_BASE+$49F       ; 1 byte
; THE SEQUENCE EDITOR'S OWN STATE, added in stage 3. The stock keeps all
; three: the cursor is its $3D0D, the window origin its $3D39 and the insert
; flag its $3D3E.
;
; THE CURSOR IS NOT THE PLAYER'S POSITION. tone_position is where the player
; is; this is where the operator is editing. The stock separates them too -
; $3D0D against $3D2C - and it has to: an operator can move the cursor while
; a sequence runs.
tone_cursor     equ     SCRATCH_BASE+$4A0       ; Seq Index, 0..249
tone_window     equ     SCRATCH_BASE+$4A2       ; the leftmost step the
                                                ; sixteen-cell window shows
tone_insert     equ     SCRATCH_BASE+$4A4       ; non-zero while the window
                                                ; shows an insert gap
tone_win_step   equ     SCRATCH_BASE+$4A5       ; the window painter's two
tone_win_cell   equ     SCRATCH_BASE+$4A7       ; counters: which step it is
                                                ; showing and which of the
                                                ; sixteen cells that lands in.
                                                ; The stock keeps a third, the
                                                ; column, which is always equal
                                                ; to the cell - $7011 and $7086
                                                ; test the two against each
                                                ; other and can never disagree.
; THE FIVE BYTES AT +$1B0 that the old sixteen-step block began on, now that it
; is gone. NOT more than five: rmt_out takes +$1B5 for 72 bytes and the three
; hop-entry bytes take +$1FD to +$1FF, which is what the block used to lie on.
tone_position   equ     SCRATCH_BASE+$1B0       ; the PLAYER's position. A WORD:
                                                ; the playlist is 250 steps and
                                                ; a byte cannot address it. The
                                                ; stock's is a word too, $3D2C.
tone_number     equ     SCRATCH_BASE+$1B2       ; the tone the screen is on,
                                                ; 0..15 - the stock's $3D1B
tone_stream_at  equ     SCRATCH_BASE+$1B3       ; 2 bytes: where the NEXT
                                                ; character of a WSQ stream
                                                ; goes in the PLAYLIST. The
                                                ; stock keeps it apart from
                                                ; the editor's own cursor -
                                                ; $3D3F against $3D0D, seeded
                                                ; from it by
                                                ; start_streamed_digit_entry
                                                ; ($79DF) and advanced and
                                                ; clamped at $00F9 by
                                                ; gpib_sequence_char_in
                                                ; ($799F-$79B8) - so a
                                                ; streamed sequence does not
                                                ; drag the cursor the operator
                                                ; left on the screen.
                                                ; digital_stream_at is page
                                                ; 2's twin of this, and the
                                                ; two are separate cells
                                                ; because the stock's are:
                                                ; $3D3F lives in page 1's RAM
                                                ; and $3CD8 in page 2's
; +$1B5 onwards is free, as the note below rmt_seq_owner sets out.
;
; WHICH IS A BUG THIS PORT REMOVES. The old tone_sequence was declared here as
; "16 steps x 5 bytes, +$1B0 to +$1FF inclusive" and tone_step_address walked
; it as tone_sequence+5*step - so step 1 began at +$1B5, exactly rmt_out's
; first byte, and steps 1 to 15 lay on top of the remote response buffer and
; those three hop bytes. A tone sequence and a bus response corrupted each
; other. The overlap gate did not see it because it reads a size out of the
; comment and "16 steps x 5 bytes" does not match its pattern, so it scored
; the block as five bytes.
; --- the digital pattern's indices -----------------------------------------
; THE PATTERN ITSELF IS NOT HERE. It is 125 bytes of battery RAM at
; digital_pattern_ram ($2280, common/ram.inc), because the instrument keeps it
; in battery RAM at $3C21 and a pattern an operator typed survives the power
; switch. What is here is everything derived from it, all of which is rebuilt
; from the pattern and the base and none of which has to survive anything.
;
; The sixteen bytes that used to be `digital_sequence` are these six words.
; That block was the rewrite's own model - sixteen steps of eight bits - and
; the instrument has no such thing: it has one 1000-bit stream read as 1000
; binary, 333 octal or 250 hexadecimal digits (set_max_length_for_base,
; $56A3).
digital_bit_index equ   SCRATCH_BASE+$380       ; 2 bytes: the PLAYER's bit
                                                ; counter, the stock's $3CC4,
                                                ; which its ISR increments at
                                                ; $41AA and compares with
                                                ; $3CAA at $41F3. Sixteen bits
                                                ; because the pattern is 1000
digital_index_bit equ   SCRATCH_BASE+$382       ; 2 bytes: the CURSOR's bit,
                                                ; $3CA6 - the LAST bit of the
                                                ; digit under the cursor,
                                                ; which is what
                                                ; read_bit_at_cursor ($54DF)
                                                ; reads and the screen shows
digital_end_bit equ     SCRATCH_BASE+$384       ; 2 bytes: the last bit of the
                                                ; END digit, $3CA8. It is the
                                                ; authority a base change
                                                ; rebuilds the digit indices
                                                ; from ($56E9), so it is kept
                                                ; separately from the player's
                                                ; copy below
digital_count   equ     SCRATCH_BASE+$386       ; 2 bytes: how many digits this
                                                ; base fits, $3CCC - 1000, 333
                                                ; or 250
digital_column  equ     SCRATCH_BASE+$388       ; 2 bytes: the cursor's column
                                                ; within the sixteen-cell
                                                ; window, $3CD4 = $3CA2-$3CD2
digital_field_ptr equ   SCRATCH_BASE+$38A       ; 2 bytes: which index the
                                                ; number field is editing,
                                                ; $3CD0 - it holds the address
                                                ; of digital_index or of
                                                ; digital_end and the field
                                                ; routines work through it
digital_insert  equ     SCRATCH_BASE+$38C       ; 1 byte: INSERT MODE, the
                                                ; stock's $3CD7. While it is
                                                ; set the window shows a blank
                                                ; cell at the cursor, a typed
                                                ; digit opens a space rather
                                                ; than overwriting, and f3
                                                ; cancels the insert instead
                                                ; of deleting
hop_page        equ     SCRATCH_BASE+$38F       ; 1 byte: which of the Hop Ram
                                                ; screen's TWO menu records is
                                                ; showing - 0 the four fields,
                                                ; 1 the four function toggles.
                                                ; The instrument has them as
                                                ; two records paged with
                                                ; NEXT/LAST (walked on the
                                                ; stock: record 4 is
                                                ; ' Hop Ram Adrs ... FREQ ...'
                                                ; and record 5
                                                ; ' Digital Port ... Freq Hop
                                                ; ...'); this firmware had
                                                ; them crammed into one
edit_extended   equ     SCRATCH_BASE+$38E       ; 1 byte: the digit just typed
                                                ; LENGTHENED the sequence, so
                                                ; an insert has to take that
                                                ; back before making its own
                                                ; room. The stock keeps it at
                                                ; 4,S inside
                                                ; enter_sequence_field_value
                                                ; ($6120 sets it, $617B reads
                                                ; it); it is here because the
                                                ; two halves are two routines
digital_edit    equ     SCRATCH_BASE+$38D       ; 1 byte: AN EDIT SESSION IS
                                                ; OPEN, the stock's $3CCA. It
                                                ; is what puts Delete and
                                                ; Insert on f3 and f4 in place
                                                ; of 'Edit Sequence', and what
                                                ; any key outside the editing
                                                ; set closes
tone_state      equ     SCRATCH_BASE+$200
tone_playing    equ     SCRATCH_BASE+$201       ; THE TONE THE PLAYER IS
                                                ; SOUNDING - the stock's $3D27,
                                                ; which load_current_step
                                                ; ($4268) writes and which the
                                                ; rear latch carries at $431C.
                                                ; Kept rather than re-derived,
                                                ; because the playlist can be
                                                ; edited while the tick runs.
digital_bit     equ     SCRATCH_BASE+$204       ; the bit last driven out
                                                ; through the Out1 routing.
                                                ; It was digital_shadow, a
                                                ; copy of an eight-bit port
                                                ; write that the hardware
                                                ; does not support - see the
                                                ; head of page2_digital.s
; --- INCR SET: the step each numeric field moves by -----------------------
; One increment per field rather than one shared, because the stock keeps them
; separately too - $62EC has its own arm for each - and because a frequency
; step of 100.0 Hz means nothing as a phase step.
;
; This said they were in the live state's span so a saved register carries
; them. incr_freq and incr_phase never were: +$21B and +$221 are below
; live_setting, which scratch_reset clears at every power-on.
;
; incr_freq WAS HERE, AND incr_ampl BESIDE IT, EACH ONE STORE FOR ALL FOUR
; CHANNELS. The stock keeps both in every channel record: the frequency step
; at +5, which step_channel_frequency ($71DD) adds to +0, and the unit it was
; keyed in at +8, which enter_freq_value ($6BA5) writes when $2215 is 6 and
; show_freq_increment_field ($5A1B) paints from. They are incr_freq_ch and
; incr_freq_unit below, and incr_ampl_ch at the top of scratch. The six bytes
; +$21B..+$220 are free.
incr_phase      equ     SCRATCH_BASE+$221       ; 3 bytes, 0.1 degree units
; --- INCR SET on the hop screen ------------------------------------------
; One increment per field, as the stock keeps three of its own at $2671, $2674
; and $267D. They are NOT in a saved register: the stock's are, but a hop
; increment is a way of working rather than a setting, and the register span
; is already REGISTER_SLOT bytes a slot (registers.s).
incr_hop_freq   equ     SCRATCH_BASE+$229       ; 3 bytes, 0.1 Hz
incr_hop_ampl   equ     SCRATCH_BASE+$22C       ; 3 bytes, microvolts
incr_hop_phase  equ     SCRATCH_BASE+$22F       ; 3 bytes, 0.1 degree
hop_incr_mode   equ     SCRATCH_BASE+$232       ; the next ENTER stores an
                                                ; increment, not a value
hop_step_work   equ     SCRATCH_BASE+$233       ; 3 bytes, the value in motion
mode_flags      equ     SCRATCH_BASE+$236       ; which modulation modes are
                                                ; ON, one bit each - see the
                                                ; MODE_FLAG_* constants. The
                                                ; stock keeps these in the low
                                                ; byte of event_flags2 at
                                                ; $2203; they live in scratch
                                                ; here because that word is
                                                ; the stock's own bookkeeping
                                                ; and this firmware keeps its
                                                ; own.
MODE_FLAG_DIGITAL equ   $10                     ; bit 4 of mode_flags: the
                                                ; 'Digital Port' row of the
                                                ; stock's hop function menu
                                                ; ($42ED), row 0 of
                                                ; set_hop_function_enable
                                                ; ($4984), which keeps it as
                                                ; bit 13 of event_flags $2204
                                                ; ($49AF ORA #$20 / $49BC ANDA
                                                ; #$DF on the high byte) and
                                                ; which write_reg15_nibble
                                                ; ($E7C4) turns into bit 4 of
                                                ; DDS register $15 ($E7E1 ORB
                                                ; #$10). The stock's byte
                                                ; $2204 has no counterpart in
                                                ; scratch; a free bit of the
                                                ; byte that already mirrors
                                                ; the three $2203 hop enables
                                                ; is used rather than a new
                                                ; byte, and its value is the
                                                ; register bit itself so
                                                ; hop_addr_put in
                                                ; page0_hop.s ORs it in
                                                ; unshifted. The other
                                                ; MODE_FLAG_* constants are in
                                                ; common/formats.inc; this one
                                                ; is here beside the byte it
                                                ; indexes because it exists
                                                ; for that byte alone.
                                                ;
                                                ; They exist because the
                                                ; control registers are
                                                ; write-only: nothing can ask
                                                ; the chip whether amplitude
                                                ; hop is on, so the firmware
                                                ; has to remember.
hop_field       equ     SCRATCH_BASE+$228       ; which of a hop slot's three
                                                ; fields the screen is editing
field_is_hop    equ     SCRATCH_BASE+$37F       ; WHICH OF THE TWO CURSORS IS
                                                ; THE FIELD ID. The stock keeps
                                                ; ONE selected-field cell,
                                                ; $2215, for the whole Channel
                                                ; Configuration chain - 1 to 8
                                                ; for a channel record's fields
                                                ; and their increments, $0C to
                                                ; $12 for the hop ones - and
                                                ; every select writes it,
                                                ; whichever record is showing.
                                                ; Here the channel screen's
                                                ; cursor is field_index and the
                                                ; hop screen's is hop_field, so
                                                ; this byte says which of the
                                                ; two was written last: zero
                                                ; for field_index, non-zero for
                                                ; hop_field. chan_query_field
                                                ; is its only reader.
                                                ;
                                                ; IT CANNOT BE DERIVED FROM THE
                                                ; RECORD ON THE GLASS, which is
                                                ; what it was going to be.
                                                ; Driven on a two-channel stock
                                                ; 2026-09-14: 'FRH;' from a
                                                ; CHANNEL record leaves $2215 =
                                                ; $000C and '?' answers the hop
                                                ; slot, and 'FRA;' from the Hop
                                                ; Ram record leaves $2215 =
                                                ; $0001 and '?' answers channel
                                                ; A. Either cursor can be the
                                                ; live one on either record, so
                                                ; only "which was written last"
                                                ; tells them apart
chan_step_work  equ     SCRATCH_BASE+$225       ; 3 bytes: a field's value
                                                ; while the arrows move it,
                                                ; widened so one piece of
                                                ; arithmetic serves the
                                                ; 24-bit fields and the
                                                ; 16-bit phase alike
incr_mode       equ     SCRATCH_BASE+$224       ; non-zero while the next
                                                ; ENTER stores an INCREMENT
                                                ; rather than a value
fm_sum          equ     SCRATCH_BASE+$214       ; 3 bytes: the summed level
                                                ; of every channel modulating
                                                ; in FM, which sets the shared
                                                ; range
fm_common       equ     SCRATCH_BASE+$217       ; the shift count that sum
                                                ; normalises to - the exponent
                                                ; every FM channel is
                                                ; expressed against
fm_work         equ     SCRATCH_BASE+$218       ; 3 bytes, the value being
                                                ; normalised
chan_ampl_unit  equ     SCRATCH_BASE+$213       ; which unit the AMPTD field
                                                ; is showing, from the
                                                ; channel's destination
diag_kbd_wide   equ     SCRATCH_BASE+$210       ; 3 bytes: the total again,
                                                ; widened, because the only
                                                ; decimal formatter here takes
                                                ; 24 bits
hop_step_rad    equ     SCRATCH_BASE+$20D       ; 1 byte: non-zero while the
                                                ; hop PHASE field being stepped
                                                ; is in radians. The unit rides
                                                ; in bit 15 of the slot's own
                                                ; phase word, and the arrows
                                                ; have to take it off before
                                                ; the arithmetic and put the
                                                ; SAME one back after - not the
                                                ; entry layer's hop_entry_unit,
                                                ; which is the unit of the last
                                                ; thing TYPED. In the byte at
                                                ; +$20D, below diag_kbd_total.
diag_kbd_total  equ     SCRATCH_BASE+$20E       ; 2 bytes: the Keyboard
                                                ; Check screen's running sum,
                                                ; the same one the stock keeps
                                                ; at $3FA3
dds_lock        equ     SCRATCH_BASE+$209       ; non-zero while the foreground
                                                ; is part-way through staging
                                                ; a synthesis-chip register.
                                                ; A wide register is written
                                                ; as several accesses through
                                                ; shared buffer latches, and
                                                ; the sequence player runs
                                                ; from an interrupt that
                                                ; cannot be masked - so the
                                                ; player checks this and
                                                ; defers one tick rather than
                                                ; writing into the middle of
                                                ; a staging sequence
tone_manual_sel equ     SCRATCH_BASE+$20A       ; non-zero while the tone
                                                ; screen's MANUAL field is the
                                                ; one selected - the stock's
                                                ; $3D11 = $0B. The arrows walk
                                                ; the sequence only with it
                                                ; set; the local edge, a $3A
                                                ; or $3B refusal and any other
                                                ; field selection clear it
rmt_stid_prior  equ     SCRATCH_BASE+$20B       ; the field armed before
                                                ; ST_ID armed the serial: the
                                                ; stock's ST_ID leaves $238F
                                                ; as it was, so it is put back
                                                ; once the serial has its
                                                ; number or the command ends
rmt_held_kind   equ     SCRATCH_BASE+$20C       ; the field RF_HELD's value
                                                ; was held for. A lone unit
                                                ; commits it only while that
                                                ; same kind is armed, so a
                                                ; field armed by any path is
                                                ; never handed another field's
                                                ; number
star_ms         equ     SCRATCH_BASE+$2F5       ; 2 bytes: timer-1 flags left
                                                ; of the banner's half-second
                                                ; step. BELOW live_setting,
                                                ; because scratch_reset must
                                                ; clear it: it is display
                                                ; state, not something that
                                                ; survives a firmware change
star_frame      equ     SCRATCH_BASE+$2F7       ; 1 byte: which star is dark,
                                                ; 0 the outermost; equal to
                                                ; banner_stars means all lit
backlight_left  equ     SCRATCH_BASE+$45        ; 2 bytes: seconds left of
                                                ; the idle timeout, counted
                                                ; down by display_tick; 0 when
                                                ; the lamp is not on a timeout
                                                ; at all. Display state, so it
                                                ; is below live_setting and
                                                ; scratch_reset clears it
backlight_half  equ     SCRATCH_BASE+$47        ; 1 byte: which half of the
                                                ; second the display tick is
                                                ; in, so a second is two of
                                                ; the banner's own steps
banner_stars    equ     SCRATCH_BASE+$44        ; 1 byte: how many stars the
                                                ; banner on line 1 has at each
                                                ; end, 0 when the screen up
                                                ; has none of ours to animate
menu_prompt     equ     SCRATCH_BASE+$21C       ; 2 bytes: the menu's prompt
                                                ; callback, beside
                                                ; menu_annotate. Asked for the
                                                ; line that replaces the title
                                                ; while a destructive entry is
                                                ; armed; zero for a menu with
                                                ; no destructive entries
menu_line1      equ     SCRATCH_BASE+$21E       ; 1 byte: what line 1 holds
                                                ; now - 0 the title, otherwise
                                                ; the armed entry's index plus
                                                ; one - so it is repainted only
                                                ; when it changes and does not
                                                ; flicker on every key
rmt_field_gone  equ     SCRATCH_BASE+$21B       ; non-zero when the tone
                                                ; screen's refusal zeroed its
                                                ; field cursor ($5071's
                                                ; epilogue, $3D11 = 0) with a
                                                ; field still armed: a unit
                                                ; then commits nothing. Every
                                                ; bus arm clears it
dtmf_current    equ     SCRATCH_BASE+$205
register_pad    equ     SCRATCH_BASE+$206       ; ONE RESERVED BYTE, and the
                                                ; register array carries it.
                                                ; It was `sequence_length`,
                                                ; the digital sequence's step
                                                ; count, and the model that
                                                ; had a step count is gone -
                                                ; the sequence's end is
                                                ; digital_end inside the
                                                ; aliased slot. The SPAN is
                                                ; kept because taking it out
                                                ; moves every register by a
                                                ; byte and shifts the whole
                                                ; array, and the array is what
                                                ; rule 2 protects; a byte per
                                                ; register is not worth that.
                                                ; Nothing reads it and nothing
                                                ; writes it, which is what
                                                ; reserved means here.
hop_row         equ     SCRATCH_BASE+$207       ; 1 byte: which row of the
                                                ; hop On/Off page a softkey
                                                ; armed - the stock's $3B80,
                                                ; 0 Digital Port, 1 Freq Hop,
                                                ; 2 Amptd Hop, 3 Phase Hop,
                                                ; which begin_entry_hop_address
                                                ; ($4908) sets and
                                                ; set_hop_function_enable
                                                ; ($4984) dispatches on.
                                                ; edit_position was here - the
                                                ; sequence editor's cursor,
                                                ; which the rebuilt page-2
                                                ; editor keeps as
                                                ; digital_index_bit and
                                                ; digital_column and which
                                                ; nothing referenced any more.
hop_want        equ     SCRATCH_BASE+$208       ; 1 byte: LBL_ON or LBL_OFF,
                                                ; the choice the key made for
                                                ; the armed row. The stock's
                                                ; $221F, which
                                                ; apply_mode_toggle ($6FCB)
                                                ; passes to
                                                ; set_hop_function_enable
                                                ; ($4984) and which that
                                                ; routine reads as On only for
                                                ; $0011.


; --- the front-panel lamp shadow -------------------------------------------
; $0900 is WRITE-ONLY, exactly like the channel latches, so the only readable
; copy of what the six lamps are doing is this byte. The stock keeps the same
; shadow at $2420 and never writes the port without writing it too; see
; modules/panel_leds.s for the bit map and where it was read from.
;
; It is here rather than at $2420 because nothing requires the address to
; match - $2420 is not per-unit data, no other firmware reads it, and this
; tree keeps its own scratch in one span so tests/test_scratch_layout.py can
; check the whole of it at once.
; --- the amplitude autoranger's working buffer -----------------------------
; TEN characters, and the ten is the stock's: autorange_digits_v_mv_uv ($D022)
; copies eight, blanks their leading zeros, APPENDS TWO '0' at 10,S and 11,S,
; and scans for the first non-blank with a limit of 10. The two appended
; characters are what make the zero case land on a real arm and what the
; five-digit format reads when the source offset runs past the eighth
; character. See ampl_autorange in modules/amplitude.s.
ampl_range_text equ     SCRATCH_BASE+$360       ; 10 bytes
ampl_range_out  equ     SCRATCH_BASE+$36A       ; 6 bytes: the formatted field.
                                                ; SEPARATE from the source,
                                                ; because formatting in place
                                                ; overwrites a character before
                                                ; it is read - the stock builds
                                                ; it in a local and mem_copies
                                                ; it out for the same reason.

led_shadow      equ     SCRATCH_BASE+$370       ; the six lamp lines, active
                                                ; low, bits 7:6 never touched

; The decoded key a HELD key would repeat, so that keypad_read does not have
; to decode it again - decoding consumes the shift latch, and re-decoding a
; held key would eat it on the first pass. KEY_NONE when nothing is held or
; when what is held does not repeat. See keypad_read in modules/keypad.s.
key_repeat_code equ     SCRATCH_BASE+$371

; --- the per-channel phase offset a modulator carries ----------------------
; Four 16-bit words, one per channel, added to the programmed phase before it
; is rounded to twelve bits and written to DDS register $10+channel. The
; stock keeps exactly this, at $24CD+2n, and output_dac_update ($E4D0) is
; where it does the addition; see phase_offset_update in modules/phase.s for
; where the value comes from.
phase_offset    equ     SCRATCH_BASE+$372       ; 4 x 2 bytes
phase_product   equ     SCRATCH_BASE+$37A       ; 3 bytes, the 24-bit
stereo_preset   equ     SCRATCH_BASE+$37D       ; which FM stereo preset the
                                                ; page-0 stereo screen shows
stereo_chan     equ     SCRATCH_BASE+$37E       ; the channel stereo_program is
                                                ; setting; $37F is free
                                                ; accumulator the multiply
                                                ; builds by repeated addition,
                                                ; exactly as the stock's does

; --- the backlight setting, which outlives a power cycle --------------------
; THE ARCHITECT'S ADDITION, 2026-09-17: the instrument
; has a fixed three-minute timeout and this makes it settable, with an Off
; setting and a choice of display kind for an aftermarket backlit panel. These
; are ABOVE live_setting because scratch_reset must not clear them - the
; setting is answered once and then kept - and they sit in the fourteen bytes
; that were free between incr_ampl_ch and the per-unit region at $3FEE.
backlight_kind  equ     SCRATCH_BASE+$560       ; 1 byte: 0 the original
                                                ; display, 1 an aftermarket
                                                ; backlit one, which has no
                                                ; timeout at all
backlight_secs  equ     SCRATCH_BASE+$561       ; 2 bytes: the timeout in
                                                ; seconds, 5 to 999, or 0 for
                                                ; Off - the lamp stays on and
                                                ; the field can still be set
backlight_set   equ     SCRATCH_BASE+$563       ; 1 byte: $5A once the setting
                                                ; has been answered. NOT one
                                                ; of the other two: 0 is a
                                                ; legitimate display kind and
                                                ; 0 seconds is a legitimate
                                                ; Off, so neither can mean
                                                ; "not chosen". The $00 a flat
                                                ; battery leaves and the $FF of
                                                ; RAM nobody has written both
                                                ; ask again
BACKLIGHT_MAGIC equ     $5A
BL_ORIGINAL     equ     $00
BL_AFTERMARKET  equ     $01

; --- the RAM bank in the A2U13 socket, option (c) ---------------------------
; A One ROM fitted in place of the 27513 answers to a fifth bank, selected by
; writing $34 where the four pages are $30-$33, and that bank is SRAM the board
; keeps in its own flash. The serial, the options and the twelve save registers
; live there, so they outlive the battery.
;
; ABOVE live_setting for the same reason the backlight bytes are: bank_present
; is answered once at boot and every wrapped accessor reads it, and
; scratch_reset must not clear it between screens.
;
; NEITHER IS PER-UNIT DATA. bank_present is derived at every boot by probing,
; never trusted from RAM; bank_saved_page lives only across one bank_enter.
; Rule 2's four addresses are untouched by any of this - the serial and the
; options stay at $3FFC-$3FFF and are the working copy, with the bank holding
; the durable one.
bank_present    equ     SCRATCH_BASE+$564       ; 1 byte: $5A when the probe
                                                ; at boot found the bank and
                                                ; its signature. Anything else
                                                ; - including the $00 of a
                                                ; flat battery and the $FF of
                                                ; RAM nobody wrote - means no
                                                ; bank, and every wrapped
                                                ; accessor becomes its old self
bank_saved_page equ     SCRATCH_BASE+$565       ; 1 byte: the page that was
                                                ; mapped when bank_enter took
                                                ; the window, so bank_leave can
                                                ; put it back. PAGE_UNKNOWN is
                                                ; a legitimate value here and
                                                ; is restored as itself
bank_work       equ     SCRATCH_BASE+$566       ; 4 bytes: the staging the
                                                ; serial and options pass
                                                ; through on their way in or
                                                ; out of the bank. A copy into
                                                ; the window needs a RAM source
                                                ; and the per-unit bytes cannot
                                                ; be that source directly -
                                                ; $3FFC-$3FFF are read by an
                                                ; interrupt path, and a copy
                                                ; that walked them while one
                                                ; ran would see them change
                                                ; underneath it
BANK_PRESENT_MAGIC equ  $5A
BANK_NUMBER     equ     $34                     ; the value written to
                                                ; page_select: the ASCII digit
                                                ; $34, exactly as pages 0-3
                                                ; are written $30-$33. It read
                                                ; `equ 4` until 2026-09-19,
                                                ; which is what bank_enter
                                                ; wrote while this comment
                                                ; already said $34 - the same
                                                ; bank on a three-bit latch,
                                                ; and the wrong form
BANK_MARK       equ     $34                     ; and therefore what byte 0 of
                                                ; the bank reads back as. A
                                                ; genuine 27513 takes only D0
                                                ; and D1, so $34 selects page 0
                                                ; there and the read-back gives
                                                ; $30 - the probe below fails
                                                ; on real silicon with nothing
                                                ; added to make it

; SCRATCH_END is declared just after live_setting, which it is derived from.

; --- the four channel records ----------------------------------------------
; Twelve bytes each, one per channel, holding everything the front panel can
; set. They are laid out so the frequency - the only field with a hardware
; format that must be written verbatim - starts each record at offset zero,
; which lets the DDS write path take a record pointer and use it directly
; rather than adding an offset it could get wrong.
;
; Frequency is 24 bits in units of 0.1 Hz. That is not a choice: the stock
; firmware writes the entered number to the chip WITHOUT ARITHMETIC OF ANY
; KIND, and its own DTMF table proves the scale - the 697 Hz row is stored as
; $01,$2C,$34 = 6964, and 6964 x 0.1 Hz = 696.4 Hz. So the value an operator
; keys IS the tuning word, and no reference clock enters the calculation.
;
; Phase is 16 bits in units of 0.1 degree, 0 to 3599.
CHAN_FREQ       equ     $00             ; 24-bit, 0.1 Hz units
CHAN_AMPL       equ     $03             ; 24-bit, see amplitude.s
CHAN_PHASE      equ     $06             ; 16-bit, 0.1 degree units
CHAN_WAVE       equ     $08             ; one of the WAVE_* codes
CHAN_DEST       equ     $09             ; one of the DEST_* codes
CHAN_MOD        equ     $0A             ; one of the MOD_* codes
CHAN_STATE      equ     $0B             ; bit 0 output on, bit 1 floating
CHAN_RECORD     equ     $0C             ; bytes per record

; CHANNEL_MAX is not defined here - channel.s owns it, with the rest of the
; channel constants. It was defined in both, and only lwasm noticed.
; --- the live instrument state, saved and recalled as one block -----------
; The four channel records first, then the settings that are not
; per-channel. REGISTER_SIZE covers exactly this, and
; tests/test_scratch_layout.py checks that it does - a register that copied
; more or less than the live state is the fault this layout exists to make
; impossible.
digital_work    equ     SCRATCH_BASE+$2EE       ; two hex characters, for the
                                                ; digital port's two read-outs

; --- routing a modulator to Channel A --------------------------------------
wave_channel    equ     SCRATCH_BASE+$34C       ; the channel being programmed
wave_code       equ     SCRATCH_BASE+$34D       ; its chip-side waveform code
wave_shift      equ     SCRATCH_BASE+$34E       ; 0 or 3, which half of the
                                                ; register it occupies
wave_reg        equ     SCRATCH_BASE+$34F       ; $1D or $1E

routed_dest     equ     SCRATCH_BASE+$350       ; 4 bytes, one a channel: the
                                                ; destination code the channel
                                                ; is ROUTED to on the chip. It
                                                ; is the stock's record+$21,
                                                ; which set_channel_destination
                                                ; ($78BF) reads at $78C5 as the
                                                ; old destination and writes at
                                                ; $7DF9 only after routing; a
                                                ; register recall there leaves
                                                ; it alone and applies the saved
                                                ; code from $24DE+2n ($5404-
                                                ; $5431). It is NOT CHAN_DEST:
                                                ; register_recall copies the
                                                ; saved block over CHAN_DEST
                                                ; before register_apply routes
                                                ; anything, so the record has
                                                ; already forgotten what the
                                                ; sockets still carry. LBL_OFF
                                                ; after dds_reset, as the stock
                                                ; leaves the main menu with
                                                ; every record on $10.
                                                ; port_source, port_index,
                                                ; port_shift and port_reg were
                                                ; these four bytes; port_route
                                                ; keeps them on its stack now

; --- the tone sequencer's on/off phase -------------------------------------
; A tone step has an ON time and an OFF time, so a step is TWO intervals and
; the player alternates between them. The stock keeps the same toggle in bit 0
; of $3D32 and advances its sequence position on every second phase
; (seq_step_advance $42B1: INC $3D32, then act only when bit 0 is now set).
tone_phase      equ     SCRATCH_BASE+$390       ; 0 = a tone is sounding,
                                                ; 1 = the gap after it
; --- the tone screen's selected field, and its increments ------------------
; The stock's sequence screens SELECT a field with a softkey and then commit
; typed digits to whichever is selected - $3C8F is that cursor, and
; key_freq_field, key_amptd_field and key_select_off_time are the arms that
; move it. That is also what makes INCR SET and the arrows possible: they act
; on the selected field, and a screen whose softkeys commit directly has no
; field for them to act on.
; --- the display backlight's idle timeout ----------------------------------
; Counted in MILLISECONDS off MC6840 timer 1, not in passes of the foreground
; loop. Timer 1 is preloaded to one millisecond and NOTHING enables its
; interrupt - grep -rn PTM_IRQ_ENABLE modules/*.s finds it only on timer 2 -
; and error_beep touches only CR1's bit 7, the output enable that drives the
; sounder. So its flag is free for the foreground to poll, and it is a real
; timebase where a count of loop passes is not.
backlight_ms    equ     SCRATCH_BASE+$3A8       ; 16-bit, 1000 down to 0
backlight_s     equ     SCRATCH_BASE+$3AA       ; seconds left of the three
                                                ; minutes

tone_field      equ     SCRATCH_BASE+$3A2       ; 0 frequency, 1 on time,
                                                ; 2 off time
incr_tone_freq  equ     SCRATCH_BASE+$3A3       ; 3 bytes, in the same 0.1 Hz
                                                ; units the step holds
incr_tone_on    equ     SCRATCH_BASE+$3A6       ; 2 bytes: the On time's step,
                                                ; in milliseconds. A WORD, and
                                                ; one byte before: the times
                                                ; themselves run to
                                                ; TONE_MS_MAX = 655, so a step
                                                ; of 500 was stored as its low
                                                ; byte, 244, and steps of 256,
                                                ; 512 and 768 were stored as
                                                ; zero - the arrow going dead
                                                ; while the field still showed
                                                ; the number the operator typed
tone_incr_mode  equ     SCRATCH_BASE+$3AB       ; 1 bytes, and the size is
                                                ; STATED because the gate
                                                ; derives one from the next
                                                ; declaration otherwise, and
                                                ; would score the bytes after
                                                ; it as this cell's. They are
                                                ; NOT free: +$3AC is
                                                ; digital_period, +$3AE is
                                                ; incr_digital and +$3B0 is
                                                ; digital_incr_mode. Every
                                                ; access is a byte - seven
                                                ; clr, one sta, four tst.
                                                ; One-shot: the next ENTER
                                                ; stores an INCREMENT rather
                                                ; than a value, exactly as
                                                ; incr_mode does on the
                                                ; channel screen

; --- the display's on/off control byte -------------------------------------
; The HD44780 has ONE instruction carrying display, cursor and blink together
; ($08 + 4 + 2 + 1), and it is write-only like everything else on that chip -
; so changing one of the three means remembering the other two. The stock
; keeps the same shadow at $242A and lcd_display_control ($D7FE) is its
; six-arm dispatch: cursor on and off, blink on and off, display on and off,
; each ANDing and ORing this byte and writing it.
lcd_control     equ     SCRATCH_BASE+$3B1       ; the last value written
digital_incr_mode equ   SCRATCH_BASE+$3B0       ; one-shot: the next commit
                                                ; stores a STEP, not a value
incr_digital    equ     SCRATCH_BASE+$3AE       ; 16-bit, the period's step,
                                                ; in the same tenths of a
                                                ; millisecond the operator
                                                ; types. The stock has
                                                ; step_period_by_increment on
                                                ; page 2's step dispatch.
digital_period  equ     SCRATCH_BASE+$3AC       ; 16-bit, the bit period in
                                                ; TIMER COUNTS - the operator
                                                ; types tenths of a
                                                ; millisecond and the entry
                                                ; multiplies by ten once. The
                                                ; stock keeps its own at $3C9E
                                                ; in raw timer counts and
                                                ; validate_period_minimum
                                                ; ($4B6D) refuses below $000A -
                                                ; ten counts, which is one
                                                ; tenth of a millisecond, so
                                                ; the minimum here is 1 and
                                                ; means the same interval.
format_point    equ     SCRATCH_BASE+$39A       ; 1 byte: where the decimal
                                                ; point falls in format_fixed's
                                                ; output, counted in digits
                                                ; before it - the stock's $CD50
                                                ; argument. hop_work was here,
                                                ; three bytes of widening
                                                ; scratch for a 24-bit
                                                ; converter; math_work is that,
                                                ; and uint24_to_text copies its
                                                ; source before touching it so
                                                ; a caller may hand it its own
                                                ; working cell.
tone_edit       equ     SCRATCH_BASE+$39B       ; 1 byte: non-zero while the
                                                ; tone sequence editor's
                                                ; session is open, which is the
                                                ; stock's $3D35 -
                                                ; softkey_edit_sequence_insert
                                                ; ($7203) sets it on its first
                                                ; press and
                                                ; repaint_sequence_page
                                                ; ($70C5) then writes the
                                                ; Delete and Insert labels
                                                ; where ' Edit Sequence'
                                                ; stands.
tone_freq_unit  equ     SCRATCH_BASE+$39C       ; 1 byte: UNIT_HZ or UNIT_KHZ,
                                                ; the unit the tone screen's
                                                ; FREQ field is shown in.
                                                ; THE STOCK KEEPS IT PER TONE,
                                                ; at +3 of each sixteen-byte
                                                ; record in the $3C50 array,
                                                ; and show_freq_field ($571F)
                                                ; reads it through $3D22; there
                                                ; is no room here for sixteen
                                                ; more bytes, so this is one
                                                ; cell for the screen and a
                                                ; tone keyed in kHz shows in
                                                ; kHz until another is keyed in
                                                ; Hz. The value is the same
                                                ; either way - the count is
                                                ; tenths of a hertz - and the
                                                ; difference is which of the
                                                ; two forms the field is
                                                ; rendered in.

format_trim     equ     SCRATCH_BASE+$39D       ; 1 byte: non-zero while
                                                ; format_fixed is to blank a
                                                ; trailing zero, which the hop
                                                ; FREQ field's kHz form does
                                                ; and its Hz form does not
hop_freq_unit   equ     SCRATCH_BASE+$39E       ; 1 byte: UNIT_HZ or UNIT_KHZ,
                                                ; the unit the FREQ field was
                                                ; last committed in. The stock
                                                ; keeps it in $2677 for the
                                                ; whole screen rather than per
                                                ; slot, and paint_hop_value_
                                                ; field reads it at $44B1.
dds_phase_work  equ     SCRATCH_BASE+$39F       ; 3 bytes: a hop slot's phase
                                                ; widened to 24 bits so
                                                ; unit_apply can turn
                                                ; thousandths of a radian into
                                                ; tenths of a degree in place,
                                                ; which hop_program needs for a
                                                ; slot carrying HOP_PHASE_RAD

digital_single  equ     SCRATCH_BASE+$399       ; non-zero: clock the pattern
                                                ; out ONCE and stop, the
                                                ; digital twin of tone_single.
                                                ; The stock's key_run_single
                                                ; sits on page 2's dispatch.
digital_page    equ     SCRATCH_BASE+$397       ; the digital screen's softkey
                                                ; page, for the same reason the
                                                ; tone screen has one: more
                                                ; functions than keys, which
                                                ; the stock answers with
                                                ; key_menu_page_change on page
                                                ; 2's dispatch.
digital_base    equ     SCRATCH_BASE+$398       ; how a pattern is shown: 0
                                                ; hexadecimal, non-zero binary.
                                                ; The stock has msg_set_number_base
                                                ; three times over in the same
                                                ; dispatch, one arm per base.
tone_page       equ     SCRATCH_BASE+$394       ; which set of softkey labels
                                                ; the screen is showing. The
                                                ; stock's sequence screens are
                                                ; MENUS with paged softkeys -
                                                ; menu_page_key on page 1
                                                ; calls dispatch_menu_action
                                                ; ($8A2F) and enter_menu_page,
                                                ; the same machinery the Main
                                                ; Selection Level uses - and
                                                ; that is how they fit more
                                                ; functions than there are
                                                ; keys.
tone_end        equ     SCRATCH_BASE+$395       ; how many steps the player
                                                ; walks before wrapping. The
                                                ; stock calls it Seq End and
                                                ; keeps it at $3D0F;
                                                ; seq_step_advance ($42B1)
                                                ; wraps the position on it
                                                ; rather than on the table's
                                                ; capacity. Zero means "not
                                                ; set", and the player then
                                                ; walks all sixteen.
tone_dtmf_mode  equ     SCRATCH_BASE+$393       ; non-zero: the playlist is a
                                        ; DTMF sequence, so each nibble is a
                                        ; dialled digit rather than an index
                                        ; into the sixteen tone tables. This is
                                        ; the instrument's $3C03, which
                                        ; enter_dtmf_sequence_mode ($7A81) sets
                                        ; at $7A97 and tone_sequence_mode_enter
                                        ; ($55C5) clears at $55D9 - ONE
                                        ; sequence, read two ways, which is why
                                        ; the cursor, Seq End and the playlist
                                        ; are shared rather than duplicated.
tone_single     equ     SCRATCH_BASE+$392       ; non-zero: play the sequence
                                                ; through ONCE and stop. The
                                                ; stock's single-shot flag is
                                                ; $3C81, set by seq_run_single
                                                ; ($4A6C) and tested in the NMI
                                                ; body at $4322 against the
                                                ; once-through flag $3D34,
                                                ; which seq_step_advance
                                                ; ($42B1) clears when the
                                                ; position wraps past Seq End.
tone_gate       equ     SCRATCH_BASE+$391       ; the last value written to
                                                ; DDS register $22, so the
                                                ; write is skipped when it has
                                                ; not changed - the stock
                                                ; guards it the same way with
                                                ; CMPB >$3D33 / BEQ at $433F

sum_flags       equ     SCRATCH_BASE+$2F4       ; SUM_ACTIVE and SUM_SPLIT: the
                                                ; two event_flags ($2204) bits,
                                                ; $0800 and $1000, that
                                                ; dds_mux_mask_add_source
                                                ; ($E029), dds_mux_mask_remove_
                                                ; source ($E185) and
                                                ; dds_reg20_program ($DF9F)
                                                ; keep between them. Cleared
                                                ; by dds_reset where the stock's
                                                ; dds_params_reset clears them
                                                ; ($DF8E ANDA #$C7). $2F5 and
                                                ; $2F6 are unused: mod_source,
                                                ; mod_dest and mod_reg were
                                                ; these three bytes, and
                                                ; mod_route keeps its values on
                                                ; the stack now

live_setting    equ     SCRATCH_BASE+$4A8       ; the whole block, 64 bytes.
                                        ; MOVED UP TWENTY-TWO so the digital
                                        ; sequence could take +$380: the tone
                                        ; sequence grew to five bytes a step
                                        ; and filled +$1B0 to +$1FF, where the
                                        ; digital one used to start, and the
                                        ; tone player's two phase bytes went
                                        ; in behind it. Scratch
                                        ; now ends at $3EE5, still far below
                                        ; $3FEE - the serial, the options and
                                        ; the signature are untouched and
                                        ; tests/test_scratch_layout.py checks
                                        ; that on every run.
                                        ;
                                        ; IT MUST BE THE LAST THING IN
                                        ; SCRATCH. scratch_reset clears from
                                        ; SCRATCH_BASE up to here and stops,
                                        ; because the live state is the one
                                        ; part that may survive a power cycle
                                        ; - special function 0 exists to keep
                                        ; it.
                                        ;
                                        ; It sat at +$290 while later
                                        ; variables were declared above it,
                                        ; so those were never cleared. One of
                                        ; them was tick_armed, and a boot
                                        ; from hostile RAM jumped through the
                                        ; stale tick_callback beside it on
                                        ; the first pass of the foreground
                                        ; loop.
                                        ;
                                        ; tests/test_scratch_layout.py
                                        ; refuses any declaration above it.

; The end of the scratch span. DERIVED from live_setting rather than written
; as an offset: it read SCRATCH_BASE+$210 while scratch had grown well past
; that, and both RAM tests used it as their lower bound - so their span ran
; from a point ABOVE their upper bound, the loop stored one byte, verified
; that byte and reported PASS.
SCRATCH_END     equ     live_setting
channel_records equ     live_setting            ; 4 x CHAN_RECORD = 48 bytes,
                                        ; so +$210 to +$23F inclusive. Placed
                                        ; after every existing block rather
                                        ; than in the first gap that looked
                                        ; free: +$A0 collided with
                                        ; live_setting and +$B0 with
                                        ; register_store's 192 bytes, both
                                        ; silently, and both were found by
                                        ; tests/test_scratch_layout.py rather
                                        ; than by reading.
live_globals    equ     live_setting+48         ; 16 bytes: the settings that
                                                ; are not per-channel. The
                                                ; four filter modes and the five
                                                ; special-function
                                                ; preferences live here so a
                                                ; recalled setup restores
                                                ; them too.

; The ceiling freq_ceiling works out for the channel being edited. Three
; bytes, big-endian, in the same 0.1 Hz units as the frequency itself, so the
; comparison in freq_in_range is byte for byte against the value with no
; conversion between them.
freq_limit      equ     SCRATCH_BASE+$240       ; 3 bytes

; --- the four channel latches' shadows -------------------------------------
; The latches at $0C00, $0D00, $0E00 and $0F00 are WRITE-ONLY. Changing one
; bit therefore means knowing the other seven, and the only way to know them
; is to remember what was last written. Without this, setting the presence
; probe bit would clear the range field, and the amplitude would jump by up
; to fifteen octaves with nothing to show why.
;
; The stock firmware keeps the same four bytes at $24F0-$24F3 and routes
; every latch change through one read-modify-write.
latch_shadow    equ     SCRATCH_BASE+$244       ; 4 bytes, one per channel

; --- amplitude conversion working space ------------------------------------
; The 24-bit value being normalised and divided, the 16-bit quotient, and the
; two counters. These are scratch in the strictest sense: they live only
; inside ampl_scale and nothing outside it may read them.
ampl_work       equ     SCRATCH_BASE+$248       ; 3 bytes, big-endian
ampl_trial      equ     SCRATCH_BASE+$24B       ; 3 bytes, the trial difference
ampl_quotient   equ     SCRATCH_BASE+$24E       ; 2 bytes
ampl_shift      equ     SCRATCH_BASE+$250       ; normalising shifts, 0 to 15
ampl_step       equ     SCRATCH_BASE+$251       ; division step, 0 to 12
                                                ; +$252 held a unit byte that
                                                ; three routines stored and
                                                ; nothing read; the head of
                                                ; amplitude.s says how it came
                                                ; to exist and why it is gone

; --- phase conversion working space ----------------------------------------
phase_work      equ     SCRATCH_BASE+$254       ; 2 bytes, the value
phase_quotient  equ     SCRATCH_BASE+$256       ; 2 bytes
phase_step      equ     SCRATCH_BASE+$258       ; division step, 0 to 15

; The bits channel_latch_rmw is to write, already positioned in the byte. It
; is a variable rather than a third register because the 6809 has two
; accumulators and the routine needs a mask, a channel and a value; passing
; the third on the stack made the caller's frame arithmetic part of the
; interface, and that is exactly the kind of coupling that breaks quietly
; when a caller pushes one more register.
latch_bits      equ     SCRATCH_BASE+$25A       ; 1 byte

; Spurious interrupt counts, shown on the Diagnostics screen. Both maskable
; interrupts are masked throughout, so either of these being non-zero is a
; hardware fault worth seeing rather than a normal event. They saturate at
; 255 rather than wrapping: an interrupt storm should read as "many", not as
; whatever 4096 modulo 256 happens to be.
spurious_irq    equ     SCRATCH_BASE+$25B       ; 1 byte
spurious_firq   equ     SCRATCH_BASE+$25C       ; 1 byte

; --- the screens A2U12 carries itself --------------------------------------
screen_mode     equ     SCRATCH_BASE+$25D       ; Save/Recall: 0 save, 1 recall
screen_bit      equ     SCRATCH_BASE+$25E       ; which latch bit the output
                                                ; screen owns
; filter_mode and special_flags are inside live_setting, not here. They
; are part of the instrument's state, so a saved register has to carry them
; and a recall has to restore them - which it cannot do if they sit outside
; the block the register copies.
                                        ; offset 0 held the one filter shape
                                        ; this firmware kept for every
                                        ; channel, and is free now
LIVE_SPECIAL    equ     1               ; offsets within live_globals
LIVE_FILTER_MODE equ    2               ; four bytes, one a channel
LIVE_ACTIVE_MODE equ    6               ; two bytes, the active mode's entry
LIVE_ACTIVE_RECORD equ  8               ; one byte, the record it shows
special_flags   equ     live_globals+LIVE_SPECIAL
filter_mode     equ     live_globals+LIVE_FILTER_MODE
                                        ; the stock's $24E8+ch, numbered
                                        ; FILTER_AUTOMATIC, _SHARP and
                                        ; _LOW_OVER for its 3, 0 and 1, so
                                        ; that a register saved before the
                                        ; port holds zero here and recalls
                                        ; as Automatic, the reset value
; THE ACTIVE MODE, as the address of the resident routine that entered it.
; The instrument keeps no mode number: it keeps the entry routine's address as
; the first word of its 425-byte live state block at $24E6. option_feature_enter
; stores the incoming mode's entry there at l8b1a (LDD 2,S / STD >$24E6) after
; tearing the old mode down, and enter_paged_menu_mode stores its own $8D23.
; Two events read it back: enter_handler_by_index ($F16A) re-enters a recalled
; register's mode with reason 1, and foreground_main_loop ($83A0) at l848d
; re-enters the active mode with reason 2 when keep-state is set - bit 0 of
; $23C2, the low byte LDD >$23C1 / ANDB #$01 tests.
;
; HERE, because this is the block a register carries and the block power-off
; keeps: register_blocks copies all 64 bytes of live_setting into every slot,
; and scratch_reset stops at live_setting. When this was placed no instruction
; reached offsets 6-15 of live_globals, directly or as a live_setting offset,
; so it changed no slot layout and needed no new REGISTER_FORMAT. Offsets 6-8
; are this and active_record now, 9-15 live_stereo; offset 0 is still unused.
;
; NOTHING HERE IS KNOWN TO BE ZERO. scratch_reset stops at live_setting, so
; after a ROM change these bytes are another firmware's, and a slot saved by
; a build before this carries whatever was live here when it was saved. boot.s
; clears both cells with the other globals when the battery signature fails.
; The instrument guards its recall only with the $C239 filler value
; power_on_reinit ($C2C4) writes into unused slots. This firmware re-enters
; only an address equal to one of four mode entries (mode_reenterable in
; main_menu.s), and otherwise leaves the screen where it is.
active_mode     equ     live_globals+LIVE_ACTIVE_MODE
; AND THE RECORD THAT MODE IS SHOWING, the port of $268E: the last byte of
; the same 425-byte block, written by menu_page_show ($89AA) whenever a mode
; changes record, and read back on re-entry - at $5473 by sequence_mode_init
; and after $5440 by enter_channel_config_mode - on reasons 1 and 2 only.
; Measured on the stock 2026-09-16: a register saved on Channel
; Configuration's ch B record, or on record 1 of Tone or Digital Sequence,
; recalls onto that record. Each mode keeps its own cell for the record it is
; on (chan_chain, tone_page, digital_page) and writes this beside it. Like
; active_mode it can hold anything, so an entry reading it back bounds it by
; its own last record first, as enter_channel_config_mode bounds $268E by
; $2242 (CMPB >$2242 / LBHI l5479) before menu_page_show.
active_record   equ     live_globals+LIVE_ACTIVE_RECORD

; AND FM STEREO'S SEVEN NARROW PARAMETERS AS OF THE LAST SAVE - st_pampl,
; st_pphase, st_mode, st_preemph and st_pilot_on, in that order, offsets 9-15,
; the last unused bytes of live_globals. register_save copies them here just
; before live_setting goes into the slot, and register_stereo_unstage copies
; them back out on a recall whose record is FM Stereo. They are a staging
; area and not the live parameters, which stay in scratch where stereo_apply
; and the screen read them: HP's own $257C is the same kind of copy.
LIVE_STEREO     equ     9
live_stereo     equ     live_globals+LIVE_STEREO ; ST_SAVED_NARROW bytes

; THE ENTRY REASON, which every mode entry the instrument re-enters takes as
; its argument and sequence_mode_init reads at $0009,s. This firmware passes
; it in U: page_enter and page_call touch only A, B and X on the way to a
; paged entry, so U arrives as the caller loaded it. main_menu_slot loads
; MODE_COLD, register_restore MODE_RECALL through mode_reenter, and the
; keep-state boot MODE_KEEP.
MODE_COLD       equ     0               ; entered from the Main Selection
MODE_RECALL     equ     1               ; a register recalled into it
MODE_KEEP       equ     2               ; power-on with keep-state set

; --- the Channel Configuration screen --------------------------------------
; chan_text is where a value is assembled with its decimal point before going
; to the display. Twelve bytes: eight digits, a point, and room to spare so a
; caller that miscounts overruns into slack rather than into the next
; variable.
chan_text       equ     SCRATCH_BASE+$261       ; 12 bytes
chan_work       equ     SCRATCH_BASE+$26D       ; 3 bytes, a widened phase
chan_before     equ     SCRATCH_BASE+$270       ; digits before the point
format_keep_zeros equ   SCRATCH_BASE+$25F       ; 1 byte: non-zero while a
                                        ; value is being rendered FOR THE BUS,
                                        ; where a leading zero is a character
                                        ; and not padding. The screen blanks
                                        ; them and the bus keeps them - the
                                        ; stock answers 'FRA?' 0001234.0 -
                                        ; and format_places_zeros in text.s
                                        ; is the entry that sets it. Cleared
                                        ; by every ordinary format_places, so
                                        ; a bus reply cannot leak into the
                                        ; next thing the screen draws.
; ===========================================================================
; THE PARALLEL-PORT POOL, handed out before any parallel port starts.
;
; scratch.inc gives out byte offsets and the layout gate only catches an
; overlap AFTERWARDS - this project has found three by hand already. So when
; several ports run at once, every cell the batch can need is allocated here
; first, in one commit, and each port takes only from its own range. A port
; that needs more than its range stops and says so; it does not take one.
;
; Each range is four bytes, above live_setting with the records, so a
; keep-state power-on preserves them - which is what a per-channel or
; per-field setting needs. A cell that must NOT survive a boot goes below
; live_setting instead, and that is a request to the allocator, not a
; decision a single port makes.
;
; Ranges, by the module that owns them:
;   +$522-$525  modules/remote.s        the bus replies and their units
;   +$526-$529  modules/page1_tone.s    the tone and DTMF screens
;   +$52A-$52D  modules/page2_digital.s the digital sequence screen
;   +$52E-$531  modules/page0_screen.s  the channel screen and the hop screen
pool_remote     equ     SCRATCH_BASE+$522       ; 4 bytes
pool_tone       equ     SCRATCH_BASE+$526       ; 4 bytes
pool_digital    equ     SCRATCH_BASE+$52A       ; 4 bytes
pool_page0      equ     SCRATCH_BASE+$52E       ; 4 bytes
; ===========================================================================

special_number  equ     SCRATCH_BASE+$532       ; 1 byte: which special
                                        ; function the screen is showing, 0 to
                                        ; SPECIAL_COUNT-1. The instrument's
                                        ; screen is one numbered row that
                                        ; NEXT, LAST, UP and DOWN step - not a
                                        ; scrolling list - so the number is
                                        ; state the screen keeps. Below
                                        ; Above live_setting, past the
                                        ; parallel-port pool: scratch_reset
                                        ; stops there, and special_screen_open
                                        ; clears both on entry anyway, so the
                                        ; screen always opens on # 0 whatever
                                        ; the battery held.
special_field   equ     SCRATCH_BASE+$533       ; 1 byte: 0 the number field,
                                        ; 1 the status field. f1 and f2 select
                                        ; them, as they do on the instrument.
; --- one amplitude step per channel, as the stock keeps one per record ----
; THE STOCK KEEPS THE STEP IN THE CHANNEL RECORD AT +15, and three routines
; prove it: show_amptd_step_field ($596E) copies [$23BF]+15 into $3D1D for
; display, hpib_query_amptd_step ($5DEF) formats record+15 as the answer for
; $3D11 = 4, and enter_amplitude_step ($634F) writes record+15 as that field's
; entry arm. This firmware kept ONE shared step, so a destination change on one
; channel cleared the step every other channel would move by, and INCR SET on a
; screen fixed to one channel showed another channel's. The harness saw it
; twice - seed 39 step 30 and seed 44 step 28 - the instrument painting 1 where
; this painted 100.
;
; TWELVE BYTES RATHER THAN A WIDER RECORD. The stock's +15 lies past the end of
; this firmware's twelve-byte CHAN_RECORD, and stretching the record would move
; live_globals, ampl_signs and hop_signs, change REGISTER_LIVE and so
; REGISTER_SIZE, and force REGISTER_FORMAT to 5 so slots written under format 4
; were refused. What the instrument HAS is one step per channel; where those
; bytes live is this firmware's own business, and register_blocks carries
; live_setting and hop_table and reached these bytes under neither layout.
;
; $3FD4-$3FDF, above hop_ampl_codes and fourteen bytes clear of the per-unit
; region the layout gate refuses anything from reaching, $3FEE-$3FFF - the
; serial, the options and the signature.
incr_ampl_ch    equ     SCRATCH_BASE+$554       ; 4 x 3 bytes: channel n's
                                                ; step at +n*3, in microvolts

hop_ampl_codes  equ     SCRATCH_BASE+$534       ; 16 x 2 bytes, $3FB4-$3FD3:
                                        ; each hop slot's 12-bit AMPLITUDE
                                        ; CODE as the chip's hop RAM was last
                                        ; given it - the stock's hop record+2
                                        ; in the $2581 array. dds_write_channel
                                        ; ($DE2E) sends record+2 as it stands
                                        ; and computes nothing, and only three
                                        ; routines ever store it: $BC3E
                                        ; reprogram_all_channels at $BCF6-$BCFA
                                        ; (amplitude hop on), $58A6
                                        ; store_hop_ram_slot (the raw service
                                        ; screen) and $E7F9 dds_table_defaults'
                                        ; clear at le809. So a level typed
                                        ; into a slot while amplitude hop is
                                        ; off changes no code, and the next
                                        ; frequency or phase commit of that
                                        ; slot re-sends the old one. Written
                                        ; here by dds.s hop_program,
                                        ; hop_program_raw and
                                        ; hop_table_defaults; read by
                                        ; hop_write_slot. ABOVE live_setting,
                                        ; so scratch_reset leaves it as the
                                        ; stock's battery leaves record+2.
                                        ; NOT IN A SAVED REGISTER, where the
                                        ; stock's 425-byte copy carries it:
                                        ; the slot has no byte to spare -
                                        ; hp8904a-rewrite/tests/
                                        ; test_scratch_layout.py measures zero
                                        ; bytes between REGISTER_BASE and
                                        ; key_code - and the port log
                                        ; carries that as an x line.
screen_exit     equ     SCRATCH_BASE+$237       ; 2 bytes: THE MODE'S EXIT
                                        ; CALLBACK, the stock's $2213. A mode
                                        ; that has to undo something as the
                                        ; operator leaves it puts the routine
                                        ; here and every path back to the Main
                                        ; Selection Level calls it -
                                        ; call_installed_handler_220f, which
                                        ; arms [3], [5], [6] and [10] of the
                                        ; $8F2A table all run before
                                        ; enter_paged_menu_mode ($8D23).
                                        ; enter_channel_config_mode ($528F)
                                        ; installs $5253, clear_all_destinations,
                                        ; at $54D1/$54D4: leaving the channel
                                        ; screens parks all four channels on
                                        ; Off through set_channel_destination
                                        ; ($78BF), so the sockets go quiet and
                                        ; the relays open. Driven side by side:
                                        ; the stock leaves Channel Config. with
                                        ; levels (0,0,0,0), destinations
                                        ; (10,10,10,10) and latches ($4 x 4),
                                        ; and this firmware left everything
                                        ; live - a difference at the sockets,
                                        ; found by the differential harness at
                                        ; seed 1 step 29.

; The other half of reg_prompt_save, which had no room beside it: the field
; geometry of the screen the Save / Recall prompt is covering. The prompt
; takes the shared field over the way the stock's arm_numeric_entry_field
; ($AC35) takes the shared descriptor at $23A4-$23AF, and hands it back so the
; screen underneath - the Output On/Off screen among them, whose field is one
; character in a different column - echoes into its own field afterwards.
reg_prompt_field equ    SCRATCH_BASE+$239       ; 2 bytes: the covered screen's
                                        ; screen_field_pos and, after it,
                                        ; screen_field_width. +$239 and +$23A
                                        ; sit between screen_exit's two and
                                        ; freq_limit at +$240
tone_unit_last  equ     SCRATCH_BASE+$260       ; 1 byte: the unit code the
                                        ; last committed tone entry was KEYED
                                        ; in. tone_entry_scale_unit consumes
                                        ; tone_entry_unit and clears it - one
                                        ; entry, one unit - which is right,
                                        ; and left the commit with nothing to
                                        ; record: the FREQ field shows its
                                        ; value in the unit it was typed in,
                                        ; as the instrument does from the
                                        ; record's +3 through $3D22.
chan_seen       equ     SCRATCH_BASE+$271       ; a non-zero digit has passed

; The key handler of whichever screen is showing. The foreground calls it for
; every new key; a zero here means no screen is installed, which the
; foreground treats as a fault and recovers from by opening the Main
; Selection Level.
screen_handler  equ     SCRATCH_BASE+$272       ; 2 bytes

; --- the three sequence modes' positions -----------------------------------
; Each mode remembers where it is in its own sequence. They are separate
; bytes rather than one shared position because the three modes can be
; entered in any order and a shared byte would silently move one mode's
; position when another was used.
dtmf_position   equ     SCRATCH_BASE+$274       ; which digit of the string
digital_running equ     SCRATCH_BASE+$275       ; non-zero while clocking out
cow_register    equ     SCRATCH_BASE+$276       ; which chip register the
                                                ; direct-access screen shows
chan_places     equ     SCRATCH_BASE+$277       ; decimal places being shown
chan_index      equ     SCRATCH_BASE+$278       ; which digit is being copied
key_shift       equ     SCRATCH_BASE+$279       ; the one-shot shift latch
entry_active    equ     SCRATCH_BASE+$27A       ; digits have been typed into
                                                ; the selected field and not
                                                ; yet committed or abandoned

; --- the screen a shared handler is currently serving ----------------------
; screen_numeric_key drives Save/Recall, Output On/Off and Output Float, and
; must not know which of them is up. Each screen leaves its commit routine
; and its field geometry here as it paints.
screen_commit       equ SCRATCH_BASE+$27B       ; 2 bytes: what ENTER runs
screen_f1           equ SCRATCH_BASE+$2F0       ; 2 bytes: what f1 runs, or
                                                ; zero where the screen has no f1
hop_phase       equ     SCRATCH_BASE+$359       ; 2 bytes: the 12-bit phase
                                                ; code a hop step is programmed
                                                ; with
hop_ampl        equ     SCRATCH_BASE+$35B       ; 2 bytes: and its 12-bit
                                                ; amplitude code
dds_register    equ     SCRATCH_BASE+$358       ; which chip register the DDS
                                                ; Registers screen is showing.
                                                ; The screen had no selector at
                                                ; all - the register came from
                                                ; how deep the menu stack was.
screen_f4       equ     SCRATCH_BASE+$2A0       ; 2 bytes: what f4 runs, or
                                                ; zero. f4 is the WAY OUT: the
                                                ; stock puts "f4 Exit" on its
                                                ; serial and option screens
                                                ; (firmware/recovery/README.md)
                                                ; and this firmware had no
                                                ; equivalent, so a screen built
                                                ; on screen_numeric_key could
                                                ; be entered and never left -
                                                ; the serial screen among them,
                                                ; which made the flat-battery
                                                ; recovery this firmware exists
                                                ; for impossible to finish.
                                                ; emulator/tests/
                                                ; test_recovery_new.py drives it
screen_field_pos    equ SCRATCH_BASE+$27D       ; the DDRAM position
screen_field_width  equ SCRATCH_BASE+$27E       ; how wide the field is
diag_kbd_last   equ     SCRATCH_BASE+$27F       ; the last key the Keyboard
                                                ; Check screen saw, so LOCAL
                                                ; twice in a row can leave
diag_probe_address equ  SCRATCH_BASE+$354    ; where the display check's
                                                ; address counter ended up.
                                                ; MOVED from +$27E, which
                                                ; screen_field_width already
                                                ; owned.
info_page       equ     SCRATCH_BASE+$355       ; which of the three
                                                ; Firmware Information
                                                ; views is showing. MOVED from
                                                ; +$27F, which diag_kbd_last
                                                ; already owned - and that
                                                ; collision was reachable:
                                                ; KEY_LOCAL is 1 and
                                                ; info_page = 1 is an ordinary
                                                ; state, so the first LOCAL
                                                ; press in Keyboard Check read
                                                ; the Firmware Information
                                                ; page number as "LOCAL was
                                                ; pressed last" and left the
                                                ; screen instead of testing
                                                ; the key.
                                                ;
                                                ; Both sat on top of something
                                                ; else for the whole life of
                                                ; tests/test_scratch_layout.py,
                                                ; because two names at the same
                                                ; offset derive a size of zero
                                                ; and `offset + 0 > offset` is
                                                ; false. The gate now checks
                                                ; equal offsets before it
                                                ; derives anything.
entry_units_w   equ     SCRATCH_BASE+$2F2       ; 1 byte: how many
                                                ; characters of that field the
                                                ; first accepted key blanks,
                                                ; and ZERO once it has - the
                                                ; stock's $23AE together with
                                                ; its $23A7 'already blanked'
                                                ; flag, set by the eight arms
                                                ; at $AD3A from the units class
                                                ; (0, 1 and 2 -> 0; 3 and 6 ->
                                                ; 3; 4 and 5 -> 2; 7 -> 1).
                                                ; memmap_page_char was here -
                                                ; the mapped page as a digit,
                                                ; which nothing referenced.

memmap_index    equ     SCRATCH_BASE+$280       ; which element the Memory Map
                                                ; Access screen has selected

; --- the paged screens' own selections -------------------------------------
; Each screen remembers which entry of its table is showing. They are
; separate bytes because the screens can be entered in any order and a shared
; one would silently move another screen's position.
hop_index       equ     SCRATCH_BASE+$281       ; hop table entry

; --- the Manual CowChip hop-RAM screen's own state -------------------------
; The stock's Ram Addr mode keeps its RAM address and two words in $3FBA,
; $3FBC and $3FBE and its 24-bit field at $3FC2; committing ANY field writes
; the whole slot from all three staged values (store_hop_ram_slot $58A6,
; called by the three ENTER arms with the same four arguments). These are
; that staging, for the raw screen on page 3. They are NOT page 0's
; hop_index: the service screen keeps its own place so leaving it and
; returning to the editing screen does not move the editor's cursor.
p3_slot         equ     SCRATCH_BASE+$286       ; which slot the raw screen
                                                ; is on, 0 to 15
p3_field        equ     SCRATCH_BASE+$287       ; 0 word1, 1 word2, 2 the
                                                ; 24-bit frequency field
p3_w1           equ     SCRATCH_BASE+$288       ; 2 bytes: the staged 12-bit
                                                ; phase code, as typed
p3_w2           equ     SCRATCH_BASE+$28A       ; 2 bytes: the staged 12-bit
                                                ; amplitude code
digital_field   equ     SCRATCH_BASE+$28C       ; the digital screen's level
                                                ; cursor: 0 = the step row,
                                                ; 1 = the mark level, 2 = the
                                                ; space level

; --- the remote-control interface at $0400-$0407 ---------------------------
; Parser and talker state, one contiguous block in free scratch; the
; battery-backed address and SRE mask live at the stock's own $227E/$227F
; (common/ram.inc). All cleared by scratch_reset at power-on.
rmt_flags       equ     SCRATCH_BASE+$120       ; RF_* bits, see remote.s
rmt_char_state  equ     SCRATCH_BASE+$121       ; 0 = expecting a first char
rmt_list        equ     SCRATCH_BASE+$122       ; 2 bytes: the record list
rmt_defer       equ     SCRATCH_BASE+$124       ; 2 bytes: a parked type-2
rmt_defer_arg   equ     SCRATCH_BASE+$126       ; that record's argument
rmt_pend_kind   equ     SCRATCH_BASE+$127       ; RK_* what a value commits to
rmt_pend_chan   equ     SCRATCH_BASE+$128       ; and for which channel/slot
rmt_val         equ     SCRATCH_BASE+$129       ; 3 bytes: mantissa/value
rmt_frac        equ     SCRATCH_BASE+$12C       ; digits after the point
rmt_frac_on     equ     SCRATCH_BASE+$12D       ; a point has been seen
rmt_exp         equ     SCRATCH_BASE+$12E       ; the E exponent magnitude
rmt_exp_neg     equ     SCRATCH_BASE+$12F       ; its sign
rmt_in_exp      equ     SCRATCH_BASE+$130       ; collecting exponent digits
rmt_unit        equ     SCRATCH_BASE+$131       ; unit code of the commit
rmt_rem         equ     SCRATCH_BASE+$132       ; remote_div_ten remainder
rmt_status      equ     SCRATCH_BASE+$133       ; the serial-poll status byte
rmt_tx_ptr      equ     SCRATCH_BASE+$134       ; 2 bytes: queued response
rmt_tx_len      equ     SCRATCH_BASE+$136       ; its length; 0 = nothing
rmt_tx_at       equ     SCRATCH_BASE+$137       ; bytes sent so far
rmt_tmp         equ     SCRATCH_BASE+$138       ; 3 bytes: a value widened for
                                                ; the digit formatter
rmt_seq_owner   equ     SCRATCH_BASE+$13B       ; who took SEQP/SEQE or WSQ: 1
                                                ; the tone screen, 2 the
                                                ; digital, 3 the DTMF
rmt_stream      equ     SCRATCH_BASE+$13C       ; non-zero: bytes are sequence
                                                ; data (after WSQ), not
                                                ; commands, until a terminator
                                                ; or END
rmt_cpt         equ     SCRATCH_BASE+$13D       ; the undecoded-command state
                                                ; the stock keeps in $224D

; THE TWO SHADOWS THE SERVICE-REQUEST LOGIC KEEPS BESIDE THE STATUS BYTE, the
; stock's $224B and $224E. They are not optional bookkeeping: without them a
; status bit raised while a request is already outstanding is lost, and one
; released while a request is outstanding is released too early.
;
;   rmt_srq_pending  = $224B. gpib_assert_service_request ($91E2) tests bit 6
;                      of the status byte first; when rsv is ALREADY set it
;                      may not rewrite $0403 - the controller has not read the
;                      byte it is asking about yet - so it ORs the new event's
;                      weight in here instead, and gpib_serial_poll_service
;                      ($92A5) merges it into the next byte and re-raises SRQ
;                      from it ($92D8 BITB >$2249).
;   rmt_srq_release  = $224E. The deferred half of the same problem.
;                      report_error_and_pulse_status_bit ($9DD3) SETS a status
;                      bit and RELEASES it immediately, and hpib_status_bit_
;                      clear ($9237) can only do the release at once when rsv
;                      is clear; with a request outstanding it records the
;                      weight here and $92AD applies it after the poll.
;
; $224F AND $226A ARE NOT HERE, and that is a finding rather than an omission.
; Both are reached only down legs guarded by the weight being ABSENT from
; $2248 - the BITA >$2248 / BNE $9270 at $9264 for $224F, the BITA ,X / BEQ
; $9279 at $9250 for $226A - and $2248 is always $BF: gpib_driver_init
; ($9AE2) pushes the literal $BF into the record and gpib_chip_init ($8F9F)
; stores it with LDD 2,U / ANDA #$BF / ANDB #$BF / STD >$2248. Every weight in
; the table d929d ($929D) - $01,$02,$04,$08,$10,$20,$00,$80 - is present in
; $BF, so those legs are dead code on this instrument. $92AD's own $226A is
; ~$2248 ANDed with a byte whose bit 6 it has just cleared, which is zero for
; the same reason.
rmt_srq_pending equ     SCRATCH_BASE+$1B5       ; $224B: raised while rsv set
rmt_srq_release equ     SCRATCH_BASE+$1B6       ; $224E: release after the poll

; THE PER-EVENT VALUE STORE, the stock's $226C+index. status_bit_write
; ($9743) does LDX #$226C / STB A,X for every event it raises, so each of the
; eight status bits keeps the error number of the last event that raised it -
; $0C under bit 1, $0D under bit 4, $FF under bits 2 and 3, whatever the
; parser reported under bit 0. The release half never clears it: $9743
; reaches hpib_status_bit_clear ($9237) on a zero B without touching the
; array, so the number stands until that bit is raised again.
;
; ITS ONLY READER IS UNREACHABLE IN THE STOCK, and that is a finding, not a
; guess. read_srq_event_value ($975E) is the read-back, and
; docs/routine-index.txt gives it exactly one caller,
; status_bit_read_wrapper ($9B70); the same index gives $9B70 no caller at
; all, and grep -c for 9b70 or 9B70 over each of the four page listings in
; firmware/src-generated returns 0, so no paged image names that address
; either. Nothing on this instrument can read these eight bytes. The STORE is
; live all the same - it is on the path every service request takes - so it
; is ported and the read-back is not: a routine no caller can reach would be
; a leftover, which is what hp8904a-rewrite/tests/test_reachable.py refuses.
;
; Eight bytes, indexed 0 to 7 by the event's INDEX, which remote_srq_index
; derives from the weight. Index 6 has weight $00 in the stock's table and is
; short-circuited before the store, so its byte is never written.
rmt_srq_value   equ     SCRATCH_BASE+$1B7       ; 8 bytes: $226C+0 to $226C+7

; THE BIT THE SERIAL POLL LEAVES BEHIND, the stock's $2281 bit 8.
; post_flag_2281_b8 ($9A89) is LDD >$2281 / ORA #$01 / STD >$2281 and
; gpib_serial_poll_service calls it at $9309, the last thing every poll does.
; The stock's $2281 is a 16-bit pending-action bitmap whose LOW byte this
; firmware keeps as named booleans instead - rmt_pend_kind, rmt_stream and
; the entry flags - so the one bit that lives in the HIGH byte gets a cell of
; its own here rather than a word that would duplicate them.
;
; NOTHING READS IT, and that too is read rather than assumed: every test of
; $2281 in A2U12 masks A with $00 or $FF and examines the low byte only, and
; the nine references in the four A2U13 pages are all to bit 0 or bit 6 of
; the low byte - the listings' own comments at page 1 line 9719 and page 2
; lines 6275, 6420 and 8219 say "bit 0", "bit 6" and "$40". It is still
; written on every poll because the instrument writes it on every poll.
rmt_poll_flag   equ     SCRATCH_BASE+$1BF       ; $2281 bit 8, set by the poll

; rmt_out IS NO LONGER HERE. It was 72 bytes at +$1B5, reaching +$1FC, and
; it is now hp8904a-rewrite/common/ram.inc's $2285 - the stock's own response
; buffer, 252 bytes, because a sequence report is 250 characters and no hole
; this wide is left in scratch. +$1C0 to +$1FC are free - +$1B5 and +$1B6 are
; the two service-request shadows declared above, +$1B7 to +$1BE the
; eight-byte value store and +$1BF the poll's own bit; +$1FD to +$1FF are the
; three hop cells that were fitted into the gap it left below tone_state.
; +$1C0 to +$1CF now hold the per-channel frequency increment below, and
; +$1D0 to +$1DB are the relay exercise's and the two screen hooks', below;
; +$1DC to +$1FC are free.
;
; THE FREQUENCY INCREMENT, ONE PER CHANNEL, AND THE UNIT IT WAS KEYED IN.
; The stock's record+5 (three bytes, tenths of a hertz, which
; step_channel_frequency ($71DD) adds to +0) and record+8 (the unit key
; enter_freq_value ($6BA5) stores when $2215 is 6). show_freq_increment_field
; ($5A1B) paints the step from +8 - CMPX #$0002 for the Hz layout - and not
; from +3, the unit the VALUE is shown in: harness seed 2 step 131, INCR SET
; on a channel showing 1.000 kHz paints the 100.0 Hz step as ' 100.0  Hz'
; on the instrument. Both reset with the record, from $ED89's +5 and +8.
incr_freq_ch    equ     SCRATCH_BASE+$1C0       ; 4 x 3 bytes: channel n's
                                                ; step at +n*3, 0.1 Hz
relay_saved     equ     SCRATCH_BASE+$1D0       ; 4 bytes: each channel latch as
                                                ; it stood when the relay
                                                ; exercise started - what every
                                                ; way out of it puts back
relay_phase     equ     SCRATCH_BASE+$1D4       ; 1 byte: $00 recorded state, $FF
                                                ; the relay bits flipped
relay_running   equ     SCRATCH_BASE+$1D5       ; 1 byte: non-zero while it cycles
relay_ms        equ     SCRATCH_BASE+$1D6       ; 2 bytes: milliseconds to the
                                                ; next step
screen_poll     equ     SCRATCH_BASE+$1D8       ; 2 bytes: called by the
                                                ; foreground once a pass while a
                                                ; screen has set it; zero is
                                                ; none. screen_install clears it
screen_leave    equ     SCRATCH_BASE+$1DA       ; 2 bytes: run by screen_install
                                                ; before the NEXT screen goes up,
                                                ; however this one is left; zero
                                                ; is none. An A2U12 address -
                                                ; screen_install may be running
                                                ; from any page
incr_freq_unit  equ     SCRATCH_BASE+$1CC       ; 4 x 1 bytes: channel n's
                                                ; UNIT_HZ or UNIT_KHZ
; edit_index is gone. The digital editor had TWO variables for one cursor:
; its key handler moved edit_index while the screen displayed edit_position,
; so NEXT and LAST changed the step being edited and the screen went on
; showing the first one.

; page0_channel_number is declared above, at +$174, with the rest of that
; screen's state.
page0_channel_delta  equ SCRATCH_BASE+$283      ; +1 or -1 while stepping
screen_takes_shift equ  SCRATCH_BASE+$284       ; set by a screen that answers
                                                ; the SHIFTED keys itself: the
                                                ; stock's $220D hook, armed by
                                                ; bit 3 of $2202 - see
                                                ; boot.s foreground_shifted
screen_keeps_local equ  SCRATCH_BASE+$285       ; set by the one screen that
                                                ; needs the LOCAL key for
                                                ; itself; the foreground
                                                ; otherwise treats LOCAL as
                                                ; "go back" on every screen
nav_stack       equ     SCRATCH_BASE+$2D0       ; 4 x 5 bytes: the menus left
                                                ; behind, so Back knows where
                                                ; it came from
; --- what the digital player CARRIES, so its tick does no arithmetic ------
; The instrument keeps its position rather than recomputing it: $3CC6 walks
; the pattern bytes, $3CC9 is the byte being shifted out and the carry of
; ASL >$3CC9 IS the bit. This firmware had digital_byte_of divide the bit
; index by eight on every tick - thirteen instructions inside the interrupt.
; These two are the instrument's pair. They sit in the five free bytes after
; reg_prompt_field, below freq_limit at +$240, and OUTSIDE the twelve bytes
; registers.s copies from digital_bit_index - they are derived state that a
; run start rebuilds, and a saved setup has no business carrying them.
; THE FIRST PLACEMENT WAS INSIDE nav_stack, whose '4 x 5 bytes' is twenty and
; not five. tests/test_scratch_layout.py named the collision, which is what it
; is for.
digital_play_ptr equ    SCRATCH_BASE+$23B       ; 2 bytes: the pattern byte
                                                ; the player is shifting out
                                                ; of, the stock's $3CC6
digital_play_byte equ   SCRATCH_BASE+$23D       ; 1 byte: that byte itself,
                                                ; shifted left a bit a tick -
                                                ; the stock's $3CC9
menu_title      equ     SCRATCH_BASE+$2E4       ; the title of the menu up now

; --- the polled timebase ---------------------------------------------------
entry_units_at  equ     SCRATCH_BASE+$2E6       ; 1 byte: the DDRAM column
                                                ; of the units field beside the
                                                ; armed numeric entry - the
                                                ; stock's $23AF, which
                                                ; open_entry_field_from_locals
                                                ; ($AC35) takes as argument 5
                                                ; at $AC55. tick_count was here
                                                ; - a free-running counter that
                                                ; nothing referenced.

tick_callback   equ     SCRATCH_BASE+$2E7       ; 2 bytes: what wants the tick
dtmf_word       equ     SCRATCH_BASE+$2E9       ; 3 bytes: a DTMF tone widened
                                                ; from the table's 16 bits to
                                                ; the 24 the frequency path
                                                ; takes
hop_running     equ     SCRATCH_BASE+$35E       ; whether fast hop is switched
                                                ; on. Nothing switched it on
                                                ; at all before: the table was
                                                ; editable and programmable
                                                ; and register $1B was written
                                                ; once, by the power-on reset,
                                                ; with the value that means
                                                ; OFF.
line6_count     equ     SCRATCH_BASE+$28D       ; how many foreground passes
                                                ; bit 6 of int_latch has been
                                                ; CLEAR - the stock's counter
                                                ; at 6,s in its main loop
line6_armed     equ     SCRATCH_BASE+$28E       ; the count passed 200 while
                                                ; it was clear, so its return
                                                ; is an event
fault_lines     equ     SCRATCH_BASE+$35F       ; which hardware fault lines
                                                ; were asserted on the last
                                                ; foreground pass, so a change
                                                ; can be reported once rather
                                                ; than every pass
tick_page       equ     SCRATCH_BASE+$35D       ; which page the tick callback
                                                ; belongs to, or PAGE_UNKNOWN
                                                ; when it is in the
                                                ; always-mapped image. A
                                                ; sequence started on a page
                                                ; installs a pointer into
                                                ; $4000-$7FFF, and nothing on
                                                ; the way out of that screen
                                                ; removed it - LOCAL goes
                                                ; through service_back_handler,
                                                ; which reopens a menu and does
                                                ; not disarm the tick. The
                                                ; foreground then jumped
                                                ; through that pointer with a
                                                ; different page in the window.

; ---------------------------------------------------------------------------
; Bytes the page screens took while their ports were written in parallel,
; moved here from the modules that declared them so test_scratch_layout.py
; sees every declaration in one place. Two screens had chosen the same three
; bytes ($37F, $393, $396) for different things; they are apart now, in
; the run after line6_armed (+$28E) that nothing else declares.
; ---------------------------------------------------------------------------
cow_wide_reg    equ     SCRATCH_BASE+$0C        ; Manual CowChip: the width-4
                                                ; register id last written
cow_wide_value  equ     SCRATCH_BASE+$0D        ; 3 bytes: its value, most
                                                ; significant first ($0D-$0F)
dtmf_tick       equ     SCRATCH_BASE+$290       ; DTMF: which interrupt is
                                                ; next, or DTMF_TICK_IDLE
dtmf_gate       equ     SCRATCH_BASE+$291       ; the last value written to
                                                ; register $22 through
                                                ; dtmf_gate_write: the
                                                ; stock's $3D33
dtmf_field      equ     SCRATCH_BASE+$292       ; non-zero while the On Time
                                                ; field is taking digits
dtmf_on_time    equ     SCRATCH_BASE+$293       ; 2 bytes: the On Time in
                                                ; counts, the stock's word 0
                                                ; of $3C10[tone] ($293-$294)
digital_manual  equ     SCRATCH_BASE+$295       ; the stock's Manual flag
                                                ; $3C04: set only at $69BC
                                                ; (enter_manual_mode), cleared
                                                ; at $68DD (stop), $6A23 and
                                                ; $6A64 (the two run keys) and
                                                ; $70C8 (mode_cold_init)
opts_page       equ     SCRATCH_BASE+$298       ; 1 byte: the Installed
                                                ; Options page, 0 to 3
digital_once    equ     SCRATCH_BASE+$29A       ; 1 byte: the stock's $3CC8 -
                                                ; set when a single run passes
                                                ; its end, so the wrap tick
                                                ; after it stops the clock
opts_armed      equ     SCRATCH_BASE+$299       ; 1 byte: non-zero once All
                                                ; Options Off has been pressed
                                                ; once and waits for the second
digital_sign_mark equ   SCRATCH_BASE+$296       ; the mark level's sign, the
                                                ; stock's $3C11
digital_sign_space equ  SCRATCH_BASE+$297       ; the space level's, $3C12
digital_entry_sign equ  SCRATCH_BASE+$28F       ; the sign of the entry in
                                                ; progress: the head of the
                                                ; stock's entry buffer, $239A,
                                                ; which mode 2 reserves for it
; ---------------------------------------------------------------------------
; THE PRESERVED BLOCK, ABOVE live_setting. scratch_reset (boot.s) clears
; SCRATCH_BASE up to live_setting and stops, so everything from live_setting
; up survives a keep-state power-on - which is where a level's sign and the
; phase unit an operator last used have to live: the stock keeps both inside
; the channel record ($24F5+35n+$14 and +$19), and power_on_init ($81AD)
; preserves those records on the keep path. Below live_setting they were
; cleared on every boot and a negative dc level came back positive; the
; critique of 2026-09-02 found it. A cold boot leaves them zero, which
; ampl_level_raw reads as '+' and chan_show_phase reads as degrees.
; ---------------------------------------------------------------------------
ampl_signs      equ     SCRATCH_BASE+$4E8       ; 4 bytes: each channel's
                                                ; level sign, '+' or '-' -
                                                ; the stock's record+$14,
                                                ; which scale_to_dds_code
                                                ; reads at $D4DC-$D4E2 and
                                                ; tests against '-' at $D4E7;
                                                ; anything else is positive.
                                                ; Written by ampl_set,
                                                ; ampl_set_signed and
                                                ; register_recall, which
                                                ; carries it as a span of
                                                ; every saved register - the
                                                ; stock's 425-byte copy at
                                                ; page 0 $52B2 brings +$14
                                                ; back with the record
ampl_sign_req   equ     SCRATCH_BASE+$29C       ; the sign the ampl_set call
                                                ; in progress was handed,
                                                ; held until its range check
                                                ; passes ($6613 and $4CF1
                                                ; both store after the check)
ampl_wave_dc    equ     SCRATCH_BASE+$29D       ; non-zero while ampl_scale
                                                ; runs for a dc record, which
                                                ; skips the rounding ($D47A
                                                ; CMPX #$0004 / $D47D BEQ);
                                                ; set and cleared by
                                                ; ampl_level_raw alone
ampl_carrier_code equ   SCRATCH_BASE+$29E       ; 2 bytes: $23BC, the full
                                                ; scale a modulation depth is
                                                ; a fraction of. It is
                                                ; channel 0's twelve-bit code
                                                ; AFTER the shift onto its
                                                ; destination's common
                                                ; exponent and BEFORE the AM
                                                ; halving - the value
                                                ; rescale_channel_dacs stores
                                                ; at $BE19 LDD 5,S / $BE1B
                                                ; STD >$23BC, one instruction
                                                ; before $BE1E LSR 5,S.
                                                ; grep 23bc src-generated/*.s
                                                ; gives three lines in all
                                                ; five images: that write, and
                                                ; the two reads in
                                                ; level_scale_by_cal ($BB98)
                                                ; at $BBB1 and $BBF7.
                                                ; It is not calibration data
                                                ; despite that routine's name
                                                ; - it is computed at run
                                                ; time, so it lives below
                                                ; live_setting and starts as
                                                ; zero after scratch_reset
chan_phase_unit equ     SCRATCH_BASE+$4FC       ; channel screen: 4 bytes, one per
                                                ; channel:
                                                ; CHAN_UNIT_RAD, or anything
                                                ; else for degrees - zero
                                                ; after scratch_reset
chan_phase_rad  equ     SCRATCH_BASE+$500       ; 4 x 2 bytes: the phase in
                                                ; milliradians, record+$17's
                                                ; twin
chan_incr_rad   equ     SCRATCH_BASE+$508       ; 2 bytes: the increment in
                                                ; milliradians, record+$1D's
                                                ; twin
hop_saved_flags equ     SCRATCH_BASE+$50A       ; 2 bytes: the snapshot the
                                                ; four hop function enables
                                                ; are re-applied from - byte
                                                ; 0 is mode_flags as last
                                                ; snapshotted, byte 1 is
                                                ; hop_running. The stock's
                                                ; $267F/$2681, snapshots of
                                                ; its live $2204/$2202:
                                                ; set_hop_function_enable
                                                ; ($4984) ends at l4bcb
                                                ; ($4BCB) with LDD >$2204 /
                                                ; STD >$267F / LDD >$2202 /
                                                ; STD >$2681, and
                                                ; enter_channel_config_mode
                                                ; ($528F) ends the same way
                                                ; at l54bf ($54BF) before
                                                ; its RTS; past the $5301
                                                ; LBEQ l53f7 gate it reads
                                                ; them back into 5,s/7,s and
                                                ; l5372-l53f4 ($5372-$53F4)
                                                ; re-applies each set bit
                                                ; through $4984 with $0011 -
                                                ; on its arg-1 path, a
                                                ; register recall ($52B2),
                                                ; and its arg-2 path, the
                                                ; keep-state boot:
                                                ; foreground_main_loop
                                                ; ($83A0) at l848d ($848D)
                                                ; tests bit 0 of $23C2 and
                                                ; calls LDB #$02 / ... / LDX
                                                ; >$24E6 / JSR ,X. They sit
                                                ; inside the $24E6-$268E
                                                ; block the stock's recall
                                                ; copies ($52B2-$52F2, $01A9
                                                ; bytes from $268F+425n), and
                                                ; no instruction in A2U12
                                                ; touches them (grep -i
                                                ; '267f|2681' over
                                                ; a2u12.s: comment lines
                                                ; only), so a keep-state
                                                ; boot preserves them -
                                                ; which is why this pair is
                                                ; above live_setting, where
                                                ; scratch_reset stops.
                                                ; Written by hop_snapshot
                                                ; (page0_hop.s) and
                                                ; register_recall
                                                ; (registers.s, a span of
                                                ; every saved register as
                                                ; $267F/$2681 are inside the
                                                ; stock's), cleared on
                                                ; boot's cold path as the
                                                ; arg-0 entry's l54bf
                                                ; snapshot of the reset
                                                ; flags clears the stock's;
                                                ; read by hop_reapply.
hop_signs       equ     SCRATCH_BASE+$4EC       ; 16 bytes, one per hop slot:
                                                ; the slot level's sign, '-'
                                                ; or anything else for
                                                ; positive - the stock's hop
                                                ; record+10 in the $2581
                                                ; array, which
                                                ; scale_to_dds_code reads at
                                                ; $D4B2-$D4C8 for channel 0
                                                ; while amplitude hop is on
                                                ; ($D4AB LDD >$2202 / ANDB
                                                ; #$40) and store_hop_amptd
                                                ; ($4CD5) writes at
                                                ; $4D59-$4D71 from the entry
                                                ; sign $241E when $2514 is 4
                                                ; ($4D4F-$4D58). Read by
                                                ; hop_program in dds.s;
                                                ; carried by every saved
                                                ; register (registers.s
                                                ; register_blocks), as the
                                                ; stock's image $24E6-$268E
                                                ; carries $2581+15n+10.
                                                ; Written by register_recall
                                                ; and by page0_hop.s
                                                ; hop_sign_store: ENTER and
                                                ; the arrows on the AMPL
                                                ; field while channel 0 is
                                                ; dc, the stock's $70AC,
                                                ; $7590, $75BC and $7602
                                                ; calls of $4CD5. A zero
                                                ; from scratch_reset reads
                                                ; positive.
hop_entry_sign  equ     SCRATCH_BASE+$1FD       ; hop screen: the sign of the
                                                ; AMPL entry in progress, '+'
                                                ; or '-' - the head of the
                                                ; stock's entry buffer $239A
                                                ; while entry_cfg_hop_amptd
                                                ; ($503D) has armed its kind-2
                                                ; layout ($5066-$5072): '+' as
                                                ; the field is armed ($ACE8),
                                                ; '-' from MINUS ($B038),
                                                ; copied to $241E at $CE1B for
                                                ; store_hop_amptd ($4CD5).
                                                ; Written by hop_entry_begin
                                                ; and hop_sign_key. Its own
                                                ; byte rather than
                                                ; chan_entry_sign, so no
                                                ; screen's entry can inherit
                                                ; another's sign. In the three
                                                ; bytes between the freed
                                                ; rmt_out block and tone_state
hop_step_sign   equ     SCRATCH_BASE+$1FE       ; the sign an AMPL step on the
                                                ; hop screen will commit, or
                                                ; zero when the step is
                                                ; unsigned: $241E as
                                                ; step_hop_amplitude ($7533)
                                                ; keeps it, cached at
                                                ; $7533-$753B and flipped at
                                                ; $75F0/$75F8. Written by
                                                ; hop_step_field,
                                                ; hop_step_ampl_sign and
                                                ; hop_step_cross
hop_entry_active equ    SCRATCH_BASE+$1FF       ; hop screen: non-zero while
                                                ; a digit or MINUS has gone
                                                ; into the armed field and
                                                ; nothing has ended the
                                                ; entry - the stock's
                                                ; first-key flag $23A7, which
                                                ; numeric_entry_key_handler
                                                ; ($B3C2) sets at $B521 on
                                                ; the first accepted key and
                                                ; tests at $B4C4 before a
                                                ; BACKSPACE repaint, and
                                                ; which
                                                ; arm_numeric_entry_field
                                                ; ($AC35) clears at $AC84 as
                                                ; a field is armed. Set by
                                                ; hop_key_digit and
                                                ; hop_sign_key, cleared by
                                                ; hop_entry_begin and
                                                ; hop_addr_entry_begin;
                                                ; while set, hop_show paints
                                                ; the entry (hop_entry_echo)
                                                ; in place of the stored
                                                ; value. The last of the
                                                ; three bytes rmt_out leaves
                                                ; free below tone_state
; THE UNIT KEY THAT TERMINATED THE ENTRY, which is the stock's $2221. The unit
; keys are not decoration: on the instrument a numeric field is COMMITTED by Hz,
; kHz or deg, and which key was pressed says what the digits meant.
; accept_units_key ($B0C1) dispatches through the table at $B212 on the field's
; units class and stores the resulting unit code in $2221, and
; entry_to_scaled_digits ($CDE1) then indexes $CF9A with it for the decade. This
; byte carries the same code from the key arm to the commit, where
; ABI_unit_apply scales the typed digits by it.
; THE SAME THING FOR THE TONE AND DTMF SEQUENCE SCREENS, which share one key
; handler behind tone_dtmf_mode. Their fields carry four of the stock's units
; classes - FREQ is 6, the On and Off times are 5, the level is 4, and Seq Index
; and Seq End are 2 - and the key that ends the entry says which unit the digits
; were in, exactly as it does on the channel screen. A cell of its own because
; the two screens open one after the other and a code left from one must not
; reach the other's commit.
; THE MEMORY MAP SCREEN'S SUB-ADDRESS, the stock's $3FAD. An element is not
; one byte: the HP-IB interface at $0400 and the timer at $1000 are eight
; registers each, and the up and down keys walk within the element while NEXT
; and LAST step between them. It is cleared whenever an element is selected,
; which is what memmap_select_element's tail does at page 3 $50B1.
; THE MENU ANNOTATION HOOK. A menu whose entries have a STATE - the Special
; Functions screen's five preferences, the Options screen's eight bits - needs
; to show it beside the entry, and menu_draw draws a label and a submenu
; marker and nothing else. A menu that wants one stores its painter here after
; menu_open and menu_draw calls it with the entry index in B.
;
; Cleared by screen_install, like screen_commit and the two f-key vectors and
; for the same reason: a menu that does not set one must not inherit the last
; menu's.
menu_annotate   equ     SCRATCH_BASE+$2A6       ; 2 bytes. NOT +$2A3:
                                                ; st_freq at +$2A2 is three
                                                ; bytes and reaches +$2A4, and
                                                ; memmap_sub has +$2A5.
                                                ; tests/test_scratch_layout.py
                                                ; caught the collision
; THE MANUAL MEMORY READ/WRITE SCREEN'S STATE. manual_memory_screen_handler
; ($5F96) keeps an address at $3FC8, a field selector at $3FB4 and the A2U13
; page number at $3FCB, which it seeds from $247B - the page A2U12 last
; selected - so the window can be read a page at a time.
memw_addr       equ     SCRATCH_BASE+$2A8       ; 2 bytes
memw_field      equ     SCRATCH_BASE+$2AA       ; 1 byte: 0 address, 1 data
memw_page       equ     SCRATCH_BASE+$2AB       ; 1 byte
; WHICH FIELD THE MANUAL COWCHIP SCREEN IS TYPING INTO. The stock keeps it at
; $3FB4 and its handler's requests $13 and $14 select field 0 or 1;
; cowchip_entry_arm_index ($5AAD) is arm 0 of the entry table at $5C67 and
; takes five digits into the REGISTER NUMBER, while
; cowchip_enter_register_value ($5B08) is the arm that takes the value.
; Without the first of those the only way to reach register 39 is thirty-nine
; presses of NEXT.
cow_field       equ     SCRATCH_BASE+$2AC       ; 1 byte: 0 register, 1 value
; THE UNIT KEY THAT ENDED A HOP ENTRY, the stock's $2221 for this screen's
; fields. The Hop Table's four fields are units-class fields like every other:
; arm_hop_frequency_editor ($5024) sets class 6, entry_cfg_hop_amptd ($503D)
; class 4, entry_setup_hop_phase ($5086) class 3 and entry_cfg_hop_address
; ($50E6) class 2 - so Hz and kHz commit a frequency, the three level keys an
; amplitude, ENTER or deg a phase, and ENTER alone the address.
hop_entry_unit  equ     SCRATCH_BASE+$2AD       ; 1 byte
; HOW MANY CHARACTERS ampl_text's ANSWER OCCUPIES, so a screen that shows
; fewer than the whole field knows where the answer starts. ampl_autorange
; returns five when the decimal point would have landed past the last digit
; it emits and six otherwise, and ampl_text right-aligns whichever it got -
; so the first character is not at a fixed offset. The Channel Configuration
; screen shows the FIRST FIVE, which is what write_unit_label_and_digits
; ($576C) writes, and without this it showed the first five of the wrong
; place: '.0000' for one volt, or '   50' for 500 microvolts.
chan_ampl_len   equ     SCRATCH_BASE+$2AE       ; 1 byte
; WHICH SEQUENCE SCREEN THE OPERATOR IS WORKING IN, so a save knows which of
; the two models to put in the register's one sequence slot. The tone and DTMF
; screens set it to SEQKIND_TONE as they open and the digital screen to
; SEQKIND_DIGITAL; a register saved before either has been opened carries
; SEQKIND_NONE and recalls neither.
;
; The instrument needs no such byte: its two models overlap in RAM, so there
; is only ever one sequence to save. See REGISTER_SEQBLOCK in
; hp8904a-rewrite/common/ram.inc: the slot is 257 bytes of every register,
; staged into it directly and no longer through a buffer of its own.
seq_kind_live   equ     SCRATCH_BASE+$2AF       ; 1 byte
; THE DIGITAL SEQUENCE'S WORKING WORDS, which the stock keeps at $3CA2-$3CCE.
; They are indices into the pattern and are rebuilt from it, so unlike the
; pattern itself they belong in scratch.
;
;   digital_index   the cursor, the stock's $3CA2 - a 0-BASED digit index
;   digital_end     Seq End, its $3CA4 - the 0-based index of the LAST digit,
;                   so the length is one more. The screen shows both 1-based,
;                   which is what $6260's SUBD #$0001 on a typed value says
;   digital_max     the highest index this base allows, its $3CCE - 999, 332
;                   or 249, one less than the count set_max_length_for_base
;                   ($56A3) installs
;   digital_window  the first digit the sixteen-cell window shows, its $3CD2
digital_index   equ     SCRATCH_BASE+$2B0       ; 2 bytes
digital_end     equ     SCRATCH_BASE+$2B2       ; 2 bytes
digital_max     equ     SCRATCH_BASE+$2B4       ; 2 bytes
digital_window  equ     SCRATCH_BASE+$2B6       ; 2 bytes
digital_shift   equ     SCRATCH_BASE+$2B8       ; 1 byte: a bit offset, while
                                                ; one digit is being cut out
digital_wide    equ     SCRATCH_BASE+$2B9       ; 1 byte: the digit's width
digital_last_bit equ    SCRATCH_BASE+$2BA       ; 2 bytes: the last bit the
                                                ; player clocks out, which is
                                                ; the stock's $3CAA. Kept in
                                                ; BITS because the player is
                                                ; base-agnostic: its ISR at
                                                ; $4196 never reads $3C20, it
                                                ; shifts bits out of the
                                                ; pattern and compares its
                                                ; counter with $3CAA

memmap_sub      equ     SCRATCH_BASE+$2A5       ; 1 byte
tone_entry_unit equ     SCRATCH_BASE+$2BC       ; 1 byte
chan_entry_unit equ     SCRATCH_BASE+$2BD       ; 1 byte
chan_entry_sign equ     SCRATCH_BASE+$2BE       ; channel screen: the sign of
                                                ; the AMPL entry in progress,
                                                ; '+' or '-'. The head of the
                                                ; stock's entry buffer $239A,
                                                ; which entry mode 2 reserves
                                                ; for it - '+' at $ACE8, '-'
                                                ; from MINUS at $B038 - and
                                                ; entry_to_scaled_digits
                                                ; copies to $241E at $CE1B
chan_step_sign  equ     SCRATCH_BASE+$2BF       ; the sign an AMPL step will
                                                ; commit, or zero when the
                                                ; step is unsigned: $241E as
                                                ; step_amptd_by_increment
                                                ; ($7259) keeps it, cached at
                                                ; $7261 and flipped at
                                                ; $733E/$7346

; THE REPEATING ROM CHECK'S OWN STATE. The Diagnostics ROM Checksum screen is
; the stock's rom_check_loop ($446C) ported: it walks the five images one per
; pass and keeps a running pass and fail count FOR EACH, so an intermittent
; device shows up as a fail count that climbs while the others stay at zero.
; A single pass/fail cannot show that, which is the whole reason the stock's
; screen repeats. Eleven bytes in the gap between chan_step_sign and
; nav_stack, which is 17 bytes wide.
diag_rom_index  equ     SCRATCH_BASE+$2C0       ; 1 byte: which image the next
                                                ; pass sums. 0 is A2U12, 1 to
                                                ; 4 are A2U13 pages 0 to 3
diag_rom_passes equ     SCRATCH_BASE+$2C1       ; 5 bytes, one per image
diag_rom_fails  equ     SCRATCH_BASE+$2C6       ; 5 bytes, one per image
diag_rom_addr_w equ     SCRATCH_BASE+$2CB       ; 2 bytes: the CPU address of
                                                ; the selected image's
                                                ; compensation byte, staged
                                                ; while line 1 is painted
diag_rom_offs_w equ     SCRATCH_BASE+$2CD       ; 2 bytes: the low four digits
                                                ; of that byte's offset into
                                                ; the burn set
diag_rom_offs_t equ     SCRATCH_BASE+$2CF       ; 1 byte: and its fifth digit,
                                                ; which is non-zero only on a
                                                ; build with more than four
                                                ; pages

; WHICH UNIT EACH CHANNEL'S FREQUENCY WAS LAST KEYED IN. The stock keeps it
; in the channel record at +3 and draw_channel_frequency ($54E6) reads it to
; choose the layout: code 2 (' Hz') blanks up to six leading zeros and puts
; the point after seven digits, anything else blanks three and puts it after
; four. So 25000 Hz and 25 kHz are the same frequency and DIFFERENT displays -
; driven on the stock, they read '25000.0  Hz' and '25.000  kHz'.
;
; ABOVE live_setting, with the five that were already there, and for their
; reason: it is part of the instrument's setting and has to survive a power
; cycle exactly as the setting does. It is NOT in the twelve saved registers,
; where the stock's is - a recalled setup shows its frequency in the unit the
; screen was last using rather than the one it was saved with. Putting it
; there would change the register format, and that is the architect's to
; decide, not a display's to force.
tone_time_unit  equ     SCRATCH_BASE+$51C       ; 2 bytes, On then Off: the
                                                ; unit each sequence time was
                                                ; KEYED in, which is what the
                                                ; screen shows it back in -
                                                ; the stock's $3C87 and $3C89,
                                                ; the pair
                                                ; select_tone_and_time_pointers
                                                ; ($561A) points $3D17 at.
                                                ; Driven on the stock
                                                ; 2026-09-11: 5 then Hz reads
                                                ; '  5.00ms' and 2 then kHz
                                                ; leaves '.00500 s' - the unit
                                                ; changes even when the value
                                                ; is refused
chan_ampl_keyed equ     SCRATCH_BASE+$510       ; 4 bytes, one a channel:
                                                ; WHICH UNIT the AMPTD field
                                                ; was last keyed in, as the
                                                ; stock keeps it in the channel
                                                ; record at +13 and reads it
                                                ; back through $4FBE and
                                                ; render_value_with_units
                                                ; ($564E). Only the radian
                                                ; twin needs it here - every
                                                ; other unit the field takes
                                                ; is the destination's own -
                                                ; and it is out of the record
                                                ; because a thirteenth byte
                                                ; would change every saved
                                                ; register, which is how
                                                ; chan_phase_unit and
                                                ; chan_freq_unit are kept too
chan_ampl_rad   equ     SCRATCH_BASE+$514       ; 8 bytes, one WORD a channel:
                                                ; the phase deviation AS TYPED,
                                                ; in milliradians. The stock
                                                ; stores the keyed number
                                                ; itself in record+10 and the
                                                ; unit beside it, so '3' comes
                                                ; back as '3.000 rad' and not
                                                ; as the 2.999 a reconversion
                                                ; of 171.9 tenths would give -
                                                ; the same reason chan_phase_rad
                                                ; exists for the PHASE field
chan_freq_unit  equ     SCRATCH_BASE+$50C       ; 4 bytes, one per channel


; THE FILTER LINE EACH CHANNEL IS SET TO, one byte apiece. This is the stock's
; $24EC, and this firmware derived the same answer on demand instead of
; storing it - which agreed with the instrument at all six sites
; recompute_channel_byte_24ec ($F7EC) writes it, and disagreed at the seventh.
;
; The seventh is a sequence-mode entry: seq_mode_defaults ($5224) loads #$01
; at $536C and calls set_channel_byte_24ec ($F713) at $5378 with index 0, so
; entering Tone or DTMF Sequence FORCES channel 0's byte to 1 and drives the
; line from it. A forced value is an OVERRIDE of the derivation, not an input
; to it, so there has to be somewhere to keep it: derived afresh, the next
; commit would undo it. Measured by the differential harness 2026-09-12 - the
; stock's channel 0 latch reads $01 after a tone entry and this firmware's
; read $00.
;
; Above live_setting, with the records it belongs beside, so a keep-state
; power-on preserves it as it preserves them.
filter_auto     equ     SCRATCH_BASE+$51E       ; 4 bytes, one a channel:
                                                ; LATCH_FILTER or zero, the
                                                ; value the line is driven to
