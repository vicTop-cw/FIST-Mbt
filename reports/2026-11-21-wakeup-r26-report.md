# 2026-11-21 唤醒巡检 R26 报告 —— EP-03 派发评审终审 + 近 10 笔提交门禁审计

> 触发：Windows 计划任务 FIST-Mbt-ExploreWatchdog（30min 无窗唤醒）。本轮为 findings-only 巡检：
> 主工作树 43 文件 WIP 属 f094 多管家收口中（src/**、run_guards.py、plugins/**、docs 均未解禁），
> Round C 队列按 r385 已全消（BUG-527 治本被 A/B 裁决否决、BUG-530 FIXED、check_usage_tool_count 已注册）。
> ⇒ 走唤醒协议步骤 3：非阻塞巡检、避开他方 WIP、不改任何码。

## 结果摘要

- **EP-03 派发评审（HEAD 18810300b，子代理只读评审 + 指挥官亲读终审）**：
  - **本体健康**（已亲读 `scripts/fist_dispatch.py` 全文核实）：stale/chain 双模式无条件反转、
    主路径无吞异常、argparse 形状 1（`--mode choices` 拒未知旗标，`--stale-vs/--staleness/--chain`
    三个错拼均被拒）、退出码契约 0/1/2 自洽、dup-gate 收敛语义正确（publish 失败 cursor 不推进，
    下轮 dup 闸收敛无重发风暴）、ts 字典序=时间序（服务端定宽 UTC 串）、`"verified"` 事件名与服务端对齐、
    FIST_DB_PATH 隔离传递性合规（spawn 仅拉 `sys.executable fist.py`，由 `fist.py:51-52` 的 BUG-122 针兜底，
    本脚本不进 `check_demo_isolation` 扫描面属判定正确而非漏扫）。
  - **#1 [高·静态推演未实跑] watcher 双 dispatch 规则疑似永不命中**：`.mcp-watch.json` 规则 2/3 的
    子目录 glob `.fist-mbt/data/fist-self-tidy.db*` 是三段锚定，而 watcher 发出的事件路径带监控根前缀
    （`watch_dir: "."` → `./…`，native 后端 `watch_native_stubs.c:130-137` 根原样拼接、js 后端
    `watcher_js.mbt` `join_path`），matcher 段锚定算法首段即 false ⇒ 永不命中；js 后端另叠加
    `recursive` 被忽略（`backend.mbt:205-212` `let _ = recursive`）。对照组：规则 1 `BACKLOG.md`
    basename 匹配能命中 ⇒ **同一份配置 1 活 2 死，说明子目录模式形态没被实测过**。
    定案法（一条命令）：daemon 起后 `touch .fist-mbt/data/fist-self-tidy.db-wal` 看 `fist_stale_dispatch`
    是否被调起。
  - **#2 [高·机制亲证 / 本机不复现] 子进程 stdout 编码错配**：`fist.py main()` 强制
    `sys.stdout.reconfigure(encoding="utf-8")`（BUG-138 闸，亲读 `scripts/fist.py` 属实）×
    `fist_dispatch.py:43` `text=True` 无 `encoding=` → locale 解码。中文 Windows cp936 机器上
    中文载荷（状态「待领取」、中文 ns/描述）大概率 `UnicodeDecodeError` 或 JSON 被字节配对破坏。
    **本机实测 `preferred-encoding=utf-8`、`fist.py --help` 经 subprocess 捕获 rc=0 不复现** ⇒
    机器相关缺陷降级定性（Linux/UTF-8 locale 或 `PYTHONUTF8=1` 下不触发）。
  - **#3 [中·判据实跑双红实锤]**：`python scripts/check_py_stdout_encoding.py --all` → FAIL
    （E1：fist_dispatch.py print 非 ASCII 却无 UTF-8 重配闸）；`python scripts/check_scripts_index.py`
    → FAIL（fist_dispatch.py 未在 scripts/README.md 登记，R62）。
  - **#4 [中] 三层超时错配**：watcher `ExecPolicy` 硬编码 60s（`action.mbt:81`）< 脚本
    `CALL_TIMEOUT_SECS=120` < 本机单次 `fist.py call` node 冷启动 ~2min × 每轮 2-3 次调用 ⇒
    即使 #1 修好，本机动作也会被 watcher 先杀。
  - **#5 [中] 上游 mcp-watcher 面**：monitor 订阅只挂 `subscribe_on_next` 无 on_error
    （监控源出错 daemon 变聋、无日志无重启）；规则 1 `recursive: true` × basename `BACKLOG.md`
    的全树误伤面（`.mooncakes/`、`temp/` 内任何同名文件都触发）。
  - **#6 [低] 边角**：chain `--limit 5` 固定窗尾漏（停机期 >5 条非 verified 事件会吃掉窗口外旧
    verified）；`--stale-days` 无下界、服务端 `stale_days*86400` Int32 溢出（>24855 变负全量判 stale）；
    docstring 承诺的 `"checked"` 键实际未输出（:20 vs :103）；argparse `allow_abbrev` 缩写放行
    （`--stal 5` 被静默接受，不违反形状 1 但比仓库严格参数面宽松）。
- **提交门禁合规审计（近 10 笔，`git log --stat` 逐笔）**：
  - **A1 [中]**：`be5f154f8`（0.3.15 查询三件套）moon.mod 版本前进 + server.mbt 增 3 工具，
    同笔**无**计数面（README/AGENTS/inventory/help_topics 五盲区面）与**无** plugins/** 投影——
    `check_plugin_sync`（manifest==moon.mod）/`check_tools_sync`/`check_doc_surface` 在该笔推演必红。
    现状：plugins/**、README、USAGE、AGENTS、inventory 等全在 WIP = f094 在飞补救中（同族先例：
    `b0d30ba4a` bugs.md +312 与 dist 大改同样无 plugins 同批）。
  - **A2 [中·判据实跑红]**：`18810300b`（EP-03）新增 `scripts/fist_dispatch.py` **无同批执行面**
    （battery case / expected / EXEMPT_RULES / 下划线前缀四选一零命中，违反 2026-10-24 判例-5 规则，
    `check_battery_count_doc` 对该脚本会报缺面）+ R62 索引未登记（实跑红）+ BUG-138 编码闸缺失
    （实跑红）。
  - **A3 [观测·在飞态]**：`check_battery_count_doc` 现读红：X1 尺登记 158/现读 159、X6 豁免 23/24
    ——f094 的 WIP `run_guards.py` 加了 1 尺 1 豁免但未同步 scripts/README.md 的 BATTERY-REGISTRATION
    锚（他方在飞，记录不代修）。

## 资源消耗（模型与工具清单）

- 模型：主线 1（指挥官终审/审计/记账）+ 子代理 1（EP-03 只读评审，78 轮 / 106 工具调用）
- 工具：read_file / grep / glob / list_directory（代码面与 ns 库面）、bash ×4（三条判据实跑 +
  最小复现 + 新鲜度探测）、task ×1（子代理评审）、write_file ×2（链脚本）、bash_start ×1（FIST 链）
- FIST 闭环：publish→claim→execute→submit→verify 五步（结果见下节）

## FIST 闭环记账

- ns = `wakeup-patrol`（历轮唤醒巡检同库）；链脚本 `temp/fist_r26_chain.sh`（稳健 TID 提取
  `temp/fist_r26_tid.py`，r318 口径：只认「能解析为 JSON 的行」）。
- 产物新鲜度前置探测：`_build/js/debug/build/cmd/cli/cli.js` mtime 03:33:54 新于最新源
  （src/server/tool_cov_query_tools_test.mbt，02:40:03）⇒ **未触发 BUG-32 自动重建**，
  链在他方 WIP 源码之上安全运行（度量的是 03:33 构建面）。
- 链结果（收口于 04:03:50，五步全 rc=0）：
  - 首发 publish → **T0**（wakeup-patrol ns），回执自带 **BUG-411 警告当场应验**：该 ns 零 agent
    持 can_write ⇒ 紧接 claim 被 ns ACL 拒（两种拒法：assignee 身份 fp=2634605c3b5c5281、
    execute/submit 缺省身份 `manual` fp=020934005581bee2）——BUG-408「角色矩阵 ≠ ns ACL」两道独立门
    的一次活体复现，publish 回执的预警告与实际拒绝完全一致。
  - 按报错处方①闭环：`agent_acl_grant(agent_id="commander-atomcode", can_write=true)`
    （human_steward 特权路径 rc=0，granted_rows=[fp]）→ claim/execute/submit/verify 补跑全 rc=0，
    状态推进 已领取→执行中→待验收→**已完成**（completed_by=commander-atomcode）。
  - 台账中文经 read_file 直解 UTF-8 验证**无写花**（bash cat 显示的 mojibake 为输出层伪影，
    非数据损坏）。
  - 链模板经验：execute/submit 不带显式 `--agent` 会落到缺省身份 `manual`（需单独授权）——
    唤醒链从此固定显式身份；重跑只补后续步骤、绝不重发 publish（r318 口径）。

## 任务分配记录

- EP-03 代码评审（只读、findings-only）→ 子代理（无 shell，评审其可读面）；
- 评审终审（亲读承重行）、判据实跑定案、git 提交审计、FIST 链记账 → 主线
  （git/判据执行需 shell，子代理无 shell 属工具面边界而非越权亲为）。

## 遗留风险

- **#1 未实证**：watcher glob 失配是静态推演；若实证为真，EP-03 的核心卖点（写事件自动派发）
  在当前形态为零——且每次误触发是 2-3 个 node 冷启动的纯浪费。
- **f094 收口时的三件同步缺一即 CI 红**：battery 锚（158/159、23/24）、scripts/README 登记
  fist_dispatch.py、fist_dispatch.py 补 UTF-8 闸——本轮三处判据已实跑留红。
- **ledger 缺口**：本轮 6 项缺陷候选**未入 memory/bugs.md**（gen_plugins 同批约束会重投影
  他方 WIP 的 plugins/**，避撞）——全部靠本报告留痕；f094 收口轮或下一安全窗口需决定立账。

## 后续建议

1. **f094 收口轮一笔带齐**：plugins 投影 + 计数面（README/AGENTS/inventory/help_topics/
   ARCHITECTURE/tool_use_rubric/agent-map/deliverable 八面同批）+ battery 锚 + scripts/README
   登记 fist_dispatch.py。
2. **EP-03 修复包候选**（建议立 BUG 待安全窗口）：`.mcp-watch.json` 子目录模式改相对形态或
   matcher 加监控根剥离；`fist_dispatch.py:43` 加 `encoding="utf-8", errors="replace"` + 补
   stdout reconfigure 闸；ExecPolicy 60s → ≥300s；chain `--limit 5` → 游标化。
3. **mcp-watcher 上游面**（rx-mbt / mcp-watcher 包，单独 ISSUE）：on_error 出口、js 后端
   recursive 支持。
4. **#1 定案实跑**并入 EP-03 修复轮验收：daemon + touch wal + 断言 `fist_stale_dispatch` 触发。

## 超额内容

- battery 锚漂移（A3）与构建产物新鲜度前置探测属计划外，但前者是判据实跑的顺带产物、
  后者是 FIST 链能否安全起跑的必要前置，均在巡检职责内。

## 来源

- `git log -10 --stat`（提交面）；`scripts/fist_dispatch.py` 全文亲读；`scripts/fist.py` :45-52/:417-422 亲读
- 判据实跑：`check_py_stdout_encoding.py --all`（RC=1）/ `check_scripts_index.py`（RC=1）/
  `check_battery_count_doc.py`（RC=1）；最小复现：`preferred-encoding=utf-8` + `fist.py --help` 捕获 rc=0
- 子代理评审报告（78 轮，read-only，其静态推演项已在本报告逐条标注「推演未实跑」）
- FIST 链：`.fist-mbt/data/wakeup-patrol.db`、`temp/fist_r26/chain.log`
