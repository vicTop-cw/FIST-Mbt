# 2026-10-22 · v0.3.10 升版对齐报告（fix/version-align-r2）

- 生成时间：2026-10-22 +08:00
- 分支：`fix/version-align-r2`（从 origin/master d8deed8b 新建，未碰主仓）
- PR：见 https://github.com/vicTop-cw/FIST-Mbt（本文件随 PR 入仓）

## 结果摘要

风语者升版 v0.3.10 后遗留的 **5 把预存红尺一次收口**：
`check_host_installable` / `check_doc_surface` / `check_release_asset_names` / `check_scripts_index` / `check_plugin_sync` 全部 **rc 1→0**。

| 面 | 改动 |
|----|------|
| DSH manifest | `.dsh/fist-mbt-plugin/package.json` version+description 0.3.9→0.3.10 |
| 文档自述 | `USAGE.md:3` 版本声明、`README.md:141` 离线线资产名字面量（R13 面）→ 0.3.10 |
| 脚本索引 | `scripts/README.md` 补登记 4 把漏网尺（fist-gate / whisperer / check_bug_refs / fist-pr-automator） |
| 插件投影 | `gen_plugins.py` 重投影（170 工具 / v0.3.10 / 账本 361 条），提交态 `check_plugin_sync` 逐字节 PASS |

提交：`8b989a52`（17 文件，+42/−35；0 个 `.mbt/.mbti`）。

## 验证方式（金条八）

- 5 把尺逐一直跑 rc=0（改前 5 红 → 改后 5 绿，同一 worktree 同一环境对照）
- 提交后复验 `check_plugin_sync` rc=0（一源四态投影一致性）
- `git status` 0 脏件、0 个 src 面污染（电池冷编译慢，全量 43 格交 CI 守卫臂权威执行）

## 资源消耗

约 6 次尺执行 + 1 次 gen_plugins + 1 次 worktree 建立；无 moon 全量重跑（本单零 src 改动，JS 测试面不受影响）。

## 任务分配记录

Lead 直接执行（轻任务：4 个手维护文件 + 生成器；金条四判定不值得外包——改哪几行是守卫读数直接给出的）。合并裁决权在风语者。

## 遗留风险

1. 账本 4 个 OPEN 缺陷（BUG-354 参数消费 / BUG-361 Json::value 形态决策 / BUG-362 编译器少报 / BUG-364 agent-map 覆盖缺口）均为 **owner 决策面**，非机械修复，留裁。
2. 主仓在途 agent 若同时改 `scripts/README.md` / `plugins/`，与本 PR 有文本冲突可能——合并时以本 PR 的 gen_plugins 重跑为准即可消解。

## 后续建议

合并后建议风语者把「升版检查单」（manifest/USAGE/README 字面量/索引/重投影五步）固化成 `fist-gate.py` 的一臂，让下次升版自动红出来，而不是靠 5 把尺事后各报各的。

## 超额内容

无——严格落在「修复已知问题」边界内，未动任何 src 语义面。

## 来源

- `memory/bugs.md`（BUG-357 先例：同类升版对齐在 0.3.9 做过一次，形状相同）
- 5 把尺的 FAIL 读数原文（改前逐条留存于本会话执行记录）
- `scripts/gen_plugins.py` / `scripts/check_plugin_sync.py`（一源四态真源）
