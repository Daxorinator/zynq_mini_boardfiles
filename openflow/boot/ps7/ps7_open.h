/* Open (no Vivado) PS7 initialisation for the ZYNQ MINI (XC7Z010, 33.333 MHz PS_CLK, 512 MB DDR3 x16).
 * Register access goes through four macros so the same code runs on the target and, with -DPS7_HOST_TRACE,
 * on a PC where every access is recorded and compared with the Vivado-generated init (see verify.sh). */
#ifndef PS7_OPEN_H
#define PS7_OPEN_H
#ifndef __UBOOT__
typedef unsigned int u32;
#endif

#ifdef PS7_HOST_TRACE
void t_write(u32 a, u32 v);
void t_maskw(u32 a, u32 m, u32 v);
int  t_poll(u32 a, u32 m);
void t_delay_ms(u32 ms);
#define REG_WRITE(a, v)       t_write((a), (v))
#define REG_MASKW(a, m, v)    t_maskw((a), (m), (v))
#define REG_POLL(a, m)        t_poll((a), (m))
#define DELAY_MS(ms)          t_delay_ms(ms)
#else
static inline void REG_WRITE(u32 a, u32 v) { *(volatile u32 *)a = v; }
static inline void REG_MASKW(u32 a, u32 m, u32 v) { volatile u32 *p = (volatile u32 *)a; *p = (v & m) | (*p & ~m); }
int ps7_poll_hw(u32 a, u32 m);
void ps7_delay_ms_hw(u32 ms);
#define REG_POLL(a, m)        ps7_poll_hw((a), (m))
#define DELAY_MS(ms)          ps7_delay_ms_hw(ms)
#endif

/* bit-field helper: value v placed in bits [hi:lo] */
#define FLD(hi, lo, v)  ((((u32)(v)) << (lo)) & ((0xFFFFFFFFu >> (31 - (hi))) & (0xFFFFFFFFu << (lo))))
#ifndef BIT
#define BIT(n)          (1u << (n))
#endif

#define PS7_OK       0
#define PS7_TIMEOUT  2

int ps7_open_init(void);         /* MIO, PLLs, clocks, DDR, peripherals (replaces ps7_init()) */
int ps7_open_post_config(void);  /* level shifters, FPGA resets (replaces ps7_post_config()) */
#endif
