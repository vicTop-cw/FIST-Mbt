# fist-gateway 黑盒判据索引

本目录下 fist-gateway 面的黑盒判据脚本一览。全部为实弹：
自建临时 db + 临时网关实例 + 测试自生成密钥（不触碰任何真实服务凭据）。
一键串跑：`python scripts/blackbox/e2e_agent_suite.py`（退出码只对硬 FAIL 负责）；
实弹前快速验形状：`python scripts/blackbox/e2e_agent_suite.py --selftest`
（只跑各成员形状自证，不起网关）。

| 脚本 | 判据 | 覆盖面 |
| --- | --- | --- |
| e2e_agent_shim_live.py | B1-B6 | /v1/chat/completions shim：认证门 / 缺 user 400 / OpenAI 形状回执 / 任务真落库 / 审计行 / id 序列 |
| e2e_agent_s3_header.py | S0-S4 | X-S3-Challenge/X-S3-Signature 头注入：ACL 授权链 / 认证门 / 控制臂 / fail-closed 验签分支 / setdefault 语义 |
| e2e_agent_models_status.py | M1-M2, R1-R3, X1 | /v1/models 发现面 + GET /v1/tasks/<id> 回执面：认证门 / 形状 / 404 / 发布-查进度配对 |
| e2e_agent_task_wait.py | W1-W4 | ?wait=1 长轮询：无 wait 即返 / 非终态轮询（W2）/ 404 快速返回 / 终态即返（W4） |
| e2e_agent_task_ns_pairing.py | — | 跨 ns 读池错位缺陷回归锁（见下） |
| e2e_agent_gateway.py | A1-A8 | 常驻网关生命周期：health / MCP 转发 / 认证门 / 心跳 / draining / lan 绑定 / watchdog / 模型自动路由 |

## 判据语义约定

- **PASS**：契约成立。
- **SKIP**：前置条件不满足（如共享池被 execute-cron 守护毫秒级抢跑，非终态观测不到），
  留因说明，不算失败。
- **KNOWN-RED**：缺陷回归锁。缺陷未修时输出复现证据并 exit 0（便于巡检跟踪），
  修后自动转严格断言（不配对即 FAIL）。

## 已知缺陷（截至 2026-11-22）

**GET /v1/tasks/<id> 跨 ns 读池错位**（T0r10）：✅ 已修复（fc4ddc24d 入库）。
shim 发布落本服务 ns 池，网关回执面 get 调用现已透传发布 ns
（`namespace=gateway.service_id`），回归锁 e2e_agent_task_ns_pairing.py 转严格
PASS；wait 长轮询 W2 亦转确定性观测（26s 轮询至超时回当前态）。
