---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_6ba0cef6e5be11f1a9b8525400f8a581
    ReservedCode1: RdC+0nYg2kLE8oenpjs6AX9+djZkbZ5ftHYinj2ABo9qoF1U/0byaYZNKeWdslD+jxJlgqcd2JLbZld7TjbmAaONXi3R4virLhUfR1QxBqTmbfzaa0d4lpoo8F3NQU2C4d71g9UoKmJZK2XokzdiE+my1GaT2hUsunNK6KP/FytpgqkHD2zZyLB5ZSM=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f2a11add43fbf12a546606fb2b962ab_6ba0cef6e5be11f1a9b8525400f8a581
    ReservedCode2: RdC+0nYg2kLE8oenpjs6AX9+djZkbZ5ftHYinj2ABo9qoF1U/0byaYZNKeWdslD+jxJlgqcd2JLbZld7TjbmAaONXi3R4virLhUfR1QxBqTmbfzaa0d4lpoo8F3NQU2C4d71g9UoKmJZK2XokzdiE+my1GaT2hUsunNK6KP/FytpgqkHD2zZyLB5ZSM=
---

# TokenSaver / Save-Token 与 fist-mbt 整合计划

日期：2026-11-21
状态：决策已定，待实现
范围：模型路由归属决策 + svc-webai 2.0 增强清单

## 1. 决策结论：双层路由混合架构（不拆分、不集成）

**模型路由功能不分发出去给 TokenSaver，也不由 fist-mbt 集成通道级路由。**

两个 router 职责层级不同，应当各司其职：

| 层级 | 归属 | 路由对象 | 说明 |
|------|------|----------|------|
| 平台级 model_router | fist-mbt（保留） | agent_service / 执行器 / free-paid 模型池 / 配额 / 成本记账 / fallback_chain | 稳定平台资产，已具备（src/router/model_router.mbt 等） |
| 通道级 provider_router | svc-webai 网关（内聚 TokenSaver router.py） | 网页 provider 实时可用性（免费优先、健康表、冷却 300s、降级） | 高频易变（网页改版/风控/登录态失效），Python 侧热修 |

### 决策依据

1. **职责边界**：fist-mbt 路由对象是平台资产（服务/执行器/模型池），稳定低频；TokenSaver 路由对象是网页 provider 的实时健康（失败计数、冷却、降级），高频变化。
2. **耦合代价**：通道级逻辑（健康表、冷却、Playwright 状态）若并入 MoonBit 核心，每次网页端改版需重编译发布；保留在 Python 网关可用脚本热修适配器，风险可控。
3. **资产复用**：TokenSaver 已验证的四重 token 节省（缓存/压缩/免费优先路由/预算拆分）+ 超级元宝验证通道应整体作为网关通道层资产保留，不拆散。
4. **既定形态一致**：符合此前确定的"编排逻辑进 fist-mbt + 网关独立进程做 HTTP 传输"混合形态。

## 2. 落地架构

```
用户/Agent 请求
  → fist-mbt model_router（平台级：池选择、配额、fallback、成本记账）
      → svc-webai（agent_service，endpoint=127.0.0.1:18645/mcp，已注册）
          → provider_router（TokenSaver router.py 迁移版：免费优先+健康/冷却）
              → Playwright 驱动已登录 Chrome（deepseek/元宝/kimi/豆包）
          → token 节省中间件（缓存 / 上下文压缩 / 预算感知拆分）
          → 超级元宝验证通道（高质量 fallback 分支）
```

- fist-mbt 侧仅需：把 svc-webai 挂入 router_config 的 free 池（已有雏形）；fallback_chain 增加 quality 分支指向 svc-webai 超级元宝通道。
- svc-webai 侧需内聚：TokenSaver 的 router.py（provider 健康/冷却/降级）、cache.py、context_compressor.py、task_splitter.py，作为网关中间件。

## 3. svc-webai 2.0 需补清单

### 3.1 Provider 矩阵扩展

当前 config.toml 仅 4 个 provider（deepseek/yuanbao/doubao/kimi）。2.0 扩展：

- provider 注册表改为可插拔配置（保留 url + deep_think 标志，新增 `auth_mode`：cookie 复用 / 本地登录态 / opencli）
- 每 provider 独立健康状态持久化（迁移 TokenSaver 的 provider_health 表）
- 新增 provider 时无需改代码，仅改 config.toml

### 3.2 Token 节省层（网关中间件）

| 机制 | 来源 | 接入点 |
|------|------|--------|
| 结果缓存 | TokenSaver cache.py（SQLite，键=问题+provider+模式） | 网关 chat 入口前置 |
| 上下文压缩 | TokenSaver context_compressor.py（历史超 4000 摘要早期消息） | 会话历史注入前 |
| 预算感知拆分 | TokenSaver task_splitter.py（子任务 token 估算超预算再拆） | 长任务编排 |
| 免费优先路由 | TokenSaver router.py（迁移） | provider 选择 |

### 3.3 超级元宝验证通道

- 保留 `-p yuanbao --super` 语义，作为 fallback_chain 的 high-quality 分支
- 对应 fist-mbt fallback_chain 中 quality 路由（深度思考/混元T1 验证）

## 4. 实施步骤（fist-mbt 开发工作流）

1. 写本计划（完成）
2. 派发 executor_run（atomcode）实现 svc-webai 2.0：
   - 迁移 router.py / cache.py / context_compressor.py / task_splitter.py 至网关
   - provider 注册表配置化
   - 挂载 token 节省中间件
3. 修改 fist-mbt router_config：svc-webai 挂 free 池 + fallback_chain quality 分支
4. 验收：selftest 全绿 + P4 端到端（用户登录 deepseek/元宝后跑通）

## 5. 安全与约束

- 端口红线：勿用 18640/18641/18643/18644
- provider 登录态仍存 .fist-mbt/data/webai-chrome-profile，不重复登录
- 免费池配额与冷却参数沿用 TokenSaver 默认（冷却 300s、失败 2 次降权）
*（内容由AI生成，仅供参考）*
