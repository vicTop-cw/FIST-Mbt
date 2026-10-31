# 2026-10-31 · OFM 免费路由全链路验证（ns=ofm-route-r1 · T0.2.1 已完成）

## 结果摘要
OFM 免费路由全链路（端点→池播种→路由决策→真跑→记账/归因）验证通过，端点为 **127.0.0.1:18326**（chanGateway relay，Bearer key 鉴权）。

## 实证记录（L4）

| 环节 | 命令/动作 | 读数 |
|---|---|---|
| 端点探活 | `GET :18326/v1/models`（带 relay key） | HTTP 200，**152 个模型**（deepseek-official / workbuddy / trae / qoder / our-free-model / minimax / zcode / raccoon / loomy / lobsterai） |
| 旧端点 18899 | curl + netstat | 未监听；settings.forward.enabled=true 但服务未起 |
| 池播种+决策 | `model_route(config_json=…)` 直连 JSON-RPC（网关 auto_convert 把 JSON 文本强转 object，schema 只认 string——**网关已知局限**） | 选中 `our-free-model/glm-5.3-flash-free`，free 有容量，5h 窗口盖章 |
| 真跑（空 model） | `executor_run(executor=ofm)` | 路由记账 `recorded(ling-3.1-flash-free)` 但 HTTP 400 `model must use provider/model format` → `failure_kind=BAD_REQUEST` |
| 真跑（显式 model） | 同上 + `--model` | `trae/glm-5.3-flash`、`deepseek-official/deepseek-flash` 均 **HTTP 200 真正文**；显式 model 按设计 `not_routed` 不代记账 |
| 失败归因 | `our-free-model/deepseek-v4.1-flash-free` | HTTP 502 `UPSTREAM_DOWN`：上游要求本地 **Bun**（harness.log 每 15min 刷同一 warn，`OUR_FREE_MODEL_FREE_TRANSPORT=node` 可回退） |

## 三个真发现（后续轮落地）
1. **默认池 ↔ relay 命名不兼容**：`executor_run(executor=ofm, model 空)` 走默认池，池名（ling-3.1-flash-free 等）缺 `provider/` 前缀，被 relay 拒 400。出路：executor_run 接 config 透传，或默认池改 provider/model 命名。**这解释了为什么历史上 OFM 通道"能启动一用就死"。**
2. **our-free-model/* lane 依赖 Bun**：本机无 bun。出路：装 Bun 或给 DSH harness 进程设 `OUR_FREE_MODEL_FREE_TRANSPORT=node`（需重启 DSH，用户侧动作）。
3. **fist.py 网关 auto_convert 限制**：值以 `{` 开头即强转 object，schema 只要 string 的参数（config_json）无法经网关传——直连 JSON-RPC 绕过。属网关缺陷候选（可加 `--raw` 旗标），记待办。

## 遗留风险 / 后续建议
- 18899 转发服务未起：DSH 插件面板里转发开关需人工确认（或等 Bun/transport 修复后自然可用）。
- 18326 的 key 已轮换（settings.json 里那把失效），以用户提供的现行 key 为准——key 只进进程 env，不入任何文件（check_model_auth_no_key 纪律）。
- routing 状态盘 `./.fist-mbt/data/model-router-ofm-route-r1.json` 仅播种过一次；executor_run 走默认池是独立行为，两者不互读。

## 来源
- FIST 闭环：ns `ofm-route-r1` T0.2.1 已完成（claim→execute→submit→verify 全过）
- 证据链：temp/ofm_models.json（152 模型清单）、%APPDATA%/dsh-desktop/logs/harness.log（Bun warn）
