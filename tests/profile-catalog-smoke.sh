#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
catalog="$repo_root/eurozone-profiles.tsv"
[ -f "$catalog" ]

awk -F'|' '
  NR == 1 { if ($1 != "id" || $2 != "name" || $3 != "culture") exit 1; next }
  {
    if (NF != 3 || $1 == "" || $2 == "" || $3 !~ /^[a-z][a-z]-[A-Z][A-Z]$/) exit 1
    seen_id[$1]++
    if (seen_id[$1] > 1) exit 1
    country = $1
    sub(/-.*/, "", country)
    countries[country] = 1
    cultures[$3]++
    if (cultures[$3] > 1) exit 1
    count++
  }
  END {
    for (country in countries) country_count++
    if (count < 21 || country_count != 21) exit 1
    printf "Profile catalog valid: %d locales across %d euro-area countries\n", count, country_count
  }
' "$catalog"
