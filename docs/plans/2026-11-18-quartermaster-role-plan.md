# PLAN · 军需官（Quartermaster）角色——AI 开发仓整理自治（2026-11-18）

> - 日期：2026-11-18
> - 状态：计划（owner 2026-11-18 指令：「拟定个角色专门做整理 AI 开发仓的任务……写上并添加默认的规则」）
> - 定位：军衔体系（`docs/2026-10-12-fist-mbt-web-dashboard-plan.md` §8）展示层新军职；
>   执行底座 = mcp-watcher（声明式规则自治），本角色负责审查规则、验收结果、向 owner 报清单。
>   上游依赖：`../rx-mbt/PLAN-2026-11-18-gap-audit.md` R1、`../mcp-watcher/PLAN-ep01-actions.md` EP-01c。

## 一、角色定义

| 项 | 内容 |
|---|---|
| 军职名 | **军需官**（Quartermaster） |
| 系属 | 参谋线（挂靠 Leader 体系，与 §8.1 参谋六军职并列的第七席） |
| 职责 | 专管 AI 开发仓（`E:/IDEProjects/AI` 下各仓）的产物生命周期治理：临时产物清理、过期报告归档、WIP 车道巡查、发布遗留回收 |
| 与后勤参谋（Allocator）的分界 | 后勤管**资源分配**；军需管**产物生命周期**（TTL/回收站/归档） |
| 协议层 | 不感知——展示层标签，协议与存储零改动（军衔体系铁律） |

## 二、工具面（新增 1 个 + 复用 3 个）

| 工具 | 类型 | 用途 |
|------|------|------|
| `quartermaster_sweep` | 新增 | 按规则扫候选清单：入参 `rules`(JSON，同 mcp-watcher schema §4 condition) 或 `preset`(默认规则集)；**只列不删**，返回 {candidates, est_bytes, rules_hit} |
| `issue_scan` | 复用 | 扫仓内残留/占位 |
| `commissar_send` | 复用 | 向各 agent 命名空间发整理指令（军需→士兵的派单） |
| `saga_register` / `saga_repair` | 复用 | 整理动作全部登记可补偿；误删可 LIFO 回滚 |

## 三、安全边界（铁律）

1. **删除类动作永不直行**：默认规则只产出候选清单 + trash/归档；任何永久删除须经 owner 或白名单闸门。
2. **豁免清单**：owner/专门轮保留物（如 `dist/fist-mbt.js` 遗留、iter-r192 车道 WIP、外来账冻结区）不整理——规则里用 `exclude` 硬排除。
3. **军需官只审不跑**：规则文件由 AI/人写，自动执行全交 mcp-watcher daemon；军需官对结果做验收（对照 TTL 事件与 trash 目录）。

## 四、默认规则（`quartermaster-default-rules.json`）

配套默认规则集见同目录 `2026-11-18-quartermaster-default-rules.json`
（按 mcp-watcher schema v1.0 编写，五条：临时产物 TTL、oversized 日志归档、巡检报告归档、
WAL/临时库超龄告警、empty-dir 清理），落到各 AI 仓根 `.mcp-watch.json` 即生效；
`watch_id` 按仓自拟（如 `fist-mbt-quartermaster`），`allowed_programs` 保持空 = 不执行任何外部命令。

## 五、落地步骤

1. fist-mbt：实现 `quartermaster_sweep`（纯计算 + 文件系统只读，js 轨先行），注册进 server.mbt（工具数 183→184），投影同步（J4/J7 守卫）。
2. mcp-watcher：EP-01c 落地后，军需官默认规则里的 `internal.log_event` 升级为 `mcp_tool_call → fist-mbt publish`（往 `quartermaster` 命名空间发整理任务，走完整 FIST 生命周期）。
3. rx-mbt：R1 native crypto 落地后，敏感产物归档规则启用 `encrypt` 动作。
4. 验收：军需官一轮完整闭环 = sweep 出清单 → commissar 派单 → 执行归档/trash → saga 可补偿 → verify 回执 status=已完成。
