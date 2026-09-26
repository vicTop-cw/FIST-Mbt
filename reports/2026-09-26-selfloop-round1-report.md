# FIST 四模式流水线 · Round 1 汇报（寻虫 → 修复 → 验证 → 打磨）

- 执行时间：2026-09-26 07:40Z ～ 09:16Z（UTC）
- 命名空间：**勘误（2026-09-26 Round 2 复核）——本报告原写「r1（T0r292 探路 / T0r294 修复树）」是错的**。`get T0r292` 实测 namespace=`default`。成因：Round 1 全程用 `publish --ns r1`，而 `publish` 只认 `namespace`，未知键名被静默忽略并落进 default（Round 2 的 A/B 对照已入账为 BUG-23：`--namespace r1`→T0r299 进 r1，`--ns r1`→T0r300 进 default，两者返回体形状相同且都不回显 namespace）。**本轮的命名空间隔离实际没有生效，12 张 Omega 强验证单全部与全库历史任务混在 default 里**；本轮所有 ns 维度的读数（status_summary --namespace 等）仍成立，因为它们当时按 task_id 点名。此处保留原判断过程而不删改，作为「写侧静默降级 + 读侧如实查空」的活档案。
- 结果：**部分完成 → Round 1 四模式均已实跑并有调用面证据**；Round 2/3 待续
- 开启的强制能力：Omega 强验证 ✅ · laya_decide ✅ · issue_scan ✅ · report_bug(issue_up) ✅ · call_log ✅

---

## 一、结果摘要

| 模式 | 做了什么 | 关键量化结果 |
|---|---|---|
| **寻虫 bugfind** | `issue_scan` 双口径扫 `src`，逐条读源码 + 实跑复核 high 命中，`report_bug` 入账 | 扫描 74 文件 / **101 命中**（high 8 / medium 56 / low 37，truncated）；8 条 high 复核后**真 bug 0 条**；入账 BUG-12..16 |
| **修复 fix_and_merge** | 从队列取 4 项，源码级修复 + 回归锁 + Omega 全流程 verify | BUG-14(high)/15/16 已修，账本卫生 BUG-6/7 就地作废；**测试 366 → 376 passed / 0 failed** |
| **验证 verify** | `project_standards` 取基准 → 6 项三形态 checklist → `output_validate` 硬门 | 发现并入账 BUG-17（文档三套口径）/BUG-18（laya 延迟）；**output_validate verdict=pass，12/12，evidence_layer=l4-pass** |
| **打磨 polish** | 补 10 个未文档化工具、统一 4 份文档工具数/测试数、`moon info && moon fmt` | 三守卫 `check_tools_sync`/`check_test_sync`/`check_badge` **由红转 PASS**；`.mbti` 零漂移 |

**本轮最重要的产出不是"改了多少行"，而是三个原本红灯的一致性守卫转绿，且转绿的方式是把文档改成实测值，而不是把守卫改松。**

---

## 二、证据（可复跑）

### 寻虫
- `python scripts/fist.py call issue_scan --dir src --max_findings 200 --include_tests false` → 修复前 total=101 / high=8 / truncated=true；留档 `temp/issue_scan_prod.json`
- high 命中逐条复核结论（源码上下文 + 实跑）：
  - `src/engine/engine_triage.mbt:161` `rows[0]` → 处于 `if not(rows.is_empty())` 内 → **误报**
  - `src/executor/registry.mbt:197/280/365` → 处于 `if rows.is_empty(){...}else{...}` 内 → **误报**
  - `src/omega/spec.mbt:23`、`src/server/issue_scan.mbt:42/49/51` → doc 注释与规则表字面量自命中 → **扫描器噪声**（→ BUG-15）
- `ocr-cli`：**skipped（未集成）**，按模板第五节约定走 fallback

### 修复（调用面，不只看单测）
- BUG-14 `laya_decide`：修复前顶层 keys `[answers,auto_decide,available,escalate,exit_code]` → 修复后含 `decision`+`decision_note`；**本次由指挥官独立实跑复核**：`call laya_decide --context "…"` → `decision.source=fallback / feature_route=拆解调度 / split_n=3`（留档 `temp/laya_r1b.json`）
- BUG-15 `issue_scan`：total **101→66**、high **8→4**、自命中 **17→0**、truncated **true→false**
- BUG-16 版本单一真源：`status_summary.version=0.3.0`、`project_health.version=0.3.0`，与 `grep '^version' moon.mod` 一致
- 全量测试：`moon test --target js` → `Total tests: 376, passed: 376, failed: 0`（留档 `temp/r1_test.log`）
- Omega 生命周期证据（`call_log --limit 400` 抽样计数）：`omega_spec_create` 15 · `omega_spec_review` 14 · `omega_result_verify` 19 · `omega_status` 2 · `report_bug` 23 · `issue_scan` 16 · `laya_decide` 6 · `call_log` 5 · `task_plan_deep` 5

### 验证
- `project_standards --dry-run true` → checklist `cl1-mcp-exists / cl2-cli-exists / cl3-skill-doc / cl4-tests-pass / cl5-ov-pass / cl6-doc-sync`
- 逐条外部实测（`temp/r1_ext.json`）：cl1/cl2/cl4 ok；**cl3/cl5/cl6 当时为 FAIL**（即 BUG-17 的活证据），本轮 polish 后复跑转 PASS
- `output_validate` 12 条产物门：全部通过，`evidence_layer=l4-pass`

### 打磨
- `check_tools_sync` 修复前逐条列出：`server 注册但 AGENTS 未列出 (10): github_env_check, github_flush_execute, github_flush_plan, github_issue_close, github_issue_comment, github_issue_webhook_parse, github_queue_mark_sent, github_queue_status, mode_list, mode_templates` + 四份文档缺 116 表述
- 修复后：`PASS 工具单一真源一致：server.mbt 注册 116 个` / `PASS 测试总数单一真源一致：实测 376` / `PASS 徽章一致：README tests-376%2F376`
- `moon info && moon fmt`：0 errors，`git diff --stat -- '*.mbti'` 无变更（修复全为包内私有，公开接口零漂移）

---

## 三、分析

1. **high 档语义已经失真**：本轮 include_tests=false 的 8 条 high 复核后真 bug 为 0。子串匹配的规则集在"有守卫的下标访问"和"注释散文"上都会升档到 high，而 high 恰是下游 `report_bug`/自动修复队列最信任的一档。BUG-15 修掉了两类最大噪声源（注释行、规则表自命中），但**精确率的天花板由"纯子串匹配"这个实现方式决定**，不在本轮"不改语义"的边界内。
2. **文档漂移是结构性问题，不是疏忽**：工具数三套口径（104/105/116）、测试数两套（317/329），根因与 BUG-16 同源——没有单一真源，且守卫没有在改动当轮被跑。本轮选择把数字改成**各自实测口径**，并拒绝把未复跑的 native 数字冒充成"双端 376/376"。
3. **账本"只写不销"在真实压力下变贵**：三条已修条目仍显示 OPEN，每轮都要靠人工追加 `FIXED(...)` 段自证；BUG-9 的成本随轮次线性上升。本轮按硬约束未新增 close API，这是有意的取舍而非遗漏。

---

## 四、任务分配记录

| 任务 | 承担者 | 说明 |
|---|---|---|
| Round 1 四模式整体执行 | 子代理 `r1-pentad` | bugfind/fix 主体完成；**verify/polish 与报告未产出**，达子代理轮次上限退出 |
| Round 1 收口（verify + polish + 报告 + 账本修补） | 指挥官本人 | 10 工具文档化、四文档计数统一、三守卫转绿、output_validate 12/12、BUG-17/18 入账 |
| BUG-14/15/16 修复与回归锁 | 子代理（ns `r1`，任务 `T0r294.*`） | 经 Omega 强验证 verify 通过 |

> 教训入档：一次性把"4 个模式 + 4 份落盘交付"整包委派，子代理会在前两个模式上耗尽轮次。Round 2/3 改为**每轮两次委派**（寻虫+修复 / 验证+打磨），指挥官只做终审与收口。

---

## 五、遗留风险

1. **BUG-18（新发现，未修）**：`laya_decide` 单次实测阻塞 >150s（sidecar 超时预算 300s，每次调用重跑 `--probe` 且不缓存），而 `.mcp.json` 的 server `timeout_ms=30000`——客户端 30s 先超时，调用方看到"无响应"而非降级决策。无人值守流水线单拍可被一个决策工具吃掉大半预算。
2. **BUG-1..5、8..13 共 11 条历史 OPEN 未进入本轮修复集合**，其中 BUG-4（run_check 宿主级命令执行面无白名单/workdir 约束）是 high 且属安全面，应优先于其余。
3. **native 目标本轮未复跑**，文档已按实措辞；若 Round 3 收口仍不跑，"双端"结论不可对外宣称。
4. **issue_scan high 档仍会污染下游**：剩余 4 条 high 全为误报，流水线若按 `by_severity.high>0` 决策仍会误判。
5. 账本无 close API（BUG-9），已修条目状态位无法翻转。

---

## 六、后续建议

- Round 2 修复集合建议：BUG-4（安全面收紧 workdir + cmd 白名单）→ BUG-18（laya 超时/缓存）→ BUG-2（execute 状态死角）→ BUG-3（audit_log 假空）。
- 把 `check_tools_sync` / `check_test_sync` / `check_badge` 写进修复模式的**收尾必跑步骤**（当前只在 polish 里跑，漂移要积累一轮才被发现）。
- `issue_scan` 的 high 档在改为 AST/作用域判定之前，宜降格为 candidate 并要求复核后才升档。

---

## 七、超额内容（本轮做了提示词未要求的）

- 复核并把 **BUG-6/BUG-7 两条探针残留垃圾账**就地标注作废（原始诉求只要求修 BUG-5）。
- 主动把"双后端全绿"的历史表述改为**分后端各自声明**，拒绝让未验证数字转正（超出"同步计数"的字面要求，但属同一缺陷根因）。
- 在 `scripts/scoring_rubric.md` 同步 116/376 口径，该文件不在原始四模式模板清单里，是三形态守卫的 DOCS 成员。

## 八、来源

- `templates/pipeline_mode_{bugfind,fix_and_merge,verify,polish}.md`
- `AGENTS.md`「FIST 指挥官模式」「终审与验证（金条八）」「记忆沉淀与汇报（金条五）」「Project standards」
- FIST-Mbt 自身工具面：`issue_scan` / `report_bug` / `bug_list` / `laya_decide` / `project_standards` / `output_validate` / `call_log` / `cost_stats` / Omega 全族
- 实测产物：`temp/issue_scan_prod.json`、`temp/issue_scan_after.json`、`temp/laya_after_fix.json`、`temp/laya_r1b.json`、`temp/r1_test.log`、`temp/r1_ext.json`、`temp/r1_arts.json`、`temp/r1_flow_*.json`
- `memory/bugs.md` BUG-12..18（18 条队列：high 3 / medium 12 / low 3）

*（内容由AI生成，仅供参考）*
