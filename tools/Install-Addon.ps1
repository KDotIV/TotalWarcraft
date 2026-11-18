param(
    [string]$AddonDirectory = 'E:\World of Warcraft\_forever_\Interface\AddOns\CallToArms'
)
$ErrorActionPreference = 'Stop'
$repoDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sourceDirectory = Join-Path $repoDirectory 'CallToArms'
$destination = [IO.Path]::GetFullPath($AddonDirectory)
if ((Split-Path $destination -Leaf) -ne 'CallToArms' -or
    (Split-Path (Split-Path $destination -Parent) -Leaf) -ne 'AddOns') {
    throw 'Destination must be the CallToArms folder directly under AddOns.'
}
if (-not (Test-Path -LiteralPath (Join-Path $sourceDirectory 'CallToArms.toc'))) { throw 'Source TOC missing.' }
$versionLine = Select-String -LiteralPath (Join-Path $sourceDirectory 'CallToArms.toc') -Pattern '^## Version: ([\w.-]+)$'
if (-not $versionLine) { throw 'Source version missing.' }
$releaseVersion = $versionLine.Matches[0].Groups[1].Value
# Never follow junctions/symlinks while backing up or installing an addon.
$ancestor = $destination
while ($ancestor) {
    if (Test-Path -LiteralPath $ancestor) {
        $item = Get-Item -LiteralPath $ancestor -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse path rejected: $ancestor" }
    }
    $ancestor = Split-Path $ancestor -Parent
}
$sourceFiles = @(Get-ChildItem -LiteralPath $sourceDirectory -Recurse -File)
foreach ($root in @($sourceDirectory, $destination)) {
    if (Test-Path -LiteralPath $root) {
        if (Get-ChildItem -LiteralPath $root -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) {
            throw "Reparse entry rejected under $root"
        }
    }
}
if (Test-Path -LiteralPath $destination) {
    $backupDirectory = Join-Path $repoDirectory 'releases\installed-backups'
    New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
    $backup = Join-Path $backupDirectory ('CallToArms-before-' + $releaseVersion + '-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '.zip')
    Compress-Archive -LiteralPath $destination -DestinationPath $backup -CompressionLevel Optimal
    Write-Output "Backup: $backup"
}
New-Item -ItemType Directory -Path $destination -Force | Out-Null
foreach ($file in $sourceFiles) {
    $relative = $file.FullName.Substring($sourceDirectory.Length).TrimStart('\','/')
    $target = [IO.Path]::GetFullPath((Join-Path $destination $relative))
    if (-not $target.StartsWith($destination + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Target escaped addon directory.' }
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    if ((Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath $target).Hash) {
        throw "Hash mismatch: $relative"
    }
}
Write-Output "Installed and hash-verified $($sourceFiles.Count) files at $destination"
Write-Output 'Existing settings and other addons were not modified. Start/restart WoW to load the testing build.'
