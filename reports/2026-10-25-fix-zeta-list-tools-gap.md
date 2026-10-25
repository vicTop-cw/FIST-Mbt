# 修复报告：CLI `list-tools` 152 → 170（委托单一真源）

> **前置侦察**：`reports/2026-10-25-scout-zeta-list-tools-gap.md`
> **执行**：司令-ζ　**修复 commit**：`cdaaa87e`　**日期**：2026-10-25
> **已推送**：`96348c64..cdaaa87e` → `gitcode/main`（三端一致已验证）

---

## 一、结果摘要

| 项 | 改前 | 改后 |
|---|---|---|
| `fist.py list-tools \| wc -l` | **152** ❌ | **170** ✅ |
| 与 `real_tools()` 集合比较 | 缺 18 个 | **逐名完全相等** ✅ |
| `fist.py list-tools` 的守卫 | **无**（零判据） | `check_fist_list_tools_sync.py`（3 条判据 + 5 格自检） |
| stdout 契约 | 名字 + 空行 + 汇总行（`wc -l` = 工具数+2） | **纯清单**，汇总行走 stderr（`wc -l` == 工具数） |
| 电池 | 119 把 / 缺执行面 0 | **120 把** / 缺执行面 **0** |

**一句话**：把「报数的脚本」从自写正则改成**委托 `_tool_registry.real_tools()` 单一真源**，
152 → 170，并补上一把此前**完全不存在**的对表守卫。

---

## 二、改动文件（4 个，`git show --stat cdaaa87e` 实测）

```
 scripts/README.md                     |   3 +-
 scripts/check_fist_list_tools_sync.py | 191 ++++++++++++++++++++++++++++++++++   (新建)
 scripts/fist.py                       |  43 +++++---
 scripts/run_guards.py                 |   6 ++
 4 files changed, 229 insertions(+), 14 deletions(-)
```

### 2.1 `scripts/fist.py` — 核心改法：**委托，不扩正则**

```python
# 改前（自写正则，只扫一个文件 + 不认点号）
server_mbt = os.path.join(os.path.dirname(__file__), "..", "src", "server", "server.mbt")
content = open(server_mbt, encoding="utf-8").read()
names = re.findall(r'instrumented_tool\(\s*\w+,\s*"([a-z_]+)"', content)

# 改后（委托单一真源）
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _tool_registry import MIN_EXPECTED, real_tools
names = real_tools()
if len(names) <= MIN_EXPECTED:      # 反幻影：解析退化时报错 rc=2，不静默打成"少了几个工具"
    ...
```

**为什么不是「把正则再扩一次」**：那是把「5 处各写一份」的路重走第六遍，
下次工具注册再搬家还会漏，**且漏在哪没人知道**。
`_tool_registry.py` 自己的注释就写着这个教训（5 个消费者各写一份 ⇒ ①假绿 ②互掐）。
`fist.py` 是**第 6 个消费者**，本次把它也收口进来。

### 2.2 stdout 契约收紧（顺带修掉一个对表陷阱）

旧实现把 `\n共 N 个工具` 打在 **stdout** ⇒ `wc -l` = 工具数 + 2。
这正是「与真源对表时数据对不上」的经典陷阱（判例-43 / 判例-41 同族）。
**改为汇总行走 stderr**，stdout 保持一行一个工具名的纯清单 ⇒ `wc -l` 直接等于工具数。

> 人类读数不受影响：`python scripts/fist.py list-tools` 终端里仍能看到「共 170 个工具」
> （stderr 默认也显示）。

### 2.3 docstring 与实现对齐

旧 docstring 写「列出所有 MCP 工具名（从 server.mbt 解析）」，实际只列 152/170——
**文档承诺 > 实现**，违反「文档即实现」。新 docstring 写清委托关系与那 18 个是什么、为什么漏。

### 2.4 `scripts/run_guards.py` — 电池接线（判例-5）

```python
case("check_fist_list_tools_sync.py"),
case("check_fist_list_tools_sync.py", "--selftest"),
```

### 2.5 `scripts/README.md` — 索引条目 + BATTERY-REGISTRATION 锚点

锚点同批归位（`check_battery_count_doc` 当场抓到漂移，正是它该做的）：
```
改前 rulers=119 ci=45 battery=78 missing=0 gate=86
改后 rulers=120 ci=45 battery=79 missing=0 gate=87
```

---

## 三、新守卫的变异对照证据（判例-29/30）

### 3.1 三条判据

| 判据 | 内容 | 为什么需要 |
|---|---|---|
| **C1** | stdout 行数 == `len(real_tools())` | 数量对不上就是缺口 |
| **C2** | stdout **集合** == 真源集合 | **不只比数量**——数量对而名字错同样是缺陷 |
| **C3** | stderr `共 N 个工具` 的 N == 真源 | 人类读数面也要对得上（机器对、人读错不算过） |

### 3.2 `--selftest` 五格（含**三个变异对照**）

```
SELFTEST OK (grid:
  S1-干净不误红(red=False)
  S2-变异①旧口径真源必红(red=True)
  S3-变异②CLI缺一名必红(red=True)
  S4-变异③stdout混汇总行必红(red=True)
  S5-空真源必红(red=True))
rc=0
```

| 格 | 变异内容 | 期望 | 实测 |
|---|---|---|---|
| S1 | 干净现状 | 不红 | red=False ✅ |
| S2 | **变异①**：真源换成「只扫 server.mbt」旧口径 | 必红 | red=True ✅ |
| S3 | **变异②**：CLI 输出截断一名 | C2 集合格必红 | red=True ✅ |
| S4 | **变异③**：stdout 混入汇总行（旧形状） | C1 必红 | red=True ✅ |
| S5 | 空真源 | 自拒 | red=True ✅ |

> **S2 是本尺的存在理由**：它证明这把尺量的确实是「入口 vs 真源的分叉」，不是恒绿装饰。
> **S3 证明 C2 不是摆设**：只比数量的尺会在「数量对、名字错」时假绿。
> **S4 把 stdout 契约锁死**：防止有人把汇总行加回 stdout，让 `wc -l` 又变成 172。

### 3.3 实机变异验证（比 selftest 更硬：改真代码、跑真命令）

我把 `fist.py` **真的改回旧口径**跑了一遍：

```
=== 变异后：CLI 报数 ===
共 152 个工具                    ← 缺陷如实复现

=== 变异后：新判据 ===
  - C1 `fist.py list-tools` stdout 152 行 != 真源 170 个工具
  - C2 真源有 / list-tools 缺 18 个: hat_debate, hat_merge, hat_run, mcpcf.circuit,
       mcpcf.ops_init, mcpcf.report, mcpcf.review, mcpcf.run_batch, mcpcf.verify,
       mcpcf.watchdog, supervisor_kill_plan, supervisor_prompt_consume,
       supervisor_prompt_inject, supervisor_prompt_list, supervisor_reminder_tick,
       supervisor_status, supervisor_task_tree, supervisor_task_upsert
  - C3 stderr 汇总写 152 个 != 真源 170 个
FAIL CLI list-tools 与真源不一致：真源 170 个 / list-tools 报 152 行（差 -18）
```

**三条判据全红，并逐名点出原来的那 18 个** ⇒ 这不是一把恒绿的尺。
（变异后已 `cp` 回备份，复验 CLI=170、判据 PASS。）

---

## 四、验收实测读数（统帅终审三项）

### ① 计数对表
```
$ python scripts/fist.py list-tools 2>/dev/null | wc -l
170
$ python -c "..._tool_registry.real_tools()..."
170
                         ⇒ 170 == 170 ✅
```
集合层（不止数量）：
```
CLI 170  truth 170  完全相等: True
```

### ② 门禁不停摆
```
$ python scripts/run_guards.py --list | grep -oE '缺执行面 [0-9]+'
缺执行面 0                                  ✅

$ python scripts/check_battery_count_doc.py
PASS 电池读数与 README 登记逐键一致：
     rulers=120 ci=45 battery=79 missing=0 gate=87 exempt=28 unclassified=7   ✅
```

### ③ 三端一致
```
local  HEAD   : cdaaa87ebf080ee75a0cb48c2d497f6a953fe5f1
gitcode main  : cdaaa87ebf080ee75a0cb48c2d497f6a953fe5f1
⇒ 三端一致 ✅ ；git branch -r --contains cdaaa87e ⇒ gitcode/main ✅
```

**三项全部满足。**

---

## 五、顺带普查结果（④，只报不改）

`grep -rn "instrumented_tool" scripts/*.py` 后逐个确认「是否委托 `_tool_registry`」：

| 脚本 | 委托状态 | 说明 |
|---|---|---|
| `check_doc_surface.py` | ✅ 已委托 | 另留着 `s1` 硬编码正则，但只用于**解析 schema 块**（非工具计数），不构成第二真源 |
| `check_plugin_sync.py` | ✅ 已委托 | 同上（`RE_TOOL` 为兼容保留） |
| `gen_plugins.py` | ✅ 已委托 | 同上 |
| `mcp_smoke.py` | ✅ 已委托 | 注释明写「单扫 instrumented_tool 会漏这 7 个」——它早就知道 |
| **`map_verify.py`** | ❌ **未委托** | **但 `RE_TOOL` 是死代码**：全文件只定义（L24）从未使用。该脚本也不在电池/CI 面 ⇒ **不构成第二真源**，本次不动 |
| `atgc_selfdrive_demo.py` | — | 命中的是注释/文案里的 `instrumented_tool` 字样，非解析逻辑 |
| `check_fist_list_tools_sync.py`（本单新增） | ✅ | 直接用 `real_tools()`；里面对 `instrumented_tool` 的引用只是注释 |

**普查结论**：`fist.py` 是唯一真正漏在收口外的**活消费者**，本单已收口。
仅剩 `map_verify.py` 一处**死代码**（定义了不用），不构成风险，建议后续随手清理（**本次不动**）。

---

## 六、遗留风险

1. **`map_verify.py:24` 的死代码 `RE_TOOL`** 仍在（定义未使用）。
   若将来有人「顺手用起来」，就会凭空造出第二真源。建议删，或改用 `real_tools()`。
2. **`check_fist_list_tools_sync.py` 会 spawn 一次子进程**（跑 `fist.py list-tools`，实测约 1–2s）。
   进电池后全量电池时长 +约 2s。可接受，但若将来电池超时可考虑合并到 `check_tools_sync`。
3. **本尺依赖 `fist.py` 的 stdout 契约**（纯清单）。若有人把汇总行加回 stdout，C1 会红——
   这是**故意**的（S4 格锁住），但意味着 stdout 格式现在是有契约的**公共面**，改它要先想清楚。
4. **未改 `cmd/cli/help tools`**：它本来就报 170（正确），且它的分组归类是人工知识，不受本次影响。
5. **诚实标注**：本次验收三项是我自己跑的，统帅终审会独立复跑。若终审环境的 `python` 不同，
   `fist.py` 走 `sys.executable` 子进程，理论上会有解释器差异——本机实测无。
6. **工作树里仍有大量他人在途改动**（约 80 个文件）。我的提交用 `-- <4 个明确路径>` 隔离，
   `git show --stat` 已确认只有我的 4 个文件，**他人的两个已暂存报告未被带走**（判例-11 后半已核）。

---

## 七、来源

- 前置侦察：`reports/2026-10-25-scout-zeta-list-tools-gap.md`
- 真源：`scripts/_tool_registry.py::real_tools()`
- 修复点：`scripts/fist.py::cmd_list_tools`
- 新守卫：`scripts/check_fist_list_tools_sync.py`
- 电池：`scripts/run_guards.py`（SPECIAL_CASES）+ `scripts/README.md`（条目 + BATTERY-REGISTRATION）
- commit：`cdaaa87e`（已 push：`96348c64..cdaaa87e` → `gitcode/main`）
