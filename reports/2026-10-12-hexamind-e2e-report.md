# HexaMind 六元引擎 · 端到端实测报告

- 日期：2026-10-12
- 任务：验证 HexaMind 六元自驱决策引擎端到端（用户指示：真跑验证，路由不通就换便宜模型）
- 方法：真起 MCP server（工作树含 hook），走真 MCP 协议，`temp/hexamind_e2e.py` 驱动四阶段
- 版本：R119（工作树未提交 hook 态）
- 结果：**HEXAMIND-E2E PASS**（fist-mbt 侧全通过）；唯一未跑到的真实模型回体卡在 DSH 外部插件缓存

---

## 1. 结果摘要

真协议实测四阶段，全部 PASS：

| 阶段 | 工具 | 实测结论 |
|---|---|---|
| 工具注册 | `tools/list` | **150 个工具**，`hat_run`/`hat_merge`/`hat_debate` 均已注册 → **server.mbt 那行 hook 接线生效** |
| P0 派发 | `hat_run` | 3 任务（wallbreaker=paid_pool / golddigger=balanced / nova=free_pool）+ 星核字段 + 黑↔黄辩论对 + policy(max_rounds=2/threshold=0.6) |
| 路由接线 | `executor_run(ofm, model="", dry_run)` | **路由到 `ling-3.1-flash-free`**（free tier，reason="free tier has capacity"）；dry_run 回显 URL `http://127.0.0.1:18899/v1/chat/completions` + 完整请求体，**未发任何请求** |
| P1 收敛 | `hat_merge` | `status=diverged`、`terminal_gate=user`、`should_iterate=True`、1 条分歧 `verdict_conflict`、Markdown 含「HexaMind 六元裁决报告」（rate=0.5<0.6） |
| P2 辩论 | `hat_debate` | 缺省议题（风险 vs 价值：致命缺陷与核心价值可否对冲）+ rounds=2 正常给 |
| 失败归因 | `executor_run(ofm, 真实)` | **`ok=False`、`failure_kind=UPSTREAM_DOWN`、`executed=True`、key 不回显** → fail-closed，绝不静默成功 |

**架构印证**：`ElementTask` 无 `model` 字段，只声明 `lane`（free_pool/paid_pool/balanced）+ 温度 + max_tokens + 输出契约 + `executor_hint=ofm`；真实模型由 `model_route` 按 lane 路由——正是"帽子选车道、路由选模型"的设计，用户提到的路由在这里实机跑通。

## 2. 唯一未跑通的环节（外部阻断，非本仓代码）

免费模型网关 `127.0.0.1:18899` 全部 8 个模型（ling-3.1-flash-free / mimo-v2.6-flash-free / muse-spark-1.2 / muse-spark-1.3 / nemotron-3.5-lightning / step-5-preview / longcat-2.5 / space-bunny）都回
**HTTP 500 `atomcode is not defined`**（通道级，非模型级）。

**定位（三件套）**：
1. **源码已修**：`dsh-our-free-model/src/adapter.js:218-221` 曾有注释明写
   「`atomcode` was never declared here, so every turn … died with `ReferenceError: atomcode is not defined`」，
   现已补 `const atomcode = isAtomcodeEntry(entry)`。
2. **补丁晚于进程**：adapter.js mtime = **2026-10-12 14:20:29**；DSH 主进程（PID 27904，服务 3099 GUI + 18899 网关）StartTime = **09:45:27**。
3. **结论**：DSH 启动时缓存的是**旧模块**，磁盘补丁未加载 → **重启 DSH 即生效**。

**为何未重启**：DSH web 同时服务本会话 GUI（端口 3099）与 18899 网关；重启会终结本会话。故未擅自重启，交用户决定。

## 3. 资源消耗

- **零 LLM 回体**（网关 500，未拿到任何模型输出）。
- 计算：1 次 `moon build --target js cmd/cli`（0 errors，428 warnings 既有）；4 次 `python temp/hexamind_e2e.py`（含调试迭代）；若干次 `GET/POST {ofm}/…` 探针（1 次真实 POST，其余 models/探针）。
- 网络：1 个真实 HTTP 请求（`executor_run(ofm)` 非 dry_run）打到本地网关，返回 500。
- 磁盘：新增 `temp/hexamind_e2e.py`（~190 行）、`temp/hexamind_e2e.db`、`temp/hexamind-e2e/memory/model-router-default.json`（路由状态，query-only 未记账）。

## 4. 任务分配记录

- 未拆子代理（直接执行；本任务是"跑通验证"，单一自包含 E2E 脚本，避免与并发会话文件作用域交叉）。
- 执行者：本会话直接完成；终审：本人（真起 server + 真走协议 + 真发请求，不靠自述）。

## 5. 遗留风险

1. **外部通道未通**：真实模型回体缺失，P0/P1 的"模型质量"维度未实证（只有协议+路由+fail-closed 实证）。待 DSH 重启后补一发真跑。
2. **`server.mbt` hook 仍未提交**：并发会话持该文件未提交改动；`embed_hexa_tools` 在其下一次 commit 一起出去（本实测用的工作树态，入库后需再验一次 tools/list=150）。
3. **钥匙管理**：网关钥匙取自 `C:\Users\victo\.dsh\our-free-model\settings.json` 的 `forwardKey`，经 env `FIST_OFM_KEY` 注入 server 进程，**未写进任何仓库文件**（遵循"密钥不回显/不入库"）。但该钥匙属 DSH 本体，勿外泄。
4. **既有红面未动**：同前（`check_plugin_sync`/`check_entry_paths`/`check_badge`/`check_test_sync`/`check_release_asset_names`/`check_scripts_index`/J15 设计文档）。
5. **`temp/hexamind_e2e.*` 未入库**（temp/ 通常 .gitignore），如需长期留档可搬 scripts/。

## 6. 后续建议

- **重启 DSH**（用户操作，会终结本会话）→ 免费模型网关恢复后，把 E2E 里 `hat_merge` 的 reports_json 换成真跑回体：
  `hat_run` 拿 3 个 prompt → 3 次 `executor_run(ofm)` 真跑（各自 verdict/confidence/evidence）→ `hat_merge` 出真裁决。
  一次成本约 3 次免费模型调用，建议模型固定 `ling-3.1-flash-free`（free tier）以压成本。
- **入库 `server.mbt` hook 后**重跑 `temp/hexamind_e2e.py`，确认 tools/list 仍 150、四阶段仍 PASS（防 hook 被并发会话覆盖）。
- 若网关恢复后仍 500，再抓 DSH 日志堆栈（本次 `.dsh/logs` 未命中该错误，需临时开网关侧调试日志）。

## 7. 超额内容

- 无超设计范围；本报告把"协议层/本仓代码"与"外部通道"的验证面分开给证据，避免把外部 500 误读成本仓缺陷。

## 8. 来源

- 代码：`src/hat/*`、`src/server/hat_hexa_tools.mbt`（R119 已提交）、`src/server/server.mbt`（hook，工作树态）
- 实测脚本：`temp/hexamind_e2e.py`（本报告证据唯一来源）
- 网关真源：`C:\Users\victo\.dsh\our-free-model\settings.json`（forwardKey/端口）、`…/src/adapter.js`（`atomcode` 修复）、`…/src/forward.js`（18899 路由）
- 路由真源：`executor_run` 回执 `route.decision`（free tier → `ling-3.1-flash-free`）
- 前置回归基线：本会话实测 `moon test --target js -j 1` = 796/796