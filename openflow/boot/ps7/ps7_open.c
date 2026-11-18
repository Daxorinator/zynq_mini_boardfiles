/* Open PS7 init for the ZYNQ MINI. Hand-written; replaces the Vivado-generated ps7_init_gpl.c.
 * Supports Zynq-7000 silicon rev 3.x only (what is on this board). Sequence and values were checked equal to the
 * Vivado output by trace comparison (verify.sh). PLL/clock settings are computed from the board parameters below.
 * Board-tuned DDR PHY values (slave ratios, DCI/IOB drive) are carried over from the Vivado output, see ps7_ddr_table.inc. */
#include "ps7_open.h"

/* ---------------- board parameters ---------------- */
#define PS_CLK_KHZ        33333u            /* 33.333 MHz crystal */
#define ARM_PLL_TARGET_KHZ 1333333u         /* CPU 666.67 MHz = /2 */
#define DDR_PLL_TARGET_KHZ 1066666u         /* DDR3-1066: 533.33 MHz DDR clock = /2 */
#define IO_PLL_TARGET_KHZ  1000000u
#define FDIV(t)           (((t) + PS_CLK_KHZ / 2) / PS_CLK_KHZ)

#define SLCR_BASE   0xF8000000u
#define DDRC_BASE   0xF8006000u
/* SLCR registers (names as in U-Boot's struct slcr_regs / Zynq TRM) */
#define SLCR_LOCK        (SLCR_BASE + 0x004)
#define SLCR_UNLOCK      (SLCR_BASE + 0x008)
#define ARM_PLL_CTRL     (SLCR_BASE + 0x100)
#define DDR_PLL_CTRL     (SLCR_BASE + 0x104)
#define IO_PLL_CTRL      (SLCR_BASE + 0x108)
#define PLL_STATUS       (SLCR_BASE + 0x10C)
#define ARM_PLL_CFG      (SLCR_BASE + 0x110)
#define DDR_PLL_CFG      (SLCR_BASE + 0x114)
#define IO_PLL_CFG       (SLCR_BASE + 0x118)
#define ARM_CLK_CTRL     (SLCR_BASE + 0x120)
#define DDR_CLK_CTRL     (SLCR_BASE + 0x124)
#define DCI_CLK_CTRL     (SLCR_BASE + 0x128)
#define APER_CLK_CTRL    (SLCR_BASE + 0x12C)
#define GEM0_RCLK_CTRL   (SLCR_BASE + 0x138)
#define GEM0_CLK_CTRL    (SLCR_BASE + 0x140)
#define LQSPI_CLK_CTRL   (SLCR_BASE + 0x14C)
#define SDIO_CLK_CTRL    (SLCR_BASE + 0x150)
#define UART_CLK_CTRL    (SLCR_BASE + 0x154)
#define PCAP_CLK_CTRL    (SLCR_BASE + 0x168)
#define FPGA0_CLK_CTRL   (SLCR_BASE + 0x170)
#define CLK_621_TRUE     (SLCR_BASE + 0x1C4)
#define FPGA_RST_CTRL    (SLCR_BASE + 0x240)
#define MIO_PIN(n)       (SLCR_BASE + 0x700 + 4 * (n))
#define SD0_WPCD_SEL     (SLCR_BASE + 0x830)
#define SD1_WPCD_SEL     (SLCR_BASE + 0x834)
#define LVL_SHFTR_EN     (SLCR_BASE + 0x900)
/* DDR I/O block (DDRIOB) and DCI */
#define DDRIOB_ADDR0     (SLCR_BASE + 0xB40)
#define DDRIOB_ADDR1     (SLCR_BASE + 0xB44)
#define DDRIOB_DATA0     (SLCR_BASE + 0xB48)
#define DDRIOB_DATA1     (SLCR_BASE + 0xB4C)
#define DDRIOB_DIFF0     (SLCR_BASE + 0xB50)
#define DDRIOB_DIFF1     (SLCR_BASE + 0xB54)
#define DDRIOB_CLOCK     (SLCR_BASE + 0xB58)
#define DDRIOB_DRIVE_SLEW_ADDR  (SLCR_BASE + 0xB5C)
#define DDRIOB_DRIVE_SLEW_DATA  (SLCR_BASE + 0xB60)
#define DDRIOB_DRIVE_SLEW_DIFF  (SLCR_BASE + 0xB64)
#define DDRIOB_DRIVE_SLEW_CLOCK (SLCR_BASE + 0xB68)
#define DDRIOB_DDR_CTRL  (SLCR_BASE + 0xB6C)
#define DDRIOB_DCI_CTRL  (SLCR_BASE + 0xB70)
#define DDRIOB_DCI_STATUS (SLCR_BASE + 0xB74)

#define SLCR_UNLOCK_KEY  0xDF0Du
#define SLCR_LOCK_KEY    0x767Bu
static void slcr_unlock(void) { REG_WRITE(SLCR_UNLOCK, SLCR_UNLOCK_KEY); }
static void slcr_lock(void)   { REG_WRITE(SLCR_LOCK, SLCR_LOCK_KEY); }

/* ---------------- DDR I/O pads ---------------- */
/* DDRIOB_ADDR/DATA/DIFF/CLOCK bit fields */
#define IOB(inp_type, term_en, dci_type, ibuf_dis, term_dis, out_en, pullup) \
	(FLD(2, 1, inp_type) | FLD(4, 4, term_en) | FLD(6, 5, dci_type) | FLD(7, 7, ibuf_dis) | FLD(8, 8, term_dis) | \
	 FLD(10, 9, out_en) | FLD(11, 11, pullup))
#define IOB_DRV(p, n, slew_p, slew_n)  (FLD(6, 0, p) | FLD(13, 7, n) | FLD(18, 14, slew_p) | FLD(23, 19, slew_n))

static void ddriob_init(void)
{
	/* address/control and clock pads: outputs only; data and differential strobes use DCI-terminated SSTL inputs */
	REG_MASKW(DDRIOB_ADDR0, 0xFFF, IOB(0, 0, 0, 0, 0, 3, 0));
	REG_MASKW(DDRIOB_ADDR1, 0xFFF, IOB(0, 0, 0, 0, 0, 3, 0));
	REG_MASKW(DDRIOB_DATA0, 0xFFF, IOB(1, 1, 3, 0, 0, 3, 0));
	REG_MASKW(DDRIOB_DATA1, 0xFFF, IOB(0, 0, 0, 0, 0, 0, 1));
	REG_MASKW(DDRIOB_DIFF0, 0xFFF, IOB(2, 1, 3, 0, 0, 3, 0));
	REG_MASKW(DDRIOB_DIFF1, 0xFFF, IOB(0, 0, 0, 0, 0, 0, 1));
	REG_MASKW(DDRIOB_CLOCK, 0xFFF, IOB(0, 0, 0, 0, 0, 3, 0));
	REG_MASKW(DDRIOB_DRIVE_SLEW_ADDR,  0xFFFFFFFF, IOB_DRV(0x1C, 0xC, 3, 3));
	REG_MASKW(DDRIOB_DRIVE_SLEW_DATA,  0xFFFFFFFF, IOB_DRV(0x1C, 0xC, 6, 0x1F));
	REG_MASKW(DDRIOB_DRIVE_SLEW_DIFF,  0xFFFFFFFF, IOB_DRV(0x1C, 0xC, 6, 0x1F));
	REG_MASKW(DDRIOB_DRIVE_SLEW_CLOCK, 0xFFFFFFFF, IOB_DRV(0x1C, 0xC, 6, 0x1F));
	/* external VREF input (board provides the half-VDDQ reference), REFIO enabled */
	REG_MASKW(DDRIOB_DDR_CTRL, 0x7FFF, FLD(6, 5, 1) | FLD(9, 9, 1));
	/* digitally controlled impedance (DCI) calibration block: pulse reset, then enable with the Xilinx-specified
	 * reference option settings */
	REG_MASKW(DDRIOB_DCI_CTRL, 0x1, 1);
	REG_MASKW(DDRIOB_DCI_CTRL, 0x21, BIT(5));
	REG_MASKW(DDRIOB_DCI_CTRL, 0x7FEFFFF, BIT(0) | BIT(1) | BIT(5) | FLD(13, 11, 1));
}

/* ---------------- MIO pins ---------------- */
/* MIO_PIN_n: tri-state enable, mux level 0..3 selects, speed, I/O standard, pull-up, receiver disable */
#define L3(n) FLD(7, 5, n)
#define MIO_VAL(tri, l0, l1, l2, l3, speed, iostd, pullup, disrcvr) \
	(FLD(0, 0, tri) | FLD(1, 1, l0) | FLD(2, 2, l1) | FLD(4, 3, l2) | FLD(7, 5, l3) | FLD(8, 8, speed) | \
	 FLD(11, 9, iostd) | FLD(12, 12, pullup) | FLD(13, 13, disrcvr))
#define IO_LVCMOS18 1
#define IO_LVCMOS33 3

static void mio_init(void)
{
	int i;
	/* Bank 500 (MIO 0..15) is at 3.3 V, bank 501 (MIO 16..53) at 1.8 V. */
	REG_MASKW(MIO_PIN(0), 0x3FFF, MIO_VAL(0, 0, 0, 0, 0, 0, IO_LVCMOS33, 1, 0));   /* GPIO: user key */
	REG_MASKW(MIO_PIN(1), 0x3FFF, MIO_VAL(0, 1, 0, 0, 0, 0, IO_LVCMOS33, 1, 0));   /* QSPI CS */
	for (i = 2; i <= 6; i++)                                                        /* QSPI IO0..3, SCK */
		REG_MASKW(MIO_PIN(i), 0x3FFF, MIO_VAL(0, 1, 0, 0, 0, 0, IO_LVCMOS33, 0, 0));
	REG_MASKW(MIO_PIN(7), 0x3FFF, MIO_VAL(0, 0, 0, 0, 0, 0, IO_LVCMOS33, 0, 0));    /* GPIO */
	REG_MASKW(MIO_PIN(8), 0x3FFF, MIO_VAL(0, 0, 0, 0, 0, 0, IO_LVCMOS33, 0, 0));    /* GPIO */
	REG_MASKW(MIO_PIN(9), 0x3FFF, MIO_VAL(0, 0, 0, 0, 0, 0, IO_LVCMOS33, 1, 0));    /* GPIO: PS LED */
	for (i = 10; i <= 15; i++)                                                      /* L3 function 4 (see TRM table 2-4) */
		REG_MASKW(MIO_PIN(i), 0x3FFF, MIO_VAL(0, 0, 0, 0, 4, 0, IO_LVCMOS33, 1, 0));
	for (i = 16; i <= 21; i++)                                                      /* Ethernet 0 (RGMII) TX */
		REG_MASKW(MIO_PIN(i), 0x3FFF, MIO_VAL(0, 1, 0, 0, 0, 0, IO_LVCMOS18, 1, 0));
	for (i = 22; i <= 27; i++)                                                      /* Ethernet 0 RX (inputs: tri-state) */
		REG_MASKW(MIO_PIN(i), 0x3FFF, MIO_VAL(1, 1, 0, 0, 0, 0, IO_LVCMOS18, 1, 0));
	/* USB 0 (ULPI): 28 DATA4, 29 DIR, 30 STP, 31 NXT, 32 DATA0 ... ; inputs are tri-stated */
	REG_MASKW(MIO_PIN(28), 0x3FFF, MIO_VAL(0, 0, 1, 0, 0, 0, IO_LVCMOS18, 1, 0));
	REG_MASKW(MIO_PIN(29), 0x3FFF, MIO_VAL(1, 0, 1, 0, 0, 0, IO_LVCMOS18, 1, 0));
	REG_MASKW(MIO_PIN(30), 0x3FFF, MIO_VAL(0, 0, 1, 0, 0, 0, IO_LVCMOS18, 1, 0));
	REG_MASKW(MIO_PIN(31), 0x3FFF, MIO_VAL(1, 0, 1, 0, 0, 0, IO_LVCMOS18, 1, 0));
	REG_MASKW(MIO_PIN(32), 0x3FFF, MIO_VAL(0, 0, 1, 0, 0, 0, IO_LVCMOS18, 1, 0));
	REG_MASKW(MIO_PIN(33), 0x3FFF, MIO_VAL(0, 0, 1, 0, 0, 0, IO_LVCMOS18, 1, 0));
	REG_MASKW(MIO_PIN(34), 0x3FFF, MIO_VAL(0, 0, 1, 0, 0, 0, IO_LVCMOS18, 1, 0));
	REG_MASKW(MIO_PIN(35), 0x3FFF, MIO_VAL(0, 0, 1, 0, 0, 0, IO_LVCMOS18, 1, 0));
	REG_MASKW(MIO_PIN(36), 0x3FFF, MIO_VAL(1, 0, 1, 0, 0, 0, IO_LVCMOS18, 1, 0));
	REG_MASKW(MIO_PIN(37), 0x3FFF, MIO_VAL(0, 0, 1, 0, 0, 0, IO_LVCMOS18, 1, 0));
	REG_MASKW(MIO_PIN(38), 0x3FFF, MIO_VAL(0, 0, 1, 0, 0, 0, IO_LVCMOS18, 1, 0));
	REG_MASKW(MIO_PIN(39), 0x3FFF, MIO_VAL(0, 0, 1, 0, 0, 0, IO_LVCMOS18, 1, 0));
	for (i = 40; i <= 45; i++)                                                      /* SD 0: CLK, CMD, DAT0..3 */
		REG_MASKW(MIO_PIN(i), 0x3FFF, MIO_VAL(0, 0, 0, 0, 4, 0, IO_LVCMOS18, 1, 0));
	REG_MASKW(MIO_PIN(46), 0x3FFF, MIO_VAL(0, 0, 0, 0, 0, 0, IO_LVCMOS18, 1, 0));   /* GPIO: USB PHY reset */
	REG_MASKW(MIO_PIN(47), 0x3FFF, MIO_VAL(0, 0, 0, 0, 0, 0, IO_LVCMOS18, 1, 0));   /* GPIO */
	REG_MASKW(MIO_PIN(48), 0x3FFF, MIO_VAL(0, 0, 0, 0, 7, 0, IO_LVCMOS18, 1, 0));   /* UART 1 TX */
	REG_MASKW(MIO_PIN(49), 0x3FFF, MIO_VAL(1, 0, 0, 0, 7, 0, IO_LVCMOS18, 1, 0));   /* UART 1 RX */
	REG_MASKW(MIO_PIN(50), 0x3FFF, MIO_VAL(0, 0, 0, 0, 0, 0, IO_LVCMOS18, 1, 0));   /* GPIO */
	REG_MASKW(MIO_PIN(51), 0x3FFF, MIO_VAL(0, 0, 0, 0, 0, 0, IO_LVCMOS18, 1, 0));   /* GPIO */
	REG_MASKW(MIO_PIN(52), 0x3FFF, MIO_VAL(0, 0, 0, 0, 4, 0, IO_LVCMOS18, 1, 0));   /* Ethernet MDC */
	REG_MASKW(MIO_PIN(53), 0x3FFF, MIO_VAL(0, 0, 0, 0, 4, 0, IO_LVCMOS18, 1, 0));   /* Ethernet MDIO */
	/* SD card detect / write protect routed from MIO 56..58 side (SD0 WP=MIO55, CD=MIO56; SD1 WP=57, CD=58) */
	REG_MASKW(SD0_WPCD_SEL, 0x3F003F, FLD(5, 0, 55) | FLD(21, 16, 56));
	REG_MASKW(SD1_WPCD_SEL, 0x3F003F, FLD(5, 0, 57) | FLD(21, 16, 58));
}

static int mio_stage(void)
{
	slcr_unlock();
	ddriob_init();
	mio_init();
	slcr_lock();
	return PS7_OK;
}

/* ---------------- PLLs ---------------- */
struct pll { u32 ctrl, cfg, lock_bit; u32 target_khz; u32 res, cp, lock_cnt; };
/* loop-filter settings (res, cp) and lock count come from the TRM's PLL table, indexed by the feedback divider */
static int pll_filter(u32 fdiv, u32 *res, u32 *cp, u32 *lock)
{
	switch (fdiv) {
	case 30: *res = 0xC; *cp = 2; *lock = 0x145; return 0;
	case 32: *res = 0x2; *cp = 2; *lock = 0x12C; return 0;
	case 40: *res = 0x2; *cp = 2; *lock = 0xFA;  return 0;
	default: return -1;   /* add the TRM row before using another divider */
	}
}
static int pll_init(u32 ctrl, u32 cfg, u32 lock_bit, u32 target_khz)
{
	u32 fdiv = FDIV(target_khz), res, cp, lock;
	if (pll_filter(fdiv, &res, &cp, &lock)) return PS7_TIMEOUT + 100;
	REG_MASKW(cfg, 0x3FFFF0, FLD(7, 4, res) | FLD(11, 8, cp) | FLD(21, 12, lock));
	REG_MASKW(ctrl, 0x7F000, FLD(18, 12, fdiv));      /* feedback divider */
	REG_MASKW(ctrl, 0x10, BIT(4));                     /* force bypass while it re-locks */
	REG_MASKW(ctrl, 0x1, BIT(0));                      /* reset */
	REG_MASKW(ctrl, 0x1, 0);
	REG_POLL(PLL_STATUS, lock_bit);
	REG_MASKW(ctrl, 0x10, 0);                          /* un-bypass */
	return PS7_OK;
}

static int pll_stage(void)
{
	int r;
	slcr_unlock();
	r = pll_init(ARM_PLL_CTRL, ARM_PLL_CFG, BIT(0), ARM_PLL_TARGET_KHZ); if (r) return r;
	/* CPU clock = ARM PLL / 2 = 666.7 MHz; all CPU clock domains (6x4x, 3x2x, 2x, 1x, peri) enabled */
	REG_MASKW(ARM_CLK_CTRL, 0x1F003F30, FLD(5, 4, 0) | FLD(13, 8, 2) | FLD(28, 24, 0x1F));
	r = pll_init(DDR_PLL_CTRL, DDR_PLL_CFG, BIT(1), DDR_PLL_TARGET_KHZ); if (r) return r;
	/* DDR 3x clock (DRAM clock) = DDR PLL / 2 = 533.3 MHz, 2x clock = /3 = 355.6 MHz */
	REG_MASKW(DDR_CLK_CTRL, 0xFFF00003, BIT(0) | BIT(1) | FLD(25, 20, 2) | FLD(31, 26, 3));
	r = pll_init(IO_PLL_CTRL, IO_PLL_CFG, BIT(2), IO_PLL_TARGET_KHZ); if (r) return r;
	slcr_lock();
	return PS7_OK;
}

/* ---------------- peripheral clocks (all from the IO PLL, 1000 MHz) ---------------- */
#define IOPLL_KHZ IO_PLL_TARGET_KHZ
#define DIV(target_khz) (IOPLL_KHZ / (target_khz))
static int clock_stage(void)
{
	slcr_unlock();
	REG_MASKW(DCI_CLK_CTRL, 0x3F03F01, BIT(0) | FLD(13, 8, 15) | FLD(25, 20, 7));            /* DCI calibration clock ~9.5 MHz */
	REG_MASKW(GEM0_RCLK_CTRL, 0x11, BIT(0) | FLD(4, 4, 0));                                   /* GEM0 RX clock from MIO */
	REG_MASKW(GEM0_CLK_CTRL, 0x3F03F71, BIT(0) | FLD(6, 4, 0) | FLD(13, 8, DIV(125000)) | FLD(25, 20, 1)); /* 125 MHz */
	REG_MASKW(LQSPI_CLK_CTRL, 0x3F31, BIT(0) | FLD(5, 4, 0) | FLD(13, 8, DIV(200000)));        /* QSPI 200 MHz */
	REG_MASKW(SDIO_CLK_CTRL, 0x3F33, BIT(0) | BIT(1) | FLD(5, 4, 0) | FLD(13, 8, DIV(100000)));/* SDIO 100 MHz */
	REG_MASKW(UART_CLK_CTRL, 0x3F33, BIT(1) | FLD(5, 4, 0) | FLD(13, 8, DIV(100000)));         /* UART 100 MHz, UART1 only */
	REG_MASKW(PCAP_CLK_CTRL, 0x3F31, BIT(0) | FLD(5, 4, 0) | FLD(13, 8, DIV(200000)));         /* PCAP 200 MHz */
	REG_MASKW(FPGA0_CLK_CTRL, 0x3F03F30, FLD(5, 4, 0) | FLD(13, 8, 5) | FLD(25, 20, 4));       /* FCLK0 = 1000/(5*4) = 50 MHz */
	REG_MASKW(CLK_621_TRUE, 0x1, 1);                                                          /* CPU clock ratio 6:2:1 */
	/* clocks enabled to the AMBA peripherals in use: DMA, USB0/1, GEM0, SDIO0/1, I2C0/1, UART1, GPIO, QSPI, SMC */
	REG_MASKW(APER_CLK_CTRL, 0x1FFCCCD,
		BIT(0) | BIT(2) | BIT(3) | BIT(6) | BIT(10) | BIT(11) | BIT(18) | BIT(19) | BIT(21) | BIT(22) | BIT(23) | BIT(24));
	slcr_lock();
	return PS7_OK;
}

/* ---------------- DDR3 controller ---------------- */
static int ddr_stage(void)
{
#include "ps7_ddr_table.inc"
	return PS7_OK;
}

/* ---------------- peripherals after DDR is up ---------------- */
#define UART1_BASE 0xE0001000u
#define GPIO_BASE  0xE000A000u
static int peripherals_stage(void)
{
	slcr_unlock();
	/* DDR input buffers / termination: now that DDR is running, let the receivers follow the controller */
	REG_MASKW(DDRIOB_DATA0, 0x180, FLD(7, 7, 1) | FLD(8, 8, 1));
	REG_MASKW(DDRIOB_DATA1, 0x180, 0);
	REG_MASKW(DDRIOB_DIFF0, 0x180, FLD(7, 7, 1) | FLD(8, 8, 1));
	REG_MASKW(DDRIOB_DIFF1, 0x180, 0);
	slcr_lock();
	/* UART1: 115200 8N1 from the 100 MHz UART clock: baud = 100e6 / (CD * (BDIV+1)) = 100e6/(124*7) */
	REG_MASKW(UART1_BASE + 0x34, 0xFF, 6);                      /* BAUDDIV */
	REG_MASKW(UART1_BASE + 0x18, 0xFFFF, 0x7C);                 /* BAUDGEN */
	REG_MASKW(UART1_BASE + 0x00, 0x1FF, BIT(0) | BIT(1) | BIT(2) | BIT(4));   /* reset FIFOs, enable TX and RX */
	REG_MASKW(UART1_BASE + 0x04, 0x3FF, FLD(5, 3, 4));          /* no parity, 1 stop bit, 8 data bits */
	REG_MASKW(0xE000D000, 0x80000, BIT(19));                    /* QSPI: HOLDB driven high (quad mode) */
	REG_MASKW(0xF8007000, 0x20000000, 0);                       /* PCAP: PL power-on-reset counter select */
	/* USB PHY reset on MIO46 (GPIO bank 1, bit 14): drive low 1 ms, then release */
	REG_MASKW(GPIO_BASE + 0x244, 0x3FFFFF, BIT(14));            /* direction: output */
	REG_MASKW(GPIO_BASE + 0x008, 0xFFFFFFFF, 0xBFFF0000u | BIT(14));  /* MASK_DATA_1_LSW: set MIO46 high */
	REG_MASKW(GPIO_BASE + 0x248, 0x3FFFFF, BIT(14));            /* output enable */
	REG_MASKW(GPIO_BASE + 0x008, 0xFFFFFFFF, 0xBFFF0000u);      /* low */
	DELAY_MS(1);
	REG_MASKW(GPIO_BASE + 0x008, 0xFFFFFFFF, 0xBFFF0000u | BIT(14));  /* high */
	return PS7_OK;
}

int ps7_open_init(void)
{
	int r;
	if ((r = mio_stage())) return r;
	if ((r = pll_stage())) return r;
	if ((r = clock_stage())) return r;
	if ((r = ddr_stage())) return r;
	return peripherals_stage();
}

int ps7_open_post_config(void)
{
	slcr_unlock();
	REG_MASKW(LVL_SHFTR_EN, 0xF, 0xF);        /* PS/PL level shifters on */
	REG_MASKW(FPGA_RST_CTRL, 0xFFFFFFFF, 0);  /* release the FPGA fabric resets */
	slcr_lock();
	return PS7_OK;
}
