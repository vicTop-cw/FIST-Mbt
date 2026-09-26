# SKILL: issue-scan — 规则驱动源码扫描（找目标项目潜问题）

> 形态：skill（本文档）｜MCP 工具 `issue_scan`｜CLI `python scripts/issue_scan.py <dir>`
> 用途：给 agent 一个「找目标项目潜在问题」的确定性抓手——不靠 LLM 自评、不依赖外部二进制，
> 内建 10 条 MoonBit 高危规则逐行匹配，命中由 agent 读上下文判真伪后进入修复闭环。

## 何时用

- 接到任务前：先用它扫目标目录，快速知道代码里有哪些高危模式（除零/越界/unwrap），
  写新代码时避开，改旧代码时优先处理高危命中。
- 打磨/收尾阶段：对 `src/` 全量扫描，把 findings 喂 `report_bug` 形成「扫描→上报→修复」闭环。
- 评审自证：`python scripts/issue_scan.py src` 一次输出可审计的证据（文件数/命中数/规则分布）。

## 怎么调

### MCP 形态（server 内）
```
tools/call issue_scan
  { "dir": "src", "max_findings": 100, "include_tests": false }
```
返回 `{ scanned_files, total_findings, include_tests, by_severity, by_rule, findings[] }`。
- `findings[]` 每项：`{ rule, severity, file, line, code }`。
- `dir` 必须相对路径（拒绝绝对/穿越/盘符，防路径逃逸）。
- `include_tests`（默认 `false`）只扫**产品代码**，跳过 `_test.mbt`/`_wbtest.mbt`
  （测试自带断言前置、命中多为安全场景，跳过后专注找产品代码真缺陷、降噪）。
  需要连测试文件一起看时传 `true`。

### CLI 形态（免写 JSON-RPC）
```
python scripts/issue_scan.py src --max-findings 30
python scripts/issue_scan.py src --include-tests   # 连测试文件一起扫
```
先 `moon build --target js cmd/main` 保证 main.js 新鲜。

### 三形态关系
- **单真源 = MoonBit 实现**（`src/server/issue_scan.mbt`）：MCP 工具直接调它；
  CLI 是薄封装（拉起 server → 调工具 → 打印 JSON），不复制扫描逻辑。
- skill（本文档）教 agent 何时用、怎么看、怎么闭环。

## 规则书（10 条，severity 分级）

| id | severity | 模式 | why |
|---|---|---|---|
| div-by-zero | high | `/ 0` | 字面量除零 = panic |
| index-out-of-bounds | high | `rows[0]` 等 | 空数组下标越界 panic |
| unwrapped-unwrap | medium | `.unwrap()` | None/Err 上 panic |
| unsafe-get | medium | `unsafe_get` | 越过越界检查 |
| unprotected-division | medium | `/ total` 等 | 除数变量可能为 0 |
| substring-overrun | medium | `substring(` | end 参数越界 panic |
| ignored-error | low | `ignore(x(...))` | 静默吞错误 |
| string-index | low | `[0]` `[1]` `[2]` | 下标字面量越界风险 |
| possible-overflow | low | `* 10` `to_int() *` | Int 溢出 |
| empty-collection-singleton | low | `.head()` `.first()` | 空集合取单例 |

## 怎么判真伪（关键：避免误报恐慌）

扫描是**字面量匹配**，命中 ≠ 缺陷。agent 必须读上下文判定，参考既有审计结论：
- 测试文件（`*_test.mbt`/`*_wbtest.mbt`）里的 `.unwrap()`/`[0]`：测试自带断言前置，多为安全。
- 有 `is_empty()` 守卫后的 `rows[0]`：安全（如 `registry.mbt` route_pick）。
- `if total > 0` 守卫后的 `/ total`：安全（如 gate/progress_gate）。
- `ignore(stmt.execute())` 仅用于 DDL/PRAGMA：安全（如 store_sqlite exec_if_ok）。
- 真缺陷判据：**无守卫的除零/越界、None 上 unwrap、substring end > length 的调用路径**。

## 闭环（扫描 → 上报 → 修复）

1. 扫：`issue_scan`（MCP 或 CLI）→ 拿到 findings。
2. 判：逐条读文件上下文，标出真缺陷（保留误报记录到 memory，防下次重扫误报）。
3. 上报：真缺陷喂 `report_bug`（`publish_task=true` 自动发布修复根任务到 bugs 命名空间）：
   ```
   report_bug { project_dir, summary: "[rule:unwrapped-unwrap] src/x.mbt:42 <code>", publish_task: true }
   ```
4. 修复：自驱/流水线认领 bugs 命名空间任务 → 修 → 复扫验证命中消失。

## 已知边界

- 字面量匹配（非语法树）→ 有误报（需 agent 判定）与漏报（复杂模式不命中）。
- `rules_file` 参数预留外部规则 JSON（ocr-local moonbit-rules.json 风格），当前未启用。
- 输出上限 `max_findings`（默认 100），防大仓库输出爆炸。
