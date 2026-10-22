# Round 126 报告 · shim 回归测试固化 + 工具数 166 实证

- 日期：2026-10-15
- 提交：`scripts/test_shim_handshake.py`（新增）+ `scripts/README.md`（登记 + 修正工具数）
- 角色：运维验证轮（未触碰并发 WIP）

## 结果摘要

### 1. 新增 shim 回归测试（BUG-163 验收判据）

把 `temp/shim_probe*.py` 临时探针提升为 repo 正式测试：

```
python scripts/test_shim_handshake.py
```

覆盖完整 Claude Desktop 握手序列，两档标准协议全过：

| 步骤 | 2025-06-18 | 2024-11-05 |
|---|---|---|
| initialize | PASS | PASS |
| tools/list | PASS (166) | PASS (166) |
| resources/list | PASS (3) | PASS (3) |
| ping | PASS | PASS |
| logging/setLevel | PASS | PASS |
| completion/complete | PASS | PASS |

**修测试 bug**：初版每次版本重建 `Client` 导致多 reader 线程抢同一 `proc.stdout`，`2024-11-05` 误 FAIL。改为复用单个 Client 后两档全过。debug 探针 `temp/shim_debug_pv.py` 独立验证了 shim 本身正常（两档都正确 echo protocolVersion）。

### 2. 工具数 166 实证（修正 Round 125 的 148 口径）

- `node dist/fist-mbt.js help` → **148**（help 文本 stale）
- `tools/list` 经 shim → **166**（MCP 工具层实际最新）

**结论**：dist 的 MCP 工具层与 src 一致（166），stale 的只是 help 命令文本。BUG-155 的 FIXED 小记声称 `git rm dist/fist-mbt.js`，但 `git show HEAD:dist/fist-mbt.js` 明确返回文件内容——**HEAD 仍含 stale dist，FIXED 假绿持续**。

### 3. MCP resources 首次读取

发布版 3 个 resources 全部通过 DSH harness 读通（`_meta` 正常返回）：

- `fist://map` → 项目结构地图（11 包 + 12 工具组 + 入口引导）
- `fist://principles` → 七条金条机器可读 JSON
- `fist://overview` → 任务库实时统计（2304 任务 / 9 状态）

这是发布版公开能力，之前未验证过。

## 资源消耗

| 项 | 值 |
|---|---|
| 工具调用 | read_mcp_resource × 3、list_mcp_resources × 1、pwsh × 4、edit × 2、write × 1、check_scripts_index × 1、python × 2 |
| 提交 | 1 个（e9d90ee） |
| 触碰并发 WIP | 无 |

## 任务分配记录

- 本会话 Round 126 完成：shim 回归测试固化 + 工具数实证 + resources 验证。
- 未发布/归档 FIST 任务（避免与并发 WIP 冲突）。

## 遗留风险

1. **BUG-155 假绿持续**——HEAD 仍含 stale dist/fist-mbt.js，help 文本仍报 148。需并发 agent 真正 `git rm` 或重建 dist。
2. **BUG-161/163 内建修复未提交**——并发 agent 的 `stdio_js.mbt` compat 层未落地，我的 shim + 新测试是唯一可复现的验收判据。
3. **并发 agent 60 文件 WIP 未提交**——`check_scripts_index` FAIL 的 5 个脚本（`bug161_smoke.py` 等）等其收口。

## 后续建议

1. **BUG-163 验收判据就绪**：并发 agent 提交 `stdio_js.mbt` 后，跑 `python scripts/test_shim_handshake.py` 与内建 compat 对同一判据双轨比对，能确认两条路线等价。
2. **BUG-155 需收口**：并发 agent 真正 `git rm dist/fist-mbt.js` 并提交，或重建 dist 从当前 src。
3. **我下次**：并发 agent 提交后跑 `moon test --target js` + 三守卫复核。

## 超额内容

- 无（严格限于 shim 回归测试固化 + 工具数实证 + resources 验证）。

## 来源

- 发布版 `dist/fist-mbt.js`（v0.3.8，MCP tools/list 返回 166）
- `scripts/test_shim_handshake.py`（新增，全 PASS）
- MCP resources `fist://map` / `fist://principles` / `fist://overview`
- `memory/bugs.md`（BUG-155 FIXED 假绿持续）
