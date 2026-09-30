# 插件态（一源四态的第四态）

四个宿主的插件目录**全部是生成产物**，唯一可编辑真源是 `plugins/source/`：

| 宿主 | 目录 | 宿主读取方式 |
|---|---|---|
| AtomCode | `atomcode/skills/<name>/SKILL.md` | 拷/链到 `~/.atomcode/skills/` |
| CodeArts Doer | `codearts/skills/<name>/SKILL.md` + `UserSkillStatus.append.txt` | 拷 + 追加登记行 |
| DeepSeek Harness | `deepseek-harness/instructions.append.md` + `skills/fist-mbt/` | 追加进 `~/.deepseek/instructions.md` |
| Claude | `claude/.claude-plugin/*.json` + `.mcp.json` + `skills/` | marketplace add |

- 生成：`python scripts/gen_plugins.py`
- 守卫（cl7）：`python scripts/check_plugin_sync.py`——重跑生成器到临时区再逐字节 diff（比较前先做
  行尾归一，否则 autocrlf 克隆会把整棵投影判红，见 BUG-102；判据自身有 `gen_plugins.py --selftest` 四格），
  手改插件、忘重生成、数字漂移都会红。
- 当前投影：129 工具 / v0.3.5 / 缺陷账本 BUG-1~130 共 129 条入账：1 条待修 / 115 条已修 / 9 条重复并入 / 4 条误报（按条目抬头状态计数；叙述面只追加，见 memory/bugs.md 记账规则）
