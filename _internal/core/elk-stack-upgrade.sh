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
TOOL_VERSION='v2.9.81.2'
log(){ printf '[INFO] %s\n' "$*"; }
fail(){ printf '[ERROR] %s\n' "$*" >&2; exit 1; }
# set -e/pipefail 중단 위치를 반드시 출력한다. (설정/비밀번호는 출력하지 않음)
unexpected_failure(){
  local rc=$? line="$1"
  printf '[ERROR] 예기치 못한 명령 실패: line=%s, exit=%s\n' "$line" "$rc" >&2
  printf '[INFO] 조회 과정 진단: sudo elk-stack-upgrade --plan 9.5.5\n' >&2
  exit "$rc"
}
trap 'unexpected_failure "$LINENO"' ERR
# Debian packages may use an epoch/revision (e.g. 1:9.5.2-1).
# Extract the upstream major without a sed pipeline or process substitution.
version_major(){
  local version="$1" major
  version="${version##*:}"             # Strip Debian epoch: 1:9.5.2-1 -> 9.5.2-1
  major="${version%%.*}"                # Upstream major: 9.5.2-1 -> 9
  [[ "$major" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$major"
}
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
log '현재 Ubuntu 버전 (업그레이드 대상 아님)'
. /etc/os-release; printf '  %s\n' "$PRETTY_NAME"
log '설치된 Elastic Stack 버전'
for pkg in elasticsearch kibana logstash; do
  v=$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || true)
  if [[ -n "$v" ]]; then
    installed+=("$pkg")
    installed_versions["$pkg"]="$v"
    printf '  %-15s %s\n' "$pkg" "$v"
  else
    printf '  %-15s %s\n' "$pkg" '(미설치)'
  fi
done
((${#installed[@]})) || fail '설치된 Elastic Stack 패키지가 없습니다.'
if [[ "$mode" == '--check' ]]; then
  log 'APT 저장소 후보 버전'
  for pkg in "${installed[@]}"; do apt-cache policy "$pkg" | grep -m1 -E 'Candidate:' | sed "s/^/  $pkg /" || true; done
  log '아직 업데이트하지 않았습니다. --plan VERSION 으로 검토하세요.'
  exit 0
fi
if $refresh_apt; then
  log 'APT 패키지 목록 갱신 (Ubuntu OS 업그레이드 없음)'
  if ! DEBIAN_FRONTEND=noninteractive apt-get update; then
    fail 'APT 저장소 목록 갱신 실패. 사용 가능한 후보가 오래되었을 수 있어 업그레이드를 중단합니다.'
  fi
fi
if [[ "$target" == latest ]]; then
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
log 'APT 저장소 패키지 조회 시작 (각 패키지 조회 결과를 표시합니다)'
packages=()
for pkg in "${installed[@]}"; do
  log "패키지 조회 중: $pkg (목표 $target)"
  # 명령 치환 안에서 set -e로 오류가 조용히 사라지지 않게 실패를 명시적으로 확인한다.
  if ! madison_output="$(LC_ALL=C apt-cache madison "$pkg" 2>&1)"; then
    fail "$pkg 저장소 조회 실패 (apt-cache madison): $madison_output"
  fi
  [[ -n "$madison_output" ]] || fail "$pkg APT 저장소에 제공 가능한 버전이 없습니다. apt-get update 및 저장소 설정을 확인하세요."
  found="$(awk -F '|' -v t="$target" '{gsub(/^[ \t]+|[ \t]+$/, "", $2); v=$2; sub(/^[0-9]+:/,"",v); if (v==t || index(v,t"-")==1) {print $2; exit}}' <<<"$madison_output")" || fail "$pkg 저장소 버전 검색에 실패했습니다."
  if [[ -z "$found" ]]; then
    printf '[INFO] %s 저장소에 있는 버전(상위 5개):\n' "$pkg"
    printf '%s\n' "$madison_output" | head -n 5 || true
    fail "$pkg 목표 버전 $target 이 현재 APT 저장소에 없습니다. apt-get update / 저장소를 확인하세요."
  fi
  current="${installed_versions[$pkg]}"
  log "$pkg: 설치=$current, 선택=$found"
  if dpkg --compare-versions "$found" lt "$current"; then fail "$pkg 다운그레이드는 지원하지 않습니다 ($current → $found)."; fi
  packages+=("$pkg=$found")
done
log '패키지 조회 완료 — APT 시뮬레이션 준비' 
# Already at the exact requested package versions: no changes are required.
all_current=true
for pkgver in "${packages[@]}"; do
  pkg="${pkgver%%=*}"
  requested="${pkgver#*=}"
  if [[ "${installed_versions[$pkg]}" != "$requested" ]]; then all_current=false; break; fi
done
if $all_current; then
  log "이미 모든 설치된 패키지가 목표 버전 $target 입니다. 변경하지 않습니다."
  exit 0
fi
log '업그레이드 계획 (설치된 패키지만 대상)'
printf '  %s\n' "${packages[@]}"
log 'APT 설치 시뮬레이션'; apt-get -s install --only-upgrade "${packages[@]}" || fail 'APT 설치 시뮬레이션 실패'
if [[ "$mode" == '--plan' ]]; then log '조회/시뮬레이션 완료. 실제 변경은 없습니다.'; exit 0; fi
if ! $assume_yes; then
  [[ -t 0 ]] || fail '무인 실행은 --yes가 필요합니다. (예: --upgrade latest --yes)'
fi
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
log "설정 백업: $backup (Elasticsearch 데이터 스냅샷 대체 아님)"
# Upgrade Elasticsearch first, then Kibana, then Logstash, one at a time.
for pkgver in "${packages[@]}"; do
  log "패키지 업그레이드: $pkgver"
  DEBIAN_FRONTEND=noninteractive apt-get install -y --only-upgrade "$pkgver" || fail "설치 실패: $pkgver; 백업: $backup"
done
log '서비스 상태 확인'
for pkg in "${installed[@]}"; do systemctl is-active "$pkg" || log "주의: $pkg 가 active 상태가 아닙니다."; done
log '패키지 업그레이드가 종료되었습니다. 애플리케이션 API/파이프라인 상태를 추가 점검하세요.'
