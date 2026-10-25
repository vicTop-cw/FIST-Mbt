# 判例集：本批多司令合并作业沉淀的判据（2026-10-24）

> **来源**：owner 下令「4 路司令并行精细合并」，4 位司令（α/β/γ/δ/ε）+ 瘦身组实战产出。
> **为什么单独成文**：`memory/2026-*.md` 日日志按 `.gitignore:154-157` 的既有裁决**不入库**
> （「614MB 级大文件膨胀 git 历史 + 每次合并必撞冲突；账本 bugs.md / product.md / target.md 等
> 结构化核心记忆单独保留在 git 里」）。判据属于**可复用方法论**，不是流水账 ⇒ 落 `reports/` 入库。
>
> **收录范围（2026-10-24 归册修订）**：本册原只收 5 条（后加判例-6），但全仓有 **30 处**引用在册外
> 编号（判例-8 ×3 / 9 ×1 / 10 ×22 / 11 ×3 / 12 ×1）⇒ 按 **C 路 verify 报告 D3** 归册，
> 现为 **判例-1~6 + 8~12（判例-7 跳号）**，并在文末给出**索引表**。
> 各条定义从**引用处的上下文**提炼，出处逐条登记（见索引表末列与「来源」表）。

---

## 判例-1：基线倒退判据（本批最重要的一条）

**问题**：filter-repo 重写历史后，`git rev-list --count main..branch` / `comm -23` / `git cherry`
**全部失效**——本批 153 支分支**每一支**都报 ahead>0，包括早已合入的。

**判据**：
```bash
git diff --diff-filter=D --name-only HEAD <branch>
```
若列出 **main 上已有的文件** ⇒ 分支顶树是**旧基线**。

**后果（这是最关键的一点）**：
整支 `merge` / `cherry-pick` **不是「把提交带进来」，而是「拿旧树覆盖 main」**——
会**删掉** main 上后来才加的文件。

**本批实测**：17 支里每一支的 `diff-filter=D` 都列出 21~53 个 main 已有文件。
典型如 `fix/battery-tree-state-cell`：相对 HEAD 是 `+515/-4477`（67 文件），缺 10 个 src/cmd 文件。

**推论**：GitHub 的 `mergeable=True` 只判**文本冲突**，判不了内容倒退。
**PR 层的绿不等于内容面的等价** —— 这是 owner 指出「推到 GitHub 没推 gitcode」之外的另一半病根。

---

## 判例-2：合入前必须预演（司令-α 的做法）

**做法**：`isolated_git_env()` + detached HEAD + 预演后 `reset --hard` + `clean -fd` 复位干净。

**产出**：拿到「188 处冲突（U 态）+ 会新增 gitlink + 26 份 memory 流水账」的**硬证据**，
而不污染主仓。

**判据**：cherry-pick 前的预演**不是可选项**——它是「这个分支能不能合」的唯一可靠证据来源。

---

## 判例-3：**改名不是接线**（司令-δ 发现，最容易复发的假绿形状）

**现象**：`check_selftest_call_face.py` 第 52 行按**函数名**判「自检有没有走调用面」：
```python
CALL_FACE_FUNCS = ("main", "run", "cli")
```

某分支（#24 j2-call-face）的 5 个文件改动**全部是把函数改名为 `run()`**：
| 文件 | 原名 | 改成 |
|---|---|---|
| `check_fmt_gate.py` | `classify()` | `run()` |
| `check_merge_loss.py` | `analyze()` | `run()` |
| `check_ps_encoding.py` | `ps_encoding_problems()` | `run()` |
| `check_branch_ancestry.py` | `classify()` | `run()` |
| `check_memory_log_size.py` | 拆 `main()` 为 `run()` + `main()` | **真重构**（唯一例外） |

**问题**：改个名字判据立刻变绿，**但行为一行没变，自检该不覆盖还是不覆盖**
⇒ 这是**迎合判据正则**而不是**真接调用面**，用**判据形状**换**判据实质**。

**而且实测**：这 5 个文件**本来就不在 J2 违例名单里** ⇒ 那 4 个改名连「无害」的收益都没有。

**裁定**：只摘 `check_memory_log_size.py`（真重构：拆出 `run()` + 加 `--root` + temp 夹具调用面锁），
其余 4 个纯改名的**不摘**。

**推广判据**：
> 看到一个 PR/分支「改个函数名 / 加个关键字就让某判据变绿」时，先问：
> **「它的行为变了没有？」** —— 没变就是假绿，不是修好了。

---

## 判例-4：哨兵值必须证明不在合法值域内

**现象**：main 的 `current_pid_token` 用 `Array[Int32?]` + `None` 表示「未缓存」；
某分支用 **`-1` 哨兵**。

**为什么是错的**：`pid` 的合法值域**含 0**。若首调得到 0，则判断 `cached >= 0` 立刻为真
⇒ 返回 0 且**永不缓存**，「只固化一次」的语义被破坏。

**判据**：
> 用哨兵值表示「未设」时，必须证明该哨兵**不在合法值域内**。
> 做不到就用 `Option`——`None` 的语义是显式的，不需要证明值域。

**相关**：这也是 main 后来改成 `Array[Int32?]` 的原因（BUG-401）。

---

## 判例-5：判据存在但没接线 = 等于没判据

**现象 A**：`#20 backfill-ghost-bugs` 实测 `ci.yml` = 0 / `gate.yml` = 0
—— 两个守卫**从来没被任何 workflow 调用**。接线后 `run_guards` 缺执行面 = 0。

**现象 B**（手册 §附录，同型）：gate chain 一路绿，但 `ck_fmt()` 在冷格式化器下恒 `DEGRADED(2)`
⇒ **gate chain 等于完全没在把关**（8 个 PR 恒红而无人深究）。

**现象 C**（本会话早期）：`check_push_guard` 的 pre-push 拦截只活在本机手装的
`$GIT_COMMON_DIR/hooks`，被调脚本未收进任何安装器 `REQUIRED`
⇒ **换机即静默退化 fail-open，且没有读数能看见**。

**判据**：
> 新立一把尺，必须同时回答**「谁调用它」**。
> 只在本地跑得通、不在 CI/钩子/电池里 = 等于没立。
> 已有专门判据：`check_battery_count_doc`（缺执行面）/ `check_selftest_call_face`（调用面）。

---

## 判例-6：**删除一个跟踪件，会让所有历史分支都"新增"它**（规模级假阳性）

**现象**：Step 3 的「新 ahead 扫描」某一轮报 **148 支分支全都有新文件**，而且**全是同一个文件**：

```
gitcode/docs/bug-389-raw-log-summary-line: .dsh/fist-mbt-plugin/cordis.patch.yml
gitcode/feat/agent-fingerprint-pid-guard: .dsh/fist-mbt-plugin/cordis.patch.yml
… 共 148 条
```

**根因**：该文件在本轮被 `git rm --cached` 掉（它渲染了本机绝对路径 `F:/AI/Fist-Mbt`，是产物不是资产）。
`git cat-file -e HEAD:.dsh/fist-mbt-plugin/cordis.patch.yml` → **不存在**。
于是 `git diff --diff-filter=A HEAD <branch>` 对每一支都报「该分支新增了这个文件」——
**因为 master 面上它不存在了，所以任何还带着它的分支都成了「新增」**。

**为什么这是系统性假阳性，不是 148 个真分支**：
`--diff-filter=A` 的语义是「相对 base **新增**」，它比较的是**两棵树的差**，而"删除"与"某分支从未有"在同一次比较里**不可区分**。
删除件越核心（被大量历史分支带过），假阳性规模越大 —— 这是**删除动作的必然副产物**，不是分支质量问题。

**判据（看到就停下来查，别逐个分支去核内容）**：
> 当 `--diff-filter=A` 的结果**高度同构**（同一个/同一组文件出现在大量分支上）时，
> **先查该文件在 base 上是否被删除过**：
> ```bash
> git log --oneline --diff-filter=D --name-only -- <file>   # base 侧删过它吗
> git cat-file -e HEAD:<file> 2>/dev/null || echo "base 上没有它"
> ```
> 若确认是删除件 ⇒ 这批"新增"是**假阳性**，该在扫描的排除面里按前缀剔掉，而不是当 148 条线索去读。

**本仓实例的收口**：
- 删除点 = `164e2d69`（「清掉 .dsh 本机路径泄漏」），`git cat-file -e HEAD:.dsh/fist-mbt-plugin/cordis.patch.yml` 确认 main 上**不存在**；
- 护栏 = `.gitignore:203` `/.dsh/fist-mbt-plugin/cordis.patch.yml`（渲染自 `cordis.patch.yml.tpl`，产物不进跟踪面）；
- 排除后真实新面孔只剩 **1 个**（已判定重复的 `git_sandbox.py`）。

**给后续扫描的固定排除面**：`.dsh/` 整个目录都是**本机渲染产物**（同 `.verify-wt`、`temp/`），
按 `^\.dsh/` 前缀剔除是**长期正确**的，不是为这一次打的补丁。

---

## 判例-7：（**跳号，故意保留空位**）

**本编号未被使用。** 全仓 `git grep "判例-7"` = **零引用**（2026-10-24 实测）。

**为什么留空位而不重排**：本批判例是在多路司令并行作业中**陆续沉淀**的，编号一旦对外被引用
（`reports/` 5 份 + `scripts/README.md`），重排会让所有历史引用指向错的条目。
**跳号是无害的；重号是有害的。** 下一个人看到 7 空着，**不要以为漏了一页**，也不要顺手补一个
凑数的第 7 条——空位本身就是结论。

> **判据**：新增判例一律**追加到当前最大编号之后**，不回收空号、不重排已用编号。

---

## 判例-8：`--diff-filter=A` 非空只是**线索**，不是结论（三源假阳性）

**问题**：`git diff --diff-filter=A` 判出「有独有新增文件」后，若直接当结论，
会得出「这是真增量」的错误判断。至少三种**假阳性源**：

| # | 假阳性源 | 本仓实例 | 判据 |
|---|---|---|---|
| 1 | **删除件** | `.dsh/fist-mbt-plugin/cordis.patch.yml`（main 已 `rm --cached`）→ 147 支同时"新增"它 | `git cat-file -e main:<f>` 不存在，但 `git log --diff-filter=D -- <f>` 有删除记录（详见判例-6） |
| 2 | **重命名件** | `scripts/git_sandbox.py`（48 行）↔ `scripts/git_env.py`（117 行），同算法 / 同 `GIT_CONFIG_NOSYSTEM=1` / 同前缀剥离面 | 已知同族能力 + `git grep -l <符号> main` 有命中 |
| 3 | **垃圾件** | `scripts/tmp_merge_batch.ps1/.sh`（34 行一次性批量合并脚本） | 文件名匹配过程产物模式 / 内容是一段 `$branches = @( … )` 常量表 |

**统一判据**：
> `--diff-filter=A` 非空 ⇒ **必须再问一句「这个文件与 main 上的什么对应？」**
> 答不出对应物，才是真增量。

**镜像教训（同名判例的另一种用法）**：`polish-plugins-cl7.md` 把判例-8 当作
**「拿『我以为的标准』当尺」的镜像**引用——即审计方把自家假设当验收标准。
两者同根：**都缺一次「与真源对照」的动作**。

---

## 判例-9：静默失败让「守恒」失效（`|| echo` 吞掉 103 支）

**现象**：`sync-from-gitcode.yml` 每 6 小时把 GitCode 全部分支 force 推到 GitHub，写法是
```bash
git push --force gh "$b:$b" 2>&1 || echo "push failed on $b"
```
`|| echo` 让 **rc 恒为 0** ⇒ 每一支失败只剩一行日志，**workflow 依旧绿（SUCCESS）**。

**本批实测**：`origin` 51 支 vs `gitcode` 153 支，**差 102 支**，
而该 workflow **从没红过一次**。
> **「workflow 存在」≠「workflow 生效」。**

**判据（已机械化为 `check_sync_workflow_reports_failures.py`，R 系列五条）**：
- **S1** 禁静默吞：任何 `git push` 不得出现在 `|| echo` / `|| true` / `|| :` 形状里（**这是缺陷本体**）；
- **S2** 聚合读数在场：必须真 `echo` 出 `OK=… FAIL=…`；`OK=0; FAIL=0` 这种**初始化**不算——
  初始化在场而排印缺席，正是「看起来有计数其实没有读数」；
- **S3** `::warning::failed branches:` **点名**在场（只给数不点名 ⇒ 不知道该修哪支）；
- **S4** 「枚举面为空」守卫在场（否则「0 支 = 0 失败」被读成健康）；
- **S5** pipefail 陷阱（`set -o pipefail` 与 `$( … git push … | … )` 同现 ⇒ 尾部命令吃掉 push 的 rc）。

**只看代码面、剔注释**：该 workflow 的改正注释里原样写着旧写法作反例，
不剔注释等于让说明文字把自己判红（BUG-132 / R9 的老账）。

---

## 判例-10：空读数不等于「无」，判 **rc** 不判输出（三支子形状）

**核心（10 本体）**：**真正的判据不是「命令输出是什么」，而是「命令的返回码是什么」。**

```bash
git grep -c <pat>      # 零命中 → rc=1 且【无任何输出】；有命中 → rc=0
```
「命令无输出」极易被误读成「null / 未命中」。
同型形状：`git rev-parse --quiet`、`git cat-file -e`、`git merge-base --is-ancestor` —— **全是「rc 才是答案」**。

> **假阴性比假阳性贵**：假阳性让你多查一次，假阴性让你**删掉还有用的东西**。

### 判例-10b：`git diff --numstat` **读错了面**（不含 index）

`git diff --numstat` 比的是**工作树 vs index**，**不含 index vs HEAD** ⇒ 用它判「相对 HEAD 有无改动」**双向误判**。

实测复现（v3 抓出）：
```
                       wt-A        wt-B
git diff --numstat        157 行      64 行      ← 工作树 vs index
git diff --cached          103 行      57 行      ← index vs HEAD
git diff HEAD              102 行      57 行      ← 工作树+index vs HEAD
```
⇒ **「已经 `git add` 但未 commit」的改动，`--numstat` 在 `HEAD` 面上是看不见的。**

### 判例-10c：`numstat` 的 `0 0` 有**两种**含义

`0 0` 既可能是「**无差异**」，也可能是「**无法计算（冲突态）**」——**两者输出长得一模一样**。
⇒ 看到 `0 0` 必须再问：`git ls-files -u` 是否非空（冲突态）。

### 为什么拆成 10 / 10b / 10c 而不是合并

三支的**失效面不同**（判 rc vs 判输出 / 读错比较面 / 同形歧义），修法也不同。
合并成一条会让读者以为「改一个 `-c`→`-l` 就都解决了」——**实际只解决 10 本体，10b/10c 照样复发**
（本批 v1→v2→v3→v4 四版正是这样一轮一轮才收敛的）。

---

## 判例-11：`--name-only` 只证明「在暂存面」，**不证明「是我造的」**

**现象（本批实录，司令-ζ 亲手踩过两次）**：
`git add <我的单文件>` 之后执行 `git diff --cached --name-only`，
看到列表像自己的就提交了 —— 但**别人的预暂存内容（已 `git add` 未 commit）会被一并带走**。

**两次实测**（2026-10-24，同一笔任务内连中两次）：
- 第 1 次：`git add docs/deliverable.md` 后暂存面出现 `scripts/check_entry_paths.py`（他人 WIP，643 insertions / 526 deletions）；
- 第 2 次：`git add README.md` 后暂存面出现 `reports/2026-10-24-bugfind-src-omega-merge.md`（他人未跟踪报告）。

**正确执行**：
> 判例-11 = **「逐条核对『是不是我造的』」**，不是「看一眼列表像不像我的」。

```bash
git diff --cached --name-only     # ← 只是第一步（列出）
# 第二步（真正的判据）：每一条逐一回答「这一步是我 add 的吗？」
# 解法：
git add <明确路径>                 # 永远只 add 明确路径，不用 -A / -u / .
git restore --staged <非我造的>    # 发现即撤，保留其工作树内容原样
```

**补救边界**：改写已提交历史属**不可逆操作**，执行权在 owner/统帅；
agent 只做「发现 + 撤销暂存 + 上报」，**不擅自 rebase**。

---

## 判例-12：`--not` 是**切换开关**，不是逐项限定符

**问题（两面，都必须满足）**：

**面 1 —「多个 `--not` 互相抵消」**：
```bash
git rev-list --count HEAD --not --branches --not --remotes --not --tags   # 实测 366  ❌
git rev-list --count HEAD --not --branches --remotes --tags               # 实测 0    ✅
```
`--not` 是**开关**：第二个 `--not` 把它**后面**的口径翻回正向 ⇒ 条件互相抵消。

**面 2 —「`--not --all` 在 detached HEAD 上漏判」**：
detached 时 `--all` **含 HEAD 自身** ⇒ 结果是恒为空，**连真孤儿都查不出**。

**正确形态**（单一 `--not` 跟多个 rev）：
```bash
git rev-list HEAD --not --branches --remotes --tags
```

**自证要求**：`check_worktree_hygiene.py --selftest` 有 43 格，其中三格专钉这条：
「单/多 `--not` 读数必须不同」/「detached 孤儿必须检出」/「`--not --all` 漏判反证」。

---

## 判例-16：**判据面 < 修复面** ⇒ 判据证明不了修复已完成

> **编号说明**：判例-13/14/15 不在本册（属其他车道，未随本批归册）；判例-16 由
> `verify-guards-completeness.md` §十 提出并命名，本册按 D3 归册补入。
> **不重排**：13~15 的空位与判例-7 同理，**重号有害、跳号无害**。

**现象（R183 实录）**：
`patch_esm_main.py` 的修复面是**全部 >100KB bundle**（实测 4 个：`cmd/cli`、`cmd/main`、
`cmd/commissar`、`smoke`），而 `check_esm_bundle_runnable.py` 的原判据**只验 1 个**
（写死 `_build/js/debug/build/cmd/cli/cli.js`）。

> **判据面 < 修复面 ⇒ 判据全绿也证明不了修复已完成**——它只证明了**被它覆盖的那一部分**。

**判据**：
> 写/读一条判据时，先量两个集合：**修复面**（改动了哪些产物/入口）与**判据面**（判据实际检查哪些）。
> `判据面 ⊂ 修复面` 时，绿只是「抽样通过」，不是「全量通过」。

**正解（本仓已落地的形状）**：覆盖面**从真源反解**，不写死清单——
`check_esm_bundle_runnable.py` 改为从各包 `moon.pkg` 的 `pkgtype(kind: "executable")` 反解
（与 `check_entry_paths.py` 同源口径）。这与 J11 的「步名从实现反解」、`J14_FACES` 的
「面从注册表反解」是同一条定律：**手写清单必然落后于真源**。

**与判例-5 的区别**：判例-5 是「判据**没接线**」（根本没跑）；判例-16 是「判据**接了但面不够**」
（跑了，只覆盖一部分）。**后者更难发现**，因为它是绿的。

---

## 判例索引（按编号 · 一句话 · 首个出处）

| 编号 | 一句话 | 出处 |
|---|---|---|
| **判例-1** | `diff-filter=D` 列出 main 已有文件 ⇒ 分支顶树是旧基线，整支 merge = 拿旧树覆盖 | 本册 §判例-1 |
| **判例-2** | 合入前必须 `isolated_git_env()` + detached HEAD 预演 | 本册 §判例-2 |
| **判例-3** | 改名不是接线（判据存在但没接线 = 没判据） | 本册 §判例-3 |
| **判例-4** | 哨兵值必须证明不在合法值域内 | 本册 §判例-4 |
| **判例-5** | 判据存在但没接线 = 等于没判据 | 本册 §判例-5 |
| **判例-6** | 删除一个跟踪件 ⇒ 所有历史分支都"新增"它（规模级假阳性） | 本册 §判例-6 |
| **判例-7** | **跳号（故意留空，勿补）** | 本册 §判例-7 |
| **判例-8** | `--filter=A` 非空只是线索：删除件 / 重命名件 / 垃圾件三源假阳 | `asset-preservation-proof.md` §2.6.5 |
| **判例-9** | `\|\| echo` 静默失败让「守恒」失效（吞 103 支，workflow 仍绿） | `asset-preservation-proof.md` §6.2 · `check_sync_workflow_reports_failures.py` |
| **判例-10** | 空读数≠无：判 **rc** 不判输出（`git grep -c` 零命中无输出） | `asset-preservation-proof.md` §2.6.1 |
| **判例-10b** | `git diff --numstat` 读的是「工作树 vs index」，**不含 index** | `asset-preservation-proof.md` §2.6.6 |
| **判例-10c** | `numstat` 的 `0 0` 有两种含义：无差异 / 冲突态无法计算 | `asset-preservation-proof.md` §2.6.6 |
| **判例-11** | `--name-only` 只证明「在暂存面」，不证明「是我造的」（逐条核对来源） | `verify-guards-completeness.md` |
| **判例-12** | `--not` 是切换开关不是逐项限定符；`--not --all` 在 detached HEAD 上漏判 | `scripts/README.md`（`check_worktree_hygiene.py` 条目） |
| **判例-13~15** | **未归册**（属其他车道，空位保留，勿补编号）。统帅 2026-10-25 确认「我也不记得正文，照现状保留」 | — |
| **判例-16** | 判据面 < 修复面 ⇒ 判据全绿证明不了修复已完成（覆盖面须从真源反解） | `verify-guards-completeness.md` §十（R183） |
| **判例-18** | **自证必须覆盖整条链，不能只测最里层纯函数**（`check_git_sandbox_hygiene` 的 selftest 只测检测器、没测聚合器；变异 `offenders → bad = []` 纯函数格全绿而聚合失效） | `reports/2026-10-24-verify-guards-completeness.md` §9–10 |
| **判例-21** | **`git status` 的 `M` 是「stat 与索引不一致」不是「内容变了」**（86 个 `M` 而 `numstat` 零行）⇒ 判内容变化只看 `numstat`；比内容须先按 CRLF 归一化 | `AGENTS.md` · 本册同族 |
| **判例-22** | **`git checkout -- <f>`（动工作树，不可逆）与 `git restore --staged <f>`（动 index，可逆）名字相近语义相反** ⇒ 命令名字骗人 | 本册（α 实测：误执行前者丢掉全部改动） |
| **判例-28** | **空号（保留未用）**——没有定案就跳过，**不要补内容** | — |
| **判例-35** | **判据读到「别人正在写的半成品」**：残骸是稳定态、并发写入是毫秒瞬态 ⇒ 最轻量修法是「读两次，两次都坏才算坏」（不用 sleep） | α R2 报告 |
| **判例-36** | **修判据时把判据改瞎**：收窄豁免面试错 5 轮，前三种收法全部反向破坏（真读数消失 / 反而更糟），只有「只跳过围栏代码块」有效 | ε task-26 回传 |
| **判例-37** | **自证格也会过度拟合**（与判例-34 对称）：格子过宽 = 漏判、过严 = 误判；正确性判据是「它红的时候红的是不是真问题」 | ε task-26 §六 |
| **判例-47** | **判例集必须有正文落盘**：只在对话里立的编号 = 未落盘的判例，必须显式列在册里，不能沉默 | `2026-10-25-overnight-governance-digest.md` §3.5 |
| **判例-51** | **`git status` 的 `A` 标记 ≠ blob 不在对象库**：`A` 只说明「在本 worktree 索引里 staged」，不等于「内容只存在于这个 worktree」。**`git fsck --lost-found` 只找 dangling（无引用）对象，历史可达的不在其中。** ⇒ **判 A 态文件是否可恢复，看 `git log --all --format=%H -- <path>` 非空即可恢复，不能只看 `status`。**（实证：δ 报 22 个 A 态文件，`git log --all` 全部可达；α 仅凭 fsck 的 dangling 结论判「A 态不可恢复」是错的） | `2026-10-25-phase2-directory-cleanup.md` 教训 2 |
| **判例-54** | **删除报错 ≠ 删除失败**：`git push --delete` 对不存在的 ref 报 `error: remote ref does not exist` 且 rc 非 0，**但这条 error 的语义是「你要删的东西已经不在了」= 目标态已达成**。判例-41 说「远端不可达 ≠ 远端是空的」，判例-54 说「删除报错 ≠ 删除失败」。**⇒ 判「删没删」看不存在的那个东西，不看你命令的 rc。**（实证：A 档 13 支里 7 支远端早已不存在，7 次「失败」实为目标态已达成） | 本册 · 2026-10-25 origin 清理实测（γ） |

> ⚠️ **本表只登记「已落盘正文」的判例。** 判例 23–27 / 29–34 / 38–41 的正文在
> `AI-DEVELOPMENT-STANDARD.md` §4.1、`AGENTS.md`、`docs/probe-authoring.md`，
> 以及 `2026-10-25-overnight-governance-digest.md` §3（那是全仓唯一的一张完整编号面总表）。
> **判例-47：只在对话里立的编号 = 未落盘的判例，必须显式列在册里。**

> **索引维护纪律**：新增判例时**同一笔**补本表。表里列了而册内没有定义 ⇒ 视为索引腐坏（判例-5 同族）。

---

## 附：本批环境读数修正（手册 §7 的订正）

| 手册说 | 实测 |
|---|---|
| `python3 scripts/moon_test_env.py`（裸跑） | **`--target js`（只传旗标）能跑**；传完整 `moon test --target js` 会 `Failed to canonicalize input filter directory` rc=2 |
| `moon fmt` 全仓慎用 | ✅ 真的：`git status` 显示 345 个 M，但 `git diff --numstat` 真实差异**只有 7 个** —— 全是 CRLF 幻影（`.gitattributes` 无 `*` 规则 + `core.autocrlf=true`）。**用 numstat 过滤，只 `git add` 明确路径。** |
| `moon fmt --check` 不可用（BUG-388） | ✅ 真的，判它用 `check_fmt_gate.py`（0/2/1 三档） |
| `core.bare` 陷阱 | ✅ 真的，本会话踩过两次；已立 `check_repo_shape.py` 常驻守卫 |

---

## 来源

| 角色 | 贡献 |
|---|---|
| 司令-α | 判例-1 的纠错（「不是 main 留着 gitlink，而是修复早于分支」）、判例-2 的预演做法 |
| 司令-β | 发现 `.dsh` 本机路径泄漏（`F:/AI/Fist-Mbt` 3 处 + `locale/*.json` 2 处）、B 面口径两次收窄的实测依据 |
| 司令-γ | 「拿旧基线当分支顶树」的量化（`+3xx/-2xxx`、缺 4-10 文件） |
| 司令-δ | 判例-3（改名不是接线）、判例-4（`-1` 哨兵）、手册三条推翻、`branch^..branch` 算法纠正 |
| 司令-ε | `patch-id` 相等作为「同补丁重复应用」的决定性判据、gitlink pre-commit 硬门、判例-6（删除跟踪件 ⇒ 全分支假阳性） |
| 司令-ζ | **D3 归册**：判例-7（跳号说明）/ 8（三源假阳）/ 9（静默失败）/ 10+10b+10c（空读数三形状）/ 11（暂存面来源）/ 12（`--not` 开关）的定义提炼与索引表；判例-11 的**两次亲手实测**（`check_entry_paths.py` / `bugfind-src-omega-merge.md` 被误带入暂存） |
| 瘦身组 | `.git` 3.2G→1.4G、分支清理硬门「不放宽前提下可释放量≈0」的诚实结论 |
