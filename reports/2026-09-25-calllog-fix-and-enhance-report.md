# call_log 修复 + 三块增强 汇报（2026-09-25）

## 结果摘要
在 `fist-mbt.db` 的 call_log 中诊断出并根治一个**整库性时间戳 bug**，随后按用户方向完成三项能力/哲学增强。**`moon test --target js` 195/195 全绿**（修复后 191，增强后 195），全部默认关闭零回归；输入端到端 MCP 验证 8 项全过，工具数 67→68。

## 资源消耗
- 未单独记账；全程本地 build/test（moonc v0.10.14，Node v25）；未在 WSL 下载模型、未启用 Laya。

## 关键发现与修复
1. **根因（call_log 453/453 损坏）**：`@env.now()` 返回 UInt64 毫秒，`now_default`/`_instrument` 用 `.to_int()` 做 32 位截断（`1790319218428 → -682144004`）→ 内部时间戳全变 1969、seq 为负。修复：`.to_int64()` Int64 运算 + `_call_log_seq` 单调计数 + `recent_call_logs` 改 `ORDER BY id DESC`。
2. **共享库被测试污染**：`call_log_wbtest` 曾写共享 `fist-mbt.db`；改独立内存引擎，并清洗 464 损坏 + 8 `wbtool_err` 假行。
3. **ns 多空不可分项目**：`_log_call` 增加 ns 缺失回退 `project_dir`。

## 三块增强
1. **Laya 躬身入局**：`task_plan_deep` 新增 `decide_*`；优先"躬身自决"（可审计 `plan_decision`），Laya 降级为冷启动参考。
2. **文档即实现门禁**：`verify(docs_check=true)` 校验 README/CHANGELOG/reports + 交付物五段式，不达标打回。
3. **外库→可选资产 + 注入**：`evolve_asset_register` + `plan/claim(inject)` 注入档案库资产。

## 任务分配记录
- 主代理：call_log 根因定位与修复、三块增强编码与单测、E2E 脚本、文档同步、本汇报。
- Explore/Plan 子代理各 3/1：定位 task_plan_deep/docs_gate/evolve 侵入点，收敛实现方案。

## 遗留风险
- `fist-mbt.db` 含 E2E 演示写入（enhance-e2e ns）；`temp/` 已 gitignore，无污染提交。
- Node `node:sqlite` 仍打实验性警告（功能正常）。

## 后续建议 / 打磨主线（本次环视归纳）
见下节「Laya 可用点」与「全局打磨清单」。

## Laya 可用点（扩展 put落到哪）
现有 `laya_decide` 只服务 `task_plan_deep` 的 split_n 自动档。可推广到：
1. **丐体验卡**：`publish` 前用 difficulty 挡位做「评审快速打钩」默认值，库冷启动第一轮免手选。
2. **派发域提示**：把 `domain`/`task_type` 挂到 `claim` 或 `publish` 返回，提示该给哪类执行者。
3. **事务型门控**：`needs_tools / is_sensitive` 作 `execute/gate` 的前置权重（浅提示，不强制 block）。
4. **工作量预估**：对 `watchdog_tick` 的 next 根任务给 timebox 建议，供 cron 节奏自适应。
> 均保持「可选、降级、可被 sqlite 建议覆盖」——Laya 永远只做 sidebar 参考，绝不做唯一决策者（本轮已确立 decide_* 躬身自决为唯一真源）。

## 全局打磨清单（环视）
1. **统一 gate 抽象**：omega/gate/docs 三个 gate 逻辑同构，收敛到 `src/engine/gates.mbt` 共用「是否开启」判定与文案。
2. **失败回流学习**（远期，已入 future-roadmap）：reject/omega 打回 reason → evolve 档案 → `inject` 注入"踩过的坑"。
3. **纯 MoonBit 化 Laya**：`mizchi/llm` 客户端替换 Python sidecar，减少运行时依赖（或保留 sidecar 但改为可选时延优先）。
4. **scoring.mbt 闭环实证**：跑通 ≥7 测试，把自进化从描述变为可运行证据。
5. **README/申报书 AIGC 标记 + 一页 PDF**：消除"纯 AI 生成"误判减分。
6. **ASCII/Dashboard 可视化**（状态流、DAG 图）：对冲"偏好可见效果"评审偏好。
7. **consolidate 命名空间隔离**：`memory_consolidate` 目前按目录写，可对齐多租户 ns 语义，避免兄弟项目互相覆盖。
8. **E2E 常驻化**：把 `log_fix_selfdrive`/`enhance_verify` 接入 `demo.ps1`/CI 轨道，确保"改动人手即跑通"。

## 超额内容
- call_log 整库损坏根因精确定位到 UInt64→Int 截断这一语言级真 bug，且用 Int64 主算完成根治。
- 三块增强均"缺省零回归"，把能力做成可选而非破坏性改动，适合多项目共享底座。

## 来源
- `fist-mbt.db` call_log 实测（453 行 1969/负 seq、162 条清洗后健康）
- `src/server/server.mbt`、`src/engine/{docs_gate,engine}.mbt`、`src/store/store_sqlite.mbt`
- 探针：`temp/probe_time`（已删）确认 `@env.now().to_int()` 截断
- E2E：`scripts/{log_fix_selfdrive,enhance_verify,atgc_selfdrive_demo}.py`

*（内容由AI生成，仅供参考）*