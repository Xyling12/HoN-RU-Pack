param(
    [switch]$CaptureBaseline,
    [string]$BaselinePath = ""
)

$ErrorActionPreference = "Stop"

$pathsOverride = Join-Path $PSScriptRoot "hon_paths_override.ps1"
if (Test-Path $pathsOverride) {
    . $pathsOverride
}

$sevenZip = "C:\Program Files\7-Zip\7z.exe"
if (-not (Test-Path $sevenZip)) {
    $sevenZipCmd = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($null -ne $sevenZipCmd) {
        $sevenZip = $sevenZipCmd.Source
    }
}

$defaultArchive = Join-Path $env:USERPROFILE "AppData\Local\Juvio\heroes of newerth\resources0.jz"
$archive = if ($HoNArchivePath) { $HoNArchivePath } else { $defaultArchive }
$trackedEntries = @(
    "stringtables\entities_en.str",
    "stringtables\interface_en.str",
    "stringtables\client_messages_en.str",
    "stringtables\game_messages_en.str",
    "stringtables\bot_messages_en.str"
)

function Assert-Path($path, $label) {
    if (-not (Test-Path $path)) {
        throw "$label not found: $path"
    }
}

function Get-ArchiveSnapshot {
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("hon_update_check_" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        $archiveItem = Get-Item $archive
        $archiveHash = (Get-FileHash $archive -Algorithm SHA256).Hash
        $files = New-Object System.Collections.Generic.List[object]

        foreach ($entry in $trackedEntries) {
            & $sevenZip e -y "-o$tempDir" $archive $entry | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "7z extract failed for $entry with code $LASTEXITCODE"
            }

            $name = Split-Path $entry -Leaf
            $extractedPath = Join-Path $tempDir $name
            if (-not (Test-Path $extractedPath)) {
                throw "Extracted file not found: $extractedPath"
            }

            $item = Get-Item $extractedPath
            $hash = (Get-FileHash $extractedPath -Algorithm SHA256).Hash

            $files.Add([PSCustomObject]@{
                archive_entry = $entry
                name = $name
                size = $item.Length
                sha256 = $hash
            }) | Out-Null
        }

        return [PSCustomObject]@{
            captured_at = (Get-Date).ToString("s")
            archive_path = $archive
            archive_size = $archiveItem.Length
            archive_last_write_utc = $archiveItem.LastWriteTimeUtc.ToString("s")
            archive_sha256 = $archiveHash
            tracked_files = $files
        }
    }
    finally {
        if (Test-Path $tempDir) {
            Remove-Item $tempDir -Recurse -Force
        }
    }
}

Assert-Path $sevenZip "7-Zip"
Assert-Path $archive "Archive"

if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
    $BaselinePath = Join-Path $PSScriptRoot "hon_translation_update_baseline.json"
}

$baselinePathResolved = [System.IO.Path]::GetFullPath($BaselinePath)
$snapshot = Get-ArchiveSnapshot

if ($CaptureBaseline) {
    $snapshot | ConvertTo-Json -Depth 6 | Set-Content -Path $baselinePathResolved -Encoding UTF8
    Write-Host ("Baseline saved: {0}" -f $baselinePathResolved)
    exit 0
}

if (-not (Test-Path $baselinePathResolved)) {
    throw "Baseline not found. Run with -CaptureBaseline first: $baselinePathResolved"
}

$baseline = Get-Content $baselinePathResolved -Raw | ConvertFrom-Json
$baselineMap = @{}
foreach ($file in $baseline.tracked_files) {
    $baselineMap[$file.archive_entry] = $file
}

$changed = New-Object System.Collections.Generic.List[object]
foreach ($file in $snapshot.tracked_files) {
    if (-not $baselineMap.ContainsKey($file.archive_entry)) {
        $changed.Add([PSCustomObject]@{
            archive_entry = $file.archive_entry
            status = "new_in_snapshot"
            baseline_sha256 = ""
            current_sha256 = $file.sha256
        }) | Out-Null
        continue
    }

    $old = $baselineMap[$file.archive_entry]
    if ($old.sha256 -ne $file.sha256) {
        $changed.Add([PSCustomObject]@{
            archive_entry = $file.archive_entry
            status = "changed"
            baseline_sha256 = $old.sha256
            current_sha256 = $file.sha256
        }) | Out-Null
    }
}

$archiveChanged = $baseline.archive_sha256 -ne $snapshot.archive_sha256

Write-Host ("Baseline: {0}" -f $baselinePathResolved)
Write-Host ("Archive changed: {0}" -f $archiveChanged)
Write-Host ("Tracked stringtable changes: {0}" -f $changed.Count)

if ($changed.Count -gt 0) {
    Write-Host ""
    Write-Host "Translation update is needed."
    foreach ($item in $changed) {
        Write-Host ("Changed: {0}" -f $item.archive_entry)
    }
    exit 10
}

Write-Host ""
Write-Host "Tracked stringtables did not change. Translation update is not required yet."
exit 0
