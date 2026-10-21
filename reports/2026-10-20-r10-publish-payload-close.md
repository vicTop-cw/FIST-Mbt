# R10 · churn 下守卫清扫 + publish 载荷面收口

- 时间：2026-10-20 21:10 (+08:00)
- 范围：并发 WIP 加重（**216 脏**，src/server 37、全 src 树均 ` M`）下，做寻虫核查 + 守卫清扫 + **check_publish_payload P1 收口**
- 结论：**测试零回归（1347/1347）**；P1 红面从 **17 → 7**（本轮清掉 10 项）；`check_test_sync` 的 R3 防空转保持绿

## 结果摘要

| 项 | 结果 |
|---|---|
| 全量测试 `moon test --target js`（churn 216 下） | **1347/1347, failed 0, rc=0**（R9 → R10 复现，并发加重无回归） |
| `check_publish_payload` P1 | **17 → 7**（本轮清 10 项：9 份报告入库 + `_scratch/` 进 .gitignore） |
| `check_test_sync` R3 防空转 | ✅ 保持绿（R9 我同步的 AGENTS.md 存活） |
| `check_test_sync` R1/R2 | ⚠️ 仍红：131 份文档中 16 处声明 1346 ≠ 实测 1347（README/README_EN/README.mbt/ARCHITECTURE/agent-map/deliverable/scoring_rubric，全部并发 WIP） |
| `check_badge` | ⚠️ 仍红（README 徽章 1346 ≠ 1347，并发 WIP） |
| `check_tools_sync` R3b | ⚠️ 仍红（并发 agent 的 playbook 把 `model_route.dry_run` 分支误列为独立工具） |
| 寻虫核查 | `src/router/model_router.mbt:502-527` 的 string-index/possible-overflow 为**扫描器误报**（见下） |

## 寻虫核查：扫描器误报的判定依据

`issue_scan` 在 `src/router` 报 `string-index` + `possible-overflow`（`iso_to_secs`）：

- 实际代码在 **`cs.length() < 19` 早退**之后才做 `dig[k]` 下标（`digit_idx` 最大 18），`dig` 长度 == `cs` 长度 ≥ 19 ⇒ **越界不可能**；
- `dig` 元素来自 `c.to_int() - 48` 且经 `o >= 0 && o <= 9` 过滤为 0..9 ⇒ `dig[0]*1000 + …` 最大 9999，**Int32 内无溢出**；
- `dig[k] < 0` 已判非法字符，`y > 2037` 已钉 Y2038（BUG-218 遗留锁仍在）。
- **结论：不是 bug**。`issue_scan` 的 `string-index`/`possible-overflow`/`array-index-bounds` 规则是**子串近似**，不含控制流前置守卫信息 ⇒ 命中只作候选，必须人工读上下文复核（这正是 `boundary_probe` + 实跑验证的价值所在）。本轮 4 个目录共 3000+ 命中里，除本例外未发现真 bug。

## publish 载荷面收口（本轮主要工作量）

**根因**：`moon publish` 打包面 = 工作树 − `.gitignore`（不是 git 跟踪面，BUG-127）。并发开发期间产生大量未跟踪产物漏入载荷面，`check_publish_payload` 红面一度 **17 项 P1**。

**我做的（3 笔孤立提交，未混入任何并发 WIP）**：

1. `73fff3b` reports(R2~R9)：把 9 份本轮报告入库（`.gitignore` 是逐文件点名策略，reports/ 已有 419 个被跟踪历史报告 ⇒ 入库是正确修法，不是 ignore）—— 清 9 项 P1。
2. `c0a5fce` gitignore(R10)：`/_scratch/` 整目录挡（含 4.1MB `fist_all.json` dump，属临时工作目录）—— 清 1 项 P1。
3. `4a88a2b` docs(AGENTS)：测试数声明 1346→1347（diff 仅 2 行，无并发混入）—— 让 R9 的修正**持久化**。

**剩余 7 项 P1 全部归属并发/generated 产物（我不动，等其作者入库）**：

| 文件 | 归属 | 建议修法 |
|---|---|---|
| `cmd/commissar/pkg.generated.mbti` | 并发新增包 | 入库（.mbti 本就是跟踪面） |
| `src/evidence/pkg.generated.mbti` | 并发新增包 | 入库 |
| `src/ops/rhop_native.mbt` | 并发新增文件 | 入库 |
| `src/server/bug335_ns_route_wbtest.mbt` | 并发新增测试 | 入库 |
| `memory/archive/thinking.archive.md` | memory_gc 归档输出 | 入库或点名 ignore |
| `memory/bug333_denoise_rules.json` | BUG-333 降噪规则语料（被并发 R46 报告引用） | 入库 |
| `publish_sigma.js` | 未知归属脚本 | 作者判定入库/ignore |

## 关键证据

```
$ git status --porcelain            → 216 项脏（并发 WIP 加重）
$ moon test --target js             → Total tests: 1347, passed: 1347, failed: 0.
$ python scripts/check_publish_payload.py
    前置：VIOLATION P1 × 17
    入库 9 报告后：VIOLATION P1 × 8
    加 _scratch/ ignore 后：VIOLATION P1 × 7
$ python scripts/check_test_sync.py temp/moon_test_r10.log → R3 防空转绿，R1/R2 报 16 处 1346
$ git log --oneline -3              → 4a88a2b / c0a5fce / 73fff3b
```

## 资源消耗

- `moon test --target js` 全量 ×1（后台）；守卫脚本 `check_publish_payload`×2 / `check_test_sync` / `check_badge` / `check_tools_sync` 各 ×1
- `issue_scan` ×4 目录（src/store、src/engine、src/router、src/display）
- 提交 3 笔，共 12 文件（9 reports + 1 .gitignore + 1 AGENTS.md），全部为我的孤立文件

## 遗留风险

1. **16 处文档 1346 声明 + README 徽章 1346** —— 全部在并发 WIP 文档里（README/README_EN/README.mbt/ARCHITECTURE/agent-map/deliverable/scoring_rubric），等并发收口后一次性同步 1347。我已把**干净的** AGENTS.md 同步并提交（R9→R10 持久化）。
2. **7 项 publish P1 未清** —— 归属并发/generated 产物，需各自作者入库；CI 的 `check_publish_payload` 会在 `moon publish` 前兜底。
3. `check_tools_sync` R3b 仍红（并发 agent 的 playbook 工具声明错误）。

## 后续建议

- R11 若 `src/server` 仍未清：继续只做「无冲突面」守卫清扫 + 让并发 agent 完成 7 项 P1 入库；若已清：恢复 BUG-333 ①（`--min-severity`）、③、BUG-327 part 2、BUG-238 server 层收尾。
- 建议并发 agent 优先入库 `src/ops/rhop_native.mbt` / `src/server/bug335_ns_route_wbtest.mbt` / 2 个未跟踪 `.mbti`（这 4 项是 P1 且是它们的直接产物）。

## 来源

- 全部读数来自本机实测（`moon`、守卫脚本、`git status` / `git diff` / `git log`）；扫描器结论经 `src/router/model_router.mbt` 源码上下文复核。
