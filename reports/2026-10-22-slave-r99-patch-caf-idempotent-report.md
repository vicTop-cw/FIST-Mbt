# R99 修尺：补丁脚本的幂等门查错行 ⇒ 绿格子写脏 src/router · 2026-10-22

分支 `slave/guard/patch-caf-idempotent-r99`，基点 `gitcode/main` = `c03d78c`（开工前 fetch 对表：main 已从 `99bacbe` 前进一格，主机当日新落 P0-2 Claim 军衔硬门；任务池无新单指派副机，本单是 R98 全量电池读数里当场抓到的一把坏尺）。

## 结果摘要

- `scripts/patch_router_config_caf_field.py` 自称幂等（正文注释写着「已有则不重复」），实际门是 `if m and not IDEMPOTENT_RE.search(line)` ——
  查的是**刚匹配到的 `use_laya:` 行本身**，而那一行永远不含 `use_caf_memory` ⇒ 门恒真。每跑一次就往同一个 struct literal 里再插一份同名字段：
  `src/router/model_router_wbtest.mbt` 的 `use_caf_memory: false,` 17 → 34 份、`src/router/router_state.mbt` 的 `use_caf_memory: cfg.use_caf_memory,` 变双份
  ⇒ **struct literal 重复字段，编译必红**，而回执打的是 `rc=0 … 总计: 18 处` 的绿灯。R98 的全量电池把这格跑了不止一次，工作树就是这样被写脏的。
- 第二处独立缺陷：退出码反向 `return 0 if total > 0 else 1` ⇒「盘面已对齐、本次补 0 处」这一正确稳态被读成红，「又插了 18 处」被读成绿——
  与本仓 BUG-369 退出码契约族同一形状（自述与实现不同色）。
- 交付五件：① 拆出纯函数 `patch_lines()`，幂等门改查**下一行**；② `patch()` 只在真要改时写盘 ⇒ 补 0 处不改字节、不刷 mtime（不白触发一次 moon 重建）；
  ③ 三档真码：`0` 已对齐或已补齐、`1` 目标不存在或盘上没有 `use_laya:` 面（拒绝空转报绿）、`2` 读写异常与自检坏；
  ④ `--selftest` 七格，含一支把门改回旧形状的变异台（证明自检能红）；⑤ `run_guards.py` 挂 `case("patch_router_config_caf_field.py", "--selftest")`
  ⇒ 脚本名被 `SPECIAL_CASES` 点名后，自动补格不再裸跑这个会改跟踪面的补丁。

## 证据

- 自检：`--selftest` ⇒ rc=0，`格数 7 / 失败 0`，`SELFTEST OK（7 格：干净输入补一份且落在 use_laya 之后 / 第二次跑逐字节相同 / 第三次跑仍相同 / 末行就是 use_laya 不越界 / 没有 use_laya 面时 matches=0 可见 / 缩进保真 / 变异台把门改回查当前行必红）`。
- 真仓连跑两遍（本次实测）：两遍都是 `补 0 处` / rc=0 / `总计: 0 处（盘面已对齐，未改任何字节 / 未刷 mtime；重跑安全）`；
  `git status --porcelain -- src/` 空；`sha1sum src/router/model_router_wbtest.mbt` 跑前跑后同为 `bdfe2ee0d75559cabc20cdf23b66abb52075a033`；
  `stat -c %Y` 前后同一秒；`grep -c "use_caf_memory: false,"` 仍是 17（旧形状在这两跑里会各插 17 份，正是 R98 现场读到的 34）。
- 变异台只跑在自检内（不落盘、不碰仓）：旧形状 `bc1=1 bc2=1` 且第二次结果与第一次不同字节 ⇒ 尺子能红，自检不是摆设。
- 电池面：`run_guards.py --list` ⇒ `尺 89 把 / CI 面 28 / 电池面 89 / 缺执行面 0`，该脚本只有一格且带 `--selftest`；
  `run_guards.py --selftest` ⇒ rc=0（13 格，现状读数行同上）。

## 门禁面

- `run_guards.py --selftest` rc=0；`check_exit_code_contract.py` rc=0（本单新增的 0/1/2 三档与自述同色）；`check_py_stdout_encoding.py --all` rc=0。
- 预存红点名不代修（属别的 lane）：`check_scripts_index.py` rc=1 —— `check_bug_refs.py`、`fist-pr-automator.py` 未在 `scripts/README.md` 登记（副机 r96 分支已修这两条），
  且 main `c03d78c` 新落的 `fist-task-pool.py` 同样没登记（同族第三件，属主机那条 lane）。

## 任务分配记录

副机本机自驱单（金条四）：单文件判据修复 + 一支电池格子，需要现场复现与连跑取证，不拆子代理。除 fetch 与本单分支 push 外未触碰远端。

## 资源消耗

进料来自 R98 那一次全量电池（约 20 分钟，仓外日志）；本单自身只跑 `--selftest`、真仓连跑两遍与四把门禁，全部秒级。`FIST_DB_PATH` 与日志一律指仓外。

## 遗留风险

1. `FILES` 写死两份目标文件、字段名写死 `use_caf_memory` —— 这脚本本就是「P2c 一次性补丁」的形状，长期该退役；本单只把它从「写脏盘还报绿」修成「诚实稳态」，没替它做通用化（那是 tidy 单的活）。
2. 幂等门按**下一行**判定：若有人把 `use_caf_memory` 挪到 record 里别的位置（不再紧跟 `use_laya:`），这一门会重新插一份。自检第 1/2 格钉的是当前形状。
3. `mcp_bug_loop.py` 往真台账 `memory/bugs.md` 追加演示条目那一半本单没动（R98 报告已立案点名）——那需要「电池隔离门」（跑完断言 `git status` 无作用域外脏文件），是独立一单的形状。
4. 副机 r98 分支基线（`99bacbe`）落后 main 一格（`c03d78c`），且 r98 与本单都碰 `scripts/run_guards.py`：r98 加分类器与限时，本单只加一行 `case(...)`。两面不重叠但同文件，`git merge-tree` 对表留给 owner。

## 后续建议

1. 立「电池隔离门」：`run_guards.py` 跑完立刻 `git status --porcelain`，出现本单作用域外的脏文件 ⇒ 打 `POLLUTED <path>` 并判红。现成两把违例进料：本单这把（rc=0 写 18 处 `.mbt`）与 `mcp_bug_loop.py`（往真台账追加 `## BUG-379`）。
2. 给「一次性补丁脚本」立声明锚点（如 `# TEMPORARY:`），让 `check_scripts_index.py` 要求它们声明「跑完即退役」——否则它们会一直留在电池宇宙里被自动裸跑。
3. 合序：本单不依赖 r98 的分类器，可单独合；若 owner 先合 r98，本单那行 `case(...)` 落在 r98 的自检面之上，读数里「常驻豁免 2」与本单无关。

## 超额内容

- 验收口径只要求「幂等门改对」，本单额外交付：退出码三档改真（原来还反向）、写盘收紧到「只在真要改时写」（mtime 不再被白刷）、七格自检含变异台，
  以及把电池里这格的裸跑换成有界自检（堵住「判据自己改跟踪面」这一类，而不只堵这一把脚本）。
- 顺带现读出 main 新落后仍未登记的第三件 `fist-task-pool.py` 并在报告点名（不代修）。

## 来源

- `scripts/patch_router_config_caf_field.py`（本单改动面：原第 39 行的门、原第 60 行的退出码）
- `src/router/model_router_wbtest.mbt` / `src/router/router_state.mbt`（被写脏现场；R98 已还原，残留 diff 存仓外 `$HOME/r98_battery_residue.patch`）
- `scripts/run_guards.py`（`SPECIAL_CASES` 与自动补格的 `covered` 逻辑）
- R98 报告 `reports/2026-10-22-slave-r98-task007-battery-resident-report.md`（进料出处）
- `AI-DEVELOPMENT-STANDARD.md` 与账本 BUG-369 族（退出码契约口径）
