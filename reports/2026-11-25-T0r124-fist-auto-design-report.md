# T0r124「一：可行性与设计定案（含 Trae 接入形态验证）」交付报告

| 项 | 值 |
|---|---|
| 任务 | T0r124 · autoplan ns · depth=3 |
| 执行身份 | atomcode |
| 约束 | 只读盘点 / 最小改动；产出物写明路径 |
| 结果 | **已完成**（verify: human_steward，2026-11-25T12:37:07Z） |
| 计划真源 | `fist-mbt/plan/active/2026-11-25-fist-auto-model.md`（裁决项 A1–A4） |

## 结果摘要

可行性**成立**，且不新造协议：现有构件够用，缺的只有两段实现——**同步真补全**与**跨协议轮转**。

两条验收问题的直接回答（均实测，非推断）：

1. **Trae 填这个地址后是否真的出内容** → **能**，硬条件一条：`base_url` 必须**整条填**
   `http://127.0.0.1:<port>/v1/chat/completions`（填基址会双拼 `/v1/v1/...` ⇒ 404）。
   实测探针 A 格 + Trae 本地状态库字段双重取证。
2. **额度耗尽跳过后是否真落到下一个可用服务** → **能**，软性轮转 + 失败顺延：
   实测首选 401 → 下一候选 200 且返回真内容，尝试次数受上限约束。

**一处必须回报的漂移（新发现）**：计划 A1 定的端口 **18651 已被 OFM-1 占用**
（实测 LISTENING；`model-router-default.json` 记其 endpoint `http://127.0.0.1:18651/mcp`）。
⇒ A1 的「独立新端点 + 复用网关骨架」判断不变，但**端口号须改为 18654**（实测空档起点）。

## 证据（实测读数）

一次性探针 `temp/t0r124_probe.py`（gitignore 内，不入提交面），合成候选网关，
不碰 Trae 配置、不动任何生产服务：

```
[PASS] A.full_endpoint_19711 :: HTTP 200            ← 整条端点可用
[PASS] A.double_join_is_404_19711 :: HTTP 404       ← 双拼形态被否证
[PASS] B.failover_produces_content :: primary(exhausted)→HTTP 401; next(healthy)→HTTP 200
[PASS] B.skipped_primary_not_retried_forever :: attempts=2
[PASS] C.relay_reachable :: HTTP 200 elapsed 2.59s
[PASS] C.relay_real_content :: content head: '连通测试'
SUMMARY: 6 checks, 0 failed · rc=0
```

其它实测读数：

| 读数 | 值 |
|---|---|
| OFM relay `/v1/models` | HTTP 200，**607 个模型**（落盘 `temp/ofm_models_live.json`） |
| OFM relay 真补全 | HTTP 200，耗时 ~2.6–3.8s，回真实 content（`trae/glm-5.3-flash`） |
| 端口实况 | OPEN：18326(relay)/18640/18641/18643/18644/18645/18646/18649/18650/**18651(OFM-1)**/18652/18653；free：18654+ |
| `derive_service_ports()` | 实测推 **9 项**（含 svc-autoclaw:18647）；fallback 常量表仍列 6 项 |
| 注册表 `agent_service` | **10 行**；`svc-codeforce`(running) 与 `svc-agent`(stopped) 同在 18649 |

## 资源消耗

| 项 | 量 |
|---|---|
| 读取文件 | 9 份源码/配置/数据面 + 2 份既有报告 |
| 新建提交面文件 | 2（设计说明 296 行 + 本汇报） |
| 新增临时产物 | `temp/` 下 4 个（探针/模型清单/任务状态快照，gitignore 内） |
| 业务代码改动 | **0**（符合「只读盘点/最小改动」约束） |
| 提交 | `91a3cd03c`（仅 1 文件，未带走他方 WIP） |
| MCP 调用 | get×4 / run_check×5 / submit×2 / verify×1 / tools/list×1 |

## 任务分配记录

单 agent（atomcode）自执行——本任务本质是只读盘点 + 一份文档，无可再分的独立子任务，
未派子代理（避免多一轮模型开销而无产出增益）。

## 遗留风险

| # | 风险 | 处置 |
|---|---|---|
| R1 | A1 端口号漂移（18651 已占） | 建议改 18654；**待指挥官确认** |
| R2 | `FIST_OFM_KEY` env 与 relay key **不是同一把**（拿 env 那把打 18326 得 401） | 工作项二须显式定源 `~/.dsh/our-free-model/settings.json` 的 `chanGateway.relay.key` |
| R3 | relay 模型数随上游增长（计划记 152 vs 实测 607） | 工作项三按次探活刷新，不抄数 |
| R4 | 注册表重复身份 + fallback 常量表滞后于真源 | 工作项三核对 |
| R5 | relay 有恒回 500 的 bug 史（现已恢复 200） | 轮转须把它当普通候选，不可硬编码为唯一后端 |
| R6 | Trae GUI 端到端未验（本单只证到协议形态与字段） | 归工作项七 |

## 后续建议

1. 工作项二按本报告 §2.3 归一化形状落地真补全 + 轮转，端口取 18654。
2. 凭据引用口径在实现里显式化（`credential_ref`），不要把 relay key 写死进代码或文档。
3. 工作项三逐个核实其余候选（当前唯一已证 = relay 18326），未核实前不得放进补全池（A2）。
4. 工作项七补 Trae GUI 端到端实配这一格，并复核「Trae 是否会额外 GET `/models`」。

## 超额内容

无超出任务要求的功能改动。额外产出：一次性的三格实测探针与 relay 模型清单快照
（均在 `temp/`，供工作项二三复跑取证，不污染提交面）。

## 来源

- 设计说明全文：`reports/2026-11-25-fist-auto-design-report.md`
- 计划：`fist-mbt/plan/active/2026-11-25-fist-auto-model.md`
- 盘点对象：`scripts/fist_gateway.py`、`scripts/gateway_guardian.py`、`scripts/check_ofm_endpoint.py`、
  `.fist-mbt/data/agent-services.db`、`.fist-mbt/data/model-router-default.json`、
  `src/router/{model_router,model_router_ops,ofm_chat,ofm_response}.mbt`、`src/executor/cli_argv.mbt`
- Trae 取证：`%APPDATA%/Trae CN/User/globalStorage/state.vscdb`
- relay 凭据真源：`~/.dsh/our-free-model/settings.json`（值不回显）
- 接力棒回执：submit（状态→待验收）→ run_check r4 passed → verify（已完成）
