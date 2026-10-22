# -*- coding: utf-8 -*-
"""scripts/check_bug_refs.py — 代码注释与测试标题里的 BUG-n 必须在账本里有对应条目。

BUG-373：账本 memory/bugs.md 是真源，但全仓代码里散落着 BUG-1/BUG-376 等引用——
没有守卫核对它们是否真存在、是否已关。R47 重编号时逐站点实测到三类失配。

三档判定：
  ✅ OK        BUG-n 在账本里存在
  ⚠️ ORPHAN    BUG-n 在代码里引用但账本里**没有**这个编号
  ⚠️ CLOSED    BUG-n 在代码里引用但账本里状态是 FIXED/DUPLICATE/FALSE_POSITIVE
  ✅ SELFTEST  自检格（--selftest 合成）

用法:
  python scripts/check_bug_refs.py                       # 扫全仓
  python scripts/check_bug_refs.py --selftest            # 自检
  python scripts/check_bug_refs.py --bugs memory/bugs.md  # 指定账本路径
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

def load_bug_ids(bugs_md):
    """从 bugs.md 提取 BUG-n → status 映射。"""
    mapping = {}
    for line in bugs_md.read_text(encoding="utf-8").splitlines():
        # 匹配 "## BUG-n [...] [sev] STATUS" 形状
        m = re.match(r"## (BUG-\d+)\b.*\b(OPEN|FIXED|DUPLICATE|FALSE_POSITIVE)\b", line)
        if m:
            mapping[m.group(1)] = m.group(2)
    return mapping

def scan_repo(bug_ids):
    """扫跟踪面文件里的 BUG-n 引用（git ls-files 快且精确）。"""
    import subprocess
    results = []
    exts = (".mbt", ".py", ".md", ".yml", ".yaml", ".json", ".ps1", ".sh", ".toml")
    r = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True)
    files = [f for f in r.stdout.splitlines() if f.endswith(exts)]
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
            for m in BUG_REF.finditer(line):
                bug_id = m.group()
                ledger_status = bug_ids.get(bug_id)
                results.append((relpath, lineno, bug_id, ledger_status))
    return results

def classify(results):
    ok, orphan, closed = [], [], []
    for file, lineno, bug_id, status in results:
        if status is None:
            orphan.append((file, lineno, bug_id))
        elif status in ("FIXED", "DUPLICATE", "FALSE_POSITIVE"):
            closed.append((file, lineno, bug_id, status))
        else:
            ok.append((file, lineno, bug_id))
    return ok, orphan, closed

def selftest():
    """真断言（旧版只 print 三行 ✅ 然后 return 0 —— **不做任何判断**，
    这种"自检"本身就是假绿：逻辑坏掉它照样绿。以下每格都构造合成输入并断言 classify/rc 映射）。"""
    cells = []

    def cell(name, got, want):
        cells.append((name, got == want, "got=%r want=%r" % (got, want)))

    ledger = {"BUG-42": "OPEN", "BUG-33": "FIXED", "BUG-7": "DUPLICATE"}
    results = [
        ("a.mbt", 1, "BUG-42", ledger.get("BUG-42")),   # 在账本且 OPEN ⇒ ok
        ("b.mbt", 2, "BUG-9999", ledger.get("BUG-9999")),  # 账本没有 ⇒ orphan
        ("c.mbt", 3, "BUG-33", ledger.get("BUG-33")),   # 已修 ⇒ closed（信息，不是违规）
        ("d.mbt", 4, "BUG-7", ledger.get("BUG-7")),     # DUPLICATE ⇒ closed
    ]
    ok, orphan, closed = classify(results)
    cell("classify-ok-count", len(ok), 1)
    cell("classify-orphan-count", len(orphan), 1)
    cell("classify-orphan-names-bug", orphan[0][2], "BUG-9999")
    cell("classify-closed-count", len(closed), 2)

    # 退出码语义（本仓约定：0 干净 / 1 发现违规 / 2 判据取不到量）
    # 注意：classify 出来的 orphan 非空 ⇒ 本格若直接喂它会得 1（这是我第一版写错的期望，
    # 被真断言当场抓出）。干净格必须喂"三项都空"的集合。
    cell("rc-clean", exit_code([("a.mbt", 1, "BUG-42")], [], [], strict=True), 0)
    cell("rc-classified-set-with-orphan-is-1", exit_code(ok, orphan, closed, strict=True), 1)
    cell("rc-orphan-strict-is-1-not-2", exit_code([], [("x", 1, "BUG-1")], [], strict=True), 1)
    cell("rc-closed-is-info-not-failure", exit_code([], [], [("x", 1, "BUG-2", "FIXED")], strict=True), 0)
    cell("rc-closed-opt-in-strict", exit_code([], [], [("x", 1, "BUG-2", "FIXED")], strict=True,
                                              strict_closed=True), 1)
    cell("rc-non-strict-always-0", exit_code([], [("x", 1, "BUG-1")], [("y", 2, "BUG-2", "FIXED")],
                                            strict=False), 0)

    bad = [(n, w) for n, okk, w in cells if not okk]
    if bad:
        print("SELFTEST FAIL：")
        for n, w in bad:
            print("  - %s：%s" % (n, w))
        return 1
    print("SELFTEST OK（%d 格：classify 三档计数 + 退出码语义 5 档，全部真断言）" % len(cells))
    return 0


def exit_code(ok, orphan, closed, strict, strict_closed=False):
    """退出码单一真源：0 干净 / 1 违规 / 2 判据取不到量（这里取不到量的情形在 main 里判）。

    政策（实测校订）：**ORPHAN 才是违规**（引用了账本里不存在的编号 = 悬空引用）；
    **CLOSED 只是信息**——在注释里引用一个已修的 BUG-n 是本仓的**正常写法**
    （如 `# BUG-88：PS5.1 读 .ps1 需 BOM`），全仓实测 7000+ 处，把它算违规等于让门永红，
    而"永红"最终就是没人读。要拿 CLOSED 当门的人显式开 `--strict-closed`。
    """
    if not strict:
        return 0
    if orphan:
        return 1
    if strict_closed and closed:
        return 1
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--bugs", default="memory/bugs.md")
    ap.add_argument("--strict", action="store_true",
                    help="ORPHAN（悬空引用）存在即 rc=1；CLOSED 仅信息（引用已修 bug 是正常注释）")
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
    print(f"🔍 全仓扫到 {len(results)} 处 BUG-n 引用")
    ok, orphan, closed = classify(results)

    print(f"\n✅ OK      {len(ok)} 处（编号在账本里且未终态）")
    if orphan:
        # 545 处逐条列出来没人能处理；按编号聚合才能行动（实测：545 处其实只落在几十个"幻影编号"上）。
        cnt = Counter(bid for _f, _l, bid in orphan)
        print(f"⚠️  ORPHAN  {len(orphan)} 处 / {len(cnt)} 个编号"
              f"（引用了但账本里没有该编号的抬头 = 悬空引用，**这是违规**）:")
        for bid, n in cnt.most_common(15):
            sample = next(f for f, _l, b in orphan if b == bid)
            print(f"  {bid:<11} {n:>4} 处   例: {sample}")
        if len(cnt) > 15:
            print(f"  ... 还有 {len(cnt)-15} 个编号（用 --list-all 看全量）")
        if args.list_all:
            print("  全量清单：")
            for f, ln, bid in orphan:
                print(f"    {f}:{ln} → {bid}")
    if closed:
        print(f"ℹ️  CLOSED  {len(closed)} 处（引用已终态编号——本仓正常写法，仅信息；--strict-closed 可转违规）:")
        for f, ln, bid, st in closed[:5]:
            print(f"  {f}:{ln} → {bid} [{st}]")
        if len(closed) > 5:
            print(f"  ... 还有 {len(closed)-5} 处")
    if not orphan and not closed:
        print("🎉 全仓 BUG-n 引用与账本完全对齐")

    rc = exit_code(ok, orphan, closed, args.strict, args.strict_closed)
    print(f"\n汇总：ok={len(ok)} orphan={len(orphan)} closed={len(closed)}")
    print(f"rc={rc} (strict={args.strict} strict_closed={args.strict_closed})")
    sys.exit(rc)

if __name__ == "__main__":
    main()
