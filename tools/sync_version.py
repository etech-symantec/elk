#!/usr/bin/env python3
"""Keep the checked-in OneClick release metadata and Wizard bundles in sync.

Run: python3 tools/sync_version.py
Check: python3 tools/sync_version.py --check
Change ONLY _internal/docs/VERSION when preparing the next release.
"""
import argparse
import base64
import gzip
import io
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
VERSION = ROOT / '_internal/docs/VERSION'
BUILD = 'version-auto-sync'


def changed_text(path, transform, check):
    if not path.exists():
        return []
    before = path.read_text(encoding='utf-8')
    after = transform(before)
    if before == after:
        return []
    if not check:
        path.write_text(after, encoding='utf-8')
    return [path.relative_to(ROOT).as_posix()]


def replace_one(text, regex, repl, label):
    result, count = re.subn(regex, repl, text, count=1, flags=re.M)
    if count != 1:
        raise ValueError(f'Expected one {label}, found {count}')
    return result


def sync_version(check=False):
    ver = VERSION.read_text(encoding='utf-8').strip()
    if not re.fullmatch(r'\d+\.\d+\.\d+', ver):
        raise ValueError('VERSION must be MAJOR.MINOR.PATCH, e.g. 2.9.46')
    dirty = []

    for name in ['install-elk.sh', 'elk-patch.sh', 'elk-report.sh']:
        path = ROOT / '_internal/core' / name
        def update(s):
            if name == 'install-elk.sh':
                s = replace_one(s, r'^# ELK Auto Installer v[0-9.]+$', f'# ELK Auto Installer v{ver}', 'installer comment')
            s = replace_one(s, r'^ELK_AUTO_VERSION="[^"]*"$', f'ELK_AUTO_VERSION="{ver}"', name+' version')
            if name == 'elk-report.sh':
                s = replace_one(s, r'^ELK_AUTO_BUILD="\$\{ELK_AUTO_BUILD:-[^}]*\}"$', f'ELK_AUTO_BUILD="${{ELK_AUTO_BUILD:-{BUILD}}}"', 'report build')
            return s
        dirty += changed_text(path,update,check)

    # Canonical release label is metadata; avoid replacing historical changelog entries.
    for name,pat,repl in [
        ('_internal/docs/README.md', r'^# ELK OneClick v[0-9.]+$', f'# ELK OneClick v{ver}'),
        ('_internal/docs/CHANGELOG.md',r'^# v[0-9.]+$',f'# v{ver}')
    ]:
        dirty += changed_text(ROOT/name, lambda s,pat=pat,repl=repl:replace_one(s,pat,repl,name),check)

    # The PowerShell runner never hardcodes a release. It always reads the generated SH marker.
    ps = ROOT / '_internal/tools/run-remote-deploy.ps1'
    if ps.exists():
        pscontent = ps.read_text(encoding='utf-8')
        if not ('Get-ShellMeta $Script' in pscontent and "'ONECLICK_PAYLOAD_VERSION'" in pscontent):
            raise ValueError('PowerShell runner must detect version from SH metadata')

    dirty += changed_text(ROOT/'version.json',lambda _:json.dumps({'version':ver,'build':BUILD},ensure_ascii=False,indent=2)+'\n',check)

    wizard = ROOT / 'config-wizard.html'
    def sync_wizard(s):
        s = replace_one(s, r"^const PKG_VER='[^']*';\s*\nconst WIZARD_BUILD='[^']*';",f"const PKG_VER='{ver}';\nconst WIZARD_BUILD='{BUILD}';",'wizard version')
        s = replace_one(s,r'(?<=L\.push\(")ONECLICK_PAYLOAD_VERSION=\x27[0-9.]+\x27(?="\);)', f"ONECLICK_PAYLOAD_VERSION='{ver}'",'payload marker')
        for marker in ['const EMBEDDED_FILES=','const PATCH_GZ=','const PACKAGE_EXTRA=']:
            i=s.find(marker)
            if i<0:continue
            st=i+len(marker)
            obj,n=json.JSONDecoder().raw_decode(s[st:])
            if marker=='const EMBEDDED_FILES=':
                for key in list(obj):
                    f=ROOT/'_internal/core'/key
                    if f.is_file():
                        obj[key]=base64.b64encode(f.read_bytes()).decode('ascii')
            elif marker=='const PATCH_GZ=':
                for key in list(obj):
                    f=ROOT/'_internal/core'/key
                    if f.is_file():
                        buf=io.BytesIO()
                        with gzip.GzipFile(fileobj=buf,mode='wb',mtime=0) as h:h.write(f.read_bytes())
                        obj[key]=base64.b64encode(buf.getvalue()).decode('ascii')
            else:
                for key,file in [('version.json','version.json'),('_internal/docs/VERSION','_internal/docs/VERSION'),('_internal/docs/README.md','_internal/docs/README.md'),('_internal/docs/CHANGELOG.md','_internal/docs/CHANGELOG.md'),('_internal/tools/run-remote-deploy.ps1','_internal/tools/run-remote-deploy.ps1')]:
                    if key in obj and (ROOT/file).is_file():
                        raw=(ROOT/file).read_bytes()
                        if isinstance(obj[key],dict):obj[key]['b64']=base64.b64encode(raw).decode('ascii')
                        elif isinstance(obj[key],str):obj[key]=base64.b64encode(raw).decode('ascii')
            s=s[:st]+json.dumps(obj,ensure_ascii=False,separators=(',',':'))+s[st+n:]
        return s
    dirty += changed_text(wizard,sync_wizard,check)
    print(f'OneClick canonical VERSION: {ver}; build: {BUILD}')
    if dirty:
        print(('OUT OF SYNC:' if check else 'SYNCED:')+' '+', '.join(dirty))
    else:
        print('All versions already synchronized')
    return bool(dirty)

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--check',action='store_true',help='Exit 1 when generated metadata needs refresh')
    args=parser.parse_args()
    try:
        dirty=sync_version(check=args.check)
    except (ValueError,OSError,KeyError) as exc:
        print('ERROR:',exc,file=sys.stderr)
        raise SystemExit(2)
    raise SystemExit(1 if args.check and dirty else 0)
