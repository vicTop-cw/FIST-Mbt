# 唤醒轮 123 报告 · BUG-572 闭环（判据变异对照缺口：空提交分支）

> 日期：2026-11-04（周三）
> 触发：标准唤醒动作（树净巡检 → Round C 队列 → E2 审计复核）
> 结论：**BUG-572 已修并 FIXED 盖章**；E2 的另一条指控经探针复核为误报（`check_memory_log_size.py` S4=CAUGHT），已如实记入条目。

## 1. 结果摘要

| 项 | 读数 | 判定 |
|---|---|---|
| 树净（起始） | 工作树干净（仅未跟踪 `.workbuddy/`） | 无 WIP 待收口 |
| HEAD（起始） | `7d6fe0c43`（BUG-571 修复） | — |
| E2 审计返回 | 2 个疑似变异对照缺口 | 1 真 1 误报 |
| `audit_branch_delete.py --selftest` | **SELFTEST OK（8 格）** | 绿 |
| 变异探针（`--func audit`） | 修复前 S1=**MISSED** / 修复后 S1=**CAUGHT** | 锁已生效 |
| 变异探针（`check_memory_log_size --func judge`） | S4=**CAUGHT**（rc=1，`callface-run-rc-0`） | E2 误报坐实 |
| 格数反解守卫 | `check_selftest_inventory_doc.py` 通过 | 绿 |
| 电池登记守卫 | `check_battery_count_doc.py` PASS（rulers=153 ci=48 battery=113 missing=0） | 绿 |
| 账本形态 | 行首三段式抬头 **557 条**，干净 | 绿 |
| 插件同步 | cl7 PASS（4 宿主 / 64 文件 / 182 工具 / v0.3.11） | 绿 |
| 投影头 | `BUG-1~572 共 557 条入账：5 待修 / 511 已修 / 13 重复并入 / 28 误报` | 一致（5+511+13+28=557） |

## 2. 本轮闭环缺陷：BUG-572（medium / FIXED）

### 2.1 现象与机制

`scripts/audit_branch_delete.py` 是**通道分支删除的硬门 + 审计（R50）**：删 `slave/*` 分支前必须能证明它已合并到远端基线，判据为

```
if contained or (cherry_plus == 0 and not diff_files)  ⇒ delete
```

`--selftest` 原有 7 格（已合可删 / 未合拒删 / 缺失不可判 / 审计两行与字段齐备），其中「未合」格构造的是 `cherry_plus >= 1` **且** `diff` 非空 ⇒ **只覆盖了 `cherry_plus == 0` 的否定侧**。

「空提交分支」（`cherry_plus == 1` 且 `diff` 为空，即分支上有提交但内容与 base 等价）这一形态**无任何格覆盖**，而它恰是 `cherry_plus == 0` 子句的**唯一区分格**。

### 2.2 定性：变异对照缺口（MISSED）

用仓内权威探针 `scripts/_mutation_probe.py` 复核（三重判定 `CRASHED`/`MISSED`/`CAUGHT`）：

- 修复前：S1（`cherry_plus == 0` → `!= 0`）= **MISSED** ⇒ 改坏机制后 selftest 照样绿，判据声称的「无新提交且无 diff」口径实际没被锁住。
- 修复后：同一探针 = **CAUGHT** ⇒ 缺口已锁。

### 2.3 修复

`selftest()` 新增 `empty-commit-keep` 格：构造空提交分支（`git commit --allow-empty`），断言 `verdict == "keep"`。该格是唯一能区分「内容等价」与「历史等价」的形态——若 `cherry_plus == 0` 被误写成 `!= 0`，空提交分支会被误判为可删，此格当场红。

同批同步 `scripts/README.md` 的格数自述 7 → 8（否则格数反解守卫 `check_selftest_inventory_doc` 会红）。

### 2.4 回归锁（判例-29/30 双重要求）

1. **机制格**（判例-29）：新增 `empty-commit-keep` 格直接断言 `audit()` 的实现行为，不是测「带某机制的 git 调用」。
2. **变异对照**（判例-30）：`_mutation_probe.py --func audit` 的 S1 由 **MISSED → CAUGHT**，且变异点落在代码（`== 0` 子句）而非注释。
3. **反向对照**：selftest 8 格全绿，已合可删 / 未合拒删 / 缺失不可判三格行为不变（零回归）。

### 2.5 诚实边界

- 本条只覆盖 `audit_branch_delete.py` 一个缺口。
- E2 对 `check_memory_log_size.py` 的指控**经探针复核为误报**（S4=`CAUGHT`，`callface-run-rc-0`：`got=1 want=0`），该脚本的变异对照**隐式存在**，已在 BUG-572 条目 `detail` 写明，不另立账。
- 探针 `MISSED ≠ 假绿定论`（判例-62）：只说明四类语义变异没让它变红；本轮的结论建立在「S1 变异点确实落在被测子句上」这一具体证据上。

## 3. E2 审计的定性修正（方法面收获）

E2 子代理审计 `selftest` 变异对照覆盖面时返回 2 个疑似缺口，**其中 1 条被权威探针推翻**。这坐实了一条方法面规则：

> **子代理的「缺口」结论必须用仓内权威探针复核后才可入账**——手工插桩（改坏代码后跑 selftest）极易落入 `_mutation_probe.py` 明确警告的 `CRASHED` 被误读成 `CAUGHT` 陷阱。

本轮未采用手工 lambda 改返回契约的做法（该做法会触发探针的 `CRASHED` 判定），而是直接复用已进电池的 `_mutation_probe.py`。

## 4. Round C 队列复核（连续第 11 轮）

| 项 | 状态 | 说明 |
|---|---|---|
| BUG-527 | **OPEN（owner 门控）** | 唯一主行动 = 出路②（上游 issue），属对外/不可逆操作，只出方案不动手 |
| BUG-530 | FIXED | `3699f012a` |
| `check_usage_tool_count` | 已注册 | `run_guards.py:175` |

## 5. 资源消耗

| 项 | 读数 |
|---|---|
| 子代理 | 2 个（E1 建议归属审计 / E2 变异对照审计） |
| 关键验证命令 | 6 条（selftest ×2 / 变异探针 ×2 / 计数守卫 ×2） |
| 落盘文件 | 3 个跟踪面（`audit_branch_delete.py` / `README.md` / `bugs.md`）+ 10 个插件投影文件 |
| 提交 | 待本轮末 `commit_scoped.sh`（带 `--` 明确路径） |

## 6. 遗留风险与后续建议

1. **BUG-527**：仍 owner 门控；出路②（上游 issue）文本已备，等 owner 一句话。
2. **本地领先远端 19 提交**（`origin/main..HEAD`）：`origin/master` 与 `gitcode/main` 均未含本轮及前数轮修复，属交付断层。owner 决策面，本轮不擅自推送。
3. **E1 的 4 条无归属建议**：本轮已取五份报告的建议节，尚未逐条落账或驳回，留待下一轮处理（非阻塞）。
4. **幻影任务** `explore-r3 T0.2.1/T0.2.2/T0.3.2` 仍「待领取」——建议下轮收口或标注为废弃。

## 7. 超额内容

- 无。本轮范围严格限定在「E2 缺口复核 → 修复 → 记账」三件事，未做计划外的重构或扩面。

## 8. 来源

- 缺陷定位：E2 子代理审计（返回 2 个疑似缺口）
- 定性复核：`python scripts/_mutation_probe.py scripts/audit_branch_delete.py --func audit`（修复前后各一次）、`python scripts/_mutation_probe.py scripts/check_memory_log_size.py --func judge`
- 修复验证：`python scripts/audit_branch_delete.py --selftest`、`python scripts/check_selftest_inventory_doc.py`、`python scripts/check_battery_count_doc.py`、`python scripts/check_bug_ledger_shape.py`、`python scripts/check_plugin_sync.py`
- 记账：`fist.py call bug_fix --bug_ids '["BUG-572"]'`（`heading_changed=1`、`note_written=true`）
- 账本：`memory/bugs.md` BUG-572 条目（`### FIXED(2026-11-04T00:53:50Z / BUG-572)`）
