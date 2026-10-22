# 2026-10-22 · v0.3.10 升版对齐 r3 报告（fix/version-align-r3）

- 生成时间：2026-10-22 +08:00
- 分支：`fix/version-align-r3`，**从最新 origin/master `99bacbe5` 新建**（遵指令：主仓有更新时从主仓开新分支，不在旧独立分支上续修）

## 结果摘要

v0.3.10 升版遗留的 **5 把预存红守卫尺一次归绿**（0 个 `src/*.mbt` 污染）：
`check_host_installable` / `check_doc_surface` / `check_release_asset_names` / `check_scripts_index` / `check_plugin_sync` 全部 rc 1→0。

| 面 | 改动 |
|----|------|
| DSH manifest | `.dsh/fist-mbt-plugin/package.json` version+description 0.3.9→0.3.10 |
| 文档自述 | `USAGE.md:3` 版本声明；`README.md:141` 离线线资产名字面量（R13 面）→ 0.3.10 |
| 脚本索引 | 点名登记 `check_bug_refs.py`、`fist-pr-automator.py`；把 `fist-gate.py` 从 whisperer 条目的顺带提及**升格为独立条目** |
| 插件投影 | `gen_plugins.py` 重投影（170 工具 / v0.3.10 / 账本 361 条），提交态 plugin-sync 逐字节 PASS |

## 与 PR #10 的关系（重要）

PR #10（`fix/version-align-r2`）base 是较早的 master，master 随后收编了 whisperer 登记 ⇒ 直接合会**重复登记**。本 PR 是它的**超集取代**：同目标、更准的登记、零重复。**建议关掉 #10 只留本 PR。**

本 PR 另纠正 #10 一处不实措辞：`check_bug_refs.py` 并非「悬空即红」——实测源码是**默认只报不判（rc=0），`--strict` 才判：ORPHAN→2 / CLOSED→1**。登记条目同样要过金条八（实读源码，不抄印象）。

## 资源消耗

5 次尺直跑 + 1 次 gen_plugins + 1 次 worktree 建立；本单零语义改动（不跑 moon test 全量，JS 测试面不受影响）。

## 任务分配记录

Lead 直接执行（轻任务，改哪几行由守卫读数逐条给出）；合并与清理裁决权在风语者 / 人类指挥官。

## 遗留风险

1. 账本 4 个 OPEN 缺陷（BUG-354 / 361 / 362 / 364）全是 **owner 决策面**（契约变更 / 形态取舍 / 判据宇宙 / 内容取舍），按金条四只出数不代拍。
2. `check_scripts_index` 的子串匹配可被「别的条目正文顺带提到」蒙过（本单已把唯一受害的 fist-gate 升格），但判据本身的形状缺陷仍在——建议后续改成「条目须以 `- \`<name>\`` 抬头形状登记」。

## 后续建议

升版检查单（manifest / USAGE / README 字面量 / 索引 / 重投影）固化成 `fist-gate.py` 的一臂，下次升版当场红出，不再事后靠 5 把尺各报各的。

## 超额内容

无——严格落在「修复已知问题」内。附带发现（fist-gate 假登记）当场修掉，未扩散。

## 来源

- 分支 `fix/version-align-r3` @ `47d7fb50`（+ 本文件所在记忆块 R71）
- 5 把尺改前/改后 rc 对照（同一 worktree 同一环境）
- `scripts/check_bug_refs.py:104-123`（strict 语义逐行实读）
- 先例：BUG-357（0.3.8→0.3.9 同款升版对齐）
