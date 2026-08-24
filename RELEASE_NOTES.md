# pve-microvm v0.3.22

## Enterprise Linux template fixes

- Repair empty or dangling OCI `/etc/resolv.conf` before chroot package installation, restoring DNS for affected image families.
- Treat apt, apk, dnf, microdnf, tdnf, and yum transaction failures as fatal instead of publishing a bare but apparently successful template.
- Use NetworkManager with an autoconnect DHCP profile on Enterprise Linux 8, 9, and 10.
- Install full `util-linux` so `/usr/bin/login` exists for the serial console.
- Remove the unavailable `dhclient` fallback from Enterprise Linux templates.
- Add regression tests for resolver repair, Enterprise Linux detection, package selection, and fail-closed transactions.

Live validation used AlmaLinux 10.2 on PVE 9.2.6: a full clone booted with root on `/dev/vda`, NetworkManager and SSH active, a responsive QEMU guest agent, working DNS, and no legacy DHCP unit.

## Guest-agent service fix

- New apt- and RPM-based templates now use the packaged, device-bound
  `qemu-guest-agent.service` exclusively.
- Stop generating a competing `microvm-agent.service` that could loop forever
  when both agents attempted to open `/dev/vport1p1`.
- Template creation removes the obsolete custom unit and unmasks the packaged
  service, making the operation safe for reused root filesystems.
- Add regression tests and remediation guidance for older affected guests.

## API/UI command-builder reload

- Package configure and qemu-server trigger paths now run
  `systemctl try-restart pvedaemon.service` after applying or refreshing files.
- This ensures UI, API, `pvesh`, and automation starts use the newly installed
  `MicroVM.pm`; long-lived pvedaemon workers previously retained the old module.
- Existing running microVMs are not interrupted. They still need an intentional
  restart when their QEMU process must gain newly added command-line options.

## Upgrade safety

- Detect and repair hosts that already contain multiple historical copies of
  the `MicroVM.pm` import/delegation block, canonicalising them to exactly one.
- Preserve existing clean backups while normalising damaged patched files.

- Package upgrades no longer remove the patch stamp and blindly insert another
  Perl import/delegation block.
- When qemu-server is already patched, upgrades refresh `MicroVM.pm` and the UI
  without modifying `QemuServer.pm` again.
- If files and stamp are out of sync, the patcher checks existing markers before
  insertion, so applying twice remains idempotent.
- The CI suite executes the embedded QemuServer patcher twice against a fixture
  and requires exactly one import and one delegation block.

This release supersedes v0.3.17 through v0.3.21 for deployment.

## Guest lifecycle fixes

- Add PVE's qmeventd event monitor to every microVM QEMU command line.
  Guest-initiated shutdowns are now reaped correctly instead of leaving QEMU
  paused in `shutdown` state under `-no-shutdown`.
- `qm shutdown`, `qm reboot`, and the corresponding PVE web UI actions now work
  for standard-profile guests with the QEMU guest agent enabled.
- Add D-Bus to newly built Debian/Ubuntu templates so the guest agent can ask
  systemd/logind to schedule shutdown and reboot.

Existing Debian/Ubuntu guests built without D-Bus need:

```bash
apt-get update
apt-get install -y dbus
systemctl enable --now dbus
```

Guests created with `--no-agent` still have no guaranteed graceful shutdown
path; use `qm stop` or install and enable the QEMU guest agent.

## Configurable PVE bridge

- Add `--bridge BRIDGE` and `--bridge=BRIDGE` to
  `pve-microvm-template`.
- Remove hardcoded `vmbr0` from OpenWrt, OPNsense, and SmolBSD template paths.
- All template paths now honour the configured bridge.

## Tests and documentation

- Add parser tests for both bridge argument forms and missing values.
- Add command-builder contracts for qmeventd, QEMU reconnect compatibility,
  D-Bus, and hardcoded bridge prevention.
- Document shutdown/reboot diagnosis, existing-guest remediation, and the
  guest-agent limitation.
- Correct troubleshooting guidance: apply patches to the current qemu-server
  files directly; never restore a potentially stale backup before applying.

## Upgrade

Use the latest-release command from the installation guide, install the `.deb`,
and restart each running microVM so its QEMU process gains the qmeventd monitor.
Templates and stopped guests do not need to be started during the upgrade.
