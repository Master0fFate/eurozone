#!/usr/bin/env bash
# Native integration: run only in a disposable macOS account / CI runner.
set -euo pipefail
if [ "${EUROZONE_ALLOW_OS_TESTS:-0}" != 1 ]; then
  echo 'Native test requires EUROZONE_ALLOW_OS_TESTS=1 in a disposable account.' >&2
  exit 1
fi
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"
# CFPreferences can ignore HOME. Protect the actual runner global preferences.
defaults export -g "$tmp/original-globals.plist"
cleanup() {
  defaults import -g "$tmp/original-globals.plist" || {
    echo "Cannot recover test account. Keep $tmp/original-globals.plist" >&2
    return 1
  }
  rm -rf "$tmp"
}
trap cleanup EXIT
export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/config"
export XDG_CACHE_HOME="$tmp/cache"
export XDG_DATA_HOME="$tmp/data"
export KARA_LOG="$tmp/karabiner.log"
mkdir -p "$HOME" "$tmp/bin"
cat > "$tmp/bin/karabiner_cli" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$KARA_LOG"
EOF
chmod +x "$tmp/bin/karabiner_cli"
export PATH="$tmp/bin:$PATH"

keys=(AppleLocale AppleMetricUnits AppleMeasurementUnits AppleTemperatureUnit AppleICUForce24HourTime AppleICUForce12HourTime AppleFirstWeekday AppleMinDaysInFirstWeek AppleICUDateFormatStrings AppleICUTimeFormatStrings AppleICUNumberFormatStrings AppleICUNumberSymbols)
state() {
  local key
  for key in "${keys[@]}"; do
    printf '%s\n' "$key"
    defaults read-type -g "$key" 2>/dev/null || printf '__MISSING_TYPE__\n'
    defaults read -g "$key" 2>/dev/null || printf '__MISSING_VALUE__\n'
  done
}
# Deliberately test both existing keys and absent keys, plus dictionary siblings.
defaults write -g AppleMetricUnits -bool false
defaults write -g AppleMeasurementUnits -string Inches
defaults write -g AppleTemperatureUnit -string Fahrenheit
defaults delete -g AppleICUForce24HourTime >/dev/null 2>&1 || true
defaults write -g AppleICUForce12HourTime -bool true
defaults write -g AppleFirstWeekday -dict gregorian 1 buddhist 3
defaults write -g AppleMinDaysInFirstWeek -dict gregorian 1 buddhist 2
defaults write -g AppleICUDateFormatStrings -dict 1 'MM/dd/yyyy'
defaults write -g AppleICUTimeFormatStrings -dict 1 'h:mm a'
defaults write -g AppleICUNumberSymbols -dict 0 '.' 1 ','
state > "$tmp/before"

"$BASH" "$repo_root/eurozone" --preview DE
[ ! -e "$XDG_CONFIG_HOME" ]
"$BASH" "$repo_root/eurozone" --setup
actual="$(defaults read -g AppleLocale)"
[[ "$actual" == en_IE@*calendar=gregorian*currency=EUR* ]]
[ "$(defaults read -g AppleMetricUnits)" = 1 ]
[ "$(defaults read -g AppleMeasurementUnits)" = Centimeters ]
[ "$(defaults read -g AppleTemperatureUnit)" = Celsius ]
[ "$(defaults read -g AppleICUForce24HourTime)" = 1 ]
[ "$(defaults read -g AppleICUForce12HourTime)" = 0 ]
defaults export -g "$tmp/applied.plist"
[ "$(plutil -extract AppleFirstWeekday.gregorian raw -o - "$tmp/applied.plist")" = 2 ]
[ "$(plutil -extract AppleMinDaysInFirstWeek.gregorian raw -o - "$tmp/applied.plist")" = 4 ]
[ "$(plutil -extract AppleFirstWeekday.buddhist raw -o - "$tmp/applied.plist")" = 3 ]
for key in AppleICUDateFormatStrings AppleICUTimeFormatStrings AppleICUNumberFormatStrings AppleICUNumberSymbols; do
  if defaults read -g "$key" >/dev/null 2>&1; then echo "Custom format still overrides profile: $key" >&2; exit 1; fi
done
[ -f "$XDG_CONFIG_HOME/eurozone/profile.active" ]
[ ! -e "$HOME/Library/LaunchAgents/com.eurozone.startup.plist" ]

"$BASH" "$repo_root/eurozone" --profile FR
[[ "$(defaults read -g AppleLocale)" == fr_FR@*currency=EUR* ]]
"$BASH" "$repo_root/eurozone" --restore-profile
state > "$tmp/after"
cmp "$tmp/before" "$tmp/after"
[ ! -e "$XDG_CONFIG_HOME/eurozone/profile.active" ]

# A v2 backup can still undo its smaller scope before a new setup.
legacy="$XDG_CONFIG_HOME/eurozone/profile-backup"
mkdir -p "$legacy"
printf 'present\n' > "$legacy/apple-locale-status"
printf 'en_US\n' > "$legacy/apple-locale"
: > "$legacy/ready"
if "$BASH" "$repo_root/eurozone" --setup DE; then echo 'Applied v3 over a v2 backup' >&2; exit 1; fi
"$BASH" "$repo_root/eurozone" --restore-profile
[ "$(defaults read -g AppleLocale)" = en_US ]
[ ! -e "$legacy" ]

# Stub checks our payload, not a live Karabiner install or non-US input layout.
"$BASH" "$repo_root/eurozone" euro >/dev/null
rule="$HOME/.config/karabiner/assets/complex_modifications/eurozone.json"
launch_agent="$HOME/Library/LaunchAgents/com.eurozone.startup.plist"
[ -f "$rule" ]
[ -f "$launch_agent" ]
grep -q 'eurozone_enabled' "$rule"
grep -q -- '--config-dir' "$launch_agent"
plutil -lint "$launch_agent"
grep -q -- '--set-variables {"eurozone_enabled":1}' "$KARA_LOG"
"$BASH" "$XDG_DATA_HOME/eurozone/eurozone" dollar >/dev/null
# Installed copy must refresh without copying a file onto itself.
grep -q -- '--set-variables {"eurozone_enabled":0}' "$KARA_LOG"
echo 'macOS native European setup/switch/typed-restore and startup payload PASS'
