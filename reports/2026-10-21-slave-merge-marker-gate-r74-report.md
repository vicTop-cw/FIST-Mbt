# R74 报告 · 冲突标记硬门禁接线 CI（slave/ci/merge-marker-gate-r74）

## 结果摘要

`scripts/blackbox/check_merge_markers.py`（510b1ff 落的 211 行活判据）落仓 5 小时**从未接进 ci.yml**——f259d79（17:15）清完 9 个文件的冲突标记，2 分钟后 259b56a（17:17）又把 3 份 issue_scan 文件的标记提交进来而 CI 无感。本单把守卫接上岗：

1. **`.github/workflows/ci.yml`**：在 Migrate 之前（沿用「挂在 Migrate 之后的判据会被 skip」的实测教训）加 `Merge-marker gate` 步——`--selftest`（五格：干净不误红 / 未解决必红 / 半截必红 / 提及字面量不误红 / 空扫描自拒）+ 实跑跟踪面，两行全绿才放行后续构建。
2. **`scripts/README.md`**：补登记条目（含血证一句话：脚本落了没接线，标记二次入库无人拦）。

## 资源消耗

半小时级；取证 5 次判据实跑 + 1 次 YAML 解析验证。

## 任务分配记录

副机单兵完成。分支 `slave/ci/merge-marker-gate-r74` **基于 r71 分支**（`slave/fix/issue-scan-min-severity-r71` @ 320b1c5）叠栈。

## 叠栈与合序（重要）

- **先合 r71，再合本单**：master 259b56a 树上守卫红（3 处标记）且构建崩；r71 树上守卫绿（rc=0）、可编译。本 MR 含 r71 的 2 个 commit。
- **f259d79 连带删除的「Plan-landing ratchet gate」CI 步骤本单不恢复**：r71 树上 `check_plan_landing.py` 仍是 SyntaxError 版（r72 修），恢复即双重红；留待 r72 合入后由主机裁决（gate 棘轮 36>25 是 BUG-367 ④ 的人的决定，判据不代答）。

## 遗留风险（预存红，点名 rc 与成因，不代修）

- `check_scripts_index.py` rc=1：3 条未登记（`check_doc_surface.py` / `commit_bug335_lock.ps1` / `slave-branch-merge.ps1`）== r71 基点预存，r73 MR 已修。
- `check_bug_reference_integrity.py` rc=1：判定面 11 条悬空 == 基线。
- `check_plan_landing.py --gate` 36>25：BUG-367 ④ 棘轮上限，人的决定。
- `moon fmt --check` rc=127：本机 ICE（零 `.mbt` 改动，不受影响）。

## 后续建议

1. 合序：r71 → r72 → r73 → 本单；r73 已含 BOM/README/电池期望清账，与本单零文件交叠（除 README 各补一条目，位置相距远）。
2. R58（主机 `fix/guard-census-covers-blackbox`）把普查宇宙扩到 blackbox 后，本单接的线正好让这把尺满足「CI 或电池有一格」。
3. plan-landing gate 步骤恢复建议挂到 r72 合入后的收尾单，与 BUG-367 ④ 上限裁决同批。

## 超额内容

无。R73 报告误判（「守卫漏检」）已在 r73 分支 erratum commit（177bb8b）更正，本单只承接其结论。

## 来源

- 基点：`slave/fix/issue-scan-min-severity-r71`（320b1c5）；分支：`slave/ci/merge-marker-gate-r74`
- 证据：selftest 五格 rc=0、实跑 rc=0、YAML 42 步含新步、`temp/ci_master.yml`（master 基线对照）
- 关联：510b1ff（脚本落地无接线）、f259d79（清扫+连带删步）、259b56a（标记二次入库实证）
- 记忆：`memory/2026-10-21.md` R74 节
