# R21 报告：组合模式编排 + 自动路由能力验证（为规则层修复落地定执行者）

- **轮次**：R21
- **日期**：2026-10-20
- **作用域**：fist-mbt 自身能力验证（组合环 `loop_create`/`loop_tick` + 自动路由 `executor_route`/`executor_auction`）
- **产物**：本报告

---

## 结果摘要

`src/server` 仍 37 脏（R14→R21 **八轮字节未变**），BUG-345/346/347/348 落地继续等待清空。本轮启用目标措辞显式要求的**组合模式 + 自动路由**两件能力，用 fist-mbt 自身**编排"规则层修复"的工作流并选出执行者**——既验证能力健康，又固化"谁来落地"的推荐。

### 1. 组合环（full-iterate）已注册并推进

```
loop_create(name="r21-rule-layer-fix", preset="full-iterate")
→ steps=["advance","bugfind","fix_and_merge","verify"], status=active, max_rounds=5
loop_tick(name="r21-rule-layer-fix")
→ next_mode="bugfind"（idx 1/4），should_stop=false
```

组合环状态：**当前停在 `bugfind` 步**（寻虫），等待下一环推进到 `fix_and_merge`（修复合并）——恰对应「寻虫已完成（BUG-345/346/347/348）、待修复落地」的现状。

### 2. 自动路由：拍卖 + 能力路由收敛于同一执行者

对需求 `need="规则精度,moonbit"`：

| 机制 | 结果 | 依据 |
|---|---|---|
| **`executor_auction`**（R87 置信度校准拍卖） | 胜者 **`exec-scan-rules`** | 4 名竞拍者；coverage=1.0，出价 1.0，校准=0.5（出价高于历史兑现率 0.5 → 折扣），拍卖分 0.5 |
| **`executor_route`**（R80 历史信任轴） | best **`exec-scan-rules`** | 19 名候选；coverage=1.0 → trust=0.5 → load=0 |

**两套独立机制给出同一答案**，交叉印证。拍卖还演示了"防胜者诅咒"：`exec-scan-rules` 自报 100% 置信但历史兑现率仅 0.5（无历史），被校准折扣后仍胜出——说明其余竞拍者能力覆盖更弱，而非该执行者真的高置信。

> 说明：本轮登记的两个执行者 `exec-scan-rules` / `exec-verify-gate` 是**演示用**登记（abilities 如实标注 moonbit/规则精度/issue_scan 与 验证/测试），已在 store 持久化。它们与库内既有的 `polish-lead`、`marvis`、`lead-fist`、`atomcode-glm53` 等真实执行者同表共存，供后续落地复用或清理。

### 3. 推荐：规则层修复落地的执行者

自动路由建议 **`exec-scan-rules`** 承担 BUG-348 修复（unused-variable/match-exhaustive 口径），`exec-verify-gate` 承担 `moon test --target js` 全绿验证门。待 `src/server` 清空后按此派单，配合 owner 已裁决的 BUG-347/345/346 批。

---

## 资源消耗

| 项 | 量 |
|---|---|
| `loop_create`（full-iterate） | 1 次 |
| `loop_tick` | 1 次（advance → bugfind） |
| `executor_register` | 2 次（演示执行者） |
| `executor_auction` | 1 次 |
| `executor_route` | 1 次 |
| 源文件编辑 | 0 |

---

## 任务分配记录

| 动作 | 执行者 | 说明 |
|---|---|---|
| 组合环创建/推进 | 本人 | `r21-rule-layer-fix` 停在 bugfind 步 |
| 演示执行者登记 | 本人 | `exec-scan-rules` / `exec-verify-gate`（已持久化） |
| 能力拍卖 + 路由 | 本人 | 双机制收敛于 `exec-scan-rules` |
| BUG-348 落地 | **待派 `exec-scan-rules`** | 待 `src/server` 清空 |

---

## 遗留风险

1. **BUG-345/346/347/348 仍未修复**：`src/server` 37 脏 + 新增未跟踪 `src/server/bug335_ns_route_wbtest.mbt`，R14→R21 **八轮字节未变**。
2. 演示执行者登记已持久化，若不再使用可 `executor_clear` 或保留复用；不影响现网（`executor_route` 按 coverage 排序，coverage=0 的既有执行者不受影响）。
3. 组合环停在 bugfind 步，需落地时再 tick 推进。

---

## 后续建议

1. `src/server` 清空后：按 owner 裁决① + 本批（BUG-347→345→346→348）一次性落地，`moon test --target js` 全绿再 `bug_fix` 销账。
2. 若落地授权派单：`exec-scan-rules`（规则层修复）+ `exec-verify-gate`（验证门），或由指挥官人工指派。
3. 落地后 tick `r21-rule-layer-fix` 组合环推进到 `fix_and_merge` / `verify`，形成完整组合模式闭环。

---

## 超额内容

- 未改动任何源文件（严守并发边界）。
- 登记 2 个演示执行者（持久化）；未发布任务、未开自驱动命名空间。
- 组合环 `r21-rule-layer-fix` 为进程内注册态，重启即失（诚实标注）。

---

## 来源

- 本报告：`reports/2026-10-20-r21-combo-loop-and-auto-route-verify.md`
- 工具：`loop_create` / `loop_tick` / `executor_register` / `executor_auction` / `executor_route`
- 单一真源总目录：R19 `reports/2026-10-20-r19-issue-scan-rule-layer-catalog.md`
- 裁决固化：R19 追加段（owner 2026-10-21）