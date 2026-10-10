# FIST-Mbt 12 轮自我迭代 · Round 7 汇报（评估 mizchi/llm）

- 日期：2026-10-10
- 轮次：Round 7 of 12
- 主题：评估 `mizchi/llm` 纯 MoonBit LLM 客户端替代 Python sidecar（BACKLOG P2-9）

## 评估过程

1. `moon search mizchi/llm` → 发现 `mizchi/llm@0.3.2`（151964 downloads，纯 MoonBit LLM 客户端，
   支持 Anthropic/OpenAI/Ollama/OpenRouter + streaming + tool calling + agent loop）。
2. `moon add mizchi/llm` → 成功加入依赖（自动拉入 `moonbitlang/regexp@0.3.5`、`mizchi/x@0.5.3`）。
3. 分析本仓 Python sidecar 清单（`scripts/*.py`），归类为两类：
   - **类 A：ML 模型 sidecar** —— 仅 `laya_decide.py`（调用 Laya Python ML 分类模型）
   - **类 B：薄封装 CLI** —— `output_validate.py` / `issue_scan.py` / `fist.py` 等，
     真实逻辑单真源在 MoonBit（`src/server/output_validate.mbt` / `src/server/issue_scan.mbt`），
     Python 只负责拉起 `node _build/js/.../cli.js` 并调用 MCP 工具。

## 评估结论

**不采用。** 理由：

| 候选替代对象 | mizchi/llm 能否替代 | 原因 |
|---|---|---|
| `laya_decide.py` | ❌ 不能 | laya 是 ML 分类模型，mizchi/llm 是 LLM 客户端，类型不匹配 |
| `output_validate.py` | ❌ 不适用 | 真实逻辑在 MoonBit，Python 只是 CLI 封装，与 LLM 无关 |
| `issue_scan.py` | ❌ 不适用 | 同上 |
| `fist.py` | ❌ 不适用 | 同上 |

若强行用 mizchi/llm 替代 laya（让 LLM 做决定），会引入：
- 网络依赖（LLM API 调用）
- API 密钥（违反 `check_model_auth_no_key` 守卫）
- 非确定性输出（违反「确定性优先」支柱；`laya_route` 内建分支已经是确定性回退）

**结论**：本仓不需要在 MoonBit 里调 LLM；mizchi/llm 能力虽强，但用错场景。
已在 `moon.mod` 移除该依赖，保持仓库依赖面最小。

## 净交付

- 新增：`docs/2026-10-10-mizchi-llm-eval.md`（评估文档，含需求背景/API 清单/逐项结论）
- 更新：`BACKLOG.md` P2-9 标记 `done(eval-no-op)` + 一句话结论
- 依赖面：`moon.mod` 保持原状（mizchi/llm 添加后移除，无残留）
- 回归：`moon test --target js` 全量通过（无源码改动，仅文档）

## 资源消耗

- 子代理：0 个（纯本地评估，无需委派）
- 命令：`moon search` / `moon add` / `moon remove` / `moon test`

## 遗留

- 未来若引入「LLM 决策环节」，mizchi/llm 是首选纯 MoonBit 客户端（零 Python 依赖）；
  但必须遵守 `check_model_auth_no_key` 守卫（API 密钥只能环境变量注入）+「确定性优先」支柱
  （LLM 只做决策建议，验证/评分/门禁仍走确定性路径）。
