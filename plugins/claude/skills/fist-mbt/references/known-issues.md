# Known Issues & Detours (BUG-1~16, snapshot 2026-09-26)

All OPEN at snapshot time. Full live details: FIST-Mbt repo `memory/bugs.md`. Check it before reporting duplicates.

## High

- **BUG-1** Caller-supplied `now` is persisted verbatim into `tasks.created_at/updated_at` → ledger timestamps can be forged (measured 7.5–8.3h ahead), and freshness checks (`omega_gate`) mis-fire. Detour: always pass explicit `now` yourself; treat ledger timestamps as advisory. Fix direction: server-side stamping (now = test seam only).
- **BUG-4** `run_check` spawns arbitrary host commands (no allowlist / workdir bound); `laya_js`/`github_js` use `sh -c` shapes. Detour: never expose the server to untrusted clients; pass explicit argv, project-scoped workdir. Fix direction: default-tight allowlist + workdir subtree.
- **BUG-14** `laya_decide` omits the contract-promised `decision` field on 3/4 return paths (sidecar passthrough, non-zero exit, Err branch). Detour: read `answers` directly, degrade to self-decided routing and record reasoning (this is also why `laya` shows as `fallback` in most reports).

## Medium

- **BUG-2** `retry` lands in 执行中 but `execute` only accepts 拆分中/已领取 → cannot register deliverables after bounce. Detour: `pause → resume → execute` (tool name `resume`, not `resume_task`). Fix direction: extend execute pre-states.
- **BUG-3** `audit_log` is in-process only; cross-process it returns `[]` (silent empty evidence). Use `call_log` for anything cross-process.
- **BUG-5** `project_dir` contract split: bug-family (report_bug/bug_list/issue_scan) requires relative paths resolved against **server process cwd**; memory-family accepts absolute without validation. Probe the landing spot once per session; never assume `.` means the project you meant.
- **BUG-8** `report_bug(publish_task=true)` drops the fix root into namespace `"bugs"`, detached from the caller's tree — auto-roll never fires for it.
- **BUG-9** No bug-close API: `bugs.md` entries stay OPEN after fix tasks complete. Reconcile via `bug_list` + task states; manual md edits bypass the server ledger.
- **BUG-12** `list` without namespace returns a single ns scope in practice (contract says all); ns `bugs` rows invisible. Reconcile with `get(task_id)`.
- **BUG-15** `issue_scan` matches raw-line substrings: hits comments and its own rule table (measured high-precision 0/8). Verify every finding against source + runtime before reporting; never bulk-report.
- **BUG-16** Version literal drift: `status_summary`/`project_health`/`fist://overview` may report an old version; trust `moon.mod`. Add a version-consistency guard before releasing.

## Low

- **BUG-10** (superseded by BUG-13) archive of 待领取 tasks fails (complete pre-state) — original "no way out" claim was wrong.
- **BUG-13** Self-correction: `pause`/`reopen_task` are legal exits for parked tasks; the real gap is that illegal-transition error messages don't hint at them.
- **BUG-11** Field naming: `report_bug` returns `bug_id`, `bug_list` rows use `id`. Reconcile by value, not key.
- **BUG-6** One-liner stub ("BUG-5 resolved_path check", no detail) — noise/probe residue; candidate for ledger cleanup (see BUG-9: no close API).
- **BUG-7** Duplicate of BUG-6 (same one-liner) — noise; ledger cleanup candidate.

- **BUG-17** Doc count drift across AGENTS/deliverable/scoring_rubric/README (tools 105/104 vs live 116; tests 317/329 vs live 376). Polish round fixed the four docs (guards re-run PASS), but there is **no build-time single source** yet — always trust live \	ools/list\ / \moon test\ over any doc count, and run the guard family in the same round you touch counts.
- **BUG-18** \laya_decide\ blocks up to ~4 min per call (unconditional probe + 300s sidecar budget vs 30s MCP client timeout) — the client sees a hang, not a degradation, inverting BUG-14's "never blocks" promise. Unfixed (Round 2 queue). Detour: in unattended pipelines prefer explicit degraded routing over \laya_auto=true\, or raise client timeout; probe results are not cached.
