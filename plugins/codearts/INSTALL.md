# CodeArts Doer 插件态安装

1. 把 `skills/` 拷到 `~/.codeartsdoer/skills/`；
2. 把 `UserSkillStatus.append.txt` 的两行追加进 `~/.codeartsdoer/skills/UserSkillStatus.txt`。

内容由 `scripts/gen_plugins.py` 生成（真源=`plugins/source/`）；手改由 cl7 守卫拦。
MCP 启动参数以仓库根 `.mcp.dev.json` 为准（122 工具 / v0.3.0）。
