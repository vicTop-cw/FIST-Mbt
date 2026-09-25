# FIST-Mbt 参赛交付说明（评审速览）

> 定位：**纯 MoonBit 实现的 MCP Server**——AI 指挥官式任务编排，同时是"更好的 AI 项目管理工具"。
> 一次自检即验证核心链路，其余为逐项证据索引。2026-09-25 状态。

## 一、10 秒自检（评审用这个）
```bash
# ① 构建 + 拉起 MCP server 并自检（需 Node ≥ 24）
moon build --target js cmd/main
python scripts/mcp_smoke.py
# 期望输出：PASS tools/list → 78 个工具 / PASS publish / PASS get → MCP-SMOKE PASS
```

## 二、硬指标（快照）
| 项 | 值 |
|---|---|
| MCP 工具 | **78**（+ 3 resources + 2 prompts） |
| 测试 | **`moon test --target js` 219/219**（Windows + WSL(Linux) 双端实测全绿） |
| 回归 | 0（既有语义不破坏，增强默认关闭零回归） |
| 依赖 | 全公开，`moon update` 即可构建，无私有包/登录/vendor |
| Env | Node ≥ 24；`moon info && moon fmt` 后测试（AGENTS.md / 环境要求） |

## 三、核心能力（评审点）
1. **任务编排闭环**：发布→认领→拆分(plan_deep 递归)→执行→提交→验收→归档；父任务自动上卷。
2. **AI 自驱式**：selfdrive_*（审视→自我派活）；自驱脚本见 `scripts/*_selfdrive.py`。
3. **Omega 强验证**：语料创建→审核→成果复验门禁，不达标记打回、超限升级人工（防死循环）。
4. **DGM 自进化**：档案库 + 多样采样 + 蒸馏 principle + **失败回流 lesson**（见探索性闭环脚本）。
5. **DAG 编排**：显式依赖 `dag_depend`、关键路径/并行度/ASCII 图/topo 排序。
6. **多租户**：命名空间物理隔离（`store_open`，`scratch` 临时区不污染根）。
7. **项目地图**：`fist://map` resource——agent 首读即有，避免全项目乱找（docs/agent-map.md）；`board_ascii` 实时任务看板，一眼看全貌。

## 四、自驱增强证据（git 4994aae → HEAD，19 轮）
| 轮 | 增强 | 验证脚本 |
|---|---|---|
| 1 项目地图 | `fist://map` + docs/agent-map + 调研纪要 | `map_verify.py` |
| 2 失败回流 | `evolve_lesson` | `lesson_verify.py` |
| 3 DAG 显式 | `dag_depend` + to_json 修复 | `dag_depend_verify.py` |
| 4 双端复现 | WSL 199/199 复核 | —（实机） |
| 5 临时隔离 | `store_open(scratch)` | `scratch_verify.py` |
| 6 回流闭环演示 | lesson 归档→dead_ends 可见 | `lesson_chain_selfdrive.py` |
| 7 Omega自动落lesson | auto-lesson + 进程内可见 | `omega_lesson_verify.py` |
| 8 看板 | `board_ascii` 实时任务看板 | `board_ascii_test.mbt` |
| 9 脉冲 | `status_summary` + fix `fist://overview`(version/9态) | 单测 + E2E |
| 10 作用域预订 | `reserve_scope/check/release`（Interlinked 拿来主义） | 双后端单测 + E2E |
| 11 预订整洁 | `clear()` 一并清空 reservations（防跨次残留） | 单测 |
| 12 难度梯度 | `task_plan_deep gradient=true`：拆解子任务带「难度梯度 序号/总数:易/中/难」+「更简单变体」提示（LADDER 信号） | `plan_gradient_verify.py` |
| 13 Critic防漂移 | `evolve_critic` 门禁（SAGE）：入库前纯计算评审拟议 principle/lesson，重合≥70% 判课程漂移拒收、综合分低暂缓 | `evolve_critic_verify.py` |
| 14 Challenger进阶 | `task_challenge`：对已完成/已归档任务发布更难变体新根任务（[challenge] 溯源 + 重要度升档，SAGE 四专家环补齐） | `task_challenge_verify.py` |
| 15 生成物清理 | `cleanup_artifacts.py`：除交付库 fist-mbt.db 外清理 *.db/-shm/-wal 与 temp/；--check 作 CI 干净度守卫 | 实跑 74+63 移除 + CLEAN |
| 16 自驱 DEMO | `award_demo.py`：一条命令串演 map→拆解(gradient)→验收→Challenger→Critic→预订→脉冲/看板 | `python scripts/award_demo.py` |
| 17 难度校准 | `task_plan_deep gradient+calibrate`：按切片给真实难度 0..5 覆盖位置档（LADDER 补真实难度） | `plan_gradient_verify.py`（含 calibrate） |
| 18 文档一致 | agent-map 分组对齐 77 工具、fist://map 文案 76→77（文档即实现扫尾） | 全仓 grep 计数审计 |
| 19 native 证据 | `moon check --target native` 0 错误；Windows native 竞态(0xc0000374)文档如实修正，权威门槛=JS 后端双端+Linux native | 实机验证 + cleanup CLEAN |
| 20 下一步推荐 | `task_triage`：可领取任务按 优先级→重要度→深度 排行 + suggestion（agent 无需全量扫描即可决定下一单） | `engine_triage_test.mbt` + award_demo ⑨ |

## 五、文档即实现
- 工具/资源/测试数均与实测一致（README/AGENTS/ARCHITECTURE/agent-map 已同步）。
- 过程日志 `memory/2026-09-25.md`；综合汇报 `reports/2026-09-25-award-enhancement-5rounds-report.md`。
- 调研：`memory/research/20260925.enrich-roadmap.md`（Repo Map / DALIA / TURA / AgentX / MoonBit 新特性）。

## 六、遗留（诚实自曝）
- Windows native 测试偶发 `0xc0000374`（堆损坏/竞态，`-j 1` 可降但不保证消除；权威稳定门槛 = JS 后端双端 + Linux native，产品单进程不受影响，README「已知边界」）。
- `node:sqlite` 打实验性警告（功能正常）。
- 测试落盘目前在仓库 `temp/`（gitignore），由 `cleanup_artifacts.py --check` 作干净度门禁；`@fs.tmpdir` 在本工具链未暴露，"收敛到系统 tmp" 作为可选后续。
- Dynamic/Marketplace 能力路由（executor 抽象层朝"能力注册+按负载/专长分配"）为远期项。

*（内容由AI生成，仅供参考）*