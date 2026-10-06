#!/usr/bin/env bash
# elk-patch.sh — 설치가 끝난 서버에서 "바꾼 값만" 적용하는 부분 패치 도구
#
#   sudo bash elk-patch.sh --set patch.env [--lib DIR] [--env /etc/elk-auto/elk.env] [--dry-run] [--yes]
#   sudo bash elk-patch.sh [옵션] KEY='값' [KEY='값' ...]
#   bash elk-patch.sh --list            # 패치할 수 있는 항목과 적용 방식
#
# 하는 일: ① 허용된 항목만 검사 → ② elk.env 백업 후 해당 값만 수정 → ③ 영향받는 부분만 적용
#   cron 시간 · ILM 보존기간 · Logstash pipeline · Index Template · Data View · 폴더 · TLS 인증서 갱신
# 인증서 패치는 서비스 재시작/CA 교체가 포함되므로 다른 패치 항목과 분리해서 실행합니다.
# 하지 않는 일: 패키지 설치, 계정/비밀번호 변경, 방화벽 변경
set -Eeuo pipefail
IFS=$'\n\t'

PATCH_VERSION="1"
ENV_FILE="${ELK_ENV_FILE:-/etc/elk-auto/elk.env}"
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRON_DIR="${ELK_CRON_DIR:-/etc/cron.d}"
BACKUP_ROOT="${ELK_PATCH_BACKUP_DIR:-/var/backups/elk-auto}"
LOGSTASH_BIN="${ELK_LOGSTASH_BIN:-/usr/share/logstash/bin/logstash}"
LOGSTASH_SETTINGS="${ELK_LOGSTASH_SETTINGS:-/etc/logstash}"
ES_CA_FILE="${ELK_ES_CA:-/etc/elasticsearch/certs/http_ca.crt}"

SET_FILE=""; DRY=0; YES=0; LIST=0
declare -a ARG_KV=()

_ts() { date '+%Y-%m-%d %H:%M:%S'; }
log()  { echo "[$(_ts)] [INFO] $*"; }
warn() { echo "[$(_ts)] [WARN] $*" >&2; }
die()  { echo "[$(_ts)] [ERROR] $*" >&2; exit 1; }
istrue() { [[ "${1,,}" =~ ^(1|true|yes|y|on)$ ]]; }

# ---------------------------------------------------------------- 패치 가능한 항목 -> 적용 동작
declare -A KEY_ACTIONS=(
  [PROXYSG_PROCESS_CRON]="cron"
  [ILM_DELETE_MIN_AGE]="ilm"
  [ILM_DELETE_ENABLED]="ilm"
  [PROXYSG_MAIN_LOG_FORMAT]="pipeline"   [PROXYSG_SSL_LOG_FORMAT]="pipeline"   [PROXYSG_CLOUD_LOG_FORMAT]="pipeline"
  [PROXYSG_CSV_FILTER_ENABLED]="pipeline" [PROXYSG_FILE_GLOB]="pipeline"
  [PROXYSG_LOGSTASH_DISCOVER_INTERVAL]="pipeline" [PROXYSG_LOGSTASH_MAX_OPEN_FILES]="pipeline"
  [INDEX_DATE_PATTERN]="pipeline"
  [PROXYSG_MAIN_SINCEDB]="pipeline" [PROXYSG_SSL_SINCEDB]="pipeline" [PROXYSG_CLOUD_SINCEDB]="pipeline"
  [PROXYSG_MAIN_PROCESS_DIR]="dirs pipeline" [PROXYSG_SSL_PROCESS_DIR]="dirs pipeline" [PROXYSG_CLOUD_PROCESS_DIR]="dirs pipeline"
  [PROXYSG_MAIN_SOURCE_DIR]="dirs" [PROXYSG_SSL_SOURCE_DIR]="dirs" [PROXYSG_CLOUD_SOURCE_DIR]="dirs"
  [PROXYSG_MAIN_BACKUP_DIR]="dirs" [PROXYSG_SSL_BACKUP_DIR]="dirs" [PROXYSG_CLOUD_BACKUP_DIR]="dirs"
  [PROXYSG_MAIN_INDEX_PREFIX]="pipeline index dataview" [PROXYSG_SSL_INDEX_PREFIX]="pipeline index dataview" [PROXYSG_CLOUD_INDEX_PREFIX]="pipeline index dataview"
  [PROXYSG_CLOUD_ENABLED]="dirs pipeline index dataview"
  [PROXYSG_MAIN_DATA_VIEW_NAME]="dataview" [PROXYSG_SSL_DATA_VIEW_NAME]="dataview" [PROXYSG_CLOUD_DATA_VIEW_NAME]="dataview"
  [ES_TLS_CA_VALIDITY_DAYS]="certs" [ES_TLS_CERT_VALIDITY_DAYS]="certs"
  [NGINX_TLS_SYNC_WITH_ES]="certs" [NGINX_TLS_DAYS]="certs" [NGINX_TLS_CN]="certs"
)
declare -A ACTION_TEXT=(
  [dirs]="로그 폴더 생성·권한 설정(없는 폴더만 새로 만듦)"
  [pipeline]="Logstash pipeline 다시 만들기 → 문법 검사 → Logstash 재시작 (검사 실패 시 자동 복구)"
  [cron]="cron 파일의 실행 시간만 교체"
  [ilm]="기존 ILM 정책의 삭제(보존기간) 단계만 수정"
  [index]="기존 Index Template의 인덱스 패턴만 수정"
  [dataview]="Kibana Data View 생성/갱신"
  [certs]="Elasticsearch CA/HTTP/Transport + Nginx Self-Signed 인증서 재발급 (서비스 재시작, 자동 백업/복구)"
)
ACTION_ORDER=(certs dirs pipeline cron ilm index dataview)

usage() { sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

list_keys() {
  echo "패치할 수 있는 항목:"
  local k; for k in $(printf '%s\n' "${!KEY_ACTIONS[@]}" | sort); do
    local a="" x acts; IFS=' ' read -ra acts <<<"${KEY_ACTIONS[$k]}"; for x in "${acts[@]}"; do a+="${ACTION_TEXT[$x]}; "; done
    printf '  %-36s %s\n' "$k" "${a%; }"
  done
}

# ---------------------------------------------------------------- 인자
while [[ $# -gt 0 ]]; do
  case "$1" in
    --set) SET_FILE="${2:-}"; shift 2 ;;
    --lib) LIB_DIR="${2:-}"; shift 2 ;;
    --env) ENV_FILE="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -y|--yes) YES=1; shift ;;
    --list) LIST=1; shift ;;
    -h|--help) usage; exit 0 ;;
    [A-Z]*=*) ARG_KV+=("$1"); shift ;;
    *) die "알 수 없는 옵션: $1  (--help 참고)" ;;
  esac
done
(( LIST )) && { list_keys; exit 0; }

# ---------------------------------------------------------------- 입력(KEY=VALUE)
declare -A NEWV=(); declare -a ORDER=()
add_kv() {
  local k="${1%%=*}" v="${1#*=}"
  [[ "$k" =~ ^[A-Z][A-Z0-9_]*$ ]] || die "항목 이름이 올바르지 않습니다: $k"
  if [[ "$v" == \'*\' && ${#v} -ge 2 ]]; then v="${v:1:${#v}-2}"; v="${v//\'\\\'\'/\'}"; fi
  [[ -n "${NEWV[$k]+x}" ]] || ORDER+=("$k")
  NEWV[$k]="$v"
}
if [[ -n "$SET_FILE" ]]; then
  [[ -f "$SET_FILE" ]] || die "패치 파일을 찾을 수 없습니다: $SET_FILE"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "${line//[[:space:]]/}" || "$line" =~ ^[[:space:]]*# ]] && continue
    add_kv "$line"
  done <"$SET_FILE"
fi
for kv in "${ARG_KV[@]}"; do add_kv "$kv"; done
(( ${#ORDER[@]} )) || { usage; die "바꿀 값이 없습니다. (--set 파일 또는 KEY='값' 인자를 지정하세요)"; }

[[ ${EUID:-$(id -u)} -eq 0 || $DRY -eq 1 ]] || die "root 권한이 필요합니다. sudo 로 실행하세요."
[[ -f "$ENV_FILE" ]] || die "설치된 elk.env를 찾을 수 없습니다: $ENV_FILE (설치가 끝난 서버에서 실행하세요)"
command -v jq >/dev/null 2>&1 || die "jq 가 필요합니다. (설치 시 함께 설치됩니다)"

# ---------------------------------------------------------------- 현재 설정 읽기
# shellcheck disable=SC1090
source "$ENV_FILE"
if grep -qE '^GUIDE_[A-Z0-9_]+=' "$ENV_FILE" 2>/dev/null && ! grep -qE '^PROXYSG_[A-Z0-9_]+=' "$ENV_FILE" 2>/dev/null; then
  die "이전 이름(GUIDE_*)으로 설치된 서버입니다. 먼저 새 설치 파일로 한 번 재설치한 뒤 패치하세요."
fi
: "${PROXYSG_FLOW_ENABLED:=false}"; : "${PROXYSG_CLOUD_ENABLED:=false}"
: "${PROXYSG_MAIN_SOURCE_DIR:=/home/main}"; : "${PROXYSG_SSL_SOURCE_DIR:=/home/ssl}"; : "${PROXYSG_CLOUD_SOURCE_DIR:=/home/cloud}"
: "${PROXYSG_MAIN_BACKUP_DIR:=/home/main_backup}"; : "${PROXYSG_SSL_BACKUP_DIR:=/home/ssl_backup}"; : "${PROXYSG_CLOUD_BACKUP_DIR:=/home/cloud_backup}"
: "${PROXYSG_MAIN_PROCESS_DIR:=/home/main_process}"; : "${PROXYSG_SSL_PROCESS_DIR:=/home/ssl_process}"; : "${PROXYSG_CLOUD_PROCESS_DIR:=/home/cloud_process}"
: "${PROXYSG_FILE_GLOB:=*.log.gz}"; : "${PROXYSG_DIR_MODE:=0775}"
: "${PROXYSG_PROCESS_SCRIPT:=/usr/local/sbin/elk-proxysg-log-process}"; : "${PROXYSG_PROCESS_LOG:=/var/log/elk-proxysg-log-process.log}"; : "${PROXYSG_PROCESS_CRON:=0 3 * * *}"
: "${PROXYSG_MAIN_SINCEDB:=/var/lib/logstash/sincedb-main}"; : "${PROXYSG_SSL_SINCEDB:=/var/lib/logstash/sincedb-ssl}"; : "${PROXYSG_CLOUD_SINCEDB:=/var/lib/logstash/sincedb-cloud}"
: "${PROXYSG_LOGSTASH_DISCOVER_INTERVAL:=5}"; : "${PROXYSG_LOGSTASH_MAX_OPEN_FILES:=1000}"; : "${PROXYSG_CSV_FILTER_ENABLED:=true}"
: "${PROXYSG_MAIN_LOG_FORMAT:=}"; : "${PROXYSG_SSL_LOG_FORMAT:=}"; : "${PROXYSG_CLOUD_LOG_FORMAT:=}"
: "${PROXYSG_MAIN_INDEX_PREFIX:=proxy-main}"; : "${PROXYSG_SSL_INDEX_PREFIX:=proxy-ssl}"; : "${PROXYSG_CLOUD_INDEX_PREFIX:=proxy-cloud}"
: "${PROXYSG_MAIN_DATA_VIEW_NAME:=main}"; : "${PROXYSG_SSL_DATA_VIEW_NAME:=ssl}"; : "${PROXYSG_CLOUD_DATA_VIEW_NAME:=cloud}"
: "${PROXYSG_ILM_POLICY_NAME:=proxy-retention-policy}"; : "${PROXYSG_INDEX_TEMPLATE_NAME:=proxy-index-template}"
: "${INDEX_PREFIX:=network-log}"; : "${INDEX_DATE_PATTERN:=YYYY.MM.dd}"; : "${INDEX_TEMPLATE_NAME:=${INDEX_PREFIX}-template}"; : "${ILM_POLICY_NAME:=${INDEX_PREFIX}-ilm}"
: "${ILM_DELETE_ENABLED:=true}"; : "${ILM_DELETE_MIN_AGE:=90d}"
: "${ES_SECURITY_ENABLED:=true}"; : "${ES_HTTP_TLS_ENABLED:=true}"; : "${ES_TRANSPORT_TLS_ENABLED:=true}"; : "${ES_HTTP_PORT:=9200}"; : "${ELASTIC_USERNAME:=elastic}"
: "${ES_TLS_CA_VALIDITY_DAYS:=7300}"; : "${ES_TLS_CERT_VALIDITY_DAYS:=7300}"; : "${ES_DISCOVERY_MODE:=single-node}"
: "${INSTALL_NGINX:=false}"; : "${NGINX_TLS_MODE:=selfsigned}"; : "${NGINX_TLS_SYNC_WITH_ES:=true}"; : "${NGINX_TLS_DAYS:=7300}"; : "${NGINX_TLS_CN:=}"
: "${KIBANA_SERVER_PORT:=5601}"; : "${KIBANA_CREATE_DATA_VIEW:=true}"; : "${KIBANA_DATA_VIEW_TIME_FIELD:=@timestamp}"; : "${KIBANA_DATA_VIEW_ALLOW_NO_INDEX:=true}"
: "${LOGSTASH_PROFILE:=generic}"; : "${LOGSTASH_PIPELINE_FILE:=/etc/logstash/conf.d/10-main.conf}"; : "${LOGSTASH_ES_HOST:=}"
: "${FTP_USER:=elkftp}"; : "${FTP_GROUP:=logstash}"; : "${INSTALL_LOGSTASH:=true}"
: "${STATE_DIR:=/root/.elk-auto-installer}"; : "${SECRETS_FILE:=${STATE_DIR}/secrets.env}"
[[ "$LOGSTASH_PROFILE" == "proxysg_guide" ]] && LOGSTASH_PROFILE="proxysg"

# ---------------------------------------------------------------- 값 검사
check_value() {
  local k="$1" v="$2"
  case "$k" in
    PROXYSG_PROCESS_CRON) [[ "$v" =~ ^[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+$ ]] && [[ "$v" =~ ^[0-9*/,[:space:]-]+$ ]] || echo "cron은 5개 필드여야 합니다. 예: 0 3 * * *  (매분: * * * * *)" ;;
    ILM_DELETE_MIN_AGE) [[ "$v" =~ ^[0-9]+(ms|s|m|h|d|w)$ ]] || echo "보존기간 형식이 올바르지 않습니다. 예: 90d" ;;
    ILM_DELETE_ENABLED|PROXYSG_CSV_FILTER_ENABLED|PROXYSG_CLOUD_ENABLED|NGINX_TLS_SYNC_WITH_ES) [[ "${v,,}" =~ ^(true|false)$ ]] || echo "true 또는 false 여야 합니다." ;;
    PROXYSG_*_LOG_FORMAT) [[ -n "${v//[[:space:]]/}" ]] || { echo "비어 있을 수 없습니다."; return; }; [[ "$v" =~ ^[A-Za-z0-9_.:()[:space:]-]+$ ]] || echo "허용되지 않는 문자가 있습니다. (영문/숫자, - _ . : ( ) 와 공백만)" ;;
    PROXYSG_*_INDEX_PREFIX) [[ "$v" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || echo "소문자·숫자·-·_·. 만 쓰고 영문/숫자로 시작해야 합니다. 예: proxy-main" ;;
    PROXYSG_*_DATA_VIEW_NAME) [[ -n "${v//[[:space:]]/}" ]] || echo "비어 있을 수 없습니다." ;;
    PROXYSG_*_DIR|PROXYSG_*_SINCEDB) [[ "$v" == /* && "$v" != *[[:space:]]* ]] || echo "공백 없는 절대경로여야 합니다." ;;
    PROXYSG_FILE_GLOB) [[ "$v" =~ ^[A-Za-z0-9_.*?-]+$ ]] || echo "파일 패턴에 허용되지 않는 문자가 있습니다. 예: *.log.gz" ;;
    PROXYSG_LOGSTASH_DISCOVER_INTERVAL|PROXYSG_LOGSTASH_MAX_OPEN_FILES) [[ "$v" =~ ^[0-9]+$ && "$v" -ge 1 ]] || echo "1 이상의 숫자여야 합니다." ;;
    INDEX_DATE_PATTERN) [[ "$v" =~ ^[A-Za-z.\-_]+$ ]] || echo "날짜 형식이 올바르지 않습니다. 예: YYYY.MM.dd" ;;
    ES_TLS_CA_VALIDITY_DAYS|ES_TLS_CERT_VALIDITY_DAYS|NGINX_TLS_DAYS) [[ "$v" =~ ^[0-9]+$ && "$v" -ge 1 && "$v" -le 36500 ]] || echo "1~36500 사이 정수(일)여야 합니다." ;;
    NGINX_TLS_CN) [[ "$v" != *[[:space:]]* ]] || echo "CN/SAN에는 공백을 사용할 수 없습니다." ;;
  esac
}
declare -A ACTIONS=()
bad=0
for k in "${ORDER[@]}"; do
  if [[ -z "${KEY_ACTIONS[$k]+x}" ]]; then
    echo "[거절] $k : 부분 패치를 지원하지 않는 항목입니다. (포트·계정·Heap 등은 별도 작업이 필요합니다)" >&2; bad=1; continue
  fi
  msg="$(check_value "$k" "${NEWV[$k]}")"
  if [[ -n "$msg" ]]; then echo "[거절] $k : $msg" >&2; bad=1; continue; fi
  IFS=' ' read -ra _acts <<<"${KEY_ACTIONS[$k]}"; for a in "${_acts[@]}"; do ACTIONS[$a]=1; done
done
(( bad )) && die "잘못된 항목이 있어 아무것도 바꾸지 않았습니다."
# 인증서 기간의 상호 관계도 새 값 기준으로 검사한다.
_ca_days="${NEWV[ES_TLS_CA_VALIDITY_DAYS]:-${ES_TLS_CA_VALIDITY_DAYS}}"
_cert_days="${NEWV[ES_TLS_CERT_VALIDITY_DAYS]:-${ES_TLS_CERT_VALIDITY_DAYS}}"
[[ "$_ca_days" =~ ^[0-9]+$ && "$_cert_days" =~ ^[0-9]+$ ]] || die "인증서 유효기간 값이 올바르지 않습니다."
(( _cert_days <= _ca_days )) || die "Elasticsearch 서버 인증서 기간($_cert_days)은 CA 기간($_ca_days)보다 길 수 없습니다."
if [[ -n "${ACTIONS[certs]+x}" && ${#ACTIONS[@]} -gt 1 ]]; then
  die "인증서 갱신 패치는 서비스 재시작/CA 교체가 포함되므로 다른 패치 항목과 분리해서 단독으로 생성·실행하세요."
fi

# ---------------------------------------------------------------- 변경 내용 표시
cur() { local n="$1"; printf '%s' "${!n-}"; }
echo "=== 적용 예정 변경 ($ENV_FILE) ==="
changed=0
for k in "${ORDER[@]}"; do
  o="$(cur "$k")"; n="${NEWV[$k]}"
  if [[ "$o" == "$n" ]]; then printf '  = %-34s 변경 없음 (%s)\n' "$k" "${n:0:60}"; else changed=1; printf '  ~ %-34s %s  →  %s\n' "$k" "${o:0:60}" "${n:0:60}"; fi
done
(( changed )) || { echo "바뀐 값이 없어 아무것도 하지 않습니다."; exit 0; }
echo "=== 적용할 작업 ==="
for a in "${ACTION_ORDER[@]}"; do [[ -n "${ACTIONS[$a]+x}" ]] && echo "  - ${ACTION_TEXT[$a]}"; done
(( DRY )) && { echo "(--dry-run: 여기까지만 보여 주고 종료합니다)"; exit 0; }
if (( ! YES )); then
  if [[ -t 0 ]]; then read -r -p "적용할까요? [y/N] " ans; [[ "${ans,,}" == y* ]] || die "취소했습니다."; else die "대화형 입력이 없습니다. --yes 를 붙여 실행하세요."; fi
fi

# ---------------------------------------------------------------- 백업 + env 수정
TS="$(date +%Y%m%d-%H%M%S)"; BK="$BACKUP_ROOT/patch-$TS"; mkdir -p "$BK"; chmod 700 "$BK"
cp -p "$ENV_FILE" "$BK/elk.env"
[[ -f "$LOGSTASH_PIPELINE_FILE" ]] && cp -p "$LOGSTASH_PIPELINE_FILE" "$BK/pipeline.conf.bak"
log "백업: $BK"
set_env_value() {
  local key="$1" val="$2" esc line tmp
  esc="${val//\'/\'\\\'\'}"; line="${key}='${esc}'"
  tmp="$(mktemp)"
  NEWLINE="$line" awk -v k="$key" 'BEGIN{line=ENVIRON["NEWLINE"];done=0} $0 ~ ("^" k "=") {if(!done){print line;done=1};next} {print} END{if(!done)print line}' "$ENV_FILE" >"$tmp"
  cat "$tmp" >"$ENV_FILE"; rm -f "$tmp"
}
restore_env() { cp -p "$BK/elk.env" "$ENV_FILE"; }
for k in "${ORDER[@]}"; do set_env_value "$k" "${NEWV[$k]}"; printf -v "$k" '%s' "${NEWV[$k]}"; done
chmod 600 "$ENV_FILE"
log "elk.env 수정 완료: ${ORDER[*]}"

# ---------------------------------------------------------------- ES / Kibana 접속
ES_LOCAL_URL=""
load_saved_secret() { local key="$1" line val; [[ -f "$SECRETS_FILE" ]] || return 1; line="$(grep -E "^${key}=" "$SECRETS_FILE" | tail -n1 || true)"; [[ -n "$line" ]] || return 1; val="${line#*=}"; eval "printf '%s' ${val}"; }
prepare_es() {
  [[ -n "$ES_LOCAL_URL" ]] && return 0
  local pw="" port code
  pw="$(load_saved_secret ELASTIC_PASSWORD 2>/dev/null || true)"; [[ -n "$pw" ]] || pw="${ELASTIC_PASSWORD:-}"
  ELASTIC_PASSWORD="$pw"
  for port in "$ES_HTTP_PORT" 9200; do
    local a=(-sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 3 "https://127.0.0.1:${port}"); [[ -f "$ES_CA_FILE" ]] && a+=(--cacert "$ES_CA_FILE")
    code="$(curl "${a[@]}" 2>/dev/null || true)"; if [[ "$code" =~ ^(200|401|403)$ ]]; then ES_LOCAL_URL="https://127.0.0.1:${port}"; return 0; fi
    code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 3 "http://127.0.0.1:${port}" 2>/dev/null || true)"; if [[ "$code" =~ ^(200|401|403)$ ]]; then ES_LOCAL_URL="http://127.0.0.1:${port}"; return 0; fi
  done
  return 1
}
es_curl() {
  local method="$1" path="$2" body="${3:-}" a
  a=(-sS -X "$method" "${ES_LOCAL_URL}${path}" -H 'Content-Type: application/json')
  istrue "$ES_SECURITY_ENABLED" && a+=(-u "${ELASTIC_USERNAME}:${ELASTIC_PASSWORD}")
  [[ "$ES_LOCAL_URL" == https://* && -f "$ES_CA_FILE" ]] && a+=(--cacert "$ES_CA_FILE")
  [[ -n "$body" ]] && a+=(-d "$body")
  curl "${a[@]}"
}
OK_LIST=(); FAIL_LIST=()
ok_()   { OK_LIST+=("$1"); log "완료: $1"; }
fail_() { FAIL_LIST+=("$1"); warn "실패: $1"; }

# ---------------------------------------------------------------- 동작들
act_certs() {
  local tool="$LIB_DIR/elk-cert-renew.sh"
  [[ -f "$tool" ]] || { fail_ "인증서 갱신 도구 없음: $tool"; return 0; }
  log "인증서 갱신 실행 (CA 교체 시 Kibana/Logstash trust도 함께 갱신)"
  if bash "$tool" --env "$ENV_FILE" --all --yes; then
    ok_ "TLS 인증서 갱신"
  else
    restore_env
    fail_ "TLS 인증서 갱신 실패 (elk.env는 이전 값으로 복구)"
    return 0
  fi
}
act_dirs() {
  istrue "$PROXYSG_FLOW_ENABLED" || { log "로그 처리 스크립트가 꺼져 있어 폴더 작업은 건너뜁니다."; return 0; }
  local src=("$PROXYSG_MAIN_SOURCE_DIR" "$PROXYSG_SSL_SOURCE_DIR") bak=("$PROXYSG_MAIN_BACKUP_DIR" "$PROXYSG_SSL_BACKUP_DIR") prc=("$PROXYSG_MAIN_PROCESS_DIR" "$PROXYSG_SSL_PROCESS_DIR") d
  if istrue "$PROXYSG_CLOUD_ENABLED"; then src+=("$PROXYSG_CLOUD_SOURCE_DIR"); bak+=("$PROXYSG_CLOUD_BACKUP_DIR"); prc+=("$PROXYSG_CLOUD_PROCESS_DIR"); fi
  for d in "${src[@]}" "${bak[@]}" "${prc[@]}"; do
    if [[ ! -d "$d" ]]; then mkdir -p "$d"; log "폴더 생성: $d"; fi
  done
  for d in "${src[@]}" "${bak[@]}"; do [[ -d "$d" ]] && { chown "$FTP_USER:$FTP_GROUP" "$d" 2>/dev/null || warn "chown 실패(건너뜀): $d"; chmod "$PROXYSG_DIR_MODE" "$d" 2>/dev/null || true; }; done
  for d in "${prc[@]}"; do [[ -d "$d" ]] && { chown logstash:logstash "$d" 2>/dev/null || warn "chown 실패(건너뜀): $d"; chmod "$PROXYSG_DIR_MODE" "$d" 2>/dev/null || true; }; done
  ok_ "로그 폴더 확인/생성"
}
act_pipeline() {
  istrue "$INSTALL_LOGSTASH" || { log "Logstash를 설치하지 않은 서버라 pipeline 작업은 건너뜁니다."; return 0; }
  local custom="$LIB_DIR/custom-pipeline.conf"
  if [[ -s "$custom" ]]; then
    log "사용자 지정 pipeline(custom-pipeline.conf)을 그대로 사용합니다."; cp -f "$custom" "$LOGSTASH_PIPELINE_FILE"
  elif [[ "$LOGSTASH_PROFILE" == "proxysg" ]]; then
    [[ -f "$LIB_DIR/proxysg-lib.sh" ]] || die "proxysg-lib.sh 를 찾을 수 없습니다: $LIB_DIR"
    # shellcheck disable=SC1091
    source "$LIB_DIR/proxysg-lib.sh"
    if [[ -z "$LOGSTASH_ES_HOST" ]]; then
      prepare_es || true; LOGSTASH_ES_HOST="${ES_LOCAL_URL:-https://127.0.0.1:${ES_HTTP_PORT}}"
    fi
    if istrue "$PROXYSG_CSV_FILTER_ENABLED"; then
      [[ -f "$LIB_DIR/proxysg-log-filter.conf" ]] || die "필터 템플릿을 찾을 수 없습니다: $LIB_DIR/proxysg-log-filter.conf"
      local _f _v
      for _f in PROXYSG_MAIN_LOG_FORMAT PROXYSG_SSL_LOG_FORMAT; do _v="${!_f}"; [[ -n "${_v//[[:space:]]/}" ]] || die "$_f 가 비어 있습니다."; done
      istrue "$PROXYSG_CLOUD_ENABLED" && { [[ -n "${PROXYSG_CLOUD_LOG_FORMAT//[[:space:]]/}" ]] || die "PROXYSG_CLOUD_LOG_FORMAT 가 비어 있습니다."; }
    fi
    proxysg_generate_pipeline "$LIB_DIR/proxysg-log-filter.conf" "$LOGSTASH_PIPELINE_FILE"
  else
    die "Logstash 프로필이 proxysg가 아니라 pipeline을 자동으로 다시 만들 수 없습니다. (현재: $LOGSTASH_PROFILE)"
  fi
  chown root:logstash "$LOGSTASH_PIPELINE_FILE" 2>/dev/null || warn "pipeline 파일 소유자 변경 실패(건너뜀)"; chmod 640 "$LOGSTASH_PIPELINE_FILE"
  log "Logstash 설정 문법 검사"
  if ! runuser -u logstash -- "$LOGSTASH_BIN" --path.settings "$LOGSTASH_SETTINGS" -t; then
    warn "Logstash 설정 검사에 실패했습니다. 이전 상태로 되돌립니다."
    if [[ -f "$BK/pipeline.conf.bak" ]]; then cp -p "$BK/pipeline.conf.bak" "$LOGSTASH_PIPELINE_FILE"; else rm -f "$LOGSTASH_PIPELINE_FILE"; fi
    restore_env; die "pipeline 패치 실패 → pipeline 과 elk.env 를 원래대로 복구했습니다. (백업: $BK)"
  fi
  if systemctl is-enabled logstash >/dev/null 2>&1 || systemctl is-active logstash >/dev/null 2>&1; then
    systemctl restart logstash && log "Logstash 재시작" || { fail_ "Logstash 재시작"; return 0; }
  fi
  ok_ "Logstash pipeline 갱신"
}
act_cron() {
  istrue "$PROXYSG_FLOW_ENABLED" || { log "로그 처리 스크립트가 꺼져 있어 cron 작업은 건너뜁니다."; return 0; }
  local f="$CRON_DIR/elk-proxysg-log-process"
  [[ -e "$f" ]] || warn "기존 cron 파일이 없어 새로 만듭니다: $f"
  mkdir -p "$CRON_DIR"
  cat >"$f.new" <<EOF_PATCH_CRON
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
${PROXYSG_PROCESS_CRON} root ${PROXYSG_PROCESS_SCRIPT} /etc/elk-auto/elk.env >> ${PROXYSG_PROCESS_LOG} 2>&1
EOF_PATCH_CRON
  chmod 644 "$f.new"; mv -f "$f.new" "$f"
  ok_ "cron 실행 시간: $PROXYSG_PROCESS_CRON"
}
act_ilm() {
  prepare_es || { fail_ "ILM 정책 수정 (Elasticsearch에 접속할 수 없음)"; return 0; }
  local name policy new resp
  if istrue "$PROXYSG_FLOW_ENABLED"; then name="$PROXYSG_ILM_POLICY_NAME"; else name="$ILM_POLICY_NAME"; fi
  resp="$(es_curl GET "/_ilm/policy/${name}" || true)"
  policy="$(printf '%s' "$resp" | jq -c --arg n "$name" '.[$n].policy // empty' 2>/dev/null || true)"
  [[ -n "$policy" ]] || { fail_ "ILM 정책 수정 (정책 '$name' 을 찾을 수 없음: ${resp:0:120})"; return 0; }
  if istrue "$ILM_DELETE_ENABLED"; then new="$(printf '%s' "$policy" | jq -c --arg age "$ILM_DELETE_MIN_AGE" '.phases.delete={min_age:$age,actions:{delete:{}}}')"
  else new="$(printf '%s' "$policy" | jq -c 'del(.phases.delete)')"; fi
  resp="$(es_curl PUT "/_ilm/policy/${name}" "$(jq -nc --argjson p "$new" '{policy:$p}')" || true)"
  [[ "$(printf '%s' "$resp" | jq -r '.acknowledged // false' 2>/dev/null)" == "true" ]] && ok_ "ILM 정책 '$name' 삭제 단계: $(istrue "$ILM_DELETE_ENABLED" && echo "$ILM_DELETE_MIN_AGE 후 삭제" || echo "자동 삭제 안 함")" || fail_ "ILM 정책 수정 (${resp:0:120})"
}
act_index() {
  istrue "$PROXYSG_FLOW_ENABLED" || { log "로그 처리 스크립트가 꺼져 있어 Index Template 작업은 건너뜁니다."; return 0; }
  prepare_es || { fail_ "Index Template 수정 (Elasticsearch에 접속할 수 없음)"; return 0; }
  local name="$PROXYSG_INDEX_TEMPLATE_NAME" resp tpl pats new
  pats="${PROXYSG_MAIN_INDEX_PREFIX}-*,${PROXYSG_SSL_INDEX_PREFIX}-*"; istrue "$PROXYSG_CLOUD_ENABLED" && pats+=",${PROXYSG_CLOUD_INDEX_PREFIX}-*"
  resp="$(es_curl GET "/_index_template/${name}" || true)"
  tpl="$(printf '%s' "$resp" | jq -c '.index_templates[0].index_template // empty' 2>/dev/null || true)"
  [[ -n "$tpl" ]] || { fail_ "Index Template 수정 (템플릿 '$name' 을 찾을 수 없음: ${resp:0:120})"; return 0; }
  new="$(printf '%s' "$tpl" | jq -c --argjson p "$(printf '%s' "$pats" | jq -R 'split(",")')" '.index_patterns=$p')"
  resp="$(es_curl PUT "/_index_template/${name}" "$new" || true)"
  [[ "$(printf '%s' "$resp" | jq -r '.acknowledged // false' 2>/dev/null)" == "true" ]] && ok_ "Index Template '$name' 패턴: $pats" || fail_ "Index Template 수정 (${resp:0:120})"
}
act_dataview() {
  istrue "$PROXYSG_FLOW_ENABLED" || { log "로그 처리 스크립트가 꺼져 있어 Data View 작업은 건너뜁니다."; return 0; }
  if ! { istrue "$KIBANA_CREATE_DATA_VIEW" && istrue "$ES_SECURITY_ENABLED"; }; then log "Data View 자동 생성이 꺼져 있어(또는 보안 꺼짐) 건너뜁니다."; return 0; fi
  prepare_es || true
  local url="${KIBANA_LOCAL_URL:-http://127.0.0.1:${KIBANA_SERVER_PORT}}" pairs=() p n t body out code allow=false any=0
  istrue "$KIBANA_DATA_VIEW_ALLOW_NO_INDEX" && allow=true
  pairs+=("${PROXYSG_MAIN_DATA_VIEW_NAME}|${PROXYSG_MAIN_INDEX_PREFIX}-*" "${PROXYSG_SSL_DATA_VIEW_NAME}|${PROXYSG_SSL_INDEX_PREFIX}-*")
  istrue "$PROXYSG_CLOUD_ENABLED" && pairs+=("${PROXYSG_CLOUD_DATA_VIEW_NAME}|${PROXYSG_CLOUD_INDEX_PREFIX}-*")
  for p in "${pairs[@]}"; do
    n="${p%%|*}"; t="${p#*|}"
    body="$(jq -nc --arg title "$t" --arg name "$n" --arg tf "$KIBANA_DATA_VIEW_TIME_FIELD" --argjson allow "$allow" '{data_view:{title:$title,name:$name,timeFieldName:$tf,allowNoIndex:$allow},override:true}')"
    out="$(curl -sS -w '\n%{http_code}' -u "${ELASTIC_USERNAME}:${ELASTIC_PASSWORD:-}" -H 'kbn-xsrf: true' -H 'Content-Type: application/json' -X POST "$url/api/data_views/data_view" -d "$body" || true)"
    code="$(printf '%s' "$out" | tail -n1)"
    if [[ "$code" == "200" ]]; then ok_ "Data View '$n' → $t"; any=1; else fail_ "Data View '$n' 생성 (HTTP=$code)"; fi
  done
}

for a in "${ACTION_ORDER[@]}"; do
  [[ -n "${ACTIONS[$a]+x}" ]] || continue
  "act_$a"
done

echo
echo "=== 패치 결과 ==="
for x in "${OK_LIST[@]}"; do echo "  ✔ $x"; done
for x in "${FAIL_LIST[@]}"; do echo "  ✖ $x"; done
echo "  백업 위치: $BK  (되돌리기: cp -p $BK/elk.env $ENV_FILE)"
(( ${#FAIL_LIST[@]} )) && exit 1
exit 0
