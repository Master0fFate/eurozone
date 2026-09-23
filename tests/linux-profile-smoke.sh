#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
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

environment_file="$HOME/.config/environment.d/90-eurozone-profile.conf"
mkdir -p "$HOME/.config/environment.d"

# Confirm that profile switching keeps one undo point, then restores both the
# GNOME region setting and any pre-existing systemd user locale file.
printf 'LC_NUMERIC=before-profile\n' > "$environment_file"
before_region="$(gsettings get org.gnome.system.locale region)"
before_environment="$(cat "$environment_file")"
have_systemd_user=0
if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
  have_systemd_user=1
fi
bash "$repo_root/eurozone" --profile DE
after_region="$(gsettings get org.gnome.system.locale region)"
[ "$after_region" = "'de_DE.UTF-8'" ]
[ -f "$XDG_CONFIG_HOME/eurozone/profile.active" ]
if [ "$have_systemd_user" -eq 1 ]; then
  grep -q '^LC_MONETARY=de_DE.UTF-8$' "$environment_file"
else
  [ "$(cat "$environment_file")" = "$before_environment" ]
fi

bash "$repo_root/eurozone" --profile FR
[ "$(gsettings get org.gnome.system.locale region)" = "'fr_FR.UTF-8'" ]
grep -q "LC_NUMERIC=before-profile" "$XDG_CONFIG_HOME/eurozone/profile-backup/environment.d"

bash "$repo_root/eurozone" --restore-profile
[ "$(gsettings get org.gnome.system.locale region)" = "$before_region" ]
[ "$(cat "$environment_file")" = 'LC_NUMERIC=before-profile' ]
[ ! -e "$XDG_CONFIG_HOME/eurozone/profile.active" ]
echo "Linux GNOME regional profile apply/switch/restore PASS"
