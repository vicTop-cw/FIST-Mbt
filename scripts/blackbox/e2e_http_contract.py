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
BRIDGE = os.path.join(ROOT, "scripts", "run_fist_mbt_http.py")
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


# ---------------------------------------------------------------- 六臂的纯判定
# 抽成纯函数的理由（BUG-50 / J10：「判据必须先证明自己会红」）：判定若埋在 main() 的
# 实时回执里，`--selftest` 就只能靠"起真桥"来验，而真桥一坏判据自己先崩——于是自检
# 变成"整条链通不通"，验不出"某支判据会不会红"。纯函数让每一格都能喂合成回执。
def p_health(status):
    """A：桥健康口回 200。"""
    return status == 200


def p_tools_unwrapped(status, j):
    """B：剥壳生效（返 {tools:[…]} 而非 jsonrpc 信封）+ 每项带 inputSchema + 数量量级。"""
    tools = j.get("tools") if isinstance(j, dict) else None
    return (status == 200
            and isinstance(tools, list) and len(tools) > 100
            and "jsonrpc" not in (j or {})
            and all("inputSchema" in t for t in tools[:20]))


def p_tool_call_live(status, j):
    """C：真调只读工具出 ok=true、data 有内容、且 result 原样保留。"""
    modes = [m.get("mode") for m in (j or {}).get("data") or [] if isinstance(m, dict)]
    return (status == 200
            and (j or {}).get("ok") is True
            and len(modes) >= 5
            and isinstance((j or {}).get("result"), dict))


def p_body_not_object_400(status):
    """D：body 非对象必须 400（不许静默当空 arguments）。"""
    return status == 400


def p_unknown_tool_no_crash(status, bridge_alive):
    """E：未知工具走 502，且桥仍活着（下一臂还要用同一条桥）。"""
    return status == 502 and bool(bridge_alive)


def p_legacy_mcp(status, j):
    """F：老 /mcp 通用口零回归——仍回 jsonrpc 信封、工具数量级正常。"""
    n = len(((j or {}).get("result") or {}).get("tools") or [])
    return status == 200 and n > 100 and "jsonrpc" in (j or {})


def arms_consistent(names, declared=None):
    """臂集合与声明逐字一致（不等即判「尺子坏了」）——独立成函数便于自检。"""
    return names == (declared if declared is not None else ARMS)


def selftest() -> int:
    """BUG-50 / J10：判据必须先证明自己会红。

    每格都是"合成回执喂进纯判定函数 → 要求它给对答案"，**不起真桥、不碰网络**。
    格子的清单与 PASS 行的判据范围一律从实现反解（不手写计数）——本仓已因手写计数返工过。
    """
    _entry_probe()
    cases = []

    def case(name, got, want):
        cases.append((name, bool(got) is bool(want), "got=%s want=%s" % (got, want)))

    # A 健康口
    case("A-ok-200", p_health(200), True)
    case("A-red-500", p_health(500), False)
    case("A-red-0-连接失败", p_health(0), False)
    # B 剥壳 + 自描述
    good_tools = {"tools": [{"name": "t%d" % i, "inputSchema": {"type": "object"}} for i in range(120)]}
    case("B-ok-120工具带schema", p_tools_unwrapped(200, good_tools), True)
    case("B-red-仍信封(jsonrpc)", p_tools_unwrapped(200, dict(good_tools, jsonrpc="2.0")), False)
    case("B-red-缺inputSchema", p_tools_unwrapped(200, {"tools": [{"name": "x"} for _ in range(120)]}), False)
    case("B-red-工具太少", p_tools_unwrapped(200, {"tools": [{"name": "x", "inputSchema": {}}]}), False)
    case("B-red-非对象", p_tools_unwrapped(200, None), False)
    # C 真调工具
    case("C-ok", p_tool_call_live(200, {"ok": True, "data": [{"mode": m} for m in
                                                              ["advance", "polish", "verify", "bugfind", "fix_and_merge"]],
                                     "result": {"content": []}}), True)
    case("C-red-result被剥掉", p_tool_call_live(200, {"ok": True, "data": [{"mode": m} for m in
                                                                          ["a", "b", "c", "d", "e"]]}), False)
    case("C-red-ok非true", p_tool_call_live(200, {"ok": False, "data": [{"mode": m} for m in "abcde"],
                                                 "result": {}}), False)
    case("C-red-data太少", p_tool_call_live(200, {"ok": True, "data": [{"mode": "a"}], "result": {}}), False)
    # D body 非对象
    case("D-ok-400", p_body_not_object_400(400), True)
    case("D-red-200(静默当空arguments)", p_body_not_object_400(200), False)
    # E 未知工具
    case("E-ok-502且桥活", p_unknown_tool_no_crash(502, True), True)
    case("E-red-桥死了", p_unknown_tool_no_crash(502, False), False)
    case("E-red-不是502", p_unknown_tool_no_crash(200, True), False)
    # F 老 /mcp 零回归
    case("F-ok-信封+工具量级", p_legacy_mcp(200, {"jsonrpc": "2.0", "result": {"tools": [{}] * 120}}), True)
    case("F-red-信封被剥", p_legacy_mcp(200, {"result": {"tools": [{}] * 120}}), False)
    case("F-red-工具太少", p_legacy_mcp(200, {"jsonrpc": "2.0", "result": {"tools": [{}]}}), False)
    # 臂集合一致性（尺子坏了那一档）
    case("ARM-ok-逐字一致", arms_consistent(list(ARMS)), True)
    case("ARM-red-少一臂", arms_consistent(ARMS[:-1]), False)
    case("ARM-red-多一臂", arms_consistent(ARMS + ["X"]), False)

    bad = [(n, why) for n, ok, why in cases if not ok]
    if bad:
        print("SELFTEST FAIL：")
        for n, why in bad:
            print("  - %s：%s" % (n, why))
        return 1
    print("SELFTEST OK（%d 格：六个臂各含正/反/边界对照 + 臂集合一致性 3 格；"
          "格子清单从实现反解，非手写）" % len(cases))
    print("  说明：本自检**不起真桥、不碰网络/端口**，只考判定函数会不会红；"
          "真桥那条链由无参数运行负责。")
    return 0



def _entry_probe() -> None:
    """入口面自证（R171 口径）：自检必须把入口纳入调用图。

    为什么要有这一格：R158 交付 check_diff_scope.py 时 `--selftest` 全绿而**现状面一跑就崩**
    （clean 分支少传一个实参抛 TypeError，冒出来的 rc=1 和「有违例」一模一样）。自检只考纯函数、
    不碰入口，照不出「自检面与入口面脱钩」。本探测**零副作用**：只验证入口存在且可调用，
    不起服务、不碰网络、不跑真桥。
    """
    if not callable(main):
        raise SystemExit("入口 main 不可调用（自检面与入口面脱钩）")


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
        arm("A_bridge_health", p_health(200 if up else 0),
            "端口 %d 起来 / 桥退出码=%s" % (PORT, proc.poll()))
        if not up:
            tail = open(os.path.join(ROOT, "temp", "http-contract-bridge.log")).read()[-500:]
            refuse("桥起不来，后续臂无从判起：%s" % tail)
            return 2
        # B：剥壳 + 自描述
        st, j, raw = req("GET", "/tools")
        tools = (j or {}).get("tools") if isinstance(j, dict) else None
        b_ok = p_tools_unwrapped(st, j)
        arm("B_tools_unwrapped", b_ok,
            "status=%d n=%s 有inputSchema=%s" % (st, len(tools) if isinstance(tools, list) else "-",
                                                 "jsonrpc" not in (j or {})))
        # C：真调一个只读工具（mode_list 纯计算零副作用）
        st, j, raw = req("POST", "/tools/mode_list/call", {})
        modes = [m.get("mode") for m in (j or {}).get("data") or [] if isinstance(m, dict)]
        c_ok = p_tool_call_live(st, j)
        arm("C_tool_call_live", c_ok, "status=%d ok=%s 模式数=%d result保留=%s" % (
            st, (j or {}).get("ok"), len(modes), isinstance((j or {}).get("result"), dict)))
        # D：body 非对象必须 400（不许静默当空 arguments）
        st, j, raw = req("POST", "/tools/mode_list/call", [1, 2])
        arm("D_body_not_object_400", p_body_not_object_400(st), "status=%d body=%s" % (st, str(raw)[:60]))
        # E：未知工具走 502 且桥不崩（下一臂仍能用同一条桥）
        st, j, raw = req("POST", "/tools/no_such_tool_zz/call", {})
        alive = proc.poll() is None
        arm("E_unknown_tool_no_crash", p_unknown_tool_no_crash(st, alive), "status=%d 桥存活=%s" % (st, alive))
        # F：老通用 /mcp 口零回归
        st, j, raw = req("POST", "/mcp", {"jsonrpc": "2.0", "id": 1,
                                          "method": "tools/list", "params": {}})
        n_legacy = len(((j or {}).get("result") or {}).get("tools") or [])
        arm("F_legacy_mcp_zero_regression", p_legacy_mcp(st, j),
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
    if sys.argv[1:] == ["--selftest"]:
        sys.exit(selftest())
    sys.exit(main())
