# 获奖提升 · R15 汇报：项目整洁——生成物清理策略（cleanup_artifacts）

> 日期：2026-09-25｜目标 pillar：项目整洁干净《临时脚本任务完清理策略增强、代码生成物清理、工具类辅助代码统一管理》
> 方式：fist-mbt 自驱式获奖概率提升链路；本轮不新增 MCP 工具（工具数保持 77），聚焦"仓库整洁/任意机器可复现"硬指标。

## 结果摘要
- **审计出真实整洁缺口**：仓库根堆了 **45+ 个被 gitignore 的 `.db` 生成物**（`watchdog_*.db`、`wal-*.db`、`smoke_e2e_*.db`、`decompose_persist.db`、`alpha/beta/gamma/pentad.db` 等，由测试 + 自驱脚本每次运行泄漏到仓库根），外加 `temp/` 的 22 个 scratch 文件与 `-shm/-wal`。它们不进 git，但污染任意检出的工作树、干扰"任意机器结果可完全复现"。
- **新增正式工具 `scripts/cleanup_artifacts.py`（幂等、安全）**：
  - 删除仓库根"除交付库 `fist-mbt.db` 外"的全部 `*.db / *.db-shm / *.db-wal`，并清空 `temp/`；
  - **`--check` 干净度守卫**：残留数=0 → 打印 `CLEAN`（退出码 0）；非 0 → 打印 `DIRTY`（退出码 1），可直接挂 CI 当整洁门禁；
  - 保留 `fist-mbt.db`（唯一被 git 跟踪、作为评审"数据库快照"的交付）与其 WAL sidecar（`-shm/-wal` 属瞬态，随下一打开必然重建，不算残留）。
- **实证数据**：首次清理移除 **74 个**生成物；再跑 mcp_smoke + 全量测试后复清理 **63 个**（确认测试会再生成、但全部 gitignore、绝不进入提交）；最终 `--check` **CLEAN**（仓库根仅 `fist-mbt.db`，`temp/` 无残留）。git 工作树只显示新增脚本本身，提交零污染。
- 顺带修正 scripts/README 里 `mcp_smoke` 描述过时的"75 工具"→77（文档即实现）。
- 验证：`moon test --target js` **215/215** 全绿（清理不影响任何测试）；`cleanup_artifacts.py --check` **CLEAN**。

## 资源消耗
- 新增：`scripts/cleanup_artifacts.py`（约 100 行，纯标准库，无第三方依赖）。
- 修改：`scripts/README.md`（新增脚本说明 + 修正 75→77）；`memory/2026-09-25.md`（R15）。
- 清理动作（不入库）：仓库根 45+ 个 `.db`、`temp/` 22 个 scratch 文件及 `-shm/-wal`。

## 任务分配记录
- 直接实现（指挥官终审制）：本轮为运维/整洁治理，证据先行（`git ls-files *.db` 确认仅 `fist-mbt.db` 被跟踪，其余全 gitignore 可安全删）；直接实现 + 实机验证（mcp_smoke 确认交付库完好、全量测试 215/215、`--check` CLEAN）。

## 遗留风险
- 测试/自驱脚本每次运行**仍会再生成**这些 gitignore `.db`（根因在测试各自在 cwd 落库，未收敛到系统 tmp）。本轮给的是"一键清理 + CI 守卫"，未做"迁移测试落盘到 tmp/ 的大改造"（改动面大、风险高，留作可选后续）。
- `fist-mbt.db`（评审数据库快照）只吃到"上次 checkpoint"，此前删除 `-wal` 会丢弃未 checkpoint 的非提交帧——属预期（快照 = 已提交态），不影响完整性（smoke 读库验证通过）。

## 后续建议
- 可选：把测试默认积落盘从 cwd 收敛到系统 tmp/（`@fs.tmpdir` / tempfile），从源头消除生成物；但需逐个包改造并回归，风险权衡后留作可选项。
- 下一可借力点（按调研强度）：
  1. **难度校准**：把 `decide_difficulty` 接进 `task_plan_deep gradient` 标签；
  2. **Marketplace / Dynamic 能力路由**（远期）。

## 超额内容
- 顺带把 `cleanup_artifacts.py --check` 做成 CI 可用的整洁门禁（退出码语义），使"项目整洁"可被机器验证、而非口头承诺。

## 来源
- 现状：仓库根 `*.db` 审计、`.gitignore`（`*.db`、`temp/`、`!fist-mbt.db`）、`git ls-files *.db`。
- 代码：`scripts/cleanup_artifacts.py`、`scripts/README.md`。