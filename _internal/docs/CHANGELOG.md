# v2.9.3 (hotfix)

- **Config Wizard**: 단계 제목 아래의 "각 입력 카드를 클릭하면…" 안내 줄 삭제. 입력 카드·파일 카드의 테두리를 진하게 하고 카드 영역에 옅은 배경과 그림자를 넣어 구분을 명확히 함(마우스를 올리거나 펼친 카드는 파란 테두리, 오류는 빨강·필수는 주황 유지). 11단계의 "자동 실행 파일(.cmd) 다운로드" 버튼을 크고 눈에 띄는 주 버튼으로 바꾸고 ZIP은 보조 버튼으로 구분.
- **이름 정리 (호환 유지)**: 기존 설치 절차 문서에서 가져온 이름을 ProxySG 기준으로 바꿨습니다. 예전 이름으로 만든 설치 파일·`elk.env`·서버도 그대로 이어서 쓸 수 있습니다.

  | 구분 | 이전 이름 | 새 이름 |
  |---|---|---|
  | 환경변수 | `GUIDE_*` | `PROXYSG_*` (`GUIDE_PROXY_FLOW_ENABLED` → `PROXYSG_FLOW_ENABLED`, `GUIDE_PROXY_CSV_FILTER_ENABLED` → `PROXYSG_CSV_FILTER_ENABLED`) |
  | Logstash 프로필 값 | `proxysg_guide` | `proxysg` |
  | 파일 처리 스크립트 | `guide-log-process.sh` → `/usr/local/sbin/elk-guide-log-process` | `proxysg-log-process.sh` → `/usr/local/sbin/elk-proxysg-log-process` |
  | 스케줄 / 로그 | `/etc/cron.d/elk-guide-log-process`, `/var/log/elk-guide-log-process.log` | `/etc/cron.d/elk-proxysg-log-process`, `/var/log/elk-proxysg-log-process.log` |
  | Logstash 필터 템플릿 | `proxysg-guide-filter.conf` | `proxysg-log-filter.conf` |
  | 운영 명령 | `elk-ops guide` | `elk-ops proxysg` |
  | 문서/예제 | `PPT_GUIDE_MAPPING.md`, `elk-guide-9.5.2.env` | `INSTALL_STEP_MAPPING.md`, `elk-proxysg.env.example` |

  호환 처리: 설치기는 예전 환경변수 이름과 프로필 값을 새 이름으로 이어받고(새 이름이 있으면 그 값이 우선), 이전 이름으로 등록된 cron 파일과 스크립트가 남아 있으면 정리해 같은 처리가 두 번 실행되지 않게 합니다. Wizard의 "기존 SH/env 불러오기"와 `wizard-defaults.js`도 예전 이름을 새 이름으로 읽습니다. 예전 설치 파일 안에 들어 있던 스크립트·필터는 수정한 것으로 취급하지 않습니다. 설명 문구의 "입력 가이드"는 "입력 방법"으로 바꿨습니다.
- **run-remote-deploy**: sudo 비밀번호 자동 입력 시 stdin 앞에 UTF-8 BOM이 붙어 sudo 인증이 실패하던 문제 수정(BOM 없는 입력 인코딩 + 원격 측 BOM/CR 제거). sudo 검증 실패 시 `[DIAG]` 자동 진단(비밀번호 값은 출력하지 않음) 추가.
- **install-elk**: `logstash-keystore create`가 stdin이 없는 systemd 실행에서 확인 질문 때문에 중단되던 문제 수정, keystore 실패 시 실제 오류 메시지 출력.
- **install-elk**: Elasticsearch 9.x에서 본문이 있는 Kibana service token 요청이 거부되던 문제 수정.
- **install-elk**: 서비스 기동 대기 중 curl 연결 오류 출력 제거, 15초마다 대기 진행 로그 출력.
- **install-elk**: `ELASTIC_USERNAME` 검증 추가, Kibana 로그인 사용 여부(`KIBANA_LOGIN_ENABLED`)와 세션 유휴 만료(`KIBANA_SESSION_IDLE_TIMEOUT`) 옵션 추가.
- **run-remote-deploy.cmd**: 완료/오류 결과를 노란 글씨로 표시하고 창이 닫히지 않도록 `pause` 추가(`ELK_NO_PAUSE=1`이면 생략). 경로에 괄호가 있어도 동작하도록 구조 정리.
- **Config Wizard**: 초기값(기본값)을 별도 파일 `wizard-defaults.js`로 분리 — 관리자가 이 파일만 고치면 반영(빌드 불필요). 잘못된 항목은 무시하고 화면 위에 경고, 파일이 없거나 문법 오류여도 내장 기본값으로 동작, 비밀번호·키 항목은 지정 불가. `tools/gen_defaults.py`(생성/점검)와 CI 점검 추가.
- **Config Wizard**: 모든 입력 카드에 `기본값: …`(기본값에서 바꾼 경우 `● 기본값에서 변경됨`)을 표시하고, 모호했던 체크박스를 `사용 | 사용 안 함` 선택 버튼(기본 옵션에 `기본` 표시)으로 교체. Nginx 사용 시 Kibana server.host 경고를 제거하고 설치기가 자동으로 127.0.0.1로 제한한다는 안내로 변경.
- **Config Wizard / install-elk**: ProxySG MAIN/SSL 로그 포맷(ELFF `#Fields` 순서)을 7단계 필수 항목으로 입력(`PROXYSG_MAIN_LOG_FORMAT`, `PROXYSG_SSL_LOG_FORMAT`). 설치기가 로그 종류(edge-http / edge-https)마다 별도의 csv `columns`를 이 포맷으로 생성해 Logstash 필터에 반영한다. 필드 이름 규칙은 소문자와 `_`(예: `cs(Referer)`→`cs_referer`, `date`→`log_date`, `time`→`log_time`)이며 화면에서 미리 볼 수 있다. `proxysg-log-filter.conf`는 `@@PROXYSG_MAIN_COLUMNS@@` / `@@PROXYSG_SSL_COLUMNS@@` 줄을 가진 템플릿으로 변경. 설치 전 검증 추가(포맷 비어 있음/허용 문자, `LOGSTASH_PIPELINE_FILE`은 `/etc/logstash/conf.d/` 바로 아래 `.conf`).
- **Config Wizard**: 빠른 설정 3단계(Kibana)·5단계(Logstash)에 설정 파일 저장 위치 패널과 경로 입력칸(`KIBANA_EXTRA_CONFIG_FILE`, `LOGSTASH_PIPELINE_FILE`, `LOGSTASH_EXTRA_CONFIG_FILE`) 추가. 7단계에 파일 처리 cron 파일 경로(`/etc/cron.d/elk-proxysg-log-process`)와 `crontab -l`에 나오지 않는 이유, `* * * * *` 테스트 후 실제 시간으로 바꾸는 방법 안내. 검색 결과 카드에 빠른/고급 설정 단계 위치 표시(클릭 시 이동).
- **Config Wizard / install-elk**: 빠른 설정 7단계(고급 설정 14A)에 "사용되는 스크립트 · Logstash 설정" 패널 추가 — `proxysg-log-process.sh`, `proxysg-log-filter.conf`, Logstash 파이프라인(설치기가 만드는 내용의 미리보기)을 화면에서 보고 수정하면 생성되는 설치 파일·ZIP에 그대로 반영. 수정한 파이프라인은 `custom-pipeline.conf`로 내장되어 자동 생성 대신 설치되고, 수정한 스크립트는 설치 전 `bash -n`으로 검사. 수정 내용은 "기본값으로 되돌리기"/"설정값으로 다시 생성"으로 복구, 기존 SH 불러오기 시 함께 복원.
- **Config Wizard**: 단계 설명을 제목 아래 줄에서 제목 옆의 짧은 주석형 문구("…하는 기능")로 이동. 기존의 자세한 역할 설명은 문구에 마우스를 올리면 표시. 카드 펼치기 안내는 작은 줄로 유지.
- **Config Wizard**: (이전) 각 단계 제목 아래 설명을 "이 단계의 기능이 무슨 역할을 하는지" 설명으로 교체(빠른 설정 11단계, 고급 설정 26단계 전부). 카드 펼치기 안내는 별도 작은 줄로 분리.
- **Config Wizard**: 자동 실행 파일(`elk-auto-install-v2.9.3.cmd`) 다운로드 추가 — 더블클릭하면 임시 폴더에 자동으로 풀고 run-remote-deploy.cmd까지 실행, 끝나면 임시 폴더 삭제(`ELK_KEEP_TEMP=1`이면 유지).
- **Config Wizard**: 자동 전송 및 설치(10단계) / 검증 및 완료(11단계) 분리, 잘못된 값이 있으면 단계 이동 차단 및 빨간 표시, 좌측 메뉴 `필수` 태그, 초기 사용자 Role 드롭다운, 명령어 복사 버튼 수정(기존 `copy()` 미정의 오류) 및 명령어 펼침, 고급 설정 단계 제목 정리, 전체 패키지 ZIP 다운로드.

# v2.9.3

- Windows PowerShell 5.1 parser error in `_internal/tools/run-remote-deploy.ps1` fixed.
  - Removed fragile nested Bash quote function.
  - Remote root commands are Base64 encoded before SSH execution.
- Top-level `run-remote-deploy.cmd` is stored as ASCII/CRLF-compatible text so `@echo off` works reliably in cmd.exe.
- Config Wizard: added **기존 SH 불러오기**.
  - Reads embedded `elk.env` from prior `elk-oneclick-install*.sh`.
  - Restores Ubuntu host/user/port/remote path and SSH/sudo auto-login settings when present.
  - Supports both historical `__ELK_ELK_ENV_B64__` and current heredoc marker names.
- Imported older SH files can be edited and re-saved as the current v2.9.3 format.

# v2.9.0

- systemd detached install에서 `/dev/tty` ENXIO로 중단되는 진행률 출력 버그 수정
- 실제 제어 TTY가 있는 경우에만 fd 9를 확보하고, 비대화형 실행은 stdout 로그 방식으로 진행률 출력
- 패키지 버전 해석 실패 시 정의되지 않은 `err` 호출을 명시적 오류 출력으로 수정

# v2.8.8

- Fixed stale one-click payload selection: Windows launcher now prefers the versioned `elk-oneclick-install-v2.8.8.sh` file.
- Added one-click payload markers so the launcher rejects an older generated SH instead of silently deploying it.
- Hardened Elastic APT version resolution with `apt-cache madison` + `awk`; Logstash `9.5.2` now resolves to Debian package `1:9.5.2-1`.
- Installer logs both the requested upstream version and the exact APT package version before installing.
- Wizard downloads a versioned one-click filename to prevent collisions with older `elk-oneclick-install.sh` files.

# v2.8.7

- Fixed exact-version APT resolution for packages whose Debian version contains an epoch/revision (for example Logstash `1:9.5.2-1` vs upstream `9.5.2`).
- Re-runs now compare installed package upstream versions before deciding to skip.
- Remote console log is pre-created with mode 0600 before the detached systemd job starts.

# v2.8.6

- Windows launcher no longer calls `--remote-start` or `--remote-monitor` inside the one-click SH.
- `run-remote-deploy.cmd` now invokes Ubuntu `systemd-run` directly and only requires the SH to support `--local-install`.
- This prevents CMD/SH version mismatches such as v2.8.5 launcher + older v2.8 generated SH.
- Detached job uses `TimeoutStartSec=infinity` so large Elasticsearch/Kibana/Logstash downloads are not killed by systemd's normal startup timeout.
- Console output is stored in `/var/log/elk-oneclick-console.log`; `--status` reconnects to the same detached job.

# v2.8.6

- 원격 설치를 SSH 세션과 분리된 `systemd-run` 작업으로 실행하도록 변경
- SSH 모니터링 연결이 끊겨도 Ubuntu 서버의 실제 설치는 계속 진행
- `run-remote-deploy.cmd --status`로 실행 중 설치에 다시 연결 가능
- 원격 콘솔 로그 `/var/log/elk-oneclick-console.log` 추가
- APT 다운로드 재시도(`APT_RETRIES`, 기본 10회) 및 연결 타임아웃(`APT_CONNECT_TIMEOUT`, 기본 30초) 추가
- 비대화형(systemd) 실행에서도 다운로드/설치 진행률이 로그에 줄 단위로 표시되도록 개선
- Elasticsearch/Kibana/Logstash 등 APT 패키지 다운로드·설치 진행률 표시 유지

# v2.8.3
- Windows OpenSSH 원격 실행 명령 단순화
- `rc=$?; if ...` 복합 원격 shell 구문 제거
- 설치 성공 시 one-click installer가 자기 자신을 삭제하도록 변경
- SCP/SSH host-key 검증 무시 설정 유지

## v2.8.2
- Windows remote deploy now ignores SSH host-key verification for both SCP and SSH.
- Uses StrictHostKeyChecking=no and NUL known-hosts files, so stale/changed host keys do not block automation.

# v2.7.0

- Configuration Wizard에서 `elk.env`와 모든 설치/보조 스크립트를 포함한 `elk-oneclick-install.sh` 단일 파일 생성
- Ubuntu 서버에는 단일 `.sh` 파일만 업로드하여 설치 가능
- 실행 시 `--validate → 설치 → 전체 상태 점검` 자동 연속 수행
- `--validate`, `--check` 실행 모드 추가
- 설치 후 `/usr/local/sbin/elk-check` 배치
- 전체 상태 점검에 서비스/API/Cluster Health/ILM/Index Template/Nginx/FTP/Timer 검사와 PASS/WARN/FAIL 집계 추가
- 상태점검 로그 `/var/log/elk-post-install-check.log` 저장

# v2.5.0
- 전역 관리자 필수 입력 영역 제거, 각 설치 단계 상단으로 관리자 확인 항목 이동
- 단계별 필수/조건부 항목을 자동 판별하여 주황색 영역에 우선 표시
- Elasticsearch 데이터 경로, Logstash 전용 계정, FTP 루트/업로드 경로 등 사이트별 확인값을 단계별 필수 확인 대상으로 보강
- 필수 항목은 아래 일반 설정 영역에서 중복 표시하지 않도록 정리
- 모든 입력 카드의 상세 설명을 기본 접힘 상태로 변경
- 카드 빈 영역 클릭 또는 Enter/Space로 기능/필요 이유/입력 방법 펼침·접힘 지원
- 조건 기능(Kibana 사용자, Nginx 인증서, FTP, UFW 등) On/Off 시 현재 단계 필수 항목이 즉시 재계산되도록 개선

# v2.4.0
- Wizard 상단 중복 흐름표 제거
- 관리자 필수 확인/입력 영역 추가(계정, 비밀번호, 로그 경로, 조건부 인증서/방화벽/백업 경로)
- 상단/단계 중복 필드 실시간 동기화
- 주요 입력항목 설명을 기능/필요 이유/입력 방법 형식으로 상세화
- 고급 변수의 단순 설명을 섹션별 운영 목적과 입력 기준이 포함된 설명으로 보강

# Changelog

## v2.3.0

- ELK 9.5.2 설치 절차 전체를 GUI `빠른 설정` 10단계로 반영
- GUI에 `빠른 설정` / `고급 설정` 모드 추가
- 환경변수 303개 전체 검색/편집 및 기존 `elk.env` Import/Export 지원
- 빠른 설정 초기값(프리셋) 추가
- ILM 기본 보존기간을 60일에서 90일로 변경
- Elasticsearch `action.destructive_requires_name` 변수화
- Nginx 설치, Self-Signed 인증서, 80→443 Redirect, Kibana Reverse Proxy 자동화
- Kibana 초기 사용자 자동 생성 옵션 추가
- ProxySG MAIN/SSL Logstash `read` mode 프로필 추가
- `/home/main`, `/home/ssl`, backup/process 디렉터리 구조 자동 생성
- `log_process.sh` 흐름을 강화한 `proxysg-log-process.sh` 추가
- 매일 03:00 등 configurable cron 자동 등록
- vsftpd Active FTP / Port 20 옵션 추가, 기존 Passive/FTPS 고급 구성 유지
- `proxy-main-*`, `proxy-ssl-*` 복수 index pattern template 지원
- 기존 인덱스에도 ILM lifecycle 설정을 적용하는 옵션 추가
- main/ssl Kibana Data View 자동 생성
- `elk-ops nginx`, `elk-ops proxysg` 운영 명령 추가

## v2.2.0

- vsftpd FTP 자동 설치/계정/Passive/FTPS/UFW 연동

## v2.1.0

- GUI Configuration Wizard 추가

## v2.0.0

- Managed File Ingest, 90일 ILM, Health Monitor, Snapshot/SLM 추가

## v2.7
- 단일 설치 `.sh`에 원격 배포 모드 추가.
- PC의 Git Bash/WSL/Linux shell에서 일반 권한으로 실행하면 자체 파일을 `scp`로 Ubuntu에 전송하고 `ssh`로 원격 설치를 시작.
- `--deploy`, `--deploy-only`, `--local-install` 모드 추가.
- Wizard 마지막 단계에 Ubuntu 서버 IP/호스트, SSH 계정/포트, 원격 전송 폴더, 전송 후 자동 설치, 성공 후 원격 설치파일 삭제 설정 추가.
- 원격 설치 완료 후 기존 v2.6과 동일하게 전체 상태 점검 자동 수행.
- 설치 성공 시 민감정보가 포함될 수 있는 사용자 홈의 원클릭 `.sh` 파일을 기본 자동 삭제. 실패 시 재실행/분석을 위해 보존.

## v2.8.1
- Fixed Windows `run-remote-deploy.cmd` parsing failures on native cmd.exe.
- Converted launcher to Windows CRLF line endings.
- Removed nested FINDSTR command parsing and delayed expansion.
- Uses direct `for /f usebackq` parsing of DEPLOY_* values from the generated SH.
- Launcher content is ASCII-only for maximum Windows cmd.exe compatibility.

## v2.9.3
- Elasticsearch 운영 설정 재시작 직후 elastic 인증을 단발성 검사하지 않고 재시도합니다.
- 인증이 계속 실패하면 elastic 비밀번호를 재동기화한 뒤 Wizard의 목표 비밀번호를 다시 적용합니다.
- Config Wizard 원격 배포 단계에 SSH 로그인 비밀번호와 sudo 비밀번호 입력을 추가했습니다.
- Windows 원격 배포는 SSH_ASKPASS + sudo -S를 사용해 저장된 비밀번호를 자동 입력할 수 있습니다.
- SSH/sudo 배포 비밀번호는 서버 업로드 직전 설치 파일에서 제거합니다.
- SH/ENV 저장 버튼은 최초 1회 폴더 권한 선택 후 Config Wizard 작업 폴더에 직접 저장합니다.
- ZIP 최상위는 config-wizard.html, run-remote-deploy.cmd만 유지하고 나머지 구성요소는 _internal 아래에 둡니다.
