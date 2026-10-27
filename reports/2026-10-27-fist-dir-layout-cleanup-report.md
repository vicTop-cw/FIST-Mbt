# `fist-dir-layout-governance` 清理落地报告（1/6 → 6/6）

> **提案**：`docs/plans/2026-10-22-fist-dir-layout-governance-proposal.md` §3.1
> **定案**：DEC-2026-10-22-001（approved）
> **执行人**：司令-γ（接力 Alpha R19）· **日期**：2026-10-27

---

## 结论

| 项 | 结果 |
|---|---|
| **创建了几个目录** | **6 个**（`pool` / `state` / `logs` / `tmp` / `cache` / `lock`）+ `README.md` ⇒ **提案 §3.1 的 8 项全部到位** |
| **清理了多少文件** | **119 个**（84 个 `*.db` + 35 个 `temp_*/build*.log`）—— **归档不是删除** |
| **根目录 `*.db` 变化** | **85 → 1** |
| **根目录 `temp_*/build*.log` 变化** | **35 → 0** |
| **核心动机实现了吗** | **部分实现** —— 见 §分析，**「不进主仓」目标原本就已达成** |
| **回归验证** | ✅ 主库 `tasks=2450` 不变；`status_summary` 用显式路径读到 2450 |

---

## 证据

### §1 清理前后对比

| | 清理前 | 清理后 |
|---|---|---|
| `.fist-mbt/` 子目录 | **2**（`data` / `db`） | **8**（`data` / `db` / `pool` / `state` / `logs` / `tmp` / `cache` / `lock`）+ `README.md` |
| 根目录 `*.db` | **85** | **1**（只剩 `fist-mbt.db`） |
| 根目录 `temp_*` / `build*.log` | **35** | **0** |

### §2 分类清单（**每一类的理由**）

#### ✅ 可安全「移动」（不是删除）—— 共 119 个

**A 类：84 个非主库 `*.db` → `.fist-mbt/tmp/db-archive/`**

实测（逐个打开 `SELECT count(*) FROM tasks`）：

| 子类 | 数量 | 代表 | 判定 |
|---|---|---|---|
| **测试产物（有数据）** | 54 | `watchdog_*.db`(26) / `tc_r109_t*.db`(10) / `omega_*.db`(2) / `saga_r9*.db`(7) / `wal-*.db`(3) / `alpha.db` / `beta.db` / `gs-*.db` | tasks=1~11 条，**全是测试夹具造的数据** |
| **空库** | 31 | `cb_b34_t*.db` / `cb_r104_t*.db` / `bugs.db` / `smoke_*.db` | `tasks` 表存在但 0 行 |

**⇒ 全部 `git ls-files` = 0（未被跟踪），`du` 显示每个 148K（同尺寸 = schema 相同）。**

**B 类：35 个 `temp_*` / `build*.log` → `.fist-mbt/tmp/logs-archive/`**

```
temp_both.txt temp_bug263.txt temp_bug358.txt temp_bug374_78.txt temp_bug377.txt
temp_build_errors.txt temp_cg2.txt ... build.log
```
**⇒ `.gitignore:51` 已覆盖 `/temp_*.txt`；`git ls-files` = 0。**

#### ❌ **必须保留** —— 1 个

| 文件 | 理由 |
|---|---|
| **`fist-mbt.db`（16MB, tasks=2450）** | **活跃主库**。实测最后更新 `2026-10-27T06:46:53Z`（今天）；`store_open` / server 缺省都指向它 |

#### ⚠️ 未动（不在本单边界内）

| 项 | 状态 |
|---|---|
| `.fist-mbt/db/fist-mbt.db`（14.3M, tasks=2278） | **不在提案 §3.1 设计中**（提案只有 `data/`），是 **2026-10-22 的旧副本**（最后更新 `2026-10-22T20:12:20Z`）。**未动 —— 它不属于根目录污染** |
| `_build/` `_scratch/` `__pycache__/` 等 6 个杂目录 | 已被 `.gitignore` 覆盖（`.gitignore:86/222/223`），**未动** |
| `fist-mbt-rank.db`（在 `.fist-mbt/db/` 内） | 同上，不在根目录 |

### §3 回归验证（清理没有破坏任何东西）

```
$ python -c "sqlite3 ... fist-mbt.db → SELECT count(*) FROM tasks"
  fist-mbt.db tasks=2450                       ← 与清理前一致

$ FIST_DB_PATH="$PWD/fist-mbt.db" python scripts/fist.py call status_summary
  {"version":"0.3.10","total_tasks":2450,
   "by_status":{"已完成":907,"已归档":1526,"已暂停":6,"待领取":10,"已领取":1}}
```

**⚠️ 一个必须说清的读数**：不带 `FIST_DB_PATH` 裸跑 `fist.py` 时返回 `total_tasks: 0`。
**这不是我的清理造成的** —— `scripts/fist.py:44-48` 是既有设计（`BUG-122` 收口）：
> 「不带 `FIST_DB_PATH` 裸跑会把演示数据写进仓库根的自举台账 `fist-mbt.db`。
> **默认改道 `temp/` 下的隔离库**」

**⇒ 这是保护机制，不是回归。** 用显式路径就回到 2450。

---

## 分析：核心动机实现了吗？—— **部分实现，而且要分清两件事**

提案 §一.2 的原话：
> 「**95 个 `*.db`**（含 `fist-mbt.db` 14.6MB）+ **37 个 `temp_*/build*.log`** + 3 个 `.cron_state_*.json` + 10 个杂目录**散落根目录**。这些是每台机器各自不同的**运行时态，不该进主仓**。」

### 拆成两个可分别验收的目标

| 目标 | 清理前 | 清理后 | 是否达成 |
|---|---|---|---|
| **①「不该进主仓」**（版本控制层面） | `git ls-files '*.db' 'temp_*'` = **0** | 仍是 **0** | **✅ 原本就已达成** |
| **②「不散落根目录」**（视觉/导航层面） | 85 + 35 = **120 个** | **1 + 0 = 1 个** | **✅ 达成**（119 个已归档） |

**⇒ 关键发现：提案把「不该进主仓」当成待解决的问题，但 `.gitignore` 早已解决它。**
**真正剩下的问题只是「根目录难看 + `ls` 混入噪声」**，而这也是我这次解决的。

### 所以「核心动机实现了吗」的准确回答

> **实现了 —— 但实现的不是提案当时以为的那个理由。**
> 提案以为在防「污染主仓」，实际 `.gitignore` 早就防住了；
> 真正的收益是**根目录可用性**（`ls` 从 120 个噪声降到 1 个主库）。

### 为什么「归档」而不是「删除」

1. **`fist-mbt.db` 以外的 84 个里有 54 个有数据** —— 虽然都是测试夹具，但**它们是某些白盒锁的历史运行证据**
2. **`.fist-mbt/` 整体被 gitignore +「每机一份可随意删」**（提案 §3.1 原文）⇒ 放进去等于「随时可清」
3. **不可逆操作保守处理**：删除 119 个文件后若发现某个是某条锁的 fixture，无法恢复

**⇒ 归档到 `.fist-mbt/tmp/db-archive/` = 既达成根目录整洁，又保留可回溯性。**

### 一个诚实的边界：主库**仍在仓根**

提案 §3.1 的 `data/` 注释是「SQLite 库 + 模型路由状态」，
**按字面理解主库应该进 `.fist-mbt/data/`**。**但我没搬**，理由：

1. **`fist-mbt.db` 是活跃主库**（2450 任务，今天还在更新）
2. **`store_open` 的缺省 `data_dir` 是 `.fist-mbt/data/`，但 `fist.py` / server 的缺省是 `{cwd}/fist-mbt.db`** ——
   **两处缺省不一致**，单搬文件会让工具找不到库
3. **搬主库需要「改代码缺省路径 + 数据迁移」**，属**另一件任务**，不在本单范围

**⇒ 已写进 `.fist-mbt/README.md` 的「已知遗留」，明确标注「主库原地不动 + 为什么」。**

---

## 缺口与风险

### 1. 主库迁入 `.fist-mbt/data/` **未做**（需改代码）

这是提案 §3.1 的**字面要求**，我只完成了 6/6 目录创建 + 根目录清理。
**要真正完成需**：改 `fist.py` / `server.mbt` 的缺省库路径 + 迁移 2450 条任务 + 回归全部工具。
**⇒ 建议单独立项。**

### 2. `.fist-mbt/db/` 是个**提案里没有的目录**

提案 §3.1 只有 `data/`、`pool/`、`state/`、`logs/`、`tmp/`、`cache/`、`lock/`。
实测 `.fist-mbt/db/` 存在且含 2026-10-22 的旧库（2278 任务）。
**它可能是某次临时迁移的残留，也可能是更早的设计** —— **本轮未追查来源，未动它**。

### 3. 提案 §一.2 提到的 `.cron_state_*.json` 与 10 个杂目录

**本轮未处理**：`*.cron_state_*.json` 实测 **0 个**（已经不在了）；
杂目录 `_build/` `_scratch/` `__pycache__/` 等**已被 `.gitignore` 覆盖**，且它们是**构建产物**（删了会重建）。
**⇒ 不属「清理」范畴，属「本来就该在的」，未动。**

### 4. 归档目录会持续增长

`.fist-mbt/tmp/db-archive/` 现在 84 个文件 ≈ 12MB。**没有任何机制清理它。**
建议：**纳入 `task_cleanup` 式的周期清理**，或加一条「超过 N 天自动清」。

### 5. 未跑 `check_fist_layout` 守卫

提案验收清单提到「双守卫 `check_fist_layout` / `check_plan_location` 通过」。
**本轮只验证了目录存在 + 主库完好，没跑 `check_fist_layout`**（若有此脚本）。

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-27-fist-dir-layout-cleanup-report.md` |
| 目录说明 | `.fist-mbt/README.md`（**gitignored，不随主仓走** —— 这是设计意图） |
| 归档位置 | `.fist-mbt/tmp/db-archive/`（84 个 .db）· `.fist-mbt/tmp/logs-archive/`（35 个日志） |
| **建议后续** | ① 主库迁入 `.fist-mbt/data/`（需改代码，独立立项）② 查清 `.fist-mbt/db/` 来源 ③ 归档目录加周期清理 |
| **未做** | **未删除任何文件**（只移动）· **未动 `src/` `scripts/` `memory/` `reports/`** · **未搬主库** |
