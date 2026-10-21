# Round 124 报告 · 用发布版 fist-mbt 自驱闭环审出并实施 shim 改进

- 日期：2026-10-15
- 提交：`9705536`（`scripts/mcp_compat_shim.js` +22 -3）
- 角色：自驱验证轮（第 4 轮，未触碰 `src/`，与并发 agent 零冲突）

## 结果摘要

**用发布版 fist-mbt 跑完整自驱闭环**，审出并实施 3 个 shim 改进点。

### 自驱闭环（`temp/shim-selfdrive` + `shim-review` 命名空间）

```
selfdrive_init           ✓ memory 四件套就绪
selfdrive_append         ✓ 思考流水
selfdrive_review_tick    → idle（未到审视轮次，报告前置）
publish_parallel         ✓ 创建 T0r609
claim                    ✓ 认领
plan (split_n=2)         ✓ 拆成 T0r609.1 / T0r609.2
execute / submit / verify  × 2   两个子任务全绿
verify（根自动上卷）      ✓ T0r609 已完成
archive                  ✓ 已归档
```

### 审出的改进点（T0r609.1 / T0r609.2 交付）

| # | 改进 | 优先级 | 处置 |
|---|---|---|---|
| A1 | `logging/setLevel` + `completion/complete` stub（server 返回 -32601） | 中 | **已实施**：shim 拦截回 `{}` / `{completion:{values:[]}}` |
| A2 | 子进程 stderr 透传 | 高 | **无需改**——审查时误以为 DEVNULL，实为探针侧设置；shim 的 `stdio: ['pipe','pipe','inherit']` 已直通 |
| A3 | 子进程崩溃退出处理 | 高 | **已修**：`code ?? 0` 在 signal 终止时误报成功；现改 `signal → exit 1`、`code null → exit 1` |

### 回归实测（发布版 dist / v0.3.8）

| 标准方法 | 结果 |
|---|---|
| `initialize` | ✅ 握手成功 |
| `ping` | ✅ `{}` |
| `logging/setLevel` | ✅ `{}`（A1 stub，原来 -32601） |
| `completion/complete` | ✅ `{completion:{values:[]}}`（A1 stub，原来 -32601） |
| `tools/list` | ✅ |
| `prompts/list` | ✅ |

## 资源消耗

| 项 | 值 |
|---|---|
| 工具调用 | ~20 次（selfdrive×3、publish/claim/plan/execute/submit/verify/archive×10、pwsh×2、read/edit×4） |
| 提交 | 1 个（`9705536`） |
| 触碰并发 WIP | 无（自驱隔离在 temp/ + shim-review ns） |

## 任务分配记录

- 本会话 Round 124 **通过发布版 fist-mbt 完整走通**：`publish_parallel` → `plan` → `claim` → `execute` → `submit` → `verify` → `archive`。
- 命名空间 `shim-review` 与项目 `temp/shim-selfdrive`，不碰默认 ns / 并发 WIP。

## 遗留风险

1. A1 stub 返回空——客户端若期待 server 实际发日志通知仍收不到（但 server 本来不支持，无实际损失）。
2. 并发 agent 的 compat 层（`stdio_js.mbt`）仍未提交——BUG-161/163 的内建修复待其 commit + `moon publish`。
3. BUG-155（dist 148 vs src 166 工具）待工具收口后重建 dist。
4. A4（请求超时）/ A5-A7（幂等握手、README 示例等）本轮未实施——可留后续。

## 后续建议

1. **并发 agent 提交 compat 层后**，用 `temp/shim_probe5.py` / `temp/shim_probe6.py` 改指内建 build 再验一遍——这就是 BUG-163 的验收判据。
2. **A4 请求超时**：若实际使用中遇到 server 长时间不响应（如大任务），再补 `-32000 timeout` 分支；本轮不预置。
3. **README 用法示例**（A7）：可在 `scripts/README.md` 补一段 `.mcp.json` 配置示例，方便用户复制。

## 超额内容

- 无超额（严格限于 shim A1/A3 改进 + 自驱闭环演示）。

## 来源

- 发布版 `dist/fist-mbt.js`（v0.3.8）
- 任务库 `temp/shim-selfdrive`（T0r609 完整闭环记录）
- 探针 `temp/shim_probe6.py`
- 记忆：`memory/2026-10-15.md`（Round 124 条目）

## 追加：独立验证并发 agent 的 BUG-162 修复

在 Round 124 报告已写完后（12:21 左右），并发 agent 提交了 `7759781 perf(issue_scan): <30s budget (BUG-18)`，并把 BUG-162 标 FIXED。

**独立验证结果**：
- `moon test --target js` → **`Total tests: 1058, passed: 1058, failed: 0`**（复现并发 agent 声称的 1058/1058）
- MCP 侧 `issue_scan` **仍超时**——MCP server 跑的是发布版 dist（旧代码），不含 src 修复；需重发布才生效

**结论**：BUG-162 的 src 侧修复已由我独立确认；发布版生效需等 `moon publish`（依赖并发 agent 的工具收口）。
