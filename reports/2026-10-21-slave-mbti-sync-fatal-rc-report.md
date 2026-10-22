# 2026-10-21 R43 汇报：`slave/guard/mbti-sync-fatal-rc` —— 修掉 BUG-369 的第二把尺，棘轮 16→8（T0r24）

- 提交面：`scripts/check_mbti_sync.py`（+59 −10 面，7 处 FATAL 出口改真 + `emit_fatal()` + 两格自测）
  + `scripts/check_exit_code_contract.py`（棘轮 16→**8**、calib 格改写、注释去掉举例形状、`--selftest` 26→**27 格**）
  + 三处文档面（`scripts/README.md`、`docs/agent-map.md` §五、`memory/bugs.md` BUG-369 `landed`）
  + R42 汇报的**回填更正段**（两处混采数字）+ 本汇报。分支 `slave/guard/mbti-sync-fatal-rc`
  链在已推的 `49395ef`（R42 面）之后单独起支，**trunk 未推**；主件 hash 写在下一笔回填里，不写进自己所在的提交（R40/R41/R42 同形）。
  逐路径 `git add`、无 `-A`、无 `--no-verify`。
- FIST：根任务 `T0r24`（publish→claim→execute→submit→verify 全生命周期，`--created-by human_steward` / `--assignee slave-guard`），连续第廿四轮自我迭代可证
- 台账：BUG-369（low，**仍 OPEN**——4 把尺已修真 2 把，判定面 **8 条 = 棘轮上限**；`landed[2026-10-21 R43]` 记下改了什么、没改什么）；
  本轮**未新增条目**，新发现全部落进 369 的叙述面与 `docs/agent-map.md` §五

## 结果摘要

| 项 | R42 结束时 | R43 现在 |
|---|---|---|
| `check_mbti_sync.py` 的 7 处「尺子坏了」出口 | `raise SystemExit("FATAL …")` ⇒ 打印文本后给 **1**，与「有违例」那一档同色 | 7 处全改 `raise SystemExit(emit_fatal("FATAL …"))`（写 stderr 后 `return 2`）⇒ 判据失灵真给 **2** |
| 棘轮 `CONTRACT_GAP_CEILING` | **16**（mbti_sync 8 ＋ pkg_imports 7 ＋ simulate_head_commit 1） | **8**（pkg_imports R1×1+R2×6 ＋ simulate_head_commit R3×1） |
| 这一档降下来靠什么 | 未核 | 逐条核过：判定面每条从「串式给 1」变成 `impl={0,1,2}`、`fatal_codes={2}`，**不是靠 R1 让位到 O 面消失的** |
| `check_mbti_sync.py --selftest` | 12 格（不锁退出码） | **17 格**，新增 `emit-fatal-returns-2`（函数返回值）＋ `fatal-empty-scan-face-rc-is-really-2`（把 `MBTI_NAME` 指到不存在的接口面、起子进程跑真 `main()`，考**进程退出码**） |
| `check_exit_code_contract.py --selftest` | 26 格 | **27 格**（新增 `own-source-has-no-bare-pair-block`，把「自家注释里不许出现裸 `N=` 举例形状」钉成格子） |
| 判定面（全量，rc=0） | 8 条 = 上限 8 | 同：**8 条 = 上限 8**，`S 21 ｜ U 37 ｜ O 1` |
| 承诺面计数（R42 登记） | 「85 份里 **31** 份有 `N=` 契约块、U **38**」 | 真源现读 **32** 份 / **U 37** —— 差值是**采样时刻混读**，不是这轮改小了宇宙；四处文档已更正 |
| 变异台 | R42 7 支 | **11 支全命中期望**（`temp/r43_mutation.py`），其中 1 支实测与预测相反、按实测改写并升为定律 |
| `run_guards.py` 电池 | 37 格 / 失败 0 | **37 格 / 失败 0 / SKIP 0 / 缺执行面的尺 0** |
| `moon test --target js -j 1` | 1302/1302/0 | **1302/1302/0**（本轮零 `.mbt` 改动） |
| `moon check --target js` | 489 warning / 0 error | **489 warning / 0 error**（本轮零 `src/**` 改动） |

修法形状：`emit_fatal(msg)` 只做两件事——把 `msg` 写到 stderr、`return 2`；调用点写成 `raise SystemExit(emit_fatal(msg))`。
**刻意不用 `raise SystemExit(msg)`**——那正是本单在抓的写法：带字符串的 SystemExit 只打印文本、码恒为 1，
一份自述「2=判据无法自证」的尺用它能自证吗？不能，它只会把「尺子坏了」伪装成「有违例」。

承重性证明（不靠自述）：把 `check_mbti_sync` 的 HEAD 版本（7 处串式）与工作树版本喂进同一份判据，
`temp/r43_mutation.py` 读到「改前判定 8 条 ⇒ 改后 0 条」，并在 M1 只回退 1 处站点时读到**恰好 1 条 R2**
——判据是逐站点判的，不是一句「这份文件修过了」就整面放行。

## 资源消耗

- 工具调用面：`Edit` ×约 14（`check_mbti_sync.py` 7 站点 + 函数 + 2 格自测、`check_exit_code_contract.py` 上限注释 / calib 格 / 自指格 3 轮、
  `scripts/README.md` 4 条目、`docs/agent-map.md` 2、`memory/bugs.md` 2、R42 汇报回填 1）+ `Bash` 取证
  （两把尺 `--selftest` 各 2、守卫全量 3、变异台 3、ast 探针 2、电池 2、`moon test` 1、`moon check` 1、`.mbti` 差集核对 2）。
- 新增临时件（全在 gitignore 的 `temp/`，不入提交）：`r43_mutation.py`（变异台 11 支）、`r43_probe_m3.py`（M3 反差的成因探针：
  `Analyzer` + `collect_sites()` 现读站点 `external=True`）、`t24_drive.py`（FIST execute→submit→verify 驱动器）、
  `pt28.log` / `mc28.txt` / `g28.txt`（金条八读数）。
- 代价账：`cleanup_artifacts --check` 预存红 654 → **663**（构成：86 个根 `.db` + 576 个 `temp/` 文件 + 1 个 `scripts/` `_` 临时脚本），
  增量 9 全是本轮取证件；按 BUG-368 口径写构成、不留裸数字。**这两个读数各属各自的采样时刻**：写本报告后再复跑一次电池，`temp/` 又多落一件
  取证件 ⇒ 现读 **664 = 86 + 577 + 1**——`temp/` 面天生随取证增长，谁的读数谁负责标时刻（本轮 §五 新律）。
- 返工账（真实成本，不粉饰）：① 变异台第一版用正则找 `emit_fatal(`，命中了 docstring 里的例子 ⇒ 造出非法 Python、判据返回 None、`TypeError`；
  改成行首锚定的站点正则 + 括号配对删除。② 探针用 `subprocess(text=True)` 撞 GBK 解码异常，改回 `PIPE` + `decode("utf-8","replace")`；
  又用 heredoc 传正则把 `\\n` 吃成换行、还把类名记成 `ExitAnalyzer`（真名 `Analyzer`）⇒ 第三次才测到东西。
  ③ **M3 实测与预测相反**：把 `emit_fatal` 的 `return 2` 换成 `return 1`、文案一字不动，我预测判定面 8 条（R1+R2），
  实测 **7 条 R2**——因为修尺后站点形状含 `returncode` ⇒ 触发 R1 让位，第 8 条从判定面**搬进 O 面留名**。按实测改写期望，
  并补 `M3b` 一格专锁「让位必须有留名」。④ **自家文档措辞把守卫判红**：README 里写「11/11」「85 / 32」这类 `NN/NN` 形状，
  被 `check_test_sync.py` 的 `RX_PAIR` + `RX_KEY`（同行含 `selftest`）读成「声明测试总数 11 ≠ 实测 1302」⇒ 电池真红了一格。
  出路不是给 README 开口子，是改写文本（memory/reports 在豁免面前缀里，docs/README 不在）。
  这四次返工全部转化为写进代码注释、自测格子与 §五 的定律，不是「修好就算」。

## 任务分配记录

| 环节 | 承担 | 说明 |
|---|---|---|
| 7 处站点的形状改动与 2 格退出码自测 | 副机 | 机械事实；`--selftest` 里那格子进程跑真 `main()`，不看 rc 只信打印 |
| 「降了 8 条」到底是被修好的还是被让位让掉的 | **副机主动核** | 题面没要求；不核就等于把棘轮降在一件没发生的事上 |
| M3 预测与实测冲突：改判据还是改期望 | **副机，选改期望** | 实测为真源；把「让位搬家」升为 §五 定律，而不是给判据补一条「让位也算报」的口子 |
| 计数面 31/U 38 与真源 32/U 37 冲突 | **副机，四处一起更正** | 含上一轮已提交汇报的**回填更正段**——已发出去的数字要补计时口径，不能装作没写过 |
| 剩 2 把尺的 rc 面改动 | 副机出方案、**执行按轮次** | 每把都要复核 CI/电池里按 rc 写死的期望与其 selftest 的死期望 ⇒ 「一轮一把尺」 |
| 棘轮上限 `CONTRACT_GAP_CEILING` 放宽 | **留指挥官/owner** | 脚本只提示收紧；改判据宇宙＝内容裁决（金条四） |
| MR / merge / trunk | **owner** | 副机只推 `slave/` 分支并给入口链接 |

## 遗留风险

1. **BUG-369 未关，剩 2 把尺**：`check_pkg_imports`（R1×1 + R2×6，6 处串式 FATAL）与 `simulate_head_commit`
   （R3×1 半形：moon 超时那条真给 2，其余 4 处 FATAL 给 1，其中一条文案自己写着「（rc=2）」）。
   这 7 + 1 条就是当前上限 8，清完才能把 369 转 `FIXED`。
2. **让位面（O）是棘轮的泄压阀**：本轮 M3 实测证明「判据失灵类的站点若含 `returncode`，R1 会主动让位」。
   这把尺修得越「透传」，判定面越可能凭空变小。`--selftest` 只锁住了 mbti_sync 这一族的标定，
   通用形状（谁让位、让了几条）目前靠 `--all-faces` 手工对表，没有常驻红门。
3. **README 行内承诺面仍未开**：条目现实形状是一整行、行内 `N=` 当前不读；实测开启后判定面 16→39、新增 10 份面真伪未核。
   盲区有格子钉住，但**它仍是盲区**：写在 README 行内的契约承诺不会进判定。
4. **工具链拼写抖动仍在账上（BUG-330，OPEN；本轮复现，不是新发现）**：`moon test`/`moon check` 重算 `.mbti`，
   本轮 23 份变脏、纯 `Int` → `Int32` 拼写差（237 增 / 237 删，逐行核对为对偶、`src/**` 一字节未动），
   收尾按 BUG-342 note③ 既有约定 `git restore -- '*.mbti'` 收回、未入提交，还原后 `check_mbti_sync.py` 仍 PASS
   （它只判 pub 名在不在，不判类型拼写）。是否一次全仓 `moon fmt` 钉成 0.10.16 口径，属独立决策（金条四，留 owner）。
5. **CI 仍无提交面门**：`core.hooksPath` 未设置，`.githooks/pre-commit` 不生效。本轮所有验证靠 CI + 本地电池 + 我手跑。
6. **用户口径「提交之前不能有任何 WARNING 和 ERROR」**：489 条 warning 是存量（本轮零 `src/**` 改动、未新增一条），
   按既有裁定「交 CI 当门，PR 里如实标注」处理——本报告即标注面。

## 后续建议

1. **R44 修 `check_pkg_imports`**（当前判定面 7 条，修法与本轮同形：`emit_fatal()` + 一格 subprocess 实测 rc 真是 2），
   棘轮 8→1；其 `--selftest` 是否有按 rc 写死的期望，动之前先读。
2. **R45 修 `simulate_head_commit`**（R3 半形，文案自称「（rc=2）」），棘轮 1→0 ⇒ BUG-369 关闭条件成立。
3. 建议把「**判定面少了 N 条必须回头对 O/S/U 三面**」做成常驻判据（现只靠 calib 格钉住 mbti_sync 一族）。
   这需要指挥官先认这条判据的形状——自述判据无执行面就等于又一把好死的尺（BUG-365/366 教训）。
4. 建议把「**一组数字必须同一批采样**」做成 `scripts/README.md` 的登记纪律：本轮两处混读（31/38）都不是判据错，
   是登记时刻错。机械化的办法是登记条目自带「采样时刻 = 一次跑齐的日志路径」，但格式改动面比本轮题面宽，留下轮。
5. `core.hooksPath` 与「整支电池进 CI」（3 格预存红需要 `continue-on-error` 分档设计）仍挂账，属架构决策，留指挥官。

## 超额内容

- **承重性核查**（「降 8 条不是让位让掉的」）与 **逐站点判别变异 M1** 都不在 T0r24 题面里；题面只要求「selftest 全格 rc=0 / 全量 rc=0 / 判定面=8」。
- **上一轮已提交汇报的回填更正段**（`reports/2026-10-21-slave-exit-code-contract-report.md`）不在题面里：
  题面只说「本轮数字写对」，没说上一轮写错的那两个数字要回头更正。我选择更正并在原文件里标明计时口径。
- **两条新定律进 `docs/agent-map.md` §五**（「修尺会改变站点形状，判定面与让位面之间会搬家」「新尺入场会把自己算进宇宙，
  登记数字必须同一批采样」）与一格 `own-source-has-no-bare-pair-block`（26→27 格）：都是返工的产物，不是任务项。
- **未做**（诚实记录）：没动 `check_pkg_imports` / `simulate_head_commit`（按「一轮一把尺」留下轮）；
  没开 README 行内承诺面；没给 `check_test_sync.py` 加「NN/NN 出现在文档里不算声明」的口子——那是又一副按文件豁免，
  与本轮定律（改写文本、不开豁免面）相反。

## 来源

- 真源读数：`scripts/check_mbti_sync.py --selftest`（**17 格 OK**）与不带参全量（**PASS：24 份 .mbti 的 654 条 pub 声明、6 种形状，rc=0**）／
  `scripts/check_exit_code_contract.py --selftest`（**27 格 OK**）与全量（**判定面 8 条 = 上限 8，rc=0**，S/U/O = 21/37/1）／
  `temp/r43_mutation.py`（**11/11**，含改前 8 条 / 改后 0 条、M1 恰 1 条 R2、M3 实测 7 条 + M3b 让位留名）／
  `run_guards.py` 整跑（**37 格 / 失败 0 / SKIP 0 / 缺执行面的尺 0**，日志 `temp/g28.txt`）／
  `moon test --target js -j 1`（**1302/1302/0**）／`moon check --target js`（**489 warning、0 error**，日志 `temp/mc28.txt`）／
  `cleanup_artifacts.py --check`（663：86 `.db` + 576 `temp/` + 1 `scripts/`）／
  `check_scripts_index`、`check_doc_surface`（170 工具 / v0.3.9）、`check_test_sync`（17 条声明，改文档措辞后复绿）全绿
- 认知来源：`memory/bugs.md` BUG-369（R41 立单 / R42 立门 / 本轮 `landed[2026-10-21 R43]`）、`memory/2026-10-21.md` R42/R43 两段、
  `docs/agent-map.md` §五「自述的退出码必须实测」→ 本轮把它降了一档；两条新定律同轮入 §五
- 上游任务面：`python scripts/fist.py` 的 `T0r24`（publish→claim→execute→submit→verify，驱动器 `temp/t24_drive.py`），
  终态 `status=已完成`；DELIV 十条见 `temp/fist-selfiter.db`
