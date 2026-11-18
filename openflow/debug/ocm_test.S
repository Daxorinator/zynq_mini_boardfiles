@ Tiny bare-metal test for the JTAG "load and run" demo: r0 = marker, r1 counts forever. Linked at 0xFFFF0000 (high OCM) by gdb_extras.sh.
	.global _start
	.text
_start:
	ldr	r0, =0x600DC0DE
	mov	r1, #0
1:	add	r1, r1, #1
	b	1b
	.ltorg
