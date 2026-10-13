#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ENV_FILE="${1:-/etc/elk-auto/elk.env}"
[[ -f "$ENV_FILE" ]] || { echo "[ERROR] env file not found: $ENV_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"

: "${PROXYSG_MAIN_SOURCE_DIR:=/home/main}"
: "${PROXYSG_SSL_SOURCE_DIR:=/home/ssl}"
: "${PROXYSG_CLOUD_ENABLED:=false}"
: "${PROXYSG_CLOUD_API_ENABLED:=true}"
: "${PROXYSG_CLOUD_API_USERNAME:=}"
: "${PROXYSG_CLOUD_API_PASSWORD:=}"
: "${PROXYSG_CLOUD_API_URL:=https://portal.threatpulse.com:443/reportpod/logs/sync}"
: "${PROXYSG_CLOUD_API_LOOKBACK_DAYS:=1}"
: "${PROXYSG_CLOUD_API_INSECURE:=true}"
: "${PROXYSG_CLOUD_SOURCE_DIR:=/home/cloud}"
: "${PROXYSG_CLOUD_BACKUP_DIR:=/home/cloud_backup}"
: "${PROXYSG_CLOUD_PROCESS_DIR:=/home/cloud_process}"
: "${PROXYSG_MAIN_BACKUP_DIR:=/home/main_backup}"
: "${PROXYSG_SSL_BACKUP_DIR:=/home/ssl_backup}"
: "${PROXYSG_MAIN_PROCESS_DIR:=/home/main_process}"
: "${PROXYSG_SSL_PROCESS_DIR:=/home/ssl_process}"
: "${PROXYSG_FILE_GLOB:=*.log.gz}"
: "${PROXYSG_DIR_MODE:=0775}"
: "${PROXYSG_PROCESS_LOG:=/var/log/elk-proxysg-log-process.log}"
: "${FTP_USER:=elkftp}"
: "${FTP_GROUP:=elkftp}"

LOCK_FILE="/run/lock/elk-proxysg-log-process.lock"
mkdir -p "$(dirname "$LOCK_FILE")" "$(dirname "$PROXYSG_PROCESS_LOG")"
exec 200>"$LOCK_FILE"
flock -n 200 || exit 0

ts(){ date '+%Y-%m-%d %H:%M:%S'; }
log(){ printf '[%s] %s\n' "$(ts)" "$*"; }
mask_id(){
  local v="${1:-}" n
  [[ -n "$v" ]] || { printf '(empty)'; return; }
  n=${#v}
  if (( n > 12 )); then
    printf '%s…%s' "${v:0:8}" "${v:n-4:4}"
  else
    printf '(set)'
  fi
}

CLOUD_ON=false
[[ "${PROXYSG_CLOUD_ENABLED,,}" == "true" ]] && CLOUD_ON=true
if [[ "$CLOUD_ON" == true ]]; then
  log "CLOUD CONFIG: env=$ENV_FILE api_enabled=${PROXYSG_CLOUD_API_ENABLED} api_id=$(mask_id "$PROXYSG_CLOUD_API_USERNAME") api_password=$([[ -n "$PROXYSG_CLOUD_API_PASSWORD" ]] && echo set || echo empty) lookback_days=${PROXYSG_CLOUD_API_LOOKBACK_DAYS} url=${PROXYSG_CLOUD_API_URL} insecure=${PROXYSG_CLOUD_API_INSECURE}"
fi
ALL_DIRS=("$PROXYSG_MAIN_SOURCE_DIR" "$PROXYSG_SSL_SOURCE_DIR"
  "$PROXYSG_MAIN_BACKUP_DIR" "$PROXYSG_SSL_BACKUP_DIR"
  "$PROXYSG_MAIN_PROCESS_DIR" "$PROXYSG_SSL_PROCESS_DIR")
if [[ "$CLOUD_ON" == true ]]; then
  ALL_DIRS+=("$PROXYSG_CLOUD_SOURCE_DIR" "$PROXYSG_CLOUD_BACKUP_DIR" "$PROXYSG_CLOUD_PROCESS_DIR")
fi
mkdir -p "${ALL_DIRS[@]}"
chmod "$PROXYSG_DIR_MODE" "${ALL_DIRS[@]}" || true


cloud_api_download() {
  [[ "$CLOUD_ON" == true ]] || return 0
  [[ "${PROXYSG_CLOUD_API_ENABLED,,}" == "true" ]] || {
    log "CLOUD API: disabled; existing source files only"
    return 0
  }

  if [[ -z "$PROXYSG_CLOUD_API_USERNAME" || -z "$PROXYSG_CLOUD_API_PASSWORD" ]]; then
    log "CLOUD API ERROR: API ID/Password is empty; download skipped"
    return 1
  fi
  [[ "$PROXYSG_CLOUD_API_LOOKBACK_DAYS" =~ ^[0-9]+$ ]] || {
    log "CLOUD API ERROR: LOOKBACK_DAYS must be integer: $PROXYSG_CLOUD_API_LOOKBACK_DAYS"
    return 1
  }

  command -v curl >/dev/null 2>&1 || { log "CLOUD API ERROR: curl not found"; return 1; }
  command -v unzip >/dev/null 2>&1 || { log "CLOUD API ERROR: unzip not found"; return 1; }
  command -v python3 >/dev/null 2>&1 || { log "CLOUD API ERROR: python3 not found"; return 1; }

  local start_ms end_date token tmpdir zipfile url http_code
  local extracted=0 moved=0 duplicate=0 bad=0 f base dest stem ext n
  start_ms="$(python3 - "$PROXYSG_CLOUD_API_LOOKBACK_DAYS" <<'PY'
import datetime, sys
days=int(sys.argv[1])
print(int((datetime.datetime.now() - datetime.timedelta(days=days)).timestamp()*1000))
PY
)"
  end_date=0
  token=none
  url="${PROXYSG_CLOUD_API_URL}?startDate=${start_ms}&endDate=${end_date}&token=${token}"

  tmpdir="$(mktemp -d "${PROXYSG_CLOUD_SOURCE_DIR%/}/.cloud-api.XXXXXX")" || {
    log "CLOUD API ERROR: temp directory create failed"
    return 1
  }
  zipfile="$tmpdir/cloud-log.zip"

  local -a curl_opts=(--silent --show-error --location
    --connect-timeout 15 --max-time 600
    -H "X-APIUsername: ${PROXYSG_CLOUD_API_USERNAME}"
    -H "X-APIPassword: ${PROXYSG_CLOUD_API_PASSWORD}"
    -o "$zipfile" -w "%{http_code}")
  [[ "${PROXYSG_CLOUD_API_INSECURE,,}" == "true" ]] && curl_opts+=(--insecure)

  log "CLOUD API: downloading logs (${PROXYSG_CLOUD_API_LOOKBACK_DAYS} day lookback, startDate=${start_ms})"
  if ! http_code="$(curl "${curl_opts[@]}" "$url")"; then
    log "CLOUD API ERROR: curl transport failure"
    rm -rf "$tmpdir"
    return 1
  fi

  if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    local api_body=""
    if [[ -s "$zipfile" ]]; then
      api_body="$(tr '\r\n\t' '   ' <"$zipfile" | head -c 500)"
    fi
    log "CLOUD API ERROR: HTTP=$http_code response=${api_body:-'(empty body)'}"
    rm -rf "$tmpdir"
    return 1
  fi
  if [[ ! -s "$zipfile" ]]; then
    log "CLOUD API ERROR: HTTP=$http_code but response body is empty"
    rm -rf "$tmpdir"
    return 1
  fi

  if ! unzip -tq "$zipfile" >/dev/null 2>&1; then
    log "CLOUD API ERROR: downloaded file is not a valid ZIP"
    rm -rf "$tmpdir"
    return 1
  fi

  mkdir -p "$tmpdir/extracted"
  if ! unzip -oq "$zipfile" -d "$tmpdir/extracted"; then
    log "CLOUD API ERROR: ZIP extraction failed"
    rm -rf "$tmpdir"
    return 1
  fi

  # API ZIP 내부의 .log.gz만 기존 Cloud 수신 폴더로 넣는다.
  # .gz 압축은 유지한다. 기존 Logstash file input은 *.log.gz를 읽고,
  # 원본 백업도 .gz 상태로 보존하도록 통합되어 있다.
  while IFS= read -r -d '' f; do
    extracted=$((extracted+1))
    base="$(basename "$f")"
    dest="$PROXYSG_CLOUD_SOURCE_DIR/$base"

    # 같은 이름이 이미 존재할 때 덮어쓰지 않는다.
    # 내용이 같으면 중복으로 보고 버리고, 다르면 suffix를 붙여 보존한다.
    if [[ -e "$dest" ]]; then
      if cmp -s -- "$f" "$dest"; then
        duplicate=$((duplicate+1))
        continue
      fi
      stem="${base%.log.gz}"
      n=1
      while [[ -e "$PROXYSG_CLOUD_SOURCE_DIR/${stem}.api${n}.log.gz" ]]; do n=$((n+1)); done
      dest="$PROXYSG_CLOUD_SOURCE_DIR/${stem}.api${n}.log.gz"
    fi

    if mv -- "$f" "${dest}.part.$$"; then
      chmod 0644 "${dest}.part.$$" 2>/dev/null || true
      mv -f -- "${dest}.part.$$" "$dest"
      chown "$FTP_USER:$FTP_GROUP" "$dest" 2>/dev/null || true
      moved=$((moved+1))
    else
      bad=$((bad+1))
      rm -f -- "${dest}.part.$$" 2>/dev/null || true
    fi
  done < <(find "$tmpdir/extracted" -type f -name '*.log.gz' -print0)

  rm -rf "$tmpdir"

  if (( extracted == 0 )); then
    log "CLOUD API WARNING: ZIP contained no *.log.gz files"
    return 1
  fi
  log "CLOUD API SUCCESS: extracted=$extracted moved=$moved duplicate=$duplicate failed=$bad"
  (( bad == 0 ))
}

process_dir() {
  local label="$1" source_dir="$2" process_dir="$3" backup_dir="$4"
  local source_file filename process_tmp backup_tmp process_file backup_file

  find "$source_dir" -maxdepth 1 -type f -name "$PROXYSG_FILE_GLOB" -print0 2>/dev/null | while IFS= read -r -d '' source_file; do
    filename="$(basename "$source_file")"
    process_file="$process_dir/$filename"
    backup_file="$backup_dir/$filename"
    process_tmp="${process_file}.part.$$"
    backup_tmp="${backup_file}.part.$$"

    # 중복 실행 방지 의도를 유지: 이미 backup/process에 있으면 source를 건드리지 않음.
    if [[ -e "$backup_file" ]]; then log "$label WARNING: backup already exists: $filename"; continue; fi
    if [[ -e "$process_file" ]]; then log "$label WARNING: process copy already exists: $filename"; continue; fi

    log "$label Processing: $filename"
    rm -f "$process_tmp" "$backup_tmp"

    if ! cp -p -- "$source_file" "$process_tmp"; then
      log "$label ERROR: process copy failed: $filename"; rm -f "$process_tmp"; continue
    fi
    chmod "$PROXYSG_DIR_MODE" "$process_tmp" || true

    if ! cp -p -- "$source_file" "$backup_tmp"; then
      log "$label ERROR: backup copy failed: $filename"; rm -f "$process_tmp" "$backup_tmp"; continue
    fi
    chmod "$PROXYSG_DIR_MODE" "$backup_tmp" || true

    # 두 복사본이 원본과 동일한지 확인한 뒤 atomic rename.
    if ! cmp -s -- "$source_file" "$process_tmp"; then
      log "$label ERROR: process verification failed: $filename"; rm -f "$process_tmp" "$backup_tmp"; continue
    fi
    if ! cmp -s -- "$source_file" "$backup_tmp"; then
      log "$label ERROR: backup verification failed: $filename"; rm -f "$process_tmp" "$backup_tmp"; continue
    fi

    mv -f -- "$process_tmp" "$process_file"
    mv -f -- "$backup_tmp" "$backup_file"
    chown logstash:logstash "$process_file" 2>/dev/null || true
    chown "$FTP_USER:$FTP_GROUP" "$backup_file" 2>/dev/null || true

    # 최종본이 모두 존재할 때만 source 삭제.
    if [[ -s "$process_file" && -s "$backup_file" ]]; then
      if rm -f -- "$source_file"; then
        log "$label SUCCESS: $filename copied to PROCESS and BACKUP; source removed"
      else
        log "$label WARNING: source removal failed: $filename"
      fi
    fi
  done
}

log "File processing started"
process_dir MAIN "$PROXYSG_MAIN_SOURCE_DIR" "$PROXYSG_MAIN_PROCESS_DIR" "$PROXYSG_MAIN_BACKUP_DIR"
process_dir SSL  "$PROXYSG_SSL_SOURCE_DIR"  "$PROXYSG_SSL_PROCESS_DIR"  "$PROXYSG_SSL_BACKUP_DIR"
if [[ "$CLOUD_ON" == true ]]; then
  if ! cloud_api_download; then
    log "CLOUD API WARNING: download step failed; continuing with files already present in Cloud source directory"
  fi
  process_dir CLOUD "$PROXYSG_CLOUD_SOURCE_DIR" "$PROXYSG_CLOUD_PROCESS_DIR" "$PROXYSG_CLOUD_BACKUP_DIR"
fi
log "File processing finished"
