T0r322 -> BUG-38  同族：BUG-37 臆造名单 / BUG-33 无人读广告 / BUG-38 臆造调用——契约说谎三连
Round4-验证段(T0r382) -> Round5-修复段(BUG-74/BUG-75)  验证段入账未修的两条：返回契约缺失 + 判据无诊断回执；两条都要配成对锁（必红 + 必不误抓）
shim -> bug-161-bug-163-mcp-compat  外部 shim 是 BUG-161/163 的当前缓解方案；内建 compat 层由并发 agent 负责，当前未提交且缺陷（protocolVersion 回写 + 丢通知）
is_finite -> Double-finite-check  MoonBit Double 无 is_finite 方法。等价替代：`n == n`（NaN 时 false，n>=X 已排除 NaN）。并发 agent 在 router_config/router_state 引入 is_finite 导致编译失败（BUG-193）。
