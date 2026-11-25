---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_0bb7ecbce67b11f184bd52540072b1e8
    ReservedCode1: VeNlcPQDBEz6jkQhiOBcxie7yE6+UA86dr5bDh4U/WWjxnTKURgA8Ew/CNTRAZk8mA/BI4EmWDzWV+c81Y192xG0wn2D54dRYVPwhQKC93b5FBm6OZyvB8pidpc6FL9eWN1giAZW0gJywB7u1jhaEqquntu9CAL0DcA1GZK2so+CYbfsbx8x/JJTGlI=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f2a11add43fbf12a546606fb2b962ab_0bb7ecbce67b11f184bd52540072b1e8
    ReservedCode2: VeNlcPQDBEz6jkQhiOBcxie7yE6+UA86dr5bDh4U/WWjxnTKURgA8Ew/CNTRAZk8mA/BI4EmWDzWV+c81Y192xG0wn2D54dRYVPwhQKC93b5FBm6OZyvB8pidpc6FL9eWN1giAZW0gJywB7u1jhaEqquntu9CAL0DcA1GZK2so+CYbfsbx8x/JJTGlI=
---

# 聊天群 GUI —— fist-mbt 角色聊天群 + 聊天式发布任务（初稿）

> 状态：初稿（autoplan 初稿区，仅建记录，任务不入池，不执行）
> 关联：docs/plans/2026-11-22-autoplan.md（autoplan v2 协议）、docs/proposals/2026-11-22-longrun-upgrade-proposal.md（长程任务升级，正交）

## 背景摘要

用户诉求：给 fist-mbt 做一个 GUI 聊天群——默认注册一批角色当聊天群成员；用户以聊天方式发布任务；后台由 dsh super agent 静默编排干活；fistagent 拉起服务时可选择入哪个群、注册什么角色。

竞品调研结论：AI 群聊协作不是空白市场，产品形态已验证（智群 AgentTeam、AI 信息中转工作台）；可借鉴 AutoGen GroupChat（RoundRobin/Selector + GroupChatManager 主持）、ChatDev（虚拟软件公司多角色研讨会）、AgentMsgr（跨平台代理聚合层）。用户底牌：常驻 Agent 服务托管平台（agent_service 表 + 常驻网关 + API-key 认证 + 自动路由）、dsh super agent 静默编排、fistagent 带身份入群机制、170+ 个 MCP 工具底座。

## 工作项

- [ ] 群模型：fist-mbt 默认注册一批角色形成聊天群，支持用户自定义群与成员
- [ ] 聊天式发布任务：用户在群里以聊天消息发布任务
- [ ] 消息 → 结构化任务转换层：聊天消息转为任务（模板路由优先 + LLM 兜底）
- [ ] 后台执行：dsh super agent 静默编排，群内只回结果与关键进展
- [ ] 发言控制：默认 @ 目标角色才回，无 @ 时群成员静默
- [ ] 终止控制：stop 命令 + 熔断双轨
- [ ] fistagent 拉起服务时选择入群、注册角色（复用 fistagent 带身份入群机制）
- [ ] GUI 承载：接入常驻 Agent 服务托管平台（agent_service 表 + 常驻网关 + API-key 认证 + 自动路由）
- [ ] 与 longrun 提案对接：跨会话任务复用 fist_longrun_* 六工具最小集，不重写
- [ ] 竞品模式吸收：GroupChatManager 主持、@插队、方案→执行→审查→回退修复→复审通过 编排模式

## 裁决问题

? GUI 技术形态 | 选项：Web 内嵌页 / 独立桌面端 / 终端 TUI | 建议：Web 内嵌页（复用常驻网关）
? 默认角色清单 | 选项：PM+架构+前端+后端+测试+审查 / 复用 agent_service 现有角色 / 用户自定义 | 建议：复用 agent_service 现有角色 + 常用缺省
? 发言控制 | 选项：@ 才回+无 @ 静默 / 群内自由发言 / 白名单角色 | 建议：@ 才回+无 @ 静默
? 任务转换层 | 选项：LLM 结构化抽取 / 模板路由 / 混合 | 建议：混合（模板路由优先 + LLM 兜底）
? 终止控制 | 选项：仅 stop 命令 / 仅熔断自动停 / 双轨 | 建议：双轨（stop 命令 + 熔断自动停）
? 与 longrun 的关系 | 选项：本计划独立推进 / 依赖 longrun 定案后合并 / 完全并入 longrun | 建议：本计划独立推进，接口对齐 longrun
*（内容由AI生成，仅供参考）*
