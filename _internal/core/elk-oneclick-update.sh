#!/usr/bin/env bash
# ELK One-Click public GitHub delta-only updater
#
# 기본 동작
#   --check : GitHub 메타데이터만 조회하여 변경 파일 확인. core 파일 다운로드 없음.
#   --apply : 실제로 변경된 런타임 파일만 다운로드 + 교체.
#   --force : 런타임 파일 전체를 다시 다운로드 + 교체.
#   --full  : 명시적으로 전체 install-elk 재적용.
#
# 핵심: --apply에서는 install-elk.sh를 실행하지 않으며, 변경되지 않은 core 파일도
#       다운로드하지 않습니다.
set -Eeuo pipefail

OWNER="${ELK_ONECLICK_GITHUB_OWNER:-etech-symantec}"
REPO="${ELK_ONECLICK_GITHUB_REPO:-elk}"
BRANCH="${ELK_ONECLICK_GITHUB_BRANCH:-main}"

ENVF="${ELK_ENV_FILE:-/etc/elk-auto/elk.env}"
RELEASE="${ELK_ONECLICK_RELEASE_FILE:-/etc/elk-auto/oneclick-release.env}"
REMOTE_MANIFEST="${ELK_ONECLICK_REMOTE_MANIFEST:-/etc/elk-auto/oneclick-github-blobs.tsv}"
BACKUP_ROOT="${ELK_ONECLICK_BACKUP_DIR:-/var/backups/elk-oneclick}"

MODE="${1:---check}"

say(){ printf '%s\n' "$*"; }
die(){ say "[ERROR] $*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "$1 명령이 필요합니다."; }

for c in curl jq sha1sum sha256sum stat cmp sort; do need "$c"; done


case "$MODE" in
  --check|check|--version|--apply|apply|--force|force|--full|full) ;;
  *)
    cat <<'USAGE'
사용:
  sudo elk-oneclick-update --check   # 변경 파일 확인 (core 파일 다운로드 없음)
  sudo elk-oneclick-update --apply   # 변경된 런타임 파일만 다운로드/교체
  sudo elk-oneclick-update --force   # 런타임 파일 전체 재다운로드/교체
  sudo elk-oneclick-update --full    # 전체 install-elk 재적용
USAGE
    exit 2
    ;;
esac

RAW="https://raw.githubusercontent.com/$OWNER/$REPO/$BRANCH"
API="https://api.github.com/repos/$OWNER/$REPO/contents/_internal/core?ref=$BRANCH"

GET(){
  curl -fsSL --connect-timeout 10 --max-time 120 \
    -H "Accept: application/vnd.github+json" \
    -H "User-Agent: elk-oneclick-update" "$1"
}

cmpver(){
  local a="$1" b="$2" top
  [[ "$a" == "$b" ]] && { echo 0; return; }
  top="$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -1)"
  [[ "$top" == "$a" ]] && echo 1 || echo -1
}

# GitHub Contents API가 반환하는 .sha는 Git blob SHA-1입니다.
# 실제 설치 파일의 Git blob SHA를 계산하면 파일 다운로드 없이 변경 여부를 판별할 수 있습니다.
git_blob_sha_file(){
  local f="$1" sz
  sz="$(stat -c %s "$f")" || return 1
  { printf 'blob %s\0' "$sz"; cat "$f"; } | sha1sum | awk '{print $1}'
}

PROXYSG_PROCESS_SCRIPT_CURRENT="/usr/local/sbin/elk-proxysg-log-process"
if [[ -r "$ENVF" ]]; then
  set +u
  # shellcheck disable=SC1090
  source "$ENVF" 2>/dev/null || true
  set -u
  PROXYSG_PROCESS_SCRIPT_CURRENT="${PROXYSG_PROCESS_SCRIPT:-$PROXYSG_PROCESS_SCRIPT_CURRENT}"
fi

target_for(){
  case "$1" in
    check-elk.sh)              printf '%s' "/usr/local/sbin/elk-check" ;;
    proxysg-log-process.sh)    printf '%s' "$PROXYSG_PROCESS_SCRIPT_CURRENT" ;;
    proxysg-log-filter.conf)   printf '%s' "/usr/local/lib/elk-auto/proxysg-log-filter.conf" ;;
    elk-health-monitor.sh)     printf '%s' "/usr/local/sbin/elk-health-monitor" ;;
    elk-ops.sh)                printf '%s' "/usr/local/sbin/elk-ops" ;;
    elk-patch.sh)              printf '%s' "/usr/local/sbin/elk-patch" ;;
    elk-color.sh)              printf '%s' "/usr/local/lib/elk-auto/elk-color.sh" ;;
    elk-report.sh)             printf '%s' "/usr/local/sbin/elk-report" ;;
    elk-report-web.py)         printf '%s' "/usr/local/lib/elk-auto/elk-report-web.py" ;;
    elk-tls-lib.sh)            printf '%s' "/usr/local/lib/elk-auto/elk-tls-lib.sh" ;;
    proxysg-lib.sh)            printf '%s' "/usr/local/lib/elk-auto/proxysg-lib.sh" ;;
    log-ingest-manager.sh)     printf '%s' "/usr/local/sbin/log-ingest-manager" ;;
    elk-oneclick-update.sh)    printf '%s' "/usr/local/sbin/elk-oneclick-update" ;;
    elk-oneclick-adopt.sh)     printf '%s' "/usr/local/sbin/elk-oneclick-adopt" ;;
    *) return 1 ;;
  esac
}

mode_for(){
  case "$1" in
    *.conf|elk-color.sh|elk-tls-lib.sh|proxysg-lib.sh) echo 644 ;;
    *) echo 755 ;;
  esac
}

IV=""; IB=""
if [[ -f "$RELEASE" ]]; then
  # shellcheck disable=SC1090
  source "$RELEASE" 2>/dev/null || true
  IV="${ONECLICK_VERSION:-}"
  IB="${ONECLICK_BUILD:-}"
fi

LV="$(GET "$RAW/_internal/docs/VERSION" | tr -d '\r\n ')"
[[ -n "$LV" ]] || die "GitHub VERSION 파일을 읽지 못했습니다."

# build 정보는 config-wizard.html 헤더만 읽음 (core 파일과 무관)
WIZ="$(GET "$RAW/config-wizard.html")" || die "config-wizard.html을 읽지 못했습니다."
LB="$(grep -oE "WIZARD_BUILD=['\"][^'\"]+" <<<"$WIZ" | head -1 | sed -E "s/.*['\"]//")"
[[ -n "$LB" ]] || LB="unknown"

C=-1
if [[ "$IV" =~ ^[0-9]+([.][0-9]+)*([._-][A-Za-z0-9.-]+)?$ ]]; then
  C="$(cmpver "$IV" "$LV")"
fi
if [[ "$C" == 1 && "$MODE" != "--force" && "$MODE" != "force" ]]; then
  die "설치된 v$IV가 GitHub v$LV보다 새 버전입니다. 자동 다운그레이드는 차단합니다."
fi

# GitHub core 디렉터리는 Contents API 메타데이터만 읽습니다.
LIST="$(GET "$API")" || die "GitHub _internal/core 파일 목록을 가져오지 못했습니다."
jq -e 'type=="array"' >/dev/null <<<"$LIST" || \
  die "GitHub API 응답 형식이 올바르지 않습니다. API rate limit도 확인하세요."

mapfile -t NAMES < <(jq -r '.[]|select(.type=="file")|.name' <<<"$LIST" | sort)
(( ${#NAMES[@]} > 0 )) || die "_internal/core 파일 목록이 비어 있습니다."

declare -A REMOTE_SHA=()
for N in "${NAMES[@]}"; do
  [[ "$N" =~ ^[A-Za-z0-9._-]+$ ]] || die "잘못된 파일명: $N"
  REMOTE_SHA["$N"]="$(jq -r --arg n "$N" '.[]|select(.type=="file" and .name==$n)|.sha' <<<"$LIST" | head -1)"
  [[ "${REMOTE_SHA[$N]}" =~ ^[0-9a-f]{40}$ ]] || die "GitHub blob SHA 확인 실패: $N"
done

declare -A PREV_SHA=()
if [[ -r "$REMOTE_MANIFEST" ]]; then
  while IFS=$'\t' read -r sha name; do
    [[ "$sha" =~ ^[0-9a-f]{40}$ && "$name" =~ ^[A-Za-z0-9._-]+$ ]] || continue
    PREV_SHA["$name"]="$sha"
  done < "$REMOTE_MANIFEST"
fi

declare -a CHANGED_RUNTIME=()
declare -a SAME_RUNTIME=()
declare -a CHANGED_SOURCE=()
declare -a BASELINE_SOURCE=()

FORCE=0
[[ "$MODE" == "--force" || "$MODE" == "force" ]] && FORCE=1

for N in "${NAMES[@]}"; do
  if DEST="$(target_for "$N" 2>/dev/null)"; then
    if (( FORCE )); then
      CHANGED_RUNTIME+=("$N")
    elif [[ ! -f "$DEST" ]]; then
      CHANGED_RUNTIME+=("$N")
    else
      LOCAL_SHA="$(git_blob_sha_file "$DEST" 2>/dev/null || true)"
      if [[ "$LOCAL_SHA" == "${REMOTE_SHA[$N]}" ]]; then
        SAME_RUNTIME+=("$N")
      else
        CHANGED_RUNTIME+=("$N")
      fi
    fi
  else
    if [[ -n "${PREV_SHA[$N]:-}" ]]; then
      if [[ "${PREV_SHA[$N]}" != "${REMOTE_SHA[$N]}" ]]; then
        CHANGED_SOURCE+=("$N")
      fi
    else
      BASELINE_SOURCE+=("$N")
    fi
  fi
done

say "ELK One-Click GitHub 증분 업데이트 확인"
say "  저장소       : https://github.com/$OWNER/$REPO ($BRANCH)"
say "  설치 버전    : ${IV:-확인 불가}"
say "  설치 빌드    : ${IB:-확인 불가}"
say "  GitHub 버전  : $LV"
say "  GitHub 빌드  : $LB"
say "  모드         : delta-only"
say "  비교 방식    : GitHub blob SHA ↔ 실제 설치 파일"

if (( ${#CHANGED_RUNTIME[@]} )); then
  say
  say "  [실제 업데이트 대상]"
  for N in "${CHANGED_RUNTIME[@]}"; do
    say "    · $N -> $(target_for "$N")"
  done
else
  say
  say "  [실제 업데이트 대상] 없음"
fi

if (( ${#CHANGED_SOURCE[@]} )); then
  say
  say "  [설치 엔진/소스 변경 - 기본 --apply에서는 적용하지 않음]"
  for N in "${CHANGED_SOURCE[@]}"; do say "    · $N"; done
  say "    ※ 전체 설치 구성을 다시 적용할 때만 --full 사용"
fi

if (( ${#BASELINE_SOURCE[@]} )); then
  say
  say "  [소스 비교 기준 최초 등록]"
  for N in "${BASELINE_SOURCE[@]}"; do say "    · $N"; done
  say "    ※ 파일 다운로드 없이 GitHub SHA만 기준값으로 등록합니다."
fi

TOTAL_RUNTIME=${#CHANGED_RUNTIME[@]}
TOTAL_SOURCE=${#CHANGED_SOURCE[@]}

if [[ "$MODE" == "--check" || "$MODE" == "check" || "$MODE" == "--version" ]]; then
  say
  say "  core 파일 다운로드 : 0개"
  say "  런타임 변경        : $TOTAL_RUNTIME개"
  say "  소스 변경          : $TOTAL_SOURCE개"
  (( TOTAL_RUNTIME + TOTAL_SOURCE > 0 )) && exit 10 || exit 0
fi

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "적용은 root 권한이 필요합니다. sudo를 사용하세요."
[[ -f "$ENVF" ]] || die "기존 설치 설정을 찾을 수 없습니다: $ENVF"

T="$(mktemp -d /tmp/elk-oneclick-update.XXXXXX)"
cleanup(){ rm -rf "$T"; }
trap cleanup EXIT

download_one(){
  local n="$1"
  say "  [DOWNLOAD] $n"
  curl -fsSL --connect-timeout 10 --max-time 120 \
    "$RAW/_internal/core/$n" -o "$T/$n" || die "다운로드 실패: $n"
}

declare -a DOWNLOAD_NAMES=()

if [[ "$MODE" == "--full" || "$MODE" == "full" ]]; then
  # full은 사용자가 명시적으로 요청한 경우에만 전체 core 다운로드.
  DOWNLOAD_NAMES=("${NAMES[@]}")
else
  # 기본 --apply / --force는 실제 런타임 변경 파일만 다운로드.
  DOWNLOAD_NAMES=("${CHANGED_RUNTIME[@]}")
fi

say
say "[다운로드]"
if (( ${#DOWNLOAD_NAMES[@]} == 0 )); then
  say "  변경된 런타임 파일이 없어 core 다운로드를 수행하지 않습니다."
else
  say "  ${#DOWNLOAD_NAMES[@]}개 파일만 다운로드합니다."
  for N in "${DOWNLOAD_NAMES[@]}"; do download_one "$N"; done
fi

# 다운로드한 파일만 SHA256 검증.
if (( ${#DOWNLOAD_NAMES[@]} > 0 )); then
  SUMS="$(GET "$RAW/SHA256SUMS.txt" 2>/dev/null || true)"
  if [[ -n "$SUMS" ]]; then
    bad=0
    for N in "${DOWNLOAD_NAMES[@]}"; do
      EXP="$(awk -v p="_internal/core/$N" '$2==p{print $1}' <<<"$SUMS" | tail -1)"
      [[ -z "$EXP" ]] && continue
      ACT="$(sha256sum "$T/$N" | awk '{print $1}')"
      [[ "$ACT" == "$EXP" ]] || { say "[ERROR] SHA256 불일치: $N"; bad=1; }
    done
    (( bad == 0 )) || die "파일 무결성 검증에 실패했습니다."
  else
    say "[WARN] SHA256SUMS.txt를 읽지 못해 다운로드 파일의 repository hash 검증을 생략합니다."
  fi
fi

if [[ "$MODE" == "--full" || "$MODE" == "full" ]]; then
  [[ -f "$T/install-elk.sh" ]] || die "업데이트에 install-elk.sh가 없습니다."

  BK="${ENVF}.before-github-full-${LV}-$(date +%Y%m%d-%H%M%S)"
  cp -a "$ENVF" "$BK"
  say "  설정 백업: $BK"

  PATCH_ENV="$T/elk.env"
  cp -a "$ENVF" "$PATCH_ENV"
  chmod 600 "$PATCH_ENV"

  LOGSTASH_WAS_ACTIVE=0
  restore_logstash(){
    if (( LOGSTASH_WAS_ACTIVE )); then
      say "[INFO] Logstash 서비스를 다시 시작합니다."
      systemctl start logstash >/dev/null 2>&1 || true
    fi
  }

  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet logstash 2>/dev/null; then
    LOGSTASH_WAS_ACTIVE=1
    say "[INFO] 전체 재적용 검증을 위해 Logstash를 잠시 중지합니다."
    systemctl stop logstash
    for _i in {1..30}; do
      systemctl is-active --quiet logstash 2>/dev/null || break
      sleep 1
    done
    systemctl is-active --quiet logstash 2>/dev/null && die "Logstash 서비스가 30초 안에 중지되지 않았습니다."
  fi

  FULL_OK=0
  full_cleanup(){
    rc=$?
    if (( FULL_OK == 0 )); then restore_logstash; fi
    exit "$rc"
  }
  trap full_cleanup EXIT

  say "[1/3] 최신 설치기 검증"
  bash "$T/install-elk.sh" "$PATCH_ENV" --validate

  say "[2/3] 전체 구성 재적용"
  bash "$T/install-elk.sh" "$PATCH_ENV"

  if (( LOGSTASH_WAS_ACTIVE )) && ! systemctl is-active --quiet logstash 2>/dev/null; then
    restore_logstash
  fi

  if [[ -f "$T/check-elk.sh" ]]; then
    say "[3/3] 전체 상태 점검"
    set +e
    bash "$T/check-elk.sh" "$ENVF"
    CHECK_RC=$?
    set -e
    (( CHECK_RC == 0 )) || say "[WARN] 상태 점검에서 확인할 항목이 있습니다. (rc=$CHECK_RC)"
  fi

  FULL_OK=1
  trap cleanup EXIT
else
  if (( ${#CHANGED_RUNTIME[@]} == 0 )); then
    say "[OK] 변경된 런타임 파일이 없습니다."
    say "     install-elk.sh / ELK 패키지 / Logstash 구성 재적용은 수행하지 않았습니다."
  else
    TS="$(date +%Y%m%d-%H%M%S)"
    BKDIR="$BACKUP_ROOT/$TS"
    install -d -m 700 "$BKDIR"

    WEB_CHANGED=0
    REPORT_CHANGED=0
    SELF_UPDATE=0
    APPLIED=0

    say
    say "[적용] 다운로드한 변경 파일만 교체합니다."

    for N in "${CHANGED_RUNTIME[@]}"; do
      DEST="$(target_for "$N")"
      MODE_N="$(mode_for "$N")"

      if [[ "$N" == "elk-oneclick-update.sh" ]]; then
        SELF_UPDATE=1
        continue
      fi

      install -d -m 755 "$(dirname "$DEST")"
      [[ -f "$DEST" ]] && cp -a "$DEST" "$BKDIR/$(basename "$DEST").before"
      install -m "$MODE_N" "$T/$N" "$DEST"

      say "  [UPDATED] $N -> $DEST"
      APPLIED=$((APPLIED+1))

      [[ "$N" == "elk-report-web.py" ]] && WEB_CHANGED=1
      [[ "$N" == "elk-report.sh" ]] && REPORT_CHANGED=1
    done

    if (( WEB_CHANGED )) && command -v systemctl >/dev/null 2>&1; then
      if systemctl is-enabled --quiet elk-report-web.service 2>/dev/null || \
         systemctl is-active --quiet elk-report-web.service 2>/dev/null; then
        say "  [RESTART] elk-report-web.service"
        systemctl restart elk-report-web.service
      fi
    fi

    if (( REPORT_CHANGED )) && [[ -x /usr/local/sbin/elk-report ]]; then
      say "  [REFRESH] ELK 점검 리포트 재생성"
      /usr/local/sbin/elk-report --no-color >/dev/null 2>&1 || true
    fi

    if (( SELF_UPDATE )); then
      DEST="/usr/local/sbin/elk-oneclick-update"
      [[ -f "$DEST" ]] && cp -a "$DEST" "$BKDIR/elk-oneclick-update.before"
      install -m 755 "$T/elk-oneclick-update.sh" "$DEST"
      say "  [UPDATED] elk-oneclick-update.sh -> $DEST"
      APPLIED=$((APPLIED+1))
    fi

    say "  적용 파일 수 : $APPLIED"
    say "  다운로드 수   : ${#DOWNLOAD_NAMES[@]}"
    say "  백업 경로     : $BKDIR"
    say "  install-elk 실행 : 안 함"
    say "  ELK 패키지 재설치 : 안 함"
  fi
fi

# 성공한 적용 뒤 GitHub blob SHA 기준값 갱신.
install -d -m 755 "$(dirname "$REMOTE_MANIFEST")"
{
  for N in "${NAMES[@]}"; do
    printf '%s\t%s\n' "${REMOTE_SHA[$N]}" "$N"
  done
} > "$REMOTE_MANIFEST"
chmod 644 "$REMOTE_MANIFEST"

install -d -m 755 "$(dirname "$RELEASE")"
cat > "$RELEASE" <<META
ONECLICK_VERSION="$LV"
ONECLICK_BUILD="$LB"
ONECLICK_INSTALLED_AT="$(date -Is)"
ONECLICK_UPDATE_MODE="$([[ "$MODE" == "--full" || "$MODE" == "full" ]] && echo full || echo delta-only)"
ONECLICK_DOWNLOADED_FILES="${#DOWNLOAD_NAMES[@]}"
ONECLICK_APPLIED_RUNTIME_FILES="${#CHANGED_RUNTIME[@]}"
META
chmod 644 "$RELEASE"

if [[ "$MODE" == "--full" || "$MODE" == "full" ]]; then
  say "[OK] 전체 구성 재적용 완료: v$LV · build $LB"
else
  say "[OK] delta-only 업데이트 완료: 실제 변경 파일만 반영했습니다. v$LV · build $LB"
fi
