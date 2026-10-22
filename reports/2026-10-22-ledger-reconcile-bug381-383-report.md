# 账本状态归位：BUG-381/382/383（已修却仍 OPEN）

- 分支：`slave/fix/ledger-reconcile-bug381-383`
- 提交：`46236713`（基线 `803293c2`，`gitcode/master`）
- MR 入口：https://gitcode.com/VictorTop/Fist-Mbt/merge_requests/new?source_branch=slave/fix/ledger-reconcile-bug381-383
- 日期：2026-10-22

## 结果摘要

`memory/bugs.md` 里 BUG-381 / BUG-382 / BUG-383 三条抬头仍标 OPEN，但对应修复提交都已经是 `gitcode/master` 的祖先。本单按账本记账规则把状态归位为 FIXED，补一条点名三号的 `### FIXED(...)` 小记，并重生成四宿主插件投影（账本摘要 18 条待修 → **15 条待修**、339 条已修）。

无代码、无守卫、无接口变更；`bug_list` 与插件态读到的“待修”数字从此与提交面对齐。

## 证据

| 条目 | 修复提交（均为 gitcode/master 祖先，`merge-base --is-ancestor` rc=0） | 现读复验 |
|---|---|---|
| BUG-381（check_mbti_sync 对泛型顶层 fn 双向隐形） | `a0408239` | `python scripts/check_mbti_sync.py` → PASS，24 份 .mbti / **676** 条 pub 声明全有定义 |
| BUG-382（reapply.sh 硬失败于已移除的 mizchi） | `f420c1e7` | `bash patches/sqlite-bug133/reapply.sh --selftest` → 4/4 OK，rc=0 |
| BUG-383（heap 探针钉死旧后端） | `07e23e7d` | `python scripts/blackbox/e2e_native_heap_probe.py --selftest` → rc=0（构建门在非 POSIX 如实 SKIPPED） |

编号映射说明：`f420c1e7` 的提交署名号码是 BUG-380（重录前的旧号）。BUG-382 条目正文的“编号说明”已交代“原 BUG-380 被并行 lane 重新分配后按新号重录”，本单按条目正文映射，不按提交署名猜。

守卫复验（提交 `46236713`）：

- `python scripts/check_plugin_sync.py` → PASS（4 宿主 / 64 个生成文件 / 170 工具 / v0.3.10）
- `python scripts/check_doc_surface.py` → PASS（J3/J4/J6/J7/J8/J9/J10/J11/J12/J13/J14/J15 全过）
- `python scripts/check_bug_reference_integrity.py` → PASS（J1 悬空-注释面 **0**，上限 0）
- `python scripts/gen_plugins.py` → 374 条入账：**15 待修 / 339 已修 / 11 重复 / 9 误报**

全量电池（交付代码 tip）：58 格 / 失败 **1**（预存红，见下）/ SKIP 5 / 缺执行面 0。

## 资源消耗

- 无 `moon build` / `moon test`（纯账本与生成投影面，零 `.mbt` 改动）
- 本地耗时：ancestry 3 发、守卫 4 发、selftest 2 发、电池 1 发；除电池外均为秒级

## 任务分配记录

- 副机自主发现（不在主机 TASK-010..023 任务池内）：对账本全部 OPEN 条目做“提交面 vs 抬头状态”扫描时命中三条。
- 单分支、单提交；未触碰并发 agent 面（`src/server/supervisor_tools.mbt` / `docs/supervisor-prompt-upsert-skill.md` / `slave/fix/supervisor-bool-flags-schema-r110`）。

## 遗留风险

1. **预存红未代修**：电池里 `check_backlog_status_staleness.py got=0 expect=1` 仍红——master 的期望值还按 R111 之前的数据写，R114 分支 `0017069a` 已修同一条。按交付口径不在本单代修，此处点名 rc 与成因。
2. BUG-383 的三档处置虽已按选项①（探针改指 daqing）落地，若 owner 另有裁决可重开本条。
3. `f420c1e7` 的提交署名与账本新号不一致，后来者若只按 commit message 对表会误判；本单在盖章正文里写明了映射。

## 后续建议

1. 把“账本 OPEN ↔ 提交面已修”做成**只报不判**的读数器（与 `check_bug_refs` 同口径），减少靠人肉 `git log --grep` 发现。
2. 编号重录时，在提交标题里同时写旧号与新号（如“原 BUG-380 / 现 BUG-382”），降低映射成本。

## 超额内容

无。

## 来源

- `memory/bugs.md`（BUG-381/382/383 条目、新增 `### FIXED(2026-10-22T08:35:00Z / BUG-381, BUG-382, BUG-383)`）
- 提交：`a0408239`、`f420c1e7`、`07e23e7d`、`46236713`
- 命令输出：见“证据”表与守卫复验清单
