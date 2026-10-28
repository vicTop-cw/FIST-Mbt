# Round 3 报告：四条并发 lane 收口（BUG-458/459/460/461）

- 日期：2026-10-28（Asia/Shanghai）
- 统帅：lead；lane-a..h 为并发子代理（同一工作树、互斥写域）
- 本轮起点：`39b259fa docs(ledger): 立 BUG-461`
- 本轮终点：`c7e7dd75 docs(report): 追记并发提交归属`

## 一、结果摘要

| 项 | 读数 | 命令 |
|---|---|---|
| 全量 JS 测试 | **1743 / 1743 / 0 failed，rc=0** | `python scripts/moon_test_env.py --target js` |
| 工具外壳覆盖 | **154 / 154（100%），rc=0** | `python scripts/check_tool_coverage.py` |
| 守卫电池 | 99 PASS / 10 FAIL（**10 红全为存量，本轮零新增**） | `python scripts/run_guards.py` |
| 冲突标记 | PASS（1232 跟踪文件） | `python scripts/blackbox/check_merge_markers.py` |

落盘 6 笔（全部单文件/明确路径提交，判例-11）：

| commit | 内容 | lane |
|---|---|---|
| `b546258f` | BUG-461 迁移测试夹具改每进程唯一目录（+145/−10） | H |
| `f976ce77` | BUG-460 engine `deps_report` 三值化（加法式 API + 8 格白盒锁） | F |
| `6e5b51a5` | rx-mbt A1 降级 A1'，5h 窗口门收敛单一真源（5 格锁含变异对照） | G |
| `9518c590` | BUG-458 非法 kind 回结构化 Err + BUG-459 补齐 ns 写门 + 判据 `check_ns_write_gate_coverage.py`（501 行，9 格自检） | E |
| `85627d19` | `e2e_upgrade_mirror` 文档串 `'\F'` 非法转义（噪声 + 未来 SyntaxError） | H/统帅 |
| `902f2eec` | 覆盖判据转正一笔的真实归属追记 | 统帅 |

## 二、账本变化

- **FIXED**：BUG-458（内部 panic 被当工具面契约）、BUG-459（文档声称三支、代码只接一支）、BUG-460（依赖三态化：`missing` 与 `pending` 混为一谈）、BUG-461（夹具固定路径并发 `database is locked`）。
- **新立**：
  - **BUG-462** — store 包同族夹具固定路径/FIST_DB_PATH 共享，两进程并发整包即红（点名 `multi_store_test.mbt:170/245/269`、`store_sqlite_agents_wbtest.mbt:271/303/342/383`、`multi_store_bug420_wbtest.mbt:38`、`executions_upsert_test.mbt:21`、`call_log_test.mbt:33`）。
  - **BUG-463** — `MultiStore::close_all`（`src/store/multi_store.mbt:143`）只清 map 不关 sqlite 句柄，`SqliteStore` 无 public close：「测试能关、产品关不掉」。
  - **BUG-464** — publish 家族（`publish` / `publish_parallel` / `dag_publish`）走 human_steward 特权路径、**不查 ns ACL**，与 claim 侧不一致；BUG-459 只补了 ns 合法性门。

## 三、分析：本轮真正的三个发现

1. **「单进程绿」不是被测属性。** BUG-461 的 A/B 对照：HEAD 原版并发两进程跑 `src/store` → A 97/86/11、B 97/89/8（`Error: database is locked`），而同一文件单进程 97/97 全绿。⇒ 并发类缺陷的判据必须是「两进程同时跑」，单进程全绿只能证明「没同时跑」。
2. **文档声称 == 代码调用点，需要一个判据对表。** BUG-459 是「`write_gate.mbt` 写三支都拦、代码只接一支」的典型；补 `dag_publish` 会让文档继续骗人（`publish_parallel` 仍无门），所以同批补了第二支，让**判据的判定面**成立，而不是把判据窄化到能过。
3. **登记面 ≠ 执行面。** `run_guards.py` 的 `build_cases()` 会给每把 `check_*.py` 自动补一格裸跑，因此「删掉手写的 `--selftest` 格」对任何计数判据都不可见（`check_battery_count_doc` 照 PASS）。那一行承重的是「自检被真跑到」，不是计数 —— 想用「删了就红」自证必须另立判据，不能假设。

## 四、工具行为教训（可复用，建议进 AGENTS.md）

- **本机 `moon fmt <单文件>` 实际是整包格式化**：本轮三条 lane 各被连带改写 8~14 份他人文件。正确姿势 = `git status --porcelain > /tmp/pre.txt` → fmt → `git diff --name-only` 逐条核 → 只留自己的，其余 `git checkout --`。
- **判「是否只是 fmt 噪声」不能用 `git diff -w`**（行内折行会改变行结构，`-w` 仍报差异）。真判据 = 剥离全部空白+逗号后的 token 流 sha256 与 HEAD 比对（本轮据此确认 4 份纯 whitespace、3 份折行+尾逗号、1 份另有 `ts=ts→ts~` 归一，全部无语义变化）。
- **`scripts/fist.py call` 的参数面严格**：数组参数要传 JSON（`--bug_ids '["BUG-461"]'`），键名必须逐字对 `tools/list`（`report_bug` 用 `summary` 不是 `title`；`bug_fix` 用 `bug_ids` 不是 `ids`；`agent_acl_grant` 不收 `project_dir`）。别猜。

## 五、缺口与风险

1. **`88cc16c7` 的 commit message 与内容不符（我的过失，已记录未改写）**：我 `git add` 三份「副机锚点抗漂移」文件时，内容已被并发会话以 `501c4929` 提交，只剩 `memory/bugs.md` 进了暂存面，而 message 仍写着脚本改动。实际落盘仅 `memory/bugs.md`（+29/−4，即本轮 4 笔 FIXED 与 3 笔新立）。**未 rebase 改写历史**（同树有并发写者），改为在此报告公开记录 —— 下不为例：`git add` 之后必须看 `git diff --cached --name-only` 再写 message，本轮这一条我自己破了。
2. **BUG-462 未修**：store 包同族夹具还有 5+ 处固定路径，需一轮专门 lane，写域跨多份既有测试文件。
3. **BUG-464 未修**：publish 家族 ACL 面。
4. **电池 10 红为存量**，已派 Lane J 逐条分流（修 / 需 owner 裁决 / 已证无关），其中 `check_scripts_naming` 棘轮 N1 29>16 属历史债，不由单轮解决。
5. **docs 测试数漂移**（1670/1532 vs 实测 1743，9 处）已派 Lane I。

## 六、超额内容

- Lane E 自检抓出并修掉自己的一个假绿：块切分只靠「撞下一块起点」会让最后一块吞掉文件尾 ⇒ 块外调用被算成「最后一个工具调了门」（M7 stray 格一度 rc=0），改成认同缩进的 `)` 收口行后 rc=1 并点名行号。
- Lane H 顺手把 `temp/` 并发残留清成 0，并给出「两进程整包并发全绿在写域内不可达」的证据化边界，而不是硬凑一个绿。

## 七、后续建议

1. 一轮专修 **BUG-462**（store 夹具族，写域 = 多份既有 `src/store/*_test.mbt`，需单 lane 独占）。
2. 一轮修 **BUG-464**（publish 家族 ACL 门，写域 `src/server/server.mbt` + 对表判据加一格）。
3. 把第四节三条工具教训写进 `AGENTS.md`（等 Lane I 的 docs 提交落盘后追加，避免同文件冲突）。
4. 电池 10 红收敛后再谈「全绿」；在此之前任何「全绿」表述都必须写成「10 存量红 + 本轮零新增」。

## 八、来源

- lane 回传（`lane-e-server` / `lane-f-engine` / `lane-g-router` / `lane-h-store`）五段报告，逐条含命令与读数。
- `git log --oneline 39b259fa..c7e7dd75`、`git show --stat` 各笔。
- `memory/bugs.md`（BUG-458/459/460/461 FIXED 记档；BUG-462/463/464 新建）。
- fist 任务 ns `r1goal`：T0r5（E）、T0r6（F）、T0r7（G）、T0r8（H），均已 `verify` → 已完成。
