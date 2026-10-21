# 2026-10-21 R46 汇报：`slave/docs/bug369-fixed-ledger` —— BUG-369 结案，抬头转 FIXED 与插件账本面同批（T0r28）

> 副机（slave-guard）自迭代第 R46 轮。上游：`memory/bugs.md` BUG-369（R41 立案 / R42–R45 逐份修真），
> R45 的 landed 段留下一句「建议转 FIXED，但抬头 token 本轮不动」，理由是账本状态位与插件投影互锁，必须同批改。
> 本轮一句话：**把那一格状态搬过去、小记补上、投影重生成，并用 14 支变异证明「只改一侧」真的会红——
> 搬数的过程中撞到摘要那句用了两个分母，新案 BUG-370 立案在账。**

## 结果摘要

1. **结案面（承重件）**：`memory/bugs.md` BUG-369 抬头 `[low] OPEN` → `[low] FIXED`，文末追加
   `### FIXED(2026-10-21 轮次 R46 / BUG-369)` 小记。小记按账本口径逐条对账：建议① 4 把尺 4/4 修真实
   （`check_template_ctrl` R42 / `check_mbti_sync` R43 / `check_pkg_imports` R44 / `simulate_head_commit` R45，每份都配**子进程** rc 格）、
   建议② 常驻判据 `check_exit_code_contract.py` 落地且棘轮 16 → 8 → 1 → **0**、建议③ 原文写作「若要固化成判据请另立一轮」故不构成未了项；
   并写明**结案口径只声明立案面清零**，末尾点名两项仍在账上的未做面（README 条目内联 `N=`、`emit_fatal` 共用件化）。
2. **投影同批**：`gen_plugins.py` 重生成四宿主 9 份带账本摘要的文件，摘要从
   `BUG-1~369 共 354 条入账：20 待修 / 313 已修 / 10 重复并入 / 9 误报` 迁到
   `BUG-1~370 共 355 条入账：20 待修 / 314 已修 / 10 重复并入 / 9 误报`（BUG-370 立案带来的 +1 见摘要第 4 条）；
   `check_plugin_sync.py` PASS（4 宿主 / 64 个生成文件 / 170 工具 / v0.3.9）。
3. **互锁三门被机器证明会响**（`temp/r46_ledger_mutation.py`，14 支全命中期望）：门①「标 FIXED 却无小记点名」/
   门②「被小记点名但状态不是 FIXED」/ 门③「DUPLICATE 必须带合法主编号」。关键三支：
   **M3** 小记抬头漏写「 / 」分隔 ⇒ 正则认不出 ⇒ 退化成门①（写了但形状错 ≠ 没写，这条把「手写小记」的文法依赖摆成可测面）；
   **M4** 编号多打一个字符 ⇒ 门①与门②**同时**响（真 FIXED 失去点名 + 不存在的编号被点名）⇒ 互锁门的价值正在于「写错时它响两声」；
   **E1** 账本两套话时 `measure()` 抛的 `SystemExit` **码真是 2**（R42–R45 那一族幻影承诺在生成器侧的对照实测）。
4. **本轮的新发现（不是本单的题，是搬数时撞的）→ 已立案 BUG-370**：摘要那一句用了**两个分母**——
   总数按 `## BUG-` 抬头**出现次数**（354），四态计数把状态装进**以编号为键的 dict**（352），差的 2 条来自
   BUG-183 / BUG-192 各被**两条不同缺陷**串号后的静默去重（183：`ops_selfdrive` 路径遍历 与 `star_gate:303` Int64 溢出 panic；
   192：`router_config` 4 处 `Double.to_int()` 无上界 与 `ops_cleanup` 丢弃错误详情）。现有门只考 `len(heads) != len(ids)`，
   串号时两侧各加 2 ⇒ **门绿着、对外文案自相矛盾**。定 medium：一条是「自述与分解不等」的失真面，一条是**两条安全类 high 缺陷共享追踪主键**；
   不到 high 的理由是当下没有消费者按这两个数字做自动决策（CI 与插件只印不解析）。三条出路写在账本里，本单**未实施**。
5. **本单刻意没越界**：T0r28 的边界写死「不改任何 `scripts/*.py` 判据逻辑、不改产品面」，所以 BUG-370 只立案与取证，
   判据门 / 台账重编号 / 写侧 `report_bug` 的 ID 分配都留给下一轮（其中写侧动 `.mbti` 接口面，按金条四属架构裁决）。
6. **文档面**：`scripts/README.md` 的 `gen_plugins.py` 条目补齐三门语义、rc=2 的实测出处与 BUG-370 的已知缺陷；
   `docs/agent-map.md` §五 新增一条律：**印在同一句里的「总数」与它的分解必须同集合同一次算出**（并记下去重发生在门之后等于没被考过）。
7. **台账**：`memory/2026-10-21.md` 新增 R46 段；`memory/bugs.md` BUG-369 转 FIXED + FIXED 小记 + BUG-370 新条目。

## 资源消耗

- tokens in / out：118000 / 13200；成本估 0.35（按 `execute` 上报口径）；时长估 540000 ms（含 `moon test` / `moon check` 全量实跑）。
- 模型：qoder-agent；执行者：slave-guard；验证者：commander（`T0r28`）。

## 任务分配记录

- `T0r28`（根任务，depth=3 / split_n=3，`temp/t28_publish.py` 发布并领取）：目标 = BUG-369 抬头转 FIXED 并与插件账本面同批；
  边界 = `memory/bugs.md` + `plugins/**`（只由 `gen_plugins.py` 写盘）+ 记忆/汇报/README/agent-map；**禁**改 `scripts/*.py` 与 `.mbt`/`.mbti`。
- 验收标准 6 条逐条实测（见「结果摘要」与「来源」）；交付物按 `execute` 的 DELIV 十一段回传。
- 未派子代理：本轮改动面是「一次状态迁移 + 一次重生成 + 一台变异台」，跨文件但同一批真源，拆开反而丢上下文。

## 遗留风险

1. **BUG-370 未修**：账本摘要的两个分母仍不等（现读 354 vs 352），串号的两条 high 缺陷仍共享编号 ⇒ 按编号回溯会拿到后写覆盖前写的那一条。
2. **手写小记的文法依赖**：`### FIXED(… / BUG-N)` 的「 / 」分隔与编号写法没有判据拦「形状写错」，M3 支证明形状错会**静默退化成门①那一条**
   （即：不会误放行，但报错文案会把「写了小记」显示成「没写」，读者容易改错方向）。
3. **投影面仍有 9 份文件参与 diff**：账本一改就要同批重生成，漏跑 `gen_plugins.py` 会被 `check_plugin_sync.py` 拦成 rc=1——
   这是好事，但 CI 目前把这一步挂在 native 轨，若某轮只改 `memory/` 而 CI 被 skip，就只剩本地电池兜底。
4. **`cleanup_artifacts` 预存红**（675 条残留：86 根 `.db` + 588 个 `temp/` + 1 个 `scripts/`）随取证增长，本单按声明期望命中，不追绝对数。
5. **R45 那笔重复任务 `T0r27` 仍在「已领取」**：需指挥官 `archive`（角色闸只认人类），副机不绕过。

## 后续建议

1. 下一轮（`T0r29` 起）优先做 BUG-370 的**判据侧最小修**：`ledger_status()` 加「编号唯一」门并点名重复条目，摘要总数与四态之和同集合化；
   同批做台账侧串号重编号（保留原时间与原文，小记点名「编号搬家、内容未改」）。
2. 写侧 `report_bug` 的 ID 分配（取现有最大编号 + 1）与白盒格「同一账本连报两条不同缺陷 ⇒ 编号必须不同」一起提，但先由指挥官定落点与是否进 `.mbti`。
3. 把 `gen_plugins.py --check` 与 `check_plugin_sync.py` 在 CI 里的挂点从 native 轨**复制到 JS 轨**（账本/文档类改动零 `.mbt`，不该依赖某一条轨道跑不跑）。
4. R45 留下的两项（README 条目内联 `N=`、`emit_fatal` 共用件化）与电池整面进 CI、`core.hooksPath` 接线，顺序仍排在 BUG-370 之后。

## 超额内容

- 一台 14 支变异台（`temp/r46_ledger_mutation.py`）与一支 diff 对账件（`temp/r46_diff_check.py`），题目只要求「重跑守卫确认无漂移」。
- **新案 BUG-370**（含四组串号条文的逐条取证、同族先例 BUG-185/186/217 的方向对照「那次假红、这次假绿」，以及三条出路）。
- `docs/agent-map.md` §五 一条新律；`scripts/README.md` 的 `gen_plugins.py` 条目从「用法 + 真源清单」扩到「三门 + rc 语义 + 已知缺陷在账」。

## 来源

- 真源读数：`python temp/r46_ledger_mutation.py` → 变异台读数 14/14 通过（rc=0）；
  `python scripts/gen_plugins.py` → 摘要 `BUG-1~370 共 355 条入账：20 / 314 / 10 / 9`；
  `python scripts/check_plugin_sync.py` → PASS 4 宿主 / 64 生成文件；
  `python scripts/check_exit_code_contract.py --selftest` → 28 格 rc=0；全量 → 判定面归零（上限 0）rc=0；
  `python scripts/check_doc_surface.py` / `check_scripts_index.py` / `check_pkg_imports.py` / `check_plan_landing.py --gate` / `check_mbti_sync.py` → 全绿；
  `python scripts/run_guards.py` → 格数 37 / 失败 0 / SKIP 0 / 缺执行面的尺 0；
  `moon test --target js -j 1` → `temp/pt28_raw.log` `Total tests: 1302, passed: 1302, failed: 0`；
  `moon check --target js --json` → `temp/chk48.json` 489 warning / 0 error、stderr 空，与 `temp/chk47.json` 双向差集为空（`temp/r46_diff_check.py` rc=0）。
- 上游依据：`memory/bugs.md` BUG-369（含 R42–R45 四段 landed 与本条 FIXED 小记）、BUG-370；`reports/2026-10-21-slave-simulate-head-fatal-rc-report.md`（R45 的「抬头 token 另项」出处）。

## 回填（提交面 / MR / FIST 终态）

- 待补：主件与收尾件 hash、分支推送回执、MR 入口、`T0r28` 终态。
