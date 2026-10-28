# 死参数判据 `check_dead_params.py`（BUG-474）

> 司令-γ · 2026-10-28
> **一句话**：上一轮手工普查报 22 处、人工核实后只有 3 处是真的（**19 处是判据缺陷**）。本判据把 5 个坑**编码成代码**，并学会**在判不了的地方主动沉默**。

---

## 结论

| 项 | 结果 |
|---|---|
| **判据怎么写的** | 切工具块（list）→ 切 schema/handler → 找取值点（带引号 + 去空白 + 完整取值函数族）→ 透传检出即 `opaque` |
| **5 条纠正都在代码里吗** | **✅ 全部在代码里**（不是注释），每格配一个 selftest 变异对照 |
| **全仓实测是否 3 处** | **✅ 是**（`loop_create.items` B 类 + `lock_acquire.ts` / `lock_renew.ts` C 类） |
| **selftest / 电池** | **14/14** · `expected(...,1,kind="known-red")` + `--selftest` 格 |

---

## 证据

### §1 五条纠正的代码位置

| # | 坑 | 后果 | **代码** |
|---|---|---|---|
| ① | 字典 `setdefault` 同名覆盖 | 漏报 | `blocks()` 返回 **list** |
| ② | 子串匹配被 `agent_touch_first_seen(` 命中 | **假活** | `is_read()` 只认**带引号** `"P"` |
| ③ | **括号配平不跳字符串** | **假死** | `match_paren()` **状态机**跳过字符串/行注释/块注释 |
| ④ | 透传 `foo(args)` / `engine.y(args)` | **假死**（14 处） | `is_opaque()` ⇒ 标 **`opaque`**，**一律不判死** |
| ⑤ | 取值函数白名单不全 | **假死**（4 处） | `reader_family()` **从全仓 `fn` 定义反推** |

**坑③ 是核心**：描述字符串里含大量 `)` ⇒ 纯计数会让块中途闭合 ⇒ handler 被截断 ⇒ 假死（实测 `laya_decide` 切完 handler 只剩 409 字符）。

### §2 ④ 的设计：**不知道比猜错好**

```
[opaque · 主动沉默] 这些工具的 handler 整包透传 args ⇒ 参数在别处读，**不判死**
当前读数：读取干净 127 · opaque 30 · 死参数 3
```

**静态判不了的，报 `opaque` 而不是猜。** 会说「我不知道」的判据比自信误报的判据有用 —— 后者让人去修不存在的问题（上一轮 19 次）。

### §3 全仓实测（= 人工审核结论）

```
✗ server.mbt:3974  loop_create   未读：items      (B 类：该摘 schema)
✗ server.mbt:6113  lock_acquire  未读：ts         (C 类：BUG-33 服务端盖章)
✗ server.mbt:6185  lock_renew    未读：ts         (C 类：同上)
```

### §4 selftest 14 格（5 个坑各一格变异对照）

| 格 | 验什么 |
|---|---|
| `dup-tool-both-kept` | 坑①：两个同名工具都保留 |
| `substring-not-counted-as-read` / `quoted-literal-counted` | 坑② |
| `block-cut-once` / `handler-contains-reader` | 坑③：描述含 `))))` 也只切一个块，且 handler 完整 |
| `opaque-foo-args` / `opaque-engine-args` / `not-opaque-normal-read` | 坑④ |
| `jnum-counts` / `get_json_text-counts` / `never-read-still-dead` | 坑⑤ |
| `multiline-call` | 换行调用 |
| `strip-comments-removes-param-name` / `strip-comments-keeps-code` | 注释剥除 |

### §5 过程中**又踩到 3 个新坑**（都已修 + 都有 selftest 格）

| 新坑 | 后果 | 修法 |
|---|---|---|
| `opt_challenge(args)` 一次读两参，外形像透传 | `lock_acquire` 判 opaque ⇒ 漏真死参数 | `MULTI_READERS` 排除+计入读 |
| `fn(args : Json)` 是 handler **自己的签名** | 当透传 ⇒ 同样漏判 `lock_acquire` | `SELF_SIG_RX` 先抹掉 |
| `m.get("P")` 解构读 | `loop_create.stop_on_*` 判死 | `.get("P")` 计入读 |

**⇒ 「判据自己会腐烂」是常态**：写判据的过程就是不断发现新坑的过程。

---

## 分析：为什么「死参数」判据天然易误报

**因为「读到参数」这件事在 MoonBit 里有至少 6 种写法**，而判据是**静态文本匹配**：

`get_str(args,"P")` · `get_int(args,"P",default=1)`（第三参）· `get_json_text` / `jnum`（非白名单函数）· `m.get("P")` / `args["P"]`（解构/索引）· `foo(args)` / `@engine.y(args)`（整包透传）· 换行调用。

**⇒ 每漏一种写法就产生一批假死；每多认一种就有假活风险。**

**所以判据的正确目标不是「全部判出来」，而是**「判出来的都是真的，判不了的自己说判不了」**。
这就是 `opaque` 存在的理由 —— 本判据对 30 个工具**主动弃权**。

### 判据成熟度三层

1 能判出东西 → 2 判出的**都是真的**（零假死，本判据 3/3 与人工一致）→ 3 **知道自己哪里判不了并说出来**（30 个 opaque）。**上一轮的手工脚本停在第 1 层，本单推到第 3 层。**

---

## 缺口与风险

- **R1** `opaque` 的 30 个工具**本判据完全看不见** —— 它们里可能还有死参数
  （已知 `cost_budget_check` 就在其中，人工核实过是安全的，但其余未逐个看）
  ⇒ **本判据 rc=0 时不能说「没有死参数」，只能说「看得见的都干净」**
- **R2** 现有 3 处**未修**（`server.mbt` 归 Beta）⇒ 判据上线时如实报 `known-red`
  - `loop_create.items`：摘字段
  - `lock_acquire.ts` / `lock_renew.ts`：描述改为「**服务端盖章、不接受覆盖**」
- **R3** `reader_family()` 从 `fn` 定义反推，若某取值函数**只写调用不写定义**（外部包），
  就反推不出来 ⇒ 当前靠 `READER_FALLBACK` 兜底
- **R4** `local_helpers()` 用 4000 字符近似取函数体 ⇒ helper 超长会截断
- **R5** 未跑 `moon fmt`（本机 BUG-388）；判据是 `.py`，不受 fmt 门约束

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-28-dead-params-judge-report.md` |
| 判据 | `scripts/check_dead_params.py`（14 格 selftest）· 提交 `1c38c6cb` |
| 执行面 | `scripts/run_guards.py`：`expected(..., 1, kind="known-red", why=...)` + `case(..., "--selftest")` |
| 锚点 | `scripts/README.md` `rulers=128 battery=87 gate=95`（`check_battery_count_doc` PASS） |
| **该记** | §5 三个新坑已写入判据头部 docstring |
