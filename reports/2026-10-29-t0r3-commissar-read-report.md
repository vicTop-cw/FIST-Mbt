# T0r3 交付报告：消息池接收侧（`commissar_read`）+ `.commissar/` 四目录

> 任务：`T0r3`（ns `fist-plan-20261029`，P1）｜认领：`lead`｜执行：子代理 `87c6e524`｜终审：lead
> 提交：`e040fc52`（30 文件 / +763 −76，含生成投影）

## 一、结果摘要

同机消息池从「只能发」变成「能发能收」：新增 MCP 工具 **`commissar_read`**（工具数 **178 → 179**），
`.commissar/` 正式化为 `events/ inbox/ outbox/ archive/` 四目录 + `reminder_log.md`。

| 项 | 读数 |
|---|---|
| `src/ops` | `Total tests: 217, passed: 217, failed: 0`（基线 212 → +5 锁） |
| `src/server` 回归 | 553/553 |
| `cmd/cli` | 10/10 |
| 端到端（真 MCP stdio） | stdout 4 行**全 JSON-RPC**、`tools/list`=179、send→read **ROUND-TRIP OK** |
| 守卫（lead 复跑） | `check_tools_sync` PASS（179）、`check_plugin_sync` PASS（4 宿主/64 文件/179） |

## 二、设计与关键取舍

1. **纯同步一次性遍历**，零 watcher / 零句柄 —— BUG-480 已结论 `fs.watch(persistent:true)` 在 js 后端 dispose 后不释放，
   订阅会让 server 进程永不退出；MCP 本身是请求/响应模型，持续订阅也不匹配。
2. **`alg` 白名单放在 decrypt 之前**：用 `CipherNone` 解 aes 密文会得到"能 base64、语义是垃圾"的明文，
   然后在 packet 层报"字段缺失" ⇒ 把「解不开密文」误报成「payload 不合规」，坏文件策略失去诊断价值。
3. **计数三分**（`matched` / `returned` / `dropped_by_limit`）：否则「被过滤掉」与「被 limit 截断」混读（BUG-74 同族）。
4. **坏文件计数 + 点名**，不中断其余文件；`bad.files` 明细上限 20，`bad.total` 全量。
5. **`since_seq` 用闭区间毫秒游标**：宁可重复不可丢；同毫秒多条一起进出（已在工具描述写明）。严格不重复游标需全局单调序号，列为后续单。

## 三、变异对照（三组，均真改代码）

| 变异 | 读数 |
|---|---|
| A：`ct` 当明文、跳过 decrypt | 3 锁红（`0 != 1` / `0 != 2` / `0 != 1`） |
| B：坏信封静默跳过、不计数 | `dl_c6` 红（`2 != 3`） |
| C：解密失败静默跳过 | `dl_c6` + `dl_c8` 红（`2 != 3` / `0 != 1`） |
| 还原 | `RESTORED-IDENTICAL` → 217/217/0；变异残留 grep = 0 |

## 四、缺口与风险

1. **`moon fmt` 的作用域是「包」不是「文件」**：它顺手重排了另一条 lane 的 `src/ops/ops_bug480_watch_probe_wbtest.mbt`
   （语义未变）。提交时**已明确排除**该文件，不记入本单。
2. **`since_seq` 粒度**：毫秒级 ⇒ 同毫秒多条无法单独定位（一起进出，不丢）。
3. **跨进程可见（同机）成立，跨机不成立**（本地文件系统）。
4. **坏文件不自动清理**、`archive/` 不自动搬移（自动搬会让"读过的还在不在"不可预期）⇒ 长期堆积需人工/运维策略。
5. **`outbox/` 只建不写**：回执语义未定案，不替后续单元拍板。
6. **未迁移到 4 池子提案目录**（`.fist-mbt/pool/messages/`）：该提案 owner 未定案。

## 五、后续建议

1. 严格不重复游标（全局单调序号，落盘）。
2. `outbox/` 与 `archive/` 的 owner 语义定案后补读写。
3. 若要正式化「同机消息池」章节，建议 `docs/2026-10-29-commissar-message-pool.md`（四目录读写 owner + outbox 待定案）。
4. 账本不必记为 bug 修复（这是新能力）；若要关联，指向 BUG-480 的「接收侧替代方案 = 短轮询」已落地。

## 六、超额内容

`moon fmt` 的包级作用域是本次撞出来的**工具行为事实**，已写入提交说明与本节：以后按"文件"调 `moon fmt` 仍会重排整包，
并发 lane 下必须按路径拆分提交。

## 七、来源

- 任务：`T0r3`（`fist-plan-20261029`）
- 上游：`reports/2026-10-29-4pools-gap-analysis-report.md`（指出"有实现但没接出来"）、`reports/2026-10-29-plan-reconciliation-report.md`
- 约束来源：BUG-480（watch 不可取消）、BUG-74（两栏不许混读）
