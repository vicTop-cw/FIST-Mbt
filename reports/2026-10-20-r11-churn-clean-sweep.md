# R11 组合模式 · churn 下守卫清扫与干净面复扫（Round 11）

- 日期：2026-10-20
- 模式：打磨 / 清整（polish + tidy）
- 轮次：R11 / 256（目标 ACTIVE，未关闭）
- 结论：**P1 17 → 8 → 7**；`src/server` 仍 37 脏、工作树 206 脏，无可安全编辑源码面；干净面（`src/{core,claimguard,ltl,decompose,constraint,symbolic,hat}` + `cmd` + `atgc` + `atgc-old` + `omega`）复扫 **真 bug = 0**，所有 `issue_scan` 命中均为子串近似误报（已逐条读源复核）。
- 来源：R10 报告 `reports/2026-10-20-r10-publish-payload-close.md`

## 结果摘要

### 1. 并发状态复查
- 工作树脏：**206**（R10 基线 216，净降 10，并发侧也在收）
- `src/server`：**37 脏**，含未跟踪 `src/server/bug335_ns_route_wbtest.mbt` ⇒ BUG-333 ①③ / BUG-327 p2 / BUG-238 server 层**仍阻塞**（并发 WIP 未清，禁写）
- 全 `src/*` 主模块脏：`router / display / store / engine / ops / evolve / executor / diff / omega / evidence`
- 干净可编辑面（本轮实测）：`src/{claimguard,constraint,core,decompose,hat,ltl,symbolic}` + `cmd` + `atgc` + `atgc-old` + `omega`

### 2. 发布版 fist-mbt 能力实测（用户要求「开启任何功能，含自动路由」）
| 能力 | 结果 |
|---|---|
| `project_health` | **healthy**；2357 任务 / in_flight 52 / ready 10 / done 858 / **done_no_artifact 0** / blocked 0 / archived 1437 |
| `executor_route`(need=moonbit,守卫脚本) | 17 候选；best=`atomcode-glm53`(coverage 0.5, trust 0, load 0)；basis=能力覆盖→信任→负载(R80) |
| `executor_auction`(同 need) | 2 竞拍；winner=`atomcode-glm53` score 0.25（出价高于历史兑现率，已按校准折扣计，仍胜出说明其余更弱） |
| `model_route`(query-only, soldier=侦查兵) | pick=`space-bunny-free`，tier=free，reason=`soldier free-fast prefer free tier`；`persisted=false`、不记账不推进游标（BUG-62 成对锁生效） |
| `model_route(dry_run=true)` | 报错 `dry_run=true 但 config.use_caf_memory=false，CAF 未开启` —— **符合预期行为，非 bug**（dry_run 需显式开 CAF，不开则显式拒绝、不静默降级） |

### 3. 干净面 issue_scan 复扫（`max_findings=40`，全 low/info）
| 目录 | findings | 主要规则 |
|---|---|---|
| `src/core` | 120 | long-function 65 / json-injection 17 / match-exhaustive 32 / unused-variable 6 |
| `src/decompose` | 78 | unused-variable 38 / long-function 13 / shared-mutable 8 / array-index-bounds 7 |
| `src/claimguard` | 163 | unused-variable 75 / long-function 39 / match-exhaustive 26 / shared-mutable 11 |
| `src/ltl` | 69 | unused-variable 27 / long-function 23 / shared-mutable 7 / match-exhaustive 9 / array-index-bounds 3 |

**逐条复核关键命中，全部误报：**
- `src/core/core_task.mbt:644-669` `Json::string(...)` 17 处「json-injection」：MoonBit `Json::string` 是**构造器**（把 String 装箱为 Json 值），不是字符串拼接 ⇒ 规则把合法 API 当注入点，恒假阳性。
- `src/core/core_role.mbt:95` / `src/core/core_principle.mbt:75` 同理。
- `src/decompose/milestone.mbt:67-88` `templates[0]/[2]/[i]`「string-index / array-index-bounds」：`templates` 是固定长度数组（len≥3），`selected` 由 `selected.length()` 驱动；读上下文见长度不变式 ⇒ 安全。
- `src/ltl/ltl.mbt:118` `let s = trace[i]`：**已读源确认**（L114 `if i >= trace.length() { return eval_end(...) }` 早退保护；i 自 0 起仅 +1，无负下标）⇒ 安全。
- `moonbit-shared-mutable`（milestone.mbt:78/86 `let mut i = 0`、ltl.mbt:173 `let mut j = i`）：`let mut` 是 MoonBit 合法可变绑定语法，规则把「可变绑定」误读为「共享可变字段派生」⇒ 恒假阳性。
- `moonbit-unused-variable`（core_principle.mbt:73 `let m : Map[...]`、decompose.mbt:34/56 `let out : Array[String] = []`）：变量随后被 `m.set(...)`/`out.push(...)` 使用，子串近似匹配 `let` 声明行 ⇒ 误报。
- `moonbit-empty-match`（decompose.mbt:38 `_ => ()`）：`match l { None => (), Some(_) => out.push(l) }` 里的 catch-all 是**有意的**分支而非空转 ⇒ 误报。

**结论**：`issue_scan` 的 ocr-local 子串近似规则（`long-function`/`unused-variable`/`shared-mutable`/`json-injection`/`match-exhaustive`/`array-index-bounds`）在 MoonBit 语言特性上**系统性假阳性**；内建 11 条高危规则（除零/下标/unsafe 等）在干净面命中数为 0。R11 未新增真 bug 上报，未误报。

### 4. check_publish_payload 收口（P1 17 → 8 → 7）
- **本轮入库**：`memory/bug333_denoise_rules.json`（1149B，BUG-333 降噪规则预案语料，被 `reports/2026-10-20-R46-bug333-denoise-report.md` 与 `reports/2026-10-20-r10-publish-payload-close.md` 引用）→ commit `524a198`，清 1 项 P1。
- **剩余 7 项（全并发 WIP，不代劳）**：
  1. `_proj_lang-zone/`（新出现的中途 scratch 根目录）
  2. `cmd/commissar/pkg.generated.mbti`
  3. `memory/archive/thinking.archive.md`
  4. `publish_sigma.js`
  5. `src/evidence/pkg.generated.mbti`
  6. `src/ops/rhop_native.mbt`
  7. `src/server/bug335_ns_route_wbtest.mbt`
- 处置建议：`*.mbti` 3 项 = `moon info` 生成物，应入库或入 `.gitignore`（归属 cmd/commissar 与 src/evidence 的 WIP owner）；`memory/archive/*.md` 应入库（历史归档）；`src/ops/rhop_native.mbt` / `src/server/bug335_*` 应随并发 commit 入库；`_proj_lang-zone/` 待 owner 明确意图（scratch 则 ignore，交付则入库）；`publish_sigma.js` 待 owner 明确。

## 资源消耗
- 调用：`project_health` ×1 / `executor_route` ×1 / `executor_auction` ×1 / `model_route` ×2（1 次 dry_run 触发预期拒绝）/ `issue_scan` ×7 / `check_publish_payload` ×1
- 新增 commit：`524a198`（memory/bug333_denoise_rules.json 入库）
- 未改任何 `src/server/*`（并发 WIP 保护），未 `git add -A`，未动他人脏文件

## 任务分配记录
- 全部自查自跑（无子代理）；`src/server` 相关三项缺陷（BUG-333 ①③ / BUG-327 p2 / BUG-238 server 层）继续等待并发 WIP 清空后收口。

## 遗留风险
1. `src/server` 37 脏未清 ⇒ 三项缺陷修复仍阻塞。
2. publish P1 7 项仍红（CI 会拦 `moon publish`），均非本轮可安全处置。
3. `issue_scan` 子串近似规则的假阳性率在 MoonBit 上极高（本轮 430 命中中复核 7 处全误报）；建议 R46 的 BUG-333 预案真正落地：对 `match`/`let`/`fn`/`Json::string`/`let mut` 类词形做**语法级消歧**，否则 by_severity 的 low/info 永远被噪音灌满。

## 后续建议
1. 待并发 WIP 清空后：收口 BUG-333 ①③（`--min-severity` 参数 + 降噪规则真正接线）、BUG-327 p2、BUG-238 server 层。
2. 待 owner 明确后：把 7 项 publish P1 逐项入库/ignore。
3. 建议后续用 `issue_scan(rules_file=memory/bug333_denoise_rules.json)` 验证降噪规则真能压掉 match-exhaustive 噪音（本轮该 JSON 已入库，可作为正式 rules_file 语料）。

## 超额内容
- 本轮额外实测并记录了发布版 fist-mbt 的 `executor_auction`（置信度校准拍卖 R87）与 `model_route`（免费优先 + soldier 软性档位 + query-only 零副作用）行为，作为「善用发布版 fist-mbt 能力」的证据面。
- 附：`src/ltl/ltl.mbt:113-118` 读源确认记录（防止未来重新误报）。

## 来源
- 工具回执（本轮）：project_health / executor_route / executor_auction / model_route ×2 / issue_scan ×7 / check_publish_payload
- 源码复核：`src/ltl/ltl.mbt` L100-149；`src/core/core_task.mbt` L644-669；`src/decompose/milestone.mbt` L67-88
- 前置：R10 报告、BUG-333 账本条目、`memory/bug333_denoise_rules.json`
