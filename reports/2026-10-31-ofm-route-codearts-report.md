# 2026-10-31 · OFM 免费路由接线 + codearts 执行器一等化验证（Round 1 · ns=ofm-route-r1）

## 结果摘要
- **T0.1.1 / T0.1.2 已完成并验收**：codearts 执行器两条注册路径全部实证。
- **T0.2（OFM 全链路）blocked**：端点 `127.0.0.1:18899` 未监听，等 DSH 桌面端拉起后复验。
- **T0.3（白名单一等化）deferred**：`src/executor/mcp_delegate.mbt`、`registry_test.mbt` 在并发 agent WIP 里，收口后再动 `cli_argv.mbt:17`。

## 实证记录（L4）
| 项 | 命令 | 读数 |
|---|---|---|
| codearts 受限通道注册 | `executor_register --name codearts` | persisted=true, executors=3 |
| 裸名真跑 | `executor_run(executor=codearts, --version)` | **ENOENT → failure_kind=NOT_EXECUTABLE**，retry_skipped 按政策不换模型（可执行缺失与模型无关）|
| 绝对路径注册 | `executor_register --name C:/Users/victo/.codeartsdoer/installers/bin/codearts.exe` | persisted=true |
| 绝对路径 dry_run | `executor_run(dry_run=true)` | argv=["--version"]，不经 shell |
| 绝对路径真跑 | 同上去掉 dry_run | **exit_code=0, failure_kind=NONE** |
| OFM 端点 | `curl 127.0.0.1:18899/v1/models` | HTTP 000（未监听）|

## 结论
1. **atomcode 已是一等**（白名单 `cli_argv.mbt:17` = aider/atomcode/ofm），无需动作。
2. **codearts 走自定义执行器通道已可用**——但 spawn 层有 Windows 硬约束：裸名（bash 脚本）与 `.cmd` 垫片都不行（判例-33 同族），**必须注册 `bin/codearts.exe` 绝对路径**。
3. 注册表 binary 由注册名推导（`executor_register` 只收 name/abilities），想给"友好名+绝对路径"需要改白名单或注册面——并入 T0.3 deferred。

## 遗留风险 / 后续建议
- DSH 拉起后跑：`/v1/models` 拉清单 → 播种 `free_pool`（lane 显式声明）→ `model_route` 决策 → `executor_run(executor=ofm)` 真跑记账。
- `src/executor` WIP 收口后：codearts 升一等白名单 + 注册面支持 binary 路径字段。

## 来源
- 真源：`src/router/`（44 文件）、`src/executor/cli_argv.mbt:17`、USAGE.md §6.15
- FIST 闭环：ns `ofm-route-r1`，T0 已拆 3×2，T0.1 两叶已完成验收
