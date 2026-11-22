# P1 阶段报告：fist-web-agent 核心服务

- 日期：2026-11-22
- 命名空间：marvis-webagent
- 任务：T0.2 / T0.2.1 / T0.2.2
- 状态：已完成

## 交付物

1. `services/fist-web-agent/main.go`（Go 单二进制核心服务，纯标准库）
2. `services/fist-web-agent/fist-web-agent-linux-amd64`（linux 静态交叉编译产物 8.44MB）

## 能力

- `GET /health`：service_id / alive / listen_addr / pid / uptime
- `POST /v1/chat/completions`：OpenAI 兼容请求解析与响应形状（回显模式）
- `POST /mcp`：JSON-RPC 2.0（initialize / tools/list / tools/call）
- `GET /api-key`：回显 key
- 鉴权：X-API-Key / Authorization Bearer 双通道，sha256 常量时间比较
- 32 位随机 key（`--api-key` 显式注入 / `--auth-print` 打印一次）
- 心跳：heartbeat.json + svc.pid 写入 state-dir（默认 /tmp/fist-web-agent）
- 零第三方依赖，`CGO_ENABLED=0` 静态编译

## 验证记录

- Windows 本地启动：API-KEY 打印正常，pid 44056，listen 127.0.0.1:18646
- /health：200 `{"alive":true,...,"service_id":"fist-web-agent"}`
- chat/completions：无 key 401；X-API-Key 200 OpenAI 兼容形状
- mcp initialize（Bearer）：200 protocolVersion 2026-07-28
- mcp tools/list：200 列出 health/echo
- mcp tools/call echo：200 `ping`
- heartbeat.json 写入正常
- linux-amd64 交叉编译：`CGO_ENABLED=0 GOOS=linux GOARCH=amd64` 成功（8.44MB）
- 打包集成：fist-web-agent-v0.1.0.fist.md 生成成功（gzip 4.63MB，MD 6.18MB，预算 8MB 内）

## 待办

- P2（T0.3）：三档可见性——lan 防火墙模板 + global cloudflared quick tunnel 实测
