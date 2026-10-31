# 2026-10-31 · explore-r2（Round B）· 拆单记账 + windows 臂修复 + 网关 --raw + 路由开启 + BUG-530

## 结果摘要
4 单元并发完成，4/4 终审通过；新立 BUG-530 一单（播种不落盘）。

| 单元 | 内容 | 终审证据 |
|---|---|---|
| T0.1.1 | BUG-523 拆单对账（账本追记 + 527 锚点交叉引用 ×3） | diff 17+/1-（唯一改动行系原句保留+关系注另起）；统帅裁决：BUG-133 保持 FIXED，拆单以 523 追记为权威 |
| T0.2.1 | BUG-513 windows 臂修复（release.yml 四处） | YAML ok；`check_release_asset_names` 主检查 PASS rc=0；docface 自检+主检 rc=0 |
| T0.3.1 | `fist.py --raw` 旗标 | --selftest PASS；端到端：此前必败的 config_json 播种经网关直达并正确选中池内模型 |
| T0.4.1 | R9 变异夹具脱锚修复（单形状合成夹具） | --selftest rc=0（R9 反解 ×6）+ 主检查 rc=0 |

## BUG-513 修复要点（release.yml 四处）
1. `MOON_VERSION: 'latest'` 弃用 → meta 作业从 toolchain.json 读出经 outputs 下发（不写死版本数字）；
2. windows 安装步换 ci.yml 已验证的 `irm …/powershell.ps1 | iex` 形状 + PATH 双行（原 curl install/windows 实测 403）；
3. build 步照抄 linux 臂（Reapply BUG-133 + scoped `moon build --target native cmd/cli`）；
4. continue-on-error 保留并注明「527 治本后摘除」。

## 终审抓到的偏差（如实记）
- fix-r9-fixture 自述「R9 自动计 ×8」，反解实读 **×6**——反解为准，属成员自述滞后，无代码问题。
- ledger-523 diff 有 1 行"删除"，实为原句保留+关系注另起（内容零丢失），判定合规。

## 新立 BUG-530（OPEN）
`model_route(config_json=…)` 声称播种池定义但 `persisted=false`、`model_router_status` 读回空池 ⇒ executor_run 空 model 永远拿默认池（缺 provider/ 前缀被 relay 拒 400）。修复动线在 `src/router`，等并发 WIP 收口进 Round C。

## 遗留风险 / 后续建议
1. 提交面（全部就绪、等 `run_guards.py` 解禁同批）：本轮改动文件 = `memory/bugs.md`（523 拆单+530 新立）、`.github/workflows/release.yml`、`scripts/fist.py`、`scripts/check_release_asset_names.py`、`scripts/check_usage_tool_count.py`（Round A 遗留，需 case 注册）、`USAGE.md`、`scripts/README.md`、`scripts/check_selftest_hermetic.py`、`scripts/blackbox/e2e_acceptance_recheck.py`、4 份插件态重投影、`.mcp.json`（gitignored 不入库）、reports/memory 两个 md。
2. Round C（等 `src/**` 解禁）：BUG-527 治本（13 份库包摘 link）→ BUG-530 修复（播种落盘）→ BUG-523 CI 复绿验证 → M1 面板。
3. R9 判据本体是文件级"GITHUB_PATH 有无"——未来新增第三种写入形状会再脱锚，格子反解机制会当场喊（成员风险①②已采纳）。

## 来源
- FIST 闭环：ns `explore-r2` T0 四单元全已完成
- 并发纪律：全程避开 `src/**`、`scripts/run_guards.py`、`cmd/cli`（另一 agent WIP 占用中）
