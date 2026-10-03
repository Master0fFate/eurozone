# Native integration test. ONLY run in a disposable Windows account / CI runner.
$ErrorActionPreference = 'Stop'
if ($env:EUROZONE_ALLOW_OS_TESTS -ne '1') { throw 'Set EUROZONE_ALLOW_OS_TESTS=1 only in a disposable test account. This test changes user settings.' }
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$scriptPath = Join-Path $repoRoot 'eurozone.ps1'
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$regExe = Join-Path $env:SystemRoot 'System32\reg.exe'
$tempRoot = Join-Path $env:TEMP ('eurozone-native-test-' + [guid]::NewGuid().ToString('N'))
$configDir = Join-Path $tempRoot 'profile with spaces'
$installDir = Join-Path $tempRoot 'installed copy'
$backupFile = Join-Path $configDir 'profile.backup.reg'
$modeFile = Join-Path $configDir 'mode'
$pidFile = Join-Path $configDir 'hook.pid'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$international = 'HKCU:\Control Panel\International'
$nativeInternational = 'HKCU\Control Panel\International'
$hadRunEntry = $false
$originalRunEntry = $null
try {
    $originalRunEntry = Get-ItemPropertyValue -LiteralPath $runKey -Name eurozone -ErrorAction Stop
    $hadRunEntry = $true
} catch { }
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
$originalSnapshot = Join-Path $tempRoot 'original.reg'
& $regExe export $nativeInternational $originalSnapshot /y | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not protect test account regional settings' }
$profiles = Import-Csv -LiteralPath (Join-Path $repoRoot 'eurozone-profiles.tsv') -Delimiter '|'
foreach ($profile in $profiles) { [void][Globalization.CultureInfo]::GetCultureInfo($profile.culture) }

function Get-NativeRegionState {
    $command = '$i=Get-ItemProperty -LiteralPath "HKCU:\Control Panel\International"; [pscustomobject]@{Culture=(Get-Culture).Name; CurrencyCode=[int][char]$i.sCurrency; Measure=[string]$i.iMeasure; Paper=[string]$i.iPaperSize; Weekday=[string]$i.iFirstDayOfWeek; Week=[string]$i.iFirstWeekOfYear; Time=[string]$i.sTimeFormat; ShortTime=[string]$i.sShortTime; Calendar=[string]$i.iCalendarType; Digits=[string]$i.iCurrDigits} | ConvertTo-Json -Compress'
    $raw = & $windowsPowerShell -NoProfile -Command $command
    if ($LASTEXITCODE -ne 0) { throw 'Could not read Windows regional settings' }
    return ($raw | ConvertFrom-Json)
}
function Invoke-Eurozone([string[]]$Arguments, [switch]$Installed) {
    $path = if ($Installed) { Join-Path $installDir 'eurozone.ps1' } else { $scriptPath }
    & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $path @Arguments --config-dir $configDir --install-dir $installDir
    if ($LASTEXITCODE -ne 0) { throw "eurozone.ps1 failed with exit code $LASTEXITCODE" }
}
function Assert-European($State, [string]$Culture) {
    if ($State.Culture -ne $Culture) { throw "Expected $Culture; got $($State.Culture)" }
    if ($State.CurrencyCode -ne 8364 -or $State.Digits -ne '2') { throw 'Expected euro with two fractional digits' }
    if ($State.Measure -ne '0') { throw "Expected metric (0, not US=1); got $($State.Measure)" }
    if ($State.Paper -ne '9') { throw 'Expected A4 paper (9)' }
    if ($State.Weekday -ne '0' -or $State.Week -ne '2') { throw 'Expected Monday and ISO first-week rule' }
    if ($State.Time -cne 'HH:mm:ss' -or $State.ShortTime -cne 'HH:mm') { throw 'Expected 24-hour clock patterns' }
    if ($State.Calendar -ne '1') { throw 'Expected Gregorian calendar' }
}
try {
    # Deliberately non-European custom values; restore must preserve them all.
    $baselineValues = @{iMeasure='1'; iPaperSize='1'; iFirstDayOfWeek='6'; iFirstWeekOfYear='0'; sTimeFormat='h:mm:ss tt'; sShortTime='h:mm tt'; iCurrDigits='3'}
    foreach ($name in $baselineValues.Keys) { New-ItemProperty -LiteralPath $international -Name $name -Value $baselineValues[$name] -PropertyType String -Force | Out-Null }
    $before = Get-NativeRegionState | ConvertTo-Json -Compress
    $languageBefore = (Get-WinUserLanguageList | ConvertTo-Json -Depth 5 -Compress)
    $timezoneBefore = (Get-TimeZone).Id

    Invoke-Eurozone @('--preview', 'DE')
    if (Test-Path $configDir) { throw 'Preview created config directory' }
    Invoke-Eurozone @('--setup')
    Assert-European (Get-NativeRegionState) 'en-IE'
    if (-not (Test-Path $backupFile)) { throw 'No regional backup' }
    $backupHash = (Get-FileHash $backupFile).Hash
    if (Test-Path $installDir) { throw 'Regional setup installed keyboard startup' }

    Invoke-Eurozone @('--profile', 'FR')
    Assert-European (Get-NativeRegionState) 'fr-FR'
    if ((Get-FileHash $backupFile).Hash -ne $backupHash) { throw 'Switch overwrote original backup' }
    if ((Get-WinUserLanguageList | ConvertTo-Json -Depth 5 -Compress) -ne $languageBefore -or (Get-TimeZone).Id -ne $timezoneBefore) { throw 'Language/input/timezone changed' }

    Invoke-Eurozone @('--restore-profile')
    if ((Get-NativeRegionState | ConvertTo-Json -Compress) -ne $before) { throw 'Restore did not return all regional values to the baseline' }
    if (Test-Path $backupFile) { throw 'Successful restore kept consumed backup' }

    # Startup is now opt-in: an explicit keyboard action installs it, quit does not.
    Invoke-Eurozone @('4')
    if (Test-Path $installDir) { throw 'Quit installed startup' }
    Invoke-Eurozone @('dollar')
    $runEntry = Get-ItemPropertyValue -LiteralPath $runKey -Name eurozone
    if ($runEntry -notmatch '--startup' -or $runEntry -notmatch '--config-dir' -or $runEntry -notmatch '--install-dir') { throw 'Startup paths missing' }
    if (-not (Test-Path (Join-Path $installDir 'eurozone-profiles.tsv'))) { throw 'Installed catalog missing' }
    Invoke-Eurozone @('dollar') -Installed # No self-copy failure on refresh.

    Set-Content -LiteralPath $modeFile -Value 'euro' -Encoding ASCII
    Invoke-Eurozone @('--startup') -Installed
    Start-Sleep -Milliseconds 1000
    if (-not (Test-Path $pidFile)) { throw 'Startup hook did not write PID file' }
    $hookPid = [int](Get-Content -LiteralPath $pidFile -TotalCount 1)
    if (-not (Get-Process -Id $hookPid -ErrorAction SilentlyContinue)) { throw 'Hook process did not stay running' }
    Set-Content -LiteralPath $modeFile -Value 'dollar' -Encoding ASCII
    Invoke-Eurozone @('--startup') -Installed
    Start-Sleep -Milliseconds 500
    if (Get-Process -Id $hookPid -ErrorAction SilentlyContinue) { throw 'Dollar mode did not stop hook' }
    'Windows native European setup/switch/restore and startup PASS'
} finally {
    if (Test-Path $pidFile) {
        try { Stop-Process -Id ([int](Get-Content $pidFile -TotalCount 1)) -Force -ErrorAction SilentlyContinue } catch { }
    }
    if (Test-Path $originalSnapshot) {
        Remove-Item -LiteralPath $international -Recurse -Force
        & $regExe import $originalSnapshot | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Failed to recover test account! Keep $originalSnapshot" }
    }
    if ($hadRunEntry) { Set-ItemProperty -LiteralPath $runKey -Name eurozone -Value $originalRunEntry }
    else { Remove-ItemProperty -LiteralPath $runKey -Name eurozone -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
