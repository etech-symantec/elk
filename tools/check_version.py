#!/usr/bin/env python3
"""버전 표기가 한 곳(_internal/docs/VERSION)과 모두 같은지 검사하고, 한 번에 올립니다.

  python3 tools/check_version.py              # 검사 (어긋나면 종료 코드 1)
  python3 tools/check_version.py --set 2.9.5  # 아래 표기를 모두 2.9.5 로 바꿈 (그 뒤 python3 tools/sync_wizard.py 실행)

검사/변경 대상: Config Wizard(제목·상단 표기·PKG_VER·One-Click 파일 이름·payload 버전), 설치기·elk-patch·elk-report(ELK_AUTO_VERSION, 설치기 맨 위 주석),
Windows 배포 스크립트(새 파일 이름 후보·배너), README의 파일 이름, CHANGELOG 맨 위 제목.
옛 버전 이름의 One-Click 파일 후보(예: ...-v2.9.3.sh)와 CHANGELOG의 지난 항목은 건드리지 않습니다.
"""
import re, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
B64 = re.compile(r'"[A-Za-z0-9+/=]{300,}"')
SEMVER = r'\d+\.\d+\.\d+'

def read(p):
    with open(ROOT / p, encoding='utf-8', newline='') as f: return f.read()
def write(p, t):
    with open(ROOT / p, 'w', encoding='utf-8', newline='') as f: f.write(t)
def version(): return read('_internal/docs/VERSION').strip()

def wizard_text():
    return B64.sub('""', read('config-wizard.html'))

def problems(v):
    P = []
    w = wizard_text()
    def need(cond, msg):
        if not cond: P.append(msg)
    need(f'<title>ELK Configuration Wizard v{v}</title>' in w, f'config-wizard.html: <title> 이 v{v} 가 아닙니다')
    need(f'<div class="brand">ELK Configuration Wizard <small>v{v}</small></div>' in w, f'config-wizard.html: 상단 표기가 v{v} 가 아닙니다')
    need(f"const PKG_VER='{v}'" in w, f"config-wizard.html: PKG_VER 이 {v} 가 아닙니다")
    need(f"ONECLICK_PAYLOAD_VERSION=\\'{v}\\'" in w or f"ONECLICK_PAYLOAD_VERSION='{v}'" in w, f'config-wizard.html: ONECLICK_PAYLOAD_VERSION 이 {v} 가 아닙니다')
    for m in set(re.findall(r'elk-oneclick-install-v(' + SEMVER + r')\.sh', w)):
        need(m == v, f'config-wizard.html: One-Click 파일 이름에 v{m} 가 남아 있습니다 (현재 {v})')
    for m in set(re.findall(r'ELK One-Click Installer v(' + SEMVER + ')', w)):
        need(m == v, f'config-wizard.html: "ELK One-Click Installer v{m}" (현재 {v})')
    for f in ('_internal/core/install-elk.sh', '_internal/core/elk-patch.sh', '_internal/core/elk-report.sh'):
        t = read(f)
        need(f'ELK_AUTO_VERSION="{v}"' in t, f'{f}: ELK_AUTO_VERSION 이 {v} 가 아닙니다')
    hdr = re.search(r'^# ELK Auto Installer v(' + SEMVER + ')', read('_internal/core/install-elk.sh'), re.M)
    need(bool(hdr) and hdr.group(1) == v, f'install-elk.sh: 맨 위 주석이 "# ELK Auto Installer v{hdr.group(1) if hdr else "?"}" 입니다 (v{v} 이어야 함)')
    ps = read('_internal/tools/run-remote-deploy.ps1')
    need(f"'elk-oneclick-install-v{v}.sh'" in ps, f'run-remote-deploy.ps1: 새 파일 이름 후보 elk-oneclick-install-v{v}.sh 가 없습니다')
    need(f"Windows OpenSSH v{v}" in ps, f'run-remote-deploy.ps1: 배너가 v{v} 가 아닙니다')
    need(f'Config Wizard v{v} and save a new SH' in ps, f'run-remote-deploy.ps1: 안내 문구가 v{v} 가 아닙니다')
    r = read('README.md')
    for m in set(re.findall(r'elk-(?:oneclick-install|auto-install|auto-installer)-v(' + SEMVER + r')\.(?:sh|cmd|zip)', r)):
        need(m == v, f'README.md: 파일 이름에 v{m} 가 남아 있습니다 (현재 {v})')
    first = read('_internal/docs/CHANGELOG.md').lstrip().split('\n', 1)[0].strip()
    need(first == f'# v{v}', f'CHANGELOG.md: 맨 위 제목이 "{first}" 입니다 ("# v{v}" 이어야 함)')
    return P

def set_version(new):
    old = version()
    if not re.fullmatch(SEMVER, new): sys.exit('버전 형식은 X.Y.Z 입니다.')
    if new == old: print('이미 같은 버전입니다:', old); return
    # wizard (embedded payloads untouched)
    parts = re.split('(' + B64.pattern + ')', read('config-wizard.html'))
    for i, p in enumerate(parts):
        if B64.fullmatch(p): continue
        p = p.replace(f'<title>ELK Configuration Wizard v{old}</title>', f'<title>ELK Configuration Wizard v{new}</title>')
        p = p.replace(f'<small>v{old}</small>', f'<small>v{new}</small>')
        p = p.replace(f"const PKG_VER='{old}'", f"const PKG_VER='{new}'")
        p = p.replace(f"ONECLICK_PAYLOAD_VERSION=\\'{old}\\'", f"ONECLICK_PAYLOAD_VERSION=\\'{new}\\'").replace(f"ONECLICK_PAYLOAD_VERSION='{old}'", f"ONECLICK_PAYLOAD_VERSION='{new}'")
        p = p.replace(f'elk-oneclick-install-v{old}.sh', f'elk-oneclick-install-v{new}.sh')
        p = p.replace(f'ELK One-Click Installer v{old}', f'ELK One-Click Installer v{new}')
        p = p.replace(f'현재 v{old} 형식', f'현재 v{new} 형식')
        parts[i] = p
    write('config-wizard.html', ''.join(parts))
    for f in ('_internal/core/install-elk.sh', '_internal/core/elk-patch.sh', '_internal/core/elk-report.sh'):
        write(f, read(f).replace(f'ELK_AUTO_VERSION="{old}"', f'ELK_AUTO_VERSION="{new}"'))
    s = re.sub(r'^# ELK Auto Installer v' + SEMVER + r'[^\n]*', f'# ELK Auto Installer v{new}', read('_internal/core/install-elk.sh'), count=1, flags=re.M)
    write('_internal/core/install-elk.sh', s)
    ps = read('_internal/tools/run-remote-deploy.ps1').replace('\r\n', '\n')
    if f"'elk-oneclick-install-v{new}.sh'" not in ps:   # 새 이름 후보를 맨 앞에 추가(옛 이름은 그대로 둠)
        ps = ps.replace(f"    (Join-Path $PackageRoot 'elk-oneclick-install-v{old}.sh'),\n", f"    (Join-Path $PackageRoot 'elk-oneclick-install-v{new}.sh'),\n    (Join-Path $PackageRoot 'elk-oneclick-install-v{old}.sh'),\n", 1)
    ps = ps.replace(f'Config Wizard v{old} and save a new SH', f'Config Wizard v{new} and save a new SH').replace(f'Windows OpenSSH v{old}', f'Windows OpenSSH v{new}')
    write('_internal/tools/run-remote-deploy.ps1', ps.replace('\n', '\r\n'))
    r = re.sub(r'(elk-(?:oneclick-install|auto-install|auto-installer)-v)' + re.escape(old) + r'(\.(?:sh|cmd|zip))', r'\g<1>' + new + r'\g<2>', read('README.md'))
    write('README.md', r)
    c = read('_internal/docs/CHANGELOG.md')
    if not c.lstrip().startswith(f'# v{new}'):
        c = f'# v{new}\n\n- (이번 버전의 변경 내용을 여기에 적으세요)\n\n' + c
        print('CHANGELOG.md 맨 위에 "# v%s" 제목을 추가했습니다. 내용을 채워 주세요.' % new)
    write('_internal/docs/CHANGELOG.md', c)
    write('_internal/docs/VERSION', new + '\n')
    print(f'버전을 {old} → {new} 로 올렸습니다. 이어서 python3 tools/sync_wizard.py 를 실행하세요.')

def main():
    a = sys.argv[1:]
    if a[:1] == ['--set']:
        if len(a) != 2: sys.exit('사용법: --set X.Y.Z')
        set_version(a[1]); return 0
    v = version(); P = problems(v)
    if P:
        print(f'버전 표기가 _internal/docs/VERSION({v})과 다릅니다:')
        for m in P: print('  -', m)
        return 1
    print(f'OK: 모든 버전 표기가 {v} 로 일치합니다.')
    return 0

if __name__ == '__main__':
    sys.exit(main())
