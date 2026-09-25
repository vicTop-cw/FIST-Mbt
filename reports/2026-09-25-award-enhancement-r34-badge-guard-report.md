# 获奖提升 · R34 README 测试徽章一致性守卫（CI 门禁）

> 日期：2026-09-25｜目标：把获奖概率再往上提——先调研、再环视薄弱点，项目整洁 + 好的 AI 项目管理工具（"文档计数一致性"可复现）。
> 本轮续接 R33：**83 MCP 工具 + 3 resources + 2 prompts，测试 230/230（Windows + WSL 双端全绿）**。

## 一、调研先行（审计缺口）
- README 徽章 `tests-N%2FN` 是手写静态数字，此前后端每轮都需手工同步（且多次易漏）；该"徽章不过时可复现"缺口与"文档即实现"直接冲突。
- 方案：把"测试计数 = 徽章计数"变成 CI 硬门禁（而非继续人工盯）。

## 二、本轮落地
- **新增 `scripts/check_badge.py`**：读 `moon test` 日志解析 Total/Passed/Failed，解析 README 徽章，不一致或 failed>0 → 退出码 1。
- **接入 `.github/workflows/ci.yml`** JS 轨道：`Test (js)` 改 `set -o pipefail; moon test --target js 2>&1 | tee /tmp/moon_test.log`，后加 `Badge consistency guard` 步骤；pipefail 保住测试失败信号，徽章同步交给 CI 校验。

## 三、结果摘要
| 项 | 值 |
|---|---|
| MCP 工具 | **83**（不变） |
| 测试 | **`moon test --target js` 230/230**（不变） |
| CI | 新增 JS 轨"Badge consistency guard"步骤（徽章 ≠ 实测即 FAIL） |
| 验证 | 正路径 PASS（230/230==230/230）；负路径 `tests-231%2F231` → **BADGE-STALE 退出码 1** |
| 回归 | 0（纯 CI 门禁 + 脚本，无运行语义改动） |
| 文档 | 仅 scripts/README 补 `check_badge.py`（无计数涟漪） |

## 四、资源消耗
- 工具链：`moon test --target js -j 1`（生成日志）+ `check_badge.py`（正/负各一次）；无新增依赖。

## 五、任务分配记录
- R34 主代理直做（写守卫脚本 + 改 ci.yml + 正/负验证），自审两关（正路径 PASS / 负路径 BADGE-STALE）。

## 六、遗留风险
- 徽章是"一致性守卫"而非真正动态读取（需要服务托管 JSON 才能真正"实时刷"）；对 CI 徽章规格，守卫已把"手改漏同步"变硬门禁，足够且零额外依赖。真正实时动态徽章（shields endpoint + 发布 JSON）列为远期。
- `tee` 的 pipefail 只在 bash（ubuntu/windows Git Bash/PowerShell 分支需保证）——CI JS 轨道在 ubuntu，已验证；Windows 轨不做徽章守卫（其 `moon test` 直接跑，保留失败信号）。

## 七、后续建议（按强度）
1. `watchdog_tick` 无人值守"无活跃任务"分支接 `selfdrive_dispatch`（免 want）：能力派单并入自动续推，构成完整自驱闭环；
2. plan_deep 深化 LADDER"先生成简单变体再逆推原题"；
3. （远期）徽章真正动态化（shields endpoint + CI 发布 JSON）。

## 八、超额内容（相对任务边界）
- 无。

## 九、来源
- 源码：scripts/check_badge.py、.github/workflows/ci.yml。
- 旁证：本地 `moon test -j 1` 日志 + 正/负路径运行结果。

*（内容由AI生成，仅供参考）*