#!/usr/bin/env bash
set -Eeuo pipefail
if (( EUID != 0 )); then echo 'sudo로 실행하세요.' >&2; exit 1; fi
TEMPLATE=/usr/local/lib/elk-auto/proxysg-log-filter.conf
NEW="$(cd "$(dirname "$0")" && pwd)/proxysg-log-filter.conf"
[[ -f "$NEW" ]] || { echo "수정된 필터 파일이 없습니다: $NEW" >&2; exit 1; }
[[ -f "$TEMPLATE" ]] || { echo "서버의 필터 템플릿이 없습니다: $TEMPLATE" >&2; exit 1; }
BACKUP="${TEMPLATE}.bak.$(date +%Y%m%d-%H%M%S)"
cp -a "$TEMPLATE" "$BACKUP"
install -m 644 "$NEW" "$TEMPLATE"
echo "설치된 필터 템플릿 수정 완료 (원본 백업: $BACKUP)"
echo '주의: 이 단계는 템플릿만 교체합니다. 실제 파이프라인은 다음 명령으로 재생성하세요:'
echo '  sudo elk-patch PROXYSG_SSL_LOG_FORMAT="현재 elk.env의 SSL 포맷 전체 값"'
echo '앞서 발생한 PQ/DLQ 잠금 충돌 문제를 해결한 elk-patch 버전이 먼저 적용되어야 합니다.'
