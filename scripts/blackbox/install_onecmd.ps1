#!/usr/bin/env pwsh
<#
scripts/blackbox/install_onecmd.ps1 —— irm 一条命令安装入口

用户跑：
  irm https://raw.githubusercontent.com/vicTop-cw/FIST-Mbt/main/scripts/blackbox/install_onecmd.ps1 | iex
或（如果 GitHub raw 被墙）：
  irm https://cdn.jsdelivr.net/gh/vicTop-cw/FIST-Mbt@main/scripts/blackbox/install_onecmd.ps1 | iex
或（如果 GitCode raw 可用）：
  irm https://gitcode.com/VictorTop/Fist-Mbt/-/raw/main/scripts/blackbox/install_onecmd.ps1 | iex
#>

param(
  [string]$Version = "0.3.0-beta",
  [string]$GitUrl = "https://gitcode.com/VictorTop/Fist-Mbt.git",
  [switch]$Force
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   FIST-Mbt Blackbox Installer v$Version" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# --- 0. 预检 ---
function Test-Cmd($name) {
  return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

if (-not (Test-Cmd "git")) {
  Write-Host "❌ 需要 git，请先安装: winget install Git.Git" -ForegroundColor Red
  exit 1
}
if (-not (Test-Cmd "node")) {
  Write-Host "❌ 需要 Node.js >=24，请先安装: winget install OpenJS.NodeJS.LTS" -ForegroundColor Red
  exit 1
}
$nv = (node -v)
$nm = [int]($nv -replace '^v', '' -split '\.')[0]
if ($nm -lt 24) {
  Write-Host "❌ Node.js 版本过低: $nv (需要 >=v24)" -ForegroundColor Red
  exit 1
}
Write-Host "✅ git + node $nv OK" -ForegroundColor Green

# --- 1. git clone 浅拉 tag ---
$temp = Join-Path $env:TEMP ("fist-src-" + [guid]::NewGuid().ToString("N"))
$dest = Join-Path $env:LOCALAPPDATA "FIST-Mbt"
$bin = "$env:USERPROFILE\.local\bin"

Write-Host ""
Write-Host "📥 克隆 $GitUrl  (tag v$Version) ..." -ForegroundColor Yellow
try {
  git clone --depth 1 --branch "v$Version" $GitUrl $temp 2>&1 | Select-Object -Last 1
} catch {
  Write-Host "❌ GitCode 失败，试 GitHub fallback..." -ForegroundColor Red
  $GitUrl2 = "https://github.com/vicTop-cw/FIST-Mbt.git"
  git clone --depth 1 --branch "v$Version" $GitUrl2 $temp 2>&1 | Select-Object -Last 1
}

# --- 2. 拷产物 ---
Write-Host ""
Write-Host "📦 安装到 $dest ..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path $dest -Force | Out-Null
Copy-Item "$temp\dist\fist-mbt.js" "$dest\fist-mbt.js" -Force
Copy-Item "$temp\dist\patch_esm_main.py" "$dest\patch_esm_main.py" -Force
'{"type":"module"}' | Set-Content "$dest\package.json" -Encoding UTF8

# --- 3. ESM patch ---
python "$dest\patch_esm_main.py" "$dest\fist-mbt.js" 2>&1 | Select-Object -Last 1

# --- 4. Shim ---
Write-Host ""
Write-Host "🔧 创建 shim $bin\fist-mbt.cmd ..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path $bin -Force | Out-Null
$shim = @"
@echo off
REM FIST-Mbt shim — v$Version
node "$dest\fist-mbt.js" %*
"@
Set-Content -Path "$bin\fist-mbt.cmd" -Value $shim -Encoding ASCII

# --- 5. PATH ---
$pathUser = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($pathUser -notlike "*$bin*") {
  [Environment]::SetEnvironmentVariable("PATH", "$bin;$pathUser", "User")
  $env:PATH = "$bin;$env:PATH"
  Write-Host "✅ 追加 $bin 到用户 PATH" -ForegroundColor Green
}

# --- 6. 清理 ---
Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue

# --- 7. 自检 ---
Write-Host ""
Write-Host "🏥 自检..." -ForegroundColor Yellow
$v = node "$dest\fist-mbt.js" version 2>$null
Write-Host "  ✅ $v" -ForegroundColor Green

Write-Host ""
Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║   ✅ 安装完成！                           ║" -ForegroundColor Green
Write-Host "║   新开终端后运行: fist-mbt help            ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Green
