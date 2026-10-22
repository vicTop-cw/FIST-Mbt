---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_66bf66e1c93c11f18b7f525400393706
    ReservedCode1: DnNuARyZEb0AZnuzpq8P5HzklqVSZJLlOlWH6RC1uJzUR4eiKK6W57on59Atiz2bQNjkJU8528sBN9e7l8Waktoc3cR49ImETCD9aNmxNmvVs3Y9aH14RhAR5aU3mC24HNB0E4E74rwrFQIbva0fc4iQdN8lGtwqhtDlR2P5KiMAMrUbLaUs4k+Hqic=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f2a11add43fbf12a546606fb2b962ab_66bf66e1c93c11f18b7f525400393706
    ReservedCode2: DnNuARyZEb0AZnuzpq8P5HzklqVSZJLlOlWH6RC1uJzUR4eiKK6W57on59Atiz2bQNjkJU8528sBN9e7l8Waktoc3cR49ImETCD9aNmxNmvVs3Y9aH14RhAR5aU3mC24HNB0E4E74rwrFQIbva0fc4iQdN8lGtwqhtDlR2P5KiMAMrUbLaUs4k+Hqic=
---

# FIST-Mbt 后续计划（2026-10-16）

> 状态说明：本文是「往后靠」项的占位计划，不排期、不阻塞当前 0.3.8 主线。
> 执行顺序按用户口述优先级：跨机器发布/查看任务在前，文件夹监控触发器在后（均非紧急）。

---

## 一、跨机器发布任务 / 查看任务（黑盒、非实时）【往后靠】

### 1.1 目标与约束

- 目标：在机器 B 上能向机器 A 的 FIST-Mbt 任务库**发布新任务**，并能**查看任务状态/结果**。
- 硬约束：
  - **不需要实时**：接受分钟级延迟，不做 WebSocket / 长连接 / 实时推送。
  - **黑盒**：机器间只交换任务数据（文本/文件），不暴露内部实现，不要求运行环境一致。
- 现状基础：`scripts/fist-mbt-http.py` 已提供 `GET /tools`、`POST /tools/{name}/call`，单机 127.0.0.1:3100。

### 1.2 方案对比

| 方案 | 做法 | 改动量 | 延迟 | 适合 |
|---|---|---|---|---|
| A. 共享后端库 | SQLite 换远程库（Postgres/网络盘），多机桥连同一库 | 中 | 秒级 | 同内网、多机常驻 |
| B. 快照文件同步 | 任务库定期导出 JSONL 快照；发布=写快照、查看=读快照；git/网盘/rsync 同步 | 低 | 分钟级 | 完全黑盒、机器可离线 |
| C. HTTP 桥暴露 + token | 3100 桥绑定 LAN IP + 简单 token；机器 B 直接 POST/GET | 最低 | 秒级 | 只发布+查看、同内网 |

### 1.3 推荐路径

1. **先做 C**（最小改动，半天内）：
   - `fist-mbt-http.py` 增加 `--bind <ip>` 与 `--token <secret>`（请求头校验）；
   - 机器 B 用任意 HTTP 客户端调用 `tools/task_create/call`（发布）、`tools/list/call`（查看）。
2. **再按需做 B**（完全黑盒形态）：
   - 新增 `export_snapshot` / `import_snapshot` 工具，导出任务库为 JSONL；
   - 机器 B 拉取快照文件 → 本地只读查看；发布 = 把新任务写入待导入 JSONL → 机器 A 定时导入。
3. A 仅在需要"多机同时活跃操作同一任务库"时启用，当前无此诉求。

### 1.4 里程碑

- M1：桥支持 bind + token（含鉴权失败的 401 语义）。
- M2：机器 B 通过 HTTP 发布任务成功 + 查看状态成功（黑盒验收：只发 JSON，不感知实现）。
- M3（可选）：快照导入导出工具 + 定时同步脚本。

---

## 二、文件夹监控触发器（事件驱动型）【往后靠】

### 2.1 背景

- 用户提及"上次弄过 RX-MBT 触发器"，方向是**文件夹变化 → 触发 FIST-Mbt 任务**。
- 现有基础：
  - `src/ops/ops_watchdog.mbt`：定时看门狗（外部 cron 每分钟 tick），已有元提示词文档命名规则 `yyyyMMdd.HH.mm.ss.md`（`is_meta_prompt_name`）。
  - `.mooncakes/moonbitlang/async/src/fs/watch*.mbt`：MoonBit async 库自带跨平台 fs watch（inotify/kqueue/Windows）。
  - 历史报告：`reports/2026-09-17-watchdog-cron-plan.md`、`2026-09-20-pipeline-watchdog-state-machine.md`。
- 待澄清：RX-MBT 触发器的具体形态（轮询目录出现新 md？还是 fs 事件？），执行前找用户确认细节，避免重复造。

### 2.2 目标

- 监控指定文件夹（如元提示词收件箱目录），**新文件出现 / 内容变化 → 自动创建/推进 FIST-Mbt 任务**。
- 事件驱动，替代"外部 cron 每分钟 tick"或作为其补充。

### 2.3 方案要点

- **轮询 vs 事件**：
  - 轮询：每 N 秒扫目录 diff（简单、跨平台稳，复用现有 tick 骨架）——优先。
  - 事件：Windows `ReadDirectoryChangesW` / inotify（低延迟，但平台差异 + 生命周期管理成本高）。
- **触发动作**：新 `.md`（符合 `yyyyMMdd.HH.mm.ss.md` 命名）→ 解析内容 → `task_create` 写入对应 namespace；或按既有 pipeline 推进下一轮。
- **幂等**：以文件名+哈希记录已处理集合，防止重复触发（写 `processed.jsonl` 或复用任务库字段）。

### 2.4 里程碑

- M1：目录轮询 diff + 新文件检测（测试目录造 3 个文件验证）。
- M2：检测 → 建任务打通（验收：投递 md → 任务库出现对应任务）。
- M3（可选）：切换到 fs 事件实现。

---

## 三、挂靠待办（非本次计划主体）

- 本地发布版同步免费路由：仓库 `dist/fist-mbt.js`（含 OFM）→ `C:\Users\victo\AppData\Local\FIST-Mbt\fist-mbt.js`。
- Web 任务可视化面板发布：改 `build_release.ps1` 纳入 `web/` + 统一版本号。
- 41 条待领取叶任务：依赖门拦截中，等父任务完成或执行器拉活，暂不处理。

---

## 四、执行前置条件

- 二（文件夹监控）开工前，需用户补充 RX-MBT 触发器的细节或确认采用轮询方案。
- 一（跨机器）开工前，确认机器 B 的环境（是否 Windows / 是否有 Python）与内网可达性。
*（内容由AI生成，仅供参考）*
