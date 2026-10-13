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
BUILD = 'version-auto-sync'  # Report fallback only; Wizard stamp owns version.json build


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

    # The top-level README is release-facing documentation. Normalize every
    # versioned install artifact reference, including older examples, while
    # leaving unrelated historical change descriptions intact.
    def update_root_readme(s):
        s = re.sub(r'(elk-(?:oneclick-install|auto-install|auto-installer)-v)\d+\.\d+\.\d+(\.(?:sh|cmd|zip))',
                   lambda m: m.group(1)+ver+m.group(2), s)
        # Version in the report section heading / illustrative build caption.
        s = re.sub(r'^## v\d+\.\d+\.\d+ · HTML 점검 리포트',
                   f'## HTML 점검 리포트 (현재 v{ver})',s,flags=re.M)
        s = re.sub(r'`v\d+\.\d+\.\d+ · 빌드 [a-z]+(?:-[a-z]+){3}`',
                   f'`v{ver} · 빌드 (Wizard 하단 자동 생성값)`',s)
        return s
    dirty += changed_text(ROOT/'README.md',update_root_readme,check)

    # The PowerShell runner never hardcodes a release. It always reads the generated SH marker.
    ps = ROOT / '_internal/tools/run-remote-deploy.ps1'
    if ps.exists():
        pscontent = ps.read_text(encoding='utf-8')
        if not ('Get-ShellMeta $Script' in pscontent and "'ONECLICK_PAYLOAD_VERSION'" in pscontent):
            raise ValueError('PowerShell runner must detect version from SH metadata')

    # version.json uses the SAME stamp as the Wizard. Never use a fixed build label.
    # Run sync_wizard.py after this tool, then run this tool a second time: the
    # first wizard synchronization may change the content-derived stamp.
    wizard_text = (ROOT/'config-wizard.html').read_text(encoding='utf-8')
    m_build = re.search(r"const WIZARD_BUILD='([a-z]+(?:-[a-z]+){3}|[0-9a-f]{8})'", wizard_text)
    wizard_build = m_build.group(1) if m_build else 'BUILDSTAMP'
    dirty += changed_text(ROOT/'version.json',lambda _:json.dumps({'version':ver,'build':wizard_build},ensure_ascii=False,indent=2)+'\n',check)

    wizard = ROOT / 'config-wizard.html'
    def sync_wizard(s):
        s = replace_one(s, r"^const PKG_VER='[^']*';", f"const PKG_VER='{ver}';", 'wizard version')
        # sync_wizard.py owns the content-based build stamp. Keep a valid stamp
        # unchanged; only normalize a legacy arbitrary build name once.
        s = re.sub(r"(const WIZARD_BUILD=')[^']*(';)", lambda m: m.group(0) if re.fullmatch(r'[0-9a-f]{8}|[a-z]+(?:-[a-z]+){3}|BUILDSTAMP', m.group(0).split("'")[1]) else m.group(1)+'BUILDSTAMP'+m.group(2), s, count=1)
        s = replace_one(s,r'(?<=L\.push\(")ONECLICK_PAYLOAD_VERSION=\x27[0-9.]+\x27(?="\);)', f"ONECLICK_PAYLOAD_VERSION='{ver}'",'payload marker')
        # Release-facing Wizard labels and generated command examples. Only touch
        # readable markup/JS, not the large base64-encoded bundled files.
        s = replace_one(s, r'<title>ELK Configuration Wizard v[0-9.]+</title>',
                        f'<title>ELK Configuration Wizard v{ver}</title>', 'wizard title')
        s = replace_one(s, r'<div class="brand">ELK Configuration Wizard <small>v[0-9.]+</small></div>',
                        f'<div class="brand">ELK Configuration Wizard <small>v{ver}</small></div>', 'wizard header')
        s = re.sub(r'elk-oneclick-install-v[0-9]+\.[0-9]+\.[0-9]+\.sh',
                   f'elk-oneclick-install-v{ver}.sh', s)
        s = re.sub(r'ELK One-Click Installer v[0-9]+\.[0-9]+\.[0-9]+',
                   f'ELK One-Click Installer v{ver}', s)

        # Bundles are exclusively generated by tools/sync_wizard.py.
        return s
    dirty += changed_text(wizard,sync_wizard,check)
    print(f'OneClick canonical VERSION: {ver}; Wizard build: {wizard_build}')
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
