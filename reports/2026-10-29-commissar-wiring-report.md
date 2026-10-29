# `ops_commissar` 接出来：只接 send，不接 watch

> 2026-10-29 · Lane DL · 4pools 第一步 + BUG-480 规避

---

## 结论

**问题：`ops_commissar` 现在接出来了吗？4pools 提案的 M1 里程碑可以算过了吗？**

> **接出来了 —— 但只接了一半，而且是刻意的一半。**
> **M1 不能算过：`send` 侧通了，`watch` 侧被 BUG-480 挡住。**

| 项 | 结果 |
|---|---|
| 10 处 `println` → `eprintln` | ✅ **10/10 改完**，零残留 |
| 白盒锁 | ✅ **3 格**（L1 落盘 / L2 同步解码 round-trip / L3 变异对照）|
| MCP 工具 | ✅ **`commissar_send` 已注册，带 `namespace`**；**`commissar_watch` 刻意不注册** |
| 177 → 178 五处同步 | ✅ 全部对齐 |
| `check_mcp_stdio_purity.py` | ✅ **rc=0**（L1 静态 / L2 / L3 全过）|
| 全量测试 | ✅ **1894/1894 passed, 0 failed** |

---

## 证据

### ① 先拆弹（10 处 println）

```
改前行号：125 153 201 210 220 228 229 232 248 250
改后：eprintln 计数 = 10 ｜ 裸 println 残留 = 0
```

**两轮才改完**（诚实记录）：第一轮正则只锚定行首，改了 5 处；
另外 5 处不在行首（`_ => println(...)` / `fn(...) { println(...) }`）⇒ 第二轮用 `(?<![e\w])println\(` 补齐。

**同族普查**：`grep -rn "println(" src/ops/ | grep -v eprintln` ⇒ 只有 `ops_commissar.mbt` 这 10 处
+ `rhop_native_wbtest.mbt` 1 处（**测试文件，不接 MCP，不污染生产 stdout**）。

### ② 白盒锁（3 格，211 passed / 4 秒退出）

| 锁 | 内容 |
|---|---|
| **L1** | `commissar_send` ⇒ `.rhop` 文件**真的落盘**（断言文件数 > 0，不是「函数没崩」）|
| **L2** | 同步解码 round-trip：读盘 → `RhopEnvelope::decode` → `RhopCipherNone::decrypt` → `RhopPacket::from_json_text` → `CommissarSignal::from_json`，**两字段都断言** |
| **L3** | **变异对照**：「没发送」等价态下 L1 的判据必须为假 ⇒ send 变 no-op 时 L1 必红 |

**⚠️ L2 判据降级了**（lead 已确认接受）：
它证明「rhop 能解码落盘的消息」，**不是**「订阅回调会触发」。
后者当前**无法测** —— BUG-480：`from_filesystem_with` 在 js 后端不可取消。

### ③ 挂起的完整根因链（三探针实测）

| 探针 | 内容 | 结果 |
|---|---|---|
| **P1** | 只构造 Observable，不订阅 | ✅ 4 秒退出 |
| **P2** | 订阅 + **立刻 `dispose()`** + 断言 `is_disposed()` | ❌ **121 秒被 SIGTERM** |
| **P3** | 纯同步读（不碰 watcher）| ✅ 4 秒退出 |

```
watcher_js.mbt:71   fs.watch(path, { persistent: true })   ← 持有 event-loop handle
rx/RX-MBT.mbt:82    Subscription::dispose() → 执行 dispose_fn
rhop_js.mbt:92      let sub = @monitor.watch_folder(path).subscribe(...)
rhop_js.mbt:132     Subscription::new(fn() { sub.dispose() })   ← 但 fs.watch 没被 close
```
**⇒ 有取消面，但取消不生效。BUG-480。**

### ④ 工具注册（`commissar_send`）

参数：`project_dir` / `kind` / `target` / `text`（必填）、**`namespace`**（可选，默认 `default`）。

工具描述里明确写了：
> ⚠️ **本工具只发送，当前版本不提供 watch / 订阅能力** —— 底层 `from_filesystem_with`
> 在 js 后端不可取消（见 **BUG-480**），**订阅会让 server 进程永不退出** ⇒ 接收侧请同步读取。

**`commissar_watch` 不注册** —— 按你的判断：MCP 工具一旦注册就等于对外承诺「这个能力可用」，
接一个一调就死的工具比不接更糟（调用方不知道它是自杀按钮）。

### ⑤ 两进程实测（Gamma 验收标准）

```
进程 A（MCP server）：commissar_send
  回执 {"ok": true, "kind": "reminder", "target": "dl-e2e-agent", "namespace": "dl-e2e", ...}

进程 B（独立进程）：同步读取 .commissar/events/*.rhop → 解码
  envelope.v = 1 | alg = none
  packet.id  = sig-1793243540964-0
  packet.payload = {"kind":"reminder","target":"dl-e2e-agent","text":"two-process-msg-2026","ns":"dl-e2e"}
  ★ 另一进程解码后 payload 一致: True
```

**⇒ 两个独立进程经 `.commissar/events/` 交换了一条消息。**

### ⑥ 五处同步（177 → 178）

| 面 | 状态 |
|---|---|
| `server.mbt` 头注释 | 178 tools |
| `README.md` 正文 ×2 | 178 个 MCP 工具 |
| `README.md` **分组标题和** | 看板·DAG·规划 **30 → 31**（和 = 178）|
| `README_EN.md` | 178 tools + 3 resources + 2 prompts |
| `docs/deliverable.md` | 178 个 MCP 工具 |
| `AGENTS.md` | 分组 27 → 28 + 工具表加 `commissar_send` 行 |
| 插件态 | `gen_plugins` 178 工具 / 4 宿主 / 64 文件 |

⚠️ **分组标题是我第一轮漏掉的** —— `gen_plugins` 报 `README 分组和 177 != 实测 178` 才抓到。
判据比 `check_tools_sync` 更严（你 R25 的提醒再次应验）。

---

## 分析：为什么「有实现没接出来」比「没实现」更难发现

**没实现** ⇒ `grep` 找不到、编译报错、调用方拿不到工具。**它有一个明确的失败点。**

**有实现没接出来** ⇒ 代码在、测试绿（零覆盖也是绿）、编译过、`moon test` 全过 ——
**每一个判据都说「好的」**，只有「工具的 `tools/list` 里有没有它」这一件事是假的。

⇒ 它与判例-33「服务本体 ≠ 服务接入」**完全同族**：
**「这个功能被实现了」与「这个功能被交付了」是两件事**，而用户只感知后者。

**⇒ 而本单又叠了一层**：`ops_commissar` 就算接出来，**`watch` 侧一接就是自杀**
（BUG-480）。⇒ 「接出来」不等于「全部接出来」——
**接一半并说清为什么不接另一半，比接全了一个月后发现进程杀不掉要好。**

---

## 缺口与风险

| # | 项 |
|---|---|
| **R1** | 🔴 **`commissar_watch` 未接**（BUG-480 挡着）。这不是「忘了」，是「不该接」。**修 BUG-480 后应补接** |
| **R2** | **L2 判据降级**：证明「rhop 能解码」，不证明「订阅回调会触发」。**BUG-480 修好后应补一格订阅式锁** |
| **R3** | `ops_commissar` 仍有 8 个函数未接（`commissar_tick` / `commissar_watch` / 目录工具等）。按你的要求**只接 1 个**，其余待评估 |
| **R4** | 实测中撞到三次环境问题（记录以备后人）：①运行 `_build` 是旧产物 ⇒ `Tool not found`（判例-32）；②`moon build` 后 ESM shim 丢失 ⇒ `require is not defined`（判例-33 第二条）；③`@monitor.watch_folder` 的 `persistent:true` 是挂起根因 |
| **R5** | 最小复现文件 `dlp_watcher_probe_wbtest.mbt` **已删除**（含必然挂起的格，不能留仓）。复现过程写在本报告 §③ |

---

## 建议入档位置

**账本 BUG-480**（已由 lead 开单）：本单的 P1/P2/P3 三探针 + 源码链是它的证据面。

**4pools 提案 M1**：**不能算过** —— `send` 通了、`watch` 被 BUG-480 挡住。
建议 M1 拆成 **M1a（send 侧，已过）** 与 **M1b（watch 侧，阻塞于 BUG-480）**。

**判例候选（lead 已确认并归入判例-29 家族第 5 位）**：
> **「资源释放」的调用成功 ≠ 资源真的释放了。**
> `dispose()` 返回 void、`is_disposed()` 返回 true —— 但底下 `fs.watch` 仍然 `persistent: true`。
> **⇒ 判「有没有泄漏」必须看进程能否退出，不能看 dispose 有没有被调用。**

**另一条（关于方法，不是关于 dispose）**：
> **证伪自己的假设，先跑最小复现，不要先改代码。**
> 我把 `dispose()` 当成「应该够了」，改了一版、编译过、`is_disposed()` 也返回 true ——
> **看起来完全正确**。而证伪只需 20 行 P1/P2/P3。
> **⇒ 当「修好了」和「没修好」都能编译通过时，先做那个 20 行的实验。**
