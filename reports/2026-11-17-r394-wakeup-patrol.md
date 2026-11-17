# 轮 394 巡检报告

> FIST-Mbt ExploreWatchdog 唤醒轮（Windows 计划任务，每 30 分钟无窗）。
> 生成时刻：2026-11-17。报告文件即本轮 FIST 任务的 deliverable。

## 一、WIP 收口核查（巡检分支判定）

`git status --short` 与 r393 一致：**6 M + 1 untracked**，无新收口、无新起 WIP：

| 文件 | numstat | 状态 |
|---|---|---|
| dist/fist-mbt.js | 41402/35319 | M（中止轮再生，r384 记录，未提交） |
| memory/bugs.md | 216+ | M（外来账冻结，r378 起，第 69+ 轮，BUG-592~636） |
| memory/target.md | 1/1 | M（冻结巡检 WIP，本轮内容级确认为陈旧 Round 24 行） |
| scripts/README.md | 1/1 | M（iter-r192 车道 F 提交③在途） |
| scripts/check_plan_landing.py | 120/24 | M（iter-r192 车道 F 在途） |
| templates/pipeline_mode_loop.md | 1/1 | M（J8 修复在途） |
| reports/2026-11-17-iter-r192-report.md | untracked | iter-r192 收口报告（**在途**） |

⇒ **iter-r192 收口进行中**（车道 F 提交③未落库），禁区零碰。`src/**` 与 `scripts/run_guards.py`
维持 r385 确认的已解禁态，但 **Round C 队列（既定迭代目标）已由 r385 逐项核实全消并移交 owner 设
下一目标** ⇒ 本轮无既定目标可执行，走**巡检分支**：非阻塞换面 + FIST 闭环记账。

本轮巡检面**全绿**（无新红面、未立新账）。换面与两项内容级核实详见第二节、第三节。

## 二、换面巡检：check_arg_face_strict（行为级参数面严格性 · 零漂移）

**为何选此面**：r393 mbti_sync（修真回归）/ r392 store_tables_wired + demo_isolation /
r391 ofm_endpoint / r390 entry_paths / r389 release_asset_names / r388 tool_required_sync /
r387 host_installable / r386 battery_count_doc ⇒ 近 8 轮换面清单里 **check_arg_face_strict
未覆盖** ⇒ 不撞面。该面是**行为级真门**：真跑 100 把 `check_*.py` 判据、逐一把未知旗标
`--definitely-not-a-real-flag` 喂进去、按结果判——每把判据遇到未知旗标必须 rc≠0 拒绝出绿才过。
守的是 AGENTS.md「新判据必须拒绝未知旗标」铁律（同族实测四次：R197 bug_ledger_shape /
R198 mcp_stdio_purity / R199 warning_ledger / R206 known_red_until——自检开关拼错 = 静默失去自检）。

### 实跑（零漂移）

`PASS 参数面全部严格：100 把判据遇到未知旗标都拒绝出绿（rc≠0）`，`RC=0`。

WIP 里的 `check_plan_landing.py`（车道 F 在途，120/24）落在被扫的 100 把之内、其参数面同样严格
——本轮换面顺带佐证该在途文件未知旗标拒绝未破。

## 三、两项内容级核实（本轮增量发现，均非新缺陷）

### 3.1 check_plan_landing.py --selftest 71 格全绿（佐证车道 F 提交③已就绪）

`SELFTEST OK（71 格：… P10 磁盘采集按段 7 格（纯判据 3 / fixture 宇宙 3 / main 接线源码格 1：
ast 核调用点、引文不喂针——判例-30）…）`，`RC=0`。

⇒ **iter-r192 车道 F 提交③（check_plan_landing.py + scripts/README.md + templates/pipeline_mode_loop.md
J8）代码面已验证就绪、可提交**。本轮只验证、不代提交：提交③是 iter-r192 收口的规划独立提交，而收口
仍在途（车道 M/X/Y 未回传），单代提交一件不属巡检职责（交接建议见第七节）。

### 3.2 target.md 工作树改动内容确认（前几轮注记的内容级细化）

r386~r393 均把 target.md 注为「冻结巡检 WIP」（1/1 M）而未读内容。本轮读 diff 确认：工作树行是
**陈旧的 Round 24 巡检摘要行**（内容「[Round 24 巡检] WIP 面 9 文件零收口（同 R21~R23，HEAD=5cbe4ce52）；
… 报告 reports/2026-11-10-watchdog-patrol-round24.md」，无尾换行），**顶掉了真实目标行**
（committed HEAD 行「iterate-1102 批次闭环（2026-11-02）…」）。

- **性质判定**：与 r192 报告自披露第 2 条「日志覆盖事故」（统帅未先 read 就写 memory/2026-11-17.md）
  **同族**——把某轮巡检摘要行写进本应持有目标的态文件、且长期未提交，已在工作树躺 65+ 轮（r378 起冻结）。
- **本轮不代改**（冻结 WIP 面 + 回退需 owner 显式授权）。
- **交接建议**：解冻/清理 WIP 时 `git restore memory/target.md`（回到 committed 目标行）；若确需状态
  跟踪文件，应为专门文件而非 target.md。

## 四、零漂移常设面

- `check_tools_sync`：`PASS 工具单一真源一致：server.mbt 注册 183 个，AGENTS/README/deliverable/
  scoring_rubric 对齐；R3b/R7 扫现状面 169 份，历史面豁免 25 份；R8 清单分组 19 组 ΣN=183`，`RC=0`。
- `check_instruction_budget`：`AGENTS.md = 50440 字节 / 预算 65536（实际注入上限 50440）`，
  `PASS 指令文件在预算内（全部章节可见）`，`RC=0`。
- `patch_esm_main` 探针：10 bundle 全 `up to date`，`total patched: 0`，`RC=0`（防 BUG-380 垫片转发 +
  r287 型 patch 读整 bundle MemoryError；FIST 链首发前先行，非环境态）。dist/fist-mbt.js 76k 行再生
  （在途）未波及 `_build/` bundle 面。

## 五、FIST 闭环

**T0r150 六步全链 rc=0**（wd-r394 / ns watchdog / `temp/fist_r394_chain.sh` 稳健 TID 提取后台串跑，
patch_esm_main 探针先行 10 bundle 全 up to date / total patched 0）：
publish rc=0 → TID=T0r150 → acl rc=0 → claim rc=0 → execute rc=0 → submit rc=0 → verify rc=0。
verify 字段：`status=已完成`、`completed_by=wd-r394`、`assignee=wd-r394`、
`deliverable=reports/2026-11-17-r394-wakeup-patrol.md`、`namespace=watchdog`、
`created_at=2026-11-17T14:44:38Z` / `updated_at=2026-11-17T14:44:44Z`。

## 六、禁区与立账

- **禁区零碰**：6 个 WIP 修改文件 + 1 个 untracked 报告零改零提交；本轮巡检面
  （check_arg_face_strict / check_tools_sync / check_instruction_budget / patch_esm_main probe /
  check_plan_landing --selftest）对 WIP 文件**只读**（check_plan_landing --selftest 跑在途脚本但不写
  任何文件；check_arg_face_strict 跑 100 把判据、各读各的扫描面，不写 WIP 文件）。
- **未立新账**：本轮无新红面。两项增量发现（提交③就绪 / target.md 陈旧 Round 24 行）属 iter-r192
  在途态的内容级细化、不构成新缺陷 ⇒ 不立新 BUG 单，并入本报告记录 + 交接建议。

## 七、交接建议（owner / 下一轮）

1. **iter-r192 收口**：车道 F 提交③（check_plan_landing.py + scripts/README.md +
   templates/pipeline_mode_loop.md）已验证就绪（3.1），待车道 M/X/Y 回传（或判丢失）后可作为独立
   提交落库；dist/fist-mbt.js 再生需巡检专门轮处理（核重投影正确后提交）。
2. **target.md**：回到 committed 目标行（3.2），一行 `git restore`，需 owner 授权。
3. **bugs.md**：45 条冻结（BUG-592~636），入账需 owner 解冻。
4. **车道 M/X/Y**：前会话未回传（工作面不在树、报告无追加段）⇒ 判丢失或重派，需 owner 定夺。

## 八、结论

本轮巡检分支：**换面 check_arg_face_strict 100 把零漂移 + 两项内容级核实**（check_plan_landing
selftest 71 格全绿佐证提交③就绪 / target.md 为陈旧 Round 24 行）。零漂移常设面 check_tools_sync 183 /
instruction_budget 50440/65536 / patch_esm_main 0 patch 均 rc=0。WIP 面 6M+1untracked 与 r393 一致 ⇒
iter-r192 收口进行中、禁区零碰。无新红面、未立新账。FIST 闭环见第五节。
