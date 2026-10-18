# 军衔体系 · 士兵分类 · 参谋线（§8.1 / §8.2 / §8.1 参谋线）实现报告

日期：2026-10-17
执行会话：marvis（marvis-verify-20261017 分支）
来源计划：`docs/2026-10-12-fist-mbt-web-dashboard-plan.md` §8.1（97-133 行）、§8.2（135-148 行）、§8.3（150-159 行）

## 结果摘要

按指挥官 2026-10-17 指令「军衔体系在弄了没？目标就是实现 docs/ 下的计划」，本会话把 §8.1 / §8.2 落地为**展示层**实现，协议与存储零改动：

| 计划章节 | 实现 | MCP 工具 | 真源 | 测试 |
|---|---|---|---|---|
| §8.1 军衔体系（*长 总表） | 8 军衔 × 协议角色映射 | `rank_of` | `src/display/rank.mbt` | 9/9 |
| §8.2 士兵分类（兵种 × 模型档位 × 攻坚任务） | 8 兵种 × 4 模型档位 × 4 攻坚类型 | `soldier_type_of` | `src/display/soldier.mbt` | 8/8 |
| §8.1 参谋线（非 *长 参谋军职） | 6 参谋军职 × 职责 × 层级 | `staff_label_of` | `src/display/staff.mbt` | 6/6 |

**合计 23/23 测试通过**（`moon test --target js src/display`）。

### 军衔体系（`rank_of`）

- `rank_of(level)`：L=0 司令 / L=1 军长 / L=2 师长 / L=3 旅长 / L=4 团长 / L=5 营长 / L=6 连长 / L=7 排长；越界回退士兵。
- `is_officer(level)`、`officer_levels()`：军官判定与军官层列表。
- 叶子恒为士兵；默认 root depth=3 → 实际激活 4 档（司令→军长→师长→士兵），旅长及以下占位（调大 depth 自动激活）。
- **协议层不感知军衔**：除统帅/士兵/政委外，所有 *长 在协议层一律映射为 Leader 角色。

### 士兵分类（`soldier_type_of`）

- 8 兵种：侦查兵（情报/调研/搜索）、炮兵（重构/算法/攻坚）、特种兵（高价值/紧急/架构）、医疗兵（修复/故障/抢救）、通信兵（消息/汇报/提醒）、后勤兵（整理/分配/归档）、工兵（环境/依赖/脚本，默认）、骑兵（短平快/高频/批量）。
- 兵种 → `pool_label_of()`（§8.3 模型池标签的展示层映射）：工兵=general、炮兵=algorithm、特种兵=architect、侦查兵=research、医疗兵=fix、通信兵=comm、后勤兵=general、骑兵=fast。
- 关键词匹配大小写不敏感（`String::to_lower()`）。

### 参谋线（`staff_label_of`）

- 6 参谋军职：侦察参谋（Searcher 情报搜集）、后勤参谋（Allocator 资源分配）、验收宪兵（Verifier 交付验收）、监察参谋（Observer 状态监察）、训练教官（SpecAuthor 规范编写）、军务文书（Recorder 记录归档，默认）。

## 资源消耗

- 全部由当前 marvis 会话直接实现，无子代理、无外部执行器调用。
- 新增文件 6 个：`src/display/{rank,soldier,staff}.mbt` + `{rank,soldier,staff}_test.mbt` + `src/display/moon.pkg`。
- 修改文件：`src/server/server.mbt`（注册 3 工具）、`README.md` / `README_EN.md` / `AGENTS.md` / `ARCHITECTURE.md`（169 工具同步）、`plugins/*`（gen_plugins 重生成）。
- 分支 `marvis-verify-20261017` 新增 7 个提交。

## 任务分配记录

| 环节 | 负责 | 完成 |
|---|---|---|
| §8.1 rank 实现 | marvis | ✅ |
| §8.2 soldier 实现 | marvis | ✅ |
| §8.1 参谋线实现 | marvis | ✅ |
| server.mbt 工具注册 | marvis | ✅ |
| 文档 169 工具同步 | marvis | ✅ |
| cl7 插件态重生成 | `scripts/gen_plugins.py` + `check_plugin_sync.py` | ✅ PASS |
| 工具清单同步 | `scripts/check_tools_sync.py` | ✅ PASS |

## 超额内容

- **check_tools_sync 三处漂移修复**：AGENTS.md 运维分组计数 `（19）→（26）`；README_EN.md / server.mbt 头注释 `166/3/2 → 169/3/2`；README.md M8 里程碑工具计数改下限式 `36+`（与守卫族「下限式防写死数字腐烂」口径一致）。
- 工具计数从 166 升到 **169**。

## 遗留风险

1. **ops_watchdog.mbt 编译错误（并发 agent 未修）**：`[4139]` / `[3002]` 错误全部位于 `src/ops/ops_watchdog.mbt`（并发 agent 正在编辑），阻塞全仓 `moon test`。**不是我改的，按金条四不代修**，但因此未能端到端调 MCP 工具验证 rank_of/soldier_type_of/staff_label_of 的运行时行为。
2. **§8.3 与自动路由联动未实现**：`pool_label_of()` 展示层已就绪，但 `model_route` 消费兵种标签属远期变更（需 `core_role` 新增 `Reminder` 枚举、`Executor` 兵种元数据），本计划文本本身也标注「当前版本不实施」。
3. **军衔 wire 到 board_ascii 未做**：可选深化，§8.1 未强制要求。
4. **`String::to_lowercase` 不存在**（MoonBit 无此 API），已改用 `to_lower()` —— 已在 soldier.mbt / staff.mbt 落定。

## 后续建议

1. **ops_watchdog 修好后跑全量 `moon test --target js`** 端到端验证三工具运行时行为（当前只能靠 23 条黑盒测试与编译期注册自证）。
2. **§8.3 路由联动**：待 `model_route` 支持池标签消费后，把 `pool_label_of` 接到路由决策。
3. **军衔 wire 进 board_ascii**：可在看板每行标注展示军衔/兵种，让「一眼看军旗体制」落地。
4. **清理僵尸**：`1111` 已暂停（force archive 需指挥官授权）、243+ 认领不执行（heal/reopen）。

## 来源

- `docs/2026-10-12-fist-mbt-web-dashboard-plan.md` §8.1（97-133 行）、§8.2（135-148 行）、§8.3（150-159 行）
- `src/display/rank.mbt` / `soldier.mbt` / `staff.mbt` 及对应 `_test.mbt`
- `src/server/server.mbt`（rank_of / soldier_type_of / staff_label_of 工具注册）
- `scripts/gen_plugins.py` / `check_plugin_sync.py` / `check_tools_sync.py`
