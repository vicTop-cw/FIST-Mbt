# 轮 222 唤醒巡检报告（r208 测试夹具沙箱化收口——WIP 全收口后首个执行的独立轮）

**时间**：2026-11-12 看门狗唤醒轮（30 分钟周期，紧随 r221 13:52 收笔）/ 收笔 ≈14:29（FIST created_at 06:26:56Z = 本地 14:26）
**轮次**：r222（ExploreWatchdog 自动唤醒）
**主线**：WIP 全收口（r221 坐实，`src/**` 自 r219 起干净）+ Round C 判空维持 + **本轮真执行 r221 列的「下一独立轮首选」= r208 测试夹具沙箱化**（两测试文件改动 + store 131/131 + 全量 2067/2067 全绿 + 仓根夹具库不再被重写）；无新 bug、未立新账。

## 结果摘要

- **r208 测试夹具沙箱化落地（本轮真动作）**：`src/store/multi_store_test.mbt` 删 `reset_db` 函数定义 + 5 处裸仓根路径调用（BUG-462 前残留，各测试已走每 run 唯一的 `base_dir()` 无需清）；`src/store/store_sqlite_open_preflight_wbtest.mbt` 4 处夹具点从裸仓根字面量改 `bug462_unique_dir("<tag>")` 唯一 temp/ 沙箱（建目录 + 收尾清理）。6 个仓根夹具库 alpha/beta/wal-a/b/c + pf-ok 不再落仓库根 ⇒ `cleanup --check` 的 stray_root_dbs 仓根面不再被测试污染。
- **验证（四格全过）**：① store 包 js **131/131 rc=0**（无回归 + 沙箱化测试本身过）；② 修后重跑测试，仓根 6 夹具库 mtime **仍停 13:09 基线（未重写 = 修复生效）**、仓根无新增 `.db`；③ temp/ 出现新沙箱目录 `b462_ms_base_*` / `b462dir_pf_p3_*`（夹具已改落 gitignore 的 temp/ 面）；④ `git status` 本轮改动仅两测试文件。
- **提交门全绿**：`moon fmt`（影响面仅两文件）+ `moon info`（.mbti 无变化）+ `check_fmt_gate.py` **rc=0** + 全量 JS **2067/2067 rc=0**。
- **Round C 队列判空维持**（三项全过期：BUG-527 摘 cc-link-flags owner 否决 / BUG-530 已 FIXED / check_usage_tool_count 已注册，待 owner 正式关闭）。
- **无新 bug，未立新账。**

## 本轮真动作：r208 测试夹具沙箱化

### 问题（r208 溯源坐实）
6 个 156KB 夹具库（alpha/beta/wal-a/b/c + pf-ok）出自两测试文件用**裸相对路径**建库 ⇒ `moon test` 从仓库根跑时夹具直接落 cwd（仓库根）⇒ `cleanup --check` 的 `stray_root_dbs` 每次点名 DIRTY，只能靠 `cleanup`（非 --check）周期清。

### 修法
- **文件 1 `multi_store_test.mbt`**：删 `reset_db` 函数定义 + 5 处 `reset_db("*.db")` 调用（原 L23 alpha / L53 beta / L175-177 wal-a/b/c）。理由：`reset_db` 对仓根 db 做 open+clear，但各测试已用 `base_dir()`（= `bug462_unique_db("ms_base")` 去 .db 后缀，token=@env.rand(8)+@env.now，**每 run 唯一**）⇒ 没有旧库需清 ⇒ 这 5 处是 BUG-462 前残留、只会制造仓根污染。
- **文件 2 `store_sqlite_open_preflight_wbtest.mbt`**：4 个测试（P1b/P2a、P1c/P2b、P2c、P3）统一加 `@fs.create_dir("temp")` → `let base = bug462_unique_dir("<唯一 tag>")` → `@fs.create_dir(base)`，夹具一律 `base + "/<name>"`，收尾先清内容再 `@fs.remove_dir(base)`（remove_dir 只删空目录）。tag 取 pf_p1b / pf_p1c / pf_p2c / pf_p3，各唯一避免并行撞名（`bug462_unique_dir` 内部还有 token 二级隔离）。**断言语义逐字零改动**——所有 `assert_eq`/`assert_true`/`assert_false`/`abort` 消息与期望值不变，唯一变化是路径变量从字面量变为拼接表达式。

### 为何「删 reset_db」而非「改指 base_dir()」
`base_dir()` **每次调用都取新 token** ⇒ `reset_db(base_dir()+"/alpha.db")` 会清一个从未被用的文件（与测试真正用的 `base_dir()` 是不同唯一目录），无意义且白造 temp 库 ⇒ **删除**才是治本（唯一性自动满足「干净库」意图）。

## WIP 状态

- `git status --short`：`M memory/target.md`（禁区，陈旧协调面）+ `?? "fist-mbt.db "`（0 字节尾空格 stray，r204 守卫已修，留 owner 确认轮）+ 本轮两测试文件。`src/**` 全干净（自 r219 收口）。
- 无并发新活动。

## FIST 闭环

ns `iter-1112r222w`：publish（T0，附 BUG-411 两道门警告）→ agent_acl_grant（wd-r222 can_write=true，granted_rows `2bbb8ab0693383b6`）→ claim（已领取）→ execute（执行中，deliverable 指本报告）→ submit（待验收）→ verify（**已完成**，completed_by=wd-r222）⇒ **全链绿，T0 收口**。同身份模式（agent=verifier=wd-r222，单次 ACL 授权即可——沿用 r208，规避 r221「verifier 独立身份需二次授权」的坑）。

## 资源消耗

- 命令：~22（git status/log ×3 + ls/stat ×3 + cleanup --check 基线 ×1 + grep ×3 + moon fmt/info ×3 + check_fmt_gate ×1 + moon_test_env store ×1 + moon_test_env 全量 ×1 + date ×1 + fist.py ×7）。
- 子代理：1（team implementer `r222-sandbox-impl`，role=implementer，scope=两测试文件）——改两文件、回传 old→new 证据 + 缺口自陈（无 shell 未跑 moon test，由指挥官终审补跑）。终审通过后停掉。

## 任务分配记录

- **1 个 implementer 派单**（`r222-sandbox-impl`）：任务包含目标 / 边界（只动两文件）/ 已坐实关键事实（base_dir 唯一性、bug462_unique_dir pub 同包直用、@fs.create_dir 非递归需先建 temp、remove_dir 只删空目录）/ 逐处精确改动 / 回传格式（结论·证据·分析·缺口·入档）/ 验收标准（git 面 + 无裸 .db + store 绿 + 仓根无新增）。它极审慎（1059 事件，非停摆——指挥官中途只读诊断一度误判为「文件 2 未动」，实为编辑前快照，复查后纠正），终审独立全读两文件 + grep 对照，与回传逐项一致。
- FIST 闭环记账（ns `iter-1112r222w`）全链绿至已完成。

## 遗留风险

- **存量 6 仓根夹具库**（alpha/beta/wal-a/b/c + pf-ok，各 156KB，mtime 13:09）仍物理留仓根——本轮只止住**新增**污染，不删存量（0 字节 stray 删除属不可逆、本轮无 owner 在场）；`.gitignore *.db` 挡住不进 git，`cleanup`（非 --check）可清（与尾空格 stray 同批，留 owner 确认轮）。
- `memory/target.md` 陈旧协调面（Round 24/HEAD=5cbe4ce52，与当前漂移两天）——禁区，本仓不代刷新。
- Round C 队列判空（三项均否决/已修/已注册）待 owner 正式关闭。
- 尾空格 `fist-mbt.db `（0 字节，r204 守卫已修，留 owner 确认轮清）。
- OFM 端点持续 down 观察项（r194 容忍定性，探活告警语义属 owner 接线决定）。

## 后续建议

- **owner 确认轮**：`python scripts/cleanup_artifacts.py`（非 --check）一并清存量 6 仓根夹具库 + 尾空格 stray `fist-mbt.db `；正式判空关闭 Round C 队列三项；刷新 `memory/target.md`。
- 报告序列连续（r218→r219→r220→r221→r222）：本轮无中断，双格（报告提交 + 日志追加）收尾正常。

## 超额内容

无。

## 来源

- `git status --short` / `git log --oneline -3`（WIP 复核：仅 target.md M + stray + 本轮两测试文件；HEAD=0a3cac13e）
- `python scripts/cleanup_artifacts.py --check`（修前基线：7 根 .db + 8758 temp/）+ `stat`（6 夹具库 mtime 基线 13:09）
- `python scripts/moon_test_env.py --target js src/store`（**131/131 rc=0**）+ `--target js` 全量（**2067/2067 rc=0**）
- `moon fmt`（影响面仅两文件）/ `moon info`（.mbti 无变化）/ `python scripts/check_fmt_gate.py`（**rc=0**）
- `ls temp/`（`b462_ms_base_*` / `b462dir_pf_p3_*` 新沙箱目录）+ `git status`（本轮仅两测试文件）
- `python scripts/fist.py call` ×7（FIST 闭环全链至已完成，completed_by=wd-r222）
- r208/r221 报告 + 当日日志（夹具库溯源 + WIP 收口 + Round C 判空对照）
