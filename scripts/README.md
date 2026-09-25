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
- `mcp_smoke.py` — MCP server 一键自检（84 工具 + publish/get 链路）。
- `award_demo.py` — **获奖自驱 DEMO（评审一条命令演示）**：串演 map→递归拆解(gradient)→验收闭环→Challenger→Critic→作用域预订→脉冲/看板 全链路，结尾自动清理临时区并 `--check` 守卫仓库干净。用法：`python scripts/award_demo.py`。
- `cleanup_artifacts.py` — **项目整洁/生成物清理**：删除仓库根"除交付库 `fist-mbt.db` 外"的全部被 gitignore 的 `*.db / -shm / -wal` 测试/演示残留，清空 `temp/`，并把 `scripts/` 下 `_` 前缀临时脚本移入 temp/ 后清理（任务完即清策略，R66）；`--check` 模式作 CI 干净度守卫（0 = 干净，非 0 退出码 1）。用法：`python scripts/cleanup_artifacts.py` / `python scripts/cleanup_artifacts.py --check`。
- `score_gate.py` + `scoring_rubric.md` — **4-AI 概率自评分门禁**：统一 rubric 提示词（维度/稍宽口径/SCORE_JSON 契约）作为正式工具统一管理（原 `_ai_prompt.md` 从临时命名升级）；全档达标 AND 聚合、error 不降级。
- `patch_esm_main.py` — moonc≥0.10.14 ESM 输出注入 createRequire shim（幂等）。
- `check_badge.py` — **README 测试徽章一致性守卫（R34）**：比对 `moon test` 实测测试数与 README 徽章 `tests-N%2FN`，不一致即退出码 1（挂 CI 作"徽章不过时可复现"门禁，杜绝手改漏同步）。已经在 `.github/workflows/ci.yml` 的 JS 轨道里自动执行。
- `check_tools_sync.py` — **工具清单单一真源守卫（R46）**：以 `src/server/server.mbt` 实际注册工具名为唯一真源，校验 AGENTS 表格工具名 ⊆ 真源、真源全部入 AGENTS、README/AGENTS/deliverable/scoring_rubric 工具总数==实测（双向防幽灵/漏写）。已在 ci.yml JS 两轨自动执行。
- `check_test_sync.py` — **测试总数单一真源守卫（R47）**：从 `moon test` 日志提取实测总数，跨 README/AGENTS/deliverable/scoring_rubric 校验述一致（N/N、N 全绿、独立 N 任一）；`--total N` 直传亦可。已在 ci.yml JS 轨自动执行。
- `check_scripts_index.py` — **工具类辅助代码单一索引守卫（R62）**：校验 `scripts/README.md` 已登记全部「正式」辅助脚本（无 `_` 前缀），防新生脚本不留说明就堆积——把地图/整洁下沉到工具层。用法：`python scripts/check_scripts_index.py`（0=PASS，1=漏登记）。
- `demo.ps1` — 一键演示（build+patch+smoke）。
- `showcase.ps1` — **30~60 秒视觉终端巡演**：Header/徽章、九态生命周期、DAG、自举采用（读盘真实 548 tasks/196 exec/6 review）、自治派送闭环（triage→dispatch_next→executor_route→watchdog autodispatch 零参数），ANSI+box；实测 exit 0 / ~1.7s，无盘符。用法：`pwsh -NoProfile -File scripts/showcase.ps1`。
- `fist-mbt-http.py` — **HTTP/SSE 传输服务**：把 stdio MCP server 桥接成 HTTP，`GET /health` 健康检查 + MCP over HTTP/SSE。
- `laya_decide.py` — **Laya 决策 sidecar**：把 Laya ML 模型包成可被 fist-mbt MCP server 调用的 JSON sidecar（冷启动选档/探测）。
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
- `evolve_critic_verify.py` — `evolve_critic` Critic 防漂移门禁 E2E（84 工具 + 放行/拒收/收紧阈值 + 只评审不写库）。
- `task_challenge_verify.py` — `task_challenge` Challenger 进阶变体 E2E（84 工具 + [challenge]溯源/扩规模 + 未完成任务拒绝 + scratch 隔离）。
- `executor_route_verify.py` — **执行者能力路由（Marketplace 雏形）E2E**：`executor_register` 登记能力 + `executor_route` 按「能力覆盖率 desc → 负载 asc」路由最佳执行者（84 工具）；R31 跨进程三步：进程A注册→进程B路由读到→clear 消失。
- `dispatch_verify.py` — **能力自动派单（R32）E2E**：`selfdrive_dispatch` 按 want 能力路由并把任务直接认领给最佳执行者（待领取→已领取）；运行后会向交付库写演示任务，完成即 `git checkout -- fist-mbt.db` 恢复整洁。
- `board_ascii`（内建 MCP 工具 + 测试）— 实时任务看板 ASCII：按状态分组 + 深度缩进，一眼看全貌（`src/server/board_ascii_test.mbt` 全绿）。

> 所有 `*_verify.py` 共用同一 MCP STDIO 启动模式（`moon build --target js cmd/main` + `patch_esm_main` → node）。