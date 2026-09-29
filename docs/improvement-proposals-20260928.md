# FIST-Mbt 改进建议书（2026-09-28，基于自动路由闭环实验与终审冲刺实测）

> 来源：自动路由闭环实验（auto-route-20260927）+ 终审分发工程实跑（BUG-102~112 系列）+ 复杂度阶梯实验归因
> 定位：不是 bug 单（bug 走 report_bug/bugs.md），是**结构性改进建议**，按优先级 P0~P2 分层，每条含「问题—方案—验收」。

---

## P0 · 清偿期必修（终审前/后立即）

### P0-1 销账控制面收尾：`bug_close` API 仍缺位
- **问题**：账本状态位已有 `FIXED(时间戳)` 格式与 `bug_mark_status`（改判 DUPLICATE/FALSE_POSITIVE），但「标 FIXED」仍只能靠 `bug_fix`（批量+小记互锁）——**单条修复的轻量销账路径缺失**，导致 dist 系列 9 条修完账本仍需手工对齐，且 44 条 OPEN 中「已修未销」的真实比例无法机读。
- **方案**：新增 `bug_close(bug_id, fixed_by, task_id?, now)`：单条销账 + 自动追加 `### FIXED(时间 / bug_id)` 小记 + 落 call_log；与 `bug_fix` 共用互锁单真源。
- **验收**：修一条 → bug_close → bug_list 状态 CLOSED 且小记存在；幂等重跑不重复写。

### P0-2 「显式传 now」旧纪律的全量文档更新
- **问题**：BUG-33 政策（时间戳一律服务端盖章，不接受注入）已全工具生效——实测 `publish_parallel` 传 `now` 直接被参数硬门拒绝。但 AGENTS.md、七份模式模板（_fist_meta_prompts）、多份实验报告仍写着「全调用显式传 now」——**新旧纪律互相矛盾，执行体按旧纪律必然撞硬门**。
- **方案**：① AGENTS.md 与模板库统一改为「时间戳由服务端盖章，**不传 now**；需要控制时间走测试替身通道」；② 在工具描述的公共段加一句「时间戳由服务端盖章」；③ 兼容期：服务端对 now 参数**显式报错并提示新纪律**（现在是硬门静默拒绝，调用方不知道原因）。
- **验收**：全仓 grep「显式传 now」归零；`publish_parallel` 带 now 的错误信息含「服务端盖章」提示。

### P0-3 README「黑盒用户」安装线的可达性收口
- **问题**：BUG-107/110 修了两轮，安装线（irm|curl）的公网可达性仍依赖 Release 资产挂出（差一次 CI）——README 承诺的「一条命令」当前对公网用户是断的。
- **方案**：跑通 Release CI → 资产挂出 → 从公网全新环境各跑一遍 install.ps1/install.sh → 把实测输出（含版本号）回写 README。
- **验收**：干净虚拟机/容器双平台安装成功；README 安装线 URL 返回 200 且内容为脚本（非 HTML）。

---

## P1 · 结构性改进（终审后第一批）

### P1-1 server 响应 flush 行为显式化（Popen 交互模式死锁根因）
- **问题**：11:20 重新构建后，MCP server 的 stdout 响应改全缓冲——Popen 交互客户端（readline 等 `\n`）与 server（等 stdin EOF 才 flush）死锁，读/写全挂。EOF 模式（stdin 喂完即关）可绕行，但**长驻交互式客户端（如未来 fistd 桥、IDE 集成）全部不可用**。
- **方案**：定位 colmugx/mcp 输出层，每次响应后显式 flush；或 server 提供 `--line-buffered` 启动参数。
- **验收**：Popen 交互模式 tools/list 秒回；fistd 桥可基于此实现。

### P1-2 `publish_parallel` 幂等防重标记
- **问题**：实验脚本重跑 4 次 → 18 条重复单堆积（publish_parallel 无 [review:file:idx] 式防重标记，selfdrive_publish_next 有而它没有）。
- **方案**：publish_parallel 支持 `idempotency_key`（可选）：同 key 重复发布返回既有 task_id（幂等 no-op）。
- **验收**：同 key 发布两次，第二次返回 same_id + created=false。

### P1-3 pause 与 heal 的语义冲突（暂停任务被自动恢复）
- **问题**：实测 pause 成功后任务回到待领取——疑似 watchdog/heal 把「无心跳的暂停任务」当僵尸恢复。人工暂停的管理动作被自动化看护撤销，**管理语义被执行语义覆盖**。
- **方案**：heal 的回滚白名单排除 `paused_by=human` 的任务（pause 工具在任务上记 `paused_by`）；或 heal 跳过已暂停态。
- **验收**：pause → watchdog_tick/heal → 任务保持已暂停。

### P1-4 `list` 的 namespace 过滤失灵（BUG-12 的现行变体）
- **问题**：任务真实存在（get 可查、namespace 字段正确）而 `list(namespace=ns)` 返回 0——过滤逻辑与存储字段不一致（BUG-19 硬门修复后 list 参数校验路径可能变化）。
- **方案**：复现最小 case → 修过滤匹配 → 加「list(ns) 结果 ⊆ list(全量) 过滤后结果」的回归锁。

### P1-5 执行器自动拉起（dispatch 闭环的最后一块）
- **问题**：`selfdrive_dispatch` 完成「认领」，但被认领的执行器需要**人工拉起 harness 会话**才会真正干活（glm5.3-flash 裸跑实验已证明无人拉起时「完成」可能只是幻觉）。
- **方案**：`fist executor spawn <name>`：按 executor 注册信息（command 模板）自动拉起对应 harness 会话（atomcode/aider），挂同一任务库；配合心跳/watchdog 形成无人值守闭环。此能力也是「机器内置服务」定位的收官件。
- **验收**：publish 3 任务 → dispatch → spawn → 无人干预全部 verify → 销账。

---

## P2 · 中期方向（终审后）

### P2-1 工具数治理：120 → 「核心 + 插件化」
- 工具已 129 个且持续增长，文档/计数守卫成本线性上涨（BUG-17/102/110 系列的根因）。建议：核心高频工具（生命周期/查询/门禁 ~30 个）保留 MCP 直挂；长尾工具转 **plugin/skill 按需加载**（四态体系已具备，cl7 守卫已有雏形）——工具数降下来，能力不减。

### P2-2 `bug_close` 之后的账本治理闭环
- P0-1 落地后：① bugs.md 加「周报视角」（OPEN 按主题分组/修复速率/积压年龄）；② bugfind 流水线的发现阈值与修复速率联动（发现 > 修复 ×3 时自动降频，防雪球）。

### P2-3 时区/时钟一致性（服务端盖章的精度）
- 实测发现服务端盖章时间与系统时钟存在 ±1h 漂移（node 子进程 TZ 数据与宿主差异）——单机自用无害，多人协作时账本排序会乱。建议盖章时显式带时区偏移或统一 UTC 存储 + 展示层转换。

### P2-4 多执行器竞标的实战校准
- executor_auction（置信度校准拍卖）已实现但未实测——建议在自动路由闭环实验二期引入（三个执行器竞标一批任务，验证校准系数对「过度自信执行者」的实际惩罚效果），产出竞标数据反哺信任轴参数。

---

## 附：价值定位一句话（终审叙事可用）

> 实验三角（A/B 对照 → 复杂度阶梯 → 自动路由闭环）+ 四项目实战（兹/Pentad/Cypy/lz）证明：FIST-Mbt 把 agent 委派的「完成」从**声明变成事实**——裸跑模型可以幻觉完成，FIST 闭环里不可能。

---

*建议人：Loomy（butler）｜ 依据：auto-route-20260927 实验 + SHIP-PLAN 实测 + BUG-102~112 修复实录 ｜ 每条建议独立可立项，可整批入 BACKLOG 走 fix_and_merge 轮消化。*
