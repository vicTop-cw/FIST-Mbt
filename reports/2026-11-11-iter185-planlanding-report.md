# 轮 185 汇报：计划落点判定面 11 → 6（BUG-589 续）

日期：2026-11-11 · 统帅：lead · 模式：explore

## 一、结果摘要

`check_plan_landing.py` 的判定面从 **11 条降到 6 条**（提交后预计 4 条），未碰棘轮上限（仍 25）、
未扩白名单、未删任何计划承诺：

| # | 面 | 处置 |
|---|---|---|
| 1 | `docs/executor-marketplace-skill.md:3` 点名 `src/ops/dispatch.mbt`（从未存在） | 改为现存的 `src/server/server.mbt` 注册面（`executor_register/route/auction/clear`） |
| 2 | `docs/fist-config-skill.md:3` 点名 `..._impl.mbt`（不存在） | 改为 `src/server/mcp_config_scaffold.mbt` |
| 3 | `docs/DOCS-STRUCTURE.md:39` 的 `memory/当日.md` 中文占位 | 改为 `memory/YYYY-MM-DD.md`（当日日志） |
| 4 | 提案文档把命令写进反引号（`... --root ../rx-mbt`） | 参数移出代码跨，路径回到真实脚本 |
| 5 | `docs/probe-authoring.md:115` 引用被截断的失败正文片段 | 按尺的「形态说明」桶写 `<…>_wbtest`，只出数不比对 |
| 6 | `docs/skills` 两次点名（DOCS-STRUCTURE / docs/README 的「今后落位」） | **真落地**：建目录 + `README.md`（存量不迁移的理由写清） |

剩下 4 条均为计划/选项/上游路径，不是「已完成」虚报：`templates/pipeline_mode_loop.md`（计划标「新增」）、
`docs/assets/README.md`（写「建议」）、`scripts/sync_host_skills.py`（owner 待裁决选项 A）、
`src/lib/fist_ops.mbt`（上游仓库路径）。

## 二、资源消耗

- 子代理：1 个（后台只读审计「自述无尺」车道，本轮未等结果，见 §四）。
- 命令：`check_plan_landing.py`（默认 + --gate 两跑）、`grep` 定位 9 处原文、`gen_plugins` + `check_plugin_sync`。

## 三、任务分配记录

- 本轮把「计划落点归零」留在主线程（改动小、需逐条对照原文），把「自述无尺审计」派给只读子代理。

## 四、遗留风险

1. 后台审计车道结果未回，不能计入本轮成果；若失败按额度问题处理。
2. 4 条残留中 `templates/pipeline_mode_loop.md` 与 `docs/assets/README.md` 是**可落地的计划**，
   本轮只归类未施工（模板需内容设计，资产 README 需先有资产）。
3. 判定面缩小后，`VERDICT_GAP_CEILING` 是否收紧到 4 仍待 owner。

## 五、后续建议

1. owner 决定上限收紧；2. 下一轮落地 `templates/pipeline_mode_loop.md`（组合环模板）；
3. 把 `scripts/sync_host_skills.py` 的 owner 选项推进到裁决。

## 六、超额内容

无（本轮只做 BUG-589 的增量归零）。

## 七、来源

- 原文锚点：`docs/executor-marketplace-skill.md:3`、`docs/fist-config-skill.md:3`、`docs/DOCS-STRUCTURE.md:39`、
  `docs/plans/2026-10-26-4pools-rhop-roadmap-proposal.md:127`、`docs/probe-authoring.md:115`。
- 新文件：`docs/skills/README.md`。
- 台账：`memory/bugs.md` BUG-589「轮 185 追记」。
- 读数：`temp/g185_plan_default.txt`（11 条）、`temp/g185_gate2.txt`（6 条，提交后复跑见下一条记录）。
