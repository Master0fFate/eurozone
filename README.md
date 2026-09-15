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

Leave the menu window open. Closing it does not always kill the hook;
pick `2` first if you want `$` back.

## Linux / macOS

```bash
chmod +x eurozone
./eurozone
```

Asks for sudo on start. Linux X11 uses `xmodmap` on number-row 4.
macOS writes a Karabiner rule (`hooks/karabiner-complex.json`).

## License

Unlicense
