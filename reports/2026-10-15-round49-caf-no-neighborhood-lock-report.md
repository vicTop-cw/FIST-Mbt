# Goal-2 Round 49 报告：标准 1 无邻域保留原始顺序真源锁

- **日期**：2026-10-15
- **提交**：R49 code（`src/router/router_caf_replay_distinct_test.mbt` 追加 `caf_c1_6`，纯测试，HEAD `c664612`）
- **状态**：标准 1 排列性质**三分支锁齐**（都在邻域 caf_c1_4 / 混合 caf_c1_5 / 无邻域 caf_c1_6）；接线仍 `4/9`（连续 12 轮 R38-R49）

## 结果摘要

### 标准 1 排列性质三分支锁齐

`caf_soft_reorder` 的三分支（`src/router/router_caf.mbt` L361-417）：

| 分支 | 行为 | 排列性质 | 锁 |
|---|---|---|---|
| 候选**都在邻域** + rate 互异 | rate 降序 | 置换不变 | **caf_c1_4**（R47） |
| **混合**（部分在邻域、部分不在） | 邻域内优先，邻域外恒排后 | 置换不变 | **caf_c1_5**（R48） |
| **都不在邻域** | 保留原始顺序 | **恒等映射** reorder(x)==x | **caf_c1_6**（R49） |

**caf_c1_6 关键语义**：此分支的排列性质**不是**「置换不变」（不同输入 → 不同输出），而是
**恒等映射**（reorder 输出 == 输入）。因为候选都无依据时系统不该自作主张重排，应把决策
交还确定性路由的原始顺序。**锁法**：断言 reorder 输出 == 输入（逐位置），并测反向输入 +
单元素候选边界。

至此**标准 1 排列性质全分支锁齐**，`docs/2026-10-15-fist-mbt-caf-acceptance-status.md` L32 的
「排序结果对候选集置换保持不变」声明三分支各有真源锁钉死。

### 写盘坑：caf_c1_6 四次写入三次失败（R49 新坑，R48 教训深化）

**caf_c1_6 写盘时间线**：
1. `Add-Content` → 显示成功，文件未变（静默失败）
2. `edit` 工具 → 返回成功，文件未变（静默失败）
3. `StreamWriter` 绝对路径 → 显示成功，文件未变（静默失败）
4. **清理工作区（提交 fmt 改动）后 StreamWriter 绝对路径 → 立即验证命中行 248，成功**

**根因假设**：**工作区脏（moon fmt 21+4- 未提交的改动）时，写入被 moon fmt 后台 watch 覆盖**。
R48 的 caf_c1_5 成功（工作区当时干净），R49 的 caf_c1_6 前三次失败（工作区被我的 fmt 重排
caf_c1_5 弄脏）。**清工作区后 StreamWriter 立即成功** —— 强佐证。

**教训**：写文件前先确保工作区干净（`git status` 空/仅目标文件），写后**立即 grep 验证**
（不依赖工具返回「成功」）。

### 接线阻塞确认（连续 12 轮）

`model_router_ops.mbt` 仍 `4/9`（R38-R49）。并发 agent 本轮修 **BUG-224**（`github_flush_execute`
bug_ids 越界 panic + flush_plan 排除空 bug_id），`5eddc18` docs 登记。非 BUG-185/186/217。

### 全仓区间寻虫收尾（R48 延续）

R48 已判定全仓 9 处 `for x in N..<=M` 都是有意闭区间 DP（表尺寸 N+1）。R49 无新发现。

## 验证

- router **202/202**（R48 201 + caf_c1_6），0 failed
- 全仓 **1214/1214**（HEAD 755bd7c 的 1212 + caf_c1_6 + 并发 1），0 failed
- `.mbti` 无变化（纯测试追加，无新 pub fn）
- `moon fmt` 通过（caf_c1_6 fmt 后仍存活，文件 276 行）
- 改动范围：`57+3-`（caf_c1_6 追加 + moon fmt 重排 caf_c1_5 的 abort 多行）

## 资源消耗

查并发 WIP 面（model_router_ops 4/9 / bugreport 8/2 / router_caf 5/1 / ops_hats 8/8 全 WIP）/
**caf_c1_6 三次写盘失败**（Add-Content + edit + StreamWriter）/ 提交 fmt 改动清工作区 /
**StreamWriter 第四次成功**（立即验证）/ `moon fmt` + `moon test --target js src/router`（202/202）/
全仓回归（1214/1214）/ `git commit`（path-scoped ×1）

## 任务分配记录

本轮**无任务分配**。本人在 router 域独立推进，改动只落 `src/router/router_caf_replay_distinct_test.mbt`
（`model_router_ops.mbt`/`router_caf.mbt`/`bugreport.mbt`/`bugreport_status_wbtest.mbt`/`ops_hats.mbt`
均 WIP/并发已避开；`.mbti` 未动证实）。

## 遗留风险

- **§2.3 server 接线仍未做**（`model_router_ops.mbt` 4/9，连续 12 轮）。接线前置四契约齐备 + 标准 1/2/3/4 真源锁齐备。
- **标准 1 已三分支锁齐**（caf_c1_4/5/6），但 **tie（rate 相同）场景的排列性质** 未锁（R13 已锁 FIFO 稳定）。
- **标准 2 的接线后端到端复验**仍待接线完成。
- **标准 3 的 server 层 dry_run 零副作用锁**仍待接线。
- **并发 WIP 面持续**：BUG-223/224 已修复，但 `bugreport.mbt` 仍 8/2、`router_caf.mbt` 仍 5/1。
- **写盘工具链**：工作区脏时写文件可能被覆盖，必须先清工作区再写。

## 后续建议

1. **R50 首选**：§2.3 接线（`model_router_ops.mbt` 释放后）。四契约 + JSON 层 + 标准 1/2/4 锁齐备，接线照抄。
2. **R50 备选**：标准 1 **tie 场景排列性质锁**（caf_c1_7：rate 相同模型置换候选集，FIFO 稳定但顺序可能变 —— 需明确「tie 不保证置换不变」的文档化边界）。
3. **R50 备选 2**：标准 2 接线后端到端复验（接线完成前提）。
4. **R50 备选 3**：标准 3 server 层 dry_run 零副作用锁（接线后）。

## 来源

- `docs/2026-10-15-fist-mbt-caf-acceptance-status.md` L32（标准 1 排列性质声明）
- `src/router/router_caf.mbt` `caf_soft_reorder`（L361-417 无邻域分支）
- 新增锁：`src/router/router_caf_replay_distinct_test.mbt` `caf_c1_6_无邻域保留原始顺序`
