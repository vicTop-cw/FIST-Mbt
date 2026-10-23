# 汇报：推送守卫可持续化 + 当前面路径硬编码清零（回收 PR#17 被吞面）

- 日期：2026-10-24
- 分支：`slave/fix-push-guard-sustainability-r1`（基线 `fcd210b8` = gitcode/main）
- 设计：`docs/design-push-guard-sustainability.md`
- FIST：ns `self-iterate-r1` T0 · 账本：BUG-389(2) 承接（dc_3 红指路并行单 `feat/fix-desc-clip-utf8`，不占号）

## 结果摘要

1. **pre-push 拦截收进跟踪面**：新增 `.githooks/pre-push`（壳只 `exec check_direct_push.py`，
   无 python 即拒、不静默 fail-open）；`install_git_hooks.REQUIRED` 加 `pre-push` ⇒ **安装器即真源**，
   换机/清理不再退化成 fail-open。判定本体 `check_direct_push.py` 抽出纯函数 `decide()` + `--selftest` 语义矩阵。
2. **新尺 `check_push_guard.py`（缺口③）**：H0 安装器 REQUIRED / H1-H3 钩子+脑在跟踪面且壳引用脑 +
   stdin 未掐 / S1 真起子进程喂 5 格 stdin 语义矩阵 / E1 本机安装态**只报不判**（CI 干净 clone 恒 WARN，
   拦的是「跟踪面本身坏了」）。`--selftest` 六格含两格变异台（语义改松→S1a 红、误伤→S1b/c 红）。
3. **回收 PR#17 被合并吞掉的硬编码清零面**：AGENTS/SOP/6 份 docs/插件真源（四宿主重投影）/
   `scripts/{fist_mbt_mcp_client,_run_check_t0r21,tmp_merge_batch,gen_plugins,scoring_rubric,e2e_reserve_xproc}`/
   `src/server` 6 文件的机器身份路径清零。开发层 `.dsh/.../cordis.patch.yml` 脱跟踪 + 模板化
   （`{{FIST_MBT_LAUNCHER}}`/`{{FIST_MBT_ROOT}}`，形状对齐社区层 `packaging/dsh/launch-mcp.mjs`）。
4. **修 `check_hardcoded_paths.py` 自命中**：文档去字面量 + fixture 运行时拼接（尺写进自己被检面即自锁扫红）。
5. **三面登记对齐**：README 补 16 条缺登记（PR#17 被吞的 render/hardcoded + 我的新尺 + 既有 11 条），
   `run_guards` 点名 `check_direct_push --selftest`（禁裸跑格，防挂 stdin 空转）+ `check_push_guard` 两格 +
   `run_light_wt --selftest`（补 G1 缺面→**缺执行面 0**），BATTERY-REGISTRATION 同批改数（105/47/66/0/74/27/6），
   ci.yml 接 3 格（position-why 锚点在步骤块内，棘轮未升）。

## 资源消耗
- 模型：DSH 会话内同机；工具 moon 0.1.20261016 / Node v25.2.1（经 moon_test_env 剔 node.cmd 垫片）/ Python 3.13 / gh 凭据走 api.github.com（github:443 本机不可达）。
- 工时：单轮多步；主要耗时在全量测试（~2min×3，含一次覆盖回退返工）与恢复被吞面。

## 任务分配记录
- FIST 任务：ns `self-iterate-r1` publish→claim→execute→submit（verify 留人类终审）。
- 子代理：无（多文件判据对齐需逐格核对，拆分反增合并风险）。

## 遗留风险
1. **覆盖回退返工（本轮已修）**：初版误用 branch 的 `write_gate_wbtest.mbt`（155 行）覆盖了 main 的
   235 行版，丢了 `ns_write_gate`/`legacy_store_exists` 12 处测试 → 全量 1427/1422。改回 base 版为底、
   仅中性化字面量后恢复 384/384。**教训**：跨基线恢复文件必须以「当前 main 版」为底，不能拿旧 PR 版。
2. **dc_3 基线预存红（已指路并行修复单，本 PR 不修不占号）**：`src/core` desc_clip 的 UTF-8 字节边界回退在本机
   String 码点语义下失效。pristine 基线 `fcd210b8` 同红取证（`git worktree add --detach`）。
   曾以 BUG-390 入账，后查合并线 gitcode/main 已存在同号（store 干净树条目）且并行单
   `feat/fix-desc-clip-utf8`（0b94ac1ce8，账本 393/394/395）已在修——**撤条**：合过去会炸门④（抬头唯一），
   修复单也落定则成"账本说没修、任务库说修完了"的矛盾。判据面留给 desc_clip 修复单：
   `python scripts/moon_test_env.py --target js src/core`（本机 18 跑 1 红 / 修后 18/18）。
3. **本机 moon fmt 世代会重排全仓 .mbt（BUG-388 家族）**：已用 `revert_and_neutralize.py` 回滚 fmt churn，
   只保留 6 个 src 目标文件的中性化改动；fmt 权威面以 CI（Linux nightly）为准。
4. `doc_dup`（38 重名/232 冗余块）/`slave_task_list`（19 失配）/`unit_number` 是基线预存红，另开车道，
   本 PR 登记面均为唯一新名（dup 计数 38→38 未增），不混入避免成合并撞车磁石。

## 后续建议
1. 合入后本机跑 `python scripts/render_dsh_patch.py`（DSH 重连即用新安装面）。
2. 下一单：dc_3 修复（desc_clip 走字节 API）或确认 CI nightly 是否仍字节语义（若是则本条 FALSE_POSITIVE）。
3. doc_dup 存量清整单（232 冗余块机械去重）。

## 超额内容
- 回收了 PR#17 被合并通道吃掉的 16 条 README 登记 + 3 格 CI + 电池格（不止 BUG-389(2) 本身）。
- `run_light_wt --selftest` 21 格验明纯逻辑可进电池，顺带解掉 G1 缺面红。

## 来源
- BUG-389(2) 账本（memory/bugs.md，本机 pre-push traceback 实测）；
- `packaging/dsh/launch-mcp.mjs`（b5c8a366 社区层，2026-10-23 读）；
- 本仓口径：docs/2026-10-20-slave-dev-playbook.md、run_guards G1/check_merge_loss 三面契约。
