---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: round4-selfloop-report
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: round4-selfloop-report
---

# 四模式流水线自我迭代 · Round 4 汇报（寻虫 → 修复 → 验证 → 打磨）

日期：2026-09-27 ｜ 指挥官：FIST 指挥官（人类在场所属会话）｜ 版本：v0.3.0（未发布）
范围：用户点名「新增的插件、路由功能也需要测试」，四段全程开 **Omega 强验证 + laya 决策 + issue 上报 + call_log 自证**。

## 1. 结果摘要

| 段 | 命名空间 / 根 | 产出 | 闭合状态 |
|---|---|---|---|
| 寻虫 | `pmode-r4-bugfind` | 入账 **BUG-61~72（12 条：4 high / 5 medium / 3 low）** | 叶子全部走完 Omega 链 |
| 修复 | `pmode-r4-fix` / `T0r379` | 12 条逐修 + 新发现 **BUG-73** 当场收口；**13 条 FIXED 小记**入账本 | 根下 21 叶 → 已完成 21 / 未闭合 0 |
| 验证 | `pmode-r4-verify` / `T0r382` | 六泳道 **13 条服务端 run_check 判据全 passed**；又抓到 **BUG-74 / BUG-75** | 29/29 已完成（含枝干与根上卷） |
| 打磨 | 本段 | 账本收口、四宿主重投影、两条新判据落盘、CHANGELOG/日志/本汇报 | 六守卫 rc=0 + 四份 `--selftest` PASS |

- 全量测试：`moon test --target js` **453/453**（`temp/r4/full4.log`）。
- 调用面（不信模块自述）：`temp/router_smoke.py` 27/27、`temp/r4/verify_r4_callsite.py` 14/14、`scripts/mcp_smoke.py` PASS。
- 硬门双向：`output_validate` 正门 `verdict=pass`，**必然违例对照门 `verdict=fail`**（抽掉一条真结果 + 引用不存在的 check_key/path）。
- 投影态：账本 **BUG-1~75（29 待修 / 46 已挂 FIXED 小记）**，`gen_plugins` 重投影后 cl7 逐字节一致（4 宿主 / 56 生成文件 / 120 工具 / v0.3.0）。

## 2. 资源消耗

- `cost_stats`（全库累计，工具无参）：`total_records=395`，`total_cost=0`，
  `total_tokens_in/out=130997`，`total_rate_limited=0`；本轮 executor 计数
  `r4-bugfind=15 / r4-fix=21 / r4-verify=21`，`human_steward=3`。
- `cost_budget_check(limit=500000, current=0)` → `exceeded=false / remaining=500000 / action=continue`。
- `call_log` 最近 1200 行 `runtime_ms` 合计 **94102 ms**（约 94 秒的服务端工具执行时间，不含 moon 编译）。
- 本地命令开销：`moon test --target js` 1 次全量（453 用例）+ `moon check` 1 次；六守卫各 1 轮 +
  四份 `--selftest` 各 1 轮；`mcp_smoke` / `router_smoke` / `verify_r4_callsite` 各 1 轮；
  `gen_plugins` 因账本两次变更共重投影 2 次。
- 未消耗项：宿主执行器真跑（`executor_run dry_run=false`）**0 次** —— 未获授权，见 §4。

## 3. 任务分配记录

| 泳道 | 承接任务 | 实际做的事 | 证据位置 |
|---|---|---|---|
| 寻虫 | `T0r375~T0r377` 等修复单 | 规则扫描 + 调用面探针 + 投影面比对，产出 12 条入账 | `temp/r4/findings_pmode-r4.json`、`filed_ids.json` |
| 修复 A~F | `T0r379.*`（21 叶） | 六组修复：路由/执行器产品码、BUG-73、假绿锁、插件投影、守卫族、扫描器降噪 | 各条 `### FIXED(...)` 小记（`memory/bugs.md:1052` 起 13 段） |
| 验证 V1~V6 | `T0r382.*`（21 叶 + 7 枝 + 根） | 13 条判据交服务端 `run_check` 真跑；MCP 侧账本/队列/扫描/规范/自证只读复核 | `temp/r4/gates_pmode-r4-verify.json`、`v4_gates.log` |
| 终审 | 指挥官亲做 | 锁承重复算（退回旧码必红 + 合成违例必红）、账本小记数字回改、树形上卷收口 | `prove_locks_red*.py`、`fix_b69_count.py`、`close_branches.py` |

过程纪律：每段先 `laya_decide` 选档与拆分数（无 sidecar ⇒ fallback），
`task_plan_deep(omega_strong_verify=true, gradient=true, boundary_probe=true, reinject_context=true)`，
每叶 claim → 建语料 → 审语料 → execute → submit → 成果复验 → verify，逐单不可跳步。

## 4. 遗留风险（不粉饰）

1. **BUG-74 / BUG-75 未修**（已入账、修复单 `T0r385 / T0r386` 挂 ns `bugs`）：
   前者是"调用方读不到返回契约 ⇒ 误判拆解失败"，后者是"判据红了举不出红在哪"。
   两条都会让无人值守流水线**在错误信息不足时做出错误决策**，优先级 medium，转 Round 5 修复段。
2. **BUG-61 的 `executed=true` 分支无端到端证据**：只证到 dry_run、argv 形状、记账路径与越权拒绝；
   真跑要起宿主进程，用户未授权（BUG-4 边界默认收紧）。账本按"代码+白盒+记账路径调用面已证、真跑侧待授权"入账。
3. **native 轨本轮未复跑**：317 是上一轮 Windows+WSL 旧数，本轮不据旧数宣称双端同版全绿；
   权威稳定门槛仍是 JS 后端（Node ≥ 24）。
4. **GitHub 同步 `enabled=false`**（凭据只走环境变量注入，本仓不读 `.env`）：
   `github_queue_status` 的 `pending=0` 含义是"未开同步"，**不许读成"无 bug 待同步"**。
5. **call_log 的 ns 列大面积为空**（本轮实测 1200 行里只有 11/3/7 行带本轮 ns）：
   按 ns 统计轮次调用数系统性偏小，本轮自证因此改用"工具名是否出现在表里"而不是"按 ns 计数"。
6. 本轮自己犯的错（已在 `memory/2026-09-27.md` §7.4 记账）：读返回体键名想当然导致
  "自证读空仍打 PASS"的险象 —— 已补 `evidence_self_check`（rows>0 且 run_check 在表里）让这类空读必须能红。

## 5. 后续建议

- **Round 5 修复段**先吃 BUG-74/75，且**两条都要配成对锁**：
  缺"返回"二字的合成工具描述必红、`issue_scan` 这类已写明返回形状者必不红；
  `run_check` 失败判据必须带出末 N 行 stderr、通过判据不得因截断丢 `ok`。
- **把本轮两条临时判据升成正式守卫**（放进 `scripts/` 并登记 `scripts/README.md`）：
  `v4_idem_plugins.py`（生成幂等）与 `v4_ledger_three_way.py`（账本↔投影三向）——
  现在 `temp/` 里的东西不受 `check_scripts_index` 保护，等于"没人认领的改进"。
- Round 5 寻虫面按边界叶点名走：`src/store` / `src/engine` / 运维类 ops / `templates/`，
  以及积压的四项：状态文件原子写、consume 后 `current_tier` 回报、`.mcp.json` 干净克隆可跑、
  deepseek 宿主不对称与 `.gitattributes`。
- 真跑授权若拿到，验收口径应为"宿主进程退出码 + 路由账变化 + argv 回显"三件齐全，不接受只回 `executed=true`。

## 6. 超额内容（超出四模式基本动作、但确实做了的）

- 新增两条**可复跑**的判据脚本（生成幂等、账本三向），不是本轮一次性检查。
- `verify_gates.py` 把"自证"本身做成可红判据（`evidence_self_check`），防 call_log 读空仍报绿。
- 修复段坚持"锁先落码、后改产品"，BUG-73 因此留下了在未修复码上的红记录（`temp/r4/t6.log`）而不是事后叙述。
- 收口 `close_branches.py`：发现叶子全绿但枝干停在待验收（强验证开着），补枝干/根上卷，
  否则 `status_summary` 会长期挂着 7 个"待验收"假活跃。

## 7. 来源

- 产品码与守卫：`src/router/*`、`src/executor/cli_argv.mbt`、`src/server/{model_router_ops,server,issue_scan}.mbt`、
  `scripts/{gen_plugins,check_plugin_sync,check_test_sync,check_tools_sync,check_doc_surface,mcp_smoke}.py`。
- 实测日志：`temp/r4/full4.log`、`v4_gates.log`、`v4_router_smoke.log`、`v4_callsite.log`、`v4_mcp_smoke.log`、
  `prove_locks_red.py` / `prove_locks_red2.py` / `prove_b72_diff.py`、`t6.log`、`mut_b73.log`。
- 任务树与账本：`temp/r4/publish_pmode-r4*.json`、`findings_pmode-r4*.json`、`walk2_*.json`、
  `gates_pmode-r4-verify.json`、`memory/bugs.md`（BUG-61~75 条目 + 本轮 13 条 `### FIXED` 小记）。
- 规范真源：`AI-DEVELOPMENT-STANDARD.md`（`project_standards` 为其机器投影）与 `AGENTS.md` 角色边界/终审条款。
