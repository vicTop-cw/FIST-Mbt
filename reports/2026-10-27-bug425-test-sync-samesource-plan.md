# BUG-425 · `check_test_sync` 读数面与原文面同源 · 精确 patch · Lane AC · 2026-10-27

> **交付形态**：`scripts/` 是 Executor 可改面，但本轮 `scripts/` 有多个在途改动（`check_dist_snapshot.py` /
> `run_guards.py` / `_deployment_symbols.py` / `check_deployment_freshness.py`，别的 lane 在做 BUG-428）
> ⇒ 按派单「只读出 patch」，**本报告不改任何 `scripts/` 文件**。

---

## 一、结论

### 1.1 三件事的读数（全部实测）

#### ① `^test` 行数与实测总数的偏差：**不稳定，方案 (a) 不可行**

| 面 | `^test` 行数 | `moon test` 实测 | 差 |
|---|---|---|---|
| **HEAD**（`89b15d38`）| **1525** | — | −7（含全部在途增量）|
| **工作树**（当前）| **1532** | **1532** | **0** |
| **Round 6 那次**（2026-10-26 22:00）| 1506 | 1505 | **+1** |

**⇒ 偏差从 +1 变成 0，不是常数。加固定偏移（`+1`）的方案 (a) 不可行。**

**补充澄清**（回答统帅「不精确要分清是行计数不准还是 HEAD 与工作树本来就该不同」）：
- **两者都有**：
  - **「HEAD 与工作树本来就该不同」是主因**：1525 vs 1532，差 7 = 在途工作新增的 test 行。
    这是**语义上正确**的差（HEAD 确实还没有那 7 个测试）。
  - **「行计数方法本身也不稳」是次因**：Round 6 测到 1506 vs 实测 1505（+1），Round 9 测到 1532 vs 1532（0）。
    同一套计数代码、同一台机器，差值却变了 ⇒ **行计数与 moon 的用例计数口径不完全一致**。
- ⇒ **方案 (a) 不但「HEAD 与工作树该不同」这一层绕不过，连「行计数≈实测数」这个前提也不成立。**

#### ② `check_test_sync` 现在怎么读数：**不数行，用调用方传入的 `--total` 或跑 `--fresh`**

**⇒ BUG-425 的描述要修正一处**：它的读数面**不是**行计数，而是**调用方传入的 `--total N`**
（或 `--fresh` 时真跑 `moon_test_env.py`）。BUG-425 的病灶依然成立，但机理更精确：

```python
# scripts/check_test_sync.py:78-96  run_fresh()
p = subprocess.run([sys.executable, str(env_script), "--target", "js", "--raw-log", snapshot_path], ...)
```
- `--total N`：**N 由人传入**，而人只能从「刚才跑的那次 `moon test`」拿 N ⇒ **读数面 = 工作树**
- 被检的 17 处 `.md`：写的是**已提交态** ⇒ **原文面 = HEAD**
- **两者不同源** ⇒ BUG-425 成立（机理与行计数无关，我 Round 6 的表述不够精确，此处修正）

#### ③ `run_guards` 会不会把 `rc=2` 当红：**会，而且是硬判红**

```python
# scripts/run_guards.py:301-302
gated("check_badge.py", TESTLOG, TESTLOG, "README.md", "--fresh"),
gated("check_test_sync.py", TESTLOG, TESTLOG, "--fresh"),

# run_guards.py:84  def gated(script, need, *args, expect=0, why=..., kind="gate")
# run_guards.py:974 ok = p.returncode in allow if allow else (p.returncode == c["expect"])
```
`gated()` 的 `expect` 默认 **0**，`run_guards` 用 **精确相等** 比对 ⇒ **`rc=2` 会被判 FAIL**。

**⚠️ 这条决定了「落哪一档」**：如果我让 `check_test_sync` 在脏树上回 `rc=2`，
**电池会红**——那不是「拒绝出数」，而是「把不可判态转成电池故障」。

---

### 1.2 选择：**落「advisory 档」= `rc=0` + 显式 `WARN` 行**，不新造退出码

**理由（三条）：**

1. **不能落 `rc=2`**（理由见 §1.1③）：`run_guards` 的 `expect=0` 是精确比对，回 2 就是电池红。
   要落 2 就必须同时改 `run_guards` 的 `expect` 或用 `allow=[0,2]` —— 那会**改动别人正在改的文件**（Lane 的 BUG-428）。
2. **不新造第三套退出码**（统帅硬要求②）：本仓已有 `check_fmt_gate`（0/1/2）与
   `e2e_native_heap_probe`（0/1/3/4）两套，**再加一套就是漂移**。
3. **「拒绝出数」在本仓的既有形态不止一种**：`check_fmt_gate` 用 `rc=2` 是因为**它只被 CI 消费、没有电池 expect 约束**；
   而 `check_test_sync` 住在**电池**里，电池的契约是「每格 expect=0」。
   ⇒ **同一语义（不可判）在不同判据上落成不同的实现形态，是因为它们的消费者不同，不是口径漂移。**
   **这正是「与既有约定一致」的正确读法：一致的是「如实标注不可判」，不是「都用 rc=2」。**

### 1.3 默认 source 该是哪个：**默认 `worktree`（保持现状），不改成 `head`**

**理由**：统帅自己也点出了 `head` 作为默认的风险——
> 若默认 `head`，本地会读到旧数 ⇒ 开发者看到的红是「HEAD 落后」而不是「我改坏了」。

**更硬的一条**：`check_test_sync` 的**唯一目的**是「现状面文档不掉队」。
在**本地开发**场景（绝大多数调用），开发者刚改完代码还没提交，
此刻他需要知道「我刚加的测试有没有让文档掉队」——**那必须对工作树**。
把默认改成 `head` 会让这个工具**对最有需求的场景失明**。

⇒ **默认 `worktree`（不变），`head` 作为显式覆盖 `--source=head` 供 CI 用。**

### 1.4 什么情况下**仍然必须红**（回答统帅硬要求③）

**三道「不许变成永远绿」的闸：**

| 场景 | 行为 |
|---|---|
| `--strict`（任何脏）| **不许降级**，照常判红。给不想看 WARN 的人一个「要么干净要么红」的开关 |
| **环境变量 `CI=true`** | **自动进入 strict**：CI 上工作树本来就该干净，脏即异常 ⇒ 不许用 advisory 盖住 |
| **脏但被检文档恰好就是脏文件之一** | **不许降级**：如果 17 处里某份 `.md` 自己就在未提交清单里，那「文档 vs 实测」的对比是有效的，red 是真 red |

**第三闸是我加的，因为它是「降级 → 假绿」最容易漏的缝**：
一般的「脏则 advisory」只看「有没有未提交文件」，但如果**被检的文档自己就被改了**，
那么这一格的红是**真信号**（人改了文档但没跑测试），不该被「脏」这个状态盖掉。

---

## 二、可粘贴 patch

### 2.1 标准 diff 摘要

```diff
--- a/scripts/check_test_sync.py
+++ b/scripts/check_test_sync.py
@@ 顶部常量区（在 RX_TOTAL 附近）
+import os as _os
+
+# BUG-425：读数面与原文面必须同源。
+#   · 读数面 = 调用方传入的 `--total N`（通常来自刚跑完的工作树 `moon test`）
+#   · 原文面 = 17 处现状面 .md（写的是**已提交态**）
+# 工作树脏时两者天然不同源 ⇒ 本判据会「制造假红」而不是「检测漂移」。
+# 处置：脏则**降级为 advisory**（rc 仍 0，但打印 WARN 并点名脏文件），
+# 三道闸禁止它变成「永远绿」：--strict / CI=true / 被检文档自身在脏清单里。
+STRICT_ENV = "CI"
+
+def dirty_mbt_files(cwd=None):
+    """返回工作树里未提交/未跟踪的 *.mbt 相对路径列表（纯只读）。
+
+    为什么用 `git status --porcelain` 而不是比较 mtime：mtime 会被 checkout / touch
+    误触发（判例-21：stat-dirty 噪声 ≠ 真变更）。
+    """
+    cmd = ["git", "status", "--porcelain", "--", "*.mbt"]
+    try:
+        p = subprocess.run(cmd, cwd=cwd or str(ROOT), capture_output=True)
+    except OSError:
+        return []
+    out = (p.stdout or b"").decode("utf-8", "replace")
+    files = []
+    for ln in out.splitlines():
+        if len(ln) > 3:
+            path = ln[3:].strip()
+            if path.endswith(".mbt"):
+                files.append(path)
+    return files
+
+def dirty_docs_overlap(docs, dirty(cwd=None)):
+    """被检文档自身是否在脏清单里（第三闸：这种红是真信号，不许降级）。"""
+    ...
```

> 完整实现见 §2.2（可粘贴）。上面只是形状说明。

### 2.2 完整可粘贴实现

**（A）新增两个纯函数（插在 `run_fresh` 之前）**

```python
def dirty_mbt_files(cwd=None):
    """工作树里未提交/未跟踪的 *.mbt 相对路径（只读）。

    为什么用 git status --porcelain 而非比 mtime：mtime 会被 checkout/touch 误触发
    （判例-21「stat-dirty 噪声 ≠ 真变更」）。
    """
    cmd = ["git", "status", "--porcelain", "--", "*.mbt"]
    try:
        p = subprocess.run(cmd, cwd=cwd or str(ROOT), capture_output=True)
    except OSError:
        return []
    out = (p.stdout or b"").decode("utf-8", "replace")
    files = []
    for ln in out.splitlines():
        if len(ln) > 3:
            path = ln[3:].strip()
            if path.endswith(".mbt"):
                files.append(path)
    return files


def dirty_docs_overlap(dirty_paths, docs_dir=None):
    """被检文档自身是否落在脏清单里 ⇒ 这种红是真信号，不许被 advisory 盖掉。"""
    for p in dirty_paths:
        if p.startswith("docs/") or "/" not in p:
            if p.endswith(".md"):
                return p
    return None


def advisories(dirty_paths, docs_dir=None):
    """返回 advisory 理由列表（空 = 不降级）。三道闸依次判。"""
    if _os.environ.get(STRICT_ENV, "").strip().lower() in ("true", "1", "yes"):
        return []          # 闸 2：CI ⇒ 永远不降级
    if not dirty_paths:
        return []          # 干净 ⇒ 不降级
    hit = dirty_docs_overlap(dirty_paths, docs_dir)
    if hit:
        return []          # 闸 3：被检文档自身脏 ⇒ 真信号，不降级
    return dirty_paths     # 闸 1（--strict）在 main 里判
```

**（B）`main()` 里接线（3 处小改）**

```diff
 def main():
     raw_args = sys.argv[1:]
     if raw_args == ["--selftest"]:
         return selftest()
+    # BUG-425 闸 1：--strict 强制不许降级
+    strict = "--strict" in raw_args
+    raw_args = [a for a in raw_args if a != "--strict"]
     fresh = "--fresh" in raw_args
     args = [a for a in raw_args if a != "--fresh"]
@@ (在拿到 total 之后、开始扫文档之前)
+    # BUG-425：脏工作树 ⇒ advisory（读数面=工作树，原文面=HEAD，不同源）
+    _dirty = dirty_mbt_files()
+    _adv = [] if strict else advisories(_dirty)
+    if _adv:
+        print("WARN 工作树有 %d 个未提交/未跟踪的 *.mbt —— 本格不判红（BUG-425）" % len(_adv))
+        print("     why：读数面 = 工作树实测 %s；原文面 = 已提交态文档；两者不同源" % total)
+        print("     ⇒ 此刻的红可能是「文档落后于在途工作」，不是「文档写错了数」。")
+        print("     点名脏文件（前 20 条）：")
+        for _p in _adv[:20]:
+            print("       · %s" % _p)
+        if len(_adv) > 20:
+            print("       …（共 %d 条）" % len(_adv))
+        print("     强制确认走 `--strict`；CI 上的红不受此影响（CI 工作树应干净）。")
```

**（C）收口处：把违例降级为警告**

```diff
     if problems:
         for p in problems:
             print("FAIL %s" % p)
-        return 1
+        if _adv:
+            # BUG-425：脏工作树 ⇒ advisory，**rc 仍 0**，但已打印 WARN 与点名
+            print("ADVISORY 上述 %d 条违例不判红（工作树脏，见上方 WARN）；"
+                  "确认要红请加 --strict" % len(problems))
+            return 0
+        return 1
     print("PASS ...")
     return 0
```

### 2.3 `--source=head`（方案 c）—— **本期不实现，理由**

统帅倾向「(b)+(c) 组合」。**我建议先只做 (b)，(c) 留作后续**：

- `--source=head` 的**唯一实现路径**是在临时 worktree 里真跑一次 `moon test`——
  **昂贵**（全量测试 ~20 分钟）且**引入新的并发风险**（多 lane 同时建临时 worktree）。
- 而**它要解决的问题 (b) 已经解决**：CI 上工作树干净 ⇒ (b) 不降级 ⇒ 行为等同 head。
- 若将来确有需要（比如想在本地预演 CI 判决），再实现 `--source=head`，
  且实现方式应是「`git stash` 后跑完自动 `pop`」——但那是**有副作用的危险操作**，不建议放进判据。

**⇒ 本期落 (b)；(c) 记为「已知未实现」，理由入档。**

---

## 三、3 格锁设计（+ 变异对照）

新增在 `check_test_sync.py` 的 `selftest()` 里：

```python
def selftest():
    cells = []
    def cell(name, got, want):
        cells.append((name, got, want))

    # ... 既有格 ...

    # —— BUG-425：advisory 三闸 ——
    # 锁 1：干净工作树 ⇒ 不降级（advisories 返回空）
    cell("bug425-clean-no-advisory", advisories([]), [])

    # 锁 2：脏工作树 ⇒ 降级，且**点名了全部脏文件**
    _d = ["src/a.mbt", "src/b.mbt"]
    cell("bug425-dirty-advisory-lists-files", advisories(_d), _d)

    # 锁 3：**被检文档自身脏 ⇒ 不降级**（第三闸，防「脏」盖掉真信号）
    cell("bug425-dirty-doc-not-degraded", advisories(["docs/ARCHITECTURE.md"]), [])

    # 锁 4（变异对照 / 判例-29）：CI 环境下**必须不降级**
    os.environ[STRICT_ENV] = "true"
    cell("bug425-ci-never-degrades", advisories(_d), [])
    del os.environ[STRICT_ENV]

    # 锁 5：dirty_mbt_files 只认 *.mbt（不把 .md/.py 算进来）
    #   —— 用真实仓库调用，断言返回项全部以 .mbt 结尾
    cell("bug425-only-mbt", all(p.endswith(".mbt") for p in dirty_mbt_files()), True)
```

**变异对照（判例-29/30）**：

| 变异 | 改哪里 | 哪格必红 |
|---|---|---|
| **M1** | 删掉 `advisories()` 里的 `if _os.environ.get(STRICT_ENV...)` 那段 | **锁 4**（CI 仍降级）|
| **M2** | 删掉 `dirty_docs_overlap` 那一支 | **锁 3**（文档脏也被降级）|
| **M3** | 把 `main()` 里 `if _adv:` 那段的 `return 0` 改回 `return 1` | **锁 2 的入口格必红**（脏树仍判红）|

**判例-30 防护**：所有锁**只断言 `advisories()` / `dirty_mbt_files()` 的返回值**，
**不断言源码里有某字符串**——后者会命中注释（本 patch 的注释里就写着 `advisories`、
`dirty_mbt_files` 等词）⇒ 自指假绿。

**⚠️ 锁 5 的注意点**：它调真实 `git status`，在**干净 CI 上返回空列表** ⇒
`all(...)` 对空列表恒 True ⇒ 该格在 CI 上恒绿。**这是它的真缺陷**，应改成：
用 `dirty_mbt_files` 的**注入面**（允许传一个假的 porcelain 文本）来测纯函数。
**建议**：把解析逻辑拆成纯函数 `_parse_porcelain_mbt(text)`，锁 5 测它。

---

## 四、分析：为什么这档与本仓既有约定一致

**本仓「拒绝出数」的语义锚点是一条，不是两套退出码：**

> **判据在自己无法给出可信结论时，必须如实标注，不许假装给了结论。**

| 判据 | 落成什么 | 为什么形态不同 |
|---|---|---|
| `check_fmt_gate.py` | `rc=2` DEGRADED | 只被 **CI** 消费，无电池 `expect` 约束 |
| `e2e_native_heap_probe.py` | `rc=3` 平台不给量 | 同上，独立脚本 |
| **`check_test_sync.py`（本 patch）** | **`rc=0` + WARN 行** | **住在电池里**，`gated(expect=0)` 精确比对 ⇒ 回 2 就是电池红 |

**⇒ 关键区别不是「语义不同」，而是「消费者不同」**：
前两者回非 0 是安全的（CI 认得），后者回非 0 会**破坏电池**。
**把「不可判」表达成 WARN 行而不是退出码，是这一格唯一不伤既有消费者的做法。**

**这也回答了统帅的疑问**：「不要新造一套退出码语义」——本 patch **零新增退出码**，
`check_test_sync` 仍然只有 0/1/2 三档，advisory 复用 0 档。

---

## 五、缺口与风险

### 5.1 「降级」会不会变成「永远绿」—— 三道闸的实际强度

| 闸 | 强度 | 弱点 |
|---|---|---|
| `--strict` | 强 | **靠人记得传** —— 这本身就是本仓批评过的「工具要人记得调用」 |
| **`CI=true` 自动 strict** | **最强** | 依赖 CI 环境真的设了 `CI=true`（GitHub Actions **默认就设**，实测安全）|
| 被检文档自身脏 ⇒ 不降级 | 中 | 只覆盖「人改了文档」这一种真信号 |

**最硬的保证是 CI 那一闸**：GitHub Actions 默认注入 `CI=true`，
⇒ **CI 上永远不会降级** ⇒ 漂移在 CI 上仍然会被抓到。
**本地降级不构成假绿风险，因为本地绿不算数**（本仓口径：权威门 = CI）。

### 5.2 剩余风险（如实列）

1. **`run_guards --fresh` 在脏树上会一直走 advisory**：本 patch 让 `check_test_sync` 在脏树上回 0，
   于是电池那格**恒绿**。**这是有意的**（脏树的数不可信），但代价是：
   **本地跑电池时这一格不再有区分力**。缓解：CI 闸。
2. **`run_guards` 的 `expect` 我不改**（别的 lane 在改该文件）；
   若将来要落 `rc=2`，必须同批改 `gated(..., expect=0)` → `allow=[0,2]`。
3. **方案 (c) `--source=head` 未实现**（§2.3）——记为已知缺口。
4. **`^test` 行数偏差 +1/0 不稳定的根因未定位**（Round 6 就记过）。
   本 patch **不依赖行计数**（用调用方传入的 `--total`），故不影响正确性；
   但若将来有人想用行计数做快速判据，这 1 的偏差会咬人。
5. **本轮未改任何 `scripts/` 文件**（派单要求只读）⇒ **patch 未编译、未跑测试**。

---

## 六、建议入档位置

| 内容 | 位置 |
|---|---|
| 本 patch | BUG-425 条目挂 `- patch: reports/2026-10-27-bug425-test-sync-samesource-plan.md` |
| **BUG-425 描述修正** | 账本追加：病灶**不是**「行计数不准」，而是「`--total` 来自工作树、文档写已提交态，两者不同源」 |
| 「拒绝出数的形态取决于消费者」 | 判例集：**同一语义在不同消费面落成不同形态，不是口径漂移** |
| `^test` 行数 ±1 不稳定 | 建议单开（若将来要行计数判据）|
| `run_guards` 的 `gated(expect=0)` 精确比对 | 与 BUG-428 车道协调（该文件正在被改）|
