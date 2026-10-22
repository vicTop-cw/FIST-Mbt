# 2026-10-22 · 副机 R90 · TASK-009 写侧收口 report

## 结果摘要

风语者巡检器（`scripts/whisperer.py`，TASK-009 / R86 交付）的**默认写侧从未被真跑过**——R86 只跑过
`--scan-only`，本轮完成审计时把默认模式跑了一遍，当场三连崩。本轮把它收口到「六格自证 + 真入池 8 单」：

1. **参数漏传（TypeError）**：`write_yaml(key, title, problem, evidence, priority="P3")` 的三处调用点
   少传一个位置参数 ⇒ 默认模式一进写侧就崩、rc=1 裸退。
2. **幂等锚从未生效**：`yaml_exists()` 拿 `key` 全文子串搜，而 `key` 从没写进 yaml 正文（正文只有
   title/problem/evidence）⇒ 「同键只入池一次」是自我声明，实际每跑一拍就多一份重单。
   现改为 yaml 落一行机器锚 `dedupe_key: "<sha1(key)[:16]>"`，幂等只判这一行。
3. **中文键文件名塌陷**：`slug` 由 `[^a-z0-9]` 反解，整串中文键得空串 ⇒ `TASK-017-.yaml`。
   现退化为键哈希前 10 位。

结构性修法：入池面从 `main()` 抽成 `pool_findings(notes, governance, cells)`，selftest 直接调用它——
漏参数这类错只有「真调用一次」才抓得到。键另去掉 `gitcode/`/`origin/` 前缀，同一分支的两条镜面只入一单。

## 资源消耗

- 会话轮次：1 轮目标续推（本轮）；命令 8 发（read/edit/grep/selftest×3/真跑×2/守卫×2）。
- 网络：0（真跑用 `--no-fetch`，读本地已 fetch 的远端引用）。
- 耗时最重的一发是分支巡检真跑（49 个远端分支 × ahead/cherry/grep，约 90 s/拍）；
  这就是 R86 把逐文件 `git show` 换成单发 `git grep` 之后仍能接受的数量级。
- 改动面：`scripts/whisperer.py`（+约 60 行，写侧函数抽取与六格自证）、`scripts/README.md`（登记同步）、
  `docs/tasks/backlog/`（新增 8 份 yaml 产物）、`memory/2026-10-22.md`、本报告。未触碰 `.mbt`（本机 moonc
  `\\?\` ICE 面无关）。

## 任务分配记录

- 指挥官（本会话，副机）：完成审计 → 定位写侧三个真问题 → 直接收口（属单文件脚本级，按分流决策树归「轻任务」，不派子代理）。
- 下游（未派）：新入池的 TASK-010~015（6 个自带冲突标记的分支）P1 单，等 AtomCode/主机认领；
  副机不代解他人分支冲突标记。

## 遗留风险

1. **入池即事实**：TASK-010~015 是「分支带未解冲突标记」的机器判定，基线取 `gitcode/main`。若某分支已被
   上游废弃，这一单就是噪声——但它同时是「别 cherry-pick 它」的挡牌，宁滥勿缺。
2. **中文键文件名**：`TASK-017-882468bb41.yaml` 唯一但不可读。正解是给每条发现显式英文 slug，
   与 TASK-008（scripts 命名规范）同族，本轮不扩权。
3. **`--apply` 面仍无自证**：快进合入分支需要真远端 + 真工作树，六格自证覆盖不到；
   本轮未跑 `--apply`，该面的行为未验证。
4. **预存红（不代修）**：`fist-gate.py --selftest` 本机 rc=2，红在 G4 fmt（moonc `\\?\` ICE，
   rc=4294967295）与 build rc=1；这两格是观察格（只接受 rc∈{0,1}，CI ubuntu 读 0/1 即绿），
   本轮改动未触碰。

## 后续建议

- 把「默认模式必须跑一次」立为脚本类交付的验收格：只跑 `--selftest`/`--scan-only` 的交付，
  写侧等于没交（本轮三连崩就是这条缺口的账单）。
- `dedupe_key` 锚已经进 yaml，建议下游认领器（AtomCode/风语者人工面）读这一行而不是读标题，
  免得人工改标题把幂等打断。
- 若要把 8 单里的 P3 两条（治理散落 / 电池对表）并到 TASK-006/TASK-007 线上，由合并者裁决，本仓不自行合并。

## 超额内容

- 未在原任务范围内的两处：①`fist-gate.py` 的 README 登记里「`--selftest` 十七格（S1-S6）」是 R87 之后
  的滞后自述，已按实现改为「十九格（G1-G5 + S1-S8）」（J10 同形：自述 ≠ 实现）；
  ②镜面分支去重（同一分支在两个远端只入一单）超出 yaml 幂等的最小修法，但少了它就会一次拍子产出双倍重单。

## 来源

- 任务真源：`docs/tasks/backlog/TASK-009-whisperer-automation.yaml`（风语者巡检器）。
- 机理承接：TASK-001（`259b56a8` 冲突标记进 commit 的实证形状）、R86（whisperer 入仓 + `git grep` 单发扫描）、
  R87（REVERT-PATTERN）、R89（电池接线：whisperer/fist-gate 只进 `--selftest` 格）。
- 实测读数：本会话 `whisperer.py --selftest` rc=0（六格全 True）、默认 `--no-fetch` 首拍入池 8 单 rc=2、
  次拍「新 yaml：无」rc=2（notes 仍在）、`check_scripts_index.py` rc=0、
  `check_py_stdout_encoding.py --all` rc=0（87/87）、`fist-gate.py --selftest` 本机 rc=2（G4 预存红）。

## 追记（同轮）· 拉主仓看到的两件撞车

按「新分支前先看主仓是否需要覆盖本地」的律回看 `gitcode/main`：基点之后有 4 格，最新 9e0064a（v0.3.10）。
其中 b0693a6 是主机自己合并的 `scripts/whisperer.py`（Step 0-4 编排版，218 行），与副机 R86 的
TASK-009 交付**同名、同单号、不同实现**；它的 `step0_head_safety()` 在巡检拍里执行
`git checkout master` → `git reset --hard <gitcode/main>` → `git push --force HEAD:main HEAD:master`（两远端），
判据 `gc == og and gc != local` 把「本地 master 有未推提交」和「工作树脏」都读成篡改。
主机自身已被这一门开过火：9e0064a 的提交信息写着「风语者 HEAD 安全门手动回救」。

两件事都只入池不自行裁决（金条四：不可逆面留指挥官/用户）：
`docs/tasks/backlog/TASK-018-whisperer-head-gate-destructive.yaml`（P1，撤巡检面强推/改显式 --recover）、
`TASK-019-task009-whisperer-double-implementation.yaml`（P1，裁决 whisperer 真源，建议以 main 的编排为真源
并入副机的探测/入池面，或改名双活）。r85 的 MR 与 main 在 `scripts/whisperer.py` 上必撞冲突，
合并者需带着这两份 yaml 一起解。
