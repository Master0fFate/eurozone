$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$scriptPath = Join-Path $repoRoot 'eurozone.ps1'
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$tempRoot = Join-Path $env:TEMP ('eurozone-profile-test-' + [guid]::NewGuid().ToString('N'))
$configDir = Join-Path $tempRoot 'profile with spaces'
$installDir = Join-Path $tempRoot 'installed copy'
$backupFile = Join-Path $configDir 'profile.backup.reg'
$modeFile = Join-Path $configDir 'mode'
$pidFile = Join-Path $configDir 'hook.pid'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$hadRunEntry = $false
$originalRunEntry = $null
try {
    $originalRunEntry = Get-ItemPropertyValue -LiteralPath $runKey -Name eurozone -ErrorAction Stop
    $hadRunEntry = $true
} catch { }
New-Item -ItemType Directory -Path $configDir -Force | Out-Null
$profiles = Import-Csv -LiteralPath (Join-Path $repoRoot 'eurozone-profiles.tsv') -Delimiter '|'
foreach ($profile in $profiles) { [void][Globalization.CultureInfo]::GetCultureInfo($profile.culture) }

function Get-NativeRegionState {
    $command = '$i=Get-ItemProperty -LiteralPath "HKCU:\Control Panel\International"; [pscustomobject]@{Culture=(Get-Culture).Name; CurrencyCode=[int][char]$i.sCurrency; Measure=[string]$i.iMeasure} | ConvertTo-Json -Compress'
    $raw = & $windowsPowerShell -NoProfile -Command $command
    if ($LASTEXITCODE -ne 0) { throw 'Could not read Windows regional settings' }
    return ($raw | ConvertFrom-Json)
}

function Invoke-Eurozone([string[]]$Arguments) {
    & $windowsPowerShell -NoProfile -File $scriptPath @Arguments
    if ($LASTEXITCODE -ne 0) { throw "eurozone.ps1 failed with exit code $LASTEXITCODE" }
}

function Invoke-InstalledEurozone([string[]]$Arguments) {
    $installedScript = Join-Path $installDir 'eurozone.ps1'
    & $windowsPowerShell -NoProfile -File $installedScript @Arguments
    if ($LASTEXITCODE -ne 0) { throw "installed eurozone.ps1 failed with exit code $LASTEXITCODE" }
}

$before = Get-NativeRegionState
$profileBaseline = $null
try {
    # Use a non-metric starting value so this test proves that the profile
    # changes it, then verifies that restore returns it to this baseline.
    New-ItemProperty -LiteralPath 'HKCU:\Control Panel\International' -Name iMeasure -Value '0' -PropertyType String -Force | Out-Null
    $profileBaseline = Get-NativeRegionState
    Invoke-Eurozone @('--profile', 'IE-EN', '--config-dir', $configDir, '--install-dir', $installDir)
    $applied = Get-NativeRegionState
    if ($applied.Culture -ne 'en-IE') { throw "Expected en-IE culture; got $($applied.Culture)" }
    if ($applied.CurrencyCode -ne 8364) { throw "Expected euro currency symbol code point; got $($applied.CurrencyCode)" }
    if ($applied.Measure -ne '1') { throw "Expected metric measurement; got $($applied.Measure)" }
    if (-not (Test-Path $backupFile)) { throw 'The previous regional settings were not backed up' }

    Invoke-Eurozone @('--profile', 'FR', '--config-dir', $configDir, '--install-dir', $installDir)
    $switched = Get-NativeRegionState
    if ($switched.Culture -ne 'fr-FR' -or $switched.CurrencyCode -ne 8364 -or $switched.Measure -ne '1') {
        throw 'Switching profiles did not apply the second regional culture'
    }

    Invoke-Eurozone @('--restore-profile', '--config-dir', $configDir, '--install-dir', $installDir)
    $restored = Get-NativeRegionState
    if ($restored.Culture -ne $profileBaseline.Culture -or $restored.CurrencyCode -ne $profileBaseline.CurrencyCode -or $restored.Measure -ne $profileBaseline.Measure) {
        throw 'Restore did not return the Windows regional settings to their pre-profile values'
    }

    # Exercise startup installation, including the profile catalog and pinned paths.
    Invoke-Eurozone @('4', '--config-dir', $configDir, '--install-dir', $installDir)
    $runEntry = Get-ItemPropertyValue -LiteralPath $runKey -Name eurozone -ErrorAction Stop
    if ($runEntry -notmatch '--startup' -or $runEntry -notmatch '--config-dir' -or $runEntry -notmatch '--install-dir') {
        throw 'The Windows Run entry is missing its startup or pinned user paths'
    }
    if (-not (Test-Path (Join-Path $installDir 'eurozone-profiles.tsv'))) { throw 'The installed profile catalog is missing' }

    # Exercise the persistent user-level Shift+4 hook without elevating.
    Set-Content -LiteralPath $modeFile -Value 'euro' -Encoding ASCII
    Invoke-InstalledEurozone @('--startup', '--config-dir', $configDir, '--install-dir', $installDir)
    if (-not (Test-Path $pidFile)) { throw 'The Windows startup hook did not write its PID file' }
    $hookPid = [int](Get-Content -LiteralPath $pidFile -TotalCount 1)
    if (-not (Get-Process -Id $hookPid -ErrorAction SilentlyContinue)) { throw 'The Windows startup hook process did not stay running' }
    Set-Content -LiteralPath $modeFile -Value 'dollar' -Encoding ASCII
    Invoke-InstalledEurozone @('--startup', '--config-dir', $configDir, '--install-dir', $installDir)
    Start-Sleep -Milliseconds 500
    if (Get-Process -Id $hookPid -ErrorAction SilentlyContinue) { throw 'The Windows dollar mode did not stop the euro hook' }
    'Windows user-region apply/restore and user-level hook PASS'
} finally {
    if (Test-Path $pidFile) {
        try { Stop-Process -Id ([int](Get-Content $pidFile -TotalCount 1)) -Force -ErrorAction SilentlyContinue } catch { }
    }
    if (Test-Path $backupFile) {
        try { Invoke-Eurozone @('--restore-profile', '--config-dir', $configDir, '--install-dir', $installDir) } catch { }
    }
    try {
        Set-Culture -CultureInfo $before.Culture
        New-ItemProperty -LiteralPath 'HKCU:\Control Panel\International' -Name sCurrency -Value ([string][char]$before.CurrencyCode) -PropertyType String -Force | Out-Null
        New-ItemProperty -LiteralPath 'HKCU:\Control Panel\International' -Name iMeasure -Value $before.Measure -PropertyType String -Force | Out-Null
    } catch { }
    if ($hadRunEntry) {
        Set-ItemProperty -LiteralPath $runKey -Name eurozone -Value $originalRunEntry -ErrorAction SilentlyContinue
    } else {
        Remove-ItemProperty -LiteralPath $runKey -Name eurozone -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
