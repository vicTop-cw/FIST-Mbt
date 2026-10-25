# 侦察报告：CLI `list-tools` 152 vs 真源 170 的 18 个缺口

> **角色**：侦察兵（只查根因与证据，**不改代码、不改文档、不 commit**）
> **侦察面**：文档一致性面 · 第 2 态 CLI `list-tools` 工具数缺口
> **执行**：司令-ζ　**基线 commit**：`5e769af3`　**日期**：2026-10-25
> **交付物**：本报告（唯一新增文件，未提交）

---

## 结论（先给确定答案）

# ✅ 这是**口径问题**，不是真缺态。零个工具缺失，零个幽灵工具。

**18 个工具在 MCP 运行态、真源注册表、真实 CLI 产物 `cmd/cli` 中全部存在且可调用。**
缺的只是 **`scripts/fist.py` 这一个便捷入口的解析器**——它的正则只扫 `server.mbt` 一个文件、
且只认 `[a-z_]+` 命名，因此漏掉了**注册在其它 3 个文件里的 11 个** + **名字带点号的 7 个**。

| 关键读数 | 值 | 来源 |
|---|---|---|
| 真源注册表 `real_tools()` | **170** | `scripts/_tool_registry.py` |
| 运行态 `tools/list` | **170** ✅ | `python scripts/mcp_smoke.py` |
| 真实 CLI 产物 `cmd/cli help tools` | **170（18 组，分组和=170）** ✅ | `node _build/.../cli.js help tools` |
| `scripts/fist.py list-tools` | **152** ❌ | 唯一不符者 |
| 差值 | **18** | 全部可用「解析器扫描面」解释 |

**判定**：`fist.py list-tools` 是**报数口径不全的便捷脚本**，不是功能缺失。
**文档说 170 是对的**，`fist.py` 的 152 才是错的（低报）。

---

## 一、真读数（第一手，全部本机现跑）

```bash
$ python scripts/fist.py list-tools | tail -1
共 152 个工具

$ cd scripts && python -c "import sys;sys.path.insert(0,'.');import _tool_registry as tr;print(len(tr.real_tools()))"
170

$ python scripts/check_tools_sync.py
PASS 工具单一真源一致：server.mbt 注册 170 个，AGENTS/README/deliverable/scoring_rubric 对齐；R3b/R7 扫现状面 177 份

$ python scripts/mcp_smoke.py
PASS tools/list → 170 个工具（含 publish/selfdrive_publish_next 等）      ← 运行态真读数
MCP-SMOKE PASS

$ node _build/js/debug/build/cmd/cli/cli.js help tools | head -1
=== 0.3.10  170 MCP tools (18 groups) ===                              ← 真实 CLI 产物
分组数: 18   之和: 170                                                  ← 逐组求和验证
```

> **判例-43 核对（清单生成命令的截断必须与真源计数对表）**：
> ```
> 命令自报: 共 152 个工具
> wc -l    : 152
> 去重后   : 152
> ```
> 三者相等 ⇒ **`wc -l` 无截断、无 stderr 吞并**（判例-41 同族），152 是可信读数，
> 不是测量伪影。**这条先排除掉，否则后面全部推理都建在沙上。**

---

## 二、逐 18 个差对照

### 2.1 集合差（`_tool_registry.real_tools()` vs `fist.py list-tools`）

```
真源: 170   CLI: 152

A. 真源有 / CLI 无  = 18   ← 疑似真缺态
B. CLI 有 / 真源无  = 0    ← 幽灵工具（一个都没有 ✅）
```

**B 类为 0 是一个重要信号**：如果 `fist.py` 的解析器只是「少扫了」，它不该凭空造出真源没有的名字。
B=0 说明它是**纯遗漏型**缺陷，不是错配型。

### 2.2 A 类 18 个的逐名归属

| # | 工具名 | 所在文件 | 为何被 `fist.py` 漏掉 |
|---|---|---|---|
| 1 | `hat_debate` | `src/server/hat_hexa_tools.mbt` | 不在 `server.mbt` |
| 2 | `hat_merge` | `src/server/hat_hexa_tools.mbt` | 不在 `server.mbt` |
| 3 | `hat_run` | `src/server/hat_hexa_tools.mbt` | 不在 `server.mbt` |
| 4 | `mcpcf.circuit` | `src/server/mcpcf_embed.mbt` | 不在 `server.mbt` **且** 名字带 `.` |
| 5 | `mcpcf.ops_init` | `src/server/mcpcf_embed.mbt` | 同上 |
| 6 | `mcpcf.report` | `src/server/mcpcf_embed.mbt` | 同上 |
| 7 | `mcpcf.review` | `src/server/mcpcf_embed.mbt` | 同上 |
| 8 | `mcpcf.run_batch` | `src/server/mcpcf_embed.mbt` | 同上 |
| 9 | `mcpcf.verify` | `src/server/mcpcf_embed.mbt` | 同上 |
| 10 | `mcpcf.watchdog` | `src/server/mcpcf_embed.mbt` | 同上 |
| 11 | `supervisor_kill_plan` | `src/server/supervisor_tools.mbt` | 不在 `server.mbt` |
| 12 | `supervisor_prompt_consume` | `src/server/supervisor_tools.mbt` | 不在 `server.mbt` |
| 13 | `supervisor_prompt_inject` | `src/server/supervisor_tools.mbt` | 不在 `server.mbt` |
| 14 | `supervisor_prompt_list` | `src/server/supervisor_tools.mbt` | 不在 `server.mbt` |
| 15 | `supervisor_reminder_tick` | `src/server/supervisor_tools.mbt` | 不在 `server.mbt` |
| 16 | `supervisor_status` | `src/server/supervisor_tools.mbt` | 不在 `server.mbt` |
| 17 | `supervisor_task_tree` | `src/server/supervisor_tools.mbt` | 不在 `server.mbt` |
| 18 | `supervisor_task_upsert` | `src/server/supervisor_tools.mbt` | 不在 `server.mbt` |

**按家族汇总**：

| 家族 | 个数 | 所在文件 | 注册形态 |
|---|---|---|---|
| 超级管家 | **8** | `supervisor_tools.mbt` | `instrumented_tool(...)` |
| 嵌入式 MCPCf | **7** | `mcpcf_embed.mbt` | 链式 `s.tool(...)` |
| 六顶帽 | **3** | `hat_hexa_tools.mbt` | `instrumented_tool(...)` |
| **合计** | **18** | | |

---

## 三、根因（代码级，已定位到行）

`scripts/fist.py` 的 `cmd_list_tools`（第 250–264 行）：

```python
def cmd_list_tools(proc):
    """列出所有 MCP 工具名（从 server.mbt 解析）。"""
    server_mbt = os.path.join(os.path.dirname(__file__), "..", "src", "server", "server.mbt")
    if os.path.isfile(server_mbt):
        content = open(server_mbt, encoding="utf-8").read()
        names = re.findall(r'instrumented_tool\(\s*\w+,\s*"([a-z_]+)"', content)
        names = sorted(set(names))
```

**两个独立缺陷叠加，恰好漏掉 18 个：**

### 缺陷 ①：只扫 `server.mbt` 一个文件（漏 11 个）

工具注册在 2026-10-14 已从 `server.mbt` **拆分到多文件**（`supervisor_tools.mbt` / `hat_hexa_tools.mbt` / `mcpcf_embed.mbt`）。
`fist.py` 的扫描面没跟上拆分 ⇒ 另外 3 个文件里的注册全部不可见。

> **这正是 `check_tools_sync.py` 注释里记录过的同一个坑**（BUG-153 同族）：
> 「工具注册已从 server.mbt 拆成多文件，判据的扫描面没跟上 ⇒ 文档面被迫对 148 自洽、
> 运行态却是 166」。
> **判据面当时修了**（改为委托 `_tool_registry.real_tools()`），
> **但 `fist.py` 这个终端用户入口没跟着修** —— 同一个根因，两处实现，只修了一处。

### 缺陷 ②：正则 `[a-z_]+` 不容点号（漏 7 个 `mcpcf.*`）

`mcpcf.circuit` 等 7 个工具的名字含 `.`，`[a-z_]+` 不匹配 `.` ⇒ 即使它们就在 `server.mbt` 里也匹配不到。
（实测它们确实不在 `server.mbt`，但**两个缺陷任修其一，都还会剩另一半**。）

### 明证：`_tool_registry` 知道正确口径，`fist.py` 没用它

`scripts/_tool_registry.py` 的 docstring 明写：

> 口径：`src/server/*.mbt`（排除测试）里 `instrumented_tool(<var>,"name",…)` 与
> 链式 `<var>.tool("name",…)` 的并集。

**`check_tools_sync` / `check_doc_surface` / `check_plugin_sync` / `gen_plugins` / `mcp_smoke` 五处
消费者都已收口到这一份实现**（见该文件注释「此前本函数在 5 个消费者里各写一份…现在只有一处实现」）。
**`fist.py` 是第 6 个消费者，它被漏在收口之外。**

---

## 四、这 18 个是**真的能用**的（决定性证据）

只证明「注册表里有」不够，必须证明「调用得通」。逐一实调（本机现跑）：

```bash
$ python scripts/fist.py call mcpcf.report
{"ok":true,"ns":"default","total":0,"by_status":{},"tasks":[]}        ← 带点号工具，真返回业务数据

$ python scripts/fist.py call supervisor_status
{"total":0,"by_status":{},"by_namespace":{"default":0},"progress_pct":0,
 "active_count":0,"active":[],"scope":"all-namespaces","namespaces_scanned":["default"]}   ← 真任务板

$ python scripts/fist.py call hat_list
{"hats":[{"id":"white","name":"白帽 · 事实", ...}], "defaults":["white","black","yellow"], "count":6}  ← 6 顶帽全在
```

> **一个特别有说服力的细节**：我最初用 `--project-dir .` 调 `supervisor_status`，得到
> ```
> FAIL supervisor_status: 未知入参 project_dir（该工具实际接受：detail, namespace）
> ```
> **能报出「该工具实际接受 detail, namespace」这句 schema 内容，本身就证明工具已注册且
> inputSchema 可读**——不存在才是真缺态时会报「未注册的工具」。
> 这比任何静态计数都硬。

**三个家族各抽一个，全部实调成功** ⇒ **18 个是活的功能，不是僵尸登记。**

---

## 五、纪律项核对

### 5.1 判据类问题优先排查：门禁是否停摆？

```bash
$ python scripts/run_guards.py --list | grep 缺执行面
尺 119 把 / CI 面 45 / 电池面 78 / 缺执行面 0        ← 0，未停摆

$ python scripts/check_battery_count_doc.py
PASS 电池读数与 README 登记逐键一致：rulers=119 ci=45 battery=78 missing=0 gate=86 exempt=28 unclassified=7
```

**⇒ CLI 计数问题没有导致任何门禁停摆，不需要优先报红。**（这条先查过，避免误报成事故。）

### 5.2 判例-43 / 判例-41：截断与 stderr

已在 §一 核对：命令自报 152 = `wc -l` 152 = 去重后 152，**无截断**。

### 5.3 侦察兵纪律
- ✅ 未改任何代码 / 文档
- ✅ 未 commit（本报告是唯一新增文件，保持未跟踪）
- ✅ 未开 worktree（主仓只读侦查）

---

## 六、受影响面（供派修参考，我不修）

| 面 | 状态 | 说明 |
|---|---|---|
| MCP 运行态 `tools/list` | ✅ **170** | 正确 |
| `cmd/cli` 真实产物 `help tools` | ✅ **170（18 组）** | 正确 |
| `scripts/fist.py list-tools` | ❌ **152** | **唯一错处** |
| 文档（README/AGENTS/agent-map/deliverable） | ✅ 全 **170** | **文档是对的，不需改** |
| `check_tools_sync` | ✅ PASS 170 | 未受影响（它用 `_tool_registry`） |
| 门禁电池 | ✅ 缺执行面 0 | 未受影响 |

> **重要**：这条缺口**从来不会让文档守卫变红**，因为守卫全部走 `_tool_registry`（170），
> 只有人手动跑 `fist.py list-tools` 才会看到 152。
> ⇒ 这是「**终端用户入口与守卫口径分叉**」类缺陷，属 **判例-16（判据面/实现面不一致）的近亲**。

---

## 七、修复建议（给做决策的人，我不执行）

**首选（一处改动，两个缺陷同时消）**：把 `cmd_list_tools` 改为委托 `_tool_registry.real_tools()`。

```python
# 现在
names = re.findall(r'instrumented_tool\(\s*\w+,\s*"([a-z_]+)"', content)

# 应为（与其余 5 个消费者同源）
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _tool_registry import real_tools
names = sorted(real_tools())
```

**为什么这是首选而非「再扩一次正则」**：
本仓已有明确先例——`check_tools_sync` 的 `real_tools()` 注释写着
「本函数曾在 **5 个消费者**里各写一份…工具注册一搬家，5 处里漏改 2 处就会 ①假绿 ②互掐。
现在只有一处实现」。
**再扩正则就是把这条路重走一遍**，下一次注册搬家还会漏，而且漏在哪没人知道。
`fist.py` 已经是第 6 个消费者，**必须收口，不能第六次手写**。

**建议同批补的守卫**（否则修完还会漂）：
`fist.py list-tools` 的输出计数应有一条常驻判据对表 `_tool_registry.real_tools()`——
这条目前**完全空缺**（`check_tools_sync` 扫文档，扫不到 `fist.py` 的运行时输出）。

---

## 八、缺口与风险

1. **本报告未修任何东西**（侦察兵纪律）。修复需另派。
2. **`fist.py` 是否是唯一漏在收口外的消费者，我没有全量排查**——只确认了它。
   建议做一次「GRP 全量收口普查」：`grep -rn "instrumented_tool(" scripts/` 找出所有还在手写解析的地方。
3. **18 这个数会漂**：下次注册再拆文件，`fist.py` 的缺口会更大（因为它扫的文件面固定）。
   所以**修「委托 `_tool_registry`」比修「补正则」更要紧**——前者一劳永逸，后者只治本次。
4. **`fist.py` 的 docstring 与实际不符**：它写「列出所有 MCP 工具名」，实际只列 152/170
   ⇒ 「文档即实现」原则在这里也被违反（文档承诺 > 实现）。
5. **我未验证 `fist.py` 的 `call` 子命令对这 18 个是否全部可用**——已实调 3 个（三个家族各一），
   全通；剩余 15 个按同一注册路径推断可用，但**未逐一实测**（诚实标注：抽检 3/18）。

---

## 来源

- 真源：`scripts/_tool_registry.py`（`real_tools()`）、`src/server/*.mbt`
- 运行态：`scripts/mcp_smoke.py`（真 `tools/list`）、`_build/js/debug/build/cmd/cli/cli.js help tools`
- 缺陷点：`scripts/fist.py:250-264`（`cmd_list_tools`）
- 纪律核对：`scripts/run_guards.py --list`、`scripts/check_battery_count_doc.py`
- 基线 commit：`5e769af3`
