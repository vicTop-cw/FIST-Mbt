# Round 125 报告 · BUG-155 假绿实锤 + shim A7 用法示例

- 日期：2026-10-15
- 提交：`mcp_compat_shim.js` A7 完整 `.mcp.json` 示例 + `scripts/README.md` 登记改进说明
- 角色：运维验证轮（未触碰并发 WIP）

## 结果摘要

### BUG-155 假绿实锤

`memory/bugs.md` 标 **BUG-155 FIXED**，FIXED 小记声称 `git rm dist/fist-mbt.js`（"遗留打包产物手提交进 HEAD"）。**但实证推翻**：

| 判据 | 结果 | 结论 |
|---|---|---|
| `git show HEAD:dist/fist-mbt.js` | 文件存在 | HEAD 未删 |
| `git ls-files dist/fist-mbt.js` | 文件在 index | 仍被跟踪 |
| `node dist/fist-mbt.js help` | `148 MCP tools / v0.3.8` | 仍 stale |
| `git log -- dist/fist-mbt.js` | 无删除 commit | `git rm` 从未落 commit |

**FIXED 小记是虚假的**——`git rm` 从未真正提交，stale dist 仍在 HEAD，发布版仍报 148 工具。这是 BUG-9 类「账本说修好了但实际没修」的又一例。

### shim A7：完整 `.mcp.json` 用法示例

内嵌 shim 文件头 + `scripts/README.md` 登记，Claude Desktop 格式可直接复制：

```json
{
  "mcpServers": {
    "fist-mbt": {
      "command": "node",
      "args": ["<repo>/scripts/mcp_compat_shim.js", "--server", "node", "<repo>/dist/fist-mbt.js", "serve"],
      "env": { "FIST_DB_PATH": "<你的库路径>" }
    }
  }
}
```

### 回归验证

- `node --check scripts/mcp_compat_shim.js` → 语法 OK
- 快速探针 `temp/shim_probe7.py` → `initialize` / `ping` 仍通过

## 资源消耗

| 项 | 值 |
|---|---|
| 工具调用 | pwsh × 3、grep × 2、edit × 2、node --check × 1、python × 1 |
| 提交 | 1 个（shim A7 + README 登记） |
| 触碰并发 WIP | 无（只读 bugs.md，未通过 report_bug 写入） |

## 任务分配记录

- 本会话 Round 125 完成：BUG-155 假绿实证 + shim A7 用法示例。
- 未发布/归档 FIST 任务（避免与并发 WIP 冲突）。

## 遗留风险

1. **BUG-155 FIXED 假绿**——stale dist 仍在 HEAD，发布版仍报 148 工具。需并发 agent 真正 `git rm` 或重建 dist。
2. **BUG-161/163 仍 OPEN**——并发 agent 的 `stdio_js.mbt` compat 层未提交，我的 shim 是唯一可用外部缓解。
3. **并发 agent 50+ WIP 未提交**——一旦提交可能引入回归，需再次 `moon test` 复核。

## 后续建议

1. **并发 agent 应**：真正 `git rm dist/fist-mbt.js` 并提交，或重建 dist 从当前 src；BUG-155 的 FIXED 才成立。
2. **并发 agent 提交 compat 层后**：用 `temp/shim_probe5.py` / `temp/shim_probe6.py` 改指内建 build 再验——这是 BUG-163 的验收判据。
3. **我下次**：并发 agent 提交后跑 `moon test --target js` + `check_plugin_sync.py` + `check_publish_payload.py` 三重复核。

## 超额内容

- 无（严格限于 shim A7 + BUG-155 假绿观察）。

## 来源

- 发布版 `dist/fist-mbt.js`（v0.3.8 / 148 工具，stale）
- `memory/bugs.md`（BUG-155 FIXED 假绿）
- 探针 `temp/shim_probe7.py`
