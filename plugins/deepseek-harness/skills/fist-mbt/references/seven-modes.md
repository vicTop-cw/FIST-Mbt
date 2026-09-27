# Seven Self-Driving Modes (meta-prompt library)

Seven battle-tested modes, each a full closed loop on the FIST state machine. Templates live in the meta-prompt library (`_fist_meta_prompts/`); instances land as `实例/<project>/<mode>_<date>.md`.

## Mode matrix

| Mode | Purpose | Default switches | Trigger scenario |
|---|---|---|---|
| 推进 advance | New feature / version iteration, deep-split tree, leaf-by-leaf closure | omega ✅ laya ✅ issue_up ✅ | Version sprints, new subsystems |
| 寻虫 bug-hunt | Five-route hunting (adversarial samples / diffing / fuzz / report re-check / code reading) → minimal repro → report, quick-win-only fixes | issue_up ✅ | Pre-release hunting, hotspot modules |
| 修复与合并 fix-and-merge | Backlog bug closure + branch/backup merge (pre-flight demo, human approval before real merge) | issue_up ✅ | bugs.md backlog, feature merge |
| 验证 verify | Gates run with evidence + Omega ledger audit + output hard gate; never fixes, only reports | omega ✅ issue_up ✅ | Pre-release re-verification |
| 清整 tidy | Ledger/memory/temp-product inventory; deletions always ask first | issue_up ✅ | Phase wrap-up, archive retiring |
| 夜间循环 night-loop | Free-model window cron: time-gate + progress ledger relay, hunt→fix→verify→polish × N rounds | omega ✅ laya ✅ issue_up ✅ call_log ✅ | Unattended windows (e.g. 23:00–08:00) |

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
