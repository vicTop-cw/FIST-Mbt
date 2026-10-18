# FIST-Mbt CAF 失败执行污染修复（Slice C）报告

- 日期：2026-10-18
- 提交：`09e1361`（fix(router): CAF 写半 ok 语义）+ `68b7aeb`（docs(usage): USAGE.md 版本对齐）
- 触发：Slice B 报告遗留项 —— `mr_record_only` 在 `resp.is_error` 检查之前被调用，导致**失败的执行也 push `ok=true` 进 CAF 记忆**，长期抬高「常失败模型」的 CAF 成功率。
- 驱动方：FIST-Mbt（父代理编排 + 子代理 191c2140 落码，父代理独立终审）

## 结果摘要

给 CAF 记录路径加上可穿透的 `ok` 语义：成功 push `ok=true`、失败 push `ok=false` —— CAF 同时学成功与失败，不再只学成功侧。

| 门禁 | 结果 |
|---|---|
| `moon check src/server src/router` | 0 errors（1066 warnings，全为仓库既有 deprecated/unused_try） |
| `-f "*caf_dr*"` | **10/10**（9 → 10，含新 `caf_dr_10`） |
| `-f "*mo_*"` | 10/10 |
| `-f "*ma_*"` | 6/6 |
| `-f "*bug229*"` | 1/1 |
| `moon test --target js` 全量 | **1324/1324, failed 0**（25.3s；1323 + 新 1） |
| `moon fmt --check` | exit 0 |
| `moon info` + `.mbti` 内容 diff | **无**（`ok?` 未暴露 pub 面；moon info 后的 5 个大 numstat 经默认 diff 归一化证为纯换行幻影，已回滚） |
| `python scripts/check_doc_surface.py` | **PASS**（J4 转绿：`当前自述版本=0.3.9`，170 工具分组和=170） |

## 资源消耗

- 子代理 191c2140：1 次（落码 + 自验，未 commit）
- 父代理终审：moon check + 4 组定向测试 + 全量 moon test + fmt + moon info + 3 次工作树 diff 核查 + check_doc_surface

## 任务分配记录

- 子代理 191c2140：`src/server/model_router_ops.mbt` + `src/server/model_router_ops_wbtest.mbt` 落码
- 父代理：终审、`.mbti` 幻影回滚、pathspec 提交、记忆/报告

## 改动明细

**`src/server/model_router_ops.mbt`（+13/-7）**
1. `mr_caf_push_evidence`（L125）新增必填 `ok : Bool`，`CafRecord::new(..., ok~, ...)` 替换硬编码 `ok=true`；文档注释改为「ok 由调用方给定：成功 ok=true、失败 ok=false——CAF 同时学成功与失败，不能只学成功（否则『常失败模型』的 CAF 成功率被长期抬高）」。
2. `model_route_impl`（L342）新增可选 `ok? : Bool = true`，在 CAF push 处（L483）传 `ok`。
3. `mr_record_only`（L543）新增可选 `ok? : Bool = true`，内部透传 `ok~`。
4. 三调用点：
   - OFM L891：`ok=not(resp.is_error)`（`resp` 在 L889 `classify_ofm_failure(http_status, resp.error_type)` 已用，作用域成立）
   - CLI 重试分支 L1234：`ok=false`（分支 `if !okk && ...` 内）
   - CLI 最终 L1254：`ok=okk`

**`src/server/model_router_ops_wbtest.mbt`（+64）**
- 辅助 `caf_read_last_ok(path)`：显式 match 读取 CAF 文件末条记录的 `ok` 字段。
- 新锁 `caf_dr_10_失败执行push_ok_false_CAF学成败`：穿透链双向验证（`ok=false` → 末条 `ok=false`；默认 → 末条 `ok=true`），`caf_read_rec_count==2` 证「追加」非「覆盖」。

## 关键决策点

1. **穿透链未超出预期**：`ok` 只穿 `mr_record_only → model_route_impl → mr_caf_push_evidence → CafRecord::new` 四层，无其他中转函数。
2. **默认 `true` 保零回归**：未显式传 `ok` 的所有既有调用（mo_*/caf_dr_*/server.mbt 的 model_route、executor_run 内其他记账路径）行为不变。
3. **MoonBit `not` 需括号**：首轮 `ok = not resp.is_error` 触发 parse error（`resp.is_error` 是 `Bool` 字段非函数），改 `not(resp.is_error)` —— 唯一一次编译往返。
4. **`caf_dr_10` 走穿透链**（与 `caf_dr_7` 同口径最小可验），不触发 OFM/CLI 真执行。
5. **`ok` 序列化为 `Json::True/False`**，`caf_read_last_ok` 显式 match 读取，不依赖 `mo_bool` 兜底。

## 边界遵守

- `mr_record_failure`（冷却路径）一字未动；`src/server/server.mbt`、`src/core`/`engine`/`store`/`display`/`router` 非必要处未动。
- `caf_dr_1..9`、`mo_*`、`ma_*`、`bug229` 既有测试行为未改。
- **MCP schema / 回执字段零增删**：`ok` 是内部参数，`model_route_impl` 非 MCP 直接暴露面。
- `query-only` 零副作用保持：`ok` 只在 `if consuming && r.config.use_caf_memory` 门后使用。
- 坏 JSON 记忆不覆盖不删除：`caf_dr_6/9` 未破。

## 遗留风险

1. **OFM 侧 `ok` 依赖 `resp.is_error`** 而非 `http_status`：与失败判据 `if resp.is_error`（L892）同源，二者一致；若未来失败判据改为看 `http_status`/`failure_kind`，此处需同步。
2. **CAF 学失败后成功率会回落**：`use_caf_memory=true` 且路由到模型失败率高时，CAF 建议会因 `ok=false` evidence 更频繁切换模型。这是本次修复的**预期行为**（治污染），但会改变现有 dry_run 建议分布，无历史基线可比。
3. **`caf_dr_10` 未覆盖真实调用路径**上 `resp.is_error`/`okk` 的取值 —— 那部分靠调用点代码正确性 + 既有 mo_*/ma_* 覆盖。

## 超额内容

- 顺手收口 **J4 文档面守卫转绿**：USAGE.md L3 版本 `0.3.8` 落后 moon.mod `0.3.9`，已改 `0.3.9`（提交 `68b7aeb`）。README 无旧资产字面量（R13 干净）。`check_doc_surface.py` PASS。
- 核查 11 条 OPEN 缺陷：全部属**外部项目**（Pentad `p5` 编译器 / actus），非 FIST-Mbt 本身 —— FIST-Mbt 自身 healthy、`done_no_artifact=0`、无内部 OPEN 缺陷。

## 后续建议

- 若下游有对 dry_run 建议稳定性的断言，需复核「CAF 学失败」对建议分布的影响。
- 若未来 OFM 失败判据演进，同步更新 L891 的 `ok=not(resp.is_error)`。
- 可考虑为 OFM/CLI 真实调用路径补一条端到端锁（覆盖 `resp.is_error`/`okk` 在真实路径的取值）。

## 来源

- 触发来源：`reports/2026-10-18-caf-slice-b-report.md`（遗留项）
- 代码真源：`src/server/model_router_ops.mbt` / `src/server/model_router_ops_wbtest.mbt`
- 验收门禁：本地 moon `0.1.20260920`（`moon check` / `moon test --target js` / `moon fmt --check` / `moon info`）