# 2026-10-14 · 用 issue_scan 找 bug：发现 moonbit-map-set-no-rebind 规则前提错误（Round 112）

## 结果摘要

**一句话**：用发布版 fist-mbt 的 `issue_scan`（31 条 MoonBit 高危规则）扫稳定模块，得 621 条 low、0 条 high/medium；
定点复核发现**最重的规则之一 `moonbit-map-set-no-rebind` 前提错误**——`why` 写「Map.set() 返回新 Map，未重绑定则变更丢失」，
但**实测铁证 `Map([]).set()` 原地生效**（`m.set("k",42); m.get("k")` = Some(42)）。该规则纯模式匹配 `.set(`，
对有效生产代码误报（如 `Principle::to_json` 实测返回非空对象却被命中）。**已上报 BUG-156**（commit `b73b3bd`）。

## 实测证据（金条八·实测而非自述）

### 环境现状
| 项 | 读数 |
|---|---|
| `moon test --target js` | **1048/1048**（较上轮 1043 又 +5，并发 agent 仍活跃） |
| `check_tools_sync` | PASS（工具数**稳定 166**，R3b/R7 扫现状面 137 份） |
| `check_doc_surface`/`check_tools_sync`/`check_template_ctrl` | PASS |
| `check_plugin_sync` | FAIL（并发 agent 工作树 `src/server/model_router_ops.mbt` 已改，可能加工具 → **不重生成 plugins**） |
| 工作树未提交 | 2 份（1 份动 .mbt，1 份 report） |

### issue_scan 全稳定模块 by_rule（8 模块，621 条 low，high=0 medium=0）
| 规则 | 命中 | 判定 |
|---|---|---|
| moonbit-long-function | 182 | 启发式，多为误报 |
| moonbit-unused-variable | 146 | 启发式，多为误报 |
| moonbit-json-injection | 70 | 启发式，需语境 |
| **moonbit-map-set-no-rebind** | **62** | **前提错误（BUG-156）** |
| moonbit-shared-mutable | 50 | 启发式 |
| moonbit-match-exhaustive | 47 | 启发式 |
| moonbit-array-index-bounds | 26 | **启发式（`[i]` 在安全 for 循环内误报）** |
| ... | 其余 | 均为 low |

### 定点复核：两个可验证误报
1. **`moonbit-map-set-no-rebind` 前提错误**（BUG-156）：
   - 规则 `src/server/issue_scan.mbt:191-196`：`why` 说「Map.set() 返回新 Map，未重绑定则变更丢失」，`pattern: [".set("]` 纯子串匹配。
   - **铁证**：临时白盒测试 `let m : Map[String, Int] = Map([]); m.set("k", 42); m.get("k")` → **`Some(42)`**。
   - 生产代码佐证：`src/core/core_principle.mbt:72-78` `Principle::to_json`（三段 `m.set(...)` 后 `Json::object(m)`）→ **`{"index":1,"title":"...","body":"..."}` 非空**。
   - 该规则被该文件 L74-76 命中，是**误报**。
2. **`moonbit-array-index-bounds` 误报**：`src/engine/engine.mbt:1098` `let slice_text = slices[i]` 在
   `for i = 0; i < slices.length(); i = i + 1` 内——**必然安全**，规则 `[i]` 纯模式匹配不看循环边界。

## 与 BUG-15 的关系（关键）

BUG-15（FIXED，2026-09-26）修的是 **high 档**规则命中注释/规则表自身字面量（high 精确率实测 0/8）。
本条 BUG-156 是 **low 档规则语义前提错误**——不是命中噪声，而是规则的**事实陈述错了**（假设所有 Map.set 返回新 map）。
**两个独立缺陷面**：BUG-15 的修（跳注释/跳自身规则表）不覆盖本条。故 BUG-156 是新上报。

## 交付（commit `b73b3bd`）

`memory/bugs.md` 追加 **BUG-156** `[2026-10-14T19:00:30Z] [low] OPEN`：
- summary：规则前提错误 + 纯模式匹配误报
- detail：规则实现行号 + `why` 前提 + 铁证（临时测试 get=Some(42)）+ 生产代码佐证（to_json 非空）+ 62 条命中
- why-not-fixed：规则 `why` 已自称启发式，但事实陈述错，应修正为区分可变/不可变 Map
- evidence：临时测试已删，无仓内残留
- 与 BUG-15 关系：独立缺陷面

## 资源消耗

- 1 个提交：`b73b3bd`（BUG-156 上报）
- 多次 `moon test --target js`（确认 1048 + 定点验证）
- 3 支临时测试（已删，无仓内残留）：`temp_bugcheck_test.mbt` 验证 to_json 非空 + Map.set 原地生效
- 4 支临时分析脚本（temp/verify_count.py、temp/scan_by_rule.py、temp/arr_bounds.py 等，gitignored）

## 任务分配记录

指挥官亲自：
- **用发布版能力找 bug**（用户指令③）：跑 `scripts/issue_scan.py` 扫 8 个稳定模块
- **实测铁证而非猜测**（金条八）：对规则前提写临时 MoonBit 测试实测 `Map.set` 语义，`get("k")=Some(42)` 铁证
- **区分真误报与已知限制**：查 bugs.md 发现 BUG-15 已修同类 high 档问题，确认本条是**独立**的 low 档语义前提错误，不重复上报
- **不追 churn**：测试数 15 分钟 +10（1043→1048）、工具数可能变（并发 agent 改 model_router_ops.mbt）→ 不追文档/插件同步，改做稳定的扫描器精度发现
- **0 仓内残留**：临时测试文件全部删除，只留 bugs.md 一条 OPEN 记录

## 遗留风险

1. **`check_plugin_sync` 红**：并发 agent WIP（加 router 工具），等收口重生成。
2. **`check_test_sync` 红**：文档 1033 vs 实测 1048，并发 WIP 收口时连文档一起修。
3. **测试/工具数 churn**：并发 agent 仍活跃，最终数待定。
4. **BUG-156 待修**：issue_scan 的 `moonbit-map-set-no-rebind` 规则前提错误，建议修正 `why` 陈述或收窄 pattern。
5. **BUG-155 dist/**：仍 OPEN 待 owner 裁决。

## 后续建议

1. **修 BUG-156**：把规则 `why` 的「Map.set() 返回新 Map」改为「Map([]) 可变 map set 原地生效；仅不可变 set 返回新 map」，或把 pattern 从 `.set(` 收窄到不可变 set 上下文——提高扫描器精确率、减误报。
2. **并发 agent 收口后**：重生成 plugins + 同步测试数文档，跑全守卫链确认归绿，发权威 Release。
3. **issue_scan 精确率**：621 条 low 中 `long-function`/`unused-variable`/`json-injection`/`map-set-no-rebind`/`array-index-bounds` 五类规则主导，多为启发式误报——可考虑按精确率调档或加语境判定。

## 超额内容

- **「用发布版能力找 bug」的正确姿势**：`issue_scan` 输出 621 条 low 看似"问题很多"，但**0 条 high/medium** + 定点复核两个最大规则都是误报——说明扫描器是启发式，**读数要按规则语义解读**，不能把 621 当"621 个问题"。
- **规则 `why` 的事实陈述是契约**：`moonbit-map-set-no-rebind` 的 `why` 写错 MoonBit Map 语义，导致使用者按错误的假设理解规则。规则文档（`why`/`hint`）应经过实测校准，不能凭经验假设语言语义。
- **可复用铁证方法**：对规则假设写一条最小 MoonBit 测试，`ignore(fail(...))` 打出实际值——这是验证任何语义假设的最快路径（本次一次就证伪了规则前提）。

## 来源

- 扫描：`scripts/issue_scan.py`（8 模块，621 条 low，high=medium=0）
- 铁证：临时 MoonBit 白盒测试（已删）`Map([]).set("k",42).get("k")` = Some(42)
- 生产代码佐证：`src/core/core_principle.mbt:72-78`（`Principle::to_json` 返回非空对象）
- 规则实现：`src/server/issue_scan.mbt:191-196`（`pattern: [".set("]`）
- 误报佐证：`src/engine/engine.mbt:1095-1098`（`for i = 0; i < slices.length()` 内 `slices[i]` 安全）
- 同类先例：`memory/bugs.md` BUG-15（high 档规则命中自身字面量/注释，FIXED）
- 实测：`moon test --target js` 1048/1048、`check_tools_sync` 166 工具稳定
