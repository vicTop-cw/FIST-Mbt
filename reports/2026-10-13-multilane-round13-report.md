# 多 lane 锁机制 · Round 13 收口报告（优先级感知级联谈判）

- 日期：2026-10-13
- 负责人：meta 目标同责 agent（本仓 `src/claimguard/` 孤立作用域 owner）
- 模式：FIST 指挥官模式 · 本人做终审/验证，库层纯增量（白盒测试自验）
- 后端：JS + native 双后端同绿

## 1. 结果摘要

Round 12 的级联谈判在「碰撞度数相同」时用**名字升序**选让权目标。多 lane 真实调度里 peer 有**优先级**（来自 executor_route 的 信任×负载 轴），协调器应让**低优先级**的 peer 先让——本回合补上这一维。

新增（均 `pub`、纯函数、只读，复用 R9 `reconcile_all` / R10 `admit`+`conflict_scoreboard` / R11 `peer_yield` / R12 `negotiate_admit` 单一真源链）：
- `negotiate_admit_priority(proposed, others, max_steps, priorities) -> NegotiateReport`：与 R12 `negotiate_admit` 同形级联，但候选排序改为 **(度数 desc, 优先级 asc, 名字 asc)**；`priorities : Map[String, Int]` 缺省按 0 计。返回结构复用 `NegotiateReport`（`ok` / `yielded` / `admit`）。
- 私有辅助 `pick_top_priority(es, i, cur)`：在 `(name, degree, priority)` 三元组上做同一不可变最大比较，不引入第二套可变累加器。

R12 原有的 `negotiate_admit`（名字序）**保留不动**，作为「关掉优先级维度」的回落与对照基准。

实证（双后端 **37/37**，35 → 37，新增 2 项白盒）：
- `cg_negotiate_admit_priority_order`：D 双撞 Z(item-z) 与 A(item-a)，两个 peer 碰撞度数相同（各 1）；`prio(Z)=1`、`prio(A)=9` → `negotiate_admit_priority(...,4,prio)` 两次让权后 `ok=true`、`yielded.length()==2`，且**首位为 Z（低优先级先于高优先级）**；真实在飞 `gz`/`ga` 仍持原 item（证纯模拟不落地）。
- `cg_negotiate_admit_priority_vs_name`：同场景、R12 名字序级联首位为 A（A < Z 升序）、R13 优先级级联首位为 Z（1 < 9）→ 两者首位不同，证明优先级维度确实改变了谈判序列、非名字序的简单别名。

## 2. 资源消耗

- 代码增量：`claimguard.mbt` 追加 `pick_top_priority`（约 28 行）+ `negotiate_admit_priority`（约 42 行，含注释与 doc）。
- 测试增量：`claimguard_wbtest.mbt` 追加 2 项白盒（约 52 行）。
- 接口重排：仅本包 `pkg.generated.mbti` 重排，导出 `negotiate_admit_priority`（私有 `pick_top_priority` 不入公开接口，符合既有封装）。
- 未碰任何 lane-owned 文件，未翻 BACKLOG 行，未提交。

## 3. 任务分配记录

- 本增量纯库层、可独立验证，由本人直接落码 + 白盒自验（指挥官模式·中任务：库内增量 + 验证循环）。
- 真实让权通道、优先级真值来源（executor_route 信任×负载轴）仍越出本包孤立作用域，接入待 owner 决策。

## 4. 遗留风险

- R13 仍是「待编排的强制层」：级联谈判结果是**计算**（`ok`/`yielded`），真实让权执行由协调器/生命周期负责；二者靠 `negotiate_admit_priority` 的 `yielded` 序列串联，不模糊所有权。
- `priorities` 由调用方注入；本包不负责维护 peer 优先级真值——真值源应是 lane-owned 的 `executor_route`（信任+负载），接入后协调器从那里取数即可，无需本包改动。
- 级联目标集仍仅在 `proposed` 当前碰撞的 peer 中选，未做「让了这一个后是否会引出新碰撞」的前瞻；当前纯投影语义下每步重跑 `admit` 已自然覆盖后效，无需额外前瞻逻辑。

## 5. 后续建议

1. 把 `negotiate_admit_priority` 的 `yielded` 序列接到真实让权通道（`reserve_release` + `release_item`），形成「计算 → 执行」闭环；优先级真值从 `executor_route` 信任×负载轴注入。
2. 给 peer 引入 priority 维度后，可进一步让 R12 的 `admit_after_yield` / `peer_yield` 也接受优先级（若谈判需要「一次让不止一个最低优先 peer」的批量让权）。
3. 并发 lane 收口后跑一次 nightly 全仓 `moon fmt`，撤销 fmt 门 `continue-on-error`、恢复门强度。

## 6. 超额内容

- 顺带修正 R13 测试里一处 MoonBit 惯用法：`Map` 的 `.set` 是**语句**（原地改、返回 `Unit`），不能链式 `.set(...).set(...)`；改用显式 `let prio : Map[String, Int] = Map([]); prio.set(a, x); prio.set(b, y)`。该惯用法与 `conflict_scoreboard`（L554 起）一致。

## 7. 来源

- 复用真源：`src/claimguard/claimguard.mbt` 的 `reconcile_all`(R9) / `admit`+`conflict_scoreboard`(R10) / `peer_yield`(R11) / `negotiate_admit`(R12)。
- 配套报告：`reports/2026-10-13-multilane-lock-mechanism-report.md` §10.12。
