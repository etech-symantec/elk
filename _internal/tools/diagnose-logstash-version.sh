#!/usr/bin/env bash
set -Eeuo pipefail
REQ="${1:-9.5.2}"
echo "Requested upstream version: $REQ"
echo "Available Logstash APT versions:"
apt-cache madison logstash | head -20
RESOLVED="$(apt-cache madison logstash 2>/dev/null | awk -F'|' -v req="$REQ" '
  function trim(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  { v=trim($2); n=v; sub(/^[0-9]+:/,"",n); sub(/-.*/,"",n); if(n==req){print v; exit} }
')"
echo "Resolved exact APT version: ${RESOLVED:-NOT_FOUND}"
[[ -n "$RESOLVED" ]]
