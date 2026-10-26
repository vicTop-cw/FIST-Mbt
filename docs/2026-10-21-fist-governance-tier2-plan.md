# FIST-Mbt 治理能力 Tier 2 升级计划

> 日期: 2026-10-21 | 负责人: AtomCode 副机执行 | 主库: c689f027

## 目标

让 FIST-Mbt 成为**多机器协作的自驱开发治理层**：约定 `.git/fist/tasks/` 文件夹为任务池，按 yaml 分片派给不同机器，小步 PR → 自动门禁 → 合入主库。

## 核心设计

### 任务池文件夹约定

```
.git/fist/                          ← .gitignore 不跟踪，仅本地/PR 内可见
  ├─ tasks/
  │   ├─ backlog/                   ← 待分配（yaml 文件）
  │   ├─ claimed/<machine-id>/      ← 某机器认领了（移动到这里 + 写 owner 字段）
  │   ├─ done/                      ← PR 合入主库，归档
  │   └─ failed/                    ← 反复打回
  └─ machines.yaml                  ← 机器注册表
```

### 每个任务 yaml 格式

```yaml
# .git/fist/tasks/backlog/20261021-check-gate.yaml
task_id: 20261021-check-gate
title: 合入前统一门禁链 — check_merge_markers + fmt + build 一键执行
want: [guard, ci, gate]
acceptance:
  - python scripts/fist-gate.py returncode=0
  - python scripts/fist-gate.py --selftest 输出所有格子 PASS
  - 至少含 5 个检查项（merge_markers / fmt / build / ps_encoding / store_path）
  - moon build --target js src/server src/engine src/store src/router src/ops 0 errors
files_touched:
  - scripts/fist-gate.py
  - scripts/blackbox/check_merge_markers.py   # 已存在，被 gate 调用
min_pr_size: 3
max_pr_size: 15
owner: null
status: backlog
created_at: "2026-10-21T17:00:00+08:00"
```

### 机器注册 yaml

```yaml
# .git/fist/machines.yaml
machines:
  atomcode-01:
    agent: atomcode
    capabilities: [engine, server, issue-scan, guard]
    trust_score: 0.85
    load: 0
    endpoint: "local"
  marvis-02:
    agent: marvis
    capabilities: [router, store, executor]
    trust_score: 0.72
    load: 0
    endpoint: "local"
```

## 实现顺序（4 PR，每 PR 独立可合入）

### PR1: scripts/fist-gate.py — 统一门禁链

**范围**: 只写 1 个新文件 + 1 个 .gitignore 追加
**PR 大小**: ≤ 80 行 Python（单文件）
**验收**: `python scripts/fist-gate.py --selftest` 所有格子 PASS；gitignore 正确排除 `.git/fist/`

| 检查项 | 来源 | 作用 |
|---|---|---|
| merge_markers | 调已存在的 `scripts/blackbox/check_merge_markers.py` | 冲突标记硬门禁 |
| fmt | `moon fmt --check` | MoonBit 格式门禁 |
| build | `moon build --target js src/server src/engine src/store src/router src/ops` | 编译门禁（0 errors 才过） |
| ps_encoding | 调已存在的 `scripts/check_ps_encoding.py` 或内联 20 行 | BOM/UTF-8 门禁 |
| store_path | 内联 10 行 grep store 源文件绝对路径 | 路径硬编码门禁 |

**排除目录**: `_build/`、`temp/`、`.git/`、`node_modules/`

**退出码**: 0=全过；1=有失败；2=自身退化（扫描面空）

**--selftest**: 必须证明自己会红（合成违例）+ 干净不误红 + 每项格子独立可观测

### PR2: scripts/fist-task-pool.py — 任务池 yaml 管理

**范围**: 1 个新文件 + `.git/fist/.gitkeep` 占位
**PR 大小**: ≤ 120 行 Python
**验收**: 5 个子命令都能跑

```
用法: python scripts/fist-task-pool.py <cmd> [args]

子命令:
  init                 初始化 .git/fist/tasks/{backlog,claimed,done,failed} + machines.yaml
  publish <yaml>       把 yaml 从当前目录移入 .git/fist/tasks/backlog/
  claim <task_id> <machine-id>   移动到 claimed/<machine-id>/ + 写 owner 字段
  release <task_id>    退回 backlog（认领超时/放弃）
  archive <task_id>    移到 done/（PR 已合入）
  fail <task_id>       移到 failed/（反复打回，需人判断）
  list [--status X] [--machine Y]  列出任务（按 status/machine 过滤）
```

### PR3: 扩展 executor_register 支持 machine_id + scripts/fist-gate.py 加入 CI

**范围**: 修改 server.mbt 里 executor_register 的 capabilities 参数接受 machine_id；新增 `.github/workflows/gate.yml` 调 fist-gate.py
**PR 大小**: 单 workflow 文件 ~50 行
**验收**: gate.yml 在 PR 时触发，rc!=0 阻止 merge

### PR4: scripts/fist-pr-automator.py — PR → Gate → Merge 自动流水线

**范围**: 1 个新脚本
**PR 大小**: ≤ 150 行
**验收**: 给定一个 task_id，自动：
  1. 找 backlog 里的 yaml
  2. 验证 `files_touched` 里的文件不被其他机器 reserve（调 reserve_check）
  3. 生成 PR 到 gitcode（标题 = yaml.title）
  4. 调 fist-gate.py 跑门禁
  5. 门禁全过 → merge 回 master → 移动 yaml 到 done/

## 与现有 FIST-Mbt 基础设施对接

| 功能 | 现有 | 要加的 |
|---|---|---|
| 任务池 yaml 管理 | 无 | PR2 的 fist-task-pool.py |
| 门禁链 | check_merge_markers.py 已存在 | PR1 统一调度 |
| PR 自动合入 | 无（手动） | PR4 自动化 |
| 机器注册 | executor_register 已有能力标签 | PR3 扩展 machine_id |
| 文件作用域预订 | reserve_scope 已实现 | PR4 调用 |
| 冲突检测 | conflicts_check 已实现 | PR4 调用 |

## 当前状态（2026-10-21）

- ✅ HEAD c689f027，三远端对齐，build 0 errors
- ✅ check_merge_markers.py 已合入（PR feat/guard-check-merge-markers）
- ✅ scripts/slave-branch-merge.ps1 已合入
- ⏳ PR1~PR4 待 AtomCode 执行
- ⏳ 写好后让 FIST-Mbt publish 任务 → 任务落 yaml → 机器 agent 认领 → 小步实现 → PR → gate → merge → done

## 关键约束（必须遵守）

1. **每个 PR ≤ 15 commits，一个功能一件事**
2. **commit 前必须 `moon fmt` + `moon fmt --check`**
3. **fist-gate.py 必须有 --selftest 且所有格子 PASS**
4. **scripts/fist-*.py 必须 UTF-8 BOM 或纯 ASCII**（PS5.1 约束）
5. **所有路径用相对路径，绝对路径硬编码 = FATAL**
6. **.git/fist/ 在 .gitignore 里**
