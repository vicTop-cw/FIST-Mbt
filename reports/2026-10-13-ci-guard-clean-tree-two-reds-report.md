# 2026-10-13 · CI 守卫族干净树两红定因与修复报告（R13 / R1）

## 结果摘要

**一句话**：在 `git archive HEAD` **干净树**（=CI 检出面）上跑守卫族，11 支中 2 支真红；
两支都已定因、修复、并实测转绿 ⇒ **干净树守卫族 11/11 全绿（红支数 0）**。

| 守卫 | 修复前 | 修复后 | 缺陷真身 |
|---|---|---|---|
| `check_release_asset_names`（R13） | rc=1 | **rc=0** | README 离线线写死 `fist-mbt-js-v0.3.6.zip`，而 moon.mod=`0.3.8` ⇒ 用户照抄即 404 |
| `check_entry_paths`（R1） | rc=1（2 处） | **rc=0** | `docs/2026-10-12-mcpcf-embed-serve.md` 引用退役入口 `cmd/main`（表格 + 构建命令） |

修复提交：`c434a5c`（R13，README 单行）、`862870f`（R1，mcpcf 文档三处 + 两条注记）。

## 关键方法学：干净树必须**先 `git init`**（我第一版实验的 harness 缺陷）

第一版我把 `git archive HEAD` 解到目录后直接跑守卫，得到 5 支"红"——其中 3 支是
`FATAL git ls-files 退出码 128: not a git repository`：`check_tools_sync` / `check_doc_surface` /
`check_publish_payload` 都靠 `git ls-files` 读跟踪面，而 archive 解出的目录**不是 git 仓库**。
那是**我的 harness 坏了**（判据自己崩不许冒用被测的读数），不是守卫红。
第二版补 `git init -q && git add -A -f`（模拟 `actions/checkout` 的"真仓库 + 只有 tracked 文件"面）后，
读数变成 **9 PASS / 2 真红**——与 CI 实际相符。**这条留档**，免后来者重犯同一个假红。

对照读数也说明一件事：**本地工作树 ≠ CI 检出面**。本地工作树那轮报 `check_tools_sync` 红
（145 工具 vs 真源 140）等，全是并发会话未提交 WIP 造成的；干净树无这些文件，11/11 绿。
⇒ 判据面必须明确"在哪个面上跑"，否则会把别人的 WIP 读成产品缺陷、或把自己 harness 的崩读成红。

## 两支红的定因与修法

**R13（`check_release_asset_names`）**——真缺陷，且是判据立格的原因本身：
R1（只扫安装器、禁写死默认版本）与 J4（只认 `@x.y.z` 式版本声明）两面之间的缝里，
README 的 `fist-mbt-js-v<版本>.zip` 字面量无人认领 ⇒ 版本前进后照抄离线/内网线指向不存在的资产。
真源对照：BACKLOG `release-fact: v0.3.8 … asset=fist-mbt-js-v0.3.8.zip bytes=429290`。
修法：单行 `v0.3.6.zip` → `v0.3.8.zip`；实测干净树 R13 rc=1 → rc=0。

**R1（`check_entry_paths`）**——该 docs 文件属**现状面**（R1 的历史豁免面只含
`memory/` / `reports/` / `docs/superpowers/` + `CHANGELOG.md`，`docs/` 不在其中），故引退役入口即红。
修法**刻意不粉饰历史**：表格与命令改为现役入口 `cmd/cli`，各加一条注记写明"当时以 `cmd/main` 构建、
其后已退役"。**L4 实证先行**（不据 `supported_targets` 声明就写文档）：WSL 同版 nightly
`moon build cmd/cli --target native` rc=0 ⇒ 产物 `_build/native/debug/build/cmd/cli/cli.exe`。

顺手测到 R1 判据的一处**实际口径**（写文档的人会踩）：反引号里的**裸** `` `cmd/main` `` 提及**不判**
（判据只认命令与路径形状，见其正文 L141-147），但 `` `…main.exe` `` 这种**路径形状**会被判红——
我第一版注记里带了 `main.exe` 形状，当场红了一次，去掉该形状后 PASS。这不是判据的 bug，
是"提及退役入口自身"与"给出可照抄的路径形状"之间的界线；留档给后人。

## 资源消耗

- 干净树实验 6 次（含 2 次 harness 缺陷版重跑），全程 `E:\temp\clean-*`，不碰共享工作树；
- WSL 隔离副本 1 次（cmd/cli native 构建实证，同版 nightly 0.1.20261012）；
- 守卫族全量跑 3 轮（本地工作树 1 + 干净树 2）；
- 本链零 `.mbt` 改动，未跑 `moon test`（守卫面全绿即本链的判据）。

## 任务分配记录

- 指挥官亲自：干净树 harness 设计与纠错 → 两支红定因 → 精确暂存修复 → 成对实测 → 报告。
- **未派子代理**：本链的每一步都要与"并发会话 WIP 面"做归属判定（精确暂存、只提交我的行），
  这正是本仓禁止旁观者代提交的面，外包会引入代提交风险。
- 边界：`src/**`(92 脏)、`cmd/**`(10 脏)、`plugins/**`(18 脏)、`memory/**`、`scripts/README.md`、
  `.github/workflows/*`（并发会话的 `continue-on-error` WIP）一律未碰未提交。

## 遗留风险

1. **精确暂存是"绕过并发面"的手工动作**：两次都用 `git hash-object -w --path` +
   `update-index --cacheinfo` 只推进我的改动，事后实测工作树 WIP 完整保留
   （README 55 行、mcpcf docs 48 行）。风险点是**若并发会话随后提交同名文件，我的 index 版本可能被覆盖**；
   已在本报告记录，交由合并时核对。
2. **`continue-on-error: true` 已被 AGENTS.md 的 Commit gate 节渠道化**（并发会话所写）：它明确
   "本地 fmt 落盘为准 + 并发 WIP 收口后 nightly 全仓重排再撤销 fmt 门"。我先前担心的
   "步名自称门却永不阻断"已被文档化为**临时措施**，故本轮**未新增判据**（避免与他们的决定打架）。
3. **干净树 11/11 ≠ CI 全绿**：CI 的 js 臂还有 `Format check`（并发会话已降为信息步）与
   其后被 skip 的守卫族；native 臂已全绿（另报告）。判据面（守卫族）与 CI 作业面要分开读。
4. **`check_tools_sync` 在本地工作树红（145 vs 140）**是并发 WIP 的预期形状；他们提交后该项应自平，
   我不代提交。

## 后续建议

1. **把"干净树守卫族"做成一条常驻判据**：本轮证明"本地工作树读数"与"CI 检出面读数"会给出不同结论，
   而 CI 检出面才是判据面。可加一支 `scripts/blackbox/e2e_guards_clean_tree.py`：`git archive HEAD`
   → `git init` → 逐守卫跑 → 汇总（这正是本轮 harness 的固化）。
2. **R13 那类"两面之间的缝"值得普查**：本轮修的 README 字面量是 R13 立格时就点名的形状，
   但同类缝（R1 扫安装器 / J4 只认 @ 式声明 / 文档离线线）可能还有别的落点；建议用 R13 的思路
   逐面反解、而不是手写清单。
3. **`docs/` 是否该进 R1 历史豁免面**：`docs/` 按 J15 是"评估/决策归档面"，按 R1 却是现状面——
   两处口径不同。若认为历史评估不该被追溯改写，应把 `docs/` 与 `memory/` `reports/` 同列豁免；
   若认为用户会照抄 docs 里的命令，则现状判定正确。**这是口径裁决，属 owner**，本轮按现行判据执行。
4. `check_entry_paths` 的反引号口径可写进其 docstring 自述的 scope 段（现已说明"只认命令与路径形状"，
   但没给"反引号里的裸提及不判、带 `.exe` 形状判"这一实测对照）。

## 超额内容

- 顺手修掉我自己第一版 harness 的假红，并把"干净树必须先 git init"这条写进报告与建议。
- 顺手测出 R1 在反引号/路径形状上的真实边界，给出一支实测对照（这不是判据缺陷，是界线）。
- 干净树终审顺带确认了并发会话已把 `check_doc_surface` 从多轮 FAIL（J14/J15）推到 PASS，
  且 `check_plugin_sync` / `check_publish_payload` / `check_scripts_index` 在 CI 面上均绿。

## 来源

- 干净树终审读数：`E:\temp\clean-final`（11 支守卫，红支数 0）；第一版假红读数见本报告方法学节。
- R13 真源：`BACKLOG.md` 的 `release-fact: v0.3.8 … asset=fist-mbt-js-v0.3.8.zip bytes=429290`；
  判据 `scripts/check_release_asset_names.py`（`EXPECTED_ASSET` / `ASSET_TMPL`）。
- R1 真源：`scripts/check_entry_paths.py` 正文 L10-11（退役定义与现状面）、L34-36（历史豁免面）、
  L141-147（只认命令与路径形状的口径）；入口清单反解 `cmd/cli, cmd/main｜发布 cmd/cli｜退役 cmd/main`。
- L4 实证原件：`temp/cmdcli_native_direct.txt`（`moon build cmd/cli --target native` rc=0 + 产物路径）。
- 修复提交：`c434a5c`（R13）、`862870f`（R1），均双远端同步。
- 并发面观测：README 55 行 WIP、mcpcf docs 48 行 WIP（AIGC 元数据）均未被我提交；
  AGENTS.md 新增 Commit gate 节（并发会话）记载 `continue-on-error` 的临时性。
