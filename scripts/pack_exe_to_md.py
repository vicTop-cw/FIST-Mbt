#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
pack_exe_to_md.py —— fist-web-agent 通用打包器（P0 交付物）

把任意 Linux 静态二进制打成单文件 .fist.md 自解压包：
  frontmatter（fist-md:1.0 规范，YAML 子集，可被脚本解析）
  + 使用说明（人 / Agent 通用）
  + 内嵌自解压代码（python3 优先，bash+base64/gzip/coreutils 兜底）
  + payload = base64(gzip(tar(exe)))

用法：
  python pack_exe_to_md.py <binary> <out.fist.md> \
      [--name fist-web-agent] [--version 0.1.0] [--os linux-amd64] \
      [--exposure global] [--port 18646] [--auth auto] \
      [--budget 8] [--split] [--exe-name fist-web-agent] [--tunnel cloudflared]

体积预算：
  payload ≤ 8MB（base64 后约 11MB）默认覆盖主流通道；超限用 --split 分片，
  自解压代码支持多段合并还原。

校验链：
  frontmatter.sha256 = sha256(base64 解码后的 gzip 流)；自解压时先校验再还原，
  失败给出明确错误码（ERR_SHA256 / ERR_B64 / ERR_GZIP / ERR_TAR）。
"""
import argparse
import base64
import gzip
import hashlib
import io
import os
import re
import sys
import tarfile

# ---------------------------------------------------------------------------
# 内嵌自解压代码（python3 优先；bash + base64/gzip/tar 兜底）
# ---------------------------------------------------------------------------
UNPACK_PY = r'''#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# fist-web-agent 自解压还原脚本（python3 优先路径）
# 用法：python3 unpack.py <本md文件> [--run] [--dir 目标目录] [--bind 127.0.0.1:18646] [--tunnel cloudflared]
import argparse, base64, gzip, hashlib, io, os, re, subprocess, sys, tarfile

BEGIN = "<!--PAYLOAD:BEGIN-->"
END = "<!--PAYLOAD:END-->"
PART_RE = re.compile(r"<!--PAYLOAD:PART:(\d+)-->")

def extract_b64(text):
    i = text.rfind(BEGIN)
    if i != -1:
        j = text.rfind(END)
        if j <= i:
            sys.exit("ERR_B64: 结束标记缺失")
        return "".join(text[i + len(BEGIN):j].split())
    # 分片模式：收集所有 PART 块并按序号拼接
    parts = []
    for m in PART_RE.finditer(text):
        idx = int(m.group(1))
        end = text.find("<!--PAYLOAD:PART_END-->", m.end())
        if end == -1:
            sys.exit("ERR_B64: 分片缺少结束标记")
        parts.append((idx, "".join(text[m.end():end].split())))
    parts.sort(key=lambda x: x[0])
    return "".join(p for _, p in parts)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("md", help="承载 payload 的 .fist.md 路径")
    ap.add_argument("--run", action="store_true", help="还原后立即按 frontmatter 启动服务")
    ap.add_argument("--dir", default=".", help="解压目标目录（默认当前目录）")
    ap.add_argument("--bind", default=None, help="覆盖监听地址，如 0.0.0.0:18646")
    ap.add_argument("--tunnel", default=None, help="覆盖隧道，如 cloudflared")
    ap.add_argument("--api-key", default=None, help="显式注入 api-key")
    a = ap.parse_args()

    text = open(a.md, encoding="utf-8").read()

    # 解析 frontmatter（YAML 子集）
    fm = {}
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n", text, re.S)
    if m:
        for line in m.group(1).splitlines():
            if ":" in line:
                k, v = line.split(":", 1)
                fm[k.strip()] = v.strip()

    b64 = extract_b64(text)
    try:
        raw = base64.b64decode(b64)
    except Exception:
        sys.exit("ERR_B64: base64 解码失败")
    expect = fm.get("sha256", "")
    if expect:
        got = hashlib.sha256(raw).hexdigest()
        if got != expect:
            sys.exit(f"ERR_SHA256: 校验失败 {got[:16]}... != {expect[:16]}...")
    try:
        gz = gzip.decompress(raw)
    except Exception:
        sys.exit("ERR_GZIP: gzip 解压失败")
    try:
        tf = tarfile.open(fileobj=io.BytesIO(gz), mode="r:")
        names = tf.getnames()
        tf.extractall(a.dir)
    except Exception:
        sys.exit("ERR_TAR: tar 解包失败")

    exe_name = fm.get("name", "fist-web-agent")
    out = os.path.join(a.dir, exe_name)
    if not os.path.exists(out):
        # 取 tar 中第一个可执行成员
        cand = [n for n in names if not n.endswith("/")]
        if cand:
            out = os.path.join(a.dir, cand[0])
    os.chmod(out, 0o755)
    print(f"OK: 还原 {len(raw)} 字节 -> {out}")

    if a.run:
        port = fm.get("port", "18646")
        exposure = fm.get("exposure", "global")
        bind = a.bind or {"local": f"127.0.0.1:{port}", "lan": f"0.0.0.0:{port}", "global": f"0.0.0.0:{port}"}.get(exposure, f"0.0.0.0:{port}")
        cmd = [out, "--bind", bind]
        if a.api_key:
            cmd += ["--api-key", a.api_key]
        tunnel = a.tunnel or (fm.get("tunnel", "") if exposure == "global" else "")
        if tunnel:
            cmd += ["--tunnel", tunnel]
        print(f"启动: {' '.join(cmd)}")
        subprocess.call(cmd)

if __name__ == "__main__":
    main()
'''

UNPACK_BASH = r'''#!/bin/sh
# fist-web-agent 自解压还原脚本（bash + base64/gzip/tar 兜底路径）
# 用法：sh unpack.sh <本md文件> [--run]
MD="$1"; RUN="$2"
BEGIN=$(grep -n "<!--PAYLOAD:BEGIN-->" "$MD" | tail -1 | cut -d: -f1)
END=$(grep -n "<!--PAYLOAD:END-->" "$MD" | tail -1 | cut -d: -f1)
[ -z "$BEGIN" ] && { echo "ERR_B64: 未找到 payload 起始标记"; exit 1; }
[ -z "$END" ] && { echo "ERR_B64: 未找到 payload 结束标记"; exit 1; }
sed -n "$((BEGIN+1)),$((END-1))p" "$MD" | tr -d '[:space:]' | base64 -d > /tmp/fist-payload.gz || { echo "ERR_B64: base64 解码失败"; exit 1; }
EXPECT=$(sed -n 's/^sha256: *//p' "$MD" | head -1)
GOT=$(sha256sum /tmp/fist-payload.gz | cut -d' ' -f1)
if [ -n "$EXPECT" ] && [ "$GOT" != "$EXPECT" ]; then
  echo "ERR_SHA256: ${GOT:0:16}... != ${EXPECT:0:16}..."; exit 1
fi
gunzip -c /tmp/fist-payload.gz > /tmp/fist-payload.tar || { echo "ERR_GZIP"; exit 1; }
NAME=$(sed -n 's/^name: *//p' "$MD" | head -1)
[ -z "$NAME" ] && NAME="fist-web-agent"
mkdir -p "$(dirname "$NAME")"
tar -xf /tmp/fist-payload.tar --transform="s|.*|$NAME|" || tar -xf /tmp/fist-payload.tar
chmod +x "$NAME"
echo "OK: 还原 -> $NAME"
if [ "$RUN" = "--run" ]; then
  PORT=$(sed -n 's/^port: *//p' "$MD" | head -1)
  [ -z "$PORT" ] && PORT="18646"
  EXP=$(sed -n 's/^exposure: *//p' "$MD" | head -1)
  case "$EXP" in
    local) BIND="127.0.0.1:$PORT" ;;
    *) BIND="0.0.0.0:$PORT" ;;
  esac
  echo "启动: ./$NAME --bind $BIND"
  exec "./$NAME" --bind "$BIND"
fi
'''


def build_launch_templates(exposure, port, tunnel):
    """三档启动模板（写入 md 使用说明）。"""
    tpls = {
        "local": ("local", f"./{{exe}} --bind 127.0.0.1:{port}", "本机 curl http://127.0.0.1:{port}/health"),
        "lan": ("lan", f"./{{exe}} --bind 0.0.0.0:{port}", f"局域网 http://<内网IP>:{port}/health"),
        "global": ("global", f"./{{exe}} --bind 0.0.0.0:{port} --tunnel {tunnel or 'cloudflared'}", f"公网 https://<随机域>.trycloudflare.com/health"),
    }
    return tpls


def pack(binary, out_md, name, version, os_name, exposure, port, auth,
         budget_mb, split, exe_name, tunnel):
    raw = open(binary, "rb").read()
    raw_size = len(raw)
    exe = exe_name or name

    # 1) payload = gzip(tar(exe))，tar 内仅一个成员
    tbuf = io.BytesIO()
    with tarfile.open(fileobj=tbuf, mode="w") as tf:
        info = tarfile.TarInfo(name=exe)
        info.size = len(raw)
        info.mode = 0o755
        tf.addfile(info, io.BytesIO(raw))
    tdata = tbuf.getvalue()
    gzdata = gzip.compress(tdata, compresslevel=9)
    payload_sha = hashlib.sha256(gzdata).hexdigest()
    b64 = base64.b64encode(gzdata).decode("ascii")
    b64_lines = "\n".join(b64[i:i + 76] for i in range(0, len(b64), 76))

    est_md = len(b64) + len(UNPACK_PY) + 1024
    over_budget = len(gzdata) > budget_mb * 1048576
    print("体积预算:")
    print(f"  原始二进制 : {raw_size / 1048576:.2f} MB")
    print(f"  gzip(tar)  : {len(gzdata) / 1048576:.2f} MB  (压缩率 {len(gzdata) / max(raw_size, 1) * 100:.0f}%)")
    print(f"  base64     : {len(b64) / 1048576:.2f} MB")
    print(f"  MD 预估    : {est_md / 1048576:.2f} MB  (预算 {budget_mb} MB)")
    if over_budget and not split:
        sys.exit(f"ERR_BUDGET: payload {len(gzdata)/1048576:.2f}MB 超预算 {budget_mb}MB，请用 --split 分片")

    tpls = build_launch_templates(exposure, port, tunnel)
    fm_lines = [
        "fist-md: 1.0",
        f"name: {name}",
        f"version: {version}",
        f"os: {os_name}",
        f"exposure: {exposure}",
        f"port: {port}",
        f"auth: {auth}",
        "payload: embed",
        f"sha256: {payload_sha}",
    ]
    if tunnel and exposure == "global":
        fm_lines.append(f"tunnel: {tunnel}")

    md = []
    md.append("---")
    md.extend(fm_lines)
    md.append("---")
    md.append("")
    md.append(f"# {name} 自解压服务包 (v{version})")
    md.append("")
    md.append("> 本文件是 fist-web-agent 交付态自建包：在任意 Linux 机器上按下方说明")
    md.append("> 还原并启动，即可获得一个可访问的 web 服务。无需手写任何命令。")
    md.append("")
    md.append("## 使用说明")
    md.append("")
    md.append("1. 将下方「解压还原」代码块保存为 `unpack.py`（或 `unpack.sh` 用于 bash 环境）；")
    md.append("2. 执行 `python3 unpack.py <本md文件> --run` 还原并启动服务；")
    md.append("3. 访问输出中的 /health 验证存活，记录 API 地址与 api-key。")
    md.append("")
    md.append(f"- SHA-256: `{payload_sha}`")
    md.append(f"- 原始大小: {raw_size / 1048576:.2f} MB；payload: {len(gzdata) / 1048576:.2f} MB；MD 整体约 {est_md / 1048576:.2f} MB")
    md.append("")
    md.append("## 解压还原（python3 优先）")
    md.append("")
    md.append("```python")
    md.append(UNPACK_PY)
    md.append("```")
    md.append("")
    md.append("## 解压还原（bash 兜底）")
    md.append("")
    md.append("```bash")
    md.append(UNPACK_BASH)
    md.append("```")
    md.append("")
    md.append("## 启动服务（可见性三档）")
    md.append("")
    for key, (label, cmd, desc) in tpls.items():
        md.append(f"- **{label}**：`{cmd.format(exe=exe)}` → {desc}")
    md.append("")
    md.append("## 载荷（勿编辑）")
    md.append("")
    if split:
        # 分片模式：每块 ~4MB base64
        chunk = 4 * 1048576  # 4MB 字符
        n = 0
        for i in range(0, len(b64), chunk):
            seg = b64[i:i + chunk]
            md.append(f"<!--PAYLOAD:PART:{n}-->")
            md.append("\n".join(seg[j:j + 76] for j in range(0, len(seg), 76)))
            md.append("<!--PAYLOAD:PART_END-->")
            n += 1
        md.append(f"<!-- 共 {n} 片 -->")
    else:
        md.append("<!--PAYLOAD:BEGIN-->")
        md.append(b64_lines)
        md.append("<!--PAYLOAD:END-->")
    md.append("")

    with open(out_md, "w", encoding="utf-8") as f:
        f.write("\n".join(md))
    print(f"已生成: {out_md}")


def main():
    ap = argparse.ArgumentParser(description="通用打包器：任意 Linux 静态二进制 -> .fist.md 自解压包")
    ap.add_argument("binary", help="要打包的 Linux 静态二进制路径")
    ap.add_argument("out_md", help="输出的 .fist.md 路径")
    ap.add_argument("--name", default="fist-web-agent", help="服务名（默认 fist-web-agent）")
    ap.add_argument("--version", default="0.1.0", help="版本号（默认 0.1.0）")
    ap.add_argument("--os", default="linux-amd64", help="目标 OS/架构（默认 linux-amd64）")
    ap.add_argument("--exposure", default="global", choices=["local", "lan", "global"], help="可见性档位（默认 global）")
    ap.add_argument("--port", default="18646", help="服务端口（默认 18646）")
    ap.add_argument("--auth", default="auto", help="认证方式（默认 auto=随机 api-key）")
    ap.add_argument("--budget", type=float, default=8.0, help="payload 体积预算 MB（默认 8）")
    ap.add_argument("--split", action="store_true", help="超预算时启用分片模式")
    ap.add_argument("--exe-name", default=None, help="解压后二进制文件名（默认取 --name）")
    ap.add_argument("--tunnel", default=None, help="global 档隧道工具（默认 cloudflared）")
    a = ap.parse_args()

    if not os.path.isfile(a.binary):
        sys.exit(f"文件不存在: {a.binary}")
    pack(a.binary, a.out_md, a.name, a.version, a.os, a.exposure, a.port,
         a.auth, a.budget, a.split, a.exe_name, a.tunnel)


if __name__ == "__main__":
    main()
