# ELK

ELK 도구 모음 페이지입니다. `https://etech-symantec.github.io/elk/` 에서 세 가지 기능을 같은 화면 안에서 전환해 사용합니다.

| 기능 | 설명 |
|---|---|
| 📊 ELK 리소스 계산기 | 일일 로그량과 보관 기간으로 CPU / MEM / Disk 사양 산정 |
| ⚙️ Logstash 설정파일 만들기 | 공통 설정과 Log Type을 입력해 `logstash.conf` 생성 |
| 🚀 ELK 자동 구성 | Ubuntu 서버에 ELK를 자동 설치하는 **Config Wizard** — 설치 파일(.sh)과 전체 패키지를 ZIP으로 다운로드 |

`https://etech-symantec.github.io/elk/#wizard` 로 접속하면 ELK 자동 구성 화면이 바로 열립니다. (`#calc`, `#conf` 도 동일)
Config Wizard 단독 주소는 `https://etech-symantec.github.io/elk/config-wizard.html` 입니다.

## ELK 자동 구성 사용 방법

1. **ELK 자동 구성**을 엽니다.
2. 1~9단계에서 설정을 확인하고, 10단계(자동 전송 및 설치)에 Ubuntu 서버 주소와 SSH 계정을 입력합니다.
3. 11단계(검증 및 완료)에서 오류가 없는지 확인한 뒤 아래 중 하나를 받습니다.
   - **자동 실행 파일 (.cmd)** — 더블클릭하면 임시 폴더에 자동으로 풀고 `run-remote-deploy`까지 실행합니다. 끝나면(또는 오류가 나면) 결과가 노란 글씨로 표시되고 창이 유지되며, 임시 폴더는 자동으로 삭제됩니다. (`ELK_KEEP_TEMP=1`을 설정하면 유지, 다시 연결하려면 `elk-auto-install-v2.9.3.cmd --status`)
   - **ZIP 전체 다운로드** — 직접 풀어서 `run-remote-deploy.cmd`를 실행합니다. (Ubuntu에서 직접 설치: `sudo bash elk-oneclick-install-v2.9.3.sh --local-install`)

> Wizard는 브라우저 안에서만 동작합니다. 입력한 값(비밀번호 포함)은 서버로 전송되지 않고, 다운로드한 ZIP에만 들어갑니다.

## 저장소 구성

```
index.html, script.js, style.css   ELK 도구 모음 페이지 (리소스 계산기 / Logstash 설정 / ELK 자동 구성)
config-wizard.html                 Config Wizard (설치기·스크립트 사본이 내장되어 있음)
wizard-defaults.js                 Wizard 초기값 파일 (관리자가 직접 편집)
run-remote-deploy.cmd              Windows 원격 배포 실행 파일
_internal/core/                    설치기(install-elk.sh)와 보조 스크립트
_internal/tools/                   원격 배포 도우미(run-remote-deploy.ps1) 등
_internal/docs/                    문서, CHANGELOG
_internal/examples/                예제 설정 파일
tools/sync_wizard.py               Wizard 내장 사본 동기화 스크립트 (개발용, ZIP에는 포함되지 않음)
tools/gen_defaults.py               wizard-defaults.js 생성/점검 스크립트 (개발용)
SHA256SUMS.txt                     패키지 파일 체크섬
```

## 스크립트 · Logstash 설정 수정 (사용자)

빠른 설정 **7단계(로그 처리 스크립트)** 아래 "이 단계에서 사용되는 스크립트 · Logstash 설정"에서 설치에 쓰이는 파일을 직접 보고 고칠 수 있습니다.

| 파일 | 역할 |
|---|---|
| `proxysg-log-process.sh` | FTP 수신 폴더의 `*.log.gz`를 백업·처리 폴더로 복사·검증하고 원본을 지우는 스크립트 (cron으로 실행) |
| `proxysg-log-filter.conf` | ProxySG 로그 한 줄을 필드로 나누는 Logstash 필터 (파이프라인에 포함) |
| `10-main.conf` (파이프라인) | 입력 → 필터 → 출력 전체. 기본은 설정값으로 자동 생성되며, 고치면 그 내용이 그대로 설치됨 |

- **MAIN / SSL(사용 시 Cloud) 로그 포맷**은 7단계 필수 항목입니다. ProxySG 로그 맨 위 `#Fields:` 줄의 필드 순서를 그대로 넣으면, 설치기가 로그 종류(MAIN·SSL·Cloud)마다 별도의 Logstash csv 컬럼 목록을 만들어 필터에 반영합니다. (필드 이름은 소문자와 `_`로 바뀜: `cs(Referer)` → `cs_referer`, `date` → `log_date`)
- **파일 처리 실행 시간**은 서버의 `/etc/cron.d/elk-proxysg-log-process`에 등록됩니다. `crontab -l`에는 나오지 않으며(시스템 cron 파일), 테스트용 `* * * * *`로 설치한 뒤 서버에서 `sudo vi /etc/cron.d/elk-proxysg-log-process`로 맨 앞 5칸을 `0 3 * * *` 등으로 바꾸면 됩니다.
- **Cloud 로그**는 기본이 **사용 안 함**입니다. 7단계의 "처리할 로그 종류"에서 Cloud를 **사용**으로 바꾸면 Cloud 전용 수신·백업·처리 폴더, Logstash 입력(type `cloud`), 필터, 인덱스(`proxy-cloud-날짜`), Data View, Index Template 패턴이 MAIN·SSL과 같은 방식으로 추가됩니다. 사용 안 함이면 Cloud 열은 회색 "비활성"으로 표시되고 설치에는 아무것도 반영되지 않습니다. Cloud 로그 포맷의 기본값은 75개 필드(`cs-method cs-user-domain …`)이며, 실제 Cloud 로그의 `#Fields` 순서와 다르면 7단계에서 수정하세요.
- 파일 카드의 중괄호 검사는 주석(`#`)·문자열·정규식(`=~ /…/`) 안의 괄호는 세지 않으며, 짝이 맞지 않으면 몇 번째 줄인지 알려 주는 **경고**만 표시합니다. (설치는 막지 않고, 설치 중 Logstash `-t` 검사가 최종 확인합니다)
- 고친 내용은 생성되는 설치 파일(.sh)과 ZIP에 그대로 들어갑니다. **기본값으로 되돌리기** / **설정값으로 다시 생성**으로 복구합니다.
- 수정한 파이프라인은 폴더·인덱스 이름 등 다른 설정을 바꿔도 자동 반영되지 않습니다. (다시 생성하면 반영)
- 설치 중 스크립트는 `bash -n`, Logstash 설정은 `logstash -t`로 검사하며, 오류가 있으면 설치가 중단됩니다.
- "기존 SH 불러오기"를 하면 수정한 파일도 함께 복원됩니다.

## 설치 후 일부 값만 수정 (패치)

이미 설치된 서버에서 **전체 재설치 없이 바꾼 값만** 적용합니다. 마지막 단계(11단계) 아래의 "설치 후 일부 값만 수정 (패치)"에서 사용합니다.

1. 위쪽 **기존 입력값 불러오기**에서 설치에 썼던 `sh 파일`(또는 `elk.env`)을 불러옵니다. → 이 값이 "기준값"이 됩니다.
2. 바꾸고 싶은 값만 수정합니다. 기준값과 달라진 항목이 패치 목록에 **자동으로 선택**됩니다. (직접 체크/해제도 가능)
3. **패치 파일(.sh) 만들기**를 눌러 `elk-patch-날짜-시간.sh`를 받아 서버로 복사합니다. (`scp elk-patch-*.sh 계정@서버:~/`)
4. 서버에서 `sudo bash elk-patch-*.sh` — 변경 내용을 보여 준 뒤 `y`를 입력하면 적용됩니다. (`--dry-run`: 미리보기만, `--yes`: 확인 생략)

| 바꾸는 값 | 실제로 하는 일 |
|---|---|
| 로그 처리 스크립트 실행 시간(cron) | `/etc/cron.d/elk-proxysg-log-process`의 실행 시간만 교체 |
| 인덱스 보존기간(ILM) | 기존 ILM 정책의 삭제 단계만 수정 (hot/warm 단계는 그대로) |
| 로그 포맷 · 파이프라인 관련 값 | 파이프라인을 다시 만들고 `logstash -t`로 검사한 뒤 Logstash 재시작. **검사 실패 시 파이프라인과 elk.env를 자동 복구** |
| Cloud 로그 처리 켜기/끄기 | Cloud 폴더 + 파이프라인 + Index Template 패턴 + Data View |
| 인덱스 Prefix · Data View 이름 | 파이프라인 + Index Template 패턴 + Data View |
| 수신·백업 폴더 | 폴더 생성/권한 (스크립트는 다음 실행부터 새 경로 사용) |

- 바꾸기 전 `elk.env`와 파이프라인은 `/var/backups/elk-auto/patch-날짜-시간/`에 백업됩니다. 되돌리려면 그 안의 `elk.env`를 `/etc/elk-auto/elk.env`로 복사하세요.
- **패치로 바꿀 수 없는 값**(포트, 계정·비밀번호, Heap, 인증서, 방화벽 등)은 도구가 거절하며 아무것도 바꾸지 않습니다. 이런 값은 전체 설치 파일로 다시 설치하세요.
- Elasticsearch/Kibana는 재시작하지 않습니다. (Logstash만, 파이프라인을 바꿨을 때)
- 이전 이름(`GUIDE_*`)으로 설치된 서버는 먼저 새 설치 파일로 한 번 재설치한 뒤 패치하세요.
- 같은 도구를 직접 쓸 수도 있습니다: `sudo bash _internal/core/elk-patch.sh --list` (패치 가능한 항목 보기)

## 기본값 바꾸기 (관리자)

Wizard를 처음 열었을 때 입력칸에 채워지는 **초기값은 `wizard-defaults.js` 한 파일**에서 관리합니다. 이 파일만 고치면 되고, 별도 빌드나 명령은 필요 없습니다.

1. GitHub에서 `wizard-defaults.js`를 열어 연필 아이콘(Edit)으로 고치거나, 로컬에서 편집기로 엽니다.
2. 따옴표 안의 값만 고칩니다. `true` / `false` 항목은 따옴표 없이 씁니다. 예)
   ```js
   LOGSTASH_PIPELINE_FILE: "/etc/logstash/conf.d/20-proxy.conf",
   INSTALL_NGINX: true,
   ```
3. 저장(커밋)하고 Wizard를 새로고침하면 반영됩니다. (GitHub Pages는 반영까지 1~2분 걸릴 수 있습니다.)

- 항목은 Wizard **고급 설정**의 단계 번호 순서로 묶여 있고, 줄 끝 `//` 뒤에 항목 이름과 선택 가능한 값이 적혀 있습니다.
- 맨 아래 `deploy`에서 Ubuntu 자동 전송/설치 대상(서버 주소, SSH 계정, 포트 등)의 초기값을 정합니다.
- 비밀번호·암호화 키 항목은 저장소에 그대로 노출되므로 지정할 수 없습니다. (지정해도 무시됩니다)
- 잘못된 항목 이름, true/false가 아닌 값, 선택 목록에 없는 값은 무시되고 Wizard 위쪽에 경고가 표시됩니다. 파일에 문법 오류가 있어도 Wizard는 내장 기본값으로 동작하며 경고를 표시합니다.
- 파일을 지우면 Wizard에 내장된 기본값이 사용됩니다. 커밋할 때 GitHub Actions가 같은 검사를 수행합니다.
- `wizard-defaults.js`는 관리자가 편집한 **이 파일 자체가 기준**입니다. Wizard에 새 항목이 추가되었다면 `python3 tools/gen_defaults.py`가 기존 줄은 한 글자도 바꾸지 않고 파일에 없는 새 항목만 끝부분에 추가합니다. (파일 전체를 다시 만드는 `--rewrite` 옵션은 줄 배치가 바뀌므로 꼭 필요할 때만 쓰세요)
- 이 파일이 정하는 것은 Wizard가 채워 주는 초기값입니다. `install-elk.sh`의 `: "${KEY:=값}"` 줄은 `elk.env`에 값이 없을 때만 쓰는 예비값이라 별개입니다.

## 파일을 수정했다면 (개발)

Wizard는 생성하는 설치 파일(.sh)과 ZIP에 넣을 파일들의 **사본을 내장**하고 있습니다. `_internal/` 아래 파일이나 `run-remote-deploy.cmd`를 고친 뒤에는 반드시 아래를 실행하고 함께 커밋하세요.

```bash
python3 tools/sync_wizard.py          # 내장 사본과 SHA256SUMS.txt 갱신
python3 tools/sync_wizard.py --check  # 갱신이 필요한지만 확인 (CI가 같은 검사를 수행)
```

## 보안 주의

- Wizard가 만든 `elk-oneclick-install-v*.sh`, `elk.env`, ZIP에는 **SSH/sudo 비밀번호(Base64 — 암호화가 아님)와 ELK 계정 비밀번호**가 들어 있을 수 있습니다. 저장소에 커밋하거나 공유하지 마세요. (`.gitignore`가 기본적으로 막아 둡니다.)
- `config-wizard.html`의 배포 서버 기본값은 내부 주소일 수 있습니다. 공개 저장소이므로 확인하세요.
