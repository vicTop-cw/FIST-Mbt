#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_registration_numbers.py —— 登记理由里的**数字**必须与实测一致。

## 为什么有这把尺（R119）

`run_guards.py` 的 `expected(..., why=...)` 里常写「现读 N 处（W=a / R=b / …）」这类读数。
实测发现它会**漂**，而且漂得很快：

- R117 按实测把 `check_selftest_hermetic` 的登记从「72 处 / W=10 / R=48」改成「94 / W 4 / R 62 / G 28」；
- R118 修完分类缺陷与状态件位置后，实测立刻变成「90 / W 1 / R 61 / G 28」——
  **一轮之内就漂了**，靠人同步必然跟不上。

**登记数字漂移和代码腐烂是一回事**：不报错、不变红，只在有人真去量的时候才暴露；
更糟的是后来者按漂了的数字判断"还剩多少可修"。

## 判据

对一张表里的每个条目：跑测量命令 → 解析实测；从 `run_guards.py` 的 why 里解析登记 → 对表。
不一致就红，并**逐项打印差在哪**（不是只报一个总数）。

## 退出码

- `0` = 全部一致
- `1` = 有登记与实测不一致（**这就是要修的东西**）
- `2` = 判据无法自证（读不到 run_guards / 解析不出登记读数 / 测量命令跑不出数）
"""
import io
import os
import re
import subprocess
import sys

# 控制台编码门（check_py_stdout_encoding E1）：本判据打印中文；没有这道门时，
# 本机控制台一红就崩在结论行之前，rc 会被冒用成「缺陷在场」。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUN_GUARDS = os.path.join(ROOT, "scripts", "run_guards.py")
AGENTS_DOC = os.path.join(ROOT, "AGENTS.md")   # R127：文档里的条数声明从这里反解

RC_OK, RC_MISMATCH, RC_BROKEN = 0, 1, 2

# 登记条目：脚本名 → (why 里的读数正则组, 实测命令)
# 正则必须**从 why 里反解**（不手抄数字：手抄就是第二份真源）。
ENTRIES = [
    {
        "script": "check_selftest_hermetic.py",
        "cmd": [sys.executable, "scripts/check_selftest_hermetic.py"],
        "claim": "红档 **{red} 处 = W {W} / R {R} / G {G}**",
        "re_claim": r"红档 \*\*(\d+) 处 = W (\d+) / R (\d+) / G (\d+)\*\*",
        "diag": "另记账 {diag}（S {S} / T {T}）",
        "re_diag": r"另记账 (\d+)（S (\d+) / T (\d+)）",
        "measure": "faces",
    },
    {
        "script": "check_scripts_naming.py",
        "cmd": [sys.executable, "scripts/check_scripts_naming.py"],
        "claim": "现读 {n} 条命名判定面",
        "re_claim": r"现读 (\d+) 条命名判定面",
        "diag": None,
        "re_diag": None,
        "measure": "over_faces",
    },
]


def measure_faces(entry):
    """跑测量命令，数各档出现次数。返回 (red, w, r, g, diag, s, t) 或 None。"""
    try:
        out = subprocess.run(entry["cmd"], capture_output=True, text=True,
                             encoding="utf-8", cwd=ROOT).stdout
    except OSError:
        return None
    if not out.strip():
        return None
    c = {k: len(re.findall(r"\[%s\]" % k, out)) for k in "WRGST"}
    red = c["W"] + c["R"] + c["G"]
    diag = c["S"] + c["T"]
    return (red, c["W"], c["R"], c["G"], diag, c["S"], c["T"])


def measure_over_faces(entry):
    """数输出了几条「违规 N…」——即**超过棘轮上限**的面数（登记里那个「2 条」）。"""
    try:
        out = subprocess.run(entry["cmd"], capture_output=True, text=True,
                             encoding="utf-8", cwd=ROOT).stdout
    except OSError:
        return None
    m = re.findall(r"^\s*违规 (N\d)", out, re.M)   # 输出行有前导空格
    return len(m) if out.strip() else None


def judge(run_guards_text, measured):
    """纯函数：登记为什么 vs 实测 → 违例列表。便于 --selftest 合成自证。"""
    problems = []
    text = run_guards_text
    for entry, meas in zip(ENTRIES, measured):
        if meas is None:
            problems.append("%s：测量命令跑不出数 ⇒ 无法对表" % entry["script"])
            continue
        if entry["measure"] == "over_faces":
            m = re.search(entry["re_claim"], text)
            if not m:
                problems.append("%s：why 里解析不到「现读 N 条命名判定面」" % entry["script"])
                continue
            if int(m.group(1)) != meas:
                problems.append("%s：登记现读 %s 条 ≠ 实测 %d 条"
                                % (entry["script"], m.group(1), meas))
            continue
        red, w, r, g, diag, s, t = meas
        m = re.search(entry["re_claim"], text)
        if not m:
            problems.append("%s：why 里解析不到「红档 N 处 = W a / R b / G c」⇒ 登记形状变了"
                            % entry["script"])
            continue
        claim = tuple(int(x) for x in m.groups())
        real = (red, w, r, g)
        if claim != real:
            problems.append(
                "%s：登记红档 red=%d/W=%d/R=%d/G=%d ≠ 实测 red=%d/W=%d/R=%d/G=%d"
                % ((entry["script"],) + claim + real))
        m2 = re.search(entry["re_diag"], text)
        if m2:
            c2 = tuple(int(x) for x in m2.groups())
            r2 = (diag, s, t)
            if c2 != r2:
                problems.append(
                    "%s：登记记账 diag=%d/S=%d/T=%d ≠ 实测 diag=%d/S=%d/T=%d"
                    % ((entry["script"],) + c2 + r2))
        else:
            problems.append("%s：why 里解析不到「另记账 N（S a / T b）」" % entry["script"])
    return problems


# ── R127：文档里的「N 条测试在 `path`」也必须对表 ──────────────────────
# 抽检 4 处曾发现 2 处漂移（text_diff 8→18、soldier_type_of 8→9）—— 这类声明从没人对过表。
# 正则从文档**反解**（不手抄数字），覆盖两种形态：
#   「18 条白盒测试在 `src/diff/diff_test.mbt`」  /  「15 条白盒锁 `src/..._wbtest.mbt`」
RE_DOC_TEST_CLAIM = re.compile(r"(\d+) 条(?:白盒)?(?:测试|白盒锁)(?:在)? ?`([^`]+)`")


def parse_doc_test_claims(text):
    """纯函数：从文档正文反解 [(declared, path, lineno)]。"""
    out = []
    for ln, line in enumerate(text.splitlines(), 1):
        for m in RE_DOC_TEST_CLAIM.finditer(line):
            out.append((int(m.group(1)), m.group(2), ln))
    return out


def check_doc_test_claims(text, count_fn):
    """纯函数：文档声明 vs 实测条数。`count_fn(path) -> int|None`（None=读不到）。"""
    problems = []
    for declared, path, ln in parse_doc_test_claims(text):
        actual = count_fn(path)
        if actual is None:
            problems.append("%s:%d 声明 %d 条测试，但**读不到该文件** ⇒ 声明指向不存在/不可读的面"
                            % (path, ln, declared))
        elif actual != declared:
            problems.append("%s:%d 声明 %d 条测试 ≠ 实测 %d 条（文档漂移：改文档或改测试）"
                            % (path, ln, declared, actual))
    return problems


def render_claim(entry, meas):
    red, w, r, g, diag, s, t = meas
    return (entry["claim"].format(red=red, W=w, R=r, G=g),
            entry["diag"].format(diag=diag, S=s, T=t))


def selftest():
    """合成夹具自证（**不读任何仓库文件**）：含一格变异对照。"""
    fails, cells = [], []

    def cell(name, ok):
        cells.append(name)
        if not ok:
            fails.append(name)

    # 夹具**从条目表生成**：加/删条目时自证自动跟随（不会出现"新条目没被自证覆盖"）
    good_meas, good_parts = [], []
    for e in ENTRIES:
        if e["measure"] == "faces":
            good_meas.append((90, 1, 61, 28, 10, 3, 7))
            claim, diag = render_claim(e, good_meas[-1])
            good_parts.append(claim + "，" + diag + "，涉 37 个文件。")
        else:
            good_meas.append(2)
            good_parts.append(e["claim"].format(n=2) + " > 棘轮上限")
    good_text = "；".join(good_parts)
    cell("consistent-claim-passes", judge(good_text, good_meas) == [])

    # 变异对照：把登记里的 W 改一个数，必须被抓到（判例-29：改坏机制要红）
    drift_text = good_text.replace("W 1", "W 4")   # 只改红档那一条的 W
    bad = judge(drift_text, good_meas)
    cell("drifted-claim-is-caught", len(bad) == 1 and "W" in bad[0])

    # 形状变了（解析不到）也要报，而不是静默通过
    cell("unparseable-claim-is-caught", judge("why 里没有读数", good_meas) != [])

    # 测量跑不出数 ⇒ 报无法对表（不静默）
    cell("broken-measurement-is-caught", judge(good_text, [None] * len(ENTRIES)) != [])

    # R127：文档里的「N 条测试在 `path`」对表（合成夹具，**不读仓库**）
    _doc = "真源 `x.mbt`，3 条白盒测试在 `a_test.mbt`。"
    _cnt = {"a_test.mbt": 3}

    def _cf(rel):
        return _cnt.get(rel)

    cell("doc-test-count-matches", check_doc_test_claims(_doc, _cf) == [])
    # 变异对照（判例-29）：把 3 改成 9 ⇒ 必须被抓到
    cell("doc-test-count-drift-is-caught",
         len(check_doc_test_claims(_doc.replace("3 条", "9 条"), _cf)) == 1)
    cell("doc-test-count-missing-file-is-caught",
         check_doc_test_claims("2 条白盒锁 `nope_wbtest.mbt`", _cf) != [])
    cell("doc-test-count-no-claims-is-clean",
         check_doc_test_claims("本篇没有任何条数声明", _cf) == [])

    print("SELFTEST %s（%d 格：%s）" % ("OK" if not fails else "FAIL",
                                       len(cells), " ".join(cells)))
    for f in fails:
        print("SELFTEST FAIL " + f)
    return RC_OK if not fails else RC_MISMATCH


def main(argv):
    if "--selftest" in argv:
        return selftest()
    unknown = [a for a in argv if a.startswith("--") and a != "--selftest"]
    if unknown:
        print("FATAL 未知参数：%s（只接受 --selftest）" % " ".join(unknown))
        return RC_BROKEN
    try:
        text = io.open(RUN_GUARDS, encoding="utf-8", errors="replace").read()
    except OSError as e:
        print("FATAL 读不到 run_guards.py：%s ⇒ 判据无法自证" % e)
        return RC_BROKEN
    measured = []
    for entry in ENTRIES:
        if entry["measure"] == "faces":
            measured.append(measure_faces(entry))
        elif entry["measure"] == "over_faces":
            measured.append(measure_over_faces(entry))
        else:
            measured.append(None)
    problems = judge(text, measured)
    # R127：AGENTS 里「N 条测试在 `path`」的声明也对表（抽检曾 2/4 漂移）
    try:
        agents = io.open(AGENTS_DOC, encoding="utf-8", errors="replace").read()
    except OSError as e:
        print("FATAL 读不到 AGENTS.md：%s ⇒ 判据无法自证" % e)
        return RC_BROKEN

    def _count_tests(rel):
        p = os.path.join(ROOT, rel)
        if not os.path.isfile(p):
            return None
        with io.open(p, encoding="utf-8", errors="replace") as fh:
            return sum(1 for ln in fh if ln.startswith('test "'))

    _claims = parse_doc_test_claims(agents)
    doc_problems = check_doc_test_claims(agents, _count_tests)
    print("  文档条数声明：%d 处（AGENTS「N 条测试在 `path`」）" % len(_claims))
    problems = problems + doc_problems
    for entry, meas in zip(ENTRIES, measured):
        if entry["measure"] == "over_faces" and meas is not None:
            print("  实测 %-28s 应为：现读 %d 条命名判定面" % (entry["script"], meas))
        elif meas:
            claim, diag = render_claim(entry, meas)
            print("  实测 %-28s 应为：%s；%s" % (entry["script"], claim, diag))
    if problems:
        print("FAIL 登记与实测不一致：")
        for p in problems:
            print("  - " + p)
        print("修法：把 why 改成上面「应为」那行（同批提交；这是登记漂移，不是判据坏了）")
        return RC_MISMATCH
    print("PASS 登记读数与实测一致（%d 条）" % len(ENTRIES))
    return RC_OK


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
