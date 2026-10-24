# 文档一致性与手抄数字普查（C 路 · verify 模式）

> **模式**：`verify`（API 枚举与完备性验证，文档面）· `require_api_enum + require_doc_check`
> **板块**：`docs/` + 根级 `*.md` 的文档一致性
> **执行**：司令-ζ　**基线 commit**：`0f63b055`　**日期**：2026-10-24
> **纪律**：主仓作业（未开 worktree）· **未改任何文档**（本报告是唯一新增文件）· verify 只出清单

---

## 摘要（先读这一段）

三支文档面门禁**全绿**，但它们在扫描面上留了两个真实缺口，本报告抓出 **3 处漂移 + 1 处判据盲区 + 1 处索引缺项**：

| # | 类别 | 位置 | 写的 | 真源 | 判定 |
|---|---|---|---|---|---|
| **D1** | 手抄数字漂移 | `docs/deliverable.md:17` | **130** 个工具 | **170** | 🔴 落后 **40** |
| **D2** | 手抄组数漂移 | `README.md:11` | **17 组** | **18 组** | 🔴 少 1 组 |
| **D3** | 判例编号悬空 | `merge-precedents.md` | 只定义判例 **1~6** | 全仓引用 **8,9,10,11,12** | 🟠 **5 个编号、30 处引用无定义** |
| **B1** | 判据盲区 | `check_doc_surface.J3` | 只扫「功能全景」标题行 | README 全身 | 🟡 README:11 因此逃检 |
| **B2** | 判据盲区 | `check_doc_surface.J14_FACES` | 5 面白名单 | 缺 `docs/deliverable.md` | 🟡 130 因此逃检 |

**关键判断**：D1/D2 之所以能长期绿着，不是因为没人写尺，而是**尺子只量它认领的那一小面**——
这正是本仓 BUG-363 的原定律（"尺子只量它自己认领的面，没认领的面等于不存在"）的**第 N 次复发**。

---

## 一、真源基线（全部本会话实测）

| 项 | 真源值 | 取证命令 | 读数 |
|---|---|---|---|
| 版本 | **0.3.10** | `grep version moon.mod` | `version = "0.3.10"` |
| MCP 工具 | **170** | `python scripts/check_tools_sync.py` | `server.mbt 注册 170 个` |
| resources | **3** | `grep -c 's1.resource(' src/server/server.mbt` | `3` |
| prompts | **2** | `grep -c 's1.prompt(' src/server/server.mbt` | `2` |
| 测试 | **1455 / 1455 / failed 0** | `python scripts/moon_test_env.py --raw-log temp/pt27.log --target js` | `Total tests: 1455, passed: 1455, failed: 0.` |
| 判据总尺 | **116**（CI 45 / 电池 76 / 门禁尺 84） | `python scripts/run_guards.py --list` | `尺 116 把 / CI 面 45 / 电池面 76 / 缺执行面 0` |
| CLI 分组标题数 | **18** 组，括号和 = **170** | 解析 README `^### .*（N）` | `[14,2,14,9,28,5,3,27,11,5,5,12,2,6,7,8,5,7]` sum=170 |
| `fist.py list-tools` | **152** | `python scripts/fist.py list-tools` | `共 152 个工具` |

> **1455 的旁证**：`temp/pt27.log` 生成前**不存在**（`ls` = MISSING），本会话用
> `--raw-log` 现跑一次落盘，因此 1455 是**本机现读**而非历史抄录。

---

## 二、文档面判据读数（三支全绿）

```
$ python scripts/check_doc_surface.py
PASS 文档面一致：170 工具在 AGENTS/README 逐个可查、分组和=170、当前自述版本=0.3.10、
     J6 规范正文↔投影一致、J7 无旧口径、J8 模板调用面契约干净、J9 返回契约未退化、
     J10 判据范围自述==实现、J11 CI native 门步骤↔账本/规范面 三向对表、
     J12 CI 的 if: 不钉分支名、J13 发布状态短语↔BACKLOG release-fact 对表、
     J14 工具计数自述与 CLI 分组和↔真源对表、J15 docs/ 归档文档文件名日期前缀、
     J17 工具链地板↔toolchain.json 单一真源对表
rc=0

$ python scripts/check_test_sync.py temp/pt27.log
PASS 测试总数单一真源一致：实测 1455；扫描现状面 139 份文档，23 条声明全部等于实测；
     must-carry 5 份齐全；豁免 22 条全部有效
rc=0

$ python scripts/check_badge.py temp/pt27.log README.md
PASS 徽章一致：README tests-1455%2F1455 == 实测 1455/1455
PASS 自检注释一致：README 『→ Total tests: 1455, passed: 1455』 == 实测 1455
rc=0
```

**结论**：三支尺都 PASS，**但下面 D1/D2 两条漂移就在它们的扫描面之外**。
"全绿"在这里**不构成"文档一致"的证据**——这正是本报告要补的洞。

---

## 三、手抄数字清单（逐条核真源）

### 3.1 🔴 D1：`docs/deliverable.md:17` 工具数落后 40

```
docs/deliverable.md:17:  | MCP 工具 | **130**（+ 3 resources + 2 prompts） |
                                     ^^^^^ 真源 170
```

| 项 | 值 | 判定 |
|---|---|---|
| 文档写的 | **130** | — |
| 真源实测 | **170** | `check_tools_sync` |
| 差额 | **−40** | 🔴 反向 overclaim（虚低） |

**为什么尺子没抓到**：`check_doc_surface` 的 `J14_FACES` 白名单只有 5 面 ——
`src/server/server.mbt` / `cmd/cli/help_topics.mbt` / `ARCHITECTURE.md` /
`templates/tool_use_rubric.md` / `docs/agent-map.md`。**`docs/deliverable.md` 不在其中。**
`check_tools_sync` 的 `RE_TOOL_CLAIM` 是窄口径（要求字面含 "MCP"），而这一行写的是
`| MCP 工具 | **130**` —— "MCP 工具" 与数字被表格分隔符隔开，两条正则都不命中。

> **同文件自相矛盾**：同一份 `docs/deliverable.md` 第 11 行写 `140+ 个 MCP 工具`（下限式，正确），
> 第 17 行写 `130`（精确式，错）。**同一份文档里对同一个量给出两个不同的数**，
> 且其中一个是下限式 `140+` —— 而 130 < 140，两个声明**互相打架**。

### 3.2 🔴 D2：`README.md:11` 组数少 1

```
README.md:11:  ...全部以 **170 个 MCP 工具**（17 组）暴露给任意 MCP 客户端。
                                            ^^^^^^ 实际 18 组
README.md:58:  ## 功能全景（170 个 MCP 工具 · 18 组）      ← 这里是对的
```

| 项 | 值 | 判定 |
|---|---|---|
| L11 写的 | **17 组** | 🔴 |
| L58 写的 | **18 组** | ✅ |
| 实际分组标题数 | **18** | ✅（括号和 = 170） |

**同一份 README 内自相矛盾**：L11 与 L58 对同一件事给了两个数。

**为什么尺子没抓到（B1 盲区根因）**：
```python
RE_J3_HEADING = re.compile(r"^##+\s*功能全景.*$", re.M)   # 只匹配 L58 那种标题行
RE_J3_GROUPN  = re.compile(r"(\d+)\s*组")
def j3_readme_group_count_problems(readme_txt, parsed_counts):
    head = RE_J3_HEADING.search(readme_txt)        # ← 只取「功能全景」那一行
    claims = [int(x) for x in RE_J3_GROUPN.findall(head.group(0))]  # ← 只在这一行里找
```
J3 的**设计意图是对的**（`scripts/README.md:129` 明写会抓 "README 标题写 17 组而正文 18 个分组标题"），
但它只读**一个标题行**，而 `17 组` 在正文第 11 行 ⇒ **J3 从未看见它**。
实测复现：
```
parsed group headings: 18  sum: 170
J3 result on REAL README: PASS (no problems)      ← 真 README 上 PASS
RE_J3_HEADING matched line: '## 功能全景（170 个 MCP 工具 · 18 组）'
claims found in that line: ['18']                 ← 只有 18，L11 的 17 不在面内
```

> **历史事实核对**：`memory/bugs.md:5859` 记录 BUG-363② 当年提的正是这个形状
> （"README 标题写 17 组而正文 18 个分组标题"）。BUG-363② **修了标题行那一处，
> 但 L11 的那一句从来没进过扫描面** ⇒ 修一半就是这个结果：标题对了，句子还错着。

### 3.3 ✅ 已核验为**正确**的声明（不必改）

| 位置 | 声明 | 真源 | 判定 |
|---|---|---|---|
| `README.md:11,58` | 170 个 MCP 工具 | 170 | ✅ |
| `README.md:58` | 18 组 | 18 | ✅ |
| `AGENTS.md:168` | **140+** 个 MCP 工具 + 3 resources + 2 prompts | 170/3/2 | ✅ 下限式，170≥140 |
| `README_EN.md:101` | 170 tools + 3 resources + 2 prompts | 170/3/2 | ✅ |
| `docs/agent-map.md:27` | 170 个工具+3 resources+2 prompts | 170/3/2 | ✅（BUG-363① 已修） |
| `docs/agent-map.md:12,61` | 实测 170 个工具 | 170 | ✅ |
| `docs/deliverable.md:11` | 140+ 个 MCP 工具 | 170 | ✅ 下限式 |
| `docs/deliverable.md:18` | 测试 1455/1455 | 1455 | ✅ |
| `BACKLOG.md:6` | 「本行原本写着 120 工具…」（自我说明已修） | — | ✅ 非现状声明 |
| `scripts/README.md` 全文 | 116 把尺 | 116 | ✅ |

> **下限式 vs 精确式**：`140+` 是本仓刻意采用的**防漂移写法**（`check_tools_sync` 注释：
> "下限式治「写死一个数就是下一颗漂移雷」"）。**D1 的 130 是精确式且已错**，正是下限式要防的那类。

### 3.4 历史面（不改数，已豁免）

以下命中**均为历史截面记录**，按本仓定律（"历史面不改数"）**不判漂移**：

| 位置 | 内容 | 处置 |
|---|---|---|
| `memory/research/_snapshot.md:7,58` | 104 个 MCP 工具 / 317 测试 | 历史快照，豁免 |
| `memory/research/competition.md:5` | 61 个工具 / 148 测试 | 历史快照，豁免 |
| `docs/archive/improvement-plan-20260929.md` | 87/104/129 个工具 | 归档，J15 豁免面 |
| `.agents/worktrees/**` | 152+/122 等 | **非跟踪面**（独立 worktree），不属文档面 |

---

## 四、一源四态：第 2、3 态（CLI / skill）枚举完备性

`check_plugin_sync` 管第 4 态（插件）。本报告补查第 2 态（CLI）与第 3 态（skill）。

### 4.1 第 2 态 CLI：`list-tools` = 152 vs 真源 170（**18 个差额已解释清楚**）

```
$ python scripts/fist.py list-tools | tail -1
共 152 个工具
```

| 集合 | 数量 |
|---|---|
| `_tool_registry.real_tools()`（真源） | **170** |
| `fist.py list-tools`（CLI 面） | **152** |
| 差 | **18** |

**逐名差集（`MCP 有 / list-tools 无`，共 18 个，`list-tools 有 / MCP 无` = 0）**：

| 家族 | 工具 | 个数 | 注册形态 |
|---|---|---|---|
| 超级管家 | `supervisor_status` / `supervisor_task_tree` / `supervisor_kill_plan` / `supervisor_prompt_inject` / `supervisor_prompt_list` / `supervisor_prompt_consume` / `supervisor_task_upsert` / `supervisor_reminder_tick` | 8 | `instrumented_tool` |
| 六顶帽 | `hat_run` / `hat_debate` / `hat_merge` | 3 | `instrumented_tool` |
| 嵌入式 MCPCf | `mcpcf.ops_init` / `mcpcf.circuit` / `mcpcf.report` / `mcpcf.review` / `mcpcf.run_batch` / `mcpcf.verify` / `mcpcf.watchdog` | 7 | 链式 `s.tool` in `mcpcf_embed.mbt` |

**机制核对**：
- `src/server/` 里 `instrumented_tool(` 出现 **164** 次（含 1 处 `pub fn` 定义）⇒ **163** 处注册
- `mcpcf_embed.mbt` 链式 `.tool(` **7** 处
- 163 + 7 = **170** ✅ 与真源吻合

**判定**：🟡 **不是漂移，但 CLI 帮助面不完备。** `list-tools` 只枚举了 `instrumented_tool` 之外的
152 个工具，**18 个 `instrumented_tool`/链式注册的工具在 CLI 面不可见**。
（`RE_TOOL_CHAIN` 能抓链式，但 `fist.py list-tools` 是从**运行态 tools/list** 取的，
所以它反映的是**服务端实际注册面**，而 152 说明这 18 个在运行态没进 tools/list —— 需 owner 判：
是 run-time 未注册（真缺态），还是 list-tools 工具自身过滤面问题。）

> **本报告不做断言**：`instrumented_tool` 的语义是"带 instrument 包装注册"，理论上都会进 tools/list。
> 实测 152 说明有 18 个没进。**这是"第 2 态枚举不完备"的硬证据，但根因需另查**（我只出清单）。

### 4.2 第 3 态 skill：4 宿主，`deepseek-harness` 少一个 skill（**按设计，不是缺态**）

```
plugins/atomcode/skills/        fist-commander  fist-mbt
plugins/codearts/skills/        fist-commander  fist-mbt
plugins/claude/skills/          fist-commander  fist-mbt
plugins/deepseek-harness/skills/                fist-mbt     ← 少 fist-commander
```

初看像缺态，**核对生成器后确认是设计**：
```
scripts/gen_plugins.py:21   plugins/deepseek-harness/skills/fist-mbt/ + instructions.append.md
scripts/gen_plugins.py:423  # ③ deepseek-harness：宿主以单一 instructions 文件为规则入口
scripts/gen_plugins.py:508  | DeepSeek Harness | instructions.append.md + skills/fist-mbt/ |
```
`check_plugin_sync` 独立复核：
```
PASS 插件态一致：4 宿主 / 64 个生成文件 / 170 工具 / v0.3.10 / 启动参数真源 .mcp.dev.json
rc=0
```
**判定**：✅ **非缺态**。deepseek-harness 用 `instructions.append.md` 作单一规则入口，
`fist-commander` 的职责被并入该文件，故不另发 skill。**这是四宿主的合法不对称**，不应"补齐"。

### 4.3 四态对照小结

| 态 | 载体 | 数量面 | 判定 |
|---|---|---|---|
| 1 MCP | `src/server/*.mbt` 注册 | **170** | ✅ 真源 |
| 2 CLI | `fist.py list-tools` | **152** | 🟡 差 18（见 4.1，根因待查） |
| 3 skill | `plugins/*/skills/` | 7 个 skill 目录（3+3+2+2=10? 见下） | ✅ 不对称合法（见 4.2） |
| 4 插件 | `plugins/<host>/` | **4 宿主 / 64 文件** | ✅ `check_plugin_sync` PASS |

> skill 目录实测：atomcode 2 / codearts 2 / claude 2 / deepseek-harness 1 = **7 个 skill 目录**，
> 但其字节来源只有 2 份真源（`SKILL.md` + `SKILL.commander.md`），deepseek-harness 只投影前者。

---

## 五、三份新报告的数字矛盾表

### 5.1 worktree 数

| 报告 | 写的 | 性质 | 判定 |
|---|---|---|---|
| `asset-preservation-proof.md:85` | 8 个 worktree | **历史审计结论**（"v1/v2 里…的 8 个 worktree，结论一律无效"） | ✅ 非现状声明 |
| `branch-cleanup-execution.md:85` | 8 个 worktree | 同上，引述证明书 §3.3 | ✅ 非现状声明 |
| `merge-precedents.md` | 未提 | — | ✅ |
| **本机现读** | `git worktree list` = **14** | 当前真实状态 | ⚠️ 见下 |

**判定**：🟢 **不矛盾**。两处 `8` 都带明确限定语（"v1/v2 里…结论一律无效"），是**被推翻的旧口径引述**，
不是现状断言。当前 14 个 worktree 与 8 不冲突。

> ⚠️ **但请注意**：`asset-preservation-proof.md:5` 的版本沿革写「worktree 口径定案 **35**」，
> 与 `8` 和 `14` 三个数并存。经读上下文，`35` 是**口径编号**（"口径定案 35"），不是 worktree 数量 ⇒ 非矛盾。
> 这类"数字旁邻术语"是手抄数字普查的主要假阳来源，**已逐条排除**。

### 5.2 分支数

| 报告 | 写的 | 本机现读 | 判定 |
|---|---|---|---|
| `asset-preservation-proof.md:124` | 148 支分支 | gitcode **155** / origin **52** / 本地+远程 **300** | ⚠️ 历史读数 |
| 同上 | "完整排除面把 151 支假阳压到 1 支" | — | 内部自洽 |
| `branch-cleanup-execution.md:25,157` | 65 支本地分支 | — | 历史读数 |
| 同上:37 | 4 支当前被 worktree | — | 历史读数 |

**判定**：🟡 **这些是"某一时刻读数"，非现状断言**。三份报告共享同一时点快照（2026-10-24 早间），
彼此**不矛盾**（148 / 151 / 65 是**三个不同的量**：有独有新增文件的分支 / 排除面后的假阳基数 / 本地分支），
但与**当前**状态（155/52/14）已不同。

**建议**：这三份是**带时点戳的执行报告**，按本仓定律不改历史数；
但**若有人拿它们当"当前资产清单"用**就会错——这属使用时风险，不是文档缺陷。**本条不计为漂移。**

### 5.3 🟠 D3：判例编号悬空（**这是真矛盾**）

`reports/2026-10-24-merge-precedents.md` 定义的判例：

| 编号 | 标题 | 行 |
|---|---|---|
| 判例-1 | 基线倒退判据（本批最重要的一条） | 10 |
| 判例-2 | 合入前必须预演 | 33 |
| 判例-3 | 改名不是接线 | 44 |
| 判例-4 | 哨兵值必须证明不在合法值域内 | 74 |
| 判例-5 | 判据存在但没接线 = 等于没判据 | 90 |
| 判例-6 | 删除一个跟踪件，会让所有历史分支都"新增"它 | 109 |

**全仓引用到的判例编号**：`判例-1 ~ 判例-6`（册内有定义）+ `判例-8,9,10,11,12`（**册内无定义**）

| 缺失编号 | 引用处（`git grep -c` 实测） | 严重度 |
|---|---|---|
| **判例-7** | **零引用** ⇒ 不是悬空，只是编号跳号 | ✅ 无需处理 |
| **判例-8** | `asset-preservation-proof.md` ×1、`polish-plugins-cl7.md` ×2 | 🟠 3 处引用无定义 |
| **判例-9** | `asset-preservation-proof.md` ×1 | 🟠 1 处 |
| **判例-10** | `asset-preservation-proof.md` ×9、`branch-cleanup-execution.md` ×10、`polish-plugins-cl7.md` ×2、`scripts/README.md` ×1 | 🔴 **22 处引用无定义（最严重）** |
| **判例-11** | `verify-guards-completeness.md` ×3 | 🟠 3 处 |
| **判例-12** | `scripts/README.md` ×1 | 🟠 1 处 |

**根因核对**：
```
$ git log --oneline -3 -- reports/2026-10-24-merge-precedents.md
ffee8d52 fix(guard)+docs(precedent): J2 调用面接线（33→31）+ 判例-6 + 电池锚点归位
3897d378 docs(report): 新增「判例集」——本批多司令合并作业沉淀的 5 条判据
$ git show HEAD:reports/2026-10-24-merge-precedents.md | grep -cE '判例-?(7|8|9|10|11|12)'
0
```
`3897d378` 建册时是 **5 条**，`ffee8d52` 加判例-6 ⇒ 现在 6 条。
**但报告把它当"判例集总账"引用，而实际只收了 6 条；其余判例散落在别的报告正文里，从未归册。**

**判定**：🟠 **真矛盾（索引不完备）**。判例-8/9/10/12 在至少 4 份文档里被当"已定义的判例"引用，
但装定义的册子里查不到。读者按图索骥会撞空。**建议把散落的判例归册，或把引用改成指示真实出处。**

---

## 六、判据盲区清单（根因，供派修参考）

| # | 盲区 | 机制 | 证据 | 建议 |
|---|---|---|---|---|
| **B1** | J3 只扫「功能全景」标题行 | `RE_J3_HEADING` 只匹配 `^##+ 功能全景`，`claims` 只从该行提取 | README:11 的 `17 组` 在面外，J3 实测 PASS | 把 `RE_J3_GROUPN` 的扫描面从"标题行"扩到 README 全文（并加反向对照：L58 仍须命中） |
| **B2** | J14_FACES 缺 `docs/deliverable.md` | 5 面白名单硬编码，deliverable 不在其中 | `130` vs 170，J14 PASS | 把 `docs/deliverable.md` 加进 `J14_FACES`（`RE_TOOL_CLAIM` 还需能认 `\| MCP 工具 \| **130**` 表格形态） |
| **B3** | `RE_TOOL_CLAIM` 不认表格分隔形态 | 要求数字与「MCP 工具」紧邻 | `\| MCP 工具 \| **130**` 不命中 | 扩正则或加表格专用形态 |

> **为什么把根因写在本报告**：D1/D2 是**症状**，B1/B2/B3 是**成因**。
> 只修 D1/D2（改文档）而不修 B1/B2/B3，下一批文档还会在同样的缝里漂 —— 这正是 BUG-363 复发的路径。

---

## 七、超出一源四态的观察（不作结论）

1. **`check_doc_surface` 的 PASS 行不列 J16，但 J16 确实在跑**（**已复核，不是缺陷**）：
   ```
   839: def j16_help_tool_names_problems(help_text, tools):
   873:     problems += j16_help_tool_names_problems(texts.get(J14_HELP, ""), tools)
   ```
   J16（CLI 帮助分组表逐个工具名 == 真源集合）**已接线并被 `main()` 调用**，
   只是 J14/J16 共用同一 CLI 帮助面，PASS 文案把两者合写进 "J14 … 对表" 一行。
   ⇒ **不是"有实现无登记"**，属可读性小瑕疵（建议 J14/J16 在 PASS 行分列），**不计为漂移**。
2. **`判例-11` 出现在 `verify-guards-completeness.md`，但同样未归册**（**已复核**）：
   ```
   reports/2026-10-24-verify-guards-completeness.md:297  这恰恰是判例-11「提交前查暂存面」要防的事…
   reports/2026-10-24-verify-guards-completeness.md:298  判例-11 的正确执行是「逐条核对来源」…
   reports/2026-10-24-verify-guards-completeness.md:305  判例-11 补注：查暂存面 = 逐条核对…
   ```
   内容与统帅任务书的描述一字不差（"提交前 `git diff --cached --name-only`"），
   ⇒ **与 D3 完全同族**：判例-11 被引用、有内容、但**不在判例集里**。
   **D3 的规模因此从 4 个悬空编号扩到 5 个（7/8/9/10/11/12 中的 8/9/10/11/12）**。

---

## 八、结论

1. **三支文档面门禁全绿**，但"绿"不等于"一致"——两个真实漂移就在扫描面外。
2. **3 处漂移**：D1（deliverable 130→170）、D2（README 17→18 组）、D3（判例 8~12 共 30 处引用无定义，其中判例-10 占 22 处）。
3. **3 处判据盲区**： B1（J3 标题行）、B2（J14_FACES 缺面）、B3（表格形态不认）。
4. **第 2 态 CLI 不完备**：`list-tools` 152 / 真源 170，差 18 已逐名解释，根因待查。
5. **第 3 态 skill 无缺态**：deepseek-harness 少 `fist-commander` 是设计，不应补齐。
6. **三份报告不互相矛盾**：8/148/65 均为带限定语的历史读数，非现状断言。

**修复建议优先级**：先修 B1/B2/B3（判据），再修 D1/D2（文档），最后归册 D3（判例）。
反过来做就只是把这一次的表象抹掉。

---

## 来源

- 真源：`moon.mod` / `src/server/*.mbt` / `scripts/_tool_registry.py` / `scripts/run_guards.py`
- 判据：`check_doc_surface.py`（J1-J17）/ `check_tools_sync.py` / `check_test_sync.py` / `check_badge.py` / `check_plugin_sync.py`
- 实测日志：`temp/pt27.log`（本会话现跑，`Total tests: 1455, passed: 1455, failed: 0`）
- 基线 commit：`0f63b055`
