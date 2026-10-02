#!/usr/bin/env python3
"""wizard-defaults.js (관리자용 기본값 파일)를 점검하거나, Wizard에 새로 생긴 항목만 더합니다.

  python3 tools/gen_defaults.py             # 기존 파일은 한 글자도 바꾸지 않고, 파일에 없는 새 항목만 끝부분에 추가
  python3 tools/gen_defaults.py --check     # 문법·항목 이름·true/false·선택 값이 올바른지 점검 (CI에서 사용)
  python3 tools/gen_defaults.py --rewrite   # (주의) 파일 전체를 다시 만듭니다. 값은 유지하지만 줄 배치/주석은 새로 정렬됨
  python3 tools/gen_defaults.py --file X.js # 다른 경로의 파일을 대상으로 실행

wizard-defaults.js 는 관리자가 직접 편집하는 파일이며, 그 파일 자체가 기준입니다.
(Wizard의 내장 기본값과 다르게 적은 값이 있어도 그대로 유지됩니다.)
"""
import argparse, json, re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WIZ = ROOT / 'config-wizard.html'
OUT = ROOT / 'wizard-defaults.js'
DEPLOY_KEYS = {'host': 's', 'user': 's', 'port': 'n', 'remoteDir': 'p', 'autoInstall': 'b', 'removeAfter': 'b', 'sudoSame': 'b'}


def find_obj(text, token):
    i = text.index(token); j = text.index('{', i)
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


def load_wizard():
    w = WIZ.read_text(encoding='utf-8')
    sc = re.search(r'<script>(.*?)</script>', w, re.S).group(1)
    a, b = find_obj(sc, 'const DATA=')
    D = json.loads(sc[a:b])
    # 빠른 설정 초기값(initialPreset)과 배포 기본값(reset) — 파일이 없을 때의 내장 동작
    m = re.search(r"function initialPreset\(\)\{reset\(\);(?:for\(const k of Object\.keys\(FILE_EDITS\)\)delete FILE_EDITS\[k\];)?(?:if\(typeof PATCH_MANUAL!=='undefined'&&PATCH_MANUAL\)\{[^}]*\})?Object\.assign\(values,\{(.*?)\}\);", sc, re.S)
    preset = dict(re.findall(r"([A-Z0-9_]+):'([^']*)'", m.group(1)))
    r = re.search(r"deployValues=\{host:'([^']*)',user:'([^']*)',password:'',sudoSame:(true|false),sudoPassword:'',port:'([^']*)',remoteDir:'([^']*)',autoInstall:(true|false),removeAfter:(true|false)\}", sc)
    deploy = {'host': r.group(1), 'user': r.group(2), 'port': r.group(4), 'remoteDir': r.group(5),
              'autoInstall': r.group(6) == 'true', 'removeAfter': r.group(7) == 'true', 'sudoSame': r.group(3) == 'true'}
    return D, preset, deploy


def read_existing():
    """기존 wizard-defaults.js 를 node 로 평가해 {values, deploy} 를 돌려준다. (없거나 깨졌으면 None)"""
    if not OUT.exists():
        return None
    js = "global.window={};require(%s);process.stdout.write(JSON.stringify(window.ELK_DEFAULTS))" % json.dumps(str(OUT))
    p = subprocess.run(['node', '-e', js], capture_output=True, text=True)
    if p.returncode != 0:
        return {'_error': (p.stderr.strip().splitlines() or ['실행 오류'])[-1]}
    return json.loads(p.stdout)


def is_bool(v):
    return str(v['default']).lower() in ('true', 'false')


def fmt(v, val):
    if is_bool(v):
        return 'true' if str(val).lower() == 'true' else 'false'
    return json.dumps(str(val), ensure_ascii=False)


def hint(v):
    if is_bool(v): return 'true | false'
    if v.get('select'): return ' | '.join(map(str, v['select']))
    return ''


HEADER = '''/* =====================================================================
 *  ELK Config Wizard - 기본값 파일 (관리자용)
 *
 *  이 파일에서 Config Wizard를 처음 열었을 때 입력칸에 채워지는 "초기값"을 정합니다.
 *  고친 뒤 저장(커밋)하고 Wizard를 새로고침하면 바로 반영됩니다. (별도 빌드/명령 필요 없음)
 *
 *  편집 방법
 *   - 값은 따옴표 안의 글자만 고칩니다.        예)  LOGSTASH_PIPELINE_FILE: "/etc/logstash/conf.d/20-proxy.conf",
 *   - true / false 항목은 따옴표 없이 true 또는 false 로 씁니다.
 *   - 줄 끝의 쉼표(,)와 따옴표("")는 지우지 마세요. 값 안에 " 나 \\ 가 필요하면 \\" , \\\\ 로 씁니다.
 *   - 줄 끝의 // 뒤는 설명(주석)이라 지워도 됩니다. 항목을 지우면 Wizard 내장 기본값이 쓰입니다.
 *   - 각 묶음 제목의 "고급 설정 N단계"는 Wizard 왼쪽 메뉴(고급 설정)의 번호입니다.
 *
 *  제한 사항
 *   - 비밀번호·암호화 키 항목은 여기서 지정할 수 없습니다. (저장소에 그대로 노출되기 때문)
 *   - 잘못된 항목 이름, true/false가 아닌 값, 선택 목록에 없는 값은 무시되고
 *     Wizard 화면 위쪽에 경고가 표시됩니다.
 *   - 이 값은 Wizard가 채워 주는 초기값입니다. 설치기(install-elk.sh)의 ": ${KEY:=값}" 줄은
 *     elk.env에 값이 없을 때만 쓰는 예비값이며 이 파일과 별개입니다.
 * ===================================================================== */
'''


def build(D, preset, deploy, existing):
    V = {v['key']: v for v in D['vars']}
    old_vals = (existing or {}).get('values', {}) if existing and '_error' not in existing else {}
    old_dep = (existing or {}).get('deploy', {}) if existing and '_error' not in existing else {}
    lines = [HEADER, 'window.ELK_DEFAULTS = {', '  values: {']
    placed = set()
    groups = []
    for n, s in enumerate(D['advanced'], 1):
        if s.get('kind') or not s['vars']:
            continue
        title = re.sub(r'^\d+[A-Z]?\.\s*', '', s['title'])
        groups.append((f'고급 설정 {n}단계 · {title}', s['vars']))
    rest = [k for k in V if not any(k in g[1] for g in groups)]
    if rest:
        groups.append(('기타 (설치 진행 표시 · APT 재시도)', rest))
    secrets = []
    for title, keys in groups:
        body = []
        for k in keys:
            v = V[k]
            if k in placed: continue
            placed.add(k)
            if v.get('secret'):
                secrets.append(k); continue
            init = preset.get(k, v['default'])            # 지금 Wizard가 처음 보여 주는 값
            val = old_vals.get(k, init)                   # 관리자가 이미 고쳤다면 그 값을 유지
            if isinstance(val, bool): val = 'true' if val else 'false'
            note = v.get('label', '')
            h = hint(v)
            ln = f'    {k}: {fmt(v, val)},'; body.append(ln + ' ' * max(2, 62 - len(ln)) + f'// {note}' + (f'  [{h}]' if h else ''))
        if body:
            lines += ['', f'    // ───── {title} ─────'] + body
    lines += ['', '    // (비밀번호·암호화 키 항목은 이 파일에서 지정할 수 없습니다: ' + ', '.join(secrets) + ')', '  },', '',
              '  // Ubuntu 자동 전송/설치 대상의 초기값 (고급 설정 21단계 / 빠른 설정 10단계). 비밀번호는 지정할 수 없습니다.',
              '  deploy: {']
    labels = {'host': 'Ubuntu 서버 IP / 호스트', 'user': 'SSH 로그인 계정', 'port': 'SSH 포트', 'remoteDir': '원격 전송 폴더',
              'autoInstall': '전송 후 자동 설치 [true | false]', 'removeAfter': '성공 후 원격 설치파일 삭제 [true | false]',
              'sudoSame': 'sudo 비밀번호 = SSH 비밀번호 [true | false]'}
    for k in DEPLOY_KEYS:
        val = old_dep.get(k, deploy[k])
        s = ('true' if val else 'false') if isinstance(val, bool) else json.dumps(str(val), ensure_ascii=False)
        ln = f'    {k}: {s},'; lines.append(ln + ' ' * max(2, 62 - len(ln)) + f'// {labels[k]}')
    lines += ['  }', '};', '']
    return '\n'.join(lines), placed, [k for k in old_vals if k not in V]


def check(D):
    V = {v['key']: v for v in D['vars']}
    ex = read_existing()
    if ex is None:
        print('wizard-defaults.js 가 없습니다. (없어도 Wizard는 내장 기본값으로 동작합니다)'); return 0
    if '_error' in ex:
        print('wizard-defaults.js 문법 오류:', ex['_error']); return 1
    bad = []
    for k, raw in ex.get('values', {}).items():
        v = V.get(k)
        if not v: bad.append(f'{k}: 알 수 없는 항목'); continue
        if v.get('secret'): bad.append(f'{k}: 비밀번호·키 항목은 지정할 수 없음'); continue
        s = str(raw).lower() if isinstance(raw, bool) else str(raw)
        if is_bool(v) and s.strip().lower() not in ('true', 'false'): bad.append(f'{k}: true/false만 가능 (값: {raw})'); continue
        if v.get('select') and (s.strip().lower() if is_bool(v) else s) not in map(str, v['select']): bad.append(f'{k}: 허용 값 {v["select"]} 중 하나여야 함 (값: {raw})')
    for k, raw in ex.get('deploy', {}).items():
        t = DEPLOY_KEYS.get(k)
        if not t: bad.append(f'deploy.{k}: 알 수 없는 항목'); continue
        if t == 'b' and not isinstance(raw, bool): bad.append(f'deploy.{k}: true/false만 가능')
        if t == 'n' and not (str(raw).isdigit() and 1 <= int(raw) <= 65535): bad.append(f'deploy.{k}: 1~65535 포트')
        if t == 'p' and (not str(raw).startswith('/') or "'" in str(raw)): bad.append(f'deploy.{k}: /로 시작하는 절대경로(작은따옴표 불가)')
    extra = set(ex) - {'values', 'deploy', 'version'}
    bad += [f'{k}: 알 수 없는 최상위 항목' for k in sorted(extra)]
    if bad:
        print('wizard-defaults.js 점검 실패:\n  - ' + '\n  - '.join(bad)); return 1
    print(f"OK: wizard-defaults.js 문법과 값이 올바릅니다. (항목 {len(ex.get('values', {}))}개, deploy {len(ex.get('deploy', {}))}개)")
    return 0


def add_missing(D, preset):
    """기존 파일은 그대로 두고, values 블록에 없는 항목만 비밀번호 안내 주석 바로 앞에 추가한다."""
    text = OUT.read_text(encoding='utf-8')
    present = set(re.findall(r'^\s{4}([A-Z][A-Z0-9_]*):', text, re.M))
    known = {v['key'] for v in D['vars']}
    missing = [v for v in D['vars'] if not v.get('secret') and v['key'] not in present]
    stale = sorted(k for k in present if k not in known)
    if stale:
        print('참고: Wizard에 더 이상 없는 항목이 파일에 남아 있습니다(그대로 둠): ' + ', '.join(stale))
    if not missing:
        print('변경 없음: 파일에 없는 새 항목이 없습니다. (파일은 수정하지 않았습니다)')
        return 0
    marker = re.search(r'^    // \(비밀번호·암호화 키 항목은', text, re.M)
    if not marker:
        print('안내 주석 위치를 찾지 못해 파일을 수정하지 않았습니다. 아래 항목을 values 블록 끝에 직접 추가하세요: ' + ', '.join(v['key'] for v in missing))
        return 1
    body = ['', '    // ───── 새로 추가된 항목 (tools/gen_defaults.py) ─────']
    for v in missing:
        k = v['key']
        ln = f'    {k}: {fmt(v, preset.get(k, v["default"]))},'
        h = hint(v)
        body.append(ln + ' ' * max(2, 62 - len(ln)) + f'// {v.get("label", "")}' + (f'  [{h}]' if h else ''))
    OUT.write_text(text[:marker.start()] + '\n'.join(body) + '\n\n' + text[marker.start():], encoding='utf-8', newline='')
    print(f'새 항목 {len(missing)}개를 파일 끝부분에 추가했습니다: ' + ', '.join(v['key'] for v in missing))
    return 0


def main():
    global OUT
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true'); ap.add_argument('--rewrite', action='store_true'); ap.add_argument('--file')
    a = ap.parse_args()
    if a.file:
        OUT = Path(a.file).resolve()
    D, preset, deploy = load_wizard()
    if a.check:
        return check(D)
    if not a.rewrite and OUT.exists():
        ex = read_existing()
        if ex and '_error' in ex:
            print('기존 wizard-defaults.js 에 문법 오류가 있어 수정하지 않았습니다:', ex['_error']); return 1
        return add_missing(D, preset)
    ex = read_existing()
    if ex and '_error' in ex:
        print('기존 wizard-defaults.js 에 문법 오류가 있어 덮어쓰지 않았습니다:', ex['_error']); return 1
    text, placed, dropped = build(D, preset, deploy, ex)
    OUT.write_text(text, encoding='utf-8', newline='')
    print(f"wizard-defaults.js 작성 완료 (항목 {len(placed) - 7}개 + deploy {len(DEPLOY_KEYS)}개)" + (f" · 더 이상 없는 항목 제거: {', '.join(dropped)}" if dropped else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main())
