# AI 项目开发规范（R116 · 规范性正文）

> **位置**：仓库根（与 `README.md`/`AGENTS.md` 同级）——它是所有项目共用的开发基线，不隶属于某个包的文档目录。
> **规范性文件（normative）**：任何由 AI agent 开发或维护的项目（下称**目标项目**）都以本文件为开发基线。
> **一源四态**在本文件上的落地方式：本文件 = 规范的**人类可读真源**；`project_standards` 工具（`src/server/project_standards.mbt`）= 同一规则的**机器投影**；两者由 `scripts/check_doc_surface.py` 的 J6 判据强制一致（缺任一规则 id 或版本号不一致即红）。README / AGENTS.md / `docs/project-standards-skill.md` 只做**摘要 + 指向本文件**，不各自另写一套口径。
> 机器取用：`python scripts/fist.py call project_standards --include-checklist true`

## 0. 术语

| 术语 | 定义 |
|---|---|
| 真源（single source） | 核心逻辑唯一手写处。FIST-Mbt 的真源语言 = MoonBit。 |
| 四态 | 同一功能的四种形态：**MCP**（工具）/ **CLI**（薄封装脚本）/ **Skill**（何时用·怎么用·怎么闭环）/ **Plugin**（宿主插件目录，**生成投影**非手写）。 |
| 投影 | 由脚本从真源生成、禁止手改的产物（`scripts/gen_plugins.py` → 四宿主插件目录）。 |
| 守卫族 | 把规范转成可执行判据的 CI 脚本：`check_tools_sync` / `check_test_sync` / `check_badge` / `check_scripts_index` / `check_plugin_sync`(cl7) / `check_doc_surface`(J1-J18：含 J9 工具描述返回契约、J10 判据范围自述==实现、J11 CI native 门步骤↔账本/规范面对表、J12 CI 的 `if:` 不钉分支名（恒假门）、J13 发布状态短语↔BACKLOG `release-fact` 对表、J14 工具计数自述与 CLI 分组和/分组数↔真源对表、J15 docs/ 归档文档文件名日期前缀、J17 工具链地板（MoonBit / Node）↔`toolchain.json` 单一真源对表——含 CI 的 `node-version`)。 |
| 证据梯 | L1 报告自述 < L2 工具消息 < L3 测试退出码 < L4 文件系统实际产物（`output_validate`）< L5 Omega 复验。**验收下限 = L4。** |
| 账本 | `memory/bugs.md`：追加式缺陷账本，无关闭 API ⇒ 用 `### FIXED(...)` / `### NOT-FIXED(...)` 段落表达状态。 |

## 1. 通用 5 条（跨项目复用）

| id | gate | 规范 | 违例判定（可执行） |
|---|---|---|---|
| `r1-doc-as-impl` | hard | **文档即实现**：接口签名/参数/返回 schema 在代码 doc 注释里，在 README 有速查表，在 skill 有使用时机；三者同步，验收先过文档再验功能 | `check_doc_surface` J2/J3（逐名覆盖 + 分组和==实测）、J7（规范性表面不得残留旧口径） |
| `r2-single-source` | hard | **一源四态，单真源优先**：核心逻辑写在单一语言/运行时；CLI/Skill 是薄封装，Plugin 态必须是**生成投影**；禁止在任何形态里重写业务逻辑 | `check_plugin_sync`(cl7) 逐字节 diff；代码审查 CLI 脚本是否含业务分支 |
| `r3-deterministic-first` | hard | **确定性优先于语义性**：能用文件检查/正则/状态机判定的，不让 LLM 自评（`issue_scan`/`output_validate`/`phi_accrual` 全确定性） | 纯计算模块必须有白盒测试；`grep` LLM 调用面 vs 纯计算面比例 |
| `r4-zero-regression` | hard | **增量零回归**：每改一行全量测试必过；临时脚本用完必须清理；可选参数默认关闭 | `moon test --target js` 全绿 + `moon check` 0 errors |
| `r5-self-evolve` | medium | **自我迭代优于一次性构建**：先最小可用，再用自身能力（`evolve_distill`/`evolve_lesson`/`task_challenge`）边做边学、失败回流 | `evolve_snapshot` 有 principle/lesson 条目 |

## 2. 目标项目必备文档集（开发文档规范）

新建/接管一个目标项目时，以下骨架必须齐（缺项=开工前先补，不允许"代码先行文档后补"）：

| 文档 | 必填内容 | 更新时机 | 门禁 |
|---|---|---|---|
| `README.md` | 是什么/为什么/快速上手/能力全景（逐个可查的名字 + 分组计数）/环境要求/已知边界 | 每次对外能力变化 | J2/J3/J4（当前自述版本 == `moon.mod`） |
| `AGENTS.md` | 角色边界、分流决策树、任务包格式、终审与记忆纪律、工具表（逐名） | 编排纪律或工具面变化时 | J2 |
| `CHANGELOG.md` | 每版一条，含 **验证证据**（测试数/门禁 verdict）与**遗留风险** | 每次发版或收口 | J4 豁免（历史陈述） |
| `docs/<feature>-skill.md` | 何时用 / 怎么调（**真实参数名**）/ 各形态关系 / 已知边界 | 每个新工具 | J8（模板与文档的调用示例参数必须等于注册参数集） |
| `memory/bugs.md` | `## BUG-N [时间]` 账本 + `### FIXED/NOT-FIXED` 状态段 | 发现即入账（`report_bug`） | 账本脚本 `bug_list` 可读 |
| `memory/YYYY-MM-DD.md` + `reports/YYYY-MM-DD-<任务>-report.md` | 结论/证据/分析/缺口与风险/建议入档位置 | 每轮终审通过后 | 金条五：缺汇报=轮次未收口 |
| `templates/pipeline_mode_*.md` | 每模式：角色/核心动作/禁止事项/交付物/FIST 调用顺序（真实参数）/红线/汇报格式 | 模式或工具契约变化时 | J8 + `mode_templates` 存在性 |

> **历史豁免边界**：`CHANGELOG.md`、`memory/`、`reports/` 按日期记录当时事实，**不做追改**；对齐只作用于"当前承诺"型表面（README/AGENTS/skill/工具描述/模板）。批量替换历史日志＝把证据改成假话，属违例。

## 3. FIST 专项 5 条 + 自我迭代操作化判据

| id | gate | 规范 |
|---|---|---|
| `f1-use-fist-self` | hard | **必须用 FIST 自身能力迭代开发**：每轮 publish 根任务 → plan/task_plan_deep → claim → execute → submit → verify，且**四个开关必须是活的**（下表）。不用自身能力的改动打回。 |
| `f2-four-forms-aligned` | hard | **四态必须对齐**：新 MCP 工具 = 同步 CLI 封装 + skill 文档 + `gen_plugins.py` 重生成四宿主；插件目录禁手改 |
| `f3-evidence-ladder` | hard | **证据梯至少 L4**：`verify` 前必须 `output_validate` verdict=pass（到文件系统查实际产物） |
| `f4-task-dag` | medium | **重任务先拆 DAG**：跨 3 文件以上先 publish + `task_plan_deep`，按 `dag_ready` 顺序执行 |
| `f5-naming-clarity` | medium | **工具命名即文档**：动宾结构、参数 snake_case；名字与描述不符=契约说谎 |

`f1` 的"自我迭代"不是口号，按下列可量信号验收（**每轮结束用 `call_log` 核对，不靠回忆**）：

| 开关 | 工具/参数 | 活证据 | 违例 |
|---|---|---|---|
| call_log | `call_log({ "project_dir": ".", "limit": 200 })` | 本轮工具调用条数 > 0，且覆盖 `verify`/`output_validate` | 全轮零调用 ⇒ 没走 FIST 生命周期 |
| issue_up（缺陷上报） | `report_bug({ "project_dir": ".", "summary": "...", "severity": "...", "publish_task": true })` | `memory/bugs.md` 本轮新增条目；`bug_list` 可查 | 发现只写进报告不入账 ⇒ 缺陷蒸发 |
| laya（冷启动选档） | `laya_decide({ "context": "...", "split_n_hint": 3 })` | 拆解前有难度/拆分数决策记录（无 sidecar 时降级为内建规则，仍算活） | 直接凭感觉 split_n |
| Omega 强验证 | `task_plan_deep(..., "omega_strong_verify": true)` → `omega_spec_create`/`omega_spec_review`/`omega_result_verify` | `omega_status` 有轮次；语料质量决定验证上限 | 只写"交付物存在"下限语料 |
| 防上下文漂移 | `task_plan_deep(..., "reinject_context": true, "boundary_probe": true)` | 子任务描述含父计划回注 + 边界四问；有 owner 叶负责全局输入域 | 深拆后无人负责地带 |

## 4. 四态验收 checklist（7 项）

| id | gate | 判据（可直接执行） |
|---|---|---|
| `cl1-mcp-exists` | hard | 工具在 `src/server/server.mbt` 有 `instrumented_tool` 块；`tools/list` 可见 |
| `cl2-cli-exists` | hard | `python scripts/fist.py call <tool>` 可路由，或有同义独立脚本 |
| `cl3-skill-doc` | hard | `docs/<tool>-skill.md` 存在且含「何时用/怎么调/已知边界」，参数名与注册集一致（J8） |
| `cl4-tests-pass` | hard | `moon test --target js` 全绿；新功能有正/负路径测试（**负向：能红才算锁**） |
| `cl5-ov-pass` | hard | `output_validate({ "project_dir": ".", "artifacts": [...], "require_evidence": true })` verdict=pass |
| `cl6-doc-sync` | medium | README/AGENTS 工具数、测试数、版本号与真源/`moon.mod` 同步（J2/J3/J4） |
| `cl7-plugin-forms-sync` | hard | `python scripts/gen_plugins.py && python scripts/check_plugin_sync.py` 绿（四宿主 == 真源投影） |

## 4.1 尺的覆盖面自证（判例-16 / 判例-23）

> **尺子只量它自己认领的面，没认领的面等于不存在。**
> 所以「我覆盖什么」这件事本身必须有判据，否则尺的绿只是在说「我看的那一小块没问题」。

### 规则（两条，都是 hard）

| id | gate | 规范 |
|---|---|---|
| `coverage-self-proof` | hard | **任何 `check_*.py` 若声称「我覆盖 X」，必须有一条自证格断言「实际覆盖集合 == 从真源反解的集合」**。禁写死数字。真源举例：`moon.pkg` 的 `pkgtype(kind:"executable")` / `git ls-files '*.mbti'` / `server.mbt` 的工具注册数 / 跟踪面文件名。 |
| `coverage-claim-explicit` | medium | **不得声称超过实际能验的面**：尺的 docstring 里写「扫描面 = 全仓 `*.mbti`」而代码只遍历 3 份，就是契约说谎（与 BUG-43「清单工具写成检查工具」同族）。要么改代码，要么把声称改窄并写明缺口。 |

**判例-16（范围）**：覆盖面 < 主张面 ⇒ 漏掉的部分永远不被发现。
**判例-23（深度）**：面是全的，但**识别方式可绕过**（如按函数名认调用面，改名即绕过）——
两者是不同病：16 靠「对表真源」治，23 靠「改识别形状（AST/调用图）」治。**修 23 属判据语义变更，不要混进覆盖面补丁。**

### 操作形态（一条自证格的模板）

```python
# 断言：实际覆盖面 == 从真源反解的集合（对表两个真源，不写死数字）
_pkgs = executable_pkg_dirs(ROOT)            # 真源 1：扫 moon.pkg 的 pkgtype
_resolved, _unbuilt = resolve_bundles(ROOT, _pkgs)
cell("e2e-coverage-covers-all-built-executables", len(_resolved), len(_pkgs) - len(_unbuilt))
# 附带三条更便宜的护栏：
#   ① 覆盖面非空（空面会让后续检查静默全绿）
#   ② 覆盖面 ⊇ 兜底清单（动态取数不得漏掉关键产物）
#   ③ 覆盖面数 == 真源总数（数字来自两边现算，任一边漂了都红）
```

### 反面实例（2026-10-24 实测三个，**全部由「不硬编码」暴露**）

| 尺 | 写死的清单 | 真源现读 | 后果 |
|---|---|---|---|
| `check_esm_bundle_runnable` | `DEFAULT_BUNDLE = ".../cmd/cli/cli.js"` | 4 个 `executable` 包 | 4 个 bundle 只验 1 个；`commissar.js` / `smoke.js` 漏网不被发现 |
| `check_mbti_eol` | 3 份 `MBTI_FILES` | `git ls-files '*.mbti'` = 24 份 | 另外 21 份谁被 autocrlf 刷脏都报绿 |
| `check_entry_paths` | 豁免面只认 `#` 注释行 | `.py` 的非执行文本还有 docstring 块 | 4 处假阳（解释历史的 docstring 被判「引用退役入口」） |

三把尺修好后都**立刻暴露了原先看不见的东西**：`check_esm_bundle_runnable` 扩面后当场抓到
自己按 `basename(pkg_dir)` 拼路径的错；`check_mbti_eol` 扩面后当场抓到
`src/core/pkg.generated.mbti` 已 dirty。**不硬编码 = 覆盖面变大 = 立刻暴露你自己看不见的错。**

### 常驻自检

`scripts/check_coverage_face.py` 扫 `scripts/check_*.py`，把「有硬编码小清单、且清单进了判定路径」
的形状报出来（可能窄 + 现读真源 + 建议）。它**只报不判**——目标不是「找出所有窄清单」
（做不到），是**「让窄清单变得可见」**（做得到）。

## 5. 一轮标准流程（自驱式四模式）

`bugfind`（寻虫，只读+入账）→ `fix_and_merge`（修复，带回归锁）→ `verify`（验证，只读稽核 + L4 门禁）→ `polish`（打磨，格式/文档/蒸馏），× N 轮。

verify 模式的 FIST 调用顺序（**照抄可用，参数名已核对真源**）：

```
project_standards({ "project_type": "moonbit-mcp", "include_checklist": true })   // 取基准，纯清单不扫描
run_check({ "task_id": "<本轮任务 id>", "cmd": "moon", "args": ["check"], "workdir": ".", "timeout_ms": 120000 })
output_validate({ "project_dir": ".", "artifacts": [ { "path": "AI-DEVELOPMENT-STANDARD.md", "contains": "R116" } ], "require_evidence": true })
report_bug({ "project_dir": ".", "summary": "[verify] file:line: reason", "severity": "high", "publish_task": false })
```

> `project_standards` **没有** `project_dir`/`dry_run`，也不会自己扫描文档——它只下发清单；扫描由调用方（agent/守卫脚本）做。把"清单工具"写成"检查工具"就是契约说谎（见 `memory/bugs.md` BUG-43）。

> **`.` 在两处含义不同、但都合法（BUG-51 统一后的口径，别写成二选一）**：
> `run_check` 的 `workdir` 相对**任务的 project_dir**（`.` 即该任务的项目目录本身，与 project_dir 绝对还是相对无关，
> 实际 spawn 的 cwd 由服务端归一为绝对路径）；`report_bug` / `output_validate` 的 `project_dir` 相对
> **store 根**（只接受相对路径，拒绝对路径/盘符/上跳——那是账本落盘的边界，不是执行边界）。

## 6. 违例分级与处置

- `hard` 违例：当场打回（`reject`）或入账并挂修复任务；不得以"下一轮再说"跳过。
- `medium` 违例：记入 `memory/bugs.md` 与 `BACKLOG.md`，允许本轮收口后处理。
- 判据无法自证（解析到 0 项、数字越界、缺夹具）⇒ **FATAL 退出码 2**，绝不报绿。
- 门禁只能拦"形状"，拦不住"语义"：语义合规靠 verify 模式的实际稽核 + 用户终审，本文件因此要求每轮报告列出**本轮真正跑过的判据**与**未 covered 的边界**。

## 7. 已知边界

- 本文件与 `project_standards` 输出的一致性有守卫（J6/J7）；**其余文档的语义**（例如 skill 里那句"用途"是否名副其实）无守卫，靠 `check_doc_surface` J8 的调用面比对与人工终审。
- `project_standards` 不支持项目自定义追加规则（无 `extra_rules` 参数），`project_type` 仅是上下文标注。
- 四宿主插件目录是生成投影，**未在真实宿主内逐一装载验证**；cl7 只保证"等于投影"，不保证"宿主可用"。
- **native 后端的稳定门槛不是本仓能自己给的**：权威门槛 = JS 后端（Node ≥ 24）。native 全量测试在 `git archive HEAD` 干净树上被依赖 `mizchi/sqlite@0.3.1` 的 FFI 打死（账本 BUG-133），2026-10-01 owner 裁决③把 CI 两条 native 臂改成「常驻判据当门 + 门后才跑全量」：门 = `scripts/blackbox/e2e_native_heap_probe.py`（`--selftest` + `--runs 12`，零本仓业务码），只有 `crashes=0/12` 才放行 `Test (native)`。这条边界**不是把红划成已知边界**——门与全量两格的红话都逐字点名 BUG-133 与它的前置（2026-10-02 实发读数是「门绿 #7/#8、`Test (native…` 红 #8/#9」，全量那一格补了 `::error::` 而退出码照原样传），且依赖侧修好后该臂自己恢复全量覆盖（步骤未删）。另注：该判据是**抽检**（同一支尺、同一次会话连跑两发给出过 `3/12` 与 `0/12` 两端），`0/N` 不等于已修；它的退出码是契约（`0/1/3/4`，`4` 专指尺子自己坏了，绝不冒用 `1`）。
- **`moon test` 自身的退出码不可靠（BUG-142）**：moon 0.1.20260920 实测，测试可执行文件被 SIGABRT 打死（日志 `signal: 6 (SIGABRT)`、`core dumped`、`PanicError`）时 `moon test` 仍回 exit 0。**以 `moon test` 收口的判据必须解析 `Total tests: N, passed: N, failed: 0` 汇总行，并检查输出无 `SIGABRT` / `core dumped` / `signal:`，不得只信 exit 0**——exit 0 只是必要条件，只查退出码的脚本会把崩溃判成通过（假的绿）。
