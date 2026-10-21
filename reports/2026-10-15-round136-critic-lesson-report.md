# Round 136 报告 · evolve_critic 防漂移门禁实测 + 教训归档

- 日期：2026-10-15
- 提交：`asset-mcp-compat-stub-2026-10-15T05:16:28Z` + `lesson-202610-15.05.17:`
- 角色：运维验证轮 + 自进化门禁实测轮

## 结果摘要

### 1. evolve_critic 门禁实测（两层有效性）

**测试 A：拟入库"shim 完整设计原则"**（broad, 包含 protocolVersion 回写 + stub + 通知透传）：

```
admit=false
novelty=0.718
score=0.9
combined=0.809 < threshold 0.85 → rank=L3 稳健性不足，拒收
top_hit=asset-mcp-compat (sim=0.28，非重复但同域)
```

**结论**：**正确拒收**。combined=0.5×0.9 + 0.5×0.718 = 0.809 未达 0.85 阈值。原因：与已有 `asset-mcp-compat` 同域（novelty 未满），score 虽高但不够补足。

**测试 B：注册聚焦 stub 资产后跑 critic 自比对**：

```
admit=false
novelty=0.138
sim=0.862 ≥ 0.70 → rank=L1 课程漂移/重复，拒收
```

**结论**：**正确识别自比对重复**（我刚注册的资产与自身比对，sim=86.2%）。Critic 把"重复入库"这个坑堵住了。

### 2. 聚焦 stub 资产注册

```
id    = asset-mcp-compat-stub-2026-10-15T05:16:28Z
goal  = [asset]mcp-compat-stub
score = 0.85
note  = server 不支持的三类方法（ping/logging/setLevel/completion/complete）必须 stub 响应；
        所有 notifications 必须透传（不加 _meta、不期待响应）。
```

### 3. 教训资产注册（新颖，非重复）

```
id       = lesson-202610-15.05.17:
category = concurrent-coordination
learned  = true
duplicate = false
reason   = 并发开发时不要改对方 WIP 文件，而是把缺陷固化为 FAIL 测试 + 归档原则，让对方提交时被拦住。
fix      = 五步闭环：读状态→独立评审→固化测试→归档原则→等对方提交时拦截。
```

## 资源消耗

| 项 | 值 |
|---|---|
| 工具调用 | evolve_critic × 2、evolve_asset_register × 1、evolve_lesson × 1、pwsh × 1 |
| 提交 | 2 个（资产 + 教训） |
| 触碰并发 WIP | 无 |

## 任务分配记录

- 本会话 Round 136 完成：evolve_critic 防漂移门禁实测 + 教训归档。

## 遗留风险

1. **内建 compat 的 protocolVersion 回写缺陷**——已归档 DGM 资产 `asset-mcp-compat-...` + 教训 `lesson-concurrent-coordination`。
2. **BUG-155 假绿持续**——HEAD 仍含 stale dist。
3. **BUG-161/163 内建修复未提交**。

## 后续建议

1. 并发 agent 提交 compat 层后，用 `plan` 的 `inject=mcp-compat,mcp-compat-stub,concurrent-coordination` 可自动检索到 3 条归档资产。
2. `evolve_critic` 的 L1/L3 双拒收路径证明门禁有效——继续用它评审所有拟入库资产。

## 超额内容

- 无（严格限于自进化门禁实测 + 教训归档）。

## 来源

- `evolve_critic` → 测试 A: L3 reject (combined=0.809)；测试 B: L1 reject (sim=0.862)
- `evolve_asset_register` → `asset-mcp-compat-stub-2026-10-15T05:16:28Z`
- `evolve_lesson` → `lesson-202610-15.05.17:` `[lesson]concurrent-coordination` (duplicate=false)
