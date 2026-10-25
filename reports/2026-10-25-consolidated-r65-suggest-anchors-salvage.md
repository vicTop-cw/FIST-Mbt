# `--suggest-anchors` 只读建议器 · 未交付增量的蒸馏保全

> **来源分支**：`origin/fix/consolidated-r65`（tip 见下）
> **蒸馏时间**：2026-10-25 · 司令-γ
> **为什么蒸馏**：该分支除两个 `tmp_merge_batch.*` 删除（判例-8 的假阳性）外，
> 只有一个**真的未交付增量**：`check_slave_task_list.py` 的 `--suggest-anchors`。
> 分支即将按 C 档清理删除，**增量先落到这里保全**。

---

## 1. 判定过程（三档证据）

```
$ git diff --name-status main...origin/fix/consolidated-r65
D  scripts/tmp_merge_batch.ps1        ← 判例-8 假阳性，不是基线倒退
D  scripts/tmp_merge_batch.sh         ← 同上
M  15 个文件（其中 12 个是文档/插件投影面）
A  scripts/check_memory_log_size.py   ← main 已有（git cat-file -e 命中）⇒ 非增量
M  scripts/check_slave_task_list.py   ← ★ 真增量 46+/1-
M  scripts/run_guards.py              ← 真增量 2+/0-（给上面的尺加电池格）
```

**不是基线倒退**：`D` 面只有两个 `tmp_merge_batch.*`（main 本来就没有，从未入库），
**没有任何 main 已有的源码/脚本文件被删**。`+249/-638` 里的 638 删除行，
主要落在 `scripts/README.md`（`6+/530-`）——那是**去重收口**，不是删功能。

**`--suggest-anchors` 在 main 上不存在**：
```
$ grep -c 'suggest-anchors' scripts/check_slave_task_list.py
0        (rc=1 —— 判 rc 不判输出，判例-10)
```

---

## 2. 增量原文（`scripts/check_slave_task_list.py`）

### 2.1 参数面（`main()` 里）

```python
-    doc, root, show_face = None, ROOT, False
+    doc, root, show_face, suggest = None, ROOT, False, False
     ...
         elif a == "--show-face":
             show_face = True
+        elif a == "--suggest-anchors":
+            suggest = True
```

### 2.2 建议器本体（在 `doc_path` 算出来之后、`sink = []` 之前）

```python
    if suggest:
        # 只读建议器：**不改文档**，只打印每条失配锚点"按现状该指哪儿"。
        # 为什么只建议不自动改：R63 实测自动改会连环翻车——行号挪了、括号里的记号还是旧名，
        # 下一轮把新行号配旧记号再报一次红；更糟的是把记号指到"也含它但语义无关"的行就能骗过判据（R61 踩过）。
        rows = parse_rows(io.open(doc_path, encoding="utf-8", errors="replace").read())
        anchors, _s, _c, _f = collect_anchors(rows, os.path.abspath(root), tracked_files(root))
        tips = []
        for a in anchors:
            # 三类都要给建议：结构坏(B1/B2)、指到空行(B4)、**内容记号不在那一行(B3)**。
            # 第一版只挑前两类，B3 全被漏掉——那正是失配的大头（实测 20 条里 17 条是 B3）。
            if a["ok"] and not a.get("blank") and not (a.get("content") and not a.get("content_ok")):
                continue
            rel, ln = a["file"], a["line"]
            ap = os.path.join(os.path.abspath(root), *rel.replace("\\", "/").split("/"))
            if not os.path.isfile(ap):
                tips.append((a["row"], rel, ln, "文件不存在"))
                continue
            src = io.open(ap, encoding="utf-8", errors="replace").read().splitlines()
            toks = a.get("tokens") or []
            cands = []
            for tk in toks:
                cands += [i + 1 for i, l in enumerate(src) if tk in l]
            if not cands:
                cands = [i + 1 for i, l in enumerate(src) if l.strip()]
            if not cands:
                tips.append((a["row"], rel, ln, "文件里没有可用锚点"))
                continue
            best = min(cands, key=lambda x: abs(x - ln))
            uniq = [tk for tk in toks if sum(1 for l in src if tk in l) == 1]
            if uniq:
                tip = "%s#%s（内容锚，记号唯一）" % (rel, uniq[0])
            elif toks:
                tip = "%s:%d（记号多处出现，内容锚不可用，只能行号锚）" % (rel, best)
            else:
                tip = "%s:%d（原锚点无记号，建议补一个唯一记号）" % (rel, best)
            tips.append((a["row"], rel, ln, tip))
        if not tips:
            print("  没有失配锚点，无需建议")
            return 0
        print("  失配锚点建议（**只读，未改文档**；落笔前请按语义确认）：")
        for rid, rel, ln, tip in tips:
            print("    %-14s %s:%s → %s" % (rid, rel, ln, tip))
        return 0
```

### 2.3 电池格（`scripts/run_guards.py`）

```python
+    # —— R60：memory 日志失控闸（613 MB 事故）。只跑 --selftest，不在此读全部真日志。 ——
+    case("check_memory_log_size.py", "--selftest"),
```

> ⚠️ 注意：这一格加的是 **`check_memory_log_size.py`** 的电池格，**不是** `--suggest-anchors` 的。
> 后者目前**没有电池格也没有 selftest 覆盖**——若要合入，须同批补自证（判例-24/29）。

---

## 3. 为什么值得保全（不只是「一条命令」）

代码里那两段注释本身就是判例级的经验：

1. **「只建议不自动改」是有理由的**：
   R63 实测自动改会**连环翻车**——行号挪了但括号里的记号还是旧名，
   下一轮把新行号配旧记号再报一次红；
   更糟的是把记号指到「也含它但语义无关」的行就能**骗过判据**（R61 踩过）。
   ⇒ **自动修复工具若能被「语义无关的巧合」满足，它就是在制造假绿。**

2. **「三类失配都要给建议」是第一版踩坑换来的**：
   第一版只挑结构坏（B1/B2）与空行（B4），**漏掉了 B3（内容记号不在那一行）**——
   而那正是失配的大头（实测 20 条里 17 条是 B3）。
   ⇒ **与判例-16「判据面 < 修复面」同族：修复器只覆盖了它自己想到的那两类。**

---

## 4. 若将来要合入，需补的三件

| # | 待补 | 理由 |
|---|---|---|
| 1 | `--suggest-anchors` 的 `--selftest` 格 | 判例-24：判据必须有变异对照格 |
| 2 | 实现路径格（真调 `parse_rows`/`collect_anchors`） | 判例-29：机制格 ≠ 实现路径格 |
| 3 | 电池格（`case("check_slave_task_list.py", "--suggest-anchors")`） | 判例-5：判据存在但没接线 = 没判据 |

**且须遵守判例-40**：「按清单补」不够，要用第三方判据（`check_selftest_inventory_doc` / `check_battery_count_doc`）交叉验证。

---

## 5. 来源

- 分支：`origin/fix/consolidated-r65`
- 判据：`git diff --name-status main...origin/fix/consolidated-r65` + `git cat-file -e main:scripts/check_memory_log_size.py`
- 判例-8（`tmp_merge_batch.*` 假阳性）· 判例-10（判 rc 不判输出）· 判例-16 / 24 / 29 / 40 / 54
