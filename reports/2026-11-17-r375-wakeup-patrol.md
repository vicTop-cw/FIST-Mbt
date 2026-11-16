# 轮 375 唤醒巡检报告（FIST-Mbt-ExploreWatchdog）

- 日期：2026-11-17
- 轮次：375（第 56 轮 WIP 静止态）
- FIST 闭环：T0r131 / agent `wd-r375` / ns `watchdog`

## 结果摘要

WIP 非冻结增长后**静止第 56 轮**：`git status --short` 仍为同一组 8 文件
（6 个已跟踪 M + 2 个 untracked），numstat 与 r326~r374 逐字同
（bugs.md 216/0 零再增长、improvement-plan 7/1、target.md 1/1、README.md 2/1、
run_guards.py 9/0、engine_circuit_test.mbt 5/0、2 untracked 545+211 行），
`src/engine/engine_circuit_test.mbt` 与 `scripts/run_guards.py` 仍 M ⇒
**Round C 三件维持过期不执行**（BUG-527 治本 / BUG-530 修复 / run_guards 注册
check_usage_tool_count 均未解禁）。

本轮走**巡检分支**，换面巡检 **`check_model_auth_no_key`**（BUG-127 凭据形状
红线守卫：config_json / `*.mcp.json` / `plugins/**/.mcp.json` / mcp_config_scaffold
常量 / HTML 生成物 / `src/router` / docs 里**禁止出现真凭据值形状**——api_key /
Bearer / `sk-` 等；对齐 BUG-127「`moon publish` 打包面会把未 ignore 的凭据形状
公开点名」的凭据形状红面）：

- `--selftest` **rc=0**（`SELFTEST OK 真凭据值形状判据可红可绿`：违例必红 /
  占位符与键名不误红 / base64 长令牌限键值上下文 / 输入面退化自拒）
  ⇒ **判据本身健康，不是坏尺**（可红可绿四档俱全）
- 实跑 **rc=0**（`PASS 文件面无真凭据值形状（扫描 146 份：fist-config /
  *.mcp.json / plugins/**/.mcp.json / mcp_config_scaffold 常量 / src/router /
  docs / README*）`）

**判定：扫描面干净，无新发现。** 146 份文件面全在提交面（不在 WIP 组内），
无真凭据值形状，rc=0 干净映射非 WIP 投影噪声。

### 撞面核对

grep git log 反解近 40 轮，`check_model_auth_no_key` **零命中**；本面最近一次
实跑为 **r325**（8343bcd76，50 轮前，超出近 40 轮反解窗口），r325~r374 的
49 轮内未被复巡 ⇒ 本面为本轮重新覆盖、非撞面。本面为 r317 列名候选、r325 首跑
（BUG-127 凭据形状红线），r374 后续建议已点名本面为下轮候选。

例行的零漂移双核对：
- `check_tools_sync` rc=0：server.mbt 注册 183 个，AGENTS/README/deliverable/
  scoring_rubric 对齐，R8 分组 19 组 ΣN=183（已与实测对表）
- `check_instruction_budget` rc=0：AGENTS.md 50440/65536 字节全部章节可见

## 资源消耗

- 唤醒巡检一轮；bash 调用约 8 次 + FIST 六步链 1 次（后台串跑，node 已温、
  链总耗时 <60s）
- 零文件改动（换面巡检只读 + 记录，禁区 WIP 零碰），无新依赖安装
- patch_esm_main 探针先行（10 bundle 全 up to date / total patched 0，防 MemoryError）

## 任务分配记录

| 步骤 | 工具 | 结果 |
|---|---|---|
| 唤醒巡检 | git status/log/numstat | WIP 静止第 56 轮，Round C 不执行 |
| 换面选面 | ls check_*.py × 近 40 轮巡检面反解 | 选 check_model_auth_no_key（BUG-127 凭据红线/零撞面/r374 点名候选） |
| 换面巡检 | check_model_auth_no_key selftest | rc=0（可红可绿四档，判据健康非坏尺） |
| 换面巡检 | check_model_auth_no_key 实跑 | **rc=0**（扫描 146 份文件面无真凭据值形状，无新发现） |
| 零漂移核对 | check_tools_sync / check_instruction_budget | 均 rc=0（183 / 50440/65536） |
| FIST 闭环 | T0r131 六步 | 见文末核实格 |

## 遗留风险

1. **Round C 三件持续过期**：src/** 仍被 WIP 占用，BUG-527/BUG-530/USAGE 注册
   均不能落地——取决于另一 agent 收口 WIP，非本巡检可解除。
2. **第 56 轮静止**：WIP 自 r318 起无增长无收口（R192 车道自 r318 停摆），已跨
   半个自然月余；建议 owner 关注 WIP 归属方是否失联。本轮定性延续 r374：该 WIP
   形似一次接近完成的判据接线工作（判据本体 545 行已写好、注册与配套文档已起笔），
   若归属方长期失联，owner 可裁决接管收口或回滚该 WIP——属不可逆操作，需 owner
   明确授权，巡检不代行。
3. **r372 真发现待 WIP 收口方修**（WIP 模板 `templates/pipeline_mode_loop.md:86`
   的 run_check 示例缺必填 cmd/task_id）：严重度低（untracked 文件，CI 无此面），
   收口方应一并修全（照同文件 60 行），否则收口后 `check_doc_surface` 实跑仍会
   rc=1 红。

## 后续建议

- WIP 收口后按 Round C 队列执行（BUG-527 治本 → BUG-530 → run_guards 注册
  check_usage_tool_count 同批），并**顺带修全 loop.md:86 的 run_check 示例**
  （r372 真发现），收口后 `check_doc_surface` 实跑方转绿。
- 巡检面下轮继续轮换未巡检过的守卫面（候选：check_release_asset_names /
  check_publish_payload / check_entry_paths / check_esm_bundle_runnable /
  check_plugin_sync / check_doc_dup / check_precedents_doc / check_mbti_eol 等
  未在近期出现过的面）。
- 基线外外来条目 BUG-613~635 继续待 owner 裁决搬移 vq 仓 / WHITELIST 登记
  （`check_foreign_ledger_entries` 脏树必红 = WIP 投影，非回归）。

## 超额内容

无。

## 来源

- git status --short / git log --oneline / git diff --numstat（唤醒巡检，只读实测）
- scripts/check_model_auth_no_key.py --selftest / 实跑输出（本轮实测）
- scripts/check_tools_sync.py / check_instruction_budget.py 输出（本轮实测）
- scripts/patch_esm_main.py 探针输出（本轮实测，见 FIST 核实格）
- grep git log 反解近 40 轮巡检面撞面核对 + ls scripts/check_*.py 全量判据清单
- memory 注入（FIST 链后台收口法 / patch_esm_main 探针 / r374 WIP 静止第 55 轮）

## FIST 闭环核实格（终审回填）

- TID = **T0r131**（task_id.txt 与 verify 回执一致）
- STEP1 publish rc=0 / STEP2 acl rc=0 / STEP3 claim rc=0 / STEP4 execute rc=0 /
  STEP5 submit rc=0 / STEP6 verify rc=0 / CHAIN_DONE
- verify 回执：status=**已完成**、completed_by=**wd-r375**、assignee=wd-r375、
  deliverable=reports/2026-11-17-r375-wakeup-patrol.md、namespace=watchdog、
  created_at=2026-11-16T20:05:08Z / updated_at=2026-11-16T20:05:27Z
- patch_esm_main 探针先行：10 bundle 全 up to date / total patched 0（rc=0，
  防 MemoryError）
