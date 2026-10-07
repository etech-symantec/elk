#!/usr/bin/env bash
# elk-report.sh — ELK 서버 정기점검 리포트 (읽기 전용: 서버 설정을 바꾸지 않습니다)
#
#   sudo elk-report                       # 전체 점검 (설치기가 설치한 서버)
#   sudo bash elk-report.sh               # 같은 도구를 파일로 실행
#   sudo elk-report --only sys,ver,disk   # 일부 항목만
#   sudo elk-report --list                # 점검 항목 목록
#   옵션: --only a,b  --skip a,b  --env FILE  --stale-hours N(기본 36)  --no-color | --color=always|never|auto  --self-delete  --version
#
# 항목:  sys(Ubuntu·Uptime) ver(Elastic/Logstash/Kibana 버전) cpu mem disk(파일시스템·로그 폴더·인덱스 용량)
#        last(마지막 로그 시각: 파일·인덱스) svc(서비스) es(클러스터 상태) ingest(수집·처리 상태) cert(인증서) os(업데이트·장애)
# 종료 코드: 0=모두 정상, 1=주의 있음, 2=이상 있음 (cron/모니터링에서 쓸 수 있음)
#
# 한 항목의 점검이 실패해도 리포트는 끝까지 나옵니다. (set -e 를 쓰지 않음)
set -uo pipefail
export LC_ALL=C.UTF-8 2>/dev/null || export LC_ALL=en_US.UTF-8 2>/dev/null || true

REPORT_VERSION="1"
ELK_AUTO_VERSION="2.9.5"
# Config Wizard / One-Click Installer와 동일한 빌드 번호
ELK_AUTO_BUILD="${ELK_AUTO_BUILD:-steady-tree-quiet-bridge}"
REPORT_BUILD="$ELK_AUTO_BUILD"
ENV_FILE="${ELK_ENV_FILE:-/etc/elk-auto/elk.env}"
ONLY=""; SKIP=""; STALE_H="${ELK_STALE_HOURS:-36}"; COLOR_MODE="${ELK_COLOR:-auto}"; SELF_DELETE=0
HTML_OUT="${ELK_REPORT_HTML_FILE:-/var/lib/elk-report/report.html}"; WRITE_HTML=1
ALL_SECTIONS=(sys ver cpu mem proc disk last svc es ingest cfg cert os)

usage() { sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
list_sections() {
  cat <<'EOF'
점검 항목 (--only / --skip 에 쉼표로 지정)
  sys     Ubuntu 버전 · 커널 · Uptime · 재부팅 필요 · 시간 동기화
  ver     Elasticsearch / Logstash / Kibana 버전 (설치본과 실행 중 버전 비교)
  cpu     CPU 사용률 · Load · 상위 프로세스
  mem     메모리 · Swap · 상위 프로세스
  proc    서비스별 CPU · 메모리 사용량 (현재 1초 샘플)
  disk    파일시스템 사용량 · 로그 폴더(main/ssl/cloud) 용량 · 인덱스(main/ssl/cloud) 용량
  last    마지막 로그 시각: 로그 파일 · 인덱스(@timestamp)
  svc     서비스 상태 (elasticsearch kibana logstash nginx vsftpd cron)
  es      클러스터 상태 · 미할당 샤드 · JVM Heap · ILM 오류 · 읽기 전용 인덱스
  ingest  처리 스크립트(cron·로그) · 처리 대기 파일 · Logstash 이벤트
  cfg     OneClick 설치 구성 일치 여부 (패키지 · 설정 · 도구 · cron · sysctl)
  cert    인증서 만료일 (Elasticsearch CA · Nginx)
  os      업데이트 · 실패한 서비스 · OOM · 프로세스 종료 이력
EOF
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --only) ONLY="${2:-}"; shift 2 ;;
    --skip) SKIP="${2:-}"; shift 2 ;;
    --env) ENV_FILE="${2:-}"; shift 2 ;;
    --stale-hours) STALE_H="${2:-36}"; shift 2 ;;
    --no-color) COLOR_MODE=never; shift ;;
    --html) HTML_OUT="${2:-}"; WRITE_HTML=1; shift 2 ;;
    --no-html) WRITE_HTML=0; shift ;;
    --color=*) COLOR_MODE="${1#--color=}"; shift ;;
    --self-delete) SELF_DELETE=1; shift ;;
    --list) list_sections; exit 0 ;;
    --version) echo "elk-report v${REPORT_VERSION} · ELK Auto Installer v${ELK_AUTO_VERSION} · build ${ELK_AUTO_BUILD}"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "알 수 없는 옵션: $1  (--help 참고)" >&2; exit 2 ;;
  esac
done
if (( SELF_DELETE )); then trap 'rm -f -- "${BASH_SOURCE[0]}"' EXIT; fi
[[ "$STALE_H" =~ ^[0-9]+$ && "$STALE_H" -ge 1 ]] || { echo "--stale-hours 는 1 이상의 숫자여야 합니다." >&2; exit 2; }

# ---------------------------------------------------------------- 색상 / 출력 도우미
case "${COLOR_MODE,,}" in
  always|1|true|yes|on) USE_COLOR=1 ;;
  never|0|false|no|off) USE_COLOR=0 ;;
  *) if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then USE_COLOR=1; else USE_COLOR=0; fi ;;
esac
if (( USE_COLOR )); then
  R=$'\033[0m'; B=$'\033[1m'; D=$'\033[2m'; G=$'\033[1;92m'; Y=$'\033[93m'; X=$'\033[1;91m'; C=$'\033[96m'; H=$'\033[1;97;44m'
else R=""; B=""; D=""; G=""; Y=""; X=""; C=""; H=""; fi
N_OK=0; N_WARN=0; N_CRIT=0
# 화면 폭: 터미널 폭(80~120). 파이프/파일로 저장할 때는 100. (ELK_REPORT_COLS=숫자 로 지정 가능)
COLS="${ELK_REPORT_COLS:-}"
if ! [[ "$COLS" =~ ^[0-9]+$ ]]; then
  if [[ -t 1 ]]; then COLS="$(tput cols 2>/dev/null || echo 100)"; else COLS=100; fi
  [[ "$COLS" =~ ^[0-9]+$ ]] || COLS=100
fi
(( COLS < 80 )) && COLS=80; (( COLS > 120 )) && COLS=120
LABW=26; VCOL=$((2+2+LABW+2)); VAVAIL=$((COLS-VCOL-1)); (( VAVAIL < 40 )) && VAVAIL=40
SEC_NAME=(); SEC_ST=(); CUR_IDX=-1; ISS_ST=(); ISS_SEC=(); ISS_LB=(); ISS_VAL=(); ROW_SEC=(); ROW_ST=(); ROW_LB=(); ROW_VAL=()
dwv() { # 화면 폭을 DW 에 저장 (한글·전각 = 2칸, 나머지 = 1칸)
  local s="$1" i o; DW=0
  for ((i=0;i<${#s};i++)); do
    printf -v o '%d' "'${s:i:1}" 2>/dev/null || o=0
    if (( (o>=4352 && o<=4447) || (o>=11904 && o<=42191) || (o>=44032 && o<=55203) || (o>=63744 && o<=64255) || (o>=65040 && o<=65049) || (o>=65072 && o<=65135) || (o>=65280 && o<=65376) || (o>=65504 && o<=65510) )); then DW=$((DW+2)); else DW=$((DW+1)); fi
  done
}
dw() { dwv "$1"; printf '%s' "$DW"; }
pad() { local s="$1" n="$2"; dwv "$s"; printf '%s' "$s"; (( DW < n )) && printf '%*s' $((n-DW)) ''; return 0; }
wrapv() { # 긴 문장을 공백 기준으로 줄바꿈해 WL 배열에 저장: wrapv "문장" 폭
  local text="$1" avail="$2" word cur="" cw=0 ww; local -a words=()
