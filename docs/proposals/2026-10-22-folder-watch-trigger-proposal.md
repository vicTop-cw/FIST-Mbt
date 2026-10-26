# 提案 — 文件夹监控触发器（事件驱动型）

> **文件命名**：`2026-10-22-folder-watch-trigger-proposal.md`
> **放置目录**：`docs/proposals/`
> **状态**：`draft`
> **替代**：`docs/archive/2026-10-16-future-plan.md` §二（内容整合进 `improvement-plan-20261010.md` §7）
> **来源**：用户提及「RX-MBT 触发器」历史 + `src/ops/ops_watchdog.mbt` 已有 tick 骨架

---

## 1. 背景与问题

FIST-Mbt 当前靠外部 cron 每分钟 tick 驱动 pipeline。用户历史提及「RX-MBT 触发器」——文件夹变化 → 触发任务。现有 `ops_watchdog.mbt` 是定时 tick，不是事件驱动；`moonbitlang/async/fs` 有跨平台 watch 能力但未接入。

## 2. 方案对比

| 方案 | 做法 | 改动量 | 适合 | 不适合 |
|---|---|---|---|---|
| A. 轮询 diff | 每 N 秒扫目录 diff，新 md 文件出现 → 触发任务 | 低 | 跨平台稳、复用 tick 骨架 | 延迟 N 秒 |
| B. fs 事件 | `ReadDirectoryChangesW` / inotify 实时回调 | 中 | 低延迟、实时响应 | 平台差异大、生命周期管理成本高 |
| C. 混合 | 轮询兜底 + fs 事件优先（事件失败时降级轮询） | 高 | 兼顾实时与可靠 | 实现复杂 |

## 3. 推荐路径

先做 A（轮询优先，简单可靠）→ 按需做 B（fs 事件）→ C 作为远期选项。

## 4. 四态对齐

| cl | 判据 | 本功能动作 |
|---|---|---|
| cl1 | MCP 工具存在 | 新增 `folder_watch_tick` 工具（轮询 diff + 新文件检测）或扩展 `watchdog_tick` |
| cl2 | CLI 封装 | `python scripts/fist.py call folder_watch_tick ...` |
| cl3 | skill 文档 | `docs/folder-watch-skill.md` |
| cl4 | 测试 | 测试目录造 3 个 md 文件验证检测 → 建任务 |
| cl5 | L4 证据 | `output_validate` 验投递 md → 任务库出现对应任务 |
| cl6 | 文档同步 | README 追加文件夹监控章节 |
| cl7 | 插件投影 | 无新增插件文件 |

## 5. 待用户拍板的决策点

| 决策点 | 选项 | 建议 |
|---|---|---|
| D1 · 方案选型 | A) 轮询 B) fs 事件 C) 混合 | 默认 A 起步 |
| D2 · 与 watchdog_tick 关系 | A) 扩展现有工具 B) 新增独立工具 | 默认 B（职责分离） |
| D3 · 元提示词命名规则 | A) 复用 `yyyyMMdd.HH.mm.ss.md` B) 新规则 | 默认 A（与 pipeline 兼容） |

## 6. 落地顺序

| 阶段 | 内容 | 涉及文件 | 依赖 | 交付 |
|---|---|---|---|---|
| P0 | 轮询 diff + 新文件检测 | `src/ops/ops_folder_watch.mbt`（新）或扩展 `ops_watchdog.mbt` | 无 | 检测到新 md 文件 |
| P1 | 检测 → 建任务打通 | `src/server/*`（注册工具） | P0 | 投递 md → 任务库出现对应任务 |
| P2（可选） | fs 事件升级 | `.mooncakes/moonbitlang/async/fs` 集成 | P1 | 实时响应 |

## 7. 已知边界与风险

- 轮询间隔 N 秒：N 太小耗资源，N 太大延迟高。建议默认 30s，可调
- fs 事件在 Windows 上 `ReadDirectoryChangesW` 需 FFI 绑定，当前无现成 MoonBit 绑定
- 幂等：同一文件多次触发需去重（文件名+哈希）
- 与现有 `watchdog_tick` 定时任务不冲突（不同命名空间）
- RX-MBT 触发器具体形态待用户补充细节

## 8. 参考

- `improvement-plan-20261010.md` §7（方向六）
- `docs/archive/2026-10-16-future-plan.md` §二（已归档）
- `src/ops/ops_watchdog.mbt`（现有 tick 骨架）
- `src/ops/ops_pipeline_tick.mbt`（pipeline 唤醒一拍）
