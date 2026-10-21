/// rhop_poll：单拍强制轮询（异机 / 网络 FS / 无 watcher 兜底）。
/// 与 @rhop.from_filesystem_with 同一解码纪律，但把"一拍"做成可重复调用的函数：
/// 扫描 dir 下 .rhop，按完整路径去重，坏信封 / 坏密文 / 版本不符静默跳过。

///|
fn rn_full_path(dir : String, name : String) -> String {
  if dir.has_suffix("/") || dir.has_suffix("\\") {
    dir + name
  } else {
    dir + "/" + name
  }
}

///|
/// 解码单个 .rhop 文本；任一步失败返回 None（静默跳过是协议约定）。
fn[T : @rhop.RhopCipher] rn_decode(
  text : String,
  cipher : T,
) -> @rhop.RhopPacket? {
  let env = match @rhop.RhopEnvelope::decode(text) {
    Err(_) => return None
    Ok(e) => e
  }
  if env.v != 1 {
    return None
  }
  match cipher.decrypt(env.ct) {
    None => None
    Some(plain) =>
      match @rhop.RhopPacket::from_json_text(plain) {
        Err(_) => None
        Ok(pkt) => Some(pkt)
      }
  }
}

///|
/// 强制轮询一拍：返回本拍新增且解码成功的消息。
/// seen 记完整文件路径，跨拍保留（同一文件只消费一次）。
pub fn[T : @rhop.RhopCipher] rhop_poll_once(
  dir : String,
  cipher : T,
  seen : @ref.Ref[@hashset.HashSet[String]],
) -> Array[@rhop.RhopPacket] {
  let out : Array[@rhop.RhopPacket] = []
  let names = @fs.read_dir(dir) catch { _ => [] }
  for name in names {
    if !name.has_suffix(".rhop") || name.has_suffix(".rhop.tmp") {
      continue
    }
    let full = rn_full_path(dir, name)
    if seen.val.contains(full) {
      continue
    }
    seen.val.add(full)
    let text = @fs.read_file_to_string(full) catch { _ => "" }
    if text == "" {
      continue
    }
    match rn_decode(text, cipher) {
      Some(pkt) => out.push(pkt)
      None => ()
    }
  }
  out
}
