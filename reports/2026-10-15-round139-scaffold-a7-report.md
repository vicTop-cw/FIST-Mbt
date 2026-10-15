# Round 139 报告 · mcp_config_scaffold 实测 + A7 补充

- 日期：2026-10-15
- 提交：`scripts/mcp_compat_shim.js`（+A7 20 行）、`scripts/README.md`（+A4/A5/A7 记录）
- 角色：运维验证轮 + shim 改进轮

## 结果摘要

### 1. mcp_config_scaffold 实测

传 shim 接入偏好：

```json
{
  "serverName":"fist-mbt","command":"node",
  "args":[".../mcp_compat_shim.js","--server","node",".../dist/fist-mbt.js","serve"],
  "cwd":".","toolCallTimeoutMs":60000,"failOnStartupError":false,
  "reconnect":{"intervalMs":500,"maxRetries":30,"delayMs":30000},
  "env":{"FIST_DB_PATH":".../fist-mbt.db"}
}
```

返回：

```
json          = 合法 fist.mcp.json（自动注入 FIST_PROJECT_DIR:"."）
unknown_keys  = []
notes         = ["配置里只写环境变量名占位（如 $FIST_GITHUB_TOKEN），真值走 server 进程环境变量",
                 "未知字段已忽略并回显到 unknown_keys（供 HTML 页调试）"]
```

**关键发现**：脚手架正确（a）白名单化 env（`FIST_DB_PATH` + 自动注入 `FIST_PROJECT_DIR`），（b）凭据硬门拒绝 api_key/token/secret 形状的表单，（c）未知字段回显到 `unknown_keys` 供调试。

### 2. 实现 A7

shim 头注释的 `.mcp.json` 示例改用脚手架生成版（含 `reconnect`/`toolCallTimeoutMs` 标准键），并加 `mcp_config_scaffold` 使用说明（含凭据硬门说明）。

### 3. README 记录 A4/A5/A7

- **A4 请求超时**（R137）：默认 30s，`FIST_SHIM_TIMEOUT_MS` 覆盖，`t.unref?.()` 不阻止退出。
- **A5 已正确**：`_meta` 只对有 id 请求注入。
- **A7 示例升级**（本轮）：shim 头注释示例改用脚手架生成版。

### 4. 回归

28 检查全 PASS（10 握手 × 2 协议 + 5 健壮性 + 3 边界）✓

## 资源消耗

| 项 | 值 |
|---|---|
| 工具调用 | mcp_config_scaffold × 1、read × 1、grep × 1、edit × 2、pwsh × 2 |
| 提交 | 1 个（+A7 20 行 + README 记录） |
| 触碰并发 WIP | 无 |

## 任务分配记录

- 本会话 Round 139 完成：mcp_config_scaffold 实测 + A7 补充。

## 遗留风险

1. **内建 compat 的 protocolVersion 回写缺陷**——已归档为 DGM 资产。
2. **BUG-155 假绿持续**——HEAD 仍含 stale dist。

## 后续建议

1. shim A1-A7 全部实现/核对完毕，可视为达到"可直接交付给标准 MCP 客户端"质量。
2. 用 `mcp_config_scaffold` 生成的 `.mcp.json` 可作为 `docs/` 下的参考模板。

## 超额内容

- 无（严格限于 mcp_config_scaffold + A7）。

## 来源

- `mcp_config_scaffold` → 合法 fist.mcp.json，unknown_keys=[]，自动注入 FIST_PROJECT_DIR
- `scripts/mcp_compat_shim.js`（+A7 20 行）
- `scripts/README.md`（+A4/A5/A7 记录）
