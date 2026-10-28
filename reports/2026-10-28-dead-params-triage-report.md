# 死参数三分类判定（Lane CS）

> 司令-γ · 2026-10-28 · **只读审核**（未改 `src/` `scripts/`）
> **结论先行：22 处的原始读数里，19 处是**误报**（判据缺陷），真实死参数只有 **3 处** ——
> 且**没有一处是「该接线」的 bug**：1 处该摘 schema、2 处是设计如此（且描述该改）。**

---

## 结论

### ① 我上一单的 22 处**大部分是判据缺陷**

| 误报来源 | 处数 | 根因 |
|---|---|---|
| `hat_*` 的 10 处 | **10** | handler 只有 `hat_run_impl(args)`，参数在 **impl 函数里**读 —— 判据没跟透传 |
| 换行调用 | 3 | `get_int(\n args,\n "P",` 跨行 ⇒ 字符串匹配失败 |
| `args` 解构 | 3 | `loop_create` 用 `match args { ... m.get("P") }` |
| 未收录的取值函数 | 4 | `jnum` / `get_json_text` / `arg_str` / `jget` 不在白名单 |
| **参数在 `@engine` 侧读** | 1 | `cost_budget_check` 把 `args` 整体交给 `@engine.budget_check_json`，后者 `jget(args,"current")` |
| **括号配平被字符串内 `)` 干扰** | 其余 | `instrumented_tool(...)` 描述里含大量 `)` ⇒ 块被**提前闭合**（`laya_decide` 真块更大，切出来 handler 只剩 409 字符）⇒ **假死** |
| **合计误报** | **19 / 22** | |

### ② 真实死参数：**3 处 / 2 个工具**

| 工具 | 参数 | 类别 | 判定依据 |
|---|---|---|---|
| `lock_acquire` | `ts` | **C 设计如此** | `let ts = now_default()` **覆盖**调用方值 = BUG-33 服务端盖章 |
| `lock_renew` | `ts` | **C 设计如此** | 同上 |
| `loop_create` | `items` | **B 该摘 schema** | schema 声明但无任何读取；同块已有 `steps` |

**⇒ 三分类结果：A（该接线）**0 处** · B（该摘 schema）**1 处** · C（设计如此）**2 处**。**

**⚠️ 没有「该接线」的 bug** —— 与 `plan.challenge`（BUG-472）/ `execute.agent`（BUG-473）性质**完全不同**：
那两个是**安全语义**的承诺未兑现；这 4 处是**无行为承诺的标注字段**。

---

## 证据

### §1 `lock_acquire.ts` / `lock_renew.ts` —— **C 类（设计如此）**

```moonbit
// lock_acquire handler（server.mbt ~6092）
let ts = now_default()      // ← 覆盖调用方传入的 ts
lock_acquire(..., ts~)      //   传给 engine 的是服务端时间

// lock_renew handler（~6165）
let ts = now_default()
let renewed = l.renew(ttl_until~, ts~)
```

**这是 BUG-33 政策「时间戳服务端盖章，调用面无 `now` 参数」**（AGENTS.md 已立）。
**⇒ 不是 bug。**

**⚠️ 但 schema 描述写的是「获取时间戳（可选，默认当前时间）」** ——
「默认当前时间」暗示**可以覆盖**，而实际**永远由服务端决定**。
**⇒ 描述有误导，属「C 类但描述该改」**（我把它记为 **C−**）。

### §2 `cost_budget_check.current` —— **误报（跨包透传）**

```moonbit
fn(args : Json) -> ... {
  let result = @engine.budget_check_json(args)   // ← 整个 args 透传
  Ok(@mcp.ToolResult::text(result.stringify()))
}
```
`schema` 声明 `limit`/`current`，handler **一个都不自己读**，而是把 `args` 交给
`@engine.budget_check_json`。**engine 侧确实在读**：
```moonbit
// src/engine/cost_tool.mbt:64
let limit   = match jget(args, "limit") { ... }
let current = match jget(args, "current") { ... }   // ← 真读了
budget_check(limit, current)
```
**⇒ 不是死参数，是我的判活只扫了 `src/server/`，没跨包。**

### §3 `loop_create.items` —— **B 类（该摘 schema）**

```moonbit
schema({
  "steps": ...,            // ← 真正的入口
  "items": string_prop("单个 step mode"),   // ← 从未被读
  "preset": ..., "max_rounds": ..., ...
})
// handler 里读 steps / preset / max_rounds / stop_on_* / baseline_*，
// 但 items 一次都没出现
```
**⇒ `items` 是**遗留字段**：`steps` 已是数组入口，`items` 单值形态从未实现。
**建议**：摘掉 `items`（若曾有调用方用它，属**静默无效**，无从兼容）。

### §4 为什么 `hat_*` 的 10 处全是误报

```moonbit
fn(args : Json) -> ... {
  match hat_run_impl(args) {        // ← 整个 args 交给 impl
    Ok(j) => Ok(...), Err(e) => Err(...)
  }
}
// impl 里：let raw = get_str(args, "config_json")     ← 真读了
//          let round = get_int(args, "round", default=1)  ← 真读了
```

---

## 分析：为什么「死参数」里大部分是**判据**问题而不是**代码**问题

### 三个层次要分清

| 层次 | 例子 | 谁的问题 |
|---|---|---|
| **语义承诺未兑现** | `plan.challenge`（BUG-472）、`execute.agent`（BUG-473） | **代码 bug**（安全语义） |
| **遗留字段** | `loop_create.items` | **schema 卫生**（该摘） |
| **设计意图未写清** | `lock_*.ts` | **文档**（描述该改） |
| **判据够不着** | `hat_*` 10 处、透传给 engine/impl | **判据缺陷**（本单的最大收获） |

**⇒ 「死参数」这个词本身是**判据的结论**，不是代码的属性。**
22 处里 18 处是判据的结论错了 —— **这正是判例-32 要防的「探针不会认」。**

### 我这一单踩的 5 个坑（每个都真实发生过）

| # | 坑 | 后果 | 修法 |
|---|---|---|---|
| 1 | 字典 `setdefault` 让同名工具互相覆盖 | 漏报 | 改 list |
| 2 | 子串匹配 `agent in handler` 被 `agent_touch_first_seen(` 命中 | **假活** | 只匹配带引号 `"agent"` |
| 3 | **括号配平不跳字符串** | `instrumented_tool` 描述里的 `)` 提前闭合块 ⇒ **假死** | 配平时跳过字符串与注释 |
| 4 | 透传给 `xxx(args)` / `engine.yyy(args)` | **假死**（本单 14 处） | 跟透传或升到全仓 |
| 5 | 取值函数白名单不全（`jnum`/`get_json_text`/`jget`/`arg_str`） | **假死**（4 处） | 从全仓 grep 反推完整族 |

**⇒ 坑 3 是判例-34 的同族：块**边界**算错，导致「handler 里没有」这个读数本身是假的。**

---

## 缺口与风险

- **R1** `loop_create.items` 该摘 schema（唯一 B 类）—— **未修**（`server.mbt` 归 Beta）
- **R2** `lock_acquire.ts`/`lock_renew.ts` 描述「可选，默认当前时间」**误导**（实际永远服务端盖章）
  ⇒ 建议改为「**时间戳由服务端盖章**（BUG-33），此字段仅为兼容保留/不接受覆盖」
- **R3** 我的判据**仍然只能扫 `src/server/`** —— `cost_budget_check` 的参数在 `@engine` 侧读
  ⇒ 任何「死参数」结论**必须**先确认参数没被透传给别的包
- **R4** 「透传给 helper/engine」是**主流写法**（`hat_*`×3、`cost_budget_check`、`mcp_config_scaffold` 等）
  ⇒ **单包内的死参数判据天然会大量误报**，做判据前必须先处理透传
- **R5** 本单**未再 `report_bug`** —— 3 处里没有「该接线」的 bug（与 BUG-472/473 性质不同）

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-28-dead-params-triage-report.md` |
| 只读脚本 | `temp/audit/lane_cs_{v3,final,evidence}.py`（六向标定版本） |
| 该改 | `loop_create.items` 摘字段；`lock_*.ts` 描述改写（均需 `server.mbt` owner） |
| 该记 | 判据坑清单（§分析）应并入 `BUG-472/473` 的修复说明 —— **别再让下一个人重踩** |
| 修正 | 我上一单报告的「22 处」应更正为「**3 处**」；`BUG-472`/`BUG-473` **不受影响**（二者经人工复核确认） |
