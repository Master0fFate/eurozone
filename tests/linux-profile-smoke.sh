#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
if [ "${EUROZONE_ALLOW_OS_TESTS:-0}" != 1 ]; then
  echo 'Native test requires EUROZONE_ALLOW_OS_TESTS=1 in a disposable account.' >&2
  exit 1
fi
if [ "${EUROZONE_PROFILE_TEST_INNER:-0}" != 1 ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  export HOME="$tmp/home"
  export XDG_CONFIG_HOME="$tmp/config"
  export XDG_CACHE_HOME="$tmp/cache"
  export XDG_DATA_HOME="$tmp/data"
  export EUROZONE_PROFILE_TEST_INNER=1
  mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME"
  dbus-run-session -- bash "$repo_root/tests/linux-profile-smoke.sh"
  exit $?
fi

environment_file="$XDG_CONFIG_HOME/environment.d/90-eurozone-profile.conf"
mkdir -p "$(dirname "$environment_file")"

# Confirm that profile switching keeps one undo point, then restores both the
# GNOME region setting and any pre-existing systemd user locale file.
printf 'LC_NUMERIC=before-profile\n' > "$environment_file"
before_region="$(gsettings get org.gnome.system.locale region)"
gsettings set org.gnome.desktop.interface clock-format '12h'
before_clock="$(gsettings get org.gnome.desktop.interface clock-format)"
bash "$repo_root/eurozone" --setup DE
after_region="$(gsettings get org.gnome.system.locale region)"
[ "$after_region" = "'de_DE.UTF-8'" ]
[ "$(gsettings get org.gnome.desktop.interface clock-format)" = "'24h'" ]
[ -f "$XDG_CONFIG_HOME/eurozone/profile.active" ]
grep -q '^LC_MONETARY=de_DE.UTF-8$' "$environment_file"
grep -q '^LC_MEASUREMENT=de_DE.UTF-8$' "$environment_file"
grep -q '^LC_PAPER=de_DE.UTF-8$' "$environment_file"

bash "$repo_root/eurozone" --profile FR
[ "$(gsettings get org.gnome.system.locale region)" = "'fr_FR.UTF-8'" ]
grep -q "LC_NUMERIC=before-profile" "$XDG_CONFIG_HOME/eurozone/profile-backup/environment.d"

bash "$repo_root/eurozone" --restore-profile
[ "$(gsettings get org.gnome.system.locale region)" = "$before_region" ]
[ "$(gsettings get org.gnome.desktop.interface clock-format)" = "$before_clock" ]
[ "$(cat "$environment_file")" = 'LC_NUMERIC=before-profile' ]
[ ! -e "$XDG_CONFIG_HOME/eurozone/profile.active" ]
[ ! -e "$XDG_CONFIG_HOME/autostart/eurozone.desktop" ]
echo "Linux GNOME regional profile apply/switch/restore PASS"
