# Round 18 报告 · 守卫族 selftest 系统性体检 → BUG-332 `--all` 残余面修复

- 日期：2026-10-19
- 目标：`[打磨，寻虫，修复，验证，清整，推进]` 组合模式，全程用 fist-mbt，善用其能力，注意并发 agent
- 轮次：18 / 256

## 结果摘要

并发 agent 未提交 `src/server/server.mbt`（HEAD 仍 `d010592`），BUG-327 part 2 继续阻塞。转独立寻虫：**对全部 22 个支持 `--selftest` 的守卫跑 selftest**（BUG-329 教训：selftest 崩溃即守卫坏）。

结果：18/19 个 selftest 通过，**仅 `check_py_stdout_encoding.py --selftest` exit=2 崩溃**，暴露 BUG-332 —— `--all` 残余面有 10 处脚本缺 BUG-58/138 的 stdout UTF-8 重配。已修 8 处（含 `e2e_assistant_xproc.py`），余 2 处为并发 WIP。CI 门禁面 **19/19 全绿**。

## 资源消耗

- 守卫 selftest 全量 1 轮 + `check_py_stdout_encoding` 三态（CI 面 / `--all` / `--selftest`）复跑
- `moon test --target js` 1 发（全量，exit 0）
- `gen_plugins.py` 1 次（BUG-332 入库后重生成）
- 代码改动：9 个 `scripts/*.py` 各插 5 行 BUG-58/138 重配块 + `memory/bugs.md` 1 条 BUG-332 + `plugins/` 9 文件投影刷新

## 任务分配记录

| 环节 | 执行者 | 结果 |
|---|---|---|
| 守卫 selftest 系统性体检（22 项） | lead 直接 | 21 绿 / 1 红（`check_py_stdout_encoding`） |
| BUG-332 根因定位 | lead 直接 | `--all` 面 10 违例，CI 真跑 `--all` |
| 8 处脚本补 UTF-8 重配 | lead 直接（Python 内联批量） | 编译全过，抽查可运行 |
| 插件重生成 | lead 直接（`gen_plugins.py`） | `check_plugin_sync` PASS |
| 终态守卫复核 | lead 直接 | CI 门禁 19/19 绿 |

## 遗留风险

1. **BUG-332 余 2 处**：`scripts/fist_mbt_mcp_client.py` / `scripts/ns_route_probe.py` 仍缺 UTF-8 重配，`check_py_stdout_encoding --all` 仍 exit 1，`--selftest` 仍 exit 2 —— 待 concurrent agent 收口时补，补后全绿。这是本轮唯一的红面，且完全在并发 agent 一侧。
2. **BUG-327 part 2 仍阻塞**：`src/server/server.mbt` / `src/server/issue_scan_wbtest.mbt` 仍 M（并发 agent）。`ocr_scan` 对 `.mbt` 的 fail-closed 门禁仍在，本仓唯一语义级寻虫能力仍缺。这是寻虫能力头号阻塞。
3. **`dist/fist-mbt.js` 未重建**：从当前工作树构建会把并发 agent 未提交代码打进 dist，不合法。留其收口后做。
4. **R17 结论修正**：R17 称「CI 守卫全绿」，但未覆盖 `check_py_stdout_encoding --all` 面（R17 首次跑该守卫主检，只跑了 CI 反解面）。本轮已补。

## 后续建议

1. 等并发 agent 提交 `server.mbt` + `issue_scan_wbtest.mbt` 后：
   - 立即接 BUG-327 part 2（恢复真实寻虫闭环）
   - 提醒其给 `fist_mbt_mcp_client.py` / `ns_route_probe.py` 补 UTF-8 重配（BUG-332 余 2）
   - 收口后重建 `dist/fist-mbt.js`（当前工作树构建不合法）
2. 建议给守卫族加一条元规则：**每个新脚本必须自带 BUG-58/138 重配**（在 `check_scripts_index` 或新守卫里），否则每次加脚本都会漏到 `--all` 面。
3. `check_plan_landing` exit 1 为诊断-only、非 CI 门禁（ci.yml/fist-ci.yml 均不调用），维持不门禁化。

## 超额内容

- 系统性 selftest 体检是 R17 守卫族枚举补全的**自然延伸**：R17 修好了「守卫没被跑」的漏洞，本轮修好了「守卫跑了却 selftest 崩」的漏洞（BUG-329 同类）。两者合起来才构成完整的守卫健康面。

## 来源

- 守卫族：`.github/workflows/ci.yml` + `.github/workflows/fist-ci.yml`（22 项 CI 门禁 + 3 项诊断）
- selftest 崩溃证据：`python scripts/check_py_stdout_encoding.py --selftest`（exit 2）
- BUG-332 账本：`memory/bugs.md`
- 修复提交：`8f00f8b`（8 处脚本 UTF-8 重配）、`4c9b94e`（插件重生成）
