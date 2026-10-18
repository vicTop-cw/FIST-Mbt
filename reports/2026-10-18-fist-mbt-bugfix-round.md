---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_840c3b94cacc11f18b7f525400393706
    ReservedCode1: /jpADHs4ViW5toWUSOubF3ib7685nANlVZRPrc/mNfDHOrtsJwPe0irCWbKTi/0hLwevD6J+tLRMEWdYVTx5PdWjnSvUj59qo3s/X2l6hnj9uqN0fPh73xR5dlRbE1iOFkB0vMfk6MhzTSKZE06yBri4O/thUmBpAUrM1VIiRiSerygRcU6KcTkz6iI=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f2a11add43fbf12a546606fb2b962ab_840c3b94cacc11f18b7f525400393706
    ReservedCode2: /jpADHs4ViW5toWUSOubF3ib7685nANlVZRPrc/mNfDHOrtsJwPe0irCWbKTi/0hLwevD6J+tLRMEWdYVTx5PdWjnSvUj59qo3s/X2l6hnj9uqN0fPh73xR5dlRbE1iOFkB0vMfk6MhzTSKZE06yBri4O/thUmBpAUrM1VIiRiSerygRcU6KcTkz6iI=
---

# FIST-Mbt 修复轮报告（BUG-261 / BUG-262 / BUG-268）

- 日期：2026-10-18
- 范围：仅代码修复与文档更新；**未提交 git、未 push、未发布**（master 保持 ahead 292）。
- moon.mod version：**0.3.8（本轮未变更）**；moon test 全量 **1302/1302 通过（failed 0, RC=0）**，moon fmt 通过，moon build --target js cmd/cli 0 errors。

## 一、BUG-261 — e2e_irm_line 真面档探针恒红（[medium] OPEN → FIXED）

**位置**：`scripts/blackbox/e2e_irm_line.py` — `probe()`（L296-320 区域）、`_find_posix_shell()`（L283-293）、`_is_wsl_bash()`（L267）。

**修复内容**（按 bugs.md 修法建议收口）：
1. 真面档（无 sbin）不再用 `[ -x 'fist' ]` 裸词测试（`-x` 不查 PATH 恒假）；
2. 改经 `_find_posix_shell()` 定位目标 shell：显式探测 4 处 Git Bash/MSYS 路径（`C:\Program Files\Git\bin\bash.exe`、`usr\bin\bash.exe`、`C:\msys64\usr\bin\bash.exe`、`C:\Program Files\MSYS2\usr\bin\bash.exe`），`shutil.which("bash")` 兜底并用 `_is_wsl_bash()`（winreg 查 App Paths\bash.exe）排除 system32/windows 的 WSL bash；
3. 两者都没有时打印「判据拒绝出数 rc=3」并返回 `REJECT` 标记，`real()` 见 REJECT 即写 `temp/e2e-irm-real.txt`（判定=REJECT）并 **return 3**（对齐 e2e_native_heap_probe 的 rc=3 语义，绝不把"没法跑"报成产品红）；
4. 找到 shell 后以 `command -v fist` 定位并**点名该 shell** 执行版本/doctor 行为面；
5. 沙箱档（传 sbin 全路径）的 `-x` 用法本身合法，保持不动。

**验证**：`python -m py_compile` 干净；静态确认真面档在无 Git Bash/MSYS 机器返回 REJECT(rc=3) 而非 MISSING。

## 二、BUG-262 — e2e_irm_line --real 无 PATH/shim 还原保护（[medium] OPEN → FIXED）

**位置**：`scripts/blackbox/e2e_irm_line.py` — `real()`（L498-560 区域）、`_userprofile_redirected()`（L486-495）。

**修复内容**（两条修法建议均落地，双保险）：
1. **入口硬拒**：`real()` 在裸形拒绝检查后新增 `_userprofile_redirected()`（SHGetFolderPathW 取 CSIDL_PROFILE 与 env USERPROFILE 比对，空值兜底），不一致即判定重定向 agent 会话，打印「--real 会污染真实用户环境，拒绝执行」并 **return 2**，把污染挡在入口；
2. **基线比对还原**：`real()` finally 块采集真实用户 PATH（`ps_path`）与真实 `.local\bin` 四件 shim（fist / fist.cmd / fist-mbt / fist-mbt.cmd，取 CSIDL_PROFILE 面、不受会话 env 重定向带偏）的 sha8 基线，逐件备份到 `temp/irm-sandbox/backup-shim-*`，跑后逐字比对：PATH 被改写即 `set_path` 还原基线、任一 shim 被改写即复制备份还原（对齐 `arm()` 的 finally 纪律，即使 run_line 抛异常也执行）；
3. js 产物保留既有「跑前备份、不绿自动还原」。

**验证**：`python -m py_compile` 干净；静态确认四件 shim 与 PATH 还原分支在位。

## 三、BUG-268 — issue_scan substring-overrun 假阳性（[medium] FIXED，本轮收口补充）

**位置**：`src/server/issue_scan.mbt` — `scan_substring_arg_expr` / `scan_guard_for_bounded` / `scan_filter_guarded` 等。

**背景**：上一轮（commit 15fe403，BUG-268 已标 FIXED）新增三类守卫检测消除 memory.mbt:165-166、mcp_config_scaffold.mbt:138、ops_selfdrive.mbt:587 三处假阳性；但全量重扫仍有 3 条 substring-overrun medium 残留，本轮定位并修复三处守卫逻辑缺陷：
1. **`scan_substring_arg_expr` 括号截断**：遇内层括号（如 `names.length()` 的 `)`）提前 break 致 end_expr 提取失败 → 改为括号深度计数、匹配到配对的 `)` 才停；
2. **`scan_guard_for_bounded` 头尾未修剪**：`for i in 0..<26 {` 尾部 `{` 未修剪致整数字面量解析失败 → 补修剪 `{`/`}`/空格；
3. **近邻守卫窗口过窄**：仅 6 行，不足覆盖 mcs_lower 中 upper/lower 定义距使用 9 行的场景 → `scan_filter_guarded` 窗口扩至 **12 行**。

**验证结果**：
- `python scripts/issue_scan.py src` 全量扫描：**126 文件、9721 findings，by_severity.medium 归零（6 → 0，substring-overrun 0 条）**；
- 三条残留经人工复核确认为安全模式（`d=rem%16` 模不变量 / `for i in 0..<26` 有界下标 / 多行 if-else 长度守卫 / has_suffix 减裁保证 end<=length），**无真阳性误豁免**；
- `moon test --target js` 全量 **1302/1302 通过（failed 0, RC=0）**；
- `moon fmt` 通过；`moon build --target js cmd/cli` 0 errors（cli.js 已重建并含新函数）。

## 四、文档更新

- `memory/bugs.md`：BUG-261、BUG-262 状态由 OPEN 改为 FIXED，保留原 OPEN 的 renumbered_from/summary/detail/reported_by，追加 FIXED evidence 块；BUG-268 在既有 FIXED 块下追加本轮收口补充 evidence。
- 本报告：`reports/2026-10-18-fist-mbt-bugfix-round.md`。

## 五、未做事项（按任务约束）

- 未提交 git、未 push、未发布（master 仍 ahead 292，无新增 commit）。
- 未运行 `--real` 真面安装（避免改真实产物；修复逻辑经 py_compile + 静态确认验证）。
- 未跑 gen_plugins.py / 未触碰其他 src 文件。
*（内容由AI生成，仅供参考）*
