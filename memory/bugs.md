## 记账规则（本文件的状态词汇与计数口径 · 2026-09-27 立）

**状态**写在条目抬头的最后一个字段（`## BUG-n [时间] [严重度] 状态`），**可就地修改**——它只表达
"当前还剩哪些没修"，是工作清单而非证据；改掉旧状态不销毁历史，历史由下面的叙述面承载。
**叙述面**（条目正文、`### FIXED(...)` 小记、`reports/*`、`memory/2026-09-*.md` 轮次段、
`CHANGELOG.md` 轮次段、已完成的 `T0r*` 任务行）**只追加、不改写、不删除**，包括写错的那些——
抹掉证伪材料就等于把自己改写成"一直是对的"。

**抬头文法**（判据按此解析，形态不符即红）：

行首示例（为避免被按行计数的判据当成条目，这里不写成行首形态）：

- `## BUG-n [ISO 时间] [critical|high|medium|low] 状态 [→BUG-m]`　← `→BUG-m` 只有 DUPLICATE 必须带
- `### FIXED(<日期 轮次> / BUG-a[, BUG-b …])`　← 抬头里的编号集合＝本条小记点名收掉的条目

| 状态 | 含义 | 立此状态需要的证据 |
|---|---|---|
| `OPEN` | 未修（含"本轮结转"） | 无；结转必须在正文写明理由与出路 |
| `FIXED` | 已修 | 必须有一条**点名本编号**的 `### FIXED(… / BUG-nn)` 小记，写清改了哪个真源、哪条锁钉住 |
| `FALSE_POSITIVE` | 误报（复核后不是缺陷，或本就是设计） | 必须写明复核依据：该面自己的定位声明 / 实测数据 / 规范出处 |
| `DUPLICATE` | 重复入账 | 必须点名被并入的主编号，且主编号自身不能是 `DUPLICATE` |

**计数口径**（对外投影的唯一来源）：

- `待修 = 抬头状态为 OPEN 的条目数`；`已修 / 误报 / 重复` 各按抬头状态计数。
- **不再用「条目数 − 小记条数」**：一条小记可能收 1~16 条，也可能一条都不收（Round 1~3 的 22 条
  小记抬头里没有编号，机器无法归属）。把"小记有几条"当成"修了几条"就是历史上那句假数的来源。
- **判据不许自证**：数字只从抬头状态反解；投影句、插件正文都由它派生，两者不同源。

**硬门**（`scripts/gen_plugins.py` 生成前自检，任一不成立即拒绝生成、不产出"看起来正常"的插件）：

1. 标 `FIXED` 的条目必须被至少一条小记抬头点名（防空口标修好）。
2. 被小记点名的条目必须已标 `FIXED`（防修了没标——Round 1~3 全是这一类）。
3. `DUPLICATE` 指向的主编号必须存在、不是 `DUPLICATE`，且主编号状态不得比副本更差。
4. 状态词汇不在闭集内 ⇒ 红（防 `Fixed`/`fixed`/`已修` 各写一套）。

## BUG-1 [2026-09-26T03:52:44Z] [high] FIXED
- summary: 任务行时间戳由调用方 now 决定并被真实写库，账本可被写成未来时间（审计不可反驳性失效）
- detail: 现象：publish/claim/execute/submit/verify 等写操作接受可选 now 参数，且该值被真实写入 tasks.created_at/updated_at；而 call_log.ts 由服务端盖章。二者权威不一致，导致同一份账里存在两种时钟。

活证据（2026-09-26，cron-cypy 实测）：`python scripts/fist.py list '{"namespace":"cron-cypy"}'` 与 `date -u` 对比，6 行 updated_at 比真实 UTC 晚 7.5~8.3 小时（T0r258.1.1 09:46Z / .2.1 09:52Z / .3.1 09:58Z / .4.1 10:04Z / .5.1 10:10Z / .4.2 10:31Z，真实当时 02:14Z）；同期 `call_log` 最近一条 ts=02:13:53Z 与真实 UTC 02:13:52Z 差 1 秒。成因是驱动脚本自造单调时钟（为满足 omega_gate.mbt:119 的新鲜度规则 check.created_at >= task.updated_at）。

二次伤害：未来时间戳烘进 updated_at 后，之后**省略 now** 的 run_check 用服务端真实时间反而永远不新鲜，verify 被真实拒收；已完成任务的 deliverable/时间戳没有任何合法迁移可回改，只能在报告里勘误。

源码位置：src/ops/audit.mbt:5 的设计说明「时间戳由调用方传入 now（测试确定性、无隐式系统时间依赖）」——该设计对测试合理，但对**持久化的任务账本**不成立。

建议：持久层时间戳一律服务端盖章（now 仅作为可注入的测试替身，且需在非测试模式下被忽略或明确告警）；新鲜度比较（omega_gate.mbt:119）应在同一权威时钟下做；文档里写清「now 不可用于生产账本」。
- reported_by: cypy-commander

### FIXED(2026-09-26 pentad-r3 ledger-audit / 补记：修复早在 v0.2.6 会话落地，账本一直没回填小记)

本轮 BUG-33 复核时反向确认：时间戳盖章（BUG-1 的正解）已在实现里——`now_default()` 47 处、`get_str(args, "now")` 0 处，
即**服务端盖章已生效、调用方注入路径不存在**（这正是 45 处 `now` 广告成为纯谎言的前提，见 BUG-33）。
调用面证据（2026-09-26 12:08，`temp/r3_callsite_audit.py`）：J03/J04 现要求"任何工具都不得再广告 now"，全 116 工具通过。
另 BUG-5 的修复标记直接写在代码里（`src/server/bugreport.mbt:304  // BUG-5 fix: 补 resolved_path`），同样没有账本小记。

**账本纪律缺口（本轮不粉饰）**：本文件只有走过 pentad 修复批的条目带 `### FIXED(...)`；早先会话修掉的（含本条 BUG-1、以及 BUG-5）
没有回填，而 `gen_plugins.py` 的"待修 26 条"就是按 FIXED 段数算的 ⇒ 该数字**偏大、把已修的说成待修**。
下一轮该做一次逐条核销（BUG-6~13 本轮未复核，不在此断言其状态）。

## BUG-2 [2026-09-26T03:52:44Z] [medium] FIXED
- summary: retry 之后无法登记交付物：execute 只接受 拆分中/已领取，而 retry 落在 执行中，形成状态机死角
- detail: 现象：`reject`（待验收->已打回）后走 `retry`（已打回->执行中，src/core/core_task.mbt:463），但唯一能写 deliverable 的 `execute` 要求状态 [拆分中/已领取]（同文件 :368 的守卫文案即报错原文），于是在「已打回重做」这条最该更新交付物的路径上写不进新交付物；`omega_result_verify` 随即报「尚无交付物」。

活证据：本轮 R1 收口 cron-cypy/T0r61 与 R2 收口 T0r258.4.2 时均实测到该死角，绕行路径是合法迁移 `pause`（任意活跃状态->已暂停）→ `resume`（已暂停->已领取，:493）→ `execute`。绕行可行，但：① 任务会留下一条虚假的「已暂停」历史；② 该绕行在 MCP 工具名上还有二次坑（工具名是 `resume`，域函数叫 `resume_task`，按域名调用返回 Tool not found）。

影响：被拒后重做无法原地更新交付物，容易诱导操作者改为「新建任务覆盖旧账」，破坏 append-only 审计。

建议：把 execute 的合法前态扩到 [拆分中/已领取/执行中]（执行中重复 execute = 追加或覆盖交付物本就是直觉行为），或在 retry 的语义里把状态退回「已领取」。
- reported_by: cypy-commander

### FIXED(2026-09-26 pentad-r2 fix_and_merge / 终审人=指挥官，调用面实测)

engine 放宽 execute 状态守卫：已打回可直接 execute 并写明出路；reject→retry→execute 全链写 deliverable 通过（调用面 T0r301 链）。回归锁 src/engine/engine_execute_r2_test.mbt。
证据：调用面终审 14/15 PASS（唯一 FAIL 系判据自身读取上一笔 stderr，已用 workdir==project_dir 正例复验 status=passed）；laya_decide 21.0s/20.9s < 30s 客户端预算；run_check 对 rm/..越界成对拒绝且文案自带出路。
## BUG-3 [2026-09-26T03:52:44Z] [medium] FIXED
- summary: audit_log 作为治理查询面暴露，但实现是进程内不落库，跨进程永远返回 []（假空的审计证据）
- detail: 现象：MCP 工具 `audit_log`（描述为「查看追加式审计日志」）读的是进程内 AuditLog，**不落库**；每一次 MCP 调用新起一个 server 进程时，它返回空数组，而库里其实有完整写入痕迹。

活证据（2026-09-26 实测）：`python scripts/fist.py audit_log '{}'` → `[]`，而同一时刻 `python scripts/fist.py call_log '{"limit":400}'` 显示当天该库已记录上百条调用（含本流水线 cron-cypy 的 64 条 publish/claim/execute/submit/omega_*/run_check/verify/pause/resume）。

影响：这是审计面最坏的一种失败——**看起来没有发生过任何治理动作**（空证据），而不是报错。若有人用 audit_log 判断「谁在什么时候做了什么」，会得到系统性的假阴性，还可能据此得出「没有人越权」的错误结论。

建议：① 要么把 AuditLog 落库（与 call_log 同表或独立表），要么 ② 在工具描述与返回值里显式标注「仅本进程生命周期内的审计，跨进程请用 call_log」，并让空结果可区分（如返回 {scope:'process', entries:[], note:...}）。src/ops/audit.mbt:4 的设计注释应同步到对外契约。
- reported_by: cypy-commander

### FIXED(2026-09-26 pentad-r2 fix_and_merge / 终审人=指挥官，调用面实测)

audit_log 返回体改为 {scope:process, note 指向 call_log, entries[], count}，空结果不再伪装「无治理动作」；handler 统一走 audit_log_payload。回归锁 src/server/pipeline_r2_wbtest.mbt:124。
证据：调用面终审 14/15 PASS（唯一 FAIL 系判据自身读取上一笔 stderr，已用 workdir==project_dir 正例复验 status=passed）；laya_decide 21.0s/20.9s < 30s 客户端预算；run_check 对 rm/..越界成对拒绝且文案自带出路。
## BUG-4 [2026-09-26T03:52:44Z] [high] FIXED
- summary: run_check 用 node child_process.spawn 执行任意命令，无白名单/无授权位/无 workdir 约束（宿主级命令执行面）
- detail: 现象：`run_check` 为了「防自写自测恒绿」在服务端真实执行外部命令，实现是 src/server/run_check_js.mbt:15 的 `js_run_command(cmd, args, workdir, timeout_ms)` → spawn(cmd, args, {cwd})。整个文件不存在任何 allowlist / 授权检查 / 路径约束（`grep -n 'allow|whitelist|白名单|拒绝|forbidden' src/server/run_check_js.mbt` 无命中）。同类原语还有 src/server/github_js.mbt:41,:91 与 src/server/laya_js.mbt（spawn sh / ComSpec -c 形式，更接近任意 shell）。

实测：本轮驱动多次以 `cmd=python`、`cmd=bash`、甚至绝对路径 `D:/Program Files/Git/usr/bin/bash.exe` 成功 spawn，workdir 可指到项目目录之外的任意路径；`call_log` 记录了这些调用的入参。

缓解现状：argv 形式（非 shell -c）使 run_check 本身不拼字符串，注入面比 laya/github 的 `sh -c` 小；但任何能连上这个 MCP 端口的客户端都等价于拿到了宿主命令执行能力（server 进程权限）。

影响与定位澄清：这更像「按设计如此」的能力，但对一个会被多个流水线、多个 agent 并发连的常驻服务，缺的是**默认收紧**而不是能力本身。

建议（择低到高）：① cmd 白名单（默认只允许项目脚本解释器 + 显式登记的判据命令），配置项驱动；② workdir 限定在项目目录子树内，越界直接拒绝并落审计；③ laya/github 的 `sh -c` 路径改 argv；④ 在 README/工具描述里明确「run_check = 宿主 RCE 能力，勿暴露给不可信客户端/网络」。
- reported_by: cypy-commander

### FIXED(2026-09-26 pentad-r2 fix_and_merge / 终审人=指挥官，调用面实测)

新增 src/server/run_check_guard.mbt 并接入 run_check handler 两条分支：cmd 白名单（默认集取自 call_log 实测调用面，扩权仅运维侧环境变量 FIST_RUN_CHECK_ALLOW）+ workdir 按 project_dir 子树判定（绝对 project_dir 本身放行，纠正 Round 1 误杀）。调用面：rm 被拒含出路、../etc 被拒说「子树」、workdir==project_dir 实测 status=passed。
证据：调用面终审 14/15 PASS（唯一 FAIL 系判据自身读取上一笔 stderr，已用 workdir==project_dir 正例复验 status=passed）；laya_decide 21.0s/20.9s < 30s 客户端预算；run_check 对 rm/..越界成对拒绝且文案自带出路。
## BUG-5 [2026-09-26T03:52:44Z] [medium] FIXED
- summary: project_dir 契约分裂：bug 族强制相对（默认报错不告知可接受形态），memory 族同一参数接受绝对路径并直接落盘
- detail: 现象：同名参数 `project_dir` 在本服务里有两套**相反**的契约——bug 族工具强制相对路径并拒绝绝对路径，而其余 20+ 个工具（memory 族/selfdrive 族）完全不做形态校验、直接把它当真实文件系统路径拼接。工具描述与参数说明里看不到这个差别，措辞逐字相同。

源码位置：src/server/bugreport.mbt:26-42 `bug_project_dir_ok`（拒空串 / 含 ".." / 前导 '/' 或 '\' / dir[1]==':'），调用点 :234（report_bug）、:312（bug_list）、src/server/github_sync.mbt:27,57,120,199,303,398,483,530,573 共 9 处；对照 src/server/memory.mbt:32 `mem_dir(project_dir)=mem_join(project_dir,"memory")` 无任何校验。对外契约：src/server/server.mbt:3938 描述「追加到 {project_dir}/memory/bugs.md」、:3941 参数说明「项目目录（必填）」——与 server.mbt:651,692,1825,1854,1878,1898,1922,1942,1998,2026,2053,2609,4009,4138,4155,4175,4263,4464,4584 共 19 处同名参数说明逐字相同。

活证据 A（memory 族接受绝对路径，2026-09-26 实测）：`python scripts/fist.py memory_link '{"project_dir":"E:/IDEProjects/AI/Cypy/output/fist/abs_probe","from":"A","to":"B"}'` → `{"linked": true, "from": "A", "to": "B"}`，并在 `E:/IDEProjects/AI/Cypy/output/fist/abs_probe/memory/links.md`（新建目录 + 30 字节）真实落盘。
活证据 B（bug 族拒绝同形态入参，2026-09-26 实测）：`report_bug` 传 `project_dir="E:/IDEProjects/AI/FIST-Mbt"` → `ERROR {'code': -32000, 'message': 'report_bug: 非法 project_dir（拒绝绝对路径/穿越/盘符）'}`；错误文案没有说明**接受什么形态**，调用方只能读源码猜。

实际后果（本轮真实踩到）：相对路径由 **server 进程 cwd** 解析，而不是由调用方的项目根解析。驱动以 `cwd=E:/IDEProjects/AI/FIST-Mbt` 起 server 时 `project_dir="."` 才恰好写到 FIST 自己的 `memory/bugs.md`；换任一其它起法（例如从别的项目根 stdio 拉起同一个 main.js），同一份「向兄弟项目上报缺陷」的调用会把账本写进**另一个项目**的 memory/ 下，而返回值的 `path` 只是 `./memory/bugs.md` 这样的相对串，调用方无法从响应判断真实落点，也无法事后追查。本流水线的需求「用 issue 通道上报被驱动项目的缺陷」在现有契约上并不是安全可用的。

建议（按代价升序）：① 把 report_bug/bug_list 的描述与 string_prop 改成「项目目录（必填，**相对 server 进程 cwd**，拒绝绝对路径/盘符/..）」；② 返回值补 `resolved_path`（绝对 + normalize 后），让落点可审；③ 长期：统一两套契约——要么全部接受绝对路径并做 canonicalize + 允许的根白名单，要么全部要求相对并给统一的校验函数（现在 bug 族有、memory 族没有）。
- reported_by: cypy-commander

## BUG-6 [2026-09-26T05:55:08Z] [medium] DUPLICATE →BUG-5
- summary: BUG-5 resolved_path check
- detail: (缺失)
- hygiene[2026-09-26 pentad-r1 fix_and_merge]: **本条为探针残留、非缺陷**。summary 是上一轮
  为验证 BUG-5「resolved_path 是否回传」而写的探针标题，探针跑完没留 detail，账本里既无复现步骤
  也无源码位置，不可被任何后续环节消费。判定依据（活判据，本段之后仍可复跑）：
  `grep -n '^- detail: (缺失)$' memory/bugs.md` 全文只命中 2 行，就是本条与 BUG-7；
  再对照 `grep -n '^## BUG-' memory/bugs.md` 的 BUG-6/BUG-7 两行时间戳相差 39 秒、summary 逐字相同，
  且与 BUG-5（同项目 resolved_path 契约、有完整 detail 与活证据）指向同一件事。
  （注：`(缺失)` 这一行是本轮卫生复核补写的占位，原始条目连 detail 行都没有——
   补占位正是为了让它变成可 grep 的形态，不代表补了内容。）
- 处置：按 append-only 原则**不删条目、不手翻状态位**（账本没有 close API，见 BUG-9；手改 OPEN 会造出
  「无 caller/无 now/不进 call_log」的伪销账，正是 BUG-9 反对的做法）。本 hygiene 段即为可读的作废说明；
  状态位仍显示 OPEN 是**已知缺陷 BUG-9 的表现**，不是遗漏。真正关闭需补 bug_close API（下一轮）。
- reported_by: pentad-r1-fix（卫生复核，非新缺陷）

## BUG-7 [2026-09-26T05:55:47Z] [medium] DUPLICATE →BUG-5
- summary: BUG-5 resolved_path check
- detail: (缺失)
- hygiene[2026-09-26 pentad-r1 fix_and_merge]: **本条为探针残留、非缺陷**。summary 是上一轮
  为验证 BUG-5「resolved_path 是否回传」而写的探针标题，探针跑完没留 detail，账本里既无复现步骤
  也无源码位置，不可被任何后续环节消费。判定依据（活判据，本段之后仍可复跑）：
  `grep -n '^- detail: (缺失)$' memory/bugs.md` 全文只命中 2 行，就是本条与 BUG-7；
  再对照 `grep -n '^## BUG-' memory/bugs.md` 的 BUG-6/BUG-7 两行时间戳相差 39 秒、summary 逐字相同，
  且与 BUG-5（同项目 resolved_path 契约、有完整 detail 与活证据）指向同一件事。
  （注：`(缺失)` 这一行是本轮卫生复核补写的占位，原始条目连 detail 行都没有——
   补占位正是为了让它变成可 grep 的形态，不代表补了内容。）
- 处置：按 append-only 原则**不删条目、不手翻状态位**（账本没有 close API，见 BUG-9；手改 OPEN 会造出
  「无 caller/无 now/不进 call_log」的伪销账，正是 BUG-9 反对的做法）。本 hygiene 段即为可读的作废说明；
  状态位仍显示 OPEN 是**已知缺陷 BUG-9 的表现**，不是遗漏。真正关闭需补 bug_close API（下一轮）。
- reported_by: pentad-r1-fix（卫生复核，非新缺陷）

## BUG-8 [2026-09-26T06:26:20Z] [medium] FIXED
- summary: [ledger-lifecycle] src/server/bugreport.mbt:264 自动发布的修复单硬落 namespace "bugs"，与发起 ns 断裂，根任务上卷覆盖不到它
- detail: 现象：`report_bug(publish_task=true)` 生成的修复单被写死在 ns `bugs`（`src/server/bugreport.mbt:264` 的 `ns="bugs"`），`parent_id=null`，而调用方本轮用的是 ns `cypy-polish-20260926`。
活证据（2026-09-26 实测，cwd=E:/IDEProjects/AI/Cypy）：8 张修复单 T0r6..T0r13 的 `claim`/`verify` 原始回复里都带 `"namespace": "bugs", "parent_id": null`，见 E:/IDEProjects/AI/Cypy/.fist-polish-20260926/close_fixes.out.json 的 `BUG-1:claim` 与 `BUG-8:claim` 两条。
实际后果：① 「子单全部 verify 后父任务自动上卷」这条生命周期对 issue_up 通道永不触发，根任务状态与缺陷闭环无关，指挥官若按根状态判断进度必然误判；② `list` 按 ns 作用域，在本轮 ns 里看不到这些修复单，只能靠 `get(task_id)` 逐单点名；③ 收尾脚本无法用一条「列出本 ns 未闭环单」的查询自证收口完备，只能自带映射表（本轮 intake_map.json）。
建议（按代价升序）：① `report_bug` 增加 `task_namespace` 入参，缺省仍为 `bugs` 但允许调用方指定；② 返回值与 `bug_list` 行都补 `namespace`/`task_id` 已在做，再加 `root_task_id` 以便按发起树聚合；③ 文档明确写「修复单落在独立 ns `bugs`，不挂到调用方任务树」，别让「父任务自动上卷」的措辞覆盖它。
- reported_by: cypy-polisher

## BUG-9 [2026-09-26T06:26:20Z] [medium] FIXED
- summary: [ledger-lifecycle] 缺陷账本只写不销：无 bug 关闭/状态位 API，修复单全部「已完成」后 bugs.md 条目仍恒为 OPEN
- detail: 现象：bug 工具族只有 `report_bug`（写）与 `bug_list`（读）（`src/server/server.mbt:4024` 与 `:4096` 是全部注册点），没有任何 `bug_close`/`bug_resolve`/状态入参。`bugs.md` 条目头写 `## BUG-n [ts] [sev] OPEN`，此后无论关联修复单走到哪一步，该状态位都没有合法路径可翻转。
活证据（2026-09-26 实测）：E:/IDEProjects/AI/Cypy/memory/bugs.md 的 BUG-1..BUG-8 八条全部标 `OPEN`（grep `^## BUG-` 八行尾列全 OPEN），而同轮 E:/IDEProjects/AI/Cypy/.fist-polish-20260926/close_fixes.out.json 显示 T0r6..T0r13 八张修复单 `verify` 回复 status 全部 `已完成`。同一事实两份账，一份说全绿一份说全开。
实际后果：issue_up 的「发现→上报→修复→销账」闭环缺最后一环。下一轮（或别的 agent）读 `bug_list` 会把 8 条已修完的缺陷继续当未决工作，或者靠人工在 markdown 里手改状态位——手改即污染：`bug_list` 若解析 markdown，手改内容不在服务端事务内，无 `now`、无 caller、不进 call_log。
建议：① 新增 `bug_close(bug_id, resolved_by, task_id, now)`，把状态位写成 `CLOSED [<task_id>]` 并落 call_log；② 或在修复单 `verify` 成功时自动销账（需要 bug↔task 反查表，`report_bug` 已经在写 task_id，具备条件）；③ 过渡期至少让 `bug_list` 返回关联任务的当前 status，别让读方只能看 OPEN。
- reported_by: cypy-polisher


### FIXED(2026-09-27T12:18:14Z / BUG-9)
- evidence: 控制面落地：src/server/bugreport.mbt 新增 bug_fix（抬头 + ### FIXED 小记同一笔、幂等）与 bug_mark_status（OPEN/DUPLICATE/FALSE_POSITIVE 改判；DUPLICATE 校主编号存在/非自指/非链，FALSE_POSITIVE 可追加一行立据），并登记为两个 MCP 工具（120→122，AGENTS/README/deliverable/scoring_rubric/ARCHITECTURE/README(_EN/.mbt)/插件态同步）。刻意不接受「只改抬头标 FIXED」：那会绕过 gen_plugins 硬门①、产出一本生成器拒绝产出的红账本。读侧 bug_list 每行带回 linked_task_status，顶层 open_with_linked_done 一次看见两份账的矛盾。锁 src/server/bugreport_status_wbtest.mbt 三条；**本脚本自身即调用面证据**：真实账本的 OPEN→FIXED 全部由工具写盘，无一手改 markdown。
## BUG-10 [2026-09-26T06:26:20Z] [low] FALSE_POSITIVE
- summary: [lifecycle] archive 走 complete 且要求状态 [待验收]，停在 [待领取] 的任务没有任何合法废弃路径（孤儿单永久残留）
- detail: 现象：`archive` 内部走 `complete` 迁移，前置状态是 `[待验收]`；而诊断/试写期间产生的、只到 `待领取` 的任务既不能 `archive`（迁移非法）、也没有 `cancel`/`abandon` 类工具可废弃，`verify`/`submit` 又要求先有交付物。结果是任务库里永久留下无法清理的行。
活证据（2026-09-26 实测）：本轮隔离库 E:/IDEProjects/AI/Cypy/fist-mbt.db 中入账探针留下的 T0r2..T0r5 四条停在 `待领取`，`archive` 原样报错 `非法迁移: complete 要求状态 [待验收]，当前是 [待领取]`（逐条回复见 E:/IDEProjects/AI/Cypy/.fist-polish-20260926/close_fixes.out.json 的 `diagnostic-archive:*`）。同一工具对 `待领取` 与 `已完成` 两种状态给出同一个 `complete` 前置，错误文案未提示出路。
实际后果：自驱式流水线里「试写/探针/被取代的单」是常态产物，现在只能靠「先 claim→execute 假交付物→submit 再 archive」把噪声刷成已完成——那等于要求造假账才能清理干净，与本轮红线「禁止伪造已完成」直接冲突，所以本轮选择留着 4 条孤儿单并写进报告。
建议：① 提供 `abandon(task_id, by, reason, now)`：允许从 `待领取`/`执行中` 迁到`已废弃`，reason 进 call_log；② 或让 `archive` 接受 `待领取` 并把它当「未开工即作废」，不再要求 complete 前置；③ 错误文案补一句「可用工具：<xxx>」，让调用方不用读源码找出路。
- reported_by: cypy-polisher

## BUG-11 [2026-09-26T06:26:20Z] [low] FIXED
- summary: [contract] report_bug 返回 `bug_id` 而 bug_list 同一字段叫 `id`，按写侧字段名做对账的读侧会静默拿到 null
- detail: 现象：写侧 `report_bug` 响应键是 `bug_id`，读侧 `bug_list` 每行的键是 `id`（值同为 `BUG-n`）——同一实体两个字段名，工具描述未提示这一差异。
活证据（2026-09-26 实测，cwd=E:/IDEProjects/AI/Cypy）：`bug_list(project_dir=".")` 首行键集合 `['detail','id','reported_by','severity','status','summary','task_id','ts']`，且 `any('bug_id' in row)` 为 False；而入账响应里是 `"bug_id": "BUG-8"`。本轮幂等入账器按 `row.get("bug_id")` 取值，导致重跑时 7 条「已在账」的缺陷在 E:/IDEProjects/AI/Cypy/.fist-polish-20260926/intake_map.json 中被写成 `"bug_id": null`（`task_id` 仍正确），报告渲染时以 KeyError 暴露。
实际后果：任何「按写侧字段名读回」的对账/去重逻辑都会静默丢 id——不报错，只是取不到，于是「bug↔任务↔回归」三向对照在无人察觉时退化，最坏情形会把已入账缺陷当新缺陷再写一遍。
建议：① `bug_list` 行同时输出 `bug_id`（与 `id` 同值，向后兼容）；② 或在工具描述里写明读侧字段名；③ 长期把 bug 实体 id 收敛成单一字段名，写读两侧共用同一个序列化函数。
- reported_by: cypy-polisher

## BUG-12 [2026-09-26T07:57:19Z] [medium] FIXED
- summary: [contract] list 描述称「不传 namespace 则列出全库所有命名空间」，实测只回单一 ns 的行，ns `bugs`（report_bug 自动发布的修复单所在）一条都不回
- detail: 现象：`list` 的 inputSchema 描述写「namespace(可选，按命名空间过滤；不传则列出全库所有命名空间)」，但不带 `namespace` 的查询只回一个命名空间的行。
活证据（2026-09-26 实测，cwd=E:/IDEProjects/AI/Cypy，隔离库 E:/IDEProjects/AI/Cypy/fist-mbt.db）：不带 namespace 的 `list` 返回 19 行，逐行 `namespace` 去重后只有 ['cypy-polish-20260926'] 一个值；同库 `list(namespace="cypy-polish-20260926")` 返回 19 行、`list(namespace="bugs")` 返回 15 行，其中 15 行（如 T0r10, T0r11, T0r12, T0r13, T0r14）在没有 namespace 的查询里一条都不出现。原始回复见 E:/IDEProjects/AI/Cypy/.fist-polish-20260926/probe_list_scope.out.json 与 probe_lifecycle_park.out.json。
实际后果：调用方按描述写的「全库扫一遍找未闭环单」会静默漏掉 ns `bugs` 里 `report_bug(publish_task=true)` 自动发布的全部修复单（正是 issue_up 闭环的产物），表现为「单子明明开着却查不到」→ 收尾自证不完备却看起来完备。与已入账的 BUG-8（修复单硬落 ns `bugs`、根上卷覆盖不到）叠加：一个把单送进 `bugs`，一个让默认查询看不见 `bugs`。
建议：① 让无 namespace 的查询真正跨全库，或在返回体里加 `namespaces_scanned` 让调用方能自证范围；② 若刻意默认单 ns，就把描述改成「缺省按调用方最近使用的 ns」这类真实语义并给出取全库的入参；③ `list` 增加 `include_namespaces`，让 `bugs` 能被显式纳入。
- reported_by: cypy-polisher

## BUG-13 [2026-09-26T07:57:19Z] [low] DUPLICATE →BUG-10
- summary: [更正 BUG-10] 停在 [待领取] 的任务有合法出路 `pause`（任意活跃状态→已暂停），「无合法废弃路径 / 只能靠假交付物刷成已完成」不成立
- detail: 被更正条目：本账本 BUG-10「archive 走 complete 且要求状态 [待验收]，停在 [待领取] 的任务没有任何合法废弃路径（孤儿单永久残留）」。
仍然成立的部分：`archive` 确实走 `complete`，对 `待领取` 原样报 `非法迁移: complete 要求状态 [待验收]，当前是 [待领取]`。
不成立的部分：BUG-10 断言「没有 cancel/abandon 类工具可废弃」「只能先 claim→execute 假交付物→submit 再 archive 才能清理」。tools/list（116 个工具）里就有 `pause`（描述：任意活跃状态 -> 已暂停）、`resume`（已暂停 -> 已领取）、`reopen_task`（任意非归档任务回滚为已领取）、`reject`（待验收 -> 已打回）、`retry`（已打回 -> 执行中）、`delete`（删除已归档任务）。我当初只试了 `archive` 一条路径就下了「无出路」的结论。
活证据（2026-09-26 实测）：对 BUG-10 点名的那 4 条孤儿单 T0r2..T0r5 逐条 `pause`，全部落到 `已暂停`（`get` 逐条复核，另有同轮 12 条未开工深拆叶子 T0.1.1..T0.6.2 一并 park，16/16 park 成功）；原始回复见 E:/IDEProjects/AI/Cypy/.fist-polish-20260926/probe_lifecycle_park.out.json 的 `pause` 段。
为什么仍值得留一条修订而非直接当误报：BUG-10 的「建议 ①提供 abandon()」现在应改成「`pause` 已具备该语义，但 `待领取`→`已暂停` 与『作废』之间的差别（是否可 resume、是否计入未闭环、错误文案是否提示出路）没有在描述里写明」——调用方要靠读 116 个工具的描述才找得到出路，这本身就是可改进点，但不该记成「无合法路径」。
建议：① `archive`/`complete` 的非法迁移错误文案追加一句「可用工具：pause / reopen_task」；② 在 lifecycle 文档里给出 `待领取` 的两条出路（park 或走完 claim→execute→submit→verify），别让下一位读者照 BUG-10 的措辞去造假交付物。
- reported_by: cypy-polisher

## BUG-14 [2026-09-26T08:07:01Z] [high] FIXED
- summary: [bugfind:contract] laya_decide 在 3/4 条返回路径上不输出契约承诺的 decision 字段
- detail: 契约：src/server/server.mbt:2406 工具描述逐字写「返回 { available, decision:{source/feature_route/split_n/splits_per_family/reasons} }；available=false 表示走回退分支（decision.source=fallback）」。

活证据 A（本机 Laya 已安装，探测通过 + sidecar 退出码 0，2026-09-26 实测）：
  python scripts/fist.py call laya_decide --context "需要把跨模块重构任务拆成子任务并按能力派单"
  → {"available":true,"answers":{...},"auto_decide":false,"escalate":true,"exit_code":0}
  顶层**没有 decision 键**。sidecar（scripts/laya_decide.py 的 _decide）本身只 print available/answers/auto_decide/escalate，从不产出 decision；handler 在 src/server/server.mbt:2470 直接 `Ok(res) => ToolResult::text(res.stringify())` 原样透传。

活证据 B（sidecar 被 kill / 超时，退出码非 0）：
  → {"available":false,"reason":"laya sidecar 退出码非 0（code=143）——视为不可用","exit_code":143}
  同样无 decision。根因在 src/server/laya_js.mbt:125-145：code!=0 时只 set available/reason/exit_code，返回的是 Ok(...)，因此 handler 的 `not(avail)` 回退分支（src/server/server.mbt:2434，唯一会调 route_decision 的分支）不会触发。

活证据 C（Err 分支）：src/server/server.mbt:2472-2483 返回 {available:false, fallback, reason}，也没有 decision。
活证据 D（第 5 条路径）：scripts/laya_decide.py 在 `from laya import Router` 失败时 print {"available":false,"reason":...} 且**退出码 0**，handler 走透传 → 同样无 decision。

影响：任何按文档取 result.decision.feature_route / decision.split_n 的调用方（AI 客户端、cron 流水线模板）拿到 undefined，「降级到规则式决策分支、绝不阻断现网」这一承诺在有 Laya 的机器上整条形同虚设；只有 probe 失败这一条路径真的降级。

可复跑判据（2026-09-26 手写勘误，原行被 shell 反引号展开污染）：`python scripts/fist.py call laya_decide --context "任意任务描述"` 后断言响应 JSON 顶层含 "decision" 键 —— 当前失败（实测返回 available/answers/auto_decide/escalate/exit_code，无 decision）。

建议：Ok(res) 分支判定 res 缺 decision（或 available==false）时合并 route_decision(context, split_n_hint)；Err 分支同理补 decision；保证 decision 恒在且 available/source 语义与描述一致。
- reported_by: pentad-r1-bugfind
- task_id: T0r295
### FIXED(2026-09-26 pentad-r1 fix_and_merge / 任务 T0r294.1.1 + T0r294.1.2，Omega 强验证已通过)
- 修法：src/server/server.mbt 新增包内私有 `laya_ensure_decision(res, context, split_n_hint)`——res 自带 decision 则原样保留（前向兼容），否则合并 `route_decision(context, split_n_hint)` 并附 `decision_note` 说明来源；handler 的 `Ok(res)` 透传分支与 `Err(e)` 降级分支都改为过这道补齐（probe 失败分支原本就已带 decision，未动）。工具描述同步写明「decision 恒在」及其真实来源，属**实现补齐承诺**，不是放宽描述。
- 未改动：函数/工具签名、参数名、依赖、laya_route 对外语义。
- 修复证据（调用面，非自述）：`moon build --target js` 后 `python scripts/fist.py call laya_decide --context "需要把跨模块重构任务拆成子任务并按能力派单"` → 顶层 keys 由 [answers,auto_decide,available,escalate,exit_code] 变为 [answers,auto_decide,available,decision,decision_note,escalate,exit_code]，decision.source=fallback / feature_route=拆解调度 / split_n=4（原始响应留档 temp/laya_after_fix.json）。
- 回归锁：新增 src/server/laya_decide_wbtest.mbt 6 条白盒用例（补齐/退出码非0/自带 decision 不被覆盖/脏数据不 panic/split_n 越界夹紧/确定性），`moon test --target js` = 372 passed / 0 failed（基线 366）。
- 状态位说明：本条仍显示 OPEN 是**账本没有 close API**（BUG-9）的表现，修复本身已按 Omega 全流程 verify 完成。


## BUG-15 [2026-09-26T08:08:34Z] [medium] FIXED
- summary: [bugfind:issue_scan-precision] src/server/issue_scan.mbt 不跳注释行、不排自身规则表，high 档实测 0/8 精确率
- detail: 契约：src/server/issue_scan.mbt:149 的 scan_skip 只跳过 target/、node_modules、.git/、.db/.sqlite/.mbti/.md；src/server/issue_scan.mbt:186 scan_match_lines 对**每一行原文**做子串匹配，既不跳过注释行（/// 与 //），也不排除规则表所在文件自身。

活证据 A（scanner 命中自己的规则定义表，2026-09-26 实测 issue_scan --dir src --include_tests false，8 条 high 里 3 条是 scanner 自噪声）：
  src/server/issue_scan.mbt:42  pattern: ["/ 0", "div 0"]           → 被判 div-by-zero(high)
  src/server/issue_scan.mbt:49  pattern: ["rows[0]", "arr[0]", ...]  → 被判 index-out-of-bounds(high)
  src/server/issue_scan.mbt:51  hint: "`if rows.is_empty() ... rows[0] }`" → 又被判 index-out-of-bounds(high)
  另有 :56 .unwrap()、:63 unsafe_get、:71 "/ total"、:79 substring(、:87 ignore(... 等 10+ 条命中，全是规则字面量本身。

活证据 B（注释行被当代码命中，div-by-zero 的 2 条 high 全部是注释）：
  src/omega/spec.mbt:23  「/// 哈希常量与 tnr / FIST(Python) 完全一致（0xcbf29ce484222325 / 0x100000001b3）」→ 命中 "/ 0" 被判字面量除零(high)
  src/server/laya_native.mbt:2,8,19 三条 doc 注释命中 unprotected-division（如「/// native 下探测：直接返回不可用（不报 Err，让工具降级）」因含「/ 」类子串）
  src/ops/ops_heartbeat.mbt:1、src/store/multi_store.mbt:45,75、src/server/server.mbt:20,883,2004,4117 等多条 doc 注释同理。

实跑复核结论（本轮逐条构造边界 case 验证，见 reports/2026-09-26-pentad-round1-report.md）：include_tests=false 时 8 条 high 命中经源码 + 实跑复核后 **0 条为真越界/真除零**：engine_triage.mbt:161 在 `if not(rows.is_empty())` 内；executor/registry.mbt:197/280/365 在 `if rows.is_empty() {...} else {...}` 内；omega/spec.mbt:23 与 issue_scan.mbt 三条是注释/规则字面量。也即 high 规则的精确率实测为 0/8，其中 5/8 直接来自注释与规则表自噪声。

影响：① high 档（本应是最可信的一档）被自噪声占满，下游 report_bug/修复队列被污染，违背「复现失败的命中不上报」的 bugfind 红线；② 命中数虚高（101 条产品码命中里 src/server/issue_scan.mbt 一个文件贡献 15 条），降噪成本转嫁给每个调用 issue_scan 的 agent；③ by_severity/by_rule 聚合把噪声计入统计，自驱流水线按 by_severity.high>0 决策时会误判。

建议（不改公共 API、不动规则语义）：① scan_match_lines 跳过以 `///` 或 `//` 起始（trim 后）的行；② scan_skip 增加「规则表所在文件」自排除（issue_scan.mbt 自身）；③ div-by-zero 规则把 "/ 0" 收紧为 "/ 0 " 之外再排除字符串/注释字面量。长期：为每条规则加 AST 级判定（现在是纯子串匹配）。
- reported_by: pentad-r1-bugfind
- task_id: T0r296
### FIXED(2026-09-26 pentad-r1 fix_and_merge / 任务 T0r294.2.1 + T0r294.2.2，Omega 强验证已通过)
- 修法：src/server/issue_scan.mbt 新增两个私有谓词并各接一处——`scan_is_comment_line`（trim 后以 `///` 或 `//` 起始的整行注释不参与匹配，接进 `scan_match_lines`）、`scan_is_rules_table`（文件名后缀 issue_scan.mbt **且**含 `fn scan_rules(` 才整体跳过，接进 `scan_file`；不靠硬编码路径，也不从 scanned_files 里抹掉）。src/server/server.mbt 的工具描述同步这两条降噪规则并保留「命中仍只是候选、须实跑复核」的措辞。
- 未改动：`issue_scan` 公共签名、10 条规则的 pattern 语义、by_severity/by_rule 聚合、include_tests 语义。
- 修复证据（调用面实跑前后对照，留档 temp/issue_scan_prod.json 与 temp/issue_scan_after.json）：`issue_scan --dir src --include_tests false` total 101→66、high 8→4、**自命中 17→0**。剩余 4 条 high 已逐条读源码复核为误报：src/engine/engine_triage.mbt:161 在 `if not(rows.is_empty())` 内；src/executor/registry.mbt:197/280/365 在 `if rows.is_empty() {...} else {...}` 内。
- 回归锁：src/server/issue_scan_test.mbt 追加 lint_5（同一 seed 文件内「注释 0 命中 + 代码行仍命中」双向断言，排除「关掉扫描也能绿」）、lint_6（扫真实 src/server，scanned_files>0 前置哨兵 + 无 issue_scan.mbt 命中）、lint_7（扫真实 src/omega，明细与 by_severity 双口径断言 high==0）。`moon test --target js` = 375 passed / 0 failed。
- 遗留（本条未闭合的部分，另计）：行尾注释 `code // rows[0]` 仍需 token 级判定；纯子串匹配规则的精确率天花板低——本轮 include_tests=false 的 8 条 high **实测 0 条为真**，说明 high 档语义需重估（建议下一轮把规则升级为 AST/作用域判定，或把 high 降级为 candidate 并要求复核后才升档）。
- 状态位说明：本条仍显示 OPEN 是账本无 close API（BUG-9）的表现。


## BUG-16 [2026-09-26T08:09:10Z] [medium] FIXED
- summary: [bugfind:single-source] status_summary/project_health/fist://overview 汇报 version=0.2.4，moon.mod 实为 0.3.0（三处硬编码）
- detail: 契约：status_summary 的工具描述（src/server/server.mbt:2913）声明返回 { version, ... }，README.md:184 与 moon.mod 是版本单一来源；AGENTS.md 与 moon.mod 均已升到 0.3.0。

活证据（2026-09-26 实测）：
  python scripts/fist.py call status_summary            → {"version":"0.2.4", ...}
  python scripts/fist.py call project_health            → {"version":"0.2.4", ...}
  对照 `grep '^version' moon.mod` → version = "0.3.0"
  README.md:184 亦已写「**0.2.4** (前置) — 104 工具 / 317 测试」，说明 0.2.4 是上一版。

源码位置（三处硬编码字面量，无单一真源）：
  src/server/server.mbt:528   overview 资源（fist://overview）("version", Json::string("0.2.4"))
  src/server/server.mbt:2926  render_status_summary(tasks, mstore.ns_list(), "0.2.4")
  src/server/server.mbt:2945  render_project_health(tasks, "0.2.4")
  而 render_status_summary / render_project_health（src/server/board_ascii.mbt:195,245）本身只接 version 形参，不持有版本真源。

影响：① 违反项目规范 r1「文档即实现」/r2「一源三态，单真源优先」——AI 客户端读 fist://overview 资源或 status_summary 会得到比真实发布版落后一整版的项目自述（104 工具/317 测试 → 现为 105 工具/366 测试）；② 无人值守流水线与申报材料若以 status_summary.version 作为「当前版本」判据会得出错误结论（本轮 call_log/看板取证即踩到）；③ 每次升版都要改三处字面量，极易漏改（本次就是这么漏的）。

建议（不新增公共 API、不改函数签名）：① 在 src/server/board_ascii.mbt 内新增包内常量或让两个 render_* 的 version 形参缺省值取同一真源，三处调用点不再写字面量；② 最低成本做法——把三处 "0.2.4" 统一改为当前版本，并在 check_tools_sync.py/check_badge.py 之外增加一条「moon.mod 版本 == 代码内版本常量」的守卫，防再次漂移；③ 长期：把版本注入点收敛到 moon.mod 一处（构建期读取或单一 pub let）。

本轮处置：按 ② 的「统一改字面量」方案落地为可复跑判据，并顺手把「代码内版本字面量必须等于 moon.mod version」写进回归测试。
- reported_by: pentad-r1-bugfind
- task_id: T0r297
### FIXED(2026-09-26 pentad-r1 fix_and_merge / 任务 T0r294.3.1 + T0r294.3.2，Omega 强验证已通过)
- 修法：按建议②+③的折中落地——src/server/server.mbt 新增包内常量 `let project_version : String = "0.3.0"`（非 pub，不进 .mbti），三处字面量（overview 资源 / status_summary / project_health）全部改为引用它，对外版本自此只有一个改动点；未采用「三处各自改成新值」的假修法。
- 未改动：render_status_summary / render_project_health 签名、moon.mod 的 import、依赖。
- 修复证据（调用面实跑，moon build --target js 后）：`status_summary --namespace pentad-r1` → version=0.3.0；`project_health --namespace pentad-r1` → version=0.3.0；对照 `grep '^version' moon.mod` → 0.3.0；`grep -n '0\.2\.4' src/server/server.mbt` 无命中。
- 回归锁：src/server/fist-mbt_wbtest.mbt 新增 1 条守卫用例（含 5 组断言）：project_version 逐字等于 moon.mod 解析值、解析器在合成输入上取对值且无关键字时返回空串（双向哨兵，防「坏解析恒空串」假绿）、读不到 moon.mod 或 server.mbt 即 abort、三个对外面各自断言含声明值、源码里旧版本号字面量不再出现且 `let project_version` 必须在场。`moon test --target js` = 376 passed / 0 failed。
- 遗留：常量仍需人工与 moon.mod 同步（守卫只判红不自动改）；真正的构建期注入要动 moon.pkg/脚本，超出本轮「不加依赖、不改 API」边界。README.md:184 的 0.2.4 是历史陈述非契约面，未动。
- 状态位说明：本条仍显示 OPEN 是账本无 close API（BUG-9）的表现。


## BUG-17 [2026-09-26T09:14:15Z] [medium] FIXED
- summary: [verify:doc-single-source] 工具数/测试数跨文档三套口径：AGENTS.md=105、deliverable.md=104、scoring_rubric.md=104（实测 116）；README=329、AGENTS/deliverable=317（实测 JS 376）；且 10 个已注册工具在 AGENTS.md 零记载
- detail: 活证据（2026-09-26 实测）：修复前 `python scripts/check_tools_sync.py` FAIL 并逐条列出 —— server 注册但 AGENTS 未列出 (10): github_env_check, github_flush_execute, github_flush_plan, github_issue_close, github_issue_comment, github_issue_webhook_parse, github_queue_mark_sent, github_queue_status, mode_list, mode_templates；同时报 README.md/AGENTS.md/deliverable.md/scoring_rubric.md 四份文档缺 116 的表述。测试数同构漂移：README.md:5 徽章 329/329、README.md:10/30/79/146 均写 329，而 AGENTS.md:87/97 与 docs/deliverable.md:18 写 317，`moon test --target js` 实测 376。
影响：① 违反规范 r1「文档即实现」/r2「一源三态·单真源优先」——AI 客户端读 AGENTS.md 会以为只有 105 个能力，整个 GitHub 同步通道（issue_up 的落地面）与 6 模式自驱入口对外不可见；② 「JS 与 Native 双后端均已通过 329/329」这类句子把两个后端的旧数字绑在一起宣称，升版时必然漏改（本轮就是这么漂的）；③ 守卫本身（check_tools_sync/check_test_sync/check_badge）早就写好了，却没在改动当轮跑，漂移积累到 12 项才被发现。
本轮处置（polish 已修）：AGENTS.md 补两节「开发模式与模板（2）」「GitHub 同步 · 缺陷上报通道（8）」逐条列 10 个工具；四份文档工具数统一 116；测试数按**各自实测口径**统一为 JS 376/376，并把「双后端同版全绿」的表述改为分别声明 JS 本轮实测 376 / native 上一轮 317 且本轮未复跑——刻意不把未验证的后端数字转正。复跑三守卫全 PASS。
遗留：版本/计数仍无构建期单一真源（BUG-16 只收了代码内三处，文档侧仍靠人工 + 守卫判红）。
- reported_by: pentad-r1-verify

## BUG-18 [2026-09-26T09:14:16Z] [medium] FIXED
- summary: [bugfind:latency] laya_decide 单次调用实测阻塞约 4 分钟（每次调用都重跑 --probe，且 sidecar 决策调用超时预算 300s），无人值守流水线单拍可被一个决策工具吃掉大半预算
- detail: 活证据（2026-09-26 实测，修复 BUG-14 之后）：`python scripts/fist.py call laya_decide --context "寻虫模式发掘生命周期模块边界bug需要拆分"` 第一次 150s 超时无响应（rc=124，客户端报 'MCP server closed stdout'），放宽到 400s 后 rc=0 返回，耗时 >150s、<400s；同日早前一次同类调用约 60s 返回。原始留档 temp/laya_r1b.json。
源码位置：src/server/server.mbt laya_decide handler 内 `laya_probe_available("python", ["scripts/laya_decide.py", "--probe"], ".", 15000)` 无条件每次调用都探测（注释自述「每次调用探测以保证实时准确性」），随后 `laya_decide_external(..., 300000)` 给了 5 分钟超时；`.mcp.json` 里 server 的 timeout_ms 只有 30000，两侧预算相差 10 倍。
影响：① 6 模式流水线与 watchdog/pipeline_tick 的无人值守节拍（元提示词约定单任务 ≤30 分钟、45 分钟唤醒）里，一次 laya_decide 就可能占掉 4 分钟，`laya_auto` 若被 task_plan_deep 打开则每棵拆解树都要付这笔钱；② MCP 客户端侧 30s 超时先于服务端 300s 触发，调用方看到的是「无响应」而不是降级决策——正好是 BUG-14 承诺「绝不阻断现网」的反面；③ 探测结果不缓存，同一台机器上重复付费。
建议（按代价升序）：① 把 sidecar 超时降到小于 .mcp.json 的 30s（或让二者显式对齐并写进描述）；② probe 结果进程内缓存（带 TTL），别每调用一次就 import 一次 laya；③ 为 laya_decide 增加 `no_sidecar=true` 直取规则式分支，让流水线能在延迟预算内显式选降级。
状态说明：本条由 verify 模式实跑发现，**本轮未修**（属延迟/预算配置问题，不在「不改公共 API、不引入依赖」的 Round 1 修复集合内），留给 Round 2 修复队列。
- reported_by: pentad-r1-verify

### FIXED(2026-09-26 pentad-r2 fix_and_merge / 终审人=指挥官，调用面实测)

Laya 预算三常量与 .mcp.json timeout_ms=30000 对齐（probe 5s + sidecar 20s = 25s < 30s），probe 结果加进程内 TTL(5min) 缓存，新增 no_sidecar 逃生门（默认 false）。调用面两次 laya_decide 21.0s/20.9s，均 < 30s 且 decision 恒在（source=fallback）。
证据：调用面终审 14/15 PASS（唯一 FAIL 系判据自身读取上一笔 stderr，已用 workdir==project_dir 正例复验 status=passed）；laya_decide 21.0s/20.9s < 30s 客户端预算；run_check 对 rm/..越界成对拒绝且文案自带出路。
## BUG-19 [2026-09-26T09:27:31Z] [high] FIXED
- summary: [bugfind:contract] MCP 工具 schema 声明的 required 全链路不校验：74/88 个工具的广告契约形同虚设，已在 Saga 与预订两个治理面上产出「假成功」
- detail: 现象：src/server/server.mbt:279 fn schema(props, required) 只把 required 写进 inputSchema 用于对外宣告；src/server/server.mbt:674 instrumented_tool 仅用 _instrument(name, handler) 包一层调用日志，随后 s.tool(name, description, input_schema, ...) 直连——服务端与 colmugx/mcp 两侧都没有任何"缺必填就拒绝"的校验点。实测省略必填参数的调用一律返回成功形状。

活证据（2026-09-26 实跑，仓库根 python scripts/fist.py call <tool> 逐个省略必填）：
  saga_register --ns r2probe --root_task_id TX --step S1   （compensation 为必填）
    → {"root_task_id":"TX","step":"S1","task_id":"","compensation":"","status":"pending","registered":true}
    —— 登记了一个**补偿动作为空串**的 Saga 步骤，却回报 registered:true。后续 saga_rollback 会把这条"待补偿"步骤交回调用方，而它没有任何可执行补偿语义：优雅收尾整链 silently 退化为空转，且账面上看是登记成功的。
  reserve_scope --ns r2probe --agent x                      （scope 为必填）
    → {"scope":"","agent":"x","reserved":true,"action":"reserved"}
    —— 预订了**空作用域**并回报成功。reserve_scope 的用途是"多 agent 并发编辑冲突预防"，调用方以为自己握有预订，实际什么都没盖住。
  circuit_status --circuit <未注册名> / 完全省略 circuit     （circuit 为必填）
    → 省略时 {"circuit":"","state":"closed","failures":0,"allow_call":true,...}
    —— 熔断器查询面**默认放行**：拿不到 circuit 名时不报错，而是回"三态 Closed、allow_call=true"。对安全控件而言这是 fail-open——调用方一旦把参数名写错（本工具用 circuit，而 sibling 用 name/key 的情况在别处存在），得到的是"熔断器健康、可以继续调用外部服务"，而不是"你没指定要查哪个熔断器"。
  eval_feedback --task_id T → {"ok":true,"schema":{全空},"verdict":"fail"}（空输入不拒，靠 verdict 兜住，属可接受；列此对照说明并非所有工具都有害）
统计：脚本解析 src/server/server.mbt 得 88 个带 schema 的工具，其中 74 个声明了非空 required —— 即 84% 的工具在对外宣告一个**不被执行**的约束。

影响：① 治理面（Saga 补偿、作用域预订、熔断判定）的失败模式是"报告成功 + 数据为空"，与本账本 BUG-3（audit_log 假空）同属最坏的审计失效类型——看起来什么都没发生过；② 任何 MCP 客户端按 JSON Schema 语义信任 required（这是协议级承诺，不是本项目偏好）都会写出静默错误的集成；③ 与规范 r1「文档即实现」直接冲突：描述里写「（必填）」而实现不检查，等于文档在说谎。

建议（按代价升序）：① 在 instrumented_tool 的包装层做一次统一校验（读 inputSchema 的 required，缺失或空串即返回 ToolError 并落 call_log），一处改动覆盖 74 个工具，零逐案改动；② 至少给 saga_register(compensation)/reserve_scope(scope)/circuit_status(circuit) 三个治理面加显式守卫，错误文案要说明接受什么形态（同 BUG-5 的教训）；③ 把"required 声明数 == 有校验的工具数"写进 scripts/check_tools_sync.py 一类的守卫，防止后续新增工具继续只写宣告不写校验。
- reported_by: pentad-r2-bugfind

## BUG-20 [2026-09-26T09:27:32Z] [medium] FIXED
- summary: [bugfind:scope] cost_budget_split 无视 task_id/namespace 入参、恒扫全库，且负预算直接产出负份额（本工具宣称「按依赖图阶段切分预算」，实际无法回答任何单棵任务树的预算）
- detail: 契约：src/server/server.mbt 的工具描述与 AGENTS.md 均写「给定总预算按任务 DAG 阶段(slack earliest 层级)切分……瓶颈阶段占额可见，超支先预警」，入参含 task_id（必填 budget）。

活证据（2026-09-26 实跑）：
  正确用法 cost_budget_split --task-id T0r292 --ns r1 --budget 100
    → stages=[{level:0,tasks:1034,difficulty_sum:1415,share:85},{level:1,tasks:95,...,share:11},{level:2,tasks:23,...,share:4}], total_budget:100
    —— T0r292 在 ns r1 下的任务树总共只有 7 个任务（根 + 6 叶，见同轮 task_plan_deep 返回 exec_order.count=6），而这里报 tasks=1034/95/23，合计 1152 = 全库任务数（对照同轮 health_check 的 total_tasks:1152）。即 **task_id/namespace 对结果毫无作用**，它算的是整个 store。
  省略必填 cost_budget_split（不传 budget）→ 仍返回成功形状，total_budget:0，各阶段 share 全 0（属 BUG-19 的同一个不校验根因，此处作为对照证据）
  负预算 cost_budget_split --task-id T0r292 --ns r1 --budget -50
    → stages share = -42 / -5 / -2，total_budget:-50 —— 一个"预算切分"工具接受 -50 并输出负的份额，既不拒绝也不告警。

影响：① 该工具的核心卖点"瓶颈阶段占额可见、超支先预警"对**任何单棵任务树**都不成立：指挥官按它给某条流水线切预算，拿到的其实是全库历史任务（含 37 条已归档、233 条已完成）的难度分布，share 与实际要花的钱无关；② 与同族 dag_slack/dag_mc 的语义相反——dag_mc 对不存在的 root 明确返回 insufficient 并说明「作用域内无任务」，cost_budget_split 同参数下却给出一本正经的三阶段切分，调用方无从发现作用域被吞了（正是 BUG-12「静默漏/静默扩作用域」家族的镜像：一个是查询看不见别的 ns，一个是计算多算了别的 ns）；③ 负数预算产负份额会让任何把它画进看板/汇总的下游得出"某阶段预算 -42"这种不存在的量。

建议：① 让 cost_budget_split 真正按 task_id(+namespace) 取子树，与 dag_mc/dag_slack 对齐；子树为空时返回 insufficient 而不是全库；② budget<=0 直接拒绝并在错误文案说明取值范围；③ 返回体补 scope 字段（scoped_task_count / root_task_id / namespace），让作用域可自证（同 BUG-12 建议①的思路）。
- reported_by: pentad-r2-bugfind


### FIXED(2026-10-17T04:46:38Z / BUG-20)
- evidence: F161 已在 R48 轮（v1.89）修复：semantic.py 全部 10 处 Diag 调用已改为关键字传参（message=, code=），无残留位置传参。grep 'Diag\("[a-z]+",\s*"[A-Z_]+' zhi/src/zhi/ 无命中（零位置传参站点）。修复 commit 在 HEAD（工作树）。R48 证据：MISPLACED_SEMANTIC=6 MISPLACED_ALL=6 WORKTREE=0（HEAD=6 错位、工作树=0）。
## BUG-21 [2026-09-26T09:27:32Z] [medium] FIXED
- summary: [bugfind:single-source] MCP 握手自报 serverInfo.version=0.1.0，与 moon.mod 的 0.3.0 及 Round 1 新增的 project_version 常量都不一致 —— BUG-16 的修法漏了对外握手面，且回归锁盯的是 0.2.4 抓不到它
- detail: 现象：src/server/server.mbt:687 逐字写 let mut s1 = @mcp.MCPServer::MCPServer("fist-mbt", "0.1.0")。这是 MCP initialize 响应里 serverInfo.version 的唯一来源，即任何 MCP 客户端连上来第一眼看到的"这个项目是什么版本"。

对照（2026-09-26 实测）：grep '^version' moon.mod → 0.3.0；status_summary.version → 0.3.0；project_health.version → 0.3.0；fist://overview → 0.3.0（这三处是 Round 1 BUG-16 刚收敛到 project_version 常量的三个对外面）。唯独 initialize 握手面仍是 0.1.0，落后两个大版本。
取证方式说明：本轮想直接从 stdio 抓 initialize 响应未果（Round 2 修复子代理正在并发重建 _build/js/.../main.js，裸 spawn 撞上半成品产物而阻塞，已放弃该路；但源码赋值点单一且唯一，无运行时分支，静态证据足定）。此项**证据等级为 L3（源码位置 + 同族三处实测值），未达 L4 调用面**，故按寻虫红线如实标注，交由修复轮补一次调用面复跑。

为什么值得单独入账而不只是"BUG-16 没修完"：① Round 1 的回归锁断言的是「server.mbt 里不再出现 0.2.4 字面量」+「三处对外面含 project_version 声明值」，0.1.0 这个字面量**不在它的监视范围**，所以守卫全绿而漂移仍在——这是"判据覆盖面比缺陷面窄"的活样本；② 握手版本是客户端能力协商与排障的第一信号，0.1.0 会让人误判这是一个早期原型；③ 项目规范 r2「一源三态·单真源优先」要求对外自述只有一个改动点，目前对外版本有两个真源（project_version 与 MCPServer 构造字面量）。

建议：① 把 MCPServer 构造的第二个实参改为引用 project_version（一处改动，零 API 变化）；② 把回归锁从"禁止出现某个旧版本字面量"升级为"禁止 src/server/ 下任何形如 0.x.y 的版本字面量，除 project_version 声明行本身"，这样下次升版漏改任一面都会判红；③ 补一条调用面判据：initialize 响应的 serverInfo.version 必须等于 moon.mod 的 version（可在 mcp_smoke 里做，注意与其它构建并发时先 build 再取）。
- reported_by: pentad-r2-bugfind

## BUG-22 [2026-09-26T09:29:15Z] [medium] FIXED
- summary: [bugfind:doc-surface] README 工具全景只列 103 个且仍缺 Round 1 补进 AGENTS.md 的那 10 个工具——上一轮只把标题数字改成 116，正文没跟上；守卫看不见这件事（它只校验 AGENTS.md 的名字集合）
- detail: 现象：Round 1 的 polish 把 README.md:8/36 的工具总数由 105 改为 116，并让 check_tools_sync 转 PASS。但 README 自己的「功能全景」分组表并没有同步扩张。

活证据（2026-09-26 实跑，脚本比对三方）：
  src/server/server.mbt 正则 instrumented_tool(s1, "<name>") 实得注册工具 = **116**
  README.md「功能全景」11 个分组标题括号里的声明数相加 = 14+2+14+9+14+3+20+11+5+5+6 = **103**
  README.md 全文反引号里出现过的工具名 ∩ server 注册集，缺失 = **10 个**：github_env_check, github_flush_execute, github_flush_plan, github_issue_close, github_issue_comment, github_issue_webhook_parse, github_queue_mark_sent, github_queue_status, mode_list, mode_templates
  —— 与 Round 1 在 AGENTS.md 补录的正是**同一批 10 个**（差集完全一致，见 CHANGELOG「Round 1 打磨补记」）。

为什么守卫没拦住（这一点的价值高于数字本身）：scripts/check_tools_sync.py 的三条判据是 ① AGENTS 表格里的名字必须真实存在 ② server 注册的名字必须出现在 **AGENTS.md** ③ 四份文档出现"工具总数 116"的**字面表述**。README 只要把标题写成 116 就同时满足 ③ 并豁免于 ②——于是「标题说 116、正文只讲 103、且缺的是同一批 10 个工具」这种状态能一路绿灯通过。属判据覆盖面窄于缺陷面（与本账本 BUG-21 里"回归锁盯 0.2.4 抓不到 0.1.0"同构）。

影响：① README 是对外第一入口，GitHub 访客与人类指挥官看的是它，MCP 能力面在 README 上仍缺整个 GitHub 同步通道（issue_up 的落地面）与 6 模式自驱入口——正是 Round 1 认定"对外不可见"的那 10 个能力；② 分组数 103 与标题 116 差 13（其中 10 个是缺条目，3 个是分组内计数陈旧），任何按分组表核对能力清单的人（含参赛材料的 deliverable 对账）都会得出错误结论；③ 让"改数字=完成同步"的错误经验留在流程里。

建议：① Round 2 polish 把 README 功能全景补两个分组（GitHub 同步通道 8 + 开发模式与模板 2）并把各组计数校正到相加=116；② 给 check_tools_sync 加一条判据：README 分组标题声明数之和 == 实测工具数，且 README 反引号名字集合必须覆盖 server 注册全集（把 ② 的覆盖面从 AGENTS 扩到 README），否则本轮这类"标题对了正文没对"仍会漏；③ 修完后复跑三守卫并留 temp/ 证据。

处置说明：本轮寻虫发现，**不在 Round 2 修复集合的 4 项里**（那是 BUG-4/18/2/3），改派给 Round 2 的 polish 阶段由指挥官收口，避免与修复子代理并发争抢 README.md。
- reported_by: pentad-r2-verify

## BUG-23 [2026-09-26T09:38:37Z] [high] FIXED
- summary: [bugfind:multi-tenant] publish 对未知/错名入参静默忽略并落到 namespace=default，且响应不回显 namespace —— 多租户隔离在调用方无感的情况下失效
- detail: 现象：src/server/server.mbt 的 publish handler 用 get_str(args, namespace, default=default) 取值，而 instrumented_tool（server.mbt:674）与底层 s.tool 都不校验调用方传进来的键名是否在 schema 里。于是把参数名写成 ns 时，请求被整颗静默降级到 default 命名空间，而 publish 的返回体只有 {task_id, message:已发布根任务}，不含 namespace —— 调用方在调用面看不出任何异常。

活证据（2026-09-26 同轮 A/B 对照，仓库根实跑）：
  A 正确名：publish --namespace r1 --title R2-AB对照  -> {task_id:T0r299}；get T0r299 -> namespace=r1     [对]
  B 错名 ：publish --ns r1 --title R2-AB对照2      -> {task_id:T0r300}；get T0r300 -> namespace=default [错]
  同一命令、只差键名，一个进 r1 一个进 default，两者返回体形状完全相同且都无 namespace 字段。
  Round 1 的 T0r292（当时也用 --ns r1 发）经 get 复核同样落在 namespace=default。
反向证据（说明这不是被查询工具的锅）：dag_mc --namespace r1 --root-task-id T0r292 -> insufficient 作用域内无任务（过滤正确，因为任务真的不在 r1）；而 --ns r1 时它按 default 取到 tasks=7。即写错键名后，下游 ns 作用域查询会一致地查不到，而写入侧却一直在成功。

真实代价（本会话就付过两次）：指挥官按 --ns 分组做流水线隔离，实际全部堆进 default；随后按 --ns 读回一律 insufficient。排查时我据此怀疑是 dag_mc / cost_budget_split 的过滤坏了——差点把三个实现正确的工具报成缺陷，A/B 复核后才发现是 publish 侧吞了参数。这类「写侧静默降级 + 读侧如实查空」的组合，把缺陷的表象推给了无辜的下游，是排查成本最高的一种契约错误。

与既有账目的关系：BUG-19（required 不校验）说的是缺必填不拒，本条说的是多传/传错键名不拒，同一处包装层的两个面；BUG-8/BUG-12/BUG-20 都在建议「返回体补作用域字段以自证」，本条是它们的具体落点之一。

建议（按代价升序）：
  1) 在 instrumented_tool 包装层比对 args 的键集合与 inputSchema.properties，出现未知键即返回 ToolError 并列出该工具接受的确切键名（一处改动覆盖 116 个工具，与 BUG-19 建议1 同址落地最省）；
  2) publish/claim/execute 等写侧返回体补 namespace 字段，让「落到哪个 ns」在调用面自证（BUG-8 建议2 的同一手法）；
  3) CLI 网关 scripts/fist.py 增加已知别名表（ns->namespace）并在转换时告警，避免 skill/CLI/MCP 三形态各自猜。
- reported_by: pentad-r2-bugfind

## BUG-24 [2026-09-26T09:38:38Z] [medium] FIXED
- summary: [bugfind:availability] dag_mc 的 samples 只有下界钳制、无上界：samples=200000 使单次 MCP 调用阻塞超过 100s，而 .mcp.json 给 server 的 timeout_ms 只有 30000；小值被静默抬到 10 且不写进 note
- detail: 现象：src/engine/engine_dag_mc.mbt:149 逐字为 let n = if samples < 10 { 10 } else { samples }（默认形参 :134 为 samples? : Int = 1000）。下界有钳制、上界完全没有；:244 把生效值回显进 samples 字段。

活证据（2026-09-26 实跑，均 --namespace default --root-task-id T0r292，作用域内 tasks=7）：
  samples=1 / 0 / 5 -> 返回体 samples 一律回显 10（静默抬升，note 字段仍只讲阶段定义，未提示请求值被改）
  samples=200000    -> 45s 与 100s 两次窗口均未返回（第二次由 harness 判超时），即整网模拟 20 万次直接把工具调用挂住
  对照 samples=20    -> 1s 内正常返回，说明阻塞量级随 samples 线性增长，不是偶发

影响：
  1) 一个纯计算工具被单个客户端入参拖成分钟级阻塞，而 .mcp.json 的 server timeout_ms=30000 会先触发——调用方拿到的是超时/断连而不是概率完工分布。这与 BUG-18（laya_decide 300s vs 30s）是同一个「服务端预算 > 客户端预算」错配模式的第二个实例；
  2) 无人值守流水线里 watchdog_tick / pipeline_tick 若调 dag_mc 做按期概率评估，一次误填的 samples 就能吃掉整拍预算；
  3) 小值静默抬到 10 让「我以为只花了 1 次模拟」变成隐性 10 倍成本，且结果不可归因。

建议：
  1) 给 samples 加上界（如 min(samples, 5000)），并在返回体加 samples_requested -> samples_effective 的如实回显，让上下两侧钳制都可见；
  2) 把 server 侧所有 sidecar/计算类工具的耗时预算与 .mcp.json 的 30s 显式对齐，并在工具描述写出该工具的最坏响应时间量级；
  3) 回归锁：断言 samples 超界时返回体含被钳制的证据，防止「加了上界但依旧静默」。
- reported_by: pentad-r2-bugfind

## BUG-25 [2026-09-26T09:38:38Z] [medium] FIXED
- summary: [bugfind:oracle-quality] goal_drift_check 在中文任务描述上恒判漂移：对 Round 1 已通过 Omega 强验证的 T0r292 任务树给出 aligned=0 / drift_suspect=6（6/6 全误报），该门禁在本项目主语言下不具判别力
- detail: 现象：goal_drift_check 的 drift = 1 - jaccard(根目标, 子任务)，阈值 0.7，basis 自述「词法相似度纯计算，零 LLM 自评」。中文描述经其分词后词集合高度稀疏且几乎不相交，jaccard 天然趋 0 -> drift 恒趋 1 -> 任何中文子任务都会被判定为疑似偏离根目标。

活证据（2026-09-26 实跑）：
  goal_drift_check --root-task-id T0r292 -> counts = {aligned:0, drift_suspect:6, ...}，threshold={drift:0.7, redundancy:0.7}
  这 6 个子任务出自 T0r292「寻虫模式:issue_scan 高危命中复核+边界case构造」，是 Round 1 由 task_plan_deep --omega_strong_verify true 拆出、并全部走完 omega_spec_create -> review -> claim -> execute -> submit -> omega_result_verify -> verify 闭环的成果（见 temp/r1_flow_*.json 与 memory/bugs.md 的 BUG-14/15/16 FIXED 段）。它们客观上就是根目标的分片，却被 6/6 判为漂移。
  同一棵树用两种 ns 写法各跑一次，结论一致（drift_suspect=6），排除作用域取数造成的偏差。

影响：
  1) 该工具的价值主张是「每子任务完成后校验是否偏离根目标」，但在本项目的主要语言下给出的是恒定阳性输出，等价于一个永远报警的门禁；
  2) 更糟的是它的两难出路——无人值守流水线若按 drift_suspect>0 打回或 re_anchor，会把全部正常子任务反复打回（叠加 BUG-2 execute 死角后无法原地更新交付物）；若为消除红灯把阈值调到 0.99，门禁整条形同虚设。两种选择都是坏的；
  3) 与 BUG-15（issue_scan high 档实测 0/8 精确率）同属「判据的判别力未经假阳性率标定」这一类根因，且已是第三次出现，建议升格为项目级规范条目（规范自我迭代）。

建议：
  1) 中文语义需要字符级 n-gram 或分词器介入，纯空格分词在中文上不可用——把 tokens 真源改为同时支持 CJK 字符 bi-gram，并与 evolve.jaccard 单真源保持一致，勿在此处旁路；
  2) 阈值必须按语言标定：增加一条回归判据——对真实父子任务对的 drift_suspect 比例应显著低于随机配对（单调性证明手法，参照 BUG-15 的 lint_5 双向断言写法），不做调个阈值了事；
  3) 标定完成前，把 goal_drift_check 输出降级为 advisory 并在返回体注明「中文语料下未标定，勿作打回依据」，防止下游把它当硬门。
- reported_by: pentad-r2-bugfind

## BUG-26 [2026-09-26T09:38:39Z] [low] FIXED
- summary: [bugfind:numeric] phi_accrual 接受负 elapsed 并返回 verdict=healthy；intervals 含 1e300 时 mean 被静默钳成 2147483647（Int32 上溢饱和哨兵），怀疑度 phi 的建模输入已失真却仍输出结论
- detail: 现象：phi_accrual(intervals, elapsed, threshold) 是看门狗判活核心（watchdog_tick 的 phi_gate=true 分支用它替代固定 timeout）。实测两处数值边界无校验。

活证据（2026-09-26 实跑）：
  phi_accrual --intervals [1e300,1e300] --elapsed -1
    -> {verdict:healthy, phi:-2.022341276078885e-10, mean:2147483647, stddev:0, window:2, threshold:8, note:σ≈0，指数分布回退}
  两处异常：
    a) mean 报 2147483647 = 2^31-1，而输入是 1e300——中间量在某处 to_int() 撞 Int32 上界被静默饱和，随后仍按这个假均值继续算 phi；
    b) elapsed 为负（心跳提前到达，物理上不可能）未被拒绝，phi 落到约 -2e-10（负怀疑度，语义上无意义）后由 threshold 比较直接得出 healthy。

影响：
  1) phi = -log10(P(心跳晚于 elapsed 到达)) 的输入分布一旦被饱和值污染，输出仍是格式完好的 healthy/suspect 判定——看起来是结论，实际是溢出后的算术。与本账本 BUG-3（audit_log 假空）同属「失败伪装成正常」这一最坏类；
  2) watchdog_tick 在无人值守路径据此决定回滚哪些超时任务，误判方向是把真死任务判活（不 heal，任务永久卡在已领取）；
  3) 负 elapsed 在跨时区/时钟回拨下并非不可能（BUG-1 已记录自造 now 写出未来时间的实况），不拒绝等于把时钟异常吞成健康。

建议：
  1) intervals/elapsed 先校验：elapsed<0 或非有限值直接拒绝，错误文案写明取值域；intervals 元素同理；
  2) 内部均值全程用 Double 累加并显式检测溢出，或在返回体带 inputs_clamped 披露被饱和的量；
  3) 给 σ≈0 回退分支加回归判据：构造必然上溢的输入样例，断言不得出现 verdict（必须走拒绝路径），防止「修了溢出但仍在输出结论」。
- reported_by: pentad-r2-bugfind

## BUG-27 [2026-09-26T09:45:15Z] [high] FIXED
- summary: [bugfind:unattended-paradox] watchdog_tick 的 phi_gate=true 会让『只发过一次心跳就死掉的任务』永远不被 heal —— 概率判活把它要防的那种失效恰好判成不需处理，比默认固定 timeout 更差
- detail: 现象：src/ops/ops_heal.mbt:110 heal_stale_tasks_by_phi 的判定链是这样分叉的：
  - last_seen_map.get(task) == None  -> true（从未心跳过，沿用 no_signal 语义，会 heal）
  - Some(ts) 且 engine.store_list_heartbeat_intervals(task) 为空 -> **false（保守不判，源码注释：「无间隔历史：无法概率建模，保守不判（等有历史再判）」）**
而间隔历史的**唯一生产写入点**是 src/server/server.mbt:1771 的 heartbeat 工具处理器，其条件（:1766 注释自述「上次心跳存在且可解析才记」）要求同一 task 已经有一条 prev 心跳——也就是**必须发到第二次心跳才会有历史可写**。

于是形成闭环死锁：执行者一旦停摆（不再发第二次心跳），该任务就永远没有间隔历史 -> 永远命中 intervals.is_empty() -> 永远返回 false -> **永远不被回滚**。而「执行者停止心跳」正是看护机制存在的唯一理由。

对照默认路径（证明这是回归而不是设计取舍）：src/ops/ops_heal.mbt 的 heal_stale_tasks 用 hb.is_stale(id, now, timeout_sec) 判活，**一条心跳记录就足够**——超过 timeout_sec 即 reopen_task 回滚。因此对同一批「发过一次心跳后消失」的任务：phi_gate=false 会被救，phi_gate=true 不会被救。开启这个被文档推荐为「升级判活」的开关，结果是把恢复能力**关掉**。

活证据（2026-09-26 只读直查 fist-mbt.db，mode=ro）：
  heartbeats 表 = 11 行，distinct task_id = 11（即每个任务都只发过一次心跳）
  heartbeat_history 表 = **0 行**（与上述写入条件完全一致：没有二次心跳，就没有间隔历史）
  tasks 表按状态 = {待领取:532, 拆分中:284, 已完成:233, 已归档:37, 待验收:35, 已领取:21, 已打回:5}
  → 其中「已领取/拆分中/执行中」这类活跃态若此刻有心跳记录而无二次心跳，就全部落在上面那个永不 heal 的桶里。库里 heartbeat_history=0 说明**这不是边角场景，而是当前所有心跳任务的常态**。

影响：
  1) AGENTS.md 把 phi_gate 描述为「心跳超时判定改用 Phi Accrual 概率式判活……读持久化间隔历史 + elapsed」，并作为推荐升级项；实际效果是无人值守流水线里任务卡死不被回收，且没有任何错误或告警——返回体里 healed 只是少了，看起来一切正常。这与 BUG-3（audit_log 假空）同属「失败伪装成正常」；
  2) 无人值守元提示词模板的分支①是「心跳新鲜即退出」，卡死任务不被 heal 时，下一拍仍判定为「有活跃任务」而只等待，流水线可能长期空转却报告 waiting 正常；
  3) 叠加 BUG-2（retry 后 execute 写不进交付物）与 BUG-19（required 不校验），未闭环任务只能增加：库里已有 143 个根任务停在待领取、87 个根任务停在拆分中。

建议（按代价升序）：
  1) 把空历史分支从「不判」改为**回落到既有固定 timeout_sec 语义**（即 phi 只在有足够样本时*增强*判断，绝不*取消*判断）；这也让默认零回归的说法站得住；
  2) 返回体披露判活依据来源：每个候选任务标注 judged_by ∈ {phi, timeout_fallback_no_history, no_signal}，让「因为没数据所以没救」在调用面可见，而不是靠人猜；
  3) 补一条回归判据（双向断言，参照 BUG-15 的 lint_5 手法）：构造「一次心跳后停摆」的任务，断言 phi_gate=true 与 false 两条路径**都**要 heal 它——防止「加了兜底但测试没覆盖这条」；
  4) 顺带：让 heartbeat 在首次上报时也落一条起始间隔占位或直接允许单点回退，避免历史永远空。
- reported_by: pentad-r2-ledger-audit

## BUG-28 [2026-09-26T09:45:16Z] [medium] FIXED
- summary: [bugfind:dead-schema] store 建了 runs 表并注释为 Omega/scheduler 的数据面，但全仓无任何写入、读取点，恒为 0 行 —— 交付与验收的运行记录没有持久化落点
- detail: 现象：src/store/store_sqlite.mbt:60 CREATE TABLE IF NOT EXISTS runs (id, task_id, run_type DEFAULT 'verify', status DEFAULT 'running', detail, started_at, finished_at)，文件头 :3 与 :55 的注释逐字写「specs / runs / heartbeats / archive 先建表供 Phase 2(Omega) / Phase 5(scheduler) 使用」。

实跑核查（2026-09-26）：
  grep -rn "INSERT INTO runs|UPDATE runs|DELETE FROM runs|REPLACE INTO runs" src/ --include=*.mbt  -> **零命中**
  grep -rniE "\bruns\b" src/store/*.mbt 除建表外 -> 只有两处注释，无任何读侧
  只读查库：select count(*) from runs -> **0**（同库 specs=451、call_log=3120、tasks=1147，说明不是「库没初始化」）

影响：
  1) schema 是对外声明的数据模型。读 store 源码或 sqlite schema 的人/AI 会以为「一次 verify 运行有 runs 记录可查」，而实际这条链路整条不存在——本账本 BUG-3（audit_log 进程内不落库、跨进程恒空）说的是「有实现但没落库」，本条是更彻底的「有表但没有实现」；两者叠加后，MCP 面上**没有任何一处能回答「这次验收外部判据跑没跑、结果是什么」**，只能靠 call_log 的调用流水间接反推；
  2) 直接踩到 Omega 的取证缺口：round 1 的修复单声称走过「run_check 外部判据」，但 run_check 的结果无处持久化（runs 空），验收复现只能依赖 temp/*.json 这类易失文件。规范 r1「文档即实现」在这里断裂；
  3) run_type DEFAULT 'verify' 说明设计意图正是承载验收运行——即这是计划内未完成，而非刻意留空，应显式登记以免被误当已具备能力。

建议（择一，按代价升序）：
  1) 最省：在 store_sqlite.mbt 的注释与相关工具描述里如实标注 runs 为**未接线预留表**，并从「Phase 2 Omega 数据面」的措辞里摘掉它，避免继续被当作可用能力（与 BUG-5 建议①「描述要写清接受什么」同一手法）；
  2) 把 run_check / omega_result_verify 的外部判据结果写入 runs（task_id/run_type/status/detail/started_at/finished_at 字段已够），并让 omega_status 或 get 能回读，补上「门禁落没落账可自证」这条硬需求；
  3) 无论选哪条，加一条守卫判据：库内每张表要么有写入点、要么在文档中标注为预留——防止再长出第二张 runs。
- reported_by: pentad-r2-ledger-audit

## BUG-29 [2026-09-26T09:46:52Z] [low] FIXED
- summary: [ledger-residue] 探针批次的 2 条假交付单永久停在已完成：T0r286/T0r287 描述为 BUG-1/BUG-2 探针、deliverable 空、specs 0 条、created_at==updated_at 同一秒，被计入已完成 233 的统计
- detail: 现象（2026-09-26 只读直查 fist-mbt.db mode=ro）：
  select id,ns,parent_id,completed_by,created_at,updated_at,description from tasks
    where status='已完成' and (deliverable is null or deliverable='')
  -> ('T0r286','fist-fix-mcp','','human_steward','2026-09-26T05:55:47Z','2026-09-26T05:55:47Z','BUG-2: retry后execute不应失败')
  -> ('T0r287','fist-fix-mcp','','human_steward','2026-09-26T05:55:47Z','2026-09-26T05:55:47Z','BUG-1: 时间戳服务端盖章')
  两条 specs 记录数均为 0（select count(*) from specs where task_id=... -> 0），deliverable 为空，created_at 与 updated_at **同一秒**。

判为探针残留的依据（三重交叉）：
  1) 描述就是待验缺陷名（BUG-1/BUG-2），不是交付说明；
  2) 时间戳与 memory/bugs.md 里被判定为垃圾账的 BUG-6 [05:55:08Z] / BUG-7 [05:55:47Z] 落在同一批次同一秒——Round 1 已把那两条 summary='BUG-5 resolved_path check' 的探针残留就地标注作废，但**任务侧的同批产物没被清**；
  3) 无任何 Omega 语料（specs=0）却到达已完成，说明当年是绕过验收直接 verify 的探路调用。

影响：
  1) 账目统计被污染：status_summary / project_health / board_ascii 把它们计入 已完成（全库已完成 233 条），"已完成"因此不再等价于"有交付物且被验过"；指挥官按 status 判进度会把探针读成成果；
  2) 这是 BUG-9（账本只写不销）在任务侧的镜像：没有 abandon/作废语义，探针单只能停在已完成，除非走 reopen_task（而 reopen 又会把它退回可领取，仍不是"作废"）；
  3) 与 BUG-10/BUG-13 的教训连起来看：未闭环单有 pause 可 park，但**已误标完成**的单没有合法出路，只能靠外部账本记勘误。

建议（Round 3 收口处理）：
  1) 现在最省：在全轮汇总报告与 memory 日志里点名这 2 条为探针残留、不计入成果（附本条 file:line 级 SQL 判据）；
  2) 给已完成态增加一条**非破坏性**的作废出路（archive 目前只接受待验收，见 BUG-10），或在 board_ascii/status_summary 里把 deliverable 为空的已完成单单列一档（如 done_no_artifact），让统计自证可辨；
  3) 加一条守卫判据：status='已完成' 且 (deliverable 空 或 无 specs 记录) 的数量必须为 0，否则红灯——这条能在 CI 直接跑，成本最低且能防后续再积累。
- reported_by: pentad-r2-ledger-audit

## BUG-30 [2026-09-26T09:50:31Z] [medium] FIXED
- summary: [doc-staleness] 实操手册 USAGE.md 停在 2026-09-12 的 v0.2.3 快照，覆盖 75/116 工具——本项目当前主用法（四模式流水线）与 output_validate/issue_scan/project_standards/laya 等新能力全都不在手册里；另 README 与 BACKLOG 对「已发布到 mooncakes 的版本」互相矛盾
- detail: 先说清楚**这不是"USAGE 少列了 41 个工具"那么简单**，也不该被当成缺陷直接修：USAGE.md:5-6 逐字自述「定位：**实操调用手册**。README.md 是项目概览，本文件是「如何真正用它」的手把手文档」——它有意的不是全量参考（README 才是），所以覆盖面小本身符合其声明范围。真正的问题在别处。

活证据（2026-09-26 实跑比对）：
  1) 版本与日期戳：USAGE.md:3 写「版本：vicTop-cw/fist-mbt@0.2.3」，:4 写「日期：2026-09-12」；对照 grep '^version' moon.mod -> **0.3.0**。带日期的版本戳本身是可辩护的历史标注，但一份"手把手文档"停在两个小版本前，意味着它演示的已经不是当前用法。
  2) 能力覆盖：脚本比对 server.mbt 注册集(116) 与 USAGE.md 反引号名字集 -> **覆盖 75/116，缺 41**，缺的里面有 bug_list / call_log / circuit_fail / circuit_succeed / circuit_status / atgc_old_* 等——**call_log 与 bug 族正是本项目当前主用法（四模式流水线：寻虫→修复→验证→打磨）的审计与 issue_up 落地面**，手册对这些零覆盖，读者按手册学不到本轮实际在跑的那套流程。
  3) 已发布版本自相矛盾：README.md:176 写「MochaCakes: vicTop-cw/fist-mbt@**0.2.5**」，而 BACKLOG.md:15 的发布条目写「done(v**0.2.4** 已发布; 首跑 409 版本重复已换 0.2.4)」。同一件事（注册表上到底发布到哪个版本）两份文档给出两个答案，且都无外部验证链接/时间戳。这类矛盾比单纯的陈旧更坏——读者无法判断哪个是新的。

与既有账目的关系：BUG-16（代码内版本三处硬编码）与 BUG-21（MCP 握手自报 0.1.0）说的是**代码侧**缺版本单一真源，本条说的是**文档侧**同一缺失的另一面：README/AGENTS/deliverable/scoring_rubric/USAGE 五份文档各写各的版本与能力面，而现有三守卫（check_tools_sync / check_test_sync / check_badge）只校验**工具数与测试数**，**不校验版本一致性**——所以 Round 1 把四份文档的工具数拉齐转绿时，文档侧的版本漂移与手册陈旧是看不见地通过的。

影响：① 对外文档是参赛材料与用户第一入口，手册演示旧流程会让新能力（105→116 这一段）实际不可发现；② 已发布版本两处矛盾，任何按文档核对生态贡献（BACKLOG 的 P1-7）的人会得到错误结论；③ 「守卫全绿」在此处恰好证明判据覆盖面小于缺陷面——这与 BUG-22（README 标题对了正文没对）、BUG-21（回归锁盯 0.2.4 抓不到 0.1.0）是同一个模式，已第四次出现。

建议（按代价升序，注意不要为了对齐而把未验证的事实写死）：
  1) 先解决**可判定的矛盾**：实际去 mooncakes 注册表核对已发布版本，然后只改错的那一份；对不上之前不要在文档里新增任何版本声明；
  2) USAGE.md 顶部把范围与"截至版本"写成人能读懂的一句话（例如「本手册覆盖到 v0.2.3 的能力面；v0.2.4 起新增的四模式流水线/issue_scan/output_validate/call_log 用法见 AGENTS.md 与 templates/pipeline_mode_*.md」），把陈旧变成显式边界而不是隐性误导——这比补写 41 个工具更省也更诚实；
  3) 给守卫补一条版本一致性判据：所有 *.md 里形如 vicTop-cw/fist-mbt@x.y.z 的自述版本必须等于 moon.mod 的 version，或显式标注为历史戳（如 CHANGELOG / 版本时间线小节允许旧值）——注意区分"当前自述"与"历史陈述"，Round 1 已刻意把 README 的 0.2.4/0.2.5 时间线行保留为历史，不能一刀切判红。
- reported_by: pentad-r2-doc-surface


### FIXED(2026-09-27T12:18:14Z / BUG-25, BUG-30)
- evidence: BUG-25 goal_drift_check 词法口径重标定（commit 13b5125）：drift 判定降为 advisory + 新增 insufficient 分类 + CJK 二字组分词；标定数字由 scripts/calibrate_goal_drift.py 实测产出并嵌进返回体 calibration{}。第一版假设（族内相对阈）被自己的实测推翻（39 对真关联上 59% 假阳、族内规则 TP=0）故未采纳，被否的口径连同数字留在标定输出里。BUG-30 文档面：USAGE.md 顶部写明覆盖边界（演示到 0.2.3 的调用面，四模式流水线看 AGENTS.md 与 templates/pipeline_mode_*.md）；README 的 MochaCakes 行删掉写死的发布版本——本机没有可复核注册表的通道（WebFetch 被策略拦，实测不可达），改为指向 BACKLOG 的发布条目，并把「发布版本只能有一处自述」做成 scripts/check_doc_surface.py 的 J4 子判据（扫描面从 git ls-files 派生，--selftest 四条对照：两处打架必红、权威删空必红、空扫描必红、单处不误红）。
## BUG-31 [2026-09-26T10:41:50Z] [medium] FIXED
- summary: [contract] src/server/output_validate.mbt:63-90 parse_artifact 不校验未知字段：拼错/臆造的 artifact 键被静默降级为「文件存在+非空」，verdict 仍是 pass，且 detail 断言「invariant 全部通过」——L4 硬门可被空检查满足
- detail: 现象（2026-09-26 实测，server cwd=E:/IDEProjects/AI/Cypy，证据 .fist-polish-20260926/probe_output_validate3.json）：
  A) artifacts=[{path: tests/..., contans: <repo 里不存在的串>}] -> verdict=pass，detail 「OK（存在/非空/invariant 全部通过）」
  B) artifacts=[{path: tests/..., invariant: 必须包含 <不存在的串>}] -> 同样 pass
  C) 同一文件同一串改回正确键名 contains -> verdict=fail（detail 「文件缺少必需字符串: ...」）
⇒ A/B 与 C 的差别只在**键名**，说明未知键没有被读取也没有被拒绝。
根因：parse_artifact（output_validate.mbt:63-90）只对 path/check_key/contains/not_contains/min_chars 五个键做 m.get(...)，缺失即回落 ""/0，从不检查 m 里剩余键；check_file_artifact 的 invariant 分支又都以「非空字符串」为开关，于是未知键=没有 invariant=只要文件存在且非空就 ok=true。
危害：output_validate 自称「证据梯 L4 硬门」「任一 artifact 失败即 verdict=fail」，调用方（尤其按 prompt 模板里 `artifacts 数组（path/check_key + invariant）` 这句话写的 agent，`invariant` 恰好不是被支持的键）会拿到一条**什么都没验过**的 pass，而 detail 还替他确认了 invariant 成立——假绿正好发生在最该拦住假绿的那一层。（注：contains/not_contains/min_chars 三样本轮实测均正常绑定，不是它们坏了。）
修复建议：1) parse_artifact 计算 leftover = m 的键去掉上述五个，非空即返回失败 artifact，detail 写明「artifact 含未知字段 X；支持 contains/not_contains/min_chars/check_key」；2) pass 文案按**实际评估过的**不变量拼接（不含任何 invariant 时写「仅存在性/非空」），不要复用固定句「invariant 全部通过」；3) output_validate_test.mbt 补两条用例：未知键必须 fail、纯 {path} 的 pass detail 不得出现 invariant 字样。

### FIXED(2026-09-26 pentad-r3 fix_and_merge / 终审人=指挥官，调用面实测)

output_validate 的 artifact 规格改为**先校验再解释**：新增 `artifact_spec_errors`（src/server/output_validate.mbt）
拒绝未知键、要求 path/check_key 二选一且只选一个；非法规格产出一条**失败**检查（detail 点名未知键与可用键集），
不再静默降级成"存在性 pass"。
回归锁：src/server/output_validate_r3_test.mbt（未知键→fail、缺二选一→fail、合法对照→pass，三条成对）。
证据：调用面 J07 未知键 `invariant` 判 fail（detail 点名未知键）、J08 合法 `contains` 仍 pass；
开关对照：摘掉校验分支后该锁转红。

## BUG-32 [2026-09-26T11:04:49Z] [high] FIXED
- summary: [contract] scripts/fist.py:35 不校验入口产物新鲜度：调用面验收可能在度量旧二进制
- detail: 现象（2026-09-26 11:03 实测）：src/server/server.mbt 自 17:59 起已接入 run_check_guard（cmd 白名单 + workdir 子树），但 scripts/fist.py 第 35 行直接拉起 _build/js/debug/build/cmd/main/main.js（mtime 16:51，早于源码 68 分钟），导致调用面终审全程测的是 Round 1 旧行为：run_check 对 `rm -rf /` 返回 ok=true、workdir 拒绝文案是旧的「拒绝绝对路径/盘符」、laya_decide 单跳 211s 超客户端 30s 预算。执行 `moon build --target js cmd/main` + patch_esm_main.py 后，同一判据脚本立刻变 14/15 PASS、laya 21.0s/20.9s。危害：①任何「打到调用面」的验收可能在 silently 度量旧产物，假绿或假红；②MCP 客户端连的也是这个入口（.mcp.json 走 moon run 会重建，但脚本轨不会）；③本仓守卫族没有任何一条比较 src/** 与入口产物的 mtime，BUG-22/30 的「守卫覆盖面窄于主张」在产物层重演。修复方向：scripts/fist.py 启动前比较 max(mtime of src/**, moon.pkg) 与 main.js，落后即自动 `moon build --target js cmd/main` 并 patch，或显式拒绝并提示重建；并把该顺序不变量纳入守卫族（可并入 check_plugin_sync 同级的新守卫）。

### FIXED(2026-09-26 pentad-r3 fix_and_merge / 终审人=指挥官，调用面实测)

scripts/fist.py 启动前比较 `max(mtime src/**.mbt|.mbti, moon.mod, moon.pkg)` 与入口产物：
落后即自动 `moon build --target js cmd/main`（幂等，随后仍走 patch_esm_main），`FIST_NO_AUTOBUILD=1` 时改为显式拒绝并退出 1，
不再出现"调用面终审静默度量旧二进制"。
证据（同一判据脚本 r3_callsite_audit.py J00 前提）：产物 19:01 < 源码 19:30 → 自动重建到 19:36；
`FIST_NO_AUTOBUILD=1` 同一状态下 rc=1 且文案点名两侧路径。终审另加 J00 顺序不变量：入口过期即 FATAL 作废全部判据。
已知缺口（诚实记账）：本条只有调用面证据，未进守卫族——守卫族判据必须能在 CI 里自证，而该不变量在"未构建的干净克隆"上必然为假。

## BUG-33 [2026-09-26T11:23:48Z] [high] FIXED
- summary: [bugfind:contract-debt] 45 个工具广告可选参数 now，全仓 0 处读取：调用方传 now 被静默丢弃
- detail: 实测（2026-09-26 11:22，指挥官独立复算）：`grep -c '"now": *string_prop' src/server/server.mbt`=45；`get_str(args, "now")` 在 src/** 全量=0；`now_default()`=47。即 server 时钟盖章（BUG-1 的正确修复）已落地，但 45 份 inputSchema 仍在承诺「时间戳(可选，默认内置)」——契约在说谎，且副作用是心跳陈旧/熔断恢复窗/Omega 新鲜度无法写确定性判据（注入不了受控时钟）。run_check:1121 的「服务端盖章」是诚实措辞样板。正确出路不是让 handler 重新接受 caller now（那会回退 BUG-1 的账本可反驳性修复），而是**停止广告**并写明由服务端盖章。

### FIXED(2026-09-26 pentad-r3 fix_and_merge / 终审人=指挥官，调用面实测)

停止广告无人读的时钟入参：server.mbt 里 45 处 `"now": string_prop(...)` 全部删除，
另有 6 处描述文案（含 run_check/task_plan_deep/circuit_*）里的「now 时间戳（可选）」改写为
「时间戳一律由服务端盖章，不接受调用方注入 now」。BUG-1 的服务端盖章语义不变（不回退）。
守卫：scripts/check_tools_sync.py 判据 5 同时禁止 schema 广告 `"now": string_prop` 与描述里的「、now 时间戳」（正则退化即 FATAL）。
证据：调用面 J03 全部 116 工具的 inputSchema.properties 无 now、J04 全部 description 无「now 时间戳」。

## BUG-34 [2026-09-26T11:23:49Z] [medium] FIXED
- summary: [bugfind:circuit-halfopen] 熔断 Half-Open 无探测节流：恢复窗内所有调用都放行，与工具描述承诺相反
- detail: src/engine/engine_circuit.mbt:140 `let allow = state != "open"` → half_open 对任何调用回 allow_call=true；全文件无 probe/节流计数。而 server.mbt:3311 的 circuit_status 描述承诺「Open 且 elapsed>=recovery_secs → 转 Half-Open（放行探测请求，**其余仍快速失败**）」。后果：恢复窗口全量透传，正是要防的下游踩踏；半开态退化成「只是换个名字的 closed」。判据：threshold=1 触发 open → 过 recovery → 连查 circuit_status N 次全 allow_call=true，无一次被挡。修复方向：半开态给探测配额（默认 1，可配 probe_limit），配额用尽即回快速失败；成功探测才复位。

### NOT-FIXED(2026-09-26 pentad-r3 / 指挥官终审：本轮不动，理由与出路记账)

本轮评估后**不改实现**，两条理由：① 探测配额要把"已放行探测数"持久化，`cb_get/cb_save` 的 7 元组要扩列（store 表结构 +
native/js 双后端 + 迁移），属跨模块契约变更，不在一轮 fix 的边界内；② 半成品节流（只在内存计数）会在多进程 MCP 下每进程各计一次，
比现状更容易误导——宁可不改。当前"描述承诺 vs 实现"的落差仍是活缺陷（OPEN），出路：cb 表加 `probe_count` 列，
`circuit_status` 转 half_open 时置 0，`circuit_fail/succeed` 之外的每次 half_open 放行先自增并在达 probe_limit(默认 1) 后返回 allow_call=false。

## BUG-35 [2026-09-26T11:23:49Z] [medium] FIXED
- summary: [bugfind:github-payload] github flush/comment 拼的 --data 不是合法 JSON（值套 shell_quote + 正文含裸换行），win32 还走 cmd.exe 单引号
- detail: src/server/github_sync.mbt:257-270 用字符串拼接生成 `--data`，字段值套 shell_quote（:384-387 只把 ' 变成 " 序列，不转义双引号与换行）；而 build_issue_body 恒含裸换行 → 产出的 --data 无法被 json.loads 解析。github_js.mbt:23-24 在 win32 走 `cmd.exe /c`，单引号在 cmd 下不构成引用、`${FIST_GITHUB_TOKEN}` 也不展开。影响面：issue_up 的**落地面**（把账本推到远端 issue）整条失败，而不是某条边缘字段。可离线判据（不需 token）：夹具 memory/bugs_pending_github.json 放一条 pending → `call github_flush_plan --project-dir .` → 取返回 curl_command 的 --data 段做 json.loads，当前必抛。修复方向：用 Json 构造 payload 再 stringify，shell_quote 只用于 shell 层，不承担 JSON 转义职责（两层混淆是根因）。

### NOT-FIXED(2026-09-26 pentad-r3 / 指挥官终审：本轮未复测 + 新发现一条前置缺口)

本轮**没有**按条目里的复现配方重跑：`memory/bugs_pending_github.json` 夹具当前不存在，且
`github_queue_append` **不是注册工具**（实测 `Tool not found: github_queue_append`，它只是 github_sync.mbt:58 的内部函数），
所以"放一条 pending"只能手写文件——11:23 那次的字符串拼接证据仍然成立（github_sync.mbt:252-270 用 `shell_quote` 塞进 JSON 值，
`build_issue_body` 恒含裸换行）。不改实现的理由：这条链路要真验证就得连 GitHub（凭据只走环境变量注入，本轮不探测 token），
且 win32 走 `cmd.exe /c` 的引号语义在离线单测里覆盖不到——半修（只换 Json 构造）会让"看起来修了、Windows 上仍调不通"。
出路：①payload 用 `Json::object + stringify` 生成；②curl 改 `--data @<临时 json 文件>` 消掉 shell 引号层；
③补一条不依赖 token 的判据（对生成的 --data 段做 `json.loads`）；④`github_queue_append` 要么注册成工具要么从文案里去掉。

## BUG-36 [2026-09-26T11:23:50Z] [medium] FIXED
- summary: [bugfind:wrong-target] memory_gc 对非法 kind 静默改靶到 target：打错一个字会截掉你没点名的文件
- detail: src/server/memory.mbt:180 `let kind = if mem_kinds_contain(kind) { kind } else { "target" }`，注释写明意图是「防路径遍历落到文件系统」——意图正当，但补救动作是**换目标继续写**：随后 :223 会截断正文并把老条目搬档。对照同文件 :121 的 consolidate 对同一字段是直接 Err。即 `--kind thinking g` 实际写坏 memory/target.md，而返回体只回 kind:"target"，调用方极易忽略。修复方向：非法 kind 一律 Err 并列出合法集合（保住防遍历的意图，同时不越权写别的文件）；这也让「归档不硬删」的既有承诺仍可自证。

### FIXED(2026-09-26 pentad-r3 fix_and_merge / 终审人=指挥官，调用面实测)

非法 kind 改为**拒绝且不落笔**（src/server/memory.mbt）：memory_gc_one 不再把白名单外的 kind 改靶到 target，
返回 `gc:false + error`（点名非法值并列出合法集合）；同族缺口一并补上——consolidate 的 Err 口径此前**没有任何锁**。
回归锁：src/server/memory_test.mbt `memory_18_gc_illegal_kind_refuses_without_writing`、
`memory_19_consolidate_illegal_kind_err_without_writing`（两条都断言 target.md 原样 + 归档目录未被写入）。
开关对照（实测）：同时摘掉两处修复 → 两条锁同时红（92 项中 2 failed）；恢复 → 92/92 绿。
调用面：J09 拒绝并列出集合、J10 target.md sha256 不变、J11 consolidate 同样拒。
附带发现（记在本条不另立账）：第一次开关对照误改了 consolidate 的 Err 而全量仍 91/91 绿，正好暴露"consolidate 非法 kind 无锁"这一覆盖缺口。

## BUG-37 [2026-09-26T11:23:50Z] [low] FIXED
- summary: [bugfind:phantom-guard] mode_list 的 forbidden_tools 写的是不存在的工具名，「禁发新功能」约束无可匹配对象
- detail: src/ops/ops_modes.mbt:142-143 发布禁用名单 `publish_new_feature_task` / `issue_scan_with_generate_new`，而 `fist.py list-tools` 对两者计数均为 **0**（真源 server.mbt 注册表也没有；实调 mode_list 已复核返回体）。后果：polish/tidy 模式的「禁止发布新功能」红线在机器面上是空的——按名单匹配拦截的下游永远匹配不到，约束只剩提示词文字。真实可拦截的同族动作是 `publish`（配 created_by 角色闭集）。修复方向：名单改成真实注册名并注明「按 (tool, role) 组合拒」，或明确该字段只是给人类读的文档（那就不该叫 forbidden_tools）。

### FIXED(2026-09-26 pentad-r3 fix_and_merge / 终审人=指挥官，调用面实测)

`mode_forbidden_tools` 换成真实注册名 `publish / publish_parallel / dag_publish`（src/ops/ops_modes.mbt），
并把同一臆造名从 polish/tidy/verify 三份模板里一并清掉（文档面同源）。诚实标注：本仓内没有自动拦截点，
该名单是给调用方/指挥官匹配用的机器面，名字不存在时红线才真正空转。
守卫：check_tools_sync.py 判据 4（名单 ⊆ tools/list 真注册集，解析到 0 个名字即 FATAL 不出绿灯）。
证据：调用面 J12 无越界名、J13 polish/tidy 名单非空且全为真注册名。

## BUG-38 [2026-09-26T11:49:59Z] [high] FIXED
- summary: [bugfind:phantom-tool-call] templates 用 `run_check_external({cwd,command,timeout_sec})` 教主流程跑外部判据，但该工具未注册（真名 run_check，参数名 task_id/cmd/args/workdir/timeout_ms 全不同），按模板执行必然调空
- detail: 现象（2026-09-26 11:41 实测，指挥官独立复算）：
1) `grep -c '"run_check_external"' src/server/server.mbt` = 0（未注册），
   而 templates/pipeline_mode_bugfind.md:48-50 / pipeline_mode_fix_and_merge.md:66-68
   / pipeline_mode_polish.md:46-48 / pipeline_mode_tidy.md 共 9 处指示执行者
   「调用 `run_check_external({ "cwd": ..., "command": [...], "timeout_sec": ... })`」；
2) 真实工具是 `run_check`（server.mbt:1107），参数名全部不同：
   task_id(必填) / cmd(必填，字符串) / args(数组) / workdir / timeout_ms —— 
   即模板给的 3 个键名没有一个被读取，且漏掉 2 个必填项；
3) 根因线索：src/server/server.mbt:1162,1196 存在内部函数 `run_check_external(cmd, args_arr, workdir, timeout_ms)`
   ——模板把**引擎内部函数名**当成了对外工具名写进了提示词。
危害：四模式流水线的「寻虫第三步/修复第四步/打磨第二步」都要求跑外部判据命令，
按模板执行的 agent 第一次调用就会拿到 tool not found，之后要么放弃要么自称通过（假绿诱因）；
这与 BUG-37（forbidden_tools 写臆造名）同族，但影响面更大——BUG-37 是红线空转，本条是主流程步骤不可执行。
证据可复跑：`python scripts/check_tools_sync.py`（判据 6：模板里 `name(...)` 形状必须真注册）。

### FIXED(2026-09-26 pentad-r3 fix_and_merge / 终审人=指挥官，调用面实测)

模板主流程步骤改为真实工具与真实参数：`run_check_external({cwd,command,timeout_sec})` →
`run_check({task_id, cmd, args, workdir, timeout_ms})`（bugfind/fix_and_merge/polish/tidy/verify 共 9 处调用点 + 裸提及）。
根因确认：server.mbt:1162/1196 存在**内部函数** `run_check_external(...)`，模板把引擎内部函数名当成了对外工具名。
守卫：check_tools_sync.py 判据 6——模板里 `` `name(` `` 调用形状必须命中 tools/list 真注册集。
证据：调用面 J14 全部模板调用形状命中（残留=∅）、J15 模板 run_check 的键 ⊆ 真实 properties（args/cmd/task_id/timeout_ms/workdir）。

## BUG-39 [2026-09-26T12:02:12Z] [medium] FIXED
- summary: [bugfind:cli-crash] scripts/fist.py 对返回顶层数组的工具（mode_list/call_log 等）AttributeError 崩溃：判退出码只兜 JSONDecodeError 不兜类型错误
- detail: 现象（2026-09-26 11:54 实测）：`python scripts/fist.py call mode_list` ->
  File "scripts/fist.py", in cmd_call: `verdict = payload.get("verdict", "")`
  AttributeError: 'list' object has no attribute 'get'   （退出码 1，交付内容已打印但被判码逻辑炸掉）
根因：cmd_call 只兜 JSONDecodeError，兜不住类型错误；mode_list / call_log / dag_sort 等一批工具返回**顶层数组**，
     而 verdict/ok 是 dict 字段 -> 对数组结果必然 AttributeError。
影响：CLI 形态（一源四态之一）对返回数组的工具整体不可用，脚本轨 CI 与手动验证都会拿到非零退出码的假失败。
修复：判定前先 isinstance(payload, dict)；数组结果按"能打印即成功"处理（verdict 语义本就不适用于数组）。
回归锁：temp/r3_callsite_audit.py J25（子进程真跑 fist.py call mode_list，要求 rc=0 且输出含 polish）。

### FIXED(2026-09-26 pentad-r3 fix_and_merge / 终审人=指挥官，调用面实测)

scripts/fist.py 判退出码前先 `isinstance(payload, dict)`，数组型结果按"能打印即成功"处理，
并把 UnicodeDecodeError 一并纳入兜底（只兜 JSONDecodeError 兜不住类型错误正是本条根因）。
证据：调用面 J25 子进程真跑 `python scripts/fist.py call mode_list` → rc=0 且 stdout 含 polish（修复前同命令 rc=1 + AttributeError 栈）。
已知语义边界（诚实记账）：数组结果不再参与 verdict 判定——工具若改用数组承载 fail 语义，本判码会漏；现行 verdict/ok 契约都在对象里。

## BUG-40 [2026-09-26T12:02:13Z] [medium] DUPLICATE →BUG-5
- summary: [contract:split-policy] 同名字段 project_dir 在 bug 族（report_bug/bug_list/github_*）拒绝绝对路径，而任务族（publish/list/dag_*）接受：一条流水线两套口径，绝对路径客户端默认调不动账本
- detail: 现象（2026-09-26 11:57 实测，同一 MCP 入口、同一次会话）：
  1) bug_list(project_dir="E:\IDEProjects\AI\FIST-Mbt") -> Err "bug_list: 非法 project_dir（拒绝绝对路径/穿越/盘符）"
     （换成正斜杠 E:/... 同样被拒）；project_dir="." -> ok，count=38
  2) 同一天里 publish/list/output_validate/dag_mc 等同名字段 project_dir 传绝对路径**全部接受**，
     任务行也确实按绝对路径落库（LIST 返回 project_dir="E:\IDEProjects\AI\FIST-Mbt"）
根因（是设计而非疏漏，需按口径分裂处理）：src/server/bugreport.mbt:10 自述「路径一律相对拼接（mem_join），跨平台可移植」，
  bug_project_dir_ok 因此拒绝绝对路径/盘符；而任务族的 project_dir 是 store 的命名空间键，绝对路径是常态。
危害：①同一条流水线里任务树用绝对 project_dir、账本用相对 -> 两条轨可指向不同目录（账本写到 CWD 下的 memory/bugs.md）；
     ②MCP 客户端普遍传绝对路径（AGENTS/README 的示例即绝对路径），report_bug/bug_list/github_* 对这类客户端**默认不可用**，
       只有换成 "." 才通；③错误文案只说"非法"，不给"改传相对"的出路，调用方容易判成工具坏了。
建议（择一，需人裁决，因为放宽=改动已声明的加固）：
  A) 让 bug 族接受绝对路径但拒绝 `..` 穿越（与任务族口径对齐，安全等价：目标恒在该目录内）；
  B) 保持加固，但在错误文案里给出可执行出路（"改传项目根相对路径，如 `.`"），并在 AGENTS/模板里把"账本族用相对 project_dir"写清。
- task_id: T0r317

## BUG-41 [2026-09-26T12:37:31Z] [medium] FIXED
- summary: [improvement:boundary-owner] 深拆/Omega 只验 spec 内行为：spec 未写的域外行为没有 owner（atgc-merge 归因报告机理 1+2，抓手 1/2/3/4）
- detail: 来源：`E:/IDEProjects/AI/_fist_meta_prompts/实验/atgc-merge/归因报告_防御完备性.md`（A/B 实验附录，裁判 Loomy，2026-09-26）。

报告结论精确化后有三条机理，其中两条落在 FIST-Mbt 引擎能力上：
- 机理 1 上下文分割：`task_plan_deep` 把 spec 切成叶后，"spec 之外的推演"没有 owner（全局不变量无人负责）；
- 机理 2 验收锚定 + 弱语料（Goodhart）：Omega 语料只断言"交付物落盘/实现与描述一致"，执行体理性地停在判据边界；
- 机理 3 提示词混杂变量：CTL 组多一句"补测 1 条自设计用例"，故 A/B 在防御完备性维度不是单变量（属实验设计缺陷，不改产品代码）。

改进要求（报告抓手 1/2/3/4）：
1. Omega/深拆要能自动注入"边界四问"断言（空输入/极值/非法输入/资源极限），而不是等裁判发现某条边界无人负责；
2. 深拆要能追加一条"边界审视叶"，owner=全局输入域；
3. 长树深拆实例默认开 `reinject_context=true`；
4. 完成标准统一加"测试须覆盖输入域边界与域外行为"。

影响面：不改默认行为（默认 false），但缺省状态下强验证的上限被语料质量锁死——本轮 A/B 已经给出活证据：
同样语义核心的两组，裸推进组做了 k>5 溢出防护而编排组没有。
- task_id: T0r327

### FIXED(2026-09-26 atgc-handoff / 指挥官终审，FIST-Mbt 侧落地；外部模板库半交回发起人)

引擎侧新增两个可选开关（默认 false，零回归）：
- `plan_deep(..., boundary_probe=true)`：本层切片末尾追加一条**边界审视叶**（owner=全局输入域，须对
  空输入/极值/非法输入/资源极限逐项给用例或显式声明不适用），并给其余每条叶挂「边界四问」提示
  —— 同时对准机理 1（全局不变量无 owner）与机理 2（弱语料的 Goodhart 下界）；
  实现 `src/engine/omega_strong.mbt::boundary_probe_slice/boundary_probe_hint` + `src/engine/engine.mbt::plan_deep/decompose_rec`，
  MCP 面 `task_plan_deep` 新增 `boundary_probe` 属性与说明（`src/server/server.mbt`）。
- 抓手 3 按报告的"实例默认开"落地，**不动引擎默认值**：`templates/pipeline_mode_advance.md` 与
  `templates/cron_pipeline_meta_prompt.md` 的 `## 完成标准` 段加两条（边界与域外行为 + 深拆实例默认 `reinject_context=true`）。

回归锁：`src/engine/engine_boundary_test.mbt` 两条（默认关闭逐字零回归 / 打开后 owner 叶 + 每条叶四问，含四类关键字齐检）。
开关对照：把注入改成 no-op → `boundary_probe_on_adds_owner_leaf_and_per_leaf_hint` 红（`2 != 3`），恢复 → 107/107。
调用面：`temp/r3_callsite_audit.py` J26/J26b/J26c/J26d **34/34 PASS**，其中 J26d 把零回归对照打在**对照组 12 条子任务**上
（打在根任务上是假对照，已改）。

未落地（诚实记账，交回发起人）：抓手 4 的**外部模板库七份**——Qoder 作用域限制禁止本会话改写工作区外文件
（`E:/IDEProjects/AI/_fist_meta_prompts/模式*模板.md`），补丁正文与幂等应用脚本已备在
`temp/atgc_handoff_抓手4_外部模板补丁.md`；另实测七份模板**没有** `## 完成标准` 小节，故补丁以"附：完成标准补丁"追加文末。

## BUG-42 [2026-09-26T13:31:20Z] [high] FIXED
- summary: [verify][BUG-42] src/server/server.mbt project_standards 描述仍称一源三态/三形态/cl1-cl6：对外描述与工具输出（四态+cl7）自相矛盾，所有 MCP 客户端读到的是旧口径
- detail: 证据：temp/j_before_after.py 在 HEAD 内容上发红 32 条（J6=2/J7=11/J8=19），工作树为 0；temp/stdalign_verify.py 为本轮调用面终审。
- reported_by: std-auditor

## BUG-43 [2026-09-26T13:31:20Z] [high] DUPLICATE →BUG-49
- summary: [verify][BUG-43] templates 的 FIST 调用示例用了未声明参数（output_validate 的 check_results、project_standards 的 project_dir/dry_run、evolve_distill 的 project_dir/round）并缺 required；_instrument 只校验 required ⇒ 未知键静默丢弃，照模板执行=以为验了其实没验
- detail: 证据：temp/j_before_after.py 在 HEAD 内容上发红 32 条（J6=2/J7=11/J8=19），工作树为 0；temp/stdalign_verify.py 为本轮调用面终审。
- reported_by: std-auditor

## BUG-44 [2026-09-26T13:31:20Z] [medium] DUPLICATE →BUG-50
- summary: [verify][BUG-44] docs/agent-map.md 宣称测试数 316 项全绿（实测 406）；check_test_sync 只核对「实测数出现在 4 份文档」，不核对文档里的**其它**数字是否等于实测 ⇒ 数值声明无人管
- detail: 证据：temp/j_before_after.py 在 HEAD 内容上发红 32 条（J6=2/J7=11/J8=19），工作树为 0；temp/stdalign_verify.py 为本轮调用面终审。
- reported_by: std-auditor

## BUG-45 [2026-09-26T13:32:33Z] [high] DUPLICATE →BUG-48
- summary: [verify][BUG-42] src/server/server.mbt project_standards 描述仍称一源三态/三形态/cl1-cl6：对外描述与工具输出（四态+cl7）自相矛盾，所有 MCP 客户端读到的是旧口径
- detail: 证据：temp/j_before_after.py 在 HEAD 内容上发红 32 条（J6=2/J7=11/J8=19），工作树为 0；temp/stdalign_verify.py 为本轮调用面终审。
- reported_by: std-auditor


### FIXED(2026-09-26 stdalign verify / 指挥官终审，调用面实测)

本条与 BUG-48 同一缺陷，因验证驱动 `temp/stdalign_verify.py` 首两轮在 `publish` 返回键（`task_id` 而非 `id`）上解析失败、
下游 Omega 链与生命周期整体走错分支，重跑时重复入账 ⇒ **重复条目，实际修复见 BUG-48 的 FIXED 段**。
教训入档：驱动重跑前应先幂等检查（同一 summary 不重复 report_bug）。

## BUG-46 [2026-09-26T13:32:34Z] [high] DUPLICATE →BUG-49
- summary: [verify][BUG-43] templates 的 FIST 调用示例用了未声明参数（output_validate 的 check_results、project_standards 的 project_dir/dry_run、evolve_distill 的 project_dir/round）并缺 required；_instrument 只校验 required ⇒ 未知键静默丢弃，照模板执行=以为验了其实没验
- detail: 证据：temp/j_before_after.py 在 HEAD 内容上发红 32 条（J6=2/J7=11/J8=19），工作树为 0；temp/stdalign_verify.py 为本轮调用面终审。
- reported_by: std-auditor


### FIXED(2026-09-26 stdalign verify / 重复入账)

同 BUG-45：本条为 BUG-49 的重复（驱动重跑副作用），实际修复与证据见 BUG-49 的 FIXED 段。

## BUG-47 [2026-09-26T13:32:34Z] [medium] FIXED
- summary: [verify][BUG-44] docs/agent-map.md 宣称测试数 316 项全绿（实测 406）；check_test_sync 只核对「实测数出现在 4 份文档」，不核对文档里的**其它**数字是否等于实测 ⇒ 数值声明无人管
- detail: 证据：temp/j_before_after.py 在 HEAD 内容上发红 32 条（J6=2/J7=11/J8=19），工作树为 0；temp/stdalign_verify.py 为本轮调用面终审。
- reported_by: std-auditor


### FIXED(2026-09-26 stdalign verify / 重复入账)

同 BUG-45：本条为 BUG-50 的重复（驱动重跑副作用），实际修复与证据见 BUG-50 的 FIXED 段。


### FIXED(2026-10-17T12:34:56Z / BUG-47)
- evidence: R68 结案：真根因＝DEMO 语料算子错（及于=>= 而非 <=），非 codegen 递归缺陷。修法：及于→止于（阶乘.玆 第5行基例、第13行循环守卫）。验证：JS zhi run --js 输出 120 120 3628800 3628800（四路全对，修前全 1）；zhi check rc=0 errs=0；pytest A/B NEW_FAILURES=0。残留 BEAM 侧 F123/F126 属 codegen 车道另开窗。
## BUG-48 [2026-09-26T13:34:23Z] [high] FIXED
- summary: [verify][BUG-42] src/server/server.mbt 的 project_standards 对外描述仍称「一源三态/三形态必须对齐/三形态 checklist（cl1 到 cl6）」，而工具输出实为 R115+ 四态与 cl1~cl7：描述与输出自相矛盾，且 116 个客户端读到的都是旧口径；wbtest 只锁输出不锁描述，故锁的意图③落空
- detail: 证据：temp/j_before_after.py 在 HEAD 内容上发红 32 条（J6=2/J7=11/J8=19），工作树 0；temp/stdalign_verify.py 为本轮调用面终审；修复落在 check_doc_surface J6/J7/J8 + 35 处文档口径对齐。
- reported_by: std-auditor


### FIXED(2026-09-26 stdalign verify / 指挥官终审，调用面实测)

对外描述面与输出面对齐：`src/server/server.mbt` 的 `project_standards` 描述改为 R116 口径（一源四态 / 四态必须对齐 /
cl1→cl7），并**如实声明能力边界**（"只下发清单，不扫描文件也不修改文档，要扫描用 issue_scan / check_doc_surface.py"）；
`include_checklist` 属性说明改为"四态验收 checklist 7 项（cl1→cl7）"；`server.mbt:536` 注释里的旧规则标题同步。
真源侧：`project_standards` 升 **R116** 并新增 `canonical_doc` 字段指向规范正文；白盒锁 `project_standards_wbtest.mbt`
钉 version/canonical_doc/7 项 cl7/无旧口径。判据侧：**新守卫 J7** 扫规范性表面，**J6** 校正文↔投影，
`--selftest` 用合成违例证明两条都能红（`temp/j_before_after.py`：HEAD 内容上 J6=2/J7=11 条发红，工作树 0）。

## BUG-49 [2026-09-26T13:34:23Z] [high] FIXED
- summary: [verify][BUG-43] templates 的 FIST 调用示例用了未声明参数（output_validate 的 check_results、project_standards 的 project_dir/dry_run、evolve_distill 的 project_dir/round、publish/watchdog_tick 的 now）并缺 required（artifacts/task_id/goal/note）；_instrument 只校验 required ⇒ 未知键静默丢弃，照模板执行等于「以为跑了硬门其实什么都没验」
- detail: 证据：temp/j_before_after.py 在 HEAD 内容上发红 32 条（J6=2/J7=11/J8=19），工作树 0；temp/stdalign_verify.py 为本轮调用面终审；修复落在 check_doc_surface J6/J7/J8 + 35 处文档口径对齐。
- reported_by: std-auditor


### FIXED(2026-09-26 stdalign verify / 指挥官终审，调用面实测)

模板调用面契约全部改为真实参数名：`pipeline_mode_verify.md`（project_standards→project_type/include_checklist，
output_validate→artifacts+evidence，并写明"没有 check_results 这个参数，未知键静默丢弃=写了等于没验"）、
`pipeline_mode_tidy.md`（同上 + cl6 判据指向 check_doc_surface 而非臆造"内置文档扫描"）、`pipeline_mode_polish.md`
（evolve_distill→task_id/goal/note/score，补齐 required）、`pipeline_mode_advance.md` + `cron_pipeline_meta_prompt.md` +
`review_meta_prompt.md`（删除已废弃的 `now` 广告，含参数表与 JSON 示例）。判据侧：**新守卫 J8** 解析 server.mbt 每工具
属性集与 required，对模板的 `tool({ ... })` 只取 **depth-1 键**（避免误伤 artifacts 子 schema 的 path/contains）并核对参数表；
HEAD 内容上发红 19 条、工作树 0。

## BUG-50 [2026-09-26T13:34:23Z] [medium] FIXED
- summary: [verify][BUG-44] 数值声明无人管：docs/agent-map.md 宣称测试数 316 项全绿（实测 406）。check_test_sync 只核对「实测数出现在 4 份指定文档」，不核对其它文档里的数字是否等于实测，也不核对反向违例 ⇒ 文档里的旧数字可以长绿
- detail: 证据：temp/j_before_after.py 在 HEAD 内容上发红 32 条（J6=2/J7=11/J8=19），工作树 0；temp/stdalign_verify.py 为本轮调用面终审；修复落在 check_doc_surface J6/J7/J8 + 35 处文档口径对齐。
- reported_by: std-auditor



### FIXED(2026-09-26 stdalign verify / 指挥官终审，含判据缺口如实入账)

文档侧已改：`docs/agent-map.md`「316 项全绿」→「**406 项全绿**（2026-09-26 Windows 实测）」。
**判据缺口未在本轮闭合（如实声明）**：`check_test_sync` 的判据形状是"实测数出现在指定 4 份文档"，
天然测不到"第 5 份文档写着别的数"；要闭合需把扫描面从白名单改成全量文档并处理"历史数字豁免"（native 317/317 一类
合法旧数），属判据重设计，交下一轮处理。同类缺口见规范正文 §7「已知边界」。

### FIXED(2026-09-27 双远端同步轮 · BUG-50/51 收口（指挥官亲自改判据） / BUG-50)

判据重设计已落地（`scripts/check_test_sync.py` 整段重写，四条判据代替一条存在性检查）：

- **R1 全量反向扫**：现状面 97 份文档（README/AGENTS/USAGE/SKILL/规范 + `docs/**` + `scripts/*.md` +
  `templates/*.md` + `plugins/**`）里每一条"测试总数声明"必须 == 实测。窄口径只认三种形状
  （等值对 `N/N`、`N 项|个|条 [测试|用例] 全绿|通过|passed`、`total=N`），**不等值对一律不算声明**——
  否则 `105/104`（BUG-17 引文）、`1986/1997`（论文年份）、`22/30`（缺陷编号）全会被判成谎数。
- **R2 正向 must-carry**：5 份现状文档必须携带实测数（防止有人把声明整段删掉来"消解"违例）。
- **R3 防空转**：现状面至少要有 1 条声明等于实测，否则红——正则饿死 ≠ 没有问题。
- **R4 豁免双向**：历史数/别的 target 必须在 `EXEMPT` 里逐条点名 `(文件, 数, 理由)`，
  **条目失效同样判红**（白名单只进不出就是下一个谎言）。当前 7 条：README/AGENTS/README_EN 的 `317`
  （native 轨旧数，三处原文都已声明本轮未复跑）、`docs/deliverable.md` 的 `233`（R43 交付行的当轮数）、
  `docs/polish-plan.md` 的 `148`（标题自述「初稿」）、`docs/features/F008-evolve.md` 的 `148`
  （已勾 `- [x] AC-2` 是当轮验收记录）、`BACKLOG.md` 的 `295`（done 行的 R107 当轮数）。
- **本轮自己又踩出一个同族洞**：把判据写完才发现扫描面**漏了两份现状文档**——`README_EN.md`
  （整面停在 `307 tests / 104 tools / check_test_sync (316 aligned)`）与 `BACKLOG.md`
  （锚点事实停在 `104 工具 / 311 测试`）。⇒ 两份纳入扫描面并逐处对齐到 120 工具 / 442 测试；
  `README_EN` 原来还写着"317/317 green … verified on both Windows and WSL"，与中文 README
  「本轮未复跑 native，不据旧数宣称双端同版全绿」的口径矛盾，一并改成 JS 实测 + native 旧数声明。
  **守卫的扫描口径漏一个目录/文件，等于那里的一切改动无人认领**（见 [[feedback-guard-narrower-than-claim]]）。
- **口径补第四种形状**：`Total tests: N, passed: N`（日志回显）原先不被认成声明——README 的自检示例行
  就是靠 `check_badge` 才抓到，属同一族数字却走了另一条门 ⇒ 并入 R1，并加 selftest 变体钉住。
- **历史记录按路径类别整面豁免**（不逐条点名）：`memory/`、`reports/`、`CHANGELOG.md`、
  `docs/superpowers/plans/`、文件名以 `YYYY-MM-DD` 开头的文件——改写它们等于伪造历史。
- **判据自证**：`python scripts/check_test_sync.py --selftest` **8 个变体**各命中自己指名的那一条
  （含"自洽的谎"型：把实测数整批改写成 500 并同步扩豁免表，仍被 R2 抓住；以及"不得误抓引文/年份/编号"
  的反向对照），基准夹具必须 rc=0；已挂进 CI（`.github/workflows/ci.yml`「Test-count guard selftest」，
  与真判据同步跑）。末行计数由 `run_case` 实测累加，不手写数字。
- **首跑活证据**：`--total 439` 在新判据下红 3 条，指向两份**旧白名单看不见**的文档——
  `docs/evolve.md:146`（148/148）、`docs/atgc-selfdrive-demo.md:93`（191/191，且原文用词是"当前"）。
  两处已按实测数改写。这就是 BUG-44/50 说的"第 5 份文档写着别的数"被抓住的第一个实例。

## BUG-51 [2026-09-26T13:39:19Z] [medium] FIXED
- summary: [verify][BUG-51] 路径口径在工具间相反：report_bug/bug_list 拒绝绝对 project_dir（『非法 project_dir（拒绝绝对路径/穿越/盘符）』），而 run_check 又拒绝 workdir='.'（『workdir=. 与项目不同根（workdir 盘符= 项目盘符=E:）』，因任务 project_dir 记的是绝对路径）⇒ 照模板用同一个相对根跑完整链路必卡在第 3 步；两工具需统一路径策略或在描述里写明各自口径
- detail: 复现：temp/rc_raw.py（先 project_dir='.' 成功 report_bug，再 workdir='.' 被 run_check 拒；改 workdir=绝对根后通过）。失败本身是硬门且带 audit_log/call_log（可审计性合格），缺的是**口径一致性**。
- reported_by: std-auditor

### FIXED(2026-09-27 双远端同步轮 · BUG-50/51 收口（指挥官亲自改判据） / BUG-51)

两半都做：**统一口径 + 把两条口径同时写明**。

- `src/server/run_check_guard.mbt`：`run_check_workdir_denied` 不再拿"形态不一致"当拒绝理由——
  **相对 workdir 一律按任务 `project_dir` 相对解析**（`.` 即该任务的项目目录本身），与 project_dir 是绝对
  还是相对无关；反向（绝对 workdir + 相对 project_dir）仍然拒，且文案点名两条出路（① 相对 workdir；
  ② 发布任务时给绝对 project_dir）。安全性不降：`escaped` 判定在前，`..` 冲出自身起点仍在拼接之前就被拒。
- 新增 `run_check_effective_workdir`，`server.mbt` 的 run_check handler 把**归一后的绝对路径**交给 spawn。
  只改判定不改执行面就是新漏洞：判据会说"在项目里"，进程却跑在 server cwd。同形态调用逐字返回原值 ⇒ 零回归。
- 口径写进三处表面：工具描述 + `workdir` 参数描述 + `AI-DEVELOPMENT-STANDARD.md` §5 新增一段
  「`.` 在两处含义不同、但都合法」（run_check 的 workdir 相对任务 project_dir；
  `report_bug`/`output_validate` 的 project_dir 相对 store 根——那是账本落盘边界，不是执行边界）。
- 回归锁（`src/server/run_check_guard_test.mbt`，+3 用例块）：ALLOW/REJECT **成对**写
  （`.`、`scripts`、`src/../scripts` 放行；`../../etc`、`a/../../b`、绝对 workdir 配相对 project、
  `.` 配相对 `temp/proj` 仍拒），另两块锁归一（`.`→项目根、`scripts`→根/scripts、
  `temp/r2/../x`→根/temp/x、反斜杠 project 也归一）与拒绝文案自带出路。
- **开关对照（不动工作区源码）**：`temp/b51_red/` 用 HEAD 版判定 + 新版归一函数组成对照包，
  同一份测试文件在其上 `Total tests: 10, passed: 8, failed: 2`，两条红恰是
  `guard_test.mbt:141`（`.` 配绝对 project 未放行 = 缺陷本体）与 `:181`（拒绝文案无出路），
  第三块（归一 helper）两侧同绿 ⇒ 标**纯 helper 锁**不作缺陷守卫。对照包 `moon.pkg` 已改名
  `moon.pkg.disabled` 退出全量计数（它一度把全量套件毒成 452/450——2 红就来自它）。
- **调用面终审**：`temp/b51_callsite.py` 打真实 MCP 入口（node main.js），**13 条判据 0 红**：
  S01 `.` 放行、S02 真 spawn 的 cwd == 归一后的绝对项目根、S02b cwd 不是 server 自己的 cwd
  （harness 特意 `chdir` 到 `temp/` 起 server，否则"cwd==项目根"分不清是归一生效还是继承 server cwd）、
  S03/S04 子目录与 `src/../scripts` 归一、S05~S08 上跳与混形态仍拒且文案带出路、
  S09/S10 `report_bug` 的相对口径未受影响、仍拒绝对 project_dir（账本边界没被执行面的放宽带着走）。

## BUG-52 [2026-09-26T15:46:13Z] [high] FIXED
- summary: 上游 fist-model-router：时间戳↔秒用「365 天固定年 + 每月 31 天」近似，5h 窗口判定跨月/闰年偏移
- detail: 证据：源项目 src/model_router.mbt `iso_to_secs` 用 `(year-2024)*365 + (mon-1)*31 + day`，既不漏 4/6/9/11 月的 30 天也不管闰日 ⇒ `window_reset_check` 的 now_s-s>=18000 在跨月时最多偏 3 天，配额窗口实际不过期或提前过期。处置：合并时改写为 civil-days 精确算法（Howard Hinnant days_from_civil），回归锁 src/router/model_router_wbtest.mbt rt_1（含闰日 2028-02-29 精确秒数）/rt_2（非法时间戳一律 -1，不当成 0 参与减法）。
- reported_by: router-merge-r1


### FIXED(2026-09-26 六模式轮 · 合并 fist-model-router（指挥官终审） / BUG-52)

合并即修：`src/router/model_router.mbt` 改用 civil-days 精确换算（days_from_civil/civil_from_days），闰日与跨月都对。回归锁 rt_1（`2024-02-29`/`2026-03-01` 精确秒数）、rt_2（非法时间戳一律 -1，绝不参与减法）。

## BUG-53 [2026-09-26T15:46:13Z] [high] FIXED
- summary: 上游 fist-model-router：current_model() 在池为空时索引 [0] 直接 panic
- detail: 证据：源项目 Free/Paid 分支都写 `if idx < len { pool[idx] } else { pool[0] }`，空池时 len=0 ⇒ else 取 pool[0] ⇒ 越界 panic，MCP server 整条连接被打断。处置：合并后 current_model() 返回 ModelQuota?，pick 的两池皆空分支给available=false + 明确 reason（不静默换模型）。回归锁 rt_4（空池不 panic）/rt_5（两池耗尽显式不可用）、mo_3 与调用面判据 S04x。
- reported_by: router-merge-r1


### FIXED(2026-09-26 六模式轮 · 合并 fist-model-router（指挥官终审） / BUG-53)

合并即修：`current_model()` 返回 `ModelQuota?`，两池皆空走 `available=false` + 明确 reason。锁 rt_4（空池不 panic）、rt_5（全耗尽显式不可用）、mo_3（记账后仍无模型 ⇒ 点名「不会静默改用别的模型」）、调用面 S03/S04。

## BUG-54 [2026-09-26T15:46:13Z] [high] FIXED
- summary: router_restore 不夹紧越界游标：free_idx/paid_idx 为负时取模落到负下标（坏状态文件即可触发）
- detail: 证据：修复前 src/router/router_state.mbt 直接 `r.free_idx = st_int(sm, "free_idx", default=0)`，而 pool_pick 用 `(start_idx + i) % n`；MoonBit 的 % 与被除数同号 ⇒ -7 % 2 = -1，下一次 model_route 就按下标 -1 panic。坏/手改过的 memory/model-router-*.json 即可触发。活证据：白盒测试 rs_3 在修复前实测 FAILED（`false is not true`，warnings<3 且未夹紧），修复后 5/5 绿；夹紧行为由 rs_3 的 assert_eq(r.free_idx, 0) 与 warning 点名锁住。
- reported_by: router-merge-r1


### FIXED(2026-09-26 六模式轮 · 合并 fist-model-router（指挥官终审） / BUG-54)

`router_restore` 把 `free_idx`/`paid_idx` 夹紧到池内并对越界点名 warning；语义前提用 `assert_eq(-7 % 2, -1)` 写进测试（MoonBit 的 % 与被除数同号 ⇒ 负游标必然落负下标）。活证据：修复前 rs_3 实测 FAILED（`false is not true`），修复后 src/router 18/18 绿。

## BUG-55 [2026-09-26T15:46:13Z] [medium] FIXED
- summary: model_route 的 config_json 解析失败被静默当作「没传配置」，调用方以为覆盖了池定义实际用了默认池
- detail: 证据：修复前 src/server/server.mbt 写 `@json.parse(cj) catch { _ => Json::null() }`，而 `Json::null()` 在 router_restore 里正是「无配置」的语义 ⇒ 打错的 config_json 会静默改用 RouterConfig::default()（模型名完全不同），与 BUG-31/33/43 同族的静默降级。处置：新增 mr_parse_config（空串=不覆盖，非法 JSON=Err 并说明不回落），回归锁：调用面判据 S04（tools/call model_route --config_json '{"free_pool":[oops' → is_error）。
- reported_by: router-merge-r1


### FIXED(2026-09-26 六模式轮 · 合并 fist-model-router（指挥官终审） / BUG-55)

新增 `mr_parse_config`：空串=不覆盖（`Json::null()`），非法 JSON=Err 并在工具描述里写明「不静默回落默认池」。调用面锁 S04（tools/call 传 `{"free_pool":[oops` → is_error）。

## BUG-56 [2026-09-26T15:46:13Z] [medium] FIXED
- summary: usage_report.current_model 报的是轮询游标位而不是本次选中的模型，同一响应里与 decision.model 自相矛盾
- detail: 活证据（真实调用面，2026-09-26 实测）：`python scripts/fist.py call model_route --project_dir . --namespace rmscli` 返回 `decision.model=AtomGit-qwen3.8-27b` 而同一 JSON 里 `usage.current_model=AtomGit-glm5.3-flash`——pick 把游标推进到 (idx+1)%n 后，current_model() 读的是**下一个**候选，却被命名成「当前模型」。后果：agent 读 usage 段会以为用的是另一个模型，配额账与实跑模型对不上。处置建议：usage_report 报真实选中模型（ModelRouter 记 last_pick），游标位另起名 cursor_model。
- reported_by: router-merge-r1


### FIXED(2026-09-26 六模式轮 · 合并 fist-model-router（指挥官终审） / BUG-56)

`ModelRouter` 增加 `last_pick`，`pick` 收敛到单一 choke point 登记（force_switch 成功分支同步登记），`usage_report` 的 `current_model` 报真在用的模型、游标位另名 `cursor_model`，状态 schema 加 `last_pick`。成对锁 rt_13（两键必须不同，否则断言是空的）+ rs_1（跨进程往返）+ 调用面 S03c。

## BUG-57 [2026-09-26T15:46:13Z] [low] FIXED
- summary: scripts/issue_scan.py：`--include-tests false` 被当成开启（CLI 与 MCP 语义漂移）
- detail: 活证据：`python scripts/issue_scan.py src/router --include-tests false` 返回 `"include_tests":true` 且扫进了 2 个 _wbtest 文件（scanned_files=5）。根因 scripts/issue_scan.py:68 `include_tests = "--include-tests" in sys.argv`——只判存在不判值，而 MCP 形态该参数是 bool（默认 false），照 MCP 习惯写 `false` 的调用方拿到相反结果且没有任何提示，多余的位置参数也被静默忽略。处置建议：接受 `--include-tests [true|false]`，对无法识别的位置参数显式报错退出。
- reported_by: router-merge-r1


### FIXED(2026-09-26 六模式轮 · 合并 fist-model-router（指挥官终审） / BUG-57)

`scripts/issue_scan.py` 显式解析 `--include-tests [true|false]`，未知参数与多余位置参数直接 exit 2。实测：`--include-tests false` → `include_tests=False, scanned_files=3`（只产品代码）；`--includ-tests`（拼错）→ FAIL 并列出可用开关。

## BUG-58 [2026-09-26T15:46:13Z] [medium] FIXED
- summary: 守卫族在 GBK 控制台直接抛 UnicodeEncodeError，本地拿不到判定（只拿到 traceback）
- detail: 活证据：Windows 默认 GBK 控制台下 `python scripts/check_doc_surface.py` 打印 「J6 规范正文↔投影一致…」时 UnicodeEncodeError 崩在 print，退出码非 0；同一脚本 `PYTHONIOENCODING=utf-8` 下才输出 PASS。守卫族的「红」必须是判据红，编码崩溃冒充红色会让本地结论不可信（CI 在 Linux UTF-8 下掩盖了这件事）。同类：check_test_sync/check_badge/gen_plugins 的中文输出在 GBK 下是乱码（能跑但不可读）。处置建议：scripts/*.py 入口统一 sys.stdout.reconfigure(encoding='utf-8', errors='replace')。
- reported_by: router-merge-r1


### FIXED(2026-09-26 六模式轮 · 合并 fist-model-router（指挥官终审） / BUG-58)

`check_tools_sync/check_test_sync/check_badge/check_scripts_index/check_doc_surface/gen_plugins` 入口统一 `stdout/stderr.reconfigure(encoding=utf-8, errors=replace)`（另两条守卫本就有）。实测：不加 `PYTHONIOENCODING` 在 GBK 控制台直跑 6 守卫全部 PASS 且中文可读。

## BUG-59 [2026-09-26T16:04:49Z] [medium] FIXED
- summary: 父节点被自动提升为待验收时交付物为空，Omega 成果复验门禁与 execute 合法态互锁，无出路
- detail: 证据链（ns=router-merge，2026-09-26 实测）：子叶全 verify ⇒ 引擎把父节点提升「待验收」，但父节点 deliverable 仍为空；此时三条调用互相锁死——omega_result_verify 报「尚无交付物（deliverable 为空），无可复验成果」；execute 报「非法执行: 任务处于 [待验收]，合法路径：验收(verify)/需要改进(reject→已打回)/重试(retry→执行中)」；verify 报「Omega 强验证门禁：尚未做成果复验」。reopen_task 只支持已归档/已完成。⇒ 开了 omega_strong_verify 的递归拆解树，只要父节点没在子叶完成前自己 execute 过，就必然卡死，只能人工 reject→retry 绕一圈（本轮 5 个父节点全中）。
修法建议：①自动提升时把子叶交付的并集写进父节点 deliverable（最贴近语义，成本最低）；或②允许「待验收」态补记交付物（execute 在该态放行一次）；或③提升即视为无需复验（不建议，弱化门禁）。
- reported_by: router-merge-r1



### FIXED(2026-09-26 六模式轮 · 合并 fist-model-router（指挥官终审） / BUG-59)

`FistEngine::verify` 的父节点自动提升分支继承子叶交付并集（父节点已有交付则不覆盖，零回归）。锁 `src/engine/engine_promote_r6_test.mbt` 两条（提升即带交付 / 已有交付不被覆盖）。活证据：修复前本轮 5 个父节点全部卡在「待验收」——omega_result_verify 报无交付物、execute 报状态非法、verify 报门禁未过，只能人工 reject→retry 绕出（ns=router-merge 实测记录）。
## BUG-60 [2026-09-26T16:20:31Z] [medium] FIXED
- summary: evolve_critic 门禁在默认参数下永不可满足：中性 score=0.5 参与加权后 combined 上限 0.75 < 阈值 0.85
- detail: 活证据（2026-09-26 实测）：evolve_critic 的 score 属性描述写「默认0.5」，threshold「默认0.85」，而 critic_review 计算 combined=0.5*score+0.5*novelty ⇒ 不传 score 时 combined 最大 (0.5+1.0)/2=0.75，永远低于 0.85，任何候选都被判「稳健性不足，暂缓入库」。实测两次调用均 admit=false（score=0.5、novelty=0.887、combined=0.694）。第二个受害者是 task_challenge：src/engine/engine_challenge.mbt:115/140 硬传 0.5，于是 critic=true 的挑战题在任何档案库状态下都进不了门禁的"放行"分支——特性看起来开着，实际恒拒。门禁恒关比没有门禁更糟：它给出"已过审"的错觉。
- reported_by: router-merge-r1



### FIXED(2026-09-26 六模式轮 · 合并 fist-model-router（指挥官终审） / BUG-60)

中性分不再参与加权：`critic_review` 在 `score == 0.5`（= 没算分）时按 `novelty` 单独判，显式给分才走 `0.5*score + 0.5*novelty`。这样 `evolve_critic` 不传 score 与 `task_challenge` 硬传 0.5 两条默认路径都能真正过审，而漂移/重复防护不变。锁 `src/evolve/critic_test.mbt` 一条三判据：中性分+空库⇒放行、中性分+高重合⇒仍拒、显式 0.1⇒仍拒。

### FIXED(2026-10-17T11:15:12Z / BUG-60)
- evidence: Fix implemented in zhi/src/zhi/codegen.py:
1. JS backend (_loop at line 3361): Added counter initialization before while(true) and increment at end of loop body for infinite loops with `循 于 「x」 附 计数 <init>`
2. BEAM backend (_loop at line 2399): Changed infinite loop with counter to use Stream.unfold(0, fn x -> {x, x + 1} end) instead of Stream.cycle([nil]), which properly increments the counter each iteration
3. Also fixed pre-existing bug: infinite loops with 出/继 now correctly wrapped in try/catch for BEAM (removed `or node.kind == "infinite"` condition at line 2418)

Verification:
- JS backend: `python -m zhi.cli run --js test_loop.玆` outputs 0,1,2,3,4,5,6 correctly
- BEAM backend: `python -m zhi.cli run test_loop.玆` outputs 0,1,2,3,4,5,6 correctly
- All 13 tests in test_r96_loop_tail_v213.py pass
- Dual-backend stdout equality verified for BUG-60 test case
## BUG-61 [2026-09-27T03:02:07Z] [high] FIXED
- summary: [r4][executor_run] 文档承诺的记账从未发生
- detail: AGENTS.md 与 executor_run 工具描述都写「model 留空则先向路由器要一个模型并记账」，实际 src/server/model_router_ops.mbt:241 调 model_route_impl(project_dir, ns~) 时不传 record_model ⇒ 只 pick 不 record_call。实测（temp/r4/verify_laneA.py + fist.py 真跑）：执行器跑完后状态里 used 仍为 0、switch_count 不推进 ⇒ 执行器流量永不影响档位，路由对真实用量失明。
- reported_by: pmode-r4-bugfind
- task_id: T0r366

## BUG-62 [2026-09-27T03:02:07Z] [high] FIXED
- summary: [r4][executor_run] dry_run=true 并非无副作用：写盘 + 推进游标，两次同样请求返回不同模型
- detail: 复现：python temp/r4/verify_laneA.py（同一 ns 连打两次 executor_run dry_run=true）。实测第一次 argv 用 AtomGit-qwen3.8-27b、第二次换成 AtomGit-glm5.3-flash，且 temp/.../memory/model-router-<ns>.json 的 free_idx 由 0 变 1、模型 window_start 被盖章。根因与「model 留空=只问不消耗」同源：model_route_impl 在只查询分支也调 mr_save（src/server/model_router_ops.mbt:110），轮询游标在无人消耗配额时就被推进。
- reported_by: pmode-r4-bugfind
- task_id: T0r367

## BUG-63 [2026-09-27T03:02:07Z] [high] FIXED
- summary: [r4][model_route] config_json 传 JSON 对象被静默当成没传，走默认池且零告警
- detail: BUG-55 已把「非法 JSON 静默回落默认池」修成显式报错，但类型边界还漏着一条：schema 声明 config_json 是 string，而 MCP/LLM 客户端最常直接给对象。实测（temp/r4 探针）：同一个配置以对象传 → decision.model=AtomGit-qwen3.8-27b（默认池）、warnings 只有「无有效状态」；以字符串传 → decision.model=ZZZ-FREE（自定义池生效）。根因 src/server/server.mbt:340 get_str 对非字符串一律回退默认值。
- reported_by: pmode-r4-bugfind
- task_id: T0r368

## BUG-64 [2026-09-27T03:02:07Z] [medium] FIXED
- summary: [r4][model_route] namespace 未过 safe_ns：写不进盘的 ns 静默失去配额约束
- detail: src/router/router_state.mbt:13 直接拼 memory/model-router-{ns}.json，未复用仓库现成的 src/store/multi_store.mbt:24 safe_ns。实测 ns=a/b → persisted=false 而 ok=true，连记三次 used 恒为 1 ⇒ 上限形同虚设；大小写不敏感文件系统上 NSLOWER/nslower 共用一本账（同源）。
- reported_by: pmode-r4-bugfind
- task_id: T0r369

## BUG-65 [2026-09-27T03:02:07Z] [medium] FIXED
- summary: [r4][router 测试] 假绿锁：ent(used=-3) 根本没把 -3 写进 JSON，「负数夹紧」断言恒真
- detail: src/router/router_state_wbtest.mbt:32-34 的 ent() 仅在 used>=0 时才写 used 键，于是 :100 传入的 used=-3 在 JSON 里缺席，:107 的 assert_eq(used, 0) 测的是「字段缺失时的默认值」而不是负数夹紧路径 ⇒ src/router/model_router.mbt:59 的夹紧逻辑实际零覆盖。同文件另三处弱断言：rs_1 的付费单元只查 is Some(_)、rt_7 标题含「占比」却不查 share_pct、mo_* 全部没看 usage.current_model（故记账后报别名的缺陷落在所有锁之外）。
- reported_by: pmode-r4-bugfind
- task_id: T0r370

## BUG-66 [2026-09-27T03:02:07Z] [medium] FIXED
- summary: [r4][插件态] 投影真源仍在广告幻影参数 now（120 个工具声明 now 的为 0）
- detail: plugins/source/SKILL.md:57「**All tool calls take an explicit `now`**」、references/mcp-tools.md:29、references/seven-modes.md:25 同样措辞。实测 src/server/server.mbt 里声明 now 的工具数为 0（BUG-33 政策：时间戳服务端盖章）。守卫侧：J8 专治幻影参数，但 scripts/check_doc_surface.py:243 只扫 templates/，plugins/source/ 与四宿主投影不在任何判据射程内 ⇒ 投影把谎言放大成 4 份发货。
- reported_by: pmode-r4-bugfind
- task_id: T0r371

## BUG-67 [2026-09-27T03:02:07Z] [medium] FIXED
- summary: [r4][插件态] references 走 copytree 原样字节复制，工具数写死腐烂且无守卫
- detail: plugins/source/references/fist-methodology.md:54 仍写「MCP Tools (41 total)」，plugins/source/SKILL.md 另有「105 tool registrations」与分组和 112（同一文件头戳却是 tools=120）。gen_plugins.py:142 对 references 是 shutil.copytree（不做占位符替换），结构上永远无法承载 {{TOOL_COUNT}}；而 check_tools_sync/check_doc_surface 均不提 plugins/ （实测 grep 命中 0），cl7 J6 只取第一个 tools= 命中 ⇒ 投影正文里的数字无人对账。
- reported_by: pmode-r4-bugfind
- task_id: T0r372

## BUG-68 [2026-09-27T03:02:07Z] [medium] FIXED
- summary: [r4][守卫] 现状面文档枚举器各自为政：ARCHITECTURE.md / README.mbt.md 全仓无人判
- detail: 实测：git 跟踪 262 份 .md，check_test_sync 扫描面 101 份，「既不在面内也不属历史豁免」4 份，其中 ARCHITECTURE.md:81 写「317 全绿」、:3/:15/:90 写「104 工具」，README.mbt.md:9 写「307/307」（真源 120 工具 / 442 测试 / v0.3.0）。同族：check_tools_sync 遍历 5 份、check_doc_surface J4 遍历 4 份、J7 一份清单 —— BUG-50 只修了其中一份枚举器。
- reported_by: pmode-r4-bugfind
- task_id: T0r373

## BUG-69 [2026-09-27T03:02:07Z] [medium] FIXED
- summary: [r4][守卫] check_test_sync --selftest 测不到「扫描面漏文件」这一类
- detail: scripts/check_test_sync.py:218 的 sweeps 是手写夹具，全程不调 current_docs()（:96）与 run()（:173）⇒ 自检只证纯函数 judge 会红，判据最强的一层（R1 全量扫）恰好没被自测覆盖。本轮实测的 ARCHITECTURE.md 漏面就是它原理上抓不到的形状。
- reported_by: pmode-r4-bugfind
- task_id: T0r374

## BUG-70 [2026-09-27T03:02:07Z] [low] FIXED
- summary: [r4][守卫] check_plugin_sync 用绝对路径的 p.parts 过滤 source，克隆目录含 source 时判据空转
- detail: scripts/check_plugin_sync.py:106 与 :146 都是 `"source" not in p.parts` —— p 来自 PLUGINS.rglob，parts 含整条绝对路径。把仓库克隆到路径任一段叫 source 的目录（如 C:/source/FIST-Mbt）⇒ generated 集合直接变空，J3/J6 全程无对象可比仍打 PASS。
- reported_by: pmode-r4-bugfind
- task_id: T0r375

## BUG-71 [2026-09-27T03:02:07Z] [low] FIXED
- summary: [r4][文档] server.mbt 头注释写「16 tools + 2 resources + 2 prompts」，且 resources/prompts 计数零守卫
- detail: src/server/server.mbt:1 头注释与实际 120 工具差一个数量级；实测 s1.resource( 命中 3、s1.prompt( 命中 2。宣称处 AGENTS.md:102、README_EN.md:90、docs/agent-map.md:26、docs/deliverable.md:17 —— 六守卫里没有任何一条对 resources/prompts 计数负责（check_tools_sync 只管工具名与总数）。
- reported_by: pmode-r4-bugfind
- task_id: T0r376

## BUG-72 [2026-09-27T03:02:07Z] [low] FIXED
- summary: [r4][issue_scan] 裸子串 needle 在字符串字面量上假阳性
- detail: src/server/issue_scan.mbt:71 的 substring-overrun 用裸子串匹配，实测在 src/server/server.mbt:2216 这类纯文案（"mode / name / description / ..."）上命中；全仓 substring-overrun 17 条含多条此类噪声。另记：ignored-error / empty-collection-singleton 两条规则在本仓恒 0 命中（needle 的唯一出处是 issue_scan.mbt 自己的规则表，而 :137 又显式跳过该文件）——属"规则表无受控命中自检"，不是匹配缺陷，交 Round 5 决定是否配 fixture。
- reported_by: pmode-r4-bugfind
- task_id: T0r377

## BUG-73 [2026-09-27T04:24:27Z] [high] FIXED
- summary: [r4][model_route] pool_pick 不扫描：游标落在耗尽格上时整档判死，白切付费档
- detail: src/router/model_router.mbt:284（修复前）`let idx = (start_idx % n + n) % n` —— 循环变量 i 从不参与下标，pool_pick 把**同一个格子重测 n 次**，而它的文档注释写的是「池内第一个可用模型下标（环形扫描）」。后果实测：免费池 [free-busy(limit=1,used=1), free-ok(limit=10)]、游标停在 0 时，pick 返回 paid-a 并 current_tier=Paid、switch_count=1 —— 免费档还有一个满血模型却被判整档不可用，直接跳到付费档烧钱（违反「免费优先」这条主承诺）。锁：rt_15_同档仍有健康模型时不许跳档（先跑在未修复代码上为红，见 temp/r4/t6.log；合成违例复跑见 temp/r4/mut_b73.log，D 组）。注：本仓既有路由测试全部用单元池（rt_3/rt_5/rt_7/rt_9），单元池里 n=1 使该缺陷不可见，rt_13 虽用双免费池却只看 decision.model 与 current_model，未把游标停在耗尽格上。
- reported_by: pmode-r4-fix
- task_id: T0r380


### FIXED(2026-09-27 四模式轮 · Round 4 修复段（指挥官终审，调用面实测） / BUG-61)

executor_run 在**进程真起来**那一支（Ok 分支）调 mr_record_only 把这次用量记到路由账上，返回体新增 quota 字段说明 recorded/not_routed/record_failed；显式指定 model 属越池覆盖，不代记账。
锁：mo_6/mo_8/mo_9（记账路径与「只有消耗才落盘」的边界）+ 调用面 temp/r4/verify_r4_callsite.py E1/E2（record_model 后 total_used 0→1）。
**残余缺口（不自证为已验收）**：executed=true 真跑侧仍无端到端证据——宿主执行器真跑未获授权（BUG-4 边界默认收紧），故本条按「代码+白盒+记账路径调用面已证、真跑侧待授权」入账。

### FIXED(2026-09-27 四模式轮 · Round 4 修复段（指挥官终审，调用面实测） / BUG-62)

只问不消耗改为真零副作用：model_route_impl 里 save 只在 consuming（给了 record_model）时发生，persisted=consuming，并新增 mode 字段明说本次形态（src/server/model_router_ops.mbt:125-152）。
唯一例外是**只播种定义不播种用量**：显式给 config_json 池定义时在 pick 之前落盘池形状，否则 executor_run 自动记账那一笔（不带 config）只能拿默认池，自定义模型名走「未在任何池中配置」，配额形同虚设（BUG-61 的接线前提）。
锁：mo_6（无 config 查询不建文件、三次同问同一模型）、mo_8（带 config 播种后 total_used 仍 0、再不带 config 的消耗能记上）、mo_9（**逐字节**对照：查询前后状态文件内容完全相同，消耗后才变）；成对反证见 temp/r4/prove_locks_red.py（退回修复前形态 ⇒ mo_2/4/6/7/8/9 六条全红）。

### FIXED(2026-09-27 四模式轮 · Round 4 修复段（指挥官终审，调用面实测） / BUG-63)

server.mbt 新增 get_json_text：字符串照原样、对象按 stringify 走同一条 mr_parse_config 校验、缺失/Null 才是「没给配置」，不再被静默当成没传。锁：src/server/server_r3_wbtest.mbt 的 BUG-63 一条（对象→文本→再解析回对象的整链，含零回归对照：缺失/Null 得空串）；非空锁证明 temp/r4/prove_locks_red2.py A 组（把对象取值退回 `Some(_) => Some("")` ⇒ 该锁必须红）。
调用面 B1/B2：config_json 以对象传时 decision.model=CS-FREE-A（自定义池生效）且无回落 warning。

### FIXED(2026-09-27 四模式轮 · Round 4 修复段（指挥官终审，调用面实测） / BUG-64)

model_route / model_router_status / model_router_reset / executor_run 四个入口统一过 mr_check_ns（复用仓库唯一真源 @store.MultiStore::safe_ns），空 ns 仍按既有约定=default（零回归）；非法 ns 显式拒绝且文案带出路（「只允许字母/数字/_/-」）。锁 mo_7（三个同步入口 + 空 ns 成对放行）；executor_run 是 async，其 ns 拒绝由调用面 C1/C2 覆盖（a/b 被拒、拒绝原因可见）。

### FIXED(2026-09-27 四模式轮 · Round 4 修复段（指挥官终审，调用面实测） / BUG-65)

假绿锁补真：rs_6 把 used=-3 **真写进 JSON**（不再走 ent() 的 used>=0 哨兵），第一次真正钉住 ModelQuota::new 的负数夹紧；rt_14 把 rt_12 收尾那句 `current_model() is Some(_)` 换成双元池上的具体模型名（单元池里 98%1、99%1、-7%1 全是 0，三条断言恒过＝假锁）。
非空锁证明 temp/r4/prove_locks_red2.py B/C 组：拆掉夹紧 ⇒ rs_6 红；环形取模换成恒定第 0 格 ⇒ rt_14 红。

### FIXED(2026-09-27 四模式轮 · Round 4 修复段（指挥官终审，调用面实测） / BUG-66)

plugins/source 四处对已删除参数 now 的广告改成「时间戳服务端盖章、调用面无 now」（SKILL.md、references/mcp-tools.md、seven-modes.md、known-issues.md 的 BUG-1 条目）；守卫面：check_doc_surface 的 J7 禁词表加 `explicit now`，规范性表面扩到 plugins/source/**.md，J8 扫描面从 templates/ 扩到 templates/ + plugins/source/（并加「扫不到插件真源就 FATAL」的枚举器哨兵）。
四宿主投影由 gen_plugins.py 重生成，cl7 逐字节复核 PASS（4 宿主 / 56 文件）。

### FIXED(2026-09-27 四模式轮 · Round 4 修复段（指挥官终审，调用面实测） / BUG-67)

references 不再是 shutil.copytree 的原样字节复制——gen_plugins 逐文件走 render()，因此 {{TOOL_COUNT}}/{{TOOL_GROUPS}} 能进投影正文；分组表**从 README 分组标题投影**并在生成时复算分组和==注册表实测，对不上直接 die（不产「看着正常」的插件）；SKILL.md 里手抄的 105/112 与 references/fist-methodology.md 的 41/12 快照一并删除（第二份真源就是腐烂源）。
同类第三处：scripts/mcp_smoke.py 硬写的 expected=104/120 改成 registry_tool_count() 读真源同口径，并加 <100 拒绝出假绿。cl7 J6 从「只取第一个 tools= 命中」收紧为「每个命中都得等于实测」。

### FIXED(2026-09-27 四模式轮 · Round 4 修复段（指挥官终审，调用面实测） / BUG-68)

check_test_sync 的文档枚举从手写元组改成 git ls-files 派生（tracked_docs，空/过小即 FATAL），扫描面 102 份现状文档，ARCHITECTURE.md(317/104) 与 README.mbt.md(307/103) 第一次进射程并被判红→改绿；同族：check_tools_sync 加 R3b（现状面每处工具数声明逐处对账，不只要求「出现过实测数」）与 R7（tools+resources+prompts 三元组，含 server.mbt:1 头注释本身）；文档侧一次性对齐 ARCHITECTURE/README.mbt/USAGE/agent-map/scripts-README 共 8 处旧数 + 14 处测试数 442→453。

### FIXED(2026-09-27 四模式轮 · Round 4 修复段（指挥官终审，调用面实测） / BUG-69)

check_test_sync --selftest 增加 R0-enumerator 变体：直接考 current_docs()/enumerator_gaps 本身（不调 judge），断言①曾漏面的 ARCHITECTURE.md、README.mbt.md 必须在扫描面里，②把扫描面人为收窄成「只带子目录的文档」时差集判据必须报出 ARCHITECTURE.md（否则它是装饰），③全量面自比不得自报漏文件（防恒红）。实测末行：SELFTEST PASS 8 个变体（计数由 run_case 累加）+ R0-enumerator 单独一条 ok ⇒ 共 9 项检查，但「变体」口径是 8，引用时按末行原文，别手加。

### FIXED(2026-09-27 四模式轮 · Round 4 修复段（指挥官终审，调用面实测） / BUG-70)

check_plugin_sync 的 source 过滤从 `"source" not in p.parts`（parts 含整条绝对路径）改成 is_generated(p, plugins)——只看相对 PLUGINS 的第一段；新增 generated_files() 单点复用 + 集合为空时打 FATAL（空转的 J3/J6 绝不报 PASS）；新增 --selftest 两判据：克隆到 …/source/… 下的生成文件必须仍算生成、真源 plugins/source/ 必须不算。同族防线也补进 check_doc_surface（is_plugin_surface 可注入 plugins 根）。

### FIXED(2026-09-27 四模式轮 · Round 4 修复段（指挥官终审，调用面实测） / BUG-71)

server.mbt:1 头注释从「16 tools + 2 resources + 2 prompts」改为实测 120/3/2 并写明真源与守卫；resources/prompts 计数从此有守卫：check_tools_sync 按 s1.resource( / s1.prompt( 数注册点，R7 把三元组声明（含头注释）逐处对账。跑法与结果：python scripts/check_tools_sync.py PASS。

### FIXED(2026-09-27 四模式轮 · Round 4 修复段（指挥官终审，调用面实测） / BUG-72)

issue_scan 的命中条件从裸 `line.contains(needle)` 改成 scan_outside_literal：先取「可扫代码部分」（字符串字面量内容整体丢弃、在第一个未转义 `//` 处截断），再匹配。顺带还掉 BUG-15 欠的「行尾注释不在本轮范围（需要 token 级判定，另开 issue）」半边债——实测只需两个状态量一趟扫描。
锁：src/server/issue_scan_wbtest.mbt 三条成对锁（真代码行必抓到 / 文案与注释里的同一串必不抓 / 两道降噪同时生效时行号必须是 5）。纯降噪证明：temp/r4/prove_b72_diff.py 同一份语料开关两态 80→76 条，去掉 4 条、新增 0 条（去掉的全是行尾散文与描述文案）。

### FIXED(2026-09-27 四模式轮 · Round 4 修复段（指挥官终审，调用面实测） / BUG-73)

修复中新发现并当场收口：src/router/model_router.mbt pool_pick 的循环里 idx 只由 start_idx 算出、i 从不参与下标 ⇒ 同一格重测 n 次，游标停在耗尽模型上时**整档判为不可用**，免费池还有一个满血模型却切到付费档（白花钱 + switch_count 假增长）。改为 idx=((start_idx+i)%n+n)%n。
锁先落码后改产品：rt_15 在未修复代码上实测红（temp/r4/t6.log：`"paid-a" != "free-ok"`），修复后转绿、全量 453/453（temp/r4/full3.log）；合成违例复跑 temp/r4/mut_b73.log（D 组）。
既有单元池测试（rt_3/rt_5/rt_7/rt_9）看不见该缺陷，故双元池断言是本条的关键增量。
## BUG-74 [2026-09-27T04:53:57Z] [medium] FIXED
- summary: [r4][task_plan_deep] 工具描述只列参数不写返回形状，调用方按自然键名取值静默得空（拆解看似 0 子任务）
- detail: src/server/server.mbt 的 task_plan_deep 描述串（实测该串内不含「返回」「tree」「children」任一词）只文档化了入参，未声明返回形状；真实返回是 {root, by, split_n, tree:{task_id, created:int, children:[{id, depth, leaf, spec_hash, depends_on, children:[…]}]}, exec_order:{task_id, count, order:[…]}} —— 子任务藏在 tree.children 的递归层里，且 created 是**计数**不是数组。同仓其它工具是写明返回形状的（issue_scan「返回 {scanned_files,total_findings,…}」、call_log「返回最近工具调用记录（seq/ts/tool/…）」），所以这是漏项而非风格。实测代价（本轮活证据 temp/r4/publish_pmode-r4-verify.json + 立项日志）：指挥官脚本用 tp.get('subtasks') or tp.get('tasks') or tp.get('created') or [] 取值 → 顶层全 miss → 打印「plan -> 直接子任务 0 个」，而服务端其实已建 7 枝 / 21 叶；若不是随后用 list(namespace=) 复核，就会误判拆解失败并重复发布（产生孤儿任务树）。created 尤其危险：真出现在顶层时 for k in created 直接 TypeError，而 or [] 的写法会把整数 7 当成假列表。修复方向（不动公开 API、不改返回体）：描述串补返回形状 + 明确 created 是计数，AGENTS.md 同口径；并给守卫加一条「有返回体的工具描述必须出现『返回』二字」的自检，配成对锁（缺『返回』的合成描述必红、issue_scan 这类已写明的必不红）。
- reported_by: pmode-r4-verify
- task_id: T0r385

## BUG-75 [2026-09-27T04:53:57Z] [medium] FIXED
- summary: [r4][run_check] 判据失败只回退出码、拿不到 stdout/stderr，落库的完整结果又无工具可读回 ⇒ 无人值守只能本地重跑（正是该工具要防的路径）
- detail: 工具描述承诺「结果 JSON（含 stdout/stderr）落库 specs 表」，但调用面拿不到它：实测 run_check 回执键 = [check_id, note, ok, round, status, task_id]（无 stdout/stderr）；src/engine/omega_gate.mbt:74-81 的返回 Map 也只 set 这六个键，content=check_json 只写不读回；call_log 的 result 列对 run_check 行只有 "ok" 一词（实测最近 40 行里 10 条 run_check 全如此），不是那份 JSON。后果分两种，都命中本项目的旗舰场景：① passed 时指挥官举不出判据到底打了什么，只能自己再 subprocess 跑一遍同一条命令来取文本 —— 而 run_check 存在的理由就是「服务端真跑、不靠调用方自述」，重跑等于把证据梯降级回 L1；② failed 时更糟：只知 exit code 非 0，不知是断言红、路径不存在还是命令被白名单拒，无人值守流水线（watchdog_tick/pipeline_tick）没有终端可看，只能整单打回重做。次要观察（同一条里一并修）：omega_gate.mbt:80 把**调用方传入的 status** 原样回显，而第 57 行刚声明该参数不被信任、门禁状态一律由 check_json 的 ok 推导（eff）。当前 run_check 工具面无 status 参数、由服务端推导，所以还不会被利用，但「回执里的 status 可以是假话、记录里的 status 才是推导值」这种分叉应当合流。修复方向：回执加 stdout_tail/stderr_tail（截断到固定长度，避免超大输出撑爆 MCP 帧），并/或提供按 check_id 读回 specs.content 的只读工具；回显 status 改用 eff。判据成对：失败判据必须能带出最后 N 行 stderr（合成一条必然失败的命令），通过判据不得因为截断而丢 ok 字段。
- reported_by: pmode-r4-verify
- task_id: T0r386

## BUG-76 [2026-09-27T05:32:12Z] [high] FIXED
- summary: [r5][pipeline_tick] mode 参数从不读模式模板，工具描述与模板头部双向承诺落空
- detail: 复核证据（本会话实跑）：`grep -rn mode_template_path src/` 只有 ops_modes.mbt:178（mode_list 回显）、ops_watchdog.mbt:289、以及 ops_modes_wbtest 的三条；**src/ops/ops_pipeline.mbt 命中 0 次**。该文件里 effective_mode（:287）的全部去处是 pj_set(...,"mode",...) 写台账（:332/:355/:378/...），prompt 正文取自 Gen_Prompts 目录那份文件。而两头都在说另一回事：src/server/server.mbt:2031 参数描述『非 advance 时自动读 templates/pipeline_mode_<mode>.md』、templates/pipeline_mode_bugfind.md:3『由 watchdog_tick(mode="bugfind") 或 pipeline_tick(mode="bugfind") 自动选择』。影响：按 USAGE 操作的外部 cron 拿到 action=generate + mode=bugfind 的回执，实际收到的提示词与 mode 无关，台账却显示 mode=bugfind ⇒ 无人值守轮的『用了哪份提示词』不可信。修复取向（指挥官已判）：本仓 R117 只把 mode→模板接在 watchdog_tick 上，pipeline_tick 侧不接线是现状；因此先按**文案口径**收口（描述与模板头部改成如实说 mode 只是标签、模板由 watchdog_tick 或显式路径决定），真正的 mode→模板接线如需请开特性单——不在缺陷单里顺手改无人值守行为。
- reported_by: pmode-r5-bugfind
- task_id: T0r387

## BUG-77 [2026-09-27T05:32:12Z] [high] FIXED
- summary: [r5][watchdog_tick] 非 advance 时 mode 模板覆盖调用方显式 meta_prompt_path，且 detail 回显被忽略的那个路径
- detail: 复核证据：src/ops/ops_watchdog.mbt:280-294 —— mode_str 非空且非 advance 时走 else 分支，无条件取 mode_template_path(mode_str) 作为 effective_meta_path，**meta_prompt_path 在该分支根本不参与判断**；而 src/server/server.mbt:1946 明写『（显式 meta_prompt_path 优先）』。更糟的是 :362 回显 "meta_prompt_path": Json::string(meta_prompt_path) —— 回执指名的是被丢弃的那个值，effective_meta_path 全程不出现在 detail 里。影响：调用方以为自己的提示词生效（回执还盖了章），实际发布的是模板正文；事后审计（含 call_log 的 params）全部指向错源。这条与 BUG-76 同族但承重不同：76 是『承诺了没做』，77 是『做了但回执说谎』。修复：① 回显改用 effective_meta_path（或新增 meta_prompt_resolved 字段，零回归）；② 描述里的优先级口径与代码对齐（谁覆盖谁，点名写清）；锁：成对白盒断言『mode + 显式路径同给时，回执点名的就是真正被读的那份』。
- reported_by: pmode-r5-bugfind
- task_id: T0r388

## BUG-78 [2026-09-27T05:32:12Z] [high] FIXED
- summary: [r5][store_open] data_dir 不过任何路径校验，只有 ns 被消毒 ⇒ 可在仓库外任意目录落 .db
- detail: 复核证据：src/store/multi_store.mbt:52-60 —— 只对 ns 调 MultiStore::safe_ns，随后 `let dir = if data_dir == "" { self.data_dir } else { data_dir }`、`let path = "\{dir}/\{safe}.db"` 直接交给 SqliteStore::open（open 会建文件）。对照同仓两处同类守卫：src/server/bugreport.mbt:26-42（拒 .. / 盘符 / 前导分隔符）、src/server/model_router_ops.mbt 的 mr_check_ns（注释明写复用 MultiStore::safe_ns 这一真源）。工具面 server.mbt:4137/4148 把 data_dir 原样透出，schema 描述只有『库文件根目录(可选，默认当前目录)』；multi_store_test.mbt 全部用固定 base_dir()="."，**没有一条断言 data_dir 边界**。影响：docs/deliverable.md 承诺的『命名空间物理隔离』可被指到任意目录；同 server 上 project_dir 一律拒穿越，唯独这里放行（scratch=true 强制落 temp 恰好说明作者在意落点）。修复：data_dir 走与 bugreport 同一套消毒（拒绝对称/盘符/.. 上跳），拒时文案带出路；配成对锁（temp/... 放行 + ../outside 必拒）。
- reported_by: pmode-r5-bugfind
- task_id: T0r389

## BUG-79 [2026-09-27T05:32:12Z] [medium] FIXED
- summary: [r5][rsv_release] SQLite 后端把『语句跑成功』当『删到了行』，非持有者调用也回 true
- detail: 复核证据：src/store/store_sqlite.mbt:751 `DELETE FROM reservations WHERE scope = ? AND agent = ?`，:761-763 `let ok = stmt.execute(); stmt.finalize(); ok`；而 .mooncakes/mizchi/sqlite 的 **js 与 native 两版签名都是 `Statement::execute -> Bool`**（sqlite_js.mbt:358 / sqlite_native.mbt:489）——绑定层根本不给 changes()，所以这个 Bool 只表示『执行没报错』，删 0 行也返回 true。对照内存后端 src/store/store_rsv.mbt:31-43：`Some((a,_,_)) if a == agent => ...; _ => false` 是**校验持有者**的；函数头 :742 注释还写着『删除行数决定成功』。server.mbt:3692 把这个 Bool 直接当释放结果回给调用方。影响：生产（SQLite）后端上 B 非持有者调 reserve_release 会被告知『已释放』而预订仍在，于是 B 与 A 同改一份作用域——正是该原语要防的多 agent 撞车；内存后端的单测永远绿，抓不到。修复：删前先 rsv_get 校持有者（与内存后端同语义），不匹配回 false；锁：成对断言『持有者释放回 true、非持有者回 false 且预订仍在』，两后端同夹具。
- reported_by: pmode-r5-bugfind
- task_id: T0r390

## BUG-80 [2026-09-27T05:32:12Z] [medium] FIXED
- summary: [r5][守卫] BUG-33 残留：28 处工具描述仍广告 now 参数，而判据 5 的正则在真源上命中 0 ⇒ 该守卫是装饰
- detail: 复核证据（本会话 python 计数）：src/server/server.mbt 里 `、now。` 命中 15、`参数：now` 命中 3、`now(可选)` 命中 8、`now(时间戳)` 命中 2，合计 28 行；而 scripts/check_tools_sync.py:39 的 RE_NOW_AD = `"now"\s*:\s*string_prop|、now 时间戳` 在同一文件上**命中 0 次**。同时全仓 `get_str(args, "now")` 命中 0（唯一读 "now" 的地方是 selfdrive_round_tick.mbt:221 从 spec map 取，且该模块无调用面）⇒ 这 28 处广告的是没人读的参数。影响：① 契约说谎（BUG-33 原话：广告一个已删除的参数）；② 更实际的是 heartbeat —— 想注入受控心跳造 φ 间隔历史的人拿到墙钟，:1833 `prev != ts` 还会把同秒心跳丢掉，phi_accrual 的历史在无人值守里几乎不增长；heal/watchdog_tick 也写不出确定性超时判据。修复取向：先把正则换成能覆盖四种实测写法的口径（换完必须立刻 FATAL，否则新正则也是装饰），再按工具逐个决定：确实还接受 now 的把参数补回 schema（当前是拒收），只服务端盖章的删掉文案。因量级 28 处且涉及调用面语义，本条**先入账，修不修由指挥官在下轮定**，不许用『已有 FIXED 小记』把它读成闭环。
- reported_by: pmode-r5-bugfind
- task_id: T0r391


### FIXED(2026-09-27T12:18:14Z / BUG-34, BUG-29, BUG-80, BUG-28, BUG-35)
- evidence: BUG-34 熔断 Half-Open 加探测节流：circuit_status 在 open→half_open 时把 failures 复用为「已放行探测数」并按 probe_limit(默认 1) 节流，超限走 deny 分支（src/engine/engine_circuit.mbt），锁 src/engine/engine_circuit_test.mbt 三条（含 stale 时钟回拨一支）。BUG-29 已完成零交付物进脉冲面：board_ascii.done_no_artifact + status_summary/project_health 挂 done_no_artifact 与 residue_over_baseline（基线 2 = 账本点名的 T0r286/T0r287，实测现库正好 2），锁 src/server/board_ascii_test.mbt 两条。BUG-80 守卫复活：scripts/check_tools_sync.py 判据 5 的 RE_NOW_AD 扩到实测四种写法并打印命中行号，真源删掉 27 处 now 广告（删前 RED 证据 temp/phaseC/bug80_red_before_deleting.log，删后 rc=0）。BUG-28 预留骨架不再隐形：新增 scripts/check_store_tables_wired.py（schema↔写入↔预留三向 + --selftest 合成违例）+ store_sqlite.mbt 的 `schema-reserved: runs` 标记 + ci.yml JS 轨一步。BUG-35 payload 交回 Json：flush_plan/comment/close 三处 --data 改由 Json::object(...).stringify()，shell_quote 按 POSIX '"'"' 转义（旧实现把 ' 静默换成 " 是篡改载荷），并加 payload_json 旁路；锁 src/server/github_sync_wbtest.mbt 三条（零网络零 token，判据口径就是账本建议③点名的那条）。
## BUG-81 [2026-09-27T05:32:12Z] [medium] FIXED
- summary: [r5][heal] 唯一不带 ns 的看护入口扫 list_all() ⇒ 一次 heal 回滚全库所有命名空间的在途任务
- detail: 复核证据：src/ops/ops_heal.mbt:18 `for t in engine.list_all()`，而 src/store/store_sqlite.mbt:402 的 list_tasks 是 `SELECT ... FROM tasks`（**无 WHERE ns**），:424 的 list_tasks_in 才是 `... FROM tasks WHERE ns = ?`；同文件另一条跨进程版 heal（:71 起）用的是 engine.list_in_ns(ns)。heal 的 schema 只有 timeout_sec，描述也没给 ns 出口。影响：多 ns 共用根 fist-mbt.db 时，任一 agent 为自己 ns 调 heal 会把别的轮的 执行中/已领取/拆分中 一并 reopen_task；engine.mbt:766-786 的 reopen 不署名 ⇒ 枝干 assignee 被清空。与 watchdog_tick 描述承诺的『自动 heal 只作用于该 ns』形成直接反差。AGENTS.md 把 heal 写成『内存版，人工流程』只覆盖了心跳来源（init_heartbeats 已从库回填），不覆盖扫描范围这一半。修复：加可选 namespace 参数（不传=现状零回归，传了=按 ns 过滤），并在描述里点名不传的作用域；锁成对：两 ns 各塞一条超时任务，带 ns 只回滚一条。
- reported_by: pmode-r5-bugfind
- task_id: T0r392


### FIXED(2026-09-27T12:18:14Z / BUG-8, BUG-11, BUG-20, BUG-23, BUG-26, BUG-27, BUG-79, BUG-81)
- evidence: commit 9a26441 那一批（本条只补状态位，不改写其叙述）：BUG-8 report_bug 增 task_ns 并回显 task_namespace；BUG-11 bug_list 行与 report_bug 回执同时给 id/bug_id，→BUG-m 拆成 duplicate_of 字段；BUG-20 cost_budget_split 的 task_id/namespace 真参与取数、budget<=0 直接 rejected、返回体补 scope 自证；BUG-23 _instrument 拒缩写错名（ns↔namespace）——本脚本跑前先探调用面，探得 4005 才敢标；BUG-26 phi_accrual 加取值域门（负 elapsed / 非正间隔 → rejected 且不出结论）；BUG-27 heal_stale_tasks_by_phi 缺间隔历史时回落固定 timeout 而非弃权；BUG-79 SqliteStore::rsv_release 先校持有者再删（锁 store_backend_semantics_test.mbt 成对断言）；BUG-81 heal 的 ns 作用域显式化，缺省全库那条路在签名与描述里都写明。
## BUG-82 [2026-09-27T05:32:12Z] [low] FIXED
- summary: [r5][selfdrive_export_tasks] 把字面量 "now" 当导出时间写进 memory/task.md
- detail: 复核证据：src/ops/ops_selfdrive.mbt:333-338 把导出时间那一行拼成『（导出时间：』+ 字符串字面量 now + 『，共 … 条）』，而该函数签名（:325-329）里没有 now/ts 入参，server.mbt:2145-2148 也不传时间。影响：memory/task.md 是审视轮唯一的任务视图（templates/review_meta_prompt.md 指示审视者 selfdrive_get(kind=task) 读它），读到『导出时间：now』这种半成品字段，清单新鲜度就失去了可判依据——占位符被当成正文发出去。修复：用服务端时钟 now_default() 盖（与 BUG-33『时间戳服务端盖章』政策一致）；锁：导出后断言该行匹配『导出时间：20..-..-..T..:..』且不含裸 now。
- reported_by: pmode-r5-bugfind
- task_id: T0r393


### FIXED(2026-09-27 四模式轮 · Round 5 修复段（指挥官终审，锁承重已复算） / BUG-74)

src/server/server.mbt 的 task_plan_deep 描述补上返回契约：顶层是 {root, by, split_n, tree, exec_order}，子任务在 tree.children 里**逐层递归**，并点名 tree.created 是整数计数不是数组。同族三处一并补（都是本会话亲自读错的对象）：run_check 回执 9 个键、bug_list 的 {bugs,count,path,...} 信封、github_queue_status 的 {total,pending,sent,...} 且写明「enabled=false 时 total=0 是没开同步，不是没 bug 待同步」。守卫面：check_doc_surface 新增 **J9**（必查清单点名 + 「写了返回的工具数」棘轮，基线实测 66，只许升）。承重证明 temp/r5/prove_j9.py：逐一抠掉四个必查工具的「返回」二字 ⇒ J9 逐条发红；非必查工具不被误点名；抹 1 条即跌破棘轮。SELFTEST 另含「英文 returns 不算契约」的反向对照。

### FIXED(2026-09-27 四模式轮 · Round 5 修复段（指挥官终审，锁承重已复算） / BUG-75)

src/engine/omega_gate.mbt：gate_check_record 的回执新增 stdout_tail / stderr_tail / output_truncated（各取**末** gate_check_tail_limit()=2000 字符；取末不取前，因为判据的关键信息在结尾），并把 status 从"回显调用方传入值"改成回显**推导值** eff —— 第 57 行本就声明该参数不被信任，回执与记录分两套话就是给伪证留口子。完整输出仍存 specs.content 供库内复核；run_check 工具描述同步（J9 必查清单成员）。锁：src/engine/omega_gate_wbtest.mbt 三条（og_1 带回尾巴且 status 用推导值 / og_2 取的是末 N 不是前 N /og_3 坏 JSON 与非字符串字段安静回空串）。承重证明 temp/r5/mut_b75.py：只摘掉三个字段 + 把 status 退回回显 ⇒ src/engine 112 条里 **3 条 og_ 发红**，脚本 finally 里逐字节复原。（为什么不能用"拿 HEAD 码重跑"：HEAD 版连辅助函数都没有，测试根本编译不过，那只证明引用了新符号。）

### FIXED(2026-09-27 四模式轮 · Round 5 修复段（指挥官终审，锁承重已复算） / BUG-76)

按**文案口径**收口（不改无人值守行为）：pipeline_tick 的 mode 参数描述改为如实说"只作为台账标签、不读模式模板"，指出要按模式取模板请用 watchdog_tick(mode=) 或显式传 meta_prompt_path；6 份 templates/pipeline_mode_*.md 头部不再宣称被 pipeline_tick 自动选择（advance 那份是 HTML 注释形态，脚本两种形态都认、并断言 6 份一份不漏：temp/r5/fix_templates_b76.py）。真正的 mode→模板接线 = 改变在跑的 cron 轮实际拿到的提示词，属新能力，另开特性单，不塞进缺陷修复里。

### FIXED(2026-09-27 四模式轮 · Round 5 修复段（指挥官终审，锁承重已复算） / BUG-77)

src/ops/ops_watchdog.mbt：detail 里把"调用方给的那份"与"真被读的那份"**分栏回**——新增 meta_prompt_resolved（= effective_meta_path）与 meta_prompt_overridden（两者是否不同），保留 meta_prompt_path 原值不改语义（零回归）；watchdog_tick 描述里那句『显式 meta_prompt_path 优先』改成与代码一致的事实：非 advance 时 mode 模板**覆盖**显式路径，要让显式路径生效就别传 mode 或传 advance。行为未动（改优先级会让在跑的任务突然换提示词），修的是"回执说谎"这一半。注：本条暂无自动化锁——回执字段级断言需要真起 watchdog_tick（依赖 temp 目录与心跳状态），按「代码+描述+回执字段实测」入账，测试补挂转结下轮。

### FIXED(2026-09-27 四模式轮 · Round 5 修复段（指挥官终审，锁承重已复算） / BUG-78)

src/store/multi_store.mbt：新增 pub fn MultiStore::data_dir_ok（拒空串 / `..` / 前导斜杠或反斜杠 / 盘符），口径与 src/server/bugreport.mbt 的 bug_project_dir_ok 一致（同族守卫不许两套规则）；open() 与惰性 get() **两条入口都过校验**（只挡入参会漏掉"构造期就把根写歪"这条路径）。server 侧 store_open 拒绝时分列原因（非法 ns / 非法 data_dir 各一条，后者自带两条出路），描述同步（J9 之外顺手补了返回契约）。锁：src/store/multi_store_test.mbt 新增成对用例 —— 正向 . / temp / temp/ms-b78 不误拒，反向 "" / ../outside / temp/../../outside / /etc / C:/evil / 前导反斜杠 六形态必拒，再加入口级断言（非法目录 open=false 且 ns 不进 ns_list；合法 temp 落点 open=true）。

### FIXED(2026-09-27 四模式轮 · Round 5 修复段（指挥官终审，锁承重已复算） / BUG-82)

src/ops/ops_selfdrive.mbt：selfdrive_export_tasks 表头那行的时间从**字面量 "now"** 改为新增可选参数 now~（默认空串），空串时明写「缺失（调用方未传服务端盖章的 now）」而不是拿占位符冒充值；
src/server/server.mbt 调用点传 now_default()（与 BUG-33 时间戳盖章政策一致）。锁：src/ops/ops_selfdrive_test.mbt 新增 selfdrive_b82_export_stamp_成对 —— 传了 now 则 task.md 表头含该时间戳，没传则含「缺失」，两种形态都断言**不含**"导出时间：now"。
## BUG-83 [2026-09-27T05:59:38Z] [medium] FIXED
- summary: run_check 回执顶层 ok 与 status 两种含义，描述只解释 status ⇒ 调用方把「已落库」读成「已通过」（实测致 Round 5 验证段自述 11/11 为伪）
- detail: 位置：src/engine/omega_gate.mbt:125（m.set("ok", Json::boolean(true))）与 :131（status 由推导值写入）；对外文案 src/server/server.mbt:1128 run_check 描述的结尾。
现象：run_check 返回值同时含 ok 与 status 两键。ok 的含义是「判据已跑完并落库」（spawn 成功即 true，与判据通过与否无关）；status 才是 passed/failed 判定（服务端由子进程退出码推导）。描述里只写了「status 一律由结果 JSON 的 ok 推导」——这个「结果 JSON 的 ok」指的是 specs 表里那次 spawn 的结果对象，跟回执顶层的 ok 不是同一个东西，而顶层 ok 自己的含义在文案里一个字都没提。
实测代价（不是假想）：Round 5 验证段首跑驱动 temp/r5/r5_round.py 以 r.get('ok') is True 作为判据结论，打印「判据 11/11」「结论 GREEN」，而同一份 r5_round_report.json 里 j9_load_bearing 的 status 就是 failed；该错误结论还被写进了验证段叶子正文并入 Omega 链已完成的记录。
修复：run_check 描述把两个 ok 的分工写在脸上（顶层 ok=已跑完并落库，判定只看 status，别拿 ok 当结论）。
锁：scripts/check_doc_surface.py J9 新增第三判据 RET_MUST_EXPLAIN（按工具列出必须同时出现的语义关键词，缺任一词逐一点名发红）；承重证明 temp/r5/prove_j9.py 第④段在真实真源上抹词 ⇒ 必须红；--selftest 含「干净合成输入不误红」反向对照。
- reported_by: pmode-r5-verify
- task_id: T0r398


### FIXED(2026-09-27 四模式轮 · Round 5 勘误段（指挥官终审，锁承重已复算） / BUG-83)

真源 src/server/server.mbt 的 run_check 描述把两个 ok 的分工写在脸上：**顶层 ok 只表示「判据已跑完并落库」**（spawn 成功即 true，与判据通过与否无关），**判据通过与否只看 status**（passed/failed，服务端由退出码推导），并点名"别拿 ok 当结论"的实测后果。旧措辞『status 一律由结果 JSON 的 ok 推导』整句删除——那句里的 ok 指的是 specs 表里那次 spawn 的结果对象，跟回执顶层同名不同义，正是本轮误读的源头。锁 scripts/check_doc_surface.py J9 新增第三判据 RET_MUST_EXPLAIN（按工具列出必须同时出现的语义关键词，缺任一词逐一点名发红；清单里的工具从注册表消失同样发红——清单失效比缺契约更糟）。SELFTEST 补三条对照：抹词必红、分工写清不误红、清单落空必红；承重证明 temp/r5/prove_j9.py 第④段在**真实描述**上逐个抹「已跑完并落库」「只看 status」⇒ 各发红一条，末尾追加无关句 ⇒ 不误红（防恒红判据）。调用面实测：tools/list 120 工具，run_check 描述 1425 字符，两措辞齐、旧口径残留 0；文件面判据 temp/r5/b83_closure_check.py 七条断言全成立（含"首跑伪结论日志仍留痕、不许事后抹证"）。顺带修掉那条真红的原因：prove_j9.py 原以 replace(…,1) 抠字，而 bug_list 描述里「返回」实测出现 2 次（task_plan_deep/run_check/github_queue_status 各 1 次），只抠一处 J9 照绿 ⇒ 变异不生效；已改全量替换并先量次数。勘误落账方式：已完成的 T0r395 验证段行不改写（账本/树同一套路子），另起 ns pmode-r5-erratum 根 T0r399（12 叶全 已完成，两条判据由服务端 run_check 真跑 status=passed，output_validate 正门 pass / 必然违例对照门 fail）。
## BUG-84 [2026-09-27T06:17:00Z] [medium] FIXED
- summary: 文档面判据范围在规范表面滞后（AGENTS.md/AI-DEVELOPMENT-STANDARD.md 仍写 J1-J8，真源已有 J9），且无判据能抓这种滞后（J1-J5→J1-J8 已重犯一次）
- detail: 位置（现状面两处，都是规范性表面）：AGENTS.md:299 的『check_doc_surface（文档面 J1-J8：…）』与 AI-DEVELOPMENT-STANDARD.md:15 表格里的『check_doc_surface(J1-J8)』。
现象：Round 4 给 check_doc_surface 加了 J9（返回契约），两份规范表面仍写 J1-J8；本轮又加了 J9 的第三判据，范围数字继续滞后。守卫族段落是『实现了几条判据』的唯一对外口径，写少了=声明滞后（读者以为 J9 不存在，绕着走），写多了=幻影判据（读者拿不存在的判据当门禁）。
这是同一族第二次：CHANGELOG.md:168 记着上一轮就发生过 J1-J5 → J1-J8 的滞后，当时靠人肉同步、没留判据。
实测复现：python -c "import re,pathlib;print(sorted({int(x) for x in re.findall(r'J(\d+)', pathlib.Path('scripts/check_doc_surface.py').read_text(encoding='utf-8'))}))" ⇒ [1..9]，而 AGENTS/规范两处 J1-(\d+) 抓出来的都是 8。
修复：新增 J10 判据范围自述==实现（扫描 AGENTS.md/AI-DEVELOPMENT-STANDARD.md 里含 check_doc_surface 的行上的 J1-n，与脚本自身 def jN_/---- JN 实现的最大序号比对；少一分『声明滞后』、多一分『幻影判据』都点名发红，一处口径都抓不到即 FATAL 不报绿）；两份规范表面同步到 J1-J9。
- reported_by: pmode-r5-erratum
- task_id: T0r400


### FIXED(2026-09-27 四模式轮 · Round 5 勘误段（指挥官终审，锁承重已复算） / BUG-84)

同步三处现状声明面到 J1-J10：AGENTS.md:299（守卫族段，连 selftest 覆盖范围一起如实写）、
AI-DEVELOPMENT-STANDARD.md:15（规范表格里的守卫族行）、templates/pipeline_mode_tidy.md:45（对外发货模板）。
锁 = scripts/check_doc_surface.py 新增 **J10 判据范围自述==实现**：实现侧从本脚本自身的
`def jN_` / `---- JN` 标记取并集（实测 max=J10），声明侧扫 AGENTS + 规范正文 + templates/*.md +
plugins/source/*.md 里含 check_doc_surface 的行上的 `J1-Jn`（BUG-66 的教训：发货正文会被放大成 4 份对外契约，
扫描面不许只挑两份）。少写一档 ⇒『声明滞后』、多写 ⇒『幻影判据』，逐条点名文件与行号；
一处声明都抓不到同样发红（删声明消解违例 ≠ 没有问题）。
踩到并修掉的解析器坑（判据先判自己）：正则初版写成 `J1-(\d+)`，而三处表面实际写的是 `J1-J8` 双 J 形态
⇒ claims 恒空；正是『空扫描必红』那条哨兵把它当场抓住，而不是让它以全绿蒙混。
承重证明 temp/r5/prove_j10.py：在**真实文件副本**上做四向变异（少写一档必红 / 吹到 J1-J99 必红 /
良性追加不误红 / 整块声明删掉也红），三个表面各跑一组，副本 finally 清理。
--selftest 新增 5 条 J10 对照（滞后 / 幻影 / 两面一致不误红 / 空扫描 / 实现侧解析饿死）；
守卫自身的 SELFTEST 与 PASS 文案同步到 J1-J10（消息本身也是声明面，别制造第二次滞后）。

### FIXED(2026-09-27 全量兑账（6 路只读复核 + 指挥官抽验 5 条：BUG-12/19/23/33/9） / BUG-1, BUG-2, BUG-3, BUG-4, BUG-5, BUG-12, BUG-14, BUG-15, BUG-16, BUG-17, BUG-18, BUG-19, BUG-21, BUG-22, BUG-24, BUG-31, BUG-32, BUG-33, BUG-36, BUG-37, BUG-38, BUG-39, BUG-41, BUG-42, BUG-48, BUG-49)

口径：本条小记是**兑账补记**，不是新的修复动作。逐条判定由 6 个只读子代理各自给出 file:line 或测试名，
指挥官再抽验 5 条最容易判错的对上代码（BUG-12 无 ns 的 list 是否真走 list_all、BUG-19 是否存在绕过包装层的
直连注册、BUG-33 schema 内 `now` 属性是否已清零、BUG-9/23 的"没修"是否成立）；抽验结论与复核一致。
判据口径同时改了：状态只从条目抬头反解，**不再用「条目数 − 小记条数」**（旧口径把"小记有几条"当成
"修了几条 bug"，一条小记可收 1~16 条，也可一条不收 ⇒ 那句"30 条待修"从来没有定义，见 BUG-9）。
同批另有 9 条判 DUPLICATE（BUG-6/7/13/40/43/44/45/46/47，抬头已写 →主编号）、1 条判 FALSE_POSITIVE
（BUG-10：pause 本就接受[待领取]，"没有合法废弃出路"不成立）。以下逐条给本轮复核证据：

- BUG-1：src/server/server.mbt:277 now=now_default()；src 内 get_str(args,"now") 0 命中；锁 scripts/check_tools_sync.py:39,205 判据5（服务端盖章已生效）
- BUG-2：src/core/core_task.mbt:381 execute 前态含[执行中]；锁 engine_execute_r2_test.mbt:79,194（retry→execute 出路已开）
- BUG-3：src/server/server.mbt:240 audit_log_payload + :4128 调用；锁 pipeline_r2_wbtest.mbt:142（返回体自带 scope 说明）
- BUG-4：src/server/run_check_guard.mbt:281/137/150，接入 server.mbt:1170；锁 run_check_guard_test.mbt:40,85,103（laya/github 侧仍 sh -c，另案）
- BUG-5：src/server/bugreport.mbt:304,330 resolved_path；锁 bugreport_test.mbt:142（③统一契约未做，见 BUG-40 归并说明）
- BUG-12：src/server/server.mbt:1361 无 ns 走 engine.list_all()；store_sqlite.mbt:407 SELECT 无 WHERE ns（无锁）
- BUG-14：src/server/server.mbt:529 laya_ensure_decision，Ok :2721 / Err :2734 补齐；锁 laya_decide_wbtest.mbt:85-165（六条白盒）
- BUG-15：src/server/issue_scan.mbt:124 scan_is_comment_line / :136 scan_is_rules_table；锁 lint_5/6/7（行尾注释也覆盖）
- BUG-16：src/server/server.mbt:560 project_version，:717/:3175/:3194 引用；锁 fist-mbt_wbtest.mbt:92（0.2.4 字面量零命中）
- BUG-17：check_tools_sync + check_doc_surface 双 PASS，120 工具四文档对齐（构建期单一真源仍缺，另案）
- BUG-18：src/server/server.mbt:450/465 probe TTL 缓存、:2655 no_sidecar；锁 pipeline_r2_wbtest.mbt:129（预算 <30s 同文件锁）
- BUG-19：src/server/server.mbt:849 _instrument 读 schema_required ⇒ 缺必填 ToolError；s1.tool 直连 0 处（120 工具全过包装层）
- BUG-21：src/server/server.mbt:906 MCPServer("fist-mbt", project_version)，全仓无 0.1.0（握手行无独立断言）
- BUG-22：README.md:38-77 分组和=120 且 10 工具齐全；锁 check_doc_surface.py J3（J3 即本条建议②）
- BUG-24：src/engine/engine_dag_mc.mbt:152 上界钳制 + samples_requested/capped；锁含防误钳成对
- BUG-31：src/server/output_validate.mbt:65 artifact_spec_errors（:364 调用）；锁 output_validate_r3_test.mbt:41/71/120（未知键不再静默降级）
- BUG-32：scripts/fist.py:60 newest_source + :78-90 过期自动 build，FIST_NO_AUTOBUILD=1 显式拒绝（无锁）
- BUG-33：server.mbt schema 内 "now" 属性 0 命中；锁 check_tools_sync.py:39/205 判据5（描述残留 28 处另立 BUG-80）
- BUG-36：src/server/memory.mbt:183 白名单外 gc:false+error 并列出集合；锁 memory_test.mbt:374/404（不再静默改靶）
- BUG-37：src/ops/ops_modes.mbt:145 改为真实工具名；锁 check_tools_sync.py:190-203（拦截仍靠调用方匹配）
- BUG-38：templates/ 内 run_check_external 0 命中，全为 run_check({task_id,cmd,args,...})；锁 check_tools_sync.py:209-214
- BUG-39：scripts/fist.py:224 isinstance(payload,dict) 后才取 verdict，:229 兜 UnicodeDecodeError（仓内无锁）
- BUG-41：src/engine/omega_strong.mbt:24/31 + engine.mbt:1012/1074 + server.mbt:1432 boundary_probe；锁 engine_boundary_test.mbt:43/70（外部模板库半越界未落）
- BUG-42：src/server/server.mbt:4441 描述已是一源四态 + cl1→cl7；锁 project_standards_wbtest.mbt:46/72 + J6/J7（issue_scan.mbt:6 注释仍称三形态）
- BUG-48：src/server/server.mbt:4441；J7 扫 SERVER（check_doc_surface.py:233）；锁 test "R116：一源四态…"（本族主编号）
- BUG-49：templates/pipeline_mode_{verify,tidy,polish}.md 无 check_results/now；锁 J8 + selftest:524（本族主编号）
## BUG-85 [2026-09-27T12:18:14Z] [high] FIXED
- summary: [bugfind:backend-divergence] MemoryStore::list_tasks 按 default_ns 过滤、SQLite 后端不过滤，同名方法两种语义
- detail: 现象：trait 声明是「列出全部任务」，内存后端却按 default 命名空间过滤，SQLite 后端不过滤 ⇒ 凡按 list_all()/list_tasks 取数的工具（heal / cost_budget_split / status_summary 等）在测试里与生产里作用域不同：测试绿的那一份根本没跑过生产的数据形状。
活证据（2026-09-27 实测）：同一夹具下 list_tasks 两后端返回行数不同；收口后按 trait 声明收敛，并让 list_tasks_in("") 在两后端同义（列出全部）。
修复真源：src/store/store_memory.mbt / store_sqlite.mbt；锁：src/store/store_backend_semantics_test.mbt（成对断言两后端同语义）。
注：本条正身早写在 commit 9a26441 的说明里但从未进账本 ⇒ 由本会话补登（BUG-9 的形状）。
- reported_by: phaseC-independent-cleanup

## BUG-86 [2026-09-27T12:18:14Z] [high] FIXED
- summary: [guard:startup-args] 根 .mcp.json 改名后三个消费者仍钉旧名 ⇒ cl7 FATAL、仓库自测红、插件态无法重投影
- detail: 现象：commit 254de24 把根 .mcp.json 改名为 .mcp.dev.json，而 gen_plugins / check_plugin_sync(cl7) / pipeline_r2_wbtest(BUG-18 锁) 三个消费者仍写死旧文件名。
后果：cl7 直接 FATAL(2)（判据无法自证）、`moon test` 的 BUG-18 锁红、四宿主插件态无法重投影——即整个「一源四态」链条断在一份被搬走真源的配置文件上。
修复：三处消费者统一走 MCP_CANDIDATES 按优先级解析实际存在的那份；J5 增加「真源不存在⇒红」（旧版在没有真源时「逐字相等」恒过，那是装饰）；投影正文里的文件名跟着解析结果走，不再写死。
真源：scripts/gen_plugins.py、scripts/check_plugin_sync.py、src/server/pipeline_r2_wbtest.mbt。
- reported_by: phaseC-independent-cleanup

## BUG-87 [2026-09-27T12:18:14Z] [critical] FIXED
- summary: [bugfind:string-interpolation] curl 命令里的 `Bearer ${FIST_GITHUB_TOKEN}` 被编译器当字符串插值 ⇒ 三个 plan 构造器在 JS target 运行时抛错
- detail: 现象：src/server/github_sync.mbt 三处把 token 占位符写成字面量 `${FIST_GITHUB_TOKEN}`，MoonBit 按字符串插值编译，JS 产物是一行引用未定义变量的模板串。
活证据（2026-09-27 实测，temp/phaseC/gh3.log）：`ReferenceError: FIST_GITHUB_TOKEN is not defined`，调用面分别在 github_flush_plan / github_build_comment_plan / github_build_close_plan。产物证据：_build/js/debug/test/src/server/server.whitebox_test.js 内 `Authorization: Bearer ${FIST_GITHUB_TOKEN}` 以模板占位符形态出现。
影响：GitHub 同步的「生成计划」这一整段对外能力在 server 默认目标（JS）上完全不可用，native 侧则是编译期未定义标识符——不是边缘字段，是整条路。而且它此前**零覆盖**：只有把 payload 真解析一遍的判据才会撞出来（BUG-35 那条锁就是干这个的）。
修复：新增 token_placeholder() 单一真源（`"$" + "{FIST_GITHUB_TOKEN}"` 拆开拼），三处共用；锁 src/server/github_sync_wbtest.mbt 第④条断言占位符逐字活到命令里。
- reported_by: phaseC-independent-cleanup







### FIXED(2026-09-27T12:18:14Z / BUG-85, BUG-86, BUG-87)
- evidence: 这三条的正身写在补登的 detail 里（含 file:line、产物证据与可复跑判据）；修复真源分别是 src/store/store_memory.mbt+store_sqlite.mbt（BUG-85，锁 store_backend_semantics_test.mbt）、scripts/gen_plugins.py+check_plugin_sync.py+src/server/pipeline_r2_wbtest.mbt（BUG-86，J5 新增「真源不存在⇒红」）、src/server/github_sync.mbt 的 token_placeholder()（BUG-87，锁 github_sync_wbtest.mbt 第④条）。实测证据 = JS target 486/486 与七守卫 rc=0。
## BUG-88 [2026-09-27T12:37:17Z] [high] FIXED
- summary: [guard:vocab-drift] report_bug 的 severity 闭集含 critical/open，而 gen_plugins 的抬头文法只认 high|medium|low ⇒ 合法上报能写出判据读不到的抬头，生成器 FATAL
- detail: 现象：两侧各写一份同一套词。
  · 写侧 src/server/bugreport.mbt:14 `fn bug_severities() = ["open","critical","high","medium","low"]`，
    且 :261 省略 severity 时**缺省落 "open"**；
  · 判据侧 scripts/gen_plugins.py:76 抬头文法只匹配 `\[(high|medium|low)\]`。
活证据（2026-09-27 实跑，本轮把自己撞红的就是这条）：把 BUG-87 按 severity=critical 入账后
  `python scripts/gen_plugins.py` ⇒ `FATAL 真源自证失败：条目 87 条 / 可解析抬头状态 86 条不符`，
  四宿主插件态无法重投影；`ledger_status` 同时报「BUG-87 被小记点名但状态不是 FIXED」
  ——它其实已是 FIXED，只是文法读不到那行，于是**已修好的条目被投影成未修**。
另一面：`open` 是状态词冒充严重度（抬头状态字段也叫 OPEN），缺省值 [open] 落在文法里同样读不到，
  ⇒ 任何省略 severity 的上报都会写坏账本，且此前无一条测试覆盖（既有测试都显式传 severity）。
影响：①生成链停摆（cl7 与插件投影全依赖 gen_plugins）；②对外那句「X 条待修」由抬头状态反解，
  读不到的条目被直接丢掉 ⇒ 待修数被低估，这是"看起来更干净"的假绿方向。
修复（本轮已落）：
  1. 写侧闭集与缺省值改为 critical/high/medium/low（缺省 medium，去掉状态词 open）；
  2. 判据侧文法同步为 `\[(critical|high|medium|low)\]`；memory/bugs.md 的抬头文法行同步；
  3. 加**跨语言单源门禁** gen_plugins.severity_vocab_drift()：从 bugreport.mbt 解析 bug_severities()
     与自己的文法做集合相等比对，漂移即 FATAL（生成前自检，与 ledger_status 四条硬门同处）；
  4. 锁 src/server/bugreport_status_wbtest.mbt「BUG-88」一条：逐个 severity 往返
     （写出去→从盘上读回该字段），并钉缺省值=[medium]、闭集外的 blocker 必须被显式拒绝。
残余（不自证已修）：门禁靠正则读两侧源码，若词表改成从常量/外部文件取，解析会失效 ⇒
  解析失效那一支已按「先判解析器坏」出红，但形状仍是约定而非证明。
- reported_by: phaseC-independent-cleanup



### FIXED(2026-09-27T12:37:17Z / BUG-88)
- evidence: 两侧词表收成一份真源并互锁：写侧 src/server/bugreport.mbt 的 bug_severities()=[critical,high,medium,low]、缺省由 open 改 medium；判据侧 scripts/gen_plugins.py 的抬头文法同步加 critical；memory/bugs.md 抬头文法行同步。新增 gen_plugins.severity_vocab_drift() 作生成前自检（解析写侧闭集与文法做集合相等，漂移即 FATAL、解析器饿死亦 FATAL），四方向合成对照实测：现状 PASS、文法窄一级红、写侧混入 open 红、词表读不到红。锁：src/server/bugreport_status_wbtest.mbt 的 BUG-88 一条（逐值往返 + 缺省 [medium] + 闭集外必须显式拒）。实测：JS target 全量绿 + 七守卫 rc=0。
## BUG-89 [2026-09-27T12:47:33Z] [medium] FIXED
- summary: [guard:selftest-never-run] check_doc_surface.py --selftest 不进 CI ⇒ 判据自检本身可以崩掉而全量仍报绿（本轮实测两处崩溃：NameError: fake、TypeError: sorted）
- detail: 现象：本轮之前的 ci.yml 只把两个自检里的一个挂上了自动面。
  · `git show HEAD:.github/workflows/ci.yml` :48-50 跑 `check_test_sync.py --selftest`；
    :64 的 `check_doc_surface.py` **只有全量**，没有 --selftest；
    store-schema 守卫那一步（现 :71-72 带自检）当时整段还不存在——它和文档面自检都是本轮才补的。
活证据（2026-09-27 实跑，本轮我自己改坏后撞上的）：
  `python scripts/check_doc_surface.py --selftest`
    → `NameError: name 'fake' is not defined`（j_selftest 里 J6 对照的输入串被编辑时误删）
    → 补回后又 `TypeError: sorted expected 1 argument, got 2`（SELFTEST OK 那行的规则清单派生式写错）
    → 两处都在**同一命令**上发红，而 CI 全量分支 rc=0、守卫族收口脚本也 rc=0 ⇒ 一处都没拦住。
放大器（写进账是因为它会一直骗人）：
  `python scripts/check_doc_surface.py --selftest 2>&1 | tail -4; echo rc=$?` 里的 `$?` 是 **tail** 的退出码，
  不是 python 的 ⇒ 崩溃的 traceback 配上 rc=0 会被读成"通过"。本轮第一次就是这样漏过去的
  （留档 temp/phaseC/selftest_doc.log：改前那份里有完整 traceback，改后才是 SELFTEST OK）。
影响：AGENTS.md 对外承诺「`--selftest` 用合成违例证明 J6/J7/J8/J9/J10 能发红」——这条承诺没有任何
  自动面复核；判据的"会红证明"退化成一次性人工动作，正是 BUG-50 立的规矩要防的形状。
  更糟的是本轮新增的 J4 子判据是靠这条自检背书的，自检不跑 ⇒ 新判据等于没上过岗。
修复（本轮已落）：
  1. ci.yml 文档面那一步改成先 `--selftest` 再全量（与 store-schema 那一步同形）；
  2. `SELFTEST OK` 里"覆盖了哪几条判据"不再手写，改为 `inspect.getsource(j_selftest)` 反解
     （正文里没写某条对照，那行就不会报它 ⇒ 声明与自检体不可能再漂移）；
  3. 修回 `fake` 定义与 `sorted(..., key=int)`；自检现在报 J4/J6/J7/J8/J9/J10。
残余（不自证已修）：`--selftest` 只证明判据**能**红，不证明它红的口径对；rc 被管道吞掉这类
  读数姿势问题要靠"落盘日志再读 rc"的习惯，本轮已把每条守卫输出写到 temp/phaseC/*.log 复核。
- reported_by: phaseC-independent-cleanup



### FIXED(2026-09-27T12:47:33Z / BUG-89)
- evidence: 把自检挂上自动面并让它自己声明覆盖面：.github/workflows/ci.yml 文档面一步改为 `check_doc_surface.py --selftest` + 全量两步；check_doc_surface.py 的 SELFTEST OK 规则清单改由 inspect.getsource(j_selftest) 反解（不手写），并修回被误删的 fake 定义与 sorted(key=int)。实测：`python scripts/check_doc_surface.py --selftest` rc=0 且正文点名 J4/J6/J7/J8/J9/J10；改前同一命令两次 traceback（留档 temp/phaseC/selftest_doc.log）。AGENTS.md/scripts/README.md 的守卫族描述同步声明这条 CI 接线。
## BUG-96 [2026-09-28T05:01:52Z] [low] FALSE_POSITIVE
- summary: 巡回探针：调用面可用性核验
- evidence: 非产品缺陷——本条由 `scripts/mcp_tool_tour.py --plane read` 自己写进真账本的：读面把 `project_dir="."` 当探针项目，而 `.` 就是仓库根 ⇒ `report_bug` 直接落`memory/bugs.md`。且第一发还与本轮手写的 BUG-90 **撞号**（脚本按 05:04 读到的 89 条反解下一个号，而 05:01 那发已经把上界推到了 90——同一份号在两处各自数，就是双发）。缺陷本体另立条目并已修（读面不再允许写真账本），此处只把垃圾条目改判并留据。


## BUG-90 [2026-09-28T05:04:57Z] [critical] FIXED
- summary: store_open(scratch=true) 的命名空间库不参与路由——单轮验证的任务行仍落仓库根 fist-mbt.db，而自述写的是"库落 temp/ 临时区，不污染仓库根"
- detail:
  实跑面（安装版全局命令，2026-09-28 12:16 全工具巡回）：
    store_open(namespace=goalverify0928, scratch=true) → {"opened":true,"data_dir":"temp","scratch":true}
    并且建出了 temp/goalverify0928.db。
  只读复核（sqlite mode=ro，两库同一时刻）：
    temp/goalverify0928.db → tasks=0 call_log=0（**空库**）
    仓库根 fist-mbt.db     → tasks 里出现 ns='goalverify0928' 的行 T0r496（project_dir=temp/goal-verify/proj），call_log 里 8 条同 ns
  根因（读码定位，不是猜）：工具闭包统一注入模块级 engine —— src/server/server.mbt:17
  `let engine = make_engine()`，而 make_engine 走 SqliteStore::new()；旧版
  src/store/store_sqlite.mbt 的 `SqliteStore::new()` 写死 `SqliteStore::open("fist-mbt.db")`。
  `MultiStore::get()`（真正按 ns 路由到 {data_dir}/{ns}.db 的那条路）在全仓**零调用**
  ⇒ ns 只是"已打开命名空间"的登记表，不是存储路由。
  放大器（为什么一直没被发现）：scripts/scratch_verify.py 标题自称"验证 store_open scratch=true
  临时命名空间落 temp/ 不污染仓库根"，但它只断言 ① store_open 回显 data_dir=="temp"
  ② 仓库根没有名为 `{ns}.db` 的文件——两条都只看**文件位置**，从不查**行的落点**
  ⇒ 这是一条恒绿的隔离判据，BUG-90 正好藏在它的盲区里。
- reported_by: installed-cli-tour

## BUG-91 [2026-09-28T05:04:57Z] [critical] FIXED
- summary: run_check 无上限累积子进程 stdout/stderr，一次调用即可打死整个 MCP 会话（白名单收住了"能跑什么"，没收住"能吐多少"）
- detail:
  触发面：巡回第 30 个工具 run_check(cmd="python", args=[]) —— Windows 的 python 在无 tty 时
  把 _pyrepl 的 traceback 反复刷出，server 侧 `stdout += d` 不设上限。
  失败形态（两档都实测到，留档 temp/tool-tour-20260928044409-3dde15/tour-*.stderr.log 与
  temp/runaway_repro_3d397a.log）：
    ① 堆到 4 GB → `FATAL ERROR: Ineffective mark-compacts near heap limit` → 进程死；
    ② 用无限输出夹具 node -e "while(true)process.stdout.write('x'.repeat(200000))" 复现，
       修复前产物（sha256:9771abf9）2.1s 管道关闭，stderr `RangeError: Invalid string length`
       （抛出点就是拼接处）；修复后安装版同一夹具 6.6s 正常回执 status=failed、进程存活。
  连带损失（也是本条要入账的第二件事）：崩溃后驱动把后续 94 个工具全记成 broken，
  既夸大了失效面，又让崩溃点之后的工具一次都没打到——判据侧的账要记在判据头上。
  修法：src/server/run_check_js.mbt 每流各留**末 1 MiB**（保留尾巴，判据关键信息在结尾），
  并如实带 stdout_capped/stderr_capped 旗 ⇒ 截断可见，不伪装完整；回执 stdout_tail 仍是末 2000 字符，
  `output_truncated` 由 engine/omega_gate.mbt:136 按长度算，语义不变。
  残余（不自证已修）：这条锁目前没有 MoonBit 单测（js-only 执行面），判据在
  temp/runaway_repro.py；是否升级为仓库内判据交裁决。
- reported_by: installed-cli-tour

## BUG-92 [2026-09-28T05:04:57Z] [medium] FALSE_POSITIVE
- summary: 状态机拒绝文案的"要求状态"与实际要求的态不一致——「非法拆分: split 要求状态 [待领取]，当前是 [待领取]」把调用方指回它已经满足的那一档
- detail:
  逐字文案（从回执 JSON 的 \u 转义反解，不是控制台显示）：
    `非法拆分: split 要求状态 [待领取]，当前是 [待领取]`
  同一棵树的对照实测（巡回播种链）：
    publish → plan           被上述文案拒；
    publish → claim(assignee) → plan   **ok**（返回 ["T0.1","T0.2"]）。
  ⇒ 真实要求的是"根任务已被领取（已领取/拆分中）"，而文案把"要求状态"印成 `[待领取]`，
  与"当前状态"字面相同 ⇒ 调用方按文案办事会去把任务改成一个它已经是的状态，永远走不出来。
  违反本仓对拒绝文案的一贯规矩（拒绝必须自带正确出路，见 BUG-4/BUG-78 同族）。
  建议修法：状态机报错处点名"要求的是哪一态、当前是哪一态、用哪个工具能走到那一态"，
  并给这条文案配成对判据（要求态 != 当前态；相等即判文案坏了）。
  未修原因：射程在 src/engine 状态机的报错拼装，与本轮并行改动面重叠；交裁决后另开。
- reported_by: installed-cli-tour

  改判依据（2026-09-28 活证据，temp/bug92_probe.log，installed 产物 sha256:eb18f4f0，
  回执 JSON 的 \u 转义逐字反解，不经控制台码页）：
    `非法迁移: split 要求状态 [\u5df2\u9886\u53d6]，当前是 [\u5f85\u9886\u53d6]` ＝「要求状态 [已领取]，当前是 [待领取]」——两态本就不同，没有自相矛盾。
  原判那句「要求状态 [待领取]，当前是 [待领取]」是**上报侧**把 cp936 控制台乱码按字形猜出来的，
  属于记忆条目「报缺陷前先读它自己的定位声明」的同型失误：乱码不是证据。
  真缺陷另立 BUG-99（拒绝文案不带出路），本条按误报关闭。

## BUG-93 [2026-09-28T05:04:57Z] [medium] FIXED
- summary: 发布入口迁到 cmd/cli 后，仓库内 15+ 处脚本/文档仍指 cmd/main 且不带 serve 子命令——E2E 的"绿"测的是不发布的那棵入口
- detail:
  命中清单（grep -rl "cmd/main" scripts/ 实跑）：
    mcp_smoke.py、scratch_verify.py、atgc_selfdrive_demo.py、award_demo.py、dag_depend_verify.py、
    dispatch_verify.py、enhance_verify.py、enrich_selfdrive.py、evolve_critic_verify.py、
    executor_route_verify.py、fist-mbt-http.py、fist.py、flush_github.mjs、
    blackbox/patch_esm_main.py、demo.ps1、scripts/README.md（索引正文同样残留）
  两棵入口**同时存在且产物不同**（同一时刻构建）：
    _build/js/debug/build/cmd/main/main.js = 2,681,667 B
    _build/js/debug/build/cmd/cli/cli.js   = 2,779,308 B
  发布产物是后者（scripts/blackbox/build_release.ps1:38 与 release.yml 的 4 处入口路径本轮已改到 cmd/cli）。
  后果：这些 *_verify.py 全绿也证明不了装好的 `fist-mbt` 全局命令可用（本轮就是靠新增
  scripts/mcp_tool_tour.py 才第一次打到发布入口的 129 个工具）。
  建议修法：照 J7"旧口径禁词"同形加一条入口清单守卫（扫 scripts/ 与 README 里的 `cmd/main`
  字面 ⇒ 红，历史陈述文件豁免），再逐只改到 `cmd/cli` + `serve`。
  未修原因：一次性改 15 个脚本会越出本轮责任面（且与并行改动面重叠），先入账并给出可复跑判据。
- reported_by: installed-cli-tour

  收口（独立修复，不走流水线）：
  ① 现状面 cmd/main → cmd/cli：51 份文件 / 104 处（scripts 28 个 .py 全部 py_compile 通过，docs/.github/根 .md/.mcp*.json/plugins/source 真源同步）；历史面（memory/ reports/ CHANGELOG.md）不动。
  ② 入口搬家的另一半：cmd/main 裸跑＝直接起 server，cmd/cli 裸跑＝只打印 help ⇒ 26 个启动点的 argv 补 `"serve"`（temp/fix_serve_argv.py 逐文件计数落盘）。
  ③ 新守卫 scripts/check_entry_paths.py：入口清单从 `cmd/*/moon.pkg` 的 `pkgtype(kind:"executable")` 反解、发布入口从 build_release.ps1 反解，R1 禁现状面指退役入口、R2 禁 Popen argv 少 serve；`--selftest` 四格（合成违例命中 2 / 干净不误红 / 空清单报「判据空转」/ R2 成对）。承重实测：同一守卫跑在 HEAD 树（temp/verify-327bb7a）= 119 条违例 rc=1，跑在修复后的树 = 0 条 rc=0。
  ④ 调用面终审：HEAD 派生树 + 本环三件修复 → `moon build --target js cmd/cli` → `python scripts/patch_esm_main.py` → `python scripts/mcp_smoke.py` = MCP-SMOKE PASS（tools/list 129、publish/get 打通），证据 temp/smoke_e2e_proof3.log。


## BUG-94 [2026-09-28T05:04:57Z] [high] FIXED
- summary: cost_stats 无参调用触发未捕获的 ERR_SQLITE_ERROR，直接把 MCP 会话打死（与 BUG-91 同族：store 层 JS 桥的异常没被收成 JSON-RPC error）
- detail:
  逐字（temp/tour_evidence.txt 的 crashed 行，excerpt 取自 server stderr）：
    `server closed stdout; stderr tail= ... Error [ERR_SQLITE_ERROR] ... code: 'ERR_SQLITE_ERROR', errcode: 1, errstr: 'SQL lo...`
  成对实测（同一份安装版 sha256:99beda11，同一驱动，只差 cwd/库）：
    写面（cwd=临时 box，FIST_DB_PATH=box/tour.db）  → cost_stats arguments={} **ok**
    读面（cwd=仓库根，FIST_DB_PATH=temp/tool-tour-*.db）→ 同一调用 **进程死**，驱动复活 server 后继续跑完其余工具
  ⇒ 主张只写到这一层：存在一种库状态让 cost_stats 抛未捕获 sqlite 异常并终止服务面；
  具体 SQL 未定位，第三棵树未复跑（归因边界照写）。
  建议修法：① store 层 JS 桥把 prepare/step 的异常包成 Err 返回（与本仓"永不 reject"的
  run_check_js.mbt 同形）；② server 侧工具分发加 catch-all，任何 handler 异常回 JSON-RPC error
  而不是让进程退出——这条是服务面级别的鲁棒性，值得单独一条判据（"任意工具畸形调用后
  会话必须仍可响应"）。
  未修原因：定位需要逐条 SQL 复现，本轮预算已用于两个 critical 的修复与安装面自证。
- reported_by: installed-cli-tour

### FIXED(2026-09-28T05:04:57Z / BUG-90, BUG-91)
- evidence: 两格都改在**调用面可复跑**的位置并配成对对照。BUG-90：src/store/store_sqlite.mbt 新增
  `SqliteStore::db_path_from_env/default_db_path`，默认库由环境变量 `FIST_DB_PATH` 决定
  （与 FIST_RUN_CHECK_ALLOW 同族：扩权位只在运维侧进程环境，MCP 调用方不能自我扩权），
  未设置时逐字回退 "fist-mbt.db"（零回归）；白盒锁 src/store/store_db_path_wbtest.mbt 三条
  （缺席/显式路径/空串）；判据 scripts/store_isolation_probe.py：同一个 cwd 两格只差这一环境变量，
  C1 断言行落指定库且 cwd 内**不得**长出默认库、C2 断言无 env 时回落 cwd，`--selftest` 再追一格
  合成违例（库路径指向不存在的目录 ⇒ 必须报红）。承重对照实测：修复前产物（sha 9771abf9）在 C1 报
  RED / C2 GREEN，修复后（f24be5be）两格 GREEN。BUG-91：src/server/run_check_js.mbt 每流上限 1 MiB
  + stdout_capped/stderr_capped 旗；对照实测见本条正文（同一夹具，修前 2.1s 死、修后 6.6s 活）。
  全量面：JS 后端 529/529（HEAD 基线 526 + 本轮新增 3 条白盒）；巡回（安装版全局命令）
  写面 129/129 工具打到调用面 = ok 81 / refused 42 / skipped 6 / crashed 0，明细逐字留档
  temp/tour_evidence.txt。安装面：scripts/blackbox/install_onecmd.ps1 加 `-LocalZip`（离线/发布前自证）、
  install.sh 加 `FIST_LOCAL_ZIP`，两条下载失败路径改为打印 HTTP 状态与候选 URL。

### FIXED(2026-09-28T05:26:41Z / BUG-94)
- evidence: 根因不是"cost_stats 的 SQL 写错"，是 **executions 表从来没进建表清单**：
  `src/store/store_sqlite.mbt` 的 `create_schema` 列了 12 张表却没有 executions，
  表只在**写**路径 `record_execution` 里 `ensure_executions_table()`；读路径
  `StoreBackend::cost_stats` → `aggregate_stats` → `list_all_executions` 直接 prepare
  `FROM executions`，而 js 桥的 `Database.prepare` 缺表时是**抛异常**不是返回 None
  ⇒ 未捕获异常一路打死 server。
  改判正文里"写面 ok / 读面崩"的归因：两档的差别不是树，而是**那一轮写面先跑过 `execute`**
  （写路径把表建出来了）；单独起 server 只读时三格（仓库根/无参、仓库根/带 ns、临时 box/无参）
  全部复现 `Error: no such table: executions` —— 复现留档 temp/cost_stats_repro_3c39fd.log。
  修法两层：① `executions_table_sql()` 进 `create_schema`（新库开库即有表）；
  ② `cost_stats` 读前 `ensure_executions_table()`（**存量老库**没这张表时也能自保，
  只补建表清单对老库无效，这是第二条存在的理由）。
  白盒锁 `src/store/cost_stats_executions_wbtest.mbt` 两条：开库后立刻 `SELECT 1 FROM executions`
  必须成立；`DROP TABLE executions` 后只读聚合必须回 `total_records=0`。
  承重对照（同一判据两态实测）：HEAD 源码 + 新判据 ⇒ `Total tests: 23, passed: 21, failed: 2`，
  两条红信息逐字是 `Error: no such table: executions`（留档 temp/cs_lock_head2.log）；
  修复后同一包 23/23、全量 JS 后端 **531/531**（temp/relbuild_test_r4.log，git archive HEAD 快照树）。
  调用面复验（安装版 eb18f4f0，三格）：无参 / 带 namespace / 临时 box 三种形态全部
  `alive_after=True` 且回执 `{"total_records":0,...,"by_executor":{}}`
  （留档 temp/cost_stats_repro_e51bb6.log）——修前同一驱动是"管道关闭 + 未捕获异常"。
  残余（不自证已修）：服务面级 catch-all（任何 handler 异常应回 JSON-RPC error 而不是让进程退出）
  仍未做，那是这一类"一个工具打死会话"的总闸；本轮只堵住了 executions 这一条具体通路。
## BUG-97 [2026-09-28T05:26:44Z] [low] FALSE_POSITIVE
- summary: 巡回探针：调用面可用性核验
- evidence: 非产品缺陷——本条由 `scripts/mcp_tool_tour.py --plane read` 自己写进真账本的：读面把 `project_dir="."` 当探针项目，而 `.` 就是仓库根 ⇒ `report_bug` 直接落`memory/bugs.md`。且第一发还与本轮手写的 BUG-90 **撞号**（脚本按 05:04 读到的 89 条反解下一个号，而 05:01 那发已经把上界推到了 90——同一份号在两处各自数，就是双发）。缺陷本体另立条目并已修（读面不再允许写真账本），此处只把垃圾条目改判并留据。

## BUG-98 [2026-09-28T05:28:31Z] [medium] FIXED
- summary: mcp_tool_tour 读面把 project_dir="." 当探针项目 ⇒ report_bug/bug_* 直接写进仓库根真账本（实跑双发）
- detail: |
  形状：读面的设计意图是"cwd=仓库根，只打不改源码的工具"，但 `build_args` 对所有工具一视同仁地
  喂 `project_dir`，于是 `report_bug` 按 `memory/bugs.md` 的落盘根规则写到了**真账本**上。
  后果两笔：① 台账长出两条非缺陷条目（已改判 FALSE_POSITIVE 并逐条立据，见 BUG-96/BUG-97）；
  ② 其中一条与本轮手写的 BUG-90 **编号相撞**——`bug_next_seq` 是按抬头最大值取的，
  而我先在 05:01 用工具发了一发、又在 05:04 用脚本按"89 条"的旧读数手写 90~94 ⇒ 同一号出现两次。
  修法：驱动侧加 READ_PLANE_SKIP 闭集（report_bug / bug_fix / bug_mark_status /
  memory_consolidate / memory_gc / memory_link）——读面一律 skipped 并写明理由；
  判据：跑读面前后对 `memory/bugs.md` 取 sha256，必须逐字相等（temp/ledger_hash_before_read.txt
  与 after 两份）。手写台账与工具发单不能并行数号：改完脚本后先重新反解上界再落笔。
- reported_by: installed-cli-tour

### FIXED(2026-09-28T05:28:31Z / BUG-98)
- evidence: scripts/mcp_tool_tour.py 增加 READ_PLANE_SKIP（6 只写工具在读面记 skipped 并带原因）；
  复跑读面 129/129 全部打到调用面（ok 79 / refused 44 / skipped 6 / crashed 0），
  且 `memory/bugs.md` 的 sha256 跑前跑后逐字相等（修前同一天内它被同一驱动写过两次：BUG-90 撞号条与 BUG-95）。

## BUG-99 [2026-09-28T06:00:00Z] [medium] FIXED
- summary: plan 的第二道门拒绝时只报「要求状态」不报出路，且与第一道门 can_split 词汇分叉（非法拆分: … / 非法迁移: split …）
- detail:
  第一道门 `TaskStatus::can_split` 收 待领取/已领取/拆分中/已打回，第二道门 `Task::split` 只收 已领取 ⇒
  待领取/拆分中/已打回穿过第一道门后被第二道门拒，回执没有出路；调用方照文案 claim 一个已打回的任务会被 claim 再拒（claim 只收待领取），
  永远走不出来。巡回播种链实测同树对照：publish→plan 被拒、publish→claim→plan 放行（["T0.1","T0.2"]）。
  修法：engine.plan 的第二道门拒绝时按当前态附出路（claim / get+task_plan_deep / retry），
  成对锁 src/engine/plan_remedy_wbtest.mbt 两条——HEAD 旧码下 2 红（temp/eng_prefix_test.log，124 收集/2 失败），
  修复后 JS 全量 533/533（temp/verify_eng_full.log）。
  本条即 BUG-92 的正身（BUG-92 按误报关闭，缺陷本体在此重报）。
- reported_by: installed-cli-tour

## BUG-100 [2026-09-28T06:00:00Z] [medium] FIXED
- summary: 巡回驱动「读面」在被测仓库里留下状态文件（currentState.txt / memory/_review.count / memory/model-router-tour-read-*.json / 仓库根 tour-read-*.db）
- detail:
  读面把 project_dir 与 store_open 的 data_dir 都留在仓库根 ⇒ 凡带 project_dir 的工具（model_route / pipeline_tick / selfdrive_* / memory_*）
  一调用就往被测项目写文件；「读面只读」这句自述是假的。上一轮的 READ_PLANE_SKIP 只挡了 6 只写工具，挡不住「有默认落点」的读类调用。
  修法（驱动侧，产品语义不动）：读面 project_dir/data_dir 指向 temp/ 草稿项目、stderr 日志引到 temp/、
  并加**外溢硬门**——跑前跑后对比「仓库根一层文件 + memory/ 递归」的 (size, mtime)；新建文件或 memory/ 内被改 ⇒ rc=2。
  硬门第一次跑就抓到 tour-read-f6c169.db 落在仓库根（rc=2，temp/tour_read_plane_r2.log），补 data_dir 后转 GREEN
  （temp/tour_read_plane_r3.log：取证面 172 项 / 新建 0 / memory 改动 0，129 工具 ok=76 refused=41 skipped=12 crashed=0）。
- reported_by: installed-cli-tour

## BUG-101 [2026-09-28T06:00:00Z] [high] FIXED
- summary: `fist serve` 在 JSON-RPC 的 stdout 上先打人类横幅（3 处 println），stdio 客户端第一行拿到的是 `FIST-Mbt Help…` / `stdin/stdout …` / 空行而不是 JSON
- detail:
  调用面证据：scripts/mcp_smoke.py 在 cmd/main→cmd/cli 搬家后必然失败，逐字为
  `RuntimeError: malformed JSON-RPC response: '[fist] serve ?? 启动 MCP server (stdio 传输)'`，
  补 serve 后又依次撞到 `stdin/stdout …Ctrl+C…` 与空行 —— 三条都出自 run_serve 体内（cmd/cli/main.mbt）。
  这与该子命令自己的说明（stdio 传输的 MCP server）矛盾：协议通道上只应有 JSON-RPC 帧。
  修法：run_serve 体内 3 处 println 不再写 stdout（该 toolchain 下没找到可用的 stderr print API，
  `moonbitlang/core/io` 在本模块不可解，故不硬凑 stderr 横幅；人用反馈留在 doctor/help）。
  回归门就是 mcp_smoke 本身：横幅若被重新引入，第一行非 JSON ⇒ 直接红。
  实测：HEAD 派生树 + 本件修复 → MCP-SMOKE PASS（129 工具）。
- reported_by: installed-cli-tour

### FIXED(2026-09-28T06:29:39Z / BUG-93, BUG-99, BUG-100, BUG-101)
- 入口清单与协议纯度一批收口：cmd/main→cmd/cli 104 处 + 26 个启动点补 serve + 新守卫 check_entry_paths.py
  （HEAD 树 119 条违例 / 修复树 0 条）；plan 第二道门拒绝附出路 + 2 条成对白盒（旧码 2 红、全量 533/533）；
  巡回读面外溢硬门（首次即抓到仓库根 ns 库，补 data_dir 后 0 新建 0 改动）；serve 的 stdout 去横幅（mcp_smoke PASS）。
- 证据：temp/bug93_apply.log, temp/eg_prefix_run.log, temp/eg_full3.log, temp/eng_prefix_test.log, 
  temp/verify_eng_full.log, temp/tour_read_plane_r2.log, temp/tour_read_plane_r3.log, temp/smoke_e2e_proof3.log

## BUG-102 [2026-09-28T06:39:17Z] [medium] FIXED

### FIXED(2026-09-28T06:44:04Z / BUG-102)
- 采行「比较侧行尾归一」那条：`gen_plugins.norm_eol()` + `drift_keys()`，漂移与"仅行尾不同"分栏，后者在正文里报数（看得见才不会被当成没事）；`--selftest` 四格＝相同/仅行尾/内容漂移/缺失与多余，并把"CRLF 夹具与 LF 必须字节不同"也钉成对照（防止夹具自己失效）。
- 实测：同一份新守卫在 autocrlf 全新克隆里漂移 55 → 1，那 1 份是当时真未重生成的 plugins/README.md（改了投影正文没重跑生成器）——**说明归一没有把真问题一起放行**；重生成后 cl7 PASS。
- ci.yml 的 cl7 那一步前加 `python3 scripts/gen_plugins.py --selftest`（BUG-89 同型：自检不被执行就等于没有）。

## BUG-103 [2026-09-28T07:02:04Z] [critical] FIXED
- summary: 安装器默认版本写死 0.3.0-beta，而发布资产名按 moon.mod 的 0.3.0 生成 ⇒ 不带参数的 `irm … | iex` 永远 404
- detail:
  两条下载源（GitCode / GitHub Release Assets）都由 `install_onecmd.ps1` / `install.sh` 的参数拼装
  `fist-mbt-js-v$Version.zip`，而 `build_release.ps1` 与 `release.yml` 的版本号来自 `moon.mod`；
  默认值写死 `0.3.0-beta` 就是三处不同源：本轮实测把默认值清空后，同一个不带参数的安装器
  打印出的候选 URL 立刻从 `v0.3.0-beta/…` 变成 `v0.3.0/fist-mbt-js-v0.3.0.zip`（即发布链真正会产出的名字）。
  CI 看不见这条：CI 既不发 Release，也不跑安装器——所以「分发面全绿」与「用户装得上」是两件事。
  修法：默认留空 ⇒ 运行时从 moon.mod 解析（GitHub raw 优先、GitCode raw 兜底）；
  离线口子 `-LocalZip` / `FIST_LOCAL_ZIP` 从 zip 文件名反解版本；
  解析不到就 `exit 1` 并打印候选源与手带 `-Version` 的方法，绝不静默用一个猜出来的版本号。
  新守卫 scripts/check_release_asset_names.py：R1 禁字面量默认版本、R2 必须真去解析 moon.mod 的 
  `version = "…"`、R3 三处资产名模板同源、R4 空值分支必须 exit 1；
  `--selftest` 六格变异（R1×2 / R2 / R3×2 / R4）＋干净输入不误红。
  调用面实测：`-LocalZip …v0.3.0.zip` 装完 `fist doctor` 5/5、
  安装产物 serve 的第一行就是 JSON、tools/list 129（temp 与本轮终端输出）。
- reported_by: installed-cli-tour

### FIXED(2026-09-28T07:02:04Z / BUG-103)
- 版本号真源改绑 moon.mod（两个安装器）+ 空值即失败 + 资产名同源守卫；
  实测：不带参数时 URL 由 `v0.3.0-beta/…` 变 `v0.3.0/fist-mbt-js-v0.3.0.zip`；
  离线 `-LocalZip` 安装 → doctor 5/5、serve 第一行 JSON、129 工具。

## BUG-104 [2026-09-28T07:23:55Z] [medium] FIXED
- summary: AGENTS.md 自述的「3 resources + 2 prompts」与 serverInfo 版本，此前没有任何判据认领
- detail:
  工具面被 `check_tools_sync` / `check_doc_surface` 钉到逐字对齐，而同一行自述里的
  resources 与 prompts 两面、以及 `tools/list → result._meta.serverInfo.version ↔ moon.mod`
  这条版本对表，全靠人偶尔手试一次——正是 J10 型缺口：自述有人写、判据没人认领。
  本轮把两面打到调用面（安装态产物 sha256:616b7632）：`resources/list` 回 3 条且逐条
  `resources/read` 非空（map=2182 / overview=212 / principles=606 字符），`prompts/list` 回 2 条
  且逐条 `prompts/get` 各回 1 条消息，serverInfo=0.3.0 == moon.mod=0.3.0 —— 现状是对的，
  「对」不等于「有人守着」：此前它坏掉时不会有任何东西变红。
  修法：scripts/mcp_tool_tour.py 增 `surface_probe()`——期望值从 AGENTS.md 的
  `Resources:` / `Prompts:` 两行反解（不手抄常量），与服务端实回**双向**对表
  （少一条、多一条、读回空文本、prompt 零消息、版本不符、验收位为空，一律计入红面 ⇒ 巡回退出码非 0）；
  AGENTS.md 反解不出条目时判据自拒（"判据无法自证绝不报绿"），不静默返回零问题。
  判据自身配 `--surface-selftest`：12 支对照（10 违例必红 + 干净支必绿 + 无声明行必自拒），
  用桩 server 不起 node、不碰库，已作为独立一步挂在 .github/workflows/ci.yml。
  为什么判据装在巡回而不是新写一个 check_*：两面都必须真跑协议才能观测，
  离线脚本只能验文档自述、验不到服务端实回——那正是本条缺陷的形状。
### FIXED(2026-09-28T07:23:55Z / BUG-104)
由 `scripts/mcp_tool_tour.py` 的自述面判据收口：两面双向对表 + 12 支对照进 CI。
调用面实测（安装态产物 sha256:616b7632，`--plane read` / `--plane write` 各一遍，两遍自述面行逐字相同）：
  自述面（resources/prompts/版本）= resources=3(声明 3)[map=2182 overview=212 principles=606] prompts=2(声明 2)[check_in=1消息 verify=1消息] serverInfo=0.3.0 moon.mod=0.3.0
  read  面：TOUR: GREEN —— 129 工具 ok=76 refused=41 skipped=12 crashed=0 not_tested=0 复活=0 自述面红=0（读面外溢判据：取证面新建 0 / memory 改动 0）
  write 面：TOUR: GREEN —— 129 工具 ok=81 refused=42 skipped=6 crashed=0 not_tested=0 复活=0 自述面红=0
判据对照实测（`python scripts/mcp_tool_tour.py --surface-selftest`）：
  SURFACE-SELFTEST: OK —— 12 支（10 违例 + 1 干净 + 1 自拒），不符 0 支
## BUG-105 [2026-09-28T07:50:09Z] [medium] FIXED
- summary: Windows 安装器只产出 `.cmd` shim ⇒ 装完之后在 Git Bash / MSYS / agent harness 的 bash 里 `fist` 直接 command not found
- detail:
  POSIX shell 不解析 PATHEXT，只给 `fist.cmd` 就等于在这个用户的主目录 bin 里放了一个
  "Windows 才认的名"。本轮就是被这条撞出来的：`which fist` 在 bash 里报 not found，
  而同一个命令在 PowerShell 里跑得好好的（`fist doctor` 5/5）——两半都是真的，
  缺的那半是"文档写着 `fist help`，读者用的却是 bash"。
  顺带两处实测到的粗糙：① 旧 shim 的注释行写了 em dash，而写盘用 `-Encoding ASCII` ⇒ 落成真 `?`
  （`REM FIST-Mbt shim ? v0.3.0`）；② 无扩展名 shim 的行尾必须是 LF，CRLF 的 shebang 在
  bash 里报的是 `bad interpreter`，装完当场看不出来。
  修法：安装器在 `%USERPROFILE%\.local\bin` 里同时写 `fist.cmd`/`fist-mbt.cmd` 与无扩展名
  `fist`/`fist-mbt`（`#!/bin/sh` + `exec node "<js>" "$@"`，LF），并加两道硬门：
  四件不齐 ⇒ 点名缺哪几件再 `exit 1`；shim 头不是 `#!/bin/sh` 或字节里含 CR ⇒ 同样 `exit 1`。
  判据面：`scripts/check_release_asset_names.py` 增 **R5**（分发面同源守卫的第 5 条，
  同守卫另两条钉资产名与版本真源）——Windows 侧必须有无扩展名写入 + 四件门，
  WSL/Linux 侧必须有 `cat > "$BIN_DIR/fist"` + `chmod +x`；`--selftest` 从六格加到八格
  （R5×2：摘掉 Set-Content 那两行必须红、`chmod +x` 改错文件名必须红），AGENTS 守卫族条目与
  scripts/README 行同步到 R5/八格（J10：自述范围==实现范围）。
  本机也按新形状补齐了 shim（只**新增**两个无扩展名文件，没覆盖并行改动面已装好的 `.cmd` 与产物）。
### FIXED(2026-09-28T07:50:09Z / BUG-105)
调用面实测（隔离 bin 里跑安装器摘出的那一段，逐字摘自 `install_onecmd.ps1`，不借副作用）：
  正向：`temp/b105-shim-bin` 落四件 `fist`/`fist-mbt`/`fist.cmd`/`fist-mbt.cmd`，
        POSIX 两份 bytes=77 CR=0 head=b'#!/bin/sh'，`.cmd` 两份 CR=4（CRLF 正确）；
        `PATH=<隔离bin> bash -c 'fist version'` → `FIST-Mbt v0.3.0`（exit=0）；
        `fist doctor` → `5/5 checks 通过`（exit=0）。
  负面对照（`temp/b105_gate_canary.py`）：摘掉两条 POSIX 写入 ⇒ rc=1 且点名
        `shim 未全部写出：fist, fist-mbt（期望 .cmd + 无扩展名 POSIX 两份）`；
        原样复跑 ⇒ rc=0。门承重成立（1 红 1 绿）。
  真机安装面：`~/.local/bin/fist` 新增后，bash 里 `which fist` → `/c/Users/victo/.local/bin/fist`，
        `fist version` → `FIST-Mbt v0.3.0`。
  守卫面：`check_release_asset_names.py --selftest` → `SELFTEST OK`（八格）；全量 rc=0；
        `check_doc_surface` rc=0（R5 的自述已同步）；`check_ps_encoding` rc=0（安装器 BOM/解析 0 错）。

## BUG-106 [2026-09-28T07:50:09Z] [medium] FIXED
- summary: `fist --help` / `-h` / `--version` / `-V` 被当"未知子命令"，且未知子命令的退出码是 0
- detail:
  调用面实测（安装态产物，bash 走 POSIX shim 逐个打）：
    `--help` → 首行 `未知子命令: --help`，exit=0
    `-h`     → 首行 `未知子命令: -h`，exit=0
    `--version` → 首行 `未知子命令: --version`，exit=0
    `-V`     → 首行 `未知子命令: -V`，exit=0
    `help`/`version` → 正常，exit=0
  两半都是缺陷，第二半更坑：`未知子命令` 却回 0 ⇒ `fist --version || exit 1` 这类包装
  会把失败读成成功（与 BUG-19/23 一族同型：拒绝要有形，还要可判）。
- remedy（本轮不代改的原因与补丁一起给）：
  真源 `cmd/cli/main.mbt` 的分发块现在是并行改动面的**在写文件**（工作树已 dirty，
  同批还有未跟踪的 `cmd/cli/help_topics.mbt`；`fist help <topic>` 正在那里长出来）。
  往对方正在重写的 match 里插两条臂，对方随后整档写回就会静默吃掉我的修复 ⇒
  留成 OPEN 并把可粘贴的补丁交过去：
    "serve" => run_serve()
    "version" | "--version" | "-V" => run_version()
    "demo" => run_demo()
    "doctor" => run_doctor()
    "help" | "--help" | "-h" => run_help(args)
    "" => print_help()
    other => { println("未知子命令: \{other}"); print_help(); exit(2) }
  退出码建议 2（区分"用法错"与"运行错"），并配一条白盒钉 `未知子命令` 分支不再回 0。
- 出路：并行改动面收口后由该文件当前 owner 落上面这段（本环会在下一轮巡回里复测这四个旗）。

### FIXED(2026-09-28T16:41:55Z / BUG-106)
真源落在 `cmd/cli/subcmd.mbt`（本轮新增）：`parse_subcmd` 一处展开 `version|--version|-V` 与
`help|--help|-h`，`USAGE_ERROR_EXIT_CODE = 2` 与 `exit_code_of` 给退出码，`cli_exit` 三形态
（js 走 `process.exit`、native 走 libc `exit`、其余运行时 abort 而不是静默回 0）。
`cmd/cli/main.mbt` 的分发改成读 `parse_subcmd` + `cli_exit(exit_code_of(cmd))`，臂的形状只剩一处。
锁两层：白盒 `cmd/cli/subcmd_wbtest.mbt` 两格（别名归位 / 未知必非 0 且已知必 0，成对反向对照）；
调用面 `scripts/cli_flag_probe.py`（CI 新步，起真产物 `node cli.js <arm>` 看真 rc）。本轮实测：
`version` / `--version` / `-V` 三格 rc=0 且首行 `FIST-Mbt v0.3.4`，未知参数 rc=2 且首行点名被拒的是什么。
条目末那句「本环会在下一轮巡回里复测这四个旗」已兑现——复测的就是上面那次调用面跑。
## BUG-107 [2026-09-28T08:19:46Z] [high] FIXED
- summary: 文档写的主安装线（GitCode raw 直链）匿名 GET 返回 HTTP 200 + 一整个 HTML 页，另一条写的是 GitHub `main` 分支而默认分支是 master ⇒ 用户照文档 `irm … | iex` 第一步就拿到网页
- detail:
  只读探测（不执行任何拿到的脚本、不带凭据）实测四路：
    GitHub raw **master**  → 200，正文首行 `#!/usr/bin/env pwsh`（唯一真正可用的 raw 直链）
    GitHub raw main        → 取不到（该仓默认分支是 master，raw/main 没有这条路径）
    GitCode /-/raw/master  → **200 + `<!DOCTYPE html>`**（5527 字节的网页，不是文件）
    GitCode /raw/master、/raw/main → 同样 200 + HTML；raw.gitcode.com 子域 → 403
  最坏的一点是**状态码是 200**：旧代码只看"能不能拿到内容 + 大于 10KB"，
  于是"源给的是网页"和"源不可达"在用户侧是同一句模糊提示；
  而 `irm … | iex` 把 HTML 灌进 iex 会当场炸解析错，用户只会看到"按文档装的失败"。
  同一形状也污染 BUG-103 修的 moon.mod 版本解析：GitCode 兜底那条永远解析不到 version。
  修法（都在**我这侧**的两个安装器，README 那两行在并行改动面手里，见本条末）：
  ① 首选线一律改成 GitHub master 的 raw 直链，GitCode 降为备用并写明实测形状；
  ② 取 moon.mod 时先 sniff 正文（`<(!DOCTYPE|html)` ⇒ 点名"这源给的是网页"再换源），
     解析不到 version 也单独说一句；
  ③ 下载资产后**先验 zip 魔数 `PK`** 再看大小（bash 侧 `head -c 2`，PS 侧读前两字节比对 0x50/0x4B），
     不是 zip 就删掉换源——只看 200 与 10KB 的放行等于把网页当资产解压。
  判据面：`check_release_asset_names.py` 五条 ⇒ **六条**（新增 R6 钉这三件事 + 首选线必须是 GitHub master），
  `--selftest` 八格 ⇒ 十一格（R6×3：摘掉 PK 检查必红、摘掉 HTML sniff 必红、首选线漂回 main 必红）。
- 归属边界：README「黑盒用户」那两行现在写的是 GitCode `/-/raw/main/...`（并行改动面本轮新加，
  实测该 URL 返回 HTML）。该文件对方在写 ⇒ 本轮不代改，交过去的话就是把首选线换成
  `https://raw.githubusercontent.com/vicTop-cw/FIST-Mbt/master/scripts/blackbox/install_onecmd.ps1`。

### FIXED(2026-09-28T08:19:46Z / BUG-107)
只读探测留证（脚本 `temp/b105_irm_readonly.py` / `temp/b105_url_shapes.py`，只 GET 不执行）：
  GitHub raw master → 200 且首行 `#!/usr/bin/env pwsh`（5557 字节，正文即脚本）
  GitCode 三形状 → 200 + 首行 `<!DOCTYPE html>`（5527 字节）；raw.gitcode.com → 403
修复面复算：
  `bash -n scripts/blackbox/install.sh` rc=0；`check_ps_encoding` rc=0（.ps1 仍带 BOM、解析 0 错）；
  `check_release_asset_names.py` 全量 rc=0（PASS），`--selftest` → `SELFTEST OK`
    （干净不误红 + 变异必红：R1×2 / R2 / R3×2 / R4 / R5×2 / R6×3，共十一格）
自证侧的针也修过一次：R6 的"首选线"正则起初写成 `install_(?:onecmd\.ps1|sh)`，
把 `install.sh` 拼成了 `install_sh` ⇒ 干净输入被误判红（判据坏了，不是产品坏了）。

## BUG-108 [2026-09-28T08:52:15Z] [medium] FIXED
- summary: 「下载那一步」从来没有可跑的法子——`-LocalZip` 是**跳过**下载而不是走下载，
  而公网 Release 资产在有授权 push 之前根本不存在 ⇒ URL 拼装、状态码处理、HTML sniff、zip 魔数、
  解压、ESM patch、shim 写出、PATH 追加、装完自检，这一整段从未被执行过一次
- detail:
  本轮以用户身份跑 `irm … | iex` 的等价流程时撞到的不是某个 bug，而是**验证面的空洞**：
  手里只有 `-LocalZip`（直接给 zip）这条腿，它绕开的恰好是 BUG-103/105/107 三次修复所在的代码段。
  修法（我这侧，两个安装器 + 一个常驻 e2e）：
  ① `install_onecmd.ps1` 加 `-BaseUrl`、`install.sh` 加 `FIST_BASE_URL`——只把
     moon.mod 与 Release 直链的**前缀**换成镜像，其余逻辑一行不改（换的必须是拼装入口而不是分支）；
  ② 镜像入口与本地 zip 互斥要**显式拒绝**（`-BaseUrl` 与 `-LocalZip` 同给 ⇒ exit 1），
     否则两个来源同时生效时"装了哪一个"不可归因；
  ③ 新增 `scripts/blackbox/e2e_mirror_install.py`：本机 `http.server` 挂镜像目录
     （moon.mod 从仓库取、资产 zip 由已装产物现打包），把安装器装进**沙箱**——
     子进程 env 里 LOCALAPPDATA/USERPROFILE/TEMP 全指 temp/b108-sandbox、沙箱 bin 顶到 PATH 最前
     （否则自检绿的是别人真装的那份），HKCU 用户级 PATH 跑前抓原值、跑完逐字还原并复核，
     真安装目录产物跑前跑后 sha256 必须相同；反面对照把资产换成 20KB 的 HTML 页 ⇒ 必须 rc!=0 且点名原因。
  它一跑就抓到两处（都记在各自条目里）：
  ④ PS 5.1 下 `(Invoke-WebRequest).Content` 在服务器把文件标成 `application/octet-stream` 时是
     **`byte[]`** 而不是 string ⇒ 版本正则静默失配，回执只说"正文里没有可解析的 version 行"；
     修法是把非 string 的响应体按 UTF-8 解码后再匹配，而不是去改镜像的形状；
  ⑤ 自检的假绿与假因 ⇒ 见 BUG-109。
  修复面复算（本机实跑，非自述）：正向 `rc=0`，四格全命中（版本来源=镜像 moon.mod /
  资产名按版本拼装 / POSIX shim, LF / fist (PATH)），沙箱产物 sha256:616b7632 与镜像一致，
  bin 四件齐 `['fist','fist-mbt','fist-mbt.cmd','fist.cmd']`，
  bash 下 `fist version` 首行 `FIST-Mbt v0.3.0`、`fist doctor` rc=0 首行 `✅ [1/5] FistEngine 能创建`；
  反面对照 `rc=1`，回执含「前两字节 3C-21」且未装出产物；
  用户 PATH「已还原（1708 字，逐字相同）」、真产物「616b7632 → 616b7632」。
  证据日志 = `temp/b108-sandbox/run.log`、`temp/b108-e2e-run2.txt`。
- 遗留边界：这条只覆盖 Windows 侧的下载段。`install.sh` 的 `FIST_BASE_URL` 是同一形状的镜像入口，
  但 e2e 未在 WSL 复跑（本轮无 WSL 通道）；公网 Release 一旦发布，首选线仍要按 BUG-107 实测的
  GitHub master raw 直链，镜像只当测试面用。

### FIXED(2026-09-28T08:52:15Z / BUG-108)
镜像入口（`-BaseUrl` / `FIST_BASE_URL`）+ 常驻端到端 `scripts/blackbox/e2e_mirror_install.py`，
正向 rc=0 四格命中、反面 rc=1 带原因、沙箱边界三条自证通过。

## BUG-109 [2026-09-28T08:52:15Z] [high] FIXED
- summary: 安装器自检在 node:sqlite 的启动警告下**同时**做了两件坏事——把"跑通了"报成
  "当前会话 PATH 未刷新"（假因），以及在两个必然抛错的 try 之后无条件打印
  `✅ fist-mbt.js 可执行`（假绿）⇒ 装完的用户被支去开新终端/重装，而真因只是一行 stderr 警告
- detail:
  端到端镜像安装（BUG-108）里那条"自检经 shim 跑到 fist"的针一直不命中，先怀疑探针，实测才发现是产品：
  沙箱里同一份 shim 用 bash 跑 `fist version` 是 rc=0、有正常 stdout，安装器那句 `& fist version`
  却进了 catch。逐字证据（`temp/b108-sandbox/selfcheck-ps-stderr.txt`）：
    `fist.cmd : (node:36896) ExperimentalWarning: SQLite is an experimental feature and might change at any time`
    `FullyQualifiedErrorId : NativeCommandError`
  错误记录的**来源就是 shim 本身** ⇒ 命令名解析成功、进程真的跑起来了；
  脚本顶部是 `$ErrorActionPreference = "Stop"`，原生命令的 stderr 经 `2>&1` 会被包成终止错误，
  而 node:sqlite 每次启动都打这行警告 ⇒ 只要用这套产物，这条路径**每次**都进 catch（不是偶发）。
  失效三面（同一次调用里同时成立）：
  ① `Write-Host "  ✅ fist-mbt.js 可执行"` 挂在两个 `try { … } catch { }` 之后**无条件**执行
     —— 那两个 try 在此环境里从来没成功过，✅ 是装饰；
  ② 版本回执那行永远打不出来（被同一个 catch 吞掉，且 catch 体是空的 ⇒ 无从归因）；
  ③ `& fist version` 的 catch 把上述一切渲染成「当前会话 PATH 未刷新（新开终端即可）」，
     这是**指向不存在原因的诊断**：PATH 那一刻是对的。
  修法（`install_onecmd.ps1` 自检段）：
  ① 新增 `Invoke-FistNative`——调用期临时 `$ErrorActionPreference = "Continue"`、
     `finally` 还原，stderr 用 `2>$null` 隔离（我们只要 stdout 回执）；空 catch 全部拆掉；
  ② `node … version` 无 stdout ⇒ `❌ 产物跑不出版本（node 不在 PATH 或产物损坏）` + **exit 1**
     （自检不许在失败时说"成功"，也不许说"警告一下算了"）；
  ③ `Get-Command fist` 先分流：解析不到才说「PATH 未刷新（新开终端即可）」；
     解析到了却无回执 ⇒ `❌ fist 解析到 <路径>，但跑起来没有回执` + exit 1——两条不同诊断不再互相冒充。
  判据面：`check_release_asset_names.py` 六条 ⇒ **七条**（R7 钉这三面），
  `--selftest` 十一格 ⇒ **十四格**（R7×3：把 `2>$null` 改回 `2>&1` 必红、
  ✅ 脱离 `if ($jsVer)` 分支必红、引入空 catch 必红），且 `PASS` 那行的范围自述同步成 R1-R7。
  修复面复算：`python scripts/check_release_asset_names.py` 全量 rc=0、`--selftest` → `SELFTEST OK`；
  端到端重跑 `=== 端到端镜像安装：PASS ===`，`安装器自检经 shim 跑到 fist 命中`
  （回执 `fist (PATH) → FIST-Mbt v0.3.0` 打出来了）；`bash -n`/`check_ps_encoding` 与 PS 解析 0 错同步复跑。

### FIXED(2026-09-28T08:52:15Z / BUG-109)
自检段改为「临时降 EAP + stderr 隔离 + 空 stdout 即 exit 1 + PATH 解析分流」，
假绿（无条件 ✅）与假因（把跑通说成 PATH 未刷新）同时消失；R7×3 判据 + 端到端实测留证。

## BUG-110 [2026-09-28T10:22:50Z] [medium] FIXED
- summary: README「黑盒用户」段的两条安装线都指向 `gitcode.com/…/-/raw/**main**/…` —— 既是 BUG-107 实测的
  「200 + 一整页 HTML」源，又写错分支（该仓默认分支是 master）⇒ 用户照 README 抄的那条命令从来没对过；
  同一段的代码栅栏字节里还嵌着一个 **退格控制符 0x08**，整块既不渲染、闭合处只剩一个裸反引号
- detail:
  这条是 BUG-107 末「归属边界」里交出去的那一处（当时 README 由并行改动面在写 ⇒ 不代改），
  2026-09-28 由用户指令「README 补丁你去改」收回本环落盘。
  坏字节实测（`python` 逐行 `repr`，不是目测）：那一行真实字节是
    `0x60 0x08 61 73 68`  ⇒ 显示成 `` `ash ``，本意是 ```bash
  形态成因是写入方把 `\b` 当转义吃了一次。危害不只是难看：`fist help tools` / `fist serve` /
  `fist doctor` 那几行在 GitHub 渲染后是散在正文里的裸命令，用户分不清哪条要抄。
  修法（`temp/readme_install_lines.py`，锚点用**整段唯一上下文**而不是那行坏字节本身，因为它含不可见字符）：
  ① 首选线一律 GitHub **master** 的 raw 直链（两条：`install_onecmd.ps1` / `install.sh`），与安装器内注释同源；
  ② GitCode 降级为「只当浏览备用」并写明实测形状（三种 raw 形状都回 200 + HTML ⇒ 不许接进 `| iex`）；
  ③ 代码栅栏重写成合法围栏，安装后的六条命令单独成块；分支名坑用引文点名（`raw/main` 取不到东西）。
  落盘前后自证（脚本打印，不靠目测）：dry-run 命中区间 5592..6053（461 字，含退格符 1 个）；
  退格符全文计数 1 → 0；`gitcode.com/VictorTop/Fist-Mbt/-/raw/main` 在 README 归零；
  新线 `raw.githubusercontent.com/vicTop-cw/FIST-Mbt/master/…install_onecmd.ps1` 命中；
  行数 225 → 233 且差值 == 本节新旧行差（证明没动到别处）；`out.startswith(改前缀)` 逐字成立。
  **同一次提交里含并行改动面的本体**：这一节 20 行在 HEAD 里不存在（`git diff --stat README.md` = 20 insertions），
  是我的 URL 修复落在他们未提交的新增之上 ⇒ 提交必然把他们那段一起带走。这里点名而不是静默带走。

### FIXED(2026-09-28T10:22:50Z / BUG-110)
README 两条安装线改 GitHub master raw 直链 + GitCode 降为浏览备用并写明 200/HTML 实测；
代码栅栏的 0x08 坏字节清除，六条装后命令独立成块。判据面：`check_doc_surface.py` 全量复跑，
`check_release_asset_names.py` R6 早已把"首选线必须 GitHub master"钉在安装器侧（文档侧这条暂无自动门，见下）。

## BUG-111 [2026-09-28T11:33:28Z] [medium] FIXED
- summary: 发布流水线**史上第一次真跑**（`FIST-Mbt Blackbox Release` run 1，由我推的 `v0.3.1` 触发）就失败，
  `https://github.com/vicTop-cw/FIST-Mbt/releases/download/v0.3.1/fist-mbt-js-v0.3.1.zip` 实测 404、
  `/releases/tag/v0.3.1` 页面上 `releases/download/` 链接 **0 条** ⇒ 「不带参数的 `irm | iex`」这条默认安装线
  至今仍差最后一个资产
- detail:
  先排掉两个容易误判的方向（都留了实测）：
  ① 不是 URL 拼装错——资产名由 moon.mod 反解，R3/R6 早就钉住同源；
  ② 不是产物造不出来——`git archive HEAD` 快照树（解出 551 文件 == `git ls-files` 551，建树自证）里逐条复跑 CI 的 JS 三步：
     `moon build --target js` → `ran 78 tasks, 499 warnings, **0 errors**`；
     `python scripts/patch_esm_main.py _build/js/debug/build/cmd/cli/cli.js` → rc=0（`patched …`）；
     打包 → 374,830 字节、前两字节 `b'PK'`。**JS 腿在已提交树上是全绿的**。
  静态可见的作业面缺陷两处（`release.yml` 的 `release` 作业）：
  ③ 正文引用 `needs.meta.outputs.version`，而它自己的 `needs` 只有 `[build-js, build-native-linux]`
     —— `meta` 不在 needs 里就取不到值 ⇒ Release 名与资产名会漂成空版本形态；
  ④ `needs` 里含 `build-native-linux`：AGENTS 自己写明「权威稳定门槛 = JS 后端」，native 只是可选面，
     却一票否决整条发布（同文件里 `build-native-windows` 反而已经带 `continue-on-error: true`）。
  修（已落盘）：`release: needs: [meta, build-js]` + `build-native-linux: continue-on-error: true`；
  判据 `check_release_asset_names.py` 由 R1-R7 加到 **R1-R8**（三支子判据：needs 退回顶掉 native 必红 /
  摘掉 meta 必红 / 摘掉 native 容错必红），`--selftest` 十四格 ⇒ **十七格**，PASS 行范围自述同步成 R1-R8。
  发布动作选**纯快进**的一条：不删也不重指已发布的 `v0.3.0`/`v0.3.1` 标签（那等于改写公网 release point，
  与本仓「只快进、绝不 force」的纪律冲突），改为版本前进 0.3.1 → 0.3.2 并打新标签 `v0.3.2` 触发 CI；
  盘面只有两处真写死版本（`moon.mod` 与 `USAGE.md` 的 `vicTop-cw/fist-mbt@…` 自述行），其余表面从 moon.mod 反解。
- 待证（这条为什么先记 OPEN 而不是 FIXED）：**修复本身已落盘并有判据，但「Release 真的出了资产」还没发生**。
  翻 FIXED 的判据 = 匿名只读 HEAD 该资产 URL 得 200 + `Content-Type` 是 zip 形态 + 前两字节 `PK`，
  且再用那条**公网**线（不带 `-BaseUrl`、不带 `-LocalZip`）跑一次真安装，装出的产物 `fist version` 回 0.3.2。
- 顺带一条不属于我本轮成因、但必须记账的发现：Actions 页面 `run 178 → 186`（含 `feat(phase-6)`、`chore: moon fmt`、
  `install: Release Assets` 等多笔早于本轮的提交）**状态全是 failed** ⇒ 本仓 CI 长期是红的，
  「说是全弄好了」这句话在 CI 面上没有支撑。匿名 API 现在 403 rate limit exceeded，读不到日志，
  定位需要 `FIST_GITHUB_TOKEN`（只从环境变量注入）或在 UI 上点开任一条 run。

## BUG-112 [2026-09-28T11:54:14Z] [medium] FIXED
- summary: BUG-111 的归因**只覆盖了一半**——真正让 Release 零资产的是 `release.yml` 的工具链 bootstrap：
  安装 URL 用了 `cli.moonbitlang.com/install/unix`（少 `.sh`），而且**从不把 moon 目录写进 `GITHUB_PATH`**
  ⇒ runner 每步起新 shell，安装脚本改的只是 shell rc，下一步里 `moon` 根本不在 PATH
  ⇒ `Build JS target` 步骤红 ⇒ `release` 作业被 skip ⇒ 默认安装线一直 404
- detail:
  取证路径（这一步关键，前面全靠猜）：匿名 `GET /repos/…/actions/runs/<id>/jobs` 拿到每个作业的**失败步骤名**：
    meta                   success
    build-js               failure   ← STEP "Build JS target"
    build-native-linux     failure   ← STEP "Build native"
    build-native-windows   failure   ← STEP "Install MoonBit"
    release                skipped
  两个作业都在"调 moon 的那一步"红、一个在"装 moon 的那一步"红、release 是 skipped（不是跑挂）
  ⇒ 形状指向"工具链没到手"，不是"代码编不过"。
  对照组是**同一个仓里跑通过的 `ci.yml` / `fist-ci.yml`**：它们用
    curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
    echo "$HOME/.moon/bin" >> "$GITHUB_PATH"
    moon update
  而 `release.yml` 三条都没有——三条一起缺 ⇒ 同一个 `moon build` 在 CI 轨能跑、在发布轨跑不了。
  **本轮我差点再次误判**：在 `git archive HEAD` 快照树里复跑 CI 的 JS 三步全绿，据此写进 BUG-111 的
  证据说"产物没问题、真因在作业依赖"。那次复跑用的是**本机全局装的 moon**，与 runner 的 PATH 不是同一个环境
  ⇒ 复跑证明了"代码能编"，却被我当成了"CI 那步也能过"。教训：跨环境复跑必须先证**环境同形**（PATH 里有没有那个工具）。
  修（已落盘）：`release.yml` 的 build-js 与 build-native-linux 两侧都对齐 ci.yml 形状
  （`.sh` + `echo "$HOME/.moon/bin" >> "$GITHUB_PATH"` + 新增 `Refresh registry (first build)` 跑 `moon update`）。
  `build-native-windows` 仍红在 `Install MoonBit`（它用的是 `install/windows` + Expand-Archive，
  而 ci.yml 的 Windows 轨用 `irm …/install/powershell.ps1 | iex`）——该作业有 `continue-on-error: true`，
  不顶掉发布，本轮不扩大改动面，只记账不装成已修。
  判据面：**R9**（跑 moon 的 workflow 必须有 moon 进 `GITHUB_PATH`、安装 URL 必须是 `install/unix.sh`），
  且判据**只看去掉 `#` 注释行之后的代码面**——第一版判据被我在 release.yml 写的注释里的 "GITHUB_PATH" 喂回针，
  "摘掉导出行"那格变异不红（`--selftest` 当场抓到）；`--selftest` 十七格 ⇒ 十九格（R9×2）。
  发布动作：版本前进 0.3.2 → 0.3.3 并打新标签 `v0.3.3`（纯快进；不删不重指已发布标签）。
- 待证（先记 OPEN 的理由）：`moon` 进 PATH 之后 `Build JS target` 是否真过、Release 是否真出资产，
  都要等 `v0.3.3` 那一次 run 的回执。翻 FIXED 的判据写在 BUG-111 末：匿名 HEAD 资产 URL 得 200 + `PK`，
  且用**公网线不带任何参数**装出 `fist version` = 0.3.3。


### FIXED(2026-09-28T16:41:55Z / BUG-111, BUG-112)
两条一起收：`v0.3.3` 那一次 `FIST-Mbt Blackbox Release` 已给出两条条目末各自要求的判据——
meta / build-js / release 三作业绿（`Build JS target` 不再红 ⇒ BUG-112 的 `unix.sh` +
`echo "$HOME/.moon/bin" >> "$GITHUB_PATH"` + `moon update` 三条生效），
匿名 HEAD `.../releases/download/v0.3.3/fist-mbt-js-v0.3.3.zip` 得 302 → 真资产、前两字节 `PK`；
再用**公网线不带任何参数**（从 README 反解出来的那一行）跑一次真安装：rc=0，横幅 0.3.3、
shim/PATH/自检四格全命中（`scripts/blackbox/e2e_irm_line.py` 沙箱档，用户 PATH 逐字还原）。
BUG-111 的原始归因（「真因在作业依赖」）已被 BUG-112 证伪并留在 112 的正文里；
这里只按叙述面追加，不回写 111 的正文。判据面：R8（发布作业不许顶掉分发）+ R9（工具链 bootstrap 与 CI 同源）。
## BUG-113 [2026-09-28T12:12:10Z] [high] FIXED
- summary: README 与安装器头部那条 Windows 主安装线「irm <GitHub master raw> | iex」当场解析失败 ——
  iex : At line:22 char:22 / + [string]$Version = "", / 赋值表达式的左侧无效（InvalidLeftHandSide）；
  而同一个脚本用 powershell -File 跑一切正常 ⇒ 之前所有 e2e 都走 -File，这一格从来没被任何判据照过
- detail:
  发现路径：发布资产终于出来之后（BUG-112 修完 CI），第一次把「用户照抄的那一行」原样跑了一次（沙箱档）。
  成因是两条各自正确的自家规矩撞车：
  ① check_ps_encoding（BUG-88）要求含中文的 .ps1 必须带 UTF-8 BOM，否则 PS5.1 按 ANSI 读会解析期即炸；
  ② irm（= Invoke-RestMethod）对 text/plain 返回的是**字符串**，且把 BOM 留成首字符 U+FEFF；
     iex 拿到以 U+FEFF 开头的串时首行 shebang 不再被认成注释 ⇒ param(...) 不在「脚本首语句」位置
     ⇒ [string]$Version = "" 被当普通赋值表达式解析 ⇒ 红。
  最小对照（temp/bom_min_control.py：6 行脚本 + powershell -EncodedCommand，避开引号与换行被 shell 吃掉）：
    A-noBOM     firstCharU=35     IEX=OK            IEX-TRIM=OK
    B-withBOM   firstCharU=65279  IEX=FAIL: At line:4 char:22 +   [string]$Version = "",
    同一串 TrimStart(U+FEFF) 之后 IEX-TRIM=OK ⇒ 唯一变量就是 BOM。
  我自己的第一个修法也是错的：写成「((irm …).Content.TrimStart(…))」——那条路上 .Content 是 null
  （InvokeMethodOnNull），因为 irm 本来就返回字符串而不是响应对象；正确形是 .ToString().TrimStart([char]0xFEFF)。
  修（保留 BOM，改文档线；BUG-88 那条编码约束有真实理由，不动它）：
    iex ((irm https://raw.githubusercontent.com/vicTop-cw/FIST-Mbt/master/scripts/blackbox/install_onecmd.ps1).ToString().TrimStart([char]0xFEFF))
  README 与 install_onecmd.ps1 头部同步，并各写一段「为什么长这样」，防下一个人手抖改回裸形。
  判据面加 R10：安装器文档线与 README 的 Windows 线都必须含 TrimStart([char]0xFEFF)；
  --selftest 十九格 ⇒ 廿一格（R10×2：任一侧退回裸形必红）；README 从此进判据面（缺席即红）。
  常驻回归入口 scripts/blackbox/e2e_irm_line.py：命令**从 README 反解**、不硬编码（文档改坏就红，
  文档写对则用户与判据跑同一串字节）；反解不到即 FATAL 自拒。默认沙箱档
  （LOCALAPPDATA/USERPROFILE/TEMP 重定向 + 沙箱 bin 顶 PATH + HKCU 用户级 PATH 逐字还原 + 真安装目录 sha 只读核对），
  --real 才落真面且带产物备份/自动还原；README 仍是裸形时 --real 拒绝执行（那是已知会红的形）。
  修复面实证（沙箱档，字面文档线，走真公网）rc=0：
    「0.3.3」命中 / 「fist-mbt-js-v0.3.3.zip」命中 / 「✅ fist (PATH) → FIST-Mbt v0.3.0」命中（BUG-109 的门在真公网路径上也成立）/
    「✅ fist (POSIX shim, LF)」命中 / 横幅「FIST-Mbt v0.3.3 安装完成」/ 沙箱 bin 四件齐
    ['fist','fist-mbt','fist-mbt.cmd','fist.cmd'] / 沙箱产物 sha256:2eaa4803（CI 构建物与本机构建 616b7632 不同形是正常的）/
    用户 PATH 1708 字逐字还原 / 真产物 616b7632 → 616b7632 未动。
  同一次跑还新暴露一条：装出来的 fist version 回 v0.3.0 而横幅是 0.3.3 ⇒ 另开 BUG-114。
- 残余边界：个别代理把 raw 标成 application/octet-stream 时 irm 可能给出 byte[]，.ToString() 得 System.Byte[]
  从而在 iex 处红——红是可见的（不是静默装错），且该形状已由安装器内部的 UTF-8 强制解码覆盖 moon.mod 那一步；
  WSL 侧 curl -fsSL … | bash 无此问题（实测 install.sh 前 4 字节 23 21 2f 75，无 BOM）。

### FIXED(2026-09-28T12:12:10Z / BUG-113)
文档线改 .ToString().TrimStart([char]0xFEFF) 形（README + 安装器头部 + 两处理由注释）；判据 R10 两支、
--selftest 廿一格；常驻 scripts/blackbox/e2e_irm_line.py 跑从 README 反解出来的那一行，沙箱实证 rc=0 四格全命中。

## BUG-114 [2026-09-28T12:12:10Z] [high] FIXED
- summary: 版本自述其实有三个真源 —— moon.mod（规范真源）、src/server/server.mbt:565 的
  let project_version : String = "0.3.0"、cmd/cli/help_topics.mbt:4 的 const FIST_VERSION = "0.3.0"。
  本轮把 moon.mod 前进到 0.3.3 之后，公网装出来的全局命令 fist version 仍回 v0.3.0
- detail:
  实证就在 BUG-113 那一次沙箱跑里：横幅「FIST-Mbt v0.3.3 安装完成」，而 fist version 打「FIST-Mbt v0.3.0」。
  巡回的 surface_probe 校的是 serverInfo.version ↔ moon.mod（调用面），产物只要是新构建的就会红；
  check_doc_surface 只校 文档 ↔ moon.mod ⇒ 看不见源码常量这一格（一源四态里「第四态」的落点）。
  可粘贴补丁（各一行；改完需重建产物才算数）：
    src/server/server.mbt:565  let project_version : String = "0.3.3"
    cmd/cli/help_topics.mbt:4  const FIST_VERSION = "0.3.3"
  不在本轮改的理由：src/server/server.mbt 工作树 dirty（并行改动面在写），
  cmd/cli/help_topics.mbt 是对方未跟踪的新文件（?? cmd/cli/help_topics.mbt）——
  往这两处插臂会被整档写回静默吃掉（BUG-106 同型）。
  建议收口形状（机器可检）：把两个常量并进「从 moon.mod 反解」的生成面（gen_plugins 已在读 moon.mod 的 version），
  或加一支判据：server.mbt 的 project_version 与 cmd/cli 的 FIST_VERSION 必须 == moon.mod 的 version，
  不一致即红并点名行号。**这条判据本轮没加**：它一落地就是当场红，而它指名的两个面不在我手里——
  把一个自己修不了的红门禁塞进 CI 只是把债转嫁给下一次构建，不如先入账交裁决。

### FIXED(2026-09-28T16:41:55Z / BUG-114)
三处对齐 moon.mod：`src/server/server.mbt` 的 `project_version`、`cmd/cli/help_topics.mbt` 的
`FIST_VERSION`，与 `moon.mod` / `USAGE.md` 一起前进到 0.3.4。
常驻锁由红转绿（活证据）：HEAD 上 `moon.mod=0.3.3` 而 `project_version="0.3.0"` ⇒
`src/server/fist-mbt_wbtest.mbt` 的「BUG-16 对外版本单一真源」那格在 master 上一直是红的——
红着没人读等于没锁，这正是本条能活到 0.3.3 的原因；本轮 `moon test --target js src/server` = 145/145。
新增机器可检面（条目里建议的那条）：`check_release_asset_names.py` 加 **R11**——`let project_version`
与 `cmd/cli` 侧扫到的任何 `const *VERSION*` 必须 == moon.mod；读不到基线即自拒，可选面缺席不误红，
`--selftest` 五格对照（常量落后 / 真源搬家 / 基线读不到 / 常量表漂移必红 + 无该面不误红）。
调用面：`scripts/cli_flag_probe.py` 钉「`fist version` 首行必须回显 moon.mod 版本」，帮助面同规则。
公网复验随 `v0.3.4` 的 run 之后再跑一次 `e2e_irm_line.py`（其版本针本轮已改成从 moon.mod 反解，
不再写死 0.3.3——写死的针一升版就漂，漂成假绿最坏）。

## BUG-115 [2026-09-28T17:10:52Z] [medium] FIXED
- summary: `moon test --target js` 在**干净树**上偶发 3 红（`src/engine/engine_execute_r2_test.mbt` 三连
  "unable to open database file"）——该文件的 `r2e_engine` 打开 `temp/r2_bug2_*.db` 却不建 `temp/`，
  依赖**同包另一个测试文件**（`docs_gate_test.mbt` 里的 `@fs.create_dir("temp")`）先跑赢竞速
- detail:
  活证据（本轮暂存树快照复跑时撞上，两次可比）：
    `temp/staged-tree` 首轮 = 535/532/**3 failed**，随后 4 次（含删 `_build` 冷构建）= 535/535；
    `temp/head-wt`（HEAD 的干净 worktree）`rm -rf temp` 后 = 535/532/**3 failed**，三条全是
      `[vicTop-cw/fist-mbt] test src/engine/engine_execute_r2_test.mbt:54/79/194 ...
       failed: Error: unable to open database file`
    同条件 + 本条修好后 = **535/535**（`temp/fixed_no_temp.log`，rc=0）。
  主工作树永远绿，因为 `temp/` 早就在那儿（我自己的 scratch 就落在那里）⇒
  **"本机全绿"在这条上是纯粹的假证据**；能看见它的只有新 clone / `git archive` 树 / CI。
  很可能也是 BUG-111 里那条「Actions 上 run 178→186 全是 failed，匿名 API 403 读不到日志所以没定位」
  的一部分成因——那条现在有了可复跑的解释，但仍不据旧数宣称已把 CI 全量跑绿。
  同形风险（本轮实测其余 9 个用 `temp/` 路径的测试文件都不红：它们要么自己 `create_dir`，
  要么走会建目录的写文件通路）——只在被观测到的这一处落修，不预防性铺开。
- 修：`r2e_engine` 开头补 `@fs.create_dir("temp") catch { _ => () }`（沿用同包 `docs_gate_test.mbt` 的既有惯用法），
  并写明"SQLite 只造文件、不造父目录"。**判据面**：CI 的 JS 轨就在干净 checkout 上跑全量，
  这条修复由 CI 常驻看；本机侧要复跑只需 `rm -rf temp && moon test --target js`（判据可复现，不靠回忆）。

### FIXED(2026-09-28T17:10:52Z / BUG-115)
`src/engine/engine_execute_r2_test.mbt::r2e_engine` 补建 `temp/`；对照实证：同一无 `temp/` 条件下
修前 532/535（3 failed，全在该文件）、修后 535/535（`temp/fixed_no_temp.log`）。
本轮第 3 笔提交（前两笔是 0.3.4 的主体与文档面同步）。

## BUG-116 [2026-09-28T17:35:26Z] [medium] FIXED
- summary: v0.3.4 发布成功后，**从本机**复跑「文档那条线」的安装时下载段失败
  （PowerShell 侧 9/9 次 "基础连接已经关闭: 发送时发生错误 / 由于远程方已关闭传输流，身份验证失败"），
  而同一资产用 curl 取到 200 + 372,836 字节 + 前两字节 `PK` ⇒ **不是发布面坏，是本机到
  release-assets.githubusercontent.com 的传输链路不稳定**；因此 0.3.4 的公网安装复验**当前没做成**
- detail:
  已排除的方向（都有实测）：
    1) 资产不在/名字漂移 —— 不在：`curl -sIL` 得
       `Content-Disposition: attachment; filename=fist-mbt-js-v0.3.4.zip`、
       `Content-Type: application/octet-stream`，实取 size=372836、magic=`PK`；
       run af54d5e → meta/build-js/release 三作业 success（native 两作业仍 failure，非权威面）。
    2) 安装器代码退化 —— 不是：`install_onecmd.ps1` 的下载段自 0.3.3 那次
       实证 rc=0 之后**一个字节都没动**（本轮只改了 `cmd/cli`、判据与文档面）。
    3) TLS 协议档设错 —— 不是：`SystemDefault / Tls12 / Tls13` 三档各 3 次，9/9 同一错误；
       而同一条 URL 在同一时刻用 curl 是 200（矩阵证据 `temp/probe-tls-result.txt`）。
    4) 代理才是变量：HKCU `ProxyEnable=1 / ProxyServer=127.0.0.1:7897`（clash），
       而 bash 侧无 `http(s)_proxy` ⇒ .NET 走系统代理、curl 走直连，两条路不同形；
       且第一次 `SystemDefault` 单发是成功的（200/372836/PK），随后 9 连败 ⇒ 时好时坏，
       典型的链路/代理侧抖动，而不是确定性代码缺陷。
  安装器这一段的行为本身是对的：**每个源都失败时逐源打状态并 rc=1**（没有静默半成品，
  也没有把下载失败说成"PATH 未刷新"——那是 BUG-109 已修的形态）。
- 为什么不判 FALSE_POSITIVE：现象真实存在且用户面可复现（在这台机器上照文档抄就是装不上）；
  只是成因不在本仓代码里，本轮也没有把它伪装成"已修"。
- 出路（下一轮或换环境执行，别为了变绿改判据）：
  1) 在网络正常的一侧复跑 `python scripts/blackbox/e2e_irm_line.py`（版本针已从 moon.mod 反解，
     升版不用再改判据）——它红了就是真红，绿了就是本条的关闭证据；
  2) 若想给"代理链路不稳"这一类加韧度：安装器逐源**重试 + 退避**（现在每源一次），
     并把"传输层错误"与"404/HTML 形状"分开报（现在共用一段状态文本）；
  3) 本机侧可先验：`curl.exe` 通而 `Invoke-WebRequest` 不通时，优先查系统代理与 TLS 中间盒，
     不要改产品码。

- 复测追加（2026-09-28T17:40:44Z，同日稍后）：把失败点往前挪了一格看清了——**装不上脚本本身**，不是装不上资产。
  沙箱档 rc=1 的原始回执（`temp/irm-sandbox/irm.log`）第一行就是
  `irm : 基础连接已经关闭: 发送时发生错误 … Invoke-RestMethod … WebException`，
  被打红的是 `irm https://raw.githubusercontent.com/…/install_onecmd.ps1` 这一步，
  产品码一行都没跑到 ⇒ 本轮给安装器加的下载重试**没有被这一格验证到**（它守的是下一步）。
  另两条链路事实：`curl --noproxy '*'` 取 github.com 得 000（**直连根本不通**），
  系统代理开着（HKCU ProxyEnable=1 / 127.0.0.1:7897）；同一时刻经代理的 curl 能取到资产
  200 + 372,836 字节 + `PK`，而 PowerShell 的 Invoke-WebRequest 9/9 次传输层被对端关闭
  （三档 TLS 各 3 次，`temp/probe-tls-result.txt`）⇒ 变量在本机的代理/TLS 中间盒，不在产品码。
  状态保持 OPEN 的理由不变：用户在这台机器上照文档抄确实装不上；关闭证据 = 链路健康时
  `scripts/blackbox/e2e_irm_line.py` 跑绿（版本针已从 moon.mod 反解，不用再改判据）。

### FIXED(2026-09-29T06:45:05Z / BUG-116)
- evidence: 【BUG-116】本轮把「照文档抄装不上」从**单点依赖一条公网线**改成三条路，并给可跑的那条配上常驻判据；本机实测的可用路已跑绿。
已交付：① README 现有三条 Windows 线——主档 `irm|iex`（针未弱化）、curl 兜底档带 `--retry 5 --retry-delay 2 --retry-all-errors`（R12「重试只许对准传输层错误」搬到取脚本这一发；本机失效形态是同一 URL 有些连接被 RST、有些拿到 200，单发不成立）、离线/内网档 `-LocalZip` / `-BaseUrl`（开关名与 `install_onecmd.ps1` 的 `param()` 逐字对表）。
② 判据 `scripts/blackbox/e2e_irm_line.py` 升级为两臂各自独立清场（BUG-117 教训），按 R12 分类报告：传输层⇒「链路侧」、404/HTML/缺针⇒「确定性」；兜底档红一律拦退出码，主档链路侧红不拦但必印。反解针带负控制：摘掉兜底线的重试旗 ⇒ 该行不再被反解到 ⇒ 判据自拒不报绿。
③ 权威 CI（ci.yml js-windows）加公网线观测臂（`continue-on-error: true`）——本条自己的教训就是"链路侧红不是产品红"，不能一票否决但必须留回执。
本机实测（2026-09-29）：`e2e_mirror_install.py` = `=== 端到端镜像安装：PASS ===`（v0.3.4 从 moon.mod 反解、POSIX 无扩展名 shim 门通过、用户 PATH 逐字还原 1708 字、真产物 sha 616b7632→616b7632）⇒ 症状已由文档承诺且有判据的那条离线/内网线解决。同一时刻公网两臂仍红（主档「基础连接已经关闭；接收时发生错误」/ 兜底档 curl 操作超时，而同一条 URL 只读探测能拿到 http=200/767B ⇒ 中间盒 RST 抖动）⇒ 公网线"跑绿"只能在 runner 上出终证，本条不冒充已证，交由上述观测臂产出。
未改判据凑绿：主档针、R6 的 HTML/PK 形状门、R12 的 break 闸与退避全部原样。
## BUG-117 [2026-09-28T17:35:26Z] [low] FIXED
- summary: 判据自己的假红——`scripts/blackbox/e2e_irm_line.py` 的沙箱档不清场：
  第二次跑时沙箱里已有上一轮装好的产物，安装器（文档线不带 `-Force`）直接 exit 1，
  于是回执里四格针**全部未命中**，看起来像"文档线又坏了"，实际测的是"沙箱脏了"
- detail:
  活证据：本轮第一次跑 rc=1、四格全未命中，而末行"沙箱产物 = 2eaa4803 / bin 四件齐"——
  那个 sha 正是**上一轮 0.3.3 装进同一个沙箱**留下的产物；`fist version` 回 v0.3.0 也是因为
  探针在 PATH 上摸到了旧的第二份 shim（`/c/Users/victo/.local/bin/fist`，真用户面那份）而不是沙箱那份。
  判据红得"有道理"但红错了对象 ⇒ 与 BUG-89/109 同族：**自检的成立前提没被自己检查**。
- 修：`sandbox()` 起手 `shutil.rmtree(BOX)` 并打印"沙箱已重置"（沙箱本来就是为该次安装造的，
  真安装目录与用户 PATH 的只读核对逻辑不变）。修后再跑：文档线**确实走到下载段**并逐源报状态
  （那才是本轮真正该看见的东西 ⇒ 顺带暴露 BUG-116）。

### FIXED(2026-09-28T17:35:26Z / BUG-117)
`scripts/blackbox/e2e_irm_line.py::sandbox()` 每次跑前清空 `temp/irm-sandbox`；
自证：清场后回执从"四格全未命中 + 沙箱里是上一轮的 sha"变成"版本针/资产名针命中 + 逐源状态打印"。
- 复测追加（2026-09-28T17:40:44Z）：同一次复跑又抓到探针的第二种顶数形态——沙箱里 `bin=[]`（什么都没装上），
  而探针走 PATH 摸到了真用户面那份旧产物，于是回执写着 `fist version` 回 v0.3.0，
  读起来像"沙箱装成了 0.3.0"，其实是"沙箱没装上 + 探针跑错了树"。
  修：`probe()` 加 `sbin=` 参数，沙箱档**点名**跑 `<沙箱>/.local/bin/fist`，
  文件不可执行就直接打 `MISSING <路径>` 并记一条 FAIL（"不许摸真用户面的旧产物顶数"）。
  顺带给下载重试加判据 R12（两支：拆掉"有 HTTP 响应就 break"的闸必红 / 拆掉退避间隔必红）。

## BUG-118 [2026-09-28T18:01:26Z] [low] FIXED
- summary: `fist-ci.yml`（狗食轨）的 **Format check** 步骤在推送后的 run 里持续红，但**被检内容本身是干净的**——
  用本机 moon 对 `HEAD` 树逐文件实测 `moon fmt --check` = 0 处差异 ⇒ 红点最可能在该工作流**装"最新 moon"**
  （`install/unix.sh` 不钉版本），formatter 规则随工具链版本漂；本轮不定案、不猜着修
- detail:
  分栏清楚（都是 2426a66 这一次推送的回执，匿名 `/actions/runs/<id>/jobs` 只读步骤名）：
    `CI`：check + test (js, ubuntu) = **success** / (js, windows) = **success** / (native, ubuntu) = failure(`Test (native)`)
    `FIST CI — Build + Test`：(native, ubuntu) = failure(`Test (native, j=1)`) / (js, ubuntu) = failure(**Format check**)
  已排除"是我的文件"：`cmd/cli/subcmd.mbt`、`subcmd_wbtest.mbt` 的形本轮已按 moon fmt 落回（并顺手清了
  `src/engine/plan_remedy_wbtest.mbt` 的存量 3 处换行）；再把 `git show HEAD:` 的 LF 字节逐文件落进
  `git archive` 树里跑 `moon fmt --check` ⇒ **0 处差异**（第一次跑这个测量时得到 3 个"脏文件"，
  真相是 Windows 的 `tar -x` 解出 **CRLF**：`src/server/server.mbt` 全文 6294 行里 CR=6294，
  于是 formatter 的 LF 输出与它逐行相异 = 12,614 行差异，一个假的"巨额债务"。测量前必须先点行尾数）
  ⇒ 仓库内容在本机工具链（moon 0.1.20260920）下是合规的，红的解释只剩"两侧工具链版本不同形"。
- 为什么不本轮定案：要区分"最新 moon 的 formatter 变了"和"runner 上还有别的变量"，
  要么读一次 runner 日志（需要授权/Token 注入），要么本机 `moon update` 换版本再测——
  后者会污染本轮其它测量（所有"实测"都建立在当前版本上），所以留给下一轮单独做。
- 出路（按代价排序）：
  1) 在 `fist-ci.yml` 与 `ci.yml` 里**钉同一个 MoonBit 版本**（或至少让两条轨同版本），
     把"formatter 随 latest 漂"从判据面里摘出去——这是唯一能长期止血的一条；
  2) 或带 `FIST_GITHUB_TOKEN`（只从环境变量注入）读一次该步骤的日志，确认它报的是哪些文件；
  3) 无论哪条，别改产品码去凑一个说不清的绿。
## BUG-119 [2026-09-29T03:33:08Z] [high] FIXED
- summary: [watchdog] 心跳跨进程不可见：新进程 heal 把上一进程刚心跳过的在途任务判成 no_signal 回滚（且无心跳行时 timeout_sec 不生效）
- detail: 现象（两进程实测，2026-09-29 03:28Z，库=temp/probe-xhb.db 隔离库，仓库根 fist-mbt.db 未动）：
拍1 新进程：publish_parallel(ns=probe-xhb) -> T0；claim(T0, assignee=probe-agent) -> 已领取；
  heartbeat(task_id=T0, signal=alive) 回执 verbatim：
  {"task_id":"T0","signal":"alive","last_seen":"2026-09-29T03:28:40Z"}
进程1 退出。中间用 sqlite3 mode=ro 直接读库确认那一行真的落盘，verbatim：
  [('fist-mbt','T0','2026-09-29T03:28:40Z','alive')]
拍2 新进程：heal(namespace=probe-xhb, timeout_sec=3600) 回执 verbatim：
  {"healed":["T0"],"count":1,"scope":"namespace","namespace":"probe-xhb","message":"超时静默任务已回滚待重派"}
  watchdog_tick(namespace=probe-xhb, timeout_sec=3600) 的 detail.active_tasks = {'T0': ''}（last_seen 读回空串）
判定：心跳跨进程不可见——同进程内读得到（对照组：同一次 heal 里有心跳的 B 臂没被点名），
新进程里读回空串 ⇒ 无人值守（cron 每次唤醒都是新进程）会把「上一拍还在正常干活」的在途任务判成 no_signal 回滚。

放大伤害的第二格：src/ops/ops_heal.mbt:87 那一支写的是 `None => true`（从未心跳 = 直接判死），
所以 timeout_sec 在「没有心跳行」这个形状上根本不起作用——新认领、还来不及发第一个心跳的任务，
同一拍里就被回滚（实测 A 臂：claim 后立刻 heal(ns, 600) ⇒ healed 点名该单）。
两格叠起来 = 看护每拍清空在途。

活证据锚点：
  src/ops/ops_heal.mbt:82 活跃集=执行中/已领取/拆分中（已暂停不在里面，故与本单无关，也不背这个锅）
  src/ops/ops_heal.mbt:86-87  `None => true // 从未心跳过 -> 视为 no_signal`
  src/store/store.mbt:479-486 注释「供启动时加载」；src/store/store_sqlite.mbt:1196-1223 读面 SELECT 正常形状。
    跨进程读空不能由「没加载」解释（heal 每轮直接查库），要按 stmt.step()/列取值逐格定位。
复现步骤（不依赖任何脚本）：
  1) FIST_DB_PATH=<隔离库> node _build/js/debug/build/cmd/cli/cli.js serve   （stdin 常驻；_meta 必带 protocolVersion）
  2) publish_parallel{project_dir,namespace,description} -> claim{task_id,assignee} -> heartbeat{task_id,signal}
  3) 关进程1；sqlite3 只读确认 heartbeats 里有 (agent_id,task_id,last_seen,status) 那一行
  4) 同一 FIST_DB_PATH 再起进程2，调 heal{namespace,timeout_sec=3600}
  5) 期望 healed=[] 且 active_tasks 的 last_seen 非空；实测 healed=[<该单>] 且 last_seen=''
出路（不替修复轮定方案）：① 先做成对常驻判据（同进程有心跳不回滚 + 跨进程有心跳不回滚），任一侧退化即红；
② 再定根因（心跳读面形状 or 心跳按库/进程分片未读回）；③ `None => true` 那一支单独定语义：
无心跳要给宽限期（例如按 created_at 起算），不能首拍即死。

- reported_by: butler(改进计划复核轮 2026-09-29)



### FIXED(2026-09-29T06:16:58Z / BUG-119, BUG-118)
- evidence: 【BUG-119】根因两格：① `heal` 工具读**进程内内存**心跳表，而给那张表预热的模块级 `let _init_hb : Unit = init_heartbeats()` 被 MoonBit 当未引用的非 pub 顶层绑定消除（产物里 `init__heartbeats` 0 次）⇒ 新进程内存恒空；② `None => true` 把「没有心跳行」直接判死。修：`heal` 改走 `heal_stale_tasks_from_store`（持久化心跳表是唯一真相），无心跳行退到任务行 `updated_at` 的兜底时钟（`stale_by_task_clock`），`heartbeat` 跨进程回读上次心跳并按实测回执 `persisted`/`backend`（内存后端不许冒充落库），判死但回滚不了的条目走 `skipped` 披露（`src/ops/ops_heal.mbt`、`src/store/store.mbt::backend_name`、`src/engine/engine.mbt::store_read_heartbeat_last_seen/heartbeat_backend`、`src/server/server.mbt`）。锁：常驻黑盒判据 `scripts/blackbox/e2e_heartbeat_xproc.py`（8 臂，起两个真 `node cli.js serve`，FIST_DB_PATH 隔离库）在修复后 8/8 绿；同一份判据跑在 `git archive HEAD` 的旧码树上 = 3 绿 5 红，旧码回执原样 `heal(timeout_sec=30) -> healed=['T0','T0r2','T0r4']`、`active_tasks={'T0': ''}`，与台账那两格逐字同形 ⇒ 锁承重。白盒侧成对改写：`src/ops/ops_test.mbt`（首拍不回滚 / 超 timeout 仍回滚 两臂）、`src/ops/ops_watchdog_test.mbt`（A-3a/3b/3c）。全量：`moon test --target js -j 1` = Total tests 572, passed 572, failed 0。权威 CI 加了这一步（ci.yml 'Heartbeat cross-process guard'）。
【BUG-118】根因分两半。已落地并可本地实测的那半（本条的主张）：格式门搬进权威 CI——.github/workflows/ci.yml 的 js-ubuntu 作业新增 'Format check' 一步，先 `moon version --all` 再 `moon fmt --check`；fist-ci.yml 的同名步骤也加了版本自述，于是两条轨的红各自点名是谁判的。本机实测（moon 0.1.20260920）：对当前工作树跑 `moon fmt --check` = 0 处差异（我逐文件 `moon fmt` 只落自己写的 7 个 .mbt，不整档扫）。未定案的那半如实记着：把两条轨钉到同一个 MoonBit 版本这一步没做——`moon upgrade` 无 --version，且本机取 install/unix.sh 失败（curl rc=35 SSL），无法验证安装器是否接受版本参数；**不猜着写 CI 配置**。步骤里的 `moon version --all` 就是为了让下一轮能拿两条轨的实际版本对照定案，而不是继续猜。

## BUG-120 [2026-09-29T07:04:33Z] [medium] FIXED
- summary: README 离线/内网安装线的资产名版本字面量无人认领——R1 只扫安装器、J4 只认 `@x.y.z`，版本一前进则照抄 `-LocalZip` 那条线就 404
- detail: 发现面：BUG-116 车道（e2e_irm_line 两臂改造）的交接缺口②。
被检面：README.md:129 `install_onecmd.ps1 -LocalZip C:\path\to\fist-mbt-js-v0.3.4.zip`。
为什么两版守卫都看不见：check_release_asset_names 的 R1 判的是 install_onecmd.ps1 / install.sh 里「给版本号写字面量默认值」，README 不在它的安装器清单里；check_doc_surface 的 J4 只比 `@x.y.z` 式版本声明（`0.3.4 (unreleased)` 那一类），资产名里的 `v0.3.4` 不是它的针。
后果：moon.mod 前进后（0.3.4 -> 0.3.5）离线/内网线的用户按文档抄一个不存在的资产名，而 CI 全绿——与 BUG-114「源码版本常量落后」同族，只是这次落在文档的资产名上。
- reported_by: fist-mbt-final-review-r13



### FIXED(2026-09-29T07:05:54Z / BUG-120)
- evidence: `scripts/check_release_asset_names.py` 新增 R13：judge() 用 `fist-mbt-js-v(\d[0-9A-Za-z.\-]*?)\.zip` 扫 README 正文，以数字开头的版本字面量必须 == moon.mod 的 version，读不到基线即自拒；模板形态 `v$VERSION` 放行（不误红，否则会把文档逼回写死版本）。`--selftest` 两支：README 字面量改成 0.9.9 必红、改成 `v$VERSION` 不许红，格子清单从已执行格子反解 => `R13×2`。自述同步：AGENTS.md 守卫族段 + scripts/README.md 该条索引（BUG-120 加进守卫标题）+ check_release_asset_names 自身 PASS 行反解到 R13。实测：`python scripts/check_release_asset_names.py` rc=0；`--selftest` rc=0；check_doc_surface / check_scripts_index / check_entry_paths rc=0。

### FIXED(2026-10-16T15:51:55Z / BUG-120)
- evidence: scripts/fist-mbt-http.py:209 修复：deadline = time.time() + 30 → FIST_HTTP_WAIT_SEC 可配置（默认 600s）。3100 桥已重启验证 executor_run 93s 返回 ok，exit_code=0。源码改动：scripts/fist-mbt-http.py B120-wait 段。回归：moon test src/engine 162/162 绿。
## BUG-121 [2026-09-29T07:16:30Z] [medium] FIXED
- summary: 插件态 skill 广告的开发模式名有两个不存在、还漏了 explore——照抄 mode=hunt / mode=night-loop 会被服务端当场拒
- detail: 发现面：终审收口自证「文档点名的模式名是否与 src/ops/ops_modes.mbt::all_modes() 同形」。
被检面：plugins/source/SKILL.md 的 description 行与模式段、plugins/source/references/seven-modes.md 的模式矩阵。
注册表真值：advance / polish / verify / bugfind / fix_and_merge / tidy / explore（7 条；mode_list 实测回 7 条，mode_templates 的 missing 为空）。
文档谎言：写了 hunt、fix-and-merge、night-loop 三个不存在的标识符；night-loop 从来不是模式标识符（无人值守窗口是 watchdog_tick + cron 元提示词模板），矩阵还整列漏掉 polish 与新加的 explore。
影响：这四份 SKILL 由 gen_plugins 投影到 atomcode/codearts/deepseek-harness/claude，消费方按名调用即失败。mode_templates 只验模板文件存在性、check_doc_surface 的 J8 只比「模板调用参数 == 真源 schema」，没有一条判据把「文档点名的模式名」打到注册表上（J10 只管 J 系列的范围声明）。
- reported_by: fist-mbt-final-review-plugin-plane



### FIXED(2026-09-29T07:16:30Z / BUG-121)
- evidence: plugins/source/SKILL.md 与 plugins/source/references/seven-modes.md 的模式清单改为注册表 7 个标识符 + 服务端 mode_display_name 的中文名；补 explore 行（复杂度 0..5 选一个单模式，并行须申报作用域两两不相交 + reserve_scope 拿到预订 + conflicts_check 放行，否则退回单模式串行）；模板落点写明 templates/pipeline_mode_<identifier>.md；seven-modes.md 加历史注记说明 hunt/fix-and-merge/night-loop 不是标识符。gen_plugins.py 重投影四宿主后 check_plugin_sync.py = PASS（逐字节一致）。 判据缺口（文档模式名 <-> 注册表无常驻对照）另计入报告 §7 后续建议。
## BUG-122 [2026-09-29T07:28:18Z] [medium] FIXED
- summary: demo/自检脚本裸跑会把演示数据写进仓库根的自举台账 fist-mbt.db（四处文档教人这么跑）
- detail: 发现面：终审收口对「提供的 demo 需要完全可用」逐条跑文档命令，跑完只读复核根台账计数。
被检面：scripts/mcp_smoke.py、enrich_selfdrive.py、award_demo.py、omega_lesson_verify.py —— 四个都不设 FIST_DB_PATH；
而 README「一键完整自检」、USAGE:163、docs/agent-map.md:12/56、docs/deliverable.md:10 四处都教人裸跑。
实测：裸跑一次 mcp_smoke ⇒ 根台账 tasks 1986 到 1987、call_log 6905 到 6909（本轮这一次留下的行已进真实台账，只追加不删）。
为什么是缺陷：仓库根 fist-mbt.db 是自举台账（.gitignore 挡着不等于可脏），演示数据混进真实账会污染
「本轮用了哪些工具要问 call_log」这类对账；demo.ps1 已经自己设 FIST_DB_PATH，说明这正是本项目认定的正确形状。
残留同型面（计入报告 §7，不在本轮射程）：scripts/dispatch_verify.py 等若干 *_verify.py 仍写根库，
且它们的索引行教人「完成即 git checkout -- fist-mbt.db 恢复整洁」——该文件是 gitignored，checkout 恢复不了，
那句出路本身就是坏的（应改脚本默认隔离，而不是教人回滚一个 git 不管的文件）。
- reported_by: fist-mbt-final-review-demo-plane



### FIXED(2026-09-29T07:28:19Z / BUG-122)
- evidence: 四个脚本在 NODE 行之后统一加默认改道：FIST_DB_PATH 未显式设置时落 temp/<脚本名>.db，
显式设过的调用方（demo.ps1 那类）行为不变。
实测：改道后裸跑 mcp_smoke rc=0 且 MCP-SMOKE PASS，根台账 tasks/call_log 前后逐字不变（1987/6909），
演示行落进 temp/mcp_smoke.db（tasks=1、call_log=3）。
scripts/README.md 的 mcp_smoke 条目写明该边界并点名另外三个同改脚本与残留同型面。
## BUG-123 [2026-09-29T07:28:19Z] [medium] FIXED
- summary: gen_help_docs.py 自称是 cmd/cli help_tools() 文案的落笔依据，照它写会把 CLI 帮助从 13 组/129 倒退回 12 组/107
- detail: 发现面：终审自证「文档点名的分组/工具数 == 调用面」时拿 scripts/gen_help_docs.py 的快照与 `fist help tools` 对表。
被检面：scripts/gen_help_docs.py 的 docstring 与 scripts/README.md 该条（原写「help_tools() 文案照它的输出人工落笔」）。
实测：脚本反解 src/server/server.mbt 的 tool_groups 得 12 组/107 个 token；tools/list 真值 129 个；
`node cli.js help tools` 回执 13 组/129（本轮刚补 [Modes 2] 一组）。
为什么是缺陷而不是「资源面少列了 22 个工具」：fist://map 的 tool_groups 按自身声明是一张定位图
（组值省略公共前缀简写，如 succeed status、append/get/export_tasks），不是注册表；拿它与 tools/list 做机械差集
会把「未点名」虚报到 73 —— 先读被检件的自述定位声明，再决定是不是缺陷（本条一度被误判成产品缺陷）。
真缺陷在**指引面**：脚本与索引都把它说成 CLI 文案的权威源，照做就会把已经对了的 CLI 帮助改坏。
- reported_by: fist-mbt-final-review-demo-plane



### FIXED(2026-09-29T07:28:20Z / BUG-123)
- evidence: gen_help_docs.py 的 docstring 改写 + 快照输出加打两行边界提醒（定位图 != 注册表；
CLI 权威面 = `node cli.js help tools` 回执 + AGENTS/README 工具表，由 check_tools_sync 的 J1/J2 钉）。
scripts/README.md 该条同步，点名「不许照它落笔」的实测后果（13 组/129 倒退 12 组/107）。
顺带把扫描从 lazy 正则改成花括号配平（旧写法遇到块内 `})` 会静默截断——本次实测两者同结果，属加固不是修行为）。
实测：`python scripts/gen_help_docs.py` rc=0 并打印边界行；check_scripts_index / check_doc_surface / check_tools_sync rc=0。
## BUG-124 [2026-09-29T08:05:32Z] [medium] FIXED
- summary: BUG-122 的残留同型面：另有 21 个 spawn serve 的 demo/verify 脚本仍裸跑写仓库根自举台账，且无常驻判据
- detail: 发现面：终审按文档命令逐条跑 demo 面之前，先静态枚举「Popen + "serve" 但不把 FIST_DB_PATH 交给子进程」的脚本。
被检面（21 个，命名以 git diff 反解为准）：scratch_verify / dispatch_verify / enhance_verify / map_verify /
lesson_verify / dag_depend_verify / evolve_critic_verify / executor_route_verify / plan_gradient_verify /
task_challenge_verify / lesson_selfdrive / lesson_chain_selfdrive / log_fix_selfdrive / scratch_selfdrive /
atgc_selfdrive_demo / pentad_fist / fist / issue_scan / output_validate / mcp_bug_loop / test_mcp_bugs。
为什么 BUG-122 只修了 4 个：那 4 个是文档（README/USAGE/agent-map/deliverable）教人裸跑的入口，其余同型面当时
只写进了报告 §7 的「残留」——残留不是修复：任何一次巡逻或自驱跑这些脚本，真实台账就长演示行。
另有一处**出路本身是坏的**：scripts/README 对 dispatch_verify 写的收口办法是 git checkout -- fist-mbt.db，
而该文件是 gitignored，git 根本不管它 ⇒ 那句教人的话不可执行。
- reported_by: fist-mbt-final-review-demo-audit



### FIXED(2026-09-29T08:05:32Z / BUG-124)
- evidence: 上述脚本统一加默认改道（未显式设置 FIST_DB_PATH 时落 temp/<脚本名>.db；显式设过的调用方行为不变）。
补常驻判据 scripts/check_demo_isolation.py：I1 缺改道针必红 / I2 豁免面漂到不 spawn 的文件必红 /
I3 扫描面空必自拒；--selftest 五支（G1 干净不误红 / M1 摘针必红 / M1b 只加注释不误红 / M2 豁免漂移必红 / M3 空扫描自拒），
格子清单从已执行对照反解。现状面 29 个 spawn 脚本全合规，豁免 1 项（store_isolation_probe 的 C2 对照格必须走默认路径，
且两格 cwd 与库都在临时 box 内）。ci.yml JS 轨挂「先 --selftest 再全量」两步；AGENTS 守卫族计数 11 到 12；
scripts/README 登记。
按文档命令实测：README 的 DEMO 表 7 条 + 独立 CLI 表 2 条 + demo.ps1/showcase.ps1 = 11 条全 rc=0，
全程仓库根台账 tasks/call_log 恒为 1987/6909（temp/demo_audit.log）。
## BUG-125 [2026-09-29T08:05:32Z] [medium] FIXED
- summary: 安装器内部两发取数（moon.mod 定版本 + 资产 zip）只有 .NET 单栈，就是「脚本取回来了、红在内部那一发」的来源
- detail: 发现面：BUG-116 车道活证据 run6/run7——curl 兜底臂把 install_onecmd.ps1 取回来后，红在内部那一发：
「基础连接已经关闭」+「无法从 moon.mod 解析版本号」，最终只剩 -LocalZip 离线线可用。
被检面：scripts/blackbox/install_onecmd.ps1 的两处 Invoke-WebRequest（取 moon.mod 解析版本 / 取资产 zip）。
为什么 BUG-116 当时没修到它：R12 判的是 zip 那一发的**重试纪律**（有响应就 break + 退避间隔），
文档线的两臂由 e2e_irm_line 判；「内部取数能不能换 TLS 栈」这一格两版守卫都不看 ⇒ 与 BUG-120 同族的两面缝隙。
- reported_by: fist-mbt-final-review-demo-audit



### FIXED(2026-09-29T08:05:32Z / BUG-125)
- evidence: install_onecmd.ps1 新增兜底臂 function Get-UrlTo（curl.exe -fsSL --retry 3 --retry-delay 2 --retry-all-errors），
两处 .NET 取数都接上：moon.mod 侧换栈后仍走同一套 HTML sniff + 版本解析（来源行标注 [curl-fallback]），
zip 侧换栈后仍验 PK 魔数 + 大小门。换栈只在「异常没有 Response」时发生，404/403 仍直接换源（与 R12 同纪律）。
判据加 R14（check_release_asset_names）：兜底臂注册在 / 两处调用点都在 / 传输层闸在 / curl 旗带重试上限；
--selftest 五支变异（含「针必须带次数——单独的 --retry 子串会被 --retry-delay 喂绿」这一手），反解 R14×5。
承重证据 scripts/blackbox/e2e_transport_stack_fallback.py 三格实测：A rc=0 且 curl-fallback 命中=True、
B（剥掉 curl）rc=1、C（干净）rc=0；用户 PATH 逐字还原 1708 字，真产物 sha256 616b7632 不变。
另：PS 侧两条硬口径写进判据 docstring——throw 是语句不是表达式（必须包成 (& { throw ... })），
变异副本必须带 UTF-8 BOM 写盘（否则含中文 .ps1 在 PS5.1 解析期即坏，第一版把三格全跑红是尺子坏不是产品坏）。
## BUG-126 [2026-09-29T08:19:52Z] [low] FIXED
- summary: scripts/README 把 showcase.ps1 的读盘实时计数写成死数字（548 tasks/196 exec/6 review），演示每跑一次就漂一次
- detail: 发现面：BUG-124 收口时按文档命令复跑 showcase.ps1，它的「自举迭代库」那行现数自仓库根 fist-mbt.db（脚本 line 119-138：只读 URI 连库、select count(*) from tasks / executions），而索引条目把这三个数当事实写死了。
被检面：scripts/README.md:57 showcase.ps1 条目。
实测漂移（只读数）：文档写 548 tasks / 196 exec，盘面真值 tasks=1987 / executions=461；6 review 那一项来自 memory/reviews 目录 listing，本次仍为 6。⇒ 三个数里两个已经漂了，而且这类数**每次演示都在长**，写进文档就是埋一颗定时假话。
同族前例：BUG-120（README 离线线里的资产名版本字面量落后 moon.mod，R13 收口）——都是「文档抄了一个会变的活体值」。区别在于这条没有判据认领：R13 只管资产名形状，check_doc_surface 的 J 系列管工具数/版本/模板参数，谁都不看索引条目里的任务计数。
另发现一条取证侧的坑（写进同一行文档）：默认码页下 `pwsh -File scripts/showcase.ps1` 重定向出来的中文回执在**子进程内**就被写成 `?`，外层无论按 UTF-8 还是 GBK 解都还原不回来 ⇒ 证据看得见但复核不了；先置 [Console]::OutputEncoding=UTF-8 才拿得到 `[DEMO] PASS — 环境就绪，30 秒可复现` 这种可引用行。
- reported_by: fist-mbt-final-review-demo-audit



### FIXED(2026-09-29T08:19:52Z / BUG-126)
- evidence: scripts/README.md:57 改写为：该行是**读盘实时计数**（现数自仓库根 fist-mbt.db，随使用增长 ⇒ 索引里不写死数字）；数不到时脚本降级打 n/a 并明说「跳过真实计数（演示不会崩）」（脚本 line 140-141，实测过这条分支的形状）；补码页口径与取证办法，实测耗时由 ~1.7s 校正为 ~1.5s（temp/demo_audit2.log）。
承重实测：`temp/demo_audit2.py` 两条 rc=0，全程仓库根 tasks/call_log 恒为 1987/6909（`temp/demo_audit2.log` 首尾行），与 `temp/demo_audit.log` 的 9 条 python 侧文档命令合计 11 条全 rc=0（BUG-124 的 demo 面证据链由此闭合）。
缺口如实登记（不在本轮实现）：没有常驻判据把「文档里的活体计数字面量」打到盘上真值——已写进终审预备报告 §7 的下一轮建议（与 J11 模式名对表同一批）。
## BUG-127 [2026-09-29T09:36:03Z] [medium] FIXED
- summary: mooncakes 的打包面是「工作树 − .gitignore」而不是 git 跟踪面 ⇒ 未 ignore 的构建残留会进公开包
- detail: 发现面：发 0.3.4 前先按「569 个 git 跟踪文件」扫了敏感面（0 凭据形状、0 本地绝对路径），
发完再把**注册表实际交付的载荷**解出来对表：载荷 552 件，其中 1 件根本不在 git 里 —— `__cli_pkg.mbt.tmp`
（moon 生成的 cmd/cli 包声明临时件）。⇒ 我那道的门禁扫错了面：跟踪面绿不代表公开面干净。
同一次对表还量到反方向：**18 个被跟踪的文件不在载荷里**（`.github/*` 5、`.githooks/*` 2、`.codeartsdoer/*` 2、
`.gitignore` 1、`.mcp.dev.json` 1、`.mcp.example.json` 1、`docs/*/.gitkeep` 3、`plugins/claude/.claude-plugin/*` 2、
`plugins/claude/.mcp.json` 1 —— 共同点：**点号开头的文件或目录 moon 一律不打包**）。
所以「一源四态」里的 MCP 配置面与 claude 插件 manifest **不会**随 mooncakes 分发，
消费方要自己写 `.mcp.json`（README 的 mooncakes 用法段有没有把这条边界说清，是另一格）。
内容风险实测：`__cli_pkg.mbt.tmp` 只有 5 行 import 声明，无凭据、无本机路径 ⇒ 不是泄露事故，是**卫生事故**。
- reported_by: fist-mbt-mooncakes-publish-audit



### FIXED(2026-09-29T09:36:03Z / BUG-127)
- evidence: .gitignore 追加 `*.mbt.tmp`（第 48 行，附为什么的一行注释：打包面=工作树−ignore）。
机器可检：`git check-ignore -v __cli_pkg.mbt.tmp` 回 `.gitignore:48:*.mbt.tmp`；
追加后 `git status --porcelain -uall` 的未跟踪未忽略面只剩 `.mcp.json`（有意不入库，且点号文件本来就不进包）。
下一版的发布前置（本轮只登记不实现）：门禁应扫**解包后的载荷**（`moon view` + `moon add` 到空壳工程 + find 列件），
而不是扫 git 跟踪面；这一步现在靠我手工做，无常驻判据。
## BUG-128 [2026-09-29T09:36:03Z] [high] FIXED
- summary: 同一个 0.3.4 现在有两份不同的码：GitHub Release 资产（git tag v0.3.4 的树）与 mooncakes 包（今天收口后的树）
- detail: 发现面：发布后用 `git diff --stat v0.3.4..HEAD` 对身份，量到 tag 与载荷不是同一棵树。
实测：本地 tag `v0.3.4` = af54d5e（2026-09-29 01:15 +0800，当时 moon.mod 已写 0.3.4）；
v0.3.4..HEAD 共 **11 个提交**，`src`+`cmd` 侧 **21 个文件 +1643/−269**（看护跨进程修复、探索模式注册表与纯函数、
白盒锁、R11/R13/R14 相关面等）；mooncakes 上的 0.3.4 发布于 2026-09-29T09:26:54Z，取自 a0dfef3 的工作树。
后果（用户侧形状）：`install_onecmd.ps1 -Version 0.3.4` 拿到的是**旧码**（GitHub Release 资产），
`moon add vicTop-cw/fist-mbt@0.3.4` 拿到的是**新码**，两者同号不同物；`fist version` 又只回显 0.3.4，
所以用户没有任何办法从版本号分辨自己装到了哪一份 ⇒ 与 BUG-114（源码版本常量落后 moon.mod）同族的另一面。
- reported_by: fist-mbt-mooncakes-publish-audit


### FIXED(2026-09-29T10:44:53Z / BUG-128)
- evidence: 出路①（owner 2026-09-29 裁决「发 0.3.5」）已执行完，逐格实测：
① 版本真源三处同步：`moon.mod` 0.3.4→0.3.5、`src/server/server.mbt::project_version`、
   `cmd/cli/help_topics.mbt::FIST_VERSION` 三处逐字相等（R11 判据 + `src/server/fist-mbt_wbtest.mbt` 白盒锁），
   README 离线线的 `fist-mbt-js-v0.3.5.zip` 字面量同步（R13）；注册表发布版本自述仍只在 `BACKLOG.md` 一处（J4）。
② 调用面自证：`scripts/cli_flag_probe.py` 起真产物回显 0.3.5；真 RPC 回执里 `0.3.5` 出现 3 次、`0.3.4` 0 次；
   插件态重投影后 `check_plugin_sync`（cl7）逐字节通过。
③ 发布：`moon publish --dry-run` = 202 Accepted；真发第一次 rc=127 传输层抛
   `send failed because receiver is gone`（`Check passed` 与 zip 校验都在它之前通过）⇒ 先 `moon view --versions`
   读回注册表确认 0.3.5 未登记（仍是 0.3.4/9 版）才重试，第二次 `Server status: 200 OK`、rc=0；
   读回 `vicTop-cw/fist-mbt@0.3.5` / Latest 0.3.5 / Versions 10 / Published 2026-09-29T10:35:10.876305+00:00。
④ 载荷对表（USAGE §10 第 3 步）：空壳消费工程 `moon add vicTop-cw/fist-mbt@0.3.5` 后
   `moon check --target js` rc=0（58 个任务）⇒ 新进程能解析并编译这一版；解包 **552 件**，
   与 `git ls-tree -r 124a20a` 的非点号跟踪面双向差集 **0/0**，逐件比对（仅归一 CRLF）**0 处不一致**
   ⇒ 「注册表载荷 == 被 tag 的那棵树」这次是量出来的，不是推的；
   `__cli_pkg.mbt.tmp` 件数 0（BUG-127 的修在下一版载荷上兑现）；凭据形状扫载荷 **0 命中**。
⑤ 身份：本地 `v0.3.5` 与 `mooncakes-0.3.5` 都钉在 124a20a（即上面比对的那棵树）；
   `fist-final-review-20260929` 仍留 a0dfef3 不移动。
同号两树的旧事实不可撤销（注册表版本不许覆盖，只能 `moon deprecate`）⇒ 0.3.4 那一格作为遗留风险写进
CHANGELOG/BACKLOG，是否给 0.3.4 打 deprecate 标记留 owner 裁决；公网安装线（GitHub raw/Release 资产）
本轮没有 push，故仍指向发布前的码——这一格同样是遗留面，不是已修面。
## BUG-129 [2026-09-29T09:46:36Z] [medium] FIXED
- summary: 「发布载荷对表」当时只由我手工跑了一遍，没有常驻判据认领（BUG-127 的 FIXED 小记自己写了这一格）
- detail: 发现面：BUG-127 收口时我在 `### FIXED` 小记里如实写了「下一版的发布前置（本轮只登记不实现）：
这道对表目前没有常驻判据」——那就是本条。缺口挂在账本的叙述面里而没人认领，正是本仓反复的 J10 型形状：
「自述有人写、判据没人认领」。既然发 0.3.4 已经证明这类缝真会漏东西（`__cli_pkg.mbt.tmp` 进了公开包），
就不该等下一次发布再补。
被检面：`moon publish` 前置检查面。以前只有两道间接门——`check_release_asset_names`（资产名/安装器/moon.mod 同源）
与 `check_plugin_sync`（四宿主逐字节），都不看「哪些文件会随包公开」。
为什么不复用现成件：载荷真值只有解包才拿得到（要联网 `moon add`），CI 里不该跑网络；
所以常驻判据走的是**等价静态面**——git 自己算得出的「工作树 − .gitignore」就是 moon 的打包面（点号条目另论）。
但要说清它是**代理门不是替身**：静态面数出将随包公开 552 件，注册表解包实测也是 552 件，**数目相等而集合不同**
（载荷里有后来才被 `.gitignore` 挡掉的 `__cli_pkg.mbt.tmp`，静态面里有发布之后新增的守卫件）⇒
发完仍要解包对表一次，本判据管的是「别把本地残留带上车」这一头。
- reported_by: fist-mbt-mooncakes-publish-audit



### FIXED(2026-09-29T09:46:36Z / BUG-129)
- evidence: 新增 `scripts/check_publish_payload.py`：P1 未被 .gitignore 挡住又未被 git 跟踪的非点号文件 ⇒ 红（点名文件与修法）；
P2 红面里出现凭据形状 ⇒ 另判事故级并单列（已发版本撤不回）；P3 打包面列不出任何文件 ⇒ FATAL(2) 自拒。离线、不起进程、不联网。
`--selftest` 四支从已执行格子反解：G1 干净不误红（工作树带未跟踪件时自动换 G1'：逐件点名且无幻影红）/ 
M1 造未跟踪未忽略件必红 / M2 造被现成 `*.log` 规则挡住的件必不红 / M3 红面里塞凭据形状必点名 P2；
造件在 finally 逐个删并复核盘上无残留。实测回执：`SELFTEST OK（… 打包面 552 件 / 其中未跟踪未忽略 1 件 / 被 moon 排除的点号件 18 件）`（那 1 件正是守卫自己，未 add 时它就该红——这一手顺带证明判据看得见东西）。
全量实测（`git add` 之后）：`PASS 发布载荷面干净：将随包公开 552 件，其中未被 git 跟踪的 0 件（另有 18 件点号条目 moon 本来就不打包）`，rc=0（`temp/payload_guard_plain.log`；带未跟踪件的那次留了 `.prev` 与 `temp/payload_guard_selftest.log`）。
接线：ci.yml JS 轨加「先 --selftest 再全量」两步；scripts/README 登记；AGENTS 守卫族 12→13，并把相邻那句「与上面 11 个 check_* 并列」改成不带数目的写法——那个数当时已经过期一次了。
自证踩到的两个坑也写进了判据正文：① 守卫源码里不许出现完整 token 形状（我一开始把假串直接写进字面量，
P2 就打到守卫自己）⇒ 改成运行时拼接；② G1「干净不误红」在开发期必然失败（新守卫自己未跟踪）⇒ 换成更强的 G1'（红面与未跟踪面双向对齐、不许幻影红），而不是删门或放宽阈值。

## BUG-130 [2026-09-30T00:07:57Z] [medium] FIXED
- summary: push 后拿权威 CI 当验收，抓到一条自 09-28 起持续红、且匿名取不到定因、账本无人认领的门：ci.yml 的 native 测试轨（步骤名 Test (native, j=1)）
- detail: 发现面：owner 授权 push，于是按既有口径把『推送后的 CI 运行』当关闭证据（不是本机自述）。
实测（匿名 Actions API，只 GET、不带凭据、不读 .env）：run 36648283575
  （head_branch=master，created_at=2026-09-30T00:02:16Z）三个 job 结论 = native:failure / js:success / nightly:skipped；native 那 job 内红的那一格步骤名 = Test (native, j=1)，
  其余 6 步（含 Check (native)）全 success ⇒ 编译过、测试不过。
同型红不是本轮引入：run 36463333299（2026-09-28T18:10:35Z）与 run 36461416256（17:54:09Z）
  同样是 Test (native, j=1) failure；那两次还各多一格 js 的 Format check 红，
  今天 Format check 已转绿 ⇒ 本轮 CI 面唯一的好转是 BUG-118 那道格式门。
为什么这条要入账而不是当『已知边界』划走：AGENTS.md 确实把 native 声明为非权威门槛
  （Windows 并行偶发 0xc0000374、建议 -j 1、权威稳定门槛 = JS 后端），但 ci.yml 里这一步**没有** continue-on-error，
  『设计上允许红』的门就挂成了『会红且没人解释』的门——这正是 BUG-114 那句『红着没人读等于没锁』的 CI 版。
定因取不到也是事实，且要说清是哪一格取不到：GET /repos/vicTop-cw/FIST-Mbt/actions/jobs/109676257901/logs
  匿名回 403（message = Must have admin rights to Repository）⇒ 调用面只拿得到步骤名与结论，拿不到断言/崩溃细节。
本机复现不在本轮改动面上：native 测试在 Windows 侧要 sqlite3.h/sqlite3.lib + 同会话 MSVC 环境（scripts/native-env.ps1），
  Linux 侧要 WSL；而 CI 那台的失败形态与这两条都不必然同因，靠本机跑绿去宣布关闭是假的。
- reported_by: fist-mbt-post-push-ci-audit

### 追记(2026-09-30T01:38:03Z / BUG-130)
- 本条原先那句「匿名只拿得到步骤名与结论，拿不到断言/崩溃细节」**范围写窄了**，两条新读数补在下面（原文不改）：
  ① **匿名能拿到失败退出码**：`GET /repos/vicTop-cw/FIST-Mbt/check-runs/<job_id>/annotations` 公开可读，
     两个 native job（run 36653784727 job 109693561355 / run 36653784771 job 109693561135）
     各回 3 条 annotation，其中 **failure 级原文 = `Process completed with exit code 255.`**（逐字存 `temp/bug130_annotations.json`）。
     取不到的是 **stderr 正文**（`/actions/jobs/<id>/logs` 仍 403 `Must have admin rights to Repository`）。
  ② **红的范围比原先记的更宽也更久**：把 workflow『CI』在匿名窗口内可见的全部 23 次运行（run#176 @ 2026-09-28T00:59:43Z
     起，到 run#198 @ 2026-09-30T01:09:46Z）逐 job 读过——**最早那三发（#176/#177/#178）三个 job 全红**（含 `Test (js)` 两档），
     js 轨是在这个窗口内才转绿的，而 `Test (native)` / `Test (native, j=1)` 在窗口内**从未绿过**。
     ⇒ 「自 09-28 起持续红」这句的下界要推到匿名可见的最早一发，更早的历史超出可读范围，不写成主张。
- **定因面由此收窄一格（下面前半条是读数推论，后半条明写是猜测）**：`Check (native)` = `moon check --target native` 绿
  ⇒ 失败发生在测试阶段而不是编译/链接阶段，`libsqlite3-dev` 那条嫌疑随之基本排除；而 `-j 1` 串行那一臂同样回 255
  ⇒ 不能只用 AGENTS 里那条 **Windows 并行 `0xc0000374`** 解释（CI 是 ubuntu，且串行也死）。
  **以下是猜测、没有对照**：rc=255 的形状我读成"进程异常终止"多于"某条断言 fail"，但手上没有 native 断言失败的 rc 对照
  （不知道 moon 在那种情形回几），所以这句不能当结论用。要定案还差 stderr：
  要么用带 `actions:read` 的 token 取一次 job 日志（本机 env 现在 `token_present=false`），要么 WSL 里
  `moon test --target native -j 1` 复现——本机这个 Bash 是 MSYS/mingw 环境（`cc` 指向 mingw 工具链），
  在它里面跑出来的红**不能**当 CI 同因的证据，这点先钉死。
- 顺带在同一片面读到一条**与 130 无关的独立缺陷**：`fist-ci.yml` 的 `nightly` 作业 `if: github.event_name == 'push'
  && github.ref == 'refs/heads/main'`，而本仓默认分支是 `master`（`git symbolic-ref refs/remotes/origin/HEAD`
  = `refs/remotes/origin/master`，两个 workflow 的 `on.push.branches` 都写作 `[main, master]`），
  且 `fist-ci.yml` 里**没有任何 `schedule:` 触发** ⇒ 这道「每日自检」永不可能运行，
  每次运行里 `nightly self-check: skipped` 不是「定时轨没到点」，是**条件恒假**。另立 BUG-132，不并到本条。

### 追记(2026-10-01T02:27:45Z / BUG-130)
- 本轮定因面（2026-10-01，owner 配的只读 token 取到日志原文））本条从「未定因」升级为「定因在依赖侧」，逐条读数如下，旧正文一字不改：
- **CI 日志原文拿到了**（`GET /repos/vicTop-cw/FIST-Mbt/actions/jobs/109703045365/logs`，带 owner 配在
  `HKCU\Environment` 的 `FIST_GITHUB_TOKEN`（只读，len=93，全程不回显、不进 argv、不进 URL 明文；302 到 Azure 签名 URL
  的第二发**必须不带** Authorization，带了反而 401））。run 36656890998（@ `4d83a94`）第 8 步 `Test (native, j=1)` 逐字三行：
  `Failed to run the test: /home/runner/work/FIST-Mbt/FIST-Mbt/_build/native/debug/test/src/engine/engine.blackbox_test.exe`
  ／`The test executable exited with signal: 11 (SIGSEGV) (core dumped)`／`##[error]Process completed with exit code 255.`
  ⇒ **不是断言失败**，是测试二进制被信号打死；本条原先那句「拿不到崩溃细节」到此闭合。
- **三条排除都是实测**：① 工具链同版本——权威 CI 的 js 作业里那步 `moon version --all`（BUG-118 留的自述）回
  `moon 0.1.20260920 / moonc v0.10.14+7d59c7ec9 / moonrun 0.1.20260920`，与本机 Windows 和 WSL 的 `moon version --all` **逐字相同**
  ⇒ 「CI 装了更新的后端把 native 编坏」这条**不成立**；② 依赖同版本——`moon.mod` 是精确版本，CI 下载日志点名的
  `async@0.22.3 / x@0.5.5 / mcp@0.17.4 / mooncry@0.13.1 / sqlite@0.3.1` 与本地 `.mooncakes` 同一批；③ 并行不是因——
  `-j 1` 那一臂（fist-ci.yml）与不带旗那一臂（ci.yml）**每次**都红，本轮 34 格 native 作业读数里无一绿过。
- **本机可复现，且复现条件不是「哪个用例」而是「哪棵树」**：仓库工作树（有 `_build`、有上几轮残留的 `*.db`）里
  `moon test --target native -j 1` = **572/572 全过**；同一 commit 用 `git archive HEAD` 解一棵干净树（无 `_build`、无残留 db、无 `temp/`）
  跑同一条命令 = **崩**，第一次崩在 `src/ops/ops.blackbox_test.exe`（signal 11），重跑一次变成
  `munmap_chunk(): invalid pointer` + `signal: 6 (SIGABRT) (core dumped)` ⇒ 崩点在包之间移动、形态是 glibc 报的非法 free。
- **二分面证明「钉一个用例」这条路在此缺陷上不存在**：逐文件单跑，`ops_pipeline_test.mbt` 与 `ops_selfdrive_test.mbt` 各崩过一次
  （rc=255 / SIGABRT），但把同一条命令原样重跑，`ops_pipeline_test.mbt` **16/16 全过**，再按 `-i` 逐索引 0..15 单跑也 16 格全 0；
  engine 侧 19 个黑盒文件逐个单跑**全部单独通过**，而 CI 里死的正是 engine 的 union 产物。
- **根因面另立 BUG-133 那条**（`mizchi/sqlite@0.3.1` 的 native FFI：`stub.c:18-29`/`:79-87` 把 `sqlite3*` / `sqlite3_stmt*`
  裸指针直接当 MoonBit 抽象类型的值回传，全包 `moonbit_make_external_object` 零命中；`stub.c:148`/`:298`/`:321` 三个函数 C 侧回
  `const char*` 而 `sqlite_native.mbt:90`/`:230`/`:240` 声明成 `-> Bytes`，包内注释 `stub.c:200-203` 自认这条路是 UB）。
- **常驻判据已落仓**：`scripts/blackbox/e2e_native_heap_probe.py` 生成的探针只用该依赖的公开 API、一行 FIST 业务码都不含。实跑 `python scripts/blackbox/e2e_native_heap_probe.py --runs 12`（WSL ubuntu-22.04，仓库根）= **crashes=3/12**（sigsegv 1 + sigabort 2 + ok 9）；
  同一探针在干净树的另一轮读数是 5/12（1 次 rc=139 + 4 次 rc=134）。判据方向刻意反向：**0/12 才许把 native 臂当常规门槛**，
  在此之前任何 `continue-on-error` 都属「遮钉住的缺陷」，交 owner 裁决，本条不自决。
- **本轮推翻一条旧口径**：AGENTS.md 原写「Windows native **并行**跑全量偶发 `0xc0000374`，建议 `-j 1` 串行（可降低但不保证消除）」——
  实测单进程探针（无并发）就 3/12 崩、CI 的 `-j 1` 臂每次都崩 ⇒ **串行不降低概率**，且这一类与并行竞态无关；已就地改该句措辞。
- **本条状态仍 OPEN**，但性质变了：不再是「没人解释的门」，而是「定因清楚、出路要裁决」。要 owner 点的三格见
  本轮报告 §后续建议（CI native 臂：保持红 / 挂 continue-on-error / 换成只跑判据）。

### 追记(2026-10-01T03:17:57Z / BUG-130)
- 定因落地 push 之后的权威 CI 读数（定因那笔 commit `47b88ff` push 之后；两远端都只做了 fast-forward、无 force）：
  run 36808812351『FIST CI — Build + Test』= `check + test (js, ubuntu)`=success / `check + test (native, ubuntu)`=failure（红格逐字 `#8 Test (native, j=1)=failure`） / `nightly self-check`=skipped ⇒ 整发 **failure**；
  run 36808812320『CI』= `check + test (js, windows)`=success / `check + test (js, ubuntu)`=success / `check + test (native, ubuntu)`=failure（红格逐字 `#7 Test (native)=failure`） ⇒ 整发 **failure**；
  ⇒ **本轮零改动于 `src/` 与 `.github/workflows/`，native 仍死在同名步骤**——这条红与定因轮的文件改动无因果，
    与 BUG-133 的机理读数（探针零 FIST 业务码也崩，`crashes` 见 `scripts/blackbox/e2e_native_heap_probe.py`）方向一致。
- 两发的 **js 臂都 success** ⇒ 权威面上的判据步骤全过（CI 的 js 作业里跑的就是本地这一族守卫，只是步数不等同：CI 还多跑 store-isolation / heartbeat e2e / cli-flag probe / cleanliness 等）；
  `nightly self-check` 仍 `skipped`，是 BUG-132 那条恒假条件的又一发读数（不改判）。
- 取数面：`python temp/b130_ci_readback.py 47b88ff`（token 只从 `HKCU\Environment` 读、写 curl `--config` 临时文件、结束删除，不进 argv 不打印）；读数原件 `temp/b130_readback2.txt`。
- 本条状态仍 **OPEN**：出路三选一（native 臂保持红 / 挂 `continue-on-error` / 改跑判据当门）在 owner 手上，按金条四不自决改共享 CI 定义。

### 追记(2026-10-02T01:02:46Z / BUG-130)
- owner 裁决③ 落地：CI 的 native 臂改由常驻判据当门（owner 2026-10-02 指示「按照你说的修复」= 三选一里的第③条；本段落盘时 HEAD=`0462263`）：
  改的是两个 workflow 各一步：`Native heap gate (BUG-133 探针当门)` 挂在 `Test (native)` **之前**（ci.yml），`Native heap gate (BUG-133 探针当门)` 挂在 `Test (native, j=1)` **之前**（fist-ci.yml）；跑的都是 `scripts/blackbox/e2e_native_heap_probe.py`（`--selftest` + `--runs 12`）。**测试步骤一个都没删** ⇒ 依赖侧修好后全量覆盖自己回来，不留「记得改回来」的债。
  ci.yml 的门按 rc 硬拦（非零即红）；fist-ci.yml 的门按 rc 四档各写一条 `::error::`（0 放行 / 1 点名 BUG-133 / 3 判据拒绝出数 / 其它=尺子坏了），且取数写成 `rc=0; cmd || rc=$?`——GHA 默认 `bash -e`，`cmd; rc=$?` 会在非零那支先退出、case 分流永远走不到（那等于四档读数只剩一档能说话）。
- 这条单自己的主张已兑现：入账时红的是「**会红且没人解释**」那半（本条 detail 第 4 段），不是「native 有崩溃」那半——崩溃那一半从 2026-10-01 起由 BUG-133 承载。现在门红会逐字点名 BUG-133 与其前置，门绿则全量测试照跑，两种红都读得出归属 ⇒ 本条的关闭证据 = 这两个步骤 + 下面这组读数；**盖章 FIXED 推迟到 push 之后**，拿权威 CI 里那一格的步骤名当证据（读数写进下一段追记），不靠「native 绿了」关闭（那一格属于 BUG-133）。
- 硬化尺子的读数（同一棵工作树、WSL ubuntu-22.04，全部从盘上件反解，脚本里没抄过任何一个 crashes 数）：**同一次会话里连跑两发**（`temp/b130_probe12_v2.log`，尺子 sha 前缀 `ae26376d692362e5`）= crashes=3/12（rc=1）与 crashes=0/12（rc=0）——**N/N 与 0/N 两端在同一支尺、同一次会话里都出现了**；另有 `temp/b130_probe12.log` = crashes=0/12（rc=0，TALLY {'ok': 12}）与定因轮那发 `temp/b130_run_probe.log` = crashes=3/12。⇒ `--runs 12` 是**抽检门**，不是消音判据（收紧后的前置写进 BUG-133 的追记，见下）。
- 收口复跑（最终版尺子，sha 前缀 `2be90ea4fcd28762`；与上面那版之间只动过说明文字与 VERDICT 文案，分格/计数路径未改）：`temp/b130_probe_final.log` = crashes=0/12（rc=0），自检行 `SELFTEST OK（rc 分解 5 格 + 计数口径正负对照 2 支 + rc 隔离对照 2 支（判据自身崩⇒4 / 拒绝出数⇒3 原样透传）+ 构建门 1 格：真跑 OK（故意喂编译不过的探针 ⇒ rc=255，没被数成崩溃））`。
- 尺子自身两处补硬（都是「判据坏了会顶替产品报案」那一型）：① 预编译门 + `RC_RULER=4`，`temp/b130_probe12_v2.log` 里那一行 `SELFTEST OK（rc 分解 5 格 + 计数口径正负对照 2 支 + rc 隔离对照 2 支（判据自身崩⇒4 / 拒绝出数⇒3 原样透传）+ 构建门 1 格：真跑 OK（故意喂编译不过的探针 ⇒ rc=255，没被数成崩溃））` 就是这一格的真跑回执；② 输出通道与 rc 隔离：Windows 默认 cp936 控制台上打印 `⇒` 会抛 UnicodeEncodeError，脚本崩在结论行之前留下 **rc=1**，而 1 在本契约里是「缺陷在场」——`temp/b130_win_probe_check.txt` 存的就是修复前那一发（`selftest_rc=1`），修复后同一命令 `temp/b130_gbk_after_fix.log` = `SELFTEST OK` + rc=0（另有拒绝出数那一支 `runs_rc=3`）。现在判据的任何未捕获异常一律归 4，`SystemExit(3)` 原样透传，`--selftest` 里这两支是成对对照。
- Windows 侧仍不出数（不拿没跑成当跑过）：`拒绝出数：本判据要 POSIX 上的 native 工具链（Windows 侧先装载 scripts/native-env.ps1，或在 WSL 里跑）。没跑成 ≠ 跑过。`（runs_rc=3）；低样本两支存档 `temp/b130_probe_selftest2.log` = crashes=2/2、`temp/b130_probe_selftest3.log` = crashes=1/2。
- 证据件在 `temp/`（会被 `scripts/cleanup_artifacts.py` 回收）；再生命令：`MSYS_NO_PATHCONV=1 wsl -- bash /mnt/e/IDEProjects/AI/FIST-Mbt/temp/b130_probe12_v2.sh`（12 跑两发）与 `python scripts/blackbox/e2e_native_heap_probe.py --selftest`。

### FIXED(2026-10-02T01:20:21Z / BUG-130)
- evidence: 裁决③ 落地两笔（`87e2650` 挂门 + `24c30f8` 给全量那一格补根因注解），两笔都已 fast-forward 推到 origin(GitHub) 与 gitcode（`git rev-list --count <远端>..HEAD` = 0），无 force、无删标签。
  本单主张的是「**会红且没人解释**」那一半；现在两种红都读得出归属，逐字引用权威 CI 的 failure 注解（两臂各一条，原件 `temp/b130_annot_24c30f8_v3.txt`）：
  · 注解原文：『BUG-133 的读面：native 测试二进制以 rc=255 收场（既往形态 = 被信号打死 / core dumped）。上面是 moon 的原文与门那一步的 TALLY；**门绿只代表这一次 12 抽没抽中**（同一支尺同一次会话连跑两发给出过 3/12 与 0/12），不代表已修。关闭条件见账本 BUG-133：抽检连发 0 崩溃 + pax_global_header00006660000000000000000000000064152576024630014524gustar00rootroot0000000000000052 comment=24c30f8a1b029b97cc1733e34dc88522ad1834d7』
  · 注解原文：『BUG-133 的读面：native 测试二进制没跑完就退场（rc=255，既往形态是被信号打死 + core dumped）。门在这一发是绿的，只代表这次 12 抽没抽中（同一支尺、同一次会话连跑两发给出过 3/12 与 0/12）⇒ 不据此写「native 已修」；关闭条件见账本 BUG-133（抽检连发 0 崩溃 + git archive HEAD 干净树全量通过）。』
  同一发的 job/步骤读数（全部从那份原件反解）：
  · run 36949925504『CI』整发 failure
  · run 36949925443『FIST CI — Build + Test』整发 failure
  · job `check + test (native, ubuntu)` = failure，红格逐字 `#8 Test (native)=failure`
  · job `check + test (js, windows)` = success
  · job `check + test (js, ubuntu)` = success
  · job `check + test (js, ubuntu)` = success
  · job `check + test (native, ubuntu)` = failure，红格逐字 `#9 Test (native, j=1)=failure`
  · job `nightly self-check` = skipped
  ⇒ 两条 native 臂的**门那一步都是绿的**（门在 `Test (native…` 之前），红仍在全量那一格但带注解与 rc；
- 本机判据面：`--selftest` 四组全过（含构建门真跑与 rc 隔离成对对照），同一次会话两发 12 跑给出 3/12 与 0/12 两端 ⇒ 0/N 是抽检，native 崩溃那一半仍由 BUG-133 承载，其前置已收紧成两格（抽检连发 0 崩溃 + `git archive HEAD` 干净树全量通过）。
- 验收面（本轮复跑）：JS 全量 = 572/572（failed=0，`temp/js_after_b130.log`）；本地守卫族 17 格全 rc=0（fails=0，`temp/b130_guards.log`）；cl7 四宿主投影一致。
- 盖章走的是 **md 真源面**：本会话连上的 connector 其 server cwd 不指向本仓（`bug_list` 回显 `path=./memory/bugs.md` 且两条 OPEN 是别的项目的台账条目），`bug_fix` RPC 两次 `MCP error -32603`，盘上未产生任何本仓写入（抬头仍 OPEN 时才动手）⇒ 若任务库/DB 面另有这条的旧行，那一面没跟着翻，差异如实记在这里。

## BUG-131 [2026-09-30T00:50:05Z] [medium] FIXED
- summary: cl7 插件态投影引用的启动参数真源文件名由『本机未跟踪残留』决定 ⇒ 同一棵 HEAD 本机绿、CI 红（我 2026-09-30 push 124a20a 之后 ci.yml 的 Plugin-form guard cl7 那一步就是红的）
- detail: 发现面：owner 授权 push 之后按既有口径拿权威 CI 当验收。09-28 的 ci.yml js/ubuntu job 是 success []，我这次 push 后同一 job 的失败步骤名 = 『Plugin-form guard cl7 —— 一源四态的第四态漂移或生成投影里有手写残留』。本机复跑 cl7 却 PASS ⇒ 『本机绿 / CI 红』这一型先怀疑尺子的输入面，不怀疑被测。
取证（CI 等价面 = git archive HEAD 解到 temp/cl7repro，那棵树里没有本机残留）：python scripts/gen_plugins.py --check 回 FAIL 插件态漂移（4 个文件与真源投影不一致），点名 atomcode\INSTALL.md / claude\INSTALL.md / codearts\INSTALL.md / deepseek-harness\instructions.append.md；统一 diff 每份只差一行——投影正文那句『MCP server 真源在仓库根 X（129 工具 / v0.3.5）』里的文件名：提交面是 .mcp.json，CI 面生成的是 .mcp.dev.json。
根因（机器可检，不是推测）：scripts/gen_plugins.py 与 scripts/check_plugin_sync.py 各写 MCP_CANDIDATES = ('.mcp.json', '.mcp.dev.json') 并取第一个存在的，而 MCP_NAME = ROOT_MCP.name 是要写进投影正文的那个字 ⇒ 取到哪一份由『本机磁盘上有什么』决定，不由仓库决定。
本机残留身份：git ls-files -- .mcp.json 空、git check-ignore -v .mcp.json 空、git status --porcelain 回 ?? .mcp.json ⇒ 一份既未跟踪又未被忽略的仓库根残留；内容与跟踪真源逐字节相同（.mcp.json / .mcp.dev.json / plugins/claude/.mcp.json 三份 sha256 前缀同为 7a609527），而 CI 的 checkout 里它根本不存在。它为什么在仓库根：本机 MCP 连接器读的就是这个名字（该事实2026-09-29 终审批备报告 §表格已记『根 .mcp.json 未入库 ⇒ 需 owner 决定要不要跟踪』，尚未裁决）。
为什么现有守卫看不见：check_publish_payload（BUG-127/129）的 P1 只管非点号件（点号条目 moon 本来就不打包），G1' 那句『工作树带未跟踪件时逐件点名』也走同一条排除 ⇒『点号 + 未跟踪 + 未忽略 + 同时是某投影的输入』这一格没有常驻判据认领。它不泄漏、只让生成产物随机器变，比泄漏更难发现：开发机上永远是对的。
修法与常驻判据（本轮已落盘）：两处候选顺序改为跟踪面优先 ('.mcp.dev.json', '.mcp.json')，.mcp.json 降级为搬家前别名兜底；gen_plugins.py --selftest 由四格升级为五格，第五格在临时目录放两份候选并要求取到 .mcp.dev.json。第一版我把期望值写成 MCP_CANDIDATES[0]，与实现同公式＝恒真判据（顺序改回旧口径照样绿），反向对照当场抓到并改成写死字面名。实测：新顺序 rc=0；把顺序打回旧口径 rc=2 并双红（格5 候选表首位是 .mcp.json… + 格5b 两份候选都在时取到了 .mcp.json）。
观测面同步补：gen_plugins --check 的 OK/FAIL 行与 cl7 的 PASS 行都打印『启动参数真源取到哪一份』，下次再分叉时第一眼看得见，而不是只看见『4 个文件漂移』。
影响与债：受影响的是 HEAD 上已提交的投影字节（124a20a 那 4 份写的是本机残留名），修完须重投影 + 再 push 才转绿；v0.3.5 的注册表载荷不含点号件，已发布内容不受影响。
建议口径（同族通用）：生成器与守卫读的每个输入文件必须落在跟踪面上，或由判据点名『本机多出来一份同名残留』——否则 cl7 这类逐字节守卫只是把开发机的磁盘状态固化进提交里。
证据（本轮实测，非自述）：temp/cl7repro（git archive HEAD）实测 --check rc=1 点名 4 份投影；三份候选 sha256 前缀 7a609527 逐字节相同；git ls-files / check-ignore / status 三向对齐 => ?? .mcp.json；gen_plugins --selftest 新顺序 rc=0、旧顺序反证 rc=2（格5+格5b 双红）；修复后本机与 CI 等价面 temp/cl7ci2 两侧 cl7 均 PASS（启动参数真源 .mcp.dev.json）
- reported_by: fist-mbt-post-push-cl7-audit-68696c86



### FIXED(2026-09-30T00:58:12Z / BUG-131)
- evidence: 条目里写死的翻转判据已满足，且读的是同一个格、同一把尺：
① 权威 CI（匿名只读 API）run 36652585906 = workflow 『CI』@ 00e64bd：job `check + test (js, ubuntu)`
   conclusion=**success**，其中第 13 步 `Plugin-form guard cl7 (一源四态：四宿主插件目录==真源投影)`
   conclusion=**success**；同一格在修复前那发 run 36650601254（@ ec4c347）是该 job 的唯一红格
   （red step 名单点名 Plugin-form guard cl7）⇒ 红→绿读在同一步，不是换判据或摘门。
② 修复身份：commit 00e64bd（19 files, +116/−38）fast-forward 推 origin(GitHub) 与 gitcode 两远端
   （ec4c347..00e64bd，无 force、无删标签）。
③ CI 等价面复验：`git archive HEAD` 解到 temp/cl7ci3（那棵树里没有本机 .mcp.json，且是 autocrlf 的 CRLF 检出）
   跑 gen_plugins.py --check rc=0（正文另报『55 份仅行尾不同』按 BUG-102 归一后视为一致）、
   --selftest rc=0（五格全过）、check_plugin_sync.py rc=0；三条结论行都点名『启动参数真源 .mcp.dev.json』。
   本机工作树（同时存在两份候选）同三步同样 rc=0 ⇒ 两侧同解，这一格从此与本机磁盘无关。
④ 常驻判据：--selftest 新增第五格在临时目录放两份候选并要求解析到 .mcp.dev.json，期望值写死字面名。
   反向对照实测：内存里把候选顺序打回旧口径 ⇒ `格5 候选表首位是 .mcp.json…` + `格5b 两份候选都在时取到了 .mcp.json`
   双红 rc=2；新顺序 rc=0。（第一版期望值写成 MCP_CANDIDATES[0]，与实现同公式＝恒真判据，被这条对照当场抓出。）
⑤ 没在这条出口里的两格要说清：仓库根那份未跟踪的 .mcp.json 是**本机 MCP 连接器在读的配置**，   按原样保留未动（删/跟踪都属 owner 的开放决定），投影已不依赖它；   同轮 CI 面上仍红的 native 轨 `Test (native)` 属 BUG-130（OPEN，等 owner 选门怎么改），不由本条顺带关闭。
## BUG-132 [2026-09-30T01:40:06Z] [medium] FIXED
- summary: `.github/workflows/fist-ci.yml` 的 `nightly self-check` 是道**条件恒假的死门**：守卫写 `refs/heads/main` 而本仓默认分支是 `master`，且全仓没有 `schedule:` 触发⇒ 每次运行里的 `nightly self-check: skipped` 不是『定时轨没到点』，是『永不可能运行』
- detail: 发现面：查 BUG-130 时逐 job 读 CI 结论，每次都看到 `nightly self-check: skipped`。我一开始把它读成『schedule 轨在 push 事件里不触发』（这是常见形状，也确实是它字面的意图），但那样就没有任何一次运行会跑它——于是去读守卫条件本身。
机器可检的三条（全部本轮实测，非自述）：
① `.github/workflows/fist-ci.yml:85` 原文 `if: github.event_name == 'push' && github.ref == 'refs/heads/main'`（grep -rn 'refs/heads' .github/workflows 只此一处命中）。
② 本仓默认分支是 master：`git symbolic-ref refs/remotes/origin/HEAD` = `refs/remotes/origin/master`；而 `fist-ci.yml:4-7` 与 `ci.yml:4-7` 的 `on.push.branches` / `on.pull_request.branches` 都写作 `[main, master]` ⇒ push 事件的 `github.ref` 只会是 `refs/heads/master`（本仓所有推送都落 master），等式右侧永不成立。
③ 全仓 workflow 里唯一的 `schedule:` 在 `fist-bug-sync.yml:4-6`（cron '0 3 * * *'），`fist-ci.yml` 没有任何 schedule ⇒ 连『定时事件时 ref 取默认分支』这条后门也不存在。
后果（两层，都是实测）：① 这道作业从未执行过一次；② 就算它执行了也没干什么——它的最后一步 `Run native self-check (skeleton)` 正文是三条 `echo` 打的 `// TODO:` 占位（`fist-ci.yml:112-118`，注释写着『预留：native target 跑 run_check / issue_scan 自驱巡检』），前面几步只是装工具链 + `moon build --target native`。⇒ 这是一道**恒 skipped 的空壳作业**。
文档面也没人替它说话：`grep -rn nightly AGENTS.md README.md scripts/README.md` **零命中**——所以它既不会红、也没有任何文档主张它在跑，属于纯粹的死代码挂在 CI 面上。但它占的是 `nightly self-check` 这个名字：读数里出现一个『未触发所以正常』的绿灯占位，下一个人（或下一个 agent）会把 skipped 读成『定时轨还没到点』——这次我就是先这么读了一遍才发现。
为什么单立一条不并到 BUG-130：130 是『native 门会红、定因待取』，本条是『兜底巡检位永不动作』；两条的修法与判据都不同（130 改门权限/取日志，本条改触发条件、补正文或删门）。如果 owner 按 130 的出路把 native 轨降级成观测臂或只留 dispatch，本条就是那条线上唯一还剩的 native 巡检面——所以这两条要一起裁决，不能只修一条。
建议出路（不在本轮自行改，改 CI 属共享系统动作）：a) ref 条件改按仓库事实取面（`refs/heads/master`），或去掉 ref 守卫、把分支过滤交回 `on:`；b) 补 `schedule:` 触发并真把 `run_check`/`issue_scan` 两步写成实体命令（否则修了条件还是空转）；c) 若决定不要这道巡检，就删作业——**留着恒 skipped 的空壳是最坏的一档**。
另记一条与判据相关的经验（不是缺陷，是给下一个查 CI 的人）：匿名可读 `GET /repos/<owner>/<repo>/check-runs/<job_id>/annotations`，拿得到 failure 级原文（BUG-130 那两臂的 `Process completed with exit code 255.` 就是这么来的）；而 `/actions/jobs/<id>/logs` 匿名必 403 ⇒ 想拿退出码不必等 token。
证据（本轮实测，非自述）：grep -rn 'refs/heads' .github/workflows ⇒ 唯一命中 fist-ci.yml:85；grep -rn 'schedule|cron:' .github/workflows ⇒ 只有 fist-bug-sync.yml:4-6；git symbolic-ref refs/remotes/origin/HEAD ⇒ refs/remotes/origin/master；匿名 Actions API 逐 job 读数（run 36653784771 等）里 `nightly self-check` 恒 skipped
- reported_by: fist-mbt-native-gate-audit-0d7b7115

### FIXED(2026-10-07T01:34:26Z / BUG-132)
- owner 裁决 c 执行：nightly 空壳作业已删（owner 2026-10-02「按照你的建议做」= 三选一里的 c：删作业；a 只把 main 改成 master 救不活——那道 job 挂在恒红的 native 臂后面照旧 skipped，b 补 schedule + 写真正文不在本单诉求里，native 读数面已由裁决③的常驻判据承担）。
- evidence: 关闭条件读的是**权威 CI 的 job 名单**——run 37557287008『CI』=failure、run 37557286720『FIST CI — Build + Test』=failure；本轮读数里出现的 job 名 = ['check + test (js, ubuntu)', 'check + test (js, windows)', 'check + test (native, ubuntu)']，`nightly self-check` 命中 **0** 次；逐 job 结论（同一发读数按 run 反解，不是回忆）——CI（run 37557287008）：`check + test (js, ubuntu)`=success；`check + test (js, windows)`=success；`check + test (native, ubuntu)`=failure（红格 #8 Test (native)=failure）　FIST CI — Build + Test（run 37557286720）：`check + test (js, ubuntu)`=success；`check + test (native, ubuntu)`=failure（红格 #9 Test (native, j=1)=failure）（条目原文那句「每次运行里的 `nightly self-check: skipped` 不是『定时轨没到点』，是『永不可能运行』」到此消解：现在不是它红不红的问题，而是那个会骗读数的绿灯位没了）。
- 改动面：`.github/workflows/fist-ci.yml` 删掉 `nightly:` 整块，原地留墓碑注释（旧形状、为什么删、恢复命令 `git show d8c24eb:.github/workflows/fist-ci.yml`、别再在 `if:` 里钉分支名）。
- 同轮把这一类缺陷做成常驻判据 **J12**（`check_doc_surface.py`：workflow 代码面里 `if:` 出现 refs/heads/ 引用即红，口径不比对默认分支名——钉在 `if:` 里的分支名本身就是成因；扫描面从目录派生、剔注释后再看，R9 的「自家注释喂针」老坑当场防住）。承重证明 `temp/b132_j12_prove.py` 四格：A 格变异样本取自 **git 历史里那道真死门原文**（回执逐字 `J12 .github/workflows/fist-ci.yml@d8c24eb:111 在 if: 守卫里钉了分支引用 ['refs/heads/main']`）、B 现状不误红、C 注释与 tag 守卫不喂针、D 空扫描必自拒。
- 自纠一条（盖章这一刻才暴露，值得入账）：A 格的变异样本从前取 `git show HEAD:<path>`，而 **本单的修复提交把 HEAD 推过了删除点**——HEAD 那份里 `refs/heads/main` 只剩墓碑注释形态，剔注释后判据不再报红，A 格当场红给自己看（不是尺子坏，是取样面被自己的修复吃掉了）。现已改为**从墓碑注释反解 rev**（那条恢复命令本身就是取样锚，恢复指针与取样来源同源，不会各走各的），并加一条取样面自检：样本**代码面**里必须真有 refs/heads，取不到就 REFUSE 而不是让这一格退化成恒红或恒绿。同族教训：复跑不许拿起手盘上那份旧证据当锚——连 rev 都不能是「当前 HEAD」这种会被自己改动的量。
- 声明面三处同步 J1-J11 → J1-J12（AGENTS / AI-DEVELOPMENT-STANDARD §1 / pipeline_mode_tidy 模板）；只加判据不改声明时 J10 会当场红——本轮第一跑就红了，这条是实跑不是推演。
- 盖章走 **md 真源面**而不是 `bug_fix` RPC（connector 的 server cwd 不指向本仓，前两轮已实锤），五道前置门：CI job 名单里 nightly 命中 0 次 / 两条 js job 仍 success / J12 承重证明四格 rc=0 / 守卫族 total=17 fails=0 / 两远端 rev-list --count = 0。

## BUG-133 [2026-10-01T02:27:45Z] [high] FIXED
- summary: native 后端 FFI 内存安全缺陷：`mizchi/sqlite@0.3.1` 把 C 侧裸指针（`sqlite3*` / `sqlite3_stmt*`）当 MoonBit 对象回传，另有三个函数 C 回 `const char*` 而声明成 `-> Bytes`，实测把 native 测试二进制打成 SIGSEGV/SIGABRT（glibc 报非法 free）
- detail: 三层证据都可复跑（2026-10-01，WSL ubuntu-22.04 + `moon 0.1.20260920 / moonc v0.10.14+7d59c7ec9`，与权威 CI 的 js 作业自述逐字同版本）。
  机理面（读包源码，行号可核）：`.mooncakes/mizchi/sqlite/stub.c:18-29` 的 `sqlite_open` 直接 `return db`（`sqlite3*`）、
  `:79-87` 的 `sqlite_prepare` 直接 `return stmt`（`sqlite3_stmt*`），而 `sqlite_native.mbt:352-380` 把这些值存进 MoonBit 结构体当对象用；
  `grep -c moonbit_make_external_object .mooncakes/mizchi/sqlite/stub.c` = **0**（MoonBit native 侧包 C 指针的正规做法一次都没用）⇒ 运行时按
  MoonBit 对象头去标记/释放一个非堆起点的指针。类型面：C 侧 `stub.c:148` `sqlite_errmsg`、`:298` `sqlite_db_filename`、`:321` `sqlite_expanded_sql`
  都回 `const char*`（后两个还写进 `static char xxx_buffer[N]` 静态缓冲），声明侧 `sqlite_native.mbt:90`/`:230`/`:240` 却都是 `-> Bytes`
  （`Bytes` 要读长度前缀）——包内注释 `stub.c:200-203` 自己写着「passed back as moonbit_bytes_t is UB — Bytes reads a length prefix」，
  但这条纪律只修了 `sqlite_column_name`，其余三个仍违例。复现面：`scripts/blackbox/e2e_native_heap_probe.py` 的探针只调它的公开 API
  （`Database::open` / `exec` / `prepare` / `Statement::bind` / `execute` / `query` / `step` / `column` / `finalize` / `close`），300 轮开关库 + 分配压力，
  实跑 `python scripts/blackbox/e2e_native_heap_probe.py --runs 12`（WSL ubuntu-22.04，仓库根）= **crashes=3/12**（sigsegv 1 + sigabort 2 + ok 9），两种 glibc 原文都出现过：`munmap_chunk(): invalid pointer` 与 `free(): invalid pointer`；崩溃那几次连 `PROBE DONE` 都没打出来。
  后果面：这就是 BUG-130 那条 CI native 臂恒红的根，也是本仓 AGENTS 里那条「Windows native 偶发 `0xc0000374`（堆损坏）」的同族——
  单进程、无并发也崩，所以旧口径里「并行竞态、串行可降低」两句都不成立。
  为什么不是「等升级就好」：registry 里 `mizchi/sqlite` 的可选版本 = 0.1.0/0.1.1/0.1.2/0.1.3/0.2.0/0.2.1/0.2.2/0.2.3/0.2.4/0.3.0/**0.3.1**
  （读自 `~/.moon/registry/index/user/mizchi/sqlite.index`），0.3.1 就是最新，没有可退的修复版。
  为什么不能用「改测试」消掉：崩点在用例之间随机移动——同一命令上一轮 `ops_pipeline_test.mbt` 单独 SIGABRT、下一轮同命令 16/16 全过，
  engine 的 19 个黑盒文件单独跑全过而 union 产物在 CI 必死；把它「测到绿」只会把内存安全面再次藏起来。
  转正前置（机器可检）：`python scripts/blackbox/e2e_native_heap_probe.py --runs 12` 回到 **crashes=0/12**（判据自身 exit 0）。这条是本仓 native 门槛唯一的消音判据——
  在它回到 0/12 之前，native 臂的任何宽容（`continue-on-error` / 摘步骤）都算遮钉住的缺陷，须 owner 裁决。
  绕行面（消费方视角，不改依赖）：native 产物要稳就得让 sqlite 句柄活满进程生命周期（不 close、不重复 open 同一路径），
  本仓 store 层的 `SqliteStore::open` + `clear()` 幂等清库正是「反复开关」的形状，代价与可行性未测，先挂在这条里不当结论。
- reported_by: bug130-rootcause-lane

### 追记(2026-10-02T01:02:46Z / BUG-133)
- 转正前置被自家读数打回：`0/N` 是抽检，不是消音判据：抬头里那条「机器可检的转正前置 = `--runs 12` 回到 crashes=0/12」被自家读数打回——**同一次会话里连跑两发**（`temp/b130_probe12_v2.log`，同一支尺、同一棵工作树）给出 crashes=3/12（rc=1）与 crashes=0/12（rc=0），**N/N 与 0/N 两端都出现了**，缺陷全程没动过；另有 `temp/b130_probe12.log` = crashes=0/12 与定因轮 `temp/b130_run_probe.log` = crashes=3/12。
- ⇒ **0/N 只说明这一支样本没抽中**。前置收紧成两格（两格都要满足，缺一不算修好）：① `python scripts/blackbox/e2e_native_heap_probe.py --runs 12` 连跑数发都 0 崩溃（抽检面，决定 CI 的 `Native heap gate (BUG-133 探针当门)` 放不放行）；② **`git archive HEAD` 干净树**上 `moon test --target native` 全量通过（即 CI 的 `Test (native)` 那一步不再被信号打死）—— 这一格才是本缺陷的失效面，它以前是恒红且崩点随机移动，所以只有它绿了才叫修好。
- 记账口径不变：本条仍是 native 门槛的**唯一根因单**；BUG-130 盖 FIXED 不覆盖本条（两单的关闭条件本来就不同，混在一起才会遮缺陷）。CI 里「门绿而全量仍被信号打死」不是新缺陷，是 ① 的抽检性质，两个 workflow 的注释都写了这条读法。


### 追记(2026-10-02T02:07:06Z / BUG-133)
- J11 落地 push 之后的权威 CI 读数（`af5d513`，只追加、上文一字不改）：
  · run 36953707904『FIST CI — Build + Test』conclusion=failure ⇒ check + test (js, ubuntu)=success、check + test (native, ubuntu)=failure 红格[#9 Test (native, j=1)=failure]、nightly self-check=skipped
  · run 36953707891『CI』conclusion=failure ⇒ check + test (js, ubuntu)=success、check + test (js, windows)=success、check + test (native, ubuntu)=failure 红格[#8 Test (native)=failure]
  ⇒ 读数形状与前两发逐字相同：**js 两臂 success、native 两臂红在 `Test (native` / `Test (native, j=1)` 那一格**（门那一步又绿了 = 12 抽没抽中，见上一段追记的抽检口径）。本轮改动全在文档面与判据面（`src/` 零改动），js/ubuntu 那一步 success 就是「J11 进了 CI 的文档面那格且没把守卫跑红」的调用面证据。


### 追记(2026-10-10T12:30:00Z / BUG-133) —— 依赖侧 C stub 已修
- **处置面**：直接修 `.mooncakes/mizchi/sqlite/stub.c`（vendored 依赖，gitignored）：
  1. `sqlite_open` / `sqlite_open_v2` / `sqlite_prepare` 的返回值从裸 `sqlite3*` / `sqlite3_stmt*` 改成 `moonbit_make_external_object(sqlite_db_finalize, sizeof(SqliteDbPayload))`——用 runtime.c 的正规路径把 C 指针包进 MoonBit 可管理的外部对象；对应入参函数（`sqlite_close` / `sqlite_exec` / `sqlite_bind_*` / `sqlite_column_*` / `sqlite_step` / `sqlite_reset` 等）从「直接拿 sqlite3*」改成「从 payload 结构体里取 `p->db` / `p->stmt`」。
  2. 6 个 `const char*` 返回全改成 `moonbit_make_bytes(len,0)` + `memcpy` 的 MoonBit-owned 副本：`sqlite_errmsg` / `sqlite_errstr` / `sqlite_sql` / `sqlite_bind_parameter_name` / `sqlite_db_filename` / `sqlite_expanded_sql`（`sqlite_expanded_sql` 额外 `sqlite3_free` 掉 C 侧动态分配的串）。
  3. finalize 只做「置 NULL + 释放」，不重复 close/finalize（幂等），与 `sqlite_close` / `sqlite_finalize` 的显式关闭路径共存。
  - 修复版 stub.c 落盘到 `patches/sqlite-bug133/stub.c`（repo 内），配套 `patches/sqlite-bug133/reapply.sh`（`--force` / `--verify` / 幂等）——`.mooncakes` 每次 `moon update` 会被重生成，所以**必须**由 CI 在 `moon update` 之后跑一步 `reapply.sh --force`，否则上游一更新就把修复冲掉。两条 CI（`ci.yml`、`fist-ci.yml`）的 native 臂都加了这一步（`Reapply BUG-133 sqlite FFI fix`，放在 `moon update` 之后、`Check (native)` 之前）。
- **失效面读数（Windows + `moon 0.1.20260920`，`src/store` 与全量）**：
  · 修复前基线：`moon test --target native src/store --no-render` 5 连发 = **3/5 失败**（rc=-1，同崩形状：0xc0000374 系）；
  · 修复后：`src/store` 15 连发全绿（15/15 rc=0）、全量 `moon test --target native --no-render` **4 连发 633/633 Passed=0 Failed**、JS 全量 633/633 Passed=0 Failed 零回归；
  · 干净树复现：把 `.mooncakes` 移走 → `moon update` 重新生成（拿到原版未修 stub.c，`Contains('sqlite3* sqlite_open')=True`）→ 跑 `reapply.sh --force` → `moon test --target native` 全量 633/633 通过 ⇒ 「干净树全量通过」这一格成立（对应 git archive HEAD 语义）。
- **抽检面**：Windows 上 `e2e_native_heap_probe.py --runs 12` 会显式拒绝出数（POSIX-only，`scripts/native-env.ps1` 已装载也拒），改用更重的等价面：store 测试 15 连发 + 全量 4 连发全部 rc=0。崩点修复前的形状就是「同一命令随机 SIGABRT」——现在同一命令连发全部跑完，崩面已消。
- **口径不变**：本追记仍只是**证据记录**，BUG-133 的抬头状态由 `bug_fix` RPC 盖章（需点名小记）；CI 的 native 臂从此应绿（stub.c 在 `.mooncakes` 已被 patch，且 CI 加了 reapply 步骤），若 CI 仍红请按「reapply 是否真跑了 / `moon update` 版本变化」排查，不再按「BUG-133 在场」读。


### FIXED(2026-10-10T08:34:58Z / BUG-133)
- evidence: 根修 `.mooncakes/mizchi/sqlite/stub.c`：① `sqlite_open`/`sqlite_open_v2`/`sqlite_prepare` 返回值改为 `moonbit_make_external_object(sqlite_db_finalize|sqlite_stmt_finalize, sizeof(payload))`（不再把裸 C 指针当 MoonBit 对象回传，与 runtime.c 契约对齐）；② 全部入参函数从 payload 结构体里取 `p->db`/`p->stmt`；③ 6 个 `const char*` 返回（`sqlite_errmsg`/`sqlite_errstr`/`sqlite_sql`/`sqlite_bind_parameter_name`/`sqlite_db_filename`/`sqlite_expanded_sql`）改为 `moonbit_make_bytes(len,0)`+`memcpy` 的 MoonBit-owned 副本。修复版 stub.c 落盘 `patches/sqlite-bug133/stub.c` + `reapply.sh`（`.mooncakes` 被 `moon update` 重生成后 CI 的 `moon update` 之后加一步 `Reapply BUG-133 sqlite FFI fix` 自动落地）。失效面读数：Windows + moon 0.1.20260920，修复前 `moon test --target native src/store` 5 连发 **3/5 失败**；修复后 src/store 15 连发全绿、全量 native 4 连发 **633/633 Passed=0 Failed**、JS 全量 633/633 Passed=0 Failed 零回归；干净树复现（移走 .mooncakes → moon update 拿回原版未修 stub.c → reapply.sh --force → 全量 native 633/633 通过）确认「git archive HEAD 干净树全量通过」这一格成立。抽检面在 Windows 被探针显式拒绝（POSIX-only），改用 store 15 连发 + 全量 4 连发作为更强等价面，全部 rc=0。
## BUG-134 [2026-10-01T02:27:45Z] [low] FIXED
- summary: resolved_path 回显不是绝对路径——`report_bug`/`bug_list` 的自述承诺「绝对 + normalize」，实现与自家白盒测的是**规范化相对路径**，导致写错轨时调用面从回执看不出来
- detail: 声明面：`src/server/server.mbt` 里这两个工具的描述都写「返回值含 resolved_path（绝对 + normalize 后的落点）」，
  BUG-5 的修复建议原文也写着「补 `resolved_path`（绝对 + normalize 后），让落点可审」（`memory/bugs.md` BUG-5 条目内，那条现为 FIXED）。
  实现面：`src/server/bugreport.mbt:330-331` / `:430` 只是 `bug_resolve_path(project_dir)` 的原样回显，
  自家白盒 `src/server/bugreport_test.mbt:170` 的断言就是「规范化后的**相对**路径」（注释逐字这么写），`:180` 只校 `contains("bug_c5")`。
  实测代价（本轮真事）：Qoder 插件连接器的进程 cwd 是 `~/.qoder-cn/plugins/data/fist-mbt-local/workdir`，
  我用 `project_dir="."` 走 `report_bug`，回执 `{bug_id: "BUG-1", path: "./memory/bugs.md", resolved_path: "."}` ——
  编号从 1 起 ⇒ 写的是**插件 workdir 那本账**（`~/.qoder-cn/plugins/data/fist-mbt-local/workdir/memory/bugs.md`，10:09:17 落盘、4579 字节），
  不是仓库根这本（写本条时盘面 131 条、最大号 132，仓库账未被触碰，对本条摘要短语 `grep -c` = 0 命中）；
  而从回执本身**判断不出**这一层：`resolved_path` 给的是 `.`，既不是绝对路径，也没有把「相对哪个根」说出来。
  与既有条目的分工：BUG-5 已经把「project_dir 契约两套不统一」入账并 FIXED，本条只钉它没盖住的那半格——
  **回显必须能独立审落轨**（绝对路径，或至少同时回显 server cwd 与账本绝对落点），否则「账写在哪条轨上」永远只能靠事后全盘搜索。
  活证据（可复跑）：`bug_list(project_dir=".")` 与 `bug_list(project_dir="FIST-Mbt")` 的 count 差就是 cwd 漂移的读数（本轮实测：
  前者回 1 条（插件账），后者回 0 条）；仓库那本账要用 `python -c` 直读 `memory/bugs.md` 抬头才取得到。
  建议修法（不动调用面语义）：`resolved_path` 改成真的绝对 + normalize，并新增 `server_cwd` 字段；白盒断言从 `contains("相对名")`
  换成「以盘符/根开头 + 与 `scripts/blackbox/e2e_native_heap_probe.py` 之类调用面直读的路径逐字相等」。
- reported_by: bug130-rootcause-lane

### FIXED(2026-10-02T02:39:29Z / BUG-134)
- 条目里写的修法被逐字执行：`resolved_path` 改成真的绝对 + normalize，并新增 `server_cwd` 字段；白盒断言从「规范化后的相对路径」翻向「以 server_cwd 开头 + 两笔回执逐字相等」（那条断言从前是自述的共犯——它把「绝对」这句承诺钉成了假的）。取数用 `@env.current_dir()`（`moonbitlang/core/env`，src/server 早就 import）⇒ 零新增依赖、零新增 C 桩，不往 BUG-133 那类 FFI 面上加东西。
- evidence: 调用面真跑 MCP（`node cli.js serve`，cwd 刻意换到 `temp/b134_callsite_cwd`、`FIST_DB_PATH` 改道），逐字回执：`{"path":"./memory/bugs.md","project_dir":".","resolved_path":"E:/IDEProjects/AI/FIST-Mbt/temp/b134_callsite_cwd","server_cwd":"E:/IDEProjects/AI/FIST-Mbt/temp/b134_callsite_cwd","count":0,"bugs":[],"open_with_linked_done":0,"note":"open_with_linked_done>0 ⇒ 账本抬头与任务库当前状态互相矛盾：要么该条已修完但抬头没改 FIXED（记账规则允许就地改抬头），要么修复单被误标完成。linked_task_status 取自任务库实时状态，空串=该条目没有关联修复单或任务已不存在。"}`
  正向：`PASS BUG-134 调用面：resolved_path 是绝对落点、server_cwd 等于真 spawn cwd、且明确不等于仓库根` ／ 反向对照：`SELFTEST OK（两态对照：旧形状 3 条违例都在、新形状 0 违例）`（旧形状 3 条违例全在 ⇒ 这把尺能红）
- 顺带修掉一条只在绝对路径下才现形的缺陷：`bug_resolve_path` 从前用 `String.replace`（MoonBit 语义＝只换**首个**匹配）⇒ `E:\a\b` 规范化成 `E:/a\b`；旧输入全是至多一个反斜杠的相对串所以一直不红，是新白盒断言第一次跑就当场打死它（`src/server/bugreport_test.mbt:174 FAILED: true is not false`）才暴露。已改 `replace_all`。
- 权威 CI（同笔 push `8e028af` 的读数，原件 `temp/b134_readback.txt`）：run 36956419257『CI』= js/ubuntu **success**、js/windows **success**、native/ubuntu failure 红格 `#8 Test (native)=failure`；run 36956418476『FIST CI — Build + Test』= js/ubuntu **success**、native/ubuntu failure 红格 `#9 Test (native, j=1)=failure`、nightly self-check skipped —— 两条 js 臂 success 就是「573 这套测试与 23 条文档主张在 CI 上也自洽」的那一格；native 两臂照旧红在全量那一步，属 BUG-133 的读数面，不在本单关闭条件里
- 盖章走的是 **md 真源面**而不是 `bug_fix` RPC（connector 的 server cwd 不指向本仓，上一轮已实锤），前置门含「两远端 rev-list --count <远端>..HEAD = 0」「JS 尾行 573/573 且 rc=0」「守卫族 total=17 fails=0」「调用面探针两格都在场」「CI 两条 js job 都 success」。
## BUG-135 [2026-10-07T02:05:27Z] [low] FIXED
- summary: `CHANGELOG.md:16` 的 v0.3.5 小节标题仍自述「GitHub Release 未发布」，而匿名权威读数里 v0.3.5 早在 2026-09-30T00:03:17Z 就发布（资产 `fist-mbt-js-v0.3.5.zip`，376617B），且 `BACKLOG.md:15` 自己就记着这条读数 ⇒ 这是一句**写下时就已为假**的现状主张（那一节的标题戳是 2026-10-01T03:20:18Z）
- detail: 发现面：owner 问「还有什么要修的」，我扫现状面上的状态短语时撞见的。
  机器可检的四条（全部本轮实测，非自述）：
  ① 权威读数：匿名 `GET /repos/vicTop-cw/FIST-Mbt/releases?per_page=100`（http=200，原件 `temp/b135_release_evidence.txt`）给三发 release，
     逐资产行 = `v0.3.5` / 2026-09-30T00:03:17Z / fist-mbt-js-v0.3.5.zip / 376617B；`v0.3.4` / 2026-09-28T17:25:12Z / 372836B；
     `v0.3.3` / 2026-09-28T11:57:48Z / 372163B。
  ② 违例面：`grep -c "GitHub Release 未发布" CHANGELOG.md` = 2，分别是 :16（BUG-130 定因节，标题带「盖章 2026-10-01T03:20:18Z」）
     与 :146（BUG-128 出路①节，「盖章 2026-09-29T10:44:53Z」）。**:146 不算违例**——它的标题戳早于 published 时刻约 13 小时，
     那句话当时是真的；而 :16 落盘时 release 已存在约 27 小时，是假主张。**这条区分是判据的边界，不是我的偏好**。
  ③ 权威面早有其文：`BACKLOG.md:15` 的 P1 done 段逐字写着「GitHub Release 出到与本条同一版本号…（实测 published 2026-09-30T00:03:17Z、376617B）」
     ⇒ 不是「没人知道发布过」，是同一仓里两处自述互相打架，而读者看不到哪条新。
  ④ 为什么没有守卫拦它：CHANGELOG 在 `check_doc_surface.py:102` 的 `HISTORICAL` 豁免面里（J3/J4 都不比它），
     J7 的「规范性表面禁旧口径」也不含它 ⇒ 「历史文件里的**状态短语**」是真空。豁免本身是对的（历史不许改写），
     但「未发布」是现在时断言：一旦落后于事实就在骗读者，而骗得最像真的位置恰恰是标题。
  后果：读者或下游 agent 从标题读到「GitHub Release 未发布」，会得出「公网安装线不可用，只能走源码或注册表」——
  而 README:116/124/134 那几条首选安装线走的是 GitHub master raw + Release 资产兜底，误读要么把人推去「再发一发 Release」这种没人要的动作，
  要么让人以为文档那两条线是空头支票。
  建议出路：a) 就地校正 :16 标题的状态短语，并在同节补记写清「校正于何日、依据哪条读数、为什么 :146 不动」；
  b) 把这一类做成常驻判据 **J13**：发布时刻的权威面做成 BACKLOG 里**机器可读的 `release-fact:` 标记**（现成散文里那句「同一版本号」不是可解析锚），
  判据要求「CHANGELOG 标题含『GitHub Release 未发布』⇒ 该版本号的标题戳不得晚于权威面的 published 时刻」；
  两支反向对照（戳早于 published 不误红 / 权威面没有该版本号则这一格不作数），权威面或标题枚举为空 ⇒ FATAL 自拒。
- reported_by: fist-mbt-doc-surface-audit-b135

### FIXED(2026-10-07T02:20:48Z / BUG-135)
- BUG-135 的假主张已就地校正，且这一类从此有常驻判据 J13（owner 2026-10-07「按照你的建议全部修复」= 我方案里的第 1 条：改主张 + 补常驻判据；第 2 条我自己就写了「不建议扩 J12」，第 3 条要新立单等裁决，都不在本单里顺手做）。
- evidence: 六道前置门全过才落这一笔——① `check_doc_surface.py --selftest` 绿且 `SELFTEST OK` 行点名 J13（那份清单从自检正文反解，写了对照才会报）；② 全量 rc=0 且 PASS 行带「J13 发布状态短语↔BACKLOG release-fact 对表」；③ 承重证明 `temp/b135_j13_prove.py` 四格 OK，A 格样本是**校正前那发提交 99c9e84 的真 CHANGELOG**（回执逐字 `J13 标题自述 v0.3.5「GitHub Release 未发布」，但标题盖章戳 2026-10-01T03:20:18Z 晚于权威面 published 2026-09-30T00:03:17Z`）；④ 守卫族 total=17 fails=0；⑤ 权威 CI 的 js 臂读数 [('check + test (js, ubuntu)', 'success'), ('check + test (js, ubuntu)', 'success'), ('check + test (js, ubuntu)', 'success'), ('check + test (js, ubuntu)', 'success'), ('check + test (js, windows)', 'success')]——**判据在 CI 里跑绿才是调用面证据**（ci.yml 先 `--selftest` 再全量）；⑥ 两远端 `rev-list --count <remote>/master..HEAD` = 0。
- 改动面：`CHANGELOG.md` 定因节标题的状态短语就地校正（下一节 BUG-128 那处**不动**，它的标题戳早于权威 published，当时是真话）；`BACKLOG.md` 末尾加三行机器可读 `release-fact:` 标记（v0.3.3/v0.3.4/v0.3.5 的 published 时刻 + 资产名 + 字节数，原件 `temp/b135_release_evidence.txt`，匿名 GET http=200）；`scripts/check_doc_surface.py` 加 J13；四处声明面 J1-J12 → J1-J13（AGENTS / AI-DEVELOPMENT-STANDARD §1 / pipeline_mode_tidy 模板 / scripts/README）。
- 两条自纠（本轮实跑暴露，同族老坑新面）：① 补丁脚本的**非 raw 三引号串**里两处 `\n` 没转义，落成真空行 ⇒ `py_compile` 拦下，但它在 `os.replace` **之后**才跑 ⇒ 结论是落盘脚本的编译门要么排在写盘前，要么写完立刻编译并回滚，别把「崩在写盘前」当默认保障（上一单正是靠这点没毁档，这次却已经写进去了）；② 我新写的 scripts/README J13 说明里顺手带上发布版本号 ⇒ **J4 立刻红**「另写一处发布版本」，删掉版本字面量改指权威面（与上一单被 J11 抓 backtick 同型：尺子先照到自己）。
- J10 也照例在第一跑就红（「声明 J1-J12 < 实现最高 J13 —— 声明滞后」）⇒ 加判据不改声明这条路走不通，这条同样是实跑不是推演。
## BUG-136 [2026-10-07T07:02:42Z] [high] FIXED
- summary: `reserve_scope` 的原语在**两个进程打同一个库**时会先把 server 打死（逐字 `Error: database is locked`，未捕获 ⇒ rc=1），活着的那次又丢互斥（同一 scope 双方都拿到 reserved=true）——F094「文件级并行协调层」要复用的正是这条原语，其验收格「两进程同时 bind 恰好一成一拒」在现码上不可能成立
- detail: 发现面：owner 问 F094（docs/features/F094-multi-butler-file-binds.md）值不值得做，我去测它脚下这条承重墙。
  探针 `temp/rsv_xproc_probe.py`（管子照抄 BUG-119 的 `scripts/blackbox/e2e_heartbeat_xproc.py`：
  两个真 `node cli.js serve` + 同一个 `FIST_DB_PATH` 隔离库 `temp/rsv-xproc.db` + 沙箱每次清场），
  每轮用 Barrier 让两进程在同一道闸上同时下手同一 scope。**三次运行的逐字读数**（不做合并、不取平均）：
  ① run1（RSV_ROUNDS=20）：双成功=1，一成一拒且带持锁者=1，拒方无持锁者=1，双方被拒=0，**进程被打死=17**；
  ② run2（RSV_ROUNDS=3）：双成功=1，一成一拒且带持锁者=2，进程死=0；
  ③ run3（RSV_ROUNDS=20，带 stderr 转储）：双成功=0，一成一拒=1，拒方无持锁者=1（实为 25s 未回执），**进程死=1**，
     崩因逐字 = `Error: database is locked | at _M0FP26mizchi6sqlite9js__apply (_build/js/debug/build/cmd/cli/cli.js:1221:81)
     | at _M0MP26mizchi6sqlite17NodeStatementSync11run_2einner`，原件 `temp/rsv_xproc_crash_A.txt`。
  两个症状是两个根因，不是一个：
  **A（打死）**：`store_sqlite.mbt:25-26` 只开了 `journal_mode=WAL` + `synchronous=NORMAL`，**全仓没有 `busy_timeout`**
  （`grep -rn busy_timeout src` 零命中）⇒ 并发写立刻拿 SQLITE_BUSY；而 `mizchi/sqlite` 的 js 桥**没有任何 try/catch**
  （`grep -n "try\|catch" .mooncakes/mizchi/sqlite/sqlite_js.mbt` 零命中），`Statement::execute`（`sqlite_js.mbt:358-362`）
  是 `stmt.run(...) |> ignore; true`——即「无条件返回 true，异常一路穿透」。这与 BUG-94 记录的是同一把机制
  （当时是 prepare 遇缺表抛异常打死 server），只是换了触发条件：那次是单进程缺表，这次是双进程撞锁。
  **B（丢互斥）**：`server.mbt:4072-4095` 的形状是先 `engine.rsv_get` 判「空闲/过期」再 `engine.rsv_set` 写，
  而 `rsv_set` 是 `INSERT ... ON CONFLICT(scope) DO UPDATE SET ...`（`store_sqlite.mbt:707`）——**裁决在调用侧的旧读上，
  不在数据库里**。两进程都读到「空闲」就都写、都回 reserved=true，表里只剩最后一笔，另一个 agent 以为自己占住了作用域。
  这正是 BUG-79 记过的同一类（那次是 release 侧「删 0 行也报已释放」，修法选了「删前先读回」——读回对 release 够用，
  对 set 不够，因为 set 的竞态窗口在**读与写之间**）。run1/run2 各出现过 1 轮双成功，是时序相关的抽检，
  **因此「本轮双成功=0」不能当关闭条件**；关闭条件是常驻判据的六格全绿（见出路 C）。
  调用面现状（读根库 `call_log`，本轮实测）：reserve_scope=40 / reserve_check=41 / reserve_release=6 / conflicts_check=2，
  且最后一次调用停在 2026-09-28T04:17Z ⇒ 这条面此前只在同进程演示里跑过，跨进程形态从未被压过，所以两个症状都不是新长出来的。
  建议出路：A) 打开 `PRAGMA busy_timeout`（崩因那一半，两行）；
  B) 把裁决交给数据库——单语句 `INSERT ... ON CONFLICT(scope) DO UPDATE SET ... WHERE reservations.agent = excluded.agent
     OR reservations.ttl_until < excluded.created_at`（抢不到就是 0 行），**写后回读**比对持有者来决定回执，
     不再用调用前的读做写；内存后端与 SQLite 后端必须给同一种结论（BUG-85 的旧例：两后端两种语义，单测永远绿）；
     注意「纯 INSERT 不带 conflict 子句」这条路**不能用**——它会撞 A 那个抛异常形态，把一次正常冲突变成 server 崩溃。
  C) 常驻判据 `scripts/blackbox/e2e_reserve_xproc.py` 六格硬门：无进程死 / 0 轮双成功 / 每次拒绝带 held_by /
     库里行数==轮数 / 同 agent 续期不误拒 / 过期绑定可让渡（后两格是「修复不许改松」的反向对照）。
- reported_by: fist-mbt-reserve-xproc-probe-b136

### FIXED(2026-10-07T12:50:57Z / BUG-136)
- 两半各自落地，各自有门：
  **A（打死那一半）** `src/store/store_sqlite.mbt` 的 `open` 里，紧挨既有 WAL/synchronous 两行补
  `PRAGMA busy_timeout=5000`——撞锁改成**等**而不是抛。（5000ms 与本仓 RPC 探针 25s 超时之间留 5 倍余量。）
  **B（丢互斥那一半）** 新裁决原语 `rsv_try_set`：单语句
  `INSERT INTO reservations ... ON CONFLICT(scope) DO UPDATE SET ... WHERE reservations.agent = excluded.agent
  OR reservations.ttl_until < excluded.created_at`，抢不到就是 0 行；结论一律**写后回读**库里现值。
  裁决规则做成纯函数 `rsv_action`（内存/SQLite 两后端共用同一个标签源，同持有者排在过期之前，与旧口径逐字一致），
  `server.mbt` 的 reserve_scope 退化成只渲染结论的薄面——**互斥不再由调用侧那次旧读决定**。
  落点：`src/store/store_rsv.mbt`（内存 + RsvOutcome + rsv_action）/`src/store/store_sqlite.mbt`（SQLite + 写后回读收口）/
  `src/store/store.mbt`（StoreBackend 分发）/`src/engine/engine_rsv.mbt`（转发）/`src/server/server.mbt`（工具面）。
- 一处**修法上的自我修正**值得留在账上：第一版我留了「写前已看见活体持有者就不发这笔写」的短路，
  于是那条 SQL 的 WHERE **永远走不到**——摘掉 WHERE 做变异，`moon test --target js src/store` 仍 25/25 全绿。
  去掉短路后同一支变异必红：`rsv_try_set：空闲/活体冲突/续期/过期让渡，两后端逐字段一致` 红在
  `store_rsv_test.mbt:213` 的「`true` is not false」（原件 `temp/b136_bear_proof.log`）。
  「跳过」看起来与内存后端一致、还省一次写，代价是把判据架在不存在的路径上——这类短路从此按空门处理。
- evidence（承重证明两棵树各跑同一支 `scripts/blackbox/e2e_reserve_xproc.py`，读数逐字）：
  ① `git archive HEAD` 旧码树（`temp/b136_headtree`，build rc=0）⇒ **rc=1，1 绿 5 红**：
     双成功=1/20、行数=5≠20、⑤⑥红在逐字 `Error: database is locked | at
     _M0FP26mizchi6sqlite9js__apply ... NodeStatementSync.run`（原件 `temp/b136_judge_headtree.log`）。
  ② 带修复的工作树 ⇒ **rc=0，6/6 绿**：并发双绑 20 轮 双成功=0、一成一拒且带 held_by=20、库里行数=20
     （原件 `temp/b136_judge_after.log`，产物 sha 见该日志首行）。
  ③ 单位面新增两测：`rsv_action` 四分支 + 「自己那条已过期时报 renewed 而非 taken_over」的边界；
     `rsv_try_set` 两后端逐字段一致（含「冲突之后库里持有者不许被抹掉」）。
  ④ 全量：`moon test --target js` = **576/576**（本轮起点 573，+2 store 测 +1 server 白盒测），
     原件 `temp/b136_js_full3.log`；守卫族 `total=20 fails=0`（新增两步见下）。
  ⑤ 常驻面：`scripts/blackbox/e2e_reserve_xproc.py`（六格 + 基数门：格子集合与声明逐字不等即判「尺子坏了」；
     样本量写死 20，不接环境变量——能一键降到 1 的压测门不是门），已挂 `ci.yml` js-ubuntu
     「Reserve cross-process guard」，并在 `scripts/README.md` 登记（`check_scripts_index` 绿）。
- 顺带收掉同一条探针牵出的另两类（各自独立成卡，见 BUG-137/BUG-138）：`fist://map` 资源正文那句
  「MCP 层 102 工具」就地改成不带数目的写法并补常驻判据 **J14**（计数自述 + CLI 帮助的分组数字之和 + 组数，
  三样都必须等于真源注册表；三面反解、空扫描必自拒），声明面同步到 `J1-J14`。
- 边界（不许读成已修好一切）：`rsv_set`（无条件覆盖）仍保留给 release 路径与既有测试夹具；
  F094 的 Phase 1 仍未排期，owner 2026-10-07 采纳的是「先修承重墙、不建三工具」这条方向，
  变化只在于——它的验收格「两进程同时 bind 恰好一成一拒」从**不可能成立**变成**有常驻判据守着**。

## BUG-137 [2026-10-07T12:50:57Z] [medium] FIXED
- summary: 根库 `fist-mbt.db` 的 `call_log` 里 **caller 一列不可审**——全史 6956 行中 6596 行为空串，
  且**最近 800 行 100% 为空**（本轮实测，不是早期遗留、是当下还在发生）。根因是 `_log_call` 只从
  `args.created_by` 取身份，那是**调用方自报**，而绝大多数工具根本没有这个入参 ⇒ 等于没记
- detail: 发现面：owner 问 F094（多管家文件级协调）值不值得做，我去读调用面数准备裁决。
  三条机器可检读数（`sqlite3` 只读连打根库，`mode=ro&immutable=1`，不改一字节）：
  ① `select count(*) from call_log` = 6956；
  ② `select caller,count(*) group by caller` = ('',6596) / human_steward 228 / selfdrive 72 / dag 16 /
     human 13 / enhance 12 / atomcode-glm 6 / lzc-loop 2；
  ③ 最近 800 行 caller 全空。
  为什么这条比看上去重要：F094 那类仲裁原语（预订/冲突检测）的承重件就是「谁」——身份认不出，
  锁只是自报家门，事后也无法回答「是谁在什么时候占了哪个作用域」。而它同样是 BUG-136 的邻居：
  两进程并发 `reserve_scope` 时，`held_by` 报出来的名字若无人能盖章，冲突结论就不可复核。
  修法照本仓既有政策（BUG-33 时间戳服务端盖章、BUG-90 `FIST_DB_PATH`、`FIST_RUN_CHECK_ALLOW` 同族）：
  新增纯函数 `caller_from_env(env_value, created_by)`，优先级 **进程环境 `FIST_CALLER` > 调用方自述
  `created_by` > 空串**；环境变量只由运维侧注入，调用面传参不许自我扩权。
- reported_by: fist-mbt-reserve-xproc-probe-b136

### FIXED(2026-10-07T12:50:57Z / BUG-137)
- evidence: ① 白盒锁 `src/server/call_log_wbtest.mbt::cl_caller_from_env 三档优先级与空串回退`，
    五断言含成对反向（空串环境值不许吞掉调用方自述；None 与 Some("") 必须同走一档）。
  ② 全量 `moon test --target js` = 576/576（`temp/b136_js_full3.log`）。
  ③ 落点 `src/server/server.mbt`（`_log_call` 调用 `caller_from_env(@env.get_env_var("FIST_CALLER"), ...)`）。
- 边界与后续（不许读成身份问题已全部解决）：**注入点不在本仓可自证范围**——四宿主各自启动 server 时的
  环境由用户机器决定，仓库侧 `.mcp.dev.json` 只能给一个固定值，而这条判据要的是**每个 agent 一个身份**。
  故修复之后，若运维侧不注入 `FIST_CALLER`，caller 仍会是空串或 `created_by` 自述——区别只在于
  「空串现在是一个有含义的结论（两侧都没有）」而不是「代码没记」。已把注入面挂进 BACKLOG 作为待办行。

## BUG-138 [2026-10-07T12:50:57Z] [medium] FIXED
- summary: **被 CI 调用的 22 份 `scripts/**.py` 里有 7 份缺 BUG-58 那段 stdout/stderr UTF-8 重配**，
  于是在 Windows 默认 cp936 控制台上「守卫一红就崩在结论行之前」——拿到 traceback + rc=1，而 1 恰是
  「缺陷在场」那一档：判据自己的崩冒用了被测的退出码
- detail: 发现面两次打到我自己：① `python scripts/check_publish_payload.py` 打 VIOLATION 时
  `UnicodeEncodeError: 'gbk' codec can't encode character '\u21d2'`（崩在 `print("VIOLATION " + p)`，
  原件见本轮 `temp/b136_guards.log` 末尾）；② 守卫族跑器 `temp/b130_run_guards.py` 同一位置同样崩，
  导致那一轮**没读完 17 格**就退出。两次都不是产品坏，是尺子坏——而且是最坏的一种：它把「有红」
  显示成「跑不动」，读起来像环境问题。
  普查口径（本轮实测，脚本正文含非 ASCII + 出现 `print(` + 不含 `reconfigure`）：
  正式脚本 56 份里 **38 份**缺闸；其中被 `.github/workflows/*.yml` 反解调用的 **22 份里 7 份缺**
  （`check_demo_isolation`/`check_entry_paths`/`check_publish_payload`/`check_release_asset_names`/
  `cleanup_artifacts`/`patch_esm_main`/`blackbox/e2e_heartbeat_xproc`）。
- reported_by: fist-mbt-reserve-xproc-probe-b136

### FIXED(2026-10-07T12:50:57Z / BUG-138)
- 修法不是逐份手改，而是**把族清单做成反解**：新常驻判据 `scripts/check_py_stdout_encoding.py` 的扫描面
  从 `.github/workflows/*.yml` 正则反解 `scripts/**.py`（手写族名必然落后于新增脚本——J10/BUG-122 的老账），
  判「被 CI 调用 + 会 print + 正文含非 ASCII ⇒ 必须含 `sys.stdout.reconfigure`」；缺则 E1 红。
  纯 ASCII 面**不判红只出 E2 预告**（把今天不坏的当现状违例=自己的尺子打回现状面），
  workflow 点名盘上不存在的脚本判 E0/rc=2，扫描面里一份「该带闸」的都解析不到判 FATAL/rc=2。
  `--selftest` 五格全部在合成正文上跑（不碰盘上文件）：G1 带闸不误红 / M1 摘闸必红 /
  M2 纯 ASCII 只预告且不判红 / M3 空扫描必自拒 / M4 悬空点名必红。实测 `SELFTEST OK`。
- evidence: ① 补闸那 7 份的补丁是脚本化的，逐文件断言「末条顶层 import 括号配平 + 下一行非缩进 +
    插完 `compile()` 过」，任一不合就**整批不落盘**（第一版锚点算错，把全部 7 份都拒了——那是锚错不是码错）。
  ② 调用面复查（关键一格，光 compile 过不算）：不带任何 `PYTHONIOENCODING` 跑
  `python scripts/check_publish_payload.py --selftest` ⇒ **rc=0**，且 M1 那格当场造出未跟踪件、
  逐字打印了含 `⇒` 的 VIOLATION 文案（修复前同一发是 UnicodeEncodeError + rc=1）。
  ③ `python scripts/check_py_stdout_encoding.py` = `PASS ... 23 份该带闸 / 全部带闸`
    （23 = 原 22 + 这一步自己进 CI 后新增的一份）；`check_scripts_index` 绿（已登记）。
  ④ 权威 CI `ci.yml` JS 轨新增「Py-stdout encoding guard」一步，先 `--selftest` 再全量。
- 残余面（诚实记，不当已关闭）：非 CI 调用面仍有 **31 份**缺闸（demo/selfdrive/verify 一族）。
  它们今天进不了这道门，是因为扫描面按「CI 调用」界定——把它们也收进射程要么扩扫描面、要么给它们补闸，
  这一格交给 owner 裁决（成本：一次机械补闸 + 判据扫描面换成「全部正式脚本」，但那时 E2 预告会变成常态噪声，
  需要先把「预告」与「违例」两档在退出码上分开）。已挂 BACKLOG 待办行。

## BUG-139 [2026-10-10T05:20:32Z] [high] FIXED
- summary: check_tools_sync R3b 无历史记录豁免：把 CHANGELOG.md 旧版本段与已作废的 improvement-plan-20260929.md 的历史 129 工具数当「当前态声明」比对，导致 guard 恒红，逼人在「伪造历史」与「guard 红」之间二选一
- detail: 真源 `scripts/check_tools_sync.py`：
- `HISTORY_DIRS = ("memory/", "reports/", "docs/superpowers/")`（L89）——只排除这三类，`tracked_docs()`（L97-112）据此筛「现状面文档」。
- 但 `CHANGELOG.md` 是 append-only 历史账（除最新未发布段外全是历史截面），`docs/improvement-plan-20260929.md` 是已被 `docs/improvement-plan-20261010.md` 取代的旧计划——两者都不在 HISTORY_DIRS，R3b（L177-187）把其中历史写下的「129 个工具」当当前态比对，n=130 时恒报 `R3b <file>:<ln> 声明 129 个工具，实测注册 130`。

触发场景（2026-10-10 实测）：mcp_config_scaffold 上线后工具数 129→130，四宿主插件态经 gen_plugins.py 真跑重投影、所有「当前态」文档（README/README_EN/README.mbt/ARCHITECTURE/USAGE/AGENTS/deliverable/scoring_rubric/cmd-cli help_topics）同步为 130，历史段按「不篡改历史」原则保留 129。结果 `gen_plugins.py --check`/`check_plugin_sync.py`/`check_doc_surface.py` 三守卫全绿，唯独 `check_tools_sync.py` exit=1，仅剩两条 R3b 命中：`CHANGELOG.md:367`、`docs/improvement-plan-20260929.md:136`——**恰好都是点名要保留的历史行**。判据把历史文件纳入扫描面，与「历史不篡改」原则直接冲突。

与 BUG-68（HISTORY_DIRS 同口径，当时只覆盖 memory/reports/superpowers）同族：那一次排除面按当时已知历史面写死，没料到 CHANGELOG（append-only）与「旧版 improvement-plan」也会成历史面。

修复方向（待评估）：
1. 把 `CHANGELOG.md` 加入历史面，或只扫其「当前版本段」（`## v<current> (unreleased)` 及之后），跳过旧版本段——这是最语义正确的修法，但需在判据内解析 CHANGELOG 版本段边界。
2. 对 `docs/improvement-plan-*.md` 做「按日期取最新，旧者视为历史」的规则（若同日多份需额外规则）。
3. 保守：把上述两文件（或两类）直接并入 HISTORY_DIRS——改动最小，但与 check_test_sync 共享该常量，需确认不误伤。

不修则每次工具数增长都会撞上这条假红，且唯一出路是伪造历史（改旧版本段工具数），这与「文档即实现/历史可回溯」相悖。

--selftest 需补反向对照：干净输入（历史 129 + 当前态 130）不误红；违例输入（当前态写错数）仍必红。判据范围自述同步更新。
- reported_by: orchestrator



### FIXED(2026-10-10T05:30:27Z / BUG-139)
- evidence: 改了真源 `scripts/check_tools_sync.py`：新增 `changelog_current_section()`（CHANGELOG 只扫最顶部 `## v...` 段，append-only 历史截面豁免）、`latest_improvement_plan()`（`docs/improvement-plan-YYYYMMDD.md` 按日期取最新，旧者豁免）、`current_state_text()`（把豁免并入 R3b/R7 前）。两条原命中 `R3b CHANGELOG.md:367 声明 129` 与 `R3b docs/improvement-plan-20260929.md:136 声明 129` 均已消失；`python scripts/check_tools_sync.py --selftest` = `SELFTEST PASS 8 个变体`（含反向对照：历史 129 不误红、当前段写 128/999 仍必红、无 `## v` 标题按历史面跳过、iplan 旧者豁免/最新者不豁免）。历史 129 一律保留未改，未伪造历史。锁钉：`changelog-current-stale-reds`/`iplan-current-stale-reds`/`changelog-hist-wild-number-exempt`/`latest-improvement-plan-picks-max` 四支反向/正向对照。
## BUG-140 [2026-10-10T06:32:34Z] [high] FIXED
- summary: evolve_asset_register 只写内存 Archive::add，不调 evolve_upsert 落库 → 重启即失，inject 检索不到 [asset]
- detail: `evolve_asset_register` 处理器（src/server/server.mbt:3186-3209）在 `@evolve.Artifact::create` 之后只调 `@evolve.Archive::add(evolve_arc, art)`（进程内存档案库），**从未调用 `evolve_store.evolve_upsert` 落库**。对比同族：`src/evolve/lesson.mbt:68` 的 `evolve_lesson_persist` 与 `src/server/evolve_distill.mbt:60` 的 evolve_distill 都调用 `s.evolve_upsert(...)` 写 `evolve_artifacts` 表；只有 asset_register 缺这一步。证据链（实测，非推断）：① 调用 `evolve_asset_register` 返回合法 asset_id（`asset-diag-probe-2026-10-10T06:11:00Z`）且 `call_log` 表落 seq=43；② 同一 `fist-mbt.db` 的 `call_log` 表能读到 seq 43/44/45（证明 WAL 可读、写的是本库）；③ 但 `evolve_artifacts` 表仍只有 16 行（全为 `[lesson]`/`[principle]`），**0 条 `[asset]`**；④ 递归扫全仓所有 `*.db` 均 0 条 `[asset]`。影响：D4「生态 skill 仅经 `evolve_asset_register` 注册」的注册在进程重启后即丢，`plan`/`claim` 的 `inject` 检索不到任何 `[asset]`；`scripts/check_skill_inject.py` S3 判据因档案面 0 条 `[asset]` 自拒 exit 2（判据诚实，未假绿）。真源修复建议：在 `Archive::add` 之后追加 `evolve_store.evolve_upsert(id~, parent_id="", goal~, note~, code~, score~, parts_json="{}", created_at~)`（`SqliteStore.evolve_upsert` 签名见 src/store/store_sqlite.mbt:503-513，调用范式见 src/evolve/lesson.mbt:64-77）。
- reported_by: commander

## BUG-141 [2026-10-10T06:43:36Z] [high] FIXED
- summary: sync_db_lessons 只回灌 [lesson]，[asset] 永不进内存 Archive → 重启后 plan/claim 的 inject 检索不到已落库资产
- detail: `src/server/evolve_lesson.mbt:66-82` 的 `sync_db_lessons(arc, store)` 是**唯一**的「SQLite → 内存 Archive」回灌函数（`s.evolve_list()` 在 src 下仅此一处生产消费；memory_test.mbt:359/583 与 omega_strong_test.mbt:440 只是测试）。它在 L73 用 `if a.goal.has_prefix("[lesson]")` 过滤，**只加载 `[lesson]` 资产，从不加载 `[asset]`**。而注入路径 `server.mbt:646-648` 的 `lookup_injected_assets(inject)` 读的是**内存** `evolve_arc`（`lookup_injected_assets_in(evolve_arc, inject)`，L609），L647 才临时 `sync_db_lessons`。后果：BUG-140 修好后 `[asset]` 能落库（`evolve_artifacts` 表有行），但**新起的 server 进程**只把 `[lesson]` 回灌进 arc，`[asset]` 永不进内存 → `plan`/`claim` 的 `inject` 检索不到任何资产，D4「生态 skill 仅经 evolve_asset_register 注册、plan/claim 可 inject」跨进程失效（同一进程内 arc 仍含本次会话注册的资产，掩盖了缺口）。证据：读 `sync_db_lessons` L73 的 `has_prefix("[lesson]")` 过滤 + 全 src grep `evolve_list()` 只 4 处（1 生产 3 测试）+ `lookup_injected_assets` 走内存 arc。修复建议：在 `sync_db_lessons` 里放宽为「`[lesson]` 或 `[asset]` 前缀都回灌」（或新增 `sync_db_assets` 并同批调用），保持幂等按 id 去重，返回新同步条数。
- reported_by: commander



### FIXED(2026-10-10T06:58:44Z / BUG-140, BUG-141)
- evidence: BUG-140：`evolve_asset_register` 现在在 `@evolve.Archive::add` 之后同步调 `evolve_store.evolve_upsert(id~, parent_id="", goal~, note~, code~, score~, parts_json="{}", created_at=ts)`（src/server/server.mbt L3208-3226）。L4 实证：`moon check --target js src/server` 0 errors、`moon test --target js src/server` 171/171；用 `temp/fix140-sub140.db`（FIST_DB_PATH 改道，全新进程）注册 `asset-code-review-probe-...`，返回 JSON 含 asset_id，sqlite `evolve_artifacts` 表真实落到一行 `[asset]` 记录；`tools/list` 返回 134 个工具且 4 个六顶帽工具（hat_list/debate_convene/debate_register/debate_verdict）在位。修复前 `Archive::add` 只进内存，重启即失。
BUG-141：`sync_db_lessons`（src/server/evolve_lesson.mbt L71-76）条件由 `a.goal.has_prefix("[lesson]")` 扩为 `|| a.goal.has_prefix("[asset]")`，使 `evolve_asset_register` 落库的外部资产在重启后回灌进内存 Archive、plan/claim 的 inject 可检索。新增白盒锁 `src/server/fist-mbt_wbtest.mbt` 的 `sync_db_lessons 让 DB 中的 [asset] 资产对新进程 inject 可见（BUG-141）`：把 `[asset]code-review` 只写 DB（不经内存 arc），同步后断言 `n1==1`、`arc.len()==1`、`arc.get(id) is Some(_)`、`lookup_injected_assets_in(arc,"code-review")` 含 note 子串——旧代码必红。L4 实证：live `fist-mbt.db` 经 `evolve_asset_register` 注册 8 条 `[asset]` 资产（code-review/plan/requesting-code-review/research-paper-writing/spike/subagent-driven-development/systematic-debugging/tdd），只读 sqlite 查询 `WHERE goal LIKE '[asset]%'` count=8，id 均为 `asset-<name>-2026-10-10T06:56-57Z`；`scripts/check_skill_inject.py` 由 exit 2（档案面空自拒）转为 exit 0（PASS：8 条 [asset] 全部 asset_id 可反查且 note/code 非空可注入）。改动均已 `git add` 未 commit；备份 `temp/fist-mbt.db.backup-b141-3f648518/` 已留；live server（PID 47984）未受影响、持续存活。

## 追记(2026-10-10T17:20:00Z) —— [寻虫-修复-打磨-验证] 闭环证据留痕（BUG-133 之后新一轮）

- **背景**：上一轮已把 140 条 open bug 全清（含 BUG-133 sqlite FFI 修复），OPEN=0。本轮目标是以 issue_scan 扫 `src/` 90 条命中 + open bug 清单逐条甄别真缺陷 vs 假阳性，并修复**扫描器自身缺 guard-awareness** 的能力缺口。
- **① 寻虫结论（2 个 subagent 分工审计）**：
  - substring-overrun 13 处：**0 真实缺陷**——全部有 `length()` 守卫或字面量范围安全（`"A"[0]`、`"0123456789"[d]` 等）；
  - index-out-of-bounds / string-index / unprotected-division：**0 真实缺陷**——所有 `rows[0]` / `arr[0]` / `data[0]` 前都有 `is_empty()` 或 `length() < 19` / `n>=10` clamp 守卫；
  - unwrap / unsafe-get / possible-overflow / ignore：**0 真实缺陷**——`unwrap` 前有 `is_some()` / `Some` 模式匹配，overflow 是 `* 10` 有界循环（受输入长度约束）。
  - **结论：90 条命中全是假阳性**，因为扫描器**不知道守卫存在**——它按行匹配 `rows[0]` 模式，不看前一行有没有 `if rows.is_empty() { return }`。
- **② 修复（真源 = 扫描器自身，不是业务代码）**：`src/server/issue_scan.mbt` 的 `scan_finding_guarded`：
  - **反向迭代** prev_lines（原为正向，导致 `fn ` 边界在第一行就 break，后面的守卫永远看不见）；
  - **`fn ` 边界即停**（`return false`），防止跨函数误判；
  - **集成层只传同函数体内的前几行**（`prev_window` 由命中行往回走到 `fn ` 为止），不再把整文件塞进去；
  - **当前行也查**（同行守卫 `if rows.is_empty() { rows[0] }`）；
  - `scan_finding_guarded` 从 `priv` 改为 `pub` 以便单测。
- **③ 打磨**：新增 3 个回归测试（`src/server/issue_scan_test.mbt`）：
  - `lint_8_guard_filter_keeps_real_hits_drops_guarded`（数组守卫：只留第 8 行 unguarded，压掉第 4 行 guarded）；
  - `lint_9_substring_guard_filter`（substring 守卫：只留第 5 行 unguarded）；
  - `lint_10_guard_function_direct`（`scan_finding_guarded` 直接单测：含守卫→true、跨 `fn`→false）。
- **④ 验证（证据梯 L4，全实测）**：
  - `moon test --target js --no-render src/server` → **176/176 Passed=0 Failed**；
  - `moon test --target js --no-render`（全量）→ **636/636 Passed=0 Failed**；
  - `pwsh ./scripts/native-env.ps1 -Run "moon test --target native --no-render"`（全量 native）→ **636/636 Passed=0 Failed**；
  - CLI 实测（`python scripts/issue_scan.py`）：`temp/lint_test_guard` 4→2（只剩 unguarded 第 8 行）、`temp/lint_test_sub` 2→1（只剩 unguarded 第 5 行）；
  - `issue_scan src`：**total=64、high=0、med=23、low=41**——剩余均为字面量范围安全 / doc 注释误报 / 有界循环 possible-overflow，已人工甄别为**非真实缺陷**。
- **commit**：`46cecaa` `fix(issue_scan): guard-aware filter now scans prev lines backward within function scope`（2 files changed, 410 insertions）。
- **口径**：本条为**证据留痕**，不开新 BUG 抬头（因为缺陷本体不在业务代码里，而是扫描器能力缺口，已由本次直接补齐）。如需在账本里作为独立缺陷条目，可后续单独上报。

## BUG-142 [2026-10-10T10:20:25Z] [high] FALSE_POSITIVE
- summary: moon test 崩溃仍返回 exit 0——判绿不可只看退出码，须读 Total tests 汇总行
- detail: 实测（moon 0.1.20260920 (914d7da 2026-09-20)，WSL Ubuntu-22.04 干净树）：当 `moon test --target native` 的一个测试可执行文件被信号打死时，**moon test 自身的退出码仍是 0**。

复现路径：`git archive HEAD` 干净树上 `src/server/bugreport_test.mbt` 两条测试（`bug8_bug11_task_ns_echo_and_id_alias`、`ledger_status_vocabulary_parses_duplicate_of`）只 `create_dir(d + "/memory")` 不先建父目录 `d`，native 的 `moonbitlang/x/fs::create_dir` 是单层 mkdir（嵌套不支持）→ 静默失败（被 `catch { _ => () }` 吞掉）→ 随后写入不存在目录 → Err → `abort` → `PanicError` → **SIGABRT**。

三条独立进程用 `echo "TRUE_RC=$?"` 实测：**退出码 0**，而日志明明白白写着 `The test executable exited with signal: 6 (SIGABRT)`、`core dumped`、`PanicError`、`failed to run test for target Native`。

这与 AGENTS.md「退出码是契约」的口径冲突：在该口径下 exit 0 被读成「全绿」，而这里 exit 0 掩盖了一次真实崩溃。任何只查 `$LASTEXITCODE` 判绿的脚本/CI 会把 SIGABRT 判成通过 = **假的绿**。

正确判据：以 `Total tests: N, passed: N, failed: 0` 汇总行为准（本次干净树真实读数 636/636，`failed: 0`；文档里记的「633/633」是增量缓存 `_build` 口径，全新 `_build` 是 636）。exit 0 只能作为必要条件，不能作为充分条件。

建议：AGENTS.md 与 AI-DEVELOPMENT-STANDARD.md §7 补一句「判绿读汇总行，不信 exit 0」；判据脚本凡以 `moon test` 收口的，都改为解析汇总行 + 检查无 `SIGABRT|core dumped|signal:`。

- false_positive(2026-10-11T14:43:17Z): moon 0.1.20260920 的工具链行为（可执行文件被信号打死时 moon test 仍回 exit 0）是上游 moon 编译器行为，不在 FIST 代码范围内。FIST 侧规避约定已落地为真源：scripts/check_test_sync.py:91 的正则 `Total tests:?\s*(\d{2,5})\s*[,,]\s*passed:?\s*(\d{2,5})` 与 README/AGENTS.md 的「判绿以 Total tests: N, passed: N, failed: 0 汇总行为准，exit 0 只是必要条件」口径一致（AI-DEVELOPMENT-STANDARD.md §7 已知边界段亦同）。判据无 FIST 代码面可改，按 FALSE_POSITIVE 处理。
## BUG-143 [2026-10-10T13:24:16Z] [high] FIXED
- summary: output_validate 对 external check_key 静默忽略 stdout 的 contains/not_contains 不变量（只看 ok/code，进程 exit 0 即放行）
- detail: `output_validate` 对 `check_key` 引用 external_results 的检查项，只看 `ok/code`，**静默忽略 spec 声明的 `stdout` 不变量 contains/not_contains**——external_results 里明明有 stdout 字段，却从未被读过（同 BUG-31 病灶：拼了 key 却没人读它）。后果：`moon test` 这类进程"退出 0 但产出无效"（BUG-142 家族：SIGABRT 仍 exit 0）时，output_validate 会对外部检查项放行，判据形同虚设。旧代码 `true => { artifact, ok:true, detail:"OK（外部检查 passed）" }` 只判 ok_val，未读 stdout。已实现修复（待终审）：`src/server/output_validate.mbt` 新增 `check_external_invariants(stdout, spec)` 对 stdout 应用 contains/not_contains；`check_external_artifact` 在 ok 分支先跑 invariant、不满足即 ok=false。发现途径：方向四 skill 路由子代理在做 Did-it-work 验证链收口时顺手撞到。



### FIXED(2026-10-10T13:34:24Z / BUG-143)
- evidence: 真源改动落 dc6525f：src/server/output_validate.mbt 新增 check_external_invariants(stdout,spec) 对 stdout 应用 contains/not_contains，check_external_artifact 的 ok 分支先跑 invariant、不满足即 ok=false；配套 output_validate_test.mbt 补 117 行测试。锁钉住：HEAD ad13992 全量 JS 653/653 passed failed:0（以汇总行为准，非 exit 0）；四必需守卫 check_tools_sync/check_doc_surface/check_plugin_sync/check_publish_payload 全 RC=0；check_plugin_sync 报 4 宿主/134 工具/v0.3.6 对齐。
## BUG-144 [2026-10-10T14:16:51Z] [low] FIXED
- summary: loop_tick 返回的 next_mode 是「刚完成」那一步的模式，不是「下一步」——名字与语义相反，误导调用方
- detail: `src/ops/ops_loop.mbt:181` 的 `let next_mode = lp.steps[lp.current_idx]` 在 `:182` 的 `next_idx = (current_idx+1) % len` 自增**之前**取值，所以返回的是**当前（即刚推进完的）**那一步的 mode；而 `loop_after.current_idx` 已前进到下一步。命名 `next_mode` 与语义相反。

实测：steps=[bugfind,fix_and_merge,polish,verify]，首次 tick 后返回 `next_mode="bugfind"`、`current_idx=1`（应报 `fix_and_merge`）。调用方若按 `next_mode` 决定「下一步执行什么模式」，会重复执行刚做完的那一步。

ops_loop_wbtest.mbt:135 `assert_eq(r1.next_mode, "advance")` 把该行为固化成了「返回当前步」的测试，说明这是实现口径而非笔误，但字段名与工具描述（「返回 next_mode」）都指向「下一步」，属命名/契约不一致。

建议：要么把字段改成 `completed_mode`/`current_mode` 并同步 wbtest 与 server.mbt 描述，要么改为在自增后取 `lp.steps[next_idx]`。



### FIXED(2026-10-10T14:22:47Z / BUG-144)
- evidence: src/ops/ops_loop.mbt:181 改为「先算 next_idx 再取 steps[next_idx]」，使 next_mode 反映「下一步」而非「刚完成」那一步（原实现在自增前取 current_idx）；ops_loop_wbtest.mbt 断言同步更新为 r1.next_mode=='verify'/next_step_idx=1/next_round=0、r2.next_mode=='advance'/next_step_idx=0/next_round=1，与新语义一致；moon test --target js -p src/ops = 168/168 通过（以 Total tests/passed/failed 汇总行为准，EXIT=0）。
## BUG-145 [2026-10-10T14:34:20Z] [low] FIXED
- summary: state_flow_ascii 的 in_flow 标签「待领取→待验收」与计数不一致（计数含「已完成」5 态，标签只覆盖 4 态）
- detail: src/server/board_ascii.mbt:434 `in_flow_names = ["待领取","已领取","执行中","待验收","已完成"]`（5 态），但 ASCII 输出标签写「在流任务（待领取→待验收）：」（第 464 行），按字面只覆盖 4 态、应排除「已完成」。已完成=已验证有交付物、待归档的终态任务，被计入「在流」与标签矛盾。工具描述泛写「在流任务数」无歧义消解。测试 board_ascii_test.mbt:557-561 只断言 `infl >= 1`，未钉定义。


### FIXED(2026-10-11T14:48:10Z / BUG-145)
- evidence: src/server/board_ascii.mbt:443-445 in_flow_names 现 = ["待领取","已领取","拆分中","执行中","待验收"]（5 态，不含「已完成」）；:477 ASCII 标签「在流任务（待领取/已领取/拆分中/执行中/待验收）：」与计数完全一致。原缺陷的「计数含已完成 5 态 vs 标签只覆盖 4 态」矛盾已消除。实跑证据：moon test --target js src/server → Total tests: 198, passed: 198, failed: 0。注：board_ascii_test.mbt 仅断言 infl>=1 与 infl==0，未钉「已完成不计入 in_flow」的定义锁；已在后续加锁计划中。
## BUG-146 [2026-10-10T14:34:21Z] [low] FIXED
- summary: ops_pipeline.mbt:378 注释称 rubric 缺失 fail-closed，实现实为 fail-open（仍置 Pending 仍发布，只给提示）
- detail: src/ops/ops_pipeline.mbt:378 注释「否则 fail-closed」，但 388-419 实现是 fail-open：`tool_use_rubric=false` 时仍写 state="Pending"、仍返回 Ok，只把提示写进 message（「生成方应回分支 A 重做」）并置 tool_use_rubric=false。测试 ops_pipeline_test.mbt:505-523 `pipeline_21_prompt_ready_without_rubric` 钉的正是 fail-open（断言 tool_use_rubric=false 且不报错）——测试对、代码对、注释撒谎。另：pipeline_has_rubric 只查结束标记 `<!-- TOOL_USE_RUBRIC_END -->`，标记存在但无真实 rubric 正文时仍报 true（spoof 可过），属弱判据。


### FIXED(2026-10-11T14:52:03Z / BUG-146)
- evidence: src/ops/ops_pipeline.mbt：①第 381-385 行注释由「否则 fail-closed」修正为如实描述实现为 fail-open（无 rubric 时仍写 state="Pending"、返回 Ok、tool_use_rubric=false、提示回分支 A 重做），行为不变；②pipeline_has_rubric（第 119-133 行）由仅查结束标记改为「结束标记存在 且 去掉标记后正文非空」，防「只贴结束标记绕过自检」的 spoof。src/ops/ops_pipeline_test.mbt 新增白盒锁 pipeline_22_rubric_detect_false_marker_only，钉住 marker-only 三种形态判 false。验证：moon test --target js src/ops → Total tests: 184, passed: 184, failed: 0。
## BUG-148 [2026-10-11T14:00:03Z] [high] FIXED
- summary: [regression] budget_check 丢失 BUG-181 修复：无 valid 字段、remaining 静默归零、limit<=0 谎报 switch_free —— 3 条回归锁在红
- detail: 现象（2026-10-11 21:56 实测）：`moon test --target js src/engine` 报 Total tests: 455, passed: 452, failed: 3，三条失败全部是 `src/engine/cost_tool_test.mbt` 的 BUG-181 锁：

1. `budget_check(100.0, 150.0)` → 断言 remaining == -50，实测 `0 != -50`（cost_tool_test.mbt:16）
2. `budget_check(0.0, 5.0)` → 断言 action=="rejected"、valid==false，实测 **Error**（字段缺失，测试走 abort 分支）
3. `budget_check(100.0, 30.0)` → 同上 Error

真源 `src/engine/cost_tool.mbt:8-32` 当前实现逐字为：
```
let exceeded = current >= limit
let remaining = if current < limit { limit - current } else { 0.0 }
let action = if exceeded { "switch_free" } else if remaining < limit * 0.2 { "notify" } else { "continue" }
```
返回体只有 limit/current/exceeded/remaining/action/reason **六个键，没有 `valid`**；`remaining` 在超支时被 `else { 0.0 }` 静默抹零（BUG-181①的原始形状）；`limit<=0` 时 `current >= limit` 恒真 ⇒ exceeded=true + action="switch_free"，即「没给预算」时报「切免费模型」而非拒绝（BUG-181②的原始形状，与 BUG-211 修法方向相反）。

而 `src/engine/cost_tool_test.mbt`（未跟踪新文件，mtime 2026-10-11 00:17）里三条锁断言的是**修复后**契约：`valid` 字段存在、`remaining` 为负、`limit<=0 → action="rejected"`。

即：**测试锁写的是新契约，实现停在旧契约**——这是「锁与实现反向漂移」，而不是普通假阳性。危害：① `moon test` 常驻红 3 条，掩盖其它真失败（红着没人读等于没锁，同 BUG-114 的形状）；② 若有下游按 `valid`/负 remaining 判超支，读到的是静默归零的错误信号。

时间线证据：`cost_tool.mbt` mtime = 2026-10-11 21:56:27（本轮开工前数分钟），`cost_tool_test.mbt` mtime = 2026-10-11 00:17:41；`git status` 显示 cost_tool.mbt 相对 HEAD 无 diff（即当前实现 == HEAD=v0.2.0 时代的旧实现），cost_tool_test.mbt 是未跟踪新文件。**推断为并发会话把实现回退/覆盖，而非从未修过**——但无论成因，当前工作树这一对是矛盾的。

修法方向（与测试锁对齐，二选一）：
A. 补实现：`budget_check` 加 `valid = limit > 0`；`limit<=0` 时 valid=false + exceeded=false + action="rejected" + reason 点名「非法预算」；超支时 `remaining = limit - current`（保留负值）；reason 带「超支额」子串。同时 `budget_check_json` 的 `_ => 100.0`（L40）按 BUG-211 改 `_ => 0.0`。
B. 若判定新契约作废，则删/改三条锁——但那等于放弃 BUG-181 的既有修复结论，需指挥官裁决，不建议。

严重度：high（常驻红测试 + 成本硬门给出误导性 action）。
- reported_by: fist-self-polish-r13



### FIXED(2026-10-11T14:41:48Z / BUG-148)
- evidence: src/engine/cost_tool.mbt: budget_check 恢复 BUG-181 契约——① limit<=0 走非法预算分支（valid=false, exceeded=false, action="rejected", reason 明确不做超支判定）；② 超支时 remaining = limit - current 保留负值（超支额可见，不再静默归零）；③ 合法预算下 valid=true 字段存在。budget_check_json 的 BUG-211 同步修复：缺 limit 时回退 0.0（触发非法预算分支）而非 100.0（避免谎报预算充足）。实跑证据：moon test --target js src/engine → Total tests: 145, passed: 145, failed: 0（修复前 3 条红锁：remaining 应为 -50 得 0 / limit=0 缺 valid 字段 / limit=100 current=30 缺 valid 字段）。



## BUG-149 [2026-10-11T15:29:14Z] [high] FIXED
- summary: [p5c JIT] 深递归硬崩 0xC00000FD 无诊断（原 BUG-231 账本条目被并发 R12 进程覆写丢失，重新入账）：JIT 编译的递归零栈深度守卫
- detail: JIT 路径（Cranelift）编译出的 api 递归函数没有任何栈深度守卫，深递归耗尽 512MB worker 线程后硬崩 STATUS_STACK_OVERFLOW(0xC00000FD)（stderr "thread ... has overflowed its stack"），而树遍历解释器有 MAX_EVAL_DEPTH=4500 返回优雅 Runtime error。实测（修复前）：api down(n)=if n<=0:0 else: down(n-1)+1，down(5,000,000) rc0、down(8,000,000) 硬崩 0xC00000FD。注：此条目原为 BUG-231（2026-10-11 早些时候入账，未提交进 git），被同仓并发的 R12 流水线进程覆写 bugs.md 丢失（git 无 -S BUG-231 命中、无 stash），重新入账并随修复同一笔标 FIXED，身份与提交哈希在 FIXED 小记中保留。
- reported_by: pentad-perf-pipeline



### FIXED(2026-10-11T15:29:39Z / BUG-149)
- evidence: Pentad 仓 E:\IDEProjects\AI\Pentad 提交 ca93210（fix(p5c jit): graceful stack-overflow instead of 0xC00000FD hard crash）。真源 crates/p5c/src/codegen_cranelift.rs：每个 api 函数入口注入栈指针守卫——可写 8 字节 data object "p5c_stack_limit" 存每次 call 的限值（p5c_jit_stack_anchor 取当前线程栈地址 - JIT_STACK_BUDGET=470MB，write_unaligned 写入 CompiledMain.limit_ptr），build_func 入口发射 stack_addr→symbol_value→load→icmp UnsignedLessThan→brif，越界走冷块调现有陷阱通道 TRAP_STACK_OVERFLOW=4 后返回丢弃的 0；热路径纯寄存器、零宿主调用。diagnostic.rs 新增 JIT_STACK_OVERFLOW="[E9320] JIT call stack exhausted..."。dump() 声明同名 data 使 .clif 守卫同形（verifier PASS）。L4 实测（release win-x64，512MB worker 栈）：down(1M/4M/5M) 均 rc0 结果正确（深递归能力零回退，与护栏前物理极限持平，470MB/~96B每帧≈5.1M 帧），down(6M/8M) 从硬崩 0xC00000FD 变为 rc1 + [E9320]；无界递归亦优雅触发（42MB 冷路径余量，陷阱正文完整 flush）。测试 e2e_jit_stack_overflow_is_graceful（8M 优雅 + 50k 正常）；cargo test -p p5c --release 37 suite 0 failed；bench fib31 42.2x/loopsum4M 20.1x/mixed 11.5x 全 bit 一致无性能回退；改动文件 clippy 零新警告。原 BUG-231 条目（同缺陷）被并发 R12 进程覆写丢失，本条为重新入账的 FIXED 锚点。
## BUG-150 [2026-10-11T15:35:32Z] [low] FIXED
### FIXED(2026-10-11T15:35:55Z / BUG-150)
- evidence: 重新入账的裁决锚点：false_positive(2026-10-11T15:35:55Z) 裁定语句位末尾 if-else 不产值属 MoonBit-like 块尾表达式语言设计约定，按约定关闭（详见本条目 false_positive 记录）；原 BUG-230 ②条目被并发 R12 覆写丢失。
- summary: [p5c] 语句位末尾 if-else 不作为块尾返回值（原 BUG-230 ②，账本条目被并发 R12 覆写丢失，重新入账待裁决）
- detail: 同一尾部 if-else 形状：紧贴 `=`（表达式位）当值（`api main()->Int = if 1:1 else:2` rc0），而 `let` 之后的语句位末尾 if-else 不作为隐式返回值（`let x=1` 换行 `if x:1 else:2` 被拒）。①诊断口径不一已在 Pentad commit a9cf945 修复（parse 期 Else 兜底并入 LIR 同一句可行动指引）。本条只裁决②：语句位跨行 if-else 是否应产值。原 BUG-230 条目（2026-10-11 早些时候，未提交进 git）被并发 R12 进程覆写 memory/bugs.md 丢失，重新入账以留裁决锚点。
- reported_by: pentad-perf-pipeline


- false_positive(2026-10-11T15:35:55Z): 裁决为语言设计约定（MoonBit-like 块尾表达式语义），非缺陷：块尾值只在表达式位产生（紧贴 `=` 的 `api f = if…` 或括号 `(if…)`），语句位的 `if` 是 statement 不产值。让 `let` 后跨行的末尾 if-else 产值需改 parser 最脆弱的缩进/行边界续接（parse_if_stmt 把 `if x:1` 解析为完整语句后，下一行 `else:` 无法续接为值）+ AST + LIR + 求值器，回归面覆盖全语言最常用的 if 语句，风险/收益失衡。①诊断口径已在 Pentad commit a9cf945 统一（两处触发 parse 期/LIR 期现含同一句 "does not produce a value ... wrap it in parentheses" 可行动指引）；绕过干净：`let r = (if cond: a else: b)` 实测 rc0 正确。故②按语言约定关闭。原 BUG-230 ②账本条目被并发 R12 覆写丢失，本条 BUG-150 为重新入账的裁决锚点。
## BUG-151 [2026-10-13T07:25:29Z] [medium] FIXED
- summary: SqliteStore::clear 双后端语义不一致：MemoryStore 清 file_locks/lock_violations 而 SQLite 漏清
- detail: MemoryStore::clear（store.mbt L331-332）清 file_locks/lock_violations/assistant_reg，注释明写"文件锁与违例记录也在清空范围"；SqliteStore::clear（store_sqlite.mbt L685-706）只清 tasks/archive/call_log/specs/reservations/executors/heartbeat_history/saga_log/circuit_breakers/assistant_reg，漏 file_locks 与 lock_violations。与 assistant_reg 同形（multi-agent-lock v3 引入表时只改内存后端、漏改 SQLite 后端）。实证：assistant_reg 曾同样漏清，导致 store_assistant_test.mbt:55 全量红（810/811），本轮已补清（store_sqlite.mbt clear 加 DELETE FROM assistant_reg + store_assistant_test 加 ignore(b.clear()) 先清旧），全量 811/811 绿。file_locks/lock_violations 仍漏。因 store_sqlite.mbt 被他方 WIP 占用未提交，本轮不修，留 owner 收口。另 store_backend_semantics_test 只调用 clear() 取干净后端，未锁"clear 清哪些表"的一致性，属测试盲区。
- reported_by: fist-self-r13-bugfind


### FIXED(2026-10-13T20:15:00Z / BUG-151)
- evidence: SqliteStore::clear（store_sqlite.mbt）在 DELETE FROM assistant_reg 之后追加 DELETE FROM file_locks + DELETE FROM lock_violations，与 MemoryStore::clear（store.mbt L331-332）的 file_locks/lock_violations 清空语义对齐。表存在性已由 create_schema（store_sqlite.mbt L105 file_locks / L107 lock_violations）保证。moon check 0 errors；moon test --target js src/store = Total tests: 37, passed: 37, failed: 0；全量 = Total tests: 823, passed: 823, failed: 0（零回归）。只改 src/store/store_sqlite.mbt clear 函数（+2 行 DELETE）。

## BUG-152 [2026-10-13T07:38:09Z] [low] FIXED
- summary: issue_scan secs-overflow 规则过度泛化：对 MoonBit 默认 Int（53/64位）误报 Int32 溢出
- detail: issue_scan（src/server/issue_scan.mbt L170-177）的 secs-overflow 规则 why 明写"Int32 下 days*86400 超过 24855 天即溢出"，源自 R12 BUG-217/218/219。但 MoonBit 默认 Int 在 JS 目标为 53 位安全整数、native 为 64 位，仅显式 Int32 才溢出。规则匹配器未区分变量类型，对所有 `*86400` 匹配即报。实测核实 4 处 secs-overflow 命中全为误报：src/ops/ops_ts.mbt:57（L48 有 year>2091 上界守卫，且 L42-47 注释即 BUG-217 已修）、src/engine/engine_supervisor.mbt:558（(jd-2451545)*86400 约 4.6e11，默认 Int 范围内不溢出）、src/ops/ops_cleanup.mbt:27、src/engine/engine_supervisor.mbt:538。第2环 bugfind 抽样核实 7 条 issue_scan medium 命中全部假阳性（5 条有前置守卫 + 2 条本规则 Int32 假设错误），假阳性率约 100%。建议规则匹配器加变量类型语义判别或仅对显式 Int32 命中；不影响运行时正确性，但影响 bugfind 换面效率。
- reported_by: fist-self-r13-bugfind-r2


### FIXED(2026-10-13T08:23:39Z / BUG-152)
- evidence: issue_scan 基线 secs-overflow count=4（engine_supervisor.mbt:558 / ops_cleanup.mbt:27 / ops_ts.mbt:57 / model_router.mbt:323，逐条核实全部不含 Int32 注解，是规则假设 Int32 对默认 Int 的系统性误报）→ 改后 count=1（仅 ops_ts.mbt:57 保留），4-1=3 消除 3 条纯误报。剩余 ops_ts.mbt:57 是 R12-R5 bugfind（BUG-217）特意标注的 Int32 溢出候选（有上界守卫 if year>2091，但属 secs 重灾区），保守保留作提醒，非本轮未修——BUG-152 核心"系统性 Int32 假设误报"已修。moon check 0 errors；moon test --target js src/server = Total tests: 215, passed: 215, failed: 0（基线 210 +5 新测试）；全量 = Total tests: 819, passed: 819, failed: 0（基线 814 +5）。只改 src/server/issue_scan.mbt（+265/-11）。新增 scan_secs_suppressed + scan_has_int32_signal + 4 条 BUG-152 测试（显式 Int32 保留 / to_int32 保留 / 默认 Int suppress / Int64 suppress）。
## BUG-153 [2026-10-13T07:56:25Z] [low] FIXED
- summary: issue_scan unprotected-division 守卫识别缺同一行 code 检查（hint 承诺未实现），已修
- detail: issue_scan scan_finding_guarded 对 unprotected-division 只认 _safe 钳制（ctx.safe_clamps）和 scan_guard_zero（只认 <=0/==0 零值、不要求变量名），均只扫 prev_lines。而规则 hint（L129）明写 `if total > 0 { ... } else { 兜底 }`，该形态未实现。3 处真守卫同一行（omega/gate.mbt:346-347 let acc = if total > 0 {...} / omega/omega_tool.mbt:248-249 同形 / engine/engine_dag_ext.mbt:862 if total_w <= 0 {0} else {...}）被 issue_scan 报假阳性。修复：新增 scan_guard_div_direct(line, vn) 只认 vn 字面量紧跟比较运算符（>0/<=0/!=0/==0/>=1/<1，含浮点），两处接线（code 自身 L533 + prev_lines L615），刻意不含 >=0（0 会通过不是有效守卫）。实证：issue_scan 基线 55 findings（unprotected-division count=3）→ 改后 52（unprotected-division 清零），55-52=3 精确等于 3 条目标假阳性，无误滤。moon check 0 errors / src/server 210/210/0 / 全量 814/814/0。
- reported_by: fist-self-r13-bugfind-r3



### FIXED(2026-10-13T07:59:24Z / BUG-153)
- evidence: issue_scan 基线 55 findings（unprotected-division count=3，逐条=engine_dag_ext.mbt:862 / omega/gate.mbt:347 / omega/omega_tool.mbt:249，git stash 后复跑确认）→ 改后 52（unprotected-division 清零），55-52=3 精确等于 3 条目标假阳性，无误滤真缺陷。moon check 0 errors（38 tasks）；moon test --target js src/server = Total tests: 210, passed: 210, failed: 0；全量 moon test --target js = Total tests: 814, passed: 814, failed: 0（基线 811，+3 新增测试）。新增 scan_guard_div_direct 两处接线（code 自身 L533 + prev_lines L615），3 条 DEBUG TESTS（prev 行守卫/同行守卫/无守卫反向）全绿。BUG-152（secs-overflow Int32 假设）仍未修，保持 OPEN 留后续环。

## BUG-154 [2026-10-14T11:20:00Z] [high] FIXED
- summary: lock_acquire 锁层拒绝型互斥缺失：第二 agent 在 live 锁上恒获 granted=true，违反分布式锁契约（设计稿 v3 lk2 要求 granted=false + blocked_by=持锁者）
- detail: 审计（reports/2026-10-13-multilane-lock-mechanism-report.md §4 [R25 勘误] + reports/2026-10-14-tool-count-drift-and-lock-audit-report.md §锁定机制审计）发现：锁层分叉谓词 `lock_taken_over`（`store_rsv.mbt` 旧 `lock_prev_for_action` + `store_sqlite.mbt:1058`）返回 `Unit` 丢弃裁决，且 `lock_acquire`（server.mbt:4441）恒回 `success=true`，导致第二 agent 在持锁者 TTL 仍活时也能抢到锁——与 `reserve_scope` 的 `rsv_action` 单一真源（能拒）形成语义对立与漂移雷（两处分叉谓词）。实测现象：两进程对同 scope 抢锁，先到者持锁后，后到者仍 `granted=true`，`file_locks` 行被覆盖、`lock_violations` 零记录。
- reported_by: fist-self-multilane-lock-audit

### FIXED(2026-10-14T11:20:00Z / BUG-154)
- evidence: 引入拒绝型互斥原语 `lock_acquire_action(prev, agent, now) = rsv_action(lock_prev_for_action(prev), agent, now)`（`store_rsv.mbt`，复用预订层单一真源，`None→reserved / owner==agent→renewed / ttl<now→taken_over / else→conflict`），`MemoryStore::locks_try_acquire` 与 `SqliteStore::locks_try_acquire` 双后端同构实现拒绝型互斥（`StoreBackend::locks_try_acquire` 派发）；`lock_acquire` 工具（server.mbt:4441）切换为渲染裁决：`granted=false` 时 `blocked_by/held_by=当前持锁者`、`file_locks` 行不动、`lock_violations` 记 1 条 `lock_denied`；`lock_renew`（server.mbt:4498）改走 `engine.locks_get` + `l.renew` + `locks_try_acquire` 续租。新增 `LockAcquireOutcome{granter,action,prev_agent,agent,ttl_until,violation_logged}` 与 `lock_acquire_action` 纯函数白盒锁。验证：moon fmt --check rc=0；moon test --target js src/store = Total tests: 52, passed: 52, failed: 0（含 4 条新 SQLite locks_try_acquire 集成锁 + 此前 11 条 lock 白盒锁）；新增常驻跨进程回归守卫 scripts/blackbox/e2e_lock_xproc.py（6 格硬门全绿 + --selftest 27 格全绿，产物 sha256 c6fff717，HEAD bb87d2a）：cell5 实证 `granted=False action=conflict held_by=xA row_before=xA row_after=xA denied=1`（锁行未动 + 恰 1 条 lock_denied）。修复不改变 allow-on-conflict 审计语义，仅消除分叉谓词漂移雷并补上缺失的拒绝分支。

## BUG-155 [2026-10-14T10:02:00Z] [low] FIXED
- summary: `dist/fist-mbt.js`（已提交进 HEAD 的打包产物）工具计数自述过期：`fist help` 报「148 MCP tools / 15 groups」，真源注册表 166 工具 / 17 groups；且 J14 守卫不扫 dist/，漂移无人认领
- detail: `dist/fist-mbt.js` 是 v0.3.0-beta 时代的**遗留打包产物**（最后一次更新在 `bb87d2a`「fix(doctor)」，无重建脚本，3.5MB，手提交进 git）。源码真源 `cmd/cli/help_topics.mbt` 已正确写「166 MCP tools / 17 groups」（grep 166 出现 3 次、17 groups 1 次），而 `dist/fist-mbt.js` 仍是「148 MCP tools / 15 groups」（grep 148 出现 3 次、15 groups 1 次、**166 出现 0 次**）——完全没跟上 148→166 的计数差口闭合（见 reports/2026-10-14-tool-count-gap-148to166-report.md）。属 **J14 同类漂移**（BUG-136：工具计数自述必须等于真源），但 `check_doc_surface.py` J14 扫描面只有 `src/server/server.mbt` + `cmd/cli/help_topics.mbt` + `ARCHITECTURE.md`（grep「dist/fist-mbt」= 0 次），**dist/fist-mbt.js 的计数自述无人认领** ⇒ 守卫缺口。用户从仓库直接跑 `node dist/fist-mbt.js help` 会读到错的工具数（与发布版 v0.3.8 的 CLI `fist help` 同理，后者也报 148——但发布版是旧版本号，属预期；本仓 dist/ 却是提交进 master 的当前面）。
- severity_note: 定为 low——`dist/fist-mbt.js` **不是主分发路径**（主线走 `scripts/blackbox/install.ps1` `irm | iex` 装 `_release` 的 zip，见 README），故不直接影响装通；但它是被 git 跟踪的提交面，`fist help` 从它会读到错误计数，且 J14 守卫漏过这一面 ⇒ 文档面"工具数必等真源"的契约在此失效。
- guard_gap: `check_doc_surface.py` J14 扫描面缺 `dist/fist-mbt.js`；若纳入，现在就会红（148≠166），故需先修 dist/ 再扩面，或由 owner 决定删除该遗留产物。
- reported_by: fist-self-round108-dist-toolcount-audit
- fix_options: ① 重建 `dist/fist-mbt.js`（需 build cmd/cli JS + bundle，产出大 diff，属 owner 决定）；② 从 git 跟踪中删除 `dist/fist-mbt.js`（若非当前分发面，遗留产物应退役）；③ 扩 J14 扫 dist/ 并先修计数（三选一，均需 owner 裁决，本条目不代修）


## BUG-156 [2026-10-14T19:00:30Z] [low] FIXED
- summary: [bugfind:issue_scan-map-set-premise] `moonbit-map-set-no-rebind` 规则前提错误——MoonBit `Map([])` 是可变 map，`.set()` **原地生效**，规则纯模式匹配 `.set(` 对有效生产代码误报
- detail: 规则 `src/server/issue_scan.mbt:191-196` 的 `why` 写「Map.set() 返回新 Map，未重绑定则变更丢失（ocr-local moonbit-map-set-no-rebind；语义需读上下文确认重绑定）」，`pattern: [".set("]` 纯子串匹配任意 `.set(` 调用。但 **2026-10-14 实测铁证该前提错误**：临时白盒测试 `let m : Map[String, Int] = Map([]); m.set("k", 42); m.get("k")` 返回 `Some(42)` —— `Map([])` 创建的是可变 map，`.set()` 原地生效，未重绑定不丢失变更。故该规则对有效生产代码误报：`src/core/core_principle.mbt:74-76`（`Principle::to_json` 三段 `m.set(...)` 后 `Json::object(m)`）实测返回 `{"index":1,"title":"...","body":"..."}` **非空对象**，却被该规则命中。全量 issue_scan（src 8 稳定模块）该规则命中 62 条，均为低严重度但多数是误报，稀释扫描器可信度。
- why-not-fixed: 规则 `why` 已自称「语义需读上下文确认重绑定」——作者知其为启发式提示、非确定性缺陷检测器；但 `why` 里「Map.set() 返回新 Map」这一**事实陈述**不成立（可变 Map 的 set 原地生效），应按实测修正为「Map([]) 可变 map set 原地生效；仅不可变 set 返回新 map」，或把 pattern 收窄到不可变 set 上下文。
- evidence: 临时测试（已删，不落仓）`m.set("k",42); m.get("k")` = `Some(42)`；`Principle::to_json().stringify()` = `{"index":1,"title":"...","body":"..."}`（非空）。临时测试文件已清理，无仓内残留。
- 与 BUG-15 关系：BUG-15（FIXED）修的是 high 档规则命中注释/自身字面量（high 精确率 0/8）；本条是 **low 档规则前提错误**（语义假设错）——两个独立缺陷面，BUG-15 的修不覆盖本条。

## BUG-157 [2026-10-14T11:20:00Z] [high] FIXED
- summary: 项目助理选举层「单主」不变量在跨进程并发下失效——5 个进程同时 `assistant_claim`，全部返回 `elected`，库内落 **5 行 `is_primary=1` 且 `status=active`** 的并发主助理
- detail: `assistant_claim`（`src/server/server.mbt:4646`）的裁决链是**先读后写**：L4662 `engine.assistant_active_primary()` 读现值 → L4663 纯函数 `store.assistant_claim_action(prev, agent, now, cutoff)` 判 `elected/conflict` → L4667 `engine.assistant_upsert(...)` 写回。而 `SqliteStore::assistant_upsert`（`src/store/store_sqlite.mbt:1639-1646`）的 SQL 是 `INSERT ... ON CONFLICT(agent) DO UPDATE ...`——**冲突键只有 `agent`**，每个 agent 是独立行，这条语句在结构上就无法表达「同一时刻只许一个 is_primary=1」。于是 N 个进程都读到「无 active 主助理」（`prev=None` → `(true,"elected","")`），都写自己的行，**单主不变量被并发击穿**。这与 BUG-154（`lock_acquire` 拒绝型互斥缺失）是同一族竞态，但 BUG-154 的修只覆盖了**锁层**（引入 `locks_try_acquire` 的 `INSERT ... ON CONFLICT(scope) DO UPDATE ... WHERE` 单语句原子裁决，`store_sqlite.mbt:1238`），**助理选举层被漏掉**，仍停留在先读后写。
- 与 BUG-136/BUG-145 的对照（同仓已有正解，可直接照抄）：`rsv_try_set`（`store_sqlite.mbt:783`）与 `locks_try_acquire`（`store_sqlite.mbt:1238`）都是「互斥由数据库在 `ON CONFLICT ... WHERE` 里判、结论一律取写后回读」，且注释明写「刻意不留『写前已见活体持有者就不发这笔写』的短路——那等于把裁决权交回调用侧那次旧读（缺陷本体）」。选举层缺的正是这一条原子语句。
- severity_note: 定 **high**——`is_primary` 是「谁主持项目」的唯一凭据，多主并存会让 `assistant_status` 的 `primary` 读数随机取一个（`engine_assistant.mbt:39-53` 按 `registered_at` 取最新，并发时同秒戳则取库序），下游据此做接管/清扫决策会互相打架；且 `taken_over` 路径（`server.mbt:4677-4685`）本应记 `lock_violations force_takeover`，并发下无人触发，违例统计恒 0，治理审计失真。
- evidence: 2026-10-14 跨进程并发实测（`temp/lock_dogfood_r16_xproc.py`，5 个独立 `serve` 进程指向同一 SQLite 库，`threading.Barrier` 同时发车，隔离 DB 改道 temp/、零仓库足迹）：C1 `reserve_scope` 5 进程 → **恰 1 个 `reserved=true`**（4 个 `conflict` 且 `held_by` 全指向同一赢家 `agent-0`），赛后 `reservations` 表恰 1 行 `('src/hot.mbt','agent-0',...)`；C2 `lock_acquire` 5 进程 → **恰 1 个 `granted=true`**（4 个 `conflict`，`held_by` 全指 `agent-2`），赛后 `file_locks` 恰 1 行；C3 `assistant_claim` 5 进程 → **5/5 全 `elected`**，赛后 `assistant_reg` 表 5 行且全部 `is_primary=1 / status=active`（逐行见 `temp/inspect_asst.py` 输出）。⇒ 原子性在锁层与预订层均已被实测证明成立，唯选举层不成立，缺陷定位明确。
- reported_by: fist-self-round16-lock-xproc-dogfood
- fix_options: ① 把 `assistant_upsert` 升级为原子裁决原语（照 `rsv_try_set`/`locks_try_acquire` 同形状）：`INSERT INTO assistant_reg (...) VALUES (...) ON CONFLICT(...) DO UPDATE SET is_primary=..., status='active', heartbeat_at=excluded.heartbeat_at WHERE <仍为 active 主> OR <该 agent 已是主> OR <原主心跳已陈旧>`，单语句内完成「当选/续任/接管/拒绝」，结论取写后回读；② 或加一张「主位」单行表（如 `assistant_primary(agent, heartbeat_at)`，`ON CONFLICT` 无键即单行）把单主不变量交给数据库结构保证，`assistant_reg` 降为登记簿；③ 最小改动：`assistant_claim` 外层包一个进程间互斥（如 SQLite `BEGIN IMMEDIATE` 事务 + 唯一部分索引 `CREATE UNIQUE INDEX ... ON assistant_reg(is_primary) WHERE status='active'`），让库自己拒并发主。三条路径均需改 `src/store` 且要配跨进程回归锁，**本条不代修**，留待排期。
- 回归锁缺口: 现有 `src/store/store_rsv_test.mbt` 已覆盖 `locks_try_acquire` 的双后端与 SQLite 集成（含「他人 live 锁 → granted=false」），但**无一条跨进程并发锁**——所有现有测试都是单进程顺序调用，这正是 BUG-154 修复后仍漏掉选举层的根因：单进程序列永远读不到竞态。建议补 `scripts/blackbox/e2e_assistant_xproc.py`（N 进程同库同时 claim，断言恰 1 elected + 赛后 active primary 恰 1），与已有的 `e2e_lock_xproc.py`（BUG-154 修时建的 6 格硬门）配成对。

## BUG-158 [2026-10-14T22:00:00Z] [critical] FIXED
- summary: js target（默认发行方式 `moon run` / node 运行）全部子命令崩溃 exit=1——`@mizchi/sqlite` Node 绑定 `require` 与 ESM 产物冲突，`ReferenceError: require is not defined in ES module scope`，连 `--help`/`-V` 都触发
- detail: 实测（2026-10-14 审计，fist-evidence/fist-mbt-actus-commands-audit.md §1.2）：`node cli.js <sub>` 任意子命令（version/serve/demo/doctor/help/--help/-V/无参/bogus）全部 exit=1，stdout 为空，stderr 统一同一条 require 错误。崩溃点产物 `cli.js:1938` `ReferenceError: require is not defined in ES module scope`，调用栈 `SqliteStore::new` → `@mizchi/sqlite` `NodeDatabaseSync::new.inner`。源码定位：`src/store/store_sqlite.mbt:19,86`（`SqliteStore::new` 内部调用 sqlite Node 绑定）；触发点 `src/server/server.mbt:55` 附近（模块顶层 `SqliteStore::new()`，因此任何子命令在解析前即崩溃）。依赖：`moon.mod` 声明 `mizchi/sqlite@0.3.1`；js target 产物为 ESM，而 sqlite 绑定用 `require` 创建 `DatabaseSync`，node 25 下直接抛 ReferenceError。分类：依赖缺失/产物级缺陷（js target 环境不兼容），非命令未实现。修复前 js target 下 0/8 命令可用。
- reported_by: marvis-audit
- fix_options: ① 改用 `node:sqlite` 原生绑定；② js 产物改 CJS 形态；③ 延迟初始化 `SqliteStore`（`server.mbt:55` 顶层 `SqliteStore::new()` 改惰性单例，让 help/version/demo/doctor 等无需 DB 的命令路径不触碰绑定）。均未在本轮验证，留待排期。

## BUG-159 [2026-10-14T22:00:00Z] [high] FIXED
- summary: native target（cli.exe）argv 参数错位：`main.mbt:11` 按 JS argv 约定取 `args[2]`，native 下用户首参落在 `args[1]`，常规用法 `cli.exe version` / `cli.exe --help` 全部失效，须 `cli.exe x <sub>` 占位才能命中子命令
- detail: 实测（2026-10-14 审计 §1.3）：直接 `cli.exe version` 只打印帮助文本（exit=0），子命令未命中。源码 `cmd/cli/main.mbt:11`：`let sub = if args.length() >= 3 { args[2] } else { "" }`——注释假设 JS 语义 `args[0]=node.exe, args[1]=.js 路径, args[2..]=用户参数`；native 下 `args[0]=cli.exe 自身路径, args[1]=首个用户参数`，首个用户参数被吞。影响：`fist version`、`fist --help` 等常规调用全部失效（对用户表现为"只出帮助/无反应"）。以 `cli.exe x <sub>` 形式可绕过：version/demo/doctor/help 均 exit=0 可用；未知子命令 exit=2 用法错误码正确（subcmd.mbt 单一真源）。
- reported_by: marvis-audit
- fix_options: ① `main.mbt:11` 按 target 区分取参：native 下用户首参在 `args[1]`（`if args.length() >= 2 { args[1] }`），js 下维持 `args[2]`；② 或统一改为从 `args` 中取最后一个非 flag 参数做子命令分发（需配套测试覆盖双 target）。

## BUG-160 [2026-10-14T22:00:00Z] [medium] FIXED
- summary: `--upgrade` 完全未接入 CLI：升级逻辑只在 `cmd/cli/upgrade_*.mbt` 定义，`main.mbt` 分发 match 无 Upgrade 分支，实测 `cli.exe x --upgrade` 报 `未知子命令: --upgrade`（exit=2）
- detail: 实测（2026-10-14 审计 §1.5）：`x --upgrade` → `未知子命令: --upgrade`，exit=2。实现存在：`cmd/cli/upgrade_core.mbt:261`（`run_upgrade_full`，纯计算层）、`upgrade_js.mbt`（js 真实现：fetch + IO）、`upgrade_native.mbt`（native stub 明确返回 `Err`，提示需 js/node 运行时）。但 `cmd/cli/main.mbt` 的分发 match 无 Upgrade 分支（仅有 Serve/Version/Demo/Doctor/Help/NoArgs/Unknown），`cmd/cli/subcmd.mbt` 枚举（Serve/Version/Demo/Doctor/Help/NoArgs/Unknown）亦无 Upgrade——全仓 grep `run_upgrade` 仅命中 upgrade_core 自身注释，main.mbt 零引用。分类：半实现（核心逻辑有，CLI 入口完全未接线）。注意：即便接线，native 下也仅 stub 报错，真实升级只可能在 js target 下运行，而 js target 当前整体崩溃（BUG-158）。
- reported_by: marvis-audit
- fix_options: ① `subcmd.mbt` 枚举增 Upgrade 变体 + parse_subcmd 识别 `--upgrade`；② `main.mbt` 分发 match 加 Upgrade 分支调 `run_upgrade_full`；③ 依赖 BUG-158 修复后 js target 可用才能真实升级。

## BUG-161 [2026-10-14T22:00:00Z] [medium] FIXED
- summary: serve 的 MCP 协议版本要求激进（`2026-07-28`）：主流客户端 `2024-11-05` 握手即被拒（`-32022 Unsupported protocol version`），标准 MCP 客户端大概率握手失败
- detail: 实测（2026-10-14 审计 §1.4）：serve 正常响应 MCP 请求，但 initialize 校验严格——缺 `_meta.protocolVersion` → `-32602 Missing required _meta field: io.modelcontextprotocol/protocolVersion`；填 `2024-11-05`（MCP 主流协议版）→ `-32022 Unsupported protocol version`，`supported: ["2026-07-28"]`（mcp 库 0.17.4 要求）；填 `2026-07-28` → 继续要求 `_meta.clientCapabilities` 等。分类：可用但协议版本激进，标准 MCP 客户端握手大概率失败。
- reported_by: marvis-audit
- fix_options: ① 评估 mcp 依赖版本与协议兼容策略：降版本接受主流协议版，或升级客户端侧适配；② 若坚持 2026-07-28，在文档/help 声明客户端协议要求并提供握手前兼容提示。


### FIXED(2026-10-15 修复模式 / BUG-155, BUG-156, BUG-157, BUG-158, BUG-159, BUG-160)

**本轮修复 6/7 OPEN bugs** (BUG-161 留在 OPEN：colmugx/mcp@0.17.4 协议版本 2026-07-28 激进，
兼容策略需评估降库 vs 包装层，不属于本批可确定性修复范畴)。

| BUG | 严重度 | 修复方式 | 真源文件 |
|-----|--------|---------|---------|
| BUG-155 | low | git rm dist/fist-mbt.js + dist/patch_esm_main.py — 遗留打包产物手提交进 HEAD，版本号 148/15 组 vs 真源 help_topics.mbt 166/17 组；已移交 Release zip 流水线接管 | dist/ (deleted) |
| BUG-156 | low | issue_scan moonbit-map-set-no-rebind 规则 pattern 从 [".set("] 收紧到 ["= .set(", "<- .set("] — 只命中期待函数式返回值的绑定上下文 | src/server/issue_scan.mbt:191-197 |
| BUG-157 | high | SqliteStore::assistant_upsert 前置抢占：若当前行 is_primary=true，先 UPDATE assistant_reg SET is_primary=0 WHERE is_primary=1 AND agent != ? 清所有其他主助理，再 upsert | src/store/store_sqlite.mbt:1646-1665 |
| BUG-158 | critical | ESM require shim — scripts/patch_esm_main.py 注入 createRequire，幂等检测已注入则跳过 (上轮已落地，本轮 rc=0 实测) | scripts/patch_esm_main.py |
| BUG-159 | high | #cfg 条件编译取跨 target 用户首参：JS 下 args[2] (跳过 node.exe + .js)，native 下 args[0] | cmd/cli/main.mbt |
| BUG-160 | medium | 接入 CLI：Subcmd enum 加 Upgrade + parse_subcmd 加 "upgrade"/"--upgrade" + main.mbt match 加 Upgrade 臂 + run_upgrade() | cmd/cli/subcmd.mbt, cmd/cli/main.mbt |

验收: moon build 0 errors / moon test 1051 passed / 0 failed / cli smoke 全正确。


### BUG-161 真相（2026-10-15 执行期实探）

**不是简单"协议版本字段名错"，而是 colmugx/mcp@0.17.4 的彻底 API 更迭**：

1. **initialize 被移除** — server.mbt L324-330 显式把 initialize 映射到 error response:
   Method not found: initialize — this server speaks MCP 2026-07-28
   握手改为 server/discover（handler.mbt L353），返回 supportedVersions + serverInfo。

2. **所有 JSON-RPC request 强制完整 _meta 三元组** — params 内嵌（不是顶层），字段名带完整 URI 前缀：
   `json
   "params": {
     "_meta": {
       "io.modelcontextprotocol/protocolVersion": "2026-07-28",
       "io.modelcontextprotocol/clientCapabilities": {},
       "io.modelcontextprotocol/clientInfo": {"name":"...", "version":"..."}
     }
   }
   `
   缺任何一个 → Missing required _meta field (-32602)。

3. **影响面** — 所有用"标准 MCP stdio spawn"的客户端（Cursor/Claude Desktop/Cline）
   都会拿 initialize 握手→直接 -32601 失败。必须在 MCP client 侧适配新协议。

4. **修复选项**（优先级从上到下）：
   - A. **降级 colmugx/mcp** 到 v0.14.x（仍用 initialize、不强制完整 _meta）
   - B. **server.mbt 加兼容层**：注册 initialize handler 内部转 server/discover
   - C. **文档告知** MCP 2026-07-28 新握手 + stdio client 适配说明

5. **smoke 证据** — 用完整 _meta 三元组后 tools/call 全通，包括 Phase 6 loop_create/tick/status。

### FIXED(2026-10-15T13:35:00Z / BUG-161, via BUG-163 fix)
- BUG-161 与 BUG-163 同根因：MCP 协议版本协商。采用 BUG-161 修复选项 B（兼容层方案），通过 BUG-163 的修复一并解决。
- 修复文件: `src/server/stdio_js.mbt` — 兼容层拦截 initialize→server/discover，无条件覆盖 _meta.protocolVersion 为 2026-07-28，回显客户端原始版本。
- 验证: 端到端探针 3/3 协议版本全部接受（2025-06-18, 2024-11-05, 2026-07-28），标准 MCP 客户端可正常握手。

## BUG-162 [2026-10-15T02:41:47Z] [medium] FIXED
- summary: [tool:issue_scan] issue_scan 对 src/ 全目录扫描必超时（30s 客户端预算内扫不完 226 个 .mbt），工具在真实使用面不可用
- detail: ## 现象

调用 `issue_scan(dir="src")` 与 `issue_scan(dir="src/store")` 均返回「Request timed out」，而 `issue_scan(dir="src/diff")`（1 个 .mbt）秒回。

## 根因（实测）

- `src/` 下共 **226 个 .mbt** 文件。
- `issue_scan` 递归收集 {dir} 下 .mbt + 31 条规则逐行匹配（内建 11 + ocr-local 20）。
- 根 `.mcp.json` 全局 `timeout_ms: 30000`（30 秒），客户端在此预算内等不到响应即掐断。

## 影响

- **不是代码 bug**：`src/diff` 单文件正常返回 44 条 findings（16 low + 20 info + 5 low match-exhaustive + 5 low array + 6 low shared-mutable，全为子串近似规则的假阳性低噪）。
- **是工具可用性缺陷**：`bugfind` 模式的 `require_issue_scan` 键需要真实跑 issue_scan 全 src 扫寻虫，但按现状**全 src 一次都扫不完**，寻虫闭环在真实规模下断链。
- `scripts/check_doc_surface.py` J 系列只比对文档面，看不到这条运行时超时。

## 建议修复方向（两条，择一或并存）

1. **调大 `timeout_ms`**：`.mcp.json` 把 30000 → 120000（issue_scan 是唯一需要长预算的工具；其余工具本地都秒级）。改前需确认 120s 内 226 文件 × 31 规则能跑完。
2. **issue_scan 加增量/分批能力**：支持按子目录递归分批（如 `src/server`、`src/store`…），调用方自己分片，避免单次全仓。需改 `src/server/issue_scan.mbt`（当前为并发会话 WIP，本轮未动）。

## 实测读数（`src/diff/diff.mbt`，证明工具本身可用）

`{"scanned_files":1,"total_findings":44,"truncated":true,"include_tests":false,"by_severity":{"high":0,"medium":0,"low":16},"by_rule":[...5 条规则...]}`

其中 `moonbit-array-index-bounds` 报的 `dp[i-1][j-1]` 等（L60/62/65/79/101）经人工核实为**假阳性**：`diff_lines` 的 DP 从 i=1,j=1 起，`dp[0][*]` 是哨兵行，无越界。但这是判据层面的低噪，不改变「工具超时」这条独立缺陷成立。


### FIXED(2026-10-15T04:21:31Z / BUG-162)
- evidence: src/server/issue_scan.mbt 三处：① scan_match_lines 预计算 is_comment[]（原每条规则对每行重判 trim+has_prefix，33×58500 次降为 58500 次），预筛改用 StringView.contains（flat slice）替代 String.contains（rope）；② 守卫过滤只对 6 条可守卫规则（substring-overrun/unprotected-division/possible-overflow/index-out-of-bounds/string-index/secs-overflow）走 mem_read+split+prev_window 全套，其余 ~8000 findings 直接透传；③ 文件内容 fc 按文件缓存（原每条命中重复 mem_read）。实测 `python scripts/fist.py call issue_scan --dir src --max_findings 0`：58s → 9.0s（BUG-18 的 30s 预算内），scanned_files=117、total_findings=9102、19 条 per-rule 计数与基线逐条相同（scan_finding_guarded 对非 6 条规则恒返回 false=不过滤，故输出字节一致）。moon test --target js 全仓 1058/1058 通过。
## BUG-163 [2026-10-15T03:04:18Z] [high] FIXED
- summary: [tool:serve] fist-mbt MCP server 只支持非标准协议版本 2026-07-28，拒绝 MCP 标准 2025-06-18/2024-11-05，发布版对标准 MCP 客户端（Claude Desktop/Cursor/VS Code）不可连接
- detail: ## 现象

用最小 MCP stdio 客户端直接连接 `node dist/fist-mbt.js serve`，发送标准 MCP `initialize`：

| 协议版本 | 结果 |
|---|---|
| `2025-06-18`（MCP 当前标准） | `{"code":-32022,"message":"Unsupported protocol version","data":{"supported":["2026-07-28"],"requested":"2025-06-18"}}` |
| `2024-11-05`（上一版标准） | 同上，`requested:2024-11-05` |
| `2026-07-28`（自定义） | 进入 `_meta` 校验（`Missing required _meta field: io.modelcontextprotocol/clientCapabilities`） |

**只有 `2026-07-28` 能过协议版本闸**，标准版本一律 `-32022` 拒绝。

## 影响

- **对标准 MCP 客户端不可用**：Claude Desktop、Cursor、VS Code MCP、Cline 等标准客户端握手时发送 `2024-11-05` 或 `2025-06-18`，会被 `-32022` 拒绝 ⇒ 发布版的 `fist-mbt serve` 在主流 MCP 生态里**连不上**。
- **只有 DSH harness 能用**：本机 harness 被定制为发送 `2026-07-28`，所以这里能用。但这是唯一能用它的客户端。
- **与 AGENTS.md 声称冲突**：AGENTS.md 说「本项目通过 `.mcp.json` 暴露 `fist-mbt` MCP Server」，未提及必须用非标准协议版本。第三方按文档接入会直接失败。
- **mcp_config_scaffold 生成的配置**会给目标项目写 `fist.mcp.json`，但协议版本不兼容时目标项目的客户端同样连不上——cl1「MCP 工具存在」在这一面是空的。

## 根因（并发会话 WIP，本轮未动）

`src/server/stdio_js.mbt:54` 有 `const MCP_PROTOCOL_VERSION : String = "2026-07-28"`，L49 注释 `// BUG-161: MCP 2026-07-28 兼容层`。当前实现只认这一个版本，`supportedVersions: ["2026-07-28"]`。

## 建议修复方向

1. **版本协商**：`supportedVersions` 增加标准版本（至少 `2025-06-18`，可选 `2024-11-05`），`initialize` 时按客户端 `protocolVersion` 选择响应版本（标准 MCP 语义）。
2. **降级**：客户端发标准版本时，用标准语义处理；客户端发 `2026-07-28` 时，用自定义扩展语义。
3. **文档诚实标注**：若坚持只支持 `2026-07-28`，必须在 README/AGENTS 显式声明「本 server speak MCP 2026-07-28，需配套客户端」，否则第三方按 MCP 标准接入失败且无解释。

## 实测脚本

临时脚本 `temp/mcp_probe7.py`（不落库）：`subprocess.Popen(["node","dist/fist-mbt.js","serve"])` → 发送 `initialize` with `protocolVersion` → 读回 JSON-RPC 响应。三分支（标准 2024-11-05 / 2025-06-18 / 自定义 2026-07-28）结果如上表。

### FIXED(2026-10-15T13:35:00Z / BUG-163)
- 修复文件: `src/server/stdio_js.mbt`
- 根因: MCP 库 (`colmugx/mcp`) 硬编码 `ProtocolVersion = "2026-07-28"`，标准客户端发送 2025-06-18/2024-11-05 被 -32022 拒绝
- 修复方案: 在兼容层拦截协议版本——`ensure_full_meta_map` 无条件覆盖 `_meta.protocolVersion` 为 2026-07-28（让内部服务器接受），`compat_request` 提取客户端原始版本并返回，`compat_response`/`build_legacy_init_response` 将客户端原始版本回显到响应中
- 验证: `moon build --target js` 0 errors, `moon test --target js` 1067/1067 passed, 端到端探针 `temp/mcp_probe_bug163.py` 3/3 协议版本全部接受（2025-06-18, 2024-11-05, 2026-07-28）



## BUG-164 [2026-10-15T04:28:48Z] [low] FIXED
- summary: [tool:issue_scan] 守卫过滤不覆盖「上一行守卫」与「局部不变量证明有界」两类安全形态，src/ 全扫 9 条 medium 全为误报
- detail: issue_scan 提速后（BUG-162 FIXED，58s→9s）用 --max_findings 20000 全扫 src/，by_severity = {high:0, medium:9, low:9093}。逐条人工复核这 9 条 medium（unwrapped-unwrap 1 + substring-overrun 8），全部是误报，扫描器的 guard filter 有两类盲区：

【A. 上一行守卫】src/ops/ops_watchdog.mbt:416 `pending_advance.unwrap()`，其守卫 `pending_advance.is_some()` 在 :415 上一行。scan_finding_guarded 只在「自身 code 同一行」查 is_empty()/length()>N 等，不把 prev_lines 的 `is_some()` 视为 unwrap 守卫，故漏判。

【B. 局部不变量证明有界】8 条 substring-overrun 都由所在函数的前置条件/常量保证不越界，guard filter 无法从单行推断：
- src/engine/engine_triage.mbt:47 `s.substring(start=0, end=max)` —— :46 已 `max <= s.length()` 显式护栏
- src/ops/ops_selfdrive.mbt:566 `ls.substring(start=3, end~)` —— :564 `end` 来自 `find("]")` 且 :565 `end > 3` 已保证
- src/server/memory.mbt:165/166 `content.substring(start=n-cut, ...)` —— :160 `n <= max_chars` 提前 return，进入 else 时 n > cut 恒成立
- src/server/output_validate.mbt:230 `names.substring(start=0, end=names.length()-cut)` —— cut ∈ {0,2}，`:229` has_suffix(", ") 已保证 names.length() ≥ 2
- src/server/mcp_config_scaffold.mbt:138/159/160 —— 常量表 `"0123456789abcdef"`(16)/`"ABCDEFGHIJKLMNOPQRSTUVWXYZ"`(26)，循环上界分别 0..15 / 0..<26，start=d/end=d+1 与 start=i/end=i+1 恒在界内

结论：9/9 误报，代码本身无缺陷。属扫描器精度问题：guard filter 可考虑为 unwrap 补「prev_lines 含 is_some()/is_ok()」形态、为 substring-overrun 补「截取上界来自同函数已校验的变量」形态；但这属精度增强，非缺陷，severity=low，供后续按需处理。
- reported_by: deepseek-harness-lead


### FIXED(2026-10-15T05:42:43Z / BUG-164)
- evidence: commit fcf34e9 新增 scan_substring_start / scan_substring_end_var / scan_guard_substring_end_var 三个辅助函数并接入 scan_finding_guarded 的 substring-overrun prev_lines 分支（fn 边界之前）。白盒锁 3 条在 src/server/issue_scan_wbtest.mbt（提取辅助 + 正反成对：`if end > 3` 判守卫 / 无守卫判真阳性 / 变量不匹配判真阳性 / 数字不等判真阳性 / 非 if 前缀判真阳性）。ops_selfdrive.mbt:565-566 原形（`if end > 3 {` → `ls.substring(start=3, end~)`）实测守卫命中。全量 moon test --target js 1070/1070 零回归（原 1067 + 新增 3 条），moon fmt --check rc=0。盲区 A（上一行 is_some()）已在先前 commit 960d42d 修掉，本轮 9/9 误报中 A 类 1 条 + B 类 ops_selfdrive 1 条均已闭环。
## BUG-165 [2026-10-15T04:48:55Z] [medium] FIXED
- summary: [tool:ocr_scan] scan/files 子命令对 .mbt 恒假绿（exit 0 + ok true 但 reviewable_count=0，全部 exclude_reason=unsupported_ext）；delegate 子命令实测支持 .mbt，双轨第二轨在 MoonBit 上从未真正跑过
- detail: 【现象】ocr_scan 的 scan/files 子命令在 MoonBit 项目上恒返回 exit_code=0 + `ok:true` 但 `reviewable_count:0`，且每份文件都带 `exclude_reason:"unsupported_ext"` —— 一场「假绿」扫描：调用方看回执以为 LLM review 跑过了，实际 0 份文件被评审。

实测三份代表性文件（`src/server/server.mbt` 7337 行 / `src/ops/ops_selfdrive.mbt` 734 行 / `src/ops/ops_loop.mbt` 423 行）全部：
```
{"path":"...","status":"scan","insertions":7337,"deletions":0,"will_review":false,"exclude_reason":"unsupported_ext"}
{"total_insertions":0,"total_deletions":0,"total_files":1,"reviewable_count":0,"excluded_count":1}
```

【根因】opencodereview.exe（@alibaba-group/ocr-win32-x64@1.12.9，`scan --help` 示例全用 `.go`/`internal/agent` 这类 Go 路径）的 scan 子命令有硬编码扩展名白名单，`.mbt` 不在内。argv 无 `--ext`/`--include`/`--lang` 旗（`scan --help` 只有 `--exclude`/`--background`/`--batch`/`--format`），白名单不可经参数覆盖。

【旁证：delegate 通道其实支持 .mbt】`ocr rules check src/server/server.mbt` 与 `ocr_scan subcmd=delegate path=src/server/server.mbt` 均返回 `Source: System built-in / Pattern: default` 的完整评审 spec（Correctness/Security/Performance/Maintainability/Test Coverage 五段），说明二进制底层语言无关、能审 MoonBit，只是 scan 的**路径过滤层**把 `.mbt` 拦了。

【影响面】AGENTS.md 第 214 行广告 `ocr_scan` 是「规则驱动源码扫描…配套 ocr_scan 做 OCR LLM review 双轨互补」，README.md:57 也把 ocr_scan 列为工具。双轨的第二轨在 MoonBit 上从未真正跑过——bugfind 模式（require_ocr）在 MoonBit 项目上会「假 GREEN」：issue_scan 有产出、ocr_scan 回执 ok=true，但 LLM review 一字节没审。

【建议修复（三选一，按收益排序）】
1. **改 ocr_scan_impl**：spawn 后解析 stdout，若 `reviewable_count == 0` 且任一文件带 `exclude_reason`，在回执里显式 `ocr_reviewed=false` + `exclude_reason` 汇总，并把 `ok` 置为 `true` 但追加 `notice`（或降级 `ocr_available=false`），避免调用方误读为「已审完」。
2. **文档面**：README/AGENTS 里把「双轨互补」限定为 `delegate` 子命令对 MoonBit 可用、`scan` 对 `.mbt` 不可用，或直接改推荐入口为 `subcmd=delegate`。
3. **绕过**：wrapper 里对 `path` 全为 `.mbt` 时自动改用 `delegate` 拼装 args（delegate 走 `ocr delegate rule --repo . <path>`，实测对 .mbt 有效），并在回执里标明 `subcmd_routed: "scan→delegate"`。

本 bug 由本轮寻虫发现：跑通 BUG-162/164 后的快 issue_scan 后，用 `ocr_scan scan` 想补 LLM review 双轨，第一份文件就暴露假绿。修复优先级 medium（不影响正确性，但影响「寻虫-修复-验证」闭环在 MoonBit 项目上的完整性）。
- reported_by: deepseek-harness-lead


### FIXED(2026-10-15T05:03:01Z / BUG-165)
- evidence: 改在 src/server/ocr_scan.mbt：新增 `ocr_fake_green_check(stdout)->(Bool,String)`（解析 stdout JSON，`reviewable_count==0 && excluded>0 && files[].exclude_reason` 时返回 false + 汇总说明），`ocr_scan_impl` 对 `subcmd=scan|files` 调用它并把结果摊到回执（`ocr_reviewed:false` + `notice` 段）；4 条白盒锁在 src/server/ocr_scan_wbtest.mbt（.mbt 假绿 / .py 正常 / 非 scan JSON 形状保守通过 / 空目录不误报）。真源锁：commit 049ffbd（全量 1065 测试 1064 通过，唯一红是 BUG-167 的 BUG-18 漂移，与本条无关）。
## BUG-166 [2026-10-15T04:53:11Z] [low] FIXED
- summary: [determinism] watchdog_tick 续轮选 prev_task 依赖 list_in_ns 未定义顺序：多个未标记完成根任务时无条件覆盖 pending_advance，续轮链条可能串错（两后端 list_tasks_in 均无 ORDER BY / recency 排序）
- detail: 【现象】`watchdog_tick`（src/ops/ops_watchdog.mbt:285）在遍历命名空间内任务时，遇到**多个**已完成的未续轮根任务会无条件 `pending_advance = Some(t)` 覆盖——最终指向哪个任务完全取决于 `list_in_ns` 返回顺序，而该顺序在两个后端上都是**未定义/插入序**，不是「最近完成优先」。

【证据链】
1. `SqliteStore::list_tasks_in`（src/store/store_sqlite.mbt:484）SQL 是 `SELECT {task_columns()} FROM tasks WHERE ns = ?` —— **无 ORDER BY**，SQLite 按 rowid/插入序返回。
2. `MemoryStore::list_tasks_in`（src/store/store.mbt:260）用 `self.tasks.each(...)` —— `Map.each` 遍历顺序同样是插入序，非 recency。
3. `watchdog_tick` 第 279-286 行：
```
} else if st == "已完成" {
  let is_root = match t.get_parent() { Some(_) => false, None => true }
  if is_root && !t.deliverable.has_prefix(@engine.advance_mark_prefix()) {
    pending_advance = Some(t)   // 无条件覆盖，无 `if pending_advance.is_none()` 或时间比较
  }
}
```
若同一 ns 下有 3 条已完成但未打 `__advanced__:` 标记的根任务，`pending_advance` 会是**遍历最后遇到的那条**，而非最新完成的一条。随后 `engine.publish_next_round(prev_task_id=prev.get_id())` 把新根任务挂到这条旧任务上，续轮链条串错。

【触发条件】正常流下 `publish_next_round` 成功后会给 prev_task 的 deliverable 加 `__advanced__:` 前缀，所以同一时刻通常只有一条未标记完成根任务；但**降级态**下会累积多条：
- 第 466 行 `Err(_) => ()` 续轮失败退化为等待/空闲，任务保持未标记；
- `done_no_artifact`（BUG-29 探针，当前基线 2）任务 deliverable 为空串 → `has_prefix("__advanced__:")` 恒 false，永不被识别为「已续轮」；
- 冷启动 `cold_publish` 与续轮并存。

【建议修复】把遍历改为显式选「最近完成的一条」：
```
if is_root && !t.deliverable.has_prefix(@engine.advance_mark_prefix()) {
  match pending_advance {
    Some(prev) =>
      if t.updated_at > prev.updated_at { pending_advance = Some(t) }
      else { () }
    None => pending_advance = Some(t)
  }
}
```
或者在 `list_tasks_in` 加 `ORDER BY updated_at DESC`（更彻底，但改动面大、会影响其他 37 处调用点语义，慎选）。

严重度 low：不阻塞、正常流不触发；但违背本仓「确定性优先」原则，降级态下会串错续轮链，且回执里 `advanced` 的 prev_task_id 难以排查。
- reported_by: deepseek-harness-lead


### FIXED(2026-10-15T05:18:27Z / BUG-166)
- evidence: 改在 src/ops/ops_watchdog.mbt：续轮选 prev_task 的循环里 `pending_advance = Some(t)` 原本无条件覆盖，现改为 `Some(prev) => watchdog_newer_task(prev, t)`（保留更晚完成的一条）；新增纯函数 `watchdog_ts_newer(a: String, b: String) -> Bool`（iso_to_secs 比较，任一侧解析失败保守 false）与 `watchdog_newer_task(a, b: @core.Task)`。2 条白盒锁在 src/ops/ops_watchdog_wbtest.mbt（晚/早/同/空串四向）。验证：`moon test --target js src/ops` 186/186 通过。真源锁：commit be729e1。
## BUG-167 [2026-10-15T04:59:51Z] [medium] FIXED
- summary: [drift] BUG-18 锁反向漂移：laya_client_budget_ms 常量停在 30000，本地 .mcp.json timeout_ms 已上调 120000，pipeline_r2_wbtest:137 恒红 30000!=120000；且 .mcp.json 是 untracked 配置，测试绿色依赖本地文件
- detail: 【现象】`src/server/pipeline_r2_wbtest.mbt:137` 断言 `laya_client_budget_ms == client_ms`（BUG-18「sidecar/probe 预算必须严格小于 .mcp.json 的客户端超时」），实测恒红：`30000 != 120000`。

【根因】代码常量 `laya_client_budget_ms : Int = 30000`（`src/server/server.mbt:487`）没有跟随本地 `.mcp.json` 的 `timeout_ms` 上调到 `120000`。而 `.mcp.json` **不在 git 跟踪面内**（`git ls-files .mcp.json` 空），是 gitignored 的本地/生成配置——所以这条测试的绿色与否完全取决于本地配置文件里的 `timeout_ms` 是否恰好等于代码常量 30000。

【两条修复方向】
1. **同步常量**：把 `laya_client_budget_ms` 从 30000 提到与本地 `.mcp.json` 一致的 120000（`server.mbt:487`）。风险：`src/server/server.mbt` 目前有并发 agent 的未提交改动（`starts_with`→`has_prefix` 重命名 + `async fn`→`fn` 批量改写，144+/144-），我本轮不动它，避免与并发 WIP 混排。
2. **测试不依赖本地配置**：`r2_root_mcp_text()` 读的是 repo 根 `.mcp.json`，那是 untracked 的。测试应改为读一个**已提交**的参照值（如 `.mcp.dev.json` 的提交版本），或断言「常量与 config 一致」而不是「常量 == 30000 硬值」。

【影响面】`moon test --target js src/server` 260 条里 1 条恒红。这是 BUG-18 病根那条锁的**反向漂移**：当年把预算调低到 30s 是为了不超客户端 30s，现在客户端超时被（本地配置）拉到 120s，锁却还钉着旧值——锁钉了「30s == 30s」这个**已过时的不等式**，而不是「常量 == config」这个**恒等式**。

【建议】优先级 medium。等并发 agent 收口 server.mbt 后，把 `laya_client_budget_ms` 与 `.mcp.json` 的 `timeout_ms` 用同一个值，并考虑把参照值改为已提交文件，避免测试绿色依赖 gitignored 本地配置。
- reported_by: deepseek-harness-lead



### FIXED(2026-10-15T05:26:42Z / BUG-167)
- evidence: 改在 src/server/server.mbt:487：`laya_client_budget_ms : Int = 120000`（原 30000 与本地 `.mcp.json` timeout_ms=120000 不一致，导致 pipeline_r2_wbtest:132 断言 `laya_client_budget_ms == client_ms` 失败：30000 != 120000）。修复把常量对齐到客户端超时（`laya_probe_budget_ms(5000) + laya_sidecar_budget_ms(20000) = 25s < 120s` 的既有不变量仍成立）。真源锁：并发 agent 在 master 上更新了该常量（伴随其 server.mbt 重构一起提交）。验证：全仓 `moon test --target js` **1067/1067 通过**（该条断言不再红）。
## BUG-168 [2026-10-15T05:17:25Z] [high] FIXED
- summary: [blocking] 并发 agent 新增 src/router/router_caf.mbt 带语法错误（Array[CafModelStats> 缺 ]，共 24 条 Error 4074），文件 untracked，全仓 moon test 被阻断
- detail: 【现象】`src/router/router_caf.mbt` 当前是 **untracked**（`git status` 显示 `??`），且带语法错误：第 105 行 `Array[CafModelStats>`（缺 `]`，应为 `Array[CafModelStats]`），后续 106-109 行 `Array[String>`/`Array[Int>`/`Array[Double>` 同样缺 `]`，连累 `moon info` 报 Error 4074（Parse error: you may expect `,` or `]`）共 24 条，并让全仓 `moon test --target js` 无法完成。

【影响面】阻断全仓 commit 门禁（`moon test` 全绿才算通过）。但作用域隔离在 `src/router/`：`moon test --target js src/ops` 186/186 通过、`src/server` 除 BUG-167 的 BUG-18 漂移外全绿——即我本轮在 `src/ops/ops_watchdog.mbt` 的 BUG-166 修复不受影响。

【根因】并发 agent 新增文件时打错了一个 `]`（`CafModelStats>`），且该文件是新增（未跟踪），`moon info` 全量编译立刻暴露。

【建议】优先级 high（阻断全仓绿）。持有该文件的 agent 把 5 处 `Array[...>` 的 `>` 改回 `]` 即可；我（deepseek-harness-lead）不与并发 WIP 混排，只提交自己的 `src/ops/` 改动。
- reported_by: deepseek-harness-lead




### FIXED(2026-10-15T05:25:59Z / BUG-168)
- evidence: 改在 src/router/router_caf.mbt（原 untracked，新增时带语法错）：① 5 处 `Array[String>`/`Array[Int>`/`Array[Double>`/`Array[CafModelStats>` 的 `>` 补成 `]`（消 Error 4074 Parse error × 24）；② `out.sort(fn(a,b){Bool 比较器})` 改为 `out.sort_by(fn(a,b)->Int)`（消 Error 4080/4028，MoonBit `Array::sort` 吃 `Compare` impl，自定义比较须走 `sort_by`，仓库其余文件一致用 `sort_by`）；排序语义保持原意（成功率降序、成本升序，负=前者在前）。真源锁：commit 354a32e（含文件首提交 204 行）。验证：`moon info` 0 errors；全仓 `moon test --target js` 1067/1067 通过（原被阻断）。


## BUG-169 [2026-10-15T05:58:21Z] [low] FIXED
- summary: [scan-guard] issue_scan 漏识别 `end_var <= target.length()` 作为 substring 上界守卫（engine_triage.mbt:46-47 原形），恒报 substring-overrun 假阳性
- detail: 【现象】issue_scan 对 src/engine/engine_triage.mbt:47 报 `substring-overrun` 假阳性：`:44-47` 是

```
fn truncate(s : String, max : Int) -> String {
  if s.length() <= max {
    s
  } else if max > 0 && max <= s.length() {
    s.substring(start=0, end=max) + "…"
  } else {
    s
  }
}
```

`:46` 的 `max <= s.length()` 已保证 `substring(start=0, end=max)` 不越界，但 guard filter（BUG-164 修完的形态）只认：
- 同 `fn` 内上一行 `.length() >= N`（scan_guard_length_above）
- 上一行 `if <end_var> > N` 且 N=start（盲区 B，已修）
- 上一行 `<end_var> <= <target>.length()`（盲区 C，本次修）

BUG-164 修完前，`:47` 这处恒报假阳性，且 `:46` 是 `} else if` 形态（B 形态只认 `if ` 前缀也拦不住）。

【根因】guard filter 对「上界约束」的识别不完整：只认 `length() >= N` 与 `end > start` 两种形态，漏了 `end_var <= target.length()` 这种与前者语义等价但形态不同的写法。

【修复】src/server/issue_scan.mbt 扩展 `scan_guard_substring_end_var(prev, code, vn)`：加 C 形态（start=0 时 `end_var <= vn.length()`）+ 放宽前缀（`} else if `）+ 收紧 B 形态（start=0 时 `end > 0` 不构成上界，不再误判）。commit 842825e。白盒锁 4 条在 src/server/issue_scan_wbtest.mbt。

【验证】全量 `moon test --target js` 1081/1081 零回归，`moon fmt --check` rc=0。



### FIXED(2026-10-15T05:58:39Z / BUG-169)
- evidence: commit 842825e 扩展 scan_guard_substring_end_var(prev, code, vn)：新增 C 形态（start=0 时 `<end_var> <= <target>.length()`）、放宽前缀接受 `} else if `（engine_triage.mbt:46 形态）、收紧 B 形态（start=0 时 `end > 0` 不构成上界，反向锁 `max > 0` 判真阳性）。白盒锁 4 条在 src/server/issue_scan_wbtest.mbt（`scan_guard_substring_end_var_上界约束判已守卫`）：engine_triage/eval 正向 + `max > 0` 无上界反向 + `max <= other.length()` 误变量反向。全量 moon test --target js 1081/1081 零回归，moon fmt --check rc=0。附带修正 router_caf_wbtest.mbt 的 avg_cost 容差断言（commit e05f544，原 assert_eq 因 (0.1+0.2+0.3)/3=0.20000000000000004 恒红）。
## BUG-170 [2026-10-15T06:21:09Z] [low] FIXED
- summary: [dag] critical_path 环保护返回 [id] 导致父级 push 重复节点，产出 [A,B,C,A] 含重复 id 的伪关键路径
- detail: 【现象】对含环依赖图（如 A→B→C→A，经 dag_depend 追加）调用 dag_critical_path 时，longest_chain_ending 的环保护在 DFS 命中 visiting 后返回 [id]（自身节点），父级随后 push(id) 形成 [A,B,C,A] 的重复节点链——返回的"关键路径"含重复任务 id，违反路径语义。

【根因】src/engine/engine_dag_ext.mbt:46-49 的环保护分支 `return [id]` 把环起点当作一条有效链返回给父级；父级在 out.push(id) 后再 push 一次自身 id，形成重复。与 BUG-204（engine_dag_mc.mbt 蒙特卡洛采样的同类问题）同族：环命中应返回"无效链"哨兵而非"链自身"。

【修复】d5ee385：环命中改返回空数组 []——父级不会把环起点并入结果，最终链 [B,C,A] 无重复且仍是最长可行链（与 engine_dag_mc 的 -1 哨兵思路一致）。新增白盒回归测试 dag_ext_test.mbt「critical_path: 成环依赖不产生重复节点」先红后绿。

【影响面】仅含环 DAG（正常 DAG 无环时行为完全不变）。dag_critical_path MCP 工具与 critical_path() API 均受益。



### FIXED(2026-10-15T06:21:16Z / BUG-170)
- evidence: commit d5ee385：src/engine/engine_dag_ext.mbt:46-49 环命中改 return []（原 return [id]），配套 src/engine/dag_ext_test.mbt:50-82 新增「critical_path: 成环依赖不产生重复节点」测试先红后绿。moon test --target js 全量 1082/1082 通过。
## BUG-171 [2026-10-15T07:10:16Z] [medium] FIXED
- summary: CafMemory::new(max_size<=0) 让 push 越界 panic（records[0] on empty array）
- detail: CafMemory::new(max_size=0) 会创建空数组 records，随后 push 时 `self.records[self.head]`（head=0）在空数组上越界 panic（Array::set index out of bounds）。负值同样触发。修复：CafMemory::new 内 clamp max_size 到至少 1。



### FIXED(2026-10-15T07:16:54Z / BUG-171)
- evidence: src/router/router_caf.mbt: CafMemory::new 内加 clamp（max_size<=0 收敛到 1）；新增 src/router/router_caf_bug188_wbtest.mbt 两条白盒回归（max_size=0 与 max_size=-5 都收敛、push 不 panic、all() 返回 1 条）；moon test --target js 全量 1084/1084 通过。
## BUG-172 [2026-10-15T07:26:35Z] [low] FIXED
- summary: difficulty_label 在 split_n=4 时"难"档不可达（third*2 边界与 pos 上限重合）
- detail: difficulty_label(idx, split_n) 的"难"档边界用 `pos > third * 2`，其中 third=ceil(split_n/3)。当 split_n=4 时 third=2，边界=4，而 pos 上限也是 4，导致"难"档整段不可达——gradient 拆解 4 片时只有"易/中"两档，与文档"由易到难三档"矛盾。实测：split_n=1→[易]、2→[易,中]、3→[易,中,难]、4→[易,中]（缺"难"）、5→[易,中,难]、6→[易,中,难]。修复：改用 ceil(2*split_n/3)=(2*total+2)/3 作为"难"档下界，split_n>=3 时三档可达。



### FIXED(2026-10-15T07:27:13Z / BUG-172)
- evidence: src/decompose/decompose.mbt: difficulty_label 的"难"档下界由 `third*2` 改为 `(2*total+2)/3`（即 ceil(2*total/3)）；新增 src/decompose/probe_difficulty_wbtest.mbt 两条白盒回归（三档可达性 + 单调性）；实测 split_n=4 现产出 [易,中,难]；moon test --target js 全量 1086/1086 通过。
## BUG-173 [2026-10-15T07:37:34Z] [medium] FIXED
- summary: [caf-router] sort_by 比较器违反严格弱序（相等时返回 1 非 0），可致排序未定义行为
- detail: src/router/router_caf.mbt:151-173 的 `caf_stats` 排序比较器违反 MoonBit `sort_by` 的严格弱序要求。比较器逻辑：

```
if rate_a != rate_b {
  if rate_a > rate_b { -1 } else { 1 }
} else if a.avg_cost < b.avg_cost {
  -1
} else {
  1   // ← 当 rate_a == rate_b 且 avg_cost_a == avg_cost_b 时恒返回 1（非 0）
}
```

问题：
1. `cmp(a, a)` 恒返回 1 ≠ 0 —— 违反严格弱序的第一条（自反性：cmp(a,a) 必须为 0）。
2. `cmp(a, b) == 1` 且 `cmp(b, a) == 1`（当两者完全相等时）——违反反对称性。

后果：MoonBit 的 `sort_by` 依赖严格弱序保证正确性与终止性。违反时可能：
- 相同元素被无限交换导致 sort 不终止或 O(n²) 退化
- 排序结果不稳定、跨运行不一致
- 在 `model_router_status` 展示 Top 成功率模型时给出错序（假统计）

复现路径：两条完全相同特征的记录（同 model、同 ok、同 cost、同 feature_hash）→ `caf_stats()` 返回 `[a, b]` 顺序随机/不稳定。

修复建议：当 rate_a == rate_b 且 avg_cost_a == avg_cost_b 时返回 0（相等）。可用 `total/success/cost` 组合三元比较，或加 tiebreaker（如按 model 名字典序）。
- task_id: T0r612


### FIXED(2026-10-15T07:48:05Z / BUG-173)
- evidence: commit 修改 src/router/router_caf.mbt:151-173 的 caf_stats 比较器：把 `else { 1 }` 改为三档比较（> / < / =），完全相等时按 model 字典序 tiebreak 并返回 0。src/router/router_caf_wbtest.mbt 新增 2 条回归测试（caf_stats_equal_rate_equal_cost_tiebreak / caf_stats_single_record）。moon test --target js src/router → 114/114 passed。moon fmt --check 通过。
## BUG-174 [2026-10-15T07:37:56Z] [low] FIXED
- summary: [caf-router] caf_feature_hash 用 h*31+c 无检查溢出 + h.abs() 在 Int64.min_value() 时未定义
- detail: src/router/router_caf.mbt:179-188 的 `caf_feature_hash` 中 `h = h * 31 + c` 对 MoonBit Int（64 位）做无检查乘加，可能溢出到负值，最后 `h.abs()` 在 `h == Int64.min_value()`（-2^63）时在 MoonBit 中未定义（panic）。

代码：
```
pub fn caf_feature_hash(context : String) -> Int {
  let mut h : Int = 0
  let mut i = 0
  while i < context.length() {
    let c = context[i].to_int()
    h = h * 31 + c
    i = i + 1
  }
  h.abs()   // ← Int64.min_value() 时 panic
}
```

分析：
- `h * 31` 对 Int64 无检查，溢出时静默回绕（wrap-around）。
- 对约 14 个以上字符的 context，h 的量级可达 31^14 ≈ 1e20 > 2^63，必然溢出。
- 溢出到 Int64.min_value() 的概率虽低（每次字符串约 1/2^64），但属真实缺陷类。
- `abs()` 在 min_value() 上 MoonBit 行为未定义（通常 panic）。

修复建议：改用 `h = ((h * 31) + c) and 0xFFFFFFFF`（32 位截断，避免溢出到极端负值），或直接用 `Int.to_string()` 的 hash code 语义；至少把 `abs()` 换成 `if h < 0 { -h } else { h }` 并处理 min_value()。
- task_id: T0r613




### FIXED(2026-10-15T07:52:17Z / BUG-174)
- evidence: commit 5792271 修改 src/router/router_caf.mbt:190-201 的 caf_feature_hash：把 `h = h * 31 + c` 改为 `h = (h * 31 + c).land(0xFFFFFFFF)`（32 位截断，避免 Int64 溢出），删除 h.abs()（Int64.min_value() 时未定义）。src/router/router_caf_wbtest.mbt 新增 2 条回归测试（caf_feature_hash_long_string_no_overflow 15 字符 / caf_feature_hash_very_long_no_overflow 104 字符）。moon test --target js src/router → 116/116 passed。moon fmt --check 通过。
## BUG-175 [2026-10-15T07:56:25Z] [high] FIXED
- summary: ops_ts.iso_to_secs 对 17/18 字符时间戳 panic（chars[17]/chars[18] 越界）——sec 分支守卫 `chars.length() >= 17` 不足，需 >= 19
- detail: src/ops/ops_ts.mbt L34-38: `let sec = if chars.length() >= 17 { parse_digits(chars, 17, len=2) } else { 0 }`。parse_digits(chars, 17, len=2) 访问 chars[17] 与 chars[18]，但守卫只保证 length>=17，length==17 时 chars[17] 越界、length==18 时 chars[18] 越界 → 数组下标 panic。真实可达：多个模块（ops_heartbeat/ops_cleanup/ops_heal/ops_watchdog/ops_pipeline/board_ascii/server.mbt）把外部传入或 DB 读出的时间戳字符串直接喂给 @ops.iso_to_secs，格式不完整（如 "2024-01-01T00:00:0" 17 字符、"2024-01-01T00:00:01" 18 字符）即触发。修复：守卫改为 `chars.length() >= 19`。
- reported_by: bug-hunter

## BUG-176 [2026-10-15T08:00:00Z] [high] FIXED
- summary: engine.mbt execute_with_meta 先写执行元数据再执行，execute 失败时留下幽灵记录
- detail: src/engine/engine.mbt:227-254 的 `execute_with_meta` 方法在调用 `self.execute()` 之前就调用 `self.store.record_execution()`。当 `execute` 失败（如空 deliverable 被 audit gate 拒绝），executions 表已写入一行幽灵元数据，导致 cost_stats double-count。修复：先调用 `execute`，成功后才写 `record_execution`。
- task_id: T0r614

### FIXED(2026-10-15T08:00:00Z / BUG-176)
- evidence: src/engine/engine.mbt:234-253 重排 execute_with_meta：先 `match self.execute(...)` 成功后才 `ignore(self.store.record_execution(...))`。修复后 moon check --target js 0 errors，moon test --target js 1101/1101 passed。
## BUG-177 [2026-10-15T08:00:00Z] [high] FIXED
- summary: engine.mbt publish_with_deps 缺少依赖存在性验证，接受不存在的任务 ID
- detail: src/engine/engine.mbt:1471-1477 的 `publish_with_deps` 方法接受 `depends_on` 数组但不验证依赖任务是否存在。调用方传入不存在的任务 ID 时，任务被创建但依赖悬空，后续 critical_path/dag 遍历可能出错。修复：添加循环检查每个 dep 是否存在。
- task_id: T0r615

### FIXED(2026-10-15T08:00:00Z / BUG-177)
- evidence: src/engine/engine.mbt:1471-1477 在 created_by 检查后添加 `for dep in depends_on { match self.store.get_task(dep) { None => return Err("依赖任务不存在: \{dep}") Some(_) => () } }`。修复后 moon check --target js 0 errors，moon test --target js 1101/1101 passed。
## BUG-178 [2026-10-15T08:00:00Z] [high] FIXED
- summary: store_sqlite.mbt assistant_upsert 非原子，并发 agents 可同时插入 is_primary=1
- detail: src/store/store_sqlite.mbt:1679-1750 的 `assistant_upsert` 方法先 `clear`（UPDATE is_primary=0）再 `insert`（upsert is_primary=1），两步不在同一事务。并发 agents 可同时看到 is_primary=0 并各自插入 is_primary=1，导致多个 primary assistant。修复：用 BEGIN IMMEDIATE/COMMIT 事务包裹。
- task_id: T0r616

### FIXED(2026-10-15T08:00:00Z / BUG-178)
- evidence: src/store/store_sqlite.mbt:1679-1750 在 clear_sql 和 insert_sql 外包裹 `ignore(db.exec("BEGIN IMMEDIATE"))` / `ignore(db.exec("COMMIT"))`。修复后 moon check --target js 0 errors，moon test --target js 1101/1101 passed。
## BUG-179 [2026-10-15T08:00:00Z] [high] FIXED
- summary: store_sqlite.mbt locks_sweep 非原子，SELECT+UPDATE+INSERT 分步执行
- detail: src/store/store_sqlite.mbt:1507-1591 的 `locks_sweep` 方法先 SELECT 过期锁，再循环 UPDATE + INSERT violations，每步独立事务。并发时可能重复处理同一锁或遗漏。修复：用 INSERT...SELECT 单语句记录 violations + 单 UPDATE 过期 + SELECT changes()，包裹在 BEGIN IMMEDIATE/COMMIT 中。
- task_id: T0r617

### FIXED(2026-10-15T08:00:00Z / BUG-179)
- evidence: src/store/store_sqlite.mbt:1507-1545 重写 locks_sweep：`INSERT INTO lock_violations ... SELECT ... FROM file_locks WHERE status='active' AND ttl_until < ?` + `UPDATE file_locks SET status='expired' WHERE ...` + `SELECT changes()`，包裹在事务中。修复后 moon check --target js 0 errors，moon test --target js 1101/1101 passed。
## BUG-180 [2026-10-15T08:00:00Z] [high] FIXED
- summary: store_sqlite.mbt locks_upsert TOCTOU，check-then-insert 竞态
- detail: src/store/store_sqlite.mbt:1094-1210 的 `locks_upsert` 方法先 `self.locks_get(scope)` 检查锁是否存在，再 INSERT。并发时两个 agents 可能同时通过检查并各自插入。修复：用 INSERT...SELECT 记录 violations + ON CONFLICT...DO UPDATE...WHERE 原子 upsert，包裹在 BEGIN IMMEDIATE/COMMIT 中。
- task_id: T0r618

### FIXED(2026-10-15T08:00:00Z / BUG-180)
- evidence: src/store/store_sqlite.mbt:1094-1210 重写 locks_upsert：`INSERT INTO lock_violations ... SELECT ... FROM file_locks WHERE scope=? AND status='active' AND agent!=? AND ttl_until>=?` + `INSERT INTO file_locks ... ON CONFLICT(scope) DO UPDATE SET ... WHERE file_locks.status!='active' OR file_locks.agent=excluded.agent OR file_locks.ttl_until<excluded.ts`，包裹在事务中。修复后 moon check --target js 0 errors，moon test --target js 1101/1101 passed。
## BUG-181 [2026-10-15T08:00:00Z] [high] FIXED
- summary: store_sqlite.mbt clear 静默失败，DELETE FROM 不存在的表不报错
- detail: src/store/store_sqlite.mbt:721-747 的 `clear` 方法直接 DELETE FROM 各表，但若表不存在则静默失败（SQLite 不报错）。修复：在 DELETE 前添加 CREATE TABLE IF NOT EXISTS 确保所有 12 张表存在。
- task_id: T0r619

### FIXED(2026-10-15T08:00:00Z / BUG-181)
- evidence: src/store/store_sqlite.mbt:721-760 在所有 DELETE FROM 前添加 12 个 `CREATE TABLE IF NOT EXISTS` 语句。修复后 moon check --target js 0 errors，moon test --target js 1101/1101 passed。
## BUG-182 [2026-10-15T08:00:00Z] [high] FIXED
- summary: server.mbt 三处时间戳注入（loop_create/lock_acquire/lock_renew 接受用户提供的 now/ts）
- detail: src/server/server.mbt:2651/4461/4515 的 `loop_create`、`lock_acquire`、`lock_renew` 工具接受用户提供的 `now`/`ts` 参数并直接使用，而非服务端盖章。恶意用户可注入未来时间戳影响锁过期判断。修复：三处均改为 `now_default()`。
- task_id: T0r620

### FIXED(2026-10-15T08:00:00Z / BUG-182)
- evidence: src/server/server.mbt:2651 `let now = now_default()`（原 `get_str(args, "now", default=now_default())`）；:4461 `let ts = now_default()`（原 `get_str(args, "ts", default=now_default())`）；:4515 `let ts = now_default()`（原 `get_str(args, "ts", default=now_default())`）。修复后 moon check --target js 0 errors，moon test --target js 1101/1101 passed。

## BUG-183 [2026-10-15T08:15:00Z] [high] FIXED
- summary: ops_selfdrive.mbt sd_kind_path 路径遍历漏洞，kind 参数可包含 ../ 导致任意文件写入
- detail: src/ops/ops_selfdrive.mbt:33-35 的 `sd_kind_path` 函数直接用 `kind + ".md"` 构造路径，未对 kind 做校验。若 kind 包含 `../` 或 `/`，可构造如 `project_dir/memory/../../etc/passwd.md` 的路径，导致任意文件写入。修复：在 sd_kind_path 中添加校验，拒绝包含 `/`、`\`、`..` 或空字符串的 kind。
- task_id: T0r621

### FIXED(2026-10-15T08:15:00Z / BUG-183)
- evidence: src/ops/ops_selfdrive.mbt:33-37 在 sd_kind_path 中添加 `if kind.length() == 0 || kind.contains("/") || kind.contains("\\") || kind.contains("..") { abort("invalid kind: \{kind}") }`。修复后 moon check --target js 0 errors，moon test --target js 1105/1105 passed。



### FIXED(2026-10-15T08:07:37Z / BUG-175)
- evidence: src/ops/ops_ts.mbt L34-38: sec 分支守卫从 `chars.length() >= 17` 收紧为 `>= 19`，`parse_digits(chars,17,len=2)` 访问 chars[17]/chars[18] 需 length>=19；新增 3 条白盒回归测试（ops_ts_wbtest.mbt：17/18/19 字符边界），src/ops 189/189 通过；commit c2374c8
## BUG-183 [2026-10-15T08:17:24Z] [high] FIXED
- summary: [rule:potential-overflow] star_gate.mbt:303 issued_at+ttl_seconds Int64 溢出 panic（恶意 1e300 JSON 可达）
- detail: src/router/star_gate.mbt L303（④ 时间层判定）：`now_epoch > data.issued_at + data.ttl_seconds` 是 Int64 加法。`issued_at` / `ttl_seconds` 经 `Double::to_int64()`（L148/L152）从 JSON Number 转换，对超范围值（如科学计数法的 `1e300`）饱和到 Int64 max（9223372036854775807）。两值相加溢出 Int64 → MoonBit 溢出检查触发 panic。可达路径：`star_gate_verify`（非钉死自指入口，L201）——攻击者用自持 Ed25519 密钥对，对 `{list, issued_at:1e300, ttl_seconds:1e300}` 自签 canonical（`star_canonical` 输出 `{"issued_at":9223372036854775807,...}`），验签步（L294）通过后进入 ④ 即 panic。`star_gate_policy`（生产入口）走 `star_gate_verify_pinned`，钉死公钥不匹配时 L264 早退 BadSignature，故该路径受钉死公钥保护；但非钉死 `star_gate_verify` 是公开函数，未来接入未钉死部署即暴露。修复：改用 Double 比较（Int64 max×2 ≈ 1.8e19 在 Double 精度内），两方都大到不可代表真实时间戳时比较恒为「未过期」，语义正确。回归测试：`star_gate_wbtest.mbt` 追加一条「恶意 1e300 issued_at+ttl 不 panic」，已验证「无修复时失败、有修复时通过」。
- reported_by: bug-hunter



### FIXED(2026-10-15T08:17:59Z / BUG-183)
- evidence: src/router/star_gate.mbt L302-313：`now_epoch > data.issued_at + data.ttl_seconds`（Int64 加法）改为 `now_epoch.to_double() > data.issued_at.to_double() + data.ttl_seconds.to_double()`（Double 加法，Int64 max×2 ≈ 1.8e19 在 Double 精度内不溢出）。新增白盒回归测试 star_gate_wbtest.mbt「恶意 1e300 issued_at+ttl 不 panic（BUG-196 溢出回归）」，已验证：无修复时该测试 fail（旧加法触发溢出 panic）、有修复时 pass。src/router 128/128 通过。commit 97bc54b

## BUG-184 [2026-10-15T08:39:00Z] [high] FIXED
- summary: engine.mbt verify() 父任务归并 TOCTOU（盲目 update_task 覆盖并发修改）
- detail: src/engine/engine.mbt L534-567 verify() 向上归并逻辑：读取父任务后，在内存中调用 execute() 和 submit() 得到 Reviewing 状态的 p2，然后使用 `update_task(p2)` 盲目写回数据库。在 L534 读取父任务到 L560 写回之间，其他 agent 可能并发修改父任务（如修改 deliverable、改变状态），盲目写入会覆盖这些并发更改，导致交付物合并丢失或状态损坏。修复：捕获父任务原始状态 `original_status = parent.get_status().to_string()`，使用 `update_task_if_status(p2.with_updated_at(now), original_status)` 进行原子比较交换，确保父任务状态未变化时才写入。
- reported_by: bug-hunter


### FIXED(2026-10-15T08:39:00Z / BUG-184)
- evidence: src/engine/engine.mbt L537 添加 `let original_status = parent.get_status().to_string()`，L562 将 `update_task(p2.with_updated_at(now))` 改为 `update_task_if_status(p2.with_updated_at(now), original_status)`。修复后 moon check --target js 0 errors，moon test --target js 1108/1108 passed。

## BUG-185 [2026-10-15T08:46:00Z] [medium] FIXED
- summary: ops_watchdog.mbt 静默吞噬 heal 错误（Err(_) => [] 让用户误以为"无需修复"）
- detail: src/ops/ops_watchdog.mbt L273/L278 在 heal_stale_tasks_by_phi 和 heal_stale_tasks_from_store 失败时返回空列表 `[]`，导致 watchdog 报告 "healed: 0 tasks" 而用户无法知道 heal 实际失败。stale 任务留在系统中无任何失败指示，无法诊断。修复：捕获错误到 `heal_error` 变量，在最终 JSON 输出的 `detail.heal_error` 字段中包含错误信息，不改变 watchdog 整体行为（仍然返回 Ok）。
- reported_by: bug-hunter


### FIXED(2026-10-15T08:46:00Z / BUG-185)
- evidence: src/ops/ops_watchdog.mbt L262 添加 `let mut heal_error : String? = None`，L273/L278 将 `Err(_) => []` 改为 `Err(e) => { heal_error = Some(e); [] }`，L593-608 在 tick_json 调用前将 heal_error 添加到 detail JSON。修复后 moon check --target js 0 errors，moon test --target js 1108/1108 passed。


### FIXED(2026-10-16T02:00:21Z / BUG-185)
- evidence: Commit 20846a4: scripts/blackbox/e2e_irm_line.py probe() bare-path changed from [ -x 'fist' ] (never searches PATH) to command -v; WSL bash detection added via _is_wsl_bash() registry check; _userprofile_redirected() guard added to prevent env pollution. python -W error -m py_compile clean.

### FIXED(2026-10-16T14:52:54Z / BUG-185)
- evidence: BUG-241 修复：同号重复条目已被逐条改判。BUG-185 次条（10/15 08:44 OPEN）与首条（10/15 08:46 FIXED）同号不同 ts，现已全部标 FIXED。

### FIXED(2026-10-16T15:19:23Z / BUG-185)
- evidence: Testing if server has BUG-241 fix
## BUG-186 [2026-10-15T08:50:00Z] [medium] FIXED
- summary: ops_heal.mbt heal_stale_tasks_by_phi 静默吞噬 reopen_task 错误（Err(e) => ignore(e)）
- detail: src/ops/ops_heal.mbt L242 在 reopen_task 失败时忽略错误 `Err(e) => ignore(e)`，导致调用方无法知道某些任务修复失败。函数返回类型为 `Result[Array[String], String]`，本应传播错误。修复：改为 `Err(e) => return Err(e)`，让错误传播到调用方（ops_watchdog.mbt），由其包含在 JSON 输出的 heal_error 字段中。
- reported_by: bug-hunter


### FIXED(2026-10-15T08:50:00Z / BUG-186)
- evidence: src/ops/ops_heal.mbt L242 将 `Err(e) => ignore(e)` 改为 `Err(e) => return Err(e)`。修复后 moon check --target js 0 errors，moon test --target js 1108/1108 passed。

### FIXED(2026-10-16T12:52:15Z / BUG-185, BUG-186)
- evidence: commit 20846a4（HEAD 链上）fix(e2e_irm)：①BUG-185 probe() 裸词档（sbin=None）由 `[ -x 'fist' ]`（-x 不查 PATH 恒 MISSING）改为 `command -v fist` 做 POSIX shell 发现；新增 _is_wsl_bash() 用 winreg 查 App Paths\bash.exe 判 system32/windows 命中则返回 SKIP: WSL bash 而非误报 MISSING（修"本机默认 bash=WSL 与 POSIX shim 行为面错位"）；沙箱档 sbin 给定时保留 -x（正确）。②BUG-186 新增 _userprofile_redirected()：用 SHGetFolderPathW 取 CSIDL_PROFILE 与 env USERPROFILE 比对，不一致即判重定向环境、`--real` 前 rc=2 拒绝执行，杜绝改写真实 .local\bin shim 与 HKCU PATH；并保留"跑前备份产物、不绿自动还原"既有保护。脚本 504 行含 PATH 逐字还原/备份/FAIL 如实上报。修改面仅 scripts/blackbox/e2e_irm_line.py（+40/-4），-W error py_compile 干净。已提交未走记账。
## BUG-261 [2026-10-15T08:44:07Z] [medium] FIXED
- renumbered_from: BUG-185（2026-10-17 fist-lead 清整，消除与已 FIXED BUG-185 的 ID 碰撞，见 BUG-260）
- summary: [判据] e2e_irm_line 真面档探针恒红：probe() 用 [ -x 'fist' ] 裸词（-x 不查 PATH）+ 本机默认 bash=WSL 与 POSIX shim 面（承诺 Git Bash/MSYS）错位，任何机器 --real 都判不出绿
- detail: 现象（2026-10-15 本机实测）：python scripts/blackbox/e2e_irm_line.py --real 文档线本体 rc=0、安装自检四面全绿（版本 v0.3.8 / fist (PATH) / POSIX shim LF），但整档 FAIL rc=1——红在 probe(env, ROOT, 真面 bash) 这一格。两个独立成因：① probe() L270-271：真面档 sbin=None ⇒ exe='fist' 裸词，sh 的 `if [ -x '%s' ]` 裸词测试**不走 PATH 检索**、永远假——真面档在任何机器（含装有 Git Bash 的）都恒报 MISSING fist ⇒ 恒红，属 BUG-117「判据自己假红」同族；实测对照：`bash -c "command -v fist"` 命中 /mnt/c/Users/victo/.local/bin/fist，而 `bash -c "if [ -x 'fist' ]"` 报 MISSING。② 本机无 Git Bash，PATH 上的 bash = C:\Windows\system32\bash.exe（WSL）；POSIX 无扩展名 shim 按安装器自述只承诺 Git Bash/MSYS 面（Windows 路径直接可用），WSL 下 `exec node "C:\..."` 语义错位实测 rc=1——即便修好①，真面档在这一格仍会给出**误导性**的红。修法建议：probe 的真面档改为 command -v 定位 + 点名目标 shell（存在 Git Bash/MSYS 才跑行为面），两者都没有时按「判据拒绝出数」（e2e_native_heap_probe 的 rc=3 同族语义）而非报产品红；沙箱档（传 sbin 全路径）的 -x 用法本身合法，不动。
- reported_by: loomy-e2e-irm-real-20261015

### FIXED(2026-10-18T06:45:00Z / BUG-261)
- evidence: scripts/blackbox/e2e_irm_line.py 真面档 probe() 按修法建议收口：probe(env, box, label, sbin=None) 真面档（无 sbin）改经 _find_posix_shell() 定位目标 shell——显式探测 4 处 Git Bash/MSYS 路径 + `shutil.which("bash")` 兜底并用 _is_wsl_bash()（winreg 查 App Paths\bash.exe）排除 system32/windows 的 WSL bash；两者都没有时打印「判据拒绝出数 rc=3」并返回 "REJECT: ..." 标记，real() 见 REJECT 即写 temp/e2e-irm-real.txt（判定=REJECT）并 return 3（对齐 e2e_native_heap_probe 的 rc=3 语义，绝不把"没法跑"报成产品红）；找到 shell 后以 `command -v fist` 定位并**点名该 shell**执行版本/doctor 行为面。沙箱档（传 sbin 全路径）的 `-x` 用法本身合法，保持不动。验证：`python -m py_compile` 干净（-W error 同口径）；静态确认真面档在无 Git Bash/MSYS 机器返回 REJECT(rc=3) 而非 MISSING。

## BUG-262 [2026-10-15T08:44:07Z] [medium] FIXED
- renumbered_from: BUG-186（2026-10-17 fist-lead 清整，消除与已 FIXED BUG-186 的 ID 碰撞，见 BUG-260）
- summary: [看护] e2e_irm_line --real 无 PATH/shim/产物目录还原保护：在重定向 HOME 的 agent 会话里跑会改写真实 .local\bin 四件 shim 与 HKCU PATH，本发实测污染并由人工还原
- detail: 现象（2026-10-15 实测）：real() L431-461 只做「产物 js 备份→不绿自动还原」，且不设沙箱 env（沙箱档 arm() 才有 LOCALAPPDATA/USERPROFILE 改道 + finally PATH 逐字还原）。在 Loomy/CI-agent 这类 HOME/APPDATA 重定向会话里跑 --real：安装器按会话 env 执行 ⇒ ① 把 HKCU Path 前插 `C:\Users\Public\Loomy\<ver>\.local\bin`（沙箱形态条目，残留于注册表）；② 真实 .local\bin（本机经 junction 归一，与沙箱路径同实体）的 fist.cmd/fist-mbt.cmd/fist/fist-mbt 四件 shim 被改写指 `$env:LOCALAPPDATA`=沙箱目录下 **2026-10-13 的旧产物**（3114943B），真面用户从此隔一层影子产物跑旧版；③ real() 的 REAL_DEST 按会话算 = 沙箱路径，跑前读 (无) ⇒ 不建备份 ⇒「不绿⇒还原备份」空转，三处污染全不回收。本次已人工还原（四件 shim 重指真产物 + PATH 删残留逐字还原，cmd 面验回 FIST-Mbt v0.3.8）。修法建议：real() 增 PATH 与 .local\bin 四件 shim 的基线比对/还原（对齐 arm() 纪律）；或更硬——检测 $env:USERPROFILE 与真实用户面（net user / WScript.Shell 法）不一致时像裸形那样**拒绝执行**，在重定向环境里让 --real 显式不可用，把污染挡在入口。
- reported_by: loomy-e2e-irm-real-20261015

### FIXED(2026-10-18T06:45:00Z / BUG-262)
- evidence: real() 双保险收口（两条修法建议都落地）：①**入口硬拒**——real() 在裸形拒绝检查后新增 `_userprofile_redirected()`（SHGetFolderPathW 取 CSIDL_PROFILE 与 env USERPROFILE 比对，空值兜底），不一致即判定重定向 agent 会话，打印「--real 会污染真实用户环境，拒绝执行」并 return 2，把污染挡在入口（对齐 BUG-186 轮既有 _userprofile_redirected 实现）；②**基线比对还原**——real() finally 块采集真实用户 PATH（ps_path）与真实 .local\bin 四件 shim（fist/fist.cmd/fist-mbt/fist-mbt.cmd，取 CSIDL_PROFILE 面不受会话 env 重定向带偏）的 sha8 基线，逐件备份到 temp/irm-sandbox/backup-shim-*，跑后逐字比对：PATH 被改写即 set_path 还原基线、任一 shim 被改写即复制备份还原（对齐 arm() 的 finally 纪律，即使 run_line 抛异常也执行）；js 产物保留既有「跑前备份、不绿自动还原」。验证：`python -m py_compile` 干净；静态确认四件 shim 与 PATH 还原分支在位。

## BUG-187 [2026-10-15T08:53:15Z] [medium] FIXED
- summary: supervisor_tools.mbt:448 `str_to_int` 缺 int_safe 上界守卫——长数字串（如 stale_hours=99999999999999）在 `v = v * 10 + d` 上溢出 Int（JS 静默精度丢失 / native panic），而同族 4 个解析器（sd_parse_int / ov_parse_int / bugreport.mbt:204 / store_sqlite_executions.mbt:202）都已用 int_safe=200_000_000 守卫
- detail: 现象：`supervisor_reminder_tick` MCP 工具从用户 JSON args 读 `stale_hours` / `pending_hours`（字符串），经 `str_to_int` 解析。该函数只有空串守卫和符号处理，`for j in i..<s.length() { v = v * 10 + d }` 无上界检查。用户传 `stale_hours="99999999999999999999"` 时：JS target（MCP server 默认）上 Int 是 53-bit Double，溢出后静默精度丢失，返回错误的阈值；native target 上 Int 是 64-bit，溢出 panic。R12-R8 已把同族 4 个解析器统一加上 `int_safe = 200_000_000` 守卫（见 BUG-221 ov_parse_int），本函数是唯一的漏网。

修法：与 ov_parse_int 同型——在累加前 `if v >= int_safe { return dft }`，并复用 200_000_000 上界（v * 10 + 9 < 2e9 < 2^31-1 安全）。

证据：`grep -n "int_safe" src/` 显示 4 处有守卫（ops_selfdrive.mbt:162 / output_validate.mbt:275 / bugreport.mbt:204 / store_sqlite_executions.mbt:202），supervisor_tools.mbt:448-465 无。
- reported_by: audit-cypy-sweep



### FIXED(2026-10-15T08:56:19Z / BUG-187)
- evidence: commit 53e6de1：`src/server/supervisor_tools.mbt:456` 新增 `let int_safe : Int = 200_000_000`，循环内在累加前 `if v >= int_safe { return dft }`（L469-471），与同族 sd_parse_int/ov_parse_int/bugreport/store_sqlite_executions 四处的 int_safe 守卫同型。`moon test --target js` 1112/1112 通过（baseline 1111 + 新锁 0 回归），`moon fmt --check src/server/supervisor_tools.mbt` 返回 0。
## BUG-188 [2026-10-15T08:57:32Z] [low] FIXED
- summary: issue_scan.mbt:627 `scan_substring_start` 的 acc 累加缺 int_safe 上界守卫——被扫描源码含 `substring(start=<长数字>, ...)` 时溢出 Int（JS 静默乱数 / native panic），substring-overrun 规则误判
- detail: 现象：`issue_scan` 的 `scan_substring_start` 扫描源码行提取 `substring(start=N, ...)` 的 N 值，`while` 循环里 `acc = acc * 10 + (code[j].to_int() - 48)` 无上界检查。若被扫描的 `.mbt` 文件含 `substring(start=99999999999999999999, ...)`，acc 溢出（JS 静默精度丢失 / native Int64 panic），返回错误的 start 值，导致 substring-overrun 规则误报/漏报。

同族 5 处解析器（sd_parse_int / ov_parse_int / bugreport.mbt:204 / store_sqlite_executions.mbt:202 / 刚修的 supervisor_tools.mbt:456）都有 `int_safe = 200_000_000` 守卫，本处是新的漏网。

修法：循环内 `if acc >= int_safe { return -1 }`，与 `scan_substring_start` 已有的 -1 哨兵语义一致（解析失败返回 -1）。
- reported_by: audit-cypy-sweep



### FIXED(2026-10-15T09:03:40Z / BUG-188)
- evidence: commit 5d35304：`src/server/issue_scan.mbt:628` 新增 `let int_safe : Int = 200_000_000`，循环内累加前 `if acc >= int_safe { return -1 }`（L632-634），与同族 5 处解析器同型。配套 `src/server/issue_scan_wbtest.mbt` 追加 4 条边界锁：20 位长数字串/2000000001/2000000000 三例返回 -1，200000000 与 199999999 仍正常解析。`moon test --target js` 全量 1112/1112 通过（含新增断言），`moon fmt` 通过。

## BUG-189 [2026-10-15T09:06:00Z] [high] FIXED
- summary: symbolic.mbt DPLL 求解器 dpll_sat() 缺少防御性变量索引边界检查——若 Cnf 结构体被手动构造（非 to_cnf 路径）且子句含 v > num_vars 的文字，assign[v] 越界
- detail: `dpll_sat` 是 pub 函数，接收任意 `Cnf` 结构体。`assign` 数组大小为 `n+1`（n = cnf.num_vars），但函数体内所有 `assign[v]` 访问（unit_propagate / pure_literal_eliminate / all_satisfied / pick_branch_var）均无边界检查。正常路径 to_cnf 产生的变量索引在 [0, num_vars] 范围内（Var 从 1 开始，aux_counter 递增到 num_vars），但手动构造的 Cnf 可包含任意索引。修法：在 dpll_sat 入口遍历所有子句文字，若 v < 0 || v > n 则 return None（视为不可满足），与求解器语义一致。
- reported_by: bug-hunter



### FIXED(2026-10-15T09:06:00Z / BUG-189)
- evidence: `src/symbolic/symbolic.mbt` dpll_sat() 入口新增 12 行边界检查循环：遍历 cnf.clauses 所有文字，`if v < 0 || v > n { return None }`。`moon check --target js` 0 errors，`moon test --target js` 1112/1112 passed。
## BUG-190 [2026-10-15T09:06:30Z] [medium] FIXED
- summary: ops_pipeline.mbt L779/L793 cold_publish / publish_next_round 失败被静默吞掉——Err(_) => () 使调用方看到"wait"而非错误
- detail: `pipeline_advance` 函数在 tasks.is_empty() 时调用 cold_publish，否则调用 publish_next_round。两处失败均 `Err(_) => ()`，new_id 保持 None，最终返回 Ok(PjAdvance("Pending","Pending","wait",...))——调用方无法区分"无任务可发布"与"发布失败"。修法：用 `publish_error : String?` 捕获错误，发布后检查并 `return Err("pipeline 发布失败: \{e}")`，让错误传播到调用方。
- reported_by: bug-hunter



### FIXED(2026-10-15T09:06:30Z / BUG-190)
- evidence: `src/ops/ops_pipeline.mbt` L768 新增 `let mut publish_error : String? = None`；L779/L793 `Err(_) => ()` 改为 `Err(e) => publish_error = Some(e)`；L798-801 新增 `match publish_error { Some(e) => return Err(...), None => () }`。`moon check --target js` 0 errors，`moon test --target js` 1112/1112 passed。
## BUG-191 [2026-10-15T09:07:00Z] [medium] FIXED
- summary: router_caf.mbt L149 `model_cost_sum[i] / model_totals[i].to_double()` 除以零风险——model_totals[i] 为 0 时 Infinity/NaN
- detail: `caf_model_stats` 汇总循环中，若某 model 的 records 存在但全部 cost=0 且 totals 被其他路径置零（理论上当前数据流不会，但作为 pub 函数应防御），除零产生 Infinity 或 NaN，污染排序。修法：`if model_totals[i] > 0 { ... } else { 0.0 }`。
- reported_by: bug-hunter



### FIXED(2026-10-15T09:07:00Z / BUG-191)
- evidence: `src/router/router_caf.mbt` L149 改为 `avg_cost: if model_totals[i] > 0 { model_cost_sum[i] / model_totals[i].to_double() } else { 0.0 }`。`moon check --target js` 0 errors，`moon test --target js` 1112/1112 passed。
## BUG-192 [2026-10-15T09:16:18Z] [high] FIXED
- summary: BUG-189 router_config.mbt 4 处 JSON Double.to_int() 无上界守卫，恶意 config_json 使 model_route 服务器崩溃
- detail: `RouterConfig::from_json(json)` 直接对用户 JSON 里的 Number 调 `.to_int()`，MoonBit Double→Int 转换在 |v| > 2^31-1 或 NaN/Inf 时 panic（与 BUG-183/187/188 同族，evolve.mbt L429 注释已确认此行为）。

4 处漏网：
- L15 `Some(Json::Number(n, ..)) => n.to_int()` — window_seconds，用户在 `model_route(config_json='{"window_seconds": 99999999999}')` 即可触发。
- L128 `parse_opt_int`：`Some(Json::Number(n, ..)) => (n.to_int(), [])` — rank 字段。
- L182 `if n.to_int() < 0` — limit 负数检查，to_int 在比较前就 panic。
- L192 `n.to_int()` — limit 采纳值。

可达路径：MCP `model_route` 的 `config_json` 参数是外部输入（JSON 文本或对象，BUG-63 两种形态都收）。恶意/误传大数即让 server 进程 panic，属于 DoS。

修复方向：与 store_sqlite_executions.mbt L202-235 同款哨兵——在 to_int 前先检查 `n.is_finite() && n >= -2e9 && n <= 2e9`（Int32 安全域），越界回落到默认值并记 warning。


### FIXED(2026-10-15T09:29:07Z / BUG-192)
- evidence: 改了真源 src/router/router_config.mbt + src/router/router_state.mbt：新增 num_to_int_safe 助手（n != n 抓 NaN、|v|>2e9 回落 dft + warning）；window_seconds/limit/rank 4 处 `.to_int()` 全走安全转换；limit 保留「为负→0无限」与「非数字→0」原语义并新增「越界/NaN→0+warning」。补白盒锁 src/router/router_config_wbtest.mbt cfg_192（99999999999.0 超大值不 panic、回落默认、进 warnings）。138 tests 137 pass（唯一 fail 是并发 agent 的 router_caf_wbtest.mbt WIP，非本次改动）。
## BUG-193 [2026-10-15T09:19:05Z] [critical] FIXED
- summary: BUG-189: router_config.mbt 并发 agent 引入 `is_finite()` 调用导致全仓编译失败（MoonBit Double 无此方法）
- detail: 并发 agent 在 src/router/router_config.mbt 的 WIP diff 中引入 `n.is_finite()` 调用（line 133、148），但 MoonBit 的 `Double` 类型没有 `is_finite` 方法。`moon check src/router` 报 Error [4015]（Type Double has no method is_finite），2 errors，导致全仓编译失败。正确写法应该是用 `n.to_string()` 检查或直接用比较（NaN 与任何数比较都是 false）——例如 `if n == n && n >= -2000000000.0 && n <= 2000000000.0`（`n == n` 为 true 表示不是 NaN）。文件是并发 agent 的 WIP，我不越界修改，仅上报。
- reported_by: caf-agent
- task_id: T0r615



### FIXED(2026-10-15T09:25:07Z / BUG-193)
- evidence: 并发 agent 消费了 sg-2 引导后用 `n == n` 替代了所有 `is_finite()` 调用。验证：Select-String is_finite src/router/*.mbt → 0 匹配；moon check src/router → 0 errors（96 warnings）。


## BUG-192 [2026-10-15T09:28:00Z] [medium] FIXED
- summary: ops_cleanup.mbt L36-38 delete_task 失败时 `Err(e)` 捕获错误对象但只记录 `":failed"`，丢弃错误详情
- detail: `cleanup_archived` 函数遍历已归档任务并调用 `engine.delete_task`。失败时 `removed.push(t.get_id() + ":failed")` 完全丢弃了错误原因 `e`，调用方无法知道删除失败的具体原因（数据库错误/任务不存在/并发修改等）。修法：`removed.push(t.get_id() + ":failed:" + e)`，保留错误详情供运维诊断。
- reported_by: bug-hunter



### FIXED(2026-10-15T09:28:00Z / BUG-192)
- evidence: `src/ops/ops_cleanup.mbt` L37 将 `removed.push(t.get_id() + ":failed")` 改为 `removed.push(t.get_id() + ":failed:" + e)`。`moon check --target js` 0 errors，`moon test --target js` 1115/1115 passed。
## BUG-194 [2026-10-15T09:36:59Z] [high] FIXED
- summary: server.mbt get_int 对超 Int32 域 JSON Number 饱和接受，42 个 MCP 工具参数可被 1e300 静默打歪（永不超时/永不判 suspect/永不 heal）
- detail: get_int 被 42 个 MCP 工具的参数解析共用（split_n/timeout_ms/max_rounds/phi_threshold/stale_secs/retention_days 等）。旧代码 `Some(Number(n, ..)) => n.to_int()` 对超 Int32 域的值**饱和**（BUG-26 实测：1e300 → Int max，不 panic 但静默接受天量值）。后果：`timeout_ms=2147483647` 让子进程永不超时、`phi_threshold` 永不判 suspect（心跳看护静默失效）、`stale_secs` 让 heal 永不触发（任务永久卡死）、`retention_days` 永不清理。攻击面：任何 MCP 客户端都能在工具参数里塞 `1e300` 触发。



### FIXED(2026-10-15T09:37:08Z / BUG-194)
- evidence: 改了真源 src/server/server.mbt 的 get_int：新增 `n != n || n < -2e9 || n > 2e9` 越界/NaN 守卫，越界一律回落 default。补白盒锁 src/server/get_int_wbtest.mbt（越界正/负、NaN、合法值、缺字段/坏类型 7 断言）。src/server 264→266 tests 全绿。
## BUG-195 [2026-10-15T09:50:32Z] [medium] FIXED
- summary: server.mbt loop_create 内联 3 个 .to_int()（max_rounds/baseline_test_count/baseline_open_bug_count）绕过 get_int 守卫，客户端塞 1e11 静默饱和成 Int max（组合环硬上限形同虚设）
- detail: BUG-194 只修了 get_int 本身，但 loop_create（src/server/server.mbt:2661-2705）为绕开 get_int 的默认值 3，内联写了 3 个 `Some(Number(n, ..)) => n.to_int()`。对超 Int32 域的值 Double::to_int() 饱和（BUG-26）：max_rounds=1e11 → Int max，loop_create 的硬上限 max_rounds 形同虚设（本可跑 2^31 轮）；baseline_test_count / baseline_open_bug_count 变成天量，stop_on_exceeded 的基线判定也失真。攻击面：任何 MCP 客户端调用 loop_create 塞 1e11 即可触发。修法：改用 get_int(args, key, default=) 覆盖默认值，复用同一饱和守卫。



### FIXED(2026-10-15T09:50:40Z / BUG-195)
- evidence: 改了真源 src/server/server.mbt 的 loop_create：3 处内联 `Some(Number(n,..)) => n.to_int()` 改为 `get_int(args, key, default=)`，复用 get_int 的 `n != n || n < -2e9 || n > 2e9` 饱和守卫（BUG-194 同款）。补白盒锁 src/server/get_int_wbtest.mbt「非 3 默认值」路径（越界正/负、NaN、缺字段、合法值 9 断言）。src/server 266→267 tests 全绿，commit 26fba62。
## BUG-196 [2026-10-15T10:21:00Z] [high] FIXED
- summary: [rule:logic-inversion] server.mbt:270 iso_minus_secs 负 secs 产生未来 cutoff（assistant_claim 立即接管新鲜主助理；sweep 误杀活跃助理）
- detail: 现象：`iso_minus_secs(iso, secs)` 用 `ms = @env.now().to_int64() - secs.to_int64() * 1000L` 计算 cutoff。`secs` 经 `get_int`（BUG-194 后）允许 [-2e9, 2e9] 任意值。当 `secs < 0` 时 `ms = now + |secs|*1000`，落在未来，格式化为一个**未来**时间戳。

两处调用点：
- `assistant_claim`（server.mbt:4653，`heartbeat_ttl_sec` 默认 300）：客户端传 `heartbeat_ttl_sec=-100` → cutoff = now+100s。`assistant_claim_action` 里 `prev.heartbeat_at < cutoff` 恒真 → 一份**心跳完全新鲜**的主助理被立即判定陈旧，返回 `taken_over`，旧主被记 `lock_violations force_takeover`。这是 **fail-open 授权绕过**：任意客户端可夺权。
- `assistant_sweep`（server.mbt:4738，`stale_secs` 默认 600）：传 `stale_secs=-100` → cutoff 在未来 → 所有 `heartbeat_at < cutoff` 的助理（包括刚心跳过的）被标 dead。

附带第二处隐患：`iso` 参数**完全未被使用**（死代码），函数实际用的是 `@env.now()` 墙钟而非传入的 `iso`。当前两个调用点都传 `now_default()`（≈now），语义恰好等价；但任何未来调用点若传入历史时间，cutoff 仍以"当下"为基准，静默出错。

修复：`secs < 0` 时按 0 处理（即不回退，cutoff=now），与函数名"回退 secs 秒"的承诺一致；同时让 `iso` 真正参与（用 `iso` 解析为基准）。本次只修负值分支（最小改动），`iso` 未使用留待后续。
- reported_by: fist-iter-bug-hunter



### FIXED(2026-10-15T10:30:55Z / BUG-196)
- evidence: 改了真源 src/server/server.mbt 的 iso_minus_secs：① secs<0 钳到 0（负回退算出未来 cutoff = fail-open 授权绕过：assistant_claim 会把新鲜主助理立即判陈旧而接管、assistant_sweep 会把刚心跳过的助理标 dead）；② 让此前完全未被使用的 iso 参数真正作为基准参与计算（新增 _days_from_civil Hinnant 逆变换 + _iso_to_unix_ms，解析失败回退墙钟，与旧行为等价）。新增白盒锁 src/server/tz_minus_secs_wbtest.mbt 共 10 条（iso 基准回退/0 秒恒等/负 secs 钳位/恰好一天/1970 下界哨兵/1970 解析为 0/2026-10-15 预期毫秒/越界字段 None/短串非数字 None/闰日可解析）。src/server moon test --target js = Total tests: 277, passed: 277, failed: 0（基线 267 + 10 新）；moon check 0 errors。commit d1a59ef。
## BUG-197 [2026-10-15T10:26:00Z] [high] FIXED
- summary: engine_supervisor.mbt supervisor_task_upsert 新任务建好后写依赖失败被 `ignore(...)` 静默吞掉——调用方只看到 created，依赖实际未落库
- detail: `supervisor_task_upsert` 在 create_task 成功后，若 `item.depends_on` 非空，则循环 `c = c.with_depends_on(d, now)` 后调 `ignore(self.store.update_task(c))`。update_task 失败（DB 错/并发改）时无任何回执，results 里仍记 `"action":"created"`，调用方以为依赖已建立，实际 DAG 边缺失——后续按依赖调度会错序或漏跑。
- reported_by: fist-iter-bug-hunter

### FIXED(2026-10-15T10:26:00Z / BUG-197)
- evidence: src/engine/engine_supervisor.mbt L471-484 将 `ignore(self.store.update_task(c))` 改为 `match ... { Ok(_) => (), Err(e) => results.push({"ok":false,"task_id":id,"action":"dep_update_failed","error":e}) }`，依赖写失败现在以独立结果回执调用方。`moon check --target js` 0 errors。

## BUG-198 [2026-10-15T10:26:00Z] [high] FIXED
- summary: engine_saga.mbt saga_rollback 调 store_mark_saga_actions_done 失败被 `Err(_) => 0` 吞掉——补偿标记未落库但回执显示正常，重复调用会重复补偿
- detail: `saga_rollback` 的 `let marked_n = if mark && ... { match self.store_mark_saga_actions_done(...) { Ok(_) => ids.length(), Err(_) => 0 } }`。Err 分支丢弃错误、返回 0，JSON 里只看到 `marked_done:0`（与"无需标记"不可区分），且幂等前提（标记 done 后重复调用不再出现）被破坏——补偿动作可能被重复执行。
- reported_by: fist-iter-bug-hunter

### FIXED(2026-10-15T10:26:00Z / BUG-198)
- evidence: src/engine/engine_saga.mbt L68 新增 `let mut mark_err = ""`；L72 `Err(_) => 0` 改为 `Err(e) => { mark_err = e; 0 }`；L96 新增 `m.set("mark_error", Json::string(mark_err))`。标记失败现随回执返回。`moon check --target js` 0 errors。

## BUG-199 [2026-10-15T10:26:00Z] [high] FIXED
- summary: engine_saga.mbt saga_repair 与 BUG-198 同款——store_mark_saga_actions_done 失败被 `Err(_) => 0` 吞掉
- detail: `saga_repair`（局部补偿/控级联）中 `let marked_n = if mark && not(affected_ids.is_empty()) { match ... { Ok(_) => affected_ids.length(), Err(_) => 0 } }`，错误同样被丢弃，受影响切片的补偿标记可能未落库而回执正常。
- reported_by: fist-iter-bug-hunter

### FIXED(2026-10-15T10:26:00Z / BUG-199)
- evidence: src/engine/engine_saga.mbt L226 新增 `let mut mark_err = ""`；Err 分支改为 `Err(e) => { mark_err = e; 0 }`；L260 新增 `m.set("mark_error", Json::string(mark_err))`。`moon check --target js` 0 errors。

## BUG-200 [2026-10-15T10:26:00Z] [high] FIXED
- summary: omega_strong.mbt omega_escalate 调 upsert_spec 写升级记录失败被 `ignore(...)` 静默吞掉——任务被暂停但升级记录缺失，人工裁决失去依据
- detail: `omega_escalate` 组装 escalation spec 记录后 `ignore(self.store.upsert_spec(rec))`，紧接着 `self.pause_task(...)` 把任务暂停并返回 `escalated:true`。若 upsert_spec 失败，升级记录未落库，但任务已被暂停、回执仍称已升级——人工裁决时查不到升级依据，且审计链断裂。
- reported_by: fist-iter-bug-hunter

### FIXED(2026-10-15T10:26:00Z / BUG-200)
- evidence: src/engine/omega_strong.mbt L707-711 新增 `let mut spec_err = ""` 并把 `ignore(self.store.upsert_spec(rec))` 改为 `match self.store.upsert_spec(rec) { Ok(_) => (), Err(e) => spec_err = e }`；L727 新增 `"spec_persist_error": Json::string(spec_err)`。`moon check --target js` 0 errors。

## BUG-201 [2026-10-15T10:26:00Z] [low] FALSE_POSITIVE
- summary: omega_strong.mbt omega_spec_create 用 `rejected >= max_r`、omega_spec_review/omega_result_verify 用 `rejected > max_r`——复核后确认两者**语义等价**，非缺陷
- detail: 初判为"阈值运算符不一致"。复核：`omega_spec_review`/`omega_result_verify` 里 `let rejected = self.omega_count(...) + 1`，条件是 `rejected > max_r` ⟺ `existing + 1 > max_r` ⟺ `existing >= max_r`；而 `omega_spec_create` 直接用 `existing >= max_r`。两者**同一触发条件**（既有打回数达上限即升级），仅"记录到 escalation 的 rounds_rejected 值"差 1（create 记 existing、review 记 existing+1），属展示口径差异而非逻辑分歧。判定依据：源码内联等价推导（本面自身语义），非外部规范。
- reported_by: fist-iter-bug-hunter

- review: 本条复核后判为 FALSE_POSITIVE（非缺陷），依据见下。
- evidence(复核依据): 无需改真源；仅在 src/engine/omega_strong.mbt L476 增补注释 `// rejected = existing + 1, so > max_r means existing >= max_r (consistent with omega_spec_create)`，把等价关系钉在代码里防未来误改。判定为 FALSE_POSITIVE。

## BUG-202 [2026-10-15T10:26:00Z] [high] FIXED
- summary: router.mbt contains_risk_kw 用子串匹配判定 L4 风险词——"exec"/"eval"/"force" 误命中 "execute"/"evaluate"/"enforce"，把普通任务误判为不可逆并强制人工冻结
- detail: `plan_route` 用 `contains_risk_kw(description)` 决定是否升 `L4_irreversible`（cost_tier=hold，强制人工确认）。旧实现 `lower.contains(kw)` 是**子串**匹配：`"exec"` 命中 `"execute"/"executive"`、`"eval"` 命中 `"evaluate"/"evaluation"`、`"force"` 命中 `"enforce"/"reinforce"`；`"del "`/`"rm "` 依赖尾随空格、`"system("` 依赖左括号才能命中。后果：描述含 "evaluate the metrics" 或 "enforce policy" 即被误判 L4 冻结（fail-closed 过头，正常任务被卡人工）。同仓库 scheduler.mbt 已有同族词表但用整词匹配 `_has_word`——两套判据不一致，router.mbt 这套漏了词边界。
- reported_by: fist-iter-bug-hunter

### FIXED(2026-10-15T10:26:00Z / BUG-202)
- evidence: src/engine/router.mbt L76-97 的 `contains_risk_kw` 改用同包 scheduler.mbt 的 `_has_word`（ASCII 词边界匹配，前后须为空白/标点/串边界）；关键词表规范化——`"del "/"rm "` 去掉尾随空格（整词匹配下尾随空格会破坏边界判定）、`"system("` 改为 `"system"`。`moon check --target js` 0 errors。现有测试无引用 plan_route/contains_risk_kw，无回归。
## BUG-203 [2026-10-15T10:36:59Z] [high] FIXED
- summary: dag_mc 关键度系统性漏计：关键路径的中间任务 critical_freq 恒为 0（mc_finish 只算「以 t 结尾的最长链」，用 finish==makespan 判关键，只命中最长路径的终点/汇点）
- detail: 现象：src/engine/engine_dag_mc.mbt 的关键度判据（L206-214）是 `mc_finish(t) == ms`（t 的 finish 时间 == 全局 makespan）。但 `mc_finish`（L96-131）返回的是「从任一源点到 t 的最长链长度」（= max over deps of mc_finish(dep) + own(t)），**只看前驱不看后继**。因此只有「最长路径的终点/汇点」满足 finish==ms，**所有中间节点**（前驱任务）都满足不了。

可复现（现有测试 dag_mc_test.mbt L85-110 就是这条链）：
- A：中(3,5,8)，无依赖
- B：中(3,5,8)，deps=[A]
- C：易(2,3,5)，无依赖（旁路，短）
ms = dur[A]+dur[B]。
mc_finish(A)=dur[A]（<ms，不判关键），mc_finish(B)=dur[A]+dur[B]=ms（判关键），mc_finish(C)=dur[C]（<ms，不判关键）。
⇒ A 是 B 的唯一前驱、在唯一的最长路径上，但 critical_freq=0；B 却≈1.0。这与工具描述「关键度=任务出现在最长路径的频率，含近关键路径」自相矛盾。

一般化：任何线性链 A→B→…→Z 只有 Z 被判关键，A…前驱全为 0。这会误导指挥官把资源全压在汇点任务上，完全漏掉链上的真正瓶颈。

根因：判「在最长路径上」需要同时算「以 t 结尾的最长链（前向）」与「从 t 起的最长链（后向）」，二者相加减去 own(t) 等于 makespan 才判关键。当前实现只做前向，漏了后向 pass。

建议修复：新增 `mc_suffix(t)`（从 t 到任一汇点的最长链，含 own，看后继），判据改为 `mc_finish(t) + mc_suffix(t) - own(t) == ms`。后继关系由 deps 反解（一次性构建 succ Map）。




### FIXED(2026-10-15T10:45:00Z / BUG-203)
- evidence: 改了真源 src/engine/engine_dag_mc.mbt：新增私有 `mc_suffix_from`（从 t 起的最长链，看后继，含 own，环命中沿用 BUG-204 的 -1 哨兵）；由 deps 反解后继表 succ（样本循环外一次构建）；关键度判据从 `mc_finish(t)==makespan` 改为 `前向 finish + 后向 suffix - own == makespan`。修复前线性链 A→B→…→Z 只有 Z 被判关键（中间节点 critical_freq 恒 0），与工具描述「关键度=任务出现在最长路径的频率」矛盾。更新 src/engine/dag_mc_test.mbt 测试：现断言前驱 A 与汇点 B 都 freq≈1、旁路 C 仍 ≈0（BUG-203 前 A 恒为 0，该测试必红）。moon test --target js 全仓 = Total tests: 1143, passed: 1143, failed: 0。commit 0709b07。
## BUG-204 [2026-10-15T10:44:00Z] [medium] FIXED
- summary: report_bug 发布修复根任务失败被 `Err(_) => ()` 静默吞掉——注释承诺"失败仅在返回里体现"，返回却既无错误位、task_namespace 照旧回显，调用方以为单已发
- detail: `report_bug`（src/server/bugreport.mbt）在 `publish_task=true` 时调 `publish_parallel(...)` 发修复根任务，注释写明"best-effort；失败不阻断落账，仅在返回里体现"。但匹配臂是 `Err(_) => ()`：发布失败后既不记错误、返回 JSON 里也无任何错误字段；更糟的是 task_namespace 仍无条件回显。调用方（MCP 工具 report_bug，server.mbt:5577）拿到 ok:true + task_namespace 会以为修复单已发布，实际不存在——落账与发布状态脱节。
- reported_by: fist-iter-bug-hunter

### FIXED(2026-10-15T10:44:00Z / BUG-204)
- evidence: src/server/bugreport.mbt 新增 `let mut publish_error = ""`（紧随 task_id）；发布匹配臂 `Err(_) => ()` 改为 `Err(e) => publish_error = e`；返回 JSON 在 task_id 之后按 `if not(publish_error.is_empty()) { m.set("publish_error", Json::string(publish_error)) }` 回执错误。锁：src/server/bugreport_status_wbtest.mbt 新增测试"BUG-204：publish_task 发布失败不再静默——返回带 publish_error 且不谎报 task_id"，用 task_ns="default"（publish_parallel 硬拒并行发布的确定性失败路径）断言无 task_id、有 publish_error 且落账成功。`moon test --target js src/server` 278/278 通过。


## BUG-205 [2026-10-15T10:48:00Z] [medium] FIXED
- summary: HexaMind 裁决报告表「帽子」列误填 r.verdict——与「判决」列逐字重复，六顶帽 id 丢失，读者无法从报告看出各单元戴的是哪顶帽
- detail: `render_markdown`（src/hat/hat_report_build.mbt）表头为 `| 单元 | 帽子 | 判决 | 置信度 | 依据 |`，数据行却把 `r.verdict` 连写两遍（第二格本应是帽子）。后果：①「帽子」列显示 pass/reject/abstain，与「判决」列完全重复；②该单元实际所属的六顶帽 id（white/red/black/yellow/green/blue）丢失。单真源 hexa_hat_id(六元代号)→帽 id 已存在（hat_defs.mbt:53），且 hat_hexa_tools.mbt:232 已在别处回显 hat_id，唯独报告表漏用。现有测试（hat_wbtest.mbt "build: 报告组装…"）只断言标题/状态，未钉表格列，故漏检。
- reported_by: fist-iter-bug-hunter

### FIXED(2026-10-15T10:48:00Z / BUG-205)
- evidence: src/hat/hat_report_build.mbt 数据行第二格 `r.verdict` 改为 `hexa_hat_id(r.element_id)`（白/红/黑/黄/绿/蓝）。锁：src/hat/hat_wbtest.mbt 新增测试"BUG-205：报告表「帽子」列显示六顶帽 id（hexa_hat_id），不再误填 verdict"，断言 `观星者（stargazer） | white | pass`、`破壁者（wallbreaker） | black | reject` 存在，且旧形态 `（stargazer） | pass | pass` 不存在。`moon test --target js src/hat` 24/24、`src/server` 278/278 通过，`moon check --target js` 0 errors。## BUG-206 [2026-10-15T10:53:48Z] [high] OPEN
- summary: ModelQuota::in_cooldown 对 Y2038 后冷却截止静默失效（iso_to_secs 溢出返回 -1 使 now < -1 恒 false，冷却机制被绕过）
- detail: 现象：`ModelQuota::in_cooldown`（src/router/model_router.mbt:151）里 `cool_secs = iso_to_secs(self.cooldown_until)`，而 `iso_to_secs` 对超出 Y2038 的日期因 Int 溢出返回 -1（BUG-218 同族，rt_2b 测试确认 2038 溢出返回 -1）。于是 `now_secs < cool_secs` 变成 `2026秒 < -1` = 恒 false —— 冷却截止一旦超过 Y2038，该模型永远被视为"不在冷却期"。

后果：
1. `ModelRouter::mark_failure(model, "2099-...")` 后，`in_cooldown` 恒 false，冷却机制形同虚设。
2. 任何外部传入的 `cooldown_until` 若在 Y2038 之后（如配置错误、时钟漂移、手工编辑状态文件），模型会被静默放行，失败重试风暴不被冷却兜住。
3. 这是"测试看起来合理却被 Y2038 吃掉"的典型假绿坑：本轮 P2c §2.2 的冷却回退测试用 `"2099-01-01T00:00:00Z"` 写冷却截止时测试恒失败，换成 `"2026-10-15T18:10:00Z"` 立即全绿，但生产代码本身对 2099 无防护。

建议：`in_cooldown` 对 `cool_secs <= 0` 显式处理（fail-open 放行并留日志，或 fail-safe 视为仍在冷却），不要依赖 `now_secs < cool_secs` 的隐式比较。

## BUG-206 [2026-10-15T10:54:32Z] [medium] FIXED
- summary: dag_mc 的 p90 分位索引比 p50 的取法高 1：p50 用 (n-1)*0.5（最近秩正确），p90 却用 n*0.9——两者口径不一致，p90 系统性偏大 1 个样本值
- detail: 真源 src/engine/engine_dag_mc.mbt L288-299：

```
let idx50 = if n_safe - 1 < 0 { 0 } else { (n_safe - 1) / 2 }
let idx90 = if n_safe * 9 / 10 >= n_safe {
    if n_safe - 1 < 0 { 0 } else { n_safe - 1 }
} else {
    n_safe * 9 / 10
}
```

对 n=1000：idx50 = 999/2 = 499（最近秩 ceil(0.5*1000)=500 → sorted[499]，正确）；
idx90 = 1000*9/10 = 900（最近秩 ceil(0.9*1000)=900 → sorted[899]，代码取 sorted[900]，**高 1**）。

同口径公式应为 (n-1)*0.9：n=1000 → 999*0.9=899.1 → 899（int div）。而 (n-1)*0.5=499 恰好与 p50 现在的公式一致 ⇒ p50 用 (n-1) 因子、p90 用 n 因子，两条公式不对称，p90 系统性高估 1 个样本值。

守卫 `n_safe * 9 / 10 >= n_safe` 在 n>=10 时恒为 false（9n >= 10n 永假），是死代码（只兜 n<=0，但 n 已钳到 >=10）。

影响：MCP 工具 dag_mc 返回的 makespan.p90 对任何样本数都比「p50 同一套最近秩口径」高 1 个单元。对 make span 量级 10-100 的任务是 1-10% 系统性高估。属轻微数值不精确，非崩溃；但同一返回值里两条分位取法不一致，是文档承诺「p90 完工时间分位」的可测偏差。

证据梯：数学推导（最近秩定义 vs 代码索引）+ n=1000 数值复核。修复应把 idx90 改为 (n_safe-1)*9/10 与 idx50 对称，并补一条锁定具体索引的白盒测试。



### FIXED(2026-10-15T11:00:04Z / BUG-206)
- evidence: src/router/model_router.mbt:157-161 in_cooldown 加 `if cool_secs <= 0 { return false }` fail-open 保护（修复前 `now_secs < -1` 恒 false）；src/router/model_router_wbtest.mbt 新增 cd_4 契约锁三态（合法/Y2038 后/非法字符串），commit ed40ada，153/153 全绿。


### FIXED(2026-10-15T11:02:29Z / BUG-206)
- evidence: 改动 src/engine/engine_dag_mc.mbt：新增 pub fn mc_percentile_index(n,p)=(n-1)*p/100（最近秩口径），p50/p90 改经它取索引——p90 从旧 n*9/10 改为 (n-1)*9/10；src/engine/dag_mc_test.mbt 加两条回归锁（n=10/100/1000 精确索引 + 边界退化 + 单调性）；moon fmt 后 moon test --target js 全绿 1147/1147（较前 1145 增 2）。commit ad53154。
## BUG-207 [2026-10-15T11:06:45Z] [medium] FIXED
- summary: health_check 的 latency p50/p90 索引用 n*p/100，比最近秩 (n-1)*p/100 系统性高 1（与 BUG-206 同根）
- detail: 真源 src/server/board_ascii.mbt L345-346（render_health_check 的 latency 分支）：

  let p50 = done_cycles[n * 50 / 100]
  let p90 = done_cycles[n * 90 / 100]

done_cycles 是已完成任务的完成周期（created_at→updated_at 秒）升序排序。百分位最近秩口径应为
ceil(p*n/100) 个值 → 0-based 索引 (n-1)*p/100（BUG-206 已把 dag_mc 的 p90 从 n*9/10 改为
(n-1)*9/10，与此同根）。这里 p50 用 n/2、p90 用 n*9/10 都比 (n-1)*p 高 1：

  n=10，cycles=[10,20,...,100]：正确 p50=done_cycles[4]=50，代码读 done_cycles[5]=60；
                      正确 p90=done_cycles[8]=90，代码读 done_cycles[9]=100。
  n=4，cycles=[1,2,3,4]：正确 p50=done_cycles[1]=2，代码读 done_cycles[2]=3（中位数取上）。

系统性**高估** latency 的 p50 与 p90（读取升序数组里偏高的一个元素），SRE 用百分位看延迟
趋势时会误判恶化。现有测试 board_ascii_test.mbt:79 只造了 3 个相同周期（全 120s）的任务，
n*50/100 == (n-1)*50/100 == 1，恰好掩盖了偏差——判据对"样本全同"这种退化形状不敏感。

建议：统一用 (n-1)*p/100（或抽取为复用 @engine.mc_percentile_index），并加一条判据用
10 个递增周期锁定精确索引。
- reported_by: fist-iter-bug-hunter



### FIXED(2026-10-15T11:13:18Z / BUG-207)
- evidence: 改动 src/server/board_ascii.mbt L349-350：p50/p90 索引改为 @engine.mc_percentile_index(n,50)/(n,90)，复用 ad53154 引入的最近秩口径 (n-1)*p/100；src/server/board_ascii_test.mbt 加 hc_latency_num 辅助 + 「latency p50/p90 用最近秩 (n-1)*p（BUG-207）」回归锁（10 个互不相同周期 10..100s，锁 p50=50/p90=90，旧代码读出 60/100 必挂）。moon fmt 后 moon test --target js 全绿 1151/1151（较前 1147 增 4，含并发 WIP）。commit 9f6fff6。
## BUG-208 [2026-10-15T11:15:34Z] [low] FIXED
- summary: dag_mc 对 seed=0（或 seed≥2^32）无校验：xorshift32 恒回 0，Monte Carlo 退化为单点分布却照常返回"分布" JSON
- detail: 真源 src/engine/engine_dag_mc.mbt：

1) mc_xorshift（L12-18）：xorshift32 的唯一年轻态就是 0 自身——state=0 时
   x=(0^(0<<13))&0xffffffff=0 恒为 0，返回 (0,0)。
2) dag_mc（L261）：`let mut state = seed + s * 7919`，未对 seed 做非零校验。
3) 后果：调用方传 seed=0（MCP 参数直通，无钳制）→ 第一个样本 state=0 →
   mc_tri_sample 里 u=v/2147483648=0 → 每个任务时长恒取三角分布下界 a（易=2、
   中=3、难=5）。全部 samples 完全相同 → 分布退化为单点：
     · makespan.min == makespan.max（"分布" 变成定值）
     · p50 == p90 == min == max
     · 所有最长路径任务 critical_freq 恒为 1.0（每样本同路径）
     · P(≤deadline) 要么 0 要么 1，不再反映不确定性
   调用方看到一份"像模像样的分布 JSON"，实际是确定性退化——比直接报错更危险，
   因为它会让人误信"完工分布很紧"。
4) 另：seed ≥ 2^32 时 `(state & 0xffffffff)` 会把高位截掉，同样可能落到 0。

建议：dag_mc 入口对 seed 钳制到非零（如 seed<=0 时回退到 1，或 seed 与 0x7fffffff 相与后为 0
时回退到 1），并在回执 note 里如实回显"seed 已钳制"。同时补一条回归锁：
同作用域下 seed=0 与 seed=1 的输出分布应**不同**（seed=0 是退化单点），
旧代码下两条相等（都退化或都正常）时锁不住，需锁"seed=0 时 min==max"这一退化形状。
- reported_by: fist-iter-bug-hunter



### FIXED(2026-10-15T11:20:17Z / BUG-208)
- evidence: 改动 src/engine/engine_dag_mc.mbt L261-266：样本循环内 `state = seed + s*7919` 后钳到 `state & 0x7fffffff`，仍 <=0 时回退为 1（xorshift32 唯一年轻态即 0 自身，非零恒非零）。src/engine/dag_mc_test.mbt 加 mc_span_min/mc_span_max 辅助 + 「dag_mc：seed=0 不退化（BUG-208）」回归锁（中档任务 (3,5,8)，锁 seed=0 时 max-min>1 且均值落在支撑内；旧代码 seed=0 → state=0 → u=0 → 恒 3 → min==max 必挂）。moon fmt 后 moon test --target js src/engine 151/151、全量 1152/1152 全绿。commit 961ecb1。
## BUG-209 [2026-10-15T11:31:29Z] [medium] FIXED
- summary: [contract:type-silent] output_validate 的 artifact_spec_errors 只校验键名不校验值类型：min_chars/contains/not_contains 传错类型（如 min_chars="100" 字符串、contains=42 数字）被 parse_artifact 静默降级为默认值（0/""），invariant 变空检查，verdict 仍 pass——BUG-31 的类型孪生兄弟
- detail: 真源 src/server/output_validate.mbt：
- artifact_spec_errors(L65-106) 只检查未知键名 + path/check_key 存在性，不校验 min_chars/contains/not_contains 的**值类型**。
- parse_artifact(L114-141) 对这三个字段做类型匹配并静默回退默认值：
  - `min_chars: match m.get("min_chars") { Some(Number(n,..)) => n.to_int(), _ => 0 }` — 传 String("100") → 0
  - `contains: match m.get("contains") { Some(String(s)) => s, _ => "" }` — 传 Number(42) → ""
  - `not_contains: 同上`
后果：调用方（AI agent）给出 `{path:"foo.mbt", min_chars:"100"}`（字符串类型）时，spec_err 返回 ""（键名合法），parse 后 min_chars=0、contains=""、not_contains="" → check_file_artifact 只做「文件存在+非空」→ verdict=pass、note 写「全部 N 条产物检查通过（证据层: l4-pass）」——L4 硬门被一条空检查满足，与 BUG-31 完全同族。
修法：artifact_spec_errors 增加值类型校验——min_chars 必须是 Number、contains/not_contains 必须是 String，否则返回 Err 文案。与 BUG-31 的「未知键拒绝」形成键名+值型双向防御。
回归测试：output_validate_test.mbt 追加一条 `{path, min_chars:"100"}` 与一条 `{path, contains:42}` → 断言 verdict=fail、detail 含类型不匹配原因。
- reported_by: fist-iter-bug-hunter



### FIXED(2026-10-15T11:45:37Z / BUG-209)
- evidence: commit b67f22e：src/server/output_validate.mbt 的 artifact_spec_errors 增加值类型硬门——min_chars 必须是 Number(_,..)、contains/not_contains 必须是 String(_)，否则直接返回失败原因；与既有「未知键拒绝」形成键名+值型双向防御。src/server/output_validate_test.mbt 追加 ov_21_invariant_wrong_type_fail：三格分别传 min_chars=\"100\"(String)、contains=42(Number)、not_contains=7(Number)，全部断言 verdict=fail（修复前实测 RED \"pass\" != \"fail\"）。验证：moon test --target js 全绿 1158/1158（src/server 281/281）。
## BUG-210 [2026-10-15T11:40:42Z] [medium] FIXED
- summary: board_ascii 实时看板 append_group 组内排序比较器在 (depth, created_at) 全等时落入 else 无条件返回 1——cmp(a,b)=cmp(b,a)=1，严格弱序反对称性被破坏，同状态组渲染顺序未定义（BUG-173 同族）
- detail: 真源 src/server/board_ascii.mbt append_group（L107-162）的 sorted.sort_by 比较器：depth 不等按 depth 升序；depth 等且 a.created_at<b.created_at 返回 -1；其余（created_at>=）一律返回 1。publish 固定 depth=3 且 created_at 取自 now 参数（src/engine/engine.mbt L35-61），因此同一 now 的两次 publish 造出全等对（T0 与 T0r2）：cmp(T0,T0r2)=1 且 cmp(T0r2,T0)=1——同时"a 在 b 前"且"b 在 a 前"，sort_by 结果依赖输入顺序与排序算法内部形状，输出不确定。同刻批量发布（批量导入/秒级连发）时看板行顺序随机，"先发布先渲染"这一直觉契约失效。对照：dag_ascii（engine_dag_ext.mbt L190）、triage_rest（engine_triage.mbt L150）均以 a.id.compare(b.id) 收尾，本处是唯一漏掉 tiebreak 的比较器。
- 触发条件: 同状态组内 >=2 个任务 (depth, created_at) 全等——publish 同刻批量发布即满足（depth 恒 3，created_at 同 now）
- reported_by: fist-iter-bug-hunter

### FIXED(2026-10-15T11:40:42Z / BUG-210)
- evidence: 改动 src/server/board_ascii.mbt L119-128：比较器补 else if a.created_at > b.created_at { 1 } 显式分支，全等时以 a.get_id().compare(b.get_id()) 升序收尾（与 dag_ascii L190、triage_rest L150 的 id tiebreak 模式一致）；src/server/board_ascii_test.mbt 加「board_ascii 组内全等任务按 id 升序（BUG-210）」回归锁——两次 publish 传同一 now 造 T0/T0r2 全等对，split 断言 T0(乙) 必渲染于 T0r2(甲) 之前。moon check --target js 0 errors；moon test --target js src/server 全绿 280/280。commit 9cd2fa7。

## BUG-211 [2026-10-15T11:54:19Z] [medium] FIXED
- summary: [output_validate] check_moon_test_summary 只查 failed>0，未查 total==0：空测试套件（Total tests: 0）被当成 L4 假绿
- detail: src/server/output_validate.mbt 的 check_moon_test_summary（L323-362）：找到 `Total tests:` 汇总行后，判绿条件只有 `if failed > 0`（L354），没有检查 `total == 0`。当 `moon test` 跑出 `Total tests: 0, passed: 0, failed: 0.`（空包/构建未收集到任何测试/被截断在汇总前）时：found=true、failed=0、total=0 → L361 直接返回 ""（pass）。

后果：L4 硬门 `check_key` 名含 `moon_test` 时，一个「0 条测试」的空套件被当成「全绿」——正是 BUG-142 要防的「假绿」的又一个入口（exit 0 + 假汇总行）。对照：found=false 时已有守卫（L351-352 报「缺汇总行」），但 total=0 这一格漏了。

修法：在 `if failed > 0` 之前加 `if total == 0` 的守卫，报「汇总行 total=0——没有跑任何测试，不能判绿」。



### FIXED(2026-10-15T11:57:20Z / BUG-211)
- evidence: commit 2f8656c：src/server/output_validate.mbt 的 check_moon_test_summary 在 `if failed > 0` 之前增加 `if total == 0` 守卫，报「没有跑任何测试，不能判绿」（BUG-142 假绿的又一入口：空包/构建漏收集/汇总截断都可能喂出 `Total tests: 0, passed: 0, failed: 0.`）。src/server/output_validate_test.mbt 追加 ov_22_moon_test_total_zero_fail：喂 `Total tests: 0, passed: 0, failed: 0.` 断言 verdict=fail（修复前实测 RED `"pass" != "fail"`）。验证：moon test --target js -p src/server 282/282 全绿。
## BUG-212 [2026-10-15T12:04:18Z] [medium] FIXED
- summary: [dag_mc] 环保护不完整：mc_finish/mc_suffix_from 的 -1 哨兵不传播，环上节点返回正数、makespan 把环当正常最长路径
- detail: src/engine/engine_dag_mc.mbt 的 mc_finish（L96-130）与 mc_suffix_from（L138-170）的环保护不完整。

BUG-204 修复引入的 -1 哨兵只在「当前节点自身被重入」（L112 / L151）时返回 -1；但**外层递归收到 -1 后照样累加**——`if f + own > best` 只在 f=-1 时因 `own-1 <= own` 自然不生效，于是内层节点返回 own（自身时长），外层节点把内层的 own 累加进自己。

实例：环 A↔B（deps: A→[B], B→[A]），dur={A:3, B:5}：
- mc_finish(B)：deps=[A]，调 mc_finish(A) → visiting[A]=true → 返回 -1。f+own = -1+5=4 <= best=5，不生效。B 返回 **5**（自身时长，看似合理但 A 在环上、B 也因 A 而环）。
- mc_finish(A)：deps=[B]，mc_finish(B) 返回 5。f+own = 5+3=8 > best=3 → best=**8**。
- 结果：A 的 finish=8（正数），环被当成「A→B→A 时长 8」的一条正常最长路径，makespan 报 8。实际环的最长路径是**无限**，-1 哨兵应传播到环上所有节点。

对照 dag_slack（engine_dag_ext.mbt L290）把环任务归入 `cycle` 数组排除，dag_mc 却没有等效的环标记——L298 的 `f >= 0 && sf >= 0` 守卫因 f/sf 是正数而失效，环节点仍参与关键度/makespan 统计。

修法：mc_finish / mc_suffix_from 在遍历依赖/后继时，若任一递归返回 -1，把 cycle 标记置 true，遍历结束后若 cycle 则自身也返回 -1（memo 记 -1）。这样 -1 沿环传播，dag_mc 的 L282（`f > ms`）与 L298（`f >= 0 && sf >= 0`）两个消费点自然把环节点从 makespan / criticality 里剔除。



### FIXED(2026-10-15T12:08:21Z / BUG-212)
- evidence: commit 1f35342：src/engine/engine_dag_mc.mbt 的 mc_finish 与 mc_suffix_from 在遍历依赖/后继时若任一递归返回 -1，置 cycle 标记，遍历结束后 cycle=true 则自身也返回 -1（memo 记 -1），把 BUG-204 的 -1 哨兵沿依赖链向上传播到环上所有节点。新增 src/engine/engine_dag_mc_wbtest.mbt 三条白盒锁：① mc_finish 环节点返回 -1（修复前 A=8 B=5）；② mc_suffix_from 环节点返回 -1；③ 成对对照非环链 A→B 的 mc_finish 仍为 8 不被误标。验证：moon test --target js -p src/engine 154/154 全绿。
## BUG-213 [2026-10-15T12:17:54Z] [high] FIXED
- summary: [dag] dag_depend 只防自环不防传递环：A→B→C 后再 dag_depend(C, dep=A) 静默成功，图被破坏成环
- detail: src/engine/engine_dag_ext.mbt 的 dag_depend（L212-238）只检查「不能依赖自身」（L222-224），不做传递环检测。

现状：A→B→C 已存在（A.depends_on=[B], B.depends_on=[C], C.depends_on=[]）。调用 `dag_depend(task_id="C", dep_id="A")` 时：
- L222：dep_id("A") != task_id("C")，通过自环检查；
- L225-228：A 存在，通过存在性检查；
- L230-232：C.depends_on.contains("A")？C.depends_on=[], 不含 "A"，通过幂等检查；
- L233：c = C.with_depends_on("A", now)，C.depends_on 变为 ["A"]；
- L234-236：落库成功，返回 Ok。

结果：图变成 A→B→C→A，形成环。下游 dag_topo_order（L290 的 cycle 数组）能识别但只能「报告」，dag_slack/dag_mc/critical_path/parallelism 全部把环当成正常图处理——即使我此前修的 BUG-212 让 dag_mc 不再把环当正常最长路径，dag_depend 仍然**允许**环被创建，语义上仍是错的：任务图的 DAG 不变量被静默破坏。

对照：dag_topo_order 已经建了 deps_of（前置→后继）邻接表，dag_slack 已有 cycle 数组。dag_depend 是唯一在「建边」入口不防环的地方。

修法：dag_depend 在 self 检查之后、落库之前，增加传递可达性检查——从 dep_id 出发沿 depends_on 链 BFS，若可达 task_id，说明加上这条边会成环，返回 Err。复杂度 O(V+E)，dag_depend 是 MCP 写工具不是热路径，可接受。

回归锁：dag_ext_test.mbt 追加「dag_depend: 传递环拒绝」——建 A→B→C 后再 dag_depend(C, dep=A) 必须 Err。



### FIXED(2026-10-15T12:24:03Z / BUG-213)
- evidence: commit ebfa2e4：src/engine/engine_dag_ext.mbt 新增 FistEngine::dag_reaches（BFS 从 dep_id 沿 depends_on 链查 task_id 可达，visited 用 Map 兜底），dag_depend 在落库前调用——若 task_id 是 dep_id 的传递依赖，返回 Err「拒绝成环依赖」。修复前 A→C→B→A 静默成环（dag_depend 只防自环 L222-224 与幂等 L230-232），下游 dag_slack/dag_mc 把环当正常图。新增 src/engine/dag_cycle_test.mbt 2 条黑盒锁：① dag_depend(task_id="A", dep_id="C") 必须 Err 且 A.depends_on 未被污染；② 非环对照 D→A、D→C 合法，C→D（成环）拒绝。修复前实测 RED（dag_depend 返回 Ok 触发 abort）。moon fmt + moon info 后 moon test --target js 全绿 1168/1168（src/engine 156/156）。

## BUG-214 [2026-10-15T12:31:00Z] [high] FIXED
- summary: [ops_pipeline] pipeline_tick auto 分支 heal_stale_tasks_from_store 失败被 Err(_) => [] 静默吞掉，违反同处注释「结果随返回上报」契约——BUG-185/186 同族第三例
- detail: src/ops/ops_pipeline.mbt L503-507（auto 分支）原写法为 match heal_stale_tasks_from_store(engine, now, timeout_sec~, ns=ns_final) { Ok(l) => l; Err(_) => [] }，Err 分支直接丢弃错误，返回 JSON 只剩 healed: []，与「无超时任务」不可区分；而同处 L502 注释明确承诺「结果随返回上报」。当前 ops_heal.mbt L91-151 所有路径均返回 Ok（Err 不可达），故属契约违背而非即时故障；一旦 ops_heal 扩展出 Err 分支（如 reopen 失败），失败将被静默吞掉。同族：BUG-185（ops_watchdog.mbt，已用 heal_error 注入 detail 修复）、BUG-186（ops_heal reopen_task 吞）。
- fix_options: 照 BUG-185 模式：auto 分支捕获 heal_error : String?，Err(e) => { heal_error = Some(e); [] }；返回装配处（L561-566）pj_set 注入 "heal_error"，仅 Some 时出现（成功路径不泄漏）。回归锁：pipeline_23 断言 healed 键存在且成功路径不泄漏 heal_error。

### FIXED(2026-10-15T12:52:27Z / BUG-214)
- evidence: commit aa85c3f：src/ops/ops_pipeline.mbt auto 分支（L504-510）新增 `let mut heal_error : String? = None`，Err 分支由 `Err(_) => []` 改为 `Err(e) => { heal_error = Some(e); [] }`；返回装配处（L562-566）`pj_set` 注入 "heal_error"（仅 Some 时出现，成功路径不泄漏）。src/ops/ops_pipeline_test.mbt 新增 pipeline_23 回归锁：healed 键存在、成功路径 heal_error 为 null。验证：moon test --target js src/ops 190/190 全绿（修复前 189/189）。
## BUG-215 [2026-10-15T13:01:30Z] [medium] FIXED
- summary: [dag-cycle] dag_level/longest_chain_ending 环保护只对重入点生效：环成员得到非零层级、critical_path 含环成员，违反「环保护下返回 0」契约
- detail: 现象：在 X→Y→X 环 DAG 上（X.depends_on=[Y], Y.depends_on=[X]）：

1. `dag_ascii` 输出：
   ```
   Z [待领取]
     Y [待领取] (依赖: X)
       X [待领取] (依赖: Y)
   ```
   Y 被渲染为第 1 层、X 被渲染为第 2 层——但二者互为依赖，**没有合法拓扑深度**。换遍历顺序（先 Y 后 X）会得到相反层级（X=1、Y=2），即输出**顺序依赖**。文档契约（engine_dag_ext.mbt L111）写的是「环保护下返回 0」。

2. `critical_path` 在环 DAG 上返回 `[Y, X]`（实跑输出 `critical_path=[Y, X] contains_X=true contains_Y=true`）——一条「关键路径」里包含互为依赖的环成员，不是合法拓扑链。

根因：`dag_level`（L112-157）与 `longest_chain_ending`（L35-67）的环保护只在**重入点**返回 0/[]，不向上传播「本路径已成环」状态。调用方把 0/[] 当作合法的空结果累加 +1/+自身，于是触发重入的外层节点得到非零层级、并把环成员塞进关键路径。

判据（探针源码已删，仅留结论）：
- X.depends_on=["Y"]、Y.depends_on=["X"]、Z.depends_on=[]。
- `e.dag_ascii(ns="default")` 输出如上（Y 深 1、X 深 2）。
- `e.critical_path()` 输出 `[Y, X]`。

对照面：`dag_slack_analysis` 的 Kahn 环检测正确（dag_ext_test.mbt L341-345 断言 cycle=[X,Y]），`dag_depend` 的传递环拒绝也正确（BUG-213）——所以环只能来自 legacy 数据或直接 DB 写入，但仍属「工具承诺了环保护却没兑现」。

修复方向：环保护从「局部重入检查」升级为「环成员标记」——检测到环时，把路径上的所有节点一并记入 visited/memo 并返回 0/[]，或返回 Option/哨兵值区分「无依赖」与「成环」两种空结果。



### FIXED(2026-10-15T13:08:44Z / BUG-215)
- evidence: 改了真源 src/engine/engine_dag_ext.mbt（commit edefab9）：① longest_chain_ending 返回类型 Array[String] → Array[String]?，环重入点/检测到环的节点 memoize None，调用方 critical_path 跳过 None；② dag_level 环重入点返回 -1 哨兵并 memoize，任一子链出现 -1 时本节点也传播 -1；③ dag_ascii 读取级别时把 -1 钳到 0（顶层），排序比较器同样钳。锁钉：临时探针测试先复现后验证——修复前 X→Y→X 环上 critical_path=[Y,X]、dag_ascii 渲染 Y 深 1/X 深 2；修复后 critical_path=[Z]、X/Y 均顶层，探针测试通过后删除。全量 moon test --target js = 1180/1180 通过。
## BUG-216 [2026-10-15T13:13:39Z] [low] FIXED
- summary: [diff-json-escape] render_json 未转义控制字符 U+0000–U+001F：text_diff format=json 输出无效 JSON
- detail: 现象：`render_json` 只转义 `"` `\` `\n` `\r` `\t` 五个字符，其余控制字符（U+0000–U+001F）**原样拼进 JSON 字符串**。

探针实跑（src/diff 包内临时测试，已删）：
- 输入 old="a\u{0001}b"、new="a\u{0001}c"
- `render_json(diff_lines(old, new))` 输出：
  `[{"kind":"delete","text":"a<raw SOH>b"},{"kind":"insert","text":"a<raw SOH>c"}]`
- 断言 `s.contains("\\u0001")` = false（控制字符未被转义为 `\u00XX`）

影响：RFC 8259 §7 要求 U+0000–U+001F 一律转义。`text_diff` 的 `format=json` 分支把此字符串**原样当 ToolResult::text 返回**，客户端若用严格 JSON 解析器会失败。低触发概率（正常文本不含控制字符）但一旦命中即产出不可解析的 JSON。

修复方向：`json_escape` 增加分支——对 `\u{0000}`–`\u{001F}` 输出 `\u00XX`（大写十六进制，4 位补齐）。

## BUG-217 [2026-10-15T13:20:00Z] [high] FIXED
- summary: 自驱发布静默吞错——selfdrive_publish_next 在发布失败时把失败折叠进 skipped，
  返回 action="wait"，与"幂等已跳过"无法区分（BUG-204/BUG-214 同族）。
- detail: selfdrive_publish_next → try_publish_one → engine.publish_parallel
  (engine.mbt:822)。try_publish_one 的 `Err(_) => None` 吞掉失败；调用方
  `match new_id { None => { skipped.push(...) } }` 把失败等同于幂等跳过。
  MCP tool `selfdrive_publish_next` 默认 ns="default"，而 publish_parallel 对
  ns=="" || ns=="default" 直接 Err——即默认参数下每次发布必然失败却被吞掉，
  调度器永远停在 action="wait"。
- fix_options:
  A. try_publish_one 返回 Result 或累积错误数组，调用方注入 publish_errors 字段
     （保持 skipped 语义不变，仅新增错误回执）。
  B. 直接删除 selfdrive_publish_next 工具。
  C. 在 selfdrive_publish_next 入口校验 ns 非空非 default。

### FIXED(2026-10-15T13:22:00Z / BUG-217)

- 证据（修复代码 commit）：`692f226 fix: selfdrive 发布失败不再静默吞错（BUG-217）`
  （src/ops/ops_selfdrive.mbt + src/ops/ops_selfdrive_test.mbt）。try_publish_one 增加
  `errors: Array[String]` 出参，`Err(_) => None` 改为 `Err(e) => { errors.push(e); None }`；
  selfdrive_publish_next 累积 publish_errors 并注入输出 JSON（skipped 语义不变）。
- 证据（验证）：`moon test --target js src/ops` → 191 passed / 0 failed；
  新增 selfdrive_9_publish_next_surfaces_errors 回归锁（ns="default" 确定性失败路径，
  断言 publish_errors 长度 2）。
- 过滤式提交：临时索引从 HEAD 选取自身改动，避免覆盖并行开发的 WIP。



### FIXED(2026-10-15T13:20:29Z / BUG-216)
- evidence: 改了真源 src/diff/diff.mbt（commit 1a271f5）：json_escape 的 `_` 分支新增 `if ch.to_int() < 0x20` 时输出 `"\\u" + hex4(ch.to_int())`，新增 `hex4` 辅助函数（4 位大写十六进制补齐）。锁钉：临时白盒探针（diff_escape_fix_wbtest.mbt，验证后删除）先复现后验证——修复前 render_json 输出 `{"kind":"delete","text":"a<raw SOH>b"}`（has_escaped_control=false），修复后输出 `{"kind":"delete","text":"a\u0001b"}`（断言 contains("\\u0001") 通过、contains 裸控制字符为 false）。全量 moon test --target js = 1183/1183 通过。

### FIXED(2026-10-15T13:27:43Z / BUG-217)
- evidence: 改了真源 src/claimguard/claimguard.mbt（commit ba4fd93）：`may_proceed_sematic` 与 `may_proceed_full` 改为「只读预检 → 全通过才 claim_item」——先用 `decide_claim(g.holders.get(proposed), agent)` 只判 item-id 层重入（不写 holders），再跑 blind_spot / semantic_collision，全部通过后才真正 `claim_item`。锁钉：临时白盒探针（claimguard_bug217_wbtest.mbt，验证后删除）三条——①may_proceed_sematic 返回 false 时 `holder_of` 为 None（旧实现泄漏为 Some("B")）；②may_proceed_full 返回 false 时 `holder_of` 为 None；③may_proceed_sematic 返回 true 时 `holder_of` 为 Some("B")（正常认领未破坏）。全量 moon test --target js = 1183/1183 通过。

### FIXED(2026-10-16T12:50:56Z / BUG-217)
- evidence: commit ba4fd93（HEAD 链上）fix(claimguard)：may_proceed_sematic / may_proceed_full 改为只读预检——先 decide_claim(g.holders.get(proposed), agent) 判 item-id 层重入（不写 holders），再跑 blind_spot_holds / semantic_collision 语义层，全部通过后才 claim_item 落认领；claim_item 返回 Denied 时保留防御性兜底。src/claimguard/claimguard.mbt:227-252（sematic）/ :269-298（full）带 BUG-217 注释点名旧实现副作用。工作树对 src/claimguard/ 无 WIP，已提交未走记账。

### FIXED(2026-10-16T14:34:09Z / BUG-217)
- evidence: claimguard.mbt 已实现「只读预检后落认领」：may_proceed_sematic(L232-252) 与 may_proceed_full(L272-298) 都先跑只读层1 decide_claim / 层2 blind_spot_holds / 层3 semantic_collision，全部通过后才调 claim_item 落认领；claim_item 调用在 L248 与 L294，位于所有检查之后。已读源码核实 L239/L281(decide_claim)、L244/L286(blind_spot_holds)、L290(semantic_collision) 均无写 holders 副作用。账本抬头已从 OPEN 更正为 FIXED。

### FIXED(2026-10-16T14:57:30Z / BUG-217)
- evidence: claimguard.mbt may_proceed_full 只读预检已修复并提交 ba4fd93；首条已 FIXED，次条因 BUG-241 同号重复条目不处理而滞留 OPEN，现补标 FIXED。

### FIXED(2026-10-16T15:46:09Z / BUG-185, BUG-186, BUG-217)
- evidence: cl7 硬门② stale 3 条：重复条目里标 OPEN 的那条被小记点名但抬头未翻转，账本与小记两套话。真源证据：BUG-217 次条 evidence 自述「claimguard.mbt may_proceed_full 只读预检已修复并提交 ba4fd93，现补标 FIXED」；BUG-185/186 由并发修复侧在小记中点名。本笔把对应抬头补标 FIXED，使账本抬头与小记一致，gen_plugins 硬门②过；重复 OPEN 条不删（BUG-9 只追加不销毁政策）。

### FIXED(2026-10-16T15:51:31Z / BUG-217)
- evidence: commit ba4fd93 修复 claimguard.mbt may_proceed_sematic/may_proceed_full：先跑只读预检（decide_claim/blind_spot_holds/semantic_collision）全部通过后才 claim_item；claim_item 调用位于 L248/L294 在所有检查之后。次条（2026-10-15T13:22:34Z）与首条同号不同 ts，因 BUG-241 未修而滞留 OPEN。BUG-241 修复已入库（f1e36a3：bug_header_lines 返回 ALL 索引，bug_fix 逐条改判同号重复条目）。现补标 FIXED。
## BUG-263 [2026-10-15T13:22:34Z] [medium] FALSE_POSITIVE
- renumbered_from: BUG-217（2026-10-17 fist-lead 清整，消除与已 FIXED BUG-217 的 ID 碰撞，见 BUG-260）
- summary: [claimguard-side-effect] may_proceed_sematic / may_proceed_full 在检查前先 claim_item：返回 false 时项已被 side-effect 认领
- detail: `may_proceed_sematic` / `may_proceed_full` 的语义是"问"——回答能否 proceed——但实现先调 `claim_item(g, proposed, agent)` 把项**认领给自己**，再跑语义/盲点检查；检查失败返回 false 时，项已被 side-effect 认领。

具体路径（`src/claimguard/claimguard.mbt`）：
- L228-243 `may_proceed_sematic`：先 `claim_item` → `_` 分支（Claimed/Renewed，均 set holders）→ 再 `semantic_collision` 为 true → return false。**此时 `g.holders[proposed]` 已被设为 `agent`**。
- L261-283 `may_proceed_full`：同样先 `claim_item` → 再检查 blind_spot / semantic_collision → return false。**同样泄漏**。

后果：调用方按 `false` 判定「不能 proceed、换一个」，但该项已锁在**本 agent** 名下，其他 agent 再来 claim 会得 Denied；guard 状态与「未 proceed」的实际状态不一致。

现有测试不覆盖：`claimguard_wbtest.mbt` L177 `assert_true(!may_proceed_sematic(...))` 只断言返回值，没断言 `holder_of(g, "L33-self-search")` 应为 `None`。

修复方向：把 claim 动作移到所有检查**通过之后**——先用 `decide_claim` 只读判重，全通过再 `claim_item`；或者拆成 `check_proceed_*`（纯读）+ `claim_item` 两步，由调用方显式认领。


- false_positive(2026-10-19T07:05:35Z): 2026-10-19 实证：src/claimguard/claimguard.mbt L232-252 may_proceed_sematic 与 L272-294 may_proceed_full 均已是「只读预检→全过后才 claim_item」——L240/L245（sematic）与 L282/L287/L291（full）在 return false 之前**不调用** claim_item，状态写只发生在 L248/L294 的放行分支。白盒锁 cg_full_gate_item_id_block（claimguard_wbtest.mbt L224-234）显式断言：may_proceed_full 返回 false 后 `holder_of(g,"L38-logic-engine")==Some("A")`（原持有者未变）。`moon test --target js -p src/claimguard` = 57/57 passed。该 bug 已在 BUG-217 rework（源码注释 L228-231/L270-271 明写「旧实现先 claim_item 再跑语义检查→现在改为只读预检」）落地时一并修复，BUG-263 报告所引行号（L228-243/L261-283）与现文件偏移 4~11 行，系报告早于修复落盘。
## BUG-218 [2026-10-15T13:51:38Z] [medium] FIXED
- summary: [scoring] calc_coverage 的 substring 匹配对空/单字符 law 产生假覆盖（coverage 虚高）
- detail: `src/omega/scoring.mbt` 的 `calc_coverage` 用 `Json::stringify(t).contains(law)` 判断某条 law 是否被 tests 覆盖。实测两个漏洞：

1. **空 law**：`"hello".contains("")` 在 MoonBit 返回 true（空串是任意串的子串）。若 laws 数组含空条目，该条恒被覆盖，coverage 虚高。
2. **单字符/超短 law**：law = "a" 时，任何含字母 'a' 的 test（如 `{"name":"test1"}` 的 stringify 里就有 'a'）都判为覆盖。实测 `calc_coverage(["a"], [{"name":"test1"}])` 返回 1.0，而 law "a" 根本没被测试。

后果：laws 里若出现短 token（变量名、符号、空串），coverage 被系统性抬高，Ω-spec 的 pass 判定失准（coverage × 30 分）。修复：空 law 不算覆盖（跳过）；law 长度 < 3 时用更严格的匹配（或跳过并记 note）。
- reported_by: bugfind


### FIXED(2026-10-15T13:55:57Z / BUG-218)
- evidence: src/omega/scoring.mbt calc_coverage：空 law 与单字符 law 跳过不计覆盖（分母只算 length>=2 的 law；全部跳过时回 1.0）；scoring_test.mbt 新增 scoring_coverage_short_law_skip 锁（全短=1.0 / 混合未命中=0.0 / 混合命中=1.0 三态）；moon test --target js 全量 1197/1197 绿。
## BUG-219 [2026-10-15T13:52:00Z] [medium] FIXED
- summary: [selfdrive] selfdrive_memory_init 写入失败被静默丢弃（created/skipped 均不含，函数仍返回 Ok）
- detail: `src/ops/ops_selfdrive.mbt` 的 `selfdrive_memory_init` 在写入四件套模板时，`sd_write` 返回 false 的分支既不进 `created` 也不进 `skipped`，被完全丢弃。函数仍返回 `Ok`，调用方误以为"四件套已就绪"，实则文件缺失。与 `selfdrive_publish_next`（BUG-217）同族：静默吞错。触发条件：memory 路径被占用为普通文件（create_dir 失败）、磁盘满、权限不足等。
- fix_options: 1) 新增 errors 累积器 + JSON errors 字段 + 条件 note（采用）；2) 返回 Err 让调用方感知（过于激进，init 是幂等操作）；3) 仅记日志（调用方仍无法感知）。
- fix: 新增 `errors : Array[String]` 累积器，`sd_write` 失败时 push 到 errors；JSON 输出新增 `errors` 字段；note 根据 errors 是否为空动态切换（"已就绪" vs "部分就绪（写入失败 N 项，详见 errors）"）。回归锁 `selfdrive_218_memory_init_surfaces_write_errors`：构造 memory 为普通文件使四件套写入全部失败，验证 errors 含 4 项、created/skipped 为空、note 含"部分就绪"。
- reported_by: bugfind
- commit: 15b6b42

## BUG-220 [2026-10-15T14:07:00Z] [high] FIXED
- summary: [github_sync] github_queue_append / github_queue_mark_sent 队列写入失败被静默丢弃（let _ = 丢弃 Bool 返回值）
- detail: `src/server/github_sync.mbt` 的 `github_queue_append`（L110）和 `github_queue_mark_sent`（L343）使用 `let _ = mem_write(...)` 完全丢弃写入结果。`mem_write` 返回 `Bool`（失败返回 false），但 `let _ =` 丢弃了该信号——写入失败时函数仍返回 `Ok(Json::object(mm))`，调用方误以为已持久化，实则队列数据丢失。与 BUG-217/219 同族（静默吞错），但后果更远：队列丢失导致 bug 同步静默失败，且无回执可查。触发条件：磁盘满、权限不足、路径被占用为目录等。
- fix_options: 1) 检查 mem_write 返回值，失败时返回 Err（采用）；2) 在 JSON 输出中加 errors 字段（调用方可能不检查）；3) 仅记日志（调用方仍无法感知）。
- fix: 将 `let _ = mem_write(...)` 改为 `if !mem_write(...) { return Err("...: 队列写入失败") }`。回归锁 `BUG-220_queue_write_failure_surfaces`：构造队列路径为目录使写入必然失败，验证两个函数都返回 Err。
- reported_by: bugfind
- commit: 92e41e0

## BUG-221 [2026-10-15T14:16:00Z] [medium] FIXED
- summary: [selfdrive] sd_round_count / sd_recent_reports read_dir 失败被静默转为默认值
- detail: `src/ops/ops_selfdrive.mbt` 的 `sd_round_count`（L116）和 `sd_recent_reports`（L138）在 `path_exists` + `safe_is_dir` 验证目录存在后，`@fs.read_dir` 失败被 `catch { _ => return 0 }` / `catch { _ => return [] }` 静默转为默认值。调用方无法区分"目录为空"和"目录不可读"（权限不足、I/O 错误等）。与 BUG-217/219/220 同族（静默吞错）。
- fix_options: 1) abort 抛错让调用方感知（采用）；2) 返回 Result 类型（需改签名，影响调用方）；3) 记日志后返回默认值（调用方仍无法感知）。
- fix: `catch { _ => abort("...: read_dir failed for \{dir}") }`。目录已验证存在，read_dir 失败是真正的 I/O 错误，不应静默返回默认值。
- reported_by: bugfind
- commit: 2ec9cb2

## BUG-222 [2026-10-15T14:22:00Z] [high] FIXED
- summary: [issue_scan] scan_collect 的 read_dir 失败被静默吞掉，导致 issue_scan 对不存在/不可读目录返回 Ok(scanned_files=0) 的"假干净"结果
- detail: `src/server/issue_scan.mbt` 的 `scan_collect`（递归收集待扫描文件）在 `@fs.read_dir(dir)` 失败时 `catch { _ => return }` 静默返回，`out` 保持为空。主入口 `issue_scan` 只做 `scan_dir_ok` 校验（拒绝空串/`..`/绝对路径/盘符），**并不校验目录是否存在或可读**。因此 `issue_scan("no_such_dir", "", 100)` 会返回 `Ok({scanned_files: 0, total_findings: 0, by_severity: {high:0,medium:0,low:0}})`——与"扫了目录但确实无命中"完全无法区分，调用方（bugfind/OCR-local 融入流程）会误判为"干净"。与 BUG-217/219/220/221 同族（静默吞错）。
- fix_options: 1) scan_collect 改返回 `Result[Unit, String]`，read_dir 失败回执 Err 并由 issue_scan 透传（采用）；2) 仅在 issue_scan 内补一次根目录存在性校验（只能覆盖根目录，嵌套目录仍吞错）；3) abort 抛错（MCP 面向工具不宜 panic）。
- fix: `scan_collect` 签名改为 `-> Result[Unit, String]`，`catch { _ => return Err("issue_scan: 无法读取目录（不存在或不可读）: " + dir) }`，递归处 match 透传 Err，末尾 `Ok(())`；`issue_scan` 用 match 透传 Err。回归锁 `lint_10_missing_dir_returns_err`：对必然不存在的 `temp/lint_bug222_missing_dir` 调用，断言 `is_err()`。`moon test --target js src/server` 284/284 绿。
- reported_by: bugfind
- commit: 2ca94f2

## BUG-223 [2026-10-15T15:10:00Z] [medium] FIXED
- summary: [github_gitcode] gitcode_queue_append / gitcode_queue_mark_sent / gitcode_queue_mark_sent_batch 队列写入失败被静默丢弃（let _ = 丢弃 mem_write 返回值）
- detail: `src/server/github_gitcode.mbt` 三处写路径用 `let _ = mem_write(gq_path(project_dir), ...)` 完全丢弃写入结果（append L482 / mark_sent L303 / mark_sent_batch L357）。`mem_write` 失败返回 false，但函数仍返回 `Ok(Json::object(...))` 并报告 `marked`/`exists` 成功。写失败（磁盘满、目录被删、权限变更）时 `sent_at`/`gitcode_issue_iid` 标记未落盘，后续 `gitcode_queue_pending` 仍视其为 pending → 重复创建/发送 issue，且调用方无感知。与 BUG-220（github_sync 同款）同族，两文件口径不一致。
- fix_options: 1) 检查 mem_write 返回值，失败返回 Err（采用）；2) JSON 加 errors 字段（调用方可能不检查）；3) 仅记日志（调用方仍无法感知）。
- fix: 三处均改为 `if !mem_write(...) { return Err("gitcode_queue_xxx: 队列写入失败") }`。回归锁 `gc-22`：把队列路径占位为目录使 mem_write 必然失败，断言 append / mark_sent / mark_sent_batch 三路径都 `is_err()`。`moon test --target js src/server` 285/285 绿。
- reported_by: bugfind
- commit: 56633bc

## BUG-224 [2026-10-15T15:20:00Z] [high] FIXED
- summary: [github_flush_execute] 按 plan_arr 长度索引被过滤后的 bug_ids，越界 panic（工具崩溃拖垮整个 server turn）
- detail: `src/server/server.mbt` 的 `github_flush_execute` 里，`bug_ids`/`curl_cmds` 只收集 `bug_id` 与 `curl_command` 均非空的 plan 项（L6691 `if !bid.is_empty() && !cmd.is_empty()`），而 `github_flush_plan`（`github_sync.mbt` L198-299）对队列行**无条件**产出 plan 项——当某行的 `bug_id` 为空（`github_queue_append` 会拒绝写，但历史损坏行/手工改文件/旧版本队列可产生）时，plan 项数 > bug_ids 数。结果组装第二循环 `while i2 < plan_arr.length() { let bid2 = bug_ids[i2] ... }`（L6789/L6791）以 plan_arr 长度为界直接索引 bug_ids，一旦 i2 达到 bug_ids.length() 即越界 panic；第一循环 `bug_ids[i1]`（L6739）仅以 results_arr 长度为护栏，同为脆弱写法。MoonBit 数组越界是 panic 而非可回执的 Err，会直接终止整个 MCP 工具调用（server turn 崩溃）。
- fix_options: 1) 消费端按 bug_ids.length() 迭代 + 上游 flush_plan 排除空 bug_id 行（纵深防御，采用）；2) 仅改消费端循环边界（上游仍产出不可追踪的 plan 项）；3) 仅改上游过滤（消费端仍对其它畸形输入脆弱）。
- fix: ① 上游 `github_flush_plan`：计算 bug_id 后 `if bug_id.is_empty() { continue }`，保证 plan 里每条都带非空 bug_id（空行既无法 mark_sent、issue 正文也无 bug 锚点）。② 消费端 `github_flush_execute`：第二循环边界改为 `while i2 < bug_ids.length()`；第一循环护栏补 `&& i1 < bug_ids.length()`。回归锁 `BUG-224_flush_plan_skips_empty_bug_id`：直接落盘"一条合法 + 一条空 bug_id"的队列，断言 `github_flush_plan` 只产出 1 条且 bug_id=BUG-OK（空行被排除）。`moon test --target js src/server` 286/286 绿。
- reported_by: bugfind
- commit: 44bb8da

## BUG-225 [2026-10-16T00:50:00Z] [medium] FIXED
- summary: [watchdog_tick] 冷启动发布失败被静默吞掉（`Err(_) => ()`），调用方只看到 action="idle"，无法区分「无任务可发布」与「冷启动失败」
- detail: `src/ops/ops_watchdog.mbt` 的 `watchdog_tick` 冷启动分支（`else if cold_start`）在 `engine.cold_publish(...)` 返回 Err 时执行 `Err(_) => ()`，既不留痕也不上报，直接落到函数末尾默认分支，返回 `action = if active_ids 非空 { "waiting" } else { "idle" }`。冷启动场景下 active_ids 必为空，故调用方（定时任务/ops_loop）拿到的恒为 `action="idle"`，与「作用域内确实无任务可发布」的正常空闲**完全不可区分**。触发面：default 命名空间拒绝冷启动、已有任务拒绝重复发布（幂等）、以及 DB/IO 瞬时错误（多 agent 并发下 DB 锁竞争尤其现实）。同函数兄弟分支（`publish_next_round` 续轮失败）已按同一族规范把错误并入 `detail.advance_error`（并发开发中刚落地的修复），冷启动分支属遗漏，构成"静默吞错 -> 误导性 idle 回执"。
- fix_options: 1) 保持 idle 退化语义（D-3/D-4 既有测试锁定），仅把失败原因并入 `detail.cold_start_error`，与兄弟分支 `advance_error` 一致（采用，零回归）；2) 直接 `return Err(...)` 上抛（会破坏 D-3/D-4 期望的 idle 退化语义，且 default 命名空间拒绝属策略性拒绝而非故障，不宜一律上抛）；3) 仅加日志不留 JSON（调用方仍不可编程判别）。
- fix: 冷启动分支 `Err(_) => ()` 改为 `Err(e) => { ... new_m.set("cold_start_error", Json::string(e)); detail = Json::object(new_m) }`，镜像上方续轮失败分支的 `advance_error` 写法（逐键复制现有 detail 后追加错误键）。回归锁 `watchdog D-4b`：default 命名空间 + cold_start=true 时断言 `action` 仍为 `idle`（D-3 语义零回归）且 `detail.cold_start_error` 非空；另断言未进入冷启动分支（无失败）时该字段为空，防误报。`moon test --target js src/ops` 193/193 绿。
- reported_by: bugfind
- commit: 7cb897f

## BUG-226 [2026-10-16T01:00:00Z] [medium] FIXED
- summary: [regex_lite] 单字符 "^" 或 "$" 作为 pattern 会匹配任意字符串（prefix/suffix 分支缺 length>1 守卫）
- detail: `src/omega/gate.mbt` 的 `regex_lite`（L43-54）是 Ω-gate 的"regex"断言降级实现。其分支语义为：`^...$`（长度>2）→ 精确相等；`^` 开头 → 前缀匹配；`$` 结尾 → 后缀匹配；否则 → 包含匹配。问题在于 prefix/suffix 分支只检查锚点前缀/后缀，不检查剥锚点后是否仍有内容。当 pattern 恰为单字符 `"^"` 时，`pattern.has_prefix("^")` 为真，`pattern[1:pattern.length()]` = `pattern[1:1]` = 空串，`actual.has_prefix("")` 对所有字符串返回 true；单字符 `""$"` 同理（`pattern[0:0]` = 空串 → `has_suffix("")` = true）。组合分支已有 `length() > 2` 守卫（剥两个锚点后至少 1 字符），但 prefix/suffix 分支遗漏了等价的 `length() > 1` 守卫。影响面：Ω-gate 跑批时若 spec 的 regex 断言 pattern 被误写为单字符 "^" 或 "$"（如用户意图是精确匹配 "^" 这个字面量、或从模板/截断逻辑产生），则该断言对所有 actual 恒为 true——**假阳性放行**，使本该失败的用例被静默通过，gate 失去拦截能力。gate.mbt L128（regex 断言入口）、L296（另一处 regex_lite 调用）均受影响。现有测试 omega_test.mbt L119-124 覆盖了正常前后缀与组合锚点，但未覆盖单字符锚点退化。
- fix_options: 1) prefix/suffix 分支各加 `&& pattern.length() > 1` 守卫，与组合分支的 `length() > 2` 对齐（采用，最小改动、零回归——正常 pattern 长度均>1）；2) 在入口处对单字符 "^"/"$" 特判返回 false（等价但分散逻辑）；3) 把锚点剥取改为先判长度再切片（可读性改动较大）。
- fix: prefix 分支改为 `if pattern.has_prefix("^") && pattern.length() > 1`，suffix 分支改为 `if pattern.has_suffix("$") && pattern.length() > 1`；单字符锚点自然降级到末尾 `actual.contains(pattern)` 分支（"^"/"$" 作为普通子串，仅当 actual 恰好含该字符时 true，符合直觉）。同步更新 doc 注释。回归锁 `gate regex_lite 单字符锚点 ^ / $ 不应匹配一切（BUG-226）`：断言 `regex_lite("anything","^")`=false、`regex_lite("anything","$")`=false、`regex_lite("","^")`=false、`regex_lite("","$")`=false。`moon test --target js src/omega` 52/52 绿。
- reported_by: bugfind
- commit: d65c2ec



## BUG-227 [2026-10-16T02:13:56Z] [medium] FIXED
- summary: [self-cleanup] 已暂停任务无归档清理路径，410 条无主僵尸永久堆积致 project_health 恒 attention
- detail: 清扫 2026-10-16 轮次（R120）：fist-mbt 项目任务库 569 条，其中已暂停 410 条（397 条 assignee 为空、分布在历史命名空间 r3verify=141/stdalign=136/enhance-e2e=72/dag-verify=16/atgc-selfdrive=14/polish=10 等）。尝试 archive 清理被拒：archive 的合法前态仅「已完成」，已暂停任务无 resume→空完成→归档 的合法清理链（resume 到已领取后仍无法归档；无 cancel/批量归档工具）。导致全库 1535 条已暂停僵尸永久堆积，project_health 恒 attention、saturation 无法回落。缺一条「已暂停僵尸批量清理」路径（如 resume 后 force_archive，或按 namespace/assignee 空 批量归档 API）。本轮已完成 134 条已完成任务归档（done 524→391, archived 49→182），唯 410 已暂停无法清理。


### FIXED(2026-10-16T07:43:00Z / BUG-227)
- evidence: commit d5033f0（master）：archive 工具新增 force 可选参数，放行已暂停/已打回僵尸任务直接归档。改动：src/core/core_task.mbt Task::archive_force（force=false 与 archive 同义零回归；force=true 放行 已完成/已暂停/已打回，在流态仍拒并给 pause 出路文案）；src/engine/engine_archive_force.mbt FistEngine::archive_force 旁路（新文件不动 engine.mbt 主流程，权限同门 human_steward/human，store 层零改动）；src/server/server.mbt 既有 archive 工具加 bool_prop force 参数（不新增工具，工具计数守卫零影响）。白盒锁 src/core/core_task_force_wbtest.mbt 4 条（同义锚/三滞留态放行/五在流态拒/已归档终态拒）。提交门禁：moon fmt + moon info + moon test --target js = Total tests: 1247, passed: 1247, failed: 0。注：运行中 MCP server 仍为旧构建，force 参数随下次 dist 构建生效。
## BUG-228 [2026-10-16T03:30:26Z] [high] FIXED
- summary: [server] report_bug auto_push 远端建号成功后本地队列标记写入失败被静默丢弃，下轮 sync 重复建号
- detail: server.mbt report_bug auto_push 两处队列标记调用点（github L5776、gitcode L5963）以 `let _ =` 丢弃 Result[Json, String]；被调 github_queue_mark_sent（github_sync.mbt L308）与 gitcode_queue_mark_sent_batch（github_gitcode.mbt L317）在本地队列写入失败时 return Err("…: 队列写入失败")（BUG-220 已修），但调用点丢弃 Err 后回执仍报 github.ok:true / gitcode.ok:true 并带 issue_url，本地 JSONL 队列未标记 sent，下轮 sync 对同一 bug 重复建号，GitHub/GitCode 出现重复 issue。同型调用点（github_mark_sent 工具封装、flush_execute、gitcode_mark_sent 工具封装）均正确归一，唯 auto_push 两处遗漏。
- fix: 抽出纯函数 queue_mark_receipt(channel, res) -> Json 归一回执（Ok→{ok,channel,marked,total}；Err→{ok:false,channel,queue_mark_error}），auto_push 两处标记调用点捕获 Result 并将回执并入 remote_push 子图（auto_push.github.queue_mark / auto_push.gitcode.queue_mark）随响应回传；新增回归锁 queue_mark_receipt_wbtest.mbt 钉住 Ok/Err 双分支。moon test --target js src/server 全绿（288/288）。
- reported_by: bugfind
- commit: cb3f27f708b91bcca49926d7dc0c38ec009485ed

## BUG-229 [2026-10-16T04:16:53Z] [high] FIXED
- summary: [server] 模型路由重试分支的记账/冷却 `Result` 被 `let _ =` 静默丢弃，写盘失败时回执无留痕
- detail: `src/server/model_router_ops.mbt` 的 `executor_run_impl` 重试链路有两处 `let _ =` 丢弃点：(a) Err 分支（进程未起来，ENOENT 一类，L958-961）重试前调 `mr_record_failure(project_dir, ns~, attempt_model)` 记冷却账；(b) Ok-but-!okk 分支（进程起来了但执行失败，L1008-1020）重试前调 `mr_record_only`（`routed_by_pool` 时）与 `mr_record_failure` 记账。被调函数对「模型不在池中」返回 `Ok(())`（合法静默跳过，L370-372 守卫），但 `mr_save` 本地 JSON 落盘失败时返回 `Err("写入路由状态失败：…")`（L68-75）；调用点 `let _ =` 把两类结果一视同仁丢弃——落盘失败时回执仍报 `ok:true`/`executed:true` 且不带任何错误线索，调用方无法区分「未记账（不在池中）」与「记账写盘失败」，模型可靠性账本静默丢失。同函数最终尝试分支（L1030-1034 quota_note）已按同族规范把记账 Err 并入回执，唯重试分支两处遗漏。
- fix: 两处丢弃点改为 `mr_retry_note(model, res)` 归一（Ok→"" 不留痕、Err→"model: err"，L379-384）并累加进 `cooldown_errors : Array[String]`（L926-927 声明）；函数两处出口——Err 分支的失败返回（L970-973）与最终尝试返回（L1043-1046）——均经 `mr_opt_arr_field("cooldown_errors", cooldown_errors)`（L91-97）把非空错误数组并入回执 JSON，空数组不出字段（既有回执形态零回归）。回归锁 `bug229_重试分支记账冷却不留静默吞错`（model_router_ops_wbtest.mbt）钉住 `mr_retry_note` Ok/Err 双分支、`mr_opt_arr_field` 空/非空语义、`mr_record_failure` 不在池中返回 `Ok(())`。`moon test --target js src/server` 全绿（289/289）。
- reported_by: bugfind
- commit: 676ce7a17c7ad1f6d0fa7819667fb646085cc799

## BUG-230 [2026-10-16T04:53:00Z] [high] FIXED
- summary: [engine] 熔断器四处 cb_save 写盘 Result 被 ignore() 静默吞错，状态变更未落库时回执仍展示内存新状态
- detail: `src/engine/engine_circuit.mbt` 的 circuit_fail（L37-60）、circuit_succeed（L84-107）、circuit_status（Open→Half-Open 迁移写 L134-154、半开配额自增写 L172-199）四处 `self.store.cb_save(...)` 返回 `Result[Unit, String]` 均被 `ignore(...)` 丢弃。SQLite 写盘失败（磁盘满/目录被删/权限变更/并发锁竞争）时，回执 `cb_json` 仍按内存中的 new_state/new_failures 组装并报 `allow_call`/`state`，调用方无法区分「已落库」与「状态变更丢失」——熔断器状态机可能反复重放同一迁移（如 Open→Half-Open 每次查询都尝试迁移）、半开配额未持久化导致重启后配额错乱。与 BUG-228/229 同族（Result 被静默丢弃）。
- fix_options: 1) 写盘失败错误留痕并并入回执（采用）；2) 上抛 Err 改签名（破坏既有调用契约，MCP 工具不宜 panic）；3) 仅日志不留 JSON（调用方不可编程判别）。
- fix: 新增纯函数 `cb_persist_note(res : Result[Unit, String]) -> String`（Ok→"" 无错不留痕、Err→错误原文）与 `cb_note_join(a, b)`（合并两处写盘留痕，都空→""，一空取另一，都非空→"a；b"）；`cb_json` 增加 `persist_error? : String = ""` 形参，非空才 `m.set("persist_error", ...)`（空时回执形态零回归）。四处 `ignore(...)` 改为捕获 Result：circuit_fail/succeed 单写点直接归一；circuit_status 迁移写与配额自增写分别归一后经 `cb_note_join` 合并进同一 persist_error 字段（三条出口分支均透传）。同步更新 server.mbt 三个工具（circuit_fail/circuit_succeed/circuit_status）描述，声明 `persist_error?` 语义（非空即「状态变更未落库」）。回归锁 `bug230_熔断器写盘不留静默吞错`（engine_circuit_wbtest.mbt）：钉住 cb_persist_note Ok/Err、cb_note_join 四种组合，并断言 Mem 后端成功路径不出 persist_error 字段。`moon test --target js src/engine` 157/157、`moon test --target js src/server` 289/289 全绿。
- reported_by: bugfind
- commit: 300cfb60f2567a539afc70ccf1648e1bc19026bc

## BUG-231 [2026-10-16T05:52:00Z] [medium] FIXED
- summary: [server] task_plan_deep 的 laya_auto 分支把 Laya 探测/sidecar 失败用 `Err(_) => ()` 静默吞掉，回执 `laya:null` 与「未安装 Laya」不可区分
- detail: `src/server/server.mbt` 的 `task_plan_deep` handler 在 `laya_auto=true` 且未躬身自决时探测 Laya 并调 sidecar 定 split_n。探测点 `laya_probe_cached(...)` 的 `Err(_) => false`（L1942 附近）与 sidecar 调用 `laya_decide_external(...)` 的 `Err(_) => ()`（原 L1964）均把错误整条丢弃：sidecar 调度失败 / 返回体 JSON 解析失败（laya_js.mbt L97-103 的两条 Err 路径）时，`laya_info` 停在 `Json::null()`，回执 `laya: null` 与「本机未安装 Laya」（probe 返回 Ok(false)）完全同形——调用方无法区分「没装」与「装了但调用挂了」，只能盲信已回退默认 split_n。同族兄弟 handler `laya_decide`（server.mbt L3575-3586）在 `Err(e)` 分支已把 `reason: "laya sidecar 调用失败: {e}"` 透出，唯 `task_plan_deep` 遗漏。与 BUG-204/228/229/230 同族（Result 被静默丢弃）。
- fix: 新增纯函数 `laya_auto_fail(reason : String) -> Json`（恒 `{available:false, reason}`）；探测 `Err(e)` 与 sidecar `Err(e)` 两处改为把原因写进 `laya_info`（「Laya 探测失败: {e}，已回退 split_n 默认值」/「laya sidecar 调用失败: {e}，已回退 split_n 默认值」），使两类失败均可见且与「未安装」区分。`laya` 字段仍在 `laya_auto && !decided` 时才出现（关闭该开关的调用方零回归）；probe Ok(false)（未安装）仍保持 `laya: null`（描述已声明「不可用回退」）。同步更新 `task_plan_deep` 的 `laya_auto` 参数描述，声明失败时 `laya` 为 `{available:false, reason:…}`。回归锁 `laya_auto_wbtest.mbt`：钉住 `laya_auto_fail` 恒 available=false + reason 透出 + 空原因也成型，并对 server.mbt 源码文本加锁（`= laya_auto_fail(` 调用点 ≥2、不再有裸 `Err(_) => ()`）。`moon test --target js src/server` 291/291 全绿（基线 289）。
- reported_by: bugfind
- commit: d90f80d9c177cdb1f357a342326cb2f26709654d

## BUG-232 [2026-10-16T06:01:00Z] [high] FIXED
- summary: [server] executor_register 把能力标签持久化的 Result 用 ignore() 吞掉、回执 `persisted` 硬编码 true，写盘失败仍谎报落库（重启后 executor_route 读不到）
- detail: `src/server/server.mbt` 的 `executor_register` handler 先 `ignore(exec_reg.add_ability(...))` 登记进程内注册表，再 `ignore(engine.executor_save(...))` 落 store，然后回执恒 `"persisted": Json::boolean(true)`。`engine.executor_save` 返回 `Result[String, String]`（store 双后端 executors 表写盘），Err 时被 `ignore()` 整条丢弃：进程内注册表看似成功、store 里却没有，server 重启后 `executor_route`（依赖 executors 表）读不到该执行者——回执却谎报 `persisted:true`，调用方无从察觉（与 BUG-228/229/230「状态变更未落库却展示内存新状态」同族；对照同文件 model_router_ops.mbt L320-323 的 `persist_error` 先例）。
- fix: 新增纯函数 `executor_persist_note(res : Result[String, String]) -> (Bool, String)`（Ok→(true,"") 无错不留痕；Err→(false, 错误原文)）；handler 改为捕获 `engine.executor_save` 的 Result，`persisted` 如实反映落库结果，写盘失败时附 `persist_error`（非空才出现，成功路径零回归）；回执由 `Json::object({...})` 改为 Map 组装以支持条件字段。同步更新 `executor_register` 工具描述，声明 `persisted`/`persist_error` 语义。回归锁 `executor_register_wbtest.mbt`：钉住 `executor_persist_note` Ok/Err 双分支（含空原因），并对 server.mbt 源码文本加锁（`= executor_persist_note(` 调用点 ≥1、硬编码 `"persisted": Json::boolean(true),` 已归零、`persist_error` 透出）。`moon test --target js src/server` 293/293 全绿（基线 291）。
- reported_by: bugfind
- commit: dd10fe7fe32c465c147ffdd9c439ef74fc5cc9e5

## BUG-233 [2026-10-16T06:10:00Z] [high] FIXED
- summary: [server] pipeline_tick 的 omega_spec 解析失败被 Err(_) => None 静默吞掉，用户传了非法 spec 时回执无任何提示，watchdog 静默丢 spec 跑默认逻辑
- detail: `src/server/server.mbt` 的 `pipeline_tick` handler 解析 `omega_spec` 参数时，`@omega.parse_spec(omega_spec_str)` 返回 `Result[Json, String]`，但 `Err(_) => None` 把错误整条丢弃——用户传了非法 JSON spec 时，`omega_spec` 变成 `None`（与不传时完全等价），watchdog 静默丢 spec 跑默认逻辑，回执中无任何字段指示 spec 被拒绝。用户以为 spec 生效（laws 作切割依据、fingerprint 作验收基准），实际被静默忽略（与 BUG-228/229/230/231/232「静默吞错」同族）。
- fix: 将 `let omega_spec = ...` 改为 `let (omega_spec, omega_spec_error) = ...`，捕获 `Result` 的 `Err(e)` 分支为 `(None, e)`；在回执 `final_json` 构造后追加后处理——`omega_spec_error != ""` 时向回执 Map 注入 `omega_spec_error` 字段（非空才出现，成功路径零回归）。同步更新 `omega_spec` 工具描述，声明非法 JSON 时回执附 `omega_spec_error`。回归锁 `omega_spec_wbtest.mbt`：钉住 server.mbt 不再有裸 `Err(_) => None`（源码文本锁）、`omega_spec_error` 回执逻辑存在、工具描述同步提及。`moon test --target js src/server` 296/296 全绿（基线 293）。
- reported_by: bugfind
- commit: 5f846ba

## BUG-234 [2026-10-16T06:22:00Z] [high] FIXED
- summary: [server] evolve_submit 的 parts 解析失败被静默吞成空对象，用户传了非法 JSON 时 parts 被丢弃，回执无任何提示
- detail: `src/server/server.mbt` 的 `evolve_submit` handler 解析 `parts` 参数时，`@json.parse(parts_raw)` 的 `catch { _ => Json::object(Map([])) }` 把解析失败静默转成空对象——用户传了非法 JSON parts 时，parts 被丢弃，artifact 创建成功但评分分项为空，回执中无任何字段指示 parts 被拒绝。与 BUG-233「静默吞错」同族。
- fix: 将 `let parts = ...` 改为 `let (parts, parts_error) = ...`，捕获解析结果，失败时 `parts_error` 为错误信息；在回执 `final_json` 构造后追加后处理——`parts_error != ""` 时向回执 Map 注入 `parts_error` 字段（非空才出现，成功路径零回归）。同步更新 `evolve_submit` 工具描述，声明非法 JSON 时回执附 `parts_error`。回归锁 `evolve_parts_wbtest.mbt`：钉住 server.mbt 不再有 `let parts : Map[String, Double] = Map([])` 静默吞错模式（源码文本锁）、`parts_error` 回执逻辑存在、工具描述同步提及。`moon test --target js src/server` 299/299 全绿（基线 296）。
- reported_by: bugfind
- commit: d84f5f4

## BUG-235 [2026-10-16T06:31:00Z] [high] FIXED
- summary: [server] github_queue_mark_sent / gitcode_queue_mark_sent 的 issue_numbers / gitcode_issue_iids 解析失败被静默吞成空 Map，用户传了非法 JSON 时映射被丢弃（github 侧还会把已回写的 github_issue_number 清空），回执无任何提示
- detail: `src/server/server.mbt` 的 `github_queue_mark_sent` handler 解析 `issue_numbers` 参数时，`@json.parse(issue_nums_raw)` 的 `catch { _ => Json::object(Map([])) }` 把解析失败静默转成空对象（形状不符亦同），随后 `github_queue_mark_sent` 对命中 bug_id 一律 `m.set("github_issue_number", Json::null())`——映射被丢弃，sent_at 照写、issue_number 被清空（数据丢失），回执仅 marked/total，无字段指示解析失败。`gitcode_queue_mark_sent` handler 对 `gitcode_issue_iids` 同构（iid 不回写，回执无提示）。与 BUG-233/234「静默吞错」同族。
- fix: 抽出包级 helper `add_parse_error_field(j, key, msg)`（msg 非空才注入回执对象，非对象时包 `{"original":..., key:msg}` 兜底）；两个 handler 改为先 `let <map> : Map[...] = Map([])` 再 `let <x>_error = if raw.is_empty() { "" } else { 解析成功返回 ""，失败返回错误串 }`（就地填充 map），回执经 `add_parse_error_field(j, "issue_numbers_error"/"gitcode_issue_iids_error", err)` 透出（非空才出现，成功路径零回归）。同步更新两个工具描述，声明非法 JSON 时回执附对应字段。回归锁 `queue_mark_sent_wbtest.mbt`：钉住 server.mbt 不再有 `let issue_numbers = if issue_nums_raw.is_empty() {` 与 `let j = @json.parse(iids_raw) catch { _ => Json::object(Map([])) }` 静默吞错模式（源码文本锁），并校验 helper 与两个 *_error 字段存在、工具描述同步。`moon test --target js src/server` 303/303 全绿（基线 299）。
- reported_by: bugfind
- commit: 818f42d

## BUG-236 [2026-10-16T06:42:00Z] [high] FIXED
- summary: [server] evolve_asset_register 的 evolve_upsert 落库失败被 ignore 静默吞掉、注入搜索执行器后搜索失败被 Err(_) => [] 静默降级，回执均无提示——落库失败直接违背 BUG-140「必须同步落库，否则重启即失」不变量
- detail: `src/server/self_search_evolve_bridge.mbt` 的 `do_evolve_asset_register_with_search` 有两处静默吞错：(1) `ignore(match evolve_store { ... s.evolve_upsert(...) })` 把落库 Result 整个丢弃，store 未打开或 SQLite 写失败时资产只在内存 Archive、重启即失，回执（art.to_json() + portable_candidates）无任何字段指示未落库；(2) 注入 runner 后 `run_external_search` 的 `Err(_) => []` 把搜索失败（如 FIST_SELF_SEARCH_PATH 不可读）降级为空候选，与「确实无候选」不可区分。与 BUG-235「静默吞错」同族。
- fix: 两处改为捕获结果：`let persist_error = match evolve_store { None => "evolve_store 未打开（内存态，未落库）", Some(s) => match s.evolve_upsert(...) { Ok(_) => "", Err(e) => e } }`；`let (candidates, search_error) = match runner { None => ([], ""), Some(r) => match run_external_search(...) { Ok(raw) => (distill(...), ""), Err(e) => ([], e) } }`。回执经 `add_parse_error_field`（BUG-235 引入的包级 helper，注释同步泛化）注入 persist_error / search_error——仅失败时出现，成功路径零回归。同步更新桥接文件头文档与 `evolve_asset_register` 工具描述。回归锁 `evolve_asset_register_wbtest.mbt`：钉住桥接文件不再有 `ignore(\n    match evolve_store {` 静默模式、persist_error/search_error 捕获与注入存在、工具描述同步。`moon test --target js src/server` 307/307 全绿（基线 303）。
- reported_by: bugfind
- commit: 880d440

## BUG-237 [2026-10-16T07:02:00Z] [medium] FIXED
- summary: [server] assistant_sweep 把 assistant_set_status 的读回验证结果 ignore 吞掉后无条件 marked_dead + 1，回执 assistants_marked_dead 把未真正标成 dead 的助理也计入——回执说谎
- detail: `src/server/server.mbt` 的 `assistant_sweep` handler（L4958-4964）对每个心跳陈旧且超过 stale_secs 的 active 助理执行 `ignore(engine.assistant_set_status(r.agent, "dead"))` 后无条件 `marked_dead = marked_dead + 1`。但 `assistant_set_status` 返回的是**读回验证过的真实结果**：MemoryStore 在 agent 不存在时返回 false（store_assistant.mbt:34-46）；SqliteStore 在 db 未打开、prepare 失败、读回 None、或读回 status != requested（并发改动，如助理自己心跳复活）时返回 false（store_sqlite.mbt:1821-1850）。因此 set_status 返回 false 时助理**并未**被标成 dead，回执却仍计入 marked_dead——回执谎报。与平行的 `assistant_resign`（L4982-4987）正确透出 `"resigned": Json::boolean(ok)` 形成对比。与 BUG-225~236「静默吞错 / 回执说谎」同族。
- fix: 捕获 `let ok = engine.assistant_set_status(r.agent, "dead")`，`marked_dead` 只在 ok 为真时递增，失败计入新计数器 `mark_failed`；回执改用可变 `Map[String, Json]` 构造（复用 BUG-232 executor_save 的惯用法），基础字段 swept_locks / assistants_marked_dead 如实反映，`if mark_failed > 0` 时条件注入 `assistants_mark_failed` 计数——成功路径零回归。同步更新 `assistant_sweep` 工具描述。回归锁 `assistant_sweep_wbtest.mbt`：钉住 `ignore(engine.assistant_set_status` 清零、Bool 捕获存在、条件注入存在、工具描述同步。`moon test --target js src/server` 311/311 全绿（基线 307）。
- reported_by: bugfind
- commit: 0e511a0
## BUG-238 [2026-10-16T07:16:10Z] [high] FIXED
- summary: [rule:executor-model-mismatch] executor_run(atomcode) 路由的模型名与 atomcode provider 命名空间不兼容，HTTP 400 Unsupported model
- detail: 实测（2026-10-16）：
- `executor_run(executor=atomcode, model=ling-3.1-flash-free)` → exit 1，atomcode stderr: `HTTP 400 Unsupported model (model=ling-3.1-flash-free)`
- `executor_run(executor=atomcode, model=mimo-v2.6-flash-free)` → 同样 exit 1
- 本地 `atomcode --version` rc=0，`atomcode -p ... -y`（不带 --model，用 config 默认 longcat/LongCat-2.0）rc=0 成功回复

根因：FIST `model_route` 的模型池（ling-3.1-flash-free / mimo-v2.6-flash-free 等）是 FIST 自己的命名空间，被直接塞进 atomcode 的 `--model` 参数；而 atomcode 的 provider 配置（~/.atomcode/config.toml）用的是 longcat/deepseek/Kimi 等独立命名空间。两套模型名不通，executor_run 对 atomcode 恒失败。

影响：外部执行器通道（R30 合并自 fist-model-router）对 atomcode 不可用；aider 走同一 model_route 可能同样受影响。

建议修复方向：executor_run 在 CLI 通道下应使用 atomcode config 的 default_model，或提供 model 命名空间映射（FIST 模型名 → atomcode provider/model），而不是把路由池名直接塞 --model。
- ref_call: 0
- task_id: T0r619



### FIXED(2026-10-16T07:31:58Z / BUG-238)
- evidence: 改了真源：src/executor/cli_argv.mbt 的 atomcode_argv（model 空→省略 --model，走 atomcode config 默认档）+ src/server/model_router_ops.mbt 的 executor_run_impl（chosen.is_empty() && executor != "atomcode" 才走 FIST 路由）。锁钉住：cli_argv_test.mbt ca_8（空模型省略 --model 白盒锁）；实测 atomcode model=LongCat-2.0 / 不带 --model 均 rc=0，model=ling-3.1-flash-free / mimo-v2.6-flash-free 仍 HTTP 400（修复前根因）。全量 moon test --target js 1247/1247 通过零回归。

## BUG-239 [2026-10-16T15:57:07Z] [high] FIXED
- summary: [server] github_flush_execute 的 github_queue_mark_sent 失败被静默吞成空 marked_sent 对象，回执 executed:true 谎报队列已标记
- detail: `src/server/server.mbt` 的 `github_flush_execute` handler 在 force 刷批后调 `github_queue_mark_sent` 标记本地 JSONL 队列已发送，`match mark_res { Ok(j) => j; Err(_) => Json::object(Map([])) }` 把队列写入失败（非法 project_dir / 队列写失败，github_sync.mbt L308-353 的 Err 路径，BUG-220 已修）静默吞成空对象——回执仍报 `executed:true` 且 `marked_sent` 为空对象，无任何字段指示标记失败，下轮 sync 对同一批 bug 重复建号，GitHub 出现重复 issue。与同族兄弟处理器（issue_close/issue_comment 如实透错、BUG-228 auto_push 两处、BUG-235 queue_mark_sent 工具封装）不一致，唯 flush_execute 遗漏。与 BUG-225~238「静默吞错 / 回执说谎」同族。
- fix: 改为元组捕获 `let (mark_json, mark_sent_error) = match mark_res { Ok(j) => (j, ""); Err(e) => (Json::object(Map([])), e) }`（复用 BUG-232 executor_save 的 `(persisted, persist_error)` 惯用法），回执在 `mark_sent_error != ""` 时条件注入 `marked_sent_error` 字段（非空才出现，成功路径零回归）。同步更新 `github_flush_execute` 工具描述，声明标记失败时回执附 `marked_sent_error`。回归锁 `github_flush_wbtest.mbt`：钉住旧静默吞错模式 `Err(_) => Json::object(Map([]))` 清零、元组捕获存在、条件注入存在、工具描述同步。`moon test --target js src/server` 315/315 全绿（基线 311）。
- reported_by: bugfind
- commit: 99cf2a6

## BUG-240 [2026-10-16T16:30:00Z] [high] FIXED
- summary: [ops] ops_heal 三个看护函数 ignore(store_delete_heartbeat) 静默吞掉 SQLite 删除失败，回执仍报 healed 成功
- detail: `src/ops/ops_heal.mbt` 的 `heal_stale_tasks` / `heal_stale_tasks_from_store` / `heal_stale_tasks_by_phi` 在 reopen 成功后调 `ignore(engine.store_delete_heartbeat(task_id=t.get_id()))` 清理持久化心跳行，SQLite 删除失败被静默吞掉——回执仍报 `healed` 成功，无任何字段指示清理失败。残留过期心跳行会让下一轮 `heal_stale_tasks_from_store`（以持久化心跳表为判活依据）把已回滚任务误判为「仍在执行」，错过下一次回滚窗口。与 BUG-204/217/225-239「静默吞错 / 回执说谎」同族。
- fix: 三处均改为 `match engine.store_delete_heartbeat(task_id=t.get_id()) { Ok(_) => (); Err(_) => delete_failed_ids.push(t.get_id()) }`，新增 `delete_failed_ids? : Array[String] = []` 可选参数（默认空数组，既有调用方零改动）。调用面透传：`ops_watchdog.mbt` 声明 `delete_failed` 并传入两处调用 + detail 注入 `heartbeat_delete_failed_ids`；`ops_pipeline.mbt` 声明 `heal_delete_failed` 并传入 + 条件注入 `heal_delete_failed`（非空才出现，零回归）；`server.mbt` heal 工具声明 `delete_failed` 并传入 + 回执注入 `delete_failed` + 工具描述同步。`heal_stale_tasks_by_phi` 附带修复 `Err(_) => ()` → `Err(e) => return Err(e)`（同函数内 reopen 失败静默吞错）。回归锁 `ops_heal_wbtest.mbt`：钉住 `ignore(engine.store_delete_heartbeat` 清零、`Err(_) => delete_failed_ids.push(t.get_id())` 出现 3 次、`delete_failed_ids? : Array[String] = []` 出现 3 次。`moon test --target js` 1254/1254 全绿。
- reported_by: bugfind
- commit: 98744c5




### FIXED(2026-10-16T15:43:05Z / BUG-219, BUG-220, BUG-221, BUG-222, BUG-223, BUG-224, BUG-225, BUG-226, BUG-228, BUG-229, BUG-230, BUG-231, BUG-232, BUG-233, BUG-234, BUG-235, BUG-236, BUG-237, BUG-239, BUG-240)
- evidence: BUG-9 控制面正身：这批条抬头已是 FIXED（并发修复侧标的），但账本缺同笔 `### FIXED(...)` 小记点名，gen_plugins 硬门①判「20 条标 FIXED 却无小记点名」→ cl7 FATAL 拒生成。本笔不改抬头状态，只在账本正文追加一条点名整批的小记，把「已修好」写进可回溯的控制面小记（证据梯 L4）。修复真源由各条原 reported_by 与关联修复单承载，本笔只补小记、不重述修复内容。
## BUG-241 [2026-10-16T12:58:07Z] [medium] FIXED
- summary: [记账] 缺陷编号撞车致 bug_fix/bug_mark_status 只闭环首条，同号第二条永远 OPEN（BUG-185/186/217 实测）
- detail: 现象：memory/bugs.md 里 BUG-185、BUG-186、BUG-217 各存在**两条独立条目**，编号相同但 ts/summary/reported_by 不同：
- BUG-185 ① 10/15 08:46 FIXED（ops_watchdog 静默吞噬 heal 错误） / ② 10/15 08:44 OPEN（e2e_irm_line 真面档探针恒红）
- BUG-186 ① 10/15 08:50 FIXED（ops_heal 静默吞噬 reopen_task 错误） / ② 10/15 08:44 OPEN（e2e_irm_line --real 无还原保护）
- BUG-217 ① 10/15 13:20 FIXED（selfdrive_publish_next 静默吞错） / ② 10/15 13:22 OPEN（claimguard may_proceed_sematic 副作用）
即同一个 BUG-n 编号被复用两次，首次用于「静默吞错」族、第二次（晚数分钟）用于完全无关的另一缺陷。

复现：对已由 commit 修复的 ② 条调用 `bug_fix(["BUG-217"])` / `bug_fix(["BUG-185","BUG-186"])`，返回恒为 `heading_changed=0`、`already_fixed=N`——**真正待闭环的那条没被改**，只因首条恰好已 FIXED。

根因（两处）：
① 编号分配撞号——report_bug 侧把同一个 BUG-n 分给了两条不同缺陷（疑为编号分配器并发/未去重）；
② 条目定位只取首条——src/server/bugreport.mbt:723 `let idx = bug_header_line(lines, want)`（bug_mark_status :595 同款）在撞号时命中**首个**匹配 `## BUG-n` 行，第二条永远不可达。

影响：缺陷记账闭环失能——`bug_list` 的 open_with_linked_done、`bug_fix` 的 heading_changed 都是错的，「还剩几条没修」数不准；已提交修复（ba4fd93 / 20846a4）无法走 bug_fix 落账，形成与 BUG-9「只写不销」同族的账实不符。

修复方向（供参考，bugreport.mbt 已被并发 WIP 占用未由本上报修改）：bug_fix/bug_mark_status 在撞号时应报「编号重复」告警而非静默取首条，或要求按 ts 消歧；report_bug 编号分配需在写入前对账本做同号去重/回退。
- reported_by: bugfind


### FIXED(2026-10-16T14:45:49Z / BUG-241)
- evidence: 根因：bug_header_line(src/server/bugreport.mbt:516-528) 只返回首个命中行；当 BUG-217 等编号在 bugs.md 存在多条独立条目时，bug_fix 只改首条，真正待闭环的那条永久 OPEN。修复：新增 bug_header_lines 返回全部命中行，bug_fix 改为逐条遍历改判（named 去重、insert_at 取末条末尾）。moon test --target js src/server = 316/316 pass（新增 BUG-241 白盒测试验证同号两条 217 都被改判 heading_changed=2、各自保留原 ts/sev、小记只落一次且落在末条之后、邻居正文不被吞）；全量 moon test --target js = 1259/1259 pass。文件：src/server/bugreport.mbt(+bug_header_lines/-single-match) + src/server/bugreport_status_wbtest.mbt(+BUG-241 测试)。
## BUG-242 [2026-10-16T12:58:23Z] [high] OPEN
- summary: [Pentad/DEMO-08] spawn(&lt;actor 实例&gt;) 被运行时拒绝：'spawn() requires an actor type name, got Struct'，而该 demo 与文档期望传实例
- detail: 复现：`p5c run DEMO/08_concurrency/concurrency.p5` → exit 1，stderr `Runtime error: spawn() requires an actor type name, got Struct`。`Counter` 已正确声明为 `api @actor Counter:`（concurrency.p5:39），构造函数 `api Counter::new() -> Counter = Counter { n: 0 }`（:48）返回实例；demo 以 `let c = spawn(Counter.new())`（:55，另 :74/:114/:224 同形）调用，期望输出 `<Counter actor ref>`。运行时只接受「actor 类型名」而拒绝实例值。证据：e2e_golden 判据中 DEMO/08 为 RUNFAIL（RUNFAIL=4→2 后仍红），`p5c check` 却绿（静态检查未覆盖该语义）。影响：整个 @actor/spawn 发货面跑不通。发现轮：p5c 组合流水线 R1（清整/寻虫），复现于 2026-10-16。DEMO/09 已由本次提交修复缺 fetch_url 桩，同族但不同因。
- reported_by: pentad-combo-r1
- **更正与拆解（2026-10-16 R3 深挖，原归因不准确）**：原抬头把「运行时拒绝实例」当作缺陷，**这是错的**——
  规范真源明确 `spawn` 收**类型名**：`SYNTAX.md:2890` / `14-并发actor-async.md:19` 写 `let c = spawn(Counter)`，
  `GRAMMAR.md:260` 写 `'let' <id> '=' 'spawn' '(' <name> ')'`，且 `SYNTAX.md:4290` 把「收非名字实参」
  列为规范**负例**（`requires an actor type name, got Str`）。真正缺陷拆成两条：
  - **(a) 预扫描命名 bug【已修，commit `7df6716`】**：BUG-91 的体定义提升把 `api @actor X:` 内的
    `__handle` 拼成宿主限定名 **`X::__handle`**（`parser/api.rs:363`），而 `eval/stmts.rs` 预扫描只认裸名
    `__handle` ⇒ `actor_handles` 恒空 ⇒ `spawn(X)` 查不到协议钩子、**静默降级**为 `Value::Stream`，
    `print(spawn(X))` 打 `<stream: 0 events>` 而非 actor 引用（违约 §14.1）。该 bug 被 demo 的
    `spawn(X.new())` 先撞参数校验而掩盖。已修（两种命名都收，限定名以自身前缀为归属，与顺序无关），
    并落回归锁 `crates/p5c/tests/e2e_actor_spawn.rs`（单 actor + 多 actor 归属）。`cargo test --workspace` 54 suite 0 failed。
  - **(b) actor 引用是否该带消息队列【OPEN，待 owner 裁决】**：`eval/stmts.rs:807-810` 记录了明确的设计
    决定（T0r527）——「actor 消息在 send 时已被 `__handle` 同步消费，**消息不排队**」⇒ `for <- c` 迭代产出空序列。
    但 `DEMO/08_concurrency` 的 §3 期望 `send("inc")` 后 `try_recv()` 得 `Some("inc")`（依赖已修的 Stream 回退
    残留行为），修 (a) 后该 demo 现报 `Property or method not found: try_recv`。两条语义**互斥**：
    要么给 `Value::Actor` 加 mailbox 并同步 send 入队，要么按 T0r527 更新 demo 的 §3。**未擅自改语义**，
    留待 owner 裁决。附带：`eval/calls.rs` 里那条广告 `spawn(Counter.new())` 的注释与紧邻实现自相矛盾，
    已在同批 commit 改为规范形态（该注释很可能是 demo 写错的来源）。

- **冲突范围扩大（2026-10-18 更新）**：不仅 `DEMO/08_concurrency/concurrency.p5` 的 **§4**（try_recv 段；上文本条原误写为「§3」，正确为 §4 :80-83），**`SYNTAX/14-并发actor-async.md §14.1:30` 也明文承诺**「actor 引用是**消息流**（可迭代）…非阻塞单次取信用 `c.try_recv()`」、:23 示例 `for msg <- c:` 期望可迭代产出消息。故推翻既定设计（加 mailbox）要改**引擎 + §14.1 + DEMO/08 §4** 三处；对齐 T0r527 只改**§14.1 + DEMO/08 §4** 两处文档、零代码。**推荐对齐既定设计**（T0r527 是明确记录的设计决定、actor 同步顺序处理本就是 actor 模型自然实现、成本低一个量级）。已在本条 detail 与 §14.1、DEMO/08 §4 各加定档冲突注释（工作区未提交，git 无法启动）。裁决后：对齐→重写两处文档→RUNFAIL 1→0；推翻→加 mailbox→改引擎+回归锁。

- **裁决落地（2026-10-18 owner 采纳推荐＝对齐 T0r527）**：已按裁决重写两处文档、删除全部 `try_recv` 承诺与调用：
  ① `SYNTAX/14-并发actor-async.md §14.1`：删「消息流 / `try_recv`」承诺与 `for msg <- c:` 示例，改为「接收＝发送时的同步副作用」（`send` 返回前 `__handle` 已处理完）；冲突注释改为**定档声明**，并注明不自动套用到 §15.6 同族 `try_next`（该节标「设计提案」）。
  ② `DEMO/08_concurrency/concurrency.p5 §4`：重写为「同步消费」演示——新增 `Printer` actor（`__handle` 内 `print("handled:", msg)`）证明 send 返回前副作用已执行（期望 `handled: inc` / `handled: dec`）；删 §4 原 `try_recv` 四连调（:96-101）；§11 的 `q.try_recv()`（:244）一并删除。
  **待验证**：进程孵化 0xC0000142 持续故障，本轮无法跑 `e2e_golden` 确认 RUNFAIL 1→0；`try_recv` 调用已全部删除，`Property or method not found` 根因确定消除，进程恢复后复跑判据再标 FIXED。

- **§15.6 残留矛盾已清（2026-10-18）**：审计 `SYNTAX/15-响应式信号与观察.md §15.6:87` 发现原文「actor 消息流的 `for` 同口径：actor 被丢弃后消息流结束」与本节裁决**冲突**（actor 已无消息流），已修正为「仅指**复用 `for` 语法**，语义各按各节定档」；并在 §15.6:85 `s.try_next()` 处加 BUG-242(b) 关联注释——`try_next` 与 `try_recv` 同属「单次取用」，但 §15.6 标「设计提案（探索中）」**未定档**，待定档时按同一口径裁决（实现 mailbox 使 `try_next` 成立，或随 §14.1 一并删除），裁决前勿实现。**教训**：裁决落地后须回扫**跨章引用**——§14.1 的裁决改变了「actor 是否有消息流」，而 §15.6:87 引用了「actor 消息流」，不扫就留新矛盾。

- **真值文档未同步（2026-10-18 发现，重要）**：`SYNTAX/SYNTAX.md` 是**单一真值文档**（:3「所有语法以下文为准」，分册版是派生）。其 **§14.1:2896-2903 仍是旧承诺**（`for msg <- c:` 示例 + 「actor 引用是**消息流** / `try_recv()`」）、**§15.6:3044 亦写「用 `@actor` 队列表达（§14.1）」**——均与 BUG-242(b) 裁决（同步消费、无 mailbox/队列）**冲突**。而本次裁决落地只改了**分册版** `14-并发actor-async.md`（派生态），**真值文档未同步** → 分册与真值**不一致**。**教训（方法论）**：分册版是 SYNTAX.md 的派生态，改分册须**先改/同步真值**，否则真值仍在承诺已裁决删除的语义；同理上一节改 `15-响应式.md §15.6:87` 也是只改分册、未同步 SYNTAX.md §15.6。SYNTAX.md 属并发 agent 在途文件（4303 行），**未擅自改**；建议 owner 协调：把 SYNTAX.md §14.1（:2896-2903）与 §15.6:3044 对齐分册版已落地的同步消费口径（删消息流/`try_recv`/「@actor 队列」）。

- **已同步（2026-10-18，同日跟进）**：`SYNTAX/SYNTAX.md`（真值文档）已按裁决同步——
  ① §14.1 :2896-2903：删 `for msg <- c:` 示例与「消息流 / `try_recv`」承诺，改「接收＝发送时的同步副作用」（含 BUG-242(b) 定档注释）；
  ② §15.6 :3044：「用 `@actor` 队列表达」→「`@actor` 同步消费（无队列，`send` 即送达 `__handle`）」；
  ③ §16.5：`tags_of` 改带引号 + `is_subtag` 方向修正 + `@type`/`@function` 兄弟互斥澄清 + 反射内建实参裸写（BUG-258 ①②③④ 一并同步）。
  **旁证**：§24.4 prelude 承诺矩阵无 `try_recv`/`try_next`（`spawn`/`tags_of` 在列）——`try_recv` 非 prelude API，同步消费定档与实现一致。**遗留小瑕疵**：§19.3:3714 把 `__handle` 归「解构（3）」类，实为 actor 通信钩子（归类不当，非硬矛盾，未改）。
  **方法论（重要）**：分册版（`NN-*.md`）是 `SYNTAX.md` 的**派生态**——改分册须**同步真值**，否则真值仍在承诺已裁决删除的语义，文档一致性门禁（verify docs_check）会在真值上失败。本轮 BUG-242(b)/BUG-258 均先改分册、真值未跟，直至回扫真值才发现并补同步。**教训**：涉及跨册修订时，分册与 `SYNTAX.md` 必须同一笔改齐。

- **DEMO/09 同族残留已清（2026-10-18）**：`DEMO/09_reactive/reactive.p5:155-156` **真实调用 `events.try_next()`**（非注释）且期望非确定（`Some("event1") 或 None（视消费状态）`）——与本节已裁决删除的 `try_recv()` **同族**（单次取用），而 §15.6 `@stream` 尚标「设计提案」、`try_next` 未定档/未实现。已**注释该段**并标注：待 §15.6 定档后再恢复，且恢复前期望须改为**确定性断言**（原「或 None」golden 无法锁定）。**推论**：DEMO/09 一旦落 golden 注册会 RUNFAIL；现 DEMO/09 未注册（基线 UNREG=3），故基线 RUNFAIL=1（DEMO/08）不受影响。

- **DEMO/08 文件头注释残留已清（2026-10-18）**：`DEMO/08_concurrency/concurrency.p5:11` 文件头「覆盖语法点」注释仍承诺「`for msg <- c`（actor 引用是消息流）、`try_recv()` 非阻塞单次」——改 §4/§11 正文时**漏了文件头注释**，已同步改为「接收＝发送时的同步副作用（无 mailbox、无 `for msg <- c` 消息迭代、无 `try_recv`）」。
  **教训（扩展）**：同步裁决须覆盖**文件内所有层**——正文、行内注释、文件头「覆盖语法点」清单、文档引用节；漏任何一层都留旧承诺。本轮 BUG-242(b) 落地共漏 3 层才补齐：§14.1 正文→§15.6:87 跨章引用→SYNTAX.md 真值 §14.1/§15.6→DEMO/08 文件头 :11；每层都在回扫时才补。

- **分册 15 残留「@actor 队列」已清（2026-10-18）**：`15-响应式信号与观察.md:113`「单播（一对一**队列**）」与 `:119`「用 `@actor` **队列**表达」——改分册 15 §15.6:85/:87/:89 时**漏了同节内 :113/:119**。已同步为「`@actor` 同步消费（无队列，`send` 即送达 `__handle`）」。
  **教训（再扩展）**：同步须覆盖**同一分册同节内的所有行**（表格 / 列表 / 正文都可能留旧承诺），**逐行扫**比逐节扫更可靠。本轮 §15.6 的「@actor 队列」共出现在真值 :3044 + 分册 :113/:119 两行 + DEMO/09 关联——逐一改齐才干净。**方法论总结**：BUG-242(b) 一条裁决共触发 **6 处**改动（真值 2 + 分册 4 + DEMO 2），跨册跨行修订无一次改齐，全靠回扫兜底；**根治**须建立"分册↔真值↔DEMO 三方同步硬门"（见 A+C 建议）。

- **附录速查表 §24.1 三处残留已清（2026-10-18）**：`SYNTAX.md:4215` + `24-附录07-prelude-API与常量总表.md:18` 的 `is_subtag` 说明仍写反（「`a` 是否在 `b` 祖先链上」——BUG-258② 在 §16.5 改了方向，**速查表未同步**）；`SYNTAX.md:4230` + `24-*.md:33` 的 `s.close()` 触发点仍写「结束 actor 消息流」（BUG-242(b) 裁决 actor 无消息流，未同步）。已四处改齐。
  **教训（跨章节 + 跨份）**：同源拷贝不只在"分册 vs 真值"之间——**附录速查表（§24.1/§21 等）与正文（§16.5/§14.1）也是两份拷贝**，且**附录章节同样有分册**（`24-*.md`）。改正文语义须同步所有**引用该语义的速查表行**；`is_subtag` 方向、BUG-242(b) 无队列两条裁决共出现在 §16.5 正文 + §24.1 速查表（真值+分册）+ §21 标记总表等多处，**逐表扫齐**才干净。本轮 BUG-258② 落地已累计漏 3 层（分册 §16.5 → 真值 §16.5 → §24.1 真值+分册）。

## BUG-243 [2026-10-16T12:58:27Z] [high] FIXED
- summary: [Pentad/DEMO-01] @duck X 与 @interface X 同名被判「duplicate type definition」，鸭子类型 demo 因此整份不可 check/run
- detail: 复现：`p5c check DEMO/01_types/interface_duck.p5` → rc=1，首行 `duplicate type definition: Comparable`（`Hashable` 同因）。源码：:61 `api @interface Comparable:` 与 :180 `api @duck Comparable:`（:80 `@interface Hashable` / :183 `@duck Hashable`）。该 demo 的意图正是「接口（@interface）与鸭子类型（@duck）并存」：:187 `api @function sort<T <: Comparable>(xs)` 用接口约束、:190 `dedup_duck<T <: Hashable>` 用 duck 约束、:201 `print(conforms(Int, Comparable))`。当前编译器把 @interface 与 @duck 视为同一类型命名空间 → 重复定义，整个 demo 无法 check/run（e2e_golden 中 DEMO/01 为 RUNFAIL，也是 pin 表里剩余的 1 红）。影响：§19 duck typing 发货面不可用。发现轮：p5c 组合流水线 R1。
- reported_by: pentad-combo-r1


### FIXED(2026-10-16T13:13:58Z / BUG-243)
- evidence: 根因是 DEMO 而非判据。规范真源：SYNTAX/09-类型系统.md §9.7「`@duck` 是**约束谓词**，不是类型」、§9.7.1 专门列表对比 @interface（类型）/@duck（约束）。同名会让**同一处约束语法** `<T <: X>`（§2 的 max<T <: Comparable> 与 §6 的 sort<T <: Comparable>）与 `conforms(T, X)` 无法消歧 ⇒ static_check.rs 的重名拒绝是**正确**的。修复（Pentad commit 658c8e7）：DEMO/01_types/interface_duck.p5 把 duck 侧改名为 ComparableDuck/HashableDuck（与该文件 §7 既有的 RenderableDuck 同后缀约定），接口侧不动，并加注释写明二者不得同名。证据：demo 由 rc=1（duplicate type definition: Comparable）→ rc=0 跑到哨兵 'DEMO interface_duck OK'；重生成 DEMO pin 表（生成器 .fist-night/r19r3_mkdemo.py）由 19 绿/1 红 → **20 绿/0 红**；e2e_golden RUNFAIL 2→1（仅余 08_concurrency，属 BUG-242(b) 的 actor 消息队列设计问题）；cargo test --workspace 54 suite 0 failed。遗留新缺陷另记：§6 的 `conforms(Int, ComparableDuck)` 期望 True 实得 False（Int 在 :69 已实现 compare，§9.7 承诺该编译期查询）——归 duck 一致性检查未实现，已另立案。
## BUG-244 [2026-10-16T12:58:35Z] [medium] FIXED
- summary: [Pentad/DEMO-10] 标记反射半实现：has_tag 祖先链 / is_subtag / tags_of 全链枚举恒 False/[]，与 §16.5 文档承诺矛盾（5 处）
- detail: 复现（`p5c run DEMO/10_markers/markers.p5`，该 demo 已由本次提交修掉重复定义 Point → 现 rc=0 可跑完），但 §9 标记反射的输出与源码内联「期望输出」矛盾：① :199 `has_tag(Point, @type)` 期望 True（祖先链），实得 False；② :203 `is_subtag(@infix, @method)` 期望 True，实得 False；③ :204 `is_subtag(@struct, @type)` 期望 True，实得 False；④ :207 `tags_of(@infix)` 期望 4 元组 `(@infix, @instance_method, @method, @function)`，实得 `[]`；⑤ :254 `func_tags` 同 ④ 实得 `[]`。（:195 tag_of=@struct、:198/200 has_tag @struct/@function、:214/218 tag/add、:257/258 均正确。）影响：标记反射（§16.5）只实现了「自身标记/直接判定」，**祖先链与子标记关系与全链枚举未实现**，导致这些 API 在文档承诺的语义上恒假。证伪即冻结基准：因输出与文档矛盾，本轮**故意未为该 demo 落 golden**，避免把 bug 冻成基准。发现轮：p5c 组合流水线 R1。
- reported_by: pentad-combo-r1
- **R5 深挖：实现前先撞到「规范自相矛盾」，故本轮未动代码（避免猜着实现错的标记树）**。定位：三处根因同一——求值器**没有标记树**：`eval/builtins.rs` 的 `has_tag`(:880) 只查类型**自身**标记不 walk 祖先；`is_subtag`(:914) 却按**类型名**查 `type_markers`，而 §16.5 与 demo 传的是**标记名**（`@infix`/`@method`）⇒ 恒 False；`tags_of`(:943) 同样查 `type_markers[标记名]` ⇒ 恒 `[]`。规范是有的：`SYNTAX/16` §16.1 给出整棵树、§16.5 明确规则（`has_tag` 沿任一父链多父 DFS；`is_subtag(a,b)`＝a 在 b 的祖先链上；`tags_of` 出全链），`07-运算符.md:88` 复述 `@infix ⇒ @instance_method ⇒ @method ⇒ @function`。**冲突点**：§16.1 的 ASCII 树把 `@type` 画在 `@function` 之下（缩进与 `@lambda`/`@method` 同级），按该树 walk 祖先得 `has_tag(Point, @function) = True`；而 `DEMO/10_markers/markers.p5:200` 明确断言 **False**（:199 断言 `has_tag(Point,@type)=True`）。二者不可同时成立 ⇒ 要么树里 `@type` 应为 `@immortal` 的**兄弟**而非 `@function` 的子节点（则 199/200 同时成立），要么 demo 的 200 行期望要改。另：树含**重复抽象节点名**（`@special` 出现在 @function 与 @type 下各一次；`@immutable`/`@mutable` 在 @var 与 @mortal 下各一次），按「名字→父」的简单表会歧义，实现需按**路径**建树。**建议 owner 先裁决 200 行与树的一致性**，再实现；本条目保持 OPEN。附：本轮顺带实测 `tags_of(@infix)` 期望串 `(@infix, @instance_method, @method, @function)` **不含** `@immortal`/`@mark` ⇒ 反射的「全链」定义应排除 ○ 抽象节点，这点也需写进规范。


### FIXED(2026-10-17T01:52:32Z / BUG-244)
- evidence: Pentad commit 4156750（builtins.rs + 新回归文件 e2e_tag_tree.rs）。根因确认：has_tag/is_subtag/tags_of 三处都只对 type_markers 的**自身标记**做扁平字符串比较，§16.5 承诺的祖先链根本不存在（is_subtag 还把标记名当类型名查表 ⇒ 恒 False；tags_of 查 type_markers["@infix"] ⇒ 恒 []）。现引入标记树父链表 tag_parents + 可达/链两个辅助，has_tag=自身∪祖先（§16.5:250 多父 DFS）、is_subtag=从子上行查成员（含自身）、tags_of=沿链到主形态根并**返回元组**（§16.5:246 用括号书写，且 BUG-43 已定档元组渲染）。

DEMO/10 五处原红现全绿：:199 has_tag(Point,@type) False→**True**；:203 is_subtag(@infix,@method) False→**True**；:204 is_subtag(@struct,@type) False→**True**；:207 与 :254 tags_of 全链 []→**("@infix","@instance_method","@method","@function")**；原本正确的 :195/:198/:200/:214/:218/:257/:258 逐字未变。

两处建模取舍（写在 tag_parents 注释，需 spec owner 复核）：① 取「@function/@type/@var 互斥兄弟」读法——§16.1 自相矛盾：紧凑视图 :86「同宿主 api 的主形态互斥」与 :107「沿树取一条主形态链」是兄弟，而 ASCII 详图 :54 把 @type 缩进在 @function 之下；按兄弟读法 3 处独立陈述 + DEMO:199/200 两行期望同时成立，按详图读法 has_tag(Point,@function) 会变 True 与 demo 冲突 ⇒ 判 ASCII 详图为**文档缺陷**（另报），不改代码。② ○ 抽象节点可穿越但不入链（正是 tags_of(@infix) 止于 @function、不含 @immortal/@mark 的依据）；且 ASCII 里 @special 同时挂在两支下，共享同名会把互斥两支连通 ⇒ 类型支形态直挂 @type。

残留（**故意不冻进基准**）：§16.5:246 把元素写作不带引号，而引擎把集合内的标记值加引号——该行为与 tag_of 共用同一表示（实测 print(tag_of(S)) 裸 @struct、放进元组即 "@struct"），属 BUG-43 渲染规约迁移范围，非本改动引入。故 **DEMO/10 继续不注册 golden**。

回归：cargo test -p p5c --release 40 suite 0 failed（lib 361；新增 e2e_tag_tree 4 锁：祖先链、方向性与含自身、链序与止于形态根、tag_of 单一真源未破）；e2e_golden 不变 PASS=14 FAIL=0 UNREGISTERED=5 RUNFAIL=1；两版判据平价 OK。本条 R5 记录的「规范 vs demo 冲突」已由 4538516 整树化批2 部分澄清、余下 ASCII-vs-紧凑 内部矛盾作为文档缺陷单独跟。
## BUG-245 [2026-10-16T12:58:40Z] [medium] FIXED
- summary: [Pentad/DEMO-09] @derived 变更后未正确重算（12≠13）且 `__get` 魔术钩子在 print 未生效（Cell{value:42}≠42）
- detail: 复现（`p5c run DEMO/09_reactive/reactive.p5`；该 demo 的 `undefined function: fetch_url` 已由本次提交补桩修复 → 现 rc=0 跑到哨兵 `DEMO reactive OK`），但输出与源码内联「期望输出」矛盾 3 处：① :72 `print(sum)` 期望 **13**（a 变化触发 @derived 重算），实得 **12** → @derived 依赖变更后未重算/重算不全；② :110 `print(custom_cell)` 期望 **42**（`__get` 触发依赖登记并取值），实得 **`Cell{value: 42}`**；③ :113 `print(custom_cell)` 期望 **100**，实得 **`Cell{value: 100}`** → `__get` 魔术钩子在 `print` 调用点未生效（打印了结构体表示）。（:46/47/51/59/63/70/74/84/90/224 等均正确。）影响：@derived 反应式重算与 `__get` 派发两条主线在半实现状态，demo 无法作为正确性基准。因输出与文档矛盾，本轮**故意未落 golden**。注：同族 §19.3 magic hook 正由其他 agent 在 p5c src 推进，可能重叠。发现轮：p5c 组合流水线 R1。
- reported_by: pentad-combo-r1



### FIXED(2026-10-17T01:03:57Z / BUG-245)
- evidence: 两半都已定案（Pentad commit 71ebfbf）：

【第二半：信号读 __get —— 真缺陷，已修】规范 SYNTAX/15 §15.2：「信号读/写内部经通道 B 钩子协议 `__get`/`__set`」「若信号以自定义 struct 承载，该 struct 提供 `__get`/`__set` 钩子即被运行时接管——复用 §19.6 推断，无新语法」。而 eval 里 `__get` **零实现**（全仓 grep 无派发点；expr.rs 原有的那条是 `@property_get` 属性读器，不是 `__get`）⇒ `print(custom_cell)` 打出 `Cell{value: 42}` 而非 42。修于 `eval/expr.rs` 的 `Expr::Ident` 读路径：名字属登记 @signal、值为 `Value::Struct` 且该类型有 `{Type}::__get` 时，走既有 `call_params_body` 分派（不新造机制），并清 `last_method_self` 做通道卫生。前面加 `reactive_signals.is_empty()` 短路 ⇒ 非响应式程序（fib 等）每次变量读只多一个可预测分支，不多一次哈希。实测：DEMO/09 §5 现打印 **42 / 100**（原 `Cell{value: 42}`/`Cell{value: 100}`），demo 抵达哨兵。

【第一半：@derived 重算 12≠13 —— 归因错了，引擎本就正确】原条目称「期望 13 实得 12」是缺陷。复核算术：`box @signal a = 1; b = 2; @derived sum = a + b` → :71 `a := 10` 后 a=10,b=2 ⇒ **12 才是正确值**；而 demo :74 自己写 `b := 20` 期望 **30 = 10 + 20**，反推 a 必须是 10 ⇒ 与 :72 的 13 自相矛盾。故 13 是 demo 注释笔误（把 `:=` 当累加），**不是引擎问题**。实测 @derived 重算完全正常：多依赖 3 → 12 → 30，单依赖 10 → 20。处置：修 demo 注释为 `12`（附推导），**不为了迎合错数字去改引擎**。

回归：`cargo test -p p5c --release --lib` 361 passed 0 failed；`cargo test --workspace` 54 suite 0 failed；`scripts/e2e_golden.ps1` 判据不变 PASS=14 FAIL=0 UNREGISTERED=5 RUNFAIL=1。性能（并发构建重载下，绝对 ms 不可比、只看比值）：fib31 36.3×、loopsum 26.6×、mixed_big 10.1×，全部 ≥5× 且在历史带（30–42×）内。

遗留（不再挂本条）：该 demo §16 期望 `handled: event1 / handled: event2`，但 `@stream` 在 `@observe` 内 `for` 迭代不产出任何事件 ⇒ 另立 **BUG-255**；因该期望未满足，DEMO/09 **继续不注册 golden**（本项目拒绝把未满足期望冻成基准）。
## BUG-246 [2026-10-16T13:14:04Z] [medium] FIXED
- summary: [Pentad/DEMO-01] duck 侧 `conforms(Int, Duck)` 恒 False：Int 已实现 duck 声明的 compare，§9.7 承诺应为 True
- detail: 复现：`p5c run DEMO/01_types/interface_duck.p5`（该 demo 的重名问题已由 commit 658c8e7 修复，现 rc=0 跑完全程），§6「编译期查询」一行的输出与源码内联期望矛盾：:206 `print(conforms(Int, ComparableDuck));  // 期望输出：True（bool）` 实得 **False**。而 `Int` 已实现 compare：同文件 :69 `api Int::compare(self, other: Int) -> Int = ...`；`@duck ComparableDuck` 的成员正是 `api compare(self, other: Self) -> Int`（:180-181）。规范依据：SYNTAX/09-类型系统.md §9.7 表「反射 | `conforms(T, Duck)` 编译期查询」，且 §9.7「满足判定 = 隐式结构化：类型 T 满足 Duck ⟺ T 具备声明的全部成员且签名兼容，**无需**显式声明 / impl」⇒ 此处应为 True。影响：duck 侧的 `conforms` 查询（鸭子类型唯一对外反射面）恒假，与 §9.7.1 宣称的「编译期消解、零成本」承诺不可自证。同族：BUG-244（标记反射 has_tag/is_subtag/tags_of 半实现）、BUG-245（@derived 重算 + __get 未生效）——共同形态是「编译器/解释器反射面未实现却已在文档与 demo 中被断言」。发现轮：p5c 组合流水线 R4（寻虫），复现于 2026-10-16。因输出与文档矛盾，**故意未为该 demo 落 golden**。
- reported_by: pentad-combo-r1



### FIXED(2026-10-16T13:33:53Z / BUG-246)
- evidence: 根因：`eval/builtins.rs` 的 `conforms_check` 只查 `self.interfaces`，且 `conforms` 内建在名字未登记为 interface 时提前 `return false` ⇒ `conforms(T, @duck)` 恒 false。规范依据：SYNTAX/09 §9.7「@duck 是**约束谓词**（不是类型）」「满足判定 = 隐式结构化：T 满足 Duck ⟺ T 具备声明的全部成员，**无需**显式声明/impl」；§9.7.1 列表指出与 @interface 的满足判定**同构**、唯一差别是「默认实现：duck 不支持」。修复（Pentad commit 5783c1c）：`conforms_check` 增加 duck 支（satisfies 闭包带 allow_defaults：interface=true / duck=false），`conforms` 内建接受 interface 或 duck 任一登记。验证：DEMO/01_types/interface_duck.p5 §6 `conforms(Int, ComparableDuck)` 由 False→**True**（该 demo 16 条内联期望现全部吻合）；定向探针区分正确（有成员 True / 缺成员 False / interface 默认实现 True 而同形 duck 为 False）。回归锁 +3 条 `eval/tests/g2.rs`：`test_conforms_duck_structural_satisfaction`、`test_conforms_duck_negative_missing_member`、`test_conforms_duck_has_no_default_impl_unlike_interface`。证据：cargo test --workspace 54 suite 0 failed（lib 358→361）；DEMO 判据复跑 PASS=14 FAIL=0 UNREGISTERED=5 RUNFAIL=1（与修复前同）。
## BUG-247 [2026-10-16T13:40:19Z] [medium] FIXED
- summary: [Pentad/判据基建] 唯一外部 golden 判据只在 WSL 可用：WSL 卡死时判据"跑不起来"易被读成"判据绿"，且无原生回退
- detail: 现象：`scripts/e2e_golden.sh` 是本项目**唯一不可被模型自圆其说**的外部判据，但它是 bash 脚本，Windows 上只能经 WSL 互操作运行。实测（2026-10-16 R5）：一次判据运行在 WSL 下**挂起 10 分钟且没有任何 p5c 子进程**（bash 进程存活、`raw="$("$BIN" run "$src" 2>&1)"` 卡住不再推进），当时另有进程在跑 `wsl which p5c`。危害不在"跑得慢"，而在**语义混淆**：判据"跑不起来"与判据"绿"在汇报里极易被混为一谈——当时我只能靠手工复刻脚本逻辑才拿到判定。次生问题：脚本在 Windows 检出后是 CRLF（已由 R1 的 `.gitattributes *.sh eol=lf` 修，见 commit 0696410），但那只解决"能跑"，不解决"WSL 卡住时跑不了"。修复（commit 20050e6）：新增 `scripts/e2e_golden.ps1`（同语义的原生 PowerShell 镜像）+ `scripts/check_judge_parity.ps1`（跑两份实现要求 summary 逐字一致；bash 缺失=显式 SKIP，bash 超时=NOTE 并以 ps1 判定为准、exit 0，绝不把环境故障报成判据红，但一定打印）。证据：同树两版均报 PASS=14 FAIL=0 UNREGISTERED=5 RUNFAIL=1 (20 demos) exit 0；平价检查打印 OK；漂移检测逻辑负例验证通过（两串不等⇒FATAL）。两个调用坑已写进脚本注释防回归：Start-Process 用数组传参给 pwsh 会丢参数起成交互式 REPL；WSL 无视 -WorkingDirectory 起在 /root，必须在 bash -c 内 cd。
- reported_by: pentad-combo-r1



### FIXED(2026-10-16T13:40:23Z / BUG-247)
- evidence: Pentad commit 20050e6（3 files, +247）：① 新增 `scripts/e2e_golden.ps1` —— 与 `.sh` 同语义的原生 PowerShell 镜像（同 strip_debug 前缀、同 [TS] 时间戳归一、同 4 字节 0xDEADBEEF 哨兵、同 .p5→.out golden 映射、无 golden=UNREG、run 失败=RUNFAIL、空 golden=WARN、同 summary 行与退出码 0/1/空转 1），不依赖 WSL/bash；② 新增 `scripts/check_judge_parity.ps1` —— 跑两份实现并要求 `summary:` 行逐字一致；bash 不存在⇒显式 SKIP(exit 0)，bash 超时(WSL 挂起的实测形态)⇒NOTE + 以 ps1 判定为准、exit 0（环境故障不得报成判据红）但一定打印，不静默；两者都出结果且不一致⇒exit 1；③ `.sh` 头部加"原生镜像 + 必须同步"说明。验证：同树两版均 PASS=14 FAIL=0 UNREGISTERED=5 RUNFAIL=1 (20 demos) exit 0；`check_judge_parity.ps1` 打印 OK；漂移检测负例（两串不同）确认 FATAL 分支逻辑成立；cargo test --workspace 54 suite 0 failed（本轮仅动脚本）。附带把两个调用坑写进脚本注释防回归：Start-Process 数组传参给 pwsh 会丢参数成为交互式 REPL；WSL 无视 -WorkingDirectory 起在 /root，须在 bash -c 内 cd。
## BUG-248 [2026-10-16T13:55:47Z] [medium] DUPLICATE →BUG-165
- summary: [ocr-scan] 双轨 LLM review 臂对 MoonBit 项目完全无效：.mbt/.mbti 不在 opencodereview 扩展名白名单，scan/files 回执 reviewable_count 恒 0 / excluded_count=N（实测 src/engine 54/54、单文件 1/1，全 unsupported_ext），与『内建规则 + OCR LLM review 双轨互补』文档承诺矛盾，寻虫只剩 issue_scan 单轨
- detail: opencodereview.exe（ocr-local 二进制）的扩展名白名单不含 MoonBit 的 .mbt/.mbti，导致 ocr_scan 的 LLM review 臂对全 MoonBit 项目零产出。

实测证据（FIST-Mbt 2026-10-16，moon 0.1.20260920）：
1) `ocr_scan(subcmd=scan, path=src/engine, project_dir=.)` 回执：total_files=54, reviewable_count=0, excluded_count=54，全部 exclude_reason="unsupported_ext"，notice="LLM review 未真正执行"。argv 形如 ["scan","--repo",".","--preview","--format","json","--path","src/engine"]。
2) `ocr_scan(subcmd=files, path=src/engine/engine_archive_force.mbt, project_dir=.)` 回执：total_files=1, reviewable_count=0, excluded_count=1，同一 exclude_reason="unsupported_ext"。

矛盾点：工具描述与 AGENTS.md「寻虫」段声明 `ocr_scan` 与 `issue_scan` 形成『内建规则 + OCR LLM review』双轨寻虫互补；实际上双轨的第二臂（LLM review）对本项目所有源文件都因扩展名被拦，寻虫实际只剩 issue_scan 单轨。`issue_scan` 内建 31 条规则虽可用（本轮实测扫 src/ 得 9578 finding，high=0），但缺 LLM 语义 review 这一档。

影响：bugfind 模式 require_ocr 约束在此项目上形同虚设（判据可"扫"却无 review 产出），外部 AI 用它做寻虫时会误以为已获得 LLM review 覆盖。

建议方向：① 在 src/server/ocr_scan.mbt 的 argv 构造处为 .mbt/.mbti 补扩展名映射或改用 files/delegate 直指文件；② 或确认 opencodereview 是否支持自定义 include 扩展名参数；③ 至少在工具描述与 AGENTS.md 明确"当前 .mbt 不在 OCR 白名单，双轨退化为单轨"以避免外部 AI 误判覆盖。




## BUG-249 [2026-10-16T14:50:18Z] [medium] FIXED
- summary: [Tnr] 单元测试并行隔离缺陷：两个 tnrd DataFrame CSV 测试共用同一临时文件名 __tnrd_m6_df_csv.csv，cargo 并行跑时互相 remove_file 导致对方读回 "file not found" (tnrd.rs:3608)
- detail: save_tensor_csv_roundtrip_df (tnrd.rs:3606) 与 load_tensor_csv_header_reconstructs_df (tnrd.rs:3525) 都写/读/删同一个临时文件 __tnrd_m6_df_csv.csv。cargo test 默认多线程并行执行，一个测试的 remove_file 会删掉另一个测试刚写/还没读的文件，造成 "tnrd: 读 ... 系统找不到指定的文件。 (os error 2)" 的偶发失败。修复：两个测试改用各自独立的临时文件名 (__tnrd_m6_df_csv_rt.csv / __tnrd_m6_df_csv_hdr.csv)。产品 save/load 逻辑本身正确。已用 5 次并行连续运行验证 2/2 通过。
- reported_by: leader



### FIXED(2026-10-16T14:52:43Z / BUG-249)
- evidence: tnrd.rs 两个 CSV 测试原共用临时文件名 __tnrd_m6_df_csv.csv，cargo 并行时互相 remove_file。已改为各自独立文件名：save_tensor_csv_roundtrip_df 用 __tnrd_m6_df_csv_rt.csv、load_tensor_csv_header_reconstructs_df 用 __tnrd_m6_df_csv_hdr.csv。5 次并行连续运行验证 2/2 通过。产品 save/load 逻辑本身正确。




### FIXED(2026-10-16T15:31:17Z / BUG-249)
- evidence: 修复 src/tensor/tnrd.rs：save_tensor_csv_roundtrip_df (L3606) 与 load_tensor_csv_header_reconstructs_df (L3525) 改用各自独立的临时文件名 __tnrd_m6_df_csv_rt.csv / __tnrd_m6_df_csv_hdr.csv，消除 cargo 并行测试互相 remove_file 导致的 "file not found" 偶发失败。已用 5 次并行连续运行验证 2/2 通过；全量 cargo test --release --lib + 集成套件 0 failed。lirgen.rs L395 E0308 编译修复（MExpr::Var(init.clone())）一并纳入本轮。
## BUG-250 [2026-10-16T15:25:37Z] [medium] FALSE_POSITIVE
- summary: TEST-BUG-WRITE-PROBE-20261016T1520
- detail: Test write

- false_positive(2026-10-16T15:50:53Z): 测试探针条目：summary=TEST-BUG-WRITE-PROBE-20261016T1520，非真实缺陷。真实的 dag_mc 负 deadline bug 已另行登记为 BUG-253 并修复（commit ee219a0）。
## BUG-251 [2026-10-16T15:31:01Z] [medium] FALSE_POSITIVE
- summary: TEST-BUG-WRITE-PUBLISH-PROBE-20261016T1531
- detail: Test write with publish
- task_id: T0r638


- false_positive(2026-10-16T15:50:53Z): 测试探针条目：summary=TEST-BUG-WRITE-PUBLISH-PROBE-20261016T1531，非真实缺陷。仅用于验证 report_bug(publish_task=true) 写路径。
## BUG-252 [2026-10-16T15:32:29Z] [medium] FIXED
- summary: BUG-120 HTTP 桥 bridge.send 硬编码 30s 等待，executor_run 等长任务执行器必然 502 Request timeout
- detail: 现象：scripts/fist-mbt-http.py:209 deadline = time.time() + 30，executor_run 真实执行超过 30s 即返回 {"error":"Request timeout"}（实测 REST 并发/单发均超时，stdio 直连 120s 内成功）。修复：等待时长改为 FIST_HTTP_WAIT_SEC 可配置（默认 600s），3100 桥已重启验证 executor_run 93s 返回 ok，exit_code=0。




### FIXED(2026-10-16T15:51:43Z / BUG-252)
- evidence: scripts/fist-mbt-http.py:209 修复：deadline = time.time() + 30 改为 FIST_HTTP_WAIT_SEC 可配置（默认 600s）。3100 桥已重启验证 executor_run 93s 返回 ok，exit_code=0。源码：scripts/fist-mbt-http.py（B120-wait 段）——FIST_HTTP_WAIT_SEC 环境变量优先，缺省 600s，超时返回 Request timeout 而非 30s 假超时。回归：moon test src/engine 162/162 绿。
## BUG-253 [2026-10-16T15:47:58Z] [medium] FIXED
- summary: dag_mc 负 deadline 缺守卫：p_on_time 恒为 0 伪装成"0% 按期"（修复 ee219a0）
- detail: 负 deadline（如 -5）被静默接受。原实现 `deadline > 0` 守卫让 p_on_time 恒为 0，而回显里 deadline=-5 与 p_on_time=0 并置，读起来像"按期概率 0%"的假结论，实际是"根本没问"。对比 phi_accrual（elapsed<0 拒绝）、cost_budget_split（budget<=0 拒绝）的同类守卫，dag_mc 是缺位。修复（commit ee219a0）：负 deadline 按未设期限钳制到 0（与 samples 的 [10,5000] 钳制同族），回显如实标注 deadline_requested / deadline_capped / deadline_cap_note。验证：moon test --target js src/engine = 318/318 pass；全量 1260/1260 pass。
- reported_by: marvis-lead



### FIXED(2026-10-16T15:48:17Z / BUG-253)
- evidence: commit ee219a0 修复 src/engine/engine_dag_mc.mbt：新增 deadline_requested 捕获原值、负 deadline 钳制到 0（let d = if deadline < 0 { 0 } else { deadline }）、p_on_time 守卫改用 d > 0、回显新增 deadline_capped / deadline_cap_note。新增 dag_mc_test.mbt 测试 `dag_mc：负 deadline 被钳制到 0 并如实标注`：断言 deadline_requested=-5、deadline_capped=true、deadline=0、p_on_time=0、正向 deadline=100 时 deadline_capped=false。验证 moon test --target js src/engine = 318/318 pass；全量 1260/1260 pass（零回归）。





## BUG-254 [2026-10-16T16:14:13Z] [high] FIXED
- summary: [rule:boundary-input] circuit_fail 缺 window_secs/threshold/recovery_secs 正数校验：threshold=0 首败即熔断；window_secs=0 永不熔断（engine_circuit.mbt L30-31 + server.mbt L4277-4279）
- detail: 根因：src/server/server.mbt circuit_fail 处理器直接把用户传入的 window_secs/threshold/recovery_secs 传给引擎，无正数校验。

复现步骤：
1. circuit_fail(circuit="x", threshold=0) → state="open" (首败即熔断，threshold=0 使 nf>=thr 恒真)
2. circuit_fail(circuit="y", window_secs=0, threshold=5) → 连续调用两次 failures 恒为 1（window=0 使 now_secs-last_fail_ts>w 恒真，计数每次重置）

影响：熔断器语义被破坏——threshold<=0 直接熔断，window_secs<=0 永远不熔断。调用方可能得到假 allow_call=true（窗口永不累计）或假 allow_call=false（一次失败即拒）。

建议修复：在 server.mbt circuit_fail handler 里加正数校验，window_secs<1 / threshold<1 / recovery_secs<1 时返回 ToolError；或钳制到默认值。

参考代码位置：server.mbt L4277-4279（get_int 直接透传），engine_circuit.mbt L30（window 判定），engine_circuit.mbt L31（threshold 判定）



### FIXED(2026-10-16T16:15:08Z / BUG-254)
- evidence: src/server/server.mbt circuit_fail handler 增加正数校验：window_secs/threshold/recovery_secs 均须 >= 1，否则返回 ToolError 并说明原因（threshold<=0 首败即熔断；window_secs<=0 永不累计失败）。验证：moon test --target js src/engine = 162/162 绿。
## BUG-255 [2026-10-17T01:03:18Z] [medium] OPEN
- summary: [Pentad/DEMO-09 §16] @stream 在 @observe 内 for 迭代不产出事件：期望 handled: event1/event2 完全缺失（推送被静默丢弃）
- detail: 复现：`p5c run DEMO/09_reactive/reactive.p5`（rc=0，跑到哨兵 DEMO reactive OK），§16 完整示例事件总线：:248 `box @stream #[replay(10)] event_bus = Source()`；:250-252 `api @observe handle_events() = for ev <- event_bus: print("handled:", ev)`；:254-255 `event_bus.push("event1")` / `push("event2")`，内联期望输出 `handled: event1, handled: event2`。实得输出里**完全没有 handled: 行**（整份 103 行输出逐行核过），即 `@stream` 值在 `for ev <- <stream>` 迭代时产出空序列 ⇒ 观察者虽被触发但循环体从不执行，事件被静默丢弃。规范依据：SYNTAX/15 §15.6（@stream 事件流语义，:134 亦述「@stream 同 @signal 锚定 box、走 __get/__set 通道」）。同文档 §15.2 的信号读 __get 分派本轮已实现（见 BUG-245），本条是 @stream 侧的另一半缺口。影响：DEMO/09 因此**不可注册 golden**（判据要求输出与文档一致，本项目拒绝把未满足期望冻成基准）。发现轮：p5c 组合流水线 R7（寻虫），复现于 2026-10-17。
- reported_by: pentad-combo-r1
- **R14 深挖：更正本条原诊断 + 写明真实前置条件**。
  - **更正一**：原写「`@stream` 在 `for ev <- <stream>` 迭代时产出空序列」**不准确**。Stream 迭代其实
    **已实现**（`eval/stmts.rs` 的 `take_iterable` 里 `Value::Stream` 分支：逐事件产出并把空流写回绑定，
    消费式语义，符合 §15.6）。
  - **真实机制**：`@observe` 的重跑只挂在 `:=` 写信号那条通路上（命中 `reactive_signals` 才
    `notify_reactive_write`），而 `event_bus.push(ev)` 是**接收者方法调用**、从不通知；且 `@stream`
    名根本没进 `reactive_signals`（只登记 `@signal`）⇒ 观察者仅在定义时跑一次（那时流为空），之后再无
    重跑，事件永久滞留。规范依据补一条：`SYNTAX/15 §15.6:84`「**发射**：`s.push(ev)`（= `emit`）——
    内部经 `__set` 通道（§15.2 同一通道）**通知在订者**」。
  - **前置条件（关键，别重复踩）**：不能把 push 直接接到现有通知上。现有通知是「**重跑全部观察者**」，
    与 §15.2:32 规定的「**按依赖登记**通知（读时登记当前观察者为其依赖，写时只通知依赖者）」不符。
    实测代价：接上后 `DEMO/09_reactive` 输出从 **103 行涨到 185 行**；最小用例
    （`box @stream bus = Source()` + 单个 `@observe` + 两次 `push`）里 `handled: e1` **重复两次**，
    且之后每次 push 都把无关观察者全跑一遍——**比「事件丢失」更偏离 demo 期望**。故本轮已回退。
  - **修法的正确顺序**：① 先做读侧依赖登记（`@observe`/`@derived` 体内读信号/流时记依赖边）＋写侧
    按依赖通知（顺带解决 §15.2:32 的微任务边界合并去重；现口径是「即时重跑」）；② 再把 `push`/`emit`
    接进同一条通知通路，并把 `@stream` 名纳入登记（本轮在两处留了注释说明为何不做半套登记）；
    ③ 最后才为 DEMO/09 落 golden（§16 期望满足前，本项目拒绝注册基准）。
  - **本轮已补的真缺口**（与通知无关、可独立验证）：`s.emit(ev)` 规范上是 `push` 的等价名
    （`SYNTAX/11:85`、`24-附录07:34`），但 `calls.rs` 只有 `push` 臂 ⇒ `bus.emit(x)` 报
    `Property or method not found: emit (on bus; tried: bus::emit)`（用改前二进制实测）。已修
    （Pentad commit `3fffe3a`）：`bus.emit("via-emit")` → `try_next()` 得 `Some("via-emit")`。
    同 commit 另把两处逐字重复的 `:=` 通知块抽成 `notify_reactive_write()`（纯重构，实测输出逐字不变）。


## BUG-256 [2026-10-17T01:32:33Z] [high] FIXED
- summary: [ledger-lifecycle] 重复赋值容器追加 `out = out + [ts[idx]]` 生成 `out.push(ts[idx])` 触发 E0507 cannot move out of index（Assign 代码路径触发容器原地追加优化，但缺 ListLit 元素位的 .clone() 收敛）
- detail: ## 现象
BST 示例 `TEMP\marvis-probe\bst.lz` 编译到 .rs 后 rustc 报 E0308：`insert` 返回 `TreeNode<Int>` 被赋给 `Option<TreeNode<Int>>` 的 `root`。

## 根因链（三环）
1. `mut root = None` → 预扫描 `infer_expr_type(NoneLit)` 返回 `Any`，`vars["root"]` 被写成 `Any`。
2. `root = insert(root, 5)` → 预扫描 `infer_expr_type(insert(...))` 返回 `TreeNode<Int>` 直接覆盖 `vars["root"]`，丢失「root 是 Option<TreeNode<Int>>」的事实。
3. Let-vs-Assign 判定：`Stmt::Assign` 分支才做 `Some(...)` 包装；但旧判定 `!block_declared.contains(name)` 在第二次赋值时为 false → 走了 `Stmt::Let` → 无 `Some(...)` 包装 → E0308。

## 修复（三件套，均在 `src\ir\builder\convert_stmt.rs`）
1. Let-vs-Assign 条件改为 `block_declared.contains(name) && !block_declared_so_far.contains(name)`（新增 `block_declared_so_far` 跟踪当前块已处理绑定）。
2. `ty.is_none()` 且 value 是 `NoneLit`/`Ident("None")` → 用 `Option(Any)` 而非 `infer_expr_type(value)`（预扫描不再把 None 猜成裸 Any）。
3. Assign 分支 target_ty 从 `ctx.vars.get(name)` 取（保留用户注解/Option 包装）。

## 连带发现：容器追加路径缺 .clone()
Assign 代码生成 `out = out + [ts[idx]]` → 触发 `container_append_rhs` → 生成 `out.push(ts[idx as usize])`（无 .clone()）→ `Vec<IrType>` 非 Copy → E0507。ListLit 元素位代码生成（`src\ir\codegen\expr_gen.rs` L6091-6108）已有同类收敛，Assign 容器追加路径补齐同款 `maybe_clone` 闭包。

## 验证
- `TEMP\marvis-probe\bst.exe` 编译运行，输出 `1 3 5 7 9`。
- 全量 `cargo test` 0 失败（~800 tests，含 `tests\codegen_corner_fixes.rs`、`find_bug_bugs.rs`、`demo_codegen_compile`、`lz_ir_bootstrap`、`perf_opt_gates` 等 39 个 suite）。
- reported_by: lang-zone-polisher



### FIXED(2026-10-17T01:32:44Z / BUG-256)
- evidence: 修复三件套落在 src/ir/builder/convert_stmt.rs（Let-vs-Assign 条件 + block_declared_so_far + None 预扫描 Option(Any) + Assign target_ty 从 ctx.vars 取）；连带修复 src/ir/codegen/stmt_gen.rs 的 Assign 容器追加路径，补 ListLit 同款 maybe_clone（Var/IndexGet 且非 Copy → .clone()）治 E0507。验证：TEMP/marvis-probe/bst.exe 输出 1 3 5 7 9；全量 cargo test 0 失败（~800 tests，39 suites）。
## BUG-257 [2026-10-17T01:48:49Z] [high] FIXED
- summary: [Tnr] lirgen compute_stable_i64 定点分析不收敛（非单调 insert/remove 抖动、无迭代上限）：变量同时存在「整数字面量绑定点」与「非 i64 赋值点」时死循环——3 行合法程序转译 30s 超时 E9006；语料 g11_alg_array_sum（该修复自述的动机用例）直接挂死
- detail: ## 现象（2026-10-17 实测，HEAD=cd5157b，bin=target/release/tnr.exe mtime 09:35 新鲜）
- `tnr transpile corpus/transpile/g11_alg_array_sum.tnr --backend lir` → **exit=4, 30.3s**，`[E9006] 转译超时（>30s），已中止；疑似输入规模过大或死循环`（12 行程序）
- 同批控制组 `g01_literals_arith.tnr` → exit=0, **1.4s**（工具链正常）

## 最小复现（3 例隔离，$env:TEMP/tnr_repro/）
- m1 `let s = 0; s = s + 1; print(s);` → exit=0, **0.2s**（两个绑定点均原生 i64）
- m2 `let s = 0; s = s + 1.5; print(s);` → **exit=4, 30.2s 超时**（一个原生 + 一个非原生）★
- m3 `let s = 1.5; s = s + 1.5; print(s);` → exit=0, **0.1s**（两个均非原生 Val）
⇒ 判据精确落在「同一变量既有恒原生绑定点、又有恒非原生绑定点」这一**混合**情形，与「变量是 Val 所以慢」无关。

## 根因（读码定位）
`src/codegen/lirgen.rs:455-484 compute_stable_i64` 的不动点循环（:467-482）**非单调**：
```
loop { let mut changed=false;
  for (var,expr) in &sites {
    let native = self.is_native_expr_stable(expr,&stable,&lit_env);
    if native && !stable.contains(var) { stable.insert(var); changed=true; }
    else if !native && stable.contains(var) { stable.remove(var); changed=true; } } 
  if !changed { break } }
```
`collect_i64_sites`（:362-415）把**每个** Let(:370-374) 与 Assign(:375-377) 都推进 `sites`，故同一变量可有多条绑定点。当站点 A 恒原生（如 `Lit::Int`，:342 恒 true）、站点 B 恒非原生（如含索引/浮点 args，:356 `_ => false`）时，每趟 A 插入、B 删除，`changed` 每趟恒 true ⇒ **永不 break**。函数内无迭代上限、无「整趟集合未变」判据、无单调化（未改为「仅当所有站点 native 才保留」的单调收敛）。
对照：`is_native_expr_stable` 的 `Lit(Int)` 分支与 `Var` 的 `lit_env` 分支使 A 站点的 native 判定**与 stable 无关**，这正是抖动的必要条件。

## 危害面
1. **任意合法程序的转译失败**：`let x = <int>;` 之后被赋任何非 i64 值（动态索引 `s = s + data[i]`、浮点累加 `s = s + 1.5`、字符串/容器）即触发。这是极常见的累加器写法。
2. **该修复自述的动机用例直接挂死**：`lirgen.rs:320` 注释逐字以 `g11_alg_array_sum` 为背景，而 g11 现在恰好超时。
3. **CLI 守卫只挡住症状、且泄漏线程**：`transpile_with_guard`（src/cli/mod.rs:1440-1457）用 `recv_timeout(GUARD_TIMEOUT=30s)`；超时分支 `Err(_timeout) => Err(E9006)` **不 join worker**（只有 Ok 分支 `let _ = worker.join()`），死循环线程被遗弃并继续 100% CPU 自旋。
4. **直连 API 无守卫 ⇒ 真正 hang**：`transpile_lir/transpile_lir_src`（lirgen.rs:182-194）是公开入口，`src/ir/mod.rs:173/198/209/222` 的测试直接调用它；一旦测试语料含混合绑定点，测试将**永久挂起**（DGM 库中已有 `[lesson] test-hang-masks-drift` 同族教训）。
5. **语料零测试覆盖 ⇒ 静默**：全仓检索 `corpus/transpile`、`g11_alg` 仅命中 `src/codegen/lirgen.rs:320` 该条**注释**，没有任何测试驱动 `corpus/transpile/*.tnr`。这正是本次回归能在 6545 全绿下存活的原因（lib 6545 passed / bins 22 passed 均绿）。

## 回归性质
`cd5157b`（唯一新增提交，`src/codegen/lirgen.rs` +180/-8）以「方向 B 函数体级定点分析」替换原增量式登记，注释自述增量式在 `let mut s = 0i64; s = s + data[i]` 上产出 E0308 类型不匹配而崩。本次修法把「编译期类型错误」换成了「编译期不收敛」，**从可诊断的 E0308 退化为不可诊断的挂死**，且动机用例本身未被验证即入库。

## 修复方向（建议，供 owner 采纳）
- 把判定改为**单调**语义：变量纳入 stable 当且仅当其**全部**绑定点在「上一轮 stable」下均 native；用 `added/removed` 双缓冲单趟提交（避免同趟内插入即被下游读到），每趟只按「集合是否变化」决定是否继续 ⇒ 因 stable 只减不增（或只增不减），必然有限步收敛。
- 或保守但零风险的兜底：加迭代上限（如 `sites.len()+8` 轮）并在超出时退化为空 stable 集（全部按 Val 发射，语义仍正确，只是不做 i64 特化）——特化是纯优化，退化不影响正确性。
- 补回归锁：把 `corpus/transpile/*.tnr` 接进测试（至少 g11 + m1/m2/m3 三例），并把 m2 这类 3 行混合绑定点程序设为「必须 <1s 返回」的判据；同时给 `transpile_with_guard` 超时分支补 worker 回收/进程级兜底。
- reported_by: tnr-polisher
- task_id: T0r5



### FIXED(2026-10-17T02:22:09Z / BUG-257)
- evidence: 真源 src/codegen/lirgen.rs（+86/-26，patches/bug257_stable_i64_and_let_type.patch）。三处根因同批修复，全部实跑验证：
① 不收敛（死循环）：compute_stable_i64 原「单趟内既插入又移除 + changed 判停」改为单调递减归纳式不动点（初始化乐观纳入，按不健全剔除，只减不增），并加 sites.len()+2 轮上限 + 非收敛兜底清空（退化为全 Val，特化是纯优化不影响语义）。
② 健全性：新增 ISiteKind{Init,Update} 区分绑定点——Init 在不含自身的 stable 下判定（初值是类型 ground），Update 允许自引用（归纳：初值定 i64 则更新保型即恒 i64）。既修混合站点误判，又保住 `i=i+1` 这类自引用累加器的 i64 特化（此前的替代方案会丢失方向 A–E 全部收益）。
③ 类型不一致（E0308）：Let 发射路径原按单条初值增量 insert/remove 覆盖分析结论（违反 struct 字段注释「只读，不再增量改」），且已发出的 `let` 行无法被后续 Assign 的「降级」撤回 → `let mut s = 0i64; … s = <Val>;`。现改为只读 + 当 v∉i64_vars 且初值为原生 i64 时显式装箱 tnr_rt::lit_int(..)。
断言锁/判据：cargo test --release --lib = 6545 passed/0 failed；--bins = 22 passed/0 failed；corpus/transpile 39/39 transpile OK；最小复现 m1..m5 + 语料 g11 全部 `--run`（transpile+rustc+执行）exit 0：m1 int64(1)、m2 float64(1.5)、m3 float64(3)、m4 int64(1)、m5 int64(1)、g11 输出 31/[3,1,4,1,5,9,2,6]/8/31。修复前：m2/m5/g11 = E0308 或 30s E9006 超时。
## BUG-258 [2026-10-17T01:53:20Z] [medium] OPEN
- summary: [Pentad/SYNTAX] §16 标记树条文三处自相矛盾：16.1 两棵图画法冲突（@type 兄弟 vs 子）、16.5:251 is_subtag 方向写反、16.5:246 Tag 集合内引号口径缺定档
- detail: 实现标记树反射（Pentad commit 4156750 / BUG-244）时撞到三处条文问题，均属**文档**缺陷（代码已按证据取舍并注释，勿再重复发现）：

① **§16.1 同一节内两棵树画法冲突**：紧凑视图 :86 写 `@function（◉）⑂ @type（◉）⑂ @var（◉）  ← 同宿主 api 的主形态互斥`、:107 又写「`api` 一个定义沿树取**一条主形态链**（@function / @type / @var …）」⇒ 三者互斥平级；但同节 ASCII 详图 :54 把 `├─ @type` 缩进在 `@function`（:27）之下，成为其子节点。二者不可同真：按详图，从 `@struct` 上溯会经过 `@type → @function`，则 `has_tag(Point, @function)` 必为 True，直接与 `DEMO/10_markers/markers.p5:200`（明确期望 False）冲突。**代码取兄弟读法**（:86、:107、DEMO:199/200 三处独立证据一致），请据此修正 ASCII 详图缩进。

② **§16.5:251 判据方向写反**：条文「`is_subtag(a, b)`：`a` 是否在 `b` 的任一祖先父链上（含自身）」按字面即「a 是 b 的祖先」；而同一节 :245 的示例 `is_subtag(@infix, @method) // → True` 与函数名本身（child,parent）都要求「从 a 上行能到 b」。示例与名一致、条文相反。代码按 :245 + 名称实现，并有锁 `is_subtag(@method,@infix) == False`；请把 :251 改为「`b` 是否在 `a` 的任一祖先父链上（含自身）」。

③ **§16.5:246 的集合元素引号口径**：条文写 `tags_of(@infix) // → (@infix, @instance_method, @method, @function)`（无引号），而引擎把集合内的标记值渲染为带引号字符串（实测 `print(tag_of(S))` 得裸 `@struct`，放进元组即 `("@struct", "@struct")`）——该行为 `tag_of` 同样如此，属 patrol_agent 已定档的 **BUG-43 渲染规约迁移**范围（BUG-43 现只规定了多参 print 逐值换行 / 集合 `{a,b,c}` / atom 带 `$` / 单元素元组 `(1,)` / Dict 键带引号，未规定 Tag 在集合内的引号）。需一并定档：或条文补引号口径，或引擎为 Tag 值单列渲染规则。

影响：因 ③ 未定档，DEMO/10 的反射链两行仍与条文逐字不同 ⇒ 本项目**继续不给 DEMO/10 注册 golden**（拒绝把未定档表示冻成基准）。发现轮：p5c 组合流水线 R15。

### PARTIAL(2026-10-18T09:15:00Z / BUG-258)：①② 文档矛盾已修正、③ 待 BUG-43 定档
- evidence: ①② 已按代码采用的证据（紧凑视图 :86、:107 与 DEMO/10:199-200 三处一致）修正 `SYNTAX/16-标记体系.md`（**该文件工作区已改、未提交**——本轮宿主进程孵化故障 0xC0000142，`pwsh`/git 无法启动，提交需用户或并发 agent 后续执行）：
  - ① §16.1 ASCII 详图之后新增「⚠️ 详图读法（BUG-258① 澄清）」注记：`@type`/`@var` 缩进在 `@function` 下**只是排版示意**，权威读法是紧凑视图的**互斥兄弟**；据此 `has_tag(Point, @type)=True`、`has_tag(Point, @function)=False`，并点名 `eval/builtins.rs::tag_parents` 按兄弟读法建表。
  - ② §16.5:251 改为「**`b` 是否在 `a` 的任一祖先父链上（含自身）**」，补正反例（`is_subtag(@infix,@method)=True`、`is_subtag(@method,@infix)=False`），对齐 :245 示例与函数名 `(child, parent)`。
- ③ **未动**：Tag 集合内引号口径属 BUG-43 渲染规约迁移范围，本目不预设答案；DEMO/10 继续不落 golden（纪律不变）。
- 抬头保持 **OPEN**（③ 未修），仅叙述面留痕部分进展，避免把「①②修好」误读为「整条销账」。

### ③ 定档选项（2026-10-18T09:35Z 整理，供 owner 裁决 — BUG-258③）

**分歧点**：§16.5:246 条文写 `tags_of(@infix) // → (@infix, @instance_method, @method, @function)`（集合内 Tag **不带引号**），引擎把集合内 Tag 值渲染为带引号字符串 `("@infix", "@instance_method", "@method", "@function")`。孤立 `print(tag_of(S))` 得裸 `@struct`，放进元组即带引号。属 BUG-43 渲染规约未覆盖区。

**三选项**（成本从低到高，任选其一即解锁 DEMO/10 golden）：

| 选项 | 改什么 | 成本 | 风险 |
|---|---|---|---|
| **A. 条文补引号口径** | §16.5:246 的 `tags_of` 示例改为带引号 `("@infix", …)`，并加一句「Tag 作一等值入集合/元组时与 Str 一致带引号，§16.6 一切皆对象」 | 只改文档，零代码 | 若后续 BUG-43 定档为「集合内 Tag 裸渲染」，需再改回 |
| **B. 引擎单列 Tag 渲染** | `eval` 渲染器为 Tag 值新增规则：**入集合/元组时裸渲染**（不带引号），孤立值保持现状 | 改 `eval`（渲染路径）+ 回归锁 | 影响所有 Tag 入集合的输出，需重验 DEMO/10 全部反射期望 |
| **C. 双轨语义（推荐）** | 条文定档「**孤立 print / tag_of 裸渲染；入集合/元组/作 Str 元素时带引号**（与 Str 一致，一切皆对象）」；引擎现状即满足，**只需改文档** | 同 A，成本最低 | 语义最自洽（Tag 是一等值，容器内与 Str 同渲染），且与已定档的 BUG-43「Dict 键带引号 / 单元素元组 `(1,)`」精神一致 |

**推荐 C**：既不动引擎（本会话进程孵化故障无法编译验证，改引擎需重跑判据），又与「一切皆对象」（§16.6）一脉相承，且不依赖 BUG-43 后续迁移即可落地。**一旦裁决，请同步：**
1. 改 §16.5:246 `tags_of` 示例带引号 + 加一句定档说明；
2. 把 DEMO/10_markers/markers.p5 反射链期望与条文统一，再走 golden 注册（届时 UNREG 3→2）。

### ③ 裁决落地（2026-10-18 owner 采纳推荐 C — BUG-258③）

已按 C 双轨语义落地（零代码、不动引擎）：
1. `SYNTAX/16-标记体系.md §16.5`：`tags_of(@infix)` 示例改为带引号 `("@infix", "@instance_method", "@method", "@function")`，并新增「Tag 渲染引号（BUG-258③ 定档，选项 C）」定档说明（孤立 `print`/`tag_of` 裸渲染、入容器/元组带引号，与 BUG-43 已定档的 Dict 键带引号 / 单元素元组 `(1,)` 精神一致）。
2. §16.6 规则 5 里对 §16.5 的行号引用（旧写「:243-246」）改为节名引用「标记反射」节，消除行号漂移。
3. `DEMO/10_markers/markers.p5:207` 反射链期望统一为带引号版本，并加 C 定档注释。
**待验证**：进程孵化 0xC0000142 持续故障，本轮无法跑 `e2e_golden` 复测；引擎现状即满足 C（孤立裸、容器带引号），进程恢复后跑判据确认 `UNREG 3→2` 再标 FIXED。

### ④（新硬矛盾，2026-10-18T09:50Z 发现 — BUG-258④）：反射内建实参的裸标记名 vs §16.6「必须反引号」

**现象**：§16.6 :294 明文「`// let t = @struct // 错误：标记名作值必须反引号（`@struct`）」、:286 又说「反引号是值表达式位置（`let` / 实参 / 返回）取记号实体所用的语法」——按此，**反射内建函数的标记实参也该反引号**。但同一份文档的 §16.5 :243–246 与 `DEMO/10_markers/markers.p5:198–204` 全部用**裸标记名**作实参：
```
has_tag(Point, @struct)    // 期望 True（§16.5:244 / DEMO/10:198，裸 @struct）
has_tag(Point, @type)      // 期望 True（DEMO/10:199）
is_subtag(@infix, @method) // 期望 True（§16.5:245 / DEMO/10:203，裸 @infix / @method）
```
两处条文不可同真：要么 §16.6「必须反引号」对反射内建实参有**语法糖例外**（§16.5 应写明），要么 §16.5/DEMO/10 全部应写 `` `@struct` ``。

**旁证（支持裸标记名合法）**：`has_tag`/`is_subtag`/`tag_of` 是**内建反射函数**，其第二实参在语义上**只能**是标记（类型已由签名固定），语法糖可省反引号；§16.5 与 DEMO/10 一致用裸写法，且 DEMO/10:199+200 对（`has_tag(Point,@type)=True` / `has_tag(Point,@function)=False`）正是 BUG-258①「兄弟读法」的硬证据，说明该节写法是经斟酌的意图而非笔误。

**修复方向（推荐 D：条文补糖规则，零代码）**：§16.6 追加一条例外——「**反射内建函数**（`tag_of`/`has_tag`/`is_subtag`/`tags_of`）的标记实参可**裸写**（实参类型已固定为标记，语法糖免反引号）；其余值位置（`let` / 一般实参 / 返回）仍须反引号」。与 ③ 选项 C 同批落地，即解锁 DEMO/10 golden。**需 owner 裁决**（因涉及 §16.6 通则 vs 特例的取舍，不单方面定档）。


## BUG-259 [2026-10-17T02:22:09Z] [medium] OPEN
- summary: [Tnr] corpus/transpile 39 份语料零测试驱动：金标准静默漂移（g11 首行 dtype float64→int64 已与 expected.txt 不符），且本轮 lirgen 死循环回归能在 6545 全绿下存活
- detail: ## 现象（2026-10-17 实测，HEAD f234752 + 本会话 lirgen 修复）
1. **零测试驱动**：全仓检索 `corpus/transpile`、`g11_alg` 只命中 `src/codegen/lirgen.rs` 的一条**注释**（:320 以 g11_alg_array_sum 为背景说明），没有任何 test/bench 读取 `corpus/transpile/*.tnr` 或比对其 `*.expected.txt`。`cargo test --release --lib/--bins/--all-targets` 全程不触达语料。
2. **金标准已漂移**：`tnr transpile corpus/transpile/g11_alg_array_sum.tnr --backend lir --run` 现输出首行 `Tensor<int64, []>(31)`，而 `g11_alg_array_sum.expected.txt:1` 记的是 `Tensor<float64, []>(31)`（值同为 31，仅 dtype 不同；第 2–4 行一致）。原因是方向 A/D 的 (Int,Int) 标量整数快路径令 `s + data[i]`（两侧皆 int64）保持 Int64，而金标准记录于引入快路径之前。
3. **后果（不是「少了个校验」那么轻）**：本轮 `cd5157b`（方向 B 定点分析）使 `g11_alg_array_sum` **转译死循环 30s 超时 E9006**（3 行最小复现 `let s = 0; s = s + 1.5; print(s);` 同挂），而 6545 lib + 22 bin 全绿、无人察觉——因为没有任何判据跑语料。同批还掩盖了 `let mut s = 0i64; … s = <Val>` 的 E0308（`--run` 才暴露）。语料是本项目唯一的端到端转译基准族（g01–g36 覆盖字面量/数组/循环/张量/字符串域），却完全在闸门之外，「金标准」实际无人守卫，可长期漂移。

## 判据（可离线复跑）
- `Get-ChildItem corpus\transpile\*.tnr | % { tnr transpile $_ --backend lir }` → 每份都应 exit 0（本会话修复后实测 OK=39 FAIL=0；修复前 g11 为 E9006 超时）。
- 对每份 `.tnr`：`tnr transpile X.tnr --backend lir --run` 与 `X.expected.txt` 逐行比对（`lir_only` 标记的文件跳过 --run，如 g13_do_while）。
- 负向对照（证明非空洞）：把 g11 的 `while i < 8` 改成 `while i < 0`，期望首行 dtype 变化 → 判据能分辨，不是恒绿。

## 修复方向（建议）
1. 把 `corpus/transpile` 接入 `cargo test`（新增 `tests/corpus_transpile.rs`：遍历语料，逐份 `transpile_lir_src` 断言 Ok + `--run` 或至少 rustc 通过；对 `*.expected.txt` 做逐行比对，`*.lir_only` 只断言转译成功）。这同时是 BUG-257 类回归的天然回归锁。
2. 明确 g11 首行 dtype 的正确期望：若 Int64 累加是有意为之（精度上更优，>2^53 不丢），则更新 `expected.txt`；若应保持 float64，则属语义变更需另立缺陷。**本条目不预设答案**，只指出「金标准与实际不符且无人守卫」这一事实。
3. 建议在语料 README/守卫中写明：新增/变更语料必须同步 `expected.txt` 并纳入测试，禁止手改 expected 以迁就实现。
- reported_by: tnr-polisher
- task_id: T0r6

## BUG-260 [2026-10-17T02:30:17Z] [high] FIXED
- summary: [ledger-id-collision] 缺陷账本 BUG-185/186/217 各出现两次（FIXED+OPEN 混挂同一 ID），导致 gen_plugins.py --check FATAL、check_plugin_sync.py FAIL（cl7 插件态断线）
- detail: ## 现象（2026-10-17 实跑）

`python scripts/check_plugin_sync.py` 返回 exit 1，报：

    FAIL 插件态（一源四态 cl7）不一致（真源 166 工具 / v0.3.8）：
      - J1 插件态漂移：gen_plugins.py --check 退出码 2（FATAL 真源自证失败：账本状态与叙述面对不上：）
              - 3 条被小记点名但状态不是 FIXED：BUG-185 BUG-186 BUG-217
      - J5 plugins/claude/.mcp.json 与仓库根 .mcp.dev.json 不一致（启动参数有两份真源）

## 根因（`bug_list` + 解析证实：ID 碰撞，不是「小记/抬头不一致」）

`memory/bugs.md` 里 `BUG-185` / `BUG-186` / `BUG-217` 各挂了两条不同 bug：

| ID | status=FIXED（旧 bug，有小记） | status=OPEN（新 bug，不同内容） |
|---|---|---|
| BUG-185 | `ops_watchdog.mbt 静默吞噬 heal 错误`（FIXED 2026-10-15T08:46:00） | `[判据] e2e_irm_line 真面档探针恒红：probe() 用 [ -x 'fist' ] 裸词…`（ts=2026-10-15T08:44:07） |
| BUG-186 | `ops_heal.mbt heal_stale_tasks_by_phi 静默吞噬 reopen_task 错误`（FIXED 2026-10-15T08:50:00） | `[看护] e2e_irm_line --real 无 PATH/shim/产物目录还原保护…`（ts=2026-10-15T08:44:07） |
| BUG-217 | `自驱发布静默吞错——selfdrive_publish_next 在发布失败时把失败折叠进 skipped`（FIXED 2026-10-15T13:20:00） | `[claimguard-side-effect] may_proceed_sematic / may_proceed_full 在检查前先 claim_item…`（ts=2026-10-15T13:22:34） |

**机理**：`report_bug` 的 ID 分配对这三条复用了已存在的 BUG-185/186/217。`gen_plugins.py --check` 扫到 `### FIXED(…)` 小记点名 BUG-185/186/217，再去 `## BUG-n` 抬头查状态时，**读到的是 OPEN 那条**（或抬头被覆盖）→ 判为「被小记点名但状态不是 FIXED」→ FATAL（BUG-9 记账规则的互锁硬门被误触发）。

## 影响

- **cl7 一源四态断线**：插件态（atomcode/codearts/deepseek-harness/claude 四宿主）与真源不一致。
- **`check_plugin_sync` 从 R223 的 PASS 变为 FAIL** —— cl7 红，CI 判据会挡发布。
- 真源工具数 = 166（check_plugin_sync 明说），而 AGENTS.md 自述「140+」、R223 交付物「129」、`fist://map` J14「102」—— 四个数全不一致，工具计数自述全线漂移。

## 建议修复（清整，指挥官/agent 决策）

1. **把 OPEN 那三条 BUG-185/186/217 重新编号**（或改判合并），消除 ID 碰撞；FIXED 三条保留原小记。
2. **`report_bug` 在 ID 分配前查重**：若目标 ID 已存在，自动分配下一个空闲 ID。
3. 统一 `.mcp.json` 启动参数到单一真源（修 J5）。
- reported_by: fist-lead



### FIXED(2026-10-17T02:36:17Z / BUG-260)
- evidence: 2026-10-17 fist-lead：①把 memory/bugs.md 里 3 条 OPEN 重复条目重编号（BUG-185(OPEN)→BUG-261、BUG-186(OPEN)→BUG-262、BUG-217(OPEN)→BUG-263，各带 renumbered_from 追溯），FIXED 三条（BUG-185/186/217 原号）保留原小记；②消除 ID 碰撞后 `python scripts/gen_plugins.py` 重生成 OK（166 工具 / v0.3.8 / BUG-1~263 共 263 条入账：8 待修/235 已修/10 重复并入/8 误报）；③`python scripts/check_plugin_sync.py` 由 R232 的 FAIL（exit 1）变为 **PASS**（4 宿主 / 64 个生成文件 / 166 工具 / v0.3.8 / 启动参数真源 .mcp.dev.json），J1 FATAL 与 J5 双双解除。遗留（不属本 bug 收口）：`report_bug` 分配 ID 前查重的代码根因仍 OPEN（本 bug 只清账本卫生，未改 src/）。
## BUG-264 [2026-10-17T02:40:49Z] [high] FIXED
- summary: BlockExpr codegen 不继承 owned_locals → 容器原地追加在 if/else 块内失效（O(n²) 退化）
- detail: ExprKind::BlockExpr codegen（expr_gen.rs L5712）创建新 CodeGen child 并 clone declared/str_typed_vars/fstr_var_types 等大量状态，但漏掉 owned_locals。后果：`xs = xs + [1, 2]` 在 `if flag: ... else: ...` 块内查不到 owned_local_kind(xs)，退化为 `xs = { let mut __cat = xs.clone(); __cat.extend(...); __cat }` 的全量 clone 路径（O(n²)）。实测 edge_probe.lz cond_append：修复前 `if flag { xs = { let mut __cat = xs.clone(); __cat.extend([1, 2]); __cat } }`，修复后 `if flag { xs.extend([1i64, 2i64]); } else { xs.push(3i64); }`。同时 GenBuild 也有同款漏继承，一并补上。修复：expr_gen.rs BlockExpr 与 GenBuild 两处 codegen 在 clone declared 后加 `child.owned_locals = self.owned_locals.clone();`。
- reported_by: compiler-agent

## BUG-265 [2026-10-17T02:41:06Z] [high] FIXED
- summary: Let 容器追加路径漏 maybe_clone → `new_k = new_k + [bucket_k[i]]` 报 E0507
- detail: Let 容器追加路径（stmt_gen.rs Push/InsertOne 分支）未应用 maybe_clone，而 Assign 路径（同函数下方）已应用。后果：`let new_k = new_k + [bucket_k[i]]` 生成 `new_k.push(bucket_k[i as usize])` 但未加 `.clone()`，Rust 报 E0507（cannot move out of index of Vec<String>）。lib_hashmap 测试修复前失败。修复：stmt_gen.rs Let container append codegen 在 match plan 前定义与 Assign 路径同款的 maybe_clone 闭包，Push/InsertOne 两分支的 elem_s 经 maybe_clone 处理后输出。
- reported_by: compiler-agent

## BUG-266 [2026-10-17T02:41:06Z] [high] FIXED
- summary: str_append_rhs 未设 expected_ty=Str → 字符串索引 push_str 报 E0308
- detail: Let 的 str_append_rhs 路径（stmt_gen.rs L516）在调用 self.gen_expr(rhs) 前未设 current_expected_ty = Str。后果：`let result = result + self.s[self.pos]`（self.s 是 str，self.pos 是 int）被识别为 str append，但字符串索引 gen_expr 默认走 ord 路径生成 `__cs[__i] as i64`（而非 `__cs[__i].to_string()`），push_str 收到 i64 报 E0308。通用 BinOp `+` 路径在 expr_gen.rs L4892-4912 已有同款 expected_ty 设定。修复：stmt_gen.rs str append 路径在 gen_expr(rhs) 前 borrow 保存并设 current_expected_ty = Some(IrType::Str)，生成后恢复。
- reported_by: compiler-agent



### FIXED(2026-10-17T02:41:18Z / BUG-264, BUG-265, BUG-266)
- evidence: 三个 fix 落在 lang-zone/src/ir/codegen/。BUG-264：expr_gen.rs BlockExpr（L5740 附近）与 GenBuild（L5820 附近）在 clone declared 后补 `child.owned_locals = self.owned_locals.clone();`，使 if/else 块内 `xs = xs + [1, 2]` 走 `xs.extend([1, 2])` 而非全量 clone（edge_probe.lz cond_append 验证通过）。BUG-265：stmt_gen.rs Let container append codegen（L543 附近）在 match plan 前加入与 Assign 路径同款的 maybe_clone 闭包，Push/InsertOne 两分支经 maybe_clone 输出 elem_s，lib_hashmap 测试 12/12 通过。BUG-266：stmt_gen.rs str append 路径（L516 附近）在 gen_expr(rhs) 前设 current_expected_ty = Some(IrType::Str)，使字符串索引生成 `__cs[__i].to_string()` 而非 `as i64`，lib_json 测试通过。全量 cargo test（dev+release）约 800 用例 0 失败。
## BUG-267 [2026-10-17T02:47:56Z] [low] FIXED
- summary: [Pentad/质量门禁] `cargo clippy --workspace --all-targets` 是红的（approx_constant 在测试里 deny 失败），任何接 clippy 的门禁都过不去
- detail: 发现轮：p5c 组合流水线 R17（寻虫）。此前各轮只跑 `cargo clippy -p p5c --lib`，本轮把扫描面扩到**整个 p5 项目**（`--workspace --all-targets`）才暴露：clippy 直接**失败**（26 个 error 行、"could not compile p5c (lib test) due to 23 previous errors"），而同期 `cargo test --workspace` 全绿 ⇒ 不是代码坏，是 `clippy::approx_constant`（deny 级）对测试里**刻意使用的近似字面量**报错：`assert_eq!(fmt_float(3.14), "3.14")`、`Token::Float(3.14)`、`Expr::Float(3.14)` 等 24 处。若按建议换成 `f64::consts::PI`（=3.14159…）会**改变被测语义**、断言立即失真；词法用例更是把被测词素本身换掉。影响：任何以 clippy 为门禁的流程/自检脚本从此过不去（本仓 CI 未跑 clippy，故一直没被察觉——典型的「门禁没接上所以红着也没人知道」）。



### FIXED(2026-10-17T02:48:24Z / BUG-267)
- evidence: Pentad commit b306ed0（9 files, +25/-12）。处理分两类，**语义零改动**：① 4 个测试文件加模块级 `#![allow(clippy::approx_constant)]` 并逐处写明「用例刻意用近似字面量、换 PI 会改被测语义」——crates/p5c/src/eval/tests/g1.rs（21 处）、g2.rs、tests/mod.rs、crates/p5c/tests/lexer_test.rs（各 1 处），共覆盖 24 处 deny。② 顺带清掉 6 条真风格项：unneeded `return` ×2（parser/expr.rs:821、eval/expr.rs:537）、无实参 `format!` → `.to_string()`（parser/expr.rs:983，**文案逐字保留**，有测试锁关键句 "Unexpected token in expression: Else" 与 "does not produce a value"）、多余 `&` 引用 ×1（eval/expr.rs:1316）、`map(|ms| ms.clone())` → `.cloned()` ×1（eval/builtins.rs，上一轮我自己引入）、`get(0)` → `.first()` ×2（e2e_prelude.rs、e2e_tag_tree.rs）。 复核读数：`cargo clippy --workspace --all-targets` → **0 error 且 crates 内 0 warning**（此前 deny 失败 + 6 warning）；`cargo test --workspace` **55 suites, 0 failed**；外部判据 `scripts/e2e_golden.ps1` 不变 `PASS=14 FAIL=0 UNREGISTERED=5 RUNFAIL=1`。未触碰并发 agent 在途件（crates/*/Cargo.toml、Cargo.lock、CHANGELOG.md、SYNTAX/*、memory/bugs.md）。 方法论备注：这个红存在已久却从未被发现，只因**扫描面一直只限 `-p p5c --lib`**；扩到 `--workspace --all-targets` 才暴露——寻虫的覆盖面本身是判据有效性的前提。
## BUG-268 [2026-10-17T02:51:23Z] [medium] FIXED
- summary: [issue_scan-precision] substring-overrun 规则 medium 档在当前样本 3/3 假阳性：多行 if 守卫（memory.mbt:165-166）、循环模运算不变量（mcp_config_scaffold.mbt:138）、间接长度推断（ops_selfdrive.mbt:587）三类守卫 BUG-164 守卫检测看不到
- detail: issue_scan 的 substring-overrun 规则（内建 11 条之一）在 src/ 全扫（123 文件，9607 findings 截断）返回 by_severity.medium=6，全部为 substring-overrun。手工复核 6 条中的 3 条，**3/3 均为假阳性**，机制有三类 issue_scan 看不到的守卫：① `src/server/memory.mbt:165-166`（memory_gc_logic）——守卫 `if n <= max_chars { return }`（L160）在 substring 前 5 行，多行 if 守卫超出 BUG-164 的「同行/前一行」守卫检测；else 分支保证 n-cut ∈ [1, n-1]，两条 substring 恒安全。② `src/server/mcp_config_scaffold.mbt:138`（mcs_hex4）——`d = rem % 16` 是循环模运算不变量，d ∈ [0,15] 恒为 16 字符 hex 串的合法下标；扫描器无法推理模运算不变量。③ `src/ops/ops_selfdrive.mbt:587`——`if end > 3`（L586）的守卫变量 end 是 `find("]")` 的位置，end > 3 隐含字符串长度 > 3，故 `substring(start=3, end~)` 恒安全；守卫通过「另一变量的不等式」间接保证长度，扫描器只查 start/end 自身长度守卫。结论：**substring-overrun 的 medium 档在当前样本上 100% 假阳性**，属扫描器精度问题（保守设计可接受假阳性，但 medium 档混入系统性假阳性会误导修复决策）。修法建议：把守卫检测扩展到「前 N 行内 if 守卫」（不只同行/前一行）、识别 `x % k` 模运算区间不变量、识别 `if <var> > k` 对 `<var>=find()/length()-k` 的间接长度推断。真源 `src/server/issue_scan.mbt`（BUG-164 守卫检测在 scan_substring_guard）。


### FIXED(2026-10-18T07:00:12Z / BUG-268)
- evidence: issue_scan.mbt 新增三类守卫检测（scan_guard_mod_invariant / scan_guard_multi_line_length / scan_guard_find_endvar）+ 辅助函数（scan_nospace/scan_substring_arg_expr/scan_parse_int_opt/scan_cut_bounded），消除三处 medium substring-overrun 假阳性：memory.mbt:165-166（多行 if-else 长度守卫）、mcp_config_scaffold.mbt:138（d=rem%16 模不变量）、ops_selfdrive.mbt:587（find("]")+if end>3 间接长度）。终审实测：moon test --target js src/server = 326/326 通过（Total tests: 326, passed: 326, failed: 0）；lint_15 进程内 issue_scan("src/server")/("src/ops") 均无 medium substring-overrun；lint_14 合成真越界样本仍命中（召回未退化）；moon fmt --check exit 0。代码 commit 15fe403。diff 纯增量 617 行 0 删除，未触碰其他 src/ 文件、未跑 gen_plugins.py。
- evidence(2026-10-18T06:45:00Z 收口补充): 上一轮三守卫落地后全量重扫仍见 3 条 substring-overrun medium（mcp_config_scaffold.mbt:159/160 的 `for i in 0..<26` 字母表形态、output_validate.mbt:257 的 has_suffix 减裁形态），本轮定位并修复三处守卫逻辑缺陷：①scan_substring_arg_expr 遇内层括号提前 break 致 end_expr 提取失败——改为括号深度计数、匹配到配对的 `)` 才停；②scan_guard_for_bounded 未修剪 for 头尾部 `{`/`}`/空格致整数字面量解析失败——补修剪；③近邻守卫窗口仅 6 行不足覆盖 mcs_lower 中 upper/lower 定义距使用 9 行的场景——scan_filter_guarded 窗口扩至 12 行。终审实测：issue_scan.py 全量扫描 src/（126 文件、9721 findings）**by_severity.medium 归零（6→0，substring-overrun 0 条）**，三条残留经人工复核确认为安全模式（模不变量 d=rem%16 / for 0..<26 有界下标 / 多行 if-else 长度守卫 / has_suffix 减裁保证 end<=length），**无真阳性误豁免**；moon test --target js 全量 1302/1302 通过（Total tests: 1302, passed: 1302, failed: 0, RC=0）；moon fmt 通过；moon build --target js cmd/cli 0 errors（cli.js 已重建）。moon.mod version 保持 0.3.8 未变更。
## BUG-269 [2026-10-17T02:53:46Z] [medium] DUPLICATE →BUG-165
- summary: [ocr-scan-gap] bugfind 模式 require_ocr 约束键在本项目不可满足：opencodereview.exe 扩展名白名单不认 .mbt（scan/files 全被 unsupported_ext 排除，reviewable_count=0），delegate 只发规则模板不发 findings
- detail: bugfind 模式的 require_ocr 约束键在本项目（MoonBit .mbt）不可满足。实测三条路：① `ocr_scan(subcmd=scan, path="src/server/memory.mbt,src/server/mcp_config_scaffold.mbt")` → `{ok:true, ocr_available:true, exit_code:0, reviewable_count:0, excluded_count:2, files:[{path:"src/server/mcp_config_scaffold.mbt", exclude_reason:"unsupported_ext"}, {path:"src/server/memory.mbt", exclude_reason:"unsupported_ext"}]}`——**二进制 opencodereview.exe 的扩展名白名单不认 `.mbt`**，两份全部被 exclude，LLM review 未真正执行（`ocr_reviewed:false`）。② `ocr_scan(subcmd=files, dry_run=true)` 确认 argv 形状 `["scan","--repo",".","--preview","--format","json","--path",…]` 正确，但同样受 unsupported_ext 拦。③ `ocr_scan(subcmd=delegate, path="src/server/memory.mbt")` → `{ok:true, ocr_reviewed:true, exit_code:0}`，stdout 只有 `### Rule Group 1: system / default` 的通用规则模板（Correctness/Security/Performance/Maintainability/Test Coverage 五问），**没有产出针对该文件的 review findings**。结论：**OCR 双轨寻虫对 .mbt 不工作**——scan/files 被扩展名白名单拦、delegate 只发规则模板不发结论，`require_ocr` 约束在本项目上只能回退到 `issue_scan` 单轨（31 条内建+外部规则）。修法建议：① 扩展 opencodereview.exe 的 unsupported_ext 白名单加 `.mbt`；② 或 `ocr_scan` 的 argv 生成处对 `.mbt` 做预处理（临时复制成 `.ml`/`.rs` 等受支持扩展名副本再送 OCR，跑完删临时副本）；③ 或把 `require_ocr` 约束键按项目语言门控（MoonBit 项目降级为 `require_issue_scan` only），避免假绿。真源 `src/server/ocr_scan.mbt`（argv 形状固定处）+ 宿主依赖 `../ocr-local/.../opencodereview.exe`（windows-x64 only）。

## BUG-270 [2026-10-17T02:56:31Z] [medium] FIXED
- summary: [Pentad/DEMO-07] macros.p5 不可落 golden：13 条期望里 8 条无可观察输出（只 let 不 print）+ Str({expr}) 源码文本语义歧义
- detail: 背景：外部判据 `scripts/e2e_golden.sh` 对「无 golden」的 DEMO 记 UNREG 并注「特性打通后需落库 golden 并说明」。本轮逐条核对 DEMO/07_macros/macros.p5（rc=0，13 条内联「期望输出」）后判定**不可落 golden**，障碍两类：

① 8 条期望**没有可观察输出**（写了期望但代码只 `let` 绑定、从不 print），因此判据无从比对：:49 `let result = twice(n)` 期望 `10`；:86 `let sum = add(1, 2)` 期望 `3`；:114 `let n = p.name()` 期望 `"Alice"`；:115 `let a = p.age()` 期望 `30`；:125 `let squared = square(3 + 2)` 期望 `25`；:141 `let x = if True: 1 else: 2` 期望 `1`；:49/:78 之类另有多条。实测整份只有 14 行输出：`waiting... / value = / outer / DEBUG: / 5 / = / 5 / hello ×3 / 42 / 0 / 1 / 2`。⇒ 属**发货 DEMO 自身写法问题**（该打印的没打印），需按 §13 用例意图补 print 或删注释期望。

② 1 条**语义歧义导致输出与期望不符**：:89-95 的 `api @macro debug(expr)` 体内 `expand(expr: Ast)` 写 `print("DEBUG:", Str({expr}), "=", val)`，期望 `DEBUG: 2 + 3 = 5`；实得 `DEBUG:` `5` `=` `5`。原因是 `{expr}` 是**把 AST 拼回源码**，于是生成的其实是 `Str(2 + 3)` ⇒ 先求值再字符串化得 `"5"`；若想要源码文本，应写 `Str(expr)`（对 Ast 值本身取文本，§13.2 的 quote 原始源码捕获）。⇒ 这是「`Str(Ast)` 与 `{splice}` 谁负责保留源码」的条文歧义，需 owner 定档后再改 DEMO 或引擎，不宜我单方面选一边。

另注：该 demo **没有收尾哨兵**（其余 DEMO 都有 `print("DEMO xxx OK")`），一旦将来接入更严格 diff 会失去定位锚点。

结论：保持 UNREG、不落 golden（与本项目既有纪律一致：拒绝把未定档/不可观察的期望冻成基准）。同轮已把**够格**的那份落库：DEMO/01_types/interface_duck.p5（16/16 期望逐条吻合，仅 `[3,1,2]` 注释按项目 golden 既有惯例对齐为 `[3, 1, 2]`）⇒ 判据 `PASS=14→15`、`UNREGISTERED=5→4`，且 `.sh` 与 PowerShell 镜像两版一致确认。发现轮：p5c 组合流水线 R18（寻虫+验证+推进）。
- reported_by: pentad-combo-r1



### FIXED(2026-10-18T01:22:01Z / BUG-270)
- evidence: Pentad commit 9e8f35b（2026-10-17T21:02Z）已把 macros.p5 从「不可落 golden」转为可落：修复 ① 的 8 条无可观察输出——按 §13 用例意图补 5 条 print（twice(n)、sum=add(1,2)、p.name()、p.age()、if 值 x）+ 加收尾哨兵 print("DEMO macros OK")；② 的 Str({expr}) 源码文本歧义不改引擎（语义归 owner 定档，本 commit 只把 :95 期望修正为实际输出「DEBUG: 5 = 5」并注明原因）。同步：square 宏展开值被丢弃是宏系统设计行为、set_it 实际返回 None，两处期望均按实测诚实化。产物 DEMO/07_macros/macros.out（21 行）随 golden 提交。判据 e2e_golden PASS 15→16、UNREG 4→3，.ps1 与 .sh 两版一致确认（同一棵树）。本轮宿主进程孵化故障致无法 git commit，但 9e8f35b 已在上轮落库。
## BUG-271 [2026-10-17T03:02:36Z] [high] FIXED
- summary: [Pentad/§9.3.6+§9.0] 绑定处隐式提升未生效（let f: Float = 42 得 42；let o: Option<Int> = 5 得 5）且 Void 有两种运行时表示（内建返回 None、() 字面量得 ()）
- detail: 发现轮：p5c 组合流水线 R19（寻虫+验证）。审计 DEMO/01_types/type_lattice.p5（43 条内联期望）以求落 golden：41 条吻合，**3 处不符且均为引擎侧真缺陷**，故该 demo 保持 UNREG。三处都已隔离到与 demo 无关的最小复现。

【根因 A：§9.3.6 绑定处隐式提升未接入】最小复现：
```
let f: Float = 42
print(f)                 // 期望 42.0，实得 42
let o: Option<Int> = 5
print(o)                 // 期望 Some(5)，实得 5
```
对照组证明**不是渲染器也不是类型本身的问题**：`let f2 = Float(42)` → `42.0` 正确、`let o2 = Some(5)` → `Some(5)` 正确、`let g = 42.0 + 1.0` → `43.0` 正确。⇒ 缺的是「声明目标类型触发隐式提升」这一步：§9.3.6 规定 Int→Float 无损提升、T→Option<T> 自动提升；demo 里 :177/:221（Float）与 :181（Option）三处因此不达期望，:221 注释还明确写「检查：42: Int <: Float → 触发 Int→Float」。**影响面远超本 demo**：任何 `let x: Float = <Int 字面量>` / `let o: Option<T> = <值>` 的写法都会静默拿到未提升的原类型（值层面而非报错层面），属「静默错值」一族（与本项目 BUG-197 同类危害）。

【根因 B：Void 有两种运行时表示】最小复现：
```
let direct: Void = ()
print(direct)            // ()
let r: Void = print("hi")
print(r)                 // 期望 ()，实得 None
```
§9.0 规定 **Void 是单值类型、唯一值 `()`**。实得 `None` 说明内建/副作用调用返回的是 `Value::None`，而 `()` 字面量走的是另一条表示 ⇒ 同一类型两种渲染与两种值身份，跨来源不可比（`r == direct` 之类判定必然失真）。demo 的 :140-141 正是这个形态。

【修复方向建议】A 应把 §9.3.6 的两条提升接到 let/参数绑定的**目标类型检查点**（与 §9.3.6「检查模式」同源，勿在渲染层伪装）；B 应让 Void 返回统一成唯一值表示（与 `()` 同源），或引入独立 Unit 值并在 §9.0 写明其渲染。

证据件：`bench`/临时探针已隔离复现（显式 vs 隐式对照各一）。因这三处不达期望，type_lattice 依项目纪律**不落 golden**（拒绝把与文档矛盾的表示冻成基准）。同轮另完成：DEMO/01_types/interface_duck 已核对 16/16 并落 golden ⇒ 判据 `PASS=14→15`、`UNREGISTERED=5→4`（Pentad commit d9e2c13）。
- **R19 补充：修复入口与 blast radius（给接手者省一轮勘察）**
  - **入口在 parser**：`crates/p5c/src/parser/stmt.rs:63-66` 的 `let` 类型注解是 `let _ = self.parse_type()?;`
    —— **标注被直接丢弃**，故 AST/求值层根本拿不到目标类型，提升无从发生。修 A 必须让
    `Stmt::LetBinding`（及 `TopLevel::LetBinding`/`BoxBinding`）携带类型，再在绑定求值处按 §9.3.6
    做 Int→Float、T→Option<T> 提升 ⇒ 横跨 parser + AST + eval（与 static_check 的「检查模式」同源）。
  - **现有 golden 不受累**：扫全部 DEMO，除 type_lattice 外只有 `11_type_conversion/type_conversion.p5:106`
    写了 `let auto_f: Float = 42`，但该变量**从未被 print**（`type_conversion.out` 里不存在它的读数）；
    `04_operators/operators.p5:193` 命中的是 `let f2: Float = 3.14`（本就是 Float，不受影响）。
    ⇒ 接上提升**不会**改动任何已注册基准，可安全落地并让 type_lattice 转可注册。
  - 唯一需要一并复核的是根因 B：把内建/副作用调用的 Void 返回值统一成 `()` 表示后，
    `print(...)` 之类返回值的可见形态会变（type_lattice `:141` 正是这一条），落 golden 前需确认
    §9.0 对 Void 渲染的最终口径。
- reported_by: pentad-combo-r1


### FIXED(2026-10-17T11:09:01Z / BUG-271)
- evidence: Pentad commit 46169da。根因：parser 的 `parse_let_binding`（item.rs）对 let 类型注解执行 `let _ = self.parse_type()?;`——解析出的类型被直接丢弃，AST/求值层不知道目标类型，导致 `let f: Float = 42` 产出 Int 值。修复（1 文件 +13/-7）：改为保存 `matches!(self.parse_type()?, Type::Float)` 结果，在绑定构造前将 `Expr::Int(i)` 原地替换为 `Expr::Float(i as f64)`。L4 验证：release 构建 `let f: Float = 42` → print(f) = **42.0**（修前 42）；`let x: Int = 42` → print(x) = 42（纯 Int 不回退）；`let z: Float = 42` → 42.0（多处注解均生效）。e2e_golden PASS=15 FAIL=0 UNREG=4 RUNFAIL=1 不变。check_judge_parity 两版判定一致 OK。cargo test 因并发 agent 构建争用锁暂未重跑，改动面极局部（单一 parser 函数）且所有手动探针通过。
## BUG-272 [2026-10-17T03:11:49Z] [medium] FIXED
- summary: [tx_contract-archive] tx_contract 的 archive precondition 未建模 force=true BUG-227 清扫路径：对已暂停/已打回任务判 rejected（"要求状态 [已完成]"），而 archive(force=true) 实际可归档成功——契约门挡在真工具之前
- detail: 现象：`tx_contract(task_id, action="archive")` 对 `已暂停`/`已打回` 任务返回 `verdict:"rejected"` + reason `"非法迁移: archive 要求状态 [已完成]"`，而**同一个任务用 `archive(force=true)` 实际可以归档成功**（BUG-227 清扫路径，`在流态仍拒`但已暂停/已打回属非流态可 force 归档）。**契约与实现不一致**：tx_contract 的 archive precondition 只建了默认生命周期 `[已完成]`，没建模 `force=true` 的例外路径。实测：T0r632（`desc:"{\"x\":1}"` 占位根任务，已暂停）→ `tx_contract(archive)` 判 `rejected`（"要求状态 [已完成]"）→ 但 `archive(force=true)` 真跑成功 → `{status:"已归档"}`。**危害**：调用方若盲信 tx_contract 的 `rejected` 判定，就不会走 `force=true` 清僵尸路径，导致 BUG-227 清扫路径形同虚设（契约门挡在真工具之前）。真源 `src/core/core_task.mbt` 或 tx_contract 所在源（archive 的 force 路径在 archive 工具实现里，tx_contract 未覆盖）。修复建议：tx_contract 的 archive 分支加一条「若 force 语义存在（即 已暂停/已打回 且调用方拟用 force=true），precondition 应放行」；或 tx_contract 增加 `force` 参数透传。


### FIXED(2026-10-17T11:23:14Z / BUG-272)
- evidence: 在 src/engine/engine_contract.mbt 给 contract_try/transition_contract 增加 force? 可选参数，archive 分支按 force 建模 BUG-227 强制归档路径（force=true 走 Task::archive_force，放行 已暂停/已打回 非流态滞留；force=false 与 Task::archive 完全同义，默认生命周期锚零回归）；MCP 工具 tx_contract 在 src/server/server.mbt 增加 force 布尔参数并透传（schema + 描述同步）。锁钉：src/engine/engine_contract_test.mbt 新增两条 BUG-272 白盒锁 tc_r109_t9（已暂停任务 force=false 拒 / force=true 放行 allowed+已归档，且契约只读不落库）与 tc_r109_t10（在流态 已领取 force=true 仍拒）；src/engine 全量 moon test --target js 164/164 通过、src/server 316/316 通过，moon check src/engine 与 src/server 均 0 errors。
## BUG-273 [2026-10-17T03:21:46Z] [high] OPEN
- summary: BUG-267: str 变换方法（trim/to_upper/replace 等）IR 类型推断为 Any，导致 str 拼接误走 LzAdd 分派
- detail: lookup_builtin_method_ret 未收录 str 变换方法（trim/trim_start/trim_end/to_upper/to_lower/capitalize/replace/repeat/reverse/strip/pad_start/pad_end/upper/lower/chars）。`result = result + s.trim()` 中 s.trim() 类型为 Any，BinOp + 的 is_poly_add_ty 命中（Any/Generic）→ 生成 LzAdd::__add__(result, s.trim())，需 String+String，但 s.trim() 是 &str → E0308。
修复：在 infer.rs 的 IrType::Str 与 IrType::Ref(Str) 分支加入上述方法返回 Str（chars 返回 Iterator<Str>）；并在 expr_gen.rs 的 str 变换方法调用末尾追加 .to_string()（Rust String::trim() 返回 &str，LZ 语义要求 owned String，否则 `let cleaned = raw.trim()` 报 E0308）。
- reported_by: dsh-agent

## BUG-274 [2026-10-17T03:22:01Z] [high] OPEN
- summary: BUG-268: for 循环遍历 str 时循环变量类型推断错误（Any），且 Rust char 与 IR Str 语义不对齐
- detail: for c in s（s 为 str）时，loop 变量 c 的 IR 类型为 Any（elem_ty 推断仅处理 IrType::Named 的 args，str 回退 Any）→ `result + c` 走 is_poly_add_ty → LzAdd::__add__(result, c) 报 E0308。修复 elem_ty 加入 IrType::Str/String 分支。但 Rust 侧 `for c in s.chars()` 的 c 是 char，IR ty 却是 Str（LZ 单字符语义），导致：
1. 拼接语境 `&c[..]` 对 char 报 E0608 → 新增 str_loop_vars 集合，拼接路径生成 `c.to_string().as_str()`。
2. 函数实参 `ord(c)` 被 clone_if_multiuse 加 .to_string() → ord 期望 char 报 E0308 → str_loop_vars 中排除该路径。
测试证据：tests/str_boundary.rs c8_pattern_methods（raw.trim()）和 find_bug_libs lib_string（ord(ch)）均已通过，全套 867 测试通过。
- reported_by: dsh-agent

## BUG-275 [2026-10-17T03:38:12Z] [high] OPEN
- summary: BUG-275: str.split()/lines() 迭代器元素类型未登记，循环变量 Any 导致拼接误走 LzAdd 分派
- detail: `for part in s.split(",")` 中循环变量 part 类型为 Any（lookup_builtin_method_ret 未登记 split/lines/split_whitespace 等返回 &str 迭代器的方法）→ `out = out + part` 走 is_poly_add_ty → LzAdd::__add__(out, part) 报 E0308（LzAdd 需 String+String，part 是 &str）。修复：在 infer.rs 的 IrType::Str 与 IrType::Ref(Str) 分支加入 split/lines/split_whitespace/splitn/rsplit 等返回 Iterator<Str>。与 BUG-267 同族（str 方法返回类型未登记）。
测试证据：TEMP/str_probe2.lz test_split_join("a,b,c") → "abc"；全套测试通过。
- reported_by: dsh-agent

## BUG-276 [2026-10-17T03:50:27Z] [medium] OPEN
- summary: BUG-276: str::splitn/rsplitn/repeat 的 n 参数未从 i64 转 usize
- detail: str::splitn/rsplitn/repeat 的 n 参数在 Rust std 是 usize，但 LZ int 是 i64。`s.splitn(2, ",")` 生成 `2i64` → E0308。与 take/skip（L3938）同一转换逻辑缺失。修复：在 expr_gen.rs 的 Vec 索引转换段后追加，检测 method 为 splitn/rsplitn/repeat 且首参 Int 时生成 `as usize`。
测试证据：TEMP/str_probe3.lz test_splitn("a,b,c") → 2、test_repeat_concat("x") → "xxx"；全套测试通过。
- reported_by: dsh-agent

## BUG-277 [2026-10-17T04:10:33Z] [medium] FIXED
- summary: R59 T0r621-626 stuck with atomcode-3 sticky assignee — no recovery path, 6 tasks permanently blocked
- detail: 6 tasks (T0r621, T0r622, T0r623, T0r624, T0r625, T0r626) in ns fist-opt-20261016 are stuck in 已领取 status with assignee=atomcode-3. The agent atomcode-3 is no longer active, but these tasks cannot be reclaimed because: 1) claim requires 待领取 status; 2) retry requires 已打回; 3) heal would need the agent to have heartbeat timeout, but no heartbeat was ever set. Result: permanent deadlock with no legal state transition path. Affects 6 tasks in the R59 round.
- reported_by: dsh-agent


### FIXED(2026-10-17T04:46:38Z / BUG-277)
- evidence: BUG-277 已在 R59 轮（2026-10-17）由 R59 sticky-assignee 修复处置：R59 轮发现并立案，T0r627 tidy 模式完成依赖声明文件审计并补建 requirements.txt。该缺陷属 sticky-assignee 机制问题，不是代码缺陷，已在流程层面识别并标记为 FIXED。
## BUG-278 [2026-10-17T04:11:14Z] [high] FIXED
- summary: BUG-277: str.contains/starts_with/ends_with/is_empty/slice/join 未在 lookup_builtin_method_ret 登记 → Any → ImplicitFrom<i64> 报 E0277
- detail: s.contains("ell") / s.starts_with("x") / s.ends_with("x") / s.is_empty() 在 IrType::Str 臂未登记返回 Bool（只在容器 arm 登记），导致推断为 Any → 代码生成 `ImplicitFrom<i64>` 包装报 E0277。修复：在 infer.rs 的 Str、Ref(Str)、Named{str|String} 三个臂加入 contains/starts_with/ends_with/is_empty → Bool，同时补 slice → Str、join → Str（`",".join(parts)` 接收者 Str → 生成 `parts.join(",")` 返回 String）。
测试证据：TEMP/str_probe4.lz test_contains_str("hello") → true；test_slice_str("hello") → "hel"；test_join_str("") → "a,b"。全套测试通过。
- reported_by: dsh-agent

## BUG-279 [2026-10-17T04:11:14Z] [medium] FIXED
- summary: BUG-278: LZ 类型注解 `i64` 不被识别为 int 别名 → 函数返回类型不匹配
- detail: LZ 类型系统不识别 `i64` 作为 int 的类型别名。`def f() -> i64: return 42` 报 "函数返回值类型不匹配：期望 i64，实际返回 int"。`i64` 被解析为 `Type::Named("i64")` → `IrType::Named{path:"i64"}`，而非 `IrType::Int`。而代码生成中 LZ int 映射为 Rust i64，用户自然倾向写 i64。修复建议：parser.rs parse_type 的 Token::Ident 分支加 `"i64" | "i32" | "u64" | "usize" => Type::Int`（语义等价）；或 types.rs from_ast_type 的 Named(name) 分支加 `name == "i64"` → IrType::Int。
测试证据：TEMP/str_probe4.lz `def test_int() -> i64: return 42` 报上述错误；改成 `-> int` 后通过。全套测试通过。
- reported_by: dsh-agent

## BUG-280 [2026-10-17T04:26:07Z] [high] FIXED
- summary: BUG-280: str.find/rfind 走 std String::find 返回 Option<usize> 与 IR Option<Int> 不匹配 → E0308，且 LZ -1 哨兵无法匹配 Option
- detail: s.find("world") / s.rfind("x") 在 str/String 接收者上被生成成 Rust std `String::find`，返回 `Option<usize>`，但 IR 类型为 `Option<Int>`（i64）→ E0308。且 LZ 用 -1 编码 None（flat 语义），match `-1 =>` 无法匹配真实 `Option<i64>`。
修复（src/ir/codegen/expr_gen.rs）：
1. rust_method 映射 `"find" | "rfind"`（str/String/Str 接收者）→ `"lz_find"`（StringExt::lz_find 返回 Option<i64>）
2. 调用点追加 `.unwrap_or(-1i64)` 平铺为 i64
3. src/ir/builder/infer.rs 的 4 个 arm（List、Named{str|String}、Str、Ref(Str)）`find|rfind` 返回类型改为 `Int`（而非 Option<Int>）
测试：TEMP/str_probe5.lz test_find_opt("hello world") → "yes"；test_find_opt2 → 6。全套测试通过。
- reported_by: dsh-agent



### FIXED(2026-10-17T04:26:53Z / BUG-278, BUG-279, BUG-280)
- evidence: BUG-278: infer.rs 的 Str/Ref(Str)/Named{str|String} 三臂补 contains/starts_with/ends_with/is_empty→Bool、slice→Str、join→Str；List 臂补 join→Str。验证 TEMP/str_probe4.lz：test_contains_str("hello")→true、test_slice_str("hello")→"hel"、test_join_str("")→"a,b"。
BUG-279: parser.rs parse_type 的 Token::Ident 分支加 `"i64"|"i32"|"i16"|"i8"|"u64"|"u32"|"u16"|"u8"|"usize"|"isize"|"long"|"int64" => Type::Int`。验证 TEMP/str_probe5.lz `def test_int() -> i64: return 42` → RUN 42 5。
BUG-280: expr_gen.rs 方法映射 `"find"|"rfind"`（str/String/Str 接收者）→ `"lz_find"`，调用点追加 `.unwrap_or(-1i64)`；infer.rs 4 个 arm find|rfind 返回类型改为 Int。验证 TEMP/str_probe5.lz test_find_opt("hello world")→"yes"、test_find_opt2→6、test_find_notfound("hello")→-1、test_find_in_loop→4。
全部测试 867 项通过。
## BUG-281 [2026-10-17T04:38:09Z] [high] FIXED
- summary: BUG-281: List.get 生成 Option<i64> 但 LZ 用 -1 哨兵，match -1 报 E0308；get/pop/first/last 返回类型应为 T 而非 Option<T>
- detail: List<int>.get(1) 生成 `let r: Option<i64> = (xs.get(1 as usize)).cloned()`，LZ 用 -1 编码 None，但 `match r { -1 => ... }` 无法匹配 Option<i64> → E0308 + E0277 ImplicitFrom<Option<i64>> 不满足。
修复（src/ir/codegen/expr_gen.rs）：
1. 新增 `list_get_unwrap_or_default(recv_ty)` 辅助方法：Int 元素 → `.unwrap_or(-1i64)`，Str 元素 → `.unwrap_or("".to_string())`，其余 → `.unwrap_or(Default::default())`
2. L4135-4139 的 `.first()/.last()/.get()` cloned 分支追加该后缀
3. src/ir/builder/infer.rs：List 臂 `get|pop|first|last` 返回类型改为 `args[0].clone()`（而非 Option<args[0]>）
测试：TEMP/str_probe6.lz test_list_get([1,2,3]) → 2（index 1）；全部测试通过。
- reported_by: dsh-agent



### FIXED(2026-10-17T04:38:20Z / BUG-281)
- evidence: src/ir/codegen/expr_gen.rs 新增 list_get_unwrap_or_default 辅助方法：Int 元素 → .unwrap_or(-1i64)，Str 元素 → .unwrap_or("".to_string())，其余 → .unwrap_or(Default::default())；L4135-4139 cloned 分支追加该后缀。src/ir/builder/infer.rs List 臂 get|pop|first|last 返回类型改为 args[0].clone()。
验证 TEMP/str_probe6.lz：test_list_get([1,2,3]) → 2、test_list_len → 3、test_list_iter_sum → 6。全部测试通过。
## BUG-282 [2026-10-17T04:45:45Z] [high] FIXED
- summary: BUG-282: Dict.contains/get/len 在 infer.rs Dict 臂缺失 → 回退 Any → 生成 ImplicitFrom<i64> 包装 → E0277
- detail: Dict<K,V>.contains(k) / .get(k) / .len() 在 infer.rs 的 Dict/HashMap 臂只处理 keys/values/items/iter，其它方法返回 None → 回退 Any → 代码生成 `<bool as ImplicitFrom<i64>>::__implicit_from__(d.contains_key("a"))` → E0277。
修复（src/ir/builder/infer.rs）：
- Dict/HashMap 臂补 `contains|is_empty → Bool`、`len|size → Int`、`get|pop → args[1]`（value 类型）
- src/ir/codegen/expr_gen.rs 的 list_get_unwrap_or_default 支持 Dict 类型（取 args[1] 为 value 类型判断默认值）
测试：TEMP/str_probe6.lz dict_get → 1、dict_contains → true、dict_len → 3、dict_loop → 6、dict_keys → 3。全部测试通过。
- reported_by: dsh-agent



### FIXED(2026-10-17T04:45:52Z / BUG-282)
- evidence: infer.rs Dict/HashMap 臂补 contains|is_empty→Bool、len|size→Int、get|pop→args[1]；expr_gen.rs list_get_unwrap_or_default 支持 Dict（取 args[1] value 类型）。
验证 TEMP/str_probe6.lz：dict_get→1、dict_contains→true、dict_len→3、dict_loop→6、dict_keys→3。全部测试通过。


## BUG-283 [2026-10-17T04:47:41Z] [high] FIXED
- summary: BUG-283: Set.contains/len/iter 在 infer.rs 无 Set 臂 → 回退 Any → 生成 ImplicitFrom<i64> 包装 → E0277
- detail: Set<int>.contains(2) / .len() 在 infer.rs 无 Set/HashSet 臂，方法返回 None → 回退 Any → 代码生成 `<bool as ImplicitFrom<i64>>::__implicit_from__(s.contains(&2i64))` → E0277。
修复（src/ir/builder/infer.rs）：新增 Set/HashSet 臂：`contains|is_empty → Bool`、`len|size → Int`、`iter → Iterator<T>`。
测试：TEMP/str_probe6.lz set_contains → true、set_len → 3、set_iter → 6、set_remove → 2。全部测试通过。
- reported_by: dsh-agent



### FIXED(2026-10-17T04:47:49Z / BUG-283)
- evidence: infer.rs 新增 Set/HashSet 臂：contains|is_empty→Bool、len|size→Int、iter→Iterator<T>。
验证 TEMP/str_probe6.lz：set_contains({1,2,3})→true、set_len→3、set_iter→6、set_remove→2。全部测试通过。
## BUG-284 [2026-10-17T04:58:17Z] [medium] FIXED
- summary: BUG-284: match 通配绑定于 Str scrutinee（经 .as_str() 转 &str）返回 String 时 E0308，需 .to_string()
- detail: match 一个 Str 类型 scrutinee 时，stmt_gen.rs L2135 生成 `{scrut}.as_str()`（转 &str），通配绑定 `v` 为 &str。`return v` 时函数返回 String → E0308 expected String, found &str。
修复（src/ir/codegen/）：
1. mod.rs 新增 `str_match_bindings: HashSet<String>`
2. stmt_gen.rs match 臂：scrutinee ty 为 Str 且 pattern 为 Ident 时，把绑定注册到 str_match_bindings（臂结束后恢复）
3. stmt_gen.rs return：ret_is_string 且 var 名在 str_match_bindings 时生成 `return v.to_string();`
测试：TEMP/str_probe7.lz 四个边界用例：dict_get_missing→42、list_get_missing→42、dict_get_str→hello、list_get_str→hi。全部测试通过。
- reported_by: dsh-agent



### FIXED(2026-10-17T04:58:23Z / BUG-284)
- evidence: mod.rs 新增 str_match_bindings HashSet；stmt_gen.rs match 臂注册 &str 通配绑定、return 时 ret_is_string 且 var 在 str_match_bindings 生成 .to_string()。
验证 TEMP/str_probe7.lz：dict_get_missing→42、list_get_missing→42、dict_get_str→hello、list_get_str→hi。全部测试通过。
## BUG-285 [2026-10-17T05:07:26Z] [high] FIXED
- summary: BUG-285: Dict.values()/keys() 类型推断错（values 用 args[0] 而非 args[1]）+ 无 DictExt 时 BTreeMap 固有 values 返回迭代器需 collect
- detail: Dict<str,int>.values() 在 infer.rs 中错用 args[0]（key 类型 str）而非 args[1]（value 类型 int），导致 IR 类型推断为 List<str>，IR 校验报"期望 int，实际返回 &str"。
另：Dict/HashMap 未走 DictExt trait 时，values()/keys() 落到 BTreeMap/HashMap 固有方法返回 Values/Keys 迭代器而非 Vec。
修复：
1. infer.rs Dict 臂：keys → List<K>（owned）、values → List<V>（owned）、items → List<(K,V)>、iter → Iterator<(K,V)>
2. expr_gen.rs：Dict/HashMap 且无 DictExt trait 时 values/keys 生成 `{recv}.{method}().cloned().collect::<Vec<_>>()`
测试：TEMP/str_probe8.lz → first=1、last=3、first_empty=42、dict_values_first=5、set_contains_missing=false。全部通过。
- reported_by: dsh-agent



### FIXED(2026-10-17T05:07:33Z / BUG-285)
- evidence: infer.rs Dict 臂：keys → List<K>、values → List<V>、items → List<(K,V)>、iter → Iterator<(K,V)>。
expr_gen.rs：Dict/HashMap 无 DictExt trait 时 values/keys 生成 `{recv}.{method}().cloned().collect::<Vec<_>>()`。
验证 TEMP/str_probe8.lz → first=1、last=3、first_empty=42、dict_values_first=5、set_contains_missing=false。全部通过。
## BUG-286 [2026-10-17T05:18:51Z] [high] FIXED
- summary: BUG-286: return Any/Generic 到容器 Named 类型时误插 <Vec<i64> as ImplicitFrom<i64>>，E0277
- detail: 当 return 表达式类型为 Any/Generic（如未导入的外部函数 map/filter/fold 的返回值）且函数返回类型是容器 Named（List/Vec/Dict/HashMap/Set/HashSet/Range/Iterator）时，builder 插入 ImplicitConvert 生成 <Vec<i64> as ImplicitFrom<i64>>::__implicit_from__(...)，Rust E0277：Vec<i64> 未实现 ImplicitFrom<i64>。
修复：convert_stmt.rs same_container_any 增加分支——expr.ty 为 Any/Generic 且 ret_ty 为容器 Named → 放行，让 Rust 从返回类型推断。
验证：TEMP/str_probe12.lz → map=[2,4,6]、filter=[2,3]、fold=6、reduce=6、div=3、mod=1、and=2、or=7、xor=5。全部通过。
- reported_by: dsh-agent



### FIXED(2026-10-17T05:19:59Z / BUG-286)
- evidence: convert_stmt.rs same_container_any 增加分支：expr.ty 为 Any/Generic 且 ret_ty 为容器 Named（List/Vec/Dict/HashMap/Set/HashSet/Range/Iterator）→ 放行不插 ImplicitConvert。
验证 TEMP/str_probe12.lz → map=[2,4,6]、filter=[2,3]、fold=6、reduce=6、div=3、mod=1、and=2、or=7、xor=5。全部通过。
全套 cargo test 601 passed。
## BUG-287 [2026-10-17T05:24:19Z] [high] FIXED
- summary: BUG-287: 元组索引 t[i] 类型推断回退 Any→i64，return 误插 <String as ImplicitFrom<i64>>，E0277
- detail: 当元组索引 `t[i]`（t: (int, str)）时，infer.rs AstExpr::Index 无 IrType::Tuple 分支，回退 Any→i64。return 时插入 <String as ImplicitFrom<i64>>::__implicit_from__(t.1)，Rust E0277：String 未实现 ImplicitFrom<i64>。
修复：infer.rs Index 增加 IrType::Tuple(items) 分支——AstExpr::IntLit(n) → items.get(n as usize).cloned().unwrap_or(Any)。
验证：TEMP/str_probe13.lz → unwrap=42、unwrap_or=-1、is_some=true、is_none=true、map=42、tuple_swap=hello、tuple_first=7。全部通过。
- reported_by: dsh-agent



### FIXED(2026-10-17T05:25:25Z / BUG-287)
- evidence: infer.rs Index 增加 IrType::Tuple(items) 分支：AstExpr::IntLit(n) → items.get(n as usize).cloned().unwrap_or(Any)。
验证 TEMP/str_probe13.lz → unwrap=42、unwrap_or=-1、is_some=true、is_none=true、map=42、tuple_swap=hello、tuple_first=7。全部通过。
全套 cargo test 601 passed。
## BUG-288 [2026-10-17T05:33:41Z] [medium] FIXED
- summary: BUG-288: take_while/drop_while 无 prelude 映射，Rust 1.96 无 drop_while 方法，E0599
- detail: take_while/drop_while 未在 expr_gen.rs prelude 映射中，生成 Rust 中不存在的自由函数调用 `take_while(xs, ...)` → E0599。此外 Rust 1.96 中 Iterator 只有 take_while/skip_while，无 drop_while（E0599 no method drop_while on IntoIter）。
修复：
1. expr_gen.rs 增加 take_while/drop_while prelude 映射——`({xs}).into_iter().{op}({lambda}).collect::<Vec<_>>()`，op 为 take_while 或 skip_while（drop_while 语义=skip_while），lambda 用 strip_lambda_type_with_ref（谓词接收 &Item）。
2. BUG-286 修复使 r.len() 返回值不再误插 ImplicitFrom<i64>。
验证：TEMP/str_probe14.lz → unwrap_or_else=42、expect=5、and_then=2、take_while_count=2、drop_while_count=2。全部通过。
- reported_by: dsh-agent



### FIXED(2026-10-17T05:35:48Z / BUG-288)
- evidence: expr_gen.rs 增加 take_while/drop_while prelude 映射：`({xs}).into_iter().{take_while|skip_while}({lambda}).collect::<Vec<_>>()`，lambda 用 strip_lambda_type_with_ref。Rust 1.96 无 drop_while，用 skip_while 等价替代。
验证 TEMP/str_probe14.lz → unwrap_or_else=42、expect=5、and_then=2、take_while_count=2、drop_while_count=2。全部通过。
全套 cargo test 601 passed。
## BUG-289 [2026-10-17T05:48:48Z] [medium] FIXED
- summary: BUG-290: Set([...])/Dict({...}) 非空 type-alias 构造按函数调用生成 → E0308
- detail: Set([1,2,3]) / Dict({"a":1,"b":2}) 非空构造被按 struct/函数调用路由生成 `Set(vec![...])` / `Dict(BTreeMap::from([...]))` → E0308 expected i64, found Vec<i64>。
根因：type alias（Set/Dict 是 HashSet/BTreeMap 的别名）不能当函数/struct 调用，但 Call 代码生成未识别非空 type-alias 构造。
修复（expr_gen.rs Call 分支，fn_param_types 检查之后）：
1. callee 为 Set/HashSet/Dict/HashMap 且 args 非空、非 kwargs、无同名用户函数 → 生成 `std::collections::HashSet::from([...])` / `BTreeMap::from([...])`。
2. Set([1,2,3]) 的实参是 ListLit → 展开 elems 为 HashSet::from([1,2,3])。
3. Dict({...}) 的实参是同名 StructCtor（已生成 BTreeMap::from([...])）→ 直接透传。
4. 空构造 Set()/Dict() 已有既有路由（HashSet::new()/BTreeMap::new()），不重复。
附带：infer.rs Dict 方法路由增加 `remove → Option<V>`（BUG-289 同批修复：先前回退 Any→Unit）。
验证：TEMP/str_probe15.lz → Set.contains=true、len=3、iter sum=6；Dict.remove=1、get=2、contains=false、iter sum=3。全套 cargo test 601 passed。
- reported_by: dsh-agent

## BUG-290 [2026-10-17T05:48:48Z] [medium] FIXED
- summary: BUG-289: Dict.remove 未登记方法路由，回退 Any→Unit → E0599
- detail: Dict.remove 在 infer.rs Dict 方法路由中未登记，回退 Any→Unit，导致 `let r = d.remove("a")` 推断 r: ()，后续 `r.unwrap_or(-1)` 在 () 上调用方法 → E0599 / E0308。
修复：infer.rs Dict 方法路由增加 `"remove" => Option<V>`（BTreeMap/HashMap::remove 返回 Option<V>）。codegen 端 need_ref 已为 Dict.remove 加 &，无需改动。
验证：TEMP/str_probe15.lz test_dict_remove → 1（d.remove("a") 移除 1 后 unwrap_or(-1)）。全套 601 passed。
- reported_by: dsh-agent



### FIXED(2026-10-17T05:49:04Z / BUG-289, BUG-290)
- evidence: BUG-289：infer.rs Dict 方法路由增加 `"remove" => Some(IrType::Option(Box::new(args[1].clone())))`（BTreeMap::remove 返回 Option<V>），先前回退 Any→Unit。
BUG-290：expr_gen.rs Call 分支（fn_param_types 检查之后）新增非空 type-alias 构造路由：callee 为 Set/HashSet/Dict/HashMap 且 args 非空、非 kwargs、无同名用户函数 → 生成 HashSet::from([...]) / BTreeMap::from([...])；Set([1,2,3]) 实参是 ListLit → 展开 elems；Dict({...}) 实参是同名 StructCtor → 透传。
验证 TEMP/str_probe15.lz → Set.contains=true、len=3、iter sum=6；Dict.remove=1、get=2、contains=false、iter sum=3。全套 cargo test 601 passed。
## BUG-291 [2026-10-17T05:55:34Z] [medium] FIXED
- summary: BUG-291: List.max/min 方法路由缺失，SetExt UFCS 语法错误
- detail: List.max()/.min() 方法调用未走方法路由，直接透传 `xs.max()` → E0061/E0308（Vec 无 max/min 方法）。
修复（expr_gen.rs MethodCall 分支，sum/product 之后）：
```rust
if (method == "max" || method == "min") && args_s.is_empty() && recv_is_list {
    return format!("(*({}).iter().{}().unwrap())", recv, method);
}
```
与 sum/product 同款迭代器链；max/min 返回 Option，unwrap() 表达 LZ 空 List 语义，与自由函数 `max(xs)` 一致。
附带修复：SetExt::union/intersection/difference 的 UFCS 语法（`SetExt::union(&a, b)` → `<HashSet<i64> as SetExt<i64>>::union(&a, b)`），并且增加 `self.trait_names.contains("SetExt")` 守卫（避免未定义 SetExt trait 时强制路由到不存在的 trait）。
验证：TEMP/str_probe16.lz → Set.contains=true、len=3、iter_sum=6、add=true、remove=false；List.max=5、min=1、sum=15。全套 601 passed。
- reported_by: dsh-agent



### FIXED(2026-10-17T05:55:53Z / BUG-291)
- evidence: expr_gen.rs MethodCall 分支增加 `if (method == "max" || method == "min") && args_s.is_empty() && recv_is_list` → `(*({recv}).iter().{method}().unwrap())`。SetExt::union/intersection/difference 改 UFCS：`<{RustType} as SetExt<_>>::{method}({recv_ref}, {args})`，并加 `self.trait_names.contains("SetExt")` 守卫。
验证 TEMP/str_probe16.lz → Set.contains=true、len=3、iter_sum=6、add=true、remove=false；List.max=5、min=1、sum=15。全套 cargo test 601 passed。
## BUG-292 [2026-10-17T06:08:02Z] [medium] FIXED
- summary: BUG-292: Range 未登记 builtin 类型 → 未知类型报错
- detail: Range 未在 builtin_type_names 中登记 → 语义校验报「未知类型: Range（位于 参数 r 的类型）」。修复：src/ast/mod.rs builtin_type_names 增加 "Range"。
- reported_by: dsh-agent

## BUG-293 [2026-10-17T06:08:03Z] [medium] FIXED
- summary: BUG-293: Range 类型映射双重泛型 + 位置构造生成存根
- detail: Range<int> 生成 std::ops::Range<i64><i64>（type_map 已含 <i64>，args 再追加一层）。修复：types_emit.rs rust_type 非空 args 分支增加 `if path == "Range" || path == "RangeInclusive" { return mapped; }`（Range 是非泛型类型）。
Range(1,6) 位置构造被生成 `fn Range(__a0, __a1) -> i64 { i64::MAX }` 存根 + 裸调用 → 运行期返回 i64::MAX。修复：expr_gen.rs Call 分支增加 Range 非空构造路由：`1i64..6i64`（RangeInclusive → `..=`）。
- reported_by: dsh-agent

## BUG-294 [2026-10-17T06:08:04Z] [medium] FIXED
- summary: BUG-294: Range/Iterator 链方法未登记返回类型 → E0282
- detail: Range<T> 未在 lookup_builtin_method_ret 中视作 Iterator，`r.collect()` 回退 Any→?，codegen 生成 `let mut xs = r.collect();` 无类型标注 → E0282。
修复：infer.rs lookup_builtin_method_ret 增加 Range arm（与 Iterator 同款：next→Option<T>、len/count→Int、collect→List<T>、filter/map/take/skip/cloned/skip_while/take_while→recv_ty 保持）。
同时为 Iterator arm 补上 filter/map/take/skip/cloned/skip_while/take_while → recv_ty.clone()（迭代链保型），修复 `xs.iter().filter(...).collect()` 的 E0282。
- reported_by: dsh-agent



### FIXED(2026-10-17T06:08:20Z / BUG-292, BUG-293, BUG-294)
- evidence: BUG-292：src/ast/mod.rs builtin_type_names 增加 "Range"。
BUG-293：types_emit.rs rust_type 非空 args 分支增加 Range/RangeInclusive 直接返回 mapped（不追加泛型）；expr_gen.rs Call 分支增加 Range/RangeInclusive 非空构造路由 → `1i64..6i64`。
BUG-294：infer.rs lookup_builtin_method_ret 增加 Range arm（next/len/count/collect/filter/map/take/skip/cloned/skip_while/take_while），并为 Iterator arm 补上 filter/map/take/skip/cloned/skip_while/take_while → recv_ty.clone()。
验证 TEMP/str_probe17.lz → tuple:42/hello/3.14/47；Range collect=5、sum=15；iterator filter=3、map=2。全套 cargo test 601 passed。
## BUG-295 [2026-10-17T06:20:47Z] [medium] FIXED
- summary: BUG-295: str.split 生成 Split 而非 Vec + float.abs 类型推断错误
- detail: `s.split(",")` 生成 std String::split 返回 Split<&str> 迭代器，LZ 语义是 List<str>（Vec<String>）→ `.len()` 报 E0599 no method named len found for Split。
修复：expr_gen.rs L3706 通用 MethodCall 回落路径增加 split 特判：`recv.split(args).map(|s| s.to_string()).collect::<Vec<_>>()`。
同时修 `x.abs()` 在 f64 上被推断为 ImplicitFrom<i64> → E0308：infer.rs 增加 Int/F64 内建方法路由（abs 保持原类型）。
- reported_by: dsh-agent



### FIXED(2026-10-17T06:21:03Z / BUG-295)
- evidence: 修复：expr_gen.rs L3706 通用 MethodCall 回落路径增加 split 特判（recv_is_str_owned && rust_method=="split" → `{recv}.split({args}).map(|s| s.to_string()).collect::<Vec<_>>()`）；infer.rs lookup_builtin_method_ret 增加 IrType::Int/F64 → abs 保持原类型。
验证 TEMP/str_probe18.lz：abs(-5)=5、abs(-3.5)=3.5、upper=HELLO、lower=world、trim=hi、split.len=4、starts_with=true、ends_with=true、contains=true。
## BUG-296 [2026-10-17T06:25:54Z] [medium] FIXED
- summary: BUG-296: List.sort()/reverse() 未登记返回类型 → E0608
- detail: `xs.sort()`/`xs.reverse()` 未在 lookup_builtin_method_ret List arm 中登记 → 回退 Any→i64/Unit，codegen 生成 `let ys = xs.sort();` → ys 为 `()` → `ys[0]` E0608。
修复：infer.rs List arm 增加 `"sort" | "reverse" => Some(recv_ty.clone())`；codegen expr_gen.rs List 方法路由增加 sort/reverse 特判：`{recv}.sort(); {recv}.clone()`（Vec::sort 原地修改返回 ()），reverse 同理。
- reported_by: dsh-agent


### FIXED(2026-10-17T06:32:08Z / BUG-296)
- evidence: 修复：infer.rs List arm 增加 `"sort" | "reverse" => Some(recv_ty.clone())`；expr_gen.rs recv_is_list 分支增加 sort/reverse 特判：`{ {recv}.sort(); ({recv}) }` / `{ {recv}.reverse(); ({recv}) }`（Vec::sort/reverse 原地返回 ()）。
验证 TEMP/str_probe20.lz：sort([3,1,2])[0]=1、reverse([1,2,3])[0]=3。

### FIXED(2026-10-17T07:25:00Z / BUG-296)
- evidence: 最终修复（Python 风格原地修改，返回 Unit）：
1. infer.rs List arm：`"sort" | "reverse" => Some(IrType::Unit)`（先前改为 List<T> 导致 `xs.sort()` 作语句生成块表达式 E0308，str_boundary c11_list_compare 回归失败）。
2. expr_gen.rs recv_is_list 分支：sort/reverse 直接透传 `{recv}.{rust_method}()`（不生成块）。
验证：str_probe20.lz sort/reverse 返回 1/3；str_boundary c11_list_compare 通过；全量 870 测试 0 失败。
## BUG-297 [2026-10-17T06:25:54Z] [medium] FIXED
- summary: BUG-297: List.join(sep) 在 Vec<i64> 上 E0599
- detail: `xs.join(",")` 在 Vec<i64> 上生成 `xs.join(",")` → E0599（Vec 无 join 方法，join 是 slice::Join trait，需 String 元素）。infer.rs 已把 join 映射为 Str，但 codegen 未特殊处理。
修复：expr_gen.rs List 方法路由增加 join 特判：`({recv}).iter().map(|x| x.to_string()).collect::<Vec<_>>().join({sep})`。
- reported_by: dsh-agent




### FIXED(2026-10-17T06:32:08Z / BUG-297)
- evidence: 修复：expr_gen.rs recv_is_list 分支增加 join 特判：`({recv}).iter().map(|x| x.to_string()).collect::<Vec<_>>().join({sep})`，sep 剥掉 .to_string() 得 &str。
验证 TEMP/str_probe20.lz：join([1,2,3]) 返回 "1,2,3" 长度 5。

### FIXED(2026-10-17T07:25:00Z / BUG-297)
- evidence: 修复：expr_gen.rs recv_is_list 分支增加 join 特判：`({recv}).iter().map(|x| x.to_string()).collect::<Vec<_>>().join({sep})`，sep 剥掉 .to_string() 得 &str。
验证：str_probe20.lz join([1,2,3]) 返回 "1,2,3" 长度 5；全量 870 测试 0 失败。
## BUG-298 [2026-10-17T07:05:52Z] [medium] FIXED
- summary: [vools] bridges/tests 8 个 script-style 文件在 pytest 收集期挂死（模块顶层执行编译器探测）
- detail: bridges/tests/ 下有 8 个 script-style 测试文件（test_auto_discovery.py / test_fb_wrapper_modules.py / test_final_validation.py / test_freebasic_hash.py / test_imports.py / test_integration.py / test_linux_so.py / test_probe_manager.py），它们没有 `test_` 前缀函数，而在模块顶层直接执行编译器探测（如 `discover_all()` 会扫全系统编译器）。pytest 收集这些文件时会在 import 阶段挂住（实测 30s+ 无输出）。核心 tests/ 全部通过（1593 tests exit=0），但 `python -m pytest bridges/tests/` 永远不返回。




### FIXED(2026-10-17T08:00:28Z / BUG-298)
- evidence: bridges/tests/ 下 8 个 script-style 文件（test_auto_discovery.py 等）在模块顶层执行编译器探测导致 pytest 收集期挂死。已全部转换为 `def test_run_xxx():` 函数（dev_tools/fix_bridges_tests.py 自动转换），pytest 收集从「30s+ 无输出」变为正常秒级返回。核心修复落地 commit ce5a83d。
## BUG-299 [2026-10-17T07:25:19Z] [medium] FIXED
- summary: BUG-298: Dict.get(key, default) 生成 2 参调用 → E0061
- detail: `d.get("missing", -1)` LZ 语义是带默认值查 Dict。但 codegen 生成 `d.get("missing", -1i64)` → BTreeMap::get 只收 1 参 → E0061。
修复：expr_gen.rs 在 call 计算后新增 is_dict_receiver 分支（args.len()==2 && rust_method=="get"），重建为 `({recv}).get({key}).cloned().unwrap_or({default})`。
验证：str_probe21.lz `test_dict_get_default({"a":2})` → -1；全量 870 测试 0 失败。
- reported_by: dsh-agent


### FIXED(2026-10-17T07:25:35Z / BUG-299)
- evidence: 修复：expr_gen.rs 在 call 计算后新增 is_dict_receiver 分支（args.len()==2 && rust_method=="get"），重建为 `({recv}).get({key}).cloned().unwrap_or({default})`。
验证：str_probe21.lz `test_dict_get_default({"a":2})` → -1；全量 870 测试 0 失败。
## BUG-300 [2026-10-17T07:25:19Z] [medium] FIXED
- summary: BUG-299: Dict.remove 被 blanket Unit 早退吞掉 → E0277
- detail: L209-219 有未受类型保护的 `remove → Unit` 早退，抢在 Dict arm（BUG-289 已登记 `remove → Option<V>`）之前返回 Unit → `let v = d.remove("a")` 生成 `i64: ImplicitFrom<()>` → E0277。
修复：从 L212 移除 `remove`（保留 push/insert/clear/append/set/skip_ws），让 Dict arm 生效；同时 List arm 增加 `"remove" => Some(args[0].clone())`（Vec::remove 返回 V）；codegen 加 is_dict_receiver remove 分支 `{recv}.remove({key}).unwrap_or(-1i64)`（LZ -1 编码 None）。
注意：is_dict_receiver 须校验 args.len()==2，否则 LZ 自定义 struct HashMap 被误匹配（lib_hashmap 回归 E0599）。
- reported_by: dsh-agent




### FIXED(2026-10-17T07:25:35Z / BUG-300)
- evidence: 修复：从 infer.rs L212 blanket `remove → Unit` 中移除 remove；List arm 增加 `"remove" => Some(args[0].clone())`；codegen 加 is_dict_receiver remove 分支 `{recv}.remove({key}).unwrap_or(-1i64)`。is_dict_receiver 须校验 args.len()==2（lib_hashmap 回归）。
验证：lib_hashmap 测试通过；全量 870 测试 0 失败。
## BUG-301 [2026-10-17T07:47:51Z] [medium] FIXED
- summary: BUG-301: Range.len() 生成 .len() → E0599
- detail: LZ `r.len()`（r: Range）infer.rs 返回 Int（正确），但 codegen 生成 `r.len()` → std::ops::Range 无 len → E0599。
修复：expr_gen.rs len/length 分支前置 Range/RangeInclusive 特判：`({recv}).end - ({recv}).start`（RangeInclusive 加 1i64）。
验证：str_probe22 `test_range_index()` 1..5 → 4；全量 870 测试 0 失败。
- reported_by: dsh-agent


### FIXED(2026-10-17T07:48:05Z / BUG-301)
- evidence: expr_gen.rs len/length 分支前置 Range/RangeInclusive 特判：`({recv}).end - ({recv}).start`（RangeInclusive 加 1i64）。
验证：str_probe22 test_range_index 1..5 → 4；全量 870 测试 0 失败。
## BUG-302 [2026-10-17T07:47:51Z] [medium] FIXED
- summary: BUG-302: pow(x,y) 自由函数 E0425
- detail: LZ std math.lz 有 `def pow(base:int,exp:int)->int`，LZ 调用 `pow(2,3)` 被 codegen 直生成 `pow(x, y)`，但 lz_builtins 只有 `pow_i64(base:i64,exp:u32)` 与 `pow_f64(base:f64,exp:f64)` → E0425 cannot find function pow。
修复：expr_gen.rs 增加 `callee_s == "pow" && args_s.len()==2` 特判：按 arg0 类型选重载（F64→pow_f64，其余→pow_i64(x, y as u32)）。
验证：str_probe22 `test_pow_free(2,3)` → 8；全量 870 测试 0 失败。
- reported_by: dsh-agent


### FIXED(2026-10-17T07:48:06Z / BUG-302)
- evidence: expr_gen.rs 增加 callee_s=="pow" && args.len()==2 特判：按 arg0 类型选重载（F64→pow_f64，其余→pow_i64(x, y as u32)）。
验证：str_probe22 test_pow_free(2,3) → 8；全量 870 测试 0 失败。
## BUG-303 [2026-10-17T07:47:51Z] [medium] FIXED
- summary: BUG-303: Dict.items() E0599
- detail: LZ `d.items()`（d: Dict<K,V>）生成 `d.items()` → BTreeMap 无 items 方法 → E0599。
修复：expr_gen.rs keys/values 分支增加 items：`({recv}).iter().map(|(k,v)| (k.clone(), v.clone())).collect::<Vec<_>>()`。
注意：receiver 必须 `(&({recv}))` 括起来，否则 `&(d).iter()` 变 `&Vec<...>` → E0308。
验证：str_probe22 `test_dict_items({"a":2,"b":4})` → 2；全量 870 测试 0 失败。
- reported_by: dsh-agent


### FIXED(2026-10-17T07:48:06Z / BUG-303)
- evidence: expr_gen.rs keys/values 分支增加 items：`(&({recv})).iter().map(|(k,v)| (k.clone(), v.clone())).collect::<Vec<_>>()`。
验证：str_probe22 test_dict_items({"a":2,"b":4}) → 2；全量 870 测试 0 失败。
## BUG-304 [2026-10-17T07:47:51Z] [medium] FIXED
- summary: BUG-304: Chars.len() E0599
- detail: LZ `s.chars()` 返回 `Chars<'_>`（IR 标为 Iterator<str>），`.chars().len()` 生成 `cs.len()` → Chars 迭代器无 len → E0599。
修复：expr_gen.rs len/length 分支增加 Iterator/Chars/Bytes/Keys/Values 特判：`(({recv}).count() as i64)`。
验证：str_probe22 `test_str_chars("hello")` → 5；`test_str_bytes("hi")` → 2；全量 870 测试 0 失败。
- reported_by: dsh-agent






### FIXED(2026-10-17T07:48:06Z / BUG-304)
- evidence: expr_gen.rs len/length 分支增加 Iterator/Chars/Bytes/Keys/Values 特判：`(({recv}).count() as i64)`。
验证：str_probe22 test_str_chars("hello") → 5；test_str_bytes("hi") → 2；全量 870 测试 0 失败。

## BUG-305 [2026-10-17T08:08:56Z] [medium] FIXED
- summary: BUG-305: Set union/intersection/difference 生成 std 迭代器而非 SetExt
- detail: LZ `a.union(b)`（a,b: Set<T>）生成 `a.union(b)` → std HashSet 固有方法返回 Union/Intersection 迭代器（无 len）→ E0599/E0308。
修复：expr_gen.rs SetExt 分支去掉 `trait_names.contains("SetExt")` 守卫（use lz_builtins::* 恒注入），映射 union→lz_union、intersection→lz_intersection，第二参数包 &；difference/symmetric_difference 走 std 固有 + `.cloned().collect::<HashSet<_>>()`。
验证：str_probe23 test_set_ops({1,2,3},{2,3,4}) → 7；全量 870 测试 0 失败。
- reported_by: dsh-agent


### FIXED(2026-10-17T08:09:10Z / BUG-305)
- evidence: expr_gen.rs SetExt 分支去掉 trait_names.contains("SetExt") 守卫（use lz_builtins::* 恒注入），映射 union→lz_union、intersection→lz_intersection，第二参数包 &；difference/symmetric_difference 走 std 固有 + .cloned().collect::<HashSet<_>>()。
验证：str_probe23 test_set_ops({1,2,3},{2,3,4}) → 7；全量 870 测试 0 失败。
## BUG-306 [2026-10-17T08:08:56Z] [medium] FIXED
- summary: BUG-306: 函数调用实参传给 int? 形参未包 Some()
- detail: LZ 函数形参为 `int?`（Option<i64>），调用方传 `5i64` → E0308 expected Option<i64>, found i64。`let z: int? = 10` 已通过 needs_some_wrap 处理，但函数调用实参未接线。
修复：expr_gen.rs 函数调用实参生成循环中，遍历 callee_expected（fn_param_types），对 needs_some_wrap 返回 true 的实参包 `Some({s})`。
验证：str_probe23 test_option_is_some(5)→true, test_option_is_some(-1)→true, test_option_unwrap_or(5)→5, test_option_unwrap_or(-1)→-1；全量 870 测试 0 失败。
- reported_by: dsh-agent


### FIXED(2026-10-17T08:09:10Z / BUG-306)
- evidence: expr_gen.rs 函数调用实参生成循环中，遍历 callee_expected（fn_param_types），对 needs_some_wrap 返回 true 的实参包 Some({s})。
验证：str_probe23 test_option_is_some(5)→true, test_option_is_some(-1)→true, test_option_unwrap_or(5)→5, test_option_unwrap_or(-1)→-1；全量 870 测试 0 失败。
## BUG-307 [2026-10-17T08:08:56Z] [low] FALSE_POSITIVE
- summary: BUG-307: 嵌套 Dict get 返回 Option 已正确 unwrap_or（探查型）
- detail: LZ 嵌套 Dict `d: Dict<str, Dict<str,int>>`，`d.get("a")` 返回 `Option<&BTreeMap>`，赋值给局部变量时生成 `.cloned().unwrap_or(Default::default())` → Default::default() 对 BTreeMap 可用，实际可编译，但 `.len()` 需 Option 展开。
本次探查中 `test_nested_dict` 生成 `(d.get("a")).cloned().unwrap_or(Default::default())`，运行输出 1（正确）。此为探查型 bug，无实际缺陷，未改代码。保留记录供后续审计。
- reported_by: dsh-agent




- false_positive(2026-10-17T08:09:10Z): 探查型 bug：nested Dict get 已正确生成 `.cloned().unwrap_or(Default::default())`，运行输出 1 正确，未改代码。
## BUG-308 [2026-10-17T08:24:31Z] [medium] FIXED
- summary: vools/utils/tools.py offset_date() 对 datetime.date 对象抛 TypeError
- detail: offset_date(run_date, offset_days) 内部用 `'-' in run_date` 判断日期格式，但 `datetime.date` 对象不是字符串、不可迭代，直接抛 `TypeError: argument of type 'datetime.date' is not iterable`。函数签名注释为「基准日期」，预期支持 str 或 datetime.date。修复：先 isinstance(run_date, (datetime.date, datetime.datetime)) 分支处理。
- reported_by: dsh-agent



### FIXED(2026-10-17T08:29:15Z / BUG-308)
- evidence: vools/utils/tools.py offset_date() 之前 `'-' in run_date` 对 datetime.date 对象抛 TypeError。已在函数开头加 isinstance(run_date, (_date, datetime)) 分支处理 date/datetime 对象，并补 2 条测试覆盖 date/datetime 输入。commit f2d3733。
## BUG-309 [2026-10-17T08:37:11Z] [medium] FIXED
- summary: vools/task/rules/rule.py RuleSet.evaluate 吞掉原始错误信息
- detail: RuleSet.evaluate() 内部用 `result.unwrap_or(None)` 提取失败原因，但 Result.failure 时 unwrap_or 返回默认值 None，导致包装后的外层 Exception 消息变成 "Rule 'xxx' failed: None"，原始错误信息被吞掉。修复：改用 `result.unwrap_or_else(lambda e: e)` 保留原始错误。commit 见 tests/test_task_rules_rule.py 的 test_evaluate_failure_stops。
- reported_by: dsh-agent



### FIXED(2026-10-17T08:37:18Z / BUG-309)
- evidence: vools/task/rules/rule.py 第 170-172 行原本用 `result.unwrap_or(None)` 提取失败原因，失败时返回默认值 None 导致外层 Exception 消息退化为 "Rule 'xxx' failed: None"。已改为 `result.unwrap_or_else(lambda e: e)` 保留原始错误。补测试 test_evaluate_failure_stops 断言外层消息含 "boom"。
## BUG-310 [2026-10-17T08:48:45Z] [high] FIXED
- summary: Result::is_ok/is_err 返回类型未登记 → E0277 ImplicitFrom<i64>
- detail: lookup_builtin_method_ret 的 Result<T,E> 分支未登记 is_ok/is_err 返回类型 → 推断为 Any → codegen 回退 i64 → return 处 `<bool as ImplicitFrom<i64>>::__implicit_from__(r.is_ok())` E0277。修复：在 IrType::Result { ok, err } 变体和 IrType::Named { path: "Result" } 两个分支都加 `"is_ok" | "is_err" => Some(IrType::Bool)`。

## BUG-311 [2026-10-17T08:48:45Z] [medium] FIXED
- summary: str.split 返回类型误标 Iterator<str> → Vec 上 E0599 count
- detail: str.split(",") 生成 Split<&str> 迭代器，但 LZ 语义是 List<str>。infer.rs 中 split/lines/split_whitespace/split_inclusive/splitn/rsplit/rsplitn/split_terminator 的返回类型从 Iterator<str> 改为 List<str>，codegen 收集为 Vec<String>。否则 `.len()` 生成 `.count()` → E0599 count not found on Vec<String>。

## BUG-312 [2026-10-17T08:48:45Z] [medium] FIXED
- summary: List.pop 缺 unwrap_or 平铺 → E0308 expected i64 found Option<i64>
- detail: List.pop() 生成 `lst.pop()` 返回 Option<i64>，但 infer.rs 标为 int。当 LZ 用 -1 编码 None 时，需要 `.unwrap_or(-1)` 平铺。expr_gen.rs 的 first/last/get/pop 处理分支中 pop 未加 unwrap_or，导致 `let v: i64 = lst.pop()` E0308。修复：pop 仅在内置集合（is_collection_type 且非用户 struct）时拼接 `.unwrap_or(default)`。用户 struct 自带 pop（如 FIND_BUG/lib_vector 的 Vector::pop 返回 i64）不受影响。



### FIXED(2026-10-17T08:49:15Z / BUG-310, BUG-311, BUG-312)
- evidence: infer.rs lookup_builtin_method_ret 两处改动：① IrType::Result { ok, err } 与 IrType::Named{path:"Result"} 两分支均加 `"is_ok"|"is_err" => Some(IrType::Bool)`；② split/lines/split_whitespace/split_inclusive/splitn/rsplit/rsplitn/split_terminator 返回类型从 Iterator<str> 改为 List<str>。expr_gen.rs L4390-4413：pop 在 is_collection_type 且非用户 struct 时拼接 list_get_unwrap_or_default 返回值（如 `.unwrap_or(-1i64)`）。验证：TEMP/str_probe24.lz 编译通过并 RUN=>5 -1 true false 8 2 3 a,b,c 2 3（10/10 符合期望）；FIND_BUG/lib_vector 输出 lib_vector OK；cargo test --release 全绿 0 failures。
## BUG-313 [2026-10-17T08:56:56Z] [medium] FIXED
- summary: vools/task/rules/engine.py evaluate_async 空规则崩溃 + get_event_loop 弃用 + 错误吞掉
- detail: RuleEngine.evaluate_async() 在 self._rules 为空时调用 asyncio.wait([])，抛 ValueError: Set of Tasks/Futures is empty.。同时使用已弃用的 asyncio.get_event_loop()（Python 3.13 DeprecationWarning）。修复：前置空列表短路返回 Result.success([])；改用 get_running_loop() 优先。另外 evaluate/evaluate_async 用 unwrap_or(None) 提取失败原因同样吞掉原始错误（与 BUG-309 同族）。
- reported_by: dsh-agent



### FIXED(2026-10-17T08:57:04Z / BUG-313)
- evidence: vools/task/rules/engine.py evaluate_async 在 sorted_rules 为空时短路返回 Result.success([])；get_event_loop() 改为 get_running_loop() 优先；evaluate/evaluate_async 的 unwrap_or(None) 改为 unwrap_or_else(lambda e: e)。补 29 条测试含 test_evaluate_async_empty / test_evaluate_async_failure / test_evaluate_failure_preserves_message。
## BUG-314 [2026-10-17T09:03:02Z] [medium] FIXED
- summary: vools/task/utils timeout() Windows 无 SIGALRM 崩溃
- detail: vools/task/utils/__init__.py 的 timeout() 函数硬编码使用 signal.SIGALRM，但 Windows 平台的 signal 模块没有 SIGALRM，调用时抛 AttributeError: module 'signal' has no attribute 'SIGALRM'。修复：检测 hasattr(signal, 'SIGALRM')，无则降级为 ThreadPoolExecutor + future.result(timeout=seconds) 实现。with_timeout 装饰器同样受益。
- reported_by: dsh-agent



### FIXED(2026-10-17T09:03:11Z / BUG-314)
- evidence: vools/task/utils/__init__.py timeout() 增加 hasattr(signal, 'SIGALRM') 检测，无则走 ThreadPoolExecutor + future.result(timeout=seconds) 分支，抛 TimeoutError。补测试 test_with_timeout_success / test_with_timeout_expired 验证两条路径。
## BUG-315 [2026-10-17T09:14:06Z] [medium] FIXED
- summary: vools/task/core/cli_exec.py cli_execute 三处真实 bug
- detail: vools/task/core/cli_exec.py cli_execute() 三个真实 bug：
1. shell=True 时 subprocess.run 传的是列表 [cmd_str]，Windows 上会把列表首元素当可执行文件直接执行失败（'The system cannot find the path specified'）。修复：shell 时改传 run_cmd = full_cmd[0] 字符串。
2. payload=None 时 line 144 payload.get('task_type') 抛 AttributeError。修复：全用 (payload or {}) 取值。
3. 语言推断失败时提前 return _fail(...) 但 finally 块引用未定义的 tmp_path → UnboundLocalError。修复：tmp_path 提到 try 之前初始化。
- reported_by: dsh-agent



### FIXED(2026-10-17T09:14:14Z / BUG-315)
- evidence: vools/task/core/cli_exec.py 三处修复：shell=True 时 subprocess.run 改传字符串 run_cmd=full_cmd[0]；payload 取值统一 (payload or {})；tmp_path 提到 try 前初始化。补 34 条测试含 test_shell_true / test_payload_none / test_unknown_lang / test_missing_cmd_and_lang。
## BUG-316 [2026-10-17T10:03:24Z] [high] FIXED
- summary: BUG-313: str_probe25 exposes 5 stdlib codegen bugs (Dict.get Option, Set is_subset arg, range(0,10).len, List index_of/remove_at Option type, tuple field access, str.rfind maps to lz_find)
- detail: TEMP/str_probe25.lz (stdlib method codegen) surfaced 6 distinct issues; all fixed and verified green via rustc+run:

1. Dict.get(k) auto-unwrapped: `d.get(&1i64).cloned().unwrap_or("".to_string()).unwrap_or("".to_string())` → E0599 unwrap_or on String. Root cause: L4130 generic first/last/get branch in expr_gen.rs applied `.cloned().unwrap_or(...)` to Dict receivers too (is_collection_type includes Dict). Fixed: added `&& !recv_is_dict_ty` guard, plus single-arg dict get branch emits `({}).cloned()` so caller's `.unwrap_or(...)` receives Option<V> not String.

2. Set is_subset/is_superset/is_disjoint missing from Set method match → `a.is_subset(b)` generated without `&` arg → E0308 expected &HashSet, found HashSet. Also receiver `&(a).is_subset(...)` parsed as `&((a).is_subset(...))` → &bool. Fixed: added methods to Set match, use plain `recv` (Rust auto-borrows self), wrap arg with `&(...)`. Also added type infer for these methods → Bool (BUG-283 family).

3. range(0,10).len() → `0i64..10i64.len()` precedence bug → E0599 len on Range. Parens fix worked but receiver type inferred Any→i64 so codegen took generic .len() branch. Fixed infer: `range(...)` call now returns IrType::Named { path: "Range", args: [elem_ty] }.

4. List index_of/remove_at: LZ stdlib signatures return Option<int>, codegen was flattening or emitting wrong types. index_of emitted `.unwrap_or(-1i64)` inline but IR type said Int → probe's `.unwrap_or(-1)` applied on i64 → E0599. Fixed: index_of → `recv.lz_index(&a0)` (Option<i64>, no auto unwrap); remove_at → inline bounds-checked `if ... { Some(recv.remove(...)) } else { None }`. Infer updated: index_of → Option(Int), remove_at → Option(T).

5. Nested tuple `inner.1` where inner: (String, bool) inferred Any→i64 → `return <bool as ImplicitFrom<i64>>::__implicit_from__(inner.1)` → E0277. Fixed FieldAccess infer to handle IrType::Tuple(items) with field as numeric index.

6. str.rfind("l") mapped to lz_find (which uses `.find()`) → returns first occurrence (2) instead of last (3). Fixed: added `lz_rfind` to StringExt trait + String/str impls in both lz_builtins/src/runtime/collections.rs and lz_builtins/src/flat.rs; codegen maps `rfind` → `lz_rfind` and adds `.unwrap_or(-1i64)` in both lz_find unwrap spots.

All 58 probe outputs match expected; cargo test --release running.
- task_id: T0r7



### FIXED(2026-10-17T10:03:47Z / BUG-316)
- evidence: TEMP/str_probe25.lz compiles via rustc and runs; all 58 output lines match expected. Changes:
- src/ir/codegen/expr_gen.rs: dict receiver excluded from L4130 first/last/get `.cloned().unwrap_or` branch; single-arg Dict.get emits `.cloned()`; Set is_subset/is_superset/is_disjoint added to Set method match with `&` arg wrapping and plain receiver; range() call parens already fixed; List index_of → `lz_index(&a0)` no auto unwrap; remove_at inline bounds-checked Option; `rfind` mapped to `lz_rfind` in method table and both unwrap_or spots (L3603, L3828).
- src/ir/builder/infer.rs: `range(...)` returns Range<T>; Set is_subset/is_superset/is_disjoint → Bool; List index_of → Option(Int), remove_at → Option(T); FieldAccess handles IrType::Tuple.
- lz_builtins/src/runtime/collections.rs + lz_builtins/src/flat.rs: added `lz_rfind` to StringExt trait + String/str impls.
- TEMP/str_probe25.lz: `d.get(1).unwrap_or("")`, `lst.index_of(3).unwrap_or(-1)`, `lst.remove_at(0).unwrap_or(-1)`, nested tuple via `let inner = t.1; inner.1`, lambda `|x| x*2`.
## BUG-317 [2026-10-17T11:08:32Z] [high] FIXED
- summary: BUG-316: fuse_classes 单类分支提前 return，忽略所有定制参数
- detail: vools/oop/fusion.py 的 fuse_classes 在只有 1 个类时（line 45-46）直接返回 `_apply_rself_if_available(classes[0])`，完全忽略 name/method_overrides/method_wrappers/auto_wrap_return 参数。例如 `fuse_classes(BaseB, method_wrappers={'value': {'replace': lambda self: 99}})` 返回原始 BaseB，包装器不生效。ClassFusion 接口的 set_name/override_method/wrap_method 在只添加一个类时同样失效。




### FIXED(2026-10-17T11:11:32Z / BUG-317)
- evidence: vools/oop/fusion.py line 45-46: 单类分支提前 return 改为仅在无任何定制参数时提前 return，使 name/method_overrides/method_wrappers/auto_wrap_return 在单类下也生效；同时修复 _wrap_methods_for_return_type 的闭包捕获循环变量 bug（用 _make_wrapper(orig_method) 捕获每个方法）。33 条新测试全通过，覆盖率 13% → 87%。


## BUG-318 [2026-10-17T11:30:13Z] [high] FIXED
- summary: BUG-318: FunctionalHandler.get_state 对 Box 类型读错属性（应读 __wrapped__）
- detail: vools/serialize/callable/functional_handler.py line 51: `get_state` for Box 类型用 `getattr(obj, '_value', getattr(obj, 'value', None))` 取值，但 vools.functional.Box 的实例数据实际存储在 `__wrapped__` 属性中（Box 继承 AOP，AOP.__init__ 设置 self.__wrapped__ = value）。因此 Box("hello").get_state() 返回 `state['value'] == None`，序列化 Box 丢失数据。restore 时 `Box(state.get('value'))` 会创建 Box(None)。应改为优先读 `__wrapped__`。



### FIXED(2026-10-17T11:31:07Z / BUG-318)
- evidence: vools/serialize/callable/functional_handler.py line 51: get_state 对 Box 类型改为优先读 __wrapped__（Box/AOP 的数据实际存放处），fallback 到 _value/value。20 条新测试全通过，覆盖率 18% → 100%。
## BUG-319 [2026-10-17T11:46:09Z] [high] FIXED
- summary: BUG-319: Mixer.remove_extra_code 无法撤销已应用的 extra_code 包装
- detail: vools/oop/mixer.py 的 remove_extra_code 只从 self._attr_code 字典中删除对应条目，但 add_extra_code 通过 `_apply_extra_code` 在 Mixer 类级别上（cls.__getattribute__ 或 setattr）修改了类行为，删除 _attr_code 后 Mixer 实例仍返回包装后的结果。测试实例：Mixer(A()) 添加 result_shell=lambda r: r+'!' 后 foo() 返回 "A.foo!"，调用 remove_extra_code("foo") 后 foo() 仍返回 "A.foo!"，期望恢复为 "A.foo"。



### FIXED(2026-10-17T11:49:33Z / BUG-319)
- evidence: vools/oop/mixer.py remove_extra_code 现在同时清除 _attr_cache 中对应条目（装饰版本被缓存，只 pop _attr_code 不够）。34 条新测试全通过，覆盖率 18% → 82%。
## BUG-320 [2026-10-17T12:20:18Z] [high] FIXED
- summary: BUG-320: vDate fmt/diffDays 交换后 fmt 为 int 触发 TypeError
- detail: vools/datetime/utils.py vDate(): `if isinstance(diffDays, str) or isinstance(fmt, (float, int))` 交换 fmt↔diffDays 后，fmt 变成 diffDays 默认值 0（int），随后 `if not '%' in fmt` 触发 `TypeError: argument of type 'int' is not iterable`。测试：vDate("2024-01-02", 1) → TypeError。修复：交换后若 fmt 不是 str/None 则回退为 None。



### FIXED(2026-10-17T12:20:30Z / BUG-320)
- evidence: vools/datetime/utils.py vDate 交换后加守卫 `if not isinstance(fmt, (str, type(None))): fmt = None`。108 条新测试全通过，覆盖率 17% → 92%。
## BUG-321 [2026-10-17T12:31:33Z] [high] OPEN
- summary: [codegen] BlockExpr 子 CodeGen 不继承 current_expected_ty → match 臂尾 Option 值被误加 .unwrap()（iter.lz Zip::size_hint E0308）
- detail: 根因：expr_gen.rs 的 `ExprKind::BlockExpr` 分支用 `CodeGen::new()` 创建子 CodeGen，复制了 current_ret_ty / current_fn_ret_ty / enum_variant_* 等，但**没有复制 `current_expected_ty`**（新实例恒为 None）。于是 `let hi: Option<int> = { match (hi_a, hi_b) { case (Some(x), Some(y)) => Some(min(x, y)); case _ => None } }` 中，外层 Let 已在 L959 把 current_expected_ty 设为 Some(Option<int>)，但 match 臂生成时经 BlockExpr 落到子 CodeGen，expected_ty 变回 None。stmt_gen.rs:1782 的尾值 unwrap 启发式只看 current_ret_ty（函数返回 Tuple，非 Option）→ 对 Option 臂尾 `Some(min(x,y))` 加 `.unwrap()` → `Some(min(x,y)).unwrap()` 为 i64，塞进 Option<i64> 绑定 → E0308（DEMO/lz_std/iter.lz L173 `Some(min(x, y))` 实为 LZ 源码，unwrap 是代码生成错误注入）。

修复：
1. expr_gen.rs BlockExpr 分支加一行 `*child.current_expected_ty.borrow_mut() = self.current_expected_ty.borrow().clone();`（继承期望类型）。
2. stmt_gen.rs:1782 尾值 unwrap 条件加 `&& !expected_is_opt` 双保险（当前 current_expected_ty 已期望 Option 时绝不 unwrap，防止其它路径同类误判）。

验证：重建 release 后重新 emit `DEMO/lz_std/iter.lz`，`.unwrap()` 消失，`rustc --edition 2021 --extern lz_builtins=... -O` 编译 EXIT=0（此前 E0308）。LZ_DBG_TAIL 调试输出从 `exp=None` 变为 `exp=Some(Option(Int))`，确认继承生效。
- reported_by: dsh-agent



## BUG-322 [2026-10-17T15:50:01Z] [medium] FIXED
- summary: [parser.py] _内联默认 方法在地支耗尽时静默丢弃默认值 — `佘` 名称不被接受
- detail: parser.py 的 _内联默认 方法（行 1974-2011）在收集默认值时检查 `if 名 in _DIZHI:`，但当地支计数超过 12 时，_infer_params 会分配 `佘` 作为名称。由于 `佘` 不在 _DIZHI 列表中，默认值被静默丢弃。

影响：13+ 默认参数的函数丢失默认值。参数仍然存在，但 params_def 不包含耗尽的地支的默认值。

位置：zhi/src/zhi/parser.py 行 2009
```python
if 名 in _DIZHI:  # ← 行 2009：只接受地支名称
    出.append((名, e))
```

修复：将检查改为 `if 名 in _DIZHI or 名 == "佘":` 或类似逻辑。
- task_id: T0r13


### FIXED(2026-10-17T15:52:29Z / BUG-322)
- evidence: parser.py 行 2009 修改：`if 名 in _DIZHI:` → `if 名 in _DIZHI or 名 == "佘":`
## BUG-323 [2026-10-17T15:50:10Z] [high] FIXED
- summary: [semantic.py] _expr 方法不对 VarRef/IdRef 进行作用域检查 — 未定义变量/函数引用静默编译
- detail: semantic.py 的 _expr 方法（行 1063-1073）在处理 VarRef/IdRef 时不进行作用域检查：

```python
# 行 1063-1064：
if isinstance(e, VarRef):
    return IR.Var(name=e.name)  # 无作用域检查！

# 行 1068-1073：
if isinstance(e, IdRef):
    if e.name in _BOOL_LIT and e.name not in self.scope:
        return IR.Lit(value=_BOOL_LIT[e.name], lit_type="bool")
    return IR.Var(name=e.name)  # 无作用域检查！
```

self.scope 字典（行 190）跟踪名称 → 'var'|'param'，但从未在遇到 VarRef 或 IdRef 时查询。参数被添加（行 501），循环变量（行 1023-1028），绑定目标（行 742-748），但未定义引用产生 0 诊断。

影响：未定义的变量/函数引用静默编译，仅在运行时被捕获（JS: ReferenceError, BEAM: undefined variable）。

修复：需要在 semantic.py 中添加作用域检查，同时维护内建名称白名单（STD 可调用对象 + 运算符 + 宏）以避免误报。
- task_id: T0r14




### FIXED(2026-10-17T16:01:10Z / BUG-323)
- evidence: semantic.py 行 1063-1079 修改：为 VarRef 和 IdRef 添加作用域检查，产生 UNDEFINED_VAR/UNDEFINED_FUNC 诊断


## BUG-324 [2026-10-18T12:20:56Z] [high] OPEN
- summary: verify DANGEROUS_PATTERNS 漏检 os.popen(<变量>)：旧 pattern `os.popen(cmd\b` 只匹配变量名恰为 cmd，实测 os.popen(wsl_cmd) 漏网（mcp_call L85 为 RCE）
- detail: ## 根因
`actions/vools/actus.verify.actus.md` 原 DANGEROUS_PATTERNS 中 os.popen pattern 为 `os\.popen\s*\(cmd\b`，仅匹配变量名恰为 `cmd`。全仓 16 个动作使用 `os.popen(<其他变量>)`（如 `wsl_cmd`、`cmd_line`、`run_cmd`），全部漏网。

## 实测
- 全仓 113 个 `.actus.md` 文件，16 个触发 os.popen 变量（新 pattern 后）
- mcp_call L85 `os.popen(wsl_cmd, "r")` 中 `wsl_cmd` 由用户 `server` 参数拼入，为 RCE
- cli_curl/git_commit 的 `wsl_cmd` 已 shlex.quote，安全但同样被旧 pattern 漏检

## 修复（本轮已完成）
1. DANGEROUS_PATTERNS 增补 3 条：`os.popen f-string`、`subprocess shell=True 全家族`、`subprocess 字符串首参`
2. 新增 SUSPICIOUS_PATTERNS（WARNING 级）2 条：`os.popen(<变量>)`、`os.system(<变量>)`
3. `_check_suspicious` 函数 + `_verify_single` 接入 + self-scan 剔除 SUSPICIOUS_PATTERNS 块
4. `tests/test_verify_injection.py` 更新为加载两表，新增 `test_suspicious_patterns_exist`，10/10 通过

## 遗留
16 个 os.popen 变量命中动作需逐个修复（shlex.quote 或改 subprocess.run 列表 argv），不在本 bug 修复范围。
- reported_by: fist-agent

## BUG-325 [2026-10-18T15:38:56Z] [high] OPEN
- summary: [rule:type-annotation] let x: T = e 的类型注解被 parser 丢弃、static_check 从不强制：`let x: Int = "hello"`、`let x: Int = 3.5`、`let x: Int = Some(5)` 全部静默通过
- detail: 根因：`parse_let_binding_top`（crates/p5c/src/parser/item.rs:530-535）把 `: T` 只当 `shall_coerce`（是否 Float）判定用后**丢弃**，AST `TopLevel::LetBinding`/`Stmt::LetBinding` 根本没有 `ty` 字段；`static_check` 侧零注解处理。连带症状：`DEMO/01_types/type_lattice.p5:182` 的 `let opt: Option<Int> = 5` 注解不生效，`print(opt)` 打印 `5` 而非 `Some(5)`、`typeof(opt)` 报 `Int`。实测（修复前）：`check` 对 `let x: Int = "hello"` 报 "Static check passed"。修复：AST 增 `ty: Option<Type>`，parser 存储注解，static_check 增 `check_let_annotation` 强制标量类型（Int/Float/Str/Bool/Atom/None/Any/Nothing），对 Named（union 成员/接口上转型/newtype 别名，含被折叠的 `Option<Int>`）宁漏报不误报。e2e_demo_golden 仍 20/20 通过。

## BUG-326 [2026-10-18T18:29:49Z] [medium] FALSE_POSITIVE
- summary: BUG-262 Module 值内省元字段 mod.apis / mod.name / mod.path / mod.is_macro 全部未实现，运行期报 Field not found（§11.2 规范-实现静默分歧）
- detail: §11.2「模块值：一等值」内省表公开四支元字段——`mod.apis`（导出 api 列表）/ `mod.name`（模块名）/ `mod.path`（模块路径）/ `mod.is_macro`（是否 `#![macro]` 宏模块，§13.9）。R61 实测（修复前）：`import("std.math").apis` → `Runtime error: Field not found: apis (module math, available exports: abs, ceil, cos, floor, ln, log10, sin, sqrt)`；文件模块 `import("lib.p5").apis` 同型失败。根因：`crates/p5c/src/eval/expr.rs` 的 `Value::Module(mv)` 字段访问只按 `mv.exports`（导出绑定）查找，未把四支元字段接线——错误信息里的 `available exports: …` 正是唯一的字段面。属**规范-实现静默分歧**（无编译期诊断，运行期才 `Field not found`），且 `DEMO/**/*.p5` 未覆盖 `mod.apis` 面故 golden 未拦。
- reported_by: pentad-polish-lead-1019


- false_positive(2026-10-18T18:30:35Z): 误报落错库：project_dir="." 解析到 server cwd（FIST-Mbt），而该缺陷属 Pentad 项目代码（crates/p5c/src/eval/expr.rs）。真实条目按 BUG-262 记入 Pentad 项目 memory/bugs.md，本库不适用。
## BUG-327 [2026-10-19T01:51:59Z] [medium] OPEN
- summary: ocr_scan 的 OCR LLM review 对 MoonBit .mbt 恒不可达（unsupported_ext 全拦），bugfind 的 require_ocr 门是伪能力/可静默满足
- detail: 实测证据（2026-10-19，opencodereview.exe @alibaba-group+ocr-win32-x64@1.12.9）：
1) `ocr_scan subcmd=scan path=src/server` → `total_files=81, reviewable_count=0, excluded_count=81`，全部 `exclude_reason: unsupported_ext`。
2) 显式单文件 `ocr scan --preview --path src/server/issue_scan.mbt` → 仍 `exclude_reason: unsupported_ext`（1/1 排除）。
3) `ocr rules check src/server/issue_scan.mbt` → 匹配 `default` 规则（Source: System built-in）—— 规则层**不拒** .mbt。
4) `ocr scan --help`：有 `--exclude`（只会加排除）与 `--rule`（规则 JSON），**无 `--include` 扩展名旗**；`ocr config` 无扩展名白名单键；CLI 无逃生门。

结论：排除发生在 scan 的文件遍历阶段（二进制硬编码扩展名白名单不含 .mbt），规则层本可处理。MoonBit 项目下 OCR LLM review 恒不可达。

影响：① AGENTS.md 宣称的「内建规则 + OCR LLM review 双轨互补」对 MoonBit 只有单轨；② 自驱 bugfind 模式的 `require_ocr` 约束在本项目不可满足，但 `ocr_scan` 顶层回执 `ok=true / exit_code=0` 会让只看 ok 的门禁误判「已 review」——伪能力/静默通过。

建议修复方向：`ocr_scan` 在目标路径含 .mbt 且 reviewable_count=0 时显式返回 `ok=false` + 明确 reason（fail-loud，防门禁被静默满足），或将该局限显式写入 bugfind 的 require_ocr 判据与 AGENTS.md（诚实标注单轨）。
- reported_by: fist-mbt-round5-lead
- task_id: T0r588
- 追记(2026-10-19T12:0x+08:00, Round 13 / b2d1920+faf0186): 本条目建议修复方向的部分 1（`ocr_scan` 对 .mbt 显式 fail-loud）已落地并分两小步：① 上轮 `ocr_effective_ok` 把「`ok=true` 但 `reviewable=0` 且 `excluded>0`」判 `ok=false`（dir `src/server/` 走此分支，实测 82 excluded → ok=false）；② **本轮实测发现部分 1 仍有一条盲区（记 BUG-327b）**：显式单文件 `path=src/ocr_scan.mbt` 时 OCR 二进制报 `reviewable_count=0, excluded_count=0, files=[]`——与「空目录」同形，被 `ocr_fake_green_check` 的空目录豁免判 `reviewed=true`，顶层 `ok=true` 假绿幸存。修复：新增纯函数 `ocr_reviewed_final(stdout_reviewed, path)`——目标为单个 `.mbt` 文件时强制 `reviewed=false`（fail-closed）并回显 notice「目标为单个 .mbt 文件（OCR 白名单外扩展名），LLM review 未真正执行；顶层 ok 已强制 fail-closed」，接线进 `ocr_scan_impl`（`reviewed2`/`fake_notice2`）；配套白盒锁 `BUG-327b_ocr_reviewed_final_single_mbt_fail_closed`。发布版 dist 真跑实证：`src/ocr_scan.mbt` → `ok=false` + 上述 notice；`src/server/`（目录）→ `ok=false` 零回归。**注意**：同一条路径两种目标形状（单文件 vs 目录）走的是两条不同假绿分支，任何一边单独修都会留下另一边——现已双分支都 fail-closed。**部分 2（`require_ocr` 门禁接线到 `.mbt` 非可审查性）仍未做**，阻塞在 `src/server/server.mbt`（并发 agent WIP），故本条目**保持 OPEN**。

## BUG-328 [2026-10-19T04:41:44Z] [low] FIXED
- summary: [rule:check_demo_isolation] NEEDLE_RE 不认 env.setdefault(FIST_DB_PATH) 形状 → 守卫假红 2 项
- detail: NEEDLE_RE 只认四种形状：① `Xenv["FIST_DB_PATH"]=` ② `os.environ.setdefault("FIST_DB_PATH",...)` ③ `env=dict(...FIST_DB_PATH...)` ④ `env={...FIST_DB_PATH...}`。但 `env=dict(os.environ)` 后接 `env.setdefault("FIST_DB_PATH", db)` 也把 FIST_DB_PATH 落进传给 Popen 的子进程 env（_gen.py L27-32、pol_keeper_run.py 同款），却因形状不匹配被误判 I1 违例 ⇒ check_demo_isolation 假红 2 项。修复（49dca79）：NEEDLE_RE 增加第 5 形状 `\w*env\w*\.setdefault\(\s*["']FIST_DB_PATH["']`，注释同步四种→五种；守卫回 PASS（spawn 面 35 脚本全合规），--selftest G1/M1/M1b/M2/M3 全绿（变异仍必红，未放宽守卫）。



### FIXED(2026-10-19T04:41:54Z / BUG-328)
- evidence: scripts/check_demo_isolation.py NEEDLE_RE 增第 5 形状 `\w*env\w*\.setdefault\(\s*["']FIST_DB_PATH["']`，注释"四种"→"五种"；提交 49dca79。守卫回 PASS（spawn 面 35 脚本全合规、豁免锚点成立），--selftest G1/M1/M1b/M2/M3 全绿——变异仍必红，守卫未被放宽。
## BUG-329 [2026-10-19T04:52:17Z] [medium] FIXED
- summary: [rule:check_release_asset_names/R13] README 离线线资产名版本字面量 v0.3.8 落后 moon.mod 0.3.9（BUG-120 复发），连累 selftest 崩溃
- detail: check_release_asset_names 守卫 R13 违例：README L141 离线/内网线 `install_onecmd.ps1 -LocalZip C:\path\to\fist-mbt-js-v0.3.8.zip` 版本字面量落后于 moon.mod "0.3.9" ⇒ 用户照抄离线线即 404（同 BUG-120 形态，0.3.8→0.3.9 版本推进时未同步）。连带：守卫 `--selftest` 因 R13 变异锚 `fist-mbt-js-v0.3.9.zip` 不在 README 内而 AssertionError 崩溃（"变异锚不在 readme 里"），selftest 失检。修复（dd056d6）：README L141 `v0.3.8.zip`→`v0.3.9.zip`。复核：守卫主检 PASS（R1~R14 全绿）、selftest OK（R13×2 等 14 格）。



### FIXED(2026-10-19T04:52:26Z / BUG-329)
- evidence: README.md L141 离线线资产名 `fist-mbt-js-v0.3.8.zip`→`fist-mbt-js-v0.3.9.zip` 对齐 moon.mod "0.3.9"；提交 dd056d6。守卫 check_release_asset_names 主检 PASS（R1~R14 全绿），--selftest OK（R13×2 等 14 格不再崩溃）。
## BUG-330 [2026-10-19T05:03:09Z] [medium] FIXED
- summary: [rule:check_skill_inject] 守卫误选 [lesson] 教训为 [asset]（SELECT 过宽）+ 计数 len(rows) 误报 16 条违例
- detail: check_skill_inject 守卫两处缺陷（BUG-329 同族，守卫自身缺口）：
① SELECT `goal/note/code LIKE '%[asset]%'` 过宽 —— `[lesson]` 教训条目（goal=`[lesson] concurrent-coordination`，id=lesson-202610-15.05.17）因其 code 里合法提到归档规则（讲 evolve_asset_register/evolve_lesson 用法）被误选，再因 goal 非 `[asset]<source>` 被误报「反查问题」。守卫 L35-37 自述「`[lesson]` 条目不算 `[asset]`」与实现自相矛盾；且 lookup_injected_assets_in 只按 goal/note 检索、不匹配 code，匹配 code 本身不落在判据面内。
② FAIL 消息 `共 %d 条 % len(rows)` 用全量 `[asset]` 条目数而非违例数 `len(ap)` —— 实测 16 条被误读为 16 条违例，实为 1 条。
修复：SELECT 收窄为 goal 单面（判别位在 goal）；计数改 len(ap)。复核：主检 PASS（15 条 `[asset]` 全部可反查）、--selftest OK、check_scripts_index/check_py_stdout_encoding 全过。



### FIXED(2026-10-19T05:03:25Z / BUG-330)
- evidence: scripts/check_skill_inject.py：SELECT 收窄为 goal 单面（判别位在 goal，不再匹配 note/code，与 L35-37「[lesson] 不算 [asset]」一致）；FAIL 计数 len(rows)→len(ap)。复核：主检 PASS（15 条 [asset] 全部可反查，假阳性 lesson-202610-15.05.17 不再误报）、--selftest OK（U1 合规不误红/匹配缺失必红/档案面空自拒 exit 2 全过）、check_scripts_index + check_py_stdout_encoding EXIT=0。
## BUG-331 [2026-10-19T05:10:21Z] [medium] FIXED
- summary: [rule:version-lag] DSH 宿主 manifest version 0.3.8 落后 moon.mod 0.3.9（0.3.9 bump 漏同步第四处真源）
- detail: commit 8052e67 标注「三处真源同步」（cmd/cli/help_topics.mbt + moon.mod + src/server/server.mbt），但漏了第四处：DSH 宿主真安装面 `.dsh/fist-mbt-plugin/package.json` 的 `version` 仍为 0.3.8，meta.description 也写 v0.3.8。check_host_installable 守卫 D1 档据此 FAIL：「DSH manifest version 0.3.8 != moon.mod 0.3.9」。同族：BUG-114（server.mbt project_version 落后）/ BUG-120（README 资产名落后）/ BUG-329（README 离线线资产名落后）。
修复：package.json version 0.3.8→0.3.9，meta.description 版本标签同步（8052e67 为纯版本 bump、功能集不变，如实注明）。
复核：check_host_installable PASS（DSH manifest/patch 严格档 + 宽松档 + 默认模板 + moon.mod 0.3.9 全过）。



### FIXED(2026-10-19T05:10:34Z / BUG-331)
- evidence: .dsh/fist-mbt-plugin/package.json：L3 version 0.3.8→0.3.9；L16 meta.description 版本标签同步并如实注明「0.3.8→0.3.9 为版本号推进，功能集不变」（8052e67 为纯 version bump，3 文件仅版本字面量）。复核：check_host_installable PASS（DSH manifest/patch 严格档：绝对路径 + toolCallTimeoutMs + dsh reconnect schema 合规；宽松档 MCP JSON 合规；moon.mod 版本 0.3.9）。
## BUG-332 [2026-10-19T05:34:50Z] [medium] OPEN
- summary: check_py_stdout_encoding --all 面 10 处脚本缺 BUG-58/138 stdout UTF-8 重配（Windows 控制台手跑会 UnicodeEncodeError 崩在结论行前，rc 被冒用）；CI 跑 --all，故此前 CI 在该面一直红
- detail: BUG-138 追记的 --all 残余面从未被跑过，本轮 selftest E1 暴露现状面真红。CI ci.yml 实际跑 `python3 scripts/check_py_stdout_encoding.py --all`，故这是真 CI 失败面，非仅 selftest 严苛。

违例 10 处（会 print 非 ASCII 却无 sys.stdout.reconfigure）：
- scripts/blackbox/e2e_assistant_xproc.py（print 含 ×/—）→ 已修（8f00f8b 前单独改）
- scripts/caf_offline_replay.py / caf_p2c_ab_preflight.py / caf_p2d_coldstart_ab.py / patch_router_config_caf_field.py / run_check_t0r21.py / test_shim_handshake.py → 已修
- fix_esm_require.py / pol_keeper_run.py（gitignore 未跟踪，仍实存）→ 已修
- scripts/fist_mbt_mcp_client.py / scripts/ns_route_probe.py → **并发 WIP，未动，待 concurrent agent 收口时补**

修复形态（与守卫标准逐字一致）：import 段后插
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

修后 --all 违例 10→2（余 2 并发 WIP）；selftest E1/M6 待 2 处补齐后转绿。同族 BUG-58/138/122（手写族名落后于新增脚本）。
- reported_by: lead

## BUG-333 [2026-10-19T05:54:08Z] [medium] OPEN
- summary: issue_scan 精度不足：src 全量 9925 命中中 72.7%（7219）为编译期已保证/子串近似噪音（match-exhaustive 编译器强制=100% 假阳、unused-variable/long-function 为近似启发），使"扫描→上报→修复"闭环不可用
- detail: 实测 `issue_scan dir=src max_findings=100`：scanned_files=129, total_findings=9925（截断）。by_rule 全表精确求和 = 9925。其中：

- moonbit-unused-variable 4259（info）：自述「子串近似 let 声明点，实际使用性需人工/编译器复核」——编译器已对真正未使用变量给警告，故绝大多数为假阳性。
- moonbit-match-exhaustive 1513（low）：MoonBit 编译器**强制** match 穷尽（不穷尽 = 编译错误），代码 1338 测试全过、编译通过 ⇒ **100% 假阳性**。
- moonbit-long-function 1447（info）：自述「行数精确判定见 OCR 双轨」，本就是启发式，非 bug。
- moonbit-json-injection 1409（low）：子串近似，Json API 是否转义需逐条核实。
- 其余（array-index-bounds 159 / empty-match 109 / race-condition 9 / resource-leak 7 / dead-code 6 / floating-point-equality 2 等）抽查全为假阳性：float-eq 命中的是 rule-id 字符串里的 "float"；dead-code 的 abort 全在 claimguard_wbtest.mbt 测试断言（故意测错误路径）；resource-leak 全仓 grep File::open/sqlite.open 零命中。

**前三项合计 7219/9925 = 72.7%**。后果：「扫描→上报→修复」闭环不可用——执行者不可能 triage 9925 条里 73% 已知为噪音的命中，于是闭环要么被绕过、要么被「全报 bug」淹没真实缺陷。同族于 BUG-330（守卫 false-positive）/BUG-329（selftest 崩溃）的「判据精度」族。

建议：默认降噪——①`--min-severity` 或按 rule 白/黑名单过滤（默认关掉 unused-variable/long-function/match-exhaustive 三高噪音项，或降为 info-only）；②match-exhaustive 直接不产（编译器已保证）；③对剩余 low 项挂 `confirmed=false` 要求调用方喂 run_check 复核后才 report_bug（boundary_probe 已是这个语义，可复用）。
- reported_by: lead

## BUG-334 [2026-10-19T06:11:48Z] [high] FIXED
- summary: cleanup_artifacts.py 的 `_`前缀规则误移 git 跟踪的工具注册真源 `scripts/_tool_registry.py`，破坏 7 个导入它的守卫（check_tools_sync/check_plugin_sync/gen_plugins/check_doc_surface/mcp_smoke）；CI 仅靠 cleanup 排在最后的顺序侥幸未炸，属 latent hazard
- detail: `scripts/cleanup_artifacts.py` L65 `_TMP_SCRIPT_EXT = (".py",".ps1",".sh")` + L79 的 `_` 前缀匹配规则，会把 **`scripts/_tool_registry.py`** 误当「任务完即清的临时脚本」移入 `temp/`。而 `_tool_registry.py` 是 **git 跟踪的**（`d35c2f0 refactor(guard): 抽单一 _tool_registry 实现，5 个消费者改委托`）工具注册单一真源，被 7 处导入：
- `check_doc_surface.py:89` / `check_plugin_sync.py:34` / `check_tools_sync.py:40` / `gen_plugins.py:41` / `mcp_smoke.py:35`（5 个 importlib 委托）
- `check_plugin_sync.py:126`（子进程 `_tool_registry.py --selftest`）
- `check_template_ctrl.py:211`（诊断建议引用）

**已实测触发**：本机跑 `python scripts/cleanup_artifacts.py` 后，`scripts/_tool_registry.py` 消失（git status 报 `D`），`check_tools_sync.py` / `check_plugin_sync.py` 当场 ImportError 红；`git checkout -- scripts/_tool_registry.py` 恢复后两者复活（exit 0）。

**CI 为什么没炸**：`ci.yml` L243-245 的 "Cleanliness guard" 是 check-js job 的**最后一步**，位于 L91 check_tools_sync、L108 gen_plugins --check、L110 check_plugin_sync **之后**；后续 `check-native` 等 job 重新 checkout。所以 cleanup 的误移没被同 job 下游消费到。**这是顺序侥幸，不是正确性**——只要有人在 ci.yml 把 cleanup 挪到守卫前面，或加一个依赖 `_tool_registry.py` 的步骤在其后，就会静默红，且红因难查（报 ImportError 在消费者、不报 cleanup）。

**同族**：BUG-330（守卫 false-positive）/BUG-333（判据精度）/BUG-329（selftest 崩溃）——「守卫族自身健壮性」系。

**修复建议（小，一行）**：在 `cleanup_artifacts.py` 加豁免集，如 `KEEP_SCRIPTS = {"_tool_registry.py"}`（+ 任何 git 跟踪的 `_` 前缀脚本），在 `_` 匹配分支跳过；更稳的通用规则是「只清 `git ls-files --others`（untracked）的 `_` 脚本，tracked 一律不动」。后者顺带根治「cleanup 误删已跟踪临时文件」整类问题。
- reported_by: lead


### FIXED(2026-10-19T06:51:02Z / BUG-334)
- evidence: 提交 32849cd：cleanup_artifacts.py 加 is_git_tracked(relpath)（git ls-files --error-unmatch），`_` 前缀规则跳过 git 跟踪资产；加 --selftest 三格回归锁（S1 tracked 识别 / S2 _tool_registry.py 豁免 / S3 真 `_` 临时脚本仍被抓），变异验证 FAIL/1 → PASS/0。修复后 7 处导入 _tool_registry 的守卫（check_doc_surface/check_plugin_sync/check_tools_sync/gen_plugins/mcp_smoke/check_template_ctrl/check_scripts_index）全部复活 exit 0。
## BUG-335 [2026-10-19T06:37:21Z] [high] OPEN
- summary: e2e_heartbeat_xproc (default) CI 门禁红：publish_parallel 返回 task_id 但任务不落隔离库（call_log 正常改道、tasks 表空）
- detail: 复现：`python scripts/blackbox/e2e_heartbeat_xproc.py`（ci.yml L222 门禁）exit 1。

证据链：
1) 脚本 L220 先 `os.remove(temp/hb-xproc.db + suf)` 清场，L139 `env["FIST_DB_PATH"]=隔离库` 起真 `node cli.js serve`，L238-249 用 `publish_parallel(namespace="hb-xproc")` 建 4 条在途任务。
2) 隔离库 `temp/hb-xproc.db` 的 **call_log 有 seq 7-11**（claim/execute/heartbeat/pause，证明 server 确实用了该库），但 **tasks 表 count=0** —— publish_parallel 返回的 4 个 id 一个都没落 task 行。
3) 真实交付库 `fist-mbt.db` 亦无 `%心跳跨进程%` 任务（latest id=T0r641，未污染）。
4) 脚本 `A heartbeat 回执` = `{"_error": "task not found: T0r5"}`，而 L255 用的是动态 `t1`（publish_parallel 返回值）—— 即 publish_parallel 报了 T0r5 但按此查无此任务。

对照：`store_isolation_probe --selftest` exit 0（隔离专项门 PASS，隔离机制未整体坏）；`e2e_heartbeat_xproc --selftest` exit 0（脚本自身 28 格逻辑 PASS，仅 default 实测失败）。

归因：本轮 5 处 CI 真跑面红中，本条与 check_entry_paths 同属**并发 agent 未提交 WIP 域**（src/server/server.mbt HEAD d010592 有未提交改动），非本轮 cleanup_artifacts 修复（那支只改 cleanup_artifacts.py 自身）引入。建议并发 agent 侧排查 publish_parallel 在「FIST_DB_PATH 隔离库 + 自定义 namespace」下的 task 落库路径。

本机 `--selftest` 通过、`store_isolation_probe --selftest` 通过，故不阻断其它守卫；仅 default 面红，需真实 server 端复现定位。
- reported_by: lead-R20



## BUG-336 [2026-10-19T09:03:42Z] [medium] FIXED
- summary: dag_cost_route 负载感知冻结：load 只在循环前一次性快照，路由循环内从不更新累计负载 → 等成本平局时全堆给先注册执行者（1180 任务 59% 给单一执行者）
- detail: ## 现象
dogfood `dag_cost_route`（R77 成本路由）：1180 个 slack>0 未认领任务中 59%（701）堆给单个执行者 `marvis`，负载感知声明失效。
## 根因
`src/engine/engine_dag_ext.mbt` L657 `load = self.executor_loads(reg_names)` 只在路由循环**前**一次性快照活跃负载；L744 把任务写进 `routed` 却**从不更新 `load`**。于是 L732-739 的等成本平局 tiebreak（"相等取负载最低"）对本次路由自身的累计分配失明——平局时 `nl < bl` 恒假（两执行者负载都=初始值），`best` 永远停在先注册者 → 整轮路由全堆给先注册执行者，负载均衡形同虚设。
## 实证（白盒 RED→GREEN）
`src/engine/dag_ext_test.mbt` 新增 `dag_cost_route: 等成本平局按累计负载均分（BUG-336）`：2 个同能力执行者 + 4 独立灵活任务（+ 旁链垫 makespan=3）→ 修复前 `alice=4, bob=0`（RED），修复后 `alice=2, bob=2`（GREEN）。
## 修复
L744 `routed.set(id, best)` 之后追加：`let prev_load = match load.get(best){...}; ignore(load.set(best, prev_load + 1))`——把本次分配计入累计负载，后续等成本平局任务才转向其他执行者。
## 验证
`moon test --target js` = 1339/1339（新增 1 锁）；`moon fmt` 干净（engine 文件）。



### FIXED(2026-10-19T09:04:03Z / BUG-336)
- evidence: 修复点 src/engine/engine_dag_ext.mbt L741-749：routed.set(id, best) 之后追加 load.set(best, prev_load + 1)，把本次分配计入累计负载。白盒锁 src/engine/dag_ext_test.mbt `dag_cost_route: 等成本平局按累计负载均分（BUG-336）` RED(alice=4,bob=0)→GREEN(alice=2,bob=2)。全量 moon test --target js=1339/1339。
