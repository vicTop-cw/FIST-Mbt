# 巡检轮15（非阻塞）· 2026-11-01

## 背景
- `git status --short`：src/** 约 60 文件 WIP 仍被占用（BUG-527 治本车道进行中），HEAD `e464c98e3` 无新收口 → 按标准动作 3 走非阻塞巡检。
- 本轮换面，避开轮 5–14 已扫面（budget/arg-face/fmt/tools-sync/known-red/host-installable/smoke）。

## 本轮探活结果
| 守卫 | 结果 |
|---|---|
| `check_demo_isolation.py` | PASS：34 个 spawn `serve` 脚本全部交付 `FIST_DB_PATH`（显式子句 2 + 豁免 1 锚点成立） |
| `check_store_tables_wired.py` | PASS：32 张表 = 31 有写入点 + 1 显式预留（runs） |
| `check_ps_encoding.py` | PASS：10 份 .ps1 全带 BOM 或纯 ASCII |
| `check_publish_payload.py` | **红**：8 份未跟踪 `reports/2026-11-01-*.md` 会进 `moon publish` 载荷面（P1） |

## 发现与处置
- **新发现（P1）**：历轮巡逻报告只写盘未入库，`moon publish` 的打包面是「工作树 − .gitignore」，
  未跟踪又未忽略的报告会被公开点名。**处置**：本轮同批 scoped 提交 8 份存量报告 + 本轮报告（共 9 份）入库。
- 观察项：`.opencode/` 目录未跟踪（判据未点名，疑其扫描面限定文本载荷形状）；后续轮确认是否应入 .gitignore。
- 其余三面零缺陷，账本无变化。

## 结论
一处 P1 已当场修（报告入库），三面全绿。WIP 收口后按 Round C 队列执行（BUG-527 收尾 → BUG-530 → run_guards 注册 case）。

## 来源
- 指令来源：AGENTS.md FIST 指挥官模式 + 用户唤醒标准动作 3
- 命令面：git status / git log / check_demo_isolation / check_store_tables_wired / check_ps_encoding / check_publish_payload
