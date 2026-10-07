# 2026-10-07 · BUG-135：一条「落盘即假」的发布状态主张，和一支专门盯它的判据 J13

## 结果摘要

owner 问「还有什么要修的」→ 我给的第 1 条建议被批准执行。台账 OPEN 回到 **1 条**
（只剩 BUG-133，上游 `mizchi/sqlite@0.3.1` 的 native FFI）。

- 主张校正：`CHANGELOG.md` 定因节标题的「GitHub Release 未发布」是现在时断言，而权威面 published 时刻
  早于该节标题戳约 27 小时 ⇒ **写下那刻就是假的**。同节相邻的 BUG-128 那处标题戳早于 published，**当时是真话，保留**。
- 这一类做成常驻判据 **J13**：`release-fact` 权威标记 ↔ CHANGELOG 标题状态短语 ↔ 标题盖章戳 三者对表。
- 逐 job 结论（按 run 反解自 temp/b135_readback.txt）——CI（run 37561285645）：`check + test (js, ubuntu)`=success；`check + test (js, windows)`=success；`check + test (native, ubuntu)`=failure（红格 #8 Test (native)=failure）　FIST CI — Build + Test（run 37561285648）：`check + test (js, ubuntu)`=success；`check + test (native, ubuntu)`=failure（红格 #9 Test (native, j=1)=failure）

## 证据（全部 L3/L4）

| 判据 | 回执 |
|---|---|
| 权威读数 | 匿名 `GET /repos/vicTop-cw/FIST-Mbt/releases?per_page=100`（http=200）三发 release，逐资产行见 `temp/b135_release_evidence.txt` |
| 台账 | `### FIXED(2026-10-07T02:20:48Z / BUG-135)`（抬头状态计数 OPEN 1 / FIXED 120）|
| 自检 | `check_doc_surface.py --selftest` → `SELFTEST OK … J4/J6/J7/J8/J9/J10/J11/J12/J13 对合成违例均发红`（那份清单从自检正文反解）|
| 全量 | `check_doc_surface.py` → `PASS … J13 发布状态短语↔BACKLOG release-fact 对表` |
| 承重 | `temp/b135_j13_prove_out.txt`：`PROVE OK（4 格…）`，A 格逐字 `J13 标题自述 v0.3.5「GitHub Release 未发布」，但标题盖章戳 2026-10-01T03:20:18Z 晚于权威面 published 2026-09-30T00:03:17Z` |
| 守卫族 | `temp/b130_guards.log` 末行 `total=17 fails=0` |
| CI | 上表「逐 job 结论」那一发（js 臂全 success ⇒ 新判据在 CI 的文档面那一步真跑过：ci.yml 先 `--selftest` 再全量）|

## 分析

- **为什么"历史文件"里也会长出假话**：CHANGELOG 的每条小节标题都带 `（盖章 <ISO>）`，
  那句话的时态是现在时（"未发布"），而它的评价依赖一个**外部事实**（Release 是否存在）。
  豁免历史文件防止的是「事后改写叙述」，不是「让现在时断言自由漂移」——两者要分开，
  否则判据要么误伤历史、要么放过假话。J13 的做法是把时间戳变成可比对的量：**戳早于事实=当时的真话，戳晚于事实=落盘即假**。
- **为什么权威面要单独做标记**：BACKLOG 原文写「GitHub Release 出到与本条同一版本号」，
  人读得懂、机器猜不出。做成 `release-fact:` 标记后，"哪个版本、哪一刻、什么资产名、多少字节"都是一行可解析文本；
  判据同时校验标记自身的自洽（残缺 / 同版本两条 / 版本与资产名打架）——**标记也是主张，不是神谕**。
- **取样锚这一格的教训被复用了一次**：上一单的 A 格锚写 `HEAD`，被本单修复提交推过删除点而红；
  这次 A 格直接写死 `99c9e84` 并先自证「那棵树里确实存在戳晚于权威的标题」，取不到就 REFUSE。

## 缺口与风险

- **J13 只判 `GitHub Release 未发布` 这一个短语**：状态短语是自由文本，换成「Release 还没出」「暂无资产」就看不见。
  缓解是标记面本身可扩，但短语表若要做成清单，就得同样有"判据范围自述==实现"的门（J10 已经盯上界，不盯词汇表）。
- **release-fact 标记靠人工追加**：发新版本不补标记 ⇒ J13 对该版本不作数（不是误红，是**没读数**）。
  要闭死这条缝得让发布作业自己写标记，属 CI 面改动，本单不动。
- **BUG-133 仍 OPEN**：native 两臂照旧红在 `Test (native`，判据是抽检不是关闭条件。

## 资源消耗

- 守卫族 1 次（17 格）、`check_doc_surface` 自检+全量各 1 次（外加两条自纠各触发一次红）、承重证明 1 次、
  CI 轮询 1 轮（后台）、`gen_plugins.py` 1 次；`moon` 0 次（未动 `src/`，JS 全量沿用同批 573/573 的产物日志）。

## 任务分配记录

| 角色 | 做的事 |
|---|---|
| owner | 批准「按建议全部修复」（= 我方案里的第 1 条；第 2 条我自己判定不该做，第 3 条待裁决）|
| 指挥官 | 扫面发现 → 入账 → 改主张 → 建权威标记 → 写判据与自检 → 声明面搬家 → 盖章与记账 |
| 子代理 | 未派发（单线，无可切并行）|

## 后续建议

1. 若要把标记维护自动化：让 `release.yml` 发布成功后自己往 BACKLOG 追加 `release-fact` 行（共享 CI 面，需裁决）。
2. 状态短语词汇表若要扩（"暂无资产"/"未出"），同时要给这张表配 J10 型对表，否则又是一处无人认领的自述。

## 超额内容

- `release-fact` 标记覆盖 v0.3.3 / v0.3.4 / v0.3.5 三发（违例只有 1 处，但权威面只记一发等于下次仍要猜）。

## 来源

- 台账 `memory/bugs.md` BUG-135（本轮发现，`reported_by: fist-mbt-doc-surface-audit-b135`）。
- 裁决出处：owner 2026-10-07「按照你的建议全部修复」。
- 读数通道：GitHub Releases API（匿名只读，未使用任何 token 于该请求）。
