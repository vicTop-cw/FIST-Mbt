# Claude 插件态安装

`/plugin marketplace add <本仓路径>/plugins/claude` → `/plugin install fist-mbt@fist-mbt`。

- `.mcp.json` 是仓库根 `.mcp.json` 的**逐字副本**（启动参数只有一份真源）；
- `skills/` 由 `scripts/gen_plugins.py` 投影自 `plugins/source/`；手改由 cl7 守卫拦。
