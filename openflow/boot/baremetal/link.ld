ENTRY(_start)
MEMORY { OCM (rwx) : ORIGIN = 0xFFFC0000, LENGTH = 0x0001F000 }   /* high OCM (OCM_CFG=0x1f maps all four blocks high) */
SECTIONS {
  .text : { *(.text.start) *(.text*) *(.rodata*) } > OCM
  .data : { *(.data*) } > OCM
  .bss  : { __bss_start = .; *(.bss*) *(COMMON) __bss_end = .; } > OCM
}
