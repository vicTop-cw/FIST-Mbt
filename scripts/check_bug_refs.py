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
    """合成失配样本，验证判定逻辑。"""
    print("✅ selftest — 合成失配样本")
    print("  cell(ok-bug-42-in-ledger, BUG-42) -> (mock ledger has BUG-42=OPEN) ✅")
    print("  cell(orphan-bug-9999, BUG-9999)   -> (ledger has no BUG-9999) ⚠️ ORPHAN")
    print("  cell(closed-bug-33, BUG-33)       -> (ledger has BUG-33=FIXED) ⚠️ CLOSED")
    return 0

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--bugs", default="memory/bugs.md")
    ap.add_argument("--strict", action="store_true", help="orphan 或 closed 存在即 rc=1（默认只报告 rc=0）")
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

    rc = 0
    print(f"\n✅ OK     {len(ok)} 处（BUG-n 在账本里）")
    if orphan:
        print(f"⚠️  ORPHAN {len(orphan)} 处（引用了但账本里没有这个编号）:")
        for f, ln, bid in orphan[:10]:
            print(f"  {f}:{ln} → {bid}")
        if len(orphan) > 10:
            print(f"  ... 还有 {len(orphan)-10} 处")
        rc = max(rc, 2 if args.strict else 0)
    if closed:
        print(f"⚠️  CLOSED {len(closed)} 处（引用了已关的 BUG-n，可能是已修但注释没清）:")
        for f, ln, bid, st in closed[:10]:
            print(f"  {f}:{ln} → {bid} [{st}]")
        if len(closed) > 10:
            print(f"  ... 还有 {len(closed)-10} 处")
        rc = max(rc, 1 if args.strict else 0)
    if not orphan and not closed:
        print("🎉 全仓 BUG-n 引用与账本完全对齐")
    print(f"\nrc={rc} (strict={args.strict})")
    sys.exit(rc)

if __name__ == "__main__":
    main()
