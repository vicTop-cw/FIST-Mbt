# 2026-10-12 ofm 非 JSON 二次重试策略报告

## 结果摘要

补 ofm 通道 JSON 容错缺口第三块（纯计算面，可安全落地）：

- **`should_retry_on_invalid_json(resp: OfmChatResponse) -> Bool`**：只在回体不可解析（`error_type == "unparseable"`）时返回 `true`
- **`append_retry_prompt(body: String) -> Result[String, String]`**：在请求体 messages 末尾追加 system 提示「请只返回合法 JSON，不要添加 markdown 围栏或其他格式」，用于二次重试时引导模型输出可解析的 JSON

**设计约束**：
- 纯计算零 IO，全部落在 `src/router`（我的文件范围）
- `src/server`（并发会话文件）收口后，在 `model_router_ops.mbt` 的 `executor_run_impl` 中：
  1. 第一次调用 `ofm_chat_http` 后解析响应
  2. 如果 `should_retry_on_invalid_json(resp)` 为 true，则用 `append_retry_prompt(body)` 构造新请求体
  3. 二次调用 `ofm_chat_http`
  4. 二次失败则放弃，返回错误

- **fail-closed**：`append_retry_prompt` 对非法输入（非 JSON / 非对象 / 无 messages 数组）返回 `Err`

## 资源消耗

- 开发：1 个文件修改（`ofm_chat.mbt`）+ 1 个测试文件追加 + 1 个 .mbti 接口更新
- 测试：router 包 81/81 全绿（含 `ofm_c_9` / `ofm_c_10`）

## 任务分配记录

- 本会话：实现重试策略函数 + 白盒锁 + 测试验证 + 提交推送
- 并发会话：未涉及（`src/server/*` 未动）

## 遗留风险

1. **`src/server` 调用未接**：`should_retry_on_invalid_json` / `append_retry_prompt` 需在 `model_router_ops.mbt` 的 `executor_run_impl` 中调用，该文件属并发会话范围，待收口后补。
2. **路由健康探测（502）**：仍需在 `src/server` 面实现已知 502 模型的规避逻辑。
3. **GitHub Release v0.3.8 未产出**：`release.yml` CI 构建红，根因疑似 `MOON_VERSION: latest` 与本地验证的 `0.1.20260920` 不一致。

## 后续建议

1. 并发会话收口后，在 `model_router_ops.mbt` L495 附近接入二次重试逻辑（伪代码）：
   ```moonbit
   let call_res = ofm_chat_http(url, body, timeout_ms)
   // ... 解析 resp ...
   if should_retry_on_invalid_json(resp) {
     let body2 = match append_retry_prompt(body) {
       Ok(b) => b
       Err(_) => // 回原始错误
     }
     let call_res2 = ofm_chat_http(url, body2, timeout_ms)
     // 用第二次结果覆盖
   }
   ```
2. `release.yml` 钉 `MOON_VERSION: 0.1.20260920`。

## 超额内容

- 无

## 来源

- `src/router/ofm_chat.mbt`（新增 `should_retry_on_invalid_json` + `append_retry_prompt`）
- `src/router/ofm_chat_wbtest.mbt`（`ofm_c_9` / `ofm_c_10` 白盒锁）
- `memory/2026-10-12.md`「目标完成度」更新
