# 报告：R4 组合模式（cl7 插件态再生成收口）

## 结果摘要
- 清掉守卫族最后一个已知红面：`check_plugin_sync`（cl7）从 FAIL → **PASS**。
- 插件态与真源投影重新对齐：**4 宿主 / 64 个生成文件 / 170 工具 / v0.3.9 / 启动参数真源 `.mcp.dev.json`**。
- 根因：并发 agent 在 `src/server` 等真源持续增改工具/版本（真源 170 工具、v0.3.9），但未同步再生成插件投影 ⇒ 一源四态 cl7 漂移。

## 证据
- 修前：`check_plugin_sync` FAIL（9 个文件与真源投影不一致：README.md + atomcode/claude 各 `fist-commander`/`fist-mbt` SKILL.md 等）。
- 处置：`python scripts/gen_plugins.py` rc=0，回执「OK 已生成四宿主插件态：170 工具 / v0.3.9 / BUG-1~343 共 343 条入账：15 条待修 / 304 已修 / 10 重复并入 / 12 误报」。
- 修后：`check_plugin_sync` **PASS rc=0**（4 宿主 / 64 生成文件 / 170 工具 / v0.3.9）。
- 账本同步读数：待修 15（R2 销 BUG-342/343 后 17→15）、已修 304、重复并入 10、误报 12。

## 变更内容
- `plugins/` 树由官方生成器 `gen_plugins.py` 从单一真源（`plugins/source/` + `server.mbt` 工具数 + `moon.mod` 版本 + `memory/bugs.md` 账本 + 根 `.mcp.dev.json`）再投影；未手改任何插件文件（遵循「插件目录禁止手改」）。

## 并发协调
- `plugins/` 先 `reserve_check`（free）→ `reserve_scope` 成功 → 生成 → `reserve_release`，未与他方插件编辑冲突。

## 遗留风险
- 并发 WIP 仍在改 `src/server`，工具数/版本可能继续漂移 ⇒ cl7 可能再次变红；建议并发 agent 在真源收敛后跑一次 `python scripts/gen_plugins.py` 再提交。
- 累计 4 轮已清红面：R1 BUG-332（stdout 编码闸）+ R2 BUG-342/343 销账 + scripts-index 漂移 + R3 入口路径回归（R1 5→0）+ R4 cl7 再生成。

## 来源
- 守卫 `scripts/check_plugin_sync.py`（cl7）、生成器 `scripts/gen_plugins.py`、账本 `memory/bugs.md`。