#!/usr/bin/env bash
# ELK OneClick Adopt v2.9.23
# 기존/수동 구축 ELK를 재설치 없이 OneClick 관리 대상으로 등록합니다.
set -Eeuo pipefail
VERSION="2.9.23"
MODE="${1:---inspect}"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVF="${ELK_ENV_FILE:-/etc/elk-auto/elk.env}"
STATE_DIR="${ELK_STATE_DIR:-/root/.elk-auto-installer}"
SECRETS_FILE="${ELK_SECRETS_FILE:-$STATE_DIR/secrets.env}"
BACKUP_ROOT="${ELK_ADOPT_BACKUP_DIR:-/var/backups/elk-oneclick-adopt}"
REPORT_WEB=0; FORCE=0; ELASTIC_USER_ARG=""
shift || true
while (($#)); do
  case "$1" in
    --source-dir) SOURCE_DIR="${2:?path required}"; shift 2;;
    --enable-report-web) REPORT_WEB=1; shift;;
    --elastic-user) ELASTIC_USER_ARG="${2:?user required}"; shift 2;;
    --force) FORCE=1; shift;;
    -h|--help) cat <<'EOF'
Usage:
  sudo bash elk-oneclick-adopt.sh --inspect
  sudo bash elk-oneclick-adopt.sh --apply --source-dir /path/to/_internal/core
Options: --enable-report-web --elastic-user USER --force
EOF
      exit 0;;
    *) echo "[ERROR] unknown argument: $1" >&2; exit 2;;
  esac
done
case "$MODE" in
  --inspect|inspect|--apply|apply) ;;
  -h|--help)
    cat <<'EOF'
Usage:
  sudo bash elk-oneclick-adopt.sh --inspect
  sudo bash elk-oneclick-adopt.sh --apply --source-dir /path/to/_internal/core
Options: --enable-report-web --elastic-user USER --force
EOF
    exit 0 ;;
  *) echo "[ERROR] use --inspect or --apply" >&2; exit 2 ;;
esac

say(){ printf '%s\n' "$*"; }; warn(){ say "[WARN] $*" >&2; }; die(){ say "[ERROR] $*" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }
active(){ have systemctl && systemctl is-active --quiet "$1" 2>/dev/null; }
first(){ local f; for f in "$@"; do [[ -e "$f" ]] && { printf '%s' "$f"; return; }; done; }
yv(){ local f="$1" k="$2"; [[ -r "$f" ]] || return 0; awk -v k="$k" '
/^[[:space:]]*#/ {next}
{p=index($0,":"); if(!p)next; kk=substr($0,1,p-1); gsub(/^[ \t]+|[ \t]+$/,"",kk); if(kk==k){v=substr($0,p+1); sub(/[ \t]+#.*/,"",v); gsub(/^[ \t]+|[ \t]+$/,"",v); gsub(/^["'\'']|["'\'']$/,"",v); print v; exit}}' "$f"; }
q(){ printf '%q' "$1"; }

ES_CFG="$(first /etc/elasticsearch/elasticsearch.yml /usr/local/etc/elasticsearch/elasticsearch.yml || true)"
KB_CFG="$(first /etc/kibana/kibana.yml /usr/local/etc/kibana/kibana.yml || true)"
LS_CFG="$(first /etc/logstash/logstash.yml /usr/local/etc/logstash/logstash.yml || true)"
LS_PIPES="$(first /etc/logstash/pipelines.yml /usr/local/etc/logstash/pipelines.yml || true)"
ES_BIN="$(command -v elasticsearch 2>/dev/null || true)"; [[ -z "$ES_BIN" && -x /usr/share/elasticsearch/bin/elasticsearch ]] && ES_BIN=/usr/share/elasticsearch/bin/elasticsearch
KB_BIN="$(command -v kibana 2>/dev/null || true)"; [[ -z "$KB_BIN" && -x /usr/share/kibana/bin/kibana ]] && KB_BIN=/usr/share/kibana/bin/kibana
LS_BIN="$(command -v logstash 2>/dev/null || true)"; [[ -z "$LS_BIN" && -x /usr/share/logstash/bin/logstash ]] && LS_BIN=/usr/share/logstash/bin/logstash

ES_PORT="${ES_CFG:+$(yv "$ES_CFG" http.port)}"; ES_PORT="${ES_PORT:-9200}"
KB_PORT="${KB_CFG:+$(yv "$KB_CFG" server.port)}"; KB_PORT="${KB_PORT:-5601}"
ES_CLUSTER="${ES_CFG:+$(yv "$ES_CFG" cluster.name)}"; ES_CLUSTER="${ES_CLUSTER:-elasticsearch}"
ES_NODE="${ES_CFG:+$(yv "$ES_CFG" node.name)}"; ES_NODE="${ES_NODE:-$(hostname -s 2>/dev/null || hostname)}"
ES_DATA="${ES_CFG:+$(yv "$ES_CFG" path.data)}"; ES_DATA="${ES_DATA:-/var/lib/elasticsearch}"
ES_LOGS="${ES_CFG:+$(yv "$ES_CFG" path.logs)}"; ES_LOGS="${ES_LOGS:-/var/log/elasticsearch}"
ES_SEC="${ES_CFG:+$(yv "$ES_CFG" xpack.security.enabled)}"; ES_SEC="${ES_SEC:-true}"
ES_TLS="${ES_CFG:+$(yv "$ES_CFG" xpack.security.http.ssl.enabled)}"; ES_TLS="${ES_TLS:-false}"
[[ "${ES_TLS,,}" == true ]] && ES_URL="https://127.0.0.1:$ES_PORT" || ES_URL="http://127.0.0.1:$ES_PORT"
KB_URL="http://127.0.0.1:$KB_PORT"
probe(){ local u="$1" k="${2:-0}" a=(-sS -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5); ((k))&&a+=(-k); curl "${a[@]}" "$u" 2>/dev/null || printf 000; }
ES_HTTP="$(probe "$ES_URL" "$([[ "${ES_TLS,,}" == true ]]&&echo 1||echo 0)")"; KB_HTTP="$(probe "$KB_URL")"

[[ -n "$ES_CFG" || -n "$ES_BIN" || "$ES_HTTP" != 000 ]] || die "Elasticsearch 설치를 확인하지 못했습니다."
say "ELK OneClick Adopt v$VERSION"
say "  Elasticsearch config : ${ES_CFG:-확인 불가}"
say "  Kibana config        : ${KB_CFG:-확인 불가}"
say "  Logstash config      : ${LS_CFG:-확인 불가}"
say "  Logstash pipelines   : ${LS_PIPES:-확인 불가}"
say "  Elasticsearch URL    : $ES_URL (HTTP $ES_HTTP)"
say "  Kibana URL           : $KB_URL (HTTP $KB_HTTP)"
say "  Services             : ES=$(active elasticsearch&&echo active||echo inactive) Kibana=$(active kibana&&echo active||echo inactive) Logstash=$(active logstash&&echo active||echo inactive)"

if [[ "$MODE" == --inspect || "$MODE" == inspect ]]; then
  say "[OK] 읽기 전용 검사 완료. ELK 패키지/설정은 변경하지 않았습니다."
  [[ -f "$ENVF" ]] && say "[INFO] $ENVF 가 이미 존재합니다." || say "[READY] --apply 가능"
  exit 0
fi

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "root 권한이 필요합니다."
[[ -d "$SOURCE_DIR" ]] || die "source dir not found: $SOURCE_DIR"
for f in elk-patch.sh elk-report.sh elk-report-web.py elk-oneclick-update.sh; do [[ -f "$SOURCE_DIR/$f" ]] || die "필수 파일 없음: $SOURCE_DIR/$f"; done
[[ ! -f "$ENVF" || $FORCE -eq 1 ]] || die "$ENVF 가 이미 있습니다. 기존 OneClick 서버라면 adopt가 필요 없습니다. 강제 재등록은 --force."

TS="$(date +%Y%m%d-%H%M%S)"; BK="$BACKUP_ROOT/$TS"; install -d -m 700 "$BK"
for f in "$ES_CFG" "$KB_CFG" "$LS_CFG" "$LS_PIPES"; do [[ -n "$f" && -f "$f" ]] && { cp -a --parents "$f" "$BK/" 2>/dev/null || cp -a "$f" "$BK/$(basename "$f")"; }; done
[[ -d /etc/logstash/conf.d ]] && cp -a /etc/logstash/conf.d "$BK/logstash-conf.d"
[[ -f "$ENVF" ]] && cp -a "$ENVF" "$BK/elk.env.before-adopt"
install -d -m 755 /etc/elk-auto /usr/local/lib/elk-auto /usr/local/sbin "$STATE_DIR"

EU="${ELASTIC_USER_ARG:-elastic}"; EP=""
if [[ "$ES_HTTP" == 401 || "${ES_SEC,,}" == true ]]; then
  if [[ -t 0 ]]; then read -rp "Elasticsearch 사용자 [$EU]: " X; [[ -n "$X" ]]&&EU="$X"; read -rsp "Elasticsearch Password (Enter=나중에): " EP; printf '\n'; else warn "Password는 저장하지 않았습니다."; fi
fi

cat >"$ENVF" <<EOF_ENV
ELK_ADOPTED_SERVER="true"
ELK_ADOPTED_AT="$(date -Is)"
ELK_ADOPT_BACKUP="$BK"
INSTALL_ELASTICSEARCH="false"
INSTALL_KIBANA="false"
INSTALL_LOGSTASH="false"
ES_CLUSTER_NAME=$(q "$ES_CLUSTER")
ES_NODE_NAME=$(q "$ES_NODE")
ES_HTTP_PORT=$(q "$ES_PORT")
ES_PATH_DATA=$(q "$ES_DATA")
ES_PATH_LOGS=$(q "$ES_LOGS")
ES_SECURITY_ENABLED=$(q "$ES_SEC")
ES_HTTP_TLS_ENABLED=$(q "$ES_TLS")
ELASTIC_USERNAME=$(q "$EU")
KIBANA_SERVER_PORT=$(q "$KB_PORT")
KIBANA_SERVER_HOST="127.0.0.1"
KIBANA_CREATE_DATA_VIEW="false"
KIBANA_CREATE_PROXYSG_DASHBOARD="false"
LOGSTASH_PATH_DATA="/var/lib/logstash"
LOGSTASH_PATH_LOGS="/var/log/logstash"
PROXYSG_FLOW_ENABLED="false"
PROXYSG_CLOUD_ENABLED="false"
PROXYSG_MAIN_INDEX_PREFIX="proxy-main"
PROXYSG_SSL_INDEX_PREFIX="proxy-ssl"
PROXYSG_CLOUD_INDEX_PREFIX="proxy-cloud"
PROXYSG_MAIN_DATA_VIEW_NAME="main"
PROXYSG_SSL_DATA_VIEW_NAME="ssl"
PROXYSG_CLOUD_DATA_VIEW_NAME="cloud"
PROXYSG_PROCESS_SCRIPT="/usr/local/sbin/elk-proxysg-log-process"
ELK_REPORT_WEB_ENABLED="$([[ $REPORT_WEB -eq 1 ]]&&echo true||echo false)"
ELK_REPORT_WEB_HOST="127.0.0.1"
ELK_REPORT_WEB_PORT="5602"
ELK_REPORT_HTML_DIR="/var/lib/elk-report"
ELK_REPORT_HTML_FILE="/var/lib/elk-report/report.html"
EOF_ENV
chmod 600 "$ENVF"
[[ -n "$EP" ]] && { printf 'ELASTIC_PASSWORD=%q\n' "$EP" >"$SECRETS_FILE"; chmod 600 "$SECRETS_FILE"; }

install -m 755 "$SOURCE_DIR/elk-patch.sh" /usr/local/sbin/elk-patch
install -m 755 "$SOURCE_DIR/elk-report.sh" /usr/local/sbin/elk-report
install -m 755 "$SOURCE_DIR/elk-report-web.py" /usr/local/lib/elk-auto/elk-report-web.py
install -m 755 "$SOURCE_DIR/elk-oneclick-update.sh" /usr/local/sbin/elk-oneclick-update
[[ -f "$SOURCE_DIR/elk-oneclick-adopt.sh" ]] && install -m 755 "$SOURCE_DIR/elk-oneclick-adopt.sh" /usr/local/sbin/elk-oneclick-adopt
[[ -f "$SOURCE_DIR/proxysg-log-process.sh" ]] && install -m 755 "$SOURCE_DIR/proxysg-log-process.sh" /usr/local/sbin/elk-proxysg-log-process
for f in proxysg-log-filter.conf proxysg-lib.sh elk-tls-lib.sh elk-color.sh; do [[ -f "$SOURCE_DIR/$f" ]] && install -m 644 "$SOURCE_DIR/$f" "/usr/local/lib/elk-auto/$f"; done

if ((REPORT_WEB)); then
  install -d -m 755 /var/lib/elk-report
  cat >/etc/systemd/system/elk-report-web.service <<'EOF'
[Unit]
Description=ELK Report Web Viewer (OneClick Adopted)
After=network.target elasticsearch.service
[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/lib/elk-auto/elk-report-web.py --host 127.0.0.1 --port 5602 --report /usr/local/sbin/elk-report --html /var/lib/elk-report/report.html --env /etc/elk-auto/elk.env
Restart=on-failure
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/var/lib/elk-report /var/log /run /tmp
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload; systemctl enable --now elk-report-web.service
fi

cat >/etc/elk-auto/oneclick-release.env <<EOF
ONECLICK_VERSION="$VERSION"
ONECLICK_BUILD="adopted-existing-elk"
ONECLICK_INSTALLED_AT="$(date -Is)"
ONECLICK_UPDATE_MODE="adopted"
EOF
cat >/etc/elk-auto/adopted.env <<EOF
ELK_ADOPTED_SERVER="true"
ELK_ADOPTED_AT="$(date -Is)"
ELK_ADOPT_BACKUP="$BK"
ELASTICSEARCH_CONFIG=$(q "$ES_CFG")
KIBANA_CONFIG=$(q "$KB_CFG")
LOGSTASH_CONFIG=$(q "$LS_CFG")
LOGSTASH_PIPELINES=$(q "$LS_PIPES")
EOF
chmod 600 /etc/elk-auto/adopted.env
say "[OK] 기존 ELK를 OneClick 관리 대상으로 등록했습니다."
say "  기존 ELK 패키지/설정 변경 : 없음"
say "  백업 : $BK"
say "  env  : $ENVF"
