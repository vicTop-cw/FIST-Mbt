# Goal-2 Round 26 报告 · P2c 前置：RouterConfig 加 use_caf_memory 字段

- 日期：2026-10-15
- 目标：使用 fist-mbt 全程开发，持续【寻虫-修复-验证-推进】循环轮转
- 交付：P2c §2.1 完成（RouterConfig 加 `use_caf_memory` 字段），148/148 + 全仓 1128/1128 零回归

## 结果摘要

P2c wiring 设计 §2.1 已实施：给 `RouterConfig` 加 `use_caf_memory : Bool` 字段。

**发现**：`model_router.mbt`、`router_config.mbt`、`model_router_wbtest.mbt`、`router_state.mbt`、`router_config_wbtest.mbt` 全部干净（已提交，非 WIP），可以安全编辑。

**改动**：
- `model_router.mbt`：struct 加 `use_caf_memory : Bool`（默认 false）+ `default()` 初始化
- `router_config.mbt`：`from_json` 解析 `use_caf_memory`（true/false/null/garbage 与 `use_laya` 同口径）+ `to_json` 序列化
- `model_router_wbtest.mbt` / `router_state.mbt`：批量补字段（18 处）
- `router_config_wbtest.mbt`：更新 `cfg_ofm_2` 键集合锁（6→7）+ 新增 `cfg_caf_1/2/3` 三条测试
- `scripts/patch_router_config_caf_field.py`：批量补字段脚本（幂等）

## 验证

```
src/router: Total tests: 148, passed: 148, failed: 0.
全仓:       Total tests: 1128, passed: 1128, failed: 0.
```

**零回归**确认：`use_caf_memory=false` 时行为完全不变（同 `use_laya`）。

## 资源消耗

| 项 | 值 |
|---|---|
| 新增文件 | 1（scripts/patch_router_config_caf_field.py） |
| 修改文件 | 5（model_router.mbt / router_config.mbt / model_router_wbtest.mbt / router_state.mbt / router_config_wbtest.mbt） |
| 新测试 | 3（cfg_caf_1/2/3） |
| moon test 次数 | 2（src/router 145→148，全仓 1124→1128） |
| commit | 7b5d96f |

## 任务分配记录

全部由主代理直接实施（子任务小、改动局部，未启用 FIST 拆解）。

## 遗留风险

1. **P2c §2.2（pick 钩子）+ §2.3（回写 + status）**：依赖 `model_router_ops.mbt` 释放（并发 agent WIP 25 文件，已 4 轮无新提交 `1e5061e` 之后）。
2. **P2d 接线**：等待 P2c wiring 完成后实施（P2d 纯函数已提交 `4134501`）。
3. **并发 agent 停滞**：`router_caf.mbt` + `model_router_ops.mbt` 均有未提交小改动（4 增 9 删 + 5 增 1 删），看起来已完成但未 commit。

## 后续建议

1. Round 27：若 `model_router_ops.mbt` 释放 → 实施 P2c §2.2/§2.3 + P2d 接线。
2. Round 27：如果并发 agent 继续停滞，考虑帮其提交未提交改动（需确认其意图，避免 conflict）。
3. Round 27：把 `scripts/patch_router_config_caf_field.py` 记录到 `scripts/README.md`（如需）。

## 超额内容

无。

## 来源

- `docs/2026-10-15-fist-mbt-caf-p2c-wiring-design.md`（更新，§2.1 标记已完成）
- `git log --oneline -6`
- `moon test --target js src/router` → 148/148
- `moon test --target js` → 1128/1128
