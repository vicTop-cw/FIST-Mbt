# BUG-421 + BUG-422 authz 残留收口 · 报告

> 执行：subagent 46a5eb98（Lane AD）+ 指挥官终审
> 时间：2026-10-27 02:15 – 03:25
> commit：`eecf05f7`（9 文件 +700/−134）

## 一、结果摘要

| 项 | 结果 |
|---|---|
| **BUG-421**（整名 `leader`/`lead` 提权面） | ✅ **白名单已删** —— 只剩 `human_steward`/`human` ⇒ HumanSteward，其余一律 Executor |
| **BUG-422**（查表键=自报名字） | ✅ **B 案三层落地** —— 取数侧剔除本进程自身份 + 接线侧单一取数 + 政策侧下限语义 |
| **两条必须同笔** | ✅ R7 报告警告「单独修 421 是白修」，同笔即消解 |
| 实测矩阵 | **修前** `leader`/`fist-mbt` 在 4 类 scope 全 ALLOWED → **修后 20/20 DENIED** |
| 测试 | engine **243/243**（基线 240）｜store **85/85** ｜ claimguard 57/57 ｜ ops 208/208 |
| 编译 | `moon check --target js` = **0 errors** |

## 二、BUG-422 为什么选 B 案

| 方案 | 为什么不选 |
|---|---|
| **A 案**（可信身份） | `agents.pubkey_fp` **全仓恒空**（BUG-403/404 的死承诺）⇒ **没有可信身份源**，做不出来 |
| **C 案**（彻底不用 declared） | 会把「服务端登记过的执行者拿到被授予角色」这条**唯一正道**一起关死，而收益为 **0** —— 现网唯一 Leader 记录恰好就是要挡的 **server 自身份**；挡掉它即可，不必废掉机制 |
| **B 案**（三层） | ✅ 采纳 |

### B 案三层

| 层 | 落点 | 作用 |
|---|---|---|
| **取数侧**（store） | `agent_record_is_process_self(rec)` = `agent_type.to_lower()=="server"`<br>+ `SqliteStore::agents_role_for_judgment(agent_id)` | 查表但把**本进程自身份整条剔除**（返回 `None`）⇒ `server.mbt:16-18` 写的 `fist-mbt/server/Leader` **彻底退出角色裁决** |
| **接线侧**（engine） | `declared_role_for_judgment(eng, agent)`；`rsv_set` / `rsv_try_set` / `locks_try_acquire` **三条门全改走它** | 旧实现三处**各抄一遍** `.agents_get(...).role` ⇒ **改一处漏两处就是半个越权口** |
| **政策侧**（纯函数） | `role_rank` + `inheritable_role`（只允许 `Executor`/`Leader` 继承，**HumanSteward 与未知值永不继承**）<br>+ `resolve_agent_role` 改**下限语义** | `inferred` 是**地板**，declared 不能降级（`human_steward` 不被 Executor 记录压回），且只有 ≥ 推断时才生效 |

**为什么「剔 server 自身份」是结构性判据**：它看的是**登记来源**（`agent_type`），**不看名字** ⇒
server 改名也照样挡住。这比「维护一个名字黑名单」稳。

## 三、变异对照（4 组，每次 `assert count(old)==1` 锁唯一上下文 —— 判例-30）

| 变异 | 读数 |
|---|---|
| **M1** 把 `leader/lead → Leader` 塞回 else 分支 | engine **237/243（6 红）**：`lock_perm_wb2_leader_name_denied_on_engine`、`scope_role_wb1/wb6/wb7`、`role_resolve_wb1/wb3`；恢复 ⇒ **243/243** |
| **M2** 删 store 的 self-identity 过滤 | engine 242/243 红=`scope_role_wb8`@:490（裁决取数面）；store 79/80 红=`bug422_agents_role_for_judgment_filters_process_self` |
| **M2b** 机制保留、engine 接线退回未过滤的 `agents_get`（**判例-29**） | engine 242/243 红=`scope_role_wb8`@:502（**端到端**那条）⇒ **端到端锁真在看接线，不是只测机制** |
| **M3** `inheritable_role` 放回 `"HumanSteward" => Some(...)` | engine 241/243 红=`scope_role_wb8`@:571 + `role_resolve_wb2`@:79 |

**M2b 是本笔最有价值的一格**：它证明「机制格 ≠ 实现路径格」的补锁真的在起作用 ——
若只锁 store 的纯函数，接线被改成未过滤版本时测试仍会全绿。

## 四、实测矩阵（临时探针复刻 server 启动注册，跑完即删）

**修前**（逐字复现账本原读数）：
```
try_set agent=leader   src/engine/ src/core/ src/router/ cmd/  => 全 ALLOWED
try_set agent=fist-mbt src/engine/ src/core/ src/router/ cmd/  => 全 ALLOWED
rsv_set  agent=leader   src/engine/... => ALLOWED reserved [role_source=inferred]
rsv_set  agent=fist-mbt src/engine/... => ALLOWED reserved [role_source=declared]   ← 本尊
```
**修后**（同一探针、同一库、同一入参）：
```
try_set agent=leader/lead/LEADER/fist-mbt × 5 scope          => 20/20 DENIED
rsv_set  agent=leader/lead/LEADER/fist-mbt src/engine/...    => DENIED
try_set agent=human_steward × 5 scope                        => ALLOWED(reserved+role_inferred)
```

**现网库读数（只读 `fist-mbt.db`）**：`agents` 3 行，唯一 Leader 是 `agent_type=server`（= `fp("fist-mbt")`），
**无任何非 server 的 Leader 记录、无任何 HumanSteward 记录** ⇒ 过滤后现网「可继承面」= **0 条**。

## 五、会不会破坏现有调用方（全仓 grep + 库实测）

1. **生产代码 0 处依赖**：`src/` 无任何调用点以 `agent="leader"`/`"lead"` 调 `reserve_scope`/`lock_acquire`；
   `check_scope_permission` / `resolve_agent_role` 的调用方只有 `engine_rsv.mbt` 三处（已全改走单一取数）。
2. **`by="leader"` 的 13 处 `scripts/*.py` 不是授权面**：它们传的是 `plan`/`task_plan_deep` 的 **`by`（拆解拳长标签）**，
   `engine.mbt:96` 只当记录/透传，**不参与** `check_scope_permission`。
3. **`call_log` 入参面实测 —— 纠正了 R7 报告的口径**：R7 按 `caller` 列看说「0 调用方」，
   但按**入参**看，`agent` 恰为 `leader` 的真实 `reserve/lock` 调用有 **3 条**（全在 2026-10-11，`ok=1`）：
   - `seq=25` `reserve_scope agent=leader scope="src/ops"`（未登记规则 ⇒ advisory，**不依赖白名单**）
   - `seq=219` `reserve_scope agent=leader scope="src/router/model_router_wbtest.mbt"`（Leader 保护面 ⇒ **确实吃过白名单**）
   - `seq=255` `reserve_release` 同上
   **近 16 天 0 条、流水线 0 条 ⇒ 不破坏现有调用方**，未触发「停下来」条件。
4. **真实代价（已被 owner 记账）**：新的军官 lane **没有自助拿 Leader 的路** ——
   `agents_register` 未暴露成 MCP 工具，只能人介入写表，或先加工具面。

## 六、缺口与风险（**别读成「已全部收口」**）

**已封**：
1. 任何 `agent_type=="server"` 记录（**结构性**判据 ⇒ server 改名也挡）
2. declared 里的 HumanSteward（`inheritable_role` **永不继承**）
3. 军官单词 `leader`/`lead`/`LEADER`（含大小写变体）

**仍可被冒用（现网 0 条）**：
4. **非 server 类型 + 被显式授予 Leader** 的登记名 —— 制造它需要**内部写入面**（MCP 面无 `agents_register`）；
   彻底收口只能靠认证身份（A 案）或彻底不用 declared（C 案）
5. `locks_upsert`（底层原语）仍是裸通道（BUG-424 已标注，本笔未动）

**相邻未修（已另立案 BUG-432）**：
6. `src/engine/engine.mbt:1770 estimate_rank` 是**另一条**「名字判军衔」的路
   （`assignee.has_prefix("leader")` ⇒ 连长 6），被 `claim` 的 **RANK_GATE** 直接用于**放行/拒绝认领**
   —— 与 `reserve_scope` 角色门是**两条独立的路**，BUG-418/421/422 **三轮收口全部漏掉它**。
   建议先只读诊断「RANK_GATE 拿 estimate_rank 结果做什么」再修。

**语义收紧须知**：
7. `role_resolve_wb2` 已改判（declared=HumanSteward 现在**不生效**、退推断）—— 这是 BUG-422 的**加固不是回归**，
   现网 0 条 HS 记录 ⇒ 零现实影响
8. 未知角色值从「照抄」变「忽略」（更严）

## 七、资源消耗

| 项 | 数值 |
|---|---|
| 改动 | 9 文件 +700/−134（含 2 份自动同步的 `pkg.generated.mbti`） |
| 测试增量 | engine +3（240 → 243）、store +1（79 → 80，终审时因并发 lane 又到 85） |
| 变异对照 | 4 组（含 1 格判例-29 端到端接线格） |
| 诊断探针 | 1 组（临时，跑完即删） |

## 八、任务分配记录

- **subagent 46a5eb98** 独立完成两条 + 4 组变异 + 矩阵实测 + 调用方影响分析
- **指挥官**：终审（实跑 243/243、85/85、claimguard/ops 抽验）、提交、记账、新立 BUG-432
- **并发面**：期间 `store_rsv_test.mbt` 有别的 lane 的 WIP 导致**瞬时 11 errors**（编译挡提交），
  重跑即自愈（作者在写）；`r10_equiv_probe_test.mbt`（未跟踪临时探针）曾挡全仓门禁，已移到 `temp/relocated/`

## 九、后续建议

1. **BUG-432** 先只读诊断 RANK_GATE 的实际用法，再按「role → rank」重写 `estimate_rank`（② 中期方案）
2. **同族收口纪律**：本笔再次印证「同一语义散落多处，只改被点名的那一处就是半个口子」——
   建议在 `AGENTS.md` 补一条：**安全收口必须 grep 全仓取数点**（`agents_get(...).role` 的同类调用）
3. **`AI-DEVELOPMENT-STANDARD.md` 已知边界**可补一行：身份自报 = 已知边界；Leader 只来自 `agents.role` 登记，
   且**无自助登记工具面**

## 十、来源

- 回传：subagent 46a5eb98 五段式（含 4 组变异表 + 修前/修后矩阵 + call_log 入参面复核）
- commit：`eecf05f7`
- 测试读数：`moon test --target js src/engine` = 243/243；`src/store` = 85/85
- 账本：BUG-421/422 一笔两条标 FIXED；新立 BUG-432