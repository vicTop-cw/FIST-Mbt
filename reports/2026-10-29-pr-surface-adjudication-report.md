# PR 面裁决报告 —— 104 支 gitcode 分支的逐支认定（2026-10-29）

> 本报告是**读数的正式归档**：以 `scripts/check_slave_mergeability.py`（**45 格自检**，
> 含内容包含探针 / 计数倒退 / 启动自愈 / 探针优先）在**全量 104 支**上跑出的结果为依据，
> 并对其中**判为 `conflict` 的 3 支**逐支做了人工复核。

## 一、方法（为什么这份读数可信）

| 判据档 | 含义 | 之前为什么判不出来 |
|---|---|---|
| `contained` `=` | 支的内容**已在 base** | 无共同祖先的支 cherry-pick **必冲突** ⇒ 旧尺全判 `conflict` |
| `superseded` `↓` | 支把某些**计数改小** ⇒ 合它=倒退 | 旧尺只比行数，看不出"数字变小" |
| `conflict` `✗` | 真冲突，需人工 | —— |
| `ok` `✓` | 可合 | —— |

**性能前提**：单支从 **78s → 1.4s**（探针优先 + 限量取样），否则 104 支要 2 小时、跑不完
⇒ 结论只能是残缺的。全量实测 **144s**。

## 二、全量读数（104 支）

| 分类 | 支数 |
|---|---|
| `contained`（内容已在 base） | **87** |
| `superseded`（合了会让计数倒退） | **14** |
| `conflict`（真冲突） | **3** |
| `ok`（可合） | **0** |

⚠️ **与 2026-10-24 的旧读数（contained 10 / conflict 93）差异巨大** —— 不是仓库变了，
是**尺子学会了分辨**：那 93 个"冲突"里 **87 个的内容早已在 base**。

## 三、3 支真冲突的逐支裁决

### ① `docs/fist-gate-degraded-analysis-r41` —— ✅ **已合入**（2026-10-29）

| 项 | 内容 |
|---|---|
| 改动 | 新增诊断报告 64 行 + 账本 3 行 |
| 冲突面 | 仅 `docs/tasks/diff-scope-claims.txt`（**append-only**） |
| 解法 | 报告取分支版本（master 无此文件）；账本**只 append 3 行**（union，不覆盖） |
| 验收 | `check_diff_scope` / `check_doc_paths` / `check_battery_count_doc` 全 rc=0 |

### ② `fix/list-tools-single-source-r39` —— ⛔ **判定 superseded，不合**

| 项 | 内容 |
|---|---|
| 支的意图 | `fist.py list-tools` 复用工具真源（它曾报 **152** 而真源 **170**，且是**文档点名**的入口） |
| master 现状 | `scripts/fist.py:cmd_list_tools()` **已**委托 `_tool_registry.real_tools()`；且已有**独立判据** `scripts/check_fist_list_tools_sync.py`（实测 **rc=0**） |
| 结论 | **同一意图已由更新的实现 + 独立判据覆盖**；合入会把 `fist.py` 换回旧形态 |
| 证据 | master `fist.py:250-282` 的 docstring 明写"2026-10-25 收口，判例-16 同族"；`check_fist_list_tools_sync.py` 存在且通过 |

### ③ `refactor/fist-gate-fmt-single-source-r42` —— 🔶 **有真价值，待实施（不在本报告内落地）**

| 项 | 内容 |
|---|---|
| 支的意图 | `fist-gate.py` 的格式面判定**收敛到 `check_fmt_gate.py`**（消除"同一套判定的两份实现"） |
| master 现状 | `fist-gate.py:60-74` **仍自带**一份 `DEGRADED fmt: ...` 三档划分 ⇒ **复制仍在** |
| 价值判断 | 本仓为"判据复制"返工过（tools 计数曾有 5 处复制）⇒ 该收敛**成立** |
| 为什么不直接合 | master 的 `fist-gate.py` 已演进（DEGRADED 文案、退出码契约），**直接取分支版本会覆盖新版逻辑**；须把"收敛意图"重新实施到当前文件上，并跑 `fist-gate.py` 自检 |
| 下一步 | 按"读 master 现状 → 委派真源 → 替换调用点 → 跑自检"四步做，**不合分支版本** |

#### ③ 实施尝试的结果（R173，**失败并撤回**，但拿到了关键证据）

按上表做了一次委派式收敛（`classify_fmt` 委托 `check_fmt_gate.run`），**2 格自检立刻红**
（`冷格式化器识别失败` / `未知退化未归 unknown`），已 `git checkout` 撤回。

**根因：两份实现不是"同一套判定的两份拷贝"，而是两个不同的判定。**

| 面 | `fist-gate.classify_fmt` | `check_fmt_gate.run` |
|---|---|---|
| 档数 | 4（clean / generation-mismatch / cold-formatter / unknown） | 3（clean / degraded / red） |
| 冷格式化器 marker | `failed to execute \`git --no-pager diff`、`/format/moon.mod`、`wasm-gc/release/format` | `No such file`、`cannot hash`、`failed when formatting project`（且要求输出含 `_build`） |
| `rc==1` | `generation-mismatch`（当"世代差"**软化**） | `red`（**真格式差异**） |
| 未知非 0 | `unknown` | `red` |

⇒ **收敛不是搬迁，是判定语义的取舍**：谁当冷格式化器的 marker？`rc=1` 该软化还是该判红？
这需要 **owner / 判据主人**裁定，不属于"合并一个分支"的机械动作。

**候选解法（按推荐度）**：
1. **以真源为唯一面，把 fist-gate 的 3 个 marker 并入真源**，并给真源补"冷格式化器"专格
   —— 会让真源的 `degraded` 判定面变宽（更保守），需复核依赖它 `red` 读数的调用方；
2. 保持两份，但**在两边 docstring 互相点名差异**（至少让下一个人不再以为它们等价）；
3. `check_fmt_gate.run(moon_rc, output, extra_markers=…)` 加可选参数，调用方各自补齐。

**⇒ 该支的结论修正为：不是"待实施"，而是"待裁定"** —— 实施前必须先决定 marker 与 `rc=1` 的语义。

## 四、结论

1. **可合 PR = 0**（全量 104 支）；本轮**已合 1 支**（纯文档，§3①）。
2. 87 支内容早已落地 —— **这不是"87 个未合并的 PR"，而是同一个问题被不同 agent 解决了多次**。
3. 14 支会**倒退计数**（合了会让用户看到更少的功能/更旧的数字）⇒ 明确不该合。
4. 剩 1 支（r42）是**真改进**，但必须以"重新实施"的方式落地，而不是合并旧分支。

## 五、来源与可复现

```bash
# 全量普查（约 144s）
python scripts/check_slave_mergeability.py --include gitcode/
# 判据自检（45 格，含变异对照）
python scripts/check_slave_mergeability.py --selftest
```

- 判据：`scripts/check_slave_mergeability.py`（45 格自检）
- 普查原始输出：`temp/census_full_r170.txt`（104 行，本地未跟踪）
- 关联账本：`docs/tasks/diff-scope-claims.txt`
