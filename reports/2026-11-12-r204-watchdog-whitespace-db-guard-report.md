# 轮 204 唤醒巡检报告（stray-db 守卫缺口修复：stray_root_dbs 尾随空格 .db 漏判）

- **时间**：2026-11-12 00:31（本地）
- **轮次**：r204（ExploreWatchdog）
- **前序**：r203（316d4fcb8，reports/2026-11-11-r203-watchdog-wip-freeze-report.md）

## 并发 WIP 状态

| 项 | 读数 |
|---|---|
| mtime（承重 4 文件） | `mcpcf_embed_bug583_wbtest.mbt` 14:29 / `run_guards.py` 14:33 / `AGENTS.md` 14:34 / `memory/bugs.md` 14:35（均 Nov 11，本轮实测）|
| 冻结时长 | **~10.0h**（14:35 → 11-12 00:31，较 r203 的 ~9.0h 又 +1.0h）|
| diff 足迹（剔除本轮我的文件） | `git diff --shortstat -- ':!scripts/cleanup_artifacts.py'` = **15 文件 +281/−64**（与 r198–r203 逐字一致）|
| 本轮我的改动 | `scripts/cleanup_artifacts.py` = **1 文件 +57/−4**（守卫缺口修复，独立于 WIP）|
| 合流足迹 | `git diff --shortstat`（含我的文件）= 16 文件 +338/−68（= 281+57 / 64+4，无交叉）|
| 新提交 | r203（316d4fcb8）后零新提交；HEAD 仍 = r203 |
| WIP 定性（r198 已立） | **BUG-591 ⑤** + **BUG-588 OPEN→FIXED**（`bug583_04` 锁关闭）+ BUG-583 缺口钉假锁；方向对、量成型（维持 r193 已升级 owner 定性）|

**连续零变化**：r198–r204 **六连轮** WIP 承重 mtime 与 diff 足迹（剔除本轮文件后）逐字无变化 ⇒ WIP 死挂/放弃定性坐实，维持 r193 已升级 owner 的已知挂起，不重复上报。

**禁区遵守**：WIP 的 15 个文件本轮未 touch（只读 + `git status`/`git diff`/`stat` 观测，不跑 WIP 内部命令）；本轮只动 `scripts/cleanup_artifacts.py`（不在 WIP 名单内，无冲突）。

## Round C 队列

确认过期（r195–r203 已核实，不重复、不重推导）：BUG-527「摘 cc-link-flags」owner 否决（e0ef45c5e 回滚）/ BUG-530 已 FIXED（3699f012a）/ check_usage_tool_count 已注册（run_guards.py:175）。本轮未执行。

## 本轮实质：stray-db 守卫缺口修复（r197 未看的那层，非重复定性）

**r197/r203 已看见游离 `fist-mbt.db `（尾随空格、0 字节、mtime 11-11 14:37）**，定性「外部副产物、非代码缺陷、非账、不删」。本轮推进到它们没看的层——它为何能**同时**穿过 `git status` 面与 CI 干净度门无人拦截？

**根因（读码定位，非猜）**：两道防线都只认「以 `.db` 结尾」：
1. `cleanup_artifacts.py` 的 `stray_root_dbs` 用 `name.endswith((".db",".db-shm",".db-wal"))` ⇒ `fist-mbt.db `（末尾空格）判 **False**，漏判；
2. `.gitignore:15 *.db` 同理只匹配无空格变体 ⇒ 该文件不被忽略、进 `git status`。

叠加：`FIST_DB_PATH`/重定向带尾随空格落出的库名（0 字节 = shell 重定向签名，SQLite 真开会写 header）能同时穿两道门。且 `stray_root_dbs` 在 `--selftest` 里**零覆盖**（S0–S6 只打 underscore 脚本 + format_lines）⇒「一把尺没跑」的坏尺面。

**修复（`scripts/cleanup_artifacts.py`，+57/−4）**：
- 抽纯函数 `_db_name_is_stray(name) = name.strip().endswith(SUFFIXES)`，`stray_root_dbs` 改调它；`KEEP`/`KEEP_SIDECAR` 精确匹配**先行**，交付库 `fist-mbt.db`（无空格）本体不受影响，只有带空格变体才被归一判残留。
- `--selftest` 补三格（S0–S6 原格不动）：**R1**（变异对照）三个尾空格名必判 True、去 `strip()` 即红；**R1b**（反向，判例-29）普通 `alpha.db` 仍判残留、`notes.txt` 不误伤；**R2**（文件系统集成）交付库+sidecar 三个精确名必被 KEEP 挡住。
- **R1 为何是纯函数非盘上探针**（本轮关键判例）：Win32 非扩展长度 API **剥掉文件名末尾空格**（实测 `open("fist-mbt.db ")` 落盘 `fist-mbt.db`、落进 KEEP），盘上造不出尾空格探针 ⇒ 盘上锁本机假红/假绿。改打 `_db_name_is_stray` 本体（机制格==实现路径格），OS 无关、Linux CI 也成立。

**验证（实测）**：`--selftest` = **rc=0 PASS**（PASS 行点名 R1/R1b/R2）；变异复算：reverted（去 strip）对三个尾空格探针全判 False ⇒ R1 必红；`--check` 现把真树游离 `fist-mbt.db ` **点名进 DIRTY 根 .db 档**（修前漏判、会报 CLEAN）。

**0 字节杂文件本身未删**：删除不可逆 + 本轮无窗无用户确认 ⇒ 不删，留 WIP 收口 / owner 确认轮清（`cleanup`（非 --check）现能抓它）。

## 已探面汇总（避免重复）

| 轮 | 面 | 结果 |
|---|---|---|
| r197 | untracked / stray-DB | 1 项 0 字节异常（定性：不立账不删，**未看守卫层**）|
| r203 | WIP 冻结再测 + 无新面（勿空转） | 冻结 ~9.0h、+281/−64 五连轮零变化；stray-db 维持 r197 定性 |
| **r204** | **stray-db 守卫缺口（r197 没看的层）+ 修复** | **WIP 冻结 ~10.0h 六连轮零变化（剔除本轮文件后 +281/−64）；修 stray_root_dbs 尾空格漏判 + 补 R1/R1b/R2 自证；selftest rc=0；--check 现点名游离库** |

## FIST 闭环

ns `iter-1112`：publish（T0，附 BUG-411 两道门警告）→ acl_grant（lead can_write=true，granted_rows de7c02f251c9bf02 落库）→ claim（已领取）→ execute（执行中，deliverable 述修复）→ submit（待验收）→ verify（**已完成**，completed_by=lead）→ archive 首轮以 human_steward 判定被拒（该身份无 ns ACL）→ acl_grant（human_steward can_write=true，6527cca83946fae6 落库）→ archive（**已归档**）⇒ **全链绿，T0 收口**。

（本轮学到：`archive` 判定身份是 `human_steward`（非任务 assignee 的 lead），须**单独**给 human_steward 授 ns ACL——与 claim/execute 用 lead 是两道身份。记入 memory。）

## 结果摘要

- 并发 WIP 冻结 **~10.0h**，剔除本轮我的文件后 **15 文件 +281/−64 逐字无变化**（r198–r204 六连轮零变化）⇒ 死挂定性坐实，维持 owner 已知挂起，不重复上报。
- **新发现并修复守卫缺口**：`stray_root_dbs` 尾随空格 `.db` 漏判（`.gitignore *.db` 同漏）⇒ 0 字节杂库能同时穿过 git 状态面与 CI 干净度门。改为 `strip().endswith` 归一 + 抽纯函数，补 R1/R1b/R2 自证（含 Win32 剥尾空格的 OS 无关纯函数锁）。selftest rc=0，--check 现点名游离库。
- 游离 `fist-mbt.db `（0 字节）未删（不可逆 + 无窗无确认），留 WIP 收口 / owner 确认轮清。
- Round C 队列确认过期，未执行。

## 资源消耗

- 模型：qwen3.8-27b（本会话）；工具：git（status/diff-shortstat/log/stat）+ `python`（探针 2 支，均 temp/ 用完即清）+ `python scripts/fist.py`（FIST 网关 8 调用：publish + acl×2 + claim/execute/submit/verify/archive×2）。
- **未 spawn 子代理**：本轮实质是「读码定位守卫缺口 + 单文件 +57/−4 修复 + 自证」，属指挥官亲自面（金条四：终审 + 沉淀记忆 + 汇报）；单文件小改无独立可分配块，子代理读多写一文件收益为负。
- 跑过判据：`cleanup_artifacts.py --selftest`（PASS）+ `--check`（点名游离库）。未重跑 mcp_smoke / check_host_installable 等同源收敛面（承重面无变化，重跑无增量）。

## 任务分配记录

- 本轮无子代理派单（原因见「资源消耗」：单文件守卫修复属指挥官亲自面）。

## 遗留风险

- WIP 挂起 **~10.0h**（15 文件 +281/−64 成型未收口，六连轮零变化），等 owner A~D 裁决（不重复上报）。
- 游离 `fist-mbt.db `（尾随空格、0 字节）**仍未跟踪未忽略**：`cleanup --check` 现已能点名它（本轮修复），但**未删除**——WIP 收口 / owner 确认轮建议 `python scripts/cleanup_artifacts.py`（非 --check）一并清掉，防污染 `git status`。
- `.gitignore:15 *.db` 对尾空格变体仍不匹配（本轮只修 cleanup 守卫、未动 .gitignore——gitignore 无法优雅匹配「以 .db 结尾 + 可选尾空格」，靠 cleanup 守卫兜底更稳）；若游离库再现，`cleanup --check` 会红着提示。
- 本地领先远端 128+ commit（历史积压，推与否归 owner）。

## 后续建议

- 本轮把 r197「游离库不立账」推进成「**守卫缺口已修**」：cleanup 守卫现能拦尾空格 .db 变体，后续同类杂库不会静默穿门。
- WIP 六连轮零变化已把死挂定性坐实：建议 owner 直接评估收口那 281 行（r198 定性方向对、量成型）；收口时 `cleanup`（非 --check）可顺带清掉游离 `fist-mbt.db `。
- 无其它建议。

## 超额内容

无（守卫缺口修复即本轮针对 r197 遗留面的必要推进，非既有判据重跑）。

## 来源

- 本仓 `git status --short` / `git diff --shortstat`（含 `:!scripts/cleanup_artifacts.py` 剔除口径）/ `git log --oneline` / `stat` 实测（2026-11-12 00:31）。
- `scripts/cleanup_artifacts.py --selftest`（rc=0 PASS 含 R1/R1b/R2）+ `--check`（DIRTY 点名 `fist-mbt.db `）实测。
- Win32 剥尾空格探针实测（temp/_r1probe.py，用完即清）：`open("fist-mbt.db ")` 落盘 `fist-mbt.db`；`\\?\` 前缀才保留 `beta.db `。
- 变异对照复算（temp/_r1verify.py，用完即清）：reverted 逻辑对三个尾空格探针全判 False。
- `python scripts/fist.py call` 八次回执（T0/iter-1112 全链绿至已归档，completed_by=lead）。
- r203 报告（…/r203-watchdog-wip-freeze-report.md）、r197 stray-db 定性（…/r197-watchdog-stray-db-report.md）。
