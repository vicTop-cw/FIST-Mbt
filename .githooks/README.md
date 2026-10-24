# Git Hooks（FIST-Mbt）

## Pre-commit Hook

钩子做四道门，**缺一不可**：

0. **gitlink 门（R179）**：`python scripts/check_index_gitlinks.py --selftest` 先自证尺子（19 格），
   再 `--staged` 判**本次暂存面**有没有 `mode 160000`。本仓 `git worktree list` 注册了 51 个 worktree，
   每个目录根都有一个 `.git` 文件 ⇒ 一次 `git add -A` 就会把它们记成 gitlink 写进索引。
   真实事故：`4a7bf82a` 把 `.agents/worktrees/fix/display-rank-boundary` 当 gitlink 提交进跟踪面，
   `check_merge_markers` 等判据「读不到正文」。**gitlink 进了历史就修不掉**（`git rm --cached`
   只挡下一次）——所以只能卡在提交前，这就是这道门存在的全部理由。
1. `python scripts/blackbox/check_merge_markers.py --selftest` —— **先让判据自证**：尺子本身坏了就拒绝提交，
   不许"绿得不知所以"；
2. 同脚本 live 扫全跟踪面 —— 冲突标记进跟踪面后 **CI 只能事后知道**；259b56a8 就是这么带 3 处标记进
   master 的（`.mbt` 带标记直接崩编译，`moon build` 报一片 `Error: [xxxx]`）；
3. `git diff --cached --check` —— 兜住暂存面里的行首标记 / 尾随空格一类"提交前就能看见"的脏。

最后跑 `moon check`（可用环境变量跳过，见下）。

### gitlink 门被触发时怎么办

钩子会打印**逐条可执行**的修复命令，最短形是：

```bash
git rm --cached -f -- "<被点名的路径>"                     # 只摘索引，工作树目录不动
git check-ignore -v -- ".agents/worktrees/"                # 确认 .gitignore 护栏命中
grep -qxF ".agents/worktrees/" .gitignore || echo ".agents/worktrees/" >> .gitignore
```

`-f` 不是可选的：对**首次** add 进来的 gitlink，不带 `-f` 的 `git rm --cached` 会报
「staged content different from both the file and the HEAD」而失败（自证格实测过）。

**不要用 `--no-verify` 绕过**：gitlink 进了历史就只能改写历史。

### 自证（两道，都进电池）

| 判据 | 格数 | 证明什么 |
|---|---|---|
| `scripts/check_index_gitlinks.py --selftest` | 19 | 识别核认得 `160000`；临时仓端到端：造雷必拦、修复命令真能修好、装上护栏后 `git add -A` 不再造雷、非 git 目录自拒 `rc=2` |
| `scripts/blackbox/e2e_precommit_gitlink_gate.py --selftest` | 9 | **钩子真会拦**：把真钩子拷进临时仓、`core.hooksPath` 指过去，跑真 `git commit` ⇒ gitlink 提交 `rc≠0` 且 HEAD 不动；合法提交 `rc=0` 且 HEAD 前进（不误拦） |

第二道是关键：`check_index_gitlinks.py --selftest` 只证明「尺子认得出 gitlink」，**没证明钩子接上了**
（`.githooks` 早在仓里、`core.hooksPath` 曾长期为空）。

### 安装（一条命令，幂等）

```bash
python scripts/install_git_hooks.py --install   # 设置 core.hooksPath=.githooks 并补可执行位
python scripts/install_git_hooks.py --check     # 只核对：0=已生效 / 1=未生效 / 2=环境不完整
```

> **为什么需要安装器**：`.githooks/pre-commit` 早在仓里，但 `core.hooksPath` 从未被设置 ⇒ **钩子默认不生效**，
> "每个 commit 前自动跑标记判据"这条其实一直没落到本地提交面（CI 那步只管推送后）。
> 本仓实测：`git config --get core.hooksPath` 为空。安装器把"装上"变成可复现命令，`--check` 供守卫核对，
> 避免"文件在、没生效"。

### 环境变量

| 变量 | 作用 |
|---|---|
| `FIST_PRECOMMIT_SKIP_MOON=1` | 跳过 `moon check`（本机依赖缓存格式过旧 / 格式化器未预热时用；CI 仍会查） |
| `FIST_PRECOMMIT_STRICT` | 保留位：将来若把 fmt 世代差纳入钩子硬门时使用 |

### 手工等效命令（不想装钩子时）

```bash
python scripts/check_index_gitlinks.py --staged && python scripts/blackbox/check_merge_markers.py --selftest && python scripts/blackbox/check_merge_markers.py
git diff --cached --check
```

### 实测证据（2026-10-21 临时仓库端到端，非"读代码就算"）

- 暂存面含 `<<<<<<< HEAD / ======= / >>>>>>> other` ⇒ `git commit` **rc=1 且 HEAD 未动**（拒绝）；
- 清掉标记后同一仓库 ⇒ `git commit` **rc=0**（通过）；
- 干净仓库上 `--check` 只核对不改配置；`--install` 幂等。
