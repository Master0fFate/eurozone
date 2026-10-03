#!/usr/bin/env bash
# Safe on a developer machine: every OS backend command is a local stub.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/config with spaces"
export XDG_CACHE_HOME="$tmp/cache"
export XDG_DATA_HOME="$tmp/data"
export EZ_TEST_STATE="$tmp/state"
export DBUS_SESSION_BUS_ADDRESS='unix:path=/eurozone-test-only'
export LC_ALL=C
mkdir -p "$HOME" "$tmp/bin" "$EZ_TEST_STATE"
export PATH="$tmp/bin:$PATH"

cat > "$tmp/bin/uname" <<'STUB'
#!/bin/sh
printf '%s\n' "${EZ_TEST_OS:-Linux}"
STUB
cat > "$tmp/bin/locale" <<'STUB'
#!/bin/sh
if [ "${1:-}" = '-a' ]; then
  printf 'C\nC.UTF-8\n'
  if [ "${EZ_NO_LOCALES:-0}" != 1 ]; then printf 'en_IE.utf8\nde_DE.utf8\nfr_FR.utf8\n'; fi
else
  case "${1:-}" in
    int_curr_symbol) printf '%s\n' "${EZ_TEST_CURRENCY:-EUR }" ;;
    t_fmt) printf '%%H:%%M:%%S\n' ;;
    first_weekday) printf '2\n' ;;
    week) printf '7;19971130;4\n' ;;
    *) printf 'int_curr_symbol="EUR "\nmeasurement=1\nheight=297\nwidth=210\nfirst_weekday=2\n' ;;
  esac
fi
STUB
cat > "$tmp/bin/gsettings" <<'STUB'
#!/bin/sh
schema="${2:-}"
key="${3:-}"
file="$EZ_TEST_STATE/$schema.$key"
[ "${EZ_NO_GNOME:-0}" != 1 ] || exit 1
case "${1:-}" in
  list-schemas) printf 'org.gnome.system.locale\norg.gnome.desktop.interface\n' ;;
  list-keys)
    case "$schema" in
      org.gnome.system.locale) printf 'region\n' ;;
      org.gnome.desktop.interface) printf 'clock-format\n' ;;
    esac ;;
  writable) printf 'true\n' ;;
  get)
    if [ -f "$file" ]; then cat "$file";
    elif [ "$key" = region ]; then printf "'en_US.UTF-8'\n";
    elif [ "$key" = clock-format ]; then printf "'12h'\n";
    else exit 1; fi ;;
  set)
    if [ "${EZ_FAIL_KEY:-}" = "$key" ] && [ ! -f "$EZ_TEST_STATE/failed-once" ]; then
      : > "$EZ_TEST_STATE/failed-once"
      exit 1
    fi
    printf '%s\n' "${4:-}" > "$file" ;;
  *) exit 1 ;;
esac
STUB
cat > "$tmp/bin/systemctl" <<'STUB'
#!/bin/sh
[ "${EZ_NO_SYSTEMD:-0}" != 1 ] || exit 1
case "$*" in
  '--user show-environment') printf 'PATH=/test\n' ;;
  *) exit 1 ;;
esac
STUB
# Any accidental keyboard/startup execution fails instead of reaching the host.
for command in xmodmap xkbcomp defaults karabiner_cli; do
  printf '#!/bin/sh\necho "unexpected backend call: %s" >&2\nexit 91\n' "$command" > "$tmp/bin/$command"
done
chmod +x "$tmp/bin/"*

run() { bash "$repo_root/eurozone" "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
reject() {
  if run "$@" > "$tmp/rejected.log" 2>&1; then fail "accepted invalid input: $*"; fi
}

run --help > "$tmp/help"
run --list-profiles > "$tmp/profiles"
run --preview DE > "$tmp/preview"
run --preview > "$tmp/default-preview"
grep -q 'de-DE' "$tmp/preview"
grep -q 'en-IE' "$tmp/default-preview"
reject --profile NOT-A-COUNTRY
reject --profile
reject --preview NOT-A-COUNTRY
reject --setup NOT-A-COUNTRY
reject --setup DE stray
reject --preview DE stray
reject --restore-profile stray
reject --not-an-option
[ ! -e "$XDG_CONFIG_HOME" ] || fail 'read-only or rejected command created config'
[ ! -e "$XDG_CACHE_HOME" ] || fail 'read-only or rejected command created cache'
[ ! -e "$XDG_DATA_HOME" ] || fail 'read-only or rejected command installed startup'

# Unknown OS must not write profile state either.
if EZ_TEST_OS=Plan9 run --setup DE > "$tmp/unsupported.log" 2>&1; then fail 'unsupported OS accepted'; fi
[ ! -e "$XDG_CONFIG_HOME/eurozone/profile.active" ] || fail 'unsupported OS marked active'

# Installed locales are required even when GNOME is available.
if EZ_NO_LOCALES=1 run --setup DE > "$tmp/missing.log" 2>&1; then fail 'missing locale accepted'; fi
[ ! -f "$EZ_TEST_STATE/org.gnome.system.locale.region" ] || fail 'missing locale changed GNOME'
[ ! -e "$XDG_CONFIG_HOME/eurozone/profile.active" ] || fail 'missing locale marked active'
if EZ_TEST_CURRENCY=BGN run --setup DE > "$tmp/currency.log" 2>&1; then fail 'stale non-euro locale accepted'; fi
[ ! -f "$EZ_TEST_STATE/org.gnome.system.locale.region" ] || fail 'stale currency changed GNOME'

unset LC_ALL
region_file="$EZ_TEST_STATE/org.gnome.system.locale.region"
clock_file="$EZ_TEST_STATE/org.gnome.desktop.interface.clock-format"
printf "'en_US.UTF-8'\n" > "$region_file"
printf "'12h'\n" > "$clock_file"
environment_file="$XDG_CONFIG_HOME/environment.d/90-eurozone-profile.conf"
mkdir -p "$(dirname "$environment_file")"
printf '# prior user config\nLC_NUMERIC=before-profile\n' > "$environment_file"
cp "$environment_file" "$tmp/original-environment"

run --setup DE
[ "$(cat "$region_file")" = "'de_DE.UTF-8'" ] || fail 'GNOME region not set'
# GSettings accepts either quoted or unquoted strings on its command line.
[ "$(tr -d "'" < "$clock_file")" = 24h ] || fail 'GNOME clock not 24h'
grep -q '^LC_MONETARY=de_DE.UTF-8$' "$environment_file"
grep -q '^LC_MEASUREMENT=de_DE.UTF-8$' "$environment_file"
grep -q '^LC_PAPER=de_DE.UTF-8$' "$environment_file"
if grep -Eq '^(LANG|LANGUAGE|LC_MESSAGES|LC_ALL)=' "$environment_file"; then fail 'language/LC_ALL overwritten'; fi
[ -f "$XDG_CONFIG_HOME/eurozone/profile.active" ] || fail 'no active state after setup'
[ ! -e "$XDG_CONFIG_HOME/autostart" ] || fail 'regional setup installed keyboard startup'

run --profile FR
[ "$(cat "$region_file")" = "'fr_FR.UTF-8'" ] || fail 'profile switch failed'
run --restore-profile
[ "$(cat "$region_file")" = "'en_US.UTF-8'" ] || fail 'region not restored'
[ "$(tr -d "'" < "$clock_file")" = 12h ] || fail 'clock not restored'
cmp "$tmp/original-environment" "$environment_file"
[ ! -e "$XDG_CONFIG_HOME/eurozone/profile.active" ] || fail 'active marker survived restore'
reject --restore-profile

# Verify a previously absent environment file is removed on restore.
rm "$environment_file"
run --setup
[ "$(cat "$region_file")" = "'en_IE.UTF-8'" ] || fail 'quick setup default not en-IE'
run --restore-profile
[ ! -e "$environment_file" ] || fail 'new environment file survived restore'

# No desktop backend: report failure, never write an active marker.
if EZ_NO_GNOME=1 EZ_NO_SYSTEMD=1 run --setup DE > "$tmp/backend.log" 2>&1; then fail 'unsupported session accepted'; fi
[ ! -e "$XDG_CONFIG_HOME/eurozone/profile.active" ] || fail 'unsupported session marked active'

echo 'Isolated Unix CLI, preview, locale preflight, setup/switch/restore PASS'
