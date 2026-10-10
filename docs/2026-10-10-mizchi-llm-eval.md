# mizchi/llm 纯 MoonBit LLM 客户端评估（BACKLOG P2-9）

> 日期：2026-10-10 · 触发：12 轮迭代 Round 7 · 结论：**不采用**（评估通过但引入网络/密钥依赖，违背本仓守卫）

## 一、需求背景

BACKLOG P2-9：评估 `mizchi/llm` 纯 MoonBit 客户端，进一步纯化——移除 Python sidecar（主要就是 `scripts/laya_decide.py`）。

## 二、mizchi/llm 是什么

`mizchi/llm@0.3.2`（151964 downloads）是纯 MoonBit 的 LLM 客户端库：
- Provider：Anthropic / OpenAI / Ollama / OpenRouter
- 能力：流式 chat / tool calling / agent loop / JSON validation / message management
- 子包：`agent`（SessionManager / CronService / SubagentQueue）、`anthropic`、`claude_code` 等
- 依赖：`mizchi/x`、`moonbitlang/regexp`（均已在仓库依赖或 registry 可得）

## 三、评估问题

**Q1：能否替换 `scripts/laya_decide.py`？**

- `laya_decide.py` 调用的是 **Laya ML 分类模型**（Python 生态），不是 LLM。
- `mizchi/llm` 是 LLM 客户端，两者**不可直接替代**——laya 输出确定性分类（feature_route/split_n），
  mizchi/llm 输出自然语言/JSON。
- 即使把 laya 换成「让 mizchi/llm 做决定」，会引入：
  1. 网络依赖（LLM API 调用）
  2. API 密钥（违反 `check_model_auth_no_key` 守卫——本仓不得出现模型认证密钥）
  3. 非确定性输出（与「确定性优先」支柱冲突；`laya_route` 内建分支已经是确定性回退）
- **结论：不可替换，且替换有负收益。**

**Q2：能否替换其他 Python 脚本（output_validate.py / issue_scan.py / fist.py）？**

- 这些脚本都是「薄封装」：真实逻辑单真源在 MoonBit（`src/server/output_validate.mbt`、`src/server/issue_scan.mbt`），
  Python 只负责拉起 `node _build/.../cli.js` 并调用 MCP 工具。
- 它们**不依赖 Python 做任何判断**，只是「CLI 形态」的一源四态投影，与 mizchi/llm 无关。
- **结论：不适用。**

## 四、结论与后续

- **评估结论**：mizchi/llm 不适用于当前 FIST-Mbt 的 Python sidecar 替代场景。
- **根本原因**：本仓的 Python 依赖只有两种——① laya（ML 模型，非 LLM）；② 薄封装 CLI（逻辑在 MoonBit）。
  mizchi/llm 解决的是「在 MoonBit 里调 LLM」，本仓**不需要**在 MoonBit 里调 LLM。
- **BACKLOG 状态**：P2-9 标记为 `eval-no-op`（评估完成，不采用；附本文件为据）。
- **未采用的原因（供未来参考）**：
  - 若未来引入「LLM 决策环节」，mizchi/llm 是首选纯 MoonBit 客户端（零 Python 依赖）。
  - 但必须遵守 `check_model_auth_no_key` 守卫：API 密钥只能通过环境变量注入，不得硬编码。
  - 必须遵守「确定性优先」支柱：LLM 只能做**决策建议**，验证/评分/门禁仍走确定性路径。

## 五、依赖状态

- 已在 `moon.mod` 添加 `mizchi/llm@0.3.2`（评估期依赖）。
- 最终决定**不保留**该依赖（本仓未使用）→ 已在提交中移除，保持仓库依赖面最小化。
- `moonbitlang/regexp` 若被其它依赖拉入则保留；否则一并清理。

*（内容由 AI 生成，仅供参考）*
