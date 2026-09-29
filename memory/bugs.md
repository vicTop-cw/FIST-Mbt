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
  grep -rniE "runs" src/store/*.mbt 除建表外 -> 只有两处注释，无任何读侧
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

## BUG-47 [2026-09-26T13:32:34Z] [medium] DUPLICATE →BUG-50
- summary: [verify][BUG-44] docs/agent-map.md 宣称测试数 316 项全绿（实测 406）；check_test_sync 只核对「实测数出现在 4 份文档」，不核对文档里的**其它**数字是否等于实测 ⇒ 数值声明无人管
- detail: 证据：temp/j_before_after.py 在 HEAD 内容上发红 32 条（J6=2/J7=11/J8=19），工作树为 0；temp/stdalign_verify.py 为本轮调用面终审。
- reported_by: std-auditor


### FIXED(2026-09-26 stdalign verify / 重复入账)

同 BUG-45：本条为 BUG-50 的重复（驱动重跑副作用），实际修复与证据见 BUG-50 的 FIXED 段。

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
