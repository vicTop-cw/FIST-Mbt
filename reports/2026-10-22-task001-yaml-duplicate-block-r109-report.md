# R109 · TASK-001 台账面去重（P0 · 副机接主机任务池 · 2026-10-22）

## 结果摘要

`docs/tasks/backlog/TASK-001-conflict-markers-no-commit.yaml` 里**整份任务块被写了两遍**
（14 个顶层键各出现 2 次：`id` / `title` / `priority` / `status` / `problem` / `acceptance` /
`partial_met` / `open_item` 等），而后一份是**截断抄本**——停在 `open_item`，
没有 `result` / `acceptance_met` / `status_note` 三段收口回填。
本单只删这一份重复块（−42 行 / +0 行），保留权威块原文逐字不动。

为什么要管：本仓对 backlog 的消费面是**逐行反解**而不是 YAML 解析（这批文件里
`- [ ]` 复选框形状本身就让 PyYAML 抛 `ParserError`，实测在本文件第 23 列），
`check_backlog_status_staleness.py`、`fist-gate.py --scan`、引擎侧读的都是「第几次出现」的歧义面；
两份抬头 ⇒ 任何「取后一份」的读法拿到的是**没有验收结论的旧状态**，
这正是 P0 单在池子里长期长得像「没人干」的机理之一。

**没做的事**（按交付口径留给 owner）：`status` 仍写 `backlog`。该单三条验收已由
主线 `.githooks/pre-commit`（判据自证 → live 全跟踪面 → `git diff --cached --check` 三步）+
`scripts/install_git_hooks.py` + CI 的 Merge-marker gate 落账，但**盖章「可关闭」是 owner 的裁决**，
我不代改抬头；去重后权威块里的 `acceptance_met` 三条与 `status_note` 一句话仍在原位。

## 验收读数（本机实跑，非自述）

- 去重前：`id` 锚点 2 处（偏移 0 / 2683）、重复键 14 个、`status: backlog` 2 处、文件 6383 字节。
- 去重后（写盘前逐条断言，任一不成立就不落盘）：`status` 1 处 / `acceptance_met` 1 处 / `result` 1 处，
  全池 `docs/tasks/backlog/TASK-*.yaml` **重复顶层键 0 份**；EOL 仍全 CRLF（60 行，无裸 LF）。
- `git diff --numstat` ⇒ `0 42`（**只删不加**，权威块文字未动，评审可只看删除面）。
- `python scripts/check_backlog_status_staleness.py` ⇒ **rc=1 / 落差 9 条 / 上限 4**（与去重前**同一读数**
  ⇒ 本改动不移动那条棘轮，`run_guards.py` 里引用「现读 9 条」的期望依据文字仍然准确，无需联动）。
- `check_doc_surface` rc=0、`check_scripts_index` rc=0、`check_publish_payload` 待推后读数。

## 预存红点名（rc + 成因，均非本单元引入）

| 尺 | rc | 成因 | 归属 |
|---|---|---|---|
| `blackbox/check_merge_markers.py` | 1 | 跟踪面含 gitlink `.agents/worktrees/fix/display-rank-boundary` ⇒ 读不到正文（电池里按期望记账，抬头已由 R107 分档点名） | 主线出该条目（`git rm --cached`） |
| `check_backlog_status_staleness.py` | 1 | 落差 9 > 上限 4，含 TASK-001/005/006 等「主线已点名收口、抬头仍写 backlog」 | 任务池那一单 + owner 盖章 |
| `check_ci_step_position.py` / `check_scripts_naming.py` / `cleanup_artifacts.py --check` | 1 | CI 位置债 / 命名棘轮 / 工作树运行态脏 | 各自那一单 |
| `fist-gate.py` | 2 | 本机 `moon fmt` rc=127（`Moonfmt.make_directory` ICE，预存）⇒ 按设计 DEGRADED | 实体机/CI 复跑 |

## 任务分配记录（金条四）

副机自查池子（P0 优先级最高）⇒ 判定「代码面已在主线、缺的是台账面一致性」⇒ 亲自做删除面最小的
文档修复，不代刷状态；被检内容（钩子三步、安装器）由主线作者实现，本单元不重复实现、不改判据。

## 资源消耗

1 份文件、−42/+0 行；实跑 4 把尺 + 2 次全池重复键扫描；无网络写、无 moon 工具链调用（纯文档面，fmt 中性）。

## 遗留风险

1. 同族形状可能在 `docs/tasks/` 之外的台账面（如 `memory/bugs.md`、reports 标题）也存在「整块写两遍」，
   本单只扫了 backlog 目录 ⇒ 需要一把「顶层键唯一」常驻尺（见后续建议）。
2. `status` 与实际交付面的落差还在（9 条），本单**故意不缩**；若 owner 采纳，改的是抬头而不是判据上限。

## 后续建议

- 立 `check_backlog_yaml_integrity.py`：对每份 backlog yaml 断言顶层键唯一 + `acceptance_met` 出现时
  必须伴随 `status` 非 backlog（或显式 `status_note`），把本轮手工去重变成常驻门。
- 交付口径建议（与 R108 同源）：给 `expected(...)` 加成因指纹，避免「同码换因」被读成旧债。

## 来源

- 真源改动：`docs/tasks/backlog/TASK-001-conflict-markers-no-commit.yaml`（删除重复块 42 行）。
- 交付面证据（主线原文）：`.githooks/pre-commit` 三步门、`scripts/install_git_hooks.py`（`--check` 现读 rc=1
  并自述「core.hooksPath 未设置 ⇒ 钩子存在但不生效」——副机不代装：装上会让每次 commit 触发 `moon check`，
  而本机 `moon` 需 `MOONC_OVERRIDE` 才能跑，属每机一次的决定）。
- 读数：本机实跑 `check_backlog_status_staleness.py`、`check_doc_surface.py`、`check_scripts_index.py`、
  `blackbox/check_merge_markers.py`。
