## BUG-1 [2026-09-26T03:52:44Z] [high] OPEN
- summary: 任务行时间戳由调用方 now 决定并被真实写库，账本可被写成未来时间（审计不可反驳性失效）
- detail: 现象：publish/claim/execute/submit/verify 等写操作接受可选 now 参数，且该值被真实写入 tasks.created_at/updated_at；而 call_log.ts 由服务端盖章。二者权威不一致，导致同一份账里存在两种时钟。

活证据（2026-09-26，cron-cypy 实测）：`python scripts/fist.py list '{"namespace":"cron-cypy"}'` 与 `date -u` 对比，6 行 updated_at 比真实 UTC 晚 7.5~8.3 小时（T0r258.1.1 09:46Z / .2.1 09:52Z / .3.1 09:58Z / .4.1 10:04Z / .5.1 10:10Z / .4.2 10:31Z，真实当时 02:14Z）；同期 `call_log` 最近一条 ts=02:13:53Z 与真实 UTC 02:13:52Z 差 1 秒。成因是驱动脚本自造单调时钟（为满足 omega_gate.mbt:119 的新鲜度规则 check.created_at >= task.updated_at）。

二次伤害：未来时间戳烘进 updated_at 后，之后**省略 now** 的 run_check 用服务端真实时间反而永远不新鲜，verify 被真实拒收；已完成任务的 deliverable/时间戳没有任何合法迁移可回改，只能在报告里勘误。

源码位置：src/ops/audit.mbt:5 的设计说明「时间戳由调用方传入 now（测试确定性、无隐式系统时间依赖）」——该设计对测试合理，但对**持久化的任务账本**不成立。

建议：持久层时间戳一律服务端盖章（now 仅作为可注入的测试替身，且需在非测试模式下被忽略或明确告警）；新鲜度比较（omega_gate.mbt:119）应在同一权威时钟下做；文档里写清「now 不可用于生产账本」。
- reported_by: cypy-commander

## BUG-2 [2026-09-26T03:52:44Z] [medium] OPEN
- summary: retry 之后无法登记交付物：execute 只接受 拆分中/已领取，而 retry 落在 执行中，形成状态机死角
- detail: 现象：`reject`（待验收->已打回）后走 `retry`（已打回->执行中，src/core/core_task.mbt:463），但唯一能写 deliverable 的 `execute` 要求状态 [拆分中/已领取]（同文件 :368 的守卫文案即报错原文），于是在「已打回重做」这条最该更新交付物的路径上写不进新交付物；`omega_result_verify` 随即报「尚无交付物」。

活证据：本轮 R1 收口 cron-cypy/T0r61 与 R2 收口 T0r258.4.2 时均实测到该死角，绕行路径是合法迁移 `pause`（任意活跃状态->已暂停）→ `resume`（已暂停->已领取，:493）→ `execute`。绕行可行，但：① 任务会留下一条虚假的「已暂停」历史；② 该绕行在 MCP 工具名上还有二次坑（工具名是 `resume`，域函数叫 `resume_task`，按域名调用返回 Tool not found）。

影响：被拒后重做无法原地更新交付物，容易诱导操作者改为「新建任务覆盖旧账」，破坏 append-only 审计。

建议：把 execute 的合法前态扩到 [拆分中/已领取/执行中]（执行中重复 execute = 追加或覆盖交付物本就是直觉行为），或在 retry 的语义里把状态退回「已领取」。
- reported_by: cypy-commander

## BUG-3 [2026-09-26T03:52:44Z] [medium] OPEN
- summary: audit_log 作为治理查询面暴露，但实现是进程内不落库，跨进程永远返回 []（假空的审计证据）
- detail: 现象：MCP 工具 `audit_log`（描述为「查看追加式审计日志」）读的是进程内 AuditLog，**不落库**；每一次 MCP 调用新起一个 server 进程时，它返回空数组，而库里其实有完整写入痕迹。

活证据（2026-09-26 实测）：`python scripts/fist.py audit_log '{}'` → `[]`，而同一时刻 `python scripts/fist.py call_log '{"limit":400}'` 显示当天该库已记录上百条调用（含本流水线 cron-cypy 的 64 条 publish/claim/execute/submit/omega_*/run_check/verify/pause/resume）。

影响：这是审计面最坏的一种失败——**看起来没有发生过任何治理动作**（空证据），而不是报错。若有人用 audit_log 判断「谁在什么时候做了什么」，会得到系统性的假阴性，还可能据此得出「没有人越权」的错误结论。

建议：① 要么把 AuditLog 落库（与 call_log 同表或独立表），要么 ② 在工具描述与返回值里显式标注「仅本进程生命周期内的审计，跨进程请用 call_log」，并让空结果可区分（如返回 {scope:'process', entries:[], note:...}）。src/ops/audit.mbt:4 的设计注释应同步到对外契约。
- reported_by: cypy-commander

## BUG-4 [2026-09-26T03:52:44Z] [high] OPEN
- summary: run_check 用 node child_process.spawn 执行任意命令，无白名单/无授权位/无 workdir 约束（宿主级命令执行面）
- detail: 现象：`run_check` 为了「防自写自测恒绿」在服务端真实执行外部命令，实现是 src/server/run_check_js.mbt:15 的 `js_run_command(cmd, args, workdir, timeout_ms)` → spawn(cmd, args, {cwd})。整个文件不存在任何 allowlist / 授权检查 / 路径约束（`grep -n 'allow|whitelist|白名单|拒绝|forbidden' src/server/run_check_js.mbt` 无命中）。同类原语还有 src/server/github_js.mbt:41,:91 与 src/server/laya_js.mbt（spawn sh / ComSpec -c 形式，更接近任意 shell）。

实测：本轮驱动多次以 `cmd=python`、`cmd=bash`、甚至绝对路径 `D:/Program Files/Git/usr/bin/bash.exe` 成功 spawn，workdir 可指到项目目录之外的任意路径；`call_log` 记录了这些调用的入参。

缓解现状：argv 形式（非 shell -c）使 run_check 本身不拼字符串，注入面比 laya/github 的 `sh -c` 小；但任何能连上这个 MCP 端口的客户端都等价于拿到了宿主命令执行能力（server 进程权限）。

影响与定位澄清：这更像「按设计如此」的能力，但对一个会被多个流水线、多个 agent 并发连的常驻服务，缺的是**默认收紧**而不是能力本身。

建议（择低到高）：① cmd 白名单（默认只允许项目脚本解释器 + 显式登记的判据命令），配置项驱动；② workdir 限定在项目目录子树内，越界直接拒绝并落审计；③ laya/github 的 `sh -c` 路径改 argv；④ 在 README/工具描述里明确「run_check = 宿主 RCE 能力，勿暴露给不可信客户端/网络」。
- reported_by: cypy-commander

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

## BUG-7 [2026-09-26T05:55:47Z] [medium] OPEN
- summary: BUG-5 resolved_path check

