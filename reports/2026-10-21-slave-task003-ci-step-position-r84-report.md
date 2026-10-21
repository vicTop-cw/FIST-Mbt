# 2026-10-21 副机 R84 报告 — TASK-003：CI 步骤位置门 check_ci_step_position.py

## 结果摘要

- 新守卫 `scripts/check_ci_step_position.py` 落地（TASK-003 验收①）：把「gate 步骤必须住在 Migrate 之前 / 新增 gate 必带 position-why」从 CI #275 的教训机械化。
  - F1（判定面，棘轮 34 只许降）：gate 步骤（name 命中 gate/guard/守卫/门禁 或 run 块引 `scripts/check_*.py`）在 Migrate 之后且步骤块内无 `position-why:` 锚点。
  - F2（只报不判）：continue-on-error 步骤逐处点名，实测 3 处（ci.yml `Format check`×1、`Public install line e2e`×1、fist-ci.yml `Format check`×1）。
  - F3（只报不判）：无 Migrate workflow 的 gate 步骤豁免，实测 0 处。
  - 自拒面：目录缺/无 yml/0 步骤/0 Migrate 基准 ⇒ rc=2。
- ci.yml 在 Migrate 之前加两步（各带 position-why，验收③）：
  1. `CI-step-position guard`（selftest + 全量）——真门禁。
  2. `Plan-landing ratchet gate`——**观测臂（continue-on-error: true）**。见「遗留风险」。
- 执行面三处齐备：ci.yml 步、run_guards.py 电池两格（SPECIAL_CASES）、scripts/README.md 登记。
- 真源读数：7 workflow / 107 步骤 / 5 Migrate 基准 / F1=34（=上限）/ rc=0。

## 资源消耗

- 1 个会话轮次内完成判据+接线+自检修正；无外部 API/网络消耗；未动任何 .mbt/.mbti。

## 任务分配记录

- 副机（本会话）独立完成：判据编写、自检九格（T1–T9）、ci.yml 接线、电池登记、README 登记、真源标定。

## 遗留风险

1. **TASK-003 验收②的「真门禁」半格未完成**：`check_plan_landing.py --gate` 现读 rc=1（判定面 36 > 上限 25，超 11 条）。硬挂会把 master CI 挂红；升档 25→36 是人的决定（BUG-367 ④ 同款先例）。本轮以**观测臂**过渡：continue-on-error: true + position-why 如实写明「升档待 owner 裁」，红不红如实给读数——CI 里看得见，不静默。
2. **34 条存量锚点未补**：逐条补 position-why 或前移可降档（棘轮只许降），建议后续单做。
3. 自检首跑抓出本尺 3 处自家 bug（合成格 rc 用棘轮不用检测 / F3 误入棘轮计数 / F2 按 gate 名分类漏真 coe 步骤），已全部修正——但说明第一版判据本身也需自检，本尺的九格自此常驻电池。
4. **master 预存红（非本单引入，需 owner 处理）**：
   - `check_bug_reference_integrity.py` rc=1：判定面 J1 悬空-注释面 **17 条 > 上限 1**——`memory/bugs.md` 无 BUG-147/327/333/336/384/385 抬头，而 17 处注释引用散在 engine/issue_scan/ocr_scan/server（BUG-384/385 来自 259b56a、BUG-333/327/336 来自更早的 host 提交）。master 的「Bug-reference integrity guard」CI 步现读应为红。
   - 全量电池本地 34 失败：绝大多数为本机环境预存（moon build 缺、demo 脚本需 MCP server/实参、POSIX-only 探针 rc=3、moonc ICE 致 fist-gate fmt 查 rc=2）；与本单相关的仅 1 条——check_publish_payload P1（新脚本尚未 git add，提交后即消）。另有 master 电池设计缺陷已顺手修（见超额）。

## 后续建议

- owner 裁 BUG-367 ④（25→36 或先降存量）后，把 Plan-landing 观测臂的 continue-on-error 撤掉即完成验收②。
- 存量 34 条锚点按 job 分批补：每补一条棘轮可降 1，降完可把 CI-step-position guard 从「位置+锚点」升级为「位置零容忍」。

## 超额内容与来源

- **顺手收口一处 master 预存红**：`check_scripts_index.py` 在 gitcode/master 37bf57c 上 rc=1——host 提交了 `fist-gate.py` 但 scripts/README.md 无其条目（R83 分支登记过但未合入）。本 PR 补了一条**最小登记**（只描述 master 现状的五查门链 + selftest，末尾注明「--scan 子命令以 R83 分支侧为准」），避免本分支电池红。合并顺序提示：若 R83 MR 先合，此条目需与 R84 版本对表去重。
- **修掉 master 电池整轮挂死（TASK-007 实现缺陷）**：host 版 `run_guards.py` 的 `discover_scripts()` 宇宙含全部 .py，未排除长驻服务脚本——本轮全量电池实测：`fist-mbt-http.py` 被自动补格后裸跑起 serve 永不退出（e2e_http_contract 之外无终止路径），父进程 `subprocess.run(capture_output)` 因孤儿子进程握着 stdout 管道而永久阻塞（17 分钟 0 CPU 实证）。CI 不受影响（只跑 `--selftest`/`--list`），但本地电池从此没人能跑完。修复：EXCLUDE_EXACT 增加 `fist-mbt-http.py` / `fist-mbt-web.py` 两行长驻服务脚本（R84 注记写进 docstring）。来源：R84 全量电池验证时挂死现场。
- 自检修正 3 处属判据自身质量收口，来源：--selftest 首跑 rc=2 的 FAIL 行逐条点名。
