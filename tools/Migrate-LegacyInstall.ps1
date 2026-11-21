param(
    [Parameter(Mandatory=$true)][string]$SavedVariablesDirectory,
    [string]$AddOnsDirectory = 'E:\World of Warcraft\_forever_\Interface\AddOns'
)
$ErrorActionPreference = 'Stop'
if (Get-Process -Name Wow,WowClassic,WowForever -ErrorAction SilentlyContinue) {
    throw 'Close WoW before migrating SavedVariables.'
}
$repoDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$addons = [IO.Path]::GetFullPath($AddOnsDirectory)
$settings = [IO.Path]::GetFullPath($SavedVariablesDirectory)
if ((Split-Path $addons -Leaf) -ne 'AddOns' -or (Split-Path $settings -Leaf) -ne 'SavedVariables') { throw 'Unexpected migration roots.' }
$legacy = [IO.Path]::GetFullPath((Join-Path $addons 'CallToArms'))
$current = [IO.Path]::GetFullPath((Join-Path $addons 'WarbandPvP'))
foreach ($directory in @($legacy,$current,$settings)) {
    $ancestor=$directory
    while ($ancestor) {
        if (Test-Path -LiteralPath $ancestor) {
            if ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse path rejected: $ancestor" }
        }
        $ancestor=Split-Path $ancestor -Parent
    }
}
$legacyToc=Join-Path $legacy 'CallToArms.toc'
$disabledToc=Join-Path $legacy 'CallToArms.toc.disabled'
if (-not (Test-Path -LiteralPath (Join-Path $current 'WarbandPvP.toc'))) { throw 'Install and verify WarbandPvP first.' }
if (-not (Test-Path -LiteralPath $legacyToc)) { throw 'No enabled legacy addon to migrate.' }
if (Test-Path -LiteralPath $disabledToc) { throw 'A previous disabled TOC exists; inspect it before migration.' }
if (Get-ChildItem -LiteralPath $legacy -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) { throw 'Legacy reparse entry rejected.' }
$version=(Select-String -LiteralPath $legacyToc -Pattern '^## Version: ([\w.-]+)$').Matches.Groups[1].Value
if (-not $version) { throw 'Legacy version missing.' }
$archive=Join-Path $repoDirectory ('releases\CallToArms-'+$version+'.zip')
if (-not (Test-Path -LiteralPath $archive)) { throw 'The matching legacy archive is required to verify ownership.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::OpenRead($archive)
$sha=[Security.Cryptography.SHA256]::Create()
try {
    $count=0
    foreach ($entry in $zip.Entries) {
        if ($entry.FullName.EndsWith('/')) { continue }
        if (-not $entry.FullName.StartsWith('CallToArms/')) { throw 'Unexpected archive root.' }
        $relative=$entry.FullName.Substring('CallToArms/'.Length)
        $path=[IO.Path]::GetFullPath((Join-Path $legacy $relative))
        if (-not $path.StartsWith($legacy+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Archive path escaped legacy addon.' }
        $stream=$entry.Open()
        try { $expected=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','') } finally { $stream.Dispose() }
        if (-not (Test-Path -LiteralPath $path) -or (Get-FileHash -LiteralPath $path).Hash -ne $expected) { throw "Legacy addon modified: $relative" }
        $count++
    }
    if (@(Get-ChildItem -LiteralPath $legacy -Recurse -File -Force).Count -ne $count) { throw 'Unknown files in legacy addon.' }
} finally { $sha.Dispose(); $zip.Dispose() }
$oldSettings=Join-Path $settings 'CallToArms.lua'
$newSettings=Join-Path $settings 'WarbandPvP.lua'
if (Test-Path -LiteralPath $newSettings) { throw 'WarbandPvP settings already exist; automatic overwrite refused.' }
if (Test-Path -LiteralPath $oldSettings) {
    if ((Get-Item -LiteralPath $oldSettings).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Settings symlink rejected.' }
    $text=[IO.File]::ReadAllText($oldSettings)
    if (-not [regex]::IsMatch($text,'(?m)^CallToArmsDB\s*=')) { throw 'Unexpected settings declarations.' }
    $converted=[regex]::Replace($text,'(?m)^CallToArmsDB(?=\s*=)','WarbandPvPDB')
    $converted=[regex]::Replace($converted,'(?m)^CallToArmsDiagnosticsDB(?=\s*=)','WarbandPvPDiagnosticsDB')
}
$stamp=[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
$backup=Join-Path $repoDirectory ('releases\installed-backups\name-migration-'+$stamp)
New-Item -ItemType Directory -Path $backup | Out-Null
Compress-Archive -LiteralPath $legacy -DestinationPath (Join-Path $backup 'CallToArms.zip')
if (Test-Path -LiteralPath $oldSettings) {
    Copy-Item -LiteralPath $oldSettings -Destination (Join-Path $backup 'CallToArms.lua')
    [IO.File]::WriteAllText($newSettings,$converted,[Text.UTF8Encoding]::new($false))
    if ([IO.File]::ReadAllText($newSettings) -cne $converted) { throw 'Settings verification failed.' }
}
# Disable only the verified old manifest. All old code and settings remain in place.
if (-not ([IO.Path]::GetFullPath($disabledToc)).StartsWith($legacy+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Disable target escaped legacy addon.' }
Move-Item -LiteralPath $legacyToc -Destination $disabledToc
Write-Output "Legacy files verified: $count. Old TOC disabled; all legacy data retained."
Write-Output "Backup: $backup"
Write-Output ('Settings migrated: '+(Test-Path -LiteralPath $newSettings))
