# 超级管家 supervisor 工具白盒测试收口报告（P1 计划 §5/§7）

- 生成时间：2026-10-14T16:10+08:00
- 任务来源：`docs/2026-10-12-fist-mbt-supervisor-tools-plan.md` §5（引导投递闭环）/ §7（kill 方案六门链）遗留测试文件未实现项
- 实现方式：白盒锁 `src/server/supervisor_tools_wbtest.mbt`（同包可见私有 fn，492 行，4 组测试）
- 实测结论：**JS 后端全仓 1042/1042 全绿**（基线 1033 + 本文件用例 + 兄弟 lane 增量），`moon fmt --check` rc=0，提交 `ab46f42`（仅 stage 本文件）
- 一句话结论：**supervisor 四大工具（guidance 投递 / kill_plan 六门链 / task_upsert 三路径 / task_tree 聚合）白盒覆盖已补齐，终态用例构造坑（`archive` 需 `[已完成]`）已修复并沉淀为 `sup_drive_to_archived` 辅助。**

---

## 1. 四组覆盖与关键判定

| 组 | 测试名 | 覆盖点 | 关键断言 |
|---|---|---|---|
| §5 引导投递 | `supervisor_guidance_inject_list_consume 闭环` | inject 3 → list（默认排除已消费、新者在前）→ consume 幂等 → include_consumed 切换 | list 长度=3 / 未消费在前 / 重复 consume 不重复返回 |
| §7 kill 方案 | `supervisor_kill_plan 六门链` | G1 身份 / only_plan / allowed / G3 根保护 / G4 终态 | 随机 agent→`blocked`；human 无 reason→`only_plan`；human+force+reason→`allowed`；root→`blocked`；归档后→`blocked` |
| upsert | `supervisor_task_upsert 三路径` | created / updated / failed(缺失·非对象·终态拒改) | 无 task_id→`created`；root→`updated`；缺 task_id→`task not found`；`Json::string`→非对象拒改；归档 child 改描述→终态拒改 |
| tree | `supervisor_task_tree 聚合` | publish→claim→plan(split_n=2) 聚合 | `subtree_total==3` / `subtree_done==0` / 2 子节点 / ghost id→Err |

---

## 2. 关键坑与修复（终态构造）

**现象**：G4（终态不可杀）与 upsert 终态拒改两例，在 `match e.archive(child) { Err(x) => abort("archive child 失败: {x}") }` 处直接 abort。

**根因**（读 `src/core/core_task.mbt` 确认）：
- `Task::archive()` 仅接受 `Completed` 状态（`core_task.mbt:447-457`：「非法迁移: archive 要求状态 [已完成]」）。
- `engine.archive` 的 fallback 是先 `complete()`，而 `complete()` 仅接受 `Reviewing`（`core_task.mbt:425-443`）——`plan` 产出的 child 仍是 `[待领取]`，既不满足 `archive` 也不满足 `complete`，故必 Err。

**修复**：新增 `sup_drive_to_archived(e, child, now)`，走完整生命周期
`claim → execute(非空交付物，绕过 audit_execute_gate 占位符门) → submit(执行中→待验收) → verify(人类主权验收) → archive(待验收→已完成→已归档)`，
把 child 真正驱动到 `[已归档]` 终态后，G4 / 终态拒改两例才成立。

> 旁路观察：终态拒改的精确错误文本为 `"终态任务 [...] 拒改"`，非 `missing`；`Json::string("...")` 走的是 `"item 不是对象或缺少 description"` 分支——两处断言均按实际产出文案绑定（非臆测）。

---

## 3. 隔离约定（防进程全局串扰）

- **kill / upsert / tree** 用例各用独立 `FistEngine::new()`（内存后端），彼此状态隔离。
- **guidance 闭环**调用包级 `engine` 与 `supervisor_guidance` 注册表（进程全局 `SupervisorGuidanceRegistry`）。为防跨测试串扰，本用例注入唯一 `target="wbtest-guidance-closed-loop"`，断言只绑定自己注入的 id。
- 复用同包 `project_standards_wbtest.mbt` 的 `ps_*` 提取器（`ps_str`/`ps_num`/`ps_arr_len`/`ps_must`），不重复定义。

---

## 4. 资源消耗与任务分配

- 本 lane 为指挥官直落（金条四：待测功能单一、集中在单文件白盒锁），未再派子代理；Lead 负责意图判定、读码定位根因、终审与记忆沉淀。
- 验证循环：`moon fmt` → `moon info && moon fmt`（同步 `.mbti`）→ `moon test --target js`（全绿 1042）→ `moon fmt --check`（rc=0）→ `git add` 仅本文件 → commit。
- 读码：定位 `archive`/`complete`/`submit`/`execute` 状态机契约（`core_task.mbt:407-457`、`engine.mbt:83-205,400-420`），确认终态构造路径。

---

## 5. 多 Agent 同目标文件锁定机制观察（顺带看看）

本轮与兄弟 agent 共享同一 objective（fist-mbt 自迭代 + 收口计划表遗留项），实证多 agent 并发编辑同一项目的工作树协调机制：

- **零冲突**：工作树存在大量兄弟 lane 改动（`.github/workflows/ci.yml`、`src/router/*`、`reports/2026-10-13-*`、`scripts/check_test_sync.py`、未跟踪的 `docs/2026-10-14-router-enhancement-plan.md` 等），本 lane 只 `git add src/server/supervisor_tools_wbtest.mbt`，未触碰任何兄弟文件。
- **提交并行不覆盖**：`git commit` 只收口本文件（commit `ab46f42`），HEAD 与兄弟提交并行推进，互不覆盖——印证「谁提交谁翻账」+ 文件作用域预订能支撑多 agent 并发编辑同一项目无破坏。
- **`.mbti` 是潜在汇合点**：`moon info` 会全仓重生成 `.mbti`；本 lane 主动不 stage 任何 `.mbti`（属兄弟 lane 改动），避免与兄弟 lane 的 `moon info` 产物冲突。
- **BACKLOG 红线未动**：L16(native) / L33(self_search) 归属其他 agent，本 lane 未翻动。

---

## 6. 遗留风险与后续建议

- **native 后端**：本轮仅在 JS 后端验证（1033 基线 + 增量全绿）。native 受 BUG-133 影响，依赖侧修复后需连发全绿确认（见账本）。
- **`.mbti` 同步**：若兄弟 lane 先提交其 `moon info` 产物，本 lane 后续若重跑 `moon info` 需留意 `.mbti` 差异，提交前只 stage 自有文件。
- **guidance 注册表**：进程全局可变，新增 guidance 测试务必用唯一 `target`，否则会与既有测试串扰导致 list 长度断言失准。

---

## 7. 超额内容与来源

- 超额：`sup_drive_to_archived` 辅助本为修终态坑而生，现已固化为「任何需 `[已归档]` 终态的 supervisor 测试」的标准构造器，惠及后续 kill/upsert 扩展用例。
- 来源：用户指令「实现计划表中未实现的计划，全程用 fist-mbt 迭代自身，开关全开，顺带看看多 agent 操作同一目标项目文件锁定机制」。
- 引用：`docs/2026-10-12-fist-mbt-supervisor-tools-plan.md` §5 / §7。
