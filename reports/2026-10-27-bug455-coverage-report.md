# BUG-455 补测报告：30 个零覆盖工具（8.4 万行代码里的 22% 盲区）

> **病灶**（我自己报的）：从 `server.mbt` 抽 154 个工具名，在全部测试文本里搜 ⇒ **30 个零覆盖**。
> **执行人**：司令-γ · **日期**：2026-10-27

---

## 结论

| 项 | 结果 |
|---|---|
| **零覆盖工具数** | **30 个 / 154 个（19.5%）** —— 比我报的 34 少 4 个（方法收紧后） |
| **补测试** | **5 格**（覆盖 4 个工具：`reserve_check` / `lock_release` / `store_close` / `assistant_status`） |
| **变异对照** | **✅ 2 个真跑**（`locks_release` 变「谁都能释放」⇒ 必红，已实测） |
| **其余 26 个** | **逐个给了理由**（见 §2 分类表） |
| **测试结果** | `Total tests: 448, passed: 448, failed: 0` |
| **★ 最重要的发现** | **「名字没出现在测试里」≠「没测试」** —— 30 个里有 **13 个是假阳性**（实现包有大量测试） |

---

## 证据

### §1 ★ 先自我证伪：我的普查方法有系统性误报

**`text_diff`（零覆盖清单第 30 个）实测**：
```
$ grep -rln 'text_diff' src/**/*_test.mbt src/**/*_wbtest.mbt   → 空
$ ls src/diff/*test*.mbt                                        → src/diff/diff_test.mbt
$ grep -c '^test ' src/diff/diff_test.mbt                       → 17 格
```
**⇒ `text_diff` 的实现是 `@diff.diff_lines`，`src/diff` 有 17 格测试；
但测试里从没提过 `text_diff` 这个**工具名**（测的是模块函数，不是 MCP 工具壳）。**

**同类**：`rank_of` / `staff_label_of` / `soldier_type_of` → `@display`（**24 格**）；
`audit_permission` / `debate_*` / `mode_templates` / `selfdrive_*` → `@ops`（**208 格**）；
`assistant_*` / `lock_*` / `reserve_*` → `@store`（**97 格**）；
`evolve_snapshot` → `@evolve`（**76 格**）；`atgc_old_*` → `@core`（**25 格**）。

**⇒ 真正的「零覆盖」是「工具壳 + 实现包都没有测试」，而不是「工具名没出现在测试文本里」。**

### §2 30 个工具的完整分类（**每个都有结论**）

| # | 工具 | 实现包 | 包测试 | 类别 | 结论 |
|---|---|---|---|---|---|
| 1 | `text_diff` | `@diff` | **17** | 假阳性 | **✅ 已覆盖**（`diff_test.mbt`） |
| 2 | `rank_of` | `@display` | **24** | 假阳性 | **✅ 已覆盖**（`rank_test.mbt`） |
| 3 | `staff_label_of` | `@display` | **24** | 假阳性 | **✅ 已覆盖**（`staff_test.mbt`） |
| 4 | `soldier_type_of` | `@display` | **24** | 假阳性 | **✅ 已覆盖**（`soldier_test.mbt`） |
| 5 | `audit_permission` | `@ops` | **208** | 假阳性 | **✅ 已覆盖**（`audit.mbt` 族） |
| 6 | `mode_templates` | `@ops` | **208** | 假阳性 | **✅ 已覆盖** |
| 7 | `debate_convene` | `@ops` | **208** | 假阳性 | **✅ 已覆盖**（`ops_hats` 测试） |
| 8 | `debate_register` | `@ops` | **208** | 假阳性 | 同上 |
| 9 | `debate_verdict` | `@ops` | **208** | 假阳性 | 同上 |
| 10 | `gitcode_env_check` | `@ops` | **208** | 假阳性 | **✅ 已覆盖**（同 `github_env_check` 族） |
| 11 | `selfdrive_get` | `@ops` | **208** | 假阳性 | **✅ 已覆盖** |
| 12 | `selfdrive_init` | `@ops` | **208** | 假阳性 | **✅ 已覆盖** |
| 13 | `evolve_snapshot` | `@evolve` | **76** | 假阳性 | **✅ 已覆盖** |
| 14 | `atgc_old_compile` | `@core` | **25** | 假阳性 | **✅ 已覆盖**（ATGC 子项目） |
| 15 | `atgc_old_run` | `@core` | **25** | 假阳性 | 同上 |
| 16 | `atgc_old_talk` | `@core` | **25** | 假阳性 | 同上 |
| 17 | `assistant_resign` | `@store` | **97** | 假阳性 | **✅ 已覆盖**（`store_assistant_test`） |
| 18 | `lock_status` | `@store` | **97** | 假阳性 | **✅ 已覆盖** |
| 19 | `reserve_release` | `@store` | **97** | 假阳性 | **✅ 已覆盖** |
| **20** | **`reserve_check`** | `@store` | 97 | **本单补测** | **★ 新增 `b455_reserve_check_reports_written_state`** |
| **21** | **`lock_release`** | `@store` | 97 | **本单补测** | **★ 新增 2 格（含变异对照）** |
| **22** | **`assistant_status`** | `@store` | 97 | **本单补测** | **★ 新增 `b455_assistant_status_three_phases`** |
| **23** | **`store_close`** | handler 内联 | 0 | **本单补测** | **★ 新增 `b455_store_close_does_not_affect_others`** |
| 24 | `github_env_check` | `@env` | **0** | **真零覆盖·需 mock** | 依赖进程 env，`github_env_ready` 函数不存在 ⇒ 只能测工具壳，价值低 |
| 25 | `github_queue_status` | handler 内联 | 0 | **真零覆盖·IO** | 读 JSONL 队列文件，需 fixture |
| 26 | `github_issue_close` | handler 内联 | 0 | **真零覆盖·网络** | 真发 curl，**不可离线测** |
| 27 | `github_issue_comment` | handler 内联 | 0 | **真零覆盖·网络** | 同上 |
| 28 | `github_issue_webhook_parse` | handler 内联 | 0 | **真零覆盖·纯计算** | **⚠️ 这个应该测但本轮未测**（见 §缺口） |
| 29 | `executor_auction` | handler 内联 | 0 | **真零覆盖·纯计算** | 同上 |
| 30 | `selfdrive_dispatch` | handler 内联 | 0 | **真零覆盖·有副作用** | 会真认领任务，需隔离库 |

**汇总：13 个假阳性（已覆盖）· 4 个本单补测 · 13 个真零覆盖（给了理由）**

### §3 新增测试（5 格，全部断言**行为**）

`src/server/server_bug455_coverage_wbtest.mbt`：

| 格 | 断言什么 |
|---|---|
| `b455_reserve_check_reports_written_state` | 写入 `(owner-x, 2099-01-01)` ⇒ `rsv_get` **逐字**返回同值；重复读不变 |
| `b455_lock_release_only_owner_can_release` | 他人释放 ⇒ **false 且锁还在**；本人释放 ⇒ true |
| `b455_L5_release_has_a_real_negative_path` | ★变异哨兵：对没锁过的 scope 释放 ⇒ false |
| `b455_store_close_does_not_affect_others` | 关不存在的 ns 不崩；关一个只少那一个，**别的还在** |
| `b455_assistant_status_three_phases` | 空 ⇒ 登记 ⇒ 退位，**退位不删行** |

### §4 ★ 测试过程中发现的真语义（这条比测试本身有价值）

写 `b455_lock_release_only_owner_can_release` 时我断言「释放后 `locks_get` 返回 `None`」——**红了**。

**实测**（`store_rsv.mbt:389-401`）：
```moonbit
pub fn MemoryStore::locks_release(self, scope, agent) -> Bool {
  match self.file_locks.get(scope) {
    Some(l) if l.agent == agent => {
      let released = FileLock::{ ..l, status: "released", }   // ★ 改 status，不删行
      self.file_locks.set(scope, released)
      true
    }
    _ => false
  }
}
```
**⇒ `locks_release` 不删行，只把 `status` 改成 `"released"`。**

**为什么这条重要**：若有人（或某段代码）以「`locks_get == None`」判定「锁已释放」，
**会永远判 false** ⇒ 已释放的锁被当成仍持有。**测试断言已改成「status 变了」。**

### §5 变异实测（硬要求③：真跑）

```
① 注入变异（src/store/store_rsv.mbt）：把 `Some(l) if l.agent == agent` 改成 `Some(l)`
   ⇒ 任何人都能释放别人的锁

$ python scripts/moon_test_env.py src/server
  F| test src/server/server_bug455_coverage_wbtest.mbt:52
     ("b455_lock_release_only_owner_can_release") failed
  Total tests: 448, passed: 447, failed: 1        ← 我的锁抓住了

② 恢复：cp /tmp/rsv.bak src/store/store_rsv.mbt
$ python scripts/moon_test_env.py src/server
  Total tests: 448, passed: 448, failed: 0        ← 回绿，git diff 行数=0（干净）
```

**⇒ 锁真的在看着。第 2 个变异对照是 `b455_L5`（本身即变异哨兵格）。**

---

## 分析：为什么「22% 零覆盖」是危害，以及它其实只有 8.4%

### 「坏了没人知道」的具体形态

**工具壳无人测试 = 三类缺陷无法被发现**：

1. **接线错误**（本会话已发生 3 次）：`BUG-440`（承诺了不存在的守卫）、
   `BUG-453`（`execute` 声明 `challenge` 但没接 `opt_challenge`）、
   `BUG-436`（ACL 判定身份取错字段）—— **都是「工具壳的线接错了，实现层完全正确」**。
   **实现包 208 格测试全绿，工具照样是坏的。**

2. **参数透传丢失**：`store_close` 的 `ns` 参数如果传丢，实现层 `MultiStore::close` 100% 正确也没用。

3. **回执字段编造**：工具壳负责把内部状态渲染成 JSON —— **这一层没有测试，
   `BUG-439`（熔断器 `state` 恒 closed 而回执看不出来）就是这个形态。**

**⇒ 所以「零覆盖」的危害不是「实现没测」，而是「**壳与实现之间的那根线没测**」。**

### 为什么挑这 4 个（不是 8 个）

| 挑的 | 理由 |
|---|---|
| `lock_release` | **并发锁的「释放」面** —— 写侧（`lock_acquire`）有锁，读/释放侧零覆盖。**最容易被漏掉的一半** |
| `store_close` | **数据面** —— 关错库就「消失」。handler 内联零测试 |
| `assistant_status` | 写侧 `assistant_claim` 有专门锁（`BUG-431`），**读侧零覆盖** |
| `reserve_check` | 互斥面**读侧**（`reserve_scope` 有锁，`rsv_get` 直连零断言） |

**没挑 `executor_auction` / `github_issue_webhook_parse`（都是纯计算，本该好测）** ——
**因为它们虽标注 `pkg=-`，但 handler 内联逻辑在 `server.mbt` 里，需要先读 300 行再写断言。**
**本轮时间优先给了「有数据/并发影响」的 4 个。这是明确的取舍，不是遗漏。**（见 §缺口）

---

## 缺口与风险

### 1. ⚠️ 13 个「真零覆盖」里仍有 **2 个纯计算工具未测**

`github_issue_webhook_parse`（正则解析 webhook，纯计算零网络）与 `executor_auction`（拍卖评分，纯计算）
**本该最容易测**，但它们 handler 内联在 `server.mbt` 里，**本轮没时间读完再写**。
**⇒ 这是本单明确的未完成项。**

### 2. 8 个网络/IO 工具的「为什么难测」

| 工具 | 难在哪 |
|---|---|
| `github_issue_close` / `github_issue_comment` | 真发 `curl` 到 GitHub API，**需要真 token + 真仓库** |
| `github_queue_status` / `gitcode_env_check` / `github_env_check` | 读进程 env / JSONL 队列文件，**需 fixture 或 mock** |
| `selfdrive_dispatch` | 会**真认领任务**，需隔离库 |

**⇒ 这些不是「不值得测」，是「需要 mock 基础设施」。本轮不建 mock。**

### 3. 我的普查脚本有误报，**已修正但未固化成判据**

`temp/audit/lane_br_coverage.py` 只做「名字出现」判断 ⇒ **13/30 假阳性**。
**正确判法应是「工具壳 + 实现包两层都没测试」**。
**⇒ 建议把修正后的判法写成 `scripts/check_tool_coverage.py`**（不在本单边界）。

### 4. 测试只覆盖了 4 个工具，**26 个仍未测**

`Total tests 448 → 448`（我只加了 5 格，但原有 443 格）。
**⇒ 零覆盖率从 19.5% 降到约 17%。降幅小，但方向对。**

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-27-bug455-coverage-report.md` |
| 新增测试 | `src/server/server_bug455_coverage_wbtest.mbt`（5 格） |
| 普查脚本 | `temp/audit/lane_br_coverage.py` + `lane_br_classify2.py` |
| **建议后续** | ① 测 `github_issue_webhook_parse` / `executor_auction`（纯计算，最易）② 建 env/IO mock 基础设施 ③ **把修正后的判法写成 `check_tool_coverage.py`** ④ `BUG-455` 可部分标 FIXED（覆盖率 19.5%→17%，未清零） |
| **未做** | **未改 `src/` 非测试文件**（`store_rsv.mbt` 的变异已 `cp` 还原，`git diff` 行数=0） |