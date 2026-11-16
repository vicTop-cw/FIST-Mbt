# 轮 354 唤醒巡检报告（ExploreWatchdog · 2026-11-16）

## 结果摘要

- **WIP 冻结判定**：r353 收口提交后 `git status --short` = 6 M + 2 untracked（8 件），
  numstat 与 r326~r353 逐字同（bugs.md 216/0 零再增长、improvement-plan 7/1、
  target.md 1/1、README.md 2/1、run_guards.py 9/0、engine_circuit_test.mbt 5/0；
  untracked：check_mcpcf_db_isolation.py + pipeline_mode_loop.md，逐字同 r353 收口后）
  ⇒ **WIP 非冻结增长后静止第 35 轮**，R192 车道自 r318 后持续停摆、
  src/** + run_guards.py 仍 M ⇒ **巡检分支**。
- **Round C 三件**（BUG-527 治本 / BUG-530 修复 / check_usage_tool_count 注册）维持**过期不执行**（src/** 未解禁）。
- **换面巡检 `check_delivery_gap`**（R46「本地领先 = 已交付？」尺；
  rc=0 无断层 / rc=1 存在未推送提交 / rc=2 判据无法自证）：
  - `--selftest` **rc=0**（**8/8 格**：纯函数三档 + 真仓库 提交未推/推送后 两例）
  - 实跑三基准对表：

    | base | ahead | files | pushed | rc |
    |---|---|---|---|---|
    | `origin/master`（判据默认） | 285 | 397 | False | 1 |
    | `gitcode/main` | 284 | 396 | False | 1 |
    | `origin/main`（真整合线） | **95** | **102** | False | 1 |

  - **关键新发现（判据基准错位 · 修正 patrol-130 起的误读）**：
    - `check_delivery_gap` 的默认基准 `origin/master`（tip `cdb241acf`）是**陈旧分支**：
      它是 `origin/main`（tip `704479864`）的祖先，`origin/main` 比它**新 190 个提交**
      （`git rev-list --count origin/master..origin/main` = 190），且含全部已交付实质工作
      （`1e25dea64` db_path trim / `cfc84b616` BUG-470 flip / `8b1a0fd11` commissar_gc /
      `4d90503c5` JS-FFI 等 `git branch -r --contains` 逐条核验均落在 origin/main）。
      用陈旧分支量 ⇒ 表观 **285** 是**虚高读数**。
    - 对真整合线 `origin/main` 量：**真实未交付 = 95 提交 / 102 文件**，其中
      **94 条纯 `docs(reports)` 自指巡检报告（r326~r353）+ 1 条实质**
      （`98a4111e5 fix(doc-surface): 轮 292 修 check_doc_surface J14/J16 工具计数漂移 182→183`，
      实测 `git branch -r --contains` = NOT in any remote）。
    - ⇒ **不存在「大量未交付实质工作」**：patrol-130（2026-11-04，读 204）起的
      「自指增量」定性其实成立（95 里 94 自指 + 1 实质漏网）。本会话初期一度按
      「gap 204→285 增长含 ~55 实质提交」拟立「升级定性」，经逐条 `git branch -r --contains`
      核验**证伪**（那 55 条里 54 条已在 origin/main、仅 `98a4111e5` 未达任何远端）
      ——这是本轮 systematic-debugging 第一阶段的实锤纠错，而非真发现「实质工作积压」。
  - **处置**：判据默认基准错位属**立账候选**（`check_delivery_gap` 默认基准
    `origin/master` 陈旧 ⇒ 建议改 `origin/main`，或文档点名「整合线=origin/main、
    量断层用 `--base origin/main`」）。但 `memory/bugs.md` 属 WIP 禁区本轮不碰
    ⇒ **不立 BUG 号**，记报告 + 当日日志，留 WIP 收口时 / 专门轮次立账。
    该尺为**诊断面非 CI 门**（无假红/假绿），严重度低；价值在「别让 285 这个虚高数
    误导后续轮次/owner 以为有 285 条实质工作未交付」。
- **零漂移判据**：`check_tools_sync` rc=0（183 工具单一真源一致）/
  `check_instruction_budget` rc=0（AGENTS.md 50440/65536 全章节可见）。
- **禁区零碰**：8 WIP 文件（含 bugs.md）零改零提交。
- **FIST 闭环**：T0r110 六步全链（publish → agent_acl_grant → claim → execute → submit → verify，
  wd-r354 / ns watchdog / verify status=已完成、completed_by=wd-r354 / deliverable=本报告，
  后台串跑收口；patch_esm_main 探针先行防 MemoryError）。

## 资源消耗

| 项 | 读数 |
|---|---|
| 判据自跑 | check_delivery_gap --selftest rc=0（8/8 格）+ 实跑三基准（285/284/95，均 rc=1）；check_tools_sync rc=0；check_instruction_budget rc=0 |
| 核验命令 | `git merge-base --is-ancestor` / `git rev-list --count` / `git branch -r --contains`（逐条核验实质提交落点，证伪「实质工作未交付」） |
| FIST 闭环 | 1 任务（T0r110）六步 |
| 提交 | 1（本报告，scoped `--` 路径） |

## 任务分配记录

| 角色 | 动作 |
|---|---|
| 统帅（本实例） | git status/log 冻结判定、换面巡检选面与执行、三基准对表、逐条落点核验证伪、零漂移复跑、报告撰写、FIST 闭环、scoped 提交 |
| 子代理 | 未派（巡检分支、全部为单命令判据 + git 只读核验 + 收口提交、无并发收益） |

## 遗留风险

1. WIP 8 件仍冻结（第 35 轮），Round C 三件过期——需 owner/R192 车道收口 WIP 后才可执行。
2. **交付断层（本轮修正口径）**：对真整合线 `origin/main` 实为 **95 提交未交付
   （94 自指巡检报告 + 1 实质 `98a4111e5`）**，非判据默认基准给的 285。推送属
   **owner 门控 + 不可逆 + pre-push 守卫（BUG-566）挡 direct push**，本实例不代行。
   **推送方案**（供 owner 一键裁决，不自动执行）：`git push origin main`
   （把 95 条自指报告 + `98a4111e5` 落到 GitHub main；`gitcode` 侧同理
   `git push gitcode main` 或按其整合线）。owner 若需先收口 WIP 8 件再推，
   则本轮维持不推。
3. **判据基准错位（立账候选，无 BUG 号）**：`check_delivery_gap` 默认基准
   `origin/master` 陈旧（落后真整合线 190 提交），表观 285 虚高。留 WIP 收口后立账。
4. **外来账检测面**（沿用 r348 判定）：白名单外外来账 23 条（BUG-613~635）悬待 owner 裁决，
   属 BUG-565「跨项目误落账持续模式」；本轮未复跑该面（换面到 check_delivery_gap），
   规模维持 r348 读数。
5. OFM 端点（127.0.0.1:18326）持续不可达——属预期基线（服务未在本机运行），非缺陷
   （本轮未复跑，沿 r353 读数）。
6. 换面巡检队列余量：mcp_smoke / 其余未巡 `check_*` 面（同源收敛面短收尾即可，勿空转）。

## 后续建议

- 下轮继续巡检分支，换面队列推进（本轮 check_delivery_gap 已用，避免与近期已巡面重复）。
- **量交付断层一律 `--base origin/main`**（真整合线），不再采信判据默认的 285 读数。
- WIP 收口时优先：① 立 `check_delivery_gap` 默认基准错位账；② 裁决 95 条自指报告 +
  `98a4111e5` 的推送路径。
- R192 车道若恢复，优先收口 Round C 三件。
- 外来账 23 条（BUG-613~635）建议 owner 一次性裁决（搬移 vq 仓 / 登记 WHITELIST）。

## 超额内容

无。

## 来源

- `git status --short` / `git log --oneline -5` / `git diff --numstat`（2026-11-16 本机）
- `python scripts/check_delivery_gap.py --selftest` + 实跑三基准
  （默认 origin/master / `--base gitcode/main` / `--base origin/main`）
- `git merge-base --is-ancestor origin/master origin/main`（= 祖先）/
  `git rev-list --count origin/master..origin/main`（=190）/
  `git rev-list --count origin/main..main`（=95）/
  `git log --oneline origin/main..main`（94 docs(reports) + 1 `98a4111e5`）/
  `git branch -r --contains <c>`（逐条核验实质提交落点）
- `python scripts/check_tools_sync.py` / `python scripts/check_instruction_budget.py`
- `python scripts/patch_esm_main.py` 探针（防 FIST 链路 MemoryError）
- FIST 闭环 `temp/fist_r354_chain.sh`（后台串跑，回盘 `temp/fist_r354_out/`）
