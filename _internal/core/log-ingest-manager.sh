#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ENV_FILE="${1:-/etc/elk-auto/elk.env}"
ACTION="${2:-run}"

[[ -f "$ENV_FILE" ]] || { echo "[ERROR] env 파일 없음: $ENV_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"

: "${FILE_INGEST_MANAGER_ENABLED:=false}"
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
: "${FILE_INGEST_BACKUP_RETENTION_DAYS:=0}"
: "${FILE_INGEST_DUPLICATE_RETENTION_DAYS:=0}"
: "${FILE_INGEST_QUARANTINE_RETENTION_DAYS:=0}"
: "${FILE_INGEST_DELETE_STAGING_AFTER_COMPLETE:=true}"
: "${FILE_INGEST_LOG:=/var/log/elk-file-ingest.log}"
: "${FILE_INGEST_LOCK_FILE:=/run/lock/elk-file-ingest.lock}"

istrue(){ [[ "${1,,}" =~ ^(1|true|yes|y|on)$ ]]; }
ts(){ date '+%Y-%m-%d %H:%M:%S'; }
log(){ printf '[%s] [INFO] %s\n' "$(ts)" "$*" | tee -a "$FILE_INGEST_LOG"; }
warn(){ printf '[%s] [WARN] %s\n' "$(ts)" "$*" | tee -a "$FILE_INGEST_LOG" >&2; }
err(){ printf '[%s] [ERROR] %s\n' "$(ts)" "$*" | tee -a "$FILE_INGEST_LOG" >&2; }

if ! istrue "$FILE_INGEST_MANAGER_ENABLED" && [[ "$ACTION" != "status" ]]; then
  exit 0
fi

mkdir -p "$(dirname "$FILE_INGEST_LOG")" "$(dirname "$FILE_INGEST_LOCK_FILE")" \
  "$FILE_INGEST_STAGING_DIR" "$FILE_INGEST_STATE_DIR" "$FILE_INGEST_BACKUP_DIR" \
  "$FILE_INGEST_DUPLICATE_DIR" "$FILE_INGEST_QUARANTINE_DIR" "$(dirname "$FILE_INGEST_COMPLETED_LOG")"
touch "$FILE_INGEST_LOG"
chmod 640 "$FILE_INGEST_LOG" || true

exec 9>"$FILE_INGEST_LOCK_FILE"
if ! flock -n 9; then
  log "다른 file-ingest 작업이 실행 중이므로 종료합니다."
  exit 0
fi

sanitize_name(){ printf '%s' "$1" | tr '/\n\r\t ' '_____'; }
base64_one(){ printf '%s' "$1" | base64 -w0; }

supported_file(){
  local f="$1" ext allowed
  ext="${f##*.}"; ext="${ext,,}"
  IFS=',' read -ra _exts <<< "$FILE_INGEST_EXTENSIONS"
  for allowed in "${_exts[@]}"; do
    allowed="${allowed#.}"; allowed="${allowed,,}"; allowed="${allowed//[[:space:]]/}"
    [[ "$ext" == "$allowed" ]] && return 0
  done
  return 1
}

is_compressed(){
  case "${1,,}" in *.gz|*.xz|*.zst|*.bz2) return 0;; *) return 1;; esac
}

stream_content(){
  local f="$1"
  case "${f,,}" in
    *.gz)  gzip -dc -- "$f" ;;
    *.xz)  xz -dc -- "$f" ;;
    *.zst) zstd -dcq -- "$f" ;;
    *.bz2) bzip2 -dc -- "$f" ;;
    *)     cat -- "$f" ;;
  esac
}

state_file(){ printf '%s/%s.json' "$FILE_INGEST_STATE_DIR" "$1"; }
state_status(){ jq -r '.status // ""' "$(state_file "$1")" 2>/dev/null || true; }

write_state(){
  local hash="$1" src="$2" root="$3" stage="$4" status="$5" note="${6:-}" backup="${7:-}"
  local sf tmp
  sf="$(state_file "$hash")"; tmp="${sf}.tmp.$$"
  jq -n \
    --arg hash "$hash" --arg src "$src" --arg root "$root" --arg stage "$stage" \
    --arg status "$status" --arg note "$note" --arg backup "$backup" \
    --arg now "$(date -Is)" \
    '{hash:$hash,source:$src,source_root:$root,staging:$stage,status:$status,note:$note,backup:$backup,updated_at:$now}' > "$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "$sf"
}

update_state(){
  local sf="$1" status="$2" note="${3:-}" backup="${4:-}" tmp="${sf}.tmp.$$"
  jq --arg s "$status" --arg n "$note" --arg b "$backup" --arg now "$(date -Is)" \
    '.status=$s | .note=$n | .backup=$b | .updated_at=$now' "$sf" > "$tmp"
  chmod 600 "$tmp"; mv -f "$tmp" "$sf"
}

unique_path(){
  local wanted="$1" hash="${2:-}"
  if [[ ! -e "$wanted" ]]; then printf '%s' "$wanted"; return; fi
  local suffix="$(date '+%Y%m%d-%H%M%S')"
  [[ -n "$hash" ]] && suffix+=".${hash:0:12}"
  printf '%s.%s' "$wanted" "$suffix"
}

relative_path(){
  local src="$1" root="$2"
  if istrue "$FILE_INGEST_PRESERVE_RELATIVE_PATH" && [[ "$src" == "$root"/* ]]; then
    printf '%s' "${src#"$root"/}"
  else
    basename -- "$src"
  fi
}

archive_duplicate(){
  local src="$1" root="$2" hash="$3" rel dest
  case "${FILE_INGEST_DUPLICATE_ACTION,,}" in
    leave)
      log "중복 파일 유지: $src ($hash)"
      ;;
    delete)
      rm -f -- "$src"
      log "중복 파일 삭제: $src ($hash)"
      ;;
    archive)
      rel="$(relative_path "$src" "$root")"
      dest="$FILE_INGEST_DUPLICATE_DIR/$(date '+%Y/%m/%d')/$rel"
      mkdir -p "$(dirname "$dest")"
      dest="$(unique_path "$dest" "$hash")"
      mv -- "$src" "$dest"
      log "중복 파일 보관: $src -> $dest"
      ;;
    *)
      warn "알 수 없는 FILE_INGEST_DUPLICATE_ACTION=$FILE_INGEST_DUPLICATE_ACTION; 파일을 유지합니다: $src"
      ;;
  esac
}

quarantine(){
  local src="$1" root="$2" reason="$3" rel dest
  [[ -e "$src" ]] || return 0
  rel="$(relative_path "$src" "$root")"
  dest="$FILE_INGEST_QUARANTINE_DIR/$(date '+%Y/%m/%d')/$rel"
  mkdir -p "$(dirname "$dest")"
  dest="$(unique_path "$dest")"
  mv -- "$src" "$dest"
  err "격리: $src -> $dest / 원인: $reason"
}

archive_original(){
  local src="$1" root="$2" hash="$3" rel dest tmp level="$FILE_INGEST_COMPRESSION_LEVEL"
  [[ -e "$src" ]] || { warn "완료 처리할 원본이 이미 없습니다: $src"; return 0; }
  rel="$(relative_path "$src" "$root")"
  dest="$FILE_INGEST_BACKUP_DIR/$(date '+%Y/%m/%d')/$rel"
  mkdir -p "$(dirname "$dest")"

  if is_compressed "$src" || [[ "${FILE_INGEST_PLAIN_BACKUP_COMPRESSION,,}" == "none" ]]; then
    dest="$(unique_path "$dest" "$hash")"
    mv -- "$src" "$dest"
    printf '%s' "$dest"
    return 0
  fi

  case "${FILE_INGEST_PLAIN_BACKUP_COMPRESSION,,}" in
    zstd)
      dest="$(unique_path "${dest}.zst" "$hash")"; tmp="${dest}.partial.$$"
      zstd -T0 -q "-${level}" -c -- "$src" > "$tmp" && mv -f "$tmp" "$dest" && rm -f -- "$src"
      ;;
    gzip)
      dest="$(unique_path "${dest}.gz" "$hash")"; tmp="${dest}.partial.$$"
      gzip "-${level}" -c -- "$src" > "$tmp" && mv -f "$tmp" "$dest" && rm -f -- "$src"
      ;;
    xz)
      dest="$(unique_path "${dest}.xz" "$hash")"; tmp="${dest}.partial.$$"
      xz -T0 "-${level}" -c -- "$src" > "$tmp" && mv -f "$tmp" "$dest" && rm -f -- "$src"
      ;;
    *)
      warn "지원하지 않는 백업 압축 방식: $FILE_INGEST_PLAIN_BACKUP_COMPRESSION. 원본 그대로 이동합니다."
      dest="$(unique_path "$dest" "$hash")"; mv -- "$src" "$dest"
      ;;
  esac
  printf '%s' "$dest"
}

completed_contains(){
  local target="$1" f
  shopt -s nullglob
  for f in "$FILE_INGEST_COMPLETED_LOG" "$FILE_INGEST_COMPLETED_LOG".*; do
    [[ -f "$f" ]] || continue
    case "$f" in
      *.gz) zgrep -Fqx -- "$target" "$f" 2>/dev/null && return 0 ;;
      *)    grep  -Fqx -- "$target" "$f" 2>/dev/null && return 0 ;;
    esac
  done
  return 1
}

process_completed(){
  local sf status stage src root hash backup
  shopt -s nullglob
  for sf in "$FILE_INGEST_STATE_DIR"/*.json; do
    status="$(jq -r '.status // ""' "$sf" 2>/dev/null || true)"
    [[ "$status" == "staged" ]] || continue
    stage="$(jq -r '.staging // ""' "$sf")"
    [[ -n "$stage" ]] || continue
    if completed_contains "$stage"; then
      src="$(jq -r '.source // ""' "$sf")"
      root="$(jq -r '.source_root // ""' "$sf")"
      hash="$(jq -r '.hash // ""' "$sf")"
      backup="$(archive_original "$src" "$root" "$hash")" || {
        update_state "$sf" "archive_error" "원본 백업 실패" ""
        err "원본 백업 실패: $src"
        continue
      }
      if istrue "$FILE_INGEST_DELETE_STAGING_AFTER_COMPLETE"; then rm -f -- "$stage"; fi
      update_state "$sf" "completed" "Logstash read 완료" "$backup"
      log "수집 완료: $src -> backup=$backup"
    fi
  done
}

free_gb(){ df -Pk "$FILE_INGEST_STAGING_DIR" | awk 'NR==2{printf "%d", $4/1024/1024}'; }

process_one(){
  local src="$1" root="$2" now mtime age size free tmp hash rc stage sf status safe
  now="$(date +%s)"; mtime="$(stat -c %Y -- "$src" 2>/dev/null || echo 0)"; age=$((now-mtime))
  (( age >= FILE_INGEST_MIN_AGE_SECONDS )) || return 0
  supported_file "$src" || return 0

  size="$(stat -c %s -- "$src" 2>/dev/null || echo 0)"
  if (( FILE_INGEST_MAX_SOURCE_FILE_BYTES > 0 && size > FILE_INGEST_MAX_SOURCE_FILE_BYTES )); then
    quarantine "$src" "$root" "source file size ${size} > limit ${FILE_INGEST_MAX_SOURCE_FILE_BYTES}"
    return 0
  fi

  free="$(free_gb)"
  if (( free < FILE_INGEST_MIN_STAGING_FREE_GB )); then
    warn "스테이징 디스크 여유 ${free}GB < 최소 ${FILE_INGEST_MIN_STAGING_FREE_GB}GB. 신규 파일 처리를 중지합니다."
    return 2
  fi

  safe="$(sanitize_name "$(basename -- "$src")")"
  tmp="$FILE_INGEST_STAGING_DIR/.${safe}.$$.partial"
  rm -f -- "$tmp"

  set +e
  if [[ "${FILE_INGEST_DEDUPE_MODE,,}" == "content_sha256" ]]; then
    hash="$(stream_content "$src" | tee "$tmp" | sha256sum | awk '{print $1}')"
    rc=$?
  else
    stream_content "$src" > "$tmp"
    rc=$?
    if [[ "${FILE_INGEST_DEDUPE_MODE,,}" == "none" ]]; then
      hash="$(printf '%s|%s|%s|%s' "$src" "$size" "$mtime" "$(date +%s%N)" | sha256sum | awk '{print $1}')"
    else
      hash="$(printf '%s|%s|%s' "$src" "$size" "$mtime" | sha256sum | awk '{print $1}')"
    fi
  fi
  set -e

  if (( rc != 0 )) || [[ ! -s "$tmp" ]]; then
    rm -f -- "$tmp"
    quarantine "$src" "$root" "압축 해제/읽기 실패 또는 빈 파일"
    return 0
  fi

  # 파일을 읽는 동안 업로드/수정이 재개되었는지 확인. 변경되었다면 다음 주기에 다시 처리한다.
  local size_after mtime_after
  size_after="$(stat -c %s -- "$src" 2>/dev/null || echo -1)"
  mtime_after="$(stat -c %Y -- "$src" 2>/dev/null || echo -1)"
  if [[ "$size_after" != "$size" || "$mtime_after" != "$mtime" ]]; then
    rm -f -- "$tmp"
    warn "처리 중 원본 파일이 변경되어 이번 주기에서 제외합니다: $src"
    return 0
  fi

  sf="$(state_file "$hash")"
  if [[ -f "$sf" ]]; then
    status="$(state_status "$hash")"
    rm -f -- "$tmp"
    archive_duplicate "$src" "$root" "$hash"
    log "중복 감지: hash=$hash, 기존 상태=$status"
    return 0
  fi

  stage="$FILE_INGEST_STAGING_DIR/${hash}__${safe}.ready"
  mv -f -- "$tmp" "$stage"
  chown logstash:logstash "$stage" 2>/dev/null || true
  chmod 640 "$stage"
  write_state "$hash" "$src" "$root" "$stage" "staged" "Logstash 대기"
  log "스테이징 완료: $src -> $stage (sha256=$hash)"
}

cleanup_retention(){
  local days="$1" dir="$2" label="$3"
  (( days > 0 )) || return 0
  [[ -d "$dir" ]] || return 0
  find "$dir" -type f -mtime "+$days" -print -delete 2>/dev/null | while read -r f; do log "$label 보존기간 만료 삭제: $f"; done
  find "$dir" -type d -empty -delete 2>/dev/null || true
}

scan_sources(){
  local root count=0 f rc
  IFS=',' read -ra roots <<< "$FILE_INGEST_SOURCE_DIRS"
  for root in "${roots[@]}"; do
    root="$(echo "$root" | xargs)"; [[ -n "$root" ]] || continue
    mkdir -p "$root"
    if istrue "$FILE_INGEST_RECURSIVE"; then
      mapfile -d '' files < <(find "$root" -type f -print0 2>/dev/null)
    else
      mapfile -d '' files < <(find "$root" -maxdepth 1 -type f -print0 2>/dev/null)
    fi
    for f in "${files[@]}"; do
      (( count >= FILE_INGEST_MAX_FILES_PER_RUN )) && return 0
      process_one "$f" "$root" || rc=$?
      rc="${rc:-0}"
      [[ "$rc" == "2" ]] && return 0
      rc=0
      if supported_file "$f"; then count=$((count+1)); fi
    done
  done
}

show_status(){
  local staged completed archive_error total
  total=$(find "$FILE_INGEST_STATE_DIR" -maxdepth 1 -name '*.json' -type f 2>/dev/null | wc -l)
  staged=$(grep -l '"status": "staged"' "$FILE_INGEST_STATE_DIR"/*.json 2>/dev/null | wc -l || true)
  completed=$(grep -l '"status": "completed"' "$FILE_INGEST_STATE_DIR"/*.json 2>/dev/null | wc -l || true)
  archive_error=$(grep -l '"status": "archive_error"' "$FILE_INGEST_STATE_DIR"/*.json 2>/dev/null | wc -l || true)
  cat <<STATUS
ELK File Ingest Manager
  enabled       : $FILE_INGEST_MANAGER_ENABLED
  source dirs   : $FILE_INGEST_SOURCE_DIRS
  staging       : $FILE_INGEST_STAGING_DIR
  backup        : $FILE_INGEST_BACKUP_DIR
  free staging  : $(free_gb) GB
  states total  : $total
  staged        : $staged
  completed     : $completed
  archive_error : $archive_error
STATUS
}

case "$ACTION" in
  run)
    process_completed
    scan_sources
    cleanup_retention "$FILE_INGEST_BACKUP_RETENTION_DAYS" "$FILE_INGEST_BACKUP_DIR" "백업"
    cleanup_retention "$FILE_INGEST_DUPLICATE_RETENTION_DAYS" "$FILE_INGEST_DUPLICATE_DIR" "중복"
    cleanup_retention "$FILE_INGEST_QUARANTINE_RETENTION_DAYS" "$FILE_INGEST_QUARANTINE_DIR" "격리"
    ;;
  status) show_status ;;
  reconcile) process_completed ;;
  *) echo "사용법: $0 [elk.env] {run|status|reconcile}" >&2; exit 2 ;;
esac
