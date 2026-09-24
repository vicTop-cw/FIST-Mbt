# Laya 集成部署报告（2026-09-24）

## 结果摘要
fist-mbt 新增**可选** MCP 工具 `laya_decide`：自动探测机器是否可用 laya，有则默认用其结构化决策（难度/领域/工具/敏感），无则静默降级，不影响现网。js 目标 build 0 errors，`moon test --target js` 135/135 全绿，端到端可用/降级两条路径实测通过。

## 资源消耗
（本次会话 token 未单独记账；模型首次 predict 触发 HF 下载约 712MB，缓存后即时。）

## 任务分配记录
- sidecar `scripts/laya_decide.py`：探测 + predict + 降级 JSON 输出（实现并实测）
- `laya_js.mbt` / `laya_native.mbt` / `server.mbt`：js node spawn、native 桩、`laya_decide` 工具注册
- `docs/laya.md` + `BACKLOG.md` F009

## 遗留风险
- native 目标 `laya_decide` 返回 `available:false`（桩），真实决策需在 node 下跑 server。
- 每次调用实时 probe 约 +150ms 开销（换来实时准确）。
- `Json::bool` 序列化在个别分支会省略小数位（如 `is_sensitive.noul: 0`），无碍语义。

## 后续建议
- 可把 `difficulty.score`/`domain` 接入 `task_plan_deep` 的 `split_n` 与 `spec.laws` 生成，作为更强档位；当前保持独立只读。
- 如需隔离数据，建议在隔离目录启动 server 测试。

## 超额内容
- 新增独立工具而非侵入既有生命周期，符合"可选工具"路线。
- 降级 path 设计为返回 `{available:false, fallback}` 而非报错，保证故障不阻断现网。

## 来源
- 评估文档：`C:\Users\victo\.openclaw\workspace\laya_fist-mbt集成评估_20260924-1130.md`
- 使用文档：`docs/laya.md`；主文档 `AGENTS.md` 金条规则

*（内容由AI生成，仅供参考）*