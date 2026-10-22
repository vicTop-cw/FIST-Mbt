# 2026-10-14 lock_acquire 拒绝型互斥修复报告（BUG-154）

> 本报告专述 **BUG-154**（`lock_acquire` 锁层拒绝型互斥缺失）的修复与实证。
> 工具计数漂移 / 锁层审计的总报告见
> `reports/2026-10-14-tool-count-drift-and-lock-audit-report.md`，
> 物理锁层审计根因见 `reports/2026-10-13-multilane-lock-mechanism-report.md` §4 `[R25 勘误]`
> 与 §10.24（R24 / R25 实锤「锁层未复用 `rsv_action` 单一真源」）。

## 1. 结果摘要

- **缺陷**：`lock_acquire` 第二 agent 在 live 锁上恒获 `granted=true`，违反分布式锁契约。
  - 设计稿 `docs/2026-10-11-multi-agent-lock-design-v3.md:292` **lk2** 明确要求：
    「A 持锁后 B `lock_acquire` → `granted=false`, `blocked_by=A`」。
  - 审计结论（R24/R25）：锁层 forked 手写谓词 `lock_taken_over` 丢弃裁决、`lock_acquire` 恒回 `success=true`，
    与预订层 `rsv_action` 单一真源（能拒）形成语义对立、漂移雷。
- **修复**：引入拒绝型互斥原语 `lock_acquire_action(prev, agent, now) = rsv_action(lock_prev_for_action(prev), agent, now)`，
  双后端（`MemoryStore` / `SqliteStore`）同构实现拒绝型互斥；`lock_acquire` / `lock_renew` 工具切换为渲染裁决。
- **状态**：BUG-154 已在 `memory/bugs.md` 登记并标 `FIXED`（证据含跨进程 e2e 守卫 cell5）。
- **实证**：
  - `moon fmt --check` rc=0
  - `moon test --target js src/store` = **52/52, failed: 0**（含 4 条新 SQLite `locks_try_acquire` 集成锁 + 此前 11 条 lock 白盒锁）
  - 新增常驻跨进程回归守卫 `scripts/blackbox/e2e_lock_xproc.py`：**6 格真协议硬门全绿** + `--selftest` 27 格全绿（产物 sha256 `c6fff717`，HEAD `bb87d2a`）

## 2. 资源消耗

| 项 | 值 |
|---|---|
| 改动文件（本人署名） | 10（`store_rsv.mbt` / `store_sqlite.mbt` / `store.mbt` / `engine_rsv.mbt` / `server.mbt` / 两包 `.mbti` / `docs/posoco-hexagonal-architecture.md` / `e2e_lock_xproc.py`） |
| 新增测试 | `src/store` 4 条 SQLite 集成锁 + `e2e_lock_xproc.py` 6 格真协议 + 27 格 selftest |
| 构建/测试 | `moon build --target js cmd/cli` + `patch_esm_main.py` + `moon test` + `e2e_lock_xproc.py` |
| 兄弟 lane 文件 | 0（遵守「谁提交谁翻账」，不 `git add` 兄弟文件） |

## 3. 任务分配记录

- 修复（本人）：`lock_acquire_action` 单一真源归一 + 双后端 `locks_try_acquire` 拒绝型互斥 + `lock_acquire`/`lock_renew` 裁决渲染。
- 收口（本人）：`moon fmt` → `moon info && moon fmt` → `moon test --target js src/store` 绿 → `git commit`。
- 不越界：兄弟 lane 文件（`cmd/cli/main.mbt`、`mcp_smoke.py`、兄弟报告、`probe_doctor_loop.mbt`）不 stage；
  不翻 BACKLOG L33(self_search) / L16(native)（owner/lane 决策锁）。

## 4. 遗留风险

- `moon test` 自身退出码不可靠（BUG-142）：判绿以 `Total tests: N, passed: N, failed: 0` 汇总行为准，本修复已据此判绿。
- Native 后端同版本语义未在本机复跑（Windows 上探针拒绝出数）；BUG-133 FFI 修复后 native 与 JS 同构图，锁层改动纯逻辑、不触 FFI。
- `e2e_lock_xproc.py` 依赖 `moon build` 产物 `cli.js` + `patch_esm_main.py` 的 require shim；CI 若跑此守卫需先 build js 产物。

## 5. 后续建议

- 将 `e2e_lock_xproc.py` 接入 CI 的「锁定机制」守卫族，作为锁层回归的常驻真协议门。
- 后续环可补 `lock_acquire` 多文件 `all-or-nothing`（设计稿 v3 lk3/lk4）的跨进程实证守卫。

## 6. 超额内容

- 顺带重锚 `docs/posoco-hexagonal-architecture.md`：旧文把 `src/dag/` 当作引擎 DAG 真源，
  实测 `src/dag/` 不存在（确认缺失），真源为 `src/engine/engine_dag_ext.mbt` + `engine_dag_mc.mbt`，已改正。

## 7. 来源

- 审计根因：`reports/2026-10-13-multilane-lock-mechanism-report.md` §4 `[R25 勘误]`、§10.24（R24/R25）。
- 计数漂移报告：`reports/2026-10-14-tool-count-drift-and-lock-audit-report.md` §锁定机制审计（引用 R24/R25）。
- 设计契约：`docs/2026-10-11-multi-agent-lock-design-v3.md:292` lk2。
- 账本：`memory/bugs.md` BUG-154（FIXED，含 cell5 实证）。
- 日常记忆：`memory/2026-10-14.md`「锁定机制修复与测试」+「锁层跨进程互斥回归守卫 + 收口」两小节。
