# Git Hooks（FIST-Mbt）

## Pre-commit Hook（TASK-001②：冲突标记不许进 commit）

钩子做三步，**缺一不可**：

1. `python scripts/blackbox/check_merge_markers.py --selftest` —— **先让判据自证**：尺子本身坏了就拒绝提交，
   不许"绿得不知所以"；
2. 同脚本 live 扫全跟踪面 —— 冲突标记进跟踪面后 **CI 只能事后知道**；259b56a8 就是这么带 3 处标记进
   master 的（`.mbt` 带标记直接崩编译，`moon build` 报一片 `Error: [xxxx]`）；
3. `git diff --cached --check` —— 兜住暂存面里的行首标记 / 尾随空格一类"提交前就能看见"的脏。

最后跑 `moon check`（可用环境变量跳过，见下）。

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
python scripts/blackbox/check_merge_markers.py --selftest && python scripts/blackbox/check_merge_markers.py
git diff --cached --check
```

### 实测证据（2026-10-21 临时仓库端到端，非"读代码就算"）

- 暂存面含 `<<<<<<< HEAD / ======= / >>>>>>> other` ⇒ `git commit` **rc=1 且 HEAD 未动**（拒绝）；
- 清掉标记后同一仓库 ⇒ `git commit` **rc=0**（通过）；
- 干净仓库上 `--check` 只核对不改配置；`--install` 幂等。
