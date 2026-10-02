#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ELK Auto Installer v2.9.2 (keystore + kibana-token hotfix)
# Target: Ubuntu 22.04 / 24.04, Elastic Stack 9.x
# Usage: sudo bash install-elk.sh ./elk.env

ENV_FILE="${1:-./elk.env}"
RUN_MODE="${2:-install}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] root 권한이 필요합니다. sudo로 실행하세요." >&2
  exit 1
fi
if [[ ! -f "$ENV_FILE" ]]; then
  echo "[ERROR] 환경파일을 찾을 수 없습니다: $ENV_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

# ----------------------------- 이전 버전 호환 -----------------------------
# 이름이 바뀐 환경변수(GUIDE_* -> PROXYSG_*)와 프로필 값(proxysg_guide -> proxysg)을 이어받는다.
# 새 이름이 이미 지정되어 있으면 그 값을 우선한다. (예전 설치 파일/elk.env를 그대로 써도 설정이 사라지지 않게 하기 위한 처리)
while IFS= read -r _old_name; do
  case "$_old_name" in
    GUIDE_PROXY_FLOW_ENABLED) _new_name="PROXYSG_FLOW_ENABLED" ;;
    GUIDE_PROXY_CSV_FILTER_ENABLED) _new_name="PROXYSG_CSV_FILTER_ENABLED" ;;
    *) _new_name="PROXYSG_${_old_name#GUIDE_}" ;;
  esac
  if [[ -z "${!_new_name+x}" ]]; then printf -v "$_new_name" '%s' "${!_old_name}"; fi
done < <(compgen -A variable GUIDE_ || true)
[[ "${PROXYSG_PROCESS_SCRIPT:-}" == "/usr/local/sbin/elk-guide-log-process" ]] && PROXYSG_PROCESS_SCRIPT="/usr/local/sbin/elk-proxysg-log-process"
[[ "${PROXYSG_PROCESS_LOG:-}" == "/var/log/elk-guide-log-process.log" ]] && PROXYSG_PROCESS_LOG="/var/log/elk-proxysg-log-process.log"
[[ "${LOGSTASH_PROFILE:-}" == "proxysg_guide" ]] && LOGSTASH_PROFILE="proxysg"
unset _old_name _new_name

# ----------------------------- defaults -----------------------------
: "${INSTALL_ELASTICSEARCH:=true}"
: "${INSTALL_KIBANA:=true}"
: "${INSTALL_LOGSTASH:=true}"
: "${ELASTIC_MAJOR:=9.x}"
: "${ELASTIC_VERSION:=}"
: "${APT_REPOSITORY_URL:=https://artifacts.elastic.co/packages}"
: "${APT_GPG_KEY_URL:=https://artifacts.elastic.co/GPG-KEY-elasticsearch}"
: "${APT_PROXY:=}"
: "${HTTP_PROXY:=}"
: "${HTTPS_PROXY:=}"
: "${NO_PROXY:=127.0.0.1,localhost}"

: "${SET_HOSTNAME:=false}"
: "${SYSTEM_HOSTNAME:=elk01}"
: "${TIMEZONE:=Asia/Seoul}"
: "${ENABLE_NTP:=true}"
: "${DISABLE_SWAP:=true}"
: "${VM_MAX_MAP_COUNT:=1048576}"
: "${SYSTEM_SWAPPINESS:=1}"
: "${INSTALL_LOG:=/var/log/elk-auto-install.log}"
: "${STATE_DIR:=/root/.elk-auto-installer}"
: "${SECRETS_FILE:=${STATE_DIR}/secrets.env}"
: "${BACKUP_DIR:=${STATE_DIR}/backups}"

# 설치 화면 진행률 표시
: "${INSTALL_PROGRESS_ENABLED:=true}"
: "${INSTALL_PROGRESS_BAR_WIDTH:=30}"
: "${APT_PROGRESS_ENABLED:=true}"
: "${APT_RETRIES:=10}"
: "${APT_CONNECT_TIMEOUT:=30}"

: "${ES_CLUSTER_NAME:=elk-cluster}"
: "${ES_NODE_NAME:=elk01}"
: "${ES_NETWORK_HOST:=0.0.0.0}"
: "${ES_HTTP_PORT:=9200}"
: "${ES_TRANSPORT_PORT:=9300}"
: "${ES_ACTION_DESTRUCTIVE_REQUIRES_NAME:=true}"
: "${ES_PATH_DATA:=/var/lib/elasticsearch}"
: "${ES_PATH_LOGS:=/var/log/elasticsearch}"
: "${ES_DISCOVERY_MODE:=single-node}"
: "${ES_DISCOVERY_SEED_HOSTS:=}"
: "${ES_CLUSTER_INITIAL_MASTER_NODES:=}"
: "${ES_SECURITY_ENABLED:=true}"
: "${ES_ENROLLMENT_ENABLED:=true}"
: "${ES_HTTP_TLS_ENABLED:=true}"
: "${ES_TRANSPORT_TLS_ENABLED:=true}"
: "${ELASTIC_USERNAME:=elastic}"
: "${ELASTIC_PASSWORD:=}"
: "${ES_HEAP_MODE:=auto}"
: "${ES_HEAP_MIN:=16g}"
: "${ES_HEAP_MAX:=16g}"
: "${ES_BOOTSTRAP_MEMORY_LOCK:=false}"
: "${ES_LIMIT_NOFILE:=65535}"
: "${ES_LIMIT_NPROC:=4096}"
: "${ES_EXTRA_CONFIG_FILE:=}"
: "${ES_DISK_WATERMARK_LOW:=85%}"
: "${ES_DISK_WATERMARK_HIGH:=90%}"
: "${ES_DISK_WATERMARK_FLOOD_STAGE:=95%}"
: "${ES_CLUSTER_INFO_UPDATE_INTERVAL:=30s}"

: "${KIBANA_SERVER_NAME:=elk-kibana}"
: "${KIBANA_SERVER_HOST:=0.0.0.0}"
: "${KIBANA_SERVER_PORT:=5601}"
: "${KIBANA_PUBLIC_BASE_URL:=}"
: "${KIBANA_ES_HOST:=}"
: "${KIBANA_ES_SSL_VERIFICATION_MODE:=full}"
: "${KIBANA_SERVICE_TOKEN_NAME:=elk-auto-kibana}"
: "${KIBANA_SECURITY_ENCRYPTION_KEY:=}"
: "${KIBANA_REPORTING_ENCRYPTION_KEY:=}"
: "${KIBANA_SAVED_OBJECTS_ENCRYPTION_KEY:=}"
: "${KIBANA_LOG_LEVEL:=info}"
: "${KIBANA_CREATE_DATA_VIEW:=true}"
: "${KIBANA_DATA_VIEW_NAME:=ELK Logs}"
: "${KIBANA_DATA_VIEW_TIME_FIELD:=@timestamp}"
: "${KIBANA_DATA_VIEW_ALLOW_NO_INDEX:=true}"
: "${KIBANA_CREATE_INITIAL_USER:=false}"
: "${KIBANA_INITIAL_USER_NAME:=}"
: "${KIBANA_INITIAL_USER_PASSWORD:=}"
: "${KIBANA_INITIAL_USER_ROLES:=viewer}"
: "${KIBANA_EXTRA_CONFIG_FILE:=}"
# v2.9.4: Kibana 로그인 사용 여부(false면 읽기 전용 익명 접속) / 세션 유휴 만료(비우면 Kibana 기본값)
: "${KIBANA_LOGIN_ENABLED:=true}"
: "${KIBANA_SESSION_IDLE_TIMEOUT:=}"

: "${INSTALL_NGINX:=false}"
: "${NGINX_SERVER_NAME:=_}"
: "${NGINX_HTTP_PORT:=80}"
: "${NGINX_HTTPS_PORT:=443}"
: "${NGINX_REDIRECT_HTTP_TO_HTTPS:=true}"
: "${NGINX_DISABLE_DEFAULT_SITE:=true}"
: "${NGINX_PROXY_HOST:=127.0.0.1}"
: "${NGINX_PROXY_PORT:=}"
: "${NGINX_CLIENT_MAX_BODY_SIZE:=100m}"
: "${NGINX_TLS_MODE:=selfsigned}"
: "${NGINX_TLS_CERT_FILE:=/etc/ssl/certs/kibana-selfsigned.crt}"
: "${NGINX_TLS_KEY_FILE:=/etc/ssl/private/kibana-selfsigned.key}"
: "${NGINX_TLS_CN:=}"
: "${NGINX_TLS_DAYS:=3650}"
: "${NGINX_TLS_PROTOCOLS:=TLSv1.2 TLSv1.3}"
: "${NGINX_TLS_CIPHERS:=HIGH:!aNULL:!MD5}"

: "${LOGSTASH_NODE_NAME:=elk-logstash}"
: "${LOGSTASH_PATH_DATA:=/var/lib/logstash}"
: "${LOGSTASH_PATH_LOGS:=/var/log/logstash}"
: "${LOGSTASH_PIPELINE_ID:=main}"
: "${LOGSTASH_PIPELINE_FILE:=/etc/logstash/conf.d/10-main.conf}"
: "${LOGSTASH_PROFILE:=generic}"
: "${LOGSTASH_HEAP_MIN:=2g}"
: "${LOGSTASH_HEAP_MAX:=2g}"
: "${LOGSTASH_PIPELINE_WORKERS:=0}"
: "${LOGSTASH_PIPELINE_BATCH_SIZE:=125}"
: "${LOGSTASH_PIPELINE_BATCH_DELAY:=50}"
: "${LOGSTASH_CONFIG_RELOAD_AUTOMATIC:=true}"
: "${LOGSTASH_CONFIG_RELOAD_INTERVAL:=3s}"
: "${LOGSTASH_QUEUE_TYPE:=persisted}"
: "${LOGSTASH_QUEUE_MAX_BYTES:=4gb}"
: "${LOGSTASH_QUEUE_PAGE_CAPACITY:=64mb}"
: "${LOGSTASH_QUEUE_DRAIN:=false}"
: "${LOGSTASH_DEAD_LETTER_QUEUE:=true}"
: "${LOGSTASH_DLQ_MAX_BYTES:=1gb}"
: "${LOGSTASH_API_ENABLED:=true}"
: "${LOGSTASH_API_HOST:=127.0.0.1}"
: "${LOGSTASH_API_PORT:=9600}"
: "${LOGSTASH_ES_USERNAME:=logstash_internal}"
: "${LOGSTASH_ES_PASSWORD:=}"
: "${LOGSTASH_ES_ROLE:=logstash_writer}"
: "${LOGSTASH_ES_HOST:=}"
: "${LOGSTASH_EXTRA_CONFIG_FILE:=}"

: "${LS_TCP_ENABLED:=true}"
: "${LS_TCP_HOST:=0.0.0.0}"
: "${LS_TCP_PORT:=5514}"
: "${LS_TCP_CODEC:=plain}"
: "${LS_UDP_ENABLED:=false}"
: "${LS_UDP_HOST:=0.0.0.0}"
: "${LS_UDP_PORT:=5514}"
: "${LS_UDP_CODEC:=plain}"
: "${LS_SYSLOG_ENABLED:=false}"
: "${LS_SYSLOG_HOST:=0.0.0.0}"
: "${LS_SYSLOG_PORT:=5515}"
: "${LS_BEATS_ENABLED:=false}"
: "${LS_BEATS_HOST:=0.0.0.0}"
: "${LS_BEATS_PORT:=5044}"
: "${LS_HTTP_ENABLED:=false}"
: "${LS_HTTP_HOST:=0.0.0.0}"
: "${LS_HTTP_PORT:=8080}"
: "${LS_HTTP_CODEC:=json}"
: "${LS_FILE_ENABLED:=false}"
: "${LS_FILE_PATHS:=/data/logs/*.log}"
: "${LS_FILE_EXCLUDE:=*.gz,*.zip,*.xz,*.zst}"
: "${LS_FILE_MODE:=tail}"
: "${LS_FILE_START_POSITION:=beginning}"
: "${LS_FILE_SINCEDB_PATH:=/var/lib/logstash/.sincedb-main}"
: "${LS_FILE_CODEC:=plain}"
: "${LS_FILE_IGNORE_OLDER:=}"
: "${LS_FILE_CLOSE_OLDER:=5m}"
: "${LS_FILE_COMPLETED_ACTION:=log}"
: "${LS_FILE_COMPLETED_LOG_PATH:=/var/log/logstash/completed-files.log}"

: "${INSTALL_FTP_SERVER:=true}"
: "${FTP_PACKAGE:=vsftpd}"
: "${FTP_LISTEN_ADDRESS:=0.0.0.0}"
: "${FTP_LISTEN_PORT:=21}"
: "${FTP_USER:=elkftp}"
: "${FTP_PASSWORD:=}"
: "${FTP_GROUP:=logstash}"
: "${FTP_USER_SHELL:=/usr/sbin/nologin}"
: "${FTP_ROOT_DIR:=/log}"
: "${FTP_UPLOAD_DIR:=/log/incoming}"
: "${FTP_ROOT_MODE:=0755}"
: "${FTP_UPLOAD_MODE:=2770}"
: "${FTP_LOCAL_UMASK:=0007}"
: "${FTP_CHROOT_LOCAL_USER:=true}"
: "${FTP_ALLOW_WRITEABLE_CHROOT:=false}"
: "${FTP_ALLOW_ANONYMOUS:=false}"
: "${FTP_DOWNLOAD_ENABLE:=false}"
: "${FTP_BANNER:=ELK Log Upload FTP}"
: "${FTP_ACTIVE_ENABLE:=false}"
: "${FTP_CONNECT_FROM_PORT_20:=false}"
: "${FTP_PASV_ENABLE:=true}"
: "${FTP_PASV_MIN_PORT:=40000}"
: "${FTP_PASV_MAX_PORT:=40100}"
: "${FTP_PASV_ADDRESS:=}"
: "${FTP_MAX_CLIENTS:=20}"
: "${FTP_MAX_PER_IP:=5}"
: "${FTP_IDLE_SESSION_TIMEOUT:=600}"
: "${FTP_DATA_CONNECTION_TIMEOUT:=120}"
: "${FTP_LOG_FILE:=/var/log/vsftpd.log}"
: "${FTP_TLS_ENABLED:=false}"
: "${FTP_TLS_FORCE:=true}"
: "${FTP_TLS_CERT_FILE:=/etc/ssl/certs/elk-vsftpd.crt}"
: "${FTP_TLS_KEY_FILE:=/etc/ssl/private/elk-vsftpd.key}"
: "${FTP_TLS_CN:=}"
: "${FTP_TLS_DAYS:=3650}"
: "${FTP_TLS_REQUIRE_REUSE:=false}"
: "${FTP_INTEGRATE_FILE_INGEST:=true}"

: "${PROXYSG_FLOW_ENABLED:=false}"
: "${PROXYSG_CLOUD_ENABLED:=false}"
: "${PROXYSG_MAIN_SOURCE_DIR:=/home/main}"
: "${PROXYSG_SSL_SOURCE_DIR:=/home/ssl}"
: "${PROXYSG_CLOUD_SOURCE_DIR:=/home/cloud}"
: "${PROXYSG_MAIN_BACKUP_DIR:=/home/main_backup}"
: "${PROXYSG_SSL_BACKUP_DIR:=/home/ssl_backup}"
: "${PROXYSG_CLOUD_BACKUP_DIR:=/home/cloud_backup}"
: "${PROXYSG_MAIN_PROCESS_DIR:=/home/main_process}"
: "${PROXYSG_SSL_PROCESS_DIR:=/home/ssl_process}"
: "${PROXYSG_CLOUD_PROCESS_DIR:=/home/cloud_process}"
: "${PROXYSG_FILE_GLOB:=*.log.gz}"
: "${PROXYSG_DIR_MODE:=0775}"
: "${PROXYSG_PROCESS_SCRIPT:=/usr/local/sbin/elk-proxysg-log-process}"
: "${PROXYSG_PROCESS_LOG:=/var/log/elk-proxysg-log-process.log}"
: "${PROXYSG_PROCESS_CRON:=0 3 * * *}"
: "${PROXYSG_MAIN_SINCEDB:=/var/lib/logstash/sincedb-main}"
: "${PROXYSG_SSL_SINCEDB:=/var/lib/logstash/sincedb-ssl}"
: "${PROXYSG_CLOUD_SINCEDB:=/var/lib/logstash/sincedb-cloud}"
: "${PROXYSG_LOGSTASH_DISCOVER_INTERVAL:=5}"
: "${PROXYSG_LOGSTASH_MAX_OPEN_FILES:=1000}"
: "${PROXYSG_CSV_FILTER_ENABLED:=true}"
: "${PROXYSG_MAIN_LOG_FORMAT:=date time time-taken c-ip cs-username cs-auth-group s-supplier-name s-supplier-ip s-supplier-country s-supplier-failures x-exception-id sc-filter-result cs-categories cs(Referer)  sc-status s-action cs-method rs(Content-Type) cs-uri-scheme cs-host cs-uri-port cs-uri-path cs-uri-query cs-uri-extension cs(User-Agent) s-ip sc-bytes cs-bytes x-virus-id cs-threat-source cs-threat-id rs-threat-source rs-threat-id x-bluecoat-application-name x-bluecoat-application-operation x-bluecoat-application-groups cs-threat-risk x-bluecoat-access-security-policy-action x-bluecoat-access-security-policy-reason x-bluecoat-transaction-uuid x-icap-reqmod-header(X-ICAP-Metadata) x-icap-respmod-header(X-ICAP-Metadata)}"
: "${PROXYSG_SSL_LOG_FORMAT:=date time time-taken c-ip cs-username cs-auth-group s-supplier-name s-supplier-ip s-supplier-country s-supplier-failures x-exception-id sc-filter-result cs-categories sc-status s-action cs-method rs(Content-Type) cs-uri-scheme cs-host cs-uri-port cs-uri-extension cs(User-Agent) s-ip sc-bytes cs-bytes x-virus-id cs-threat-source cs-threat-id rs-threat-source rs-threat-id x-rs-certificate-observed-errors x-cs-ocsp-error x-rs-ocsp-error x-rs-connection-negotiated-cipher-strength x-rs-certificate-hostname x-rs-certificate-hostname-category cs-threat-risk x-rs-certificate-hostname-threat-risk x-bluecoat-access-security-policy-action x-bluecoat-access-security-policy-reason}"
: "${PROXYSG_CLOUD_LOG_FORMAT:=cs-method cs-user-domain cs-x-requested-with x-rs-ocsp-error cs-icap-error-details c-ip-version x-cs-ocsp-error sc-status x-action-result x-client-device-id x-rs-certificate-hostname-categories s-action x-rs-certificate-hostname-threat-risk x-bluecoat-reference-ids cs-bytes x-rs-connection-negotiated-ssl-version rs-icap-status x-bluecoat-reference-id x-cs-connection-negotiated-cipher-size c-port x-bluecoat-request-tenant-id sc-bytes x-bluecoat-placeholder x-rs-connection-negotiated-cipher cs-uri-port x-client-agent-sw cs-threat-risk x-cs-connection-negotiated-ssl-version r-supplier-country cs-user-agent x-bluecoat-application-operation x-file-details r-ip cs-icap-status cs-host x-client-device-name cs-uri-path sc-filter-result x-request-origin rs-icap-error-details x-cs-certificate-subject x-virus-id date x-bluecoat-location-name cs-uri-query x-cs-client-ip-country x-rs-certificate-validate-status x-client-os cs-categories x-icap-respmod-header(X-ICAP-Metadata) x-exception-id x-bluecoat-access-type x-data-leak-detected cs-uri-extension time-taken x-client-device-type x-cs-public-ip x-data-types x-bluecoat-transaction-uuid x-bluecoat-application-name cs-uri-scheme x-rs-certificate-hostname x-cs-connection-negotiated-cipher rs-content-type x-client-agent-type cs-userdn x-rs-certificate-observed-errors r-ip-version x-symc-inspected s-ip x-icap-reqmod-header(X-ICAP-Metadata) cs-auth-groups time x-client-agent-ip x-rs-connection-negotiated-cipher-size}"
: "${PROXYSG_MAIN_INDEX_PREFIX:=proxy-main}"
: "${PROXYSG_SSL_INDEX_PREFIX:=proxy-ssl}"
: "${PROXYSG_CLOUD_INDEX_PREFIX:=proxy-cloud}"
: "${PROXYSG_MAIN_DATA_VIEW_NAME:=main}"
: "${PROXYSG_SSL_DATA_VIEW_NAME:=ssl}"
: "${PROXYSG_CLOUD_DATA_VIEW_NAME:=cloud}"
: "${PROXYSG_ILM_POLICY_NAME:=proxy-retention-policy}"
: "${PROXYSG_INDEX_TEMPLATE_NAME:=proxy-index-template}"

: "${FILE_INGEST_MANAGER_ENABLED:=true}"
: "${FILE_INGEST_SOURCE_DIRS:=/log/incoming}"
: "${FILE_INGEST_STAGING_DIR:=/var/lib/elk-file-ingest/staging}"
: "${FILE_INGEST_STATE_DIR:=/var/lib/elk-file-ingest/state}"
: "${FILE_INGEST_BACKUP_DIR:=/backup/logs}"
: "${FILE_INGEST_DUPLICATE_DIR:=/backup/logs/duplicates}"
: "${FILE_INGEST_QUARANTINE_DIR:=/backup/logs/quarantine}"
: "${FILE_INGEST_COMPLETED_LOG:=/var/log/logstash/completed-files.log}"
: "${FILE_INGEST_EXTENSIONS:=log,txt,json,csv,gz,xz,zst,bz2}"
: "${FILE_INGEST_RECURSIVE:=true}"
: "${FILE_INGEST_MIN_AGE_SECONDS:=60}"
: "${FILE_INGEST_MAX_FILES_PER_RUN:=20}"
: "${FILE_INGEST_MAX_SOURCE_FILE_BYTES:=0}"
: "${FILE_INGEST_MIN_STAGING_FREE_GB:=20}"
: "${FILE_INGEST_DEDUPE_MODE:=content_sha256}"
: "${FILE_INGEST_DUPLICATE_ACTION:=archive}"
: "${FILE_INGEST_PLAIN_BACKUP_COMPRESSION:=zstd}"
: "${FILE_INGEST_COMPRESSION_LEVEL:=3}"
: "${FILE_INGEST_PRESERVE_RELATIVE_PATH:=true}"
: "${FILE_INGEST_DELETE_STAGING_AFTER_COMPLETE:=true}"
: "${FILE_INGEST_BACKUP_RETENTION_DAYS:=0}"
: "${FILE_INGEST_DUPLICATE_RETENTION_DAYS:=0}"
: "${FILE_INGEST_QUARANTINE_RETENTION_DAYS:=0}"
: "${FILE_INGEST_SCAN_INTERVAL:=1min}"
: "${FILE_INGEST_TIMER_RANDOM_DELAY:=10s}"
: "${FILE_INGEST_SOURCE_OWNER:=root}"
: "${FILE_INGEST_SOURCE_GROUP:=logstash}"
: "${FILE_INGEST_SOURCE_MODE:=0775}"
: "${FILE_INGEST_LOG:=/var/log/elk-file-ingest.log}"
: "${FILE_INGEST_LOCK_FILE:=/run/lock/elk-file-ingest.lock}"

: "${HEALTH_MONITOR_ENABLED:=true}"
: "${HEALTH_MONITOR_INTERVAL:=5min}"
: "${HEALTH_MONITOR_RANDOM_DELAY:=20s}"
: "${HEALTH_MONITOR_LOG:=/var/log/elk-health-monitor.log}"
: "${HEALTH_DISK_WARN_PERCENT:=85}"
: "${HEALTH_DISK_CRIT_PERCENT:=92}"
: "${HEALTH_AUTO_PAUSE_FILE_INGEST_ON_CRITICAL:=false}"
: "${LS_PARSE_JSON_MESSAGE:=false}"
: "${LS_JSON_SOURCE_FIELD:=message}"
: "${LS_JSON_TARGET_FIELD:=}"
: "${LS_DATE_SOURCE_FIELD:=}"
: "${LS_DATE_MATCH:=}"
: "${LS_DATE_TARGET_FIELD:=@timestamp}"
: "${LS_DATE_TIMEZONE:=Asia/Seoul}"
: "${LS_DROP_EMPTY_MESSAGE:=false}"
: "${LS_CUSTOM_FILTER_FILE:=}"
: "${LS_STDOUT_DEBUG:=false}"

: "${INDEX_PREFIX:=network-log}"
: "${INDEX_MODE:=daily}"
: "${INDEX_DATE_PATTERN:=YYYY.MM.dd}"
: "${INDEX_TEMPLATE_NAME:=${INDEX_PREFIX}-template}"
: "${INDEX_TEMPLATE_PATTERNS:=}"
: "${INDEX_TEMPLATE_PRIORITY:=200}"
: "${INDEX_NUMBER_OF_SHARDS:=1}"
: "${INDEX_NUMBER_OF_REPLICAS:=0}"
: "${INDEX_REFRESH_INTERVAL:=5s}"
: "${INDEX_TOTAL_FIELDS_LIMIT:=2000}"
: "${INDEX_MAPPING_FILE:=}"
: "${ILM_POLICY_NAME:=${INDEX_PREFIX}-ilm}"
: "${ILM_DELETE_ENABLED:=true}"
: "${ILM_DELETE_MIN_AGE:=90d}"
: "${ILM_APPLY_TO_EXISTING:=false}"
: "${ILM_EXISTING_INDEX_PATTERNS:=}"
: "${ILM_WARM_ENABLED:=false}"
: "${ILM_WARM_MIN_AGE:=7d}"
: "${ILM_WARM_READONLY:=true}"
: "${ILM_WARM_FORCE_MERGE:=false}"
: "${ILM_WARM_FORCE_MERGE_SEGMENTS:=1}"
: "${ILM_ROLLOVER_ALIAS:=${INDEX_PREFIX}}"
: "${ILM_ROLLOVER_PATTERN:=000001}"
: "${ILM_ROLLOVER_MAX_AGE:=1d}"
: "${ILM_ROLLOVER_MAX_PRIMARY_SHARD_SIZE:=50gb}"
: "${ILM_ROLLOVER_MAX_DOCS:=}"

: "${SNAPSHOT_REPO_ENABLED:=false}"
: "${SNAPSHOT_REPO_NAME:=local-backup}"
: "${SNAPSHOT_REPO_PATH:=/backup/elasticsearch}"
: "${SNAPSHOT_COMPRESS:=true}"
: "${SNAPSHOT_READONLY:=false}"
: "${SLM_POLICY_ENABLED:=false}"
: "${SLM_POLICY_NAME:=daily-snapshot}"
: "${SLM_SCHEDULE:=0 30 1 * * ?}"
: "${SLM_SNAPSHOT_NAME:=<elk-snap-{now/d}>}"
: "${SLM_INDICES:=${INDEX_PREFIX}-*}"
: "${SLM_IGNORE_UNAVAILABLE:=true}"
: "${SLM_INCLUDE_GLOBAL_STATE:=false}"
: "${SLM_RETENTION_EXPIRE_AFTER:=30d}"
: "${SLM_RETENTION_MIN_COUNT:=3}"
: "${SLM_RETENTION_MAX_COUNT:=50}"

: "${UFW_MANAGE:=false}"
: "${UFW_ENABLE_IF_INACTIVE:=false}"
: "${UFW_KIBANA_ALLOWED_CIDRS:=}"
: "${UFW_NGINX_ALLOWED_CIDRS:=}"
: "${UFW_ELASTICSEARCH_ALLOWED_CIDRS:=}"
: "${UFW_LOGSTASH_ALLOWED_CIDRS:=}"
: "${UFW_FTP_ALLOWED_CIDRS:=}"
: "${ENABLE_SERVICES_ON_BOOT:=true}"
: "${START_SERVICES_AFTER_INSTALL:=true}"
: "${WAIT_TIMEOUT_SECONDS:=180}"
: "${CREATE_TEST_EVENT:=false}"
: "${TEST_EVENT_MESSAGE:=ELK auto installer test event}"
: "${POST_INSTALL_SCRIPT:=}"

mkdir -p "$STATE_DIR" "$BACKUP_DIR" "$(dirname "$INSTALL_LOG")"
touch "$INSTALL_LOG"
chmod 600 "$INSTALL_LOG"

# 설치 시작 시 실제 제어 TTY가 있는 경우에만 fd 9를 확보한다.
# systemd-run/nohup/cron 환경에서는 /dev/tty 노드가 존재하고 -w 검사도 통과할 수 있지만
# 실제 open()은 ENXIO("No such device or address")로 실패할 수 있으므로
# 이후에는 /dev/tty를 다시 직접 열지 않는다.
PROGRESS_TTY_FD=""
if [[ -t 1 ]]; then
  if exec 9>/dev/tty 2>/dev/null; then
    PROGRESS_TTY_FD="9"
  fi
fi

exec > >(tee -a "$INSTALL_LOG") 2>&1

# ----------------------------- helpers -----------------------------
_ts() { date '+%Y-%m-%d %H:%M:%S'; }
log()  { echo "[$(_ts)] [INFO] $*"; }
warn() { echo "[$(_ts)] [WARN] $*"; }
die()  { echo "[$(_ts)] [ERROR] $*" >&2; exit 1; }
istrue() { [[ "${1,,}" =~ ^(1|true|yes|y|on)$ ]]; }


progress_tty() {
  # 실제 제어 TTY가 확보된 경우에만 그 fd로 갱신한다.
  # 분리 실행(systemd-run)에서는 일반 stdout으로 기록하여 원격 모니터가 읽을 수 있게 한다.
  if [[ "${PROGRESS_TTY_FD:-}" == "9" ]]; then
    printf '%b' "$*" >&9
  else
    printf '%b' "$*"
  fi
}

progress_bar_line() {
  local pct_raw="${1:-0}" label="${2:-진행 중}" detail="${3:-}" width="${INSTALL_PROGRESS_BAR_WIDTH:-30}"
  istrue "$INSTALL_PROGRESS_ENABLED" || return 0
  local pct filled empty bar1 bar2
  pct="${pct_raw%%.*}"
  [[ "$pct" =~ ^[0-9]+$ ]] || pct=0
  (( pct < 0 )) && pct=0
  (( pct > 100 )) && pct=100
  [[ "$width" =~ ^[0-9]+$ ]] || width=30
  (( width < 10 )) && width=10
  (( width > 60 )) && width=60
  filled=$(( pct * width / 100 ))
  empty=$(( width - filled ))
  printf -v bar1 '%*s' "$filled" ''
  printf -v bar2 '%*s' "$empty" ''
  bar1="${bar1// /#}"
  bar2="${bar2// /-}"
  # 실제 터미널에서는 한 줄을 갱신하고, systemd/nohup 같은 비대화형 실행에서는
  # 원격 모니터가 진행률을 읽을 수 있도록 각 상태를 새 줄로 기록한다.
  if [[ "${PROGRESS_TTY_FD:-}" == "9" ]]; then
    progress_tty "\r\033[K[${label}] [${bar1}${bar2}] ${pct}% ${detail}"
  else
    printf '[%s] [%s%s] %s%% %s\n' "$label" "$bar1" "$bar2" "$pct" "$detail"
  fi
}

progress_done_line() {
  local label="${1:-완료}" detail="${2:-}"
  istrue "$INSTALL_PROGRESS_ENABLED" || return 0
  progress_bar_line 100 "$label" "$detail"
  progress_tty "\n"
}

overall_progress() {
  local pct="${1:-0}" detail="${2:-}"
  istrue "$INSTALL_PROGRESS_ENABLED" || return 0
  progress_bar_line "$pct" "전체" "$detail"
  progress_tty "\n"
}

apt_status_parser() {
  # APT::Status-Fd 형식: dlstatus:id:percent:text / pmstatus:pkg:percent:text
  local phase="${1:-APT}" line kind ident pct msg last_key=""
  while IFS= read -r line; do
    kind="${line%%:*}"
    case "$kind" in
      dlstatus|pmstatus)
        IFS=':' read -r kind ident pct msg <<< "$line"
        local p_int="${pct%%.*}" key
        [[ "$p_int" =~ ^[0-9]+$ ]] || p_int=0
        if [[ "$kind" == "dlstatus" ]]; then
          key="D:${p_int}:${msg}"
          if [[ "$key" != "$last_key" ]]; then
            progress_bar_line "$p_int" "다운로드" "${phase} - ${msg}"
            last_key="$key"
          fi
        else
          key="I:${p_int}:${msg}"
          if [[ "$key" != "$last_key" ]]; then
            progress_bar_line "$p_int" "설치" "${phase} - ${msg}"
            last_key="$key"
          fi
        fi
        ;;
      pmerror)
        progress_tty "\n[APT ERROR] ${line}\n"
        ;;
    esac
  done
  istrue "$INSTALL_PROGRESS_ENABLED" && progress_tty "\n"
}

apt_install_progress() {
  local label="$1"; shift
  local -a pkgs=("$@")
  if ! istrue "$APT_PROGRESS_ENABLED"; then
    DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries="${APT_RETRIES}" -o Acquire::http::Timeout="${APT_CONNECT_TIMEOUT}" -o Acquire::https::Timeout="${APT_CONNECT_TIMEOUT}" install -y "${pkgs[@]}"
    return $?
  fi
  log "$label 패키지 다운로드/설치 시작: ${pkgs[*]}"
  # fd 3은 사람이 보기 좋은 다운로드/설치 percentage를 제공한다.
  # 일반 apt 출력은 기존 로그와 화면에 그대로 남기고, status fd만 진행률 바로 표시한다.
  DEBIAN_FRONTEND=noninteractive apt-get \
    -o APT::Status-Fd=3 \
    -o Dpkg::Progress-Fancy=0 \
    -o APT::Color=0 \
    -o Acquire::Retries="${APT_RETRIES}" \
    -o Acquire::http::Timeout="${APT_CONNECT_TIMEOUT}" \
    -o Acquire::https::Timeout="${APT_CONNECT_TIMEOUT}" \
    install -y "${pkgs[@]}" \
    3> >(apt_status_parser "$label")
  progress_done_line "설치" "$label 완료"
}

backup_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  local safe ts
  safe="$(echo "$f" | sed 's#/#_#g; s/^_//')"
  ts="$(date '+%Y%m%d-%H%M%S')"
  cp -a "$f" "$BACKUP_DIR/${safe}.${ts}.bak"
}

# ---- v2.9.4: ProxySG MAIN/SSL 로그 포맷(ELFF) -> Logstash csv columns --------------------------------
# 규칙: date->log_date, time->log_time, 그 밖의 필드는 소문자로 바꾸고 영문/숫자 이외의 연속 문자를 _ 로 바꿈
#       (예: cs(Referer)->cs_referer, rs(Content-Type)->rs_content_type, c-ip->c_ip). 이름이 겹치면 _2, _3 ... 을 붙임.
elff_columns() {
  local fmt="$1" tok col base n
  local -A seen=()
  local IFS=$' \t\n'
  for tok in $fmt; do
    case "$tok" in
      date) col="log_date" ;;
      time) col="log_time" ;;
      *) col="$(printf '%s' "$tok" | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C sed -E 's/[^a-z0-9]+/_/g; s/^_+//; s/_+$//')" ;;
    esac
    [[ -n "$col" ]] || col="field"
    base="$col"; n=1
    while [[ -n "${seen[$col]:-}" ]]; do n=$((n+1)); col="${base}_${n}"; done
    seen[$col]=1
    printf '%s\n' "$col"
  done
}
proxysg_columns_block() {
  local cols=() i
  mapfile -t cols < <(elff_columns "$1")
  for i in "${!cols[@]}"; do
    if (( i < ${#cols[@]} - 1 )); then printf '          "%s",\n' "${cols[i]}"; else printf '          "%s"\n' "${cols[i]}"; fi
  done
}
render_proxysg_filter() {
  local tpl="$1" line skip=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      "# @@PROXYSG_CLOUD_BEGIN@@") istrue "$PROXYSG_CLOUD_ENABLED" || skip=1; continue ;;
      "# @@PROXYSG_CLOUD_END@@")   skip=0; continue ;;
    esac
    (( skip )) && continue
    case "$line" in
      "@@PROXYSG_MAIN_COLUMNS@@")  proxysg_columns_block "$PROXYSG_MAIN_LOG_FORMAT" ;;
      "@@PROXYSG_SSL_COLUMNS@@")   proxysg_columns_block "$PROXYSG_SSL_LOG_FORMAT" ;;
      "@@PROXYSG_CLOUD_COLUMNS@@") proxysg_columns_block "$PROXYSG_CLOUD_LOG_FORMAT" ;;
      *) printf '%s\n' "$line" ;;
    esac
  done <"$tpl"
}

random_secret() {
  openssl rand -hex 24
}

save_secret() {
  local key="$1" val="$2"
  mkdir -p "$(dirname "$SECRETS_FILE")"
  touch "$SECRETS_FILE"
  chmod 600 "$SECRETS_FILE"
  if grep -qE "^${key}=" "$SECRETS_FILE" 2>/dev/null; then
    sed -i "/^${key}=/d" "$SECRETS_FILE"
  fi
  printf '%s=%q\n' "$key" "$val" >> "$SECRETS_FILE"
}

load_saved_secret() {
  local key="$1"
  [[ -f "$SECRETS_FILE" ]] || return 1
  local line
  line="$(grep -E "^${key}=" "$SECRETS_FILE" | tail -n1 || true)"
  [[ -n "$line" ]] || return 1
  local val="${line#*=}"
  eval "printf '%s' ${val}"
}

csv_to_json_array() {
  local csv="$1"
  if [[ -z "$csv" ]]; then echo '[]'; return; fi
  printf '%s' "$csv" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length>0))'
}

csv_to_ls_array() {
  local csv="$1" first=1 item out="["
  IFS=',' read -ra arr <<< "$csv"
  for item in "${arr[@]}"; do
    item="$(echo "$item" | xargs)"
    [[ -n "$item" ]] || continue
    item="${item//\\/\\\\}"
    item="${item//\"/\\\"}"
    if (( first )); then first=0; else out+=", "; fi
    out+="\"${item}\""
  done
  out+="]"
  printf '%s' "$out"
}

validate_codec() {
  case "$1" in plain|json|json_lines) return 0 ;; *) die "지원하지 않는 codec: $1 (plain/json/json_lines)" ;; esac
}

wait_for_http_code() {
  local url="$1" cacert="${2:-}" expected_re="${3:-200|401}" elapsed=0 code
  while (( elapsed < WAIT_TIMEOUT_SECONDS )); do
    # v2.9.4: -s (not -sS) so connection-refused errors while the service is still starting
    # are not printed as scary curl messages; a short progress line is logged instead.
    if [[ -n "$cacert" && -f "$cacert" ]]; then
      code="$(curl -s --connect-timeout 3 --max-time 5 --cacert "$cacert" -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || true)"
    else
      code="$(curl -s --connect-timeout 3 --max-time 5 -k -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || true)"
    fi
    if [[ "$code" =~ ^(${expected_re})$ ]]; then return 0; fi
    if (( elapsed > 0 && elapsed % 15 == 0 )); then
      log "서비스 기동 대기 중: ${url} (${elapsed}/${WAIT_TIMEOUT_SECONDS}초)"
    fi
    sleep 3; elapsed=$((elapsed+3))
  done
  return 1
}

ES_CA="/etc/elasticsearch/certs/http_ca.crt"
# 실행 중인 Elasticsearch 프로토콜은 설치/재실행 상태에 따라 달라질 수 있어 자동 탐지한다.
ES_LOCAL_URL="https://127.0.0.1:${ES_HTTP_PORT}"

detect_es_local_url() {
  local port https_code http_code
  local ports=("$ES_HTTP_PORT")
  [[ "$ES_HTTP_PORT" == "9200" ]] || ports+=("9200")
  for port in "${ports[@]}"; do
    local https_args=(-sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 3 "https://127.0.0.1:${port}")
    [[ -f "$ES_CA" ]] && https_args+=(--cacert "$ES_CA")
    https_code="$(curl "${https_args[@]}" 2>/dev/null || true)"
    if [[ "$https_code" =~ ^(200|401|403)$ ]]; then
      ES_LOCAL_URL="https://127.0.0.1:${port}"
      return 0
    fi
    http_code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 3 "http://127.0.0.1:${port}" 2>/dev/null || true)"
    if [[ "$http_code" =~ ^(200|401|403)$ ]]; then
      ES_LOCAL_URL="http://127.0.0.1:${port}"
      return 0
    fi
  done
  return 1
}
es_curl() {
  local method="$1" path="$2" body="${3:-}" pw="${4:-$ELASTIC_PASSWORD}"
  local args=(-sS -X "$method" "${ES_LOCAL_URL}${path}" -H 'Content-Type: application/json')
  if istrue "$ES_SECURITY_ENABLED"; then
    args+=( -u "${ELASTIC_USERNAME}:${pw}" )
  fi
  if [[ "$ES_LOCAL_URL" == https://* && -f "$ES_CA" ]]; then
    args+=( --cacert "$ES_CA" )
  fi
  [[ -n "$body" ]] && args+=( -d "$body" )
  curl "${args[@]}"
}

es_http_code() {
  local method="$1" path="$2" pw="${3:-$ELASTIC_PASSWORD}"
  local args=(-sS -o /dev/null -w '%{http_code}' -X "$method" "${ES_LOCAL_URL}${path}")
  if istrue "$ES_SECURITY_ENABLED"; then args+=( -u "${ELASTIC_USERNAME}:${pw}" ); fi
  if [[ "$ES_LOCAL_URL" == https://* && -f "$ES_CA" ]]; then args+=( --cacert "$ES_CA" ); fi
  curl "${args[@]}" || true
}

es_auth_ok() {
  local pw="$1" code
  if ! istrue "$ES_SECURITY_ENABLED"; then return 0; fi
  local args=(-sS -o /dev/null -w '%{http_code}' -u "${ELASTIC_USERNAME}:${pw}" "${ES_LOCAL_URL}/_security/_authenticate")
  if [[ "$ES_LOCAL_URL" == https://* && -f "$ES_CA" ]]; then args+=( --cacert "$ES_CA" ); fi
  code="$(curl "${args[@]}" || true)"
  [[ "$code" == "200" ]]
}

wait_for_es_auth() {
  local pw="$1" timeout="${2:-$WAIT_TIMEOUT_SECONDS}" elapsed=0 code="000"
  if ! istrue "$ES_SECURITY_ENABLED"; then return 0; fi
  while (( elapsed < timeout )); do
    code="$(es_http_code GET "/_security/_authenticate" "$pw")"
    if [[ "$code" == "200" ]]; then
      return 0
    fi
    if (( elapsed == 0 || elapsed % 15 == 0 )); then
      log "elastic 인증 준비 대기 중: HTTP ${code} (${elapsed}/${timeout}초)"
    fi
    sleep 3
    elapsed=$((elapsed+3))
  done
  ES_AUTH_LAST_CODE="$code"
  return 1
}

# ProxySG MAIN/SSL 전용 프로필. 일반 고급구성과 충돌하지 않도록 명시적으로 켠 경우에만 적용합니다.
if istrue "$PROXYSG_FLOW_ENABLED"; then
  LOGSTASH_PROFILE="proxysg"
  LS_TCP_ENABLED="false"
  LS_UDP_ENABLED="false"
  LS_SYSLOG_ENABLED="false"
  LS_BEATS_ENABLED="false"
  LS_HTTP_ENABLED="false"
  LS_FILE_ENABLED="false"
  FILE_INGEST_MANAGER_ENABLED="false"
  FTP_INTEGRATE_FILE_INGEST="false"
  INDEX_MODE="daily"
  INDEX_TEMPLATE_NAME="$PROXYSG_INDEX_TEMPLATE_NAME"
  INDEX_TEMPLATE_PATTERNS="${PROXYSG_MAIN_INDEX_PREFIX}-*,${PROXYSG_SSL_INDEX_PREFIX}-*"
  if istrue "$PROXYSG_CLOUD_ENABLED"; then INDEX_TEMPLATE_PATTERNS="${INDEX_TEMPLATE_PATTERNS},${PROXYSG_CLOUD_INDEX_PREFIX}-*"; fi
  ILM_POLICY_NAME="$PROXYSG_ILM_POLICY_NAME"
  [[ -n "$ILM_EXISTING_INDEX_PATTERNS" ]] || ILM_EXISTING_INDEX_PATTERNS="$INDEX_TEMPLATE_PATTERNS"
fi
# Nginx Reverse Proxy 사용 시 Kibana 5601을 외부에 직접 노출하지 않습니다.
if istrue "$INSTALL_NGINX" && [[ "$KIBANA_SERVER_HOST" == "0.0.0.0" ]]; then KIBANA_SERVER_HOST="127.0.0.1"; fi
if istrue "$INSTALL_NGINX" && [[ -z "$NGINX_PROXY_PORT" ]]; then NGINX_PROXY_PORT="$KIBANA_SERVER_PORT"; fi

# FTP 업로드 경로와 Managed File Ingest를 하나의 흐름으로 사용할 때 source를 자동 정렬합니다.
if istrue "$INSTALL_FTP_SERVER" && istrue "$FTP_INTEGRATE_FILE_INGEST" && istrue "$FILE_INGEST_MANAGER_ENABLED"; then
  FILE_INGEST_SOURCE_DIRS="$FTP_UPLOAD_DIR"
  FILE_INGEST_SOURCE_OWNER="$FTP_USER"
  FILE_INGEST_SOURCE_GROUP="$FTP_GROUP"
  FILE_INGEST_SOURCE_MODE="$FTP_UPLOAD_MODE"
fi

# Managed file ingest를 사용하면 Logstash file input을 안전한 read-mode 스테이징 경로로 강제합니다.
if istrue "$FILE_INGEST_MANAGER_ENABLED"; then
  LS_FILE_ENABLED="true"
  LS_FILE_MODE="read"
  LS_FILE_PATHS="${FILE_INGEST_STAGING_DIR}/*.ready"
  LS_FILE_EXCLUDE=""
  LS_FILE_START_POSITION="beginning"
  LS_FILE_COMPLETED_ACTION="log"
  LS_FILE_COMPLETED_LOG_PATH="$FILE_INGEST_COMPLETED_LOG"
fi

validate_secret_min() {
  local key="$1" value="${2:-}" min="$3" note="${4:-}"
  [[ -z "$value" ]] && return 0
  if (( ${#value} < min )); then
    die "${key}는 직접 입력할 경우 최소 ${min}자 이상이어야 합니다.${note:+ $note} 비워두면 설치기가 안전한 값을 자동 생성합니다."
  fi
}

validate_abs_path() {
  local key="$1" value="${2:-}"
  [[ -n "$value" && "$value" == /* ]] || die "${key}는 / 로 시작하는 절대경로여야 합니다: ${value:-<빈 값>}"
}

validate_port() {
  local key="$1" value="${2:-}"
  [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 1 && value <= 65535 )) || die "${key}는 1~65535 범위의 포트 번호여야 합니다: ${value:-<빈 값>}"
}

validate_env() {
  # 서버 변경 전에 먼저 실패하도록 계정/비밀번호/경로의 하드 조건을 검증합니다.
  # Elasticsearch native user password API: 직접 입력 시 최소 6자. 빈 값은 자동 생성.
  if istrue "$INSTALL_ELASTICSEARCH" && istrue "$ES_SECURITY_ENABLED"; then
    validate_secret_min "ELASTIC_PASSWORD" "$ELASTIC_PASSWORD" 6 "(Elasticsearch 계정 정책)"
    [[ -n "$ELASTIC_USERNAME" ]] || die "ELASTIC_USERNAME(Elasticsearch 관리자 ID)이 비어 있습니다."
    # 내장 superuser 'elastic'은 이름 변경/삭제가 불가능하다. 신규 설치는 이 계정으로 bootstrap 하므로
    # 다른 이름은 이미 같은 이름의 superuser가 있는 기존 클러스터에 재배포할 때만 허용한다.
    if [[ "$ELASTIC_USERNAME" != "elastic" ]] && ! dpkg -s elasticsearch >/dev/null 2>&1; then
      die "ELASTIC_USERNAME='${ELASTIC_USERNAME}': 신규 설치에서는 내장 관리자 계정 'elastic'을 사용해야 합니다. 별도 관리자 계정은 Kibana '초기 사용자 자동 생성'(Role: superuser)으로 만드세요."
    fi
  fi
  if istrue "$INSTALL_LOGSTASH"; then
    validate_secret_min "LOGSTASH_ES_PASSWORD" "$LOGSTASH_ES_PASSWORD" 6 "(Elasticsearch native user 계정 정책)"
    [[ -n "$LOGSTASH_ES_USERNAME" ]] || die "LOGSTASH_ES_USERNAME이 비어 있습니다."
  fi
  if istrue "$KIBANA_CREATE_INITIAL_USER"; then
    validate_secret_min "KIBANA_INITIAL_USER_PASSWORD" "$KIBANA_INITIAL_USER_PASSWORD" 6 "(Elasticsearch native user 계정 정책)"
    [[ -n "$KIBANA_INITIAL_USER_NAME" ]] || die "KIBANA_INITIAL_USER_NAME이 비어 있습니다."
    [[ -n "$KIBANA_INITIAL_USER_ROLES" ]] || die "KIBANA_INITIAL_USER_ROLES가 비어 있습니다."
  fi
  if istrue "$INSTALL_FTP_SERVER"; then
    # Ubuntu 환경별 PAM 정책 차이를 피하기 위해 사용자 지정 FTP 비밀번호는 최소 8자로 제한합니다.
    validate_secret_min "FTP_PASSWORD" "$FTP_PASSWORD" 8 "(Ubuntu 계정 정책 호환을 위한 Wizard 기준)"
  fi
  if istrue "$INSTALL_KIBANA" && [[ -n "$KIBANA_SESSION_IDLE_TIMEOUT" ]]; then
    [[ "$KIBANA_SESSION_IDLE_TIMEOUT" =~ ^[0-9]+(ms|s|m|h|d|w|M|Y)$ ]] \
      || die "KIBANA_SESSION_IDLE_TIMEOUT 형식 오류: '${KIBANA_SESSION_IDLE_TIMEOUT}' (예: 30m, 8h, 7d)"
  fi
  if istrue "$INSTALL_KIBANA"; then
    validate_secret_min "KIBANA_SECURITY_ENCRYPTION_KEY" "$KIBANA_SECURITY_ENCRYPTION_KEY" 32 "(Kibana encryption key)"
    validate_secret_min "KIBANA_REPORTING_ENCRYPTION_KEY" "$KIBANA_REPORTING_ENCRYPTION_KEY" 32 "(Kibana encryption key)"
    validate_secret_min "KIBANA_SAVED_OBJECTS_ENCRYPTION_KEY" "$KIBANA_SAVED_OBJECTS_ENCRYPTION_KEY" 32 "(Kibana encryption key)"
  fi

  validate_abs_path "ES_PATH_DATA" "$ES_PATH_DATA"
  validate_abs_path "ES_PATH_LOGS" "$ES_PATH_LOGS"
  validate_port "ES_HTTP_PORT" "$ES_HTTP_PORT"
  validate_port "KIBANA_SERVER_PORT" "$KIBANA_SERVER_PORT"
  if istrue "$INSTALL_FTP_SERVER"; then validate_port "FTP_LISTEN_PORT" "$FTP_LISTEN_PORT"; fi

  case "$INDEX_MODE" in daily|rollover|plain) ;; *) die "INDEX_MODE은 daily/rollover/plain 중 하나여야 합니다." ;; esac
  case "$ES_HEAP_MODE" in auto|fixed) ;; *) die "ES_HEAP_MODE은 auto 또는 fixed여야 합니다." ;; esac
  case "$ES_DISCOVERY_MODE" in single-node|multi-node) ;; *) die "ES_DISCOVERY_MODE은 single-node 또는 multi-node여야 합니다." ;; esac
  case "$LOGSTASH_PROFILE" in generic|proxysg) ;; *) die "LOGSTASH_PROFILE은 generic 또는 proxysg여야 합니다." ;; esac
  case "$NGINX_TLS_MODE" in selfsigned|existing) ;; *) die "NGINX_TLS_MODE은 selfsigned/existing 중 하나여야 합니다." ;; esac
  validate_codec "$LS_TCP_CODEC"
  validate_codec "$LS_UDP_CODEC"
  validate_codec "$LS_HTTP_CODEC"
  validate_codec "$LS_FILE_CODEC"
  [[ "$INDEX_PREFIX" =~ ^[a-z0-9._-]+$ ]] || die "INDEX_PREFIX는 소문자 영문/숫자/.-_ 조합을 권장합니다: $INDEX_PREFIX"
  if istrue "$INSTALL_FTP_SERVER"; then
    [[ "${FTP_PACKAGE,,}" == "vsftpd" ]] || die "현재 FTP_PACKAGE는 vsftpd만 지원합니다."
    [[ "$FTP_LISTEN_PORT" =~ ^[0-9]+$ ]] && (( FTP_LISTEN_PORT >= 1 && FTP_LISTEN_PORT <= 65535 )) || die "FTP_LISTEN_PORT가 올바르지 않습니다: $FTP_LISTEN_PORT"
    [[ "$FTP_PASV_MIN_PORT" =~ ^[0-9]+$ && "$FTP_PASV_MAX_PORT" =~ ^[0-9]+$ ]] || die "FTP Passive Port는 숫자여야 합니다."
    (( FTP_PASV_MIN_PORT >= 1 && FTP_PASV_MAX_PORT <= 65535 && FTP_PASV_MIN_PORT <= FTP_PASV_MAX_PORT )) || die "FTP Passive Port 범위를 확인하십시오: $FTP_PASV_MIN_PORT-$FTP_PASV_MAX_PORT"
    [[ "$FTP_ROOT_DIR" == /* && "$FTP_UPLOAD_DIR" == /* ]] || die "FTP_ROOT_DIR/FTP_UPLOAD_DIR은 절대경로여야 합니다."
    if istrue "$FTP_CHROOT_LOCAL_USER"; then case "$FTP_UPLOAD_DIR/" in "$FTP_ROOT_DIR"/*) ;; *) die "FTP_CHROOT_LOCAL_USER=true이면 FTP_UPLOAD_DIR은 FTP_ROOT_DIR 아래에 있어야 합니다." ;; esac; fi
    [[ -n "$FTP_USER" && -n "$FTP_GROUP" ]] || die "FTP_USER/FTP_GROUP이 비어 있습니다."
  fi
  if istrue "$FILE_INGEST_MANAGER_ENABLED"; then
    istrue "$INSTALL_LOGSTASH" || die "FILE_INGEST_MANAGER_ENABLED=true이면 INSTALL_LOGSTASH=true가 필요합니다."
    case "${FILE_INGEST_DEDUPE_MODE,,}" in content_sha256|metadata|none) ;; *) die "FILE_INGEST_DEDUPE_MODE은 content_sha256/metadata/none 중 하나여야 합니다." ;; esac
    case "${FILE_INGEST_DUPLICATE_ACTION,,}" in archive|delete|leave) ;; *) die "FILE_INGEST_DUPLICATE_ACTION은 archive/delete/leave 중 하나여야 합니다." ;; esac
    case "${FILE_INGEST_PLAIN_BACKUP_COMPRESSION,,}" in zstd|gzip|xz|none) ;; *) die "FILE_INGEST_PLAIN_BACKUP_COMPRESSION은 zstd/gzip/xz/none 중 하나여야 합니다." ;; esac
  fi
  if istrue "$PROXYSG_CLOUD_ENABLED" && ! istrue "$PROXYSG_FLOW_ENABLED"; then
    warn "PROXYSG_CLOUD_ENABLED=true이지만 로그 처리 스크립트(PROXYSG_FLOW_ENABLED)가 꺼져 있어 Cloud 수신 폴더 복사는 자동으로 실행되지 않습니다. Cloud 처리 폴더에 파일을 직접 공급해야 합니다."
  fi
  if istrue "$PROXYSG_FLOW_ENABLED"; then
    istrue "$INSTALL_LOGSTASH" || die "PROXYSG_FLOW_ENABLED=true이면 INSTALL_LOGSTASH=true가 필요합니다."
    istrue "$INSTALL_FTP_SERVER" || warn "ProxySG 로그 처리 스크립트를 사용하지만 FTP 서버 설치가 꺼져 있습니다. source 디렉터리에 파일을 별도로 공급해야 합니다."
    _chk_dirs=("$PROXYSG_MAIN_SOURCE_DIR" "$PROXYSG_SSL_SOURCE_DIR" "$PROXYSG_MAIN_BACKUP_DIR" "$PROXYSG_SSL_BACKUP_DIR" "$PROXYSG_MAIN_PROCESS_DIR" "$PROXYSG_SSL_PROCESS_DIR")
    if istrue "$PROXYSG_CLOUD_ENABLED"; then _chk_dirs+=("$PROXYSG_CLOUD_SOURCE_DIR" "$PROXYSG_CLOUD_BACKUP_DIR" "$PROXYSG_CLOUD_PROCESS_DIR"); fi
    for _d in "${_chk_dirs[@]}"; do
      [[ "$_d" == /* ]] || die "PROXYSG_* 디렉터리는 절대경로여야 합니다: $_d"
    done
    # v2.9.4: 로그 종류별 인덱스 Prefix / Data View 이름 검사 (서로 달라야 로그가 섞이지 않는다)
    _pfx=("$PROXYSG_MAIN_INDEX_PREFIX" "$PROXYSG_SSL_INDEX_PREFIX"); _dvn=("$PROXYSG_MAIN_DATA_VIEW_NAME" "$PROXYSG_SSL_DATA_VIEW_NAME")
    if istrue "$PROXYSG_CLOUD_ENABLED"; then _pfx+=("$PROXYSG_CLOUD_INDEX_PREFIX"); _dvn+=("$PROXYSG_CLOUD_DATA_VIEW_NAME"); fi
    for _p in "${_pfx[@]}"; do
      [[ "$_p" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || die "인덱스 Prefix는 소문자·숫자·-·_·. 만 쓰고 영문/숫자로 시작해야 합니다: '$_p'"
    done
    [[ -z "$(printf '%s\n' "${_pfx[@]}" | sort | uniq -d)" ]] || die "MAIN/SSL/Cloud 인덱스 Prefix는 서로 달라야 합니다: ${_pfx[*]}"
    for _p in "${_dvn[@]}"; do [[ -n "${_p//[[:space:]]/}" ]] || die "Data View 이름이 비어 있습니다."; done
    [[ -z "$(printf '%s\n' "${_dvn[@]}" | sort | uniq -d)" ]] || die "MAIN/SSL/Cloud Data View 이름은 서로 달라야 합니다: ${_dvn[*]}"
    [[ "$PROXYSG_PROCESS_CRON" =~ ^[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+$ ]] || die "PROXYSG_PROCESS_CRON은 5개 필드 cron 형식이어야 합니다. 예: 0 3 * * *"
  fi
  if istrue "$ILM_DELETE_ENABLED" && [[ ! "$ILM_DELETE_MIN_AGE" =~ ^[0-9]+(ms|s|m|h|d|w)$ ]]; then
    die "ILM_DELETE_MIN_AGE 형식이 올바르지 않습니다. 예: 90d (현재: '$ILM_DELETE_MIN_AGE')"
  fi
  if istrue "$INSTALL_LOGSTASH" && [[ "$LOGSTASH_PROFILE" == "proxysg" ]] && istrue "$PROXYSG_CSV_FILTER_ENABLED"; then
    # v2.9.4: MAIN/SSL(/Cloud) 로그 포맷(ELFF 필드 순서)으로 Logstash csv columns를 만든다.
    _fmt_vars=(PROXYSG_MAIN_LOG_FORMAT PROXYSG_SSL_LOG_FORMAT)
    if istrue "$PROXYSG_CLOUD_ENABLED"; then _fmt_vars+=(PROXYSG_CLOUD_LOG_FORMAT); fi
    for _lf in "${_fmt_vars[@]}"; do
      _lv="${!_lf}"
      [[ -n "${_lv//[[:space:]]/}" ]] || die "${_lf}이 비어 있습니다. (ProxySG access log의 #Fields 순서를 공백으로 구분해 입력)"
      [[ "$_lv" =~ ^[A-Za-z0-9_.:()[:space:]-]+$ ]] || die "${_lf}에 허용되지 않는 문자가 있습니다. (영문/숫자, - _ . : ( ) 와 공백만 사용)"
    done
  fi
  if istrue "$INSTALL_LOGSTASH" && { [[ "$LOGSTASH_PIPELINE_FILE" != /etc/logstash/conf.d/*.conf ]] || [[ "${LOGSTASH_PIPELINE_FILE#/etc/logstash/conf.d/}" == */* ]]; }; then
    die "LOGSTASH_PIPELINE_FILE은 /etc/logstash/conf.d/ 바로 아래의 .conf 파일이어야 합니다. (pipelines.yml이 conf.d/*.conf만 읽습니다): $LOGSTASH_PIPELINE_FILE"
  fi
  if istrue "$INSTALL_NGINX" && [[ "$NGINX_TLS_MODE" == "existing" ]]; then
    [[ -s "$NGINX_TLS_CERT_FILE" && -s "$NGINX_TLS_KEY_FILE" ]] || die "NGINX_TLS_MODE=existing이면 인증서/키 파일이 미리 존재해야 합니다."
  fi
  if [[ "$ES_DISCOVERY_MODE" == "multi-node" ]]; then
    warn "multi-node 선택됨: 이 설치기는 discovery 설정은 생성하지만 노드 간 Transport TLS 인증서 배포/CA 통합은 자동화하지 않습니다. 동일 CA 기반 Transport 인증서를 별도로 구성해야 합니다."
  fi
}

validate_env
case "$INDEX_MODE" in
  plain) INDEX_MATCH_PATTERN="$INDEX_PREFIX" ;;
  rollover) INDEX_MATCH_PATTERN="${ILM_ROLLOVER_ALIAS}-*" ;;
  daily) INDEX_MATCH_PATTERN="${INDEX_PREFIX}-*" ;;
esac
[[ -n "$INDEX_TEMPLATE_PATTERNS" ]] || INDEX_TEMPLATE_PATTERNS="$INDEX_MATCH_PATTERN"
if istrue "$PROXYSG_FLOW_ENABLED"; then INDEX_MATCH_PATTERN="$INDEX_TEMPLATE_PATTERNS"; fi
[[ -n "$ILM_EXISTING_INDEX_PATTERNS" ]] || ILM_EXISTING_INDEX_PATTERNS="$INDEX_TEMPLATE_PATTERNS"
if [[ "$INDEX_MODE" == "rollover" && -z "$ILM_ROLLOVER_MAX_AGE$ILM_ROLLOVER_MAX_PRIMARY_SHARD_SIZE$ILM_ROLLOVER_MAX_DOCS" ]]; then
  die "INDEX_MODE=rollover에서는 rollover 조건(max_age/max_primary_shard_size/max_docs) 중 하나 이상이 필요합니다."
fi
if ! istrue "$INSTALL_ELASTICSEARCH"; then
  if istrue "$INSTALL_KIBANA" && [[ -z "$KIBANA_ES_HOST" ]]; then die "INSTALL_ELASTICSEARCH=false이면 KIBANA_ES_HOST를 직접 지정해야 합니다."; fi
  if istrue "$INSTALL_LOGSTASH" && [[ -z "$LOGSTASH_ES_HOST" ]]; then die "INSTALL_ELASTICSEARCH=false이면 LOGSTASH_ES_HOST를 직접 지정해야 합니다."; fi
fi
if [[ "$RUN_MODE" == "--validate" || "$RUN_MODE" == "validate" ]]; then
  cat <<VALID
[OK] elk.env 기본 검증 완료
  Elastic major      : $ELASTIC_MAJOR
  Elastic version    : ${ELASTIC_VERSION:-latest}
  Cluster / Node     : $ES_CLUSTER_NAME / $ES_NODE_NAME
  Elasticsearch data: $ES_PATH_DATA
  Index mode         : $INDEX_MODE
  Index match        : $INDEX_MATCH_PATTERN
  Template patterns  : $INDEX_TEMPLATE_PATTERNS
  Logstash profile   : $LOGSTASH_PROFILE
  ProxySG flow       : $PROXYSG_FLOW_ENABLED
  ILM policy         : $ILM_POLICY_NAME
  Delete age         : $ILM_DELETE_MIN_AGE
  TCP input          : $LS_TCP_ENABLED / $LS_TCP_PORT
  File input         : $LS_FILE_ENABLED / $LS_FILE_PATHS
  FTP server         : $INSTALL_FTP_SERVER / ${FTP_USER}@${FTP_LISTEN_ADDRESS}:${FTP_LISTEN_PORT} -> $FTP_UPLOAD_DIR
  Nginx HTTPS        : $INSTALL_NGINX / ${NGINX_HTTPS_PORT}
  File ingest mgr    : $FILE_INGEST_MANAGER_ENABLED / $FILE_INGEST_SOURCE_DIRS
  Backup compression : $FILE_INGEST_PLAIN_BACKUP_COMPRESSION
  Health monitor     : $HEALTH_MONITOR_ENABLED / $HEALTH_MONITOR_INTERVAL
VALID
  exit 0
fi

# ----------------------------- OS -----------------------------
log "환경파일: $ENV_FILE"
log "설치 로그: $INSTALL_LOG"

[[ -f /etc/os-release ]] || die "/etc/os-release를 찾을 수 없습니다."
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || warn "Ubuntu가 아닌 OS입니다: ${PRETTY_NAME:-unknown}. 설치는 계속하지만 검증 범위 밖입니다."
log "OS: ${PRETTY_NAME:-unknown}"

if istrue "$SET_HOSTNAME"; then
  log "Hostname 설정: $SYSTEM_HOSTNAME"
  hostnamectl set-hostname "$SYSTEM_HOSTNAME"
fi
if [[ -n "$TIMEZONE" ]]; then
  log "Timezone 설정: $TIMEZONE"
  timedatectl set-timezone "$TIMEZONE"
fi
if istrue "$ENABLE_NTP"; then
  timedatectl set-ntp true || true
fi

log "커널/메모리 설정 적용"
cat >/etc/sysctl.d/99-elk.conf <<SYSCTL
vm.max_map_count=${VM_MAX_MAP_COUNT}
vm.swappiness=${SYSTEM_SWAPPINESS}
SYSCTL
sysctl --system >/dev/null

if istrue "$DISABLE_SWAP"; then
  swapoff -a || true
  if [[ -f /etc/fstab ]]; then
    cp -a /etc/fstab "$BACKUP_DIR/fstab.$(date '+%Y%m%d-%H%M%S').bak"
    sed -ri '/^[[:space:]]*[^#].*[[:space:]]swap[[:space:]]/ s/^/# ELK-AUTO disabled swap: /' /etc/fstab
  fi
fi

export http_proxy="$HTTP_PROXY" https_proxy="$HTTPS_PROXY" no_proxy="$NO_PROXY"
export HTTP_PROXY="$HTTP_PROXY" HTTPS_PROXY="$HTTPS_PROXY" NO_PROXY="$NO_PROXY"

if [[ -n "$APT_PROXY" ]]; then
  cat >/etc/apt/apt.conf.d/99elk-proxy <<APTCONF
Acquire::http::Proxy "${APT_PROXY}";
Acquire::https::Proxy "${APT_PROXY}";
APTCONF
fi

overall_progress 5 "Ubuntu 기본환경 및 필수 패키지 준비"
log "필수 패키지 설치"
apt-get -o Acquire::Retries="${APT_RETRIES}" -o Acquire::http::Timeout="${APT_CONNECT_TIMEOUT}" -o Acquire::https::Timeout="${APT_CONNECT_TIMEOUT}" update -y
apt_install_progress "필수 패키지" ca-certificates curl wget gnupg apt-transport-https jq openssl rsync netcat-openbsd lsof unzip xz-utils zstd bzip2 coreutils util-linux logrotate cron

# ----------------------------- Elastic APT repo -----------------------------
overall_progress 10 "Elastic ${ELASTIC_MAJOR} APT 저장소 구성"
log "Elastic APT 저장소 구성: ${ELASTIC_MAJOR}"
wget -qO - "$APT_GPG_KEY_URL" | gpg --dearmor --yes -o /usr/share/keyrings/elasticsearch-keyring.gpg
cat >/etc/apt/sources.list.d/elastic-${ELASTIC_MAJOR}.list <<REPO
deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] ${APT_REPOSITORY_URL}/${ELASTIC_MAJOR}/apt stable main
REPO
apt-get -o Acquire::Retries="${APT_RETRIES}" -o Acquire::http::Timeout="${APT_CONNECT_TIMEOUT}" -o Acquire::https::Timeout="${APT_CONNECT_TIMEOUT}" update -y

normalize_elastic_pkg_version() {
  # Debian package versions may include an epoch/revision.
  # Examples: 1:9.5.2-1 -> 9.5.2, 9.5.2 -> 9.5.2
  local v="${1:-}"
  v="${v#*:}"
  v="${v%%-*}"
  printf '%s' "$v"
}

resolve_elastic_pkg_version() {
  # Return the REAL APT package version that corresponds to the requested
  # upstream Elastic version.  Logstash commonly uses an epoch/revision such
  # as 1:9.5.2-1 even when ELASTIC_VERSION is 9.5.2.
  local pkg="$1" requested="$2" resolved=""
  resolved="$(apt-cache madison "$pkg" 2>/dev/null | awk -F'|' -v req="$requested" '
    function trim(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    {
      v=trim($2)
      n=v
      sub(/^[0-9]+:/, "", n)
      sub(/-.*/, "", n)
      if (n == req) { print v; exit }
    }
  ')"
  if [[ -n "$resolved" ]]; then
    printf '%s\n' "$resolved"
    return 0
  fi
  return 1
}

install_pkg() {
  local pkg="$1" installed="" resolved="" installed_upstream=""
  installed="$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || true)"

  if [[ -n "$ELASTIC_VERSION" ]]; then
    resolved="$(resolve_elastic_pkg_version "$pkg" "$ELASTIC_VERSION" || true)"
    if [[ -z "$resolved" ]]; then
      echo "[$(_ts)] [ERROR] $pkg의 요청 버전 ${ELASTIC_VERSION}에 대응하는 APT 패키지 버전을 찾지 못했습니다." >&2
      echo "[INFO] ${pkg} 저장소에서 확인되는 버전:" >&2
      apt-cache madison "$pkg" 2>/dev/null | head -20 >&2 || true
      return 100
    fi

    log "$pkg 버전 확인: 요청=${ELASTIC_VERSION} / APT=${resolved}"

    if [[ -n "$installed" ]]; then
      installed_upstream="$(normalize_elastic_pkg_version "$installed")"
      if [[ "$installed_upstream" == "$ELASTIC_VERSION" ]]; then
        log "$pkg 이미 설치됨: $installed (upstream ${ELASTIC_VERSION})"
        return 0
      fi
      log "$pkg 설치 버전 변경: 현재=$installed / 요청=${ELASTIC_VERSION} / APT=$resolved"
    else
      log "$pkg upstream ${ELASTIC_VERSION} -> APT version ${resolved} 로 설치"
    fi

    # IMPORTANT: apt-get receives the exact Debian package version returned by
    # apt-cache madison, not the upstream-only version.
    apt_install_progress "$pkg ${ELASTIC_VERSION}" "${pkg}=${resolved}"
  else
    if [[ -n "$installed" ]]; then
      log "$pkg 이미 설치됨: $installed"
      return 0
    fi
    log "$pkg 최신 ${ELASTIC_MAJOR} 설치"
    apt_install_progress "$pkg ${ELASTIC_MAJOR}" "$pkg"
  fi
}

if istrue "$INSTALL_ELASTICSEARCH"; then overall_progress 15 "Elasticsearch 패키지 다운로드/설치"; install_pkg elasticsearch; fi
if istrue "$INSTALL_KIBANA"; then overall_progress 28 "Kibana 패키지 다운로드/설치"; install_pkg kibana; fi
if istrue "$INSTALL_LOGSTASH"; then overall_progress 38 "Logstash 패키지 다운로드/설치"; install_pkg logstash; fi
if istrue "$INSTALL_NGINX"; then overall_progress 45 "Nginx 패키지 설치"; log "Nginx 설치"; apt_install_progress "Nginx" nginx; fi
if istrue "$INSTALL_FTP_SERVER"; then
  overall_progress 48 "FTP(vsftpd) 패키지 설치"
  log "FTP 서버 패키지 설치: $FTP_PACKAGE"
  apt_install_progress "FTP 서버" "$FTP_PACKAGE"
fi

# ----------------------------- FTP server -----------------------------
overall_progress 50 "FTP 계정/경로 및 vsftpd 설정"
if istrue "$INSTALL_FTP_SERVER"; then
  # 그룹/계정 생성. 기본 shell은 nologin이며 PAM pam_shells 호환을 위해 /etc/shells에 등록합니다.
  getent group "$FTP_GROUP" >/dev/null || groupadd --system "$FTP_GROUP"
  if [[ "$FTP_USER_SHELL" == */nologin && -x "$FTP_USER_SHELL" ]] && ! grep -qxF "$FTP_USER_SHELL" /etc/shells 2>/dev/null; then
    echo "$FTP_USER_SHELL" >> /etc/shells
  fi
  if ! id "$FTP_USER" >/dev/null 2>&1; then
    useradd --create-home --home-dir "$FTP_ROOT_DIR" --gid "$FTP_GROUP" --shell "$FTP_USER_SHELL" "$FTP_USER"
    log "FTP 전용 계정 생성: $FTP_USER"
  else
    usermod -d "$FTP_ROOT_DIR" -g "$FTP_GROUP" -s "$FTP_USER_SHELL" "$FTP_USER"
  fi
  if [[ -z "$FTP_PASSWORD" ]]; then
    SAVED_FTP="$(load_saved_secret FTP_PASSWORD 2>/dev/null || true)"
    FTP_PASSWORD="${SAVED_FTP:-$(random_secret)}"
  fi
  printf '%s:%s\n' "$FTP_USER" "$FTP_PASSWORD" | chpasswd
  save_secret FTP_USER "$FTP_USER"
  save_secret FTP_PASSWORD "$FTP_PASSWORD"

  # chroot root는 사용자 쓰기 금지, upload 폴더만 쓰기 허용.
  mkdir -p "$FTP_ROOT_DIR" "$FTP_UPLOAD_DIR" "$(dirname "$FTP_LOG_FILE")"
  chown root:root "$FTP_ROOT_DIR"
  chmod "$FTP_ROOT_MODE" "$FTP_ROOT_DIR"
  chown "$FTP_USER:$FTP_GROUP" "$FTP_UPLOAD_DIR"
  chmod "$FTP_UPLOAD_MODE" "$FTP_UPLOAD_DIR"

  # 지정한 업로드 디렉터리가 깊은 경로인 경우 중간 경로는 접근 가능하게 유지.
  cur="$(dirname "$FTP_UPLOAD_DIR")"
  while [[ "$cur" != "$FTP_ROOT_DIR" && "$cur" != "/" ]]; do
    chmod o+x "$cur" 2>/dev/null || true
    cur="$(dirname "$cur")"
  done

  FTP_TLS_CN_EFFECTIVE="${FTP_TLS_CN:-$(hostname -f 2>/dev/null || hostname)}"
  if istrue "$FTP_TLS_ENABLED"; then
    if [[ ! -s "$FTP_TLS_CERT_FILE" || ! -s "$FTP_TLS_KEY_FILE" ]]; then
      log "FTP TLS self-signed 인증서 생성: CN=$FTP_TLS_CN_EFFECTIVE"
      mkdir -p "$(dirname "$FTP_TLS_CERT_FILE")" "$(dirname "$FTP_TLS_KEY_FILE")"
      openssl req -x509 -nodes -newkey rsa:3072 -sha256 -days "$FTP_TLS_DAYS" \
        -subj "/CN=${FTP_TLS_CN_EFFECTIVE}" \
        -keyout "$FTP_TLS_KEY_FILE" -out "$FTP_TLS_CERT_FILE" >/dev/null 2>&1
    fi
    chmod 600 "$FTP_TLS_KEY_FILE"
    chmod 644 "$FTP_TLS_CERT_FILE"
  fi

  backup_file /etc/vsftpd.conf
  cat >/etc/vsftpd.conf <<EOF_FTP
listen=YES
listen_ipv6=NO
listen_address=${FTP_LISTEN_ADDRESS}
listen_port=${FTP_LISTEN_PORT}
anonymous_enable=$(istrue "$FTP_ALLOW_ANONYMOUS" && echo YES || echo NO)
local_enable=YES
write_enable=YES
download_enable=$(istrue "$FTP_DOWNLOAD_ENABLE" && echo YES || echo NO)
local_umask=${FTP_LOCAL_UMASK}
local_root=${FTP_ROOT_DIR}
chroot_local_user=$(istrue "$FTP_CHROOT_LOCAL_USER" && echo YES || echo NO)
allow_writeable_chroot=$(istrue "$FTP_ALLOW_WRITEABLE_CHROOT" && echo YES || echo NO)
userlist_enable=YES
userlist_deny=NO
userlist_file=/etc/vsftpd.user_list
pam_service_name=vsftpd
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
log_ftp_protocol=YES
vsftpd_log_file=${FTP_LOG_FILE}
ftpd_banner=${FTP_BANNER}
pasv_enable=$(istrue "$FTP_PASV_ENABLE" && echo YES || echo NO)
pasv_min_port=${FTP_PASV_MIN_PORT}
pasv_max_port=${FTP_PASV_MAX_PORT}
port_enable=$(istrue "$FTP_ACTIVE_ENABLE" && echo YES || echo NO)
connect_from_port_20=$(istrue "$FTP_CONNECT_FROM_PORT_20" && echo YES || echo NO)
max_clients=${FTP_MAX_CLIENTS}
max_per_ip=${FTP_MAX_PER_IP}
idle_session_timeout=${FTP_IDLE_SESSION_TIMEOUT}
data_connection_timeout=${FTP_DATA_CONNECTION_TIMEOUT}
ssl_enable=$(istrue "$FTP_TLS_ENABLED" && echo YES || echo NO)
EOF_FTP
  if [[ -n "$FTP_PASV_ADDRESS" ]]; then echo "pasv_address=${FTP_PASV_ADDRESS}" >>/etc/vsftpd.conf; fi
  if istrue "$FTP_TLS_ENABLED"; then
    cat >>/etc/vsftpd.conf <<EOF_FTP_TLS
rsa_cert_file=${FTP_TLS_CERT_FILE}
rsa_private_key_file=${FTP_TLS_KEY_FILE}
force_local_logins_ssl=$(istrue "$FTP_TLS_FORCE" && echo YES || echo NO)
force_local_data_ssl=$(istrue "$FTP_TLS_FORCE" && echo YES || echo NO)
require_ssl_reuse=$(istrue "$FTP_TLS_REQUIRE_REUSE" && echo YES || echo NO)
ssl_sslv2=NO
ssl_sslv3=NO
EOF_FTP_TLS
  fi
  printf '%s\n' "$FTP_USER" >/etc/vsftpd.user_list
  chmod 600 /etc/vsftpd.user_list
  log "FTP 구성 완료: ${FTP_USER}@${FTP_LISTEN_ADDRESS}:${FTP_LISTEN_PORT}, upload=${FTP_UPLOAD_DIR}"
fi

# ----------------------------- ProxySG MAIN/SSL directories -----------------------------
overall_progress 54 "ProxySG 로그 디렉터리 및 권한 설정"
if istrue "$PROXYSG_FLOW_ENABLED"; then
  log "ProxySG 로그 처리 디렉터리 생성"
  _ps_src=("$PROXYSG_MAIN_SOURCE_DIR" "$PROXYSG_SSL_SOURCE_DIR")
  _ps_bak=("$PROXYSG_MAIN_BACKUP_DIR" "$PROXYSG_SSL_BACKUP_DIR")
  _ps_prc=("$PROXYSG_MAIN_PROCESS_DIR" "$PROXYSG_SSL_PROCESS_DIR")
  if istrue "$PROXYSG_CLOUD_ENABLED"; then
    _ps_src+=("$PROXYSG_CLOUD_SOURCE_DIR"); _ps_bak+=("$PROXYSG_CLOUD_BACKUP_DIR"); _ps_prc+=("$PROXYSG_CLOUD_PROCESS_DIR")
  fi
  mkdir -p "${_ps_src[@]}" "${_ps_bak[@]}" "${_ps_prc[@]}"
  chown -R "$FTP_USER:$FTP_GROUP" "${_ps_src[@]}" "${_ps_bak[@]}"
  chown -R logstash:logstash "${_ps_prc[@]}"
  chmod "$PROXYSG_DIR_MODE" "${_ps_src[@]}" "${_ps_bak[@]}" "${_ps_prc[@]}"
fi

# ----------------------------- Elasticsearch bootstrap -----------------------------
overall_progress 58 "Elasticsearch 설정 및 Security/TLS 초기화"
if istrue "$INSTALL_ELASTICSEARCH"; then
  mkdir -p /etc/systemd/system/elasticsearch.service.d
  cat >/etc/systemd/system/elasticsearch.service.d/override.conf <<EOF_ES_SYSTEMD
[Service]
LimitNOFILE=${ES_LIMIT_NOFILE}
LimitNPROC=${ES_LIMIT_NPROC}
EOF_ES_SYSTEMD
  if istrue "$ES_BOOTSTRAP_MEMORY_LOCK"; then
    echo 'LimitMEMLOCK=infinity' >>/etc/systemd/system/elasticsearch.service.d/override.conf
  fi
  systemctl daemon-reload

  # 최초 부팅 시 Elastic의 자동 보안 설정/TLS 인증서 생성을 이용
  if [[ ! -f "$ES_CA" && ! -f /etc/elasticsearch/certs/http.p12 ]]; then
    log "Elasticsearch 최초 시작 - 자동 보안/TLS 생성"
    systemctl enable elasticsearch >/dev/null 2>&1 || true
    systemctl start elasticsearch
    if ! wait_for_http_code "https://127.0.0.1:9200" "$ES_CA" '200|401'; then
      journalctl -u elasticsearch -n 120 --no-pager || true
      die "Elasticsearch 최초 시작 확인 실패"
    fi
  else
    log "기존 Elasticsearch TLS 구성 감지"
    systemctl start elasticsearch || true
    wait_for_http_code "https://127.0.0.1:9200" "$ES_CA" '200|401' || true
  fi

  detect_es_local_url || true
  log "현재 Elasticsearch 로컬 URL 감지: $ES_LOCAL_URL"

  # 보안이 켜져 있을 때 관리자 비밀번호 확보
  if istrue "$ES_SECURITY_ENABLED"; then
    [[ -f "$ES_CA" ]] || die "Elasticsearch CA 인증서를 찾을 수 없습니다: $ES_CA"

    # 사용자가 Wizard에서 지정한 목표 비밀번호는 운영 설정 재시작 뒤 복구 과정에서도 유지한다.
    DESIRED_ELASTIC_PASSWORD="$ELASTIC_PASSWORD"
    CURRENT_PW=""
    if [[ -n "$ELASTIC_PASSWORD" ]] && es_auth_ok "$ELASTIC_PASSWORD"; then
      CURRENT_PW="$ELASTIC_PASSWORD"
      log "환경파일의 elastic 비밀번호 확인 완료"
    else
      SAVED_ELASTIC="$(load_saved_secret ELASTIC_PASSWORD 2>/dev/null || true)"
      if [[ -n "$SAVED_ELASTIC" ]] && es_auth_ok "$SAVED_ELASTIC"; then
        CURRENT_PW="$SAVED_ELASTIC"
        log "저장된 elastic 비밀번호 확인 완료"
      fi
    fi

    if [[ -z "$CURRENT_PW" ]]; then
      log "elastic 관리자 비밀번호 재설정(자동 생성)"
      RESET_OUT="$(/usr/share/elasticsearch/bin/elasticsearch-reset-password -u "$ELASTIC_USERNAME" -b -s 2>&1 || true)"
      # -s 모드는 보통 값만 출력. 형식이 달라도 마지막 비어있지 않은 줄을 사용.
      CURRENT_PW="$(printf '%s\n' "$RESET_OUT" | awk 'NF{line=$0} END{print line}' | sed -E 's/^New value: //')"
      [[ -n "$CURRENT_PW" ]] || die "elastic 비밀번호 자동 재설정 실패: $RESET_OUT"
      if ! es_auth_ok "$CURRENT_PW"; then
        die "재설정된 elastic 비밀번호 인증 실패. 출력: $RESET_OUT"
      fi
    fi

    if [[ -n "$ELASTIC_PASSWORD" && "$CURRENT_PW" != "$ELASTIC_PASSWORD" ]]; then
      log "사용자 지정 ELASTIC_PASSWORD 적용"
      pw_json="$(jq -n --arg p "$ELASTIC_PASSWORD" '{password:$p}')"
      resp="$(es_curl POST "/_security/user/${ELASTIC_USERNAME}/_password" "$pw_json" "$CURRENT_PW")"
      if [[ "$(echo "$resp" | jq -r '.error.type? // empty')" != "" ]]; then
        die "ELASTIC_PASSWORD 변경 실패: $resp"
      fi
      CURRENT_PW="$ELASTIC_PASSWORD"
    fi
    ELASTIC_PASSWORD="$CURRENT_PW"
    save_secret ELASTIC_PASSWORD "$ELASTIC_PASSWORD"
  fi

  log "Elasticsearch 서비스 중지 후 운영 설정 적용"
  systemctl stop elasticsearch || true

  # path.data 변경 시 최초 데이터(보안 인덱스 포함) 안전 복사
  if [[ "$ES_PATH_DATA" != "/var/lib/elasticsearch" ]]; then
    mkdir -p "$ES_PATH_DATA"
    chown elasticsearch:elasticsearch "$ES_PATH_DATA"
    chmod 750 "$ES_PATH_DATA"
    src_count="$(find /var/lib/elasticsearch -mindepth 1 -maxdepth 1 2>/dev/null | wc -l || true)"
    dst_count="$(find "$ES_PATH_DATA" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l || true)"
    if (( src_count > 0 && dst_count == 0 )); then
      log "기본 Elasticsearch 데이터를 새 경로로 복사: $ES_PATH_DATA"
      rsync -aHAX /var/lib/elasticsearch/ "$ES_PATH_DATA/"
      chown -R elasticsearch:elasticsearch "$ES_PATH_DATA"
    elif (( src_count > 0 && dst_count > 0 )); then
      warn "기본 경로와 새 데이터 경로 모두 데이터가 있습니다. 데이터 보호를 위해 자동 병합하지 않습니다. 새 경로의 기존 데이터를 사용합니다."
    fi
  fi
  mkdir -p "$ES_PATH_LOGS"
  chown -R elasticsearch:elasticsearch "$ES_PATH_LOGS"

  if istrue "$SNAPSHOT_REPO_ENABLED"; then
    mkdir -p "$SNAPSHOT_REPO_PATH"
    chown -R elasticsearch:elasticsearch "$SNAPSHOT_REPO_PATH"
    chmod 750 "$SNAPSHOT_REPO_PATH"
  fi

  backup_file /etc/elasticsearch/elasticsearch.yml
  {
    echo "# Managed by ELK Auto Installer"
    echo "cluster.name: \"${ES_CLUSTER_NAME}\""
    echo "node.name: \"${ES_NODE_NAME}\""
    echo "path.data: \"${ES_PATH_DATA}\""
    echo "path.logs: \"${ES_PATH_LOGS}\""
    echo "network.host: \"${ES_NETWORK_HOST}\""
    echo "http.port: ${ES_HTTP_PORT}"
    echo "transport.port: ${ES_TRANSPORT_PORT}"
    echo "action.destructive_requires_name: ${ES_ACTION_DESTRUCTIVE_REQUIRES_NAME}"
    echo "bootstrap.memory_lock: ${ES_BOOTSTRAP_MEMORY_LOCK}"
    if [[ "$ES_DISCOVERY_MODE" == "single-node" ]]; then
      echo "discovery.type: single-node"
    else
      [[ -n "$ES_DISCOVERY_SEED_HOSTS" ]] && echo "discovery.seed_hosts: $(csv_to_json_array "$ES_DISCOVERY_SEED_HOSTS")"
      [[ -n "$ES_CLUSTER_INITIAL_MASTER_NODES" ]] && echo "cluster.initial_master_nodes: $(csv_to_json_array "$ES_CLUSTER_INITIAL_MASTER_NODES")"
    fi
    echo "xpack.security.enabled: ${ES_SECURITY_ENABLED}"
    if istrue "$ES_SECURITY_ENABLED"; then
      echo "xpack.security.enrollment.enabled: ${ES_ENROLLMENT_ENABLED}"
      echo "xpack.security.http.ssl.enabled: ${ES_HTTP_TLS_ENABLED}"
      if istrue "$ES_HTTP_TLS_ENABLED"; then
        echo "xpack.security.http.ssl.keystore.path: certs/http.p12"
      fi
      echo "xpack.security.transport.ssl.enabled: ${ES_TRANSPORT_TLS_ENABLED}"
      if istrue "$ES_TRANSPORT_TLS_ENABLED"; then
        echo "xpack.security.transport.ssl.verification_mode: certificate"
        echo "xpack.security.transport.ssl.keystore.path: certs/transport.p12"
        echo "xpack.security.transport.ssl.truststore.path: certs/transport.p12"
      fi
    fi
    [[ -n "$ES_DISK_WATERMARK_LOW" ]] && echo "cluster.routing.allocation.disk.watermark.low: \"${ES_DISK_WATERMARK_LOW}\""
    [[ -n "$ES_DISK_WATERMARK_HIGH" ]] && echo "cluster.routing.allocation.disk.watermark.high: \"${ES_DISK_WATERMARK_HIGH}\""
    [[ -n "$ES_DISK_WATERMARK_FLOOD_STAGE" ]] && echo "cluster.routing.allocation.disk.watermark.flood_stage: \"${ES_DISK_WATERMARK_FLOOD_STAGE}\""
    [[ -n "$ES_CLUSTER_INFO_UPDATE_INTERVAL" ]] && echo "cluster.info.update.interval: \"${ES_CLUSTER_INFO_UPDATE_INTERVAL}\""
    if istrue "$SNAPSHOT_REPO_ENABLED"; then
      echo "path.repo: [\"${SNAPSHOT_REPO_PATH}\"]"
    fi
    if [[ -n "$ES_EXTRA_CONFIG_FILE" ]]; then
      [[ -f "$ES_EXTRA_CONFIG_FILE" ]] || die "ES_EXTRA_CONFIG_FILE 없음: $ES_EXTRA_CONFIG_FILE"
      echo
      echo "# ---- user extra config ----"
      cat "$ES_EXTRA_CONFIG_FILE"
    fi
  } >/etc/elasticsearch/elasticsearch.yml
  chown root:elasticsearch /etc/elasticsearch/elasticsearch.yml
  chmod 660 /etc/elasticsearch/elasticsearch.yml

  mkdir -p /etc/elasticsearch/jvm.options.d
  if [[ "$ES_HEAP_MODE" == "fixed" ]]; then
    cat >/etc/elasticsearch/jvm.options.d/99-heap.options <<EOF_HEAP
-Xms${ES_HEAP_MIN}
-Xmx${ES_HEAP_MAX}
EOF_HEAP
  else
    rm -f /etc/elasticsearch/jvm.options.d/99-heap.options
  fi

  log "Elasticsearch 운영 설정으로 시작"
  systemctl start elasticsearch
  if istrue "$ES_SECURITY_ENABLED" && istrue "$ES_HTTP_TLS_ENABLED"; then
    ES_LOCAL_URL="https://127.0.0.1:${ES_HTTP_PORT}"
  else
    ES_LOCAL_URL="http://127.0.0.1:${ES_HTTP_PORT}"
  fi
  if [[ -z "$KIBANA_ES_HOST" ]]; then KIBANA_ES_HOST="$ES_LOCAL_URL"; fi
  if [[ -z "$LOGSTASH_ES_HOST" ]]; then LOGSTASH_ES_HOST="$ES_LOCAL_URL"; fi
  if ! wait_for_http_code "$ES_LOCAL_URL" "$ES_CA" '200|401'; then
    journalctl -u elasticsearch -n 160 --no-pager || true
    die "Elasticsearch 시작 실패"
  fi

  # 보안 false면 URL 재정의 후 확인
  if ! istrue "$ES_SECURITY_ENABLED"; then
    ELASTIC_PASSWORD=""
    ES_LOCAL_URL="http://127.0.0.1:${ES_HTTP_PORT}"
  elif ! wait_for_es_auth "$ELASTIC_PASSWORD" 60; then
    warn "운영 설정 적용 직후 elastic 인증이 아직 준비되지 않았거나 기존 비밀번호가 유효하지 않습니다. 마지막 HTTP=${ES_AUTH_LAST_CODE:-unknown}"
    warn "보안 인덱스 복구 지연/재시작 타이밍에 대비해 elastic 비밀번호를 안전하게 다시 동기화합니다."

    RESET_OUT="$(/usr/share/elasticsearch/bin/elasticsearch-reset-password -u "$ELASTIC_USERNAME" -b -s 2>&1 || true)"
    RECOVERY_PW="$(printf '%s\n' "$RESET_OUT" | awk 'NF{line=$0} END{print line}' | sed -E 's/^New value: //')"
    [[ -n "$RECOVERY_PW" ]] || die "운영 설정 적용 후 elastic 비밀번호 복구 실패: $RESET_OUT"

    if ! wait_for_es_auth "$RECOVERY_PW" 90; then
      journalctl -u elasticsearch -n 160 --no-pager || true
      die "운영 설정 적용 후 재설정된 elastic 비밀번호도 인증되지 않습니다. 마지막 HTTP=${ES_AUTH_LAST_CODE:-unknown}"
    fi
    log "운영 설정 적용 후 elastic 인증 복구 완료"

    # Wizard에서 사용자가 지정한 비밀번호가 있으면 복구용 임시 비밀번호에서 다시 목표값으로 맞춘다.
    if [[ -n "${DESIRED_ELASTIC_PASSWORD:-}" && "$RECOVERY_PW" != "$DESIRED_ELASTIC_PASSWORD" ]]; then
      log "사용자 지정 ELASTIC_PASSWORD 재적용"
      pw_json="$(jq -n --arg p "$DESIRED_ELASTIC_PASSWORD" '{password:$p}')"
      resp="$(es_curl POST "/_security/user/${ELASTIC_USERNAME}/_password" "$pw_json" "$RECOVERY_PW")"
      if [[ "$(echo "$resp" | jq -r '.error.type? // empty')" != "" ]]; then
        die "운영 설정 후 ELASTIC_PASSWORD 재적용 실패: $resp"
      fi
      ELASTIC_PASSWORD="$DESIRED_ELASTIC_PASSWORD"
      if ! wait_for_es_auth "$ELASTIC_PASSWORD" 60; then
        die "운영 설정 후 사용자 지정 ELASTIC_PASSWORD 재적용 뒤 인증 실패. 마지막 HTTP=${ES_AUTH_LAST_CODE:-unknown}"
      fi
    else
      ELASTIC_PASSWORD="$RECOVERY_PW"
    fi
    save_secret ELASTIC_PASSWORD "$ELASTIC_PASSWORD"
  fi

  log "Elasticsearch 정상 응답 및 elastic 인증 확인"
fi

# ----------------------------- ILM & templates -----------------------------
overall_progress 66 "Index Template / ILM 90일 정책 구성"
create_ilm_policy() {
  [[ "$INDEX_MODE" == "plain" ]] && return 0

  local hot='{"actions":{}}' warm='null' del='null'
  if [[ "$INDEX_MODE" == "rollover" ]]; then
    hot="$(jq -n \
      --arg age "$ILM_ROLLOVER_MAX_AGE" \
      --arg size "$ILM_ROLLOVER_MAX_PRIMARY_SHARD_SIZE" \
      --arg docs "$ILM_ROLLOVER_MAX_DOCS" '
        {actions:{rollover:({}
          + (if $age!="" then {max_age:$age} else {} end)
          + (if $size!="" then {max_primary_shard_size:$size} else {} end)
          + (if $docs!="" then {max_docs:($docs|tonumber)} else {} end))}}')"
  fi

  if istrue "$ILM_WARM_ENABLED"; then
    warm="$(jq -n \
      --arg age "$ILM_WARM_MIN_AGE" \
      --argjson ro "$(istrue "$ILM_WARM_READONLY" && echo true || echo false)" \
      --argjson fm "$(istrue "$ILM_WARM_FORCE_MERGE" && echo true || echo false)" \
      --arg seg "$ILM_WARM_FORCE_MERGE_SEGMENTS" '
      {min_age:$age,actions:({}
        + (if $ro then {readonly:{}} else {} end)
        + (if $fm then {forcemerge:{max_num_segments:($seg|tonumber)}} else {} end))}')"
  fi

  if istrue "$ILM_DELETE_ENABLED"; then
    del="$(jq -n --arg age "$ILM_DELETE_MIN_AGE" '{min_age:$age,actions:{delete:{}}}')"
  fi

  local body
  body="$(jq -n \
    --argjson hot "$hot" \
    --argjson warm "$warm" \
    --argjson del "$del" '
    {policy:{phases:({hot:$hot}
      + (if $warm!=null then {warm:$warm} else {} end)
      + (if $del!=null then {delete:$del} else {} end))}}')"

  resp="$(es_curl PUT "/_ilm/policy/${ILM_POLICY_NAME}" "$body")"
  [[ "$(echo "$resp" | jq -r '.acknowledged // false')" == "true" ]] || die "ILM Policy 생성 실패: $resp"
  log "ILM Policy 적용: $ILM_POLICY_NAME"
}

create_index_template() {
  local lifecycle='{}'
  if [[ "$INDEX_MODE" == "daily" ]]; then
    lifecycle="$(jq -n --arg p "$ILM_POLICY_NAME" '{"index.lifecycle.name":$p}')"
  elif [[ "$INDEX_MODE" == "rollover" ]]; then
    lifecycle="$(jq -n --arg p "$ILM_POLICY_NAME" --arg a "$ILM_ROLLOVER_ALIAS" '{"index.lifecycle.name":$p,"index.lifecycle.rollover_alias":$a}')"
  fi

  local mappings='{}'
  if [[ -n "$INDEX_MAPPING_FILE" ]]; then
    [[ -f "$INDEX_MAPPING_FILE" ]] || die "INDEX_MAPPING_FILE 없음: $INDEX_MAPPING_FILE"
    jq empty "$INDEX_MAPPING_FILE" || die "INDEX_MAPPING_FILE JSON 오류"
    mappings="$(cat "$INDEX_MAPPING_FILE")"
  fi

  local body
  body="$(jq -n \
    --argjson patterns "$(csv_to_json_array "$INDEX_TEMPLATE_PATTERNS")" \
    --argjson priority "$INDEX_TEMPLATE_PRIORITY" \
    --arg shards "$INDEX_NUMBER_OF_SHARDS" \
    --arg replicas "$INDEX_NUMBER_OF_REPLICAS" \
    --arg refresh "$INDEX_REFRESH_INTERVAL" \
    --arg fields "$INDEX_TOTAL_FIELDS_LIMIT" \
    --argjson lifecycle "$lifecycle" \
    --argjson mappings "$mappings" '
    {
      index_patterns:$patterns,
      priority:$priority,
      template:{
        settings:({
          "number_of_shards":$shards,
          "number_of_replicas":$replicas,
          "refresh_interval":$refresh,
          "mapping.total_fields.limit":$fields
        } + $lifecycle),
        mappings:$mappings
      },
      _meta:{managed_by:"elk-auto-installer"}
    }')"
  resp="$(es_curl PUT "/_index_template/${INDEX_TEMPLATE_NAME}" "$body")"
  [[ "$(echo "$resp" | jq -r '.acknowledged // false')" == "true" ]] || die "Index Template 생성 실패: $resp"
  log "Index Template 적용: $INDEX_TEMPLATE_NAME"

  if [[ "$INDEX_MODE" == "rollover" ]]; then
    local initial="${ILM_ROLLOVER_ALIAS}-${ILM_ROLLOVER_PATTERN}"
    local exists_code
    exists_code="$(es_http_code HEAD "/${initial}")"
    if [[ "$exists_code" == "404" ]]; then
      body="$(jq -n --arg a "$ILM_ROLLOVER_ALIAS" '{aliases:{($a):{is_write_index:true}}}')"
      resp="$(es_curl PUT "/${initial}" "$body")"
      [[ "$(echo "$resp" | jq -r '.acknowledged // false')" == "true" ]] || die "Rollover 초기 인덱스 생성 실패: $resp"
      log "Rollover 초기 인덱스 생성: $initial -> $ILM_ROLLOVER_ALIAS"
    fi
  fi
}

if istrue "$INSTALL_ELASTICSEARCH"; then
  create_ilm_policy
  create_index_template
  if istrue "$ILM_APPLY_TO_EXISTING" && [[ "$INDEX_MODE" == "daily" ]]; then
    existing_path="/${ILM_EXISTING_INDEX_PATTERNS}/_settings?allow_no_indices=true&ignore_unavailable=true&expand_wildcards=open"
    existing_body="$(jq -n --arg p "$ILM_POLICY_NAME" '{"index.lifecycle.name":$p}')"
    resp="$(es_curl PUT "$existing_path" "$existing_body" || true)"
    if echo "$resp" | jq -e '.error' >/dev/null 2>&1; then
      warn "기존 인덱스 ILM 적용 결과 확인 필요: $resp"
    else
      log "기존 인덱스에도 ILM 적용 시도: $ILM_EXISTING_INDEX_PATTERNS -> $ILM_POLICY_NAME"
    fi
  fi
fi

# ----------------------------- optional initial Kibana/Elastic user -----------------------------
if istrue "$INSTALL_ELASTICSEARCH" && istrue "$ES_SECURITY_ENABLED" && istrue "$KIBANA_CREATE_INITIAL_USER"; then
  [[ -n "$KIBANA_INITIAL_USER_NAME" ]] || die "KIBANA_CREATE_INITIAL_USER=true이지만 사용자명이 비어 있습니다."
  if [[ -z "$KIBANA_INITIAL_USER_PASSWORD" ]]; then
    _saved_user_pw="$(load_saved_secret KIBANA_INITIAL_USER_PASSWORD 2>/dev/null || true)"
    KIBANA_INITIAL_USER_PASSWORD="${_saved_user_pw:-$(random_secret)}"
  fi
  _roles_json="$(csv_to_json_array "$KIBANA_INITIAL_USER_ROLES")"
  _user_body="$(jq -n --arg p "$KIBANA_INITIAL_USER_PASSWORD" --argjson r "$_roles_json" '{password:$p,roles:$r,full_name:"ELK Wizard User"}')"
  _user_resp="$(es_curl POST "/_security/user/${KIBANA_INITIAL_USER_NAME}" "$_user_body")"
  if echo "$_user_resp" | jq -e '.error' >/dev/null 2>&1; then die "초기 사용자 생성 실패: $_user_resp"; fi
  save_secret KIBANA_INITIAL_USER_NAME "$KIBANA_INITIAL_USER_NAME"
  save_secret KIBANA_INITIAL_USER_PASSWORD "$KIBANA_INITIAL_USER_PASSWORD"
  save_secret KIBANA_INITIAL_USER_ROLES "$KIBANA_INITIAL_USER_ROLES"
  log "초기 Kibana/Elasticsearch 사용자 생성: $KIBANA_INITIAL_USER_NAME ($KIBANA_INITIAL_USER_ROLES)"
fi

# ----------------------------- Logstash user/role -----------------------------
overall_progress 72 "Logstash 계정/Role 및 Pipeline 구성"
if istrue "$INSTALL_LOGSTASH"; then
  if istrue "$ES_SECURITY_ENABLED"; then
    if [[ -z "$LOGSTASH_ES_PASSWORD" ]]; then
      SAVED_LS="$(load_saved_secret LOGSTASH_ES_PASSWORD 2>/dev/null || true)"
      LOGSTASH_ES_PASSWORD="${SAVED_LS:-$(random_secret)}"
    fi
    save_secret LOGSTASH_ES_PASSWORD "$LOGSTASH_ES_PASSWORD"

    role_body="$(jq -n \
      --argjson pats "$(csv_to_json_array "$INDEX_TEMPLATE_PATTERNS")" \
      '{cluster:["manage_index_templates","monitor","manage_ilm"],indices:[{names:$pats,privileges:["write","create","create_index","manage","manage_ilm","view_index_metadata"]}]}')"
    resp="$(es_curl PUT "/_security/role/${LOGSTASH_ES_ROLE}" "$role_body")"
    if echo "$resp" | jq -e '.error' >/dev/null 2>&1; then die "Logstash role 생성 실패: $resp"; fi

    user_body="$(jq -n --arg p "$LOGSTASH_ES_PASSWORD" --arg r "$LOGSTASH_ES_ROLE" '{password:$p,roles:[$r],full_name:"Internal Logstash Writer"}')"
    resp="$(es_curl POST "/_security/user/${LOGSTASH_ES_USERNAME}" "$user_body")"
    if echo "$resp" | jq -e '.error' >/dev/null 2>&1; then die "Logstash user 생성 실패: $resp"; fi
    log "Logstash 전용 계정/Role 구성: $LOGSTASH_ES_USERNAME / $LOGSTASH_ES_ROLE"
  fi

  mkdir -p "$LOGSTASH_PATH_DATA" "$LOGSTASH_PATH_LOGS" /etc/logstash/certs /etc/logstash/conf.d
  chown -R logstash:logstash "$LOGSTASH_PATH_DATA" "$LOGSTASH_PATH_LOGS" /etc/logstash/certs

  if istrue "$ES_SECURITY_ENABLED" && istrue "$ES_HTTP_TLS_ENABLED"; then
    cp -f "$ES_CA" /etc/logstash/certs/http_ca.crt
    chown logstash:logstash /etc/logstash/certs/http_ca.crt
    chmod 640 /etc/logstash/certs/http_ca.crt
  fi

  backup_file /etc/logstash/logstash.yml
  {
    echo "# Managed by ELK Auto Installer"
    echo "node.name: \"${LOGSTASH_NODE_NAME}\""
    echo "path.data: \"${LOGSTASH_PATH_DATA}\""
    echo "path.logs: \"${LOGSTASH_PATH_LOGS}\""
    if [[ "$LOGSTASH_PIPELINE_WORKERS" != "0" ]]; then echo "pipeline.workers: ${LOGSTASH_PIPELINE_WORKERS}"; fi
    echo "pipeline.batch.size: ${LOGSTASH_PIPELINE_BATCH_SIZE}"
    echo "pipeline.batch.delay: ${LOGSTASH_PIPELINE_BATCH_DELAY}"
    echo "config.reload.automatic: ${LOGSTASH_CONFIG_RELOAD_AUTOMATIC}"
    echo "config.reload.interval: \"${LOGSTASH_CONFIG_RELOAD_INTERVAL}\""
    echo "queue.type: ${LOGSTASH_QUEUE_TYPE}"
    echo "queue.max_bytes: ${LOGSTASH_QUEUE_MAX_BYTES}"
    echo "queue.page_capacity: ${LOGSTASH_QUEUE_PAGE_CAPACITY}"
    echo "queue.drain: ${LOGSTASH_QUEUE_DRAIN}"
    echo "dead_letter_queue.enable: ${LOGSTASH_DEAD_LETTER_QUEUE}"
    echo "dead_letter_queue.max_bytes: ${LOGSTASH_DLQ_MAX_BYTES}"
    echo "api.enabled: ${LOGSTASH_API_ENABLED}"
    echo "api.http.host: \"${LOGSTASH_API_HOST}\""
    echo "api.http.port: ${LOGSTASH_API_PORT}"
    if [[ -n "$LOGSTASH_EXTRA_CONFIG_FILE" ]]; then
      [[ -f "$LOGSTASH_EXTRA_CONFIG_FILE" ]] || die "LOGSTASH_EXTRA_CONFIG_FILE 없음: $LOGSTASH_EXTRA_CONFIG_FILE"
      echo "# ---- user extra config ----"
      cat "$LOGSTASH_EXTRA_CONFIG_FILE"
    fi
  } >/etc/logstash/logstash.yml
  chown root:logstash /etc/logstash/logstash.yml
  chmod 640 /etc/logstash/logstash.yml

  # jvm.options를 안전하게 수정
  backup_file /etc/logstash/jvm.options
  sed -ri "s/^-Xms.*/-Xms${LOGSTASH_HEAP_MIN}/" /etc/logstash/jvm.options
  sed -ri "s/^-Xmx.*/-Xmx${LOGSTASH_HEAP_MAX}/" /etc/logstash/jvm.options

  cat >/etc/logstash/pipelines.yml <<EOF_PIPELINES
- pipeline.id: ${LOGSTASH_PIPELINE_ID}
  path.config: "/etc/logstash/conf.d/*.conf"
EOF_PIPELINES
  chown root:logstash /etc/logstash/pipelines.yml
  chmod 640 /etc/logstash/pipelines.yml

  # Logstash keystore: 비밀번호를 conf에 평문 저장하지 않음
  if istrue "$ES_SECURITY_ENABLED"; then
    # v2.9.4: logstash-keystore create asks "Continue without password protection? [y/N]" when
    # LOGSTASH_KEYSTORE_PASS is unset. Under systemd-run stdin is empty, so it aborted with exit 1
    # (only "Using bundled JDK" was visible because stdout was sent to /dev/null). Answer "y"
    # explicitly and surface the real error message if it still fails.
    if [[ ! -f /etc/logstash/logstash.keystore ]]; then
      ls_ks_out="$(printf 'y\n' | /usr/share/logstash/bin/logstash-keystore --path.settings /etc/logstash create 2>&1)" \
        || die "Logstash keystore 생성 실패: ${ls_ks_out}"
    fi
    /usr/share/logstash/bin/logstash-keystore --path.settings /etc/logstash remove LS_ES_USER >/dev/null 2>&1 || true
    /usr/share/logstash/bin/logstash-keystore --path.settings /etc/logstash remove LS_ES_PASSWORD >/dev/null 2>&1 || true
    ls_ks_out="$(printf '%s' "$LOGSTASH_ES_USERNAME" | /usr/share/logstash/bin/logstash-keystore --path.settings /etc/logstash add LS_ES_USER --stdin 2>&1)" \
      || die "Logstash keystore LS_ES_USER 추가 실패: ${ls_ks_out}"
    ls_ks_out="$(printf '%s' "$LOGSTASH_ES_PASSWORD" | /usr/share/logstash/bin/logstash-keystore --path.settings /etc/logstash add LS_ES_PASSWORD --stdin 2>&1)" \
      || die "Logstash keystore LS_ES_PASSWORD 추가 실패: ${ls_ks_out}"
    chown logstash:root /etc/logstash/logstash.keystore
    chmod 600 /etc/logstash/logstash.keystore
  fi

  if istrue "$FILE_INGEST_MANAGER_ENABLED"; then
    mkdir -p "$FILE_INGEST_STAGING_DIR" "$FILE_INGEST_STATE_DIR" "$FILE_INGEST_BACKUP_DIR" \
      "$FILE_INGEST_DUPLICATE_DIR" "$FILE_INGEST_QUARANTINE_DIR" "$(dirname "$FILE_INGEST_COMPLETED_LOG")"
    chown -R logstash:logstash "$FILE_INGEST_STAGING_DIR"
    touch "$FILE_INGEST_COMPLETED_LOG"
    chown logstash:logstash "$FILE_INGEST_COMPLETED_LOG"
    chmod 640 "$FILE_INGEST_COMPLETED_LOG"
    IFS=',' read -ra _ingest_roots <<< "$FILE_INGEST_SOURCE_DIRS"
    for _root in "${_ingest_roots[@]}"; do
      _root="$(echo "$_root" | xargs)"; [[ -n "$_root" ]] || continue
      mkdir -p "$_root"
      chown "$FILE_INGEST_SOURCE_OWNER:$FILE_INGEST_SOURCE_GROUP" "$_root" 2>/dev/null || warn "source 소유권 적용 실패: $_root"
      chmod "$FILE_INGEST_SOURCE_MODE" "$_root" 2>/dev/null || true
    done
  fi

  if [[ -s "$SCRIPT_DIR/custom-pipeline.conf" ]]; then
    # v2.9.4: Config Wizard에서 직접 수정한 pipeline을 그대로 사용한다. (설정값으로부터 자동 생성하지 않음)
    log "사용자 지정 Logstash pipeline 사용 (custom-pipeline.conf -> $LOGSTASH_PIPELINE_FILE)"
    cp -f "$SCRIPT_DIR/custom-pipeline.conf" "$LOGSTASH_PIPELINE_FILE"
  else
  log "Logstash pipeline 생성 ($LOGSTASH_PROFILE)"
  if [[ "$LOGSTASH_PROFILE" == "proxysg" ]]; then
    cat >"$LOGSTASH_PIPELINE_FILE" <<EOF_PROXYSG_LS
input {
  file {
    path => ["${PROXYSG_MAIN_PROCESS_DIR}/${PROXYSG_FILE_GLOB}"]
    mode => "read"
    file_completed_action => "delete"
    sincedb_path => "${PROXYSG_MAIN_SINCEDB}"
    type => "edge-http"
    discover_interval => ${PROXYSG_LOGSTASH_DISCOVER_INTERVAL}
    max_open_files => ${PROXYSG_LOGSTASH_MAX_OPEN_FILES}
  }
  file {
    path => ["${PROXYSG_SSL_PROCESS_DIR}/${PROXYSG_FILE_GLOB}"]
    mode => "read"
    file_completed_action => "delete"
    sincedb_path => "${PROXYSG_SSL_SINCEDB}"
    type => "edge-https"
    discover_interval => ${PROXYSG_LOGSTASH_DISCOVER_INTERVAL}
    max_open_files => ${PROXYSG_LOGSTASH_MAX_OPEN_FILES}
  }
EOF_PROXYSG_LS
    if istrue "$PROXYSG_CLOUD_ENABLED"; then
      cat >>"$LOGSTASH_PIPELINE_FILE" <<EOF_PROXYSG_CLOUD_IN
  file {
    path => ["${PROXYSG_CLOUD_PROCESS_DIR}/${PROXYSG_FILE_GLOB}"]
    mode => "read"
    file_completed_action => "delete"
    sincedb_path => "${PROXYSG_CLOUD_SINCEDB}"
    type => "cloud"
    discover_interval => ${PROXYSG_LOGSTASH_DISCOVER_INTERVAL}
    max_open_files => ${PROXYSG_LOGSTASH_MAX_OPEN_FILES}
  }
EOF_PROXYSG_CLOUD_IN
    fi
    printf '}\n' >>"$LOGSTASH_PIPELINE_FILE"
    if istrue "$PROXYSG_CSV_FILTER_ENABLED"; then
      [[ -f "$SCRIPT_DIR/proxysg-log-filter.conf" ]] || die "필수 파일 없음: $SCRIPT_DIR/proxysg-log-filter.conf"
      render_proxysg_filter "$SCRIPT_DIR/proxysg-log-filter.conf" >>"$LOGSTASH_PIPELINE_FILE"
    else
      printf '\nfilter { if ![message] or [message] =~ /^\s*#/ or [message] =~ /^\s*$/ { drop { } } }\n' >>"$LOGSTASH_PIPELINE_FILE"
    fi
    cat >>"$LOGSTASH_PIPELINE_FILE" <<EOF_PROXYSG_OUT
output {
  if [type] == "edge-http" {
    elasticsearch {
      hosts => ["${LOGSTASH_ES_HOST}"]
EOF_PROXYSG_OUT
    if istrue "$ES_SECURITY_ENABLED"; then
      cat >>"$LOGSTASH_PIPELINE_FILE" <<'EOF_PROXYSG_AUTH'
      user => "${LS_ES_USER}"
      password => "${LS_ES_PASSWORD}"
EOF_PROXYSG_AUTH
      if istrue "$ES_HTTP_TLS_ENABLED"; then cat >>"$LOGSTASH_PIPELINE_FILE" <<'EOF_PROXYSG_TLS'
      ssl_enabled => true
      ssl_certificate_authorities => ["/etc/logstash/certs/http_ca.crt"]
EOF_PROXYSG_TLS
      fi
    fi
    cat >>"$LOGSTASH_PIPELINE_FILE" <<EOF_PROXYSG_MAIN_OUT
      manage_template => false
      ilm_enabled => false
      index => "${PROXYSG_MAIN_INDEX_PREFIX}-%{+${INDEX_DATE_PATTERN}}"
    }
  } else if [type] == "edge-https" {
    elasticsearch {
      hosts => ["${LOGSTASH_ES_HOST}"]
EOF_PROXYSG_MAIN_OUT
    if istrue "$ES_SECURITY_ENABLED"; then
      cat >>"$LOGSTASH_PIPELINE_FILE" <<'EOF_PROXYSG_AUTH2'
      user => "${LS_ES_USER}"
      password => "${LS_ES_PASSWORD}"
EOF_PROXYSG_AUTH2
      if istrue "$ES_HTTP_TLS_ENABLED"; then cat >>"$LOGSTASH_PIPELINE_FILE" <<'EOF_PROXYSG_TLS2'
      ssl_enabled => true
      ssl_certificate_authorities => ["/etc/logstash/certs/http_ca.crt"]
EOF_PROXYSG_TLS2
      fi
    fi
    cat >>"$LOGSTASH_PIPELINE_FILE" <<EOF_PROXYSG_SSL_OUT
      manage_template => false
      ilm_enabled => false
      index => "${PROXYSG_SSL_INDEX_PREFIX}-%{+${INDEX_DATE_PATTERN}}"
    }
  }
EOF_PROXYSG_SSL_OUT
    if istrue "$PROXYSG_CLOUD_ENABLED"; then
      cat >>"$LOGSTASH_PIPELINE_FILE" <<EOF_PROXYSG_CLOUD_OUT
  if [type] == "cloud" {
    elasticsearch {
      hosts => ["${LOGSTASH_ES_HOST}"]
EOF_PROXYSG_CLOUD_OUT
      if istrue "$ES_SECURITY_ENABLED"; then
        cat >>"$LOGSTASH_PIPELINE_FILE" <<'EOF_PROXYSG_AUTH3'
      user => "${LS_ES_USER}"
      password => "${LS_ES_PASSWORD}"
EOF_PROXYSG_AUTH3
        if istrue "$ES_HTTP_TLS_ENABLED"; then cat >>"$LOGSTASH_PIPELINE_FILE" <<'EOF_PROXYSG_TLS3'
      ssl_enabled => true
      ssl_certificate_authorities => ["/etc/logstash/certs/http_ca.crt"]
EOF_PROXYSG_TLS3
        fi
      fi
      cat >>"$LOGSTASH_PIPELINE_FILE" <<EOF_PROXYSG_CLOUD_OUT2
      manage_template => false
      ilm_enabled => false
      index => "${PROXYSG_CLOUD_INDEX_PREFIX}-%{+${INDEX_DATE_PATTERN}}"
    }
  }
EOF_PROXYSG_CLOUD_OUT2
    fi
    printf '}\n' >>"$LOGSTASH_PIPELINE_FILE"
  else
  {
    echo "input {"
    if istrue "$LS_TCP_ENABLED"; then
      echo "  tcp { host => \"${LS_TCP_HOST}\" port => ${LS_TCP_PORT} codec => ${LS_TCP_CODEC} }"
    fi
    if istrue "$LS_UDP_ENABLED"; then
      echo "  udp { host => \"${LS_UDP_HOST}\" port => ${LS_UDP_PORT} codec => ${LS_UDP_CODEC} }"
    fi
    if istrue "$LS_SYSLOG_ENABLED"; then
      echo "  syslog { host => \"${LS_SYSLOG_HOST}\" port => ${LS_SYSLOG_PORT} }"
    fi
    if istrue "$LS_BEATS_ENABLED"; then
      echo "  beats { host => \"${LS_BEATS_HOST}\" port => ${LS_BEATS_PORT} }"
    fi
    if istrue "$LS_HTTP_ENABLED"; then
      echo "  http { host => \"${LS_HTTP_HOST}\" port => ${LS_HTTP_PORT} codec => ${LS_HTTP_CODEC} }"
    fi
    if istrue "$LS_FILE_ENABLED"; then
      echo "  file {"
      echo "    path => $(csv_to_ls_array "$LS_FILE_PATHS")"
      [[ -n "$LS_FILE_EXCLUDE" ]] && echo "    exclude => $(csv_to_ls_array "$LS_FILE_EXCLUDE")"
      echo "    mode => \"${LS_FILE_MODE}\""
      echo "    start_position => \"${LS_FILE_START_POSITION}\""
      echo "    sincedb_path => \"${LS_FILE_SINCEDB_PATH}\""
      echo "    codec => ${LS_FILE_CODEC}"
      [[ -n "$LS_FILE_IGNORE_OLDER" ]] && echo "    ignore_older => \"${LS_FILE_IGNORE_OLDER}\""
      [[ -n "$LS_FILE_CLOSE_OLDER" ]] && echo "    close_older => \"${LS_FILE_CLOSE_OLDER}\""
      if [[ "$LS_FILE_MODE" == "read" ]]; then
        echo "    file_completed_action => \"${LS_FILE_COMPLETED_ACTION}\""
        if [[ "$LS_FILE_COMPLETED_ACTION" =~ ^(log|log_and_delete)$ ]]; then
          echo "    file_completed_log_path => \"${LS_FILE_COMPLETED_LOG_PATH}\""
        fi
      fi
      echo "  }"
    fi
    echo "}"
    echo
    echo "filter {"
    if istrue "$LS_DROP_EMPTY_MESSAGE"; then
      echo '  if ![message] or [message] == "" { drop { } }'
    fi
    if istrue "$LS_PARSE_JSON_MESSAGE"; then
      if [[ -n "$LS_JSON_TARGET_FIELD" ]]; then
        echo "  json { source => \"${LS_JSON_SOURCE_FIELD}\" target => \"${LS_JSON_TARGET_FIELD}\" skip_on_invalid_json => true }"
      else
        echo "  json { source => \"${LS_JSON_SOURCE_FIELD}\" skip_on_invalid_json => true }"
      fi
    fi
    if [[ -n "$LS_DATE_SOURCE_FIELD" && -n "$LS_DATE_MATCH" ]]; then
      echo "  date { match => [\"${LS_DATE_SOURCE_FIELD}\", \"${LS_DATE_MATCH}\"] target => \"${LS_DATE_TARGET_FIELD}\" timezone => \"${LS_DATE_TIMEZONE}\" }"
    fi
    if [[ -n "$LS_CUSTOM_FILTER_FILE" ]]; then
      [[ -f "$LS_CUSTOM_FILTER_FILE" ]] || die "LS_CUSTOM_FILTER_FILE 없음: $LS_CUSTOM_FILTER_FILE"
      cat "$LS_CUSTOM_FILTER_FILE"
    fi
    echo "}"
    echo
    echo "output {"
    if istrue "$ES_SECURITY_ENABLED"; then
      echo "  elasticsearch {"
      echo "    hosts => [\"${LOGSTASH_ES_HOST}\"]"
      echo '    user => "${LS_ES_USER}"'
      echo '    password => "${LS_ES_PASSWORD}"'
      if istrue "$ES_HTTP_TLS_ENABLED"; then
        echo "    ssl_enabled => true"
        echo "    ssl_certificate_authorities => [\"/etc/logstash/certs/http_ca.crt\"]"
      fi
    else
      echo "  elasticsearch {"
      echo "    hosts => [\"${LOGSTASH_ES_HOST}\"]"
    fi
    echo "    manage_template => false"
    echo "    ilm_enabled => false"
    case "$INDEX_MODE" in
      daily) echo "    index => \"${INDEX_PREFIX}-%{+${INDEX_DATE_PATTERN}}\"" ;;
      rollover) echo "    index => \"${ILM_ROLLOVER_ALIAS}\"" ;;
      plain) echo "    index => \"${INDEX_PREFIX}\"" ;;
    esac
    echo "  }"
    if istrue "$LS_STDOUT_DEBUG"; then
      echo "  stdout { codec => rubydebug }"
    fi
    echo "}"
  } >"$LOGSTASH_PIPELINE_FILE"
  fi
  fi
  chown root:logstash "$LOGSTASH_PIPELINE_FILE"
  chmod 640 "$LOGSTASH_PIPELINE_FILE"

  log "Logstash 설정 문법 검사"
  if ! runuser -u logstash -- /usr/share/logstash/bin/logstash --path.settings /etc/logstash -t; then
    die "Logstash configuration test 실패"
  fi
fi

# ----------------------------- Kibana -----------------------------
overall_progress 80 "Kibana 연결 및 Data View 구성"
if istrue "$INSTALL_KIBANA"; then
  mkdir -p /etc/kibana/certs
  if istrue "$ES_SECURITY_ENABLED" && istrue "$ES_HTTP_TLS_ENABLED"; then
    cp -f "$ES_CA" /etc/kibana/certs/http_ca.crt
    chown kibana:kibana /etc/kibana/certs/http_ca.crt
    chmod 640 /etc/kibana/certs/http_ca.crt
  fi

  # v2.9.4: Kibana 로그인 비활성 = Kibana anonymous provider + 읽기 전용(viewer) 서비스 계정
  KIBANA_ANON_USER="kibana_anonymous"
  KIBANA_ANON_PASSWORD=""
  if istrue "$ES_SECURITY_ENABLED"; then
    if istrue "$KIBANA_LOGIN_ENABLED"; then
      es_curl DELETE "/_security/user/${KIBANA_ANON_USER}" >/dev/null 2>&1 || true
    else
      KIBANA_ANON_PASSWORD="$(load_saved_secret KIBANA_ANON_PASSWORD 2>/dev/null || true)"
      [[ -n "$KIBANA_ANON_PASSWORD" ]] || KIBANA_ANON_PASSWORD="$(random_secret)"
      save_secret KIBANA_ANON_PASSWORD "$KIBANA_ANON_PASSWORD"
      _anon_body="$(jq -n --arg p "$KIBANA_ANON_PASSWORD" '{password:$p,roles:["viewer"],full_name:"Kibana anonymous (read-only)"}')"
      _anon_resp="$(es_curl POST "/_security/user/${KIBANA_ANON_USER}" "$_anon_body")"
      if echo "$_anon_resp" | jq -e '.error' >/dev/null 2>&1; then die "Kibana 익명 접속 계정 생성 실패: $_anon_resp"; fi
      log "Kibana 로그인 비활성: 읽기 전용 익명 계정 ${KIBANA_ANON_USER}(viewer)으로 접속합니다."
    fi
  fi

  backup_file /etc/kibana/kibana.yml
  {
    echo "# Managed by ELK Auto Installer"
    echo "server.name: \"${KIBANA_SERVER_NAME}\""
    echo "server.host: \"${KIBANA_SERVER_HOST}\""
    echo "server.port: ${KIBANA_SERVER_PORT}"
    [[ -n "$KIBANA_PUBLIC_BASE_URL" ]] && echo "server.publicBaseUrl: \"${KIBANA_PUBLIC_BASE_URL}\""
    echo "elasticsearch.hosts: [\"${KIBANA_ES_HOST}\"]"
    if istrue "$ES_SECURITY_ENABLED" && istrue "$ES_HTTP_TLS_ENABLED"; then
      echo "elasticsearch.ssl.certificateAuthorities: [\"/etc/kibana/certs/http_ca.crt\"]"
      echo "elasticsearch.ssl.verificationMode: \"${KIBANA_ES_SSL_VERIFICATION_MODE}\""
    fi
    echo "logging.root.level: \"${KIBANA_LOG_LEVEL}\""
    if istrue "$ES_SECURITY_ENABLED"; then
      [[ -z "$KIBANA_SESSION_IDLE_TIMEOUT" ]] || echo "xpack.security.session.idleTimeout: \"${KIBANA_SESSION_IDLE_TIMEOUT}\""
      if ! istrue "$KIBANA_LOGIN_ENABLED"; then
        echo "xpack.security.authc.providers:"
        echo "  anonymous.anonymous1:"
        echo "    order: 0"
        echo "    credentials:"
        echo "      username: \"${KIBANA_ANON_USER}\""
        echo "      password: \"${KIBANA_ANON_PASSWORD}\""
        echo "  basic.basic1:"
        echo "    order: 1"
      fi
    fi
    if [[ -n "$KIBANA_EXTRA_CONFIG_FILE" ]]; then
      [[ -f "$KIBANA_EXTRA_CONFIG_FILE" ]] || die "KIBANA_EXTRA_CONFIG_FILE 없음: $KIBANA_EXTRA_CONFIG_FILE"
      echo "# ---- user extra config ----"
      cat "$KIBANA_EXTRA_CONFIG_FILE"
    fi
  } >/etc/kibana/kibana.yml
  chown root:kibana /etc/kibana/kibana.yml
  chmod 660 /etc/kibana/kibana.yml

  # Kibana keystore 생성
  if [[ ! -f /etc/kibana/kibana.keystore ]]; then
    env KBN_PATH_CONF=/etc/kibana /usr/share/kibana/bin/kibana-keystore create >/dev/null
  fi

  kibana_keystore_set() {
    local k="$1" v="$2"
    env KBN_PATH_CONF=/etc/kibana /usr/share/kibana/bin/kibana-keystore remove "$k" >/dev/null 2>&1 || true
    printf '%s' "$v" | env KBN_PATH_CONF=/etc/kibana /usr/share/kibana/bin/kibana-keystore add "$k" --stdin >/dev/null
  }

  if istrue "$ES_SECURITY_ENABLED"; then
    # 기존 keystore에 토큰이 있어도 idempotency를 위해 새 토큰을 생성해 교체
    es_curl DELETE "/_security/service/elastic/kibana/credential/token/${KIBANA_SERVICE_TOKEN_NAME}" >/dev/null 2>&1 || true
    # v2.9.4: this endpoint rejects any request body on Elasticsearch 9.x
    # ("request [POST ...] does not support having a body"), so send no -d at all.
    token_resp="$(es_curl POST "/_security/service/elastic/kibana/credential/token/${KIBANA_SERVICE_TOKEN_NAME}")"
    KIBANA_SERVICE_TOKEN="$(echo "$token_resp" | jq -r '.token.value // empty')"
    [[ -n "$KIBANA_SERVICE_TOKEN" ]] || die "Kibana service token 생성 실패: $token_resp"
    kibana_keystore_set elasticsearch.serviceAccountToken "$KIBANA_SERVICE_TOKEN"
    save_secret KIBANA_SERVICE_TOKEN "$KIBANA_SERVICE_TOKEN"
  fi

  [[ -n "$KIBANA_SECURITY_ENCRYPTION_KEY" ]] || KIBANA_SECURITY_ENCRYPTION_KEY="$(load_saved_secret KIBANA_SECURITY_ENCRYPTION_KEY 2>/dev/null || random_secret)"
  [[ -n "$KIBANA_REPORTING_ENCRYPTION_KEY" ]] || KIBANA_REPORTING_ENCRYPTION_KEY="$(load_saved_secret KIBANA_REPORTING_ENCRYPTION_KEY 2>/dev/null || random_secret)"
  [[ -n "$KIBANA_SAVED_OBJECTS_ENCRYPTION_KEY" ]] || KIBANA_SAVED_OBJECTS_ENCRYPTION_KEY="$(load_saved_secret KIBANA_SAVED_OBJECTS_ENCRYPTION_KEY 2>/dev/null || random_secret)"
  save_secret KIBANA_SECURITY_ENCRYPTION_KEY "$KIBANA_SECURITY_ENCRYPTION_KEY"
  save_secret KIBANA_REPORTING_ENCRYPTION_KEY "$KIBANA_REPORTING_ENCRYPTION_KEY"
  save_secret KIBANA_SAVED_OBJECTS_ENCRYPTION_KEY "$KIBANA_SAVED_OBJECTS_ENCRYPTION_KEY"
  kibana_keystore_set xpack.security.encryptionKey "$KIBANA_SECURITY_ENCRYPTION_KEY"
  kibana_keystore_set xpack.reporting.encryptionKey "$KIBANA_REPORTING_ENCRYPTION_KEY"
  kibana_keystore_set xpack.encryptedSavedObjects.encryptionKey "$KIBANA_SAVED_OBJECTS_ENCRYPTION_KEY"
  chown kibana:kibana /etc/kibana/kibana.keystore
  chmod 600 /etc/kibana/kibana.keystore
fi

# ----------------------------- Nginx reverse proxy -----------------------------
overall_progress 84 "Nginx HTTPS Reverse Proxy 구성"
if istrue "$INSTALL_NGINX"; then
  [[ "$NGINX_TLS_MODE" == "selfsigned" || ( -s "$NGINX_TLS_CERT_FILE" && -s "$NGINX_TLS_KEY_FILE" ) ]] || die "Nginx TLS 인증서/키를 찾을 수 없습니다."
  if [[ "$NGINX_TLS_MODE" == "selfsigned" && ( ! -s "$NGINX_TLS_CERT_FILE" || ! -s "$NGINX_TLS_KEY_FILE" ) ]]; then
    _nginx_cn="$NGINX_TLS_CN"
    if [[ -z "$_nginx_cn" ]]; then _nginx_cn="$(hostname -I 2>/dev/null | awk '{print $1}')"; fi
    [[ -n "$_nginx_cn" ]] || _nginx_cn="$(hostname -f 2>/dev/null || hostname)"
    mkdir -p "$(dirname "$NGINX_TLS_CERT_FILE")" "$(dirname "$NGINX_TLS_KEY_FILE")"
    _san="DNS:${_nginx_cn}"
    if [[ "$_nginx_cn" =~ ^[0-9a-fA-F:.]+$ ]]; then _san="IP:${_nginx_cn}"; fi
    openssl req -x509 -nodes -days "$NGINX_TLS_DAYS" -newkey rsa:2048 \
      -keyout "$NGINX_TLS_KEY_FILE" -out "$NGINX_TLS_CERT_FILE" \
      -subj "/C=KR/ST=Seoul/L=Seoul/O=IT/CN=${_nginx_cn}" -addext "subjectAltName=${_san}" >/dev/null 2>&1
    chmod 600 "$NGINX_TLS_KEY_FILE"; chmod 644 "$NGINX_TLS_CERT_FILE"
    log "Nginx self-signed 인증서 생성: CN=$_nginx_cn"
  fi
  if istrue "$NGINX_DISABLE_DEFAULT_SITE"; then rm -f /etc/nginx/sites-enabled/default; fi
  cat >/etc/nginx/conf.d/kibana.conf <<EOF_NGINX
server {
    listen ${NGINX_HTTP_PORT};
    server_name ${NGINX_SERVER_NAME};
$(istrue "$NGINX_REDIRECT_HTTP_TO_HTTPS" && echo "    return 301 https://\$host\$request_uri;" || echo "    location / { proxy_pass http://${NGINX_PROXY_HOST}:${NGINX_PROXY_PORT}; }")
}

server {
    listen ${NGINX_HTTPS_PORT} ssl;
    server_name ${NGINX_SERVER_NAME};

    ssl_certificate ${NGINX_TLS_CERT_FILE};
    ssl_certificate_key ${NGINX_TLS_KEY_FILE};
    ssl_protocols ${NGINX_TLS_PROTOCOLS};
    ssl_ciphers ${NGINX_TLS_CIPHERS};
    client_max_body_size ${NGINX_CLIENT_MAX_BODY_SIZE};

    location / {
        proxy_pass http://${NGINX_PROXY_HOST}:${NGINX_PROXY_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF_NGINX
  nginx -t || die "Nginx configuration test 실패"
  log "Nginx Reverse Proxy 구성 완료: ${NGINX_HTTP_PORT} -> HTTPS ${NGINX_HTTPS_PORT} -> Kibana ${NGINX_PROXY_HOST}:${NGINX_PROXY_PORT}"
fi

# ----------------------------- ProxySG MAIN/SSL copy/backup process -----------------------------
overall_progress 87 "MAIN/SSL 자동 복사·백업 처리 구성"
if istrue "$PROXYSG_FLOW_ENABLED"; then
  [[ -f "$SCRIPT_DIR/proxysg-log-process.sh" ]] || die "필수 파일 없음: $SCRIPT_DIR/proxysg-log-process.sh"
  # v2.9.4: Config Wizard에서 스크립트를 수정했을 수 있으므로 설치 전에 문법을 검사한다.
  bash -n "$SCRIPT_DIR/proxysg-log-process.sh" || die "proxysg-log-process.sh 문법 오류: Config Wizard에서 수정한 스크립트를 확인하세요."
  install -m 750 "$SCRIPT_DIR/proxysg-log-process.sh" "$PROXYSG_PROCESS_SCRIPT"
  touch "$PROXYSG_PROCESS_LOG"; chmod 640 "$PROXYSG_PROCESS_LOG"
  # 이전 버전이 같은 처리를 다른 이름으로 등록해 두었다면 정리한다. (이름 변경 후 같은 처리가 두 번 실행되는 것을 방지)
  if [[ -e /etc/cron.d/elk-guide-log-process || -e /usr/local/sbin/elk-guide-log-process ]]; then
    log "이전 이름으로 등록된 파일 처리 스케줄/스크립트를 정리합니다."
    rm -f /etc/cron.d/elk-guide-log-process /usr/local/sbin/elk-guide-log-process
  fi
  cat >/etc/cron.d/elk-proxysg-log-process <<EOF_PROXYSG_CRON
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
${PROXYSG_PROCESS_CRON} root ${PROXYSG_PROCESS_SCRIPT} /etc/elk-auto/elk.env >> ${PROXYSG_PROCESS_LOG} 2>&1
EOF_PROXYSG_CRON
  chmod 644 /etc/cron.d/elk-proxysg-log-process
  log "로그 처리 스크립트 cron 등록: $PROXYSG_PROCESS_CRON"
fi

# ----------------------------- managed file ingest / ops / monitoring -----------------------------
overall_progress 89 "운영/모니터링 자동화 구성"
mkdir -p /etc/elk-auto
install -m 600 "$ENV_FILE" /etc/elk-auto/elk.env

if [[ -f "$SCRIPT_DIR/elk-ops.sh" ]]; then
  install -m 750 "$SCRIPT_DIR/elk-ops.sh" /usr/local/sbin/elk-ops
fi
if [[ -f "$SCRIPT_DIR/check-elk.sh" ]]; then
  install -m 750 "$SCRIPT_DIR/check-elk.sh" /usr/local/sbin/elk-check
fi

if istrue "$FILE_INGEST_MANAGER_ENABLED"; then
  [[ -f "$SCRIPT_DIR/log-ingest-manager.sh" ]] || die "필수 파일 없음: $SCRIPT_DIR/log-ingest-manager.sh"
  install -m 750 "$SCRIPT_DIR/log-ingest-manager.sh" /usr/local/sbin/elk-log-ingest-manager
  cat >/etc/systemd/system/elk-log-ingest.service <<EOF_INGEST_SERVICE
[Unit]
Description=ELK Managed File Ingest Reconciler
After=network-online.target logstash.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/elk-log-ingest-manager /etc/elk-auto/elk.env run
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF_INGEST_SERVICE
  cat >/etc/systemd/system/elk-log-ingest.timer <<EOF_INGEST_TIMER
[Unit]
Description=Run ELK Managed File Ingest periodically

[Timer]
OnBootSec=2min
OnUnitActiveSec=${FILE_INGEST_SCAN_INTERVAL}
RandomizedDelaySec=${FILE_INGEST_TIMER_RANDOM_DELAY}
Persistent=true
Unit=elk-log-ingest.service

[Install]
WantedBy=timers.target
EOF_INGEST_TIMER

  cat >/etc/logrotate.d/elk-file-ingest <<EOF_INGEST_ROTATE
${FILE_INGEST_LOG} ${FILE_INGEST_COMPLETED_LOG} {
  daily
  rotate 30
  compress
  delaycompress
  missingok
  notifempty
  copytruncate
}
EOF_INGEST_ROTATE
fi

if istrue "$HEALTH_MONITOR_ENABLED"; then
  [[ -f "$SCRIPT_DIR/elk-health-monitor.sh" ]] || die "필수 파일 없음: $SCRIPT_DIR/elk-health-monitor.sh"
  install -m 750 "$SCRIPT_DIR/elk-health-monitor.sh" /usr/local/sbin/elk-health-monitor
  cat >/etc/systemd/system/elk-health-monitor.service <<EOF_HEALTH_SERVICE
[Unit]
Description=ELK Health Monitor
After=network-online.target elasticsearch.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/elk-health-monitor /etc/elk-auto/elk.env
Nice=10
EOF_HEALTH_SERVICE
  cat >/etc/systemd/system/elk-health-monitor.timer <<EOF_HEALTH_TIMER
[Unit]
Description=Run ELK Health Monitor periodically

[Timer]
OnBootSec=3min
OnUnitActiveSec=${HEALTH_MONITOR_INTERVAL}
RandomizedDelaySec=${HEALTH_MONITOR_RANDOM_DELAY}
Persistent=true
Unit=elk-health-monitor.service

[Install]
WantedBy=timers.target
EOF_HEALTH_TIMER
  cat >/etc/logrotate.d/elk-health-monitor <<EOF_HEALTH_ROTATE
${HEALTH_MONITOR_LOG} {
  daily
  rotate 30
  compress
  delaycompress
  missingok
  notifempty
  copytruncate
}
EOF_HEALTH_ROTATE
fi
systemctl daemon-reload

# ----------------------------- snapshots -----------------------------
overall_progress 91 "Snapshot / SLM 구성"
if istrue "$INSTALL_ELASTICSEARCH" && istrue "$SNAPSHOT_REPO_ENABLED"; then
  repo_body="$(jq -n --arg loc "$SNAPSHOT_REPO_PATH" \
    --argjson comp "$(istrue "$SNAPSHOT_COMPRESS" && echo true || echo false)" \
    --argjson ro "$(istrue "$SNAPSHOT_READONLY" && echo true || echo false)" \
    '{type:"fs",settings:{location:$loc,compress:$comp,readonly:$ro}}')"
  resp="$(es_curl PUT "/_snapshot/${SNAPSHOT_REPO_NAME}" "$repo_body")"
  [[ "$(echo "$resp" | jq -r '.acknowledged // false')" == "true" ]] || die "Snapshot repository 생성 실패: $resp"
  log "Snapshot repository 등록: $SNAPSHOT_REPO_NAME"

  if istrue "$SLM_POLICY_ENABLED"; then
    slm_indices_json="$(csv_to_json_array "$SLM_INDICES")"
    slm_body="$(jq -n \
      --arg sched "$SLM_SCHEDULE" --arg name "$SLM_SNAPSHOT_NAME" --arg repo "$SNAPSHOT_REPO_NAME" \
      --argjson indices "$slm_indices_json" \
      --argjson ign "$(istrue "$SLM_IGNORE_UNAVAILABLE" && echo true || echo false)" \
      --argjson gs "$(istrue "$SLM_INCLUDE_GLOBAL_STATE" && echo true || echo false)" \
      --arg exp "$SLM_RETENTION_EXPIRE_AFTER" --arg min "$SLM_RETENTION_MIN_COUNT" --arg max "$SLM_RETENTION_MAX_COUNT" '
      {schedule:$sched,name:$name,repository:$repo,config:{indices:$indices,ignore_unavailable:$ign,include_global_state:$gs},retention:{expire_after:$exp,min_count:($min|tonumber),max_count:($max|tonumber)}}')"
    resp="$(es_curl PUT "/_slm/policy/${SLM_POLICY_NAME}" "$slm_body")"
    [[ "$(echo "$resp" | jq -r '.acknowledged // false')" == "true" ]] || die "SLM policy 생성 실패: $resp"
    log "SLM Policy 적용: $SLM_POLICY_NAME"
  fi
fi

# ----------------------------- services -----------------------------
overall_progress 93 "서비스 Enable/Start"
manage_service() {
  local svc="$1" install_flag="$2"
  istrue "$install_flag" || return 0
  if istrue "$ENABLE_SERVICES_ON_BOOT"; then systemctl enable "$svc" >/dev/null; fi
  if istrue "$START_SERVICES_AFTER_INSTALL"; then systemctl restart "$svc"; fi
}

manage_service elasticsearch "$INSTALL_ELASTICSEARCH"
manage_service kibana "$INSTALL_KIBANA"
manage_service logstash "$INSTALL_LOGSTASH"
manage_service vsftpd "$INSTALL_FTP_SERVER"
manage_service nginx "$INSTALL_NGINX"

if istrue "$FILE_INGEST_MANAGER_ENABLED"; then
  systemctl enable elk-log-ingest.timer >/dev/null
  if istrue "$START_SERVICES_AFTER_INSTALL"; then systemctl restart elk-log-ingest.timer; fi
fi
if istrue "$HEALTH_MONITOR_ENABLED"; then
  systemctl enable elk-health-monitor.timer >/dev/null
  if istrue "$START_SERVICES_AFTER_INSTALL"; then systemctl restart elk-health-monitor.timer; fi
fi

# ----------------------------- firewall -----------------------------
overall_progress 95 "UFW 방화벽 구성"
ufw_allow_list() {
  local csv="$1" port="$2" proto="${3:-tcp}" item
  [[ -n "$csv" ]] || return 0
  IFS=',' read -ra arr <<< "$csv"
  for item in "${arr[@]}"; do
    item="$(echo "$item" | xargs)"
    [[ -n "$item" ]] || continue
    ufw allow from "$item" to any port "$port" proto "$proto" >/dev/null
  done
}

if istrue "$UFW_MANAGE"; then
  apt_install_progress "UFW" ufw
  if istrue "$INSTALL_NGINX"; then
    ufw_allow_list "$UFW_NGINX_ALLOWED_CIDRS" "$NGINX_HTTP_PORT" tcp
    ufw_allow_list "$UFW_NGINX_ALLOWED_CIDRS" "$NGINX_HTTPS_PORT" tcp
  else
    ufw_allow_list "$UFW_KIBANA_ALLOWED_CIDRS" "$KIBANA_SERVER_PORT" tcp
  fi
  ufw_allow_list "$UFW_ELASTICSEARCH_ALLOWED_CIDRS" "$ES_HTTP_PORT" tcp
  if istrue "$LS_TCP_ENABLED"; then ufw_allow_list "$UFW_LOGSTASH_ALLOWED_CIDRS" "$LS_TCP_PORT" tcp; fi
  if istrue "$LS_UDP_ENABLED"; then ufw_allow_list "$UFW_LOGSTASH_ALLOWED_CIDRS" "$LS_UDP_PORT" udp; fi
  if istrue "$LS_SYSLOG_ENABLED"; then
    ufw_allow_list "$UFW_LOGSTASH_ALLOWED_CIDRS" "$LS_SYSLOG_PORT" tcp
    ufw_allow_list "$UFW_LOGSTASH_ALLOWED_CIDRS" "$LS_SYSLOG_PORT" udp
  fi
  if istrue "$LS_BEATS_ENABLED"; then ufw_allow_list "$UFW_LOGSTASH_ALLOWED_CIDRS" "$LS_BEATS_PORT" tcp; fi
  if istrue "$LS_HTTP_ENABLED"; then ufw_allow_list "$UFW_LOGSTASH_ALLOWED_CIDRS" "$LS_HTTP_PORT" tcp; fi
  if istrue "$INSTALL_FTP_SERVER"; then
    ufw_allow_list "$UFW_FTP_ALLOWED_CIDRS" "$FTP_LISTEN_PORT" tcp
    if istrue "$FTP_PASV_ENABLE" && [[ "$FTP_PASV_MIN_PORT" != "$FTP_PASV_MAX_PORT" ]]; then
      IFS=',' read -ra ftp_cidrs <<< "$UFW_FTP_ALLOWED_CIDRS"
      for item in "${ftp_cidrs[@]}"; do
        item="$(echo "$item" | xargs)"; [[ -n "$item" ]] || continue
        ufw allow from "$item" to any port "${FTP_PASV_MIN_PORT}:${FTP_PASV_MAX_PORT}" proto tcp >/dev/null
      done
    elif istrue "$FTP_PASV_ENABLE"; then
      ufw_allow_list "$UFW_FTP_ALLOWED_CIDRS" "$FTP_PASV_MIN_PORT" tcp
    fi
  fi
  if istrue "$UFW_ENABLE_IF_INACTIVE" && ufw status | grep -q 'Status: inactive'; then
    ufw --force enable
  fi
fi

# ----------------------------- health & data view -----------------------------
overall_progress 97 "서비스 Health Check / Data View 확인"
if istrue "$START_SERVICES_AFTER_INSTALL"; then
  if istrue "$INSTALL_ELASTICSEARCH"; then
    if ! wait_for_http_code "$ES_LOCAL_URL" "$ES_CA" '200|401'; then
      journalctl -u elasticsearch -n 120 --no-pager || true
      die "최종 Elasticsearch Health Check 실패"
    fi
  fi

  if istrue "$INSTALL_KIBANA"; then
    KIBANA_LOCAL_URL="http://127.0.0.1:${KIBANA_SERVER_PORT}"
    if ! wait_for_http_code "$KIBANA_LOCAL_URL/api/status" "" '200|302|401'; then
      journalctl -u kibana -n 120 --no-pager || true
      die "Kibana Health Check 실패"
    fi
    log "Kibana 응답 확인"

    if istrue "$KIBANA_CREATE_DATA_VIEW" && istrue "$ES_SECURITY_ENABLED"; then
      create_data_view() {
        local _name="$1" _title="$2" _body _out _code
        _body="$(jq -n --arg title "$_title" --arg name "$_name" --arg tf "$KIBANA_DATA_VIEW_TIME_FIELD" --argjson allow "$(istrue "$KIBANA_DATA_VIEW_ALLOW_NO_INDEX" && echo true || echo false)" '{data_view:{title:$title,name:$name,timeFieldName:$tf,allowNoIndex:$allow},override:true}')"
        _out="$(curl -sS -w '\n%{http_code}' -u "${ELASTIC_USERNAME}:${ELASTIC_PASSWORD}" -H 'kbn-xsrf: true' -H 'Content-Type: application/json' -X POST "$KIBANA_LOCAL_URL/api/data_views/data_view" -d "$_body" || true)"
        _code="$(echo "$_out" | tail -n1)"
        if [[ "$_code" == "200" ]]; then log "Kibana Data View 생성/갱신: $_name ($_title)"; else warn "Kibana Data View 자동 생성 실패: $_name HTTP=$_code"; fi
      }
      if istrue "$PROXYSG_FLOW_ENABLED"; then
        create_data_view "$PROXYSG_MAIN_DATA_VIEW_NAME" "${PROXYSG_MAIN_INDEX_PREFIX}-*"
        create_data_view "$PROXYSG_SSL_DATA_VIEW_NAME" "${PROXYSG_SSL_INDEX_PREFIX}-*"
        if istrue "$PROXYSG_CLOUD_ENABLED"; then create_data_view "$PROXYSG_CLOUD_DATA_VIEW_NAME" "${PROXYSG_CLOUD_INDEX_PREFIX}-*"; fi
      else
        create_data_view "$KIBANA_DATA_VIEW_NAME" "$INDEX_MATCH_PATTERN"
      fi
    fi
  fi

  if istrue "$INSTALL_LOGSTASH"; then
    elapsed=0
    while (( elapsed < WAIT_TIMEOUT_SECONDS )); do
      if systemctl is-active --quiet logstash && nc -z 127.0.0.1 "$LOGSTASH_API_PORT" 2>/dev/null; then break; fi
      sleep 3; elapsed=$((elapsed+3))
    done
    systemctl is-active --quiet logstash || { journalctl -u logstash -n 160 --no-pager || true; die "Logstash 서비스 시작 실패"; }
    log "Logstash 서비스 정상"
  fi
  if istrue "$INSTALL_NGINX"; then
    systemctl is-active --quiet nginx || { journalctl -u nginx -n 120 --no-pager || true; die "Nginx 서비스 시작 실패"; }
    nginx -t >/dev/null 2>&1 || die "Nginx 최종 문법 검사 실패"
    log "Nginx 서비스 정상"
  fi
  if istrue "$INSTALL_FTP_SERVER"; then
    systemctl is-active --quiet vsftpd || { journalctl -u vsftpd -n 120 --no-pager || true; die "FTP(vsftpd) 서비스 시작 실패"; }
    nc -z 127.0.0.1 "$FTP_LISTEN_PORT" 2>/dev/null || warn "vsftpd는 실행 중이나 localhost:${FTP_LISTEN_PORT} 포트 확인에 실패했습니다. FTP_LISTEN_ADDRESS를 확인하십시오."
    log "FTP(vsftpd) 서비스 정상"
  fi
fi

# ----------------------------- optional test event -----------------------------
if istrue "$CREATE_TEST_EVENT" && istrue "$LS_TCP_ENABLED" && istrue "$START_SERVICES_AFTER_INSTALL"; then
  log "TCP 테스트 이벤트 전송: 127.0.0.1:${LS_TCP_PORT}"
  printf '%s\n' "$TEST_EVENT_MESSAGE" | nc -w 2 127.0.0.1 "$LS_TCP_PORT" || warn "테스트 이벤트 전송 실패"
fi

# ----------------------------- post install -----------------------------
if [[ -n "$POST_INSTALL_SCRIPT" ]]; then
  [[ -f "$POST_INSTALL_SCRIPT" ]] || die "POST_INSTALL_SCRIPT 없음: $POST_INSTALL_SCRIPT"
  log "Post-install script 실행: $POST_INSTALL_SCRIPT"
  bash "$POST_INSTALL_SCRIPT"
fi

# ----------------------------- result -----------------------------
overall_progress 100 "설치 구성 완료"
server_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
[[ -n "$server_ip" ]] || server_ip="SERVER_IP"

cat <<RESULT

===============================================================================
 ELK Auto Installer 완료
===============================================================================
 Hostname              : $(hostname)
 Elasticsearch         : $(systemctl is-active elasticsearch 2>/dev/null || echo n/a)
 Kibana                : $(systemctl is-active kibana 2>/dev/null || echo n/a)
 Logstash              : $(systemctl is-active logstash 2>/dev/null || echo n/a)
 Nginx                 : $(systemctl is-active nginx 2>/dev/null || echo n/a)
 FTP(vsftpd)           : $(systemctl is-active vsftpd 2>/dev/null || echo n/a)

 Elasticsearch URL     : ${ES_LOCAL_URL}
 Kibana Login          : $(istrue "$KIBANA_LOGIN_ENABLED" && echo "사용(로그인 필요)" || echo "비활성(읽기 전용 익명 접속)")
 Kibana URL            : $(istrue "$INSTALL_NGINX" && echo "https://${server_ip}:${NGINX_HTTPS_PORT}" || echo "http://${server_ip}:${KIBANA_SERVER_PORT}")
 Index Mode            : ${INDEX_MODE}
 Index Prefix          : ${INDEX_PREFIX}
 Index Template        : ${INDEX_TEMPLATE_NAME}
 Index Patterns        : ${INDEX_TEMPLATE_PATTERNS}
 ILM Policy            : ${ILM_POLICY_NAME}
 ILM Delete Age        : ${ILM_DELETE_MIN_AGE}
 Elasticsearch Data    : ${ES_PATH_DATA}
 Logstash Pipeline     : ${LOGSTASH_PIPELINE_FILE}
 FTP Server            : ${INSTALL_FTP_SERVER}
 FTP Upload            : ${FTP_USER}@${server_ip}:${FTP_LISTEN_PORT} -> ${FTP_UPLOAD_DIR}
 FTP Passive Ports     : ${FTP_PASV_MIN_PORT}-${FTP_PASV_MAX_PORT}
 FTP TLS               : ${FTP_TLS_ENABLED}
 ProxySG Flow         : ${PROXYSG_FLOW_ENABLED}
 File Ingest Manager   : ${FILE_INGEST_MANAGER_ENABLED}
 File Source(s)        : ${FILE_INGEST_SOURCE_DIRS}
 File Backup           : ${FILE_INGEST_BACKUP_DIR}
 Health Monitor        : ${HEALTH_MONITOR_ENABLED}
 Secrets File          : ${SECRETS_FILE}
 Install Log           : ${INSTALL_LOG}
===============================================================================

중요:
  sudo chmod 600 ${ENV_FILE}
  sudo cat ${SECRETS_FILE}

서비스 확인:
  systemctl status elasticsearch --no-pager
  systemctl status kibana --no-pager
  systemctl status logstash --no-pager
  systemctl status nginx --no-pager
  systemctl status vsftpd --no-pager
  sudo elk-ops status
  sudo elk-ops indices
  sudo elk-ops ingest
  sudo elk-check /etc/elk-auto/elk.env
RESULT

if istrue "$LS_TCP_ENABLED"; then echo " Logstash TCP Input     : ${server_ip}:${LS_TCP_PORT}"; fi
if istrue "$LS_UDP_ENABLED"; then echo " Logstash UDP Input     : ${server_ip}:${LS_UDP_PORT}"; fi
if istrue "$LS_BEATS_ENABLED"; then echo " Logstash Beats Input   : ${server_ip}:${LS_BEATS_PORT}"; fi
if istrue "$LS_HTTP_ENABLED"; then echo " Logstash HTTP Input    : ${server_ip}:${LS_HTTP_PORT}"; fi

echo
log "완료"
