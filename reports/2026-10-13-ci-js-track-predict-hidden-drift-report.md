# 2026-10-13 · CI js 轨「Format 降门后」预测 + 隐藏漂移定因报告

## 结果摘要

**一句话**：在 `git archive HEAD` **干净树**（=CI 检出面）上按 ci.yml **原序**跑完 js 轨 31 条调用面，
预测 Format 门降为信息步后 CI 的**真实**形状 —— 结果**不是全绿，而是 3 支红**，其中两支暴露了
**长期被 Format 门掩盖的真漂移**。

| 项 | 读数 |
|---|---|
| 前置（CI steps 2–5） | `moon update` rc=0 / `migrate` rc=0 / `Check (js)` rc=0 / **HTTP 契约自证 6/6 PASS** |
| step 7 `Test (js)` | **`Total tests: 807, passed: 807, failed: 0`** |
| steps 8–26（守卫族 + e2e） | **28/31 通过** |
| 3 支红 | `check_badge`（README 徽章 737 ≠ 实测 807）、`check_test_sync`（30+ 处文档自述 737/811 ≠ 807）、`cleanup_artifacts --check`（我的 WSL 残留） |

**核心结论**：守卫族**本来就在红**，与 Format 门无关；Format 门只是**从没让它们跑起来**
（CI 现状：`Format check` 之后 **19 步全 skip**）⇒ 这些漂移已积累多轮无人看见。
这正是本仓「红着没人读等于没锁」那句的另一面：**没跑起来的守卫比红着的守卫更安全地藏着问题**。

## 三支红的性质（逐支定因，含我自己的 harness 缺陷）

**① `check_test_sync`（真漂移，非我引入）** —— 文档自述 **737**（README 徽章 / AGENTS.md:88 /
ARCHITECTURE.md:81 / README_EN.md 多处 / docs/*.md 多处）与 **811**（BACKLOG.md:11），
而干净树实测 **807**。干净树违例清单 30+ 条，`R2` 另点名 README/AGENTS/deliverable/agent-map/
scoring_rubric 五处「**未出现实测总数 807 的声明**」。

**② `check_badge`（真漂移）** —— `BADGE-STALE: README 徽章 737/737 ≠ 实际测试数 807/807`。

**③ `cleanup_artifacts --check`（我的 harness 缺陷，非产品）** —— 报 `仓库残留 77 个根 .db + 45 个
temp/ 文件`；实测这些文件的 mtime **全在本树创建时间 20:26:11 之后**、名字是 `alpha.db` / `cb_b34_t*.db` /
`cl-alpha.db` 等我历次 **WSL 实验**的产物，**CI 的干净检出里没有它们**（本树 `运行前：根 *.db 数=0、
temp/ 不存在` 已记）。⇒ 该红是我在 WSL 侧累积的垃圾，不是产品缺陷。

**另外两支"红"是我的第二次 harness 缺陷（已自查更正）**：
第一发预测报 8/10 号红，根因是 `FileNotFoundError: /tmp/moon_test.log` —— 我**独立复跑**时把
CI 里"step 7 与 step 8/10 同 job 顺序执行"的会话割裂了（CI 上那份日志必然在场）。
修正版把 7→27 串进同一次执行后，8/10 号读到了真日志、报的**才是**真漂移。

## 顺带修掉：我自己上轮翻账引入的两处缺陷（`fabf0e3`）

对表翻账 L27 时我用 Python 内联字面量构造该行，引入两处**我自己的**缺陷，本轮均已修并实测：
1. **数据损坏（严重）**：`engine_boundary_test.mbt` 被写成 `\x1bngine_boundary_test.mbt`——
   逐字节核 HEAD blob 确认含 **ESC 控制字符 0x1b**（`\e` 转义被解释）。已还原正确拼写。
2. **判据面误伤**：同行 `146/146` 是**该包**测试数，而 `check_test_sync` 口径是
   "`N/N` 形状 + 附近有测试字样 ⇒ 视为**全量**声明" ⇒ 被判 `声明测试总数 146 ≠ 实测 807`。
   改为不复述包内计数后该行不再被判（干净树实测）。
   顺带确认此误伤面在他人行里也存在（BACKLOG:47 的 86、:48 的 23/62）——**属判据口径问题，交 owner**。

## 三个测试总数各不相同（须报告的判据面风险）

| 面 | 读数 |
|---|---|
| 本地钉版 moon `0.1.20260920`、`-j 1` | **822/822** |
| 干净树 nightly `0.1.20261012`（CI 面） | **807/807** |
| 文档自述 | **737/737**（+ BACKLOG:11 的 811） |

⇒ 「文档自述 ↔ 实测」这条守卫**必须锚在 CI 用的那个 moon 版本上**，否则本地读数与 CI 读数会各判一次红。
`check_test_sync` 的实测值来自 CI 传入的日志（`/tmp/moon_test.log`），这点是对的；
但**修文档时要写哪个数**，取决于接受哪个门为准 —— 这属口径裁决。

## 资源消耗

- WSL 隔离副本 4 次（预测 2 发 + 三红复核 + 判定性复核）；每次 `git archive HEAD` + `git init`；
- `moon test --target js` 共 3 次（干净树 2 + 本地权威 `-j 1` 1）；
- GitHub API 只读 6 次；本链零 `.mbt` 改动、零网络请求。

## 任务分配记录

- 指挥官亲自：把 CI 调用面搬下来逐条跑（不新造判据）→ 三红定因 → 自查出我自己两处 harness 缺陷
  → 修 ESC 损坏 → 报告。
- **未派子代理**：本链要害是"分清哪个红是我的 harness、哪个是产品、哪个是他人的 WIP"，
  每步都要归属判定，外包会引入误判。
- 边界：只动 `BACKLOG.md`（索引法，并发 32 行 WIP 原样保留）；`src/**`、`README.md`、
  `ARCHITECTURE.md`、`.github/**`（并发会话的 `continue-on-error` WIP）均未碰。

## 遗留风险

1. **守卫族的红是真红，且不为 Format 门所掩盖**：`check_badge` + `check_test_sync` 两者互锁
   （徽章与文档计数），修一处不改另一处会互相打架。**修法须 owner 定口径**（见上表）。
2. **`check_test_sync` 的 `N/N` 口径会误伤"局部计数"**：本轮我已在自己行避开，但他人行（BACKLOG:47/48）
   仍在被判。若认为该口径过宽，应在判据里加"仅当前后文出现『全量/总』等限定词才计"；
   若认为正确，则那些行也该改写 —— **两种都属裁决**。
3. **我第一次预测的"8/10 号红"是我割裂会话造成的假红**：已在本报告方法学节留档，
   免后来者按那个读数去修文档。
4. **`cleanup_artifacts --check` 在我这侧永远会红**（WSL 累积残留），故**不能**把它当本地判据；
   它只在 CI 干净检出面才有意义。建议后续本地实验改用一次性 box 目录。

## 后续建议

1. **给 CI 加一条"守卫族不被格式门 skip"的可见性检查**：J12 抓的是"恒假门"，
   但本轮的形状是"**真门 skip 掉后面的守卫族**"——两者都会让守卫族读数失真。
   可写一支只读脚本：读 ci.yml 的步序，报出"哪些步会因某步失败而 skip，且其中含 N 支守卫"。
2. **把本轮预测固化成常驻判据**：`scripts/blackbox/e2e_ci_js_track.py`（`git archive` → `git init`
   → 按 ci.yml 原序跑 → 汇总），让它替代"人肉预测"。本轮已证明这条 harness 能一次抓住 3 支红。
3. **测试计数单一真源**：`check_test_sync`（文档面）+ `check_badge`（徽章面）+ `check_tools_sync`（工具面）
   三支各自反解、各有口径；建议加一支"计数基线文件"（如 `scripts/counts.json`，由 CI 在跑完测试后生成），
   三支都读它 —— 否则永远要在"改文档还是改徽章"之间来回。
4. **本地实验一律用 box 目录**：本轮 ③ 的成因是我历次实验在 WSL `/root` 下累积 78 个 .db；
   建议所有临时实验脚本起手 `rm -rf <box> && mkdir`（本仓 e2e 已有此纪律，我也是照做的——问题在**上一轮**的残留没清）。

## 超额内容

- 顺带**自查并修掉自己上轮翻账引入的 ESC 控制字符损坏**（逐字节发现，非肉眼）；
- 顺带确认 `check_test_sync` 的过度捕获面在他人行也存在（BACKLOG:47/48），给 owner 一条可裁的口径问题；
- 顺带测出"三个不同测试总数"这一判据面风险（本地 822 / CI 807 / 文档 737）——这是修文档前必须先定的口径；
- 顺带把"守卫族因 Format skip 而从未执行"从推断变成**可复现的实测**（19 步 skip 清单在 CI 作业页可查）。

## 来源

- 预测原件：`temp/ci_js_predict2_direct.txt`（31 条调用面逐条 rc）、`temp/verify_three_reds_direct.txt`（三红定因）。
- 第一发（含 harness 缺陷）：`temp/ci_js_predict_direct.txt`、`temp/three_reds_direct.txt`。
- 本地权威读数：`moon test --target js -j 1` ⇒ `Total tests: 822, passed: 822, failed: 0`。
- CI 现状：`ci.yml #288` js,ubuntu —— `Migrate ✅ / Check(js) ✅ / HTTP contract self-proof ✅ /
  Format ✗ / 其后 19 步 skipped`；native ✅；windows ✅。
- ESC 损坏证据：`git cat-file blob HEAD:BACKLOG.md` 含 `b'\x1bngine_boundary_test.mbt:183'`。
- 修复提交：`fabf0e3`（ESC + 计数形状），双远端同步。
