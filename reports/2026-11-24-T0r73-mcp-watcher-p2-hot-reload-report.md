# T0r73 · mcp-watcher P2 热重载（可换表规则容器 + mtime 轮询）执行报告

- 日期：2026-11-24
- 任务：T0r73（namespace=autoplan，优先级=高）
- 执行身份：codearts（svc-codearts，端口 18641）
- 验收目标：运行中改配置即生效；坏配置不停机（保留旧表）；`reload` 子命令；`status` 显示表版本

---

## 一、结果摘要

在依赖副本 `vicTop-cw/mcp-watcher@0.2.0` 内落地 §P2 热重载，四件全部完成并实测：

1. **可换表规则容器** `LiveRuleTable`：版本号单调递增 / 装载时刻 / 规则数 / 最近校验诊断；
   `swap()` 原子替换 `rules_ref`（既有 `attach_rules` 调用面零改动）；失败只写 meta 不动规则。
2. **mtime 轮询→解析→校验→原子换表**：`fs_stat` 指纹 diff（None=变化、mtime 或 size 变=变化、
   不变=零成本跳过）；stat 失败不动画表；装载复用 `Config::from_json`（尾部含 `validate_config`）。
3. **daemon 接线**：`run_daemon` 建表 → 启动即写侧车基线 → 常驻轮询任务（与 EP-01d 事件通道
   共用同一张表，谁先看到变更都能热切换）；每次成功换表落侧车。
4. **CLI**：`reload` 走表通道并报「表版本/规则数/装载时刻」；`status` 读侧车显示同三项 + 最近错误。

新增测试两面：纯逻辑格（全目标，40 格）+ native 真文件轮询 e2e（18 格，native 门控）。

### 验证读数（本机 Windows，moon 钉版 0.1.20261016）

| 面 | 命令 | 读数 |
|---|---|---|
| JS · scheduler | `moon test --target js scheduler` | **Total tests: 40, passed: 40, failed: 0** |
| Native · scheduler | `moon test --target native scheduler` | **Total tests: 58, passed: 58, failed: 0** |
| Native · 编译 | `moon check --target native scheduler` | **Finished. (14 warnings, 0 errors)** |
| JS · 全仓 | `moon test --target js`（格式化后复跑） | **Total tests: 40, passed: 40, failed: 0**（scheduler 包面；全仓口径见「缺口」） |
| 格式 | `moon fmt` | Finished（无残留改动，`git status .mooncakes` 空） |

> native 本轮在本包真跑通（scheduler 测试 exe 未带 `-lsqlite3` 链接），
> 与 BUG-527「全项目 native build/test 必崩」不冲突——那条边界针对**可执行包/全仓**链接面。

---

## 二、产出物（绝对路径）

根：`E:\IDEProjects\AI\FIST-Mbt\.mooncakes\vicTop-cw\mcp-watcher`

| 文件 | 行数 | 改动 |
|---|---|---|
| `scheduler/scheduler.mbt` | 1488 | 新增 `LiveRuleTable`(:946) / `fingerprint_changed`(:1070) / `apply_rules_text`(:1133) / `table_state_path`(:1215) / `parse_table_state_text`(:1269) / `write_table_state`(:1357) / `poll_rules_once`(:1392) / `POLL_INTERVAL_MS`(:1419) / `poll_rules_file`(:1427，native 真循环 + 非 native 诚实空转) |
| `cmd/main/main.mbt` | 942 | `run_daemon`(:217-330 段)：建表 + 初始侧车(:249) + 轮询任务(:318)；`cmd_status`(:705 起) 读侧车；`cmd_reload`(:783 起) 走表通道 |
| `scheduler/hot_reload_test.mbt` | 233 | 新增 · 纯逻辑 18 格（全目标） |
| `scheduler/hot_reload_native_test.mbt` | 221 | 新增 · native 真文件 4 格（已登记 `moon.pkg` targets 门控） |
| `scheduler/moon.pkg` | 27 | 新增 `"hot_reload_native_test.mbt": [ "native" ]` 门控 |
| `scheduler/reload_native_test.mbt` | 117 | 夹具路径由上游硬编码绝对路径改为副本内相对路径 `tests/harness/...` |

---

## 三、关键实现决策

- **指纹跨轮存活于单次常驻循环**：`poll_rules_file` 内 `fp` 为局部 `Ref`，循环跨轮持续；
  每被调用一次都从 `None` 起。测试首轮若误用两次独立调用，会把「第二次调用的首轮」当变化而重复装载
  （实测踩到，已按生产语义改为单调用多轮，见下节实证）。
- **休眠不抽象为注入参数**：曾尝试把 `@async.sleep` 抽成 `sleeper~` 以便确定性驱动，但本仓/async
  无「async 函数类型作参数」先例，收益不抵风险 ⇒ 回退，保持生产循环原样；可测面交给
  `poll_rules_once` 的纯判定格（全目标）+ 真文件 e2e（native）。
- **`@async.sleep(interval_ms)` 的类型坑**：该 API 收 `Int`，轮询间隔是 `Int64` ⇒ js 目标因无 async
  体被当警告放过、native 真红（Expr Type Mismatch）。已 `to_int()` 修正。
- **兼容**：既有 `rules_ref` / `reload_config` / `ReloadResult` / `attach_rules_file_reload` 事件通道
  一字未动，新容器是其上层；daemon 中两路并行、共用一张表。

---

## 四、实证与排错（真实抓到的两处）

1. **「无变化却重复装载 v3」**：先怀疑 Windows mtime 精度，加诊断格连 stat 四次 —— 读数逐位相同
   （`1795520615583564100` ×4），推翻精度假设；根因是**测试把两次独立 `poll_rules_file` 调用当作
   「连续两轮」**，而每次调用 `fp` 都重置为 `None`。改成单调用多轮后通过。
   ⇒ 结论：不是产品缺陷，是测试语义错位；此错位若不修，会永久掩盖「指纹记忆」这一核心性质。
2. **`sleep(Int64)` 类型错**：native check 实红 1 error，js 面看不见 ⇒ 判据必须 native 复验，
   不能只跑 js（本次正是靠 native 面兜住）。

---

## 五、缺口与风险

1. **未做上游落地**：`.mooncakes/` 在 `.gitignore` 内、CI 每次 `rm -rf .mooncakes`（ci.yml:29-32）
   ⇒ 本轮改动**无法随本仓提交分发**，只能作为「工作区副本内实现 + patch」。上游真源克隆
   `E:\IDEProjects\AI\mcp-watcher`（v0.2.3）不在本轮可编辑范围 ⇒ 上游落地与版本 bump 归 **T0r77**。
2. **版本漂移**：依赖副本 0.2.0（RX-MBT@0.4.5）vs 上游 0.2.3（RX-MBT@0.4.6 + moonbitlang/x@0.5.5，
   含 EP-02a/EP-02b）⇒ 两处不同源，向上游移植时需重测（Rx 时钟 API 可能有差）。
3. **js/wasm 无 fs**：`fs_stat`/`fs_read_text` 非 native 恒 `Err(Io)` ⇒ 轮询在这些目标为诚实空转
   （不假装在工作）；热重载的**真文件能力只在 native**。这符合本仓既有口径（EP-01d 同款门控）。
4. **轮询 e2e 依赖 `@async.sleep` 真实定时**，属慢格（20ms×N 轮）；测试夹具已逐格隔离并清理，
   不复用他格残留文件（诊断过程证明同实例/跨实例残留都会污染指纹观测）。
5. **`cmd_status` 读的是侧车**：daemon 未启动时无侧车文件 ⇒ 显示为空/不可得（已按「读不到即自拒」
   处理，不编造读数）。

## 六、后续建议

- 上游落地（T0r77 车道）：把 `scheduler.mbt` 的容器+轮询段、CLI 接线、两个测试文件按上游
  0.2.3 基线重放，重点复验 Rx 时钟与 fs API 差异。
- 可选增强（非本单范围）：轮询间隔 `--poll-interval-ms` 旗标；侧车加入 `etag`/内容哈希，
  使「内容变而 mtime 未变」的极端场景也能命中（当前指纹只含 mtime+size）。
- 上游修复后可删除「非 native 空转」分支注释中的临时说明，改为引用上游行为。

## 七、来源

- 任务包原文（ns=autoplan，T0r73 description）：`mcp-watcher P2 热重载（§P2）…验收：运行中改配置即生效，坏配置不停机`
- 计划真源：`E:\IDEProjects\AI\FIST-Mbt\.mooncakes\vicTop-cw\mcp-watcher\workbuddy\plan\development-plan.md` §P2
- 基线：上游克隆隔离 worktree `python scripts/moon_test_env.py --root E:/IDEProjects/AI/mcp-watcher-p2 --target js`
  ⇒ 203 total / 197 passed / 6 failed（红全在 action/webhook_js_test 2 + action/mcp_stdio_js_test 4，
  为**既有** e2e 红，非本轮引入）；落点副本 `--target js scheduler` ⇒ 25/25 绿（基线）。
- 判绿口径：不以「全仓全绿」宣称；本单判据 = 不新增红 + scheduler 包两面全绿 + native 编译 0 error。
