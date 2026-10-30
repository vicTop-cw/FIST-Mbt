---
status: 已定案
decided_by: human_steward
decided_at: 2026-10-30
decision: approved
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

---

## 八、实现卡点实录（Lane DS 实测，2026-10-29）

> **本节是本文档最有长期价值的部分** —— 它记录的是**对 API 面的事实认定**，不是猜测。
> 下一个实现者会先想「按 mtime 排序」，然后撞同一堵墙。**请先读本节。**

### 8.1 `@fs` 可用接口的**完整清单**（实测枚举）

本包能用的 `moonbitlang/x/fs` 接口**只有这 7 个**：

| 接口 | 用途 |
|---|---|
| `@fs.path_exists(p) -> Bool` | 判存在 |
| `@fs.read_dir(dir) -> Array[String]`（抛错式，用 `catch`） | 列目录 |
| `@fs.read_file_to_string(p) -> String`（抛错式） | 读全文 |
| `@fs.write_string_to_file(p, content)`（抛错式） | 写全文 |
| `@fs.create_dir(p)`（抛错式） | 建目录 |
| `@fs.remove_dir(p)`（抛错式） | 删目录 |
| `@fs.remove_file(p)`（抛错式） | 删文件 |

### 🔴 8.2 **没有 `stat` / `mtime` / `metadata`** —— 由此推出两条硬约束

**这是本设计的形状限制，不是代码细节。**

| 原设计 | 为什么不可行 | 改成 |
|---|---|---|
| 按 **mtime** 排序决定 seq | **拿不到 mtime** | seq 从**文件名** `sig-<at_ms>-<counter>` 解析 |
| `gc(older_than_hours)` 按「文件多老」删 | **拿不到「文件多老」** | `gc(keep~ : Int)` —— **保留最近 N 条** |

**⇒ 「保留最近 N 条」不但可行，语义还更好**：
不依赖时钟（时钟回拨/时区不会影响）、可预测、且**与 seq 的「位置」语义天然对齐**。

**seq 的三段排序键（都不能省）**：
```
(at_ms, counter, name)
  │        │        └── 兜底：保证同一份目录的次序**确定**（判例「确定性优先」）
  │        └── 破同毫秒并列（`commissar_send` 的进程内自增）
  └── 时间先后（epoch 毫秒，粗粒度）
```

### 8.3 剩下 3 处 API 适配（逐条给出「假设错在哪」+「正确的做法」）

#### ① `String::parse_int64` **不存在**（`[4015] Value parse_int64 not found`）

**我的错误假设**：以为 `String` 有 `parse_int64()` / `parse_int()`。
**实际**：**MoonBit 标准库没有这个**；本仓的做法是**手工逐字符解析**。

**正确做法**（本仓既有先例 `src/ops/ops_ts.mbt:12`）：
```moonbit
fn parse_digits(chars : Array[Char], start : Int32, len~ : Int32) -> Int32 {
  let mut v = 0
  for i = 0; i < len; i = i + 1 {
    let c = chars[start + i]
    if c < '0' || c > '9' { return -1 }
    v = v * 10 + (c.to_int() - '0'.to_int())
  }
  v
}
```
**⇒ 实现 `parse_event_name` 时改用这个模式**（自己写一个小 helper，或用 `@json.parse` 绕）。

#### ② `@rhop.RhopEnvelope::decode` **返回 `Result`，不是 `Option`**

**我的错误假设**：`Some(env) ... None` 匹配。
**实际签名**（`RX-MBT/rhop/packet.mbt:86`）：
```moonbit
pub fn RhopEnvelope::decode(text : String) -> Result[RhopEnvelope, String]
```
**⇒ 应写 `Ok(env) => ... Err(_) => None`。**

⚠️ 顺带：`env.decrypt(cipher)` 的返回类型**也需再核**（未确认，是下一手的第 1 个检查点）。

#### ③ `derive(Debug)` 会因 `CommissarSignal` 无 `Debug` 而报 `[4018]`

**我的错误假设**：给 `CommissarPollItem` 加 `derive(Debug)` 便于调试。
**实际**：它含 `signal : CommissarSignal?`，而 `CommissarSignal`（`ops_commissar.mbt:66`）**没有 `derive(Debug)`**
⇒ `Option[它]` 也没有 ⇒ `[4018]`。
**⇒ 两个选择**：(a) 不加 `derive(Debug)`（**已在 WIP 里这么做**）；
(b) 给 `CommissarSignal` 加 `derive(Debug)`（它字段全是 `String`，安全）——但那要改别人的文件。

### 8.4 WIP 位置与复用建议

半成品在 **`temp/ops_commissar_poll.mbt.beta-wip`**（**不在编译树内**）。

**可直接复用的骨架**（是对的，只差 API 适配）：
- `parse_event_name`
- `commissar_list_events_sorted`（三段排序）
- `commissar_poll`（`since_seq` / `limit` / `next_seq` / `has_more` / `total` 的结构完整）
- `commissar_gc(keep~, dry_run~)`（含「`dry_run` 真不删」的实现）

**⚠️ 下一手的工作纪律**：**在 `temp/` 改到自洽，再一次性移回 `src/ops/`。**
中间态永远不进编译树 —— 本单曾两次因为红态挂在 `src/` 里而**挡住全仓提交各一轮**。

### 8.5 「为什么停」的判据（值得入档）

停手时有两条**可观测特征**，不是主观感受：

| 情况 | 特征 | 正确反应 |
|---|---|---|
| **偶发错误** | 修一个，错误数**减少** | 继续试 |
| **假设系统性错误** | 修一个，**下一层还有一个**（错误数不降反增：2 → 8） | **改设计或停** |

本单实测：2 errors → 改完 → **8 errors**。**这个方向是判据**：错误数不降 = 假设错了，不是手气差。

---

## 定案记录（2026-10-30 · R95 状态同步 · status=`已定案` / decision=`approved`）

**不是新实现，是状态同步 —— 三问早已在代码里落地（逐条实测）：**

| 问 | 草案选择 | 代码实况 |
|---|---|---|
| **Q1** `since_seq` 由谁维护 | **调用方传**，服务端无状态 | `commissar_read(since_seq~)` 已实现（实测 5 处引用）|
| **Q2** 已消费消息怎么标已读 | **不做**，调用方 dedup | 按草案未实现（**这是正确的「不做」**）|
| **Q3** 目录堆积怎么办 | 独立工具 `gc(keep~)` | `pub fn commissar_gc` 已在位（2 格白盒锁 `dl_c9`/`dl_c10`）|

**⚠️ `commissar_gc` 未接入 MCP 工具面**（`grep -c "commissar_gc" src/server/server.mbt` = 0）
—— 因生产从未使用政委消息池（项目根无 `.commissar/`）⇒ 为 0 使用者付 10 处投影成本收益为负。
**状态已标注在 `ops_commissar.mbt` 的文档注释里（BUG-493）。**
