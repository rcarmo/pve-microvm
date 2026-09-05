"""Execute safety regressions without PVE, root, network or real mounts."""
from pathlib import Path
import re
import subprocess
import tempfile

script = Path('tools/pve-microvm-template').read_text()
cleanup = re.search(r'cleanup_build\(\) \{.*?\n\}', script, re.S).group()
with tempfile.TemporaryDirectory() as tmp:
    work = Path(tmp) / 'build'
    for mode in ('mounted', 'unavailable', 'clear'):
        work.mkdir(exist_ok=True)
        (work / 'sentinel').write_text('must survive unsafe cleanup')
        findmnt = {'mounted': f'printf "%s\\n" "{work}/dev"',
                   'unavailable': 'return 1', 'clear': 'printf "/\\n"'}[mode]
        subprocess.run(['bash', '-c', f'''
set -euo pipefail
WORKDIR={work}
ROOTFS_DIR=$WORKDIR/rootfs
log() {{ :; }}
umount() {{ return 1; }}
findmnt() {{ {findmnt}; }}
{cleanup}
cleanup_build
'''], check=True)
        assert work.exists() == (mode != 'clear'), mode

runner = Path('tools/pve-microvm-run').read_text()
assert runner.index('qm clone ') < runner.index('trap cleanup EXIT') < runner.index('qm set ')
python = runner.split('python3 -c "', 1)[1].rsplit('"', 1)[0]
for response, code in [('{"exitcode":7,"out-data":"hello"}', 7),
                       ('{"exitcode":0}', 0), ('not JSON', 1), ('{}', 1), ('[]', 1), ('{"exitcode":true}', 1)]:
    result = subprocess.run(['python3', '-c', python], input=response, text=True,
                            capture_output=True)
    assert result.returncode == code, (response, result.returncode)

# Execute refresh safety checks with an existing non-template and failed destroy.
block = script[script.index('# Check if template already exists'):script.index('# Validate tools')]
for template in (False, True):
    result = subprocess.run(['bash', '-c', '''
set -euo pipefail
TEMPLATE_VMID=123; REFRESH=1
log() { :; }
die() { echo "$*" >&2; exit 1; }
qm() {
 case "$1" in
 config) echo "template: ''' + ('1' if template else '0') + '''";;
 status) echo 'status: stopped';;
 *) exit 99;;
 esac
}
''' + block], capture_output=True, text=True)
    assert result.returncode == (0 if template else 1)
assert 'qm destroy "$TEMPLATE_VMID" --purge || die' in script
assert 'curl -fL --retry 3 "$NFRONT_URL" -o "$NFRONT_GZ"' in script
print('audit regressions passed: bind-mount cleanup, failed inventory, refresh guards, exit codes, clone cleanup, 9Front download')

# Run the actual embedded QemuServer patcher on an unsupported layout.
patcher = Path('tools/pve-microvm-patch').read_text()
embedded = patcher.split("<< 'PATCHQS'\n", 1)[1].split('\nPATCHQS', 1)[0]
with tempfile.TemporaryDirectory() as tmp:
    fixture = Path(tmp) / 'QemuServer.pm'
    original = 'use strict;\n# incompatible upstream layout\n'
    fixture.write_text(original)
    code = re.sub(r'^path = .*$', f'path = {str(fixture)!r}', embedded, flags=re.M)
    result = subprocess.run(['python3', '-c', code], capture_output=True, text=True)
    assert result.returncode != 0
    assert fixture.read_text() == original

# Kernel checks must fail rather than merely print missing Kconfig values.
kernel = Path('kernel/build-kernel.sh').read_text()
assert 'required kernel option $cfg is missing' in kernel
assert 'rollback cannot verify legacy backups' in patcher
assert 'sha256sum -c "$BACKUP_DIR/patched.sha256"' in patcher
assert 'fresh_originals=1' in patcher
print('patch layout refusal and rollback/kernel safety contracts passed')

# Execute rollback with fake files; ensure legacy/mismatched files survive.
revert = re.search(r'cmd_revert\(\) \{.*?\n\}', patcher, re.S).group()
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    (root/'backup').mkdir()
    for name in ('stamp','Machine.pm','QemuServer.pm','module'):
        (root/name).write_text('current')
    for name in ('Machine.pm.orig','QemuServer.pm.orig'):
        (root/'backup'/name).write_text('old')
    prefix = f'''
set -e
STAMP={root}/stamp
BACKUP_DIR={root}/backup
MACHINE_PM={root}/Machine.pm
QEMU_SERVER_PM={root}/QemuServer.pm
MICROVM_MODULE={root}/module
INDEX_TPL={root}/index
PVE_CSS_DIR={root}/css
PVE_JS_DIR={root}/js
log() {{ :; }}
die() {{ echo "$*" >&2; exit 1; }}
'''
    for manifest in (None, '0'*64+'  '+str(root/'Machine.pm')+'\n'):
        if manifest: (root/'backup'/'patched.sha256').write_text(manifest)
        result = subprocess.run(['bash','-c',prefix+revert+'\ncmd_revert'],capture_output=True)
        assert result.returncode != 0
        assert (root/'Machine.pm').read_text() == 'current'
        assert (root/'module').exists()
    import hashlib
    manifest=''.join(hashlib.sha256((root/n).read_bytes()).hexdigest()+'  '+str(root/n)+'\n' for n in ('Machine.pm','QemuServer.pm'))
    (root/'backup'/'patched.sha256').write_text(manifest)
    subprocess.run(['bash','-c',prefix+revert+'\ncmd_revert'],check=True)
    assert (root/'Machine.pm').read_text() == 'old'
    assert not (root/'module').exists()
print('rollback: legacy refusal, changed-file refusal, verified restore passed')

# Machine transformer must refuse unknown layouts without changing the file.
machine = patcher.split("<< 'PATCHMACHINE'\n", 1)[1].split('\nPATCHMACHINE', 1)[0]
with tempfile.TemporaryDirectory() as tmp:
    fixture = Path(tmp) / 'Machine.pm'
    fixture.write_text('unsupported upstream layout\n')
    code = re.sub(r'^path = .*$', f'path = {str(fixture)!r}', machine, flags=re.M)
    result = subprocess.run(['python3', '-c', code], capture_output=True)
    assert result.returncode != 0
    assert fixture.read_text() == 'unsupported upstream layout\n'

# Execute the actual drive write-protection expression, not a duplicate model.
module = Path('tools/MicroVM.pm').read_text()
readonly = next(line for line in module.splitlines() if '$drive_cmd .= ",readonly=on"' in line)
for drive, expected in [("{ro => 1}", ',readonly=on'), ("{ro => 0}", ''),
                        ("{media => 'cdrom'}", ',readonly=on'), ('{}', '')]:
    result = subprocess.run(['perl', '-e', 'use strict; use warnings; my $drive = '+drive+'; my $drive_cmd = ""; '+readonly+' print $drive_cmd;'], capture_output=True, text=True, check=True)
    assert result.stdout == expected
print('drive write protection: read-only, writable, optical and default passed')
