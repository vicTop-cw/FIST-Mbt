# 2026-11-01 · Round C（BUG-530 收尾 + 播种读回锁 + custom executor argv 修通）

## 结果摘要
3 件任务全部终审通过（实跑格子 + 全量回归，零自述）。Round C 标记**收口**。

| # | 任务 | 终审证据 |
|---|---|---|
| 1 | BUG-530 src/server 3 红（mo_2/mo_3/mo_8 播种路径锁假红）→ 0 红 | src/server 563 测试全绿；全量 JS 2004/2004 |
| 2 | b530_1 回归锁过严 → 修法对齐「缺字段 vs 显式空数组」语义 | src/router 96 测试全绿（rs_3 不回归） |
| 3 | custom executor argv 适配 codearts `run [message..]` 接口 | codearts spawn + 写文件 + exit 0 端到端验证 |

## 修复要点

### 1. BUG-530 3 红根因（src/server/model_router_ops.mbt）
`seeds_pools` 用 `warns.is_empty()` 把关，把 `router_restore` 的状态级信息（"无有效状态，按配置新建路由器"——首次调用恒产）误判为配置校验警告 → 播种被误关 → `persisted=false`。

**修法**：分离配置校验警告与状态信息警告。`seeds_pools` 只看 `RouterConfig::from_json` 产出的字段级回落（mo_4 的 window_seconds/threshold_pct 校验仍被拦），不再混入 `router_restore` 的运行时状态信息。

### 2. b530_1 回归锁（src/router/router_state.mbt）
`router_restore(state)` 时 state 显式含 `paid_pool: []`，但旧实现用 `sp.length()==0` 判定 → 回落到默认配置（4 个付费模型），锁假绿。

**修法**：区分「state 中缺字段/非数组」（回落配置，兼容 rs_3 坏状态）vs 「state 中是显式数组（含空数组）」（保留实效值，b530_1 锁真绿）。

### 3. codearts custom executor argv（src/server/model_router_ops.mbt）
`build_command` 只认 aider/atomcode/ofm，自定义执行器走 `(executor, [prompt])` = `codearts.exe <prompt>`，但 codearts 需要 `codearts run <prompt>`。

**修法**：custom_cli 分支改为 `(executor, ["run", prompt])`。

### 4. 插件态同步（plugins/）
gen_plugins.py 重跑 → 四宿主同步到 BUG-1~531/516 条 → cl7 PASS → 同步本机 atomcode/codearts skills 目录。

## 提交记录（scoped 六道校验）
- `3699f012a` fix(router): BUG-530 收尾 + 播种读回锁 + custom executor argv 修通（src/server/model_router_ops.mbt + src/router/router_state.mbt，2 文件）
- `3373ef75a` fix(plugins): 同步账本到 BUG-531/516 + cl7 全绿（9 文件）
- `f43deb6e8` fix(bugs): BUG-530 账本关闭（OPEN→FIXED）+ 插件态同步到 531/516（10 文件）

## 终审验证（2026-11-01 最终树）
- 全量 JS：**2004/2004 passed**（含 b530_1/b530_2/mo_2/mo_3/mo_8 回归锁）
- cl7：PASS（4 宿主 / 64 生成文件 / 182 工具 / v0.3.11 / J 面 6/6 认领）
- mcp_smoke：PASS（182 工具；issue_scan/publish/get 通）
- codearts spawn + 写文件 + exit 0 端到端：PASS
- FIST BUG-530：账本手工落账（OPEN→FIXED）+ 收口小记（点名回归锁）

## 遗留风险 / 后续建议
1. BUG-527（库包 link 面）——独立单号，CI native 臂复验待 runner 实测
2. BUG-525（usage 守卫）——case 已注册但 CI 门禁待跑
3. BUG-523（账实对齐）——拆单追记已落地，CI native 复验同上
4. M1 路由+成本可视化面板 —— Round C 收口后进入 M1 队列
5. 本机 codearts skills 目录已同步，dsh/deepseek-harness 技能目录本机未装（路径 `~/.dsh/skills/` 不存在）
6. FIST bug_fix cwd 限制（serve-launcher 产物目录 ≠ 仓库根）导致本次账本手工落账；后续闭环建议人工兜底或改 server cwd

## 来源
- FIST 闭环：ns `ofm-route-r1` T0.1/T0.2 已关；`explore-r1/r2` 4/4 已关
- 提交纪律：scoped 六道校验（commit_scoped.sh）
- 并发禁区：全程避开 src/** 66 文件 WIP 面（其他 agent 占用中）
- 账本权威：memory/bugs.md BUG-1~531 共 516 条：**8 待修 / 469 已修**（BUG-530 已 FIXED）
- fix-530-mo 子代理 scope 与 fix-530-final 冲突 → stop 后重派；fix-530-mo 第一轮被限流 → 统帅直接接手诊断
- codearts 首次 argv 错把 prompt 当 project 路径 → 静态 grep 发现 parse_lane 全静默收（不产 warning）→ 实测才定位到 router_restore 状态级信息是真因
- b530_1 首轮修法（`sm.contains("paid_pool")`）误伤 rs_3（`paid_pool: "nope"` 字符串被当数组用）→ 加 `Json::Array(_)` 守卫后双绿

## 遗留风险 / 后续建议
1. BUG-527（库包 link 面）——独立单号，CI native 臂复验待 runner 实测
2. BUG-525（usage 守卫）——case 已注册但 CI 门禁待跑
3. BUG-523（账实对齐）——拆单追记已落地，CI native 复验同上
4. M1 路由+成本可视化面板 —— Round C 收口后进入 M1 队列
5. 本机 codearts skills 目录已同步，dsh/deepseek-harness 技能目录本机未装（路径 `~/.dsh/skills/` 不存在）

## 来源
- FIST 闭环：ns `ofm-route-r1` T0.1/T0.2 已关；`explore-r1/r2` 4/4 已关
- 提交纪律：scoped 六道校验（commit_scoped.sh）
- 并发禁区：全程避开 src/** 66 文件 WIP 面（其他 agent 占用中）
- 账本权威：memory/bugs.md BUG-1~531 共 516 条：9 待修 / 468 已修
