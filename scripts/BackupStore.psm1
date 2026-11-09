Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Write-AtomicJson([string]$Path,$Value) {
    $temporary="$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value | ConvertTo-Json -Depth 16))
    $stream=[IO.FileStream]::new($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temporary,$Path,[NullString]::Value) }
    else { [IO.File]::Move($temporary,$Path) }
}
function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable }
function Get-Manifest([string]$Root) {
    @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force | Sort-Object FullName | ForEach-Object {
        if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse-point files are not supported.' }
        @{Path=$_.FullName.Substring($Root.Length+1); Bytes=$_.Length; SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
    })
}
function Assert-Manifest([string]$Root,$Expected) {
    $actual=@(Get-Manifest $Root)
    if ($actual.Count -ne @($Expected).Count) { throw "File count changed: $Root" }
    foreach ($item in $Expected) {
        $found=@($actual | Where-Object { $_.Path -ceq $item.Path })
        if ($found.Count -ne 1 -or $found[0].Bytes -ne $item.Bytes -or $found[0].SHA256 -ne $item.SHA256) { throw "Hash mismatch: $($item.Path)" }
    }
}
function Get-CharacterHash([string]$App) {
    $path=Join-Path $App 'remote\win64_save\data001Slot.bin'
    $stream=[IO.FileStream]::new($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try { (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash } finally { $stream.Dispose() }
}
function Assert-Capacity($Slots) {
    if ($Slots -isnot [int] -and $Slots -isnot [long]) { throw 'Capacity must be an integer.' }
    if ($Slots -lt 3 -or $Slots -gt 16) { throw 'Capacity must be between 3 and 16.' }
}
function New-Snapshot([string]$Store,[string]$App,[int]$Slots,[string]$Reason,$Evidence) {
    # Slots=0 denotes an unclassified file change, never a load/trim candidate.
    if ($Slots -ne 0) { Assert-Capacity $Slots }
    $id=[guid]::NewGuid().ToString('N')
    $directory=Join-Path $Store "snapshots\$id"
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $manifest=@(Get-Manifest $App)
    $copy=Join-Path $directory 'app'
    Copy-Item -LiteralPath $App -Destination $copy -Recurse
    Assert-Manifest $copy $manifest
    Assert-Manifest $App $manifest
    $record=@{version=2; id=$id; slots=$Slots; reason=$Reason; utc=[DateTime]::UtcNow.ToString('o');
        character_sha256=Get-CharacterHash $copy; files=$manifest; evidence=$Evidence}
    # This manifest is the commit marker; incomplete directories never qualify.
    Write-AtomicJson (Join-Path $directory 'manifest.json') $record
    return $record
}
function Get-VerifiedSnapshot([string]$Store,[string]$Id) {
    if ($Id -notmatch '^[a-f0-9]{32}$') { throw 'Invalid snapshot identifier.' }
    $directory=Join-Path $Store "snapshots\$Id"
    $record=Read-Json (Join-Path $directory 'manifest.json')
    if ($record.id -cne $Id) { throw 'Snapshot identifier mismatch.' }
    Assert-Manifest (Join-Path $directory 'app') $record.files
    if ((Get-CharacterHash (Join-Path $directory 'app')) -ne $record.character_sha256) { throw 'Snapshot character hash mismatch.' }
    return $record
}
function Initialize-Store([string]$Store,[string]$App,[string]$SessionId,[int]$Slots) {
    Assert-Capacity $Slots
    if (Test-Path -LiteralPath (Join-Path $Store 'ledger.json')) { throw 'Store already initialized; it cannot be overwritten.' }
    New-Item -ItemType Directory -Path (Join-Path $Store 'transactions') -Force | Out-Null
    $record=New-Snapshot $Store $App $Slots 'verified-session-baseline' @{}
    $ledger=@{version=2;session_id=$SessionId;snapshot=$record.id;slots=$Slots;character_sha256=$record.character_sha256;
        ack='';highest_slots=$Slots;expanded_snapshot=if ($Slots -gt 3) {$record.id} else {''};trim=$null;quarantine_sha=''}
    Write-AtomicJson (Join-Path $Store 'ledger.json') $ledger
    return $ledger
}
function Invoke-BackupStep([string]$Store,[string]$App,[string]$Data,[string]$SessionId) {
    $ledgerPath=Join-Path $Store 'ledger.json'
    $ledger=Read-Json $ledgerPath
    if ($ledger.session_id -cne $SessionId) { throw 'Backup store belongs to a different session.' }
    $now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $runtime=@{session_id='';heartbeat=0;busy=$false;event=$null;trim=$null;fault=$null;runtime_id=''}
    try { $read=Read-Json (Join-Path $Data 'MHWAddSaveSlots.runtime.json'); foreach ($key in $read.Keys) { $runtime[$key]=$read[$key] } } catch { }
    $live=$runtime.session_id -ceq $SessionId -and $runtime.heartbeat -is [long] -and $now -ge $runtime.heartbeat -and ($now-$runtime.heartbeat) -le 10
    # ConvertFrom-Json can represent small synthetic timestamps as Int32.
    if ($runtime.heartbeat -is [int]) { $live=$runtime.session_id -ceq $SessionId -and $now -ge $runtime.heartbeat -and ($now-$runtime.heartbeat) -le 10 }
    $event=@{phase='';id=''}
    $intent=if ($live -and $runtime.trim) { $runtime.trim } else { @{stage=''} }
    $eventRuntime=''
    $receiptEnd=$null
    $receiptStart=$null
    $latestPath=Join-Path $Data 'MHWAddSaveSlots.latest-save.json'
    if (Test-Path -LiteralPath $latestPath) {
        # A receipt is independent of the replaceable runtime heartbeat. Its
        # start/end file times bracket the native file write; later mod-absent
        # changes must not be attributed to an old successful completion.
        $latest=Read-Json $latestPath
        if ($latest.session_id -ceq $SessionId) {
            if ($latest.event.id -notmatch '^[0-9-]{1,100}$') { throw 'Invalid save receipt ID.' }
            $event=$latest.event; $eventRuntime=$latest.runtime_id
            $startPath=Join-Path $Data "MHWAddSaveSlots.save-start-$($event.id).json"
            $endPath=Join-Path $Data "MHWAddSaveSlots.save-end-$($event.id).json"
            if (Test-Path -LiteralPath $endPath) {
                $ended=Read-Json $endPath
                $started=Read-Json $startPath
                if ($ended.session_id -cne $SessionId -or $ended.runtime_id -cne $eventRuntime -or
                    $ended.event.id -cne $event.id -or $started.event.id -cne $event.id -or
                    $started.session_id -cne $SessionId -or $started.runtime_id -cne $eventRuntime -or $started.event.phase -ne 'writing' -or
                    $started.event.slots -ne $ended.event.slots) { throw 'Save receipt identity mismatch.' }
                $event=$ended.event
                $receiptEnd=Get-Item -LiteralPath $endPath
                $receiptStart=Get-Item -LiteralPath $startPath
            }
        }
    }
    $writing=$event.phase -eq 'writing'
    $hash=if ($writing) { $ledger.character_sha256 } else { Get-CharacterHash $App }
    $errorMessage=$null
    if ($writing -and (!$live -or $runtime.runtime_id -cne $eventRuntime)) { $errorMessage='An interrupted save has no completion receipt. Inspect retained backups before continuing.' }
    if ($event.phase -eq 'completed' -and $event.id -cne $ledger.ack) {
        Assert-Capacity $event.slots
        $modified=(Get-Item -LiteralPath (Join-Path $App 'remote\win64_save\data001Slot.bin')).LastWriteTimeUtc
        if (!$receiptEnd -or !$receiptStart -or ($hash -ne $ledger.character_sha256 -and
            ($modified -lt $receiptStart.LastWriteTimeUtc -or $modified -gt $receiptEnd.LastWriteTimeUtc))) {
            throw 'Character file write is outside the completed request interval. Refusing to classify it.'
        }
        if ($event.slots -ne $ledger.slots -and $hash -eq $ledger.character_sha256) { throw 'Capacity changed without a new character file.' }
        if ($event.slots -lt $ledger.slots) {
            if ($event.slots -ne 3 -or $event.purpose -ne 'trim' -or !$ledger.trim -or
                $ledger.trim.id -cne $event.trim_id -or $ledger.trim.runtime_id -cne $eventRuntime -or
                $ledger.trim.source -cne $ledger.snapshot -or $ledger.trim.stage -ne 'prepared') { throw 'Unapproved capacity reduction.' }
            $null=Get-VerifiedSnapshot $Store $ledger.trim.source
        }
        $record=New-Snapshot $Store $App $event.slots $event.purpose @{runtime_id=$eventRuntime;event=$event}
        $again=Read-Json $latestPath
        if ($again.runtime_id -cne $eventRuntime -or $again.event.id -cne $event.id) { throw 'Save activity changed while backing up; retry.' }
        $ledger.snapshot=$record.id; $ledger.slots=$event.slots; $ledger.character_sha256=$record.character_sha256; $ledger.ack=$event.id
        $ledger.quarantine_sha=''
        if ($event.slots -gt 3) { $ledger.expanded_snapshot=$record.id; $ledger.highest_slots=[Math]::Max($ledger.highest_slots,$event.slots) }
        if ($event.purpose -eq 'trim') {
            $ledger.trim.stage='complete'; $ledger.trim.result=$record.id
            Write-AtomicJson (Join-Path $Store "transactions\$($ledger.trim.id).json") $ledger.trim
        }
        Write-AtomicJson $ledgerPath $ledger
        $hash=$record.character_sha256
    }
    if ($live -and !$runtime.busy -and $intent.stage -eq 'awaiting-journal') {
        if ($intent.id -notmatch '^[a-zA-Z0-9-]{1,100}$' -or $intent.source -cne $ledger.snapshot -or
            $intent.count -ne $ledger.slots -or $ledger.slots -le 3 -or $event.id -cne $ledger.ack -or $event.phase -ne 'completed') { throw 'Trim intent does not match the latest expanded backup.' }
        if (!$ledger.trim -or $ledger.trim.id -cne $intent.id) {
            $null=Get-VerifiedSnapshot $Store $intent.source
            $ledger.trim=@{id=$intent.id;runtime_id=$runtime.runtime_id;source=$intent.source;slots=$intent.count;stage='prepared';result=''}
            Write-AtomicJson (Join-Path $Store "transactions\$($intent.id).json") $ledger.trim
            Write-AtomicJson $ledgerPath $ledger
        }
    }
    if ($hash -ne $ledger.character_sha256 -and !$writing) {
        # Re-read the start journal after hashing: execution can begin between
        # the first journal read and the file read. Do not quarantine that race.
        if (Test-Path -LiteralPath $latestPath) {
            $again=Read-Json $latestPath
            if ($again.session_id -ceq $SessionId -and $again.event.id -cne $event.id) { return Invoke-BackupStep $Store $App $Data $SessionId }
        }
        $errorMessage='Save changed without a verified completion. Expanded backups are retained; inspect before continuing.'
        if ($ledger.quarantine_sha -ne $hash) {
            $null=New-Snapshot $Store $App 0 'unclassified-change' @{}
            $ledger.quarantine_sha=$hash; Write-AtomicJson $ledgerPath $ledger
        }
    }
    if ($live -and $runtime.fault) { $errorMessage=[string]$runtime.fault }
    $status=@{version=2;session_id=$SessionId;heartbeat=$now;ready=(!$errorMessage);error=$errorMessage;
        snapshot=$ledger.snapshot;slots=$ledger.slots;ack=$ledger.ack;character_sha256=$ledger.character_sha256;
        expanded_snapshot=$ledger.expanded_snapshot;trim_ack=if ($ledger.trim) {$ledger.trim.id} else {''}}
    Write-AtomicJson (Join-Path $Data 'MHWAddSaveSlots.companion.json') $status
    return $status
}
Export-ModuleMember -Function Write-AtomicJson,Read-Json,Get-Manifest,Assert-Manifest,Get-CharacterHash,Assert-Capacity,New-Snapshot,Get-VerifiedSnapshot,Initialize-Store,Invoke-BackupStep
