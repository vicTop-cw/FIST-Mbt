# BUG-418 角色推断收窄 · 收回与验证报告

> 执行：Lane Q（subagent 91b19655）诊断+验证 / 并发 lane 落地修法 / 指挥官终审
> 时间：2026-10-26 21:20 – 22:20
> commits：`ed8dffdf`（修法，并发 lane）/ `bb892db1`（端到端锁 6 格）/ `3e8033aa`（账本）

## 一、结果摘要

| 项 | 结果 |
|---|---|
| **BUG-418 是否成立** | ✅ 成立（修前复现：`lane-b-leader` ⇒ Leader、`not-a-commander` ⇒ HumanSteward，可直接预订 `src/engine/`、`src/store/store_sqlite.mbt`） |
| **核心攻击面（子串匹配）** | ✅ **已关闭**：子串/前缀/大小写变体全部塌回 Executor（实测 `lane-b-leader` / `leader-foo` / `polish-lane` / `commander-in-chief` / `not-a-commander` 全 Err） |
| **回归锁** | ✅ 两套互补：`engine_role_resolve_wbtest.mbt`（4 格，纯函数）+ `engine_scope_perm_role_wbtest.mbt`（6 格，端到端走 `rsv_try_set`） |
| **测试** | `moon test src/engine` = **229/229 passed, 0 failed**（修前同批锁 = 226/229，3 failed） |
| **编译** | `moon check --target js` = **0 errors** |
| **残留** | ⚠️ **4 条**，已新立 BUG-421~424（详见 §四） |

## 二、修法（并发 lane 落地）

**修前**（`git show a9b010e3:src/engine/engine_scope_perm.mbt` 逐字）：

```moonbit
if a.contains("commander") || a.contains("human_steward") || a == "human" { "HumanSteward" }
else if a.contains("leader") || a.contains("lead") || a.contains("polish") || a.contains("optimization") { "Leader" }
else { "Executor" }
```

`engine_rsv.mbt` 两个调用点（`rsv_set` / `rsv_try_set`）拿返回值**直接决定** `RoleDenied` 还是放行 ⇒ **名字=通行证**。

**修后**（`ed8dffdf`）：
1. `infer_role_from_agent` 改**整名精确匹配**（消灭子串）
2. 新增 `agent_fp_of()` / `resolve_agent_role(name, declared)`
3. `rsv_*` 先 `agents_get(agent_fp_of(agent))` 取 `agents.role`（**declared 优先、推断兜底**）

## 三、为什么端到端锁不可省（判例-29 实证）

已提交的 4 格测的是 `infer_role_from_agent` / `resolve_agent_role` / `agent_fp_of` 三个**纯函数**。

而「角色结果有没有真的进 `match check_scope_permission`」、「declared 查询有没有真的接上 `agents_get(agent_fp_of(...))`」都在 `engine_rsv` 里 —— **纯函数全绿 + 接线被改成 `let role = "Executor"` 也能过**。

本笔补的 6 格全走 `FistEngine::rsv_try_set`（`reserve_scope` 真实调用路径）：

| 格 | 覆盖 |
|---|---|
| `wb1` | 12 个子串/前缀名 → 全 Executor |
| `wb2` | 整名 `human_steward`/`human`/`HUMAN_STEWARD` → HumanSteward |
| `wb3` | **端到端** 5 组名字打 5 类 scope → 全 Err |
| `wb4` | 端到端 `human_steward` 订同样 scope → 全 Ok（合法路径不退化） |
| `wb5` | 端到端 A 案权威面：登记 Leader 放行 / 同族未登记拒绝 / 登记 Leader 仍进不了 HumanSteward 面 |
| `wb6` | 变异对照（旧规则提权 vs 新实现 fail-closed）+ **函数体扫描**（体内无 `.contains(`，只扫函数体避开注释字面量 —— 判例-30） |

## 四、遗留风险：4 条残留（已新立，不塞进 BUG-418）

| 编号 | 严重度 | 内容 | 实测 |
|---|---|---|---|
| **BUG-421** | medium | 整名 `leader`/`lead` 仍买到 Leader 军官面 | `ALLOWED agent=leader src/engine/*` · `DENIED agent=leader-x`（子串已失效 ✅） |
| **BUG-422** | medium | A 案查表键仍是**自报名字**，报已登记身份名即继承其角色 | `ALLOWED agent=fist-mbt src/engine/*`（命中 `server.mbt:16-18` 的 `role="Leader"`） |
| **BUG-423** | **high** | `claim`/`execute` 写 `role="Executor"` 且 `ON CONFLICT` 不更新 ⇒ 统帅被毒化后永久锁死 | `DENIED agent=human_steward scope=store_sqlite.mbt` |
| **BUG-424** | **high** | `lock_acquire`/`lock_renew` 完全无权限门 | `engine_rsv.mbt:108-109` 注释自述「暂时没接」 |

**为什么拆开而不是塞进 BUG-418**：四条性质不同、修法不同（政策裁决 / 需 MCP 面身份核验 / schema 语义 / 接线），按「一单一改法」拆，比让它们藏在 FIXED 抬头后面更符合记账规则。

## 五、资源消耗

| 项 | 数值 |
|---|---|
| 提交 | 3 笔（修法 1 + 锁 1 + 账本 1） |
| 代码 | 修法 +90 行 / 端到端锁 +333 行 |
| 测试增量 | +10 格（4 纯函数 + 6 端到端），engine 219 → 229 |
| 诊断探针 | 2 组（临时，取证后已删，未入库） |

## 六、任务分配记录（并发 lane 撞车事实）

**撞车**：Lane Q（本单）与另一并发 lane 在**同一批文件**上各自实现修法。对方先落地并提交（`ed8dffdf`，21:46:46）。

**处置**：Lane Q **不重复改实现**（避免 lost-update），转为「独立验证 + 补它没测的一半 + 找残留」。这是并发环境下的正确姿势 —— 重写实现会导致两份改动互相覆盖，而验证+补锁是净增益。

## 七、后续建议

**优先级排序**（按「能被主动利用」的程度）：
1. **BUG-423（high，功能性雷）** —— 统帅被毒化后永久锁死，影响面最直接。建议 A 案（`max(declared, inferred)` 白名单当下限）
2. **BUG-424（high，拒绝服务）** —— `lock_*` 接角色门（注意 `lock_release` 语义特殊：只校验持有者，不过角色门）
3. **BUG-421（medium，政策裁决）** —— 关掉 `leader`/`lead` 整名白名单需 owner 确认「现有调用方是否依赖自报 leader」
4. **BUG-422（medium，需跨模块）** —— A 案完整路径：MCP 面加已核验身份（会话令牌 / `agents.pubkey_fp` 签名，该列已存在但全仓恒空 —— BUG-403/404 的死承诺）

**A 案完整路径**（要真收口必须走）：
① MCP 面给 `reserve_scope`/`lock_*` 增加已核验身份 → ② 角色只从已验证身份对应行读、名字降级为显示字段 → ③ store 侧区分「身份首登」与「低权覆盖 role」→ ④ 整体删除 `infer_role_from_agent`，锁改成「名字完全不参与裁决」

## 八、超额内容

1. **发现并发 lane 撞车并避免 lost-update**（没说"我也改了"，而是转为验证+补锁）
2. **端到端锁 6 格**（对方 4 格只测纯函数，接线零覆盖）
3. **挖出 4 条残留**（修法本身新增了 1 条：BUG-422 的「按名字继承角色」是修前没有的面）
4. **`check_fmt_gate.py` = DEGRADED(2)** 的处置：Lane Q 主动**没跑** `moon fmt`（会重排并发 lane 的文件），新文件按仓内风格手写 —— 这是并发环境下的正确克制

## 九、来源

- 修法：commit `ed8dffdf`（并发 lane）
- 端到端锁：commit `bb892db1`（本会话）
- 账本：commit `3e8033aa`
- 测试读数：`python scripts/moon_test_env.py src/engine` → `Total tests: 229, passed: 229, failed: 0`
- 修前对照：同一批锁、未改实现时 = `229 / 226 passed / 3 failed`
- Lane Q 原始回传：本会话 subagent `91b19655` 的五段式（含逐字修前代码、可执行复现、残留实测）
