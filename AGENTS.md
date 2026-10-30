# Project Agents.md Guide

> ⚠️ **本文件有字节预算（R211 发现 / R212 已修）**：harness 对工作区指令的注入上限是 **65,244 字节**，
> 超出部分**任何 agent 都读不到**（R211 实测曾有 10 个章节不可见，含 `## 路径约定`）。
> **R212 已把 MCP 工具清单整块搬到 [`docs/AGENTS-mcp-inventory.md`](docs/AGENTS-mcp-inventory.md)**
> （逐字保留，需要时 read 打开）⇒ 本文件现 **51,277 字节 / 472 行，全部可见**。
> **新增内容请放前部、并先跑** `python scripts/check_instruction_budget.py`（逐条列出被截章节，`--strict` 才判红）。
> **没人读到的规则等于没有规则。**

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

本地已克隆 MoonBit skills 仓库，技能可直接从本地读取：
`<本机 moonbit-skills 克隆路径>`（结构：`skills/<name>/SKILL.md`，进入项目会话时按需加载其中的技能）。

## FIST 指挥官模式（默认行为）

本项目是 **FIST-Mbt** —— **AI 自驱式开发的项目管理者**：用纯 MoonBit 重写的 FIST 指挥官任务分配体系，同时作为 MCP Server 暴露给 AI 客户端。
一等的打磨对象只有两件——**自驱** 与 **递归拆解**；而本项目迭代自己所用的，正是这两件能力（工具面见「自我记忆与自进化」「开发模式与模板」两节，实证面见文末「实证伴生仓」段）。

在此项目中启动 AtomCode 会话时，**默认启用 FIST 指挥官模式**：

### 角色边界（金条四）
- 你**不亲力亲为**可分配的具体工作（写代码、查资料、跑长命令）→ 交给子代理
- 你**亲自做**：理解用户意图、决定分流、写任务包、终审结果、沉淀记忆、汇报
- 不可逆操作（删除、发布、合并代码）→ 只给"方案 + 预案"，执行权留在指挥官或用户确认

### 分流决策树
1. **轻任务**（单文件修改、小重构、格式转换）→ 直接子代理
2. **中任务**（多文件、需要验证循环）→ 子代理 + 你终审
3. **重任务**（跨模块重构、新项目、PR/CI 闭环）→ 调 FIST MCP 工具发布任务
4. **不可逆任务**：出方案，挂起等用户确认

### 任务包格式
每个子任务必须带：目标 / 边界（只动哪些文件）/ 回传格式 / 验收标准

子代理回传强制格式（缺一打回）：结论 / 证据 / 分析 / 缺口与风险 / 建议入档位置

### 终审与验证（金条八）
- 所有子任务结果由你**终审**后才对外生效
- 不合格 → 带失败原因打回重做（最多 3 轮，超限挂起）
- 代码任务终审必须实际运行验证（`moon test` / `moon check`），不靠自述

### 记忆沉淀与汇报（金条五）
任务结束（终审通过后）立即：
1. 追加当日日志：`memory/YYYY-MM-DD.md`
2. 生成汇报：`reports/YYYY-MM-DD-<任务名>-report.md`
   必填：结果摘要 / 资源消耗 / 任务分配记录 / 遗留风险 / 后续建议 / 超额内容 / 来源

## Project Structure

- MoonBit packages are organized per directory; each directory contains a
  `moon.pkg` file listing its dependencies. Each package has its files and
  blackbox test files (ending in `_test.mbt`) and whitebox test files (ending in `_wbtest.mbt`).

- In the toplevel directory, there is a `moon.mod` file listing module metadata.

## Coding convention

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.

- Try to keep deprecated blocks in file called `deprecated.mbt` in each
  directory.

### Commit gate（提交门禁 · 本仓强制标准）

- **提交前必须运行 `moon fmt`**：所有代码改动（新增/修改的 `.mbt` 文件）在
  `git commit` 之前必须执行 `moon fmt`（全仓或至少对改动文件），并确认
  `moon fmt --check` 返回 0，未格式化不得提交。
- 严禁跳过格式化直接提交：CI 的 `moon fmt --check` 门会把未格式化代码判红
  （rc=255）。
- 版本差异说明：本地钉版 moon（**0.1.20261016**——`is` 模式匹配表达式为
  d799f56 适配此版引入，替代已移除的 is_ok/is_err）与 CI nightly（`latest`，
  观测到 0.1.20261012）分属不同 moon fmt 世代，输出可能不一致。以本地
  `moon fmt` 落盘 + `moon fmt --check` 通过为准；并发 WIP 收口后跑一次
  nightly 全仓重排，统一风格后即可撤销 `continue-on-error`、恢复 fmt 门强度。
- **本机 `moon fmt --check` 不可用（**BUG-388**，2026-10-22 实测）**：moon 0.1.20261016 的 `--check` 管线报 `_build/wasm-gc/release/format/…: No such file` + `fatal: cannot hash` 且 rc=-1，**与本仓无关的 3 文件最小工程同样复现** ⇒ 工具链缺陷。判它请用 `python scripts/check_fmt_gate.py`：`0` 干净 / `2` 不可测（拒绝判红也拒绝判绿）/ `1` 真格式差异；格式门权威面以 CI（Linux nightly）为准。
- 标准提交流程：`moon fmt` → `moon info && moon fmt`（同步 `.mbti`）→
  `moon test --target js` 全绿 → `git commit`。

### 提交纪律：`git commit` 必须带 `-- <明确路径>`（2026-10-24 立 · 判例-11 最终形态）

**单次并发索引事故在本仓一天内发生 8 次、5 个人（含统帅本人）。**

根因：`git add <A>` 与 `git commit` 之间存在**时窗**，别的 agent 在这段里 add 的东西会被一并
带走。实测最讽刺的一例发生在「提交解决这个事故的脚本」的那一笔 commit 里。

**两半法**（提交前看暂存面 `git diff --cached --name-only` + 提交后看落盘面
`git show --stat HEAD`）**能事后发现，但挡不住窗口** —— `git restore --staged` 回滚完又被塞。

**默认纪律**：

1. **`git commit` 必须带 `-- <明确路径>`** —— 事中阻止，不靠事后发现。
   ```bash
   git commit -F msg.txt -- path/a path/b
   ```
   **`-F` / `-m` 必须在 `--` 之前**：放后面会被当成 pathspec，实测报
   `fatal: <msg path> is outside repository` —— **错误信息完全指错方向**（看着像路径问题）。
2. **禁止 `git add -A` / `git add <目录>` / `git add <通配>`**：目录会把同目录下别人刚写的东西
   一起 add 进来，那是风控面不是便利面。逐个列文件。
3. 批量/正式提交用 **`scripts/commit_scoped.sh <msg-file> <path...>`**：它做 6 道校验
   （前置暂存面必须为空 → 逐个 add → 核暂存面 → 核 `numstat` 拒 `0 0` →
   `git commit -F msg -- <paths>` → 核落盘面）。

**为什么写进纪律而不只写进工具**：工具要人记得调用，纪律是默认行为。
**`--` 是一个词，记不住就没有防线。**

### 往 `scripts/` 加 `.py` 必须同批给执行面（2026-10-24 立 · 判例-5 同族）

**一天内 3 次踩中**（`tmp_audit_preservation_scan.py` / `commit_scoped.sh` / `badge_anchor.py`），
每次的后果都是 `check_battery_count_doc` **FATAL，全仓门禁停摆**。

往跟踪面加任何 `scripts/*.py`，必须在**同一笔提交**里给它一个执行面，三选一：
1. `case("x.py", ...)` 进电池；2. `expected(..., kind="diag"|"known-red")` 带理由；
3. `EXEMPT_RULES` 带理由（**仅限「被导入的共享模块 / 一次性工具」**）。

**更简单的办法：共享模块以 `_` 开头**（`_badge_anchor.py` / `_tool_registry.py` 已是惯例），
自动命中既有的 `("_", ...)` 豁免规则，**不需要新加豁免**。

判据自己会抓：`check_battery_count_doc` 报 `缺面清单：x.py` 就是漏了这一步。

### 新判据必须**拒绝未知旗标**（2026-10-29 立 · R207 · 同族实测四次）

**同一个缺陷在本会话被修了四次**，每次都是"新脚本扫了 `--flag in argv`、却不拒绝未知旗标"：

| 轮 | 脚本 |
|---|---|
| R197 | `check_bug_ledger_shape.py` |
| R198 | `check_mcp_stdio_purity.py` |
| R199 | `check_warning_ledger.py` |
| R206 | `check_known_red_until.py` |

**失效形态**：把 `--selftest` 拼成 `--self-test` ⇒ 条件不成立 ⇒ **落进真检查分支并可能回 rc=0**
⇒ 人以为"自检通过"，实际跑的是对真仓库的扫描。**自检开关拼错 = 静默失去自检。**

**硬要求**（三选一，写的时候就要有）：

1. **argparse**（天生拒绝未知参数）；
2. **白名单 + 未知即拒**：
   ```python
   _KNOWN = ("--selftest", "--list")          # 带值旗标只放旗标名
   unknown = [a for a in argv if a.startswith("-") and a not in _KNOWN]
   if unknown:
       print("[FATAL] 未知参数 %s —— 已知：%s（rc=2）" % (" ".join(unknown), " / ".join(_KNOWN)))
       return 2
   ```
3. 整体拒绝剩余参数（`if argv: … return 2`，`--selftest` 另行先处理）。

**两道防线各司其职**（别只指望其中一道）：

- **提交时** `scripts/_new_script_hygiene.py` 的 **A3** 给 advisory（**低精度**：实测 6/6 误报，
  因为 while 分派 / 整体拒绝这些合格形状它认不全）⇒ 看到它**先自己跑一次
  `python <script> --definitely-not-real` 确认**，再据它改代码；
- **落地后** `scripts/check_arg_face_strict.py` 是**行为级**真门（真跑、按结果判，已在电池里）。

判据自己会抓：`check_arg_face_strict` 报 "参数面没兜住 N 把" 就是漏了这一步。

### 变异对照必做（2026-10-24 立 · 判例-29/30）

**任何判据的 `--selftest`，必须至少有一格是「变异对照」**：把被测机制改坏，断言锁会红。
只断言「正常路径通过」的锁，证明不了它真在看。

两条硬要求，都来自实测踩坑：

1. **改坏的是代码，不是注释**（判例-30 自指假绿）：
   判据里写死一个模式串去匹配被测文件时，**模式串自己就在文件里** ⇒ 变异真代码后匹配仍然命中
   模式串 ⇒ **锁恒绿**（看起来在工作：有匹配、有断言）。修法：`^` 行首锚定 + 只比对真实赋值行
   + 变异后确认替换点落在代码而非注释（实测有过「同一串在全文出现 3 次、`str.replace(…,1)`
   替换到注释那处」⇒ **在错误的地方验了三次**）。
2. **机制格 ≠ 实现路径格**（判例-29）：测了「带某机制的 git/库调用」不等于测了「脚本自己的实现」。
   实测：`s10` 只测「带 `--` 的 `git commit`」，把脚本第 5 步的 `--` 删掉后它照样绿
   ⇒ 必须补一格**直接断言脚本源码里机制还在**。同族：判例-3「改名不是接线」。

**造竞态测试时不要用 `sleep` 抢时序**（判例-31）：慢则变成前置拦截、快则读到上一发残留 ⇒
**不可复现的锁 = 不可信**。改用「**确定性注入污染状态**」（如手工复刻两步、在两步之间直接写坏索引）。

### 判例-32：探针必须先在新样本上标定（2026-10-27 立 · BUG-428）

**被测对象的标识符可能被工具链变形。** 实测 MoonBit 的 JS 产物把标识符里的 `_` **逐字翻倍**：

```
grep -c  'omega_orphan_of_archived_parent'        cli.js → 0    ← 裸串（假红）
grep -cE 'omega_+orphan_+of_+archived_+parent\('  cli.js → 3    ← 容忍变形（真读数）
实际: function _M0FP411vicTop_…6engine35omega__orphan__of__archived__parent(t)
```

⇒ **裸字符串探针在「未变异的、新鲜的」产物上就会报「找不到」** —— 看着像「产物旧」，
实际是「探针不会认」。实测代价：BUG-417 的诊断因此误判 40 分钟（四个逻辑条件全查过、全部正常，
真因是「进程跑的是旧构建」而「判断旧构建的方法本身失灵」）。

**硬要求**（任何「grep 产物找符号」的判据，上线前必须做）：

1. **在新鲜样本上标定一次**：拿刚构建的产物跑一遍，确认探针**能认出来**（否则它的「找不到」没有意义）；
2. **容忍变形**：`_` → `_+`（或等价宽松式），且要求命中后紧跟 `(` —— 否则 bundle 里大量工具名**字符串**会误命中；
3. **反脱锚格**：符号被改名/删除时判 **`rc=4「尺子坏了」`**，**不是**判「被测对象旧」
   —— 判据自己的腐烂与对象的陈旧是两种结论，混为一谈会让下一个人去修错的东西。

**同族口径**：**版本号 PASS ≠ 代码新鲜。** 只比版本字符串的守卫
（`check_dist_snapshot` 的前身）在「快照版本 0.3.10 == moon.mod 0.3.10、代码是 3 天前的」时照样绿。
要比内容，不能只比号。落地见 `scripts/check_deployment_freshness.py`（48 格自检，7 处变异对照）
+ `scripts/_deployment_symbols.py`（探针单一真源）。

### 判例-33：自检要测「配置这根线」，不是「服务本体」（2026-10-27 立 · BUG-437）

**判据绿了整场，而生产入口一次都没起来。** `scripts/mcp_smoke.py` 一直 PASS（171 工具），
DSH 侧 `fist-mbt` 却恒报 `mcp-client(fist-mbt): server is disconnected` —— 因为 smoke 自己拼了
`[NODE, main_js, "serve"]` 直接拉 bundle，**绕过了 `.mcp.json` 那根真正出故障的线**
（`"command": "fist-mbt"` 在 Windows 无 shell 不可 spawn：裸名 → `ENOENT`，`.cmd` → `EINVAL`）。

⇒ 与判例-29「机制格 ≠ 实现路径格」、判例-32「版本号 PASS ≠ 代码新鲜」同族：
**「被测对象能工作」与「被测对象被正确接入」是两件事**，而用户只感知后者。

**硬要求**：任何「服务可用性」自检，必须用**生产配置的同一份启动描述**（`command` + `args` 原样）去 spawn，
不得自己拼一条更"好走"的路；绕路那一条只能在拿不到配置时当 fallback，且必须**明说降级**。

**第二条（同族不同面）：构建产物不是稳定属性。** 依赖「产物后处理」的东西
（ESM `require` 兼容层、`MOONC_OVERRIDE` 注入、`patch_esm_main.py` 这类补丁）**必须在每次启动时幂等重建**，
不能假设「上一次 build 之后它还在」。实测同一路径 `cli.js` 的 shim 在 **08:50 / 08:57 / 09:03 三次反复**
（并发构建各写各的）⇒ 不幂等的补丁等于没有补丁，且失效形态是「能启动、一用就死」（首次打库才崩），
比启动即崩更难判。**判据要盯「启动后真的用一次」，不能只盯 banner。**

**第三条（Windows 面）**：`spawn('x')` **不认 `.cmd`/`.bat`**（「node 18.20.2」起无 `shell:true` 直接 `EINVAL` —— 这是**行为变更版本**，不是地板声明），
也不认无扩展名的 sh 脚本。配置里写裸命令名**只在 POSIX 成立**。Windows 上要么写绝对 `node <js>`，
要么钉真 `node.exe`（PATH 首条常是 `dsh-desktop\harness\.desktop-bin\node.cmd` 垫片，
经 `cmd.exe` 转发会吞引号 —— BUG-380 同源）。

**落地**：`%LOCALAPPDATA%\FIST-Mbt\serve-launcher.cjs`（幂等补 ESM shim + 修双补丁 + debug/release 自动选 +
日志打**内容身份** mtime/size/sha8；**双路由**：`serve|version|demo|doctor|help` → MoonBit bundle，
其余 → `scripts/fist.py` 网关，网关子进程注入 `FIST_NODE=process.execPath` 避开 `node.cmd` 垫片）
+ `.mcp.json` 走 `node` + 该启动器 + 两份注册垫片（`~/.local/bin/fist-mbt.cmd` 与 POSIX `fist-mbt`，均委派它，
`.cmd` 另钉真 `node.exe`）；账本 BUG-437。

### 判例-34：**错误信息的指向 ≠ 错误的真实位置**（2026-10-28 立 · MoonBit 字符串拼接两次踩坑）

**同一天两次，都在 `src/server/server.mbt` 的 schema 描述上，都指向完全无关的位置。**

**坑 1（相邻字符串隐式拼接不存在）**：写
```moonbit
"第一行"
"第二行"
"第三行",
```
⇒ **2708 个级联错误**，第一条是 `The toplevel identifier boundary_probe is declared twice`
—— **所有顶层标识符都「declared twice」，且指向完全无关的文件**。

**坑 2（`+` 必须放行末）**：以为用 `+` 就对了，写成
```moonbit
"第一行"      ← 末尾没有 +
+ "第二行"
+ "第三行",
```
⇒ `Unexpected line`，**又指向 `schema(` 整块**。

**正确写法**：`+` 在**行末** —— `"第一行" +` / `"第二行" +` / `"第三行",`。

**⇒ 硬要求（判据）**：
1. **一个错误说「X declared twice」而 `grep` 只找到 X 一次** ⇒ **那不是 X 的问题**，
   是**解析器在别处失了同步** ⇒ **往前找**（离出错位置最近的、**我改过**的地方）。
2. **错误指向一个结构体/块的开头**（`schema(`）而里面某行"看起来对" ⇒
   **看那一行的行末**（少了 `+` / 少了 `,` / 多了 `"`）。
3. **改 9800 行的大文件前，先把片段写到 `temp/` 验语法**，贴完**立刻** `moon check`。

**同族口径（与判例-29/32/33 一脉）**：**工具给你的定位是「症状的位置」，不是「病因的位置」。**
判例-29 是「机制格 ≠ 实现路径格」、判例-32 是「版本号 PASS ≠ 代码新鲜」、
判例-33 是「服务本体 ≠ 服务接入」—— 本条是「**报错指向 ≠ 病因所在**」。

**代价实测**：Round 19 我把它误判成「并发编译把 `_build` 弄乱」，
理由是「`sleep 90` 后再跑就绿了」—— **真相是并发 lane 在 14:10:07 修好了我的语法**
（`95ea5106`）。**⇒ 「等一等就绿了」有三种可能**：别人 WIP 收口 / **别人修好了我的代码** /
缓存重建 —— **不能当成「我的判断被验证了」**，必须读 `git log` 看这几分钟里**有没有别人提交**。

**完整版见 `temp/moonbit_string_concat_pitfalls.md`**（两个坑 + 共同教训 + 流程建议）。

### 已知边界：`agent` / `assignee` / `executor` / **`created_by`** 是**自报的**，服务端无法验证（BUG-430 / BUG-464 · S1）

**这是安全性公告，不是安全措施。** 写在这里**不会**让系统更安全 ——
**在 S3（身份锚点）落地前，冒充风险不会消除。**

`reserve_scope` / `lock_acquire` / `claim` / `execute` 等工具的 `agent`（以及 `assignee` / `executor`）
都是**调用方自报的字符串**，服务端没有任何手段验证它真属于谁。

**还有一条更容易被漏掉的**：`publish` / `publish_parallel` / `dag_publish` 的 **`created_by`** ——
它是「人类指挥官特权入口」的准入凭证（`engine.publish` 硬检查 `created_by` 必须是 `human_steward`/`human`），
而 `created_by` **同样全仓零验证**（三处都是 `get_str(args, "created_by", default="human_steward")`）
⇒ **任何能调到 MCP 的人都能以指挥官身份在任意 ns 发布任务**（BUG-464 定夺：这**不是** ACL 缺陷，是 S1 同族）。

**⇒ 不能防有意的冒充**：任何调用方都可以把这个字段填成任意已登记的名字，
从而以那个身份取得该身份有资格取得的一切（预订、锁、任务认领、验收……）。

**具体后果**：
- 角色判定（Leader / HumanSteward 等）读的就是这个字符串 ⇒ **自称 `leader-xxx` 即可越过 Leader 级保护**；
- `reserve_scope` / `lock_acquire` 的互斥只保证「同一字符串不会被两人同时持有」，
  **不保证**「那个字符串背后是同一个人」；
- 回执里的 `role_source` / `agent_source` 只能告诉你**这个角色是怎么推出来的**，
  **不能告诉你**「这个 agent 是不是它自称的那个人」。

**分级（别把 S1 当成修复）**：
| 阶段 | 做了什么 | 是否改变安全属性 |
|---|---|---|
| **S1 公告边界**（本轮）| 工具描述 + 回执写明「自报、不可验证」 | **否**（只是让不安全**可见**）|
| S2 显式授权 | 未登记者被拒 | **否**（已登记者仍可被冒充）|
| **S3 身份锚点** | 签名挑战 / 验签 / 会话绑定 | **是**（唯一真正改变安全属性的一档）|

**BUG-430 第九段（2026-10-28）：有钥匙就必须出示（软强制降权）。**
agent 的 `pubkey_fp != ""`（自己选择登记了公钥）却**不传** `challenge` ⇒
角色按 **Executor** 算（fail-closed，不认它自称的角色），`role_source = "challenge_required"`，
回执 `action` 带 `+challenge_required`。**不传也不降级的只剩「根本没钥匙」的 agent**（零回归）。
⚠️ 这是**软强制**不是硬拒绝：降权让失败精确发生在「真正需要那个权限」的那一刻，
而 `+challenge_required` 让原因自解释；硬 `Err` 会让整条流水线停摆且原因难查。

**⇒ BUG-430 的关闭条件不是「S1 做完」，而是「存在至少一条『调用方无法自报』的路径」。**
S3 九段全落地 + BUG-466 取票窗口 + 本段软强制后，**该条件技术上已满足**；
但 `execute`/`verify` 仍未接 challenge、公钥按 ns 隔离、且**默认仍不要求认证**
⇒ 建议拆 `430a/430b`（FIXED）与 `430c`（仍 OPEN：默认要求认证的迁移路径）。

**BUG-470（2026-10-28）：`FIST_AUTH_MODE` 三档开关已落地（owner 批准 B）。**

| 值 | 对「有公钥但不出示」 | 对「无公钥且不出示」 | 备注 |
|---|---|---|---|
| **off**（**首次默认**）| **降权**（challenge_required）| **自报**（放行）| = 修前行为，逐字零回归 |
| **soft** | **降权** | **降权** | owner 批准的「策略 B」 |
| **strict** | **拒绝** | **拒绝** | 未启用，前置条件见决策单 |

⚠️ **`off` 不是「完全关闭认证」** —— S3 第九段的「有钥匙不传 ⇒ 降权」在 `off` 下**仍生效**。
`off` 关的只是「**对无钥匙者也降权**」这一层。为何这样定义：那一层是已上线的行为，
把它塞进开关里意味着「关开关 = 回退已交付特性」，那不是开关是倒车。

⚠️ **非法值回退 `off`（不是 `strict`）**：写错一个字母不该让现网停摆 ——
本开关的「严」档会让 56 个调用方失败，而回退默认只是维持现状。**配置写错 ≠ 环境不安全。**

⚠️ **默认值写在启动器里**（`%LOCALAPPDATA%\FIST-Mbt\serve-launcher.cjs` 的 `DEFAULT_AUTH_MODE`），
**不是只写在文档** —— 否则回滚时人要「想起来该设什么」。
⇒ **回滚 = 把 `DEFAULT_AUTH_MODE` 改回 `'off'` 或显式传 `FIST_AUTH_MODE=off`，实测 0.95 秒。**
⚠️ 读一次即缓存（不做热切）：热切要处理「一请求跨切换点」的语义漂移，而重启只需几秒 —— 用简单换正确。
真源 `src/engine/auth_mode.mbt`（`auth_mode()` 是**唯一** env 读取点，判例-29）；
白盒锁 `src/engine/engine_bug470_auth_mode_wbtest.mbt`（5 格 + 2 处变异对照）。

## Tooling

- `moon fmt` is used to format your code properly.

- `moon ide` provides project navigation helpers like `peek-def`, `outline`, and
  `find-references`.

- `moon info` is used to update the generated interface of the package, each
  package has a generated interface file `.mbti`, it is a brief formal
  description of the package.

- In the last step, run `moon info && moon fmt` to update the interface and
  format the code. Check the diffs of `.mbti` file to see if the changes are
  expected.

- Run `moon test` to check tests pass. MoonBit supports snapshot testing; when
  changes affect outputs, run `moon test --update` to refresh snapshots.

> 环境要求：新环境首次先 `moon update` 刷新 registry（依赖全公开，无私有包）；
> **moon 工具链 ≥ 0.1.20261016**（`is` 模式匹配表达式为 d799f56 适配此版引入，替代已移除的 is_ok/is_err——R29 升级）；
> **JS 目标需 Node.js ≥ 24**（项目默认 target，SQLite 后端依赖 `node:sqlite` 的 `returnArrays`，
> node <24 会退化为对象行导致列读取为空）。
> **常驻入口 spawn `moon` 统一带 `MOONC_OVERRIDE`**：`scripts/moon_env_probe.py`（R125）在本机自动发现
> `~/.moon-shim/shim.exe`（剥离 `\\?\` 前缀，绕 moonc 的 `Sys_error("\\\\?: Invalid argument")` ICE），
> 显式环境变量优先、非 Windows 原样透传；8 个入口已接线，静态普查与 `--selftest` 均在电池里。
> 见 README「环境要求」。
> **JS 可执行产物 ESM 兼容**：moonc ≥0.10.14 对 `cmd/cli` 输出 ESM，而 `mizchi/sqlite` 的 JS 桩用 CJS `require`，
> 直接 `node main.js` 会报 `require is not defined`。`scripts/mcp_smoke.py` / `demo.ps1` 启动前会自动调
> `scripts/patch_esm_main.py` 注入 require shim（幂等）；手动跑 server 请先 `python scripts/patch_esm_main.py`。

> **JS 测试在本机跑不起来？先看这一条（BUG-380 根因，2026-10-22 实测）**：
> `moon test --target js` 会把测试选择面作为**一整段 JSON 参数**交给测试产物；若 PATH 上的 `node`
> 落在 **`node.cmd` / `node.bat` 垫片**（例如 DSH 桌面端的 `%APPDATA%\dsh-desktop\harness\.desktop-bin\node.cmd`），
> 参数经 `cmd.exe` 转发会**吞掉引号**，产物收到残缺 JSON →
> `failed to parse args: Unterminated string in JSON`、`Error: failed to run test for target Js`。
> **对照实验**：同一 payload，垫片 rc=1「Expected property name or '}'」；真 `node.exe` rc=0 并正常打印
> `----- BEGIN MOON TEST RESULT -----`。⇒ 坏的是垫片转发，不是 moon、不是本仓、更不是测试代码。
> **常驻入口**：`python scripts/moon_test_env.py [moon test 的参数…]`——按目录内容剔垫片、校验真 `.exe`、
> 跑测试并核对汇总行；rc 契约 0/1/2（2=判据无法自证）；Windows 上另自动发现 `~/.moon-shim/shim.exe` 并设
> `MOONC_OVERRIDE`，绕开 moonc 的 `\\?\` 路径 ICE（工具链缺陷，见账本 BUG-380）。实测清理后全仓 **1959/1959 passed, rc=0**。
> **MCP 执行面同源（R126）**：`run_check` 走 server 的 js `spawn` 原语，server 被宿主直连 `node cli.js serve` 拉起时
> 不经过任何 Python 入口——原语层同样自动发现 `~/.moon-shim/shim.exe` 并注入 `MOONC_OVERRIDE`（显式 env 优先、
> 非 Windows 透传）；`run_check`/`executor_run`/`ocr_scan` 共用这一层，判据不再把工具链 ICE 记成任务失败。

### native 目标构建环境要求

> 全部项目 `moon.pkg` 已内置 native 链接 flag `options(link: {"native": {"cc-link-flags": "-lsqlite3"}})`，
> Linux 下直接可链接系统 SQLite；Windows 下按下列要求配置 sqlite3.h/sqlite3.lib 与 MSVC 环境即可。
> **JS 后端**：`moon test --target js` = **1959/1959**（2026-10-28 Windows 本机实测，四模式流水线自我迭代 Round 1~3 收口 + 一源四态 cl7 + 模型路由与外部执行器合并 + 多管家/supervisor 工具 + web 面板 M0 + 五语言接入示例 + CAF 属性测试与边界探针 + BUG-333 默认降噪锁等后续追加）。
> **Native 后端**：2026-10-01 在 WSL(Linux ubuntu-22.04) 实测 `moon test --target native -j 1` = **572/572**（工作树带既往构建残留时）；
> 同一 commit 的 `git archive HEAD` **干净树**上同一条命令必崩，根因见账本 BUG-133（依赖的 native FFI），
> 崩没崩由 `scripts/blackbox/e2e_native_heap_probe.py` 说话，不据任何旧数宣称双端同版全绿。
> **2026-10-01 owner 裁决③已落地**：CI 两条 native 臂（`ci.yml` `Test (native)` / `fist-ci.yml` `Test (native, j=1)`）前面
> 各挂一道同名门 `Native heap gate (BUG-133 探针当门)`，跑的就是上面那支判据（`--selftest` + `--runs 12`）；
> 只有 `crashes=0/12` 才放行全量测试。**步骤没删**，所以依赖侧修好后这一臂自己恢复覆盖，不需要再来改 workflow。
> 2026-10-02 那发权威 CI 是「门绿（#7/#8）而 `Test (native…` 红（#8/#9）」⇒ 全量那一格也补了一条 `::error::`
> 把根因与「门绿 ≠ 已修」写进 annotations，**退出码照原样传**（不挂 `continue-on-error`，红还是红）。

`src/store/store_sqlite.mbt` 依赖 `mizchi/sqlite`（native stub），其 `stub.c` 用尖括号 `#include <sqlite3.h>` 并 `#pragma comment(lib, "sqlite3.lib")` 链接系统 SQLite。

- **js 目标（MCP server 默认）**：无需额外安装，`moon test --target js` 直接可用。
- **native 目标**：需要系统 SQLite 开发库（`sqlite3.h` + `sqlite3.lib`）。Windows + MSVC 下：
  1. 下载官方 amalgamation（含 sqlite3.h/sqlite3.c），把 `sqlite3.h`、`sqlite3ext.h` 放进一个目录（如 `C:\sqlite-dev\include`），用 `cl` + `lib` 把 `sqlite3.c` 编译成 `sqlite3.lib`（放 `C:\sqlite-dev\lib`）；
  2. 编译/链接前在**同一会话**加载 `Enter-VsDevShell`（VS Build Tools）并追加 `INCLUDE`/`LIB` 指向该目录（注册表 User 级环境变量会被 moon 自发现的 MSVC 环境覆盖，不生效）；
  3. 之后 `moon test --target native` 即可通过。缺失时 `stub.c` 报 `fatal error C1083: 无法打开包括文件 "sqlite3.h"` / `LNK1104: sqlite3.lib`。
  一键装载上述环境（自动探测 VS + sqlite-dev）：`pwsh ./scripts/native-env.ps1`；
  Windows native 并行跑全量测试偶发 `0xc0000374`（堆损坏）—— **旧口径里「并行竞态、`-j 1` 串行可降低」两句已被 2026-10-01 实测推翻**：
  崩因是 `mizchi/sqlite@0.3.1` 的 native FFI 把 C 侧裸指针当 MoonBit 对象回传（BUG-133），**单进程也崩**，CI 的 `-j 1` 臂与不带旗的臂
  每次同红，串行不改变概率；判据 `python scripts/blackbox/e2e_native_heap_probe.py --runs 12`（探针不含本仓业务码，
  崩没崩由那条判据说话，不在这里抄读数），但**它是抽检不是关闭条件**：同一支尺、同一次会话里连跑两发
  就给出过 `3/12` 与 `0/12` 两端（2026-10-02 WSL，逐跑 rc 分解见账本 BUG-133 追记）⇒ `crashes=0/N` 只说明
  "这一支样本没抽中"，不许据此写「native 已修」；BUG-133 的关闭条件因此是两格（抽检连发 0 崩溃 + 干净树全量通过）。
  退出码是契约（`0` 全跑完 / `1` 有崩溃 / `3` 平台或工具链不给量、拒绝出数 / `4` 尺子自己坏了——含判据未捕获异常，
  绝不冒用 `1` 那一档）。**权威稳定门槛 = JS 后端（Node ≥ 24，本轮 1959/1959）**，见 `AI-DEVELOPMENT-STANDARD.md` §7「已知边界」。
   但 `moon test` 自身的退出码**不可靠**（moon 0.1.20260920 实测：测试可执行文件 SIGABRT 时 `moon test` 仍回 exit 0，BUG-142）——**判绿以 `Total tests: N, passed: N, failed: 0` 汇总行为准**，exit 0 只是必要条件；只查退出码的脚本会把崩溃判成通过。

> **BUG-133 已在依赖侧修复（2026-10-10）**：`mizchi/sqlite` 的 `stub.c` 已改写成
> `moonbit_make_external_object` 包装裸 `sqlite3*` / `sqlite3_stmt*`，并把 6 处 `const char*` 返回改成
> `moonbit_make_bytes` 副本。修复版落在 `patches/sqlite-bug133/stub.c`（repo 内），配套
> `patches/sqlite-bug133/reapply.sh`（`--force` / `--verify` / 幂等）。
> **为什么不能只改 `.mooncakes`**：它在 `.gitignore` 里，`moon update` 会重生成——所以 CI 两条 native 臂
> 在 `moon update` 之后、`Check (native)` 之前都加了一步 `Reapply BUG-133 sqlite FFI fix`
> （`bash patches/sqlite-bug133/reapply.sh --force`），保证依赖一更新就把修复落回来。
> 本地装完依赖后同样跑一次 `bash patches/sqlite-bug133/reapply.sh` 再 `moon test --target native`。
> 实测读数（Windows + `moon 0.1.20260920`）：修复前 `moon test --target native src/store` 5 连发 3 次失败；
> 修复后 src/store 15 连发 + 全量 native 4 连发全部 633/633 通过（JS 同版本 633/633 零回归）。
> 探针在 Windows 会拒绝出数（POSIX-only），故抽检面以「同命令连发全绿」为等价面。

### 一源四态 · 插件态（生成投影，非手写）

> **开发规范正文真源 = [`AI-DEVELOPMENT-STANDARD.md`](AI-DEVELOPMENT-STANDARD.md)**（R116）。`project_standards` 工具是它的机器投影，README/AGENTS/skill 只做摘要；三者一致性由 `check_doc_surface.py` J6/J7 拦（缺任一规则 id、版本不符或残留旧口径即红）。目标项目照该文件的 §2 文档集骨架开工。

每个功能的第四种形态是**宿主插件目录**，由 `scripts/gen_plugins.py` 从单一真源投影，顺序固定：
**atomcode → codearts → deepseek-harness → claude**（真源 = `plugins/source/` 正文 + `server.mbt` 工具数 + `moon.mod` 版本 + `memory/bugs.md` 账本 + 根 `.mcp.dev.json` 启动参数——候选按**跟踪面优先**解析，本机连接器在读的那份 `.mcp.json` 已被根锚定 `/.mcp.json` 挡在 ignore 面，不得决定投影正文，BUG-131 + 同日 owner 裁决）。

- 插件目录**禁止手改**：`scripts/check_plugin_sync.py`（cl7）子进程重跑生成器做逐字节 diff，另查四宿主入口齐全、无残留 `{{占位符}}`、manifest 版本==moon.mod、`plugins/claude/.mcp.json` 与根 `.mcp.dev.json` 逐字相等、生成 SKILL.md 的 `tools=` == 实测工具数；实测 <=100 直接 FATAL(2)（判据无法自证绝不报绿）。
- 守卫族（数目不在此自述——写死一个数就是下一颗漂移雷，本仓已为它返工过一次；下列都在 ci.yml JS 轨）：`check_tools_sync` / `check_test_sync` / `check_badge` / `check_scripts_index` / **`check_plugin_sync`（cl7）** / `check_doc_surface` / **`check_store_tables_wired`（BUG-28：库内每张表要么有写入点、要么在 store 源文件里 `schema-reserved:` 点名预留，两个方向都发红）** / **`check_publish_payload`（BUG-127：`moon publish` 的打包面是「工作树 − .gitignore」而不是 git 跟踪面，且点号文件不进包——未被 ignore 又未跟踪的文件会被公开点名，红面里出现凭据形状另判 P2 事故级；空扫描必自拒）** / **`check_demo_isolation`（BUG-122 起、BUG-124 收全：凡 `Popen` 起 `serve` 的脚本必须把 `FIST_DB_PATH` 交给子进程，否则 README/USAGE 教人的那条裸跑命令就在往仓库根自举台账 `fist-mbt.db` 里塞演示行；豁免项必须锚点成立，扫描面空即自拒；现状面 29 个 spawn 脚本全合规 = 27 个带默认改道针 + 2 个显式子句，另有 1 项豁免且锚点成立）** / **`check_ps_encoding`（BUG-88：.ps1 要么纯 ASCII 要么带 UTF-8 BOM，否则 PS5.1 按 ANSI 读会解析期即炸）** / **`store_isolation_probe`（BUG-90：`FIST_DB_PATH` 必须真的改道——同一 cwd 两格只差这个环境变量，且带合成违例格） / **`check_entry_paths`（BUG-93/101：现状面的命令与产物路径不得指退役入口，`Popen([node, cli.js])` 的 argv 必须带 serve——入口搬家漏掉的另一半；判据从 `cmd/*/moon.pkg` 的 `pkgtype(kind:"executable")` 与 build_release.ps1 反解入口清单，不硬编码） / **`check_release_asset_names`（BUG-103/105/107/109：发布资产名 ↔ 安装器 ↔ moon.mod 三处同源；安装器禁写死默认版本、版本解析为空必须 exit 1——用户跑不带参数的 `irm | iex` 是否在装一个不存在的资产名，CI 看不见这条；R5 再钉「命令名两类 shell 都可见」——Windows 侧除 `.cmd` 外必须有**无扩展名**的 `#!/bin/sh` shim ＋「四件齐否则 exit 1」的门，WSL/Linux 侧必须 `cat` 出无扩展名 shim 并 `chmod +x`（POSIX shell 不解析 PATHEXT ⇒ 只给 `.cmd` 就是「装成功了但 bash 里 `fist` 不存在」）；**R6 再钉「200 不等于拿到文件」**（BUG-107 实测：GitCode 三种 raw 形状匿名 GET 全回 HTTP 200 + HTML 页，GitHub 侧 `main` 取不到、`master` 才是可达线）——文档首选安装线必须指 GitHub master raw，且安装器必须做 HTML 形状检查 + zip 魔数 `PK` 检查；**R7 再钉「装完的自检不许假绿」**（BUG-109，由 `scripts/blackbox/e2e_mirror_install.py` 端到端跑出来的：`$ErrorActionPreference="Stop"` 下原生命令的 stderr 经 `2>&1` 变终止错误，而 node:sqlite 每次启动都打 `ExperimentalWarning` ⇒ 旧自检的 `try{}catch{}` 必吞错、`✅ fist-mbt.js 可执行` 却无条件打印，`& fist version` 的 catch 还把「shim 跑通了」报成「当前会话 PATH 未刷新」；三支子判据＝禁空 catch／原生调用必须「临时降 EAP + `2>$null`」封装／✅ 必须挂在版本回执的 `if ($jsVer)` 分支上；`--selftest` 十四格 R1×2/R2/R3×2/R4/R5×2/R6×3/R7×3；**R8 再钉「发布作业不许顶掉分发」**（BUG-111，release run 1 实测失败且 Release 零资产，而本机快照复跑 JS 三步全绿 ⇒ 根因在 `release.yml` 的 `release` 作业：引用 `needs.meta.outputs.version` 却没把 `meta` 放进自己的 needs，又把**可选的** `build-native-linux` 当一票否决项）——判据打 release.yml：needs 必须含 meta、不得含 native、native-linux 必须带 `continue-on-error: true`；**R9 再钉「工具链 bootstrap 与 CI 同源」**（BUG-112，从匿名 `/actions/runs/<id>/jobs` 的**失败步骤名**反解出来的真最后一格：`build-js` 红在 `Build JS target`、`build-native-linux` 红在 `Build native`、`release` 是 `skipped` ⇒ runner 上根本没有 `moon`——`release.yml` 用 `install/unix`（少 `.sh`）且从不 `echo "$HOME/.moon/bin" >> "$GITHUB_PATH"`，而同仓跑通过的 `ci.yml` 两条都有）——判据只看**去掉 `#` 注释行之后**的代码面（第一版被自家注释里的 "GITHUB_PATH" 喂回针，那格变异不红，`--selftest` 当场抓到）：跑 moon 的 workflow 必须有 moon 进 `GITHUB_PATH`、安装 URL 必须是 `install/unix.sh`；**R10 再钉「文档那条线必须 BOM 安全」**（BUG-113 实测：`irm <GitHub master raw> | iex` 当场报「At line:22 char:22 赋值表达式的左侧无效」——含中文的 .ps1 按 BUG-88 必须带 UTF-8 BOM，而 `irm` 把 BOM 留成首字符 U+FEFF ⇒ `iex` 认不出 `param()` 是首语句；同一个脚本 `-File` 跑却正常 ⇒ 之前所有走 -File 的 e2e 照不出这一格）——安装器文档线与 README 的 Windows 线都必须含 `TrimStart([char]0xFEFF)`（正确形是 `.ToString().TrimStart(…)`，`.Content` 那条路上是 null），README 从此进判据面，常驻入口 `scripts/blackbox/e2e_irm_line.py` 的特点是**命令从 README 反解、不硬编码**。同一 e2e 也是 BUG-108 的镜像入口（安装器 `-BaseUrl` / `install.sh` `FIST_BASE_URL`）的常驻判据——没有公网 Release 时让「真的走下载」这一段可跑；**R11 再钉「源码版本常量不许落后于 moon.mod」**（BUG-114：moon.mod 已经前进之后 `src/server/server.mbt` 的 `project_version` 还停在上一个版本号 ⇒ 公网装出来的全局命令 `fist version` 回旧版，而安装横幅、README、插件态都说新版；文档面守卫只比「文档 ↔ moon.mod」，看不见源码这一格，而 `src/server/fist-mbt_wbtest.mbt` 里那条常驻锁在 master 上**一直红着、没人读**——红着没人读等于没锁）——`let project_version` 与 `cmd/cli` 侧扫到的任何 `const *VERSION*` 必须 == moon.mod：读不到基线即自拒，该可选面不存在时不误红。**调用面另有常驻判据** `scripts/cli_flag_probe.py`（CI 起真产物 `node cli.js <arm>` 看真 rc、读真首行：三档缺一不可——版本旗 rc=0 且首行回显 moon.mod 版本 / 帮助旗 rc=0 且不落「未知子命令」/ 未知参数 rc≠0，即 BUG-106 与 BUG-114 的入口锁；白盒测试钉的是纯函数 `parse_subcmd`，入口被改回字符串 match 它照样全绿）。`--selftest` 的格子清单与 PASS 行的判据范围**一律从实现反解**，不手写计数（本轮顺手拆掉一处幻影：R5 那格因「变异只改注释」被循环跳过，自述里却照写 `R5×2`）；**R12 再钉「下载重试只许对准传输层错误」**（BUG-116 实测：本机走系统代理时 `raw.githubusercontent.com` / `release-assets…` 会瞬时抛"基础连接已经关闭"，而同一时刻 curl 取同一 URL 得 200 + `PK` ⇒ 一失败就换源会把抖动放大成"装不上"；但 404/403/"给的不是 zip" 是确定性结论，重试只是拖慢用户）——两条子判据：必须保留"拿到 HTTP 响应就 break"的闸、重试必须带退避间隔。另外常驻 e2e 的沙箱**每次清场**、探针**点名跑沙箱那一份产物**（不这样，判据会红在"上一轮的旧安装"上，见 BUG-117）；**R13 再钉「文档离线线的资产名版本字面量不许落后于 moon.mod」**（BUG-120，BUG-116 车道的交接缺口：README 的 `-LocalZip …\fist-mbt-js-v0.3.4.zip` 落在 R1（只扫安装器、禁写死默认值）与 J4（只认 `@x.y.z` 式版本声明）**两面守卫之间无人认领** ⇒ 版本一前进，照抄离线/内网线就指向一个不存在的资产）——README 里以数字开头的 `fist-mbt-js-v<版本>.zip` 字面量必须 == `moon.mod`，无基线即自拒；模板形态 `v$VERSION` 不是字面量、不误红（两支自证：漂移必红 + 模板不红，`--selftest` 反解出 `R13×2`）；**R14 再钉「安装器内部两发取数也要有第二条 TLS 栈」**（BUG-125，即 BUG-116 的**内部半**：车道把 `install_onecmd.ps1` 取回来后红在内部那一发——「基础连接已经关闭」+「无法从 moon.mod 解析版本号」，因为 R12 判的是 zip 那一发的**重试纪律**、文档线两臂由 `e2e_irm_line` 判，「内部取数能不能换栈」两版守卫都不看 ⇒ 与 BUG-120 同族的另一道两面缝）——四条子判据：兜底臂 `function Get-UrlTo` 注册在 / 调用点≥2 处（moon.mod 与 zip 各一）/ 「只对没有 HTTP 响应的传输层错误换栈」的闸在（404/403 仍直接换源）/ curl 旗带重试上限且**针必须带次数**（单独 `--retry` 子串会被自家 `--retry-delay` 喂绿，这一手有自证格）；`--selftest` 反解 `R14×5`，承重件 `scripts/blackbox/e2e_transport_stack_fallback.py` 三格实测（A 换栈装通且回执带 `curl-fallback` / B 把 `$script:CurlExe` 置空必拿到**一个真非零整数** rc——`rc is None` 也算判据坏，否则"这一格根本没起跑"会被读成"如预期红" / C 干净安装不误伤；用户 PATH 逐字还原、真产物 sha256 跑前跑后必须相同）（文档面 J1-J18：逐个工具可查 + 分组和==实测 + 自述版本==moon.mod + 反幻影哨兵 + **J4 子判据：注册表发布版本只在 `BACKLOG.md` 一处自述** + **J6 规范正文↔机器投影一致** + **J7 规范性表面禁旧口径** + **J8 模板调用参数==真源 schema** + **J9 工具描述返回契约（必查清单 + 歧义键分工 + 棘轮只许升）** + **J10 判据范围自述==实现（少写=声明滞后、多写=幻影判据）** + **J11 CI native 门步骤↔账本/规范面 三向对表（账上 BUG-133 仍 OPEN 时：门不许被删、不许挪到 `Test (native` 之后、规范面逐字点名的步名必须等于 workflow 里的步名；单转 FIXED 后这一格自然失效，不留恒红）** + **J12 CI 的 `if:` 守卫不许钉分支名（BUG-132 的恒假门形状：`if:` 里出现 refs/heads/ 引用即红——分支名一变那道门永不可能运行，而它在读数里长得像「未触发所以正常」的绿灯位；分支过滤交回 `on:`，判据只看剔掉注释之后的代码面，墓碑注释不喂针）** + **J13 CHANGELOG 标题里的发布状态短语不许落后于 `BACKLOG.md` 的 `release-fact:` 读数（BUG-135 的形状：标题写「GitHub Release 未发布」而那一节的盖章戳晚于权威面的 published 时刻——豁免历史文件是对的，但不等于放过「戳晚于事实」那一档；版本归属必须由机器可读标记给出，散文里那句「与本条同一版本号」不是可解析锚）** + **J14 工具计数自述与 CLI 帮助的分组数字之和、分组数都必须等于真源注册表（BUG-136 附带抓到的形状：`fist://map` 资源正文写着「MCP 层 102 工具」而真源是 129，`check_tools_sync` 第 3 条不扫 src/、J3 只扫 README ⇒ 资源面与 CLI 帮助面两头没人认领，而这句话随插件态一起发货）** + **J15 docs/ 归档文档文件名日期前缀（R12 新增：docs/ 是评估/决策归档面，文件名里带日期数字却不用 `YYYY-MM-DD-` 前缀时，回溯性审查无从按时间排序这条评估；纯参考文档与已确立的 `improvement-plan-YYYYMMDD.md` / `improvement-proposals-YYYYMMDD.md` 命名族豁免，目录里一份 .md 都枚举不到 ⇒ 自拒不报绿） + **J17 工具链地板 ↔ `toolchain.json` 单一真源对表（R141 新增：MoonBit / Node 的版本地板此前只有散文、没有机器可读真源、没有尺——`moon_version()` 读的是 moon.mod 的**模块版本**而非工具链版本，README 首屏 `badge/MoonBit-<版本>` 由零把尺验证。现在现状规范表面的每条地板声明（`≥` 式、徽章式、`精确` 式钉版）必须 == `toolchain.json`；必须声明地板的面（README / README_EN / USAGE / AGENTS）把地板删光即红（同 J4「权威被删空必红」）；CI 的 `node-version` 也须 == pin，否则文档教的与 CI 跑的不是同一台机器。引文 `「…」`、`reports/` `memory/` `docs/archive/` CHANGELOG BACKLOG 与 `plugins/<host>/` 生成副本豁免；读不到 pin、枚举不到 .md、一个地板都解析不到 ⇒ 三档自拒不报绿。上岗第一跑即抓到 `docs/2026-10-12-mcpcf-embed-serve.md` 的「要求 Node >= 22.5」与 README 的 ≥24 互相矛盾——POLISH-04 当年只改字不补尺，同一形状已在另一面复发）**`；`--selftest` 用合成违例证明 J4/J6/J7/J8/J9/J10/J11/J12/J13/J14/J15/J17 能发红（自检正文里没写对照，`SELFTEST OK` 那行就不会报它——那份清单从正文反解，不手写），J9/J10/J4 各配反向对照（干净输入/两面一致不误红），**J11 另配「合法态不误红」一支（BUG-133 已 FIXED + 门已撤 + 文档不再点名 ⇒ 不许红）**、**J12 另配两支反向对照（注释里的旧条件不红、refs/tags/ 守卫不红）加一支「一份 workflow 都没读到必自拒」**、**J13 另配两支反向对照（标题戳早于 published 不误红、权威面没记这一版则这一格不作数）加两支「BACKLOG 读不到 release-fact 标记必自拒」「CHANGELOG 解析不到 `## v` 标题必自拒」**、**J14 另配两支反向对照（自述数字正确不误红、分组和与组数都正确不误红）加两支「三面都解析不到计数自述必自拒」「CLI 分组面读不到必自拒」**、**J15 另配两支反向对照（带 `YYYY-MM-DD-` 前缀不误红、纯参考文档不带日期数字不误红）加一支「docs/ 一份 .md 都枚举不到必自拒」**、**J17 另配三支反向对照（干净现状面不误红、`「…」` 引号内的旧值不误红、历史面与生成副本不误红）加三档自拒（无 pin / 枚举不到 .md / 一个地板都解析不到）与两支漂移必红（首屏徽章漂移、CI `node-version` 漂移）** / **`check_model_auth_no_key`（config_json、HTML 生成物、`default-fist.mcp.json` 里禁止出现 `api_key`/`Bearer`/`sk-` 值形状，对齐 BUG-127 的凭据形状红）** / **`check_host_installable`（check_plugin_sync 之外补一格——deepseek-harness 宿主侧真的能装上，避免 cl7「等于投影」却「装不上」的旧边界）** / **`check_skill_inject`（evolve_asset_register 注入路径可测命中，plan/claim 传了 `inject` 时返回的 `injected_assets` 非空才算命中）**，且 ci.yml 的文档面那一步先跑 `--selftest` 再跑全量（BUG-89：本轮之前 ci.yml 里只有 `check_test_sync` 的自检被执行，文档面守卫的自检崩了也报绿），不是装饰）。

- 自述面判据（BUG-104，与上面守卫族里那些 `check_*` 并列的 CI 一步，但它刻意不是 `check_*`——数目会随族增减，写死一个数就是下一颗漂移雷）：`scripts/mcp_tool_tour.py` 的 `surface_probe()` 把 AGENTS.md 自述的 resources / prompts 两面与 `serverInfo.version ↔ moon.mod` **打到调用面双向对表**（少一条 / 多一条 / 读回空文本 / prompt 零消息 / 版本不符 / 验收位为空 ⇒ 巡回退出码非 0；文档反解不出条目 ⇒ 判据自拒不报绿）。为什么它不是 `check_*`：这两面必须真跑 MCP 协议才观测得到，离线脚本只能验文档自述、验不到服务端实回——而 tools 面早已被 `check_tools_sync` 钉住，恰好剩这两面没人认领（J10 型缺口）。CI 跑的是它的 `--surface-selftest`（12 支对照：10 违例必红 + 干净必绿 + 无声明行必自拒，桩 server 不起 node、不碰库）；真协议巡回要 node + 产物，用法与两面记账口径见 `scripts/README.md` 同名条目。

Prompts: `fist:check_in`, `fist:verify`

> **术语注记（2026-09-26 立，防误读）**：本仓日志/账本里出现的 `pentad-r1/r2/r3` 是
> **FIST-Mbt 自身「四模式流水线自我迭代」的轮次标签**（ns 名与 `reported_by` 署名已入库，不改写历史），
> 与衍生项目 **Pentad**（`scripts/pentad_fist.py`、模板里「Pentad 无人值守流水线」正文）不是一回事：
> 那些地方 Pentad 是被 FIST-Mbt 驱动的**另一个项目**。写文档/报告标题一律用「四模式流水线自我迭代 · Round N」，
> 不要把 Pentad 当本仓特性名（本轮已把 4 份报告与三处文档计数口径改回本仓术语）。

> **实证伴生仓（fist-evidence，2026-09-27 公开）**：本系统的受控实验证据链在独立仓库
> https://github.com/vicTop-cw/fist-evidence —— 三组实验（`selfdrive-ab-20260926` 编排 vs 裸跑 /
> `atgc-merge-20260926` 三方合并裁决含归因自我修正 / `core-split-ladder-20260927` 核心拆解最小内核 +
> 裸跑幻觉实锤）+ 十份真实项目驱动实例总表，原始报告/日志/裁判测试一字可回溯。
> 本仓「证据梯至少 L4（实测才算数）」的对外展示面即该仓库；引用实验结论时以 `stories/evidence/` 原件为准。

## 路径约定

| 项 | 值 |
|---|---|
| FIST 根 | `<FIST-项目根目录>` |
| FIST SKILL 全文 | `<FIST-项目根目录>/FIST-SKILL.md` |
| FIST-Mbt 根 | `<FIST-Mbt-项目根目录>` |
*（内容由AI生成，仅供参考）*

## MCP 工具清单（已搬出，本文件只留指针）

> 本仓 MCP Server 共 **182 个 MCP 工具**（+3 resources +2 prompts）。完整清单
> （生命周期 / 查询 / 运维 / 自驱 / 记忆与进化 / Marketplace / 审计权限 /
> 多租户 / Omega 强验证 / 开发模式与模板 / GitHub·GitCode 同步 / 模型路由·外部执行器 /
> 六顶帽 / 项目助理 / 超级管家 / MCPCf 内部工具）**共约 274 行**，已搬到
> **`docs/AGENTS-mcp-inventory.md`**（逐字保留；需要时用 read 打开）。
> 搬出的原因：`AGENTS.md` 超过 harness 指令预算（上限 65,244 字节），后段对 agent 不可见 ——
> **清单是参考材料，规则必须可见**。判据：`python scripts/check_instruction_budget.py`；
> 工具计数一致性判据 `check_tools_sync` 会把「本文件 + 那份清单」**合起来**当 AGENTS 面（R213）。
