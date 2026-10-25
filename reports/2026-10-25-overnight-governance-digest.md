# 一夜治理总报告（Overnight Governance Digest）· 2026-10-25

> **这份文件的唯一用途：让下一个人 / 下一次会话，在 15 分钟内读懂这一夜发生了什么、立了什么规矩、还欠什么。**
> 40 条判例散在 4 处（`reports/` 多份 + `AI-DEVELOPMENT-STANDARD.md` §4.1 + `AGENTS.md` 3 段 + `docs/probe-authoring.md`），
> 此前**没人能一次读完**。本文件是那份索引。读完本页，请直接跳到 §6「仍然待办」。

---

## 0. 一句话结论

**这一夜做的不是「加功能」，是「把判据说的话和现实对账」** ——
期间抓到的每一条，形状都是同一个：**判据绿着，但它绿的理由是假的。**

---

## 1. 盘面：一夜之间的数字

| 项 | 之前 | 之后 | 处置人 |
|---|---|---|---|
| 非主 worktree | 54 | **14**（目标 0） | α |
| `gitcode` 分支 | 154 | **91** | α/各司令 |
| 判例（编号） | 12 | **40**（本册整理） | 全员 + 统帅 |
| 守卫尺（`check_*.py` 计入电池宇宙） | 113 | **119** | 各司令 |
| JS 测试总数 | 1455 | **1457** | γ（F3 修 + 2 锁） |
| 提交数（本夜） | — | **约 44 笔** | 全员 |
| `origin` 分支 | 53 | **53（未动，见 §5）** | γ（阻塞） |
| `temp/` | 284 MB | 待删 | δ |
| 非标准顶层目录 | 13 个 / 48 MB | 待归档 | δ |
| 兄弟目录 | 34 个 | 待迁出 | β |

**判据面规模（现读 `run_guards --list`）**：
`尺 119 把 / CI 面 45 / 电池面 78 / 缺执行面 0 / 门禁尺 86 / 豁免 28 / 未归类 7`

---

## 2. 这一夜的六条主线（按「发现顺序」而非重要性）

### 2.1 合并面：分支清理与「基线倒退」
- 一批 `slave/*` 分支的顶树是**旧基线**，整支 merge = 拿旧树覆盖 main。
  判据：`git diff --name-status HEAD <branch> --diff-filter=D` 列出 main 已有文件 ⇒ 整支 merge 即倒退。
- **4 支「疑似已合」分支核验 → 全部 DROP**（`r152`/`r156`/`r160`/`battery-tree-state-cell`），
  依据是「代码增量已在 main + 残余全是基线倒退」，详见 `reports/2026-10-24-merge-precedents.md`。

### 2.2 sync workflow：静默吞掉 102 支
- `.github/workflows/sync-from-gitcode.yml` 的 `git push … || echo "failed"` 让 rc 恒 0
  ⇒ 102 支没推上去而 workflow **从没红过**。
- 修法：逐支计数 + `::notice::branch sync: OK=N FAIL=M` + `::warning::failed branches: …`，
  **不改 rc 语义**（失败仍不阻断，但读数可见）。
- 配 `check_sync_workflow_reports_failures.py`（S1–S5 五条判据）+ 本地真跑模拟
  `.github/workflows/sync-from-gitcode.simulate.sh`（从 workflow 原样抽段 + 假 bare 远端，16 格）。

### 2.3 Omega 门禁：一条在线缺陷（F3）
- `decompose_rec` 里子任务开关取自**本次入参**而非**父任务状态** ⇒
  父开着 `[omega:required]`、调用方不传参时，**整棵子树门禁静默失效**。
- 修法：`let omega_on = omega_strong_verify || omega_enabled(parent)`（复用单一真源，不引第 5 种判法）。
- 两条锁 wb1/wb2；**变异实测**：改回旧写法 ⇒ wb1 红（206/207），改回 ⇒ 207/207。

### 2.4 假绿三连（本轮最值钱的部分）

| 假绿 | 形状 | 修法 |
|---|---|---|
| `check_badge` 比旧快照 | README 1455 == 快照 1455 ⇒ PASS，而现实 1457 | 快照带**源码面锚点**，过期 ⇒ rc=2；`--fresh` 判前真跑 |
| `check_test_sync` 同病 | 同上（两把尺吃同一份 `temp/pt27.log`） | 接同一份 `_badge_anchor.py` |
| `check_selftest_call_face` 的 E3 格串味 | 加了锚点前置后，E3 静默改考锚点面 | 夹具补锚点 |

### 2.5 门禁 FATAL 两次（都是「往 `scripts/` 加 `.py` 没同批给执行面」）
- `tmp_audit_preservation_scan.py`（tidy）/ `commit_scoped.sh`（α）/ `badge_anchor.py`（γ）
- 后果统一：`check_battery_count_doc` **FATAL，全仓门禁停摆**。
- 已立纪律（`AGENTS.md`）+ 惯例（共享模块以 `_` 开头自动豁免）。

### 2.6 `git mv` 静默失效（判例-38）
- `core.ignorecase=true` 的仓里，`git mv bad.py _bad.py` **退出码 0 但旧路径仍在跟踪面**。
- 我自己踩的，**我自曝的**：功能没坏（import 都指新名），但留了 252 行死代码在跟踪面。
- 复核铁律：**rename 后一律 `git ls-files <旧名>`，不看 `status` 也不看 `diff`**。

---

## 3. 40 条判例 · 一句话索引

> **读法**：前 12 条与 16 条有专册；13~15 是**故意留空的编号**（属别的车道）；
> 17~24、28、32~33、35~37、40 尚未逐条落文，只在本册给出一句话。
> **索引维护纪律：新增判例时同一笔补本表；表里列了而册内没有定义 ⇒ 索引腐坏（判例-5 同族）。**

### 3.1 合并与 git 操作（1–14）

| 编号 | 一句话 | 出处 |
|---|---|---|
| 判例-1 | `diff-filter=D` 列出 main 已有文件 ⇒ 分支顶树是旧基线，整支 merge = 拿旧树覆盖 | `merge-precedents.md` §判例-1 |
| 判例-2 | 合入前必须 `isolated_git_env()` + detached HEAD 预演 | `merge-precedents.md` §判例-2 |
| 判例-3 | **改名不是接线**（判据存在但没接线 = 没判据） | `merge-precedents.md` §判例-3 |
| 判例-4 | 哨兵值必须证明不在合法值域内 | `merge-precedents.md` §判例-4 |
| 判例-5 | 判据存在但没接线 = 等于没判据（与 3 同族，本册多处引用） | `merge-precedents.md` §判例-5 |
| 判例-6 | 删除一个跟踪件 ⇒ 所有历史分支都「新增」它（规模级假阳性） | `merge-precedents.md` §判例-6 |
| 判例-7 | **跳号（故意留空，勿补）** | `merge-precedents.md` §判例-7 |
| 判例-8 | `--filter=A` 非空只是线索：删除件 / 重命名件 / 垃圾件三源假阳 | `asset-preservation-proof.md` §2.6.5 |
| 判例-9 | `\|\| echo` 静默失败让「守恒」失效（吞 102 支，workflow 仍绿） | `asset-preservation-proof.md` §6.2 · `check_sync_workflow_reports_failures.py` |
| 判例-10 | **空读数 ≠ 无：判 rc 不判输出**（`git grep -c` 零命中无输出） | `asset-preservation-proof.md` §2.6.1 |
| 判例-10b | `git diff --numstat` 读的是「工作树 vs index」，**不含 index** | `asset-preservation-proof.md` §2.6.6 |
| 判例-10c | `numstat` 的 `0 0` 有两种含义：无差异 / 冲突态无法计算 | `asset-preservation-proof.md` §2.6.6 |
| 判例-11 | `--name-only` 只证明「在暂存面」，不证明「是我造的」（逐条核对来源）；**最终形态 = `git commit -- <路径>`** | `verify-guards-completeness.md` · `AGENTS.md` |
| 判例-12 | `--not` 是切换开关不是逐项限定符；`--not --all` 在 detached HEAD 上漏判 | `scripts/README.md`（`check_worktree_hygiene.py`） |
| 判例-13~15 | **未归册**（属其他车道，空位保留，勿补编号） | — |
| 判例-14 | **filter-repo 后 `merge-base --is-ancestor` 不可靠**（无共同祖先 ⇒ 祖先判据恒假）⇒ 用「新增文件/内容面」判 | `asset-preservation-proof.md` §2.6 |

### 3.2 判据的面（16–23）

| 编号 | 一句话 | 出处 |
|---|---|---|
| 判例-16 | **判据面 < 修复面** ⇒ 判据全绿证明不了修复已完成（覆盖面须从真源反解，禁写死清单） | `AI-DEVELOPMENT-STANDARD.md` §4.1 |
| 判例-17 | 判据的「通过」必须能指到**具体产物**，不是指到「我跑过了」 | `STANDARD` §4.1 引用 |
| 判例-19 | **`assert_true(true)` 是最危险的断言**（锁恒绿且看起来在工作） | `docs/probe-authoring.md` §9 |
| 判例-20 | **潜伏要诚实降级**：探针拿到「机理成立」之后还要判**可达性**，否则只能说「潜伏」不能说「在线」 | `docs/probe-authoring.md` §8 |
| 判例-23 | **深度病**：面是全的，但**识别方式可绕过**（按函数名认调用面，改名即绕过）⇒ 靠 AST/调用图治，不要混进覆盖面补丁 | `STANDARD` §4.1 |

### 3.3 元判据与自证（24–31）

| 编号 | 一句话 | 出处 |
|---|---|---|
| 判例-24 | 判据的 `--selftest` 必须至少一格是**变异对照**（改坏被测机制，断言锁会红） | `AGENTS.md`「变异对照必做」 |
| 判例-25 | **判据的真源若是「可过期快照」，它只能证明「文档 == 快照」，不能证明「文档 == 现实」**——两个都停在旧值 ⇒ 一致 ⇒ 绿。**这不是判据不准，是判据在说谎** | `scripts/README.md`（`check_badge.py` 条目）· `_badge_anchor.py` |
| 判例-26 | **元判据的第一版必然错** ⇒ 必须反向喂「已知会伤害它的案例的修复前形态」 | `STANDARD` §4.1 |
| 判例-27 | **判据必须断言「我验的对象存在」**：空面 ⇒ rc=2 不是 PASS；每个被验对象单独断言存在性 | `STANDARD` §4.1 |
| 判例-28 | 判据的「实测」一词只配指**现实**；证明不了现实时不许用（旧文案「== 实测 1455/1455」里的"实测"指的是快照） | `scripts/README.md`（`check_badge.py` 条目「文案纪律」） |
| 判例-29 | **机制格 ≠ 实现路径格**：测了「带某机制的 git/库调用」不等于测了「脚本自己的实现」⇒ 须补一格断言实现路径（用**运行时注入**，别用模式串匹配源码） | `AGENTS.md`「变异对照必做」 |
| 判例-30 | **自指假绿**：判据里写死一个模式串去匹配被测文件时，模式串自己就在文件里 ⇒ 变异真代码后匹配仍命中 ⇒ 锁恒绿 | `AGENTS.md`「变异对照必做」 |
| 判例-31 | **造竞态测试不要用 `sleep` 抢时序** ⇒ 改用「确定性注入污染状态」 | `AGENTS.md`「变异对照必做」 |

### 3.4 面与清单（34、40）

| 编号 | 一句话 | 出处 |
|---|---|---|
| 判例-32 | **新增前置条件后，所有依赖「后面某步」的格都会静默改考前面那步** ⇒ 加前置时必须逐格检查「它现在还在考它声称的东西吗」 | 本册（`check_badge` E3 / `check_test_sync` LOG-entry 两次实测） |
| 判例-33 | **性能逃生口的输出必须包含「跳过了什么能力的证明」**，不能只输出 SKIP（不带说明的 SKIP 在汇总里 = 「这格没问题」） | `run_guards.py` `fresh_enabled()` · `FIST_BADGE_FRESH=0` |
| 判例-34 | **判据面过宽**是「面窄」的反向病且更危险：面太宽 ⇒ 假红 ⇒ 红灯被忽略一次整把尺就废 | `STANDARD` §4.1 §判例-34 |
| 判例-38 | **`git mv` 在 `core.ignorecase=true` 的仓里对「只改大小写前缀」静默无效**（rc=0 但旧路径仍在跟踪面；内容若相同则 `status`/`diff` 都看不出来）⇒ rename 后必须 `git ls-files <旧名>` 复核 | 本册 §2.6 · 今日实测 |
| 判例-39 | **判例正文里的「病历数字」属历史面，不得随现状更新**（改了 = 说「当时就已经是新数」⇒ 后人读不出「为什么要有这条判例」）⇒ 进 `EXEMPT` 并在理由里写明 | `scripts/check_test_sync.py` EXEMPT 表 |
| 判例-40 | **「按清单执行」时必须问「这份清单是谁的产物、它自己的覆盖面是什么」**——清单是二手真源；执行前后都要用第三方判据交叉验证（实测：`check_test_sync` 的清单漏了 shields 徽章行，只有 `check_badge` 管） | 本册 §2.4 · `0f44433d` |

### 3.5 尚未逐条落文的编号（诚实标注）

**35、36、37** —— 本册未能定位到明确正文（可能属其他车道或未落盘）。
**不补编号、不臆造内容**：当你需要引用它们时，先去 `reports/` 里 `grep '判例-3[5-7]'` 定位。

---

## 4. 五条纪律：出处与触发条件

| # | 纪律 | 出处 | 什么时候会触发 |
|---|---|---|---|
| 1 | **`git commit` 必须带 `-- <明确路径>`** | `AGENTS.md`「提交纪律」 | 任何 `git add` 与 `git commit` 之间存在时窗 ⇒ 别人在这段里 add 的东西会被一并带走（一天内 8 次/5 人）。`-F`/`-m` 必须放 `--` 之前。批量用 `scripts/commit_scoped.sh`。 |
| 2 | **往 `scripts/` 加 `.py` 必须同批给执行面** | `AGENTS.md` | 一天内 3 次踩中，每次都是 `check_battery_count_doc` **FATAL、全仓门禁停摆**。三选一：进电池 / `expected(kind=…)` 带理由 / `EXEMPT_RULES` 带理由；**共享模块以 `_` 开头**自动豁免。 |
| 3 | **变异对照必做** | `AGENTS.md`「变异对照必做」 · 判例-29/30 | 任何判据的 `--selftest` 都要至少一格「改坏被测机制 ⇒ 断言锁会红」。两个陷阱：改坏注释不是改坏代码（判例-30）；机制格 ≠ 实现路径格（判例-29）。 |
| 4 | **不要用 `sleep` 抢时序** | `AGENTS.md` · 判例-31 | 造竞态测试时。慢则变成前置拦截、快则读到上一发残留 ⇒ **不可复现的锁 = 不可信**。改用「确定性注入污染状态」。 |
| 5 | **§4.1 尺的覆盖面自证 + 对称原则 + 反向样本库** | `AI-DEVELOPMENT-STANDARD.md` §4.1 | 写/改任何 `check_*.py` 时。三条规则：`coverage-self-proof`（hard，覆盖面 == 从真源反解的集合）/ `coverage-claim-explicit`（不得声称超过能验的面）/ `coverage-gap-declared`（**不覆盖什么要写明**——与「覆盖什么要有自证」构成对称）。另加判例-26：元判据的 `--selftest` 必须含**反向格**，样本取自真实历史形态。 |

---

## 5. 仍然待办（诚实清单）

| # | 项 | 状态 | 阻塞原因 |
|---|---|---|---|
| 1 | **`origin` 53 支清理** | **未执行** | **GitHub 不可达**（`Connection reset by 20.205.243.166 port 22`，三次探测均失败）。**本地缓存的 `refs/remotes/origin/*` 仍可做离线判定**，三档清单已出（见 §5.1）。 |
| 2 | 阶段 2/3/4/5（其他治理批次） | 未开工 | 未排期 |
| 3 | 非主 worktree 54 → 14 → **0** | 进行中（14 剩） | α |
| 4 | `temp/` 284 MB 清理 | 未执行 | δ |
| 5 | 13 个非标准顶层目录（48 MB） | 未执行 | δ |
| 6 | 兄弟目录 34 个迁出 | 未执行 | β |
| 7 | 判例 35/36/37 编号归属 | **未定位** | 见 §3.5 |
| 8 | `check_test_sync` 剩余历史面 EXEMPT 的巡检 | 已做（26 条全有效） | — |

### 5.1 `origin` 53 支 · 离线三档判定（用本地缓存 refs，不含主分支）

> ⚠️ **判例-41（本次新立）**：**「远端不可达」不是「远端是空的」。**
> `git ls-remote` 失败时 stdout 为空且**不报错到 stdout** ⇒ 会被读成「0 支 = 已清空」。
> **必须先验可达性再看内容**：`git ls-remote --heads origin 2>&1` 看 stderr 有无 `Connection reset` / `Could not read`。

| 档 | 支数 | 判定 |
|---|---|---|
| **A 零增量** | **13** | `git diff --numstat main...<br>` 无任何内容差 ⇒ 可删 |
| **B 小增量** | **7** | 内容差 ≤ 40 行（多为 main 已有等价改动）⇒ 可删，逐支给读数 |
| **C 需蒸馏** | **31** | 有独有内容（含 3 支 main 缺文件）⇒ **先蒸馏进 `reports/` 再删** |

**已复用的旧账**：`reports/2026-10-24-asset-preservation-proof.md` §2.6 已对其中 **17 支 origin-only**
做完逐支三重判据（A 文件面缺省 / B 符号面探针 / C 特征面人工核），结论：
**17 支里 13 支已等价落地、1 支无实质增量、3 支真增量未交付**
（`fix-desc-clip-utf8` / `fix/agent-fp-honest` / `fix/j2-call-face`）。**本单不重做那 17 支的判定。**

**删前必做**（网络恢复后）：① 三档清单报统帅批；② `git push origin --delete` 一次一批 ≤10 支；③ 每批报读数；④ **C 档先蒸馏**。

---

## 6. 怎么用这份文件

1. **第一次进来**：读 §0 一句话结论 + §5 待办清单，**别读完 40 条判例**，按需跳。
2. **要写判据**：读 §3.2 + §3.3 + §4 第 5 条（`STANDARD` §4.1）。
3. **要提交**：读 §4 第 1、2 条。
4. **要合并分支**：读 §3.1（判例-1/2/6/14 四条是必读）。
5. **怀疑「这判据绿得可疑」**：读 §3.3 全文 + §2.4（假绿三连）。

---

## 7. 来源

| 角色 | 本夜主要产出 |
|---|---|
| 统帅 | 判例定名与裁决、纪律立文、假绿定性 |
| 司令-α | worktree 清理、`commit_scoped.sh` 六道校验 |
| 司令-β | 兄弟目录迁移、`slave/*` 判据修复 |
| 司令-γ | sync 失败可见化（判例-9）、F3 门禁继承、判例-25 三笔（锚点/`--fresh`/EXEMPT）、本册整理 |
| 司令-δ | `temp/` 清理、`asset-preservation-proof.md`（17 支 origin-only 判定 + 判例-10/14 正文） |
| 司令-ε | `docs/probe-authoring.md`（判例-19/20）、task-26 |

**详细文档索引**：
- 判例专册：`reports/2026-10-24-merge-precedents.md`（1–12 + 索引表）
- 判例-10/14 正文：`reports/2026-10-24-asset-preservation-proof.md` §2.6
- 规范正文：`AI-DEVELOPMENT-STANDARD.md` §4.1
- 纪律正文：`AGENTS.md`（提交纪律 / `scripts/*.py` 执行面 / 变异对照必做）
- 探针规范：`docs/probe-authoring.md`
- 判据实现：`scripts/_badge_anchor.py` · `scripts/check_sync_workflow_reports_failures.py` · `scripts/check_badge.py` · `scripts/check_test_sync.py`
