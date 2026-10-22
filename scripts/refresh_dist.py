#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/refresh_dist.py — 刷新仓内发布快照 `dist/fist-mbt.js`（一条命令，幂等）。

**为什么要脚本而不是手改**：`docs/2026-10-20-slave-dev-playbook.md` 明确写着「不能手改 dist/fist-mbt.js
（构建产物）」。但快照又必须与 `moon.mod` 同步，否则 `scripts/mcp_compat_shim.js` 默认连的那份服务端
就是旧版本（实测 v0.3.9 vs moon.mod 0.3.10）。于是把"该怎么刷新"固化成脚本，任何人一条命令可复现。

步骤（与 `.github/workflows/release.yml` 的产物线一致）：
  1) `moon build --target js --release cmd/cli`
  2) `python scripts/patch_esm_main.py <产物>`（注入 createRequire shim，幂等）
  3) 拷贝到 `dist/fist-mbt.js`
  4) 末尾跑 `check_dist_snapshot.py` 自证（版本 == moon.mod）

用法：
  python scripts/refresh_dist.py            # 真刷新
  python scripts/refresh_dist.py --dry-run  # 只打印将执行的步骤与路径
退出码：0 刷新并自证通过 / 1 任一步失败 / 2 环境不完整（没有 moon 或产物缺失，拒绝"假装刷新成功"）
"""
import os
import shutil
import subprocess
import sys

from moon_env_probe import moon_env

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
ARTIFACT = os.path.join(ROOT, "_build", "js", "release", "build", "cmd", "cli", "cli.js")
DIST = os.path.join(ROOT, "dist", "fist-mbt.js")


def run(cmd, cwd=ROOT):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8",
                       errors="replace", env=moon_env())
    return r.returncode, (r.stdout or "") + (r.stderr or "")


def main():
    dry = "--dry-run" in sys.argv[1:]
    steps = [
        ("构建 release 产物", ["moon", "build", "--target", "js", "--release", "cmd/cli"]),
        ("注入 ESM shim", [sys.executable, os.path.join(ROOT, "scripts", "patch_esm_main.py"), ARTIFACT]),
        ("拷贝到 dist", None),
        ("自证版本一致", [sys.executable, os.path.join(ROOT, "scripts", "check_dist_snapshot.py")]),
    ]
    def show(p):
        """跨盘（C:/ 的 python vs E:/ 的仓库）时 relpath 会抛 ValueError——降级为原样显示。"""
        if not os.path.isabs(p):
            return p
        try:
            return os.path.relpath(p, ROOT)
        except ValueError:
            return p

    print("dist 快照刷新计划：")
    for i, (name, cmd) in enumerate(steps, 1):
        print("  %d) %-14s %s" % (i, name, ("复制 %s → dist/fist-mbt.js" % show(ARTIFACT)) if cmd is None
                                   else " ".join(show(c) for c in cmd)))
    if dry:
        print("\n[dry-run] 未执行。")
        return 0

    for name, cmd in steps[:2]:
        rc, out = run(cmd)
        print("[%s] rc=%d %s" % (name, rc, (out.strip().splitlines() or [""])[-1][:120]))
        if rc != 0:
            print("FAIL：%s 失败，未改动 dist（不留下半成品）" % name)
            return 2 if name.startswith("构建") else 1

    if not os.path.isfile(ARTIFACT):
        print("FATAL：产物不存在 %s —— 拒绝「假装刷新成功」" % ARTIFACT)
        return 2
    shutil.copyfile(ARTIFACT, DIST)
    print("[拷贝到 dist] %d 字节" % os.path.getsize(DIST))

    rc, out = run([sys.executable, os.path.join(ROOT, "scripts", "check_dist_snapshot.py")])
    print("[自证版本一致] rc=%d %s" % (rc, (out.strip().splitlines() or [""])[-1][:120]))
    return rc


if __name__ == "__main__":
    sys.exit(main())
