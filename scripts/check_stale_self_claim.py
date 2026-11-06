#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""check_stale_self_claim.py —— 把 AI-DEVELOPMENT-STANDARD.md §4.1「自述滞后现状」钉成常驻门。

判的是什么
    源码里对**某个具名符号**作出的「能力不存在」断言（注释面 + 运行时字符串面两式），
    如果该符号在仓内**真有代码级消费者**，这条断言就是滞后的 ⇒ 红。
    两类取数面刻意分开报码，因为它们的历史失效形态不同：
      S1 注释面：`///` / `//` 文档注释里写「`foo` 尚未实现」而 foo 早被调用。
      S2 运行时字面量面：`"..."` 里的同一句式——它会随 tools/list / 启动横幅**发货**，
         纯散文判据看不见（BUG-577 的 agent_register_key 描述串就是这个面）。

为什么不是「扫所有『尚未』」
    本仓的甄别式（BUG-575 立规）：**现在时否定活接线 = 滞后；点名变更史 = 准确**。
    历史陈述常与违例句式同串（「此前写 X，现已改为 Y」），所以判定必须
    ① 按子句切分，② 子句里出现变更史标记（此前/当初/落地时/旧口径/已改/已被…推翻）即跳过，
    ③ 只认带**反引号符号名**的断言（没有具名对象的泛指一律不判，那是修辞不是契约）。
    反面教材同族：run_guards 的 flag_claims_in_reason（否定句把「无 --selftest 旗标」读成声称）。

退出码契约
    0 干净 / 1 判据红（存在滞后自述）/ 2 判据无法自证（宇宙为空、一条主张都没解析到、未知旗标）
    / 4 尺子自己坏了（未捕获异常，绝不冒用 1）

豁免表 EXEMPTIONS
    逐条点名 (文件, 声称的符号, 原句子串, 理由)。**豁免本身会被反查**：
    条目若在该文件里已经找不到，判「陈旧豁免」红（幻影豁免 = 无人认领的免检面）。

真未实现不报红
    符号在全仓（含注释/测试/生成面）都找不到 ⇒ 该断言为真，跳过。
    这是**有意的宽松侧**：宁可放过一条，也不制造误红逼人来关尺（判据恒红 = 没人读 = 没锁）。
"""

import argparse
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

NEG_PHRASES = (
    "尚未实现", "还未实现", "未实现", "没有实现", "尚未接线", "未接线",
    "死承诺", "尚未落地", "还没实现", "not implemented",
)

HISTORY_MARKERS = (
    "此前", "当初", "当时", "旧口径", "旧文案", "已改", "已纠正", "纠正",
    "已被", "推翻", "上一版", "初版", "曾经", "原本", "原来", "修前", "落地时",
)

# 生成/孪生面：不是现状，不扫（点名理由见 docstring）
SKIP_PATH_PARTS = (
    os.path.join("dist", ""), os.path.join("_build", ""), os.path.join("plugins", ""),
    ".mbti", os.path.join(".mooncakes", ""),
)
TEST_SUFFIXES = ("_test.mbt", "_wbtest.mbt")

# 逐条点名的豁免（文件, 符号, 原句子串, 理由）
EXEMPTIONS = (
    # 逐条点名 (文件, 符号, 原句子串, 理由)。空表是现状：src/ 的六处负面句式全是点名变更史的准确陈述，
    # 不需要免检。**别为了过关往这里加条目**——陈旧豁免由 stale_exemptions() 判红（本尺自证格）。
)

RE_BACKTICK = re.compile(r"`([A-Za-z_][A-Za-z0-9_:/]{2,})`")


def _read(path):
    with io.open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def is_comment(line):
    s = line.lstrip()
    return s.startswith("///") or s.startswith("//")


def claim_lines(text):
    """产出 (行号, 行文本)：注释面与运行时字面量面各打一种标签。"""
    out = []
    for i, line in enumerate(text.split("\n"), 1):
        if not any(p in line for p in NEG_PHRASES):
            continue
        face = "S1" if is_comment(line) else ("S2" if '"' in line else None)
        if face:
            out.append((i, line, face))
    return out


def clauses(line):
    return [c for c in re.split(r"[；;。\(\)]| —— |,|\|", line) if c.strip()]


def symbols_in(clause):
    return RE_BACKTICK.findall(clause)


def code_consumers(sym, self_rel, universe):
    """该符号在**非注释、非测试、非生成面**里的引用次数（定义行自身不计）。"""
    base = sym.split("::")[-1].split(".")[-1]
    pat = re.compile(r"(?<![A-Za-z0-9_])" + re.escape(base) + r"(?![A-Za-z0-9_])")
    hits = []
    for rel in universe:
        if rel.endswith(TEST_SUFFIXES):
            continue
        text = universe[rel]
        for i, line in enumerate(text.split("\n"), 1):
            if is_comment(line) or "///" in line.split("//")[0][:0]:
                continue
            if not pat.search(line):
                continue
            stripped = line.strip()
            if rel == self_rel and i == _def_line(text, base):
                continue
            if re.match(r"^(pub )?(let|fn|type|exception)\b", stripped) and base in stripped.split("(")[0]:
                continue  # 别处的定义不算消费者
            hits.append((rel, i))
    return hits


def _def_line(text, base):
    for i, line in enumerate(text.split("\n"), 1):
        s = line.strip()
        if re.match(r"^(pub )?(let|fn)\b", s) and re.search(r"\b" + re.escape(base) + r"\b", s):
            return i
    return -1


def any_occurrence(sym, universe):
    base = sym.split("::")[-1].split(".")[-1]
    for rel in universe:
        if base in universe[rel]:
            return True
    return False


def build_universe():
    files = []
    for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, "src")):
        dirnames[:] = [d for d in dirnames if d not in ("_build", ".mooncakes")]
        for fn in filenames:
            if fn.endswith(".mbt"):
                files.append(os.path.relpath(os.path.join(dirpath, fn), ROOT))
    uni = {}
    for rel in files:
        if any(part in rel for part in SKIP_PATH_PARTS):
            continue
        uni[rel] = _read(os.path.join(ROOT, rel.replace(os.sep, "/")))
    return uni


def exempted(rel, sym, clause):
    for f, s, frag, _why in EXEMPTIONS:
        if f == rel and s == sym and frag in clause:
            return True
    return False


def scan(universe):
    violations, claims, hits = [], 0, 0
    for rel in sorted(universe):
        if rel.endswith(TEST_SUFFIXES):
            continue  # 测试面既不计消费者也不作现状自述（否则夹具注释会造出假违例）
        text = universe[rel]
        for lineno, line, face in claim_lines(text):
            hits += 1
            for cl in clauses(line):
                if not any(p in cl for p in NEG_PHRASES):
                    continue
                # 符号取**整行**级关联：`foo` 尚未实现 / 尚未实现（见 `foo`）两种词序都得认
                syms = symbols_in(line)
                if not syms:
                    continue
                if any(m in cl for m in HISTORY_MARKERS):
                    continue  # 点名变更史 = 准确陈述
                for sym in syms:
                    claims += 1
                    if exempted(rel, sym, cl):
                        continue
                    if not any_occurrence(sym, universe):
                        continue  # 真未实现
                    got = code_consumers(sym, rel, universe)
                    if got:
                        where = ", ".join("%s:%d" % (r, n) for r, n in got[:3])
                        violations.append(
                            "✗ [%s 自述滞后] %s:%d —— 断言 %r 说 `%s` 不存在，"
                            "但它在非注释/非测试面有 %d 处消费者（%s）"
                            % (face, rel, lineno, cl.strip()[:48], sym, len(got), where))
    return violations, claims, hits


def stale_exemptions(table=None):
    out = []
    for f, s, frag, why in (table if table is not None else EXEMPTIONS):
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            out.append("✗ [EX1 豁免指向不存在的文件] %s（理由：%s）" % (f, why))
            continue
        if frag not in _read(p):
            out.append("✗ [EX2 陈旧豁免] %s 里已找不到 %r ⇒ 该免检面无人认领，请删条目" % (f, frag))
    return out


def run(argv):
    ap = argparse.ArgumentParser(prog="check_stale_self_claim.py", description=__doc__.split("\n")[0])
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--list", action="store_true", help="只列判到的主张数，不判红")
    ap.add_argument("--root", default=None, help="夹具根（仅自检用；正式跑不许指真仓以外）")
    ns = ap.parse_args(argv)
    if ns.selftest:
        return selftest()
    universe = build_universe() if not ns.root else fixture_universe(ns.root)
    if not universe:
        print("[FATAL] 扫描宇宙为空（src/ 读不到 .mbt）⇒ 拒绝出数（rc=2）")
        return 2
    violations, claims, hits = scan(universe)
    violations += stale_exemptions()
    # 自拒的**唯一**触发条件是「尺读不到任何可判面」，不是「没判出违例」：
    # 本仓现状面里负面句式确实可能为零（BUG-575 立了甄别式后，残留的全是点名变更史的准确陈述）——
    # 那属于干净，报绿并留痕；而 phrase 命中数为零意味着路径/编码/取数面坏了，绝不冒报绿。
    if hits == 0:
        print("[FATAL] %d 份文件里一条负面句式都没读到 ⇒ 判据无法自证，拒绝报绿（rc=2）" % len(universe))
        return 2
    if ns.list:
        print("负面句式 %d 处 · 具名主张 %d 条 · 违规 %d 处" % (hits, claims, len(violations)))
        return 0
    print("[扫描] %d 份 .mbt · 负面句式 %d 处 · 具名负面主张 %d 条（其余为无具名对象的修辞或变更史陈述）"
          % (len(universe), hits, claims))
    for v in violations:
        print(v)
    if violations:
        print("\n[结论] %d 处自述滞后（§4.1）⇒ rc=1" % len(violations))
        return 1
    print("[结论] 无滞后自述。**这不等于自述全都对** —— 本判据只看「具名否定式 ↔ 非注释/非测试消费者」。")
    return 0


def fixture_universe(root):
    uni = {}
    for dirpath, _dn, filenames in os.walk(root):
        for fn in filenames:
            if fn.endswith(".mbt"):
                p = os.path.join(dirpath, fn)
                uni[os.path.relpath(p, root)] = _read(p)
    return uni


def selftest():
    import tempfile
    shutil_import = None
    cells = []
    tmp = tempfile.mkdtemp(prefix="staleclaim-selftest-")
    try:
        pkg = os.path.join(tmp, "src", "demo")
        os.makedirs(pkg)
        wired = (
            "/// 缓存层 `warm_cache` 尚未实现，先走直读。\n"
            "pub fn warm_cache(x: Int) -> Int { x }\n"
            "pub fn use_it(x: Int) -> Int { warm_cache(x) }\n"
        )
        historical = (
            "/// 此前写「`warm_cache` 尚未实现」，已被 BUG-9 推翻并接线。\n"
            "pub fn use_it2(x: Int) -> Int { warm_cache(x) }\n"
        )
        truely_missing = "/// 限流器 `rate_governor` 尚未实现（本仓无此物）。\n"
        testish = "// 死承诺：`warm_cache` 未接线（本文件是测试面，不计消费者）\n"
        open(os.path.join(pkg, "a.mbt"), "w", encoding="utf-8").write(wired)
        open(os.path.join(pkg, "b.mbt"), "w", encoding="utf-8").write(historical)
        open(os.path.join(pkg, "c.mbt"), "w", encoding="utf-8").write(truely_missing)
        open(os.path.join(pkg, "d_test.mbt"), "w", encoding="utf-8").write(testish)
        uni = fixture_universe(tmp)

        def cell(name, cond):
            cells.append((name, bool(cond)))

        cell("fixture-four-files", len(uni) == 4)
        v, claims1, hits1 = scan(uni)
        cell("stale-claim-is-red", any("warm_cache" in x and "S1" in x for x in v))
        cell("past-tense-not-red", not any("BUG-9" in x for x in v))
        cell("genuinely-missing-not-red", not any("rate_governor" in x for x in v))
        cell("test-face-not-consumer", all("d_test" not in x for x in v))
        cell("history-only-face-is-clean-not-blind", hits1 >= 2 and claims1 >= 1)
        cell("empty-universe-refuses", not fixture_universe(os.path.join(tmp, "nope")))

        # 运行时字面量面（S2）：串里的同一句式必须换码报出
        s2dir = os.path.join(tmp, "src", "s2")
        os.makedirs(s2dir)
        open(os.path.join(s2dir, "e.mbt"), "w", encoding="utf-8").write(
            'pub fn desc() -> String { "**轮换**：`warm_cache` 尚未实现。参数：x(必填)。" }\n')
        uni2 = fixture_universe(tmp)
        v2, claims, hits2 = scan(uni2)
        cell("claims-counted", claims >= 3)
        cell("phrase-hits-counted", hits2 >= 4)
        cell("runtime-string-face-S2", any("[S2" in x and "warm_cache" in x for x in v2))

        # ── 变异对照：逐行改**真代码行**（判例-30：改注释不算变异），并断言替换点恰 1 处 ──
        lines = _read(os.path.abspath(__file__)).split("\n")

        def mutate(target, repl):
            idx = [i for i, l in enumerate(lines) if l.strip() == target]
            if len(idx) != 1:
                return None, len(idx)
            out = list(lines)
            indent = len(lines[idx[0]]) - len(lines[idx[0]].lstrip())
            out[idx[0]] = " " * indent + repl
            return "\n".join(out), len(idx)

        m1, n1 = mutate("if any(m in cl for m in HISTORY_MARKERS):", "if False:")
        if m1 is None:
            print("  [诊断] 历史跳过行的命中数=%d（要求恰 1）·候选行样例：%s" % (
                n1, [l.strip()[:60] for l in lines if "HISTORY_MARKERS" in l][:4]))
        cell("mutation-history-skip-anchor-exactly-one", m1 is not None and n1 == 1)
        SELF = os.path.abspath(__file__)
        if m1 is not None:
            ns1 = {"__name__": "mut1", "__file__": SELF}
            exec(compile(m1, "<mut1>", "exec"), ns1)
            v3, _c3, _h3 = ns1["scan"](uni2)
            cell("mutation-history-skip-really-fires",
                 any("BUG-9" in x for x in v3))  # 跳过被摘掉 ⇒ 历史陈述被误判成红
        m2, n2 = mutate("if got:", "if False:")
        if m2 is None:
            print("  [诊断] 消费者闸门的命中数=%d（要求恰 1）" % n2)
        cell("mutation-consumer-gate-anchor-exactly-one", m2 is not None and n2 == 1)
        if m2 is not None:
            ns2 = {"__name__": "mut2", "__file__": SELF}
            exec(compile(m2, "<mut2>", "exec"), ns2)
            v4, _c4, _h4 = ns2["scan"](uni2)
            cell("mutation-consumer-gate-really-fires", not v4)  # 闸门摘掉 ⇒ 全不红 = 尺失明

        # 陈旧豁免反查（用合成表，不靠真豁免面存在）
        # 合成串的 needle **不许以字面量出现在本文件里**，否则 stale 检查会自喂成「豁免仍然成立」（判例-30 自指形状）
        needle = "".join(["绝无此串", "-", "ZQK", "-9"])
        synth = ((os.path.relpath(SELF, ROOT).replace("\\", "/"), "ghost", needle, "合成理由"),
                 ("src/ghost_file.mbt", "ghost", "任意", "指向不存在的文件"))
        ex = stale_exemptions(table=synth)
        cell("stale-exemption-is-red", any("EX2" in e for e in ex))
        cell("exemption-pointing-nowhere-is-red", any("EX1" in e for e in ex))

        # ── 调用面（check_selftest_call_face 的要求）：四档退出码必须由真 `run()` 给出来，
        #    不许用「另造一个 argparse」冒充（那测的是我的想象力，不是我的参数面）──
        face = {"dirty": os.path.join(tmp, "face_dirty"),
                "clean": os.path.join(tmp, "face_clean"),
                "empty": os.path.join(tmp, "face_empty")}
        for d in face.values():
            os.makedirs(d)
        with io.open(os.path.join(face["dirty"], "x.mbt"), "w", encoding="utf-8") as f:
            f.write("/// `warm_cache` 尚未实现。\npub fn warm_cache(x: Int) -> Int { x }\n"
                    "pub fn c2(x: Int) -> Int { warm_cache(x) }\n")
        with io.open(os.path.join(face["clean"], "y.mbt"), "w", encoding="utf-8") as f:
            f.write("/// 此前写「`warm_cache` 尚未实现」，已被 BUG-9 推翻。\n"
                    "pub fn c3(x: Int) -> Int { warm_cache(x) }\n")
        with io.open(os.path.join(face["clean"], "z.mbt"), "w", encoding="utf-8") as f:
            f.write("pub fn warm_cache(x: Int) -> Int { x }\n")
        cell("call-face-violation-rc1", run(["--root", face["dirty"]]) == 1)
        cell("call-face-clean-rc0", run(["--root", face["clean"]]) == 0)
        cell("call-face-empty-refuses-rc2", run(["--root", face["empty"]]) == 2)
        cell("call-face-unknown-flag-rc2", _exit_code_of(["--definitely-not-real"]) == 2)
    finally:
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)

    bad = [n for n, ok in cells if not ok]
    for n, ok in cells:
        print("%s %s" % ("[OK]" if ok else "[XX]", n))
    if bad:
        print("[selftest] %d/%d 失败：%s" % (len(bad), len(cells), ", ".join(bad)))
        return 1
    print("[selftest] %d/%d 格通过（含 2 处变异对照锚点 + 1 处历史陈述反证 + 1 处真未实现反证）"
          % (len(cells), len(cells)))
    return 0


def _exit_code_of(argv):
    """走**真 run()**（含真 argparse 与四档出口），不是另造一个解析器。"""
    try:
        return run(argv)
    except SystemExit as e:
        return int(e.code if e.code is not None else 0)


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.exit(run(sys.argv[1:]))
    except SystemExit:
        raise
    except Exception as exc:  # noqa
        import traceback
        traceback.print_exc()
        print("[FATAL] 尺子自己坏了：%r ⇒ rc=4（绝不冒用 1 那一档）" % (exc,))
        sys.exit(4)
