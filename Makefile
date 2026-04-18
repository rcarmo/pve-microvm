# Update the debian/rules to also install MicroVM.pm
PACKAGE = pve-microvm
VERSION = 0.1.0

.PHONY: all build install clean deb

all: build

build:
	@echo "Nothing to build"

install:
	install -d $(DESTDIR)/usr/share/pve-microvm/patches
	install -m 644 debian/patches/*.patch $(DESTDIR)/usr/share/pve-microvm/patches/
	install -d $(DESTDIR)/usr/share/pve-microvm
	install -m 755 tools/pve-microvm-patch $(DESTDIR)/usr/share/pve-microvm/
	install -m 644 tools/MicroVM.pm $(DESTDIR)/usr/share/pve-microvm/
	install -m 644 doc/microvm-defaults.conf $(DESTDIR)/usr/share/pve-microvm/
	install -d $(DESTDIR)/usr/bin
	install -m 755 tools/pve-oci-import $(DESTDIR)/usr/bin/

deb:
	dpkg-buildpackage -us -uc -b

clean:
	dh_clean
