#!/usr/bin/env bash
set -Eeuo pipefail
ENV_FILE="${ELK_ENV_FILE:-/etc/elk-auto/elk.env}"
if [[ -n "${1:-}" && -f "${1:-}" ]]; then
  ENV_FILE="$1"
  shift
fi
[[ -f "$ENV_FILE" ]] || { echo "env 파일을 찾을 수 없습니다: $ENV_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"
: "${SECRETS_FILE:=/root/.elk-auto-installer/secrets.env}"
: "${ES_HTTP_PORT:=9200}"
: "${ELASTIC_USERNAME:=elastic}"
: "${ES_SECURITY_ENABLED:=true}"
: "${INDEX_PREFIX:=network-log}"
: "${INDEX_TEMPLATE_PATTERNS:=}"
: "${PROXYSG_FLOW_ENABLED:=false}"
: "${PROXYSG_MAIN_INDEX_PREFIX:=proxy-main}"
: "${PROXYSG_SSL_INDEX_PREFIX:=proxy-ssl}"
: "${PROXYSG_CLOUD_ENABLED:=false}"
: "${PROXYSG_CLOUD_INDEX_PREFIX:=proxy-cloud}"
: "${INSTALL_NGINX:=false}"
: "${NGINX_HTTPS_PORT:=443}"
: "${INSTALL_FTP_SERVER:=true}"
: "${FTP_LISTEN_PORT:=21}"
: "${FTP_UPLOAD_DIR:=/log/incoming}"
if [[ -f "$SECRETS_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$SECRETS_FILE"
fi
CA=/etc/elasticsearch/certs/http_ca.crt
[[ -f "$CA" ]] && URL="https://127.0.0.1:${ES_HTTP_PORT}" || URL="http://127.0.0.1:${ES_HTTP_PORT}"
curl_args=(-sS)
[[ -f "$CA" ]] && curl_args+=(--cacert "$CA")
[[ "${ES_SECURITY_ENABLED,,}" == "true" && -n "${ELASTIC_PASSWORD:-}" ]] && curl_args+=(-u "${ELASTIC_USERNAME}:${ELASTIC_PASSWORD}")
es(){ curl "${curl_args[@]}" "$URL$1"; }
PATTERN="${INDEX_PREFIX}-*"
if [[ "${PROXYSG_FLOW_ENABLED,,}" == "true" ]]; then PATTERN="${PROXYSG_MAIN_INDEX_PREFIX}-*,${PROXYSG_SSL_INDEX_PREFIX}-*"; [[ "${PROXYSG_CLOUD_ENABLED,,}" == "true" ]] && PATTERN="${PATTERN},${PROXYSG_CLOUD_INDEX_PREFIX}-*"; elif [[ -n "$INDEX_TEMPLATE_PATTERNS" ]]; then PATTERN="$INDEX_TEMPLATE_PATTERNS"; fi
cmd="${1:-status}"
case "$cmd" in
  status)
    systemctl --no-pager --full status elasticsearch kibana logstash vsftpd nginx 2>/dev/null | grep -E '●|Active:' || true
    echo; es '/_cluster/health?pretty' | jq .
    ;;
  health) es '/_cluster/health?pretty' | jq . ;;
  indices) es "/_cat/indices/${PATTERN}?v&s=index" ;;
  ilm) es "/${PATTERN}/_ilm/explain?pretty" | jq . ;;
  disk) es '/_cat/allocation?v&h=node,disk.total,disk.used,disk.avail,disk.percent,shards' ;;
  nodes) es '/_cat/nodes?v&h=name,ip,heap.percent,ram.percent,cpu,load_1m,disk.avail,node.role,master' ;;
  pending) es '/_cluster/pending_tasks?pretty' | jq . ;;
  ingest) /usr/local/sbin/elk-log-ingest-manager "$ENV_FILE" status ;;
  nginx)
    systemctl --no-pager --full status nginx 2>/dev/null | grep -E '●|Active:' || true
    nginx -t || true
    echo "https://$(hostname -I 2>/dev/null | awk '{print $1}'):${NGINX_HTTPS_PORT}"
    ;;
  proxysg)
    echo "ProxySG 로그 처리 스크립트: ${PROXYSG_FLOW_ENABLED} (Cloud: ${PROXYSG_CLOUD_ENABLED})"
    [[ -x /usr/local/sbin/elk-proxysg-log-process ]] && /usr/local/sbin/elk-proxysg-log-process "$ENV_FILE" || true
    ;;
  ftp)
    systemctl --no-pager --full status vsftpd 2>/dev/null | grep -E '●|Active:' || true
    echo "FTP upload: $FTP_UPLOAD_DIR"
    ss -ltnp 2>/dev/null | grep -E ":${FTP_LISTEN_PORT}([[:space:]]|$)" || true
    ;;
  logs)
    journalctl -u elasticsearch -u kibana -u logstash -u vsftpd -u nginx -n 100 --no-pager
    ;;
  restart)
    systemctl restart elasticsearch kibana logstash; [[ "${INSTALL_FTP_SERVER,,}" == "true" ]] && systemctl restart vsftpd || true; [[ "${INSTALL_NGINX,,}" == "true" ]] && systemctl restart nginx || true
    ;;
  *)
    echo "사용법: $0 [elk.env] {status|health|indices|ilm|disk|nodes|pending|ingest|ftp|nginx|proxysg|logs|restart}" >&2
    exit 2
    ;;
esac
