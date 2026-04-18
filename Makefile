PACKAGE = pve-microvm
VERSION = 0.1.0

.PHONY: all build install clean deb kernel

all: build

build:
	@echo "Nothing to compile (kernel built separately via CI or kernel/build-kernel.sh)"

kernel:
	cd kernel && ./build-kernel.sh --version 6.12.22 --output vmlinuz-microvm

install:
	# Patches
	install -d $(DESTDIR)/usr/share/pve-microvm/patches
	install -m 644 debian/patches/*.patch $(DESTDIR)/usr/share/pve-microvm/patches/

	# Patch tool and MicroVM module
	install -d $(DESTDIR)/usr/share/pve-microvm
	install -m 755 tools/pve-microvm-patch $(DESTDIR)/usr/share/pve-microvm/
	install -m 644 tools/MicroVM.pm $(DESTDIR)/usr/share/pve-microvm/
	install -m 644 doc/microvm-defaults.conf $(DESTDIR)/usr/share/pve-microvm/

	# OCI import tool
	install -d $(DESTDIR)/usr/bin
	install -m 755 tools/pve-oci-import $(DESTDIR)/usr/bin/

	# Kernel binary (if built)
	if [ -f kernel/vmlinuz-microvm ]; then \
		install -m 644 kernel/vmlinuz-microvm $(DESTDIR)/usr/share/pve-microvm/vmlinuz; \
	fi

	# Kernel build tooling
	install -d $(DESTDIR)/usr/share/pve-microvm/kernel
	install -m 755 kernel/build-kernel.sh $(DESTDIR)/usr/share/pve-microvm/kernel/
	install -m 644 kernel/base-x86_64-6.1.config $(DESTDIR)/usr/share/pve-microvm/kernel/
	install -m 644 kernel/pve-microvm-overlay.config $(DESTDIR)/usr/share/pve-microvm/kernel/

deb:
	dpkg-buildpackage -us -uc -b

clean:
	dh_clean 2>/dev/null || true

realclean:
	rm -f kernel/vmlinuz-microvm
