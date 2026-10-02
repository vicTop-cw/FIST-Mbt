# 2026-10-02 · BUG-130 出路③ 落地：native 臂改由常驻判据当门

## 结果摘要

owner 三选一里选了第③条（「按照你说的修复」）。CI 的 **两条 native 臂**现在各挂一道门，门跑的就是
`scripts/blackbox/e2e_native_heap_probe.py`（`--selftest` + `--runs 12`）：

| 臂 | 门步骤 | 门之后 | 红话 |
|---|---|---|---|
| `ci.yml` | `Native heap gate (BUG-133 探针当门)` | `Test (native)` | 非零即红，判据自己打印 TALLY/VERDICT |
| `fist-ci.yml` | `Native heap gate (BUG-133 探针当门)` | `Test (native, j=1)` | 四档 rc 各一条 `::error::`（0/1/3/其它） |

**测试步骤一个都没删** ⇒ 依赖侧修好后 native 全量覆盖自己回来，不留「以后记得改回来」的债。
`src/` 本轮零改动。

## 证据（全部从盘上件反解，无手抄）

- 同一把尺、同一棵 WSL 工作树、缺陷全程未动，给出过两端读数：`0/12`（rc=0，`temp/b130_probe12.log`）、
  `3/12`（rc=1）与 `0/12`（rc=0，`temp/b130_probe12_v2.log`）、定因轮 `3/12`（`temp/b130_run_probe.log`）。
  ⇒ **`crashes=0/12` 是抽检门，不是消音判据**；据此把 BUG-133 的机器可检前置收紧成两格：
  ① 抽检连发都 0 崩溃，② `git archive HEAD` 干净树上 `moon test --target native` 全量通过（那个数不在这里写死——native 侧以运行回执为准，本轮没让它绿过）。
- 判据自身两处「会顶替产品报案」的洞已补：
  ① 预编译门 ⇒ `RC_RULER=4`（`SELFTEST OK（rc 分解 5 格 + 计数口径正负对照 2 支 + rc 隔离对照 2 支（判据自身崩⇒4 / 拒绝出数⇒3 原样透传）+ 构建门 1 格：真跑 OK（故意喂编译不过的探针 ⇒ rc=255，没被数成崩溃））` 那一格是真跑回执）；
  ② 输出通道 + rc 隔离 ⇒ Windows cp936 控制台上 `⇒` 触发 UnicodeEncodeError 时，脚本原先**崩在结论行之前留下 rc=1**，
  而 1 = 「缺陷在场」；修复前 `selftest_rc=1`、修复后 `selftest_default_console_rc=0`。现在未捕获异常一律归 4，`SystemExit(3)` 原样透传，
  `--selftest` 里这两支是成对对照（判据自身崩⇒4 / 拒绝出数⇒3）。
- Windows 侧仍拒绝出数（不拿没跑成当跑过）：`拒绝出数：本判据要 POSIX 上的 native 工具链（Windows 侧先装载 scripts/native-env.ps1，或在 WSL 里跑）。没跑成 ≠ 跑过。`。
- 权威面：JS 全量本轮复跑 `572/572`；本地守卫族 17 格全 rc=0（fails=0）；账本抬头 133 条。
- 探针脚本身份 sha256 前缀 `ae26376d692362e5`；两发 12 跑墙钟 3.5 / 13.1 分钟。

## 分析

BUG-130 入账时的主张是「**会红且没人解释**」，不是「native 有崩溃」（后者自 2026-10-01 起由 BUG-133 承载）。
③ 改的正是前一半：门红逐字点名 BUG-133 与它的前置；门绿则全量照跑。两种红都读得出归属，所以这条单
**在自己的主张面上**成立；盖章 FIXED 的取证推迟到 push 之后，用权威 CI 里那一格的步骤名（而不是本机自述）。
同时把「门绿而全量仍被信号打死」这一种组合也写进 workflow 注释——它是 0/N 的抽检性质，不是新缺陷，
否则下一次读 CI 的人会再开一张重复单。

## 缺口与风险

1. 若日后有人删掉这两道门，**没有常驻判据会红**（只有 native 全量自己的崩会红，_legibility_ 消失而无人认领）。
   建议下一轮把它做成 `check_doc_surface` 的一条 J 规则（「文档声称的 CI 门步骤必须在两个 workflow 里存在」）。
2. 抽检门的检出率没标定：`--runs 12` 下 0 崩溃的概率看起来不小（本轮真出现过 0/12）。要更高置信只能加大 N，
   代价是两臂各 ~3.5 分钟起——留给 owner 取舍，本轮不自决加时长。
3. BUG-132（nightly 恒假条件）与 BUG-134（resolved_path 自述）仍在 OPEN，与本轮无因果。
4. 证据件都在 `temp/`，会被 `scripts/cleanup_artifacts.py` 回收；再生命令写进账本追记那一段。

## 后续建议

- push 后拿权威 CI：native 那 job 的红格应为 `Native heap gate (BUG-133 探针当门)` 或 `Test (native)`（取决于抽检抽没抽中），
  两种都由日志自己说明归属；拿到读数后 `bug_fix` 盖章 BUG-130，再重生成四宿主投影（账本口径随之变）。
- 依赖侧（`mizchi/sqlite`）的修复动作不在本仓：BUG-133 的两格前置就是它的验收单。

## 超额内容

本轮只做了裁决③本体 + 判据自证加固 + 文档同步；未新建第 18 格守卫、未加 CI 时长、未动 nightly 臂（BUG-132 仍等裁决）。

## 来源

`memory/bugs.md` 的 BUG-130 / BUG-133 追记（同一次反解的两处渲染）、`temp/b130_probe12.log`、
`temp/b130_probe12_v2.log`、`temp/b130_run_probe.log`、`temp/b130_win_probe_check.txt`、
`temp/b130_gbk_after_fix.log`、`temp/js_after_b130.log`、`temp/b130_guards.log`、两个 workflow 文件本身。
