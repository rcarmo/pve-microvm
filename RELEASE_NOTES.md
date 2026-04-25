# pve-microvm v0.3.1

Bugfix release: cloud-init drive ordering, UI overhaul, 9p support.

## Bug fixes

- **Cloud-init drive order** — on qemu-server < 9.1.8, the cloud-init ISO
  could displace the root disk. Fixed with three layers: is_microvm()
  fallback, sorted drive iteration, and LABEL=microvm-root root device.
- **dpkg trigger loop** — `interest-noawait` prevents upgrade hangs.
- **Hardware view Remove button** — CSS hiding instead of store.filterBy.

## New features

- **Create µVM dialog** — OCI image picker with 12 distros, profiles, storage selector
- **Console tab** — xterm.js with ⚡ bolt icon for microvm VMs
- **Console button** — forces xterm.js (serial) instead of noVNC
- **9p filesystem sharing** — `pve-microvm-9p` tool, no daemon needed
- **Amber ⚡ icon** — all microvm UI elements use amber/orange

## Docs

- Full audit: FAQ, usage, test matrix, all aligned
- Firecracker VMM (was incorrectly listed as libkrun)
- Template options: --profile, --no-docker, --no-ssh, --no-agent documented
