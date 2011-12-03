
# Let's not allow parallel operation if for no other reason than to avoid mangled output
# Set SUBMAKE_JOBS to pass -jN to submakes. Defaults to 3.
.NOTPARALLEL:

ifeq ($(SUBMAKE_JOBS),)
  SUBMAKE_JOBS=3
endif

ifneq ("$(shell id -nu)","root")
  $(error Makefile must be run as root)
endif

all: kernel initrd rootfs

# Output directory
OUT=output
CHROOT=$(OUT)/chroot

dummy_create_output_dir := $(shell test -d $(OUT) || mkdir -p $(OUT))

# Kernel
KERNEL_VERSION=3.1

kernel: $(OUT)/linux.uml

$(OUT)/linux.uml: $(OUT)/linux-$(KERNEL_VERSION) $(OUT)/aufs3-standalone
	scripts/compile-kernel.sh $(OUT)/linux-$(KERNEL_VERSION) $(SUBMAKE_JOBS)
	cp -f $(OUT)/linux-$(KERNEL_VERSION)/linux $@

$(OUT)/linux-$(KERNEL_VERSION): $(OUT)/linux-$(KERNEL_VERSION).tar.bz2
	tar -C $(OUT) -xvjf $(OUT)/linux-$(KERNEL_VERSION).tar.bz2
	cp kernel/kernel-config $(OUT)/linux-$(KERNEL_VERSION)/.config

$(OUT)/linux-$(KERNEL_VERSION).tar.bz2:
	wget -O $@ http://www.kernel.org/pub/linux/kernel/v3.0/linux-$(KERNEL_VERSION).tar.bz2

$(OUT)/aufs3-standalone:
	git clone -b aufs3.1 git://aufs.git.sourceforge.net/gitroot/aufs/aufs3-standalone.git $(OUT)/aufs3-standalone


# Chroot and rootfs
rootfs: $(OUT)/rootfs.squashfs

ifneq ($(NO_SQUASHFS_COMPRESS),)
  SQUASHFS_EXTRA_OPTS="-noD -noI -noF"
endif

$(OUT)/rootfs.squashfs: chroot
	mksquashfs $(CHROOT) $@ -all-root -noappend -e var/cache/apt $(SQUASHFS_EXTRA_OPTS)
	chmod a+r $@

chroot: $(CHROOT)/var/log/dpkg.log $(CHROOT)/sbin/tmc-init

$(CHROOT)/var/log/dpkg.log: rootfs/multistrap.conf
	mkdir -p $(CHROOT)
	multistrap -f rootfs/multistrap.conf
	umount $(CHROOT)/proc

$(CHROOT)/sbin/tmc-init: $(CHROOT)/var/log/dpkg.log rootfs/tmc-init
	cp rootfs/tmc-init $(CHROOT)/sbin/tmc-init
	chmod +x $(CHROOT)/sbin/tmc-init

# Busybox
BUSYBOX_VERSION=1.19.2
BUSYBOX_INSTALL_DIR=$(OUT)/busybox-$(BUSYBOX_VERSION)/_install
busybox: $(BUSYBOX_INSTALL_DIR)/bin/busybox

$(BUSYBOX_INSTALL_DIR)/bin/busybox: $(OUT)/busybox-$(BUSYBOX_VERSION) busybox/busybox-config
	cp busybox/busybox-config $(OUT)/busybox-$(BUSYBOX_VERSION)/.config
	make -C $(OUT)/busybox-$(BUSYBOX_VERSION) -j$(SUBMAKE_JOBS)
	make -C $(OUT)/busybox-$(BUSYBOX_VERSION) install

$(OUT)/busybox-$(BUSYBOX_VERSION): $(OUT)/busybox-$(BUSYBOX_VERSION).tar.bz2
	tar -C $(OUT) -xvjf $(OUT)/busybox-$(BUSYBOX_VERSION).tar.bz2

$(OUT)/busybox-$(BUSYBOX_VERSION).tar.bz2:
	wget -O $@ http://busybox.net/downloads/busybox-$(BUSYBOX_VERSION).tar.bz2

# Initrd
initrd: $(OUT)/initrd.img

$(OUT)/initrd.img: $(OUT)/initrd/init
	cd $(OUT)/initrd && mkdir -p proc sys tmp var
	cd $(OUT)/initrd && find . | cpio --quiet -H newc -o | gzip > ../initrd.img

$(OUT)/initrd/init: chroot busybox
	mkdir -p $(OUT)/initrd
	cp -a $(BUSYBOX_INSTALL_DIR)/* $(OUT)/initrd/
	cp -a $(CHROOT)/dev $(OUT)/initrd/dev
	cp initrd/initrd-init-script $(OUT)/initrd/init
	chmod +x $(OUT)/initrd/init


# Cleanup
clean:
	rm -Rf $(OUT)

clean-kernel:
	rm -Rf $(OUT)/linux-$(KERNEL_VERSION) $(OUT)/linux.uml

clean-chroot:
	rm -Rf $(CHROOT)

clean-rootfs: clean-chroot
	rm -f $(OUT)/rootfs.squashfs

clean-busybox:
	rm -Rf $(OUT)/busybox-$(BUSYBOX_VERSION)

clean-initrd:
	rm -Rf $(OUT)initrd $(OUT)/initrd.img
