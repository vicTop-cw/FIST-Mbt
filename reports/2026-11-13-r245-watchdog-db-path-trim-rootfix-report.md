# 轮 245 唤醒巡检报告——db_path_from_env 加 trim 根治尾随空格 stray 上游成因（r197/r241 挂账首次代码面落地）+ P3 WIP 定性升级（跨项目误落账 · BUG-565 形状）+ r244 承诺触发：owner 正式呈报（看门狗降频 / 事件驱动信号）

- 日期：2026-11-13（Fri）
- 轮次：r245（ExploreWatchdog 每 30 分钟无窗唤醒 · temp/explore_watchdog/）
- 执行面：fist-commander 模式（统帅本人；微修复由统帅直接实施并自终审，理由见「任务分配记录」）

## 结果摘要

1. **真 bug 根治（本轮主产出）**：`SqliteStore::db_path_from_env`（`src/store/store_sqlite.mbt:177`）的 `Some(p)` 分支原样采用、**零 trim** ⇒ `FIST_DB_PATH` 被带尾随空格的值污染时去打开 `fist-mbt.db `（带空格），Windows 落 0 字节 stray 文件（r197 首现、r241 surgical 清存量时定性为「上游成因面·根治需代码改动」，此后 r242/r243/r244 连续三轮挂账）。本轮落地根治：`Some(p)` 分支 `let t = p.trim().to_owned()`（MoonBit 的 `trim()` 回 StringView 借用，落库路径要 owned String）；trim 后为空串与空串同语义回默认；**路径中间空白不动**（`temp/ns db/x.db` 这类合法名不受影响——防过度修复对照锁已钉）。
2. **回归锁**：`src/store/store_db_path_wbtest.mbt` 新增 3 格 test（6 asserts）——尾随空格实测复发形态 / 首尾空白 / 纯空白视为未设置 / 路径中间空白对照（防「把空白全删掉」的过修静默通过）。
3. **验证面全绿**：`moon check` 33 warnings 0 errors（与 r241 基线一致，零新增告警）；store 包 JS 134/134；**全仓 JS 2072/2072 passed, failed 0, rc=0**（2067 为 2026-11-11 读数，其间并发批次有测试增量，本轮 +3 格新锁后 2072）；fmt 门 PASS（`moon fmt --check rc=0`——本轮本机 `--check` 管线可用，BUG-388 未复现，按 AGENTS.md「以本地落盘 + --check 通过为准」）；`moon info` 无 .mbti 差异（签名未变）。
4. **P3 WIP 定性升级（本轮增量证据）**：`memory/bugs.md` 挂账的 P3 批次（BUG-592~600，最后写账 2026-11-12 16:29:54，挂账 >20h 跨自然日）逐条读账后确认——pytest 381→384 / vue-tsc / vitest / `ask_router.py` / `mcp_acceptance.py` / `.gitattributes` 钉 rs 文件——**这是另一个 Rust+Vue 项目的条目误落本仓账本**（BUG-565 根因形状：`report_bug` 把账落到 `FIST_MBT_REPO` 指向的树）。这解释了 >20h 无人提交：持有面在裁决误落条目怎么处置，而非「忘记提交」。禁区零碰维持。
5. **owner 正式呈报（r244 承诺触发）**：r244 明确承诺「若下一轮仍零变化，正式向 owner 呈报」。本轮实测 WIP 零变化（bugs.md / target.md mtime 未动、无新并发提交、HEAD 仍 7ccce82ba）⇒ 触发条件成立，呈报见下文专节。
6. **Round C 队列**：判空维持（r225 已 git 实查坐实三事实，memory 已定死为过期指令），本轮不重推导。
7. **FIST 闭环**：T0 收口（completed_by=wd-r245），见文末。

## 改动明细

| 文件 | 改动 | 说明 |
|---|---|---|
| `src/store/store_sqlite.mbt` | `db_path_from_env` 的 `Some(p)` 分支：`if p.is_empty() { default } else { p }` → `{ let t = p.trim().to_owned() if t.is_empty() { default } else { t } }` + doc 注释同步 | 最小改动，一处分支；match arm 带 let 须花括号块（MoonBit 语法 [3002]，首轮编译实测抓到） |
| `src/store/store_db_path_wbtest.mbt` | 尾部追加 3 格 test（6 asserts） | 尾随空格实测形态 / 首尾+纯空白 / 中间空白防过修对照 |

**行为变更面（诚实披露）**：唯一行为变化是「带首尾空白的 env 值从『原样采用（落 stray 文件）』变为『trim 后采用』」。无空白路径逐字不变（既有 3 格锁全绿证明）；调用链 `SqliteStore::new()` / `server.mbt:2164` 回显 / `server_log.mbt:80` 日志路径三处消费方全部受益于同一修正。

## 任务分配记录

- 本轮为**微修复**（1 处分支 + 3 格锁，~30 行）：`task` 子代理工具集只读（read/grep/glob/web），无写权限；`team` implementer 需完整上下文传递 + 合并回合，对 30 行改动的传递成本超过改动本身 ⇒ 按 FIST 模式「轻任务」分流，统帅直接实施并自终审（终审=实际运行 `moon check` + 定向包 + 全仓测试，非自述）。
- 根因调查（Phase 1）全部只读完成：读源码定位缺陷形状、wbtest 缺口、调用面（`find_references` 31 处引用逐类：1 处真调用 `default_db_path()`、其余文档/测试/mbti 引用）、trim API 本仓先例（`store_bug475_created_by_wbtest.mbt:163` 的 `to_owned()`）。
- 编译两次失败均按 systematic-debugging 处置（读错误 → 新假设 → 最小修正）：① [3002] match arm 裸 let 不允许 → 加花括号块；② [4014] `trim()` 回 StringView 非 String → 补 `.to_owned()`。两次失败都是语法/类型面、非逻辑面，未累积到「三修问架构」阈值。

## owner 正式呈报（看门狗降频 / 事件驱动信号）

**触发依据**：r234 首次呈报「降频 / 事件驱动」信号；r244 承诺「连续多轮（r239~r244）实质活动仅『并发 agent 落地 + 只读确认』，且 WIP 挂账已跨自然日 ⇒ 若下一轮仍零变化，正式呈报」。本轮（r245）实测 WIP 零变化（两文件 mtime 逐字未动、无新提交），**承诺条件成立，正式呈报如下**：

**现状**：看门狗每 30 分钟唤醒一次；r234~r245 共 12 轮中，除并发 agent 的落地外，看门狗自身产出的「新信息」高度收敛（mcp_smoke 同源 PASS、stray 复发检查干净、计数面零影响、Round C 判空维持）。每轮固定消耗：git status/log + 若干只读确认 + 报告 + 提交 + FIST 闭环 ×4~7 调用。

**建议（三选一，请 owner 拍板）**：
1. **事件驱动**：唤醒条件从「每 30 分钟」改为「仅当 `git log` 出现新提交 或 `memory/bugs.md`、`memory/target.md` 的 mtime/内容变化时唤醒」（Windows 计划任务 + 轻量轮询脚本即可实现，脚本可落 `scripts/watchdog_event_probe.py`，需 owner 授权后另行立任务）。
2. **降频**：30 分钟 → 2 小时（保留无窗守护语义，消耗降 ~75%）。
3. **维持现状**：owner 认为当前频率的「零变化巡检」本身有价值（每轮都在验证 WIP 是否收口），不动。

**owner 同时需裁决的两件挂账**（均非看门狗射程）：
- **P3 批次误落账处置**：`bugs.md` 的 BUG-592~600 是另一项目的条目（BUG-565 形状）。建议：owner 确认后，看门狗下一轮协助**整体移除这 9 条**（scoped 提交、只动这 9 条块）+ 在 BUG-565 条目下追记实证；或 owner 指定持有面 agent 处置。
- **`memory/target.md` 孤儿 WIP**（2026-11-10 10:34 起挂账 >2 日）：单行陈旧协调行，处置权在持有面 agent / owner（覆写为新协调行即可）。

## WIP 状态（r244 基线 → 轮 245）

| 时点 | M 文件 | 未跟踪 | HEAD | 定性 |
|---|---|---|---|---|
| r244 收笔 | `memory/bugs.md` + `memory/target.md` | （无） | 0f51433fd | 跨天挂账 |
| 轮 245 开轮 | 同上（mtime 未变：bugs.md 2026-11-12 16:29:54 / target.md 2026-11-10 10:34:16） | （无） | 7ccce82ba（r244 报告） | 零变化 + 本仓动 src/ 面 |
| 轮 245 收笔 | 同前两文件（禁区零碰）+ 本轮 2 个 src/ 文件（已提交） | （无） | 本笔提交 | 零变化第 2 连轮 ⇒ 呈报触发 |

## 遗留风险

- **P3 批次（BUG-592~600）跨项目误落账仍未处置**：定性已升级为「另一项目条目误落本仓」（BUG-565 根因形状），需 owner 裁决处置方式（移除 + 追记 / 持有面 agent 处置）；在此之前 bugs.md 维持 WIP 挂账，本仓只记录不代改。
- **`memory/target.md` 孤儿 WIP**：>2 日未动，同属 owner / 持有面 agent 项。
- **本缺陷的账本回填**：`db_path_from_env` 不 trim 此前**无 bugs.md 条目**（仅 r197/r241 报告挂账）。因 bugs.md 是并发 WIP 禁区，本轮只落代码与锁，**账目（立 BUG + FIXED 状态回填）待 WIP 收口后同批补**——届时同批跑 `gen_plugins.py` 重投影。
- **全量 native 面未验**：本轮只跑 JS 目标（权威稳定门槛）；native 面受 BUG-133/BUG-527 约束维持 CI 权威口径，本机不代跑。
- **6 个 gitignored 夹具库**（alpha/beta/pf-ok/wal-a/b/c.db）仍物理留仓根（r240 owner 确认项 ①）：维持挂账。

## 后续建议

- **等 owner 对「降频 / 事件驱动」呈报拍板**（见上节三选一）；拍板前看门狗维持当前节奏。
- **P3 误落账 + target.md 孤儿**两件 owner 裁决件落地后，bugs.md / target.md 的 WIP 应能整体收口——收口那轮同批补 `db_path_from_env` 账目（立 BUG 条目 + FIXED 状态 + `gen_plugins.py` 重投影）。
- 无其他新增后续项。

## 资源消耗

- 命令：~18（git status/log/stat ×3 + grep/find_references/read 只读调查 ×8 + moon fmt/check ×4 + moon_test_env 定向 + 全仓 ×2 + check_fmt_gate + moon info ×1 + fetch_output ×1 + commit_scoped ×1 + fist.py ×4~7）。
- 测试面：store 包 134/134 + 全仓 JS 2072/2072（rc=0）。
- 改动面：2 文件 ~30 行（1 处分支修正 + 3 格锁）。

## 超额内容

无（本轮全部动作在「有 bug 优先修 bug + r244 呈报承诺 + 标准记账」授权范围内）。

## 来源

- `src/store/store_sqlite.mbt:177-190`（`db_path_from_env` 真源，改前/改后）
- `src/store/store_db_path_wbtest.mbt`（BUG-90 既有 3 格 + 本轮新增 3 格）
- `reports/2026-11-11-r197-watchdog-stray-db-report.md`（首现定性：代码产生不了带空格名 ⇒ 外部来源）
- `reports/2026-11-12-r241-watchdog-stray-trailing-space-closeout-report.md`（surgical 清存量 + 「根治需代码改动·后续 owner/代码面 agent 项」立账）
- `reports/2026-11-13-r244-watchdog-steady-mcp-smoke-report.md`（零变化承诺 + WIP 挂账基线）
- `memory/bugs.md` BUG-565（`report_bug` 跨项目误落根因形状）+ P3 批次 BUG-592~600（只读定性）
- `memory/bugs.md:10187` 附近（BUG-463/462 报告引 `db_path_from_env` 纯函数锁的既有约定）
- AGENTS.md「Commit gate / 提交纪律 / FIST 指挥官模式」
