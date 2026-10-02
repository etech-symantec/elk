#!/usr/bin/env bash
# proxysg-lib.sh — ProxySG 로그 처리용 Logstash pipeline 생성 함수 모음 (elk-patch.sh 가 사용)
#
# 이 파일의 함수는 install-elk.sh 가 설치할 때 쓰는 코드와 같은 결과를 내야 합니다.
# (tools/check_patch_lib.sh 가 두 결과가 같은지 검사합니다. install-elk.sh 의 해당 부분을 고치면 여기도 같이 고치세요.)
#
# 필요한 변수(elk.env): PROXYSG_*_PROCESS_DIR/_SINCEDB/_LOG_FORMAT/_INDEX_PREFIX, PROXYSG_CLOUD_ENABLED,
#   PROXYSG_FILE_GLOB, PROXYSG_LOGSTASH_DISCOVER_INTERVAL, PROXYSG_LOGSTASH_MAX_OPEN_FILES, PROXYSG_CSV_FILTER_ENABLED,
#   INDEX_DATE_PATTERN, ES_SECURITY_ENABLED, ES_HTTP_TLS_ENABLED, LOGSTASH_ES_HOST   /   필요한 함수: istrue, die


# ---- v2.9.4: ProxySG MAIN/SSL 로그 포맷(ELFF) -> Logstash csv columns --------------------------------
# 규칙: date->log_date, time->log_time, 그 밖의 필드는 소문자로 바꾸고 영문/숫자 이외의 연속 문자를 _ 로 바꿈
#       (예: cs(Referer)->cs_referer, rs(Content-Type)->rs_content_type, c-ip->c_ip). 이름이 겹치면 _2, _3 ... 을 붙임.
elff_columns() {
  local fmt="$1" tok col base n
  local -A seen=()
  local IFS=$' \t\n'
  for tok in $fmt; do
    case "$tok" in
      date) col="log_date" ;;
      time) col="log_time" ;;
      *) col="$(printf '%s' "$tok" | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C sed -E 's/[^a-z0-9]+/_/g; s/^_+//; s/_+$//')" ;;
    esac
    [[ -n "$col" ]] || col="field"
    base="$col"; n=1
    while [[ -n "${seen[$col]:-}" ]]; do n=$((n+1)); col="${base}_${n}"; done
    seen[$col]=1
    printf '%s\n' "$col"
  done
}
proxysg_columns_block() {
  local cols=() i
  mapfile -t cols < <(elff_columns "$1")
  for i in "${!cols[@]}"; do
    if (( i < ${#cols[@]} - 1 )); then printf '          "%s",\n' "${cols[i]}"; else printf '          "%s"\n' "${cols[i]}"; fi
  done
}
render_proxysg_filter() {
  local tpl="$1" line skip=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      "# @@PROXYSG_CLOUD_BEGIN@@") istrue "$PROXYSG_CLOUD_ENABLED" || skip=1; continue ;;
      "# @@PROXYSG_CLOUD_END@@")   skip=0; continue ;;
    esac
    (( skip )) && continue
    case "$line" in
      "@@PROXYSG_MAIN_COLUMNS@@")  proxysg_columns_block "$PROXYSG_MAIN_LOG_FORMAT" ;;
      "@@PROXYSG_SSL_COLUMNS@@")   proxysg_columns_block "$PROXYSG_SSL_LOG_FORMAT" ;;
      "@@PROXYSG_CLOUD_COLUMNS@@") proxysg_columns_block "$PROXYSG_CLOUD_LOG_FORMAT" ;;
      *) printf '%s\n' "$line" ;;
    esac
  done <"$tpl"
}

# proxysg_generate_pipeline <filter-template> <output-file>
proxysg_generate_pipeline() {
  local _tpl="$1" _out="$2"
    cat >"$_out" <<EOF_PROXYSG_LS
input {
  file {
    path => ["${PROXYSG_MAIN_PROCESS_DIR}/${PROXYSG_FILE_GLOB}"]
    mode => "read"
    file_completed_action => "delete"
    sincedb_path => "${PROXYSG_MAIN_SINCEDB}"
    type => "edge-http"
    discover_interval => ${PROXYSG_LOGSTASH_DISCOVER_INTERVAL}
    max_open_files => ${PROXYSG_LOGSTASH_MAX_OPEN_FILES}
  }
  file {
    path => ["${PROXYSG_SSL_PROCESS_DIR}/${PROXYSG_FILE_GLOB}"]
    mode => "read"
    file_completed_action => "delete"
    sincedb_path => "${PROXYSG_SSL_SINCEDB}"
    type => "edge-https"
    discover_interval => ${PROXYSG_LOGSTASH_DISCOVER_INTERVAL}
    max_open_files => ${PROXYSG_LOGSTASH_MAX_OPEN_FILES}
  }
EOF_PROXYSG_LS
    if istrue "$PROXYSG_CLOUD_ENABLED"; then
      cat >>"$_out" <<EOF_PROXYSG_CLOUD_IN
  file {
    path => ["${PROXYSG_CLOUD_PROCESS_DIR}/${PROXYSG_FILE_GLOB}"]
    mode => "read"
    file_completed_action => "delete"
    sincedb_path => "${PROXYSG_CLOUD_SINCEDB}"
    type => "cloud"
    discover_interval => ${PROXYSG_LOGSTASH_DISCOVER_INTERVAL}
    max_open_files => ${PROXYSG_LOGSTASH_MAX_OPEN_FILES}
  }
EOF_PROXYSG_CLOUD_IN
    fi
    printf '}\n' >>"$_out"
    if istrue "$PROXYSG_CSV_FILTER_ENABLED"; then
      [[ -f "$_tpl" ]] || die "필수 파일 없음: $_tpl"
      render_proxysg_filter "$_tpl" >>"$_out"
    else
      printf '\nfilter { if ![message] or [message] =~ /^\s*#/ or [message] =~ /^\s*$/ { drop { } } }\n' >>"$_out"
    fi
    cat >>"$_out" <<EOF_PROXYSG_OUT
output {
  if [type] == "edge-http" {
    elasticsearch {
      hosts => ["${LOGSTASH_ES_HOST}"]
EOF_PROXYSG_OUT
    if istrue "$ES_SECURITY_ENABLED"; then
      cat >>"$_out" <<'EOF_PROXYSG_AUTH'
      user => "${LS_ES_USER}"
      password => "${LS_ES_PASSWORD}"
EOF_PROXYSG_AUTH
      if istrue "$ES_HTTP_TLS_ENABLED"; then cat >>"$_out" <<'EOF_PROXYSG_TLS'
      ssl_enabled => true
      ssl_certificate_authorities => ["/etc/logstash/certs/http_ca.crt"]
EOF_PROXYSG_TLS
      fi
    fi
    cat >>"$_out" <<EOF_PROXYSG_MAIN_OUT
      manage_template => false
      ilm_enabled => false
      index => "${PROXYSG_MAIN_INDEX_PREFIX}-%{+${INDEX_DATE_PATTERN}}"
    }
  } else if [type] == "edge-https" {
    elasticsearch {
      hosts => ["${LOGSTASH_ES_HOST}"]
EOF_PROXYSG_MAIN_OUT
    if istrue "$ES_SECURITY_ENABLED"; then
      cat >>"$_out" <<'EOF_PROXYSG_AUTH2'
      user => "${LS_ES_USER}"
      password => "${LS_ES_PASSWORD}"
EOF_PROXYSG_AUTH2
      if istrue "$ES_HTTP_TLS_ENABLED"; then cat >>"$_out" <<'EOF_PROXYSG_TLS2'
      ssl_enabled => true
      ssl_certificate_authorities => ["/etc/logstash/certs/http_ca.crt"]
EOF_PROXYSG_TLS2
      fi
    fi
    cat >>"$_out" <<EOF_PROXYSG_SSL_OUT
      manage_template => false
      ilm_enabled => false
      index => "${PROXYSG_SSL_INDEX_PREFIX}-%{+${INDEX_DATE_PATTERN}}"
    }
  }
EOF_PROXYSG_SSL_OUT
    if istrue "$PROXYSG_CLOUD_ENABLED"; then
      cat >>"$_out" <<EOF_PROXYSG_CLOUD_OUT
  if [type] == "cloud" {
    elasticsearch {
      hosts => ["${LOGSTASH_ES_HOST}"]
EOF_PROXYSG_CLOUD_OUT
      if istrue "$ES_SECURITY_ENABLED"; then
        cat >>"$_out" <<'EOF_PROXYSG_AUTH3'
      user => "${LS_ES_USER}"
      password => "${LS_ES_PASSWORD}"
EOF_PROXYSG_AUTH3
        if istrue "$ES_HTTP_TLS_ENABLED"; then cat >>"$_out" <<'EOF_PROXYSG_TLS3'
      ssl_enabled => true
      ssl_certificate_authorities => ["/etc/logstash/certs/http_ca.crt"]
EOF_PROXYSG_TLS3
        fi
      fi
      cat >>"$_out" <<EOF_PROXYSG_CLOUD_OUT2
      manage_template => false
      ilm_enabled => false
      index => "${PROXYSG_CLOUD_INDEX_PREFIX}-%{+${INDEX_DATE_PATTERN}}"
    }
  }
EOF_PROXYSG_CLOUD_OUT2
    fi
    printf '}\n' >>"$_out"
}
