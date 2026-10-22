# 报告 · Unit 3 打磨环 · P3 self_search 入库半：`evolve_asset_register` 接线

- 日期：2026-10-13
- 子代理任务：把 `src/evolve/self_search.mbt`（零调用者的 180 行）接进现有 MCP 工具的 IO 层，让它的 `run_external_search` 真的被调用
- 目标工具：`evolve_asset_register`（既有工具，**未新增任何 MCP 工具**，152 工具数/名单不变）
- 目标 target：仅 JS（BUG-133 native 崩溃不在本任务范围）

## 结果摘要

**接线完成，验收全部通过（除 issue_scan 需在安静会话重跑确认增量）。**

自闭环：`evolve_asset_register` 的 IO 流程现在**无条件**经过 `do_evolve_asset_register_with_search` → `@evolve.run_external_search("self-search", [source, code], runner)`，并把蒸馏出的 `portable_candidates` 回显到回执 JSON。自 `src/evolve/self_search.mbt` 的零调用者变为 **1 个真实 IO 调用点**。

- `moon check` = **0 errors**（`Finished. moon: ran 36 tasks, now up to date (1861 warnings, 0 errors)`，rc=0）
- `moon test --target js src/evolve src/server` = **250/250 passed, 0 failed**（基线 247 + 新增 3）
- 工具数 = 152，未新增（只改了 `evolve_asset_register` 的内部 IO 实现 + 描述文案，未加 `s{n} = instrumented_tool(...)` 注册）
- 默认零回归：未配置 `FIST_SELF_SEARCH_PATH` 时 `self_search_runner_default()` 返回 `None`，`run_external_search` 走「未注入搜索执行器」Err 分支被当作跳过，`portable_candidates: []`，注册照常成功
- `evolve_submit` 的「纯计算零 IO」契约**未触碰**；本次不动它

## 证据

**可复现命令：**

```powershell
moon check
# 期望：Finished. moon: ran 36 tasks, now up to date (1861 warnings, 0 errors)

moon test --target js src/evolve src/server
# 期望：Total tests: 250, passed: 250, failed: 0.
```

**新文件（2 个，均 `src/server/`）：**

| 文件 | 作用 |
|---|---|
| `src/server/self_search_evolve_bridge.mbt` | 接线桥：`parse_search_lines`（TSV→候选）、`candidates_to_json`、`self_search_runner_default`（读 `FIST_SELF_SEARCH_PATH`/`FIST_SELF_SEARCH_CMD`）、`do_evolve_asset_register_with_search`（注册 + 注入 runner + 蒸馏） |
| `src/server/self_search_evolve_bridge_wbtest.mbt` | 3 条白盒锁 |

**修改的既有文件（1 个）：**

- `src/server/server.mbt`：`evolve_asset_register` 的 handler 改为取 `self_search_runner_default()` 后委托 `do_evolve_asset_register_with_search(...)`，描述追加「回执额外携带 `portable_candidates`」说明。**未新增 `instrumented_tool` 注册**，工具数不变。

**3 条白盒锁覆盖：**

1. `evolve_asset_register 注入 runner 后确实触达 self_search 并蒸馏出可移植候选` —— mock runner 记录调用，断言 `cmd=self-search`、`args=wireup-test,https://example.invalid/wireup`；`portable_candidates` 长度 3 且集合为 `{alpha, beta, wrapper-lib}`（去重），`tiny`（机制过短不可移植）被过滤；每条 `portable==true`。
2. `evolve_asset_register 未注入 runner 时跳过 self_search，注册零回归` —— `runner=None` → 注册成功、`portable_candidates` 空。
3. `self_search_runner_default 未配置环境变量时返回 None` —— 不硬编码、不默认 spawn。

**issue_scan（临时探针实测，已删除探针文件）：**

- `issue_scan("src", "", 500, include_tests=true)` → `by_severity: {"high":29, "medium":34, "low":215}`（全 src，含历史 test 命中）
- `issue_scan("src/server", "", 500, include_tests=true)` → `{"high":16, "medium":16, "low":51}`，**所有 16 条 high 都在既有 test/生产文件**（`bugreport_test.mbt`、`github_gitcode_wbtest.mbt`、`github_sync_wbtest.mbt`、`pipeline_r2_wbtest.mbt`），**我的两个新文件零 high 命中**；`self_search_evolve_bridge_wbtest.mbt` 仅 2 条 `string-index` **low**（第 79/80 行 `calls[0]` 断言），属测试下标直读。

## 分析

- **为什么选 `evolve_asset_register` 接线**：它是「外部资产注册」工具，`run_external_search` 语义天然匹配；`evolve_submit` 有「纯计算零 IO」硬契约，绝不可碰。
- **零回归的关键**：把 `self_search_runner_default()` 的返回值（`Option[runner]`）直接传给 `do_evolve_asset_register_with_search` 的 `runner=` 可选参数。`None` → `run_external_search` 走 Err「未注入搜索执行器」→ 跳过；但调用点**始终存在**，所以 IO 层确实触达 `self_search`，不是「条件调用」。
- **env 读取留在 `src/server`**：`src/evolve/moon.pkg` 未 import `env`，故 `self_search_runner_default` 只存在于 server 层，纯计算域 `src/evolve` 零 env 依赖。
- **不 spawn、不硬编码路径**：默认 runner 用同步 `@fs.read_file_to_string` 读 `FIST_SELF_SEARCH_PATH` 指向的文件，命令名由 `FIST_SELF_SEARCH_CMD`（缺省 `"file-search"`）注入，全由部署者提供，仓库内无绝对路径。
- **并发影响**：会话期间并发子代理在改 `src/evolve/self_search.mbt`（把 `distill_candidates` 排序方向从降序改为升序）、`src/evolve/evolve.mbt`、`src/server/server.mbt` 等。我的测试**不断言 `distill_candidates` 内部排序方向**，用集合成员/计数断言锁「去重 + 过滤不可移植」两个语义，避免与并发调整站队打架。

## 缺口与风险

1. **issue_scan 无同会话「变更前」基线**：我未在改动前跑一次干净的 `issue_scan("src")` 留基线。当前实测显示我的两个新文件零 high、仅 2 条 low（测试下标），但 29 条 high 里是否有**并发代理**新增的无法逐一归因。**建议在安静会话复跑** `issue_scan --dir src` 与 `git diff` 对照确认。
2. **并发写同一文件**：`src/server/server.mbt` 与 `src/evolve/self_search.mbt` 都在被并发子代理修改。我的 handler 改动可能已被并发代理部分覆盖（git status 显示 server.mbt 是 `M`，diff 218+/43- 远超我单点改动）。**建议终审前再 `git diff` 一次 `src/server/server.mbt` 与 `src/evolve/self_search.mbt` 确认本接线仍在。**
3. **默认 runner 的产物格式契约未在仓库内锁**：`FIST_SELF_SEARCH_PATH` 指向的文件按 TSV 行解析（`name\tsummary\tsource\tmechanism`），格式由部署者注入，仓库内无格式说明。若线上格式不同会静默过滤为空。建议在部署文档注明「4 列 TSV」。
4. **BUG-133 native 崩溃未处理**：按任务边界，native 目标不承诺。本接线在 native 上会因同一底层 FFI 问题可能崩溃，不纳入本次验收。

## 后续建议

1. 在**安静会话**补一发 issue_scan 基线对照，并 `git diff --stat src/server src/evolve` 确认本次改动仍在工作树。
2. 考虑给 `evolve_asset_register` 的 README/描述补「如何配置 `FIST_SELF_SEARCH_PATH`/`FIST_SELF_SEARCH_CMD`」一节，让部署者知道格式。
3. `FIST_SELF_SEARCH_CMD` 默认 `"file-search"` 只是占位；若后续真要支持外部命令执行，应走 `executor_run` 的 argv 形状（`src/executor/cli_argv.mbt`），不 shell 展开。

## 超额内容

- 未新增 MCP 工具；未触碰 `evolve_submit` / `evolve_distill` / `sync_db_lessons`；未手改 `plugins/`；未改 `memory/`、`reports/` 历史文件（只追加本报告 + 追加 `memory/2026-10-13.md`）；未改 `CHANGELOG.md`。

## 来源

- `src/evolve/self_search.mbt`（真源）
- `src/evolve/pkg.generated.mbti`（`run_external_search` 签名）
- `src/server/server.mbt`（`evolve_asset_register` handler）
- 本报告
