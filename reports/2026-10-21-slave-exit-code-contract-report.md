# 2026-10-21 R42 汇报：`slave/guard/exit-code-contract` —— 给「自述退出码」装上一道机器门（BUG-369 建议② / T0r23）

- 提交面：新守卫 `scripts/check_exit_code_contract.py`（740 行）+ 一把尺修真 `scripts/check_template_ctrl.py`（+42 −3）
  + 执行面三处（`ci.yml` +11、`run_guards.py` +4、`scripts/README.md`）+ 认知面两处（`docs/agent-map.md` §五 +4 −1、`memory/bugs.md` BUG-369 `landed`）
  + 本汇报；主件 `4d87191`（9 个显式路径 / +924 −6，逐路径 `git add`、无 `-A`、无 `--no-verify`）。分支 `slave/guard/exit-code-contract`
  链在已推的 `slave/guard/plan-landing-moved-face`（R41 `095bf31`）之后单独起支，**trunk 未推**，已推 gitcode、远端
  `Start Git Hooks Checking [PASSED]`，
  MR 入口 `https://gitcode.com/VictorTop/Fist-Mbt/merge_requests/new?source_branch=slave/guard/exit-code-contract`（MR 由 owner 开）
- FIST：根任务 `T0r23`（publish→claim→execute→submit→verify 全生命周期，`--created-by human_steward` / `--assignee slave-guard`），连续第廿三轮自我迭代可证
- 台账：BUG-369（low，**仍 OPEN**——4 把尺只修真 1 把，判定面 16 条 = 棘轮上限；`landed[2026-10-21 R42]` 记下改了什么、没改什么）；
  本轮**未新增条目**（354 条 / 20 OPEN 不变），因为发现的东西全部落进 369 的叙述面

## 结果摘要

| 判据 | R41 结束时 | R42 现在 |
|---|---|---|
| 「自述 rc=2」与代码实现面之间有没有门 | **零执行面**（普查件躺在 `temp/`，本身是一把不跑的死尺） | 常驻守卫 `check_exit_code_contract.py`，CI + 电池各两格在跑 |
| 判定面读数 | 未固化 | **16 条 = `CONTRACT_GAP_CEILING`**：mbti_sync 8（R1×1+R2×7）／pkg_imports 7（R1×1+R2×6）／simulate_head_commit 1（R3×1）／**template_ctrl 0（本轮修真）**／plan_landing 0 |
| 承诺面来源 | 手工读 | 现读 `git ls-files scripts` = **85 份 .py（解析跳过 0）**，其中 31 份有 `N=` 契约块；脚本正文 ∪ 自家 `scripts/README.md` 条目切片 |
| 只报不判（必须出数，不许静默丢） | 无口径 | S 沉默出口 **21** ｜ U 未认作契约 **38** ｜ O 不透明/让位 **1**（外部件 `p.returncode` 透传 ⇒ R1 主动让位但留名） |
| `check_template_ctrl.py --selftest` | 七格（不锁退出码） | **八格**，新增 `fatal-exit-code-is-really-2`：起子进程把 `TPL_DIR` 指到空目录，实测「判据空转时 rc 真是 2」 |
| `run_guards.py` 电池 | 35 格 | **37 格 / 失败 0 / SKIP 0 / 缺执行面的尺 0** |
| 变异台 | R41 8 支 + 6 对照 | **7/7**（`temp/r42_mutation.py`，每支按实测方向而非预测方向记账） |
| `moon test --target js -j 1` | 1302/1302/0 | **1302/1302/0**（本轮零 `.mbt` 改动） |
| `moon check --target js --json` | 489 warning / 0 error | **489 warning / 0 error**，stderr 空，逐 `location.path` 分布与基线 `temp/chk47.json` **求差集为空** |

判据形状（三条判定共用一个棘轮，只许下降）：**R1 模块面幻影**＝承诺了 N（N≥2）而 ast 实现面一个 N 都给不出——刻意不判 0/1
（1 是 Python 未捕获异常的默认码，判它必假红），这是**按形状的保守，不是按文件的豁免**；**R2 站点类指派矛盾**＝出口站点文本属判据失灵类
（FATAL／空转／无法自证／拒绝报绿／尺子坏），而承诺面把该类指派给的码不在站点实给码集里；**R3 站点自述码不符**＝站点文案自己写 `rc=N`
而该站点实给≠N。R3 是本轮才加的一面，抓的正是 R1 结构上看不见的**半形**：`simulate_head_commit` 别处确有 `return 2`（R1=0），
唯独「PATH 上没有 moon」那条给 1 而文案自称 rc=2。

## 资源消耗

- 工具调用面：`Edit` ×约 18（新守卫实现面/承诺面/判定面/自测/上限注释 5 轮迭代、`check_template_ctrl.py` 3 处、`ci.yml` 1、`run_guards.py` 1、
  `scripts/README.md` 3、`docs/agent-map.md` 2、`memory/bugs.md` 2、`memory/2026-10-21.md` 2）+ `Bash` 取证（电池整跑 2、守卫复读 8、
  ast 普查 2 版、变异台 3 次、`moon test` 1、`moon check` 1、JSON 差集核对 2）。
- 新增临时件（全在 gitignore 的 `temp/`，不入提交）：`r42_census.py`（第一版普查）、`r42_census2.py`（ast 版，本单的**临时前身**，
  正式面已固化进守卫）、`r42_readme_face.py`（README 行内承诺面开关实验，实测判定面 16→39）、`r42_mutation.py`（变异台 7 支）、
  `r42_battery.log`、`r42_check.json` / `r42_check.err`（金条八读数）。
- 代价账：`cleanup_artifacts --check` 预存红 643 → **654**（构成：86 个根 `.db` + 567 个 `temp/` 文件 + 1 个 `scripts/` `_` 临时脚本），
  增量 11 全是本轮取证件；按 BUG-368 口径写构成、不留裸数字。
- 返工账（真实成本，不粉饰）：新守卫初版报出 **21 条**，其中 **5 条是假红**（模块常量、顶层 `sys.exit(rc)`、元组解包、高阶透传），
  逐条修真后 21→18→17→16 才敢定上限；`--selftest` 4 格先在假状态 FAIL 才暴露「夹具比语料严」；`LEAD_JUNK` 放宽后判据把自己注释里的
  例子判红（16→17）。这三次返工全部转化为写进代码注释与 §五 的定律，不是「修好就算」。

## 任务分配记录

| 环节 | 承担 | 说明 |
|---|---|---|
| 承诺面/实现面的文法与 26 格自测 | 副机 | 机械事实；`calib:` 5 格钉死 BUG-369 已知真相，对不上即判「尺子坏」 |
| 假红 5 条该修判据还是豁免文件 | **副机，且拒绝豁免** | 一律放宽实现面（按形状保守），未给任何一份文件开后门 |
| README 行内承诺面开不开 | **副机判断 + 上账留裁** | 实测 16→39、新增 10 份面真伪未核 ⇒ 本轮不开，盲区写进 `--selftest` 一格与 README 条目，谁开谁同时改上限 |
| 剩 3 把尺的 rc 面改动 | 副机出方案、**执行按轮次** | 每改一把都要复核 CI/电池里按 rc 写死的期望，且其 selftest 可能藏一按就红的死期望 ⇒ 「一轮一把尺」 |
| 棘轮上限 `CONTRACT_GAP_CEILING` 放宽 | **留指挥官/owner** | 脚本只提示收紧；改判据宇宙＝内容裁决（金条四） |
| MR / merge / trunk | **owner** | 副机只推 `slave/` 分支并给入口链接 |

## 遗留风险

1. **BUG-369 未关，剩 3 把尺**：`check_mbti_sync`（7 处串式 FATAL）、`check_pkg_imports`（6 处）、`simulate_head_commit`（半形 + 文案自称 rc=2）
   的「尺子坏了」与「有违例」仍在 rc=1 上同色。本轮给了门（CI 会红在超上限时），没给修法。
2. **两处已声明盲区**：① README 条目现实形状是一整行，行内 `N=` 当前不读（`--selftest` 有格锁住；开启后判定面 16→39，10 份新面未核）；
   ② 形状识别分不出「举例」与「承诺」，出路是改写文本——若有人加「跳过注释」的口子，先被吃掉的是把契约写在 `#` 注释块里的真脚本
   （`e2e_native_heap_probe` 正是这种）。
3. **O 面只有 1 条但非零**：`sys.exit(p.returncode)` 这类外部件透传 ⇒ R1 主动让位。让位面若长大，R1 的承重力就下降，需要人读。
4. **工具链拼写抖动仍在账上（BUG-330，OPEN；本轮复现，不是新发现）**：`moon test`/`moon check` 会重算 `.mbti`，本轮实测
   23 份变脏、其中 18 份真有 `Int` → `Int32` 纯拼写差（237 增 / 237 删，`src/**` 一字节未动）。收尾按 BUG-342 note③ 的既有约定
   `git restore -- '*.mbti'` 收回、未入提交，还原后 `check_mbti_sync.py` 仍 PASS（它只判 pub 名在不在，不判类型拼写）。
   真正待裁决的是「要不要一次全仓 `moon fmt` 把拼写钉成 0.10.16 的口径」——几万行级 churn、与任何功能单正交，属独立决策（金条四，留 owner）。
5. **CI 仍无提交面门**：`core.hooksPath` 未设置，`.githooks/pre-commit` 不生效；本轮把守卫挂进 CI 与本地电池，但「本地提交前自动跑」这件事没做。
6. **用户口径「提交之前不能有任何 WARNING 和 ERROR」**：489 条 warning 是存量（非本轮引入，逐文件分布与基线求差为空），
   按既有裁定「交 CI 当门，PR 里如实标注」处理——本报告即标注面。

## 后续建议

1. 下一轮按「一轮一把尺」清 `check_template_ctrl` 之外的 3 把，每清一把 `CONTRACT_GAP_CEILING` 就得降（16→8→1）；
   修完才允许把 BUG-369 转 `FIXED`。
2. 逐条核对 README 行内承诺面那 10 份新面，核完再开那一面；开的那一刻同时改上限与本条说明。
3. 建议把「棘轮上限必须随修尺下降」做成一条跨守卫判据（现只有 `--gate` 的超上限红，没有「上限数字本身该降」的红）——
   这需要指挥官先认这条判据的形状，否则又是一把自己写的死尺。
4. `core.hooksPath` 与「整支电池进 CI」仍挂账（3 格预存红需要 `continue-on-error` 的分档设计），属架构决策，留指挥官。

## 超额内容

- `check_template_ctrl.py` 修真是 BUG-369 建议① 的**第一份**，不在建议② 的题面里（题面只要求「立判据」）；连带把它的 `--selftest` 从七格加到八格。
- R41 的 BUG-369「后续建议③」（把两条定律固化成判据）本轮**未做**，只把定律写进 `docs/agent-map.md` §五——题面没要求，且自述判据形状需指挥官认可。
- 变异台从 R41 的 8 支缩到 7 支：**没有为凑数加变异**。7 支全部实测有方向，其中 2 支（断整数识别=假红暴涨、跨行块截断=丢 7 条）
  与我的预测相反，已按实测改写台账。

## 来源

- 真源读数：`git ls-files scripts`（85 份 .py）／`scripts/check_exit_code_contract.py` 的 `--selftest`（26 格）与全量输出（判定面 16、S/U/O 21/38/1）／
  `temp/r42_mutation.py`（7/7）／`run_guards.py` 整跑（37 格 / 失败 0 / SKIP 0 / 缺执行面的尺 0，日志 `temp/r42_battery.log`）／
  `moon test --target js -j 1`（1302/1302/0）／`moon check --target js --json`（489 warning、0 error，`temp/r42_check.json` vs `temp/chk47.json` 差集为空）／
  `cleanup_artifacts.py --check`（654：86 `.db` + 567 `temp/` + 1 `scripts/`）／`gen_plugins --check`、`check_plugin_sync`、
  `check_scripts_index`、`check_doc_surface` 全绿（170 工具 / v0.3.9）
- 认知来源：`memory/bugs.md` BUG-369（R41 立单 + 本轮 `landed`）、`memory/2026-10-21.md` R41/R42 两段、`docs/agent-map.md` §五
  「一把尺不跑就等于一把坏尺」→ 本轮把它从口头纪律变成有门的判据
- 上游任务面：`python scripts/fist.py` 的 `T0r23`（publish→claim→execute→submit→verify，驱动器 `temp/t23_drive.py`），
  终态 `status=已完成`；DELIV 十一点见 `temp/fist-selfiter.db`

---

## 回填更正（R43，2026-10-21 下一轮）

上表两处数字是**同一轮里两次采样的混读**，现读真源更正如下（不改写当时的判定面读数，只补计时口径）：

- 「85 份 .py 里 **31** 份有 `N=` 契约块」⇒ 真源现读 **32** 份。原因：**新尺入场会把自己算进宇宙**——`git ls-files` 的 85 是加判据之后重跑的，31 是加之前那次普查的读数。同一条自咬在棘轮说明上又踩一次：构成注释写成「8 = 2026-…」开头 ⇒ 自家注释被承诺面当成一份新契约（该文件契约块 2→3），按既有定律改写文本、不开豁免面，并加 `own-source-has-no-bare-pair-block` 一格钉住形状。
- 「U 未认作契约 **38**」⇒ 真源现读 **37**（同一采样时刻问题，不是这轮把 U 面修小了）。
- 判定面那两栏（16 条 = 上限）无更正：R42 的 16 条是入场后重跑过的；本轮 R43 修掉 `check_mbti_sync` 一族 8 条后降到 **8**。
- 教训一句话：**一组数字要么一次跑齐，要么各自标清采样时刻**（与 `cleanup_artifacts` 读数那条计时口径同律）。
