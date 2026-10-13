# 2026-10-12 502 健康探测报告

## 结果摘要

补 ofm 通道 JSON 容错缺口第四块（纯计算面，可安全落地）：

- **`filter_unhealthy_models(models: Array[OfmModel], unhealthy_ids: Array[String]) -> Array[OfmModel]`**：从模型清单中过滤掉已知频繁 502 的模型
- **`is_model_unhealthy(model_id: String, unhealthy_ids: Array[String]) -> Bool`**：判断单个模型是否在黑名单中

**设计约束**：
- 纯计算零 IO，全部落在 `src/router`（我的文件范围）
- `src/server` 收口后，在路由决策前调用：
  1. 从配置/观测面读取 `unhealthy_ids` 黑名单
  2. 调用 `filter_unhealthy_models` 过滤模型池
  3. 用过滤后的模型列表做路由决策
- **精确匹配**：只匹配完整模型 id，不误伤前缀/子串
- **空黑名单原样返回**：调用方未配置黑名单时不误伤任何模型

## 资源消耗

- 开发：1 个文件修改（`ofm_models.mbt`）+ 1 个测试文件追加 + 1 个 .mbti 接口更新
- 测试：router 包 84/84 全绿（含 `ofm_m_6` / `ofm_m_7` / `ofm_m_8`）

## 任务分配记录

- 本会话：实现健康探测函数 + 白盒锁 + 测试验证 + 提交推送
- 并发会话：未涉及（`src/server/*` 未动）

## 遗留风险

1. **`src/server` 调用未接**：`filter_unhealthy_models` / `is_model_unhealthy` 需在 `model_router_ops.mbt` 的路由决策前调用，该文件属并发会话范围，待收口后补。
2. **GitHub Release v0.3.8 未产出**：`release.yml` CI 构建红，根因疑似 `MOON_VERSION: latest` 与本地验证的 `0.1.20260920` 不一致。

## 后续建议

1. 并发会话收口后，在 `model_router_ops.mbt` 的模型路由决策前接入健康探测：
   ```moonbit
   let healthy_models = filter_unhealthy_models(all_models, config.unhealthy_ids)
   // 用 healthy_models 做路由决策
   ```
2. `release.yml` 钉 `MOON_VERSION: 0.1.20260920`。

## 超额内容

- 无

## 来源

- `src/router/ofm_models.mbt`（新增 `filter_unhealthy_models` + `is_model_unhealthy`）
- `src/router/ofm_models_wbtest.mbt`（`ofm_m_6` / `ofm_m_7` / `ofm_m_8` 白盒锁）
- `memory/2026-10-12.md`「目标完成度」更新
