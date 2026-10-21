#!/usr/bin/env python3
"""scripts/fist-gate.py - unified gate chain (merge_markers/fmt/build/ps_encoding/store_path). rc: 0=pass 1=fail 2=degraded."""
import re, subprocess, sys, tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
EXC = ("_build", "temp", ".git", "node_modules")
def run(cmd, cwd=None): return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace")
def tracked(root):
    r = run(["git", "-C", str(root), "ls-files", "-z"])
    return None if r.returncode else [f for f in r.stdout.split("\0") if f.strip()]
def pick(files, suffix, prefix=""): return [f for f in files if f.startswith(prefix) and f.endswith(suffix) and not any(x in Path(f).parts for x in EXC)]
def ck_mm(root):
    if root == ROOT:
        r = run(["python", "scripts/blackbox/check_merge_markers.py"], cwd=root)
        out = (r.stdout.strip().splitlines() or ["no output"])[-1]
        return (2, "DEGRADED merge_markers: " + out) if r.returncode == 2 else (r.returncode, out)
    fs = tracked(root)
    if fs is None: return 2, "DEGRADED merge_markers: git unavailable"
    bad = [f for f in fs if any(l.startswith(("<<<<<<<", "=======", ">>>>>>>")) for l in (root / f).read_text(encoding="utf-8", errors="replace").splitlines())]
    return (1, "FAIL merge_markers: " + ", ".join(bad)) if bad else (0, "merge_markers: %d files ok" % len(fs))
def ck_fmt(root):
    r = run(["moon", "fmt", "--check"], cwd=root)
    if r.returncode == 0: return 0, "moon fmt --check: clean"
    if r.returncode == 1: return 1, "moon fmt --check: format diff"
    return 2, "DEGRADED fmt: rc=%d %s" % (r.returncode, ((r.stderr + r.stdout).strip().splitlines() or ["no output"])[-1])
def ck_build(root):
    r = run(["moon", "build", "--target", "js", "src/server", "src/engine", "src/store", "src/router", "src/ops"], cwd=root)
    return (0, "build: rc=0, 0 errors") if r.returncode == 0 else (1, "build FAIL rc=%d tail: %s" % (r.returncode, (r.stdout + r.stderr)[-160:]))
def ck_ps(root):
    fs = tracked(root)
    if fs is None: return 2, "DEGRADED ps_encoding: git unavailable"
    ps = pick(fs, ".ps1")
    if not ps: return 2, "DEGRADED ps_encoding: no tracked .ps1 (empty scan)"
    bad = [f for f in ps if any(x > 127 for x in (root / f).read_bytes()) and not (root / f).read_bytes().startswith(b"\xef\xbb\xbf")]
    return (1, "FAIL ps_encoding: " + ", ".join(bad)) if bad else (0, "ps_encoding: %d .ps1 ASCII/BOM ok" % len(ps))
def ck_sp(root):
    fs = tracked(root)
    if fs is None: return 2, "DEGRADED store_path: git unavailable"
    st = [f for f in pick(fs, ".mbt", "src/store/") if not f.endswith("_test.mbt")]
    if not st: return 2, "DEGRADED store_path: no src/store/*.mbt (empty scan)"
    pat = re.compile(r'"[^"\n]*(?:C:|c:)[\\/][^"\n]*"|"[^"\n]*/(?:etc|home|usr|var|root)/[^"\n]*"|"[^"\n]*\\\\[A-Za-z][^"\n]*"')
    bad = [f for f in st if pat.search((root / f).read_text(encoding="utf-8", errors="replace"))]
    return (1, "FAIL store_path: " + ", ".join(bad)) if bad else (0, "store_path: %d store files ok" % len(st))
CHECKS = [("merge_markers", ck_mm), ("fmt", ck_fmt), ("build", ck_build), ("ps_encoding", ck_ps), ("store_path", ck_sp)]
def safe(name, fn, root):
    try: return fn(root)
    except Exception as e: return 2, "DEGRADED %s: %s" % (name, e)
def gate(root):
    rc = 0
    for name, fn in CHECKS:
        c, line = safe(name, fn, root)
        print(("FAIL " if c == 1 else "DEGRADED " if c == 2 else "PASS ") + name + ": " + line)
        rc = max(rc, c)
    return rc
def selftest():
    executed, fails = [], []
    def repo(files):
        d = Path(tempfile.mkdtemp(prefix="fg-"))
        run(["git", "init", "-q"], cwd=d); run(["git", "config", "user.email", "t@t"], cwd=d); run(["git", "config", "user.name", "t"], cwd=d)
        for rel, body in files.items():
            p = d / rel; p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(body) if isinstance(body, bytes) else p.write_text(body, encoding="utf-8")
        run(["git", "add", "-A"], cwd=d); run(["git", "commit", "-qm", "f"], cwd=d)
        return d
    def probe(name, fn, d, want, label):
        c, line = safe(name, fn, d); executed.append(label % (name, c))
        if c != want: fails.append("%s rc=%d want %d: %s" % (name, c, want, line))
    bad = repo({"x.mbt": "a\n<<<<<<< HEAD\nb\n=======\nc\n>>>>>>> t\n", "bad.ps1": b"Write-Output '\xc4\xe2\xba\xba'\n", "src/store/x.mbt": "let p = \"C:\\\\data\"\n"})
    for name, fn in [("merge_markers", ck_mm), ("ps_encoding", ck_ps), ("store_path", ck_sp)]: probe(name, fn, bad, 1, "G1 %s red-on-inject rc=%d")
    clean = repo({"ok.ps1": b"Write-Output 'ascii'\n", "src/store/y.mbt": "let p = \"data\"\n", "a.mbt": "def f() = 1\n"})
    for name, fn in [("merge_markers", ck_mm), ("ps_encoding", ck_ps), ("store_path", ck_sp)]: probe(name, fn, clean, 0, "G2 %s green-on-clean rc=%d")
    probe("ps_encoding", ck_ps, repo({"a.mbt": "def f() = 1\n"}), 2, "G3 %s empty-scan self-reject rc=%d")
    for name, fn in [("fmt", ck_fmt), ("build", ck_build)]: c, line = safe(name, fn, ROOT); executed.append("G4 %s observable-on-real (rc=%d)" % (name, c)); fails.append("G4 %s rc=%d degraded: %s" % (name, c, line)) if c not in (0, 1) else None
    print("SELFTEST %s (grid: %s)" % ("OK" if not fails else "FAIL", " / ".join(executed)))
    for f in fails: print("SELFTEST FAIL " + f)
    return 0 if not fails else 2
if __name__ == "__main__":
    if "--selftest" in sys.argv[1:]: sys.exit(selftest())
    if len(sys.argv) > 1: raise SystemExit("usage: python scripts/fist-gate.py [--selftest]")
    sys.exit(gate(ROOT))
