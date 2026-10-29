# MCP stdout 纯净性判据（BUG-477）

> 司令-γ · 2026-10-29
> **这是给我自己那个 R33 bug 立的机械化防线。**
> 我在 BUG-476 给 `run_server()` 加了一行 `println`，**整个 MCP server 对所有客户端不可用**，
> 而同一时刻 `moon test` **1835/1835/0 全绿** —— 判例-33 的完美实例。

---

## 结论

| 项 | 结果 |
|---|---|
| **三层都做了吗** | **✅ L1 静态 + L2 动态握手 + L3 动态 tools/call** |
| **selftest** | **19/19 格**（含 6 个变异对照 + 2 个反脱锚） |
| **变异实测** | **L1 ✅ 精确命中 `server.mbt:1885`；L2 ✅ stdout 第一行 `POLLUTION-PROBE`** |
| **全仓读数** | **L1 干净（38 文件 / 175 工具）· L2 stdout 2 行全合法 · L3 `result.content` 在** ⇒ **rc=0** |

---

## 证据

### §1 三层各自抓什么（为什么缺一不可）

| 层 | 抓什么 | 盲区 |
|---|---|---|
| **L1 静态** | `src/server/**/*.mbt` 里写 stdout 的调用 | **看不见依赖库里的 print** |
| **L2 动态·握手** | 用**生产启动描述** spawn，断言 **stdout 每一行**都是合法 JSON | 只覆盖**跑到的路径** |
| **L3 动态·工具** | 发 `tools/call`，断言 **`result.content` 存在** | 同上 |

**⇒ 静态快但不完整；动态完整但慢且只覆盖跑到的路径。**

### §2 按**语义**写，不按 `println` 这个字面写

抓的是「**往 stdout 写了非 JSON-RPC 的东西**」，`println` 只是最常见形态：

| 形态 | 判为污染 | 处理 |
|---|---|---|
| `println` / `print` / `print_char` | ✅ | L1 静态 |
| **依赖库自己 print** | ✅ | **只有 L2 动态能抓** |
| `eprintln` / `eprint` | ❌（走 stderr） | 剔除，不误报 |
| **字符串里的 `"println(...)"`** | ❌ | `strip_strings()` 抹掉内容 |
| **注释里的 `// println(...)`** | ❌ | `code_lines()` 跳注释 |

### §3 判例-33 硬要求：用生产启动描述

```python
launch = load_launch(root)   # 原样读 .mcp.json 的 command + args
# 拿不到 ⇒ rc=2（无法自证），**不降级猜测**
# 只有显式传 --allow-fallback 才退回 cli.js，且输出里明说降级
```
实测读到的就是生产的：
```
node C:\Users\victo\AppData\Local\FIST-Mbt\serve-launcher.cjs serve
```

### §4 变异实测（真跑）

**M1 · L1 静态**：往 `server.mbt:1885` 插 `println("POLLUTION-PROBE")`
```
✗ src/server/server.mbt:1885  println("POLLUTION-PROBE")  // ★变异
rc=1
```

**M2 · L2 动态**：同一变异，重新 `moon build` 后跑生产启动器 ⇒ stdout **第一行非 JSON**：
```
[0] **非JSON** 'POLLUTION-PROBE'
[1] JSON '{"jsonrpc":"2.0","id":1,"result":{...}}'     非 JSON 行数: 1
```
**⇒ 两层各自独立抓到同一污染，且 L2 抓的是「真的跑起来的那个进程」。**

**恢复后：L1 干净 / L2 2 行全合法 / L3 content 在 ⇒ rc=0 ✅**

### §5 selftest 19 格

| 组 | 格数 | 内容 |
|---|---|---|
| 形态识别 | 7 | `println` / `print` / `print_char` 判污染；`eprintln` / `eprint` / 注释 / 字符串内 判干净 |
| **变异对照** | 7 | `println` 检出（含行号）· 字符串诱饵不报 · 注释不报 · 干净样本 0 报 · 见到文件/工具 |
| **反脱锚** | 2 | 无 `src/server/` ⇒ **rc=4**；有目录但 0 个工具 ⇒ **rc=4** |
| L2/L3 判定 | 3 | 合法 JSON ⇒ 0；**污染行 ⇒ 1**；空输出 ⇒ 2 |

### §6 过程中踩的两个坑（都已修）

1. **L3 探针用错工具**：原先用 `version` —— 它是 **CLI 子命令**不是 MCP 工具，回执 `Tool not found` 被判成 L3 脏（**假红**）。改用 `mode_list`（纯计算、零参数、零副作用）。
   **⇒ 判例-32 同族：探针名要先在新鲜样本上标定，不能凭印象挑。**
2. **构建被 `temp/` 残留夹具阻塞**（`temp/k463_*` 等），`moon build` 报 `Unable to fetch info for packages`。清理后正常。

---

## 分析：为什么静态与动态**必须都做**

**一句话：它们抓的不是同一个集合。**

```
L1 静态能抓 = {源码里明写的 stdout 写入}            ⊂ 全部污染
L2 动态能抓 = {实际跑起来时写进 stdout 的东西}       ⊃ L1（含依赖库 / 生成代码）
```

| 场景 | L1 | L2 |
|---|---|---|
| 有人写 `println` 在 `src/server/` | **✅ 抓到** | ✅ 抓到（若跑到） |
| 依赖库内部 print | ❌ **看不见** | **✅ 抓到** |
| 某条只在特定分支才走的 print | ✅ 抓到（源码里有） | ❌ 没跑到就不报 |
| 生成代码/宏展开产生 print | ❌ | ✅ |

**⇒ 只做静态 = 依赖库打印会漏；只做动态 = 没跑到的分支会漏。**
**两者的盲区互补，所以三层都要。**

**这与 R33 是同一件事**：`moon test` 走引擎层 API、**不经过 stdio 传输** ⇒ 结构上看不见。
**本判据是唯一一条真的去看「进程 stdout 里出现了什么」的尺。**

---

## 缺口与风险

- **R1 L2/L3 只在跑 `serve` 子命令的客户端态成立** —— 若将来 MCP 改用 HTTP/SSE 传输，
  本判据的 L2/L3 **不再适用**（需换探测面）。
- **R2 L1 只扫 `src/server/`** —— `cmd/cli/` 的 `println` 是**对的**（CLI 输出就该走 stdout），
  故意不扫。但若有人把 server 逻辑挪到别的包，L1 会漏（L2 仍能抓）。
- **R3 L2 超时 60s** —— 超时判 rc=2（不自证）而非 rc=1（脏），方向正确。
- **R4 `--static-only` 是 CI 快速档；它等于放弃 L2/L3**。电池跑的是**完整三层**。
- **R5 动态层会真的 spawn 一个 server 进程** ⇒ 电池比纯静态慢（约 3~5s）。

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-29-mcp-stdio-purity-report.md` |
| 判据 | `scripts/check_mcp_stdio_purity.py`（19 格 selftest） |
| 执行面 | `scripts/run_guards.py`：`case(判据)` + `case(判据, "--selftest")` 两格（判例-5） |
| **该记** | 判例-33 的**第一条可执行尺**：从此「stdout 被污染」不再只能靠人肉连客户端发现 |
