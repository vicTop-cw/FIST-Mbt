# T0r53 收口报告：fist_longrun_checkpoint / resume 实现核实与收口（2026-11-28）

> **任务**：池任务 T0r53（namespace=autoplan，原状态「已暂停」——停摆真因为 11-25 额度耗尽）。
> 核实 `fist_longrun_checkpoint` / `fist_longrun_resume` 实现完成度，缺口 200 行内当场补齐，收口后 execute→submit。
> **执行**：workbuddy（2026-11-28）。
> **验收面**：`moon check` / `moon test --target js`（`scripts/moon_test_env.py` 常驻入口）/ e2e 实测链（`temp/t0r53-e2e/run_e2e.py`）。

## 1. 结论

1. **T0r53 P0（checkpoint/resume 最小闭环）实现完成度 = 100%**：工具注册、快照写入/恢复、字段 schema 对齐、幂等键防重放四方面全部在位，无半实现点。
2. **唯一真缺口 G1 已当场补齐**：longrun 四列（checkpoint_path/last_baton/budget_used/idempotency_keys）此前**没有任何 sqlite 层写读往返锁**（R191 全字段往返锁恰好漏这四列——它们在 `Task::new` 里默认全空）⇒ 若 INSERT/UPDATE 绑定位错位会静默落默认值而不红（R148 同类事故形状）。补 2 格行为锁（+110 行 < 200 行），create/update 两条绑定路径各一格。
3. **验证全绿**：`moon check` 0 errors；`moon test --target js` 全量 **2130/2130**（改动落盘后复跑）；e2e 真工具调用链 **18/18 格全绿**（publish→claim→checkpoint→pause→resume→断言状态恢复→快照落盘→负例→幂等重入）。
4. G2（`fist_longrun_baton` 工具未注册）属 T0r58（P1）范围，本轮不动手，列为待办。

## 2. 实现核实表

| 方面 | 结论 | 证据（文件:行） |
|---|---|---|
| ① 工具注册 | ✅ 三件注册可调用 | `src/server/server.mbt:3603` `fist_longrun_checkpoint` / `:3654` `fist_longrun_resume` / `:3693` `fist_longrun_guard`（T0r56 P1 附带）；各带 inputSchema + `agent_write_gate` ACL + `task_event_log` 审计（`longrun_checkpointed` / `longrun_resumed`）；`fist.py list-tools` 实测在册 |
| ② 快照写入（D1=A 整包） | ✅ 完整 | `engine.mbt:1486-1508` `longrun_checkpoint` → `longrun.mbt:145-177` `write_snapshot`（逐层补父目录防 BUG-390 / UTF-8 写 / **写后回读 parse 校验 + task_id 比对**）→ `core_task.mbt:311-325` `with_longrun_checkpoint`（**增量预算、交换律**）→ `store.update_task`；快照体复用 `Task::to_json`（不另立序列化），信封 `{format, task_id, written_at, task}`（`longrun.mbt:66-77`） |
| ②' 恢复语义 | ✅ 完整 | `engine.mbt:1519-1540` `longrun_resume` → `longrun.mbt:272-299` `resume_precheck`（**两层**：状态裁决在前——已暂停/执行中/已领取→已领取，非法六态逐一点名出路；快照存在性 fail-closed，含空文件/格式不符/task_id 不匹配三道拒）→ `core_task.mbt:344-346` `mark_claimed`（**唯一**目标态出口）→ `update_task`；`Claimed→Claimed` 幂等重入（注释+实测双证） |
| ③ 字段读写 ↔ 池库 schema 对齐 | ✅ 完整 | `store_sqlite.mbt`：CREATE TABLE 含四列 `:1556` / 旧库 ALTER 迁移 `:738-749` / `task_columns()` 24 列 `:882` / INSERT bind 21..24 `:970-984` / UPDATE bind 19..22 + WHERE id 第 23 位 `:1242-1251` / `row_to_task` 读索引 20..23 `:1138-1180` → `core from_db_longrun` 24 参 `:598-630`（与 BUG-475 同手法，旧签名零回归）；`core.to_json` 四字段外显 `:1100-1104`（看板可见「有快照」） |
| ④ 幂等键防重放 | ✅ 完整 | `core_task.mbt:354-376` `idempotency_add` / `has_idempotency_key`（D3=A **任务内**作用域、append-only、core 唯一写入口）+ `engine.mbt:1577-1588` guard 接线（duplicate 只读判定、register=true 才落库）；checkpoint「重复=重快照」与 resume「Claimed 重入」均为设计幂等（e2e 第 10 步实测） |
| ⑤ 测试面 | ⚠️ 原缺一格 → ✅ 已补 | `longrun_wbtest.mbt` 7 格（信封 round-trip / parse fail-closed 六拒 / 状态机 3 合法+6 非法 / precheck 两层顺序 / core 写入语义+交换律+幂等去重 / 真 IO 回环 / 变异对照）+ `guard_wbtest` + `baton_wbtest` 齐；**sqlite 层四列往返锁缺失 = G1（本轮补齐，见 §4）** |

## 3. 缺口清单

| # | 缺口 | 定性 | 处置 |
|---|---|---|---|
| **G1** | longrun 四列无 sqlite 层写读往返锁：`store_task_field_roundtrip_wbtest.mbt`（R191 全字段往返锁）走 `Task::new`，四字段默认全空从未被 sqlite 验证；INSERT(21..24) 与 UPDATE(19..22, WHERE id 第 23 位) 两套绑定位均无行为锁 ⇒ 错位即静默落默认值（R148「位置参数接错不报错」形状；`store_sqlite.mbt:1249` 注释点名的「UPDATE 静默失效」事故亦无行为锁兜住） | 测试缺口（非实现缺陷） | **本轮补齐**（2 格 / +110 行） |
| G2 | `core_task.mbt:328` 注释引用的 `fist_longrun_baton` 工具未注册（P1 baton 包 `baton.mbt`/`baton_wbtest.mbt` 已实现，工具面未接线） | T0r58（P1）范围 | **不动手**，列待办交管家 |
| G3 | engine 全链（`FistEngine` 穿 store）无白盒锁：longrun_wbtest 锁纯函数半区、store wbtest（G1 补后）锁库半区，中间衔接此前只有 e2e 覆盖 | 覆盖说明 | 本轮 e2e 实测已覆盖该形状（§5） |

## 4. 补齐记录（G1）

`src/store/store_task_field_roundtrip_wbtest.mbt` +110 行，两格（均为真 sqlite 行为锁，非源码文本锁）：

- **`task_longrun_fields_round_trip_create`**：四列各设**不同**非默认值（`Task::new` 命名参直填）→ `create_task` → `get_task` → 逐字段比对。锁 INSERT 绑定位 21..24：错位会让相邻字段「值互换」，逐字段比对当场红。
- **`task_longrun_fields_round_trip_update`**：默认值 create → core 唯一写入口（`with_longrun_checkpoint` 增量预算 + `idempotency_add` 追加键）→ `update_task` → `get_task` → 四字段逐一比对 + 其他列未动断言。锁 UPDATE 绑定位 19..22 + WHERE id 第 23 位：WHERE id 绑错位（idempotency_keys 槽拿到 id ⇒ WHERE id=NULL）⇒ UPDATE 一行不改而 execute 仍报成功 ⇒ 四字段停在默认值 ⇒ 必红。

## 5. 验证证据

| 验证面 | 命令/入口 | 读数 |
|---|---|---|
| 编译 | `moon check` | 0 errors（68/85 warnings 均为既有） |
| 定向套件 | `python scripts/moon_test_env.py --target js src/store src/longrun` | 165/165 passed |
| 全量 JS 权威门 | `python scripts/moon_test_env.py --target js`（改动落盘**后**复跑） | **2130/2130 passed, rc=0** |
| e2e 真工具调用链 | `temp/t0r53-e2e/run_e2e.py`（沙箱 ns=`t0r53-e2e`、`FIST_DB_PATH=temp/t0r53-e2e.db`、project_dir=`temp/t0r53-e2e-proj`，全落 gitignore 的 `temp/`，不进仓库） | **18/18 格全绿**（task=T0r6） |

e2e 链明细：`store_open` → `agent_acl_grant(workbuddy)` → `publish`(T0r6) → `claim`(→已领取) → `fist_longrun_checkpoint`(baton + budget_delta=10) → 回执 `checkpoint_path` 非空 / `budget_used=10` → `pause`(→已暂停) → **`fist_longrun_resume` → 状态恢复「已领取」** → `task_query` 跨调用复核（status/checkpoint_path/budget_used/last_baton 全部落库）→ **快照文件真落盘且信封可解析**（`format=fist-longrun-checkpoint-v1`、task_id 一致）→ 负例：待领取任务 resume 被拒且文案点名「[待领取]」（状态裁决先于快照存在性，两层顺序实证）→ 幂等重入：已领取再 resume 仍成功且状态不变。

### 附带发现（e2e 环境坑，非实现缺陷）

1. **WindowsApps Store python 桩吞参数**：subprocess 传**相对**脚本路径（`scripts/fist.py`）时桩把后续参数吞掉（rc=1 `can't find __main__`）⇒ 子进程必须绝对路径。
2. **sqlite 面 ACL fail-closed**：claim/checkpoint/resume 前须对身份 `agent_acl_grant(can_write=true)`；longrun 工具须显式传 `agent`（缺省 `manual` 身份无授权会被拒，且报错文案自带 BUG-436 提示）。
3. **`task_query` 无 `task_id` 参数**（只收 keyword/assignee/status 等过滤位），且 keyword 匹配 description 不匹配 id。

## 6. 遗留风险 / 后续建议

- **G2 待办（交 T0r58）**：`fist_longrun_baton` 工具接线（baton 包已实现，只差 server 注册 + 测试面接线锁）。
- resume 不校验快照**新鲜度**（陈旧快照也放行恢复）——属 P1/P2 护栏面，不在 T0r53 P0 边界。
- guard 失败比例阈值在内存后端不启用（`record_execution` 为 no-op，`store.mbt:1324-1326` 已注明）——设计一致，非缺陷。

## 7. 资源消耗 / 任务分配 / 来源（金条五）

- **资源消耗**：本会话单线执行，约 35 次工具调用；`moon check` ×1、定向测试 ×1、全量 JS 测试 ×2（各 2~4 分钟）、JS 构建 ×1（fist.py 新鲜度自检触发）；未起常驻进程（e2e 沙箱 server 为 fist.py 一次性 spawn，随调用结束）。
- **任务分配记录**：workbuddy 一人完成，未派子代理（任务为单线核实+小缺口补齐，无并行拆解价值）。
- **超额内容**：无任务边界外动作——零实现代码改动，仅测试文件 + 本报告 + 当日记忆日志；G1 补齐属任务第 3 条授权内（200 行内当场补齐）。
- **来源**：池任务 T0r53（管家派发，2026-11-28）；实现真源 `src/longrun/`、`src/engine/engine.mbt`、`src/core/core_task.mbt`、`src/store/store_sqlite.mbt`；提案 D1=A/D3=A 见 `src/longrun/longrun.mbt` 头注。
