# 2026-10-22 · 副机 R101 · git 面隔离守卫 `check_battery_isolation.py`（副机自立项）

- 角色：副机（FIST 指挥官模式 · 金条四/五/八）
- 分支：`slave/guard/battery-isolation-r101`（基点 `gitcode/main = f656001`）
- 交付：新增 1 把尺 `scripts/check_battery_isolation.py` + `scripts/README.md` 登记 + 本日日志一节

## 结果摘要

给「一条命令跑完之后，git 跟踪面与未跟踪面必须一格未变」立了本仓第一把尺。它不判被包命令成功与否
（那是那条命令自己的契约），只判它有没有动仓库。退出码字母表 0/1/2/4 四档各有实读数，被包命令的 rc
只回显在 `WRAPPED_RC=<n>` 行上、绝不借用本判据的码（BUG-369 抓的就是这种透传不透明出口）。

## 证据

1. `python scripts/check_battery_isolation.py --selftest` → `SELFTEST OK: 9 格（合成违例必红 5 + 干净反向对照 1 + 规则失明对照 3，含 R98 内容漂移那一形）`，**rc=0**。
2. 本仓裸跑（不带 `--`，快照 → 空操作子进程 → 快照）→ `WRAPPED_RC=0` + `ISOLATION=clean`，**rc=0**。
3. 临时沙箱仓盘上九格（每格独立构造 git 视图，跑完即删沙箱）：
   - T1 命令新建未跟踪文件 → rc=1 `POLLUTED untracked-added leftover.py`
   - T2 命令把已跟踪干净文件改脏 → rc=1 `POLLUTED diff-added a.mbt`
   - T3 文件本来已脏（状态 M 两侧不变）、命令再往里插一份 → rc=1 `POLLUTED diff-content a.mbt`（**R98 真实形状**）
   - T4 命令把本来就脏的文件 `git checkout --` 洗掉 → rc=1 `UNDIRTY diff-cleaned a.mbt`
   - T5 命令什么都没改 → rc=0 `ISOLATION=clean`
   - T6 被包命令自己 `SystemExit(3)` → 本尺 rc=0，`WRAPPED_RC=3`（不借用码，反向对照）
   - T7 只 `os.utime` 改 mtime、内容未变 → rc=0（证明「刻意不看 mtime」不是嘴上说的）
   - T8 `--repo` 指到非 git 目录 → rc=2 `FATAL: ... 不在 git 仓里，判据测不到东西`
   - T9 被包命令根本起不来（`WinError 2`）→ rc=2「隔离面未测到，拒绝出数」（空扫描必自拒）
4. 门禁面（基点 `f656001` 实测）：
   - `python scripts/check_exit_code_contract.py` → 「判定面归零（上限 0）」，**rc=0** ⇒ 新尺没添任何一条假契约。
   - `python scripts/check_scripts_index.py` → **rc=1，红的是 3 条预存项**：`check_bug_refs.py` / `fist-pr-automator.py` / `fist-task-pool.py`（均非本单元文件；本尺已在 `scripts/README.md` 登记，未新增红）。
   - `python scripts/run_guards.py --list` → 「尺 90 把 / CI 面 28 / 电池面 90 / 缺执行面 0」，新尺自动进电池：`check_battery_isolation.py CI=- 电池=电池`。
   - `python scripts/check_ps_encoding.py` → **rc=0**（9 个 `.ps1` 全带 BOM 或纯 ASCII，本单元未动 PowerShell）。
   - `python scripts/check_doc_surface.py` → **rc=1，预存红**：`USAGE.md 自述版本 0.3.9 != moon.mod 0.3.10`（主机版本推进留下的落差，本单元没碰 `USAGE.md`，按裁决不代修）。
5. 代码定位：快照与逐块哈希 `scripts/check_battery_isolation.py:50`（`snapshot`）与 `:59`（`diff_map`）；五条规则 `:75`（`detect`）；9 格自检 `:106`（`selftest`）；退出码 2 那一档 `:145`（`fatal`，写 stderr 后由 `sys.exit(main())` 落成，刻意不用 `raise SystemExit("串")`——那形实给 1）；4 那一档 `:207`（`RULER BROKEN`）。

## 分析

- 为什么按 diff 切片取哈希而不是按 `git status` 的行：R98 那一次脏法是「同一个 struct literal 里重复插入一个字段」，
  前后状态字母都是 `M`。若快照取的是 status 行清单，这一形会被读成「前后同一行 ⇒ 没变」，判据照样绿着。
  内容哈希把「状态不变而内容漂移」这一格关掉了，T3 就是钉这一格的。
- 为什么保留 `UNDIRTY` 两档：命令把预先存在的脏洗掉，同样是「改了工作树状态」。R98 那次收场是我手工 `git checkout --`，
  如果电池里有这条尺，读数会直接点名「谁洗了谁」而不是静默——静默正是这类事故第二次复发的原因。
- 为什么不借用被包命令退出码：本尺的 1 有确定含义「git 视图变了」。把别人的 rc 透传成自己的 rc，
  等于让读者无法从码分辨「尺红」与「被测的东西红」，这是 BUG-369 那一族的老形状。

## 资源消耗

- 本轮为落地这一把尺用的工具调用：写判据 + 跑 selftest/裸跑 1 轮、盘上对照 3 轮（其中 2 轮被自家 harness 的 `--repo` 漏传绊住，见「遗留风险」第 3 条）、门禁面 3 支尺 + 电池 `--list`、文档面 2 处落盘。
- 无 `moon` 参与（本单元纯 Python 判据，不动 `.mbt`，不需 `moon fmt`/`moon test`；这点在「超额内容」里按边界说明）。

## 任务分配记录

- 分流：轻任务（单文件新增 + 两处文档追加）→ 副机亲做，未派子代理；派子代理会把「尺必须先证明自己会红」这条判据的对照设计外包出去，反而要再审一遍，不划算。
- 立项来源：副机自立项（不是主机任务池里的 TASK-*）。理由见「结果摘要」前的两条自家实锤，属主机池未覆盖的缺口。

## 遗留风险

1. 本尺**只判「变没变」，不判「变得对不对」**。合法的写盘工具（如生成物同步脚本）被包住时会拿到 rc=1，
   调用方要么给它开豁免面（本尺刻意没内建白名单——加了就等于把判据交给调用方），要么改用「跑完再自己提交」的顺序。
2. 电池目前仍把本尺当**裸跑格**收（自证快照机制在本仓成立），还没有把任何电池格包进 `-- <cmd>` 里。
   接线是下一步：需要一条「哪些格子该包」的清单，那清单本身又要有判据，不宜在这一单里顺手做。
3. 我自己的盘上对照 harness 曾漏传 `--repo`，把 `leftover.py`/`a.mbt` 写进了真仓根（已 `rm`，`git status` 复核干净）。
   这说明 harness 类脚本也该被本尺包住——本尺第一次"抓到脏"就是抓在我自己的测试脚手架上，不是巧合，是这类默认值 `.` 的通用风险。
4. 预存红两条未动（`check_scripts_index` 3 项、`check_doc_surface` USAGE 版本），按裁决不代修。

## 后续建议

- 建议主机把「凡 `Popen` 会改工作树的脚本，跑时挂 `check_battery_isolation.py --`」立成规范条目，与 `check_demo_isolation`（库改道）配成隔离族两翼。
- 建议下一单做电池接线时，先给「该包的格子」列清单并让清单本身可判红（空清单必自拒），再谈白名单。
- `patch_router_config_caf_field.py`（R99 已修幂等门）建议也纳入被包面：它就是 R98 那次脏的来源。

## 超额内容

- 无新增功能、无重构、未动 `.mbt`/`.ps1`/CI workflow；只落 1 把尺 + `scripts/README.md` 一条登记 + 日志一节。
- 未开 MR（按裁决只交链接）。

## 来源

- 实锤①：2026-10-22 R98 全量电池 working tree 读数（`src/router/router_state.mbt` / `src/router/model_router_wbtest.mbt` 重复插入），当日手工 `git checkout --` 收场。
- 实锤②：`scripts/mcp_bug_loop.py` 写 `memory/bugs.md` 的既有路径；`scripts/check_demo_isolation.py` 的覆盖面只到 `FIST_DB_PATH`。
- 规范依据：`AI-DEVELOPMENT-STANDARD.md` 通用 5 条（文档即实现 / 确定性优先 / 增量零回归）与「尺子必须先证明自己会红」；BUG-369 退出码字母表；AGENTS.md 金条五/八。
- 基点：`gitcode/main = f656001`（本分支开工前已 fetch 对表，主仓未落后）。
