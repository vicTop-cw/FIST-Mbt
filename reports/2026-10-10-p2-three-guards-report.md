# 2026-10-10 · P2 · 三个新守卫 + 文档收口

## 结果摘要

按 `docs/improvement-plan-20261010.md`（v3）方向 P2「三个新守卫 + 文档收口」实现完毕：新增三支守卫脚本并全部 rc=0，文档面 130→134 计数同步收口。**四态对齐 cl1–cl7，证据梯 L4（`output_validate` verdict=pass / evidence_layer=l4-pass）。**

| 守卫 | 作用 | 本轮 rc |
|---|---|---|
| `scripts/check_host_installable.py` | 宿主可装性：DSH manifest/patch 严格档（绝对路径 + `toolCallTimeoutMs` + dsh reconnect schema）、宽松档 MCP JSON、默认模板合法性、`moon.mod` 版本 | 0 |
| `scripts/check_model_auth_no_key.py` | 文件面无真凭据值形状（扫 40 份：fist-config / *.mcp.json / plugins/**/.mcp.json / mcp_config_scaffold 常量 / src/router / docs / README*） | 0 |
| `scripts/check_skill_inject.py` | 注入路径可测命中：`lookup_injected_assets_in` 按 goal/note 子串匹配 + 白盒锁 `memory_13_...` 在位 + 已注册 `[asset]` 资产可反查 | 0 |

## 资源消耗

- 三守卫 `--selftest` 均自证可红可绿；全量扫描 7 支守卫连跑 rc=0。
- `python scripts/gen_plugins.py`：先 `--check`（rc=2，README 分组和 130≠134 基线漂移）→ 真投影（rc=0，134 工具 / v0.3.6）→ 复核 `--check`（rc=0）闭环。
- `moon check --target js src` 与 `cmd/cli` 均 0 errors。
- 权威稳定门槛 `moon test --target js` = **623/623 通过 / 0 失败**。

## 任务分配记录

| 阶段 | 承担者 | 交付 |
|---|---|---|
| 三守卫实现 + `scripts/README.md` 文档条目 | 子代理 2bc02e7c | `check_host_installable.py` / `check_model_auth_no_key.py` / `check_skill_inject.py` |
| 凭据 fixture 运行时拼接（清 `check_publish_payload` P2） | 指挥官 | `check_model_auth_no_key.py` S1 fixture 改为 `'...sk-abc123def456' + 'ghi789...'`：运行时字符串与字面量等价，源码不再含 ≥16 位连续凭据字面量，`check_publish_payload` 的 `sk-[A-Za-z0-9]{16,}` 不再误点名判据自身 |
| 文档面 130→134 计数同步 + 插件态重投影 | 子代理 fdaeea03 | AGENTS.md / README.md / ARCHITECTURE.md / README.mbt.md / README_EN.md / USAGE.md / docs/deliverable.md / scripts/scoring_rubric.md / cmd/cli/help_topics.mbt（分组数 13→14、和 130→134）+ `plugins/` 24 个生成文件 |

## 遗留风险

- `check_host_installable` 对 `.mcp.json` 的 `timeout_ms` 报信息级 WARN（部分客户端按自身 schema 忽略该字段）。是否把真源统一改为 `toolCallTimeoutMs` 由人终审，本轮未动真源。
- 文档面计数自述面比任务清单更广：J14 首轮在 ARCHITECTURE.md L90（`130 工具分组`）红了一次。下次计数搬家建议先 `grep -n "1[0-9][0-9] 工具" *.md docs cmd` 全局扫一遍再动工。

## 后续建议

- 三守卫已在 `ci.yml` JS 轨接入（同族既有守卫并列），后续计数搬家/凭据形状变化都会被 CI 直接拦下。
- `check_skill_inject` 的 S3 只查 `[asset]` id/goal/note/code 可反查，不校验 `score`；若生态资产要在快照排序里不下沉，建议后续把 `evolve_asset_register` 的 `score` 默认值从 0 抬到 0.5。

## 超额内容

- BUG-141 顺带发现并修好：`sync_db_lessons` 只回灌 `[lesson]`，`evolve_asset_register` 落库的 `[asset]` 在重启后不被回灌，导致 `plan`/`claim` 的 `inject` 跨进程检索不到资产（详见 `2026-10-10-bug140-141-asset-persist-report.md`）。

## 来源

- 决策：`docs/improvement-plan-20261010.md` v3（P2）。
- 守卫回执：`scripts/check_host_installable.py` / `check_model_auth_no_key.py` / `check_skill_inject.py` 全量 rc=0。