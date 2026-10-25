# `check_plugin_sync.py` J2~J6 变异格补齐（判例-29/30/50）

- **日期**：2026-10-25
- **执行人**：司令-ε
- **前置**：β 修完 J1（可注入 `_run_gen_check` + J 面覆盖对表 + J1 真变异格），
  并**自己承认边界**：「J2~J6 有认领、无变异。按判例-29/30，认领 ≠ 证明。」
- **本单**：给 J2~J6 各补一格**真变异**，让 cl7 六面全部有「变异 ⇒ 红」的对照。

---

## 一、结论

**J1~J6 六面现在全部有真变异格，且逐条实测「改坏真代码 ⇒ selftest 报对应的面」。**

| J 面 | 认领（原有） | 真变异（本单新增） | 实测结果 |
|---|---|---|---|
| J1 生成器漂移 | ✅ | ✅（β 已做） | CAUGHT |
| **J2 四宿主齐全** | ✅ | ✅ **新增** | **CAUGHT**（on-face） |
| **J3 无残留占位符** | ✅ | ✅ **新增** | **CAUGHT**（on-face） |
| **J4 版本一致** | ✅ | ✅ **新增** | **CAUGHT**（on-face） |
| **J5 启动参数单一真源** | ✅ | ✅ **新增** | **CAUGHT**（on-face） |
| **J6 计数一致** | ✅ | ✅ **新增** | **CAUGHT**（on-face） |

生产路径**零回归**：`PASS 插件态一致：4 宿主 / 64 个生成文件 / 170 工具 / v0.3.10`。

---

## 二、注入点设计

`collect_problems()` 原有的注入面只有 `gen_check_cmd`（J1）。本单加 **4 个关键字参数**，
缺省全部取模块常量 ⇒ **生产路径行为逐字不变**：

| 参数 | 覆盖 | 服务 J 面 |
|---|---|---|
| `gen_check_cmd` | 生成器子进程命令 | J1（β 原有） |
| `host_entries` | 四宿主入口清单 `{host: [Path…]}` | **J2** |
| `generated` | 生成文件清单 | **J3 / J6** |
| `plugins_dir` | `plugins/` 根 | **J4** |
| `mcp_pair` | `(claude_mcp, root_mcp)` | **J5** |

```python
def collect_problems(tools, version, gen_check_cmd=None, *,
                     host_entries=None, generated=None, plugins_dir=None,
                     mcp_pair=None):
```

---

## 三、五格变异的构造方式（统一骨架）

每格都是**同一个三段式**（这是本单的方法论核心）：

```
① 造「干净的合成世界」 —— 让 J2~J6 全绿
   ↓ 先断言它真的全绿（否则下面的「红」分不清是变异还是本来就有）
② 只把一个维度改坏 —— 注入坏路径 / 坏内容 / 坏版本 / 坏数字
   ↓ 断言主判据报出**对应面**的那条 failure
③ 判例-50 自证 —— 断言「变异前后的 problems 不同」
   ↓ 证明变异真的命中了判据，不是没生效所以恰好绿
```

### 各格具体注入

| 面 | 变异动作 | 期望的 failure |
|---|---|---|
| **J2** | 把 `atomcode` 的入口换成**不存在**的 `GHOST.md` | `J2 缺宿主入口` |
| **J3** | 生成文件里塞 `{{PLACEHOLDER}}` | `J3 残留未替换占位符` |
| **J4** | claude manifest 写 `"version": "99.99.99-WRONG"` | `J4 … 未声明 moon.mod 版本` |
| **J5** | `claude/.mcp.json` 写成 `{"mcpServers": {"DRIFT": true}}`（与根真源不同） | `J5 … 不一致` |
| **J6** | `SKILL.md` 的 `tools=` 写成 `len(tools)+7` | `J6 … 不符`，且**必须点名**偏差值 |

---

## 四、变异证据（判例-29/30/50 对照）

### 4.1 判例-29：自检必须命中**实现路径**，不能只测辅助纯函数

本单的变异格**调的是 `collect_problems()`（主判据真身）**，不是辅助纯函数：
```python
def _run(**kw):
    base = dict(host_entries=_hosts, generated=[_gen_ok],
                plugins_dir=_plugins_ok, mcp_pair=(_claude_mcp_ok, _root_mcp_ok))
    base.update(kw)
    return collect_problems(tools, version, **base)     # ← 主判据
```

### 4.2 判例-30：改坏的是**代码**，不是注释

**外部验证**（把每个 J 分支的 `problems.append(...)` 换成 `pass`，跑 selftest）：

```
J2   rc=1   crashed=False  caught=True  on-face=True
       -> - J2-变异对照失守：注入不存在的宿主入口后，主判据没报 `J2 缺宿主入口`
J3   rc=1   crashed=False  caught=True  on-face=True
       -> - J3-变异对照失守：注入含 `{{` 的生成文件后，主判据没报 `J3 残留未替换占位符`
J4   rc=1   crashed=False  caught=True  on-face=True
       -> - J4-变异对照失守：注入错误版本后，主判据没报 `J4 … 未声明 moon.mod 版本`
J5   rc=1   crashed=False  caught=True  on-face=True
       -> - J5-变异对照失守：注入内容不同的启动参数后，主判据没报 `J5 … 不一致`
J6   rc=1   crashed=False  caught=True  on-face=True
       -> - J6-变异对照失守：注入错误 tools= 数字后，主判据没报 `J6 … 不符`
```

**`on-face=True` 是关键**：不只验证「红了」，还验证「**红在对应的那个面上**」——
避免「J3 坏了报的是 J6」这种串面。

### 4.3 判例-50：先验「变异真的改变了被测行为」

每格都对比**干净世界**与**变异世界**：

```python
# 基线：干净世界必须零 J2~J6 问题，否则下面的变异无意义
_clean, _, _ = _run()
_clean_j = [p for p in _clean if any(p.startswith("J%d" % i) for i in (2,3,4,5,6))]
if _clean_j:
    fails.append("J2~J6 变异基线不干净 ⇒ 下面的变异无意义")
```
外加各格独立断言，例如 J2：
```python
if len(_j2) == len(_clean_j):
    fails.append("J2-变异对照未生效：注入坏入口前后的 J2 问题数相同 ⇒ 变异没命中判据")
```

---

## 五、★ 过程中抓到的一个真缺陷（判据崩溃，不是报违例）

### 5.1 现象

第一版变异格用 `tempfile.TemporaryDirectory()` 造合成路径，selftest 直接**抛异常**：

```
ValueError: 'C:\Users\...\cl7-mut-xxx\atomcode\GHOST.md' is not in the subpath of
            'E:\IDEProjects\AI\FIST-Mbt'
  at  problems.append(f"J2 缺宿主入口：{host} → {f.relative_to(ROOT)}")
```

### 5.2 根因

`collect_problems` 里有 **4 处 `p.relative_to(ROOT)`**。当被检路径**不在仓库子树内**时
（外部路径、合成路径、软链、其他盘的挂载点），`relative_to` 抛 `ValueError` ⇒
**判据不是在报告违例，而是崩了**。

**这是真缺陷**：判据对「被检路径不在仓库内」这个形态没有防御，而那是完全可能的输入
（比如误把 `plugins/` 软链到别处、或 CI 的 checkout 路径变化）。

### 5.3 修法

新增 `_rel(p)` 辅助，4 处全部改用它：
```python
def _rel(p):
    try:
        return p.relative_to(ROOT)
    except ValueError:
        return p          # 不在 ROOT 下 ⇒ 原样显示绝对路径
```

**行为变化**：仅在「路径不在 ROOT 子树内」时，从 **崩溃** 变为 **正常报出绝对路径**。
生产路径（全部在 ROOT 内）**逐字不变**。

---

## 六、★ 我的第一次变异测试是**假绿**（自查纠错）

### 6.1 发生了什么

第一次跑「改坏分支 ⇒ 看 selftest 是否红」，我把变异文件放在 `tempfile.mkdtemp()` 下，
得到 **5/5 CAUGHT** —— 看起来完美。

**但那是假的。** 深挖发现：

```
=== STDOUT ===
（空）
=== STDERR ===
FileNotFoundError: ... '_tool_registry.py'
  at  _ir_spec.loader.exec_module(_tool_registry)     # line 36
```

脚本第 36 行用 `Path(__file__).resolve().parent / "_tool_registry.py"` 加载共享模块。
文件一旦被复制到临时目录，**import 阶段就崩了，根本没跑到 selftest**。

⇒ **`rc != 0` 被我当成了「判据咬住了」，实际是「脚本没跑起来」。**

### 6.2 这个错误和判例-37 是一族

【判例-37】**断言/判据过严 ⇒ 把合法判红。**
本单的形态更隐蔽：**测试方法过松 ⇒ 把「崩溃」判成「生效」。**

两者的共同点：**判据（这里是我人工的判定）红/绿的时候，红的/绿的不是真问题。**

### 6.3 修正后的测法

把变异文件放在 **`scripts/` 下用临时文件名**（`_mut_probe_J2.py` 等），
这样 `__file__` 的父目录就是 `scripts/`，`_tool_registry.py` 能正常加载：

| 版本 | 方法 | 结果 | 真实性 |
|---|---|---|---|
| 第一版 | 复制到 `tempfile.mkdtemp()` | 5/5 CAUGHT | ❌ **假绿**（全是 import 崩溃） |
| **第二版** | 放 `scripts/` 下临时文件 | **5/5 CAUGHT，crashed=False，on-face=True** | ✅ **真** |

**新增判定维度**：除了 `caught`（是否变红），必须同时看 `crashed`（是否因异常退出）
和 `on-face`（是否红在对应面）。**三者都满足才算 CAUGHT。**

---

## 七、纪律自检

| 项 | 结果 |
|---|---|
| 只动 `scripts/check_plugin_sync.py` + 本报告 | ✅ |
| 未改 `plugins/` | ✅（`git status` 中 plugins 的 M 全是他人改动） |
| 未改 `scripts/` 其他文件 | ✅ |
| `git commit -F msg -- <paths>`（`-F` 在 `--` 前） | ✅ |
| 禁止 `git add -A` / add 目录 / add 通配 | ✅ 逐个列文件名 |
| 临时探针文件零残留 | ✅ `ls scripts/_mut_probe_*.py` 无输出 |
| 生产路径零回归 | ✅ `PASS … 170 工具 …` rc=0 |
| `--selftest` rc=0 | ✅ |

---

## 八、验收对照

| 验收项 | 结果 |
|---|---|
| ① `--selftest` rc=0 | ✅ `SELFTEST OK` |
| ② J1~J6 每条都有变异格 | ✅ 6/6（本单补 5 条） |
| ③ 每条变异格验了「变异真生效」 | ✅ 判例-50 基线对比 + 各格独立断言 |
| ④ commit 文件数 = 1 或 2 | ✅ 2（脚本 + 报告） |
| ⑤ 三端一致 | ✅ `gitcode/main == HEAD`（commit 前已同步） |

---

## 九、可复现命令

```bash
# ① 生产路径与自检
python scripts/check_plugin_sync.py
python scripts/check_plugin_sync.py --selftest

# ② 外部验证「改坏真代码 ⇒ 自检变红」（注意放 scripts/ 下，否则 import 会崩）
#    见本报告 §6.3 的第二版方法
```

## 来源

| 项 | 来源 |
|---|---|
| 任务 | 统帅派工（2026-10-25） |
| 前置 | β 的 `check_plugin_sync.py` J1 修复与自述边界 |
| 判例-29/30/50 | 本仓既有判例（变异对照必做） |
| 判例-37 | 自证格过严/过松都会判错——本单 §6 是同族的「测试方法过松」变体 |
