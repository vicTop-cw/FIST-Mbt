# 轮 374 唤醒巡检报告（FIST-Mbt-ExploreWatchdog）

- 日期：2026-11-17
- 轮次：374（第 55 轮 WIP 静止态）
- FIST 闭环：T0r130 / agent `wd-r374` / ns `watchdog`

## 结果摘要

WIP 非冻结增长后**静止第 55 轮**：`git status --short` 仍为同一组 8 文件
（6 个已跟踪 M + 2 个 untracked），numstat 与 r326~r373 逐字同
（bugs.md 216/0 零再增长、improvement-plan 7/1、target.md 1/1、README.md 2/1、
run_guards.py 9/0、engine_circuit_test.mbt 5/0、2 untracked 545+211 行），
`src/engine/engine_circuit_test.mbt` 与 `scripts/run_guards.py` 仍 M ⇒
**Round C 三件维持过期不执行**（BUG-527 治本 / BUG-530 修复 / run_guards 注册
check_usage_tool_count 均未解禁）。

**本轮新观察（WIP 定性，只读核实）**：`git diff scripts/run_guards.py`（只读）
显示 WIP 唯一改动 = 在 SPECIAL_CASES 里注册 `check_mcpcf_db_isolation.py`，
注释点名为 **R192（BUG-583 方向④）**——mcpcf 嵌入式引擎的库
（%LOCALAPPDATA%\mcpconftest\data）与主库（.fist-mbt/data/<ns>.db）两条路径
家族不相交的可核断言，rc 0/1/2/4 四档、`--selftest` 27 格全合成夹具。⇒ WIP 组
8 文件 = R192 车道的判据接线工作（新判据 545 行 + run_guards 注册 + README/
bugs.md/target.md/improvement-plan 配套 + engine_circuit_test.mbt 测试 +
loop 模板 211 行），**与 r372 报告的 loop.md:86 缺参发现同属该 WIP**（收口方
应一并补全）。

本轮走**巡检分支**，换面巡检 **`check_workflow_step_parity`**（R87 · BUG-490
家族：同源 workflow 之间的「必要步骤」覆盖面守卫——`ci.yml` 与 `release.yml`
都是同源 workflow，依赖惰性解包 ⇒ 任何「跑 moon 的 job」必须**前序**先有
`migrate_mooncakes_modjson` step；历史上这一步在 release.yml 上被漏过 3 次，
第 3 次还被 `continue-on-error` 长期静默）：

- `--selftest` **rc=0**（`SELFTEST PASS` 7 格：干净不误红 / 缺 migrate 必红 /
  顺序错必红 / 空 job 自拒 / 空 moon 自拒 / 未豁免的静默 job 必报 / 同步合规）
  ⇒ **判据本身健康，不是坏尺**（S1 顺序断言 / S2 覆盖面差值 / S3 自拒 2 档俱全）
- 实跑 **rc=0**（`扫描面：.github/workflows/ci.yml + .github/workflows/release.yml；
  跑 moon 的 job 6 个 / 有 migrate 的 job 6 个；PASS：全部「跑 moon」的 job 都**先**
  migrate；不跑 moon 的 job 已逐条点名理由`）

**判定：扫描面干净，无新发现。** 两份 workflow 均为提交面文件（不在 WIP 组内），
6 个跑 moon 的 job 前序全有 migrate，rc=0 干净映射非 WIP 投影噪声。

### 撞面核对

grep git log 反解近 40 轮，`check_workflow_step_parity` **零命中**，不撞近期
巡检面（近 40 轮已巡检面见 git log：doc_paths r373 / doc_surface r372 /
arg_face_strict r371 / mcp_stdio_purity r370 / ps_encoding r369 等 20 面均
不含它）。本面为 R87 立（BUG-490），40 轮内未被巡检过。

例行的零漂移双核对：
- `check_tools_sync` rc=0：server.mbt 注册 183 个，AGENTS/README/deliverable/
  scoring_rubric 对齐，R8 分组 19 组 ΣN=183（已与实测对表）
- `check_instruction_budget` rc=0：AGENTS.md 50440/65536 字节全部章节可见

## 资源消耗

- 唤醒巡检一轮；bash 调用约 10 次 + FIST 六步链 1 次（后台串跑，node 已温、
  链总耗时 <60s）
- 零文件改动（换面巡检只读 + 记录，禁区 WIP 零碰），无新依赖安装
- patch_esm_main 探针先行（10 bundle 全 up to date / total patched 0，防 MemoryError）

## 任务分配记录

| 步骤 | 工具 | 结果 |
|---|---|---|
| 唤醒巡检 | git status/log/numstat | WIP 静止第 55 轮，Round C 不执行 |
| WIP 定性（只读） | git diff run_guards.py + ls check_*.py | R192 车道注册 check_mcpcf_db_isolation |
| 换面选面 | 11 把零撞面候选 × HEAD 电池注册核对 | 选 check_workflow_step_parity（CI 门禁/高价值/零撞面） |
| 换面巡检 | check_workflow_step_parity selftest | rc=0（7 格含变异对照与自拒档，判据健康） |
| 换面巡检 | check_workflow_step_parity 实跑 | **rc=0**（6/6 跑 moon job 全先 migrate，无新发现） |
| 零漂移核对 | check_tools_sync / check_instruction_budget | 均 rc=0（183 / 50440/65536） |
| FIST 闭环 | T0r130 六步 | 见文末核实格 |

## 遗留风险

1. **Round C 三件持续过期**：src/** 仍被 WIP 占用，BUG-527/BUG-530/USAGE 注册
   均不能落地——取决于另一 agent 收口 WIP，非本巡检可解除。
2. **第 55 轮静止**：WIP 自 r318 起无增长无收口（R192 车道自 r318 停摆），已跨
   半个自然月余；建议 owner 关注 WIP 归属方是否失联。本轮定性后判断：该 WIP 形似
   一次接近完成的判据接线工作（判据本体 545 行已写好、注册与配套文档已起笔），
   若归属方长期失联，owner 可裁决接管收口或回滚该 WIP——属不可逆操作，需 owner
   明确授权，巡检不代行。
3. **r372 真发现待 WIP 收口方修**（WIP 模板 `templates/pipeline_mode_loop.md:86`
   的 run_check 示例缺必填 cmd/task_id）：严重度低（untracked 文件，CI 无此面），
   收口方应一并修全（照同文件 60 行），否则收口后 `check_doc_surface` 实跑仍会
   rc=1 红。
4. **WIP 内 2 个 untracked 新文件**（`scripts/check_mcpcf_db_isolation.py` 545 行 /
   `templates/pipeline_mode_loop.md` 211 行）自 r326 起零增长——收口方需同批登记
   执行面（判例-5 族）：本轮只读核实 run_guards.py 已含 check_mcpcf_db_isolation
   的 case() 注册（9/0 行改动全部用于此），判例-5 风险半格已解；loop 模板属
   templates/ 面，按既有惯例不进电池。

## 后续建议

- WIP 收口后按 Round C 队列执行（BUG-527 治本 → BUG-530 → run_guards 注册
  check_usage_tool_count 同批），并**顺带修全 loop.md:86 的 run_check 示例**
  （r372 真发现），收口后 `check_doc_surface` 实跑方转绿。
- 巡检面下轮继续轮换未巡检过的守卫面（候选：check_release_asset_names /
  check_publish_payload / check_entry_paths / check_esm_bundle_runnable /
  check_plugin_sync / check_doc_dup / check_model_auth_no_key /
  check_precedents_doc / check_mbti_eol 等未在近期出现过的面）。
- 基线外外来条目 BUG-613~635 继续待 owner 裁决搬移 vq 仓 / WHITELIST 登记
  （`check_foreign_ledger_entries` 脏树必红 = WIP 投影，非回归）。

## 超额内容

无。

## 来源

- git status --short / git log --oneline / git diff --numstat / git diff
  scripts/run_guards.py（唤醒巡检与 WIP 定性，只读实测）
- scripts/check_workflow_step_parity.py --selftest / 实跑输出（本轮实测）
- scripts/check_tools_sync.py / check_instruction_budget.py 输出（本轮实测）
- scripts/patch_esm_main.py 探针输出（本轮实测，见 FIST 核实格）
- grep git log 反解近 40 轮巡检面撞面核对 + ls scripts/check_*.py 全量判据清单
  + git show HEAD:scripts/run_guards.py 电池注册核对
- memory 注入（FIST 链后台收口法 / patch_esm_main 探针 / r373 WIP 静止第 54 轮）

## FIST 闭环核实格（终审回填）

- TID = **T0r130**（task_id.txt 与 verify 回执一致）
- STEP1 publish rc=0 / STEP2 acl rc=0 / STEP3 claim rc=0 / STEP4 execute rc=0 /
  STEP5 submit rc=0 / STEP6 verify rc=0 / CHAIN_DONE
- verify 回执：status=**已完成**、completed_by=**wd-r374**、assignee=wd-r374、
  deliverable=reports/2026-11-17-r374-wakeup-patrol.md、namespace=watchdog、
  created_at=2026-11-16T19:34:26Z / updated_at=2026-11-16T19:35:08Z
- patch_esm_main 探针先行：10 bundle 全 up to date / total patched 0（rc=0，
  防 MemoryError）
