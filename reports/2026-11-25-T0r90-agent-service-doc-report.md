# T0r90 · P3 文档（agent-service-skill + USAGE 会话内嵌 worker 节）· 交付报告

- 任务号：`T0r90`（ns `autoplan`，执行身份 `atomcode`）
- 口径来源：`fist-mbt/plan/active/2026-11-25-fist-agent-worker-issue1.md`（P3 条）
- 约束：**只读盘点 / 最小改动**；不动 Marvis 未提交文件面、不 push、不 merge
- 日期：2026-11-25

## 1. 结果摘要

P3 三项现状为 **2 项是缺口（本轮补齐）、1 项不可执行（记缺口）**：

| P3 项 | 本轮动作 | 产出路径 |
|---|---|---|
| `docs/agent-service-skill.md` | **新建**（131 行） | `docs/agent-service-skill.md` |
| USAGE「会话内嵌 worker」节 | **新增** §11.2（33 行） | `USAGE.md`（第 11 节后） |
| `fist help agent` | **部分落地**：`help_cli()` 补两行说明（如实标注未接线） | `cmd/cli/help_topics.mbt` |
| 插件态重生成 | **不适用**：`gen_plugins.py` 不消费 `docs/`、`USAGE.md`、`cmd/cli/*`（逐行核对零命中） | — |

**一句话交付**：把「会话内嵌 worker」这一层从散文读成了可查的文档面，且**如实写明它当前不可用**
——`node dist/fist-mbt.js agent status` 实测 rc=2（`未知子命令: agent`），因为 P0 骨架存在但未接进 CLI。

## 2. 现状盘点证据（本轮实测）

| 检查 | 读数 |
|---|---|
| `docs/agent-service-skill.md` 原是否存在 | **不存在**（glob 零命中） |
| `cmd/cli/agent.mbt` | 748 行，含完整 P0 骨架（锁/三态/一轮/旗标白名单/native 臂）；**untracked**、跨文件引用 **0 处** |
| `cmd/cli/subcmd.mbt` `Subcmd` | `Serve/Version/Demo/Doctor/Upgrade/Help/NoArgs/Unknown` —— **无 `Agent`** |
| `cmd/cli/main.mbt` 分发臂 | 同上，**无 agent 分支** |
| `cmd/cli/moon.pkg` | 已声明 `agent_js.mbt`(js) / `agent_native.mbt`(native+llvm) target 臂（他方 WIP，工作树为 M） |
| `node dist/fist-mbt.js agent status` | `未知子命令: agent`，**rc=2**（产物 banner `v0.3.11 (183 MCP tools)`，构建于 11-17，早于骨架） |
| P1 `--executor` / `{packet}` / `task_packet` | 全仓（src/cmd/scripts/services）**零命中**（T0r87 同结论，本轮复核） |
| 消息池读取 | `cmd/cli/agent.mbt` 对四条已知池路径正则全 `<none>`（T0r89 D3） |
| 插件真源 `plugins/source/` | 只有 `SKILL.md` / `SKILL.commander.md` / `references/`，**无 agent-service-skill** |

## 3. 产出物要点

### 3.1 `docs/agent-service-skill.md`（新建）

六节：① 这一层解决什么问题（三条红线：执行器外置 / server 保持被动 / 不依赖 cron）；
② 三层结构 P0/P1/P2 与各自现状；③ 最小改动面（解缺三处 + 必须同批补行为锁）；
④ 当前真能用的替代路径（注册表 + 常驻网关，已上线实弹）与两条路径分工表；
⑤ 相关落点索引；⑥ 边界声明（身份字段自报不可验证、WSL 无发行版）。

关键判断：**不写成「已交付清单」**，凡未实测的面一律标注来源报告，避免把计划当事实。

### 3.2 `USAGE.md` §11.2 会话内嵌 worker（新增，33 行）

挂在 §11「Agent 服务」之后、§11.1 之后（§12 之前）。内容为可用性红字表 + 设计口径命令面 +
「现在就要长期可调用请用 §11 那条线」的指引。

### 3.3 `cmd/cli/help_topics.mbt` `help_cli()`（+2 行）

```
fist agent       in-session worker: serve/run/status/stop (P0 skeleton,
                 NOT wired into this build yet -> 'agent' is unknown here)
```

⚠️ 该文件工作树版本混入**他方未提交 hunk**（`FIST_VERSION` 0.3.11→0.3.15、工具数 183→188 及分组表）。
按本仓既定做法**只提交自己那两行**：备份工作树全文 → `git checkout -- <file>` 回退 HEAD →
只改目标两行 → 提交后写回备份全文。⇒ 他方 WIP 在工作树原地保留，不被带走也不被覆盖。

## 4. 验证证据（实跑）

| 判据 | 读数 | 结论 |
|---|---|---|
| `node dist/fist-mbt.js agent status` | rc=2，`未知子命令: agent` | 支撑「未接线」结论 |
| `python scripts/check_tools_sync.py` | PASS：server.mbt 注册 197，R8 分组 21 组 ΣN=197 | 绿 |
| `python scripts/check_usage_tool_count.py` | PASS：真源 197；活体 196 × §6 表行 83 行零漂移 | 绿 |
| `moon fmt cmd/cli/help_topics.mbt` | rc=0 | 绿 |
| `python scripts/check_fmt_gate.py` | DEGRADED(2)（BUG-388 工具链缺陷，本机不可测） | 既非红亦非绿，如实记 |
| `python scripts/check_doc_surface.py` | rc=1（14 行 J14/J16 计数面红） | **非本次引入**，见下对照实验 |

**J14 红的归因对照实验**（自证不是我的改动造成）：撤掉我这两行 → 再跑判据 → 两次输出**仅差行号**
（`help_topics.mbt:58` vs `:60`），红行数同为 14。即 HEAD 基线上原样红着，根因是计数搬家
（真源已 197，`ARCHITECTURE.md`/`templates/tool_use_rubric.md`/`docs/agent-map.md`/`deliverable.md`
等仍写 188）属他方在飞 WIP 未收口。

## 5. 缺口与风险

| # | 缺口 / 风险 | 影响 |
|---|---|---|
| G1 | P0 骨架仍未接线（`subcmd.mbt` 无 `Agent`、`main.mbt` 无分发、`agent.mbt` untracked） | 云机器侧拿不到「同一命令」，P2+ 无法开工 |
| G2 | `agent.mbt` 入跟踪面即新增 `.mbt` 面 ⇒ 须同批给行为锁（`subcmd_wbtest.mbt` 现 0 处 agent 引用） | 漏则覆盖判据类门会红 |
| G3 | `dist/fist-mbt.js` 落后于源码（banner v0.3.11 / 183 工具） | 文档所述「未接线」在旧产物上表现一致，但新产物仍不会自动获得 agent |
| G4 | `fist help agent` 只做了一半：`help_cli()` 有说明，但无独立 topic（需改 `list_topics()` 主题面） | 派单第三项只算部分交付，已在产出物与§3.3 如实标注 |
| G5 | J14 计数面红（他方 WIP 未收口） | 与本任务无关，但会随本笔提交一起出现在 CI 读数里，需 owner 知悉归属 |

## 6. 后续建议

1. **另立任务做块①接线**（P0）：`subcmd.mbt` 加 `Agent` + `main.mbt` 加 `run_agent(args)` 透传二级参数
   + 同批补 `subcmd_wbtest.mbt` 的 agent 词法/旗标白盒锁；验收 = `node <新产物> agent status` rc=0、
   `--dry-run --once` 不落盘、双进程抢锁必退。
2. **G4 收口**：把 `fist help agent` 做成真 topic（`run_help` 加 `"agent"` 臂 + `list_topics()` 列名），
   正文复用 `agent_help_text()`。
3. **G5 归属澄清**：J14/J16 计数面红应由正在改工具计数的他方一并收口，避免下一轮被误记成本任务的账。

## 7. 来源

- 计划真源：`fist-mbt/plan/active/2026-11-25-fist-agent-worker-issue1.md`
- 姊妹件：`docs/fist-agent-principle.md`、`reports/2026-11-25-T0r87-executor-writeback-inventory.md`、
  `reports/2026-11-25-T0r89-crossmachine-pool-wiring-report.md`
- 对表件：`cmd/cli/{agent,agent_js,agent_native,main,subcmd,help_topics}.mbt`、`cmd/cli/moon.pkg`
- 实跑：`node dist/fist-mbt.js agent status`、`python scripts/check_tools_sync.py`、
  `python scripts/check_usage_tool_count.py`、`moon fmt cmd/cli/help_topics.mbt`、
  `python scripts/check_doc_surface.py`（含撤改对照）、`python scripts/check_fmt_gate.py`
- 产出：`docs/agent-service-skill.md`、`USAGE.md` §11.2、`cmd/cli/help_topics.mbt`
- 备注：`memory/2026-11-25.md` 当日日志本地追加（`.gitignore:162` 忽略，不入库）
