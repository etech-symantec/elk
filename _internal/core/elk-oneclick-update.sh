#!/usr/bin/env bash
# ELK One-Click public GitHub delta-only updater
#
# 기본 동작
#   --check : GitHub 메타데이터만 조회하여 변경 파일 확인. core 파일 다운로드 없음.
#   --apply : 실제로 변경된 런타임 파일만 다운로드 + 교체.
#   --force : 런타임 파일 전체를 다시 다운로드 + 교체.
#   --full  : 최신 런타임 파일 동기화 + install-elk 재적용.
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

MODE="--check"
for _arg in "$@"; do
  case "$_arg" in --color=always|--color=never|--no-color) ;; *) MODE="$_arg"; break ;; esac
done

# ANSI colors: only on an interactive terminal, never in redirected logs or pipes.
UI_COLOR_MODE="${ELK_UPDATE_COLOR:-auto}"
for _arg in "$@"; do
  case "$_arg" in --color=always) UI_COLOR_MODE=always ;; --color=never|--no-color) UI_COLOR_MODE=never ;; esac
done
case "${UI_COLOR_MODE,,}" in
  always) UI_COLOR=1 ;;
  never) UI_COLOR=0 ;;
  *) if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then UI_COLOR=1; else UI_COLOR=0; fi ;;
esac
if (( UI_COLOR )); then
  UI_RESET=$'\033[0m'; UI_BOLD=$'\033[1m'; UI_BLUE=$'\033[1;94m'; UI_CYAN=$'\033[1;96m'
  UI_GREEN=$'\033[1;92m'; UI_YELLOW=$'\033[1;93m'; UI_RED=$'\033[1;91m'; UI_DIM=$'\033[2m'
else
  UI_RESET=''; UI_BOLD=''; UI_BLUE=''; UI_CYAN=''; UI_GREEN=''; UI_YELLOW=''; UI_RED=''; UI_DIM=''
fi
say(){ printf '%s\n' "$*"; }
ui_heading(){ printf '\n%s━━━━━━━━ %s ━━━━━━━━%s\n' "$UI_BLUE" "$*" "$UI_RESET"; }
ui_kv(){ printf '  %s%-19s%s : %s\n' "$UI_DIM" "$1" "$UI_RESET" "$2"; }
ui_info(){ printf '%s[INFO]%s %s\n' "$UI_CYAN" "$UI_RESET" "$*"; }
ui_ok(){ printf '%s[OK]%s %s\n' "$UI_GREEN" "$UI_RESET" "$*"; }
ui_warn(){ printf '%s[WARN]%s %s\n' "$UI_YELLOW" "$UI_RESET" "$*" >&2; }
ui_error(){ printf '%s[ERROR]%s %s\n' "$UI_RED" "$UI_RESET" "$*" >&2; }
die(){ ui_error "$*"; exit 1; }
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
  sudo elk-oneclick-update --full    # 전체 구성 재적용 + 런타임 파일 동기화
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


# 변경 파일의 성격을 분류하여 --apply만으로 충분한지,
# 현재 elk.env를 기준으로 --full 재적용이 필요한지 안내한다.
# 실제 적용 명령은 자동 실행하지 않고 사용자에게 명시적으로 제안만 한다.
impact_for(){
  case "$1" in
    # 실제 Logstash pipeline/filter 재렌더링이 필요한 템플릿.
    proxysg-log-filter.conf)
      printf '%s' "reconcile"
      ;;
    # 설치 엔진에는 Dashboard, Kibana 설정, Logstash 렌더링,
    # installer default 값이 포함될 수 있으므로 전체 재적용을 권장.
    install-elk.sh)
      printf '%s' "full"
      ;;
    # 환경 기본값/설치 도우미 변경 가능성이 높은 소스.
    wizard-defaults.js|config-wizard.html)
      printf '%s' "env-review"
      ;;
    # 런타임 교체만으로 즉시 반영되는 파일.
    check-elk.sh|proxysg-log-process.sh|elk-health-monitor.sh|elk-ops.sh|elk-patch.sh|elk-color.sh|elk-report.sh|elk-report-web.py|elk-tls-lib.sh|proxysg-lib.sh|log-ingest-manager.sh|elk-oneclick-update.sh|elk-oneclick-adopt.sh)
      printf '%s' "runtime"
      ;;
    *)
      printf '%s' "source"
      ;;
  esac
}

impact_text(){
  case "$1" in
    runtime)    printf '%s' "파일 교체만으로 반영 가능" ;;
    reconcile)  printf '%s' "Logstash 설정 재생성 필요 → --full 권장" ;;
    full)        printf '%s' "설치 엔진/대시보드/기본값 변경 가능 → --full 권장" ;;
    env-review)  printf '%s' "기존 elk.env 값은 자동 변경되지 않음 → 설정값 확인 필요" ;;
    *)           printf '%s' "설치 소스 변경 → 필요 시 --full 검토" ;;
  esac
}

env_value_present(){
  local key="$1"
  [[ -r "$ENVF" ]] || return 1
  grep -qE "^${key}=" "$ENVF" 2>/dev/null
}

print_reconcile_advice(){
  local _n _impact
  local _need_full=0 _need_env_review=0 _filter_changed=0 _install_changed=0
  local _runtime_only=1

  for _n in "${CHANGED_RUNTIME[@]}"; do
    _impact="$(impact_for "$_n")"
    [[ "$_impact" == "runtime" ]] || _runtime_only=0
    [[ "$_impact" == "reconcile" ]] && { _need_full=1; _filter_changed=1; }
  done
  for _n in "${CHANGED_SOURCE[@]}"; do
    _impact="$(impact_for "$_n")"
    _runtime_only=0
    [[ "$_impact" == "full" || "$_impact" == "reconcile" ]] && _need_full=1
    [[ "$_impact" == "env-review" || "$_impact" == "full" ]] && _need_env_review=1
    [[ "$_n" == "install-elk.sh" ]] && _install_changed=1
  done

  # install-elk.sh는 target_for 대상이 아니므로 CHANGED_SOURCE에 잡힌다.
  if (( ${#CHANGED_RUNTIME[@]} + ${#CHANGED_SOURCE[@]} == 0 )); then
    say
    ui_heading "적용 권장사항"
    ui_ok "현재 설치 파일과 GitHub 기준이 동일합니다."
    return 0
  fi

  say
  ui_heading "적용 권장사항"
  if (( _runtime_only )); then
    ui_ok "--apply만으로 충분합니다. 추가 구성 재적용이 필요하지 않습니다."
  else
    if (( _filter_changed )); then
      say "    · proxysg-log-filter.conf 변경 감지"
      say "      → /etc/logstash의 실제 pipeline/filter는 --apply만으로 다시 렌더링되지 않습니다."
    fi
    if (( _install_changed )); then
      say "    · install-elk.sh 변경 감지"
      say "      → Dashboard, Kibana 설정, Logstash 렌더링 또는 installer 기본값 변경이 포함될 수 있습니다."
    fi
    if (( _need_env_review )); then
      say "    · 기존 /etc/elk-auto/elk.env의 명시 값은 새 버전의 기본값으로 자동 덮어쓰지 않습니다."
      if env_value_present PROXYSG_CLOUD_LOG_FORMAT; then
        say "      → 현재 PROXYSG_CLOUD_LOG_FORMAT 값이 elk.env에 있으므로 새 기본 포맷 적용 여부를 확인하세요."
      fi
    fi
    if (( _need_full )); then
      say "    · 권장: 필요한 elk.env 값을 먼저 패치/확인한 뒤 아래 명령으로 전체 구성을 재적용하세요."
      say "      ${UI_CYAN}sudo elk-oneclick-update --full${UI_RESET}"
    else
      say "    · 설치 소스 변경이 있으므로 변경 내용을 확인한 뒤 필요할 때만 --full을 사용하세요."
    fi
  fi
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

ui_heading "ELK OneClick 업데이트"
ui_kv "저장소" "https://github.com/$OWNER/$REPO ($BRANCH)"
ui_kv "설치 버전" "${IV:-확인 불가}  ·  ${IB:-빌드 확인 불가}"
ui_kv "GitHub 최신" "${UI_GREEN}v$LV${UI_RESET}  ·  $LB"
ui_kv "실행 모드" "$MODE"
ui_kv "비교 방식" "GitHub blob SHA ↔ 로컬 파일"
ui_heading "변경 파일 분석"

if (( ${#CHANGED_RUNTIME[@]} )); then
  say
  ui_info "런타임 변경: ${#CHANGED_RUNTIME[@]}개"
  for N in "${CHANGED_RUNTIME[@]}"; do
    printf "    %s●%s %s\n" "$UI_GREEN" "$UI_RESET" "$N"
    say "      ↳ $(target_for "$N")"
    say "      ↳ $(impact_text "$(impact_for "$N")")"
  done
else
  say
  ui_ok "런타임 변경 파일 없음"
fi

if (( ${#CHANGED_SOURCE[@]} )); then
  say
  ui_warn "설치 엔진/소스 변경: ${#CHANGED_SOURCE[@]}개 (--apply에서는 미적용)"
  for N in "${CHANGED_SOURCE[@]}"; do
    printf "    %s●%s %s\n" "$UI_YELLOW" "$UI_RESET" "$N"
    say "      ↳ $(impact_text "$(impact_for "$N")")"
  done
  say "    ※ --apply는 런타임 파일만 교체하며 Dashboard/Logstash 재렌더링/installer 기본값은 자동 재적용하지 않습니다."
fi

if (( ${#BASELINE_SOURCE[@]} )); then
  say
  ui_info "소스 비교 기준 최초 등록"
  for N in "${BASELINE_SOURCE[@]}"; do say "    · $N"; done
  say "    ※ 파일 다운로드 없이 GitHub SHA만 기준값으로 등록합니다."
fi

TOTAL_RUNTIME=${#CHANGED_RUNTIME[@]}
TOTAL_SOURCE=${#CHANGED_SOURCE[@]}

print_reconcile_advice

if [[ "$MODE" == "--check" || "$MODE" == "check" || "$MODE" == "--version" ]]; then
  say
  ui_heading "검사 결과"
  ui_kv "Core 다운로드" "0개"
  ui_kv "런타임 변경" "$TOTAL_RUNTIME개"
  ui_kv "소스 변경" "$TOTAL_SOURCE개"
  (( TOTAL_RUNTIME + TOTAL_SOURCE > 0 )) && exit 10 || exit 0
fi

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "적용은 root 권한이 필요합니다. sudo를 사용하세요."
[[ -f "$ENVF" ]] || die "기존 설치 설정을 찾을 수 없습니다: $ENVF"

T="$(mktemp -d /tmp/elk-oneclick-update.XXXXXX)"
cleanup(){ rm -rf "$T"; }
trap cleanup EXIT

download_one(){
  local n="$1"
  ui_info "다운로드: $n"
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
ui_heading "다운로드"
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
      [[ "$ACT" == "$EXP" ]] || { ui_error "SHA256 불일치: $N"; bad=1; }
    done
    (( bad == 0 )) || die "파일 무결성 검증에 실패했습니다."
  else
    ui_warn "SHA256SUMS.txt를 읽지 못해 다운로드 파일 검증을 생략합니다."
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

  ui_heading "[1/3] 최신 설치기 검증"
  bash "$T/install-elk.sh" "$PATCH_ENV" --validate

  ui_heading "[2/3] 전체 구성 재적용"
  bash "$T/install-elk.sh" "$PATCH_ENV"

  if (( LOGSTASH_WAS_ACTIVE )) && ! systemctl is-active --quiet logstash 2>/dev/null; then
    restore_logstash
  fi

  if [[ -f "$T/check-elk.sh" ]]; then
    ui_heading "[3/3] 전체 상태 점검"
    set +e
    bash "$T/check-elk.sh" "$ENVF"
    CHECK_RC=$?
    set -e
    (( CHECK_RC == 0 )) || ui_warn "상태 점검에서 확인할 항목이 있습니다. (rc=$CHECK_RC)"
  fi

  # install-elk.sh 재적용은 일부 런타임 도구를 관리하지 않을 수 있습니다.
  # 따라서 전체 재적용 성공 이후, 이번에 내려받은 GitHub core 중 실제로
  # 변경된 런타임 파일들을 직접 동기화합니다. updater 자신은 마지막에 교체합니다.
  ui_heading "[4/4] 런타임 도구 동기화"
  TS="$(date +%Y%m%d-%H%M%S)"
  BKDIR="$BACKUP_ROOT/$TS"
  install -d -m 700 "$BKDIR"
  WEB_CHANGED=0; REPORT_CHANGED=0; SELF_UPDATE=0; APPLIED=0
  for N in "${CHANGED_RUNTIME[@]}"; do
    DEST="$(target_for "$N")" || die "대상 경로를 찾을 수 없습니다: $N"
    MODE_N="$(mode_for "$N")"
    [[ -f "$T/$N" ]] || die "다운로드된 런타임 파일 없음: $N"
    if [[ "$N" == "elk-oneclick-update.sh" ]]; then
      SELF_UPDATE=1
      continue
    fi
    # 설치기가 이미 최신 내용으로 갱신한 파일은 중복 교체하지 않습니다.
    if [[ -f "$DEST" ]] && cmp -s "$T/$N" "$DEST"; then
      ui_ok "이미 최신: $N"
      continue
    fi
    install -d -m 755 "$(dirname "$DEST")"
    [[ -f "$DEST" ]] && cp -a "$DEST" "$BKDIR/$(basename "$DEST").before"
    install -m "$MODE_N" "$T/$N" "$DEST"
    ui_ok "도구 갱신: $N → $DEST"
    APPLIED=$((APPLIED+1))
    [[ "$N" == "elk-report-web.py" ]] && WEB_CHANGED=1
    [[ "$N" == "elk-report.sh" ]] && REPORT_CHANGED=1
  done
  if (( WEB_CHANGED )) && command -v systemctl >/dev/null 2>&1; then
    if systemctl is-enabled --quiet elk-report-web.service 2>/dev/null || \
       systemctl is-active --quiet elk-report-web.service 2>/dev/null; then
      ui_info "리포트 웹 서비스 재시작"
      systemctl restart elk-report-web.service
    fi
  fi
  if (( REPORT_CHANGED )) && [[ -x /usr/local/sbin/elk-report ]]; then
    ui_info "ELK 점검 리포트 재생성"
    /usr/local/sbin/elk-report --no-color >/dev/null 2>&1 || ui_warn "리포트 재생성을 확인해 주세요."
  fi
  if (( SELF_UPDATE )); then
    DEST="/usr/local/sbin/elk-oneclick-update"
    if [[ -f "$DEST" ]] && cmp -s "$T/elk-oneclick-update.sh" "$DEST"; then
      ui_ok "업데이터 이미 최신"
    else
      [[ -f "$DEST" ]] && cp -a "$DEST" "$BKDIR/elk-oneclick-update.before"
      install -m 755 "$T/elk-oneclick-update.sh" "$DEST"
      ui_ok "업데이터 자체 갱신(마지막): $DEST"
      APPLIED=$((APPLIED+1))
    fi
  fi
  ui_ok "전체 재적용 및 런타임 동기화 완료 (교체 ${APPLIED}개)"
  say "  런타임 백업: $BKDIR"

  FULL_OK=1
  trap cleanup EXIT
else
  if (( ${#CHANGED_RUNTIME[@]} == 0 )); then
    ui_ok "변경된 런타임 파일이 없습니다."
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
    ui_heading "변경 파일 적용"

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

      ui_ok "교체 완료: $N → $DEST"
      APPLIED=$((APPLIED+1))

      [[ "$N" == "elk-report-web.py" ]] && WEB_CHANGED=1
      [[ "$N" == "elk-report.sh" ]] && REPORT_CHANGED=1
    done

    if (( WEB_CHANGED )) && command -v systemctl >/dev/null 2>&1; then
      if systemctl is-enabled --quiet elk-report-web.service 2>/dev/null || \
         systemctl is-active --quiet elk-report-web.service 2>/dev/null; then
        ui_info "리포트 웹 서비스 재시작"
        systemctl restart elk-report-web.service
      fi
    fi

    if (( REPORT_CHANGED )) && [[ -x /usr/local/sbin/elk-report ]]; then
      ui_info "ELK 점검 리포트 재생성"
      /usr/local/sbin/elk-report --no-color >/dev/null 2>&1 || true
    fi

    if (( SELF_UPDATE )); then
      DEST="/usr/local/sbin/elk-oneclick-update"
      [[ -f "$DEST" ]] && cp -a "$DEST" "$BKDIR/elk-oneclick-update.before"
      install -m 755 "$T/elk-oneclick-update.sh" "$DEST"
      ui_ok "업데이터 자체 갱신: $DEST"
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
ONECLICK_APPLIED_RUNTIME_FILES="${APPLIED:-0}"
META
chmod 644 "$RELEASE"

if [[ "$MODE" == "--full" || "$MODE" == "full" ]]; then
  ui_ok "전체 구성 및 런타임 파일 갱신 완료: v$LV · build $LB"
  say "     Dashboard / Logstash 렌더링 / Kibana 설정은 현재 elk.env 기준으로 재적용되었습니다."
else
  ui_ok "차등 업데이트 완료: v$LV · build $LB"
  say
  ui_heading "다음 단계"
  _NEXT_FULL=0
  for N in "${CHANGED_RUNTIME[@]}" "${CHANGED_SOURCE[@]}"; do
    [[ -n "$N" ]] || continue
    case "$(impact_for "$N")" in
      full|reconcile) _NEXT_FULL=1 ;;
    esac
  done
  if (( _NEXT_FULL )); then
    say "  이번 변경에는 구성 재생성이 필요한 항목이 포함되어 있습니다."
    say "  1) /etc/elk-auto/elk.env의 기본값 변경 필요 여부를 확인/패치"
    say "  2) sudo elk-oneclick-update --full"
    say "  ※ --full은 현재 elk.env를 기준으로 Dashboard, Kibana 설정, Logstash 구성을 다시 생성합니다."
  else
    say "  런타임 파일 업데이트만으로 반영 완료되었습니다. --full은 필요하지 않습니다."
  fi
fi
