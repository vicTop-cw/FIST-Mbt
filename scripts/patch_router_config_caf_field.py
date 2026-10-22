#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
批量给 RouterConfig 构造点补 use_caf_memory 字段（P2c 前置步骤）。
用途：model_router.mbt 加了 use_caf_memory: Bool 字段后，所有 struct literal 需补该字段。
只在 `use_laya: <expr>,` 行后追加 `use_caf_memory: <expr>,`（幂等：下一行已有则不重复，重跑不改字节也不刷 mtime）。
"""
import re
import sys
from pathlib import Path


# BUG-58/138 stdout/stderr UTF-8 重配：本脚本 print 非 ASCII，
# Windows 控制台（cp1252/GBK）下不重配会当场 UnicodeEncodeError（check_py_stdout_encoding --all 面）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# 目标文件及其 use_caf_memory 值
FILES = {
    "src/router/model_router_wbtest.mbt": "false",
    "src/router/router_state.mbt": "cfg.use_caf_memory",
}

IDEMPOTENT_RE = re.compile(r"use_caf_memory\s*:")


def patch_lines(lines, value: str):
    """只在 `use_laya:` 行的**下一行还不是** use_caf_memory 时补该字段。

    返回 (新行清单, 补写次数, 匹配到的 use_laya 行数)。
    原实现的门写成 `not IDEMPOTENT_RE.search(line)`，查的是刚匹配到的 `use_laya:` 行本身
    ——那一行永远不含 use_caf_memory ⇒ 门恒真，每跑一次多插一份，同一 struct literal 里出现两个
    同名字段（编译必红），而读数打的是 `rc=0 总计: 18 处` 的绿灯。门因此必须查**下一行**。
    """
    out = []
    count = 0
    matches = 0
    for i, line in enumerate(lines):
        out.append(line)
        m = re.match(r"^(\s*)use_laya:\s*(.+),\s*$", line)
        if not m:
            continue
        matches += 1
        nxt = lines[i + 1] if i + 1 < len(lines) else ""
        if IDEMPOTENT_RE.search(nxt):
            continue
        out.append(f"{m.group(1)}use_caf_memory: {value},")
        count += 1
    return out, count, matches


def patch(path: Path, value: str):
    """落盘只在真要改的时候做：幂等重跑不得改文件字节，也不得刷 mtime（会白触发一次重建）。"""
    content = path.read_text(encoding="utf-8")
    out, count, matches = patch_lines(content.split("\n"), value)
    if count:
        path.write_text("\n".join(out), encoding="utf-8")
    return count, matches


def selftest() -> int:
    """自证尺子会红：幂等、门查下一行、边界与缩进、以及「旧缺陷形状必被抓住」。"""
    fails = []

    def check(name, ok, detail=""):
        print(("ok   " if ok else "FAIL ") + name + ((" :: " + detail) if detail else ""))
        if not ok:
            fails.append(name)

    base = ["  RouterConfig({", "    use_laya: cfg.use_laya,", "    caf_min_evidences: 3,"]
    out1, n1, m1 = patch_lines(base, "cfg.use_caf_memory")
    check("clean-input-inserts-one", n1 == 1 and m1 == 1 and out1[2].strip() == "use_caf_memory: cfg.use_caf_memory,",
          "count=%d matches=%d" % (n1, m1))
    out2, n2, _ = patch_lines(out1, "cfg.use_caf_memory")
    check("second-run-byte-identical", n2 == 0 and out2 == out1, "count=%d" % n2)
    out3, n3, _ = patch_lines(out2, "cfg.use_caf_memory")
    check("third-run-still-identical", n3 == 0 and out3 == out1, "count=%d" % n3)
    out4, n4, m4 = patch_lines(["  use_laya: x,"], "false")
    check("eof-laya-line-no-crash", m4 == 1 and n4 == 1 and out4 == ["  use_laya: x,", "  use_caf_memory: false,"])
    _, n5, m5 = patch_lines(["fn main() {}", "  let a = 1"], "false")
    check("no-laya-face-is-visible", m5 == 0 and n5 == 0, "matches=%d" % m5)
    out6, _, _ = patch_lines(["\tuse_laya: y,"], "false")
    check("indent-preserved", out6[1] == "\tuse_caf_memory: false,", repr(out6[1]))

    # 变异台（不落盘、不碰仓）：把门改回原缺陷形状「查当前行」⇒ 必须每跑一次多插一份，
    # 这一格是自检存在的理由：抓不住旧形状的自检等于没锁。
    def old_guard(lines, value):
        out, c = [], 0
        for line in lines:
            out.append(line)
            m = re.match(r"^(\s*)use_laya:\s*(.+),\s*$", line)
            if m and not IDEMPOTENT_RE.search(line):
                out.append("%suse_caf_memory: %s," % (m.group(1), value))
                c += 1
        return out, c

    b1, bc1 = old_guard(base, "cfg.use_caf_memory")
    b2, bc2 = old_guard(b1, "cfg.use_caf_memory")
    check("mutation-old-guard-red", bc1 == 1 and bc2 == 1 and b2 != b1, "bc1=%d bc2=%d" % (bc1, bc2))

    print("=== 自检 ===")
    print("格数 %d / 失败 %d" % (7, len(fails)))
    if fails:
        print("SELFTEST FAIL: " + " ".join(fails) + "（尺子坏了 ⇒ rc=2，不冒用判红的 1）")
        return 2
    print("SELFTEST OK（7 格：干净输入补一份且落在 use_laya 之后 / 第二次跑逐字节相同 / 第三次跑仍相同 / "
          "末行就是 use_laya 不越界 / 没有 use_laya 面时 matches=0 可见 / 缩进保真 / 变异台把门改回查当前行必红）")
    return 0


def main() -> int:
    if "--selftest" in sys.argv[1:]:
        return selftest()
    if len(sys.argv) > 1:
        print("usage: python scripts/patch_router_config_caf_field.py [--selftest]")
        return 2
    total = 0
    laya_face = 0
    for rel, val in FILES.items():
        p = Path(rel)
        if not p.exists():
            print(f"[FAIL] {rel} 不存在")
            return 1
        try:
            n, matches = patch(p, val)
        except OSError as e:
            print(f"[尺坏] {rel} 读写失败：{e}")
            return 2
        total += n
        laya_face += matches
        print(f"[OK] {rel}: 补 {n} 处")
    if laya_face == 0:
        print("[FAIL] 目标面里一处 `use_laya:` 都没有 ⇒ 补丁对准的已不是当前代码形状，拒绝空转报绿")
        return 1
    if total == 0:
        print(f"总计: 0 处（盘面已对齐，未改任何字节 / 未刷 mtime；重跑安全）")
        return 0
    print(f"总计: {total} 处")
    return 0


if __name__ == "__main__":
    sys.exit(main())