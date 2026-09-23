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

Stay-open CLI. Type a number. **Shift+4** flips between `$` and `€`.

```
  1  euro
  2  dollar
  3  doctor
  4  quit
```

1 and 2 apply immediately.

## Run (Windows)

```bat
eurozone.cmd
```

Accept the UAC prompt. The first window closes; use the new admin window.
Type `1`, then press Shift+4 in Notepad. You should get €.

No AutoHotkey install. The admin process starts a hidden Shift+4 hook
(`RegisterHotKey` + `SendInput`). Dollar mode (`2`) kills the hook so
the layout types `$` again.

The first run also installs a per-user startup copy in
`%LOCALAPPDATA%\eurozone` and registers it under the launching user's Windows
`Run` key. The mode file stays in that user's `%APPDATA%\eurozone` directory,
even if UAC uses credentials for a different administrator account. At the
next sign-in, euro mode is restored automatically; dollar mode stays off. The
startup hook runs without an admin prompt, so it cannot type into elevated
applications. Launch `eurozone.cmd` manually when the hook must also work in
elevated windows. Running the launcher again refreshes the installed startup
copy and its saved paths.

The hidden hook keeps running after the menu closes. Pick `2` before
quitting if you want `$` back.

## Linux / macOS

```bash
chmod +x eurozone
./eurozone
```

The first run installs a per-user login item and refreshes its private copy
of the launcher. The login item stores the exact config path used for the mode
file, so a different XDG environment at login cannot silently reset the
selection. No sudo prompt is needed: `xmodmap` must run as the logged-in Linux
user, not root.

- **Linux (X11):** installs `~/.config/autostart/eurozone.desktop`. At the
  next graphical login it restores the saved mode with `xmodmap`. Wayland does
  not support `xmodmap`, so this release cannot remap it.
- **macOS:** installs
  `~/Library/LaunchAgents/com.eurozone.startup.plist`, which restores the saved
  mode at login using the config path captured at install time. It also places
  the rule in Karabiner-Elements’ `assets/complex_modifications` directory.
  Enable the **eurozone Shift+4** rule once in Karabiner-Elements; thereafter
  the login item retries setting its `eurozone_enabled` variable while
  Karabiner starts, and switches it on for euro mode or off for dollar mode.

Run the launcher again after updating it to refresh the installed login copy.

## License

Unlicense
