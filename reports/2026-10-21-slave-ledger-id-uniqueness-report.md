# R47 · 账本编号唯一门（门④）+ 串号条目重编号 —— 汇报

## 结果摘要

- **修的是上一轮自己撞出来的那条**：BUG-370（`gen_plugins.py` 的账本摘要一句里用了两个分母）三条出路里的两条已落地——
  ① 判据侧：`ledger_status()` 新增**门④「抬头编号必须唯一」**，位置在四态计数 `st = {id: …}` **之前**；
  ② 台账侧：串号的 BUG-183 / BUG-192 各拆出一条，先出现者保留原号，后出现者迁为 **BUG-371**（`star_gate` Int64 溢出）/
  **BUG-372**（`ops_cleanup` 丢弃错误详情）；③ 写侧（`report_bug` 的 ID 取「现有最大值 + 1」）**未做**，动 `.mbti` 接口面 ⇒ 按金条四留指挥官。
- **摘要句现在由结构保证自洽**：`measure()` 里 `total = len(ids)` 改成 `total = sum(counts.values())`，恒等式「总数 == 四态之和」不再依赖"此刻恰好对上"。
- **读数搬家（全现读）**：改前语料 `抬头出现 355 / 唯一 353 / 之和 353`（两分母差 2、旧门全绿）→ 工作树 `356 / 356 / 356`
  （`OPEN 20 + FIXED 317 + DUPLICATE 10 + FALSE_POSITIVE 9 = 356`）。FIXED 314→317 里两条是"一直被吞"的存量、一条是本单真修的 BUG-370。
- **叙述面纪律守住了**：2026-10-15 那两条 `### FIXED` 旧小记逐字不动；迁移由文末新增的
  `### FIXED(2026-10-21 轮次 R47 编号迁移 / BUG-371, BUG-372)` 点名收口（`memory/bugs.md` 文首规则：叙述面只追加、不改写、不删除）。
- **投影同批**：`gen_plugins.py` 重跑，四宿主 9 份生成件与账本同色，`--check` rc=0、`check_plugin_sync.py` PASS（4 宿主 / 64 生成文件）。
- **本单新立 BUG-373**（medium，只立案不修）：代码注释与测试标题里引用的 `BUG-N` 与账本编号之间零闭环，
  实测三类失配各有站点（错号 / 悬空 / 一号三义），另有反向对照证明这并非不可判。

## 资源消耗

- 轮次 R47，单任务 `T0r29`；工具链：Python 3.11 判据 + MoonBit `moon test` / `moon check` 各一次（`-j 1`，js 目标）。
- 真源读数落盘：`temp/pt29_raw.log`（`Total tests: 1302, passed: 1302, failed: 0`）、`temp/chk49.json`（489 warning / 0 error）、
  `temp/chk49.err`（0 字节）、`temp/r47_battery.log`（电池 37 格 / 失败 0 / SKIP 0 / 缺执行面的尺 0）、`temp/r47_ledger_mutation.py`（变异台 17/17 rc=0）。
- 改面规模：`memory/bugs.md` 抬头 4 处（BUG-370 状态位 + BUG-371/372 新抬头 + BUG-373 新单）与 3 段追加叙述；
  `scripts/gen_plugins.py` 两处（门④ + 总数导出）；`scripts/README.md` / `docs/agent-map.md` 文档面；`plugins/**` 9 份生成件。
  零 `.mbt` / `.mbti` 改动（任务包边界写死，且金条八差集证明成立）。

## 任务分配记录

- 指挥官（主机 AtomCode 会话）：定题目、终审、写记忆与本报告、执行提交与推送。
- FIST 根任务 `T0r29`（`temp/t29_publish.py` 先 `get` 现读再 `publish`，避免重复发布）：十一段任务包，边界「只动
  `gen_plugins.py` / `memory/bugs.md` / `plugins/**` / `scripts/README.md` / `docs/` / `memory/` / `reports/`，**不改**任何 `.mbt/.mbti`」；
  `created_by` 刻意不传（服务端默认 `human_steward`，本仓无人值守流水线即此入口）。`claim --assignee slave-guard` → 已领取。
- 副机自验：变异台 17 支、电池 37 格、金条八两次实跑、与基线 `temp/chk48.json` 双向差集。

## 遗留风险

1. **BUG-373 未修**（medium）：注释/测试标题里的 `BUG-N` 引用与账本对不上，重编号这类动作**没有安全网**——本单是靠人工逐条核过才敢迁号；
   下一单若再迁号而没先立判据，就有把「引用面」改脏而无人报的风险。
2. **写侧 ID 分配未改**：`report_bug` 仍可能把新单落到一个已存在的编号上（BUG-370 的成因至今仍在代码里，只是被门④当场拦下）。
   这一拦是「FATAL + 拒生成」，不是「自动分配」，所以写侧修法仍在指挥官手里。
3. **门④只考账本抬头，不考 `### FIXED` 小记里的编号集合**：小记点一个不存在的号，是靠门②（"被点名但状态不是 FIXED"）间接响的；
   若那条不存在的号恰好与某个真条目同号，仍是漏判（与 BUG-373 同族）。
4. **`cleanup_artifacts` 预存红读数继续上涨**（本轮 686 = 86 根 .db + 599 个 temp/ + 1 个 scripts/）：本轮新增 4 份 temp 证据件，按声明期望命中，不是回归。
5. `.mbti` 的 Int↔Int32 拼写抖动（BUG-330）本轮未复现（未跑 `moon info`），但全仓 `moon fmt` 仍未做，随时可被下一次 `moon info` 带回。

## 后续建议

1. 下一单首选 **BUG-373 出路①**：立只读判据 `scripts/check_bug_reference_integrity.py`（扫 `src/**` 注释与 `_test.mbt` 标题里的 `BUG-N`，
   与账本编号集合对表，**只报不判**、必须先出数），核完再分两批改（注释先行，测试标题须与快照刷新同批）。
2. `report_bug` 的 ID 分配改「现有最大值 + 1」需要一次 `moon info`，会把 `.mbti` 接口面带进提交——建议单开一单并**事前**说明 `.mbti` 差异面。
3. 仍挂着的两项：README 条目内联 `N=` 的 10 份新面逐条核（核完才谈开启 `check_exit_code_contract` 的 README 面）、`emit_fatal` 三份尺共用件化。
4. 请 owner：归档 `T0r27`（`python scripts/fist.py call archive --task-id T0r27 --by human_steward`）；R41–R47 各分支的 MR 由 owner 开。

## 超额内容

- 任务包只要求"门④ + 重编号 + 重投影"，本单额外做了：
  ① **BUG-373 的立案与逐站点取证**（为核重编号安全性而普查引用面，撞出引用完整性零校验这一类；只立案不动 `.mbt`，未越界）；
  ② 变异台从 14 支扩到 17 支，新增 `M3b 门后置 ⇒ 永不响`（把"门的位置"从口头纪律变成可考格子）与 `M4b 旧口径配新账本 ⇒ 恰好对上`
  （钉住"为什么当初没发现"）；
  ③ `docs/agent-map.md` §五 两条新律（门必须站在集合收缩之前；编号迁移走追加点名小记）。
- 未做超额：没动 `.mbt/.mbti`，没跑 `moon info`，没碰写侧 `report_bug`（边界内收手）。

## 来源

- 真源读数：`python temp/r47_ledger_mutation.py` → 17/17 通过（rc=0）；`python scripts/gen_plugins.py` → 摘要
  `BUG-1~373 共 356 条入账：20 / 317 / 10 / 9`；`python scripts/gen_plugins.py --check` rc=0；
  `python scripts/check_plugin_sync.py` → PASS 4 宿主 / 64 生成文件；
  `python scripts/check_exit_code_contract.py --selftest` → 28 格 rc=0，全量 → 判定面 0 条 rc=0；
  `python scripts/check_doc_surface.py` / `check_scripts_index.py` / `check_pkg_imports.py` / `check_mbti_sync.py` /
  `check_test_sync.py temp/pt29_raw.log` / `check_publish_payload` / `check_plan_landing.py --gate` → 全绿；
  `python scripts/run_guards.py` → 格数 37 / 失败 0 / SKIP 0 / 缺执行面的尺 0；
  `moon test --target js -j 1` → `temp/pt29_raw.log` `Total tests: 1302, passed: 1302, failed: 0`；
  `moon check --target js --json` → `temp/chk49.json` 489 warning / 0 error、stderr 空，与 `temp/chk48.json` 双向差集为空
  （`python temp/r46_diff_check.py temp/chk48.json temp/chk49.json` rc=0）。
- 上游依据：`memory/bugs.md` BUG-370（含 R46 立案与本条 FIXED 小记）、BUG-371 / BUG-372（编号迁移）、BUG-373（本单新立）；
  `reports/2026-10-21-slave-bug369-fixed-ledger-report.md`（R46，BUG-370 的出处与「门绿着、文案自相矛盾」的原始证据）。

## 回填（提交面 / MR / FIST 终态）

- 待补：主件与收尾件 hash、分支推送回执、MR 入口、`T0r29` 终态。
