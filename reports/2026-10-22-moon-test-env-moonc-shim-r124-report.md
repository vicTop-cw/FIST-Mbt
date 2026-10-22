# R124 报告：moon test 执行面第二道坑（moonc `\\?\` ICE）收口 + BUG-380 结案

- 日期：2026-10-22
- 分支：`slave/fix/moon-test-env-moonc-shim-r124`
- 基线：`gitcode/master` @ `8e6e5444`
- 判据：`python scripts/moon_test_env.py` = Total tests 1387 / passed 1387 / failed 0, rc=0

## 1. 结果摘要（结论 / 证据 / 分析）

- 结论：`scripts/moon_test_env.py` 之前只修了「node.cmd 垫片吞 JSON 引号」一道坑；清干净 PATH 之后，**冷编译面**仍会撞 moonc 的 `\\?\` 路径 ICE（`Sys_error("\\\\?: Invalid argument")`），守卫诚实返回 rc=2。本单把第二道坑纳入同一常驻入口：Windows 上自动发现 `~/.moon-shim/shim.exe` 并设 `MOONC_OVERRIDE`（显式环境变量优先），找不到则照跑、但 ICE 出现时点名成因并 rc=2。
- 证据：同一基线两条对照——无 override `moon check --target js` rc=1（moonc ICE）；设 override 后 rc=0（46 tasks / 506 warnings / 0 errors）。全量测试经守卫跑出 1387/1387 passed, rc=0。`--selftest` 12 格全绿。
- 分析：R54 的「1387/1387」是在 `_build` 热缓存上取得的读数——编译面没有被真正踩过；本单先复现冷编译 ICE，再验证 override 修复，读数才覆盖完整执行面。这也解释为什么 R54 之后该守卫仍会在冷缓存机器上给 rc=2。

## 2. 实测读数（2026-10-22，master 8e6e5444）

| 步骤 | 命令 | 读数 |
|---|---|---|
| 复现 | `moon check --target js`（无 override） | rc=1，`Sys_error("\\\\?: Invalid argument")`，Compiler args 里 `-o "\\?\F:\..."` |
| 对照 | `MOONC_OVERRIDE=~/.moon-shim/shim.exe moon check --target js` | rc=0，`Finished. moon: ran 46 tasks, now up to date (506 warnings, 0 errors)` |
| 修复前 | `python scripts/moon_test_env.py` | rc=2，无汇总行（ICE 中断编译） |
| 修复后 | `python scripts/moon_test_env.py` | rc=0，`Total tests: 1387, passed: 1387, failed: 0` |
| 自证 | `python scripts/moon_test_env.py --selftest` | rc=0，12 格：垫片目录 2 + PATH 清理 3 + node 解析 2 + moonc 覆盖 4 |
| dry-run | `python scripts/moon_test_env.py --dry-run` | 打印 `moonc override：~/.moon-shim/shim.exe（自动发现…）`，不执行 |

## 3. 改动清单

- `scripts/moon_test_env.py`：新增 `DEFAULT_MOONC_SHIM` 与纯函数 `pick_moonc_override`（env 优先 / Windows 自动发现 / 缺失与非 Windows 不设）；main 里设置 `MOONC_OVERRIDE` 并在输出含 `Sys_error…Invalid argument` 时点名 ICE 给 rc=2；`--selftest` 8→12 格；docstring 增「第二道坑（R124）」。
- `scripts/README.md`：`moon_test_env.py` 条目补第二道坑与 12 格读数。
- `AGENTS.md`：环境要求段的常驻入口补 moonc override 一句。
- `memory/bugs.md`：BUG-380 抬头 OPEN→FIXED，并落一条点名 BUG-380 的 `### FIXED(2026-10-22T11:51:00Z / BUG-380)` 小记（evidence 非空）。
- `reports/2026-10-22-moon-test-env-moonc-shim-r124-report.md`、`memory/2026-10-22.md`：本单沉淀。
- `plugins/`（生成投影，禁手改）：BUG-380 改判使账本计数 `16 待修/339 已修` → `15 待修/340 已修`，`python scripts/gen_plugins.py` 重投影 8 份宿主文档 + `plugins/README.md`；`gen_plugins.py --check` 与 `check_plugin_sync.py` 复绿。

## 4. 资源消耗

- 会话轮次：本单为副机自驱 R124 轮；主要耗时在两次全量冷编译（`moon check` 与 `moon test`）。
- 外部资源：零网络、零依赖安装；`MOONC_OVERRIDE` shim 为本机既有件（`~/.moon-shim/shim.exe`），未入仓。
- 测试读数：1387/1387 全绿。

## 5. 任务分配记录

- 本单无主机下发 TASK 对应（TASK-013~015 已在 R123 对账为 in_review；TASK-016 属 atomcode），为副机自驱发现。
- 单 agent 直做，无子代理派发；终审由本会话执行（selftest + 全量测试 + 守卫电池）。

## 6. 遗留风险

- moonc 的 `\\?\` ICE 是工具链缺陷，本单只提供本机常驻绕法，**未修上游**；其他 Windows 机器没有 shim 时仍会得到 rc=2（点名成因，不假绿）。
- `MOONC_OVERRIDE` 依赖本机 `~/.moon-shim/shim.exe`（宿主既有绕法），不在仓库内、不受版本控制；换机/重装需重建。
- 同族 fmt 面 `moon fmt --check` 仍不可判（BUG-388，`check_fmt_gate.py` 三档已落地）。

## 7. 后续建议

1. 用「空包 + 一条 test」最小工程向 moon 上游报 `\\?\` ICE（与 BUG-388 一并）。
2. 若上游修复（`moon check` 无 override 可过），删除/降级自动发现，避免继续背机器级依赖。
3. CI 保持 Linux 为格式与测试的权威面；本地守卫的 rc=2 语义继续保留（不可判 ≠ 绿）。

## 8. 超额内容

- 顺手结掉账本 BUG-380（OPEN→FIXED）：该条与 R123 的「账本落后于事实」同形——修复已落地而抬头仍 OPEN，会让下一轮 triage 重复派单。

## 9. 来源

- 代码：`scripts/moon_test_env.py`（`pick_moonc_override` / main / selftest）、`scripts/README.md` 同名条目、`AGENTS.md` 环境要求段。
- 账本：`memory/bugs.md` BUG-380（含 R54 追记与本单 FIXED 小记）、BUG-388。
- 观测：`_scratch/train*.py` 等宿主脚本展示 `MOONC_OVERRIDE=~/.moon-shim/shim.exe` 用法；`~/.moon-shim/shim.cs` 显示 shim 剥离 `\\?\` 前缀并重新引用 argv。
- 命令：见 §2 表格。
