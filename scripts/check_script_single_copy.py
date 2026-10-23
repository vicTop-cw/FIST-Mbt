#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""scripts/check_script_single_copy.py — 「单文件单副本」守卫（R139，副机自立项）。

**为什么要有它**（实测 2026-10-23）：`scripts/fist-gate.py` 曾被三次「手动解冲突」整文件串接成
**4 份副本**（提交 5656cdfb / 8f75bf70 / d5dc918f 各串一次），四个 `# -*- coding` 头、四个
`if __name__ == "__main__"` 块。Python 会按顺序执行模块顶层语句，首个 `__main__` 块里的
`sys.exit(...)` 让进程当场退出 ⇒ **只有最老的一份在执行**，后面的副本（R93 的 whisperer 检查、
TASK-004 的断言修复、R125 的 moon_env……）全是死代码；而所有读数、文档、电池都以为它们在跑。
这类毁伤没有语法错、没有异常、所有守卫照常绿——只有「一个文件里出现第二份副本」这一眼能抓。

**判定面**：`scripts/**/*.py`（本尺自己的目录；整文件串接是本仓实测过的毁伤形状）。
  U1 副本头重复 = `# -*- coding: utf-8 -*-` 出现 ≥2 次（整文件串接的最硬信号）。
  U2 主块重复   = `if __name__ == "__main__":` 出现 ≥2 次（无编码头的串接也逃不掉）。
不判「同名函数重复定义」：`def run` 一类的覆盖在正常重构里合法，误报代价比漏报大。

退出码契约（BUG-369）：0=无违例 / 1=有文件出现第二份副本 / 2=判据无法自证（被检面为空或参数不认）/
4=尺子自己坏了（未捕获异常，绝不冒用 1 那一档）。

用法：
  python scripts/check_script_single_copy.py               # 裸扫 scripts/，可进电池
  python scripts/check_script_single_copy.py --selftest    # 尺子先证明自己会红
"""

from __future__ import annotations

import os
import re
import sys
import tempfile

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS_DIR = os.path.join(REPO_ROOT, "scripts")
HEADER_RE = re.compile(r"^# -\*- coding: utf-8 -\*-\s*$")
MAIN_RE = re.compile(r"^if __name__ == ['\"]__main__['\"]:\s*$")


def rel_posix(path):
    """仓内相对路径用 / 分隔，Windows 与 Linux 读数一致。"""
    try:
        return os.path.relpath(path, REPO_ROOT).replace(os.sep, "/")
    except ValueError:
        return str(path).replace(os.sep, "/")


def py_files(root):
    found = []
    for base, dirs, files in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d != "__pycache__")
        for name in sorted(files):
            if name.endswith(".py"):
                found.append(os.path.join(base, name))
    return found


def scan(root):
    """扫一个目录。返回 (rc, 违例[(rel, headers, mains)], 文件数, 为什么)。"""
    files = py_files(root)
    if not files:
        return 2, [], 0, "被检面为空（%s 下一份 .py 都没枚举到）——判据无法自证" % rel_posix(root)
    bad = []
    for path in files:
        try:
            text = open(path, "r", encoding="utf-8", errors="replace").read()
        except OSError as e:
            return 2, bad, len(files), "读不了 %s：%s" % (rel_posix(path), e)
        lines = text.splitlines()
        headers = sum(1 for line in lines if HEADER_RE.match(line))
        mains = sum(1 for line in lines if MAIN_RE.match(line))
        if headers > 1 or mains > 1:
            bad.append((rel_posix(path), headers, mains))
    return (1 if bad else 0), bad, len(files), ""


_EXECUTED = []


def check(cell, passed, detail=""):
    _EXECUTED.append((cell, passed))
    print(("PASS " if passed else "FAIL ") + cell + (" " + detail if detail else ""))


def selftest():
    def sandbox(files):
        d = tempfile.mkdtemp(prefix="ssc-")
        for name, body in files.items():
            p = os.path.join(d, name)
            parent = os.path.dirname(p)
            if parent:
                os.makedirs(parent, exist_ok=True)
            with open(p, "w", encoding="utf-8") as f:
                f.write(body)
        return d

    # U1：两份编码头 = 整文件串接 ⇒ 红
    d = sandbox({"dup.py": "# -*- coding: utf-8 -*-\nx = 1\n# -*- coding: utf-8 -*-\ny = 2\n"})
    rc, bad, total, _ = scan(d)
    check("U1", rc == 1 and len(bad) == 1 and bad[0][1] == 2, "rc=%d bad=%s total=%d" % (rc, bad, total))

    # U2：没有第二份编码头、但有两个 __main__ 块 ⇒ 同样红（另一种串接形状）
    d = sandbox({"dup2.py": "# -*- coding: utf-8 -*-\nif __name__ == \"__main__\":\n    pass\n"
                             "if __name__ == \"__main__\":\n    pass\n"})
    rc, bad, _, _ = scan(d)
    check("U2", rc == 1 and len(bad) == 1 and bad[0][2] == 2, "rc=%d bad=%s" % (rc, bad))

    # G1：正常单副本不误红
    d = sandbox({"ok.py": "# -*- coding: utf-8 -*-\nx = 1\nif __name__ == \"__main__\":\n    pass\n"})
    rc, bad, _, _ = scan(d)
    check("G1", rc == 0 and not bad, "rc=%d bad=%s" % (rc, bad))

    # Z1：空宇宙自拒（真给 2，不冒用 0）
    d = sandbox({})
    rc, _, _, why = scan(d)
    check("Z1", rc == 2 and "为空" in why, "rc=%d" % rc)

    # Z2：不认识的参数不许当成功（2 号档）
    rc = main(["--bogus"])
    check("Z2", rc == 2, "rc=%d" % rc)

    # L1：真源现状面必须绿——本尺在现状不恒红（否则它只是个装饰）
    rc, bad, total, _ = scan(SCRIPTS_DIR)
    check("L1", rc == 0, "真源 rc=%d 文件=%d bad=%s" % (rc, total, bad[:3]))

    ok = all(passed for _, passed in _EXECUTED)
    cells = " / ".join("%s×1" % c for c, _ in _EXECUTED)
    print("SELFTEST %s（%d 格：%s，清单从已执行格子反解，不手写计数）"
          % ("OK" if ok else "FAIL", len(_EXECUTED), cells))
    return 0 if ok else 1


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if "--selftest" in argv:
        return selftest()
    if argv:
        print("SINGLECOPY=reject 不认识的参数：%s（只认 --selftest）" % " ".join(argv))
        return 2
    rc, bad, total, why = scan(SCRIPTS_DIR)
    if rc == 2:
        print("SINGLECOPY=reject %s" % why)
        return 2
    if rc == 1:
        for rel, headers, mains in bad:
            print("SINGLECOPY=violation %s：编码头 %d 份 / __main__ 块 %d 份——整文件副本串接，"
                  "只有第一份在执行，后面全是死代码" % (rel, headers, mains))
        print("SINGLECOPY=violation %d 份文件出现多副本（被检 %d 份 .py）" % (len(bad), total))
        return 1
    print("SINGLECOPY=clean 被检 %d 份 .py，单副本 %d 份" % (total, total))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as e:  # noqa: BLE001 — 尺子自己坏了走 4 号档，绝不冒用 1
        print("SINGLECOPY=FATAL 尺子自己坏了：%r" % (e,))
        sys.exit(4)
