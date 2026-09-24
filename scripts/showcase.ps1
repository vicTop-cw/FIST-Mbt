#!/usr/bin/env pwsh
<#
scripts/showcase.ps1 — FIST-Mbt 30~60 秒视觉终端演示

在 Windows Terminal / VS Code 终端（UTF-8 + ANSI 真色）中渲染：
  1. Header 横幅 + 徽章 + mooncakes 发布信息
  2. 九态生命周期状态机（box-drawing）
  3. DAG 依赖结构图（递归拆解）
  4. 自举采用证据（读盘真实数据：review 轮数 + SQLite 任务/执行数）
  5. Footer 汇总

用法（自包含、相对路径、不硬编码盘符）：
    pwsh -NoProfile -File scripts/showcase.ps1

任何一步失败都会优雅降级为打印提示，绝不抛异常。
#>
$ErrorActionPreference = "SilentlyContinue"

$root = Split-Path -Parent $PSScriptRoot   # FIST-Mbt 根
$reviewsDir = Join-Path $root "memory\reviews"
$dbPath     = Join-Path $root "fist-mbt.db"

# ---- ANSI 色彩原语（直接输出转义码，Windows Terminal / CI 均可用）----
$ESC  = [char]27
$GREEN = "$ESC[0;32m"; $CYAN = "$ESC[0;36m"; $YELLOW = "$ESC[0;33m"
$BOLD  = "$ESC[1m";    $RED  = "$ESC[0;31m"; $MAG  = "$ESC[0;35m"

# 给一段文本上色，返回整串（复位码已含）。
function C([string]$code, [string]$s) { return ($code + $s + $ESC + "[0m") }
function W([string]$s) { Write-Output $s }   # 整行输出，规避命令拼接歧义

# ================ 1. HEADER 横幅 ================
Write-Output ""
$lineH  = (C $CYAN "┌────────────────────────────────────────────────────────────────────────┐")
$line1 = (C $CYAN "│ ") + (C $GREEN "FIST-Mbt") + (C $CYAN "  — 纯 MoonBit 版 FIST 指挥官任务分配体系 · MCP Server")
$line1 = $line1.PadRight(80 - 1) + (C $CYAN "│")
$line2 = (C $CYAN "│ ") + (C $CYAN "徽章: ") + (C $GREEN "[moon:js] [moon:native] [moon:js-windows]  CI 3 tracks")
$line2 = $line2.PadRight(80 - 1) + (C $CYAN "│")
$line3 = (C $CYAN "│ ") + (C $YELLOW "vicTop-cw/fist-mbt@0.2.4  ·  mooncakes published")
$line3 = $line3.PadRight(80 - 1) + (C $CYAN "│")
$lineF  = (C $CYAN "└────────────────────────────────────────────────────────────────────────┘")
W $lineH; W $line1; W $line2; W $line3; W $lineF

# ================ 2. 九态生命周期状态机 ================
Write-Output ""
$h = (C $YELLOW "任务生命周期  LIFECYCLE  九态状态机 / 源自 src\core\core_task.mbt")
W $h

$r1 = (C $GREEN "[待领取 Pending]").PadRight(18) + " ──▶ " + (C $GREEN "[已领取 Claimed]").PadRight(18) + " ──▶ " + (C $CYAN "[拆分中 Splitting]").PadRight(20) + " ──▶ " + (C $CYAN "[执行中 Executing]")
W ("  " + $r1)
$r2 = (C $CYAN "[待验收 Reviewing]").PadRight(18) + " ──▶ " + (C $GREEN "[已完成 Completed]").PadRight(17) + " ──▶ " + (C $YELLOW "[已归档 Archived]")
W ("  " + $r2)
# 分支：验收不通过 → Rejected → 重新执行（retry）
W ("  " + (C $CYAN "[待验收 Reviewing]") + " ─(验收不通过)─▶ " + (C $RED "[已打回 Rejected]") + " ──retry──▶ " + (C $CYAN "[执行中 Executing]"))
# 分支：任意活跃态可暂停
W ("  " + (C $MAG  "外部中断 / 等待依赖　──▶  [已暂停 Paused]　─resume─▶ [已领取 Claimed]"))

# ================ 3. DAG 依赖结构图 ================
Write-Output ""
$h2 = (C $YELLOW "依赖图  DAG  （任务递归拆解样例）")
W $h2
W ("  " + (C $GREEN  "R0 ┌ 根任务「重构 store 层为 SQLite」"))
W ("  " + (C $CYAN   "   ├── A  「对比 store_sqlite.mbt」"))
W ("  " + (C $CYAN   "   │      └── A1「JS 后端 node:sqlite 读写用例」"))
W ("  " + (C $CYAN   "   │      └── A2「native 链接 SQLite 环境」"))
W ("  " + (C $CYAN   "   ├── B  「迁移 store_sqlite.mbt」"))
W ("  " + (C $CYAN   "   │      └── B1「migrations 建表 DDL」"))
W ("  " + (C $CYAN   "   └── C  「moon test --target js/native」"))
W ("  " + (C $CYAN   "          └── C1「spring13 · CI 三轨验证」"))

# ================ 4. 自举采用证据（读盘真实数据） ================
Write-Output ""
$h3 = (C $YELLOW "自举采用  SELF-DRIVE DOGFOOD  （读盘真实证据）")
W $h3

# 4a. review 轮数
$reviewCount = -1
if (Test-Path $reviewsDir) {
    $reviewCount = @(Get-ChildItem -Path $reviewsDir -Filter *.md -File -ErrorAction SilentlyContinue).Count
}
$revStr = if ($reviewCount -ge 0) { "$reviewCount" } else { "n/a" }

# 4b. SQLite 任务/执行数（用 python，base64 内联脚本规避引号转义）
$taskCount = -1; $execCount = -1
$py = @'
import sqlite3, sys
db = sys.argv[1]
c = sqlite3.connect(db)
try:
    t = c.execute("select count(*) from tasks").fetchone()[0]
    e = c.execute("select count(*) from executions").fetchone()[0]
    print(f"{t}|{e}")
except Exception:
    print("-1|-1")
'@
$pyb64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($py))
$pyArgs = "-c", ("exec(__import__('base64').b64decode('" + $pyb64 + "').decode('utf-8'))"), $dbPath
$result = (& python @pyArgs 2>$null)
if ($LASTEXITCODE -eq 0 -and $result -match "^(\d+)\|(\d+)$") {
    $taskCount = [int]$matches[1]; $execCount = [int]$matches[2]
}
$tStr = if ($taskCount -ge 0) { "$taskCount" } else { "n/a" }
$eStr = if ($execCount -ge 0) { "$execCount" } else { "n/a" }

W ("  " + (C $GREEN "▶ 子代理自审轮数  (memory\reviews\)：") + (C $BOLD $revStr) + (C $GREEN " 轮 review 存档"))
if ($taskCount -ge 0) {
    W ("  " + (C $GREEN "▶ 自举迭代库  (fist-mbt.db)：") + (C $CYAN $tStr) + " tasks  /  " + (C $CYAN $eStr) + " executions")
    W ("     " + (C $CYAN "→ FIST-Mbt 正用自己管理自己的迭代，实际跑出了 ") + (C $BOLD $tStr) + (C $CYAN " 项任务"))
} else {
    W ("  " + (C $YELLOW "▶ 自举迭代库：未找到可用的 python / sqlite，跳过真实计数（演示不会崩）"))
}
Write-Output ""

# ================ 5. FOOTER 汇总 ================
$f1 = (C $GREEN "61 MCP tools") + (C $CYAN " · ") + (C $GREEN "165 tests") + (C $CYAN " · ") + (C $GREEN "JS+Native") + (C $CYAN " · ") + (C $GREEN "CI 3 tracks")
W ("  " + $f1)
W ("  " + (C $BOLD (C $CYAN "fist-mbt drives itself ─ 自举采用，自动演进")))
Write-Output ""
exit 0