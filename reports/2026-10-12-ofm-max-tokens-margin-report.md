# 2026-10-12 ofm max_tokens 余量预留报告

## 结果摘要

补 ofm 通道 JSON 容错缺口第二块（可安全落地的纯计算面）：
`ofm_reserve_max_tokens(limit, margin)` 从模型硬上限预留余量，避免回体被 token 天花板截断成半截 JSON。

- **新增 pub fn**：`src/router/ofm_chat.mbt` `ofm_reserve_max_tokens(limit: Int, margin: Int) -> Result[Int, String]`
- **白盒锁**：`src/router/ofm_chat_wbtest.mbt` `ofm_c_8_max_tokens 余量预留_不越硬上限`
- **测试**：router 包 79/79 全绿；全量 `moon test --target js -j 1` = 803 total / 802 passed（唯一失败在并发会话新加 `store_assistant_test.mbt:123`，与 Star 门/ofm 无关）
- **提交**：`8d45f9d`，已 push origin + gitcode

## 资源消耗

- 开发：1 个文件修改 + 1 个测试文件追加 + 1 个 .mbti 接口更新
- 测试：2 次 router 包测试 + 1 次全量测试
- 磁盘：无额外占用

## 任务分配记录

- 本会话：实现 `ofm_reserve_max_tokens` + 白盒锁 + 测试验证 + 提交推送
- 并发会话：未涉及（`src/server/*` 未动）

## 遗留风险

1. **非 JSON 二次重试**：仍需在 `src/server/ofm_http_{js,native}.mbt` 实现 HTTP 层重试（并发会话文件，待收口后补）。
2. **路由健康探测（502）**：同上，需改 `src/server` 面。
3. **GitHub Release v0.3.8 未产出**：`release.yml` CI 构建红（`build-js` / `build-native-linux` / `build-native-windows` 全红），根因疑似 `MOON_VERSION: latest` 与本地验证的 `0.1.20260920` 不一致。建议钉版本或拿 GitHub token 读日志确认。

## 后续建议

1. 并发会话收口后，在 `src/server/ofm_http_js.mbt` 的 `executor_run_impl` 里接入 `ofm_reserve_max_tokens`（把模型硬上限传给 HTTP 层，请求前预留余量）。
2. 同一处加非 JSON 回体的二次重试（`response_format` 已带，但网关偶发仍可能回非 JSON）。
3. `release.yml` 钉 `MOON_VERSION: 0.1.20260920` 或取失败日志后修复 CI。

## 超额内容

- 无

## 来源

- `src/router/ofm_chat.mbt`（新增 `ofm_reserve_max_tokens`）
- `src/router/ofm_chat_wbtest.mbt`（`ofm_c_8` 白盒锁）
- `memory/2026-10-12.md`「四发」段
