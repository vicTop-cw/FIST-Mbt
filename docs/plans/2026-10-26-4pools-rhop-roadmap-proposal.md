---
status: 提案中
decided_by:
decided_at:
decision:
---

<!-- 原文件头部的 AIGC 生成标记（不是 YAML frontmatter，已移到此处保留）：
  AIGC:
      Label: "1"
      ContentProducer: 001191440300708461136T1XGW3
      ProduceID: 9f2a11add43fbf12a546606fb2b962ab_f991019ad13511f18460525400393706
      ReservedCode1: pC4ZdXEB8Gbp9/szeM+c3IuLw0nsYhDYrF3drfnn6LiNR/SwlReOdZODuiqMYjoJzz8VZxPeKUn9pBOwVW3wxaqR/NGcwT4QnbUvg239IjDN8z7vO1knXyxMu+GJ+2zpdUhq7AB2foX2rZK2xKHrfURe6w5XsSu7i9uAzIMLlnH2iwiRhC1OoZMfWMM=
      ContentPropagator: 001191440300708461136T1XGW3
      PropagateID: 9f2a11add43fbf12a546606fb2b962ab_f991019ad13511f18460525400393706
      ReservedCode2: pC4ZdXEB8Gbp9/szeM+c3IuLw0nsYhDYrF3drfnn6LiNR/SwlReOdZODuiqMYjoJzz8VZxPeKUn9pBOwVW3wxaqR/NGcwT4QnbUvg239IjDN8z7vO1knXyxMu+GJ+2zpdUhq7AB2foX2rZK2xKHrfURe6w5XsSu7i9uAzIMLlnH2iwiRhC1OoZMfWMM=
-->

# 提案：4 池子建设 + rx-mbt rhop 完善 + fist-mbt 对齐 vools-rhop

## 一、背景与问题

1. **4 个池子缺失**：同机任务池、跨机任务池、同机消息池、跨机消息池均未正式落地。现有 `.commissar/`（events/inbox/reminder_log）只是同机消息池雏形；`.fist-mbt/pool/` 在治理提案 DEC-2026-10-22-001 中规划但实测未建。
2. **核心依赖未成熟**：4 个池子的传输底座依赖 rx-mbt 库的 **rhop（同机器异进程传输协议）**，目前仅实现一点点——`cipher.mbt`（RhopCipher trait + none 实现）、`packet.mbt`（RhopPacket + RhopEnvelope 编解码）、`rhop_js.mbt`（AES-256-GCM + PBKDF2 密钥派生 + tmp/rename 原子写 + shared path 文件监控），`rhop_native.mbt` 仅为占位 stub。
3. **目标形态已存在**：vools 项目下的 **vools-rhop**（Python）是成熟参考——MVP-1（抽象密钥函数）、MVP-2（shared path 传输 + 监控 + 在线优先/离线回退）、MVP-3（双端自建临时服务器中转）均已实现并通过全部判据（2026-10-18，18/18 测试通过），另有信封/签名/心跳/会话/镜像/任务队列等完整模块。

> **现状勘误（2026-10-29 · 事实订正，不改技术主张，status 仍待 owner 定案）**
>
> 上面第 1、2 条的读数已过时，实测如下：
>
> | 提案说法 | 2026-10-29 实测 | 证据 |
> |---|---|---|
> | rhop「仅实现一点点」，只列 4 个文件 | rx-mbt/rhop 实有 **29 个 `.mbt` / 12 787 行**（另有 envelope/signer/integrity/relay/session/watch/transport_×4/mirror/daemon/online 等 25 个） | `../rx-mbt/rhop`；`reports/2026-10-29-4pools-gap-analysis-report.md` |
> | 4 池子「均未正式落地」 | `.fist-mbt/pool/` **存在但 0 文件**；`.commissar/` **不存在**；`fist-mbt/pool/` **不存在** | 同上报告 §②，本轮复测一致 |
> | 同机消息池「只是雏形」 | 能力已实现且**已接出 MCP**：`src/ops/ops_commissar.mbt` + 工具 `commissar_send`（只发不收） | `src/ops/ops_commissar_wbtest.mbt`；BUG-477 / BUG-480 |
> | `rhop_native` 占位 stub | **属实**：47 行 stub，三函数只 println + 返回空 | 同上 |
>
> **⇒ 真缺口不是「没实现」，而是「跨机传输 + native 实现 + 0 测试（0 测试下"全绿"= 0/0 空真）」。
> 提案状态（`提案中`）未由本订正改变 —— `docs/plans/README.md` 硬规则 3：定案权仅 `human_steward`，agent 只提不定。**

## 二、目标

分三阶段推进，最终让 fist-mbt 的 4 个池子以 rx-mbt rhop 为传输底座运转，功能与 vools-rhop 对齐：

1. **阶段一**：4 个池子的建设计划先落地到 fist-mbt（本文档即计划载体，后续按此执行）。
2. **阶段二**：开发 rx-mbt 仓库，完善 rhop 核心依赖（对照 vools-rhop 补齐能力）。
3. **阶段三**：使用 fist-mbt 开发 rhop 功能，目标与 vools-rhop 对齐。

## 三、4 个池子定义（阶段一落地）

### 3.1 同机任务池（机器独有，gitignored）

- 位置：`.fist-mbt/pool/tasks/`（自 `.git/fist` 迁来，遵循 DEC-2026-10-22-001 双层目录治理）
- 文件形态：`task.md` 文件夹，子目录四态：
  - `预案/`（proposal，未批准）
  - `定案/`（decided，已批准待执行）
  - `执行中/`（running，被某 agent 认领）
  - `归档/`（archive，已完成/已关闭）
- 流转规则：预案 → 定案（human_steward 或 lead 批准）→ 执行中（认领）→ 归档；状态变更在 frontmatter 的 `status` 字段维护。
- 用途：单机多 agent 之间的任务交接与状态跟踪。

### 3.2 跨机任务池（团队共享，committed）

- 位置：`fist-mbt/pool/tasks/`（仓库根下的 `fist-mbt/` 共享侧，随主仓提交）
- 文件形态：与同机任务池相同的 task.md 四态目录，但内容经 rhop 信封封装或包含跨机来源标记（`origin` 字段记录机器/节点）。
- 传输底座：通过 rhop 的 shared path / 在线通道在机器间同步任务文件，本机拉取后落入本地同机任务池执行。

### 3.3 同机消息池（机器独有）

- 位置：`.fist-mbt/pool/messages/`（由 `.commissar/` 雏形扩展迁移）
- 文件形态：目录 `events/`（事件流）、`inbox/`（收件箱）、`outbox/`（发件箱）、`reminder_log/`（提醒日志）、`archive/`（归档）。
- 传输底座：单机多 agent 消息优先走 **rhop 同机 shared path**（`.rhop` 信封文件 + 文件监控），替代/补充现有事件文件直写。

### 3.4 跨机消息池（团队共享）

- 位置：`fist-mbt/pool/messages/`（共享侧），或配置的 shared path（FTP/URL/Git 仓/挂载盘/UNC 等任一共通介质）
- 文件形态：`.rhop` 信封文件（`{"v":1,"alg":...,"ct":...}`），内容为加密 JSON。
- 传输底座：rhop 的 shared path 抽象 + 在线优先（Git/SFTP/自建中转）/离线回退（shared path）通道选择。

## 四、rx-mbt rhop 完善计划（阶段二）

对照 vools-rhop 能力清单，补齐 rx-mbt/rhop：

| 模块 | vools-rhop 对应 | rx-mbt 现状 | 补齐动作 |
|---|---|---|---|
| 密码学抽象 | `crypto.py`（密钥派生+加密+解密验证一体） | `RhopCipher` trait + none + AES-256-GCM（js） | 补密钥派生抽象（PBKDF2 参数化）、解密验证返回区分失败原因；native 目标至少支持 none |
| 信封/签名/完整性 | `envelope.py` `signer.py` `integrity.py` | `RhopEnvelope` v/alg/ct | 补签名域（sig）、完整性校验（hmac/哈希） |
| 消息包 | `models.py` | `RhopPacket` id/source/kind/payload/at | 对齐字段扩展（可选 seq/ack/ttl） |
| shared path 抽象 | `transport/`（写端视图+读端视图、file:/// http(s):// 解析） | 仅本地路径拼接（`/` 跨平台） | 补多端视图解析、URL 形式识别、在线/离线通道选择与回退 |
| 文件监控 | `watch.py`（vools-rx 触发器 API） | `from_filesystem`（rx Observable） | 补 skip_existing 语义细化、坏文件策略文档化 |
| 心跳/会话 | `heartbeat.py` `session.py` | 无 | 新增 heartbeat/session 包 |
| 中转（MVP-3） | `transport/jump.py`（RelayHost/RelayClient 三端） | 无 | 新增 relay：RelayHost 临时 HTTP 中转 + TTL + RelayClient 投递 |
| 镜像/任务队列 | `mirror.py` `queue.py` | 无 | 视需要跟进（MVP 之外） |

工程约束（历史踩坑，必须遵守）：
- rx 包引用一律 `"vicTop-cw/RX-MBT/rx" @rx` 别名 + `@rx.` 前缀访问；
- 跨包 trait impl 必须加 `pub`（`pub impl T for X with ...`）；
- 路径拼接统一用 `/`（`root.ends_with("/") || root.ends_with("\\")` 判断），node fs 跨平台均接受 `/`；
- 包根名大小写敏感：`vicTop-cw/RX-MBT`（MBT 大写）。

## 五、fist-mbt 开发 rhop 功能（阶段三，对齐 vools-rhop）

- 在 fist-mbt 中接入 rx-mbt/rhop，落地为 MCP 工具/服务：
  - 消息收发工具（rhop_send / from_filesystem 包装）；
  - 4 池读写工具（任务池 task.md 流转、消息池信封读写）；
  - 跨机同步工具（shared path 推送/拉取、在线通道优先）。
- 对齐判据（参照 vools-rhop MVP 出口判据）：
  1. 本地固定密钥能对 JSON 加密，解密验证通过/失败可明确区分；
  2. 同一机器两进程（A/B 模拟）通过 shared path 收发一包加密 JSON 成功；
  3. 有网介质可用时优先走在线通道，不可用时自动回退 shared path；
  4. 接收方用 rx Observable 监控到新文件并成功解密验证；
  5. 双端都有网且异机时，任一方自建中转可完成加密 JSON 投递。

## 六、里程碑与验收

- **M1（阶段一）**：本文档定案，4 池目录结构在 `.fist-mbt/pool/` 与 `fist-mbt/pool/` 创建完毕，README 说明流转规则。
- **M2（阶段二）**：rx-mbt/rhop 补齐表内 P0 项（密钥派生抽象、签名/完整性、shared path 多端视图、在线/离线回退、heartbeat），js 目标 `moon test` 全绿。
  - **前置（2026-10-29 补）**：**先补出测试，再谈"全绿"** —— 实测 rx-mbt/rhop 为 **0 个测试**，
    0 测试下「`moon test` 全绿」= 0/0 空真，不能作为完成标志。见 `reports/2026-10-29-4pools-gap-analysis-report.md` §④。
- **M3（阶段三）**：fist-mbt 接入 rhop，4 池工具可走通同机收发 + 跨机 shared path 同步；对照 vools-rhop 判据 1-5 全部通过。

## 七、参考

- vools-rhop 源码与设计：`E:\IDEProjects\AI\vools\rhop`（`analysis/rhop-PLAN.md` v2，2026-10-18 MVP 全通过）
- rx-mbt 现状：`E:\IDEProjects\AI\rx-mbt\rhop`（cipher/packet/rhop_js/rhop_native）
- 治理基线：DEC-2026-10-22-001 双层目录（`.fist-mbt/` 机器独有 + `fist-mbt/` 团队共享）
*（内容由AI生成，仅供参考）*
