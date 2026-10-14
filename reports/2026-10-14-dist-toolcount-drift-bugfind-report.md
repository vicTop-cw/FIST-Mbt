# 2026-10-14 · 使用发布版 fist-mbt 找 bug：dist/fist-mbt.js 工具计数漂移（Round 108）

## 结果摘要

**一句话**：按用户「善用发布版的 fist-mbt 找 bug」的指示，跑发布版 v0.3.8 CLI 的 `fist help`，
发现**发货正文里的工具计数自述过期**——已提交进 HEAD 的 `dist/fist-mbt.js` 报「148 MCP tools / 15 groups」，
而真源注册表是 **166 工具 / 17 groups**；且 J14 守卫不扫 dist/ ⇒ 漂移无人认领。
按项目记账纪律上报 **BUG-155**（low，留 owner 裁决），未越权代修。

## 发现过程（真跑发布版）

1. 检查是否有 fist-mbt 进程在跑 → 多个 `fist-mbt.js serve` 进程确认发布版已装。
2. 跑 `node C:\Users\victo\AppData\Local\FIST-Mbt\fist-mbt.js --help` → 得「FIST-Mbt Help v0.3.8 (148 MCP tools)」。
3. 对照真源：`scripts/_tool_registry.py` 的 `real_tools()` = **166**，`cmd/cli/help_topics.mbt` 也写 166。
4. 深挖：`dist/fist-mbt.js`（**被 git 跟踪、提交进 HEAD**）仍是 148/15 groups —— 与源码不一致。

## 核心认知

**`dist/fist-mbt.js` 是 v0.3.0-beta 时代的遗留打包产物**：最后一次更新在 `bb87d2a`（fix(doctor)），
**无重建脚本**（全仓 grep「dist/fist-mbt」在 build/install 脚本里 0 命中），3.5MB，手提交进 git。
它不是主分发路径（主线走 `scripts/blackbox/install.ps1` `irm | iex` 装 `_release` zip），
所以**定 low 不 critical**——不影响装通，但 `fist help` 从它会读到错误计数。

**这暴露了 J14 守卫的真实边界**：`check_doc_surface.py` J14 扫描面只有
`src/server/server.mbt` + `cmd/cli/help_topics.mbt` + `ARCHITECTURE.md`（grep「dist/fist-mbt」= 0 次）。
**凡是"被提交进 git 但不在 J14 扫描面"的文档面，工具计数漂移都会无人认领**——与 BUG-136 同族。

## 交付

### ① 三面计数对表（证据）
| 面 | 工具数 | groups | 166 出现 |
|---|---|---|---|
| 真源注册表 `_tool_registry.py` | **166** | — | — |
| 源码 `cmd/cli/help_topics.mbt` | 166（3 次） | 17（1 次） | — |
| `dist/fist-mbt.js`（已提交 HEAD） | **148**（3 次） | **15**（1 次） | **0 次** |

### ② 上报 BUG-155（commit `2a94feb`）
按账本格式追加到 `memory/bugs.md`（152→153 条）：
- **summary**：dist/fist-mbt.js 工具计数自述过期（148 vs 166）+ J14 守卫缺口
- **severity**：low（非主分发路径，不影响装通）
- **fix_options**：① 重建 dist/（owner 决定）；② 从 git 跟踪删除遗留产物；③ 扩 J14 扫 dist/ 并先修计数
- **guard_gap**：明写 J14 扫描面缺 dist/，纳入即红（需先修再扩或退役）

## 验证（金条八：实际运行）

| 项 | 结果 |
|---|---|
| 发布版 CLI `fist help` | 报「148 MCP tools」——漂移在发货正文 |
| `dist/fist-mbt.js` grep「148」/「166」 | 148 出现 3 次，**166 出现 0 次** |
| 源码 `help_topics.mbt` grep「166」/「17 groups」 | 166 出现 3 次，17 groups 1 次 |
| `check_doc_surface.py` grep「dist/fist-mbt」 | **0 次**（J14 缺口确认） |
| `check_doc_surface` / `check_tools_sync` / `check_scripts_index` / `check_template_ctrl` | 全 PASS |
| `check_badge` | rc=1 是**用法错误**（需 `<moon_test_log> <README.md>` 参数），非真失败 |
| 三端同步 | `2a94feb` |

## 资源消耗

- 1 个提交：`2a94feb`（BUG-155 入账，+7 行）
- 0 `.mbt` 改动；0 CI 改动；0 `src/router/*` 触碰
- 发布版 CLI 调用 1 次 + 三面 grep 对表

## 任务分配记录

指挥官亲自：
- **按用户指示真跑发布版 fist-mbt**（`node .../fist-mbt.js --help`），不是只看文档
- 把"CLI 报 148"与"真源 166"的差异**追到根**（dist/ 是遗留产物、无重建脚本、非主路径）
- 判定严重度：**定 low 不夸大**（非主分发路径），避免把低价值发现包装成 critical
- **不越权代修**：重建 3.5MB 产物 / 退役 / 扩 J14 都会影响并发面或破坏 CI，留 owner 裁决三选一
- 账本格式严格对齐（`## BUG-n [时间] [severity] OPEN` + summary/detail/fix_options），未破坏记账规则

## 遗留风险

1. **BUG-155 未修**：dist/fist-mbt.js 计数过期 + J14 缺口仍在，等 owner 裁决（重建/退役/扩面）。
2. **J14 扩面会破坏 CI**：若直接把 dist/ 纳入 J14，现在会红（148≠166），需先修或退役。
3. `moon test` 仍 1041/1042（`cfg_ofm_2` 并发 agent 未提交 WIP，非本轮）。
4. **同类"不在 J14 扫描面的提交面"可能还有**：本轮只查了 dist/，其它被提交的文档/产物面是否也有计数漂移，未穷尽。

## 后续建议

1. **owner 裁决 BUG-155 三选一**：重建 / 退役 dist/ / 扩 J14。若选扩面，需先修计数再扩（否则 CI 红）。
2. **穷尽同类扫描面**：除 dist/ 外，是否还有"被 git 跟踪、含工具计数自述、但不在 J14 扫描面"的文件
   （如 `_release`、`docs/` 归档面）——建议后续专项扫一遍。
3. **发布版 v0.3.8 的 CLI 也报 148**：那是旧版本号，属预期；但发布流程是否应在发布前跑一次
   `check_doc_surface` 校验，防止旧产物带过期计数发布，值得纳入发布门禁。

## 超额内容

- **证明了"真跑发布版"能发现文档面看不到的漂移**：`_tool_registry.py` 真源 166，源码 help_topics 也 166，
  但**发货正文 dist/ 还停在 148**——文档面守卫全绿却仍有一面漂移，因为那面不在扫描射程。
  这是"一源四态"契约里"发货正文也算一态"的边界案例。

## 来源

- 发布版 CLI：`C:\Users\victo\AppData\Local\FIST-Mbt\fist-mbt.js`（v0.3.8）
- 源码真源：`cmd/cli/help_topics.mbt`（166/17 groups）、`scripts/_tool_registry.py`（166）
- 漂移面：`dist/fist-mbt.js`（148/15 groups，已提交 HEAD）
- 守卫缺口：`scripts/check_doc_surface.py`（J14 扫描面无 dist/）
- 账本：`memory/bugs.md` BUG-155（新 OPEN，low）
