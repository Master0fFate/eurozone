# eurozone

**European regional settings in one setup. Windows, macOS, and Linux.**

Not just a `$` → `€` key switch. Set country-specific dates, numbers and money,
plus European time and unit preferences where your OS supports them.
Your **display language, keyboard layout, and time zone stay unchanged**.
No administrator access is needed.

## Quick start

Download and extract the **whole release bundle**. Keep the scripts and
`eurozone-profiles.tsv` together.

| OS | Open |
| --- | --- |
| Windows 10 / 11 | Double-click `eurozone.cmd` |
| macOS | Open `eurozone.command`, or run `bash eurozone` in Terminal |
| Linux | Run `bash eurozone` in a terminal in your desktop session |

Press **Enter** for European setup. Pick your country, review the preview,
and confirm. Press Enter at the country prompt for **Ireland (English)**:
euro currency and European formats without changing your interface language.
If macOS blocks a downloaded launcher, run `bash eurozone` from Terminal;
do not disable OS security protections.

There is no single European date or decimal format. France, Germany, Ireland,
and other countries differ. Select the country whose formats you need.
The catalog has **31 locale choices across 21 euro-area countries**, including
Bulgaria. Membership follows the [ECB euro-area list](https://data.ecb.europa.eu/data/geographical-areas)
as of 1 January 2026. Locale availability still depends on your OS.

## What changes

| Setting | Windows | macOS | Linux |
| --- | --- | --- | --- |
| Country date and number formats | Yes | Yes | Installed locale |
| Euro currency | Explicit `€` | Explicit EUR locale override | Installed locale; old currency data is reported |
| 24-hour time | Explicit | Explicit | Locale; GNOME clock also set to 24h when supported |
| Metric units | Explicit | Explicit | Locale measurement category |
| Celsius | App-specific | Explicit | App-specific; metric locale is not a temperature switch |
| A4 paper preference | Explicit | Country/printer default; verify in Print settings | Locale paper category |
| Monday-first / ISO week rules | Explicit | Explicit | Locale; calendars can override it |
| Gregorian calendar | Explicit | Explicit | Locale / application |

Windows also sets the user's home country; undo restores it. macOS backs up
and clears custom ICU date/time/number overrides so country formats can apply.

**These are per-user preferences, not a forced conversion of every app.**
Restart applications or sign out and back in after applying or restoring.
Printer drivers, weather apps, office files, browsers, games and cloud accounts
can keep their own settings. Existing documents and stored amounts are not
rewritten. Changing a currency format does **not** convert money at an exchange rate.

### Linux support

- **GNOME:** regional formats and, when writable, the desktop 24-hour clock.
  Requires a working session bus and the selected UTF-8 locale.
- **Other desktops with a systemd user session:** locale categories in
  `$XDG_CONFIG_HOME/environment.d/90-eurozone-profile.conf` (normally
  `~/.config/environment.d`). These reach processes started through the user
  manager; not every desktop imports them. Sign in again and check your apps.
- **KDE, Xfce and other desktop-specific overrides:** not edited. Their own
  clock/calendar controls can still override locale settings.
- Missing locales or unsupported sessions produce an error, not a success
  message. Install/generate the chosen locale using your distribution's tools.
  No `sudo`, locale installation, or system-wide writes run automatically.
- `LC_ALL` overrides the individual format categories. Remove that override in
  your session configuration if the preview warns about it.

The optional keyboard remap is separate from regional setup. Regional setup
can work on Wayland; the Linux keyboard remap is **X11 only**.

## Preview, apply, undo

```bash
# Linux / macOS
bash eurozone --list-profiles
bash eurozone --preview DE       # Read-only: no startup or settings changes
bash eurozone --setup            # Ireland (English), no interactive questions
bash eurozone --setup FR         # France
bash eurozone --profile IE-EN    # Same full setup, explicit profile required
bash eurozone --restore-profile
bash eurozone --help
```

```powershell
# Windows: use the launcher from PowerShell or Command Prompt
.\eurozone.cmd --preview DE
.\eurozone.cmd --setup
.\eurozone.cmd --setup FR
.\eurozone.cmd --list-profiles
.\eurozone.cmd --restore-profile
```

CLI apply commands are non-interactive: use `--preview` first if uncertain.
The menu always asks for confirmation. Invalid IDs and arguments fail without
applying settings.

The first successful setup keeps an undo point. Switching countries keeps that
original backup. **Restore previous regional settings** (menu **6**) returns the
saved values and removes the backup only after restoration succeeds. Keep your
configuration directory until you no longer need to undo. A restore also undoes
manual edits to the settings in that snapshot since setup.

- Windows configuration: `%APPDATA%\eurozone`
- Linux/macOS configuration: `$XDG_CONFIG_HOME/eurozone`, normally `~/.config/eurozone`

Older v2 regional backups remain usable. On Linux/macOS, restore that backup
before applying a v3 setup. Old backups contain only the settings that v2
saved; they cannot reconstruct changes outside that snapshot.

## Optional Shift+4 shortcut

Menu **1** enables euro input. Menu **2** selects dollar/default input.
These actions install or refresh a **per-user login startup item**. Merely
opening the menu, previewing, or applying regional settings does not install a
keyboard hook or a startup item.

- **Windows:** built-in `RegisterHotKey` / `SendInput` hook. It may miss elevated
  apps. It does not change the keyboard layout. Dollar mode stops the hook and
  restores the layout's own Shift+4 output, which is not `$` on every layout.
- **Linux/X11:** `xkbcomp`, with an `xmodmap` fallback. Not supported on Wayland.
- **macOS:** needs Karabiner-Elements and one-time enabling of the
  **eurozone Shift+4** rule. The rule assumes a US input layout; other layouts
  may produce a different character.

Regional restore does not disable the separate keyboard shortcut. Select
menu **2** to turn off the Windows/macOS euro hook. Existing v2 startup items
remain installed until you remove them yourself.

## Phones, tablets, and other devices

Desktop scripts cannot set system-wide preferences on **iOS/iPadOS, Android,
ChromeOS, TVs or consoles**. No jailbreak, root access or remote-management
bypass is attempted.

- **iPhone/iPad:** Settings → General → Language & Region. Choose your region,
  metric units, Celsius, and Monday where offered. Settings → General → Date &
  Time → 24-Hour Time. Keep automatic time zone selection if you travel.
- **Android:** Settings → System → Languages → Regional preferences (on
  supported versions). Select Celsius and Monday. In Date & time, enable
  24-hour format. Region options vary by device maker and app.
- On other devices, use their regional settings. Choose the desired euro-area
  country and review date, time, units, paper size, and app currency settings.

A format profile does not change your citizenship, billing country, app-store
region, legal residency, electricity standard, network region, or physical
keyboard. Mercifully, it also does not move your time zone to Brussels.

## Testing

Safe checks (no real regional changes):

```bash
bash -n eurozone
bash tests/profile-catalog-smoke.sh
bash tests/unix-isolated-smoke.sh
```

```powershell
pwsh -NoProfile -File tests/windows-isolated-smoke.ps1
```

The cross-OS GitHub Actions workflow also runs **native apply/switch/restore
checks on disposable Windows, macOS and Linux runners**, plus the X11 remap
check. Native test scripts require `EUROZONE_ALLOW_OS_TESTS=1`; do not run them
in your daily-use account. Mock checks are not proof of native integration.

## References

- [Windows measurement setting: 0 = metric, 1 = US](https://learn.microsoft.com/en-us/windows/win32/intl/locale-imeasure)
- [macOS Language & Region settings](https://support.apple.com/guide/mac-help/change-language-region-settings-on-mac-intl163/mac)
- [systemd user environment files](https://www.freedesktop.org/software/systemd/man/latest/environment.d.html)

## License

[Unlicense](LICENSE)
