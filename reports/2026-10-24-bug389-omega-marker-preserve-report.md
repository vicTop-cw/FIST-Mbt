# BUG-389 修复报告 —— supervisor_task_upsert 保留 decomposer 结构标记

- 日期：2026-10-24
- 分支：`fix/omega-marker-preserve`（基点 `gitcode/main` = `d78e7dae`，最新主线）
- Commit：`4bf59fec`（fix）+ `dc3d6e45` / `029e4b3d`（diff-scope 声明，共 3 个 commit）
- 状态：已 push 到 `gitcode`（**未动主线**，`gitcode/main` 无任何写入）
- 终审人：lead（指挥官模式，金条八——独立实跑验证，不据子代理自述判绿）

## 结果摘要

按 BUG-389 立案的**修法方向①**落地：`supervisor_task_upsert` 在整体覆盖 `description` 时，先经
`preserve_plan_markers(old_desc, new_desc)` 把 decomposer 注入的结构标记做**缺失补回**，再落 `with_description`。
`[omega:required]` 不再被静默覆盖，`omega_spec_create` 不再把「标记丢失」误报成「用户没开 Omega 强验证」。

- 全仓 JS 测试：**`Total tests: 1456, passed: 1456, failed: 0.`**（基线 1451 + 新增 5，lead 独立复跑确认）
- 引擎包独立测试：**206/206**（基线 201 + 5）
- 格式门：`python scripts/check_fmt_gate.py` → **DEGRADED(2)**（BUG-388 工具链缺陷，拒判红也拒判绿，可接受）；`fist-gate.py` 在 warm 缓存下 rc=0
- `check_diff_scope.py`：**DIFFSCOPE=clean**（改动逐条落在声明内，含 `contract` 关键字处理 `.mbti`）
- 作用域严格：仅 5 个文件有真实内容变更，其余 `git status` 噪声全部为 CRLF churn（`--ignore-cr-at-eol` 后 0）

## 改动文件（5 个，真实内容变更 135 insertions / 10 deletions）

| 文件 | 变更 | 性质 |
|---|---|---|
| `src/engine/omega_strong.mbt` | 新增内部 `plan_markers() -> Array[String]` 作标记清单**单一真源**；`strip_plan_annotations` 复用（纯重构，行为不变）；新增 `pub fn preserve_plan_markers(old_desc, new_desc) -> String` | 核心修复 |
| `src/engine/engine_supervisor.mbt:422` | `with_description(item.description, now)` → `with_description(preserve_plan_markers(t.description, item.description), now)` | 接线 |
| `src/engine/omega_strong_test.mbt` | 新增 5 条锁：① omega 标记保留 ② 边界四问保留 ③ 无标记原样返回 ④ 已含不重复追加（幂等） ⑤ 端到端 upsert 后标记仍在、`omega_spec_create` 不被拦 | 白盒锁 |
| `src/engine/pkg.generated.mbti` | `moon info` 同步新公开 API `pub fn preserve_plan_markers(String, String) -> String` | moon info 惯例 |
| `docs/tasks/diff-scope-claims.txt` | 声明本分支作用域 `src/engine/* docs/tasks/* contract`（`.mbti` 命中契约面故带 `contract` 交审） | 过程面 |

## 核心实现

```moonbit
/// 合并 decomposer 注入的结构标记：新描述缺哪些，就把旧描述里的对应标记补回（BUG-389）。
/// 语义：对 plan_markers() 列出的标记面做「缺失补回」——若旧描述含某标记而新描述不含，
/// 则把该标记（连同其前导空格，omega_mark() 无前导空格）追加到新描述末尾。
pub fn preserve_plan_markers(old_desc : String, new_desc : String) -> String {
  let markers = plan_markers()
  let mut out = new_desc
  for m in markers {
    if not out.contains(m) {
      if old_desc.contains(m) {
        out = out + m
      }
    }
  }
  out
}
```

关键设计：`plan_markers()` 被 `strip_plan_annotations` 与 `preserve_plan_markers` 共用，**消除了两份清单漂移的风险**
（立案时点名过的隐患）。标记面与 `decompose_rec` 写入端一字不差（含前导空格）。

## 资源消耗

- 1 个实现子代理（`865f0ca7`）：落地代码 + 修两处编译错（`String.to_owned`、`items` 位置参数）+ 5 条测试 + `.mbti` 同步
- Lead 终审：独立复跑全仓测试、检查真实内容变更、补声明作用域、rebase 3 次跟上主线、核对平行分支去重

## 任务分配记录

| 阶段 | 角色 | 产出 |
|---|---|---|
| 方向①实现 | 子代理 865f0ca7 | commit `98316b97`（后经 rebase 变 `4bf59fec`） |
| 终审/作用域/去重/rebase | lead | 声明文件 2 个 commit，最终 rebase 至 `d78e7dae` |

## 遗留风险

1. **补回的是标记前缀而非完整标注文本**：如旧描述含 `" [边界四问:空输入/极值/非法输入/资源极限——须有用例或声明不适用]"`，
   补回的是前缀 `" [边界四问"`，描述尾会带一条未闭合的标记片段。`omega_enabled`（判 `[omega:required]`）与
   `strip_plan_annotations`（按同一清单 `cut_before`）都能正确识别，无功能影响；若需「整段原样搬回」得另改语义。
2. **平行分支去重（重要）**：仓库存在 3 个并行分支都在做 BUG-389：
   - `fix/omega-mark-keep`（`d91e077a`，2026-10-24 02:34）——修法①的窄版，仅保留 `[omega:required]`，内联在 `engine_supervisor.mbt`，无共享清单、无边界四问/难度梯度/父计划/spec 覆盖
   - `fix/omega-required-column`（`8bd46a56`，2026-10-24 06:15）——修法②，把门禁判据从 description 文本迁到 `tasks.omega_required` 元数据列（更彻底的架构解）
   - `fix/omega-marker-upsert-r38`（仅本地，未推送）
   - **本分支 `fix/omega-marker-preserve`**——修法①的完整版，单一真源清单 + 全标记面保留 + 5 条锁 + 端到端锁

   合并前必须先裁决。本分支比 `fix/omega-mark-keep` 严格更强（后者会被「描述里只写业务文本、缺边界四问」的路径漏掉）；
   与 `fix/omega-required-column` 是互补的两条路线（①治「标记丢失」，②治「描述可被覆盖」的根），不冲突但需择一或叠加。
3. **本机冷编译工具链**：`moon fmt --check` 在本 worktree 撞 BUG-388（`\\?\` ICE + `cannot hash`），
   `_build/wasm-gc/release/format/` 需先跑 `moon fmt` 预热才可判；`fist-gate.py` 因此首跑 DEGRADED(2)，预热后 rc=0。
   换新环境 / 清缓存后可能复现，`~/.moon-shim/shim.exe` 缺失时脚本提示但本次未撞 ICE。
4. **电池遗留 FAIL（全部与本次变更无关）**：在最新主线 `d78e7dae` 上逐一独立复跑确认，5 个 FAIL 全部是主线自身 / 工具链问题：
   - `check_selftest_call_face.py`：**主线上即红**（多脚本缺 main/run 调用面，与本分支无关）
   - `check_battery_count_doc.py` / `check_selftest_inventory_doc.py`：**主线上即 FATAL**（`run_guards --list` 缺面清单 `git_env.py`——`590129cf` 新加的 `git_env.py` 未登记进电池索引）
   - `check_slave_task_list.py`：主线自身文档/实现失配（D1 失配 3 条）
   - `fist-gate.py`：本 worktree 冷缓存导致首跑 DEGRADED，预热后 rc=0
   - `check_delivery_gap.py`：推分支后已自愈

   本分支的真实内容变更仅触及 `src/engine/*` + `pkg.generated.mbti` + `docs/tasks/diff-scope-claims.txt`，与上述判据的扫描面不相交。

## 后续建议

1. **立即**：请指挥官裁决 `fix/omega-marker-preserve`（完整修法①）与 `fix/omega-required-column`（修法②）的取舍，再决定 cherry-pick 哪一支入主线。
2. 若选修法①，`fix/omega-mark-keep` 与 `fix/omega-marker-upsert-r38` 可关闭（本分支为其超集）。
3. 若选修法②，则保留描述清洗面、但把 `omega_enabled` 判据迁到元数据列——两者可叠加（①防历史描述丢标记，②防未来覆盖）。
4. 账本 `memory/bugs.md` 的 BUG-389 走 `bug_fix` 盖章时请点名 commit `4bf59fec`（本分支最终 fix commit）。

## 来源

- BUG-389 账本条目：`memory/bugs.md:6580`
- 涉及源文件：`src/engine/omega_strong.mbt`、`src/engine/engine_supervisor.mbt`、`src/engine/omega_strong_test.mbt`
- 平行分支：`fix/omega-mark-keep`、`fix/omega-required-column`、`fix/omega-marker-upsert-r38`
- 相关工具链缺陷：BUG-388（fmt --check）、BUG-380（moon_test_env.py 入口）