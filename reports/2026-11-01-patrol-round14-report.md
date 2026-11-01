# 巡检报告（Round C 挂起轮）· 2026-11-01

## 结果摘要
- **Round C 队列未解锁**：`git status` 显示 src/**（含大量 moon.pkg）与 `scripts/run_guards.py`（mtime 09:18）仍被他人 BUG-527 R2 车道占用。按标准动作 3 转非阻塞巡检，**未触碰任何 WIP 文件**。
- 新提交：`8da9f920b`（BUG-535 翻 FIXED + 插件态同步）、`95aa8ed62`（check_usage_tool_count 补 UTF-8 重配）。

## 巡检读数
| 探针 | 结果 |
|---|---|
| `check_instruction_budget.py` | PASS（63236 / 65536 字节，全部章节可见） |
| `check_host_installable.py` | PASS（timeout_ms 三处 WARN 为信息级已知项， moon.mod 0.3.11） |
| `mcp_smoke.py` | **FAIL：入口产物缺失**（见下） |
| `fist.py` 网关记账 | **FAIL：同因** |

## 新发现（未立账，判定瞬态 + 一条提示）
1. `_build/js/release/build/cmd/cli/` 下 cli.js 已被并发构建清空（目录仅剩 db 残留与 moonbit.d.ts）⇒ mcp_smoke 与 fist.py 网关同时失灵。判定为 WIP 车道重建中的瞬态，**不去抢 _build**（并发构建各写各的历史事故）。产物恢复后需补跑 smoke + 补 FIST 记账。
2. **提示（判例-33 同族新一面）**：`dist/fist-mbt.js` 明明存在，但 `fist.py` 网关只认 `_build` 面的 find_main 候选 ⇒ **「dist 在」救不了「_build 被并发清掉」**。两条入口（smoke / fist.py）候选面不一致，值得在 Round C 解锁后评估是否给网关补 dist fallback（暂不动 src/**）。

## 遗留与风险
- BUG-527 → BUG-530 → run_guards 注册 case 的 Round C 队列原样顺延。
- 本轮 FIST 在线记账未完成（网关不可用），以本报告为记账面。

## 后续建议
1. 下一轮唤醒先 `git status` 确认 WIP 收口；收口后按队列执行。
2. `cli.js` 产物恢复后补跑 `mcp_smoke.py` 与本轮欠的 FIST 记账。
3. `fist.py` 的 dist fallback 属 scripts/ 改动（run_guards 所在面），归入 Round C 批同批做，避免单独动禁区。

## 来源
- 自主巡检（fist-commander 模式），证据均为本机命令实测输出。
