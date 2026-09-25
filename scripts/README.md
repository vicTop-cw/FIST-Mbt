# scripts/ 脚本分类规范

> 目的：项目整洁——临时脚本任务完即清理，正式工具统一管理，避免根目录/scripts 堆垃圾。

## 命名约定

| 前缀 | 含义 | 处理 | 示例 |
|---|---|---|---|
| **无前缀** | 正式、可复用工具 | 保留，写入 README 说明 | `mcp_smoke.py`、`patch_esm_main.py`、`omega_lesson_verify.py`、`demo.ps1`、`gen_apply_pdf.py` |
| **`_` 前缀** | 临时/一次性/诊断脚本 | **任务完即删**，或移入 `temp/`（gitignored） | `_diag_*.py`、`_scratch_probe.py` |
| `m9_* / m18_*` | 历史迁移遗留 | gitignore 覆盖；无需再产生 | — |

## 约束（Golden Rule）

1. **不产生带 `_` 前缀的正式工具**：`_` = 临时代码生成物，用完即删。
2. **临时产物落 `temp/` 或系统 tmp**：不要污染仓库根；`temp/` 已在 `.gitignore`。
3. **正式工具**：无前缀 + 文件头 docstring 说明用途/用法/前置 + 退出码约定。
4. **改完即验**：新增/改动脚本后，确保它能在干净环境跑（依赖公开）。
5. **不留绝对路径**：脚本内路径用 `os.path.join(dirname, ...)` 或环境变量，禁止硬编码盘符。

## 现有正式工具速查

**基础 / 演示**
- `mcp_smoke.py` — MCP server 一键自检（81 工具 + publish/get 链路）。
- `award_demo.py` — **获奖自驱 DEMO（评审一条命令演示）**：串演 map→递归拆解(gradient)→验收闭环→Challenger→Critic→作用域预订→脉冲/看板 全链路，结尾自动清理临时区并 `--check` 守卫仓库干净。用法：`python scripts/award_demo.py`。
- `cleanup_artifacts.py` — **项目整洁/生成物清理**：删除仓库根"除交付库 `fist-mbt.db` 外"的全部被 gitignore 的 `*.db / -shm / -wal` 测试/演示残留，并清空 `temp/`；`--check` 模式作 CI 干净度守卫（0 = 干净，非 0 退出码 1）。用法：`python scripts/cleanup_artifacts.py` / `python scripts/cleanup_artifacts.py --check`。
- `score_gate.py` + `scoring_rubric.md` — **4-AI 概率自评分门禁**：统一 rubric 提示词（维度/稍宽口径/SCORE_JSON 契约）作为正式工具统一管理（原 `_ai_prompt.md` 从临时命名升级）；全档达标 AND 聚合、error 不降级。
- `patch_esm_main.py` — moonc≥0.10.14 ESM 输出注入 createRequire shim（幂等）。
- `demo.ps1` — 一键演示（build+patch+smoke）。
- `native-env.ps1` — Windows native 环境一键装载（VS + sqlite-dev）。
- `gen_apply_pdf.py` — 一页项目申报书 PDF 生成（个人档，不入库）。

**自驱闭环（selfdrive）**
- `log_fix_selfdrive.py` — call_log 缺陷修复自驱闭环。
- `enhance_verify.py` — 三块增强 E2E 验证。
- `enrich_selfdrive.py` — 获奖提升增强自驱闭环。
- `atgc_selfdrive_demo.py` — ATGC 极简双链虚拟机自驱+Omega DEMO。
- `lesson_selfdrive.py` / `scratch_selfdrive.py` — 失败回流 / 临时隔离 技能自驱闭环。

**能力 E2E 验证（verify）**
- `map_verify.py` — 项目地图（`fist://map`）E2E。
- `lesson_verify.py` — 失败回流（evolve_lesson 独立工具）E2E。
- `lesson_chain_selfdrive.py` — 打回→lesson 归档→dead_ends 闭环演示。
- `dag_depend_verify.py` — DAG 显式依赖 E2E。
- `scratch_verify.py` — `store_open(scratch)` 临时隔离 E2E。
- `omega_lesson_verify.py` — **Omega 打回自动落 [lesson] + 进程内可见** E2E（三类打回自动沉淀 + scratch 隔离 + 结束精确清理根库）。
- `plan_gradient_verify.py` — `task_plan_deep gradient=true` 难度梯度 + 更简单变体 E2E（默认关闭零回归 + scratch 隔离）。
- `evolve_critic_verify.py` — `evolve_critic` Critic 防漂移门禁 E2E（81 工具 + 放行/拒收/收紧阈值 + 只评审不写库）。
- `task_challenge_verify.py` — `task_challenge` Challenger 进阶变体 E2E（81 工具 + [challenge]溯源/扩规模 + 未完成任务拒绝 + scratch 隔离）。
- `executor_route_verify.py` — **执行者能力路由（Marketplace 雏形）E2E**：`executor_register` 登记能力 + `executor_route` 按「能力覆盖率 desc → 负载 asc」路由最佳执行者（81 工具）。
- `board_ascii`（内建 MCP 工具 + 测试）— 实时任务看板 ASCII：按状态分组 + 深度缩进，一眼看全貌（`src/server/board_ascii_test.mbt` 全绿）。

> 所有 `*_verify.py` 共用同一 MCP STDIO 启动模式（`moon build --target js cmd/main` + `patch_esm_main` → node）。