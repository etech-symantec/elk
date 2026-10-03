#!/usr/bin/env bash
# elk-color.sh — 설치 화면 색상 (install-elk.sh 와 one-click 설치 파일이 함께 사용)
#
# 원칙
#  · 색은 "화면에 보여 줄 때만" 입힙니다. 로그 파일(/var/log/elk-auto-install.log 등)은 항상 색 없는 일반 텍스트입니다.
#  · 터미널이 아니면(파일/파이프/systemd) 색을 쓰지 않습니다. 강제로 켜려면 ELK_COLOR=always, 끄려면 ELK_COLOR=never 또는 NO_COLOR=1.
#  · 색을 꺼도 출력 문장은 그대로입니다. ([INFO] [WARN] [ERROR] 같은 글자는 바뀌지 않음)
#
# 중요도(태그/배경색)         주제(INFO 문장의 글자색)
#   ERROR/FAIL  흰 글자 + 빨강    Kibana  보라        Elasticsearch/인덱스  하늘색     FTP/처리 스크립트  분홍
#   WARN        검정 + 노랑       Logstash 청록       Nginx/TLS  모래색              방화벽  갈색
#   OK/PASS/완료 검정 + 초록      패키지  연보라       시스템/디스크  강철색
#   INFO        회색 태그
#
# 사용:  elk_color_init [auto|always|never]
#        some_command 2>&1 | elk_paint_stream        # 한 줄씩 색을 입혀 출력 (색이 꺼져 있으면 그대로 통과)
#        elk_say INFO|OK|WARN|ERROR "메시지"          # 색이 꺼져 있으면 예전과 똑같이 "[LEVEL] 메시지"
#        elk_banner ok|fail|neutral "제목" ["부제"...]  # 완료(초록)/실패(빨강) 상자

ELK_COLOR_ON=0
ELK_STREAM_PAINTED=0   # 1이면 이 프로세스의 출력이 이미 "| elk_paint_stream" 으로 흘러가므로, elk_say/elk_banner 는 색 없는 글자만 내보낸다(그래야 로그 파일에 색이 섞이지 않음)
_ELK_BAR=""            # 줄 바꿈을 기다리는 구분선 한 줄
_ELK_BANNER=""         # none | ok | fail | neutral : 지금 안에 있는 상자 종류
_ELK_OPEN=0            # 1이면 다음 줄이 방금 열린 상자의 제목
_ELK_RE_LEVEL='^([[:space:]]*)(\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8}\] )?\[(INFO|WARN|ERROR|OK|PASS|FAIL|SKIP|DIAG|DEBUG)\] ?(.*)$'
_ELK_RE_PROG='^\[([^]]+)\] \[([#-]+)\] ([0-9]+)% ?(.*)$'
_ELK_RE_STATE='^([[:space:]]*[^:]{1,34}:[[:space:]]*)(active|activating|inactive|failed|n/a)$'
_ELK_RE_BAR_EQ='^={20,}$'
_ELK_RE_BAR_EX='^!{20,}$'

elk_color_init() {
  local mode="${1:-${ELK_COLOR:-auto}}"
  case "${mode,,}" in
    always|1|true|yes|on) ELK_COLOR_ON=1 ;;
    never|0|false|no|off) ELK_COLOR_ON=0 ;;
    *) if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then ELK_COLOR_ON=1; else ELK_COLOR_ON=0; fi ;;
  esac
  if (( ELK_COLOR_ON )); then
    K_RST=$'\033[0m'; K_BOLD=$'\033[1m'; K_DIM=$'\033[2m'
    K_ERRTAG=$'\033[1;97;41m'; K_WARNTAG=$'\033[1;30;43m'; K_OKTAG=$'\033[1;30;42m'; K_INFOTAG=$'\033[2;37m'; K_DIAGTAG=$'\033[1;97;45m'; K_SKIPTAG=$'\033[2;37m'
    K_ERR=$'\033[1;91m'; K_WARN=$'\033[93m'; K_OK=$'\033[1;92m'; K_BAR=$'\033[2;36m'; K_TITLE=$'\033[1;97m'
    K_T_OS=$'\033[38;5;110m'; K_T_PKG=$'\033[38;5;139m'; K_T_ES=$'\033[38;5;75m'; K_T_KB=$'\033[38;5;177m'
    K_T_LS=$'\033[38;5;80m';  K_T_NGX=$'\033[38;5;180m'; K_T_FTP=$'\033[38;5;175m'; K_T_FW=$'\033[38;5;137m'
    K_BAN_OK=$'\033[1;30;102m'; K_BAN_ERR=$'\033[1;97;101m'
  else
    K_RST=""; K_BOLD=""; K_DIM=""; K_ERRTAG=""; K_WARNTAG=""; K_OKTAG=""; K_INFOTAG=""; K_DIAGTAG=""; K_SKIPTAG=""
    K_ERR=""; K_WARN=""; K_OK=""; K_BAR=""; K_TITLE=""; K_T_OS=""; K_T_PKG=""; K_T_ES=""; K_T_KB=""; K_T_LS=""; K_T_NGX=""; K_T_FTP=""; K_T_FW=""; K_BAN_OK=""; K_BAN_ERR=""
  fi
  _ELK_BAR=""; _ELK_BANNER=""; _ELK_OPEN=0
}

# 주제 -> _ELK_TOPIC (색 코드, 없으면 빈 문자열). 먼저 맞는 규칙이 이긴다.
_elk_topic() {
  local m="${1,,}"
  _ELK_TOPIC=""
  if   [[ "$m" == *kibana* || "$m" == *"data view"* || "$m" == *"서비스 토큰"* ]]; then _ELK_TOPIC="$K_T_KB"
  elif [[ "$m" == *logstash* || "$m" == *pipeline* || "$m" == *파이프라인* || "$m" == *sincedb* || "$m" == *keystore* ]]; then _ELK_TOPIC="$K_T_LS"
  elif [[ "$m" == *elasticsearch* || "$m" == *elastic* || "$m" == *ilm* || "$m" == *index* || "$m" == *인덱스* || "$m" == *template* || "$m" == *snapshot* || "$m" == *slm* || "$m" == *클러스터* ]]; then _ELK_TOPIC="$K_T_ES"
  elif [[ "$m" == *nginx* || "$m" == *https* || "$m" == *인증서* || "$m" == *certificate* ]]; then _ELK_TOPIC="$K_T_NGX"
  elif [[ "$m" == *ftp* || "$m" == *proxysg* || "$m" == *cloud* || "$m" == *"로그 처리 스크립트"* || "$m" == *cron* || "$m" == *수신* || "$m" == *"처리 폴더"* || "$m" == *"file ingest"* || "$m" == *"파일 수집"* ]]; then _ELK_TOPIC="$K_T_FTP"
  elif [[ "$m" == *ufw* || "$m" == *방화벽* || "$m" == *firewall* ]]; then _ELK_TOPIC="$K_T_FW"
  elif [[ "$m" == *apt* || "$m" == *패키지* || "$m" == *저장소* || "$m" == *다운로드* || "$m" == *gpg* || "$m" == *dpkg* ]]; then _ELK_TOPIC="$K_T_PKG"
  elif [[ "$m" == *hostname* || "$m" == *timezone* || "$m" == *ntp* || "$m" == *swap* || "$m" == *sysctl* || "$m" == *커널* || "$m" == *메모리* || "$m" == *디스크* || "$m" == *lvm* || "$m" == *"루트 lv"* || "$m" == os:* || "$m" == *ubuntu* ]]; then _ELK_TOPIC="$K_T_OS"
  fi
}

_elk_is_success_text() {
  local m="$1"
  [[ "$m" == *완료* || "$m" == *정상* || "$m" == *성공* || "$m" == *통과* ]] || return 1
  [[ "$m" == *실패* || "$m" == *오류* || "$m" == *불가* || "$m" == *않* || "$m" == *못* ]] && return 1
  return 0
}

_elk_emit_bar() { # kind
  local c="$K_BAR"
  case "$1" in ok) c="$K_OK";; fail) c="$K_ERR";; esac
  printf '%s%s%s\n' "$c" "$2" "$K_RST"
}

# 한 줄을 받아 색을 입혀 출력한다. (구분선은 다음 줄을 보고 색을 정하므로 한 줄 늦게 나올 수 있음 → elk_paint_flush)
elk_paint_line() {
  local line="${1%$'\r'}" ts="" lvl="" msg="" lead="" tag="" body="" c="" L R
  if (( ! ELK_COLOR_ON )); then printf '%s\n' "$line"; return 0; fi
  # --- 구분선
  if [[ "$line" =~ $_ELK_RE_BAR_EQ ]]; then
    if [[ -n "$_ELK_BANNER" && "$_ELK_BANNER" != "none" ]]; then _elk_emit_bar "$_ELK_BANNER" "$line"; _ELK_BANNER="none"; return 0; fi
    if [[ -n "$_ELK_BAR" ]]; then _elk_emit_bar neutral "$_ELK_BAR"; fi
    _ELK_BAR="$line"; return 0
  fi
  if [[ "$line" =~ $_ELK_RE_BAR_EX ]]; then
    if [[ -n "$_ELK_BAR" ]]; then _elk_emit_bar neutral "$_ELK_BAR"; _ELK_BAR=""; fi
    if [[ "$_ELK_BANNER" == "fail" ]]; then _elk_emit_bar fail "$line"; _ELK_BANNER="none"; _ELK_OPEN=0
    else _elk_emit_bar fail "$line"; _ELK_BANNER="fail"; _ELK_OPEN=1; fi
    return 0
  fi
  # --- 구분선 바로 다음 줄: ✔ / ✖ 로 시작하면 완료/실패 상자의 제목, 아니면 일반 구분선(그 줄은 아래에서 평소처럼 처리)
  if [[ -n "$_ELK_BAR" ]]; then
    if [[ "$line" == " ✔"* ]]; then
      _ELK_BANNER="ok"; _elk_emit_bar ok "$_ELK_BAR"; _ELK_BAR=""
      printf '%s%s%s\n' "$K_BAN_OK" "$line" "$K_RST"; return 0
    elif [[ "$line" == " ✖"* ]]; then
      _ELK_BANNER="fail"; _ELK_OPEN=0; _elk_emit_bar fail "$_ELK_BAR"; _ELK_BAR=""
      printf '%s%s%s\n' "$K_BAN_ERR" "$line" "$K_RST"; return 0
    fi
    _elk_emit_bar neutral "$_ELK_BAR"; _ELK_BAR=""
  fi
  if [[ "$_ELK_BANNER" == "fail" ]]; then   # 실패 상자: 첫 줄은 제목 스타일, 안쪽 줄은 빨강
    if (( _ELK_OPEN )); then _ELK_OPEN=0; printf '%s%s%s\n' "$K_BAN_ERR" "$line" "$K_RST"; else printf '%s%s%s\n' "$K_ERR" "$line" "$K_RST"; fi
    return 0
  fi
  # --- [시각] [LEVEL] 메시지
  if [[ "$line" =~ $_ELK_RE_LEVEL ]]; then
    lead="${BASH_REMATCH[1]}"; ts="${BASH_REMATCH[2]}"; lvl="${BASH_REMATCH[3]}"; msg="${BASH_REMATCH[4]}"
    [[ -n "$ts" ]] && ts="${K_DIM}${ts%% }${K_RST} "
    case "$lvl" in
      ERROR|FAIL) printf '%s%s%s %s%s%s\n' "$lead" "$ts" "${K_ERRTAG} ${lvl} ${K_RST}" "$K_ERR" "$msg" "$K_RST" ;;
      WARN)       printf '%s%s%s %s%s%s\n' "$lead" "$ts" "${K_WARNTAG} WARN ${K_RST}" "$K_WARN" "$msg" "$K_RST" ;;
      OK|PASS)    printf '%s%s%s %s%s%s\n' "$lead" "$ts" "${K_OKTAG} ${lvl} ${K_RST}" "$K_OK" "$msg" "$K_RST" ;;
      SKIP)       printf '%s%s%s %s%s%s\n' "$lead" "$ts" "${K_SKIPTAG} SKIP ${K_RST}" "$K_DIM" "$msg" "$K_RST" ;;
      DIAG)       printf '%s%s%s %s\n' "$lead" "$ts" "${K_DIAGTAG} DIAG ${K_RST}" "$msg" ;;
      *)          # INFO / DEBUG
        if _elk_is_success_text "$msg"; then
          printf '%s%s%s %s✔ %s%s\n' "$lead" "$ts" "${K_INFOTAG}INFO${K_RST}" "$K_OK" "$msg" "$K_RST"
        else
          _elk_topic "$msg"
          printf '%s%s%s %s%s%s\n' "$lead" "$ts" "${K_INFOTAG}INFO${K_RST}" "$_ELK_TOPIC" "$msg" "${_ELK_TOPIC:+$K_RST}"
        fi ;;
    esac
    return 0
  fi
  # --- 진행률 줄:  [전체] [####------] 38% 설명
  if [[ "$line" =~ $_ELK_RE_PROG ]]; then
    tag="${BASH_REMATCH[1]}"; body="${BASH_REMATCH[2]}"; c="${BASH_REMATCH[3]}"; msg="${BASH_REMATCH[4]}"
    L="${body%%-*}"; R="${body#"$L"}"; L="${L//#/█}"; R="${R//-/░}"
    local bc=$'\033[96m'; (( c >= 100 )) && bc="$K_OK"
    printf '%s[%s]%s %s%s%s%s%s%s %s%s%%%s %s\n' "$K_BOLD" "$tag" "$K_RST" "$bc" "$L" "$K_RST" "$K_DIM" "$R" "$K_RST" "$K_BOLD" "$c" "$K_RST" "$msg"
    return 0
  fi
  # --- 단계 제목:  " [1/3] ..."  /  " ELK ..."
  if [[ "$line" == " ["[0-9]*"/"[0-9]*"] "* || "$line" == " ELK "* ]]; then printf '%s%s%s\n' "$K_TITLE" "$line" "$K_RST"; return 0; fi
  # --- 서비스 상태 값:  " Kibana : active"
  if [[ "$line" =~ $_ELK_RE_STATE ]]; then
    L="${BASH_REMATCH[1]}"; R="${BASH_REMATCH[2]}"
    case "$R" in active) c="$K_OK";; activating) c="$K_WARN";; failed) c="$K_ERR";; inactive) c="$K_WARN";; *) c="$K_DIM";; esac
    printf '%s%s%s%s%s\n' "$L" "$c" "$R" "$K_RST" ""; return 0
  fi
  # --- apt 오류/경고
  if [[ "$line" == E:\ * || "$line" == Err:* ]]; then printf '%s%s%s\n' "$K_ERR" "$line" "$K_RST"; return 0; fi
  if [[ "$line" == W:\ * ]]; then printf '%s%s%s\n' "$K_WARN" "$line" "$K_RST"; return 0; fi
  printf '%s\n' "$line"
}

elk_paint_flush() {
  if (( ELK_COLOR_ON )) && [[ -n "$_ELK_BAR" ]]; then _elk_emit_bar neutral "$_ELK_BAR"; fi
  _ELK_BAR=""
}

elk_paint_stream() {
  local line
  if (( ! ELK_COLOR_ON )); then cat; return; fi
  while IFS= read -r line || [[ -n "$line" ]]; do elk_paint_line "$line"; done
  elk_paint_flush
}

# 한 줄 메시지: 색이 꺼져 있으면 예전과 똑같은 "[LEVEL] 메시지"
elk_say() {
  local lvl="$1"; shift
  local out
  if (( ELK_COLOR_ON && ! ELK_STREAM_PAINTED )); then
    out="$(_ELK_BAR=""; _ELK_BANNER=""; _ELK_OPEN=0; elk_paint_line "[$lvl] $*")"
  else
    out="[$lvl] $*"
  fi
  if [[ "$lvl" == "ERROR" || "$lvl" == "FAIL" ]]; then printf '%s\n' "$out" >&2; else printf '%s\n' "$out"; fi
}

# 상자: 색이 꺼져 있어도 모양은 같다. ok=완료(===), fail=실패(!!!), neutral=일반(===)
elk_banner() {
  local kind="$1" title="$2"; shift 2
  local bar glyph="" line
  case "$kind" in ok) glyph="✔ ";; fail) glyph="✖ ";; esac
  if [[ "$kind" == "fail" ]]; then bar="$(printf '%*s' 79 '' | tr ' ' '!')"; else bar="$(printf '%*s' 79 '' | tr ' ' '=')"; fi
  local out=""
  out+="$bar"$'\n'" ${glyph}${title}"$'\n'
  for line in "$@"; do out+=" ${line}"$'\n'; done
  out+="$bar"
  if (( ELK_COLOR_ON && ! ELK_STREAM_PAINTED )); then
    local save_bar="$_ELK_BAR" save_ban="$_ELK_BANNER" save_open="$_ELK_OPEN"; _ELK_BAR=""; _ELK_BANNER=""; _ELK_OPEN=0
    local l; while IFS= read -r l; do elk_paint_line "$l"; done <<<"$out"; elk_paint_flush
    _ELK_BAR="$save_bar"; _ELK_BANNER="$save_ban"; _ELK_OPEN="$save_open"
  else
    printf '%s\n' "$out"
  fi
}

# 색 안내 한 줄 (색이 켜져 있을 때만)
elk_legend() {
  (( ELK_COLOR_ON && ! ELK_STREAM_PAINTED )) || return 0
  printf '%s색 안내%s  %s■%s 시스템 %s■%s 패키지 %s■%s Elasticsearch %s■%s Kibana %s■%s Logstash %s■%s Nginx/TLS %s■%s FTP/처리 스크립트 %s■%s 방화벽   %s OK %s %s WARN %s %s ERROR %s\n' \
    "$K_DIM" "$K_RST" "$K_T_OS" "$K_RST" "$K_T_PKG" "$K_RST" "$K_T_ES" "$K_RST" "$K_T_KB" "$K_RST" "$K_T_LS" "$K_RST" "$K_T_NGX" "$K_RST" "$K_T_FTP" "$K_RST" "$K_T_FW" "$K_RST" "$K_OKTAG" "$K_RST" "$K_WARNTAG" "$K_RST" "$K_ERRTAG" "$K_RST"
}
