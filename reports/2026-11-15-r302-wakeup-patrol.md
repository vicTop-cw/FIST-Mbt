# 轮 302 唤醒巡检报告（ExploreWatchdog）

- 时间：2026-11-15
- 触发：Windows 计划任务 FIST-Mbt-ExploreWatchdog 例行 30 分钟唤醒
- 角色：fist-commander 非阻塞巡检（指挥官不代行 owner 裁决与清理）

## 1. WIP 收口核对

四件套逐字冻结 **第 19 轮**（r284 起连续）：

| 文件 | mtime | 状态 |
|---|---|---|
| docs/improvement-plan-20261010.md | 2026-11-14 10:55 | M |
| memory/bugs.md | 2026-11-14 10:47 | M（+200 行） |
| memory/target.md | 2026-11-10 10:34 | M |
| scripts/check_mcpcf_db_isolation.py | 2026-11-14 11:11 | ??（23423 B） |

- `git diff --stat` 逐字同 r284~r301：3 文件 208+/2-，相对 r301 零新增量。
- mtimes 全早于 r284 提交时刻（15:19:37）⇒ 冻结判定维持。
- r287 提请的 owner 弃置裁决维持挂起（指挥官不代行清理，不可逆操作先出方案）。

## 2. Round C 队列

维持过期不执行（既定记忆，勿重推导）：
- BUG-527 摘 cc-link-flags：owner 否决（CI A/B 实证有害，d43a06a28→8a669992d 回滚）；
- BUG-530：已 FIXED（3699f012a）；
- check_usage_tool_count：已注册（scripts/run_guards.py:175）。

## 3. 换面巡检：check_demo_isolation（spawn 隔离守卫 · BUG-122/124）

选面理由：近 25 轮（r277~r301）未轮过；守卫族（AGENTS.md:360 点名）成员；
判据为纯静态文本扫描（`Popen` 起 `serve` 的脚本必须把 `FIST_DB_PATH` 交给子进程），
扫描面为 spawn 脚本本身，完全避开 WIP 四件套，读数干净。

- `--selftest`：rc=0，6/6 格（G1 干净不误红 / M1 摘掉一个真 spawn 脚本的改道针必红 /
  M1b 只加一行注释不许误红 / M2 把豁免扩到不 spawn 的文件必红 / M3 空扫描必自拒 /
  M3b 入口级空扫描自拒）；自检自述「spawn 面 36 个脚本，显式子句 2 项 / 豁免 1 项」。
- 实测：rc=0。`PASS spawn 面隔离一致：36 个脚本 spawn serve 时都把 FIST_DB_PATH 交给了子进程
  （显式子句 2 项 + 豁免 1 项锚点均成立）`。

**新发现（立账受阻，待 owner 裁决）——AGENTS.md 散文计数滞后（BUG-514「自述滞后于现状」同族）：**

- AGENTS.md:360（守卫族段）check_demo_isolation 描述写死
  「现状面 **29** 个 spawn 脚本全合规 = **27** 个带默认改道针 + 2 个显式子句，另有 1 项豁免且锚点成立」；
- 本轮实测扫描面 **36**（= 33 带默认改道针 + 2 显式子句 + 1 豁免锚点成立），数字面漂移 +7；
- 该散文计数**不在任何守卫面**（scripts/ 全目录对该数字零命中，check_demo_isolation 本体
  只判 spawn 语义不判文档计数）⇒ 无人认领，与 BUG-514（mcp_tool_tour 抄来的「12 支」在格子
  变 14 时没人知道）同失效形态；
- 讽刺点：同段 AGENTS.md 明文「数目不在此自述——写死一个数就是下一颗漂移雷」，
  这条禁令指守卫族总数，spawn 脚本数却以具体数字形式留在描述里，正是本仓预警的雷形；
- **落账受阻**：memory/bugs.md 正被 WIP 占用（M，+200 行）⇒ 指挥官不代行落账（禁区纪律），
  发现完整记入本报告，待 owner 裁决后补入账本。

**两方案（供 owner 选）：**
- 方案 A（缓解）：手工把 AGENTS.md:360 的「29 = 27+2」改为现读「36 = 33+2」——一次修好，
  下次 spawn 脚本再增减又漂（不推荐为长期手段）；
- 方案 B（治本）：check_doc_surface 扩面——解析 AGENTS.md 该段散文计数，与
  check_demo_isolation 实测扫描面对表（J10/J14 同族「自述==实现」），数字一变当场红。

## 4. 零漂移例行复跑

| 尺 | 读数 | rc |
|---|---|---|
| check_tools_sync | 183 工具（R8 分组 19 组 ΣN=183 对表） | 0 |
| check_instruction_budget | 50440/65536 字节 | 0 |

（两者每轮独立复跑，防漂移雷。）

## 5. FIST 闭环

六步串跑后台收口（node 冷启动 ~2min/发，前台 60s 上限不可行），call 落盘 `temp/fist_r302_out/`：

1. publish（ns watchdog）→ task_id T0r58，claim_ready=true，writable_agents 56→57
2. agent_acl_grant（wd-r302，can_write）→ 已落库
3. claim（assignee=wd-r302）→ status=已领取
4. execute（agent=wd-r302，deliverable=本报告）→ status=执行中
5. submit（agent=wd-r302）→ status=待验收
6. verify（verifier=wd-r302）→ status=已完成，completed_by=wd-r302

六步全链 rc=0 一发收口。

## 6. 遗留风险 / 后续建议

- WIP 四件套冻结已 19 轮（跨 11-14→11-15 两天），owner 弃置裁决仍是唯一解法；指挥官维持挂起、不代行清理。
- 新发现（§3）待 owner 裁决：AGENTS.md:360 spawn 计数 29→36 滞后，方案 A/B 二选一；
  裁决前该数字留在散文面无人认领（守卫全绿，不影响 CI）。
- 换面巡检队列消耗进度：r284~r302 已轮 15 面，未轮过面（check_release_asset_names /
  check_model_auth_no_key / check_template_ctrl / check_pkg_imports 真跑面等）仍有余量，后续轮次继续轮换。

## 7. 来源

- git status / git log（会话起始快照 + 本轮复跑）
- `git diff --stat` + `ls -la`（冻结判定）
- `python scripts/check_demo_isolation.py --selftest` / 真跑（近 25 轮未轮过，本轮首跑）
- `grep '29 个 spawn' scripts/ AGENTS.md docs/`（新发现数字面归属核验）
- `python scripts/check_tools_sync.py` / `python scripts/check_instruction_budget.py`（独立复跑）
- `temp/fist_r302_out/1~6_*.txt`（六步回执原件）
