# 2026-10-01 · BUG-130 定因轮汇报（native 门槛的根在依赖的 FFI）

- 盖章：2026-10-01T03:01:00Z（写盘瞬间的 UTC，不是手敲）
- 任务包：目标 = BUG-130 定因（不是修复）；边界 = 只动文档面 + 新判据 + 账本，**不动 `src/` 产品码、不动 CI 定义**；验收 = 权威面读数 + JS 全量 + 守卫族全 rc=0。

## 结果摘要

1. **BUG-130 定因完成**，根因不在本仓逻辑：CI 的 native 测试臂（`Test (native)` 与 `Test (native, j=1)` 两臂）恒红，是测试二进制被信号打死
   （`Failed to run the test: /home/runner/work/FIST-Mbt/FIST-Mbt/_build/native/debug/test/src/engine/engine.blackbox_test.exe` ／ `The test executable exited with signal: 11 (SIGSEGV) (core dumped)`），而打死它的是 `mizchi/sqlite@0.3.1` 的 native FFI——C 侧裸指针当 MoonBit 对象回传 + 三个 `const char*` 声明成 `-> Bytes`。
   机理逐行、复现逐格、排除逐项都落在 BUG-133 条目里。
2. **三条嫌疑全部实测排除**（不是推理排除）：工具链漂移（CI 自述 `moonc v0.10.14+7d59c7ec9 (2026-09-18) ~/.moon/bin/moonc`，与本机 WSL 逐字同版本）、依赖版本漂移（`moon.mod` 精确锁定，
   registry 里 0.3.1 就是最新版，没有可退的修复版）、并行竞态（本轮 34 格 native 作业读数里 `-j 1` 臂同红，串行不降低概率）。
3. **一条常驻判据入库**：`scripts/blackbox/e2e_native_heap_probe.py` 用零 FIST 业务码的探针反复开关该依赖，按退出码分格并报 glibc 原文。本轮 **crashes=3/12（sigsegv 1、sigabort 2、ok 9，读数出自 WSL ubuntu 侧；Windows 侧该判据显式拒绝出数，见下）**。
   它的方向被刻意设成反向——`crashes=0` 才允许 native 臂当常规门槛，所以它现在的作用是「让 native 的红继续可见」，不是消音。
4. **文档旧口径 4 份同步改正**（AGENTS / README / README_EN / ARCHITECTURE），并按 R4「豁免条目失效即红」的设计删掉
   `check_test_sync` 里四条已失效的 `317` 豁免，同批改写该判据 `--selftest` 夹具基线 ⇒ 八格对照重新全过。
5. **账本净增两号**：BUG-133（high / OPEN）+ BUG-134（low / OPEN）。账本现 **133 条**（9 DUPLICATE / 4 FALSE_POSITIVE / 116 FIXED / 4 OPEN）；OPEN 逐条点名 = BUG-130, BUG-132, BUG-133, BUG-134（计数从 `## BUG-nn …` 抬头反解，不是数小记）

## 资源消耗（从产物文件反解，不手算）

- 权威面取数：owner 只读 token 一次会话内 3 个面（runs / jobs / annotations）+ 1 发作业日志（302 签名 URL 匿名续取），
  落到盘上的 CI 作业日志正文 1628 KB 字节；判据读数 34 格 native 作业。
- 本机量测：WSL native 全量 3 格（工作树 300s / 干净树 146s / 干净树重跑 68s），JS 全量 1 格 572/572。
- 常驻判据连跑 12 次（每次生成探针 + `moon test` + 300 轮开关库）合计 411s。
- 守卫族复跑：17 格全 rc=0（逐格 rc 落在 `temp/b130_guards.log`，可与该文件对表；复跑器 `temp/b130_run_guards.py`）。
- token 面：全程未回显 key、未写进 argv（`curl --config` 临时文件，脚本结束删除）。定因已闭合 ⇒ 建议 owner 现在就撤销该 token。

## 任务分配记录

- 指挥官（本会话）亲自做：定因判断、排除项设计、账本与文档落笔、判据脚本编写、终审。
- 分流：**无**——本轮没有把「查日志 / 写代码」派给子代理，因为取证链要求同一上下文里逐格对表（既往教训：对方在同一棵树上重建产物时取证会读到中间态）。
- 交回 owner 的三选一（共享 CI 面，本轮不自决）：
  ① native 臂**保持红**（现状，最诚实，代价是每次 push 有一格恒定红）；
  ② native 臂挂 `continue-on-error: true` + 在本仓 AGENTS/标准 §7 点名 BUG-133 为「已知且已定因」；
  ③ native 臂**摘掉测试步骤**，改跑 `scripts/blackbox/e2e_native_heap_probe.py --runs N` 当门（判据本身可移植，POSIX 侧出数）。
  我推荐 ③：它把「没人解释的红」换成「有读数、有转正前置的门」；②最容易被读成遮缺陷（本轮已按这条自我克制）。

## 遗留风险

- BUG-133 是**依赖侧**缺陷，本仓无法自修：绕行方案（让 sqlite 句柄活满进程生命周期）代价未测，已明写在条目里、不当结论。
- native 门槛至今没有可信读数：Windows 侧该判据拒绝出数（`return 3`），本轮所有 native 量测都在 WSL 做 ⇒ 「Windows native 也崩」这一句
  的依据只有仓库既有的 `0xc0000374` 记录 + 同族机理，**本轮没在 Windows 上复跑判据**，故不作为主张写进文档。
- `0xc0000374` 与本轮 glibc 读数是两个不同 libc 的形态，机理同源（非法 free）但证据链各走各的；条目里分栏写清了。
- BUG-132（fist-ci.yml 的 nightly 恒 skipped）仍等 owner 一句话，本轮未动 workflow 文件。
- 本机自伤过两次（探针脚本用了不存在的 `debugprintln` / `@fs.append_string_to_file`），已被预编译门拦住；
  这个门类（「10/10 全红 = 我的脚本坏了」）以后每次量测起手都要保留。

## 后续建议

1. owner 裁决 CI 三选一后，把选择与理由追加到 BUG-130 条目（追记不改原文），并同步 AGENTS「已知边界」段。
2. 上游动作（可另开任务）：给 `mizchi/sqlite` 提 issue，附本轮机理行号 + 探针脚本 + crashes=3/12（sigsegv 1、sigabort 2、ok 9，读数出自 WSL ubuntu 侧；Windows 侧该判据显式拒绝出数，见下） 读数——这是唯一能让 native 臂真正转绿的路。
3. BUG-134 的修法很轻（`resolved_path` 改真绝对 + 新增 `server_cwd`，白盒断言反向写严），下一轮可并入一个小修复批。
4. 撤销 `FIST_GITHUB_TOKEN`（HKCU），定因不再需要它；后续若要做上游 issue，再按需用一次性细粒度 token。
5. 不要跑 `scripts/cleanup_artifacts.py` 清 `temp/`：本轮账本/报告逐字引用的证据文件都在里面（当前 0/11 缺失）。

## 超额内容（做了但任务包没要求）

- 顺手把 AGENTS.md 里指向 README「已知边界」的悬空引用改成指向 `AI-DEVELOPMENT-STANDARD.md` §7（真源）。
- `check_test_sync` 的 `--selftest` 夹具基线跟着新口径重写（不改的话判据会红在自家对照上）。
- 抓到并入账 BUG-134（工具面回显可审性），非本轮目标。

## 来源

- 权威面：GitHub Actions API `repos/vicTop-cw/FIST-Mbt` 的 `/actions/runs`、`/actions/runs/<id>/jobs`、`/check-runs/<id>/annotations`、
  `/actions/jobs/<id>/logs`（302 → 签名 URL，续取不带 Authorization）。run 36656890998 / job 109703045365 @ `4d83a94`。
- 依赖源码：`.mooncakes/mizchi/sqlite/stub.c`（`:18-29` `:79-87` `:148` `:200-203` `:298` `:321`）与 `sqlite_native.mbt`（`:90` `:230` `:240` `:352-380`）。
- 注册表版本清单：`~/.moon/registry/index/user/mizchi/sqlite.index`。
- 本仓判据与守卫：`scripts/blackbox/e2e_native_heap_probe.py`、`scripts/check_test_sync.py`、`scripts/check_doc_surface.py`、`scripts/check_plugin_sync.py`、
  `scripts/check_scripts_index.py`、`scripts/check_publish_payload.py`。
- 账本：`memory/bugs.md` BUG-130 追记 + BUG-133 / BUG-134 新条目。

### 证据件（现存 / 已回收两栏，逐条给再生命令）

| 证据 | 路径 | 状态 |
|---|---|---|
| CI native 作业日志正文（权威面） | `temp/native_job_109703045365.log` | 现存（1668024 字节） |
| CI 取数脚本的读数汇总（34 格 native 作业） | `temp/b130_ci_probe.out` | 现存（10938 字节） |
| 同上，结构化 | `temp/b130_native_history.json` | 现存（12774 字节） |
| 匿名 annotations 取到的 exit code 255 原文 | `temp/bug130_annotations.json` | 现存（1992 字节） |
| 常驻判据连跑 12 次的分格读数 | `temp/b130_run_probe.log` | 现存（773 字节） |
| 工作树带残留的 native -j 1 全量 | `temp/b130_wsl_full.log` | 现存（4039 字节） |
| git archive HEAD 干净树的 native 全量（崩点 ops） | `temp/b130_wsl_clean.log` | 现存（3526 字节） |
| 干净树重跑换形态（SIGABRT + munmap_chunk） | `temp/b130_switch2.log` | 现存（1910 字节） |
| JS 全量（权威门槛） | `temp/js_after_b130.log` | 现存（1063 字节） |
| 写账本用的脚本（幂等键 + --verify） | `temp/b130_ledger.py` | 现存（15735 字节） |
| 守卫族复跑的逐格 rc 读数 | `temp/b130_guards.log` | 现存（3703 字节） |

再生命令（任一文件被回收后）：
- CI 面：`python temp/b130_ci_probe.py`（token 从 `HKCU\Environment` 读、写临时 `--config` 文件、结束删除；不落 argv）
- 判据面：`python scripts/blackbox/e2e_native_heap_probe.py --runs 12`（POSIX + native 工具链；Windows 侧回 rc=3 拒绝出数）
- 账本面：`python temp/b130_ledger.py --verify`（与盘面逐字 diff，幂等）
- JS 门槛：`moon test --target js`（读数 `temp/js_after_b130.log`）
