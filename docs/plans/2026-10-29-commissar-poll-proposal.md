---
status: 提案中
decided_by:
decided_at:
decision:
---

# `commissar_poll` 设计草案（BUG-480 的替代方案）

> **状态：仅设计，未实现。** 前提：`commissar_watch` 已因 BUG-480 撤回（不注册成 MCP 工具）。

---

## 一、为什么不是「让 watch 可关闭」，而是改成 poll

`commissar_watch` 撤回时的三条事实：

1. **它只 `subscribe`、不保存 sub 句柄、从不 `dispose`**
   ⇒ 即使 RX-MBT 的 `close()` 已修（`Number(id)` 归一），**它根本不调 dispose**。
2. **它不是同步阻塞**，而是靠 `fs.watch(persistent:true)` 让事件循环保持活跃
   ⇒ 表现是「**活着、能响应、但进程永不退出**」——**比阻塞更难发现**。
3. **MCP 是请求/响应模型。** 任何「长驻句柄」都会让
   **进程生命周期与一次工具调用耦合**。

**⇒ 结论：问题不在「订阅没关好」，在「订阅这个形状本身与 MCP 不匹配」。**
把长驻改短轮询，是**用形状匹配换掉补丁**。

| | `commissar_watch`（撤） | `commissar_poll`（本设计） |
|---|---|---|
| 句柄 | 长驻 `fs.watch` | **无** |
| 进程能否退出 | ❌ 否 | ✅ **随时** |
| 与 MCP 模型 | 不匹配 | **匹配**（一问一答）|
| 新消息怎么来 | 回调推送 | **调用方下次来问** |

---

## 二、签名

```moonbit
pub fn commissar_poll(
  engine : @engine.FistEngine,
  project_dir~ : String,
  since_seq~ : Int64 = 0,   // 0 = 从头（或从服务端记的位置）
  limit~ : Int = 100,        // 单次上限，防一次吐爆回执
) -> Result[Json, String]     // { signals: [...], next_seq: Int64, has_more: Bool }
```

`CommissarSignal` 复用现有结构（`src/ops/ops_commissar.mbt` 已有 `from_json`）。

---

## 三、三个关键设计问题的取舍

### Q1：`since_seq` 由谁维护？

| 方案 | 优点 | 缺点 | 结论 |
|---|---|---|---|
| **A. 调用方传（无状态）** | 服务端零状态、天然多客户端、重启无影响 | 调用方要自己存 seq；**忘了存就重复消费** | ✅ **主方案** |
| B. 服务端按「最后消费位置」记 | 调用方省事 | **单点状态**：两个客户端会互抢；进程重启丢失；要额外表 | ❌ 不做 |

**⇒ 选 A：`since_seq` 由调用方传，服务端**完全无状态**。**

「服务端记位置」还有个更根本的问题：**它假定「只有一个消费者」**。
本仓的实际形态（多 agent 并发）明确否定这个假定。

### Q2：已消费的消息怎么标「已读」？

**⇒ 不做已读。`poll` 幂等，调用方自己 dedup。**

理由：
- 「已读」需要**写状态** ⇒ 又把无状态改回有状态。
- 调用方本来就有 `next_seq`，**它天然知道「我消费到哪」**——那已经是「已读」，
  只是这个「已读」标记**存在调用方那边**，与服务端无关。
- 事件文件（`.commissar/events/*.rhop`）**只读不改** ⇒ 多消费者互不干扰。

**⚠️ 代价要说清**：两个客户端用同一个 `since_seq` 会**都收到**同一条（各读各的）。
**这是特性不是缺陷**——「广播」语义比「竞争消费」语义更适合政委信号（引导/心跳）。

### Q3：目录里文件堆积怎么办？

**三层，按「谁产生谁负责」分**：

| 层 | 谁做 | 做什么 |
|---|---|---|
| **① 生产侧限流** | `commissar_send` | 已有：写 `.rhop` 时按 kind 落不同子目录，天然分桶 |
| **② 消费侧裁剪** | `commissar_poll` **不裁** | — |
| **③ 运维侧清理** | **新的 `commissar_gc(retention_hours=72)`** | 删 `mtime` 超过保留期的 `.rhop` |

**为什么不在 poll 里裁**：poll 只读，**读操作删文件**是最坏的副作用类型
（两个客户端并发 poll 会互相删掉对方还没读的）。

**为什么需要 gc**：不 gc 目录会无限涨。但 **gc 必须是显式工具调用**，
不是「poll 顺便清」——**隐式删除比不删除更吓人**。

---

## 四、验收判据（实现时用）

1. **两进程对称**：A `commissar_send` ⇒ B `commissar_poll`，B 拿到 A 的消息。
2. **B 的进程能退出** —— 这是本设计的**唯一核心判据**（BUG-480 那轮教训：
   「能跑」不等于「能退出」）。
3. **无长驻句柄**：`grep -c "fs.watch\|subscribe" src/ops/ops_commissar_poll.mbt` **必须为 0**。
4. **`since_seq` 前进**：poll 返回 `next_seq`，用它再 poll ⇒ 不重复。

---

## 五、不做什么（避免范围蔓延）

- ❌ 不做 push / 回调 / webhook（那就是 watch 换个名字）
- ❌ 不做服务端「已读」标记（见 Q2）
- ❌ 不在 poll 里删文件（见 Q3）
- ❌ 不做 `commissar_unwatch`（没有 watch 需要 unwatch）

---

## 六、与现有资产的关系

| 资产 | 关系 |
|---|---|
| `commissar_send` | **对称的另一半**：send 写 `.commissar/events/`，poll 读同一目录 |
| `RX-MBT` BUG-480 补丁 | poll **不需要**它（不碰 `fs.watch`）⇒ **poll 落地后，watch 补丁的价值只剩「不让既有代码挂住」** |
| `commissar_watch`（未注册） | **保留源码但不注册**；若将来 MCP 支持长连接再评估 |

---

## 七、待决

1. `since_seq` 用**文件名字典序**还是**文件 mtime**？（前者确定、后者受时钟影响 ⇒ **倾向文件名**，
   要求 `send` 侧文件名带单调递增前缀）
2. `limit` 默认 100 是否够？（要估政委信号的日常量级）
3. `commissar_gc` 的保留期默认值（建议 72h，与 `stale_hours` 24h 错开两级）
