# R20 报告：issue_scan low/info 规则精度审计（成本工具样本 12/12 近似全 FP）

- **轮次**：R20
- **日期**：2026-10-20
- **作用域**：`issue_scan` 的 `low`/`info` 规则精度 · 新缺陷 BUG-348
- **产物**：本报告

---

## 结果摘要

`src/server` 仍 37 脏（R14→R20 七轮阻塞），BUG-347/345/346 落地继续等待清空。本轮转向**对扫描器自身 `low`/`info` 规则的精度做抽样审计**——因为"修复扫描器"的前提是知道哪些规则真能报真 bug、哪些是噪音。

选 `src/engine/cost_tool.mbt`（77 行，可全文复核）为**精度样本**：12 条 low/info 命中 = **0 真 bug**，且暴露 `moonbit-unused-variable` 与 `moonbit-match-exhaustive` 两条规则的**判定口径缺陷**。

### 精度样本：`src/engine/cost_tool.mbt`

| 行 | 规则 | 实际代码 | 判定 |
|---|---|---|---|
| L29 | `unused-variable`（info） | `let exceeded = current >= limit`；`exceeded` 在 L43 `Json::boolean(exceeded)`、L46 `if exceeded` **实际使用** | **FP** |
| L31 | `unused-variable`（info） | `let remaining = limit - current`；`remaining` 在 L44 `Json::number(remaining)`、L52 `if remaining < limit*0.2` **实际使用** | **FP** |
| L32 | `unused-variable`（info） | `let action = ...`；`action` 在 L45 `Json::string(action)` **实际使用** | **FP** |
| L68 | `match-exhaustive`（low） | `match args.value("limit") { Some(Number(n,..)) => n; _ => 0.0 }` —— **已含 `_` catch-all，穷尽** | **FP** |
| L72 | `match-exhaustive`（low） | 同上，`current` 分支 | **FP** |
| L23/24/45/47/53/55 | `json-injection`（low） | 全为 `Json::string(...)` 安全构造器 | **FP**（BUG-346） |
| L14 | `long-function`（info） | `budget_check` L14-59 = 46 行 | 临界 |
| L64 | `long-function`（info） | `budget_check_json` L64-76 = **仅 13 行** | **FP** |

**合计 12 条命中 → 11 FP + 1 临界，0 真 bug。**

### 新缺陷：BUG-348（本轮入账）

- **`moonbit-unused-variable`**：把已使用的 `let` 绑定报成"未使用变量"。`src/engine` 全目录 **708 条** info，规模巨大。疑似只按 `let <ident> =` 行首启发式匹配，未做实际使用性检查。
- **`moonbit-match-exhaustive`**：把**已含 catch-all** 的 `match` 报成"可能非穷尽"。`src/engine` 全目录 **252 条** low。
- 两者叠加 + json-injection，构成 `src/engine` 1693 条命中里 `low`/`info` 噪音的主体（`high=0 medium=0`）。

⇒ 结论与 BUG-345/346/347 一致：**问题在规则层，不在被测代码**。修复扫描器应先处理规则口径，否则 `issue_scan` 输出会被 FP 淹没，真告警不可见。

---

## 修复方向（与既有 BUG 同批，待 owner 裁决）

1. `moonbit-unused-variable`：做**实际使用性检查**（在作用域内搜索后续引用），否则降级/退役。
2. `moonbit-match-exhaustive`：**先排除已含 `_`/catch-all 的 match**，再报非穷尽。
3. 与 BUG-347（统一匹配器）→ BUG-345（`by_severity` 补 info）→ BUG-346（json-injection 退役，owner 已裁决）同批落地。
4. `src/engine` 的 `high/medium` 仍为 0，无阻塞性真 bug，可安全等待。

---

## 资源消耗

| 项 | 量 |
|---|---|
| `issue_scan`（src/engine） | 1 次（1693 命中） |
| `ocr_scan`（src/router） | 1 次（本机不可用，诚实回 false） |
| `cost_tool.mbt` 全文复核 | 1 次 read（77 行） |
| 源文件编辑 | 0 |
| 新 BUG 入账 | **BUG-348**（medium，OPEN） |

---

## 任务分配记录

| 动作 | 执行者 | 说明 |
|---|---|---|
| 精度样本复核（cost_tool.mbt） | 本人 | 12/12 判定 |
| BUG-348 上报 | 本人 | 入账 `memory/bugs.md` |
| 规则层落地 | **待 src/server 清空** | BUG-345/346/347/348 同批 |

---

## 遗留风险

1. `src/server` 37 脏 + 新增未跟踪 `src/server/bug335_ns_route_wbtest.mbt`，R14→R20 **七轮字节未变**——BUG-345/346/347/348 落地全部阻塞。
2. `unused-variable`（708）/`match-exhaustive`（252）/`json-injection`（340）三条规则在 `src/engine` 单一目录就贡献近 1300 条 FP，**真告警被淹没**，`issue_scan` 当前信噪比很低。
3. OCR 双轨本机不可用（缺 `opencodereview.exe`），无法用 LLM 复核分担。

---

## 后续建议

1. **请 owner 一并裁决** BUG-348 处置（修口径 / 降级 / 退役），并纳入 BUG-345/346/347 同批落地。
2. 若暂不修，建议至少把 `unused-variable`/`match-exhaustive` 的严重度降为 `info`（当前 `match-exhaustive` 已是 `low`，会进 `by_severity.low`，与 BUG-345 的 `else→low` 兜底叠加，进一步污染）。
3. `src/server` 清空后按裁决① + 本批一次性落地。

---

## 超额内容

- 未改动任何源文件（严守并发边界）。
- 新入账 BUG-348（1 条），账本计数升至 348。
- 未启用自驱动命名空间；无新任务发布。

---

## 来源

- 本报告：`reports/2026-10-20-r20-low-info-rule-precision-audit.md`
- 新缺陷：**BUG-348**
- 单一真源总目录：R19 `reports/2026-10-20-r19-issue-scan-rule-layer-catalog.md`
- 被检样本：`src/engine/cost_tool.mbt`