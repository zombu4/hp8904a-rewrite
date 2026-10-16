; ===========================================================================
; service_menu.inc - the service menu's structure, as data
;
; THE PROBLEM THIS REPLACES
;
; Everything a service engineer needs on this instrument is hidden, and two
; of the three ways in are undocumented numbers:
;
;   SHIFT SPECIAL 87 ENTER    serial number entry     (manual page 8-43)
;   SHIFT SPECIAL 48 ENTER    option installation     (manual page 8-46)
;   SHIFT SPECIAL 37 ENTER    the available-option list  (UNDOCUMENTED - it
;                             is in no page of 08904-90008; found by reading
;                             the comparison at page 3 $6C53)
;
; and the diagnostics menu behind them is gated by a six-digit access code,
; 092448, held as ASCII at page 3 $4466 and compared with mem_compare_bytes.
;
; A number you must already know is not a security measure on a signal
; generator. It is a way to lose access to your own instrument, and combined
; with the serial/option deadlock it is how a flat battery turned into a
; board replacement.
;
; WHAT THIS DOES INSTEAD
;
;   - No access code. None. The diagnostics menu is an ordinary entry.
;   - No numbers to memorise. Every entry is named for what it does.
;   - Nothing gated on anything. No entry is hidden by an option bit, a
;     serial-number state, or a flag.
;   - Every screen the stock firmware has is reachable, plus the two the
;     stock firmware makes unreachable once the battery has gone flat.
;
; THE STRUCTURE
;
; One table, walked by the menu renderer. Each entry is a fixed-size record
; so the renderer can index it without a per-entry length walk:
;
;   +0  .. +39   forty characters of label, space-padded, no terminator.
;                The LCD line is forty characters, so a label that fits the
;                record fits the screen exactly - there is no case where a
;                name is silently truncated at run time, and writing the
;                whole line means the tail of the previous screen cannot
;                show through.
;   +40 .. +41   address of the handler for this entry
;   +42          flags, see SVC_* below
;
; Forty-three bytes per entry. The label is stored plainly rather than
; compressed or indexed into a string pool: the pool would save perhaps four
; hundred bytes and cost every reader of this table an indirection, and this
; ROM has room.
;
; The record was twenty-three bytes with a twenty-character label until the
; display geometry was actually checked against the stock firmware. It is
; forty by two - lcd_repaint_both_lines ($D989) writes $28 characters per
; line - and every label here had been written to the wrong width.
; ===========================================================================

SVC_LABEL_LEN   equ     LCD_COLUMNS     ; one whole LCD line, so a
                                        ; label always clears what
                                        ; the last screen left
SVC_ENTRY_SIZE  equ     SVC_LABEL_LEN+3 ; label + handler + flags,
                                        ; derived so the two can
                                        ; never disagree again

; --- Entry flags -----------------------------------------------------------
; A byte of flags per entry. Two are defined; the rest are reserved and must
; be written zero, so that a later firmware can use them without a stale bit
; changing what an old entry means.

SVC_PLAIN       equ     $00             ; ordinary entry, just call it
SVC_SUBMENU     equ     $01             ; the handler opens another menu
SVC_BACK        equ     $04             ; this entry LEAVES the menu, so the
                                        ; runner must not remember the menu
                                        ; before calling it.
                                        ;
                                        ; menu_key_run pushed the current menu
                                        ; onto the navigation stack for every
                                        ; entry without exception, and Back is
                                        ; an ordinary record. So pressing it
                                        ; wrote the menu now showing into slot
                                        ; N, stepped nav_top to N+1, and then
                                        ; service_back_handler decremented to
                                        ; N and read back the entry just
                                        ; written - reopening the menu the
                                        ; operator was trying to leave, on the
                                        ; first press, from any depth.
SVC_DESTRUCTIVE equ     $02             ; changes stored state or disturbs
                                        ; the output; the renderer marks it
                                        ; so nobody walks into a destructive
                                        ; RAM test expecting a read-only one

; ---------------------------------------------------------------------------
; A menu record is written out directly rather than through a macro:
;
;       fcc     "Serial Number                           "      exactly forty characters
;       fdb     serial_screen               the handler
;       fcb     SVC_SUBMENU                 the flags
;
; A macro was tried and does not survive both assemblers. lwasm splits macro
; arguments on WHITESPACE as well as commas, so a quoted label containing
; spaces arrives as `"Serial` and the rest is lost - and a comment on the
; body's fcc line is swallowed into the operand. Three directives are clearer
; than fighting that, and they mean the same thing to both assemblers.
;
; hp8904a-rewrite/tests/test_menu_complete.py counts every label and fails on
; any that is not forty characters, because a thirty-nine-character one shifts
; every following byte of the record and makes the handler address garbage. It
; caught one while this file was being written: "* INSTALLED OPTIONS *" is
; forty-one.
;
; That gate used to be named here as test/native_menu_selftest.py, which does
; not exist and never did - `find . -name "native_menu_selftest*"` returns
; nothing. The check is real and the catch it describes is real; only the path
; was invented, and a comment naming a gate that is not there is exactly what
; the no-lying rule was written about.
; ---------------------------------------------------------------------------
