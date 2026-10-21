#!/usr/bin/env bash
set -Eeuo pipefail
# ELK OneClick - Elastic Stack package upgrade helper (no Ubuntu release upgrades).
# Fix: validate installed major versions independently, allowing Debian epoch (1:) and revision (-1).
usage(){ cat <<'HELP'
Usage:
  sudo bash elk-stack-upgrade.sh --check
  sudo bash elk-stack-upgrade.sh --plan VERSION
  sudo bash elk-stack-upgrade.sh --upgrade VERSION [--yes] [--refresh] [--stop-timeout SECONDS]
  sudo bash elk-stack-upgrade.sh --upgrade latest --yes --refresh
Examples: --plan 9.5.5 / --plan latest / --upgrade 9.5.5
Installed OneClick command: sudo elk-stack-upgrade --plan 9.5.5
Only upgrades the installed Elasticsearch/Kibana/Logstash packages. Never upgrades Ubuntu OS.
Logstash gracefully stops before APT; if it cannot stop, upgrade safely aborts (no SIGKILL).
HELP
}
TOOL_VERSION='v2.9.81.3'
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
stop_timeout=180
if [[ "$mode" == '--check' || "$mode" == '--help' ]]; then
  (($# <= 1)) || fail '이 모드에서는 추가 인수가 필요하지 않습니다.'
else
  (($# >= 2)) || fail '목표 버전 또는 latest를 지정하세요.'
  extra_args=("${@:3}")
  for ((i=0; i<${#extra_args[@]}; i++)); do
    arg="${extra_args[i]}"
    case "$arg" in
      --yes) assume_yes=true ;;
      --refresh) refresh_apt=true ;;
      --stop-timeout)
        ((i+=1))
        ((i<${#extra_args[@]})) || fail '--stop-timeout 뒤에 초 단위 숫자가 필요합니다.'
        stop_timeout="${extra_args[i]}" ;;
      --stop-timeout=*) stop_timeout="${arg#*=}" ;;
      *) fail "알 수 없는 옵션: $arg" ;;
    esac
  done
fi
if [[ "$mode" != '--upgrade' ]] && $assume_yes; then fail '--yes는 --upgrade에서만 사용합니다.'; fi
[[ "$stop_timeout" =~ ^[0-9]+$ ]] && ((10#$stop_timeout >= 1 && 10#$stop_timeout <= 3600)) || fail '--stop-timeout은 1~3600초 정수여야 합니다.'
stop_timeout=$((10#$stop_timeout))

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
log 'APT 설치 시뮬레이션'; DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 NEEDRESTART_MODE=l apt-get -s install --only-upgrade "${packages[@]}" || fail 'APT 설치 시뮬레이션 실패'
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

# needrestart on Ubuntu 24.04 can restart services inside APT and wait forever on
# Logstash's systemd TimeoutStopUSec=infinity. Stop explicitly BEFORE package changes.
# NEVER auto-kill Logstash or manipulate its persistent queue.
logstash_managed=false
logstash_stopped=false
logstash_restored=false
upgrade_finished=false
cleanup_notice(){
  local rc=$?
  if $logstash_managed && ! $logstash_restored; then
    printf '[WARN] Logstash 종료/시작이 완료되지 않았습니다. 강제 종료/재시작은 자동으로 하지 않습니다.\n' >&2
    printf '[WARN] 상태 확인: sudo systemctl status logstash --no-pager -l\n' >&2
    printf '[WARN] 패키지 점검: sudo dpkg --audit 및 sudo dpkg-query -W elasticsearch kibana logstash\n' >&2
  fi
  if ((rc != 0)); then printf '[WARN] 업그레이드 도구 종료 코드: %s / 설정 백업: %s\n' "$rc" "$backup" >&2; fi
}
trap cleanup_notice EXIT

# APT lock check: do not start another install while previous needrestart/APT is waiting.
if command -v fuser >/dev/null 2>&1; then
  for lock in /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock; do
    if [[ -e "$lock" ]] && fuser -s "$lock" 2>/dev/null; then
      fail "다른 APT/dpkg 작업이 $lock 잠금을 사용 중입니다. 해당 작업 완료 후 다시 시도하세요. (잠금 파일을 삭제하지 마세요.)"
    fi
  done
fi

if [[ " ${installed[*]} " == *' logstash '* ]]; then
  command -v systemctl >/dev/null 2>&1 || fail 'systemctl 명령이 없어 안전한 Logstash 종료를 확인할 수 없습니다.'
  logstash_state="$(systemctl show logstash.service -p ActiveState --value)" || fail 'Logstash 서비스 상태 조회 실패'
  logstash_substate="$(systemctl show logstash.service -p SubState --value)" || true
  log "Logstash 업그레이드 전 상태: $logstash_state / $logstash_substate"
  case "$logstash_state" in
    active)
      logstash_managed=true
      log "Logstash 정상 종료 요청 (--no-block, 최대 ${stop_timeout}초)"
      systemctl stop --no-block logstash.service || fail 'Logstash 종료 요청 실패. 패키지 변경 전 중단합니다.'
      deadline=$((SECONDS + stop_timeout))
      while :; do
        logstash_state="$(systemctl show logstash.service -p ActiveState --value)" || fail 'Logstash 종료 상태 조회 실패'
        logstash_pid="$(systemctl show logstash.service -p MainPID --value)" || fail 'Logstash PID 조회 실패'
        if [[ "$logstash_state" == inactive && ( "$logstash_pid" == 0 || -z "$logstash_pid" ) ]]; then
          logstash_stopped=true
          log "Logstash 정상 종료 완료 (APT 시작 전)"
          break
        fi
        if [[ "$logstash_state" == failed ]]; then
          fail 'Logstash 종료가 failed 상태입니다. 로그 및 큐 상태를 수동 확인하세요. 패키지 변경 전 중단합니다.'
        fi
        if ((SECONDS >= deadline)); then
          warn_state="$(systemctl show logstash.service -p SubState --value 2>/dev/null || true)"
          fail "Logstash가 ${stop_timeout}초 동안 정상 종료되지 않았습니다 ($logstash_state/$warn_state, PID=$logstash_pid). 패키지는 아직 변경하지 않았습니다. journalctl -u logstash -n 50 --no-pager -l 로 확인하세요. 강제 종료는 자동 실행하지 않습니다."
        fi
        sleep 2
      done
      ;;
    inactive)
      log 'Logstash가 원래 중지되어 있습니다. 업그레이드 후에도 자동 시작하지 않습니다.' ;;
    deactivating|activating|failed|reloading|*)
      fail "Logstash 상태가 $logstash_state 입니다. 기존 종료/재시작 문제 해결 후 진행하세요. 패키지 변경 전 중단합니다." ;;
  esac
fi

# Suppress only the needrestart APT hook for THIS invocation; Ubuntu packages' own
# maintainer scripts may still restart services. Do not alter global needrestart config.
# Install Elasticsearch first, Kibana next and Logstash last.
for pkgver in "${packages[@]}"; do
  pkg="${pkgver%%=*}"; requested="${pkgver#*=}"
  if [[ "${installed_versions[$pkg]}" == "$requested" ]]; then
    log "이미 대상 버전 — 설치 생략: $pkgver"
    continue
  fi
  log "패키지 업그레이드: $pkgver (needrestart 자동 재시작 훅 비활성화)"
  DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 NEEDRESTART_MODE=l \
    apt-get install -y --only-upgrade "$pkgver" \
      || fail "패키지 업그레이드 실패: $pkgver; 백업: $backup (APT/dpkg 상태를 점검하세요)"
done
upgrade_finished=true

log 'systemd 서비스 정의 다시 읽기'
systemctl daemon-reload || fail 'systemctl daemon-reload 실패'
if $logstash_managed; then
  # Only restart the service that this tool explicitly stopped. Bounded wait,
  # no SIGKILL, and preserve originally inactive service state.
  current_state="$(systemctl show logstash.service -p ActiveState --value)" || fail 'Logstash 상태 확인 실패'
  if [[ "$current_state" != active ]]; then
    log "Logstash 시작 요청 (--no-block, 최대 ${stop_timeout}초)"
    systemctl start --no-block logstash.service || fail 'Logstash 시작 요청 실패. 수동 점검이 필요합니다.'
    deadline=$((SECONDS + stop_timeout))
    while :; do
      current_state="$(systemctl show logstash.service -p ActiveState --value)" || fail 'Logstash 시작 상태 확인 실패'
      [[ "$current_state" == active ]] && break
      [[ "$current_state" == failed ]] && fail 'Logstash 시작 실패. journalctl -u logstash -n 80 --no-pager -l 로 확인하세요.'
      ((SECONDS < deadline)) || fail "Logstash가 ${stop_timeout}초 안에 active 상태가 되지 않았습니다 (상태: $current_state). 수동 점검이 필요합니다."
      sleep 2
    done
  fi
  logstash_restored=true
  log 'Logstash 서비스 active 확인 (파이프라인 정상 처리 여부는 추가 점검 필요)'
fi

log '최종 설치 패키지 버전 및 서비스 상태 확인'
for pkg in "${installed[@]}"; do
  actual="$(dpkg-query -W -f='${Version}' "$pkg")" || fail "$pkg 설치된 버전 조회 실패"
  printf '  %-15s %s\n' "$pkg" "$actual"
  if ! systemctl is-active --quiet "$pkg"; then
    log "주의: $pkg 서비스가 active 상태가 아닙니다. 원래 중지된 서비스일 수도 있습니다."
  fi
done
log 'APT/dpkg 구성 점검'
if [[ -n "$(dpkg --audit)" ]]; then
  fail 'dpkg --audit에서 불완전한 패키지 상태가 발견되었습니다. 점검 후 복구하세요.'
fi
log '패키지 업그레이드가 종료되었습니다. Logstash API/파이프라인 및 Elasticsearch 클러스터 상태를 추가 점검하세요.'
