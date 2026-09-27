#!/usr/bin/env pwsh
<#
scripts/blackbox/install.ps1 —— FIST-Mbt 黑盒安装（Windows）

来源优先级:
  1) -Source <dir>          —— 本地已构建目录 (_release)
  2) GitHub Releases → GitCode Releases fallback

安装位置:
  <InstallDir>\FIST-Mbt\fist-mbt.js / fist-mbt.exe

Shim:
  ~/.local/bin/fist-mbt.cmd  放 shim（自动追加到用户 PATH）

用法:
  pwsh ./scripts/blackbox/install.ps1                                # 默认 JS 版
  pwsh ./scripts/blackbox/install.ps1 -JsOnly                        # 只装 JS 版
  pwsh ./scripts/blackbox/install.ps1 -NativeOnly                    # 只装 Native 版
  pwsh ./scripts/blackbox/install.ps1 -Source .\_release             # 从本地构建装
  pwsh ./scripts/blackbox/install.ps1 -InstallDir C:\tools           # 自定义父目录
  pwsh ./scripts/blackbox/install.ps1 -NoPath                        # 不自动改 PATH
#>
param(
    [string]$Source = "",
    [string]$InstallDir = "$env:LOCALAPPDATA",
    [string]$Version = "",
    [switch]$JsOnly,
    [switch]$NativeOnly,
    [switch]$NoPath
)

$ErrorActionPreference = "Stop"

# ---------- Repo ----------
$GitHubRepo = "vicTop-cw/FIST-Mbt"
$GitCodeRepo = "VictorTop/Fist-Mbt"

# ---------- 规范化 InstallDir（自动加 FIST-Mbt 子目录） ----------
$InstallDir = Join-Path $InstallDir "FIST-Mbt"
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
New-Item -ItemType Directory -Path "$env:USERPROFILE\.local\bin" -Force | Out-Null

# ---------- 推断版本 ----------
if (-not $Version) {
    if ($Source -and (Test-Path "$Source\VERSION")) {
        $Version = (Get-Content "$Source\VERSION" -Raw).Trim()
        Write-Host "[VERSION] 从本地: $Version" -ForegroundColor DarkGray
    } else {
        $Version = "0.3.0"
        Write-Host "[VERSION] 默认: $Version (可 -Version 指定)" -ForegroundColor DarkGray
    }
}
Write-Host "=== FIST-Mbt Install v$Version ===" -ForegroundColor Cyan

# ---------- Node >=24 检查 ----------
function Test-Node {
    param([int]$MinMajor = 24)
    try {
        $v = (& node -v) 2>$null
        if (-not $v) { Write-Host "  未找到 node" -ForegroundColor Red; return $false }
        $major = [int]($v -replace '^v', '' -split '\.')[0]
        if ($major -lt $MinMajor) {
            Write-Host "  node 版本过低: $v (需要 >=v$MinMajor)" -ForegroundColor Red
            return $false
        }
        Write-Host "  node $v OK" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "  node 不可用: $_" -ForegroundColor Red
        return $false
    }
}
$needNode = -not $NativeOnly
if ($needNode) { Test-Node | Out-Null }

# ---------- 双源下载 ----------
function Download-Artifact {
    param(
        [Parameter(Mandatory)] [string]$Filename,
        [Parameter(Mandatory)] [string]$Version,
        [Parameter(Mandatory)] [string]$Dest
    )
    $url1 = "https://github.com/$GitHubRepo/releases/download/v$Version/$Filename"
    Write-Host "  GitHub: $url1" -ForegroundColor DarkGray
    try {
        Invoke-WebRequest -Uri $url1 -OutFile $Dest -UseBasicParsing -TimeoutSec 30
        Write-Host "  GitHub OK" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "  GitHub 失败" -ForegroundColor Yellow
    }
    $url2 = "https://gitcode.com/$GitCodeRepo/releases/download/v$Version/$Filename"
    Write-Host "  GitCode: $url2" -ForegroundColor DarkGray
    try {
        Invoke-WebRequest -Uri $url2 -OutFile $Dest -UseBasicParsing -TimeoutSec 30
        Write-Host "  GitCode OK" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "  GitCode 也失败" -ForegroundColor Red
        return $false
    }
}

# ---------- 解包 + 安装 ----------
function Install-Package {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$ZipPattern,
        [Parameter(Mandatory)] [string]$TargetName
    )
    $destMain = Join-Path $InstallDir $TargetName
    $localZip = $null
    if ($Source) {
        foreach ($sub in @("", "js", "native")) {
            $cand = if ($sub) { Join-Path $Source "$sub\$ZipPattern" } else { Join-Path $Source $ZipPattern }
            if (Test-Path $cand) { $localZip = $cand; break }
        }
        if (-not $localZip) {
            $bare = Join-Path $Source $TargetName
            if (Test-Path $bare) {
                Copy-Item $bare $destMain -Force
                $barePatch = Join-Path $Source "patch_esm_main.py"
                if (Test-Path $barePatch) { Copy-Item $barePatch (Join-Path $InstallDir "patch_esm_main.py") -Force }
                Write-Host "  OK 本地裸文件: $destMain" -ForegroundColor Green
                return $true
            }
        }
    }
    if ($localZip) {
        $zipPath = $localZip
    } else {
        $zipPath = Join-Path $env:TEMP $ZipPattern
        if (-not (Download-Artifact -Filename $ZipPattern -Version $Version -Dest $zipPath)) { return $false }
    }
    $unpack = Join-Path $env:TEMP ("fist-unpack-" + [guid]::NewGuid().ToString("N"))
    try {
        Expand-Archive $zipPath -DestinationPath $unpack -Force
        Get-ChildItem $unpack -File -Recurse | ForEach-Object {
            if ($_.Name -eq $TargetName) { Copy-Item $_.FullName $destMain -Force }
            if ($_.Name -eq "patch_esm_main.py") { Copy-Item $_.FullName (Join-Path $InstallDir "patch_esm_main.py") -Force }
        }
        if (-not (Test-Path $destMain)) { Write-Host "  zip 内未找到 $TargetName" -ForegroundColor Red; return $false }
        Write-Host "  OK ${Name}: $destMain" -ForegroundColor Green
    } catch {
        Write-Host "  解包失败: $_" -ForegroundColor Red
        return $false
    } finally {
        Remove-Item $unpack -Recurse -Force -ErrorAction SilentlyContinue
        if (-not $localZip) { Remove-Item $zipPath -Force -ErrorAction SilentlyContinue }
    }
    return $true
}

# ---------- 执行安装 ----------
$installed = @()
if (-not $NativeOnly) {
    if (Install-Package -Name "JS" -ZipPattern "fist-mbt-js-v$Version.zip" -TargetName "fist-mbt.js") { $installed += "JS" }
}
if (-not $JsOnly) {
    if (Install-Package -Name "Native" -ZipPattern "fist-mbt-native-win-x64-v$Version.zip" -TargetName "fist-mbt.exe") { $installed += "Native" }
}
if ($installed.Count -eq 0) {
    Write-Host "无可用二进制安装" -ForegroundColor Red; exit 1
}

# ---------- Shim ----------
$shim = "$env:USERPROFILE\.local\bin\fist-mbt.cmd"
$jsBin = Join-Path $InstallDir "fist-mbt.js"
$nativeBin = Join-Path $InstallDir "fist-mbt.exe"
$patchPy = Join-Path $InstallDir "patch_esm_main.py"
$content = @"
@echo off
REM FIST-Mbt shim — v$Version
if exist "$nativeBin" (
  "$nativeBin" %*
  goto :eof
)
REM 若 ESM require 报错, 运行 python $patchPy 重新 patch
node "$jsBin" %*
"@
Set-Content -Path $shim -Value $content -Encoding ASCII
Write-Host "  OK Shim: $shim" -ForegroundColor Green

# ---------- PATH 追加 ----------
$binDir = "$env:USERPROFILE\.local\bin"
$pathUser = [Environment]::GetEnvironmentVariable("PATH", "User")
if ((-not $NoPath) -and ($pathUser -notlike "*$binDir*")) {
    $newPath = if ([string]::IsNullOrWhiteSpace($pathUser)) { $binDir } else { "$binDir;$pathUser" }
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
    $env:PATH = "$binDir;" + $env:PATH
    Write-Host "  OK 追加 $binDir 到用户 PATH" -ForegroundColor Green
} else {
    Write-Host "  (PATH 未修改)" -ForegroundColor DarkGray
}

# ---------- ESM patch（JS 版）----------
if (-not $NativeOnly -and (Test-Path $jsBin) -and (Test-Path $patchPy)) {
    try {
        & python $patchPy $jsBin 2>&1 | ForEach-Object { Write-Host "  patch: $_" -ForegroundColor DarkGray }
    } catch {
        Write-Host "  (ESM patch 跳过: python 不可用)" -ForegroundColor DarkGray
    }
}

# ---------- Doctor 自检 ----------
$doctorTarget = if ($NativeOnly) { $nativeBin } else { $jsBin }
if ($doctorTarget -and (Test-Path $doctorTarget)) {
    Write-Host ""
    Write-Host "=== 自检: fist-mbt doctor ===" -ForegroundColor Cyan
    try {
        & node $doctorTarget doctor 2>&1 | Select-Object -Last 8 | ForEach-Object {
            if ($_ -match "✅") { Write-Host "  $_" -ForegroundColor Green }
            elseif ($_ -match "⏭️") { Write-Host "  $_" -ForegroundColor DarkGray }
            else { Write-Host "  $_" }
        }
    } catch {
        Write-Host "  (doctor 跳过: $_)" -ForegroundColor Yellow
    }
}

Write-Host "`n=== 安装完成 ===" -ForegroundColor Green
Write-Host "  已装: $($installed -join ', ')"
Write-Host "  路径: $InstallDir"
Write-Host "  Shim: $shim"
Write-Host "  运行: fist-mbt --help"
