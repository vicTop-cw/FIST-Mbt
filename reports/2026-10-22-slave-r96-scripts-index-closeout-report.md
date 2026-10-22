# 2026-10-22 副机 R96 汇报 —— scripts/README 登记收口（main 的索引门转绿）

## 结果摘要

- **目标**：`check_scripts_index.py` 是 `ci.yml:117` 上无豁免的一步，而 main 上有几份脚本从没登记进
  `scripts/README.md` ⇒ **共享线的 CI 从它们落仓那天起一直红着**，每条 MR 都顶着同一格假红看不了自己的真读数。
- **交付**（分支 `slave/docs/scripts-index-closeout-r96`，基点 `gitcode/main 99bacbe`，叠在 R95 的 `938837b` 之后）：
  1. 补登记 **三把尺**：`fist-gate.py` / `fist-pr-automator.py` / `check_bug_refs.py` —— 每条带 rc 契约，
     并点名「登记 ≠ 选边/背书」（`fist-pr-automator.py` 默认 `merge` 撞金条四 → TASK-021；
     `check_bug_refs.py` 三处硬伤归 peer `484aced` → TASK-020）。
  2. `whisperer.py` 一条**降级为追记**：中途 main 前进（`d8deed8 → 99bacbe`），主机自己把它登记了，
     且把旗标 `--self-test` / `--selftest` 收进同一 dest。本支取 main 的条目正文，只补它没写的两件事实：
     Step 0 `reset --hard` + `push --force` 的危险面与 `run_guards.EXCLUDE_EXACT` 接线、`whisperer_patrol.py` 双活解（TASK-019）。
  3. 清掉 **4 行互斥的同名重复读数**：`run_guards.py` 曾同时挂 4 条自述互不相同的条目（24 把尺/34 格失败 2、
     24 把尺/35 格、26 把尺/38 格 ×2 逐字相同），`check_bug_reference_integrity.py` 挂 2 条逐字相同；
     `check_scripts_index` 只查「名字在不在」，重复与互斥读数一律放过 —— 这就是「同一工具多份历史读数并存」能躺在索引里没人管的机理。
  4. **废止 README 自己的旧口径**：原表「无前缀 = 正式、可复用工具」与 Golden Rule 第 3 条「正式工具：无前缀 + docstring + 退出码」
     同 TASK-008 立案判据（「看文件名猜不出它是门禁还是工具」）自相矛盾 ⇒ 两处改为「角色必须写在名字两端之一，见 `NAMING.md`，
     由 `check_scripts_naming.py` 钉棘轮」，旧口径留在原行内标「R96 废止」以免再被抄回。
- **本单未动任何 `.mbt`**：开工时工作树里 `src/router/router_state.mbt` + `model_router_wbtest.mbt` 带着 18 行
  重复 `use_caf_memory:` 字段（struct literal 同字段两次 = 编译期错，diff 只有增行、零删行，形状是一次瞄歪的批量替换）
  ⇒ 已 `git checkout --` 还原，不属于本单改动面。

## 资源消耗

- 会话内本轮消耗：约 1 个上下文窗口（含一次压缩续推）、goal 计数 22/40 轮次段内完成；命令面约 15 次
  （fetch / merge-tree 试算 / 两次 rebase 冲突解 / 六把守卫尺复跑 / 提交与推送）。
- 无 LLM 侧成本记账（本仓 `cost_stats` 只记 MCP 调用面，本轮未走 MCP 派单）。

## 任务分配记录

| 单 | 承接 | 状态 |
|---|---|---|
| TASK-007 收口（scripts 索引登记面） | 副机（本单，指挥官模式下的轻任务：单文件文档 + 一次 rebase） | 已交付并推送 |
| TASK-020（两把 bug-ref 尺并存） | 入池待 owner 裁 | 只登记、不选边 |
| TASK-021（`fist-pr-automator.py` 默认 merge 撞金条四） | 入池待 owner 裁 | 只登记现状、不背书 |
| TASK-019（whisperer 双活解） | 入池待 owner 裁 | 追记点名危险面 |

## 遗留风险

1. **`check_doc_surface.py` 仍 rc=1**（预存红，非本单引入）：`USAGE.md` 自述 0.3.9 ≠ `moon.mod` 0.3.10。
   我在 `slave/integrate/r93-on-cef1e9c-r94` 已修为 0.3.10；本分支刻意不重复修 —— 交 owner 按合序取一份。
2. **本支含 R95 的重放提交**（`938837b` = 原 `bcdd393` rebase 后的新哈希）：R95 的旧 MR 面与这一份是同一内容两个哈希，
   合序时只能取一条，否则重复登记 `NAMING.md` / `check_scripts_naming.py`。
3. **README 尾节是三个「同日追加」叠出来的**（主机 R70 段 + 我的 R95/R96 段）：下次谁再往文件尾追加，仍会撞同一处。
   根治办法是把登记改成按脚本名分节、不让追加位置携带语义 —— 属 TASK-008 第二批面，本单不做。
4. **登记数量本身仍是散文**：README 里「三件/四件」这类计数写在正文，而 `check_scripts_index` 只查名字在不在，
   不查计数 —— 写死的数字就是下一颗漂移雷（本仓已为同类问题返工过一次）。

## 后续建议

- 合序建议：**R95 → R96 → r94**（r94 的 `USAGE.md` 一行随它自己那条 MR 走，不要在本单里替它合）。
- 下一单值得做的面：把 `check_scripts_index` 从「名字在不在」升级到「同名条目唯一 + 同名条目读数不互斥」——
  本单清掉的那 4 行正是它当前看不见的那一类。判据形态已想清楚：按行首反引号名分组，组内 >1 条即红，
  并配一支「散文引子形如条目」的反向对照（本单实测到过这个假阳形状）。
- `fist-gate.py` / `fist-pr-automator.py` 的 N1+N2 双债改名，建议与 CI 步骤名同批改，别分两次动引用面。

## 超额内容

- 本单正文只该登记 + 清重复，实际还做了：README 自身旧口径废止（与 NAMING.md 对立必修，否则两份词法并存）；
  一次整支 rebase 到新 main 并手工解两处冲突（fetch 纪律要求，非本单范围）；
  还原两份被误改的 `.mbt`（工作树卫生，非本单范围）。
- 未做：`moon test`（本单无源码面，跑它不产生对本单有意义的证据）。

## 来源

- 分支 `slave/docs/scripts-index-closeout-r96`：`938837b`（R95，rebase 重放）+ `3115636`（本单）。
- 真源读数（rebase 后复跑，非首稿）：`check_scripts_index` rc=0（目标格）；`run_guards --selftest` OK 13 格，
  现状 89 把尺 / CI 面 29 / 电池面 89 / 缺面 0；`check_scripts_naming` PASS N1 16/16 + N2 4/4；
  `check_py_stdout_encoding --all` 89/89（另 1 份纯 ASCII 出 E2 预告，不红）；
  `blackbox/check_merge_markers` PASS 1239 份跟踪文件；`whisperer.py --selftest` rc=0（G1/G2 双过）。
- 撞车取证：`git merge-tree --write-tree gitcode/main <本支>` 在 rebase 前给出 `memory/2026-10-22.md` add/add +
  `scripts/README.md` 尾节冲突；`git ls-tree 99bacbe` 与 `git show 99bacbe:scripts/README.md` 证明 main 已含
  `whisperer.py` 登记与旗标修复。
- 日志面：`memory/2026-10-22.md` 的「R96」一节（含我踩到的两格：R95 没 grep 既有命名表就立 `NAMING.md`；
  没先 fetch 就把别人昨夜修掉的旗标当现状登记）。
