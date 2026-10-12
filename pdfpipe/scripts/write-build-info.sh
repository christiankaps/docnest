#!/bin/sh
set -eu

output="${SCRIPT_OUTPUT_FILE_0:?Missing build-info output path}"
mkdir -p "$(dirname "$output")"
rm -f "$output"
/usr/bin/plutil -create xml1 "$output"
/usr/bin/plutil -insert BuildTimestampUTC -string "$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')" "$output"
