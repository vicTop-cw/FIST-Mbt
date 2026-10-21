# P0-c 报告 · fist-mbt skill 装进宿主 + 生态 skill 注册（D4 · 拿来主义）

> 日期：2026-10-10　方向：四（生态 skill 拿来主义）　决策：D4=默认 A（只注册不 clone）
> 输入：`docs/improvement-plan-20261010.md` §4 P0-c

## 结果摘要

两项都做完，且都实测验证：

1. **fist-mbt skill 已装进宿主 `C:\Users\victo\.agents\skills\fist-mbt`**
   - 来源：`plugins/deepseek-harness/skills/fist-mbt/`（gen_plugins.py 投影产物，未手改）
   - 宿主目录数 322 → **323**（新增 fist-mbt，未触碰其它生态目录）
   - 安装后：`SKILL.md`(9770B) + `references\` 10 份
   - **SHA256 字节级一致**（src 与 dst 同为 `8B191648CABFD5EE0228A45F26C53D85A543BF57FF7C554850702E60D4C9F34D`）
   - `SKILL.md` L5-7 生成注：`host=deepseek-harness tools=130 version=0.3.6`

2. **通过 `evolve_asset_register` 注册 8 条生态 skill**（D4=A，只注册进 DGM 档案库，**未 clone 任何第三方仓库**）
   - `super-search` 在宿主目录里是**空目录、无 SKILL.md**，按「不存在就跳过」如实跳过

## 资源消耗

| 项 | 值 |
|---|---|
| 子代理 | 1（P0-c 单一 subagent） |
| MCP 调用 | `evolve_asset_register` × 8 |
| 文件写入 | `~/.agents/skills/fist-mbt/` 11 文件（1 SKILL.md + 10 references） |
| 本仓改动 | **0**（DGM 库由 evolve_asset_register 自己写，宿主 skill 在 `~/.agents/skills`） |

## 任务分配记录

| 任务 | 负责 | 结果 |
|---|---|---|
| 安装 fist-mbt skill 到宿主 | P0-c subagent | 完成，字节一致 |
| 枚举生态 skill 存在性 | P0-c subagent | 8/9 存在（super-search 空目录跳过） |
| `evolve_asset_register` 注册 | P0-c subagent | 8 次全 ok |

## 生态 skill 注册映射（source → asset_id → 可 inject 关键词）

| source | asset_id | 关键词 |
|---|---|---|
| test-driven-development | `asset-test-driven-development-2026-10-10T05:23:45Z` | tdd / test-driven-development |
| systematic-debugging | `asset-systematic-debugging-2026-10-10T05:23:45Z` | systematic-debugging |
| spike | `asset-spike-2026-10-10T05:23:45Z` | spike |
| plan | `asset-plan-2026-10-10T05:23:45Z` | plan / plan-mode |
| research-paper-writing | `asset-research-paper-writing-2026-10-10T05:23:45Z` | research-paper-writing |
| requesting-code-review | `asset-requesting-code-review-2026-10-10T05:23:45Z` | requesting-code-review |
| ideation | `asset-ideation-2026-10-10T05:23:45Z` | ideation |
| subagent-driven-development | `asset-subagent-driven-development-2026-10-10T05:23:45Z` | subagent-driven-development |

每条 `note` 写明「怎么用/何时用/inject 关键词」，`code` 指向真实绝对路径，`score=0.5`，`goal=[asset]<source>`。

## 遗留风险

1. **注入面未端到端实跑**：`evolve_asset_register` 的注入路径（`plan`/`claim` 传 `inject=<keyword>` 返回非空 `injected_assets`）本轮只按工具契约 + asset_id 给出命中面，未触发 plan/claim（避免造任务）。**由 P2 的 `check_skill_inject` 守卫补这一格。**
2. **super-search 未注册**：宿主目录空、无 SKILL.md，按硬边界跳过；要纳入需先补全内容。
3. **installed skill 会随工具数漂移**：当前 `tools=130`，P1-b 上线后变 134，需在 P1-b 后**重同步**宿主 skill（本报告不覆盖）。
4. **落点可复现性未对表**：`evolve_asset_register` 写当前 server 进程 cwd 的 DGM 库，回执无 resolved_path；未与 `memory/` 归档落点核对。
5. **文案误差**：任务前提「references 11 份」实际 10 份（列出的名字本身也是 10 个），未改任何文件。

## 后续建议

- P1-b 注册 4 个 hat 工具后重跑 `gen_plugins.py` + 重同步宿主 skill（`tools=130→134`）。
- `check_skill_inject` 落盘后跑一次真注入命中测试（用已注册的 8 条 asset_id 之一）。
- 宿主目录命名是 `hm-<name>-<version>`（Hermes 托管命名），仅 super-search 是裸名——注册 `code` 路径已按实际存在路径给，无需改。

## 来源

- 生成真源：`plugins/deepseek-harness/skills/fist-mbt/SKILL.md` + `references/*.md`
- 宿主落点：`C:\Users\victo\.agents\skills\fist-mbt\`
- 生态 skill：`C:\Users\victo\.agents\skills\hm-*` + `super-search`（空）
- 档案库：fist-mbt DGM（`evolve_asset_register` 写入）
