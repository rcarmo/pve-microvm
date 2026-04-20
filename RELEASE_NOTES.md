# pve-microvm v0.1.22

Networking fix, GUI features, documentation update.

## Fixes

- **Networking**: `dhclient` fallback service for reliable DHCP on boot.
  systemd-networkd on Trixie has config matching issues with microvm's
  devtmpfs — the new `microvm-dhcp.service` runs `dhclient -4 eth0`
  as a oneshot at boot.
- **VM shutdown state**: documented `-no-shutdown` behavior and workaround.

## GUI features

- **Conditional panel hiding**: BIOS, EFI, TPM, USB, PCI rows hidden
  in create wizard and hardware view for microvm guests.
- **One-click clone**: right-click microvm templates → "⚡ Clone microvm".
- **Machine edit**: vIOMMU and version options hidden for microvm.
- **Add hardware menu**: unsupported device types disabled.

## Documentation

- Updated all docs for v0.1.21 architecture (PCIe, initrd, vsock, virtiofs).
- Added project icon to README.
- Added blog post link.
- Known issues fully documented with workarounds.
