# 轮 380 唤醒巡检报告（FIST-Mbt-ExploreWatchdog）

- 日期：2026-11-17
- 轮次：380（第 61 轮 WIP 静止态）
- FIST 闭环：T0r136 / agent `wd-r380` / ns `watchdog`

## 结果摘要

WIP 非冻结增长后**静止第 61 轮**：`git status --short` 仍为同一组 8 文件
（6 个已跟踪 M + 2 个 untracked），`src/engine/engine_circuit_test.mbt` 与
`scripts/run_guards.py` 仍 M ⇒ **Round C 三件维持过期不执行**（BUG-527 治本 /
BUG-530 修复 / run_guards 注册 check_usage_tool_count 均未解禁）。
numstat 合计 6 文件 240+/3-，与 r378/r379 逐字相同（零再增长）；`memory/bugs.md`
仍 216/0 零再增长（与 r326~r379 同组零增量）。

本轮走**巡检分支**，换面巡检 **`check_hardcoded_paths`**（「当前面不得写出本机
身份路径」硬编码回归锁——判 A 面词表 `IDEProjects`/`victo` + B 面配置面盘符形状
`X:[\\/]`；豁免面=只追加历史/构建产物/本地产物；三档 rc：0 干净 / 1 命中违例 /
2 判据无法自证；覆盖面真源=`git ls-files`，不硬编码）。本面上次巡检为 **40+ 轮前**
（近 40 轮换面全集零命中），本轮首次覆盖该面、非撞面。

- `--selftest` **rc=0**（15 格全按预期：C0 扫描面非空 / C1 工程目录名→红 /
  C2 豁免面不误红 / C3 合成盘符不误红 / C4 家目录→红 / D1 渲染件回跟踪→红 /
  D1b 模板态不误红 / D2 值面盘符（列表/key 形）→红 / B1 未知本机根形状（配置面）
  →红 / B2 模板占位符行不误红 / B3 注释反例引述不误红 / B4 教学用占位段不误红 /
  B5 代码面夹具合成形不误红 / B6 非 YAML 配置面（JSON）→红 / C5 空扫描面可识别）
  ⇒ **判据本身健康，不是坏尺**
- 实跑 **rc=1**（命中 4 处，全在 `scripts/check_foreign_ledger_entries.py`）：
  - `:165` 注释：`# ── vq 批（2026-11-02 勘误裁定：E:/IDEProjects/AI/vq 的缺陷误落本树…）`
  - `:167` 白名单理由串：`bid: ("foreign", "…缺陷位置在 E:/IDEProjects/AI/vq")`
  - `:319` evidence 夹具：`- evidence: … E:/IDEProjects/AI/vools 的清单见附件`
  - `:325` cwd 夹具：`- detail: cwd=E:\IDEProjects\AI\vools 启动 serve…`

### 根因（守卫互指假阳，非真回归）

`check_foreign_ledger_entries.py` 是**检测「外来路径」的守卫**（BUG-565 后续动作）：
它的外来信号是路径族 token（`crates/`/`apps/`/`vools/<path>` 等）+ 行首署名标签，
**根本不靠 `IDEProjects`/盘符判别**。其 selftest 夹具（319/325）与白名单理由（165/167）
**必须含真实机器身份 `E:/IDEProjects/...`** 才能测到/说明其检测目标。而
`check_hardcoded_paths` 的豁免面**均不覆盖**「守卫自指引用」：

- **B5 夹具豁免只认合成盘符**（`E:/repo/...`、`E:/proj/...`）——真实项目名
  `IDEProjects` 不在此列；
- **B3 只豁免「被禁形状引述」**（注释/docstring 里作为被禁止的形状被引述）——
  165 是溯源注释、167 是理由串、319/325 是夹具，都不是「被禁形状引述」。

⇒ `a9fe6c973`（feat(guards)：新增 check_foreign_legder_entries）把面打红后，
`check_hardcoded_paths` **不在 run_guards 电池内（非 CI 门）**，红了一直静默。
对照：`check_hardcoded_paths` **自己的** selftest 夹具即用合成盘符（`E:/repo`、
`E:/proj`）避免自触发——这是本仓既定惯例；`check_foreign_ledger_entries` 的夹具
却用了真实 `E:/IDEProjects/...`，**违反了这条既定惯例**，这才是根因所在。

### 修复（根因解，不碰尺子）

让被点名文件**回归本仓既定惯例**（夹具用合成盘符、注释/理由用中性措辞），
真实机器身份 `IDEProjects` → 0，`check_hardcoded_paths`（尺子）**零改**：

| 行 | 改前 | 改后 | 依据 |
|---|---|---|---|
| 165 | `…：E:/IDEProjects/AI/vq 的缺陷误落本树…` | `…：vq 项目缺陷误落本树…` | 溯源注释去机器身份，保留「vq 项目」本质事实 |
| 167 | `…缺陷位置在 E:/IDEProjects/AI/vq` | `…缺陷位置在 vq 仓（外部项目）` | 白名单理由去机器身份，保留「外部项目」语义 |
| 319 | `E:/IDEProjects/AI/vools` | `E:/proj/AI/vools` | evidence 夹具改合成盘符（判别锚点是 `crates/vq-core`，非 IDEProjects） |
| 325 | `cwd=E:\IDEProjects\AI\vools` | `cwd=E:\proj\AI\vools` | cwd 夹具改合成盘符（保留双反斜杠转义；锚点是 vools 作 cwd 无 `vools/<path>` 信号） |

### 双判据验证（全绿）

- 残留 `IDEProjects`/`victo`：**0**（grep）
- `check_foreign_ledger_entries --selftest` **rc=0**（15/15 格）：case⑦
  `evidence-citation-not-flagged` 与 case⑧ `ns-cwd-context-not-flagged` 的锚点是
  「evidence 行不扫」+「vools 作 cwd 无 `vools/<path>` 信号」，**不依赖
  `IDEProjects` 字面** ⇒ 换合成盘符不破坏断言
- `check_hardcoded_paths` 实跑**转 rc=0**（`PASS 当前面无本机身份路径（扫描 747 个
  跟踪文件）`）⇒ 假阳已消
- `check_hardcoded_paths --selftest` **rc=0**（尺子未变，仍健康）

### 撞面核对

grep git log 反解近 40 轮换面巡检面（check_store_tables_wired / check_mbti_eol /
check_esm_bundle_runnable / check_precedents_doc / check_model_auth_no_key /
check_doc_paths / check_doc_surface / check_arg_face_strict / check_mcp_stdio_purity /
check_ps_encoding / check_selftest_hermetic / check_exit_code_contract /
check_backlog_status_staleness / check_byte_slice_truncation / check_plan_landing /
check_dead_params / check_delivery_gap / check_demo_isolation / check_effective_catch /
check_entry_paths / check_ns_write_gate_coverage / check_ofm_endpoint /
check_plugin_sync / check_release_asset_names / check_selftest_inventory_doc /
check_sql_bind_alignment / check_stale_self_claim / check_tool_add_completeness /
check_two_faces / check_workflow_step_parity / check_foreign_ledger_entries /
check_host_installable 等）—— **`check_hardcoded_paths` 零命中** ⇒ 本面为本轮换面、
非撞面（且它是近 40 轮里少数从未进过巡检轮的硬编码回归锁面）。

例行的零漂移双核对：
- `check_tools_sync` rc=0：server.mbt 注册 183 个，AGENTS/README/deliverable/
  scoring_rubric 对齐，R3b/R7 扫现状面 168 份、历史面豁免 25 份，R8 清单分组
  19 组 ΣN=183（已与实测 183 对表）
- `check_instruction_budget` rc=0：AGENTS.md 50440/65536 字节全部章节可见

## 资源消耗

- 唤醒巡检一轮；bash 调用约 14 次 + FIST 六步链 1 次（后台串跑，~1 次 node 冷启动）
- 1 个文件改动（`scripts/check_foreign_ledger_entries.py`，非 `.mbt`，无需 moon fmt），
  禁区 WIP 零碰，无新依赖安装

## 任务分配记录

| 步骤 | 工具 | 结果 |
|---|---|---|
| 唤醒巡检 | git status/log/diff | WIP 静止第 61 轮，Round C 不执行 |
| 换面选面 | git log 近 40 轮撞面反解 + 候选陈旧度普查 | 选 check_hardcoded_paths（40+ 轮未用、硬编码回归锁、路径纪律强主题面） |
| 换面巡检 | check_hardcoded_paths selftest | rc=0（15 格，判据健康非坏尺） |
| 换面巡检 | check_hardcoded_paths 实跑 | **rc=1**（命中 4 处，全在 check_foreign_ledger_entries.py） |
| 根因调查 | 读 4 处上下文 + 核 HEAD/电池/git log | 守卫互指假阳：自指引用 + 非 CI 门静默 |
| 修复 | 4 处 edit_file | 夹具改合成盘符 + 注释/理由中性措辞，IDEProjects→0，尺子零改 |
| 双判据验证 | FLT selftest / HC 实跑 / HC selftest | 全绿（15/15 rc=0 / 转 rc=0 747 文件 / rc=0） |
| 零漂移核对 | check_tools_sync / check_instruction_budget | 均 rc=0（183 / 50440/65536） |
| FIST 闭环 | T0r136 六步 | 见文末核实格 |

## 遗留风险

1. **Round C 三件持续过期**：src/** 仍被 WIP 占用，BUG-527/BUG-530/USAGE 注册
   均不能落地——取决于另一 agent 收口 WIP，非本巡检可解除。
2. **第 61 轮静止**：WIP 自 r318 起无增长无收口，已跨半个自然月余；owner 可裁决
   接管收口或回滚该 WIP（不可逆操作，需明确授权，巡检不代行，同 r374/r375/r377/r379）。
3. **`check_hardcoded_paths` 非 CI 门**（本轮根因的「静默」放大器）：它不在
   `run_guards.py` 电池内，红了没人知道——本轮靠换面巡检才照出。**修复它需改
   `run_guards.py`（属 WIP 禁区），留专门轮**：注册为 battery case（selftest + 实跑）
   + 同批提交。
4. **尺子对「守卫自指夹具」无防御性豁免**：任何检测「本机身份路径」的守卫，其
   selftest 夹具若用真实身份就会触发本尺。本轮靠「让被点名文件回归合成盘符惯例」
   解了当前假阳，但**惯例靠自觉、没有尺子盯**——建议评估给 `check_hardcoded_paths`
   加一条「`check_*.py` 内 selftest 夹具/理由串的自指引用」防御性豁免（需谨慎设计，
   避免把真泄漏也豁免掉），或至少把「守卫夹具禁用真实机器身份」写成判例。
5. **r372/r377 真发现仍待专门轮修**（WIP 模板 `templates/pipeline_mode_loop.md:86`
   run_check 示例缺必填；`check_esm_bundle_runnable` 观察一/二）——均不在 WIP 组、
   不阻塞也不被阻塞，规格已备（见 r372/r377 报告）。

## 后续建议

- **下轮候选**：
  - **注册 `check_hardcoded_paths` 进 CI 电池**（本面根因的静默放大器，最高优先）
    ——待 `run_guards.py` 解禁后同批（改 battery case + selftest/实跑）；
  - 或评估尺子对「守卫自指夹具」的防御性豁免（遗留风险 4）；
  - 或继续轮换未巡检面（check_publish_payload / check_release_asset_names /
    check_entry_paths / check_dead_params_py / check_deprecated_text_census 等
    近 40 轮未用面）。
- WIP 收口后按 Round C 队列执行（BUG-527 治本 → BUG-530 → run_guards 注册
  check_usage_tool_count 同批），并**顺带修全 loop.md:86 的 run_check 示例**
  （r372 真发现）+ `check_esm_bundle_runnable` 观察一/二（r377 规格）。
- 基线外外来条目 BUG-613~635 继续待 owner 裁决搬移 vq 仓 / WHITELIST 登记
  （`check_foreign_ledger_entries` 脏树必红 = WIP 投影，非回归；本轮修的夹具是其
  selftest 合成件，与真账本判定无关）。

## 超额内容

无。

## 来源

- git status --short / git log --oneline / git diff --numstat / git show HEAD:（唤醒巡检 + 根因取证，只读实测）
- scripts/check_hardcoded_paths.py --selftest / 实跑 / --selftest（本轮实测）
- scripts/check_foreign_ledger_entries.py 165/167/319/325 上下文 + selftest 断言（根因取证 + 修复验证）
- scripts/check_tools_sync.py / check_instruction_budget.py 输出（本轮实测）
- temp/fist_r380_out/chain.log + task_id.txt + 6_verify.txt（FIST 闭环回执）
- reports/2026-11-17-r379-wakeup-patrol.md（r379 后续建议 + 报告格式对齐）
- memory 注入（FIST 链后台收口法 / WIP 禁区纪律 / r379 静止第 60 轮）

## FIST 闭环核实格（终审回填）

- TID = **T0r136**（task_id.txt 与 publish 回执一致）
- STEP1 publish rc=0 / STEP2 acl rc=0 / STEP3 claim rc=0 / STEP4 execute rc=0 /
  STEP5 submit rc=0 / STEP6 verify rc=0 / CHAIN_DONE
- verify 回执：status=**已完成**、completed_by=**wd-r380**、
  deliverable=reports/2026-11-17-r380-wakeup-patrol.md、namespace=watchdog
