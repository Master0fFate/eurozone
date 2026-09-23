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
keymap="$(xkbcomp -xkb "$DISPLAY" -)"
printf '%s\n' "$keymap" | awk '
  $1 == "key" && $2 == "<AE04>" { in_target=1 }
  in_target { print }
  in_target && /EuroSign/ { found=1 }
  in_target && /};/ { in_target=0 }
  END { exit !found }
' || {
  echo 'EuroSign not present in active XKB map; checking the XKB compile/load steps:' >&2
  debug_map="$tmp/debug-map.xkb"
  debug_edited="$tmp/debug-edited.xkb"
  xkbcomp -xkb "$DISPLAY" "$debug_map"
  grep -n -A4 -B2 'key <AE04>' "$debug_map" >&2 || true
  awk -v target='<AE04>' -v symbol='EuroSign' '
    $1 == "key" && $2 == target { in_target=1 }
    in_target && ((/symbols/ && /\[/) || ($1 == "key" && /\[/)) { if (sub(/,[[:space:]]*[^],]+/, ", " symbol)) changed=1 }
    in_target && /};/ { in_target=0 }
    { print }
    END { if (!changed) exit 1 }
  ' "$debug_map" > "$debug_edited" || true
  echo 'edited key:' >&2
  grep -n -A4 -B2 'key <AE04>' "$debug_edited" >&2 || true
  xkbcomp -w0 "$debug_edited" "$DISPLAY" >&2 || true
  xkbcomp -xkb "$DISPLAY" - | grep -n -A4 -B2 'key <AE04>' >&2 || true
  exit 1
}

bash "$repo_root/eurozone" dollar
keymap="$(xkbcomp -xkb "$DISPLAY" -)"
printf '%s\n' "$keymap" | awk '
  $1 == "key" && $2 == "<AE04>" { in_target=1 }
  in_target && /dollar/ { found=1 }
  in_target && /};/ { in_target=0 }
  END { exit !found }
' || { echo 'dollar not present in active XKB map' >&2; exit 1; }
echo "Linux X11 Shift+4 apply/restore PASS"
