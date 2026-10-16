; ---------------------------------------------------------------------------
; interrupts.inc - masking the 6809's two maskable interrupts
;
; The MC6809 carries its interrupt masks in the condition-code register:
; bit 4 (I) masks IRQ, bit 6 (F) masks FIRQ. Setting either takes one
; instruction and three cycles.
;
; THE ROM DOES NOT DO IT IN ONE INSTRUCTION. It calls a subroutine:
;
;       $DD06  orcc  #$10      ; disable_irq  - the whole routine
;       $DD08  rts
;       $DD09  orcc  #$40      ; firq_disable - the whole routine
;       $DD0B  rts
;
; So masking an interrupt costs an LBSR (9 cycles), the ORCC (3) and an RTS
; (5): seventeen cycles and five bytes at the call site, to do three cycles
; and two bytes of work. That is not a defect in HP's logic - it is what a C
; compiler does with a function that happens to be one instruction long, and
; there were 43 such calls.
;
; These macros put the instruction where it belongs: at the point of use.
; A macro, not a subroutine, because there is nothing to call.
;
; WHY MASK AT ALL, which matters more than the cycles saved: the interrupt
; handlers write the same flag words the foreground does. The foreground
; reads a word, changes a bit and writes it back, and an interrupt landing
; between the read and the write has its own change overwritten and lost -
; and what is lost is a key-press or an interrupt latch. Every such sequence
; in this rewrite is bracketed by DISABLE_INTERRUPTS / RESTORE_INTERRUPTS.
;
; RESTORE, not "enable". PULS CC puts back exactly what was there, so a
; bracketed sequence inside another one does not switch interrupts on early.
; ---------------------------------------------------------------------------

; The bit names come from conventions.inc, which defines every condition-code
; bit once. Two names for one bit is how a mask ends up wrong in one of them.
BOTH_MASKS      equ     CC_IRQ_MASK|CC_FIRQ_MASK

; Mask both interrupts, remembering the caller's condition codes on the
; stack. 21 to 25 MPU cycles pass before RESTORE_INTERRUPTS, which is the
; longest any interrupt is held off anywhere in this ROM.
DISABLE_INTERRUPTS macro
                pshs    cc              ; remember what the caller had
                orcc    #BOTH_MASKS     ; I and F set: nothing gets in
                endm

; Put back exactly what the caller had, whatever that was.
RESTORE_INTERRUPTS macro
                puls    cc
                endm

; Mask IRQ alone, without saving. For the power-on path, where there is no
; caller state worth preserving and interrupts stay off until the hardware
; has been programmed.
MASK_IRQ        macro
                orcc    #CC_IRQ_MASK
                endm

; Mask FIRQ alone, same reasoning.
MASK_FIRQ       macro
                orcc    #CC_FIRQ_MASK
                endm

; Allow both. USED NOWHERE, and that is deliberate rather than an oversight:
; this rewrite masks both interrupts at power-on and leaves them masked,
; because the FIRQ source cannot be acknowledged by anything establishable
; from the stock firmware and an interrupt that cannot be acknowledged locks
; the instrument up. The keypad and the tick are polled instead.
;
; It said "used once, at the end of the power-on sequence". Grepping the tree
; for ENABLE_INTERRUPTS returns this definition and nothing else. The macro is
; kept because the day the acknowledgement IS established, the thing that
; enables them should already be written and named; a reader deserves to know
; it is not called today.
ENABLE_INTERRUPTS macro
                andcc   #~BOTH_MASKS    ; clear I and F
                endm
