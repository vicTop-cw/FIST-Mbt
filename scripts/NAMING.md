# scripts/ 命名规范（TASK-008 第一批）

判据真源：`scripts/check_scripts_naming.py`（读本篇的两条 anchor 行做宇宙分类）。
本篇只定**词法**；哪个文件欠什么名、改名要花多少引用面，由判据与「债清单」出数，不在散文里抄读数。

## 定律

1. **角色必须写在名字的两端之一**：要么以角色前缀开头（`check_*` 一眼是门禁），要么以角色后缀结尾
   （`*_verify.py` 一眼是验证件）。既无前缀又无后缀的名字，看文件名猜不出它是门禁、工具还是补丁 —— 这是债。
2. **分隔符只有 `_`**：文件名里出现 `-` 的模块不可 `import`，在 shell 里与在 Python 里被切成的词还不一样
   （`fist-gate.py` 在 bash 里是一个词、在 Python 里是 `fist` 减 `gate`）。
3. **归档面不回写**（改名成本的硬边界）：`memory/`、`reports/`、`stories/`、`docs/` 记的是**当时真跑过的命令**，
   为一次改名把它们改成别的字面量就是把记录改成事后叙述。判据的宇宙因此只取 `scripts/` 顶层，
   改名波及的引用面按「活面必改、归档面不改」处理（两面的实测构成见下）。

## 角色前缀

`naming-roles-prefix:` check_, gen_, patch_, run_, clean_, cleanup_, migrate_, build_, sync_, emit_, report_, test_, e2e_

| 前缀 | 语义 | 例 |
|---|---|---|
| `check_` | 门禁/判据：退出码即裁决，不产生产物 | `check_doc_surface.py` |
| `gen_` | 生成器：产物是别的文件（投影/脚手架），手写那份禁止改 | `gen_plugins.py` |
| `patch_` | 补丁：就地改已有产物的字节，幂等 | `patch_esm_main.py` |
| `run_` | 编排/跑手：把一串别的脚本跑起来并汇总 | `run_guards.py` |
| `clean_` / `cleanup_` | 清场：删除/归档属于它的动作 | `cleanup_artifacts.py` |
| `migrate_` | 迁移：把旧形状的数据搬到新形状，须可重放 | 尚无（保留位） |
| `build_` | 构建：产出可执行/发布物 | `build_release.ps1`（同族） |
| `sync_` | 同步：把 A 面的事实刷到 B 面 | `mbti_sync.py` 族 |
| `emit_` | 产出诊断/事件行，不改被诊断对象 | `check_*` 内共用件 |
| `report_` | 把读数汇成给人看的报告件 | 尚无（保留位） |
| `test_` | 测试件：只在验证回路里跑，不进产品路径 | `test_shim_handshake.py` |
| `e2e_` | 端到端件：起真进程/真产物才观测得到（`scripts/blackbox/` 的主力形态） | `blackbox/e2e_irm_line.py` |

## 角色后缀

`naming-roles-suffix:` _verify, _probe, _demo, _smoke, _selfdrive, _tour, _replay, _preflight, _coldstart, _ab, _gate, _automator

`_verify`=对某面做真跑验证并回写结论 ｜ `_probe`=只观测不判定 ｜ `_demo`=演示件（不进 CI 判定） ｜
`_smoke`=端到端冒烟 ｜ `_selfdrive`=自驱回路的一次轮次 ｜ `_tour`=按协议巡回调用面 ｜
`_replay`/`_preflight`/`_coldstart`/`_ab`=回放/预检/冷启动/对照实验 ｜ `_gate`=合入门 ｜ `_automator`=自动开单件。

## 共享模块白名单（`_` 开头，**不是角色**，是「非独立工具」的标记）

`naming-shared-modules:` _badge_anchor.py, _deployment_symbols.py, _tool_registry.py

**为什么需要这一行**：`_` 开头的文件是**被别的脚本 import 的共享件**，不是可独立执行的工具，
按「前缀/后缀=角色」的词法它必然落进 N1。但**「共享件」本身是一个真实角色**，只是它的标记法是 `_`
（与 `check_battery_count_doc` 的 `("_", ...)` 豁免规则同源）。

**⚠️ 为什么是「白名单 + 显式登记」而不是「文件头自述共享模块 ⇒ 豁免」**：
后者等于**「写一句注释就绕过判据」**（判例-30 自指假绿的变体）——
绕过成本从「改一个文档」降成「在目标文件里加一句」，而且会随「谁写得好听」而扩大
（下一个人写「本文件是共享真源的只读投影」也能过）。

**⇒ 判例：豁免必须付出「改另一个文件」的代价，否则它不是豁免是后门。**
本行与 `prefix`/`suffix` 同构：**判据从本文件现读**，改白名单 = 改判据，review 时可见。

**加入条件（逐条标明「机核 / 靠 review」—— 混在一起会让人以为全都自动核了）**：

| # | 条件 | 谁核 | 判据怎么核 |
|---|---|---|---|
| 1 | 文件名以 `_` 开头 | **机核** | 白名单行解析时逐个查，非 `_` 开头 ⇒ `[自拒]` |
| 2 | **不被 `run_guards.py` 登记为独立电池格** | **机核** | 扫 `run_guards.py` 里有没有 `"<name>"` 登记；有 ⇒ 它是判据不是共享件 ⇒ `[自拒]` |
| 3 | **被别的 `scripts/**/*.py` 以任何方式引用** | **机核（有盲区）** | 见下「引用形态」；**零引用 ⇒ 红** |
| 4 | 它**属于共享真源**（而不是「碰巧被一个脚本用到」） | **⚠️ 靠 review** | **判据不核，也不该核**（这是语义判断，机器判不了） |

**⚠️ 第 4 条为什么明写「靠 review」而不是混在列表里**：
「属于共享真源」是**语义判断**，机器判不了。把它和 1-3 并列写，读的人会以为四条都自动核了 ——
**而实际上只有前三条是。** ⇒ **说不清的条件不许伪装成已机核。**

**第 4 条靠什么保证有人看**：白名单是**低频改动**（R51 至今 3 条，0 次新增），
每次改动都在 `NAMING.md` 的 diff 里，**review 时一眼可见**（这是方案 D 选它而 not 读文件头的原因）。
**若将来白名单增长到需要「有人专门审」，那时它就不该再是白名单了 —— 那是另一个信号。**

**引用形态（第 3 条判据认哪些，以及它的盲区）**：
- ✅ `import _x` / `from _x import ...`
- ✅ `subprocess.*(…, "_x.py", …)` / `Popen([…, "_x.py"])` —— 按 `subprocess` 调不是 `import`，但**也是共享件被用**
- ✅ `importlib` / `runpy` 动态加载（按文件名出现算）
- ⚠️ **盲区**：把文件名拼出来的引用（如 `"_" + "badge_anchor" + ".py"`）、符号链接、跨仓库引用
  —— **判据认不出，会误红**。出现这种情形时**在白名单行尾加 `# 引用形态特殊：<说明>`**，
  判据见到该注释即降为 WARN（**不静默放行，也不硬红**）。

**⚠️ 未进白名单的 `_` 文件照样算 N1 债** —— 例如 `_new_script_hygiene.py` / `_run_check_t0r21.py`
**是可独立执行的判据**（只是名字带 `_`），它们的正确归宿是改名 `check_*.py`，不是进白名单。

## 判定面（共用棘轮，只许下降）

- **N1 无角色名**：`scripts/` 顶层 `.py` 里既不带角色前缀也不带角色后缀的份数。
- **N2 连字符名**：同一宇宙里 basename 含 `-` 的份数。
- 只报不判、必须出数：子目录（`scripts/blackbox/` 等）里的同类份数 —— 本轮不判（TASK-008 acceptance 把子目录列为低优先级），
  但必须打印，否则「顶层 16 份」会被读成「全仓就 16 份」。

自拒（真给 2）：宇宙为空、本篇缺失、两条 anchor 行任一条解析不到词 —— 判据读不到词法就无权说「都合规」。

## 用法

```
python scripts/check_scripts_naming.py              # 全量（判定面 ≤ 棘轮上限 ⇒ 0）
python scripts/check_scripts_naming.py --show        # 列 N1/N2 名单 + 子目录只报面
python scripts/check_scripts_naming.py --selftest    # 合成夹具自证 + 真源码对照
```

## 改名成本的实测构成（2026-10-22，`git grep -c -F` 逐名统计 46 份候选名）

| 面 | 引用命中 | 涉及文件 | 处理 |
|---|---|---|---|
| 活面（`scripts/` + `.github/workflows/`） | 163 | 32 | **必改**，判据与 CI 都在这里 |
| 归档面（`memory/` `reports/` `stories/` `docs/`） | 944 | 227 | **不改**（定律 3） |
| 其余（根 `README`/`AGENTS`/`USAGE`/`BACKLOG`/`CHANGELOG`、`plugins/` 投影、`dist/` 产物、`cmd/`） | 117 | 35 | 投影件由 `gen_plugins.py` 重生成；`dist/` 是产物；根文档必改 |

全仓一次性改 46 份 = 动 1224 处引用、其中 **944 处在归档面**。TASK-008 acceptance 第 3 条「CI / run_guards / docs 里的引用全部更新」
照字面执行就会撞上定律 3，所以改名范围是 owner 的裁决项，不是本判据的默认动作。判据的作用是把债钉成**只许下降的数**，
让「改一批、少一批」这一步可验证。

## 债清单（N1，改名建议按定律 1）

| 现名 | 角色缺位 | 建议 | 活面引用 |
|---|---|---|---|
| `_run_check_t0r21.py` | 下划线开头 + 轮次号烤进文件名 | 临时件，移出 `scripts/` 或 `check_t0r21.py` | 0 |
| `_tool_registry.py` | 数据件混在脚本宇宙 | 移入 `scripts/data/` 或 `registry_data.py` 并登记豁免 | 53（含归档） |
| `calibrate_goal_drift.py` | 动词没在表里 | `run_calibrate_goal_drift.py` | 低 |
| `fist-gate.py` | N1+N2 双债 | `check_fist_gate.py`（它本是合入门） | 70 |
| `fist-mbt-http.py` / `fist-mbt-web.py` | N1+N2 | `run_http_panel.py` / `run_web_panel.py` | 58 / 26 |
| `fist-pr-automator.py` | N1+N2（`_automator` 后缀被 `-` 隔断） | `fist_pr_automator.py` | 26 |
| `fist.py` | 主入口无角色 | `run_fist_cli.py`（入口搬家要同步 `check_entry_paths`） | 175 |
| `fist_mbt_mcp_client.py` | 名词串 | `mcp_client_probe.py` | 低 |
| `issue_scan.py` | 与 MCP 工具同名但只是 helper | `run_issue_scan_helper.py` | 36 |
| `laya_decide.py` | 名词 | `run_laya_decide.py` | 32 |
| `mcp_bug_loop.py` | 名词 | `run_mcp_bug_loop.py` | 低 |
| `output_validate.py` | 名词化的验收件 | `check_output_validate.py` | 低 |
| `pentad_fist.py` | 驱动另一项目的件，名字两头都猜不出 | `run_pentad_fist.py` | 低 |
| `simulate_head_commit.py` | 动词不在表里 | `_verify` 族：`simulate_head_commit_verify.py` | 低 |
| `whisperer.py` | 编排件用人名命名 | `run_whisperer.py`（它与 `whisperer_patrol.py` 的分工见 scripts/README） | 74 |

> 表里的「活面引用」只是**成本档**，不是改名许可。动哪个文件名，先量它自己的活面/归档面命中数再决定。
