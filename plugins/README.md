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
  行尾归一，否则 autocrlf 克隆会把整棵投影判红，见 BUG-102；判据自身有 `gen_plugins.py --selftest` 五格，
  第五格钉「启动参数真源文件名不被本机未跟踪残留决定」（BUG-131：本机绿 / CI 红的源头）），
  手改插件、忘重生成、数字漂移都会红。
<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
- 当前投影：170 工具 / v0.3.9 / 缺陷账本 BUG-1~348 共 348 条入账：19 条待修 / 305 条已修 / 10 条重复并入 / 12 条误报（按条目抬头状态计数；叙述面只追加，见 memory/bugs.md 记账规则）
=======
- 当前投影：170 工具 / v0.3.9 / 缺陷账本 BUG-1~368 共 353 条入账：19 条待修 / 313 条已修 / 10 条重复并入 / 9 条误报（按条目抬头状态计数；叙述面只追加，见 memory/bugs.md 记账规则）
>>>>>>> f73788da (fix(guard): 守卫执行面普查 + 仓内电池真源化（BUG-365/366 / T0r21）)
=======
- 当前投影：170 工具 / v0.3.9 / 缺陷账本 BUG-1~369 共 354 条入账：20 条待修 / 313 条已修 / 10 条重复并入 / 9 条误报（按条目抬头状态计数；叙述面只追加，见 memory/bugs.md 记账规则）
>>>>>>> 095bf312 (feat: check_plan_landing 加搬家态与判定面棘轮（BUG-367 D 类 / 新账 BUG-369）)
=======
- 当前投影：170 工具 / v0.3.9 / 缺陷账本 BUG-1~364 共 349 条入账：17 条待修 / 311 条已修 / 10 条重复并入 / 9 条误报（按条目抬头状态计数；叙述面只追加，见 memory/bugs.md 记账规则）
>>>>>>> 5246a611 (fix(guard): J14 认领项目地图面 + J3 钉组数，文档面三格盲区同步真源（BUG-363 / T0r20）)
=======
- 当前投影：170 工具 / v0.3.9 / 缺陷账本 BUG-1~342 共 327 条入账：11 条待修 / 295 条已修 / 10 条重复并入 / 9 条误报（按条目抬头状态计数；叙述面只追加，见 memory/bugs.md 记账规则）
>>>>>>> 9dfd08a0 (fix(deps): 清零 0029 unused_package 全族 16 条（BUG-342）)
=======
- 当前投影：170 工具 / v0.3.9 / 缺陷账本 BUG-1~343 共 328 条入账：11 条待修 / 296 条已修 / 10 条重复并入 / 9 条误报（按条目抬头状态计数；叙述面只追加，见 memory/bugs.md 记账规则）
>>>>>>> c161e059 (fix(deps): 清零 0071 core_package_not_imported 剩族 4 条（BUG-343）)
