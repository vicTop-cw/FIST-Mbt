# marvis 组合模式第4轮（2026-10-16）

## 总览
- 命名空间：`marvis-drive`
- 主题：清整 + 验证
- 时间：16:10Z – 16:26Z
- 分支：`marvis-polish-20261016`

## 阶段汇总

| # | 阶段 | 任务 | 状态 | 交付物 |
|---|------|------|------|--------|
| 1 | 寻虫 bugfind·R3 | T0r643 | ✅已归档 | 发现并修复 BUG-254 |
| 2 | 打磨 polish·R3 | T0r644 | ✅已归档 | plan/task_plan_deep split_n>=1 校验 |
| 3 | 清整 tidy·R4 | T0r645 | ✅已归档 | 清理 T0r628.1-6 孤儿占位任务 |
| 4 | 验证 verify·R4 | T0r646 | ✅已归档 | 全仓 1260/1260 绿 + issue_scan 复查 |

## 关键成果

### BUG-254 发现与修复
- **现象**：`circuit_fail(threshold=0)` → 首败即熔断；`circuit_fail(window_secs=0)` → 永不熔断
- **根因**：server.mbt circuit_fail handler 未校验 window_secs/threshold/recovery_secs 正数
- **修复**：增加正数校验（<1 返回 ToolError）
- **commit**：26a3783

### split_n 校验
- `plan` handler 增加 split_n >= 1 校验
- `task_plan_deep` handler 增加 split_n >= 1 校验
- 防止 0/负值拆分产出空子任务数组
- **commit**：04cd9f2

### 孤儿任务清理
- T0r628.1-6 六条占位子任务（父 T0r628 已归档，实际工作已由 T0r629-635 完成）全部归档
- marvis-drive 占位垃圾清零

### 验证核验
- `moon test --target js` 全量：**1260/1260 绿**
- `issue_scan src/server`：0 high / 6 medium（substring-overrun 均判误报）
- `issue_scan src/engine`：0 high / 0 medium
- 健康度：**healthy**

## Git 提交
- `26a3783` fix(BUG-254): circuit_fail 参数正数校验
- `04cd9f2` fix(server): plan/task_plan_deep split_n >= 1 校验

## 环境
- MCP server（PID 2728）仍跑旧 debug bundle
- BUG-241 修复未在现网生效（需 DSH/MCP 重启加载新 bundle）
- BUG-217②/185②/186② 次条待重启后补标 FIXED

## 后续建议
1. 重启 DSH/MCP 加载新 bundle，使 BUG-241 修复现网生效
2. 重启后补标 BUG-217②/185②/186② 次条
3. 重启后继续 LADDER 链（fist-allmodes 35 条 spec=none 任务）
4. 组合循环下一轮可聚焦 explore 模式探索全局 blocked 旧任务清扫