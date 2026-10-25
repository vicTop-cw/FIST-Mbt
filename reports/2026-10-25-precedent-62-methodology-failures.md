# 判例-62 方法学实证：三次假结论的完整记录

- **日期**：2026-10-25
- **记录人**：司令-ε
- **来源任务**：全仓 selftest 变异格普查（`b9b1de0d`）
- **用途**：判例-62 的**实证材料**（转 audit-preservation 入档）
- **性质**：方法论失败记录 —— 记录的是**我做审计时自己给出的错误结论**，不是被审计对象的问题

---

## 零、为什么这份记录值得单独成文

判例-62 的命题是：

> **做「覆盖度审计」本身就是一个判据，两个方向都会错：过宽 ⇒ 假绿；过窄 ⇒ 假红。
> 唯一可靠的路径是「读源码 + 逐条核对」，机器只能缩小范围，不能给结论。**

这句话如果只是被**主张**，它和本仓账本里那些「号称能咬、实际恒绿」的判据没有区别。
**它必须有自己的变异实证** —— 即：**我作为一个审计者，真的在这个任务上给出了三次错误结论。**

这份记录就是那三次。每一条都带**具体读数**与**被发现的过程**。

---

## 一、假结论 #1：关键词词表 ⇒ 42 个假 RED

### 做法

用「本仓惯例词」扫每个 selftest 函数体，命中 ≥2 次判 GREEN：

```python
MUT_RE = re.compile(r"变异|MUTANT|变异台|改坏|注入.*假|假命令|SIMULATED|失守|反向对照|反例|必红|会红")
```

### 结果

```
总计 95 个带 --selftest 脚本
  GREEN(命中 ≥2) : 43
  YELLOW(命中 =1) : 10
  RED(零命中)     : 42      ← 我据此宣布「42 个判据没有变异格」
```

### 它是假的 —— 反证

`check_index_gitlinks.py` 落在 RED 里，但它的 selftest 明明有：

```python
cell("e2e-gitlink-blocked", rc, 1)          # 造一个含 gitlink 的索引 ⇒ 断言 rc==1
cell("e2e-fullindex-blocked", rc2, 1)
```

**那是最标准的「造坏输入 ⇒ 断言红」变异格**，只是**没有使用"变异"这个词**。

### 根因

**判据面建在「恰好这么措辞」上。** 本仓自检格用英文（`blocked`）、用中文（`失守`）、
用无词（`cell("...", rc, 1)`）三种写法并存，任何词表都只能覆盖一种。

### 对应判例

**判例-37 的反面**：那边是「自证格过严 ⇒ 把合法判红」，这里是「分类器过窄 ⇒ 把有变异的说成没有」。
两者都是**判据的判定边界与实际语义边界不重合**。

---

## 二、假结论 #2：结构判定（初版）⇒ 1 假 RED + 3 假 NOSELF

### 做法

改成结构判定：selftest 体内同时出现「造坏输入的形状」与「红灯断言的形状」即 GREEN。

### 结果

```
GREEN 79 / YELLOW 12 / RED 1 / NOSELF 3
```

我据此宣布：`check_selftest_hermetic` **无变异格**，另有 3 个脚本**没有自检函数**。

### 它是假的 —— 两个具体误判

**误判 A：`check_selftest_hermetic` 判 RED**

我的 `selftest_body()` 用宽松正则：

```python
m = re.search(r"^def \w*selftest\w*\s*\(", txt, re.M)     # ← 缺陷在这
```

该文件里同时有：

```python
def selftest_fns(tree):      # ← 辅助函数（取函数列表），先被匹配到
def selftest():              # ← 真正的主自检，在被匹配到的位置之后
```

⇒ **取到的是 20 行工具函数**，里面自然没有变异格 ⇒ 判 RED。
而真身的 `selftest()` 有 `W1-anchor-derived-path-written-by-selftest` /
`W2-method-anchor-on-receiver_pathlib-write_text` / `T1-temp-derived-anchor-write-is-diag-not-red`
三格，**全是造合成源码 → 断言分类正确**的真变异格。

**误判 B：3 个假 NOSELF**

它们的自检函数分别叫 `surface_selftest()` / 内联在 `main()` 的
`if "--selftest" in sys.argv:` 分支里 —— 都不叫 `def selftest`，我的正则认不出。

### 根因

**探测器的取数面选错。** 我审计的是「selftest 里有没有变异格」，但我的取数器
**取到的不是 selftest** —— 它取到了第一个名字像 selftest 的函数。

### 对应判例

**判例-37 同族**：探测器自己的取数面出错 ⇒ 报出来的红是假红。
**更精确的说法**：审计器的**输入面**（它以为在审什么）与**真实面**（它实际审到了什么）分离。

### 修正

```python
# ① 精确 `def selftest(`
m = re.search(r"^def selftest\s*\(", txt, re.M)
# ② 其他命名（排除 selftest_fns / selftest_body 这类取数辅助）
if not m:
    m = re.search(r"^def (?!selftest_(?:fns|body)\b)\w*selftest\w*\s*\(", txt, re.M)
# ③ 内联在 main() 的 --selftest 分支
if not m:
    inline = re.search(r'^.*"--selftest".*$', txt, re.M)
    return txt[inline.start():] if inline else None
```

修正后：**GREEN 85 / YELLOW 9 / NOSELF 1 / RED 0**。

---

## 三、假结论 #3：动态变异 ⇒ 3 个 CRASHED 被误读成 CAUGHT

### 做法

想用「改坏代码，看 selftest 是否红」来**实证**（而不是静态推断）：

```python
# 第一版：被测函数体首行插一个「恒通过」返回
lines.insert(start + 1, "%sreturn %s  # MUTANT" % (indent, pick))
```

### 结果

```
check_py_stdout_encoding   CRASHED  rc=1  TypeError: cannot unpack non-iterable bool object
check_bug_refs             CRASHED  rc=1  TypeError: cannot unpack non-iterable bool object
check_dist_snapshot        CRASHED  rc=1  TypeError: 'bool' object is not subscriptable
```

**我第一反应把它们记成了 CAUGHT**（因为 `rc != 0`）。

### 它是假的

被测函数多返回 tuple / `(rc, msg)` / 列表。插一个 bool 进去 ⇒ **类型不匹配，运行期崩**。
`rc != 0` 不等于「判据咬住了」，只等于「脚本没跑完」。

**`CRASHED` 既不是"咬了"也不是"没咬"** —— 它是**第三种状态**，而我的第一版分类里没有这一档。

### 同一个坑：这是本会话**第二次**犯

| 场合 | 崩溃原因 | 我的误读 |
|---|---|---|
| cl7 J2~J6 变异格（上一单） | 变异文件复制到 `tempfile.mkdtemp()` ⇒ `Path(__file__).parent` 找不到共享模块 ⇒ **import 阶段崩** | 记成 CAUGHT（5/5，看起来完美） |
| 本轮动态变异 A | 插 `return True` 给返回 tuple 的函数 ⇒ **TypeError 崩** | 又记成 CAUGHT |

**两次都是「脚本没跑起来」被读成「判据咬住了」，只是入口不同。**

### 修正

引入**三重判定**，`CRASHED` 成为独立一档：

```python
if "Traceback (most recent call last)" in blob:
    return "CRASHED"        # ← 专门挡这两次误判
```

并把它固化成入库工具 `scripts/_mutation_probe.py`（`d3f2f913`），
`--selftest` 里有两格专门覆盖这两个真实崩溃形状。

---

## 四、假结论 #4（附）：语义变异 ⇒ 2 个假 MISSED

### 做法

改正后做语义级替换（保持类型）：`== 0` → `!= 0`。

### 结果

```
check_backlog_status_staleness  S1 eq0-to-ne0   MISSED
check_backlog_status_staleness  S4 return0→1   MISSED
```

我据此在报告里把它列为「🟡 待人工复核 / 假绿候选」。

### 它是假的 —— 深查

它的 selftest **有 16 格，其中 3 格正是真变异格**：

```
mutation-rule-blind-R1     ← 关掉 R1 规则，断言对应违例不再被识别
mutation-rule-blind-R2
mutation-rule-blind-R4
```

**MISSED 的原因是我的全文文本替换命中了无关的 `== 0`**，没碰到那三条规则开关。

### 修正

`_mutation_probe.py` 里加了 `--func`：**只在指定函数体内变异、默认只改第一处**。

---

## 五、总结：四次假结论的共同结构

| # | 我的结论 | 真实情况 | 错误方向 | 被什么抓住 |
|---|---|---|---|---|
| 1 | 42 个判据无变异格 | 至少 `check_index_gitlinks` 有 | **过窄 ⇒ 假红** | 抽查一个具体反例 |
| 2 | `check_selftest_hermetic` 无变异格 | 有 W1/W2/T1 三格 | **取数面错 ⇒ 假红** | 读源码发现函数取错 |
| 3 | 3 个判据「咬住了」 | 是脚本崩了 | **过宽 ⇒ 假绿** | 读 stderr 发现 Traceback |
| 4 | 2 个判据「假绿候选」 | 有 3 格真变异格 | **命中点错 ⇒ 假红** | 读源码发现真变异格 |

**共同结构**：

> 每一条错误结论，都是**我的判定链在某一环与真实语义脱钩**：
> 词表 vs 措辞（#1）· 正则 vs 函数名（#2）· 退出码 vs 是否跑完（#3）· 文本位置 vs 判据路径（#4）。
> **而每一条被纠正的方式，都是「去读真实的那一面」（读反例 / 读源码 / 读 stderr）。**

---

## 六、给判例-62 的正文建议

> **判例-62：做「覆盖度审计」本身就是一个判据，两个方向都会错。**
>
> **过宽**（关键词词表）：把没变异的说成有 —— 判据面建在「恰好这么措辞」上。
> **过窄**（结构判定 / 文本替换）：把有变异的说成没有 —— 提取器先命中辅助函数、文本替换命中无关代码。
> **过「信退出码」**：把「脚本没跑起来」说成「判据咬住了」—— `rc != 0` 有三种成因，只有一种是咬住。
>
> **反例不是假设，是实测。** 本会话一个「审计判据覆盖度」的任务里，我给出了 4 次错误结论
> （42 假红 / 1 假红 + 3 假 NOSELF / 3 假绿 / 2 假红），4 次都被「读真实的那一面」纠正。
>
> ⇒ **分类器只能缩小范围，不能给结论。**
> ⇒ **凡是「批量判定」的输出，都必须标注置信度，并给出「下一步该读哪个文件」的指引。**
> ⇒ **凡是报告里说"某 N 个有问题"的地方，抽查 1 个反例的时间成本，远低于误判后返工的成本。**

---

## 七、这份记录的自我约束

本记录本身也可能错。它的每一条都标了**读数来源**，可复核：

```bash
# #1 的反证
grep -n 'e2e-gitlink-blocked' scripts/check_index_gitlinks.py

# #2 的反证
grep -n 'def selftest' scripts/check_selftest_hermetic.py

# #2 的修正后读数
python temp/_audit_mutation.py     # 需临时工具（未入库）

# #3 的反证
python scripts/_mutation_probe.py --selftest     # 立方两格覆盖该崩溃形状

# #4 的反证
grep -n 'mutation-rule-blind' scripts/check_backlog_status_staleness.py
```

## 来源

| 项 | 来源 |
|---|---|
| 主报告 | `reports/2026-10-25-selftest-mutation-coverage-audit.md`（`b9b1de0d`）|
| 前一单同型错误 | `reports/2026-10-25-fix-plugin-sync-j2j6-mutations.md` §6（`b8d087f3`）|
| 固化产物 | `scripts/_mutation_probe.py`（三重判定 + CRASHED 档）|
| 判例-37 / 62 | 本仓既有判例 |
