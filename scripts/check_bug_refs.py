# -*- coding: utf-8 -*-
"""scripts/check_bug_refs.py — 代码注释与测试标题里的 BUG-n 必须在账本里有对应条目。

BUG-373：账本 memory/bugs.md 是真源，但全仓代码里散落着 BUG-1/BUG-376 等引用——
没有守卫核对它们是否真存在、是否已关。R47 重编号时逐站点实测到三类失配。

R115/TASK-020 裁决（两把尺并存、各钉一面，不合并）：
  · check_bug_reference_integrity.py（R48 立、已接 CI）= `.mbt` 注释面悬空的棘轮门（J1=0）；
  · 本尺 = 全仓普查 + 可分面的 `--strict`：只有**注释面 ORPHAN** 计入判定面，
    字面量（wbtest 合成语料）与叙述面（.md/.yaml/…）只报不判，CLOSED 仅信息。
  夹具降档（与前者 S1b 同口径）：测试文件里的注释面编号若在同文件字面量面也出现 ⇒ 那是
  夹具说明注释，机械降为 string。棘轮 `STRICT_ORPHAN_CEILING` 只许降不许升。

面分类：
  · comment    代码注释（`.mbt` 的 `//`、`.py/.ps1/.sh` 的 `#` 之后）
  · string     代码文件里的字面量（测试合成语料，如 BUG-901/999）
  · narrative  文档面（.md/.yml/.yaml/.json/.toml）

三档判定：
  ✅ OK        BUG-n 在账本里存在
  ⚠️ ORPHAN    BUG-n 在代码里引用但账本里**没有**这个编号
  ⚠️ CLOSED    BUG-n 在代码里引用但账本里状态是 FIXED/DUPLICATE/FALSE_POSITIVE
  ✅ SELFTEST  自检格（--selftest 合成）

用法:
  python scripts/check_bug_refs.py                       # 扫全仓（只报不判）
  python scripts/check_bug_refs.py --strict              # 注释面 ORPHAN 不得超过棘轮上限
  python scripts/check_bug_refs.py --selftest            # 自检
  python scripts/check_bug_refs.py --bugs memory/bugs.md  # 指定账本路径

退出码：0=通过/只报告 / 1=注释面 ORPHAN 超过棘轮上限（或 --strict-closed 命中 CLOSED）/
       2=账本不存在或扫描面取不到量（空扫描自拒，绝不报绿）。
"""
from collections import Counter
import argparse, os, re, sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
EXCL = ("_build", "temp", ".git", "node_modules", ".mooncakes",
        "plugins", "reports", "docs/archive", ".hermes")
BUG_REF = re.compile(r"\bBUG-\d+\b")  # 匹配 BUG-n 形状
NARRATIVE_EXTS = (".md", ".yml", ".yaml", ".json", ".toml")
CLOSED_STATUSES = ("FIXED", "DUPLICATE", "FALSE_POSITIVE")
# R115/TASK-020 棘轮：--strict 只数注释面 ORPHAN。立单现读 3 条，全部落在
# scripts/commit_bug335_lock.ps1 的注释（两个脚本自述编号均不在账本，README 同名
# 条目已点名「脚本自述编号未入账，别当账本事实」）。只许降不许升。
STRICT_ORPHAN_CEILING = 3


def is_excluded(relpath):
    """路径是否落在声明排除面（R115：EXCL 以前只声明没生效，reports/ 169 条噪音就是这么进来的）。"""
    rel = relpath.replace("\\", "/")
    return any(rel == e or rel.startswith(e + "/") for e in EXCL)


def load_bug_ids(bugs_md):
    """从 bugs.md 提取 BUG-n → status 映射。"""
    mapping = {}
    for line in bugs_md.read_text(encoding="utf-8").splitlines():
        # 匹配 "## BUG-n [...] [sev] STATUS" 形状
        m = re.match(r"## (BUG-\d+)\b.*\b(OPEN|FIXED|DUPLICATE|FALSE_POSITIVE)\b", line)
        if m:
            mapping[m.group(1)] = m.group(2)
    return mapping


def _mbt_faces(line):
    """按列扫描一行 MoonBit，返回 [(BUG-n, face)]。注释优先于字面量（同完整性守卫口径）。"""
    out = []
    in_str = False
    esc = False
    comment_at = None
    for i, ch in enumerate(line):
        if comment_at is None:
            if ch == '"':
                if not esc:
                    in_str = not in_str
            elif ch == "\\":
                esc = not esc
                continue
            elif line.startswith("//", i) and not in_str:
                comment_at = i
        esc = False
        m = BUG_REF.match(line, i)
        if m and i > 0 and (line[i - 1].isalnum() or line[i - 1] == "_"):
            continue  # 防把 `XBUG-1` 这类更长 token 切出假引用
        if m:
            if comment_at is not None and i >= comment_at:
                out.append((m.group(), "comment"))
            else:
                out.append((m.group(), "string" if in_str else "code"))
    return out


def _hash_comment_at(line):
    """`.py/.ps1/.sh` 一行的第一个注释符列位（引号内的 # 不算注释）。"""
    quote = None
    esc = False
    for i, ch in enumerate(line):
        if esc:
            esc = False
            continue
        if quote:
            if ch == "\\" and quote == '"':
                esc = True
            elif ch == quote:
                quote = None
            continue
        if ch in "\"'":
            quote = ch
        elif ch == "#":
            return i
    return None


def line_faces(relpath, line):
    """按扩展名把一行里的 BUG-n 归到 comment / string / narrative 三面之一。"""
    ext = Path(relpath).suffix
    if ext in NARRATIVE_EXTS:
        return [(m.group(), "narrative") for m in BUG_REF.finditer(line)]
    if ext == ".mbt":
        return _mbt_faces(line)
    if ext in (".py", ".ps1", ".sh"):
        at = _hash_comment_at(line)
        return [(m.group(), "comment" if at is not None and m.start() >= at else "string")
                for m in BUG_REF.finditer(line)]
    return [(m.group(), "narrative") for m in BUG_REF.finditer(line)]


def _is_test_file(relpath):
    return relpath.endswith("_test.mbt") or relpath.endswith("_wbtest.mbt")


def downgrade_fixtures(results):
    """测试文件里注释面的编号若在同文件字面量面出现 ⇒ 夹具说明注释，降为 string（S1b 同口径）。"""
    string_ids = {}
    for rel, _ln, bid, _st, face in results:
        if face == "string":
            string_ids.setdefault(rel, set()).add(bid)
    out = []
    for rel, ln, bid, st, face in results:
        if face == "comment" and _is_test_file(rel) and bid in string_ids.get(rel, ()):
            face = "string"
        out.append((rel, ln, bid, st, face))
    return out


def scan_repo(bug_ids):
    """扫跟踪面文件里的 BUG-n 引用（git ls-files 快且精确；EXCL 声明面 R115 起真生效）。"""
    import subprocess
    results = []
    exts = (".mbt", ".py", ".md", ".yml", ".yaml", ".json", ".ps1", ".sh", ".toml")
    r = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True)
    files = [f for f in r.stdout.splitlines() if f.endswith(exts) and not is_excluded(f)]
    if r.returncode != 0 or not files:
        return None  # 判据取不到量 ⇒ main 给 2，绝不把「没测到」报成绿
    for relpath in files:
        f = ROOT / relpath
        if not f.exists():
            continue
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        for lineno, line in enumerate(text.splitlines(), 1):
            # 跳过 bugs.md 自己（真源）
            if relpath.endswith("bugs.md") and line.startswith("## BUG-"):
                continue
            for bug_id, face in line_faces(relpath, line):
                results.append((relpath, lineno, bug_id, bug_ids.get(bug_id), face))
    return downgrade_fixtures(results)


def classify(results):
    ok, orphan, closed = [], [], []
    for file, lineno, bug_id, status, face in results:
        if status is None:
            orphan.append((file, lineno, bug_id, face))
        elif status in CLOSED_STATUSES:
            closed.append((file, lineno, bug_id, status, face))
        else:
            ok.append((file, lineno, bug_id, face))
    return ok, orphan, closed


def gate_orphans(orphan):
    """判定面：只有注释面 ORPHAN 算违规；string/narrative 只报。"""
    return [o for o in orphan if o[3] == "comment"]


def selftest():
    """真断言（旧版只 print 三行 ✅ 然后 return 0 —— **不做任何判断**，
    这种"自检"本身就是假绿：逻辑坏掉它照样绿。以下每格都构造合成输入并断言 classify/face/rc 映射）。"""
    cells = []

    def cell(name, got, want):
        cells.append((name, got == want, "got=%r want=%r" % (got, want)))

    ledger = {"BUG-42": "OPEN", "BUG-33": "FIXED", "BUG-7": "DUPLICATE"}
    results = [
        ("a.mbt", 1, "BUG-42", ledger.get("BUG-42"), "comment"),   # 在账本且 OPEN ⇒ ok
        ("b.mbt", 2, "BUG-9999", ledger.get("BUG-9999"), "string"),  # 合成语料 ⇒ orphan/string
        ("c.mbt", 3, "BUG-33", ledger.get("BUG-33"), "string"),   # 已修 ⇒ closed（信息，不是违规）
        ("d.mbt", 4, "BUG-7", ledger.get("BUG-7"), "comment"),     # DUPLICATE ⇒ closed
    ]
    ok, orphan, closed = classify(results)
    cell("classify-ok-count", len(ok), 1)
    cell("classify-orphan-count", len(orphan), 1)
    cell("classify-orphan-names-bug", orphan[0][2], "BUG-9999")
    cell("classify-closed-count", len(closed), 2)
    cell("gate-excludes-string", gate_orphans(orphan), [])

    # 面分类：注释/字面量/叙述三分；hash 类语言按 # 切面；字符串里的 # 不算注释。
    cell("face-mbt-comment", _mbt_faces('// 残留 BUG-42'), [("BUG-42", "comment")])
    cell("face-mbt-string", _mbt_faces('let s = "BUG-42"'), [("BUG-42", "string")])
    cell("face-py-comment", line_faces("x.py", "# BUG-42"), [("BUG-42", "comment")])
    cell("face-py-string-hash", line_faces("x.py", 's = "pre # BUG-42"'), [("BUG-42", "string")])
    cell("face-narrative", line_faces("x.md", "见 BUG-42"), [("BUG-42", "narrative")])

    # 夹具降档：测试文件同号也在字面量面 ⇒ 注释降 string；非测试文件不降。
    fixture = [
        ("t_wbtest.mbt", 1, "BUG-901", None, "comment"),
        ("t_wbtest.mbt", 2, "BUG-901", None, "string"),
        ("prod.ps1", 3, "BUG-339", None, "comment"),
        ("prod.ps1", 4, "BUG-339", None, "string"),
    ]
    dd = {(r[0], r[1]): r[4] for r in downgrade_fixtures(fixture)}
    cell("fixture-comment-downgraded", dd[("t_wbtest.mbt", 1)], "string")
    cell("prod-comment-not-downgraded", dd[("prod.ps1", 3)], "comment")

    # 排除面（R115 修复：声明了就要生效）
    cell("excl-reports", is_excluded("reports/a.md"), True)
    cell("excl-docs-archive", is_excluded("docs/archive/a.md"), True)
    cell("excl-memory-not-excluded", is_excluded("memory/a.md"), False)
    cell("excl-prefix-boundary", is_excluded("reportsX/a.md"), False)

    # 退出码语义（本仓约定：0 干净 / 1 发现违规 / 2 判据取不到量）
    two = [("x.ps1", 1, "BUG-339", "comment"), ("x.ps1", 2, "BUG-335", "comment")]
    three = two + [("x.ps1", 3, "BUG-1", "comment")]
    cell("rc-clean", exit_code([], [], [], strict=True), 0)
    cell("rc-comment-orphan-at-ceiling", exit_code([], two, [], strict=True, ceiling=2), 0)
    cell("rc-comment-orphan-over-ceiling", exit_code([], three, [], strict=True, ceiling=2), 1)
    cell("rc-string-narrative-not-gated", exit_code([], [
        ("x.mbt", 1, "BUG-9999", "string"), ("x.md", 1, "BUG-77", "narrative")],
        [], strict=True, ceiling=0), 0)
    cell("rc-closed-is-info-not-failure", exit_code([], [], [("x", 1, "BUG-2", "FIXED", "comment")],
                                                    strict=True), 0)
    cell("rc-closed-opt-in-strict", exit_code([], [], [("x", 1, "BUG-2", "FIXED", "comment")],
                                              strict=True, strict_closed=True), 1)
    cell("rc-non-strict-always-0", exit_code([], three, [("y", 2, "BUG-2", "FIXED", "comment")],
                                            strict=False), 0)

    # 校准格：真实语料上的注释面 ORPHAN 必须恰好等于棘轮上限——降了就说明该收紧上限，
    # 升了就说明悬空引用变多；两边都要人改常数，不允许静默漂。
    bugs_path = ROOT / "memory/bugs.md"
    if bugs_path.exists():
        real = scan_repo(load_bug_ids(bugs_path))
        if real is None:
            cells.append(("calib-scan-self-refuse", False,
                          "git ls-files 取不到扫描面 ⇒ 校准格取不到量，判据应自拒而不是报绿"))
        else:
            _ok, real_orphan, _closed = classify(real)
            cell("calib-real-corpus-gate-at-ceiling", len(gate_orphans(real_orphan)),
                 STRICT_ORPHAN_CEILING)
    else:
        cells.append(("calib-ledger-present", False, "memory/bugs.md 不存在，校准格取不到量"))

    bad = [(n, w) for n, okk, w in cells if not okk]
    if bad:
        print("SELFTEST FAIL：")
        for n, w in bad:
            print("  - %s：%s" % (n, w))
        return 1
    print("SELFTEST OK（%d 格：三档计数 + 三面分类 + 夹具降档 + 排除面 + 退出码/棘轮 + 真语料校准，全部真断言）" % len(cells))
    return 0


def exit_code(ok, orphan, closed, strict, strict_closed=False, ceiling=STRICT_ORPHAN_CEILING):
    """退出码单一真源：0 干净 / 1 违规 / 2 判据取不到量（这里取不到量的情形在 main 里判）。

    政策（R115/TASK-020 裁决）：**只有注释面 ORPHAN 进判定面**——引用了账本里不存在的编号
    才是悬空引用；字面量是测试合成语料、叙述面是文档叙述，只报不判。**CLOSED 只是信息**——
    在注释里引用一个已修的 BUG-n 是本仓的正常写法（如 `# BUG-88：PS1 读 .ps1 需 BOM`），
    全仓现读 9000+ 处，把它算违规等于让门永红，而"永红"最终就是没人读。
    要拿 CLOSED 当门的人显式开 `--strict-closed`。
    注释面 ORPHAN 过 `ceiling` 才红：棘轮只许降不许升，`--selftest` 的校准格钉住现读值。
    """
    if not strict:
        return 0
    if len(gate_orphans(orphan)) > ceiling:
        return 1
    if strict_closed and closed:
        return 1
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--bugs", default="memory/bugs.md")
    ap.add_argument("--strict", action="store_true",
                    help="注释面 ORPHAN 超过棘轮上限即 rc=1；字面量/叙述面与 CLOSED 仅信息")
    ap.add_argument("--strict-closed", action="store_true",
                    help="额外把 CLOSED 也算违规（默认不算）")
    ap.add_argument("--list-all", action="store_true", help="ORPHAN 逐条列全（默认按编号聚合）")
    args = ap.parse_args()

    if args.selftest:
        sys.exit(selftest())

    bugs_path = ROOT / args.bugs
    if not bugs_path.exists():
        print(f"FATAL 账本不存在: {bugs_path}")
        sys.exit(2)

    bug_ids = load_bug_ids(bugs_path)
    print(f"📋 账本里加载了 {len(bug_ids)} 条 BUG-n")
    results = scan_repo(bug_ids)
    if results is None:
        print("FATAL git ls-files 枚举失败或扫描面为空 ⇒ 无从判定，绝不报绿")
        sys.exit(2)
    print(f"🔍 全仓扫到 {len(results)} 处 BUG-n 引用（排除面 {', '.join(EXCL)}）")
    ok, orphan, closed = classify(results)
    gate = gate_orphans(orphan)

    face_cnt = Counter(o[3] for o in orphan)
    print(f"\n✅ OK      {len(ok)} 处（编号在账本里且未终态）")
    print(f"🧭 面分布  ORPHAN 里 comment={face_cnt.get('comment', 0)} / "
          f"string={face_cnt.get('string', 0)} / narrative={face_cnt.get('narrative', 0)}"
          f"（R115：--strict 只判注释面）")
    if orphan:
        # 逐条列出来没人能处理；按编号聚合才能行动。
        cnt = Counter(bid for _f, _l, bid, _face in orphan)
        print(f"⚠️  ORPHAN  {len(orphan)} 处 / {len(cnt)} 个编号"
              f"（引用了但账本里没有该编号的抬头 = 悬空引用；判定面 = 注释面 {len(gate)} 处）:")
        for bid, n in cnt.most_common(15):
            sample = next(f for f, _l, b, _face in orphan if b == bid)
            print(f"  {bid:<11} {n:>4} 处   例: {sample}")
        if len(cnt) > 15:
            print(f"  ... 还有 {len(cnt)-15} 个编号（用 --list-all 看全量）")
        if args.list_all:
            print("  全量清单：")
            for f, ln, bid, face in orphan:
                print(f"    {f}:{ln} → {bid} [{face}]")
    if closed:
        print(f"ℹ️  CLOSED  {len(closed)} 处（引用已终态编号——本仓正常写法，仅信息；--strict-closed 可转违规）:")
        for f, ln, bid, st, _face in closed[:5]:
            print(f"  {f}:{ln} → {bid} [{st}]")
        if len(closed) > 5:
            print(f"  ... 还有 {len(closed)-5} 处")
    if not orphan and not closed:
        print("🎉 全仓 BUG-n 引用与账本完全对齐")

    rc = exit_code(ok, orphan, closed, args.strict, args.strict_closed)
    print(f"\n汇总：ok={len(ok)} orphan={len(orphan)} comment_orphan={len(gate)}"
          f" closed={len(closed)} 棘轮={STRICT_ORPHAN_CEILING}")
    print(f"rc={rc} (strict={args.strict} strict_closed={args.strict_closed})")
    sys.exit(rc)


if __name__ == "__main__":
    main()
