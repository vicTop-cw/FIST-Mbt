# Round 120 报告 · 发布版校验 + 测试数同步 1058 + MCP 协议 BUG-163

- **日期**：2026-10-15
- **任务**：校验用户安装的发布版 `C:\Users\victo\AppData\Local\Fist-Mbt\fist-mbt.js` 与当前源码是否一致、能否用；并落地本轮发现
- **HEAD 基线**：`5d8fc59`（并发 agent 仍在提交中，本轮只提交我的文件）

## 结果摘要

| 项 | 结果 |
|---|---|
| **发布版 ↔ dist 一致性** | ✅ 字节级一致（sha256 `C6FFF7177B71...`，均 3482040 字节） |
| **版本 0.3.8 三处一致** | ✅ `dist` == `src/server/server.mbt` == `moon.mod`（BUG-114 未出现） |
| **`moon test --target js`** | ✅ **1058/1058**（瞬态红来自并发 agent 的 `stdio_js.mbt` 编辑，已自愈） |
| **`output_validate`（R119 交付物）** | ✅ verdict=pass，`evidence_layer=l4-pass` |
| **`check_test_sync --total 1058`** | ✅ PASS（同步 9 份现状文档 38 处 1051→1058） |
| **`check_badge`** | ✅ PASS（README `tests-1058%2F1058` == 实测） |
| **`moon fmt --check`** | ⚠️ 红（rc=-1），**失败面全在并发 agent 的未格式化 `.mbt`**，非我的 `.md` |
| **BUG-163 新上报** | 🔴 **HIGH**：MCP server 只支持非标准协议 `2026-07-28`，标准客户端不可连接 |

## 核心发现

### 1. BUG-163（新，HIGH）：MCP 协议版本不兼容主流客户端

- 发布版/当前 `fist serve` 的 MCP 握手**只接受 `2026-07-28`**。
- 标准版本 `2025-06-18` 与 `2024-11-05` 全部被 `-32022 Unsupported protocol version` 拒绝，回执带 `{"supported":["2026-07-28"],"requested":"<ver>"}`。
- 连 `initialize` 方法在标准版本下也被拒（`Method not found: initialize`）——服务端把整个方法名当成协议相关。
- 根因：`src/server/stdio_js.mbt:54` `const MCP_PROTOCOL_VERSION : String = "2026-07-28"`（L49 `// BUG-161: MCP 2026-07-28 兼容层`），是并发 agent 的 WIP。
- **影响**：Claude Desktop / Cursor / VS Code / Cline 等标准 MCP 客户端**无法连接**。只有被定制成发 `2026-07-28` 的客户端（如本 DSH harness）能连。`mcp_config_scaffold` 生成配置不含协议版本字段，目标项目的标准客户端同样失败。
- **修复方向**（交并发 agent / owner 裁决）：
  1. `initialize` 支持 `supportedVersions` 协商，至少包含标准 `2025-06-18`，按客户端 `protocolVersion` 选择；
  2. 或保留 `2026-07-28` 为默认，但接受标准版本并回 `protocolVersion: <客户端给的>`；
  3. 至少文档（`README`/`AGENTS.md`/`docs/`）显式声明「speak 2026-07-28，需配套客户端」。

### 2. 发布版不落后于 dist（对 BUG-155 有影响）

- 两者 sha256 相同 ⇒ **dist stale 则发布版 stale，dist fresh 则发布版 fresh**。
- 版本 0.3.8 三处一致、`tools_sync` 守卫 PASS、`output_validate` 对 R119 交付 L4 通过 ⇒ **dist 未被并发 agent 的 src 改动拖成 stale**。
- BUG-155（dist 工具数 148 vs 166）更可能是 BUG-163 协议差异在工具枚举侧的投影，或 dist 尚未含并发 agent 最新 src 工具（未 rebuild）。终态仍需在标准客户端里看 `tools/list` 实际数量。

### 3. 测试数同步 1051 → 1058（R119 的 +7 测试遗留）

- R119 我加了 7 条边界测试把总数推到 1058，但现状文档还写 1051，`check_test_sync` FAIL。
- 已同步 9 份文档、38 处：`ARCHITECTURE.md`、`README.mbt.md`、`README.md`、`README_EN.md`、`AGENTS.md`、`scripts/scoring_rubric.md`、`docs/deliverable.md`、`docs/agent-map.md`、`docs/SHIP-PLAN-BLACKBOX-v2.md`。
- AGENTS.md 的 1051 行未被并发 agent 的 5 行 WIP 触及，安全单独更新；日期 2026-10-14 → 2026-10-15（1058 是今日实测）。
- `check_test_sync --total 1058` = PASS（20 条一致 + must-carry 5 + exempt 19）。

## 资源消耗

- `moon test --target js` × 2（一发瞬态红、一发 1058/1058 绿）
- `moon fmt --check` × 2
- MCP 协议探测脚本 × 5（`temp/mcp_probe*.py`，用 `FIST_DB_PATH=E:/temp/fist-db-check.db` 不污染仓库根）
- 8 份文档批量 1051→1058

## 任务分配记录

| 子任务 | 执行者 | 结果 |
|---|---|---|
| 发布版 sha256 与 dist 比对 | 我 | ✅ 一致 |
| 版本三处一致性（dist/src/moon.mod） | 我 | ✅ 0.3.8 一致 |
| MCP 协议三分支探测 | 我 | ✅ 确认只有 `2026-07-28` |
| 9 份现状文档 1051→1058 | 我 | ✅ 38 处 |
| `output_validate` R119 交付物 | 我 | ✅ pass |

## 遗留风险

1. **BUG-163（HIGH）**：MCP 协议不兼容主流客户端。属并发 agent 的 `stdio_js.mbt` WIP 区，**不能由我修**。终态需 owner 或并发 agent 落 `supportedVersions` 协商。
2. **BUG-162（OPEN）**：`issue_scan` 全 `src/` 超 30s 预算。仍在并发 agent 的 `src/server/issue_scan.mbt` 区。
3. **BUG-155**：dist 工具数 148 vs 166。本轮证实 dist 与发布版一致、版本一致、`tools_sync` PASS，故 dist 不 stale；但协议差异可能影响工具枚举。仍待用户裁决。
4. **`moon fmt --check` 红**：并发 agent 的 4 个 `.mbt` 未格式化（`cmd/cli/main.mbt`、`cmd/cli/subcmd.mbt`、`src/server/stdio_js.mbt`、`src/server/board_ascii.mbt`）。非本轮改动，不影响我提交 `.md`。
5. **AGENTS.md**：本轮已改 1051→1058 + 日期修正，但并发 agent 仍有 5 行 WIP 在同一文件，提交时可能合并/冲突，需留意。

## 后续建议

1. **给 owner 的最关键一条**：发布版的 `fist serve` 在主流 MCP 客户端连不上。这是 cl1（MCP 工具存在）在第三方侧的暗礁，优先级应高于其余打磨项。
2. 若走「接受标准版本」路线，`mcp_config_scaffold` 也应考虑显式写协议版本字段，让目标项目生成配置时知道服务端 speak 什么。
3. 等并发 agent 收口后，`dist/fist-mbt.js` 需 rebuild 一次（含最新 src 工具），再核 BUG-155 的 148 vs 166。

## 来源

- 本会话 Round 119/120 工具调用记录
- `src/server/stdio_js.mbt:49,54`
- `memory/bugs.md` BUG-163 条目
- `memory/2026-10-15.md` Round 120 段
