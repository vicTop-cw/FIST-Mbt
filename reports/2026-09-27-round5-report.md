---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: round5-selfloop-report
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: round5-selfloop-report
---

# 四模式流水线自我迭代 · Round 5 汇报（寻虫 → 修复 → 验证 → 打磨 + 勘误）

日期：2026-09-27 ｜ 指挥官：FIST 指挥官（人类在场所属会话）｜ 版本：v0.3.0（未发布）
范围：用户点名的第二轮四模式，继续覆盖**新增插件态与路由/执行器**，四段全程开
**Omega 强验证 + laya 决策 + issue 上报（report_bug→修复单）+ call_log 自证**。
本轮与上一轮最大的不同：**验证段推翻的是指挥官自己那一版的结论**，且推翻过程与复算结果都落账。

## 1. 结果摘要

| 段 | 命名空间 / 根 | 产出 | 闭合状态 |
|---|---|---|---|
| 寻虫 | 承接 `pmode-r4-verify` 的 BUG-74/75 + 子代理扫插件/路由/存储/看护 | 入账 **BUG-76~82（7 条：3 high / 3 medium / 1 low）**，修复单 `T0r387~T0r393` | 逐条独立复验后才落账 |
| 修复 | `pmode-r5-fix` / `T0r394` | 闭合 **BUG-74/75/76/77/78/82**（6 条成对锁 + 2 条承重证明）；**BUG-79/80/81 入账未修并写明出路** | 18 叶 → 全树 25 已完成，Omega 步错 0 |
| 验证 | `pmode-r5-verify` / `T0r395` | 11 条判据交服务端 `run_check` 真跑 + 硬门双态；**抓到并推翻首跑自己的"11/11"伪结论** | 12 叶 → 全树 17 已完成 |
| 勘误 | `pmode-r5-erratum` / `T0r399` | 口径修正 + 真因（`prove_j9` 变异不生效）+ **BUG-83** 真源修复与锁；顺带抓到 Round 4 留的声明面滞后 **BUG-84** | 12 叶全已完成，0 步错，判据服务端 status=passed |
| 打磨 | 本段 | 账本收口（2 条 FIXED）、三处现状声明面同步、四宿主重投影、CHANGELOG/日志/本汇报 | 六守卫 rc=0 + `--selftest` PASS |

- 全量测试：`moon test --target js` **458/458**（`temp/r5/full4.log`）。
- 判据口径（本轮教训的直接产物）：**信封 `ok` = 判据已跑完并落库，判定只看 `status`**；
  复算 `temp/r5/r5_recheck.log` ⇒ **11/11 status=passed**，首跑伪结论日志 `temp/r5/r5_round.log` **原样留痕**。
- 调用面（不信模块自述）：`tools/list` 120 工具，`run_check` 描述 1425 字符含
  「已跑完并落库」「只看 status」，旧口径残留 **0**；`temp/router_smoke.py`、`scripts/mcp_smoke.py` 均在泳道内真跑。
- 硬门双向：验证段与勘误段各一组 —— `output_validate` 正门 `verdict=pass`、
  **必然违例对照门 `verdict=fail`**（引用不存在的 `check_key`、抽掉一条真结果）。
- 投影态：账本 **BUG-1~84 共 84 条**（25 high / 48 medium / 11 low，**30 待修 / 54 已挂 FIXED 小记**，本轮 8 条），
  `gen_plugins` 重投影后 cl7 逐字节一致（4 宿主 / 56 生成文件 / 120 工具 / v0.3.0），同真源两次投影哈希不变。
- **BUG-84（勘误段的产品级收获）**：三处现状表面（`AGENTS.md:299`、`AI-DEVELOPMENT-STANDARD.md:15`、
  `templates/pipeline_mode_tidy.md:45`）仍写文档面判据为 J1-J8，而真源 Round 4 就有 J9 ——
  上一轮 J1-J5→J1-J8 同样是"改了脚本、没改声明"，靠人肉同步且没留判据。本轮把范围数字本身变成可判的
  **J10**（实现侧读本脚本 `def jN_`/`---- JN` 标记，声明侧扫含 `check_doc_surface` 的行上的 `J1-Jn`，
  扫描面按 BUG-66 教训扩到 `templates/` 与 `plugins/source/`）：少写=声明滞后、多写=幻影判据、
  整块删掉=空扫描，三种都点名发红；`temp/r5/prove_j10.py` 在真实文件副本上做四向变异复算。

## 2. 资源消耗

| 项 | 实测 | 来源 |
|---|---|---|
| 台账成本记录 | 累计 437 条；本轮 `r5-fix` 18 / `r5-verify` 12 / `r5-erratum` 12 | `cost_stats`（`total_rate_limited=0`，未注入单价 ⇒ `total_cost=0`） |
| token 记账 | 130,997 in / 130,997 out（累计，宿主未分档上报，两值同源于记账占位） | `cost_stats` |
| 服务端判据真跑 | 本轮 `run_check` 共 **24 次**（首跑 11 + 复算 11 + 勘误段 2），逐条可在三份日志里对上；**不拿 `call_log` 窗口当总量**：同一 `limit=400` 窗口现在只剩 13 条 `run_check`（勘误段链上调用把更早的顶出了窗口），`limit=1200/3000` 才见 51/78 条（含往轮累计） | `temp/r5/{r5_round,r5_recheck,r5_erratum}.log` + `call_log` 三档窗口实测 |
| 全量测试 | 458 条 JS 后端全绿，单轮 | `moon test --target js` → `temp/r5/full4.log` |
| 守卫 | 六守卫 rc=0 + `check_doc_surface --selftest`（J9 反向对照 2 → 4 条；J10 新挂 5 条对照）+ 承重证明 3 份（`prove_j9` / `mut_b75` / `prove_j10`） | `temp/r5/*.py`、`scripts/check_*.py` |
| 新增任务树 | 3 棵（fix / verify / erratum），共 42 张叶全部走完 Omega 链 | `status_summary` 逐 ns |

## 3. 任务分配记录

- **子代理（寻虫候选）**：负责插件投影、路由状态文件、存储/看护面的初筛。
  交付纪律照旧：结论 / 证据 / 分析 / 缺口与风险 / 建议入档位置，缺一打回。
- **指挥官终审（不采信转述）**：7 条候选逐条读真源行号或打调用面复现后才 `report_bug`；
  其中 BUG-80 的"守卫是装饰"一条，判据正则命中数是在真源上实量得 0 才成立。
- **服务端（防自写自测恒绿）**：11 条判据全部由 `run_check` 真 spawn，不在指挥官自己进程里跑；
  勘误段刻意**不**把 `r5_recheck.py` 放进 `run_check`（那会让被 spawn 的进程再 spawn 服务端、
  两进程同写一份任务库），改判文件面断言 `temp/r5/b83_closure_check.py`，理由写在该脚本头部。
- **Omega 强验证**：每棵树的叶走 claim→`omega_spec_create`→`omega_spec_review`→execute→submit→
  `omega_result_verify`→verify；枝干/根按 `omega_enabled` 分流上卷，三棵树合计步错 **0**。
- **laya 决策**：三棵树发布前各问一次 `laya_decide`（`no_sidecar=true` 走内建规则分支），
  本轮路由到「深度验证」。

## 4. 遗留风险（不粉饰）

1. **账面上有两条"说谎"的已完成行**：`T0r395.1.1` / `.2.1` 的 deliverable 正文写着"全树 11/11"，
   那是首跑拿信封 `ok` 汇总出来的。按"只追加不关闭"未改写，改由 `T0r399` 勘误树补正——
   **只读验证树、不读勘误树的人仍会误读**，这是本方案自身的残留风险。
2. **BUG-79/80/81 结转**：`rsv_release` 把"语句跑成功"当"删到了行"；28 处描述仍广告 `now` 且
   守卫正则命中 0（判据一放宽就 28 红，属批量文案工程）；`heal` 不带 ns 时扫 `list_all()` 回滚全库在途任务。
3. **BUG-77 无自动化锁**：修的是"回执说谎"那一半（`meta_prompt_resolved` / `meta_prompt_overridden` 分栏回），
   行为未动；字段级断言需真起 `watchdog_tick`，本轮只到"代码 + 描述 + 实测"，测试补挂转结。
4. **`executor_run` 真跑分支仍无端到端证据**：BUG-4 边界默认收紧，只证到记账路径与 `dry_run`，真执行未获授权。
5. **native 轨本轮未复跑**：不据旧数宣称双端同版全绿；权威稳定门槛仍是 JS 后端（Node ≥ 24）。
6. **GitHub 同步通道未开**：`github_env_check` ⇒ `enabled=false / repo_set=false / token_present=false`，
   `github_queue_status.total=0` 的含义是"未开同步"而不是"无 bug 待同步"（凭据只走环境变量注入，仓库不读 `.env`）。

## 5. 后续建议

- **把"两义键"扫描从点名清单扩成枚举**：现在 `RET_MUST_EXPLAIN` 只有本轮亲自踩过的 `run_check`。
  下一轮可先从 `src/engine/omega_gate.mbt` 的回执构造里枚举所有"同时含 `ok` 与另一状态键"的工具，
  再按实测条数定基线——避免许愿式全量判据第一天就红。
- **判据脚本自身也要成对**：`prove_j9.py` 的 `replace(…,1)` 说明"证明锁承重的脚本"也需要同伴生对照
  （变异前后needle计数）。建议把这条并入 `--selftest`，而不是留在一次性脚本里。
- **BUG-80 走批量文案工程专项**：一次收 28 处 + 同时把守卫正则的命中数写进判据（命中 0 即红），
  别塞进缺陷修复的零碎轮次里。
- **`mode → 模板` 接线另开特性单**：改变在跑任务实际拿到的提示词属新能力，与本轮"文案如实化"不同一条线。

## 6. 超额内容（超出四模式基本动作、但确实做了的）

- **多长了一棵勘误树**（12 叶 + 2 条服务端判据 + 一组双态硬门），代价约一次判据复跑；换来的是
  "伪结论可追溯、不许事后抹证"这条纪律第一次有了实现。
- **J9 从两条判据增至三条**（新增 `RET_MUST_EXPLAIN`），`--selftest` 反向对照 2 → 4 条；
  承重证明新增第④段（真实描述抹词必红 + 良性追加不误红）。
- **新增 J10 并把"声明面滞后"这一族收进判据**：范围数字从此由脚本自己认领，
  三处现状表面（AGENTS / 规范正文 / 对外模板）同步到 J1-J10，连守卫自身的 SELFTEST 与 PASS 文案一起改口径。
- 顺手修掉本轮唯一一条真红判据的成因（`prove_j9` 全量替换 + 先量出现次数），未另开单。
- 未做（守边界）：没有为让数字好看去动 `executor_run` 的收紧默认、没动 `heal`/`rsv_release` 的行为语义、
  没新增依赖、没改任何公开 API 签名（新增一律为可选参数，默认零回归）。

## 7. 来源

- 真源改动：`src/server/server.mbt`（`run_check`/`store_open`/`task_plan_deep`/`bug_list`/`github_queue_status` 描述、
  `selfdrive` 调用点传 `now_default()`）、`src/engine/omega_gate.mbt`（回执尾巴 + status 推导）、
  `src/store/multi_store.mbt`（`data_dir_ok`）、`src/ops/ops_watchdog.mbt`（resolved/overridden 分栏）、
  `src/ops/ops_selfdrive.mbt`（可选 `now~`）、`scripts/check_doc_surface.py`（J9 ③ + 4 条对照）。
- 锁：`src/engine/omega_gate_wbtest.mbt`（`og_1~og_3`）、`src/store/multi_store_test.mbt`（成对 + 入口级）、
  `src/ops/ops_selfdrive_test.mbt`（`selfdrive_b82_export_stamp_成对`）、
  `scripts/check_doc_surface.py` 的 J9③ 与 J10（配 `--selftest` 合成违例 + 反向对照）。
- 声明面同步：`AGENTS.md`（守卫族段 J1-J10）、`AI-DEVELOPMENT-STANDARD.md`（守卫族表格行）、
  `templates/pipeline_mode_tidy.md`（对外模板第五步）。
- 判据与证据：`temp/r5/{r5_round.py,r5_round.log,r5_round_report.json,r5_recheck.py,r5_recheck.log,prove_j9.py,prove_j10.py,mut_b75.py,b83_closure_check.py,r5_erratum.py,r5_erratum.log,file_b83.py,full4.log}`。
- 账本与投影：`memory/bugs.md`（BUG-1~83；本轮 7 条 FIXED 小记）、`plugins/{atomcode,codearts,deepseek-harness,claude}`（cl7 逐字节一致）。
- 项目内记录：`CHANGELOG.md`「四模式流水线自我迭代 · Round 5」、`memory/2026-09-27.md` §8。
- 规范依据：`AI-DEVELOPMENT-STANDARD.md`（一源四态 / 证据梯 L4 / 增量零回归 / 确定性优先 / 自我迭代）+
  `AGENTS.md`「FIST 指挥官模式」金条四、五、八。
