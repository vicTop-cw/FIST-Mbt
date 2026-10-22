# 副机 R103 汇报 · R9 被检面改目录派生（`.github/workflows/` 普查）+ README 离线线版本字面量同步

- 日期：2026-10-22（副机，Qoder Desktop 会话）
- 分支：`slave/guard/ci-moon-bootstrap-census-r103`，基点 `f42648d`（起笔与收口各 fetch 一次，main 仍 `f42648d`）
- 性质：副机自立项（主线新合 `gate.yml` 触发的扫描面盲区），非主机 TASK-* 池条目

## 结果摘要

`scripts/check_release_asset_names.py` 的 R9（"工具链 bootstrap 与 CI 同源"，BUG-112 的执行面）此前只扫手写名单里的
`release.yml` / `ci.yml` / `fist-ci.yml`。改成从 `.github/workflows/` 目录派生（逻辑名 `wf:<文件名>`），只判代码面里真跑
`moon build|test|update|ide|check` 的那几份，并加空面自拒（`R9 FATAL`）。自证新增三格，格子清单仍从已执行格子反解。

## 证据

- 盲区实锤（逐份数代码面 moon 调用行）：`ci.yml` 11 / `fist-ci.yml` 8 / `release.yml` 4 / **`fist-bug-sync.yml` 2** /
  **`gate.yml` 1** / attest、copilot-setup-steps、sync-from-gitcode 各 0 ⇒ 旧名单覆盖 3/5，两份跑 moon 的新 workflow 无人判。
- 现状不因此变红：`gate.yml` 与 `fist-bug-sync.yml` 都已带 `install/unix.sh` + `echo "$HOME/.moon/bin" >> "$GITHUB_PATH"`
  （`grep -nE "moon|GITHUB_PATH|install/unix"` 实测行号 31-32 / 34-38）⇒ 本单是**扩面**，不是给主线补红。
- 新增件：`workflow_face()`（目录派生 + `utf-8-sig` 读，BOM 不吃进判据）、`code_face_text()`（剔整行注释，保留 R9 原有
  那手"注释里的 GITHUB_PATH 不喂针"）、`judge()` 内 `wf_face` 空 ⇒ `R9 FATAL`。
- `--selftest` **rc=0**：`SELFTEST OK（干净不误红 + 变异必红；清单从已执行格子反解：… R8×3 / R9×5 / R10×2 …）`。
  R9 五格＝release 两支变异 + `gate.yml` 摘导出行必红（证的正是"目录里的新 workflow 真进了判据面"）+
  合成 `wf:no-moon.yml` 不误红（反向对照）+ 摘掉全部 `wf:` 键 ⇒ `R9 FATAL`（空扫描必自拒）。
- 裸跑 **rc=0**：`PASS 分发面同源（判据范围从正文反解：R1…R14）`。
- 门禁族：`check_exit_code_contract.py` rc=0；`check_scripts_index.py` rc=1（3 支未登记，基线预存）；
  本改动 diff 只含 `scripts/check_release_asset_names.py` + `README.md` 一行 + `scripts/README.md` 两处自述 + 日志/报告。

## 代修的一处继承红（如实点名）

- 基线 `f42648d` 上这支守卫**裸跑 rc=1**，红在 R13：`README 的 fist-mbt-js-v0.3.9.zip ≠ moon.mod 0.3.10`；
  且 `--selftest` **AssertionError 崩在 R13 那格**（变异锚按 `VER` 拼串，README 实际写 0.3.9 ⇒ 锚找不到）。
- 为什么本单必须处理它：守卫的 selftest 一崩，**我新加的三格永远不会被执行**——那正是本仓反复点名的
  "红着没人读等于没锁"，也与「尺子必须先证明自己会红」直接冲突。先例：r93 也代修过一处继承红（`USAGE.md` 版本自述）。
- 改法最小：只把 `README.md` 第 141 行那一处离线/内网线字面量 0.3.9 → 0.3.10；R13 判定逻辑一字未动，
  两支 R13 变异格照旧（漂移必红 + 模板形态不误红）。根因（版本前进时没同步文档线）仍归主线，建议见下。

## 资源消耗

- 对话轮次：3 轮（对表定位盲区 / 改尺 + 自证 / 收口）。无子代理、无网络写、未跑 `moon test`（纯 Python 判据面）。
- 产物 5 件：守卫 +56/−8、`README.md` 1 行、`scripts/README.md` 两处自述、当日日志 20 行、本报告。

## 任务分配记录

- 指挥官侧：主机池 9 单全部已有交付分支（001/005/006/009 见 R102 的四条落差；002/004 已 `in_review`；003/007/008 各有分支），
  本轮不抢单，走自驱巡逻面；开工前 fetch 对表：main 未前进（`f42648d..gitcode/main` = 0），远端删了 4 支已合并支。
- 边界：workflow 正文一律未动（CI 属共享设施，改动权在 owner）；只改判据的**扫描面**。

## 遗留风险

1. R9 只判"代码面出现 moon 调用"这一形状；`moon` 若被包进 `.sh` 脚本再由 workflow 调用，R9 看不见（要判这条得引 shell 解析，成本不匹配）。
2. 目录派生面新增的 workflow 若**不跑 moon**，反向对照格保证不误红；但若将来出现"跑 moon 却用别的方式导出 PATH"
   （如 `PATH=$HOME/.moon/bin:$PATH`），会被判红——那种形在 runner 上确实不稳，红是对的，出路是改成 `GITHUB_PATH`。
3. 本次代修的那行字面量属于"文档线落后于 moon.mod"的**第 N 次复发**（BUG-120 的 R13 已经立了门，但门只判 README，
   不判版本号前进时谁该同步它）；根治在发布流程里加一步"bump moon.mod 同时刷文档线字面量"，归 owner/主线裁决。

## 后续建议

- 建议①：把 `check_ci_step_position.py`（r84 支）与 R9 的目录面对齐，同一份 workflow 清单两处手写必然漂移。
- 建议②：`scripts/README.md` 里 "十九格（R9×2）" 这类**格子计数自述**建议全部改成"从 `--selftest` 读数抄"，
  或由 J10 增一条子判据把 README 里的 `R×n` 与守卫自述行对表（现只比守卫自己的正文，比不到 README）。
- 建议③：`check_scripts_index` 那 3 支未登记脚本仍在红面（`check_bug_refs.py` / `fist-pr-automator.py` / `fist-task-pool.py`），
  归 r96 支与主线，副机不代改。

## 超额内容

- 无。本单唯一超出"扩面"的动作是那处继承红代修，理由与先例已在上面单独成节，未顺手改任何 workflow 或 CI 行为。

## 来源

- `.github/workflows/gate.yml`（主线 `feat/tier2-pr3-gate-ci`，随 `f42648d` 合入）；`scripts/check_release_asset_names.py` R9 段。
- 同口径先例：`scripts/check_doc_surface.py` 的 `j12_workflow_texts()`（注释原文："扫描面从目录派生，不手写文件名清单（手写清单必然落后于新增 workflow，J4/BUG-68 同族教训）"）。
- 退出码字母表 BUG-369；「尺子必须先证明自己会红」+ J10「自述==实现」：本仓判据族惯例。
