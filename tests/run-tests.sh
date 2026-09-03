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

test_template_rootfs_helpers() {
    local tmp host_resolv
    tmp=$(mktemp -d)
    host_resolv=$(cat /etc/resolv.conf 2>/dev/null || true)
    # shellcheck disable=SC1091
    PVE_MICROVM_TEST_HELPERS_ONLY=1 source tools/pve-microvm-template

    mkdir -p "$tmp/empty/etc"
    : > "$tmp/empty/etc/resolv.conf"
    ensure_rootfs_resolver "$tmp/empty"
    [ -s "$tmp/empty/etc/resolv.conf" ] || { rm -rf "$tmp"; return 1; }

    mkdir -p "$tmp/dangling/etc"
    ln -s /run/systemd/resolve/stub-resolv.conf "$tmp/dangling/etc/resolv.conf"
    ensure_rootfs_resolver "$tmp/dangling"
    [ -f "$tmp/dangling/etc/resolv.conf" ] \
        && [ ! -L "$tmp/dangling/etc/resolv.conf" ] \
        && [ -s "$tmp/dangling/etc/resolv.conf" ] || { rm -rf "$tmp"; return 1; }

    mkdir -p "$tmp/alma/etc"
    printf 'ID="almalinux"\nID_LIKE="rhel centos fedora"\n' > "$tmp/alma/etc/os-release"
    is_enterprise_linux_rootfs "$tmp/alma" \
        && [ "$(rpm_base_packages "$tmp/alma")" = "iproute NetworkManager systemd cloud-init util-linux" ] \
        || { rm -rf "$tmp"; return 1; }

    mkdir -p "$tmp/photon/etc"
    printf 'ID=photon\n' > "$tmp/photon/etc/os-release"
    ! is_enterprise_linux_rootfs "$tmp/photon" \
        && [ "$(rpm_base_packages "$tmp/photon")" = "iproute dhcp-client systemd cloud-init util-linux" ] \
        || { rm -rf "$tmp"; return 1; }

    # Debian-family package path and cleanup of legacy/masked services.
    mkdir -p "$tmp/debian/usr/sbin" "$tmp/debian/etc/systemd/system/multi-user.target.wants"
    : > "$tmp/debian/usr/sbin/qemu-ga"
    chmod +x "$tmp/debian/usr/sbin/qemu-ga"
    printf 'legacy\n' > "$tmp/debian/etc/systemd/system/microvm-agent.service"
    ln -s ../microvm-agent.service "$tmp/debian/etc/systemd/system/multi-user.target.wants/microvm-agent.service"
    ln -s /dev/null "$tmp/debian/etc/systemd/system/qemu-guest-agent.service"
    mkdir -p "$tmp/debian/etc/systemd/system/qemu-guest-agent.service.d"
    : > "$tmp/debian/etc/systemd/system/qemu-guest-agent.service.d/stale.conf"
    configure_systemd_guest_agent "$tmp/debian"
    grep -q 'exec /usr/sbin/qemu-ga --method=virtio-serial --path=/dev/vport1p1' \
        "$tmp/debian/etc/systemd/system/qemu-guest-agent.service" \
        && grep -q '^WantedBy=multi-user.target$' "$tmp/debian/etc/systemd/system/qemu-guest-agent.service" \
        && grep -q 'test -c /dev/vport1p1' "$tmp/debian/etc/systemd/system/qemu-guest-agent.service" \
        && ! grep -Eq '^(BindsTo|Requires|ConditionPathExists)=' "$tmp/debian/etc/systemd/system/qemu-guest-agent.service" \
        && [ ! -e "$tmp/debian/etc/systemd/system/microvm-agent.service" ] \
        && [ ! -e "$tmp/debian/etc/systemd/system/multi-user.target.wants/microvm-agent.service" ] \
        && [ ! -e "$tmp/debian/etc/systemd/system/qemu-guest-agent.service.d" ] \
        || { rm -rf "$tmp"; return 1; }

    # RPM-family package path commonly installs qemu-ga under /usr/bin.
    mkdir -p "$tmp/rpm/usr/bin"
    : > "$tmp/rpm/usr/bin/qemu-ga"
    chmod +x "$tmp/rpm/usr/bin/qemu-ga"
    configure_systemd_guest_agent "$tmp/rpm"
    grep -q 'exec /usr/bin/qemu-ga --method=virtio-serial --path=/dev/vport1p1' \
        "$tmp/rpm/etc/systemd/system/qemu-guest-agent.service" \
        || { rm -rf "$tmp"; return 1; }

    rm -rf "$tmp"
}

test_qemuserver_patch_idempotency() {
    local tmp fixture patch_py
    tmp=$(mktemp -d)
    fixture="$tmp/QemuServer.pm"
    patch_py="$tmp/patchqs.py"
    cat > "$fixture" <<'EOF'
use PVE::QemuServer::Machine;

sub config_to_command {
    my ($storecfg, $vmid, $conf) = @_;
    return [];
}
EOF
    sed -n "/python3 << 'PATCHQS'/,/^PATCHQS$/p" tools/pve-microvm-patch \
        | sed '1d;$d' \
        | sed "s|^path = .*|path = r\"$fixture\"|" > "$patch_py"
    python3 "$patch_py" >/dev/null
    python3 "$patch_py" >/dev/null
    [ "$(grep -c '^use PVE::QemuServer::MicroVM;$' "$fixture")" -eq 1 ] \
        && [ "$(grep -c 'PVE::QemuServer::MicroVM::is_microvm' "$fixture")" -eq 1 ] || {
        rm -rf "$tmp"
        return 1
    }

    # Reproduce an old damaged host with three copies and require the same
    # patcher to heal it back to one canonical import/delegation block.
    cat > "$fixture" <<'EOF'
use PVE::QemuServer::Machine;
use PVE::QemuServer::MicroVM;
use PVE::QemuServer::MicroVM;
use PVE::QemuServer::MicroVM;

sub config_to_command {
    # pve-microvm: delegate to microvm command builder
    if (PVE::QemuServer::MicroVM::is_microvm(($_[2]))) {
        return PVE::QemuServer::MicroVM::microvm_config_to_command(@_);
    }
    # pve-microvm: delegate to microvm command builder
    if (PVE::QemuServer::MicroVM::is_microvm(($_[2]))) {
        return PVE::QemuServer::MicroVM::microvm_config_to_command(@_);
    }
    # pve-microvm: delegate to microvm command builder
    if (PVE::QemuServer::MicroVM::is_microvm(($_[2]))) {
        return PVE::QemuServer::MicroVM::microvm_config_to_command(@_);
    }
    my ($storecfg, $vmid, $conf) = @_;
    return [];
}
EOF
    python3 "$patch_py" >/dev/null
    [ "$(grep -c '^use PVE::QemuServer::MicroVM;$' "$fixture")" -eq 1 ] \
        && [ "$(grep -c 'PVE::QemuServer::MicroVM::is_microvm' "$fixture")" -eq 1 ]
    local rc=$?
    rm -rf "$tmp"
    return "$rc"
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
run_test "managed disk format executes raw/qcow2/RBD detection" perl tests/test-managed-volume-format.pl
run_test "managed disk format uses parse_volname" assert_file_contains tools/MicroVM.pm 'PVE::Storage::parse_volname\(\$storecfg, \$volid\)'
run_test "managed disk format avoids nonexistent volume_format API" assert_file_not_contains tools/MicroVM.pm 'PVE::Storage::volume_format'
run_test "managed disk format never silently falls back to raw" assert_file_not_contains tools/MicroVM.pm "detected_format.*//.*'raw'|format.*//.*'raw'"
run_test "apt templates install dbus for guest shutdown" assert_file_contains tools/pve-microvm-template 'PKGS=.*dbus'
run_test "template repairs empty and dangling resolv.conf" test_template_rootfs_helpers
run_test "template package transactions fail closed" assert_file_not_contains tools/pve-microvm-template '(apt-get|apk|dnf|microdnf|tdnf|yum).*install.*\|\| true'
run_test "Enterprise Linux uses NetworkManager" assert_file_contains tools/pve-microvm-template 'systemctl enable NetworkManager\.service'
run_test "Enterprise Linux installs full util-linux" assert_file_contains tools/pve-microvm-template 'NetworkManager systemd cloud-init util-linux'
run_test "templates configure one packaged guest-agent service" bash -c "[ \"\$(grep -c 'configure_systemd_guest_agent \"\$ROOTFS_DIR\"' tools/pve-microvm-template)\" -eq 2 ]"
run_test "guest-agent replacement opens the direct microVM port" assert_file_contains tools/pve-microvm-template 'exec \$qemu_ga --method=virtio-serial --path=/dev/vport1p1'
run_test "guest-agent replacement has no named-device dependency" assert_file_not_contains tools/pve-microvm-template '^BindsTo=.*org\.qemu\.guest_agent|^ConditionPathExists=.*/dev/virtio-ports'
run_test "templates do not create competing guest agent" assert_file_not_contains tools/pve-microvm-template 'ExecStart=.*microvm-agent|systemctl mask qemu-guest-agent.service'
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
run_test "postinst does not delete patch stamp" assert_file_not_contains debian/pve-microvm.postinst 'rm -f /usr/share/pve-microvm/\.applied'
run_test "postinst reloads pvedaemon after configure" bash -c "[ \"\$(grep -c 'systemctl try-restart pvedaemon.service' debian/pve-microvm.postinst)\" -eq 2 ]"
run_test "patcher refreshes module on package upgrade" assert_file_contains tools/pve-microvm-patch 'patches already applied; refreshing module and UI'
run_test "QemuServer patch insertion is idempotent" test_qemuserver_patch_idempotency
run_test "early service runs before pvedaemon and pve-guests" bash -c "grep -q 'Before=.*pvedaemon.service' tools/pve-microvm-early.service && grep -q 'Before=.*pve-guests.service' tools/pve-microvm-early.service"

log "Documentation contracts"
run_test "README install snippet is version-agnostic" assert_file_not_contains README.md 'pve-microvm_0\.[0-9]+\.[0-9]+-[0-9]+_all\.deb'
run_test "installation docs are version-agnostic" assert_file_not_contains docs/installation.md 'pve-microvm_0\.[0-9]+\.[0-9]+-[0-9]+_all\.deb|releases/download/v0\.[0-9]+'
run_test "docs keep scsi0 root at vda with cloud-init on vdb" bash -c "grep -q '\`scsi0\` is emitted first' docs/architecture.md && grep -q '\`/dev/vda\`; an optional cloud-init disk at \`scsi1\` appears as \`/dev/vdb\`' docs/architecture.md"
run_test "troubleshooting avoids unreliable vmlinuz strings check" assert_file_not_contains docs/troubleshooting.md 'strings /usr/share/pve-microvm/vmlinuz'
run_test "docs explain direct guest-agent port" assert_file_contains docs/known-issues.md '/dev/vport1p1'
run_test "docs prohibit dual qemu-ga processes" assert_file_contains docs/troubleshooting.md 'exactly one `qemu-ga` process'
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
