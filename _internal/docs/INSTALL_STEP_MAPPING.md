# ELK 수동 설치 단계 → Auto Installer 매핑

수동 설치 순서를 Configuration Wizard의 **빠른 설정**에 반영한 문서입니다.

| 수동 작업 | 자동화 |
|---|---|
| Elastic GPG Key 등록 / 9.x APT 저장소 | `APT_GPG_KEY_URL`, `APT_REPOSITORY_URL`, `ELASTIC_MAJOR`로 자동 구성 |
| Elasticsearch 설치 / enable / start | `INSTALL_ELASTICSEARCH`, `ENABLE_SERVICES_ON_BOOT` |
| elastic 비밀번호 변경 | `ELASTIC_PASSWORD`; 비우면 자동 생성 후 `secrets.env` 저장 |
| `network.host: 0.0.0.0` | `ES_NETWORK_HOST` |
| `action.destructive_requires_name: false` | `ES_ACTION_DESTRUCTIVE_REQUIRES_NAME`; 빠른 설정은 false, 일반 기본은 true |
| Kibana 설치 / Elasticsearch 연동 | Service Account Token을 자동 생성해 Kibana keystore에 저장 |
| Kibana `server.host` | 직접 접속=0.0.0.0 / Nginx 사용=127.0.0.1 |
| Nginx + Self-Signed HTTPS | `INSTALL_NGINX`, 80→443, TLS1.2/1.3, Reverse Proxy, `nginx -t` |
| Kibana 사용자 생성 | `KIBANA_CREATE_INITIAL_USER`와 사용자/Role 변수로 선택 자동화 |
| Logstash 설치 / enable | `INSTALL_LOGSTASH`, `ENABLE_SERVICES_ON_BOOT` |
| MAIN `/home/main_process/*.log.gz` | `PROXYSG_MAIN_PROCESS_DIR`, `PROXYSG_FILE_GLOB` |
| SSL `/home/ssl_process/*.log.gz` | `PROXYSG_SSL_PROCESS_DIR`, `PROXYSG_FILE_GLOB` |
| (선택) Cloud `/home/cloud_process/*.log.gz` | `PROXYSG_CLOUD_ENABLED`, `PROXYSG_CLOUD_PROCESS_DIR`, `PROXYSG_FILE_GLOB` |
| Logstash `mode => read` / 처리 후 delete | `proxysg` 프로필에서 자동 생성 |
| `sincedb-main`, `sincedb-ssl`, (선택) `sincedb-cloud` | `PROXYSG_MAIN_SINCEDB`, `PROXYSG_SSL_SINCEDB`, `PROXYSG_CLOUD_SINCEDB` |
| `discover_interval => 5`, `max_open_files => 1000` | ProxySG Logstash 변수로 반영 |
| vsftpd 설치 | `INSTALL_FTP_SERVER=true` |
| `elkftp` 계정 | `FTP_USER=elkftp`; 비밀번호 자동생성 가능 |
| Active FTP Port 20 / SSL off | `FTP_ACTIVE_ENABLE`, `FTP_CONNECT_FROM_PORT_20`, `FTP_TLS_ENABLED` |
| `/home/main`, `/home/ssl` | ProxySG source 경로 |
| `/home/main_backup`, `/home/ssl_backup` | ProxySG backup 경로 |
| `/home/main_process`, `/home/ssl_process` | ProxySG process 경로 |
| `log_process.sh` | `proxysg-log-process.sh`; lock/copy/검증/원본삭제 로직 강화 |
| crontab 매일 03:00 | `PROXYSG_PROCESS_CRON="0 3 * * *"`로 `/etc/cron.d/elk-proxysg-log-process` 생성 |
| Data View `main`, `proxy-main-*` | main/ssl Data View 자동 생성 |
| ILM `proxy-retention-policy` | ProxySG 정책명 자동 적용 |
| Index Template `proxy-index-template` | `proxy-main-*`, `proxy-ssl-*` 두 패턴 자동 적용 |
| 기존 인덱스에 lifecycle 설정 | `ILM_APPLY_TO_EXISTING=true` 선택 시 자동 적용 |
| HTML 점검 리포트 / 웹 Viewer | `elk-report` → `/var/lib/elk-report/report.html`, `elk-report-web`(기본 8088/tcp) |
| OneClick 구성 일치 점검 | `elk-report --only cfg`, `elk-check`가 패키지·sysctl·Heap·pipeline·도구·cron 확인 |

## 보존기간 차이

ILM 보존기간은 빠른 설정과 기본 ELK 구성 모두 **90d**를 사용합니다.

## 장애 점검 항목

Wizard 최종 단계에 다음 점검 항목을 요약했습니다.

- Kibana 연결 거부 → `server.host`, Kibana 서비스 상태
- Kibana 503 → Elasticsearch 상태 / JVM·RAM 확인
- Configure Elastic 화면에서 진행되지 않음 → Kibana 서비스 및 `kibana.yml`
- Logstash `E212: Can't open file for writing` → 설치 여부와 설정 디렉터리 권한
- Data View index pattern 오류 → 실제 `proxy-main-*`, `proxy-ssl-*` 인덱스 생성 여부
- Nginx → `nginx -t` / 서비스 상태 / Self-Signed 인증서 신뢰

자동 설치 스크립트는 설정 파일을 root 권한으로 생성하므로 장애 대응 예시로 흔한 `chmod 777 /etc/logstash/conf.d/`는 자동 적용하지 않습니다.

## v2.9.5 점검 웹

- `sudo elk-report` 실행 시 터미널 출력과 HTML 리포트를 동시에 갱신합니다.
- `elk-report-web`은 HTML을 제공하고 `/api/run`에서 허용된 `elk-report` 옵션만 실행합니다.
- 기본 URL은 `http://서버IP:8088/`이며 `ELK_REPORT_WEB_HOST`, `ELK_REPORT_WEB_PORT`, `UFW_REPORT_ALLOWED_CIDRS`로 제어합니다.
