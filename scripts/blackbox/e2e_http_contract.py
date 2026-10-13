#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""fist-mbt HTTP 契约自证守卫（docs/openapi/fist.yaml 的活体判据）

**为什么需要它**：契约 v1 只登记被真实服务的端点（x-implementation: served|pre-existing）。
「服务着」这件事目前只在我的开发机上验过一次——实现漂移（改桥、剥壳规则动、_meta 补齐失效、
工具面改名）会让 yaml 静默变成假承诺，而 CI 里没人再跑过。这是本仓反复踩的形状：
文档即实现，反过来也成立——**契约不跑就等于没有**。

六臂（缺一即 FAIL，结论行带基数门，格子集合与声明逐字不等即判「尺子坏了」exit 2）：
  A 起桥 + GET /health                  → 桥与 server 子进程真起来（前置不满足即 REFUSED，不假绿）
  B GET /tools                          → 剥壳生效：返 {tools:[…]}，且每项带 inputSchema
                                           （自描述驱动是契约的立身之本，丢了它 yaml 的承诺就是空话）
  C POST /tools/mode_list/call          → 只读零副作用工具真跑出 ok=true + data 有内容
                                           （_meta 由桥补齐：缺了服务端直接 -32602，这条同时钉住那格）
  D body 非对象（[1,2]）                → 400 显式拒绝，不静默当空 arguments
  E 未知工具名                          → 502（走 error 通道）**且桥不崩**——下一臂还要用同一个桥
  F 老 POST /mcp tools/list             → 163 量级正常回执 ⇒ 加新口没有破坏既有通用口（零回归）

用法（与 ci.yml「HTTP contract self-proof」一步同形）：
  moon build --target js cmd/cli
  python scripts/patch_esm_main.py _build/js/debug/build/cmd/cli/cli.js
  python scripts/blackbox/e2e_http_contract.py
退出码：0=六臂全过 / 1=有臂红 / 2=前置不满足或尺子坏了（缺产物、端口起不来、臂数对不上）。
"""
import json
import os
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

# BUG-138（BUG-58 同族）：守卫的红必须是判据红——中文结论里的 ⇒ 在 cp936 控制台会先崩掉 print，
# 把 traceback 冒充成「缺陷在场」那一档。CI 在 Linux UTF-8 下是无损 no-op。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CLI = os.path.join(ROOT, "_build", "js", "debug", "build", "cmd", "cli", "cli.js")
BRIDGE = os.path.join(ROOT, "scripts", "fist-mbt-http.py")
# BUG-122/90：起 serve 的面必须把库改道到 temp，绝不写仓库根自举台账
DB = os.path.join(ROOT, "temp", "http-contract-e2e.db")
PORT = 0  # 0 = 让 OS 发一个空闲端口（写死端口会在 CI 与本机并发时自撞）
ARMS = ["A_bridge_health", "B_tools_unwrapped", "C_tool_call_live",
        "D_body_not_object_400", "E_unknown_tool_no_crash", "F_legacy_mcp_zero_regression"]
RESULTS = []


def say(k, v):
    print("%-30s %s" % (k, v), flush=True)


def arm(name, ok, detail):
    RESULTS.append((name, bool(ok)))
    say("  " + name, "%s | %s" % ("PASS" if ok else "FAIL", detail))


def refuse(msg, hint=""):
    print("HTTP-CONTRACT E2E REFUSED: %s" % msg, flush=True)
    if hint:
        print("  出路：%s" % hint, flush=True)
    sys.exit(2)


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    p = s.getsockname()[1]
    s.close()
    return p


def req(method, path, body=None, timeout=25):
    """返回 (status, parsed_or_None, raw_text)。非 2xx 不抛——判据要看状态码。"""
    url = "http://127.0.0.1:%d%s" % (PORT, path)
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, method=method,
                              headers={"Content-Type": "application/json"} if data else {})
    try:
        with urllib.request.urlopen(r, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", "replace")
            return resp.status, _try_json(raw), raw
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        return e.code, _try_json(raw), raw
    except Exception as e:
        return 0, None, "%s: %s" % (type(e).__name__, e)


def _try_json(s):
    try:
        return json.loads(s)
    except Exception:
        return None


def main() -> int:
    global PORT
    if not os.path.isfile(CLI):
        refuse("找不到 MCP 入口产物 %s" % os.path.relpath(CLI, ROOT),
               "先 `moon build --target js cmd/cli` + `python scripts/patch_esm_main.py`")
    if not os.path.isfile(BRIDGE):
        refuse("找不到桥 %s（契约实现面被移走？）" % os.path.relpath(BRIDGE, ROOT))
    os.makedirs(os.path.join(ROOT, "temp"), exist_ok=True)
    for suffix in ("", "-shm", "-wal"):
        p = DB + suffix
        if os.path.exists(p):
            os.remove(p)
    PORT = free_port()
    env = dict(os.environ)
    env["FIST_DB_PATH"] = DB          # I1 形状之一：显式把改道交给子进程（桥再 inherits 给 serve）
    log = open(os.path.join(ROOT, "temp", "http-contract-bridge.log"), "w")
    proc = subprocess.Popen([sys.executable, BRIDGE, str(PORT)], cwd=ROOT,
                            env=env, stdout=log, stderr=subprocess.STDOUT)
    try:
        up = False
        for _ in range(80):
            time.sleep(0.5)
            if proc.poll() is not None:
                break
            st, _, _ = req("GET", "/health", timeout=3)
            if st == 200:
                up = True
                break
        # A
        arm("A_bridge_health", up, "端口 %d 起来 / 桥退出码=%s" % (PORT, proc.poll()))
        if not up:
            tail = open(os.path.join(ROOT, "temp", "http-contract-bridge.log")).read()[-500:]
            refuse("桥起不来，后续臂无从判起：%s" % tail)
            return 2
        # B：剥壳 + 自描述
        st, j, raw = req("GET", "/tools")
        tools = (j or {}).get("tools") if isinstance(j, dict) else None
        b_ok = (st == 200 and isinstance(tools, list) and len(tools) > 100
                and "jsonrpc" not in (j or {})          # 仍是信封=剥壳没生效
                and all("inputSchema" in t for t in tools[:20]))
        arm("B_tools_unwrapped", b_ok,
            "status=%d n=%s 有inputSchema=%s" % (st, len(tools) if isinstance(tools, list) else "-",
                                                 "jsonrpc" not in (j or {})))
        # C：真调一个只读工具（mode_list 纯计算零副作用）
        st, j, raw = req("POST", "/tools/mode_list/call", {})
        modes = [m.get("mode") for m in (j or {}).get("data") or [] if isinstance(m, dict)]
        c_ok = (st == 200 and (j or {}).get("ok") is True and len(modes) >= 5
                and isinstance((j or {}).get("result"), dict))   # result 必须原样保留
        arm("C_tool_call_live", c_ok, "status=%d ok=%s 模式数=%d result保留=%s" % (
            st, (j or {}).get("ok"), len(modes), isinstance((j or {}).get("result"), dict)))
        # D：body 非对象必须 400（不许静默当空 arguments）
        st, j, raw = req("POST", "/tools/mode_list/call", [1, 2])
        arm("D_body_not_object_400", st == 400, "status=%d body=%s" % (st, str(raw)[:60]))
        # E：未知工具走 502 且桥不崩（下一臂仍能用同一条桥）
        st, j, raw = req("POST", "/tools/no_such_tool_zz/call", {})
        alive = proc.poll() is None
        arm("E_unknown_tool_no_crash", st == 502 and alive, "status=%d 桥存活=%s" % (st, alive))
        # F：老通用 /mcp 口零回归
        st, j, raw = req("POST", "/mcp", {"jsonrpc": "2.0", "id": 1,
                                          "method": "tools/list", "params": {}})
        n_legacy = len(((j or {}).get("result") or {}).get("tools") or [])
        arm("F_legacy_mcp_zero_regression", st == 200 and n_legacy > 100 and "jsonrpc" in (j or {}),
            "status=%d tools=%d 信封保留=%s" % (st, n_legacy, "jsonrpc" in (j or {})))
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=8)
        except Exception:
            proc.kill()
        log.close()

    got = [n for n, _ in RESULTS]
    if got != ARMS:
        print("E2E HTTP-CONTRACT REFUSED: 臂集合与声明不一致（尺子坏了）\n  实际=%s\n  声明=%s" % (got, ARMS))
        return 2
    bad = [n for n, ok in RESULTS if not ok]
    print("E2E-HTTP-CONTRACT %s: %d/%d 臂通过%s" % (
        "PASS" if not bad else "FAIL", len(RESULTS) - len(bad), len(RESULTS),
        "" if not bad else " 红在 " + ", ".join(bad)))
    print("  台账：temp/%s（已改道，仓库根 fist-mbt.db 未写入）" % os.path.basename(DB))
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())
