#!/usr/bin/env bash
# Bootstrap GitHub updater onto an existing / legacy ELK One-Click installation.
set -Eeuo pipefail

OWNER="${ELK_ONECLICK_GITHUB_OWNER:etech-symantec}"
REPO="${ELK_ONECLICK_GITHUB_REPO:elk}"
BRANCH="${ELK_ONECLICK_GITHUB_BRANCH:main}"
ENVF="${ELK_ENV_FILE:-/etc/elk-auto/elk.env}"
RELEASE="${ELK_ONECLICK_RELEASE_FILE:-/etc/elk-auto/oneclick-release.env}"
BIN="${ELK_ONECLICK_UPDATE_BIN:-/usr/local/sbin/elk-oneclick-update}"
APPLY=0

usage(){
  cat <<'EOF'
사용:
  sudo bash bootstrap-update.sh --repo OWNER/REPO [--branch main] [--apply]

옵션:
  --repo OWNER/REPO   public GitHub repository
  --branch NAME       branch (기본 main)
  --apply             Bootstrap 완료 후 최신 버전까지 자동 적용
  --check             Bootstrap만 설치하고 최신 버전 비교 (기본)
EOF
}

while (($#)); do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      OWNER="${2%%/*}"; REPO="${2#*/}"; shift 2 ;;
    --branch)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      BRANCH="$2"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --check) APPLY=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[ERROR] 알 수 없는 옵션: $1" >&2; usage; exit 2 ;;
  esac
done

say(){ printf '%s\n' "$*"; }
die(){ say "[ERROR] $*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "$1 명령이 필요합니다."; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "root 권한이 필요합니다. sudo를 사용하세요."
need curl
need grep
need awk
need sed

[[ "$OWNER" != CHANGE_ME_* && "$REPO" != CHANGE_ME_* ]] || \
  die "--repo OWNER/REPO 를 지정하세요."
[[ "$OWNER" =~ ^[A-Za-z0-9_.-]+$ && "$REPO" =~ ^[A-Za-z0-9_.-]+$ && "$BRANCH" =~ ^[A-Za-z0-9_./-]+$ ]] || \
  die "GitHub owner/repo/branch 형식이 올바르지 않습니다."
[[ -f "$ENVF" ]] || die "기존 ELK 설정을 찾을 수 없습니다: $ENVF"

RAW="https://raw.githubusercontent.com/$OWNER/$REPO/$BRANCH"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ENVF}.before-bootstrap-${TS}"

say "ELK One-Click Legacy Bootstrap"
say "  저장소    : https://github.com/$OWNER/$REPO ($BRANCH)"
say "  기존 설정 : $ENVF"

# 1) Backup existing config before touching it.
cp -a "$ENVF" "$BACKUP"
say "[OK] 기존 설정 백업: $BACKUP"

# 2) Legacy migration: append modern aliases, never delete the old keys.
#    Mirrors Config Wizard's legacy conversion rules.
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
cp -a "$ENVF" "$TMP"

has_key(){ grep -qE "^${1}=" "$TMP"; }
get_raw_value(){ grep -E "^${1}=" "$TMP" | tail -1 | cut -d= -f2-; }
append_alias(){
  local old="$1" new="$2" val
  has_key "$old" || return 0
  has_key "$new" && return 0
  val="$(get_raw_value "$old")"
  printf '\n# Legacy migration: %s -> %s\n%s=%s\n' "$old" "$new" "$new" "$val" >> "$TMP"
  say "  migration: $old -> $new"
}

LEGACY=0
if grep -qE '^GUIDE_[A-Z0-9_]+=' "$TMP"; then
  LEGACY=1
  while IFS='=' read -r key _; do
    [[ "$key" =~ ^GUIDE_[A-Z0-9_]+$ ]] || continue
    case "$key" in
      GUIDE_PROXY_FLOW_ENABLED) new="PROXYSG_FLOW_ENABLED" ;;
      GUIDE_PROXY_CSV_FILTER_ENABLED) new="PROXYSG_CSV_FILTER_ENABLED" ;;
      *) new="PROXYSG_${key#GUIDE_}" ;;
    esac
    append_alias "$key" "$new"
  done < <(grep -E '^GUIDE_[A-Z0-9_]+=' "$TMP")
fi

# Known legacy value translations.
if grep -qE '^LOGSTASH_PROFILE="?proxysg_guide"?$' "$TMP"; then
  sed -i -E 's/^LOGSTASH_PROFILE="?proxysg_guide"?$/LOGSTASH_PROFILE="proxysg"/' "$TMP"
  say "  migration: LOGSTASH_PROFILE proxysg_guide -> proxysg"
  LEGACY=1
fi
if grep -qE '^PROXYSG_PROCESS_SCRIPT="?/usr/local/sbin/elk-guide-log-process"?$' "$TMP"; then
  sed -i -E 's#^PROXYSG_PROCESS_SCRIPT=.*#PROXYSG_PROCESS_SCRIPT="/usr/local/sbin/elk-proxysg-log-process"#' "$TMP"
  LEGACY=1
fi
if grep -qE '^PROXYSG_PROCESS_LOG="?/var/log/elk-guide-log-process.log"?$' "$TMP"; then
  sed -i -E 's#^PROXYSG_PROCESS_LOG=.*#PROXYSG_PROCESS_LOG="/var/log/elk-proxysg-log-process.log"#' "$TMP"
  LEGACY=1
fi

if (( LEGACY )); then
  install -m 600 "$TMP" "$ENVF"
  say "[OK] Legacy 설정 호환 alias를 추가했습니다. 기존 GUIDE_* 항목은 삭제하지 않았습니다."
else
  say "[INFO] GUIDE_* Legacy 설정은 발견되지 않았습니다."
fi

# 3) Download updater from the public repo.
UPD_URL="$RAW/_internal/core/elk-oneclick-update.sh"
say "[INFO] updater 다운로드: $UPD_URL"
curl -fsSL --connect-timeout 10 --max-time 120 "$UPD_URL" -o "${BIN}.new" || \
  die "elk-oneclick-update.sh 다운로드에 실패했습니다."
bash -n "${BIN}.new" || { rm -f "${BIN}.new"; die "다운로드한 updater의 shell 문법 검증에 실패했습니다."; }
sed -i \
  -e "s|CHANGE_ME_OWNER|$OWNER|g" \
  -e "s|CHANGE_ME_REPO|$REPO|g" \
  -e "s|^BRANCH=.*|BRANCH=\"\${ELK_ONECLICK_GITHUB_BRANCH:-$BRANCH}\"|" \
  "${BIN}.new"
install -m 755 "${BIN}.new" "$BIN"
rm -f "${BIN}.new"
say "[OK] 설치: $BIN"

# 4) Create version metadata for old installs only if it does not already exist.
if [[ ! -f "$RELEASE" ]]; then
  DETECTED=""
  if [[ -f /var/log/elk-auto-install.log ]]; then
    DETECTED="$(grep -Eo 'ELK One-Click Installer v[0-9]+([.][0-9]+)+' /var/log/elk-auto-install.log 2>/dev/null | tail -1 | sed -E 's/.* v//' || true)"
  fi
  [[ -n "$DETECTED" ]] || DETECTED="0.0.0-legacy"
  install -d -m 755 "$(dirname "$RELEASE")"
  cat > "$RELEASE" <<META
ONECLICK_VERSION="$DETECTED"
ONECLICK_BUILD="legacy-bootstrap"
ONECLICK_INSTALLED_AT=""
META
  chmod 644 "$RELEASE"
  say "[OK] Legacy 버전 메타데이터 생성: $DETECTED"
else
  say "[INFO] 기존 버전 메타데이터 유지: $RELEASE"
fi

say
say "[OK] Bootstrap 완료"
say "  버전 확인 : sudo elk-oneclick-update --check"
say "  자동 패치 : sudo elk-oneclick-update --apply"
say "  설정 복구 : cp '$BACKUP' '$ENVF'"

if (( APPLY )); then
  say
  say "[INFO] --apply가 지정되어 최신 버전 적용을 시작합니다."
  exec "$BIN" --apply
else
  say
  set +e
  "$BIN" --check
  rc=$?
  set -e
  # updater returns 10 when an update is available; bootstrap itself still succeeded.
  [[ $rc -eq 0 || $rc -eq 10 ]] || exit "$rc"
fi
