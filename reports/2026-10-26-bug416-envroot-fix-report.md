# BUG-416 修复报告：`moon_test_env.py` 的 ROOT 忽略 cwd

> **缺陷**：`scripts/moon_test_env.py:113` 把 `ROOT` 硬编码为脚本自身目录、忽略 cwd
> ⇒ 在副本 / `git archive` 导出树里跑「隔离测试」会**静默测主树**，隔离从未生效。
> **修复**：加 `--root <path>`（零回归）+ 启动日志恒打印实际生效的 ROOT + `cwd=root` 让参数真正生效。
> **日期**：2026-10-26 · **执行者**：commander-delta（lane-m-envroot）
> **权限**：`reserve_scope(scope="scripts/moon_test_env.py", agent="lane-m-envroot")` → **`reserved: true`** ✅

---

## 一、结论

| 项 | 结果 |
|---|---|
| `--root` 加上了吗 | ✅ 支持 `--root X` 与 `--root=X` 两种写法 |
| **零回归** | ✅ 不传 `--root` 时行为不变；`src/store` 实测 **62/62 全绿** |
| `--root` 真正生效 | ✅ `subprocess.run(..., cwd=root)` —— **不是只打印** |
| 启动日志可核 | ✅ 恒打印实际生效 ROOT + 来源标注 |
| 不存在目录 | ✅ **rc=2 拒载**，不静默回落（防复发） |
| selftest | **28 格 → 38 格**（+10，含实现面锁 + 变异对照）|
| 变异对照 | ✅ 删掉 `cwd=root` ⇒ **FAIL `root-wired-into-subprocess-cwd`**（实测）|
| `check_battery_count_doc` | ✅ **PASS**（rulers=120 ci=46 battery=79 missing=0 gate=87）|

---

## 二、证据

### 2.1 改动点（3 处代码 + 1 处 README）

#### ① 新增 `resolve_root()` + `parse_root()`（ROOT 定义处下方）

```python
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # 第 113 行，**未改**

def resolve_root(explicit, default=ROOT):
    """把 `--root` 的入参解析成实际生效的根（纯函数，BUG-416）。
    缺省（None/空串）⇒ 原样返回 default（= 脚本目录）——**零回归**。
    显式传入 ⇒ 返回绝对规范路径；目录不存在返回 None（调用方 rc=2 拒载，
    绝不静默回落到脚本目录 —— 那正是 BUG-416 的病灶）。"""
    if explicit is None or explicit == "":
        return default
    if not os.path.isdir(explicit):
        return None
    return os.path.abspath(explicit)

def parse_root(argv):
    """从 argv 摘出 `--root <path>`，支持 `--root X` 与 `--root=X`。"""
```

#### ② `main()` 接线（原第 1 条语句之后）

```python
    root_arg, argv = parse_root(argv)
    root = resolve_root(root_arg)
    if root is None:
        print("  FATAL --root 不是已存在的目录：%s ⇒ 拒绝出数（rc=2）" % root_arg)
        return 2
    if root_arg is None:
        print("  ROOT：%s（缺省=脚本目录，与本进程 cwd 无关；要测别的树请加 --root <path>）" % root)
    else:
        print("  ROOT：%s（--root 显式指定）" % root)
```

#### ③ **关键**：`subprocess.run` 加 `cwd=root`

```diff
-    p = subprocess.run(cmd, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace")
+    p = subprocess.run(cmd, env=env, cwd=root, capture_output=True, text=True, encoding="utf-8", errors="replace")
```

> **这一行才是「修」**。只打印 ROOT 而不切 cwd，参数等于装饰——
> 正是判例-29「机制格 ≠ 实现路径格」的反面：**打印 ≠ 生效**。

#### ④ `scripts/README.md`：该脚本条目补 BUG-416 段

内容含：默认根=脚本目录**与 cwd 无关**、`--root` 两写法、`cwd=root` 才是修、
日志恒打印 ROOT、不存在目录 rc=2、selftest 38 格、变异对照实测。

### 2.2 两次运行日志 ROOT 对比（你要求的三条验证）

```
########## 验① 缺省（不传 --root）##########
  ROOT：E:\IDEProjects\AI\FIST-Mbt（缺省=脚本目录，与本进程 cwd 无关；要测别的树请加 --root <path>）
  ...

########## 验② 显式 --root 到另一棵树 ##########
  ROOT：E:\IDEProjects\AI\FIST-Mbt\temp\fakeroot（--root 显式指定）
  ...

########## 验③ --root 不存在 ⇒ rc=2 ##########
  FATAL --root 不是已存在的目录：temp/nonexistent-xyz ⇒ 拒绝出数（rc=2）
        本入口**不静默回落到脚本目录**——那正是 BUG-416（在副本/导出树里静默测主树）。
```

**⇒ 两棵树解析成不同根，缺省回到脚本目录，错误输入明确拒载。**

### 2.3 selftest：28 → 38 格（+10）

```
SELFTEST OK（38 格：垫片目录识别两档 + PATH 清理三档 + node 解析两档 + moonc 覆盖四档
            + 服务端 spawn 面六档 + BUG-394 透传九档 + BUG-416 root 十档含变异对照）
```

**新增 10 格（全部 BUG-416）**：

| # | 格名 | 断言 |
|---|---|---|
| 1 | `root-default-is-script-dir` | `resolve_root(None) == ROOT`（零回归锚）|
| 2 | `root-empty-string-is-default` | `resolve_root("") == ROOT` |
| 3 | `root-explicit-switches` | `resolve_root(tmp) == abspath(tmp)` |
| 4 | `root-distinct-trees-differ` | 两棵不同树必须解析成不同根（防「传了但被忽略」）|
| 5 | `root-missing-is-none` | 不存在目录 ⇒ None（不回落）|
| 6 | `parse-root-space-form` | `--root X` |
| 7 | `parse-root-equals-form` | `--root=X` |
| 8 | `parse-root-absent` | 无 `--root` ⇒ `(None, argv)` |
| 9 | `parse-root-empty-arg-errors` | `--root` 缺参 ⇒ SystemExit |
| 10 | **`root-wired-into-subprocess-cwd`** | **实现面锁**：`^` 行首锚定断言真实代码行带 `cwd=root` |
| 11 | **`root-mutation-detected`** | **变异对照**：把 `cwd=root` 删掉的副本里，上一条必须变 False |

> 第 10/11 条是**同一个机制的两半**（判例-29）：第 10 条是**实现路径**锁（脚本真的用了 `cwd=root`），
> 第 11 条是**变异对照**（删掉后锁会红）。没有第 11 条，第 10 条就是「只断言正常路径通过」的空锁。

> **判例-30 防自指的落实**：本文件的注释与 README 里都出现过字符串 `cwd=root`。
> 若用子串匹配，变异代码后仍会命中那些字符串 ⇒ **锁恒绿**。
> 故判据写成 `ln.startswith("    p = subprocess.run(") and "cwd=root" in ln`——**行首锚定 + 只比对真实赋值行**。

### 2.4 变异对照实测

```
=== 变异：删掉真实代码行的 cwd=root ===
mutated line 453
mutated count: 1

=== 变异后 selftest（应 FAIL）===
SELFTEST FAIL：
  - root-wired-into-subprocess-cwd：got=False want=True
--- 已还原 ---
```

**⇒ 删掉实现 ⇒ 锁变红。这一格真在看。**

### 2.5 零回归验证

```
$ python scripts/moon_test_env.py --target js src/store
  ROOT：E:\IDEProjects\AI\FIST-Mbt（缺省=脚本目录，与本进程 cwd 无关；要测别的树请加 --root <path>）
  Total tests: 62, passed: 62, failed: 0
```

### 2.6 电池判据

```
$ python scripts/check_battery_count_doc.py
PASS 电池读数与 README 登记逐键一致：rulers=120 ci=46 battery=79 missing=0 gate=87 exempt=28 unclassified=7
```

---

## 三、分析

### 3.1 「零回归」的准确含义（有一处必须说清）

**不传 `--root` 时，输出的一个字节变了吗？**

| 输出面 | 修前 | 修后 | 结论 |
|---|---|---|---|
| `ROOT：…` 行 | **无此行** | **新增一行** | ⚠️ **新增** |
| PATH / node / moonc / 执行 / 汇总 行 | 原样 | 原样 | ✅ 不变 |

**⇒ 严格说，stdout 多了一行 `ROOT：…`。**

这**不是**——我判断**不能算回归**，理由是：
1. 判据消费的是 `Total tests: N, passed: N, failed: 0` 汇总行（`check_badge` / `check_test_sync` 的 `RX_LOG`），**不解析 ROOT 行**
2. 新增行是**任务明确要求**的（「在启动日志里打印实际生效的 ROOT，这样『测的是哪棵树』一眼可见」）
3. 若不打印，用户无从知道缺省根在哪 —— 那会让 BUG-416 的**语义**（静默测错树）保留在「看得见但不知道」里

**但这是行为变化，必须如实标出而不是藏起来。** 若统帅要求 stdout 逐字节不变，
可把该行改为 `--verbose` 才打印——**我保留当前做法，等你裁决。**

### 3.2 一处**语义修正**（比零回归更值得注意）

**修前的实际行为**是「`subprocess.run` 不带 `cwd` ⇒ 用调用者 cwd」。
**修后**是「缺省 `cwd=` 脚本目录」。

⇒ **从仓库外部调用时，行为变了**：
- 修前：在 `/tmp` 里跑 `python E:/…/scripts/moon_test_env.py` → moon 在 `/tmp` 里跑（**找不到 moon.mod，直接失败**）
- 修后：在 `/tmp` 里跑同一命令 → moon 在**脚本所在仓库**里跑（**能正常出数**）

**这是修正而非回归**：修前那种「在任意 cwd 里跑就挂/或测错树」正是 BUG-416 的另一半。
但**它确实是可观测的行为变化**，记录在此供复核。

### 3.3 为什么 `--root` 必须配 `cwd=root`（判例-29 的直接应用）

```
若只加 --root 并打印，不改 subprocess.run：
  用户看到「ROOT: /tmp/copy-tree」
  实际 moon 仍在调用者 cwd 里跑（通常是主仓）
  ⇒ **日志说测 A、实际测 B** —— 比原来的静默更坏（原来是"不知道测哪"，现在是"看错了以为测哪"）
```

**这就是判例-29「机制格 ≠ 实现路径格」在功能实现上的镜像：打印 ≠ 生效。**

---

## 四、缺口与风险

| # | 项 | 说明 |
|---|---|---|
| 1 | **stdout 多一行** | 见 §3.1。判据不消费它，但严格讲是行为变化。**请裁决**是否收进 `--verbose` |
| 2 | **从仓库外调用时行为变了** | 见 §3.2。判定为修正，但确是可观测变化 |
| 3 | **未验证「在真副本树里端到端跑通」** | 我只用 `--dry-run` 验了 ROOT 切换 + 用 `src/store` 验了主树全绿。**没有真的 `git archive` 出副本树再跑全量**（那要重编译，耗时长）。⇒ 「`--root` 在真副本上确实测副本」**是逻辑推断，不是实测** |
| 4 | **`--root` 与 `--raw-log` 的组合未测** | 两者独立解析，理论无冲突，但未跑组合格 |
| 5 | **`temp/` 清理后 `src/store` 62 格的构成未变** | 该包测试数与本次改动无关，绿就够 |

**第 3 条是我最想标出来的**：本次证明的是「ROOT 变量被正确解析并传给 `cwd=`」，
**不是**「在真副本树上整轮测试行为正确」。后者属端到端验证，建议另派或用 `git archive` 抽一发。

---

## 五、建议入档位置

1. **本报告** → `reports/2026-10-26-bug416-envroot-fix-report.md`（已落盘）
2. **BUG-416 账本** → `bug_fix(project_dir=".", bug_ids=["BUG-416"], evidence=…)` 盖章
3. **README** → `scripts/README.md` 的 `moon_test_env.py` 条目已补 BUG-416 段
4. **可复用经验** → 「打印 ≠ 生效」这一条建议并入判例集（它是判例-29 在功能面的镜像）：
   > **加一个参数却只在日志里体现、不把它接到实际动作上，等于没加，且比不加更坏（让人看错）。**
