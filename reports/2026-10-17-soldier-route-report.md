# 军衔体系 · §8.3 兵种↔模型池路由联动 — 报告

日期：2026-10-17
任务：实现 docs/ 计划的 §8.3「与自动路由的联动」（指挥官覆盖"远期变更，本期不做"）

## 结果摘要

§8.3 已完整落地为第 170 个 MCP 工具 `soldier_route`，并让 `model_route` 直接吃兵种提示：

- **`src/router/model_router.mbt`** 新增两个纯函数 + 一条新 pick 分支：
  - `pool_label_tier_hint(label)`：兵种/池标签 → `"paid"` / `"free"`（识别 `paid`、`特种`、`炮兵`）。
  - `soldier_label_reason(label)`：8 兵种 → 中文理由串（默认回退通用）。
  - `ModelRouter::pick` 新增可选 `soldier_label`；命中时走 `pick_with_hint`（复用 laya 分支的同一 helper），理由串 `"soldier <label> prefer <tier> tier"`、`laya_reason="soldier:<label>"`；无容量自动回落到正常逻辑，协议/存储零改动。
- **`src/server/model_router_ops.mbt`**：`model_route_impl` 增加 `soldier`/`pool_label` 参数，`resolved_pool = pool_label 优先，否则 display.pool_label_of(soldier)`；pick 传入 `soldier_label`；回执新增 `soldier`/`pool_label`/`tier_hint` 三字段。
- **`src/server/server.mbt`**：`model_route` 工具 schema 增 `soldier`/`pool_label`；新增 `soldier_route` 工具（兵种→池档位提示+理由+攻坚任务+模型档位），工具总数 169→**170**。
- **测试**：`src/router/soldier_route_wbtest.mbt`（sr_1~7）——tier 映射含特种兵/炮兵→paid、理由覆盖、特种兵→paid-a、通信兵→free-a、空标签零回归、paid 耗尽回落 free、档位匹配时 switch_count 不虚增。`moon test --target js src/router` = **209/209 passed**。
- **一源四态 cl7**：`gen_plugins.py` 重生成四宿主插件态（确认 **170 工具 / v0.3.8**），`check_plugin_sync.py` PASS，`check_tools_sync.py` PASS。

## 资源消耗

- 本地 `moon test --target js src/router`（209 用例）
- `moon fmt`（改动文件）+ `moon fmt --check`（改动文件 rc=0）
- `gen_plugins.py` ×2、`check_plugin_sync.py` ×2、`check_tools_sync.py` ×1
- 人工编辑：3 个源码文件 + 1 个新测试文件 + 4 份文档 + 1 次文档组计数修正

## 任务分配记录

- 全程自行实现（兵种映射 + 路由接线 + 工具注册 + 白盒锁 + 文档四态 + cl7 收口），未派子代理。

## 遗留风险

1. **全仓 `moon fmt --check` / `moon test --target js` 仍被并发 agent 的 `src/ops/ops_watchdog.mbt` 编译错误（`[4139]`/`[3002]`）挡住**，本仓无法全量判绿；按金条四未触碰该文件，需指挥官裁决让并发方收口。本域改动经 `moon info` 确认编译干净、路由器测试全绿。
2. `model_route` 服务端接线（`model_router_ops.mbt`/`server.mbt` 的 tool 层）**未能在本机跑一次真实 pick**（server 全量测试被上面同一编译错误阻塞），接线正确性由 `moon info` 通过 + 白盒测试覆盖路由层映射保证。
3. AGENTS.md 因指令预算被反复截断，`soldier_route` 行与组计数 `（27）` 已保留在正文内，但周边文字可能被截（内容由 `plugins/source/` 与 README 承载真源）。
4. BUG 账本已被并发 agent 推到 304 条（16 OPEN / 267 FIXED / 11 DUPLICATE / 8 FP）；`gen_plugins.py` 每次读取都反映最新账本，工具新增未产生账本漂移。

## 后续建议

- 指挥官裁决 `ops_watchdog.mbt` 的两处编译错误归属，让并发方收口后跑一次全量 `moon test --target js` + `moon fmt --check` 全绿，本 §8.3 随主分支一起验收。
- 后续可把 `soldier_route` 的 `tier_hint` 接入 `task_triage`/`dag_cost_route` 的建议链，让"兵种"成为跨模块软信号（本期未做，防范围蔓延）。

## 超额内容

- 指挥官要求仅 §8.3；额外补了 AGENTS.md 组计数 26→27、README/README_EN/ARCHITECTURE 工具计数 169→170 的对齐（cl6 一致性所必需）。

## 来源

- docs/ 计划 §8.1 军衔 / §8.2 士兵分类 / §8.3 与自动路由的联动
- 既有 `soldier_type_of`（§8.2，`src/display/soldier.mbt`）、`rank_of`（§8.1）、`staff_label_of`（§8.1 参谋线）
- `model_route` / `model_auth_status` 既有接线（`src/router/model_router.mbt` + `src/server/model_router_ops.mbt`）
