#!/usr/bin/env bash
set -e
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FILE="$DIR/../../config-wizard.html"
[[ -f "$FILE" ]] || FILE="$DIR/config-wizard.html"
FILE="$(cd -- "$(dirname -- "$FILE")" && pwd)/$(basename -- "$FILE")"
if command -v xdg-open >/dev/null 2>&1; then xdg-open "$FILE" >/dev/null 2>&1 &
elif command -v sensible-browser >/dev/null 2>&1; then sensible-browser "$FILE" >/dev/null 2>&1 &
else echo "브라우저에서 다음 파일을 여세요: $FILE"; fi
