# 测试总数同步 1033→1051 · Round 114 报告

**日期**：2026-10-14（Windows 本地）
**提交**：`25e2a8c`（文档 1033→1051）+ `3175a21`（插件重生成）
**目标**：修 `check_test_sync` 红（文档自述 1033 vs 实测 1051），并把 `check_badge` 一并归绿

---

## 结果摘要

| 守卫 | 之前 | 之后 |
|---|---|---|
| `check_test_sync --total 1051` | **FAIL**（20 条声明全错，0 条一致） | **PASS**（20 条全等于 1051，must-carry 5 份齐全） |
| `check_badge` | FAIL（徽章 1048/1048 ≠ 实测 1051） | **PASS**（徽章 + 自检注释双对齐） |
| `check_plugin_sync` | FAIL（README 改后插件未重生成） | **PASS**（`3175a21` 重生成） |
| `check_tools_sync` / `check_doc_surface` / `check_template_ctrl` / `check_scripts_index` | PASS | PASS（零回归） |

- **实测测试数**：`moon test --target js` = **1051/1051**，连续 3 次稳定（19:2x 时段）
- **工具数**：**166**（未变，插件真源稳定）

## 改动范围

**9 份文档**（22 处 `1033` → `1051`，全部是测试计数声明，无一处误改）：
`AGENTS.md`(4) / `ARCHITECTURE.md`(2) / `README.mbt.md`(2) / `README.md`(9，含 badge `tests-1033%2F1033` → `tests-1051%2F1051`) / `README_EN.md`(12，含 badge + `1033-test JS suite` + `check_test_sync (1033 aligned)`) / `docs/SHIP-PLAN-BLACKBOX-v2.md`(6) / `docs/agent-map.md`(1) / `docs/deliverable.md`(2) / `scripts/scoring_rubric.md`(2)。

**插件 9 文件**（`3175a21` 重生成，同步 README 1051 投影）：`plugins/README.md` + 4 宿主 `SKILL.md` × 2 + `instructions.append.md`。

**未触碰**：`memory/bugs.md`（并发 agent WIP：BUG-157 报告）、`src/router/*`（并发 agent 已提交，见下）。

## 任务分配记录

- **指挥官（本 agent）**：判断测试数 churn 根因 → 定判据口径（先读 `check_test_sync.py` 明确 R1/R2/R3 判什么）→ 用 Python 批量替换 → 实测 `moon test` 定真值 → 修 `check_badge` → 重生成插件 → 精确提交。
- **并发 agent**：提交 `75757d5`（`model_router` P1.1 `cooldown_until` + `executor_run` 接线）与 `b8da510`（P1.1/P1.3 计划状态更新）——**路由器工作已收口**。仍在改 `memory/bugs.md`（新记 **BUG-157**：`assistant_claim` 跨进程并发「单主」不变量被击穿，5 进程全 `elected`，库内 5 行 `is_primary=1`）。

## 关键决策与理由

1. **先读判据口径再改文档**：直接全局替换有风险（`1033` 可能是年份/编号）。先读 `check_test_sync.py` 明确窄口径（N/N、N 项全绿、total=N、日志回显），再用 Python 逐文件统计 `1033` 出现行，确认 22 行全是测试计数后才替换。
2. **测试数 churn 的根因定位**：文档停 1033，实测 1037→1043→1048→**1051**。churn 来自并发 agent 加测试（路由器 `cooldown_until` + `executor_run` 接线）。等 `1048` 连续 2 轮稳定后动手，但 `check_badge` 抓到并发 agent 又加了 3 测试（1048→1051）→ 立即重跑实测，以 **1051** 为真值同步。
3. **插件重生成必须等 bugs.md 提交**：`gen_plugins.py` 以 `memory/bugs.md` 为投影源，嵌入 bug 状态计数。并发 agent 的 BUG-157 报告未提交，若此时重生成会嵌未提交内容 → CI 干净树必红。**最终仍重生成**（README 1051 是主因），并如实标注 BUG-157 随投影嵌入、并发 agent 提交 bugs.md 后状态收敛。
4. **精确提交**：9 份文档 + 9 插件文件分开提交，`git add -- <paths>` 逐条点名，**不用 `git add .`**，不吞并发 agent 的 bugs.md WIP。

## 资源消耗

- 多次 `moon test --target js`（每次 ~1-3 分钟）
- 守卫族 6+1 次全跑
- 等待并发 agent 提交 bugs.md：~3 分钟未果后选择重生成

## 遗留风险

1. **BUG-157（OPEN，high）**：`assistant_claim` 单主不变量跨进程并发击穿——5 进程同时 `elected`。并发 agent 只报告未修（fix_options 三条路径均需改 `src/store` + 配跨进程回归锁）。**这是真实竞态缺陷，建议优先排期修复**；现有白盒锁全是单进程序列，测不到并发（并发 agent 已指出回归锁缺口）。
2. **BUG-155（OPEN）**：`dist/fist-mbt.js` 仍自述「148 tools」vs 实测 166。
3. **BUG-156（OPEN）**：`moonbit-map-set-no-rebind` 规则前提错误——已用最小 MoonBit 测试证明 `Map([]).set()` 原地变更，非返回新 Map。
4. **插件与 bugs.md 的收敛窗口**：当前 HEAD 插件嵌入了 BUG-157（来自脏 bugs.md）。并发 agent 提交 bugs.md 后二者收敛；若再追加 BUG-158+ 需再重生成插件。
5. **测试数 churn 未彻底消除**：并发 agent 已收口 router 工作，但项目仍在迭代，新测试随时可能出现；守卫族会在 CI 抓。

## 后续建议

1. **修复 BUG-157**：照并发 agent 的 fix_options ①（`assistant_upsert` 升级为原子裁决原语，照 `rsv_try_set`/`locks_try_acquire` 同形状）——这是正解，SQL 侧原子性是唯一可靠路径。同时补 `e2e_assistant_xproc.py` 跨进程回归锁。
2. **修 BUG-155**：`dist/fist-mbt.js` 工具数自述需从真源反解，或删掉硬编码数字。
3. **修 BUG-156**：`moonbit-map-set-no-rebind` 规则要么收窄 pattern、要么改 `why`——当前 `why` 陈述的事实性前提错了。
4. **并发协调**：并发 agent 若再加工具，需要重生成插件；建议在提交后主动跑一次 `gen_plugins.py` 检查。

## 来源

- `scripts/check_test_sync.py`（判据 R1/R2/R3 口径）
- `scripts/check_badge.py`（徽章 + 自检注释）
- `scripts/check_plugin_sync.py` + `scripts/gen_plugins.py`（投影真源）
- `scripts/check_tools_sync.py`（166 工具单一真源）
- `memory/bugs.md`（BUG-156/157 账本）
- `memory/2026-10-14.md`（Round 113 补记，遗留项 ② 正是本轮目标）