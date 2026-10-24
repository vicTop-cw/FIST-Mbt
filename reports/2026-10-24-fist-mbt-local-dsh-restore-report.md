# 报告 · 本地 fist-mbt 命令与 DSH 插件恢复最新可用（BUG-405）

日期：2026-10-24 ｜ 执行：lead ｜ 依据：用户指令「其它项目 fist_mbt 服务不可用，你更新一下本地 fist-mbt 命令并更新 dsh fist-mbt，让其恢复可用且最新」

## 结果摘要

| 项 | 修复前 | 修复后 |
|---|---|---|
| 本地 `fist --version` | v0.3.9（Oct 18，落后） | **v0.3.10**（moon.mod 真源一致） |
| `fist serve` MCP initialize | — | **可用**：`{"serverInfo":{"name":"fist-mbt","version":"0.3.10"}}` |
| DSH 插件安装面 `cordis.patch.yml` | 硬编码旧路径 `F:/AI/Fist-Mbt`（不存在）⇒ **断连根因** | 指向 `E:/IDEProjects/AI/FIST-Mbt/_build/js/release/build/cmd/cli/cli.js` |
| 渲染器 CLI 选择 | 硬编码 debug > release（debug 旧 07:42，release 新 10:19，仍选 debug） | 按 mtime 取新（自动选 release 10:19） |

## 资源消耗

- `moon build --target js --release cmd/cli`：71 任务，0 errors（约 2 分钟）
- 守卫电池 `run_guards.py`：零真实红
- 专项守卫：`render_dsh_patch.py --check` PASS / `--selftest` OK / `check_hardcoded_paths` PASS（572 跟踪文件干净）

## 任务分配记录

- lead 独立完成（无副机派单）：诊断根因 → 构建 release → 渲染 cordis → 更新本地 fist-mbt.js → 修渲染器 bug → 验证 → 沉淀。

## 遗留风险

1. **DSH 需重新加载插件**：`cordis.patch.yml` 已改，但 DSH 侧需刷新/重连 MCP 才能看到 v0.3.10。若仍显示断连，重启 DSH 会话。
2. **`check_plugin_sync.py`（cl7）仍红**：`plugins/claude/skills/{fist-commander,fist-mbt}/SKILL.md` 内容不一致 —— **非本次改动引入**（我未动 plugins/），属 fist-bot 插件同步面。
3. **`locale/*.json` 同源隐患**：`check_hardcoded_paths.py` 提示 `cordis.patch.yml` 与 `locale/*.json` 都是 `F:/AI/Fist-Mbt` 位置高发区 —— 已复查 locale 无残留，但建议守卫补形状锁。

## 后续建议

1. 给 `render_dsh_patch.py --check` 加一条"渲染件里不得出现任何已知历史机器路径"的形状锁（词表 + 形状双面），让**本地产物内部**的路径污染也能被 `run_guards` 抓（当前守卫只查跟踪面，本地产物已 ignore 不进跟踪面）。
2. DSH 断连的自愈建议：在 `fist-mbt.js` 启动时若 `cwd` 不存在，报错信息带上"检查 `render_dsh_patch.py`"提示，方便外部诊断。

## 超额内容

- 顺手修了**渲染器优先级 bug**（BUG-405 关联）：`render_dsh_patch.py` 硬编码 `debug` 先于 `release`，而两者是独立构建目录，谁新谁旧取决于最近一次 `moon build` 用什么 flag。已改为按 `st_mtime` 取新，与 glob 兜底同一律。

## 来源

- 用户指令（2026-10-24 10:13）：「其它项目 fist_mbt 服务不可用，你更新一下本地 fist-mbt 命令并更新 dsh fist-mbt，让其恢复可用且最新」
- 诊断证据：`git rev-parse --short main` = `3897d378`（本地 main）；`grep version moon.mod` = `0.3.10`；`node fist-mbt.js --version` 修复前 v0.3.9
- 根因：`.dsh/fist-mbt-plugin/cordis.patch.yml` 硬编码 `F:/AI/Fist-Mbt`（旧机器路径，不存在），DSH mcp-client stdio 把 args/cwd 当字面 argv 交 spawn，宿主不做 `${}` 插值 ⇒ server 起不来