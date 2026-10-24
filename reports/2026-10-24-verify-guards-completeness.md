# `scripts/` 判据面完备性验证报告（B·verify · task-18）

- **日期**：2026-10-24
- **模式**：`verify`（`mode_list` 要求 `require_api_enum + require_doc_check`）
- **板块**：`scripts/` 判据面（**116 把尺**）的完备性
- **执行人**：司令-ε（本会话造判据最多的执行者 —— **本次审的是自己造的东西**）
- **纪律**：主仓作业、**不改判据代码**、只出矩阵

---

## 一、结论（先给判断）

| # | 结论 | 读数 |
|---|---|---|
| 1 | **T4 缺执行面 = 0** | 116 把全部有执行面（CI 或电池）✅ |
| 2 | **T3「只在本地跑过」= 0 把** | 30 把 `CI=- 电池=-` **全是非 `check_*`** 的 e2e/CLI/生成器/辅助库，已在 REGISTRY 带理由登记 ✅ |
| 3 | **64 把 `check_*` 全部有 `--selftest`** | 100% 覆盖 |
| 4 | **60/64 selftest 绿；3 把真非绿 + 1 把口径误判** | 见 §4 |
| 5 | **变异抽查 29 把（唯一判据）→ 1 把假绿**（3.4%） | `check_git_sandbox_hygiene.offenders` |
| 6 | **三端自述数字 vs 实测数字：逐键一致** | `116/45/76/0/84/27/7` ✅ |

**总评**：判据面整体健康。**唯一实锤的假绿是 `check_git_sandbox_hygiene`** —— 而这把尺
恰恰是本会话用来**防别的尺忘隔离环境**的那把，属于「守卫自己的守卫失守」，优先级应高于普通债。

---

## 二、T1–T4 四张表（全量枚举）

数据源：`python scripts/run_guards.py --list`（116 条），逐条正则解析。

### T1 电池面 —— **76 把**在电池里真跑

### T2 CI 面 —— **45 把**进了 `.github/workflows`

| 交集面 | 把数 | 说明 |
|---|---|---|
| **CI ∩ 电池** | **35** | 双面覆盖，最强 |
| **仅 CI**（电池没盖） | **10** | 由 CI 独占保护，本地不跑 |
| **仅电池**（CI 没盖） | **41** | 本地/提交前面，CI 不管 —— 这是**主力面** |
| **两者皆无** | **0** | ✅ 无死角 |

### T3 只本地跑过（`CI=-` 且 `电池=-`）—— **30 把，但 `check_*` 里 0 把**

> **关键区分**：任务书预期这里藏着「存在于仓里但从不被执行」的尺（判例-5 同族）。
> 实测 **0 把判据**落在这个格子里。30 把全部是非判据脚本：

| 类别 | 把数 | 例 | 为什么不算漏检 |
|---|---|---|---|
| e2e 探针 | 6 | `e2e_mirror_install` / `e2e_guard_mutation` | 需宿主进程/网络/POSIX，REGISTRY 带理由 |
| CLI / 工具入口 | 4 | `fist.py` / `fist-pr-automator.py` | 是给人用的入口，不是判据 |
| 生成器 / 安装器 | 5 | `gen_plugins` 系 / `install_git_hooks` | 被其它判据子进程调用 |
| 实验 / 一次性 / 演示 | 13 | `caf_*` / `*_demo` / `score_gate` | 非门禁族 |
| 辅助库 | 2 | `git_env.py` | 单一真源库，由 8 个接线脚本的 selftest 覆盖 |

### T4 缺执行面 —— **0** ✅（`run_guards --list` 直接给 `missing=0`）

---

## 三、假绿排查（核心）

### 3.1 方法（**这一节本身就是交付物**）

不能靠「读代码觉得它应该能红」，必须**让它真红一次**。做法：

1. 把判据**复制到临时目录**（不碰真仓）；
2. 定位它的**判定核心函数**（名字含 `judge`/`classify`/`compare`/`scan`/`is_*` 且返回布尔或元组的那个）；
3. 在函数体首行插入 `return <通过值>`（把判据**变成恒通过**）；
4. 跑 `--selftest`：
   - **变红** ⇒ 该判据的 selftest 覆盖了核心 = **能咬**；
   - **仍绿** ⇒ selftest 从没走到那段逻辑 = **假绿嫌疑**。

> **这个方法的要义**：它不问「判据写得对不对」，只问「**判据坏了，自证知不知道**」。
> 后者才是 selftest 的唯一职责。

### 3.2 抽查结果：29 把（30 次变异） → **1 把假绿**

| 判据 | 变异函数 | 结果 |
|---|---|---|
| `check_index_gitlinks` | `parse_staged_gitlinks` | 能咬 ✅ |
| `check_worktree_hygiene` | `judge` | 能咬 ✅ |
| `check_esm_bundle_runnable` | `classify_run` | 能咬 ✅ |
| `check_esm_bundle_runnable` | `shim_present` | 能咬 ✅ |
| `check_master_mirror` | `classify` | 能咬 ✅ |
| `check_repo_shape` | `judge` | 能咬 ✅ |
| `check_repo_hygiene` | `is_fixture_identity` | 能咬 ✅ |
| `check_selftest_call_face` | `judge_one` | 能咬 ✅ |
| `check_battery_count_doc` | `compare` | 能咬 ✅ |
| `check_backlog_status_staleness` | `judge` | 能咬 ✅ |
| `check_battery_isolation` | `detect` | 能咬 ✅ |
| `check_branch_ancestry` | `classify` | 能咬 ✅ |
| `check_bug_refs` | `classify` | 能咬 ✅ |
| `check_commit_bug_refs` | `is_red` | 能咬 ✅ |
| `check_delivery_gap` | `classify_divergence` | 能咬 ✅ |
| `check_demo_isolation` | `judge` | 能咬 ✅ |
| `check_deprecated_text_census` | `judge_hits` | 能咬 ✅ |
| `check_dist_snapshot` | `judge` | 能咬 ✅ |
| `check_entry_paths` | `judge` | 能咬 ✅ |
| `check_fmt_gate` | `classify` | 能咬 ✅ |
| `check_mbti_sync` | `judge` | 能咬 ✅ |
| `check_memory_log_size` | `judge` | 能咬 ✅ |
| `check_pkg_imports` | `judge` | 能咬 ✅ |
| `check_release_asset_names` | `judge` | 能咬 ✅ |
| `check_scripts_naming` | `judge` | 能咬 ✅ |
| `check_selftest_inventory_doc` | `judge` | 能咬 ✅ |
| `check_test_sync` | `judge` | 能咬 ✅ |
| `check_ci_step_position` | `is_gate` | 能咬 ✅ |
| `check_scripts_index` | `is_registered` | 能咬 ✅ |
| **`check_git_sandbox_hygiene`** | **`offenders`** | **假绿嫌疑 ❌** |

### 3.3 实锤假绿：`check_git_sandbox_hygiene.offenders`

**证据**：把 `offenders()` 改成恒返回通过，`--selftest` **仍然绿灯**。

**根因**（读源码确认，非推测）：
```
scripts/check_git_sandbox_hygiene.py:
  # selftest() 里出现的调用：
  analyze_source(...)   ← T1/T2/T3/T4 四格全测的是它
  offenders(...)        ← 只出现在第 221 行的 main() 里，selftest 从不调用
```
⇒ `selftest` 覆盖的是**检测器**（`analyze_source`，逐文件判是否缺 `env=`），
而**聚合器 + 棘轮判定**（`offenders` 里的 `n > DIRTY_CEILING` 分支与「棘轮登记落后」分支）
从来不在自证面内。

**危害放大**：这把尺是**防别的尺忘隔离 `GIT_DIR`** 的（本会话 R46 造）。
它失守时，**其它判据的夹具可能污染真仓而无人察觉**——属「守卫的守卫」层级。

**修法建议**（不在本单执行，交派修）：
- selftest 增加两格：① 造一个缺 `env=` 的合成仓库 ⇒ `offenders()` 必须返回非空；
  ② 把 `DIRTY_CEILING` 临时设为小于现读数 ⇒ 必须进 `FAIL ... 超棘轮` 分支。
- 判例对应：**「自证必须覆盖聚合层与棘轮层，不能只覆盖检测器」**。

---

## 四、4 把非绿 selftest 的定性

| 判据 | rc | 实际性质 | 判定 |
|---|---|---|---|
| `check_commit_bug_refs` | 0 | **实为 PASS**，输出用 `selftest PASS（7 格…）` 而非 `SELFTEST OK` —— **我的自动口径误判** | ✅ 绿 |
| `check_ci_step_position` | 2 | 自检格 **T9「真源现状 rc=1」** 失败：F1 缺锚点违例 **35 > 上限 34** | ⚠️ 存量债 |
| `check_exit_code_contract` | 2 | 自检格 **`ceiling-matches-live-reading`**：现算判定面 5 条 vs 上限常量 0 | ⚠️ 存量债 |
| `check_scripts_naming` | 2 | 自检格 **`real-ceiling-matches-measured`**：实测 N1 份数 > 钉住上限 | ⚠️ 存量债 |

### 这 3 把是**同一个族**，且**不是 bug，是纪律**

三者都有一条「**真源现状必须符合钉住的上限**」的自检格。它们红的原因是
**棘轮常量与实测面脱节**（有人加了 `check_*` 脚本，N1/ceiling 就涨了，但没人同批改常量）。

**定性**：这不是判据坏了 —— 恰恰是**判据在正确地报告「债累积了」**。
按本仓律「升档是人的决定」，常量不能自动改 ⇒ 自检格**必然红**，直到人裁决。

**建议**：这三格应登记为 `kind="known-red"` 并在 `run_guards.py` 里写明理由（部分已如此登记），
避免每轮有人误以为「判据坏了」而去改常量。

---

## 五、判据健康度矩阵（`check_*` 全 64 把）

图例：**能咬** = 变异测试证实 selftest 覆盖核心；`—` = 未抽查（本轮抽样 30/64）。

### 5.1 汇总

| 维度 | 读数 |
|---|---|
| `check_*` 总数 | **64** |
| 有 `--selftest` | **64**（100%） |
| selftest 绿 | **60**（93.8%） |
| selftest 真非绿 | **3**（全是棘轮存量债，非缺陷） |
| 在电池 | **64**（100%） |
| 在 CI | **32**（50%） |
| CI ∩ 电池 | **32** |
| 两者皆无（死角） | **0** |
| 变异抽查（唯一判据） | **29** |
| 抽查中假绿 | **1**（3.4%） |

### 5.2 本会话新增的 6 把（重点自审）

| 判据 | 有 selftest | 真能红 | 在电池 | 在 CI | 判定 |
|---|---|---|---|---|---|
| `check_index_gitlinks` | ✅ 20 格 | ✅ 能咬 | ✅ | ✅ | **健康** |
| `check_master_mirror` | ✅ 26 格 | ✅ 能咬 | ✅ | — | **健康**（未接 CI 有据：CI 无写权限） |
| `check_esm_bundle_runnable` | ✅ 17 格 | ✅ 能咬（2 函数各验） | ✅ | — | **健康**（真产物档需 build，未接 CI） |
| `check_worktree_hygiene` | ✅ 43 格 | ✅ 能咬 | ✅ | — | **健康**（诊断尺，tolerant 0/1） |
| `check_git_sandbox_hygiene` | ✅ | **❌ 假绿** | ✅ | ✅ | **失守**（见 §3.3） |
| `check_commit_bug_refs` | ✅ 7 格 | ✅ 能咬 | ✅ | ✅ | **健康** |

> **自审结论**：我造的 6 把里，**5 把健康、1 把假绿**。假绿的那把不是我这轮写的逻辑，
> 但它是**本会话 R46 的产物**，同样算我的账。

### 5.3 全 64 把矩阵

见附录 A（机器生成，逐行：判据 / selftest / 绿否 / 电池 / CI）。

---

## 六、三端枚举对表（verify 的 `api_enum` 面）

| 判据 | 自述 | 实测 | 一致 |
|---|---|---|---|
| `check_tools_sync` | 170 工具 | 170（server.mbt）/ 扫现状面 174 份 | ✅ PASS |
| `check_plugin_sync` | 4 宿主 / 64 文件 / 170 工具 / v0.3.10 | 同左 | ✅ PASS |
| `check_doc_surface` | J1–J17 全套 | 全 PASS（含 J9/J10/J11/J12/J13/J14/J15/J17） | ✅ PASS |
| 电池锚点 | `rulers=116 ci=45 battery=76 missing=0 gate=84 exempt=27 unclassified=7` | 逐键相同 | ✅ PASS |
| README 徽章测试数 | `tests-1455/1455` | 本轮未跑全量 `moon test`（见缺口） | ⚠️ 未核 |

> **诚实标注**：测试数一项本轮**没有实测**（全量 `moon test` 耗时且与本审查无关），
> 只核了「徽章 ↔ README 正文 ↔ 电池锚点」的内部一致性。**不自称核对过**。

---

## 七、缺口与风险

1. **假绿只查出 1 把，但抽样只覆盖 30/64（46.9%）**。
   未抽查的 35 把**不能宣布健康** —— 只能说「本轮抽到的都能咬」。
   **建议**：把变异测试做成常驻判据（`check_mutation_immunity.py`），全量跑，进 CI 观测臂。
2. **3 把棘轮债**需 owner 裁决：是升常量，还是真正还债（降实测面）。
3. **`check_git_sandbox_hygiene` 失守期间**，其它判据夹具的 `GIT_DIR` 隔离**没有可靠守卫**。
   建议优先派修（工作量小：加 2 格 selftest）。
4. **32 把仅在电池、未进 CI**：本地能跑，但 clone 后不装 hooks 的人/CI 不覆盖。
   是否扩 CI 面属权限与成本决策。
5. **本报告未跑 `moon test`**，代码健康面不在 verify 范围（归 `check_test_sync` / CI）。

---

## 八、建议动作（交统帅派工，本单不执行）

| 优先级 | 动作 | 预估 |
|---|---|---|
| **P0** | 修 `check_git_sandbox_hygiene` selftest 覆盖 `offenders` + 棘轮两分支 | 小（+2 格） |
| **P1** | 3 把棘轮债裁决（升常量 or 还债） | 中（需 owner） |
| **P2** | 把变异测试落成常驻判据，全量 64 把 | 中 |
| **P3** | 评估 32 把「仅电池」是否值得扩 CI 面 | 大（成本） |

---

## 附录 A：`check_*` 64 把完整矩阵

完整数据见 **`reports/verify-guards-matrix.csv`**（64 行，列：判据 / 有selftest / 真能红 / 在电池 / 在CI / 判定）。

判定分布（机器统计）：

| 判定 | 把数 |
|---|---|
| 健康（有 selftest、selftest 绿、抽查能咬或双面覆盖） | 25 |
| 未抽查（selftest 绿，但本轮未做变异） | 34 |
| 棘轮债（selftest 真非绿，性质为存量债） | 4 |
| 失守（假绿） | 1 |
| **合计** | **64** |

> ⚠️ 「未抽查」34 把**不等于健康** —— 本轮只对其余 29 把做了变异证明。
> 见 §七 缺口 1。

## 附录 B：本审查的可复现命令

```bash
# ① 全量枚举
python scripts/run_guards.py --list

# ② 四张表
python scripts/run_guards.py --list | grep -E 'CI=-.*电池=-'   # T3

# ③ 全量 selftest
for f in scripts/check_*.py; do python "$f" --selftest; done

# ④ 变异抽查（临时脚本，未入库）
python scripts/tmp_verify_mutation.py
```

> `scripts/tmp_verify_mutation.py` 是本次审查的临时工具，**不入库**（复查后删除）。

## 来源

| 项 | 来源 |
|---|---|
| 任务书 | task-18（统帅派工） |
| 判据清单 | `scripts/run_guards.py --list`（116 条，2026-10-24 实读） |
| 假绿方法 | 本会话教训：对照格造不出差异、`judge()` 参数顺序颠倒、`--not` 语义错 |
| 参考实例 | `check_mbti_eol.py`（R43 只盯 3 份 `.mbti`）、判例-3（改名绕过） |
