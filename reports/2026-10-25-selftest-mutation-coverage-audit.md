# 全仓 selftest 变异格普查（判例-29/30/50 覆盖度审计）

- **日期**：2026-10-25
- **执行人**：司令-ε
- **任务**：统帅派工 —— 普查 `scripts/*.py` 里每个带 `--selftest` 的判据，看是否都有真变异格
- **纪律**：**只读不写**，不改任何脚本，零副作用

---

## 一、结论（先给判断）

**全仓 95 个带 `--selftest` 的脚本：结构判定 85 🟢 / 9 🟡 / 1 ⬜NOSELF / 0 🔴。**

**但本报告最重要的结论不是这个分类，而是：**

> **静态词法/结构判定不足以证明「有真变异格」，它两次给出了假结论；**
> **动态语义变异同样不可靠，它也会给出假结论。**
> **唯一可信的判据是「读到那段 selftest 源码，确认里面真的造了坏输入并断言红」。**

本报告因此**把三个层次的证据分开列**，并明确标注每条结论的**置信度**。

---

## 二、枚举（验收①）

```bash
git ls-files 'scripts/*.py' 'scripts/**/*.py' | while read -r f; do
  grep -q -- '--selftest' "$f" && echo "$f"; done | sort
```

| 项 | 计数 |
|---|---|
| 带 `--selftest` 的脚本 | **95** |
| 其中 `check_*.py` | 66 |
| 其中非 `check_*` | 29 |

清单落盘：`temp/_selftest_scripts.txt`（临时，未入库）。

---

## 三、方法演进（**这一节是本报告最诚实的部分**）

我做这轮普查试了 **3 种分类方法**，前两种都给出了**假结论**。全部留档。

### 3.1 方法一：关键词词表 ⇒ **大面积假红**

用 `变异|MUTANT|失守|改坏|必红` 等词扫 selftest 函数体：

```
GREEN(>=2 命中) 43 / YELLOW(=1) 10 / RED(零命中) 42
```

**42 个「RED」是假的。** 反例：`check_index_gitlinks.py` 明明有
`cell("e2e-gitlink-blocked", rc, 1)` —— 那是标准的「造坏输入 ⇒ 断言 rc==1」变异格，
但它**没用一个"变异"字样**。

> **教训（判例-37 的反面）**：判据面建在「恰好这么措辞」上，就会把合法结构判红。

### 3.2 方法二：结构判定（造坏 + 红灯断言）⇒ **仍有假红**

改成结构判定：selftest 体内同时出现「造坏输入的形状」与「红灯断言的形状」即算 GREEN。

```
GREEN 79 / YELLOW 12 / RED 1 / NOSELF 3
```

**两个假结论，都被我抓到并修正：**

| 假结论 | 根因 | 修正 |
|---|---|---|
| `check_selftest_hermetic` 判 RED | 我的 `selftest_body()` 用 `def \w*selftest\w*` 宽松匹配，**先命中辅助函数 `def selftest_fns(tree)`**，取到 20 行工具函数 | 改为**先精确匹配 `def selftest(`** |
| 3 个脚本判 NOSELF | 它们的自检函数叫 `surface_selftest` / 内联在 `main()` 的 `--selftest` 分支里 | 补 ②宽松命名 ③内联分支两条退路 |

修正后：**GREEN 85 / YELLOW 9 / NOSELF 1 / RED 0**。

### 3.3 方法三：动态语义变异 ⇒ **同样给出假结论**

想用「改坏代码看 selftest 是否红」来实证。两次尝试都失败：

**尝试 A：函数体首行插 `return True`** —— **无效变异**
```
check_py_stdout_encoding  CRASHED  TypeError: cannot unpack non-iterable bool object
check_bug_refs            CRASHED  TypeError: cannot unpack non-iterable bool object
check_dist_snapshot       CRASHED  TypeError: 'bool' object is not subscriptable
```
被测函数多返回 tuple / `(rc, msg)`，插 bool 直接崩。**`CRASHED` 既不是"咬了"也不是"没咬"。**

> 这与我上一单（cl7 J2~J6）犯的错**同型**：那次是「文件复制到临时目录 ⇒ import 崩 ⇒ 误读成 CAUGHT」，
> 这次是「类型不匹配 ⇒ 运行崩 ⇒ 误读成 CAUGHT」。**同一个坑，换了个入口又踩了一次。**

**尝试 B：语义替换 `== 0` → `!= 0` / `return 0` → `return 1`** —— **命中点不可控**

```
check_py_stdout_encoding        S1 eq0-to-ne0   CAUGHT  ✓
check_diff_scope                S1 eq0-to-ne0   CAUGHT  ✓
check_selftest_inventory_doc    S1 eq0-to-ne0   CAUGHT  ✓
check_backlog_status_staleness  S1 eq0-to-ne0   MISSED  ← 深查后是**假黄**
check_backlog_status_staleness  S4 return0→1   MISSED  ← 同上
check_bug_refs                  S4 return0→1   MISSED  ← 命中点不在主判定
```

深查 `check_backlog_status_staleness`：它的 selftest **有 16 格，其中 3 格正是真变异格**
（`mutation-rule-blind-R1` / `-R2` / `-R4`：关掉一条规则，断言对应违例不再被识别）。

⇒ **「MISSED」是因为我的文本替换命中了无关的 `== 0`，不是判据缺变异格。**

---

## 四、分类结果（验收②）

**置信度标注**（本报告的关键设计）：
- **高**：既通过结构判定，我**又亲自读过** selftest 源码确认
- **中**：仅结构判定，未逐条核对
- **低**：结构判定与其自述有矛盾

| 分类 | 数量 | 说明 |
|---|---|---|
| 🟢 **有真变异格** | **85** | 结构判定通过（含造坏输入 + 红灯断言） |
| 🟡 **待人工复核** | **9** | 结构上只命中一侧 |
| ⬜ **无独立 selftest 函数** | **1** | `blackbox/e2e_guard_mutation.py` |
| 🔴 **无变异格** | **0** | — |

### 4.1 🟡 待人工复核（9 个）—— 已逐个初查

| 脚本 | 结构读数 | 初查结论 | 置信度 |
|---|---|---|---|
| `check_bug_reference_integrity` | bad=2 red=0 | 用**装饰器式** `@cell("...")` 写格，正则识别不到断言；实跑 `SELFTEST PASS（10 格）`，格名含 `comment-dangling-must-judge` 等→**疑似有真变异格** | 中 |
| `check_deprecated_text_census` | bad=4 red=0 | 实跑 `SELFTEST PASS 17 个变体`，格名含 `D-dead-entry-flag` →**疑似有** | 中 |
| `check_unit_number_unique` | bad=0 red=6 | 实跑 `SELFTEST OK（11 格 S1~S11）`，**S10/S11 显式验 rc=2** →**疑似有** | 中 |
| `check_commit_bug_refs` | bad=0 red=5 | 有 `is_red` 判据函数 + 5 处红灯断言，**疑似有** | 中 |
| `check_direct_push` | bad=0 red=2 | 有 `decide()` 纯函数 + 拦截语义格（含「大小写不敏感」变异）→**疑似有** | 中 |
| `check_fist_list_tools_sync` | bad=0 red=11 | 11 处红灯断言，未读源码 | 低 |
| `check_release_asset_names` | bad=0 red=18 | 18 处红灯断言，未读源码 | 低 |
| `check_selftest_call_face` | bad=0 red=1 | **已知有真变异**（我本会话审过，J2 的 `judge_one` 变异能咬） | 高 |
| `store_isolation_probe` | bad=4 red=0 | 内联在 `main()` 的 `--selftest` 分支，含「合成违例期望 RED」自述 | 中 |

### 4.2 ⬜ 无独立 selftest 函数（1 个）

**`blackbox/e2e_guard_mutation.py`** —— 它自己**就是**变异测试器（对全仓判据做变异）。
它的 `--selftest` 语义不同：验的是「变异器自己会不会咬」，不是「被测判据有没有变异格」。
**判定**：不是缺陷，是**元层面的工具**。

---

## 五、需要交给修复的清单（验收③）

**🔴 官方清单：0 个。**

**🟡 建议人工复核（按置信度排序，低置信度优先查）：**

| 优先级 | 脚本 | 为什么值得看一眼 |
|---|---|---|
| **P1** | `check_fist_list_tools_sync` | red=11 但 bad=0，说明有大量断言却**找不到造坏输入**——可能是「只断言正常路径」 |
| **P1** | `check_release_asset_names` | 同上（red=18 / bad=0） |
| **P2** | `check_commit_bug_refs` | 同上（red=5 / bad=0） |
| **P2** | `check_direct_push` | 同上（red=2 / bad=0） |
| **P2** | `store_isolation_probe` | 结构 bad=4 / red=0，可能缺「断言红」而非缺「造坏」 |
| **P3** | 其余 4 个 | 已初查疑似有真变异格，只需确认 |

**注意**：`bad=0 而 red>0`（前 4 个）是**最可疑的形状** ——
有断言、但没找到"造坏输入"的结构 ⇒ 可能是「只测正常路径」，正是判例-30 要防的。

---

## 六、判例对照

### 判例-29（自检必须命中实现路径）
本报告**未能**逐条验证这一点（需要读 85 个脚本的自检调用图）。**如实标注为缺口。**

### 判例-30（改坏的是代码不是注释）
**结构判定完全无法验证这一条**。反例来自我自己的实测：
cl7 的 J2~J6 变异格是「注入参数」型（不改文件、改被测世界的输入），
这符合判例-30 的**精神**（改的是被测行为），但**形式上**不是"改坏源码"。
⇒ **判例-30 的判定必须有人的解释，机器替代不了。**

### 判例-50（变异必须真的改变被测行为）
本报告**只对 6 个脚本**做了动态验证，其中 3 个 CAUGHT、3 个因方法问题得假结论。
**全量动态验证不可行**（95 × 每格 1~5 分钟）。

---

## 七、我的方法学失败记录（★ 这是本报告最有价值的部分）

| # | 方法 | 失败形态 | 根因 | 对应判例 |
|---|---|---|---|---|
| 1 | 关键词词表 | **42 个假 RED** | 判据面建在「恰好这么措辞」上 | 判例-37 反面 |
| 2 | 结构判定（初版） | `check_selftest_hermetic` 假 RED | 提取器先命中辅助函数 `selftest_fns` | **判例-37 同族：探测器自己的取数面选错** |
| 3 | 结构判定（初版） | 3 个假 NOSELF | 自检函数命名不规范（`surface_selftest` / 内联） | 同上 |
| 4 | 动态变异 A | 3 个 CRASHED 被误读 | 插 `return True` 类型不匹配 | **与上一单「import 崩被误读成 CAUGHT」同型** |
| 5 | 动态变异 B | 2 个假 MISSED | 文本替换命中无关的 `== 0` | 命中点不可控 |

**统一教训**：

> **做「覆盖度审计」这件事本身，就是一个判据。**
> 而判据的两个方向都会错：
> **过宽**（词表）⇒ 假绿（把没变异的说成有）；
> **过窄**（结构/文本替换）⇒ 假红（把有变异的说成没有）。
> **唯一可靠的路径是「读源码 + 逐条核对」，机器只能缩小范围，不能给结论。**

---

## 八、缺口与风险

1. **85 个 🟢 只经过结构判定，未逐条读源码** —— 不能宣布它们全健康。
2. **动态验证只覆盖 6/95（6.3%）**，且其中 5 条因方法问题不可用。
3. **判例-29 / 判例-30 无法机器验证**（见 §6）。
4. **9 个 🟡 的初查多基于格名推断**，不是读源码确认。
5. 本报告的 `temp/_audit_mutation.py` / `_dyn_mutate*.py` 是临时工具，**未入库**（按纪律）。

---

## 九、建议（交统帅派工）

| 优先级 | 动作 |
|---|---|
| **P1** | 人工复核 4 个「bad=0 red>0」的脚本（`check_fist_list_tools_sync` / `check_release_asset_names` / `check_commit_bug_refs` / `check_direct_push`）——它们最像「只测正常路径」 |
| **P2** | 把「变异格存在性」做成**常驻判据**：要求每个 `--selftest` 至少有一格的名字/结构与「造坏 ⇒ 断言红」匹配，否则告警（**只告警不判红**，因为判例-37 说机器判定会误伤） |
| **P3** | 统一自检函数命名（`def selftest()`），让机器普查成为可能 |

---

## 十、可复现命令

```bash
# ① 枚举
git ls-files 'scripts/*.py' 'scripts/**/*.py' | while read -r f; do
  grep -q -- '--selftest' "$f" && echo "$f"; done | sort

# ② 结构分类（临时工具，未入库）
python temp/_audit_mutation.py

# ③ 动态变异（临时工具，未入库）
python temp/_dyn_mutate2.py scripts/<check_xxx.py>
```

## 来源

| 项 | 来源 |
|---|---|
| 任务 | 统帅派工（2026-10-25） |
| 判例-29/30/37/50 | 本仓既有判例 |
| 上一单对照 | `reports/2026-10-25-fix-plugin-sync-j2j6-mutations.md`（同型的「崩溃被误读成 CAUGHT」） |
