# MCP Tools Reference (FIST-Mbt)

**Live truth first**: call `tools/list` on the server — the registry evolves fast (41 → 105+ in weeks). This file is a categorical map, not an exhaustive schema list.

Server entry: `node cmd/main/main.js` (run `python scripts/patch_esm_main.py` first; Node ≥ 24). Protocol `2026-07-28`, `params._meta` three fields required. Python driver: `scripts/fist.py call <tool> --json '<args>'` (or subprocess per fist_drive.py pattern).

## Tool categories (105 at snapshot)

| Group | Count | Representative tools |
|---|---|---|
| Lifecycle | 14 | publish, publish_parallel, plan, claim, execute, submit, verify, reject, retry, pause, resume, reopen_task, archive, delete |
| Query | 2 | list (status filter, Chinese status names), get |
| Ops | 14 | task_plan_deep (omega_strong_verify/laya_auto/gradient/calibrate/reinject_context), conflicts_check, heartbeat, heal, watchdog_tick, task_cleanup, phi_accrual, saga_register/rollback/repair, circuit_fail/succeed/status, tx_contract |
| Selfdrive | 9 | selfdrive_init/get/append/export_tasks/review_tick/review_ready/publish_next/parse_next_tasks/pick_next, selfdrive_dispatch |
| Logs/bugs/cost | 15 | call_log, bug_list, report_bug, issue_scan, eval_feedback, run_check, output_validate, project_standards, schedule, pipeline_tick, cost_stats, cost_budget_check/split, progress_gate, laya_decide |
| Omega | 6 | omega_spec_create, omega_spec_review, omega_result_verify, omega_status, omega_verify, omega_verify_fix |
| DAG | 20 | dag_critical_path/parallelism/ascii/check/ready/sort/depend/publish/slack/schedule/cost_route/mc, plan_revise, goal_drift_check, board_ascii, status_summary, project_health, health_check, reserve_scope/check/release, task_triage |
| Marketplace | 5 | executor_register, executor_route, executor_auction, executor_clear |
| Memory/evolve | 11 | memory_consolidate/gc/link, evolve_distill/lesson/critic/sample/snapshot/submit/asset_register, task_challenge |
| ATGC-old | 3 | atgc_old_compile, atgc_old_run, atgc_old_talk |
| Audit | 2 | audit_permission, audit_log (in-process only — see BUG-3) |
| Namespace | 3 | store_open (scratch), store_list, store_close |

## Call etiquette

- `params._meta` = { protocolVersion: "2026-07-28", clientCapabilities: {}, clientInfo: {...} } — missing → `Missing required _meta field`.
- `initialize` returns `Method not found` — harmless, call `tools/call` directly.
- Python stdout decode: `encoding="utf-8", errors="replace"` (gbk otherwise).
- No `now` parameter exists on any tool (BUG-33): the server stamps ISO8601 timestamps itself, so ledger times cannot be forged by the caller. `heartbeat` during long work.
- Relative paths only for bug-family tools; they resolve against server cwd (BUG-5).

## Contract-drift watchlist (verify against live behavior)

- BUG-12: `list` namespace scope ≠ description. BUG-14: `laya_decide` decision field missing. BUG-11: `bug_id` vs `id` naming. BUG-9: no bug_close. When a tool's return contradicts its description, file a `report_bug` with live evidence (after probing duplicates in `memory/bugs.md`).
