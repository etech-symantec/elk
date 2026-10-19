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
: "${PROXYSG_CLOUD_API_MAX_RETRIES:=3}"
: "${PROXYSG_CLOUD_API_RETRY_DEFAULT_SECONDS:=60}"
: "${PROXYSG_CLOUD_SOURCE_DIR:=/home/cloud}"
: "${PROXYSG_CLOUD_BACKUP_DIR:=/home/cloud_backup}"
: "${PROXYSG_CLOUD_PROCESS_DIR:=/home/cloud_process}"
: "${PROXYSG_MAIN_BACKUP_DIR:=/home/main_backup}"
: "${PROXYSG_SSL_BACKUP_DIR:=/home/ssl_backup}"
: "${PROXYSG_MAIN_PROCESS_DIR:=/home/main_process}"
: "${PROXYSG_SSL_PROCESS_DIR:=/home/ssl_process}"
: "${PROXYSG_FILE_GLOB:=*.log.gz}"
: "${PROXYSG_BACKUP_FORMAT:=gz}"   # gz | zstd
: "${PROXYSG_ZSTD_LEVEL:=19}"     # 1..19; highest standard compression, CPU/RAM intensive
: "${PROXYSG_ZSTD_THREADS:=2}"  # positive integer

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
  log "CLOUD CONFIG: env=$ENV_FILE api_enabled=${PROXYSG_CLOUD_API_ENABLED} api_id=$(mask_id "$PROXYSG_CLOUD_API_USERNAME") api_password=$([[ -n "$PROXYSG_CLOUD_API_PASSWORD" ]] && echo set || echo empty) lookback_days=${PROXYSG_CLOUD_API_LOOKBACK_DAYS} max_retries=${PROXYSG_CLOUD_API_MAX_RETRIES} retry_default=${PROXYSG_CLOUD_API_RETRY_DEFAULT_SECONDS}s url=${PROXYSG_CLOUD_API_URL} insecure=${PROXYSG_CLOUD_API_INSECURE}"
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
  if (( PROXYSG_CLOUD_API_LOOKBACK_DAYS > 7 )); then
    log "CLOUD API ERROR: lookback_days=${PROXYSG_CLOUD_API_LOOKBACK_DAYS} exceeds SyncAPI limit (7 days / 168 hours)"
    return 1
  fi
  [[ "$PROXYSG_CLOUD_API_MAX_RETRIES" =~ ^[0-9]+$ ]] || PROXYSG_CLOUD_API_MAX_RETRIES=3
  [[ "$PROXYSG_CLOUD_API_RETRY_DEFAULT_SECONDS" =~ ^[0-9]+$ ]] || PROXYSG_CLOUD_API_RETRY_DEFAULT_SECONDS=60

  command -v curl >/dev/null 2>&1 || { log "CLOUD API ERROR: curl not found"; return 1; }
  command -v unzip >/dev/null 2>&1 || { log "CLOUD API ERROR: unzip not found"; return 1; }
  command -v python3 >/dev/null 2>&1 || { log "CLOUD API ERROR: python3 not found"; return 1; }

  local start_ms end_date token tmpdir zipfile url http_code
  local extracted=0 moved=0 duplicate=0 bad=0 f base dest stem ext n
  effective_hours=$(( PROXYSG_CLOUD_API_LOOKBACK_DAYS * 24 ))
  # SyncAPI rejects the exact 168-hour boundary in practice.
  # Keep the UI setting at 7 days, but use a 167-hour request window.
  if (( PROXYSG_CLOUD_API_LOOKBACK_DAYS == 7 )); then
    effective_hours=167
  fi
  start_ms="$(python3 - "$effective_hours" <<'PY'
import datetime, sys
hours=int(sys.argv[1])
print(int((datetime.datetime.now() - datetime.timedelta(hours=hours)).timestamp()*1000))
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

  local headerfile="$tmpdir/headers.txt"
  local attempt=1 retry_after wait_seconds api_body=""
  local -a curl_opts=(--silent --show-error --location
    --connect-timeout 15 --max-time 600
    -H "X-APIUsername: ${PROXYSG_CLOUD_API_USERNAME}"
    -H "X-APIPassword: ${PROXYSG_CLOUD_API_PASSWORD}"
    -D "$headerfile"
    -o "$zipfile" -w "%{http_code}")
  [[ "${PROXYSG_CLOUD_API_INSECURE,,}" == "true" ]] && curl_opts+=(--insecure)

  while :; do
    : >"$headerfile"
    : >"$zipfile"
    log "CLOUD API: downloading logs (${PROXYSG_CLOUD_API_LOOKBACK_DAYS} day setting, effective=${effective_hours}h, startDate=${start_ms}, attempt=${attempt}/$((PROXYSG_CLOUD_API_MAX_RETRIES+1)))"

    if ! http_code="$(curl "${curl_opts[@]}" "$url")"; then
      log "CLOUD API ERROR: curl transport failure"
      rm -rf "$tmpdir"
      return 1
    fi

    api_body=""
    if [[ -s "$zipfile" ]]; then
      api_body="$(tr '\r\n\t' '   ' <"$zipfile" | head -c 500)"
    fi

    if [[ "$http_code" == "429" ]]; then
      retry_after="$(awk 'BEGIN{IGNORECASE=1} /^Retry-After:/ {gsub("\r","",$2); print $2; exit}' "$headerfile")"
      if [[ "$retry_after" =~ ^[0-9]+$ ]]; then
        wait_seconds="$retry_after"
      else
        wait_seconds="$PROXYSG_CLOUD_API_RETRY_DEFAULT_SECONDS"
      fi

      log "CLOUD API THROTTLED: HTTP=429 retry_after=${retry_after:-not-provided} wait=${wait_seconds}s response=${api_body:-'(empty body)'}"

      if (( attempt > PROXYSG_CLOUD_API_MAX_RETRIES )); then
        log "CLOUD API ERROR: throttling retry limit exceeded (${PROXYSG_CLOUD_API_MAX_RETRIES} retries)"
        rm -rf "$tmpdir"
        return 1
      fi

      log "CLOUD API RETRY: sleeping ${wait_seconds}s before retry $((attempt+1))/$((PROXYSG_CLOUD_API_MAX_RETRIES+1))"
      sleep "$wait_seconds"
      attempt=$((attempt+1))
      continue
    fi

    if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
      log "CLOUD API ERROR: HTTP=$http_code response=${api_body:-'(empty body)'}"
      rm -rf "$tmpdir"
      return 1
    fi

    if [[ ! -s "$zipfile" ]]; then
      log "CLOUD API ERROR: HTTP=$http_code but response body is empty"
      rm -rf "$tmpdir"
      return 1
    fi

    break
  done

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

# Backup mode: gz keeps original, zstd streams gzip -> zstd without a plaintext .log file.
case "${PROXYSG_BACKUP_FORMAT,,}" in gz|zstd) PROXYSG_BACKUP_FORMAT="${PROXYSG_BACKUP_FORMAT,,}";;
  *) log "ERROR: PROXYSG_BACKUP_FORMAT must be gz or zstd"; exit 1;; esac
if [[ "$PROXYSG_BACKUP_FORMAT" == zstd ]]; then
  command -v gzip >/dev/null || { log 'ERROR: gzip not found'; exit 1; }
  command -v zstd >/dev/null || { log 'ERROR: zstd not found (sudo apt-get install zstd)'; exit 1; }
  [[ "$PROXYSG_ZSTD_LEVEL" =~ ^([1-9]|1[0-9])$ ]] || { log 'ERROR: ZSTD level must be 1..19'; exit 1; }
  [[ "$PROXYSG_ZSTD_THREADS" =~ ^[1-9][0-9]*$ ]] || { log 'ERROR: ZSTD threads must be positive integer'; exit 1; }
fi

process_dir() {
  local label="$1" source_dir="$2" process_dir="$3" backup_dir="$4"
  local source_file filename process_tmp backup_tmp process_file backup_file txt_base

  while IFS= read -r -d '' source_file; do
    filename="$(basename "$source_file")"
    process_file="$process_dir/$filename"
    txt_base="${filename%.gz}"
    if [[ "$PROXYSG_BACKUP_FORMAT" == zstd ]]; then
      backup_file="$backup_dir/${txt_base}.zst"
    else
      backup_file="$backup_dir/$filename"
    fi
    process_tmp="${process_file}.part.$$"
    backup_tmp="${backup_file}.part.$$"

    # Existing archive / process means manual review, never silently delete input.
    if [[ -e "$backup_file" ]]; then log "$label WARNING: backup already exists: $backup_file"; continue; fi
    if [[ -e "$process_file" ]]; then log "$label WARNING: process copy already exists: $filename"; continue; fi
    log "$label Processing: $filename [backup=$PROXYSG_BACKUP_FORMAT]"
    rm -f -- "$process_tmp" "$backup_tmp"
    if ! cp -p -- "$source_file" "$process_tmp"; then
      log "$label ERROR: process copy failed: $filename"; rm -f -- "$process_tmp"; continue
    fi
    if ! cmp -s -- "$source_file" "$process_tmp"; then
      log "$label ERROR: process verification failed: $filename"; rm -f -- "$process_tmp"; continue
    fi
    if [[ "$PROXYSG_BACKUP_FORMAT" == zstd ]]; then
      # Decompress to stdout and immediately compress: no intermediate plaintext on disk.
      if ! (set -o pipefail; gzip -cd -- "$source_file" | zstd -q -T"$PROXYSG_ZSTD_THREADS" -"$PROXYSG_ZSTD_LEVEL" -o "$backup_tmp"); then
        log "$label ERROR: streaming zstd compression failed: $filename"; rm -f -- "$process_tmp" "$backup_tmp"; continue
      fi
      if ! zstd -q -t -- "$backup_tmp"; then
        log "$label ERROR: archive zstd integrity test failed: $filename"; rm -f -- "$process_tmp" "$backup_tmp"; continue
      fi
      # Check round-trip content identity, not only archive checksum.
      if [[ "$(gzip -cd -- "$source_file" | sha256sum | cut -d' ' -f1)" != "$(zstd -dcq -- "$backup_tmp" | sha256sum | cut -d' ' -f1)" ]]; then
        log "$label ERROR: decompressed sha256 mismatch: $filename"; rm -f -- "$process_tmp" "$backup_tmp"; continue
      fi
    else
      if ! cp -p -- "$source_file" "$backup_tmp" || ! cmp -s -- "$source_file" "$backup_tmp"; then
        log "$label ERROR: backup copy/verification failed: $filename"; rm -f -- "$process_tmp" "$backup_tmp"; continue
      fi
    fi
    chmod "$PROXYSG_DIR_MODE" "$process_tmp" 2>/dev/null || true
    chmod "$PROXYSG_DIR_MODE" "$backup_tmp" 2>/dev/null || true

    # Commit backup first, then publish process to Logstash.
    if ! mv -n -- "$backup_tmp" "$backup_file"; then
      log "$label ERROR: archive rename failed: $filename"; rm -f -- "$process_tmp" "$backup_tmp"; continue
    fi
    # GNU mv -n can return zero without moving. Verify archive exists and temp is gone.
    if [[ ! -s "$backup_file" || -e "$backup_tmp" ]]; then
      log "$label ERROR: archive finalization failed: $filename"; rm -f -- "$process_tmp" "$backup_tmp"; continue
    fi
    if ! mv -n -- "$process_tmp" "$process_file"; then
      log "$label ERROR: process publish failed: $filename"; rm -f -- "$process_tmp"; continue
    fi
    if [[ ! -s "$process_file" || -e "$process_tmp" ]]; then
      log "$label ERROR: process file finalization failed: $filename"; rm -f -- "$process_tmp"; continue
    fi
    chown logstash:logstash "$process_file" 2>/dev/null || true
    chown "$FTP_USER:$FTP_GROUP" "$backup_file" 2>/dev/null || true

    if rm -f -- "$source_file"; then
      log "$label SUCCESS: $filename -> PROCESS gzip + BACKUP $PROXYSG_BACKUP_FORMAT; source removed"
    else
      log "$label WARNING: source removal failed: $filename"
    fi
  done < <(find "$source_dir" -maxdepth 1 -type f -name "$PROXYSG_FILE_GLOB" -print0 2>/dev/null)
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
