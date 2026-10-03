# eurozone — Shift+4  $ / €
# Windows PowerShell 5.1 + 7. Menu stays open. Regional profiles are per-user.
# Built-in RegisterHotKey hook. AutoHotkey optional.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Version = "3.0.0"

# Startup may pass the user's paths explicitly so the installed copy uses the
# same per-user profile and region settings as the menu.
$script:UserArgs = New-Object 'System.Collections.Generic.List[string]'
$script:ConfigDirOverride = $null
$script:InstallDirOverride = $null
# Validate the entire command before creating directories or touching settings.
try {
    for ($i = 0; $i -lt $args.Count; $i++) {
        $arg = [string]$args[$i]
        if ($arg -in @('--config-dir', '--install-dir')) {
            if ($i + 1 -ge $args.Count -or [string]::IsNullOrWhiteSpace([string]$args[$i + 1]) -or
                ([string]$args[$i + 1]).StartsWith('--')) { throw "missing path for $arg" }
            $value = [string]$args[++$i]
            if ($arg -eq '--config-dir') {
                if ($script:ConfigDirOverride) { throw 'duplicate --config-dir' }
                $script:ConfigDirOverride = $value
            } else {
                if ($script:InstallDirOverride) { throw 'duplicate --install-dir' }
                $script:InstallDirOverride = $value
            }
        } else { [void]$script:UserArgs.Add($arg) }
    }
    $allArgs = @($script:UserArgs.ToArray())
    $cmd = if ($allArgs.Count) { $allArgs[0].ToLowerInvariant() } else { '' }
    if ($allArgs.Count -gt 0 -and [string]::IsNullOrWhiteSpace($cmd)) { throw 'empty command; use --help' }
    switch ($cmd) {
        '--profile' { if ($allArgs.Count -ne 2) { throw '--profile requires exactly one profile ID' } }
        { $_ -in @('--setup', '--preview') } {
            if ($allArgs.Count -gt 2) { throw "$cmd accepts at most one profile ID" }
        }
        { $_ -in @('', '--help', '-h', '--list-profiles', '--restore-profile', '--hook', '--startup',
                '1', 'euro', 'eur', '2', 'dollar', 'usd', '3', '4', 'quit') } {
            if ($allArgs.Count -gt 1) { throw "unexpected arguments after $cmd" }
        }
        default { throw "unknown command '$cmd'; use --help" }
    }
    if ($cmd -in @('--profile', '--setup', '--preview') -and $allArgs.Count -eq 2) {
        if ([string]::IsNullOrWhiteSpace($allArgs[1]) -or $allArgs[1].StartsWith('-')) {
            throw "invalid profile ID; use --list-profiles"
        }
    }
} catch { Write-Host ("argument error: " + $_.Exception.Message); exit 2 }

$ConfDir = if ($script:ConfigDirOverride) { $script:ConfigDirOverride } else { Join-Path $env:APPDATA "eurozone" }
$ModeFile = Join-Path $ConfDir "mode"
$ProfileActiveFile = Join-Path $ConfDir "profile.active"
$ProfileBackupFile = Join-Path $ConfDir "profile.backup.reg"
$ProfileCatalog = Join-Path $PSScriptRoot "eurozone-profiles.tsv"
$InternationalKey = "HKCU:\Control Panel\International"
$InternationalRegistryKey = "HKCU\Control Panel\International"
$PidFile = Join-Path $ConfDir "hook.pid"
$InstallDir = if ($script:InstallDirOverride) { $script:InstallDirOverride } else { Join-Path $env:LOCALAPPDATA "eurozone" }
$InstalledScript = Join-Path $InstallDir "eurozone.ps1"
$RunKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$RunValue = "eurozone"
$WindowsPowerShell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$script:StartupError = $null

function Initialize-EzConfig {
    if (-not (Test-Path -LiteralPath $ConfDir)) {
        New-Item -ItemType Directory -Path $ConfDir -Force | Out-Null
    }
}

function Test-EzAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-EzColor {
    if ($env:NO_COLOR) { return $false }
    return $true
}

function Write-Ez {
    param([string]$Text, [ConsoleColor]$Color = "Cyan")
    if (Test-EzColor) { Write-Host $Text -ForegroundColor $Color }
    else { Write-Host $Text }
}

function Write-Banner {
    $ring = @(
        "                    *",
        "               *         *",
        "           *                 *",
        "         *                     *",
        "           *                 *",
        "               *         *",
        "                    *"
    )
    $mark = @(
        "  ____  _   _  ____    ___   _____  ___   _   _  ____",
        " |  __|| | | ||  _ \  / _ \ |__  / / _ \ | \ | ||  __|",
        " | |_  | | | || |_) || | | |  / / | | | ||  \| || |_",
        " |  _| | |_| ||  _ < | |_| | / /_ | |_| || |\  ||  _|",
        " |____| \___/ |_| \_\ \___/ /____| \___/ |_| \_||____|"
    )
    foreach ($line in $ring) { Write-Ez $line }
    Write-Host ""
    foreach ($line in $mark) { Write-Ez $line }
}

function Get-Mode {
    if (Test-Path $ModeFile) {
        $m = (Get-Content -Path $ModeFile -TotalCount 1).Trim()
        if ($m -eq "euro" -or $m -eq "dollar") { return $m }
    }
    return "dollar"
}

function Set-Mode([string]$Mode) {
    Initialize-EzConfig
    $temporary = Join-Path $ConfDir (".mode." + [Guid]::NewGuid().ToString("N"))
    $backup = $temporary + ".bak"
    [IO.File]::WriteAllText($temporary, ($Mode + "`r`n"), [Text.Encoding]::ASCII)
    try {
        if ([IO.File]::Exists($ModeFile)) {
            # Windows PowerShell 5.1 requires a valid backup path here.
            [IO.File]::Replace($temporary, $ModeFile, $backup)
        } else {
            [IO.File]::Move($temporary, $ModeFile)
        }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
        if ([IO.File]::Exists($backup)) { [IO.File]::Delete($backup) }
    }
}

function Get-Symbol([string]$Mode) {
    if ($Mode -eq "euro") { return [char]0x20AC } else { return "$" }
}

function Write-Ok([string]$Text) { Write-Ez ("  * " + $Text) }

function Get-RegionProfiles {
    if (-not (Test-Path -LiteralPath $ProfileCatalog)) {
        throw "profile catalog not found: $ProfileCatalog"
    }
    return @(Import-Csv -LiteralPath $ProfileCatalog -Delimiter '|')
}

function Get-RegionProfile([string]$Identifier) {
    $query = $Identifier.Trim()
    $profile = Get-RegionProfiles | Where-Object {
        $_.id -eq $query -or $_.culture -eq $query
    } | Select-Object -First 1
    if (-not $profile) { throw "unknown profile '$query'; use --list-profiles" }
    [void][Globalization.CultureInfo]::GetCultureInfo($profile.culture)
    return $profile
}

function Show-RegionProfiles {
    foreach ($profile in (Get-RegionProfiles)) {
        Write-Host ("  {0,-7} {1,-25} {2}" -f $profile.id, $profile.name, $profile.culture)
    }
}

function Save-ProfileActive([string]$ProfileId, [string]$Culture) {
    $temporary = $ProfileActiveFile + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    $backup = $temporary + '.bak'
    try {
        [IO.File]::WriteAllText($temporary, ("{0}|{1}`r`n" -f $ProfileId, $Culture), [Text.Encoding]::ASCII)
        if ([IO.File]::Exists($ProfileActiveFile)) {
            [IO.File]::Replace($temporary, $ProfileActiveFile, $backup)
        } else {
            [IO.File]::Move($temporary, $ProfileActiveFile)
        }
    } finally {
        # Cleanup must not turn a committed metadata write into a failed apply.
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
    }
}

function Get-RegionPlan([string]$Identifier = 'IE-EN') {
    $profile = Get-RegionProfile $Identifier
    # Ignore the current user's overrides: presets must be reproducible.
    $culture = [Globalization.CultureInfo]::new($profile.culture, $false)
    $calendar = @($culture.OptionalCalendars | Where-Object { $_ -is [Globalization.GregorianCalendar] })[0]
    if (-not $calendar) { throw "Gregorian calendar is unavailable for $($profile.culture)" }
    $culture.DateTimeFormat.Calendar = $calendar
    $culture.DateTimeFormat.FirstDayOfWeek = [DayOfWeek]::Monday
    $culture.DateTimeFormat.CalendarWeekRule = [Globalization.CalendarWeekRule]::FirstFourDayWeek
    $culture.DateTimeFormat.TimeSeparator = ':'
    $culture.DateTimeFormat.ShortTimePattern = 'HH:mm'
    $culture.DateTimeFormat.LongTimePattern = 'HH:mm:ss'
    $culture.NumberFormat.CurrencySymbol = [string][char]0x20AC
    $culture.NumberFormat.CurrencyDecimalDigits = 2
    $region = [Globalization.RegionInfo]::new($culture.Name)
    if ($region.GeoId -le 0) { throw "Windows has no supported home-country ID for $($culture.Name)" }
    $number = $culture.NumberFormat
    $date = $culture.DateTimeFormat
    # Windows grouping strings have a terminal zero (repeat the last group).
    $numberGroups = ($number.NumberGroupSizes -join ';')
    if ($number.NumberGroupSizes[-1] -ne 0) { $numberGroups += ';0' }
    $moneyGroups = ($number.CurrencyGroupSizes -join ';')
    if ($number.CurrencyGroupSizes[-1] -ne 0) { $moneyGroups += ';0' }
    $values = [ordered]@{
        sDecimal = $number.NumberDecimalSeparator
        sThousand = $number.NumberGroupSeparator
        sGrouping = $numberGroups
        iDigits = [string]$number.NumberDecimalDigits
        iNegNumber = [string]$number.NumberNegativePattern
        sNegativeSign = $number.NegativeSign
        sPositiveSign = $number.PositiveSign
        sCurrency = [string][char]0x20AC
        sMonDecimalSep = $number.CurrencyDecimalSeparator
        sMonThousandSep = $number.CurrencyGroupSeparator
        sMonGrouping = $moneyGroups
        iCurrency = [string]$number.CurrencyPositivePattern
        iNegCurr = [string]$number.CurrencyNegativePattern
        iCurrDigits = '2'
        iIntlCurrDigits = '2'
        sShortDate = $date.ShortDatePattern
        sLongDate = $date.LongDatePattern
        sYearMonth = $date.YearMonthPattern
        sDate = $date.DateSeparator
        sTime = ':'
        sShortTime = 'HH:mm'
        sTimeFormat = 'HH:mm:ss'
        iTime = '1'
        iTimePrefix = '0'
        iTLZero = '1'
        iMeasure = '0'
        iFirstDayOfWeek = '0'
        iFirstWeekOfYear = '2'
        iCalendarType = [string][int]$calendar.CalendarType
        iPaperSize = '9'
    }
    return [pscustomobject]@{ Profile = $profile; Culture = $culture; Region = $region; Values = $values }
}

function Show-RegionPreview([string]$Identifier = 'IE-EN') {
    $plan = Get-RegionPlan $Identifier
    $sample = [datetime]::new(2026, 12, 31, 17, 45, 30)
    Write-Host ("  European setup: {0} ({1})" -f $plan.Profile.name, $plan.Culture.Name)
    Write-Host ("  Date     {0} | {1}" -f $sample.ToString('d', $plan.Culture), $sample.ToString('D', $plan.Culture))
    Write-Host ("  Time     {0} | {1} (24-hour)" -f $sample.ToString('t', $plan.Culture), $sample.ToString('T', $plan.Culture))
    Write-Host ("  Number   {0}" -f (1234567.89).ToString('N', $plan.Culture))
    Write-Host ("  Currency {0} | {1} (EUR symbol, two decimals)" -f (1234567.89).ToString('C', $plan.Culture), (-1234.56).ToString('C', $plan.Culture))
    Write-Host ("  Patterns date={0}; time=HH:mm / HH:mm:ss" -f $plan.Values.sShortDate)
    Write-Host '  Metric; Monday first; ISO first week (four-day rule); Gregorian; A4 paper.'
    Write-Host ("  Home country: {0} (GeoID {1}). Current Windows user only." -f $plan.Region.EnglishName, $plan.Region.GeoId)
    Write-Host '  Unchanged: display language, input layouts, Shift+4, startup, time zone, system/admin settings.'
    Write-Host '  Celsius: Windows has no supported global preference; choose Celsius in each app.'
    Write-Host '  Apps/printer drivers may override formats, week rules or paper size; restart apps/sign out as needed.'
    if ($plan.Region.ISOCurrencySymbol -ne 'EUR') {
        Write-Host ("  Windows locale metadata still reports {0}; EUR symbol is forced, not the OS ISO currency code." -f $plan.Region.ISOCurrencySymbol)
    }
    Write-Host '  Preview is read-only. Apply saves the original regional registry (including home country) for restore.'
}

function Export-RegionSnapshot([string]$Path) {
    $temporary = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $regExe = Join-Path $env:SystemRoot 'System32\reg.exe'
        & $regExe export $InternationalRegistryKey $temporary /y | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($temporary)) {
            throw 'could not back up the current Windows regional registry; nothing was applied'
        }
        # Never overwrite the original baseline, even when switching profiles.
        [IO.File]::Move($temporary, $Path)
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function Import-RegionSnapshot([string]$Path) {
    if (-not [IO.File]::Exists($Path)) { throw "regional snapshot missing: $Path" }
    # Import alone merges values and leaves newly added keys behind. Replacing
    # this entire per-user tree restores value types, subkeys and absent values.
    if (Test-Path -LiteralPath $InternationalKey) {
        Remove-Item -LiteralPath $InternationalKey -Recurse -Force
    }
    $regExe = Join-Path $env:SystemRoot 'System32\reg.exe'
    & $regExe import $Path | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "could not import regional snapshot: $Path" }
}

function Undo-RegionFailure([string]$Snapshot, [string]$Failure) {
    try { Import-RegionSnapshot $Snapshot }
    catch {
        throw ("{0}; ROLLBACK FAILED: {1}. Settings may be partial. Recovery snapshot retained at {2}; original backup at {3}" -f
            $Failure, $_.Exception.Message, $Snapshot, $ProfileBackupFile)
    }
    Remove-Item -LiteralPath $Snapshot -Force -ErrorAction SilentlyContinue
    throw "$Failure; previous regional registry recovered. Restart apps/sign out to refresh cached formats."
}

function Set-RegionProfile([string]$Identifier) {
    $plan = Get-RegionPlan $Identifier
    # Fail before any settings writes on hosts missing the per-user Windows API.
    $null = Get-Command Set-Culture -ErrorAction Stop
    $null = Get-Command Set-WinHomeLocation -ErrorAction Stop
    Initialize-EzConfig
    $currentSnapshot = Join-Path $ConfDir ('.profile-current.' + [Guid]::NewGuid().ToString('N') + '.reg')
    Export-RegionSnapshot $currentSnapshot
    try {
        if (-not [IO.File]::Exists($ProfileBackupFile)) {
            # Copy an already completed snapshot; publish atomically.
            $temporary = $ProfileBackupFile + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
            try {
                [IO.File]::Copy($currentSnapshot, $temporary)
                [IO.File]::Move($temporary, $ProfileBackupFile)
            } finally {
                if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
            }
        }
    } catch {
        Remove-Item -LiteralPath $currentSnapshot -Force -ErrorAction SilentlyContinue
        throw
    }
    try {
        Set-Culture -CultureInfo $plan.Culture
        foreach ($name in $plan.Values.Keys) {
            New-ItemProperty -LiteralPath $InternationalKey -Name $name -Value $plan.Values[$name] -PropertyType String -Force | Out-Null
        }
        Set-WinHomeLocation -GeoId $plan.Region.GeoId
        foreach ($name in $plan.Values.Keys) {
            $actual = Get-ItemPropertyValue -LiteralPath $InternationalKey -Name $name
            if ([string]$actual -cne [string]$plan.Values[$name]) { throw "regional setting verification failed: $name" }
        }
        $locale = Get-ItemPropertyValue -LiteralPath $InternationalKey -Name LocaleName
        if ($locale -ne $plan.Culture.Name) { throw 'regional culture verification failed' }
        $nation = Get-ItemPropertyValue -LiteralPath (Join-Path $InternationalKey 'Geo') -Name Nation
        if ([string]$nation -ne [string]$plan.Region.GeoId) { throw 'home country verification failed' }
        Save-ProfileActive $plan.Profile.id $plan.Culture.Name
    } catch { Undo-RegionFailure $currentSnapshot $_.Exception.Message }
    Remove-Item -LiteralPath $currentSnapshot -Force -ErrorAction SilentlyContinue
    Write-Ok ("European setup applied: {0} ({1})" -f $plan.Profile.name, $plan.Culture.Name)
    Write-Ok 'EUR symbol, two decimals; country date/number formats; 24-hour time; metric; Monday/ISO week; Gregorian; A4; home country'
    Write-Ok 'display language, input layouts, keyboard hook, startup and time zone were not changed'
    Write-Ok 'Celsius must be selected per app; apps/printers may override regional defaults'
    if ($plan.Region.ISOCurrencySymbol -ne 'EUR') {
        Write-Host ("  WARNING: Windows locale metadata reports {0}; EUR symbol is forced, not the OS ISO currency code." -f $plan.Region.ISOCurrencySymbol)
    }
    Write-Ok 'restart apps or sign out and back in if formats do not update'
}

function Restore-RegionProfile {
    if (-not [IO.File]::Exists($ProfileBackupFile)) { throw 'no saved Windows regional settings to restore' }
    $currentSnapshot = Join-Path $ConfDir ('.profile-current.' + [Guid]::NewGuid().ToString('N') + '.reg')
    Export-RegionSnapshot $currentSnapshot
    $hadActive = [IO.File]::Exists($ProfileActiveFile)
    $active = if ($hadActive) { ,([IO.File]::ReadAllBytes($ProfileActiveFile)) } else { $null }
    try {
        Import-RegionSnapshot $ProfileBackupFile
        if ([IO.File]::Exists($ProfileActiveFile)) { [IO.File]::Delete($ProfileActiveFile) }
        # Consume the original backup only after the complete import succeeds.
        [IO.File]::Delete($ProfileBackupFile)
    } catch {
        $failure = $_.Exception.Message
        if ($hadActive) {
            try { [IO.File]::WriteAllBytes($ProfileActiveFile, [byte[]]$active) }
            catch { $failure += '; active-profile metadata could not be recovered: ' + $_.Exception.Message }
        }
        Undo-RegionFailure $currentSnapshot $failure
    }
    Remove-Item -LiteralPath $currentSnapshot -Force -ErrorAction SilentlyContinue
    Write-Ok 'previous Windows regional registry and home country restored (including removal of added values/keys)'
    Write-Ok 'restart apps or sign out and back in if formats do not update'
}

function Select-RegionProfile {
    try {
        Show-RegionProfiles
        $choice = (Read-Host '  country/profile ID [IE-EN]').Trim()
        if (-not $choice) { $choice = 'IE-EN' }
        $profile = Get-RegionProfile $choice
        Show-RegionPreview $profile.id
        $confirm = Read-Host '  apply European setup? [y/N]'
        if ($confirm.Trim() -notmatch '^(y|yes)$') {
            Write-Ok 'no regional settings changed'
            return $false
        }
        Set-RegionProfile $profile.id
        return $true
    } catch {
        Write-Ez ('setup failed: ' + $_.Exception.Message) Red
        return $false
    }
}

function Get-StartupCommand {
    return ('"{0}" -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{1}" --startup --config-dir "{2}" --install-dir "{3}"' -f `
        $WindowsPowerShell, $InstalledScript, $ConfDir, $InstallDir)
}

function Install-EzStartup {
    try {
        if (-not (Test-Path $InstallDir)) {
            New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        }
        $source = [IO.Path]::GetFullPath($PSCommandPath)
        $destination = [IO.Path]::GetFullPath($InstalledScript)
        if (-not $source.Equals($destination, [StringComparison]::OrdinalIgnoreCase)) {
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
        $catalogDestination = [IO.Path]::GetFullPath((Join-Path $InstallDir 'eurozone-profiles.tsv'))
        if (-not ([IO.Path]::GetFullPath($ProfileCatalog)).Equals($catalogDestination, [StringComparison]::OrdinalIgnoreCase)) {
            Copy-Item -LiteralPath $ProfileCatalog -Destination $catalogDestination -Force
        }
        if (-not (Test-Path $RunKey)) {
            New-Item -Path $RunKey -Force | Out-Null
        }
        Set-ItemProperty -Path $RunKey -Name $RunValue -Value (Get-StartupCommand)
        $script:StartupError = $null
        return $true
    } catch {
        $script:StartupError = $_.Exception.Message
        return $false
    }
}

function Test-EzStartup {
    try {
        $actual = Get-ItemPropertyValue -Path $RunKey -Name $RunValue -ErrorAction Stop
        return $actual -eq (Get-StartupCommand)
    } catch {
        return $false
    }
}

function Get-HookPid {
    if (-not (Test-Path $PidFile)) { return $null }
    $raw = (Get-Content -Path $PidFile -TotalCount 1).Trim()
    $n = 0
    if (-not [int]::TryParse($raw, [ref]$n)) {
        Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
        return $null
    }
    $proc = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $n" -ErrorAction SilentlyContinue
    $commandLine = if ($proc) { [string]$proc.CommandLine } else { "" }
    $isThisScript = $commandLine.IndexOf($PSCommandPath, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $commandLine.IndexOf($InstalledScript, [StringComparison]::OrdinalIgnoreCase) -ge 0
    $isHook = $isThisScript -and $commandLine.IndexOf("--hook", [StringComparison]::OrdinalIgnoreCase) -ge 0
    if ($isHook) { return $n }
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
    return $null
}

function Stop-EzHook {
    $n = Get-HookPid
    if ($n) {
        Stop-Process -Id $n -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
}

function Start-EzHook {
    Initialize-EzConfig
    Stop-EzHook
    $self = $PSCommandPath
    $arg = ('-NoProfile -STA -ExecutionPolicy Bypass -File "{0}" --hook --config-dir "{1}" --install-dir "{2}"' -f `
        $self, $ConfDir, $InstallDir)
    $p = Start-Process -FilePath "powershell.exe" -PassThru -WindowStyle Hidden -ArgumentList $arg
    Set-Content -Path $PidFile -Value ([string]$p.Id) -Encoding ASCII
}

function Set-KeyboardMode([string]$Mode) {
    Set-Mode $Mode
    if (-not (Install-EzStartup)) {
        throw ("keyboard startup installation failed: " + $script:StartupError)
    }
    Invoke-Apply
}

function Invoke-Apply {
    $mode = Get-Mode
    if ($mode -eq "euro") {
        Start-EzHook
        Start-Sleep -Milliseconds 800
        if (Get-HookPid) {
            Write-Ok ("Shift+4 -> " + [char]0x20AC + "   user-level hook running")
        } else {
            Write-Ok "hook failed to start"
        }
    } else {
        Stop-EzHook
        Write-Ok "Shift+4 -> `$   hook off (layout default)"
    }
}

function Show-Doctor {
    Write-Host ""
    Write-Ok "version     $Version"
    Write-Ok ("mode        " + (Get-Mode) + "  " + (Get-Symbol (Get-Mode)))
    Write-Ok ("mode file   " + $ModeFile)
    Write-Ok ("region      " + (Get-Culture).Name)
    if (Test-Path $ProfileActiveFile) { Write-Ok ("profile     " + (Get-Content $ProfileActiveFile -TotalCount 1).Trim()) }
    Write-Ok ("admin       " + (Test-EzAdmin))
    Write-Ok ("windows     " + [Environment]::OSVersion.VersionString)
    Write-Ok ("powershell  " + $PSVersionTable.PSVersion.ToString())
    $hp = Get-HookPid
    if ($hp) { Write-Ok "hook        running  pid $hp" } else { Write-Ok "hook        not running" }
    if (Test-EzStartup) { Write-Ok "startup     registered" } else { Write-Ok "startup     not registered" }
    Write-Host ""
    Write-Host "  press Enter to go back"
    [void](Read-Host)
}

function Show-Menu {
    $last = ""
    while ($true) {
        Clear-Host
        Write-Banner
        Write-Host ""
        $mode = Get-Mode
        $hp = Get-HookPid
        $hookTxt = if ($hp) { "hook on" } else { "hook off" }
        $culture = (Get-Culture).Name
        $profile = if (Test-Path $ProfileActiveFile) { (Get-Content $ProfileActiveFile -TotalCount 1).Trim() } else { "none" }
        Write-Host ("  now  " + $mode + "  Shift+4 -> " + (Get-Symbol $mode) + "   " + $hookTxt)
        Write-Host ("  region " + $culture + "   profile " + $profile)
        if (-not (Test-EzAdmin)) { Write-Host "  WARNING  not admin  remap will miss elevated windows" }
        if ($script:StartupError) { Write-Host ("  WARNING  startup registration failed: " + $script:StartupError) }
        if ($last) { Write-Ez ("  " + $last) }
        Write-Host ""
        $a1 = ""
        $a2 = ""
        if ($mode -eq "euro") { $a1 = "  [active]" }
        if ($mode -eq "dollar") { $a2 = "  [active]" }
        Write-Ez '  7  European setup (recommended; Enter default)'
        Write-Host '     country formats, EUR, 24h, metric, Monday/ISO week, Gregorian, A4'
        Write-Host ''
        Write-Host ("  1  euro     Shift+4 becomes " + [char]0x20AC + $a1)
        Write-Host ("  2  dollar   Shift+4 becomes `$ " + $a2)
        Write-Host "  3  doctor"
        Write-Host "  4  quit"
        Write-Host "  5  country / regional format profile"
        Write-Host "  6  restore previous regional settings"
        Write-Host ""
        $choice = Read-Host '  choice [7]'
        switch -Regex ($choice.Trim()) {
            "^(1|e|euro)$" {
                try { Set-KeyboardMode 'euro'; $last = 'applied euro keyboard mode' }
                catch { $last = 'keyboard mode failed: ' + $_.Exception.Message }
            }
            "^(2|d|dollar)$" {
                try { Set-KeyboardMode 'dollar'; $last = 'applied dollar keyboard mode' }
                catch { $last = 'keyboard mode failed: ' + $_.Exception.Message }
            }
            "^3$" {
                Clear-Host
                Write-Banner
                Show-Doctor
            }
            "^(4|q|quit|x|exit)$" {
                return
            }
            '^(5|7)?$' {
                if (Select-RegionProfile) { $last = 'European setup applied' } else { $last = 'setup was not applied' }
            }
            "^6$" {
                try { Restore-RegionProfile; $last = "previous regional settings restored" }
                catch { $last = "restore failed: " + $_.Exception.Message }
            }
            default { $last = 'press Enter for European setup, or type 1-7' }
        }
    }
}

function Start-HookLoop {
    Initialize-EzConfig
    $code = @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class EzHook : Form {
    private const int WM_HOTKEY = 0x0312;
    private const uint MOD_SHIFT = 0x0004;
    private const uint MOD_NOREPEAT = 0x4000;
    private const uint VK_4 = 0x34;
    private const int HOTKEY_ID = 0x45A4;
    private const uint INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_UNICODE = 0x0004;
    private const uint KEYEVENTF_KEYUP = 0x0002;

    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [StructLayout(LayoutKind.Sequential)]
    struct KEYBDINPUT {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct MOUSEINPUT {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct HARDWAREINPUT {
        public uint uMsg;
        public ushort wParamL;
        public ushort wParamH;
    }
    [StructLayout(LayoutKind.Explicit)]
    struct InputUnion {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public HARDWAREINPUT hi;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct INPUT {
        public uint type;
        public InputUnion U;
    }

    public EzHook() {
        FormBorderStyle = FormBorderStyle.FixedToolWindow;
        ShowInTaskbar = false;
        WindowState = FormWindowState.Minimized;
        Opacity = 0;
        Width = 0;
        Height = 0;
        Text = "eurozone-hook";
    }

    protected override void OnHandleCreated(EventArgs e) {
        base.OnHandleCreated(e);
        RegisterHotKey(Handle, HOTKEY_ID, MOD_SHIFT | MOD_NOREPEAT, VK_4);
    }

    protected override void OnFormClosing(FormClosingEventArgs e) {
        UnregisterHotKey(Handle, HOTKEY_ID);
        base.OnFormClosing(e);
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_HOTKEY && m.WParam.ToInt32() == HOTKEY_ID) {
            SendEuro();
        }
        base.WndProc(ref m);
    }

    static void SendEuro() {
        INPUT[] inputs = new INPUT[2];
        inputs[0].type = INPUT_KEYBOARD;
        inputs[0].U.ki.wVk = 0;
        inputs[0].U.ki.wScan = 0x20AC;
        inputs[0].U.ki.dwFlags = KEYEVENTF_UNICODE;
        inputs[1].type = INPUT_KEYBOARD;
        inputs[1].U.ki.wVk = 0;
        inputs[1].U.ki.wScan = 0x20AC;
        inputs[1].U.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
        SendInput(2, inputs, Marshal.SizeOf(typeof(INPUT)));
    }
}
"@
    $log = Join-Path $ConfDir "hook.log"
    try {
        Add-Type -TypeDefinition $code -ReferencedAssemblies System.Windows.Forms, System.Drawing
        $form = New-Object EzHook
        Set-Content -Path $log -Value "hook started $(Get-Date -Format o)" -Encoding ASCII
        [void][System.Windows.Forms.Application]::Run($form)
    } catch {
        Set-Content -Path $log -Value ("hook failed: " + $_) -Encoding ASCII
        exit 1
    }
}

function Show-EzHelp {
    Write-Host "eurozone $Version - per-user European regional setup"
    Write-Host '  --setup [ID]       apply complete setup (default IE-EN)'
    Write-Host '  --preview [ID]     read-only samples and scope (default IE-EN)'
    Write-Host '  --profile ID       same complete setup, explicit country/profile'
    Write-Host '  --list-profiles    list country/profile IDs and locale codes'
    Write-Host '  --restore-profile restore the original regional registry and home country'
    Write-Host '  --help             show this help without writes'
    Write-Host '  euro | dollar      explicit Shift+4 keyboard mode and startup installation'
    Write-Host '  no command         menu (Enter: European setup; preview then confirmation)'
    Write-Host '  --config-dir PATH / --install-dir PATH: optional per-user storage paths'
    Write-Host '  Setup: EUR symbol/two decimals, local numbers/dates, HH:mm/HH:mm:ss,'
    Write-Host '  metric, Monday/ISO first week, Gregorian, A4 and home country.'
    Write-Host '  No display language, input layout, time zone, admin or system-wide changes.'
    Write-Host '  Celsius is per-app on Windows. Apps/printers can override regional defaults.'
    Write-Host '  Setup does not install startup or change the keyboard hook.'
}

try {
    switch ($cmd) {
        { $_ -in @('--help', '-h') } { Show-EzHelp }
        '--list-profiles' { Show-RegionProfiles }
        { $_ -in @('--profile', '--setup', '--preview') } {
            $identifier = if ($allArgs.Count -eq 2) { $allArgs[1] } else { 'IE-EN' }
            if ($cmd -eq '--preview') { Show-RegionPreview $identifier }
            else { Set-RegionProfile $identifier }
        }
        '--restore-profile' { Restore-RegionProfile }
        '--hook' { Start-HookLoop }
        '--startup' {
            if ((Get-Mode) -eq 'euro') { Start-EzHook } else { Stop-EzHook }
        }
        { $_ -in @('1', 'euro', 'eur') } { Set-KeyboardMode 'euro' }
        { $_ -in @('2', 'dollar', 'usd') } { Set-KeyboardMode 'dollar' }
        '3' { Write-Banner; Show-Doctor }
        { $_ -in @('4', 'quit') } { }
        '' { Show-Menu }
    }
    exit 0
} catch { Write-Host ('eurozone failed: ' + $_.Exception.Message); exit 1 }
