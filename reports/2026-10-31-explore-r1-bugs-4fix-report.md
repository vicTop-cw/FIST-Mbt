# 2026-10-31 · explore 模式迭代 Round A（ns=explore-r1）· 尺子自愈四连

## 结果摘要
四个 OPEN 缺陷经 4 路并发 agent 修复，统帅逐一终审（实跑格子 + 变异对照，不靠自述），4/4 通过：

| BUG | 修复 | 终审证据 |
|---|---|---|
| **BUG-516** 棘轮越线 | `--bless-baseline` 显式前移（只许升不许降，实测 W=8/R=92/G=34 写回） | bless rc=0 → 主检查 rc=0 |
| **BUG-517** SELFTEST_FUNCS 白名单漏判 | 识别面改 `SELFTEST_NAME_MARKS` 反解，新形状自动纳面 | 自检 42/42 rc=0 |
| **BUG-529** ST 自检格排真检查后 | ST1/2/3 前移至 A1 之前 fail-fast + ST1 增自清理 | --selftest 9 格 rc=0 + 全量 6 格 5P/1S rc=0 |
| **BUG-525** USAGE 计数无尺 | 新建 `check_usage_tool_count.py`（真源=_tool_registry）+ USAGE 三处对齐 182 | 真检 PASS / 自检 4 格 / 未知旗标 rc=2 |

## 任务分配记录
- fix-516-517：`scripts/check_selftest_hermetic.py`（返工 1 轮：F1 对全局基线意外耦合 → 显式零基线，根因归因准确，采纳）
- fix-523：`scripts/blackbox/e2e_acceptance_recheck.py`（派单时我误标单号 523，实为 529——diag-native 纠偏，已按 529 入账）
- fix-525：新建守卫 + USAGE.md
- diag-native：native 三连只读诊断，产出根因链与修复顺序（527 治本 → 513 收尾 → 523 拆单 → 529 前移）

## 关键发现（diag-native，未落地待后续轮）
- **BUG-527 根因**：13 份库包 `moon.pkg` 带 `cc-link-flags`，moon 0.1.20261021 把库包当可执行链接 → 全项目 native build/test 必崩。治本=摘 link 集中到 3 份可执行包（**碰 src/**，等并发 WIP 收口**）。
- **BUG-513 windows 臂**红在 Install MoonBit 403（BUG-112 同形），未走到 build；linux 臂已 scoped 绕行走通。
- **BUG-523**（CI 恒红）与 527 同根因：BUG-133 的 FIXED 口径从未覆盖「干净树全量 native」格，需拆单对账。

## 遗留风险 / 后续建议
1. `run_guards.py` 注册 `case("check_usage_tool_count.py")`——**该文件在并发禁区**（另一 agent WIP），收口后同批提交，否则 `check_battery_count_doc` 会 FATAL（新脚本无执行面）。
2. `memory/bugs.md` 叙述面追加（516/517/525/529 四单 FIXED + diag 诊断追记 + 529/527 交叉引用）——同在禁区，随收口同批。
3. scoped 提交面（本轮可提交文件）：`scripts/check_selftest_hermetic.py`、`scripts/blackbox/e2e_acceptance_recheck.py`、`scripts/check_usage_tool_count.py`、`USAGE.md`、`scripts/README.md`——**必须等 run_guards.py 案子同批**，本轮全部挂起。
4. native 三连修复排 Round B（src/** 解禁后）。

## 超额内容 / 来源
- 成员报告五段制全部齐全；终审抓到 2 个真缺陷（F1 耦合、编号错标）并归因修正。
- 全程 FIST 闭环：ns `explore-r1`，T0 拆 4 单元，T0.1.1/T0.2.1/T0.3.1/T0.4.1 四叶已完成。
