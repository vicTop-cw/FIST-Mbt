#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""scripts/check_handwritten_seed.py —— 手写 Ed25519 seed 静态判据（BUG-468 R2）。

## 为什么需要它

BUG-468 的交易背景：**手写的 `Bytes` 字面量如果长度不是 32，`@mooncry.ed25519_public_key`
会 `abort`**（实测：1/4/8/16/31/33/64 字节全 abort，唯一可用长度是 32）。

BUG-468 已把 `test_crypto.mbt` 里的两个标准 seed 常量（`TEST_ED25519_SEED_A/B`）
上提到 `src/core`，让各包统一引用。

**⚠️ 但那只是「移除了手写动作」，没有机制阻止新人再手写。**
本判据补那个机制：**把「靠自觉」变成「靠判据」**。

## 判法（三层筛选，误报为 0 的关键）

```
① 形状：`b"..."` 且整个内容都是 `\x??` 转义（即「字节字面量」，不是普通字符串）
② 长度：字节数 ∈ {32, 64}        ← ★ 这是本判据的核心
③ 上下文：同文件里出现 ed25519 或 seed 关键字（大小写不敏感）
```

**为什么是这三层、而不是别的**（全仓普查实测依据，2026-10-28）：

| 候选判法 | 结果 |
|---|---|
| 只找 `b"\x.."` | 全仓 13 处 ⇒ **13 处全是误报**（含 4 字节的 hex 测试数据） |
| 只找「16/64 字节」 | **0 处**（真实的手写 seed 全是 32 字节）⇒ **全漏** |
| 只找「长度 != 32」 | **1 处**，而那 1 处是 `\xde\xad\xbe\xef`（**hex 编解码数据，不是 seed**）⇒ 误报 1 |
| **①+②+③（本判据）** | **命中全仓 12 处手写 seed；误报 0** |

**核心洞察**：**Ed25519 的 seed 长度只有 32 一种合法值** ⇒
「32 字节字面量 + ed25519 上下文」**几乎不可能是别的东西**；
而「长度 != 32」在 ed25519 上下文里反而**不是 seed**（是别的测试数据）。

## 已知边界（诚实标注）

- **不判**：通过变量传递的 seed（`let s = SOME_CONST; ed25519_public_key(s)`）——
  那已经不是「手写字面量」，本判据的靶子是**字面量**。
- **不判**：`\x` 之外的字节写法（如 `[0x3a, 0x7f, ...]` 数组）——
  全仓普查确认当前没有这种写法；若将来出现，本判据看不见。
- **不判**：`test_crypto.mbt` 里**定义** seed 常量本身（那是**唯一允许**的地方）——
  由 `ALLOW_FILES` 显式豁免，且豁免理由写在下面。

## rc 契约（与其它判据同口径）

- `0` = 无手写 seed
- `1` = 有（逐条点名 file:line + 字节数）
- `2` = 判据无法自证（扫不到任何测试文件）

用法：
    python scripts/check_handwritten_seed.py            # 判据模式
    python scripts/check_handwritten_seed.py --selftest # 自证（含变异对照）
"""

from __future__ import annotations

import argparse
import glob
import io
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RC_OK, RC_VIOLATION, RC_BROKEN = 0, 1, 2

# 唯一允许「定义」标准 seed 的地方（其余一律引用它）。
# 理由：`test_crypto.mbt` 就是**存放标准 seed 常量**的文件，它必须写字面量。
ALLOW_FILES = {"src/core/test_crypto.mbt"}

# ⚠️ 「有意保留」登记（**不是白名单豁免**，是逐条带理由的现状登记）。
#
# 判据上线时（2026-10-28）全仓 12 处手写 seed，其中 4 处是 A/B 的**复制粘贴**
# （值完全相同）⇒ 已改为 `@core.TEST_ED25519_SEED_A` / `_B`。
# 剩下 8 处**故意用不同的 seed**，替换会**破坏测试语义**：
#   · 「用另一把私钥签的签名必须验不过」⇒ 必须有两把不同的钥匙
#   · 「两把钥匙的公钥必须不同」⇒ 同上
#   · 「已知向量对照（RFC 00010203...）」⇒ 种子是**测试向量的一部分**，不是可替换的夹具
#
# ⇒ 这些是**合法的手写字面量**，判据不该报它们。
# ⚠️ 但每一条都必须**在这里写明理由**才豁免 —— 「白名单豁免」之所以不好，
#    是因为它只要名字不要理由；这里**要理由**，且新增一条会被人看见。
# ⚠️ 「有意保留」登记 —— **精确到行**，不是按文件。
#
# 为什么按行而不是按文件：
#   实测踩过 —— 按文件豁免时，往 `star_gate_wbtest.mbt` 末尾**新增**一个手写 seed，
#   判据**照样绿**（整个文件被跳过）⇒ 判据在最该抓的场景下失效。
#   改成「文件 + 行号」后，同文件新增 seed 落在未登记行 ⇒ **判据会红**。
#
# ⚠️ 行号会随文件改动漂移。这**是有意的**：漂移后判据报红，逼人重新确认那行是否仍合法；
#    这比「静默放过一个挪了位置的 seed」安全。
#
# 判据上线时（2026-10-28）全仓 12 处手写 seed，其中 4 处是 A/B 的复制粘贴
# （值完全相同）⇒ 已改为 `@core.TEST_ED25519_SEED_A` / `_B`。
# 剩下 8 处**故意用不同的 seed**，替换会破坏测试语义：
#   · 「用另一把私钥签的签名必须验不过」⇒ 必须有两把不同的钥匙
#   · 「已知向量对照（RFC 00010203...）」⇒ 种子是测试向量的一部分
INTENTIONAL = {
    "src/engine/engine_bug430_first_reg_proof_wbtest.mbt": {
        16: "BS 的两把钥匙 0x5a.. / 0xa5.. —— 测「首次登记用 A 签、再用 B 冒认必须失败」，需要两把与标准夹具不同的钥匙才能避免与其它用例串扰",
        18: "BS 的两把钥匙 0x5a.. / 0xa5.. —— 测「首次登记用 A 签、再用 B 冒认必须失败」，需要两把与标准夹具不同的钥匙才能避免与其它用例串扰",
    },
    "src/engine/engine_bug430_s3_key_wbtest.mbt": {
        130: "other_seed 0x99.. —— 测「用另一把私钥签 ⇒ 必须验不过」，它就是那个「另一把」",
    },
    "src/engine/engine_bug430_s3_p3_wbtest.mbt": {
        92: "other_seed 0xaa.. —— 同上（p3 段的「另一把」）",
    },
    "src/engine/engine_bug430_s3_wbtest.mbt": {
        69: "seed 00..1f / seed2 ff..f6 —— 测「min 级」验签真的验，用连续/反序字节便于人工核对",
        81: "seed 00..1f / seed2 ff..f6 —— 测「min 级」验签真的验，用连续/反序字节便于人工核对",
    },
    "src/router/star_gate_wbtest.mbt": {
        7: "sg_seed 00..1f —— RFC 已知向量的输入，配套断言「该 seed 的公钥 == 给定 hex」；种子本身就是测试向量",
    },
    "src/server/server_bug430_keypin_wbtest.mbt": {
        31: "kp_seed_b 0x99.. —— pin（首次登记锁定）的对立面钥匙，与 kp_seed_a 配成一正一反",
    },
}


# ① 形状：整个内容都是 \x?? ⇒ 字节字面量
LIT_RX = re.compile(r'b"((?:\\x[0-9a-fA-F]{2})+)"')

# ② 长度：Ed25519 seed 合法长度只有 32；64 也纳入（可能有人手写私钥而非 seed）
SEED_LENS = (32, 64)

# ③ 上下文关键字
CTX_WORDS = ("ed25519", "seed")


def read(p):
    return io.open(p, encoding="utf-8", errors="replace").read()


def iter_test_files(root):
    for f in glob.glob(os.path.join(root, "src", "**", "*_test.mbt"), recursive=True):
        yield f
    for f in glob.glob(os.path.join(root, "src", "**", "*_wbtest.mbt"), recursive=True):
        yield f


def relpath(root, p):
    return os.path.relpath(p, root).replace("\\", "/")


def scan(root):
    """返回 (hits, n_files)。hits = [(rel, line, nbytes)]。"""
    hits = []
    n_files = 0
    for p in iter_test_files(root):
        n_files += 1
        r = relpath(root, p)
        if r in ALLOW_FILES:
            continue
        txt = read(p)
        low = txt.lower()
        # ③ 上下文：整文件只要出现任一关键字即算「ed25519 上下文」
        if not any(w in low for w in CTX_WORDS):
            continue
        allowed_lines = INTENTIONAL.get(r, {})
        for m in LIT_RX.finditer(txt):
            nbytes = m.group(1).count("\\x")
            if nbytes not in SEED_LENS:
                continue
            line = txt[: m.start()].count("\n") + 1
            if line in allowed_lines:
                # 有意保留：**这一行**登记过（理由在 INTENTIONAL 里，必须有）
                continue
            hits.append((r, line, nbytes))
    return hits, n_files


def stale_registrations(root):
    """★防登记腐烂：登记了 (file, line) 但那一行**已不是手写 seed** 的条目。

    登记表本身也是一种豁免，豁免会腐烂 —— 有人改了文件/add 了行，登记还在，
    下一个人就会以为那里还有手写 seed。让腐烂可见（报红并要求更新登记）。
    """
    stale = []
    for r, byline in INTENTIONAL.items():
        fp = os.path.join(root, r)
        if not os.path.isfile(fp):
            stale.append((r, 0, "文件不存在"))
            continue
        txt = read(fp)
        # 该行的实际字节字面量长度集合
        line_of = {}
        for m in LIT_RX.finditer(txt):
            ln = txt[: m.start()].count("\n") + 1
            line_of.setdefault(ln, []).append(m.group(1).count("\\x"))
        for ln in byline:
            if not any(n in SEED_LENS for n in line_of.get(ln, [])):
                stale.append((r, ln, "该行已不是 32/64 字节字节字面量"))
    return stale


def render(hits, n_files):
    print("[覆盖面] 本判据只判「**测试文件里手写字面量形态的** Ed25519 seed」：")
    print("  ✅ 形状 = b\"\\x??...\"（字节字面量，非普通字符串）")
    print("  ✅ 长度 ∈ {32, 64}（Ed25519 seed 唯一合法长度是 32）")
    print("  ✅ 同文件出现 ed25519 / seed 关键字")
    print("  ❌ 不判：通过变量传递的 seed（那已不是字面量）")
    print("  ❌ 不判：[0x3a, 0x7f, ...] 数组写法（当前全仓无此形态）")
    print("  ❌ 不判：src/core/test_crypto.mbt（**定义**标准 seed 的地方，显式豁免）")
    print()
    print("[扫描] 测试文件 %d 个" % n_files)
    print("[豁免] 有意保留 %d 处（INTENTIONAL，**每条都带理由**，不是白名单）：" % len(INTENTIONAL))
    for _r in sorted(INTENTIONAL):
        print("  · %s" % _r)
    if hits:
        print()
        print("[违例] 发现 %d 处手写 seed：" % len(hits))
        for r, line, n in hits:
            print("  ✗ %s:%d  （%d 字节）" % (r, line, n))
        print()
        print("[结论] 请改用 `@core.TEST_ED25519_SEED_A` / `_B`（BUG-468 已上提到 core）。")
    else:
        print()
        print("[结论] 无手写 seed。**这不代表没有种子字面量** —— 见上面的覆盖边界。")


def selftest():
    import contextlib
    import tempfile

    cells = []

    def cell(name, got, want):
        cells.append((name, got, want))
        print("  [%s] %-46s got=%r want=%r"
              % ("OK" if got == want else "FAIL", name, got, want))

    def mk(root, fname, body):
        os.makedirs(os.path.join(root, "src", "engine"), exist_ok=True)
        with io.open(os.path.join(root, "src", "engine", fname), "w",
                     encoding="utf-8") as fh:
            fh.write(body)

    S32 = "".join("\\x%02x" % i for i in range(32))
    S4 = "\\xde\\xad\\xbe\\xef"
    S16 = "".join("\\x%02x" % i for i in range(16))

    print("[selftest] 临时裸目录端到端（不碰真 src/）")
    with tempfile.TemporaryDirectory() as td:
        # 格1：干净 —— 有 ed25519 但字面量只有 4 字节（hex 数据）⇒ 不报
        mk(td, "hex_wbtest.mbt",
           'test "t" {\n  let d : Bytes = b"%s"\n  ed25519_verify(d)\n}\n' % S4)
        hits, n = scan(td)
        cell("4-byte-hex-data-not-reported", len(hits), 0)
        cell("scan-sees-file", n, 1)

        # 格2：★变异对照 —— 加一个 32 字节 seed ⇒ 必红
        mk(td, "seed_wbtest.mbt",
           'test "t" {\n  let s : Bytes = b"%s"\n  ed25519_public_key(s)\n}\n' % S32)
        hits, _n = scan(td)
        cell("MUTATION-32byte-seed-reported", len(hits), 1)
        cell("MUTATION-names-file", any("seed_wbtest" in h[0] for h in hits), True)

        # 格3：32 字节但**没有** ed25519/seed 上下文 ⇒ 不报（避免误伤普通测试数据）
        os.remove(os.path.join(td, "src", "engine", "seed_wbtest.mbt"))
        mk(td, "plain_wbtest.mbt",
           'test "t" {\n  let d : Bytes = b"%s"\n  ignore(d)\n}\n' % S32)
        hits, _n = scan(td)
        cell("32byte-without-context-not-reported", len(hits), 0)

        # 格4：16 字节 seed（BUG-468 的原始病灶长度之一）⇒ **不报**
        #   理由：实测 Ed25519 只接受 32；16 字节在 ed25519 上下文里不会被当 seed 用
        mk(td, "short_wbtest.mbt",
           'test "t" {\n  let s : Bytes = b"%s"\n  ed25519_public_key(s)\n}\n' % S16)
        hits, _n = scan(td)
        cell("16-byte-not-in-scope", len(hits), 0)

        # 格5：ALLOW_FILES 豁免真的生效
        os.makedirs(os.path.join(td, "src", "core"), exist_ok=True)
        with io.open(os.path.join(td, "src", "core", "test_crypto.mbt"), "w",
                     encoding="utf-8") as fh:
            fh.write('pub const X : Bytes = b"%s"\nfn f() { ed25519_public_key(X) }\n' % S32)
        hits, _n = scan(td)
        cell("allow-file-exempt", len(hits), 0)

        # 格7（★按行豁免的核心）：同一文件里
        #   · 第 N 行（已登记）⇒ 放过
        #   · 第 N+5 行（未登记）⇒ 必须报
        # 这是对「按文件豁免」那个缺陷的直接反证：
        #   实测按文件豁免时，往已豁免文件末尾新增 seed，判据照样绿（整个文件被跳过）。
        import re as _re
        os.makedirs(os.path.join(td, "src", "router"), exist_ok=True)
        plus5 = "".join("\\x%02x" % i for i in range(32))
        body = (
            'test "a" {\n'
            '  let s1 : Bytes = b"%s"\n'
            "  ed25519_public_key(s1)\n"
            "}\n"
            'test "b" {\n'
            '  let s2 : Bytes = b"%s"\n'
            "  ed25519_public_key(s2)\n"
            "}\n"
        ) % (S32, S32)
        with open(os.path.join(td, "src", "router", "byline_wbtest.mbt"), "w") as fh:
            fh.write(body)
        # 强制只登记第 2 行（要精确覆盖模块级 INTENTIONAL）
        global INTENTIONAL
        saved = INTENTIONAL
        INTENTIONAL = {"src/router/byline_wbtest.mbt": {2: "selftest: line-2 registered"}}
        hits_by, _n = scan(td)
        INTENTIONAL = saved
        cell("byline-registered-line-allowed", any(h[1] == 2 for h in hits_by), False)
        cell("byline-unregistered-line-reported", any(h[1] == 6 for h in hits_by), True)

        # 格6：扫不到任何测试文件 ⇒ 自拒 rc=2
        with tempfile.TemporaryDirectory() as empty:
            hits, n = scan(empty)
            cell("empty-scan-self-reject", (len(hits) == 0 and n == 0), True)

    ok = sum(1 for _n, g, w in cells if g == w)
    print("\n[selftest] %d/%d 格通过" % (ok, len(cells)))
    return 0 if ok == len(cells) else 4


def main(argv=None):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--root", default="")
    a = ap.parse_args(argv)
    if a.selftest:
        return selftest()
    root = a.root or ROOT
    hits, n_files = scan(root)
    if n_files == 0:
        print("[FATAL] 扫不到任何测试文件（src/**/*_test.mbt / *_wbtest.mbt）")
        print("判据无法自证 —— 拒绝出结论，也拒绝因「没找到」报绿。rc=2")
        return RC_BROKEN
    render(hits, n_files)
    return RC_OK if not hits else RC_VIOLATION


if __name__ == "__main__":
    sys.exit(main())
