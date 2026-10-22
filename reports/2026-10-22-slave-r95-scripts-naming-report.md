# 2026-10-22 副机 R95 汇报 · TASK-008 第一批（scripts/ 命名规范 + 词法棘轮，零改名）

分支：`slave/ci/task008-scripts-naming-r95`｜基点：`gitcode/main d8deed8`｜MR：
https://gitcode.com/VictorTop/Fist-Mbt/merge_requests/new?source_branch=slave/ci/task008-scripts-naming-r95

## 结果摘要

TASK-008（`docs/tasks/backlog/TASK-008-scripts-naming.yaml`，P3，风语者立案）的 acceptance 第 1 条已交付，
并把剩余三条钉成**可裁决、可验证**的形状，而不是照原口径机械改 50 个文件名。

交付四件（新增 2 + 修改 3）：

| 件 | 位置 | 作用 |
|---|---|---|
| 命名规范正文 | `scripts/NAMING.md`（92 行） | 定律三条 + 角色前缀表 13 项 + 角色后缀表 12 项 + 16 份债清单与改名建议 + 改名成本的实测构成 |
| 命名判据 | `scripts/check_scripts_naming.py`（242 行） | N1 无角色名 16/16、N2 连字符名 4/4 两条棘轮；词表从 `NAMING.md` 的 anchor 行现读；`--selftest` 十格；`--show` 出名单 |
| CI 接线 | `.github/workflows/ci.yml:277-283` | 新步「Scripts naming guard」先 `--selftest` 再全量（本仓口径：判据的自检必须先跑，自检崩了不许占一个绿位） |
| 索引登记 | `scripts/README.md`（同名条目） | 过 `check_scripts_index`（89 份全登记） |
| 单据回写 | `docs/tasks/backlog/TASK-008-scripts-naming.yaml` | acceptance 第 1 条勾 `[x]` + `delivery_r95:` 段（纯插入 15 行） |

关键读数（全部实测，非引用单据）：

- 顶层 `scripts/*.py` **80 份**，子目录 12 份。
- 风语者报的「约 50 个无前缀」里，**29 份角色写在后缀**（`*_verify/_probe/_demo/_smoke/_selfdrive/_tour/_replay/_preflight/_coldstart/_ab/_gate/_automator`）——
  按 TASK-008 自己的判据「看文件名猜不出用途」，它们读得出角色；只看前缀会把演示件与验证件一起算成债，读数虚高一倍。
- 真债 **N1 = 16 份**；另有一面 **N2 = 4 份含连字符**（`fist-gate.py` / `fist-mbt-http.py` / `fist-mbt-web.py` / `fist-pr-automator.py`）。
- 改名成本 **1224 处引用**（`git grep -c -F` 逐名统计 46 份候选名）：活面 163 处 / 32 份文件；
  **归档面 944 处 / 227 份文件**（`memory/` `reports/` `stories/` `docs/`）；其余 117 处 / 35 份（根文档、`plugins/` 投影、`dist/` 产物、`cmd/`）。

## 资源消耗

- 目标轮次：本单占 1 个 goal turn 序列（第 21 轮内完成，累计 22/40）。
- 命令面：约 16 次工具调用（3 次普查脚本 + 5 次守卫 + 4 次文件写 + 变异台/自检各若干）。
- 未消耗：`moon` 构建/测试（本单 0 行 MoonBit 改动，`moon fmt`/`moon test` 面无；本机 `moon build --target js`
  仍受 `\\?\` 长路径 ICE 限制，与本单无关）。
- 网络：1 次 `git fetch`（前一轮）+ 1 次 `git push`（本单）。

## 任务分配记录

- 副机自派：TASK-008 第一批（词法 + 判据 + 接线），按用户裁定「风语者任务优先」选题，
  基点为最新 `gitcode/main`（不是叠在自己的 open 分支上，遵守一单一分支）。
- **未派给子代理**：改名范围是 owner 裁决项（见「遗留风险」第 1 条），把它做成机械任务交出去只会产出
  一个 1224 处引用的不可评审 diff。
- 并行面（不在本单，如实点名不代做）：
  - peer 分支 `slave/fix/bug-refs-guard-semantics`（484aced）在改 `check_bug_refs.py` 的语义（假自测 / 退出码反用 / 把正常注释当违规）——
    与本单的 `check_scripts_index` 预存红同一条脚本，登记面归它，不抢。
  - peer 分支 `slave/fix/v0310-projection-closeout`（5751a97，叠在 `b90a0bf` 上）动 `scripts/README.md` +17 与 `run_guards.py` +88——
    与本单的 README 同文件插入不同条目，`run_guards.py` 本单**没动**（靠自动发现进电池，缺面 0）。
  - `TASK-018/019/020/021/022/023` 仍在 `slave/integrate/r93-on-cef1e9c-r94` 的池里等裁决。

## 遗留风险

1. **改名范围未定，TASK-008 acceptance 第 2/3/4 条不能自动执行**：acceptance 第 3 条要求「docs/ 里的引用全部更新」，
   而 `docs/`、`memory/`、`reports/`、`stories/` 那 944 处引用记的是**当时真跑过的命令**——回写它们等于把记录改成事后叙述。
   两案都在 `delivery_r95:` 里写清：A 只动活面 + NAMING.md 留「旧名→新名」映射（副机倾向）；B 连归档面一起回写（换一致性、失真记录）。
2. **棘轮上限是人的常量**：`N1_CEILING = 16` / `N2_CEILING = 4`（`scripts/check_scripts_naming.py:47-48`）。
   改一批名必须同批下调上限，否则「少了一批债」这件事在读数上看不见；`real-ceiling-matches-measured` 那一格正是在盯这件事，
   但**它盯的是「相等」，不是「下降」**——下降本身仍要靠人来改常量（放宽与收紧都是人的决定，判据不自动改数，与本仓 `check_exit_code_contract` 同口径）。
3. **词法表可以被人稀释**：往 `NAMING.md` 的 anchor 行再加一个词，就会有一批名字从 N1 面消失。
   本单用两道保守挡：`e2e_`/`test_` 这类**必须先有表里的语义行**才被认（表与 anchor 同一文件，读者一眼能看到加了哪个词、为什么加）；
   子目录同形面「只报不判、必须出数」，把 `e2e_*` 收进前缀表后 C 面自己归零，这一步在 `--show` 里可复看。
4. **两条预存红不在本单手里**（都不是本分支引入，均按裁定点名不代修）：
   - `check_scripts_index.py` **rc=1**：main 上 4 份脚本未登记（`check_bug_refs.py` / `fist-gate.py` / `fist-pr-automator.py` / `whisperer.py`），
     实测 `git show gitcode/main:scripts/README.md | grep -c` 四名均为 **0**、`git ls-tree gitcode/main scripts/` 均为 1 ⇒ 红在 main。
   - `check_doc_surface.py` **rc=1**：`USAGE.md` 自述 0.3.9 != `moon.mod` 0.3.10。这一条已在
     `slave/integrate/r93-on-cef1e9c-r94` 修过；本分支刻意不重复修，避免自己的两条分支互相冲突，由 owner 按合序取一份。
   - 另 `check_bug_reference_integrity.py` **rc=1**（J1 悬空 17 > 上限 1）为 main 的存量红，本单 0 份新 `BUG-n` 引用，读数不动。
5. **本机无 `moon` 全量验证面**：本单纯脚本/文档，不需要编译；但合入后 CI 的 `moon test --target js` 臂不在副机上验证过，
   按「交 CI 当门」处理。

## 后续建议

1. owner 先裁「归档面是否回写」这一条（A/B 案），裁完就能按档批量改名：NAMING.md 末节已按**活面引用数**给每份债标了成本档，
   低成本那批（`_run_check_t0r21.py`、`output_validate.py`、`laya_decide.py`、`mcp_bug_loop.py`、`pentad_fist.py`）可先动，
   `fist.py`（活面引用最高的一档）留到最后单独一单。
2. `fist-gate.py` 是 N1+N2 双债且**它自己是合入门**——改名会同时动 CI 引用面，建议与 CI 步骤名一起改，一次到位。
3. `check_bug_refs.py`（peer 在修）与 `check_bug_reference_integrity.py`（副机在跑）两把尺的分工仍未裁（TASK-020）；
   建议裁决后由胜者一并把 `scripts/README.md` 的 4 条缺登记补齐，让 `check_scripts_index` 在 main 上转绿。
4. 本仓可考虑把「命名词法门」升格进 `AI-DEVELOPMENT-STANDARD.md`（新增一条 J 判据的位子在 `check_doc_surface`），
   现在它只是一把独立尺 + 一份 `NAMING.md`；升格与否是规范面的事，本单不擅自扩。

## 超额内容

- 用户/单据未要求、本单顺手做了的：
  - 把 46 份候选名的**引用成本**按活面/归档面/其余三面量化（163/944/117）——这是 TASK-008 acceptance 第 3 条能否照字面执行的前置事实，不做就只能空口争。
  - N2（连字符面）：TASK-008 只提「无前缀」，没提分隔符；`fist-gate.py` 这类名字不可 import，是同一病灶的另一半，故一并钉成棘轮。
  - `subdir-name-classified-by-basename` 这一格来自实现自审（第一版按整条路径比前缀会把 `blackbox/check_*.py` 算成债），修实现并留格锁死。
- **没有**做且刻意不做：任何一次 `git mv`；`run_guards.py` 的手工点名（自动发现已覆盖，动它反而与 peer 分支撞 +88 行）；
  预存红的修复。

## 来源

- `docs/tasks/backlog/TASK-008-scripts-naming.yaml`（本单立案原文与 acceptance）
- `scripts/NAMING.md`、`scripts/check_scripts_naming.py:47-48`（上限常量）、`:54`（`read_roles`）、`:95`（`census`）、`:111`（`judge`）、`:123`（`selftest`）、`:175`（真源码对照格）、`:204`（`main`）
- `.github/workflows/ci.yml:277-283`（新步）、`scripts/README.md` 同名条目
- 实测读数：`python scripts/check_scripts_naming.py --show`、`--selftest`；`python scripts/run_guards.py --selftest`；
  `python scripts/check_exit_code_contract.py`；`python scripts/check_py_stdout_encoding.py --all`；
  `python scripts/blackbox/check_merge_markers.py`；`python scripts/check_scripts_index.py`（rc=1）；
  `python scripts/check_doc_surface.py`（rc=1）；`python scripts/check_bug_reference_integrity.py`（rc=1）
- 成本普查：`git grep -c -F <name> -- ':!scripts/<name>'` 逐名统计（46 份候选名 → 1224 处引用，三面 163/944/117）
- 基点与并行面：`git log --oneline -1 gitcode/main`（d8deed8）、`git diff --stat gitcode/main...gitcode/<peer>`
