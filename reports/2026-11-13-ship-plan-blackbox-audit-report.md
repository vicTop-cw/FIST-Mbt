# SHIP-PLAN-BLACKBOX-v2 对表审计报告（2026-11-13）

> 执行者：Lane L3（fist-pm-executor-3）｜任务包：SHIP-PLAN-BLACKBOX-v2 对表收口（研究+报告，不提交）
> 仓库快照：HEAD `cfc84b616`（2026-11-13 10:42）｜moon.mod version = **0.3.11**｜`_release/VERSION` = **0.3.10**（两处口径不一致，见 §五）
> 工具真源读数：`python scripts/_tool_registry.py` → **182 个**（扫描 41 份 src/server/*.mbt；2026-11-13 10:50 实测。团队口径 182/183 并存——commissar_gc 接线是否落盘以该脚本复跑为准）
> 证据日志集中区：`temp/l3-audit/*.log`（e2e 原始输出；temp/ 非入库面）

---

## 一、逐 Phase 状态表

| Phase | 内容 | 判定 | 一手证据 |
|---|---|---|---|
| Phase 0 | GitCode Release 基础设施 | **部分闭合**：GitHub 面闭合，GitCode 面开放 | `BACKLOG.md:66-72` release-fact 行：v0.3.8(2026-10-13)/v0.3.9/v0.3.10/v0.3.11(2026-10-31，js 794603B + native-linux-x64 3835963B 两枚) 均 github-published；**GitCode 侧发布零证据**（G7 未接，release.yml 无 gitcode 字样） |
| Phase 1 | irm 一键安装（1.1 入口 / 1.2 GitCode 适配 / 1.3 端到端） | **1.1/1.2 闭合；1.3 本机不可绿** | `install_onecmd.ps1` 在场（19331B，BOM 在场属 check_ps_encoding 契约）；`install.ps1` L36 `$GitCodeRepo` + L92-99 GitCode 直链与双失败分支；README:201/209 两档安装线与 `e2e_irm_line.py`（反解 README 字面线）常驻。本机实跑 FAIL（详见 §三 e2e 表）——根因一：**安装器 Node≥24 硬门**（install.ps1:55）撞上本机 Node v22.22.2；根因二：兜底档 curl 传输层 `curl: (35)`（TLS 中间盒），主档判定"确定性"红 |
| Phase 2 | 后台 hidden shim | **未落地（=G4，且 2026-10-13 复核判存疑设计、owner 未回裁决）** | `grep -rilE "fist-mbt-background\|WindowStyle" scripts/ cmd/` 仅命中 `scripts/explore_watchdog_hidden.vbs`、`scripts/pol_keeper_wrapper.ps1`（均非安装 shim）⇒ shim 确实没做 |
| Phase 3 | Linux/WSL2 端到端 | **功能面已闭合（v0.3.8 时代一手实测）；网络面与复测本机不可测** | 计划 §1 G5 复核行（2026-10-13）：WSL2 install.sh 后半段 INSTALL_RC=0、`node fist-mbt.js serve` 真起、tools/list 163、三处产物 md5 逐字节同。**本轮 wsl.exe 被本机安全策略拦（PROGRAM BLOCKED）** ⇒ 无法复测；WSL 直连 github.com 下载面 25s 超时的旧结论无新证据推翻 |
| Phase 4 | CI 自动发布接 GitCode | **未落地（=G7）** | `grep -in gitcode .github/workflows/release.yml` 零命中；2026-10-13 的探测结论（GitCode API 形状未知、token 404、刻意不盲落不可逆发布步）仍无新事实推翻 |
| Phase 5 | 验收（一次性） | **有证据项 4/7；不可测 2；未验 1** | 见下逐项 |
| Phase 6 | 组合环 PipelineLoop | **闭合（含一个模板小尾巴）** | `src/ops/ops_loop.mbt`(13247B) + `src/ops/ops_loop_wbtest.mbt`(9564B) 在场；`server.mbt:4314-4318` 注册 loop_create/loop_tick/loop_status；`e2e_http_contract.py` 实测 182 工具全量在册。尾巴：§6.7 清单里的 `templates/pipeline_mode_loop.md` **不在盘上**（`ls` 无此文件） |

### Phase 5 验收项逐格

| 验收项 | 判定 | 证据 |
|---|---|---|
| moon test 不退化 | **本轮复跑通过** | `moon test --target js` → 全绿（读数见 §四；基线量级已远超计划写就时的 1058） |
| irm 命令可达（GitCode URL 200） | **本机不可测** | 兜底档实跑 `curl: (35)`（TLS 层），网络面被本机中间盒拦 |
| Windows 安装（干净 PowerShell 跑 irm） | **本机不可绿** | Node v22.22.2 < 安装器硬门 ≥24，安装器当场拒（box 日志：`? Node.js v22.22.2 …需要 >=24`） |
| Windows 后台（fist-mbt-background.cmd） | **未验** | shim 本身未落地（=G4），无对象可验 |
| WSL2 安装 | **本机不可测** | wsl.exe 被安全策略拦；旧一手读数（2026-10-13）为过 |
| GitCode Release tag 可见 | **未验** | G7 未接，GitCode 侧无发布事实 |
| 执行策略绕过 | **有文档与判据面证据，未在本轮复现** | install_onecmd.ps1 首 `-ExecutionPolicy Bypass` 线在（README:209 兜底线带 `-ExecutionPolicy Bypass`）；本轮未单独复现该格 |

---

## 二、Gap 清单（G1-G8）现状判定

| # | 判定 | 一手证据 |
|---|---|---|
| G1 从未发布 Release | **已闭合**（计划 2026-10-13 复核已判闭合，本轮 release-fact 侧无回退：v0.3.11 双资产 2026-10-31 发布） | `BACKLOG.md:67` release-fact v0.3.11 行；README:169 直链引用 v0.3.11 |
| G2 缺 irm 入口脚本 | **已闭合**（脚本+判据都在；"真跑通"读数停留在 v0.3.8 时代，本轮复跑红——红因见 §三，属本机环境面） | `install_onecmd.ps1` 在场；README:201/209 与 `e2e_irm_line.py` 常驻 |
| G3 GitCode Releases API 未接入 | **已闭合（安装器侧）**；"直链能取到资产"仍开放（依赖 G7） | `install.ps1` L36/L92-99；`install.sh` L7-8/L33 GitCode 镜像行在场 |
| G4 后台 hidden shim | **仍开放**（未落地 + 2026-10-13 的"存疑设计、建议 owner 裁决是否作废"未见裁决回执） | grep 零命中（见 Phase 2 行） |
| G5 WSL2 未实测 | **功能面已闭合；网络面仍开放且本机不可测** | 计划 §1 G5 复核行（INSTALL_RC=0 / md5 三处同 / serve 真起 163 工具）；未测面=WSL 直连下载主机超时；本轮 wsl.exe 被拦 |
| G6 serve 缺 --foreground/--bg | **仍开放** | `grep -inE "foreground\|--bg" cmd/cli/*.mbt` 零命中 |
| G7 CI 自动发布未接 GitCode | **仍开放（刻意不盲落的裁决维持）** | release.yml gitcode 零命中；无新 API 事实 |
| G8 单模式无法串联 | **已闭合** | `src/ops/ops_loop.mbt` + wbtest 在场；`server.mbt:4314-4318` 三工具注册；本轮 `_tool_registry.py` 182 工具全量在册。**小尾巴**：`templates/pipeline_mode_loop.md` 缺席 |

---

## 三、e2e 电池 15 连真跑读数（2026-11-13，本机）

前置统一：`moon build --target js cmd/cli`（增量，0 errors）+ `python scripts/patch_esm_main.py`（total patched 1/10 bundles）。

| # | 判据 | rc | 结论行 | 读数要点 |
|---|---|---|---|---|
| 1 | e2e_assistant_xproc.py | **0** | `VERDICT: PASS — 单主不变量成立` | 20/20 轮、并发 5 进程、最坏主数=1 |
| 2 | e2e_transport_stack_fallback.py | **1** | `=== 端到端传输层换栈判据：FAIL ===` | 三格 rc 序列 [1,1,1]，A/C 应 0 实 1；根因=安装器 Node≥24 硬门拒本机 Node v22.22.2（box_A/run.log）；判据自述"唯一变量没起作用"（curl 有无两态同死在前置门） |
| 3 | e2e_precommit_gitlink_gate.py | **1** | `SELFTEST FAIL (9 cells…)` | 8/9 绿，红 1 格 `guarded-add-all-not-blocked: got=1 want=0`（清场后 `git add -A`+commit 应放行实被拦；疑似夹具空 diff 使 commit 落 rc=1，待尺子侧 triage） |
| 4 | e2e_guard_mutation.py | **0** | `汇总：BITES 5 / BLUNT 0 / SKIP 0` + `PASS 每把被检尺在各自违例上都咬住了` | 临时 clone 内变异全部被咬（phantom-tool/plugin-handedit/dup-index-entry/retired-entry 等） |
| 5 | e2e_reserve_xproc.py | **3** | `RSV-XPROC REFUSED: 锚点 scope 失效：moon.mod 的 action=None（期望 base=reserved）` | 格 1-3 PASS（并发双绑 20 轮 0 双成功、拒方必带持锁者、行数 20/20）；格 4-6 因权限表锚点漂移拒跑（REFUSED≠PASS，符合判据纪律；出路已由判据自述：改 REG_SCOPE 指向仍在册 scope） |
| 6 | e2e_lock_xproc.py | **3** | `LOCK-XPROC REFUSED: 预热都没跑通` | warmup 回执 `action=unregistered+challenge_required`——产品新增 challenge 门后判据预热未跟（anchor 漂移，REFUSED） |
| 7 | e2e_heartbeat_xproc.py | **0** | `E2E-HEARTBEAT-XPROC PASS：8 格全绿` | A/B1/B/C/D/E/D2+基数门 8/8；heal 自述 backend=sqlite heartbeat_source=sqlite-heartbeats |
| 8 | e2e_server_log_heartbeat.py | **0** | `PASS：serve 调用面心跳真落盘（1 行形状+pid 双对）` | 子进程 pid 36412，实测首拍间隔 60s，心跳行 pid 对上 |
| 9 | e2e_http_contract.py | **0** | `PASS: 6/6 臂通过` | n=**182** 工具有 inputSchema；mode_list ok=true；502 不崩桥；legacy /mcp tools/list 182 零回归；台账改道 temp/http-contract-e2e.db（仓库根 fist-mbt.db 未写入） |
| 10 | e2e_acceptance_recheck.py | **1** | `4 PASS / 1 FAIL / 1 SKIP` | A1/A2/A5/A6 PASS；**A3 FAIL**（executor_run dry_run argv 实得 `['run','写一个 hello']`，判据期望的 argv 形状不符——产品 argv 形状与判据锚漂移）；A4 SKIP（本机无 native 产物，已发布 native 资产仅 linux-x64） |
| 11 | e2e_mirror_install.py | **1** | `=== 端到端镜像安装：FAIL ===`（7 格 FAIL） | 沙箱内正向安装 rc=1，根因同 #2（Node≥24 硬门）；反面对照格也红（HTML 资产的拒绝理由未打印到判据针）；隔离纪律守住：用户 PATH 逐字还原、真产物 sha256 65dd0f5e 跑前跑后同 |
| 12 | e2e_irm_line.py | **1** | `主档 FAIL·确定性；兜底档 FAIL·链路侧 curl: (35)` | 主档红=版本针未命中（安装器在 Node 门死）；兜底档红=TLS 传输层（本机网络面）；判据把两档分开定性（R12），链路侧不冒充确定性 |
| 13 | e2e_upgrade_mirror.py | **1** | `汇总: 0/5 PASS`（C1-C5 全 FAIL，upgrade rc=1） | 同 Node≥24 硬门；清理面干净（真产物 sha256 before=after、PATH 还原 same=True、沙箱清场） |
| 14 | e2e_native_heap_probe.py --runs 12 | **3** | `拒绝出数：本判据要 POSIX 上的 native 工具链…没跑成 ≠ 跑过` | Windows 无 native-env ⇒ 拒绝出数（契约档 rc=3） |
| 15 | （WSL 侧复测） | — | **wsl.exe 被本机安全策略拦（PROGRAM BLOCKED）** | G5/Phase 3 复测与 native 探针 WSL 臂均无法执行 |

**本机不可测清单**（含根因，均按纪律标"不可测"，不读成"已验"）：
1. **Node 版本门**：本机 Node v22.22.2 < 安装器硬门 ≥24 ⇒ 一切走 install.ps1/upgrade_install.ps1 真安装路径的电池（#2/#11/#12/#13）全部死在前置门——判据本身的行为面（下载/换栈/回滚）本轮无法观测到。
2. **TLS/网络面**：兜底档 curl (35) ⇒ 公网直链（GitHub raw / GitCode）可达性格全部不可测。
3. **native 面**：Windows 无 native 工具链 ⇒ #14 拒绝出数；A4 native serve/demo SKIP。
4. **WSL 面**：wsl.exe 被安全策略拦 ⇒ G5 复测不可执行。

---

## 四、moon test 基线（Phase 5 第一格一手读数）

`moon test --target js`（2026-11-13，HEAD cfc84b616，全量）→ **Total tests: 2074, passed: 2074, failed: 0**（rc=0，耗时 2m17s；原始输出 `temp/l3-audit/moon_test.log`）。不引历史值；本轮一手。

## 五、额外发现（对表之外、值得入账的）

1. **版本口径分裂**：`moon.mod` version = **0.3.11**，`_release/VERSION` = **0.3.10**——后者落后一位。`e2e_upgrade_mirror.py` C5（VERSION 兼容回退格）吃这个文件；发布面以哪边为准需要 owner 定一句（若 VERSION 是发布时手工 bump 的遗留，建议在发布 checklist 里补同步步骤）。
2. **判据锚点漂移 ×2**（产品进化快于判据）：reserve_xproc 的 `moon.mod` 权限表锚、lock_xproc 的 challenge 门预热，都属"产品新增门后判据没跟"，判据自己拒跑（REFUSED，不假绿，纪律正确）。修复方向判据自述里已给，属尺子侧小修。
3. **A3 argv 形状漂移**：`executor_run` 的 dry_run argv 与 e2e_acceptance_recheck 的期望形状不符——要么产品 argv 形状变了、要么判据锚旧了，需要 owner 一句定性（同属锚漂移族）。
4. **`templates/pipeline_mode_loop.md` 缺席**：§4/§6.7 交付物清单里登记了，盘上没有。
5. `scripts/patch_esm_main.py` 与 `scripts/blackbox/patch_esm_main.py` 两份并存（内容是否同源未审）——§4 清单只登记了一份，登记面与盘面有出入（低危，仅记录）。

## 六、结论

- **已闭合**：G1、G2、G3（安装器侧）、G8（除模板文件）；Phase 1 的 1.1/1.2、Phase 3 功能面、Phase 6。
- **仍开放**：G4（存疑设计待 owner 裁决）、G6（serve 参数）、G7（CI GitCode 发布，且刻意不盲落的裁决仍有效）；Phase 0 的 GitCode 面、Phase 2、Phase 4。
- **本机不可测**：一切公网直链面、WSL 面、native 面、以及 Node<24 撞门的四条安装/升级电池。
- **计划状态行维持「实施中」**：G4/G6/G7 三格开放 + 模板文件缺席，不满足全闭合。

### 剩余开放项清单（按建议优先序）
1. G7：GitCode Releases 发布侧（前置=拿到可用 API 形状 + owner 拍板不可逆发布步）——主源"GitCode 主源"拍板至今实际靠 GitHub fallback 兜底。
2. G4：owner 先裁决"作废 or 改文档说明"，再决定是否落 shim（stdio 与 hidden daemon 的冲突论证见计划 §1 复核行）。
3. G6：`fist serve --foreground/--bg` 极简参数。
4. `templates/pipeline_mode_loop.md` 补齐或从 §4/§6.7 清单删行。
5. 尺子侧小修（锚漂移 ×2 + A3 argv 锚 + precommit 夹具空 diff 格）——不锯判定式，只改锚。
