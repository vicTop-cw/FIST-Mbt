# R125 报告：常驻入口 spawn moon 统一带 shim（moonc `\\?\` ICE 收口到调用面）

- 日期：2026-10-22
- 分支：`slave/fix/moon-spawn-shim-r125`
- 基线：`gitcode/master` @ `ede53f30`（开工 2531e6ad；R124 于本单交付期间并入主线，已叠线）
- 判据：`python scripts/fist.py call issue_scan` 自动重建不再 ICE；`moon_env_probe.py` 普查 11 份接线 / 违例 0

## 1. 结果摘要（结论 / 证据 / 分析）

- 结论：R124 只修了 `scripts/moon_test_env.py` 这一条入口；本轮把同一发现规则收成 `scripts/moon_env_probe.py` 单一真源，并接到本仓全部 8 个会 spawn `moon build/check` 的常驻脚本。干净 PATH 上没有显式 `MOONC_OVERRIDE` 时，各入口自动发现本机 `~/.moon-shim/shim.exe` 注入子进程；非 Windows 或垫片缺失时原样透传（零回归）。
- 证据：先复现——`scripts/fist.py` 的 BUG-32 自动重建撞 `Sys_error("\\\\?: Invalid argument")`，把工具链缺陷报成 `fist.py` 失败；接入后同一条命令（父进程 `env -u MOONC_OVERRIDE`）自动重建成功并返回 `{"scanned_files":132,"total_findings":0,...}`，rc=0，全程 8s。
- 分析：根因不在某一个入口，而在「每个入口自己拼 subprocess 环境」这一形状。只修 `fist.py` 会在下一个入口复现（R124 的教训同形）；因此本单不再零散补`env=`，而是提供可复用函数 + 带自证的静态普查：新增入口若 spawn moon 却没接 `moon_env()`，普查 rc=1 点名到文件与行号。
- 口径：普查是**文件级**判据（文件里出现 `moon_env(` 或 `moon_env_probe` 即算接线），不解析调用图；白名单三项逐条带理由，`--selftest` 会校验理由非空。

## 2. 实测读数（2026-10-22，master 2531e6ad）

| 步骤 | 命令 | 读数 |
|---|---|---|
| 复现（修前） | `python scripts/fist.py call issue_scan …`（无 override，产物过期触发重建） | 自动重建 rc=1，moonc `Sys_error("\\\\?: Invalid argument")` |
| 修复后 | 同上，父进程 `env -u MOONC_OVERRIDE` | rc=0，8s，`scanned_files=132 / total_findings=0 / filtered_out=981` |
| 普查 | `python scripts/moon_env_probe.py` | rc=0，`scanned=11 / allowlisted=3 / violations=[]`，自动发现 shim 路径 |
| 自证 | `python scripts/moon_env_probe.py --selftest` | rc=0，11 格（D×5 / A×4 / L×2） |
| 电池登记 | `python scripts/check_battery_count_doc.py` | rc=0，`rulers=88 ci=41 battery=50 missing=0 gate=58 exempt=27 unclassified=5` |
| 索引/自述 | `check_scripts_index.py` / `check_selftest_inventory_doc.py` | 均 rc=0；31 条判定族逐一对表通过 |
| 编码面 | `check_py_stdout_encoding.py --all` | rc=0，该带闸 107 份 / 已带 107 份 |
| 命名面（预存红） | `check_scripts_naming.py` | rc=1：N1 无角色 22 > 上限 16、N2 连字符 5 > 上限 4；电池已按 `expected=1` 登记（清单含主线 BUG-327 刻意降级的 `_` 临时件与 `_tool_registry.py`），非本单引入 |

## 3. 改动清单

- `scripts/moon_env_probe.py`（新）：`moonc_override`（显式 env 优先 / Windows 自动发现 / 其他不设）、`moon_env`（返回子进程环境副本，不改 `os.environ`）、`audit`（静态普查）、`decide`（0/1/2 三档 + 空扫描自拒）、`--selftest` 11 格。白名单：`moon_test_env.py`（R124 自带同一逻辑，MR 待合）、`check_fmt_gate.py`（只 `moon fmt`，不经 moonc）、`check_exit_code_contract.py`（`["moon"]` 在字符串夹具里）。
- 接线 8 个入口：`scripts/fist.py`（BUG-32 自动重建）、`scripts/fist-mbt-web.py`（产物缺失补建）、`scripts/fist-gate.py`（4 处 `run()` 定义统一带 env）、`scripts/whisperer.py`、`scripts/check_slave_mergeability.py`、`scripts/simulate_head_commit.py`、`scripts/refresh_dist.py`、`scripts/award_demo.py`。
- `scripts/run_guards.py`：新增 `case("moon_env_probe.py")` + `case(..., "--selftest")`（裸跑=静态普查，只读且快）。
- `scripts/README.md`：新增 `moon_env_probe.py` 条目（含 11 格反解）并同步 `BATTERY-REGISTRATION` 锚点到现读；`AGENTS.md` 环境要求段补常驻入口统一注入 `MOONC_OVERRIDE`。
- 本报告 + `memory/2026-10-22.md` 追记。

## 4. 资源消耗

- 会话轮次：副机自驱 R125 轮；主要耗时在冷/热构建验证与两轮治理守卫。
- 外部资源：零网络、零依赖安装；shim 为本机既有件（`~/.moon-shim/shim.exe`），未入仓。
- 测试读数：端到端 1 发 rc=0；探针自检 11/11；全量电池终读见 §5。

## 5. 电池终读

- 待填（post-push 全量 `python scripts/run_guards.py`）。

## 6. 任务分配记录

- 本单无主机下发 TASK 对应（主仓 backlog 仅 TASK-016-docs 属 atomcode，其余 in_review）；为副机自驱发现。
- 单 agent 直做，无子代理派发；终审由本会话执行（py_compile + 探针自检 + 端到端 + 治理守卫 + 全量电池）。

## 7. 遗留风险

- 普查是文件级判据：同一文件里只要出现 `moon_env(` 就放行，无法保证每个 spawn 点都带 `env=`；这是为兼容 `fist-gate.py` 的 `run()` 间接层做的取舍，行级判据会与间接层互掐。
- `moon_test_env.py` 仍列白名单：R124 已并入 master（ede53f30），但本单不改其 12 格自检面；后续单应把发现规则收敛到 `moon_env_probe` 并删白名单（否则同规则两份实现会漂）。
- `scripts/blackbox/*` 与 PowerShell 构建脚本（`build_release.ps1` 等）不在本单扫描面；native 探针在 CI Linux 上跑，不涉及 Windows ICE。
- shim 仍是机器级依赖（宿主既有绕法，不在仓库内）；换机/重装需重建，未修 moon 上游。
- 发现但**未在本单修**：`scripts/fist-mbt-web.py` 的 `ensure_mcp_build()` 只判产物是否存在、不判新鲜度，与 docstring「已存在且新鲜」不符（源码更新后可能静默用旧产物）。建议另单登记。

## 8. 后续建议

1. R124 合入后，`moon_test_env.py` 改为调用 `moon_env_probe.moon_env()`，删白名单，形成单一真源。
2. 给 `fist-mbt-web.py` 补产物新鲜度判据（或以 BUG 登记后单独修）。
3. 若 moon 上游修复 `\\?\` ICE，删除自动发现，只保留显式 env 透传与普查。
4. PowerShell 入口如需本机冷缓存构建，另做 `$env:MOONC_OVERRIDE` 的等价接线。

## 9. 超额内容

- 把「接线」做成了可回归的静态普查（裸跑 + 自检两个电池格），而不是一次性 8 处 `env=` 补丁；下一份 spawn moon 的脚本漏接线时，电池会先红。
- 普查对空扫描面自拒（rc=2），避免目录改名后判据空转报绿。

## 10. 来源

- 代码：`scripts/moon_env_probe.py`（`moonc_override` / `moon_env` / `audit` / `decide` / `selftest`）、8 个入口的同名调用点、`scripts/run_guards.py` SPECIAL_CASES 的 R125 两格。
- 文档：`scripts/README.md` 同名条目与 `BATTERY-REGISTRATION` 锚点、`AGENTS.md` 环境要求段。
- 观测：`env -u MOONC_OVERRIDE python scripts/fist.py call issue_scan …` 的自动重建行与 JSON 回执；`~/.moon-shim/shim.exe` 的既有绕法（R124 同源）。
- 命令：见 §2 表格。
