# Changelog

## 3.0.0

### European setup

- Quick setup from the menu or `--setup [PROFILE]`; default: Ireland (English).
- Read-only `--preview [PROFILE]` and `--help`.
- Country-specific dates, numbers and euro currency, with explicit European
  preferences where the OS exposes them.
- Windows: 24-hour time, metric units, A4, Monday-first weeks, ISO first-week
  rule, Gregorian calendar and two euro fractional digits.
- macOS: euro locale, Gregorian calendar, metric units, Celsius,
  24-hour time and Monday/ISO week preferences. Clear and back up custom ICU
  format overrides. Paper size follows country/printer defaults; verify A4
  in Print settings.
- Linux: installed UTF-8 locale preflight, GNOME regional formats and 24-hour
  clock, plus per-user systemd locale categories when supported.
- macOS double-click launcher: `eurozone.command`.

### Safety and corrections

- Correct Windows metric measurement to `iMeasure=0` (1 means US units).
- Preserve language, input layout, and time zone.
- Preserve the original undo point when switching countries. Allow v2 backups
  to be restored before applying the new Linux/macOS setup.
- Check backup and apply failures instead of claiming partial changes succeeded.
- Reject unknown profiles and malformed CLI input without opening the menu.
- Respect `XDG_CONFIG_HOME` for Linux `environment.d` settings.
- Install keyboard startup only after an explicit keyboard action.
- Keep native OS tests behind an explicit disposable-account guard.

### Compatibility

`--profile PROFILE` now applies the full supported European preset. Existing
keyboard commands and menu options 1–6 remain available; option 7 / Enter opens
setup. App-specific settings and unsupported devices are not silently altered.
Linux uses installed locale data; custom calendar, temperature and desktop
preferences can still need manual changes. Windows has no universal Celsius
preference. Mobile setup is documented, not automated.
