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

CLOUD_ON=false
[[ "${PROXYSG_CLOUD_ENABLED,,}" == "true" ]] && CLOUD_ON=true
ALL_DIRS=("$PROXYSG_MAIN_SOURCE_DIR" "$PROXYSG_SSL_SOURCE_DIR"
  "$PROXYSG_MAIN_BACKUP_DIR" "$PROXYSG_SSL_BACKUP_DIR"
  "$PROXYSG_MAIN_PROCESS_DIR" "$PROXYSG_SSL_PROCESS_DIR")
if [[ "$CLOUD_ON" == true ]]; then
  ALL_DIRS+=("$PROXYSG_CLOUD_SOURCE_DIR" "$PROXYSG_CLOUD_BACKUP_DIR" "$PROXYSG_CLOUD_PROCESS_DIR")
fi
mkdir -p "${ALL_DIRS[@]}"
chmod "$PROXYSG_DIR_MODE" "${ALL_DIRS[@]}" || true

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
  process_dir CLOUD "$PROXYSG_CLOUD_SOURCE_DIR" "$PROXYSG_CLOUD_PROCESS_DIR" "$PROXYSG_CLOUD_BACKUP_DIR"
fi
log "File processing finished"
