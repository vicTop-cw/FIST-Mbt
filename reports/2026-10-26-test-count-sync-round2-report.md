# Lane R · 1460 → 1463 同步 + `--fix-dry-run`（含事故记录）

- **日期**：2026-10-26
- **执行人**：司令-ε（Lane R）
- **模式**：Round 2 —— `check_test_sync` 第二次因测试数变动 FAIL

---

## 一、结论

| 项 | 结果 |
|---|---|
| **21 处 1460 → 1463 同步** | ✅ 完成（9 文件） |
| `check_test_sync --total 1463` | ✅ **PASS**（17 条声明全部等于实测） |
| `--fix-dry-run` 可用且幂等 | ✅ 两次输出完全相同；`SUGGEST 无需改动` |
| `--fix-dry-run` 不落盘 | ✅ 实证（md5 未变） |
| `--selftest` | ✅ **PASS 32 变体**（含 4 格新格，其中 1 格用真实 AGENTS.md） |
| 两个面都核对 | ✅ **js = 1463 / native = 572**（全库 572 文件数 22 → 22 零变化） |
| `moon check --target js` | ⚠️ 1 error，**在 `src/engine/engine_scope_perm_wbtest.mbt:86`（他人改动）**，与本单无关 |

---

## 二、事故记录（**必须先说这个**）

### 2.1 发生了什么

第一版 `--fix`（写盘版）被我用来做「21 处同步」。它跑完后我一看输出，**当场发现越界**：

```
FIX AGENTS.md:187 572 → 1463（N/N）         ← native 面！
FIX README.md:28  572 → 1463（N/N）         ← 同上
FIX BACKLOG.md:16 811 → 1463（N/N）         ← 历史任务读数
FIX BACKLOG.md:17 737 → 1463（N/N）
FIX BACKLOG.md:21 807 → 1463（N/N）
FIX BACKLOG.md:27 295 → 1463（N/N）
FIX BACKLOG.md:41 50  → 1463（N/N）
FIX BACKLOG.md:52 86  → 1463（N/N）
FIX BACKLOG.md:53 62  → 1463（N/N）×2
FIX README.md:290 77  → 1463（N/N）
FIX README.md:293 162 → 1463（N/N）
FIX docs/SHIP-PLAN-BLACKBOX-v2.md:34/219/377 1058 → 1463
...
```

**波及 19 个文件 / 40+ 处**。

### 2.2 处置

```bash
git checkout -- <这 19 个文件>
```

**零提交、零推送**。工作树当场恢复。发现 → 回滚 → 上报，全程未让错误内容进入任何 commit。

### 2.3 根因：**权限级别搞错了，不是笔误**

`collect_claims()` 报出的 `num` 是「**行内任意**一个带 `测试/test/全绿` 关键词的数字」，
**不是「总数」**：

```python
if not RX_KEY.search(line):        # RX_KEY = (测试|用例|全绿|passed|test)
    continue
for m in RX_PAIR.finditer(line):   # 这一行里所有 N/N
    hits.append((m.group(1), "N/N", ln))
```

**`judge()` 用它没问题** —— 它只拿 `num` 与 `total` 比，不等就报
`R1 ... 声明 572 ≠ 实测 1463`，**报红了让人去看**，那是对的（572 确实是「声明」，
只是不是「总数声明」，需要人判断）。

**但 `--fix` 用它写盘就是灾难** —— 因为「像声明的数字」与「该改的数字」不是同一集合。

> **判据「报红让人看」与「自动改」是两种权限级别。**
> 我把只读判据的结论直接当成了可写指令 —— 这是**越权**，不是 bug。

具体例：`AGENTS.md:187` 那句是「**Native 后端** … `moon test --target native -j 1` = **572/572**」，
`RX_KEY` 因为同一行里有 `moon test` 而命中，于是 572 被当成总数。

### 2.4 为什么我的自证格没抓到（**最该反省的一点**）

我写了 3 格 selftest，**全部通过**，包括变异对照格。但它们的输入**全是合成句**：

```python
_shapes = [("N/N", "测试 **1460/1460** 全绿"), ("N 全绿", "1460 项测试全绿"), ...]
```

**没有一个格喂「`572/572` native」这种「形态像声明但语义不是总数」的真实反例。**

> **我的 selftest 证明的是「我设计的输入能被我处理」，没有证明「真实语料里不会误伤」。**

**这正是我自己在判例-62 里写过的句子，我在自己的自证格里复发了。**

---

## 三、判例稿（判例-63）

> ### 判例-63 · 写盘类工具的失败是**静默蔓延**的，它的自证门槛必须比只读判据高一档
>
> **两种权限级别**：判据「报红让人看」与「自动改」不是同一个东西。
> 只读判据判错只影响一次读数（人还会来看）；**写盘类工具判错会静默改写整个仓库**。
> ⇒ 任何 `--fix` / `--update` / `--apply` 的**边界必须比它的只读判据更严**，不是复用同一份。
>
> **任何写盘类工具的 `--selftest`，必须至少有一格是「从真实语料里摘出来的脏样本」**，
> 不许全部用合成句。因为：
> - 只读判据的失败 = 一次错误读数（下次还能发现）
> - **写盘类工具的失败 = 静默蔓延**（没人会去 review 40 处"看起来只是数字变了"的 diff）
>
> **本仓实证（2026-10-26）**：`--fix` 第一版的 3 格自证全用合成句、全部通过；
> 一碰真实文档就误伤 19 文件 40+ 处 —— 把 native 面 `572` 与历史读数 `811/737/807` 当成 JS 总数。
>
> **配套硬要求**：
> 1. **优先不给写盘路径**。`--fix` 降级为 `--fix-dry-run`（只建议、带证据、无 `--force`）。
>    人工确认挡不住自动化误判 —— 一屏 21 条会让人条件反射按 y。
> 2. **建议清单必须与判据共用同一组边界**（历史面 / 围栏块 / 声明形态 / **EXEMPT 豁免** / **语义面**）——
>    少一条就会制造噪声：本轮实测漏了 EXEMPT 一条，判据 PASS 时建议清单仍报 41 处已豁免项。
> 3. **判不准时必须显式说「不确定」**（`[?]`），不许默认猜一个方向。

---

## 四、21 处逐条对照

| # | 文件:行 | 前 | 后 | 语义面 |
|---|---|---|---|---|
| 1 | `README.md:8` | `tests-1460%2F1460` | `tests-1463%2F1463` | 徽章（js） |
| 2 | `README.md:13` | `1457 项测试全绿` → 上轮已改 1460 | `1463` | js |
| 3 | `README.md:27` | `= **1460/1460**` | `**1463/1463**` | js |
| 4 | `README.md:51` | `→ 1460/1460 零回归` | `1463/1463` | js |
| 5 | `README.md:122` | `Total tests: 1460, passed: 1460` | `1463, passed: 1463` | js 日志回显 |
| 6 | `AGENTS.md:177` | `全仓 **1460/1460 passed` | `**1463/1463 passed` | js（全量） |
| 7 | `AGENTS.md:186` | `= **1460/1460**（…四模式流水线` | `**1463/1463**` | js |
| 8 | `AGENTS.md:211` | `本轮 1460/1460` | `1463/1463` | js |
| 9 | `README_EN.md:9` | `tests-1460%2F1460` | `tests-1463%2F1463` | 徽章（js） |
| 10 | `README_EN.md:14` | `pass **1460/1460 tests` | `**1463/1463**` | js |
| 11 | `README_EN.md:26` | `Total tests: 1460, passed: 1460` | `1463, passed: 1463` | js 日志回显 |
| 12 | `README_EN.md:86` | `the 1460-test JS suite` | `1463-test` | js |
| 13 | `README_EN.md:110` | `- **1460/1460** tests green` | `**1463/1463**` | js |
| 14 | `README_EN.md:112` | `(1460 aligned` | `(1463 aligned` | js |
| 15 | `README_EN.md:131` | `1460/1460 measured` | `1463/1463` | js |
| 16 | `README.mbt.md:9` | `JS 端 **1460/1460**` | `**1463/1463**` | js |
| 17 | `ARCHITECTURE.md:81` | `JS 端 … = 1460/1460` | `= 1463/1463` | **仅 JS 段**，native 段 `572/572` 未动 |
| 18 | `docs/SOP.md:38` | `全量 = 1460/1460 绿` | `1463/1463` | js |
| 19 | `docs/agent-map.md:10` | `**1460 项全绿**` | `**1463 项全绿**` | js |
| 20 | `docs/deliverable.md:18` | `1457/1457` → 上轮已改 1460 | `1463/1463` | js |
| 21 | `scripts/scoring_rubric.md:8` | `（1460/1460，含 quickcheck）` | `（1463/1463` | js |

**每改一处都念过「这个数对应哪个面」。** `ARCHITECTURE.md:81` 是唯一的**同行双面**——
该行既有 `JS 端 … = 1460/1460` 又有 `Native 端 … 同为 572/572`，**只改了 JS 那半**。

---

## 五、两个面都核对（统帅要求的回报）

```
① AGENTS.md:187      Native 后端 … = **572/572**                    ✅ 未动
② ARCHITECTURE.md:81 JS 端 = 1463/1463（2026-10-26；Native … 同为 572/572  ✅ 双面各自正确
③ README.md:28       572/572                                        ✅ 未动
④ README_EN.md:110   572/572                                        ✅ 未动
⑤ 全库含 572 的 .md 文件数：改前 22 → 现在 22                        ✅ 零变化
⑥ 现状面 9 文件的 1463 出现数：21 处（改前 1460 也是 21 处）          ✅ 一一对应
```

---

## 六、`--fix-dry-run` 三件验证

### 6.1 只建议、不落盘（实证）

```
$ md5sum AGENTS.md      → BEFORE
$ python scripts/check_test_sync.py --total 1463 --fix-dry-run
SUGGEST AGENTS.md:177  1460 → 1463  [?] 该行既无 JS 标记也无 native 标记 ⇒ 无法判断…
$ md5sum AGENTS.md      → AFTER
✅ dry-run 后文件 md5 未变 = 不落盘
```

### 6.2 语义面判别（native 护栏）

事故那一处现在的输出：

```
SUGGEST AGENTS.md:187  572 → 1463  [✗] 该行含 native 语境（`--target native` / 「Native 后端」）
                                       ⇒ native 面 ≠ JS 面，建议不改
```

**事故点现在被显式标成 `[✗]`。**

### 6.3 幂等 + 豁免面

```
$ python scripts/check_test_sync.py --total 1463 --fix-dry-run   # 连跑两次
两次输出 md5 完全相同 ✅
SUGGEST 无需改动：现状面已全部等于实测 1463
```

**修复了一个新发现**：初版 `scan_fix_candidates` 没检查 `EXEMPT` ⇒ 判据已 PASS 时仍报 **41 处**
（全是 `BACKLOG.md` / `docs/probe-authoring.md` 等**已被豁免的历史读数**）。
补上第 ④ 道边界后 **41 → 0**。

### 6.4 `--fix`（写盘版）已彻底删除

现在敲 `--fix` 会得到：

```
REJECT `--fix`（写盘版）已废弃：它在 2026-10-26 实测误伤 19 个文档 40+ 处数字
       （把 native 面的 572 与历史读数 811/737/807 当成 JS 总数改写）。
       改用 `--fix-dry-run`：只列出建议与理由，**不落盘**，由人落最后一笔（判例-63）。
```

**不静默降级成 dry-run** —— 那样会让人以为文件已经改好了。

---

## 七、selftest：4 格新格（**用真实语料**）

| 格 | 输入 | 断言 |
|---|---|---|
| `fix-real-native-line-is-not-js` | **真实 `git show HEAD:AGENTS.md` 的 native 行**（含 `--target native` + `572/572`） | 必须判 `native`（建议不改）；成对反例：真实 JS 行必须判 `js` |
| `fix-native-veto-is-live` | **变异对照**：把 `RX_NATIVE_CTX` 换成恒不匹配 | 格 A 必须变红（不再判 native）；恢复后必须回到 native |
| `fix-has-no-write-path` | 扫描源码 | 不存在 `run_fix` / `fix_claims`；建议面里无 `open(` |
| `fix-skips-history` | `is_history()` 真源 | 四个历史前缀都判 True；四个现状面都判 False |

**改前 28 格 → 改后 32 格，全绿。**

---

## 八、缺口与风险

1. **`--fix-dry-run` 的 `[?]` 占多数**（很多行既无 JS 标记也无 native 标记）。
   这是**设计选择**：判不准就说不准，不猜。代价是人要自己看那几行；
   收益是**不会再有 572 被当成 1463**。
2. **徽章 URL 形态判据不认**（`tests-1460%2F1460` 里的 `%2F` 不在 `SEP` 里）。
   本轮是我**人工补**的 2 处。这是判据的一个既有盲区，建议后续单开一单补 `%2F` 分隔符。
3. **`moon check --target js` 有 1 error**，在 `src/engine/engine_scope_perm_wbtest.mbt:86`
   （`Package "fs" not found`）—— 属**他人在途改动**，未影响本单（本单未改任何 `.mbt`）。
4. **本单未重跑 `moon test`**：1463 这个数来自 zeta 的 `cc2c6c37`，我按它同步。
   若该数有误，21 处会一起错 —— 建议最终收口时跑一次全量复核。

---

## 九、可复现命令

```bash
# 判据（应 PASS）
python scripts/check_test_sync.py --total 1463

# 自证（应 PASS 32 变体）
python scripts/check_test_sync.py --selftest

# 建议（只打印，不落盘）
python scripts/check_test_sync.py --total 1463 --fix-dry-run

# 写盘版已废弃（应 rc=2 + 提示）
python scripts/check_test_sync.py --total 1463 --fix

# 两个面核对
git grep -n '1463' -- README.md AGENTS.md README_EN.md README.mbt.md ARCHITECTURE.md \
    docs/SOP.md docs/agent-map.md docs/deliverable.md scripts/scoring_rubric.md
grep -n 'moon test --target native' AGENTS.md ARCHITECTURE.md
```

## 十、建议入档位置

| 项 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-26-test-count-sync-round2-report.md` |
| **判例-63 正文** | 建议由 audit-preservation 从本报告 §三 摘出 |
| 判据盲区（徽章 `%2F`） | 建议单开一单 |
