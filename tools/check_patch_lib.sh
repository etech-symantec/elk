#!/usr/bin/env bash
# elk-patch.sh 가 쓰는 proxysg-lib.sh 의 pipeline 생성 결과가, 설치기(install-elk.sh)가 만드는 결과와 같은지 검사합니다.
# (두 곳의 코드를 따로 두었기 때문에, 한쪽만 고치면 이 검사가 실패해서 알려 줍니다.)
#   bash tools/check_patch_lib.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INST="$ROOT/_internal/core/install-elk.sh"; LIB="$ROOT/_internal/core/proxysg-lib.sh"; TPL="$ROOT/_internal/core/proxysg-log-filter.conf"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
# 설치기의 proxysg pipeline 생성 구간(입력~출력)을 그대로 뽑는다.
python3 - "$INST" "$W/installer_block.sh" <<'PY'
import sys
L=open(sys.argv[1],encoding='utf-8').read().split('\n')
a=next(i for i,l in enumerate(L) if l.strip()=='cat >"$LOGSTASH_PIPELINE_FILE" <<EOF_PROXYSG_LS')
pr=[i for i,l in enumerate(L) if i>a and l.strip()=="printf '}\\n' >>\"$LOGSTASH_PIPELINE_FILE\""]
open(sys.argv[2],'w',encoding='utf-8').write('\n'.join(L[a:pr[1]+1])+'\n')
PY
# 설치기의 함수 3개(elff_columns, proxysg_columns_block, render_proxysg_filter)도 뽑는다.
python3 - "$INST" "$W/installer_funcs.sh" <<'PY'
import sys
L=open(sys.argv[1],encoding='utf-8').read().split('\n')
a=next(i for i,l in enumerate(L) if l.startswith('elff_columns() {'))
b=next(i for i,l in enumerate(L) if l.startswith('render_proxysg_filter() {'))
e=next(i for i in range(b,len(L)) if L[i]=='}')
open(sys.argv[2],'w',encoding='utf-8').write('\n'.join(L[a-4:e+1])+'\n')
PY
MAIN='date time time-taken c-ip cs(Referer)  sc-status sc-bytes cs-bytes'
SSL='date time time-taken c-ip sc-status sc-bytes cs-bytes x-rs-certificate-hostname'
CLOUD='cs-method date time time-taken sc-bytes cs-bytes x-icap-reqmod-header(X-ICAP-Metadata) c-ip-version'
fails=0; n=0
scen() { # name  cloud  csv  security  tls  [extra assignments...]
  local name="$1" cloud="$2" csv="$3" sec="$4" tls="$5"; shift 5
  n=$((n+1))
  local common="istrue(){ [[ \"\${1,,}\" == \"true\" ]]; }; die(){ echo \"DIE: \$*\" >&2; exit 1; }
PROXYSG_MAIN_PROCESS_DIR=/home/main_process; PROXYSG_SSL_PROCESS_DIR=/home/ssl_process; PROXYSG_CLOUD_PROCESS_DIR=/home/cloud_process
PROXYSG_FILE_GLOB='*.log.gz'; PROXYSG_MAIN_SINCEDB=/v/sm; PROXYSG_SSL_SINCEDB=/v/ss; PROXYSG_CLOUD_SINCEDB=/v/sc
PROXYSG_LOGSTASH_DISCOVER_INTERVAL=5; PROXYSG_LOGSTASH_MAX_OPEN_FILES=1000; PROXYSG_CSV_FILTER_ENABLED=$csv
PROXYSG_MAIN_LOG_FORMAT='$MAIN'; PROXYSG_SSL_LOG_FORMAT='$SSL'; PROXYSG_CLOUD_LOG_FORMAT='$CLOUD'
PROXYSG_MAIN_INDEX_PREFIX=proxy-main; PROXYSG_SSL_INDEX_PREFIX=proxy-ssl; PROXYSG_CLOUD_INDEX_PREFIX=proxy-cloud; INDEX_DATE_PATTERN=YYYY.MM.dd
ES_SECURITY_ENABLED=$sec; ES_HTTP_TLS_ENABLED=$tls; LOGSTASH_ES_HOST=https://127.0.0.1:9200; PROXYSG_CLOUD_ENABLED=$cloud
$*"
  bash -c "set -Eeuo pipefail
$common
source '$W/installer_funcs.sh'
SCRIPT_DIR='$ROOT/_internal/core'
LOGSTASH_PIPELINE_FILE='$W/a.conf'
source '$W/installer_block.sh'" >/dev/null 2>"$W/err_a" || { echo "FAIL - $name: installer block error: $(head -2 "$W/err_a")"; fails=$((fails+1)); return; }
  bash -c "set -Eeuo pipefail
$common
source '$LIB'
proxysg_generate_pipeline '$TPL' '$W/b.conf'" >/dev/null 2>"$W/err_b" || { echo "FAIL - $name: lib error: $(head -2 "$W/err_b")"; fails=$((fails+1)); return; }
  if cmp -s "$W/a.conf" "$W/b.conf"; then echo "PASS - $name ($(wc -c <"$W/a.conf") bytes identical)"; else echo "FAIL - $name: installer and proxysg-lib.sh produce different pipelines"; diff "$W/a.conf" "$W/b.conf" | head -10; fails=$((fails+1)); fi
}
scen "cloud off / csv on / security+tls" false true true true
scen "cloud on" true true true true
scen "cloud on / security off" true true false false
scen "cloud on / tls off" true true true false
scen "cloud off / csv parsing off" false false true true
scen "cloud on / csv parsing off" true false true true
scen "custom names and date pattern" true true true true "PROXYSG_MAIN_PROCESS_DIR=/d/m PROXYSG_SSL_PROCESS_DIR=/d/s PROXYSG_CLOUD_PROCESS_DIR=/d/c PROXYSG_MAIN_INDEX_PREFIX=pm PROXYSG_SSL_INDEX_PREFIX=ps PROXYSG_CLOUD_INDEX_PREFIX=pc INDEX_DATE_PATTERN=yyyy.MM PROXYSG_LOGSTASH_DISCOVER_INTERVAL=9 PROXYSG_LOGSTASH_MAX_OPEN_FILES=77"
echo
if (( fails )); then echo "SOME FAILED ($fails of $n)"; exit 1; fi
echo "ALL PASSED ($n scenarios)"
