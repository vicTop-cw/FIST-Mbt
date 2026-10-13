# F094 · 多管家协作文件级并行协调层 —— 特性定位

> 状态：**承重墙已修，Phase 1 仍不排期**（BACKLOG L49，owner 2026-10-07 采纳「先修承重墙、不建三工具」方向）。
> 本文是 2026-10-13 第 2 轮「顺带看看锁机制」复核后补写的**定位文档**，澄清 F094 与现有
> `reserve_scope` / `lock_acquire` 两族工具的关系，以及本轮回测暴露的一个**逻辑级盲区**。

## 1. F094 是什么

多 agent（"管家"）并发编辑**同一个目标项目**时，需要一层「文件级并行协调」：

- `file_binds` 表：记录某 agent 绑定（bind）了哪些文件/目录作用域；
- `file_bind` / `file_release` / `file_status` 三个工具：绑定、解绑、查状态；
- 构建互斥：同一作用域同一时刻只有一个 bind 成功；
- worktree 终态：跨 worktree 的绑定收口。

## 2. 与现有两族锁工具的关系

| 层 | 工具族 | 已落地 | 作用域粒度 |
|---|---|---|---|
| 作用域预订 | `reserve_scope` / `reserve_check` / `reserve_release` | 已落地（store_rsv） | 命名空间内 scope 字符串 |
| 分布式文件锁 | `lock_acquire` / `lock_renew` / `lock_release` / `lock_status` | 已落地（store_rsv） | scope + TTL + 违例留痕 |
| **多管家文件绑定** | `file_bind` / `file_release` / `file_status` | **F094，未排期** | 物理文件路径 + worktree 终态 |

F094 是前两族的**上层编排**：前两族解决「同一命名空间内 scope 互斥」，F094 解决
「多个管家跨 worktree 对同一物理文件树的绑定协调」，多了「worktree 终态」这一维。

## 3. 承重墙（已修，使验收格成立）

- **BUG-136 预订原子性**：`rsv_try_set` 写后回读收口（store_rsv.mbt L94-137），跨进程下
  `reserve_scope` 才真正互斥——「两进程同时预订同一 scope 恰好一成一拒」从不可能成立变为有常驻判据守着。
- **BUG-137 调用方身份**：裁决必须携带调用 agent 身份（`RsvOutcome.agent`），回执不许由请求反推。
- **J14 计数自述**：工具计数与 CLI 分组自述一致，避免新增工具后文档漂移。

承重墙修好后，F094 的验收格「两进程同时 bind 恰好一成一拒」才从「恒红/恒绿位」变成「有常驻判据守着的真命题」。

## 4. 本轮回测暴露的盲区（关键发现）

物理文件锁 / scope 锁 / 文件绑定 三层都只能防住**同一物理作用域**的并发写冲突。
但它们**防不住逻辑级 BACKLOG 项碰撞**：两个 agent 在**不同的文件作用域**里实现了**同一个待办项**。

实证（2026-10-13 第 2 轮）：
- BACKLOG L38「毫秒级符号逻辑引擎」的规范实现是并发 lane 的 `src/symbolic/`（Tseitin CNF + DPLL SAT）；
- 本 agent 第 1 轮在 `src/constraint/` 也落地了一个「布尔约束拦截 planned action」包——
  功能上**重叠**于 L38，但目录不同、scope 不相交，于是 `reserve_scope` / `lock_acquire` 两族工具**全程无告警**。
- 同样，L35「里程碑式渐进分解」已在 `src/decompose/milestone.mbt` 由另一 lane 实现，
  而 BACKLOG L35 行仍 `pending`（owner 未翻账），旁观者无从在认领前知道它已被占用。

**结论**：多 agent 协作的「硬互斥」靠文件锁已足够；但「软互斥」——同一 BACKLOG/P 项不被两个
agent 在两份文件里各做一遍——目前**没有任何机制**拦截，只能靠 (a) 认领前逐行核对 BACKLOG 全部
pending 行的实现落点，或 (b) 给 BACKLOG 项也加一个 `reserve_scope` 式的逻辑预订。

**建议（写入 F094 范围，待 owner 决策）**：
- 短期：自驱/认领流程在动手写代码前，先 `grep` 全仓 `src/**` 是否已有该 BACKLOG 项的落点
  （本次即靠 `grep "milestone|里程碑"` / `grep "符号逻辑|SAT"` 才避免重复实现）；
- 中期：F094 的 `file_binds` 表可复用为「BACKLOG 项 → 落点文件作用域」的登记，使逻辑项也
  有 bind/release 协调，把软互斥升级为硬互斥。

### 4.1 盲区已落「逻辑项互斥闸」强制包（第 3 轮收口，2026-10-13）

第 3 轮把上述盲区从「建议」推进到「可运行强制层」——新建**独立自包含**库 `src/claimguard/`：

- 复用 `rsv_action` 同序裁决（`decide_claim`：空闲→认领 / 本人→续订 / 他人→拒绝）；
- 以 `holders : Map[String,String]`（项→agent）做**逻辑项级 mutex**，与物理文件作用域解耦；
- `claim_all` 批量原子抢占、`blind_spot_holds` 显式编码「作用域不相交且项被他主持有」、
  `may_proceed` 作为推荐门控；
- 实证：`moon fmt --check` rc=0、`moon test --target js` **12/12 全绿**、`moon info` 重新生成 `pkg.generated.mbti` rc=0。

`src/claimguard/` 与 F094 是**互补**关系：它管「逻辑项碰撞」，F094 的 `file_binds` 管「物理文件绑定登记」；
两者都不依赖对方即可独立收口——盲区的强制层已落地，**无需等** F094 Phase-1 工具排期。
该包当前仅作为库暴露，**尚未接入 MCP server 生命周期**（`claim`/`publish` 流程前未挂 `claim_item`），
接入与否由 owner 决策（见 `reports/2026-10-13-multilane-lock-mechanism-report.md` §10.4）。

## 5. 待办

- [ ] owner 复核：是否把 `src/claimguard/` 接入 `claim`/`publish` 流程前，作为逻辑项预订的运行时拦截；
- [ ] owner 复核：是否把「逻辑项预订」纳入 F094 的 `file_binds` 语义（扩面）；
- [ ] 若扩面，补 `file_bind` 对 BACKLOG 项 ID 的预留位（schema-reserved，避免 BUG-28 红面）；
- [ ] 不改现有 scope 锁语义，仅在编排层加逻辑项登记。
