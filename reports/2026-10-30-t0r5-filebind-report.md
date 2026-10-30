# T0r5 交付报告：F094 文件绑定协调层（多管家并行）

> 任务：`T0r5`（ns `fist-plan-20261029`，P2）｜认领：`lead`｜执行：子代理 `f7f130e6`｜终审：lead
> 提交：`a2d8e0a2`（24 文件 / +372 −64）｜`src/filebind/**` 由他人 lane 先行以 `f8029d18a` 入库

## 一、结果摘要

F094「多管家并行的文件绑定协调层」三件套落地，工具数 **179 → 182**。

| 项 | 读数 |
|---|---|
| `src/filebind` | `Total tests: 26, passed: 26, failed: 0` |
| `src/server`（回归面） | `Total tests: 557, passed: 557, failed: 0` |
| 工具一致性守卫 | `check_tools_sync` PASS（182）、`check_plugin_sync` PASS（4 宿主/64 文件/182）、`check_tool_add_completeness` rc=0 |
| 真跑冒烟 | 单进程内完整生命周期（bound → conflict 点名 A → renewed → invalid_path 逐条 → status 分栏 → not_holder → released → force 无理由被拒 → force → 空） |

## 二、中间态与两轮纠错（重要）

1. **上一位子代理中途失败**，留下 `src/filebind/filebind.mbt` **编译不过**的半成品，且它声称"已能编译"。
   我修掉一处类型错误（`Int.to_int()`）后**以为**包可用了 —— 后来新子代理证明**仍有两处 `StringView` 类型错误**
   和一处 `replace_all(old="\\\\")` 写成双反斜杠（导致 Windows 路径用例全错）。
   ⇒ 教训：**"我修过一处"不等于"它能用了"**，必须真跑编译/测试到出汇总行。
2. **我的还原动作做错了一次**：变异后用文本替换还原，替换到了另一个合法位置（`BndConflict` 撞进了原本 `BndNew` 的分支），
   结果 2 格红、且与 HEAD 差 2 行。改用**字节级备份 + `git diff HEAD` 验证**（diff 0 行）后才复绿。
   ⇒ 判例-30 同族：**还原要字节验证，不能凭"跑一次绿"当还原**。

## 三、设计与关键判断

1. **键**：`ns | 归一 project_dir`；条目 = `FileBind{ns, project_dir, path, holder, task_id, kind, scope, intent, bound_at, ttl_secs}`。
   `fb_norm` 只做 `\\`→`/`、丢空段/`.` 段、剥尾 `/`；**不**折叠 `..`（折叠会把越界洗白，交给 `fb_path_ok` 拒）、**不**小写化（POSIX 大小写敏感）。
2. **冲突判定 `fb_decide` 单一真源，顺序承重**：空闲→`BndNew`；**同一 holder 先判续期**（即便已过期也是 `BndRenewed`，不去接管自己的坟）；
   他 holder 已过期→`BndReclaimed`（过期 ≠ 仍被持有，绝不永远挡路）；他 holder 仍有效→`BndConflict`（拒绝并点名 holder/bound_at/ttl）。
3. **TTL 判据**写成 `now - bound_at >= ttl` 而非 `bound_at + ttl`，避免 Int32 相加溢出。
4. **与前三族的互补**（不是替代）：`reserve_scope`=作用域软预订；`lock_acquire`=物理路径并发写；`wt_*`=空间隔离；
   `file_bind`=**意图登记**（谁打算改哪个文件）。与 `claimguard`（逻辑项互斥）互补——一个防"两个 agent 做同一个逻辑项"，一个防"两个 agent 改同一个物理文件"。

## 四、变异对照（两发）

| 变异 | 读数 |
|---|---|
| 子代理：`fb_decide` 冲突分支改成永远放行 | **20/6 红**（另编译期 `Variant 'BndConflict' is never constructed` 自证死分支）；还原后 26/26 |
| **终审独立复验**（只改测试期望分支） | **恰好 1 格红**（`fb_conflict_lock_conflicting_holder_rejected`）；还原（字节级）后 26/26 |

## 五、缺口与风险

1. **跨进程不可见（最重要）**：账本是**进程内 Map**（与 `claimguard` 同型）。两个 server 进程各持一本账 ⇒
   多进程并行下本层的"冲突拒绝"只在**单进程内**成立。真解是 F094 §3.1 的 SQLite `file_binds` 表 + 事务裁决。
2. **无 TTL 后台清理**：过期绑定不自动删除，只在 `fb_status`/`fb_counts` 的 `now` 判定里"过期但可见"。
3. **`holder` 自报**：与 `reserve_scope`/`lock_acquire` 同源，属 BUG-430/S1 边界，不能防有意冒充（工具描述已写明）。
4. **未覆盖入口**：`scope=build`（构建互斥）未做；`verify`/`archive` 自动 release、`reject`/`reopen` 保留绑定的生命周期挂钩未做。
5. **并发 WIP**：AGENTS.md 计数被他人 lane 反复更新导致插件投影漂移一次，`gen_plugins.py` 重新生成后复绿。
6. **测试数锚点**：README/AGENTS 等写的是他人 lane 刚刷的 1959/1959，当前全量实测更高（并发 lane 在加测试）——锚点以提交时实测为准。

## 六、后续建议

1. 若要跨进程：开 F094 Phase-1b「file_binds SQLite 表 + 事务裁决」（依赖 BUG-119 心跳跨进程可见性）。
2. 若要生命周期挂钩：`watchdog_tick` 顺带清理过期绑定（F094 §3.3）。
3. 若要构建互斥：`scope=build` 分支（F094 §四 Phase 2）。

## 七、来源

- 任务：`T0r5`（`fist-plan-20261029`）
- 上游：`docs/features/F094-multi-butler-file-binds.md`、`-positioning.md`
- 上游对表：`reports/2026-10-29-plan-reconciliation-report.md`（指出 F094 协调层未实现）
