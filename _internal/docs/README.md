## v2.9.0 원격 분리 실행 안정화

- `systemd-run`/nohup/cron처럼 제어 TTY가 없는 환경에서 `/dev/tty`를 열어 진행률을 표시하려다 `No such device or address`로 종료되던 문제를 수정했습니다.
- 설치 시작 시 실제 TTY가 있을 때만 전용 fd를 확보하고, 분리 실행에서는 진행률을 일반 로그 라인으로 기록합니다.
- 기존 Elasticsearch/Kibana가 설치된 서버에서 재실행하면 설치된 동일 버전은 건너뛰고 Logstash/FTP/나머지 구성부터 계속 진행합니다.

# ELK Auto Installer v2.9.0

> v2.9.0 prevents stale one-click SH files from being deployed. The Wizard now downloads `elk-oneclick-install-v2.9.0.sh`, and the Windows launcher verifies the payload marker before SCP. Logstash upstream `9.5.2` is resolved to the exact APT version such as `1:9.5.2-1`.

## v2.9.0 패키지 버전 해석 수정

`ELASTIC_VERSION=9.5.2`처럼 upstream 버전을 지정했을 때 Debian/Ubuntu APT 패키지 버전이 `1:9.5.2-1`처럼 epoch/revision을 포함해도 자동으로 동일 버전으로 인식합니다. Elasticsearch, Kibana, Logstash 각각의 실제 APT 버전을 `apt-cache madison`에서 확인해 설치하므로 Logstash의 exact-version 설치 실패를 방지합니다.

원격 콘솔 로그 `/var/log/elk-oneclick-console.log`도 root 전용(0600)으로 생성하여 패키지 설치 중 출력될 수 있는 초기 인증정보가 일반 사용자에게 노출되지 않도록 강화했습니다.

## v2.9.0 핵심 변경: SSH가 끊겨도 설치 계속

Windows의 `run-remote-deploy.cmd`는 이제 원격 설치를 SSH 세션에 직접 매달아 실행하지 않습니다. Ubuntu에서 `systemd-run`으로 독립 작업을 만든 뒤, Windows 쪽 SSH는 진행상황만 모니터링합니다. 따라서 대용량 Elasticsearch 패키지 다운로드 중 `Connection reset`이 발생해도 서버의 설치 작업은 계속됩니다.

원격 모니터 연결이 끊기면 같은 폴더에서 다음 명령으로 다시 연결할 수 있습니다.

```cmd
run-remote-deploy.cmd --status
```

Ubuntu에서 직접 확인하려면:

```bash
sudo cat /run/elk-oneclick-install.unit
sudo tail -f /var/log/elk-oneclick-console.log
```

APT 다운로드에는 기본적으로 재시도와 연결 타임아웃도 적용합니다.

```bash
APT_RETRIES="10"
APT_CONNECT_TIMEOUT="30"
```


## 설치 진행률 표시 (v2.9.0)

대용량 Elastic 패키지를 내려받는 동안 화면이 멈춘 것처럼 보이지 않도록 진행률 표시를 추가했습니다.

- 전체 설치 단계: `[전체] [#####-----] 38% Logstash 패키지 다운로드/설치`
- 패키지 다운로드: `[다운로드] [########--] 82% Elasticsearch 9.5.2 - Retrieving file ...`
- 패키지 설치: `[설치] [##########] 100% Elasticsearch 9.5.2 - ...`
- 진행률은 가능하면 `/dev/tty`에만 표시하므로 `/var/log/elk-auto-install.log`에는 불필요한 carriage-return 출력이 쌓이지 않습니다.

환경변수:

```bash
INSTALL_PROGRESS_ENABLED="true"
INSTALL_PROGRESS_BAR_WIDTH="30"
APT_PROGRESS_ENABLED="true"
```

진행률 표시를 원하지 않으면 `INSTALL_PROGRESS_ENABLED=false` 또는 APT 다운로드/설치 percentage만 끄려면 `APT_PROGRESS_ENABLED=false`로 설정할 수 있습니다.


## v2.9.0 핵심 변경: 서버에는 단일 설치 파일 1개만 업로드

Configuration Wizard 마지막 단계에서 **`elk-oneclick-install-v2.9.0.sh`**를 다운로드할 수 있습니다. 이 파일 하나 안에 현재 Wizard 설정값(`elk.env`)과 설치기, ProxySG Filter, FTP/파일처리/모니터링/상태점검 스크립트가 모두 Base64 payload로 포함됩니다.

Ubuntu 서버에는 이 파일 하나만 전송하면 됩니다.

```bash
chmod 600 elk-oneclick-install-v2.9.0.sh
sudo bash elk-oneclick-install-v2.9.0.sh
```

기본 실행은 다음 3단계를 자동으로 연속 수행합니다.

1. **설정 검증** — 내장된 환경설정을 `install-elk.sh --validate`로 검사
2. **자동 설치** — Elasticsearch/Kibana/Logstash/FTP/Nginx/ILM 등 선택한 구성 설치
3. **전체 상태 점검** — 서비스, API, Elasticsearch Cluster Health, ILM Policy, Index Template, Kibana, Logstash, FTP, 파일수집/Health Monitor Timer를 검사하고 `/var/log/elk-post-install-check.log`에 저장

설치 전에 검증만 하고 싶다면:

```bash
sudo bash elk-oneclick-install-v2.9.0.sh --validate
```

설치 후 언제든 전체 상태를 다시 검사하려면:

```bash
sudo bash elk-oneclick-install-v2.9.0.sh --check
# 또는 설치 후 생성되는 명령
sudo elk-check /etc/elk-auto/elk.env
```

> 단일 설치 파일에는 관리자가 입력한 계정/비밀번호가 포함될 수 있으므로 서버에서 권한을 `600`으로 유지하십시오. 실행 시 스크립트도 자신의 파일 권한을 자동으로 `600`으로 조정합니다.


Ubuntu 22.04/24.04 초기 설치 서버에서 **Elasticsearch + Kibana + Logstash + FTP(vsftpd) + 선택형 Nginx HTTPS + ILM + ProxySG MAIN/SSL 파일 처리**를 자동 구성합니다.

Configuration Wizard의 `빠른 설정`은 설치 순서에 맞춰 필요한 항목만 단계별로 보여 줍니다. 모든 환경변수는 `고급 설정`에서 조정할 수 있습니다.

> ILM 기본 삭제 기간은 **90일**입니다.

## 빠른 사용

Windows에서 ZIP을 풀고 `open-config-gui.cmd`를 실행하거나 `config-wizard.html`을 Chrome/Edge에서 엽니다.

Wizard의 `빠른 설정`에서 필요한 값을 입력한 뒤 마지막 단계에서 **`단일 설치 파일 다운로드 (.sh)`**를 누릅니다. Ubuntu 서버에는 생성된 `elk-oneclick-install-v2.9.0.sh` 하나만 복사합니다.

```bash
chmod 600 elk-oneclick-install-v2.9.0.sh
sudo bash elk-oneclick-install-v2.9.0.sh
```

설치 스크립트가 설정 검증부터 실제 설치, 전체 상태 점검까지 자동으로 수행합니다. 설치 후 재점검은 다음 중 하나를 사용합니다.

```bash
sudo bash elk-oneclick-install-v2.9.0.sh --check
sudo elk-check /etc/elk-auto/elk.env
sudo elk-ops status
sudo elk-ops indices
```

`elk.env만 다운로드` 버튼도 유지되어 있으므로 기존 다중 파일 방식이 필요한 경우에는 계속 사용할 수 있습니다.

## Configuration Wizard

### v2.5 단계별 관리자 확인 UI

전역 상단에 관리자 입력값을 모으지 않습니다. 각 단계에 들어가면 **그 단계에서 실제 운영환경에 맞게 확인해야 할 값만 가장 위쪽 주황색 영역**에 표시됩니다. 예를 들어 Elasticsearch 단계에는 관리자 비밀번호와 데이터 경로, FTP 단계에는 FTP 계정/비밀번호와 루트·업로드 경로, MAIN/SSL 단계에는 Source/Backup/Process 경로가 우선 표시됩니다. 조건부 기능을 켜면 Nginx 인증서, Kibana 사용자, UFW 허용 대역 등의 필수 항목도 해당 단계에서 자동으로 나타납니다.

입력 카드의 상세 설명은 기본적으로 접혀 있습니다. **카드의 빈 영역을 클릭**하면 `기능 / 왜 필요한가 / 입력 방법` 설명이 펼쳐지고 다시 클릭하면 접힙니다. 입력창, Select, 생성/보기 버튼을 클릭할 때는 설명이 열리지 않아 값 편집을 방해하지 않습니다.


`config-wizard.html`에는 두 가지 모드(`빠른 설정`, `고급 설정`)가 있습니다.

### 빠른 설정

설치 순서에 맞춘 단계입니다.

```text
01 Elastic 9.x 저장소
       ↓
02 Elasticsearch
       ↓
03 Kibana
       ↓
04 Nginx HTTPS (선택)
       ↓
05 Logstash
       ↓
06 FTP (vsftpd)
       ↓
07 MAIN / SSL 파일 처리
       ↓
08 인덱스 · Data View · ILM 90일
       ↓
09 서비스 · 방화벽
       ↓
10 검증 · 장애 대응 · elk.env 생성
```

각 변수에는 기능, 왜 필요한지, 입력 방법과 기본값이 표시됩니다.

### 고급 설정

현재 `elk.env`의 **308개 환경변수**를 모두 수정할 수 있습니다. 변수 검색, 기존 env 불러오기, 비밀번호 생성, 최종 검증과 env 다운로드를 지원합니다.

## ProxySG MAIN/SSL 프로필의 기본 흐름

빠른 설정의 초기값은 다음 구성을 만듭니다.

```text
FTP client
   │
   ├─ MAIN .log.gz → /home/main
   └─ SSL  .log.gz → /home/ssl
             │
             ▼
      proxysg-log-process.sh
      기본: 매일 03:00
             │
      ┌──────┴───────────┐
      │                  │
      ▼                  ▼
/home/*_backup      /home/*_process
 원본 보관              │
                       ▼
                    Logstash
                   mode = read
                       │
            EOF 후 process 파일 삭제
                       │
              ┌────────┴────────┐
              ▼                 ▼
 proxy-main-YYYY.MM.dd   proxy-ssl-YYYY.MM.dd
              │                 │
              └────────┬────────┘
                       ▼
             proxy-index-template
                       │
             proxy-retention-policy
                       │
                    90일 삭제
```

`proxysg-log-process.sh`는 다음 보호 기능을 포함합니다.

- `flock` 중복 실행 방지
- 임시 `.part` 복사 후 atomic rename
- process/backup 두 복사본을 `cmp`로 원본과 검증
- 두 복사본이 모두 정상일 때만 source 삭제
- 동일 이름의 backup 또는 process가 이미 있으면 source를 남기고 건너뜀

## Elasticsearch

Elastic 버전은 기본적으로 `ELASTIC_VERSION=""`로 비워 두어 9.x 저장소의 최신 버전을 설치합니다. 특정 버전으로 고정하려면 `x.y.z` 형식(예: `9.5.2`)으로 입력합니다.

주요 설정은 다음 변수로 관리합니다.

```bash
ES_NETWORK_HOST="0.0.0.0"
ES_HTTP_PORT="9200"
ES_ACTION_DESTRUCTIVE_REQUIRES_NAME="false"  # 빠른 설정 초기값
ELASTIC_PASSWORD=""                           # 비우면 자동 생성
```

일반 기본값에서 `ES_ACTION_DESTRUCTIVE_REQUIRES_NAME`은 안전을 위해 `true`입니다. 빠른 설정은 편의상 `false`로 시작합니다.

테스트 VM에서 쓰는 `-Xms512m / -Xmx512m` 같은 작은 고정 Heap은 운영 기본값으로 설정하지 않았습니다. 기본은:

```bash
ES_HEAP_MODE="auto"
```

이며 필요할 때 `fixed`와 Xms/Xmx를 지정합니다.

## Kibana / 사용자

자동 설치에서는 Enrollment Token + Verification Code 수동 절차 대신 Kibana용 **Service Account Token**을 생성해 Kibana keystore에 저장합니다.

초기 사용자를 별도로 만들고 싶으면:

```bash
KIBANA_CREATE_INITIAL_USER="true"
KIBANA_INITIAL_USER_NAME="elkadmin"
KIBANA_INITIAL_USER_PASSWORD=""
KIBANA_INITIAL_USER_ROLES="kibana_admin"
```

비밀번호를 비우면 자동 생성됩니다. `superuser`, `kibana_admin`, `viewer`, `monitoring_user` 등의 Role을 사용할 수 있습니다.

## Nginx HTTPS

선택 구성(Self-Signed HTTPS, 80→443 Redirect, Kibana Reverse Proxy)을 자동화했습니다.

```bash
INSTALL_NGINX="true"
NGINX_HTTP_PORT="80"
NGINX_HTTPS_PORT="443"
NGINX_REDIRECT_HTTP_TO_HTTPS="true"
NGINX_TLS_MODE="selfsigned"
NGINX_TLS_DAYS="3650"
NGINX_TLS_CN=""
```

Self-Signed 인증서를 자동 생성하고 SAN에 서버 IP/hostname을 넣습니다. Nginx 구성 후 반드시 `nginx -t`를 통과해야 설치가 계속됩니다. Nginx 사용 시 Kibana listen 주소가 `0.0.0.0`이면 자동으로 `127.0.0.1`로 제한합니다.

## Logstash ProxySG 프로필

```bash
LOGSTASH_PROFILE="proxysg"
PROXYSG_FLOW_ENABLED="true"
PROXYSG_MAIN_PROCESS_DIR="/home/main_process"
PROXYSG_SSL_PROCESS_DIR="/home/ssl_process"
PROXYSG_FILE_GLOB="*.log.gz"
PROXYSG_MAIN_SINCEDB="/var/lib/logstash/sincedb-main"
PROXYSG_SSL_SINCEDB="/var/lib/logstash/sincedb-ssl"
PROXYSG_LOGSTASH_DISCOVER_INTERVAL="5"
PROXYSG_LOGSTASH_MAX_OPEN_FILES="1000"
```

Logstash File Input은 `read` mode로 구성되며 파일 처리가 완료되면 process 파일을 삭제합니다. 원본은 이미 backup 폴더에 보관됩니다.

`proxysg-log-filter.conf`는 ProxySG CSV 파싱 템플릿이며, MAIN/SSL 로그 포맷(`PROXYSG_MAIN_LOG_FORMAT`, `PROXYSG_SSL_LOG_FORMAT`)으로 만든 컬럼 목록이 설치할 때 들어갑니다. 파싱을 쓰지 않으려면:

```bash
PROXYSG_CSV_FILTER_ENABLED="false"
```

로 먼저 raw message 수집을 확인한 뒤, 로그 포맷을 실제 `#Fields` 순서에 맞게 입력하십시오.

## FTP

빠른 설정은 `elkftp` 계정이 `/home/main` 및 `/home/ssl`에 접근하도록 구성합니다.

```bash
FTP_USER="elkftp"
FTP_PASSWORD=""
FTP_CHROOT_LOCAL_USER="false"
FTP_ACTIVE_ENABLE="true"
FTP_CONNECT_FROM_PORT_20="true"
FTP_PASV_ENABLE="false"
FTP_TLS_ENABLED="false"
```

일반 운영용 고급 설정에서는 기존 v2.2의 Chroot + Passive Port + 선택형 FTPS 구성을 계속 사용할 수 있습니다.

## Index / Data View / ILM

빠른 설정 초기값:

```bash
PROXYSG_MAIN_INDEX_PREFIX="proxy-main"
PROXYSG_SSL_INDEX_PREFIX="proxy-ssl"
PROXYSG_MAIN_DATA_VIEW_NAME="main"
PROXYSG_SSL_DATA_VIEW_NAME="ssl"
PROXYSG_ILM_POLICY_NAME="proxy-retention-policy"
PROXYSG_INDEX_TEMPLATE_NAME="proxy-index-template"
INDEX_TEMPLATE_PATTERNS="proxy-main-*,proxy-ssl-*"
ILM_DELETE_MIN_AGE="90d"
ILM_APPLY_TO_EXISTING="true"
ILM_EXISTING_INDEX_PATTERNS="proxy-main-*,proxy-ssl-*"
```

새 인덱스에는 `proxy-index-template`을 통해 lifecycle policy가 자동 적용됩니다. `ILM_APPLY_TO_EXISTING=true`이면 이미 존재하는 matching index에도 `index.lifecycle.name`을 설정합니다.

Kibana Data View도 `main = proxy-main-*`, `ssl = proxy-ssl-*`로 자동 생성합니다.

## 설치 후 비밀번호 확인

```bash
sudo cat /root/.elk-auto-installer/secrets.env
```

여기에는 자동 생성된 `ELASTIC_PASSWORD`, FTP 비밀번호, Logstash 비밀번호, 초기 사용자 비밀번호 등이 저장될 수 있습니다. 파일 권한은 root 전용으로 제한됩니다.

## 장애 점검

```bash
systemctl status elasticsearch --no-pager
systemctl status kibana --no-pager
systemctl status logstash --no-pager
systemctl status vsftpd --no-pager
systemctl status nginx --no-pager

sudo nginx -t
sudo elk-ops status
sudo elk-ops indices
sudo elk-ops ilm
```

Logstash `E212: Can't open file for writing` 대응으로 흔히 쓰는 `chmod 777 /etc/logstash/conf.d/`는 자동화에 넣지 않았습니다. 설치기는 root 권한으로 설정 파일을 만들고 필요한 서비스 그룹 권한만 부여합니다.

자세한 설치 단계 매핑은 `INSTALL_STEP_MAPPING.md`를 참고하십시오.


## v2.5 Wizard UI 개선
- 상단 전역 관리자 입력 영역을 제거하고, **각 단계의 맨 위**에 그 단계에서 확인할 계정·비밀번호·경로·인증서·방화벽 값을 표시합니다.
- 관리자 확인 항목은 아래 일반 설정 영역에서 중복 표시하지 않습니다.
- Kibana 사용자 생성, Nginx, UFW 등 조건 기능을 켜거나 끄면 해당 단계 필수 항목이 즉시 다시 계산됩니다.
- 입력 카드 설명은 기본적으로 접혀 있으며, 카드를 클릭하면 `기능 / 왜 필요한가 / 입력 방법`가 펼쳐집니다.
- 입력창과 버튼을 클릭할 때는 카드가 열리거나 닫히지 않도록 분리했습니다.

---

## v2.9.0 원격 자동 전송 / 원클릭 설치

Wizard 마지막 `10. 검증 / 장애 대응 / 생성` 단계의 **PC → Ubuntu 자동 전송 / 설치** 영역에서 다음 값을 확인합니다.

- Ubuntu 서버 IP/호스트: 예 `172.16.70.208`
- SSH 로그인 계정: 예 `etech`
- SSH 포트: 기본 `22`
- 원격 전송 폴더: 예 `/home/etech`
- 전송 후 자동 설치: 기본 `ON`
- 성공 후 원격 설치파일 삭제: 기본 `ON`

이 값은 `elk.env`가 아니라 생성되는 `elk-oneclick-install-v2.9.0.sh` 자체에 포함됩니다. SSH 비밀번호와 sudo 비밀번호는 파일에 저장하지 않으며 접속 시 터미널에서 입력합니다.

### Windows PowerShell/CMD에서 원클릭 배포

```bash
bash elk-oneclick-install-v2.9.0.sh
```

일반 권한으로 실행하면 자동으로 다음 순서를 수행합니다.

```text
현재 .sh 확인
  → scp -P <SSH_PORT> .sh <USER>@<HOST>:<REMOTE_DIR>/
  → ssh -tt <USER>@<HOST>
  → chmod 600
  → sudo bash <REMOTE_FILE> --local-install
  → 설정 검증
  → ELK/FTP/선택 구성 설치
  → 전체 상태 점검
  → 성공 시 원격 홈의 .sh 삭제(기본값)
```

명시적으로 원격 배포하려면:

```bash
bash elk-oneclick-install-v2.9.0.sh --deploy
```

파일만 전송하려면:

```bash
bash elk-oneclick-install-v2.9.0.sh --deploy-only
```

### Ubuntu 서버에 이미 파일을 올려둔 경우

```bash
sudo bash elk-oneclick-install-v2.9.0.sh --local-install
```

검증만:

```bash
sudo bash elk-oneclick-install-v2.9.0.sh --validate
```

상태점검만:

```bash
sudo bash elk-oneclick-install-v2.9.0.sh --check
```

### Windows PowerShell / CMD 주의

Windows에서는 `.sh`를 직접 실행하지 않습니다. 같은 폴더의 `run-remote-deploy.cmd`가 SH 안의 `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_PORT`, `DEPLOY_REMOTE_DIR` 값을 읽고 **Windows 기본 OpenSSH의 scp.exe/ssh.exe를 직접 실행**합니다. Git Bash/WSL은 필요하지 않습니다.

```cmd
run-remote-deploy.cmd
```

Windows에서 `scp`와 `ssh`가 이미 동작한다면 추가 설치 없이 사용할 수 있습니다.


## Windows 원격 배포 v2.9.0.3 수정

`run-remote-deploy.cmd`는 Windows `cmd.exe` 호환성을 위해 CRLF/ASCII 형식으로 제공되며, SH의 `DEPLOY_*` 값을 직접 읽습니다. Git Bash/WSL은 필요하지 않습니다.


### v2.9.0.3 remote deployment behavior
`run-remote-deploy.cmd` intentionally disables SSH host-key verification for automated SCP/SSH deployment. Existing entries in Windows `known_hosts` are ignored and no new host key is stored.


## v2.9.0 Windows 원격 실행 안정화
- Windows CMD가 SSH에 넘기는 원격 명령을 `sudo bash <installer> --local-install` 한 줄로 단순화했습니다.
- 설치 성공 후 단일 설치 파일 삭제는 원격 SSH 복합 명령이 아니라 installer 내부에서 처리합니다.
- SSH exit code 255 문제 진단을 위해 서버의 SSH/TTY/sudo가 정상인 환경에서 보다 안정적으로 동작하도록 변경했습니다.


## v2.9.0 사용자용 ZIP 구조
일반 사용자는 최상위의 `config-wizard.html`과 `run-remote-deploy.cmd`만 사용합니다. 나머지 코어/예제/문서는 `_internal/` 하위에 배치됩니다.

### 비밀번호 사전 검증
- `ELASTIC_PASSWORD`: 비워두면 자동 생성, 직접 입력 시 최소 6자
- `LOGSTASH_ES_PASSWORD`: 비워두면 자동 생성, 직접 입력 시 최소 6자
- `KIBANA_INITIAL_USER_PASSWORD`: 초기 사용자 생성 시 비워두면 자동 생성, 직접 입력 시 최소 6자
- `FTP_PASSWORD`: 비워두면 자동 생성, 직접 입력 시 8자 이상
- Kibana encryption key 3종: 비워두면 자동 생성, 직접 입력 시 최소 32자
Wizard에서 먼저 검증하고 Ubuntu의 `--validate` 단계에서도 같은 조건을 다시 검사합니다.

### 생성 파일을 Wizard 폴더에 저장
브라우저 보안상 HTML 파일의 로컬 폴더를 자동으로 쓰는 것은 허용되지 않습니다. 상단의 `📁 저장 폴더 연결`을 눌러 Config Wizard가 있는 폴더를 최초 1회 선택하면 이후 생성되는 SH/ENV 파일을 해당 폴더에 직접 저장합니다. 폴더 연결을 하지 않은 경우 `run-remote-deploy.cmd`가 Windows Downloads 폴더에서 가장 최근 생성된 one-click SH도 자동 탐색합니다.

## v2.9.3 원격 자동 인증
Config Wizard 10단계에서 Ubuntu SSH 계정/비밀번호와 sudo 비밀번호를 입력할 수 있습니다. 비밀번호를 입력하면 `run-remote-deploy.cmd`가 Windows OpenSSH의 SSH_ASKPASS와 `sudo -S`를 사용해 SCP/SSH/sudo 프롬프트를 자동 처리합니다. 로컬 One-Click SH의 배포 비밀번호 메타데이터는 Base64이며 암호화가 아니므로 로컬 파일 보관에 주의하십시오. 서버로 전송할 때는 배포 비밀번호 메타데이터를 제거한 임시 사본만 업로드합니다.

## v2.9.3 Elasticsearch 인증 복구
Elasticsearch 운영 설정 재시작 후 HTTP 리스너가 먼저 열리고 Security 인덱스가 늦게 준비되는 경우를 고려해 elastic 인증을 재시도합니다. 계속 실패하면 `elasticsearch-reset-password`로 관리자 인증을 복구하고, Wizard에서 지정한 `ELASTIC_PASSWORD`가 있으면 다시 적용한 후 재검증합니다.

## 기존 One-Click SH 다시 불러오기 (v2.9.3)

Config Wizard 상단의 **기존 SH 불러오기**를 선택하면 이전에 생성한 `elk-oneclick-install*.sh`에서 내장 `elk.env`와 Ubuntu 원격 배포 설정을 복원할 수 있습니다. 불러온 뒤 필요한 값만 수정하여 v2.9.3 SH로 다시 저장하세요.

