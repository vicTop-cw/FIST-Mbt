## BUG-1 [2026-09-26T03:52:44Z] [high] OPEN
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

## BUG-2 [2026-09-26T03:52:44Z] [medium] OPEN
- summary: retry 之后无法登记交付物：execute 只接受 拆分中/已领取，而 retry 落在 执行中，形成状态机死角
- detail: 现象：`reject`（待验收->已打回）后走 `retry`（已打回->执行中，src/core/core_task.mbt:463），但唯一能写 deliverable 的 `execute` 要求状态 [拆分中/已领取]（同文件 :368 的守卫文案即报错原文），于是在「已打回重做」这条最该更新交付物的路径上写不进新交付物；`omega_result_verify` 随即报「尚无交付物」。

活证据：本轮 R1 收口 cron-cypy/T0r61 与 R2 收口 T0r258.4.2 时均实测到该死角，绕行路径是合法迁移 `pause`（任意活跃状态->已暂停）→ `resume`（已暂停->已领取，:493）→ `execute`。绕行可行，但：① 任务会留下一条虚假的「已暂停」历史；② 该绕行在 MCP 工具名上还有二次坑（工具名是 `resume`，域函数叫 `resume_task`，按域名调用返回 Tool not found）。

影响：被拒后重做无法原地更新交付物，容易诱导操作者改为「新建任务覆盖旧账」，破坏 append-only 审计。

建议：把 execute 的合法前态扩到 [拆分中/已领取/执行中]（执行中重复 execute = 追加或覆盖交付物本就是直觉行为），或在 retry 的语义里把状态退回「已领取」。
- reported_by: cypy-commander

### FIXED(2026-09-26 pentad-r2 fix_and_merge / 终审人=指挥官，调用面实测)

engine 放宽 execute 状态守卫：已打回可直接 execute 并写明出路；reject→retry→execute 全链写 deliverable 通过（调用面 T0r301 链）。回归锁 src/engine/engine_execute_r2_test.mbt。
证据：调用面终审 14/15 PASS（唯一 FAIL 系判据自身读取上一笔 stderr，已用 workdir==project_dir 正例复验 status=passed）；laya_decide 21.0s/20.9s < 30s 客户端预算；run_check 对 rm/..越界成对拒绝且文案自带出路。
## BUG-3 [2026-09-26T03:52:44Z] [medium] OPEN
- summary: audit_log 作为治理查询面暴露，但实现是进程内不落库，跨进程永远返回 []（假空的审计证据）
- detail: 现象：MCP 工具 `audit_log`（描述为「查看追加式审计日志」）读的是进程内 AuditLog，**不落库**；每一次 MCP 调用新起一个 server 进程时，它返回空数组，而库里其实有完整写入痕迹。

活证据（2026-09-26 实测）：`python scripts/fist.py audit_log '{}'` → `[]`，而同一时刻 `python scripts/fist.py call_log '{"limit":400}'` 显示当天该库已记录上百条调用（含本流水线 cron-cypy 的 64 条 publish/claim/execute/submit/omega_*/run_check/verify/pause/resume）。

影响：这是审计面最坏的一种失败——**看起来没有发生过任何治理动作**（空证据），而不是报错。若有人用 audit_log 判断「谁在什么时候做了什么」，会得到系统性的假阴性，还可能据此得出「没有人越权」的错误结论。

建议：① 要么把 AuditLog 落库（与 call_log 同表或独立表），要么 ② 在工具描述与返回值里显式标注「仅本进程生命周期内的审计，跨进程请用 call_log」，并让空结果可区分（如返回 {scope:'process', entries:[], note:...}）。src/ops/audit.mbt:4 的设计注释应同步到对外契约。
- reported_by: cypy-commander

### FIXED(2026-09-26 pentad-r2 fix_and_merge / 终审人=指挥官，调用面实测)

audit_log 返回体改为 {scope:process, note 指向 call_log, entries[], count}，空结果不再伪装「无治理动作」；handler 统一走 audit_log_payload。回归锁 src/server/pipeline_r2_wbtest.mbt:124。
证据：调用面终审 14/15 PASS（唯一 FAIL 系判据自身读取上一笔 stderr，已用 workdir==project_dir 正例复验 status=passed）；laya_decide 21.0s/20.9s < 30s 客户端预算；run_check 对 rm/..越界成对拒绝且文案自带出路。
## BUG-4 [2026-09-26T03:52:44Z] [high] OPEN
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
## BUG-5 [2026-09-26T03:52:44Z] [medium] OPEN
- summary: project_dir 契约分裂：bug 族强制相对（默认报错不告知可接受形态），memory 族同一参数接受绝对路径并直接落盘
- detail: 现象：同名参数 `project_dir` 在本服务里有两套**相反**的契约——bug 族工具强制相对路径并拒绝绝对路径，而其余 20+ 个工具（memory 族/selfdrive 族）完全不做形态校验、直接把它当真实文件系统路径拼接。工具描述与参数说明里看不到这个差别，措辞逐字相同。

源码位置：src/server/bugreport.mbt:26-42 `bug_project_dir_ok`（拒空串 / 含 ".." / 前导 '/' 或 '\' / dir[1]==':'），调用点 :234（report_bug）、:312（bug_list）、src/server/github_sync.mbt:27,57,120,199,303,398,483,530,573 共 9 处；对照 src/server/memory.mbt:32 `mem_dir(project_dir)=mem_join(project_dir,"memory")` 无任何校验。对外契约：src/server/server.mbt:3938 描述「追加到 {project_dir}/memory/bugs.md」、:3941 参数说明「项目目录（必填）」——与 server.mbt:651,692,1825,1854,1878,1898,1922,1942,1998,2026,2053,2609,4009,4138,4155,4175,4263,4464,4584 共 19 处同名参数说明逐字相同。

活证据 A（memory 族接受绝对路径，2026-09-26 实测）：`python scripts/fist.py memory_link '{"project_dir":"E:/IDEProjects/AI/Cypy/output/fist/abs_probe","from":"A","to":"B"}'` → `{"linked": true, "from": "A", "to": "B"}`，并在 `E:/IDEProjects/AI/Cypy/output/fist/abs_probe/memory/links.md`（新建目录 + 30 字节）真实落盘。
活证据 B（bug 族拒绝同形态入参，2026-09-26 实测）：`report_bug` 传 `project_dir="E:/IDEProjects/AI/FIST-Mbt"` → `ERROR {'code': -32000, 'message': 'report_bug: 非法 project_dir（拒绝绝对路径/穿越/盘符）'}`；错误文案没有说明**接受什么形态**，调用方只能读源码猜。

实际后果（本轮真实踩到）：相对路径由 **server 进程 cwd** 解析，而不是由调用方的项目根解析。驱动以 `cwd=E:/IDEProjects/AI/FIST-Mbt` 起 server 时 `project_dir="."` 才恰好写到 FIST 自己的 `memory/bugs.md`；换任一其它起法（例如从别的项目根 stdio 拉起同一个 main.js），同一份「向兄弟项目上报缺陷」的调用会把账本写进**另一个项目**的 memory/ 下，而返回值的 `path` 只是 `./memory/bugs.md` 这样的相对串，调用方无法从响应判断真实落点，也无法事后追查。本流水线的需求「用 issue 通道上报被驱动项目的缺陷」在现有契约上并不是安全可用的。

建议（按代价升序）：① 把 report_bug/bug_list 的描述与 string_prop 改成「项目目录（必填，**相对 server 进程 cwd**，拒绝绝对路径/盘符/..）」；② 返回值补 `resolved_path`（绝对 + normalize 后），让落点可审；③ 长期：统一两套契约——要么全部接受绝对路径并做 canonicalize + 允许的根白名单，要么全部要求相对并给统一的校验函数（现在 bug 族有、memory 族没有）。
- reported_by: cypy-commander

## BUG-6 [2026-09-26T05:55:08Z] [medium] OPEN
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

## BUG-7 [2026-09-26T05:55:47Z] [medium] OPEN
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

## BUG-8 [2026-09-26T06:26:20Z] [medium] OPEN
- summary: [ledger-lifecycle] src/server/bugreport.mbt:264 自动发布的修复单硬落 namespace "bugs"，与发起 ns 断裂，根任务上卷覆盖不到它
- detail: 现象：`report_bug(publish_task=true)` 生成的修复单被写死在 ns `bugs`（`src/server/bugreport.mbt:264` 的 `ns="bugs"`），`parent_id=null`，而调用方本轮用的是 ns `cypy-polish-20260926`。
活证据（2026-09-26 实测，cwd=E:/IDEProjects/AI/Cypy）：8 张修复单 T0r6..T0r13 的 `claim`/`verify` 原始回复里都带 `"namespace": "bugs", "parent_id": null`，见 E:/IDEProjects/AI/Cypy/.fist-polish-20260926/close_fixes.out.json 的 `BUG-1:claim` 与 `BUG-8:claim` 两条。
实际后果：① 「子单全部 verify 后父任务自动上卷」这条生命周期对 issue_up 通道永不触发，根任务状态与缺陷闭环无关，指挥官若按根状态判断进度必然误判；② `list` 按 ns 作用域，在本轮 ns 里看不到这些修复单，只能靠 `get(task_id)` 逐单点名；③ 收尾脚本无法用一条「列出本 ns 未闭环单」的查询自证收口完备，只能自带映射表（本轮 intake_map.json）。
建议（按代价升序）：① `report_bug` 增加 `task_namespace` 入参，缺省仍为 `bugs` 但允许调用方指定；② 返回值与 `bug_list` 行都补 `namespace`/`task_id` 已在做，再加 `root_task_id` 以便按发起树聚合；③ 文档明确写「修复单落在独立 ns `bugs`，不挂到调用方任务树」，别让「父任务自动上卷」的措辞覆盖它。
- reported_by: cypy-polisher

## BUG-9 [2026-09-26T06:26:20Z] [medium] OPEN
- summary: [ledger-lifecycle] 缺陷账本只写不销：无 bug 关闭/状态位 API，修复单全部「已完成」后 bugs.md 条目仍恒为 OPEN
- detail: 现象：bug 工具族只有 `report_bug`（写）与 `bug_list`（读）（`src/server/server.mbt:4024` 与 `:4096` 是全部注册点），没有任何 `bug_close`/`bug_resolve`/状态入参。`bugs.md` 条目头写 `## BUG-n [ts] [sev] OPEN`，此后无论关联修复单走到哪一步，该状态位都没有合法路径可翻转。
活证据（2026-09-26 实测）：E:/IDEProjects/AI/Cypy/memory/bugs.md 的 BUG-1..BUG-8 八条全部标 `OPEN`（grep `^## BUG-` 八行尾列全 OPEN），而同轮 E:/IDEProjects/AI/Cypy/.fist-polish-20260926/close_fixes.out.json 显示 T0r6..T0r13 八张修复单 `verify` 回复 status 全部 `已完成`。同一事实两份账，一份说全绿一份说全开。
实际后果：issue_up 的「发现→上报→修复→销账」闭环缺最后一环。下一轮（或别的 agent）读 `bug_list` 会把 8 条已修完的缺陷继续当未决工作，或者靠人工在 markdown 里手改状态位——手改即污染：`bug_list` 若解析 markdown，手改内容不在服务端事务内，无 `now`、无 caller、不进 call_log。
建议：① 新增 `bug_close(bug_id, resolved_by, task_id, now)`，把状态位写成 `CLOSED [<task_id>]` 并落 call_log；② 或在修复单 `verify` 成功时自动销账（需要 bug↔task 反查表，`report_bug` 已经在写 task_id，具备条件）；③ 过渡期至少让 `bug_list` 返回关联任务的当前 status，别让读方只能看 OPEN。
- reported_by: cypy-polisher

## BUG-10 [2026-09-26T06:26:20Z] [low] OPEN
- summary: [lifecycle] archive 走 complete 且要求状态 [待验收]，停在 [待领取] 的任务没有任何合法废弃路径（孤儿单永久残留）
- detail: 现象：`archive` 内部走 `complete` 迁移，前置状态是 `[待验收]`；而诊断/试写期间产生的、只到 `待领取` 的任务既不能 `archive`（迁移非法）、也没有 `cancel`/`abandon` 类工具可废弃，`verify`/`submit` 又要求先有交付物。结果是任务库里永久留下无法清理的行。
活证据（2026-09-26 实测）：本轮隔离库 E:/IDEProjects/AI/Cypy/fist-mbt.db 中入账探针留下的 T0r2..T0r5 四条停在 `待领取`，`archive` 原样报错 `非法迁移: complete 要求状态 [待验收]，当前是 [待领取]`（逐条回复见 E:/IDEProjects/AI/Cypy/.fist-polish-20260926/close_fixes.out.json 的 `diagnostic-archive:*`）。同一工具对 `待领取` 与 `已完成` 两种状态给出同一个 `complete` 前置，错误文案未提示出路。
实际后果：自驱式流水线里「试写/探针/被取代的单」是常态产物，现在只能靠「先 claim→execute 假交付物→submit 再 archive」把噪声刷成已完成——那等于要求造假账才能清理干净，与本轮红线「禁止伪造已完成」直接冲突，所以本轮选择留着 4 条孤儿单并写进报告。
建议：① 提供 `abandon(task_id, by, reason, now)`：允许从 `待领取`/`执行中` 迁到`已废弃`，reason 进 call_log；② 或让 `archive` 接受 `待领取` 并把它当「未开工即作废」，不再要求 complete 前置；③ 错误文案补一句「可用工具：<xxx>」，让调用方不用读源码找出路。
- reported_by: cypy-polisher

## BUG-11 [2026-09-26T06:26:20Z] [low] OPEN
- summary: [contract] report_bug 返回 `bug_id` 而 bug_list 同一字段叫 `id`，按写侧字段名做对账的读侧会静默拿到 null
- detail: 现象：写侧 `report_bug` 响应键是 `bug_id`，读侧 `bug_list` 每行的键是 `id`（值同为 `BUG-n`）——同一实体两个字段名，工具描述未提示这一差异。
活证据（2026-09-26 实测，cwd=E:/IDEProjects/AI/Cypy）：`bug_list(project_dir=".")` 首行键集合 `['detail','id','reported_by','severity','status','summary','task_id','ts']`，且 `any('bug_id' in row)` 为 False；而入账响应里是 `"bug_id": "BUG-8"`。本轮幂等入账器按 `row.get("bug_id")` 取值，导致重跑时 7 条「已在账」的缺陷在 E:/IDEProjects/AI/Cypy/.fist-polish-20260926/intake_map.json 中被写成 `"bug_id": null`（`task_id` 仍正确），报告渲染时以 KeyError 暴露。
实际后果：任何「按写侧字段名读回」的对账/去重逻辑都会静默丢 id——不报错，只是取不到，于是「bug↔任务↔回归」三向对照在无人察觉时退化，最坏情形会把已入账缺陷当新缺陷再写一遍。
建议：① `bug_list` 行同时输出 `bug_id`（与 `id` 同值，向后兼容）；② 或在工具描述里写明读侧字段名；③ 长期把 bug 实体 id 收敛成单一字段名，写读两侧共用同一个序列化函数。
- reported_by: cypy-polisher

## BUG-12 [2026-09-26T07:57:19Z] [medium] OPEN
- summary: [contract] list 描述称「不传 namespace 则列出全库所有命名空间」，实测只回单一 ns 的行，ns `bugs`（report_bug 自动发布的修复单所在）一条都不回
- detail: 现象：`list` 的 inputSchema 描述写「namespace(可选，按命名空间过滤；不传则列出全库所有命名空间)」，但不带 `namespace` 的查询只回一个命名空间的行。
活证据（2026-09-26 实测，cwd=E:/IDEProjects/AI/Cypy，隔离库 E:/IDEProjects/AI/Cypy/fist-mbt.db）：不带 namespace 的 `list` 返回 19 行，逐行 `namespace` 去重后只有 ['cypy-polish-20260926'] 一个值；同库 `list(namespace="cypy-polish-20260926")` 返回 19 行、`list(namespace="bugs")` 返回 15 行，其中 15 行（如 T0r10, T0r11, T0r12, T0r13, T0r14）在没有 namespace 的查询里一条都不出现。原始回复见 E:/IDEProjects/AI/Cypy/.fist-polish-20260926/probe_list_scope.out.json 与 probe_lifecycle_park.out.json。
实际后果：调用方按描述写的「全库扫一遍找未闭环单」会静默漏掉 ns `bugs` 里 `report_bug(publish_task=true)` 自动发布的全部修复单（正是 issue_up 闭环的产物），表现为「单子明明开着却查不到」→ 收尾自证不完备却看起来完备。与已入账的 BUG-8（修复单硬落 ns `bugs`、根上卷覆盖不到）叠加：一个把单送进 `bugs`，一个让默认查询看不见 `bugs`。
建议：① 让无 namespace 的查询真正跨全库，或在返回体里加 `namespaces_scanned` 让调用方能自证范围；② 若刻意默认单 ns，就把描述改成「缺省按调用方最近使用的 ns」这类真实语义并给出取全库的入参；③ `list` 增加 `include_namespaces`，让 `bugs` 能被显式纳入。
- reported_by: cypy-polisher

## BUG-13 [2026-09-26T07:57:19Z] [low] OPEN
- summary: [更正 BUG-10] 停在 [待领取] 的任务有合法出路 `pause`（任意活跃状态→已暂停），「无合法废弃路径 / 只能靠假交付物刷成已完成」不成立
- detail: 被更正条目：本账本 BUG-10「archive 走 complete 且要求状态 [待验收]，停在 [待领取] 的任务没有任何合法废弃路径（孤儿单永久残留）」。
仍然成立的部分：`archive` 确实走 `complete`，对 `待领取` 原样报 `非法迁移: complete 要求状态 [待验收]，当前是 [待领取]`。
不成立的部分：BUG-10 断言「没有 cancel/abandon 类工具可废弃」「只能先 claim→execute 假交付物→submit 再 archive 才能清理」。tools/list（116 个工具）里就有 `pause`（描述：任意活跃状态 -> 已暂停）、`resume`（已暂停 -> 已领取）、`reopen_task`（任意非归档任务回滚为已领取）、`reject`（待验收 -> 已打回）、`retry`（已打回 -> 执行中）、`delete`（删除已归档任务）。我当初只试了 `archive` 一条路径就下了「无出路」的结论。
活证据（2026-09-26 实测）：对 BUG-10 点名的那 4 条孤儿单 T0r2..T0r5 逐条 `pause`，全部落到 `已暂停`（`get` 逐条复核，另有同轮 12 条未开工深拆叶子 T0.1.1..T0.6.2 一并 park，16/16 park 成功）；原始回复见 E:/IDEProjects/AI/Cypy/.fist-polish-20260926/probe_lifecycle_park.out.json 的 `pause` 段。
为什么仍值得留一条修订而非直接当误报：BUG-10 的「建议 ①提供 abandon()」现在应改成「`pause` 已具备该语义，但 `待领取`→`已暂停` 与『作废』之间的差别（是否可 resume、是否计入未闭环、错误文案是否提示出路）没有在描述里写明」——调用方要靠读 116 个工具的描述才找得到出路，这本身就是可改进点，但不该记成「无合法路径」。
建议：① `archive`/`complete` 的非法迁移错误文案追加一句「可用工具：pause / reopen_task」；② 在 lifecycle 文档里给出 `待领取` 的两条出路（park 或走完 claim→execute→submit→verify），别让下一位读者照 BUG-10 的措辞去造假交付物。
- reported_by: cypy-polisher

## BUG-14 [2026-09-26T08:07:01Z] [high] OPEN
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


## BUG-15 [2026-09-26T08:08:34Z] [medium] OPEN
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


## BUG-16 [2026-09-26T08:09:10Z] [medium] OPEN
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


## BUG-17 [2026-09-26T09:14:15Z] [medium] OPEN
- summary: [verify:doc-single-source] 工具数/测试数跨文档三套口径：AGENTS.md=105、deliverable.md=104、scoring_rubric.md=104（实测 116）；README=329、AGENTS/deliverable=317（实测 JS 376）；且 10 个已注册工具在 AGENTS.md 零记载
- detail: 活证据（2026-09-26 实测）：修复前 `python scripts/check_tools_sync.py` FAIL 并逐条列出 —— server 注册但 AGENTS 未列出 (10): github_env_check, github_flush_execute, github_flush_plan, github_issue_close, github_issue_comment, github_issue_webhook_parse, github_queue_mark_sent, github_queue_status, mode_list, mode_templates；同时报 README.md/AGENTS.md/deliverable.md/scoring_rubric.md 四份文档缺 116 的表述。测试数同构漂移：README.md:5 徽章 329/329、README.md:10/30/79/146 均写 329，而 AGENTS.md:87/97 与 docs/deliverable.md:18 写 317，`moon test --target js` 实测 376。
影响：① 违反规范 r1「文档即实现」/r2「一源三态·单真源优先」——AI 客户端读 AGENTS.md 会以为只有 105 个能力，整个 GitHub 同步通道（issue_up 的落地面）与 6 模式自驱入口对外不可见；② 「JS 与 Native 双后端均已通过 329/329」这类句子把两个后端的旧数字绑在一起宣称，升版时必然漏改（本轮就是这么漂的）；③ 守卫本身（check_tools_sync/check_test_sync/check_badge）早就写好了，却没在改动当轮跑，漂移积累到 12 项才被发现。
本轮处置（polish 已修）：AGENTS.md 补两节「开发模式与模板（2）」「GitHub 同步 · 缺陷上报通道（8）」逐条列 10 个工具；四份文档工具数统一 116；测试数按**各自实测口径**统一为 JS 376/376，并把「双后端同版全绿」的表述改为分别声明 JS 本轮实测 376 / native 上一轮 317 且本轮未复跑——刻意不把未验证的后端数字转正。复跑三守卫全 PASS。
遗留：版本/计数仍无构建期单一真源（BUG-16 只收了代码内三处，文档侧仍靠人工 + 守卫判红）。
- reported_by: pentad-r1-verify

## BUG-18 [2026-09-26T09:14:16Z] [medium] OPEN
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
## BUG-19 [2026-09-26T09:27:31Z] [high] OPEN
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

## BUG-20 [2026-09-26T09:27:32Z] [medium] OPEN
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

## BUG-21 [2026-09-26T09:27:32Z] [medium] OPEN
- summary: [bugfind:single-source] MCP 握手自报 serverInfo.version=0.1.0，与 moon.mod 的 0.3.0 及 Round 1 新增的 project_version 常量都不一致 —— BUG-16 的修法漏了对外握手面，且回归锁盯的是 0.2.4 抓不到它
- detail: 现象：src/server/server.mbt:687 逐字写 let mut s1 = @mcp.MCPServer::MCPServer("fist-mbt", "0.1.0")。这是 MCP initialize 响应里 serverInfo.version 的唯一来源，即任何 MCP 客户端连上来第一眼看到的"这个项目是什么版本"。

对照（2026-09-26 实测）：grep '^version' moon.mod → 0.3.0；status_summary.version → 0.3.0；project_health.version → 0.3.0；fist://overview → 0.3.0（这三处是 Round 1 BUG-16 刚收敛到 project_version 常量的三个对外面）。唯独 initialize 握手面仍是 0.1.0，落后两个大版本。
取证方式说明：本轮想直接从 stdio 抓 initialize 响应未果（Round 2 修复子代理正在并发重建 _build/js/.../main.js，裸 spawn 撞上半成品产物而阻塞，已放弃该路；但源码赋值点单一且唯一，无运行时分支，静态证据足定）。此项**证据等级为 L3（源码位置 + 同族三处实测值），未达 L4 调用面**，故按寻虫红线如实标注，交由修复轮补一次调用面复跑。

为什么值得单独入账而不只是"BUG-16 没修完"：① Round 1 的回归锁断言的是「server.mbt 里不再出现 0.2.4 字面量」+「三处对外面含 project_version 声明值」，0.1.0 这个字面量**不在它的监视范围**，所以守卫全绿而漂移仍在——这是"判据覆盖面比缺陷面窄"的活样本；② 握手版本是客户端能力协商与排障的第一信号，0.1.0 会让人误判这是一个早期原型；③ 项目规范 r2「一源三态·单真源优先」要求对外自述只有一个改动点，目前对外版本有两个真源（project_version 与 MCPServer 构造字面量）。

建议：① 把 MCPServer 构造的第二个实参改为引用 project_version（一处改动，零 API 变化）；② 把回归锁从"禁止出现某个旧版本字面量"升级为"禁止 src/server/ 下任何形如 0.x.y 的版本字面量，除 project_version 声明行本身"，这样下次升版漏改任一面都会判红；③ 补一条调用面判据：initialize 响应的 serverInfo.version 必须等于 moon.mod 的 version（可在 mcp_smoke 里做，注意与其它构建并发时先 build 再取）。
- reported_by: pentad-r2-bugfind

## BUG-22 [2026-09-26T09:29:15Z] [medium] OPEN
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

## BUG-23 [2026-09-26T09:38:37Z] [high] OPEN
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

## BUG-24 [2026-09-26T09:38:38Z] [medium] OPEN
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

## BUG-25 [2026-09-26T09:38:38Z] [medium] OPEN
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

## BUG-26 [2026-09-26T09:38:39Z] [low] OPEN
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

## BUG-27 [2026-09-26T09:45:15Z] [high] OPEN
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

## BUG-28 [2026-09-26T09:45:16Z] [medium] OPEN
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

## BUG-29 [2026-09-26T09:46:52Z] [low] OPEN
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

## BUG-30 [2026-09-26T09:50:31Z] [medium] OPEN
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

## BUG-31 [2026-09-26T10:41:50Z] [medium] OPEN
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

## BUG-32 [2026-09-26T11:04:49Z] [high] OPEN
- summary: [contract] scripts/fist.py:35 不校验入口产物新鲜度：调用面验收可能在度量旧二进制
- detail: 现象（2026-09-26 11:03 实测）：src/server/server.mbt 自 17:59 起已接入 run_check_guard（cmd 白名单 + workdir 子树），但 scripts/fist.py 第 35 行直接拉起 _build/js/debug/build/cmd/main/main.js（mtime 16:51，早于源码 68 分钟），导致调用面终审全程测的是 Round 1 旧行为：run_check 对 `rm -rf /` 返回 ok=true、workdir 拒绝文案是旧的「拒绝绝对路径/盘符」、laya_decide 单跳 211s 超客户端 30s 预算。执行 `moon build --target js cmd/main` + patch_esm_main.py 后，同一判据脚本立刻变 14/15 PASS、laya 21.0s/20.9s。危害：①任何「打到调用面」的验收可能在 silently 度量旧产物，假绿或假红；②MCP 客户端连的也是这个入口（.mcp.json 走 moon run 会重建，但脚本轨不会）；③本仓守卫族没有任何一条比较 src/** 与入口产物的 mtime，BUG-22/30 的「守卫覆盖面窄于主张」在产物层重演。修复方向：scripts/fist.py 启动前比较 max(mtime of src/**, moon.pkg) 与 main.js，落后即自动 `moon build --target js cmd/main` 并 patch，或显式拒绝并提示重建；并把该顺序不变量纳入守卫族（可并入 check_plugin_sync 同级的新守卫）。

### FIXED(2026-09-26 pentad-r3 fix_and_merge / 终审人=指挥官，调用面实测)

scripts/fist.py 启动前比较 `max(mtime src/**.mbt|.mbti, moon.mod, moon.pkg)` 与入口产物：
落后即自动 `moon build --target js cmd/main`（幂等，随后仍走 patch_esm_main），`FIST_NO_AUTOBUILD=1` 时改为显式拒绝并退出 1，
不再出现"调用面终审静默度量旧二进制"。
证据（同一判据脚本 r3_callsite_audit.py J00 前提）：产物 19:01 < 源码 19:30 → 自动重建到 19:36；
`FIST_NO_AUTOBUILD=1` 同一状态下 rc=1 且文案点名两侧路径。终审另加 J00 顺序不变量：入口过期即 FATAL 作废全部判据。
已知缺口（诚实记账）：本条只有调用面证据，未进守卫族——守卫族判据必须能在 CI 里自证，而该不变量在"未构建的干净克隆"上必然为假。

## BUG-33 [2026-09-26T11:23:48Z] [high] OPEN
- summary: [bugfind:contract-debt] 45 个工具广告可选参数 now，全仓 0 处读取：调用方传 now 被静默丢弃
- detail: 实测（2026-09-26 11:22，指挥官独立复算）：`grep -c '"now": *string_prop' src/server/server.mbt`=45；`get_str(args, "now")` 在 src/** 全量=0；`now_default()`=47。即 server 时钟盖章（BUG-1 的正确修复）已落地，但 45 份 inputSchema 仍在承诺「时间戳(可选，默认内置)」——契约在说谎，且副作用是心跳陈旧/熔断恢复窗/Omega 新鲜度无法写确定性判据（注入不了受控时钟）。run_check:1121 的「服务端盖章」是诚实措辞样板。正确出路不是让 handler 重新接受 caller now（那会回退 BUG-1 的账本可反驳性修复），而是**停止广告**并写明由服务端盖章。

### FIXED(2026-09-26 pentad-r3 fix_and_merge / 终审人=指挥官，调用面实测)

停止广告无人读的时钟入参：server.mbt 里 45 处 `"now": string_prop(...)` 全部删除，
另有 6 处描述文案（含 run_check/task_plan_deep/circuit_*）里的「now 时间戳（可选）」改写为
「时间戳一律由服务端盖章，不接受调用方注入 now」。BUG-1 的服务端盖章语义不变（不回退）。
守卫：scripts/check_tools_sync.py 判据 5 同时禁止 schema 广告 `"now": string_prop` 与描述里的「、now 时间戳」（正则退化即 FATAL）。
证据：调用面 J03 全部 116 工具的 inputSchema.properties 无 now、J04 全部 description 无「now 时间戳」。

## BUG-34 [2026-09-26T11:23:49Z] [medium] OPEN
- summary: [bugfind:circuit-halfopen] 熔断 Half-Open 无探测节流：恢复窗内所有调用都放行，与工具描述承诺相反
- detail: src/engine/engine_circuit.mbt:140 `let allow = state != "open"` → half_open 对任何调用回 allow_call=true；全文件无 probe/节流计数。而 server.mbt:3311 的 circuit_status 描述承诺「Open 且 elapsed>=recovery_secs → 转 Half-Open（放行探测请求，**其余仍快速失败**）」。后果：恢复窗口全量透传，正是要防的下游踩踏；半开态退化成「只是换个名字的 closed」。判据：threshold=1 触发 open → 过 recovery → 连查 circuit_status N 次全 allow_call=true，无一次被挡。修复方向：半开态给探测配额（默认 1，可配 probe_limit），配额用尽即回快速失败；成功探测才复位。

### NOT-FIXED(2026-09-26 pentad-r3 / 指挥官终审：本轮不动，理由与出路记账)

本轮评估后**不改实现**，两条理由：① 探测配额要把"已放行探测数"持久化，`cb_get/cb_save` 的 7 元组要扩列（store 表结构 +
native/js 双后端 + 迁移），属跨模块契约变更，不在一轮 fix 的边界内；② 半成品节流（只在内存计数）会在多进程 MCP 下每进程各计一次，
比现状更容易误导——宁可不改。当前"描述承诺 vs 实现"的落差仍是活缺陷（OPEN），出路：cb 表加 `probe_count` 列，
`circuit_status` 转 half_open 时置 0，`circuit_fail/succeed` 之外的每次 half_open 放行先自增并在达 probe_limit(默认 1) 后返回 allow_call=false。

## BUG-35 [2026-09-26T11:23:49Z] [medium] OPEN
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

## BUG-36 [2026-09-26T11:23:50Z] [medium] OPEN
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

## BUG-37 [2026-09-26T11:23:50Z] [low] OPEN
- summary: [bugfind:phantom-guard] mode_list 的 forbidden_tools 写的是不存在的工具名，「禁发新功能」约束无可匹配对象
- detail: src/ops/ops_modes.mbt:142-143 发布禁用名单 `publish_new_feature_task` / `issue_scan_with_generate_new`，而 `fist.py list-tools` 对两者计数均为 **0**（真源 server.mbt 注册表也没有；实调 mode_list 已复核返回体）。后果：polish/tidy 模式的「禁止发布新功能」红线在机器面上是空的——按名单匹配拦截的下游永远匹配不到，约束只剩提示词文字。真实可拦截的同族动作是 `publish`（配 created_by 角色闭集）。修复方向：名单改成真实注册名并注明「按 (tool, role) 组合拒」，或明确该字段只是给人类读的文档（那就不该叫 forbidden_tools）。

### FIXED(2026-09-26 pentad-r3 fix_and_merge / 终审人=指挥官，调用面实测)

`mode_forbidden_tools` 换成真实注册名 `publish / publish_parallel / dag_publish`（src/ops/ops_modes.mbt），
并把同一臆造名从 polish/tidy/verify 三份模板里一并清掉（文档面同源）。诚实标注：本仓内没有自动拦截点，
该名单是给调用方/指挥官匹配用的机器面，名字不存在时红线才真正空转。
守卫：check_tools_sync.py 判据 4（名单 ⊆ tools/list 真注册集，解析到 0 个名字即 FATAL 不出绿灯）。
证据：调用面 J12 无越界名、J13 polish/tidy 名单非空且全为真注册名。

## BUG-38 [2026-09-26T11:49:59Z] [high] OPEN
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

## BUG-39 [2026-09-26T12:02:12Z] [medium] OPEN
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

## BUG-40 [2026-09-26T12:02:13Z] [medium] OPEN
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

## BUG-41 [2026-09-26T12:37:31Z] [medium] OPEN
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

## BUG-42 [2026-09-26T13:31:20Z] [high] OPEN
- summary: [verify][BUG-42] src/server/server.mbt project_standards 描述仍称一源三态/三形态/cl1-cl6：对外描述与工具输出（四态+cl7）自相矛盾，所有 MCP 客户端读到的是旧口径
- detail: 证据：temp/j_before_after.py 在 HEAD 内容上发红 32 条（J6=2/J7=11/J8=19），工作树为 0；temp/stdalign_verify.py 为本轮调用面终审。
- reported_by: std-auditor

## BUG-43 [2026-09-26T13:31:20Z] [high] OPEN
- summary: [verify][BUG-43] templates 的 FIST 调用示例用了未声明参数（output_validate 的 check_results、project_standards 的 project_dir/dry_run、evolve_distill 的 project_dir/round）并缺 required；_instrument 只校验 required ⇒ 未知键静默丢弃，照模板执行=以为验了其实没验
- detail: 证据：temp/j_before_after.py 在 HEAD 内容上发红 32 条（J6=2/J7=11/J8=19），工作树为 0；temp/stdalign_verify.py 为本轮调用面终审。
- reported_by: std-auditor

## BUG-44 [2026-09-26T13:31:20Z] [medium] OPEN
- summary: [verify][BUG-44] docs/agent-map.md 宣称测试数 316 项全绿（实测 406）；check_test_sync 只核对「实测数出现在 4 份文档」，不核对文档里的**其它**数字是否等于实测 ⇒ 数值声明无人管
- detail: 证据：temp/j_before_after.py 在 HEAD 内容上发红 32 条（J6=2/J7=11/J8=19），工作树为 0；temp/stdalign_verify.py 为本轮调用面终审。
- reported_by: std-auditor

## BUG-45 [2026-09-26T13:32:33Z] [high] OPEN
- summary: [verify][BUG-42] src/server/server.mbt project_standards 描述仍称一源三态/三形态/cl1-cl6：对外描述与工具输出（四态+cl7）自相矛盾，所有 MCP 客户端读到的是旧口径
- detail: 证据：temp/j_before_after.py 在 HEAD 内容上发红 32 条（J6=2/J7=11/J8=19），工作树为 0；temp/stdalign_verify.py 为本轮调用面终审。
- reported_by: std-auditor


### FIXED(2026-09-26 stdalign verify / 指挥官终审，调用面实测)

本条与 BUG-48 同一缺陷，因验证驱动 `temp/stdalign_verify.py` 首两轮在 `publish` 返回键（`task_id` 而非 `id`）上解析失败、
下游 Omega 链与生命周期整体走错分支，重跑时重复入账 ⇒ **重复条目，实际修复见 BUG-48 的 FIXED 段**。
教训入档：驱动重跑前应先幂等检查（同一 summary 不重复 report_bug）。

## BUG-46 [2026-09-26T13:32:34Z] [high] OPEN
- summary: [verify][BUG-43] templates 的 FIST 调用示例用了未声明参数（output_validate 的 check_results、project_standards 的 project_dir/dry_run、evolve_distill 的 project_dir/round）并缺 required；_instrument 只校验 required ⇒ 未知键静默丢弃，照模板执行=以为验了其实没验
- detail: 证据：temp/j_before_after.py 在 HEAD 内容上发红 32 条（J6=2/J7=11/J8=19），工作树为 0；temp/stdalign_verify.py 为本轮调用面终审。
- reported_by: std-auditor


### FIXED(2026-09-26 stdalign verify / 重复入账)

同 BUG-45：本条为 BUG-49 的重复（驱动重跑副作用），实际修复与证据见 BUG-49 的 FIXED 段。

## BUG-47 [2026-09-26T13:32:34Z] [medium] OPEN
- summary: [verify][BUG-44] docs/agent-map.md 宣称测试数 316 项全绿（实测 406）；check_test_sync 只核对「实测数出现在 4 份文档」，不核对文档里的**其它**数字是否等于实测 ⇒ 数值声明无人管
- detail: 证据：temp/j_before_after.py 在 HEAD 内容上发红 32 条（J6=2/J7=11/J8=19），工作树为 0；temp/stdalign_verify.py 为本轮调用面终审。
- reported_by: std-auditor


### FIXED(2026-09-26 stdalign verify / 重复入账)

同 BUG-45：本条为 BUG-50 的重复（驱动重跑副作用），实际修复与证据见 BUG-50 的 FIXED 段。

## BUG-48 [2026-09-26T13:34:23Z] [high] OPEN
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

## BUG-49 [2026-09-26T13:34:23Z] [high] OPEN
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

## BUG-50 [2026-09-26T13:34:23Z] [medium] OPEN
- summary: [verify][BUG-44] 数值声明无人管：docs/agent-map.md 宣称测试数 316 项全绿（实测 406）。check_test_sync 只核对「实测数出现在 4 份指定文档」，不核对其它文档里的数字是否等于实测，也不核对反向违例 ⇒ 文档里的旧数字可以长绿
- detail: 证据：temp/j_before_after.py 在 HEAD 内容上发红 32 条（J6=2/J7=11/J8=19），工作树 0；temp/stdalign_verify.py 为本轮调用面终审；修复落在 check_doc_surface J6/J7/J8 + 35 处文档口径对齐。
- reported_by: std-auditor



### FIXED(2026-09-26 stdalign verify / 指挥官终审，含判据缺口如实入账)

文档侧已改：`docs/agent-map.md`「316 项全绿」→「**406 项全绿**（2026-09-26 Windows 实测）」。
**判据缺口未在本轮闭合（如实声明）**：`check_test_sync` 的判据形状是"实测数出现在指定 4 份文档"，
天然测不到"第 5 份文档写着别的数"；要闭合需把扫描面从白名单改成全量文档并处理"历史数字豁免"（native 317/317 一类
合法旧数），属判据重设计，交下一轮处理。同类缺口见规范正文 §7「已知边界」。
## BUG-51 [2026-09-26T13:39:19Z] [medium] OPEN
- summary: [verify][BUG-51] 路径口径在工具间相反：report_bug/bug_list 拒绝绝对 project_dir（『非法 project_dir（拒绝绝对路径/穿越/盘符）』），而 run_check 又拒绝 workdir='.'（『workdir=. 与项目不同根（workdir 盘符= 项目盘符=E:）』，因任务 project_dir 记的是绝对路径）⇒ 照模板用同一个相对根跑完整链路必卡在第 3 步；两工具需统一路径策略或在描述里写明各自口径
- detail: 复现：temp/rc_raw.py（先 project_dir='.' 成功 report_bug，再 workdir='.' 被 run_check 拒；改 workdir=绝对根后通过）。失败本身是硬门且带 audit_log/call_log（可审计性合格），缺的是**口径一致性**。
- reported_by: std-auditor

## BUG-52 [2026-09-26T15:46:13Z] [high] OPEN
- summary: 上游 fist-model-router：时间戳↔秒用「365 天固定年 + 每月 31 天」近似，5h 窗口判定跨月/闰年偏移
- detail: 证据：源项目 src/model_router.mbt `iso_to_secs` 用 `(year-2024)*365 + (mon-1)*31 + day`，既不漏 4/6/9/11 月的 30 天也不管闰日 ⇒ `window_reset_check` 的 now_s-s>=18000 在跨月时最多偏 3 天，配额窗口实际不过期或提前过期。处置：合并时改写为 civil-days 精确算法（Howard Hinnant days_from_civil），回归锁 src/router/model_router_wbtest.mbt rt_1（含闰日 2028-02-29 精确秒数）/rt_2（非法时间戳一律 -1，不当成 0 参与减法）。
- reported_by: router-merge-r1


### FIXED(2026-09-26 六模式轮 · 合并 fist-model-router（指挥官终审） / BUG-52)

合并即修：`src/router/model_router.mbt` 改用 civil-days 精确换算（days_from_civil/civil_from_days），闰日与跨月都对。回归锁 rt_1（`2024-02-29`/`2026-03-01` 精确秒数）、rt_2（非法时间戳一律 -1，绝不参与减法）。

## BUG-53 [2026-09-26T15:46:13Z] [high] OPEN
- summary: 上游 fist-model-router：current_model() 在池为空时索引 [0] 直接 panic
- detail: 证据：源项目 Free/Paid 分支都写 `if idx < len { pool[idx] } else { pool[0] }`，空池时 len=0 ⇒ else 取 pool[0] ⇒ 越界 panic，MCP server 整条连接被打断。处置：合并后 current_model() 返回 ModelQuota?，pick 的两池皆空分支给available=false + 明确 reason（不静默换模型）。回归锁 rt_4（空池不 panic）/rt_5（两池耗尽显式不可用）、mo_3 与调用面判据 S04x。
- reported_by: router-merge-r1


### FIXED(2026-09-26 六模式轮 · 合并 fist-model-router（指挥官终审） / BUG-53)

合并即修：`current_model()` 返回 `ModelQuota?`，两池皆空走 `available=false` + 明确 reason。锁 rt_4（空池不 panic）、rt_5（全耗尽显式不可用）、mo_3（记账后仍无模型 ⇒ 点名「不会静默改用别的模型」）、调用面 S03/S04。

## BUG-54 [2026-09-26T15:46:13Z] [high] OPEN
- summary: router_restore 不夹紧越界游标：free_idx/paid_idx 为负时取模落到负下标（坏状态文件即可触发）
- detail: 证据：修复前 src/router/router_state.mbt 直接 `r.free_idx = st_int(sm, "free_idx", default=0)`，而 pool_pick 用 `(start_idx + i) % n`；MoonBit 的 % 与被除数同号 ⇒ -7 % 2 = -1，下一次 model_route 就按下标 -1 panic。坏/手改过的 memory/model-router-*.json 即可触发。活证据：白盒测试 rs_3 在修复前实测 FAILED（`false is not true`，warnings<3 且未夹紧），修复后 5/5 绿；夹紧行为由 rs_3 的 assert_eq(r.free_idx, 0) 与 warning 点名锁住。
- reported_by: router-merge-r1


### FIXED(2026-09-26 六模式轮 · 合并 fist-model-router（指挥官终审） / BUG-54)

`router_restore` 把 `free_idx`/`paid_idx` 夹紧到池内并对越界点名 warning；语义前提用 `assert_eq(-7 % 2, -1)` 写进测试（MoonBit 的 % 与被除数同号 ⇒ 负游标必然落负下标）。活证据：修复前 rs_3 实测 FAILED（`false is not true`），修复后 src/router 18/18 绿。

## BUG-55 [2026-09-26T15:46:13Z] [medium] OPEN
- summary: model_route 的 config_json 解析失败被静默当作「没传配置」，调用方以为覆盖了池定义实际用了默认池
- detail: 证据：修复前 src/server/server.mbt 写 `@json.parse(cj) catch { _ => Json::null() }`，而 `Json::null()` 在 router_restore 里正是「无配置」的语义 ⇒ 打错的 config_json 会静默改用 RouterConfig::default()（模型名完全不同），与 BUG-31/33/43 同族的静默降级。处置：新增 mr_parse_config（空串=不覆盖，非法 JSON=Err 并说明不回落），回归锁：调用面判据 S04（tools/call model_route --config_json '{"free_pool":[oops' → is_error）。
- reported_by: router-merge-r1


### FIXED(2026-09-26 六模式轮 · 合并 fist-model-router（指挥官终审） / BUG-55)

新增 `mr_parse_config`：空串=不覆盖（`Json::null()`），非法 JSON=Err 并在工具描述里写明「不静默回落默认池」。调用面锁 S04（tools/call 传 `{"free_pool":[oops` → is_error）。

## BUG-56 [2026-09-26T15:46:13Z] [medium] OPEN
- summary: usage_report.current_model 报的是轮询游标位而不是本次选中的模型，同一响应里与 decision.model 自相矛盾
- detail: 活证据（真实调用面，2026-09-26 实测）：`python scripts/fist.py call model_route --project_dir . --namespace rmscli` 返回 `decision.model=AtomGit-qwen3.8-27b` 而同一 JSON 里 `usage.current_model=AtomGit-glm5.3-flash`——pick 把游标推进到 (idx+1)%n 后，current_model() 读的是**下一个**候选，却被命名成「当前模型」。后果：agent 读 usage 段会以为用的是另一个模型，配额账与实跑模型对不上。处置建议：usage_report 报真实选中模型（ModelRouter 记 last_pick），游标位另起名 cursor_model。
- reported_by: router-merge-r1


### FIXED(2026-09-26 六模式轮 · 合并 fist-model-router（指挥官终审） / BUG-56)

`ModelRouter` 增加 `last_pick`，`pick` 收敛到单一 choke point 登记（force_switch 成功分支同步登记），`usage_report` 的 `current_model` 报真在用的模型、游标位另名 `cursor_model`，状态 schema 加 `last_pick`。成对锁 rt_13（两键必须不同，否则断言是空的）+ rs_1（跨进程往返）+ 调用面 S03c。

## BUG-57 [2026-09-26T15:46:13Z] [low] OPEN
- summary: scripts/issue_scan.py：`--include-tests false` 被当成开启（CLI 与 MCP 语义漂移）
- detail: 活证据：`python scripts/issue_scan.py src/router --include-tests false` 返回 `"include_tests":true` 且扫进了 2 个 _wbtest 文件（scanned_files=5）。根因 scripts/issue_scan.py:68 `include_tests = "--include-tests" in sys.argv`——只判存在不判值，而 MCP 形态该参数是 bool（默认 false），照 MCP 习惯写 `false` 的调用方拿到相反结果且没有任何提示，多余的位置参数也被静默忽略。处置建议：接受 `--include-tests [true|false]`，对无法识别的位置参数显式报错退出。
- reported_by: router-merge-r1


### FIXED(2026-09-26 六模式轮 · 合并 fist-model-router（指挥官终审） / BUG-57)

`scripts/issue_scan.py` 显式解析 `--include-tests [true|false]`，未知参数与多余位置参数直接 exit 2。实测：`--include-tests false` → `include_tests=False, scanned_files=3`（只产品代码）；`--includ-tests`（拼错）→ FAIL 并列出可用开关。

## BUG-58 [2026-09-26T15:46:13Z] [medium] OPEN
- summary: 守卫族在 GBK 控制台直接抛 UnicodeEncodeError，本地拿不到判定（只拿到 traceback）
- detail: 活证据：Windows 默认 GBK 控制台下 `python scripts/check_doc_surface.py` 打印 「J6 规范正文↔投影一致…」时 UnicodeEncodeError 崩在 print，退出码非 0；同一脚本 `PYTHONIOENCODING=utf-8` 下才输出 PASS。守卫族的「红」必须是判据红，编码崩溃冒充红色会让本地结论不可信（CI 在 Linux UTF-8 下掩盖了这件事）。同类：check_test_sync/check_badge/gen_plugins 的中文输出在 GBK 下是乱码（能跑但不可读）。处置建议：scripts/*.py 入口统一 sys.stdout.reconfigure(encoding='utf-8', errors='replace')。
- reported_by: router-merge-r1


### FIXED(2026-09-26 六模式轮 · 合并 fist-model-router（指挥官终审） / BUG-58)

`check_tools_sync/check_test_sync/check_badge/check_scripts_index/check_doc_surface/gen_plugins` 入口统一 `stdout/stderr.reconfigure(encoding=utf-8, errors=replace)`（另两条守卫本就有）。实测：不加 `PYTHONIOENCODING` 在 GBK 控制台直跑 6 守卫全部 PASS 且中文可读。

## BUG-59 [2026-09-26T16:04:49Z] [medium] OPEN
- summary: 父节点被自动提升为待验收时交付物为空，Omega 成果复验门禁与 execute 合法态互锁，无出路
- detail: 证据链（ns=router-merge，2026-09-26 实测）：子叶全 verify ⇒ 引擎把父节点提升「待验收」，但父节点 deliverable 仍为空；此时三条调用互相锁死——omega_result_verify 报「尚无交付物（deliverable 为空），无可复验成果」；execute 报「非法执行: 任务处于 [待验收]，合法路径：验收(verify)/需要改进(reject→已打回)/重试(retry→执行中)」；verify 报「Omega 强验证门禁：尚未做成果复验」。reopen_task 只支持已归档/已完成。⇒ 开了 omega_strong_verify 的递归拆解树，只要父节点没在子叶完成前自己 execute 过，就必然卡死，只能人工 reject→retry 绕一圈（本轮 5 个父节点全中）。
修法建议：①自动提升时把子叶交付的并集写进父节点 deliverable（最贴近语义，成本最低）；或②允许「待验收」态补记交付物（execute 在该态放行一次）；或③提升即视为无需复验（不建议，弱化门禁）。
- reported_by: router-merge-r1



### FIXED(2026-09-26 六模式轮 · 合并 fist-model-router（指挥官终审） / BUG-59)

`FistEngine::verify` 的父节点自动提升分支继承子叶交付并集（父节点已有交付则不覆盖，零回归）。锁 `src/engine/engine_promote_r6_test.mbt` 两条（提升即带交付 / 已有交付不被覆盖）。活证据：修复前本轮 5 个父节点全部卡在「待验收」——omega_result_verify 报无交付物、execute 报状态非法、verify 报门禁未过，只能人工 reject→retry 绕出（ns=router-merge 实测记录）。
## BUG-60 [2026-09-26T16:20:31Z] [medium] OPEN
- summary: evolve_critic 门禁在默认参数下永不可满足：中性 score=0.5 参与加权后 combined 上限 0.75 < 阈值 0.85
- detail: 活证据（2026-09-26 实测）：evolve_critic 的 score 属性描述写「默认0.5」，threshold「默认0.85」，而 critic_review 计算 combined=0.5*score+0.5*novelty ⇒ 不传 score 时 combined 最大 (0.5+1.0)/2=0.75，永远低于 0.85，任何候选都被判「稳健性不足，暂缓入库」。实测两次调用均 admit=false（score=0.5、novelty=0.887、combined=0.694）。第二个受害者是 task_challenge：src/engine/engine_challenge.mbt:115/140 硬传 0.5，于是 critic=true 的挑战题在任何档案库状态下都进不了门禁的"放行"分支——特性看起来开着，实际恒拒。门禁恒关比没有门禁更糟：它给出"已过审"的错觉。
- reported_by: router-merge-r1



### FIXED(2026-09-26 六模式轮 · 合并 fist-model-router（指挥官终审） / BUG-60)

中性分不再参与加权：`critic_review` 在 `score == 0.5`（= 没算分）时按 `novelty` 单独判，显式给分才走 `0.5*score + 0.5*novelty`。这样 `evolve_critic` 不传 score 与 `task_challenge` 硬传 0.5 两条默认路径都能真正过审，而漂移/重复防护不变。锁 `src/evolve/critic_test.mbt` 一条三判据：中性分+空库⇒放行、中性分+高重合⇒仍拒、显式 0.1⇒仍拒。
