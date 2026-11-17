# 轮 406 唤醒巡检——换面 check_store_tables_wired

**时间**：本地 2026-11-18 ~04:50 / UTC 2026-11-17T20:50
**HEAD**：`1f7f64fa7`（r405）
**WIP**：6M（全 unstaged）+ 1 untracked（他方 `reports/2026-11-17-iter-r192-report.md`），与 r393~r405 一致，暂存面为空。

## 换面：check_store_tables_wired

CI 硬门判据：库内每张表要么有写入点、要么在 store 源文件里 `schema-reserved:` 点名预留，两个方向都发红。

- **selftest**：rc=0 `SELFTEST OK: 判据对「死 schema」与「声明滞后」两个方向都发红，干净输入不误红，表名解析口径可证`
- **实跑**：rc=0 `PASS store schema 接线一致：32 张表 = 31 张有写入点 + 1 张显式预留（runs）`
- 近 30 轮未单巡（上单巡记录缺失，属长期未覆盖面），输入面（src/store/*.mbt）零 WIP 触碰，回面复核有效。

## 零漂移常设面

| 面 | 读数 | 状态 |
|---|---|---|
| `check_tools_sync` | 183 工具 R8 19 组 ΣN=183 | PASS |
| `check_instruction_budget` | 50440/65536 | PASS |
| `patch_esm_main` | 10 bundle 0 patch | up to date |

全 rc=0 零漂移。

## 立账

无新发现（类型）、无新立账。

## Round C 队列

空态确认（r385 2026-11-17 逐项实证，后续轮不重核）：
- BUG-527 治本：owner 否决严禁重跑
- BUG-530：FIXED（`3699f012a`）
- check_usage_tool_count：已注册 run_guards.py:175
- check_tool_coverage：延后至 bugs.md 解冻

⇒ 既定目标为空，不派单，走巡检分支。

## FIST 闭环

T0r406 六步（wd-r406 / ns ns-patrol）。详见 FIST 回执。

## 禁区

他方 WIP（iter-r192 车道 + 外来账 BUG-592~636）零碰；`dist/fist-mbt.js` 巡检中止轮遗留不代收，留 owner/专门轮。

## 后续建议

- Round C 队列空态持续，待 owner 设下一目标
- WIP iter-r192 车道持续冻结（r393 起 ≥13 轮未动），建议 owner 确认该车道状态（收口/放弃/继续）
