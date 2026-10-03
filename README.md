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

## 서버 정기점검 (점검 페이지)

상단 메뉴 **`점검`** 에서 서버 정기점검에 쓰는 **추천 항목**과 **확인 명령**을 볼 수 있습니다. (빠른 설정 · 고급 설정 · 패치 · **점검**)

1. **정기점검 추천 항목** — 매일 / 주 1회 / 월 1회 체크리스트. 항목마다 "왜 확인하나 · 정상 기준 · 리포트 항목"이 있습니다.
2. **항목별 점검 명령** — 아래 항목마다 **한 줄 명령**을 복사해서 서버에서 실행합니다. 현재 설정값(폴더·인덱스 이름·포트·Cloud 사용 여부)에 맞춰 만들어집니다.
   Ubuntu Version · Elastic(Elasticsearch) / Logstash / Kibana Version · 서버 Uptime · 디스크 사용량(로그 파일 main/ssl/cloud, Indices main/ssl/cloud) · CPU Usage · Memory Usage · Last Log Date(로그 파일, Indices) — 그리고 추가로 서비스 상태, 클러스터 상태, 처리 대기 파일.
3. **한 번에 점검(리포트)** — 위 항목을 읽기 쉬운 색 리포트로 한 번에 출력합니다.

| 방법 | 명령 | 언제 |
|---|---|---|
| 짧은 명령 | `sudo elk-report` (`--only sys,disk` · `--stale-hours 48` · `--no-color`) | 이 버전 이상의 설치 파일로 설치한 서버 |
| 전체 붙여넣기 | 페이지의 **전체 명령 복사** → 서버 터미널에 붙여넣기 (약 14KB, 읽기 전용, 끝나면 임시 파일 삭제) | 어느 서버에서나 |

- 점검 항목(`--only`/`--skip`): `sys ver cpu mem disk last svc es ingest cert os` (`sudo elk-report --list`)
- 상태 기준: 디스크 85% 주의 / 90% 이상, CPU 80% / 95%, 메모리 85% / 95%, JVM Heap 75% / 90%, 마지막 로그 36시간(기본) 주의 / 2배 이상, 인증서 30일 / 7일.
- 종료 코드: `0` 정상 · `1` 주의 있음 · `2` 이상 있음 (cron/모니터링에서 사용 가능). 예: `sudo elk-report --no-color >> /var/log/elk-report.log`
- Elasticsearch 조회에는 서버의 `secrets.env`(root 전용)에서 읽은 비밀번호를 쓰며, 서버 설정은 바꾸지 않습니다(읽기 전용).
- 한 항목이 실패해도(예: Elasticsearch 연결 불가) 리포트는 끝까지 출력되고, 해당 항목만 `✖`/`⚠`로 표시됩니다.

## 상단 메뉴 배치

왼쪽에 **제목과 페이지 탭**(빠른 설정 · 고급 설정 · 패치 · 점검), 가운데에 **검색**, 오른쪽에 나머지(저장 폴더 · 불러오기 · 초기화)가 놓입니다. 창이 좁으면(약 1400px 이하) 검색이 두 번째 줄 가운데로 내려갑니다. 패치·점검 페이지에서는 검색창을 숨깁니다.

## 설치 화면 색상

설치 중 출력은 **중요도**와 **주제**에 따라 글자색이 구분됩니다. (터미널에서 실행할 때)

| 구분 | 표시 |
|---|---|
| 오류 `ERROR/FAIL` | 흰 글자 + 빨강 태그, 메시지는 굵은 빨강 |
| 경고 `WARN` | 검정 글자 + 노랑 태그, 메시지는 노랑 |
| 완료 `OK/PASS`, "…정상/완료" 안내 | 초록 (✔) |
| 일반 안내 `INFO` | 회색 태그 + **주제별 글자색** — 시스템 강철색 · 패키지 연보라 · Elasticsearch 하늘색 · Kibana 보라 · Logstash 청록 · Nginx/TLS 모래색 · FTP/처리 스크립트 분홍 · 방화벽 갈색 |
| 진행률 | `█░` 막대 (100%는 초록) |
| 끝 | 성공: 초록 **✔ 설치 완료** 상자 / 실패: 빨강 **✖ 설치 실패** 상자(원인·로그 위치·다음 조치) |

- **로그 파일에는 색이 들어가지 않습니다.** (`/var/log/elk-auto-install.log` 등은 항상 일반 텍스트)
- 터미널이 아니면(파일/파이프/systemd) 자동으로 색이 꺼집니다. 원격 설치(`--remote-monitor`)는 서버에서는 일반 로그로 기록하고, **보여 줄 때** 색을 입힙니다. Windows `run-remote-deploy.cmd`도 같은 방식입니다.
- 끄기: 실행 옵션 `--no-color` 또는 `--color=never`, 환경변수 `NO_COLOR=1` / `ELK_COLOR=never`. 강제로 켜기: `--color=always` / `ELK_COLOR=always`.
- 색을 꺼도 출력 문장(`[INFO]` `[WARN]` `[ERROR]` …)은 그대로입니다.

## 설치 전 디스크 자동 확장 (LVM)

Ubuntu Server를 LVM으로 설치하면 디스크 일부만 루트(/)에 할당되고 나머지가 볼륨 그룹의 미할당 공간으로 남는 경우가 있습니다. 설치기는 시작할 때 이를 확인해, **남는 공간이 있으면 전부 루트에 할당**합니다. (`lvextend -l +100%FREE -r <루트 LV>`와 같은 동작이며 파일시스템도 함께 늘립니다)

- 루트가 LVM이 아니거나, thin 볼륨이거나, 남는 공간이 없으면 아무것도 하지 않습니다. 확장에 실패해도 설치는 계속됩니다(경고만).
- 이미 모두 할당된 서버에서 다시 실행해도 안전합니다.
- 끄려면 `OS_EXTEND_ROOT_LVM=false` (고급 설정 2단계 "OS 기본 설정").
- 하이퍼바이저에서 **디스크 자체를 키운 경우**(파티션/PV 확장)는 대상이 아닙니다. 그 경우 `growpart`·`pvresize`가 먼저 필요합니다.

## 설치 후 일부 값만 수정 (패치)

이미 설치된 서버에서 **전체 재설치 없이 바꾼 값만** 적용합니다. 상단 메뉴의 **`패치`** (빠른 설정 · 고급 설정 · **패치**) 페이지에서 사용합니다.

1. **기준값 불러오기** — 설치에 썼던 `sh 파일`(또는 `elk.env`)을 불러옵니다. 이 값이 기준이 되어, 달라진 항목이 자동으로 선택됩니다. (불러오지 않아도 됩니다. 그때는 값을 고치거나 직접 체크한 항목이 대상입니다)
2. **바꿀 값 선택 · 수정** — 이 페이지에서 바로 값을 고칠 수 있고, 체크한 항목만 패치됩니다. (여기서 바꾼 값은 빠른/고급 설정의 같은 항목에도 반영됩니다)
3. **패치 적용** — 실행 방식(확인 후 적용 / 미리보기만 `--dry-run` / 바로 적용 `--yes`)을 고른 뒤 아래 세 가지 중 하나로 적용합니다.

| 방법 | 어떻게 | 언제 |
|---|---|---|
| **A. 패치 파일** | `elk-patch-날짜-시간.sh`를 받아 서버로 복사 → `sudo bash elk-patch-*.sh` | 파일을 전송할 수 있을 때 |
| **B-1. 전체 붙여넣기** | **전체 명령 복사** → 서버 터미널에 붙여넣기 → Enter (약 16KB·220줄, 임시 파일을 만들었다가 끝나면 스스로 삭제) | 어느 서버에서나. 파일 전송이 번거로울 때 |
| **B-2. 짧은 명령** | `sudo elk-patch KEY='값' …` 한 번 복사해 붙여넣기 | 이 버전 이상의 설치 파일로 설치한 서버 (서버에 `elk-patch`가 설치되어 있음) |

> 붙여넣기 뒤에 다른 명령을 이어 붙이지 마세요. "확인 후 적용"은 `적용할까요? [y/N]` 질문에 직접 `y`를 입력해야 하는데, 이어 붙인 줄이 그 입력으로 소비되어 취소됩니다.
> 짧은 명령은 서버에 설치된 필터·파이프라인 파일을 쓰므로, 파일 카드(스크립트·필터·파이프라인)를 기준값에서 바꿨다면 **전체 붙여넣기**를 사용하세요. (페이지가 자동으로 막고 안내합니다)

| 바꾸는 값 | 실제로 하는 일 |
|---|---|
| 로그 처리 스크립트 실행 시간(cron) | `/etc/cron.d/elk-proxysg-log-process`의 실행 시간만 교체 |
| 인덱스 보존기간(ILM) | 기존 ILM 정책의 삭제 단계만 수정 (hot/warm 단계는 그대로) |
| 로그 포맷 · 파이프라인 관련 값 | 파이프라인을 다시 만들고 `logstash -t`로 검사한 뒤 Logstash 재시작. **검사 실패 시 파이프라인과 elk.env를 자동 복구** |
| Cloud 로그 처리 켜기/끄기 | Cloud 폴더 + 파이프라인 + Index Template 패턴 + Data View |
| 인덱스 Prefix · Data View 이름 | 파이프라인 + Index Template 패턴 + Data View |
| 수신·백업 폴더 | 폴더 생성/권한 (스크립트는 다음 실행부터 새 경로 사용) |

- 바꾸기 전 `elk.env`와 파이프라인은 `/var/backups/elk-auto/patch-날짜-시간/`에 백업됩니다. 되돌리려면 그 안의 `elk.env`를 `/etc/elk-auto/elk.env`로 복사하세요.
- **패치로 바꿀 수 없는 값**(포트, 계정·비밀번호, Heap, 인증서, 방화벽 등)이 하나라도 섞이면 도구가 거절하며 아무것도 바꾸지 않습니다. 이런 값은 전체 설치 파일로 다시 설치하세요. 값은 한 줄이어야 합니다.
- Elasticsearch/Kibana는 재시작하지 않습니다. (Logstash만, 파이프라인을 바꿨을 때)
- 설치기는 서버에 `/usr/local/sbin/elk-patch` 와 `/usr/local/lib/elk-auto/` 를 남깁니다. `sudo elk-patch --list`로 패치 가능한 항목을 볼 수 있습니다.
- 이전 이름(`GUIDE_*`)으로 설치된 서버는 먼저 새 설치 파일로 한 번 재설치한 뒤 패치하세요.

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
