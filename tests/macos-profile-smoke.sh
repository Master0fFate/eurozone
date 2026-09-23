#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/config"
export XDG_CACHE_HOME="$tmp/cache"
export XDG_DATA_HOME="$tmp/data"
export KARA_LOG="$tmp/karabiner.log"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$tmp/bin"
cat > "$tmp/bin/karabiner_cli" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$KARA_LOG"
EOF
chmod +x "$tmp/bin/karabiner_cli"
export PATH="$tmp/bin:$PATH"

before="$(defaults read -g AppleLocale 2>/dev/null || printf '__MISSING__')"
bash "$repo_root/eurozone" --profile IE-EN
actual="$(defaults read -g AppleLocale)"
[ "$actual" = "en_IE" ]
[ -f "$XDG_CONFIG_HOME/eurozone/profile-backup/apple-locale-status" ]
[ -f "$XDG_CONFIG_HOME/eurozone/profile.active" ]

bash "$repo_root/eurozone" --restore-profile
after="$(defaults read -g AppleLocale 2>/dev/null || printf '__MISSING__')"
[ "$after" = "$before" ]
[ ! -e "$XDG_CONFIG_HOME/eurozone/profile.active" ]

# The keyboard service is represented by a local CLI stub. This checks our
# rule, launch-agent, and variable payload, not a live Karabiner install.
bash "$repo_root/eurozone" euro >/dev/null
rule="$HOME/.config/karabiner/assets/complex_modifications/eurozone.json"
launch_agent="$HOME/Library/LaunchAgents/com.eurozone.startup.plist"
[ -f "$rule" ]
[ -f "$launch_agent" ]
grep -q 'eurozone_enabled' "$rule"
grep -q -- '--config-dir' "$launch_agent"
plutil -lint "$launch_agent"
grep -q -- '--set-variables {"eurozone_enabled":1}' "$KARA_LOG"
bash "$repo_root/eurozone" dollar >/dev/null
grep -q -- '--set-variables {"eurozone_enabled":0}' "$KARA_LOG"
echo "macOS regional profile and startup/keyboard configuration PASS"
