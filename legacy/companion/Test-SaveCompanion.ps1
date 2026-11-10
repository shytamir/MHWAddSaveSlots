#requires -Version 7.0
param([string]$CopiedSaveDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'BackupStore.psm1') -Force -DisableNameChecking
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$root=Join-Path $repo ('work\sandbox-fixtures\backup-'+[guid]::NewGuid().ToString('N'))
$app=Join-Path $root '2246340'
$data=Join-Path $root 'data'
$store=Join-Path $root 'store'
New-Item -ItemType Directory -Path (Join-Path $app 'remote\win64_save'),$data -Force | Out-Null
$character=Join-Path $app 'remote\win64_save\data001Slot.bin'
[IO.File]::WriteAllBytes($character,[byte[]](1,2,3))
[IO.File]::WriteAllBytes((Join-Path $app 'remote\win64_save\data00-1.bin'),[byte[]](4,5))
$null=Initialize-Store $store $app 'fixture' 3
$status=Invoke-BackupStep $store $app $data 'fixture'
if (!$status.ready -or $status.slots -ne 3) { throw 'Baseline was not ready.' }
$runtime=@{session_id='fixture';runtime_id='run1';heartbeat=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds();busy=$false;fault=$null;trim=$null;
    event=@{id='1000-1';phase='writing';slots=5;purpose='save';trim_id=$null}}
function Complete-TestSave([byte[]]$Bytes) {
    $runtime.event.phase='writing'
    $receipt=@{version=3;session_id='fixture';runtime_id=$runtime.runtime_id;event=$runtime.event}
    Write-AtomicJson (Join-Path $data "MHWAddSaveSlots.save-start-$($runtime.event.id).json") $receipt
    Write-AtomicJson (Join-Path $data 'MHWAddSaveSlots.latest-save.json') $receipt
    [IO.File]::WriteAllBytes($character,$Bytes)
    $runtime.event.phase='completed'
    Write-AtomicJson (Join-Path $data "MHWAddSaveSlots.save-end-$($runtime.event.id).json") $receipt
    Write-AtomicJson (Join-Path $data 'MHWAddSaveSlots.latest-save.json') $receipt
    Write-AtomicJson (Join-Path $data 'MHWAddSaveSlots.runtime.json') $runtime
}
Complete-TestSave ([byte[]](10,11,12,13,14))
# Regression: process exits before its busy flag clears; a new process replaces
# runtime.json before the companion consumes the previous save completion.
Write-AtomicJson (Join-Path $data 'MHWAddSaveSlots.runtime.json') @{session_id='fixture';runtime_id='run2';heartbeat=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds();busy=$true;event=$null;fault=$null;trim=$null}
$status=Invoke-BackupStep $store $app $data 'fixture'
if (!$status.ready -or $status.slots -ne 5 -or $status.ack -ne '1000-1') { throw 'Completed expanded save was lost across restart.' }
$expanded=$status.snapshot
$record=Get-VerifiedSnapshot $store $expanded
$runtime.trim=@{id='trim-1';stage='awaiting-journal';source=$expanded;count=5}
Write-AtomicJson (Join-Path $data 'MHWAddSaveSlots.runtime.json') $runtime
$status=Invoke-BackupStep $store $app $data 'fixture'
if ($status.trim_ack -ne 'trim-1') { throw 'Trim intent was not durably acknowledged.' }
$intent=Read-Json (Join-Path $store 'transactions\trim-1.json')
if ($intent.source -ne $expanded -or $intent.stage -ne 'prepared') { throw 'Incorrect trim journal.' }
$runtime.trim.stage='saving'
$runtime.event=@{id='1000-2';phase='writing';slots=3;purpose='trim';trim_id='trim-1'}
Complete-TestSave ([byte[]](10,11,12))
$status=Invoke-BackupStep $store $app $data 'fixture'
if ($status.slots -ne 3 -or $status.expanded_snapshot -ne $expanded) { throw 'Trim overwrote the expanded recovery point.' }
$null=Get-VerifiedSnapshot $store $expanded
if ((Read-Json (Join-Path $store 'transactions\trim-1.json')).stage -ne 'complete') { throw 'Trim journal not completed.' }
$trimmed=$status.snapshot
$status=Invoke-BackupStep $store $app $data 'fixture'
if ($status.snapshot -ne $trimmed) { throw 'Completion was replayed.' }
# Mod-absent writes are archived as unclassified and block new mutations.
$runtime.heartbeat=0
Write-AtomicJson (Join-Path $data 'MHWAddSaveSlots.runtime.json') $runtime
[IO.File]::WriteAllBytes($character,[byte[]](20,21,22))
$status=Invoke-BackupStep $store $app $data 'fixture'
if ($status.ready -or $status.expanded_snapshot -ne $expanded -or $status.snapshot -ne $trimmed) { throw 'Untracked write replaced a trusted backup.' }
$null=Get-VerifiedSnapshot $store $expanded
$rejected=$false
try { Invoke-BackupStep $store $app $data 'wrong-session' | Out-Null } catch { $rejected=$true }
if (!$rejected) { throw 'Cross-session store access allowed.' }
# Corrupt snapshot cannot be exported or used to authorize a trim.
[IO.File]::WriteAllBytes((Join-Path $store "snapshots\$trimmed\app\remote\win64_save\data001Slot.bin"),[byte[]](99))
$rejected=$false
try { Get-VerifiedSnapshot $store $trimmed | Out-Null } catch { $rejected=$true }
if (!$rejected) { throw 'Corrupt snapshot passed verification.' }
if ($CopiedSaveDirectory) {
    # Real bytes are copied again into a fixture. No fabricated game completion
    # is attached to them; this checks only backup and exact byte preservation.
    $source=[IO.Path]::GetFullPath($CopiedSaveDirectory).TrimEnd('\')
    $before=@(Get-Manifest $source)
    $realCopy=Join-Path $root 'copied-save'
    Copy-Item -LiteralPath $source -Destination $realCopy -Recurse
    Assert-Manifest $realCopy $before
    $realStore=Join-Path $root 'copied-backups'
    $saved=New-Snapshot $realStore $realCopy 0 'real-copy-byte-check-only' @{}
    $null=Get-VerifiedSnapshot $realStore $saved.id
    Assert-Manifest $source $before
    Write-Output "PASS: all $($before.Count) copied-save files backed up and hash-verified; source unchanged."
}
Write-Output 'PASS: baseline, five-entry receipts, immediate exit/relaunch, journaled trim, immutable recovery point, replay, mod-absent change, wrong session, corruption.'
