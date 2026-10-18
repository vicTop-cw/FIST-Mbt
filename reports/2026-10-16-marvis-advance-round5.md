# marvis 组合模式第5轮 · 推进评估报告

## 时间
2026-10-16 16:27Z – 16:32Z

## 现状评估

### marvis-drive
- 20 任务全部归档（0 在流 / 0 待领取）
- 健康度：**stalled**（无活跃在流，需要继续发布组合循环）

### fist-allmodes（LADDER 链）
- 123 任务，40 在流，35 待领取，46 已完成
- 健康度：**healthy**（0 blocked）
- **瓶颈**：35 条 spec=none 待领取任务全部依赖前序兄弟完成
- 根因：T0r583.1.2 等前序叶任务被其他 agent（atomcode-3 等）claim 后未交付
- heal 已回滚至「已领取」但**未清空 assignee**（BUG-240 修复未在现网生效）
- 无法通过 reopen_task 强制重派（BUG-240）

### 全局
- 2445 任务，1105 已暂停（全部在旧轮次命名空间）
- 活跃命名空间：`tnr-polish`, `fist-allmodes`
- marvis-drive 不在活跃列表中，但我们的任务库仍可用

## 推进方案

### 短期（本轮已做）
1. ✅ 修复 BUG-254（circuit_fail 正数校验）
2. ✅ 修复 plan/task_plan_deep split_n >= 1 校验
3. ✅ 清理 T0r628.1-6 孤儿占位任务
4. ✅ 全仓 1260/1260 测试回归

### 中期（需 MCP server 重启）
1. 重启 DSH/MCP server 加载新 bundle（fist-mbt.js）
2. 补标 BUG-217②/185②/186② 次条 FIXED
3. 重启后 LADDER 链可被 heal 清空 assignee 重新认领
4. 继续 fist-allmodes 组合循环

### 长期
1. 清扫 1105 条已暂停旧任务（task_cleanup 或批量归档）
2. 探索新的 fist-mbt 能力（explore 模式）
3. 开启自动路由（selfdrive_dispatch）推进 fist-allmodes

## 本轮 Git 提交
- `26a3783` BUG-254 fix
- `04cd9f2` split_n >= 1 校验
- `f7e1a6b` 第4轮汇总报告

## 下一轮建议
1. 重启 DSH/MCP 后重跑 LADDER 链
2. explore 模式探索新能力
3. 继续组合循环