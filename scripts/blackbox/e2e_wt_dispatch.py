#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""F094 Phase 3 验收黑盒：worktree 派发编排（wt_dispatch / wt_collect）。

真 git 仓库 + 真 server 进程：
  1. 双执行器 dispatch → 两个沙箱路径/分支互不相同
  2. 同 task+executor 重复 dispatch → reused=true（幂等）
  3. 执行器在沙箱内 commit → wt_collect → ff-merge 回主线 + 沙箱回收
  4. 脏沙箱 collect → blocked（收的是提交，不是工作区）
  5. 主线也前进 → ff-only 不可行 → blocked 点名
  6. force=true → --no-ff 强并成功
红线：FIST_DB_PATH 隔离库；git 全部在临时仓库内。
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
BOX = os.path.join(ROOT, "temp", "wt-dispatch-box")
# 每次运行唯一库名：上次运行残留的 server 进程会锁着旧库，固定名会撞 WinError 32
DB = os.path.join(ROOT, "temp",
                  "wt-dispatch-%d.db" % int(time.time() * 1000))

META = {
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": {},
    "io.modelcontextprotocol/clientInfo": {"name": "wt-dispatch-guard", "version": "1"},
}

RESULTS = []


def say(k, v):
    print("%s: %s" % (k, v))


def arm(name, ok, detail=""):
    RESULTS.append((name, bool(ok)))
    say("ARM %s" % ("PASS" if ok else "FAIL"), "%s %s" % (name, detail))


def die(msg):
    print("DIE " + msg)
    sys.exit(2)


def git(cwd, *args):
    p = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True)
    return p.returncode, p.stdout.strip(), p.stderr.strip()


class Sess:
    def __init__(self, tag):
        if not os.path.isfile(CLI):
            die("产物不存在 %s" % CLI)
        env = dict(os.environ)
        env["FIST_DB_PATH"] = DB
        self.errf = open(os.path.join(ROOT, "temp", "wt-dispatch-%s.err" % tag),
                         "w", encoding="utf-8")
        self.p = subprocess.Popen(
            ["node", CLI, "serve"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=self.errf, cwd=BOX, env=env, bufsize=0)
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

    def call(self, name, args, timeout=60):
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


def setup_repo():
    if os.path.isdir(BOX):
        shutil.rmtree(BOX, ignore_errors=True)
    os.makedirs(os.path.join(BOX, "src"), exist_ok=True)
    with open(os.path.join(BOX, "src", "base.mbt"), "w", encoding="utf-8") as f:
        f.write("// base\n")
    git(BOX, "init", "-b", "main")
    git(BOX, "config", "user.email", "e2e@fist.local")
    git(BOX, "config", "user.name", "e2e")
    git(BOX, "add", "-A")
    git(BOX, "commit", "-m", "base")
    # gitignore 沙箱目录（与 wt_create 的账目录约定一致）
    with open(os.path.join(BOX, ".gitignore"), "w", encoding="utf-8") as f:
        f.write("wt/\n.fist-mbt/\n")
    git(BOX, "add", "-A")
    git(BOX, "commit", "-m", "gitignore")
    if os.path.exists(DB):
        os.remove(DB)


def commit_in(path, fname, msg):
    with open(os.path.join(path, fname), "w", encoding="utf-8") as f:
        f.write("// " + msg + "\n")
    git(path, "add", "-A")
    return git(path, "commit", "-m", msg)


def main():
    setup_repo()
    s = Sess("main")

    # 1. 双执行器 dispatch → 两个沙箱
    r = s.call("wt_dispatch", {"project_dir": ".", "task": "T1", "executor": "exe-A"})
    arm("D1_dispatch_a", r.get("ok") is True and r.get("path") == "wt/T1-exe-A",
        "path=%s" % r.get("path"))
    r = s.call("wt_dispatch", {"project_dir": ".", "task": "T1", "executor": "exe-B"})
    arm("D2_dispatch_b", r.get("ok") is True and r.get("path") == "wt/T1-exe-B",
        "path=%s" % r.get("path"))

    # 2. 幂等：同 task+executor 重复 dispatch → reused=true
    r = s.call("wt_dispatch", {"project_dir": ".", "task": "T1", "executor": "exe-A"})
    arm("D3_dispatch_idempotent", r.get("reused") is True, "reused=%s" % r.get("reused"))

    # 3. exe-A 沙箱先弄脏（未提交）→ collect ⇒ blocked；提交后 ⇒ ff 收口 + 回收
    with open(os.path.join(BOX, "wt", "T1-exe-A", "src", "dirty.mbt"), "w",
              encoding="utf-8") as f:
        f.write("// dirty\n")
    r = s.call("wt_collect", {"project_dir": ".", "task": "T1", "executor": "exe-A"})
    arm("D4_collect_dirty_blocked", r.get("_error", "") != "" and "未提交" in r.get("_error", ""),
        str(r)[:160])
    commit_in(os.path.join(BOX, "wt", "T1-exe-A"), "src/feat_a.mbt", "feat A")
    r = s.call("wt_collect", {"project_dir": ".", "task": "T1", "executor": "exe-A"})
    arm("D5_collect_ff", r.get("merged_mode") == "ff" and r.get("collect_blocked") is False,
        str(r)[:160])
    main_has = os.path.isfile(os.path.join(BOX, "src", "feat_a.mbt"))
    sandbox_gone = not os.path.isdir(os.path.join(BOX, "wt", "T1-exe-A"))
    arm("D6_merged_and_reclaimed", main_has and sandbox_gone,
        "main_has=%s sandbox_gone=%s" % (main_has, sandbox_gone))

    # 4. ff 冲突：exe-B 提交后主线也前进 → ff-only blocked → force 强并
    commit_in(os.path.join(BOX, "wt", "T1-exe-B"), "src/feat_b.mbt", "feat B")
    commit_in(BOX, "src/main_advance.mbt", "main advance")
    r = s.call("wt_collect", {"project_dir": ".", "task": "T1", "executor": "exe-B"})
    arm("D7_ff_conflict_blocked", r.get("_error", "") != "" and "ff-only" in r.get("_error", ""),
        str(r)[:160])
    r = s.call("wt_collect", {"project_dir": ".", "task": "T1", "executor": "exe-B",
                              "force": True})
    arm("D8_force_no_ff", r.get("merged_mode") == "no-ff", str(r)[:160])
    b_has = os.path.isfile(os.path.join(BOX, "src", "feat_b.mbt"))
    arm("D9_b_merged_to_main", b_has, "feat_b on main=%s" % b_has)

    s.kill()


if __name__ == "__main__":
    main()
    fails = [n for n, ok in RESULTS if not ok]
    for n, ok in RESULTS:
        say("RESULT", "%s %s" % ("PASS" if ok else "FAIL", n))
    if fails:
        die("%d/%d 臂失败" % (len(fails), len(RESULTS)))
    say("ALL", "%d/%d 臂全绿" % (len(RESULTS), len(RESULTS)))
    sys.exit(0)
