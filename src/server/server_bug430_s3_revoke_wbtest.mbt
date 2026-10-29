///|
/// server_bug430_s3_revoke_wbtest.mbt —— `agent_revoke_key`（BUG-430 / S3 第八段）白盒锁。
///
/// **为什么有这个文件（R134）**：AGENTS 一直声称「白盒锁
/// `src/server/server_bug430_s3_revoke_wbtest.mbt`(4 格)」，但该文件**从未存在过**
/// （`git ls-files` 无此路径、`--diff-filter=D` 也查不到删除记录）——
/// 是**文档指向了一个不存在的锁**。同时全仓对 `agent_revoke_key` 只有两处**间接**提及
/// （`keypin` 的一处报错文案断言 + `keytool` 的一处注释），**没有任何一格验它的行为**。
/// 本文件把这句承诺变成真的：4 格，且全部断言**剔注释后的代码面**（`srv_code_only`），
/// 不靠注释或文案自证（判例-30）。

///|
/// 【锁 1】工具**存在**且 schema 必填 `agent_id`。
test "rv_01_tool_is_registered" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  let src = srv_code_only(raw)
  assert_true(src.contains("\"agent_revoke_key\""))
  assert_true(src.contains("[\"agent_id\"]"))
}

///|
/// 【锁 2】★ **真的把公钥清空**（实现路径格：不是"有描述"，而是"有那次写"）。
/// 断言代码面出现 `agents_set_pubkey(agent_id=fp, pubkey_fp="")` —— 空串即吊销。
/// 变异对照：把 `pubkey_fp=""` 改成任何非空值，本格必红。
test "rv_02_pubkey_is_actually_cleared" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  let src = srv_code_only(raw)
  assert_true(src.contains("agents_set_pubkey(agent_id=fp, pubkey_fp=\"\")"))
}

///|
/// 【锁 3】★ **先读后写**：回读必须发生在清空之前，否则看不出「本来有没有密钥」
/// （`had_key` 恒 false ⇒ 回执说谎）。
/// 判法用**下标比较**而不是 `contains`：两段都在文件里也能通过，只有顺序错了才红。
test "rv_03_read_before_write" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  let src = srv_code_only(raw)
  let read_at = src.find("store.agents_get(fp)")
  let write_at = src.find("agents_set_pubkey(agent_id=fp, pubkey_fp=\"\")")
  let (r, w) = match (read_at, write_at) {
    (Some(a), Some(b)) => (a, b)
    _ =>
      abort(
        "找不到读/写锚点 —— 判据脱锚（先确认这两个调用还在）",
      )
  }
  assert_true(r < w)
}

///|
/// 【锁 4】回执字段与判定口径：`mode` 来自 `@engine.key_revoke_verdict`，
/// 回执含 `revoked` / `had_key` / `revoked_by` 三件，且「本来没有密钥」走的是
/// **成功语义**（`revoked=false` 而不是报错）——这一点在工具描述里承诺过。
test "rv_04_receipt_fields_and_verdict" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  let src = srv_code_only(raw)
  assert_true(src.contains("@engine.key_revoke_verdict(prev_key)"))
  assert_true(src.contains("\"revoked\": Json::boolean(false)"))
  assert_true(src.contains("\"had_key\": Json::boolean(false)"))
  assert_true(src.contains("\"revoked_by\":"))
}
