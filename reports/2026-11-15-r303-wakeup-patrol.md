# 轮 303 唤醒巡检报告（ExploreWatchdog）

- 时间：2026-11-15
- 触发：Windows 计划任务 FIST-Mbt-ExploreWatchdog 例行 30 分钟唤醒
- 角色：fist-commander 非阻塞巡检（指挥官不代行 owner 裁决与清理）

## 1. WIP 收口核对

四件套逐字冻结 **第 20 轮**（r284 起连续）：

| 文件 | mtime | 状态 |
|---|---|---|
| docs/improvement-plan-20261010.md | 2026-11-14 10:55:34 | M |
| memory/bugs.md | 2026-11-14 10:47:48 | M（+200 行） |
| memory/target.md | 2026-11-10 10:34:16 | M |
| scripts/check_mcpcf_db_isolation.py | 2026-11-14 11:11:49 | ??（23423 B） |

- `git diff --stat` 逐字同 r284~r302：3 文件 208+/2-，相对 r302 零新增量。
- mtimes 全早于 r284 提交时刻（15:19:37）⇒ 冻结判定维持。
- r287 提请的 owner 弃置裁决维持挂起（指挥官不代行清理，不可逆操作先出方案）。

## 2. Round C 队列

维持过期不执行（既定记忆，勿重推导）：
- BUG-527 摘 cc-link-flags：owner 否决（CI A/B 实证有害，d43a06a28→8a669992d 回滚）；
- BUG-530：已 FIXED（3699f012a）；
- check_usage_tool_count：已注册（scripts/run_guards.py:175）。

## 3. 换面巡检：check_release_asset_names（分发面同源守卫 · BUG-103~125/513 族）

选面理由：r299~r302 连续四轮列「未轮过面」，本轮首跑；
判据覆盖 16 面 R1~R16（资产名三处同源 / 版本真源 moon.mod / 空值即失败 /
命令名两类 shell 都可见 / 200-HTML-魔数检查 / 安装自检不假绿 / 发布作业不顶掉分发 /
工具链 bootstrap 与 CI 同源 / 文档线 BOM 安全 / 源码版本常量与 moon.mod 同源 /
windows 臂安装形状与 ci.yml 同源 / 发布后资产逐名比对步在位等），
全部静态扫描，完全避开 WIP 四件套，读数干净。

- `--selftest`：rc=0，`SELFTEST OK`，清单从已执行格子反解：
  R1×2 / R2 / R3×2 / R4 / R5×2 / R6×3 / R7×3 / R8×3 / R9×6 / R10×2 / R11×5 / R12×2 / R13×2 / R14×5 / R15×5 / R16×7。
- 实测：rc=0。`PASS 分发面同源（判据范围从正文反解：R1/R2/R3/R4/R5/R6/R7/R8/R9/R10/R11/R12/R13/R14/R15/R16）`。

无新发现、无新立账。

## 4. 零漂移例行复跑

| 尺 | 读数 | rc |
|---|---|---|
| check_tools_sync | 183 工具（R8 分组 19 组 ΣN=183 对表） | 0 |
| check_instruction_budget | 50440/65536 字节 | 0 |

（两者每轮独立复跑，防漂移雷。）

## 5. FIST 闭环

六步串跑后台收口（node 冷启动 ~2min/发，前台 60s 上限不可行），call 落盘 `temp/fist_r303_out/`：

1. publish（ns watchdog）→ task_id T0r59，claim_ready=true，writable_agents 57→58
2. agent_acl_grant（wd-r303，can_write）→ 已落库（granted_rows 1 行）
3. claim（assignee=wd-r303）→ status=已领取
4. execute（agent=wd-r303，deliverable=本报告）→ status=执行中
5. submit（agent=wd-r303）→ status=待验收
6. verify（verifier=wd-r303）→ status=已完成，completed_by=wd-r303

六步全链 rc=0 一发收口。

## 6. 遗留风险 / 后续建议

- WIP 四件套冻结已 20 轮（跨 11-14→11-15 两天），owner 弃置裁决仍是唯一解法；指挥官维持挂起、不代行清理。
- r302 新发现（AGENTS.md:360 spawn 计数 29→36 滞后）仍待 owner 裁决：方案 A（手工改数）/ 方案 B（check_doc_surface 扩面对表）二选一；裁决前该数字留在散文面无人认领（守卫全绿，不影响 CI）。
- 换面巡检队列消耗进度：r284~r303 已轮 16 面，未轮过面（check_model_auth_no_key /
  check_template_ctrl / check_pkg_imports 真跑面等）仍有余量，后续轮次继续轮换。

## 7. 来源

- git status / git log / `git diff --stat` / `ls -la`（冻结判定）
- `python scripts/check_release_asset_names.py --selftest` / 真跑（r299~r302 列未轮过面，本轮首跑）
- `python scripts/check_tools_sync.py` / `python scripts/check_instruction_budget.py`（独立复跑）
- `temp/fist_r303_out/1~6_*.txt`（六步回执原件）
