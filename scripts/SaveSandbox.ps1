[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Prepare','Arm','Disarm','Restore','Status')][string]$Action,
    [Parameter(Mandatory)][string]$SessionDirectory,
    [string]$AppDirectory,
    [string]$GameDirectory,
    [switch]$CloudDisabled,
    [switch]$SteamOffline,
    [switch]$Fixture
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function FullPath([string]$Path) { [IO.Path]::GetFullPath($Path).TrimEnd('\') }
function AssertClosed {
    if ($Fixture) { return } # AssertPaths confines synthetic fixtures to work\sandbox-fixtures.
    $running = @(Get-Process -Name steam,steamwebhelper,MonsterHunterWilds -ErrorAction SilentlyContinue)
    if ($running.Count) { throw 'Close Wilds and exit Steam completely before changing save directories.' }
}
function Manifest([string]$Root) {
    @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
        [pscustomobject]@{ Path=$_.FullName.Substring($Root.Length+1); Bytes=$_.Length; SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    })
}
function Verify([string]$Root, $Expected) {
    $actual = @(Manifest $Root)
    if ($actual.Count -ne @($Expected).Count) { throw "File count mismatch at $Root" }
    foreach ($file in $Expected) {
        $match = @($actual | Where-Object Path -CEQ $file.Path)
        if ($match.Count -ne 1 -or $match[0].Bytes -ne $file.Bytes -or $match[0].SHA256 -ne $file.SHA256) {
            throw "Hash mismatch: $($file.Path)"
        }
    }
}
function WriteJson([string]$Path, $Value) {
    $temporary="$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporary -Encoding utf8
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temporary,$Path,[NullString]::Value) }
    else { [IO.File]::Move($temporary,$Path) }
}
function AssertPaths($State) {
    $active = FullPath $State.active
    $parent = Split-Path -Parent $active
    if ((Split-Path -Leaf $active) -ne '2246340') { throw 'Expected the Wilds app directory named 2246340.' }
    if (-not $Fixture -and $active -notmatch '\\Steam\\userdata\\[0-9]+\\2246340$') { throw 'Expected a Steam userdata app directory.' }
    if ($Fixture -and $active -notmatch '\\work\\sandbox-fixtures\\') { throw 'Fixtures must be under work\sandbox-fixtures.' }
    foreach ($path in @($State.original, $State.staged, $State.result)) {
        $resolved = FullPath $path
        if ((Split-Path -Parent $resolved) -ne $parent -or (Split-Path -Leaf $resolved) -notlike '2246340.mhw4-*') {
            throw "Unsafe rename destination: $resolved"
        }
    }
}

$SessionDirectory = FullPath $SessionDirectory
$journal = Join-Path $SessionDirectory 'session.json'
if ($Action -eq 'Prepare') {
    AssertClosed
    if (-not $CloudDisabled -or -not $SteamOffline) { throw 'Confirm Cloud is disabled for Wilds and Steam is offline.' }
    if (Test-Path -LiteralPath $journal) { throw 'This session already has a journal. Inspect or restore it first.' }
    if (-not $AppDirectory -or -not $GameDirectory) { throw 'AppDirectory and GameDirectory are required.' }
    $active = FullPath $AppDirectory
    $game = FullPath $GameDirectory
    if (-not (Test-Path -LiteralPath (Join-Path $active 'remote\win64_save\data001Slot.bin'))) { throw 'Wilds save file was not found.' }
    if (-not (Test-Path -LiteralPath (Join-Path $game 'reframework\data'))) { throw 'REFramework data directory was not found.' }
    $id = [guid]::NewGuid().ToString('N')
    $state = [pscustomobject]@{
        version=1; id=$id; stage='preparing'; active=$active;
        original="$active.mhw4-original-$id"; staged="$active.mhw4-staged-$id";
        result="$active.mhw4-result-$id"; game=$game;
        createdUtc=[DateTime]::UtcNow.ToString('o'); fixture=[bool]$Fixture
    }
    AssertPaths $state
    foreach ($path in @($state.original,$state.staged,$state.result)) {
        if (Test-Path -LiteralPath $path) { throw "Destination already exists: $path" }
    }
    New-Item -ItemType Directory -Path $SessionDirectory -Force | Out-Null
    $manifest = @(Manifest $active)
    WriteJson (Join-Path $SessionDirectory 'original-sha256.json') $manifest
    WriteJson $journal $state
    Copy-Item -LiteralPath $active -Destination $state.staged -Recurse
    Verify $state.staged $manifest
    Verify $active $manifest
    AssertClosed
    # All rename destinations were resolved and checked above. No files are deleted.
    $state.stage='renaming-original'; WriteJson $journal $state
    Move-Item -LiteralPath $active -Destination $state.original
    try {
        Move-Item -LiteralPath $state.staged -Destination $active
    } catch {
        Move-Item -LiteralPath $state.original -Destination $active
        $state.stage='rolled-back'; WriteJson $journal $state
        throw
    }
    $state.stage='isolated'; WriteJson $journal $state
    WriteJson (Join-Path $game 'reframework\data\MHWAddSaveSlots.session.json') @{
        isolated=$true; session_id=$id; mutation_enabled=$false;
        expires_utc=[DateTime]::UtcNow.AddHours(12).ToString('o')
    }
    Write-Output "Isolated $($manifest.Count) verified files. Journal: $journal"
} else {
    $state = Get-Content -LiteralPath $journal -Raw | ConvertFrom-Json
    if ([bool]$state.fixture -ne [bool]$Fixture) { throw 'Fixture flag does not match session.' }
    AssertPaths $state
    if ($Action -eq 'Status') {
        $state | Format-List
        Write-Output "Original retained: $(Test-Path -LiteralPath $state.original)"
        Write-Output "Active present: $(Test-Path -LiteralPath $state.active)"
        return
    }
    if ($Action -eq 'Arm' -or $Action -eq 'Disarm') {
        if ($state.stage -ne 'isolated') { throw 'Only an isolated session can be armed or disarmed.' }
        if (!(Test-Path -LiteralPath $state.original) -or !(Test-Path -LiteralPath $state.active)) { throw 'Isolation directories are missing.' }
        $manifest = @(Get-Content -LiteralPath (Join-Path $SessionDirectory 'original-sha256.json') -Raw | ConvertFrom-Json)
        Verify $state.original $manifest
        WriteJson (Join-Path $state.game 'reframework\data\MHWAddSaveSlots.session.json') @{
            isolated=$true; session_id=$state.id; mutation_enabled=($Action -eq 'Arm');
            expires_utc=[DateTime]::UtcNow.AddHours(12).ToString('o')
        }
        Write-Output "$Action completed for verified isolated session."
        return
    }
    AssertClosed
    $manifest = @(Get-Content -LiteralPath (Join-Path $SessionDirectory 'original-sha256.json') -Raw | ConvertFrom-Json)
    WriteJson (Join-Path $state.game 'reframework\data\MHWAddSaveSlots.session.json') @{
        isolated=$false; session_id=$state.id; mutation_enabled=$false
    }
    if (Test-Path -LiteralPath $state.original) {
        Verify $state.original $manifest
        if (Test-Path -LiteralPath $state.active) {
            if (Test-Path -LiteralPath $state.result) { throw 'Both active and result exist. Inspect the journal before continuing.' }
            $state.stage='preserving-test'; WriteJson $journal $state
            Move-Item -LiteralPath $state.active -Destination $state.result
        }
        $state.stage='restoring-original'; WriteJson $journal $state
        Move-Item -LiteralPath $state.original -Destination $state.active
    }
    Verify $state.active $manifest
    $state.stage='restored'; WriteJson $journal $state
    Write-Output "Restored and verified $($manifest.Count) original files. Test results retained: $($state.result)"
}
