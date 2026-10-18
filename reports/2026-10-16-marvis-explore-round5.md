# marvis 组合模式第5轮 · 探索发现报告

## 时间
2026-10-16 16:29Z – 16:31Z

## 探索能力清单

### 1. 项目助理选举系统（assistant_*）
- 当前 primary：`polish-lead`（mode=all，heartbeat 新鲜 @16:13）
- 无冲突，其他 agent 已占用主助理位
- marvis 可 `assistant_claim` 注册为备选或接管（需 heartbeat 陈旧 >300s）

### 2. 自进化档案库（evolve_*）
- 32 条 artifacts 已入库
- Best principle：**可选分发的顶层硬 import 是标准安装的崩溃源**（vools 项目经验，score=1）
- 可 `evolve_submit` 提交本轮经验（如「多 agent 共享工作区时 git add 必须审查 staged diff」）

### 3. 组合环注册表（loop_create/status/tick）
- `tnr-combined-6phase`：goal_reached（8 轮上限，健康度 healthy 触发停止）
- `vools-combo-r1`：goal_reached
- `round262-fix-iterate`：active（bugfind + fix_and_merge，5 轮上限）
- marvis-drive 尚未创建组合环，可 `loop_create` 创建 marvis 专属环

### 4. Laya 决策（laya_decide）
- Laya 本机不可用（sidecar 未安装），自动降级规则式分支
- 当前任务判：complex=true，feature_route=排程路由，split_n=4
- `no_sidecar=true` 逃生门已启用，零延迟确定性决策

### 5. 执行者市场（executor_*）
- marvis 已注册为 executor（abilities=[寻虫,修复,打磨,验证,文档]）
- executor_auction：marvis 因 load=1 + trust=0 被 pentad-fixer 超越
- 教训：**需要更多已完成+验收通过的交付记录才能获得信任分**；当前负载高

### 6. 超级管家（supervisor_*）
- 待投递引导：0 条（当前无阻塞）
- supervisor_reminder_tick 可扫描停滞任务

### 7. 模式注册表
- 7 种模式全部可用
- 当前循环已使用：bugfind/polish/verify/tidy/advance/explore
- 未使用：fix_and_merge（需 GitHub token）

## 新能力建议

1. **evolve_submit 提交经验**：把「多 agent 共享工作区时 git add 必须审查 staged diff（commit 26a3783 事故）」作为 lesson 入库
2. **loop_create 创建 marvis 专属组合环**：把 advance/polish/bugfind/verify/tidy 循环起来
3. **assistant_claim 注册为备选助理**：polish-lead heartbeat 陈旧时接管
4. **executor_auction 参拍**：先把 trust 提升再参拍关键任务

## 结论
- FIST-Mbt 已具备全套自驱能力
- marvis 已注册 executor 能力
- 下一步：把探索成果沉淀进档案库 + 创建 marvis 专属组合环