#!/usr/bin/env pwsh
param(
    [string]$Version = "0.3.0",
    [string]$TargetDir = "$PSScriptRoot\..\..\_release",
    [switch]$SkipNative,
    [switch]$SkipJs
)
$REPO_ROOT = (Resolve-Path "$PSScriptRoot\..\..").Path
$ErrorActionPreference = "Stop"

function Invoke-MoonBuild($target, $label) {
    $prevErr = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    Write-Host "[$label] moon build --target $target ..." -ForegroundColor Yellow
    $result = (& moon build --target $target 2>&1 | Out-String)
    $ExitCode = $LASTEXITCODE
    $ErrorActionPreference = $prevErr
    $result -split "`n" | Select-Object -Last 3 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    if ($ExitCode -ne 0) {
        Write-Host "[$label] build failed (exit $ExitCode)" -ForegroundColor Red
        return $false
    }
    return $true
}

Write-Host "=== FIST-Mbt Blackbox Build v$Version ===" -ForegroundColor Cyan
Write-Host "Repo root: $REPO_ROOT"

if (Test-Path $TargetDir) { Remove-Item -Recurse -Force $TargetDir }
New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
if (-not $SkipJs)    { New-Item -ItemType Directory -Path "$TargetDir\js"    -Force | Out-Null }
if (-not $SkipNative) { New-Item -ItemType Directory -Path "$TargetDir\native" -Force | Out-Null }

$any = $false

if (-not $SkipJs) {
    if (Invoke-MoonBuild "js" "JS") {
        $jsMain = Resolve-Path "$REPO_ROOT\_build\js\debug\build\cmd\main\main.js" -ErrorAction SilentlyContinue
        if (-not $jsMain) { Write-Host "[JS] main.js not found" -ForegroundColor Red; exit 1 }
        Write-Host "[JS] patching ESM createRequire ..." -ForegroundColor Yellow
        $patchScript = Resolve-Path "$PSScriptRoot\patch_esm_main.py" -ErrorAction SilentlyContinue
        if ($patchScript) { python $patchScript $jsMain } else { Write-Host "[JS] patch skipped" -ForegroundColor DarkGray }
        Copy-Item $jsMain "$TargetDir\js\fist-mbt.js" -Force
        if ($patchScript) { Copy-Item "$PSScriptRoot\patch_esm_main.py" "$TargetDir\js\patch_esm_main.py" -Force }
        $kb = [math]::Round((Get-Item "$TargetDir\js\fist-mbt.js").Length / 1024, 1)
        Write-Host "[JS] OK: fist-mbt.js ($kb KB)" -ForegroundColor Green
        $any = $true
    } else { exit 1 }
}

if (-not $SkipNative) {
    $nativeEnv = Resolve-Path "$REPO_ROOT\scripts\native-env.ps1" -ErrorAction SilentlyContinue
    if ($nativeEnv) { try { . $nativeEnv } catch { } }
    if (Invoke-MoonBuild "native" "Native") {
        $nativeMain = Resolve-Path "$REPO_ROOT\_build\native\debug\build\cmd\main\main.exe" -ErrorAction SilentlyContinue
        if ($nativeMain) {
            Copy-Item $nativeMain "$TargetDir\native\fist-mbt.exe" -Force
            Write-Host "[Native] OK: fist-mbt.exe" -ForegroundColor Green
            $any = $true
        }
    } else {
        Write-Host "[Native] skipped (MSVC+sqlite3.lib may be needed)" -ForegroundColor Yellow
    }
}

if (-not $any) { Write-Host "[FAIL] no artifacts" -ForegroundColor Red; exit 1 }

Set-Content -Path "$TargetDir\VERSION" -Value $Version -Encoding ASCII

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
    $mb = [math]::Round($_.Length / 1048576, 2)
    Write-Host "  $rel  ($mb MB)"
}
