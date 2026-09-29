# Seven Self-Driving Modes (meta-prompt library)

Seven battle-tested modes, each a full closed loop on the FIST state machine. Templates live in the meta-prompt library (`_fist_meta_prompts/`); instances land as `实例/<project>/<mode>_<date>.md`.

## Mode matrix

| Identifier | Display name | Purpose | Default switches | Trigger scenario |
|---|---|---|---|---|
| `advance` | 持续开发新功能 | New feature / version iteration, deep-split tree, leaf-by-leaf closure | omega yes, laya yes, issue_up yes | Version sprints, new subsystems |
| `polish` | 打磨完善（不加新功能） | Harden/refactor what exists; publishing a new feature task is refused | issue_up yes | Pre-release polish, hotspot modules |
| `verify` | API 枚举与完备性验证 | Gates run with evidence + Omega ledger audit + output hard gate; never fixes, only reports | omega yes, issue_up yes | Pre-release re-verification |
| `bugfind` | 寻虫：issue_scan + 边界语料 | Rule-driven source scan + boundary corpus -> minimal repro -> report | issue_up yes | Hunting before a release |
| `fix_and_merge` | 修复 issues + 合并分支 | Backlog bug closure + branch merge (human approval before the real merge); needs a GitHub/GitCode token | issue_up yes | bugs.md backlog, feature merge |
| `tidy` | 项目打扫清整 | Ledger/memory/temp-product inventory; adding new code is refused, deletions ask first | issue_up yes | Phase wrap-up, archive retiring |
| `explore` | 探索：按复杂度自选模式 | Scores the goal's complexity 0..5, selects one of the six single modes, and only then dispatches a leg into it. Parallel modes are allowed **only** when each candidate declares a non-empty file scope, the scopes are pairwise disjoint, `reserve_scope` returns reserved/renewed/taken_over and `conflicts_check` clears — otherwise it falls back to single-mode serial. | no forbidden tools (it is a selector, not a worker) | Goal given without a pre-chosen mode; multi-mode candidates |

> Historical note: older copies of this file listed `hunt`, `fix-and-merge` and `night-loop`. Only `bugfind`
> and `fix_and_merge` are accepted by the server; `night-loop` was never a mode identifier (the unattended
> window is `watchdog_tick` + the cron meta-prompt template, not a mode), and `explore` replaces it here.

## Loop pattern (mode G core)

1. Time gate (optional) → read `loop_progress.md` ledger → take the `next` segment.
2. Each segment = one independent root task (`[tag:id]` idempotent marker), full closed loop.
3. Constraints per session: time box + max segments; on failure retry once, then skip & record; two consecutive failures → safe exit.
4. Ledger first: a segment is done only when the ledger `done` line is written.

## Common red lines

- Timestamps are server-stamped — there is no `now` to pass (BUG-33). Relative paths for bug-family tools; probe `report_bug` landing spot once per session.
- No irreversible ops without human approval (push / delete / wipe); local commit only where the param card allows.
- Gate not green → no verify. Failures surface verbatim; never fake completion.
- Omega strong verify on: spec_create → spec_review → execute → result_verify → verify; missing deliverable = reopen → execute → resubmit.
