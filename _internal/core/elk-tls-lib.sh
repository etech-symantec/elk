#!/usr/bin/env bash
# elk-tls-lib.sh — Elasticsearch / Nginx 인증서 발급·갱신 공용 함수 (설치기와 elk-patch 가 함께 사용합니다)
#
#   source elk-tls-lib.sh   로 불러 쓰는 라이브러리입니다. (직접 실행하지 않습니다)
#   필요: openssl 1.1.1 이상 (Ubuntu 22.04 / 24.04 기본), date, awk
#
# 방식: Elasticsearch 가 처음 시작할 때 자동으로 만드는 인증서(CA 약 3년, 서버 인증서 약 2년)를 "같은 CA 키로" 유효기간을 늘려 다시 발급합니다.
#   · CA 인증서  : 같은 키·같은 이름으로 새 유효기간의 인증서를 다시 만듭니다. (Kibana/Logstash/클라이언트가 믿는 CA 가 바뀌지 않음)
#   · HTTP·transport 인증서 : 그 CA 로 새로 서명합니다. 주소(SAN)는 기존 인증서의 것을 이어받고 이 서버의 이름·IP 를 더합니다.
#   · 결과는 PEM 파일(/etc/elasticsearch/certs/pem/)로 저장하고, elasticsearch.yml 은 그 PEM 을 가리키게 합니다. (tls_yml_switch_to_pem)
# 실패하면 아무것도 덮어쓰지 않고 1 이상을 돌려줍니다. 오류 설명은 TLS_ERR 에 담깁니다.

declare -F log  >/dev/null 2>&1 || log()  { echo "[INFO] $*"; }
declare -F warn >/dev/null 2>&1 || warn() { echo "[WARN] $*" >&2; }
TLS_ERR=""
tls_err() { TLS_ERR="$*"; return 1; }

tls_valid_days() { [[ "${1:-}" =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 36500 )); }
tls_serial() { printf '0x%s' "$(openssl rand -hex 16)"; }

# ---- 인증서 읽기 --------------------------------------------------------------------------------------------------
tls_enddate_epoch() { local e; e="$(openssl x509 -noout -enddate -in "$1" 2>/dev/null | cut -d= -f2)"; [[ -n "$e" ]] || return 1; date -d "$e" +%s; }
tls_days_left()     { local ep; ep="$(tls_enddate_epoch "$1")" || return 1; echo $(( (ep - $(date +%s)) / 86400 )); }
tls_subject()       { openssl x509 -noout -subject -nameopt RFC2253 -in "$1" 2>/dev/null | sed 's/^subject= *//'; }
tls_pubkey_hash()   { # 인증서 또는 개인키의 공개키 지문 (둘이 짝인지 비교할 때 사용)
  local f="$1" kind="${2:-cert}"
  if [[ "$kind" == key ]]; then openssl pkey -in "$f" -pubout 2>/dev/null | openssl sha256 | awk '{print $NF}'
  else openssl x509 -in "$f" -noout -pubkey 2>/dev/null | openssl sha256 | awk '{print $NF}'; fi
}
tls_san_from_cert() { # "DNS:a,DNS:b,IP:1.2.3.4"
  openssl x509 -noout -ext subjectAltName -in "$1" 2>/dev/null | tail -n +2 | sed 's/^[[:space:]]*//; s/IP Address:/IP:/g; s/[[:space:]]*,[[:space:]]*/,/g' | tr -d '\n'
}
tls_is_ca() { openssl x509 -noout -ext basicConstraints -in "$1" 2>/dev/null | grep -q 'CA:TRUE'; }
tls_is_selfsigned() { [[ "$(openssl x509 -noout -subject -in "$1" 2>/dev/null | sed 's/^subject= *//')" == "$(openssl x509 -noout -issuer -in "$1" 2>/dev/null | sed 's/^issuer= *//')" ]]; }

# ---- SAN(주소 목록) ----------------------------------------------------------------------------------------------
_tls_classify() { local x="${1// /}"; [[ -n "$x" ]] || return 0; if [[ "$x" == DNS:* || "$x" == IP:* ]]; then echo "$x"; elif [[ "$x" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ || "$x" == *:* ]]; then echo "IP:$x"; else echo "DNS:$x"; fi; }
tls_merge_sans() { # 여러 개의 쉼표 목록을 중복 없이 합친다
  local -A seen=(); local out=() item part
  for item in "$@"; do
    IFS=',' read -ra parts <<<"$item"
    for part in "${parts[@]}"; do part="$(_tls_classify "$part")"; [[ -n "$part" && -z "${seen[$part]:-}" ]] && { seen[$part]=1; out+=("$part"); }; done
  done
  local IFS=','; printf '%s' "${out[*]}"
}
tls_default_sans() { # 이 서버에서 접속할 때 쓰는 이름·IP.  인자: 추가로 넣을 이름/IP (쉼표)
  local extra="${1:-}" h fq ips=""
  h="$(hostname 2>/dev/null || true)"; fq="$(hostname -f 2>/dev/null || true)"; ips="$(hostname -I 2>/dev/null | tr ' ' ',' | sed 's/,$//' || true)"
  tls_merge_sans "DNS:localhost,IP:127.0.0.1,IP:::1" "${h:+DNS:$h}" "${fq:+DNS:$fq}" "$ips" "$extra"
}

# ---- 발급 --------------------------------------------------------------------------------------------------------
tls_new_ca() { # keyout crtout days cn
  local key="$1" crt="$2" days="$3" cn="${4:-ELK Auto CA}"
  tls_valid_days "$days" || { tls_err "CA 유효기간(일)이 올바르지 않습니다: $days"; return 1; }
  openssl genrsa -out "$key" 4096 >/dev/null 2>&1 || { tls_err "CA 키 생성 실패"; return 1; }
  openssl req -x509 -new -key "$key" -sha256 -days "$days" -subj "/CN=$cn" -set_serial "$(tls_serial)" \
    -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" -addext "subjectKeyIdentifier=hash" -out "$crt" 2>/dev/null \
    || { tls_err "CA 인증서 생성 실패"; return 1; }
}
tls_renew_ca() { # cakey oldcrt outcrt days — 같은 키·같은 이름·같은 확장으로 새 유효기간의 CA 인증서
  local key="$1" old="$2" out="$3" days="$4"
  tls_valid_days "$days" || { tls_err "CA 유효기간(일)이 올바르지 않습니다: $days"; return 1; }
  [[ "$(tls_pubkey_hash "$key" key)" == "$(tls_pubkey_hash "$old" cert)" ]] || { tls_err "CA 키가 CA 인증서와 짝이 맞지 않습니다."; return 1; }
  openssl x509 -in "$old" -signkey "$key" -days "$days" -set_serial "$(tls_serial)" -out "$out" 2>/dev/null || { tls_err "CA 인증서 갱신 실패"; return 1; }
  [[ "$(tls_subject "$out")" == "$(tls_subject "$old")" ]] || { tls_err "갱신한 CA 의 이름이 달라졌습니다."; return 1; }
  local want=$days got; got="$(tls_days_left "$out")" || { tls_err "갱신한 CA 를 읽을 수 없습니다."; return 1; }
  (( got >= want - 2 )) || { tls_err "갱신한 CA 의 만료일이 요청과 다릅니다. (요청 ${want}일, 실제 ${got}일)"; return 1; }
}
tls_issue_leaf() { # cakey cacrt outkey outcrt days cn sans [eku]
  local cakey="$1" cacrt="$2" outkey="$3" outcrt="$4" days="$5" cn="$6" sans="$7" eku="${8:-serverAuth,clientAuth}" t left
  tls_valid_days "$days" || { tls_err "인증서 유효기간(일)이 올바르지 않습니다: $days"; return 1; }
  left="$(tls_days_left "$cacrt")" || { tls_err "CA 인증서를 읽을 수 없습니다: $cacrt"; return 1; }
  if (( days >= left )); then
    # CA 와 같은(또는 반올림 차이로 하루 긴) 기간을 요청하면 서버 인증서를 CA 보다 "하루 먼저" 끝나게 맞춘다.
    # (키 생성에 걸리는 시간 때문에 서버 인증서가 CA 보다 몇 초 늦게 끝나는 일도 막는다)
    if (( days - left <= 1 && left > 2 )); then days=$(( left - 1 )); else tls_err "서버 인증서 유효기간(${days}일)이 CA 의 남은 기간(${left}일)보다 깁니다. CA 유효기간을 더 길게 하세요."; return 1; fi
  fi
  t="$(mktemp -d)"
  if ! openssl genrsa -out "$t/k" 2048 >/dev/null 2>&1 || ! openssl req -new -key "$t/k" -subj "/CN=$cn" -out "$t/r" 2>/dev/null; then rm -rf "$t"; tls_err "서버 키/요청 생성 실패"; return 1; fi
  { echo "basicConstraints=critical,CA:FALSE"; echo "keyUsage=critical,digitalSignature,keyEncipherment"; echo "extendedKeyUsage=$eku"; echo "subjectKeyIdentifier=hash"; echo "authorityKeyIdentifier=keyid,issuer"; echo "subjectAltName=$sans"; } >"$t/ext"
  if ! openssl x509 -req -in "$t/r" -CA "$cacrt" -CAkey "$cakey" -set_serial "$(tls_serial)" -days "$days" -sha256 -extfile "$t/ext" -out "$t/c" >/dev/null 2>&1; then rm -rf "$t"; tls_err "서버 인증서 서명 실패"; return 1; fi
  if ! openssl verify -CAfile "$cacrt" "$t/c" >/dev/null 2>&1; then rm -rf "$t"; tls_err "새 서버 인증서가 CA 로 검증되지 않습니다."; return 1; fi
  cat "$t/k" >"$outkey"; cat "$t/c" >"$outcrt"; rm -rf "$t"
}

# ---- 기존 PKCS12(http.p12) 에서 CA 키/인증서 꺼내기 ---------------------------------------------------------------
# Elasticsearch 자동 보안 설정이 만든 http.p12 안에는 HTTP CA(키+인증서)와 HTTP 서버 인증서가 함께 들어 있습니다.
tls_p12_dump() { # p12 password outdir  -> outdir/ca.key ca.crt leaf.crt
  local p12="$1" pw="$2" out="$3" dump i f c k n=0 cacrt="" cakey=""
  dump="$(mktemp)"; export TLS_P12_PW="$pw"
  if ! openssl pkcs12 -in "$p12" -nodes -passin env:TLS_P12_PW >"$dump" 2>/dev/null; then
    if ! openssl pkcs12 -in "$p12" -nodes -legacy -passin env:TLS_P12_PW >"$dump" 2>/dev/null; then unset TLS_P12_PW; rm -f "$dump"; tls_err "http.p12 를 열 수 없습니다. (비밀번호가 다르거나 지원하지 않는 형식)"; return 1; fi
  fi
  unset TLS_P12_PW
  mkdir -p "$out/parts"
  awk -v d="$out/parts" '/-----BEGIN (CERTIFICATE|PRIVATE KEY|RSA PRIVATE KEY|EC PRIVATE KEY|ENCRYPTED PRIVATE KEY)-----/{n++; f=sprintf("%s/p%03d.pem",d,n); inb=1} inb{print > f} /-----END /{inb=0}' "$dump"
  rm -f "$dump"
  local leaf=""
  for f in "$out"/parts/p*.pem; do
    [[ -e "$f" ]] || continue
    if grep -q 'BEGIN CERTIFICATE' "$f"; then
      if tls_is_ca "$f" && tls_is_selfsigned "$f"; then [[ -z "$cacrt" ]] && cacrt="$f"; else [[ -z "$leaf" ]] && leaf="$f"; fi
    fi
  done
  [[ -n "$cacrt" ]] || { tls_err "http.p12 안에서 CA 인증서를 찾지 못했습니다."; return 1; }
  for f in "$out"/parts/p*.pem; do
    grep -q 'PRIVATE KEY' "$f" || continue
    if [[ "$(tls_pubkey_hash "$f" key)" == "$(tls_pubkey_hash "$cacrt" cert)" ]]; then cakey="$f"; break; fi
  done
  [[ -n "$cakey" ]] || { tls_err "http.p12 안에 CA 개인키가 없습니다. (사용자가 직접 만든 인증서일 수 있습니다)"; return 1; }
  cat "$cakey" >"$out/ca.key"; cat "$cacrt" >"$out/ca.crt"; [[ -n "$leaf" ]] && cat "$leaf" >"$out/leaf.crt"
  chmod 600 "$out/ca.key"; rm -rf "$out/parts"; return 0
}
tls_keystore_get() { # ES keystore(elasticsearch.keystore) 의 보안 설정 값
  local bin="${TLS_KEYSTORE_BIN:-/usr/share/elasticsearch/bin/elasticsearch-keystore}"
  [[ -x "$bin" ]] || return 1
  ES_PATH_CONF="${ES_PATH_CONF:-/etc/elasticsearch}" "$bin" show "$1" 2>/dev/null | tail -n1
}

# ---- Elasticsearch 인증서 한 벌(CA + HTTP + transport) 발급 -----------------------------------------------------------
# 입력(전역):  TLS_CERT_DIR(기본 /etc/elasticsearch/certs)  TLS_CA_DAYS  TLS_CERT_DAYS  TLS_EXTRA_SANS  TLS_NEW_CA_OK(1 이면 CA 를 못 찾을 때 새로 만듦)
#              TLS_ES_GROUP(기본 elasticsearch)  TLS_CN(기본: 호스트 이름)
# 결과(전역):  TLS_RESULT_MODE = renewed-pem | renewed-p12 | new-ca     TLS_RESULT_SANS = 새 인증서의 주소 목록
tls_es_reissue() {
  local d="${TLS_CERT_DIR:-/etc/elasticsearch/certs}" pem work cakey cacrt leafold="" mode sans cn grp="${TLS_ES_GROUP:-elasticsearch}" pw="" cadays="${TLS_CA_DAYS:-7300}" certdays="${TLS_CERT_DAYS:-7300}"
  tls_valid_days "$cadays" && tls_valid_days "$certdays" || { tls_err "유효기간(일)은 1~36500 사이의 숫자여야 합니다. (CA ${cadays}, 서버 ${certdays})"; return 1; }
  (( certdays <= cadays )) || { tls_err "서버 인증서 유효기간(${certdays}일)은 CA 유효기간(${cadays}일)보다 길 수 없습니다."; return 1; }
  pem="$d/pem"; work="$(mktemp -d)"; chmod 700 "$work"; cn="${TLS_CN:-$(hostname 2>/dev/null || echo elasticsearch)}"
  if [[ -s "$pem/ca.key" && -s "$pem/ca.crt" ]]; then
    cakey="$pem/ca.key"; cacrt="$pem/ca.crt"; mode=renewed-pem; leafold="$pem/http.crt"
  elif [[ -s "$d/http.p12" ]]; then
    pw="$(tls_keystore_get xpack.security.http.ssl.keystore.secure_password || true)"
    if tls_p12_dump "$d/http.p12" "$pw" "$work"; then cakey="$work/ca.key"; cacrt="$work/ca.crt"; mode=renewed-p12; leafold="$work/leaf.crt"
    elif (( ${TLS_NEW_CA_OK:-0} )); then warn "기존 CA 를 재사용할 수 없어 새 CA 를 만듭니다: $TLS_ERR"; mode=new-ca
    else rm -rf "$work"; return 1; fi
  elif (( ${TLS_NEW_CA_OK:-0} )); then mode=new-ca
  else rm -rf "$work"; tls_err "기존 CA 를 찾을 수 없습니다. ($pem/ca.key 도, $d/http.p12 도 없음)"; return 1; fi
  if [[ "$mode" == new-ca ]]; then
    tls_new_ca "$work/ca.key" "$work/ca.new.crt" "$cadays" "ELK Auto CA ($cn)" || { rm -rf "$work"; return 1; }
    cakey="$work/ca.key"; cacrt="$work/ca.new.crt"
  else
    tls_renew_ca "$cakey" "$cacrt" "$work/ca.new.crt" "$cadays" || { rm -rf "$work"; return 1; }
    cacrt="$work/ca.new.crt"
  fi
  sans="$(tls_default_sans "${TLS_EXTRA_SANS:-}")"
  if [[ -n "$leafold" && -s "$leafold" ]]; then sans="$(tls_merge_sans "$(tls_san_from_cert "$leafold")" "$sans")"; fi
  tls_issue_leaf "$cakey" "$cacrt" "$work/http.key" "$work/http.crt" "$certdays" "$cn" "$sans" serverAuth,clientAuth || { rm -rf "$work"; return 1; }
  tls_issue_leaf "$cakey" "$cacrt" "$work/transport.key" "$work/transport.crt" "$certdays" "$cn" "$sans" serverAuth,clientAuth || { rm -rf "$work"; return 1; }
  # ---- 모두 만들어졌을 때만 설치한다 (하나라도 실패하면 위에서 이미 반환)
  local fail=0
  install -d -m 750 -o root -g "$grp" "$pem" 2>/dev/null || { mkdir -p "$pem" && chmod 750 "$pem" && { chgrp "$grp" "$pem" 2>/dev/null || true; }; } || fail=1
  if [[ "$cakey" -ef "$pem/ca.key" ]]; then chmod 600 "$pem/ca.key" || fail=1; else install -m 600 "$cakey" "$pem/ca.key" || fail=1; fi
  install -m 644 "$cacrt" "$pem/ca.crt" || fail=1
  install -m 640 "$work/http.key" "$pem/http.key" || fail=1;           install -m 644 "$work/http.crt" "$pem/http.crt" || fail=1
  install -m 640 "$work/transport.key" "$pem/transport.key" || fail=1; install -m 644 "$work/transport.crt" "$pem/transport.crt" || fail=1
  chgrp "$grp" "$pem/http.key" "$pem/transport.key" 2>/dev/null || true
  if [[ -e "$d/http_ca.crt" ]]; then cat "$pem/ca.crt" >"$d/http_ca.crt" || fail=1; else install -m 644 "$pem/ca.crt" "$d/http_ca.crt" || fail=1; fi
  (( fail == 0 )) || { rm -rf "$work"; tls_err "인증서 파일을 설치하지 못했습니다. ($pem)"; return 1; }
  rm -rf "$work"
  TLS_RESULT_MODE="$mode"; TLS_RESULT_SANS="$sans"; return 0
}
tls_verify_es_set() { # 설치된 PEM 한 벌이 서로 맞는지 확인
  local pem="${TLS_CERT_DIR:-/etc/elasticsearch/certs}/pem" n
  for n in http transport; do
    openssl verify -CAfile "$pem/ca.crt" "$pem/$n.crt" >/dev/null 2>&1 || { tls_err "$n 인증서가 CA 로 검증되지 않습니다."; return 1; }
    [[ "$(tls_pubkey_hash "$pem/$n.key" key)" == "$(tls_pubkey_hash "$pem/$n.crt" cert)" ]] || { tls_err "$n 개인키와 인증서가 짝이 맞지 않습니다."; return 1; }
  done
  cmp -s "$pem/ca.crt" "${TLS_CERT_DIR:-/etc/elasticsearch/certs}/http_ca.crt" || { tls_err "http_ca.crt 가 CA 인증서와 다릅니다."; return 1; }
}

# ---- elasticsearch.yml : p12 설정 -> PEM 설정 --------------------------------------------------------------------
tls_yml_pem_lines() { # http_ssl_enabled transport_ssl_enabled  (true/false)  — 설치기가 yml 을 쓸 때도 이 줄을 사용
  if [[ "${1:-true}" == true ]]; then
    echo "xpack.security.http.ssl.key: certs/pem/http.key"
    echo "xpack.security.http.ssl.certificate: certs/pem/http.crt"
    echo "xpack.security.http.ssl.certificate_authorities: [\"certs/pem/ca.crt\"]"
  fi
  if [[ "${2:-true}" == true ]]; then
    echo "xpack.security.transport.ssl.key: certs/pem/transport.key"
    echo "xpack.security.transport.ssl.certificate: certs/pem/transport.crt"
    echo "xpack.security.transport.ssl.certificate_authorities: [\"certs/pem/ca.crt\"]"
  fi
}
tls_yml_switch_to_pem() { # yml — keystore/truststore 줄을 지우고 PEM 줄을 넣는다. 이미 PEM 이면 그대로 둔다.
  local y="$1" tmp http transport
  [[ -f "$y" ]] || { tls_err "elasticsearch.yml 이 없습니다: $y"; return 1; }
  if grep -qE '^xpack:|^[[:space:]]*xpack(\.security)?(\.(http|transport))?(\.ssl)?:[[:space:]]*$|^[[:space:]]+(enabled|keystore\.path|truststore\.path|verification_mode|key|certificate|certificate_authorities):' "$y"; then tls_err "elasticsearch.yml 이 들여쓰기(중첩) 형식이라 자동으로 고칠 수 없습니다. (설치기가 만든 한 줄 형식이어야 합니다)"; return 1; fi
  http=false; grep -qE '^[[:space:]]*xpack\.security\.http\.ssl\.enabled:[[:space:]]*true' "$y" && http=true
  transport=false; grep -qE '^[[:space:]]*xpack\.security\.transport\.ssl\.enabled:[[:space:]]*true' "$y" && transport=true
  tmp="$(mktemp)"
  grep -vE '^[[:space:]]*xpack\.security\.(http|transport)\.ssl\.(keystore\.path|keystore\.type|truststore\.path|truststore\.type|key|certificate|certificate_authorities|key_passphrase)[[:space:]]*:' "$y" >"$tmp"
  [[ -n "$(tail -c1 "$tmp")" ]] && echo >>"$tmp"
  tls_yml_pem_lines "$http" "$transport" >>"$tmp"
  if [[ "$transport" == true ]] && ! grep -qE '^[[:space:]]*xpack\.security\.transport\.ssl\.verification_mode:' "$tmp"; then echo "xpack.security.transport.ssl.verification_mode: certificate" >>"$tmp"; fi
  cat "$tmp" >"$y"; rm -f "$tmp"
}
tls_yml_is_pem() { grep -qE '^[[:space:]]*xpack\.security\.http\.ssl\.certificate:[[:space:]]*certs/pem/http\.crt' "$1" 2>/dev/null; }

# ---- 자체 서명(self-signed) 인증서: Nginx 등 ---------------------------------------------------------------------------
tls_renew_selfsigned() { # crt key days — 같은 키·같은 이름·같은 SAN 으로 유효기간만 새로 (Nginx 용)
  local crt="$1" key="$2" days="$3" out
  tls_valid_days "$days" || { tls_err "유효기간(일)이 올바르지 않습니다: $days"; return 1; }
  [[ -s "$crt" && -s "$key" ]] || { tls_err "인증서 또는 키 파일이 없습니다: $crt / $key"; return 1; }
  [[ "$(tls_pubkey_hash "$key" key)" == "$(tls_pubkey_hash "$crt" cert)" ]] || { tls_err "개인키가 인증서와 짝이 맞지 않습니다."; return 1; }
  tls_is_selfsigned "$crt" || { tls_err "자체 서명 인증서가 아니라서(공인/사설 CA 발급) 여기서 갱신할 수 없습니다. 발급 기관에서 새로 받으세요."; return 1; }
  out="$(mktemp)"
  openssl x509 -in "$crt" -signkey "$key" -days "$days" -set_serial "$(tls_serial)" -out "$out" 2>/dev/null || { rm -f "$out"; tls_err "인증서 갱신 실패"; return 1; }
  [[ "$(tls_subject "$out")" == "$(tls_subject "$crt")" && "$(tls_pubkey_hash "$out" cert)" == "$(tls_pubkey_hash "$crt" cert)" ]] || { rm -f "$out"; tls_err "갱신한 인증서의 이름 또는 키가 달라졌습니다."; return 1; }
  cat "$out" >"$crt"; rm -f "$out"
}
