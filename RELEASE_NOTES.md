# pve-microvm v0.3.4

## New guest OS support

- **OpenWrt 25.12.2** — `pve-microvm-template --image openwrt`
  13 MB download, boots in ~5s, full routing/firewall stack
- **OPNsense 25.1** — `pve-microvm-template --image opnsense`
  FreeBSD-based firewall, 500 MB download, HTTPS + SSH out of box

## Bug fixes

- **postinst reapply** — upgrades now always revert+reapply patches
  (previously skipped when stamp existed, leaving stale MicroVM.pm)
- **Cloud-init drive order** — scsi0 always first (/dev/vda = root)
  via sorted conf key iteration (not valid_drive_names)

## UI

- Create µVM dialog: added OpenWrt, OPNsense, 9Front, OSv to dropdown
- 49 shipped features total

## Full guest OS matrix

12 Linux distros + 8 non-Linux:
Debian, Ubuntu, Alpine, Fedora, Rocky, Alma, Amazon, Oracle, UBI,
Photon, Azure Linux, 9Front, OSv, gokrazy, Firecracker, OpenWrt, OPNsense
