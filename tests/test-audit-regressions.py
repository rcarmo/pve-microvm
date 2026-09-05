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
                       ('{"exitcode":0}', 0), ('not JSON', 1)]:
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
