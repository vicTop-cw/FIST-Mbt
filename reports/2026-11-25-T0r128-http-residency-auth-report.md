# T0r128 · HTTP 服务常驻与鉴权（只读盘点 + 最小改动面）

- **执行身份**：workbuddy
- **日期**：2026-11-25
- **计划真源**：`fist-mbt/plan/active/2026-11-25-fist-auto-model.md` 工作项 **五：HTTP 服务常驻与鉴权**（裁决 A1-A4 见该文件「裁决项」节）
- **约束**：只读盘点 / 最小改动；产出物写明路径
- **本轮实际改动面**：**零代码改动**。唯一新增产物 = 本报告
  `reports/2026-11-25-T0r128-http-residency-auth-report.md`

---

## 一、结果摘要（结论）

1. **真源只有一个**：HTTP 常驻网关 = `scripts/fist_gateway.py`（被 git 跟踪，1337 行 /
   72,202 B，mtime 2026-11-25 20:41）。它同时承担「HTTP 面 + 子进程托管 + 认证 + 限流 +
   审计 + 心跳回写 + 注册表落库」。同目录另有一份**未跟踪**的 `scripts/fist-gateway.py`
   （他方 WIP，51,135 B），**不是**真源，本轮未读改、未据其下结论。
2. **鉴权是两层，别混**：
   - **传输/接入层**（网关自身）：`X-API-Key`（或 `Authorization: Bearer`）→ sha256 比对；
     本机档（127.0.0.1/localhost）在未给 key 时免认证，`lan/global` 档缺 key **启动期直接
     `sys.exit`**。**明文 key 从不落盘**，只存哈希；`--api-key-file` 从文件首行读。
   - **引擎/ACL 层**（MoonBit 侧）：`FIST_AUTH_MODE` 三档 `off`/`soft`/`strict`
     （真源 `src/engine/auth_mode.mbt`），当前默认 **`soft`**（2026-11-13 flip），
     与安装侧 `%LOCALAPPDATA%\FIST-Mbt\serve-launcher.cjs` 的 `DEFAULT_AUTH_MODE = 'soft'`
     **逐字一致**（已核）。
3. **实测鉴权面成立**：`/health` 免认证可读；`POST /mcp` 裸头 401、错 key 401、
   正确 key（两种头形态）200。
4. **实测发现一处「文档 ≠ 实现」**：文档口径写「per-key 限流默认 60/min，**超限 429**」
   （`docs/fist-agent-principle.md:63`，另见 `docs/web-model-agent-deploy-guide.md:146`），
   而实现里限流分支**返回的是 401**，且落审计事件 `auth_fail`（与「key 不对」同一张脸）。
   连发 66 发实测：**59 × 200 + 7 × 401，无一个 429**。⇒ 限流真的生效了（第 61 发起被拦），
   但**归因与状态码都不可分辨**。
5. **常驻机制：只有一层，没有 OS 级守护。**
   - 现有 9 个网关进程各自常驻（`fist_gateway.py` 主体 + spawn 出的 `node ... cli.js serve`
     子进程，父进程 50588 → 子进程 51152 实证）。
   - `scripts/gateway_guardian.py` 是**按需手动**的只读巡检/按需拉起器（`--status` /
     `--once` / `--force-restart` / `--prune-orphan`），**当前没有任何常驻入口**：
     全量计划任务扫描无 guardian 相关任务（仅 `FIST-WatchDaemon`(mcp-watcher) /
     `FIST-Mbt-ExploreWatchdog` / `FIST-Mbt-PoliticalCommissar`），无 guardian 进程在跑，
     其 state 文件末条时间停在 2026-11-25T18:54:02Z，lock 文件不存在。
   - ⇒ **「重启后自恢复」这条验收目前无机制承载**（详见 §四 缺口 1）。
6. **fist-auto 端点尚未落地为注册服务**：裁决 A1 定「独立新端口 18651」，实测 18651/18652/
   18653 被 **OFM-1/OFM-2/OFM-3** 占用（在监听，但**不在**注册表 `agent_service` 真源内，
   故被 guardian 判 `[STALE]`）；`temp/gateway-fist-auto.log` 存在过（12:42 有 `real_completion`
   记录）但对应进程已不在 `--status` 的陈旧清单里。注册表 `.fist-mbt/data/agent-services.db`
   表 `agent_service` 共 10 行，**无 fist-auto 行**。

---

## 二、证据（全部为本轮实测，含命令与读数）

### 2.1 接入层鉴权（对 18646 实弹）

```
$ curl /health                     → {"service_id":"svc-workbuddy","alive":true,
                                      "listen_addr":"127.0.0.1:18646","pid":50588}
$ POST /mcp  无 key                → 401
$ POST /mcp  X-API-Key: deadbeef   → 401
$ POST /mcp  X-API-Key: <真 key>   → 200
$ POST /mcp  Authorization: Bearer <真 key> → 200
```

限流（默认 `--rate-limit 60`，连发 66 发 `tools/list`）：

```
200 × 59 ，401 × 7        （无一 429）
审计尾行：{"ts":"2026-11-25T12:40:59Z","service_id":"svc-workbuddy",
          "event":"auth_fail","ip":"127.0.0.1"}
```

审计面全量事件分布（`temp/gateway-svc-workbuddy.log`，11,066 B）：

| event | 次数 |
|---|---|
| `mcp_call` | 64 |
| `auth_fail` | 23 |
| `patrol_trigger` | 3 |
| `chat_completions` | 2 |

（另有 `model_injected` / `real_completion` 两事件类型在代码里接线，见 `fist_gateway.py:940` /
`:1058`；本轮该日志内未见。）

### 2.2 鉴权实现原文定位

| 面 | 位置 |
|---|---|
| key 指纹提取（`X-API-Key` 优先，退回 `Bearer`） | `scripts/fist_gateway.py:480-487` |
| 认证 + 限流同一函数 `auth_ok()` | `scripts/fist_gateway.py:489-505` |
| 暴露档判定 `args_host_is_local()`（仅 127.0.0.1/localhost） | `scripts/fist_gateway.py:1235-1237` |
| `lan_binding_requires_key()` | `scripts/fist_gateway.py:493-497` |
| 明文只存哈希 | `scripts/fist_gateway.py:405-417` |
| `--api-key-file` 首行读取 | `scripts/fist_gateway.py:409-412` |
| `--api-key` / `--api-key-file` / `--rate-limit` 参数面 | `scripts/fist_gateway.py:1293-1299` |
| POST 路由的认证闸（401 分支 + `auth_fail` 审计） | `scripts/fist_gateway.py:886-902` |
| 模型路由注入审计 | `scripts/fist_gateway.py:940` |
| 真补全审计 | `scripts/fist_gateway.py:1058` |
| 引擎层三档模式唯一 env 读取点 | `src/engine/auth_mode.mbt`（`auth_mode()`，读一次缓存；非法值回退 `soft`） |
| 安装侧默认档 | `%LOCALAPPDATA%\FIST-Mbt\serve-launcher.cjs` `DEFAULT_AUTH_MODE='soft'` + `authEnv()` |

`auth_ok()` 的关键形状（**限流失败与 key 不匹配走同一个 `return False`**）：

```python
fp = self._key_fingerprint(headers)
if fp != self.api_key_hash:
    return False
...
if len(dq) >= self.rate_limit:
    return False          # ← 调用方拿到的同样是 401
```

### 2.3 常驻面实测

```
$ python scripts/gateway_guardian.py --status          rc=0
[ROW] 18640 svc-atomcode   ALIVE pid=10324  实例=1 reg=ok
[ROW] 18641 svc-codearts   ALIVE pid=9144   实例=1 reg=ok
[ROW] 18643 svc-freebuff   ALIVE pid=48764  实例=1 reg=ok
[ROW] 18644 svc-marvis     ALIVE pid=33436  实例=1 reg=ok
[ROW] 18645 svc-webai      ALIVE pid=41860  实例=1 reg=ok
[ROW] 18646 svc-workbuddy  ALIVE pid=50588  实例=1 reg=ok
[ROW] 18647 svc-autoclaw   ALIVE pid=23680  实例=1 reg=ok
[ROW] 18649 svc-codeforce  ALIVE pid=4740   实例=1 reg=ok
[ROW] 18650 svc-xiaoquan   ALIVE pid=19596  实例=1 reg=ok
[SUM] 9/9 活体
[STALE] 18651 OFM-1 / [STALE] 18652 OFM-2 / [STALE] 18653 OFM-3

$ python scripts/gateway_guardian.py --selftest       rc=0
SELFTEST OK: 53 格（B×2/C×7/G×2/L×12/M×10/N×3/R×8/S×5/T×4）
```

- 端口真源已是**注册表现实推导**（T0r103 已闭环，本轮复核仍生效）；`[STALE]` 块的语义
  见 `gateway_guardian.py:539-557`（复用 `find_orphan_gateway_ports`，只点名、**不改退出码**）。
- 无常驻守护的实证：
  - `Get-CimInstance Win32_Process | ? CommandLine like '*guardian*'` → 零命中；
  - 全量 `Get-ScheduledTask` 按动作命令行 grep `*guardian*` → 零命中；
  - `.fist-mbt/data/gateway-guardian.state.json` 末条 2026-11-25T18:54:02Z（早于本轮）；
    `.fist-mbt/data/gateway-guardian.lock` **不存在**。
- 进程树实证：网关 50588（`python scripts/fist_gateway.py --service-id svc-workbuddy ...`）
  有子进程 51152（`node E:\...\cmd\cli\cli.js serve`）⇒ 「网关托管 stdio MCP 子进程」成立。
- 监听面实扫（18600–18700）：`0.0.0.0` = 18640/41/43/44/45/49；`127.0.0.1` =
  18646/47/50/51/52/53/54。

### 2.4 注册表真源（`.fist-mbt/data/agent-services.db` 表 `agent_service`，10 行）

| service_id | status | listen_addr | session_token | heartbeat |
|---|---|---|---|---|
| svc-agent | **stopped** | 0.0.0.0:18649 | set | 11:27:21Z |
| svc-atomcode | running | 0.0.0.0:18640 | set | 12:45:22Z |
| svc-autoclaw | running | 127.0.0.1:18647 | set | 12:45:15Z |
| svc-codearts | running | 0.0.0.0:18641 | set | 12:45:24Z |
| svc-codeforce | running | 0.0.0.0:18649 | set | 12:45:20Z |
| svc-freebuff | running | 0.0.0.0:18643 | set | 12:45:24Z |
| svc-marvis | running | 0.0.0.0:18644 | set | 12:45:23Z |
| svc-webai | running | 0.0.0.0:18645 | set | 12:45:24Z |
| svc-workbuddy | running | 127.0.0.1:18646 | set | 12:44:42Z |
| svc-xiaoquan | running | 127.0.0.1:18650 | set | 12:45:35Z |

注：`svc-agent` 为脏行（`status=stopped` 却占 18649，与 running 的 svc-codeforce 同端口），
端口真源靠 `status='running'` 过滤掉它——与 T0r103 的推导口径一致。

### 2.5 run_check 在本实例的失能读数（**重要排障证据**）

```
18646 (svc-workbuddy): run_check {cmd:"python", args:["scripts/gateway_guardian.py","--selftest"]}
  → {"ok":true,"check_id":"check:T0r128:r1","status":"failed",
     "stdout_tail":"","stderr_tail":""}
  specs.content = {"ok":false,"code":1,"error":"exit code 1","stdout":"","stderr":""}
  —— r1/r2/r3/r4 四发全 failed（含 --version、显式 workdir:"." 各变体）
18641 (svc-codearts) : 同一 cmd/args → status="passed", stdout_tail="Python 3.13.14\r\n"
18640 (svc-atomcode) : 同一 cmd/args → status="passed", stdout_tail="Python 3.13.14\r\n"
```

⇒ 这是 **18646 单个实例的子进程调度层失能**，不是仓库缺陷、也不是命令白名单问题；
同仓其他实例同命令正常。完整输出仍在 `specs.content` 可复核。本轮**不推测根因**
（无该实例 server.log 的取证），只登记事实与影响。

### 2.6 接力棒读数

- `submit` schema 实测（18646，197 工具）：只有 `task_id`/`namespace`/`agent`，
  **无 `deliverable` 字段**；传 `deliverable` 属多余键。
- `verify` schema 实测：必填 `task_id` + `verifier`；带 `[gate:required]`，
  校验 specs 新鲜度（`created_at >= 任务 updated_at`）。
- 终态：`T0r128` = **已完成**，`completed_by=human_steward`，`updated_at=2026-11-25T12:46:24Z`。
  支撑它的新鲜记录是 12:46:25 / 12:46:28 两条 `passed`（由 18641 / 18640 落的）。
- 随后重发 `submit` 的回执（作为「已完成态不可再提交」的实证）：
  `{"code":-32000,"message":"非法迁移: submit 要求状态 [执行中]，当前是 [已完成]"}`。

---

## 三、分析（为什么是这些结论）

1. **为什么把「401 vs 429」当成一个需要修的点**：限流与鉴权共用 `auth_ok()` 的一个
   `bool`，调用点（`fist_gateway.py:894-902`）只能看到 `False`，于是两种完全不同的情况
   （凭据错 / 配额超）对调用方**完全同形**：同一个 401、同一行 `auth_fail`。后果有三：
   ① 调用方无法区分「key 写错了」与「稍后再试」；② 监控里配额抖动会伪装成安全事件；
   ③ 文档教的 429 重试策略无处附着。这是**最小改动可收口**的一格：让限流分支返回独立
   状态码 + 独立审计事件（如 `rate_limited`），不动认证本体。
2. **为什么常驻面是当前最大缺口**：`gateway_guardian.py` 已经具备 `--once` 拉起能力，
   但**没有任何东西周期性调用它**。于是「重启后自恢复」在事实上不成立：进程被 OOM /
   宿主重启 / 误杀之后，只能靠人想起去跑一次 `--once`。计划条目五的验收第一条就是
   「重启后自恢复」，这一格**必须挂一个常驻触发器**（计划任务 / 由 mcp-watcher 链
   驱动 / 或宿主启动器自拉），而不是继续加功能。
3. **为什么 `fist-auto` 要优先复用而不是新写**：`fist_gateway.py` 已含认证、审计、限流、
   注册表、生命周期（`running → draining → stopped`）、心跳回写，且 `--complete-backend`
   候选池（`parse_complete_backends` / `CompletionPool`）已落地（T0r125）。条目五要做的
   只是**用它起一个新 service-id**，不需要新进程形态。
4. **18646 的 run_check 失能为何不阻塞验收**：`[gate:required]` 校验的是**任务所在 ns 的
   specs 记录**，记录可由任一实例落（同一份 `autoplan.db`）。但它暴露了一个真实风险：
   **无人值守流水线若恰好在 18646 上跑验收链，会拿到 r1..rN 全 failed 而误判任务失败**。

---

## 四、缺口与风险（遗留，均未在本轮擅自修）

| # | 缺口 | 证据 | 影响 |
|---|---|---|---|
| 1 | **无常驻守护触发器**，「重启后自恢复」无机制承载 | 计划任务零命中、无 guardian 进程、state 停 18:54:02Z | 条目五验收第①条不成立；单点挂死需人工 |
| 2 | **限流与鉴权同脸**（401 + `auth_fail`），文档写的 429 未兑现 | `:489-505` + 连发 66 发实测 | 归因失真、文档漂移、配额问题伪装成安全事件 |
| 3 | **fist-auto 未进注册表**（裁决 A1 的 18651 被 OFM-1 占用） | `agent_service` 10 行无 fist-auto；`[STALE] 18651 OFM-1` | 端点不可被发现/巡检；与裁决冲突 |
| 4 | **OFM-1/2/3 在监听但不在真源** | `--status` STALE 三行；库 `.fist-mbt/data/OFM-*.db` 存在 | 非真源服务无人接管，守护器只能点名 |
| 5 | **18646 子进程调度层失能**（run_check 四发全 failed，空输出） | §2.5 | 该实例上的验收链/外部判据不可用；根因未取证 |
| 6 | **注册表脏行**：`svc-agent` stopped 却占 18649 | §2.4 | 端口推导须持续依赖 `status='running'` 过滤 |
| 7 | 启动器 gateway 路由指向 `scripts/fist.py`（CLI 分发），非 `fist_gateway.py` | `serve-launcher.cjs:197-216` | 命名易误解；两者是不同层的「gateway」 |
| 8 | `scripts/fist-gateway.py`（未跟踪）与真源并存 | `git ls-files` 只含 `fist_gateway.py` | 他方 WIP 漂移面，容易被误当参考 |

---

## 五、后续建议（含最小改动方案，**均未执行**）

1. **补常驻触发器（最高优先，条目五验收①）**：给 `gateway_guardian.py` 挂一个每 N 分钟
   的 `--once` 触发器。三条现成路径，按侵入性排序：
   - ① 计划任务（schtasks 模板仓内已有 `scripts/explore_watchdog_hidden.vbs` 与
     `FIST-Mbt-ExploreWatchdog` 可照抄形态）；
   - ② 挂进现有 `FIST-WatchDaemon` 链（mcp-watcher，注意 EP-03 四层死链尚未收口，
     见记忆）；
   - ③ 由 `%LOCALAPPDATA%\FIST-Mbt\serve-launcher.cjs` 启动时自拉一次。
   ⚠️ 三者都需要管理员/计划任务权限，属**不可逆面**，按项目纪律只出方案、等指挥官/用户
   确认后再动。
2. **拆限流与鉴权（最小改动，约 10 行）**：`auth_ok()` 改为返回 `(ok, reason)`，
   限流分支在 `:896` 前返回 **429** 并落 `rate_limited` 审计；同步把
   `docs/fist-agent-principle.md:63` 与 `docs/web-model-agent-deploy-guide.md:146` 的口径
   对齐（无论选哪个方向，文档与实现必须一字一致）。
3. **为 18651 的占用做裁决**：要么把 OFM-1/2/3 收进注册表真源（它们本就是 `fist_gateway`
   起的、有审计日志），要么给 fist-auto 换端口并在计划文件更新 A1 的端口字面量。
4. **18646 run_check 失能单独立项**：需要该实例的 server.log（BUG-538 心跳 + `spawn.end`
   行）才能定位；建议复现方式 = 在 18640/18641 上 A/B 对照同一 payload。
5. **清 `svc-agent` 脏行**：一条 UPDATE 即可，但它牵动端口真源过滤口径，建议与
   `derive_service_ports()` 的注释一起改。

---

## 六、资源消耗

| 项 | 读数 |
|---|---|
| 代码改动 | **0 行**（零代码改动；唯一产物为本报告） |
| 新增文件 | 1（本报告，`reports/`） |
| 实测命令 | 约 15 条（curl 探针 ×4 类、守护器 `--status`/`--selftest`、注册表直读、计划任务枚举、监听端口扫描、跨实例 run_check 对照 ×4） |
| 触碰的线上进程 | 只读探测 18646/18640/18641；未重启、未 kill、未改任何注册表行 |
| 副产物 | 18646 审计日志新增若干 `mcp_call`/`auth_fail` 行（append-only，预期内）；`autoplan.db` specs 新增 6 条 run_check 记录（r1-r6，其中 r5/r6 为 passed） |

## 七、任务分配记录

| 环节 | 归属 |
|---|---|
| 执行身份 | workbuddy（池内任务 T0r128） |
| 派发 | 接力棒派发（`deliverable` 原文字面） |
| 验收 | `verify(verifier=human_steward)` → 已完成 / completed_by=human_steward |
| 本任务未委派子代理：全部为只读盘点，单 agent 一轮可完成（按分流决策树属「轻任务」） |

## 八、超额内容

- 主动做了跨实例 A/B 对照（18646 vs 18640 vs 18641）来定性 run_check 失能，超出「只读盘点」
  的字面要求，但属零副作用的只读探针，且直接支撑了条目五「验收链可用性」的判断。
- 未做（也未被授权做）：改代码、改文档、改注册表、挂计划任务、重启任何服务。

## 九、来源

- 计划真源：`fist-mbt/plan/active/2026-11-25-fist-auto-model.md`（工作项五 + 裁决项 A1-A4）
- 代码面：`scripts/fist_gateway.py`（认证/限流/审计/生命周期）、`scripts/gateway_guardian.py`
  （真源推导 `:539-557`、`write_status` `:997-1051`、自检 S 族 `:1281-1295`）、
  `src/engine/auth_mode.mbt`、`%LOCALAPPDATA%\FIST-Mbt\serve-launcher.cjs`
- 数据面：`.fist-mbt/data/agent-services.db`（`agent_service` 10 行）、
  `.fist-mbt/data/autoplan.db`（`tasks` / `specs` / `call_log`）、
  `temp/gateway-*.log`、`.fist-mbt/data/guardian-logs/guardian.log`
- 前序实证：`reports/2026-11-25-T0r103-guardian-port-truth-report.md`（端口真源）、
  `reports/2026-11-25-T0r122-ocr-method-merge-report.md`（18646 spawn 失效）、
  `reports/2026-11-25-T0r124-fist-auto-design-report.md`（设计面）
- 账本：`memory/bugs.md` BUG-470（三档开关）、BUG-476（strict 硬拒范围）、
  BUG-587（server cwd / 相对路径落库边界）
- 实测命令与读数：见本报告 §二 各块原文
