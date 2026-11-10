#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Initialize','Watch','Step','Status','Export')][string]$Action,
    [Parameter(Mandatory)][string]$SessionDirectory,
    [ValidateRange(3,16)][int]$Slots=3,
    [string]$Snapshot,
    [string]$Destination,
    [switch]$Fixture
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'BackupStore.psm1') -Force -DisableNameChecking
$SessionDirectory=[IO.Path]::GetFullPath($SessionDirectory).TrimEnd('\')
$state=Read-Json (Join-Path $SessionDirectory 'session.json')
if ([bool]$state.fixture -ne [bool]$Fixture) { throw 'Fixture flag mismatch.' }
$app=[IO.Path]::GetFullPath($state.active).TrimEnd('\')
if ($Fixture) {
    if ($app -notmatch '\\work\\sandbox-fixtures\\') { throw 'Fixture path must stay under work\sandbox-fixtures.' }
} elseif ($app -notmatch '\\Steam\\userdata\\[0-9]+\\2246340$') { throw 'Invalid Steam save path.' }
$store=Join-Path $SessionDirectory 'backups'
$data=Join-Path $state.game 'reframework\data'
if ($Action -eq 'Status') { Read-Json (Join-Path $store 'ledger.json') | ConvertTo-Json -Depth 8; return }
if ($Action -eq 'Export') {
    $record=Get-VerifiedSnapshot $store $Snapshot
    if (!$Destination) { throw 'Choose a new export directory.' }
    $destinationPath=[IO.Path]::GetFullPath($Destination).TrimEnd('\')
    foreach ($protected in @($app,$state.original,$store)) {
        $protected=[IO.Path]::GetFullPath($protected).TrimEnd('\')
        if ($destinationPath -eq $protected -or $destinationPath.StartsWith($protected+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Export must be outside active saves, originals, and the backup store.' }
    }
    if (Test-Path -LiteralPath $destinationPath) { throw 'Export destination already exists; nothing will be overwritten.' }
    New-Item -ItemType Directory -Path $destinationPath | Out-Null
    Copy-Item -LiteralPath (Join-Path $store "snapshots\$Snapshot\app") -Destination (Join-Path $destinationPath 'app') -Recurse
    Assert-Manifest (Join-Path $destinationPath 'app') $record.files
    Write-AtomicJson (Join-Path $destinationPath 'manifest.json') $record
    Write-Output "Verified export created. Capacity: $($record.slots). Original and active saves unchanged."
    return
}
if ($state.stage -ne 'isolated') { throw 'An isolated session is required.' }
Assert-Manifest $state.original (Read-Json (Join-Path $SessionDirectory 'original-sha256.json'))
if ($Action -eq 'Initialize') {
    if (!$PSBoundParameters.ContainsKey('Slots')) { throw 'Initialize requires an explicit known -Slots count; it is not inferred from file size.' }
    if (!$Fixture -and (Get-Process -Name MonsterHunterWilds -ErrorAction SilentlyContinue)) { throw 'Close Wilds before initializing backups.' }
}
# Exclusive lease prevents two companions from racing ledger updates.
New-Item -ItemType Directory -Path $store -Force | Out-Null
$lock=[IO.FileStream]::new((Join-Path $store 'companion.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try {
    if ($Action -eq 'Initialize') {
        $null=Initialize-Store $store $app $state.id $Slots
    } else {
        $ledger=Read-Json (Join-Path $store 'ledger.json')
        $null=Get-VerifiedSnapshot $store $ledger.snapshot
        if ($ledger.expanded_snapshot) { $null=Get-VerifiedSnapshot $store $ledger.expanded_snapshot }
    }
    do {
        $current=Read-Json (Join-Path $SessionDirectory 'session.json')
        if ($current.stage -ne 'isolated') { break }
        try {
            $status=Invoke-BackupStep $store $app $data $state.id
            if ($Action -ne 'Watch') { $status | ConvertTo-Json -Depth 5 }
        } catch {
            Write-AtomicJson (Join-Path $data 'MHWAddSaveSlots.companion.json') @{session_id=$state.id;heartbeat=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds();ready=$false;error=$_.Exception.Message}
            if ($Action -ne 'Watch') { throw }
            Write-Warning $_.Exception.Message
        }
        if ($Action -eq 'Watch') { Start-Sleep -Milliseconds 500 }
    } while ($Action -eq 'Watch')
} finally { $lock.Dispose() }
