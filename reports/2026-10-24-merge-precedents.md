# 判例集：本批多司令合并作业沉淀的 5 条判据（2026-10-24）

> **来源**：owner 下令「4 路司令并行精细合并」，4 位司令（α/β/γ/δ/ε）+ 瘦身组实战产出。
> **为什么单独成文**：`memory/2026-*.md` 日日志按 `.gitignore:154-157` 的既有裁决**不入库**
> （「614MB 级大文件膨胀 git 历史 + 每次合并必撞冲突；账本 bugs.md / product.md / target.md 等
> 结构化核心记忆单独保留在 git 里」）。判据属于**可复用方法论**，不是流水账 ⇒ 落 `reports/` 入库。

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
| 司令-ε | `patch-id` 相等作为「同补丁重复应用」的决定性判据、gitlink pre-commit 硬门 |
| 瘦身组 | `.git` 3.2G→1.4G、分支清理硬门「不放宽前提下可释放量≈0」的诚实结论 |
