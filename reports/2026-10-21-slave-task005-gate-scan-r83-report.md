# R83 报告 — TASK-005 fist-gate.py `--scan` 分支普查（合入者巡检自动进料）

- 分支：`slave/feat/task005-gate-scan-r83`（基于 master `072a463`）
- 任务来源：`docs/tasks/backlog/TASK-005`（风语者 P1）
- MR：https://gitcode.com/VictorTop/Fist-Mbt/merge_requests/new?source_branch=slave/feat/task005-gate-scan-r83

## 1. 结果摘要

`scripts/fist-gate.py` 新增 `--scan` 子命令：fetch（失败降级并点名）→ 遍历远端分支 → 每支算
ahead / `git cherry` 的 + 数 / src± 行数 / 分支顶树冲突标记 → 四档建议动作（ABORT 带标记 /
DROP 已并等价 / MERGE-LOW-RISK 纯文档 / MERGE-CODE 先过门链）→ 写
`.git/fist/tasks/backlog/<完整分支名>.yaml`（gitignored 进料区）+ 清 stale yaml。
输出尾行附可直接粘贴的巡检 prompt 句。顺带把 fist-gate.py 首次登记进 scripts/README.md，
**关掉了 check_scripts_index 的预存红**（其成因就是 fist-gate.py 未登记）。

改动文件：`scripts/fist-gate.py`、`scripts/README.md`、`memory/2026-10-21.md`、本报告。零 `.mbt/.mbti`。

## 2. 资源消耗

单会话副机一轮；Python 3 + 本地 git（无 moon 依赖，不触发本机 moonc ICE 面）。
selftest ~10s；真跑 scan ~20s（25 支候选 × git 查询）。

## 3. 任务分配记录（TASK-005 验收四条对表）

| 验收项 | 结果 |
|---|---|
| scan 子命令：遍历远端分支 + cherry --no-merges + 冲突标记 + 生成 yaml | ✅ `scan()`：远端分支枚举（`%(refname)` 全名）、`git cherry <base> <ref>` 计 + 数、`git show` 顶树标记检测、yaml 落 `.git/fist/tasks/backlog/` |
| 文件名 = BRANCH-NAME.yaml，含 ahead / cherry+ / 冲突标记 / src 改动行数 / 建议动作 | ✅ 嵌套目录保留完整分支名（`backlog/gitcode/slave/fix/xxx.yaml`），字段 branch/base/scanned_at/ahead/cherry_plus/conflict_markers/src_lines_changed/code_files/suggested_action |
| 巡检 prompt 里加「发现问题自动写 .git/fist/tasks/backlog/*.yaml」 | ⚠️ **部分**：prompt 本体在主机 schedule-9a125f43（schedule 工具数据，不在仓内）——scan 每次输出尾行给出可粘贴的原句，主机下次巡检贴入即可；如实点名不代改主机侧 |
| 合入者下次巡检能看到任务状态（backlog→claimed→done） | ⚠️ **结构就绪**：yaml 带 `status: backlog` 字段；状态推进是合入者晋升到 docs/tasks/backlog/ 跟踪面时的人工动作，scan 刻意不自动写跟踪面（人的终审） |

## 4. 判据面设计

- **rc 契约**：0 = 有产出（发现是输出不是失败——scan 是普查器不是门）；2 = 判据无法自证
  （远端分支枚举不到 / 无 master-main 基点）。
- **自测离线化**：S1-S6 用「本地仓库当 origin」（`git remote add` + fetch 本地路径），
  不碰网络可复现：无远端自拒 / 代码支字段全 / 纯文档低风险 / 已并支 DROP / 带标记支 ABORT / stale 清除。
- **两个自测抓到的自身缺陷**（都是真枪）：① `%(refname:short)` 把 `origin/HEAD` 短名打成 `origin`
  冒充分支 → 改 `%(refname)` 全名过滤 + 剔除各远端 master/main 基线镜像；② 加中文字符串后
  `check_py_stdout_encoding` 当场红（会 print 非 ASCII 无 stdout 重配）→ 补 BUG-58/138 闸，86/86 齐。

## 5. 遗留风险（预存红 + 边界，如实点名）

- **G4 fmt 预存红（本机）**：`--selftest` 的 G4 fmt 格在本机 rc=2（moonc `\\?\` 路径 ICE）——
  master 基线 `git show gitcode/master:scripts/fist-gate.py` 复跑逐字相同红，**非本单引入**；
  CI（ubuntu）上该格 rc=0 正常。S1-S6 全绿。
- **真发现待裁决**：scan 首轮抓出 **r72/r73 顶树各带 3 处未解决冲突标记**
  （`src/server/issue_scan.mbt`、`issue_scan_test.mbt`、`issue_scan_wbtest.mbt` 行首
  `<<<<<<<`/`>>>>>>>`，逐文件 `git show` 复核为真）。这两支进入合入队列前需人工处理；
  r81 的 commit 前门会拦，但这是分支侧治理第一次有仪器可见。
- `.git/fist/tasks/backlog/` 是 gitignored 进料区：scan 产出不进跟踪面，晋升到
  docs/tasks/backlog/ 仍是合入者的人工动作（金条四：不可逆/共享面执行权留给指挥官）。
- `git cherry` 的 + 数是「补丁不等价」近似（cherry-pick 改动过的提交会误报 +），
  建议动作只作分流提示，不是合入判据。

## 6. 后续建议

- TASK-004（P3 反向 diff REVERT-PATTERN）可直接建在 scan 的数据面上：src± 已算出，
  补 deletions > insertions×1.5 判据 + `failed/` 目录分流即可。
- TASK-003（P2 CI 步骤位置门 check_ci_step_position.py）落仓后，本电池/CI 面记得三处齐备
  （ci.yml + run_guards 电池 + README 登记）——run_guards r82 分支已把宇宙扩到 blackbox，新尺不再有盲区。
- 主机把 scan 输出尾行那句贴进 schedule-9a125f43 后，巡检即全自动。

## 7. 超额内容与来源

- **超出验收面两项**：① fist-gate.py 首次登记 scripts/README.md（关 check_scripts_index 预存红）——
  核对过 TASK-003/004 的 scope 都不含登记面，属 TASK-005 scope（scripts/fist-gate.py）的顺带收口；
  ② stdout UTF-8 闸补齐（守卫抓到后修复）。
- 来源链：TASK-005 yaml（风语者 P1）；BUG-58/138（stdout 闸律）；check_scripts_index 的登记律；
  r81 的 slave-branch-merge 门（marker 治理的 commit 侧，与 scan 的分支侧互补）。
