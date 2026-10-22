/// ofm_failure_wbtest.mbt —— P0.4 白盒锁：lane 失败归因（`classify_ofm_failure`）
///
/// 钉死的四条硬纪律：
///   1. 401/403 → `InvalidCredential`，**绝不**误归上游故障（P0.3 一旦误归，重试一万次还是 401）；
///   2. 429 → `RateLimit`，5xx → `UpstreamDown`，两者语义不同不得混淆；
///   3. 状态码 ≤0（没拿到 HTTP 响应）→ `NetworkError`，与 `UpstreamDown` 区分；
///   4. 归不出来 → `Unknown`，**绝不猜**成某一种具体归因。
///
/// 与 P0.1 的 `cfg_ofm_*` 同族续编号，这里起 `ofm_f_*`。

///|
test "ofm_f_1_401_403 归凭据类且不被误归上游" {
  assert_eq(
    classify_ofm_failure(401, "invalid_api_key"),
    OfmFailure::InvalidCredential,
  )
  assert_eq(classify_ofm_failure(401, ""), OfmFailure::InvalidCredential)
  assert_eq(
    classify_ofm_failure(403, "permission_denied"),
    OfmFailure::InvalidCredential,
  )
  assert_eq(OfmFailure::InvalidCredential.label(), "INVALID_CREDENTIAL")
}

///|
test "ofm_f_2_429 归限流" {
  assert_eq(
    classify_ofm_failure(429, "rate_limit_exceeded"),
    OfmFailure::RateLimit,
  )
  assert_eq(classify_ofm_failure(429, ""), OfmFailure::RateLimit)
  assert_eq(OfmFailure::RateLimit.label(), "RATE_LIMIT")
}

///|
test "ofm_f_3_5xx 归上游故障" {
  for s in [500, 502, 503, 504, 599] {
    assert_eq(classify_ofm_failure(s, "server_error"), OfmFailure::UpstreamDown)
  }
  assert_eq(OfmFailure::UpstreamDown.label(), "UPSTREAM_DOWN")
}

///|
test "ofm_f_4_网络层与成功边界" {
  // 状态码 ≤0 = 没拿到 HTTP 响应（连接失败/超时/DNS）
  assert_eq(classify_ofm_failure(0, ""), OfmFailure::NetworkError)
  assert_eq(classify_ofm_failure(-1, "server_error"), OfmFailure::NetworkError)
  assert_eq(OfmFailure::NetworkError.label(), "NETWORK_ERROR")
  // 2xx 不是失败：真进来说明调用方传错，归 Unknown 而非猜
  assert_eq(classify_ofm_failure(200, ""), OfmFailure::Unknown)
}

///|
test "ofm_f_5_状态码语义不明时退到 error_code 文本" {
  // 3xx 不直接给语义，走 error.code 二次提示
  assert_eq(
    classify_ofm_failure(302, "invalid_api_key"),
    OfmFailure::InvalidCredential,
  )
  assert_eq(
    classify_ofm_failure(302, "rate_limit_exceeded"),
    OfmFailure::RateLimit,
  )
  // 无任何线索 → Unknown，绝不猜
  assert_eq(classify_ofm_failure(302, ""), OfmFailure::Unknown)
  assert_eq(classify_ofm_failure(302, "something_else"), OfmFailure::Unknown)
}

///|
test "ofm_f_6_其它 4xx 归调用方问题不归上游" {
  assert_eq(
    classify_ofm_failure(400, "invalid_request"),
    OfmFailure::BadRequest,
  )
  assert_eq(classify_ofm_failure(404, ""), OfmFailure::BadRequest)
  assert_eq(classify_ofm_failure(422, "bad_payload"), OfmFailure::BadRequest)
  assert_eq(OfmFailure::BadRequest.label(), "BAD_REQUEST")
}
