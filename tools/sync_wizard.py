#!/usr/bin/env python3
"""config-wizard.html 안에 들어 있는 파일 사본을 저장소의 실제 파일로 다시 채웁니다.

Wizard는 (1) 생성하는 단일 설치 파일(.sh)과 (2) 다운로드하는 ZIP 안에 아래 파일들을 넣기 위해
사본을 내장하고 있습니다. 저장소의 파일을 고친 뒤에는 반드시 이 스크립트를 실행하세요.

  python3 tools/sync_wizard.py            # 내장 사본 + SHA256SUMS.txt 갱신
  python3 tools/sync_wizard.py --check    # 갱신이 필요하면 종료코드 1 (CI에서 사용)
  python3 tools/sync_wizard.py --extract-js out.js   # Wizard의 <script>를 파일로 추출(문법 검사용)
"""
import argparse, base64, gzip, hashlib, json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WIZ = ROOT / 'config-wizard.html'

# 생성되는 단일 설치 파일(.sh)에 들어가는 파일: Wizard 내부 이름 -> (저장소 경로, ZIP 내 경로와 동일)
EMBEDDED = {
    'install-elk.sh':             '_internal/core/install-elk.sh',
    'check-elk.sh':               '_internal/core/check-elk.sh',
    'proxysg-log-process.sh':       '_internal/core/proxysg-log-process.sh',
    'proxysg-log-filter.conf':  '_internal/core/proxysg-log-filter.conf',
    'elk-health-monitor.sh':      '_internal/core/elk-health-monitor.sh',
    'elk-ops.sh':                 '_internal/core/elk-ops.sh',
    'elk-patch.sh':               '_internal/core/elk-patch.sh',
    'elk-color.sh':               '_internal/core/elk-color.sh',
    'elk-report.sh':              '_internal/core/elk-report.sh',
    'proxysg-lib.sh':             '_internal/core/proxysg-lib.sh',
    'log-ingest-manager.sh':      '_internal/core/log-ingest-manager.sh',
    'custom-filter.example.conf': '_internal/examples/custom-filter.example.conf',
    'mapping.example.json':       '_internal/examples/mapping.example.json',
}
# 패치 파일/붙여넣기 명령에 쓰는 압축본(gzip+base64): 붙여넣는 분량을 줄이려고 정적 파일 3개만 압축해서 따로 내장한다.
PATCH_GZ = {
    'elk-patch.sh':            '_internal/core/elk-patch.sh',
    'proxysg-lib.sh':          '_internal/core/proxysg-lib.sh',
    'proxysg-log-filter.conf': '_internal/core/proxysg-log-filter.conf',
    'elk-report.sh':           '_internal/core/elk-report.sh',
}
# ZIP에만 들어가는 파일: 저장소 경로 -> 권한(8진수 문자열)
EXTRA = {
    'run-remote-deploy.cmd':                         '644',
    '_internal/tools/run-remote-deploy.ps1':         '644',
    '_internal/tools/open-config-gui.cmd':           '644',
    '_internal/tools/open-config-gui.sh':            '755',
    '_internal/tools/diagnose-logstash-version.sh':  '755',
    '_internal/docs/README.md':                      '644',
    '_internal/docs/CHANGELOG.md':                   '644',
    '_internal/docs/INSTALL_STEP_MAPPING.md':           '644',
    '_internal/docs/VERSION':                        '644',
    '_internal/examples/elk.env':                    '644',
    '_internal/examples/elk.env.example':            '644',
    '_internal/examples/elk-proxysg.env.example':        '644',
}
# SHA256SUMS.txt 에 넣지 않는 것(저장소 관리용 파일)
SUMS_SKIP = {'SHA256SUMS.txt', 'README.md', 'index.html', 'script.js', 'style.css', 'wizard-defaults.js', '.gitignore', '.gitattributes', '.nojekyll'}
SUMS_SKIP_DIRS = {'.git', '.github', 'tools'}


def b64(path):
    return base64.b64encode((ROOT / path).read_bytes()).decode()


def gz_b64(path, existing=None):
    """파일 내용이 그대로면 이미 들어 있는 압축본을 재사용한다. (zlib 버전이 달라도 --check 가 흔들리지 않도록)"""
    raw = (ROOT / path).read_bytes()
    if existing:
        try:
            if gzip.decompress(base64.b64decode(existing)) == raw:
                return existing
        except Exception:
            pass
    return base64.b64encode(gzip.compress(raw, 9, mtime=0)).decode()


def dumps(o):
    return json.dumps(o, ensure_ascii=False, separators=(',', ':'))


def find_obj(text, start_token):
    """'const NAME=' 뒤의 { ... } JSON 객체 범위를 돌려준다."""
    i = text.index(start_token)
    j = text.index('{', i)
    depth = 0; instr = False; esc = False; k = j
    while True:
        c = text[k]
        if instr:
            if esc: esc = False
            elif c == '\\': esc = True
            elif c == '"': instr = False
        else:
            if c == '"': instr = True
            elif c == '{': depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0: break
        k += 1
    return j, k + 1


def build(text):
    # 1) 단일 설치 파일에 내장되는 파일
    j, k = find_obj(text, 'const EMBEDDED_FILES=')
    text = text[:j] + dumps({n: b64(p) for n, p in EMBEDDED.items()}) + text[k:]
    # 1-1) 패치 도구 압축본
    j, k = find_obj(text, 'const PATCH_GZ=')
    try:
        cur = json.loads(text[j:k])
    except Exception:
        cur = {}
    text = text[:j] + dumps({n: gz_b64(p, cur.get(n)) for n, p in PATCH_GZ.items()}) + text[k:]
    # 2) ZIP 경로 매핑
    j, k = find_obj(text, 'const EMBEDDED_PATHS=')
    text = text[:j] + dumps(EMBEDDED) + text[k:]
    # 3) ZIP 전용 추가 파일
    a = text.index('/*PKG-BEGIN*/') + len('/*PKG-BEGIN*/')
    z = text.index('/*PKG-END*/')
    extra = {p: {'b64': b64(p), 'mode': m} for p, m in EXTRA.items()}
    text = text[:a] + 'const PACKAGE_EXTRA=' + dumps(extra) + ';' + text[z:]
    return text


def sums():
    lines = []
    for p in sorted(ROOT.rglob('*')):
        if not p.is_file():
            continue
        rel = p.relative_to(ROOT)
        if rel.parts[0] in SUMS_SKIP_DIRS or (len(rel.parts) == 1 and rel.name in SUMS_SKIP):
            continue
        lines.append(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  ./{rel.as_posix()}")
    return '\n'.join(lines) + '\n'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--extract-js')
    a = ap.parse_args()
    cur = WIZ.read_text(encoding='utf-8')
    if a.extract_js:
        import re
        Path(a.extract_js).write_text(re.search(r'<script>(.*?)</script>', cur, re.S).group(1), encoding='utf-8')
        return 0
    new = build(cur)
    if a.check:
        bad = []
        if new != cur:
            bad.append('config-wizard.html (내장 사본이 저장소 파일과 다릅니다)')
        s = ROOT / 'SHA256SUMS.txt'
        # SHA256SUMS 는 갱신된 Wizard 기준으로 계산해야 하므로 임시로 덮어써서 비교
        if new != cur:
            WIZ.write_text(new, encoding='utf-8', newline='')
        expected = sums()
        if new != cur:
            WIZ.write_text(cur, encoding='utf-8', newline='')
        if not s.exists() or s.read_text(encoding='utf-8') != expected:
            bad.append('SHA256SUMS.txt')
        if bad:
            print('동기화 필요: ' + ', '.join(bad) + '\n  -> python3 tools/sync_wizard.py 를 실행한 뒤 커밋하세요.')
            return 1
        print('OK: Wizard 내장 사본과 SHA256SUMS.txt가 저장소와 일치합니다.')
        return 0
    if new != cur:
        WIZ.write_text(new, encoding='utf-8', newline='')
    (ROOT / 'SHA256SUMS.txt').write_text(sums(), encoding='utf-8', newline='')
    print(f"동기화 완료: 내장 {len(EMBEDDED)}개 + ZIP 추가 {len(EXTRA)}개, SHA256SUMS.txt 갱신")
    return 0


if __name__ == '__main__':
    sys.exit(main())
