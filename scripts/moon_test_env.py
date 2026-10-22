#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/moon_test_env.py — 让 `moon test` 在本机真的能跑（BUG-380 根因修复的常驻入口）。

## 根因（2026-10-22 实测，R54）
`moon test --target js` 会把测试选择面作为**一整段 JSON 参数**交给测试产物：
```
node --enable-source-maps _build/js/debug/test/src/engine/engine.blackbox_test.js '{"package":…,"file_and_index":[…]}}'
```
本机 PATH 上 `node` 解析到 DSH 桌面端的 **`node.cmd` shim**（`%APPDATA%\\dsh-desktop\\harness\\.desktop-bin\\node.cmd`），
参数经 `cmd.exe` 转发时**引号被吞**，于是测试产物收到残缺 JSON：

    failed to parse args:  Unterminated string in JSON at position 175 (line 1 column 176)
    Error: failed to run test for target Js

**同一 payload 对照实验（决定性）**：
| 调用方式 | 结果 |
|---|---|
| `.desktop-bin\\node.cmd` + 同一 payload | **rc=1** `failed to parse args: Expected property name or '}' in JSON at position 1` |
| `C:\\Program Files\\nodejs\\node.exe` + 同一 payload | **rc=0**，正常打出 `----- BEGIN MOON TEST RESULT -----` |

⇒ 坏的不是 moon、不是本仓、更不是测试代码，而是**经由 `.cmd` 垫片转发时丢失的 JSON 引号**。
把该垫片目录从 PATH 移除后：`moon test --target js` = **1387/1387 passed, rc=0（15s）**。

## 这个脚本做什么
1. 递归剔除 PATH 里"含有 `node.cmd` 垫片"的目录（判据是**目录内容**，不是写死路径）；
2. 校验 `node` 现在解析到**真实 `.exe`**（不是 `.cmd`/`.bat`）；解析不到就 rc=2（拒绝出数）；
3. 用清理后的 PATH 跑 `moon test`，把参数原样透传；
4. 按本仓契约出 rc：**0=全绿 / 1=有红 / 2=判据无法自证**，
   并核对汇总行 `Total tests: N, passed: N, failed: 0`（BUG-142：`moon test` 自身退出码不可靠，
   崩了也可能回 0 ⇒ 判绿必须看汇总行，不能只看 rc）。

用法：
  python scripts/moon_test_env.py                 # 全仓
  python scripts/moon_test_env.py src/engine      # 只跑某包（参数原样透传给 moon test）
  python scripts/moon_test_env.py --selftest      # 只验"垫片识别 + 清理"的纯逻辑
  python scripts/moon_test_env.py --dry-run       # 只打印将要执行的环境与命令
"""
import os
import re
import shutil
import subprocess
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SHIM_NAMES = ("node.cmd", "node.bat")


def split_path(path):
    return [p for p in path.split(os.pathsep) if p.strip()]


def is_shim_dir(d):
    """目录里只要放着 node.cmd / node.bat 垫片，就算垫片目录（按内容判定，不写死路径）。"""
    try:
        return any(os.path.isfile(os.path.join(d, n)) for n in SHIM_NAMES)
    except OSError:
        return False


def clean_path(path):
    """返回 (新 PATH, 被剔除的目录列表, 保留列表)。纯函数，便于自检。"""
    kept, dropped = [], []
    for d in split_path(path):
        if is_shim_dir(d):
            dropped.append(d)
        else:
            kept.append(d)
    return os.pathsep.join(kept), dropped, kept


def resolve_node(clean):
    """在清理后的 PATH 里找 node，返回 (路径, 是否真实 exe, 说明)。"""
    exts = os.environ.get("PATHEXT", ".COM;.EXE;.BAT;.CMD").split(";")
    for d in split_path(clean):
        for ext in [""] + [e.lower() for e in exts] + [e.upper() for e in exts]:
            cand = os.path.join(d, "node" + ext)
            if os.path.isfile(cand):
                real = cand.lower().endswith(".exe")
                return cand, real, ("真实 node.exe" if real else "仍是垫片/脚本（不可用）")
    which = shutil.which("node", path=clean)
    if which:
        return which, which.lower().endswith(".exe"), "shutil.which 命中"
    return "", False, "清理后的 PATH 里找不到 node"


def selftest():
    cells = []

    def cell(name, got, want):
        cells.append((name, got == want, "got=%r want=%r" % (got, want)))

    # 用真实临时目录造"垫片目录"与"干净目录"
    import tempfile
    base = tempfile.mkdtemp(prefix="mtea-")
    try:
        shim = os.path.join(base, "bin-shim")
        clean_dir = os.path.join(base, "bin-clean")
        os.makedirs(shim)
        os.makedirs(clean_dir)
        open(os.path.join(shim, "node.cmd"), "w").close()
        open(os.path.join(clean_dir, "node.exe"), "w").close()
        cell("is-shim-dir", is_shim_dir(shim), True)
        cell("is-clean-dir", is_shim_dir(clean_dir), False)
        fake_path = os.pathsep.join([shim, clean_dir, "/does/not/exist"])
        newp, dropped, kept = clean_path(fake_path)
        cell("drops-shim", dropped, [shim])
        cell("keeps-clean", clean_dir in kept, True)
        cell("new-path-lacks-shim", shim not in split_path(newp), True)
        node, real, _why = resolve_node(newp)
        cell("resolves-clean-node", node, os.path.join(clean_dir, "node.exe"))
        cell("marks-real-exe", real, True)
        # 只给垫片目录 ⇒ 必须解析失败（判据自证：不许把垫片当可用 node）
        node2, real2, _ = resolve_node(shim)
        cell("shim-only-not-real", real2, False)
    finally:
        shutil.rmtree(base, ignore_errors=True)

    bad = [(n, w) for n, ok, w in cells if not ok]
    if bad:
        print("SELFTEST FAIL：")
        for n, w in bad:
            print("  - %s：%s" % (n, w))
        return 1
    print("SELFTEST OK（%d 格：垫片目录识别两档 + PATH 清理三档 + node 解析两档）" % len(cells))
    return 0


def main(argv):
    if "--selftest" in argv:
        return selftest()
    args = [a for a in argv if a not in ("--dry-run",)]
    dry = "--dry-run" in argv
    clean, dropped, _kept = clean_path(os.environ.get("PATH", ""))
    node, real, why = resolve_node(clean)
    print("  PATH 垫片目录：%d 个%s" % (len(dropped), ("（" + "; ".join(dropped) + "）") if dropped else ""))
    print("  node 解析：%s（%s）" % (node or "(无)", why))
    if not node or not real:
        print("  FATAL 清理后仍拿不到真实 node.exe ⇒ 拒绝出数（rc=2，不冒用 0/1 两档）")
        return 2
    env = dict(os.environ)
    env["PATH"] = clean
    cmd = ["moon", "test", "--target", "js"] + args
    print("  执行：%s" % " ".join(cmd))
    if dry:
        return 0
    p = subprocess.run(cmd, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace")
    out = (p.stdout or "") + (p.stderr or "")
    tail = [l for l in out.strip().splitlines() if l.strip()][-6:]
    for l in tail:
        print("  | " + l[:150])
    m = None
    for line in out.splitlines():
        mm = re.search(r"Total tests:\s*(\d+),\s*passed:\s*(\d+),\s*failed:\s*(\d+)", line)
        if mm:
            m = mm
    if "failed to parse args" in out:
        print("  判据失败：测试产物收到残缺 JSON（说明 PATH 垫片没清干净或 moon 用了别的 node）")
        return 1
    if m is None:
        print("  判据无法自证：没有汇总行 `Total tests: …` ⇒ rc=2（BUG-142：不许只凭 moon 的退出码判绿）")
        return 2
    total, passed, failed = int(m.group(1)), int(m.group(2)), int(m.group(3))
    print("  汇总：Total tests %d / passed %d / failed %d" % (total, passed, failed))
    if failed != 0 or passed != total:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
