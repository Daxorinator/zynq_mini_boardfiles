#!/usr/bin/env bash
# Builds a Debian (bookworm, armhf) root filesystem for the ZYNQ MINI with the open kernel: systemd, OpenSSH, apt, Python with the scientific stack, Jupyter, the USB gadget
# (serial + Ethernet) and network services, and the zynqmini hardware library (no PYNQ), and from it an SD image.
#   ./build.sh [stage ...]        stages: tools base packages configure image   (default: all; every stage resumes from the previous snapshot)
# Needs: sudo (chroot, mount, loop-less ext4 creation), qemu-user with binfmt registered for armhf (qemu-arm), curl, dpkg-deb, e2fsprogs, sfdisk, mkfs.fat.
# Output: build/debian/rootfs.ext4 and, with the open kernel (../linux/build.sh) and boot files (../boot/build.sh), build/debian/zynqmini-debian.img
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); OF=$HERE/..
WORK=${WORK:-$OF/build/debian}; SUITE=${SUITE:-bookworm}; MIRROR=${MIRROR:-http://deb.debian.org/debian}
ROOTFS=$WORK/rootfs; TOOLS=$WORK/tools; SIZE_MB=${SIZE_MB:-5120}
stages=${*:-tools base packages configure image}
mkdir -p "$WORK"
need() { command -v "$1" >/dev/null || { echo "missing: $1"; exit 1; }; }
need sudo; need curl; need dpkg-deb; need mke2fs
[ -e /proc/sys/fs/binfmt_misc/qemu-arm ] || { echo "qemu-arm is not registered in binfmt_misc (install qemu-user-static)"; exit 1; }

mounts() { for m in proc sys dev dev/pts; do sudo mountpoint -q "$ROOTFS/$m" || sudo mount --bind "/$m" "$ROOTFS/$m"; done; sudo mountpoint -q "$ROOTFS/run" || sudo mount -t tmpfs tmpfs "$ROOTFS/run"; }
umounts() { for m in run dev/pts dev sys proc; do sudo mountpoint -q "$ROOTFS/$m" && sudo umount "$ROOTFS/$m" || true; done; }
trap umounts EXIT
inchroot() { mounts; sudo chroot "$ROOTFS" /usr/bin/env -i HOME=/root TERM=dumb PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin DEBIAN_FRONTEND=noninteractive LC_ALL=C "$@"; }
snap() { umounts; sudo tar -C "$ROOTFS" --numeric-owner -cpf "$WORK/$1.tar" .; echo "snapshot $1: $(du -sh "$WORK/$1.tar" | cut -f1)"; }
restore() { umounts; sudo rm -rf "$ROOTFS"; sudo mkdir -p "$ROOTFS"; sudo tar -C "$ROOTFS" --numeric-owner -xpf "$WORK/$1.tar"; }

stage_tools() {      # debootstrap and the Debian archive keyring, fetched over HTTPS from the Debian archive and unpacked here (nothing is installed on the host)
  mkdir -p "$TOOLS/dl"; cd "$TOOLS/dl"
  for pkg in debootstrap debian-archive-keyring; do
    d=$(curl -sSf "$MIRROR/pool/main/${pkg:0:1}/$pkg/" | grep -o "${pkg}_[0-9][^\"]*_all\.deb" | sort -uV | tail -1); [ -n "$d" ] || { echo "no $pkg deb found"; exit 1; }
    [ -f "$d" ] || curl -sSfLO "$MIRROR/pool/main/${pkg:0:1}/$pkg/$d"; dpkg-deb -x "$d" "$TOOLS"; echo "tool: $d"
  done
}
DEBOOTSTRAP() { sudo env DEBOOTSTRAP_DIR="$TOOLS/usr/share/debootstrap" "$TOOLS/usr/sbin/debootstrap" "$@"; }
stage_base() {       # minimal Debian with an init system, then a snapshot
  sudo rm -rf "$ROOTFS"; sudo mkdir -p "$ROOTFS"
  DEBOOTSTRAP --arch=armhf --variant=minbase --keyring="$TOOLS/usr/share/keyrings/debian-archive-keyring.gpg" \
    --include=systemd-sysv,udev,kmod,dbus,ca-certificates,ifupdown,isc-dhcp-client,iproute2,openssh-server,sudo,locales "$SUITE" "$ROOTFS" "$MIRROR"
  snap base
}
stage_packages() {   # the big package list (apt under qemu: slow, resumable by snapshot)
  restore base
  sudo install -d "$ROOTFS/usr/sbin"; printf '#!/bin/sh\nexit 101\n' | sudo tee "$ROOTFS/usr/sbin/policy-rc.d" >/dev/null; sudo chmod 755 "$ROOTFS/usr/sbin/policy-rc.d"   # no services start in the chroot
  printf 'deb %s %s main\ndeb %s %s-updates main\ndeb http://security.debian.org/debian-security %s-security main\n' "$MIRROR" "$SUITE" "$MIRROR" "$SUITE" "$SUITE" | sudo tee "$ROOTFS/etc/apt/sources.list" >/dev/null
  # smaller image and faster installs under emulation: no docs, man pages or extra locales
  sudo install -d "$ROOTFS/etc/dpkg/dpkg.cfg.d"
  printf 'path-exclude=/usr/share/doc/*\npath-include=/usr/share/doc/*/copyright\npath-exclude=/usr/share/man/*\npath-exclude=/usr/share/info/*\npath-exclude=/usr/share/locale/*\npath-include=/usr/share/locale/locale.alias\n' | sudo tee "$ROOTFS/etc/dpkg/dpkg.cfg.d/01_nodoc" >/dev/null
  printf 'APT::Install-Recommends "false";\nAcquire::Languages "none";\n' | sudo tee "$ROOTFS/etc/apt/apt.conf.d/99zynqmini" >/dev/null
  inchroot apt-get update
  grep -v '^\s*#' "$HERE/packages.txt" | grep -v '^\s*$' | xargs sudo chroot "$ROOTFS" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin DEBIAN_FRONTEND=noninteractive LC_ALL=C apt-get install -y --no-install-recommends
  inchroot apt-get clean; sudo rm -rf "$ROOTFS"/var/lib/apt/lists/* "$ROOTFS/usr/sbin/policy-rc.d"
  snap packages
}
stage_configure() {  # overlay, users, services, Jupyter, zynqmini, notebooks, bitstreams, kernel modules
  restore packages
  sudo cp -a --no-preserve=ownership "$HERE/overlay/." "$ROOTFS/"
  sudo chmod 440 "$ROOTFS/etc/sudoers.d/zynq"
  # hardware layer, notebooks, tests, bitstreams (built by ../pl/build.sh) and the open kernel's modules
  sudo rm -rf "$ROOTFS/tmp/zynqmini-src"; sudo cp -r --no-preserve=ownership "$OF/py" "$ROOTFS/tmp/zynqmini-src"; sudo find "$ROOTFS/tmp/zynqmini-src" -name __pycache__ -prune -exec rm -rf {} +
  sudo install -d "$ROOTFS/usr/share/zynqmini/bitstreams" "$ROOTFS/usr/share/zynqmini/tests" "$ROOTFS/home/zynq/notebooks"
  sudo cp -r --no-preserve=ownership "$OF/py/notebooks/." "$ROOTFS/home/zynq/notebooks/"
  sudo cp -r --no-preserve=ownership "$OF/py/tests/." "$ROOTFS/usr/share/zynqmini/tests/"
  for d in hp_dma ple_mac zm_base; do [ -f "$OF/pl/build/$d/$d.bin" ] && sudo cp "$OF/pl/build/$d/$d.bin" "$ROOTFS/usr/share/zynqmini/bitstreams/" || echo "warning: pl/build/$d/$d.bin missing (run ../pl/build.sh $d)"; done
  for d in hp_dma ple_mac zm_base; do sudo cp "$OF/py/zynqmini/maps/$d.json" "$ROOTFS/usr/share/zynqmini/bitstreams/"; done
  if [ -f "$OF/linux/build/out/modules.tgz" ]; then sudo tar -xzf "$OF/linux/build/out/modules.tgz" -C "$ROOTFS/lib" --no-same-owner; else echo "warning: linux/build/out/modules.tgz missing (run ../linux/build.sh)"; fi
  KVER=$(ls "$ROOTFS/lib/modules" | grep zynqmini | head -1)
  sudo tee "$ROOTFS/tmp/configure.sh" >/dev/null <<'CFG'
#!/bin/sh
set -e
ln -sf /usr/share/zoneinfo/UTC /etc/localtime; echo UTC > /etc/timezone
sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen; locale-gen >/dev/null; echo 'LANG=en_US.UTF-8' > /etc/default/locale
useradd -m -s /bin/bash -G sudo,dialout,i2c,plugdev zynq 2>/dev/null || useradd -m -s /bin/bash -G sudo,dialout zynq
echo 'zynq:zynqmini' | chpasswd; echo 'root:zynqmini' | chpasswd
chown -R zynq:zynq /home/zynq
pip3 install --no-deps --no-build-isolation --break-system-packages /tmp/zynqmini-src
rm -rf /tmp/zynqmini-src
# Jupyter: password login (default password zynqmini; change it with `jupyter notebook password`), as root so notebooks can use /dev/mem and the FPGA manager
mkdir -p /root/.jupyter
H=$(python3 -c "from notebook.auth import passwd; print(passwd('zynqmini'))")
printf "c.NotebookApp.password = '%s'\nc.NotebookApp.open_browser = False\n" "$H" > /root/.jupyter/jupyter_notebook_config.py
# services
for u in zynqmini-mac zynqmini-usb-gadget zynqmini-sshkeys zynqmini-firstboot jupyter ssh haveged systemd-timesyncd fake-hwclock "serial-getty@ttyPS0"; do systemctl enable "$u.service" >/dev/null 2>&1 || echo "note: could not enable $u"; done
systemctl mask systemd-firstboot.service >/dev/null 2>&1 || true      # an empty machine-id counts as a first boot: never stop at an interactive setup on the serial console
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
for u in apt-daily.timer apt-daily-upgrade.timer e2scrub_all.timer e2scrub_reap.service; do systemctl mask "$u" >/dev/null 2>&1 || true; done
rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub            # fresh keys on the first boot (zynqmini-sshkeys)
grep -q '^initial-interval' /etc/dhcp/dhclient.conf || printf 'initial-interval 1;\nbackoff-cutoff 3;\n' >> /etc/dhcp/dhclient.conf
CFG
  inchroot sh /tmp/configure.sh
  [ -n "$KVER" ] && inchroot depmod -a "$KVER"
  sudo rm -f "$ROOTFS/tmp/configure.sh" "$ROOTFS/etc/machine-id"; sudo touch "$ROOTFS/etc/machine-id"        # an empty machine-id is filled in on the first boot
  sudo rm -rf "$ROOTFS"/var/cache/apt/* "$ROOTFS"/root/.cache "$ROOTFS"/tmp/*
  snap configured
}
stage_image() {      # ext4 from the tree (ownership kept, run as root), then the SD image with the open kernel and boot files if they exist
  restore configured; umounts
  sudo rm -f "$WORK/rootfs.ext4"
  sudo mke2fs -q -F -t ext4 -L zmroot -E root_owner=0:0 -d "$ROOTFS" "$WORK/rootfs.ext4" "${SIZE_MB}M"
  sudo chown "$(id -u):$(id -g)" "$WORK/rootfs.ext4"; e2fsck -fn "$WORK/rootfs.ext4" | tail -1
  B=$OF/boot/build/out; K=$OF/linux/build/out
  if [ -f "$B/BOOT.BIN" ] && [ -f "$B/u-boot.img" ] && [ -f "$K/zImage" ]; then
    python3 "$OF/linux/mkimage.py" --rootfs-image "$WORK/rootfs.ext4" --boot-bin "$B/BOOT.BIN" --u-boot-img "$B/u-boot.img" --kernel-dir "$K" --out "$WORK/zynqmini-debian.img"
  else echo "boot files or kernel missing: only $WORK/rootfs.ext4 was built (run ../boot/build.sh and ../linux/build.sh, then ./build.sh image)"; fi
}
for s in $stages; do echo "=== stage $s ($(date +%T))"; "stage_$s"; done
