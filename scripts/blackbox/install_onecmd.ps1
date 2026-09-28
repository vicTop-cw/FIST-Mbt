#!/usr/bin/env pwsh
<#
scripts/blackbox/install_onecmd.ps1 —— irm 一条命令安装入口（v2 Release Assets 版）

用户跑：
  irm https://gitcode.com/VictorTop/Fist-Mbt/-/raw/main/scripts/blackbox/install_onecmd.ps1 | iex
或（GitHub 镜像）：
  irm https://raw.githubusercontent.com/vicTop-cw/FIST-Mbt/main/scripts/blackbox/install_onecmd.ps1 | iex

下载源（自动按序 fallback）：
  1. GitCode Release Assets 直链
  2. GitHub Release Assets 直链
#>

param(
  # 版本号唯一真源 = moon.mod（发布资产名也从它生成）。写死默认值的后果实测过：
  # 默认值偏一个字 ⇒ 用户跑不带参数的 `irm … | iex` 永远指向发布链不会产出的资产名（两条源都 404）。
  [string]$Version = "",
  [switch]$Force,
  # 离线/内网/发布前自证：给了本地 zip 就跳过下载（不发 Release 也能装）
  [string]$LocalZip = ""
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   FIST-Mbt Installer  v$Version" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

function Test-Cmd($name) { return [bool](Get-Command $name -ErrorAction SilentlyContinue) }

$needPython = $true
$pyCmd = if (Test-Cmd "python") { "python" } elseif (Test-Cmd "py") { "py -3" } else { "" }

if (-not (Test-Cmd "node")) { Write-Host "❌ 需要 Node.js >=24 (winget install OpenJS.NodeJS.LTS)" -ForegroundColor Red; exit 1 }
$nv = (node -v)
$nm = [int]($nv -replace '^v', '' -split '\.')[0]
if ($nm -lt 24) { Write-Host "❌ Node.js $nv 过低，需要 >=24" -ForegroundColor Red; exit 1 }
Write-Host "✅ node $nv" -ForegroundColor Green

if (-not $pyCmd) { Write-Host "⚠️ python 未找到，ESM patch 将跳过" -ForegroundColor Yellow; $needPython = $false }
else { Write-Host "✅ python ($pyCmd)" -ForegroundColor Green }

# 版本号没显式给就现取：从 moon.mod（与发布链同源的那批 raw 地址）解析，解析不到就显式失败——
# 绝不静默退回某个"猜出来的版本号"，那正是 `irm | iex` 装不上的根因。
$rawUrls = @(
  "https://raw.githubusercontent.com/vicTop-cw/FIST-Mbt/master/moon.mod",
  "https://gitcode.com/VictorTop/Fist-Mbt/-/raw/master/moon.mod"
)
$versionSource = ""
if ($Version -eq "") {
  if ($LocalZip -ne "" -and (Split-Path -Leaf $LocalZip) -match '^fist-mbt-js-v(.+)\.zip$') {
    $Version = $matches[1]; $versionSource = "本地 zip 文件名"
  } else {
    foreach ($r in $rawUrls) {
      try {
        $mm = (Invoke-WebRequest -Uri $r -UseBasicParsing -TimeoutSec 20).Content
        if ($mm -match '(?m)^\s*version\s*=\s*"([^"]+)"') { $Version = $matches[1]; $versionSource = $r; break }
      } catch {
        Write-Host "  · 取不到 $r ：$($_.Exception.Message)" -ForegroundColor DarkGray
      }
    }
  }
}
if ($Version -eq "") {
  Write-Host "❌ 无法从 moon.mod 解析版本号（候选源见上）。显式指定：& <脚本> -Version 0.3.0" -ForegroundColor Red
  exit 1
}
Write-Host "  目标版本 v$Version（来源：$versionSource）" -ForegroundColor DarkGray

$zipName = "fist-mbt-js-v$Version.zip"
$urls = @(
  "https://gitcode.com/VictorTop/Fist-Mbt/-/releases/download/v$Version/$zipName",
  "https://github.com/vicTop-cw/FIST-Mbt/releases/download/v$Version/$zipName"
)

$dest = Join-Path $env:LOCALAPPDATA "FIST-Mbt"
$bin  = Join-Path $env:USERPROFILE ".local\bin"
$temp = Join-Path $env:TEMP ("fist-install-" + [guid]::NewGuid().ToString("N"))

Write-Host ""
Write-Host "📥 下载 $zipName ..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path $temp -Force | Out-Null

$zipPath = Join-Path $temp $zipName
$downloaded = $false
if ($LocalZip -ne "") {
  if (-not (Test-Path $LocalZip)) {
    Write-Host "❌  -LocalZip 指向的文件不存在: $LocalZip" -ForegroundColor Red
    Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue; exit 1
  }
  $li = Get-Item $LocalZip
  Copy-Item $li.FullName $zipPath -Force
  Write-Host ("  ✅ 用本地 zip（跳过下载）: " + $li.FullName + " (" + [math]::Round($li.Length/1KB,1) + " KB)") -ForegroundColor Green
  $downloaded = $true
}
foreach ($u in $(if ($downloaded) { @() } else { $urls })) {
  Write-Host "  尝试: $u" -ForegroundColor DarkGray
  try {
    Invoke-WebRequest -Uri $u -OutFile $zipPath -UseBasicParsing -TimeoutSec 60
    if ((Get-Item $zipPath).Length -gt 10KB) {
      Write-Host "  ✅ 下载成功 ($([math]::Round((Get-Item $zipPath).Length/1KB,1)) KB)" -ForegroundColor Green
      $downloaded = $true; break
    } else { Remove-Item $zipPath -Force }
  } catch {
    # 吞掉异常就等于让用户分不清「资产没发布(404)」和「我这里断网」，两者处方完全不同
    $resp = $_.Exception.Response
    $code = if ($resp) { [int]$resp.StatusCode } else { "n/a" }
    Write-Host ("  ⚠️ 失败 HTTP " + $code + " (" + $_.Exception.GetType().Name + ") ... 换源") -ForegroundColor Yellow
  }
}
if (-not $downloaded) {
  Write-Host "❌ 下载全部失败（每个源的状态见上）。三种可能：Release 未发布 / 资产名不是 $zipName / 本机连不上外网" -ForegroundColor Red
  foreach ($u in $urls) { Write-Host "    - $u" -ForegroundColor DarkGray }
  Write-Host "  离线安装：& <脚本路径> -Version $Version -LocalZip $env:USERPROFILE\Downloads\$zipName" -ForegroundColor DarkGray
  Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue; exit 1
}

Write-Host ""
Write-Host "📦 解压 ..." -ForegroundColor Yellow
Expand-Archive -Path $zipPath -DestinationPath $temp -Force
$jsMain = Get-ChildItem -Path $temp -Filter "fist-mbt.js" -Recurse -File | Select-Object -First 1
if (-not $jsMain) { Write-Host "❌ zip 里没找到 fist-mbt.js" -ForegroundColor Red; Remove-Item -Recurse -Force $temp; exit 1 }
$pyPatch = Get-ChildItem -Path $temp -Filter "patch_esm_main.py" -Recurse -File | Select-Object -First 1
Write-Host "  ✅ fist-mbt.js ($([math]::Round($jsMain.Length/1024,1)) KB)" -ForegroundColor Green

Write-Host ""
Write-Host "📦 安装到 $dest ..." -ForegroundColor Yellow
if (Test-Path $dest) { if ($Force) { Remove-Item -Recurse -Force $dest } else { Write-Host "  ⚠️ 已存在，加 -Force 覆盖" -ForegroundColor Yellow } }
New-Item -ItemType Directory -Path $dest -Force | Out-Null
Copy-Item $jsMain.FullName          "$dest\fist-mbt.js"          -Force
if ($pyPatch) { Copy-Item $pyPatch.FullName "$dest\patch_esm_main.py" -Force }
'{"type":"module"}' | Set-Content "$dest\package.json" -Encoding ASCII

if ($needPython -and $pyPatch) {
  Write-Host "🔧 注入 ESM createRequire shim ..." -ForegroundColor Yellow
  Invoke-Expression "$pyCmd `"$dest\patch_esm_main.py`" `"$dest\fist-mbt.js`" 2>&1 | Select-Object -Last 1" | Out-Null
}

Write-Host ""
Write-Host "🔧 创建 shim + PATH ..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path $bin -Force | Out-Null
$shim = "@echo off`r`nREM FIST-Mbt shim — v" + $Version + "`r`nnode `"$dest\fist-mbt.js`" %*`r`n"
Set-Content -Path "$bin\fist.cmd"      -Value $shim -Encoding ASCII
Set-Content -Path "$bin\fist-mbt.cmd"  -Value $shim -Encoding ASCII

$pathUser = [Environment]::GetEnvironmentVariable("PATH", "User")
$pathChanged = $false
if ($pathUser -notlike "*$bin*") {
  [Environment]::SetEnvironmentVariable("PATH", "$bin;$pathUser", "User")
  $env:PATH = "$bin;$env:PATH"; $pathChanged = $true
}

Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "🏥 自检..." -ForegroundColor Yellow
try { $v = (& node "$dest\fist-mbt.js" version 2>&1 | Out-String).Trim(); if ($v) { Write-Host "  ✅ $v" -ForegroundColor Green } } catch { }
try { $null = (& node "$dest\fist-mbt.js" help 2>&1 | Select-Object -First 1) } catch { }
Write-Host "  ✅ fist-mbt.js 可执行" -ForegroundColor Green
try { $vv = (& fist version 2>&1 | Out-String).Trim(); Write-Host "  ✅ fist.cmd (PATH) → $vv" -ForegroundColor Green } catch { Write-Host "  ⚠️ 当前会话 PATH 未刷新（新开终端即可）" -ForegroundColor Yellow }

Write-Host ""
Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║   ✅ FIST-Mbt v$Version 安装完成！" -ForegroundColor Green
Write-Host "║   新开终端:  fist help" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Green
if ($pathChanged) { Write-Host "💡 已把 $bin 追加到用户级 PATH" -ForegroundColor DarkGray }

