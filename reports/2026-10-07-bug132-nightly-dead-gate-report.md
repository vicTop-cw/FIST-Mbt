# 2026-10-07 · BUG-132 收口：删掉恒 skipped 的 nightly 空壳 + 把「恒假门」做成常驻判据 J12

## 结果摘要

owner 三选一里选 **c（删作业）** 已执行，并把这一类缺陷转成常驻判据。台账 OPEN 降到 **1 条**（只剩 BUG-133，上游依赖侧）。
关闭证据不是「测试通过」，而是**权威 CI 的 job 名单里那个名字消失**：

- 逐 job 结论：CI（run 37557287008）：`check + test (js, ubuntu)`=success；`check + test (js, windows)`=success；`check + test (native, ubuntu)`=failure（红格 #8 Test (native)=failure）　FIST CI — Build + Test（run 37557286720）：`check + test (js, ubuntu)`=success；`check + test (native, ubuntu)`=failure（红格 #9 Test (native, j=1)=failure）（条目原文那句「每次运行里的 `nightly self-check: skipped` 不是『定时轨没到点』，是『永不可能运行』」到此消解：现在不是它红不红的问题，而是那个会骗读数的绿灯位没了）。
- 取舍：a（改 `refs/heads/main` → `master`）救不活——那道 job `needs` 恒红的 native 臂，改完照旧 skipped；
  b（补 `schedule:` + 写实体巡检正文）是新造一条巡检轨，不在本单诉求；c 正是账本原文认定的最坏一档「留着恒 skipped 的空壳」的反面。

## 证据（全部 L3/L4，指得到盘上件）

| 判据 | 回执 |
|---|---|
| 台账翻面 | `memory/bugs.md`：`## BUG-132 … FIXED` + `### FIXED(2026-10-07T01:34:26Z / BUG-132)`；抬头计数 OPEN 1 / FIXED 119 |
| CI 权威读数 | `temp/b132_readback.txt`（run 37557287008『CI』、run 37557286720『FIST CI — Build + Test』，逐 job 结论见上）|
| J12 承重证明四格 | `temp/b132_j12_prove_out.txt`：`PROVE OK（4 格 + 现状面…）`；取样锚 `rev=d8c24eb` **反解自墓碑**；A 格逐字 `J12 .github/workflows/fist-ci.yml@d8c24eb:111 在 if: 守卫里钉了分支引用 ['refs/heads/main']`；扫描面 5 份 workflow |
| 守卫族 | `temp/b130_guards.log` 末行 `total=17 fails=0`（盖章 + 投影重生成之后重跑的那一发）|
| JS 全量无回归 | 本轮未动 `src/`，沿用同批 `temp/js_b134_take3.log` = 573/573（`check_badge` / `check_test_sync` 读的就是这份）|
| 投影（cl7） | `python scripts/gen_plugins.py` 回显 133 条入账 = 1 待修 / 119 已修 / 9 重复并入 / 4 误报；`check_plugin_sync` 逐字节 diff 通过 |

## 分析

- **J12 的口径选择**：不比对「本仓默认分支叫什么」，而是禁止在 `if:` 里钉分支引用。钉进去的分支名就是成因，
  比对分支名的判据会在下一次改名时**跟着一起错**；分支过滤交回 `on.push.branches`，`if:` 只留事件条件。
- **两条防自喂的构造**：扫描面从目录派生（手写清单必然落后），且**剔注释后才看**——本仓删完留的墓碑注释里正当引用着旧条件，
  不剔就会被自家注释喂针（R9 老坑同型，A/C 两格正是为这两条各留一把）。
- **「红给自己看」这一格是有价值的**：A 格在盖章前变红不是判据坏，是它的取样面（`HEAD`）被本单的修复提交推进过了删除点。
  改成从墓碑反解 rev 后，恢复指针与取样锚同源；再加一条取样面自检（代码面必须真有 refs/heads，否则 REFUSE），
  这一格就不会在将来悄悄退化成恒红或恒绿。

- **记账环节自己的检查连错两版**（不是产品问题，但值得进报告，因为它是同一个失效模式）：
  落盘后断言先要求三件产物都含盖章戳 ⇒ 红在当日日志（本就不该含），改成要求日志含本轮写盘瞬间的戳 ⇒
  幂等复跑必假红（那是上一轮 `now()` 的值）。规则「断言不许含会被重跑改变的量」这次落在我自己写的检查上；
  终版按件分派：CHANGELOG 与汇报比盖章戳（跨轮不变），当日日志只比日期，秒级戳由写入那一次的形状检查负责。

## 缺口与风险

- **BUG-133 仍 OPEN**（上游 `mizchi/sqlite@0.3.1` 的 native FFI 把 C 侧裸指针当 MoonBit 对象回传）：CI 两条 native 臂照旧红，
  `Native heap gate (BUG-133 探针当门)` 是抽检不是关闭条件。本仓无行动项，除非 owner 决定换依赖。
- **删掉的巡检位没有替代品**：那道 job 的正文本就是 `echo // TODO` 空壳，删掉不损失覆盖；但「native 侧真实自驱巡检」
  从此在仓里没有任何占位——将来要做就新立一单，别误读成「被本轮弄丢了」。
- **J12 只覆盖 `refs/heads/` 这一类恒假门**：`if:` 里钉死的仓库名、actor、路径前缀是同族别的形状，现在没人判。

## 资源消耗

- 盖章段新增执行：守卫族 2 次（17 格/次）、J12 承重证明 2 次（其中 1 次红 → 改取样锚 → 绿）、CI 轮询 1 轮（后台）、
  `gen_plugins.py` 1 次、`moon` 0 次（未动 `src/`）。

## 任务分配记录

| 角色 | 做的事 |
|---|---|
| owner | 三选一里裁 c（「按照你的建议做，修复掉已知的问题」= 批整个方案，含同轮加判据）|
| 指挥官（本会话） | 删作业 + 写墓碑、实现 J12 并接进 `--selftest`、三处声明面同步、盖章五道门、投影重生成、记账与本报告 |
| 子代理 | 本轮未派发（无可切的并行独立工作）|

## 后续建议

1. 撤 `FIST_GITHUB_TOKEN`（HKCU User 级，len=93，全程未回显、未进 argv）——读数已取完，凭据留在环境里没有受益方。
2. 若还要 native 侧真实巡检：新立一单写实体正文 + `schedule:`，别复用那个绿灯位。
3. BUG-133 的关闭条件是两格（抽检连发 0 崩溃 + 干净树全量通过），都在账本里；上游修好后 CI 自己恢复，不需要改 workflow。

## 超额内容

- 判据 J12 + 三处声明面同步 + `scripts/README.md` 记账——owner 批的是「删作业」，把这一类做成常驻判据是方案里的配套件。
- 盖章小记的逐 job 结论从读数反解（原本只列 job 名）：收口自查发现证据不足以独立复核，属于本单自己补齐的。

## 补记（盖章提交 `eb65298` / tag `b132-fixed-20261007` 自身的权威 CI）

盖章那一发只动了台账与投影，所以这一格考的是「**有没有把别的臂带崩**」，读数逐 job 抄自 `temp/b132_final_readback.txt`：

- CI（run 37558531687）：`check + test (js, ubuntu)`=success；`check + test (js, windows)`=success；`check + test (native, ubuntu)`=failure（红格 #8 Test (native)=failure）。FIST CI — Build + Test（run 37558531629）：`check + test (js, ubuntu)`=success；`check + test (native, ubuntu)`=failure（红格 #9 Test (native, j=1)=failure）。
- 三条自证都过了：job 名单里 `nightly` 命中 **0** 次（BUG-132 的关闭面在终态树上仍然成立）、
  js 两臂 3 条读数全 success、红格只有 #8 Test (native)=failure/#9 Test (native, j=1)=failure 即 BUG-133 那条 native 读面。
- 所以本轮终态：**台账 OPEN 只剩 BUG-133（上游 `mizchi/sqlite@0.3.1` 的 native FFI）**，
  本仓侧没有待修项；native 两臂继续由常驻门 `Native heap gate (BUG-133 探针当门)` 说话，不需要再改 workflow。

## 来源

- 账本条目 `memory/bugs.md` BUG-132（发现于 BUG-130 审计轮，`reported_by: fist-mbt-native-gate-audit-0d7b7115`）。
- 裁决出处：owner 2026-10-02 对话「三个选项的取舍在什么？按你的建议做」→「按照你的建议做，修复掉已知的问题」。
- 读数通道：GitHub Actions API（jobs 给步骤名与结论、`check-runs/<job_id>/annotations` 给 failure 级原文、`jobs/<id>/logs` 匿名 403）。
