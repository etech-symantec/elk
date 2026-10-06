#!/usr/bin/env bash
# elk-cert-renew.sh — 설치 완료 서버의 Elasticsearch/Nginx TLS 인증서 갱신 도구
#
# 기본 동작은 /etc/elk-auto/elk.env 의 유효기간 설정을 사용합니다.
#   sudo bash elk-cert-renew.sh --show
#   sudo bash elk-cert-renew.sh --all
#   sudo bash elk-cert-renew.sh --elasticsearch
#   sudo bash elk-cert-renew.sh --nginx
#   sudo bash elk-cert-renew.sh --all --dry-run
#   sudo bash elk-cert-renew.sh --all --yes
#
# Elasticsearch 갱신은 CA 자체를 새로 발급하므로 로컬 Kibana/Logstash trust도 함께 교체합니다.
# 외부에서 http_ca.crt 를 신뢰하는 클라이언트가 있다면 새 CA를 별도로 배포해야 합니다.
set -Eeuo pipefail
IFS=$'\n\t'

ENV_FILE="${ELK_ENV_FILE:-/etc/elk-auto/elk.env}"
TARGET_ES=0
TARGET_NGINX=0
SHOW=0
DRY=0
YES=0
BACKUP_ROOT="${ELK_CERT_BACKUP_DIR:-/var/backups/elk-auto}"
ES_CA="/etc/elasticsearch/certs/http_ca.crt"
CERTUTIL="/usr/share/elasticsearch/bin/elasticsearch-certutil"
ES_KEYSTORE="/usr/share/elasticsearch/bin/elasticsearch-keystore"

_ts(){ date '+%Y-%m-%d %H:%M:%S'; }
log(){ echo "[$(_ts)] [INFO] $*"; }
warn(){ echo "[$(_ts)] [WARN] $*" >&2; }
die(){ echo "[$(_ts)] [ERROR] $*" >&2; exit 1; }
istrue(){ [[ "${1,,}" =~ ^(1|true|yes|y|on)$ ]]; }
usage(){ sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV_FILE="${2:-}"; shift 2 ;;
    --all) TARGET_ES=1; TARGET_NGINX=1; shift ;;
    --elasticsearch|--es) TARGET_ES=1; shift ;;
    --nginx) TARGET_NGINX=1; shift ;;
    --show) SHOW=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -y|--yes) YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "알 수 없는 옵션: $1" ;;
  esac
done
if (( TARGET_ES == 0 && TARGET_NGINX == 0 )); then TARGET_ES=1; TARGET_NGINX=1; fi
[[ -f "$ENV_FILE" ]] || die "elk.env를 찾을 수 없습니다: $ENV_FILE"
# shellcheck disable=SC1090
source "$ENV_FILE"

: "${INSTALL_ELASTICSEARCH:=true}"
: "${ES_SECURITY_ENABLED:=true}"
: "${ES_HTTP_TLS_ENABLED:=true}"
: "${ES_TRANSPORT_TLS_ENABLED:=true}"
: "${ES_DISCOVERY_MODE:=single-node}"
: "${ES_HTTP_PORT:=9200}"
: "${ES_NODE_NAME:=elk01}"
: "${SYSTEM_HOSTNAME:=elk01}"
: "${STATE_DIR:=/root/.elk-auto-installer}"
: "${ES_TLS_CA_VALIDITY_DAYS:=7300}"
: "${ES_TLS_CERT_VALIDITY_DAYS:=7300}"
: "${INSTALL_KIBANA:=true}"
: "${INSTALL_LOGSTASH:=true}"
: "${INSTALL_NGINX:=false}"
: "${NGINX_TLS_MODE:=selfsigned}"
: "${NGINX_TLS_SYNC_WITH_ES:=true}"
: "${NGINX_TLS_DAYS:=7300}"
: "${NGINX_TLS_CERT_FILE:=/etc/ssl/certs/kibana-selfsigned.crt}"
: "${NGINX_TLS_KEY_FILE:=/etc/ssl/private/kibana-selfsigned.key}"
: "${NGINX_TLS_CN:=}"

[[ "$ES_TLS_CA_VALIDITY_DAYS" =~ ^[0-9]+$ ]] && (( ES_TLS_CA_VALIDITY_DAYS >= 1 && ES_TLS_CA_VALIDITY_DAYS <= 36500 )) || die "ES_TLS_CA_VALIDITY_DAYS는 1~36500일 정수여야 합니다."
[[ "$ES_TLS_CERT_VALIDITY_DAYS" =~ ^[0-9]+$ ]] && (( ES_TLS_CERT_VALIDITY_DAYS >= 1 && ES_TLS_CERT_VALIDITY_DAYS <= 36500 )) || die "ES_TLS_CERT_VALIDITY_DAYS는 1~36500일 정수여야 합니다."
(( ES_TLS_CERT_VALIDITY_DAYS <= ES_TLS_CA_VALIDITY_DAYS )) || die "Elasticsearch 서버 인증서 기간은 CA보다 길 수 없습니다."
if istrue "$NGINX_TLS_SYNC_WITH_ES"; then NGINX_EFFECTIVE_DAYS="$ES_TLS_CERT_VALIDITY_DAYS"; else NGINX_EFFECTIVE_DAYS="$NGINX_TLS_DAYS"; fi
[[ "$NGINX_EFFECTIVE_DAYS" =~ ^[0-9]+$ ]] && (( NGINX_EFFECTIVE_DAYS >= 1 && NGINX_EFFECTIVE_DAYS <= 36500 )) || die "Nginx 인증서 유효기간은 1~36500일 정수여야 합니다."

cert_dates(){
  local label="$1" file="$2"
  if [[ -s "$file" ]]; then
    echo "[$label] $file"
    openssl x509 -in "$file" -noout -subject -issuer -startdate -enddate 2>/dev/null || echo "  (X.509 PEM 형식으로 읽을 수 없음)"
  else
    echo "[$label] 없음: $file"
  fi
}
show_status(){
  echo "=== 현재 인증서 ==="
  cert_dates "Elasticsearch CA" "$ES_CA"
  cert_dates "Nginx" "$NGINX_TLS_CERT_FILE"
  echo
  echo "=== 목표 설정 ==="
  echo "Elasticsearch CA       : ${ES_TLS_CA_VALIDITY_DAYS}일"
  echo "Elasticsearch HTTP/TLS : ${ES_TLS_CERT_VALIDITY_DAYS}일"
  if istrue "$NGINX_TLS_SYNC_WITH_ES"; then
    echo "Nginx Self-Signed      : ${NGINX_EFFECTIVE_DAYS}일 (Elasticsearch 서버 인증서와 동기화)"
  else
    echo "Nginx Self-Signed      : ${NGINX_EFFECTIVE_DAYS}일"
  fi
}
show_status
(( SHOW )) && exit 0
(( DRY )) && { echo; echo "[DRY-RUN] 인증서를 변경하지 않았습니다."; exit 0; }
[[ ${EUID:-$(id -u)} -eq 0 ]] || die "root 권한이 필요합니다. sudo로 실행하세요."
command -v openssl >/dev/null 2>&1 || die "openssl이 필요합니다."

if (( TARGET_ES )) && [[ "$ES_DISCOVERY_MODE" != "single-node" ]]; then
  die "다중 노드 Elasticsearch에서는 CA를 한 노드만 교체하면 클러스터 연결이 끊길 수 있어 자동 갱신을 차단합니다. staged CA rotation 절차를 사용하세요."
fi

if (( YES == 0 )); then
  echo
  echo "주의: Elasticsearch 갱신은 CA 자체를 새로 발급합니다."
  echo "      Kibana/Logstash의 로컬 trust는 자동 교체하지만, 외부 클라이언트의 기존 CA trust는 직접 갱신해야 합니다."
  echo "      Elasticsearch/Kibana/Logstash는 갱신 중 잠시 중지될 수 있습니다."
  read -r -p "계속하시겠습니까? [y/N] " ans
  [[ "${ans,,}" =~ ^(y|yes)$ ]] || { echo "취소했습니다."; exit 0; }
fi

TS="$(date +%Y%m%d-%H%M%S)"
BK="$BACKUP_ROOT/cert-$TS"
mkdir -p "$BK"; chmod 700 "$BK"
log "인증서 백업 위치: $BK"

svc_active(){ systemctl is-active --quiet "$1" 2>/dev/null; }
ES_WAS=0; LS_WAS=0; KB_WAS=0
svc_active elasticsearch && ES_WAS=1 || true
svc_active logstash && LS_WAS=1 || true
svc_active kibana && KB_WAS=1 || true

renew_es(){
  istrue "$INSTALL_ELASTICSEARCH" || { warn "Elasticsearch 설치가 꺼져 있어 ES 인증서 갱신 건너뜀"; return 0; }
  istrue "$ES_SECURITY_ENABLED" || { warn "Elasticsearch Security가 꺼져 있어 ES 인증서 갱신 건너뜀"; return 0; }
  [[ -x "$CERTUTIL" ]] || die "elasticsearch-certutil을 찾을 수 없습니다: $CERTUTIL"
  [[ -x "$ES_KEYSTORE" ]] || die "elasticsearch-keystore를 찾을 수 없습니다: $ES_KEYSTORE"

  local tmp es_certs pki_dir dns_csv ip_csv short_host fqdn
  tmp="$(mktemp -d /tmp/elk-cert-renew.XXXXXX)"
  es_certs="/etc/elasticsearch/certs"
  pki_dir="${STATE_DIR}/pki"
  mkdir -p "$es_certs" "$pki_dir"; chmod 700 "$pki_dir"

  short_host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
  fqdn="$(hostname -f 2>/dev/null || true)"
  dns_csv="$({ printf '%s\n' localhost "$short_host" "$fqdn" "${SYSTEM_HOSTNAME:-}"; } | awk 'NF && !seen[$0]++' | paste -sd, -)"
  ip_csv="$({ printf '%s\n' 127.0.0.1; hostname -I 2>/dev/null | tr ' ' '\n'; } | awk 'NF && !seen[$0]++' | paste -sd, -)"
  [[ -n "$dns_csv" ]] || dns_csv="localhost"
  [[ -n "$ip_csv" ]] || ip_csv="127.0.0.1"

  log "새 Elasticsearch CA/서버 인증서 생성: CA=${ES_TLS_CA_VALIDITY_DAYS}일, cert=${ES_TLS_CERT_VALIDITY_DAYS}일"
  "$CERTUTIL" ca --silent --days "$ES_TLS_CA_VALIDITY_DAYS" --out "$tmp/elastic-stack-ca.p12" --pass ""
  if istrue "$ES_HTTP_TLS_ENABLED"; then
    "$CERTUTIL" cert --silent --ca "$tmp/elastic-stack-ca.p12" --ca-pass "" --days "$ES_TLS_CERT_VALIDITY_DAYS" \
      --name "$ES_NODE_NAME" --dns "$dns_csv" --ip "$ip_csv" --out "$tmp/http.p12" --pass ""
  fi
  if istrue "$ES_TRANSPORT_TLS_ENABLED"; then
    "$CERTUTIL" cert --silent --ca "$tmp/elastic-stack-ca.p12" --ca-pass "" --days "$ES_TLS_CERT_VALIDITY_DAYS" \
      --name "${ES_NODE_NAME}-transport" --dns "$dns_csv" --ip "$ip_csv" --out "$tmp/transport.p12" --pass ""
  fi
  openssl pkcs12 -in "$tmp/elastic-stack-ca.p12" -nokeys -passin pass: 2>/dev/null | openssl x509 -out "$tmp/http_ca.crt"

  [[ -d "$es_certs" ]] && cp -a "$es_certs" "$BK/elasticsearch-certs"
  [[ -f /etc/elasticsearch/elasticsearch.keystore ]] && cp -a /etc/elasticsearch/elasticsearch.keystore "$BK/elasticsearch.keystore"
  [[ -f "$pki_dir/elastic-stack-ca.p12" ]] && cp -a "$pki_dir/elastic-stack-ca.p12" "$BK/elastic-stack-ca.p12"
  [[ -f "$pki_dir/validity.txt" ]] && cp -a "$pki_dir/validity.txt" "$BK/validity.txt"
  [[ -f /etc/kibana/certs/http_ca.crt ]] && cp -a /etc/kibana/certs/http_ca.crt "$BK/kibana-http_ca.crt"
  [[ -f /etc/logstash/certs/http_ca.crt ]] && cp -a /etc/logstash/certs/http_ca.crt "$BK/logstash-http_ca.crt"

  (( KB_WAS )) && systemctl stop kibana || true
  (( LS_WAS )) && systemctl stop logstash || true
  systemctl stop elasticsearch || true

  install -m 600 "$tmp/elastic-stack-ca.p12" "$pki_dir/elastic-stack-ca.p12"
  install -m 640 "$tmp/http_ca.crt" "$ES_CA"
  istrue "$ES_HTTP_TLS_ENABLED" && install -m 640 "$tmp/http.p12" "$es_certs/http.p12"
  istrue "$ES_TRANSPORT_TLS_ENABLED" && install -m 640 "$tmp/transport.p12" "$es_certs/transport.p12"
  chown root:elasticsearch "$ES_CA"
  istrue "$ES_HTTP_TLS_ENABLED" && chown root:elasticsearch "$es_certs/http.p12"
  istrue "$ES_TRANSPORT_TLS_ENABLED" && chown root:elasticsearch "$es_certs/transport.p12"

  for key in xpack.security.http.ssl.keystore.secure_password xpack.security.transport.ssl.keystore.secure_password xpack.security.transport.ssl.truststore.secure_password; do
    "$ES_KEYSTORE" remove "$key" >/dev/null 2>&1 || true
  done

  systemctl start elasticsearch
  local ok=0 code=""
  for _ in $(seq 1 60); do
    code="$(curl -s --cacert "$ES_CA" -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 4 "https://127.0.0.1:${ES_HTTP_PORT}" 2>/dev/null || true)"
    [[ "$code" =~ ^(200|401|403)$ ]] && { ok=1; break; }
    sleep 2
  done
  if (( ok == 0 )); then
    warn "새 Elasticsearch 인증서로 기동 확인 실패. 기존 인증서로 자동 복구합니다."
    systemctl stop elasticsearch || true
    rm -rf "$es_certs"
    cp -a "$BK/elasticsearch-certs" "$es_certs"
    if [[ -f "$BK/elasticsearch.keystore" ]]; then cp -a "$BK/elasticsearch.keystore" /etc/elasticsearch/elasticsearch.keystore; fi
    systemctl start elasticsearch || true
    (( LS_WAS )) && systemctl start logstash || true
    (( KB_WAS )) && systemctl start kibana || true
    rm -rf "$tmp"
    return 1
  fi

  if istrue "$INSTALL_LOGSTASH" && [[ -d /etc/logstash ]]; then
    mkdir -p /etc/logstash/certs
    install -m 640 "$ES_CA" /etc/logstash/certs/http_ca.crt
    chown logstash:logstash /etc/logstash/certs/http_ca.crt 2>/dev/null || true
  fi
  if istrue "$INSTALL_KIBANA" && [[ -d /etc/kibana ]]; then
    mkdir -p /etc/kibana/certs
    install -m 640 "$ES_CA" /etc/kibana/certs/http_ca.crt
    chown kibana:kibana /etc/kibana/certs/http_ca.crt 2>/dev/null || true
  fi

  {
    echo "generated_at=$(date -Is)"
    echo "ca_validity_days=${ES_TLS_CA_VALIDITY_DAYS}"
    echo "cert_validity_days=${ES_TLS_CERT_VALIDITY_DAYS}"
    openssl x509 -in "$ES_CA" -noout -subject -issuer -dates
  } >"$pki_dir/validity.txt"
  chmod 600 "$pki_dir/validity.txt"

  (( LS_WAS )) && systemctl start logstash || true
  (( KB_WAS )) && systemctl start kibana || true
  rm -rf "$tmp"
  log "Elasticsearch CA/HTTP/Transport 인증서 갱신 완료"
  log "새 CA 만료: $(openssl x509 -in "$ES_CA" -noout -enddate | cut -d= -f2-)"
  warn "외부 클라이언트가 기존 http_ca.crt를 신뢰했다면 새 CA를 배포해야 합니다: $ES_CA"
}

renew_nginx(){
  istrue "$INSTALL_NGINX" || { log "Nginx 미사용: 인증서 갱신 건너뜀"; return 0; }
  if [[ "$NGINX_TLS_MODE" != "selfsigned" ]]; then
    warn "NGINX_TLS_MODE=$NGINX_TLS_MODE: 외부/기존 인증서는 설치기가 유효기간을 늘릴 수 없습니다. 발급기관에서 새 인증서를 받은 뒤 경로의 파일을 교체하세요."
    return 0
  fi
  command -v nginx >/dev/null 2>&1 || die "nginx 명령을 찾을 수 없습니다."
  local tmp cn san cert_bk key_bk
  tmp="$(mktemp -d /tmp/elk-nginx-cert.XXXXXX)"
  cn="$NGINX_TLS_CN"
  if [[ -z "$cn" && -s "$NGINX_TLS_CERT_FILE" ]]; then
    cn="$(openssl x509 -in "$NGINX_TLS_CERT_FILE" -noout -subject -nameopt RFC2253 2>/dev/null | sed -n 's/^subject=.*CN=\([^,]*\).*$/\1/p' | head -1 || true)"
  fi
  if [[ -z "$cn" ]]; then cn="$(hostname -I 2>/dev/null | awk '{print $1}')"; fi
  [[ -n "$cn" ]] || cn="$(hostname -f 2>/dev/null || hostname)"
  san="DNS:${cn}"; [[ "$cn" =~ ^[0-9a-fA-F:.]+$ ]] && san="IP:${cn}"
  openssl req -x509 -nodes -days "$NGINX_EFFECTIVE_DAYS" -newkey rsa:2048 \
    -keyout "$tmp/nginx.key" -out "$tmp/nginx.crt" \
    -subj "/C=KR/ST=Seoul/L=Seoul/O=IT/CN=${cn}" -addext "subjectAltName=${san}" >/dev/null 2>&1
  openssl x509 -in "$tmp/nginx.crt" -noout -checkend 60 >/dev/null || { rm -rf "$tmp"; die "새 Nginx 인증서 검증 실패"; }

  mkdir -p "$(dirname "$NGINX_TLS_CERT_FILE")" "$(dirname "$NGINX_TLS_KEY_FILE")"
  cert_bk="$BK/nginx-cert.pem"; key_bk="$BK/nginx-key.pem"
  [[ -f "$NGINX_TLS_CERT_FILE" ]] && cp -a "$NGINX_TLS_CERT_FILE" "$cert_bk"
  [[ -f "$NGINX_TLS_KEY_FILE" ]] && cp -a "$NGINX_TLS_KEY_FILE" "$key_bk"
  install -m 644 "$tmp/nginx.crt" "$NGINX_TLS_CERT_FILE"
  install -m 600 "$tmp/nginx.key" "$NGINX_TLS_KEY_FILE"
  if ! nginx -t; then
    warn "Nginx 설정 검사 실패. 기존 인증서로 복구합니다."
    [[ -f "$cert_bk" ]] && cp -a "$cert_bk" "$NGINX_TLS_CERT_FILE"
    [[ -f "$key_bk" ]] && cp -a "$key_bk" "$NGINX_TLS_KEY_FILE"
    rm -rf "$tmp"
    return 1
  fi
  systemctl reload nginx || systemctl restart nginx
  rm -rf "$tmp"
  log "Nginx Self-Signed 인증서 갱신 완료: CN=$cn, ${NGINX_EFFECTIVE_DAYS}일"
  log "Nginx 만료: $(openssl x509 -in "$NGINX_TLS_CERT_FILE" -noout -enddate | cut -d= -f2-)"
}

rc=0
if (( TARGET_ES )); then renew_es || rc=1; fi
if (( TARGET_NGINX )); then renew_nginx || rc=1; fi

echo
show_status
echo "백업 위치: $BK"
exit "$rc"
