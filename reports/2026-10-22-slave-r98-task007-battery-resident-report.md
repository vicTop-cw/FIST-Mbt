# R98 副机自踩坑收口：守卫电池被常驻脚本挂死（TASK-007 面追修）· 2026-10-22

分支 `slave/ci/task007-battery-resident-r98`，基点 `gitcode/main` = `99bacbe`（开工前 fetch 对表：main 未前进，主机当日另有三支在飞 `fix/bug-refs-ledger-backfill` / `fix/v0310-projection-closeout2` / `fix/dist-snapshot-guard`，任务池仍是 9 单，无新单指派副机）。

## 结果摘要

- **发现的缺陷在 main 上，且是我自己 TASK-007 那一单引进的**：`run_guards.py` 的宇宙自动补格把 `scripts/*.py` 全量卷进来，
  对没被 `SPECIAL_CASES` 点名的脚本一律 `case(script)` **裸跑**。其中 `fist-mbt-http.py` 与 `fist-mbt-web.py` 是
  `serve_forever()` 的常驻服务 —— 实测单独跑 15s 被 timeout 杀掉（rc=124），**永不退出**。
  于是电池里第 57/58 格把整轮挂死（我这一轮跑到第 56 格后停了 6 分钟以上，无任何后续输出）。
- **为什么 CI 照不出来**：`.github/workflows/ci.yml` 里只跑 `run_guards.py --selftest` 与 `--list`（两条都不执行格子），
  全量电池从来只有人在本地跑 —— 而本地一跑就挂，挂掉的现场又被读成「日志空 = 命令没跑」。这条我昨天写进记忆的判语是错的，本轮推翻并改正。
- **交付（四件，全部现读、不抄名单）**：
  1. `is_resident_src()` / `is_resident()` 分类器：源码含 `serve_forever(` 或 `run_forever(` 即归类为常驻服务；
  2. `build_cases()` 自动补格**跳过常驻脚本**（手写的有界格子不受影响 —— 豁免是形状豁免，不是身份豁免）；
  3. `face_report()` 把常驻脚本从「缺执行面」里摘出来的同时**逐条点名**，`--list` 与 `--selftest` 都把「常驻豁免 N」打在读数行上；
  4. 每格限时：`--case-timeout`（默认 600s）超时 ⇒ 打 `TIMEOUT` 并进 `fails` 判红点名，「尺子不结束」不再可能被读成「没输出」。
- 自检 **13 格 → 19 格**；`--selftest` 现状读数：`86 把尺 / CI 面 28 / 电池面 86 / 缺面 0 / 常驻豁免 2`。
- 修后**全量电池第一次跑到底**并给出可复核读数：`格数 97 / 失败 41 / SKIP 5 / 缺执行面的尺 0`，电池自身 `RC=1`（判红，不是挂死）。41 条按原因分四族逐条点名，见「证据」。
- 顺带抓到两条更重的「电池不隔离」实锤（绿格子写脏跟踪面）：非幂等的 `patch_router_config_caf_field.py` 把 `src/router` 弄成重复字段（编译必红）、`mcp_bug_loop.py` 把演示 bug 追加进真台账 `memory/bugs.md`；两处工作树脏面已还原，证据包留在仓外 `$HOME/r98_battery_residue.patch`。

## 证据

- 常驻格裸跑实测：`timeout 15 python scripts/fist-mbt-http.py` ⇒ rc=124，日志最后一行 `FIST-Mbt HTTP bridge listening on port 3000`。
- main 上的裸跑格点名：`[c['name'] for c in CASES if c['script'] in ('fist-mbt-http.py','fist-mbt-web.py')]` ⇒ `['fist-mbt-http.py ', 'fist-mbt-web.py ']`，电池格数 99。
- 三支变异台各咬一个失效方向（内存里改源码后 exec，绝不落盘变异件）：
  - 去掉「跳过常驻」⇒ `resident-face-is-named-not-silent` 红（rc=1）；
  - 把豁免改成静默丢弃（`resident=[]`）⇒ `repo-current-has-no-orphan-guard` 红（G1 把它们读成缺面孤儿）；
  - 分类器失明（marker 换成永不命中串）⇒ `resident-src-flags-serve-forever` 红。
- 修后 `--list` 尾部读数：`尺 86 把 / CI 面 28 / 电池面 86 / 缺执行面 0 / 常驻豁免 2`，两把常驻服务各带一行「（常驻服务：serve_forever，不裸跑）」。
- **全量电池首次跑到底的读数**（`$HOME/battery_r98.log`，21688 字节，本次由本单修复后才第一次拿得到）：
  `G1 通过：86 把尺全部有执行面（CI 28 / 电池 86）；常驻服务 2 把不裸跑` ⇒ `格数 97 / 失败 41 / SKIP 5 / 缺执行面的尺 0` ⇒ 电池自身 `RC=1`（判红，不是「没跑完」）。`TIMEOUT` 出现 0 次。

  41 条 FAIL 按读数里的原因串分成四族，逐条点名（不打包成「41 个新 bug」）：
  - **A 主线预存红 8 条**（别的单在修，本单不代修，只点名 rc 与成因）：`check_doc_surface.py` rc=1（USAGE.md 自述 0.3.9 != moon.mod 0.3.10，主机 `c27d6e7` 已修）、
    `check_scripts_index.py` rc=1（`fist-pr-automator.py` 未登记，副机 r96 分支已修）、`check_release_asset_names.py` rc=1、`check_plugin_sync.py` rc=1、
    `gen_plugins.py --check` rc=1、`check_host_installable.py` rc=1（DSH manifest 0.3.9 != 0.3.10）、`check_bug_reference_integrity.py` rc=1（判定面 17 条 > 上限 1）、`cli_flag_probe.py` rc=1（帮助面不回显版本）。
  - **B 自动裸跑的「形状不匹配」27 条** —— 与本单同一个根假设的另一半：`build_cases()` 认为「裸跑 rc=0 即自证」，
    但这一族脚本要么要求参数、要么需要活体 server，注定不可能 rc=0。
    · 要求参数（6）：`issue_scan.py` / `output_validate.py` / `fist-pr-automator.py` / `laya_decide.py` 打 usage rc=1，`score_gate.py` / `fist-gate.py` rc=2（argparse）；
    · 需要活体 MCP server 且名为 `T0` 的任务（13，回执串一致 `task not found: T0`）：`atgc_selfdrive_demo` `award_demo` `dispatch_verify` `enhance_verify`
      `enrich_selfdrive` `lesson_chain_selfdrive` `lesson_selfdrive` `log_fix_selfdrive` `mcp_smoke` `pentad_fist` `plan_gradient_verify` `scratch_selfdrive` `task_challenge_verify`；
    · 缺前置产物 / 缺依赖 / 断言类，需逐格复跑才能定因（8）：`blackbox/patch_esm_main.py`（要先 `moon build --target js`）、`gen_apply_pdf.py`（`No module named 'fpdf'`）、
      `fist_mbt_mcp_client.py`（WinError 267 目录名称无效）、`_run_check_t0r21.py`（`spawn` WinError 2）、`simulate_head_commit.py`、`mcp_bug_loop.py`、`map_verify.py`、`evolve_critic_verify.py`。
  - **C 判据诚实、电池期望值没跟上 2 条**：`blackbox/e2e_native_heap_probe.py` got=**3**、`blackbox/e2e_reserve_xproc.py` got=**3**。
    退出码契约里 3 = 「平台不给量 / fail-closed 拒绝出数」，这两把尺按契约正确自拒；是电池的 `expect=0` 把它们误读成红 —— 应改写成 `gated()`/`expected(3)`，不是改脚本。
  - **D 本机环境与网络 4 条**：`blackbox/e2e_irm_line.py`（schannel SSL/TLS 握手失败，走系统代理那一族，同刻 curl 对照 exit=35）、
    `blackbox/e2e_mirror_install.py`、`blackbox/e2e_upgrade_mirror.py`、`blackbox/e2e_heartbeat_xproc.py`（沙箱/构建产物依赖，本机无 pwsh 与公网 Release）。
  - SKIP 5 条是手写格子的前置文件（`temp/pt27.log`、`temp/chk47.json`）不存在 —— 而 `temp/` 正是 `cleanup_artifacts.py` 那格按职责清空的地方，
    所以「先跑生成格、再跑消费格」在电池里天然不成立（本单没动它，读数里如实挂着）。

- **本轮新抓到的两条「电池不隔离」实锤**（都是电池自己写进跟踪面的，11:43 同一分钟，见 mtime）：
  1. `scripts/patch_router_config_caf_field.py` 自称幂等（注释「已有则不重复」），实际第 38 行的门是 `not IDEMPOTENT_RE.search(line)` ——
     查的是**刚匹配到的 `use_laya:` 那一行**，而那一行永远不含 `use_caf_memory` ⇒ 门恒真，每跑一次就多插一份。本次跑出 `rc=0 … 总计: 18 处`（绿灯），
     把 `src/router/model_router_wbtest.mbt` 的 `use_caf_memory: false,` 从 17 份变成 34 份、`router_state.mbt` 的 `use_caf_memory: cfg.use_caf_memory,` 变成同一 record 字面量里两份 ⇒ **struct literal 重复字段，编译必红**。
     副机已把这三个被写脏的跟踪文件还原（残留 diff 存 `$HOME/r98_battery_residue.patch`，163 行，未落仓内）。
  2. `scripts/mcp_bug_loop.py` 把演示用的 `## BUG-379 [2026-10-22T03:43:27Z] [medium] OPEN / summary: BUG-5 resolved_path check` **追加进了真台账 `memory/bugs.md`**
     —— `FIST_DB_PATH` 早在仓外，但账本路径是仓内相对路径，隔离门（`check_demo_isolation`）管的是 db，管不到这条。同批已还原。
  这两条是「裸跑即自证」假设最坏的后果：绿格子不止是噪声，还会**改走样的源码留在工作树里**。上一轮（R96）我把同形状的 `src/router` 脏面判成「主机在飞改动」，本轮据 mtime + 计数器证伪并改正：**是本机那格补丁脚本自己写的**。

## 门禁面（本单改动集实测）

- `python scripts/run_guards.py --selftest` ⇒ rc=0，`SELFTEST OK（19 格 …）`，现状读数行 `86 把尺 / CI 面 28 / 电池面 86 / 缺面 0 / 常驻豁免 2`。
- `python scripts/fist-gate.py --scan` ⇒ rc=0（冲突标记普查全 0，本单无 marker 残留）。
- `python scripts/check_py_stdout_encoding.py --all` ⇒ rc=0；`python scripts/check_exit_code_contract.py` ⇒ rc=0。
- 主线预存红（本单不代修，点名 rc 与成因）：`check_scripts_index.py` rc=1（`check_bug_refs.py` / `fist-pr-automator.py` 未登记 —— 副机 r96 分支已修）、
  `check_doc_surface.py` rc=1（USAGE.md 自述 0.3.9 != moon.mod 0.3.10 —— 主机 `c27d6e7` 已修）。
  本单为纯 Python + 文档改动，未碰 `.mbt`，故 `moon fmt/check` 面不在本单作用域（工作树里那 18 处重复字段是电池格写脏、已还原，见「证据」）。

## 任务分配记录

副机本机自驱：金条四下不再拆子代理（单文件、需要我在场观测挂死现场，委派反而丢证据）。观测手段全部是本地判据，未触碰网络与远端分支。

## 资源消耗

全量电池在本机耗时以「格子」计：跑到第 56 格约 6 分钟，卡死格之后由限时机制接管。moon 侧格子走 shim（`MOONC_OVERRIDE=C:/Users/Administrator/.moon-shim/shim.exe`），
`FIST_DB_PATH` 与日志一律指到仓库外（`$HOME/battery_r98.*`）—— 后者是本轮的另一条实测结论：`cleanup_artifacts.py` 本身就是电池的一格，它按职责清空 `temp/`，会把写在 `temp/` 的电池日志删掉。

## 遗留风险

1. 全量电池的**收尾读数**依赖本机工具链（shim + Node 24），CI 面不含这一格，所以「电池能跑完」这件事在 CI 上仍然没有执行面 —— 建议把 `run_guards.py --selftest` 之外再加一条 `--list` 已够，但「常驻豁免」清单若被改瞎，只有变异台能抓到，而变异台不在 CI 里。
2. `--case-timeout` 默认 600s 是本机量出来的；`moon` 系格子在慢机上可能合法超时，那时读数会显示 `TIMEOUT` 而不是「未跑完」—— 这是有意的（宁可假红不要无输出），但需要读数的人知道这一档语义。
3. 本单不改 CI 步骤位置、不改 `serve_forever` 那两个脚本本身（它们没有有界自检模式，加一个属于另一个单）。

## 后续建议

- 若要给 http/web 两个 bridge 真正的执行面，正确形状是各加一条 `--selftest`（起在临时端口 → 自打 `/health` → 关掉 → 退出），
  然后在本单的分类器豁免之上手写 `case(script, "--selftest")` 把它们请回宇宙——这一步做完，「常驻豁免 2」会自己变成「常驻豁免 0」，读数会盯着这个变化。
- `TASK-007` 的验收面应追加一条「自动扫描不得把不会自己结束的脚本卷进电池」，否则下一个 server 脚本仍会靠同一形状挂死电池。
- **同一根假设还差另一半（本单只收了「会挂死」，没收「形状」）**：`build_cases()` 的「裸跑 rc=0 即自证」对 B 族 27 条同样不成立。
  最小改法是让自动注册认「有界自检面」而不是认「脚本存在」：只有源码里出现 `--selftest`（或 `SELFTEST` 分支）的脚本才自动成格，
  其余一律走 `SPECIAL_CASES` 手写 —— 这一改会立刻把电池从 97 格缩到 ~70 格，缩掉的那些必须逐条补手写格或显式豁免，属 owner 裁决项，副机不自作主张。
- **电池隔离门（新单，比上一条更急）**：`check_demo_isolation` 只管 `FIST_DB_PATH`，管不到「电池格写跟踪面」。
  建议形状：电池跑完立刻 `git status --porcelain`，凡出现本单作用域外的脏文件 ⇒ 打 `POLLUTED <path>` 并 rc=1（判据不叙述、只看盘面）。
  两把现成的违例进料：`patch_router_config_caf_field.py`（rc=0 却写 18 处 `.mbt`）、`mcp_bug_loop.py`（rc=1 且往真台账 `memory/bugs.md` 追加 `## BUG-379`）。
- `patch_router_config_caf_field.py:38` 的幂等门本身是错的一行：`not IDEMPOTENT_RE.search(line)` 查的是刚匹配到的 `use_laya:` 行（永不含 `use_caf_memory`），
  按注释本意应查**下一行**。一行改动 + 一支「连跑两次必须与跑一次同字节」的自证，是独立小单的形状（本单没动它，避免把「电池形状」与「补丁脚本」两件事混进一个 MR）。

## 超额内容

- 除修挂死之外顺带把「尺子不结束」这一类失败整体收进限时语义（`TIMEOUT` 判红点名），这是 TASK-007 验收没要求的一格。
- 分类器写成纯函数 `is_resident_src(src)` 而非只读文件，使变异台能在不落盘的前提下证明「分类器失明」这一方向可红。
- 本单验收只要求「电池不再挂死」；额外交付的是**第一次可读的全量电池读数 + 41 条红的四族归因**，以及两条电池不隔离实锤（含绿格子改走样源码这一族）。

## 来源

- `scripts/run_guards.py`（本单改动面）、`.github/workflows/ci.yml`（CI 只跑 `--selftest`/`--list` 的行位）、
  `scripts/fist-mbt-http.py:417`、`scripts/fist-mbt-web.py:575`（`server.serve_forever()`）、
  `scripts/cleanup_artifacts.py:12`（「清空 temp/」职责，即电池日志消失的真因）、
  记忆条目 `project-slave-unit-close-out-traps` 第 11 条（本轮据实测改正）。
