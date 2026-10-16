; ===========================================================================
; conventions.inc - the calling convention this rewrite uses
;
; The stock firmware was compiled, and its convention shows it: every routine
; opens by loading a frame-size word out of a pool and calling a shared
; allocator, whether or not it has a single local. Arguments go on the stack
; behind a byte-count word. It costs six bytes and a subroutine call at each
; of 180 sites, plus 360 bytes of pool words, plus a LEAS to unwind.
;
; That convention exists so a compiler can generate code without thinking.
; A person writing assembly can do better, and this is what this rewrite
; uses instead.
;
; ---------------------------------------------------------------------------
; REGISTERS
; ---------------------------------------------------------------------------
;
;   D (A:B)   first argument, and the return value
;   X         second argument, and a pointer return
;   Y         third argument; otherwise free for the callee
;   U         frame pointer ONLY where a routine genuinely needs one;
;             otherwise a fourth scratch register
;   S         hardware stack. DP is fixed at 0 and never written, so every
;             direct-page access is to $00xx and `<` is only used where that
;             is what is meant.
;
; A routine may destroy D, X and Y unless its own comment says otherwise.
; It must preserve U and S. This is stated once here rather than repeated in
; 400 routine headers; a routine that differs says so at its own head.
;
; ---------------------------------------------------------------------------
; ARGUMENTS
; ---------------------------------------------------------------------------
;
; Up to three arguments go in D, X and Y. That covers almost everything in a
; ROM of this kind. A routine needing more takes a POINTER to a block in D,
; which is cheaper and clearer than pushing four words and unwinding them.
;
; There is no argument byte-count word. The compiler needed one because its
; callee unwound the caller's arguments; here the caller cleans up whatever
; it pushed, which is one instruction it was going to execute anyway.
;
; ---------------------------------------------------------------------------
; RETURN VALUES
; ---------------------------------------------------------------------------
;
;   a value       in D, or in B for a byte
;   a pointer     in X
;   a yes/no      in the Z flag, and SAY SO in the routine's comment
;
; A boolean returned in a register AND in a flag is a routine with two
; answers that can disagree. Pick one. Where a routine returns a flag, its
; header states which flag and which sense, because "returns true" is not a
; fact about a 6809.
;
; ---------------------------------------------------------------------------
; NAMES
; ---------------------------------------------------------------------------
;
;   subsystem_verb_object     lcd_write_string, keypad_read_row
;   subsystem_noun            dds_registers, keypad_column_shadow
;   local labels              a leading dot, scoped to the routine above them
;
; No label encodes its own address. The disassembly this rewrite replaces is
; full of names like l8089 and viaeedf, which is what a machine produces when
; nobody has worked out what something is. A name that says where a thing
; lives tells the reader nothing and goes stale the moment it moves.
; ===========================================================================

; --- Condition-code bits, by name ------------------------------------------
; Used with ORCC and ANDCC. Writing #$50 and trusting the reader to know it
; is I|F is how a mask ends up wrong and nobody notices.

CC_CARRY        equ     $01             ; C
CC_OVERFLOW     equ     $02             ; V
CC_ZERO         equ     $04             ; Z
CC_NEGATIVE     equ     $08             ; N
CC_IRQ_MASK     equ     $10             ; I - set to mask IRQ
CC_HALF_CARRY   equ     $20             ; H
CC_FIRQ_MASK    equ     $40             ; F - set to mask FIRQ
CC_ENTIRE       equ     $80             ; E - set when the whole state was
                                        ;     stacked by an interrupt
