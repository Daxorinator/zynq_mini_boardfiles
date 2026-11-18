/* Target glue: polling with timeout and a millisecond delay on the Cortex-A9 global timer (same method as the Vivado code). */
#include "ps7_open.h"
#define GT_COUNT_L   0xF8F00200u
#define GT_CONTROL   0xF8F00208u
#define APU_KHZ      666667u          /* CPU clock; the global timer runs at half of it */
#define POLL_LIMIT   100000000u
int ps7_poll_hw(u32 a, u32 m)
{
	u32 i;
	for (i = 0; i < POLL_LIMIT; i++)
		if (*(volatile u32 *)a & m) return 0;
	return PS7_TIMEOUT;
}
void ps7_delay_ms_hw(u32 ms)
{
	u32 ticks = APU_KHZ * ms / 2;
	*(volatile u32 *)GT_CONTROL = 0;
	*(volatile u32 *)GT_COUNT_L = 0;
	*(volatile u32 *)(GT_COUNT_L + 4) = 0;
	*(volatile u32 *)GT_CONTROL = BIT(0) | BIT(3);
	while (*(volatile u32 *)GT_COUNT_L < ticks) ;
	*(volatile u32 *)GT_CONTROL = 0;
}
