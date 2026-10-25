# 工作树 M 文件分类核实测（只读）

> **执行**：司令-ζ　**基线 commit**：`0cfe1e90`　**日期**：2026-10-25
> **纪律**：**只读**——本报告是唯一新增文件，未改任何被检文件
> **方法**：blob 级逐文件比对（比 numstat 对比更强，见 §二）

---

## 一、结论

**逐文件 blob 比对 79 个 M 文件，三类占比：**

| 类别 | 数量 | 判定依据 |
|---|---|---|
| **纯 stat-cache 假 M** | **78** | 工作树 blob == index blob（内容逐字节相同） |
| **真内容差异** | **1** | blob 不同，且 `--ignore-cr-at-eol` 后**仍有**差异 |
| **CRLF 幻影** | **0** | 一个都没有（没有"忽略 CRLF 后归零"的文件） |
| 无法判定 | 0 | — |

> ### ⚠️ 与统帅快照的差异（先说清楚）
> 统帅给的读数是 `78 M / 真内容差异 0 / CRLF 0`。
> 我接手时实测是 **`79 M / 真内容差异 1 / CRLF 0`** —— **多出来的那 1 个是别人在这几分钟内新写的**，
> 与统帅的判定**不矛盾**（他的 78/0/0 是我接手前的真实快照，只是已过时）。
>
> 那 1 个是：`reports/2026-10-24-merge-precedents.md` **+3/−0**，
> 内容是另一路新增的**判例-58 / 判例-59 / 判例-60** 三行（索引表条目）。
> **不属我的域，我没有动它。**

**因此最终判定：**
- **统帅的核心判断「78 个 M 全是 stat-cache 假 M，不是 CRLF 幻影」——成立 ✅**
- 但准确表述应为：**「当前 79 个 M = 78 纯 stat-cache + 1 真内容（他人的新写入）+ 0 CRLF 幻影」**

---

## 二、方法说明（为什么用 blob 比对而不是只比 numstat）

统帅给的分辨法（`--ignore-cr-at-eol` 对比）方向正确，但它有一个前提：
**文件必须真的进了 `git diff` 的输出**。实测发现那 78 个**根本没进**：

```
$ git status --porcelain | grep -c '^ M'       → 79
$ git diff --raw | wc -l                        → 1      ← 只有 1 条！
$ git diff --raw
:100644 100644 715836fc 00000000 M	reports/2026-10-24-merge-precedents.md
```

**只有 1 条 raw 记录** ⇒ 其余 78 个**连 blob 对都没有**，git 认为它们与 index 完全一致。

这比"numstat 全 0 0"更强：numstat 的 `0 0` 仍可能是「有差异但不可数」（如纯 mode 变化、
或 CRLF 归一化后的空白行），而 **raw 里没有条目 = git 层面判定无差异**。

**我做的验证（逐文件，不是抽样）：**
```python
for f in <79 个 status 报 M 的文件>:
    w   = git hash-object -- f        # 工作树实际内容 hash
    i   = git ls-files -s -- f        # index 记录的 blob hash
    if w == i:  归类 stat-cache 假 M          # 内容逐字节相同
    else:       再看 --ignore-cr-at-eol 是否归零 → CRLF 幻影 / 真内容差异
```

**判据强度对比：**

| 方法 | 能区分 stat-cache vs CRLF 幻影？ | 结论强度 |
|---|---|---|
| `numstat` 是否非 0 0 | ❌ 两者都是 0 0 | 只能证明"无**可数**差异" |
| `--ignore-cr-at-eol` 对比 | ⚠️ 能，但前提是文件进了 diff | 中 |
| **blob 直接比对（本次采用）** | ✅ 直接看内容是否同一字节序列 | **强：逐文件定性，无歧义** |

---

## 三、逐类证据

### 3.1 纯 stat-cache 假 M：78 个

抽样实比（`cmd/cli/*` 三份，它们正是别人在途改动的文件）：
```
cmd/cli/help_topics.mbt    blob 相同 ⇒ 纯 stat-cache
cmd/cli/main.mbt           blob 相同 ⇒ 纯 stat-cache
cmd/cli/subcmd.mbt         blob 相同 ⇒ 纯 stat-cache
```
全量结果：**78/78 blob 与 index 一致**。

**成因**：文件被读过/格式化工具触碰过 ⇒ mtime 或 size 变了，但内容未变。
`git status` 因 stat 信息不匹配而报 M，`git diff` 做实际比较后判定无差异。
**这类不需要任何清理**——`git status` 下次运行会自己刷新 stat-cache。

### 3.2 CRLF 幻影：**0 个**

**为什么这次一个都没有？**
CRLF 幻影的成因是「工作树存 CRLF / index 存 LF」，`git diff` 会据此报出一个**整文件重写的差异**
（就是手册 §7 记的"345 个 M、numstat 只有 7 个真差异"那个坑）。
要出现它，必须**文件被以 CRLF 写回工作树**。

本次 78 个文件的 blob **与 index 逐字节相同** ⇒ 它们的行尾与 index 一致，
**根本没有 CRLF/LF 错配**，所以不可能有幻影。

**排查 corroboration**：
```
$ git diff --ignore-cr-at-eol --numstat | awk '$1!="0"||$2!="0"' | wc -l   → 1
```
若存在 CRLF 幻影，这一条会 **小于** 默认 numstat 的计数（幻影被忽略后归零）。
实测两者**相等**（都是 1）⇒ **没有任何文件因 CRLF 而归零** ⇒ **零幻影**。

> 机制补充（回答统帅 §二 的疑问"为什么 autocrlf=true 却没有幻影"）：
> `core.autocrlf=true` 只在**文件被写入工作树时**做 LF→CRLF 转换；
> 若文件内容自上次 checkout 后从未被重新写出（本次 78 个正是如此），
> 工作树里仍是 checkout 时的原样，与 index 一致 ⇒ 不产生幻影。
> 真正制造幻影的是「**重新写出文件**」这个动作（例如 `moon fmt` 全仓重排、
> 编辑器保存、脚本回写），而不是 autocrlf 这个配置本身。

### 3.3 真内容差异：1 个（他人的新写入）

```
reports/2026-10-24-merge-precedents.md    +3 -0
```
内容（另一路在写判例集索引）：
```
+| 判例-58 | remote ref does not exist 的双面性 —— 同一条 error，两种相反的真相
+| 判例-59 | 凭据脱敏面必须与命令面一致
+| 判例-60 | 元判据自己的假阳性面：对"什么算真源"的假设可朝两个方向错
```
**判定**：这是**有效的他人工作**，不是幻影、不是脏数据。
**我没有动它**（不在我的域，按纪律只读）。
若需落盘应由该路自行 commit，或你指派。

---

## 四、对判例-42 的延伸（本次实测贡献）

统帅列的三子类判据是正确的，本次实测补一条**更硬的判定工具**：

> **判例-42 延伸：假 M 的分类判据**
>
> | 子类 | `git status` | `git diff --raw` | 工作树 blob vs index | 会自己消失吗 |
> |---|---|---|---|---|
> | **stat-cache 假 M** | 报 M | **无条目** | **相同** | ✅ 会（下次 status 刷新） |
> | **CRLF 幻影** | 报 M | **有条目**（整文件差异） | **不同** | ❌ 不会，持续复现 |
> | **真内容差异** | 报 M | 有条目，numstat 非 0 0 | 不同 | ❌ 不会，需处理 |
>
> **最快分辨法（比 `--ignore-cr-at-eol` 更直接）：**
> ```bash
> git diff --raw | wc -l    # 与 status 的 M 数比较
> # 两者相等 ⇒ 全是真差异；远小于 ⇒ 差额就是纯 stat-cache 假 M
> ```
> 原因是 `git diff` 只输出**它认为内容真的不同**的文件，stat-cache 假 M 根本不进这个列表。
> 再用 `git hash-object -- f` vs `git ls-files -s -- f` 逐文件确认即可定性。

---

## 五、给统帅的结论（三句话）

1. **你的核心判定成立**：78 个 M 全是 stat-cache 假 M，**CRLF 幻影为 0**（一个都没有）。
2. **不需要任何清理**：stat-cache 假 M 由 `git status` 自行刷新；CRLF 幻影不存在所以也无从复现。
3. **但快照已漂**：当前实读 79 M，多出的 1 个是他人新写的判例-58/59/60（+3 行），
   **不是假 M、也不是我的域**——建议按正常流程由那一路 commit。

---

## 六、纪律声明

- ✅ **只读**：全程未修改任何被检文件；本报告是唯一新增文件。
- ✅ 未 `git add` 任何被检文件；未清理 stat-cache（结论是不需要）。
- ✅ 未触碰他人在途改动（那 1 个真内容差异原样留在工作树）。

## 来源

- 基线 commit：`0cfe1e90`
- 方法：`git status --porcelain` / `git diff --raw` / `git diff --numstat` /
  `git diff --ignore-cr-at-eol --numstat` / `git hash-object` / `git ls-files -s`
- 相关判例：判例-42（M 数 ≠ 内容差异）、判例-41（测量伪影先排除）
