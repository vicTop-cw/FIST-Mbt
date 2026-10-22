# 副机 R102 汇报 · 新尺 check_backlog_status_staleness.py（任务池 status ↔ 主线盖章对表）

- 日期：2026-10-22（副机，Qoder Desktop 会话）
- 分支：`slave/guard/backlog-status-staleness-r102`，基点 `f42648d`（gitcode/main 当日最新合并点）
- 性质：副机自立项（自驱巡逻发现，非主机任务池条目；主机任务池 r100/r101 两单已在各自分支交付）

## 结果摘要

给任务池这一面补了一把只读判据：`docs/tasks/backlog/TASK-*.yaml` 里的 `status` 与 `gitcode/main` 提交标题里
点名的 `TASK-nnn` **对表**。落差超过只许下降的棘轮上限即 rc=1 并逐条点名，否则打印读数不判红。
登记面 `scripts/README.md` 加了一条（只增行），已自动进本地电池。

## 证据（读数一字可回溯）

- 真源：`scripts/check_backlog_status_staleness.py`（237 行，工作树 CRLF、裸 LF 0）。
  `BACKLOG_DIR` :42 / `STALE_CEILING=4` :46 / `UNSTAMPED` :47 / `parse_yaml` :50 / `citations` :64 /
  `judge` :73（R1 stale :76、棘轮收紧提示 :89）/ `selftest` :97 / `fatal` :142 / `resolve_rev` :149 /
  `main` :159（判定面重算 :203-:205、`--show-open` 标记 :210）/ `RULER BROKEN` :236。
- `--selftest` ⇒ rc=0，11 行 OK + 末行
  `SELFTEST OK: 11 格（合成违例必红 3 + 反向对照不误红 4 + 规则失明对照 2 + 解析面自证 2）`。
- 裸跑 ⇒ rc=0：
  `扫描面=gitcode/main | backlog 9 份 | 主线点名到的 TASK id 7 个 | 落差 4 条 / 上限 4 条 / 超限 0 条`，
  四条点名 `TASK-001 / TASK-005 / TASK-006 / TASK-009 status=backlog`（各带那条已存在的盖章标题），
  末行 `BACKLOG_STALENESS=within 落差 4 条 <= 上限 4（存量等 owner 盖章即下降；新增一条就红）`。
- 变异对照（仓外临时副本，跑完已删）：`STALE_CEILING = 3` ⇒ rc=1
  `BACKLOG_STALENESS=exceed 落差 4 条 > 上限 3 ⇒ 超 1 条（判定面只许下降）`，逐条点名仍在。
- 空扫描自拒：`FIST_BACKLOG_DIR` 指空目录 ⇒ rc=2 `FATAL: … 里一份可解析的 TASK-*.yaml 都没有，判据空转不报绿`。
- 退出码四档齐：0 within / 1 exceed / 2 拿不到扫描面或空扫描 / 4 未捕获异常（`RULER BROKEN`），
  全程不 `sys.exit(字符串)`、不透传被调命令的码（BUG-369 字母表）。
- 附注（透明记账）：`memory/2026-10-22.md` 在 HEAD 上**末行没有换行符**（git 标 `\ No newline at end of file`），追加段落必须先给它补上终止符 ⇒ `git diff --numstat` 显示 `24 / 1`，那 1 条"删除"是同一行原文重打，内容一字未改（已用 `cat -A` 核过）。除这一格，本分支全部 diff 为纯增行。

## 门禁面（本仓判据族，跑给读数不跑给自述）

| 判据 | rc | 读数 | 归属 |
|---|---|---|---|
| `check_exit_code_contract.py` | 0 | 判定面归零（上限 0），新脚本一条没进 | 本改动带入 0 条 |
| `check_scripts_index.py` | 1 | 未登记 3 项：`check_bug_refs.py` / `fist-pr-automator.py` / `fist-task-pool.py` | **预存红，非本改动**（新脚本已登记，不在红名单） |
| `check_doc_surface.py` | 1 | `USAGE.md 自述版本 0.3.9 != moon.mod 0.3.10` | **预存红，非本改动**（我没碰 USAGE.md） |
| `run_guards.py --list` | 0 | `check_backlog_status_staleness.py CI=- 电池=电池`；`尺 32 把 / CI 面 28 / 电池面 32 / 缺执行面 0` | 自动入电池，无缺执行面 |

两条预存红按 owner 裁决**不代修**，在此点名 rc 与成因即可；本分支的 diff 为纯增行（脚本 + README 1 行 + 日志 + 报告），
不含任何删除，工作树除这四件外一格未变。

## 资源消耗

- 对话轮次：本单占用 3 轮（读基线 / 写尺 + 自证 / 收口 + 提交推送）；无子代理、无网络写操作。
- 命令：`git`（rev-parse / log / diff / ls-files）+ 6 支本地判据 + 1 次临时沙箱变异副本；未跑 `moon test`（本单为纯 Python 判据，不动 `.mbt` 跟踪面，`moon fmt --check` 契约件不在改动面上）。
- 时间：约 25 分钟；产物 4 件（脚本 237 行 / README 1 行 / 日志 24 行 / 报告本件）。

## 任务分配记录

- 指挥官侧：主机任务池当前待办（TASK-001/005/006/009）都已有分支实做，副机这轮走「自驱巡逻」分支：
  找一个"重复派发"的真实病灶立尺。R101（电池只读）与 R102（任务池对表）是同一巡逻回路里连续抓到的两形。
- 副机侧：判据设计 + 自证 + 门禁跑全，全部本会话完成，未派子代理（单文件、需逐项验真，委派反而丢证据）。
- 边界：只动 `scripts/check_backlog_status_staleness.py`、`scripts/README.md`、`memory/2026-10-22.md`、`reports/` 本件；
  没有改任何 backlog yaml、没有改 `USAGE.md`、没有改 `.gitignore`。

## 遗留风险

1. **存量 4 条落差仍未盖章**：本尺只点名、拦住第 5 条，改 `status` 是任务池 owner 的裁决（改完把 `STALE_CEILING` 降到 0 才有门强度）。
   如果没人降数，这把尺的实际强度是"不许再变差"，不是"必须修好"。
2. `citations` 只看提交**标题**里的 `TASK-nnn`：正文/分支名里的点名不算。故意收紧（标题是盖章的落点），
   但也意味着"合并时把标题改写了"会让对表漏认——漏认方向是 R2（自称 done 却没点名），偏保守，不会假绿。
3. 扫描面按 `gitcode/main → git/main → HEAD` 解析：副机在旧基点上跑会读到旧盖章集。`--rev` 可覆盖，报告里已写明当轮用的是 `gitcode/main`。
4. `status` 词表目前只认 `backlog`（`UNSTAMPED`）：任务池若新增 `planned`/`ready` 一类中间态，需要 owner 决定它算不算"该盖章"，本尺不猜。

## 后续建议

- 建议①（owner，一次改完）：把 TASK-001/005/006/009 的 `status` 按已落地的盖章改成 `done` 或 `in_review`，并把 `STALE_CEILING` 降到 0，之后这把尺才是硬门。
- 建议②：`fist-gate.py --scan` 生成 backlog 时顺手写 `stamp:`（点名提交标题），让新单从出生就带着可对表的锚。
- 建议③：把本尺挂进 CI 面（现在只在电池里，`CI=-`）；挂法应与 `check_doc_surface` 同批，避免单条红拖整条流水线。
- 建议④：合并序仍是 r95→r96→r98/r99→r100→r101→r102（各分支基点不同，冲突面已在项目记忆登记；`fix/battery-readonly` 已由主机自行合入，与 R101 前提同源）。

## 超额内容

- 无改动被塞进本单之外的面：没动 backlog、没动 `USAGE.md`、没动两条预存红。
- 多做的一件事：给 selftest 补了「解析面自证」2 格（无 `id:` 的 yaml 不进判定面、字段解析正确）——
  这是首版自己踩到的（读不懂的文件混进判定面），不在任务要求里，但缺它这条缝会一直开着。

## 来源

- `docs/tasks/backlog/TASK-*.yaml`（9 份，`status` 字段实测）；`gitcode/main` 提交标题（`git log --format=%s`，点名 7 个 id）。
- 同形先例：`AGENTS.md` 的 `bug_list.open_with_linked_done`（账本/任务库矛盾一次看见）；棘轮纪律：`check_plan_landing.py` P6、`check_deprecated_text_census.py` R3。
- 退出码字母表：BUG-369（`check_exit_code_contract.py`）；「尺子必须先证明自己会红」：全仓 selftest 惯例 + `check_doc_surface` J10。
- 本轮实做前读过的基线：`f42648d`（含主机 `fix/battery-readonly`、`feat/tier2-pr3-gate-ci`）。
