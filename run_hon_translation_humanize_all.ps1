param(
    [string]$InputDir = "D:\HoN_RU_Pack\bundle",
    [string]$OutputDir = "",
    [ValidateSet("auto", "gemini", "openai")]
    [string]$Provider = "gemini",
    [string]$Model = "gemini-2.0-flash",
    [int]$ChunkSize = 90,
    [double]$RequestDelay = 4.2,
    [int]$Timeout = 120,
    [int]$MaxLines = 0,
    [switch]$DryRun,
    [string]$PythonExe = "python"
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolPath = Join-Path $scriptRoot "tools\hon_translation_humanize.py"

if (-not (Test-Path $toolPath)) {
    throw "Tool not found: $toolPath"
}

if (-not (Test-Path $InputDir)) {
    throw "InputDir not found: $InputDir"
}

$mode = if ($DryRun) { "dryrun" } else { "apply" }
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $InputDir ("humanize_{0}_{1}" -f $mode, (Get-Date -Format "yyyyMMdd_HHmmss"))
}
$outputPath = [System.IO.Path]::GetFullPath($OutputDir)
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null

$files = @(
    "entities_en.str",
    "interface_en.str",
    "client_messages_en.str",
    "game_messages_en.str",
    "bot_messages_en.str"
)

$results = New-Object System.Collections.Generic.List[object]

foreach ($name in $files) {
    $inFile = Join-Path $InputDir $name
    if (-not (Test-Path $inFile)) {
        Write-Host ("Skip missing file: {0}" -f $inFile)
        continue
    }

    $outFile = Join-Path $outputPath $name
    $report = Join-Path $outputPath ("{0}.humanize.report.json" -f [System.IO.Path]::GetFileNameWithoutExtension($name))

    Write-Host ""
    Write-Host ("=== Humanize: {0} ===" -f $name)

    $args = @(
        $toolPath,
        "--input", $inFile,
        "--output", $outFile,
        "--report", $report,
        "--provider", $Provider,
        "--model", $Model,
        "--chunk-size", "$ChunkSize",
        "--request-delay", "$RequestDelay",
        "--timeout", "$Timeout"
    )

    if ($MaxLines -gt 0) {
        $args += @("--max-lines", "$MaxLines")
    }
    if ($DryRun) {
        $args += "--dry-run"
    }

    & $PythonExe @args
    if ($LASTEXITCODE -ne 0) {
        throw "Humanize failed for $name with exit code $LASTEXITCODE"
    }

    $statChanged = 0
    $statErrors = 0
    if (Test-Path $report) {
        $obj = Get-Content $report -Raw | ConvertFrom-Json
        $statChanged = [int]$obj.stats.changed
        $statErrors = [int]$obj.stats.errors
    }

    $results.Add([PSCustomObject]@{
        file = $name
        input = $inFile
        output = $outFile
        report = $report
        changed = $statChanged
        errors = $statErrors
    }) | Out-Null
}

$summaryPath = Join-Path $outputPath "summary.json"
$summary = [PSCustomObject]@{
    mode = $mode
    provider = $Provider
    model = $Model
    input_dir = $InputDir
    output_dir = $outputPath
    files = $results
}
$summary | ConvertTo-Json -Depth 6 | Set-Content -Path $summaryPath -Encoding UTF8

Write-Host ""
Write-Host ("Humanize summary: {0}" -f $summaryPath)
