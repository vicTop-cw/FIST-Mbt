# R82 报告 — TASK-007 run_guards 宇宙扩展：26 把尺 → 全树自动扫描 + 登记面

- 分支：`slave/ci/task007-run-guards-universe-r82`（基于 master `072a463`）
- 任务来源：`docs/tasks/backlog/TASK-007`（风语者 P1）
- MR：https://gitcode.com/VictorTop/Fist-Mbt/merge_requests/new?source_branch=slave/ci/task007-run-guards-universe-r82

## 1. 结果摘要

`scripts/run_guards.py` 的守卫宇宙从「scripts/ 顶层 26 份」扩为「scripts/ 全树自动扫描 67 份」，
并新增第三执行面**登记面（REGISTRY）**。TASK-007 的核心缺陷——blackbox/ 里落了不接线的尺
（`check_merge_markers.py` 既不要求登记也不进电池，落了不接线就无人跑）——从结构上收口：
此后任何新落仓的 `check_*.py` 若三面（CI/电池/登记）皆无，G1 当场点名。

改动文件：`scripts/run_guards.py`、`scripts/README.md`（run_guards 条目追加 R82 段）。
零 `.mbt`/`.mbti` 改动。

## 2. 资源消耗

单会话副机一轮；本地 Python 3（moon 工具链未触发——本单 py-only）。
电池全量约 1 分钟（多数格秒级，doc_surface/plugin_sync 生成器校验占大头）。

## 3. 任务分配记录

副机单干（py-only 守卫改造，无子任务拆分必要）。TASK-007 验收四条逐条对表：

| 验收项 | 结果 |
|---|---|
| CASES 自动扫描（filter `test_/verify_/selfdrive_`） | `guard_files()` os.walk 递归 + `UNIVERSE_EXCLUDE_RE` 排除 `^_`/`^test_`/`^verify_`/`^selfdrive_`/`_verify.py$`/`_selfdrive`，现读 67 份 |
| blackbox/*.py 全部进宇宙 | selftest 格 `blackbox-all-in-universe` 钉死；check_merge_markers.py 双格进电池 |
| `--list` 尺数 26→40+ | 现读 67，`--list` 四列 `CI=/电池=/登记=` |
| 诊断格保留不回退 | plan_landing 诊断格 + merge_markers selftest 格原样在位；`--selftest` 19 格含既有 13 格全部保留 |

## 4. 判据面设计（为什么多出一条登记面）

只做「自动扫描」不够：67 份里 28 份根本不是该自动跑的（servers、长跑、网络、一次性证据脚本、
helpers、不在 CI 的黑盒 e2e）。两条路都坏——硬把它们塞进电池 = CI 每 run 凭空多 28 个假红源；
只报「不在 CI/电池」= 恒红装饰。故复用本仓 `schema-reserved` 点名预留律（`check_store_tables_wired`）：
REGISTRY 28 条每条带 why，G1 改「三面皆无才算孤儿」；**G2 反向抓 stale**（登记点了不存在的脚本 ⇒
FATAL）——两向发红，与表接线守卫同构。`auto_cases()` 对新落仓 `check_*` 自动补格，防「写了格忘了抄进
CASES」重演 plan_landing 躺一周的旧事。

## 5. 遗留风险（预存红 + 边界，如实点名）

- **master `072a463` 的 src/ops 编译红未修**（`healed` 未绑 `ops_test.mbt:66/67` + `rhop_poll_once` 未绑
  `rhop_native_wbtest.mbt:51/57/72`，`moon test` rc=1）：本单 py-only 不依赖 moon 工具链，如实点名；
  修法在 r79 单（`slave/fix/ops-compile-restore-r79`），留 owner 合序裁决（r79 与 TASK-002 对
  rhop_poll.mbt 的定性相反——r79 视为新文件修复，TASK-002 视为 poison 重复定义）。
- **预存红 2 条按电池律声明**（`expected()` 期望值 + 依据，非豁免）：
  `check_scripts_index.py` rc=1（fist-gate.py 未在 scripts/README.md 登记，TASK-003/004 主机在办）；
  `cleanup_artifacts.py --check` rc=1（工作树残留 989 件，清扫属人的决定）。
- **SKIP 5 条**（缺 temp 前置：badge/test_sync 的 pt27.log、census ×3 的 chk47.json）：SKIP 不构成
  「这格过了」的证据，电池汇总单独披露。
- REGISTRY 是快照式人工清单：脚本改名/删除由 G2 兜底，不追求自动发现。
- 电池首跑 rc=1 的两个干扰项已排除：旧 `case("check_scripts_index.py")` 与新增 expected() 并存（删旧留新）；
  stale 的 `temp/pt27.log`（1348 时代 scratch 日志）喂出 test_sync 假红（删除即归位，gated SKIP 设计如此）。

## 6. 后续建议

- TASK-003（P2 ci-step-position）与本单相邻：ci.yml 步骤位置审查时可用本单放宽后的 CI 引用面读数。
- fist-gate.py 的 README 登记在 TASK-003/004 落地后，应同步把本电池里那条 expected() 期望改回 0（why 里已写明）。
- `scripts/README.md` 的 run_guards 历史重复条目（4 条）是预存状态，建议某轮 tidy 单合并为一条 + 按轮追加。

## 7. 超额内容与来源

- 超出 TASK-007 验收面的一项：CI 引用面正则放宽（`ci_referred()` 能看见 `scripts/blackbox/…` 与子路径），
  实测 CI 真跑 38 份——旧正则看不见 5 支 blackbox e2e 探针与 cli_flag_probe。来源：做 G1 三面对表时
  发现「CI 明明在跑、旧读数却说没跑」，属同一缺陷的另一半，一并修掉。
- 来源链：TASK-007 yaml（风语者首轮发现）；R58（blackbox 盲区立案）；R74（merge_markers 接线 CI）；
  `check_store_tables_wired` 的 schema-reserved 律（登记面设计模板）。
