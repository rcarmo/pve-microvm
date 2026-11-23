#!/usr/bin/env python3
"""Run actual storage/import helpers against an isolated PVE mock."""
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
if not os.environ.get('PVE_MICROVM_RUN_DIR'):
    raise SystemExit(subprocess.run(['bash', str(ROOT / 'tools/pve-microvm-env.sh'),
                                    '--exec', 'tests', sys.executable, *sys.argv]).returncode)
os.chdir(ROOT)
script = (ROOT / 'tools/pve-microvm-template').read_text()
helpers = script[script.index('validate_template_storage() {'):script.index('# Allow the network/package policy helpers')]
assert script.index('case "${IMAGE,,}" in') < script.index('log "Removing existing template')
assert script.index('case "${IMAGE,,}" in') < script.index('log "Creating microvm template from')
assert script.count('$(qm importdisk ') == 1
assert script.count('    import_template_disk ') == 4
assert 'import_template_disk "$QCOW2" --format qcow2' in script
assert '|| echo "$STORAGE:vm-' not in script

with tempfile.TemporaryDirectory() as tmp:
    work = Path(tmp)
    (work / 'PVE').mkdir()
    (work / 'PVE/Storage.pm').write_text(r'''package PVE::Storage;
use strict; use warnings;
sub config { return {}; }
sub storage_check_enabled {
 my ($cfg,$sid)=@_;
 die "missing store\n" if $sid eq 'missing';
 die "storage is disabled\n" if $sid eq 'disabled';
 die "unavailable on node\n" if $sid eq 'other-node';
 return {content=>{images=>($sid ne 'backup')}};
}
sub storage_info { my ($cfg,$content,$sid)=@_;return {$sid=>{enabled=>1,active=>($sid ne 'inactive')}}; }
sub parse_volume_id { return split /:/,$_[0],2; }
sub parse_volname {
 my ($cfg,$volid)=@_;
 my ($owner)=$volid=~/vm-(\d+)/;
 return ('images','root',$owner);
}
sub volume_size_info { return $ENV{MOCK_EMPTY} ? 0 : 1048576; }
1;
''')
    env = dict(os.environ, PERL5LIB=str(work))
    prefix = r'''
set -euo pipefail
STORAGE=${MOCK_STORAGE:-pool}
TEMPLATE_VMID=9000
PROG=test
log() { :; }
die() { echo "$*" >&2; exit 1; }
qm() {
 printf '%s\n' "$*" >> "$MOCK_CALLS"
 case "$1" in
 config)
  if [ -f "$MOCK_STATE" ]; then
   case "$MOCK_MODE" in
    absent) echo 'name: fixture';;
    ambiguous) printf 'unused0: pool:vm-9000-disk-1\nunused1: pool:vm-9000-disk-2\n';;
    other-store) echo 'unused0: other:vm-9000-disk-0';;
    other-vm) echo 'unused0: pool:vm-9001-disk-0';;
    changed) echo 'unused4: pool:vm-9000-disk-8';;
    attached)
      if [ -f "$MOCK_ATTACHED" ]; then echo 'scsi0: pool:vm-9000-disk-7,size=1G';
      else echo 'unused4: pool:vm-9000-disk-7'; fi;;
    *) printf 'unused2: pool:vm-9000-disk-6\nunused4: pool:vm-9000-disk-7\n';;
   esac
  else
   if [ "$MOCK_MODE" = changed ]; then echo 'unused4: pool:vm-9000-disk-6';
   elif [ "$MOCK_MODE" = attached ]; then echo 'name: fixture';
   else echo 'unused2: pool:vm-9000-disk-6'; fi
  fi;;
 importdisk)
  [ "$MOCK_MODE" != failed ] || { echo 'real import failure: storage disappeared' >&2; return 42; }
  touch "$MOCK_STATE"
  echo 'unrecognised/localised progress output';;
 set) touch "$MOCK_ATTACHED";;
 *) return 99;;
 esac
}
'''
    def run(storage='pool', mode='ok', command='import_template_disk fixture.img --format qcow2', empty=False):
        calls, state, attached = (work / n for n in ('calls', 'state', 'attached'))
        for p in (calls, state, attached):
            p.unlink(missing_ok=True)
        e = dict(env, MOCK_STORAGE=storage, MOCK_MODE=mode, MOCK_CALLS=str(calls),
                 MOCK_STATE=str(state), MOCK_ATTACHED=str(attached))
        if empty:
            e['MOCK_EMPTY'] = '1'
        result = subprocess.run(['bash', '-c', prefix+helpers+'\n'+command],
                                env=e, capture_output=True, text=True)
        return result, calls.read_text() if calls.exists() else ''
    for storage in ('missing','disabled','other-node','backup','inactive'):
        result, calls = run(storage=storage)
        assert result.returncode != 0 and not calls, (storage, result.stderr, calls)
    result, calls = run()
    assert result.returncode == 0, result.stderr
    assert 'importdisk 9000 fixture.img pool --format qcow2' in calls
    for mode in ('failed','absent','ambiguous','other-store','other-vm','changed'):
        result, calls = run(mode=mode)
        assert result.returncode != 0 and 'set ' not in calls, (mode,result.stderr)
        if mode == 'failed':
            assert 'real import failure: storage disappeared' in result.stderr
    result, _ = run(empty=True)
    assert result.returncode != 0 and 'missing or empty' in result.stderr
    result, calls = run(mode='attached',command='import_template_disk fixture.img; attach_template_disk scsi0; test "$IMPORT_VOLID" = pool:vm-9000-disk-7')
    assert result.returncode == 0 and 'set 9000 --scsi0 pool:vm-9000-disk-7' in calls, result.stderr
    result, _ = run(command='import_template_disk fixture.img; attach_template_disk scsi0')
    assert result.returncode != 0 and 'not attached as scsi0' in result.stderr
print('Template storage preflight, import diagnostics, config-derived volume, ownership/backing and attachment checks passed')
