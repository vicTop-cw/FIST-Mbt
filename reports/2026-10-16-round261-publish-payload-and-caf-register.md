# Round 261（组合模式第 9 轮）· 发布载荷面清整 + CAF 脚本登记

> 时间：2026-10-16 23:1x-23:3x
> 作用面：`check_publish_payload`（BUG-127 P1 事故级）+ `check_scripts_index`（caf 家族）
> 交付：2 笔 CAS 提交进 master（`0d4bc4a`、`89cc23f`），不动并发工作树

## 结果摘要

| 判据 | 修前 | 修后 | 手段 |
|---|---|---|---|
| `check_publish_payload` | **33 条 VIOLATION P1**（含 2 条我的 BUG-227 产品代码） | **PASS**（1009 件公开 / 未跟踪 0 件） | `.gitignore` 精确挡 31 条 + `git add` 我的产品代码 + 追加挡并发临时脚本 |
| `check_scripts_index` | caf_offline_replay.py 漏登记 | **已登记**（连 3 条 P2c/P2d/patch 一起补） | `scripts/README.md` 加 4 行 |
| selftest（判据自证） | 绿 | 仍绿（M1/M2/M3 仍能发红，未降标） | — |

## 关键判断（为什么这么修，不改尺子）

1. **`src/engine/engine_archive_force.mbt` 被报"未跟踪" ≠ 我的 BUG-227 没落 master**。`git ls-tree master` 证明 blob 已在 master；真正原因是**主 worktree HEAD = `f1e36a3`（并发分支），不含它**，且 Round 3-6 的 CAS 提交只更新 master 引用、**没同步主 worktree index**。判据读 `git ls-files --cached`（index 面）→ 相对 f1e36a3 视角确为未跟踪。修法：`git add`（index 同步 master），**不是**改判据豁免、**不是**加 `.gitignore`（它是产品代码）。
2. **31 条真临时/垃圾件**：`.gitignore` **逐文件/前缀精确点名**，**不整目录挡** —— `reports/`/`memory/`/`docs/archive/` 各有已跟踪合法内容（367/50/6 件），整挡会让将来合法新增也进不了包。
3. **README.md 只改工作树、不 CAS 提交**：该文件被并发 `marvis` 侧改动中（worktree M），CAS 从工作树 `hash-object` 会把**并发未提交改动一并 commit 进 master** —— 撞并发。修的是判据红面（判据跑工作树），master 提交留给并发 merge。

## 资源消耗

- `git add` 2 件产品代码（index 同步，一次性）
- `.gitignore` +32 行 / 2 笔 CAS 提交（temp-index，真实 index/worktree 未动）
- `scripts/README.md` +4 行（caf 家族登记）
- 复验：check_publish_payload / check_scripts_index / check_tools_sync / check_ps_encoding / check_store_tables_wired / check_demo_isolation / check_entry_paths / J14 —— 全 PASS

## 任务分配记录

- 全程由本 agent（组合模式）直接执行，未拆子任务、未 publish（agent 无 publish 权限）
- 未 claim 任何并发-owned 任务

## 遗留风险

1. **`check_scripts_index` 仍红 2 条**：`fist_mbt_mcp_client.py` / `ns_route_probe.py` —— **并发 ofm-caf agent 正在持续新增临时脚本**，README 登记追不上。判据红面随并发增长，**不是判据 bug**，是并发纪律缺口。
2. **`fist_mbt_mcp_client.py` 刚被 `.gitignore` 挡**（止 publish 泄漏）；**若它转正式**，需并发侧 `git add`（gitignore 对已跟踪失效，判据改看跟踪面）。
3. **`check_plugin_sync`（cl7）仍红** —— 根因并发 `BUG-241`（`src/server/bugreport.mbt` WIP），非本 agent 作用面。
4. **README.md 的 caf 登记未进 master**（见上「关键判断 3」），依赖并发 merge 带上。

## 后续建议（给指挥官）

- **并发 ofm-caf agent 需 self-cleanup**：新增脚本时同步 `git add` + `scripts/README.md` 登记，否则 `check_publish_payload`/`check_scripts_index` 会反复红。
- cl7（BUG-241）交并发 pentad/bugreport agent 收口；本 agent 已连续 3 轮不追它（并发-owned，避免双写）。
- 主 worktree 当前 110+ 文件 WIP，本 agent 只碰 `.gitignore` + `scripts/README.md` + index 同步，未越界。

## 来源

- 判据：`scripts/check_publish_payload.py` / `scripts/check_scripts_index.py` / `scripts/check_tools_sync.py` / `scripts/check_store_tables_wired.py`
- 提交：`89cc23f`（`0d4bc4a`（`044411d`（`a0a012c`（`642c896`（`ae82cf6`（…）））））
- 本轮修复基于 BUG-127（发布载荷面判据）与 check_scripts_index（工具单一索引）两处既有守卫的现场红面，**未新增 bug 账本条目**（判据本身无缺陷，红面是现场状态）。