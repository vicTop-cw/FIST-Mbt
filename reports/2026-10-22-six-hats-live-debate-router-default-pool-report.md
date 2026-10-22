# 2026-10-22 · 六顶帽真跑一次（模型路由默认池议题）+ 本机 P0-c 技能补装

分支：`fix/six-hats-live-debate-and-host-skill`（基点 = `gitcode/main` 现读 `3eec0901`，开工前 fetch、开工时 0/0 对齐）
边界：**不改 `src/`、不改 `scripts/`、不改他人文档**。全部动作 = ①一次进程内 MCP 调用链 ②把已有投影装进宿主技能目录 ③本报告 + 当日日志一条。

---

## 结果摘要

两件都落了，且都以实测读数为凭，不靠自述：

1. **六帽真跑**：在**同一个 `serve` 进程**内跑完 `hat_list → debate_convene → debate_register ×3 → debate_verdict`，拿到机器裁决
   `session_id=debate-20261022-001 / total=3 / agree=1 / rate=0.3333333333333333 / threshold=0.6 / pass=false / terminal_gate=user`。
   议题 = `docs/improvement-plan-20261010.md` §3.1 的字面那条（把默认免费池预置成 `[anon-opencode, eac, kilo]`，并把 atomcode 执行器与免费池路由打通）。
   **帽子结论：两顶 reject ⇒ 不照字面做**；终审门照工具自述留在用户（本单不代拍板）。
2. **本机 P0-c 补齐**：把仓库投影 `plugins/deepseek-harness/skills/fist-mbt/` 逐字节装进 `~/.agents/skills/fist-mbt/`
   （**11/11 文件 sha256 相同，0 缺失 0 多余**），再调 `evolve_asset_register` 登记一条 `[asset]fist-mbt-host-skill`（DGM `count 3 → 4`）。
   交付判据不是「我装了」而是「用的时候真拿得到」：**本会话的可用技能列表里 `fist-mbt` 已出现**（计划 §7 P0-c 交付栏「用户用 fist-mbt 时真的拿到 skill」在本机成立）。

门禁（合入硬门）：`moon check --target js` = **`ran 31 tasks, now up to date (508 warnings, 0 errors)`**。本单零 `.mbt` 改动 ⇒ `moon fmt` 面为空集；whisperer `--fast` 读数见「遗留风险」第 6 条（那条标签本身不可信，已点名）。

---

## 一、机器读数（逐字摘录驱动 stdout）

```
tools_total=170  missing=[]
schema debate_convene  : required=['topic']                              props=['hats','threshold','topic']
schema debate_register : required=['session_id','hat_id','verdict','evidence']
schema evolve_asset_register : required=['source','note','code']         props=['code','note','score','source']
--- hat_list            [OK]  6 顶（White/Red/Black/Yellow/Green/Blue），默认三帽 [white,black,yellow]
--- DGM-snapshot-before [OK]  {"count":3, ["[asset]wireup-test","[asset]wireup-none","[asset]code-review"]}
--- debate_convene      [OK]  session_id=debate-20261022-001  threshold=0.6  note="进程内会话态，重启即失；跨进程不可见"
--- register:white      [OK]  registered=1  summary={total:1, agree:1, rate:1, pass:true}
--- register:black      [OK]  registered=2  summary={total:2, agree:1, rate:0.5, pass:false}
--- register:yellow     [OK]  registered=3  summary={total:3, agree:1, rate:0.3333333333333333, pass:false}
--- debate_verdict      [OK]  见下
--- asset-register      [OK]  id=asset-fist-mbt-host-skill-2026-10-22T06:58:04Z  goal=[asset]fist-mbt-host-skill  score=0  portable_candidates=[]
--- DGM-snapshot-after  [OK]  {"count":4, ...}
done rc=1
```

```json
{
 "session_id": "debate-20261022-001",
 "summary": { "total": 3, "agree": 1, "rate": 0.3333333333333333, "threshold": 0.6, "pass": false },
 "terminal_gate": "user",
 "anti_drift": [ "evolve_critic", "goal_drift_check"
]
}
```

两处必须一起读的失败/噪声（不藏）：

- **第一次 `debate_convene` 直接 `-32602 inputSchema mismatch at /threshold (type)`** —— 我把 `threshold` 传成字符串 `"0.6"`，schema 是 `number_prop`（`src/server/server.mbt:7858`）。这是**调用面错误**，不是工具缺陷；改成数字后一次通过。附带结论：`debate_*` 的入参校验是**前置且拒绝的**（坏类型不会静默回退默认值），这一格形状对无人值守派发是有用的。
- **`done rc=1` 是 `proc.terminate()` 的退出码**（node 被杀），不是业务失败。判绿只看上面三段 JSON 是否齐——拿 rc 判绿的脚本在这一格会把成功读成失败（同 BUG-142 族）。

---

## 二、三帽判决（evidence 逐字）

| 帽 | verdict | evidence（原文摘录，全部 file:line 为实测锚点） |
|---|---|---|
| White | `pass` | 事实足以支撑裁决：默认免费池已硬编码 8 个真 OFM id（`src/router/model_router.mbt:368-413`，注释 `:365-367` 点名 2026-10-12 实机 `GET /models` 取得）；§3.1 的 `anon-opencode/eac/kilo` 三串在 `src/` 零命中（只在 `docs/improvement-plan-20261010.md:74` 与两份报告里）；`RouterConfig` 无多池结构、`window_seconds` 全局单值（`model_router.mbt:334-349`）；atomcode 依 `model_router_ops.mbt:1000` 被显式排除在路由外（BUG-238）。 |
| Black | `reject` | 三条硬风险：(1) 改默认值必破 `cfg_ofm_6`（`router_config_wbtest.mbt:116-143` 逐条点名 8 个 ID + lane）与 `mo_4` / `length==8` 两处锁；(2) 路由不校验上游模型存在性（`available:true` 在池非空即给，`model_router.mbt:815/898/920`），漂移名会被自信 pick 并记账，比显式 `ok=false` 更坏；(3) `router_state.mbt:192-202` 状态文件优先 ⇒ 新默认对存量 ns 静默 no-op、新 ns 生效，同仓两形状。另 BUG-238（`memory/bugs.md:4272-4290`，FIXED 2026-10-16T07:31Z）实测 `model=ling-3.1-flash-free` → atomcode HTTP 400 Unsupported model，打通=撤销已定案裁决；`check_model_auth_no_key.py:78,230` 只判凭据值形状，无任何判据校验默认池与上游 `/models` 一致性。 |
| Yellow | `reject` | 收益面已被吃掉一半、另一半是负的：新用户无状态文件时 `router_state.mbt:160-163` 与 `router_config.mbt:213-219` 都落默认池 ⇒ 拿得到模型名，不空池不失败，「预置默认清单」这一格**成本 0 收益 0**；atomcode 打通是**反向收益**（BUG-238 的修复正是让 atomcode 跳过路由 + `cli_argv.mbt:96-104` 空模型省略 `--model`，锁 `ca_8`）；端点不预置是刻意设计（`model_router.mbt:361-363`「绝不硬编码看起来能用的端点」，未配置在 `model_router_ops.mbt:786-792` 显式拒绝），且 `reports/2026-10-10-five-directions-closure-report.md:54` 已记 owner 裁决「真值 provider 专属，属部署者责任，本仓不做」。 |

> evidence 由本轮派出的证据采集子代理逐文件取回，我复核过其中 4 处锚点在现主干仍然成立（`model_router.mbt:368-413` 的 8 个 id、`model_router_ops.mbt:1000` 的 atomcode 例外、`memory/bugs.md:4272` 的 BUG-238 抬头、`router_config_wbtest.mbt:116-143` 的 `cfg_ofm_6`）。

---

## 三、这条 rate 不能当「共识度」读（诚实标注 · 本单最有价值的一格）

`debate_verdict` 的实现是 `rate = agree / total`，`agree` 只数 `verdict == "pass"` 的帽子（`src/ops/ops_hats.mbt:209-246`，注释 `:226` 明写「abstain 与 reject 都不算达成一致」）。但本轮**三帽被问的不是同一个问题**：

- White 那一顶我拿到的问句是「**事实是否足以支撑裁决**」——它答 `pass` 说的是「证据够了」；
- Black / Yellow 的问句是「**该不该照 §3.1 字面做**」——它们答 `reject` 说的是「不该做」。

于是 `rate=0.33 / pass=false` 这个数**不等于**「1/3 的视角支持做」，它只是「唯一那顶被问事实的帽子说够了」被机械地平均进了价值判断。
读数本身没错，**错在把混合语义的 rate 当共识度**——如果指挥官据此宣布「多数否决」，那是工具没说的话被替它说了。两条出路（交回 owner，见后续建议 3）：议题模板里对每帽统一问句；或者把 White 的「事实充分」单设字段、不进 `rate`。

另两条机械事实：

- **会话态是进程内的**：`debate_convene` 回执自带 `note="进程内会话态，重启即失；跨进程不可见"`。⇒ 拆成 4 次 CLI 调用**必然拿不到 session**（这不是 bug，是设计，但它让「用 CLI 跑辩论」这条路上所有尝试都长得像工具坏了）。本单唯一的正确用法是把 5 步压进 1 个 `serve` 进程。
- **`anti_drift=["evolve_critic","goal_drift_check"]` 是清单不是动作**：本轮没有任何帽子结论真的过 `evolve_critic`（它只在 `task_challenge` 发挑战题时挡）。计划 §4.1 承诺的「防课程漂移」在工具面上仍是**挂名状态**。

---

## 四、P0-c 本机面实况（为什么只做 1 条注册，不做 8 条）

装进宿主的 11 份正文（`~/.agents/skills/fist-mbt/`，逐字节 = 仓库投影）：

```
SKILL.md 9988B 08d74d1966872e32 · references/dag-operations.md · fist-methodology.md · known-issues.md
· mcp-tools.md · moonbit-idioms.md · omega-verification.md · seven-modes.md · storage.md
· task-state-machine.md · testing.md            （installed=11 projection=11 sha256_mismatch=0）
投影头（SKILL.md 第 6 行）：host=deepseek-harness tools=170 version=0.3.10
```

本机宿主技能目录普查（这条决定了我**不照抄主机的注册清单**）：

| 目录 | 现状 |
|---|---|
| `~/.agents/skills` | 1 项 = `fist-mbt`（本单装的）。计划 §5.1 那句「实测 `~/.agents/skills` = 322 目录」是**主机侧读数**，副机为 1 |
| `~/.codeartsdoer/skills` | 3 项 CodeArts 自带（`codebase-crossrepo-pipeline` / `repo-simple-wiki` / `repo-simple-wiki-update`）+ `UserSkillStatus.txt`，与 DGM 生态 skill 不同名 |
| `~/.claude/skills`、`~/.atomcode/skills`、`~/.codex/skills`、`~/.qoder/skills` | **均不存在** |

⇒ 把主机那批 `test-driven-development` / `superpowers` / `grill-me` 类资产照抄进副机 DGM，等于**在档案库里登记本机不存在的路径**；而计划 §6.2 里专门用来抓这种幻影的 `check_skill_inject` **还没落**（本轮 grep：`scripts/` 无同名判据）。所以我宁缺不造：本机只登记 1 条真实存在、且路径当场核对过的资产。
覆盖其余三宿主 = 要新建用户主目录，属越界动作，本单不做，交回 owner。

---

## 五、计划/文档与代码的错位（errata，只点名，不改他人文档）

1. `docs/improvement-plan-20261010.md:74` 的 `[anon-opencode, eac, kilo]` 三串在 `src/` **零命中**；默认免费池早已硬编码 8 个真 OFM id（`src/router/model_router.mbt:368-413`）。⇒ §3.1 第一条的真价值只剩「**多池 + 每池独立 `limit`/`window_seconds**`」（`RouterConfig` 现无多池结构、`window_seconds` 全局单值 `:334-349`），模型名清单本身是陈旧文档。
2. `docs/model-router-skill.md:26` 仍列 `AtomGit-qwen3.8-27b`（已不在默认池）；`:48` 写 `aider | atomcode`，而 AGENTS.md 自述 `aider | atomcode | ofm`。
3. 「atomcode 与免费池打通」是**反向收益**：BUG-238（`memory/bugs.md:4272`，抬头 `## BUG-238 [2026-10-16T07:16:10Z] [high] FIXED`，小记 `:4289`）的修复方向正是让 atomcode 跳过路由。做它 = 撤销已定案裁决，需要 owner 明确推翻而不是「按计划补上」。
4. 改默认值必破两处锁：`router_config_wbtest.mbt:116-143`（`cfg_ofm_6` 逐条点名 8 个 ID + lane）与 `mo_4` / `length==8`。
5. `router_state.mbt:192-202` 状态文件优先 ⇒ 新默认值对存量 ns 静默 no-op、只对新 ns 生效（同仓两形状，任何「改了没生效」的排查都会在这里绕圈）。
6. 路由不校验上游模型存在性（`model_router.mbt:815/898/920`：池非空即 `available:true`）⇒ 漂移名会被自信地 pick 并记账，**比显式 `ok=false` 更坏**。本议题里唯一「做了严格更差」的机理。
7. **AGENTS.md 的六帽表有三行描述与真源不符**（新发现，非本单引入）：`AGENTS.md:375-377` 把 `hat_run` / `hat_debate` / `hat_merge` 写成「register 进同一 session」「一步到底 convene+register」，而真源 `src/server/hat_hexa_tools.mbt:1-19` 自述是 **HexaMind 六元 R119、纯计算只读、无进程内会话态、无网络**，`hat_run` 的入参是 `config_json`（`topic/hats/hat_policy`），根本没有 `session_id`。两者是**同名不同族**：会话族在 `src/ops/ops_hats.mbt` + `server.mbt:7831/7850/7907/…`，六元族在 `src/hat/` + `hat_hexa_tools.mbt`（接线 `server.mbt:8088 s1 = embed_hexa_tools(s1)`）。工具都在（`tools_total=170`），**描述把两条族串成了一条**。

---

## 资源消耗

- 亲自执行：`node serve` 起停 2 次（1 次失败于 `-32602`、1 次全程通过）、`tools/list` 1 次、`tools/call` 7 次（`hat_list` / `evolve_snapshot` ×2 / `debate_convene` / `debate_register` ×3 / `evolve_asset_register`）—— 均在同一进程内。
- `moon check --target js` 1 次（基线，31 tasks / 508 warnings / 0 errors）；sha256 普查 22 份文件（11 安装 + 11 投影）；宿主目录普查 6 个。
- 产物：1 份报告 + 当日日志 1 节 + 1 条 DGM 资产 + 1 个仓外驱动脚本与 1 份判决 JSON（不进仓库跟踪面）。
- 未做：全量 `moon test --target js`（纯文档单，基线 0 errors 已取，见遗留风险 6）。

## 任务分配记录

| 分配 | 内容 | 回传 | 终审 |
|---|---|---|---|
| 证据采集子代理（路由面） | 默认池真源、多池缺口、atomcode 接线、锁面 | `model_router.mbt:368-413/334-349/815`、`model_router_ops.mbt:1000`、`router_state.mbt:160-163/192-202`、`router_config_wbtest.mbt:116-143`、`cli_argv.mbt:96-104` | 通过（4 处锚点我当场复核） |
| 证据采集子代理（skill/投影面） | `gen_plugins` 投影头、宿主技能目录、计划 §5.1/§7 口径 | 投影正文 11 份 + P0-c 交付栏原文 | 通过 |
| 本单亲自 | 驱动脚本、三帽 JSON 落盘、装机、注册、报告/日志、门禁 | 本报告 | — |

## 遗留风险

1. `docs/debate-skill.md`（计划 §4.3 cl3）**没落** ⇒ 「六帽必须同进程」这条唯一正确用法只存在于本报告的第三节，下一个人还会先撞 `-32602` 或拿不到 session。
2. `check_skill_inject`（计划 §6.2 候选）未落 ⇒ 幻影资产无人抓。本单那条路径当场核过是真的，但**下一次登记不存在路径的动作没有任何判据会红**。
3. `check_host_installable`（计划 §6.2 候选）未落 ⇒ 「投影 == 装得上」只能靠我这次的手工 sha256 比对，不可持续；四宿主面只有 deepseek-harness 一份被证过。
4. rate 语义混合（第三节）：把 `pass=false` 读成「多数否决」是**本工具当前的可读性陷阱**，不是缺陷被修掉了。
5. DGM 现在 4 条资产里 2 条（`wireup-test` / `wireup-none`）的 `code` 指向 `https://example.invalid/…`，是既往接线测试残留，与我这条真实资产混在同一检索面；`dead_ends` 列表也把它们列进去了。
6. 本机 whisperer `--fast` 的「三端一致」标签仍不可信（只读本地陈旧 `origin/main`，不比对 GitHub）⇒ 我按硬规则跑了它，但不拿它的绿灯当合入依据；主干 `0 errors` 才是。
7. 本单未跑 `moon test --target js`，若 owner 要测试面读数需另跑一次。

## 后续建议

1. **交回用户拍板**（`terminal_gate=user`）：把 §3.1 拆两半——① 模型名清单**作废**（改文档，不动代码）；② 「多池 + 每池 `limit`/`window_seconds`」**留作 P1-a 真需求**；③ atomcode↔免费池**不做**，除非 owner 明确推翻 BUG-238。
2. 修 `docs/improvement-plan-20261010.md:74` 与 `docs/model-router-skill.md:26/:48` 三处陈旧自述，并把第五节第 7 条的 AGENTS.md 三行改回两族分述——**都属他人/主线文档，等 owner 点头再动**。
3. 议题模板里对每帽**统一问句**（或把 White 的「事实充分」移出 `rate`），否则 `debate_verdict` 的数值永远不可比。
4. 补 `docs/debate-skill.md` 时应把三条机械事实写进去：同进程约束、`threshold` 必须是 number、终止 rc≠业务 rc。
5. `hat_debate` / `hat_run` / `hat_merge`（六元族）与 `debate_*`（会话族）**同名同表不同实现**，值得立一单把两条族的边界写清楚——本单只点名，不合并。
6. 若要覆盖四宿主 P0-c，需要 owner 授权在副机新建 `~/.claude/skills` 等目录；我不动用户主目录之外的东西。

## 超额内容

- 顺手取了 `moon check --target js` 基线（本单不强制，但硬规则 3 要合入门禁读数）。
- 普查了 6 个宿主技能目录（为「不能照抄主机注册」拿现读证据，计划里没有这一格）。
- 发现并点名了 AGENTS.md 六帽表的两族混写（第五节第 7 条），**未修**。
- 未做：没有改 `src/`、没有改 `docs/improvement-plan-20261010.md`、没有新建其他宿主目录、没有代开 MR。

## 来源

- 驱动与判决：`C:\Users\Administrator\hat_debate_driver.py`（仓外脚手架，刻意不进 `scripts/` ⇒ 不让 `check_scripts_index` 多认领一件）、`C:\Users\Administrator\hat_verdicts.json`
- 议题真源：`docs/improvement-plan-20261010.md` §3.1（`:72-76`）/ §4.1（`:101-109`）/ §5.1-5.2（`:122-129`）/ §6.2（`:153-156`）/ §7（`:164-166`）
- 代码真源：`src/ops/ops_hats.mbt`、`src/server/server.mbt:7831/7850/7907/8088`、`src/server/hat_hexa_tools.mbt:1-30`、`src/router/model_router.mbt:334-349/361-363/368-413/815`、`src/router/router_config.mbt:213-219`、`src/router/router_state.mbt:160-163/192-202`、`src/server/model_router_ops.mbt:786-792/1000`、`src/executor/cli_argv.mbt:96-104`、`src/router/router_config_wbtest.mbt:116-143`
- 账本：`memory/bugs.md:4272`（BUG-238 FIXED 抬头）/ `:4289`（盖章小记）
- 前序：`reports/2026-10-11-plan-v3-gap-audit-report.md`、`reports/2026-10-10-five-directions-closure-report.md:54`、`reports/2026-10-22-merge-backlog-clear-report.md`
- 投影真源：`plugins/deepseek-harness/skills/fist-mbt/`（11 份，`gen_plugins.py` 生成，禁手改）
