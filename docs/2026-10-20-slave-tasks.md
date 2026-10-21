# FIST-Mbt 副机（Slave Agent）任务清单

> **主机** 2026-10-20 更新。副机认领时把 `[ ]` 改成 `[working]` 并 commit 认领。
> **每个任务** = 一个独立分支 = 一个独立 PR = 四态闭环。

---

## Slice 1 · CAF 写回（R43 读半已落地，写半空）

| # | 任务 | 分支名 | 状态 | 主机账本 bug_id | 参考 plan | 验收标准 |
|---|---|---|---|---|---|---|
| CAF-01 | `executor_run` 成功后 `caf_memory.push` 回写 + caf_dr_6 bad-JSON 降级锁 | `feature/caf-writeback-slice-b` | `[ ]` | 新 | `docs/2026-10-17-caf-writeback-task-package.md` Slice B | moon fmt/check/test 全绿；主机 MR 前 run_check |
| CAF-02 | `CafMemory::to_json` 补充原始 records 字段（R45 缺口） | `feature/caf-raw-records` | `[ ]` | 新 | `docs/2026-10-15-fist-mbt-caf-p2d-cold-start-design.md` L248 | 纯计算改动、零 IO；白盒锁 caf_rr_1 |

---

## Slice 2 · 守卫族（立项后写 scripts/check_*.py）

| # | 任务 | 分支名 | 状态 | 主机账本 bug_id | 参考 plan | 验收标准 |
|---|---|---|---|---|---|---|
| GUARD-01 | `check_model_auth_no_key`：config_json/HTML 输出禁止 api_key/token 值形状 | `guard/check-model-auth-no-key` | `[ ]` | 新 | `docs/improvement-plan-20261010.md` §6.2 | 覆盖 ci.yml / HTML / example / default-fist.mcp.json 全扫描面 |
| GUARD-02 | `check_host_installable`：deepseek-harness 宿主侧真能装 fist-mbt 插件 | `guard/check-host-installable` | `[ ]` | 新 | 同上 | 不新增 CI 时间（一次性 smoke） |
| GUARD-03 | `check_skill_inject`：plan/claim 传 inject 时 injected_assets 非空才算命中 | `guard/check-skill-inject` | `[ ]` | 新 | 同上 | 黑盒跑 fist-mbt MCP 自证 |

---

## Slice 3 · 多语言 SDK（cmd/ 下新增多语言 shim）

| # | 任务 | 分支名 | 状态 | 主机账本 bug_id | 参考 plan | 验收标准 |
|---|---|---|---|---|---|---|
| MULTI-01 | Python shim + 四态闭环 | `feature/multilang-sdk-python` | `[ ]` | 新 | `docs/2026-10-12-fist-mbt-multilang-sdk-plan.md` | `pip install -e .` → `fist list` 能调 MCP |
| MULTI-02 | Node.js shim + 四态闭环 | `feature/multilang-sdk-node` | `[ ]` | 新 | 同上 | `npm run dev` → `fist list` 能调 MCP |
| MULTI-03 | Go shim + 四态闭环 | `feature/multilang-sdk-go` | `[ ]` | 新 | 同上 | `go run .` → `fist list` 能调 MCP |

---

## Slice 4 · Web Dashboard（静态前端面板）

| # | 任务 | 分支名 | 状态 | 主机账本 bug_id | 参考 plan | 验收标准 |
|---|---|---|---|---|---|---|
| WEB-01 | 任务看板（board_ascii 可视化 + DAG 图） | `feature/web-dashboard-board` | `[ ]` | 新 | `docs/2026-10-12-fist-mbt-web-dashboard-plan.md` | 纯 HTML/JS 静态页；fetch MCP HTTP 端点 |
| WEB-02 | 状态流转 + 健康卡 + 脉冲三页 | `feature/web-dashboard-health` | `[ ]` | 新 | 同上 | 同上 |

---

## Slice 5 · Light Worktree Isolation（代码层 git worktree 隔离）

> **前置条件**：多租户数据隔离（store_open + FIST_DB_PATH + scratch=true）**已实现**，副机只做**代码隔离层**（git worktree + sparse cone + diff-scope CI 守卫）。

| # | 任务 | 分支名 | 状态 | 主机账本 bug_id | 参考 plan | 验收标准 |
|---|---|---|---|---|---|---|
| WT-01 | claimguard 挂 claim/publish 钩子（已有 src/claimguard/ 库） | `feature/claimguard-hook` | `[ ]` | 新 | `docs/plan-light-worktree-isolation.md` L33 + L208 | claim/publish 前走 may_proceed_full 预检 |
| WT-02 | `wt_create` / `wt_status` / `wt_destroy` 三工具（git worktree 生命周期） | `feature/wt-lifecycle-tools` | `[ ]` | 新 | 同上 L158-160 | 纯 git 命令封装 + src/server/wt_tools.mbt |
| WT-03 | sparse cone worktree 创建 + `light-wt` / `light-wt-teardown` shell 脚本 | `feature/wt-sparse-scripts` | `[ ]` | 新 | 同上 L147-149 | bash + pwsh 双轨可用 |
| WT-04 | e2e_assistant_xproc.py（两进程并发 claim 恰好一成一拒） | `feature/e2e-assistant-xproc` | `[ ]` | 新 | 同上 L135 | Python 脚本 + 自动化判据 |
| WT-05 | diff-scope 越界检测 + drift-check + merge-predict（CI 守卫） | `guard/check-diff-scope` | `[ ]` | 新 | 同上 L186-189 + L214 | scripts/check_diff_scope.py |
| WT-06 | lock_acquire 带 worktree_id + lock_status 视图补全 | `feature/lock-wt-bind` | `[ ]` | 新 | 同上 L170-173 + L212 | lock_acquire 新增 worktree_id 参数 |
| WT-07 | collector 定时回收 + 磁盘水位告警 + watchdog 接线 | `feature/wt-collector` | `[ ]` | 新 | 同上 L199-201 + L217 | 定时任务 + watchdog_tick 集成 |

---

## Slice 6 · Ship Plan Blackbox（安装/发布缺口）

| # | 任务 | 分支名 | 状态 | 主机账本 bug_id | 参考 plan | 验收标准 |
|---|---|---|---|---|---|---|
| SHIP-01 | GitCode Releases API 端点探测 + 接入 | `ci/gitcode-releases-api` | `[ ]` | 新 | `docs/SHIP-PLAN-BLACKBOX-v2.md` G3 | gitcode_queue_status 拉通 |
| SHIP-02 | CI release.yml 加 GitCode upload step | `ci/gitcode-release-upload` | `[ ]` | 新 | 同上 G7 | 每次 tag 自动发 GitCode |
| SHIP-03 | install.ps1 加 Node.js 自检 + winget install 提示 | `fix/install-node-check` | `[ ]` | 新 | 同上 L238 | 无 Node 时提示 winget OpenJS.NodeJS.LTS |

**已作废项**：SHIP-PLAN G4（后台 hidden shim）—— 与 stdio 协议冲突，主机判定作废，**不要做**。

---

## Slice 7 · Polish Plan（打磨冲刺）

| # | 任务 | 分支名 | 状态 | 主机账本 bug_id | 参考 plan | 验收标准 |
|---|---|---|---|---|---|---|
| POLISH-01 | README 顶部 3 行内落死一句话卖点 | `docs/polish-readme-slogan` | `[ ]` | 新 | `docs/polish-plan.md` A | README 前 20 行可见 |
| POLISH-02 | docs/selfdrive-walkthrough.md 真实运行 trace | `docs/selfdrive-walkthrough` | `[ ]` | 新 | 同上 B | 从主机跑完的 trace 复制（副机无 FIST-Mbt MCP server 活库） |
| POLISH-03 | CI native job 去掉 continue-on-error（BUG-133 闭环） | `fix/native-ci-green` | `[ ]` | BUG-133 | 同上 C | 干净树 `moon test --target native -j 1` 全绿 |
| POLISH-04 | 环境要求（Node≥24 / moon ≥0.1.20261016）移到 README 最显眼处 | `docs/readme-env-bold` | `[ ]` | 新 | 同上 D | README "环境要求"节加 ⚠️ + 版本号 |
| POLISH-05 | docs/known-boundaries.md 主动自曝 node:sqlite 实验警告 + native 配置复杂度 | `docs/known-boundaries` | `[ ]` | 新 | 同上 E | 新文件 30-50 行 |
| POLISH-06 | **拳头 Logo** + assets/ + gen_plugins 加 assets 拷贝步骤 | `feature/fist-logo-assets` | `[ ]` | 新 | `docs/improvement-plan-20261010.md` §2.2 | assets/fist-logo.svg 存在 + plugins/*/assets/ 拷贝 |

---

## Slice 8 · 其他

| # | 任务 | 分支名 | 状态 | 主机账本 bug_id | 参考 plan | 验收标准 |
|---|---|---|---|---|---|---|
| MISC-01 | **多租户命名空间 skill 文档**（`docs/multi-tenant-mode-skill.md` 已存在但内容薄） | `docs/multi-tenant-skill-enhance` | `[ ]` | 新 | AGENTS.md §多租户命名空间 | 补齐：scratch=true / data_dir 相对 cwd / store_open/store_list/store_close 三工具用法 |
| MISC-02 | **plan-light-worktree claimguard 已落地但未接**（src/claimguard/ 已存在 5 个 .mbt） | `feature/claimguard-hook` | 同 WT-01 | 新 | docs/plan-light-worktree-isolation.md L33 | claim/publish 走 may_proceed_full |

---

## 主机不做、副机也不做（已判定作废/不推荐）

| # | 作废项 | 原因 |
|---|---|---|
| ❌1 | SHIP-PLAN G4（后台 hidden shim） | 与 stdio 协议冲突，plan 自身建议作废 |
| ❌2 | Star 门服务端网关（强门禁） | 需 FIST-Mbt 自备服务器，超出本仓范围 |
| ❌3 | 多账号平台托管 | 涉及厂商条款边界 + 合规审查，必须用户拍板 |
| ❌4 | 远程 agent 自动 selfdrive_publish_next 推进 PR | 主机 MR 前要做一次性收口，自动推进会把并发 WIP 带进来 |
| ❌5 | 任何涉及并发 agent 当前 WIP 文件的改动 | 副机从 HEAD cd6a363 起分支，并发 WIP（195 行 M）在副机不可见 |

---

## 主机 MR 前统一收口（主机自己做，副机等）

1. 所有副机 PR 合入后，主机跑一次完整 `gen_plugins.py` → `check_plugin_sync.py` 逐字节 diff PASS
2. 主机跑一次完整 `check_doc_surface.py`（J6/J7 文档同步）
3. 主机跑一次完整 `check_test_sync.py`（cl6 文档计数）
4. 主机跑一次 CI 全量（43 项守卫族绿面）
5. 主机 commit `merge: slave PRs (CAF writeback + multilang-sdk + light-worktree)`

---

## 更新日志

- **2026-10-20** 主机创建。覆盖 improvement-plan-20261010.md / polish-plan.md / SHIP-PLAN-BLACKBOX-v2.md / plan-light-worktree-isolation.md / multi-agent-lock-v3.md / caf-p2c-wiring.md / caf-acceptance-status.md / caf-writeback-task-package.md / 多语言 SDK plan / Web Dashboard plan / OCR local integration plan / router-enhancement-plan / router-caf-learning-plan。
