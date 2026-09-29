# 汇报 · 2026-09-29 · Qoder 插件封装（fist-mbt 黑盒形态）

写盘时间：2026-09-29T03:41:59Z（本机 11:41 +0800）

## 结果摘要

FIST-Mbt 现在有第五种宿主形态——一个已注册启用的 Qoder 插件 `fist-mbt@local v0.1.0`：

- 源目录 `~/.qoder-cn/plugins/fist-mbt/`，运行副本 `~/.qoder-cn/plugins/cache/local/fist-mbt/0.1.0/`（`diff -rq` 逐字一致）
- `skills/fist-commander`（分流/任务包/终审/沉淀）+ `skills/fist-mbt`（129 工具消费手册 + 9 份 references）→ `qodercli skills list` 已登记为 `fist-mbt:fist-commander` / `fist-mbt:fist-mbt`
- `commands/{check-in,verify,board,triage}.md`（默认只读，写操作要先展示再确认）
- `mcp.json` + `scripts/fist_mcp_bridge.mjs`（stdio 协议桥）+ `scripts/verify_bridge.mjs`（自检）+ `CONNECTORS.md`（环境变量与存储落点）+ `README.md`
- 注册面：`installed_plugins_v2.json` 的 `plugins["fist-mbt@local"]` + `settings.json` 的 `enabledPlugins["fist-mbt@local"]=true`（改前各留了 `.bak-20260929`）

黑盒边界：插件只调 PATH 上已注册的 `fist-mbt` 命令，不含、不构建、不引用 `E:\IDEProjects\AI\FIST-Mbt` 源码树；仓库源码本轮**一行未改**。

## 资源消耗

- 量级（未留逐项计数底）：约 30 次本机命令、13 次文件写、1 次 4 问确认；`qodercli` 嵌套调用 5 次；子代理 0 次
- 最贵的一步：在 91 MB 的 Qoder bundle 上 grep 协议版本表（首次 240 s 超时转后台，窄化 pattern 后完成）
- 副作用：桥的一次旧版本运行把 `fist-mbt.db` 写进了插件包目录（已迁出并修死）；`fist-mbt version/doctor` 在探针目录各建过库

## 任务分配记录

| 档 | 走法 | 内容 |
|---|---|---|
| 轻 | 指挥官亲自做 | 协议对表、桥实现与两轮修复、README/CONNECTORS 判据口径 |
| 中 | 指挥官亲自做 + 自检门 | `tool-map.md` 生成（14 组求和 == `tools/list` 基数门）、references 消费视角改判 |
| 重 | 未派单 | 本次改动全在仓库外，未建 FIST 任务树（没有台账可收口，故不虚构 ns） |

## 遗留风险

1. **无守卫的投影**：Qoder 形态不在 `gen_plugins.py` 宿主顺序内，也不受 cl7 `check_plugin_sync.py` 逐字节覆盖 ⇒ `plugins/source` 一改即静默落后。
2. **产物滞后**：本机装的是 v0.3.0/129，仓库 moon.mod 已是 0.3.4（另据记忆：dist 侧还见过 126 的陈旧孪生）⇒ 插件正文里所有计数随产物版本走，升级后必须重跑 `verify_bridge.mjs`。
3. **存储语义**：库落点随 spawn cwd 变（`store_open(scratch)` 不做隔离，唯一真出口是 spawn 期 `FIST_DB_PATH`）；桥固定 workdir 治了漂移，但也意味着插件台账与仓库根那份真实台账（1986 任务）默认是**两份库**，要合流须显式设 `FIST_DB_PATH`。
4. **斜杠命令名未证**：`commands/` 被宿主识别为 convention component（`plugin validate` 已报），但确切 `/` 名要在新会话补全里看——本会话早于插件安装，`qodercli mcp list` 也证明它不列插件自带 server，故连接器实接只验到「模拟客户端 + 配置面」两层。

## 后续建议

1. 把 Qoder 形态接进 `gen_plugins.py`（第五宿主）+ 扩 `check_plugin_sync.py` 的逐字节守卫，消掉风险 1；
2. `scripts/verify_bridge.mjs` 的 7 格 + 摘 PATH 对照格可以收进 CI 的文档面之后一步（判据自带反向对照，符合 J10 口径）；
3. 只读命令往 cwd 落库那条，值得按活证据走一次 `report_bug`（复现：空目录 `fist-mbt version` ⇒ 出现 `fist-mbt.db`；`doctor` ⇒ 另出 `_fist_doctor_check.db`）——本轮没建任务树也没报账，留给你裁决是否入账；
4. 想让插件默认接着用仓库根台账，就把 `FIST_MBT_WORKDIR`/`FIST_DB_PATH` 指过去，别把两份库长期并行。
5. 把 `plugins/source/references/omega-verification.md` 的表名改到实测面（`specs` / 无 `gate_records`），否则下一次投影还会把这双假表名带出去；这条与风险 1 一起修最省（改真源 → 接进生成器 → 重装插件）。

## 超额内容

- `CONNECTORS.md` 里补了「工作目录 = 存储位置」这一节（含三条落点实测与"仓库根库勿删"的告警），超出原始需求。
- 对拷进来的 references 做了调用面改判（BUG-9 控制面、BUG-4 默认收紧、BUG-16 版本真源改指 `fist-mbt version`），并清掉了未插值的 `{{PLACEHOLDER}}` 与 CRLF/BOM（`known-issues.md` 原带 BOM，会让 frontmatter 解析踩坑）。
- **抓到上游 reference 的一处文档↔行为不符并就地改判**：`plugins/source/references/omega-verification.md` 写的 `omega_specs` / `gate_records` 两张表在实测 `sqlite_master` 里**不存在**（真名是 `specs`，`run_check` 判定按 `spec_type='check'` 落 `specs`，`runs` 表存在但 0 行）。插件那份已按实测重写并加了「先列 `sqlite_master` 再查表名」的告警；**仓库真源那份仍是错的**，见后续建议 5。

## 来源

- 本机实测：`fist-mbt version`（v0.3.0）、`tools/list`/`resources/list`/`prompts/list`/`tools/call` 探针、`verify_bridge.mjs` 正反向两跑
- 仓库真源：`plugins/source/SKILL.md`、`SKILL.commander.md`、`plugins/claude/skills/fist-mbt/references/*`（生成态、已插值）、`plugins/claude/.mcp.json`、`.gitignore:9 *.db`、`git remote -v`、`moon.mod`
- 宿主事实：`~/.qoder-cn/plugins/cache/qoder-bundler/qoder-create-plugin/skills/create-plugin/`（清单规范 + 离线校验器）、`@qoder-ai/qodercli/bundle` 内协议版本表与 `${QODER_PLUGIN_ROOT}` 替换、Qoder 文档 https://docs.qoder.com/extensions/plugins（`/plugin-name` 调用形态）
- 交叉印证：`AGENTS.md`「一源四态 · 插件态」段、既有记忆 [[reference-fist-mbt-store-namespacing]] / [[reference-fist-mbt-lifecycle-gotchas]]
