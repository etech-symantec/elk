#!/usr/bin/env bash
set -Eeuo pipefail
ENV_FILE="${1:-/etc/elk-auto/elk.env}"
[[ -f "$ENV_FILE" ]] || { echo "[FAIL] 환경파일 없음: $ENV_FILE" >&2; exit 2; }
# shellcheck disable=SC1090
source "$ENV_FILE"

: "${INSTALL_ELASTICSEARCH:=true}"
: "${INSTALL_KIBANA:=true}"
: "${INSTALL_LOGSTASH:=true}"
: "${INSTALL_NGINX:=false}"
: "${INSTALL_FTP_SERVER:=false}"
: "${ES_HTTP_PORT:=9200}"
: "${ES_SECURITY_ENABLED:=true}"
: "${ES_HTTP_TLS_ENABLED:=true}"
: "${ELASTIC_USERNAME:=elastic}"
: "${ELASTIC_PASSWORD:=}"
: "${SECRETS_FILE:=/root/.elk-auto-installer/secrets.env}"
: "${KIBANA_SERVER_PORT:=5601}"
: "${NGINX_HTTPS_PORT:=443}"
: "${LOGSTASH_API_PORT:=9600}"
: "${FTP_LISTEN_PORT:=21}"
: "${INDEX_PREFIX:=network-log}"
: "${INDEX_MODE:=daily}"
: "${ILM_POLICY_NAME:=${INDEX_PREFIX}-ilm}"
: "${INDEX_TEMPLATE_NAME:=${INDEX_PREFIX}-template}"
: "${ILM_ROLLOVER_ALIAS:=${INDEX_PREFIX}}"
: "${PROXYSG_FLOW_ENABLED:=false}"
: "${PROXYSG_MAIN_INDEX_PREFIX:=proxy-main}"
: "${PROXYSG_SSL_INDEX_PREFIX:=proxy-ssl}"
: "${PROXYSG_CLOUD_ENABLED:=false}"
: "${PROXYSG_CLOUD_INDEX_PREFIX:=proxy-cloud}"
: "${PROXYSG_CLOUD_SOURCE_DIR:=/home/cloud}"
: "${PROXYSG_CLOUD_PROCESS_DIR:=/home/cloud_process}"
: "${PROXYSG_ILM_POLICY_NAME:=proxy-retention-policy}"
: "${PROXYSG_INDEX_TEMPLATE_NAME:=proxy-index-template}"
: "${PROXYSG_MAIN_SOURCE_DIR:=/home/main}"
: "${PROXYSG_SSL_SOURCE_DIR:=/home/ssl}"
: "${PROXYSG_MAIN_PROCESS_DIR:=/home/main_process}"
: "${PROXYSG_SSL_PROCESS_DIR:=/home/ssl_process}"
: "${ES_PATH_DATA:=/var/lib/elasticsearch}"
: "${FILE_INGEST_MANAGER_ENABLED:=false}"
: "${FILE_INGEST_SOURCE_DIRS:=/log/incoming}"
: "${FILE_INGEST_STAGING_DIR:=/var/lib/elk-file-ingest/staging}"
: "${FILE_INGEST_BACKUP_DIR:=/backup/logs}"
: "${HEALTH_MONITOR_ENABLED:=false}"
: "${ILM_DELETE_MIN_AGE:=90d}"
: "${SNAPSHOT_REPO_ENABLED:=false}"
: "${SNAPSHOT_REPO_NAME:=local-backup}"
: "${SLM_POLICY_ENABLED:=false}"
: "${SLM_POLICY_NAME:=daily-snapshot}"
: "${UFW_MANAGE:=false}"
: "${VM_MAX_MAP_COUNT:=1048576}"
: "${SYSTEM_SWAPPINESS:=1}"
: "${DISABLE_SWAP:=false}"
: "${LOGSTASH_PIPELINE_FILE:=/etc/logstash/conf.d/logstash.conf}"
: "${LOGSTASH_HEAP_MIN:=2g}"
: "${LOGSTASH_HEAP_MAX:=2g}"
: "${PROXYSG_PROCESS_SCRIPT:=/usr/local/sbin/elk-proxysg-log-process}"
: "${PROXYSG_PROCESS_CRON:=0 3 * * *}"
: "${ELK_REPORT_WEB_ENABLED:=true}"
: "${ELK_REPORT_WEB_PORT:=8088}"
: "${ES_CLUSTER_NAME:=elk-cluster}"
: "${ES_NETWORK_HOST:=0.0.0.0}"

istrue(){ [[ "${1,,}" =~ ^(1|true|yes|y|on)$ ]]; }
if [[ -f "$SECRETS_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$SECRETS_FILE"
fi

if istrue "$PROXYSG_FLOW_ENABLED"; then
  ILM_POLICY_NAME="$PROXYSG_ILM_POLICY_NAME"
  INDEX_TEMPLATE_NAME="$PROXYSG_INDEX_TEMPLATE_NAME"
  INDEX_PATTERN="${PROXYSG_MAIN_INDEX_PREFIX}-*,${PROXYSG_SSL_INDEX_PREFIX}-*"
  if istrue "$PROXYSG_CLOUD_ENABLED"; then INDEX_PATTERN="${INDEX_PATTERN},${PROXYSG_CLOUD_INDEX_PREFIX}-*"; fi
elif [[ "$INDEX_MODE" == "rollover" ]]; then
  INDEX_PATTERN="${ILM_ROLLOVER_ALIAS}-*"
elif [[ "$INDEX_MODE" == "plain" ]]; then
  INDEX_PATTERN="$INDEX_PREFIX"
else
  INDEX_PATTERN="${INDEX_PREFIX}-*"
fi

PASS=0; WARN=0; FAIL=0
pass(){ PASS=$((PASS+1)); printf '[PASS] %s\n' "$*"; }
warn(){ WARN=$((WARN+1)); printf '[WARN] %s\n' "$*"; }
fail(){ FAIL=$((FAIL+1)); printf '[FAIL] %s\n' "$*"; }
hr(){ printf '%*s\n' 96 '' | tr ' ' '='; }
check_service(){
  local enabled="$1" svc="$2" label="$3"
  istrue "$enabled" || { printf '[SKIP] %s (비활성 설정)\n' "$label"; return; }
  if systemctl is-active --quiet "$svc"; then pass "$label 서비스 active"; else fail "$label 서비스가 active가 아님"; fi
  if systemctl is-enabled --quiet "$svc" 2>/dev/null; then pass "$label 부팅 자동 시작 enabled"; else warn "$label 부팅 자동 시작 상태 확인 필요"; fi
}

hr
echo " ELK 설치 후 전체 상태 점검"
echo " 환경파일: $ENV_FILE"
echo " 시간: $(date '+%F %T %Z')"
hr

check_service "$INSTALL_ELASTICSEARCH" elasticsearch "Elasticsearch"
check_service "$INSTALL_KIBANA" kibana "Kibana"
check_service "$INSTALL_LOGSTASH" logstash "Logstash"
check_service "$INSTALL_NGINX" nginx "Nginx"
check_service "$INSTALL_FTP_SERVER" vsftpd "FTP(vsftpd)"

if istrue "$INSTALL_ELASTICSEARCH"; then
  [[ -d "$ES_PATH_DATA" ]] && pass "Elasticsearch 데이터 경로 존재: $ES_PATH_DATA" || fail "Elasticsearch 데이터 경로 없음: $ES_PATH_DATA"
  df_line="$(df -hP "$ES_PATH_DATA" 2>/dev/null | awk 'NR==2{print $3" / "$2" ("$5")"}' || true)"
  [[ -n "$df_line" ]] && echo "[INFO] Elasticsearch 디스크: $df_line"
fi

if istrue "$PROXYSG_FLOW_ENABLED"; then
  _chk=("$PROXYSG_MAIN_SOURCE_DIR" "$PROXYSG_SSL_SOURCE_DIR" "$PROXYSG_MAIN_PROCESS_DIR" "$PROXYSG_SSL_PROCESS_DIR")
  if istrue "$PROXYSG_CLOUD_ENABLED"; then _chk+=("$PROXYSG_CLOUD_SOURCE_DIR" "$PROXYSG_CLOUD_PROCESS_DIR"); fi
  for d in "${_chk[@]}"; do
    [[ -d "$d" ]] && pass "ProxySG 경로 존재: $d" || fail "ProxySG 경로 없음: $d"
  done
fi

if istrue "$FILE_INGEST_MANAGER_ENABLED"; then
  if systemctl is-active --quiet elk-log-ingest.timer 2>/dev/null; then pass "파일 수집 timer active"; else fail "파일 수집 timer inactive"; fi
  [[ -d "$FILE_INGEST_STAGING_DIR" ]] && pass "파일 수집 staging 경로 존재" || fail "파일 수집 staging 경로 없음: $FILE_INGEST_STAGING_DIR"
  [[ -d "$FILE_INGEST_BACKUP_DIR" ]] && pass "파일 백업 경로 존재" || fail "파일 백업 경로 없음: $FILE_INGEST_BACKUP_DIR"
fi
if istrue "$HEALTH_MONITOR_ENABLED"; then
  if systemctl is-active --quiet elk-health-monitor.timer 2>/dev/null; then pass "Health Monitor timer active"; else fail "Health Monitor timer inactive"; fi
fi

if istrue "$ES_HTTP_TLS_ENABLED"; then
  ES_URL="https://127.0.0.1:${ES_HTTP_PORT}"
  CURL_TLS=(--cacert /etc/elasticsearch/certs/http_ca.crt)
else
  ES_URL="http://127.0.0.1:${ES_HTTP_PORT}"
  CURL_TLS=()
fi
CURL_AUTH=()
if istrue "$ES_SECURITY_ENABLED"; then
  if [[ -z "${ELASTIC_PASSWORD:-}" ]]; then
    fail "elastic 비밀번호를 확인할 수 없음 (환경파일/Secrets 확인)"
  else
    CURL_AUTH=(-u "${ELASTIC_USERNAME}:${ELASTIC_PASSWORD}")
  fi
fi

if istrue "$INSTALL_ELASTICSEARCH"; then
  if curl -fsS "${CURL_TLS[@]}" "${CURL_AUTH[@]}" "$ES_URL" >/dev/null 2>&1; then
    pass "Elasticsearch API 연결 성공: $ES_URL"
    health_json="$(curl -fsS "${CURL_TLS[@]}" "${CURL_AUTH[@]}" "$ES_URL/_cluster/health" 2>/dev/null || true)"
    cluster_status="$(printf '%s' "$health_json" | jq -r '.status // empty' 2>/dev/null || true)"
    case "$cluster_status" in
      green) pass "Cluster Health GREEN" ;;
      yellow) warn "Cluster Health YELLOW (단일 노드 replica 설정이면 발생 가능)" ;;
      red) fail "Cluster Health RED" ;;
      *) fail "Cluster Health 상태 확인 실패" ;;
    esac
    echo "[INFO] Cluster: $(printf '%s' "$health_json" | jq -c '{cluster_name,status,number_of_nodes,active_primary_shards,unassigned_shards}' 2>/dev/null || echo n/a)"

    if [[ "$INDEX_MODE" != "plain" ]]; then
      if curl -fsS "${CURL_TLS[@]}" "${CURL_AUTH[@]}" "$ES_URL/_ilm/policy/${ILM_POLICY_NAME}" >/dev/null 2>&1; then
        pass "ILM Policy 존재: $ILM_POLICY_NAME (기본 삭제 ${ILM_DELETE_MIN_AGE})"
      else
        fail "ILM Policy 조회 실패: $ILM_POLICY_NAME"
      fi
      if curl -fsS "${CURL_TLS[@]}" "${CURL_AUTH[@]}" "$ES_URL/_index_template/${INDEX_TEMPLATE_NAME}" >/dev/null 2>&1; then
        pass "Index Template 존재: $INDEX_TEMPLATE_NAME"
      else
        fail "Index Template 조회 실패: $INDEX_TEMPLATE_NAME"
      fi
    else
      echo "[SKIP] INDEX_MODE=plain: ILM/Index Template 점검 생략"
    fi
    if istrue "$SNAPSHOT_REPO_ENABLED"; then
      if curl -fsS "${CURL_TLS[@]}" "${CURL_AUTH[@]}" "$ES_URL/_snapshot/${SNAPSHOT_REPO_NAME}" >/dev/null 2>&1; then pass "Snapshot Repository 존재: $SNAPSHOT_REPO_NAME"; else fail "Snapshot Repository 조회 실패: $SNAPSHOT_REPO_NAME"; fi
    fi
    if istrue "$SLM_POLICY_ENABLED"; then
      if curl -fsS "${CURL_TLS[@]}" "${CURL_AUTH[@]}" "$ES_URL/_slm/policy/${SLM_POLICY_NAME}" >/dev/null 2>&1; then pass "SLM Policy 존재: $SLM_POLICY_NAME"; else fail "SLM Policy 조회 실패: $SLM_POLICY_NAME"; fi
    fi

    idx="$(curl -fsS "${CURL_TLS[@]}" "${CURL_AUTH[@]}" "$ES_URL/_cat/indices/${INDEX_PATTERN}?h=index,health,docs.count,store.size&s=index:desc" 2>/dev/null || true)"
    if [[ -n "$idx" ]]; then
      pass "대상 인덱스 확인됨: $INDEX_PATTERN"
      echo "$idx" | head -10 | sed 's/^/[INDEX] /'
    else
      warn "아직 대상 인덱스가 없음: $INDEX_PATTERN (로그가 들어오기 전이면 정상)"
    fi
  else
    fail "Elasticsearch API 연결 실패: $ES_URL"
  fi
fi

if istrue "$INSTALL_KIBANA"; then
  kcode="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${KIBANA_SERVER_PORT}/api/status" || true)"
  case "$kcode" in 200|302|401) pass "Kibana HTTP 응답 정상: $kcode" ;; *) fail "Kibana HTTP 응답 비정상: ${kcode:-000}" ;; esac
fi
if istrue "$INSTALL_NGINX"; then
  if nginx -t >/dev/null 2>&1; then pass "Nginx 설정 문법 정상"; else fail "Nginx 설정 문법 오류"; fi
  ncode="$(curl -k -s -o /dev/null -w '%{http_code}' "https://127.0.0.1:${NGINX_HTTPS_PORT}/" || true)"
  case "$ncode" in 200|302|401) pass "Nginx HTTPS 응답 정상: $ncode" ;; *) fail "Nginx HTTPS 응답 비정상: ${ncode:-000}" ;; esac
fi
if istrue "$INSTALL_LOGSTASH"; then
  lcode="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${LOGSTASH_API_PORT}/_node/pipelines" || true)"
  [[ "$lcode" == "200" ]] && pass "Logstash API 응답 정상: 200" || fail "Logstash API 응답 비정상: ${lcode:-000}"
fi
if istrue "$INSTALL_FTP_SERVER"; then
  if nc -z 127.0.0.1 "$FTP_LISTEN_PORT" 2>/dev/null; then pass "FTP Control Port OPEN: ${FTP_LISTEN_PORT}/tcp"; else fail "FTP Control Port CLOSED: ${FTP_LISTEN_PORT}/tcp"; fi
fi

# OneClick 설치 항목 / 주요 값 일치 점검
for _spec in "true:/usr/local/sbin/elk-check:elk-check" "true:/usr/local/sbin/elk-ops:elk-ops" "true:/usr/local/sbin/elk-report:elk-report" "true:/usr/local/sbin/elk-patch:elk-patch"; do
  IFS=: read -r _on _path _label <<<"$_spec"; [[ -x "$_path" ]] && pass "관리 도구 설치됨: $_label" || fail "관리 도구 없음: $_path"
done
_mm="$(sysctl -n vm.max_map_count 2>/dev/null || echo '?')"; [[ "$_mm" == "$VM_MAX_MAP_COUNT" ]] && pass "vm.max_map_count 일치: $_mm" || warn "vm.max_map_count 불일치: 기대 $VM_MAX_MAP_COUNT / 실제 $_mm"
yaml_val(){ local f="$1" k="$2"; awk -F: -v k="$k" '$1 ~ "^[[:space:]]*"k"[[:space:]]*$" {sub(/^[^:]*:[[:space:]]*/,""); gsub(/^[\"'\'' ]+|[\"'\'' ]+$/ ,""); print; exit}' "$f" 2>/dev/null || true; }
if istrue "$INSTALL_ELASTICSEARCH" && [[ -f /etc/elasticsearch/elasticsearch.yml ]]; then
  _v="$(yaml_val /etc/elasticsearch/elasticsearch.yml cluster.name)"; [[ "$_v" == "$ES_CLUSTER_NAME" ]] && pass "Elasticsearch cluster.name 일치: $_v" || warn "Elasticsearch cluster.name 불일치: 기대 $ES_CLUSTER_NAME / 실제 ${_v:-없음}"
  _v="$(yaml_val /etc/elasticsearch/elasticsearch.yml network.host)"; [[ "$_v" == "$ES_NETWORK_HOST" ]] && pass "Elasticsearch network.host 일치: $_v" || warn "Elasticsearch network.host 불일치: 기대 $ES_NETWORK_HOST / 실제 ${_v:-없음}"
fi
if istrue "$INSTALL_KIBANA" && [[ -f /etc/kibana/kibana.yml ]]; then
  _v="$(yaml_val /etc/kibana/kibana.yml server.port)"; [[ "$_v" == "$KIBANA_SERVER_PORT" ]] && pass "Kibana server.port 일치: $_v" || warn "Kibana server.port 불일치: 기대 $KIBANA_SERVER_PORT / 실제 ${_v:-없음}"
fi
_sw="$(sysctl -n vm.swappiness 2>/dev/null || echo '?')"
if istrue "$DISABLE_SWAP"; then
  [[ "$(swapon --noheadings 2>/dev/null | wc -l)" -eq 0 ]] && pass "Swap 비활성 정책 일치" || warn "DISABLE_SWAP=true 이지만 Swap이 활성 상태"
else
  [[ "$_sw" == "$SYSTEM_SWAPPINESS" ]] && pass "vm.swappiness 일치: $_sw" || warn "vm.swappiness 불일치: 기대 $SYSTEM_SWAPPINESS / 실제 $_sw"
  [[ "$(swapon --noheadings 2>/dev/null | wc -l)" -gt 0 ]] && pass "Swap 안전망 활성" || warn "DISABLE_SWAP=false 이지만 활성 Swap 없음"
fi
if istrue "$INSTALL_LOGSTASH"; then
  [[ -f "$LOGSTASH_PIPELINE_FILE" ]] && pass "Logstash pipeline 존재: $LOGSTASH_PIPELINE_FILE" || fail "Logstash pipeline 없음: $LOGSTASH_PIPELINE_FILE"
  _xms="$(grep -hE '^-Xms' /etc/logstash/jvm.options /etc/logstash/jvm.options.d/* 2>/dev/null | tail -1 | sed 's/^-Xms//' || true)"; _xmx="$(grep -hE '^-Xmx' /etc/logstash/jvm.options /etc/logstash/jvm.options.d/* 2>/dev/null | tail -1 | sed 's/^-Xmx//' || true)"
  [[ "$_xms" == "$LOGSTASH_HEAP_MIN" && "$_xmx" == "$LOGSTASH_HEAP_MAX" ]] && pass "Logstash Heap 일치: Xms=$_xms Xmx=$_xmx" || warn "Logstash Heap 불일치: 기대 $LOGSTASH_HEAP_MIN/$LOGSTASH_HEAP_MAX 실제 ${_xms:-?}/${_xmx:-?}"
fi
if istrue "$PROXYSG_FLOW_ENABLED"; then
  [[ -x "$PROXYSG_PROCESS_SCRIPT" ]] && pass "ProxySG 처리 스크립트 설치됨" || fail "ProxySG 처리 스크립트 없음: $PROXYSG_PROCESS_SCRIPT"
  _cf=/etc/cron.d/elk-proxysg-log-process; [[ -f "$_cf" ]] || _cf=/etc/cron.d/elk-guide-log-process
  if [[ -f "$_cf" ]]; then _cr="$(grep -vE '^[[:space:]]*(#|$|[A-Z_]+=)' "$_cf" | head -1 | awk '{print $1,$2,$3,$4,$5}')"; [[ "$_cr" == "$PROXYSG_PROCESS_CRON" ]] && pass "ProxySG cron 일치: $_cr" || warn "ProxySG cron 불일치: 기대 $PROXYSG_PROCESS_CRON / 실제 ${_cr:-없음}"; else fail "ProxySG cron 파일 없음"; fi
fi
if istrue "$ELK_REPORT_WEB_ENABLED"; then
  [[ -f /usr/local/lib/elk-auto/elk-report-web.py ]] && pass "점검 웹 도구 설치됨" || fail "점검 웹 도구 없음"
  systemctl is-active --quiet elk-report-web 2>/dev/null && pass "점검 웹 서비스 active (:${ELK_REPORT_WEB_PORT})" || fail "점검 웹 서비스 inactive"
fi

if istrue "$UFW_MANAGE"; then
  if command -v ufw >/dev/null 2>&1; then
    ufw_state="$(ufw status 2>/dev/null | head -1 || true)"
    [[ -n "$ufw_state" ]] && pass "UFW 상태 확인: $ufw_state" || warn "UFW 상태를 읽지 못함"
  else
    fail "UFW_MANAGE=true 이지만 ufw 명령이 없음"
  fi
fi

hr
printf ' 최종 결과: PASS=%d  WARN=%d  FAIL=%d\n' "$PASS" "$WARN" "$FAIL"
if (( FAIL == 0 )); then
  echo " [OK] 핵심 구성요소 전체 상태 점검 통과"
else
  echo " [ERROR] 실패 항목이 있습니다. /var/log/elk-auto-install.log 및 journalctl을 확인하십시오."
fi
hr
(( FAIL == 0 ))
