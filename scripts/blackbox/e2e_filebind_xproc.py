#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""F094 Phase 1 验收黑盒：两进程 file_bind 协调（跨进程可见性 + 一成一拒）。

进程 A 绑定后退出；进程 B（全新 server 进程，同一隔离库）必须看到持久化的绑定：
同路径 → conflict 并**点名 agent-A**（验收格「恰好一成一拒」）；不同路径 → 并行不冲突；
agent-A 释放 → B 重绑成功；TTL 过期 → 他 holder 接管（BndReclaimed）。

协议注记：与 e2e_heartbeat_xproc.py 同款——无 initialize 握手，_meta 逐条请求带。
红线：FIST_DB_PATH 隔离库，绝不碰仓库根台账。
"""
import json
import os
import shutil
import subprocess
import sys
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CLI = os.path.join(ROOT, "_build", "js", "debug", "build", "cmd", "cli", "cli.js")
BOX = os.path.join(ROOT, "temp", "fb-xproc-box")
DB = os.path.join(ROOT, "temp", "fb-xproc.db")

META = {
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": {},
    "io.modelcontextprotocol/clientInfo": {"name": "fb-xproc-guard", "version": "1"},
}

RESULTS = []


def say(k, v):
    print("%s: %s" % (k, v))


def arm(name, ok, detail=""):
    RESULTS.append((name, bool(ok)))
    say("ARM %s" % ("PASS" if ok else "FAIL"), "%s %s" % (name, detail))


def die(msg, hint=""):
    print("DIE " + msg)
    if hint:
        print("HINT " + hint)
    sys.exit(2)


class Sess:
    """一个真 `node cli.js serve` 进程：FIST_DB_PATH 指到隔离库。"""

    def __init__(self, tag):
        if not os.path.isfile(CLI):
            die("产物不存在 %s" % CLI, "moon build --target js cmd/cli")
        env = dict(os.environ)
        env["FIST_DB_PATH"] = DB
        self.errf = open(os.path.join(ROOT, "temp", "fb-xproc-%s.err" % tag),
                         "w", encoding="utf-8")
        self.p = subprocess.Popen(
            ["node", CLI, "serve"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=self.errf, cwd=BOX, env=env, bufsize=0)
        self.tag = tag
        self.lines = []
        threading.Thread(target=self._pump, daemon=True).start()

    def _pump(self):
        for raw in iter(self.p.stdout.readline, b""):
            s = raw.decode("utf-8", "replace").strip()
            if s.startswith("{"):
                try:
                    self.lines.append(json.loads(s))
                except Exception:
                    pass

    def call(self, name, args, timeout=30):
        self.n = getattr(self, "n", 0) + 1
        my = self.n
        req = {"jsonrpc": "2.0", "id": my, "method": "tools/call",
               "params": {"name": name, "arguments": args, "_meta": META}}
        self.p.stdin.write((json.dumps(req) + "\n").encode())
        self.p.stdin.flush()
        t0 = time.time()
        while time.time() - t0 < timeout:
            hit = [m for m in self.lines if m.get("id") == my]
            if hit:
                r = hit[0]
                if "error" in r:
                    return {"_error": r["error"].get("message")}
                c = r.get("result") or {}
                txt = (c.get("content") or [{}])[0].get("text", "")
                try:
                    return json.loads(txt)
                except Exception:
                    return {"_raw": txt}
            time.sleep(0.05)
        return {"_timeout": True}

    def kill(self):
        try:
            self.p.stdin.close()
        except Exception:
            pass
        try:
            self.p.kill()
            self.p.wait(timeout=5)
        except Exception:
            pass


def main():
    if os.path.exists(DB):
        os.remove(DB)
    if os.path.isdir(BOX):
        shutil.rmtree(BOX, ignore_errors=True)
    os.makedirs(os.path.join(BOX, "src"), exist_ok=True)
    with open(os.path.join(BOX, "src", "x.mbt"), "w", encoding="utf-8") as f:
        f.write("// probe fixture\n")

    PD = "."

    # 进程 A：绑定 src/x.mbt（agent-A / T1）
    a = Sess("A")
    r = a.call("file_bind", {"project_dir": PD, "paths": ["src/x.mbt"],
                             "holder": "agent-A", "task_id": "T1",
                             "kind": "file", "scope": "edit",
                             "intent": "F094 xproc"})
    arm("A1_bind_first", r.get("bound") == 1, json.dumps(r.get("rows", []))[:200])
    a.kill()

    # 进程 B（全新进程，同一隔离库）：同路径 → conflict 点名 agent-A
    b = Sess("B")
    r = b.call("file_bind", {"project_dir": PD, "paths": ["src/x.mbt"],
                             "holder": "agent-B", "task_id": "T2",
                             "kind": "file", "scope": "edit"})
    rows = r.get("rows") or []
    verdict = rows[0].get("verdict") if rows else "?"
    holder = rows[0].get("holder") if rows else "?"
    arm("B1_conflict_names_holder", verdict == "conflict" and holder == "agent-A",
        "verdict=%s holder=%s" % (verdict, holder))

    # B：不同路径 → 并行不冲突
    r = b.call("file_bind", {"project_dir": PD, "paths": ["src/y.mbt"],
                             "holder": "agent-B", "task_id": "T2",
                             "kind": "file", "scope": "edit"})
    arm("B2_parallel_other_path", r.get("bound") == 1, "")

    # B：file_status 可见 A 的绑定（跨进程读）
    r = b.call("file_status", {"project_dir": PD, "paths": ["src/x.mbt"]})
    entries = r.get("entries") or []
    st_holder = entries[0].get("holder") if entries else "?"
    arm("B3_status_xproc_visible", r.get("total") == 1 and st_holder == "agent-A",
        "total=%s holder=%s" % (r.get("total"), st_holder))

    # A 回来：释放自己的绑定
    r = a2_release()
    arm("A2_release", r.get("released") == 1, "")

    # B：释放后重绑同路径 → 成功
    r = b.call("file_bind", {"project_dir": PD, "paths": ["src/x.mbt"],
                             "holder": "agent-B", "task_id": "T2",
                             "kind": "file", "scope": "edit"})
    arm("B4_rebind_after_release", r.get("bound") == 1, "")
    b.kill()


def a2_release():
    a = Sess("A")
    r = a.call("file_release", {"project_dir": ".", "holder": "agent-A",
                                "paths": ["src/x.mbt"]})
    a.kill()
    return r


def ttl_arm():
    """TTL 过期 → 他 holder 接管（BndReclaimed）。"""
    a = Sess("TTL")
    a.call("file_bind", {"project_dir": ".", "paths": ["src/ttl.mbt"],
                         "holder": "agent-TTL", "task_id": "T-TTL",
                         "kind": "file", "scope": "edit", "ttl_secs": 1})
    a.kill()
    time.sleep(2)
    b = Sess("TTL2")
    r = b.call("file_bind", {"project_dir": ".", "paths": ["src/ttl.mbt"],
                             "holder": "agent-NEXT", "task_id": "T-NEXT",
                             "kind": "file", "scope": "edit"})
    b.kill()
    rows = r.get("rows") or []
    verdict = rows[0].get("verdict") if rows else "?"
    return verdict


def ttl_arm_check():
    v = ttl_arm()
    arm("C1_ttl_expired_reclaimed", v == "reclaimed", "verdict=%s" % v)


if __name__ == "__main__":
    main()
    ttl_arm_check()
    fails = [n for n, ok in RESULTS if not ok]
    for n, ok in RESULTS:
        say("RESULT", "%s %s" % ("PASS" if ok else "FAIL", n))
    if fails:
        die("%d/%d 臂失败" % (len(fails), len(RESULTS)))
    say("ALL", "%d/%d 臂全绿" % (len(RESULTS), len(RESULTS)))
    sys.exit(0)
