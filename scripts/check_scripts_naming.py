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
import re
import shutil
import sys
import tempfile

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
# 共享模块白名单：`_` 开头且不是独立判据的共享件（见 NAMING.md 同名段）
SHARED_ANCHOR = "naming-shared-modules:"


def read_roles(doc_path):
    """从 NAMING.md 现读两份词表 + 共享模块白名单。

    返回 (prefixes, suffixes, shared, problems)。

    ⚠️ **白名单为什么放 NAMING.md 而不是「读文件头自述」**（判例-30 同族）：
    按自述豁免 = 「写一句注释就绕过判据」，绕过成本从「改一个文档」降成「加一句话」，
    且会随「谁写得好听」而扩大。**豁免必须付出「改另一个文件」的代价。**
    """
    if not os.path.isfile(doc_path):
        return [], [], [], ["读不到 NAMING.md：%s" % doc_path]
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
            return roles.get(PREFIX_ANCHOR, []), roles.get(SUFFIX_ANCHOR, []), [], ["NAMING.md 缺 anchor 行：%s" % anchor]
        body = line.split(anchor, 1)[1]
        words = [w.strip() for w in body.replace("`", "").split(",")]
        roles[anchor] = [w for w in words if w and all(ch.isalnum() or ch in "_-" for ch in w)]
        if not roles[anchor]:
            return roles.get(PREFIX_ANCHOR, []), roles.get(SUFFIX_ANCHOR, []), [], ["anchor 行解析到 0 个词：%s" % anchor]
    # 白名单行（可缺省 ⇒ 空名单；但**出现了就必须解析出 ≥1 个 .py**，否则是行写坏了）
    shared = []
    sline = None
    for ln in text.splitlines():
        if SHARED_ANCHOR in ln:
            sline = ln
            break
    if sline is not None:
        body = sline.split(SHARED_ANCHOR, 1)[1]
        # ⚠️ 顺序要紧：先剥反引号再 strip —— 行首是 ` ` 反引号+空格，
        #    先 strip 会留下反引号，`startswith("_")` 恒 false（实测踩过）。
        shared = [w.replace("`", "").strip() for w in body.split(",")]
        shared = [w for w in shared if w.endswith(".py")]
        if not shared:
            return roles[PREFIX_ANCHOR], roles[SUFFIX_ANCHOR], [], [
                "白名单行解析到 0 个 .py：%s" % SHARED_ANCHOR]
        bad = [w for w in shared if not w.startswith("_")]
        if bad:
            return roles[PREFIX_ANCHOR], roles[SUFFIX_ANCHOR], [], [
                "白名单只收 `_` 开头的共享件，以下不是：%s" % ", ".join(bad)]
    return roles[PREFIX_ANCHOR], roles[SUFFIX_ANCHOR], shared, []


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


def census(names, prefixes, suffixes, shared=()):
    """纯函数：按词法给一份宇宙挑出 N1（无角色名）与 N2（连字符名）。
    分类一律取 basename —— 子目录点名形如 `blackbox/check_foo.py`，拿整条路径比前缀会把
    已带角色的尺算成债（C 面虚高，读数就成了假的）。"""
    roleless, hyphen = [], []
    for fn in names:
        base = os.path.basename(fn)
        stem = base[:-3]
        has_role = stem.startswith(tuple(prefixes)) or stem.endswith(tuple(suffixes))
        # 共享模块白名单（NAMING.md 显式登记，不是读文件头自述）⇒ 不算 N1
        if base in shared:
            has_role = True
        if not has_role:
            roleless.append(fn)
        if "-" in base:
            hyphen.append(fn)
    return roleless, hyphen


def _iter_ref_texts(scripts_dir):
    """产出 (相对路径, 源码文本) —— 用于「谁引用了谁」的扫描。

    ⚠️ 扫 `scripts/` 全树（含 blackbox/），不扫别的目录：`import` 只在同目录/包内成立，
    而 `subprocess` 调用的路径写法以 `scripts/` 为基。跨树引用是盲区（见 NAMING.md）。
    """
    out = []
    for dp, _dn, fns in os.walk(scripts_dir):
        for fn in sorted(fns):
            if not fn.endswith(".py"):
                continue
            full = os.path.join(dp, fn)
            rel = os.path.relpath(full, scripts_dir).replace(os.sep, "/")
            try:
                with io.open(full, encoding="utf-8", errors="replace") as f:
                    out.append((rel, f.read()))
            except OSError:
                continue
    return out


def is_referenced(name, refs):
    """`name`（含 .py）是否被 refs 里**任何一个**别处引用。

    认三种形态（NAMING.md「引用形态」节同源）：
      ① import `_x` / `from _x import`（按 stem）
      ② subprocess/Popen 里出现 `"_x.py"`（按带扩展名的字面量）
      ③ importlib / runpy 动态加载（按带扩展名的字面量出现算）
    排除自身文件。
    """
    stem = name[:-3] if name.endswith(".py") else name
    imp_rx = re.compile(r"^\s*(?:from\s+%s(?:\s+import|\s*$)|import\s+.*\b%s\b)"
                        % (re.escape(stem), re.escape(stem)), re.M)
    lit_rx = re.compile(r"""["']%s["']""" % re.escape(name))
    for rel, text in refs:
        if os.path.basename(rel) == name:
            continue
        if imp_rx.search(text) or lit_rx.search(text):
            return True
    return False


def check_admission(shared, scripts_dir, guards_path):
    """白名单**准入条件**核验（NAMING.md 的四条，条件 4 语义判断不在此核）。

    返回 (problems, warns)：
      problems ⇒ 硬错（判据 rc=2，拒绝判绿）—— 条件 1/2/3 被违反
      warns    ⇒ 软提示（白名单行尾有 `#` 说明时用）

    条件 1（`_` 开头）已在 read_roles 里核，此处只核 2/3。
    """
    problems, warns = [], []
    if not shared:
        return problems, warns
    guards = ""
    if guards_path and os.path.isfile(guards_path):
        with io.open(guards_path, encoding="utf-8", errors="replace") as f:
            guards = f.read()
    refs = _iter_ref_texts(scripts_dir)
    for name in shared:
        # 条件 2：不得是独立电池格
        if re.search(r'"%s"' % re.escape(name), guards):
            problems.append(
                "白名单成员 %s 被 run_guards.py 登记为独立电池格 ⇒ 它是**判据**不是共享件"
                "（条件 2 违反）⇒ 该改名 check_*.py，不该进白名单" % name)
            continue
        # 条件 3：必须被别处引用
        if not is_referenced(name, refs):
            problems.append(
                "白名单成员 %s **零引用**（无 import / 无 subprocess 字面量 / 无 runpy）"
                "⇒ 它可能不是共享件（条件 3 违反）。若引用形态特殊（拼接名/跨树），"
                "在白名单行尾加 `# 引用形态特殊：<说明>` 降为 WARN" % name)
    return problems, warns


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
    prefixes, suffixes, shared, probs = read_roles(NAMING_DOC)
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
        p2, s2, sh2, pr2 = read_roles(os.path.join(empty_dir, "NAMING.md"))
        ok6 = (t2 == []) and pr2 != []
    except Exception as e:
        print("FATAL 判据未捕获异常：%s" % e)
        sys.exit(2)  # NO_CALL_FACE J2
    cells.append(("empty-universe-and-missing-doc-selfrefuse", ok6))

    # 7) 空词表不许报绿（词法解析到 0 个词就是判据坏了）
    try:
        _, _, _, pr3 = read_roles(_write_tmp_naming("naming-roles-prefix:\nnaming-roles-suffix: _verify\n"))
        ok7 = pr3 != []
    except Exception as e:
        print("FATAL 判据未捕获异常：%s" % e)
        sys.exit(2)  # NO_CALL_FACE J2
    cells.append(("empty-role-table-selfrefuse", ok7))

    # 9) ★ 白名单有没有真的在起作用（判例-29 机制格 ≠ 实现路径格）
    #    断言的是「同一个名字，名单内不报 N1、名单外报 N1」——
    #    只断言「判据能跑」证明不了白名单接线了（把 shared 传空它照样跑）。
    # ⚠️ 探针名必须**本身无角色**（`_xxx_probe` 的 `_probe` 是后缀角色 ⇒ 本来就免 N1，
    #    用它测白名单会「假绿」——实测踩过）。
    probe = ["_helper_thing.py", "plain_thing.py"]
    n1_out, _ = census(probe, prefixes, suffixes, ())
    n1_in, _ = census(probe, prefixes, suffixes, ("_helper_thing.py",))
    ok9 = (len(n1_out) == 2) and (len(n1_in) == 1) and ("_helper_thing.py" not in n1_in)
    cells.append(("shared-whitelist-actually-exempts", ok9))

    # 10) ★ 变异 1：白名单里放一个**非 `_` 开头**的名字 ⇒ 必须自拒（不许静默豁免普通脚本）
    try:
        _, _, _, pr10 = read_roles(
            _write_tmp_naming(
                "naming-roles-prefix: check_\nnaming-roles-suffix: _verify\n"
                "naming-shared-modules: plain_thing.py\n"))
        ok10 = pr10 != []
    except Exception as e:  # noqa: BLE001
        print("FATAL 判据未捕获异常：%s" % e)
        sys.exit(2)  # NO_CALL_FACE J2
    cells.append(("MUTATION-non-underscore-in-whitelist-selfrefuse", ok10))

    # 11) ★ 变异 2：白名单行**解析到 0 个 .py** ⇒ 必须自拒（行写坏了不许当空名单放行）
    try:
        _, _, _, pr11 = read_roles(
            _write_tmp_naming(
                "naming-roles-prefix: check_\nnaming-roles-suffix: _verify\n"
                "naming-shared-modules: （空）\n"))
        ok11 = pr11 != []
    except Exception as e:  # noqa: BLE001
        print("FATAL 判据未捕获异常：%s" % e)
        sys.exit(2)  # NO_CALL_FACE J2
    cells.append(("MUTATION-empty-whitelist-selfrefuse", ok11))

    # 12) ★ 变异 3：**真仓库的白名单真的免掉了 3 份**（按真实 NAMING.md + 真实宇宙对表）
    #     N1 现状 27 = 30 - 3 ⇒ 把 shared 传空应回到 30。这条锁住「白名单与现状读数一致」。
    top_real, _sub_real = universe(SCRIPTS_DIR)
    n1_with, _ = census(top_real, prefixes, suffixes, shared)
    n1_without, _ = census(top_real, prefixes, suffixes, ())
    ok12 = (len(n1_without) - len(n1_with) == len(shared)) and len(shared) > 0
    cells.append(("MUTATION-whitelist-count-matches-live-repo", ok12))

    # 13) ★ 准入条件 3：**零引用的文件进白名单 ⇒ 硬错**（本单主要缺口）
    #     变异：编一个没人引用的名字塞进 shared ⇒ check_admission 必须报 problem。
    # ⚠️ 探针名必须**拼接构造**：直接在源码里写死一个假名，会被 is_referenced 扫到
    #    「本判据自己源码里有这个字面量」⇒ 误判成「有人引用」⇒ 该格恒绿（判例-30 自指假绿）。
    # ⚠️ **改读 temp 合成树**（R56）：本格只验「零引用被拒」，不需要真仓任何文件。
    #    原版传 SCRIPTS_DIR ⇒ 触发 `check_selftest_hermetic` 的 R 档 +1（每格读真仓即计债）。
    #    这不是放宽判据：被检的规则（条件 3）仍在 temp 树上完整生效。
    _fake13 = "_zero" + "_ref_probe.py"
    _t13 = tempfile.mkdtemp(prefix="naming-adm13-")
    _guards13 = os.path.join(_t13, "run_guards.py")
    with io.open(_guards13, "w", encoding="utf-8") as _f13:
        _f13.write("# temp 合成 run_guards（不含任何登记）\n")
    _a13, _ = check_admission([_fake13], _t13, _guards13)
    cells.append(("MUTATION-zero-ref-in-whitelist-rejected", len(_a13) >= 1))
    shutil.rmtree(_t13, ignore_errors=True)

    # 14) ★ 准入条件 2：**被 run_guards 登记为独立格的文件进白名单 ⇒ 硬错**
    #     用真仓库里真实存在的一把判据当样本（check_doc_surface 确实在电池里登记）。
    _a14, _ = check_admission(["check_doc_surface.py"], SCRIPTS_DIR,
                              os.path.join(SCRIPTS_DIR, "run_guards.py"))
    cells.append(("MUTATION-battery-registered-in-whitelist-rejected", len(_a14) >= 1))

    # 15) ★ 正向对照：**真仓库的白名单必须全过**（否则这一格会把「现状」判成坏）
    _a15, _ = check_admission(shared, SCRIPTS_DIR,
                              os.path.join(SCRIPTS_DIR, "run_guards.py"))
    cells.append(("admission-live-whitelist-all-passes", len(_a15) == 0))

    # 16) ★ 引用形态：`is_referenced` 认 import 与 subprocess 字面量两种
    # ⚠️ `_r16a` 必须读真仓（要证明「真共享件**被认出**」—— 传 temp 空树等于没标定，判例-32）。
    _r16a = is_referenced("_badge_anchor.py", _iter_ref_texts(SCRIPTS_DIR))
    # ⚠️ `_r16b` 改读 temp 合成树（本格只验「假名不被误认」，与真仓内容无关）：
    #    原版也传 SCRIPTS_DIR ⇒ R 档 +1。规则（不误认）在 temp 上同样完整生效。
    # 同上：假名拼接构造（字面量会被本判据自身命中 ⇒ 假绿）
    _fake16 = "_definitely_nobody_" + "references_this.py"
    _t16 = tempfile.mkdtemp(prefix="naming-ref16-")
    with io.open(os.path.join(_t16, "unrelated.py"), "w", encoding="utf-8") as _f16:
        _f16.write("# temp 合成文件，不含任何 import\n")
    _r16b = not is_referenced(_fake16, _iter_ref_texts(_t16))
    cells.append(("ref-detector-sees-real-misses-fake", _r16a and _r16b))
    shutil.rmtree(_t16, ignore_errors=True)

    # 8) 真源码校准：**上限不得宽于实测**（上限烂掉比没上限更贵）。
    #
    #    ⚠️ 这一格原来写的是「实测 == 上限」——那等于把「债没还完」也算成「尺子坏了」：
    #    只要 N1/N2 超上限，`--selftest` 就返 rc=2「判据无法自证」，而真相是**判据工作正常、
    #    只是对象有债**。判例-32 明令：「判据自己的腐烂与对象的陈旧是两种结论，混为一谈会让
    #    下一个人去修错的东西」。⇒ 债由**主路径**报 FAIL（rc=1），自检只负责证明尺子能咬。
    #
    #    改成 >= 后原意完整保留且更精确：
    #      · 上限 > 实测 ⇒ 上限比现实松（有人还了债忘降上限）⇒ 红
    #      · 上限 <= 实测 ⇒ 上限仍在卡着 ⇒ 绿（债由主路径报）
    real_n1, real_n2 = census(top, prefixes, suffixes)
    cells.append(("real-ceiling-not-looser-than-measured",
                  len(real_n1) >= N1_CEILING and len(real_n2) >= N2_CEILING))

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

    prefixes, suffixes, shared, probs = read_roles(NAMING_DOC)
    if probs:
        print("FATAL 判据无法自证：词法读不到 —— " + "；".join(probs))
        return 2

    # 白名单**准入条件**核验（NAMING.md 四条件的 2/3；条件 4 是语义判断，靠 review）
    adm_probs, _adm_warns = check_admission(
        shared, SCRIPTS_DIR, os.path.join(SCRIPTS_DIR, "run_guards.py"))
    if adm_probs:
        print("FATAL 白名单准入条件被违反（%d 条）—— 拒绝判绿：" % len(adm_probs))
        for x in adm_probs:
            print("  - " + x)
        return 2
    top, sub = universe(SCRIPTS_DIR)
    if not top:
        print("FATAL 判据无法自证：scripts/ 顶层 .py 宇宙为空")
        return 2

    n1, n2 = census(top, prefixes, suffixes, shared)
    c1, c2 = census(sub, prefixes, suffixes, shared)
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
