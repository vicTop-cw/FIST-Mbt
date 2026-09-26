# SKILL: model-router — 模型配额路由 + 外部编码执行器（aider / atomcode）

> 形态：skill（本文档）｜MCP 工具 `model_route` / `model_router_status` / `model_router_reset` / `executor_run`
> 真源：`src/router/`（决策与状态 schema，纯计算零 IO）+ `src/executor/`（argv 形状，纯计算）
> + `src/server/model_router_ops.mbt`（落盘 / 盖章 / 起进程——唯一有 IO 的一层）
> 用途：让"用哪个模型"成为**可复现的确定性决策**而不是 agent 的心情——免费优先、达阈值自动切付费、
> 每模型独立 5h 滚动窗口；并把任务真正交给外部编码 CLI（aider/atomcode），且**不给调用方注入命令的机会**。

## 何时用

- **开工前问价**：一次 `model_route` 就知道当前该用哪个模型、各模型还剩多少配额（`usage.free_pool/paid_pool`）。
  留空 `record_model` 时**只决策不消耗**，可以随便问。
- **真实用完一次**：调 `model_route --record_model <池内模型名>`，`used+1` 后再决策；
  免费池整体越过 `threshold_pct`（默认 95%）时自动切付费并记 `switch_count`；付费池耗尽自动回退免费。
- **无人值守派单前**：`executor_run` 把活真交给 aider/atomcode（模型留空则路由器决定并记账），
  先 `dry_run=true` 审 argv，再去掉 `dry_run` 真跑。
- **窗口卡住时**：`model_router_reset`（等价"这 5 小时重新开始"）；`hard=true` 连档位/游标/计数一起复位。

## 怎么调（参数名 = schema 真名，不是杜撰）

### MCP 形态

```
tools/call model_route
  { "project_dir": ".", "namespace": "mytask",
    "record_model": "AtomGit-qwen3.8-27b",
    "config_json": "{\"window_seconds\":18000,\"threshold_pct\":95,\"free_pool\":[{\"name\":\"a\",\"limit\":100}],\"paid_pool\":[]}" }
```

| 参数 | 必填 | 说明 |
|---|---|---|
| `project_dir` | ✅ | 相对 server cwd；**拒绝绝对路径/盘符/`..`**（与 `report_bug` 同一条校验） |
| `namespace` | — | 默认 `default`；**每个 ns 一份独立配额账**，互不串用 |
| `record_model` | — | 给了就先记账再决策；留空=只问不消耗。名字不在池内 → `decision.reason` 点名"未在任何池中配置"且不记账 |
| `config_json` | — | RouterConfig 的 JSON 文本，覆盖池定义（同名模型的已用配额保留）。**非法 JSON 直接报错**，不静默回落 |

返回 `{ ok, stamped_at, decision{model,tier,reason,switched,available,next_switch_at}, usage{...}, warnings[], persisted, state_path }`。
`ok=false` 只有一种含义：**两池都不可用**——此时绝不静默改用别的模型，`note` 会明说。

```
tools/call model_router_status  { "project_dir": ".", "namespace": "mytask" }   # 只读，不落盘
tools/call model_router_reset   { "project_dir": ".", "namespace": "mytask", "hard": false }
tools/call executor_run         { "project_dir": ".", "namespace": "mytask", "executor": "aider",
                                 "prompt": "改 README 的测试数", "model": "",
                                 "timeout_ms": 180000, "dry_run": true }
```

`executor_run` 的 `executor` **只接受登记表里的名字**（当前 `aider | atomcode`）；argv 形状固定在
`src/executor/cli_argv.mbt`（aider：`--message/--model/--edit-format/--map-tokens/--encoding/--yes-always/--no-auto-commits`；
atomcode：`-p/-C/-y/--model`），可执行文件名同样由登记表推导 ⇒ 调用方无法借这个工具注入任意命令。

### CLI 形态（免写 JSON-RPC）

```
python scripts/fist.py call model_route --project_dir . --namespace mytask
python scripts/fist.py call model_router_status --project_dir . --namespace mytask
python scripts/fist.py call executor_run --project_dir . --namespace mytask \
       --executor atomcode --prompt "接线检查" --dry_run true
```

先 `moon build --target js` 再 `python scripts/patch_esm_main.py`（ESM shim），否则 `node main.js` 起不来。

### 四态关系

- **单真源 = MoonBit 实现**（`src/router` + `src/executor` + 服务端 ops 层）；MCP 工具直接调它，
  CLI 只是薄封装，不复制决策逻辑。
- **skill**（本文档）教 agent 何时用、参数真名、边界在哪。
- **Plugin** 态由 `scripts/gen_plugins.py` 从真源投影进四宿主目录，`check_plugin_sync.py`（cl7）拦漂移。

## 状态与时间语义（跟源项目不一样的三处，合并时的裁决）

| 项 | 本仓语义 | 为什么 |
|---|---|---|
| 时钟 | `stamped_at` 由**服务端盖章**，调用面**没有** `now` 参数 | BUG-33 政策：可注入时钟 = 可伪造窗口过期 |
| 时间换算 | ISO↔秒用 civil-days 精确算法（含闰年/跨月） | 源项目「365 天固定年 + 每月 31 天」会把 5h 窗口判偏（BUG-52） |
| 空池 | 返回 `available=false` + 明确 reason，不索引 `[0]` | 源项目空池直接越界 panic（BUG-53） |

状态落盘在 `{project_dir}/memory/model-router-{ns}.json`（schema v1），跨进程可复现；
坏状态**逐项回落并写进 `warnings`**（越界的 `free_idx` 会被夹紧——负游标取模后落到负下标会 panic），
且旧文件保留不删（坏状态是证据）。

## 安全边界

- 不含任何密钥：模型名与配额来自 `config_json` 或默认池定义，凭据只来自 server 进程环境变量。
  本仓库不读 `.env`，返回值里也不回显任何 key（`model_router_ops_wbtest` 的 rs_5/mo_* 有反证）。
- `dry_run=true` 只回显 argv、**一个进程都不起**（`executed:false`）。宿主命令能力默认收紧：先审后跑。
- 不经 shell：提示词里的 `;`、`$()`、反引号都只是 argv 里的一个字面量元素
  （`src/executor/cli_argv_test.mbt` 的 ca_5 钉住"整串是一个元素"）。
- native 构建下 `run_check_external` 返回明确拒绝，不假装成功。

## 已知边界

- 真实起进程（`dry_run=false`）会**真的调用外部 agent**，消耗真实配额——需要人明确点头，
  本文档不给"顺手跑一次"的建议；调用面只验证到 argv 与拒绝路径。
- 配额是**次数**不是 token/金额：`cost_estimate` 只是占位（atomcode 0.0 / aider -1.0 表示未知）。
- 默认池里写的是模型名而非密钥；换供应商时改 `config_json`（或上层配置）而不是改代码。
