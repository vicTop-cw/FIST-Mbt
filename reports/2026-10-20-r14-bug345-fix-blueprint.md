# R14 组合模式 · BUG-345 修复蓝本（drop-in 就绪，待 src/server 清空即落）

- 日期：2026-10-20
- 轮次：R14 / 256（目标 ACTIVE）
- 类型：fix（蓝本，非落地 —— `src/server/issue_scan.mbt` 与 `issue_scan_wbtest.mbt` 均为并发 WIP 脏文件，禁写）
- 结论：**BUG-345 根因 + 修复点已逐行锁定，蓝本设计为可 wbtest 化的最小补丁**；`issue_scan_wbtest.mbt` **当前不存在任何 denoise 锁**（grep `denoise|by_severity|BUG-333|bug333` 零命中）—— BUG-333 ③ 承诺的「默认降噪锁」在白盒层**缺席**，蓝本一并补齐。

## 1. 并发/账本现状（R14 实测）

- 工作树脏 **205**；`src/server` 脏 **37**（含 `issue_scan.mbt`、`issue_scan_wbtest.mbt`）
- 注：`git status --porcelain -- src/server` 曾返回空 —— 该 pathspec 存在歧义，**全量 `git status --porcelain | Select-String src/server` = 37** 才是权威读数；判据脚本不得依赖目录 pathspec 计数。
- 账本 `memory/bugs.md`：**345 条**，FIXED 306 / DUPLICATE 10 / FALSE_POSITIVE 12 / **OPEN 17**，`open_with_linked_done = 0`（无账本↔任务库矛盾）
- OPEN 中归属 fist-mbt 且归我的 3 条：**BUG-327**（ocr_scan unsupported_ext，server 层）、**BUG-333**（issue_scan 降噪，server 层）、**BUG-345**（by_severity info→low，server 层）—— **全部需要 `src/server` 编辑 ⇒ 全部阻塞**
- 其余 14 条 OPEN（BUG-242/255/258/259/273/274/275/276/321/324/325/339/341/344）分属 Pentad/Tnr/codegen 等并发项目或并发 agent 域，非本次修复范围

## 2. BUG-345 根因（逐行复核，`src/server/issue_scan.mbt`）

聚合块 L1962-2011：

```moonbit
let dedup = guarded_filtered
let mut high = 0
let mut medium = 0
let mut low = 0                     // ← 无 info 计数器
for h in dedup {
  if h.severity == "high"      { high = high + 1 }
  else if h.severity == "medium" { medium = medium + 1 }
  else                           { low = low + 1 }   // ← BUG-345：info 落入 low
  rule_counts.set(h.rule, rule_counts.get(h.rule).unwrap_or(0) + 1)
}
// ...
"by_severity": Json::object({
  "high":   Json::number(high.to_double()),
  "medium": Json::number(medium.to_double()),
  "low":    Json::number(low.to_double()),          // ← 无 info 键
}),
```

**缺陷**：`else → low` 兜底把 `severity=="info"` 的命中并入 `low` 桶，`by_severity` 结构上不暴露 info。而 `by_rule`（L1987）用的是 `r.severity`（规则表档），因此出现「`by_rule` 显示 info、`by_severity` 显示 low」的同参撕裂 —— R12 A/B 实测 `src/ltl` 三条降噪规则 severity 从 low→info 后，`by_severity.low` **一字不变（69）**。

**影响**：BUG-333 降噪预案的核心价值（「降 severity 为 info 后，按 severity 过滤/判读变干净」）在 `by_severity` 层**无法兑现**；扫描结果仍不可判读。

## 3. 修复蓝本（drop-in）

### 3.1 主补丁（`src/server/issue_scan.mbt` 聚合块）

**A. 抽纯函数（让聚合可白盒测）** —— 新加，置于聚合块前：

```moonbit
///| 严重度分桶（BUG-345）：把命中严重度归入 high/medium/low/info 四桶，
///| 未知值一律视为 info（不吞进 low）。
fn severity_bucket(sev : String) -> String {
  if sev == "high" { return "high" }
  if sev == "medium" { return "medium" }
  if sev == "low" { return "low" }
  "info"
}
```

**B. 改聚合计数**（替换 L1964-1976 的 if/else 链）：

```moonbit
let mut high = 0
let mut medium = 0
let mut low = 0
let mut info = 0
for h in dedup {
  match severity_bucket(h.severity) {
    "high"   => high = high + 1
    "medium" => medium = medium + 1
    "low"    => low = low + 1
    _        => info = info + 1
  }
  rule_counts.set(h.rule, rule_counts.get(h.rule).unwrap_or(0) + 1)
}
```

**C. 改 by_severity 输出**（替换 L2007-2011）：

```moonbit
"by_severity": Json::object({
  "high":   Json::number(high.to_double()),
  "medium": Json::number(medium.to_double()),
  "low":    Json::number(low.to_double()),
  "info":   Json::number(info.to_double()),
}),
```

> 兼容性：新增 `info` 键为**纯增量**（原调用方读 high/medium/low 不受影响）；`total_findings` 与 `by_rule` 口径不变。零破坏。

### 3.2 白盒锁（`src/server/issue_scan_wbtest.mbt`，当前该文件 denoise 锁**缺席**）

新增 `severity_bucket` 四桶穷举锁 + 降噪守恒锁：

```moonbit
test "BUG-345 severity_bucket 四桶穷举（含未知值兜底）" {
  if severity_bucket("high") != "high" { abort("high") }
  if severity_bucket("medium") != "medium" { abort("medium") }
  if severity_bucket("low") != "low" { abort("low") }
  if severity_bucket("info") != "info" { abort("info") }
  if severity_bucket("critical") != "info" { abort("未知值应落入 info，不得落 low") }
  if severity_bucket("") != "info" { abort("空串应落入 info") }
}
```

### 3.3 A/B 守恒判据（常驻守卫，防回归）

**归属 `scripts/`**（待该目录并发 WIP 清空后加入，否则先不入库以免提交红守卫）。

逻辑（CLI 级，跑真产物 `node cli.js issue_scan` 或经 MCP 回读）：
1. `A = issue_scan(src/ltl)`（默认 rules）→ 记 `low_A`、`has_info_A`
2. `B = issue_scan(src/ltl, rules_file=memory/bug333_denoise_rules.json)` → 记 `low_B`、`has_info_B`
3. 断言（违反任一即 exit 1）：
   - `has_info_B == true`（`info` 键存在）—— 修 BUG-345 的直接证据
   - `low_B < low_A`（降噪后 low 严格下降）—— BUG-333 价值兑现
   - `low_A == low_B` ⇒ 判定「降噪未生效」且 exit 1 —— 锁住 R12 复现的回归
4. `--selftest` 提供已知基线（A: low=69；B: low=19, info=50 —— 以修复落地后的实测为准回填）。

> 该守卫在 BUG-345 未修前**必然红**（`has_info_B==false`），故**先修主补丁再入守卫**，避免 CI 常红。

## 4. 为什么先修 BUG-345、再修 BUG-333 ①③

BUG-333 的①②③（默认 severity→info / 白盒锁 / A/B 判据）在 `by_severity` 未分桶前**结构性不成立**：把命中 severity 降为 info 只改标签，桶不变。修 345 是 333 全部子项价值兑现的**前置条件**。落地顺序：

```
① 主补丁 severity_bucket + by_severity 加 info   （BUG-345）
② wbtest 四桶穷举锁 + 降噪守恒锁                  （BUG-333③ / 345 白盒）
③ A/B 判据脚本入 scripts/ + 回填基线             （BUG-333③ 常驻）
④ --min-severity 过滤参数（按四桶过滤 findings）  （BUG-333①）
```

## 5. 资源消耗
- 调用：`pwsh`（git 状态 ×3）、`bug_list`、`list`、`store_list`、`grep`、`read` ×2
- 新增 commit：待写（蓝本入库后）
- 未改任何 `src/*`，未 `git add -A`

## 6. 遗留风险
1. BUG-327/333/345 三项修复**全部依赖 `src/server` 清空**；当前 37 脏且近期无并发 commit（`git log` 顶部 8 条全是我自己的报告 commit），预计仍需等待。
2. `src/server` 目录 pathspec 计数不可靠（见 §1），任何判据必须用全量 porcelain 过滤。
3. 修复后需跑 `moon test --target js` 全量验证（权威门槛 1347/1347，`Total tests: N, passed: N, failed: 0` 为准，不看 exit 0——BUG-142）。

## 7. 后续建议
- `src/server` 清空窗口打开时，按 §3 顺序一次落地 ①→②（源码 + 白盒锁同批，`moon fmt` 后 `moon test --target js`），再补 ③④。
- 落地后回填 `memory/bugs.md`（`bug_fix` 带 evidence：改了 `severity_bucket` + `by_severity` 四桶 + wbtest 两锁），一次一笔销账。

## 来源
- `src/server/issue_scan.mbt` L1962-2011（BUG-345 根因，读源逐行）
- `src/server/issue_scan_wbtest.mbt`（grep `denoise|by_severity|BUG-333|bug333` 零命中 ⇒ 降噪锁缺席）
- `memory/bugs.md`（`bug_list`，345 条，OPEN 17，open_with_linked_done=0）
- R12 报告（A/B 实测基线 low=69）
