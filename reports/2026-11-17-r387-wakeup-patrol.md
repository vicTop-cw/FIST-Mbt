# 轮 387 巡检报告

> FIST-Mbt ExploreWatchdog 唤醒轮（Windows 计划任务，每 30 分钟无窗）。
> 生成时刻：2026-11-17。报告文件即本轮 FIST 任务的 deliverable。

## 一、WIP 收口核查（巡检分支判定）

`git status --short` 与 r386 一致：**6 M + 1 untracked**，无新收口、无新起 WIP：

| 文件 | numstat | 状态 |
|---|---|---|
| dist/fist-mbt.js | 76721 变更 | M（中止轮再生，r384 记录，未提交） |
| memory/bugs.md | 216+ | M（外来账冻结，r378 起，第 65+ 轮） |
| memory/target.md | 1/1 | M（巡检 WIP，冻结面） |
| scripts/README.md | 1/1 | M（iter-r192 车道 F 提交③在途：R192 T0r2 登记同步） |
| scripts/check_plan_landing.py | 144（+/−） | M（iter-r192 车道 F 在途：:864 子串排除修复 + selftest 64→71 格） |
| templates/pipeline_mode_loop.md | 1/1 | M（J8 修复：run_check 示例补必填 task_id/cmd，排提交③） |
| reports/2026-11-17-iter-r192-report.md | untracked | iter-r192 收口报告（**在途**，自述车道 M/X/Y 未回传） |

⇒ **iter-r192 收口进行中**（车道 F 提交③未落库），禁区零碰。`src/**` 与 `scripts/run_guards.py`
维持 r385 确认的已解禁态，但 **Round C 队列（既定迭代目标）已由 r385 逐项核实全消并移交 owner 设
下一目标** ⇒ 本轮无既定目标可执行，走**巡检分支**：非阻塞换面 + FIST 闭环记账，不代设目标、不重跑
已否决动作（BUG-527 治本，重跑必红 CI native）。

## 二、换面巡检：check_host_installable（宿主侧「真的能装上」守卫 · cl7 补丁）

**为何选此面**：r386 刚跑 check_battery_count_doc、r385 跑 check_store_tables_wired、r384 及更早
近 ~20 轮（r367~r385）的换面面清单里 check_host_installable 未在近轮覆盖（上一次本地实跑读数在
2026-11-01 晚巡检：PASS + `timeout_ms` 信息级 WARN 既有项）⇒ 不撞面。该面守的是「插件态 == 投影」
（cl7）之外的另一半——**投影一致 ≠ 真能装上**：DSH 宿主严格档（绝对路径 / `toolCallTimeoutMs` /
reconnect schema）+ Claude 宽松档 + 默认模板三档，字段白名单反解自 `mcp_config_scaffold` 真源。
只读、判据语义窄而清晰，且是发布面（`plugins/` 投影随版本发货）的装机可行性守门。

### selftest（判据健康性，先判尺子不坏）

`SELFTEST OK 宿主可装性判据可红可绿（DSH 严格档：相对路径/timeout_ms/reconnect 键名/未定义占位符 必红；
干净 DSH + 默认模板 + 宽松档 不误红；输入面退化自拒；字段白名单反解自真源）`，`RC=0`。

⇒ **判据健康**：可红可绿双向 + 输入面退化自拒 + 白名单真源反解，非恒绿。

### 实跑（现状面）

`PASS 宿主可装性：DSH manifest/patch（严格档：绝对路径 + toolCallTimeoutMs + dsh reconnect schema）合规；
宽松档 MCP JSON 合规；默认模板合法性合规；moon.mod 版本 0.3.11`，`RC=0`。

三条 **WARN（信息级，不计入退出码）**：`.mcp.json/fist-mbt`、`.mcp.dev.json/fist-mbt`、
`plugins/claude/.mcp.json/fist-mbt` 用 `timeout_ms`——部分客户端按自身 schema 忽略该字段，
**是否改真源由人终审**。与 2026-11-01 晚巡检读数逐条一致（同 3 条、同措辞）⇒ **既有已知项、零漂移**，
非本轮新发现，不立账（立账口径：同一已知项重复巡检不重复立单）。

## 三、换面巡检：OFM 端点探活（127.0.0.1:18326/v1）

- 端点真源：env `FIST_OFM_ENDPOINT=http://127.0.0.1:18326/v1`（HKCU\Environment，2026-11-01 owner
  授权 setx 改至 18326；会话 env 与注册表逐字一致）。
- 探活（TCP 层，不涉 key）：`curl --max-time 5 http://127.0.0.1:18326/v1/models` ⇒ **HTTP=000、
  curl rc=7（连接失败）**；`netstat` 无 18326/18899 监听行 ⇒ **relay 服务未起**。
- 对照：2026-10-31 全链报告实证该端点曾 HTTP 200 + 152 模型；2026-11-01 实测即已「relay 服务未起
  （WinError 10061），探活读数 1」，并记「是否查启动方式待 owner 答复」⇒ **本轮与 11-01 同态，
  非本轮回归**；属 owner 待答项（是否/如何启动 relay），不在巡检轮代行，不新立 BUG 号（既有待答项
  已在 2026-11-01 报告留痕）。

## 四、FIST 闭环

**T0r143 六步全链 rc=0**（wd-r387 / ns watchdog / `temp/fist_r387_chain.sh` 稳健 TID 提取后台串跑，
patch_esm_main 探针先行 10 bundle 全 up to date / total patched 0）：
publish rc=0 → TID=T0r143 → acl rc=0 → claim rc=0 → execute rc=0 → submit rc=0 → verify rc=0。
verify 字段：`status=已完成`、`completed_by=wd-r387`、`assignee=wd-r387`、
`deliverable=reports/2026-11-17-r387-wakeup-patrol.md`、`namespace=watchdog`、
`created_at=2026-11-17T06:38:49Z` / `updated_at=2026-11-17T06:38:55Z`。

## 五、禁区与立账

- **禁区零碰**：6 个 WIP 修改文件 + 1 个 untracked 报告零改零提交；插件态 / 构建产物 / PATH 垫片
  本轮均未写。patch_esm_main 探针只动 `_build/`（gitignore 面），不碰 dist/ WIP。
- **无新立账**：两面巡检均无新发现（host_installable 零漂移、OFM 未起为 11-01 既有待答项）；
  bugs.md 属 WIP 冻结面不代改；Round C 队列空属「既定目标完成/过时、非代码缺陷」，不立 BUG 号
  （同 BUG-636 临时立账口径逆向）。

## 六、结论

本轮换面巡检两面均干净：**check_host_installable**（selftest rc=0 可红可绿 + 全量 PASS rc=0，
3 条 `timeout_ms` 信息级 WARN 与 11-01 逐条一致为既有项）⇒ 宿主可装性面无新发现；**OFM 端点
18326** curl rc=7 未监听 ⇒ 与 2026-11-01 实证同态（relay 未起，owner 待答项，非回归）。WIP 面
6M+1untracked 与 r386 一致 ⇒ **iter-r192 收口进行中**、禁区零碰。既定迭代目标（Round C 队列）
维持 r385 移交态：不代设、不重跑已否决动作（BUG-527 治本）。FIST 闭环见第四节。
