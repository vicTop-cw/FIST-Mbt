# 轮 221 唤醒巡检报告

**时间**：2026-11-12 13:39 开轮 / 13:52 收笔
**轮次**：r221（ExploreWatchdog 自动唤醒）
**主线**：WIP 全面收口坐实（`src/**` 自 r219 起全干净）+ Round C 判空维持 + 表面稳定复测 + 两未决项因 WIP 收口**解锁**列下一独立轮候选；无新 bug、未立新账。

## 结果摘要

- **WIP 全收口坐实（本轮主线事实）**：r198–r218 持续 ~20.4h 的「15 文件冻结死挂 WIP」已于 r218 中途被并发 agent 以 `3f7e9724b`（BUG-588→FIXED + BUG-591⑤ + 计数面 2064→2067，26 文件）收口；`src/server/mcpcf_embed.mbt` 自 r219 起回正至 HEAD ⇒ **`src/**` 与 `scripts/run_guards.py` 全干净**。本轮 `git status --short` 复核：仅 `M memory/target.md`（禁区，陈旧协调面）+ 游离 `fist-mbt.db `（尾空格 0 字节）。**冻结 saga 彻底终结**（转「已收口」，非「已放弃」）。
- **Round C 队列判空维持**：三项仍全过期 ⇒ 无待办、不执行、不重推导（① BUG-527 摘 cc-link-flags → owner 已否决 `e0ef45c5e`；② BUG-530 → 已 FIXED `3699f012a`；③ check_usage_tool_count → 已注册 `run_guards.py:175`）。
- **表面稳定（无未探面，不重跑既有判据）**：全量 JS 2067/2067 green（r220 独立复验 `3f7e9724b` 背书）/ mcp_smoke 182 工具 PASS（r217）/ check_host_installable PASS（r219）/ OFM 端点 down 容忍态（r218）——r194–r220 已全覆盖，本轮按「勿空转」不重跑同源判据。
- **两未决项因 WIP 收口解锁（本轮前瞻增量，列下一独立轮 / owner 确认轮候选，本轮不动）**：
  ① **r208 测试夹具沙箱化**（`src/store/multi_store_test.mbt:23/53/175-177` 的 alpha/beta/wal-a/b/c + `src/store/store_sqlite_open_preflight_wbtest.mbt:91` 的 pf-ok，现用裸相对路径建库 ⇒ `cleanup --check` 恒 DIRTY）——r208 明确「留 WIP 收敛后独立轮走完整 FIST+派单+验证」，**该前提（WIP 收口）本轮已满足**，故升为下一独立轮首选打磨项（低优先级、已知已缓解、属「已实现打磨」末位）。
  ② **游离 `fist-mbt.db ` owner 确认清理**——r207/r208 定性「WIP 收口 / owner 确认轮用 `cleanup`（非 --check）清」，WIP 收口前提本轮已满足；但 0 字节文件删除属不可逆 + 本轮为无窗看门狗（无 owner 在场确认）⇒ 不代删，列 owner 确认轮。
- **无新 bug，未立新账。**

## WIP 状态转移（r220 → r221）

| 时点 | M 文件数 | 未跟踪 | 定性 |
|---|---|---|---|
| r220 末（13:15） | 1 | `fist-mbt.db `（0 字节） | 仅 `memory/target.md`；`src/**` 全干净 |
| r221 开轮（13:39） | 1 | `fist-mbt.db `（0 字节） | 逐字维持 r220；无并发新活动 |

**残留 1 个 M（禁区，不碰）**：`memory/target.md`——陈旧协调面（`[Round 24 巡检]…HEAD=5cbe4ce52`，mtime 2026-11-10，与当前 `0d1701081` 漂移两天），属并发 agent 共享面，本仓不代刷新；是否刷新属并发 agent / owner。
**游离 `fist-mbt.db `**（尾空格、0 字节、mtime 11-11 14:37）维持 r197 定性（外部来源、非代码缺陷、非账）+ r204 守卫已修（`cleanup_artifacts.py` `_db_name_is_stray` 先 strip 再 endswith，`--selftest` R1/R1b/R2 PASS）；本轮非 owner 确认轮，不删。

## 非阻塞巡检（本轮真动作：FIST 闭环 verify 身份门实证 + 表面稳态确认）

- **FIST 闭环 verify 身份门实证（本轮唯一真发现，供后续少踩坑）**：首跑六步链 S1–S5 全绿（publish→acl(wd-r221)→claim→execute→submit），**S6 verify 红**——`acl: ACL 无记录（fail-closed）: abf1a89ace70981e/iter-1112r221w`。
  **根因**：S2 只给 agent 身份 `wd-r221` 授了 ACL，而 verify 的判定身份是 `--verifier commander`（**另一身份**，来源=explicit-agent）⇒ `commander` 在该 ns 无 can_write 行 ⇒ fail-closed 拒。
  **修法**：补 `agent_acl_grant --agent-id commander …`（granted_rows `abf1a89ace70981e`）后重跑 verify ⇒ T0 转「已完成」（completed_by=commander）。
  **判例**：verify 用 `--verifier` 指定**独立**验收身份时，该身份**必须与 claim/execute 的 agent 身份分别各授一次 ACL**（ns ACL 是逐 ns 库的独立门，两道身份不互通）；沿用 r205–r217「verifier==agent 同身份」则一次授权即可。
- **表面稳态确认**：无未探面（r194–r220 已全覆盖），按「勿空转」不重跑 mcp_smoke / check_host_installable / check_battery_count_doc / moon test 等同源判据；仅 `git status` / `git diff --shortstat` / `ls` 只读观测。

## Round C 队列

- `run_guards.py` 与 `src/**` 全解锁（「占用」前提自 r218 起彻底解除）。
- **三项全部过期，无待办，不执行**（维持 r218/r219/r220 结论，待 owner 正式判空关闭）：
  ① BUG-527 治本（摘 cc-link-flags）→ owner 已否决（`e0ef45c5e`，CI A/B 实证有害，回滚）；
  ② BUG-530（model_route 播种 + executor_run 路由）→ 已 FIXED（`3699f012a`）；
  ③ run_guards.py 注册 check_usage_tool_count + 同批 USAGE.md → 已注册（`run_guards.py:175`）。

## 资源消耗

- 命令：~12（git status/log/diff ×4 + ls/cat -A 溯源 ×2 + grep FIST_DB_PATH/gitignore/尾空格 ×2 + fist.py list-tools ×1 + FIST 闭环 7 次（S1–S6 + S2b 补授 commander）+ 报告/日志/提交写入 ×3）
- 无子代理（读态 + FIST 闭环 + 记账属指挥官本职；本轮无新探面、无未修 bug，无需派单；且 moon 验证需 shell，`task`/`team` 子代理无终端，打磨项留独立轮自行验证）

## 任务分配记录

无派发。FIST 闭环记账（ns `iter-1112r221w`）：publish → acl(wd-r221) → claim → execute → submit → acl(commander) → verify，**全链 rc=0 至 T0 已完成**（completed_by=commander，granted_rows `abf1a89ace70981e`/`2bbb89b069338203`）。

## 遗留风险

- **`memory/target.md` 陈旧协调面**（Round 24/HEAD=5cbe4ce52，与当前 `0d1701081` 漂移，mtime 2026-11-10 两天未动）：属并发 agent 共享面（禁区），本仓不代刷新。
- **BUG-591 ②③④ 仍 OPEN**（并发 agent 提交自述，②③ 属 owner 裁决、④ 需真远端）——本仓不代裁决，待 owner。
- **Round C 队列判空**（三项均否决/已修/已注册）待 owner 正式关闭。
- 游离 `fist-mbt.db ` 维持挂账（r197 定性 + r204 守卫已修）；owner 确认轮 `cleanup` 可清。
- **OFM 端点持续 down 观察项**（非账，r194 容忍定性）：随外部服务浮动，探活告警语义属 owner 接线决定。

## 后续建议

- **下一独立轮首选：r208 测试夹具沙箱化**——WIP 收口前提已满足，把 `multi_store_test.mbt` + `store_sqlite_open_preflight_wbtest.mbt` 两测试文件夹具改 `base_dir()` 沙箱路径，从根止住 `cleanup --check` 恒 DIRTY；走完整 FIST+派单+`moon test` 验证（低优先级打磨，建议单独立轮不混入巡检）。
- **owner 确认轮**：清游离 `fist-mbt.db `（`cleanup` 非 --check）+ 正式判空关闭 Round C 队列三项 + 刷新 `memory/target.md` 陈旧协调面。
- 报告序列连续（r218→r219→r220→r221）：本轮无中断，双格（报告提交 + 日志追加）收尾正常。

## 超额内容

无。

## 来源

- `git status --short` / `git log --oneline -3` / `git diff memory/target.md`（WIP 复核：仅 `memory/target.md` M + 游离 db；HEAD=`0d1701081`）
- `ls -la | cat -A`（`fist-mbt.db` 18MB KEEP / `fist-mbt.db ` 0 字节尾空格 / `-shm`/`-wal` 属主库）+ `git check-ignore -v`（`*.db` 仅匹配无空格主库）+ `grep FIST_DB_PATH`（无脚本产尾空格路径）
- `python scripts/fist.py list-tools`（确认 publish/agent_acl_grant/claim/execute/submit/verify 工具名）
- `python scripts/fist.py call` ×7（FIST 闭环，S6 verify 首跑红 → S2b 补授 commander → verify 绿，全链至已完成）
- r204/r207/r208/r218/r219/r220 报告 + 当日日志（游离 db 守卫 + WIP 收口 + 表面稳态对照）
