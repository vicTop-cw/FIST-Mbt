# FIST-Mbt `--upgrade` 自动升级 · 阶段 1（`--check` 只读）实施报告

- **日期**：2026-10-11
- **驱动**：指挥官「fist-mbt 没有自动升级功能 --upgrade，设计一下」
- **范围**：设计文档 `docs/2026-10-11-fist-upgrade-design.md` §9「阶段 1（只读）」的落地与实测
- **状态**：阶段 1 完成、实测通过；阶段 2（写盘）待指挥官批准

---

## 结果摘要

`fist-mbt upgrade --check` 已实现并端到端跑通：能**读本地版本 → 探测 GitHub 远端最新版 → 语义化比较 → 给结论**，全程零写盘。检测失败或不可比较时**显式 rc≠0 报错，绝不回落成「已是最新」假绿**（R7）。

实测读数（本机 Windows + moon 0.1.20260920 + Node 25.2.1）：

| 判据 | 结果 |
|---|---|
| `moon check --target js` / `--target native` | 均无 error |
| `moon test --target js cmd/cli` | **5/5**（3 条 upgrade + 既有） |
| `moon test --target js`（全量） | **731/731** |
| `node cli.js upgrade --check` | **rc=0**，本地 v0.3.8 / 远端 v0.3.5 → 「本地超前（可能是 dev 构建），未动作」 |
| `node cli.js upgrade --bogus` | **rc=2**（用法错，BUG-106） |
| `node cli.js --upgrade-xxx` | **rc=2**（未知子命令，不被吞成 upgrade） |
| `scripts/cli_flag_probe.py` | **PASS** |
| `scripts/check_doc_surface.py` | **PASS** |
| `check_desc_enum_sync` / `check_scripts_index` / `check_tools_sync` | **PASS** |
| `scripts/check_plugin_sync.py` | FAIL（真源 `server.mbt` 在并发 agent 手上，非本阶段所致） |

---

## 资源消耗

- 代码改动：`cmd/cli/` 内 7 个文件（3 新增 + 3 编辑 + moon.pkg）+ `docs/2026-10-11-fist-upgrade-design.md` 状态与 §10 追加
- 构建：`moon build --target js` ×4；`moon check --target js` ×6 / `--target native` ×3
- 测试：`moon test --target js cmd/cli` ×3（5/5）；`moon test --target js` 全量 ×2（731/731）
- 守卫：`cli_flag_probe.py`、`check_doc_surface.py`、`check_plugin_sync.py`、`check_desc_enum_sync.py`、`check_scripts_index.py`、`check_tools_sync.py`
- ESM shim：`scripts/patch_esm_main.py` ×4（幂等）

---

## 任务分配记录

指挥官亲自动手（本次为孤立聚焦的 `cmd/cli` 单包阶段 1 收口，且处于既有实现的中间态，未再拆子代理）；设计阶段已前置在 `docs/2026-10-11-fist-upgrade-design.md`。

---

## 技术要点与踩坑（沉淀）

1. **MoonBit async 组合**：async fn 调 async fn 直接拿已 resolve 值，**不能再 `.wait()`**；`.wait()` 只用于 foreign `@js_async.Promise`。
2. **避免双重 JSON 解析**：`upgrade_fetch_latest` 已把 `{ok,tag,error}` 解包成 `Result[String,String]`，`latest_tag` 若再 `@json.parse` 会把 `Ok("0.3.8")` 当 JSON 解析失败——实测抓出并改为纯透传。
3. **Windows libuv 断言**：`AbortSignal.timeout` 的定时器在进程退出时若仍挂起，Windows 下 libuv 断言崩溃（`UV_HANDLE_CLOSING`）。改 `AbortController` + `finally clearTimeout` 后 rc=0 干净退出。
4. **pre-release 不相等**：`0.3.8-alpha1` 若不区分会被当成等于 `0.3.8`（假绿）。`parse_version` 加 `is_pre` 第四元，`cmp_version` 在数字段全同时让带 pre-release 一方更低。
5. **MoonBit 字符串 API 事实**：`split` 返回 `Iter[StringView]` 需 `.collect()` 才能 `[i]`；`substring` 必须命名参数；`String` 无 `index_of`/`parse_int`（手写 digit 循环）；`?` on Option 不支持（用 `match`）；`var` 已废弃用 `let mut`；`assert` 保留用 `assert_eq`。
6. **反引号 + 行续行 `\` 在 native 报 lexing 错**：MoonBit 字符串不支持 JS 风格反引号与 `\` 续行。
7. **BUG-114 同族顺手修**：`help_topics.mbt` 的 `FIST_VERSION="0.3.6"` 硬编码落后 moon.mod(0.3.8)，`cli_flag_probe.py` 抓出；改 `fn fist_version()` 动态取 `@server.get_version()`。

---

## 遗留风险与后续建议

1. **阶段 2 待批准**：`fist-mbt upgrade` 会写文件换二进制，按 AGENTS.md「不可逆操作只给方案+预案」，执行权留指挥官。建议复用 `install_onecmd.ps1` + 备份 + 自检 + 回滚（设计 §6/§7）。
2. **native target 未实跑**：本机 native 无 fetch，stub 返 rc=3 文案；如要在 Linux/WSL 实跑 native `--check`，需补网络层（阶段 3）。
3. **GitCode fallback**：GitHub API 不可达时的 GitCode 兜底留阶段 3。
4. **`check_plugin_sync.py` 红**：真源 `src/server/server.mbt` 正被并发 agent 改（工具数/描述漂移）。**非本阶段代码所致**——本阶段只改 `cmd/cli/`，不进 `gen_plugins.py` 的源面（server.mbt / moon.mod / bugs.md / .mcp.dev.json）。待 server.mbt 收口后由该项目负责人重新 `gen_plugins.py` 并复跑守卫。
5. **`--channel` / MCP 工具面**：设计 §3 列了 `--channel <stable|pre>` 与 MCP 工具面，均留后续阶段。
6. **发现：远端最新 release 是 v0.3.5，而 moon.mod 是 0.3.8**——说明 0.3.8 尚未发布 GitHub Release。这是「本地超前」的正确语义；也提示发布流水线（`release.yml`）与版本前进的节奏要跟上，否则用户会长期看到「超前」。

---

## 超额内容

- 顺手修复了 `help_topics.mbt` 的 `FIST_VERSION` 静态漂移（BUG-114 同族，`cli_flag_probe.py` 抓出），使帮助面版本 == moon.mod。
- 在设计文档追加 §10「实施记录 · 阶段 1」，记录实现细节、实测读数与遗留。

---

## 来源

- 设计文档：`docs/2026-10-11-fist-upgrade-design.md`（§9 分阶段建议、§10 实施记录）
- 代码真源：`cmd/cli/upgrade_core.mbt` / `upgrade_js.mbt` / `upgrade_native.mbt` / `upgrade_wbtest.mbt` / `subcmd.mbt` / `main.mbt` / `help_topics.mbt` / `subcmd_wbtest.mbt` / `moon.pkg`
- 版本源：`moon.mod` `version="0.3.8"`；BUG-114 常驻锁 `src/server/fist-mbt_wbtest.mbt`
- 判据入口：`scripts/cli_flag_probe.py`（BUG-106/114）、`scripts/check_doc_surface.py`（J15）、`scripts/check_plugin_sync.py`