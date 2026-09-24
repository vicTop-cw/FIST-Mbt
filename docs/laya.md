# Laya 集成（可选外部决策工具）

> **一句话**：fist-mbt 提供 `laya_decide` 这个**可选** MCP 工具——自动探测机器上有没有 Laya，
> 有就默认用它给「目标任务描述」做结构化决策（难度/领域/是否需工具/是否敏感），没有就静默降级，
> 完全不影响现网 schedule / omega / decompose 等既有工具。

## 1. 为什么引入 Laya

fist-mbt 的拆解/调度（`plan`、`task_plan_deep`、`schedule`、`omega`）依赖规则与 LLM 判断。
Laya 是一个 Python ML 决策模型（ModernBERT，405M 参数），它把**规则分级语义**中的模糊地带
（「这任务算多难？属于哪个领域？要不要工具？敏感不敏感？」）变成可复用的结构化打分，正好补上
「纯规则盲区」与「LLM 昂贵判断」之间的一段：

- **任务拆解边界**：`difficulty` 分数（0 trivial / 1 easy / 2 moderate / 3 hard）辅助决定拆几层、
  split_n 取多大；
- **任务类型判断**：`domain` 单选（code / math_or_logic / writing / factual_lookup /
  data_analysis / chitchat）辅助决定派给哪类执行者、是否需要专门语料/验证门禁；
- **工具/敏感门控**：`needs_tools` / `is_sensitive` 两个 0-1 分数辅助决定是否走工具增强、
  是否标 sensitive 交人工。

## 2. 关键设计：可选 + 自动探测 + 降级

| 原则 | 实现 |
|---|---|
| 可选 | `laya_decide` 是独立工具，不侵入现有 schedule/omega/decompose |
| 自动探测 | 每次调用先 `laya_decide.py --probe`（退出码 0=可用 3=不可用） |
| 默认用上 | 探测到可用 → 走真实 `Router.predict` |
| 否则不用 | 探测不可用/调用异常 → 返回 `{available:false, fallback}`，**不报错** |
| 平台兜底 | js 目标跑真实 node spawn；native 目标桩返回 `available:false` |

核心保证：**laya 缺失或故障绝不导致 fist-mbt 任何工具报错或阻塞**，一切退化为「用现有 schedule / LLM」。

## 3. 架构与文件

```
fist-mbt
├── scripts/laya_decide.py     # Python sidecar
│     --probe                   探测（退出码 0/3/1）
│     空参数 + stdin JSON        决策（强转 single-line JSON 到 stdout）
└── src/server/
    ├── laya_js.mbt            # js 目标：node child_process spawn + stdin 喂 JSON
    ├── laya_native.mbt        # native 目标：桩 → 返回 available:false
    └── server.mbt             # 注册 laya_decide MCP 工具（每次调用实时探测）
```

### 3.1 sidecar 输入/输出（`scripts/laya_decide.py`）

**stdin**（单行 JSON）：

```json
{
  "context": "目标任务描述",
  "questions": {...},          // 可选，缺省用 laya.router_questions()
  "model": "english"           // 可选
}
```

**stdout**（成功时）：

```json
{
  "available": true,
  "answers": {
    "difficulty": {"type":"score","score":2.1,...},
    "domain": {"type":"choice","choice":"code",...},
    "needs_tools": {"type":"noul","noul":0.003,...},
    "is_sensitive": {"type":"noul","noul":0.0002,...}
  },
  "auto_decide": false,       // 所有 answer 低置信度→false
  "escalate": true            // 任一 answer confidence<0.6 → 建议人工
}
```

**退出码**：`0` 成功（含 available:false 时也能被读取）、`1` 运行期异常、`3` Laya 不可用。

## 4. MCP 工具 `laya_decide`

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `context` | string | 是 | 待决策的任务/文本描述 |
| `questions` | string(JSON) | 否 | 决策 schema；缺省用 Laya 内置 |
| `model` | string | 否 | 默认 `english` |

**返回**：mode=text 的 JSON 字符串。两条分支：

- **可用**：`{available:true, answers:{...}, auto_decide, escalate, exit_code:0}`
- **降级**：`{available:false, fallback:"use existing schedule / LLM", reason:"..."}`

## 5. 安装 Laya（可选，本机已验证）

```bash
python -m pip install laya        # 已验证 0.3.12
# 首次调用 predict 会触发 712MB 模型下载（HF Hub 缓存），缓存后即快速
```

不装也可以——`laya_decide` 会返回 `available:false` 降级，其余工具不受影响。

## 6. 端到端实录（可用 / 降级两条路径）

**可用路径**（本机已装 Laya）：

```json
{"jsonrpc":"2.0","id":"1","method":"tools/call","params":{
  "name":"laya_decide",
  "arguments":{"context":"把 fist-mbt 扩展为对接飞书审批流"},
  "_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}}}
```

响应片段：`available:true`、`difficulty.score≈2.1`(moderate)、`domain=code`、
`needs_tools≈0.003`、`is_sensitive≈0.0002`、`auto_decide:false`、`escalate:true`。

**降级路径**（模拟 probe 失败）：返回

```json
{"available":false, "fallback":"use existing schedule / LLM",
 "reason":"机器上未探测到 Laya（python-sidecar 不可用），已降级"}
```

## 7. 对「任务拆解边界 / 任务类型判断」的具体使用建议

- **边界（split 粒度）**：`difficulty.score ≤1` → 一次原子任务；`2` → 拆 1-2 层；`3` +
  `needs_tools.noul<0.5` → 上 `schedule`/`watchdog`，配合 `plan` split_n。
- **类型（派发/门禁）**：`domain=code` → 走工程执行者；`factual_lookup` → 走检索子代理；
  `is_sensitive.noul>0.5` → 挂起交人工裁决（金条四不可逆边界）。
- **升迁信号**：`escalate:true` 表示 Laya 自身不确定（低置信度），交给现有 LLM/规则流程兜底。

## 7b. 接入 `task_plan_deep` 自动选档

`task_plan_deep` 新增可选参数 **`laya_auto`**（默认 `false`，不传=现状）。开启后：

1. 先探测 Laya 可用性；
2. 可用 → 用该任务描述的 `difficulty.score` 自动定每层拆分数
   `split_n = clamp(round(score)+2, 2, 6)`（score 0→2 / 1→3 / 2→4 / 3→5）；
3. 把完整 Laya 决策附到返回的 `laya` 字段（含 `auto_split_n`、answers、context）；
4. 不可用 / 调用异常 → 回退显式或默认 split_n，行为与现状完全一致。

不传 `laya_auto` 时返回格式与原来逐字节一致，不影响既有调用方（如 watchdog）。

**端到端实录**（`laya_auto:true`，任务描述为多租户编排服务设计）：`difficulty.score=2.175`
→ `auto_split_n:4`，实际拆出 4 个子任务，返回附 `laya.domain=code`、`needs_tools=0.9`。

## 8. 边界与遗留

- **只读辅助**：`laya_decide` 只做「判断/打分」，不写任何任务状态。
- **实时探测**：每次调用都 probe，保证「机器装了就用、卸了就降级」实时准确；换来每次 ~150ms probe 开销。
- **native 目标**：返回 `available:false`（桩），native 下无 Python 决策，需在 node 下跑 server 才有真实决策。

*（内容由AI生成，仅供参考）*