$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Join-Path (Split-Path $PSScriptRoot -Parent) ('work\sandbox-fixtures\check-'+[guid]::NewGuid().ToString('N'))
$active=Join-Path $root 'userdata\2246340'
$game=Join-Path $root 'game'
$session=Join-Path $root 'session'
$script=Join-Path $PSScriptRoot 'SaveSandbox.ps1'
New-Item -ItemType Directory -Path (Join-Path $active 'remote\win64_save'),(Join-Path $game 'reframework\data') -Force | Out-Null
$save=Join-Path $active 'remote\win64_save\data001Slot.bin'
[IO.File]::WriteAllBytes($save,[byte[]](0,1,2,255))
$hash=(Get-FileHash -LiteralPath $save).Hash
& $script -Action Prepare -SessionDirectory $session -AppDirectory $active -GameDirectory $game -CloudDisabled -SteamOffline -Fixture
$marker=Join-Path $game 'reframework\data\MHWAddSaveSlots.session.json'
if ((Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json).mutation_enabled) { throw 'Prepare must default to read-only.' }
& $script -Action Arm -SessionDirectory $session -Fixture
if (!(Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json).mutation_enabled) { throw 'Arm failed.' }
[IO.File]::WriteAllBytes($save,[byte[]](10,20,30))
& $script -Action Restore -SessionDirectory $session -Fixture
if ((Get-FileHash -LiteralPath $save).Hash -ne $hash) { throw 'Original was not restored.' }
$state=Get-Content -LiteralPath (Join-Path $session 'session.json') -Raw | ConvertFrom-Json
if ([IO.File]::ReadAllBytes((Join-Path $state.result 'remote\win64_save\data001Slot.bin'))[0] -ne 10) { throw 'Test result was not retained.' }
if ((Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json).mutation_enabled) { throw 'Restore left mutations enabled.' }
$rejected=$false
try { & $script -Action Arm -SessionDirectory $session -Fixture } catch { $rejected=$true }
if (!$rejected) { throw 'Restored session must not re-arm.' }
& $script -Action Restore -SessionDirectory $session -Fixture
Write-Output 'PASS: verified isolation, explicit arming, test retention, hash restoration, re-arm refusal, idempotent restore.'
