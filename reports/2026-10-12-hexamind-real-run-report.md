# HexaMind 六元引擎 · 真模型回体实测报告

- 日期：2026-10-12（用户重启 DSH 后补跑）
- 任务：把 HexaMind 端到端闭环里的**模型回体换真**——`hat_run` → 3 次 `executor_run(ofm)` 真调用 → `hat_merge` 出真分歧+收敛+裁决报告
- 前置：上一份报告（`2026-10-12-hexamind-e2e-report.md`）卡在 DSH 网关 500 `atomcode is not defined`；用户重启 DSH 后补丁加载
- 版本：R119（工作树含未提交 hook 态）
- 结果：**HEXAMIND-REAL PASS**（第一次真跑全通）；同时抓到 ofm 通道一条真实健壮性缺口

---

## 1. 结果摘要

### 1.1 网关状态变化（用户重启后）

| 项 | 结论 |
|---|---|
| DSH 进程 | 旧 PID 27904 → 新 PID **2832**（start 17:11:26） |
| `adapter.js` 补丁 | `const atomcode = isAtomcodeEntry(entry)` 生效，**500 `atomcode is not defined` 消失** |
| 模型级故障 | `mimo-v2.6-flash-free` 直连真回体 `[**2**]`；但 **`ling-3.1-flash-free` 直连 502 `Upstream request failed: Endpoint is unavailable`**（短/长 prompt 都 502，5 连发全 502） |

关键发现：**通道级 500 已修，但 ling 模型的上游端点不可用（模型级故障）**。路由默认挑 free 池第一个 = ling，等于默认踩坑。故用 `FIST_HAT_MODEL=mimo-v2.6-flash-free` 强制钉一个真回体模型（免费，避掉付费池）。

### 1.2 真跑闭环（第一次，成功）

```
hat_run(hats=[black,yellow,green])
  → 3 任务 → 各 1 次 executor_run(ofm, model=mimo-v2.6-flash-free) 真回体
  → hat_merge 出真裁决报告
```

| 单元 | 判决 | 置信度 | 证据要点 |
|---|---|---|---|
| 破壁者 wallbreaker | **reject** | 0.78 | 9 条构造性反例：E1 边界加权 0.499 vs 0.501 一次重采样即翻转 / E4 关键路径 6d 组合恶化 / E5 GDPR Art.22 自动化决策条款 / **E8 自陈"本次评审环境的代码/配置检索工具不可用……上述 evidence 均为第一性原理推导，尚无实测数据支撑"**（模型自己把证据梯说清了） |
| 掘金者 golddigger | **pass** | 0.78 | 议题前提（内核空缺即收益位）/ 六元结构输出一致→可解释可复用 / 默认化正反馈链 |
| 新星 nova | **pass** | 0.83 | 输出契约逐项给满（40 条替代方案 + 18 条想象路径）/ 覆盖默认/非默认/条件默认/取消默认四象限 |

**`hat_merge` 收敛读数**：`status=partial`（部分收敛）、`terminal_gate=user`、`rate=0.667`（agree=2/3，阈值 0.6）、`should_iterate=True`、round=1/2。

**3 条分歧（程序化提取，零 LLM 自评）**：

| 类型 | 左 | 右 | 严重度 | 说明 |
|---|---|---|---|---|
| `verdict_conflict` | wallbreaker | golddigger | 3 | reject 对冲 pass |
| `verdict_conflict` | wallbreaker | nova | 3 | reject 对冲 pass |
| `evidence_mismatch` | golddigger | nova | 1 | 论据重合度 0 < 0.25（各说各话） |

输出完整 Markdown「HexaMind 六元裁决报告」（含收敛读数/各单元结论表/分歧清单/已选六元 [wallbreaker, golddigger, stargazer]）。

**结论：P0 派发 + P1 收敛 + 真模型回体全闭环打通。**

## 2. 健壮性缺口（真 bug，第二次跑抓到）

同样的脚本第二次跑，2/3 帽子失败：

- `wallbreaker` / `nova`：`ok=False`、`failure_kind=NETWORK_ERROR`、`error=OFM 回体不是合法 JSON（可能被网关换过）`
- `golddigger`：回体是**被 `max_tokens` 截断的半截 JSON**（`{"verdict":"pass","confidence":0.74,"benefits":[…` 无闭括号），我侧解析也失败

**本质**：`executor_run(ofm)` 硬性要求回体是合法 JSON（fail-closed 拒绝，不静默取数），而**模型偶发不产严格 JSON**时直接判失败——ofm 通道**没有** `response_format=json_object` 强制、没有 max_tokens 余量保护、没有非 JSON 重试/修复策略。这是本仓真实弱点，不是外部问题。

**建议后续**：
1. `executor_run(ofm)` 请求体带 `response_format={"type":"json_object"}`；
2. `max_tokens` 给足（当前 schema 要求多项证据，2048/4096 可能不够）；
3. 回体非合法 JSON 时做一次"请只返回合法 JSON"的二次重试（带修复提示）；
4. 解析层容忍前后废话与截断。

## 3. 资源消耗

- 真 LLM 调用：`mimo-v2.6-flash-free`（免费）——成功跑 3 次 + 失败跑 3 次 = **共 6 次免费调用**，零付费消耗（强制免费模型，避掉 paid_pool 的 wallbreaker 会路由到付费池）。
- 计算：多次 `moon build`（既有）+ 若干次 E2E/探针脚本。
- 网络：多次直连 `http://127.0.0.1:18899/v1/chat/completions`（成功 + 502 + 健康复测）。
- 磁盘：新增 `temp/hexamind_real_run.py`、`temp/hexamind_real.db`；未成功落盘 `temp/hexamind-real-verdict.md`（该次跑 rc=1 早退），成功那次读数以本报告为准。

## 4. 任务分配记录

- 未拆子代理（沿用上一轮判断：单一自包含 E2E 脚本，避免与并发会话文件作用域交叉）。
- 执行者：本会话直接完成；终审：本人（真起 server + 真发 6 次模型调用 + 真看回体，不靠自述）。

## 5. 遗留风险

1. **ofm 通道无 JSON 容错**（§2）：模型输出不稳定时 P1 整条打停。已列修复建议，未在本轮实现（涉及 `src/executor/ofm_*.mbt` 改动，属新改动面）。
2. **`ling-3.1-flash-free` 上游 502**：外部模型级故障，非本仓可控；路由默认 pick 第一个免费模型即踩中它——建议路由层加"上游可用性探测"或把默认游标避开故障模型（可选新特性）。
3. **`server.mbt` hook 仍未提交**：并发会话持该文件；本报告证据基于工作树态（tools/list=150），入库后需再验。
4. **真跑证据未落盘**：成功那次的 `temp/hexamind-real-verdict.md` 因失败跑覆盖逻辑/早退没落成；如需留档可用 `FIST_HAT_MODEL=mimo-v2.6-flash-free python temp/hexamind_real_run.py` 重跑（会再产一份新证据）。
5. **既有红面未动**：同前（`check_plugin_sync`/`check_entry_paths`/`check_badge`/`check_test_sync`/`check_release_asset_names`/`check_scripts_index`/J15 设计文档）。

## 6. 后续建议

1. **优先补 ofm 通道 JSON 容错**（`response_format` + 余量 + 非 JSON 重试），让 P1 对模型输出不稳有韧性。
2. 把本报告的裁决报告原文落成 `reports/…-verdict.md` 或入库 `temp/` 归档，便于复核 wallbreaker 的 E8 自陈（证据梯自我诚实）与三条分歧。
3. 入库 `server.mbt` hook 后重跑 `temp/hexamind_real_run.py` 再验一轮真回体闭环，确认 hook 未丢。
4. 考虑路由层把已知 502 的 `ling-3.1-flash-free` 降权或加健康探测，避免默认踩坑。

## 7. 超额内容

- 无超设计范围。本轮额外产出：把"外部通道已修"与"模型级故障"分开给证据（避免把 ling 的 502 误读成还没修好），并把模型偶发非 JSON 定位成本仓健壮性缺口（真 bug，非甩锅外部）。

## 8. 来源

- 代码：`src/hat/*`、`src/server/hat_hexa_tools.mbt`（R119 已提交）、`src/server/server.mbt`（hook，工作树态）、`src/executor/ofm_*`（JSON 硬门）
- 实测脚本：`temp/hexamind_real_run.py`（真回体闭环唯一入口）、`temp/hexamind_e2e.py`（dry_run 机械版）
- 网关真源：`C:\Users\victo\.dsh\our-free-model\settings.json`（forwardKey/端口）、`…/src/adapter.js`（`atomcode` 修复已加载）
- 回体证据：`executor_run(ofm, model=mimo-v2.6-flash-free)` 真回体（wallbreaker=reject 0.78 / golddigger=pass 0.78 / nova=pass 0.83）
- 收敛证据：`hat_merge` 回执 `status=partial`、`rate=0.667`、3 条分歧、Markdown 裁决报告
- 前置回归基线：本会话实测 `moon test --target js -j 1` = 796/796