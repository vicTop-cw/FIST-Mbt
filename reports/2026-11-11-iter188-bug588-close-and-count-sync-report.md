# 轮 188 汇报 · BUG-588 收口（数据目录注入已有锁）+ 测试计数面同步 2064→2067

日期：2026-11-11（落盘 2026-11-12）· 统帅：lead · 模式：explore 选模 → verify/bugfind 施工

## 1. 结果摘要

两件事，都已实测收口：

1. **BUG-588 由 OPEN 翻 FIXED**。关闭条件是「mcpcf 有可注入的时钟**或**数据目录（任一即可）」：
   - ① 时钟注入在轮 186 已落地（`arg_now_secs`，`mcpcf.circuit` / `mcpcf.watchdog` 两入口同基）。
   - ② 本轮**现读推翻 summary 的「任何 mcpcf 测试必须先 set_engine」**：`tool_ops_init` 本来就收
     `data_dir`（读 `arg_str_opt(args, "data_dir")` → 在该目录下开 `mcpconftest-ops.db`）。
     可测性在工具层早已存在，缺的只是一把锁 ⇒ 新增
     `bug588_02_ops_init_data_dir_redirects_db`（`src/server/mcpcf_embed_bug583_wbtest.mbt`）：
     注入 `data_dir="temp/g188-mcpcf-data"` 后 `db` 回执必须含该目录且仍以 `mcpconftest-ops.db` 结尾；
     缺省调用回执仍指向 mcpconftest 目录。
   - 残余（保留在 FIXED 段内，不另立免测单）：`ensure_engine()` 对未走 `ops_init` 的路径仍 fail-open 到
     `MCPCONFTEST_DATA_DIR`/`LOCALAPPDATA`，库名字面量仍硬编码。这是「默认落点」不是「不可注入」。
2. **测试计数面同步**：全量实测 **2067/2067, rc=0**，而 10 份现状文档仍写 2064（轮 186/187 各加了格）。
   按 `check_test_sync.py --total 2067 --fix-dry-run` 的逐条建议**人工落最后一笔**（该工具刻意无写盘路径，
   判例-63）：23 行 / 41 处数字改为 2067，同批把「2026-11-09 / 2026-11-07 实测」的日期戳改为 2026-11-11。
   改后 `check_test_sync` **PASS**（19 条声明全部等于实测、must-carry 5 份齐全、豁免 27 条有效），
   `check_badge` **PASS**（徽章 + 自检注释 + 快照同源三格）。

## 2. 资源消耗

- 模型：本会话统帅（无外部额度）；轮 186/187 的车道 J/L/M 已在前两轮结算。
- 工具/命令（本轮实跑）：`moon test --target js src/server`（598/598）、全量 `moon test --target js`
  （2067/2067，快照 `temp/g188_full.txt` + 源码面锚点 `temp/g188_full.txt.src`）、
  `check_test_sync.py`（`--total 2067 --fix-dry-run` / `--total 2067`）、`check_badge.py`、
  `check_doc_surface.py`、`_badge_anchor.write_anchor`（API 写锚点，CLI 只有 `--selftest/--show`）、
  一次性脚本 `temp/g188_countfix.py`（先 dry-run 后 `--apply`，行级作用域：只改含 2064 的行）。
- 未跑：native 轨（本机必崩，BUG-527）、WSL 复跑（上一次 2026-11-02）。

## 3. 任务分配记录

| 轮 | 车道 | 任务包（目标/边界/回传/验收） | 结局 |
|---|---|---|---|
| 186 | J | 自述无尺认领盲区审计（只读，禁改文档） | 5 条发现 → 入账 BUG-591 |
| 187 | L | `check_tools_sync` 分组计数判据 R8（只动该脚本） | 落地，29 格自检；首跑抓 4 处清单漂移 |
| 187 | M | USAGE 参数列/守卫归属措辞（只动 USAGE.md） | 落地 2 处 |
| 188 | 统帅 | ② 现读复核 + 补锁 + 计数面同步 | 本轮（车道额度紧张，文档计数面属终审同批登记，按轮 187 先例由统帅落笔） |

过程纪律：**未达标一项** —— 本轮计数面同步未派车道而由统帅亲笔（金条四）。理由：它是终审的同批登记面
（与 cl7/锚点同一笔提交），拆出去会产生跨车道索引窗口；事后不可补派（已落盘），如实记为流程债。

## 4. 遗留风险

- BUG-588 残余：`ensure_engine()` 默认落点 fail-open + 库名硬编码（要消灭需新单「默认目录 fail-closed」）。
- 2038/2039 档在 mcpcf 调用层**可锁但尚未锁**：引擎层 Int32 到期算术属 BUG-583（时钟 Int64 化专项，BACKLOG P1）。
- BUG-589：`check_plan_landing --gate` 判定面 11 条（上限 25），收紧上限是人的决定。
- BUG-591 ②③（CI 是否接 `check_usage_tool_count`）、④（镜像只增不删无尺）仍 OPEN；⑤ 见轮 189 汇报。
- owner 钉住项：BUG-527 / 542 / 565A / 566 / 582。
- 本地 main 领先远端多笔未推 ⇒ CI 面尚未验证本轮改动（push 属 owner）。

## 5. 后续建议

1. 时钟 Int64 化专项（BUG-583）落地后，把 2038/2039 两臂补进 mcpcf 调用层锁（注入点已就绪）。
2. 若 owner 决定消灭默认落点风险：`ensure_engine()` 在测试态 fail-closed（无显式 `data_dir`/env 即拒），
   并把库名做成参数；这属新单，不在 BUG-588 内代修。
3. 计数面同步建议做成「全量测试后自动提示」而非自动写盘（判例-63 的教训：写盘版曾误伤 19 文件 40+ 处）。

## 6. 超额内容

- 把 `check_test_sync` 的 `--fix-dry-run` 建议面**逐条人工核过**再落笔（7 处 [✓] + 12 处 [?] 全部判定为
  JS 测试计数语义，native 面 0 处被动）；日期戳同批更新，避免「数字对、日期错」的半截同步。
- 为快照补源码面锚点（`_badge_anchor.write_anchor`），使 `check_badge` 的「快照同源」一格真能判，
  而不是长期停在 rc=2「无法自证」。

## 7. 来源

- `src/server/mcpcf_embed.mbt`（`arg_now_secs` / `tool_ops_init` / `ops_data_dir` / `ensure_engine`，现读）
- `src/server/mcpcf_embed_bug583_wbtest.mbt`（`bug583_04_…` / `bug588_02_ops_init_data_dir_redirects_db`）
- `memory/bugs.md` BUG-588 抬头 + 轮 186 追记 + 本轮 `### FIXED(2026-11-12T02:53:00Z / BUG-588 …)`
- 快照：`temp/g188_full.txt`(+`.src`)、`temp/g188_test1.txt`、`temp/g188_mut.txt`、
  `temp/g188_testsync_dry.txt`、`temp/g188_testsync2.txt`、`temp/g188_badge4.txt`、`temp/g188_docs.txt`、
  `temp/g188_countfix_dry.txt` / `_apply.txt`
- 判据：`scripts/check_test_sync.py`、`scripts/check_badge.py`、`scripts/check_doc_surface.py`、
  `scripts/gen_plugins.py`、`scripts/check_plugin_sync.py`
