# 2026-09-29 · 改进建议书逐条复测与计划修正 · 报告

> 任务：读 `docs/improvement-proposals-20260928.md`（12 条改进建议）与 `fist-evidence/实验/atgc-core/自动路由闭环实验报告.md`（4 条过程发现），
> 做**计划修正与完善**。落点：`docs/improvement-plan-20260929.md`。

## 结果摘要

建议书 12 条逐条打到调用面/库面/守卫面重测，结论分布：

- **前提被实测证伪 4 条**——照原案动手会修不到东西：
  - P1-1「server 响应全缓冲死锁」：同进程两次 `tools/list` 往返 **0.25s / 0.10s**，各回 129 工具。
  - P1-3「pause 被 heal 撤销」：`heal(namespace, timeout_sec=600)` 回 `healed=[]`，暂停单被列进 `watchdog_tick` 的 `blocked`；`ops_heal.mbt:82` 活跃集本就不含已暂停。
  - P2-3「盖章 ±1h 漂移」：服务端 vs 客户端 UTC 实测 **+0.2 秒**。
  - P1-4「`list(namespace=)` 过滤失灵」：BUG-85 已修；实测 `list()` 全库 4 个 ns / `list(probeA)` 精确 1 行，且成对回归锁已在 `store_backend_semantics_test.mbt:30`。
- **已兑现 2 条**：P0-1（`bug_fix` 单条即走，抬头+小记同一笔；`bug_mark_status` 管改判）、P1-4 的回归锁那一半。
- **成立但要改写 6 条**：P0-2 的残留位置指错（不在模板库，在 `USAGE.md` 36 处 + `AGENTS.md` Omega 表 6 行）、P0-3 只剩公网复验那一格（= BUG-116）、P1-2/P1-5/P2-1/P2-2 前提成立。
- **新报 1 条并入账**：**BUG-119（high，OPEN）**——心跳跨进程不可见 + `None => true` 首拍即死 ⇒ 无人值守每拍清空在途任务；它是 P1-5 的硬前置。

修正后的优先级：P0′ 三条（成对看护判据 → 跨进程根因 → 时钟入参归一）、P1′ 五条（未声明键可见化 / stdout 纯度 / 幂等防重 / 时间戳形状 / 执行器任务绑定）、P2′ 三条，另有 5 项交指挥官裁决（`docs/improvement-plan-20260929.md` §5）。

## 资源消耗

- 只读+隔离库探针 8 支（`temp/plan_probe_p1..p8.py`、`temp/b_now_strip.py`），全部落 `FIST_DB_PATH` 隔离库；**仓库根 `fist-mbt.db` 只打开读，未写一行**（BUG-119 的账本走默认库由 `report_bug` 落，属既有记账轨道）。
- 只读普查：`fist-mbt.db` 1986 行 / 49 ns / call_log 6904 条。
- 网络：只读 GET 探测 4 次（`raw.githubusercontent` 200；`releases/download` 三次各 21s → 000），不带任何凭据。
- 未跑 `moon test` / `moon check`：本轮改动全是文档与投影件，**不含 MoonBit 源码**（工作区里 `src/**`、`cmd/cli/**` 的改动是另一条车道的在制品，不属本轮，我不替它验）。

## 任务分配记录

- 指挥官（本会话）亲自做：读两份文档、定复核口径、逐条打调用面取证、判哪些前提要作废、写修正计划、落 BUG-119、修两格文档面。
- 未派子代理：本轮的瓶颈是"取证据要打到同一个进程/同一个库上"，委派会稀释证据链（跨会话无法复现同一夹具），且成本低于自行实测。

## 遗留风险

1. **BUG-119 未修**：无人值守（cron 每拍新进程）目前会把在途任务判死并重派；任何"自动拉起执行器"的闭环在它之前不能开工。
2. **BUG-116 仍 OPEN**：公网安装线在本机链路下测不了（raw 200 / release 资产 000 的分工已量化），收口条件写成"链路健康时同一判据跑绿"，没为关单而关单。
3. **`loop_create` 仍读未 advertise 的 `now`**：HEAD 实测全仓 `get_str(args, "now"` 恰 1 处，是 BUG-33 政策的唯一活口（本轮只记录，未改代码）。
4. **重复单仍在库**：`auto-route-20260927` 有 17 待领取 + 1 已暂停（= 报告说的 18 条），处置（archive vs delete）交裁决。
5. **判据缺口只定位未实现**：手册参数列/工具计数仍不在任何守卫扫描面上；本轮把噪声形状量清楚了（14 处命中里仅 6 处真违例），实现留给 P0′-3③。
6. **别车道的两格红只登记未处理**：`check_scripts_index`（`scripts/gen_help_docs.py` 未登记，且该文件与 `cmd/cli/help_topics.mbt`、`__cli_pkg.mbt.tmp` 同为未跟踪在制品）；`cleanup_artifacts --check` 报 77 个根 `.db` + 366 个 `temp/` 文件（CI 先删再查，本机我没跑删除步——不删别人的在制品）。

## 后续建议

- 下一轮直接按 P0′ 三条开工，第一条就是给看护做成对常驻判据（四臂：无心跳 / 有心跳 / 已暂停 / 心跳写在上一进程），并要求在 `git archive HEAD` 的旧码树上至少 1 臂红，证明锁承重。
- `executor_run` 加 `task_id` 绑定这件事**排在 BUG-119 之后**，否则自动拉起等于每拍把自己派出去的执行器判死。
- 建议给 `docs/improvement-proposals-20260928.md` 加一段「复核注记」（它自身保留 09-28 截面原样，已在 §1 基线表里标出过期项）。

## 超额内容（原任务未要求，但复核时顺手做完）

- `AGENTS.md` Omega 表 6 行按活体 schema 校正（3 行删 `now`；2 行把 `omega_verify`/`omega_verify_fix` 的入参与描述从 `task_id/判定/reason` 改成 `specs`(+`max_rounds`)）。
- `USAGE.md` 摘掉 36 处实现不读的 `now`（含两个 JSON 示例；摘前后各 13 块示例均可解析、0 坏块），两处「87 个工具」改成实测「129 个 MCP 工具」——写成带 MCP 的形状好让 `RE_TOOL_CLAIM` 数得着；§7 那次实跑的截面记录**没改数**，只加限定语。
- BUG-119 入账后按 cl7 给的处置重投影 `plugins/**` 9 个文件（逐文件 diff 只有一行账本投影）。
- 守卫复跑：`check_tools_sync` 0 / `check_doc_surface` 0 / `check_plugin_sync` 0。
- 本地提交 `cbba558`；**未推送**（推送授权是上一轮针对 v0.3.1/v0.3.4 那两次出包给的，不自动覆盖本轮）。

## 来源

- `docs/improvement-proposals-20260928.md`（待复核对象，未改动正文）
- `E:\IDEProjects\AI\fist-evidence\实验\atgc-core\自动路由闭环实验报告.md`（用户给的路径 `…\_fist_meta_prompts\实验\atgc-core\…` 不存在，实际在 fist-evidence 仓）
- 活体调用面：`_build/js/debug/build/cmd/cli/cli.js serve`（协议需 `params._meta.protocolVersion`）
- 库面：仓库根 `fist-mbt.db`（只读）＋ `temp/probe-plan.db`、`temp/probe-xhb.db`（隔离写）
- 源码锚点：`git show HEAD:src/server/server.mbt`、`src/ops/ops_heal.mbt:82,87`、`src/ops/ops_ts.mbt:24`、`src/store/store.mbt:75-96`、`src/ops/ops_cleanup.mbt:22-24`
- 账本：`memory/bugs.md` BUG-9 / 14 / 19 / 21 / 33 / 85 / 116 / 118 / **119**
- 本报告与 `docs/improvement-plan-20260929.md`、`CHANGELOG.md` v0.3.4 段、`memory/2026-09-29.md` 同轮

---

*AIGC 标注：本报告正文由 AI 依据本机实测撰写（2026-09-29）。*
