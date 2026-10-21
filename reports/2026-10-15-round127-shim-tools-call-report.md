# Round 127 报告 · shim 测试扩展到 tools/call + ATGC-old 试用

- 日期：2026-10-15
- 提交：`scripts/test_shim_handshake.py`（扩展 tools/call）
- 角色：运维验证轮

## 结果摘要

### 1. shim 测试扩展到 `tools/call`

原来只测 `tools/list`（能列不能调等于没用）。新增 `tools/call` 步骤真调用 `status_summary`，握手从 6 步升到 7 步：

| 步骤 | 2025-06-18 | 2024-11-05 |
|---|---|---|
| initialize | PASS | PASS |
| tools/list | PASS (166) | PASS (166) |
| **tools/call** | **PASS** (真数据) | **PASS** (真数据) |
| resources/list | PASS (3) | PASS (3) |
| ping | PASS | PASS |
| logging/setLevel | PASS | PASS |
| completion/complete | PASS | PASS |

### 2. 修的 check 逻辑（两次）

- **第一次**：`"result" in call_result` 反了——`call_result` 本身就是 `result` 对象，不该再查 `result` 键。
- **第二次**：`"isError" not in call_result` 因 MCP 标准响应**恒带 `isError:false` 键**（值不是 true）而误 FAIL。改为 `call_result.get("isError") is not True`。

debug 探针 `temp/shim_debug_call.py` 显示响应结构为：
```
{"jsonrpc":"2.0","id":21,"result":{"content":[{"type":"text","text":"{...data...}"}],"isError":false,"resultType":"complete","_meta":{...}}}
```

### 3. ATGC-old DNA VM 试用（发布版公开能力）

"善用发布版 fist-mbt 任何能力"——之前未用过的 ATGC-old：

- `atgc_old_compile("ATG GTA GCA GCT AAT TAA")`：
  - transcription: `AUGGUAGCAGCUAAUUAA`
  - ops: `START OVER SWAP SWAP JUMP_IF_NEG HALT`
  - mode: B, antisense: `TTAATTAGCTGCTACCAT`
- `atgc_old_run`（同一 DNA）：`err: OVER: 栈不足2`（预期栈下溢，错误处理正常）

DNA VM 工作正常。

## 资源消耗

| 项 | 值 |
|---|---|
| 工具调用 | atgc_old_compile × 1、atgc_old_run × 1、pwsh × 4、edit × 2、debug probe × 2 |
| 提交 | 1 个（扩展 tools/call） |
| 触碰并发 WIP | 无 |

## 任务分配记录

- 本会话 Round 127 完成：shim 测试扩展 tools/call + ATGC-old 试用。
- 未发布/归档 FIST 任务（避免与并发 WIP 冲突）。

## 遗留风险

1. **BUG-155 假绿持续**——HEAD 仍含 stale dist。
2. **BUG-161/163 内建修复未提交**——并发 agent 的 `stdio_js.mbt` compat 层仍未落地。
3. **并发 agent 66 文件 WIP**——`check_scripts_index` FAIL 的 5 个脚本等其收口。

## 后续建议

1. **BUG-163 验收判据更完备**：现在测试覆盖 initialize + tools/list + tools/call + resources/list + 3 个可选 stub——完整对应标准 MCP 客户端日常用法。
2. 并发 agent 提交 compat 层后，跑 `python scripts/test_shim_handshake.py` 与内建 compat 双轨比对。
3. 下次可试用 hat/marketplace/Omega 等其它未用过的发布版能力。

## 超额内容

- 无（严格限于 shim 测试扩展 + ATGC-old 试用）。

## 来源

- `scripts/test_shim_handshake.py`（扩展后全 PASS）
- `temp/shim_debug_call.py`（响应结构 debug）
- 发布版 `atgc_old_compile` / `atgc_old_run`
