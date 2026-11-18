/* Bare-metal DDR3 stability test for the ZYNQ MINI, using the hand-written PS7 init (no Vivado code).
 * Run from U-Boot out of high OCM: see ../../tests/run_ddr_test.sh. Prints progress on UART1 and leaves a result code in
 * SLCR REBOOT_STATUS[23:16] before soft-resetting the PS, so Linux can read the verdict after the reboot:
 *     0xA5 = all tests passed, 0xE1 = memory error, 0xE2 = ps7 init failed  (the boot ROM ORs 0x08 into the byte on reset).
 * Region tested: 0x00100000 .. 0x1FFFFFFF (511 MiB; the first MiB overlaps the OCM remap window). */
#include "ps7_open.h"
#include "ps7_open.c"
#include "ps7_hw.c"

#define UART_SR       0xE000102Cu
#define UART_FIFO     0xE0001030u
#define SLCR_PSS_RST  0xF8000200u
#define SLCR_REBOOT   0xF8000258u
#define SWDT_RESTART  0xF8005008u   /* kick the PS watchdog the loader armed: a hang still resets within ~77 s */
#define DDR_BASE      0x00100000u
#define DDR_END       0x20000000u

#define RD(a)    (*(volatile u32 *)(a))
#define WR(a, v) (*(volatile u32 *)(a) = (v))

static void putc_(char c) { while (RD(UART_SR) & BIT(4)) ; WR(UART_FIFO, (u32)c); }
static void puts_(const char *s) { while (*s) { if (*s == '\n') putc_('\r'); putc_(*s++); } }
static void puthex(u32 v) { int i; puts_("0x"); for (i = 28; i >= 0; i -= 4) putc_("0123456789abcdef"[(v >> i) & 15]); }
static void flush(void) { while (!(RD(UART_SR) & BIT(3))) ; }
static void set_result(u32 code) { WR(SLCR_UNLOCK, 0xDF0D); WR(SLCR_REBOOT, (RD(SLCR_REBOOT) & ~0x00FF0000u) | (code << 16)); }

static u32 errs;
static void bad(u32 a, u32 exp, u32 got)
{
	if (!errs) { puts_("  first mismatch at "); puthex(a); puts_(" expected "); puthex(exp); puts_(" got "); puthex(got); puts_("\n"); }
	errs++;
}
static u32 xorshift(u32 *s) { u32 x = *s; x ^= x << 13; x ^= x >> 17; x ^= x << 5; return *s = x; }

/* pattern kinds */
enum { ADDR, NADDR, RANDOM, NRANDOM, CHECK55, CHECKAA };
static u32 pat(int kind, u32 a, u32 *rng)
{
	switch (kind) {
	case ADDR:    return a;
	case NADDR:   return ~a;
	case RANDOM:  return xorshift(rng);
	case NRANDOM: return ~xorshift(rng);
	case CHECK55: return 0x55555555u;
	default:      return 0xAAAAAAAAu;
	}
}
static void run(const char *name, int kind, u32 seed)
{
	u32 a, rng = seed, before = errs;
	puts_(name); puts_(": write ");
	for (a = DDR_BASE; a < DDR_END; a += 4) { if (!(a & 0xFFFFF)) WR(SWDT_RESTART, 0x1999); WR(a, pat(kind, a, &rng)); }
	puts_("verify ");
	rng = seed;
	for (a = DDR_BASE; a < DDR_END; a += 4) { u32 e = pat(kind, a, &rng), g = RD(a); if (!(a & 0xFFFFF)) WR(SWDT_RESTART, 0x1999); if (g != e) bad(a, e, g); }
	puts_("errors "); puthex(errs - before); puts_("\n");
}

int main(void)
{
	u32 i;
	int r;
	puts_("\n\n=== zynq-mini DDR stability test (hand-written ps7 init) ===\n");
	flush();
	r = ps7_open_init();
	puts_("ps7_open_init returned "); puthex((u32)r); puts_("\n");
	if (r != PS7_OK) { set_result(0xE2); goto reset; }
	ps7_open_post_config();
#ifdef FULL_TEST   /* about 9 minutes; the default short test is the two random patterns (about 3 minutes) */
	run("address-in-address ", ADDR, 0);
	run("inverted address   ", NADDR, 0);
	run("checkerboard 55    ", CHECK55, 0);
	run("checkerboard AA    ", CHECKAA, 0);
#endif
	run("random seed 1      ", RANDOM, 0x12345679u);
	run("random seed 2 (inv)", NRANDOM, 0x9E3779B9u);
	puts_("data-bus walking ones/zeros: ");
	for (i = 0; i < 32; i++) {
		WR(0x10000000u, 1u << i); WR(0x10000004u, ~(1u << i));
		if (RD(0x10000000u) != (1u << i)) bad(0x10000000u, 1u << i, RD(0x10000000u));
		if (RD(0x10000004u) != ~(1u << i)) bad(0x10000004u, ~(1u << i), RD(0x10000004u));
	}
	puts_("done\n");
	if (errs) { puts_("RESULT: FAIL, total errors "); puthex(errs); puts_("\n"); set_result(0xE1); }
	else { puts_("RESULT: PASS (511 MiB of DDR3)\n"); set_result(0xA5); }
reset:
	flush();
	{ volatile int d; for (d = 0; d < 2000000; d++) ; }
	WR(SLCR_UNLOCK, 0xDF0D);
	WR(SLCR_PSS_RST, 1);
	for (;;) ;
}
