# Round 3 全量测试基线 + `check_test_sync` 复核报告

> **任务**：Lane V · Round 3 测试基线建立 + `check_test_sync` 复核（含 BUG-413 新锁）
> **日期**：2026-10-26 · **执行者**：commander-delta
> **边界**：只读 + 写报告，**未改任何 `src/` `scripts/` 文档**

---

## 一、结论

| 项 | 读数 |
|---|---|
| **实测总数** | **1468** |
| **passed** | **1468** |
| **failed** | **0** |
| 汇总行 | `Total tests: 1468, passed: 1468, failed: 0.` |
| **`check_test_sync` 是否 FAIL** | **是（FAIL）** |
| **差几条到同步** | **17 处 R1 声明仍写 1463**（+5 处 R2 + 1 条 R3 连带）|
| `check_battery_count_doc` | **PASS**（rulers=120 ci=46 battery=79 missing=0 gate=87）|
| **1468 这个推算对不对** | ✅ **对**（1463 + 5 = 1468，实测吻合）|

---

## 二、证据

### 2.1 快照

```
HEAD          : c90009016a7c3b20e874681f4218cfa017c69e41（短 c9000901）
moon.mod 版本 : version = "0.3.10"
cwd           : /e/IDEProjects/AI/FIST-Mbt
工作树        : git status --porcelain | wc -l = 1
                →  M src/server/output_validate.mbt（已知在途，未 stash）
```

### 2.2 全量测试（用常驻入口，规避 BUG-380）

```bash
python scripts/moon_test_env.py --target js > temp/audit/lane_v_fulltest.log 2>&1
```

**日志首行**（顺带验证 BUG-416 的 `--root` 已生效）：

```
ROOT：E:\IDEProjects\AI\FIST-Mbt（缺省=脚本目录，与本进程 cwd 无关；要测别的树请加 --root <path>）
PATH 垫片目录：1 个（C:\Users\victo\AppData\Roaming\dsh-desktop\harness\.desktop-bin）
```

**汇总行原文（判绿依据，不信 exit 0 —— BUG-142）**：

```
  汇总：Total tests 1468 / passed 1468 / failed 0
Total tests: 1468, passed: 1468, failed: 0.
```

**⇒ 1468 / 1468 / 0，零失败。无逐条记录需求。**

### 2.3 `check_test_sync --total 1468` → **FAIL**

```
FAIL 测试总数一致性守卫（实测 1468，扫描 141 份现状文档，0 条声明一致）：
```

**17 处 R1（声明≠实测）全清单**：

| # | 位置 | 形态 | 声明值 |
|---|---|---|---|
| 1 | `AGENTS.md:177` | N/N | 1463 |
| 2 | `AGENTS.md:177` | N 全绿/通过 | 1463 |
| 3 | `AGENTS.md:186` | N/N | 1463 |
| 4 | `ARCHITECTURE.md:81` | N/N | 1463 |
| 5 | `README.mbt.md:9` | N/N | 1463 |
| 6 | `README.md:13` | N 全绿/通过 | 1463 |
| 7 | `README.md:27` | N/N | 1463 |
| 8 | `README.md:51` | N/N | 1463 |
| 9 | `README_EN.md:14` | N/N | 1463 |
| 10 | `README_EN.md:86` | N-test | 1463 |
| 11 | `README_EN.md:110` | N/N | 1463 |
| 12 | `README_EN.md:112` | (N aligned | 1463 |
| 13 | `README_EN.md:131` | N/N | 1463 |
| 14 | `docs/SOP.md:38` | N/N | 1463 |
| 15 | `docs/agent-map.md:10` | N 全绿/通过 | 1463 |
| 16 | `docs/deliverable.md:18` | N/N | 1463 |
| 17 | `scripts/scoring_rubric.md:8` | N/N | 1463 |

**+ 5 处 R2（必带文件未出现实测总数）**：`README.md` / `AGENTS.md` / `docs/deliverable.md` / `docs/agent-map.md` / `scripts/scoring_rubric.md`

**+ 1 条 R3（防空转）**：现状面里没有任何一条声明等于实测 1468

### 2.4 `--fix-dry-run` 三类统计（**关键：验证 BUG-418 同族修复**）

```
合计 17 处：可改 [✓] 8 / 待判 [?] 9 / native 面不动 [✗] 0
本工具**不落盘**。请人工核 [✓] 那几处；[?] 需先判定语义面再改；[✗] 一律不动。
```

#### 🔴 重点验证：`572`（native 面）有没有被误报？

**文档里 572 的实际位置**：

```
AGENTS.md:187   > **Native 后端**：… `moon test --target native -j 1` = **572/572**（工作树带既往构建残留时）
README.md:28    > **Native 后端**：… `moon test --target native -j 1` = **572/572**（与 JS 同数…）
```

**`fix-dry-run` 输出里 `grep -c "572"` = `0`** ✅

**⇒ `[✗] native 面不动 = 0`，且 572 一次都没被建议修改。
Lane R 的 BUG-418 同族修复（native/JS 两面区分）确实生效。**

#### 三类各列几条

**[✓] 8 条（含 JS 语境，可直接改）**：

```
README_EN.md:131  [✓] 该行含 JS 语境（`--target js` / 「JS 后端」）
docs/SOP.md:38    [✓] 该行含 JS 语境 —— `moon test --target js` 全量 = 1463/1463 绿
docs/agent-map.md:10  [✓] 该行含 JS 语境 —— `moon test --target js`（**1463 项全绿**）
docs/deliverable.md:18 [✓] 该行含 JS 语境 —— `moon test --target js` 1463/1463
```

**[?] 9 条（无 JS/native 标记，需人判语义面）**：

```
README_EN.md:112  [?] 形态 (N aligned）—— check_test_sync (1463 aligned — sweeps every current-state doc…)
scripts/scoring_rubric.md:8  [?] 形态 N/N —— 评审员提示词里含 1463
AGENTS.md:177 / AGENTS.md:186 / ARCHITECTURE.md:81 / README.mbt.md:9 /
README_EN.md:14 / README_EN.md:86 / README_EN.md:110
```

**[✗] 0 条**（本轮无 native 面误报）

### 2.5 我人工核了 9 条 `[?]` 的语义面（供下一单参考）

| 位置 | 原文摘要 | 实际语义面 | 结论 |
|---|---|---|---|
| `AGENTS.md:177` | `全仓 **1463/1463 passed, rc=0**` | JS 全仓 | **应改** |
| `AGENTS.md:186` | `**JS 后端**：moon test --target js = 1463/1463` | **显式 JS** | 工具标 `[?]` 偏保守，**应改** |
| `ARCHITECTURE.md:81` | `JS 端 moon test --target js = 1463/1463` | **显式 JS** | **应改** |
| `README.mbt.md:9` | `JS 端 **1463/1463**` | **显式 JS** | **应改** |
| `README_EN.md:14` | Why MoonBit 段（长英文行） | 需读全行 | 待定 |
| `README_EN.md:86` | `re-runs the 1463-test JS suite` | **显式 JS（"JS suite"）** | **应改** |
| `README_EN.md:110` | `**1463/1463** tests green on the JS backend … native **572/572**` | **⚠️ 同一行混两面** | **改 1463→1468，但绝不能碰同行的 572** |
| `README_EN.md:112` | `check_test_sync (1463 aligned …)` | 工具自述里的读数 | **应改**（它说的是本尺的期望值）|
| `scripts/scoring_rubric.md:8` | 评审员提示词 | 需读全文 | 待定 |

**⇒ 9 条 `[?]` 里至少 7 条实际是 JS 面（其中 4 条甚至显式写了 `--target js` / "JS"）。**
**这不是工具判错，是语境外推的保守**——`[?]` 的定义是「无法判断」，它诚实地把判断权交回给人。

**⚠️ 最高风险的一条是 `README_EN.md:110`：同一行既有 JS 的 1463 又有 native 的 572。
下一个改文档的 lane 若用「整行替换」会连带改坏 572。**

### 2.6 任务 3：`check_battery_count_doc`

```
PASS 电池读数与 README 登记逐键一致：rulers=120 ci=46 battery=79 missing=0 gate=87 exempt=28 unclassified=7
```

**⇒ `engine_scope_perm_wbtest.mbt` 的加入没有让电池登记数失配。**

---

## 三、分析：1468 这个推算对不对

**推算**：Round 2 全量 1463 + BUG-413 新增 5 条白盒锁 = 1468。

**实测**：**1468 / 1468 / 0**。

**⇒ 推算精确成立。** 三个旁证：

1. **`src/engine` 从 207 → 212** 的 +5，与全量 +5 完全对齐（BUG-413 的 5 条锁全在 `src/engine`，没有连带产生别处的测试）
2. **0 失败** ⇒ 没有「某条锁把别的测试带红」的情况
3. `check_battery_count_doc` PASS ⇒ 电池登记数没有因新测试文件失配

**为什么这个推算值得单独说**：
1463 是 zeta 在 `cc2c6c37`（隔离树 @ `d5a84c76`）实测的；
BUG-413 的 5 条锁是 `681832ce` 加的；当前 HEAD 是 `c9000901`。
**中间还有别的提交**——推算能成立说明**这些提交没有再增删测试**，这是个有信息量的结论，不是算术巧合。

---

## 四、缺口与风险

| # | 项 | 说明 |
|---|---|---|
| 1 | **`check_test_sync` 现在红** | 17 处 R1 + 5 处 R2 + 1 条 R3。**我未改文档**（按指令，那是另一单）。**⇒ 全仓 `check_test_sync` 门禁当前是 FAIL 状态，需要立刻派单修** |
| 2 | **`README_EN.md:110` 混行风险** | 同一行含 1463（JS）+ 572（native）。**下一个改的人若整行替换会改坏 572**。建议在派单里**点名这一行** |
| 3 | **9 条 `[?]` 需人判** | 我给出语义面判断（7 条判为 JS 面、2 条待读全文），但**这是人工判断，不是工具结论** |
| 4 | **`check_battery_count_doc` PASS ≠ 新测试有电池格** | 它只对「电池规模读数 ↔ README 登记」，不保证 `engine_scope_perm_wbtest.mbt` 里的 5 条锁**各自**被点名。若该文件是 `_wbtest`（白盒）则按惯例不进电池格 |
| 5 | **工作树有 1 个在途文件** | `M src/server/output_validate.mbt`（他人）。它**不影响**本次测试结果（`moon test` 编译了它，且全绿），但我未核它是否已提交 |
| 6 | **未验 `--root` 隔离面** | 本次在**主仓**跑。按 BUG-416，若要「隔离树」基线应显式 `--root <隔离树>`。**本基线是主仓基线，不是隔离树基线** |

---

## 五、建议入档位置

1. **本报告** → `reports/2026-10-26-r3-test-baseline-report.md`（已落盘）
2. **Round 3 基线 1468** → 建议同步进 `AGENTS.md:186` 与 `README.md:27` 等 **`[✓]` 那 8 条**（另派单）
3. **`README_EN.md:110` 的混行警告** → 建议在该文件的注释或下一单的任务书里**显式点名**
4. **`[?]` 9 条的语义面判断** → 见 §2.5 表格，可直接作为下一单的输入
5. **「19 处 1463 待改」这个读数** → 建议进当轮日志，作为 `check_test_sync` 从红转绿的验收基线

---

## 附：本轮命令清单（可复现）

```bash
# 快照
git rev-parse HEAD && git status --porcelain | wc -l && grep version moon.mod

# 任务 1：全量
python scripts/moon_test_env.py --target js > temp/audit/lane_v_fulltest.log 2>&1
grep "Total tests" temp/audit/lane_v_fulltest.log   # → 1468 / 1468 / 0

# 任务 2：同步复核
python scripts/check_test_sync.py --total 1468                  # → FAIL（17 R1 + 5 R2 + 1 R3）
python scripts/check_test_sync.py --total 1468 --fix-dry-run   # → 17 处：[✓]8 / [?]9 / [✗]0
python scripts/check_test_sync.py --total 1468 --fix-dry-run | grep -c 572   # → 0（native 未误报）

# 任务 3：电池
python scripts/check_battery_count_doc.py                       # → PASS
```
