# 三轮自我迭代汇总（寻虫 → 修复 → 验证 → 打磨 × 3）

- 日期：2026-09-26（03:52 ~ 12:19 UTC）
- 目标：连续跑满 3 轮「寻虫 / 修复 / 验证 / 打磨」，全程符合本项目开发规范（R115），
  并开启 **Omega 强验证、laya、issue_up（report_bug→修复单）、call_log** 等能力
- 结论：**三轮全部收口**，终态指标见下表；未收口的缺陷全部带理由与出路挂在账本，没有粉饰成"已修"

## 一、终态指标（全部实测，可复跑）

| 指标 | 三轮起点 | Round 1 后 | Round 2 后 | Round 3 后（终态） | 复跑方式 |
|---|---|---|---|---|---|
| JS 测试 | 376/376 | 376/376（+锁维持） | 394/394 | **404/404** | `moon test --target js -j 1` |
| MCP 工具 | 116 | 116 | 116 | **116**（零公共签名变更） | `tools/list` |
| 守卫族 | 4 | 4 | 5 | **6**，逐个 rc=0 | `scripts/check_*.py` |
| 缺陷账本 | BUG-1~13（13 条） | +11 | +20 | **40 条**（含本轮 +9） | `fist.py call bug_list --project_dir .` |
| FIXED 小记 | 0（本任务口径） | 3 | 4 | **15** | `grep -c '^### FIXED(' memory/bugs.md` |
| 调用面终审 | 无此机制 | — | 14/15 | **30/30** | `python temp/r3_callsite_audit.py` |

入账时间分桶（按 `## BUG-N [ts]` 实测）：R1 窗口 11 条 · R2 窗口 20 条 · 一源四态窗口 6 条 · R3 窗口 3 条。
（BUG-32~37 发生在 11:04~11:23 的钟面 R2/一源四态区间，但语义上属 **Round 3 的寻虫产出**，故本轮报告记为 R3 新账 9 条。）

## 二、逐轮做了什么

### Round 1 —— 建立"证据梯"而不是自我宣称
- 寻虫：BUG-14/15/16 等 11 条；修复：三条均带 Omega 强验证闭环（`task_plan_deep omega_strong_verify` → 建语料 → 审语料 → execute → 成果复验 → verify），
  这是本项目第一次让"修好了"这句话由**语料 + 复验记录**而不是自述支撑。
- 打磨：`call_log` 成为"本轮用了哪些工具"的唯一口径（不再靠回忆）。

### Round 2 —— 打到调用面 + 一源四态插入任务
- 关键自纠：**首轮终审全程在度量旧二进制**（BUG-32 的由来）；`String::split` 消费式 `Iter` 造成两条假红（判据坏了，不是代码坏了）。
- 修复：BUG-2/3/4/18（含 `run_check` 的 BUG-4 **默认收紧**而非移除：白名单 + workdir 子树 + 运维侧 `FIST_RUN_CHECK_ALLOW`）。
- 插入需求（用户指定）：新增**插件态**，atomcode → codearts → deepseek-harness → claude 四宿主目录迁入主仓，
  `scripts/gen_plugins.py` 生成投影 + `check_plugin_sync.py`（cl7）挂守卫族 + 规范升 R115（`f2-four-forms-aligned`、checklist 6→7）。
- 收口时 394/394、五守卫绿、终审 14/15。

### Round 3 —— 契约诚实（这一轮的主轴）
- 寻虫 9 条：BUG-32（入口产物新鲜度）、BUG-33（45 处无人读的 `now` 广告）、BUG-34/35（熔断节流 / github 载荷）、
  BUG-36（`memory_gc` 非法 kind 静默改靶）、BUG-37（禁发名单是臆造工具名）、BUG-38（**模板教主流程调用未注册工具**）、
  BUG-39（CLI 对数组结果崩溃）、BUG-40（`project_dir` 双口径）。
- 修复 7 条 + 2 条明写 NOT-FIXED + 1 条账本补记；每条都给"改在哪 + 怎么复跑判据 + 调用面/回归锁证据"。
- 守卫加固并**先证明它会红**：`check_tools_sync` 新增 3 条判据，人工注入三处漂移 → 三条分别点名 → 还原即绿。
- 开关对照：摘掉 BUG-36 两处修复 → `memory_18/19` 同时红；恢复 → 92/92；顺带发现"consolidate 非法 kind 从未有锁"。
- 终审 30/30：含 Omega 全链（无交付物时复验被拒 = fail-closed 正确）、`laya_decide` 降级决策、`call_log` 记到被拒调用、
  BUG-21 的服务端版本在 `tools/list._meta.serverInfo` 处**第一次真正可审**。

## 三、目标里要求的开关，逐项交代

| 要求 | 是否用上 | 实测证据 |
|---|---|---|
| Omega 强验证 | ✅ 三轮都在用 | R3：`[omega:required]` 建根 → 拆 → 建语料 → 审 → 无交付物被拒 → 交付后 `status:approved`（终审 J16~J19c） |
| laya | ✅ | `laya_decide` 无 sidecar 时走 `source:fallback` 决策（`available:false, exit_code:-1`），R2 实测单跳 21.0s/20.9s < 30s 预算 |
| issue_up | ✅ | 三轮 `report_bug` 逐条入账；R3 的 BUG-40 用 `publish_task=true` 自动发布修复单 `T0r317`（bugs ns） |
| call_log | ✅ | `cost_stats` 12:09 实测 total_records=306（此后调用继续累积，只作下限）、`call_log` 可回读被 BUG-19 硬门拒绝的调用与拒绝文案（J21/J22） |
| 符合开发规范（R115） | ✅ | `project_standards` 10 条 + cl1~cl7 七项；六守卫 + 文档面守卫 + 插件态守卫本轮全绿 |

## 四、遗留与风险（不藏）

1. **25 条账本意义上"待修"**（40 - 15 FIXED）。其中 BUG-6~13 本轮**未逐条复核**，不排除早先会话已修但没回填小记——
   这个"待修"数字因此可能偏大，账本里已把该纪律缺口写明（BUG-1 补记段），不当已清处理。
2. **BUG-34 / BUG-35 有意识地不修**：分别需要 store 表结构迁移、跨平台 shell 引号语义 + 真实 token 验证；
   半修会带来比现状更误导的结果（内存计数在多进程 MCP 下每进程各计 / Windows 上仍调不通），已在账本给出四条出路。
3. **BUG-40 需要人裁决**：放宽 bug 族的相对路径限制 = 改动 `bugreport.mbt:10` 已声明的设计，不替用户拍板。
4. **插件态只证明了"自洽"**：cl7 保证四宿主目录与真源一致，但**未在真实宿主里装载**验证过；下一轮补装载记录。
5. **BUG-32 的修复未进守卫族**：干净克隆未构建时该 mtime 不变量必假，做成守卫必红，故只留调用面证据。
6. BUG-30 的 mooncakes 已发布版本矛盾（0.2.4 vs 0.2.5）未联网核对，保持原样。

## 五、下一轮建议（按价值排序）

1. 账本**逐条核销**一次（BUG-6~13 起），把"待修"数字变成可审的；并把 FIXED 回填写成流程门禁（`cl` 系列新增一项）。
2. BUG-35 先做**离线判据**（`json.loads` 生成的 `--data`），再谈修复；顺手决定 `github_queue_append` 是否注册成工具。
3. BUG-34 单开一轮做 store 迁移（含 native/js 双后端回归）。
4. 把"契约说谎"三类形状（无人读的广告 / 不存在的名字 / 模板里的臆造调用）写进 `project_standards` checklist，让四形态吃同一门禁。
5. 四宿主插件真机装载验证，补进 `plugins/README.md`。

## 六、来源

- 三轮报告：`reports/2026-09-26-selfloop-round1-report.md`、`-round2-`、`-round3-`
- 日志：`memory/2026-09-26.md`（含三轮收口小节）；账本：`memory/bugs.md`（40 条 / 15 FIXED / 2 NOT-FIXED）
- 判据：`scripts/check_{tools_sync,test_sync,badge,plugin_sync,doc_surface,scripts_index}.py`、`temp/r3_callsite_audit.py`
- 代码与文档：`src/**`、`scripts/**`、`templates/pipeline_mode_*.md`、`plugins/**`、`README.md`、`AGENTS.md`、`CHANGELOG.md`

---
*汇总人：FIST 指挥官。表中每个数字都对应一次本轮实测输出；未做的事写在第四节，不写成已完成。*
