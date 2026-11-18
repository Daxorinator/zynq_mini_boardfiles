/* Bare-metal start-up, run from U-Boot (`go 0xFFFC0000`) with the MMU and caches switched off first (`dcache off`). */
    .section .text.start
    .global _start
    .arm
_start:
    cpsid   if
    @ turn off MMU, caches, branch prediction (U-Boot left them on), invalidate
    mrc     p15, 0, r0, c1, c0, 0
    bic     r0, r0, #(1 << 0)       @ M
    bic     r0, r0, #(1 << 2)       @ C
    bic     r0, r0, #(1 << 11)      @ Z
    bic     r0, r0, #(1 << 12)      @ I
    mcr     p15, 0, r0, c1, c0, 0
    isb
    mov     r0, #0
    mcr     p15, 0, r0, c7, c5, 0   @ invalidate I-cache
    mcr     p15, 0, r0, c8, c7, 0   @ invalidate TLB
    dsb
    isb
    ldr     sp, =0xFFFDFFF0
    ldr     r0, =__bss_start
    ldr     r1, =__bss_end
    mov     r2, #0
1:  cmp     r0, r1
    strlo   r2, [r0], #4
    blo     1b
    bl      main
2:  wfi
    b       2b
