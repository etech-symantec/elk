#!/usr/bin/env bash
set -Eeuo pipefail
# ELK OneClick - Elastic Stack package upgrade helper (no Ubuntu release upgrades).
# Fix: validate installed major versions independently, allowing Debian epoch (1:) and revision (-1).
usage(){ cat <<'HELP'
Usage:
  sudo bash elk-stack-upgrade.sh --check
  sudo bash elk-stack-upgrade.sh --plan VERSION
  sudo bash elk-stack-upgrade.sh --upgrade VERSION [--yes] [--refresh]
  sudo bash elk-stack-upgrade.sh --upgrade latest --yes --refresh
Examples: --plan 9.5.5 / --plan latest / --upgrade 9.5.5
Installed OneClick command: sudo elk-stack-upgrade --plan 9.5.5
Only upgrades the installed Elasticsearch/Kibana/Logstash packages. Never upgrades Ubuntu OS.
HELP
}
TOOL_VERSION='styled-2026.10'
# Only terminal output uses colors; pipe/CI/log output is plain text.
UI_COLOR_MODE="${ELK_UPGRADE_COLOR:-auto}"
case "$UI_COLOR_MODE" in
  always) UI_ENABLED=true ;;
  never) UI_ENABLED=false ;;
  auto) if [[ -t 1 && "${TERM:-dumb}" != dumb && -z "${NO_COLOR:-}" ]]; then UI_ENABLED=true; else UI_ENABLED=false; fi ;;
  *) UI_ENABLED=false ;;
esac
C_RESET='' C_BOLD='' C_DIM='' C_BLUE='' C_GREEN='' C_YELLOW='' C_RED='' C_CYAN='' C_PURPLE=''
if $UI_ENABLED; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_BLUE=$'\033[38;5;75m'; C_GREEN=$'\033[38;5;78m'; C_YELLOW=$'\033[38;5;220m'
  C_RED=$'\033[38;5;203m'; C_CYAN=$'\033[38;5;51m'; C_PURPLE=$'\033[38;5;141m'
fi
ui_line(){ printf '%s────────────────────────────────────────────────────────────────────%s\n' "$C_DIM" "$C_RESET"; }
ui_header(){
  printf '\n%s%s╭──────────────────────────────────────────────────────────────────╮%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  printf '%s%s│%s  ELK OneClick · Stack Upgrade                                  %s%s│%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET" "$C_BOLD" "$C_CYAN" "$C_RESET"
  printf '%s%s│%s  설치 버전 검사 / APT 시뮬레이션 / 동일 메이저 업그레이드         %s%s│%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET" "$C_BOLD" "$C_CYAN" "$C_RESET"
  printf '%s%s╰──────────────────────────────────────────────────────────────────╯%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
}
ui_section(){ printf '\n%s%s▸ %s%s\n' "$C_BOLD" "$C_PURPLE" "$*" "$C_RESET"; ui_line; }
log(){ printf '%s● INFO%s  %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok(){ printf '%s✔ OK%s    %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn(){ printf '%s▲ WARN%s  %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
fail(){ printf '%s✖ ERROR%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
ui_row(){ printf '  %s%-16s%s %s\n' "$C_DIM" "$1" "$C_RESET" "$2"; }
ui_final(){ ui_section '작업 결과'; ok "$*"; }

# Debian packages may use an epoch/revision (e.g. 1:9.5.2-1).
# Extract the upstream major without a sed pipeline or process substitution.
version_major(){
  local version="$1" major
  version="${version##*:}"             # Strip Debian epoch: 1:9.5.2-1 -> 9.5.2-1
  major="${version%%.*}"                # Upstream major: 9.5.2-1 -> 9
  [[ "$major" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$major"
}
ui_header
[[ ${EUID} -eq 0 ]] || fail 'sudo로 실행하세요.'
mode=${1:---check}; target=${2:-}
assume_yes=false
refresh_apt=false
if [[ "$mode" == '--check' || "$mode" == '--help' ]]; then
  (($# <= 1)) || fail '이 모드에서는 추가 인수가 필요하지 않습니다.'
else
  (($# >= 2)) || fail '목표 버전 또는 latest를 지정하세요.'
  for arg in "${@:3}"; do
    case "$arg" in
      --yes) assume_yes=true ;;
      --refresh) refresh_apt=true ;;
      *) fail "알 수 없는 옵션: $arg" ;;
    esac
  done
fi
if [[ "$mode" != '--upgrade' ]] && $assume_yes; then fail '--yes는 --upgrade에서만 사용합니다.'; fi

[[ "$mode" =~ ^(--check|--plan|--upgrade|--help)$ ]] || { usage; exit 2; }
[[ "$mode" == '--help' ]] && { usage; exit 0; }
log "ELK Stack Upgrade 도구: $TOOL_VERSION (동일 메이저 버전만 허용)"
command -v dpkg-query >/dev/null || fail 'Ubuntu/Debian 패키지 환경이 아닙니다.'
command -v apt-cache >/dev/null || fail 'APT가 필요합니다.'
installed=()
declare -A installed_versions=()
ui_section '01  현재 시스템 및 설치 상태'
log '현재 Ubuntu 버전 (업그레이드 대상 아님)'
. /etc/os-release; printf '  %s\n' "$PRETTY_NAME"
log '설치된 Elastic Stack 버전'
for pkg in elasticsearch kibana logstash; do
  v=$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || true)
  if [[ -n "$v" ]]; then
    installed+=("$pkg")
    installed_versions["$pkg"]="$v"
    ui_row "$pkg" "$v"
  else
    ui_row "$pkg" '(미설치)'
  fi
done
((${#installed[@]})) || fail '설치된 Elastic Stack 패키지가 없습니다.'
if [[ "$mode" == '--check' ]]; then
  ui_section '02  APT 후보 버전'
  log 'APT 저장소 후보 버전'
  for pkg in "${installed[@]}"; do apt-cache policy "$pkg" | grep -m1 -E 'Candidate:' | sed "s/^/  $pkg /" || true; done
  ui_final '조회 완료 · 시스템 변경 없음. --plan VERSION으로 검토하세요.'
  exit 0
fi
if $refresh_apt; then
  ui_section '02  저장소 새로고침'
  log 'APT 패키지 목록 갱신 (Ubuntu OS 업그레이드 없음)'
  if ! DEBIAN_FRONTEND=noninteractive apt-get update; then
    fail 'APT 저장소 목록 갱신 실패. 사용 가능한 후보가 오래되었을 수 있어 업그레이드를 중단합니다.'
  fi
fi
if [[ "$target" == latest ]]; then
  ui_section '02  최신 버전 탐색'
  log 'APT 저장소 최신 후보 버전 탐색 (설치된 구성 요소만)'
  latest_version=''
  for pkg in "${installed[@]}"; do
    candidate="$(LC_ALL=C apt-cache policy "$pkg" | awk '/^[[:space:]]*Candidate:[[:space:]]*/ {print $2; exit}')"
    [[ -n "$candidate" && "$candidate" != '(none)' ]] || fail "$pkg 저장소 후보 버전이 없습니다."
    upstream="${candidate##*:}"
    upstream="${upstream%%-*}"
    [[ "$upstream" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "$pkg 후보 버전 해석 실패: $candidate"
    printf '  %-15s 후보=%-20s upstream=%s\n' "$pkg" "$candidate" "$upstream"
    if [[ -z "$latest_version" ]]; then latest_version="$upstream";
    elif [[ "$latest_version" != "$upstream" ]]; then
      fail "패키지별 최신 버전이 다릅니다 ($latest_version / $pkg=$upstream). 자동 업그레이드를 중단합니다."
    fi
  done
  target="$latest_version"
fi
[[ "$target" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail '목표 버전은 x.y.z 또는 latest 형식이어야 합니다.' 
target_major="${target%%.*}"
ui_section '03  목표 버전 및 호환성 검사'
log "요청한 업그레이드 대상: $target (메이저 $target_major)"
# Compare each installed upstream major to the requested one.
# Store and print concrete versions so failures can be diagnosed from the terminal log.
base_major=''
for pkg in "${installed[@]}"; do
  current="${installed_versions[$pkg]}"
  current_major="$(version_major "$current")" || fail "$pkg 설치 버전을 해석할 수 없습니다: $current"
  printf '  [버전 검사] %-15s 설치=%-15s 메이저=%s  대상=%s\n' "$pkg" "$current" "$current_major" "$target_major"
  if [[ -z "$base_major" ]]; then
    base_major="$current_major"
  elif [[ "$current_major" != "$base_major" ]]; then
    fail "제품 메이저 버전이 서로 다릅니다 ($pkg=$current_major, 앞선 제품=$base_major). 수동 진단이 필요합니다."
  fi
  [[ "$current_major" == "$target_major" ]] || fail "$pkg 메이저 버전 변경($current_major → $target_major)은 지원하지 않습니다. 공식 업그레이드 가이드를 확인하세요."
done
packages=()
for pkg in "${installed[@]}"; do
  found=$(apt-cache madison "$pkg" | awk -F '|' -v t="$target" '{gsub(/^[ \t]+|[ \t]+$/, "", $2); v=$2; sub(/^[0-9]+:/,"",v); if (v==t || index(v,t"-")==1) {print $2; exit}}')
  [[ -n "$found" ]] || fail "$pkg 목표 버전 $target 이 현재 APT 저장소에 없습니다. apt update / 저장소를 확인하세요."
  current="${installed_versions[$pkg]}"
  if dpkg --compare-versions "$found" lt "$current"; then fail "$pkg 다운그레이드는 지원하지 않습니다 ($current → $found)."; fi
  packages+=("$pkg=$found")
done
# Already at the exact requested package versions: no changes are required.
all_current=true
for pkgver in "${packages[@]}"; do
  pkg="${pkgver%%=*}"
  requested="${pkgver#*=}"
  if [[ "${installed_versions[$pkg]}" != "$requested" ]]; then all_current=false; break; fi
done
if $all_current; then
  ui_final "이미 목표 버전 $target · 변경 없음"
  exit 0
fi
ui_section '04  업그레이드 계획'
log '업그레이드 계획 (설치된 패키지만 대상)'
printf '  %s\n' "${packages[@]}"
ui_section '05  APT 시뮬레이션'
log 'APT 설치 시뮬레이션'; apt-get -s install --only-upgrade "${packages[@]}" || fail 'APT 설치 시뮬레이션 실패'
if [[ "$mode" == '--plan' ]]; then ui_final '계획 검증 완료 · 실제 변경 없음'; exit 0; fi
if ! $assume_yes; then
  [[ -t 0 ]] || fail '무인 실행은 --yes가 필요합니다. (예: --upgrade latest --yes)'
fi
ui_section '06  업그레이드 전 확인'
cat <<'WARN'
[주의] 실제 업그레이드 시 서비스 중단이 발생할 수 있습니다.
- Elasticsearch 스냅샷/데이터 백업은 별도 확인이 필요합니다.
- 플러그인 호환성과 디스크 여유 공간 및 클러스터 상태를 먼저 점검하세요.
- 이 스크립트는 Ubuntu OS 버전 업그레이드를 수행하지 않습니다.
WARN
if $assume_yes; then
  log '명시적인 --yes 옵션에 따라 자동 진행합니다. (예상되는 서비스 중단을 수락한 경우에만 사용하세요.)'
else
  read -r -p "대상 버전 $target 으로 진행하려면 UPGRADE 입력: " yes
  [[ "$yes" == UPGRADE ]] || fail '취소했습니다.'
fi
backup="/var/backups/elk-stack-upgrade/$(date +%Y%m%d-%H%M%S)"
install -d -m 700 "$backup"
for f in /etc/elasticsearch/elasticsearch.yml /etc/kibana/kibana.yml /etc/logstash/logstash.yml /etc/elk-auto/elk.env; do
  [[ ! -f "$f" ]] || { install -d -m 700 "$backup$(dirname "$f")"; cp -a "$f" "$backup$f"; }
done
ok "설정 백업: $backup (Elasticsearch 데이터 스냅샷 대체 아님)"
ui_section "07  패키지 업그레이드"
# Upgrade Elasticsearch first, then Kibana, then Logstash, one at a time.
for pkgver in "${packages[@]}"; do
  log "패키지 업그레이드: $pkgver"
  DEBIAN_FRONTEND=noninteractive apt-get install -y --only-upgrade "$pkgver" || fail "설치 실패: $pkgver; 백업: $backup"
done
ui_section '08  서비스 상태 점검'
log '서비스 상태 확인'
for pkg in "${installed[@]}"; do
  state="$(systemctl is-active "$pkg" 2>/dev/null || true)"
  if [[ "$state" == active ]]; then ok "$pkg : active"; else warn "$pkg : ${state:-unknown} (추가 점검 필요)"; fi
done
ui_final 'APT 패키지 업그레이드 절차 종료 · 실제 API/파이프라인 및 실행 버전 별도 확인 필요'
