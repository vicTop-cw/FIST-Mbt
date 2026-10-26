# BUG-428 诊断与修法方案 · 部署产物陈旧但版本守卫 PASS

> **文种**：只读诊断 + 可粘贴 patch
> **日期**：2026-10-27 · **执行**：Lane Z（commander-alpha）
> **边界**：**未改 `scripts/check_dist_snapshot.py`**（按你指示先出方案，改动判定面会影响 CI）
> **所有读数均为本次实测**，非引用

---

## 结论

| 问题 | 答案 |
|---|---|
| **BUG-428 根因** | `check_dist_snapshot.py` **只比 `project__version` 字符串**（119 行，`VERSION_RE` 一个正则）|
| **(a) 符号探针** | 🔴 **不可行** —— 实测**新构建产物里函数名全部不存在**（MoonBit 消除函数名，只留字段名/表名/字符串）|
| **(b) 内容摘要** | ✅ **完全可行** —— 实测**两次干净构建字节完全相同**（`ec384783…`）|
| **(c) mtime 比对** | 🔴 **不可靠** —— 我刚才 `touch` 一个 `.mbt` 它就成了「最新」，任何 checkout/cp 都会失效 |
| **我倾向** | **(b) 主判据 + (a′) 降级版（字段名/表名探针）做补充，均自动生成，零人工维护** |
| **PATH 上那个产物谁更新** | 🔴 **没人** —— `install.ps1` 手工 `Copy-Item -Force`，**无任何自动更新机制**。这是比守卫更根本的根因 |

---

## 证据

### ① 三个必测读数（实测值，非估算）

#### 读数 1：构建可复现性 —— **字节完全相同** ✅

```bash
# 第一次构建
$ md5sum _build/js/release/build/cmd/main/main.js
ec38478344b22df15181120888efa26e

# 删产物后干净重建
$ rm -f <该文件> && moon build --target js --release
Finished. moon: ran 1 task, now up to date

# 第二次构建
$ md5sum _build/js/release/build/cmd/main/main.js
ec38478344b22df15181120888efa26e

$ cmp -s b1.js main.js   →  字节完全相同
```

**⇒ (b) 内容摘要在本仓**技术上完全可行**（MoonBit 的 release JS 构建是可复现的）。**
（⚠️ 注意：只测了**同一台机、同一工具链、同一天**——跨机器/跨 moon 版本的可复现性**未测**，见 R2。）

#### 读数 2：从产物 mtime 到现在，有多少 commit 引入新 `pub fn`

```
$ git log --since="2026-10-26 11:59" --oneline | wc -l
52

$ git log --since="2026-10-26 11:59" -p -- 'src/**/*.mbt' | grep '^+pub fn ' | sort -u
pub fn omega_orphan_of_archived_parent     ← BUG-417
pub fn resolve_agent_role                   ← BUG-418
pub fn agents_acl_count_writable            ← BUG-411
pub fn agent_fp_of / RsvOutcome::relabel
pub fn SqliteStore::agents_acl_count_writable
pub fn db_file_exists / db_file_task_count / migrate_legacy_store
pub fn store_migration_applies / store_migration_note / store_migration_reason
pub fn StoreMigration::skipped / skipped_at / to_json
pub fn matching_rule / ocr_mbt_include_rule_json / ocr_mbt_remedy
pub fn ocr_needs_mbt_include / ocr_path_has_mbt
（共 20+ 个）
```

**⇒ 「从 git log 自动抽 `pub fn`」这个想法在**数据上**可行（52 commit 抽得出 20+ 符号）。**
**但下面这条实测直接判了它死刑：**

#### 读数 2.5（🔴 决定性）：**符号在产物里根本不存在**

```bash
# 用【刚构建出来的新产物】去 grep 这些新符号
$ grep -c omega_orphan_of_archived_parent  _build/js/release/build/cmd/main/main.js
0                                        ← 新产物里也没有！
$ grep -c resolve_agent_role               同上
0
$ grep -c agents_acl_count_writable        同上
0
```

**对照：字段名/表名/字符串常量是能 grep 到的**

```
$ grep -c omega_required   main.js   →  42    ✅
$ grep -c agent_acl        main.js   →   9    ✅
$ grep -c project__version main.js   →   5    ✅
$ grep -c archive_force    main.js   →   0    ❌（函数名同样被消除）
```

**⇒ MoonBit → JS **消除了函数名**，只保留字段名、表名、字符串常量。**
**⇒ (a) 用 `pub fn` 名字做探针**在物理上不成立**，不是「维护成本高」，是「根本 grep 不到」。**
**⇒ 这是 BUG-428 任务包给我的三条路里，最需要实测才能发现的一条 —— 若照搬 (a)，守卫会 100% 恒红。**

#### 读数 3：`src/` 最新 `.mbt` mtime vs 三份产物 mtime —— **(c) 不可靠**

```
三份产物 mtime:
  2026-10-24 06:16:54  5,590,176 B  dist/fist-mbt.js
  2026-10-18 16:34:10  3,857,767 B  _release/js/fist-mbt.js
  2026-10-26 11:59:25  5,342,744 B  C:/Users/victo/AppData/Local/FIST-Mbt/fist-mbt.js

src/ 最新 .mbt mtime（实测前）：2026-10-26 23:23:53  src/core/core_task.mbt
```

**⇒ 三份产物全部早于 src 最新文件 —— 但这是个**脆弱的判断**，我实测了它的失效方式：**

```bash
$ touch src/core/core_task.mbt          # 我为了触发重建摸了一下它
$ find src -name "*.mbt" -printf '%T+ %p\n' | sort -r | head -1
2026-10-26+23:37:15  src/core/core_task.mbt   ← 立刻变成「最新」
```

**⇒ 任何 `touch` / `git checkout` / `git stash` / `cp` 都会让「最新 .mbt mtime」变成噪声值。**
**⇒ (c) 会把「我 touch 了一下文件」误判成「产物必须重建」** —— 假阳性直接毁掉守卫的可信度。
**（这正是你「第一次读就觉得不可靠」的直觉，实测证实了。）**

### ② `check_dist_snapshot.py` 判定逻辑（逐行）

**119 行，判定面只有两个正则：**

```python
# 第 26 行：唯一的数据提取规则
VERSION_RE = re.compile(r'project__version = "([0-9]+\.[0-9]+\.[0-9]+)"')

# 第 29-35 行：基线（从 moon.mod 读）
def moon_version(root=ROOT):
    m = re.search(r'version\s*=\s*"([^"]+)"', ...)
    ...

# 第 37-44 行：样本（从产物读，去重）
def dist_versions(text):
    return sorted(set(VERSION_RE.findall(text)))

# 第 46-58 行：judge —— ★ 这就是全部判定逻辑
def judge(text, want):
    got = dist_versions(text)
    if want is None:  return 2, "moon.mod 读不到 version —— 判据没有基线，拒绝出结论"
    if not got:       return 2, "快照里读不到 project__version —— 判据没有样本，拒绝出结论"
    ...              # 全部是 got 与 want 的字符串相等比较
```

**⇒ 判定面 = 「产物里那个版本字符串 == moon.mod 里的版本字符串」。**
**⇒ 它对「代码改了但版本没 bump」完全无感 —— 而本仓**正是这么工作的**（52 个 commit 没有 bump 版本）。**

**selftest 的 6 格也全是版本字符串的对照**（第 68-76 行），**没有一格测「内容」**。

### ③ 实测印证：三份产物的版本 vs 代码

| 产物 | `project__version` | 守卫判定 | 实际代码 | mtime |
|---|---|---|---|---|
| `dist/fist-mbt.js` | **0.3.10** | **PASS** | 🔴 旧（无 BUG-411/417/418） | Oct 24（3 天前） |
| `_release/js/fist-mbt.js` | **0.3.9** | FAIL | 🔴 更旧 | Oct 18（8 天前） |
| **`AppData/Local/FIST-Mbt/fist-mbt.js`** | **0.3.10** | **PASS** | 🔴 旧 | Oct 26 11:59（12 小时前，**但 src 已改了 52 个 commit**） |
| `moon.mod` | 0.3.10 | （基线） | 最新 | — |

**⇒ `dist/` 与 `AppData/` 都**PASS**，代码都是旧的。这正是 BUG-428 的现场。**

### ④ 任务 4：其他守卫是否也只看版本

| 守卫 | 内容哈希相关行 | 版本/文本相关行 | 判定 |
|---|---|---|---|
| `check_badge.py` | **0** | 0 | 比徽章文本，与产物无关 |
| `check_tools_sync.py` | **0** | 6 | 🔴 只比**工具名/数量**，不比代码 |
| `check_plugin_sync.py` | **0** | **23** | 🔴 生成器**重跑逐字节 diff** —— **这个是唯一真正比内容的**（见 §分析） |
| `check_host_installable.py` | **0** | 14 | 🔴 只比路径/版本 |

**⇒ 结论：只有 `check_plugin_sync` 做了真正的字节比对（它 `子进程重跑生成器做逐字节 diff`）。
其余三支都是文本/版本比对。**

### ⑤ 任务 3（可能更严重）：PATH 上那个产物谁更新

```powershell
# scripts/blackbox/install.ps1
[string]$InstallDir = "$env:LOCALAPPDATA"          # 第 25 行
Copy-Item $bare $destMain -Force                   # 第 121 行 ← 手工拷贝
if ($_.Name -eq $TargetName) { Copy-Item $_.FullName $destMain -Force }   # 第 139 行
$jsBin = Join-Path $InstallDir "fist-mbt.js"       # 第 171 行
```

**⇒ `install.ps1` 是**一次性安装脚本**：`Copy-Item -Force` 把当时那份 js 拷到 `%LOCALAPPDATA%\FIST-Mbt\`。**
**⇒ 之后**没有任何自动更新机制** —— 没有定时任务、没有版本检查、没有 `upgrade` 钩子。**

**⇒ 这就是「代码改了但 MCP 行为不变」的**真正根因**，比守卫陈旧更根本：**
即使把守卫修好，**PATH 上那份仍然不会自己更新** —— 它需要**人再跑一次 install.ps1**。

**⇒ 建议把「产物更新」也纳入方案（见 §3.3），否则修好守卫只是「知道产物旧了」，仍然不会变新。**

---

## 3. 修法方案

### 3.1 三条路的最终判定

| 路 | 实测结论 | 可行性 |
|---|---|---|
| **(a) 符号探针（函数名）** | 🔴 新产物里 **grep 不到**任何 `pub fn` 名 | **不可行 —— 会恒红** |
| **(a′) 符号探针（字段名/表名/字符串）** | ✅ `omega_required` 42 处、`agent_acl` 9 处 | **可行，但语义弱**（字段名不随 BUG 修复变化） |
| **(b) 内容摘要** | ✅ 两次构建字节完全相同 | **可行，且最正确** |
| **(c) mtime** | 🔴 `touch` 一个文件就失效 | **不可靠** |

### 3.2 我倾向的方案：**(b) 主判据 + 零人工维护**

**核心思路：不比「产物 vs 源码」，而是比「产物 vs 当场重建的产物」。**

```python
# 伪代码（不是最终 patch，见 3.4）
def judge_by_content(dist_path):
    # 1. 当场构建到临时位置（不污染 _build）
    fresh = build_to_temp()                   # moon build --target js --release
    # 2. 逐字节比
    if sha256(dist_path) == sha256(fresh):
        return 0, "PASS：产物与当前源码重建结果逐字节相同"
    else:
        return 1, "FAIL：产物陈旧（dist 与重建结果不同）+ 给出重建命令"
```

**为什么这条不制造下一颗雷（回答你的硬要求 ②）**：

| 潜在负担 | 本方案 |
|---|---|
| 要不要维护符号清单？ | **不要** —— 没有任何清单 |
| 每修一个 bug 要加一条？ | **不要** —— 判据自动覆盖全部代码 |
| 会不会因为构建噪声恒红？ | **实测不会**（字节相同）—— 但**跨机器/跨 moon 版本要防**（见 R2 缓解） |
| 运行成本？ | 一次 `moon build --release`（本机实测约 **1~2 分钟**）—— 建议**只在 CI/release 前跑，不进 pre-commit** |

**⇒ 这是三条路里**唯一**「不需要人记着维护」的一条。**

### 3.3 配套：产物更新机制（比守卫更根本）

**若只修守卫不修更新，结果只是「知道产旧了，但仍不新」。** 建议：

1. **`install.ps1` 加版本自检**：安装时比 `$InstallDir\fist-mbt.js` 与源产物的 sha256，**不同就提示「有更新，建议重装」**
2. **MCP server 启动时打印自身版本 + 产物 mtime**（让客户端一眼看到跑的是哪份）
3. **`mcp_smoke.py` / 冒烟脚本先断言产物新鲜度**，再起 server

### 3.4 可粘贴 patch（`scripts/check_dist_snapshot.py` 增量，不替换现有判定）

**设计原则：保留现有版本判定，**新增**一层内容判定，且默认不改变 CI 现有行为。**

```diff
--- a/scripts/check_dist_snapshot.py
+++ b/scripts/check_dist_snapshot.py
@@ -20,6 +20,10 @@
+import hashlib
+import shutil
+import subprocess
+import tempfile
+
 VERSION_RE = re.compile(r'project__version = "([0-9]+\.[0-9]+\.[0-9]+)"')
+
+# BUG-428：版本号相等 ≠ 产物新鲜。本仓 52 个 commit 未 bump 版本，
+# 于是「dist 是 3 天前的、AppData 是 12 小时前的」，版本却都 == moon.mod。
+# 内容判定必须比「产物 vs 当场重建的产物」，不能比版本字符串。
+#
+# ⚠️ 不用函数名做符号探针：实测 MoonBit release JS **消除函数名**
+#    （omega_orphan_of_archived_parent / resolve_agent_role / archive_force 在新产物里 grep 计数均为 0），
+#    而字段名/表名/字符串保留（omega_required=42 / agent_acl=9）。用函数名做探针会恒红。
+# ⚠️ 不用 mtime：实测 touch 一个 .mbt 就让「最新源文件」变成噪声值。
+
+
+def sha256_of(path):
+    h = hashlib.sha256()
+    with io.open(path, "rb") as f:
+        for chunk in iter(lambda: f.read(1 << 20), b""):
+            h.update(chunk)
+    return h.hexdigest()
+
+
+def built_artifact(root=ROOT):
+    """当前源码 release 构建的产物路径（不构建，只定位）。"""
+    return os.path.join(root, "_build", "js", "release", "build", "cmd", "main", "main.js")
+
+
+def judge_content(dist_path, root=ROOT):
+    """BUG-428 内容判据：产物 vs 当前源码重建结果，逐字节比。
+
+    rc 契约与 judge() 一致：0 相同 / 1 不同（陈旧）/ 2 判据无法自证。
+    **本函数不构建** —— 它假定 `moon build --target js --release` 已跑过；
+    构建动作留给调用方（CI 步骤 / 人工），避免判据里藏着一条分钟级命令。
+    """
+    if not os.path.isfile(dist_path):
+        return 2, "产物不存在: %s" % dist_path
+    fresh = built_artifact(root)
+    if not os.path.isfile(fresh):
+        return 2, "release 产物不存在（先跑 moon build --target js --release）: %s" % fresh
+    if os.path.getsize(fresh) == 0:
+        return 2, "release 产物是空文件（构建失败？）"
+    a, b = sha256_of(dist_path), sha256_of(fresh)
+    if a == b:
+        return 0, "PASS：产物与当前源码重建结果逐字节相同"
+    return 1, ("FAIL：产物陈旧 —— 与重建结果不同\n"
+               "  产物 sha256: %s\n  重建 sha256: %s\n"
+               "  修法：moon build --target js --release 后重新拷贝到发布位置") % (a, b)
```

**调用点（`main()` 里，建议加 `--content` 开关，默认关闭以保护 CI）**：

```diff
@@ main()
     ap.add_argument("--selftest", action="store_true")
+    ap.add_argument("--content", action="store_true",
+                    help="BUG-428：额外做「产物 vs 重建结果」内容比对（需先 build）")
     ...
     rc_ver, msg_ver = judge(text, want)
+    if args.content:
+        rc_con, msg_con = judge_content(SNAPSHOT)
+        if rc_con != 0:
+            rc = max(rc_ver, rc_con)   # 任一红即红；2 优先于 1
+            print(msg_con)
```

**⚠️ 我没有改文件**（按你指示先出方案）。以上是提案。

### 3.5 新增锁（3 格，含变异对照）

```python
# 加进 selftest()
# 锁 1（正例）：产物 == 重建 ⇒ 0
cell("content-same-is-pass",
     judge_content(同一文件两次)[0], 0)

# 锁 2（反例，本缺陷的现场）：产物 != 重建 ⇒ 1
#   夹具：两个内容不同但**版本字符串相同**的文件
cell("content-stale-same-version-is-1",
     judge_content(陈旧产物)[0], 1)

# 锁 3（⭐ 变异对照，判例-29/30）：
#   证明锁 2 真在比内容，而不是因为「文件不同名」碰巧红。
#   做法：造两个**版本字符串相同、内容差 1 字节**的文件，
#   断言 rc==1；再让它们内容相同，断言 rc==0。
#   ⇒ 若实现退化成「只比 version」，这两个文件版本相同 ⇒ 锁 2 必红。
cell("content-variant-version-equal-content-diff-is-1", ..., 1)
```

**⚠️ 判例-30 防护**：锁 3 **不断言源码里有 `sha256` 字样**（那会命中注释），只断言**判定结果随内容变化**。

---

## 4. 缺口与风险

| # | 项 | 说明 |
|---|---|---|
| **R1** | **未测跨机器/跨 moon 版本的可复现性** | 只测了「同一台机、同一工具链、同一天」两次构建字节相同。**换 moon 版本（CI nightly vs 本地 0.1.20261016）大概率不同** ⇒ (b) 在 CI 上可能恒红。**缓解**：内容判据**只在 release 前/本地跑，不进 CI 的常规臂**；或比「排序后的符号集合」而非字节 |
| **R2** | **`_build` 可能不存在** | `judge_content` 依赖 `moon build --release` 已跑过。**若没跑就 rc=2**（判据无法自证），不是 rc=1 —— 这个区分很重要 |
| **R3** | ~~未验证 `dist/` 与 `_build` 的拷贝关系~~ | ✅ **已实测消解，且是重大发现**：`scripts/refresh_dist.py`（85 行）**已经是正确的生成链**，但它的**第 4 步「自证」正是那个只比版本的守卫** —— 详见 §6 |
| **R4** | **任务 4 只做了静态 grep** | 我按「内容哈希相关行数」判断，**没有逐行读** `check_plugin_sync` / `check_host_installable`。它们可能用别的形态比内容 |
| **R5** | **未查 `_release/js/fist-mbt.js` 谁生成** | 它版本 0.3.9、mtime Oct 18，**比 dist 还旧 8 天**。生成路径未查 |
| **R6** | **install.ps1 的「自动更新」只给了建议** | 未实现、未验证 |
| **R7** | **`patch_esm_main.py` 的幂等性未实测** | §6.3 的 `judge_content` 依赖它。**应用前必须实测 `patch(patch(x)) == patch(x)` 逐字节成立** |
| **R8** | **§3.2 伪代码的 `built_artifact()` 目标路径是错的** | 我最初指向 `cmd/main/main.js`，实际应为 `cmd/cli/cli.js` + 隔 patch。**§6.2/§6.3 已修正** —— 这条自曝留在这里，提醒应用者以 §6 为准 |

---

## 5. 建议入档位置

1. **本报告**：`reports/2026-10-27-bug428-dist-guard-fix-plan.md`
2. **判例候选（本轮最重要）**：
   > **判例-XX：「守卫 PASS」不等于「产物新鲜」。**
   > `check_dist_snapshot` 比版本字符串，而本仓 52 个 commit 未 bump 版本
   > ⇒ **守卫 PASS 是「版本号对上了」，不是「代码对上了」。**
   > **⇒ 任何「产物 vs 源码」的守卫必须比内容/重建结果，不能比版本号或 mtime。**
3. **判例候选 ②（实测得来，可复用）**：
   > **判例-XX：符号探针要先测「符号在产物里是否存在」。**
   > MoonBit → JS **消除函数名**，保留字段名/表名/字符串。
   > **⇒ 拿函数名做探针会 100% 恒红** —— 这是「本该红的守卫恒红」，比恒绿更容易被发现，但同样是坏的。
   > **⇒ 任何 grep 式探针，第一件事是「先在生产形态上 grep 一次，确认探得到」。**
4. **比守卫更根本的一条（§3.3）**：
   **`install.ps1` 是一次性拷贝，无自动更新** ⇒
   **「代码改了但 MCP 行为不变」的真正根因是「没人重装」，不是「守卫没发现」。**
   **建议把「产物更新机制」单独立项**，否则修好守卫也只是「知道旧了」。

---

**本报告未修改 `scripts/check_dist_snapshot.py`。所有 diff 均为提案。未调 `bug_fix`。**

---

## 6. ⭐ 补充发现：`refresh_dist.py` 已经是正确的生成链，但它末尾的自证用错了尺

**这条比 §3.2 的 (b) 方案更精确地定位了改法。**（R3 实测时发现）

### 6.1 `scripts/refresh_dist.py`（85 行）的四步

```python
# 第 44-47 行
    ("构建 release 产物", ["moon", "build", "--target", "js", "--release", "cmd/cli"]),
    ("注入 ESM shim", [sys.executable, os.path.join(ROOT, "scripts", "patch_esm_main.py"), ARTIFACT]),
    ("拷贝到 dist", None),                                    # ARTIFACT → DIST
    ("自证版本一致", [sys.executable, os.path.join(ROOT, "scripts", "check_dist_snapshot.py")]),
```

**⇒ 前 3 步完全正确**（build → patch → copy），**问题在第 4 步**：
它调 `check_dist_snapshot.py` 做「自证」，而那个守卫**只比版本号**。

**⇒ 于是形成闭环缺陷：**
```
refresh_dist.py 自证 → check_dist_snapshot.py 只比版本
  ⇒ 「产物是旧的」这件事，在 refresh_dist 自己的自证里也**永远发现不了**
  ⇒ 只要版本号没变，第 4 步就 PASS，无论产物内容新旧
```

### 6.2 dist 与 _build 的大小差（消解 R3 的关键读数）

```
dist/fist-mbt.js                          5,590,176 B  md5=0b116e99…
_build/…/cmd/main/main.js                 5,513,600 B  md5=ec384783…
```

**两个文件大小差 76 KB、md5 不同 —— 但这不是「dist 陈旧」的证据，是生成链不同：**
- `refresh_dist.py` 用的是 **`cmd/cli`** 的产物（`ARTIFACT` 第 31 行 = `.../cmd/cli/cli.js`）
- 我实测比对的是 **`cmd/main`** 的产物（`.../cmd/main/main.js`）

**⇒ ⚠️ 我的 §3.2 伪代码里 `built_artifact()` 指向 `cmd/main/main.js` 是**错的**，
正确目标应是 `cmd/cli/cli.js` + **隔着 `patch_esm_main.py` 这一步**。**

**⇒ (b) 方案的正确形态必须复刻 refresh_dist 的链条：**
```
fresh = build(cmd/cli) → patch_esm_main(fresh) → 与 dist/fist-mbt.js 逐字节比
```
**不能直接比 `_build` 里的裸产物**（ESM shim 注入会让字节不同 ⇒ 恒红）。

### 6.3 因此最优改法其实更简单

**不是新写一个内容判据，而是把 `check_dist_snapshot.py` 的第 4 步自证从「比版本」升级为「比内容」**，
且**这个比较恰好可以复用 refresh_dist 已有的 ARTIFACT + patch 步骤**。

```python
# check_dist_snapshot.py 里新增（语义与 §3.4 相同，但目标路径修正）
CLI_ARTIFACT = os.path.join(ROOT, "_build", "js", "release", "build", "cmd", "cli", "cli.js")
DIST = os.path.join(ROOT, "dist", "fist-mbt.js")

def judge_content(dist_path=DIST, cli_artifact=CLI_ARTIFACT):
    """产物 vs 「当前源码 build + patch_esm_main」后的结果，逐字节比。

    ⚠️ 必须隔着 patch_esm_main 这一步：dist 是**已注入 ESM shim** 的产物，
    裸 build 产物（cmd/cli/cli.js）与它字节不同，直接比会恒红。
    """
    if not os.path.isfile(dist_path):
        return 2, "产物不存在: %s" % dist_path
    if not os.path.isfile(cli_artifact):
        return 2, "release 产物不存在（先跑 moon build --target js --release cmd/cli）"
    # 在临时副本上 patch，避免污染 _build
    with tempfile.TemporaryDirectory() as td:
        tmp = os.path.join(td, "cli.js")
        shutil.copy2(cli_artifact, tmp)
        subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "patch_esm_main.py"), tmp],
                       check=True, capture_output=True)
        a, b = sha256_of(dist_path), sha256_of(tmp)
    if a == b:
        return 0, "PASS：dist 与「当前源码 + ESM patch」重建结果逐字节相同"
    return 1, ("FAIL：dist 陈旧 —— 与重建结果不同\n"
               "  dist   sha256: %s\n  重建   sha256: %s\n"
               "  修法：python scripts/refresh_dist.py") % (a, b)
```

**⇒ 这样 `refresh_dist.py` 的第 4 步会自动变成「真自证」**（它调的就是这个脚本），
**不需要改 `refresh_dist.py` 一行** —— 这是最省、最不容易引入新缺陷的落点。

### 6.4 一条必须同时修的事

`patch_esm_main.py` **是幂等的**（AGENTS 已记），但我**未实测**它在「已 patch 过的文件」上再跑一次的字节结果。
**⇒ 应用 patch 前必须实测：`patch(patch(x)) == patch(x)` 是否逐字节成立。**
若不成立，`judge_content` 的临时副本要确保只 patch 一次（上面的写法已经是「拷裸产物 → patch 一次」，符合）。
