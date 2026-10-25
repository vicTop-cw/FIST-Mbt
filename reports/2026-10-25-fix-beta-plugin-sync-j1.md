# 修 `check_plugin_sync` 的 J1 假绿 + 补 J 面覆盖对表 · 2026-10-25

**commit**：`b53f65bc` ｜ **判例**：29 / 30 / 50 ｜ **来源**：侦察报告 `96348c64`

---

## 一、结果摘要

| 项 | 修前 | 修后 |
|---|---|---|
| J1「生成器漂移 ⇒ 红」有无自检 | **无**（把 `if r.returncode != 0:` 改成 `if False:`，selftest 仍 `SELFTEST OK`、一字不差） | **有**（注入 `-c "raise SystemExit(7)"` ⇒ 断言主判据报 `J1 插件态漂移`） |
| J2~J6 有无自检认领 | **无**（自检只碰 `is_generated`） | **有**（对表格两向都红：漏格 / 幻影格） |
| 自检是否命中共判据实现路径 | 否（只测辅助纯函数） | **是**（真调 `collect_problems()`，即 `main()` 的判定体） |
| `--selftest` | rc=0（但没在测主判据） | rc=0（**并且在测**） |
| 插件真跑 | rc=0 | rc=0 + 多印一行 J 面覆盖 |

**一句话**：cl7 唯一守卫的主判据，从「零自检覆盖」变成「变异对照钉住 + 覆盖面双向对表」。

---

## 二、J1 可注入函数（① 最小）

```python
def _run_gen_check(cmd=None):
    """J1 的子进程入口：跑 `gen_plugins.py --check`，**可注入**以便自检钉住这条分支。"""
    if cmd is None:
        cmd = [sys.executable, str(ROOT / "scripts" / "gen_plugins.py"), "--check"]
    return subprocess.run(
        cmd, capture_output=True, text=True, encoding="utf-8", errors="replace",
        env={**os.environ, "PYTHONIOENCODING": "utf-8"},
    )
```

**配套重构**：`main()` 的判定体抽成可测内核

```python
def collect_problems(tools, version, gen_check_cmd=None):
    """返回 (problems, generated, j_faces)。从 main() 抽出来是为了让自检能真调主判据。"""
```

`gen_check_cmd` 透传给 `_run_gen_check` —— **这是①与③的共同地基**：
没有可注入性，自检就只能干看着；没有可测内核，自检就只能测辅助函数。

---

## 三、J 面覆盖对表面板（③ 结构性）

**两个真源，不写死数字（判例-16）**：

| 真源 | 位置 | 含义 |
|---|---|---|
| 实现面 | `collect_problems` 里 `j_faces.add("<n>")` | **执行过**的 J 分支 |
| 认领面 | `SELFTEST_CLAIMED_J_FACES = {"1","2","3","4","5","6"}` | 自检为哪些面配了格 |

**双向判定**（`j_face_self_consistency()`）：

| 方向 | 违例文案 | 意味着 |
|---|---|---|
| 实现有 · 认领无 | `J-COVERAGE 实现里有 J 面未被 --selftest 认领：J9（新增 J 分支必须同批补自检格…）` | 新增了 J 分支但没配自检 ⇒ **假绿复发入口** |
| 认领有 · 实现无 | `J-COVERAGE 自检认领了实现里不存在的 J 面：J9 ⇒ 幻影格` | 自述滞后于实现 |

**跑在哪三层**：
1. **自检**里（`selftest()`）—— 认领表 vs 实现
2. **主判据**里（`main()` → `collect_problems` → `j_face_self_consistency`）—— 让「实现加了 J9 而自检没跟上」在**正判据**上现形，不必靠自检自说自话
3. **反证格**：往合成输入塞幻影面 J99，断言对表格**真的会红**（证明它不是恒绿装饰）

### ⚠️ 第一版就红了，如实记录

`j_faces` 最初按「**报过的**面」记账 ⇒ 干净仓库上所有分支都跑但都不报 ⇒ 集合为空
⇒ 对表格把 6 个面全判成幻影格：

```
SELFTEST FAIL（cl7 判据自身违例）：
  - J-COVERAGE 自检认领了实现里不存在的 J 面：J1, J2, J3, J4, J5, J6 ⇒ 幻影格
```

**修正为「执行过的面」**（`j_faces.add("n")` 提到每个分支入口）。
对表格要回答的是「这个 J 分支**还在不在**」，不是「它今天报没报」。
—— 这条是**对表格自己抓出来的**，不是我事后想到的。

---

## 四、变异对照证据

### 修复前（侦察阶段，假绿证据）
```
baseline        --selftest rc=0  "SELFTEST OK：合成克隆路径两判都对，真实生成集合 64 个文件"
J1 -> if False  --selftest rc=0  "SELFTEST OK：合成克隆路径两判都对，真实生成集合 64 个文件"   ← 一字不差
```

### 修复后（全部 CAUGHT）

| 变异 | rc | 报出的失败行 |
|---|---|---|
| **M1[原逃脱变异]** J1 漂移分支 → `if False:` | **1** | `J1-变异对照失守：注入必然非零的生成器命令后，主判据没报 'J1 插件态漂移' ⇒ J1 分支已失效` |
| M2 删掉 J1 的 `j_faces.add("1")` | **1** | `J1-变异对照失守：J1 触发后没把 J 面 '1' 记进 j_faces` |
| M3 `_run_gen_check` 忽略注入 cmd | **1** | 同 M1（对照失去可注入性） |
| M4 实现多点一个未认领面 J9 | **1** | `J-COVERAGE 实现里有 J 面未被自检认领：J9` |

**M1 正是侦察阶段逃过的那一发**，现在被钉住。四次变异后文件均逐字节还原
（`git diff --numstat` 只剩本笔的正式改动）。

### 判例-50 自证格（本轮新增纪律：不能只看 rc）

```python
real_rc = _run_gen_check().returncode          # 真生成器（应为 0）
if real_rc == rc_bad.returncode:               # 假命令 rc=7
    fails.append("判例-50 自证失败：假命令 rc=%d 与真生成器 rc=%d 相同 ⇒ 本格没区分开"
                 "『漂移』与『干净』，变异未命中锁")
```
⇒ 这一格绿**不是**因为「变异没生效所以没红」，而是因为假命令的 rc 确实与真命令不同。
**把「我变异了」和「我变异成功了」分开断言。**

---

## 五、验收实测读数（逐条对统帅验收标准）

| # | 命令 | 读数 |
|---|---|---|
| 1 | `python scripts/check_plugin_sync.py --selftest` | **rc=0** ｜ `SELFTEST OK：…J1 变异对照已钉住（假命令 rc=7 ⇒ 报 J1 插件态漂移）；J 面覆盖对表通过（6 个面：J1, J2, J3, J4, J5, J6）` |
| 2 | `run_guards.py --list \| grep '缺执行面'` | **`缺执行面 0`** |
| 3 | `python scripts/check_battery_count_doc.py` | **PASS** ｜ `rulers=120 ci=45 battery=79 missing=0 gate=87 exempt=28 unclassified=7` |
| 4 | `python scripts/check_plugin_sync.py`（插件真跑） | **rc=0** ｜ `PASS 插件态一致：4 宿主 / 64 个生成文件 / 170 工具 / v0.3.10 / 启动参数真源 .mcp.dev.json` + `J 面覆盖：6 个面（J1…J6）全部被 --selftest 认领` |
| 5 | `moon check --target js` | **501 warnings, 0 errors** |

三端：本笔提交 `b53f65bc` 落在 main 上；`gitcode/main` 由统帅推送后一致（本笔未做 force/推送动作）。

---

## 六、遗留风险

1. **③ 的对表格认的是「J 分支存在」，不是「J 分支判得对」。**
   J2~J6 的**判定正确性**仍只由各自的违规场景保证；本笔**没有**为每个 J 面造违规树
   （要造就得改真实 `plugins/` 或另建整棵夹具树，属独立工作量）。
   **对表格堵的是「分支被删 / 新增没跟上」，不是「判定写错」。** 这个边界必须写清，
   否则下一个人会以为「对表通过 = J2~J6 都对」。
2. **J2~J6 的变异对照仍缺**。本笔只给了 J1 的真变异格；其余 5 面有「认领」无「变异」。
   按判例-29/30，认领 ≠ 证明。**建议下一单：为 J2/J3/J4/J5/J6 各补一格真变异**
   （J3 可注入 `PLUGINS`、J4/J5 可注入版本/路径、J6 可注入实测工具数）。
3. **判例-50 正文已在 `cf73a091` 由他人落地**（含我的两次自纠）；本笔不重复写，
   只在自检里加了**可执行**的 50 自证格——文字纪律 + 机器判据各一份，不冲突。
4. 侦察报告里「其余 29 把未抽查」的边界不变，仍未证。
