# Round 130 报告 · shim 测试扩展 resources/read + prompts/list

- 日期：2026-10-15
- 提交：`scripts/test_shim_handshake.py`（+resources/read + prompts/list）
- 角色：运维验证轮

## 结果摘要

### 1. shim 测试覆盖标准客户端完整用法

新增 2 个步骤，测试从 19 检查升到 **23 检查**：

| 步骤 | 2025-06-18 | 2024-11-05 |
|---|---|---|
| initialize | PASS | PASS |
| tools/list | PASS (166) | PASS (166) |
| tools/call | PASS (真数据) | PASS (真数据) |
| resources/list | PASS (3) | PASS (3) |
| **resources/read** | **PASS (fist://map → 2261 字符)** | **PASS** |
| **prompts/list** | **PASS (2)** | **PASS (2)** |
| ping | PASS | PASS |
| logging/setLevel | PASS | PASS |
| completion/complete | PASS | PASS |
| 畸形输入健壮性 ×5 | PASS | PASS |

### 2. server 原生支持 resources/read + prompts/list

直连 `dist/fist-mbt.js serve` 验证：

- `resources/read` → 返回 `contents[]`，`fist://map` 2261 字符 ✓
- `prompts/list` → 返回 2 个 prompt ✓

**不需要 shim stub**——shim 只需补 `_meta` 透传即可。

### 3. 标准客户端完整日常用法验证

Claude Desktop / VS Code / cursor 的典型启动序列：
1. `initialize` → shim 改写 `server/discover` + 回写客户端请求的 protocolVersion
2. `notifications/initialized` → 透传
3. `tools/list` → 166 工具
4. `tools/call` → 真调用
5. `resources/list` → 3 资源
6. `resources/read` → 真读内容
7. `prompts/list` → 2 提示
8. `ping` / `logging/setLevel` / `completion/complete` → shim stub

**shim 全支持** ✓

## 资源消耗

| 项 | 值 |
|---|---|
| 工具调用 | read × 1、edit × 2、pwsh × 3、debug probe × 1 |
| 提交 | 1 个（+resources/read + prompts/list） |
| 触碰并发 WIP | 无 |

## 任务分配记录

- 本会话 Round 130 完成：shim 测试覆盖标准客户端完整资源与提示面。

## 遗留风险

1. **内建 compat 的 protocolVersion 回写缺陷**（R128 核心发现）——提交前须修。
2. **内建 compat 丢弃通知**（差异但当前无害）。
3. **BUG-155 假绿持续**——HEAD 仍含 stale dist。
4. **BUG-161/163 内建修复未提交**。

## 后续建议

1. 并发 agent 提交 compat 层后，用 `python scripts/test_shim_handshake.py`（23 检查）与内建 compat 双轨比对。
2. 若内建 compat 的 `notifications/initialized` 丢弃行为要改，需加"通知透传"逻辑。

## 超额内容

- 无（严格限于 shim 测试扩展）。

## 来源

- `scripts/test_shim_handshake.py`（扩展后 23 检查全 PASS）
- 直连 `dist/fist-mbt.js serve` 的 resources/read + prompts/list 探针
