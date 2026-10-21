# 2026-10-13 ofm 七发收口 · 二次重试 + 502 黑名单接线报告

## 结果摘要

目标「① ofm 通道 JSON 容错缺口 + 路由健康探测（避开已知 502 模型）；② Star 门默认开启」**七发全链路收口**：

1. **非 JSON 二次重试（调用点接线，ebf3516）**：`src/server/model_router_ops.mbt` 的 `ofm_execute_http` 在回体判 `unparseable`（`should_retry_on_invalid_json`）时，用 `append_retry_prompt(body)` 重写请求体（messages 末尾追加 system「请只返回合法 JSON，不要添加 markdown 围栏或其他格式」）**重发一次**；二次 `(http_status, resp)` 覆盖首次；`append_retry_prompt` 自身失败则原样保留首次错误（fail-closed 不吞）。
2. **502 路由健康探测（调用点接线，ebf3516）**：`src/router/model_router.mbt` 的 `pool_pick`/`pick`/`pick_inner` 新增可选参数 `unhealthy_ids`（默认 `[]` 零回归），环形扫描时跳过黑名单模型；`model_route_impl` 经新 helper `mr_unhealthy_models()` 读 server 进程环境变量 `FIST_OFM_UNHEALTHY_MODELS`（逗号分隔、trim、精确匹配、空=不误伤）。
3. 此前六发已落地的配套：`response_format=json_object` 恒带（d2dd3b5）、`ofm_reserve_max_tokens` 余量（8d45f9d）、重试策略纯函数（32da8ed）、黑名单过滤纯函数（3be67c9）、Star 门发布模板默认公钥（d2dd3b5，`.mcp.example.json` L15）。

**判绿（金条八实测）**：
- `moon test --target js -j 1` = **Total tests: 811, passed: 811, failed: 0**（上轮唯一失败——并发会话 `store_assistant_test.mbt:123`——已自行转绿；基数 803→811）。
- router 包 **86/86**，含新锁 `rt_health_1`（黑名单跳过 + 空名单零回归 + 全黑显式不可用）与 `rt_health_2`（精确匹配不误伤前缀）。
- 本地命令重建重装修复后的冒烟：`fist version` / `fist-mbt version` 均 **`FIST-Mbt v0.3.8`**（产物含七发代码）。

## 资源消耗

- 5 次测试运行（router 3、router+server 1、全量 1）、1 次全量构建 + ESM 补丁 + 重打包 + 重装修补。
- 磁盘 ENOSPC（C 盘 0 空闲，git 写对象失败 1 次）→ 临时重定向 `TEMP/TMP` 到 E 盘后恢复（工作目录本就在 E 盘，579GB 空闲）。

## 任务分配记录

- 本会话（指挥官亲自收口 4 处最小 hunk）：`src/router/model_router.mbt`（+29）、`src/router/model_router_wbtest.mbt`（+45）、`src/router/pkg.generated.mbti`（接口行）、`src/server/model_router_ops.mbt`（+59）。
- diff 逐 hunk 核验：提交面只含本任务改动；并发会话其余 26 个未提交 `src/server` 文件一律未 add。
- `src/server/model_router_ops.mbt` 属并发会话活跃面：goal round 6 向 owner 申报编辑预案（边界=仅 OFM/route 段、备份、改后跑测试），round 7 继续指示推进后按预案执行；动手前确认该文件与 origin 同步、无未提交冲突。

## 遗留风险

1. **GitHub Release v0.3.8 未产出**：`release.yml` CI 三臂红（`build-js` 红在 `Build JS target`），本地同命令全绿 ⇒ 疑似 `MOON_VERSION: latest` 与本地钉版 `0.1.20260920` 的工具链回归差；无 GitHub token 拿不到失败日志（匿名 403）。本地命令不受影响（`-LocalZip` 已装含七发代码的产物）。
2. **502 黑名单靠 env 手工给**：`FIST_OFM_UNHEALTHY_MODELS` 无人自动喂名单；「失败 N 次自动拉黑」可挂既有 `circuit_fail` 熔断链，留后续轮次。
3. **Star 门私钥 secret**（owner 必做，仍有效）：`ED25519_PRIVATE_KEY_HEX` 未设进仓库 secrets 前，attestation 无法签发，启用门的部署会被 fail-closed 锁住免费池（设计如此）。
4. 并发会话面（README R13 字面量、docs/*-20261012.md 的 J15/payload 红）仍归其收口。

## 后续建议

1. release.yml `MOON_VERSION` 钉 `0.1.20260920` 后重推 tag（或由 owner 供 token 先读日志定根因）。
2. 若要自动化拉黑：在 `executor_run` 的 ofm 失败分支调 `circuit_fail`，Half-Open 探测恢复即自动解禁——名单语义与 `unhealthy_ids` 直接兼容。
3. 文档面（README 安装线资产名）待并发会话收口时一起对齐到已发布的真实资产。

## 超额内容

- 顺带修复 memory 表格里一处行粘连（六发写入时把两行并成一行）。
- 本地资产 zip 重建为含七发代码版本（`_release/fist-mbt-js-v0.3.8.zip`，gitignored）。

## 来源

- `src/server/model_router_ops.mbt`（二次重试 L546-572、`mr_unhealthy_models()` L116-144、pick 传参 L212/216）
- `src/router/model_router.mbt`（`pool_pick`/`pick`/`pick_inner` 的 `unhealthy_ids`）
- `src/router/model_router_wbtest.mbt`（rt_health_1/2）
- 前序提交：d2dd3b5 / 8d45f9d / 32da8ed / 3be67c9 / ebf3516
- `memory/2026-10-12.md`「七发」段
