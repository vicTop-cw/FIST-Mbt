# AtomCode 插件态安装

把本目录的 `skills/` 整体拷到 `~/.atomcode/skills/`（或软链），重启即见 `/fist-mbt`。

- 本目录内容全部由 `scripts/gen_plugins.py` 从 `plugins/source/` 生成，**不要手改**；
  改了会在 `scripts/check_plugin_sync.py`（cl7）下红。
- MCP server 真源在仓库根 `.mcp.dev.json`（129 工具 / v0.3.1）；
  AtomCode 侧只需在 mcp 配置里指向同一命令，不在插件里复制第二份启动参数。
