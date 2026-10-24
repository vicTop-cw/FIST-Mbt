#!/usr/bin/env python3
"""scripts/fist-task-pool.py - task pool yaml manager (.git/fist/tasks/).
Commands: init | publish <yaml> | claim <tid> <machine> | release <tid> | archive <tid> | fail <tid> | list [--status X] [--machine Y]"""
import re, shutil, sys
from pathlib import Path
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
ROOT = Path(__file__).resolve().parent.parent
T = ROOT / ".git" / "fist" / "tasks"
M = ROOT / ".git" / "fist" / "machines.yaml"
S = ("backlog", "done", "failed")
def die(m):
    print("ERROR " + m, file=sys.stderr); sys.exit(1)
def init():
    for s in S + ("claimed",): (T / s).mkdir(parents=True, exist_ok=True)
    if not M.exists(): M.write_text("machines: {}\n", encoding="utf-8")
def parse(t):
    d, k = {}, None
    for l in t.splitlines():
        l = l.rstrip()
        if not l or l.lstrip().startswith("#"): continue
        if l.lstrip().startswith("- "):
            if k is None: die("yaml list item outside key")
            d.setdefault(k, []).append(l.strip()[2:].strip().strip('"')); continue
        m = re.match(r"^(\w+):\s*(.*)$", l)
        if not m: die("yaml line unparsed: " + l)
        k, v = m.group(1), m.group(2).strip()
        if v == "": d[k], k = [], k
        elif v.startswith("["): d[k] = [x.strip().strip('"') for x in v[1:-1].split(",") if x.strip()]
        elif v in ("null", "~"): d[k] = None
        elif re.fullmatch(r"-?\d+", v): d[k] = int(v)
        elif v.startswith('"'): d[k] = v.strip('"')
        else: d[k] = v
    return d
def dump(d):
    return "\n".join("%s: %s" % (k, "[%s]" % ", ".join(v) if isinstance(v, list) else ("null" if v is None else v)) for k, v in d.items()) + "\n"
def find(tid):
    for s in S:
        p = T / s / (tid + ".yaml")
        if p.exists(): return p
    for d in (T / "claimed").iterdir():
        p = d / (tid + ".yaml")
        if p.exists(): return p
    return None
def rd(p):
    d = parse(p.read_text(encoding="utf-8"))
    return d if d.get("task_id") else dict(d, task_id=p.stem)
def wr(p, d): p.write_text(dump(d), encoding="utf-8")
def mv(tid, sub, m=None):
    p = find(tid)
    if p is None: die("task not found: " + tid)
    d = (T / "claimed" / m if sub == "claimed" else T / sub) / (tid + ".yaml")
    d.parent.mkdir(parents=True, exist_ok=True); shutil.move(str(p), str(d)); return d
def c_init():
    init(); print("init: " + str(T.parent))
def c_pub(a):
    init(); p = Path(a)
    if not p.is_file(): die("no such yaml: " + a)
    d = parse(p.read_text(encoding="utf-8"))
    if not d.get("task_id"): die("yaml missing task_id: " + a)
    dst = T / "backlog" / (d["task_id"] + ".yaml")
    if dst.exists(): die("task already in backlog: " + d["task_id"])
    shutil.copy(str(p), str(dst)); print("publish: " + str(dst))
def c_claim(t, m):
    p = find(t)
    if p is None: die("task not found: " + t)
    d = rd(p)
    if d.get("owner"): die("task owned by " + d["owner"])
    wr(p, dict(d, owner=m, status="claimed")); mv(t, "claimed", m); print("claim: %s -> %s" % (t, m))
def c_rel(t):
    p = find(t)
    if p is None or "claimed" not in str(p): die("task not claimed: " + t)
    wr(p, dict(rd(p), owner="null", status="backlog")); mv(t, "backlog"); print("release: " + t)
def c_arc(t, st):
    p = find(t)
    if p is None: die("task not found: " + t)
    wr(p, dict(rd(p), status=st)); mv(t, st); print("%s: %s" % (st, t))
def c_lst(status=None, machine=None):
    rows = []
    for s in S + ("claimed",):
        b = T / s
        if not b.exists(): continue
        fs = [f for d in b.iterdir() for f in d.glob("*.yaml")] if s == "claimed" else list(b.glob("*.yaml"))
        rows += [rd(f) for f in fs]
    for t in sorted(rows, key=lambda x: x.get("created_at") or x.get("task_id") or ""):
        if status and t.get("status") != status: continue
        if machine and t.get("owner") != machine: continue
        print("%s | %s | owner=%s | %s" % (t.get("task_id"), t.get("status"), t.get("owner") or "-", t.get("title") or ""))
def main():
    a = sys.argv[1:]
    if not a: die("usage: fist-task-pool.py <cmd> [args]")
    c = a[0]
    if c == "init": c_init()
    elif c == "publish" and len(a) == 2: c_pub(a[1])
    elif c == "claim" and len(a) == 3: c_claim(a[1], a[2])
    elif c == "release" and len(a) == 2: c_rel(a[1])
    elif c == "archive" and len(a) == 2: c_arc(a[1], "done")
    elif c == "fail" and len(a) == 2: c_arc(a[1], "failed")
    elif c == "list": c_lst(a[a.index("--status") + 1] if "--status" in a else None, a[a.index("--machine") + 1] if "--machine" in a else None)
    else: die("bad cmd/args: " + " ".join(a))
if __name__ == "__main__":
    main()
