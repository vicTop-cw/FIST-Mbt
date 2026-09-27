#!/usr/bin/env pwsh
param(
    [string]$Version = "0.2.6",
    [string]$TargetDir = "$PSScriptRoot\..\..\_release",
    [switch]$SkipNative,
    [switch]$SkipJs
)
$REPO_ROOT = (Resolve-Path "$PSScriptRoot\..\..").Path
$ErrorActionPreference = "Stop"
Write-Host "=== FIST-Mbt Blackbox Build v$Version ===" -ForegroundColor Cyan
Write-Host "Repo root: $REPO_ROOT"

if (Test-Path $TargetDir) { Remove-Item -Recurse -Force $TargetDir }
New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
if (-not $SkipJs)    { New-Item -ItemType Directory -Path "$TargetDir\js"    -Force | Out-Null }
if (-not $SkipNative) { New-Item -ItemType Directory -Path "$TargetDir\native" -Force | Out-Null }

if (-not $SkipJs) {
    Write-Host "[JS] moon build --target js ..." -ForegroundColor Yellow
    moon build --target js 2>&1 | Select-Object -Last 5
    if ($LASTEXITCODE -ne 0) { Write-Host "[JS] build failed" -ForegroundColor Red; exit 1 }
    $jsMain = Resolve-Path "$REPO_ROOT\_build\js\debug\build\cmd\main\main.js" -ErrorAction SilentlyContinue
    if (-not $jsMain) { Write-Host "[JS] main.js not found" -ForegroundColor Red; exit 1 }
    Write-Host "[JS] patching ESM createRequire ..." -ForegroundColor Yellow
    python "$PSScriptRoot\patch_esm_main.py" $jsMain
    Copy-Item $jsMain "$TargetDir\js\fist-mbt.js" -Force
    $size = (Get-Item "$TargetDir\js\fist-mbt.js").Length
    Write-Host "[JS] OK: $TargetDir\js\fist-mbt.js ($([math]::Round($size/1KB, 1)) KB)" -ForegroundColor Green
}

if (-not $SkipNative) {
    Write-Host "[Native] moon build --target native ..." -ForegroundColor Yellow
    $nativeEnv = Resolve-Path "$REPO_ROOT\scripts\native-env.ps1" -ErrorAction SilentlyContinue
    if ($nativeEnv) { try { . $nativeEnv 2>$null } catch { Write-Host "[Native] native-env skipped" -ForegroundColor DarkGray } }
    moon build --target native 2>&1 | Select-Object -Last 5
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[Native] build failed (MSVC + sqlite3.lib needed), skipping" -ForegroundColor Yellow
    } else {
        $nativeMain = Resolve-Path "$REPO_ROOT\_build\native\debug\build\cmd\main\main.exe" -ErrorAction SilentlyContinue
        if ($nativeMain) {
            Copy-Item $nativeMain "$TargetDir\native\fist-mbt.exe" -Force
            Write-Host "[Native] OK: $TargetDir\native\fist-mbt.exe" -ForegroundColor Green
        }
    }
}

Write-Host "=== Packaging ===" -ForegroundColor Cyan
if (-not $SkipJs -and (Test-Path "$TargetDir\js\fist-mbt.js")) {
    $zip = "$TargetDir\fist-mbt-js-v$Version.zip"
    Compress-Archive -Path "$TargetDir\js\*" -DestinationPath $zip -Force
    Write-Host "[ZIP] $zip" -ForegroundColor Green
}
if ((Test-Path "$TargetDir\native\fist-mbt.exe")) {
    $zip = "$TargetDir\fist-mbt-native-win-x64-v$Version.zip"
    Compress-Archive -Path "$TargetDir\native\*" -DestinationPath $zip -Force
    Write-Host "[ZIP] $zip" -ForegroundColor Green
}

Write-Host "=== Done ===" -ForegroundColor Green
Get-ChildItem $TargetDir -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Replace($TargetDir + "\", "")
    Write-Host "  $rel  ($([math]::Round($_.Length/1MB, 2)) MB)"
}
