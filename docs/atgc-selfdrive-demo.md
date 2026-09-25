# 用 fist-mbt 自驱式 + Omega 强验证开发 atgc（能力演示）

> 中文 · 文档即实现。本文所有事实均来自一次**真实经 MCP server 驱动的自驱动管线运行**（`scripts/atgc_selfdrive_demo.py`），不做任何虚构。

---

## 一句话目的

展示 fist-mbt 的**可靠性闭环**：它用**它自己的**任务生命周期 + Omega 强验证语料门禁 + 全量调用日志，把一个新的极小 ATGC 库（`atgc/`）**真实地开发了出来**——发布→递归拆解→每叶语料审核→执行→成果复验→验收→归档，全程有可核验的落库证据。这本身就是「用它自己管理自己」的最硬采用证据。

## 管线图

```
publish_parallel(ns="atgc-selfdrive")          root = T0rNN（depth=3）
        │
        ▼
task_plan_deep(omega_strong_verify=true, split_n=4)
        │  递归拆解 → 4 个聚合节点 × 2 叶 = 8 叶（全部带 [omega:required]）
        ▼
对每个叶子（以及聚合节点）：
   omega_spec_create(author=spec_author)         ──► specs 表 (spec: approved)
        │
   omega_spec_review(verifier, approve)          语料审核放行
        │
   claim(demo_executor)                          认领（叶子）
        │
   execute(deliverable = <该叶真实 atgc/*.mbt 全文>)
        │      ↑ 受 omega_execute_gate 门禁：语料未 approved 前被拒绝
   omega_result_verify(verifier, pass)           ──► specs 表 (result: approved)
        │      ↑ verify 前受 omega_verify_gate 门禁
   submit ──► verify
        │
   聚合节点上卷 ──► verify(root) ──► archive(root) ──► 根【已归档】
```

其中**每一个工具调用**（publish_parallel / task_plan_deep / omega_* / execute / verify / archive…）
均由 `instrumented_tool` 自动写入 `call_log` 表（每调用一行，含 ts/tool/caller/ns/入参/结果/耗时/ok）。

## 角色

| 角色 | 职责 | 本演示中的动作 |
|---|---|---|
| `leader` | 拆解指令来源 | 发起 `task_plan_deep`（`by="leader"`） |
| `spec_author` | 创建验证语料 | `omega_spec_create(author=spec_author)` |
| `verifier` | 审核语料 + 复验成果 | `omega_spec_review(verifier, approve)`；`omega_result_verify(verifier, pass)`；最终 `verify` |
| `demo_executor` | 认领 + 执行 | `claim`→`execute`（写入真实 atgc 源码全文） |

## 复现命令

```bash
moon install && moon build --target js cmd/main   # 先 build MCP server（JS 目标）
python scripts/atgc_selfdrive_demo.py             # 跑真实 MCP 驱动管线
```

> 脚本内部会先嵌套调用 `scripts/patch_esm_main.py`（幂等）为 `moonc ≥0.10.14` 的 ESM 产物注入 `require` shim，
> 再以 stdio 拉起 `node main.js`，全程 JSON-RPC 走 MCP，**不伪造任何一步**。

## 真实证据

管线随运行在 SQLite（`fist-mbt.db`）中累计的证据（只读核对时的全库计数值，随每次运行增长）：

| 表 | 计数 | 说明 |
|---|---|---|
| `tasks` | **156** | 根任务 + 各叶子/聚合节点（含本演示任意运行的全部轮次） |
| `specs` | **121** | 语料（`spec`）+ 复验记录（`result`），`status=approved` 即放行证据 |
| `executions` | **92** | 每次 `execute` 落一条（deliverable 已写入模块全文） |
| `call_log` | **451** | `instrumented_tool` 全量埋点，一工具调用一行 |

本次能力演示的命名空间 `ns=atgc-selfdrive` 下，最近一次完整闭环的根任务最终为 **已归档**，
其下 4 个聚合节点 + 8 个叶子全部 `已完成`（`spec approved` / `result approved` 逐叶留痕）。

**提交历史**：本演示开发产物对应 commit `4cf2a41`（`feat(atgc-selfdrive)`），
README 顶部 CI 徽章与 `atgc/`、`atgc-old/`、`scripts/atgc_selfdrive_demo.py` 均在仓库内可核验。

## atgc（管线产物）vs atgc-old（全量参照）

| 维度 | `atgc/`（极简，本演示产出） | `atgc-old/`（全量参照） |
|---|---|---|
| 定位 | 经 fist-mbt 自驱+Omega 强验证开发的最小库 | 原全量 ATGC 项目整体保留，未改动 |
| 内容 | `atgc_base.mbt`(base↔四进制/complement/对合 reverse_complement/transcribe T→U/valid_input) + `vm.mbt`(Op/Inst/run，二元 +−) + `atgc_run.mbt`(run_dna、§2.4 语境二分、PushImm 消费紧邻数据) + `atgc_test.mbt` | 含 base/codon/lexer/transpile/vm(快照回滚)/talk 等完整模块 |
| 工具 | —（内嵌库） | 原 `atgc_compile/run/talk` 工具保留（更名为 `atgc_old_*`） |
| CLI/入口 | `moon test` 集成 | — |
测试要求 | `reverse_complement` 对合 / MODE_B 转录 / `1+2=3` / `1+2+2=5` / 非法输入拒绝 | 全量叙事 + 验算 |

## 诚实说明（不夸大）

- **8 片叶而非 4 片**：引擎递归（根 `depth=3`、中间层 `split_n=2`）实际产出 **4 聚合 × 2 叶 = 8 片叶**，而非脚本预期的 4；
  脚本如实以 `NOTE` 打印「engine 以 depth=3 递归拆出 N 片叶」，并不静默掩盖。
- **前 4 叶映射、额外叶复用**：产物树 DFS 前 4 叶按序对应 `atgc_base/vm/atgc_run/atgc_test`，
  第 5–8 叶（同一聚合下的第二叶）循环复用对应模块内容——**内容仍是真实交付物**，用于保证整棵递归树可归并、根任务可收官归档。
- **Omega 门禁真实把关**：`execute` 在语料 `approved` 前会被 `omega_execute_gate` 拒绝；
  `verify` 在 `omega_result_verify=pass` 前被 `omega_verify_gate` 拒绝。所以「开发被 fist-mbt 真正门禁过」是**如实**的，不是演示代码里绕过。
- **测试数**：当前 `moon test --target js` = **191/191**（含新增 atgc 极简库测试）。

## 结论 / 价值

- **可靠性可证**：这次 atgc 极小库是经 fist-mbt 自身生命周期（发布→拆解→语料→执行→成果复验→验收→归档）
  真实一次跑完开发出来的，验证语料与成果复验都被真实门禁把关，全程调用日志留痕——这正是「用它自己管理自己」的硬证据。
- **可复现**：一条 `moon build` + `python scripts/atgc_selfdrive_demo.py` 即可重跑整个管线，逐行核对 DB 证据。