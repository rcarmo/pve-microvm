# High Availability & Migration

## Offline migration

Microvms support offline migration between nodes on shared storage:

```bash
# VM must be stopped
qm migrate <vmid> <target-node>
```

Tested: z83ii ↔ borg, ~2 seconds on shared CIFS.

## HA support

```bash
# VM disks must be on shared storage (CIFS, NFS, etc.)
ha-manager add vm:<vmid> --group Intel --state started

# Relocate (stop → migrate → start)
ha-manager relocate vm:<vmid> <target-node>

# Remove from HA
ha-manager remove vm:<vmid>
```

## Limitations

- **No live migration** — QEMU microvm doesn't implement it
- **HA relocate** performs stop → migrate → start (2–10 s downtime)
- **Shared storage required** — all nodes must see the VM disk

## Tested flow

| Step | Result |
|---|---|
| Create on z83ii (shared CIFS) | ✅ |
| Offline migrate z83ii → borg | ✅ (2 seconds) |
| Start on borg | ✅ |
| HA add + started | ✅ |
| HA relocate borg → z83ii | ✅ |
| VM running after relocate | ✅ |
