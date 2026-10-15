#!/usr/bin/env bash
set -Eeuo pipefail
# ELK OneClick - Elastic Stack package upgrade helper (no Ubuntu release upgrades).
usage(){ cat <<'HELP'
Usage:
  sudo bash elk-stack-upgrade.sh --check
  sudo bash elk-stack-upgrade.sh --plan VERSION
  sudo bash elk-stack-upgrade.sh --upgrade VERSION
Examples: --plan 9.2.1 / --upgrade 9.2.1
Only upgrades the installed Elasticsearch/Kibana/Logstash packages. Never upgrades Ubuntu OS.
HELP
}
log(){ printf '[INFO] %s\n' "$*"; }
fail(){ printf '[ERROR] %s\n' "$*" >&2; exit 1; }
[[ ${EUID} -eq 0 ]] || fail 'sudo로 실행하세요.'
mode=${1:---check}; target=${2:-}
[[ "$mode" =~ ^(--check|--plan|--upgrade|--help)$ ]] || { usage; exit 2; }
[[ "$mode" == '--help' ]] && { usage; exit 0; }
command -v dpkg-query >/dev/null || fail 'Ubuntu/Debian 패키지 환경이 아닙니다.'
command -v apt-cache >/dev/null || fail 'APT가 필요합니다.'
installed=()
log '현재 Ubuntu 버전 (업그레이드 대상 아님)'
. /etc/os-release; printf '  %s\n' "$PRETTY_NAME"
log '설치된 Elastic Stack 버전'
for pkg in elasticsearch kibana logstash; do
  v=$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || true)
  if [[ -n "$v" ]]; then installed+=("$pkg"); printf '  %-15s %s\n' "$pkg" "$v"; else printf '  %-15s %s\n' "$pkg" '(미설치)'; fi
done
((${#installed[@]})) || fail '설치된 Elastic Stack 패키지가 없습니다.'
if [[ "$mode" == '--check' ]]; then
  log 'APT 저장소 후보 버전'
  for pkg in "${installed[@]}"; do apt-cache policy "$pkg" | grep -m1 -E 'Candidate:' | sed "s/^/  $pkg /" || true; done
  log '아직 업데이트하지 않았습니다. --plan VERSION 으로 검토하세요.'
  exit 0
fi
[[ "$target" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail '목표 버전은 x.y.z 형식이어야 합니다.'
mapfile -t current_majors < <(for pkg in "${installed[@]}"; do dpkg-query -W -f='${Version}' "$pkg" | sed -E 's/^([0-9]+:)?([0-9]+)\..*/\2/'; done | sort -u)
((${#current_majors[@]}==1)) || fail '제품 메이저 버전이 서로 다릅니다. 수동 진단이 필요합니다.'
[[ "${target%%.*}" == "${current_majors[0]}" ]] || fail '메이저 버전 업그레이드는 지원하지 않습니다. 공식 업그레이드 가이드를 확인하세요.'
packages=()
for pkg in "${installed[@]}"; do
  found=$(apt-cache madison "$pkg" | awk -F '|' -v t="$target" '{gsub(/^[ \t]+|[ \t]+$/, "", $2); v=$2; sub(/^[0-9]+:/,"",v); if (v==t || index(v,t"-")==1) {print $2; exit}}')
  [[ -n "$found" ]] || fail "$pkg 목표 버전 $target 이 현재 APT 저장소에 없습니다. apt update / 저장소를 확인하세요."
  current=$(dpkg-query -W -f='${Version}' "$pkg")
  if dpkg --compare-versions "$found" lt "$current"; then fail "$pkg 다운그레이드는 지원하지 않습니다 ($current → $found)."; fi
  packages+=("$pkg=$found")
done
log '업그레이드 계획 (설치된 패키지만 대상)'
printf '  %s\n' "${packages[@]}"
log 'APT 설치 시뮬레이션'; apt-get -s install --only-upgrade "${packages[@]}" || fail 'APT 설치 시뮬레이션 실패'
if [[ "$mode" == '--plan' ]]; then log '조회/시뮬레이션 완료. 실제 변경은 없습니다.'; exit 0; fi
[[ -t 0 ]] || fail '실제 업그레이드는 대화형 서버 콘솔에서만 실행 가능합니다.'
cat <<'WARN'
[주의] 실제 업그레이드 시 서비스 중단이 발생할 수 있습니다.
- Elasticsearch 스냅샷/데이터 백업은 별도 확인이 필요합니다.
- 플러그인 호환성과 디스크 여유 공간 및 클러스터 상태를 먼저 점검하세요.
- 이 스크립트는 Ubuntu OS 버전 업그레이드를 수행하지 않습니다.
WARN
read -r -p "대상 버전 $target 으로 진행하려면 UPGRADE 입력: " yes
[[ "$yes" == UPGRADE ]] || fail '취소했습니다.'
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
