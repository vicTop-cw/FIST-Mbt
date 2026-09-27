#!/usr/bin/env pwsh
<#
scripts/blackbox/install.ps1 —— FIST-Mbt 黑盒安装（Windows）

来源优先级:
  1) -Source <dir>          —— 本地已构建目录 (_release)
  2) -Version + GitHub Releases 下载 URL（默认）

安装位置:
  <InstallDir>\fist-mbt.js  (或 fist-mbt.exe)
  $env:LOCALAPPDATA\FIST-Mbt\fist-mbt 下

Shim:
  在 ~/.local/bin/fist-mbt.cmd 放 shim（若目录在 PATH 上即可直接 fist-mbt）

用法:
  pwsh ./scripts/blackbox/install.ps1                                # 默认 JS 版
  pwsh ./scripts/blackbox/install.ps1 -JsOnly                        # 只装 JS 版
  pwsh ./scripts/blackbox/install.ps1 -NativeOnly                    # 只装 Native 版
  pwsh ./scripts/blackbox/install.ps1 -Source .\_release             # 从本地构建装
  pwsh ./scripts/blackbox/install.ps1 -InstallDir C:\tools\FIST-Mbt  # 自定义安装路径
#>
param(
    [string]$Source = "",                  # 本地目录；空则从 GitHub Releases 拉
    [string]$InstallDir = "$env:LOCALAPPDATA\FIST-Mbt",
    [string]$Version = "0.2.6",
    [string]$Repo = "AI/???",               # TODO: 替换为真实 GitHub repo path
    [switch]$JsOnly,
    [switch]$NativeOnly
)

$ErrorActionPreference = "Stop"
Write-Host "=== FIST-Mbt Install v$Version ===" -ForegroundColor Cyan

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
New-Item -ItemType Directory -Path "$env:USERPROFILE\.local\bin" -Force | Out-Null

function Copy-Binary($name, $zipPattern, $targetName) {
    $dest = Join-Path $InstallDir $targetName
    if ($Source -and (Test-Path (Join-Path $Source $zipPattern))) {
        Copy-Item (Join-Path $Source $zipPattern) $dest -Force
        Write-Host "  ✅ 从本地: $dest" -ForegroundColor Green
        return $true
    }
    # 远程下载
    $url = "https://github.com/$Repo/releases/download/v$Version/$zipPattern"
    Write-Host "  下载: $url" -ForegroundColor Yellow
    try {
        Invoke-WebRequest -Uri $url -OutFile "$env:TEMP\$zipPattern" -UseBasicParsing
        if ($zipPattern.EndsWith(".zip")) {
            Expand-Archive "$env:TEMP\$zipPattern" -DestinationPath "$env:TEMP\fist-unpack" -Force
            Copy-Item "$env:TEMP\fist-unpack\*" $dest -Recurse -Force
            Remove-Item "$env:TEMP\$zipPattern" -Force -ErrorAction SilentlyContinue
            Remove-Item "$env:TEMP\fist-unpack" -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Copy-Item "$env:TEMP\$zipPattern" $dest -Force
        }
        Write-Host "  ✅ 远程安装: $dest" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "  ⚠️ 下载失败（跳过）: $_" -ForegroundColor Yellow
        return $false
    }
}

$installed = @()
if (-not $NativeOnly) {
    if (Copy-Binary "JS" "fist-mbt.js" "fist-mbt.js") { $installed += "JS" }
}
if (-not $JsOnly) {
    if (Copy-Binary "Native" "fist-mbt.exe" "fist-mbt.exe") { $installed += "Native" }
}

if ($installed.Count -eq 0) {
    Write-Host "❌ 无可用二进制安装" -ForegroundColor Red
    exit 1
}

# ---------- Shim ----------
$shim = "$env:USERPROFILE\.local\bin\fist-mbt.cmd"
$jsBin = Join-Path $InstallDir "fist-mbt.js"
$nativeBin = Join-Path $InstallDir "fist-mbt.exe"

$content = @"
@echo off
REM FIST-Mbt shim — 由 install.ps1 生成
REM 用法: fist-mbt [args...]

if exist "$nativeBin" (
  "$nativeBin" %*
  goto :eof
)
node "$jsBin" %*
"@
Set-Content -Path $shim -Value $content -Encoding ASCII
Write-Host "  ✅ Shim: $shim" -ForegroundColor Green

Write-Host "`n=== 安装完成 ===" -ForegroundColor Green
Write-Host "  已装: $($installed -join ', ')"
Write-Host "  路径: $InstallDir"
Write-Host "  若 fist-mbt 不在 PATH, 请加 $env:USERPROFILE\.local\bin 到 PATH"
