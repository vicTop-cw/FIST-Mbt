# Goal-2 Round 35 报告：CAF 字段坏类型降级契约锁（caf_cfg_3~4）

- **日期**：2026-10-15
- **提交**：`2b3e3cc`（1 文件 +55）
- **状态**：§2.3 server 接线仍阻塞（并发 agent 占用），本轮钉死接线的**契约前置**

## 结果摘要

### 背景

检查 `model_router_ops.mbt` WIP diff（4/9）：并发 agent 只改 `ends_with`→`has_suffix`（字符串 API）与
`build_command(..., workdir="")`，**完全无关 CAF 接线区域**。但同文件改动未提交，
此时介入会与并发 agent 的工作混在同一 commit —— 风险大于收益。**放弃接线**，改钉 §2.3 的契约前置。

### R33 的 from_json 坏类型逻辑存在但未锁

R33 给 `RouterConfig` 加 `caf_default_preference` / `caf_min_evidences` 时，`from_json` 已实现坏类型降级
（`src/router/router_config.mbt`）：
- L102：`caf_default_preference` 非数组 → `[]` + warning
- L109：`caf_min_evidences` 非数字 → `10` + warning

但 R33 的 `caf_cfg_1` 只锁了**正常形状**的 JSON 往返，**坏类型降级无锁**。§2.3 server 接线会依赖这条
健壮性（config JSON 字段类型不对不得 panic），是接线前必须钉死的契约。

### 新增 2 条契约锁

| 锁 | 钉死的契约 | 区分度 |
|---|---|---|
| `caf_cfg_3_坏类型偏好降级默认` | `caf_default_preference` 给 `Json::string("oops")` → `[]` + 1 warning；同一 JSON 里正常 `caf_min_evidences=3` 不被牵连 | 断言空偏好 + warns≥1 + min=3 |
| `caf_cfg_4_坏类型min_evidences降级默认` | `caf_min_evidences` 给 `Json::string("abc")` → 默认 10 + 1 warning | 断言 10 + warns≥1 |

两条锁都有**双向区分**：正确路径（降级+warning）通过，错误路径（panic 或静默返回坏值）即红。

## 资源消耗

`moon fmt` / `moon check` / `moon test --target js src/router` / 全仓回归 / `git diff`（WIP diff 审计）

## 任务分配记录

本轮**无任务分配**（未拆子任务）。本人在 router 域独立推进，未触碰并发 agent 工作面。

## 遗留风险

- **§2.3 server 接线仍未做**。并发 agent 的 `model_router_ops.mbt` 改动（字符串 API + workdir）不覆盖 CAF 区域，
  但同文件多 agent 混改有 commit 污染风险（本轮已实际踩到）。
- **并发 agent WIP 面极大**：工作树 80+ 文件未提交（整个 src/ 在同步开发），任何全仓操作（`moon fmt` / `git add -A`）
  都可能误触他们的改动。

## 后续建议

1. **接线改用独立文件策略**：§2.3 接线的 CAF 逻辑放新文件 `src/server/model_router_caf_ops.mbt`，
  只在 `model_router_ops.mbt` 加**最少调用点**；提交时用 `git commit --only <path>` 限定，避免 commit 污染。
2. **R36 首选**：并发 agent 释放 `model_router_ops.mbt` 后立即接线（验收 = `executor_run` 走 CAF 路由 +
   status 看到记忆聚合 + dry_run 预览返回建议模型与依据）。
3. **R36 备选**：CAF 记忆的**持久化**设计（CafMemory 现为进程内存，server 重启即失；§2.3 接线后应落盘
   `memory/model-router-caf-{ns}.json`，与 `model-router-{ns}.json` 同形态）。

## 超额内容

**共享 repo 的 commit 污染教训**：`git add <file>` 后 `git commit` 会把 index 里**其他 agent 已 staged** 的文件
一起提交（本轮误提交 `ops_pipeline.mbt` 等 3 个并发文件，已 `reset --soft` + `unstage` 回滚）。
**正确姿势**：`git commit --only <path>`（只提交指定路径的版本，index 其他内容不动）。
这是多 agent 共仓开发的必知纪律，已记入 memory。

## 来源

- 代码（只读审查）：`src/router/router_config.mbt`（from_json L66-128、to_json L336-341）
- 测试：`src/router/model_router_caf_wbtest.mbt`（caf_cfg_3~4 追加于 caf_cfg_2 后）
- 设计：`docs/2026-10-15-fist-mbt-caf-p2c-wiring-design.md`、`docs/2026-10-15-fist-mbt-caf-p2d-cold-start-design.md`
