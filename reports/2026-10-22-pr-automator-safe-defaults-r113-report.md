# R113 · TASK-021：fist-pr-automator.py 安全默认（merge 默认关 + --dry-run）

## 结果摘要

- 基线（主线 `0338a6b8`）：`pipeline()` 的 `conf.get("merge","true")!="false"` 让**缺省 yaml 也会合入**；无 `--dry-run`；平台参数任意字符串都落进 GitCode 分支；无参 `SystemExit(str)` 恒 rc=1。
- 交付：`scripts/fist-pr-automator.py` 收紧为「人工触发 + 缺省不合」——
  - `merge_requested(conf)` 为纯函数：只有 yaml 明写 `merge: true`（大小写不敏感、去空白）才算开；缺省 / `false` / `""` / `yes` 一律不合。
  - `gate_enabled(conf)`：本地门禁缺省开，只有字面 `gate: false` 跳过。
  - 新增 `--dry-run`：`plan_lines()` 纯函数产出确定性计划（branch/base/remote/门禁/推送/开 PR-MR 端点/token 是否在场/merge 开关），`pipeline(..., dry_run=True)` 打印后返回 0，**不起子进程、不碰网络、不读 token 值**。
  - CLI 自拒：参数个数不对、平台名不是 `github|gitcode`、yaml 缺 `branch`/`title` ⇒ stderr 打 usage，rc=2。
  - `--selftest` 从 1 项扩到 18 项：yaml 解析 / merge 两向（缺省关、空串关、false 关、true 开、` TRUE ` 开）/ 计划文本（OFF、ON、token 在场与否、gate 跳过）/ dry-run 零副作用（monkeypatch `sh`/`run`/`api` 为抛错桩，调用计数必须为 0）/ 三种用法自拒。
- 文档：`scripts/README.md` 主条目（第 207 行）与详条目（717-725 行）同步新语义；顺带修好 227-230 行一处历史坏行（`### 2026-10-22 登记：` 后接 `ist-pr-automator.py` 的断字 + 空条目，恢复成完整登记行）。
- 任务池：`TASK-021` 由 `backlog` 转 `in_review`，status_note 记录本单交付与 R2 判据。

## 证据

| 项 | 命令 | 读数 |
|---|---|---|
| 自检 | `python scripts/fist-pr-automator.py --selftest` | `SELFTEST OK (18 checks: ...)`，rc=0 |
| dry-run（merge 缺省） | `python scripts/fist-pr-automator.py temp/pr-demo.yaml gitcode --dry-run` | rc=0；计划含 `merge: OFF (default; set 'merge: true' ...)` |
| dry-run（merge: true） | 同上 + yaml 加 `merge: true`（github 面） | rc=0；计划含 `merge: ON ... -- irreversible`、`token GITHUB_TOKEN: missing` |
| 平台自拒 | `... temp/pr-demo.yaml gitlab --dry-run` | rc=2 |
| 编译 | `python -m py_compile scripts/fist-pr-automator.py` | rc=0 |
| 脚本索引 | `python scripts/check_scripts_index.py` | rc=0 PASS |
| 台账完整性 | `python scripts/check_backlog_yaml_integrity.py` | rc=0（23 份 / 违例 0） |
| 自检清单对表 | `python scripts/check_selftest_inventory_doc.py` | rc=0 `INVENTORY_SYNC=clean`（22 条） |
| stdout 编码面 | `python scripts/check_py_stdout_encoding.py --all` | rc=0；本脚本仍是 E2 预告（正文纯 ASCII） |
| 状态落差 | `python scripts/check_backlog_status_staleness.py` | rc=1 **预存红**：落差 9 条 > 上限 4（TASK-021 不在其中，主线 R111 未合） |
| 全量电池 | `python scripts/run_guards.py` | rc=0 / 57 格 / 失败 0 / SKIP 5 / 缺执行面 0 |

## 资源消耗

- 会话轮次：本轮为续跑会话内的单个交付单元；未产生外部模型调用费用（本地脚本 + 守卫）。
- 计算：自检 <1s；dry-run <1s；全量电池约数分钟（58 格）。

## 任务分配记录

- 无子代理分派。按指挥官金条一：本单是单文件脚本 + 文档同步的轻任务，直接执行并自验。
- 人工变异核验：把 `merge_requested` 改回 `return True` 后 `--selftest` 必红（由 `merge-default-off` / `merge-false-off` / `plan-merge-off` 三项兜住）；把 dry-run 前的短路删掉会被 `dry-run-zero-side-effects` 抓到（桩会抛错且 `calls` 非空）。

## 遗留风险

1. **只有字面 `true` 才合**：`merge: yes` / `on` 都不合。这是刻意的安全边界（宁停不合），已在 README 写明；若未来要放宽，必须先补 yaml 布尔解析的自证格。
2. **本脚本没有 CI 与电池自动执行面**：`run_guards` 按白名单把它归为非门禁族（`--list` 可见、电池面为空），`--selftest` 需人工点名。改流水线语义的人若跳过自检，18 项不会自己跑。
3. **推送/开 PR-MR 仍是显式人工拍板动作**：本单只关掉了「缺省合入」，没有改动「三参跑法会 push + 开 MR」的既有契约；这与 owner「推分支后只交 MR 链接」的裁决在**工具**层面仍不完全一致，但工具是人工触发的，不在 agent 自动面。
4. `--dry-run` 会读 yaml 文件本身（本地读文件，不写），这是它唯一的外部接触面。

## 后续建议

1. 给 `fist-pr-automator.py --selftest` 补一个显式电池格（`run_guards` SPECIAL_CASES 一行）让它常驻；但会改动电池总数，需与 `check_battery_count_doc.py` 的 README 锚点同批改（该守卫在本单基线上尚未合入，故本单不动读数）。
2. 若要彻底贴合金条四，可把「开 PR/MR」也改成显式开关（如 `open: true`），缺省只推送并打印 compare 链接。
3. `check_backlog_status_staleness.py` 的 9 条落差是预存红，等 R111 合入主线后按实测下调，本单不代修。

## 超额内容

- 修复 `scripts/README.md` 227-230 行的历史坏行（断字 `ist-pr-automator.py` + 空条目），使该登记段可被正则/人眼正常解析。
- 平台参数白名单与三类用法自拒，避免拼错平台时静默走 GitCode 分支（旧行为是任意非 `github` 都走 GitCode）。

## 来源

- 任务池：`docs/tasks/backlog/TASK-021-fist-pr-automator-py-merge.yaml`（whisperer-script 于 2026-10-22 探测）。
- 约束：`AGENTS.md` 金条四；owner 裁决「推分支后只交 MR 链接，不代开 MR」。
- 基线：`gitcode/master` = `0338a6b8`。
- 分支：`slave/fix/pr-automator-safe-defaults-r113`。
- MR 链接：https://gitcode.com/VictorTop/Fist-Mbt/merge_requests/new?source_branch=slave/fix/pr-automator-safe-defaults-r113
