# 4pools 提案差距分析（Lane DK · R36）

> 司令-γ · 2026-10-29 · 只读（未改 `src/`）· 提案 `docs/plans/2026-10-26-4pools-rhop-roadmap-proposal.md`（111 行）

## 结论

**⇒ 该推迟（不是驳回）。回答那一句**：
> **能推进吗？** 不能按提案原样推 —— 「阶段二」大部分已被 3 天内的并行工作做完（提案不知道），
> 真正缺的那步（`ops_commissar` 接线）**不在它三阶段任何一格**。
> **第一步是什么？** 给 `src/ops/ops_commissar.mbt` 补 **1 格白盒锁 + 1 个 MCP 工具**，
> 并把它的 **10 处 `println` 改成 `eprintln`**。
> **验收**：两个独立进程经 `.fist-mbt/pool/` 交换一条消息，回执在 `call_log` 可见。
> **缺什么？** 缺「接线 + 测试」，不缺实现；另缺 `rhop_native` 真实实现（卡住生产部署）。

## 四个读数

### ① rx-mbt 在哪、rhop 实现了多少

**位置**：`../rx-mbt/rhop`（在）

| 读数 | 值 |
|---|---|
| 文件 / 行数 | **29 个 `.mbt` / 12 787 行** |
| 测试 | **0 个** |
| 提案点名的 4 个 | `cipher.mbt` 40 · `packet.mbt` 95 · `rhop_js.mbt` 194 · `rhop_native.mbt` **47 = stub** |

**提案没提但已存在 25 个**（含 `envelope` `signer` `integrity` `relay` `session` `watch`
`transport_*` ×4 `mirror` `daemon` `online` 等）—— 提案表格要补的东西**大多已在**。

**`rhop_native.mbt` 是 stub（47 行）**：文件头自述「native 目标占位 / MoonBit core 无文件系统 API」，
三个函数全部「`println` 一句 + 返回空/error」，**无真实实现**。

**⇒ 提案「仅实现一点点」已过时**（列 4 个，实际 29 个 / 12787 行）；**但 native 仍是 stub 且零测试。**

### ② 池子目录建了吗
- `.commissar/` — **不存在**（提案称其为「同机消息池雏形」）
- `.fist-mbt/pool/` — **存在但 0 文件**（空壳）
- `fist-mbt/pool/`（共享侧）— **不存在**

**⚠️ 但“池子”能力已以另一形态存在**：`src/ops/ops_commissar.mbt`（**275 行 / 11 函数**）
已真实调用 `@rhop.rhop_send` / `@rhop.from_filesystem_with`，含 `commissar_send` / `commissar_tick` /
`commissar_watch` / `CommissarSignal`。fist-mbt **已接入** rx-mbt
（`moon.mod:34` `RX-MBT@0.3.0`；`src/ops/moon.pkg:4` `rhop`）。

**⇒ 缺口不是「没实现」，是「有实现但没接出来」：0 白盒测试、0 MCP 工具。**

### ③ vools-rhop 参考在不在

**在**：`../vools/rhop`（Python，`vools/rhop/` 包 + `tests/` **34 个 `test_*.py`**）。

**⚠️ 提案 §七 引用的 `analysis/rhop-PLAN.md` 实测不存在** ⇒ 「优秀实践基线」无从对照。

### ④ 提案三阶段的验收判据

**写了，且比多数提案好**（§六里程碑 + §五判据 1-5）：

| 阶段 | 提案的完成标志 | 我的判定 |
|---|---|---|
| **M1** | 「本文档定案，4 池目录在 `.fist-mbt/pool/` 与 `fist-mbt/pool/` 创建完毕，README 说明流转规则」 | **弱**：空目录也算过 |
| **M2** | 「rx-mbt/rhop 补齐 P0 项（密钥派生/签名完整性/shared path 多端/在线离线回退/heartbeat），js 目标 `moon test` 全绿」 | **空真**：rx-mbt **0 测试** ⇒ 「全绿」= 0/0 |
| **M3** | 「fist-mbt 接入 rhop，4 池工具走通同机收发 + 跨机 shared path 同步；对照 vools-rhop 判据 1-5 全过」 | **最好**，5 条可机器化 |

**⇒ 判据不缺，但 M1 弱、M2 空真（0 测试 ⇒ 全绿=0/0）。**

---

## 缺口

- **R2** `rhop_native.mbt` 是 stub ⇒ **只有 js 可跑，原生部署不可行**。
- **R4** `ops_commissar.mbt` 有 **10 处 `println`** —— 当前未接 MCP 所以还不污染 stdout；
  **一旦接成工具必须先改 `eprintln`**（见 BUG-477 判据）。
- **R5** `ops_commissar` 零测试，275 行无锁。

---

## 建议入档位置

- **建议**：提案 §一「现状」标注已过时并指向本报告；M2 补「先有测试」前置
- **第一步**：见 §结论（`ops_commissar` 补 1 锁 + 1 工具 + `println`→`eprintln`）
