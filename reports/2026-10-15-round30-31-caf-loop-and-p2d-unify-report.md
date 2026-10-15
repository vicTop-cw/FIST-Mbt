# Round 30-31 报告 · caf_loop_1 回写通路真源 + P2c/P2d 统一

- 日期：2026-10-15
- 目标：Goal-2 持续【寻虫-修复-验证-推进】循环 —— R30 验证 §2.3 回写通路真源；R31 把 P2c 与 P2d 在 router 层统一
- 状态：**完成**，commit `132fcca`（R30 caf_loop_1）+ `2a669ef`（R31 P2c+P2d 统一）

## 结果摘要

### R30 · caf_loop_1：钉住 §2.3 回写的真源前提

§2.3 的核心动作是 `executor_run` 后调 `caf_memory.push(...)` 把执行结果写回记忆。`push` 的签名是
`pub fn CafMemory::push(self : CafMemory, rec : CafRecord) -> Unit` —— **值接收**。若 MoonBit 严格值语义
导致 `count`/`head` 改动不传播，回写形同虚设。

新增白盒锁 `caf_loop_1_记忆可写可读闭环` 实测钉死三件事：
1. `mem.push(...)` 3 次后 `mem.count` 0→1→3 **真的更新**（值接收下 mut 字段改动传播到调用方，与直觉相反但行为已证）
2. `mem.knn_stats(...)` 能把 push 的记录聚合出 free-a/free-b 两条统计
3. 同一份 memory 传给 `pick_caf_dry_run` 能把决策从 free-a 重排到 free-b（0% 失败 → 100% 成功）

即"执行结果 push → 记忆可读 → 下次决策重排"的闭环在 router 层**成立**。server 层接线时只需把同一份
`CafMemory` 传进 `push` 与 `pick_caf_dry_run` 即可，**无额外 router 层改动**。

### R31 · P2c 与 P2d 在 router 层统一

P2d（Round 22-23）已实现 `caf_soft_reorder_with_preference`，但接线要进 `model_router_ops.mbt`（被阻塞）。
R31 在 router 层把"是否启用冷启动偏好"的分支收敛到一处：

- 新增私有函数 `caf_reorder_combined(candidates, stats, preference, min_evidences)`：
  - `preference` 为空（默认）→ 纯 `caf_soft_reorder`，**行为与 R29 完全一致**（零回归）
  - `preference` 非空 → `caf_soft_reorder_with_preference`：记忆充足时内部退化为成功率排序，
    记忆不足时按偏好冷启动重排
- `pick_caf` / `apply_caf` / `pick_caf_dry_run` 统一加两个可选参数：
  `caf_default_preference? : Array[String] = []` 与 `caf_min_evidences? : Int = 10`
- server 层接线时把 `RouterConfig` 的两个新字段直接透传即可，**无需分支判断**

新增 3 条白盒锁：
| 锁 | 断言 |
|---|---|
| `caf_pref_1_默认偏好为空时行为与无偏好一致` | `caf_default_preference=[]` 与不传时 reordered/picked 完全一致（零回归） |
| `caf_pref_2_记忆不足按冷启动偏好重排` | 空记忆 + 偏好 free-b → base=free-a 切到 free-b |
| `caf_pref_3_记忆充足时偏好退化为成功率排序` | 记忆充足 + 偏好指定 free-a 但证据更优的 free-b 胜出（**真实证据优先于冷启动偏好**） |

## 资源消耗

| 项 | R30 | R31 |
|---|---|---|
| 涉及文件 | 1（`model_router_caf_wbtest.mbt`） | 3（`model_router_caf.mbt` + `model_router_caf_wbtest.mbt` + `pkg.generated.mbti`） |
| 新增行数 | 65 | 120 |
| 测试基线 | src/router 157/157 | src/router 160/160 |
| 提交门禁 | `moon fmt` + `moon test --target js src/router` | 同左 + `moon info` 同步 `.mbti`（3 处签名 +2 参数） |
| 全仓 `moon test --target js` | 仍不可跑：并发 agent WIP 的 3 errors（`src/symbolic` 等）挡住 `moon info`；router 包独立绿 | 同左 |

## 任务分配记录

| 步骤 | 执行者 | 结果 |
|---|---|---|
| caf_loop_1 回写通路真源锁 | 主 agent | ✅ commit `132fcca`，157/157 |
| caf_reorder_combined + 三函数加参数 | 主 agent | ✅ commit `2a669ef` |
| caf_pref_1~3 白盒锁 | 主 agent | ✅ 160/160 |
| 三份 docs 状态同步 | 主 agent | ✅ p2c wiring 头部 / p2d 设计头部 / plan 状态行 |

## 遗留风险

1. **server 层 §2.3 接线仍是唯一阻塞**：`RouterConfig` 加 `caf_default_preference` / `caf_min_evidences`
   字段（`src/router/model_router.mbt`）+ `model_router_ops.mbt` 回写/透传/status 三处，都等并发 agent WIP 收口。
2. **`CafMemory::push` 的传播机制未从源码层面解释清楚**：行为已验证（count 0→1→3），但 MoonBit
   值接收 `self` 下 mut 字段为何传播到调用方，本轮未深挖底层语义。行为契约已由 `caf_loop_1` 钉死，
   即使未来语义变化，该锁会立刻红——这是把"经验判断"升级为"可回归断言"的典型收益。
3. **全仓回归仍未跑**：并发 agent WIP 未提交的 parse/编译 errors 挡住 `moon info` 与全仓 `moon test`。
   router 包 160/160 是本轮可靠基线。
4. **P2d 的 A/B 预演结论（Round 25）**：冷启动偏好的收益是**场景依赖**的（成本敏感场景 baseline 反而更优）。
   本轮只在 router 层做了机制统一，未重跑 A/B。建议 §2.3 接线后按场景配置 `caf_default_preference`，
   默认保持空（零回归）。

## 后续建议

1. 并发 agent WIP 收口后：照 `docs/2026-10-15-fist-mbt-caf-p2c-wiring-design.md` §2.3 实施三处接线
   （RouterConfig 字段 + executor_run 回写 + status 展示），随后跑全仓 `moon test --target js` 确认零回归。
2. P2d 偏好默认保持空（`caf_default_preference=[]`），避免未经验证的场景假设上线。
3. 可选加固：`mark_failure` 写入前 clamp 冷却截止到 Y2038 内（源头上杜绝坏值），消除 BUG-206 fail-open 语义歧义。
4. 下次遇到 `Array[T].map(fn(x){x})` 意图深拷贝时，先想 MoonBit 的 copy elision——显式构造才是可靠路径（R29 踩坑）。

## 超额内容

- 无（R30/R31 严格在 src/router + docs + memory + reports 允许作用域内）
