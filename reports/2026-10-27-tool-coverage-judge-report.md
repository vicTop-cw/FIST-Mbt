# 工具覆盖判据 + 两个纯计算工具补测

> **任务**：① 把 BUG-455 的普查做成判据 ② 补测 `github_issue_webhook_parse` / `executor_auction`
> **执行人**：司令-γ · **日期**：2026-10-28 · **提交** `c684499a` + `0cc7f7ca`

---

## 结论

| 项 | 结果 |
|---|---|
| **判据** | `scripts/check_tool_coverage.py` —— **A 外壳面 / B 实现面分开判**，rc 0/1/2，selftest **10/10** |
| **覆盖率读数** | **外壳零覆盖 22 / 154（14.3%）**（修正了我上一轮报的 19.5% / 30 个 → 假阳性已剔除） |
| **进电池** | ✅ 两格（`--selftest` gate + 本体 known-red）；锚点 `123→124 / 82→83 / 90→91` |
| **2 个工具测了吗** | ✅ **4 格**（`webhook` 2 格 + `auction` 2 格），全断言行为 |
| **变异对照** | ✅ **2 个真跑**（删测试 ⇒ 判据红；`cov>0` 改 `true` ⇒ 拍卖两格齐红） |
| **测试** | `Total tests: 456, passed: 456, failed: 0` |

---

## 证据

### §1 判据设计：A / B 两层，**B 不能替代 A**

**一个工具算「有覆盖」当且仅当至少一条成立**：
- **A 外壳面**：工具名出现在任何 `*_test.mbt` / `*_wbtest.mbt` 里
- **B 实现面**：该工具映射到的实现函数出现在测试里

**⚠️ 为什么 B 单独不够**（这是判据的全部价值）：
```
BUG-453 的 execute：底层 execute_task 有测试（B ✓）
                    但「challenge 参数有没有接上 opt_challenge」—— 只有外壳面测得出（A ✗）
⇒ 若用「A or B」的合并判法，execute 会被判「已覆盖」，BUG-453 永远发现不了。
```
**⇒ 输出把 A / B **分开列**，A 缺失即报「外壳零覆盖」。**

**工具名 → 实现函数：显式白名单 `IMPL_MAP`（15 项），不做启发式**
```
实测：自动从 handler 抽 @pkg.fn 会混入 @mcp.*（注册宏）与 get_str/now_default 等工具函数
      ⇒ 假阳性 13/30。启发式在这个面上不可靠。
不在表里的标 impl=unmapped —— **诚实标注未映射，不假装查过**。
```

### §2 覆盖率读数（真仓）

```
[扫描] 工具 154 个 · 测试文本 1254664 字符
[A 外壳面] 有覆盖 132 / 154
  外壳零覆盖 22 个：
    assistant_resign(impl=mapped)  audit_permission(impl=mapped)  executor_auction(impl=mapped)
    atgc_old_compile/run/talk  dag_check  dag_publish  gitcode_env_check  github_env_check
    github_issue_close/comment/webhook_parse  github_queue_status  ...
[B 实现面] 已映射 15 个工具，其中实现函数在测试里出现 14 个
[结论] 外壳零覆盖 22 / 154（14.3%）；覆盖率 85.7%
```

**rc 契约**：`0` 全有外壳覆盖 / `1` 有零覆盖（逐条点名）/ `2` 无法自证。

**输出首行自带覆盖面声明**（不只写在 docstring）：
```
[覆盖面] 本判据只判「有没有测试」，**不判测试好不好**：
  ✅ A 外壳面（能抓接线/回执类缺陷，如 BUG-453/436/439）
  ✅ B 实现面（**不能替代 A**）
  ❌ 不判：测试是否断言行为（只断言字符串的也放行 → 那要人工/check_two_faces）
  ？未映射：不在 IMPL_MAP 白名单里 → 只查 A 面，**不假装查过 B**
...
[PASS] 全部工具有外壳覆盖。**这不代表工具是对的** —— 只代表「有人碰过它」。
```

### §3 selftest 10 格（含变异对照）

```
[OK] all-covered-rc0 / all-covered-missing0
[OK] ★MUTATION-removed-test-rc1        ← 删掉 tool_b 的测试引用 ⇒ rc 0→1
[OK] ★MUTATION-names-tool_b            ← 且点名 tool_b
[OK] impl-only-still-missing           ← 只有实现层测试 ⇒ **仍报零覆盖**（B 不替代 A）
[OK] impl-only-rc1 / impl-layer-detected
[OK] empty-self-reject-rc2             ← 空扫描面自拒
[OK] coverage-note-in-output / pass-not-correct-in-output   ← 覆盖率声明必须在输出里
[selftest] 10/10 格通过
```

### §4 两个纯计算工具的补测（4 格，全断言行为）

`src/server/server_bug455_pure_wbtest.mbt`：

| 格 | 断言什么 |
|---|---|
| `b455_w1_webhook_parse_valid_payload` | `@fist-bot reopen T-1` ⇒ `action=reopen` + `task_id=T-1`；`challenge` ⇒ `action=challenge`；`blocked <reason>` ⇒ `action=blocked` |
| `b455_w2_webhook_parse_rejects_bad_input` | 空 payload ⇒ `Err`；`{ not json` ⇒ `Err` |
| `b455_a1_auction_picks_highest_coverage` | 只覆盖者胜出（`winner.name == "auction-alpha"`）+ `count == 1`（覆盖 0 的被排除） |
| `b455_a2_auction_empty_when_no_coverage` | 无人覆盖 ⇒ `winner` 是 **`null`** + `count == 0` |

**⚠️ 写测试时纠正了两个错误假设**（这是测试的价值）：
1. 我假设 `winner` 是**字符串** → 实测是**对象** `{name, coverage, bid, trust, calibration, load, score}`
2. 我假设无覆盖时 `winner` 是**空串** → 实测是 **`Json::null()`**

### §5 变异实测（真跑）

**变异 A：判据自身**
```
删掉 tool_b 的测试引用 → ★MUTATION-removed-test-rc1 红（rc 0→1）+ 点名 tool_b ✅
```

**变异 B：拍卖覆盖率**
```
注入：src/executor/registry.mbt:313  `if cov > 0.0 {` → `if true {`
  → F| b455_a1_auction_picks_highest_coverage   failed
  → F| b455_a2_auction_empty_when_no_coverage   failed
  → Total: 456, passed 454, failed 2

恢复：cp /tmp/reg.bak → Total: 456, passed 456, failed 0
      git diff src/executor/registry.mbt 行数 = 0
```

---

## 分析：为什么「外壳 + 实现两层」是正确判法

### 三层各自的缺陷类型不同

| 层 | 它能抓什么 | 本会话实例 |
|---|---|---|
| **实现层**（B） | 算法/逻辑错 | 大多数 |
| **外壳层**（A） | **接线错**（参数没透传、工具没注册、回执字段编造、死参数） | **`BUG-440`/`BUG-453`/`BUG-436`/`BUG-439`** |
| 端到端 | 集成错 | — |

**⇒ 「实现层 208 格全绿、工具照样是坏的」的原因，就是**只有 B 没有 A**。**
**`BUG-453` 是最好的标本：`execute_task` 测得很全，但「`challenge` 参数有没有接上 `opt_challenge`」这件事，实现层永远看不见。**

### 为什么用白名单而不是启发式

**启发式的失败模式很具体**：从 handler 里抽 `@pkg.fn`，会把
- `@mcp.ToolResult` / `@mcp_types.ToolError`（注册框架）
- `get_str` / `now_default` / `json_bid_map`（本文件工具函数）

一起算成「实现函数」⇒ 几乎所有工具都被判「B 已覆盖」⇒ **B 面失去判别力**。

**⇒ 白名单的代价是「新工具要手动加一条」，收益是「每条映射都是人确认过的」。**
**不在表里的标 `impl=unmapped`** —— 这样「没查过」与「查过没有」在输出上可区分。

---

## 缺口与风险

### 1. ⚠️ 判据本体登记为 `known-red`（`expect=1`），不是门禁绿

**理由**：`rc=1` 是**当前真实的待办清单**（22 个工具外壳零覆盖），不是判据坏了。
**代价**：若有人把 22 个都补了，`rc` 会变 0 ⇒ 电池该格**变红**（因为期望是 1）
⇒ 逼他改回 `expect=0`。**这是本文件自订的律**（同 `check_ci_step_position.py` 的先例）。

### 2. 22 个外壳零覆盖工具**仍未补测**

本单只补了 2 个（`webhook_parse` / `auction`）。**判据现在把它们逐条点名了，这是进步，但没有消灭它们。**

### 3. `IMPL_MAP` 只有 15 项，154 个工具里 **139 个标 `impl=unmapped`**

**意味着 B 面对大部分工具是盲的**。不过 A 面覆盖全部 154 个 ⇒ **主要防线在**。

### 4. 判据不判「测试好不好」

只断言字符串 `"foo"` 出现在源码里的测试**会被放行**。
**⇒ 与 `check_two_faces.py` 互补，但两者都不判「测试质量」——那是人工的活。**

### 5. 我发现并修正了上一轮的报告误差

上一轮报「30 个零覆盖 / 19.5%」，本单修正为 **22 个 / 14.3%**
（8 个是我方法假阳性：`text_diff`/`rank_of`/`staff_label_of`/`soldier_type_of` 等的**工具名**不在测试里，但**实现包**有大量测试）。

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-27-tool-coverage-judge-report.md` |
| 判据 | `scripts/check_tool_coverage.py`（10 格 selftest） |
| 执行面 | `scripts/run_guards.py`（`--selftest` gate + 本体 known-red） |
| 锚点 | `scripts/README.md`：`rulers=124 ci=46 battery=83 gate=91` |
| 补测 | `src/server/server_bug455_pure_wbtest.mbt`（4 格） |
| **建议后续** | ① 补 `dag_check`/`dag_publish`/`github_issue_webhook_parse` 外壳测试（最易）② 扩 `IMPL_MAP` ③ `BUG-455` 可标部分 FIXED（22 个已点名，2 个已测） |
| **未做** | **未改 `src/` 生产代码**（两处变异已 `cp` 还原，`git diff` 均为 0 行） |
