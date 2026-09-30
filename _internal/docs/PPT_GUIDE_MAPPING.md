# ELK 9.5.2 PPT 가이드 → Auto Installer v2.7 매핑

사용자가 제공한 PPT 스크린샷의 설치 순서를 Configuration Wizard의 **가이드 간단 설정**에 반영한 문서입니다.

| PPT 작업 | v2.7 자동화 |
|---|---|
| Elastic GPG Key 등록 / 9.x APT 저장소 | `APT_GPG_KEY_URL`, `APT_REPOSITORY_URL`, `ELASTIC_MAJOR`로 자동 구성 |
| Elasticsearch 설치 / enable / start | `INSTALL_ELASTICSEARCH`, `ENABLE_SERVICES_ON_BOOT` |
| elastic 비밀번호 변경 | `ELASTIC_PASSWORD`; 비우면 자동 생성 후 `secrets.env` 저장 |
| `network.host: 0.0.0.0` | `ES_NETWORK_HOST` |
| `action.destructive_requires_name: false` | `ES_ACTION_DESTRUCTIVE_REQUIRES_NAME`; 가이드 프리셋은 false, 일반 기본은 true |
| Kibana 설치 / Elasticsearch 연동 | Service Account Token을 자동 생성해 Kibana keystore에 저장 |
| Kibana `server.host` | 직접 접속=0.0.0.0 / Nginx 사용=127.0.0.1 |
| Nginx + Self-Signed HTTPS | `INSTALL_NGINX`, 80→443, TLS1.2/1.3, Reverse Proxy, `nginx -t` |
| Kibana 사용자 생성 | `KIBANA_CREATE_INITIAL_USER`와 사용자/Role 변수로 선택 자동화 |
| Logstash 설치 / enable | `INSTALL_LOGSTASH`, `ENABLE_SERVICES_ON_BOOT` |
| MAIN `/home/main_process/*.log.gz` | `GUIDE_MAIN_PROCESS_DIR`, `GUIDE_FILE_GLOB` |
| SSL `/home/ssl_process/*.log.gz` | `GUIDE_SSL_PROCESS_DIR`, `GUIDE_FILE_GLOB` |
| Logstash `mode => read` / 처리 후 delete | `proxysg_guide` 프로필에서 자동 생성 |
| `sincedb-main`, `sincedb-ssl` | `GUIDE_MAIN_SINCEDB`, `GUIDE_SSL_SINCEDB` |
| `discover_interval => 5`, `max_open_files => 1000` | Guide Logstash 변수로 반영 |
| vsftpd 설치 | `INSTALL_FTP_SERVER=true` |
| `elkftp` 계정 | `FTP_USER=elkftp`; 비밀번호 자동생성 가능 |
| PPT의 Active FTP Port 20 / SSL off | `FTP_ACTIVE_ENABLE`, `FTP_CONNECT_FROM_PORT_20`, `FTP_TLS_ENABLED` |
| `/home/main`, `/home/ssl` | Guide source 경로 |
| `/home/main_backup`, `/home/ssl_backup` | Guide backup 경로 |
| `/home/main_process`, `/home/ssl_process` | Guide process 경로 |
| `log_process.sh` | `guide-log-process.sh`; lock/copy/검증/원본삭제 로직 강화 |
| crontab 매일 03:00 | `GUIDE_PROCESS_CRON="0 3 * * *"`로 `/etc/cron.d/elk-guide-log-process` 생성 |
| Data View `main`, `proxy-main-*` | main/ssl Data View 자동 생성 |
| ILM `proxy-retention-policy` | Guide 정책명 자동 적용 |
| Index Template `proxy-index-template` | `proxy-main-*`, `proxy-ssl-*` 두 패턴 자동 적용 |
| 기존 인덱스에 lifecycle 설정 | `ILM_APPLY_TO_EXISTING=true` 선택 시 자동 적용 |

## 보존기간 차이

PPT 화면에는 `60d`가 보이지만, 사용자의 후속 요청에 따라 v2.7 가이드 프리셋과 기본 ELK 구성 모두 **90d**를 사용합니다.

## 가이드의 장애 항목 반영

Wizard 최종 단계에 다음 점검 항목을 요약했습니다.

- Kibana 연결 거부 → `server.host`, Kibana 서비스 상태
- Kibana 503 → Elasticsearch 상태 / JVM·RAM 확인
- Configure Elastic 화면에서 진행되지 않음 → Kibana 서비스 및 `kibana.yml`
- Logstash `E212: Can't open file for writing` → 설치 여부와 설정 디렉터리 권한
- Data View index pattern 오류 → 실제 `proxy-main-*`, `proxy-ssl-*` 인덱스 생성 여부
- Nginx → `nginx -t` / 서비스 상태 / Self-Signed 인증서 신뢰

자동 설치 스크립트는 설정 파일을 root 권한으로 생성하므로 PPT 장애 대응 예시의 `chmod 777 /etc/logstash/conf.d/`는 자동 적용하지 않습니다.
