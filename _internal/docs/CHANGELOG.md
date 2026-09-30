# v2.9.3 (hotfix)

- **run-remote-deploy**: sudo 비밀번호 자동 입력 시 stdin 앞에 UTF-8 BOM이 붙어 sudo 인증이 실패하던 문제 수정(BOM 없는 입력 인코딩 + 원격 측 BOM/CR 제거). sudo 검증 실패 시 `[DIAG]` 자동 진단(비밀번호 값은 출력하지 않음) 추가.
- **install-elk**: `logstash-keystore create`가 stdin이 없는 systemd 실행에서 확인 질문 때문에 중단되던 문제 수정, keystore 실패 시 실제 오류 메시지 출력.
- **install-elk**: Elasticsearch 9.x에서 본문이 있는 Kibana service token 요청이 거부되던 문제 수정.
- **install-elk**: 서비스 기동 대기 중 curl 연결 오류 출력 제거, 15초마다 대기 진행 로그 출력.
- **install-elk**: `ELASTIC_USERNAME` 검증 추가, Kibana 로그인 사용 여부(`KIBANA_LOGIN_ENABLED`)와 세션 유휴 만료(`KIBANA_SESSION_IDLE_TIMEOUT`) 옵션 추가.
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
- 카드 빈 영역 클릭 또는 Enter/Space로 기능/필요 이유/입력 가이드 펼침·접힘 지원
- 조건 기능(Kibana 사용자, Nginx 인증서, FTP, UFW 등) On/Off 시 현재 단계 필수 항목이 즉시 재계산되도록 개선

# v2.4.0
- Wizard 상단 중복 흐름표 제거
- 관리자 필수 확인/입력 영역 추가(계정, 비밀번호, 로그 경로, 조건부 인증서/방화벽/백업 경로)
- 상단/단계 중복 필드 실시간 동기화
- 주요 입력항목 설명을 기능/필요 이유/입력 가이드 형식으로 상세화
- 고급 변수의 단순 설명을 섹션별 운영 목적과 입력 기준이 포함된 설명으로 보강

# Changelog

## v2.3.0

- 사용자가 제공한 ELK 9.5.2 PPT 스크린샷 전체를 GUI `가이드 간단 설정` 10단계로 반영
- GUI에 `가이드 간단 설정` / `전체 고급 설정` 모드 추가
- 환경변수 303개 전체 검색/편집 및 기존 `elk.env` Import/Export 지원
- `PPT 9.5.2 프리셋` 추가
- PPT의 60일 ILM을 사용자 요청에 따라 90일로 변경
- Elasticsearch `action.destructive_requires_name` 변수화
- Nginx 설치, Self-Signed 인증서, 80→443 Redirect, Kibana Reverse Proxy 자동화
- Kibana 초기 사용자 자동 생성 옵션 추가
- ProxySG MAIN/SSL Logstash `read` mode 프로필 추가
- `/home/main`, `/home/ssl`, backup/process 디렉터리 구조 자동 생성
- PPT `log_process.sh` 흐름을 강화한 `guide-log-process.sh` 추가
- 매일 03:00 등 configurable cron 자동 등록
- vsftpd Active FTP / Port 20 옵션 추가, 기존 Passive/FTPS 고급 구성 유지
- `proxy-main-*`, `proxy-ssl-*` 복수 index pattern template 지원
- 기존 인덱스에도 ILM lifecycle 설정을 적용하는 옵션 추가
- main/ssl Kibana Data View 자동 생성
- `elk-ops nginx`, `elk-ops guide` 운영 명령 추가

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
