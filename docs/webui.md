# Web UI

## Create µVM button

The PVE header toolbar has a **Create µVM** button (⚡ bolt icon) next to
Create VM and Create CT. It opens a dialog with:

- OCI image selector (12 Linux distros + specialist OS, freeform entry)
- Profile picker (minimal / standard / full)
- Storage picker (auto-filtered by node)
- VM ID (auto-populated from cluster)
- Memory, cores, disk size fields

The same option appears in the node right-click context menu.

## Microvm VM features

When a VM uses `machine: microvm`:

- **Resource tree**: ⚡ amber bolt icon (running/stopped/template states)
- **Console tab**: xterm.js serial terminal with bolt icon
- **Console button**: forces xterm.js (not noVNC)
- **Hardware view**: USB, PCI, BIOS, EFI, TPM, audio rows hidden
- **Add hardware menu**: unsupported devices disabled
- **Machine edit**: vIOMMU and version options hidden
- **Options panel**: unsupported options marked n/a
- **Context menu**: ⚡ Serial Console + ⚡ Clone microvm
- **Template right-click**: one-click clone

## Dark mode

All UI elements support PVE's dark theme automatically.

## Tags

Add `microvm` tag to any VM for the ⚡ icon:

```bash
qm set <vmid> --tags microvm
```

The template tool sets this automatically.
