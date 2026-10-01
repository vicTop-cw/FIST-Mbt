# FIST-Mbt

> **fist-mbt — the project manager for AI self-driven development.**
> Only two things are polished as first-class objects: **self-driving** and **recursive decomposition** —
> and the project iterates on itself with exactly those two (see the note below).

[![Made with MoonBit](https://img.shields.io/badge/MoonBit-0.1.20260827-blue)](https://www.moonbitlang.com)
[![License](https://img.shields.io/badge/License-Apache--2.0-green)](./LICENSE)
[![Tests](https://img.shields.io/badge/tests-572%2F572-brightgreen)](./src)
[![CI](https://github.com/vicTop-cw/FIST-Mbt/actions/workflows/ci.yml/badge.svg)](https://github.com/vicTop-cw/FIST-Mbt/actions) (js ×2 + native)

**FIST-Mbt** is an **AI commander task-orchestration foundation** rewritten in **pure MoonBit** and exposed as an **MCP Server** — not another agent framework, but an autonomous system that keeps itself moving: the full lifecycle `publish → claim → plan → execute → submit → verify → archive`, plus self-driving review loops, DGM evolution sampling, Omega strong verification, and cross-process watchdog — all surfaced as **129 MCP tools** to any MCP client (Claude Desktop / Cursor / a custom JSON-RPC client).

**Why MoonBit**: task orchestration is inherently correctness-sensitive (state machine, permission matrix, append-only audit, recursive decomposition). MoonBit's strong typing, zero runtime dependencies, and JS+Native cross-compilation let this logic pass **572/572 tests on the JS target** (Windows + Linux CI, measured 2026-09-29) — reproducible on any machine. `moon update && moon test --target js -j 1` and you are up; no Python environment hell.

> It polished itself to a deliverable state using its **own** self-driving + recursive-decomposition pipeline — evidence: `docs/selfdrive-walkthrough.md`.
> "It says so itself" is not evidence: the narrative / proof surface of this project is the companion repository **fist-evidence** <https://github.com/vicTop-cw/fist-evidence> — see the Evidence section below.

---

## Quick Start

```bash
moon update                    # first run: refresh registry index (all deps are public)
moon check
moon test --target js -j 1     # → Total tests: 572, passed: 572, failed: 0
python scripts/patch_esm_main.py            # ESM shim: moonc ≥0.10.14 emits ESM, the SQLite JS stub uses CJS require
node _build/js/debug/build/cmd/cli/cli.js serve   # start the MCP server (STDIO) — `serve` is mandatory, bare run only prints help
```

> Verified on this tree: bare `node _build/js/debug/build/cmd/cli/cli.js` prints the help banner and exits (`serve` is not optional),
> while `… cli.js serve` takes over stdin/stdout as the MCP server. After the black-box install the equivalent command is the
> global `fist serve`. Note that `python scripts/fist.py` is the **CLI gateway** with only two subcommands,
> `list-tools` and `call`; it has **no** `serve` subcommand.

**Requirements**: MoonBit toolchain ≥ 0.1.20260827; **Node.js ≥ 24** for the JS target (the SQLite JS backend relies on `node:sqlite` `returnArrays`; older Node silently returns object rows and reads fail); Native target needs a system SQLite dev library (`libsqlite3-dev` on Linux; `sqlite3.h/sqlite3.lib` + MSVC on Windows — `pwsh ./scripts/native-env.ps1` loads it).

**One-command self-check (for reviewers):**

```bash
python scripts/mcp_smoke.py    # → PASS tools/list → 129 tools … MCP-SMOKE PASS
python scripts/award_demo.py   # → MCP-AWARD-DEMO PASS (capability chain, ends with cleanup → CLEAN)
```

Any MCP client launches the executable over STDIO and starts interacting immediately.

---

## Capabilities

### Lifecycle — nine-state state machine
`publish / claim / plan / execute / submit / verify / reject / retry / pause / resume / archive / delete`. Human sovereignty (only `human_steward` publishes/archives), append-only audit, illegal-transition rejection, optional `docs_check=true` "docs-are-the-implementation" gate at verify.

### Self-driving programming (selfdrive)
`selfdrive_init / append / get / export_tasks / review_tick / review_ready / publish_next / parse_next_tasks` — review → parse → publish loop keeps the project moving with no human in the loop; optionally fully unattended via `watchdog_tick` (+ optional Phi-Accrual probabilistic liveness with `phi_gate`).

### Omega strong verification (optional, off by default)
Corpus-driven verification: `spec_author` creates the corpus → `verifier` reviews and challenges it → execution is gated until the corpus passes → the verifier re-checks deliverables against the corpus → hard round cap with escalation (no infinite loops).

### Scheduling & budget — mechanism family
`dag_slack` (PERT/CPM) → `dag_mc` (Monte-Carlo completion distribution) → `dag_cost_route` (STAR cost routing) → `cost_budget_split` (ZEBRA budget slicing) → `executor_route` / `executor_auction` (trust-weighted routing / Agora confidence auction) → `progress_gate` (PROGROUTER budget-vs-progress gate).

### Reliability
`phi_accrual` (probabilistic failure detection) → `saga_register / saga_rollback / saga_repair` (durable compensation, local scope control) → `plan_revise` (feedback-driven replanning, keep/rework/ready) → `goal_drift_check` (drift + redundancy detection) → `health_check` (SRE four golden signals) → `circuit_fail / circuit_succeed / circuit_status` (circuit breaker: Closed/Open/Half-Open fail-fast).

### Governance & scale
`audit_permission / audit_log`, multi-tenant namespaces (`store_open / store_list / store_close`, scratch isolation), `call_log` invocation tracing, bug report/fix loop, cost stats & budget checks.

### Self-evolution
`memory_consolidate / gc / link` + `evolve_distill / lesson / critic / sample / snapshot / submit / asset_register` — verified deliverables are distilled into principles, failures become lessons, and both are injected at plan/claim time (`inject` parameter). A project that learns from itself.

### Project map — one-glance orientation
`fist://map` resource (machine-readable tool groups + repo map), `board_ascii` live board, `status_summary` pulse, `project_health` + `health_check`. An agent finds everything on first read — no hunting through the repo.

---

## Why It Is a Better AI Project-Management Tool

The core value is **recursive decomposition of complex tasks made observable and controllable**:

- every task is a real, queryable, stateful entity — no hallucinated progress;
- DAG dependency + scheduling + budget + cost routing turn "who does what when" into a computable plan;
- self-driving review, watchdog, sagas, and circuit breakers keep long-running autonomous pipelines from stalling or cascading;
- self-evolution closes the loop: the tool absorbs what works from each verified delivery.

Everything is reproducible: one command re-runs the 572-test JS suite, the smoke test, and the full capability-chain demo.

---

## Architecture

```
FIST-Mbt/
├── cmd/cli          # STDIO MCP server entry (moon run cmd/cli)
├── cmd/cli           # CLI entry (moon run cmd/cli/main)
├── src/core/         # domain entities + nine-state machine + DAG depends_on
├── src/store/        # persistence: Store abstraction, SQLite impl, multi-tenant
├── src/engine/       # FistEngine business logic + DAG ext + decomposition
├── src/ops/          # operations: audit, heartbeat, heal, watchdog, cleanup
├── src/omega/        # explainable spec/gate/check
└── src/server/       # MCP assembly: 129 tools + 3 resources + 2 prompts
```

Pure MoonBit; no Rust/C wrappers. Protocol layer: [`colmugx/mcp`](https://mooncakes.io/colmugx/mcp) (Apache-2.0, protocol 2026-07-28). Domain core (`core/store/engine`) is separated from the protocol layer for clean unit testing.

---

## Testing

- **572/572** tests green on the JS backend (Windows; first measured 2026-09-28, re-confirmed 2026-09-29 on this working tree). The native track measured **572/572** on WSL (Linux, ubuntu-22.04) on 2026-10-01 **with build residue in the working tree**, but the *same commit* checked out clean (`git archive HEAD`) makes the native test binary die on a signal — root cause is the dependency's native FFI (ledger BUG-133), and `scripts/blackbox/e2e_native_heap_probe.py` is the judge for whether that is still true. Do not read either number as a dual-target green. Since R107 the suite includes **property tests** (`moonbitlang/core/quickcheck`): random inputs validate invariants (slice arity/prefix, difficulty monotonicity, Task transition discipline claim/execute/reopen/split/submit/reject) with fixed seeds. Since R109 a **transition-contract guard** (`tx_contract`, Design by Contract: precondition/invariant/postcondition read-only pre-check — any failure rejects the batch, state A stays stable, nothing persisted). Since R111 a **feedback convergence** tool (`eval_feedback`, Evaluator-Optimizer schema: free-text feedback normalized into Defects/Evidence/Fix/Acceptance with a deterministic pass/fail verdict) — reproducible on any machine.
- CI three tracks (js ubuntu / native ubuntu / js windows) with live badges.
- Guard family: `check_tools_sync` (129 tools aligned) / `check_test_sync` (572 aligned — sweeps **every** current-state doc, not a 4-file whitelist; `--selftest` proves the judge itself can go red) / `check_badge` / `check_scripts_index` / `map_verify` / `cleanup --check` (repo cleanliness gate).

---

## Evidence (narrative companion repo)

Saying "it works" is not evidence — this project's proof surface is a separate repository,
[fist-evidence](https://github.com/vicTop-cw/fist-evidence) (public since 2026-09-27): three controlled experiments
(A/B: orchestrated self-driving vs bare run; three-way merge adjudication with self-corrected attribution;
complexity ladder including a caught bare-run hallucination) plus ten real-project drive instances spanning eight
projects. The original reports, run logs and judge tests are reproducible verbatim there
(`stories/experiment-0*.md`, `stories/evidence/`, `cases/cases.md` — those paths live in that repo; this repo has no `stories/` directory).
It is the physical form of this project's own rule "evidence ladder at least L4 — only measured counts".

---

## Known Boundaries (honest notes)

- JS backend prints Node's `ExperimentalWarning: SQLite is an experimental feature` on Node ≥ 24 — harmless, ignorable.
- Windows native test may rarely hit `0xc0000374` (heap race in the local native SQLite stub) even with `-j 1`; the authoritative stability gate is the JS backend (Node ≥ 24, 572/572 measured on Windows).

---

## License

Apache-2.0

> Full Chinese documentation (tools reference, state machine diagram, HTTP/SSE bridge, FAQ): [README.md](./README.md).
