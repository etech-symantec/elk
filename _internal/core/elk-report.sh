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
ELK_AUTO_VERSION="2.9.4"
ENV_FILE="${ELK_ENV_FILE:-/etc/elk-auto/elk.env}"
ONLY=""; SKIP=""; STALE_H="${ELK_STALE_HOURS:-36}"; COLOR_MODE="${ELK_COLOR:-auto}"; SELF_DELETE=0
ALL_SECTIONS=(sys ver cpu mem disk last svc es ingest cert os)

usage() { sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
list_sections() {
  cat <<'EOF'
점검 항목 (--only / --skip 에 쉼표로 지정)
  sys     Ubuntu 버전 · 커널 · Uptime · 재부팅 필요 · 시간 동기화
  ver     Elasticsearch / Logstash / Kibana 버전 (설치본과 실행 중 버전 비교)
  cpu     CPU 사용률 · Load · 상위 프로세스
  mem     메모리 · Swap · 상위 프로세스
  disk    파일시스템 사용량 · 로그 폴더(main/ssl/cloud) 용량 · 인덱스(main/ssl/cloud) 용량
  last    마지막 로그 시각: 로그 파일 · 인덱스(@timestamp)
  svc     서비스 상태 (elasticsearch kibana logstash nginx vsftpd cron)
  es      클러스터 상태 · 미할당 샤드 · JVM Heap · ILM 오류 · 읽기 전용 인덱스
  ingest  처리 스크립트(cron·로그) · 처리 대기 파일 · Logstash 이벤트
  cert    인증서 만료일 (Elasticsearch CA · Nginx)
  os      업데이트 · 실패한 서비스 · OOM 기록
EOF
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --only) ONLY="${2:-}"; shift 2 ;;
    --skip) SKIP="${2:-}"; shift 2 ;;
    --env) ENV_FILE="${2:-}"; shift 2 ;;
    --stale-hours) STALE_H="${2:-36}"; shift 2 ;;
    --no-color) COLOR_MODE=never; shift ;;
    --color=*) COLOR_MODE="${1#--color=}"; shift ;;
    --self-delete) SELF_DELETE=1; shift ;;
    --list) list_sections; exit 0 ;;
    --version) echo "elk-report (ELK Auto Installer v${ELK_AUTO_VERSION})"; exit 0 ;;
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
SEC_NAME=(); SEC_ST=(); CUR_IDX=-1; ISS_ST=(); ISS_SEC=(); ISS_LB=(); ISS_VAL=()
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
  WL=(); read -ra words <<<"$text"
  for word in "${words[@]}"; do
    dwv "$word"; ww=$DW
    if [[ -z "$cur" ]]; then cur="$word"; cw=$ww
    elif (( cw + 1 + ww <= avail )); then cur+=" $word"; cw=$((cw+1+ww))
    else WL+=("$cur"); cur="$word"; cw=$ww; fi
  done
  [[ -n "$cur" ]] && WL+=("$cur")
  return 0
}
heading() { # ━━ 제목 ━━━━━━━━ (화면 폭에 맞춤)
  local t="$1" fill bar; dwv "$t"; fill=$((COLS-DW-4)); (( fill < 4 )) && fill=4
  printf -v bar '%*s' "$fill" ''; bar="${bar// /━}"
  printf '\n%s━━ %s %s%s\n' "$B$C" "$t" "$bar" "$R"
}
section() { SEC_NAME+=("${1%%  *}"); SEC_ST+=(0); CUR_IDX=$((${#SEC_NAME[@]}-1)); heading "$1"; }
group() { printf '  %s▸ %s%s' "$B" "$1" "$R"; [[ -n "${2:-}" ]] && printf '  %s%s%s' "$D" "$2" "$R"; printf '\n'; }
mark() { (( CUR_IDX >= 0 )) && (( $1 > SEC_ST[CUR_IDX] )) && SEC_ST[CUR_IDX]=$1; return 0; }
row() { # status label value  — 라벨 칸 고정, 긴 값은 값 칸에 맞춰 줄바꿈, 주의/이상은 라벨 색 강조
  local st="$1" label="$2" val="$3" g c lc="$B" lw i
  case "$st" in
    ok)   g="✔"; c="$G"; N_OK=$((N_OK+1)); mark 0 ;;
    warn) g="⚠"; c="$Y"; lc="$B$Y"; N_WARN=$((N_WARN+1)); mark 1; ISS_ST+=(warn); ISS_SEC+=("${SEC_NAME[CUR_IDX]:-}"); ISS_LB+=("$label"); ISS_VAL+=("$val") ;;
    crit) g="✖"; c="$X"; lc="$B$X"; N_CRIT=$((N_CRIT+1)); mark 2; ISS_ST+=(crit); ISS_SEC+=("${SEC_NAME[CUR_IDX]:-}"); ISS_LB+=("$label"); ISS_VAL+=("$val") ;;
    *)    g="·"; c="$D" ;;
  esac
  dwv "$label"; lw=$DW; wrapv "$val" "$VAVAIL"
  if (( lw > LABW )); then
    printf '  %s%s%s %s%s%s\n' "$c" "$g" "$R" "$lc" "$label" "$R"
    for ((i=0;i<${#WL[@]};i++)); do printf '%*s%s\n' "$VCOL" '' "${WL[i]}"; done
  else
    printf '  %s%s%s %s%s%*s%s  %s\n' "$c" "$g" "$R" "$lc" "$label" $((LABW-lw)) '' "$R" "${WL[0]:-}"
    for ((i=1;i<${#WL[@]};i++)); do printf '%*s%s\n' "$VCOL" '' "${WL[i]}"; done
  fi
}
sub() { local i; wrapv "$1" $((VAVAIL-2)); for ((i=0;i<${#WL[@]};i++)); do if (( i == 0 )); then printf '%*s%s↳ %s%s\n' "$VCOL" '' "$D" "${WL[i]}" "$R"; else printf '%*s%s  %s%s\n' "$VCOL" '' "$D" "${WL[i]}" "$R"; fi; done; }
bytes_h() { awk -v b="${1:-0}" 'BEGIN{split("B KB MB GB TB PB",u," ");i=1;while(b>=1024&&i<6){b/=1024;i++}; if(i==1)printf "%d%s",b,u[i]; else printf "%.1f%s",b,u[i]}'; }
num_h() { awk -v n="${1:-0}" 'BEGIN{s=sprintf("%d",n);o="";while(length(s)>3){o="," substr(s,length(s)-2) o;s=substr(s,1,length(s)-3)};print s o}'; }
age_h() { local s="${1:-0}"; if (( s < 0 )); then s=0; fi; if (( s < 3600 )); then printf '%d분 전' $((s/60)); elif (( s < 172800 )); then printf '%d시간 전' $((s/3600)); else printf '%d일 전' $((s/86400)); fi; }
epoch_h() { date -d "@$1" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$1"; }
want() { local s="$1"; [[ -n "$ONLY" ]] && [[ ",$ONLY," != *",$s,"* ]] && return 1; [[ -n "$SKIP" && ",$SKIP," == *",$s,"* ]] && return 1; return 0; }
for x in ${ONLY//,/ } ${SKIP//,/ }; do [[ " ${ALL_SECTIONS[*]} " == *" $x "* ]] || { echo "알 수 없는 점검 항목: $x  (--list 로 확인)" >&2; exit 2; }; done

# ---------------------------------------------------------------- 환경(elk.env) 읽기
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set +u; source "$ENV_FILE" 2>/dev/null; set -u
else
  ENV_MISSING=1
fi
# ---- 이전 버전(2.9.4 미만) 서버: 설정 이름이 GUIDE_* 인 elk.env 도 읽는다. (재설치 없이 점검 도구만 추가한 서버를 위해)
LEGACY_ENV=0
if grep -qE '^GUIDE_[A-Z0-9_]+=' "$ENV_FILE" 2>/dev/null && ! grep -qE '^PROXYSG_[A-Z0-9_]+=' "$ENV_FILE" 2>/dev/null; then LEGACY_ENV=1; fi
while IFS= read -r _old; do
  case "$_old" in
    GUIDE_PROXY_FLOW_ENABLED) _new="PROXYSG_FLOW_ENABLED" ;;
    GUIDE_PROXY_CSV_FILTER_ENABLED) _new="PROXYSG_CSV_FILTER_ENABLED" ;;
    *) _new="PROXYSG_${_old#GUIDE_}" ;;
  esac
  if [[ -z "${!_new+x}" ]]; then printf -v "$_new" '%s' "${!_old}"; fi
done < <(compgen -A variable GUIDE_ || true)
unset _old _new
[[ "${LOGSTASH_PROFILE:-}" == "proxysg_guide" ]] && LOGSTASH_PROFILE="proxysg"
tf() { [[ "${1,,}" =~ ^(1|true|yes|y|on)$ ]]; }
: "${STATE_DIR:=/root/.elk-auto-installer}"; : "${SECRETS_FILE:=${STATE_DIR}/secrets.env}"
: "${ES_HTTP_PORT:=9200}"; : "${ELASTIC_USERNAME:=elastic}"; : "${ES_SECURITY_ENABLED:=true}"; : "${ES_PATH_DATA:=/var/lib/elasticsearch}"
: "${INDEX_PREFIX:=network-log}"; : "${PROXYSG_FLOW_ENABLED:=false}"; : "${PROXYSG_CLOUD_ENABLED:=false}"
: "${PROXYSG_MAIN_SOURCE_DIR:=/home/main}"; : "${PROXYSG_SSL_SOURCE_DIR:=/home/ssl}"; : "${PROXYSG_CLOUD_SOURCE_DIR:=/home/cloud}"
: "${PROXYSG_MAIN_BACKUP_DIR:=/home/main_backup}"; : "${PROXYSG_SSL_BACKUP_DIR:=/home/ssl_backup}"; : "${PROXYSG_CLOUD_BACKUP_DIR:=/home/cloud_backup}"
: "${PROXYSG_MAIN_PROCESS_DIR:=/home/main_process}"; : "${PROXYSG_SSL_PROCESS_DIR:=/home/ssl_process}"; : "${PROXYSG_CLOUD_PROCESS_DIR:=/home/cloud_process}"
: "${PROXYSG_MAIN_INDEX_PREFIX:=proxy-main}"; : "${PROXYSG_SSL_INDEX_PREFIX:=proxy-ssl}"; : "${PROXYSG_CLOUD_INDEX_PREFIX:=proxy-cloud}"
: "${PROXYSG_PROCESS_LOG:=/var/log/elk-proxysg-log-process.log}"; : "${PROXYSG_PROCESS_CRON:=0 3 * * *}"
: "${INSTALL_NGINX:=false}"; : "${NGINX_TLS_CERT_FILE:=/etc/ssl/certs/kibana-selfsigned.crt}"; : "${INSTALL_FTP_SERVER:=true}"
: "${LOGSTASH_API_ENABLED:=true}"; : "${LOGSTASH_API_HOST:=127.0.0.1}"; : "${LOGSTASH_API_PORT:=9600}"; : "${KIBANA_SERVER_PORT:=5601}"
[[ "$LOGSTASH_API_HOST" == "0.0.0.0" ]] && LOGSTASH_API_HOST=127.0.0.1
if [[ -f "$SECRETS_FILE" ]]; then set +u; source "$SECRETS_FILE" 2>/dev/null; set -u; fi
CA="${ELK_CA_FILE:-/etc/elasticsearch/certs/http_ca.crt}"
if [[ -n "${ELK_ES_URL:-}" ]]; then URL="$ELK_ES_URL"; elif [[ -f "$CA" ]]; then URL="https://127.0.0.1:${ES_HTTP_PORT}"; else URL="http://127.0.0.1:${ES_HTTP_PORT}"; fi
curl_args=(-sS --max-time 20)
[[ "$URL" == https://* && -f "$CA" ]] && curl_args+=(--cacert "$CA")
tf "$ES_SECURITY_ENABLED" && [[ -n "${ELASTIC_PASSWORD:-}" ]] && curl_args+=(-u "${ELASTIC_USERNAME}:${ELASTIC_PASSWORD}")
HAVE_JQ=1; command -v jq >/dev/null 2>&1 || HAVE_JQ=0
es() { curl "${curl_args[@]}" "$URL$1" 2>/dev/null; }
es_post() { curl "${curl_args[@]}" -X POST -H 'Content-Type: application/json' -d "$2" "$URL$1" 2>/dev/null; }
ES_OK=-1   # -1 아직 모름, 0 접속 실패, 1 접속 성공
es_up() {
  if (( ES_OK < 0 )); then
    local r; r="$(es "/" || true)"
    if (( HAVE_JQ )) && [[ -n "$r" ]] && jq -e '.version.number' >/dev/null 2>&1 <<<"$r"; then ES_OK=1; ES_ROOT="$r"; else ES_OK=0; ES_ROOT=""; fi
  fi
  (( ES_OK == 1 ))
}
# 로그 종류 목록: "표시이름|수신폴더|백업폴더|처리폴더|인덱스 접두어"
TYPES=()
if tf "$PROXYSG_FLOW_ENABLED"; then
  TYPES+=("MAIN|$PROXYSG_MAIN_SOURCE_DIR|$PROXYSG_MAIN_BACKUP_DIR|$PROXYSG_MAIN_PROCESS_DIR|$PROXYSG_MAIN_INDEX_PREFIX")
  TYPES+=("SSL|$PROXYSG_SSL_SOURCE_DIR|$PROXYSG_SSL_BACKUP_DIR|$PROXYSG_SSL_PROCESS_DIR|$PROXYSG_SSL_INDEX_PREFIX")
  tf "$PROXYSG_CLOUD_ENABLED" && TYPES+=("Cloud|$PROXYSG_CLOUD_SOURCE_DIR|$PROXYSG_CLOUD_BACKUP_DIR|$PROXYSG_CLOUD_PROCESS_DIR|$PROXYSG_CLOUD_INDEX_PREFIX")
else
  TYPES+=("로그||||${INDEX_PREFIX}")      # ProxySG 흐름을 쓰지 않는 서버: 폴더 없이 일반 인덱스만
fi
dir_stat() { # dir -> "count bytes newest_epoch oldest_epoch"
  local d="$1"
  [[ -n "$d" && -d "$d" ]] || { echo "- - - -"; return; }
  timeout 60 find "$d" -type f -printf '%s %T@\n' 2>/dev/null | awk 'BEGIN{n=0;s=0;mx=0;mn=0} {n++;s+=$1;t=int($2); if(t>mx)mx=t; if(mn==0||t<mn)mn=t} END{printf "%d %d %d %d\n",n,s,mx,mn}'
}
NOW="$(date +%s)"

# ---------------------------------------------------------------- 머리말
kv() { printf '  %s%s%s %s\n' "$D" "$(pad "$1" 8)" "$R" "$2"; }
_t=" ELK 정기점검 리포트"; dwv "$_t"; printf '\n%s%s%*s%s\n' "$H" "$_t" $(( COLS > DW ? COLS-DW : 0 )) '' "$R"
kv "서버" "$(hostname)    ·    $(date '+%Y-%m-%d %H:%M:%S %Z')"
kv "버전" "ELK Auto Installer v${ELK_AUTO_VERSION}    ·    환경파일 ${ENV_FILE}"
kv "범례" "${G}✔ 정상${R}   ${Y}⚠ 주의${R}   ${X}✖ 이상${R}   ${D}· 정보${R}"
unset _t
(( LEGACY_ENV )) && printf '  %s· 이전 버전(2.9.4 미만, GUIDE_*) 설정 파일을 읽어 점검합니다.%s\n' "$D" "$R"
[[ -n "${ENV_MISSING:-}" ]] && printf '  %s⚠ elk.env 를 찾지 못해 기본값으로 점검합니다: %s%s\n' "$Y" "$ENV_FILE" "$R"
(( HAVE_JQ )) || printf '  %s⚠ jq 가 없어 Elasticsearch 항목은 건너뜁니다. (sudo apt-get install -y jq)%s\n' "$Y" "$R"

# ---------------------------------------------------------------- sys
if want sys; then
  section "시스템  (Ubuntu · Uptime)"
  pretty=""; ver_id=""; [[ -r /etc/os-release ]] && { pretty="$(. /etc/os-release; printf '%s' "${PRETTY_NAME:-}")"; ver_id="$(. /etc/os-release; printf '%s' "${VERSION_ID:-}")"; }
  [[ -n "$pretty" ]] || pretty="$(lsb_release -ds 2>/dev/null || echo unknown)"
  if [[ "$ver_id" == "22.04" || "$ver_id" == "24.04" ]]; then st=ok; else st=warn; fi
  row "$st" "Ubuntu Version" "$pretty  (kernel $(uname -r))"
  [[ "$st" == warn ]] && sub "이 설치기는 Ubuntu 22.04 / 24.04 에서 검증되었습니다."
  up_s="$(awk '{printf "%d",$1}' /proc/uptime 2>/dev/null || echo 0)"; d=$((up_s/86400)); h=$(((up_s%86400)/3600)); m=$(((up_s%3600)/60))
  since="$(uptime -s 2>/dev/null || date -d "@$((NOW-up_s))" '+%Y-%m-%d %H:%M:%S')"
  if (( d >= 180 )); then st=warn; else st=ok; fi
  row "$st" "서버 Uptime" "${d}일 ${h}시간 ${m}분  (부팅 $since)"
  (( d >= 180 )) && sub "부팅한 지 180일이 넘었습니다. 커널/보안 업데이트 적용을 위한 재부팅을 계획하세요."
  if [[ -e /var/run/reboot-required ]]; then row warn "재부팅 필요" "업데이트 적용을 위해 재부팅이 필요합니다. ($(tr '\n' ' ' </var/run/reboot-required.pkgs 2>/dev/null | cut -c1-60))"; else row ok "재부팅 필요 여부" "필요 없음"; fi
  ntp="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo unknown)"
  case "$ntp" in yes) row ok "시간 동기화(NTP)" "동기화됨 ($(date +%Z))" ;; no) row warn "시간 동기화(NTP)" "동기화되지 않음 — 로그 시각이 어긋날 수 있습니다." ;; *) row info "시간 동기화(NTP)" "확인할 수 없음" ;; esac
fi

# ---------------------------------------------------------------- ver
norm_ver() { local v="${1:-}"; v="${v#*:}"; v="${v%%-*}"; printf '%s' "$v"; }
if want ver; then
  section "버전  (Elastic Stack)"
  declare -A INST=(); for p in elasticsearch logstash kibana; do v="$(dpkg-query -W -f='${Version}' "$p" 2>/dev/null || true)"; INST[$p]="$(norm_ver "$v")"; done
  run_es=""; run_ls=""
  if (( HAVE_JQ )) && es_up; then run_es="$(jq -r '.version.number // empty' <<<"$ES_ROOT")"; fi
  if tf "$LOGSTASH_API_ENABLED" && (( HAVE_JQ )); then run_ls="$(curl -sS --max-time 5 "http://${LOGSTASH_API_HOST}:${LOGSTASH_API_PORT}/" 2>/dev/null | jq -r '.version // empty' 2>/dev/null || true)"; fi
  for p in elasticsearch logstash kibana; do
    case "$p" in elasticsearch) lab="Elasticsearch"; run="$run_es" ;; logstash) lab="Logstash"; run="$run_ls" ;; *) lab="Kibana"; run="" ;; esac
    iv="${INST[$p]}"
    if [[ -z "$iv" ]]; then row info "$lab Version" "설치되어 있지 않음"
    elif [[ -n "$run" && "$run" != "$iv" ]]; then row warn "$lab Version" "설치본 $iv · 실행 중 $run  (재시작이 필요합니다)"
    else row ok "$lab Version" "$iv${run:+  (실행 중 $run)}"; fi
  done
  vs=(); for p in elasticsearch logstash kibana; do [[ -n "${INST[$p]}" ]] && vs+=("${INST[$p]}"); done
  if (( ${#vs[@]} > 1 )) && [[ "$(printf '%s\n' "${vs[@]}" | sort -u | wc -l)" -gt 1 ]]; then row warn "제품 간 버전 일치" "Elasticsearch / Logstash / Kibana 버전이 서로 다릅니다."; elif (( ${#vs[@]} > 1 )); then row ok "제품 간 버전 일치" "모두 ${vs[0]}"; fi
fi

# ---------------------------------------------------------------- cpu
if want cpu; then
  section "CPU"
  read -r _ u1 n1 s1 i1 w1 q1 sq1 st1 _ < /proc/stat; sleep 1; read -r _ u2 n2 s2 i2 w2 q2 sq2 st2 _ < /proc/stat
  t1=$((u1+n1+s1+i1+w1+q1+sq1+st1)); t2=$((u2+n2+s2+i2+w2+q2+sq2+st2)); idle=$(((i2+w2)-(i1+w1))); tot=$((t2-t1))
  if (( tot > 0 )); then pct=$(( (100*(tot-idle) + tot/2) / tot )); else pct=0; fi
  cores="$(nproc 2>/dev/null || echo 1)"; read -r l1 l5 l15 _ < /proc/loadavg
  if (( pct >= 95 )); then st=crit; elif (( pct >= 80 )); then st=warn; else st=ok; fi
  row "$st" "CPU Usage" "${pct}%  (코어 ${cores}개, 1초 평균)"
  lr="$(awk -v l="$l1" -v c="$cores" 'BEGIN{printf "%.2f",l/c}')"; if awk -v r="$lr" 'BEGIN{exit !(r>=2.0)}'; then st=crit; elif awk -v r="$lr" 'BEGIN{exit !(r>=1.0)}'; then st=warn; else st=ok; fi
  row "$st" "Load Average" "$l1 / $l5 / $l15  (1/5/15분, 코어당 ${lr})"
  top="$(ps -eo comm=,pcpu= --sort=-pcpu 2>/dev/null | head -3 | awk '{printf "%s%s %s%%",(NR>1?", ":""),$1,$2}')"; [[ -n "$top" ]] && sub "상위 프로세스: $top"
fi

# ---------------------------------------------------------------- mem
if want mem; then
  section "메모리"
  read -r total used avail swt swu <<<"$(free -b 2>/dev/null | awk '/^Mem:/{t=$2;a=$7} /^Swap:/{st=$2;su=$3} END{printf "%d %d %d %d %d",t,t-a,a,st,su}')"
  if (( total > 0 )); then mp=$(( 100*used/total )); else mp=0; fi
  if (( mp >= 95 )); then st=crit; elif (( mp >= 85 )); then st=warn; else st=ok; fi
  row "$st" "Memory Usage" "${mp}%  (사용 $(bytes_h "$used") / 전체 $(bytes_h "$total") · 사용 가능 $(bytes_h "$avail"))"
  sw_pct=0; (( swt > 0 )) && sw_pct=$(( 100*swu/swt ))
  swn="$(cat "${ELK_SWAPPINESS_FILE:-/proc/sys/vm/swappiness}" 2>/dev/null || sysctl -n vm.swappiness 2>/dev/null || echo '?')"
  mlock="?"; if (( HAVE_JQ )) && es_up; then mlock="$(es "/_nodes?filter_path=nodes.*.process.mlockall" | jq -r '[.nodes[]?.process.mlockall]|if length==0 then "?" else (all|tostring) end' 2>/dev/null || echo '?')"; fi
  case "$mlock" in true) mlk="memory_lock 켜짐" ;; false) mlk="memory_lock 꺼짐" ;; *) mlk="memory_lock 확인 불가" ;; esac
  if (( swt == 0 )); then
    row info "Swap" "사용 안 함 — 메모리가 갑자기 모자라면 OOM 으로 Elasticsearch 가 종료될 수 있습니다. (권장: swap 파일 + vm.swappiness=1 + bootstrap.memory_lock)"
  elif [[ "$swn" =~ ^[0-9]+$ ]] && (( swn > 10 )); then
    row warn "Swap" "$(bytes_h "$swt") (사용 $(bytes_h "$swu")) · vm.swappiness=${swn} — Elasticsearch 서버는 1 을 권장합니다. (sysctl vm.swappiness=1)"
  elif (( sw_pct >= 25 )); then
    row warn "Swap" "$(bytes_h "$swt") 중 ${sw_pct}% 사용 중($(bytes_h "$swu")) — 메모리가 부족해 swap 을 쓰고 있습니다. Heap/메모리 증설을 검토하세요."
  else
    row ok "Swap" "$(bytes_h "$swt") (사용 $(bytes_h "$swu")) · 안전망으로 켜져 있음 · vm.swappiness=${swn} · ${mlk}"
  fi
  top="$(ps -eo comm=,pmem= --sort=-pmem 2>/dev/null | head -3 | awk '{printf "%s%s %s%%",(NR>1?", ":""),$1,$2}')"; [[ -n "$top" ]] && sub "상위 프로세스: $top"
fi

# ---------------------------------------------------------------- disk
if want disk; then
  section "디스크 사용량"
  declare -A SEEN=(); paths=("/" "$ES_PATH_DATA")
  for t in "${TYPES[@]}"; do IFS='|' read -r _ a b c _ <<<"$t"; paths+=("$a" "$b" "$c"); done
  for p in "${paths[@]}"; do
    [[ -n "$p" && -e "$p" ]] || continue
    line="$(df -PB1 "$p" 2>/dev/null | awk 'NR==2{print $1"|"$6"|"$2"|"$3"|"$4"|"$5}')"; [[ -n "$line" ]] || continue
    IFS='|' read -r dev mnt tot usd av pc <<<"$line"; [[ -n "${SEEN[$mnt]:-}" ]] && continue; SEEN[$mnt]=1; pc="${pc%\%}"
    if (( pc >= 90 )); then st=crit; elif (( pc >= 85 )); then st=warn; else st=ok; fi
    lab="디스크 $mnt"; [[ "$mnt" == "/" ]] && lab="디스크 / (루트)"
    row "$st" "$lab" "${pc}%  (사용 $(bytes_h "$usd") / 전체 $(bytes_h "$tot") · 여유 $(bytes_h "$av"))"
    (( pc >= 85 )) && sub "Elasticsearch 는 85% 이상에서 새 샤드 배치를 멈추고, 95%에서 인덱스를 읽기 전용으로 바꿉니다."
  done
  tf "$PROXYSG_FLOW_ENABLED" && {
    group "로그 파일 폴더" "(수신 → 처리 → 백업)"
    for t in "${TYPES[@]}"; do
      IFS='|' read -r nm src bak prc _ <<<"$t"; out=""
      for pair in "수신:$src" "처리:$prc" "백업:$bak"; do
        lab="${pair%%:*}"; d="${pair#*:}"; read -r n s _ _ <<<"$(dir_stat "$d")"
        if [[ "$n" == "-" ]]; then out+="$lab 폴더 없음 · "; else out+="$lab $(num_h "$n")개 $(bytes_h "$s") · "; fi
      done
      row info "로그 $nm" "${out% · }"
    done
  }
  group "Indices" "(Elasticsearch 인덱스 용량)"
  if (( HAVE_JQ )) && es_up; then
    for t in "${TYPES[@]}"; do
      IFS='|' read -r nm _ _ _ pfx <<<"$t"
      js="$(es "/_cat/indices/${pfx}-*?bytes=b&h=index,docs.count,store.size&format=json" || true)"
      if ! jq -e 'type=="array"' >/dev/null 2>&1 <<<"$js"; then row warn "인덱스 $nm" "조회 실패 (${pfx}-*)"; continue; fi
      cnt="$(jq 'length' <<<"$js")"
      if (( cnt == 0 )); then row warn "인덱스 $nm" "${pfx}-* 인덱스가 없습니다."; continue; fi
      docs="$(jq '[.[]|(."docs.count"//"0")|tonumber]|add' <<<"$js")"; size="$(jq '[.[]|(."store.size"//"0")|tonumber]|add' <<<"$js")"
      first="$(jq -r 'map(.index)|sort|first' <<<"$js")"; last="$(jq -r 'map(.index)|sort|last' <<<"$js")"
      row info "인덱스 $nm" "${cnt}개 · 문서 $(num_h "$docs") · 용량 $(bytes_h "$size")  ($first ~ $last)"
    done
    al="$(es "/_cat/allocation?bytes=b&format=json" || true)"
    if jq -e 'type=="array"' >/dev/null 2>&1 <<<"$al"; then
      while IFS='|' read -r nd pc usd tot; do [[ -z "$nd" || "$nd" == "UNASSIGNED" ]] && continue
        if (( pc >= 90 )); then st=crit; elif (( pc >= 85 )); then st=warn; else st=ok; fi
        row "$st" "ES 데이터 디스크" "${pc}%  (노드 $nd · 사용 $(bytes_h "$usd") / 전체 $(bytes_h "$tot"))"
      done < <(jq -r '.[]|select(."disk.percent"!=null)|"\(.node)|\(."disk.percent"|tonumber)|\(."disk.used"|tonumber)|\(."disk.total"|tonumber)"' <<<"$al")
    fi
  else row warn "Indices" "Elasticsearch 에 연결할 수 없어 인덱스 용량을 확인하지 못했습니다. ($URL)"; fi
fi

# ---------------------------------------------------------------- last
if want last; then
  section "마지막 로그 시각"
  group "로그 파일" "(수신·처리·백업 폴더 중 가장 최근 파일, 기준 ${STALE_H}시간)"
  declare -A FILE_LAST=()
  if tf "$PROXYSG_FLOW_ENABLED"; then
    for t in "${TYPES[@]}"; do
      IFS='|' read -r nm src bak prc _ <<<"$t"; best=0; bestd=""
      for d in "$src" "$prc" "$bak"; do read -r n _ mx _ <<<"$(dir_stat "$d")"; [[ "$n" =~ ^[0-9]+$ ]] || continue; (( n > 0 && mx > best )) && { best="$mx"; bestd="$d"; }; done
      if (( best == 0 )); then row warn "로그 파일 $nm" "로그 파일이 없습니다."; continue; fi
      f="$(timeout 60 find "$bestd" -type f -printf '%T@ %f\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)"
      FILE_LAST[$nm]="$best"; age=$((NOW-best))
      if (( age > 2*STALE_H*3600 )); then st=crit; elif (( age > STALE_H*3600 )); then st=warn; else st=ok; fi
      row "$st" "로그 파일 $nm" "$(epoch_h "$best")  ($(age_h "$age"))  $f"
    done
  else row info "로그 파일" "ProxySG 로그 처리 스크립트를 쓰지 않아 해당 없음"; fi
  group "Indices" "(@timestamp 최댓값)"
  if (( HAVE_JQ )) && es_up; then
    for t in "${TYPES[@]}"; do
      IFS='|' read -r nm _ _ _ pfx <<<"$t"
      js="$(es_post "/${pfx}-*/_search?size=0&ignore_unavailable=true&allow_no_indices=true" '{"aggs":{"last":{"max":{"field":"@timestamp"}}}}' || true)"
      v="$(jq -r '.aggregations.last.value // empty' <<<"$js" 2>/dev/null || true)"
      if [[ -z "$v" ]]; then row warn "인덱스 $nm" "${pfx}-* 에서 @timestamp 를 찾지 못했습니다. (인덱스 없음 또는 문서 없음)"; continue; fi
      ep=$(( ${v%.*} / 1000 )); age=$((NOW-ep))
      if (( age > 2*STALE_H*3600 )); then st=crit; elif (( age > STALE_H*3600 )); then st=warn; else st=ok; fi
      row "$st" "인덱스 $nm" "$(epoch_h "$ep")  ($(age_h "$age"))  ${pfx}-*"
      fl="${FILE_LAST[$nm]:-0}"; if (( fl > 0 && fl - ep > 6*3600 )); then row warn "수집 지연 $nm" "로그 파일이 인덱스보다 $(age_h $((fl-ep)) | sed 's/ 전//') 더 최신입니다. Logstash 처리가 밀렸을 수 있습니다."; fi
    done
  else row warn "Indices" "Elasticsearch 에 연결할 수 없어 마지막 로그 시각을 확인하지 못했습니다."; fi
fi

# ---------------------------------------------------------------- svc
if want svc; then
  section "서비스"
  svcs=(elasticsearch kibana logstash); tf "$INSTALL_NGINX" && svcs+=(nginx); tf "$INSTALL_FTP_SERVER" && svcs+=(vsftpd); svcs+=(cron)
  for s in "${svcs[@]}"; do
    a="$(systemctl is-active "$s" 2>/dev/null || true)"; e="$(systemctl is-enabled "$s" 2>/dev/null || true)"
    case "$a" in
      active) if [[ "$e" == enabled || "$e" == static ]]; then row ok "$s" "실행 중 · 부팅 시 자동 시작"; else row warn "$s" "실행 중이지만 부팅 시 자동 시작이 꺼져 있습니다. ($e)"; fi ;;
      "") row info "$s" "상태를 확인할 수 없음" ;;
      *) row crit "$s" "실행 중이 아닙니다. ($a)" ;;
    esac
  done
fi

# ---------------------------------------------------------------- es
if want es; then
  section "Elasticsearch 상태"
  if (( HAVE_JQ )) && es_up; then
    h="$(es "/_cluster/health" || true)"
    if jq -e '.status' >/dev/null 2>&1 <<<"$h"; then
      stt="$(jq -r '.status' <<<"$h")"; case "$stt" in green) st=ok ;; yellow) st=warn ;; *) st=crit ;; esac
      row "$st" "클러스터 상태" "$stt  (노드 $(jq -r '.number_of_nodes' <<<"$h")개 · 활성 샤드 $(jq -r '.active_shards' <<<"$h") · $(jq -r '.active_shards_percent_as_number' <<<"$h")%)"
      un="$(jq -r '.unassigned_shards' <<<"$h")"; if (( un > 0 )); then row warn "미할당 샤드" "${un}개 — 단일 노드에서 replica 를 쓰면 yellow 가 됩니다. (replica 0 권장)"; else row ok "미할당 샤드" "0개"; fi
      pt="$(jq -r '.number_of_pending_tasks' <<<"$h")"; if (( pt > 0 )); then row warn "대기 작업" "${pt}개"; fi
    else row crit "클러스터 상태" "조회 실패"; fi
    jv="$(es "/_nodes/stats/jvm?filter_path=nodes.*.jvm.mem.heap_used_percent" || true)"; hp="$(jq -r '[.nodes[]?.jvm.mem.heap_used_percent]|max // empty' <<<"$jv" 2>/dev/null || true)"
    if [[ -n "$hp" ]]; then if (( hp >= 90 )); then st=crit; elif (( hp >= 75 )); then st=warn; else st=ok; fi; row "$st" "JVM Heap" "${hp}%  (75% 이상이 계속되면 Heap 증설을 검토하세요)"; fi
    ie="$(es "/_all/_ilm/explain?only_errors=true&filter_path=indices" || true)"; ic="$(jq -r '(.indices // {})|length' <<<"$ie" 2>/dev/null || echo "")"
    if [[ "$ic" =~ ^[0-9]+$ ]]; then if (( ic > 0 )); then row warn "ILM 오류" "${ic}개 인덱스에서 ILM 오류 — $(jq -r '.indices|keys|.[0:2]|join(", ")' <<<"$ie")"; else row ok "ILM 오류" "없음"; fi; fi
    ro="$(es "/_all/_settings/index.blocks.read_only_allow_delete?flat_settings=true&filter_path=*.settings" || true)"; rc="$(jq -r '[to_entries[]|select(.value.settings["index.blocks.read_only_allow_delete"]=="true")]|length' <<<"$ro" 2>/dev/null || echo "")"
    if [[ "$rc" =~ ^[0-9]+$ ]]; then if (( rc > 0 )); then row crit "읽기 전용 인덱스" "${rc}개 — 디스크가 가득 차 Elasticsearch 가 쓰기를 막았습니다. 공간 확보 후 해제가 필요합니다."; else row ok "읽기 전용 인덱스" "없음"; fi; fi
  else row crit "Elasticsearch" "연결할 수 없습니다. ($URL) 서비스 상태와 비밀번호를 확인하세요."; fi
fi

# ---------------------------------------------------------------- ingest
if want ingest; then
  section "수집·처리 상태"
  if tf "$PROXYSG_FLOW_ENABLED"; then
    cf="${ELK_CRON_FILE:-}"
    if [[ -z "$cf" ]]; then for _c in /etc/cron.d/elk-proxysg-log-process /etc/cron.d/elk-guide-log-process; do if [[ -f "$_c" ]]; then cf="$_c"; break; fi; done; fi
    if [[ -n "$cf" && -f "$cf" ]]; then row ok "처리 스크립트 cron" "$(grep -v '^[#A-Z]' "$cf" | head -1 | awk '{print $1,$2,$3,$4,$5}')  ($cf)"; else row crit "처리 스크립트 cron" "cron 파일이 없습니다: ${cf:-/etc/cron.d/elk-proxysg-log-process} (이전 버전은 /etc/cron.d/elk-guide-log-process)"; fi
    if [[ -f "$PROXYSG_PROCESS_LOG" ]]; then
      lt="$(grep -E '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8}\]' "$PROXYSG_PROCESS_LOG" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')"; ec="$(tail -n 500 "$PROXYSG_PROCESS_LOG" | grep -c ' ERROR' || true)"; wc_="$(tail -n 500 "$PROXYSG_PROCESS_LOG" | grep -c ' WARNING' || true)"
      row info "처리 로그 마지막 기록" "${lt:-없음}  ($PROXYSG_PROCESS_LOG)"
      if (( ec > 0 )); then row warn "처리 오류(최근 500줄)" "ERROR ${ec}건 — 복사/검증에 실패한 파일이 있습니다."; else row ok "처리 오류(최근 500줄)" "없음${wc_:+ (WARNING ${wc_}건)}"; fi
    else row warn "처리 로그" "로그 파일이 없습니다: $PROXYSG_PROCESS_LOG (스크립트가 아직 실행되지 않았을 수 있음)"; fi
    for t in "${TYPES[@]}"; do
      IFS='|' read -r nm src _ prc _ <<<"$t"
      read -r n _ _ old <<<"$(dir_stat "$prc")"
      if [[ "$n" =~ ^[0-9]+$ ]]; then
        if (( n == 0 )); then row ok "처리 대기 $nm" "Logstash 처리 폴더가 비어 있음 (밀린 파일 없음)"
        else a=$((NOW-old)); if (( a > 12*3600 )); then st=crit; elif (( a > 2*3600 )); then st=warn; else st=ok; fi; row "$st" "처리 대기 $nm" "${n}개 대기 · 가장 오래된 파일 $(age_h "$a")"; fi
      fi
      read -r n _ _ old <<<"$(dir_stat "$src")"
      if [[ "$n" =~ ^[0-9]+$ ]] && (( n > 0 )); then a=$((NOW-old)); if (( a > STALE_H*3600 )); then row warn "수신 미처리 $nm" "수신 폴더에 ${n}개 · 가장 오래된 파일 $(age_h "$a") — 처리 스크립트(cron)가 돌지 않을 수 있습니다."; fi; fi
    done
  else row info "처리 스크립트" "사용 안 함 (PROXYSG_FLOW_ENABLED=false)"; fi
  if tf "$LOGSTASH_API_ENABLED" && (( HAVE_JQ )); then
    ev="$(curl -sS --max-time 5 "http://${LOGSTASH_API_HOST}:${LOGSTASH_API_PORT}/_node/stats/events" 2>/dev/null || true)"
    if jq -e '.events.in' >/dev/null 2>&1 <<<"$ev"; then row info "Logstash 이벤트" "in $(num_h "$(jq -r '.events.in' <<<"$ev")") · filtered $(num_h "$(jq -r '.events.filtered' <<<"$ev")") · out $(num_h "$(jq -r '.events.out' <<<"$ev")")  (재시작 이후 누적)"
    else row warn "Logstash 이벤트" "Logstash API(${LOGSTASH_API_HOST}:${LOGSTASH_API_PORT})에 연결할 수 없습니다."; fi
  fi
  le="$(journalctl -u logstash --since '24 hours ago' -p err --no-pager -q 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$le" =~ ^[0-9]+$ ]]; then if (( le > 0 )); then row warn "Logstash 오류 로그(24시간)" "${le}줄 — journalctl -u logstash -p err --since '24 hours ago'"; else row ok "Logstash 오류 로그(24시간)" "없음"; fi; fi
fi

# ---------------------------------------------------------------- cert
cert_days() { local f="$1" e; e="$(openssl x509 -enddate -noout -in "$f" 2>/dev/null | cut -d= -f2)"; [[ -n "$e" ]] || return 1; echo $(( ( $(date -d "$e" +%s) - NOW ) / 86400 )); }
if want cert; then
  section "인증서 만료일"
  any=0
  for pair in "Elasticsearch CA:$CA" "Elasticsearch 서버(pem):/etc/elasticsearch/certs/pem/http.crt" "Elasticsearch transport(pem):/etc/elasticsearch/certs/pem/transport.crt" "Nginx:$( tf "$INSTALL_NGINX" && echo "$NGINX_TLS_CERT_FILE" || echo "")"; do
    lab="${pair%%:*}"; f="${pair#*:}"; [[ -n "$f" && -f "$f" ]] || continue; any=1
    if dd_="$(cert_days "$f")"; then if (( dd_ < 7 )); then st=crit; elif (( dd_ < 30 )); then st=warn; else st=ok; fi; row "$st" "인증서 $lab" "만료까지 ${dd_}일  ($f)"; else row warn "인증서 $lab" "읽을 수 없음 ($f)"; fi
  done
  if command -v openssl >/dev/null 2>&1 && [[ "$URL" == https://* ]]; then
    served="$(echo | timeout 8 openssl s_client -connect "127.0.0.1:${ES_HTTP_PORT}" -servername localhost 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || true)"
    if [[ -n "$served" ]]; then any=1; sd=$(( ( $(date -d "$served" +%s) - NOW ) / 86400 )); if (( sd < 7 )); then st=crit; elif (( sd < 30 )); then st=warn; else st=ok; fi; row "$st" "인증서 Elasticsearch(제공 중)" "만료까지 ${sd}일  (지금 9200 포트가 실제로 내보내는 인증서)"
      (( sd < 30 )) && sub "연장: sudo elk-patch ES_CA_DAYS=7300 ES_CERT_DAYS=7300   (20년, Elasticsearch 를 한 번 재시작합니다)"
    fi
  fi
  (( any )) || row info "인증서" "점검할 인증서 파일이 없습니다."
fi

# ---------------------------------------------------------------- os
if want os; then
  section "OS 업데이트·장애"
  up="$(apt list --upgradable 2>/dev/null | tail -n +2 | grep -c . || true)"; sec="$(apt list --upgradable 2>/dev/null | grep -ci security || true)"
  if [[ "$up" =~ ^[0-9]+$ ]]; then if (( sec > 0 )); then row warn "대기 중인 업데이트" "${up}개 (보안 ${sec}개) — sudo apt-get upgrade"; elif (( up > 0 )); then row info "대기 중인 업데이트" "${up}개 (보안 업데이트 없음)"; else row ok "대기 중인 업데이트" "없음"; fi; fi
  fl="$(systemctl --failed --no-legend --plain 2>/dev/null | grep -c . || true)"
  if [[ "$fl" =~ ^[0-9]+$ ]]; then if (( fl > 0 )); then row warn "실패한 서비스" "${fl}개 — $(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | head -3 | tr '\n' ' ')"; else row ok "실패한 서비스" "없음"; fi; fi
  oom="$(journalctl -k --since '7 days ago' --no-pager -q 2>/dev/null | grep -ciE 'out of memory|oom-kill' || true)"
  if [[ "$oom" =~ ^[0-9]+$ ]]; then if (( oom > 0 )); then row crit "OOM 기록(7일)" "${oom}건 — 메모리 부족으로 프로세스가 종료된 적이 있습니다."; else row ok "OOM 기록(7일)" "없음"; fi; fi
fi

# ---------------------------------------------------------------- 요약
heading "점검 요약"
for ((_i=0;_i<${#SEC_NAME[@]};_i++)); do
  case "${SEC_ST[_i]}" in 0) _g="✔"; _c="$G" ;; 1) _g="⚠"; _c="$Y" ;; *) _g="✖"; _c="$X" ;; esac
  printf '  %s%s%s %s' "$_c" "$_g" "$R" "$(pad "${SEC_NAME[_i]}" 22)"
  if (( (_i+1) % 3 == 0 || _i == ${#SEC_NAME[@]}-1 )); then printf '\n'; fi
done
printf '\n  %s✔ 정상 %d%s     %s⚠ 주의 %d%s     %s✖ 이상 %d%s\n' "$G" "$N_OK" "$R" "$Y" "$N_WARN" "$R" "$X" "$N_CRIT" "$R"
if (( ${#ISS_ST[@]} > 0 )); then
  heading "조치 필요  (이상 ${N_CRIT} · 주의 ${N_WARN})"
  for _p in crit warn; do
    for ((_i=0;_i<${#ISS_ST[@]};_i++)); do
      [[ "${ISS_ST[_i]}" == "$_p" ]] || continue
      if [[ "$_p" == crit ]]; then _g="✖"; _c="$X"; else _g="⚠"; _c="$Y"; fi
      printf '  %s%s%s %s%s › %s%s\n' "$_c" "$_g" "$R" "$B" "${ISS_SEC[_i]}" "${ISS_LB[_i]}" "$R"
      wrapv "${ISS_VAL[_i]}" $((COLS-6))
      for _l in "${WL[@]}"; do printf '      %s%s%s\n' "$D" "$_l" "$R"; done
    done
  done
else
  printf '\n  %s✔ 주의·이상 항목이 없습니다. 모든 점검이 정상입니다.%s\n' "$G" "$R"
fi
printf '\n'
(( N_CRIT > 0 )) && exit 2
(( N_WARN > 0 )) && exit 1
exit 0
