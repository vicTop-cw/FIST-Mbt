# 工具链死锁恢复 + 合并后同步死角清扫报告

- 日期：2026-10-18
- 范围：FIST-Mbt 主仓 master（合并 marvis-verify-20261017 之后）
- 触发：用户「已经重启了，我让另外一个 agent 已经合并了，正在修复合并后的 bug；你处理工具链死锁等问题」

## 结果摘要

- **工具链死锁解除**：前段持续 ~13h 的 pwsh `0xC0000142`（`STATUS_DLL_INIT_FAILED`）+ grep/glob ripgrep provider + `run_check` node spawn 三重哑火，经用户重启 DSH 会话后恢复。本轮全流程实测可用。
- **cl7 插件态漂移修复**：合并把工具面推进到 170，9 个插件投影 + J5 `plugins/claude/.mcp.json` 未跟随 → 重生成 `gen_plugins.py`（170 工具 / v0.3.8 / 323 条账）→ cl7 PASS。
- **J14 文档面真漂移修复**：`cmd/cli/help_topics.mbt` 3 处 `166` 字面量 + 分组表缺 `[Display 4]`；`templates/tool_use_rubric.md` 计数 166 → 全部同步到 170，分组 17→18。
- **编译验证**：`moon check --target js src/server` = 0 errors，`cmd/cli` = 0 errors，`moon fmt --check` rc=0。
- **同步门族全绿**：`check_doc_surface` / `check_tools_sync` / `check_mbti_sync` / `check_desc_enum_sync` / `check_plugin_sync` 全部 PASS。
- **孤儿清理**（用户确认后）：worktree `FIST-Mbt-light-isolation`（分支已 100% 并入）先抢救计划文档再 remove + 删分支；过期 stash `stash@{0}`（Round 108 快照，内容已入 master）drop。

## 资源消耗

- 时间：会话重启后约 1 小时内完成核心恢复（pwsh 探测 → 侦察 → cl7 修复 → J14 修复 → 编译验证 → 孤儿清理 → 沉淀）。
- 工具调用：`pwsh`（约 12 次）、`read`（3）、`edit`（5）、`write`（1）、`glob`（1）、`grep`（1）、`mcp__fist-mbt__lock_status`（1）。
- Git 提交：`9d8552c`（cl7 重投影）、`1091ebc`（J14 计数同步）、`229e97d`（抢救文档）。

## 任务分配记录

| 步骤 | 执行者 | 结果 |
|---|---|---|
| pwsh / 工具链探测 | 本人 | ✅ `moon 0.1.20260920`、`node v25.2.1`（≥24）、`.mbti` 无漂移 |
| 合并后 git 侦察 | 本人 | ✅ 分支已 100% 并入，起手 0 脏文件 |
| cl7 插件态重投影 | 本人 | ✅ PASS（`9d8552c`） |
| J14 计数同步 | 本人 | ✅ PASS（`1091ebc`） |
| 编译 + 同步门族验证 | 本人 | ✅ 0 errors，五门全绿 |
| 孤儿 worktree / stash 清理 | 本人（用户确认） | ✅ `229e97d` + worktree/branch/stash 清除 |
| 合并 bug 修复 | 并发 agent（用户已分配） | ⏳ 进行中 |

## 遗留风险

- `check_test_sync` **未判定**：需真实 `moon test` 通过总数作参数（从日志/直接传参），当前合并修复 agent 正在跑测试，未抢跑。
- `scripts/blackbox/e2e_irm_line.py` 出现 **96+/26−** 改动，起手脏文件=0、操作期间出现 → 判为并发 agent 在主工作树的 WIP，**未触碰**，其收口前该文件保持 dirty。
- FIST 文件锁 3 条历史接管违例（`polish-lead` / `atomcode-3` / `agent-20260712…`）为合并期并发接管留痕，全部已 released，无 active 死锁，仅作审计留痕。
- 抢救的 `docs/plan-light-worktree-isolation.md` 为合并前计划文档（264 行），作为历史记录保留，未逐行复核其内容是否仍适用。

## 后续建议

1. 合并修复 agent 收口后跑一次 `moon test --target js` 全量回归（基线 1058/1058），并把实测通过总数喂给 `check_test_sync` 完成 R1/R2/R3 双向判。
2. 工具数推进时一次跑全 `check_*_sync` 门族（tools / test / mbti / doc_surface / desc_enum / plugin）——本次 `check_tools_sync` 已绿而 cl7/J14 滞后，属三处独立真源计数未联动。
3. 后续并发修复期间，`cmd/cli/*.mbt` 与 `src/server/*.mbt` 由该 agent 持有，勿改；本次仅动 `cmd/cli/help_topics.mbt`（计数同步，已提交）。

## 超额内容

- 主动抢救并入库 16.5KB 计划文档（超出单纯"清理"范围，避免不可逆信息丢失）。
- 顺带核验 `.mbti` 无漂移、FIST 锁无 active 死锁、无残留 git/moon 锁文件——均非用户显式点名但属"工具链死锁"排查面。

## 来源

- 本地实测（`pwsh` / `git` / `moon` / `python scripts/check_*.py`）。
- 相关文档：`docs/2026-10-15-fist-mbt-caf-acceptance-status.md`、`memory/2026-10-18.md`（本报告同日日志）。
