#!/usr/bin/env python3
"""Assemble a bootable ZYNQ MINI SD image with the open boot chain and kernel, without root and without PetaLinux/Vivado.
usage: mkimage.py --base-image ZynqMini-3.1.2.img --boot-bin BOOT.BIN --u-boot-img u-boot.img --kernel-dir build/out --out open.img
The root filesystem (partition 2) is taken from the base image (the existing PYNQ/Ubuntu userland, unchanged except that the new kernel's
modules and a modules-load entry for the zmbuf driver are added); partition 1 is a new FAT32 volume holding BOOT.BIN, U-BOOT.IMG, a boot
script, the kernel and the device tree. Needs: mkfs.fat, debugfs (e2fsprogs; set DEBUGFS=... to a debugfs at least as new as the mkfs.ext4 that made the filesystem, e.g. Buildroot's host/sbin/debugfs for its image), mkimage (u-boot-tools), sfdisk. Pure-Python FAT writer below."""
import argparse, os, shutil, struct, subprocess, sys, tempfile

def run(*a, **k): return subprocess.run(a, check=True, **k)

# ---------------------------------------------------------------------------- minimal FAT32 writer (root directory, 8.3 names)
class Fat32:
    def __init__(self, path):
        self.f = open(path, "r+b"); b = self.f.read(512)
        self.bps, self.spc, self.rsv, self.nfat = struct.unpack("<HBHB", b[11:17])
        self.spf = struct.unpack("<I", b[36:40])[0]; self.root = struct.unpack("<I", b[44:48])[0]
        self.data0 = self.rsv + self.nfat * self.spf
        total = struct.unpack("<I", b[32:36])[0] or struct.unpack("<H", b[19:21])[0]
        self.nclus = (total - self.data0) // self.spc
        self.cs = self.bps * self.spc; self.next = self.root + 1
        self.f.seek(self.rsv * self.bps); self.fat = bytearray(self.f.read(self.spf * self.bps))
        self.dirents = []
    def _clus_off(self, c): return (self.data0 + (c - 2) * self.spc) * self.bps
    def put(self, name83, data):
        n = max(1, -(-len(data) // self.cs)); first = self.next
        if first + n >= self.nclus + 2: raise RuntimeError("FAT volume full")
        for i in range(n):
            c = first + i; struct.pack_into("<I", self.fat, 4 * c, (c + 1) if i < n - 1 else 0x0FFFFFFF)
        self.f.seek(self._clus_off(first)); self.f.write(data + b"\0" * (n * self.cs - len(data))); self.next += n
        base, _, ext = name83.upper().partition(".")
        t = (13 << 11) | (0 << 5) | 0; d = ((2026 - 1980) << 9) | (11 << 5) | 18
        ent = (base.ljust(8) + ext.ljust(3)).encode() + struct.pack("<BBBHHHHHHHI", 0x20, 0, 0, t, d, d, first >> 16, t, d, first & 0xFFFF, len(data))
        self.dirents.append(ent)
    def close(self):
        self.f.seek(self._clus_off(self.root)); cur = bytearray(self.f.read(self.cs))      # keep the volume label entry
        pos = next(i for i in range(0, self.cs, 32) if cur[i] == 0)
        new = b"".join(self.dirents)
        if pos + len(new) > self.cs: raise RuntimeError("too many files for one root directory cluster")
        cur[pos:pos + len(new)] = new
        self.f.seek(self._clus_off(self.root)); self.f.write(cur)
        for i in range(self.nfat):
            self.f.seek((self.rsv + i * self.spf) * self.bps); self.f.write(self.fat)
        self.f.close()

def make_fat(path, size, files):
    with open(path, "wb") as f: f.truncate(size)
    run("mkfs.fat", "-F", "32", "-n", "ZMBOOT", path, stdout=subprocess.DEVNULL)
    fat = Fat32(path)
    for name, data in files: fat.put(name, data)
    fat.close()

# ---------------------------------------------------------------------------- ext4 population through debugfs (no mount)
def debugfs_script(stage_root, dest_root, extra_files):
    cmds = ["mkdir %s" % dest_root] if False else []
    for dirpath, dirs, files in os.walk(stage_root):
        rel = os.path.relpath(dirpath, stage_root)
        target = dest_root if rel == "." else dest_root + "/" + rel
        cmds.append("mkdir %s" % target)
        for fn in sorted(files):
            p = os.path.join(dirpath, fn)
            if os.path.islink(p): cmds.append("symlink %s/%s %s" % (target, fn, os.readlink(p)))
            else: cmds.append("write %s %s/%s" % (p, target, fn))
    for src, dst in extra_files: cmds.append("rm %s" % dst); cmds.append("write %s %s" % (src, dst))
    return "\n".join(cmds) + "\n"

def main():
    ap = argparse.ArgumentParser()
    for a in ("boot-bin", "u-boot-img", "kernel-dir", "out"): ap.add_argument("--" + a, required=True)
    ap.add_argument("--base-image", help="copy the root filesystem (partition 2) from this existing image (e.g. the PYNQ image)")
    ap.add_argument("--rootfs-image", help="or: an ext4 file (e.g. the Buildroot image from ../buildroot) to use as the root filesystem")
    o = ap.parse_args()
    out = o.out
    with tempfile.TemporaryDirectory() as tmp:
        if bool(o.base_image) == bool(o.rootfs_image): sys.exit("give exactly one of --base-image and --rootfs-image")
        if o.base_image:
            # partition table of the base image
            sf = subprocess.run(["sfdisk", "-d", o.base_image], capture_output=True, text=True, check=True).stdout
            parts = {}
            for line in sf.splitlines():
                if line.startswith(o.base_image + "1") or line.startswith(o.base_image + "2"):
                    num = line[len(o.base_image)]; kv = dict(x.strip().split("=", 1) for x in line.split(":", 1)[1].split(",") if "=" in x)
                    parts[num] = (int(kv["start"]) * 512, int(kv["size"]) * 512)
            if len(parts) != 2: sys.exit("base image must have 2 partitions (FAT boot + ext4 root)")
            print("copying base image (sparse) ..."); run("cp", "--sparse=always", o.base_image, out)
        else:
            rsz = os.path.getsize(o.rootfs_image); p1s, p1n = 8 * 512 * 32, 266240 * 512            # boot partition: 130 MiB at 128 KiB... (sector 8192)
            p1s = 8192 * 512; p2s = p1s + p1n; p2n = (rsz + 511) // 512 * 512
            parts = {"1": (p1s, p1n), "2": (p2s, p2n)}
            with open(out, "wb") as f: f.truncate(p2s + p2n)
            run("sfdisk", "-q", out, input=("label: dos\n%d,%d,c,*\n%d,%d,83\n" % (p1s // 512, p1n // 512, p2s // 512, p2n // 512)).encode(), stdout=subprocess.DEVNULL)
            with open(out, "r+b") as img, open(o.rootfs_image, "rb") as f: img.seek(p2s); shutil.copyfileobj(f, img, 1 << 20)
        # boot script and FAT volume
        script = os.path.join(tmp, "boot.cmd")
        open(script, "w").write("""# ZYNQ MINI open boot: kernel and device tree from this FAT partition, root filesystem on partition 2
setenv bootargs root=/dev/mmcblk${devnum}p2 rw rootfstype=ext4 rootwait earlycon devtmpfs.mount=1 clk_ignore_unused uio_pdrv_genirq.of_id=generic-uio
fatload mmc 0:1 0x02000000 zimage
fatload mmc 0:1 0x01f00000 zynqmini.dtb
bootz 0x02000000 - 0x01f00000
""")
        run("mkimage", "-A", "arm", "-T", "script", "-C", "none", "-n", "zynqmini boot", "-d", script, os.path.join(tmp, "boot.scr"), stdout=subprocess.DEVNULL)
        rd = lambda p: open(p, "rb").read()
        files = [("BOOT.BIN", rd(o.boot_bin)), ("U-BOOT.IMG", rd(o.u_boot_img)), ("BOOT.SCR", rd(os.path.join(tmp, "boot.scr"))),
                 ("ZIMAGE", rd(os.path.join(o.kernel_dir, "zImage"))), ("ZYNQMINI.DTB", rd(os.path.join(o.kernel_dir, "zynq-zynqmini.dtb")))]
        fat = os.path.join(tmp, "boot.fat"); make_fat(fat, parts["1"][1], files)
        with open(out, "r+b") as img, open(fat, "rb") as f:
            img.seek(parts["1"][0]); shutil.copyfileobj(f, img, 1 << 20)
        # root filesystem: add the new kernel's modules + load zmbuf at boot
        stage = os.path.join(tmp, "stage"); os.makedirs(stage)
        run("tar", "-xzf", os.path.join(o.kernel_dir, "modules.tgz"), "-C", stage)
        conf = os.path.join(tmp, "zmbuf.conf"); open(conf, "w").write("zmbuf\n")
        cmd = os.path.join(tmp, "debugfs.cmd")
        open(cmd, "w").write(debugfs_script(os.path.join(stage, "modules"), "/lib/modules", [(conf, "/etc/modules-load.d/zmbuf.conf")]))
        print("adding modules to the root filesystem ...")
        r = subprocess.run([os.environ.get("DEBUGFS", "debugfs"), "-w", "-f", cmd, "%s?offset=%d" % (out, parts["2"][0])], capture_output=True, text=True)
        errs = [l for l in r.stdout.splitlines() + r.stderr.splitlines() if "rror" in l and "already exists" not in l.lower()]
        if errs: print("debugfs messages:", *errs[:5], sep="\n  ")
    print("image written:", out)

if __name__ == "__main__": main()
