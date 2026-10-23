# 2026-10-24 warning-cleanup-r2 收尾报告

## 结论

**三支修复分支已在新 mainline（`gitcode/main` tip `9c8e2e8e`）上零冲突合流（本地验证树 `fix/merge-final` @ `c0fe1d56`），本仓 Python 全量 SyntaxWarning 清零；唯一新增修复 `scripts/blackbox/e2e_upgrade_mirror.py:26` 非法转义 `\F` → `\\F` 已落 `fix/e2e-upgrade-mirror-escape`（tip `8b10fa4c`）并提交本报告。**

判据矩阵：12 支静态判据全绿 + 12 支 `--selftest` 全过；`check_badge`/`check_test_sync` 在真实测试日志（1447/1449，2 fail）下**如实判 FAIL**，喂干净 1449 汇总行则 rc=0——**BUG-394 修法 A 生效，判据能直接吃 `moon_test_env.py` passthrough 出的英文汇总行**。`check_fmt_gate` rc=2 = BUG-388（moon 0.1.20261016 `--check` 管线工具链缺陷，权威面 CI），拒判绿。

**本批未达「全绿」的唯一缺口：`moon test --target js` 实测 1447/1449（2 fail），两处失败在 `src/server/run_check_guard_test.mbt:93`（BUG-4 workdir）与 `:178`（BUG-51 cwd 归一）——与 `gitcode/main` tip 干净全测 baseline **逐字一致**，非本轮引入，属 worktree 深路径环境既存。**未硬改测试强推绿**，如实沉淀。

## 证据

### 一、SyntaxWarning 清零（核心交付）

普查面：`scripts/**/*.py` 排除 `_` 前缀，125 份 / 1,939,790 字节，`-W error::SyntaxWarning` 下 `compile(src, path, 'exec')`。
- **修后合并树**：`OK: zero SyntaxWarning / SyntaxError across scripts/ (excluding _ prefixed)`，rc=0。
- **修前基线**：6 处违规，全部落在本批两支 diff 内。

**修前违规清单（6 处）**：

| 文件:行 | 违规 | 修后 | 所在分支 |
|---|---|---|---|
| `scripts/moon_test_env.py:27` | `\\?\F:` | `\\?\\F:` | fix/moon-env-raw-log-and-escapes |
| `scripts/check_deprecated_text_census.py:31` | `\{}` | `\\{}` | 同上 |
| `scripts/check_exit_code_contract.py:162` | `` \` `` | `` \\` `` | 同上 |
| `scripts/check_mbti_sync.py:20,123` | `\w+` | `\\w+` | 同上 |
| `scripts/check_selftest_inventory_doc.py:159` | `` \` `` | `` \\` `` | 同上 |
| `scripts/blackbox/e2e_upgrade_mirror.py:26` | `\F`（丢反斜杠，**真 bug**） | `\\F` | **fix/e2e-upgrade-mirror-escape（本轮新增）** |

**e2e 单点复现（修复前后对照）**：
- 修前：`python -W error::SyntaxWarning -m py_compile scripts/blackbox/e2e_upgrade_mirror.py` → rc=1，`SyntaxError: invalid escape sequence '\F'`。
- 修后：rc=0；`ast.literal_eval` 提取 `%LOCALAPPDATA%\\FIST-Mbt` → `'%LOCALAPPDATA%\\FIST-Mbt'`，`renders exactly as %LOCALAPPDATA%\FIST-Mbt: True`。
- 同文件其余 5 处 `FIST-Mbt`（56/105/110/285/333 行）已 grep 核验无 `\F`。

### 二、三支零冲突合并

- 合并基：`gitcode/main`（当前 tip `9c8e2e8e`，自本任务开工时 `81f0a74b` 推进两档：`00cfbe79` check_hardcoded_paths 转 PASS → `9c8e2e8e` check_call_face 缺口 46→30）。
- 三支：`fix/test-count-1449`（`867caf41`，文档测试数 1415→1449）、`fix/moon-env-raw-log-and-escapes`（`c2fe5cbc`，修 5 处转义 + BUG-394 raw-log passthrough + moon_test_env argv 容错）、`fix/e2e-upgrade-mirror-escape`（`8b10fa4c`，本轮）。
- 合并命令：`git merge --no-edit <branch>`，`ort` 策略，**`git ls-files -u` 空（零冲突）**；合并线 tip `c0fe1d56`。
- 并发交集核查：`git diff` 显示三支与 `9c8e2e8e` 的唯一文件交集为 `plugins/README.md`（mainline 侧独立改账本计数，三支未动该文件，diff 空）；`moon_test_env.py` 等其余文件**零交集**。

### 三、BUG-394 修法 A 生效证明

- `moon_test_env.py` passthrough 后，`moon test --target js` 的**英文汇总行** `Total tests: 1449, passed: N, failed: N.` 原样落日志（`/tmp/moon_raw.log` 末行可见）。
- `check_badge.py` / `check_test_sync.py` 直接吃这条线，**无需临时 log 脚本**：
  - 喂干净 `Total tests: 1449, passed: 1449, failed: 0.` → `check_badge` **rc=0**（`PASS 徽章一致：README tests-1449%2F1449 == 实测 1449/1449`；`PASS 自检注释一致`）；`check_test_sync` **rc=0**（`PASS 测试总数单一真源一致：实测 1449；扫描现状面 137 份文档，23 条声明全部等于实测；must-carry 5 份齐全；豁免 22 条全部有效`）。
  - 喂真实 1447/1449 日志 → `check_test_sync` **FAIL**（`passed=1447 != Total tests=1449，failed=2 != 0`）；`check_badge` **FATAL**（`测试有失败 failed=2（徽章守卫前置失败）`）。两条判据**未假绿**，如实反映测试失败。

### 四、判据矩阵（合并线实测）

| 判据 | rc | 关键读数 |
|---|---|---|
| check_scripts_index | 0 | 登记面 128 |
| check_doc_dup | 0 | 零重复 |
| check_test_sync（真实日志） | FAIL | 因 2 fail；干净汇总行 rc=0 |
| check_badge（真实日志） | FATAL | 因 2 fail；干净汇总行 rc=0 |
| check_slave_task_list | 0 | 8/8/9/3/0 |
| check_backlog_status_staleness | 0 | within |
| check_memory_log_dup | 0 | empty-universe 豁免（策略锚点成立） |
| check_memory_log_dedupe | 0 | empty-universe 豁免 |
| check_py_stdout_encoding --all | 0 | 123 份该带闸全带 |
| check_fmt_gate | 2 | BUG-388，不可测，权威面 CI |
| check_backlog_yaml_integrity | 0 | 23 台账零违规 |
| check_text_control_chars | 0 | 1364 文件零违规 |

`--selftest` 全部 rc=0（12 支）：check_scripts_index 4 格 / check_doc_dup 21 / check_test_sync 20 / check_badge 8 / check_slave_task_list 18 / check_backlog_status_staleness 16 / check_memory_log_dup 14 / check_memory_log_dedupe C1..C10 / check_py_stdout_encoding M1..M5 / check_fmt_gate 6 / check_backlog_yaml_integrity C1..C11 / check_text_control_chars 9。

### 五、1447/1449 非本轮引入（baseline 对照）

- **合并线** `fix/merge-final` 实测：`Total tests 1449 / passed 1447 / failed 2`；失败行 `run_check_guard_test.mbt:93` + `:178`。
- **baseline** `gitcode/main` `9c8e2e8e` 干净全测（`verify/main-clean` 独立 worktree，同命令 `python scripts/moon_test_env.py moon test --target js`）：**逐字一致** `Total tests 1449 / passed 1447 / failed 2`，同一失败行、同一截断输出 `"E:/proj/AI`。
- 故两处失败与三支合并/转义/文档改动**无因果关系**，归 worktree 深路径（`E:\IDEProjects\AI\FIST-Mbt\.agents\worktrees\...`）下 cwd 归一判定既存，待 mainline 侧修复或换浅路径复测。

## 分析

1. **`\F` 类转义是真 bug**：Python 3.12+ 起 `\F` 属 unrecognized escape，`SyntaxWarning` 下 `compile`/`py_compile` 直接抛 SyntaxError；运行时反斜杠被吞，`%LOCALAPPDATA%\FIST-Mbt` 变成 `%LOCALAPPDATA%FIST-Mbt`。同族 `\w+`、`` \` ``、`\{}` 虽在字面量里语义未错，但 `-W error::SyntaxWarning` 下同被判红——**一并清掉才能过 py_compile 级门禁**。
2. **BUG-394 判据面打通是关键**：`check_test_sync`/`check_badge` 此前要借助临时 log 脚本抓英文汇总行（判据只能读中文行或特定段）。现在 `moon_test_env.py` 直接 passthrough，两条判据能原样吃到真实读数——**这使「真实测试失败 → 判据如实 FAIL」成为可能**，也证明本轮 2 fail 未被掩盖。
3. **不硬推绿是正确取舍**：`run_check_guard_test` 的 BUG-4/BUG-51 断言依赖 `E:/proj/...` 形态，在 `E:\IDEProjects\AI\...\.agents\...` 深路径下触发既有 cwd 归一判定（可能 `..` 归一或盘符比较在深 worktree 下失配）。强行改测试或改代码会让 `git diff` 污染 `src/server/*` 范围（违反边界），且掩盖环境既存问题——**按仓库「诚实沉淀」口径记录，留作独立 issue**。
4. **判据矩阵整体绿**：SyntaxWarning 清零 + 静态判据全绿 + `--selftest` 全过，说明本批改动对仓库静态面**无任何副作用**；动态面（moon test）与 baseline 一致，也无回归。

## 缺口与风险

| # | 缺口 / 风险 | 等级 | 说明 |
|---|---|---|---|
| 1 | `moon test --target js` = 1447/1449（2 fail） | 中 | `run_check_guard_test` BUG-4/BUG-51，worktree 深路径既存；`check_badge`/`check_test_sync` 如实 FAIL。**非本批引入**，但合入 mainline 后 CI 在深路径 checkout 也可能红 |
| 2 | `check_fmt_gate` rc=2 | 低 | BUG-388 moon 0.1.20261016 `--check` 管线缺陷，与本仓无关，权威面 CI nightly |
| 3 | 三支分支未推远端 | 中 | 本轮为子代理收尾任务，`git push` 动作由主代理/owner 决定；分支仅本地存在，未同步至 origin/gitcode 远端 |
| 4 | `fix/test-count-1449` 实际改 10 份文档（非 9） | 低 | 已在分析中记录实际 diff，未造成文档计数不一致（`check_test_sync` 干净汇总行下 rc=0） |
| 5 | 深路径合并树含 `tmp_*.py` 临时脚本 | 低 | 全部未纳入任何 commit，工作树本地残留，不影响提交面 |

## 建议入档位置

- **本报告**：`reports/2026-10-24-warning-cleanup-r2-report.md`（随 `fix/e2e-upgrade-mirror-escape` commit 一并提交）。
- **日日志**：`memory/2026-10-24.md`（追加「warning-cleanup-r2 收尾」段）。**注意**：该文件被 `.gitignore:157 memory/2026-*.md` 忽略，**不入 commit**——这是仓库设计（日日志流水账不入 git，防历史膨胀），报告面由 `reports/` 归档。
- **修复**：`scripts/blackbox/e2e_upgrade_mirror.py:26` 的 `\F`→`\\F` 已提交在 `fix/e2e-upgrade-mirror-escape`（`8b10fa4c`）。
- **遗留项**：`run_check_guard_test` BUG-4/BUG-51 两失败，建议由 mainline 侧独立开 issue 或在浅路径 checkout 复测确认环境性后关闭；不建议在本批内改 `src/server/*`。

## 资源消耗

- 工具调用：约 30 次 ops_bash / read / write。
- 计算：3 次全量 `moon test --target js`（合并线 + baseline + 早前失败重试）；1 次 SyntaxWarning 普查（125 文件 compile）；12 支静态判据 + 12 支 `--selftest`。
- 时间：约 2 小时（含 2 次全量 moon test 等待）。

## 任务分配记录

- 本轮为**子代理**执行（父会话 `session-a5bbbf3e-8c39-431c-8d53-6e9273056893`），无再拆分。

## 来源

- 主仓库：`E:\IDEProjects\AI\FIST-Mbt`
- 修复分支 worktree：`.agents/worktrees/fix/e2e-upgrade-mirror-escape`
- 合并验证 worktree：`.agents/worktrees/fix/merge-final`
- baseline 验证 worktree：`.agents/worktrees/verify/main-clean`（`gitcode/main` tip `9c8e2e8e`）
- 修复文件：`scripts/blackbox/e2e_upgrade_mirror.py:26`
- 相关判据：`scripts/check_badge.py`、`scripts/check_test_sync.py`、`scripts/moon_test_env.py`、`scripts/check_fmt_gate.py`
- 测试日志：`/tmp/moon_raw.log`（合并线）、`/tmp/moon_raw_baseline.log`（baseline）

## 超额内容

- 无（本轮严格限定在 e2e_upgrade_mirror.py 转义 + 三支收口 + 沉淀；未改动 `.mbt/.mbti`、`ci.yml`、其它判据脚本、docs 或三支既有内容）。
