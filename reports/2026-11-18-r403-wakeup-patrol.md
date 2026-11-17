# 轮 403 唤醒巡检报告（FIST-Mbt-ExploreWatchdog）

> 日期 2026-11-18（本地 03:06 / UTC 2026-11-17T19:06）｜ 轮次 r403（HEAD `d0579e0a4`，r402 之后无新提交）｜ agent wd-r403 ｜ ns watchdog

## 一、唤醒状态

- **WIP 收口核查**：`git status --short` = 6M + 1 untracked，与 r393~r402 一致（iter-r192 车道在途：`dist/fist-mbt.js` M、`memory/bugs.md`、`memory/target.md`、`scripts/README.md`、`scripts/check_plan_landing.py`、`templates/pipeline_mode_loop.md` 均 unstaged；untracked `reports/2026-11-17-iter-r192-report.md`；暂存面为空）⇒ iter-r192 车道仍未收口，**禁区零碰**（零改零提交，`git restore`/`git add` 他方文件一概未动）。
- **Round C 队列维持 r385/r400/r401/r402 实证移交态**：BUG-527 治本已被 2026-11-02 追记3 A/B 裁决否决（摘库包 `cc-link-flags` 反断 CI native，现行态 18 份 moon.pkg 全保留为正确态，**严禁重跑**）/ BUG-530 已 FIXED（`3699f012a`，HEAD 版 bugs.md:14772 `[medium] FIXED`）/ `check_usage_tool_count` 已注册（run_guards.py:175 `case("check_usage_tool_count.py")`）⇒ **既定目标为空**，不派单，走巡检分支（标准动作 3）。
- **check_tool_coverage（BUG-636 同族临时项）明确延后**：修它需动冻结的 `memory/bugs.md`（现 WIP +vq 外来账待 owner 裁决），越界 ⇒ 本轮不修，维持延后（规格见 `reports/2026-11-15-r315-wakeup-patrol.md`）。注：账本内 `BUG-636` 实为 vq 项目 MinGW 入口 bug（已 FIXED），与本仓 check_tool_coverage 盲区同号不同事。

## 二、换面巡检：`check_release_asset_names`（发布资产名三处同源判据）

选择依据：本判据上次单巡为 **r389（14 轮前）**，近 6 轮（r397 sql_bind / r398 battery_count / r399 host_installable / r400 mbti_sync / r401 precedents_doc / r402 two_faces）未触及。发布安全网是本仓最高价值守卫族之一（BUG-103/105/107/109/111/112/113/114/116/120/125 一族，R1–R16），且其输入面（moon.mod / install_onecmd.ps1 / install.sh / README / release.yml）本轮零 WIP 触碰，14 轮窗口的回面复核是一次干净的「分发面同源」确认，不属重复空转。

| 项 | 结果 |
|---|---|
| `--selftest` | **rc=0**（干净不误红 + 变异必红；清单从已执行格子反解：R1×2 / R2 / R3×2 / R4 / R5×2 / R6×3 / R7×3 / R8×3 / R9×6 / R10×2 / R11×5 / R12×2 / R13×2 / R14×5 / R15×5 / R16×7；全合成入参不读真仓） |
| 实跑 | **rc=0 PASS 分发面同源**（判据范围从正文反解 R1–R16）：资产名三处一致（安装器 ↔ 发布作业 ↔ moon.mod）+ 版本真源 moon.mod + 空值即失败 + 命令名两类 shell 都可见（Windows `.cmd` + 无扩展名 `#!/bin/sh` shim）+ 200/HTML/魔数 `PK` 检查 + 安装自检不假绿（✅ 挂 `if ($jsVer)`）+ 发布作业不顶掉分发（needs 含 meta 不含 native + native `continue-on-error`）+ 工具链 bootstrap 与 CI 同源（moon 进 `GITHUB_PATH` + `install/unix.sh`）+ 文档线 BOM 安全（`TrimStart([char]0xFEFF)`）+ 源码版本常量与 moon.mod 同源 + windows 臂安装形状与 ci.yml 同源 + 发布后资产逐名比对步在位（BUG-513 出路③） |

**结论：分发面 16 个判据维度全对齐，零漂移。**（本判据判「发布装出来的东西名/版本/形状是否与 moon.mod、CI、安装器三处一致」，PASS = 公网 `irm|iex` 与离线安装线指向同一份正确资产。）

## 三、零漂移常设面

| 判据 | 结果 |
|---|---|
| `check_tools_sync` | rc=0（server.mbt 注册 183；AGENTS/README/deliverable/scoring_rubric 对齐；R3b/R7 扫现状面 169 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183 与实测对表） |
| `check_instruction_budget` | rc=0（AGENTS.md = 50440 字节 / 预算 65536，实际注入上限 50440，全部章节可见） |
| `patch_esm_main` | rc=0（10 bundle 全 up to date / total patched 0 / 10，FIST 闭环前先行探针防 MemoryError） |

## 四、立账与禁区

- **无新发现（类型）、无新立账**（换面 + 常设面全绿零漂移）。
- **禁区零碰**：6M + 1 untracked 他方 WIP（iter-r192 车道）零改零提交；`dist/fist-mbt.js` 巡检中止轮遗留不代收，留 owner/专门轮。

## 五、FIST 闭环

T0r159 六步全链 **rc=0**（wd-r403 / ns watchdog / `temp/fist_r403_chain.sh` 稳健 TID 提取后台串跑，job bg-1；patch_esm_main 探针先行 10 bundle up to date / 0 patched 防 MemoryError）。verify 回执：status=已完成、completed_by=wd-r403、assignee=wd-r403、deliverable=本报告、namespace=watchdog、created_at=2026-11-17T19:05:48Z / updated_at=2026-11-17T19:06:04Z。

## 六、遗留风险与后续建议

1. 无新增。Round C 队列空 → 需 owner 设下一迭代目标（与 r385/r400/r401/r402 移交态一致，持续挂起）。
2. check_tool_coverage 盲区（`_tool_registry` 真源未接线的第 6 消费者，漏扫 18 工具中 7 个零 A 面覆盖）维持延后——待 `memory/bugs.md` 解冻（当前 WIP vq 外来账待 owner 裁决）后按巡检口径认领，规格见 `reports/2026-11-15-r315-wakeup-patrol.md`。
3. iter-r192 车道（dist 重构 + bugs.md 外来账等）在途 40+ 轮未收口，其 scoped 提交收口前本树维持「巡检分支」节奏；target.md 陈旧行问题 r394 已交接（需 owner 授权 `git restore`），维持不代改。

*（内容由AI生成，仅供参考）*
