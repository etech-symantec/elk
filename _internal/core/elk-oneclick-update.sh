#!/usr/bin/env bash
# ELK One-Click public GitHub incremental updater
# 기본 --apply는 "변경된 런타임 파일만" 교체합니다.
# 전체 install-elk 재적용은 명시적으로 --full 을 사용해야 합니다.
set -Eeuo pipefail

OWNER="${ELK_ONECLICK_GITHUB_OWNER:-etech-symantec}"
REPO="${ELK_ONECLICK_GITHUB_REPO:-elk}"
BRANCH="${ELK_ONECLICK_GITHUB_BRANCH:-main}"
ENVF="${ELK_ENV_FILE:-/etc/elk-auto/elk.env}"
RELEASE="${ELK_ONECLICK_RELEASE_FILE:-/etc/elk-auto/oneclick-release.env}"
MANIFEST="${ELK_ONECLICK_MANIFEST_FILE:-/etc/elk-auto/oneclick-files.sha256}"
CACHE_DIR="${ELK_ONECLICK_CACHE_DIR:-/usr/local/lib/elk-auto/update-cache/core}"
BACKUP_ROOT="${ELK_ONECLICK_BACKUP_DIR:-/var/backups/elk-oneclick}"
MODE="${1:---check}"

say(){ printf '%s\n' "$*"; }
die(){ say "[ERROR] $*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "$1 명령이 필요합니다."; }

need curl
need jq
need sha256sum
need sort
need cmp

[[ "$OWNER" != CHANGE_ME_* && "$REPO" != CHANGE_ME_* ]] || \
  die "GitHub 저장소가 설정되지 않았습니다. ELK_ONECLICK_GITHUB_OWNER/REPO를 지정하세요."

case "$MODE" in
  --check|check|--version|--apply|apply|--force|--full|full) ;;
  *)
    say "사용:"
    say "  sudo elk-oneclick-update --check   # 변경 파일 확인"
    say "  sudo elk-oneclick-update --apply   # 변경된 파일만 업데이트 (기본)"
    say "  sudo elk-oneclick-update --force   # 런타임 파일 전체 재복사"
    say "  sudo elk-oneclick-update --full    # 전체 install-elk 재적용"
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

# 기존 설정은 "읽기만" 해서 런타임 스크립트 경로를 알아냅니다.
PROXYSG_PROCESS_SCRIPT_CURRENT="/usr/local/sbin/elk-proxysg-log-process"
if [[ -r "$ENVF" ]]; then
  set +u
  # shellcheck disable=SC1090
  source "$ENVF" 2>/dev/null || true
  set -u
  PROXYSG_PROCESS_SCRIPT_CURRENT="${PROXYSG_PROCESS_SCRIPT:-$PROXYSG_PROCESS_SCRIPT_CURRENT}"
fi

# GitHub core 파일 -> 실제 서버에서 동작 중인 파일
# install-elk.sh 자체는 설치 엔진이므로 기본 incremental 모드에서는 실행하지 않습니다.
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
    *)                         return 1 ;;
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

WIZ="$(GET "$RAW/config-wizard.html")" || die "config-wizard.html을 읽지 못했습니다."
LB="$(grep -oE "WIZARD_BUILD=['\"][^'\"]+" <<<"$WIZ" | head -1 | sed -E "s/.*['\"]//")"
[[ -n "$LB" ]] || LB="unknown"

C=-1
if [[ "$IV" =~ ^[0-9]+([.][0-9]+)*([._-][A-Za-z0-9.-]+)?$ ]]; then
  C="$(cmpver "$IV" "$LV")"
fi
if [[ "$C" == 1 && "$MODE" != "--force" ]]; then
  die "설치된 v$IV가 GitHub v$LV보다 새 버전입니다. 자동 다운그레이드는 차단합니다."
fi

T="$(mktemp -d /tmp/elk-oneclick-update.XXXXXX)"
cleanup(){ rm -rf "$T"; }
trap cleanup EXIT

LIST="$(GET "$API")" || die "GitHub _internal/core 파일 목록을 가져오지 못했습니다."
jq -e 'type=="array"' >/dev/null <<<"$LIST" || \
  die "GitHub API 응답 형식이 올바르지 않습니다. API rate limit도 확인하세요."

mapfile -t NAMES < <(jq -r '.[]|select(.type=="file")|.name' <<<"$LIST" | sort)
(( ${#NAMES[@]} > 0 )) || die "_internal/core 파일 목록이 비어 있습니다."

for N in "${NAMES[@]}"; do
  [[ "$N" =~ ^[A-Za-z0-9._-]+$ ]] || die "잘못된 파일명: $N"
  curl -fsSL --connect-timeout 10 --max-time 120 \
    "$RAW/_internal/core/$N" -o "$T/$N" || die "다운로드 실패: $N"
done

SUMS="$(GET "$RAW/SHA256SUMS.txt" 2>/dev/null || true)"
if [[ -n "$SUMS" ]]; then
  bad=0
  for N in "${NAMES[@]}"; do
    EXP="$(awk -v p="_internal/core/$N" '$2==p{print $1}' <<<"$SUMS" | tail -1)"
    [[ -z "$EXP" ]] && continue
    ACT="$(sha256sum "$T/$N" | awk '{print $1}')"
    [[ "$ACT" == "$EXP" ]] || { say "[ERROR] SHA256 불일치: $N"; bad=1; }
  done
  (( bad == 0 )) || die "파일 무결성 검증에 실패했습니다."
else
  say "[WARN] SHA256SUMS.txt를 읽지 못해 repository hash 검증을 생략합니다."
fi

# 변경 판정:
# 1) 실제 런타임 대상이 있는 파일은 서버의 실제 파일과 직접 비교
# 2) 설치 엔진/비런타임 파일은 지난 업데이트 때 저장한 cache와 비교
declare -a CHANGED_RUNTIME=()
declare -a CHANGED_SOURCE=()
declare -a SAME_RUNTIME=()
declare -a BASELINE_SOURCE=()

for N in "${NAMES[@]}"; do
  if DEST="$(target_for "$N" 2>/dev/null)"; then
    if [[ "$MODE" == "--force" ]]; then
      CHANGED_RUNTIME+=("$N")
    elif [[ ! -f "$DEST" ]] || ! cmp -s "$T/$N" "$DEST"; then
      CHANGED_RUNTIME+=("$N")
    else
      SAME_RUNTIME+=("$N")
    fi
  else
    if [[ -f "$CACHE_DIR/$N" ]]; then
      if ! cmp -s "$T/$N" "$CACHE_DIR/$N"; then
        CHANGED_SOURCE+=("$N")
      fi
    else
      BASELINE_SOURCE+=("$N")
    fi
  fi
done

say "ELK One-Click GitHub 업데이트 확인"
say "  저장소       : https://github.com/$OWNER/$REPO ($BRANCH)"
say "  설치 버전    : ${IV:-확인 불가}"
say "  설치 빌드    : ${IB:-확인 불가}"
say "  GitHub 버전  : $LV"
say "  GitHub 빌드  : $LB"
say "  업데이트 방식: 변경 파일만 교체 (incremental)"

if (( ${#CHANGED_RUNTIME[@]} )); then
  say
  say "  [변경된 런타임 파일]"
  for N in "${CHANGED_RUNTIME[@]}"; do
    DEST="$(target_for "$N")"
    say "    · $N  ->  $DEST"
  done
fi

if (( ${#CHANGED_SOURCE[@]} )); then
  say
  say "  [설치 엔진/소스 변경]"
  for N in "${CHANGED_SOURCE[@]}"; do
    say "    · $N"
  done
  say "    ※ 기본 --apply에서는 실행하지 않고 최신 소스만 보관합니다."
  say "       현재 ELK 구성을 전체 재적용하려면 --full을 사용하세요."
fi

if (( ${#BASELINE_SOURCE[@]} )); then
  say
  say "  [최초 기준 등록]"
  for N in "${BASELINE_SOURCE[@]}"; do say "    · $N"; done
  say "    ※ 런타임 파일이 아닌 항목은 이번 실행에서 비교 기준만 저장합니다."
fi

TOTAL_CHANGED=$(( ${#CHANGED_RUNTIME[@]} + ${#CHANGED_SOURCE[@]} ))
if (( TOTAL_CHANGED == 0 )); then
  say "  상태         : 변경된 런타임 파일 없음"
else
  say "  상태         : 변경 ${TOTAL_CHANGED}개"
fi

if [[ "$MODE" == "--check" || "$MODE" == "check" || "$MODE" == "--version" ]]; then
  (( TOTAL_CHANGED > 0 )) && exit 10 || exit 0
fi

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "적용은 root 권한이 필요합니다. sudo를 사용하세요."
[[ -f "$ENVF" ]] || die "기존 설치 설정을 찾을 수 없습니다: $ENVF"

# --full은 예전 방식의 전체 reconcile을 명시적으로 요청했을 때만 수행
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
  # 기본 incremental 적용
  if (( ${#CHANGED_RUNTIME[@]} == 0 && ${#CHANGED_SOURCE[@]} == 0 && ${#BASELINE_SOURCE[@]} == 0 )); then
    say "[OK] 이미 최신 파일 상태입니다. ELK 재설치는 수행하지 않았습니다."
    exit 0
  fi

  TS="$(date +%Y%m%d-%H%M%S)"
  BKDIR="$BACKUP_ROOT/$TS"
  install -d -m 700 "$BKDIR"

  WEB_CHANGED=0
  REPORT_CHANGED=0
  SELF_UPDATE=0
  APPLIED=0

  say
  say "[적용] 변경된 파일만 교체합니다."
  for N in "${CHANGED_RUNTIME[@]}"; do
    DEST="$(target_for "$N")"
    MODE_N="$(mode_for "$N")"

    # 실행 중인 updater는 마지막에 자기 자신을 교체
    if [[ "$N" == "elk-oneclick-update.sh" ]]; then
      SELF_UPDATE=1
      continue
    fi

    install -d -m 755 "$(dirname "$DEST")"
    if [[ -f "$DEST" ]]; then
      cp -a "$DEST" "$BKDIR/$(basename "$DEST").before"
    fi
    install -m "$MODE_N" "$T/$N" "$DEST"
    say "  [UPDATED] $N -> $DEST"
    APPLIED=$((APPLIED+1))

    [[ "$N" == "elk-report-web.py" ]] && WEB_CHANGED=1
    [[ "$N" == "elk-report.sh" ]] && REPORT_CHANGED=1
  done

  # 점검 웹 Python만 바뀐 경우 해당 서비스만 재시작
  if (( WEB_CHANGED )) && command -v systemctl >/dev/null 2>&1; then
    if systemctl is-enabled --quiet elk-report-web.service 2>/dev/null || \
       systemctl is-active --quiet elk-report-web.service 2>/dev/null; then
      say "  [RESTART] elk-report-web.service"
      systemctl restart elk-report-web.service
    fi
  fi

  # report 스크립트가 바뀌었으면 최신 HTML을 한 번 생성
  if (( REPORT_CHANGED )) && [[ -x /usr/local/sbin/elk-report ]]; then
    say "  [REFRESH] ELK 점검 리포트 재생성"
    /usr/local/sbin/elk-report --no-color >/dev/null 2>&1 || true
  fi

  # updater 자기 자신은 모든 작업이 끝난 후 교체
  if (( SELF_UPDATE )); then
    DEST="/usr/local/sbin/elk-oneclick-update"
    [[ -f "$DEST" ]] && cp -a "$DEST" "$BKDIR/elk-oneclick-update.before"
    install -m 755 "$T/elk-oneclick-update.sh" "$DEST"
    say "  [UPDATED] elk-oneclick-update.sh -> $DEST"
    APPLIED=$((APPLIED+1))
  fi

  say "  적용 파일 수 : $APPLIED"
  say "  백업 경로    : $BKDIR"
  say "  ELK 패키지 재설치/재구성 : 수행하지 않음"
fi

# GitHub core 원본을 다음 변경 비교 기준으로 저장
install -d -m 755 "$CACHE_DIR"
for N in "${NAMES[@]}"; do
  install -m "$(mode_for "$N")" "$T/$N" "$CACHE_DIR/$N"
done

# 원격 core 전체 hash manifest 기록
install -d -m 755 "$(dirname "$MANIFEST")"
: > "$MANIFEST"
for N in "${NAMES[@]}"; do
  H="$(sha256sum "$T/$N" | awk '{print $1}')"
  printf '%s  %s\n' "$H" "_internal/core/$N" >> "$MANIFEST"
done
chmod 644 "$MANIFEST"

install -d -m 755 "$(dirname "$RELEASE")"
cat > "$RELEASE" <<META
ONECLICK_VERSION="$LV"
ONECLICK_BUILD="$LB"
ONECLICK_INSTALLED_AT="$(date -Is)"
ONECLICK_UPDATE_MODE="$([[ "$MODE" == "--full" || "$MODE" == "full" ]] && echo full || echo incremental)"
META
chmod 644 "$RELEASE"

if [[ "$MODE" == "--full" || "$MODE" == "full" ]]; then
  say "[OK] 전체 구성 재적용 완료: v$LV · build $LB"
else
  say "[OK] 증분 업데이트 완료: 변경된 파일만 반영했습니다. v$LV · build $LB"
fi
