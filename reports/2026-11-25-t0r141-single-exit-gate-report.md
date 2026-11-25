# T0r141 · 五：唯一出口合规自检 —— 交付报告

- 任务：`T0r141`（namespace `autoplan`，计划真源 `fist-mbt/plan/active/2026-11-25-global-net-exit.md` 工作项五）
- 执行身份：`codeforce`
- 日期：2026-11-25
- 判定口径：证据梯 ≥ L4（实测才算数），不据自述报绿

## 一、结果摘要

**结论：现场不合规（rc=1），且「唯一出口」目标在当前时刻尚未达成。**

产出物两份：

| 件 | 路径 |
|---|---|
| 自检判据 | `scripts/_single_exit_gate.py`（`_` 前缀共享模块形态，命中既有豁免规则） |
| 本报告 | `reports/2026-11-25-t0r141-single-exit-gate-report.md` |

判据对三面观测取并集 + 白名单断言 + api-key 匿名档强制检查：

```
python scripts/_single_exit_gate.py            # rc: 0 合规 / 1 不合规 / 2 判据无法自证
python scripts/_single_exit_gate.py --selftest # 29 格含 2 个变异对照
```

### 实测读数（2026-11-25 本机真跑）

| 面 | 计数 | 端口 |
|---|---|---|
| `tunnels.json` 台账 | 6 | 18640, 18641, 18643, 18644, 18645, 18649 |
| 凭据残留 | 9（含 1 条测试产物） | 18640/18641/18643/18644/18645/18649/18653/18651 + `-`（临时凭据） |
| 活进程 | 7 | 18699, 18640, 18641, 18643, 18644, 18645, 18649 |
| **边缘注册证据** | **7** | 18640, 18641, 18643, 18644, 18645, 18649, **18653** |

**并集 = {18640, 18641, 18643, 18644, 18645, 18649, 18651, 18653, 18699}**，白名单 `[18654]`
⇒ 违例 9 个端口，`rc=1`。

### 关键判定（三条验收逐条）

| 验收条 | 现状 | 判定 |
|---|---|---|
| ①映射集合 == {fist-auto}（即 18654） | 并集 9 个端口，仅 18654 缺席 | **不满足** |
| ②api-key 鉴权生效 | 18654 无人监听（`WinError 10061`）；既有 OFM 受理器匿名档 `/v1/models` 一律 HTTP 401（拒匿名） | **目标端点未起；既有面鉴权本身有效** |
| ③其余 8 服务端口公网侧不可达 | 7 条隧道日志均含 `Registered tunnel connection`（边缘真收）；18651/18699 的凭据是 `%TEMP%\credtest.json` 测试产物、无注册记录 | **不满足**（7 条真对外） |

> 口径说明：本机 `ATOMCODE_PROXY_MODE=no_proxy`，直连 trycloudflare 公网主机名回 `HTTP 000`
> ⇒ **公网可达性无法从本机出网验证**（环境限制，非结论）。判据因此改以**边缘注册证据**
> （日志 `Registered tunnel connection`）作为「这条映射真的被 CF 边缘接受」的 L4 依据，
> 而不是用「进程活着」代替——后者在 `--protocol http2` 形状下会打印 help 后空转。

## 二、证据

### 2.1 活进程（PowerShell `Get-CimInstance Win32_Process`）

```
cloudflared.exe 42536  tid=64e15197-16b8-41e4-8ced-28378a83d015  port=18699
cloudflared.exe 37868  tid=c7b52290-4bba-4f30-bcf2-90ca9742f658  port=18651
cloudflared.exe 53704  tid=bc24ae3f-67cc-4fbe-a3b0-00d00318c97d  port=18640
cloudflared.exe 14268  tid=16d3a427-0d50-489f-b5cc-f33caa778313  port=18641
cloudflared.exe  9984  tid=178c180d-40d9-416e-8223-0d101a391cbd  port=18643
cloudflared.exe 14000  tid=ff288279-cd0b-4b2f-b6d3-9a36c3a71be6  port=18644
cloudflared.exe 39672  tid=bc4e337d-c36f-4013-b190-c3c68f92aa73  port=18645
cloudflared.exe 43040  tid=b0157fdb-5eb5-4c85-a0b9-7d64a14cd5aa  port=18649
```

`tasklist /FI "IMAGENAME eq cloudflared.exe"` 独立复核同 8 行（pid 全同）⇒ 进程面非单点来源。

### 2.2 台账 `.fist-mbt/data/tunnels.json`

6 条，字段齐全（`url`/`hostname`/`backend_port`/`pid`/`tunnel_id`/`cred_file`/`log`/`started_at`），
`started_at` 集中在 `2026-11-25T21:04:06 ~ 21:04:36`（本轮并发 lane 新建，不是历史遗留）。

### 2.3 边缘注册证据 `.fist-mbt/data/tunnel-logs/*.log`

```
grep -ic "Registered tunnel connection" tunnel-*.log
→ 18640:4  18641:4  18643:4  18644:4  18645:4  18649:4  18653:4   （7 份有）
  18651 无对应注册日志；18699 无日志文件
```

日志头部实测（`tunnel-18649.log`）：`Settings: map[... url:http://127.0.0.1:18649]`、
`Initial protocol quic`、UDP Connectivity PASS ⇒ 连接建立走的是 quic，**命令行里的
`--protocol http2` 在本机 cloudflared 上被忽略/未生效**（工作项三边界，见风险节）。

### 2.4 凭据分级

| 凭据 | sha256 前 8 | TunnelID | 判级 |
|---|---|---|---|
| `creds-18640.json` | `c2bf4517…` | `ef299452-09e5-406b-9715-2d1776222b18` | real |
| `%TEMP%\credtest.json` | `c8eb3b13…` | `64e15197-16b8-41e4-8ced-28378a83d015` | temp-test（测试产物） |

⇒ `creds-t0r140-18651.json` / `%TEMP%\credtest.json` 属**凭据测试残件**，其 TunnelID 与
`18699` 的进程相同 ⇒ 18699 是测试形态，不计入真实违规面（判据输出已标 `src=temp-test`）。

### 2.5 自检读数

```
SELFTEST OK: 29 checks (2 mutation controls)
--definitely-not-real → rc=2
--selftes            → rc=2     # allow_abbrev=False，缩写不被静默当 --selftest
```

两个变异对照：
- **M1**：把 `evaluate` 改成「只看是否非空」⇒ 与真实现分叉，被抓。
- **M2**：把 `parse_port` 换成「取第一个候选端口」⇒ 对带前导端口的合成命令行必然分叉，被抓。

## 三、分析

1. **「活跃映射」的权威面必须是进程 + 边缘注册证据，台账与凭据都只是交叉面。**
   实测反例：`global_tunnel down` 会清空 `tunnels.json` 但**不停进程**；反过来
   `%TEMP%\credtest.json` 有凭据文件却没有任何真隧道。首版本尺把三面等权并集，
   会把测试凭据读成对外端口（首版实测还把 `creds-t0r140-18651.json` 解析成 140）。
2. **首版两处真 bug 由真跑暴露**（不是自检能发现的）：
   - 三面行结构不一致（进程面四元组、另两面二元组）而并集统一按 `row[1]` 取端口
     ⇒ 真跑读到**空并集**却仍按「非空」继续判，`face_counts` 与实际不符；
   - `parse_port` 不容忍命令行空格分隔 ⇒ 三个进程全 `port=None`。
   两者都在 `main()` 真跑路径上，`--selftest` 因为只喂合成件而全绿 ⇒ **自检绿不等于真跑对**。
3. **新增注册证据面后**，进程面与注册面一致（18651/18699 无注册记录），
   违规面收敛为 7 个真通端口 + 18654 未起。

## 四、缺口与风险

| # | 项 | 性质 | 建议 |
|---|---|---|---|
| 1 | **18654 无人监听** | 硬缺陷 | fist-auto 网关未常驻；需先起 `fist_gateway` 常驻实例，本尺才有可判的白名单目标 |
| 2 | 7 条真隧道仍在公网侧对外 | 违反唯一出口 | 由工作项三/四车道回收（`global_tunnel down` + 停进程），**不可逆动作须 owner 确认** |
| 3 | `global_tunnel.py` 仍传 `--protocol http2` | 工具缺陷 | 日志实测显示实走 quic ⇒ 该旗标无效；工作项三边界，本轮不改 |
| 4 | 白名单值 18654 来自文档反解 | 上游未定案 | 定案文件落地后只需改 `ALLOWED_PUBLIC_PORTS` 一处常量 |
| 5 | 公网可达性未验证 | 环境限制 | 本机 no_proxy，需 WSL/CI 侧补一发外网探测 |
| 6 | 电池锚点 `check_battery_count_doc` 现读红 | **他方 WIP** | 缺面清单 `pack_exe_to_md.py` / `blackbox/e2e_web_agent_p1.py`（均为 untracked），非本任务引入 |
| 7 | 计划一定案后本尺的端口口径需同步 | 上游漂移 | 定案后复跑一次并核对违例清单 |

## 五、后续建议

1. **先起 18654 常驻实例**，再复跑本尺 ⇒ 届时才有「合规 = 并集 == {18654}」的完整判据面。
2. 回收其余 7 条隧道时，**同时清台账与停进程**（只做一半会让下一轮自检读出假干净或假违规）。
3. 本尺可作工作项三/四的**验收门**：定案后把 `ALLOWED_PUBLIC_PORTS` 指向定案文件解析值。

## 六、资源消耗

- 新增脚本 1 份（约 550 行）、报告 1 份。
- 实测命令：PowerShell 进程枚举 ×2、台账读取 ×3、日志 grep ×1、curl 探针 ×2、判据自检/真跑各若干发。
- 未动任何生产进程、未改 `global_tunnel.py`、未改网关。

## 七、超额内容

- 额外加了「边缘注册证据」面（超出「只读盘点」的最小要求）——理由：工作项①的验收要求
  「映射集合 == {fist-auto}」，而「进程活着」证明不了映射存在，必须有一面能区分真通与空转。
- 额外加了凭据来源分级（`data` vs `temp-test`）——理由：不分级会把测试残件计成违规端口。

## 八、来源

- 计划真源：`fist-mbt/plan/active/2026-11-25-global-net-exit.md`（工作项五，验收三条）
- 设计依据：`reports/2026-11-25-T0r124-fist-auto-design-report.md`（A1 漂移：18651→18654）
- 同族模板：`scripts/check_ofm_endpoint.py`（rc 契约 0/1/2、argparse 拒未知旗标、selftest 变异对照）
- 现场事实：`.fist-mbt/data/tunnels.json`、`.fist-mbt/data/tunnel-logs/`、`tasklist`
- 未改动既有生产件；`git commit` 将带 `-- <明确路径>`。
