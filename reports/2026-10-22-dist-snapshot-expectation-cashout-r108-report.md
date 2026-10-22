# R108 · 兑现 `check_dist_snapshot` 的预存红期望（副机自立项 · 2026-10-22）

## 结果摘要

主线 `866e2e65` 把发布快照 `dist/fist-mbt.js` 刷到与 `moon.mod` 同版（0.3.10）之后，
`scripts/run_guards.py` 里我上一单登记的 `expected("check_dist_snapshot.py", 1, ...)`
**反过来现形**：电池报 `FAIL check_dist_snapshot.py got=0 expect=1`。
按本文件自订的律「预存红照写期望值 + 依据；被检内容修好后这一格自己翻红，逼下一位把期望改回 0」
⇒ 本单就是那一次兑现：`expected(...)` → `case("check_dist_snapshot.py")`，**依据随期望一起删**
（留着那句「本机 bundle 比快照大」就是下一颗漂移雷）。
这一格自此变成真门禁：快照版本再落后 `moon.mod` 会直接判红，而不是躲在「已知红」里。

- 只动 `scripts/run_guards.py` 一格（+3/−3），不动被检脚本 `check_dist_snapshot.py`，不动宇宙与旗标。
- 车道纪律：文案修尺那一单（R107，`slave/fix/merge-markers-headline-r107`）不带期望值改动，
  期望车道单独成单 ⇒ 两 MR 文件面零重叠。

## 验收读数（本机实跑，非自述）

- `python scripts/check_dist_snapshot.py` ⇒ **rc=0** `PASS dist 快照：快照版本 0.3.10 == moon.mod 0.3.10`；
  `--selftest` ⇒ **rc=0**（8 格：版本解析去重 3 档 + 判定 5 档）。
- `python scripts/run_guards.py --selftest` ⇒ **rc=0 / 34 格**（格子数未变 ⇒ 无 README 格数联动）；
  `--list` ⇒ **rc=0 / 缺执行面 0**，普查读数未变（尺 80 把 / CI 面 39 / 电池面 42 / 常驻豁免 2）。
- 期望格计数：`expected(` 由 13 → **12**，`case(` 由 32 → **33**（`grep -c` 现读，不手数）。
- `check_doc_surface` / `check_scripts_index` / `check_selftest_inventory_doc` / `check_publish_payload`
  四把尺在改后同棵树现读（见下节推后权威读数）。
- 全量电池（推后复跑，权威）：见文末「推后读数」。

## 预存红点名（rc + 成因，均非本单元引入）

| 尺 | rc | 成因 | 归属 |
|---|---|---|---|
| `blackbox/check_merge_markers.py` | 1 | 主线跟踪面含 gitlink `.agents/worktrees/fix/display-rank-boundary`（mode 160000）⇒ 判据读不到正文；电池里已按 `expected(...,1)` 记账，出路是 `git rm --cached` 该条目 | 主线那一单（别人的 worktree 注册面，我不代删） |
| `fist-gate.py` | 2 | fmt 段依赖 `git diff` 管道在本机退化 ⇒ 按设计 DEGRADED；本机 `moon fmt` rc=127（`Moonfmt.make_directory` ICE，预存） | 实体机/CI 复跑 |
| `check_ci_step_position.py` | 1 | CI workflow 位置违规计数 > 棘轮上限 | `docs/tasks/backlog` 那一单 |
| `check_backlog_status_staleness.py` / `check_scripts_naming.py` / `cleanup_artifacts.py --check` | 1 | 任务池状态落差 / 命名棘轮 / 工作树运行态脏——三格仍按期望命中，不是本单面 | 各自那一单 |

## 任务分配记录（金条四）

指挥官只做分流与终审：本单由副机自查电池红面后立项（改一格期望），
证据全部为本机实跑读数；被检内容（dist 快照）由主线 `866e2e65` 修好，本单元不代刷快照
（刷快照属发布流程动作，不在电池里做——这条依据本来就写在被我删掉的那句里）。

## 资源消耗

1 个文件 / 1 格改动，读数取自 3 次实跑（被检尺 + 电池 selftest + `--list`）；无 LLM 调用、无网络写操作。

## 遗留风险

1. 本单把 `check_dist_snapshot` 变成真门禁后，**副机侧**若用不同代 moonc 重跑 `refresh_dist.py`
   会重新造红。这是设计意图（红＝快照与 moon.mod 脱钩的现场证据），但下一位可能又是「改期望」了事；
   报告里把「依据要一起删」和「这一格已是门禁格」写死，供对照。
2. 主线仍在推进：交单窗口内 `gitcode/master` 若再动，本单需按现读重跑（`fetch --prune` + `rev-list --left-right --count`），
   不看存档 tip。

## 后续建议

- 给 `expected(...)` 加**成因指纹**（不只是 rc 数）：本轮 `check_scripts_index` 出现过「expect=1 仍命中但成因已从
  『素材件未登记』换成『新尺未登记』」的同码换因形状，只比 rc 会把新债读成旧债。
- 预存红表列建议加「兑现次数」列：本仓这条律已实战三次（R106 三格 / R106 追记二 / 本单），
  写明次数能防止有人把「登记红」当成免检牌。

## 来源

- 主线提交：`gitcode/master 866e2e65`（README 去重 378 行 + 登记 `check_delivery_gap.py` + dist 快照刷到 0.3.10）、`f2413472`（merge R106 分支）。
- 真源改动：`scripts/run_guards.py`（`expected` → `case` 一格 + 兑现注释）。
- 读数：本机 `check_dist_snapshot.py`（rc=0）、`run_guards.py --selftest`（rc=0 / 34 格）、`--list`（rc=0 / 缺执行面 0）。
