# 轮 189 汇报 · BUG-591 ⑤ 落地：拒收六项探针的内存级自检进电池（车道 N 额度耗尽后的统帅实跑终审）

日期：2026-11-12 · 统帅：lead · 模式：explore 选模 → verify 施工 + 终审

## 1. 结果摘要

BUG-591 ⑤「`README.md:145` 承诺六件事都由一支活体探针复验，而那支探针只在 `REGISTRY` 留一行理由、
CI 现读 0 处接线 ⇒ 承诺面零自动化」**已落地为真电池格**：

- `scripts/blackbox/e2e_acceptance_recheck.py` 的 `--selftest` 裸跑改成**内存级**：零 spawn server、
  零 sqlite、零 js 产物读取。新增三格 ST5（A1 判据三类合成违例必红）/ ST6（干净输入不误红）/
  ST7（六格承诺清单完整性：承诺表缩水或某格 record 被搬走 ⇒ rc=2 拒绝出数）。
- A1 判据抽成纯函数 `judge_a1(grew, mism, ns_total)`，**活体那一格与 ST5/ST6 共用同一份实现**
  （不是各写一遍 ⇒ 自检绿不等于活体绿的风险被结构消掉）。
- `run_guards.py`：该脚本从 `REGISTRY`（在册但不跑）移进 `SPECIAL_CASES` 一格 `case(..., "--selftest")`，
  并在原处留「不要抄回本表」的墓碑注释。
- 六格**活体**复验改由 `--selftest --live` 手动跑；`--json` 与点名 `FIST_ACCEPT_JS` 都隐含 `--live`
  （命令语义不因改造而漂）。`KNOWN_FLAGS` 白名单外一律 rc=2 点名已知旗标。
- 同批登记面：`scripts/README.md` 的 `BATTERY-REGISTRATION` `battery` **115→116**（其余键不动），
  该脚本条目改写为「内存级 / 活体」两档口径。

**终审实跑读数（不采信车道自述）**：
- 内存级 `--selftest`：**6 格 = 6 PASS / 0 FAIL, rc=0**（格数从 CELLS 反解，不手写）。
- 变异 A：把 `judge_a1` 的主库增量检测改成 `bad = []` ⇒ **ST5 FAIL, rc=3**（尺子坏了档）。
- 变异 B：把 `promised_gate` 的缺格清单改成 `missing = []` ⇒ **ST7 FAIL, rc=2**（拒绝出数档）。
- 两次变异跑后**逐字节还原**（脚本自校 `restored=True`）。
- 未知旗标 `--live-typo` ⇒ **rc=2**，原文点名 `--selftest / --json / --help / -h / --live`。
- `check_battery_count_doc`：改锚点前 **rc=1**（X3 登记落后 115/116）→ 改后 **rc=0**（逐键一致）。
- `check_scripts_index` rc=0；`gen_plugins` rc=0；`check_plugin_sync`（cl7）rc=0；
  `check_bug_ledger_shape` / `check_bug_ledger_scope` rc=0。

## 2. 资源消耗

- 车道 N（子代理）：**失败** —— `You've reached your credit usage limit`（12,239,690 subagent tokens /
  65 tool uses / 413.6s）。它已把代码写盘，但**没有回传报告**。
- 统帅终审：`e2e_acceptance_recheck.py --selftest` ×4（base + 2 变异 + 还原后）、`--live-typo` ×1、
  `check_battery_count_doc` ×2、`run_guards.py --list`、`gen_plugins.py` ×2、`check_plugin_sync` ×2、
  一次性变异脚本 `temp/g189_mut.py`。
- 未跑：六格**活体**面（需 js 产物 + node，数分钟）——本轮只终审内存级面，活体面口径未变。

## 3. 任务分配记录

| 轮 | 车道 | 任务包 | 结局 |
|---|---|---|---|
| 187 | N | BUG-591 ⑤：给 `e2e_acceptance_recheck.py` 补无前置 `--selftest` 并接进 `run_guards.py`；边界=只动这两个脚本；回传=结论/证据/分析/缺口/入档位置；验收=自检真跑 + 变异对照 | **额度耗尽失败**，代码已落盘、无回传 |
| 189 | 统帅 | 按金条八实跑终审 + 补登记面（README 锚点/条目）+ 账本追记 + 汇报 | 本轮 |

过程纪律：**未达标两项** —— ① 车道 N 无回传（五件格式缺全部），按「缺一打回」本应打回重做，
但额度已尽 ⇒ 改为统帅实跑取证替代自述，如实记为流程债；② 登记面（README 锚点 + 条目）由统帅补，
属车道边界外的同批登记，事后不可补派。

## 4. 遗留风险

- BUG-591 ②③：`check_usage_tool_count` 是否接进 CI 属 **owner 裁决**，本轮未代翻（`ci=49` 不动）。
- BUG-591 ④：镜像「只增不删」无尺，需真远端，未做。
- 活体六格仍不在自动电池（刻意分档：电池跑内存级，活体面手动/黑盒）⇒ 「六格全绿」这一承诺
  在 CI 上仍无自动证据，只有内存级判据 + 承诺完整性闸。
- 车道额度耗尽 ⇒ 后续并发派单能力受限；本轮之后未再派新车道。
- 本地 main 领先远端多笔未推，CI 面未验证本轮改动（push 属 owner）。

## 5. 后续建议

1. owner 裁决 ②③：要么把 `check_usage_tool_count` 接进 ci.yml（`ci` 键同批 +1），
   要么在文档里把「CI 面」措辞永久改成「电池面」——两条路都不许留「自称有守卫」。
2. 活体面建议挂一条**夜间/手动**观测臂（与 `e2e_*_xproc` 同族），把六格活体证据也变成可回溯读数。
3. 额度恢复后重派 ④（镜像只增不删判据），任务包沿用本轮格式。

## 6. 超额内容

- 变异对照**两支分别打在两个不同机制上**（A1 判据 / 承诺完整性闸），而不是只测「正常路径通过」；
  两支各自落在不同退出码档（rc=3 / rc=2），证明分档语义真的可达。
- 未知旗标负复现（`--live-typo`）——R207 同族「自检开关拼错 = 静默失去自检」的防线现跑确认。
- 在 `run_guards.py` 原 REGISTRY 位置留墓碑注释，防后人把同一脚本抄回「在册但不跑」面。

## 7. 来源

- `scripts/blackbox/e2e_acceptance_recheck.py`（`judge_a1` / `promised_gate` / `PROMISED_CELLS` /
  `ST_PRELIVE` / `ST_LIVE_ONLY` / `KNOWN_FLAGS` / `LIVE` / `cleanup_hermetic`，现读）
- `scripts/run_guards.py`（`SPECIAL_CASES` 新格 + `REGISTRY` 墓碑注释）
- `scripts/README.md`（`BATTERY-REGISTRATION` 锚点 + 该脚本条目）
- `memory/bugs.md` BUG-591 `### 追记（2026-11-12 / 轮 189 …）`
- 快照：`temp/g189_accept_selftest.txt`、`temp/g189_mut_summary.txt`、`temp/g189_mut_base.txt`、
  `temp/g189_mut_A_drop_main_db_growth_check.txt`、`temp/g189_mut_B_promise_gate_blind.txt`、
  `temp/g189_battery.txt`（改前 rc=1）/ `temp/g189_battery2.txt`（改后 rc=0）、
  `temp/g189_genplugins2.txt`、`temp/g189_cl7b.txt`、`temp/g189_ledger.txt`、`temp/g189_scope.txt`
- 车道 N 失败回执：task `ad2c777a4fd03ca7a`（credit usage limit）
