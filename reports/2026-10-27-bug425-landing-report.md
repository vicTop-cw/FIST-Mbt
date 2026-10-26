# BUG-425 落地报告 · `check_test_sync` 读数面与原文面同源 · Lane AG · 2026-10-27

> **落地形态**：本单的核心代码 **已在工作树中（他人先行实现，126 行）**；
> 本 lane 的职责是 **核它是否真的对、修掉它的缺陷、跑出四次真读数**，而不是重写。

---

## 一、结论

### 1.1 `scripts/` 当前状态（任务 1，逐条实测）

| 核查项 | 读数 |
|---|---|
| `git log --oneline -5 -- scripts/` | `4e43f4dc` BUG-428 部署面新鲜度 / `ceb44f13` 测试总数 1463→1532 / `60929d14` 1460→1463 / `1375f36a` check_plan_landing / `a309cdbe` moon_test_env --root |
| `run_guards.py:301-302` | **仍是 `gated(..., expect=0)`**；`--only` **不支持**（grep 无命中）|
| `scripts/` 在途 | **1 个：`M scripts/check_test_sync.py`**（126 插入 / 2 删除）|
| `check_test_sync.py` 行数 | **1158 → 1155**（Round 9 时约 500 行 ⇒ **已被人大幅改过**，我的 Round 9 patch 是**旧版**，不能照抄）|

**⇒ 关键发现：BUG-425 的实现早已落在工作树里**，且已包含我 Round 9 指出的「锁 5 假绿」修正
（`dirty_mbt_files` 加了 `porcelain_text` **注入面**，注释直接写「避免在干净 CI 上 `all(...)` 恒 True 的假绿」）。

### 1.2 我修掉的真缺陷（两项）

#### (a) 在途实现的语法错误（已由并行 lane 修掉，我确认）

**在途实现一度整份文件跑不起来**（我首次读到时）：

```
$ python scripts/check_test_sync.py --selftest
  File "scripts/check_test_sync.py", line 1048
    _fake = " M src/a.mbt
            ^
SyntaxError: unterminated string literal (detected at line 1048)
```

**三行 porcelain 夹具字面量没闭合**。在我读取后约 1 分钟（文件 mtime `02:09:00`），
该处已被改成 `"\n".join([...]) + "\n"`。**如实记录**：这是「同一文件多 lane 并发」的时序现象，
**该行不是我修的**（我未编辑它）。

#### (b) 判例-29 的原始形状缺一格 —— **本单修掉**

在途实现的 6 格锁**全部测纯函数**（`advisories()` / `dirty_mbt_files()`），
而降级**动作**内联在 `run()` 里 ⇒
**把 `run()` 里那段降级整段删掉，6 格照样全绿** —— 这正是判例-29「机制格 ≠ 实现路径格」。

**我的修法**：抽出 `advisory_verdict(dirty_paths, strict)` 纯函数
→ 返回 `AdvisoryVerdict(warn_paths, rc)`；`run()` 退化为 `return veto.rc`。
新增**锁 7（实现路径格）** 直接断言 `rc`。

**变异实测（真跑，非设计）—— 这一段比结论更重要**：
```bash
# 把 AdvisoryVerdict(list(adv), 0) 改成 (…, 1)  —— 等于删掉降级效果
$ python scripts/check_test_sync.py --selftest
SELFTEST FAIL [bug425-dirty-must-degrade-rc0] BUG-425 advisory 三闸失守
rc=1                                    ← 锁 7 真红了
# 恢复后
SELFTEST PASS 33 个变体…   rc=0
```
**这一格证明的正是「锁 7 在看实现路径，而不只是纯函数」。**

### 1.3 `run_guards` 要不要同批改（任务 3）：**不需要**

**判断依据（实测）**：

```python
# scripts/run_guards.py:974 —— 判红的**唯一**依据
ok = p.returncode in allow if allow else (p.returncode == c["expect"])
```
- `run_guards` **不扫 stdout 任何关键字**（`grep 'WARN\|stdout' ` 只命中文档注释与 `stdout.reconfigure` 编码设置）
- 本方案 **rc 恒 0**（advisory 不判红）⇒ `returncode == expect(0)` ⇒ **PASS**
- **实跑验证**：按 `run_guards` 的确切 argv `check_test_sync.py temp/pt27.log --fresh` 跑一次
  ⇒ **rc=0**（尾部是 `ADVISORY` 行，但退出码是 0）

**⇒ `run_guards` 无需改动。** 结论的硬依据是「rc=0 且 run_guards 只看 rc」两条同时成立。

### 1.4 五格 selftest：**全绿（实际有 6 格）**

```
$ python scripts/check_test_sync.py --selftest
  ok  fix-real-native-line-is-not-js
  ok  fix-native-veto-is-live
  ok  fix-has-no-write-path
  ok  fix-skips-history
  ok  bug425-advisory-three-gates
SELFTEST PASS 33 个变体各自命中自己指名的判据（计数由 run_case 实测累加，非手写）
rc=0
```

---

## 二、证据

### 2.1 六格设计（在途实现 `selftest()` 的 `_bug425()` 内）与统帅要求的五格对照

| 统帅要求 | 在途实现的格 | 内容 |
|---|---|---|
| 锁 1 干净 ⇒ 正常判定 | `advisories([]) != []` | 干净工作树不降级 ✅ |
| 锁 2 脏 ⇒ WARN + rc=0 + **点名文件** | `advisories(_d) != _d` | 返回**完整脏文件列表** ✅ |
| 锁 3 变异：删「脏则降级」⇒ 锁 2 必红 | **锁 7**：`advisory_verdict(_d).rc == 0` | ✅ **本单新增**（抽出纯函数后方可测；变异实测必红）|
| 锁 4 变异：删 `CI=true ⇒ strict` ⇒ 必红 | `os.environ[STRICT_ENV]="true"` 后断言 `advisories(_d)==[]` | ✅ 删该分支则此格红 |
| 锁 5 第三闸：被检文档自身脏 ⇒ 不许降级 | `advisories(["docs/ARCHITECTURE.md"]) == []` | ✅（变异删除 `dirty_docs_overlap` 则红）|
| （我加的）`--strict` 不降级 | `advisories(_d, strict=True) == []` | ✅ |
| （我加的）注入面只认 `*.mbt` | `dirty_mbt_files(porcelain_text=_fake)` | ✅ 用假 porcelain 夹具，**避免干净 CI 上假绿** |
| （本单新增）**实现路径格** | `advisory_verdict(_d).rc == 0` 等 4 条断言 | ✅ **判例-29 补强**，变异实测必红 |

**判例-30 防护**：全部锁**只断言 `advisories()` / `dirty_mbt_files()` 的返回值**，
**不断言源码里有某字符串** ⇒ 不会命中注释造成自指假绿。

### 2.2 四次真跑读数

| # | 场景 | 命令 | 结果 | rc |
|---|---|---|---|---|
| ① | 脏工作树 + 会红的数 | `--total 1463` | **23 条违例 → ADVISORY**，点名 6 个脏文件 | **0** |
| ② | `--strict` | `--total 1463 --strict` | **不降级，判红** | **1** |
| ③ | `CI=true` | `CI=true --total 1463` | **自动 strict，判红** | **1** |
| ④ | 正确数（文档已同步 1532）| `--total 1532` | **PASS** | **0** |
| ⑤ | `run_guards` 的确切 argv | `temp/pt27.log --fresh` | **ADVISORY 行 + rc=0** | **0** |

**⑤ 是「`run_guards` 无需改动」的直接证据**：其 `gated(expect=0)` 只看 rc，而此处 rc=0 ⇒ PASS。

场景① 原文（节选）：
```
  - R3 防空转：现状面里没有任何一条声明等于实测 1463（正则饿死或文档改写≠没有问题）

WARN 工作树有 6 个未提交/未跟踪的 *.mbt —— 本格不判红（BUG-425）
     why：读数面 = 工作树实测 1463；原文面 = 已提交态文档；两者不同源，
          此刻的红可能是「文档落后于在途工作」，不是「文档写错了数」。
     点名脏文件（前 20 条 / 共 6 条）：
       · src/core/core_task_retry_deliverable_wbtest.mbt
       · src/engine/engine_role_resolve_wbtest.mbt
       · src/engine/engine_scope_perm_order_wbtest.mbt
       · src/engine/engine_scope_perm_role_wbtest.mbt
       · src/engine/omega_orphan_wbtest.mbt
       · src/server/output_validate.mbt
ADVISORY 上述 23 条违例不判红（工作树脏）；确认要红请加 --strict
```

> **⚠️ 一个测量陷阱，如实记录**：我最初用 `cmd 2>&1 | tail -3; echo rc=$?` 取退出码，
> 得到的 `rc=0` 是 **`tail` 的退出码**，不是判据的 ⇒ 我一度误判「`--strict` 没生效」。
> 改为 `cmd > file 2>&1; echo $?` 直取后才得到正确读数（1/1/0）。
> **这是本仓「打印 ≠ 生效」家族的又一实例：管道末端的退出码不是被测进程的退出码。**

### 2.3 落地前后对比

| | 落地前 | 落地后 |
|---|---|---|
| 脏工作树上 `--total 1463`（文档写 1532） | **FAIL，rc=1** —— 23 条违例，**无法分辨**「文档落后于在途工作」与「文档写错了数」 | **ADVISORY + WARN + 点名 6 个脏文件，rc=0** |
| `--strict` | 不存在 | **rc=1，照常判红** |
| `CI=true` | 不存在 | **自动 strict，rc=1** |
| 被检文档自身脏 | 无此概念 | **不降级（真信号保留）** |

**这不是「放过了一个真问题」，而是「把不可判状态如实标注为不可判」。**
三条理由：
1. **真问题仍然会被抓**：CI 上工作树干净 ⇒ 不降级 ⇒ 漂移照红；
   `--strict` 也能随时强制。
2. **降级的那一类「红」本来就不是缺陷信号**：文档写 1532（已提交态）、
   实测 1463 是调用方**手输的旧数**——这恰恰证明了「读数面与原文面不同源」，
   而不是「文档写错了」。
3. **WARN 行点名了全部脏文件**，读者能自己判断该信哪个数 —— 这比一个笼统的红**信息量更大**。

---

## 三、分析

### 3.1 为什么这档与本仓既有约定一致

本仓「拒绝出数」的语义锚点是**一条**，不是两套退出码：

> **判据在自己无法给出可信结论时，必须如实标注，不许假装给了结论。**

| 判据 | 落成什么 | 为什么形态不同 |
|---|---|---|
| `check_fmt_gate.py` | `rc=2` DEGRADED | 只被 CI 消费，无电池 `expect` 约束 |
| `e2e_native_heap_probe.py` | `rc=3` 平台不给量 | 独立脚本，无电池约束 |
| **`check_test_sync.py`（本单）** | **`rc=0` + WARN 行** | **住在电池里**，`gated(expect=0)` 精确比对 |

**⇒ 关键区别不是「语义不同」，而是「消费者不同」**。
本单**零新增退出码**，`check_test_sync` 仍只有 0/1/2 三档。

### 3.2 为什么「降级」不会变成「永远绿」

| 闸 | 强度 | 弱点 |
|---|---|---|
| `--strict` | 强 | 靠人记得传 |
| **`CI=true` 自动 strict** | **最强** | 依赖 CI 设了 `CI=true`（GitHub Actions **默认注入**）|
| 被检文档自身脏 ⇒ 不降级 | 中 | 只覆盖「人改了文档」这一种真信号 |

**最硬的保证是 CI 那一闸**：CI 上工作树必然干净 ⇒ **永不降级** ⇒ 漂移在 CI 上仍会红。
**本地绿本来就不算数**（本仓口径：权威门 = CI）。

### 3.3 判例稿：「退出码不可跨管道传递」

**本单实测踩到的**（差点写出一条虚假缺陷）：

```bash
# 坏形状（我一开始就是这么写的）
$ cmd 2>&1 | tail -3; echo rc=$?
rc=0                     ← 这是 **tail** 的退出码，恒 0
                         ← 于是我一度判定「--strict 没生效」

# 正确形状
$ cmd > file 2>&1; rc=$?; echo rc=$rc
rc=1                     ← 这才是被测判据的退出码
```

**判例正文（建议入档）**：

> **判例：「退出码不可跨管道传递」**
>
> `cmd | tail` 的 `$?` 是 **`tail` 的**，不是 `cmd` 的。任何 `A | B` 形式的管道，
> 其 `$?` 报的是 **B** 的退出码。
>
> **实测代价**：一个**工作正常**的 `--strict` 被判成「没生效」；
> 若当时不是在专门核这件事，报告里就会写着「`--strict` 不工作」——**一个完全虚构的缺陷**。
>
> **与既有判例同族，但方向相反**：
>
> | 判例 | 机理 |
> |---|---|
> | 「打印 ≠ 生效」 | **有输出**但机制没生效 |
> | 「读数面 ≠ 原文面」（BUG-425） | **读了**但读错了面 |
> | **「退出码跨管道」（本条）** | **读到的退出码是另一个进程的** |
>
> **共同点：观测手段本身改变了观测对象。**
>
> **硬要求**：判据里凡要用退出码，必须 `cmd > file 2>&1; rc=$?` 直取，
> **不许经过任何管道 / 子 shell**。

**⚠️ 全仓扫描（统帅要求的清单）**：`grep` 本仓所有 `| …; echo rc=$?` / `| …; $?` 形状 ——
| 扫描面 | 结果 |
|---|---|
| `scripts/*.py` `*.sh` `*.ps1`：管道后取 `$?` | **0 处** |
| `.github/workflows/*.yml` 的 `$?` | **4 处，全部是 `cmd \|\| rc=$?`**（正确形状：无管道，且避开 GHA `bash -e`）|
| `scripts/commit_scoped.sh` 的 `$?`（9 处） | **全部紧跟子 shell `( … )` 或 `out=$(…)`**，无管道 ⇒ 正确 |
| `scripts/migrate_mooncakes_modjson.sh:74` | `rc=$?` 紧跟 `out="$(…)"` 赋值，无管道 ⇒ 正确 |

**⇒ 结论：本仓没有别的判据在用这个坏形状。** 这条坏形状只存在于我这轮的**命令行临时写法**里，
没有进任何脚本。**但不入判例的话，下一个人还会踩。**


---

## 四、缺口与风险

1. ~~缺一格「删除降级段 ⇒ 锁 2 必红」的显式变异~~ —— **已在本单补齐（锁 7）**。
   原在途实现用「锁 2 断言 `advisories(_d) == _d`」覆盖行为面，但那**只是纯函数格**：
   把 `run()` 里那段降级整段删掉，`advisories()` 的锁**照样全绿**（判例-29「机制格 ≠ 实现路径格」的原始形状）。
   **本单的修法**：把降级**判决**从 `run()` 内联代码抽成可测纯函数 `advisory_verdict(dirty, strict)`
   → 返回 `AdvisoryVerdict(warn_paths, rc)`，`run()` 只做 `return veto.rc`。
   新增**锁 7** 直接断言：
   ```python
   advisory_verdict(_d).rc          == 0    # 脏 ⇒ 必须降级
   advisory_verdict(_d).warn_paths  == _d   # 脏 ⇒ 必须点名
   advisory_verdict([]).rc          == 1    # 干净 ⇒ 违例照常红
   advisory_verdict(_d, strict=True).rc == 1  # 闸生效 ⇒ 照常红
   ```
   **变异实测（真做，不是设计）**：把 `return AdvisoryVerdict(list(adv), 0)` 改成 `, 1)`
   ⇒ `SELFTEST FAIL [bug425-dirty-must-degrade-rc0]`，**rc=1 必红**；恢复后 rc=0。
   **这就是统帅硬要求①的锁 3 变异对照，已真实生效。**
2. **`run_guards --fresh` 在脏树上该格恒绿**：本方案的**有意代价**（脏树的数不可信）。
   缓解：CI 闸。**本地跑电池时这一格不再有区分力**，需在 `scripts/README.md` 里写明。
3. **`--source=head`（方案 c）未实现**：需临时 worktree 真跑全量（~20 分钟）+ 并发风险。
   CI 闸已覆盖其主要价值，记为「已知未实现」。
4. **同文件多 lane 并发**：我读到的版本有 `SyntaxError`，1 分钟后被修好。
   **建议**：`check_test_sync.py` 这类热的守卫文件，落盘后应立刻跑一次 `--selftest`，
   别让半成品在树上过夜。
5. **`^test` 行数偏差 +1/0 不稳定**的根因仍未定位（Round 6 记的）。
   本方案**不依赖行计数**，故不影响正确性。

---

## 五、建议入档位置

| 内容 | 位置 |
|---|---|
| 本落地报告 | BUG-425 条目挂 `- landing: reports/2026-10-27-bug425-landing-report.md` |
| **「管道末端退出码不是被测进程退出码」** | 判例集（「打印 ≠ 生效」家族新实例，本单实测踩到 2 次）|
| **「纯函数格的变异对照 ≠ 实现路径格的变异对照」** | **判例-29 补强**：本单缺口 1 是它的又一个实例 |
| `run_guards --fresh` 该格恒绿 | `scripts/README.md` 的 check_test_sync 条目 + BUG-425 追记 |
| 热的守卫文件落盘后须立即 `--selftest` | AGENTS.md 提交纪律附近（或 `scripts/README.md`）|
