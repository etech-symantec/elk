#!/usr/bin/env bash
set -euo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "sudo bash $0 로 실행하세요."; exit 1; }
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$BASE/_internal/core/elk-report.sh"
DST="/usr/local/sbin/elk-report"
[[ -f "$SRC" ]] || { echo "업데이트 파일을 찾지 못했습니다: $SRC"; exit 1; }
if [[ -f "$DST" ]]; then
  BK="${DST}.bak.$(date +%Y%m%d-%H%M%S)"
  cp -a "$DST" "$BK"
  echo "[OK] 기존 elk-report 백업: $BK"
fi
install -m 755 "$SRC" "$DST"
echo "[OK] elk-report 업데이트 완료: $DST"
if systemctl list-unit-files elk-report-web.service >/dev/null 2>&1; then
  systemctl restart elk-report-web.service || true
  echo "[OK] elk-report-web 재시작 요청"
fi
set +e
"$DST" --no-color >/tmp/elk-report-update-check.log 2>&1
RC=$?
set -e
if (( RC <= 2 )); then
  echo "[OK] 새 점검 리포트 생성 완료 (상태 코드 $RC)"
else
  echo "[WARN] 리포트 생성 확인 실패 (코드 $RC): /tmp/elk-report-update-check.log 확인"
fi
PORT=5602
if [[ -f /etc/elk-auto/elk.env ]]; then
  set +u; source /etc/elk-auto/elk.env 2>/dev/null || true; set -u
  PORT="${ELK_REPORT_WEB_PORT:-5602}"
fi
IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo "웹 리포트: http://${IP:-SERVER_IP}:${PORT}/"
