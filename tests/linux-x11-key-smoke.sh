#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/config"
export XDG_CACHE_HOME="$tmp/cache"
export XDG_DATA_HOME="$tmp/data"
export TERM=dumb
export NO_COLOR=1
mkdir -p "$HOME"

bash "$repo_root/eurozone" euro
keycode="$(cat "$XDG_CONFIG_HOME/eurozone/keycode")"
[ -f "$XDG_CONFIG_HOME/autostart/eurozone.desktop" ]
[ -f "$XDG_DATA_HOME/eurozone/eurozone-profiles.tsv" ]
grep -q -- '--config-dir' "$XDG_CONFIG_HOME/autostart/eurozone.desktop"
xmodmap -pke | awk -v key="$keycode" '$1 == "keycode" && $2 == key && /EuroSign/ { found=1 } END { exit !found }'

bash "$repo_root/eurozone" dollar
xmodmap -pke | awk -v key="$keycode" '$1 == "keycode" && $2 == key && /dollar/ { found=1 } END { exit !found }'
echo "Linux X11 Shift+4 apply/restore PASS"
