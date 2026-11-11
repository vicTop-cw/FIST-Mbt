# 轮 208 唤醒巡检报告（WIP 冻结再测 + 根 stray-DB 面全量溯源 + 无新可修 bug 简短收尾）

- **时间**：2026-11-12 03:39（本地）
- **轮次**：r208（ExploreWatchdog）
- **前序**：r207（641e41554，reports/2026-11-12-r207-watchdog-wip-freeze-report.md）

## 并发 WIP 状态

| 项 | 读数 |
|---|---|
| mtime（承重 4 文件） | `mcpcf_embed_bug583_wbtest.mbt` 14:29 / `run_guards.py` 14:33 / `AGENTS.md` 14:34 / `memory/bugs.md` 14:35（均 Nov 11，本轮实测）|
| 冻结时长 | **~13.1h**（14:35:33 → 11-12 03:39，较 r207 的 ~12.4h 又 +0.7h）|
| diff 足迹 | `git diff --shortstat` = **15 文件 +281/−64**（与 r198–r207 基线逐字一致，无暂存）|
| 新提交 | r207（641e41554）后零新提交；HEAD 仍 = r207 |
| WIP 定性（r198 已立） | **BUG-591 ⑤** + **BUG-588 OPEN→FIXED**（`bug583_04` 锁关闭）+ BUG-583 缺口钉成 `mcpcf_embed_bug583_wbtest.mbt` 假锁；方向对、量成型 |
| 状态位 | 已知挂起，r193 已升级 owner 决策，按既定不再重复上报 |

**连续零变化**：r198–r208 **十一连轮** diff 足迹与承重 mtime 逐字无变化 ⇒ WIP 死挂/放弃定性彻底坐实（r193 已升级 owner，维持既定，不重复上报）。

**禁区遵守**：WIP 的 15 个文件本轮未 touch（只读 + `git status`/`git diff --shortstat`/`stat` 观测，不跑 WIP 内部命令、不跑 `moon test`——WIP 占用 `src/**` + `scripts/run_guards.py`，任何 moon 构建/测试都跑在脏基线上）。

## Round C 队列

确认过期（r195–r207 已核实，不重复、不重推导）：BUG-527「摘 cc-link-flags」owner 否决（e0ef45c5e 回滚）/ BUG-530 已 FIXED（3699f012a）/ check_usage_tool_count 已注册（run_guards.py:175）。本轮未执行。

## 本轮实质：根 stray-DB 面全量溯源（比 r207 深一层，非重复定性）

r197/r207 只盯那个 0 字节 `fist-mbt.db `（尾随空格 stray）。本轮把**仓库根全部 7 个 .db 逐一溯源**（`stat` 体积/mtime + `git ls-files '*.db'` 跟踪态 + `grep` 产出点），补齐 r207 没看的层——这 7 个里除 1 个 stray 外**还有 6 个 156KB 夹具库**，来源此前从未定位：

| 根 .db | 体积 | mtime | 跟踪态 | 来源（grep 实测） |
|---|---|---|---|---|
| `fist-mbt.db` | 18,964,480 | 11-11 14:51 | 未跟踪（`*.db` ignore）| 真·自举台账（KEEP，FIST 记账面，**勿删**）|
| `alpha.db` | 159,744 | 11-11 14:31 | 未跟踪（ignore）| `src/store/multi_store_test.mbt:23` `reset_db("alpha.db")` |
| `beta.db` | 159,744 | 11-11 14:31 | 未跟踪（ignore）| `src/store/multi_store_test.mbt:53` `reset_db("beta.db")` |
| `wal-a.db` | 159,744 | 11-11 14:31 | 未跟踪（ignore）| `src/store/multi_store_test.mbt:175` |
| `wal-b.db` | 159,744 | 11-11 14:31 | 未跟踪（ignore）| `src/store/multi_store_test.mbt:176` |
| `wal-c.db` | 159,744 | 11-11 14:31 | 未跟踪（ignore）| `src/store/multi_store_test.mbt:177` |
| `pf-ok.db` | 159,744 | 11-11 14:31 | 未跟踪（ignore）| `src/store/store_sqlite_open_preflight_wbtest.mbt:91` `let path = "pf-ok.db"` |
| `fist-mbt.db `（尾随空格）| 0 | 11-11 14:37 | 未跟踪（**不**被 `*.db` 匹配⇒进 git status）| shell 重定向副产物（r197 定性，r204 守卫已修）|

**机制（读码定位，非猜）**：6 个夹具库全部来自 MoonBit 白盒测试用**裸相对路径**建库（`reset_db("alpha.db")` / `let path = "pf-ok.db"`，非 `base_dir()` 沙箱）⇒ `moon test` 从仓库根跑时夹具直接落进 cwd（仓库根）。体积均 159,744 字节（固定 schema 签名）、mtime 均 11-11 14:31（与 WIP 末次活动同时刻）。

**定性**：这是**已知且已文档化**的根泄漏模式，非新 bug——`scripts/cleanup_artifacts.py:8` docstring 早已点名 `alpha.db` / `wal-*.db` 为预期根产物；`.gitignore:15 *.db` 挡住它们（不进 git status）；`cleanup --check` 能抓（DIRTY）。**唯一真正污染 git status 的仍是那个尾空格 `fist-mbt.db `**（`.gitignore` 不匹配带空格变体，r204 已修守卫、留 owner 确认轮清）。

**为何本轮不修**：(a) WIP 占用 `src/**` ⇒ 修测试隔离后必须 `moon test` 验证，但会跑在脏基线上，结果无法归因；(b) 测试隔离属「已实现打磨」（最低优先级），且是已知已缓解（`cleanup`）已文档化模式，非 bug；(c) 属应独立成轮、走完整 FIST + 派单 + 验证的实质改动，非看门狗巡检 drive-by。⇒ **留 WIP 收敛后的独立轮**，届时可直接指 `multi_store_test.mbt` + `store_sqlite_open_preflight_wbtest.mbt` 两文件把夹具改沙箱路径。

## 已探面汇总（避免重复）

| 轮 | 面 | 结果 |
|---|---|---|
| r194 | OFM 端点 + byte-slice | 容忍诊断 / PASS |
| r195 | check_host_installable + byte budget | PASS / PASS |
| r196 | NUL-byte（src+scripts）| 干净 |
| r197 | untracked / stray-DB | 1 项 0 字节异常（定性：不立账不删，**未看守卫层、未看 6 夹具库**）|
| r198 | WIP diff 足迹 + WIP 定性 | 15 文件 +281/−64 冻结、方向合法 |
| r199 | untracked 工具目录 + ignore + r198 补提交 | 三组外部产物补 ignore（已验证）|
| r200 | WIP 冻结再测 + check_host_installable 复探 | 冻结 ~7.7h；宿主可装性 PASS |
| r201 | WIP 冻结再测 + AGENTS.md 字节预算复探 | 冻结 ~8.0h；50303/65536 PASS |
| r202 | WIP 冻结再测 + 无新面（勿空转） | 冻结 ~8.5h、+281/−64 逐字无变化；无新发现 |
| r203 | WIP 冻结再测 + 无新面（勿空转） | 冻结 ~9.0h、+281/−64（五连轮）；无新发现 |
| r204 | stray-db 守卫缺口（r197 没看的层）+ 修复 | 冻结 ~10.0h（六连轮）；修 stray_root_dbs 尾空格漏判 + R1/R1b/R2 自证；selftest rc=0 |
| r205 | WIP 冻结再测 + 无新面（勿空转） | 冻结 ~10.5h（七连轮）；stray-db 守卫已修、文件挂账；无新发现 |
| r206 | WIP 冻结再测 + 无新面（勿空转） | 冻结 ~11.0h（八连轮）；无新发现；漏提交漏记账，r207 补 |
| r207 | WIP 冻结再测 + r206 补收口 + 无新面 | 冻结 ~12.4h（十连轮）；r206 补提交+日志补条目；无新发现 |
| **r208** | **WIP 冻结再测 + 根 stray-DB 面全量溯源（比 r207 深一层）** | **冻结 ~13.1h（十一连轮）；7 个根 .db 逐一溯源（6 夹具库→2 测试文件裸相对路径，已知已文档化非新 bug）；无新可修 bug；不修（留 WIP 收敛独立轮）** |

## FIST 闭环

ns `iter-1112r208w`：publish（T0，附 BUG-411 两道门警告）→ agent_acl_grant（wd-r208 can_write=true，granted_rows 2bc21cb06938e77a 落库）→ claim（已领取）→ execute（执行中，deliverable 指本报告）→ submit（待验收）→ verify（**已完成**，completed_by=wd-r208）⇒ **全链绿，T0 收口**。

## 结果摘要

- 并发 WIP 冻结 **~13.1h 逐字无变化**（15 文件 +281/−64，承重 mtime 仍 14:29–14:35），r198–r208 **十一连轮**零变化 ⇒ 死挂定性彻底坐实，维持 r193 已升级 owner 的已知挂起，不重复上报。
- **本轮增量（比 r207 深一层）**：把仓库根全部 7 个 .db 逐一溯源——6 个 156KB 夹具库（alpha/beta/wal-a/b/c + pf-ok）全部出自 `multi_store_test.mbt` + `store_sqlite_open_preflight_wbtest.mbt` 用**裸相对路径**建库，`cleanup_artifacts.py:8` docstring 早已点名 ⇒ 已知已文档化模式，非新 bug。唯一污染 git status 的仍是尾空格 `fist-mbt.db `（r204 守卫已修，留 owner 确认轮清）。
- **无新可修 bug**：Round C 过期、WIP 占用 src/**（不跑脏基线 moon test）、测试隔离属低优先级打磨留独立轮 ⇒ 无代码改动，简短收尾。

## 资源消耗

- 模型：qwen3.8-27b（本会话）；工具：git（status/diff-shortstat/log/ls-files/stat）+ `grep`（夹具库产出点溯源 2 支）+ `python scripts/fist.py`（FIST 网关 6 调用：publish + acl/claim/execute/submit/verify）。
- 未跑 mcp_smoke / check_host_installable / check_instruction_budget / cleanup_artifacts.py（非 --check 清删）等既有判据（「勿空转」——承重面无任何变化，重跑无信息增量）；本轮 `cleanup --check` 只读观测 stray-DB 面，不触发删除。
- 未 spawn 子代理（无可分配实质工作——WIP 占用、Round C 过期、无新可修 bug）。

## 任务分配记录

- 本轮无子代理派单。原因同 r199–r207：可分配实质工作（修 bug / Round C / 测试隔离打磨）全被并发 WIP 占用或属应独立成轮的低优先级项，本轮实质是「冻结再测 + stray-DB 溯源 + 记账」，属指挥官亲自面（金条四）。

## 遗留风险

- WIP 挂起 **~13.1h**（15 文件 +281/−64 成型未收口，十一连轮零变化），等 owner A~D 裁决（不重复上报）。
- `fist-mbt.db `（尾随空格、0 字节）仍未跟踪未忽略：守卫 r204 已修，WIP 收口 / owner 确认轮建议一并 `python scripts/cleanup_artifacts.py`（非 --check）清掉（同批会清 6 个夹具库），防污染 `git status`。
- **新增**：6 个 156KB 测试夹具库（alpha/beta/wal-a/b/c + pf-ok）落仓库根 = `multi_store_test.mbt` + `store_sqlite_open_preflight_wbtest.mbt` 用裸相对路径建库。已知已文档化、`.gitignore` 挡住不进 git，但污染工作树 + 令 `cleanup --check` 恒 DIRTY。**建议 WIP 收敛后的独立轮**把这两文件夹具改沙箱路径（`base_dir()`），从根上止住根泄漏（当前靠 `cleanup` 周期性清）。
- 看门狗自身记账面：r206 曾「报告写了但未提交未记账」⇒ r207 已补；本轮收尾前已核「报告将提交 + 日志将追加」两格（见下）。
- 本地领先远端 128+ commit（历史积压，维持同口径、本轮不重核远端，推与否归 owner）。

## 后续建议

- WIP 十一连轮零变化已把「死挂」定性彻底坐实：建议 owner 直接评估收口那 281 行（r198 定性：方向对、量成型，不必作废）；收口时 `cleanup`（非 --check）可顺带清掉 7 个 stray .db。
- 测试夹具根泄漏（本轮新溯源）留 WIP 收敛后的独立轮：改 `multi_store_test.mbt` + `store_sqlite_open_preflight_wbtest.mbt` 两文件把 `reset_db`/`open` 夹具路径走 `base_dir()` 沙箱，从根止住 `cleanup --check` 恒 DIRTY。
- 无其它建议（无新可修 bug）。

## 超额内容

- 根 stray-DB 面全量溯源（比 r207 深一层：r207 只知 0 字节 stray，本轮补齐 6 夹具库的精确产出点与机制）——属既有 stray-DB 面的必要深化，非既有判据重跑。

## 来源

- 本仓 `git status --short` / `git diff --shortstat` / `git log --oneline` / `git ls-files '*.db'` / `stat` 实测（2026-11-12 03:39）。
- `grep`（`alpha.db|beta.db|pf-ok.db|wal-a.db|wal-b.db|wal-c.db` @ scripts + src）产出点溯源实测。
- `python scripts/cleanup_artifacts.py --check`（只读，DIRTY 点名 7 个根 .db + 8649 temp/ 文件）实测。
- `python scripts/fist.py call` 六次回执（T0/iter-1112r208w 全链绿至已完成，completed_by=wd-r208）。
- r207 报告（reports/2026-11-12-r207-watchdog-wip-freeze-report.md）、r204 stray-db 守卫修复、r197 stray-db 定性、`cleanup_artifacts.py:8` docstring。
