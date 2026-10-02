# 2026-10-02 · BUG-134 修复：`resolved_path` 从此真是绝对落点

## 结果摘要

账本剩余 3 张 OPEN 里唯一**本仓可自修**的一张（BUG-132 等 owner 裁决、BUG-133 根在依赖 `mizchi/sqlite` 的 native FFI）。
`report_bug` / `bug_list` 的自述从 BUG-5 起就写「返回值含 resolved_path（**绝对** + normalize 后的落点）」，
实现回显的却是「相对 server 进程 cwd 的规范化路径」⇒ 账写进了哪本台账，从回执本身判不出来。现在：

| 键 | 修复前 | 修复后 |
|---|---|---|
| `resolved_path` | `.`（相对） | `E:/…/temp/b134_callsite_cwd`（绝对 + 正斜杠规范化） |
| `server_cwd` | 不存在（自述没承诺，也就没人发现缺） | 与 resolved_path 同批回显；取不到 cwd 时为**空串**（空串本身即信号，不新造布尔旗） |
| `path` | `./memory/bugs.md` | 逐字不变（相对回显与绝对落点的分工保留 ⇒ 既有调用零回归） |

`src/` 改动 4 件（`bugreport_resolve.mbt` / `bugreport.mbt` / `server.mbt` / `pkg.generated.mbti`）+ 测试 1 件；**未新增任何依赖或 C 桩**。

## 证据（全部从盘上件反解，无手抄）

- 取数路径零新增依赖：`@env.current_dir()` 就在 `moonbitlang/core/env`，而 `src/server/moon.pkg` 早就 import 了它
  （js 走 `process.cwd()`；native 走 `moonbit_rt_get_current_dir`，是 runtime 提供的符号，不是本仓的 `stub.c`）
  ⇒ 没有往 BUG-133 那类 FFI 面上加东西。
- 白盒断言**翻向**：`src/server/bugreport_test.mbt` 里那句注释原本逐字写着「resolved_path 存在且是规范化后的**相对**路径」——
  它把上面那句谎供成了契约。现断言为 `resolved_path` 以 `server_cwd` 开头 + `bug_list` 与 `report_bug` 两笔回执**逐字相等**；
  另加纯函数形状格 `bug134_abs_path_shapes`（Windows 反斜杠 cwd / 尾斜杠 + `dir="."` / 相对段尾斜杠 / cwd 空串），
  负向一支断言"空 cwd 必须原样回相对"，不许拼一条**看着像**绝对的路径。
- **调用面**（`temp/b134_callsite_probe.py`，原文回执落 `temp/b134_callsite_raw.json`）：真起 `node cli.js serve`，
  把 server 的 cwd 刻意换到 `temp/b134_callsite_cwd`、`FIST_DB_PATH` 改道（BUG-122 口径），走 MCP `tools/call bug_list{project_dir:"."}`：
  `resolved_path=E:/IDEProjects/AI/FIST-Mbt/temp/b134_callsite_cwd`、`server_cwd` 同值、`path=./memory/bugs.md` 原样保留。
  探针自带两态对照（`--selftest`：修复前形状 3 条违例全在、修复后 0 违例）——只跑正向的探针是恒绿装饰。
- 顺手挖出的隐藏缺陷：`bug_resolve_path` 从前用 `String.replace`，而 MoonBit 的 `replace` **只替换首个匹配**
  ⇒ `E:\a\b` 规范化成 `E:/a\b`。以前喂进来的全是「至多一个反斜杠」的相对串所以一直不红；
  是新白盒断言第一次把绝对路径喂进去时**当场打死**才暴露（`src/server/bugreport_test.mbt:174 FAILED: true is not false`）。已改 `replace_all`。
- 测试数 572→573 的搬家代价照账执行：`temp/b134_count_sync.py` 逐锚点断言命中次数，改 11 份现状文档共 23 条主张；
  其中 4 条是 **native 轨 2026-10-01 的实测数**（AGENTS / ARCHITECTURE / README / README_EN）——native 本轮没复跑，
  翻那 4 个数＝伪造测量记录 ⇒ 走 `check_test_sync.EXEMPT` 逐条点名，并把 selftest 夹具改成「JS=实测 / native=旧数」共存形状
  （夹具不跟着改，R4 判"失效豁免"，基准格当场不绿——这条是实跑出来的，不是推演）。
- 读数：`moon check` 0 errors；`moon info && moon fmt` up to date、`moon fmt --check` no work；
  JS 全量 **573/573**（`temp/js_b134_take2.log` 尾行 `Total tests: 573, passed: 573, failed: 0.` + `moon_rc=0`）；
  守卫族 17 格 `total=17 fails=0`（含 `gen_plugins --check/--selftest`、cl7、`test-sync --selftest` 8 变体、badge `tests-573%2F573`）。

## 分析

BUG-134 的形状不是"少了一个字段"，而是**主张与实现之间那道缝只有调用者会掉进去**：
白盒测试当时是照着实现写的（"相对路径"），于是它把文档里那句「绝对」钉成了假契约——红着没人读等于没锁，写反了也等于没锁。
所以本轮的修法顺序刻意是：先让自述不变（那句"绝对"本来就是对的），把实现抬到主张的高度，再让白盒断言反过来**考主张**；
如果反过来做（把文档降级成"相对"），缺陷就消失了而调用面照旧瞎。

`replace` 那一格同族：一条只有绝对路径才能触发的规范化缺陷，在相对路径时代是隐形的。
两个缺陷都不是"没想到"，是**测试输入的覆盖面从来没到过主张所描述的那一侧**。

## 缺口与风险

1. `bug_fix` RPC 面仍指向另一本台账（连接器 server cwd 不指向本仓，上一轮已实锤）⇒ BUG-134 的 FIXED 盖章走 **md 真源面**，
   并在小记里点名是哪一面被改（不假装是 RPC 落的账）。
2. 本机 js 产物已重建（`_build/js/.../cli.js` + `patch_esm_main.py`），但**已连接的 Qoder 插件运行时是另一份副本**：
   那侧要吃到修复得同步 cache 副本并重启 stdio 进程（既往记过：换引擎文件不换已连接的进程）。本轮不代做，留给需要它的那一刻。
3. 白盒两笔回执「逐字相等」这条只覆盖了 `bug_list` 与 `report_bug` 的 `project_dir="."` 形态；
   `resolved_path` 对**非平凡相对目录**（`temp/bug_c5`）的绝对性由纯函数格与新断言共同钉住，但未在协议面上逐形状跑一遍。
4. 证据件都在 `temp/`，会被 `scripts/cleanup_artifacts.py` 回收；再生命令：
   `python temp/b134_callsite_probe.py`（需先 `moon build --target js && python scripts/patch_esm_main.py`）、
   `python temp/b134_callsite_probe.py --selftest`、`python temp/b134_count_sync.py --dry`。

## 后续建议

- push 后读权威 CI：js 两臂应仍 success 且 `Total tests: 573`；native 两臂照旧红在 `Test (native` 那一格（BUG-133，与本轮无因果）。
  拿到读数后把 BUG-134 的 FIXED 小记补一行「同笔 push 的 CI 读数」，并因抬头状态变化重跑投影（cl7 会跟着变）。
- 若要把「回执可独立审落轨」变成常驻门：把 `temp/b134_callsite_probe.py` 提进 `scripts/blackbox/`（自带 --selftest 两态对照，形状已合身），
  代价是守卫族多一格 + `scripts/README.md` 索引 + ci.yml 一步。本轮不自决扩门。

## 超额内容

只做了 BUG-134 本体 + 它顺带暴露的 `replace` 缺陷 + 测试数搬家（判据要求的既有义务）。未新建第 18 格守卫、未动 workflow、未动 native 臂、未碰插件运行时副本。

## 补记（同轮第二笔）：盖章与投影

- `### FIXED(2026-10-02T02:39:29Z / BUG-134)` 已落 **md 真源面**（`bug_fix` RPC 面指向另一本台账 ⇒ 不拿它盖本仓的章），
  由 `temp/b134_fixed_stamp.py` 写抬头 + 小记。**五道前置门**全过才落盘：JS 尾行 573/573 且 `moon_rc=0`、
  守卫族 `total=17 fails=0`、调用面探针正向 PASS 与 `--selftest` 两态对照都在场、两远端 `rev-list --count <远端>..HEAD = 0`、
  CI 两条 js job 都 success。
- 盖章后的权威 CI（`temp/b134_readback.txt`，run 36956419257『CI』/ 36956418476『FIST CI』）：
  js/ubuntu 与 js/windows 全 success；native 两臂仍红在 `#8 Test (native)` / `#9 Test (native, j=1)` —— 那是 BUG-133 的读数面，
  **不在本单关闭条件里**，所以本单盖 FIXED 不覆盖它（两单关闭条件不同，混在一起才会遮缺陷）。
- 台账从 3 待修降到 2（BUG-132 等 owner 裁决、BUG-133 根在依赖），投影随之重生成：
  `gen_plugins` 回执 `133 条入账 = 118 已修 / 9 重复并入 / 4 误报 / 2 待修`，cl7 重跑 PASS，守卫族再跑 `total=17 fails=0`。
- 上面缺口 #1（"盖章要走 md 面并写明是哪一面"）到此闭合；缺口 #2（插件运行时副本没同步）与 #3（协议面只跑了 `.` 形态）仍然开着。

## 来源

`memory/bugs.md` BUG-134 条目（含 BUG-5 原始建议那句「绝对 + normalize」）、`temp/js_b134_take2.log`、
`temp/b130_guards.log`、`temp/b134_callsite_raw.json`、`temp/b134_evidence.txt`、
`src/server/bugreport_resolve.mbt`、`src/server/bugreport_test.mbt`。
