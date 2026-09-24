---
topics: [evolve, dgm, self-driving]
doc_kind: guide
created: 2026-09-24
---

# evolve 模块：DGM 档案库（使用指南）

> 状态：可用（已随 `0.2.3` 后并入）。实现：`src/evolve/`，通过 MCP 工具 `evolve_*` 暴露。
> 机制来源：移植自 `dna_forge`（DGM 论文的核心档案库设计），用 MoonBit 重写并以**域无关**方式抽象。

## 一、它是什么

`evolve` 实现了 DGM（Gradient-based Decoupled Meta-programming）论文中最重要的机制——**档案库 + 多样性加权采样**：

1. **保留所有通过门槛的产物**（包含低分，故意不淘汰）。DGM 实证：最优 agent 的谱系常经过【性能下降】的中间节点，爬山法会立刻抛弃它们，而档案库保留它们，后来的突破正建在其上。消融数据：贪心 39.7% vs 多样选择 50.0%。
2. **采样 = 性能加权 × 子代探索**（`p ∝ s·h`），任何产物都保留非零概率，路径不被永久封死。
3. **可计算评分**：绝不让 LLM 自评，评分是注入式的（可对接 Omega gate / run_check）。

它被设计成**域无关**——`goal / note / code` 是任何"产物"的通用元数据（可以是语言设计、代码、文档、配置），没有 DNA 领域的硬编码。

## 二、核心概念

| 概念 | 说明 |
|---|---|
| `Artifact` 产物 | 档案库中的一个条目：`id / parent_id / goal / note / code / score / parts / children / created_at` |
| `Archive` 档案库 | 产物的容器（进程内 Map），提供操作与采样 |
| 谱系（lineage） | 沿 `parent_id` 回溯的"垫脚石链"——看到最优解是如何经过低分中间态演化而来 |

### 打分模型（可配置）

采样权重 = 性能分量 × 新颖性分量：

```
weight = sigmoid(λ(score - α0)) × 1/(1+children)
```

- 性能分量：`score` 越高越可能被选作**父代**，但用饱和映射防单节点垄断；
- 新颖性分量：`children`（已有子代数）越少越该被探索，防止收敛到单一路线。

## 三、库 API（MoonBit）

包：`vicTop-cw/fist-mbt/src/evolve`（`src/evolve/`）。

### Archive（档案库）

| 方法 | 签名 | 说明 |
|---|---|---|
| `new` | `(String) -> Archive` | 新建档案库 |
| `add` | `(Archive, Artifact) -> Unit` | 加入产物；若 parent 在库中，自动递增其 children |
| `get` | `(Archive, String) -> Artifact?` | 按 id 取产物 |
| `all` | `(Archive) -> Array[Artifact]` | 全部产物 |
| `len` / `is_empty` | — | 数量 / 是否为空 |
| `best` | `(Archive) -> Artifact?` | 最高分产物 |
| `sample_parent` | `(Archive, lam?, a0?, rand~ : () -> Double) -> Artifact?` | **p∝s·h 多样性采样**父代 |
| `is_duplicate` | `(Archive, goal, threshold?) -> Bool` | Jaccard 查重（防重复做同一事） |
| `novelty` | `(Archive, note) -> Double` | 相对档案库的新颖度 [0,1] |
| `summaries` | `(Archive, limit?) -> Array[String]` | 高分优先摘要，给课程生成器 |
| `dead_ends` | `(Archive, limit?) -> Array[String]` | 低分"此路不通"地图 |
| `lineage` | `(Archive, from, depth?) -> Array[(String, Double, String)]` | 谱系回溯 |

### Artifact（产物）

| 方法 | 签名 | 说明 |
|---|---|---|
| `create` | `(id~, parent_id~, goal~, note~, code~, score~, parts~, created_at~) -> Artifact` | 构造产物 |
| `to_json` / `from_json` | — | 与 JSON 互转 |
| `with_children` | `(Artifact, Int) -> Artifact` | 返回 children 更新后的副本 |

## 四、MCP 工具

三个 `evolve_*` 工具（走 `tools/call`）。当前 Archive 为**进程内**状态（`evolve_arc` 模块变量）；SQLite 持久化能力已就绪（`evolve_artifacts` 表 + store 方法），供后续接入。

### 1. `evolve_submit` — 归档一个产物

```
tools/call  evolve_submit {
  id, goal, note, code,      // 必填
  score: 0,                  // 可计算评分（默认 0）
  parent_id: "",             // 父产物 id（可选）
  parts: "{}",               // 评分分项 JSON（可选）
  now: <timestamp>           // 时间戳（可选）
}
```

- 若 `goal` 与库中已有产物 Jaccard 相似度 ≥ 0.88，返回 `{rejected: true}`（防重复）。
- 成功返回该产物的 JSON。

### 2. `evolve_sample` — 采样父代

```
tools/call  evolve_sample { rand: 0.5 }
```

按 `p∝s·h` 多样性加权返回一个父代 `picked`。空库返回 `picked: null`。

### 3. `evolve_snapshot` — 查看档案库

```
tools/call  evolve_snapshot {}
```

返回 `{ count, best, summaries, dead_ends, lineage_of_best }`——一次看清最优解、摘要、低分地图与谱系。

## 五、端到端使用示例（走 MCP）

构造一个 3 层谱系的编译器演化：

```
evolve_submit { id:"v1", goal:"实现词法分析", note:"DFA 状态机", code:"lex", score:0.4 }
evolve_submit { id:"v2", goal:"实现语法分析", note:"递归下降", code:"parse", score:0.7, parent_id:"v1" }
evolve_submit { id:"v3", goal:"实现代码生成", note:"LLVM", code:"codegen", score:0.9, parent_id:"v2" }

evolve_snapshot {}
// count:3  best:id=v3  lineage:[v3 0.9 代码生成] → [v2 0.7 语法分析] → [v1 0.4 词法分析]

evolve_sample { rand:0.5 }   // 高分配偶 v3 更可能被选中作为下一步父代
```

## 六、评分注入（与 Omega gate 对齐）

`evolve` 本身**不内置评分算法**——这是刻意的。建议评分逻辑对接 fist-mbt 已有的可计算判据：

- **`run_check`**：服务端真实执行外部判据命令，退出码 0 = passed；
- **`omega_verify` / Omega gate**：schema + fingerprint 校验，accuracy < 100% 一票否决；
- 在调用 `evolve_submit` 前先跑判据拿到 `score`，再入库——保证"评分数值可复现、非 LLM 自评"。

## 七、边界与注意

- 当前 MCP 的 Archive 是**进程内**状态，重启后清空；如需持久化，调用 store 层 `evolve_upsert / evolve_list / evolve_bump_child`（表 `evolve_artifacts`）。
- `is_duplicate` / `novelty` 基于**字符级 Jaccard**（中英文均适用），是粗粒度查重；生产可替换为 embedding 余弦。
- 测试：`src/evolve/evolve_wbtest.mbt`（5 用例，含采样/查重/新颖性/谱系）。

## 八、回归

改动不影响既有模块；全量 `moon test --target js` 保持 **136/136 全绿**。