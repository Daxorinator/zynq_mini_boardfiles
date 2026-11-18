/* Host harness: runs ps7_open_init() / ps7_open_post_config() on the PC, printing every register operation. */
#include <stdio.h>
#include "ps7_open.h"
void t_write(u32 a, u32 v)          { printf("W %08x %08x\n", a, v); }
void t_maskw(u32 a, u32 m, u32 v)   { printf("M %08x %08x %08x\n", a, m, v & m); }
int  t_poll(u32 a, u32 m)           { printf("P %08x %08x\n", a, m); return 0; }
void t_delay_ms(u32 ms)             { printf("D %u\n", ms); }
int main(void)
{
	int r = ps7_open_init();
	printf("# init returned %d\n", r);
	r = ps7_open_post_config();
	printf("# post_config returned %d\n", r);
	return 0;
}
