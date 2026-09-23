```
                    *
               *         *
           *                 *
         *                     *
           *                 *
               *         *
                    *

  ____  _   _  ____    ___   _____  ___   _   _  ____
 |  __|| | | ||  _ \  / _ \ |__  / / _ \ | \ | ||  __|
 | |_  | | | || |_) || | | |  / / | | | ||  \| || |_
 |  _| | |_| ||  _ < | |_| | / /_ | |_| || |\  ||  _|
 |____| \___/ |_| \_\ \___/ /____| \___/ |_| \_||____|
```

# eurozone

A per-user Euro-area regional profile tool, plus an optional **Shift+4** shortcut
for `$` or `€`.

The country profile changes regional date, number, and currency formatting. It
keeps the operating-system display language, keyboard layout, and time zone as
they are. Those are separate choices; there is no single format for every
Euro-area country.

```
  1  euro shortcut
  2  dollar shortcut
  3  doctor
  4  quit
  5  country / regional format profile
  6  restore previous regional settings
```

The shared presets are in `eurozone-profiles.tsv`. Multilingual countries have
more than one locale option. The list follows [ECB Euro-area membership as of
1 January 2026](https://data.ecb.europa.eu/data/geographical-areas); update the
catalog as membership changes.

## Run (Windows)

```bat
eurozone.cmd
```

The menu runs as your current user. No admin prompt is needed to apply a
regional profile. Choose **5**, then enter a profile ID such as `FR` or
`IE-EN`. Windows uses that user's culture, sets the currency symbol to `€`,
and selects metric measurement. It does not change the Windows display
language, keyboard, or time zone. Some apps need to restart or sign out/in to
use the new formats. **6** restores the prior Windows regional settings.

The optional key hook uses Windows `RegisterHotKey` and `SendInput`; it runs
with the menu's permissions. It can miss elevated apps when eurozone runs as a
standard user. Use an elevated launch only if you need the shortcut inside an
elevated app. Regional profiles should be applied in the account you want to
change.

The first interactive run installs a per-user startup copy in
`%LOCALAPPDATA%\eurozone` and registers it under that user's Windows `Run` key.
At sign-in, the hook restores the saved `$` or `€` shortcut. The installed copy
includes the profile catalog and saved user paths.

CLI examples:

```powershell
.\eurozone.ps1 --list-profiles
.\eurozone.ps1 --profile IE-EN
.\eurozone.ps1 --restore-profile
```

## Run (Linux / macOS)

```bash
chmod +x eurozone
./eurozone
```

Use menu option **5** to choose a country/locale profile. CLI equivalents:

```bash
./eurozone --list-profiles
./eurozone --profile FR
./eurozone --restore-profile
```

- **Linux:** GNOME uses its per-user regional-format setting. A systemd user
  session can use `~/.config/environment.d` for number, date, measurement, and
  paper formats. The locale must be installed for this fallback. Other Linux
  desktop environments can report unsupported. The Shift+4 remap still needs
  X11 and `xmodmap`; it does not work on Wayland.
- **macOS:** the profile uses the user's `AppleLocale` setting for regional
  formats. Existing separate measurement, temperature, and time-zone choices
  are left unchanged. The Shift+4 remap uses Karabiner-Elements: enable the
  **eurozone Shift+4** rule once, then login restores the shortcut state.

Profiles are reversible and per-user. They do not set the time zone or
keyboard layout. Applications can use their own regional settings and may
ignore the operating-system profile. Country formats come from the OS locale
data, so keep that data up to date (especially for recently changed currency
rules).

Run the launcher again after updating it to refresh its per-user startup copy.

## License

Unlicense
