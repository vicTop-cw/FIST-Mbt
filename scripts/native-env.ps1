#!/usr/bin/env pwsh
<#
scripts/native-env.ps1 — 一键装载 Windows Native 构建环境（VS MSVC + SQLite 开发库）

用法（项目根，同一会话）：
    pwsh ./scripts/native-env.ps1                                  # 仅装载环境并提示
    pwsh ./scripts/native-env.ps1 -Run "moon test --target native" # 装载后立即执行
    pwsh ./scripts/native-env.ps1 -SqliteDev C:\sqlite-dev -VsInstallPath "D:\VSBuildTools" -Run "moon test --target native"

原理：Windows 下 native 目标需 MSVC 头/库与 sqlite3.h/sqlite3.lib「同时」可解析。
       AGENTS 已记录：注册表 User 级 INCLUDE/LIB 会被 moon 自发现的 MSVC 环境覆盖，
       故必须在此脚本所在会话内先 Enter-VsDevShell、再追加 sqlite-dev 路径。
       只加 sqlite 路径而不用完整 VS 环境，会导致测试二进制运行时堆损坏（0xc0000374），
       本脚本把这两步合到同一会话自动完成。

无硬编码：VS 安装位置用 vswhere 自动探测（BuildTools，退化到任意含 MSVC 的实例），
       可 -VsInstallPath 覆盖；sqlite-dev 默认探测常见位置，可用 -SqliteDev 或环境变量 FIST_SQLITE_DEV 覆盖。
#>
[CmdletBinding()]
param(
  [string]$VsInstallPath = "",
  [string]$SqliteDev = "",
  [string]$Run = ""
)

$ErrorActionPreference = "Stop"

# ---------- 1) 解析 sqlite-dev ----------
if ([string]::IsNullOrWhiteSpace($SqliteDev)) { $SqliteDev = $env:FIST_SQLITE_DEV }
if ([string]::IsNullOrWhiteSpace($SqliteDev)) {
  $sqliteCandidates = @("C:\sqlite-dev", "C:\sqlite", (Join-Path $PSScriptRoot "..\.sqlite-dev"))
  $SqliteDev = $sqliteCandidates | Where-Object { Test-Path (Join-Path (Join-Path $_ "include") "sqlite3.h") } | Select-Object -First 1
}
if ([string]::IsNullOrWhiteSpace($SqliteDev)) {
  $SqliteDev = "."  # 占位符：避免下方 Join-Path/Test-Path 抛错，缺失文件告警仍会照常触发
}
$sqliteInclude = Join-Path $SqliteDev "include"
$sqliteLib = Join-Path $SqliteDev "lib"
if (Test-Path (Join-Path $sqliteInclude "sqlite3.h")) {
  Write-Host "[native-env] sqlite 头文件 OK: $sqliteInclude" -ForegroundColor Green
} else {
  Write-Host "[native-env] 未找到 $sqliteInclude\sqlite3.h。Native 需 SQLite 开发库（见 README「环境要求」/ AGENTS「native 目标」）。" -ForegroundColor Yellow
  Write-Host "  可用 -SqliteDev <dir> 或环境变量 FIST_SQLITE_DEV 指向含 include\sqlite3.h 与 lib\sqlite3.lib 的根目录。" -ForegroundColor Yellow
}
if (-not (Test-Path (Join-Path $sqliteLib "sqlite3.lib"))) {
  if (-not [string]::IsNullOrWhiteSpace($Run)) {
    throw "[native-env] 未找到 $sqliteLib\sqlite3.lib，无法执行 -Run（LNK1104: sqlite3.lib）。"
  }
  Write-Host "[native-env] 未找到 $sqliteLib\sqlite3.lib。Native 链接将失败（LNK1104: sqlite3.lib）。" -ForegroundColor Yellow
}

# ---------- 2) 探测 / 校验 VS Build Tools ----------
if ([string]::IsNullOrWhiteSpace($VsInstallPath)) {
  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  if (Test-Path $vswhere) {
    $instances = & $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    foreach ($cand in $instances) {
      if (Test-Path (Join-Path $cand "Common7\Tools\Microsoft.VisualStudio.DevShell.dll")) {
        $VsInstallPath = $cand
        break
      }
    }
  }
  if ([string]::IsNullOrWhiteSpace($VsInstallPath)) {
    foreach ($root in @("${env:ProgramFiles(x86)}\Microsoft Visual Studio", "$env:ProgramFiles\Microsoft Visual Studio")) {
      $try = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
          foreach ($edition in @("BuildTools", "Community", "Professional", "Enterprise")) {
            $candidate = Join-Path $_.FullName $edition
            if (Test-Path (Join-Path $candidate "Common7\Tools\Microsoft.VisualStudio.DevShell.dll")) { $candidate; break }
          }
        } | Select-Object -First 1
      if ($try) { $VsInstallPath = $try; break }
    }
  }
}
$devShellDll = Join-Path $VsInstallPath "Common7\Tools\Microsoft.VisualStudio.DevShell.dll"
if ([string]::IsNullOrWhiteSpace($VsInstallPath) -or -not (Test-Path $devShellDll)) {
  Write-Error "[native-env] 未找到 VS Build Tools 的 DevShell.dll。请用 -VsInstallPath <dir> 显式指定（如 D:\VisualStudioBuildTools）。"
}

# ---------- 3) 同一会话装载 ----------
Import-Module $devShellDll
Enter-VsDevShell -VsInstallPath $VsInstallPath -SkipAutomaticLocation -DevCmdArguments "-arch=x64" | Out-Null
$env:INCLUDE = "$sqliteInclude;$env:INCLUDE"
$env:LIB = "$sqliteLib;$env:LIB"

Write-Host "[native-env] VS 已装载: $VsInstallPath" -ForegroundColor Green
Write-Host "[native-env] INCLUDE += $sqliteInclude ; LIB += $sqliteLib"
if (-not [string]::IsNullOrWhiteSpace($Run)) {
  Write-Host "[native-env] 执行: $Run" -ForegroundColor Cyan
  Invoke-Expression $Run
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} else {
  Write-Host "[native-env] 环境就绪。可运行: moon test --target native / moon build --target native" -ForegroundColor Cyan
}