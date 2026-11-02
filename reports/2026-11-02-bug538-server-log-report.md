# BUG-538 server 落盘日志（工程半）汇报 · 2026-11-02

## 结果摘要
- **事故**：fist-mbt MCP server（Qoder 插件连接器拉起）进程死亡，全机进程面零实例，连接器对一切调用回 -32603 持续 >60 分钟；死因不可判——server 的 stdout/stderr 被宿主吞掉、无落盘日志（BUG-538，[medium] OPEN）。
- **工程半落地**：serve 入口现在把关键生命周期事件写 `<db 目录>/server.log`（`FIST_SERVER_LOG` 可覆盖路径 / `=off` 关闭），只写文件、零 stdout 占用、IO 失败静默降级。记录面：`server.start`（version/pid/auth_mode/db_path/log_path）、spawn 生命周期（`spawn.start`/`spawn.end`：cmd、截断 args、timeout、ok/code/耗时/capped 旗）、崩溃钩子（uncaughtException / unhandledRejection / exit——只加记录不改退出语义）。
- **运维半**：owner 在 Qoder 重连 fist-mbt MCP 连接器（T0r6/T0r11/T0r12 的 verify→archive 仍挂起等恢复）。

## 资源消耗
- 模型：Qoder 主会话统帅（终审/落账/计数同步）+ general-purpose 车道 ×1（实现）。
- 工具：Read/Edit/Write/Bash/Grep/Git；判据面 `moon_test_env`、`check_mcp_stdio_purity`、`check_fmt_gate`、`check_test_sync --fresh`。

## 任务分配记录
- 车道（general-purpose ×1）：server_log.mbt（纯函数 8 面）/ server_log_js.mbt（js FFI + 崩溃钩子）/ server_log_native.mbt（no-op 桩）/ 两份 wbtest（5+3 格）/ run_server 接线 / run_check_external 单一收口点接线 / moon.pkg targets 三条。
- 统帅：BUG-538 立账（进程面取证）、任务包、终审（diff 亲读 + 判据亲跑）、计数面 2020→2028 同步、落账与本报告。

## 终审证据（统帅亲跑）
- `moon_test_env --target js src/server` = **584/584**（基线 576 + 8）；全仓 `--target js` = **2028/2028 failed 0**（temp/full_js_2028.log）。
- `check_mcp_stdio_purity` rc=0（stdout 2 行全合法 JSON-RPC）；`check_fmt_gate` PASS。
- 端到端冒烟（车道，FIST_DB_PATH 指 temp 隔离库）：server.log 实录 `server.start` / `spawn.start` / `spawn.end ms=39` / `server.exit code=0` 四行；`FIST_SERVER_LOG=off` 时零文件。
- native 面：`moon check --target native src/server` 0 error；wbtest manifest 实证 js-only IO 格不进 native 测试面。

## 遗留风险
- native 面无日志（no-op 桩不假装成功）——权威运行面是 js，风险低。
- node 原生 OOM（`FATAL ERROR: Ineffective mark-compacts`）不经过 uncaughtException，只能靠最后一条 spawn.end + server.start 判区间，不是全量 OOM 取证。
- 日志无轮转/大小上限（行级已截断），低频事件增长极慢，轮转留后续单。
- 文档面：USAGE/README 的 `FIST_SERVER_LOG` 环境变量清单未补（本单边界外，并入下次文档收口，注意 J4/J17 同步）。

## 后续建议
1. owner 重连连接器后：T0r6/T0r11/T0r12 补 run_check 记录 → verify(verifier=human_steward) → archive ×3。
2. BUG-538 关闭条件②改判「工程半已具备」；两半齐（重连 + 下次死亡若有可判因）才翻 FIXED。
3. 下次文档收口补 `FIST_SERVER_LOG` 说明。

## 超额内容
- 计数面 2020→2028 全现状面同步（9 文档、同日复测日期归属不变）+ `check_test_sync --fresh` 复验——本属「计数合流」纪律的必要收口，非本单任务书内容，单列。

## 来源
- 会话：Qoder Desktop 统帅会话（130c7515），2026-11-02 14:30~16:30 段；任务台账 ns iterate-1102（server 死亡期间无法 publish，本单走 scoped 直提）。
