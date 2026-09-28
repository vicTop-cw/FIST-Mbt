#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/store_isolation_probe.py — 存储隔离调用面探针（BUG-90 的活判据）。

它证明的是**一件事**：一个 FIST server 进程的任务行到底落在哪个 sqlite 文件里，
只能由**进程环境变量**决定；`store_open(scratch=true)` 单独不构成隔离。

为什么必须有这条（历史上怎么骗过人的）：
  2026-09-28 用安装版跑 129 工具巡检时，起手就调了
  `store_open(namespace=goalverify0928, scratch=true)`，返回
  `{"opened":true,"data_dir":"temp","scratch":true}` —— 于是按自述认定"库落 temp/，
  不污染仓库根"。收口后只读复核：`temp/goalverify0928.db` 是**空库**（0 任务 / 0 调用行），
  而仓库根 `fist-mbt.db` 里多了 `ns='goalverify0928'` 的任务行与 8 条 call_log。
  根因：工具闭包用的是模块级 `engine`（`SqliteStore::new()` 打开的库），
  `MultiStore::get()` 全仓零调用 ⇒ ns 只是登记表，不是路由。⇒ BUG-90。
  修法是运维侧出口 `FIST_DB_PATH`（与 `FIST_RUN_CHECK_ALLOW` 同族：调用方不能自我扩权），
  本探针就是它在**调用面**的成对判据。

两格（同一个 cwd 只差一个环境变量，两格都不碰仓库根 `fist-mbt.db`——那是并发工作区的共享面，
任何一格依赖它都会被别人写脏，判据就测不出自己的结论）：
  C1 env 生效格：cwd=scratch/box + FIST_DB_PATH=scratch/probe.db
                 ⇒ 行必须落 probe.db，**且 box 里不得长出默认 fist-mbt.db**
                 （长出来就说明有两个引擎各自开库，隔离只覆盖了一半）。
  C2 默认回落格：同一 box、无 env ⇒ 行必须落 box/fist-mbt.db。
                 这一格是 C1 的成对对照：没有它，"C1 绿"可能只是探针根本看不见样本。

反幻影（判据自己坏了不能报绿）：
  · 每格起跑先断言 server 进程真起来了、tools/list 拿到 >100 个工具；
  · 每格发布后必须"探针看得见样本"：目标库存在且 tasks 行数增量 ≥1，
    否则该格判 RED（open 失败会静默回退内存版 —— 那种"绿"正是 BUG-90 藏身的形状）；
  · 结论行最后打印且带 `PROBE:` 前缀，正文计数全部从盘上反解，不手写。

用法：
    python scripts/store_isolation_probe.py                 # 两格（C1/C2）
    python scripts/store_isolation_probe.py --selftest        # 再加一格合成违例（期望 RED，抓到才算绿）
    python scripts/store_isolation_probe.py --json            # 追加机器可读 JSON
环境变量：
    FIST_PROBE_JS  指定要验的 server 产物（承重对照要用修复前那份）
    NODE           指定 node 可执行文件（默认 `node`）
退出码：0 = 两格全部符合预期；1 = 任一格违例；2 = 探针自身不可用（找不到 server / node）。
"""
import hashlib
import io
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import time
import uuid

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUN_ID = time.strftime("%Y%m%d%H%M%S", time.gmtime()) + "-" + uuid.uuid4().hex[:6]
SCRATCH = os.path.join(ROOT, "temp", "store-isolation-" + RUN_ID)
LOG = os.path.join(ROOT, "temp", "store_isolation_probe_%s.log" % RUN_ID)
# 证据文件先占住再干活：脚本崩在半路时，同名旧日志不能冒充这次的结果
io.open(LOG, "w", encoding="utf-8").write("started=%s run_id=%s\n" % (
    time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), RUN_ID))

SERVER_JS_CANDIDATES = [
    os.path.expandvars(r"%LOCALAPPDATA%\FIST-Mbt\fist-mbt.js"),
    os.path.join(ROOT, "_build", "js", "debug", "build", "cmd", "cli", "cli.js"),
]
META = {
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": {},
    "io.modelcontextprotocol/clientInfo": {"name": "store-isolation-probe", "version": "1"},
}


def say(msg):
    line = msg
    with io.open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")
    print(line)
    sys.stdout.flush()


def sha8(path):
    h = hashlib.sha256()
    with io.open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()[:8]


def count_rows(db_path):
    """只读取 (tasks, call_log) 行数；库不存在返回 None（不是 0——0 意味着空库，语义不同）。"""
    if not os.path.isfile(db_path):
        return None
    c = sqlite3.connect("file:%s?mode=ro" % db_path.replace("\\", "/"), uri=True)
    try:
        return (c.execute("select count(*) from tasks").fetchone()[0],
                c.execute("select count(*) from call_log").fetchone()[0])
    finally:
        c.close()


class Serve:
    """node <js> serve —— 协议行只认 { 开头（serve 会先打横幅）。

    stderr 收进文件而不是 DEVNULL：'server closed stdout' 这种失败，
    真正的原因（模块解析失败 / require is not defined / 缺 node 版本）只在 stderr 里。
    吞掉它 = 把可诊断的拒绝写成不可诊断的红。
    """

    def __init__(self, js, cwd, env, errlog):
        self.errlog = errlog
        self.p = subprocess.Popen(
            [os.environ.get("NODE", "node"), js, "serve"],
            cwd=cwd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=io.open(errlog, "wb"), bufsize=0, env=env)
        self.mid = 0

    def stderr_tail(self, n=400):
        try:
            return io.open(self.errlog, "rb").read()[-n:].decode("utf-8", "replace")
        except Exception:
            return ""

    def _send(self, obj):
        self.p.stdin.write((json.dumps(obj) + "\n").encode("utf-8"))
        self.p.stdin.flush()

    def call(self, tool, args, timeout=45):
        self.mid += 1
        want = self.mid
        p = {"_meta": META, "name": tool, "arguments": args}
        self._send({"jsonrpc": "2.0", "id": want, "method": "tools/call", "params": p})
        t0 = time.time()
        while time.time() - t0 < timeout:
            line = self.p.stdout.readline()
            if not line:
                raise RuntimeError("server closed stdout")
            s = line.decode("utf-8", "replace").strip()
            if not s.startswith("{"):
                continue
            try:
                m = json.loads(s)
            except Exception:
                continue
            if m.get("id") == want:
                return m
        raise RuntimeError("timeout waiting id=%s (tool=%s)" % (want, tool))

    def tools_count(self, timeout=60):
        self.mid += 1
        want = self.mid
        self._send({"jsonrpc": "2.0", "id": want, "method": "tools/list",
                    "params": {"_meta": META}})
        t0 = time.time()
        while time.time() - t0 < timeout:
            line = self.p.stdout.readline()
            if not line:
                raise RuntimeError("server closed stdout")
            s = line.decode("utf-8", "replace").strip()
            if not s.startswith("{"):
                continue
            try:
                m = json.loads(s)
            except Exception:
                continue
            if m.get("id") == want:
                if "error" in m:
                    raise RuntimeError("tools/list error: %s" % m["error"])
                return len(m.get("result", {}).get("tools", []) or [])
        raise RuntimeError("timeout tools/list")

    def close(self):
        try:
            self.p.stdin.close()
        except Exception:
            pass
        try:
            self.p.wait(timeout=8)
        except Exception:
            self.p.kill()


def publish_and_check(js, ns, cwd, env, expect_db, tag):
    """起 server → 发布一条根任务 → 回读行数。返回 (verdict, detail dict)。"""
    detail = {"ns": ns, "cwd": os.path.relpath(cwd, ROOT).replace("\\", "/"),
              "expect_db": os.path.relpath(expect_db, ROOT).replace("\\", "/")}
    errlog = os.path.join(SCRATCH, "serve-%s.stderr.log" % tag)
    srv = Serve(js, cwd, env, errlog)
    try:
        try:
            ntools = srv.tools_count()
        except RuntimeError as e:
            # 进程起不来 ≠ 隔离坏了 ≠ 隔离好了：判 UNUSABLE 并附 stderr，交人读
            return "RED", detail | {"why": "server 无响应（%s）；stderr 尾：%s" % (e, srv.stderr_tail())}
        detail["tools_listed"] = ntools
        if ntools <= 100:
            return "RED", detail | {"why": "tools/list 只回 %d 个工具 ⇒ 探针看不见样本" % ntools}
        r = srv.call("publish", {
            "project_dir": ".", "namespace": ns,
            "description": "隔离探针 %s —— 只为一行任务，不落任何交付物" % ns,
            "created_by": "human_steward",
            "now": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        })
        txt = json.dumps(r, ensure_ascii=False)
        detail["publish_response"] = txt[:300]
        if "error" in r:
            return "RED", detail | {"why": "publish 被拒（探针无效）：%s" % txt[:200]}
        time.sleep(0.4)  # WAL 落盘
    finally:
        srv.close()
    if not os.path.isfile(expect_db):
        return "RED", detail | {"why": "期望库不存在 ⇒ server 很可能静默回退内存版（BUG-90 的藏身形状）: %s" % detail["expect_db"]}
    got = count_rows(expect_db)
    detail["expect_rows"] = got
    if got is None or got[0] < 1:
        return "RED", detail | {"why": "期望库 tasks 行数=%s ⇒ 行没写进被指定的库" % (got[0] if got else "n/a")}
    return "GREEN", detail


def main():
    # FIST_PROBE_JS：指定要验的产物。承重证明要用它跑"修复前那份 js"——
    # 只在修好的产物上报绿不等于锁承重，必须让旧产物在这一格发红。
    forced = os.environ.get("FIST_PROBE_JS")
    if forced:
        SERVER_JS_CANDIDATES.insert(0, forced)
    js = next((p for p in SERVER_JS_CANDIDATES if os.path.isfile(p)), None)
    if not js:
        say("PROBE: UNUSABLE —— 找不到 server 产物（候选：%s）。先 moon build --target js 或跑安装器。"
            % ", ".join(SERVER_JS_CANDIDATES))
        return 2
    os.makedirs(SCRATCH, exist_ok=True)
    say("server  = %s (sha256:%s)" % (js, sha8(js)))
    say("scratch = %s" % os.path.relpath(SCRATCH, ROOT).replace("\\", "/"))

    results = {}
    # —— 同一个 cwd 两格只差一个环境变量：这样"设了/没设"必须是两种可观测形态 ——
    #    两格都不碰仓库根 fist-mbt.db（并发工作区里根库是共享面，任何一格依赖它都会被别人写脏）。
    box = os.path.join(SCRATCH, "box")          # server 进程的 cwd
    probe_db = os.path.join(SCRATCH, "probe.db")  # C1 指定的库（在 cwd 之外）
    default_db = os.path.join(box, "fist-mbt.db")  # 未设 env 时的默认落点
    os.makedirs(box, exist_ok=True)

    # C1 env 生效格：FIST_DB_PATH 指向 box 外的 probe.db ⇒ 行进 probe.db，且 box 里不得长出默认库
    env1 = dict(os.environ)
    env1["FIST_DB_PATH"] = probe_db
    ns1 = "iso-c1-" + RUN_ID[-6:]
    v1, d1 = publish_and_check(js, ns1, box, env1, probe_db, "c1")
    d1["default_db_created_in_cwd"] = os.path.isfile(default_db)
    if v1 == "GREEN" and d1["default_db_created_in_cwd"]:
        v1 = "RED"
        d1["why"] = ("FIST_DB_PATH=%s 生效了，但 cwd 仍长出默认 fist-mbt.db ⇒ "
                     "有两个引擎各自开了库（隔离只覆盖了一半）"
                     % os.path.relpath(probe_db, ROOT).replace("\\", "/"))
    results["C1_env_routing"] = (v1, d1)

    # C2 默认回落格（成对对照）：同一 cwd、无 env ⇒ 行必须落 box/fist-mbt.db
    env2 = {k: v for k, v in os.environ.items() if k != "FIST_DB_PATH"}
    ns2 = "iso-c2-" + RUN_ID[-6:]
    v2, d2 = publish_and_check(js, ns2, box, env2, default_db, "c2")
    if v2 == "GREEN":
        d2["c1_rows_isolated"] = count_rows(probe_db)
    results["C2_default_under_cwd"] = (v2, d2)

    # —— ST1 合成违例（判据必须能发红，否则"C1 绿"没有信息量）——
    #    把 FIST_DB_PATH 指到一个父目录不存在的库：open 失败 ⇒ 引擎静默回退内存版
    #    ⇒ C1 这类形状必须被抓成 RED。这一格期望值就是 RED，抓到才算探针看得见样本。
    if "--selftest" in sys.argv:
        bad_db = os.path.join(SCRATCH, "no-such-dir", "probe.db")
        envs = dict(os.environ)
        envs["FIST_DB_PATH"] = bad_db
        vst, dst = publish_and_check(js, "iso-st1-" + RUN_ID[-6:], box, envs, bad_db, "st1")
        verdict = "GREEN" if vst == "RED" else "RED"
        dst["expected"] = "RED（合成违例：库打不开 ⇒ 必须报『期望库不存在』而不是绿）"
        dst["got"] = vst
        if verdict == "RED":
            dst["why"] = "合成违例没有被抓到 ⇒ 探针恒绿，结论不可用"
        results["ST1_synthetic_violation"] = (verdict, dst)

    for k, (v, d) in results.items():
        say("%-22s %s  %s" % (k, v, json.dumps(d, ensure_ascii=False)[:300]))

    reds = [k for k, (v, _) in results.items() if v != "GREEN"]
    if "--json" in sys.argv:
        jpath = os.path.join(ROOT, "temp", "store_isolation_probe_%s.json" % RUN_ID)
        io.open(jpath, "w", encoding="utf-8").write(json.dumps(
            {"started": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
             "server_js": js, "server_sha8": sha8(js),
             "results": {k: {"verdict": v, "detail": d} for k, (v, d) in results.items()}},
            ensure_ascii=False, indent=2))
        say("JSON 证据 = %s" % os.path.relpath(jpath, ROOT).replace("\\", "/"))
    # 格数从 results 反解，不手写：加一格（比如 --selftest 的 ST1）而忘改结论行的话，
    # 结论行就会报一个和实际跑过的格数不符的数——那正是本仓 lint 反复打回的"范围自述≠实现"。
    say("PROBE: %s —— %d 格中红 %d 格%s" % (
        "GREEN" if not reds else "RED", len(results), len(reds),
        "" if not reds else "（%s）" % ", ".join(reds)))
    return 0 if not reds else 1


if __name__ == "__main__":
    rc = main()
    try:
        shutil.rmtree(SCRATCH, ignore_errors=True)
    except Exception:
        pass
    sys.exit(rc)
