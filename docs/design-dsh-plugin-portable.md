# 设计：DSH 插件安装面可移植化 + 当前面路径硬编码清零

- 日期：2026-10-23
- 分支：`slave/dsh-plugin-portable`
- 关联：主仓「DSH 插件装到别人机器就 disconnected」+「源码里到处是本机绝对路径」

## 目标（一句话）

DSH 插件的安装面（`.dsh/fist-mbt-plugin/`）不再把任何一台机器的绝对路径写进跟踪面，
同时把**当前面**（脚本 / 源码注释 / 测试夹具 / 现状文档 / 插件真源）里的机器身份路径清零，
并立一把回归锁防止重新长回来。

## 要改哪些文件

| 文件 | 动作 |
|---|---|
| `.dsh/fist-mbt-plugin/cordis.patch.yml` | 从跟踪面移除（改为本机渲染件，gitignore） |
| `.dsh/fist-mbt-plugin/cordis.patch.yml.tpl` | 新增：模板（`{{FIST_MBT_CLI}}` / `{{FIST_MBT_ROOT}}`，零绝对路径） |
| `scripts/render_dsh_patch.py` | 新增：按脚本位置反推仓根渲染 patch（`--check` / `--selftest`） |
| `scripts/check_hardcoded_paths.py` | 新增：「当前面不得写出本机身份路径」回归锁（`--selftest`） |
| `scripts/check_host_installable.py` | D1 档改判：模板档（跟踪真源）+ 渲染件在场时严格档 |
| `scripts/README.md` | 登记两个新脚本 + 改写 D1 档描述 |
| `.github/workflows/ci.yml` | 接两格新判据（带 `position-why` 锚点） |
| `scripts/fist_mbt_mcp_client.py` / `_run_check_t0r21.py` / `tmp_merge_batch.sh` | 路径改由脚本位置 / env / PATH 推导 |
| `plugins/source/SKILL.commander.md` | FIST 根 / fistcode / 模型清单改为配置化占位（再投影四宿主） |
| `AGENTS.md` / `docs/SOP.md` / 6 份 docs 现状文档 | 机器身份路径 → 环境变量 / 中性占位 |
| `src/server/{issue_scan,run_check_guard,write_gate}.mbt` + 3 个测试 | 注释与夹具的机器身份前缀 → 中性（保留绝对路径**形状**，夹具语义不变） |

## 不改哪些文件（边界）

- **只追加的叙述历史**：`CHANGELOG.md`、`reports/**`、`memory/**`、`docs/archive/**` —— 改它等于伪造历史。
- **构建产物**：`dist/**`、`_build/**`（随发布重建）。
- **生成接口**：`*.mbti`（`moon info` 生成；本机 fmt/info 世代与 CI nightly 不同，本 PR 不做全仓重排）。
- **判据语义**：`run_check` / `write_gate` 的路径判定逻辑**一行未改**，只换夹具里的身份前缀。

## 四态覆盖

- cl1 MCP 工具：无新增工具（无 tool schema 变化）。
- cl2 CLI：无变化。
- cl3 文档：`scripts/README.md` 登记 + 本设计文档 + 本轮报告。
- cl4 测试：`src/server` 379/379（全量 1413 见报告）；两个新守卫各自 `--selftest`。
- cl5/cl6：README/AGENTS 版本与工具数未动（0.3.10 / 170 工具，`check_doc_surface` PASS）。
- cl7 插件态：`gen_plugins.py` 重投影 + `check_plugin_sync.py` PASS。

## 验收标准（可执行）

1. `python scripts/check_hardcoded_paths.py --selftest && python scripts/check_hardcoded_paths.py` → rc 0
2. `python scripts/render_dsh_patch.py --selftest` → rc 0；`--check` 在本机渲染后 → rc 0
3. `python scripts/check_host_installable.py --selftest && python scripts/check_host_installable.py` → rc 0
4. `python scripts/check_plugin_sync.py` → PASS；`python scripts/check_scripts_index.py` → PASS
5. `python scripts/moon_test_env.py --target js` → 全绿
6. 干净检出（无渲染件）上 `check_host_installable` 不得因缺 `cordis.patch.yml` 判红
