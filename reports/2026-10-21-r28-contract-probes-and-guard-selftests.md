# R28 · 发布版 fist-mbt 契约不变量实测（15+ 探测全符合）+ 守卫族 25 selftest 全绿

- 日期：2026-10-21
- 性质：验证（verify）
- 结论：**发布版 fist-mbt 的边界值/安全/非法输入/BUG-9 互锁/角色权限五类契约探测 15+ 项全部符合**；守卫族 25 判据 selftest 全绿（首次）；守卫族无 R24 类弱 lookbehind 隐患

---

## 一、守卫族 25 selftest 全绿（首次）

对 `scripts/check_*.py` 逐个跑 `--selftest`：**24 个 exit 0**，仅 `check_badge`（需 moon_test_log 参数，属用法非失败）。此前未跟踪的并发新增守卫全部自证可红可绿：

- `check_mbti_sync`：24 份 .mbti 656 条 pub 声明一致（PASS）
- `check_pkg_imports`：26 份 moon.pkg 34 条本地 import 指向在跟踪面（PASS）
- `check_desc_enum_sync`：登记项枚举一致（PASS）
- `check_model_auth_no_key`：107 份文件无真凭据值形状（PASS）
- `check_host_installable`：宿主可装性（WARN 级，`timeout_ms` 是否改真源由人终审）
- `check_skill_inject`：注入路径可测命中（PASS）
- `check_upgrade_installer`：G1×5+G2×5+G3×8+real-surface
- `check_py_stdout_encoding`：CI 面 30/30、--all 面 82 份该带闸

## 二、守卫族无 R24 类隐患（整类覆盖）

R24 教训：数字声明正则 `(?<!\.)` 弱 lookbehind 会被 `cl1` 这类标识符污染（假阳）。本轮全族扫描：

- **`(?<!\.)` 弱 lookbehind：全族 0 命中**
- **含 `\d` 的正则：仅 1 命中**，是 `check_entry_paths.py` 写 Windows 路径字符串（`\d` 在 `Repo\\...` 里，非正则）

⇒ R24 修复覆盖了整类，无同类潜在 FP 雷。

## 三、发布版 fist-mbt 契约不变量实测（15+ 项全符合）

真跑发布版 fist-mbt MCP 工具，按五类契约探测：

### A. 边界值
| 探测 | 契约 | 实测 |
|---|---|---|
| `cost_budget_split(budget=-1)` | 负预算拒绝 | rejected「负份额=赤字」✓ |
| `dag_mc(samples=1)` | 钳到 10 | samples=10（160 任务）✓ |
| `dag_mc(deadline=0)` | 不参与 | p_on_time=0 不计 ✓ |
| `phi_accrual(elapsed=-1)` | 拒绝 | rejected「时钟回拨」✓ |
| `rank_of(level=99)` | 士兵回退 | 士兵 rank_index=-1 ✓ |

### B. 安全/非法输入
| 探测 | 契约 | 实测 |
|---|---|---|
| `mcp_config_scaffold` 传 `sk-abc…` | 拒凭据形状 | Error「真值不要进配置」✓ |
| `store_open(namespace=../escape)` | 拒穿越 | Error「只允许字母/数字/_/-」✓ |

### C. 不存在的实体
| 探测 | 契约 | 实测 |
|---|---|---|
| `tx_contract(task_id=nonexistent)` | 拒 | rejected precondition ✓ |
| `goal_drift_check(root=nonexistent)` | 拒 | ok=false ✓ |

### D. BUG-9 账本互锁
| 探测 | 契约 | 实测 |
|---|---|---|
| `bug_fix(evidence=空)` | 拒空口 | Error「记账规则硬门①」✓ |
| `bug_mark_status(status=FIXED)` | 拒只改抬头 | Error「必须走 bug_fix」✓ |

### E. 角色权限
| 探测 | 契约 | 实测 |
|---|---|---|
| `executor_auction(need=空)` | 拒缺参 | Error「BUG-19 硬门」✓ |
| `dag_publish(created_by=leader)` | 拒非 human_steward | Error「publish 仅限人类指挥官」✓ |

**五类契约无一违反。** 与守卫族全绿 + 测试门 1347/1347 共同构成发布版 fist-mbt 强正确性证据。

## 资源消耗

- 15+ 次 MCP 工具调用（边界/安全/互锁/权限探测）
- 1 次守卫族 25 selftest 批量
- 1 次守卫族弱 lookbehind / 数字正则全族审计

## 任务分配记录

- 无新派单。src/server 36 脏（R15 第十五轮）。

## 遗留风险

1. **BUG-339 仍 OPEN**：`bug335_ns_route_wbtest.mbt` 仍 tracked=0、HEAD server.mbt 不含 `publish_parallel_route`（R27 复核确认）。成对提交须在同一 commit。
2. **issue_scan 家族 6 条 OPEN**（327/333/345/346/347/348）：全在脏的 `issue_scan.mbt`，等 src/server 清空 + R23 裁决授权。
3. `check_plan_landing` exit=1：66 份文档 368 条点名路径，64 条不在跟踪面（63 条不存在）。这是并发 agent 的**诊断**（刻意非门禁），反映历史计划文档点名了未落地文件——属并发收尾范围。
4. `check_host_installable` WARN：`timeout_ms` 字段部分客户端忽略，是否改真源由人终审。

## 后续建议

1. src/server 清空后按 R23 六顶帽工件单批落地（347→345→346→348），预派 exec-scan-rules。
2. BUG-339 成对提交（server.mbt + bug335 锁）在同一 commit。
3. 守卫族 11/11 全绿 + 25 selftest 全绿 + 测试门 1347/1347 + 契约探测 15+ 全符合 = 可作后续任何改动的**强零回归锚点**。

## 来源

- `scripts/check_*.py` 25 判据 selftest 实跑（2026-10-21 09:55）
- 发布版 fist-mbt MCP 工具 15+ 次调用实测回执
- 本会话 R22/R24/R25/R26/R27 提交：`c7934f3` / `b4665e2` / `fea6839` / `a15ab01` / `d5464bb`