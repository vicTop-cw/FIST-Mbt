# 2026-10-13 · check_mbti_sync 判据增强报告（6 形状扩面 + 红文案出路分流）

## 结果摘要

**一句话**：本轮两次增强上轮刚落地的 `check_mbti_sync` 判据——
① 判据面从 `pub fn` 单形状扩到 **6 种形状**；② 红文案加**出路分流**，
区分「实现已在工作树、只是没提交」（出路 `git add`）与「真缺失」（出路补实现）。

| 项 | 读数 |
|---|---|
| `--selftest` | **12 格全过**（从 7 → 9 → 12） |
| 变异实测 | **6/6 被抓住**（两轮：先 5/5，扩面后 6/6） |
| 全量扫描面 | 540 条 `pub` 声明 / 6 种形状（原 440 条 / 1 形状） |
| 对当前 HEAD | rc=1 且**逐条给出正确出路**（4 个符号全报"已在工作树、只是没进跟踪面"） |

提交：`457a23d`（6 形状扩面）、`336d59b`（README 同步）、`e878432`（出路分流）、`6267f0a`（README 同步）。
均已推 origin + gitcode。

## 增强 ①：判据面扩到 6 种形状（`457a23d`）

**先预判零误报，再落地**（不凭感觉扩面）——用一次性脚本对 HEAD（坏）与工作树（健康）各跑一遍 6 形状：

| 形状 | HEAD 声明数 | 源里找不到 | 工作树（健康）找不到 |
|---|---|---|---|
| `fn` | 440 | **4**（真缺口） | **0** |
| `struct` | 57 | 0 | 0 |
| `enum` | 21 | 0 | 0 |
| `const` | 12 | 0 | 0 |
| `let` | 5 | 0 | 0 |
| `trait` | 2 | 0 | 0 |

⇒ 5 种新形状在健康树零误报才扩。重构为 `SHAPES` 表（形状 → `.mbti` 侧正则 + 源侧正则，
源侧允许 `pub` / `pub(all)` / 无前缀三种写法 —— **`pub(all)` 是扩面新引入的误报面**，
已用 selftest 格 `src-pub-all-recognized` + 变异实测双重锁住）。

## 增强 ②：红文案出路分流（`e878432`）

**动机（本会话真实踩过的坑）**：判据只读跟踪面 ⇒ 「工作树有实现、只是没提交」与「实现根本不存在」
两种情况**文案相同**，但出路截然不同。第 70 轮我就因此按"未实现"方向去找代码，
而实际工作树里那四个符号的定义都在。

**改法**：`judge()` 增加可选 `wt_defs`（取自工作树磁盘的定义集；只读不写、单文件读失败即跳过）；
给了它就按两条分支给出路：
- 符号在工作树里存在 ⇒ 「**实现已在工作树磁盘上、只是没进跟踪面** ⇒ 出路是 `git add` 该文件并提交（不是缺实现）」
- 工作树也没有 ⇒ 「跟踪面与工作树磁盘都找不到 ⇒ 出路是补实现（或从 `.mbti` 撤掉该声明）」

不给 `wt_defs` 时保持原文案（向后兼容，有专格锁定）。

**对当前 HEAD 实测**：rc=1，且 4 条违例**全报"已在工作树、只是没进跟踪面"**——与事实相符
（工作树里它们的定义都在），出路直接可执行。

## L4 实测（金条八）

**`--selftest` 12 格**（逐格实跑，清单从实现反解）：
1. clean-no-false-positive 2. synthetic-violation-caught 3. struct-violation-caught（扩展形状可红）
4. real-shape-4-symbols-caught（真实 4 符号必红）5. private-fn-not-considered
6. no-mbt-package-skipped 7. only-pub-fn-collected（`.mbti` 侧只收 pub 项）
8. src-pub-all-recognized（源侧认 `pub(all)`）9. missing-counted-in-n
10. hint-split-not-in-wt（工作树无 ⇒ 报补实现）11. hint-split-in-wt-uncommitted（工作树有 ⇒ 报 git add）
12. hint-compat-without-wt（不给 `wt_defs` ⇒ 向后兼容）

**变异实测 6/6 被抓住**（两轮累计）：

| # | 变异 | 抓它的格 |
|---|---|---|
| 1 | M1 判定恒不报红 | synthetic-violation-caught |
| 2 | 去掉缺包保护（`.get` 改直接下标） | no-mbt-package-skipped-judge-crashed（judge 抛 KeyError ⇒ 尺子坏了） |
| 3 | `.mbti` 侧正则放宽收内部 fn | only-pub-fn-collected |
| 4 | 缺额不计入 n | missing-counted-in-n |
| 5 | 源侧不认 `pub(all)` | src-pub-all-recognized |
| 6 | **出路分流被去掉 / 判反** | hint-split-not-in-wt |

> 第 2、3、4 格是首轮变异**抓不住**后补的；第 5、6 格分别是两轮扩面**新引入的误报/退化面**。
> 变异测试两轮共暴露 5 处覆盖缺口——**若只写自传不看变异，会交付一支"看起来有自证、实际有洞"的判据**。

## 资源消耗

- 判据脚本 328 行（从 222 行增至）；`--selftest` 跑 8 次（两轮变异 + 还原 + 初跑）；
- 可行性预判脚本 2 支（`temp/feasibility_mbti.py`、`temp/feasibility_shapes.py`）；
- 变异脚本 3 版（锚点随实现更新）；成对 `git archive` 树 1 棵；
- 守卫链复跑 3 轮；本链零 `.mbt` 源码改动、零网络请求（除 push）。

## 任务分配记录

- 指挥官亲自：预判零误报 → 扩面重构 → 出路分流设计 → 两轮 selftest/变异 → README 两次同步 → 报告。
- **未派子代理**：本链要害是"扩面口径取舍"与"变异暴露的覆盖缺口判断"（哪格该补），外包会引入误判。
- 边界：只改 `scripts/check_mbti_sync.py` 与 `scripts/README.md` 两文件；未改 `.mbt`、未代提交他人 WIP。

## 遗留风险

1. **判据仍只判"名字存在"，不判签名**：同名不同参（签名漂移）会漏——那属 `moon info` 职责。
2. **`wt_defs` 的读取面是"工作树磁盘"**：若某文件在磁盘上存在但**未跟踪且内容与跟踪版不同**，
   分流会走"已在工作树"分支（正确，因为它确实在工作树）；但这也意味着**判据的分流依赖磁盘状态**，
   在 clone 环境（无未提交文件）里会自然退化为"真缺失"文案——两条分支都有 selftest 格锁定。
3. **当前 HEAD 仍坏（20 errors）**：判据会红并给出正确出路（`git add` + 提交那 13 个未跟踪文件
   + `store.mbt`/`store_sqlite.mbt` 配套）；修复仍需该面 owner 执行。
4. **`check_doc_surface` 的 J14 仍红**（`cmd/cli/help_topics.mbt` 与 `ARCHITECTURE.md` 自述 146、
   真源 148）：那是并发会话新增工具后未同步的两面，**不属我的面**（两文件均为其 ` M`）。

## 后续建议

1. **给 `check_mbti_sync` 加"签名一致性"抽查**（可选）：本轮只判名字。若要判签名，
   可直接比对 `.mbti` 的签名行与源里同名 fn 的参数列表——但需先确认 `moon info` 的签名文本
   是否与源一致（可能被规范化，如 `Int`→`Int32` 的同类问题），**须先预判误报**（本轮已确立该做法）。
2. **把"出路分流"推广到其它判据**：本会话多支判据的红文案是"问题是什么"但没"出路往哪走"——
   例如 `check_pkg_imports` 的"该包目录没被 git add"已是好形状，可作模板。
3. **`Migrate` 步根因分流**（连续三轮已提）：现在 CI 第一处红已是 `MBTI sync guard`（精确点名），
   但 `Migrate` 自身的 `Failed to calculate build plan` 仍易误读；建议按错误文本分流。
4. **提交纪律**：本轮 HEAD 坏状态的正解就是"把工作树里已有的 13 个未跟踪 `.mbt` + store 层配套提交"——
   判据现在直接这么说了。

## 超额内容

- 顺带**用变异测试累计暴露并补齐 5 处覆盖缺口**（三轮扩面各引入新的误报/退化面，
  每次都靠变异发现）——这条方法学价值高于判据本身。
- 顺带**确立了"扩面前先预判零误报"的固定做法**（两轮预判：单形状→6 形状，
  都先对 HEAD 与工作树各跑一遍再决定）。
- 顺带**修掉自己两处操作失误**：重构中途留下的半成品（3 处引用已删 API）与 selftest 里的重复打印格
  ——都当场发现并修正，未带入提交。
- 顺带**把"判据只读跟踪面导致文案不指出路"这个本会话踩过的坑，变成判据的显式能力**。

## 来源

- 判据：`scripts/check_mbti_sync.py`（SHAPES 表 / collect_decls / collect_defs / judge(wt_defs) / selftest 12 格）。
- 预判原件：`temp/feasibility_mbti.py`（单形状）、`temp/feasibility_shapes.py`（6 形状），
  输出 `E:\temp\feas.txt` / `E:\temp\feasshapes.txt`。
- 变异原件：`temp/mutate_mbti.py`（3 版，输出 `E:\temp\mutmbti5.txt` / `mutmbti7.txt` / `mut72.txt`）。
- 全量读数：对 HEAD `FAIL … 扫 21 份 .mbti、540 条 pub 声明、6 种形状`，4 条 M1 全带"已在工作树"分流。
- 登记：`scripts/README.md` 的 `check_mbti_sync.py` 条目（12 格 / 6-6 变异 / 出路分流语义）。
- 提交：`457a23d` / `336d59b` / `e878432` / `6267f0a`。
