param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDir,

    [int]$WatchSeconds = 900,
    [int]$WatchIntervalSeconds = 2
)

$ErrorActionPreference = "Stop"

$pathsOverride = Join-Path $PSScriptRoot "hon_paths_override.ps1"
if (Test-Path $pathsOverride) {
    . $pathsOverride
}

$defaultDocsRoot = Join-Path $env:USERPROFILE "Documents\Juvio\Heroes of Newerth"
$defaultLocalRoot = Join-Path $env:USERPROFILE "AppData\Local\Juvio\heroes of newerth"
$docsRoot = if ($HoNDocsRoot) { $HoNDocsRoot } else { $defaultDocsRoot }
$localRoot = if ($HoNLocalRoot) { $HoNLocalRoot } else { $defaultLocalRoot }

$trackedBases = @(
    "entities",
    "interface",
    "client_messages",
    "game_messages",
    "bot_messages"
)

$targets = @(
    (Join-Path $docsRoot "stringtables"),
    (Join-Path $docsRoot "game\stringtables"),
    (Join-Path $localRoot "stringtables"),
    (Join-Path $localRoot "game\stringtables")
)

$startupCfg = Join-Path $docsRoot "startup.cfg"
$fileCacheDir = Join-Path $docsRoot "filecache"
$webCacheDir = Join-Path $docsRoot "webcache"

function Assert-Path($path, $label) {
    if (-not (Test-Path $path)) {
        throw "$label not found: $path"
    }
}

function Get-SourceMap($dirPath) {
    $map = @{}
    foreach ($base in $trackedBases) {
        $candidate = Join-Path $dirPath ($base + "_en.str")
        if (-not (Test-Path $candidate)) {
            throw "Missing source file: $candidate"
        }
        $map[$base] = $candidate
    }
    return $map
}

function Copy-SourceSetToTarget($targetDir, $sourceMap) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

    foreach ($base in $trackedBases) {
        $src = $sourceMap[$base]
        foreach ($name in @(
            ($base + ".str"),
            ($base + "_en.str"),
            ($base + "_ru.str"),
            ($base + "_th.str")
        )) {
            $dst = Join-Path $targetDir $name
            Copy-Item -Path $src -Destination $dst -Force
            Write-Host ("Copied: {0}" -f $dst)
        }
    }
}

function Ensure-SourceSetInTarget($targetDir, $sourceMap) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

    foreach ($base in $trackedBases) {
        $src = $sourceMap[$base]
        $srcLength = (Get-Item $src).Length
        foreach ($name in @(
            ($base + ".str"),
            ($base + "_en.str"),
            ($base + "_ru.str"),
            ($base + "_th.str")
        )) {
            $dst = Join-Path $targetDir $name
            $needCopy = $true
            if (Test-Path $dst) {
                $dstLength = (Get-Item $dst).Length
                if ($dstLength -eq $srcLength) {
                    $needCopy = $false
                }
            }

            if ($needCopy) {
                Copy-Item -Path $src -Destination $dst -Force
                Write-Host ("Re-copied: {0}" -f $dst)
            }
        }
    }
}

function Force-EnglishLocale {
    if (-not (Test-Path $startupCfg)) {
        Write-Host "startup.cfg not found, skipping locale normalization."
        return
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $text = [System.IO.File]::ReadAllText($startupCfg)
    $updated = $text
    $updated = [Regex]::Replace($updated, 'SetSave "host_locale" "[^"]*"', 'SetSave "host_locale" "en"')
    $updated = [Regex]::Replace($updated, 'SetSave "host_backuplocale" "[^"]*"', 'SetSave "host_backuplocale" "en"')
    $updated = [Regex]::Replace($updated, 'SetSave "language" "[^"]*"', 'SetSave "language" "en"')

    if ($updated -ne $text) {
        [System.IO.File]::WriteAllText($startupCfg, $updated, $utf8NoBom)
        Write-Host "startup.cfg locale normalized to en."
    } else {
        Write-Host "startup.cfg locale already set."
    }
}

function Clear-CacheIfExists($dirPath, $label) {
    if (-not (Test-Path $dirPath)) {
        return
    }

    Get-ChildItem -Path $dirPath -Force | Remove-Item -Recurse -Force
    Write-Host ("Cleared {0}: {1}" -f $label, $dirPath)
}

$sourceDirResolved = (Resolve-Path $SourceDir).Path
Assert-Path $sourceDirResolved "Source directory"

$sourceMap = Get-SourceMap -dirPath $sourceDirResolved

Write-Host ("Deploying full HoN stringtables from: {0}" -f $sourceDirResolved)
foreach ($target in $targets) {
    Write-Host ("Target: {0}" -f $target)
    Copy-SourceSetToTarget -targetDir $target -sourceMap $sourceMap
}

Force-EnglishLocale
Clear-CacheIfExists -dirPath $fileCacheDir -label "filecache"
Clear-CacheIfExists -dirPath $webCacheDir -label "webcache"

Write-Host ("Watching targets for {0} seconds. Keep this window open while Juvio updates..." -f $WatchSeconds)
$watchUntil = (Get-Date).AddSeconds($WatchSeconds)
while ((Get-Date) -lt $watchUntil) {
    foreach ($target in $targets) {
        Ensure-SourceSetInTarget -targetDir $target -sourceMap $sourceMap
    }
    Start-Sleep -Seconds $WatchIntervalSeconds
}

Write-Host ""
Write-Host "Done. Full stringtables watch window finished."
