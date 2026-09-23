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
mapping="$(xmodmap -pke | awk -v key="$keycode" '$1 == "keycode" && $2 == key { print; exit }')"
printf 'X11 keycode %s after euro apply: %s\n' "$keycode" "$mapping"
case "$mapping" in
  *EuroSign*) ;;
  *)
    echo "Applying the same mapping directly for diagnostics:" >&2
    xmodmap -verbose -e "keycode $keycode = 4 EuroSign 4 EuroSign" >&2 || true
    xmodmap -pke | awk -v key="$keycode" '$1 == "keycode" && $2 == key { print; exit }' >&2
    exit 1
    ;;
esac

bash "$repo_root/eurozone" dollar
mapping="$(xmodmap -pke | awk -v key="$keycode" '$1 == "keycode" && $2 == key { print; exit }')"
printf 'X11 keycode %s after dollar apply: %s\n' "$keycode" "$mapping"
case "$mapping" in *dollar*) ;; *) echo 'dollar not present in X11 mapping' >&2; exit 1 ;; esac
echo "Linux X11 Shift+4 apply/restore PASS"
