# T0r69 · 消息池归档动作（成功 → processed/，重试耗尽 → .failed/）

- 日期：2026-11-25
- 执行身份：atomcode（FIST 指挥官模式下的执行子代理）
- 任务编号：T0r69 ｜ namespace：autoplan
- 真源条目：`fist-mbt/plan/draft/2026-11-24-msg-loop-closed.md:50`
  「归档动作：转发成功后消息移 processed/；失败重试 3 次后移 .failed/」
- 基线：`reports/2026-11-25-T0r88-msg-pool-atomic-rename-report.md`

---

## 一、结果摘要

**产出物（唯一新增件）**：`E:/IDEProjects/AI/FIST-Mbt/scripts/_msg_archive.py`

一条命令完成「读 inbox → 转发 → 按结果归档」：

```
python scripts/_msg_archive.py --msg-dir .fist-mbt/msg            # 处理 inbox 全部
python scripts/_msg_archive.py --msg-dir .fist-mbt/msg --file x.json
python scripts/_msg_archive.py --msg-dir .fist-mbt/msg --dry-run # 照算不移动
python scripts/_msg_archive.py --selftest                         # 离线自证
```

| 结果 | 落位 | 语义 |
|---|---|---|
| 转发成功（HTTP 2xx 且无 JSON-RPC error） | `processed/` | 防重触发 |
| 首次 + 3 次重试全失败 | `.failed/` | 保留原文可人工回溯 |
| 消息无 `endpoint` 且未给 `--endpoint` | **原地不动** | 拒绝出数（rc=1），不猜目标 |

回执逐条 JSON 单行（`file/archived/attempts/verdict/detail/endpoint`），
`.failed` 时进程 rc=1；`--selftest` 20 格全绿 rc=0；未知旗标 rc=2。

**实测证据（端到端临时池）**：`inbox` 两条不可达端点消息 → `attempts: 4`、
`verdict: "failed"`、落 `.failed/`、`inbox` 清空；随后 `--dry-run` 回
`[msg_archive] inbox 空` rc=0（幂等）。

---

## 二、关键发现：真源声称的复用前提，有三条不成立

真源 §分工判定（`:44`）称 mcp-watcher「无需加核心功能，只加规则配置」，
依据是「fs watch + webhook action（带 backoff）+ 归档移动全部现成」。
逐条实测（只读 shell 读兄弟仓 `E:/IDEProjects/AI/mcp-watcher`，HEAD `b1773aa`）：

| # | 真源假设 | 实测事实 | 证据 |
|---|---|---|---|
| G1 | webhook action「带 backoff」⇒ 可完成重试 | v1 **明确无重试循环**（红线注释：「本函数只计算调度，不真正 sleep/重试…是否应用由上层决定」） | `action/webhook.mbt:60-80` |
| G2 | trash/move「现成」⇒ 归档可直接用 | `trash_native.mbt` 是 **native 专属**（依赖 `@fs.mkdir/rename`）；`trash_stub.mbt` 门控 `[js, wasm]` 且**恒返 Err** | `action/trash_native.mbt:34-55`、`action/trash_stub.mbt` |
| G3 | watcher 运行态有原生 fs 能力 | 守护进程跑的是 **js 产物** `node main.js`，故生产路径上 trash **必走 stub 降级** | `scripts/daemon/watch_daemon.ps1` |

补充：动作分发表的 kind 只有 `command` / `mcp_tool_call` / `webhook` / `internal`
（`action/action.mbt:1150-1184`），**没有 archive/move 类**；`internal` 注册表仅
`reload_config/pause_watch/resume_watch/log_event` 四 op（`scheduler/scheduler.mbt:632`）。

**结论**：「归档动作」在当前树上是**不存在的一条可执行路径**。而 watcher 的
`command` 动作可跑任意 argv ⇒ **本脚本即那条路径**：watcher 侧只需按真源 `:49`
补一条规则配置（`kind: command` + argv 指向 `_msg_archive.py`），**零源码改动**。
⇒ 真源「只加规则配置」的**结论方向正确**，但其**理由（三能力现成）错误**；
落地形态从「改 watcher」修正为「新增 fist-mbt 侧归档器 + watcher 一条 command 规则」。

---

## 三、复用口径（不新造第二套词表/算法）

| 复用对象 | 镜像方式 |
|---|---|
| `webhook_backoff_delay_ms` | 阶梯**逐字对齐** base=500ms / cap=8000ms / 每重试翻倍 / 封顶 / attempt<0 归零 / 超上限按上限（`webhook.mbt:21-23,65-80`） |
| `trash_file` | 语义**镜像**其 `mkdir(recursive, allow_exist)` + `rename(replace=true)`：先建目录再原子改名；跨卷 `os.replace` 抛错即退化 `shutil.move`（copy+unlink，**不原子**——T0r88 已裁决的边界，不假装原子） |
| 分区名 | `inbox` / `processed` / `.failed`，与 `scripts/git_pool_bridge.py:38` 及 draft `:26` 一致 |

同名冲突：按内容 sha256 前 8 位去重（`d.json` → `d.<sha8>.json`），**不覆盖**——
对齐 trash 分桶「可按桶还原」的可恢复精神（代价：去重而非时间戳桶，桶级整体还原
需另做索引；本件选择 sha 去重是因为归档件要能被按内容核对）。

**口径分歧显式标注**：任务文本与 draft 写 `.failed/`（带点号），active 计划
`fist-mbt/plan/active/2026-11-25-fist-agent-worker-issue1.md:25` 写 `failed`（无点号），
T0r88 建议四态 `processing/`。本件**以本任务文本为准**（`.failed`），
不擅自统一；四态是否演进属另一单。

---

## 四、任务分配记录

FIST 指挥官模式分流：本件为**中任务**（单文件新增 + 自检 + 端到端验证），
由执行子代理一次做完，未派生子代理（无可并行的独立子工作）。

| 阶段 | 手段 | 结果 |
|---|---|---|
| 现状盘点 | grep/glob/read + 只读 shell 读兄弟仓 | G1–G3 三条缺口定性 |
| 落点决策 | 读 `run_guards.py` 宇宙/豁免实现 + `check_scripts_index.py` 扫描面 | 定 `_` 前缀豁免，避开他方 dirty 面 |
| 实现 | `write_file` → `edit_file` 修用例 | 441 行单文件 |
| 自检 | `--selftest` | 20 格 PASS（含 2 处变异对照） |
| 参数面 | `--definitely-not-real` | rc=2 合格 |
| 端到端 | 临时池 + 不可达端点 | 落 `.failed`、inbox 清空、dry-run 幂等 |
| 登记面对表 | `check_battery_count_doc` / `check_scripts_index` 实跑 | 未被点名（详见 §六） |

---

## 五、资源消耗

- 新增 1 份 Python 脚本（约 18.7 KB / 441 行），**未新增依赖**（仅标准库
  `argparse/hashlib/io/json/os/shutil/sys/tempfile/urllib`）。
- **未跑 MoonBit 全量测试**：本轮改动全在 `scripts/` 面，无 `.mbt` 改动 ⇒
  按 AGENTS.md「纯脚本面不必空转全量」处理。
- 未联网、未触碰真消息池（`.fist-mbt/msg` 本机不存在）、未 push/release。

---

## 六、遗留风险与后续建议

1. **红面归属（非本件引入，已实证排除）**：`check_battery_count_doc` rc=2、
   `check_scripts_index` rc=1，均由**他方未跟踪件**造成——
   `pack_exe_to_md.py` / `web_bridge.py` / `blackbox/e2e_web_agent_p1.py`；
   实测 `_msg_archive.py` 在两把判据的扫描面上均未被点名（`_` 前缀天然豁免：
   `run_guards.UNIVERSE_EXCLUDE_RE` 的 `^_`、`check_scripts_index.formal_scripts()`
   的 `name.startswith("_")` 跳过）。**处置**：归各自任务单，本单不动他方 WIP。
2. **watcher 接线仍未做**：本机 `.mcp-watch.json` 零 `msg/inbox|processed|.failed`
   规则，且 EP-03 四层死链未修（见 memory）⇒ 归档器当前**无生产调用方**。
   建议下一单：watcher 侧补一条 `kind: command` 规则（或修 EP-03 后由 watcher
   轮询触发），把「事件 → 转发 → 归档」真正闭环。
3. **失败件的再处理路径缺失**：`.failed/` 只进不出。建议补 `requeue` 子命令
   （`.failed/` → `inbox/`，带次数上限防抖动）。
4. **退避总耗时的口径**：3 次重试的等待为 1000+2000+4000 = 7000ms（attempt 1..3），
   叠加 HTTP 超时可能使单条处理达数十秒；批量场景建议并发或降 retries。
5. **`.failed` 目录名分歧**需在四态演进单里一次性统一（本单不擅自改）。

---

## 七、超额内容（超出任务文本的部分，如实列出）

- 额外提供 `--dry-run`（任务未要求，用于验证幂等与「不猜目标」）；
- 额外提供同名 sha 去重（任务未提，源于复用 trash「不覆盖」语义）；
- 额外提供 `--timeout` / `--retries` 可调（默认值即任务口径）；
- 未做：`requeue`、跨机池搬运、watcher 规则文件改动（超出「最小改动」授权，
  且后者属另一单）。

---

## 八、来源

- `fist-mbt/plan/draft/2026-11-24-msg-loop-closed.md`（拓扑 `:17-19`、分区 `:26`、
  消息格式 `:33-38`、本条目 `:50`、watcher 规则 `:49`、分工判定 `:44`）
- `fist-mbt/plan/active/2026-11-25-fist-agent-worker-issue1.md:25`
- `reports/2026-11-25-T0r88-msg-pool-atomic-rename-report.md`
- `scripts/git_pool_bridge.py:38`（`MSG_SUBDIRS`）
- `scripts/run_guards.py`（`UNIVERSE_EXCLUDE_RE:1010`、`EXEMPT_RULES:1023-1066`
  的 `("_", ...)`、`classify:1305-1325`、`_tracked_scripts:1180`、`non_gate_reason:912`）
- `scripts/check_scripts_index.py:170-185`（`formal_scripts` 的 `_` 跳过）
- `scripts/check_battery_count_doc.py`（对表口径与自拒档）
- `E:/IDEProjects/AI/mcp-watcher`（只读 shell）：`action/webhook.mbt`、
  `action/trash_native.mbt`、`action/trash_stub.mbt`、`action/moon.pkg`、
  `action/action.mbt:1150-1184`、`scheduler/scheduler.mbt:632`、
  `scripts/daemon/watch_daemon.ps1`
- `.fist-mbt/data/autoplan.db`（`tasks` 表 `id='T0r69'` 任务卡）
