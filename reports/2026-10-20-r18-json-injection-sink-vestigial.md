# R18 报告：`moonbit-json-injection` 的注入汇（sink）在本仓根本不存在 → 建议退役而非修 pattern

- **轮次**：R18
- **日期**：2026-10-20
- **作用域**：全仓 `@json.parse` / `Json::*` 调用面 · BUG-346 / BUG-347 修复方向修正
- **产物**：本报告 + `memory/bug346_json_injection_sink_analysis.json`（可复现的 sink 枚举清单）

---

## 结果摘要

R16/R17 已定位 BUG-346/347 的机制。本轮进一步回答一个**更根本的问题**：这条规则在本仓**到底有没有可能命中真注入**？

答案：**没有**。全仓既无「写入侧」真注入（用安全构造器），也无「读取侧」注入汇（无拼接字符串喂解析器）。该规则是**残留/失效规则**——对两类真实风险面都不可见。

### 1. 读取侧：`@json.parse` 有 127 处，但全是反序列化外部载荷

对 `src/**/*.mbt` 全文检索 `@json.parse`（MoonBit 的 JSON 反序列化入口），127 处调用，按输入来源分类：

| 输入来源 | 代表位置 | 说明 |
|---|---|---|
| HTTP 响应体 | `src/evolve/github_client.mbt` L88/151、`src/router/ofm_chat.mbt` L97、`src/server/github_js.mbt` L129/152/212、`src/server/laya_js.mbt` L73/101/122 | 远端返回的 JSON，非本地拼接 |
| 配置文件 | `src/store/store_sqlite.mbt` L351/679、`src/server/server.mbt` L3623/7253、`src/server/issue_scan.mbt` L1735 | `rules_file`/`form_json` 等用户提交的 JSON 文本 |
| 进程/stdin 消息 | `src/server/stdio_js.mbt` L41/135/183 | MCP 消息体 |
| 测试/自建语料 | `src/router/ofm_chat_wbtest.mbt` L21、`src/server/memory_test.mbt` 多处 | 测试内 `Json::object(...).stringify()` 后回读 |

**无一处**是「本地用 `+` 把用户输入拼成 JSON 字符串再 `@json.parse`」。`Json::parse` / `Json::from_string` / `Json::from_json` / `Json::decode` / `Json::read_from` / `Json::from_str` 全仓**零命中**（独立检索确认）。

> 这些 `@json.parse` 是**反序列化**（deserialization）面，与"JSON 注入"（write-side output-encoding flaw）不是同一风险类别。若要管，应单列一条「未校验反序列化」规则，而非复用 json-injection。

### 2. 写入侧：只用安全构造器，无裸字符串拼接

本仓 JSON 序列化全部走 `Json::object({...})` + `Json::string(...)` / `@json.to_json(...)`（见 `src/omega/spec.mbt` L27/29、`src/omega/omega_test.mbt` L236-238、`src/omega/check.mbt` L28/60、`src/server/hat_hexa_tools.mbt` 多处）。R16 已证 `Json::string(` 是**安全构造器**，`moonbit-json-injection` 命中它 = 100% 假阳（`src/store` 基线 45/45）。

### 3. 结论：规则应退役或重构，而非只修 pattern

三条独立证据指向同一结论：

| 证据 | 结论 |
|---|---|
| R16 三探针：pattern 被 `::` 剥离为 `string(`，命中全库 `*.to_string(` | 机制缺陷（BUG-347） |
| 内建 pattern `Json::string(` = 安全构造器 | 语义反转（BUG-346） |
| **本仓无「拼接→解析」注入汇，写侧只用安全构造器** | **规则对真实风险不可见 = 残留规则** |

⇒ 修 BUG-346/347 的**正确方向不是"把 pattern 改对"，而是决定这条规则去留**。

---

## 修复建议（修订 R17 蓝图 §3 方案 B）

### 推荐 1：退役该规则（最诚实）

在 `issue_scan.mbt` 规则表中**删除** `moonbit-json-injection`，或将其 `severity` 永久置 `info` 且 `pattern` 改为必不命中标记（显式标注 `deprecated: no-sink-in-moonbit`）。理由：子串规则无法可靠检测「拼接进 JSON 输出」这类**语义**问题；本仓无该风险面，留着只产生噪音。

### 推荐 2：若坚持保留，重构为真实可检测风险

把规则改名并改语义为 **`moonbit-unvalidated-json-parse`**：pattern 指向 `@json.parse(` **且**该行/调用无 `catch` 兜底、或对解析结果不做结构校验。这才对应本仓 127 处反序列化面的真实风险（坏 JSON 抛错 / 未校验字段）。但这属于**新增能力**，需单独评估 FP 率（多数 `@json.parse` 已带 `catch`）。

### 推荐 3（过渡）：保持 v2 降噪

`memory/bug333_denoise_rules_v2.json` 已把 json-injection 降为 `info`（pattern 显式化为 `string(` 如实编码 BUG-347 行为），在退役/重构落地前止损。

### 落地路径（待 src/server 清空）

R17 蓝图方案 A（统一匹配器）+ 本报告的退役/重构决策 → `moon fmt` → `moon test --target js` 全绿 → 更新 wbtest 锁（删除/替换对 json-injection 的断言）→ `bug_fix([BUG-347, BUG-346], evidence=...)`。

---

## 资源消耗

| 项 | 量 |
|---|---|
| `grep` 全仓 `Json::parse/from_*` | 1 次（0 命中） |
| `grep` 全仓 `@json.parse`/`.parse(`/`from_string` | 1 次（127 命中，逐条分类） |
| 源文件编辑 | 0（`src/server` 保持只读） |
| 任务发布 | 0 |

---

## 任务分配记录

| 动作 | 执行者 | 说明 |
|---|---|---|
| sink 面枚举与分类 | 本人 | 127 处 `@json.parse` 按来源分类 |
| 退役/重构决策 | 本人 | 三条独立证据 → 推荐退役 |
| BUG-346/347 落地 | **待派** | 仍被 `src/server` 37 个并发 WIP 阻塞 |

---

## 遗留风险

1. **BUG-345/346/347 均未真正修复**（`src/server/issue_scan.mbt` 37 脏 + 新增并发未跟踪 `src/server/bug335_ns_route_wbtest.mbt`）。
2. **退役决策需 owner 确认**：删除/降级一条既有规则是行为变更，本报告只给方案 + 预案，执行权在指挥官/owner。
3. `@json.parse` 的**未校验反序列化**是真实但**尚未被任何规则覆盖**的风险面（若启用推荐 2 需先评估 FP）。

---

## 后续建议

1. 建议 owner 先裁决 json-injection 的**去留**（推荐 1 退役 > 推荐 3 过渡），再决定 BUG-346/347 修复形态——否则可能出现"修好了 pattern 但规则本身没用"的白做。
2. 若走推荐 2，需另立一条 `moonbit-unvalidated-json-parse` 提案，单独评估 127 处 `@json.parse` 的 catch 覆盖率作为 FP 基线。
3. `src/server` 清空后同批落地 BUG-327/333/345/346/347。

---

## 超额内容

- 未改动任何 `src/server` 文件。
- 无新任务发布（无本人活跃命名空间）。
- 未新增 BUG 账本条目（本报告是对 BUG-346/347 修复方向的修订，不构成新缺陷）。

---

## 来源

- 本报告：`reports/2026-10-20-r18-json-injection-sink-vestigial.md`
- 可复现清单：`memory/bug346_json_injection_sink_analysis.json`
- 前序：R16 `reports/2026-10-20-r16-denoise-rules-v2-and-bug347.md`、R17 `reports/2026-10-20-r17-bug347-fix-blueprint.md`
- 账本：BUG-345 / BUG-346 / BUG-347