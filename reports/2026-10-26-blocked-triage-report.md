# 阻塞任务审计报告（Lane B）· 2026-10-26

> **任务**：`grade=attention` 主因「85 个 blocked 任务」的逐条分类与处置方案
> **执行人**：司令-γ（Lane B 审计队）· **执行方式**：只读任务库 + 写报告，**未动任何源码**
> **产出**：本报告 + `temp/audit/lane_b_*.{py,json}`（辅助脚本与中间数据）

---

## 结论（先给数）

| 类 | 含义 | 条数 |
|---|---|---|
| **A 真阻塞** | 有明确失败原因、需要人裁决 | **1** |
| **B 僵尸** | 父已归档 / 从未动过 / 指向不存在的目录 | **0**（按判据；但有 6 条「父已归档」见下） |
| **C 外来项目** | 不属于 FIST-Mbt 本项目 | **83** |
| **D 可自动清理** | 无交付物 + 无依赖 + 长期停滞 | **1** |
| **合计** | | **85** |

**⚠️ 最重要的发现：85 条里 83 条（97.6%）不是 FIST-Mbt 的任务。**
它们全部 `status=已暂停` / `cleanup_mode=deferred`，落在 `fist-mbt.db` 的 `default` 库里，
但 `project_dir` 指向 **vools / 兹(lang-zone) / light-isolation** 等项目。

**⇒ `grade=attention` 的主因不是「本项目有 85 个阻塞任务」，而是「本项目的库里存着别的项目的 85 条历史」。**
这是一个**数据边界问题**，不是工作量问题。

---

## 证据

### 0. 扫描面自证（判例-41：先报读了哪些库，再看内容）

```
$ python temp/audit/lane_b_scan.py
=== 扫描面 ===
  （148 个 .db 被扫）  ---- 合计：库 148 个，blocked 94 条 ----

=== blocked 按库分布 ===
  fist-mbt.db                                    85      ← 本单目标
  .fist-mbt/data/vools-ext.db                     5
  omega_auto_lesson.db                            1
  tc_r109_t9.db                                   1
  watchdog_a4b.db                                 1
  watchdog_b3.db                                  1

=== blocked 按状态 ===
  已暂停        94        ← 全部是「已暂停」
  （已打回 0 条）
```

**⚠️ 与派单口径的差异**：任务是「`已暂停` + `已打回`」，实测 **`已打回` 全库 0 条**。
85 条**全部**是 `已暂停`。这不是漏扫——`SELECT ... WHERE status IN ('已暂停','已打回')` 的返回就是这个。

### 1. 批量暂停痕迹（决定「僵尸」判据）

```
=== updated_at 精确分布 ===
  2026-10-21T02:11:41    10
  2026-10-21T02:11:43    10
  2026-10-21T02:11:45    10
  2026-10-22T07:38:14    10
  2026-10-22T13:17:11    10
  2026-10-21T02:11:44     9
  2026-10-22T13:17:10     9
  2026-10-22T13:17:12     8
```

**⇒ `updated_at` 集中在 3 个时刻（各 10 条/秒的批处理）⇒ 这批是「批量暂停动作」产生的，
不是「逐个任务执行失败」产生的。** 这是 C 类判断的关键旁证。

### 2. 结构面统计

```
有交付物: 4 / 85      ← 95% 无交付物
有依赖  : 7 / 85
有父任务: 10 / 85     ← 87% 是根任务
子树规模: 有后代 4 条 / 无后代 81 条
```

### 3. C 类外来项目（83 条）· 细分与逐条点名

#### C1 · `ns` 是外来命名空间（10 条）

| # | id | ns | project_dir | 描述（截断） |
|---|---|---|---|---|
| 1 | `T0r636.1.2` | `fist-opt-20261016` | `.` | fist-mbt 全程打磨推进（组合模式）… |
| 2 | `T0r636.2.2` | `fist-opt-20261016` | `.` | 同上 |
| 3 | `T0r636.3.2` | `fist-opt-20261016` | `.` | 同上 |
| 4 | `T0r652` | `tnr-polish` | `.` | S6-0 协调：与并行 agent 的 src/codegen/* WIP 收敛对齐 |
| 5 | `T0r662.1.2` | `light-isolation` | `E:/IDEProjects/AI/FIST-Mbt-light-isolation`（**不存在**） | P0-2·补 e2e_assistant_xproc.py |
| 6 | `T0r662.1.3` | `light-isolation` | 同上（**不存在**） | P0-3·claimguard 接入决策与落地 |
| 7 | `T0r662.2` | `light-isolation` | 同上（**不存在**） | P1·light worktree 工具链落仓 |
| 8 | `T0r566` | `zn` | `E:\IDEProjects\AI\兹`（存在） | R309 推进：修复 兹 语言项目 bug |
| 9 | `T0r582` | `zn` | `E:\IDEProjects\AI\兹`（存在） | R317 推进：同上 |
| 10 | `T0r677` | `lz-r14` | `_proj_lang-zone` | 修复 bug: 柯里化闭包… |

**⚠️ C1 里 `T0r636.*` 三条值得单独说**：它们 `ns=fist-opt-20261016`、`project_dir=.`，
描述是「fist-mbt 全程打磨推进」——**看起来像本项目的任务，但 ns 是某次一次性优化的临时命名空间**，
且**父任务已归档**（见 §3.4）。**属于「本项目的历史残片」而非「别项目的任务」，但同样不应留在默认库的 backlog 里。**

#### C2 · `project_dir` 指向 vools 项目（73 条）

**全部是 `修复 bug: <vools 的模块/文件>` 形状**。逐条点名见 `temp/audit/lane_b_lists.txt` 的 C2 段
（73 行，逐条 id + ns + project_dir + 描述）。

代表性样本（前 16 条）：
```
T0r45.1   ns=default  pd=E:\IDEProjects\AI\vools   阶段0+1：规范定稿(kind矩阵/后缀矩阵/…)
T0r45.2   ns=default  pd=E:\IDEProjects\AI\vools   阶段2+3：任意语言入口(runner路由放开…)
T0r45.3   ns=default  pd=E:\IDEProjects\AI\vools   阶段4：索引扩展(name/kind/md5/languages…)
T0r45.4   ns=default  pd=E:\IDEProjects\AI\vools   阶段5：存量修复与回归…
T0r589    ns=bugs     pd=_proj_vools               修复 bug: VBJsonBackend.parse 对畸形字面量…
T0r591    ns=bugs     pd=_proj_vools               修复 bug: CallableHandler 中悬空的 @abstractmethod…
T0r592    ns=bugs     pd=_proj_vools               修复 bug: EnvCommands.nim() 硬导入可选子包…
T0r593    ns=bugs     pd=_proj_vools               修复 bug: VList.islice 在 step=0 且 start>stop…
T0r602    ns=bugs     pd=_proj_vools               修复 bug: VDate.simplify_date_ranges 对无效日期…
T0r603    ns=bugs     pd=_proj_vools               修复 bug: SharedBridge.write 负 offset…
T0r605    ns=bugs     pd=_proj_vools               修复 bug: ChannelBridge.send/send_pickle…
T0r606    ns=bugs     pd=_proj_vools               修复 bug: [rule:syntax] bridges/vools/bridge/md…
T0r609    ns=bugs     pd=_proj_vools               修复 bug: tests/test_utils_tools.py test_shift…
T0r611    ns=bugs     pd=_proj_vools               修复 bug: vools/sys/dll.py fallback 路径…
T0r619    ns=bugs     pd=_proj_vools               修复 bug: vools/sys/__init__.py L41 `from .dll import dll`…
T0r628    ns=bugs     pd=_proj_vools               修复 bug: vools/sys/dll.py 同步 @dll 装饰 async…
```

**其中 `pd=_proj_vools` 是 69 条，且该目录 `_proj_vools` 在本仓**不存在**（判例-49 的 symlink 假 0 已排除：
`os.path.isdir` 判为 False）。**

### 4. B 类候选：父已归档（6 条，派单判据下的 B）

```
T0r636.1.2   父=T0r636.1   父状态=已归档
T0r636.2.2   父=T0r636.2   父状态=已归档
T0r636.3.2   父=T0r636.3   父状态=已归档
T0r662.1.2   父=T0r662.1   父状态=已归档
T0r662.1.3   父=T0r662.1   父状态=已归档
T0r662.2     父=T0r662     父状态=已归档
```

**这 6 条同时也在 C1 里**（外来 ns）。按「父已归档 ⇒ 僵尸」的判据它们是 B，
按「外来项目」判据它们是 C。**我按 C 归档，但把 B 的证据单独列出**——处置上它们是**最无争议可清理**的一批。

### 5. A 类真阻塞（1 条）与 D 类（1 条）

#### A · `T0r588` — 本仓真缺陷，**问题仍在**

```
id=T0r588  ns=bugs  project_dir=.  status=已暂停  cleanup_mode=deferred
created=2026-10-19T01:51:59Z  updated=2026-10-21T02:11:42Z
assignee=atomcode-3  deliverable=(空)  depends_on=[]
description: 修复 bug: ocr_scan 的 OCR LLM review 对 MoonBit .mbt 恒不可达
             （unsupported_ext 全拦），bugfind 的 require_ocr 门是伪能力/可静默满足
```

**核验**：`src/server/ocr_scan.mbt:315-340` 现在有 `ocr_fake_green_check`（BUG-165），
但描述所指的**「`.mbt` 恒不可达 ⇒ require_ocr 门可静默满足」**这条是否已解决，
需**人裁**：判据里写的是「假绿检测」，而原单要的是「让 .mbt 可达」——**两者不同**。

**⇒ 这是唯一一条「本项目 + 有明确缺陷 + 需人判」的真阻塞。**

#### D · `T0r672` — **问题已消失**，可清理

```
id=T0r672  ns=bugs  project_dir=.  description: HEAD src/server/debate_tools_wbtest.mbt
           的 @(expr) 语法被 pinned moon 0.1.20261016 判 lexing error ⇒ src/server 测试包整体编译失败
```

**核验（判例-10：判 rc 不判输出）**：
```
$ grep -c '@(' src/server/debate_tools_wbtest.mbt
0                        ← 0 处
$ grep -rn '@(' src/server/*.mbt
（无输出）
```
**⇒ `@(expr)` 语法已从 `src/server` 全域消失，该任务描述的现象已不存在。**
无交付物、无依赖、无后代、`cleanup_mode=deferred` ⇒ **D 类可清理。**

---

## 分析

### 1. `grade=attention` 的根因是「库的物理边界」而不是「任务工作量大」

85 条全部落在 **`fist-mbt.db`（本项目的默认库）**，但 83 条的 `project_dir` 指向别的项目：

| project_dir | 条数 | 是否本仓 |
|---|---|---|
| `_proj_vools` | 69 | **不存在** |
| `.` | 6 | 本仓（但 ns 是 `fist-opt-*` / `light-isolation`，父已归档） |
| `E:\IDEProjects\AI\vools` | 4 | 外部项目（存在） |
| `E:/IDEProjects/AI/FIST-Mbt-light-isolation` | 3 | **不存在** |
| `E:\IDEProjects\AI\兹` | 2 | 外部项目（存在） |
| `_proj_lang-zone` | 1 | 存在（symlink 目标见判例-49） |

**⇒ 这是 BUG-78 的同族**（`store_open` 的 `data_dir` 隔离失效 / 多项目共用默认库）。
**根治办法不是「清理 85 条」，而是「让外来项目的任务落进各自的库」。**

### 2. 为什么「批量暂停」是重要证据

`updated_at` 集中在 3 个时刻（每时刻 ~10 条/秒）⇒ 这批是**一次性批量 `pause`** 的产物。
**批量暂停 + `cleanup_mode=deferred` 全部一致** ⇒ 说明当时有人（或某个脚本）主动把它们标记为「暂缓处理」，
而不是「执行失败后被系统打回」。

**⇒ 这 85 条从来就不是「活跃 backlog 的一部分」，它们是被显式归档掉的。**

### 3. `已打回` 0 条

派单说「`已暂停` + `已打回`」，实测**全库 `已打回` = 0**。
**这不是漏扫**：148 个库全扫，`WHERE status IN ('已暂停','已打回')` 只返回 94 条已暂停。
⇒ **本项目从来没有「打回」态的任务积压**，健康卡的 `blocked` 计数完全由 `已暂停` 贡献。

---

## 缺口与风险

| # | 缺口/风险 | 影响 |
|---|---|---|
| **1** | **`_proj_vools` 目录不存在**（69 条指向它） | 若真去「恢复」这些任务，`project_dir` 是死路径 ⇒ 全部会立刻再阻塞一次 |
| **2** | **`E:/IDEProjects/AI/FIST-Mbt-light-isolation` 不存在**（3 条） | 同上 |
| **3** | **`已打回` 口径 0 条**，与派单前提不符 | 派单说「85 条 = 已暂停 + 已打回」，实测 85 条**全部**是已暂停。**建议修正健康卡口径** |
| **4** | **`reserve_scope` fail-closed（BUG-413）** | 本轮我按领导指示**未使用** `reserve_scope`；但该缺陷让「explore 并行门」不可用，属机制缺陷 |
| **5** | 我**没有逐条判断 vools 的 bug 是否仍有效** | 73 条 vools 任务指的外部代码我不读（边界外），**只判了「它们不属于本项目」**，未判「它们该不该修」 |
| **6** | **`fist-opt-20261016` 三条（`T0r636.*`）性质模糊** | 描述是本项目内容、`project_dir=.`，但 ns 是临时优化空间且父已归档 ⇒ 「本项目的历史残片」，处置需人定 |
| **7** | 未验证 `T0r588` 的「`.mbt` 不可达」是否仍成立 | 只确认了 `ocr_scan.mbt` 有假绿检测函数，**没跑 ocr 二进制验 `.mbt` 是否真被排除**（本机 OCR 二进制依赖，未跑） |

---

## 建议入档位置

### 报告本身
- **本文件**：`reports/2026-10-26-blocked-triage-report.md`（新建）
- **辅助脚本与中间数据**：`temp/audit/lane_b_scan.py` / `lane_b_shape.py` / `lane_b_final.py`
  + `lane_b_blocked.json` / `lane_b_shape.json` / `lane_b_classified.json` / `lane_b_lists.txt`

### 建议统帅批准的清理动作（**我不执行，只出方案**）

| # | 动作 | 范围 | 风险 | 依据 |
|---|---|---|---|---|
| **1** | **`archive` 6 条 B 类**：`T0r636.1.2` / `T0r636.2.2` / `T0r636.3.2` / `T0r662.1.2` / `T0r662.1.3` / `T0r662.2` | 父均已归档 + ns 外来 | **极低**（父已归档是硬证据） | §3.4 |
| **2** | **`archive` 1 条 D 类**：`T0r672` | 单条 | **极低**（`@(` 已从 `src/server` 全域消失，描述现象不存在） | §3.5 |
| **3** | **`pause` → `archive` 73 条 C2（vools）** | 全部 `project_dir` 指向 vools | **低**，但**应先确认 vools 项目是否还在维护**；若在维护，这些任务应迁到 vools 自己的库 | §3.3 |
| **4** | **`archive` 3 条 C4**（`light-isolation`，目录不存在） | `T0r662.*` 已在 #1 里 | **极低** | §3.3 |
| **5** | **`T0r588` 转人工裁决**（A 类唯一真阻塞） | 单条 | — | §3.5 |
| **6** | **（根治项，非本单）** 让外来项目的任务落进各自的库（BUG-78 同族） | 机制 | — | §分析 1 |

**⚠️ 我不建议直接 `delete`**：`archive` 是**可逆**的（`reopen_task` 可回），`delete` 不可逆。
**85 条全部建议走 `archive`，不删。**

### 给下一单的两条线索
1. **健康卡应区分「本项目 blocked」与「库内外来 blocked」** —— 否则 `fist-mbt.db` 永远显示 `attention`。
2. **`已打回` 恒 0** 值得单独查：是「打回后立即被处理」还是「`reject` 从未被真实使用」。
