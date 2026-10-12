#!/usr/bin/env bash
# ELK One-Click public GitHub updater
set -Eeuo pipefail

OWNER="${ELK_ONECLICK_GITHUB_OWNER:-etech-symantec}"
REPO="${ELK_ONECLICK_GITHUB_REPO:-elk}"
BRANCH="${ELK_ONECLICK_GITHUB_BRANCH:-main}"
ENVF="${ELK_ENV_FILE:-/etc/elk-auto/elk.env}"
RELEASE="${ELK_ONECLICK_RELEASE_FILE:-/etc/elk-auto/oneclick-release.env}"
MODE="${1:---check}"

say(){ printf '%s\n' "$*"; }
die(){ say "[ERROR] $*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "$1 명령이 필요합니다."; }

need curl
need jq
need sha256sum
need sort

[[ "$OWNER" != CHANGE_ME_* && "$REPO" != CHANGE_ME_* ]] || \
  die "GitHub 저장소가 설정되지 않았습니다. ELK_ONECLICK_GITHUB_OWNER/REPO를 지정하세요."

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

say "ELK One-Click GitHub 업데이트 확인"
say "  저장소    : https://github.com/$OWNER/$REPO ($BRANCH)"
say "  설치 버전 : ${IV:-확인 불가}"
say "  설치 빌드 : ${IB:-확인 불가}"
say "  최신 버전 : $LV"
say "  최신 빌드 : $LB"

C=-1
if [[ "$IV" =~ ^[0-9]+([.][0-9]+)*([._-][A-Za-z0-9.-]+)?$ ]]; then
  C="$(cmpver "$IV" "$LV")"
fi

if [[ "$C" == 0 && "${IB:-}" == "$LB" ]]; then
  say "  상태      : 최신 버전"
  [[ "$MODE" != "--force" ]] && exit 0
fi
if [[ "$C" == 1 ]]; then
  die "설치된 v$IV가 GitHub v$LV보다 새 버전입니다. 자동 다운그레이드는 차단합니다."
fi
if [[ "$MODE" == "--check" || "$MODE" == "check" || "$MODE" == "--version" ]]; then
  say "  상태      : 업데이트 가능"
  exit 10
fi

[[ "$MODE" == "--apply" || "$MODE" == "apply" || "$MODE" == "--force" ]] || {
  say "사용: sudo elk-oneclick-update --check | --apply | --force"
  exit 2
}
[[ ${EUID:-$(id -u)} -eq 0 ]] || die "적용은 root 권한이 필요합니다. sudo를 사용하세요."
[[ -f "$ENVF" ]] || die "기존 설치 설정을 찾을 수 없습니다: $ENVF"

LIST="$(GET "$API")" || die "GitHub _internal/core 파일 목록을 가져오지 못했습니다."
jq -e 'type=="array"' >/dev/null <<<"$LIST" || \
  die "GitHub API 응답 형식이 올바르지 않습니다. API rate limit도 확인하세요."

T="$(mktemp -d /tmp/elk-oneclick-update.XXXXXX)"
mapfile -t NAMES < <(jq -r '.[]|select(.type=="file")|.name' <<<"$LIST" | sort)
(( ${#NAMES[@]} > 0 )) || die "_internal/core 파일 목록이 비어 있습니다."

for N in "${NAMES[@]}"; do
  [[ "$N" =~ ^[A-Za-z0-9._-]+$ ]] || die "잘못된 파일명: $N"
  say "  다운로드: $N"
  curl -fsSL --connect-timeout 10 --max-time 120 \
    "$RAW/_internal/core/$N" -o "$T/$N" || die "다운로드 실패: $N"
done

[[ -f "$T/install-elk.sh" ]] || die "업데이트에 install-elk.sh가 없습니다."

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
  say "[WARN] SHA256SUMS.txt를 읽지 못해 hash 검증을 생략합니다."
fi

BK="${ENVF}.before-github-update-${LV}-$(date +%Y%m%d-%H%M%S)"
cp -a "$ENVF" "$BK"
say "  설정 백업: $BK"

# Logstash가 실행 중이면 persistent queue의 .lock을 잡고 있으므로
# 최신 install-elk.sh의 config.test_and_exit가 LockException으로 실패할 수 있다.
# 패치 직전에만 중지하고, 성공/실패와 관계없이 원래 실행 상태를 복원한다.
LOGSTASH_WAS_ACTIVE=0
restore_logstash(){
  if (( LOGSTASH_WAS_ACTIVE )); then
    say "[INFO] Logstash 서비스를 다시 시작합니다."
    systemctl start logstash >/dev/null 2>&1 || true
  fi
}
if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet logstash 2>/dev/null; then
  LOGSTASH_WAS_ACTIVE=1
  say "[INFO] Logstash 설정 검증을 위해 서비스를 잠시 중지합니다. (persistent queue lock 해제)"
  systemctl stop logstash
  for _i in {1..30}; do
    systemctl is-active --quiet logstash 2>/dev/null || break
    sleep 1
  done
  if systemctl is-active --quiet logstash 2>/dev/null; then
    die "Logstash 서비스가 30초 안에 중지되지 않았습니다. 패치를 중단합니다."
  fi
fi

PATCH_OK=0
trap 'rc=$?; if (( PATCH_OK == 0 )); then restore_logstash; fi; rm -rf "$T"; exit $rc' EXIT

say "[1/3] 최신 설치기 검증"
if ! bash "$T/install-elk.sh" "$ENVF" --validate; then
  say "[ERROR] 최신 설치기 검증 실패. 기존 설정은 백업되어 있으며 Logstash는 원래 상태로 복원합니다."
  exit 1
fi

say "[2/3] 최신 구성 적용"
if ! bash "$T/install-elk.sh" "$ENVF"; then
  say "[ERROR] 최신 구성 적용 실패. Logstash를 원래 실행 상태로 복원합니다."
  exit 1
fi

# 설치기가 Logstash를 시작했을 수 있으므로 상태 확인 후 필요할 때만 복원
if (( LOGSTASH_WAS_ACTIVE )) && ! systemctl is-active --quiet logstash 2>/dev/null; then
  restore_logstash
fi

sleep 5
if [[ -f "$T/check-elk.sh" ]]; then
  say "[3/3] 전체 상태 점검"
  bash "$T/check-elk.sh" "$ENVF"
fi
PATCH_OK=1

install -d -m 755 "$(dirname "$RELEASE")"
cat > "$RELEASE" <<META
ONECLICK_VERSION="$LV"
ONECLICK_BUILD="$LB"
ONECLICK_INSTALLED_AT="$(date -Is)"
META
chmod 644 "$RELEASE"

say "[OK] GitHub 온라인 자동 패치 완료: v$LV · build $LB"
