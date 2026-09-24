#!/usr/bin/env pwsh
<#
scripts/demo.ps1 — FIST-Mbt 30 秒体验：一键自检 + CLI 演示

用法（任意机器，无需本机私有路径）：
    pwsh ./scripts/demo.ps1

行为：
    1) 若 JS server 产物缺失则先 `moon build --target js cmd/main`
    2) `python scripts/mcp_smoke.py`   → 打印 MCP-SMOKE PASS（tools/list + publish + get 断言）
    3) `moon run cmd/cli`              → 打印「发布成功 / 认领成功 / 拆分成功」
    全部通过时打印 `[DEMO] PASS`，供评审 30 秒复现环境就绪。
#>
$ErrorActionPreference = "Stop"

# 以脚本所在上一级作为项目根，相对定位，避免盘符/绝对路径硬编码
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
  # 每次先 build 刷新产物，避免 mcp_smoke 用到陈旧 main.js 导致工具数不一致。
  # moon build 为增量，up-to-date 时秒级。
  Write-Host "[demo] 刷新 JS server 产物..." -ForegroundColor Cyan
  moon build --target js cmd/main

  Write-Host "[demo] 一键自检 (mcp_smoke)..." -ForegroundColor Cyan
  python scripts/mcp_smoke.py

  Write-Host "[demo] CLI 全流程演示..." -ForegroundColor Cyan
  moon run cmd/cli

  Write-Host "`n[DEMO] PASS — 环境就绪，30 秒可复现" -ForegroundColor Green
} finally {
  Pop-Location
}