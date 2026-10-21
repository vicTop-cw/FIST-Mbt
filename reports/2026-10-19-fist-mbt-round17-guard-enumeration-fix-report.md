# Round 17 报告 · 补全 CI 权威守卫枚举 + 修复 2 处守卫自身缺陷

- 轮次：Round 17 / 256
- 时间：2026-10-19 13:00–15:15（Asia/Shanghai）
- 模式：advance（打磨收口车道）
- 状态：**完成**。账本 331 条：13 待修 / 296 已修 / 10 重复并入 / 10 误报。提交 `765d60d`、`3e67820`。

## 结果摘要

1. **补全 CI 权威守卫枚举（BUG-329 教训闭环）**：从 `.github/workflows/{ci,fist-ci}.yml` 反解出 CI 权威守卫 = **22 项**。此前每轮只跑 9–10 项就声称「守卫全绿」，遗漏 11 项（`check_desc_enum_sync` / `check_host_installable` / `check_mbti_sync` / `check_model_auth_no_key` / `check_pkg_imports` / `check_plan_landing` / `check_py_stdout_encoding` / `check_skill_inject` / `check_template_ctrl` / `check_upgrade_installer` / `cli_flag_probe`）。**22 项中我能影响的 19 项全 PASS**；仅 `check_entry_paths`（5 违例全在并发 WIP 文件）、`check_test_sync`、`store_isolation_probe`（后两者并发 WIP 未动）未绿。
2. **BUG-330 · `check_skill_inject` 守卫自身缺陷**（上报+FIXED）：SELECT `goal/note/code LIKE '%[asset]%'` 过宽 —— `[lesson]` 教训条目 `lesson-202610-15.05.17`（goal=`[lesson] concurrent-coordination`）因 code 里合法提到归档规则被误选，再因 goal 非 `[asset]<source>` 被误报「反查问题」；守卫 L35-37 自述「`[lesson]` 不算 `[asset]`」与实现自相矛盾；且检索面 `lookup_injected_assets_in` 只按 goal/note 匹配、不匹配 code。另修 FAIL 计数 `len(rows)`→`len(ap)`（「共 16 条」实为 1 条）。修复后主检 PASS（15 条 `[asset]` 全部可反查）、`--selftest` OK。
3. **BUG-331 · DSH 宿主 manifest 版本落后**（上报+FIXED）：`check_host_installable` D1 档 FAIL「DSH manifest version 0.3.8 != moon.mod 0.3.9」。`8052e67` 标注「三处真源同步」（help_topics.mbt + moon.mod + server.mbt）漏了第四处 `.dsh/fist-mbt-plugin/package.json`（被 git 跟踪、手写、`gen_plugins` 不生成）。修复 version 0.3.8→0.3.9 + meta.description 同步。复核 PASS。同族 = BUG-114 / BUG-120 / BUG-329。
4. **全仓残留版本滞后字面量清零**：`git grep "0\.3\.8"` 剩余命中全为合法（CHANGELOG/BACKLOG 历史事实、`upgrade_wbtest.mbt` 测试数据）。
5. **零回归**：`moon test --target js` = **Total tests: 1338, passed: 1338, failed: 0**（工作树含并发 agent 未提交代码）。`cli_flag_probe` 三档全对（版本旗 rc=0 回显 0.3.9 / 帮助旗 rc=0 / 未知子命令 rc=2）。`e2e_native_heap_probe --selftest` OK（Windows 构建门 SKIPPED 为预期，POSIX-only）。

## 资源消耗

| 项 | 读数 |
|---|---|
| 守卫实跑 | 22 项（CI 权威）+ 关联守卫复核 |
| 工具调用 | 守卫族 + `bug_list` + `report_bug`×2 + `bug_fix`×2 + `gen_plugins`×2 + `check_plugin_sync` |
| 测试 | `moon test --target js` 1 次全量 |
| 提交 | `765d60d`、`3e67820` |
| 修改文件 | `scripts/check_skill_inject.py`、`.dsh/fist-mbt-plugin/package.json`、`memory/bugs.md`、`memory/2026-10-19.md`、`plugins/**`（生成投影） |

## 任务分配记录

| 步骤 | 执行 | 结果 |
|---|---|---|
| 并发状态核查 | 主 agent（读） | `server.mbt`/`issue_scan_wbtest.mbt` 仍 M，8 项并发 WIP 未提交 |
| 守卫枚举反解 | 主 agent | CI 权威 22 项，发现 11 项此前漏跑 |
| BUG-330 修复 | 主 agent（`scripts/check_skill_inject.py`） | PASS + selftest OK |
| BUG-331 修复 | 主 agent（`.dsh/fist-mbt-plugin/package.json`） | PASS |
| 插件重生成 | `gen_plugins.py` + `check_plugin_sync` | 331 条入账，四宿主投影对齐 |

## 遗留风险

1. **BUG-327 part 2 仍阻塞**：`src/server/server.mbt` / `src/server/issue_scan_wbtest.mbt` 仍 M（并发 agent）。`require_ocr` 门 fail-closed 修复未落地 ⇒ `ocr_scan` 对 `.mbt` 不可用 ⇒ 本仓唯一语义 bug 检测能力仍是坏的。这是寻虫能力头号阻塞。
2. **`check_entry_paths` 5 违例**全在并发 WIP 文件（`mcp_tool_tour.py`/`ns_route_probe.py`/`store_isolation_probe.py`/`fist_mbt_mcp_client.py`/`check_test_sync.py`），留并发 agent 收口。
3. **未重建 `dist/fist-mbt.js`**：从当前工作树构建会把并发 agent 未提交的 omega 代码一起打进 dist（不合法）。留并发收口后做。
4. **`check_plan_landing` exit 1**：自述只读诊断，非门禁红，不视作风险。

## 后续建议

1. **并发 agent 收口后**：① 重建 `dist/fist-mbt.js` 上线 BUG-327 part 1/2；② 跑 `check_entry_paths` 消 5 违例；③ 升 README 徽章 1338→实际测试数。
2. **版本 bump 清单化**：`0.3.9` 已暴露 3 次漏同步（README / DSH manifest / 历史 server.mbt）。建议把版本字面量检查并入一次守卫（现 `check_host_installable`/`check_release_asset_names`/`check_doc_surface` 各查一面，仍有间隙）。

## 超额内容

- 修复 BUG-330 时一并修了同文件的计数误导（`len(rows)`→`len(ap)`）——非本次上报诉求，但属于同一处缺陷面。

## 来源

- CI 权威清单：`.github/workflows/ci.yml`、`.github/workflows/fist-ci.yml`
- 守卫代码：`scripts/check_skill_inject.py`（L140-145 SELECT、L332 计数）
- DSH manifest：`.dsh/fist-mbt-plugin/package.json`（L3 version、L16 meta.description）
- 版本 bump：`git show 8052e67 --stat`（3 文件仅版本字面量）
- 账本：`memory/bugs.md` BUG-330、BUG-331