# R126 · MCP `run_check` 服务端 spawn 面注入 moonc shim

- 日期：2026-10-22
- 分支：`slave/fix/mcp-server-moon-env-r126`（基线 `gitcode/master` = `ede53f30`，开工与交单前各 fetch 一次）
- 性质：副机自驱迭代自找项（主机任务池无新增 T0/T0r2/T0r3 指派）

## 结果摘要

修掉 moonc `\?\` ICE 的**第三面**：MCP 的 `run_check` 由 server 的 js `spawn` 原语执行，server 被宿主直连
`node cli.js serve` 拉起时不经过任何 Python 入口，R125（`slave/fix/moon-spawn-shim-r125`，尚未并入主线）
那批 `moon_env()` 接线不在链路上 ⇒ `run_check cmd=moon` 的判据仍把工具链缺陷记成任务失败。

- 修复点：`src/server/run_check_js.mbt` 的 `js_run_command` 在 spawn 前构造子进程 env（显式 `MOONC_OVERRIDE`
  优先；Windows 且 `~/.moon-shim/shim.exe` 存在则注入；其他平台/无垫片原样透传），`run_check`/`executor_run`/
  `ocr_scan` 共用这一层。
- 判据：`scripts/moon_test_env.py --selftest` 12→18 格（服务端 spawn 面六格：合规不误红 / 摘 env 必红 /
  摘垫片发现必红 / 摘平台门必红 / 空面自拒 / 真现状面必须绿）；README 与 AGENTS 同批登记。

## 证据（修复前/后同一调用）

    env -u MOONC_OVERRIDE FIST_DB_PATH=<temp>/r126_e2e.db python scripts/fist.py call run_check \
      --task-id T0 --namespace r126 --cmd moon --args '["check","--target","js"]' --timeout-ms 300000

| 时点 | 读数 |
|---|---|
| 修复前 | `status=failed`；`stderr_tail` 含 `Sys_error("\\?: Invalid argument")` 与 `-o "\?\F:\AI\Fist-Mbt\_build\..."`，`ice=true` |
| 修复后 | `status=passed`；`stderr_tail` 为 `Finished. moon: ran 34 tasks, now up to date (506 warnings, 0 errors)`；`ice=false` |

两次 e2e 的 server 进程都在 `env -u MOONC_OVERRIDE` 下启动，任务与检查记录落在 `%TEMP%` 的临时 SQLite（不碰仓库根台账）。

## 判据自证

`server_spawn_env_violations(text)` 是纯函数，静态针四类：垫片发现（`moon-shim`+`shim.exe`）、平台门（`win32`）、
显式值优先（`!env.MOONC_OVERRIDE`）、spawn 调用行必须带 `env`。六格分工：

- `server-spawn-clean`：合成正确形状不误红；
- `server-spawn-env-dropped`：摘掉 spawn 的 `env` 必红（注入不交给子进程 = 白注入）；
- `server-spawn-shim-dropped`：摘掉垫片发现必红；
- `server-spawn-platform-gate-dropped`：摘掉平台门必红（非 Windows 不该被改环境）；
- `server-spawn-face-missing`：空文本自拒并点名缺失文件（不把“没读到”当“合规”）；
- `server-spawn-live`：真现状文件必须绿（合成正例只能证明文法对，证明不了仓库里那一份没被改回旧形状）。

## 读数

- `moon check --target js`：rc=0（0 errors）。
- `env -u MOONC_OVERRIDE python scripts/moon_test_env.py`：`Total tests 1387 / passed 1387 / failed 0`，rc=0。
- `~/.moon/bin/moonfmt.exe src/server/run_check_js.mbt -o`：rc=0，与工作树零差异（格式已合规）。
- 目标守卫：`check_scripts_index` rc=0 / `check_selftest_inventory_doc` rc=0 / `check_battery_count_doc` rc=0
  （`rulers=87 ci=41 battery=49 missing=0 gate=58 exempt=26 unclassified=5`）/ `check_py_stdout_encoding --all` rc=0 /
  `check_doc_surface` rc=0。
- 全量电池：`python scripts/run_guards.py` → `格数 64（手写 64 + 自动 0）/ 失败 0 / SKIP 5 / 缺执行面 0`，rc=0（5 个 SKIP 均因 `temp/` 前置件缺失，不计失败，也不构成通过证据）。\r\n- 非 moon 零回归：`run_check cmd=python args=["-c","print(1+1)"]`（server 仍在 `env -u MOONC_OVERRIDE` 下）→ `status=passed`、轮次 3、stdout `2`、`ice=false`。

## 预存红（不代修）

- `moon fmt` 本机 rc=127：moonfmt 自身撞同一颗 `\?\` ICE（BUG-329），改用 `moonfmt.exe` 直调逐文件对照。
  另：`moon fmt` / `moon info` 会把全部 `.mbti` 刷成 LF（git 报 LF→CRLF），已用 `git checkout -- '*.mbti'` 还原，
  提交面只含本单四份文件。
- `check_scripts_naming.py` rc=1（N1/N2 上限），电池已按期望红登记，非本单引入。

## 资源消耗

- 构建 3 次（修复前/后各一次；交单前为刷新 `.mbti` 还原后的 mtime 再增量一次，1 task），全量测试 1 次（约 55s），全量守卫电池 1 次（约 10 min）。
- e2e 复用仓库既有 `fist.py` 与临时 SQLite，未起额外服务；未使用子代理。
- 临时日志与 DB 全部落在 `%TEMP%`，仓内无残留。

## 任务分配记录

- 自找项，无主机指派；未触碰并行 agent 的任务/分支/文件。
- 改动 4 份文件：`src/server/run_check_js.mbt`（修复）、`scripts/moon_test_env.py`（判据 12→18 格）、
  `scripts/README.md` 与 `AGENTS.md`（同批登记）。

## 遗留风险

- `run_check cmd=moon args=["test",…]` 的 **node.cmd 垫片面**未在本单处理：R124 的 PATH 清理只在
  `moon_test_env.py` 入口内做，MCP 直连面仍可能撞 `failed to parse args`。它与 moonc ICE 是两个独立面。
- 服务端按用户 `~/.moon-shim/shim.exe` 发现垫片；换用户/机器需各自放置（与 R124 同口径，缺失时行为与旧版一致）。
- 每次 spawn 一次 `existsSync`，开销可忽略；非 Windows 不设，这是刻意的零回归边界。

## 后续建议

- R125 落地主线后，把本单的服务端面静态判据去重收敛到 `moon_env_probe.py`，避免两处各养一份针。
- `scripts/fist-mbt-web.py` 的 `ensure_mcp_build` 仍只查产物存在、不查新鲜度（docstring 写的是“已存在且新鲜”），另单。
- 若要覆盖 `run_check moon test`，可把“按目录内容剔 node.cmd 垫片”的 PATH 规则下沉为共享件（Python 侧）
  或在 js 原语层复刻，两者都应与本单的 env 注入共用一次发现。

## 超额内容

- 追加 `server-spawn-live` 真现状格：只测合成正例会让尺子停在“文法对”的层面。
- AGENTS.md 环境段同步 MCP 执行面口径，避免下一位 agent 误以为 R124/R125 的入口修补覆盖了所有 moon 子进程。

## 来源

- `src/server/run_check_js.mbt`（`js_run_command` 的 env 构造与 spawn 选项）
- `scripts/moon_test_env.py`（`server_spawn_env_violations` / `read_server_spawn_text` / 六格）
- `scripts/README.md`（`moon_test_env.py` 条目 R126 段）
- `AGENTS.md`（环境要求 · MCP 执行面同源）
- 实测产物：`%TEMP%/r126_before.json`、`%TEMP%/r126_after.json`、`%TEMP%/r126_nonmoon.json`、`%TEMP%/r126_battery.log`（仓外留档）
