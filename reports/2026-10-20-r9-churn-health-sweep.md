# R9 · churn 健康复查 + 守卫清扫

- 时间：2026-10-20 20:50 (+08:00)
- 范围：`src/server` 并发 WIP（约 37 个脏文件 + 1 个未跟踪新文件）期间，做全量测试健康复查 + 全守卫清扫
- 结论：**产品零回归**（`moon test --target js` = 1347/1347, failed 0, exit 0）；文档面因「我上轮加测试 → 1346→1347」+「并发 WIP 文件未同步」产生 4 处可归因红，其中 1 处已由我在干净文件 AGENTS.md 上消除

## 结果摘要

| 项 | 结果 | 说明 |
|---|---|---|
| 全量测试 `moon test --target js` | **1347/1347, failed 0, exit 0** | 并发 churn 下仍零回归；R8 的 BUG-333 锁保留 |
| R8 变更存活 | ✅ `scan_denoise_default_skip` 9 处引用、BUG-333 锁 1 处；diff = 29 插入 / 0 删除（与 R8 一致，未被并发覆盖） | `git diff --stat -- src/server/issue_scan.mbt` |
| `check_plugin_sync` / `check_scripts_index` / `check_store_tables_wired` / `check_ps_encoding` / `check_desc_enum_sync` / `check_doc_surface` / `check_entry_paths` / `check_pkg_imports` / `check_mbti_sync` / `check_py_stdout_encoding` / `check_demo_isolation` / `check_release_asset_names` / `cli_flag_probe` | **全 PASS** | 13 项守卫绿 |
| `check_test_sync` | ⚠️ 红（R2）→ 我修好 R3 | R3 防空转已通过我在 AGENTS.md 同步 1347 消除；R2 仍点名 2 个并发脏文件（见下） |
| `check_badge` | ⚠️ 红 | README 徽章 1346 ≠ 实测 1347 |
| `check_tools_sync` | ⚠️ 红（R3b） | 并发 agent 的 playbook 声明 1 个不存在的工具 |
| `check_publish_payload` | 🔴 P1 红 | 并发 agent 的未跟踪文件漏入发布面（有守卫兜底） |

## 4 处红的归因（不隐瞒、不误归）

1. **`check_badge` / `check_test_sync` R2 — README、`docs/agent-map.md`、`scripts/scoring_rubric.md` 仍声明 1346**
   - 根因：R8 我加了 1 条白盒锁（BUG-333 降噪锁），实测数 1346 → **1347**，文档声明面集体过时。
   - 我做了：在**干净的** `AGENTS.md`（在守卫扫描集内）把 L107 与 L132 的「1346/1346」同步为「**1347/1347**」（2026-10-20 实测，注明 + BUG-333 默认降噪锁），**消除了 `check_test_sync` 的 R3 防空转红**。
   - 未做：README.md / `docs/agent-map.md` / `scripts/scoring_rubric.md` / ARCHITECTURE.md / docs/deliverable.md 的 1346 → 1347 —— **这 5 个文件当前都是并发 WIP 脏文件**（`git status --porcelain` 为 ` M`），我按约束不覆盖他人未提交改动。这些红由 README 侧收敛时一并同步。
   - 风险：徽章红会持续到并发 WIP 收口；期间 CI 的 badge 判据红但**不阻断**产物（非 P1）。

2. **`check_tools_sync` R3b — `docs/2026-10-20-slave-dev-playbook.md:206` 声明 1 个工具，实测注册 170**
   - 根因：并发 agent 的 playbook 把 `model_route` 的 `dry_run` 分支回写**误当作一个独立工具**列出；实测无此工具。
   - 归责：并发 agent 的文档错误，非产品 bug（`dry_run` 是 `model_route`/`executor_run` 的可选参数，非独立工具）。
   - 未做：该文件是并发 WIP，不覆盖。建议 README/playbook 作者改为描述为参数分支。

3. **`check_publish_payload` P1 — `src/server/bug335_ns_route_wbtest.mbt` 未跟踪且未 ignore**
   - 根因：并发 agent 新增的 `src/server/bug335_ns_route_wbtest.mbt` 处于 `??` 未跟踪态，`moon publish` 打包面 = 工作树 − .gitignore，会把该 WIP 测试文件公开进包。
   - 风险受控：`check_publish_payload` 已挂在 ci.yml，CI 会在 publish 前拦下；且文件是测试代码、无凭据形状（非 P2）。
   - 未做：不加 .gitignore（会挡住并发 agent 后续 `git add`）、不代其 commit。**归责 = 该文件的作者需将其入库**。

4. **`check_test_sync` 初跑 rc=1 "无法从参数/日志解析测试总数"** —— 我少传 log 参数（同 check_badge 的教训），补 `temp/moon_test_r9.log` 后正常出判定。属调用错，非产品红。

## 关键证据

```
$ moon test --target js     → Total tests: 1347, passed: 1347, failed: 0.   (exit 0)
$ python scripts/check_badge.py temp/moon_test_r9.log README.md
    → BADGE-STALE: README 徽章 1346/1346 ≠ 实际测试数 1347/1347
$ python scripts/check_test_sync.py temp/moon_test_r9.log
    → 修 AGENTS.md 前：R3 防空转（现状面无声明等于 1347）
    → 修 AGENTS.md 后：R3 消失，仅剩 R2 点名 agent-map.md / scoring_rubric.md
$ git diff --stat -- src/server/issue_scan.mbt
    → src/server/issue_scan.mbt | 29 +++++++++++++++++++++++++++++
```

## 资源消耗

- 命令：`moon test --target js`（全量，约数分钟）×1；守卫脚本约 17 次子进程调用
- 产物：`temp/moon_test_r9.log`（测试日志，gitignored）

## 遗留风险

1. **文档面 1346 → 1347 同步未完成**（README/agent-map/scoring_rubric/ARCHITECTURE/deliverable 5 处），全部卡在并发 WIP 上；`check_badge` 与 `check_test_sync R2` 保持红。修法：并发收口后，由 README 侧一次性把测试数声明同步到 1347。
2. **`src/server/bug335_ns_route_wbtest.mbt` P1 发布面泄漏** —— 等待该文件作者入库；期间 `check_publish_payload` 会在 CI 兜底。
3. `docs/2026-10-20-slave-dev-playbook.md` 工具声明错误 —— 等待作者修正为参数分支描述。

## 后续建议

- 下一轮（R10）等 `src/server` 并发 WIP 收口后：① 一次性把全部文档的测试数 1346→1347 同步（清 badge/test_sync 红）；② 让并发 agent 入库 `bug335_ns_route_wbtest.mbt`；③ 恢复对 `src/server/server.mbt` 的编辑以继续 BUG-333 ①（`--min-severity`）、BUG-333 ③、BUG-327 part 2、BUG-238 server 层。
- 我本轮唯一落盘改动：`AGENTS.md` 两行测试数 1346→1347（`git status` 原为干净，现在含我这 1 处改动，未 commit，与其余 WIP 隔离）。

## 来源

- 全部读数来自本机实测（`moon`、守卫脚本、`git status --porcelain` / `git diff --stat`），未引用任何自述。
