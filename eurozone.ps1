# eurozone — Shift+4  $ / €
# Windows PowerShell 5.1 + 7. Menu stays open. Regional profiles are per-user.
# Built-in RegisterHotKey hook. AutoHotkey optional.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Version = "2.0.0"

# Startup may pass the user's paths explicitly so the installed copy uses the
# same per-user profile and region settings as the menu.
$script:UserArgs = New-Object 'System.Collections.Generic.List[string]'
$script:ConfigDirOverride = $null
$script:InstallDirOverride = $null
for ($i = 0; $i -lt $args.Count; $i++) {
    switch ([string]$args[$i]) {
        "--config-dir" {
            if ($i + 1 -lt $args.Count) { $script:ConfigDirOverride = [string]$args[++$i] }
        }
        "--install-dir" {
            if ($i + 1 -lt $args.Count) { $script:InstallDirOverride = [string]$args[++$i] }
        }
        default { [void]$script:UserArgs.Add([string]$args[$i]) }
    }
}

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

if (-not (Test-Path $ConfDir)) {
    New-Item -ItemType Directory -Path $ConfDir | Out-Null
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
    $temporary = $ProfileActiveFile + ".tmp"
    $backup = $temporary + ".bak"
    [IO.File]::WriteAllText($temporary, ("{0}|{1}`r`n" -f $ProfileId, $Culture), [Text.Encoding]::ASCII)
    try {
        if ([IO.File]::Exists($ProfileActiveFile)) {
            [IO.File]::Replace($temporary, $ProfileActiveFile, $backup)
        } else {
            [IO.File]::Move($temporary, $ProfileActiveFile)
        }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
        if ([IO.File]::Exists($backup)) { [IO.File]::Delete($backup) }
    }
}

function Set-RegionProfile([string]$Identifier) {
    $profile = Get-RegionProfile $Identifier
    if (-not [IO.File]::Exists($ProfileBackupFile)) {
        $regExe = Join-Path $env:SystemRoot "System32\reg.exe"
        & $regExe export $InternationalRegistryKey $ProfileBackupFile /y | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "could not back up the current Windows regional settings" }
    }
    $culture = [Globalization.CultureInfo]::GetCultureInfo($profile.culture)
    Set-Culture -CultureInfo $culture
    New-ItemProperty -LiteralPath $InternationalKey -Name sCurrency -Value ([string][char]0x20AC) -PropertyType String -Force | Out-Null
    New-ItemProperty -LiteralPath $InternationalKey -Name iMeasure -Value "1" -PropertyType String -Force | Out-Null
    Save-ProfileActive $profile.id $profile.culture
    $region = [Globalization.RegionInfo]::new($culture.Name)
    Write-Ok ("regional profile applied: {0} ({1})" -f $profile.name, $culture.Name)
    if ($region.ISOCurrencySymbol -ne "EUR") {
        Write-Host ("  WARNING  Windows locale data reports {0}; update Windows for current ISO currency data." -f $region.ISOCurrencySymbol)
    }
    Write-Ok "currency symbol set to euro; metric measurement enabled"
    Write-Ok "interface language, keyboard layout and time zone were not changed"
    Write-Ok "restart apps or sign out and back in if formats do not update"
}

function Restore-RegionProfile {
    if (-not [IO.File]::Exists($ProfileBackupFile)) {
        throw "no saved Windows regional settings to restore"
    }
    $currentSnapshot = Join-Path $ConfDir ".profile-current.reg"
    $regExe = Join-Path $env:SystemRoot "System32\reg.exe"
    & $regExe export $InternationalRegistryKey $currentSnapshot /y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "could not protect the current regional settings before restore" }
    Remove-Item -LiteralPath $InternationalKey -Recurse -Force
    & $regExe import $ProfileBackupFile | Out-Null
    if ($LASTEXITCODE -ne 0) {
        & $regExe import $currentSnapshot | Out-Null
        throw "could not restore the saved regional settings; current settings were recovered"
    }
    Remove-Item -LiteralPath $currentSnapshot -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $ProfileBackupFile -Force
    Remove-Item -LiteralPath $ProfileActiveFile -Force -ErrorAction SilentlyContinue
    Write-Ok "previous Windows regional settings restored"
    Write-Ok "restart apps or sign out and back in if formats do not update"
}

function Select-RegionProfile {
    try {
        Show-RegionProfiles
        $choice = Read-Host "  enter a profile ID or locale code"
        $profile = Get-RegionProfile $choice
        Write-Host ("  Preview: set regional formats to {0} ({1}). Keep display language, keyboard and time zone." -f $profile.name, $profile.culture)
        $confirm = Read-Host "  apply these settings? [y/N]"
        if ($confirm -notmatch '^(y|yes)$') {
            Write-Ok "no regional settings changed"
            return $false
        }
        Set-RegionProfile $profile.id
        return $true
    } catch {
        Write-Ez ("profile failed: " + $_.Exception.Message) Red
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
        Copy-Item -LiteralPath $ProfileCatalog -Destination (Join-Path $InstallDir "eurozone-profiles.tsv") -Force
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
    Stop-EzHook
    $self = $PSCommandPath
    $arg = ('-NoProfile -STA -ExecutionPolicy Bypass -File "{0}" --hook --config-dir "{1}" --install-dir "{2}"' -f `
        $self, $ConfDir, $InstallDir)
    $p = Start-Process -FilePath "powershell.exe" -PassThru -WindowStyle Hidden -ArgumentList $arg
    Set-Content -Path $PidFile -Value ([string]$p.Id) -Encoding ASCII
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
        Write-Host ("  1  euro     Shift+4 becomes " + [char]0x20AC + $a1)
        Write-Host ("  2  dollar   Shift+4 becomes `$ " + $a2)
        Write-Host "  3  doctor"
        Write-Host "  4  quit"
        Write-Host "  5  country / regional format profile"
        Write-Host "  6  restore previous regional settings"
        Write-Host ""
        $choice = Read-Host "  "
        switch -Regex ($choice.Trim()) {
            "^(1|e|euro)$" {
                Set-Mode "euro"
                Invoke-Apply
                $last = "applied euro"
            }
            "^(2|d|dollar)$" {
                Set-Mode "dollar"
                Invoke-Apply
                $last = "applied dollar"
            }
            "^3$" {
                Clear-Host
                Write-Banner
                Show-Doctor
            }
            "^(4|q|quit|x|exit)$" {
                return
            }
            "^5$" {
                if (Select-RegionProfile) { $last = "regional profile applied" } else { $last = "profile was not applied" }
            }
            "^6$" {
                try { Restore-RegionProfile; $last = "previous regional settings restored" }
                catch { $last = "restore failed: " + $_.Exception.Message }
            }
            default { $last = "type 1, 2, 3, 4, 5 or 6" }
        }
    }
}

function Start-HookLoop {
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

$allArgs = @($script:UserArgs.ToArray())
if ($allArgs -contains "--list-profiles") {
    Show-RegionProfiles
    exit 0
}
if ($allArgs.Count -gt 0 -and $allArgs[0] -eq "--profile") {
    if ($allArgs.Count -lt 2) { Write-Host "usage: eurozone.ps1 --profile PROFILE_ID"; exit 2 }
    try { Set-RegionProfile $allArgs[1]; exit 0 }
    catch { Write-Host ("profile failed: " + $_.Exception.Message); exit 1 }
}
if ($allArgs -contains "--restore-profile") {
    try { Restore-RegionProfile; exit 0 }
    catch { Write-Host ("restore failed: " + $_.Exception.Message); exit 1 }
}
if ($allArgs -contains "--hook") {
    Start-HookLoop
    exit 0
}

if ($allArgs -contains "--startup") {
    if ((Get-Mode) -eq "euro") { Start-EzHook }
    else { Stop-EzHook }
    exit 0
}

[void](Install-EzStartup)

if ($allArgs.Count -eq 0) {
    Show-Menu
    exit 0
}

$cmd = $allArgs[0].ToLowerInvariant()
switch ($cmd) {
    { $_ -in @("1", "euro", "eur") } { Set-Mode "euro"; Invoke-Apply }
    { $_ -in @("2", "dollar", "usd") } { Set-Mode "dollar"; Invoke-Apply }
    "3" { Write-Banner; Show-Doctor }
    { $_ -in @("4", "quit") } { exit 0 }
    default { Show-Menu }
}
