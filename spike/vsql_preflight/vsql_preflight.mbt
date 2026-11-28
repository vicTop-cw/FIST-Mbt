// SPDX-License-Identifier: Apache-2.0
// vsql-w3-spike: package-level preflight gate for FIST-Mbt task publishing.
//
// Minimal spike (PLAN.md W3 #4 / vsql-w3-dev.md): before a SQL task is
// published, run the vsql-mbt preflight gate on its payload. An
// illegal-annotation task is rejected (`ok=false`); a clean task passes. This
// proves vsql-mbt's `core` + `analyze` are consumable as a FIST-Mbt
// dependency with zero third-party deps. Full integration (the publish hook,
// task schema) belongs to the fist-mbt main line, not this spike.
//
// The vsql `core` package is aliased `@vsqlcore` to avoid clashing with the
// FIST-Mbt `src/core` package (both are named `core`).

///|
/// The structured preflight decision for one SQL task payload.
pub struct GateResult {
  ok : Bool
  text : String
}

///|
pub fn GateResult::GateResult(ok : Bool, text : String) -> GateResult {
  { ok, text }
}

///|
/// Direct `core` scan of a task payload — demonstrates the vsql `core`
/// package is consumable as a FIST-Mbt dependency: `Ok` on a well-formed
/// payload, `Err` with the scanner's structured error otherwise.
pub fn scan_task(payload : String) -> Result[Unit, String] {
  match @vsqlcore.scan(payload) {
    Ok(_) => Ok(())
    Err(e) => Err("[" + e.code + "] line " + e.line.to_string() + ": " + e.message)
  }
}

///|
/// Runs the vsql preflight gate over one SQL task payload (annotated-SQL
/// text). Returns `ok=false` when the payload has a scan error or any
/// error-level finding (illegal annotation / unclosed loop / undefined var);
/// warnings are advisory and do not fail the gate (same as the lint CLI).
pub fn preflight_gate(payload : String) -> GateResult {
  let r = @vsqlanalyze.preflight(payload)
  GateResult(r.ok(), @vsqlanalyze.render_preflight_text(r))
}
