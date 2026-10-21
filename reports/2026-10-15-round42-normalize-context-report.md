# Goal-2 Round 42 报告：caf_normalize_context 归一化契约（接线前置）

- **日期**：2026-10-15
- **提交**：R42 code（`router_caf_ext.mbt` + `router_caf_ext_wbtest.mbt`，HEAD `43c83de`）+ router `.mbti`（HEAD `7ed22a2`）
- **状态**：§2.3 server 接线仍阻塞（`model_router_ops.mbt` 4/9 WIP），本轮用 fist-mbt 能力寻虫 + 做接线前置契约

## 结果摘要

### 接线释放复查（本轮起点）

`model_router_ops.mbt` 仍 **4/9** WIP，工作树 94 文件，`cmd/cli/*` 也大面积 WIP → **§2.3 接线不可行**。

### 寻虫双轨复核（R41 遗留建议 2 收口）

对 R41 复核的 `model_router.mbt` L487 `dig[0..18]` 用 **`boundary_probe`**（rule=string-index）：
返回 4 条边界建议（负下标 / 边界下标 / 空输入 / 超长输入），`confirmed_count=0` —— **探测链走通**，
但因 L455 长度守卫 + L464-472 非负检查 + BUG-218 边界，这些输入都安全返回 -1，**不触发 panic**（预期）。

另复核 `issue_scan` 的 `array-index-bounds` 候选 L544 `pool[idx]`：
`idx = ((start_idx+i) % n + n) % n`，i∈[0,n-1] → idx∈[0,n-1]，**双取模已防御**，假阳性。

**结论**：`issue_scan` 在 `model_router.mbt` 的高价值候选全部是假阳性（防御已就位）。寻虫面真正产出
靠「finding 当线索 → 人工复核真源 → 防御缺锁才补锁」这条链，而非 finding 本身。

### 本轮实质产出：`caf_normalize_context` 归一化契约

`issue_scan` 未命中但**真源暴露**的碎片化风险（R41 遗留建议 4 落地）：

`caf_feature_hash(context)` 直接对 `context[i].to_int()` 做多项式 hash（`h = h*31 + c`，`c = char.to_int()`），
**大小写与空白敏感**：
- `"PYTHON"` / `"python"` / `"  python  "` → **完全不同**的 hash
- 三者落在 `knn_search`（编辑距离 on hash 数字串）的**不同邻域** → 同类任务记忆写进三条不相连的桶

新增 `caf_normalize_context(context) : String`（trim 首尾空白 + ASCII lowercase），
**契约**：接线时用 `caf_feature_hash(caf_normalize_context(ctx))` 代替 `caf_feature_hash(ctx)`，
使语义等价输入收敛到同一 hash → 命中同一 knn 邻域。

**实现要点**：MoonBit `String[i]` 返回 **UInt16**（非 Char），故用 `context[i].to_int()` 取字节，
`is_ws_byte`（32/9/10/13）+ `to_lower_byte`（A-Z → +32）按字节处理。

**锁（`caf_norm_1~4`，加在独立文件 `router_caf_ext_wbtest.mbt`，不碰并发域）**：

| 锁 | 钉死的契约 |
|---|---|
| `caf_norm_1_大小写归一后hash一致` | `caf_feature_hash(caf_normalize_context("PYTHON"))` == 同 `"python"` == 同 `"Python"` |
| `caf_norm_2_空白归一后hash一致` | `caf_feature_hash(caf_normalize_context("  python  "))` == 同 `"python"` == 同 `"\tPython\n"` |
| `caf_norm_3_未归一化hash碎片化` | 未归一化时 `"PYTHON"`/`"python"`、`"  python  "`/`"python"` hash **不同** → 确认接线必须归一化 |
| `caf_norm_4_空串与纯空白安全` | `""`/`"   "`/`"\t\n  "` → `""`（不 panic）；幂等：归一化后再归一化不变 |

**零回归性质**：输入已归一化时是恒等（幂等）。

### 验证

router **193/193**（R41 基线 189 + 4 锁），0 failed。

### 全仓门禁被并发 WIP 阻塞（如实记录）

`moon test --target js` 全仓 **exit 1**，报 `Error: [4080]` at `src/server/github_sync_wbtest.mbt:250`：
`github_queue_append` 需 8 参数但测试给 6 参数 —— **并发 agent 改签名未同步 wbtest 的半成品**（git status 确认 `github_sync.mbt` + `github_sync_wbtest.mbt` 均为 M WIP）。
**非本 R42 引入**（router 层独立 193/193 绿）。按 AGENTS.md **不碰并发 WIP 文件**，path-scope 提交 router 层。

### .mbti 同步教训

`moon info`（无路径）**未把新 pub fn 写入 router `.mbti`**（因并发 WIP 编译错误导致整体 info 未重跑到 router 包）。
改为 `moon info src/router` 指定包路径后成功写入（diff `+2`，只加 `caf_normalize_context(String) -> String`）。
**教训**：并发 WIP 阻塞全仓编译时，用 `moon info <路径>` 只同步自己包的接口，避免连带混入并发 `.mbti` 变化
（本轮 `src/server/pkg.generated.mbti` 1/1、`src/store/pkg.generated.mbti` 3/0 均为并发变化，未提交）。

## 资源消耗

`boundary_probe` / `moon check` / `moon info`（含 `src/router` 指定路径）/ `moon test --target js src/router` / 全仓回归（被并发 WIP 阻塞）/ `git commit`（path-scoped ×3）

## 任务分配记录

本轮**无任务分配**。本人在 router 域独立推进，改动只落 `router_caf_ext*.mbt` + router `.mbti`（均无并发 WIP）。

## 遗留风险

- **§2.3 server 接线仍未做**（`model_router_ops.mbt` 4/9）。
- **全仓编译被并发 WIP 阻塞**：`github_sync_wbtest.mbt` L250 `github_queue_append` 参数 mismatch
  （`github_sync.mbt` 已改 8 参，wbtest 仍 6 参）—— **并发 agent 需同步**，R42 不代修。
- **接线时需用归一化**：`caf_feature_hash(caf_normalize_context(ctx))`，否则碎片化（caf_norm_3 已锁）。
- **中文 context 未做 lowercase**（`caf_normalize_context` 只处理 ASCII A-Z）；中文本身无大小写，但
  全角/半角空白未覆盖，若接线遇此类输入可再扩。

## 后续建议

1. **R43 首选**：§2.3 接线（`model_router_ops.mbt` 释放后），接线点直接用 `caf_feature_hash(caf_normalize_context(ctx))`。
2. **R43 备选**：提醒者角色（`docs/2026-10-12-fist-mbt-reminder-role-plan.md`）——R42 未评估。
3. **R43 备选 2**：等并发 WIP 收口后跑一次全仓 `moon test --target js`，确认 `github_sync_wbtest` 已同步。
4. **持续观察**：`issue_scan` + `boundary_probe` 双轨的**真正产出**是「防御缺锁才补锁」，
   而非 finding 本身；高价值 finding 需人工复核真源。

## 来源

- `boundary_probe`（rule=string-index，`model_router.mbt` L487）
- 真源复核：`src/router/model_router.mbt` L535-554（`pool[idx]` 双取模）
- 真源：`src/router/router_caf.mbt` L198-207（`caf_feature_hash`）
- 新增：`src/router/router_caf_ext.mbt`（`caf_normalize_context` + `is_ws_byte` + `to_lower_byte`）
- 新增锁：`src/router/router_caf_ext_wbtest.mbt`（`caf_norm_1~4`）
- 设计文档：`docs/2026-10-15-fist-mbt-caf-p2c-wiring-design.md` §2.3
