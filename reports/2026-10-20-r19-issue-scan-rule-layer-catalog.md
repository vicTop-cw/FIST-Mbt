# R19 报告：issue_scan 规则层缺陷总目录（R11→R19 九轮收敛）

- **轮次**：R19
- **日期**：2026-10-20
- **作用域**：`issue_scan` 规则层（内建 + 外部 rules_file）+ 本轮新增佐证
- **产物**：本报告（单一真源，替代 R11-R18 散落的规则缺陷笔记）

---

## 结果摘要

本轮完成两件事：① 把 R11→R19 九轮发现的**规则层缺陷**收敛成一张总目录（替代此前散落的 6 份报告）；② 补两条新佐证（`src/engine` 单目录 json-injection **340 命中**、`moonbit-result-discard` 规则**匹配任意 `ignore(`**）。并确认本机 **OCR 双轨不可用**（诚实回 `ocr_available:false`）。

### 1. 本轮新佐证

| 发现 | 证据 | 结论 |
|---|---|---|
| json-injection FP 量级最大单目录 | `src/engine` 扫描：`moonbit-json-injection` **340 命中**，抽样全部为 `Json::string(...)` 安全构造器（`cost_tool.mbt` L23/24/45/47/53/55、`engine.mbt` L1081/1082/1240/1243/1244/1251/1432/1434/1436/1438/1445） | FP 量级随目录规模放大：store=45、ltl=11、**engine=340** |
| `moonbit-result-discard` 规则过宽 | `src/engine/engine.mbt` L739、L853 `ignore(created_by)`，此处 `created_by : String` **非 Result**，注释显式写明"续轮发起者仅作审计用途…非法值不阻断" | 规则命中**任意 `ignore(` 调用**，非仅 Result 丢弃 → 规则语义与名称不符 |
| 干净面零真 bug（复确认） | `src/engine` 23 文件 1693 命中，`high=0 medium=0`，全部 low/info 且多为规则 FP | 与 R13 结论一致 |
| OCR 双轨不可用 | `ocr_scan(project_dir=".", subcmd="scan", path="src/router")` → `{ocr_available:false}`，提示安装 `opencodereview.exe` | 本机无法启用 OCR LLM 复核；`issue_scan` 单轨结论需自行读上下文复核 |

### 2. 规则层缺陷总目录（R11→R19）

| 编号 | 缺陷 | 位置/路径 | 严重度 | 实证 | 状态 |
|---|---|---|---|---|---|
| **BUG-345** | `by_severity` 聚合缺 `info` 档，`else→low` 兜底 ⇒ 降噪无法净化 `by_severity`，`low` 混入 `info` | `src/server/issue_scan.mbt` | medium | `src/store` `{low:989}`、`src/ltl` `{low:80}`、`src/engine` `{low:1693}` 四轮一致；R14 有 A/B 守恒判据 | OPEN，蓝图 R14 |
| **BUG-346** | 内建 `moonbit-json-injection` pattern `Json::string(` 与意图相反，匹配**安全构造器** | `src/server/issue_scan.mbt` L259 | medium | `src/store` 基线 45/45 全为 `Json::string(` | OPEN |
| **BUG-347** | 外部 `rules_file` pattern 被匹配器按 `::` 切分只取尾段 ⇒ `Json::string(` 降级为 `string(`，命中全库 `*.to_string(` | `src/server/issue_scan.mbt`（外部匹配路径） | **high** | 三探针：`Foo::string(` 与 `Json::string(` 在 `src/ltl` 各命中逐字相同 11 条，均为 `to_string(` | OPEN，蓝图 R17 |
| **（本轮新增）** | `moonbit-result-discard` 命中任意 `ignore(`，非仅 Result | `src/server/issue_scan.mbt`（该规则定义） | low | `engine.mbt` L739/L853 `ignore(created_by : String)` | 未上报，待定 |
| **（R12）** | 整表含 `::` 的 pattern 仅 2 条（json-injection、resource-leak），均可被 BUG-347 剥离 | — | — | 34 处 pattern 枚举 | 已归入 BUG-347 |

### 3. json-injection 规则去留（R18 结论重申 + 本轮放大）

三条独立证据 + 本轮量级数据：

| 证据 | 数据 |
|---|---|
| 注入汇不存在 | `Json::parse/from_*/decode/read_from/from_str` 全仓 **0 命中**；`@json.parse` 127 处全为反序列化外部载荷 |
| 写侧无注入 | 全仓仅 `Json::object` + `Json::string` 安全构造 |
| FP 量级 | `src/store`=45、`src/ltl`=11、**`src/engine`=340**，抽样全为安全构造器 |

⇒ 该规则对写入侧和读取侧**两头都测不到真注入**，属残留/失效规则。修复方向：**退役 > 重构（`moonbit-unvalidated-json-parse`）> 保持 info 过渡**。

### 4. 单一真源指向

九轮的规则缺陷分析已收敛到本报告；后续修复/决策请以本报告为唯一入口，R14/R16/R17/R18 报告作为证据细节引用即可。

---

## 资源消耗

| 项 | 量 |
|---|---|
| `issue_scan`（src/engine） | 1 次（23 文件，1693 命中） |
| `ocr_scan`（src/router） | 1 次（**不可用**，诚实回 false） |
| 源码上下文复核（engine.mbt L728-863） | 2 次 read |
| 源文件编辑 | 0（`src/server`、`src/engine` 均未改动） |
| 任务发布 | 0 |

---

## 任务分配记录

| 动作 | 执行者 | 说明 |
|---|---|---|
| `src/engine` 扫描 + 340 FP 计数 | 本人 | 佐证 json-injection FP 量级 |
| `ignore(created_by)` 上下文复核 | 本人 | 判定为刻意设计 + 规则过宽 |
| OCR 可用性探测 | 本人 | 确认本机双轨不可用 |
| 规则层缺陷总目录收敛 | 本人 | 替代 R11-R18 散落笔记 |
| BUG-345/346/347 落地 | **待 owner 裁决 + src/server 清空** | 持续阻塞 |

---

## 遗留风险

1. **BUG-345/346/347 仍未修复**：`src/server` 37 脏 + 新增并发未跟踪 `src/server/bug335_ns_route_wbtest.mbt`，R14→R19 **六轮字节未变**。
2. **json-injection 去留未裁决**：退役是行为变更，需 owner 拍板；否则修复可能白做。
3. **`moonbit-result-discard` 规则过宽**：本轮新发现但未上报，若修 BUG-346/347 应一并评估。
4. **OCR 双轨不可用**：本机缺 `opencodereview.exe`，bugfind 的 `require_ocr` 约束在本机无法满足，寻虫结论依赖 `issue_scan` 单轨 + 人工复核。

---

## 后续建议

1. **请 owner 裁决** json-injection 去留（退役/重构/过渡），并确认是否同步处理 `moonbit-result-discard` 过宽。
2. `src/server` 清空后一次性落地：BUG-347（统一匹配器）→ BUG-345（`by_severity` 补 info）→ BUG-346/退役决策 → 可选 BUG-327/333。
3. 若需 OCR 双轨，需在宿主安装 `opencodereview.exe` 或设 `FIST_OCR_BIN`。

---

## 超额内容

- 未改动任何源文件（严守并发边界）。
- 无新任务发布、无新 BUG 入账（本轮发现为佐证与规则过宽，`moonbit-result-discard` 过宽可并入未来修复批）。
- 本报告替代此前散落的规则缺陷笔记，作为单一真源。

---

## 来源

- 本报告：`reports/2026-10-20-r19-issue-scan-rule-layer-catalog.md`
- 证据细节：R14 `reports/2026-10-20-r14-bug345-fix-blueprint.md`、R16 `…-r16-denoise-rules-v2-and-bug347.md`、R17 `…-r17-bug347-fix-blueprint.md`、R18 `…-r18-json-injection-sink-vestigial.md`
- 数据：`memory/bug346_json_injection_sink_analysis.json`、`memory/bug347_external_pattern_probe.json`、`memory/bug333_denoise_rules_v2.json`
- 账本：BUG-345 / BUG-346 / BUG-347

---

## 追加：owner 裁决（2026-10-21，R19 收口）

**裁决① · `moonbit-json-injection` 处置 = 退役**（owner 选定）
- 处置方式：删除该规则，或 `severity` 永久置 `info` + `pattern` 改必不命中标记 + 显式标注 `deprecated: no-sink-in-moonbit`。
- 依据：R16-R19 四轮实证——内建命中安全构造器（BUG-346）、外部 rules_file 被剥离 `::` 限定（BUG-347）、本仓注入汇不存在（`Json::parse/from_*` 零命中，`@json.parse` 127 处全为反序列化外部载荷；FP 量级 store=45 / ltl=11 / engine=340）。

**裁决② · 落地授权 = 清空后落地**（owner 选定）
- 授权范围：等 `src/server` 并发 WIP 清空后，一次性落地 BUG-347（统一匹配器）→ BUG-345（`by_severity` 补 info）→ BUG-346（json-injection 退役，按裁决①）→ 可选 BUG-327/333；落地后跑 `moon test --target js` 全绿再 `bug_fix` 销账。
- 边界：不触碰并发未提交的 `src/server` 37 个改动与新增未跟踪 `src/server/bug335_ns_route_wbtest.mbt`；不越权修改无关子系统。

**待定项**：`moonbit-result-discard` 规则命中任意 `ignore(`（`engine.mbt` L739/L853 `ignore(created_by : String)`）的过宽问题，未在本次裁决范围内；建议在 BUG-346/347 修复批一并评估，或另立提案。