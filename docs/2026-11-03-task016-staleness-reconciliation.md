# TASK-016 盖章收口的 subject 点名补账（2026-11-03）

## 事实
- `docs/tasks/backlog/TASK-016-docs.yaml` 的 `status: done` 是**有据的**：
  lead 终审盖章（`reviewed_by: lead` / `reviewed_at: "2026-11-02"`），
  review_evidence 引 reports/2026-11-02-task016-governance-pointer-report.md
  （窄口径命中 56 份、c 类真源指针缺失为空、收敛面由 T0r8 落地、
  check_doc_paths rc=0），工作量真实完成，无虚报。
- 但盖章那一笔落地 commit `795177a58` 的 **subject 用的是 T0r7 别名**
  （"feat(scripts): 反向 diff 判据落地（T0r7）+ …"），subject 未字面含
  `TASK-016`。

## 为什么这是一颗判据红而不是判据错
- `scripts/check_backlog_status_staleness.py` 的 R2 判据设计为「done 必须有
  **commit subject** 点名该 id」——数 subject 而非 body 是刻意收紧（body 可
  事后任意补写，subject 是当时的申报面）。别名（T0rNN）不认是同一收紧的
  一部分：判读面必须是机器可正则的单一名义，别名表会让判据变成人读面。
- 所以红是真的：TASK-016 的 done 在 R2 证据面上**未成立**，即使工作量完成。

## 本笔的补账
- 本笔 commit 的 **subject 字面点名 `TASK-016`**，使 R2 证据面成立。
- yaml 本身不动（append-only 盖章面；工作、证据、盖章均真实，无需改判）。
- 之后的落账纪律：任务卡盖章收口类的 commit，subject 必须带 `TASK-0NN`
  正名，别名（T0rNN / 车道名）只可出现在 body——否则 staleness 判据红。

## 来源
- 判据读数：`python scripts/check_backlog_status_staleness.py` rc=1，
  `UNPROVEN-DONE TASK-016 status=done 但主线无任何点名该 id 的 commit`。
- 盖章 commit：795177a58（gitcode/main 祖先，双远端已推、CI 双绿）。
- 日期：2026-11-03
