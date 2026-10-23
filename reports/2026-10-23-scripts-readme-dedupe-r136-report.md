# R136 · scripts/README.md 结构去重 + check_doc_dup 硬化接线

- **轮次**：R136（副机）
- **分支**：`slave/fix/scripts-readme-dedupe-r136`（base = `gitcode/master` `92d0edba`）
- **模式**：fix_and_merge（文档真源重整 + 判据硬化）
- **交付物**：`scripts/README.md`（1144→272 行）、`scripts/check_doc_dup.py`（按块重写）、
  `scripts/run_guards.py`（+2 电池格）、`.github/workflows/ci.yml`（Migrate 前加预检步）、
  `docs/2026-10-20-slave-tasks.md`（行号锚点随插入平移）

## 结果摘要

`scripts/README.md` 被多轮合并反复拼接成 1144 行 / 247 KB：**117 个脚本名对应 341 个登记块**，
同名最多 11 份（`fist-gate.py`），读数互相打架（`run_guards.py` 一条并存 26 把尺/24 把尺等四种说法）。
R48 的 `check_doc_dup.py` 用「>150 字的长条目行」判定，短副本全部滤掉，于是这份文件在旧尺下
**照报绿**；而它只被电池的自动无参格跑到，`--selftest` 与 CI 面都没有它。

本单把 README 重整为 **272 行 / 115 个登记块（117 个脚本名，一行双名的那块保留）**，并把尺改成按**整块**判定（含续行、
无长度门槛），补 21 格真断言自检，四面接线（电池裸跑+自检 / README 自登记 / BATTERY-REGISTRATION
锚点 / ci.yml 预检步）。

## 证据 A · 缺陷在场（修前）

```
$ python scripts/check_doc_dup.py --paths <HEAD 版 scripts/README.md>
scripts/README.md：1144 行，登记块 341，重复名字 38 个（冗余 232 块 / 浪费 66168 字节）
rc=1
```

旧实现对同一文件：`rc=0`（长度门槛 + 行级判定，短副本与续行均不可见）。

## 证据 B · 修复（修后现读）

```
$ python scripts/check_doc_dup.py
scripts/README.md：272 行，登记块 115，无重复登记
rc=0

$ python scripts/check_doc_dup.py --selftest
SELFTEST OK: 21 格（短条目/整块/散文排除/多名字/--fix 整块删与幂等，全部真断言）
rc=0
```

- 无损性：修前 117 个名字 → 修后 117 个（配对行 `lesson_selfdrive.py` / `scratch_selfdrive.py`
  作为一行双名字保留，故块数 115 < 名字数 117）；`missing=[]`、`dups=[]`、非逐字保留块 `[]`（保留块全部逐字取自原文）。
- `--fix` 在副本上的实测：1144 → 616 行、115 块、0 重名；本单的 272 行是人工重整（分三组 + 历史补记），
  不是机械删除的产物。
- 推后电池终读（`run_guards.py`，含本单两格）：**格数 69 / 失败 0 / SKIP 5 / 缺执行面 0，rc=0**；
  其中 `check_doc_dup.py` = `272 行，登记块 115，无重复登记`、`--selftest` = `21 格`。
- 四面接线现读：`check_battery_count_doc.py` PASS（`rulers=89 ci=43 battery=51 missing=0 gate=59 exempt=27 unclassified=5`）；
  `ci.yml` 新步挂在 `Migrate mooncakes dep manifests` **之前**；`check_ci_step_position.py` 现读仍为
  预存红 `35 > 34`（本单未加一条，步子在 Migrate 前）。
- 回归：`moon check` **0 errors**（508 warnings，均为存量）；`check_scripts_index` / `check_doc_surface`
  （J1-J16 全绿）/ `check_selftest_inventory_doc`（36 族）/ `check_slave_task_list` / `check_plan_landing`
  现读与本单前一致。

## 证据 C · 反向对照

- 散文条目不计登记块：`- 这一条是说明，不是脚本登记` 在自检 `prose-bullet-not-entry` 格断言不识别。
- 表格行不计登记块：`| a | b |` 在 `table-row-not-entry` 格断言不识别。
- 多名字块删不得：`fix-keeps-unique-multi-name` 格断言「某名字只在这一块登记过 ⇒ 整块保留」，
  不替人做丢登记的决定。
- `--fix` 幂等：`fix-idempotent` 格二次运行行数不变。
- 真相自证：修前 rc=1 / 修后 rc=0 的两端都在上面 A/B 两段留了逐字输出。

## 遗留风险

1. **README 全场重写的并发冲突面**：本单把 1144 行压到 272 行，任何并行分支对 `scripts/README.md`
   的追加都会撞车（建议并行分支后合时按「本单为基 + 补回自家条目」处理）。
2. **`check_ci_step_position.py` 预存红 `35 > 34`**：本单未变（新步在 Migrate 前），按账本口径登记为
   预存红、不代修；升档是人的决定。
3. **行号锚点的易腐性**：本单对 `ci.yml`/`run_guards.py` 的插入使 `docs/2026-10-20-slave-tasks.md`
   的锚点整体位移（尺报 B3×10 + B4×1 + D1×1），已按 R126 立的纪律逐条改回真行号并记入该文件更新日志；
   该面每次动 ci.yml/run_guards.py 都会再撞一次，长期出路是锚点带记号（已在该文件 §1 纪律中）。
4. **电池 SKIP 5 格**：依赖 `temp/pt27.log` / `temp/chk47.json` 的运行态前置，本机不具备，与本单无关。
5. **`whisperer.py --fast` 在本机不可用（本单实测，R137 候选）**：`step0_head_safety()` 在
   `origin/main != gitcode/main` 时**无条件**执行 `git push origin <gc>:refs/heads/main <gc>:refs/heads/master --force`
   （`scripts/whisperer.py:61`），与「GitHub 端不用管」的交付约束直接冲突。本单跑到该处时 GitHub 侧不可达
   （`Failed to connect to github.com port 443`），push 子进程挂在凭据管理器上，已被人工中止；**未发生远端写入**。
   fast/full 两模式都会走这段，修法是给镜像同步加显式开关（默认关）。
