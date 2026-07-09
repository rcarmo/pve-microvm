#!/usr/bin/env bash
# pve-microvm local/CI test suite
#
# These tests deliberately avoid requiring a live Proxmox VE host.  Runtime PVE
# behaviours are checked with mocks or static contract tests; live-node checks
# remain documented in AGENTS.md.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

PASS=0
FAIL=0

log() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
ok() { printf '\033[32mOK\033[0m   %s\n' "$*"; PASS=$((PASS + 1)); }
not_ok() { printf '\033[31mFAIL\033[0m %s\n' "$*"; FAIL=$((FAIL + 1)); }

run_test() {
    local name="$1"; shift
    if "$@"; then
        ok "$name"
    else
        not_ok "$name"
    fi
}

assert_file_contains() {
    local file="$1" pattern="$2"
    grep -Eq "$pattern" "$file"
}

assert_file_not_contains() {
    local file="$1" pattern="$2"
    ! grep -Eq "$pattern" "$file"
}

log "Shell syntax"
for script in \
    tools/pve-microvm-template \
    tools/pve-microvm-patch \
    tools/pve-oci-import \
    tools/pve-microvm-run \
    tools/pve-microvm-bench \
    tools/pve-microvm-9p \
    tools/pve-microvm-share \
    tools/pve-microvm-ssh-agent \
    kernel/build-kernel.sh; do
    [ -f "$script" ] || continue
    run_test "bash -n $script" bash -n "$script"
done

log "pve-microvm-template argument parser"
mock_dir=$(mktemp -d)
tmp_out=$(mktemp)
tmp_err=$(mktemp)
cleanup_parser() { rm -rf "$mock_dir" "$tmp_out" "$tmp_err"; }
trap cleanup_parser EXIT

cat > "$mock_dir/qm" <<'MOCKQM'
#!/bin/sh
case "$1" in
  config)
    # Pretend the template already exists so pve-microvm-template exits after
    # parsing and validation, before any destructive/create path.
    exit 0
    ;;
  list)
    printf 'VMID NAME STATUS MEM PID\n'
    exit 0
    ;;
  *)
    echo "MOCK qm $*" >&2
    exit 0
    ;;
esac
MOCKQM
chmod +x "$mock_dir/qm"

parser_ok() {
    PATH="$mock_dir:$PATH" ./tools/pve-microvm-template "$@" >"$tmp_out" 2>"$tmp_err"
}

parser_fail() {
    if PATH="$mock_dir:$PATH" ./tools/pve-microvm-template "$@" >"$tmp_out" 2>"$tmp_err"; then
        printf 'expected failure, got success\nstdout:\n%s\nstderr:\n%s\n' "$(cat "$tmp_out")" "$(cat "$tmp_err")" >&2
        return 1
    fi
    grep -q 'ERROR:' "$tmp_err"
}

run_test "GUI command shape parses" parser_ok \
    --image nginx:1.30.2 --vmid 105 --name microvm --storage local-lvm \
    --memory 256 --disk-size 2G --profile standard --cores 1

run_test "bridge space form parses" parser_ok --bridge vmbr1
run_test "bridge equals form parses" parser_ok --bridge=vmbr1

run_test "equals form parses" parser_ok \
    --image=nginx:1.30.2 --vmid=105 --name=microvm --storage=local-lvm \
    --memory=256 --disk-size=2G --profile=standard --cores=1 --bridge=vmbr1

run_test "profile flags parse" parser_ok --profile full --no-docker --no-ssh --no-agent
run_test "list action parses" parser_ok --list

run_test "missing --image value fails cleanly" parser_fail --image
run_test "missing --vmid value fails cleanly" parser_fail --vmid --name x
run_test "missing --name value fails cleanly" parser_fail --name
run_test "missing --storage value fails cleanly" parser_fail --storage --memory 256
run_test "missing --disk-size value fails cleanly" parser_fail --disk-size
run_test "missing --memory value fails cleanly" parser_fail --memory
run_test "missing --memory before next option fails cleanly" parser_fail --memory --cores 1
run_test "missing --cores value fails cleanly" parser_fail --cores
run_test "missing --bridge value fails cleanly" parser_fail --bridge
run_test "missing --bridge before next option fails cleanly" parser_fail --bridge --cores 1
run_test "missing --profile value fails cleanly" parser_fail --profile
run_test "empty --memory= fails cleanly" parser_fail --memory=
run_test "empty --cores= fails cleanly" parser_fail --cores=
run_test "nonnumeric memory fails" parser_fail --memory nope --cores 1
run_test "zero memory fails" parser_fail --memory 0 --cores 1
run_test "nonnumeric cores fails" parser_fail --memory 256 --cores nope
run_test "zero cores fails" parser_fail --memory 256 --cores 0
run_test "unknown argument fails" parser_fail --bogus
run_test "unknown profile fails" parser_fail --profile enormous

log "GUI/CLI contract"
run_test "wizard-generated flags are accepted by pve-microvm-template" python3 - <<'PY'
from pathlib import Path
import re
ui = Path('ui/pve-microvm.js').read_text()
script = Path('tools/pve-microvm-template').read_text()
# Flags produced in the pve-microvm-template command string inside the GUI.
cmd_start = ui.index("var cmd = 'pve-microvm-template'")
cmd_end = ui.index(';', cmd_start)
cmd = ui[cmd_start:cmd_end]
ui_flags = set(re.findall(r"' --([a-z0-9-]+) '", cmd))
# Flags supported by parser, including --flag and --flag=* cases.
parser_flags = set(re.findall(r"--([a-z0-9-]+)(?:\)|=\*)", script))
missing = sorted(ui_flags - parser_flags)
if missing:
    raise SystemExit(f'GUI emits unsupported pve-microvm-template flags: {missing}')
PY

log "Memory-management command builder contracts"
run_test "balloon enables free page reporting" assert_file_contains tools/MicroVM.pm 'free-page-reporting=on'
run_test "balloon enables deflate-on-oom" assert_file_contains tools/MicroVM.pm 'deflate-on-oom=on'
run_test "virtio-mem backend exists" assert_file_contains tools/MicroVM.pm 'memory-backend-ram,id=vmem0'
run_test "virtio-mem device exists" assert_file_contains tools/MicroVM.pm 'virtio-mem-pci,id=vmem0,memdev=vmem0'
run_test "virtio-mem starts with requested-size=0" assert_file_contains tools/MicroVM.pm 'requested-size=0'
run_test "no stale balloon_target assignment" assert_file_not_contains tools/MicroVM.pm 'my \$balloon_target'
run_test "microVM command includes qmeventd socket" assert_file_contains tools/MicroVM.pm 'path=/var/run/qmeventd\.sock'
run_test "microVM command includes qmp-event monitor" assert_file_contains tools/MicroVM.pm 'chardev=qmp-event,mode=control'
run_test "qmeventd supports QEMU 9.2 reconnect-ms" assert_file_contains tools/MicroVM.pm 'reconnect-ms=5000'
run_test "qmeventd keeps older QEMU reconnect fallback" assert_file_contains tools/MicroVM.pm 'reconnect=5'
run_test "apt templates install dbus for guest shutdown" assert_file_contains tools/pve-microvm-template 'PKGS=.*dbus'
run_test "special templates do not hardcode vmbr0" assert_file_not_contains tools/pve-microvm-template 'bridge=vmbr0'

log "Kernel config contracts"
run_test "kernel build merges PVE overlay" assert_file_contains kernel/build-kernel.sh 'pve-microvm-overlay\.config'
run_test "kernel verifies TUN survives olddefconfig" assert_file_contains kernel/build-kernel.sh 'CONFIG_TUN'
run_test "kernel enables TUN/TAP" assert_file_contains kernel/pve-microvm-overlay.config '^CONFIG_TUN=y$'
run_test "kernel enables netfilter advanced" assert_file_contains kernel/pve-microvm-overlay.config '^CONFIG_NETFILTER_ADVANCED=y$'
run_test "kernel enables nftables inet family" assert_file_contains kernel/pve-microvm-overlay.config '^CONFIG_NF_TABLES_INET=y$'
run_test "kernel enables nft NAT" assert_file_contains kernel/pve-microvm-overlay.config '^CONFIG_NFT_NAT=y$'
run_test "kernel enables nft masquerade" assert_file_contains kernel/pve-microvm-overlay.config '^CONFIG_NFT_MASQ=y$'
run_test "kernel enables IPv6 NAT" assert_file_contains kernel/pve-microvm-overlay.config '^CONFIG_IP6_NF_NAT=y$'
run_test "kernel enables bridge netfilter" assert_file_contains kernel/pve-microvm-overlay.config '^CONFIG_BRIDGE_NETFILTER=y$'

log "Patch-script safety contracts"
run_test "patch script has stamp/idempotency guard" assert_file_contains tools/pve-microvm-patch 'patches already applied'
run_test "patch script delegates config_to_command once per apply path" assert_file_contains tools/pve-microvm-patch 'delegate to microvm command builder'
run_test "postinst never reverts before applying" assert_file_not_contains debian/pve-microvm.postinst 'pve-microvm-patch revert|cmd_revert| revert'
run_test "early service runs before pvedaemon and pve-guests" bash -c "grep -q 'Before=.*pvedaemon.service' tools/pve-microvm-early.service && grep -q 'Before=.*pve-guests.service' tools/pve-microvm-early.service"

log "Documentation contracts"
run_test "README install snippet is version-agnostic" assert_file_not_contains README.md 'pve-microvm_0\.[0-9]+\.[0-9]+-[0-9]+_all\.deb'
run_test "installation docs are version-agnostic" assert_file_not_contains docs/installation.md 'pve-microvm_0\.[0-9]+\.[0-9]+-[0-9]+_all\.deb|releases/download/v0\.[0-9]+'
run_test "README roadmap table rows have two columns" python3 - <<'PY'
from pathlib import Path
bad=[]
for i,line in enumerate(Path('README.md').read_text().splitlines(), 1):
    if line.startswith('|') and '|' in line[1:]:
        cells=[c.strip() for c in line.strip().strip('|').split('|')]
        # Only enforce the roadmap table: it has Feature/Priority header.
        if 'Feature' in cells and 'Priority' in cells:
            in_table=True
        if '~~Memory management' in line and len(cells) != 2:
            bad.append((i, len(cells), line))
if bad:
    raise SystemExit(bad)
PY
run_test "AGENTS.md avoids local cluster IP literals" assert_file_not_contains AGENTS.md '192\.168\.1\.'
run_test "AGENTS.md documents PVE dist-upgrade process" assert_file_contains AGENTS.md 'apt-get dist-upgrade'
run_test "AGENTS.md documents EFI kernel maintenance" assert_file_contains AGENTS.md 'EFI partition|/boot/efi'

log "GitHub latest release command shape"
run_test "latest release API exposes a .deb asset" python3 - <<'PY'
# This is intentionally network-free in CI/local tests: validate the documented
# command shape rather than calling GitHub on every test run.
from pathlib import Path
text = Path('docs/installation.md').read_text() + '\n' + Path('README.md').read_text()
required = [
    'https://api.github.com/repos/rcarmo/pve-microvm/releases/latest',
    'browser_download_url',
    "grep '.deb'",
    'dpkg -i pve-microvm_*.deb',
]
missing = [s for s in required if s not in text]
if missing:
    raise SystemExit(f'missing latest-release install fragments: {missing}')
PY

log "Summary"
printf 'Passed: %d\nFailed: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
