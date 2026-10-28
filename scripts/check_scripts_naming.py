#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""scripts/check_scripts_naming.py — scripts/ 命名的词法门（TASK-008 第一批，R95）。

**为什么要有它**：TASK-008 的原口径是「~50 个无前缀脚本，改名 + 更新全部引用」。实测两件事把它拆开：
①那 50 份里 29 份的角色写在**后缀**上（`*_verify.py` / `*_probe.py` / `*_demo.py` / `*_smoke.py`），
按「看文件名猜不出用途」这条判据它们本来就合格 —— 只看前缀会把演示件和验证件一起算成债，
读数虚高一倍，后面真债反而没人排；
②剩下 16 份真债的改名成本是 1224 处引用，其中 **944 处落在 `memory/` `reports/` `stories/` `docs/`
归档面** —— 那些文件记的是「当时真跑过的命令」，为一次改名回写它们，就是把记录改成事后叙述。
所以本判据**不替 owner 决定改不改名**，它只做一件必须有人做的事：把债钉成一个只许下降的数，
让「改一批、少一批」这一步可验证，并且挡住新入场的无角色名。

**词法真源在文档，不在代码**：角色前缀表与后缀表从 `scripts/NAMING.md` 的
`naming-roles-prefix:` / `naming-roles-suffix:` 两条 anchor 行现读。判据里不抄第二份清单 ——
代码与文档各持一份词法，就是下一颗漂移雷（BUG-373 那类「两把尺各执一词」的同形）。

**判定面（两条，共用一个棘轮口径、只许下降）**：
  N1 = `scripts/` 顶层 `.py` 里既不带角色前缀、也不带角色后缀（后缀按 stem 尾段比）的份数。
  N2 = 同一宇宙里 basename 含 `-` 的份数（连字符模块不可 import，shell 与 Python 切的词还不一样）。
**只报不判、必须出数**：
  C 子目录同形份数 —— 本轮不判（TASK-008 把子目录列为低优先级），但不打印就等于把 16 冒充成全仓总数。
自拒（真给 2，绝不冒用 1）：宇宙为空 / `NAMING.md` 读不到 / 两条 anchor 任一行解析不到词。
读不到词法却报「都合规」，是 J10 点名的最便宜假绿。

用法：
  python scripts/check_scripts_naming.py                 # 全量（判定面 ≤ 棘轮上限 ⇒ 0）
  python scripts/check_scripts_naming.py --show          # N1/N2 名单 + C 面读数
  python scripts/check_scripts_naming.py --selftest      # 合成夹具 + 真源码对照，格子数由实现反解
退出码：0=判定面在棘轮上限内 / 1=判定面超限（N1 或 N2 超） / 2=判据无法自证（宇宙或词法读不到，FATAL）。
"""
import argparse
import io
import os
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS_DIR = os.path.join(ROOT, "scripts")
NAMING_DOC = os.path.join(SCRIPTS_DIR, "NAMING.md")

# 棘轮上限：必须 == 现状读数。下降要随改名同批下调，任何一条新债都会顶穿上限。
N1_CEILING = 16
N2_CEILING = 4

PREFIX_ANCHOR = "naming-roles-prefix:"
SUFFIX_ANCHOR = "naming-roles-suffix:"


def read_roles(doc_path):
    """从 NAMING.md 现读两份词表。返回 (prefixes, suffixes, problems)。"""
    if not os.path.isfile(doc_path):
        return [], [], ["读不到 NAMING.md：%s" % doc_path]
    with io.open(doc_path, encoding="utf-8", errors="replace") as f:
        text = f.read()
    roles = {}
    for anchor in (PREFIX_ANCHOR, SUFFIX_ANCHOR):
        line = None
        for ln in text.splitlines():
            if anchor in ln:
                line = ln
                break
        if line is None:
            return roles.get(PREFIX_ANCHOR, []), roles.get(SUFFIX_ANCHOR, []), ["NAMING.md 缺 anchor 行：%s" % anchor]
        body = line.split(anchor, 1)[1]
        words = [w.strip() for w in body.replace("`", "").split(",")]
        roles[anchor] = [w for w in words if w and all(ch.isalnum() or ch in "_-" for ch in w)]
        if not roles[anchor]:
            return roles.get(PREFIX_ANCHOR, []), roles.get(SUFFIX_ANCHOR, []), ["anchor 行解析到 0 个词：%s" % anchor]
    return roles[PREFIX_ANCHOR], roles[SUFFIX_ANCHOR], []


def universe(dir_path):
    """现读 `scripts/` 顶层与子目录的 .py 文件名（不做 git 依赖，电池里离线可跑）。"""
    top, sub = [], []
    if not os.path.isdir(dir_path):
        return top, sub
    for fn in sorted(os.listdir(dir_path)):
        p = os.path.join(dir_path, fn)
        if os.path.isfile(p) and fn.endswith(".py"):
            top.append(fn)
    for dp, dn, fns in os.walk(dir_path):
        if os.path.abspath(dp) == os.path.abspath(dir_path):
            continue
        for fn in sorted(fns):
            if fn.endswith(".py"):
                sub.append(os.path.relpath(os.path.join(dp, fn), dir_path).replace("\\", "/"))
    return top, sub


def census(names, prefixes, suffixes):
    """纯函数：按词法给一份宇宙挑出 N1（无角色名）与 N2（连字符名）。
    分类一律取 basename —— 子目录点名形如 `blackbox/check_foo.py`，拿整条路径比前缀会把
    已带角色的尺算成债（C 面虚高，读数就成了假的）。"""
    roleless, hyphen = [], []
    for fn in names:
        base = os.path.basename(fn)
        stem = base[:-3]
        has_role = stem.startswith(tuple(prefixes)) or stem.endswith(tuple(suffixes))
        if not has_role:
            roleless.append(fn)
        if "-" in base:
            hyphen.append(fn)
    return roleless, hyphen


def judge(roleless, hyphen, n1_ceiling, n2_ceiling):
    """判定面：超限的条目如实点名，返回违规行清单（空 = 在上限内）。"""
    v = []
    if len(roleless) > n1_ceiling:
        v.append("N1 无角色名 %d 份 > 上限 %d（超 %d 份，名单见 --show）"
                 % (len(roleless), n1_ceiling, len(roleless) - n1_ceiling))
    if len(hyphen) > n2_ceiling:
        v.append("N2 连字符名 %d 份 > 上限 %d（超 %d 份，名单见 --show）"
                 % (len(hyphen), n2_ceiling, len(hyphen) - n2_ceiling))
    return v


def selftest():
    cells = []
    prefixes, suffixes, probs = read_roles(NAMING_DOC)
    if probs:
        print("FATAL 判据无法自证：词法读不到 —— " + "；".join(probs))
        sys.exit(2)  # NO_CALL_FACE J2
    top, sub = universe(SCRIPTS_DIR)
    if not top:
        print("FATAL 判据无法自证：scripts/ 顶层 .py 宇宙为空")
        sys.exit(2)  # NO_CALL_FACE J2

    # 1) 合成宇宙：全带角色 ⇒ 两面 0
    synth = ["check_foo.py", "gen_bar.py", "baz_verify.py", "qux_probe.py"]
    r1, r2 = census(synth, prefixes, suffixes)
    cells.append(("clean-synth-green", judge(r1, r2, N1_CEILING, N2_CEILING) == [] and not r1 and not r2))

    # 2) 新入场一份无角色名 ⇒ 顶穿上限必红（这就是这道门的存在理由）
    cells.append(("new-roleless-red", judge(r1 + ["mystery.py"], r2, len(r1), len(r2)) != []))

    # 3) 后缀角色不误伤：`x_probe.py` 不该进 N1
    cells.append(("suffix-role-not-counted", census(["x_probe.py"], prefixes, suffixes)[0] == []))

    # 4) 前缀角色不误伤：`check_x.py` 即便含 `-` 也不进 N1，只进 N2
    cells.append(("prefix-role-not-in-n1", census(["check_a-b.py"], prefixes, suffixes)[0] == []))

    # 5) 连字符单独成面
    n1x, n2x = census(["a-b.py"], prefixes, suffixes)
    cells.append(("hyphen-in-n2", n2x == ["a-b.py"] and "a-b.py" in n1x))

    # 6) 词法读不到 ⇒ 自拒真给 2（不许退化成「读不到就当成合规」）
    empty_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "__no_such_scripts__")
    ok6 = False
    try:
        t2, _ = universe(empty_dir)
        p2, s2, pr2 = read_roles(os.path.join(empty_dir, "NAMING.md"))
        ok6 = (t2 == []) and pr2 != []
    except Exception as e:
        print("FATAL 判据未捕获异常：%s" % e)
        sys.exit(2)  # NO_CALL_FACE J2
    cells.append(("empty-universe-and-missing-doc-selfrefuse", ok6))

    # 7) 空词表不许报绿（词法解析到 0 个词就是判据坏了）
    try:
        _, _, pr3 = read_roles(_write_tmp_naming("naming-roles-prefix:\nnaming-roles-suffix: _verify\n"))
        ok7 = pr3 != []
    except Exception as e:
        print("FATAL 判据未捕获异常：%s" % e)
        sys.exit(2)  # NO_CALL_FACE J2
    cells.append(("empty-role-table-selfrefuse", ok7))

    # 8) 真源码阳性对照：现状读数必须 == 棘轮上限（上限烂掉比没上限更贵）
    real_n1, real_n2 = census(top, prefixes, suffixes)
    cells.append(("real-ceiling-matches-measured",
                  len(real_n1) == N1_CEILING and len(real_n2) == N2_CEILING))

    # 9) 子目录点名必须按 basename 分类：`blackbox/check_foo.py` 已带角色，不许算成债；
    #    同一条路径里的 `-` 也不许算进 N2（那是目录名，不是模块名）。
    p1, p2 = census(["blackbox/check_foo.py", "e2e-run/probe_bar.py"], prefixes, suffixes)
    cells.append(("subdir-name-classified-by-basename", p1 == ["e2e-run/probe_bar.py"] and p2 == []))

    # 10) 上限被抬高一档 ⇒ 同一条对照格必须红（证明它在考东西，不是恒真）
    cells.append(("ceiling-drift-detected",
                  not (len(real_n1) == N1_CEILING + 1 and len(real_n2) == N2_CEILING)))

    bad = [n for n, v in cells if not v]
    print("SELFTEST %s（%d 格：%s）" % ("OK" if not bad else "FAIL", len(cells),
                                        " ".join(n for n, _ in cells)))
    if bad:
        print("未通过格：" + " ".join(bad))
    sys.exit(0 if not bad else 2)  # NO_CALL_FACE J2


def _write_tmp_naming(body):
    import tempfile
    d = tempfile.mkdtemp(prefix="naming-roles-")
    p = os.path.join(d, "NAMING.md")
    with io.open(p, "w", encoding="utf-8") as f:
        f.write(body)
    return p


def main(argv=None):
    ap = argparse.ArgumentParser(prog="check_scripts_naming.py")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--show", action="store_true")
    ap.add_argument("--show-ceiling", action="store_true")
    ns = ap.parse_args(argv)
    if ns.selftest:
        return selftest()

    prefixes, suffixes, probs = read_roles(NAMING_DOC)
    if probs:
        print("FATAL 判据无法自证：词法读不到 —— " + "；".join(probs))
        return 2
    top, sub = universe(SCRIPTS_DIR)
    if not top:
        print("FATAL 判据无法自证：scripts/ 顶层 .py 宇宙为空")
        return 2

    n1, n2 = census(top, prefixes, suffixes)
    c1, c2 = census(sub, prefixes, suffixes)
    v = judge(n1, n2, N1_CEILING, N2_CEILING)
    if ns.show_ceiling:
        print("上限 N1=%d N2=%d｜现状 N1=%d N2=%d" % (N1_CEILING, N2_CEILING, len(n1), len(n2)))
    if ns.show:
        print("  N1：" + " ".join(sorted(n1)))
        print("  N2：" + " ".join(sorted(n2)))
        print("  C（子目录只报面）：" + " ".join(sorted(set(c1) | set(c2))))
    if v:
        for line in v:
            print("  违规 %s" % line)
        print("FAIL 判定面 %d 条 > 棘轮上限（只许下降；改名要同批下调上限，新增无角色名一律挡在门外）" % len(v))
        return 1
    print("PASS scripts/ 顶层 %d 份 .py：N1 无角色 %d/%d、N2 连字符 %d/%d；只报面子目录 N1=%d N2=%d（%d 份，本轮不判）"
          % (len(top), len(n1), N1_CEILING, len(n2), N2_CEILING, len(c1), len(c2), len(sub)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
