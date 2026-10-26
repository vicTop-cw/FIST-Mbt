# Lane I · 7 条 blocked 任务归档执行报告 · 2026-10-26

> **任务**：按统帅批准，把 Lane B 核实为「零风险可清理」的 7 条 blocked 从 `已暂停` 归档
> **执行人**：司令-γ · **纪律**：只走 `archive`，**零 `delete`**；逐条 get 核状态；不碰 vools 73 条、不碰 `T0r588`
> **结果**：**4 条归档成功 / 3 条被 Omega 门禁拦截 / 0 条删除**

---

## 结论

| # | task_id | 结果 | 原因 |
|---|---|---|---|
| 1 | `T0r636.1.2` | ❌ **FAILED** | Omega 门禁拦截（描述含 `[omega:required]`） |
| 2 | `T0r636.2.2` | ❌ **FAILED** | 同上 |
| 3 | `T0r636.3.2` | ❌ **FAILED** | 同上 |
| 4 | `T0r662.1.2` | ✅ **ARCHIVED** | — |
| 5 | `T0r662.1.3` | ✅ **ARCHIVED** | — |
| 6 | `T0r662.2` | ✅ **ARCHIVED** | — |
| 7 | `T0r672` | ✅ **ARCHIVED** | — |

**已暂停：85 → 81（减 4，不是减 7）。**
**`delete` 用量：0。**

---

## 证据

### 1. 前后条数（`list({status:"已暂停"})`）

```
归档前 list --status 已暂停 = 85 条
归档后 list --status 已暂停 = 81 条
```

### 2. 逐条回执原文

**① T0r636.1.2** — get `已暂停` → tx_contract(force) `allowed` → archive
```json
{"_error": {"code": -32000, "message": "Omega 门禁拦截归档: Omega 强验证门禁：任务 [T0r636.1.2] 尚未做成果复验，请先由验证者执行 omega_result_verify"}}
```

**② T0r636.2.2** — 同上
```json
{"_error": {"code": -32000, "message": "Omega 门禁拦截归档: Omega 强验证门禁：任务 [T0r636.2.2] 尚未做成果复验，请先由验证者执行 omega_result_verify"}}
```

**③ T0r636.3.2** — 同上
```json
{"_error": {"code": -32000, "message": "Omega 门禁拦截归档: Omega 强验证门禁：任务 [T0r636.3.2] 尚未做成果复验，请先由验证者执行 omega_result_verify"}}
```

**④ T0r662.1.2** — get `已暂停` → tx_contract(force) `allowed` → archive
```json
{"status": "已归档"}
```

**⑤ T0r662.1.3**
```json
{"status": "已归档"}
```

**⑥ T0r662.2**
```json
{"status": "已归档"}
```

**⑦ T0r672**
```json
{"status": "已归档"}
```

### 3. 失败者与成功者的差异（根因定位）

直接查库 `fist-mbt.db`：

```
失败（3 条）：
  ('T0r636.1.2', '已暂停', omega_required=0, 'fist-opt-20261016')
  ('T0r636.2.2', '已暂停', omega_required=0, 'fist-opt-20261016')
  ('T0r636.3.2', '已暂停', omega_required=0, 'fist-opt-20261016')

成功（4 条）：
  ('T0r662.1.2', '已归档', omega_required=0, 'light-isolation')
  ('T0r662.1.3', '已归档', omega_required=0, 'light-isolation')
  ('T0r662.2',   '已归档', omega_required=0, 'light-isolation')
  ('T0r672',     '已归档', omega_required=0, 'bugs')
```

**`omega_required` 两边都是 0**，但失败者仍然被 Omega 门禁拦住。**差别在描述文本**：

```
失败者描述含 [omega:required] 标记：T0r636.1.2 ✓ / T0r636.2.2 ✓ / T0r636.3.2 ✓
```

源码判据（`src/engine/omega_strong.mbt`）：
```moonbit
pub fn omega_enabled(t : @core.Task) -> Bool {
  t.get_omega_required() || t.description.contains(omega_mark())
}
```

**⇒ 这 3 条命中「文本兜底面」**：元数据列 `omega_required=0` 但描述里带着 `[omega:required]`，
于是 `omega_enabled` = true，而归档路径（含 `archive_force(force=true)`）**也受 Omega 成果复验门约束**。

---

## 分析

### 1. 为什么 3 条被拦而 4 条通过 —— 不是随机

三条失败者（`T0r636.*`）是**某次 `plan_deep(omega_strong_verify=true)` 的产物**：
描述尾部带 `[边界四问:…] · 剩余兄弟: 1]`，且含 `[omega:required]` 标记
⇒ **它们是「开了强验证的拆解树」的叶子**。

四条成功者（`T0r662.*` + `T0r672`）描述里**没有** `[omega:required]` ⇒ `omega_enabled=false` ⇒ 归档直通。

**⇒ 这不是 archive 的 bug，是 Omega 门禁按设计工作**：开了强验证的任务，**成果没做复验就不许归档**。

### 2. 但它暴露了一个**能力死角**（本单最有价值的发现）

这 3 条任务的情况是：
- 父任务**已归档**（它们本身就是孤儿）
- `omega_required` 元数据 = **0**（没在元数据列上标）
- 只有描述里残留 `[omega:required]` 文本

**⇒ 想归档它，唯一合规路径是先 `omega_result_verify`；而没有交付物、父已归档的任务，做成果复验没有意义。**

**`archive_force(force=true)` 的语义是「放行已完成/已暂停/已打回三类滞留态」，
但它**没有豁免 Omega 门禁** —— 于是「强制归档」这个逃生口对这 3 条**不可用**。**

**这是盲区：`force` 管状态机前置，不管门禁族。两者是两道独立的门，而 `force` 只开了前面那道。**

### 3. 关于流程的 4 次踩坑（原样记录）

| # | 坑 | 现象 | 真相 |
|---|---|---|---|
| 1 | `fist.py call list` | 恒返回 `[]` | 每次调用是新进程 ⇒ `store_open` 的 ns 不跨进程保留 |
| 2 | `store_open --data_dir .` | 建出空的 `bugs.db` / `default.db`（tasks=0） | 它切成 `<data_dir>/<ns>.db` 分库，而 85 条在**根库 `fist-mbt.db`** 单体库里 |
| 3 | `FIST_DB_PATH=./fist-mbt.db` | `store_open` 回执仍 `data_dir:"."` | 本 server 版本不认这个 env |
| 4 | 正确解法 | 不调 `store_open`，MCP 长连接直连 | `src/server/server.mbt:60`：「`""`/`"default"` → 模块级默认引擎（默认库 `fist-mbt.db`）」⇒ **list 立刻返回 85 条** |

**我误建的两个空库已清理**（`rm bugs.db default.db`，两者 `tasks=0` 且都在 `.gitignore` 的 `*.db` 面）。

### 4. `tx_contract` 的必要性被实证

不加 `force` 时，`tx_contract` 对全部 7 条返回：
```json
{"verdict":"rejected","phase":"precondition",
 "reasons":["非法迁移: archive 要求状态 [已完成]，当前是 [已暂停]"]}
```
**⇒ `archive` 裸调对这 7 条 100% 失败。`archive_force(force=true)` 才是正确入口**
（源码 `core_task.mbt:524-536`：「force=true 时放行 已完成/已暂停/已打回 三类滞留态直接入档」）。

**如果我没做 tx_contract 预检，会直接撞 7 次 precondition 拒绝，然后误以为「archive 坏了」。**

---

## 缺口与风险

| # | 缺口 | 影响 | 建议 |
|---|---|---|---|
| **1** | **3 条 `T0r636.*` 无法归档**（Omega 门禁 + 无交付物） | 85 → 81 而非 78 | 见下「建议统帅批准」#1 |
| **2** | **`archive_force` 不豁免门禁族** | 「强制归档」逃生口对带 `[omega:required]` 的任务失效 | 可作为机制缺陷上报（与 BUG-227 的 `force` 语义不完整同族） |
| **3** | **`store_open --data_dir` 会静默建空分库** | 我第一次就建出两个空库；若没人清理，下次读到的就是空库 | 建议 `store_open` 对「已存在根库 `fist-mbt.db`」时给出提示；或记入账本 |
| **4** | **`fist.py call` 不能跨进程保留 ns** | 所有一次性 CLI 调用查不到分库任务 | 已在报告 §分析-3 记下正确用法（MCP 长连接） |
| **5** | 未来清理 vools 73 条时可能**同样撞 Omega 门禁** | 需先核它们的描述是否带 `[omega:required]` | 建议批量归档前先查该字段 |

---

## 建议入档位置

### 本报告
`reports/2026-10-26-lane-i-archive-execution.md`（本文件）

### 辅助脚本与中间数据
- `temp/audit/lane_i_run.py`（常驻 MCP 长连接执行器，含 4 个坑的注释）
- `temp/audit/lane_i_results.json`（逐条回执原文）
- `temp/audit/lane_i_archive.py` / `lane_i_mcp.py`（前两版失败尝试，作为「为什么不能用 fist.py」的证据）

### 建议统帅批准 / 裁决

| # | 动作 | 说明 |
|---|---|---|
| **1** | **3 条 `T0r636.*` 改走 `omega_result_verify` 后归档** | 需先以 `verifier` 身份对它们执行一次成果复验（无交付物时可判「不适用」并说明），再 archive。**或**由你裁决「直接 archive 并接受门禁记录」 |
| **2** | **上报一条机制缺陷**：「`archive_force` 的 `force` 只放开状态机前置、不放开门禁族」 | 我未自行上报（边界外），建议由你或对应车道入账 |
| **3** | **`store_open --data_dir .` 建空分库** 是否入账 | 同上 |

### 剩余工作（未执行，等你裁决）
- vools 73 条：未动（按派单边界）
- `T0r588`：未动（A 类真阻塞，转人工裁决）
- 剩余 81 条 blocked 中，77 条是 vools/zn 等外来项目，4 条是 `fist-opt` / `light-isolation` 残片
