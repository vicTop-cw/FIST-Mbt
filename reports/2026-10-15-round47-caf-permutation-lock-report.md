# Goal-2 Round 47 报告：标准 1 候选集置换不变真源锁

- **日期**：2026-10-15
- **提交**：R47 code（`src/router/router_caf_replay_distinct_test.mbt` 追加 `caf_c1_4`，纯测试，HEAD `70fc711`）
- **状态**：§2.3 server 接线仍阻塞（连续 10 轮）；本轮补齐 CAF 验收标准 1 的**候选集置换不变**真源锁

## 结果摘要

### 接线阻塞确认

`model_router_ops.mbt` 仍 `4/9`（连续 10 轮 R38-R47）。并发 agent 新增 2 个未跟踪脚本
`scripts/fix_router_caf.py` / `fix_router_caf2.py`（`??` 态，推断在补 `router_caf.mbt` 的实现缺陷）。

### 新发现：标准 1「候选集置换不变」未锁

`docs/2026-10-15-fist-mbt-caf-acceptance-status.md` L32 明确声明标准 1 的三条关键断言：
1. 简单任务 Top-1 = `m_free`
2. 复杂任务 Top-1 = `m_premium`
3. **排列性质：排序结果对候选集置换保持不变**

`caf_c1_1/2/3` 锁了 1/2/3（上下文区分度），**未锁第 3 条排列性质**。若 `caf_soft_reorder`
依赖输入顺序（如数组下标隐式参与排序），置换候选集会让回放优先级漂移 → 标准 1「离线回放可复现」违约。

### 实质产出：caf_c1_4 候选集置换不变锁

补 `caf_c1_4_候选集置换不变`：

- 用 `c1_mem()`（m_free rate 0.667 + m_premium rate 1.0，**rate 互不相同 → 无 tie**）
- 两个置换候选集：`[m_free, m_premium]` vs `[m_premium, m_free]`
- 断言：
  1. `caf_soft_reorder` 首位恒为 rate 1.0 的 `m_premium`（与输入顺序无关）
  2. **完整序列逐位置一致**（base[i] == perm[i]）

**边界说明**：排列性质只在**无 tie** 时成立（tie 时按原始位置稳定序，R13 `caf_soft_reorder_tie_stable`
已锁 FIFO，不在本锁范围）。

### 调试发现：MoonBit 区间语法坑（真 bug 定位）

首次实现 caf_c1_4 用 `for i in 0..<=2`，**caf_c1_4 失败**（`router.blackbox_test.js` panic）。

**诊断过程**：
1. 加临时诊断 `tmp_diag_perm` 打印 `caf_soft_reorder` 两个置换的实际结果 → 结果**完全一致**（`[m_premium, m_free]`）
2. 说明**排列性质成立**，失败不在 reorder 结果
3. 逐条排查断言 → 定位到 `for i in 0..<=2` 遍历 0,1,**2** 共 3 次 → 第 3 次 `r_base[2]` **数组越界 panic**

**MoonBit 区间语义**：
- `0..<2` = 半开区间 [0, 2)，遍历 0,1
- `0..=2` / `0..<=2` = **闭区间 [0, 2]，含 2**，遍历 0,1,2
- moon fmt 把 `0..2` 规范化为 `0..<=2`（闭区间）→ 遍历含 2 → 越界

**修复**：`for i in 0..<r_base.length()`（半开，动态长度）。

**为何重要**：这是 MoonBit 与多数语言（Rust/Python 的 `range(len)` 排他）**不一致**的坑。
写循环遍历数组时若用闭区间 `0..<=len` 会越界 panic；必须 `0..<len`。

### 并发观察

并发 agent 本轮推进：`model_router_ops.mbt`（4/9）、`router_caf.mbt`（WIP，新增 fix_router_caf*.py）、
`bugreport.mbt`（8/2）、`ops_hats.mbt`（六顶帽）。**均不越界**。

## 验证

- router **200/200**（R46 199 + caf_c1_4），0 failed
- 全仓 **1210/1210**（R46 1209 + 1），0 failed
- `.mbti` 无变化（纯测试追加，无新 pub fn）
- `moon fmt --check` 通过
- 改动范围：`46+ 0-`（纯追加，仅 caf_c1_4）

## 资源消耗

`git diff --numstat`（接线释放探测）/ `read` CAF 验收状态标准 1 断言 /
`grep caf_c1 锁清单`（确认区分度锁已有，排列性质未锁）/ 加锁 / **加临时诊断 `tmp_diag_perm` 定位越界** /
删诊断 / `edit` 修 `0..<2` / `moon fmt` + `moon test --target js src/router` / 全仓回归 / `git commit`（path-scoped ×1）

## 任务分配记录

本轮**无任务分配**。本人在 router 域独立推进，改动只落 `src/router/router_caf_replay_distinct_test.mbt`
（`router_caf.mbt`/`model_router_ops.mbt`/`bugreport.mbt`/`ops_hats.mbt`/`scripts/fix_router_caf*.py` 均 WIP/并发已避开；`.mbti` 未动证实）。

## 遗留风险

- **§2.3 server 接线仍未做**（`model_router_ops.mbt` 4/9，连续 10 轮）。接线前置四契约齐备 + 标准 3 JSON 层就绪 + 标准 1/2/4 真源锁齐备，接线成本已最小化。
- **标准 2 的接线后端到端复验**仍待接线完成（R46 只闭合纯计算侧）。
- **标准 1 的 Python 脚本 `scripts/caf_offline_replay.py`**：断言 1/2 已由 caf_c1_1/2 真源锁，断言 3 已由 caf_c1_4 真源锁 → 标准 1 真源侧闭合。
- **并发 WIP 面持续扩大**：新增 `scripts/fix_router_caf*.py`（推断在补 `router_caf.mbt` 实现缺陷），可动域收窄。
- **BUG-185/186/217 重复条目**：`bugreport.mbt` WIP（并发在修），不越界。

## 后续建议

1. **R48 首选**：§2.3 接线（`model_router_ops.mbt` 释放后）。四契约 + JSON 层 + 标准 1/2/4 锁齐备，接线照抄。
2. **R48 备选**：标准 2 的接线后端到端复验（接线完成前提）。
3. **R48 备选 2**：标准 3 的 dry_run 真源锁——`pick_caf_dry_run` + `caf_dry_run_to_json` 已落地（R29/R37），但**未锁「dry_run 零副作用」在 server 层**（caf_dry_1 已锁纯计算侧；server 层需接线后才能锁）。
4. **持续观察**：并发收口 `model_router_ops.mbt` / `router_caf.mbt` → 立即实施接线。

## 来源

- `docs/2026-10-15-fist-mbt-caf-acceptance-status.md` L32（标准 1 排列性质声明未锁）
- `src/router/router_caf.mbt` `caf_soft_reorder`（邻域内 rate 降序 → cost 升序 → 稳定序）
- 新增锁：`src/router/router_caf_replay_distinct_test.mbt` `caf_c1_4_候选集置换不变`
- 参考：`src/router/router_caf_replay_distinct_test.mbt` `c1_mem`（R40 构造方式复用）
