# 报告：R3 组合模式（守卫族体检 + 入口路径回归修复）

## 结果摘要
- 守卫族 6 项重跑全绿（含 R2 修复保持）；CI JS 轨补扫发现 **2 处真红**。
- **修复 `check_entry_paths` 回归（R1 5 处违例 → 0）**：BUG-93/101「发布入口迁至 cmd/cli」被并发 agent 用开发机绝对路径 `_build\...\cmd\main\main.js` 重新踩红。
- `check_plugin_sync`（cl7）仍红：插件态与真源投影漂移，处置为重跑 `gen_plugins.py`（属较重再生成，留待下轮或 owner 裁决）。

## 证据
- `check_entry_paths.py`：修前 FAIL（5 处），修后 **PASS（R1 退役入口引用 0 处、R2 缺 serve 启动器 0 个；扫描面 220 份文件）**，rc=0。
- `python -m py_compile` 5 个改动脚本 = rc=0（语法完好）。
- build 产物核查：`_build/js/debug/build/cmd/cli/cli.js` 存在（发布入口），`cmd/main/main.js` 为陈旧遗留（源入口已退役）。
- 同批守卫：`check_doc_surface` / `check_scripts_index` / `check_ps_encoding` / `check_py_stdout_encoding` / `check_pkg_imports` / `check_mbti_sync`（656 条 pub 声明全有定义）/ `check_store_tables_wired`（26 表接线一致）/ `check_desc_enum_sync` 全 rc=0。

## 变更内容（5 脚本，仅入口路径面）
- `scripts/fist_mbt_mcp_client.py`、`scripts/ns_route_probe.py`：`_build\js\debug\build\cmd\main\main.js` → `_build\js\debug\build\cmd\cli\cli.js`。
- `scripts/fix_esm_require.py`、`scripts/mcp_tool_tour.py`、`scripts/store_isolation_probe.py`：候选列表首项已是 cli.js，**删除**陈旧的 `cmd\main\main.js` 兜底项（避免重复）。其余代码零改动。

## 并发协调
- 5 文件逐一 `reserve_scope` 成功 → 编辑 → `reserve_release`，全程未抢占他人文件。
- `scripts/ns_route_probe.py:22` 仍有 `SyntaxWarning: invalid escape sequence '\I'`（并发 agent 的非 raw 字符串 `"E:\..."`），仅警告不阻断，已留痕未代改。

## 遗留风险
- `check_plugin_sync` cl7 仍红：真源 170 工具 / v0.3.9，9 个插件文件与投影不一致。处置 `python scripts/gen_plugins.py` 后再复跑守卫；再生成会批量改写 `plugins/`，需防与并发 agent 插件编辑冲突。
- `check_badge` / `check_test_sync` 需显式传测试日志参数（本次调用姿势不对，非产品红）。
- 建议并发 agent：新增/引用产物路径一律用 `cmd\cli`，且用 `r"..."` 或 `os.path.join` 拼路径，避免 R1 违例与 invalid-escape 告警复发。

## 来源
- 守卫 `scripts/check_entry_paths.py`（BUG-93/101）；产物 `_build/js/debug/build/cmd/cli/cli.js`；账本 L1497（cmd/main→cmd/cli 搬家）与 L1516（104 处修复）为回归基线。