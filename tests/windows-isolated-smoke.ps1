# Safe tests: AST-load functions, then replace every regional OS boundary.
# No Set-Culture, registry, startup, or keyboard calls reach Windows.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$scriptPath = Join-Path $repoRoot 'eurozone.ps1'
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
$functions = $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)
foreach ($function in $functions) { . ([scriptblock]::Create($function.Extent.Text)) }

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('eurozone-isolated-' + [guid]::NewGuid().ToString('N'))
$ConfDir = Join-Path $tempRoot 'config with spaces'
$ProfileActiveFile = Join-Path $ConfDir 'profile.active'
$ProfileBackupFile = Join-Path $ConfDir 'profile.backup.reg'
$ProfileCatalog = Join-Path $repoRoot 'eurozone-profiles.tsv'
$InternationalKey = 'MockRegistry:\International'
$InternationalRegistryKey = 'MOCK\International'
$script:FakeRegistry = @{ 'MockRegistry:\International|LocaleName' = 'en-US'; 'MockRegistry:\International|iMeasure' = '1'; 'MockRegistry:\International|custom-value' = 42 }
$script:FailName = ''
$script:FailImport = $false

function Set-Culture($CultureInfo) { $script:FakeRegistry["$InternationalKey|LocaleName"] = $CultureInfo.Name }
function Set-WinHomeLocation($GeoId) { $script:FakeRegistry["$InternationalKey/Geo|Nation"] = [string]$GeoId }
function Join-Path {
    param([string]$Path, [string]$ChildPath)
    if ($Path -eq $InternationalKey) { return "$Path/$ChildPath" }
    Microsoft.PowerShell.Management\Join-Path -Path $Path -ChildPath $ChildPath
}
function New-ItemProperty {
    [CmdletBinding()] param($LiteralPath, $Name, $Value, $PropertyType, [switch]$Force)
    if ($script:FailName -eq $Name) { $script:FailName = ''; throw 'injected settings write failure' }
    if ($PropertyType -ne 'String') { throw 'Regional Windows values must be strings' }
    $script:FakeRegistry["$LiteralPath|$Name"] = $Value
}
function Get-ItemPropertyValue {
    [CmdletBinding()] param($LiteralPath, $Name)
    return $script:FakeRegistry["$LiteralPath|$Name"]
}
function Export-RegionSnapshot([string]$Path) {
    if (Test-Path -LiteralPath $Path) { throw 'Snapshot would overwrite baseline' }
    $script:FakeRegistry | Export-Clixml -LiteralPath $Path
}
function Import-RegionSnapshot([string]$Path) {
    if ($script:FailImport -and $Path -eq $ProfileBackupFile) {
        $script:FailImport = $false
        $script:FakeRegistry.Clear() # Simulate partial OS restore before failure.
        throw 'injected restore failure'
    }
    $script:FakeRegistry = Import-Clixml -LiteralPath $Path
}
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function State {
    return (($script:FakeRegistry.GetEnumerator() | Sort-Object Key | ForEach-Object { '{0}={1}:{2}' -f $_.Key, $_.Value.GetType().Name, $_.Value }) -join "`n")
}
function Expect-Failure([scriptblock]$Action, [string]$Message) {
    $failed = $false
    try { & $Action } catch { $failed = $true }
    Assert $failed $Message
}
try {
    $baseline = State
    $profiles = @(Get-RegionProfiles)
    Assert ($profiles.Count -eq 31) 'Unexpected profile catalog size'
    foreach ($profile in $profiles) {
        $plan = Get-RegionPlan $profile.id
        Assert ($plan.Values.iMeasure -eq '0') 'Metric regression: Windows 1 is US, not metric'
        Assert ($plan.Values.iPaperSize -eq '9') 'A4 missing'
        Assert ($plan.Values.iFirstDayOfWeek -eq '0' -and $plan.Values.iFirstWeekOfYear -eq '2') 'Monday/ISO week missing'
        Assert ($plan.Values.sShortTime -ceq 'HH:mm' -and $plan.Values.sTimeFormat -ceq 'HH:mm:ss') '24-hour clock missing'
        Assert ($plan.Values.iCurrDigits -eq '2' -and [int][char]$plan.Values.sCurrency -eq 8364) 'Euro formatting missing'
        Assert ($plan.Values.iCalendarType -eq '1') 'Gregorian calendar missing'
        Assert ($plan.Region.GeoId -gt 0) 'Home country missing'
    }
    Show-RegionPreview 'DE'
    Assert (-not (Test-Path $ConfDir)) 'Read-only plan/preview created config'
    Expect-Failure { Get-RegionPlan 'unknown-country' } 'Invalid profile accepted'
    Assert ((State) -ceq $baseline) 'Preview changed fake OS state'

    Set-RegionProfile 'IE-EN'
    Assert (Test-Path $ProfileBackupFile) 'Baseline not saved'
    $backupHash = (Get-FileHash $ProfileBackupFile).Hash
    $first = State
    $firstActive = [IO.File]::ReadAllText($ProfileActiveFile)
    $script:FailName = 'sTimeFormat'
    Expect-Failure { Set-RegionProfile 'FR' } 'Injected apply failure was swallowed'
    Assert ((State) -ceq $first) 'Failed switch did not roll back all settings'
    Assert ([IO.File]::ReadAllText($ProfileActiveFile) -ceq $firstActive) 'Failed switch changed active metadata'
    Assert ((Get-FileHash $ProfileBackupFile).Hash -eq $backupHash) 'Switch replaced original backup'

    Set-RegionProfile 'FR'
    Assert ($script:FakeRegistry["$InternationalKey|LocaleName"] -eq 'fr-FR') 'Profile switch did not apply culture'
    Assert ((Get-FileHash $ProfileBackupFile).Hash -eq $backupHash) 'Successful switch replaced original backup'
    $second = State
    $script:FailImport = $true
    Expect-Failure { Restore-RegionProfile } 'Injected restore failure was swallowed'
    Assert ((State) -ceq $second) 'Failed restore did not recover current settings'
    Assert (Test-Path $ProfileBackupFile) 'Failed restore consumed backup'
    Assert (Test-Path $ProfileActiveFile) 'Failed restore lost active metadata'

    Restore-RegionProfile
    Assert ((State) -ceq $baseline) 'Restore lost original types/values or kept added values'
    Assert (-not (Test-Path $ProfileBackupFile)) 'Successful restore did not consume backup'
    Assert (-not (Test-Path $ProfileActiveFile)) 'Successful restore left active metadata'
    Expect-Failure { Restore-RegionProfile } 'Restore accepted missing backup'
    'Isolated Windows plans, preview, apply/switch/restore and rollback PASS'
} finally {
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
