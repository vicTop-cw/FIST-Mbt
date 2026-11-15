# 轮 346 唤醒巡检报告

**日期**：2026-11-16
**轮次**：r346
**执行者**：wd-r346（FIST-Mbt-ExploreWatchdog）

## 结果摘要

**WIP 非冻结增长后静止第 27 轮（numstat 与 r326~r345 逐字同）** —— `memory/bugs.md` 维持 **216/0**
（r345 后零再增长、无 BUG-637+ 新外来账），其余 5 个已跟踪 WIP 文件（`improvement-plan` 7/1、
`target.md` 1/1、`README` 2/1、`run_guards` 9/0、`engine_circuit_test` 5/0）与 2 个 untracked
（`check_mcpcf_db_isolation.py` 545 行、`pipeline_mode_loop.md` 211 行）**逐字同 r345**；
R192 车道自 r318 后持续停摆。`src/**` + `scripts/run_guards.py` 仍 M ⇒ **巡检分支**
（Round C 三件仍锁）。

换面巡检 `check_release_asset_names`（BUG-103+105+107+109+111+112+113+114「**资产名/版本真源同源、
命令名两类 shell 都可见、200 不等于拿到文件、装完的自检不许假绿、发布作业不许顶掉分发、文档线要 BOM
安全、源码版本常量不许落后于 moon.mod**」判据。本守卫真正管的是**分发面同源**——用户按文档敲的那条
命令、发布链产出的那个文件名、那条命令实际拿回来的字节，三者必须说的是同一件事：资产名对不上是
「下载 404」、命令名对不上是「下载成功却找不到命令」、源返回 HTML 是「HTTP 200 但装不了」、自检假绿
是「安装器自己说装好了、那句诊断还是错的」、发布作业依赖错是「流水线跑完了却一个资产也没出」、文档
线吃 BOM 是「照抄即语法错」、源码常量落后是「装完了但命令自述上一版」——同一张表面的几类失效，拆成
多个守卫只会各看半边。**判据条数不手写**——`--selftest` 的清单与 PASS 行的范围都从正文/已执行格子反解、
全部只看文本形状、不联网：**R1** 安装器不许给版本号写死字面量默认值 / **R2** 两个安装器都要真的从
`moon.mod` 取版本 / **R3** 资产名模板三处一致（`install_onecmd.ps1`/`install.sh`/`build_release.ps1`
必须都是 `fist-mbt-js-v<版本>.zip`、`release.yml` 若也出现一并比）/ **R4** 解析失败必须显式失败（空
版本分支里有 `exit 1`、不许静默用猜的版本号）/ **R5** 命令名两类 shell 都要可见（Windows 侧除 `.cmd`
外必须再写**无扩展名** `#!/bin/sh` shim 并有「四件齐」的 `exit 1` 门——POSIX shell 不解析 PATHEXT ⇒
只给 `.cmd` 就等于在 Git Bash / MSYS / agent harness 的 bash 里 `fist` 不存在；WSL/Linux 侧必须有
`cat > "$BIN_DIR/fist"` + `chmod +x`）/ **R6**「200 不等于拿到文件」（GitCode 三种 raw 形状匿名 GET 都
回 HTTP 200 + 整页 HTML ⇒ 文档首选安装线必须指 GitHub **master** 的 raw 直链〔写成 main 实测取不到〕且
两个安装器都要 (a) 对 `moon.mod` 响应做 HTML 形状检查、(b) 下载后验 zip 魔数 `PK`——只按「状态码 200 +
大于 10KB」放行、一页 HTML 就能被当作资产继续解压）/ **R7** 装完的自检不许假绿（脚本顶部
`$ErrorActionPreference="Stop"` 而原生命令的 stderr 经 `2>&1` 被包成终止错误——node:sqlite 每次启动都打
`ExperimentalWarning` ⇒ 旧自检里两个 `& node … 2>&1` 的 try **必然**进 catch、而紧随其后的
`Write-Host "✅ fist-mbt.js 可执行"` 无条件打印〔绿是装饰〕、`& fist version` 那句更把「shim 跑通了」报成
「当前会话 PATH 未刷新」；三条子判据：(a) 自检不许留空 `catch { }`〔吞错=无从归因〕、(b) 原生命令调用
必须走「临时降 EAP + stderr 隔离」的封装（`$ErrorActionPreference = "Continue"` 与 `2>` 同现）、(c)
`✅ fist-mbt.js 可执行` 必须挂在版本回执的条件分支上、不许无条件打印）/ **R8** 发布作业不许顶掉分发
（`release` 作业的 needs 必须**含 meta**〔引用 `needs.meta.outputs.version`、不在自己 needs 里就取空值 ⇒
Release 名与资产名漂成空版本形态〕且**不得含 native 作业**〔native 不是权威面、AGENTS 自己写明权威门槛
是 JS 后端、一次 native 编译失败不该让 JS 安装线没资产〕、同时 `build-native-linux` 必须与 windows 侧一样
带 `continue-on-error: true`）/ **R9** 工具链 bootstrap 与 CI 同源（`release.yml` 用
`cli.moonbitlang.com/install/unix`〔少 `.sh`〕且从不把 moon 目录写进 `GITHUB_PATH` ⇒ runner 每步起新 shell、
安装脚本改的是 shell rc、下一步里 `moon` 不在 PATH ⇒ `Build JS target` 红 ⇒ `release` 作业被 skip ⇒
Release 零资产、默认安装线一直 404；判据只看**去掉注释行之后**的代码面〔第一版被自家注释里的
`GITHUB_PATH` 喂回针、那格变异不红〕、被检面从 `.github/workflows/` **目录派生**〔逻辑名 `wf:<文件名>`〕、
只判其中真跑了 `moon build|test|update|ide|check` 的那几份、一个 workflow 都没读到 ⇒ `R9 FATAL` 拒绝出数）/
**R10** 文档线必须 BOM 安全（安装脚本按 BUG-88 带 UTF-8 BOM、`irm` 把 BOM 留成首字符 U+FEFF、`iex` 于是把
`param()` 当普通语句解析 ⇒ 用户照 README 粘的那一行当场报「赋值表达式的左侧无效」，而同一脚本用 `-File`
跑一切正常；安装器与 README 两侧的文档线都必须 `TrimStart([char]0xFEFF)`）/ **R11** 版本自述的**源码常量**
必须 == `moon.mod`（`moon.mod` 前进到 0.3.3 之后 `src/server/server.mbt` 的 `project_version` 仍是 "0.3.0"
⇒ 公网装出来的 `fist version` 回 v0.3.0）/ **R12** windows 臂安装形状与 `ci.yml` 同源 / **R13** 文档离线线
资产名版本字面量不许落后 `moon.mod` / **R14** 安装器内部两发取数也要有第二条 TLS 栈 / **R15/R16** 发布后
资产逐名比对步在位〔BUG-513 出路③〕。纯静态、不联网。扫描面含 WIP 的 `README.md`，但**只读、不触碰禁区**）
selftest **rc=0**（干净不误红 + 变异必红；清单从已执行格子反解：**R1×2 / R2 / R3×2 / R4 / R5×2 / R6×3 /
R7×3 / R8×3 / R9×6 / R10×2 / R11×5 / R12×2 / R13×2 / R14×5 / R15×5 / R16×7**）+ 实测 **PASS rc=0**
（**分发面同源 R1~R16**：资产名三处一致 + 版本真源 `moon.mod` + 空值即失败 + 命令名两类 shell 都可见 +
200/HTML/魔数检查 + 安装自检不假绿 + 发布作业不顶掉分发 + 工具链 bootstrap 与 CI 同源 + 文档线 BOM 安全 +
源码版本常量与 `moon.mod` 同源 + windows 臂安装形状与 `ci.yml` 同源 + 发布后资产逐名比对步在位〔BUG-513
出路③〕——**WIP 在飞面 `README.md` 在分发面同源上无违例**）。

零漂移 `check_tools_sync` **183** / `check_instruction_budget` **50440/65536** 均 rc=0。Round C 三件
维持过期不执行。**无新发现（类型）、无新立账**（vq 外来账队列规模与 r326~r345 持平，全挂 owner
裁决，同 BUG-565 持续模式）。**FIST 闭环 T0r102 六步全链 rc=0**（wd-r346，ns watchdog，verify
status=已完成、completed_by=wd-r346，deliverable=本报告）。禁区零碰（8 WIP 文件含 bugs.md 零改零提交）。

## 巡检明细

1. **WIP 状态**（`git status --short` + `git diff --numstat`，本轮实读，逐文件对表 r345）：
   - `memory/bugs.md` **216+/0-**（与 r326~r345 逐字同 ⇒ **零增长**；无 BUG-637+ 新条目）；
   - 其余 5 个已跟踪 WIP 文件**逐字同 r345**：`improvement-plan` 7/1、`target.md` 1/1、`README` 2/1、
     `run_guards` 9/0、`engine_circuit_test` 5/0 ⇒ R192 车道面**仍静止**（自 r318 后无再推进）；
   - 2 个 untracked（`check_mcpcf_db_isolation.py` 545 行 / `pipeline_mode_loop.md` 211 行）未变。
   - 结论：**WIP 非冻结增长后静止第 27 轮**（r321 记非冻结增长第 1 轮 = vq BUG-636 落账；r322 静止第 2；
     r323 静止第 4；r324 静止第 5；r325 静止第 6；r326 静止第 7；r327 静止第 8；r328 静止第 9；
     r329 静止第 10；r330 静止第 11；r331 静止第 12；r332 静止第 13；r333 静止第 14；r334 静止第 15；
     r335 静止第 16；r336 静止第 17；r337 静止第 18；r338 静止第 19；r339 静止第 20；r340 静止第 21；
     r341 静止第 22；r342 静止第 23；r343 静止第 24；r344 静止第 25；r345 静止第 26；r346 本轮 = 静止第 27）。
   - 禁区处置：8 个 WIP 文件（含 bugs.md）**本轮零改、零提交**。

2. **换面巡检 `check_release_asset_names`**（BUG-103~117 分发面同源守卫；R1~R16、条数不手写从已执行格子
   反解、纯静态不联网、扫描面只读含 WIP `README.md` 不触碰禁区）：
   - 自检：`--selftest` **rc=0**（干净不误红 + 变异必红；清单从已执行格子反解：**R1×2 / R2 / R3×2 / R4 /
     R5×2 / R6×3 / R7×3 / R8×3 / R9×6 / R10×2 / R11×5 / R12×2 / R13×2 / R14×5 / R15×5 / R16×7**）；
   - 实测：**PASS rc=0** —— **分发面同源 R1~R16**：
     · 资产名三处一致（`install_onecmd.ps1`/`install.sh`/`build_release.ps1` 都是 `fist-mbt-js-v<版本>.zip`）；
     · 版本真源 `moon.mod`、空值即失败（解析失败显式 `exit 1`、不静默用猜的版本号）；
     · 命令名两类 shell 都可见（Windows 无扩展名 `#!/bin/sh` shim + 四件齐 `exit 1` 门 / WSL·Linux
       `cat > "$BIN_DIR/fist"` + `chmod +x`）；
     · 200/HTML/魔数检查（文档首选 GitHub master raw + moon.mod HTML 形状检查 + zip 魔数 `PK`）；
     · 安装自检不假绿（无空 `catch{}` / 临时降 EAP+stderr 隔离封装 / `✅` 挂版本回执条件分支）；
     · 发布作业不顶掉分发（needs 含 meta、不含 native、`build-native-linux` 带 `continue-on-error`）；
     · 工具链 bootstrap 与 CI 同源（moon 进 `GITHUB_PATH` + 安装 URL `install/unix.sh`）；
     · 文档线 BOM 安全（`TrimStart([char]0xFEFF)`）；源码版本常量与 `moon.mod` 同源；windows 臂安装形状与
       `ci.yml` 同源；发布后资产逐名比对步在位〔BUG-513 出路③〕；
   - 判读：WIP 在飞面 `README.md` 在分发面同源上**无违例** ⇒ WIP 在飞面在发布资产名面上**无新增风险**。

3. **零漂移双检**：
   - `check_tools_sync` rc=0（server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；
     R3b/R7 扫现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183 对表一致）；
   - `check_instruction_budget` rc=0（AGENTS.md 50440 / 65536 字节，全部章节可见）。

4. **Round C 三件**：维持过期不执行——BUG-527 摘 cc-link-flags 已 owner 否决（CI A/B 实证有害）、
   BUG-530 已 FIXED（3699f012a）、`check_usage_tool_count` 已注册（run_guards.py:175）；`src/**` +
   `run_guards.py` 仍 M ⇒ 队列仍锁。

5. **FIST 闭环 T0r102 六步全链一发收口**（wd-r346，ns watchdog）：
   - 链脚本 `temp/fist_r346_chain.sh`（沿 r321~r345 稳健 TID 提取，逐行取能解析为 JSON 的那行）；
   - 六步 `publish / agent_acl_grant / claim / execute / submit / verify` 全 rc=0（后台一发收全），
     verify 回执 **status=已完成、completed_by=wd-r346**、deliverable=
     `reports/2026-11-16-r346-wakeup-patrol.md`（回盘 `temp/fist_r346_out/`）。

## 资源消耗

- 判据 4 支（1 换面巡检 check_release_asset_names selftest + 实测 + 2 零漂移）+ WIP numstat 核验 1 支
  + FIST 六步链 1 发（后台串跑一次收全）；
- 本轮无子代理（巡检判据为轻量命令执行 + 只读核验 + FIST 链为网关记账，命令结果需指挥官亲阅终审，故直跑）。

## 任务分配记录

- **r346 FIST 闭环 T0r102 六步全链**（wd-r346，ns watchdog）：`temp/fist_r346_chain.sh`（稳健 TID 提取，
  六步全 rc=0），回盘 `temp/fist_r346_out/`（`1_publish..6_verify.txt` / `chain.log` / `task_id.txt`；
  verify status=已完成、completed_by=wd-r346）。

## 遗留风险

- **vq 外来账队列**：白名单外 **23 条（BUG-613~635）** + 契约不命中 1 条（BUG-636）待 owner 裁决
  （搬移 vq 仓 / 带理由登记 WHITELIST kind=foreign-adjudicated）；本轮账本零增长，规模与 r326~r345
  持平，同 BUG-565 持续模式，指挥官不代行清理、不立新账。
- **WIP 非冻结增长后持续静止**：`memory/bugs.md` 216/0 无再增长；四件套核心 R192 车道面自 r318 后
  无再推进（连续第 27 轮静止）。
- **owner 裁决件**（同 r321~r345，本轮无增减）：① WIP 四件套弃置 ③ r302 落账方式 ④ 外来账处置
  （BUG-613~636，规模 23+1）⑤ BUG-636（FIST 自留临时号）known-red 登记口径（②
  check_mcpcf_db_isolation.py 缺执行面/未注册已被 R192 车道推进消解——r341 确认 README 登记自洽、
  r344 确认 spawn 隔离合规、注册面归 R192 收口时核）。
- **R192 车道收口清单（维持 5 项）**：① git add 两份在飞交付物（check_publish_payload P1 点名）+
  ② **修 `pipeline_mode_loop.md:86` 的 `run_check` 示例补 `cmd`+`task_id` 必填参数**（r342 J8 点名）+
  ③ 核 `check_mcpcf_db_isolation.py` 注册面（r341 确认 README 登记自洽、r344 确认 spawn 隔离合规、
  注册面归 R192 核）+ ④ **U 面 5 条脚本补 `N=` 契约块**（r337 点名）+ ⑤ **提交 `bugs.md` 时同批重跑
  `gen_plugins.py` 重投影插件态**（r343 J1 点名 9 文件、AGENTS.md 提交门禁既有义务，漂移即消解）。
  同属「专门轮次」批处理面。
- **FIST 链提取鲁棒性（r318 遗留）**：45 份 `temp/fist_r*_chain.sh` 同形脆弱提取（本轮 +1）；
  durable 修复在 `scripts/fist.py`（notice→stderr / stdout 纯 JSON）或 tracked 链脚本模板稳健取
  JSON 行，留专门轮次。本轮稳健提取是**临时绕过**，非 durable 修复。
- **判据自述格子数/注释文档滞后**（r332 起累计·非缺陷）：`check_arg_face_strict.py`「已知债」段
  （27 把已消解、注释仍写现状）+ r338 `check_sql_bind_alignment.py` docstring「6 格」实跑 7/7 格，
  留专门轮次批量更新（均属各尺本体、非 WIP 面）。
- **R192 在飞 WIP 的发布载荷暴露**（r334 check_publish_payload 实测确认）：`check_mcpcf_db_isolation.py`
  + `pipeline_mode_loop.md` 两 untracked 文件会在下一次 `moon publish` 被公开（P1）。R192 车道收口时
  应 `git add` 入库（属真交付物、不该 ignore）；在那之前若有人 `moon publish`，会把这两份在飞稿公开——
  发布前须先收口 R192 车道。

## 后续建议

- **最高优先仍为 BUG-636（FIST 自留临时号·check_tool_coverage 盲区修复规格）**：待 `memory/bugs.md`
  WIP 解禁后专门轮次委派（含「加进 `_tool_registry.consumers()` 收口格」最易漏环节）。
- **vq 外来账队列（BUG-613~636）owner 裁决**：规模与 r345 持平（白名单外 23 条 + 契约不命中 1 条），
  裁决面完整，可一次批了。
- **FIST 链提取鲁棒性专门轮次修复**（口径见遗留风险）。
- **判据自述格子数/注释批量更新**（r332 `check_arg_face_strict`「已知债」段 + r338
  `check_sql_bind_alignment` docstring「6 格」→ 实跑 7 格）：属轻微文档滞后、非缺陷，可一并批量修。
- **R192 车道收口清单**（维持 5 项）：git add 两份在飞交付物 / 修 pipeline_mode_loop.md:86 run_check
  示例 / 核 check_mcpcf_db_isolation.py 注册面 / U 面 5 条脚本补 N= 契约块 / 提交 bugs.md 同批重跑
  gen_plugins.py 重投影插件态。
- 换面巡检下轮候选：`check_mcp_stdio_purity`（BUG-477 MCP stdout 纯净性·判例-33 服务本体≠服务接入，
  三层 L1 静态+L2/L3 动态、`--selftest` 反解、扫描面避开 WIP 面）；继续按注册面轮换，优先近期未轮过
  且有 `--selftest` 的判据。
- Round C 三件维持过期（owner 已裁决面），唤醒轮继续非阻塞巡检。

## 超额内容

无。

## 来源

- `git status --short` / `git diff --numstat`（2026-11-16 本轮实读：bugs.md **216/0**、其余 5 文件逐字同
  r345；2 untracked 未变：check_mcpcf_db_isolation.py 545 行 / pipeline_mode_loop.md 211 行）
- `reports/2026-11-16-r345-wakeup-patrol.md`（r345 WIP 基线 + per-file 拆分）
- `python scripts/check_release_asset_names.py --selftest`（rc=0：干净不误红+变异必红、清单从已执行格子
  反解 R1×2/R2/R3×2/R4/R5×2/R6×3/R7×3/R8×3/R9×6/R10×2/R11×5/R12×2/R13×2/R14×5/R15×5/R16×7）+ 同判据
  实测（PASS rc=0：分发面同源 R1~R16——资产名三处一致+版本真源 moon.mod+空值即失败+命令名两类 shell
  都可见+200/HTML/魔数检查+安装自检不假绿+发布作业不顶掉分发+工具链 bootstrap 与 CI 同源+文档线 BOM
  安全+源码版本常量与 moon.mod 同源+windows 臂安装形状与 ci.yml 同源+发布后资产逐名比对步在位
  〔BUG-513 出路③〕；WIP 在飞面 README.md 在分发面同源上无违例）（本轮）
- `python scripts/check_tools_sync.py`（183 PASS）/ `python scripts/check_instruction_budget.py`
  （50440/65536 PASS）（本轮）
- `temp/fist_r346_out/`（六步回执 + `chain.log` + `task_id.txt`，TID=T0r102，verify status=已完成）
