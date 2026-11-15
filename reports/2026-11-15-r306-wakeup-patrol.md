# 轮 306 巡检报告（ExploreWatchdog 唤醒 · 2026-11-15）

## 结果摘要

- **WIP 四件套冻结零变化第 23 轮**：`git status --short` 与 r284~r305 逐字同——
  `M docs/improvement-plan-20261010.md` / `M memory/bugs.md` / `M memory/target.md` /
  `?? scripts/check_mcpcf_db_isolation.py`；mtimes 逐字同（11-14 10:47:48 / 10:55:34 /
  11-10 10:34:16 / 11-14 11:11:49，全早于 r284 提交 15:19:37），`diff --stat` 逐字同
  3 文件 208+/2-，相对 r305 零新增量。r287 提请的 owner 弃置裁决维持挂起（指挥官不代行清理）。
- **Round C 三件维持过期不执行**：BUG-527 owner 否决 / BUG-530 FIXED /
  `check_usage_tool_count` 已注册（run_guards.py:175）。
- **换面巡检 `check_host_installable`（cl7 补丁：投影一致 ≠ 真能装上；D1 DSH 严格档 /
  D2 宽松档 / D3 默认模板三档判据，纯静态不联网不真装；r305 列下轮候选·本轮首跑）**：
  - `--selftest` → SELFTEST OK rc=0（DSH 严格档：相对路径 / `timeout_ms` / reconnect 键名 /
    未定义占位符必红；干净 DSH + 默认模板 + 宽松档不误红；输入面退化自拒；
    字段白名单反解自真源 `src/server/mcp_config_scaffold.mbt` 的 `mcp_form_field_whitelist`）；
  - 实测 **PASS rc=0**：DSH manifest/patch（严格档：绝对路径 + `toolCallTimeoutMs` +
    dsh reconnect schema）合规；宽松档 MCP JSON 合规；默认模板合法性合规；
    moon.mod 版本 0.3.11。
  - 3 条信息级 WARN（`.mcp.json` / `.mcp.dev.json` / `plugins/claude/.mcp.json` 用
    `timeout_ms`）：判据 D2 档按设计只打信息级 WARN、**不计入退出码**（「是否改真源
    由人终审」）⇒ 设计稳态，非新发现、不落账。
- **零漂移两把尺**：`check_tools_sync` 183 一致 rc=0（R8 清单分组 19 组 ΣN=183）；
  `check_instruction_budget` 50440/65536 rc=0（全部章节可见）。均与 r305 读数一致。
- **无新发现、无新立账**。
- **禁区零碰**：4 个 WIP 文件零改、不提交。

## 资源消耗

- 判据 4 支（1 换面巡检自检 + 1 实测 + 2 零漂移）+ FIST 六步链 1 发；本轮无子代理。

## 任务分配记录

- FIST 闭环 T0r62 六步全链 rc=0 一发收口（wd-r306，ns watchdog）：`temp/fist_r306_chain.sh`
  后台串跑，回盘 `temp/fist_r306_out/1..6_*.txt`（publish / agent_acl_grant / claim /
  execute / submit / verify）；verify 回执 status=已完成、completed_by=wd-r306。

## 遗留风险

- WIP 四件套冻结第 23 轮，跨日 11-14→11-15 仍零变化；弃置裁决持续挂起等 owner。
- r305 新发现（`scripts/check_mcpcf_db_isolation.py` 双风险：`moon publish` 公开面 +
  未注册 `run_guards.py`）仍待 owner 裁决（方案 A 推荐：WIP 提交时同批给执行面 +
  入库或进 .gitignore / 方案 B：指挥官代落账，当前 memory/bugs.md 被 WIP 占用受阻）。
- r302 发现（AGENTS.md:360 check_demo_isolation 散文计数 29 ↔ 实测 36 漂移）落账仍受阻
  （memory/bugs.md 被 WIP 占用，指挥官不代行），维持待 owner 裁决 A/B 两方案。

## 后续建议

- 换面巡检继续轮换制：本轮 `check_host_installable` 已跑，下轮候选
  `check_plugin_sync`（cl7 一源四态；脏树 rc=1 为 WIP 投影已知读数，r292 实证）/
  `check_arg_face_strict` / `check_model_auth_no_key`。
- owner 裁决件累计三件：WIP 四件套弃置、新脚本执行面 + publish 公开面、r302 落账方式。

## 超额内容

- 无。

## 来源

- `git status --short` / `git log --oneline -3`（HEAD f1a2e97d3 = r305 提交）
- `python scripts/check_host_installable.py --selftest` 与实测输出
- `python scripts/check_tools_sync.py` / `python scripts/check_instruction_budget.py` 输出
- `temp/fist_r306_out/` 六步回盘
