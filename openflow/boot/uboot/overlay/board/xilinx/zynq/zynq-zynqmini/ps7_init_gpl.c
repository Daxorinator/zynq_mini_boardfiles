/* ZYNQ MINI: the SPL's ps7_init()/ps7_post_config() are the hand-written open version (ps7_open.c, copied here by
 * boot/build.sh from boot/ps7/). The Vivado-generated tables are not used; they live in boot/ps7/vivado_ref/ only as the
 * reference the open version is verified against (boot/ps7/verify.sh). */
#include <linux/types.h>
#include "ps7_open.h"
#include "ps7_open.c"
#include "ps7_hw.c"

int ps7_init(void)        { return ps7_open_init(); }
int ps7_post_config(void) { return ps7_open_post_config(); }
