#!/usr/bin/env pwsh
<#
scripts/demo.ps1 — FIST-Mbt 30 秒体验：一键自检 + CLI 演示

用法（任意机器，无需本机私有路径）：
    pwsh ./scripts/demo.ps1

行为：
    1) `moon build --target js cmd/cli` + `python scripts/patch_esm_main.py`
       （moonc ≥0.10.14 对可执行目标输出 ESM，mizchi/sqlite 的 JS 桩用 CJS require，
        不注入 shim 就直接 `node cli.js` 会 ReferenceError: require is not defined）
    2) `python scripts/mcp_smoke.py`  → 打印 MCP-SMOKE PASS（tools/list + publish + get 断言）
    3) `node <产物> demo`             → 打印「=== FIST-Mbt CLI Demo: 七态闭环 ===」，
       逐行 ✅ [1/7] publish → ✅ [2/7] claim → ✅ [3/7] plan → … → ✅ [7/7] archive，
       末行「🎉 七态闭环全绿 ✅」（字符串真源 = cmd/cli/main.mbt 的 run_demo）
    三步各自查退出码，全绿才打印 `[DEMO] PASS`，供评审 30 秒复现环境就绪。

演示数据落 temp/demo.ps1.db（FIST_DB_PATH 隔离），不写仓库根的自举台账 fist-mbt.db。
#>
$ErrorActionPreference = "Stop"

# 以脚本所在上一级作为项目根，相对定位，避免盘符/绝对路径硬编码
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
  # 每次先 build 刷新产物，避免 mcp_smoke 用到陈旧 cli.js 导致工具数不一致。
  # moon build 为增量，up-to-date 时秒级。
  Write-Host "[demo] 刷新 JS server 产物..." -ForegroundColor Cyan
  moon build --target js cmd/cli
  if ($LASTEXITCODE -ne 0) { throw "moon build 失败（rc=$LASTEXITCODE）" }

  # 现役入口产物（cmd/cli）；发布链与 ci.yml:101 用的是同一条 build 命令的同一个产物。
  $cliJs = Join-Path $root "_build\js\debug\build\cmd\cli\cli.js"
  if (-not (Test-Path $cliJs)) { throw "产物不存在：$cliJs" }

  Write-Host "[demo] 注入 ESM require shim（幂等）..." -ForegroundColor Cyan
  python scripts/patch_esm_main.py $cliJs
  if ($LASTEXITCODE -ne 0) { throw "patch_esm_main 失败（rc=$LASTEXITCODE）" }

  # 演示分录进临时库：仓库根 fist-mbt.db 是自举台账（真实任务账本），不该被一次体验写脏。
  New-Item -ItemType Directory -Path (Join-Path $root "temp") -Force | Out-Null
  $env:FIST_DB_PATH = Join-Path $root "temp\demo.ps1.db"

  Write-Host "[demo] 一键自检 (mcp_smoke)... (库=$env:FIST_DB_PATH)" -ForegroundColor Cyan
  python scripts/mcp_smoke.py
  if ($LASTEXITCODE -ne 0) { throw "mcp_smoke 未通过（rc=$LASTEXITCODE）" }

  Write-Host "[demo] CLI 全流程演示（七态闭环）..." -ForegroundColor Cyan
  node $cliJs demo
  if ($LASTEXITCODE -ne 0) { throw "cli demo 失败（rc=$LASTEXITCODE）" }

  Write-Host "`n[DEMO] PASS — 环境就绪，30 秒可复现" -ForegroundColor Green
} finally {
  Pop-Location
}
