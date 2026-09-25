# FIST-Mbt 架构总览

> **一句话定位**：纯 MoonBit 的 AI 指挥官任务编排底座 + MCP Server + 自进化——"人类指挥、AI/定时器持续自推动"的自治系统，以 75 个 MCP 工具暴露给任意 MCP 客户端。

项目体积小、包边界清晰，本页面向评审展示"用户怎么理解 → 系统怎么运转 → 系统怎么自我进化"的全貌。

## 一、总分结构

```
┌───────────────────────────────────────────────────────────────────┐
│  外部 MCP 客户端（Claude Desktop / Cursor / AtomCode / 自研 JSON-RPC）│
└───────────────────────────┬───────────────────────────────────────┘
                            │  JSON-RPC over STDIO / HTTP-SSE
┌───────────────────────────▼───────────────────────────────────────┐
│  ① 协议层  src/server/       server.mbt     70 工具注册 + run_server │
│                             stdio_js.mbt   JS 后端 STDIO 传输        │
│                             stdio_native   Native 后端 STDIO 传输    │
└───────────────────────────┬───────────────────────────────────────┘
                            │  工具分发
┌───────────────────────────▼───────────────────────────────────────┐
│  ② 引擎层  src/engine  + src/core                                  │
│     FistEngine 领域闭环：发布→认领→拆解→执行→提交→验收→归档          │
│     九态状态机  core_task  / 角色权限矩阵  core_role                 │
│     递归拆解  decompose  / DAG 依赖图  engine_dag_ext               │
│     Omega 强验证  omega_strong（语料门禁 + 成果复验 + 打回升级）      │
└───────────────────────────┬───────────────────────────────────────┘
                            │  读 / 写
┌───────────────────────────▼───────────────────────────────────────┐
│  ③ 运维层  src/ops        心跳 heartbeat / 超时自愈 heal            │
│                           看门狗 watchdog_tick / 冲突检测 conflicts │
│                           审计 audit(追加式) / 清理 cleanup          │
└───────────────────────────┬───────────────────────────────────────┘
                            │
┌───────────────────────────▼───────────────────────────────────────┐
│  ④ 存储层  src/store      Store 抽象 + SQLite 实现  store_sqlite     │
│                           多租户 ns 多库隔离  multi_store            │
│                           表：tasks/executions/heartbeats/specs      │
└───────────────────────────┬───────────────────────────────────────┘
                            │  提交 scoring / DGM
┌───────────────────────────▼───────────────────────────────────────┐
│  ⑤ 自进化层  src/evolve + src/executor                             │
│     evolve  DGM 档案库：评分注入式（非 LLM 自评）+ 血缘 + 查重 + 采样  │
│     omega   可解释验证   /  executor 执行器注册 + MCP 委派            │
└───────────────────────────────────────────────────────────────────┘
```

## 二、一条关键数据流（外部调用一次 `publish`）

```
MCP 客户端 --JSON-RPC--> 协议层 tools/call 分发(name=publish)
      --> 引擎层 FistEngine.publish  校验角色权限(human_steward 唯一权威)
      --> 状态机：新建根任务(待领取)
      --> 存储层 Store 落库 tasks 表(SQLite)
      --> 写审计、回写 JSON-RPC result 给客户端
```

域核心（core/store/engine）与协议层（server）解耦：协议层只做装配与传输，业务正确性全在纯逻辑、可单测的引擎层。

## 三、自驱闭环（系统自己推动自己，M6 文档即实现）

```
审视报告(selfdrive 四件套 memory/reviews)
   │
   ▼
selfdrive_publish_next    解析 "## Next Tasks" 并行发布为独立根任务
   ▼
task_plan_deep            AO 式递归拆解整棵子任务树（可选开启 Omega 强验证）
   ▼
claim --> execute --> submit --> verify（外部判据 run_check / gate 门禁）
   ▼
memory_consolidate        交付物收敛写回 memory/{kind}.md
   ▼
evolve_distill            蒸馏成 [principle] 原则写入 DGM，4-AI 门禁裁决
   ▼（回到审视 → 下一轮）
```

验证不靠"自写自测恒绿"：`run_check` 服务端真实执行命令；`evolve` 评分用注入式可计算函数对接 Omega gate / run_check，**绝不让 LLM 自评**。

## 四、设计要点

1. **纯 MoonBit，零运行时依赖**：无 Python/Rust 包装；JS + Native 双端交叉编译，Windows/Linux 各 208 项测试全绿、跨环境可复现（`moon update && moon run cmd/main` 即用）。
2. **状态机正确性优先**：九态状态机 + 非法迁移拦截（未认领直接 plan/execute 报错）+ 父任务自动上卷，正确性敏感逻辑由强类型保证、易单测。
3. **验证可计算化**：Omega 语料门禁（schema+fingerprint，accuracy<100% 一票否决）与 evolve 注入式评分均不依赖 LLM 自评，杜绝"自己给自己打分"。
4. **跨平台可复现**：SQLite 双后端（JS 走 node:sqlite，Native 走 mizchi/sqlite + `-lsqlite3`），specs/心跳均持久化、跨进程可读；Windows native 并行测试偶发堆损坏的边界已在 README 主动自曝，产品运行时不受影响。
5. **多租户隔离**：`MultiStore` 按 namespace 路由到独立 SQLite 文件 `{data_dir}/{ns}.db`，惰性打开、互不污染。

## 五、快速读懂指引

- 生命周期语义：`README.md` §状态机（九态）
- 70 工具分组：`README.md` §MCP 暴露面（生命周期/查询/DAG/自驱/演化/运维/Omega/调用日志+bug上报）
- 自驱走通实例：`docs/selfdrive-walkthrough.md`
- 评审关注"补齐 MCP 概念门槛"建议从此页分层图入手，再下沉到 `src/` 各包。

*（内容由AI生成，仅供参考）*