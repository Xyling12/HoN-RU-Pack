param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDir,

    [int]$WatchSeconds = 900,
    [int]$WatchIntervalSeconds = 2
)

$ErrorActionPreference = "Stop"

# --- Path resolution: override > auto-detect > defaults ---

$pathsOverride = Join-Path $PSScriptRoot "hon_paths_override.ps1"
if (Test-Path $pathsOverride) {
    . $pathsOverride
}

function Find-HoNDocsRoot {
    # Look for the folder that contains startup.cfg
    $searchRoots = @(
        (Join-Path $env:USERPROFILE "Documents\Juvio\Heroes of Newerth"),
        (Join-Path $env:USERPROFILE "Documents\Heroes of Newerth"),
        (Join-Path $env:USERPROFILE "AppData\Local\Juvio\Heroes of Newerth")
    )
    foreach ($candidate in $searchRoots) {
        if (Test-Path (Join-Path $candidate "startup.cfg")) { return $candidate }
    }
    # Deep search under common parents
    $deepRoots = @(
        (Join-Path $env:USERPROFILE "Documents"),
        (Join-Path $env:USERPROFILE "AppData\Local")
    )
    foreach ($root in $deepRoots) {
        if (-not (Test-Path $root)) { continue }
        $hit = Get-ChildItem -Path $root -Recurse -Filter "startup.cfg" -ErrorAction SilentlyContinue |
               Where-Object { $_.DirectoryName -match "(?i)heroes.of.newerth" } |
               Select-Object -First 1
        if ($hit) { return $hit.DirectoryName }
    }
    return $null
}

function Find-HoNLocalRoot {
    # Look for the folder that contains resources0.jz
    $searchRoots = @(
        (Join-Path $env:USERPROFILE "AppData\Local\Juvio\heroes of newerth"),
        "C:\Games\Juvio\heroes of newerth",
        "D:\Games\Juvio\heroes of newerth",
        "C:\Program Files\Juvio\heroes of newerth",
        "C:\Program Files (x86)\Juvio\heroes of newerth",
        "D:\Juvio\heroes of newerth",
        "C:\Juvio\heroes of newerth"
    )
    foreach ($candidate in $searchRoots) {
        if (Test-Path (Join-Path $candidate "resources0.jz")) { return $candidate }
    }
    # Scan all drive roots for Juvio
    Get-PSDrive -PSProvider FileSystem | ForEach-Object {
        $tryPath = Join-Path $_.Root "Juvio\heroes of newerth"
        if (Test-Path (Join-Path $tryPath "resources0.jz")) { return $tryPath }
        $tryPath2 = Join-Path $_.Root "Games\Juvio\heroes of newerth"
        if (Test-Path (Join-Path $tryPath2 "resources0.jz")) { return $tryPath2 }
    }
    return $null
}

$defaultDocsRoot = Join-Path $env:USERPROFILE "Documents\Juvio\Heroes of Newerth"
$defaultLocalRoot = Join-Path $env:USERPROFILE "AppData\Local\Juvio\heroes of newerth"

if ($HoNDocsRoot) {
    $docsRoot = $HoNDocsRoot
} else {
    $autoDocsRoot = Find-HoNDocsRoot
    if ($autoDocsRoot) {
        $docsRoot = $autoDocsRoot
        Write-Host "Auto-detected DocsRoot: $docsRoot"
    } else {
        $docsRoot = $defaultDocsRoot
    }
}

if ($HoNLocalRoot) {
    $localRoot = $HoNLocalRoot
} else {
    $autoLocalRoot = Find-HoNLocalRoot
    if ($autoLocalRoot) {
        $localRoot = $autoLocalRoot
        Write-Host "Auto-detected LocalRoot: $localRoot"
    } else {
        $localRoot = $defaultLocalRoot
    }
}

Write-Host "DocsRoot:  $docsRoot"
Write-Host "LocalRoot: $localRoot"

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
