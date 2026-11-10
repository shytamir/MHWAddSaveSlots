[CmdletBinding()]
param([string]$Version='0.3.0-dev.3',[string]$OutputDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($Version -notmatch '^[0-9A-Za-z.-]+$'){throw 'Invalid package version.'}
$repo=Split-Path $PSScriptRoot -Parent
if(!$OutputDirectory){$OutputDirectory=Join-Path $repo 'outputs'}
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
$stage=Join-Path $repo ('work\package-'+[guid]::NewGuid().ToString('N'))
$files=@(
 'README.md','LICENSE','docs\lua-backend-validation.md','docs\save-byte-investigation.md',
 'reframework\autorun\MHWAddSaveSlots.lua',
 'reframework\autorun\MHWAddSaveSlots\control.lua',
 'reframework\autorun\MHWAddSaveSlots\policy.lua',
 'reframework\autorun\MHWAddSaveSlots\records.lua',
 'reframework\autorun\MHWAddSaveSlots\poc.lua',
 'reframework\autorun\MHWAddSaveSlots\preservation.lua',
 'reframework\autorun\MHWAddSaveSlots\snapshot_codec.lua',
 'reframework\autorun\MHWAddSaveSlots\archive.lua'
)
New-Item -ItemType Directory -Path $stage,$OutputDirectory -Force | Out-Null
$manifest=@()
foreach($relative in $files){
 $source=Join-Path $repo $relative
 if(!(Test-Path -LiteralPath $source -PathType Leaf)){throw "Missing package input: $relative"}
 $destination=Join-Path $stage $relative
 New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
 Copy-Item -LiteralPath $source -Destination $destination
 $manifest+=[pscustomobject]@{path=$relative.Replace('\','/');sha256=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()}
}
@{version=$Version;channel='development candidate';live_restore_validation='focused and packaged copied-save recovery passed 2026-11-10';integrated_package_validation='dev.2 copied-save workflows passed with documented menu-array reset; dev.3 Lua unchanged';files=$manifest} |
 ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $stage 'package-manifest.json') -Encoding utf8
$zip=Join-Path $OutputDirectory "MHWAddSaveSlots-$Version.zip"
if(Test-Path -LiteralPath $zip){throw 'Refusing to overwrite an existing package. Use a new version or destination.'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($stage,$zip,[IO.Compression.CompressionLevel]::Optimal,$false)
$archive=[IO.Compression.ZipFile]::OpenRead($zip)
try {
 $expected=@($files | ForEach-Object {$_.Replace('\','/')})+@('package-manifest.json')
 $actual=@($archive.Entries | ForEach-Object {$_.FullName.Replace('\','/')})
 if(@(Compare-Object $expected $actual).Count){throw 'Archive contents differ from the allowlist.'}
 foreach($item in $manifest){
  $entry=$archive.Entries | Where-Object {$_.FullName.Replace('\','/') -ceq $item.path}
  $stream=$entry.Open()
  try { $hash=[Security.Cryptography.SHA256]::Create();try {$digest=[BitConverter]::ToString($hash.ComputeHash($stream)).Replace('-','').ToLowerInvariant()}finally{$hash.Dispose()} } finally {$stream.Dispose()}
  if($digest -cne $item.sha256){throw "Packaged bytes differ: $($item.path)"}
 }
} finally {$archive.Dispose()}
$digest=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
"$digest  $([IO.Path]::GetFileName($zip))" | Set-Content -LiteralPath ($zip+'.sha256') -Encoding ascii
Write-Output "Verified $($files.Count) packaged source/document files; no saves, settings, companion, or DLL: $zip"
