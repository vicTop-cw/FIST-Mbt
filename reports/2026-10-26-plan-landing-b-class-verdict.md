# B 类 21 条「落地 vs 作废」裁决材料

> **任务**：对 Lane E 报告（`d5a84c76`）给出的 B 类 21 条「真缺失（跟踪面与磁盘都没有）」逐条给三选一判定 + 可复核证据。
> **日期**：2026-10-26 · **执行者**：commander-delta
> **边界**：只读 + 写报告；**未改 `src/` / `scripts/` 任何文件**；未用 `reserve_scope`（BUG-413 fail-closed）

---

## 一、结论（21 条分档 · **2026-10-26 统帅裁决后**）

| 判定 | 数量 | 条目 |
|---|---|---|
| **(i) 真未落地**（应排期开发）| **0** | —— |
| **(ii) 已以别的形态实现**（应标作废）| **13** | B2, B4, B6, B7, B10, B13, B15, B16, B17, B18, B19, B20, B21 |
| **(iii) 计划本身已作废**（应标作废）| **8** | B1, B3, B5, B8, B9, B14, **B11, B12** |

**合计 21 条，与 Lane E 的判定面一致。**
**裁决结论：21 条全部作废（13 条 (ii) + 8 条 (iii)），无一需要排期。**

> **⚠️ B11/B12 原判 (i)，经统帅裁决改判 (iii)。**
> 下方 §二 的 B11/B12 行**保留原始判定与证据原文**（那是当时下判的依据）——
> 按判例-45「叙述面只追加、不改写」，不做涂改。
> 改判理由见 **§三 末段「关于 B11/B12 的改判」**；将来该不该重开见 **§六「重新评估的触发条件」**。

### 与 Lane E 的差异（三处，均有实测依据）

| # | Lane E 的判定 | 我的判定 | 差异原因 |
|---|---|---|---|
| **B16** | **落地**（「测试文件确缺」）| **(ii) 已实现** | 实测 `supervisor_tools_wbtest.mbt` **有 9 个 test、覆盖全部 8 个工具、387/387 全绿**（见 §二 B16）。不是缺测试，是**命名 `_wbtest` 而非 `_test`** |
| **B13** | 标作废 | **(ii) 已实现** | `templates/` 已有 **8 份 `pipeline_mode_*.md`**，与 B19 同族；worktree 等待模板的**能力面已被 `scripts/run_light_wt.py` 实现** |
| **B1/B9** | 标作废（理由：「`memory/` 已被 .gitignore」）| **(iii) 但理由要改** | **实测 `.gitignore` 未整体忽略 `memory/`**（L90 注释明写「逐文件/前缀精确点名，不整目录挡」）。正确理由：`lock-config.json` 未被采纳，TTL 走工具参数而非配置文件 |

---

## 二、证据（21 条逐条表格）

### 前置：21 个点名路径「跟踪面 + 磁盘」双查

```
命令：for p in <21 paths>; do git ls-files -- "$p"; [ -e "$p" ]; done
结果：全部 tracked=0 / disk=no  ⇒  Lane E 的判定面准确，21 条都确实不存在
```

---

### B1 | `memory/lock-config.json`

| 项 | 内容 |
|---|---|
| **计划原话** | `docs/2026-10-11-multi-agent-lock-design-v3.md:169`「`lock_acquire` 的 `ttl_sec` 缺省读 store 级配置（`memory/lock-config.json` 或环境变量 `FIST_LOCK_TTL_SEC`），默认 600」 |
| **判定** | **(iii) 计划本身已作废** |
| **证据** | `grep -rn "lock-config\|FIST_LOCK_TTL_SEC" --include=*.mbt src/` → **空**<br>`grep -n '"lock_acquire"' src/server/server.mbt` → **5187**（工具存在，TTL 走 schema 参数）<br>⇒ 配置文件这一形态**未采纳**；TTL 由调用方参数直接给，不需要外部配置 |
| **注意** | ⚠️ **Lane E 的理由错了**：它说「`memory/` 已被 .gitignore」。实测 `.gitignore:90` 注释明写「**逐文件/前缀精确点名，不整目录挡**」，`git check-ignore memory/lock-config.json` **未命中**。作废理由应为「未采纳该形态」而非「目录被忽略」 |

---

### B2 | `src/engine/engine_lock.mbt`

| 项 | 内容 |
|---|---|
| **计划原话** | 设计文档 `:313`「文件：`src/store/store_locks.mbt` + `src/engine/engine_lock.mbt` + `src/server/locks_ops.mbt`」<br>`:353`「`engine_lock.mbt` \| 引擎层锁编排（仿 `engine_rsv.mbt` 纯转发）\| 新文件」 |
| **判定** | **(ii) 已以别的形态实现** |
| **证据** | `git ls-files src/engine/ \| grep -i "assistant\|rsv\|lock"` → `engine_assistant.mbt` / `engine_rsv.mbt`<br>`grep -rn "pub fn.*locks_" src/engine/engine_rsv.mbt` → **6 个**：`FistEngine::locks_upsert`(L70) / `locks_try_acquire`(L82) / `locks_get`(L90) / `locks_list`(L98) / `locks_release`(L103) 等<br>⇒ 引擎层锁编排**就在 `engine_rsv.mbt`**（计划里写的是「仿 `engine_rsv.mbt` 纯转发」—— 实际直接并入了它），未拆独立文件 |

---

### B3 | `src/executor/kill_argv.mbt`

| 项 | 内容 |
|---|---|
| **计划原话** | `:212`「argv 构造文件：`src/executor/kill_argv.mbt`（纯计算零 IO，仿 `cli_argv.mbt` 的 `prompt_ok`/`external_executors` 模式）」<br>`:328`「`src/executor/kill_argv.mbt`（纯计算 argv）+ `src/server/kill_exec.mbt`（spawn）」 |
| **判定** | **(iii) 计划本身已作废** |
| **证据** | `grep -rn "kill_" --include=*.mbt src/ \| grep -i "pub fn\|tool"` → **无 kill 执行实现**<br>现有的是 `src/engine/engine_supervisor.mbt:154` `supervisor_kill_plan`（**只出方案**）与 `:324` `supervisor_kill_apply_pause`（**唯一可逆动作 pause**）<br>`src/server/supervisor_tools.mbt:4` 头注：「`supervisor_kill_plan` … **真 kill 由指挥官按方案人工执行**」<br>⇒ **kill 执行力被明确设计为「不自动化」** ⇒ 计划中的 spawn 形态已作废 |

---

### B4 | `src/server/assistant_ops.mbt`

| 项 | 内容 |
|---|---|
| **计划原话** | `:320`「文件：`src/store/store_assistant.mbt` + `src/engine/engine_assistant.mbt` + `src/server/assistant_ops.mbt`」<br>`:356`「`src/server/assistant_ops.mbt` \| server 助理工具 impl \| 同上（新文件，不改 `server.mbt` 尾部）」 |
| **判定** | **(ii) 已以别的形态实现** ✅（**Lane E 判定相同，我独立复核**）|
| **证据** | `grep -c '"assistant_' src/server/server.mbt` → **6**（含 `assistant_claim`:5392 / `assistant_status`:5449 / `assistant_sweep`:5479 / `assistant_resign`:5519 / `assistant_heartbeat`:5537 = **5 个工具** + 1 处其它引用）<br>`git ls-files src/store/ \| grep -i assistant` → `store_assistant.mbt` + `store_assistant_test.mbt`<br>⇒ 5 个工具**都在 `server.mbt`**，store 层在 `store_assistant.mbt`，未拆 `assistant_ops.mbt` |

---

### B5 | `src/server/kill_exec.mbt`

| 项 | 内容 |
|---|---|
| **计划原话** | `:328`「`src/server/kill_exec.mbt`（spawn）」 |
| **判定** | **(iii) 计划本身已作废** |
| **证据** | 同 B3：`supervisor_kill_plan` 头注明写「真 kill 由指挥官按方案人工执行」；`grep -rn "kill_exec" src/` → 空<br>⇒ spawn 形态未采纳，属**设计决定**（不可逆操作不自动化）|

---

### B6 | `src/server/locks_ops.mbt`

| 项 | 内容 |
|---|---|
| **计划原话** | `:313`「`src/server/locks_ops.mbt`（server 工具）」<br>`:355`「`src/server/locks_ops.mbt` \| server 锁工具 impl（仿 `server.mbt:4334` 范式）\| 新文件，不改 `server.mbt` 尾部」 |
| **判定** | **(ii) 已以别的形态实现** ✅（Lane E 相同，我独立复核）|
| **证据** | `grep -n '"lock_acquire"\|"lock_renew"\|"lock_release"\|"lock_status"' src/server/server.mbt` →<br>**5187** `lock_acquire` / **5244** `lock_renew` / **5299** `lock_release` / **5324** `lock_status`（**4 个工具全在**）<br>⇒ 计划的「新文件、不改 server.mbt 尾部」这一形态未采纳，4 工具直接落在 `server.mbt` |

---

### B7 | `src/store/store_locks.mbt`

| 项 | 内容 |
|---|---|
| **计划原话** | `:313`「`src/store/store_locks.mbt`（双后端 `locks_*`）」<br>`:351`「`src/store/store_locks.mbt` \| 双后端 `locks_*` \| 新文件，不改 `store.mbt`/`store_sqlite.mbt` 主体」 |
| **判定** | **(ii) 已以别的形态实现** ✅（Lane E 相同，我独立复核）|
| **证据** | `grep -rn "pub fn.*locks_" src/store/*.mbt` →<br>`store.mbt:603 locks_upsert` / `:613 locks_try_acquire` / `:624 locks_get` / `:635 locks_list` / `:643 locks_release` / `:655 locks_sweep`<br>`store_rsv.mbt:228 locks_upsert` / `:250 locks_try_acquire` …（MemoryStore 双后端）<br>`store_sqlite.mbt` 亦有 SQL 实现<br>⇒ **双后端 `locks_*` 已实现**，只是并入了 `store.mbt` + `store_rsv.mbt`，未拆 `store_locks.mbt` |

---

### B8 | `templates/lock_wait_loop.md`

| 项 | 内容 |
|---|---|
| **计划原话** | `:341`「`templates/lock_wait_loop.md`：client 侧等待循环模板」 |
| **判定** | **(iii) 计划本身已作废** |
| **证据** | `git ls-files templates/` → **11 份模板，无 `lock_wait_loop.md`**<br>现有模板：`cron_pipeline_meta_prompt.md` / `pipeline_meta_prompt.md` / `pipeline_mode_{advance,bugfind,explore,fix_and_merge,polish,tidy,verify}.md` / `review_meta_prompt.md` / `tool_use_rubric.md`<br>⇒ 等待循环以**工具参数 `ttl_until`** 表达（`lock_acquire` 的 schema 直接收 TTL），不需要独立模板 |

---

### B9 | `memory/lock-config.json`（第二次点名）

| 项 | 内容 |
|---|---|
| **计划原话** | `:379`「TTL 可配置：`lock_acquire(ttl_sec=?)` 缺省读 `FIST_LOCK_TTL_SEC` 环境变量或 `memory/lock-config.json`，默认 600」 |
| **判定** | **(iii) 计划本身已作废** |
| **证据** | 同 B1。补充：`grep -n "ttl" src/server/server.mbt` 的 `lock_acquire` schema 直接收 `ttl_until`（调用方给值），**无需 store 级配置**<br>⚠️ 同 B1，**Lane E 的「memory/ 被 gitignore」理由不成立** |

---

### B10 | `src/core/types.mbt`

| 项 | 内容 |
|---|---|
| **计划原话** | Lane E §5 对照表点名（`src/core/types.mbt`）|
| **判定** | **(ii) 已以别的形态实现** |
| **证据** | `git ls-files src/core/` → `core_principle.mbt` / `core_role.mbt` / `core_task.mbt` + 3 个 wbtest + `moon.pkg` + `pkg.generated.mbti`，**无 `types.mbt`**<br>`grep -q "pub struct Task" src/core/core_task.mbt` → **命中**<br>⇒ 类型**按领域分文件**（Task→`core_task.mbt` / Role→`core_role.mbt` / Principle→`core_principle.mbt`），未采纳单文件 `types.mbt` 形态 |

---

### B11 | `src/engine/engine_worktree.mbt` 🚨

| 项 | 内容 |
|---|---|
| **计划原话** | `docs/plan-light-worktree-isolation.md:74`「引擎层转发 \| `engine_rsv.mbt` 纯转发范式 \| **`engine_worktree.mbt` 照搬**」<br>`:153`「新建 `src/engine/engine_worktree.mbt` + `src/store/store_worktree.mbt`（双后端同构，照 `store_rsv` 范式）」 |
| **判定** | **(i) 真未落地** |
| **证据** | `git ls-files -- src/engine/engine_worktree.mbt` → **0**；`[ -e ]` → **no**<br>`grep -rln "worktree" --include=*.mbt src/` → **仅 `src/engine/engine_execute_r2_test.mbt`**（测试夹具提到，非实现）<br>⇒ **`src/` 内零 worktree 管理代码** |

---

### B12 | `src/store/store_worktree.mbt` 🚨

| 项 | 内容 |
|---|---|
| **计划原话** | 同上 `:153`「新建 … + `src/store/store_worktree.mbt`（双后端同构）」 |
| **判定** | **(i) 真未落地** |
| **证据** | `git ls-files -- src/store/store_worktree.mbt` → **0**；`[ -e ]` → **no**<br>`grep -rln "worktree" --include=*.mbt src/store/` → **空**<br>⇒ store 层零 worktree 持久化 |

---

### B13 | `templates/worktree_wait_loop.md`

| 项 | 内容 |
|---|---|
| **计划原话** | `docs/plan-light-worktree-isolation.md:196`「`templates/worktree_wait_loop.md`：client 侧等待/换单模板」 |
| **判定** | **(ii) 已以别的形式实现** ⚠️**与 Lane E 不同** |
| **证据** | `git ls-files templates/` → 无该文件（原判定面正确）<br>**但能力面已实现**：`scripts/run_light_wt.py` 的 `create` / `teardown` / `status` 三子命令 + `--ttl-min` 参数（见本会话 task-27 实测：`run_light_wt.py create --repo . --task <id>` 可正常创建/回收）<br>⇒ 「client 侧等待/换单」的**能力**在脚本层，不需要 md 模板 |

---

### B14 | `src/ops/ops_folder_watch.mbt`

| 项 | 内容 |
|---|---|
| **计划原话** | Lane E §5 对照表点名（`src/ops/ops_folder_watch.mbt`）|
| **判定** | **(iii) 计划本身已作废** |
| **证据** | `grep -rn "folder_watch" --include=*.mbt src/` → **空**<br>⇒ 提案未获批，无等价实现；Lane E 判「提案未获批」，我复核**确无任何实现痕迹** |

---

### B15 | `src/ops/ops_pipeline_tick.mbt`

| 项 | 内容 |
|---|---|
| **计划原话** | Lane E §5 对照表点名（`src/ops/ops_pipeline_tick.mbt`）|
| **判定** | **(ii) 已以别的形态实现** |
| **证据** | `grep -rn "pipeline_tick" --include=*.mbt src/ \| grep -i "pub fn\|\"pipeline_tick\""` →<br>`src/ops/ops_pipeline.mbt:287` **`pub fn pipeline_tick(`**<br>`src/server/server.mbt:3088` **`"pipeline_tick"`**（工具注册）<br>⇒ 实现**就在 `ops_pipeline.mbt`**（`ops_` 前缀已采纳，但**未按功能拆 `ops_pipeline_tick.mbt`**）|

---

### B16 | `src/server/supervisor_tools_test.mbt` 🚨

| 项 | 内容 |
|---|---|
| **计划原话** | `docs/2026-10-12-fist-mbt-supervisor-tools-plan.md` 点名 `src/server/supervisor_tools_test.mbt` |
| **判定** | **(ii) 已以别的形态实现** ⚠️**与 Lane E 相反（Lane E 判「落地/测试文件确缺」）** |
| **证据** | `git ls-files src/server/ \| grep -i supervisor` → `supervisor_tools.mbt` + **`supervisor_tools_wbtest.mbt`**<br>`grep -c "^test " src/server/supervisor_tools_wbtest.mbt` → **9 个 test**<br>`grep -o 'supervisor_[a-z_]*' …wbtest.mbt \| sort -u` → 覆盖 **8 个工具全**（status / task_tree / task_upsert / kill_plan / prompt_inject / prompt_list / prompt_consume / reminder_tick）+ 若干内部函数<br>**实测运行**：`python scripts/moon_test_env.py --target js src/server` → **Total tests 387 / passed 387 / failed 0** ✅<br>⇒ **测试不缺**，只是命名 **`_wbtest.mbt`（白盒）而非 `_test.mbt`（黑盒）**。这是本仓既有惯例（`supervisor_tools` 内部函数多，白盒才能测） |

---

### B17 | `src/server/mcp_config_scaffold_impl.mbt`

| 项 | 内容 |
|---|---|
| **计划原话** | `docs/fist-config-skill.md` 点名该文件 |
| **判定** | **(ii) 已以别的形态实现** ✅（Lane E 相同，我独立复核）|
| **证据** | `grep -rln "mcp_config_scaffold" --include=*.mbt src/` → `src/server/mcp_config_scaffold.mbt` + `mcp_config_scaffold_wbtest.mbt` + `src/server/server.mbt` + `src/hat/hat_config.mbt`(引用) + `issue_scan_test.mbt`(测试)<br>⇒ **实现在 `mcp_config_scaffold.mbt`**（不带 `_impl` 后缀），`server.mbt` 注册工具 |

---

### B18 | `src/lib/fist_ops.mbt`

| 项 | 内容 |
|---|---|
| **计划原话** | `docs/mcpcf-embed-skill.md` 点名 `src/lib/fist_ops.mbt` |
| **判定** | **(ii) 已以别的形态实现** ✅（Lane E 相同，我独立复核）|
| **证据** | `[ -d src/lib ]` → **否**（`src/lib/` 目录不存在）<br>但 `git ls-files src/server/ \| grep -i mcpcf` → **`src/server/mcpcf_embed.mbt`**<br>⇒ mcpcf 7 工具全在 `mcpcf_embed.mbt`，未采纳 `src/lib/` 这一目录结构 |

---

### B19 | `templates/pipeline_mode_loop.md`

| 项 | 内容 |
|---|---|
| **计划原话** | `docs/SHIP-PLAN-BLACKBOX-v2.md` 点名 `templates/pipeline_mode_loop.md` |
| **判定** | **(ii) 已以别的形态实现** ✅（Lane E 相同，我独立复核）|
| **证据** | `git ls-files templates/ \| grep pipeline_mode` → **7 份**（advance / bugfind / explore / fix_and_merge / polish / tidy / verify），**无 `loop` 变体**<br>`grep -n "mode_template_path\|PipelineMode" src/ops/ops_modes.mbt` → 7 种模式的真源<br>⇒ `loop` 变体未采纳；「组合环」能力在 `src/ops/ops_loop.mbt`（`loop_create/loop_tick/loop_status` 3 工具）|

---

### B20 | `src/server/model_router_caf_ops.mbt`

| 项 | 内容 |
|---|---|
| **计划原话** | `docs/2026-10-15-fist-mbt-caf-p2d-cold-start-design.md` 点名该文件 |
| **判定** | **(ii) 已以别的形态实现** ✅（Lane E 相同，我独立复核）|
| **证据** | `git ls-files src/router/ \| grep -i caf` → **5 份**（`model_router_caf.mbt` / `model_router_caf_wbtest.mbt` / `router_caf.mbt` / `router_caf_bug188_wbtest.mbt` / `router_caf_cost_decides_test.mbt`）<br>`git ls-files src/server/ \| grep "caf_ops\|model_router_ops"` → **`model_router_ops.mbt`**（无 `caf_ops`）<br>⇒ CAF 实现在 `src/router/` 的 5 个文件 + `model_router_ops.mbt`，未采纳 `model_router_caf_ops.mbt` |

---

### B21 | `docs/polish-plan-point-A`

| 项 | 内容 |
|---|---|
| **计划原话** | `docs/2026-10-20-slave-dev-playbook.md:82`「\| **文档** \| `docs/` \| **`docs/polish-plan-point-A`** \| 纯文档改动（README、AGENTS、docs/）\|」 |
| **判定** | **(ii) 已以别的形态实现**（**路径漂移**，非缺失）|
| **证据** | `git ls-files docs/ \| grep -i "slave\|polish"` → `2026-10-20-slave-dev-playbook.md` / **`2026-10-20-slave-tasks.md`** / `polish-plan.md`<br>**`grep -n "Slice 7" docs/2026-10-20-slave-tasks.md` → `95:## Slice 7 · Polish Plan（打磨冲刺）`** ✅<br>⇒ 计划里写的是**分支名**（`polish-plan-point-A`），实际落点是 `slave-tasks.md` 的 **Slice 7**。**这是路径引用错误，不是缺失** |

---

## 三、分析：如果 (i) 真要做，工作量多大

只有 **B11 + B12** 两条真未落地，且它们是**一体两面**（引擎层 + store 层）。

### 现状

```
src/ 内 worktree 管理代码：0 行
仅 src/engine/engine_execute_r2_test.mbt 提到 worktree（测试夹具）
但 scripts/run_light_wt.py 已有完整实现（create/teardown/status + TTL）
```

### 工作量估算

| 任务 | 参照物 | 估量 |
|---|---|---|
| `src/store/store_worktree.mbt`（双后端） | 仿 `store_rsv.mbt`（228+ 行，含 MemoryStore 与 SqliteStore 两套 `locks_*`）| **中**：约 150~250 行 + 双后端一致性测试 |
| `src/engine/engine_worktree.mbt`（引擎转发）| 仿 `engine_rsv.mbt` 的 `locks_*` 纯转发（6 个函数 ≈ 60 行）| **小**：约 60~80 行 + 转发正确性测试 |
| store 层新增表（若需要持久化）| 参照 `file_locks` 表 DDL | **小**：1 张表 + `check_store_tables_wired` 需同批给写入点 |
| 与 `scripts/run_light_wt.py` 的职责划分 | —— | **需设计决策**：脚本层已有完整实现，MCP 层再实现会不会双轨？|

### 🔴 关键判断（必须提请统帅注意）

**B11/B12 的「真未落地」可能不是缺陷，而是「架构选择」：**

- `scripts/run_light_wt.py` **已提供完整的 worktree 生命周期**（`create`/`teardown`/`status` + `--ttl-min` + manifest 记账），且本会话 task-27 实测可用
- 把这套能力**再实现一遍到 `src/` 内**（store + engine + MCP 工具）会产生**双轨**
- 计划（`plan-light-worktree-isolation.md`）写于更早，当时脚本层可能还没有

**⇒ 建议：B11/B12 不应直接判「排期开发」，而应先回答一个设计问题：**
> **「worktree 管理应该住在 `scripts/` 还是 `src/`？」**
> 若答案是 `scripts/`（现状）⇒ **B11/B12 应改判 (iii) 作废**（计划的分层设想被脚本期取代）
> 若答案是 `src/`（MCP 工具面）⇒ **B11/B12 确应排期**

**我无法单方面回答这个问题** —— 它涉及架构取向，超出「读代码给证据」的范围。**列入 §五 请统帅裁决。**

### ✅ 关于 B11/B12 的改判（2026-10-26 · 统帅裁决）

**统帅采纳了上述推理，裁决 B11/B12 改判 (iii) 作废。** 裁决理由（原文）：

> 1. `scripts/run_light_wt.py` 已提供 `create` / `teardown` / `status` + `--ttl-min` + manifest 记账，
>    **你实测过 `create --repo . --task <id>` 正常创建/回收**
> 2. 计划 `plan-light-worktree-isolation.md` 写在**脚本层成熟之前**，所以列了 `src/` 分层
>    —— 那是当时的信息条件下的设想
> 3. **现在再在 `src/` 实现一遍 = 双轨制**，两个入口管同一批 worktree，
>    且 `src/` 那套还要与脚本层的 manifest 记账对账 —— **这是造 bug 不是补功能**

**⇒ 21 条全部作废。但「作废」不等于「永久关闭」——见 §六。**

---

## 四、缺口与风险

### 4.1 我修正了 Lane E 的三处判定（都有实测）

| # | Lane E | 我 | 依据 |
|---|---|---|---|
| **B16** | 「落地」（测试确缺）| **(ii) 已实现** | `supervisor_tools_wbtest.mbt` 9 test / 8 工具全覆盖 / **387-387 全绿实测** |
| **B13** | 标作废 | **(ii) 已实现** | `run_light_wt.py` 已有 create/teardown/status 能力面 |
| **B1/B9 理由** | 「`memory/` 已被 .gitignore」| **理由错误** | `.gitignore:90` 明写「逐文件/前缀精确点名，不整目录挡」；`check-ignore` 未命中 |

**⇒ 建议：Lane E 报告（`d5a84c76`）的这三处应更正，或至少标注我的修正。**

### 4.2 本次裁决的证据边界

| 项 | 说明 |
|---|---|
| **只验了「点名路径不存在」+「能力在何处」** | **未验「能力是否完整覆盖计划设想的全部场景」**——例如 lock 的 TTL 语义是否与计划一致，我只确认了工具存在 |
| **未读计划全文** | 只 grep 了点名行；计划里可能还有别的约束（如双后端语义一致性要求）未纳入判断 |
| **B21 的判定依赖「Slice 7 就是 point-A」** | 我根据命名与内容推断，**未逐字比对** `polish-plan-point-A` 分支的实际内容（若该分支曾存在）|

### 4.3 最大的风险：(i) 那两条可能是伪缺口

见 §三 末段。**如果 B11/B12 实际是「架构选择」而非「遗漏」，把它们排期开发会造出双轨制。**
**这是本次报告最需要统帅注意的一条。**

---

## 五、建议入档位置 + 请统帅批准的分档

### 建议分档（请裁决）

#### 组 1：确认作废（13 条，(ii)）— **建议直接标作废**

```
B2  B4  B6  B7  B10  B13  B15  B16  B17  B18  B19  B20  B21
```
**共同模式：计划的设计级模块划分（拆文件/拆目录）未被执行，但能力已实现在别处。**

#### 组 2：确认作废（6 条，(iii)）— **建议直接标作废**

```
B1  B3  B5  B8  B9  B14
```
**共同模式：计划里的形态被后续设计决定放弃（kill 不自动化 / 配置走参数 / 模板走脚本）。**

#### 组 3：待裁决（2 条，(i)）— **建议先答架构问题，再决定排期或作废**

```
B11  src/engine/engine_worktree.mbt
B12  src/store/store_worktree.mbt
```
**问题：「worktree 管理住 `scripts/` 还是 `src/`？」**
- 答 `scripts/` ⇒ 改判 (iii) 作废，**21 条全作废**
- 答 `src/` ⇒ 确应排期，工作量估 **中**（250~330 行 + 双后端测试 + 与脚本层职责划分）

### 入档建议

1. **本报告** → `reports/2026-10-26-plan-landing-b-class-verdict.md`
2. **B 类作废结论** → 建议在 Lane E 报告 `d5a84c76` 上追加「裁决」节，指向本报告
3. **三处修正（B16/B13/B1-B9 理由）** → 同批更正 `d5a84c76`
4. **B11/B12 的架构问题** → 建议立一条独立决策单，不要混在「排期」里

---

## 六、🔄 重新评估的触发条件（**不是永久关闭**）

**B11/B12 判作废的依据是「当前没有需要 src/ 层 worktree 管理的真实需求」——
不是「这件事永远不该做」。**

若将来出现下列需求，**B11/B12 的性质会从「补旧计划」变成「新增需求」**，
届时应**重开新单**，而不是翻这份报告说「当初判错了」。

### 6.1 触发条件（统帅原话，逐字保留）

> **「MCP 客户端（AI）需要在 `claim` 时自动创建 worktree 沙箱，
> 而不是由人或 CI 脚本先手动 create。」**

### 6.2 为什么这一句构成真实的区别

| 驱动方式 | 现状 | 能力住在哪 |
|---|---|---|
| **人 / CI 驱动** | 已实现 | `scripts/run_light_wt.py`（`create`/`teardown`/`status` + `--ttl-min` + manifest）|
| **任务调度驱动**（MCP 面） | **未实现** | —— |

**这两者确实不同：**
- 现状是「**先建沙箱，再在沙箱里干活**」—— 沙箱是**前置条件**
- 触发条件描述的是「**claim 的那一刻自动分配沙箱**」—— 沙箱是**调度产物**

后者需要 `src/` 内能感知「任务生命周期」，而 `scripts/` 无此上下文。

### 6.3 当前的判断：没需求就不造

**当前没有真实需求** —— 没有哪个 lane 报过「claim 后要自动隔离」。
**⇒ 没需求就不造。**
**⇒ 若将来真的出现，那不是「B11/B12 复活」，是「新增一条需求」，配一份新的设计。**
