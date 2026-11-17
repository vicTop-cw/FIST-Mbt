# 轮 407 唤醒巡检——换面 check_mcp_stdio_purity

**时间**：本地 2026-11-18 ~05:10 / UTC 2026-11-17T21:10
**HEAD**：`25697af75`（r406）
**WIP**：6M（全 unstaged）+ 1 untracked（他方 `reports/2026-11-17-iter-r192-report.md`），与 r393~r406 一致，暂存面为空。bugs.md mtime 2026-11-15 23:40 未动（冻结第 14 轮）。

## 换面：check_mcp_stdio_purity

CI 硬门判据：MCP server 的 stdout 必须是纯 JSON-RPC —— L1 静态扫产品 `.mbt` 里写 stdout 的调用 + L2/L3 动态 spawn 真 server 验 stdio。

- **selftest**：rc=0 `19/19 格通过`（可红可绿：L1 形态识别 8 格 + 变异对照 6 格（真写 `println` 必红 / 字符串诱饵与注释不误报）+ 反脱锚 2 格（找不到 `src/server` ⇒ rc=4 尺子坏了不判绿）+ L2/L3 判据 3 格（非 JSON 行 / 缺 content 必脏））
- **静态实跑**：rc=0 `扫 41 个产品文件（181 处 instrumented_tool）L1 干净（无写 stdout 的调用）`
- **全动态实跑**：rc=0 `[L2/L3 动态] 启动描述来源 .mcp.json（node serve-launcher.cjs serve）→ [L2] stdout 2 行全部是合法 JSON-RPC ✅ + [L3] tools/call 的 result.content 存在 ✅`
- 近 80 轮未单巡（长期未覆盖面），输入面（`src/server/*.mbt`）零 WIP 触碰，回面复核有效。

## 零漂移常设面

| 面 | 读数 | 状态 |
|---|---|---|
| `check_tools_sync` | 183 工具 R8 19 组 ΣN=183 | PASS |
| `check_instruction_budget` | 50440/65536 | PASS |
| `patch_esm_main` | 0/10 bundles up to date | up to date |

全 rc=0 零漂移。

## 立账

无新发现（类型）、无新立账。

## Round C 队列

空态确认（r385 2026-11-17 逐项实证，后续轮不重核）：
- BUG-527 治本：owner 否决严禁重跑（2026-11-02 A/B 裁决：摘库包 cc-link-flags 反断 CI native）
- BUG-530：FIXED（`3699f012a`）
- check_usage_tool_count：已注册 run_guards.py:175
- check_tool_coverage：延后至 bugs.md 解冻（BUG-636 中危判据缺陷）

⇒ 既定目标为空，不派单，走巡检分支。

## FIST 闭环

T0r163 六步全 rc=0（wd-r407 / ns watchdog），`get` 终审 `status=已完成`、`completed_by=wd-r407`、deliverable 已挂本报告。（本轮 FIST 链路连上常驻热 server，秒级收口，未复现内存压力 transient MemoryError——patch_esm_main probe 0/10 已先行确认环境干净。）

## 禁区

他方 WIP（iter-r192 车道 + 外来账 BUG-592~636）零碰；`dist/fist-mbt.js` 巡检中止轮遗留不代收，留 owner/专门轮。

## 后续建议

- Round C 队列空态持续，待 owner 设下一目标。
- WIP iter-r192 车道持续冻结（r393 起 ≥14 轮未动），建议 owner 确认该车道状态（收口 / 放弃 / 继续）。
