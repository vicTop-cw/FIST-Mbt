# 报告 · 2026-11-02 · required 矛盾面落地（修 bug_fix.evidence + 立 check_tool_required_sync 守卫尺）

> FIST 统帅批 · 续20 · 单轮收口（本轮无并发派单，team 委派在本会话未获批 ⇒ 统帅直接落地 + 终审）

## 结果摘要

续19 的「required 矛盾面普查」结论落地：把**唯一真缺陷**（`bug_fix.evidence` required 漏列）修掉，
并**同批立起**防回归守卫 `check_tool_required_sync.py`（本仓第一例）。二者是同一笔逻辑改动：
修的是现状，立尺是回归锁（R105「标 FIXED 必须留锁」的正身）。

- **修**：`src/server/server.mbt:9180` `bug_fix` 的 schema required 数组
  `["project_dir","bug_ids"]` → `["project_dir","bug_ids","evidence"]`。
  依据：描述三处「必填非空」（主描述 / evidence 属性 / 参数 summary）+ `bugreport.mbt:830`
  硬拒空 evidence ⇒ 客户端硬门此前与服务端函数不一致（漏写形态：空参一路漏到服务端函数才炸）。
- **立尺**：`scripts/check_tool_required_sync.py`（282 行）源↔源对表 `required` 数组 ↔ 必填 描述：
  - **漏写**：描述声称必填但 required 未列（本单形状）。
  - **多写**：required 列了但描述是「可选」或「条件必填」。
  - **条件必填白名单**：3 条点名豁免（`file_release.reason` / `bug_mark_status.dup_of` /
    `ocr_scan.path`）+ 三向过期自红（工具消失 / 参数不在 schema / 已变无条件必填且进 required）。
  - 源↔源解析（直接读 server.mbt 文本），**不起 server、不 build**，CI 可裸跑。

## 资源消耗

| 项 | 读数 |
|---|---|
| 落地文件 | 3（server.mbt 1 行 / check_tool_required_sync.py 282 行新 / run_guards.py 6 行） |
| 提交 | `184b75910`（scoped，落盘面与申报面逐字相等，未混并发 WIP） |
| 验证 | selftest 14/14；real 对表 167 工具零漂移；check_battery_count_doc PASS（missing=0）；check_arg_face_strict 96 把全严格 |
| gen_plugins | **未跑**（只改 required 数组、工具数 182 不变、未动 bugs.md 计数面） |
| 并发 | team 委派未获批 ⇒ 未派子代理；本轮单线程落地 |

## 任务分配记录

- 原计划派「实现车道」落地（续19 已定稿可直接派）；`team` 委派在本会话被拒（未获批），
  `task` 子代理只读无 shell ⇒ 无法「编辑+验证」闭环 ⇒ **统帅直接落地 + 自终审**（金条八：实际运行验证）。
- 校准子步骤：先写 `temp/_calib_required.py` 探针解析真 server.mbt（167 注册），
  定位 dag_mc 误报根因（空 `[]` 数组被 `^\[\s*"` 漏匹配而越界读到下一工具），修 `_schema_block` 后转绿。

## 遗留风险

1. **条件必填白名单是「主防线」而非「自动识别」**：`RE_COND`（仅/时必填/当…必填）只是辅助；
   新增条件必填若措辞不落在 RE_COND 且没进白名单 ⇒ 会被误判成漏写红。这是**故意的**（逼人显式登记），
   但新加条件必填的工具时**必须同批进 `WHITELIST_CONDITIONAL`**，否则 CI 红。
2. **多写只认「显式可选/条件必填」**：required 列了但参数**根本没出现在 参数 summary** 的情况
   不判多写（保守，避免 summary 不全造成误红）。这是已知漏检面（低优先）。
3. **解析器是文本扫描非 AST**：极端形状（required 数组跨行 / props 内嵌 `Json::object` 花括号）
   可能误切。当前 167 工具全解析、0 误报；若未来引入新形状需扩 `_schema_block`。

## 后续建议

- **挂 owner 面（等裁决，本轮不擅动）**：
  - **BUG-542**（宿主技能副本 ledger 计数滞后，OPEN）：倾向**出路 B**（在 `docs/known-boundaries.md`
    §3 登记「宿主副本是快照式、与仓内真源可能不一致、harness 注入的是宿主本地仓」）——
    可逆、CI 可自证、不引入本机路径耦合；出路 A（`sync_host_skills.py`）本机耦合 + 不可 CI 自证，
    代价更高。**请 owner 定 A/B。**
  - BUG-538 ops 半（owner 在 Qoder 重连 MCP 连接器）、BUG-527 出路②（上游 issue，文本已备）。
- **可选增强（非阻塞）**：多写检测扩到「required 列了但 summary 完全未提及该参数」（当前保守跳过），
  需在真树上确认零误报后再开。

## 超额内容

- 无。严格限定在续19 定稿范围（修 bug_fix.evidence + 立 check_tool_required_sync + run_guards 注册）。
  未动 AGENTS.md / plugins / 4 个并发 WIP 脚本（另一 agent 活跃面）。

## 来源

- 续19 普查回传（memory/2026-11-02.md 统帅批·续19「required 矛盾面普查」段）。
- 真源：`src/server/server.mbt`（167 `= instrumented_tool(` 注册）、`src/server/bugreport.mbt:830`、
  `src/server/server.mbt:3902`（[omega:required] 根任务标记）。
- 同族守卫：`scripts/check_usage_tool_count.py`（Part B T0r12 参数列双向对表，本尺的文档面互补）。
- 判例：R207（新判据拒绝未知旗标，argparse）、判例-30（变异对照改代码不改注释）、
  BUG-514（PASS 行格数从已执行格子反解不手写）、R105（标 FIXED 必须留回归锁）。
