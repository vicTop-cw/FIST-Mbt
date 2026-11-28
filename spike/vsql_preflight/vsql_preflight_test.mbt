// SPDX-License-Identifier: Apache-2.0
// vsql-w3-spike: blackbox test — the preflight gate rejects an illegal
// annotation task and accepts a clean one. This is the W3 acceptance
// criterion ("fist-mbt 能拦住一个非法注解任务") exercised through the
// vsql-mbt dependency as consumed from FIST-Mbt.

///|
test "spike: illegal annotation task is rejected by the preflight gate" {
  let r = preflight_gate("--@var dt\nSELECT id FROM ods.orders WHERE dt = '${dt}';\n")
  assert_false(r.ok)
  assert_true(r.text.has_prefix("E:1 E_VAR_MISSING"))
}

///|
test "spike: unclosed loop task is rejected by the preflight gate" {
  let r =
    preflight_gate(
      "--@var dt 2026-11-28\n--@loop i in 1..3\nSELECT id FROM ods.orders WHERE dt = '${dt}';\n",
    )
  assert_false(r.ok)
  assert_true(r.text.has_prefix("E:2 E_LOOP_UNCLOSED"))
}

///|
test "spike: clean task passes the preflight gate" {
  let r =
    preflight_gate(
      "--@var dt 2026-11-28\nSELECT id FROM ods.orders WHERE dt = '${dt}';\n",
    )
  assert_true(r.ok)
  assert_eq(r.text, "ok")
}

///|
test "spike: core scan_task accepts a well-formed payload" {
  match scan_task("--@var dt 2026-11-28\nSELECT 1;\n") {
    Ok(_) => ()
    Err(e) => abort("unexpected scan error: " + e)
  }
}

///|
test "spike: core scan_task rejects a malformed annotation" {
  match scan_task("--@var dt\nSELECT 1;\n") {
    Ok(_) => abort("expected a scan error")
    Err(e) => assert_true(e.has_prefix("[E_VAR_MISSING]"))
  }
}
