# OFM 真实模型清单（P0.2 拉取记录）

- **日期**：2026-10-12
- **拉取方式**：`GET {FIST_OFM_ENDPOINT}/models`，`Authorization: Bearer $FIST_OFM_KEY`
- **服务端实测**：HTTP **200**（此前无 key 时同请求回 **401**，实测印证
  `ofm_failure.mbt` 里「401 → InvalidCredential」的归因）
- **回体形状**：`{ "object", "data": [ { "id", "owned_by" }, … ] }`（OpenAI 兼容；
  `parse_ofm_models` 解析的就是这一形状）
- **结果**：`owned_by = our-free-model` 的 8 个 free 模型

## 8 个真实模型 ID（已写进默认 free_pool）

| # | `id` | `owned_by` |
|---|---|---|
| 1 | `ling-3.1-flash-free` | our-free-model |
| 2 | `mimo-v2.6-flash-free` | our-free-model |
| 3 | `muse-spark-1.2-contributor-free` | our-free-model |
| 4 | `muse-spark-1.3-contributor-free` | our-free-model |
| 5 | `nemotron-3.5-lightning-free` | our-free-model |
| 6 | `step-5-preview-free` | our-free-model |
| 7 | `longcat-2.5-preview-free` | our-free-model |
| 8 | `space-bunny-free` | our-free-model |

## lane 怎么标的

- 全部标 `lane="ofm"`：把「同属外部 OFM 通道」这一**已核实事实**标出来。
- **不是**从 id 猜 SenseNova 的 zen/kilo/eac——那才是真的在猜；`lane` 的语义是
  「未知就不要默认路由」，这里「ofm」是拉取清单时就确定的事实。
- 若将来 OFM 端点返回了明确的渠道字段，再按**服务端给的值**细化；在那之前不臆测。

## 代码侧对应

- 默认池：`src/router/model_router.mbt` 的 `RouterConfig::default()`（8 条，`lane="ofm"`）。
- 白盒锁：`src/router/router_config_wbtest.mbt` 的 `cfg_ofm_6`（逐条对上 + lane 非空 + tier=Free）。
- 解析层：`src/router/ofm_models.mbt` 的 `parse_ofm_models`（OpenAI 兼容 `/v1/models` 解析）。
- 拉取命令：`USAGE.md` §6.15「模型路由 · OFM 外部服务接线」。

## 复现

```pwsh
$env:FIST_OFM_ENDPOINT = "<你的端点>"
$env:FIST_OFM_KEY = "<你的 key>"
Invoke-RestMethod -Uri "$env:FIST_OFM_ENDPOINT/models" -Headers @{ Authorization = "Bearer $env:FIST_OFM_KEY" }
```

> 密钥纪律不变：key 只从**环境变量**读，`RouterConfig` 无密钥字段，配置投影进
> skill/插件目录不可能带出密钥。
