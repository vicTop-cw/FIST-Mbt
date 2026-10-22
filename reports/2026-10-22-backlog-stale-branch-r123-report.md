# R123 交付报告：任务池状态尺补 R4 分支并线面 + TASK-013/014/015 台账对账

日期：2026-10-22
分支：`slave/fix/backlog-stale-branch-r123`
基线：`gitcode/master` = `cd697333`
交付提交：`b08c1faf`

## 1. 结果摘要

- `scripts/check_backlog_status_staleness.py` 新增 **R4 STALE-BRANCH**：yaml 点名的任务分支已出现在主线
  commit subject 里（`Merge <branch>`）而 `status` 仍为 `backlog` ⇒ 判红。补的正是 R1 的盲区——
  R1 只认 subject 里的 `TASK-0NN`，而这批任务的活是随分支并线的，subject 里根本没有任务号。
- 以真实基线实测：新规则当场抓到 **2 条**存量（TASK-014 / TASK-015），rc=1；对账后 rc=0。
- TASK-013 的分支 `feat/guard-check-merge-markers` 已从两端删除且无同名 merge subject，R4 刻意不认
  （只看主线 subject，不猜远端删除），按人工证据转 `in_review`。
- 三条任务（TASK-013/014/015）均转 `in_review` 并落 `status_note` 证据；`check_backlog_yaml_integrity`
  23 份台账 0 违例。
- 电池（叠最新主线后）：**63 格 / 失败 0 / SKIP 5 / 缺执行面 0（rc=0）**。叠线前的 4 条既有红随 R121
  并入主线而清零（见 §5 追记），本单没有重复落那批 hunk。

## 2. 证据

### 2.1 尺子自检（16 格，从已执行格子反解）

```
SELFTEST OK: 16 格（反解：M×3 / P×3 / R×6 / V×4）
```

新增 5 格：`violation-branch-merged-backlog-is-named`（合成违例必红）/
`reverse-branch-merged-in_review-not-red` / `reverse-branch-not-merged-backlog-is-open-not-red`（反向对照）/
`mutation-rule-blind-R4`（摘掉 R4 后同一违例必须看不见）/ `parser-extracts-branch-not-path`（路径不冒充分支）。

### 2.2 现状面实测（对账前，新规则的真实命中）

```
扫描面=gitcode/main | backlog 23 份 | 主线点名到的 TASK id 16 个 | 落差 2 条 / 上限 0 条 / 超限 2 条
  落差 STALE-BRANCH TASK-014 status=backlog :: 分支 fix/guard-docstring-correct-measurement 已并线 —— Merge fix/guard-docstring-correct-measurement: 清积压（自动合入，moon check 0 e…
  落差 STALE-BRANCH TASK-015 status=backlog :: 分支 fix/guards-parse-dead-after-marker-clear 已并线 —— Merge remote-tracking branch 'origin/fix/guards-parse-dead-after-marke…
BACKLOG_STALENESS=exceed 落差 2 条 > 上限 0 ⇒ 超 2 条
rc=1
```

### 2.3 对账后

```
扫描面=gitcode/main | backlog 23 份 | 主线点名到的 TASK id 16 个 | 落差 0 条 / 上限 0 条 / 超限 0 条
BACKLOG_STALENESS=within 落差 0 条 <= 上限 0
rc=0

扫描面=docs/tasks/backlog | 台账 23 份 | 违例 0 条 | 诊断 0 条
PASS backlog 顶层键唯一、抬头齐全且无控制字符
```

### 2.4 三条任务的合并/删除证据

| 任务 | 分支 | 证据 |
|---|---|---|
| TASK-014 | `fix/guard-docstring-correct-measurement` | 并线 `e3f76387`（master 祖先）；`git ls-remote` 两端均无该 ref |
| TASK-015 | `fix/guards-parse-dead-after-marker-clear` | 并线 `f84eac58`（master 祖先）；两端均无该 ref |
| TASK-013 | `feat/guard-check-merge-markers` | 两端均无该 ref；能力已在主线 `scripts/blackbox/check_merge_markers.py`（`510b1ff0` 落尺、R74 接 CI、电池两格），冲突标记处置见 TASK-001 |

### 2.5 判据设计（为什么是离线、窄口径）

- 分支名从 yaml 正文反解，前缀白名单 `feat/fix/slave/docs/chore/ci/refactor/test`；
  `.md/.mbt/.mbti/.py/.json/.ya?ml/.sh/.ps1/.txt` 尾巴过滤 ⇒ `docs/agent-map.md`、`src/ops/x.mbt`
  这类路径不冒充任务分支。
- 只比对**主线 subject**（`git log --format=%s`），不查远端 refs、不碰网络 ⇒ CI 与副机都能离线判。
- `status` 只在 `backlog` 时判红；`in_review/done` 不判（与 R1 的 `UNSTAMPED` 同口径）。

## 3. 任务分配记录

- 本单由指挥官直接完成，未派子代理：改动面 5 文件（1 尺 + 1 文档 + 3 任务台账），
  且判据设计需要对 R1 盲区做逐条反证，拆给子代理的交接成本高于直接执行。

## 4. 资源消耗

- 工时：约 4 分钟（11:33–11:37，含全量电池一次）。
- 电池 3 次（叠线前 62 格 ×2、叠线后 63 格 ×1）；相关守卫复跑 10 次；无构建、无网络调用。

## 5. 遗留风险

1. **叠线前 master 既有红 4 条（已随 R121 并线归零，非本单遗留）**：
   - `check_scripts_index` rc=1：`check_fmt_gate.py` 未在 `scripts/README.md` 登记；
   - `check_battery_count_doc` rc=1：锚点 85/47/56 vs 实际 86/48/57；
   - `check_fmt_gate` rc=2 exp=0：SPECIAL_CASE 丢失，且本机 `moon fmt --check` 量不出来；
   - `check_selftest_inventory_doc` rc=2：上一条导致 `check_battery_count_doc --selftest` 红（X4 级联）。
   四条的形状同源：主线合线时丢了 R121 的接线修复（README 条目 / 锚点 / SPECIAL_CASE）。本单开工时
   master 为 `cd697333`，四项均实测复现；交单前主机把 R121 并入主线（master 前进到 `8e6e5444`），叠线后
   四项全部转绿（见 §9）。**本单没有重复落那批 hunk**，根因与证据保留在此，避免下次误判为 R123 遗留。
2. 三条任务转 `in_review` 而非 `done`：`done` 受 R2 约束（主线 subject 必须点名该 id），而它们的历史
   merge subject 没有任务号。owner 盖章时可一次转 done，本单提交 subject 已点名 TASK-013/014/015，
   并线后 R2 即可查到点名证据。
3. R4 的已知盲区：分支删除但从未以同名 subject 合入的任务（如 TASK-013）不会被自动抓——判据刻意保守，
   宁可漏报也不把「删分支＝已完成」当成事实。

## 6. 后续建议

- R121 并线后复跑电池已兑现：63 格 / 失败 0（§9）。后续每次叠线仍要复跑，并观察 R4 是否有新增命中。
- 巡检侧（whisperer / fist-gate）生成「清理分支冲突标记」类任务时，优先用分支并线证据去重，
  避免任务分支消失后任务池长期悬空。
- owner 给 TASK-013/014/015 盖章转 done；此后同类落差由 R4 + R2 双面兜住。

## 7. 超额内容

- 顺手核对了 `check_backlog_status_staleness` 的三条旧规则在本次改动下零回归（V×3/R×4/M×2/P×2 旧格全绿）。
- 额外验证 `check_doc_surface` / `check_doc_dup` / `check_exit_code_contract` 三条相邻守卫均 rc=0。

## 8. 来源

- 尺子：`scripts/check_backlog_status_staleness.py`（R4 + 5 格自检）、`scripts/README.md` 条目同步。
- 合并证据：`e3f76387`、`f84eac58`、`510b1ff0`；分支存在性：`git ls-remote --heads gitcode` / `origin`（2026-10-22 现读）。
- 台账：`docs/tasks/backlog/TASK-013…`、`TASK-014…`、`TASK-015…`（均含 `status_note`）。
- 电池读数：`python scripts/run_guards.py`（62 格 / 失败 4 / SKIP 5 / 缺执行面 0）。

## 9. 追记（叠线后终读）

- 开工基线 `cd697333`；交付期间主机把 R121 快进并入主线，master 前进到 `8e6e5444`。
- R123 以 merge 方式叠上新主线（`22e73037`），冲突两处：`scripts/README.md`（R121 新增条目/锚点 vs
  R123 更新同一条任务池尺条目）与 `memory/2026-10-22.md`（两单都在文件尾追加）——均按「两边都保留」解析：
  R121 的 `check_text_control_chars` 条目 + R123 的四规则条目；两段日志 R121 → R123 按时间序各留一份。
  `<<<<<<<` / `=======` / `>>>>>>>` 零残留，CRLF 三元组逐份复核（README 1141 行、memory bareLF=0）。
- 叠线后权威电池（推送后现读）：**63 格（手写 63 + 自动 0）/ 失败 0 / SKIP 5 / 缺执行面 0，rc=0**；
  `check_delivery_gap` 汇总 0 个未推送提交。
- 关键格：`check_backlog_status_staleness` 落差 0 / `check_text_control_chars` 文本面干净 /
  `check_battery_count_doc` 锚点 87/41/49/0/58/26/5 逐键一致 / `check_selftest_inventory_doc` 28 条族逐一对表通过。
