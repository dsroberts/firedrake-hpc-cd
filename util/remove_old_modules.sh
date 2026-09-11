#!/usr/bin/env bash
set -euo pipefail

while read mod version; do
    echo "Would remove /g/data/fp50/apps/${mod}/${version}"
done < <( sqlite3 -readonly -noheader -column /g/data/fp50/modules/.module_load_log.sqlite <<<"SELECT argument1, argument2 FROM entries WHERE argument2 LIKE 'main%' GROUP BY argument1, argument2 HAVING MAX(created_at) < CAST(strftime('%s', 'now', '-60 days') AS INTEGER) ORDER BY argument1, argument2;" )