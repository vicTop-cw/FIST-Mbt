# R110 · 超级管家四枚开关参数收口成真 boolean —— 报告

- 日期：2026-10-22
- 分支：`slave/fix/supervisor-bool-flags-schema-r110`（基点 `gitcode/master` = `4914a81f`，已叠主线）
- 提交：`17b12584`（代码）+ 本报告与文档面一笔
- 真源：`src/server/supervisor_tools.mbt`
- 立项来源：本轮以「全开关」真实消费方身份跑通 170 工具面（仓外探针 `fist_fullswitch_probe.py`，
  96 次调用、单进程、沙箱 cwd + `FIST_DB_PATH` 针到 temp），失败读数里唯一一类**不是我传错形状**的
  结构性缺陷。

## 结果摘要

1. **四枚伪装布尔收口**：`supervisor_kill_plan.force` / `supervisor_kill_plan.apply_pause` /
   `supervisor_prompt_list.include_consumed` / `supervisor_reminder_tick.include_consumed`
   原先声明为 `string_prop`、handler 用 `get_str(args, k) == "true"` 解析。现在一律
   `bool_prop` + `get_bool`（`src/server/supervisor_tools.mbt:93-94`、`:104-105`、
   `:163`/`:171`、`:275`/`:285`）。
2. **兑现一枚幻影参数**：`supervisor_reminder_tick` 先 `supervisor_guidance_list(include_consumed~)`
   取回全量，紧接着 `src/server/supervisor_tools.mbt:292` 的无条件 `filter(!g.consumed)` 把已消费丢掉
   ⇒ 参数在 schema 和文案里都 advertised，`true` 传上去读数恒为空。现在 `true` 时另出
   `guidance_consumed_count` / `guidance_consumed`（`:319-327`），
   且 `total_reminders` 口径**不动**（仍 = 提醒数 + 未消费引导数）⇒ 既有读侧零回归。
3. **文档面同步**：`docs/supervisor-prompt-upsert-skill.md` §5 的「返回」从一句「提醒清单」补成
   逐键列举 + 布尔收紧说明。该文档 §3/§2 早就写着 `apply_pause: true`、`include_consumed=true` ——
   **文档一直是对的，说谎的是实现**。

## 证据（全部为调用面实测，取真产物 `node cli.js serve`）

### A 修复前（全开关探针，`fist_probe_rows.json`）

| 调用 | 读数 |
|---|---|
| `supervisor_prompt_list {include_consumed: false}` | `-32602 inputSchema mismatch at /include_consumed (type): instance has none of the permitted types` |

即：照文档传真布尔 ⇒ 在 handler 之前就被 schema 拒。`supervisor_kill_plan` 的 `force`/`apply_pause`
同形（那一发因我另处传了 `task_id=null` 先红在 `/task_id`，但键与判据同一条）。

### B 修复后契约面（`tools/list` 的 inputSchema.properties）

```
supervisor_kill_plan.force            declared_type=boolean
supervisor_kill_plan.apply_pause      declared_type=boolean
supervisor_prompt_list.include_consumed  declared_type=boolean
supervisor_reminder_tick.include_consumed declared_type=boolean
```

### C 修复后行为面（真布尔，沙箱库）

| 调用 | 读数 |
|---|---|
| `supervisor_prompt_inject {target, prompt}` | `{"id":"sg-1", …}` |
| `supervisor_prompt_consume {guidance_id:"sg-1"}` | `consumed=true` |
| `supervisor_prompt_list {include_consumed:false}` | `{"count":0,"items":[]}` |
| `supervisor_prompt_list {include_consumed:true}` | `{"count":1,"items":[{…,"consumed":true}]}` |
| `supervisor_reminder_tick {include_consumed:false}` | 键集不含 consumed 两键；`guidance_unconsumed_count=0` `total_reminders=0` |
| `supervisor_reminder_tick {include_consumed:true}` | 键集多出 `guidance_consumed`/`guidance_consumed_count`；`consumed_count=1`，`total_reminders` **仍 0** |

⇒ 证明的不是「不再报错」，而是**值真的改变了返回内容**，且默认档零回归。

### D 反向对照（兼容面，诚实记账）

```
supervisor_prompt_list {include_consumed:"true"} → -32602 … at /include_consumed (type)
supervisor_kill_plan   {apply_pause:"true"}      → -32602 … at /apply_pause (type)
```

原先按 `string_prop` 契约传 `"true"` 的调用方，现在会被拒。取舍：本仓 policy 是
**reject-first、不做静默宽化**（BUG-19/23 同族：宁可显式拒并点名键，不要吞下错形状），
且仓库内文档 / `scripts/mcp_tool_tour.py:284`（`args["force"] = False`）本就写真布尔——
字符串形态没有任何文档背书。拒收消息点名键与 type，调用方可自证。

### E 门禁读数（叠主线 `4914a81f` 之后复跑）

| 门禁 | 读数 |
|---|---|
| `moon info --target js` | 155 warnings / **0 errors** |
| `moon check --target js` | 508 warnings / **0 errors** |
| `moon test --target js`（全量） | **Total tests: 1379, passed: 1379, failed: 0** |
| `moon test --target js src/server` | 361 / 361 |
| `scripts/run_guards.py`（推前） | 格数 55 / 失败 1 / SKIP 5 —— 唯一 FAIL 是 `check_delivery_gap.py` got=1 expect=0 |
| `check_tools_sync` | rc=0 PASS（170 工具四面对齐） |
| `check_doc_surface` | rc=0 PASS（J1-J15，含 J9 返回契约未退化） |
| `check_scripts_index` | rc=0 PASS |
| `check_plugin_sync` | rc=0 PASS（4 宿主 / 64 生成文件 / v0.3.10）—— 工具描述不进投影，无需重跑生成器 |

`check_delivery_gap` 那一格量的是**交付态**而不是代码（HEAD 领先主线、tip 尚未出现在任何远端分支）。
按本仓既有裁决：不给它 `expected`、不豁免、不降棘轮；权威读数取 push 之后那一次复跑（见「后续」）。

### E′ 推后权威读数（本单交付证据以此行为准）

分支推上 `gitcode/slave/fix/supervisor-bool-flags-schema-r110` 之后复跑 `scripts/run_guards.py`：
**格数 55 / 失败 0 / SKIP 5 / 缺执行面 0，rc=0** —— `check_delivery_gap` 如预期归 0（tip 已在远端分支上）。
SKIP 5 是缺前置产物（`temp/pt27.log`、`temp/chk47.json`），不构成「这格过了」的证据，也不构成失败。
期间主线又前进一次（`4914a81f → 15bb3b24`，含 `d1847018 fix(whisperer.py)`），已叠进来复跑：
`moon check --target js` = 508 warnings / 0 errors，`moon test --target js` = 1379/1379。

### F `whisperer --fast` 读数（照硬规则跑，但**不采纳它的处方**）

```
🔀 origin/main (e5293cc) ≠ gitcode/main (15bb3b2) — 镜像不同步！ gitcode 领先 11 / 落后 0
⚠️ 本地 HEAD 与远端 main 不一致（篡改） → 跑 --scan-only 恢复，或手动 git reset --hard 15bb3b2
```

两条都是**新Fix（`d1847018` 加了 fetch + 双远程比对）带来的新读数**，逐条判读：

1. 镜像不同步 = GitHub 侧落后，owner 裁决「gitHub 那边不用管，弄 GITcode 端即可」⇒ 对本单无关，不处置。
2. 「本地 HEAD 与远端 main 不一致（篡改）」并把 `git reset --hard` 写成恢复处方 —— 这是**判据 defect**，
   不是本单问题：feature 分支「领先主线 N 个提交」是 MR 工作流的正常形状，而 `reset --hard` 会把
   刚提交并推送的单元**在本地抹掉**。本单不执行该处方（HEAD 落后主线 0 / 领先 4，已由 merge 保证）。
   建议下一单：`--fast` 先判当前分支是否等于主线名，非主线时改报「落后/领先 N（feature 分支，勿 reset）」，
   且处方文本里不再出现销毁性命令。

## 资源消耗

- 工具面普查：1 个 `serve` 进程 96 次调用（全开关）+ 2 次针对性验证进程（各 6~10 次调用）；
  库针到 `%TEMP%`，仓库根 `fist-mbt.db` 未被写入演示行。
- 构建：`moon info` / `check` / `test`（全量 1379）/ `build cmd/cli` 各复跑两轮（改动后 + 叠主线后）。
- 电池：`run_guards.py` 一轮（55 格）。
- 代码改动量：`src/server/supervisor_tools.mbt` 23 增 / 9 删；文档面 1 段。
- 仓外脚手架（**不进 `scripts/` 登记面**）：`fist_probe_lib.py`、`fist_fullswitch_probe.py`、
  `fist_boolflag_verify.py`。

## 任务分配记录

- 指挥官（本 agent）亲自做：全开关探针的判读、把「我传错」与「产品说谎」分开归因、选定
  伪装布尔这一形作为首个代码 PR、终审。
- 未派发子代理：本单作用域是单文件 4 个点 + 1 段文档，派发反而要重付上下文（金条四边界内
  的「轻任务直接做」）。
- FIST 任务面：探针里 `publish` 需要 `created_by=human_steward` 才过门（默认身份被拒），
  这一点是**符合设计**的（人类指挥官硬门），不是缺陷；因此本轮未把发现登记成 FIST 任务卡。

## 遗留风险

1. **兼容收紧**：任何按旧 `string_prop` 契约写的外部调用方（本机之外的宿主插件、私有脚本）
   会开始收到 `-32602`。仓库内已全查：无一处传字符串形态（grep `include_consumed|apply_pause`
   命中 25 处全是文档/真布尔）。
2. **没有常驻尺钉住「schema 声明类型 ↔ handler 解析方式」一致**：本轮 4 处是手工 grep 出来的
   （判据机械：`string_prop("k")` 且 `get_str(args,"k") == "true"`）。同类漂移还会再来一次。
   候选下一单：`scripts/check_disguised_bool_flag.py`（空扫描必自拒 + `--selftest` 合成违例格）。
   注意主线 `cfaf7caa` 刚把 `scripts/README.md` 的重复抄本机械去重，登记前**必须重新普查抄本数**
   （R105 的「7 份同改」经验值已失效）。
3. **`supervisor_kill_plan` / `supervisor_task_tree` 无法寻址非 default 命名空间**（本轮实测新发现）：
   `get`/`list`/`pause` 都有 `namespace` 参数，这两支超级管家工具没有。把任务发进
   `boolflag-r108` 后，`kill_plan` 报 `G2_exists passed=false · task not found: T0`、
   `get`（未带 ns）同样 not found —— 失败形状与「任务不存在」不可区分。多租户下这是派发链
   静默断头，值得单独一单（加可选 `namespace`，或把 not-found 消息改成点名搜索过的 ns）。
4. 本轮**未**写 `memory/bugs.md`：账本世系在 master 与主机线之间对同一编号有双义
   （BUG-328 前车之鉴），立案编号交主机裁决，我只在此处点名。

## 后续建议（按价值排序）

1. 下一单：`supervisor_kill_plan` / `supervisor_task_tree` 的 ns 寻址 + not-found 消息点名 ns（风险 3）。
2. 常驻尺 `check_disguised_bool_flag.py`（风险 2），并把「参数被 schema advertised 却在 handler 里
   被丢弃」这一形一并纳入判据（本轮 `include_consumed` 就是它的第一发实证）。
3. `AGENTS.md` 六顶帽段把 `hat_run`/`hat_debate`/`hat_merge` 与 `src/hat/*` 的**六元**族混写成同一家族
   （实测 `hat_merge` 的词表是 `stargazer/pulse/wallbreaker/golddigger/nova/nucleus`，与六帽无关），
   已在上一轮报告列勘误，建议单独一笔文档修。
4. `src/hat/hat_defs.mbt:88` 的拒绝消息不带 offending 值与字段名，调用方无从自证 —— 小改，可搭车。
5. `scripts/whisperer.py --fast` 的「篡改 + `git reset --hard`」处方（F 节实测读数）：对 feature 分支
   把正常领先判成事故，并给销毁性处方。AI 消费方照做会丢单元，判绿也不该带这句。

## 超额内容（超出「把 4 个参数改成 boolean」的部分）

- `supervisor_reminder_tick.include_consumed` 从幻影参数做成真行为 + 工具描述逐键自述；
- `docs/supervisor-prompt-upsert-skill.md` §5 返回面补全；
- 一次 170 工具面的全开关实测与读数表（96 格），其结论继续供后续单使用。

理由：4 个点里第 4 个点所在的工具，其参数改成 boolean 之后仍然「什么都不做」，只改类型等于
把一个谎换成另一个更精确的谎。

## 来源

- `src/server/supervisor_tools.mbt`（真源，本轮唯一代码改动）
- `src/server/server.mbt`（`bool_prop` :481 / `get_bool` :577 / inputSchema 校验链 :1177-1260）
- `docs/supervisor-core-skill.md` §3、`docs/supervisor-prompt-upsert-skill.md` §2/§5（真布尔教法的文档背书）
- `scripts/mcp_tool_tour.py:284`（`args["force"] = False` —— 仓内已在传真布尔的消费者）
- 探针读数：`%TEMP%\fist_probe_rows.json`（修复前 96 格）、`%TEMP%\fist_boolflag_verify.json`
  （修复后 A/B/C 三格）、`%TEMP%\r110_battery.log`（55 格电池）
- `memory/2026-10-22.md`（当日日志同笔追加）
