---
status: 提案中
decided_by:
decided_at:
decision:
---

> **来源（孤本捞回，判例-24）**：本稿原只存在于 sibling 目录 `E:/IDEProjects/AI/FIST-Mbt-slave-wt03` 的
> commit `81eac734`（分支 `feature/wt-sparse-scripts`），**主仓与 `ls-remote origin` 均无此文件**。
> 该 sibling 三条件全过（dirty=0/unpushed=0/conflict=0）却含此孤本 ⇒ 由 tidy/F 路（task-21）原样捞回，
> **正文一字未改**，仅补本头部以满足 `docs/plans/README.md` 的强制字段与 `check_plan_location` 守卫。
> 关联：`docs/plan-light-worktree-isolation.md`（母计划，§4 定双轨）｜`scripts/run_light_wt.py`（Python 主轨，已实现同名能力）。

# WT-03 设计：sparse cone worktree 创建 + light-wt / light-wt-teardown 双轨脚本

## 目标（一句话）

一条命令给任务开一个「轻沙箱」（git worktree + sparse cone），再一条命令幂等回收；
bash / pwsh 双轨同语义，磁盘占用显著低于全量 checkout。

## 要改哪些文件（纯新增）

- `bin/light-wt.sh`（新增）— bash 轨创建脚本
- `bin/light-wt.ps1`（新增）— PowerShell 轨创建脚本
- `bin/light-wt-teardown.sh`（新增）— bash 轨回收脚本
- `bin/light-wt-teardown.ps1`（新增）— PowerShell 轨回收脚本

## 不改哪些文件（边界）

- `src/**` 全部 `.mbt` 源码不动 → MoonBit 侧零回归
- `plugins/`、`.mbti`、`dist/`、`memory/bugs.md` 抬头状态不碰
- `scripts/` 不动（`bin/` 不在任何守卫扫描面：`check_ps_encoding` 只扫 `scripts/**/*.ps1`，
  `check_scripts_index` 只扫 `scripts/` 直接子文件）
- 不 push upstream（主仓）

## 命令序列（已在合成仓原型验证）

创建（`--no-checkout` 留空 index，`set` 不物化 ⇒ 必须补 `read-tree -mu HEAD`）：

```
git -C $BASE worktree add --no-checkout -b $BRANCH $PATH $REF
git -C $PATH sparse-checkout init --cone
git -C $PATH sparse-checkout set <cone...>
git -C $PATH read-tree -mu HEAD      # 只物化 cone（cone 模式自动含顶层文件）
```

回收：

```
git -C $BASE worktree remove $PATH            # 脏树拒绝 rc=128（安全默认）
git -C $BASE worktree remove --force $PATH    # --force 才丢弃未提交改动
git -C $BASE worktree prune                   # 收尾清残留；已不存在则幂等 rc=0
```

## 接口

```
light-wt <wt-name> <cone-path>... [--base P] [--root P] [--ref R] [--branch B] [--dry-run]
light-wt-teardown <wt-name> [--base P] [--root P] [--force] [--delete-branch] [--dry-run]
```

环境变量（plan L145 约定）：`FIST_BASE`=基仓（缺省=cwd 的 git toplevel）；
`LIGHT_WT_ROOT`=worktree 根目录（缺省=系统 temp 下 `fist-light-wt`，不污染任何 checkout）。
worktree 路径 = `$LIGHT_WT_ROOT/<wt-name>`；缺省分支 = `wt/<wt-name>`；缺省 base ref = 基仓 HEAD。
`--branch` 指向已存在分支时走挂载模式（不带 `-b`）。

## 四态覆盖

| cl | 覆盖 | 状态 |
|---|---|---|
| cl1 MCP 工具 | 不需要（shell 脚本；`wt_*` MCP 工具归 WT-02） | ⏭ |
| cl2 CLI 封装 | 不需要 | ⏭ |
| cl3 skill 文档 | 不需要 | ⏭ |
| cl4 测试 | 双轨语法检查 + 真实仓 e2e 实跑（见验收） | ✅ |
| cl5 L4 证据 | 实跑输出：创建成功 / 磁盘对比 / teardown 幂等 | ✅ |
| cl6 文档同步 | 无工具增删，README/AGENTS 计数不变 | ⏭ |
| cl7 插件投影 | 工具数不变，无需 gen_plugins | ⏭ |

## 验收标准

1. `bash -n bin/light-wt.sh bin/light-wt-teardown.sh` rc=0；双 `.ps1` 经 pwsh AST 解析 0 error
2. 双 `.ps1` 纯 ASCII（BUG-88 的 PS5.1 判据）
3. 真实仓 `light-wt demo src/display` 创建成功：worktree 只物化 cone，磁盘显著小于全量 checkout
4. `light-wt-teardown demo` 连跑两次均 rc=0；`git worktree list` 无残留、`prune` 幂等
5. `moon fmt --check` + `moon test --target js` 全绿（无 `.mbt` 改动，基线零回归）
