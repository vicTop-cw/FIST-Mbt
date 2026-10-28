# 假绿报告校正 + 两条门禁红线收口（lead · 见缝插针单）

> **任务**：在另一 agent 占着 `src/server` / `src/engine` / `src/store` 主线（BUG-430 S3 第七段）期间，
> 取**不与其重叠**的缝：报告口径面 + 两条独立门禁。
> **执行人**：lead · **日期**：2026-10-28 · **账本**：BUG-457 · **味道**：阿里（口径不是修复）

---

## 结论

| 项 | 结果 |
|---|---|
| **BUG-457** | ✅ 建档 → 校正 → 标 FIXED（同一笔落证据） |
| **报告 §4 作废** | ✅ `reports/2026-10-27-tool-coverage-judge-report.md` 加「追记（BUG-457）」，顶部两行加作废标记 |
| **核心事实** | ✅ §4 声称的 `src/server/server_bug455_pure_wbtest.mbt` **在任何分支历史上都不存在**（`git log --all` 空） |
| **门禁 1** | ✅ `check_text_control_chars.py` FAIL → **PASS**（`reports/2026-10-28-dist-refresh-report.md` 一处 0x0c） |
| **门禁 1 连带** | ✅ `check_selftest_inventory_doc.py` 的 X4 FATAL（`check_text_control_chars --selftest` 实回 rc=4）随之**转 clean** |
| **门禁 2** | ✅ `check_bug_reference_integrity.py` J1 悬空注释面 1 → **0**，PASS |
| **没做什么** | ❌ 没有补写那 4 格测试去「把声称变成真的」—— 那会让下一个读报告的人以为当时真测过；真实覆盖由同日 lane 文件承接，以判据读数为准 |
| **没碰什么** | `src/server/server.mbt` / `src/engine` / `src/store` / `tool_cov_lane_*`（另一 agent 的在飞面，一行未改） |

---

## 证据

### §1 判「从未落盘」与「回滚」是两件事（本单的方法面）

只跑 `ls` 分不出「没做」和「做完被回滚」。本单用 `git log --all -- <path>` 做二分：

```text
$ git log --all --oneline -- src/server/server_bug455_pure_wbtest.mbt
(空)

$ git log --all --oneline -- src/server/bug335_ns_route_wbtest.mbt
ff56709b Revert "test(r29): 提交 BUG-335 配套回归锁 bug335_ns_route_wbtest.mbt…"
c33bb361 test(r29): 提交 BUG-335 配套回归锁 bug335_ns_route_wbtest.mbt…
```

| 形状 | 判法读数 | 结论 |
|---|---|---|
| 从未存在 | `git log --all` **空** | 声称无制品 ⇒ **假绿** |
| 提交后 revert | `git log --all` **有提交点** | 当时为真，今天引用是**陈旧引用** |

⇒ 同一批「报告引用了不存在的测试文件」的 25 个命中里，只有本例是「从未落盘」；
`bug335_ns_route_wbtest.mbt`（27 处引用）属于**回滚**，不按假绿处理。
**把两种形状混为一谈，会让下一个人去删一份本来正确的报告。**

### §2 两条门禁的「改前 / 改后」真读数

```text
# 改前（同一棵树上实跑）
FAIL check_text_control_chars.py
  VIOLATION reports\2026-10-28-dist-refresh-report.md :: 共 1 处，首个 0x0c 在第 81 行第 123 字节列
FAIL check_bug_reference_integrity.py
  J1 src/server/bugreport.mbt:84 (BUG-999) // 拿它做「是不是条目」的判据 ⇒ `## BUG-999 [x] [medium]`…
FAIL check_selftest_inventory_doc.py
  FATAL: X4 自述失联 1 处：X4 scripts\check_text_control_chars.py …--selftest 实回 rc=4

# 改后
PASS check_text_control_chars.py            → 扫描面 1591 份 · 违例 0 处
PASS check_text_control_chars.py --selftest → SELFTEST OK: 9 格（G×4 / M×3 / R×2）
PASS check_bug_reference_integrity.py       → J1 悬空-注释面 0 条（上限 0）
PASS check_selftest_inventory_doc.py        → INVENTORY_SYNC=clean 判定族 59 条逐一对表通过
```

### §3 两处改动为什么这么改（不是「让判据闭嘴」）

| 文件 | 改法 | 为什么不是降标准 |
|---|---|---|
| `reports/2026-10-28-dist-refresh-report.md:81` | 0x0c 还原成 `\f`（路径 `%LOCALAPPDATA%\FIST-Mbt\fist-mbt.js`，与本报告第 12 行的规范路径一致） | 是**修复文本**，不是例外放行；路径本身在两处变得一致 |
| `src/server/bugreport.mbt:84` | 示例编号 `BUG-999` → `BUG-NNN`，并写明「示例若要可点就必须先入账，不值得为一个举例造一条假 BUG」 | 判据是对的（注释里的 `BUG-<数字>` 会被当引用去查账）；改的是**示例**，不是判据上限 |

### §4 覆盖读数（引用就别凭记忆）

```text
python scripts/check_tool_coverage.py
[A 外壳面] 有覆盖 150 / 154
  外壳零覆盖 4 个：assistant_resign / github_issue_close / github_issue_comment / lock_status
[B 实现面] 已映射 15 个，其中实现函数在测试里出现 15 个
[结论] 外壳零覆盖 4 / 154（2.6%）
```

**这四个未覆盖项是当前真实的待办清单**（判据本体在电池里是 `known-red expect=1`；
补完后 rc 会变 0、该格会转红，逼下一个人把期望改成 0 —— 那是本文件自订的律，不是本单能顺手改的）。

---

## 缺口与风险

1. **那 4 格测试仍然不存在**。本单只校正了口径，没有、也不应该替它「补成真的」：
   - 若补在 `src/server/`，会与在飞的 lane 文件重复；
   - 更关键：**补写≠当时测过**，把追记改回「✅」会二次制造假绿。真实覆盖只认判据读数。
2. **`reports/` 里仍有一批「回滚型陈旧引用」**（如 `bug335_ns_route_wbtest.mbt` 27 处）。
   它们**不是假绿**，但下一个人按文件名去找会扑空 ⇒ 建议后续做一次「回滚清单 ↔ 报告引用」对表（未做）。
3. **电池本轮仍是 15 红**（111 格）。与本单相关的 3 格已转绿；其余多为在飞面
   （`output_validate.mbt:210` 硬编码路径 = 另一 agent 的 WIP）与预存红，本单不动。
4. **未跑 `moon fmt`**：本次 `.mbt` 改动**只加注释行**，不触发格式差异；融合仓里另一 agent 有在飞未格式化文件，
   全局 `moon fmt` 会把不属于我的改动一起重排 —— 那正是「提交纪律」要避免的形状。

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-28-report-claim-and-ledger-repair.md` |
| 被校正的报告 | `reports/2026-10-27-tool-coverage-judge-report.md`（文末「追记（BUG-457）」+ 顶部两行作废标记） |
| 账本 | `memory/bugs.md`（BUG-457：OPEN → FIXED，同一笔落 `### FIXED` 小记） |
| 门禁修复 | `reports/2026-10-28-dist-refresh-report.md:81`、`src/server/bugreport.mbt:84` |
| **建议后续** | ① 覆盖清单最后 4 个工具（谁做谁负责把电池期望翻到 0）② 「回滚清单 ↔ 报告引用」对表 ③ 报告写作自查三条已写进被校正报告文末 |
