# Round 131 报告 · shim 测试补全提示面 prompts/get

- 日期：2026-10-15
- 提交：`scripts/test_shim_handshake.py`（+prompts/get）
- 角色：运维验证轮

## 结果摘要

### 1. shim 测试覆盖标准客户端完整 MCP 面

新增 `prompts/get`，测试从 23 检查升到 **25 检查**：

| 类别 | 方法 | 2025-06-18 | 2024-11-05 |
|---|---|---|---|
| 握手 | initialize | PASS | PASS |
| 通知 | notifications/initialized | 透传 | 透传 |
| 工具 | tools/list | PASS (166) | PASS (166) |
| 工具 | tools/call | PASS (真数据) | PASS (真数据) |
| 资源 | resources/list | PASS (3) | PASS (3) |
| 资源 | resources/read | PASS (fist://map → 2261 字符) | PASS |
| 提示 | prompts/list | PASS (2) | PASS (2) |
| 提示 | **prompts/get** | **PASS (fist:verify → 1 msg)** | **PASS** |
| 可选 | ping | PASS | PASS |
| 可选 | logging/setLevel | PASS | PASS |
| 可选 | completion/complete | PASS | PASS |
| 健壮性 | 畸形输入 ×5 | PASS | PASS |

### 2. server 原生支持 prompts/get

直连 `dist/fist-mbt.js serve` 验证：

- `prompts/get(fist:verify)` → 返回 `messages[]`，1 条 role=user ✓

**不需要 shim stub**——shim 只需补 `_meta` 透传即可。

### 3. 标准客户端日常用法全覆盖

Claude Desktop / VS Code / cursor 的完整启动序列：
1. `initialize` → shim 改写 `server/discover` + 回写客户端请求的 protocolVersion
2. `notifications/initialized` → 透传
3. `tools/list` → 166 工具
4. `tools/call` → 真调用
5. `resources/list` → 3 资源
6. `resources/read` → 真读内容
7. `prompts/list` → 2 提示
8. `prompts/get` → 真取提示
9. `ping` / `logging/setLevel` / `completion/complete` → shim stub

**shim 全支持，25 检查固化** ✓

## 资源消耗

| 项 | 值 |
|---|---|
| 工具调用 | read × 1、edit × 1、pwsh × 3、debug probe × 1 |
| 提交 | 1 个（+prompts/get） |
| 触碰并发 WIP | 无 |

## 任务分配记录

- 本会话 Round 131 完成：shim 测试补全提示面，标准客户端完整 MCP 面全覆盖。

## 遗留风险

1. **内建 compat 的 protocolVersion 回写缺陷**（R128 核心发现）——提交前须修。
2. **内建 compat 丢弃通知**（差异但当前无害）。
3. **BUG-155 假绿持续**——HEAD 仍含 stale dist。
4. **BUG-161/163 内建修复未提交**。

## 后续建议

1. 并发 agent 提交 compat 层后，用 `python scripts/test_shim_handshake.py`（25 检查）与内建 compat 双轨比对。
2. 若内建 compat 的 `notifications/initialized` 丢弃行为要改，需加"通知透传"逻辑。

## 超额内容

- 无（严格限于 shim 测试扩展）。

## 来源

- `scripts/test_shim_handshake.py`（扩展后 25 检查全 PASS）
- 直连 `dist/fist-mbt.js serve` 的 prompts/get 探针
