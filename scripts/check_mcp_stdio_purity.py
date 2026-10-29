#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_mcp_stdio_purity.py —— MCP server 的 **stdout 纯净性**判据（BUG-477）。

## 为什么需要它（R33 实测事故）

我自己在 BUG-476 里给 `run_server()` 加了一行诊断：

    println("[fist-mbt] auth_mode = " + @engine.auth_mode().to_string())

`println` 写 **stdout**，而 MCP stdio 传输把 stdout 当 **JSON-RPC 通道**：

    RuntimeError: malformed JSON-RPC response: '[fist-mbt] auth_mode = off\\n'

**⇒ 整个 MCP server 对任何客户端都不可用**，而同一时刻 `moon test` **1835/1835/0 全绿**。

### 判例-33 的完美实例

| 「服务本体」 | 「服务接入」 |
|---|---|
| 引擎层 API 正确、单测全绿 | **stdio 传输被一行 println 打死** |

`moon test` 走的是引擎层函数调用，**不经过 stdio 传输** ⇒ 它结构上看不见这类缺陷。
**⇒ 必须另立一把尺，直接看「进程的 stdout 里出现了什么」。**

## 判据按「语义」写，不按 `println` 这个字面写

本判据要抓的是 **「往 stdout 写了非 JSON-RPC 的东西」**，而 `println` 只是最常见的一种形态：

| 形态 | 是否污染 stdout | 本判据怎么处理 |
|---|---|---|
| `println(...)` | **是** | L1 静态抓 |
| `print(...)` / `print_char` | **是** | L1 静态抓 |
| `println` 在第三方/库代码里 | **是** | **L2 动态抓**（静态扫不到别的包） |
| `eprintln(...)` | 否（走 stderr） | 放行 |
| 依赖库自己 print | **是** | **L2 动态抓** |

⇒ **静态（L1）与动态（L2/L3）必须都做**：静态快但不完整，动态完整但慢且只覆盖跑到的路径。

## 三层

| 层 | 做什么 | 抓什么 |
|---|---|---|
| **L1 静态** | `src/server/**/*.mbt` 里是否有写 stdout 的调用 | 源码里明写的 print |
| **L2 动态·握手** | 用**生产启动描述**（`.mcp.json` 的 `command` + `args` 原样）spawn，喂一行 `initialize`，断言 **stdout 第一行是合法 JSON** | 启动路径上任何 stdout 写入（含依赖库） |
| **L3 动态·工具调用** | 同一进程发 `tools/call`，断言回执**有 `result.content`**（不是 error） | R33 的直接复刻（`KeyError: 'content'`） |

## ⚠️ 判例-33 的硬要求：必须用生产配置的同一份启动描述

**不得自己拼一条更好走的路**（例如直接 `node cli.js serve`）。
本判据**原样读 `.mcp.json`** 的 `command` + `args`；拿不到配置 ⇒ **rc=2（无法自证）**，不降级猜测。
若调用方显式传 `--allow-fallback`，才允许退回 `node <cli.js> serve`，且**输出里明说降级**。

## rc 契约
- `0` stdout 纯净
- `1` 有污染（逐条点名 file:line 或 stdout 行）
- `2` 判据无法自证（拿不到启动描述 / server 起不来 / 握手无回执）
- `4` 尺子自己坏了（反脱锚：`src/server` 不存在 / 一个 `instrumented_tool` 都解析不到）

用法：
    python scripts/check_mcp_stdio_purity.py
    python scripts/check_mcp_stdio_purity.py --selftest
    python scripts/check_mcp_stdio_purity.py --static-only    # 只跑 L1（快，CI 友好）
"""

from __future__ import annotations

import argparse
import glob
import io
import json
import os
import re
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RC_OK, RC_DIRTY, RC_BROKEN, RC_RULER = 0, 1, 2, 4

# ── L1：写 stdout 的调用形态（**按语义，不按字面**）─────────────────────
# 正向：确实写 stdout
STDOUT_WRITERS = (
    "println(",       # 最常见
    "print(",         # println 的前缀，也会命中 println —— 去重时注意
    "print_char(",
    "output(",        # @stdio 之类的裸写
    "js_console_log(",  # 若有 FFI 别名
)
# 反向：**不**写 stdout（必须从命中里剔除，否则误报）
STDOUT_EXEMPT = (
    "eprintln(",
    "eprint(",
    "eprint_char(",
    "debug_print(",   # core 的 Debug 输出（若走 stderr）
)


def is_comment_line(t: str) -> bool:
    return t.startswith("///") or t.startswith("//")


def code_lines(src: str):
    """产出 (lineno, line) —— 已剥掉行注释与块注释。"""
    in_block = False
    for i, ln in enumerate(src.splitlines(), 1):
        t = ln.strip()
        if in_block:
            if "*/" in t:
                in_block = False
            continue
        if t.startswith("/*"):
            if "*/" not in t:
                in_block = True
            continue
        if is_comment_line(t):
            continue
        yield i, ln


def strip_strings(ln: str) -> str:
    """把字符串字面量内容抹成空 —— 免得 `"...println(..."` 之类的**字符串内容**误命中。"""
    out = []
    i = 0
    n = len(ln)
    in_str = False
    while i < n:
        c = ln[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
                out.append('"')
            i += 1
            continue
        if c == '"':
            in_str = True
            out.append('"')
            i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def l1_scan(root: str):
    """返回 (hits, n_files, n_tools)。hits = [(relpath, line, code)]。"""
    files = sorted(glob.glob(os.path.join(root, "src", "server", "**", "*.mbt"),
                             recursive=True))
    prod = [f for f in files
            if not f.endswith("_test.mbt") and not f.endswith("_wbtest.mbt")]
    hits = []
    n_tools = 0
    for f in prod:
        rel = os.path.relpath(f, root).replace("\\", "/")
        src = io.open(f, encoding="utf-8", errors="replace").read()
        n_tools += src.count("instrumented_tool(")
        for ln_no, ln in code_lines(src):
            code = strip_strings(ln)
            # 先剔除豁免形态
            excerpt = code
            for ex in STDOUT_EXEMPT:
                excerpt = excerpt.replace(ex, "")
            if any(w in excerpt for w in STDOUT_WRITERS):
                hits.append((rel, ln_no, ln.strip()[:110]))
    return hits, len(prod), n_tools


# ── L2/L3：动态（用生产启动描述）────────────────────────────────────────
def load_launch(root: str, server_name: str = "fist-mbt"):
    """从 `.mcp.json` 原样取 command + args（判例-33）。拿不到返回 None。"""
    p = os.path.join(root, ".mcp.json")
    if not os.path.isfile(p):
        return None
    try:
        cfg = json.load(io.open(p, encoding="utf-8"))
    except Exception:  # noqa: BLE001
        return None
    srv = (cfg.get("mcpServers") or {}).get(server_name)
    if not isinstance(srv, dict):
        return None
    cmd = srv.get("command")
    args = srv.get("args") or []
    if not isinstance(cmd, str) or not cmd:
        return None
    return {"command": cmd, "args": [str(a) for a in args], "source": ".mcp.json"}


FALLBACK_CLI = os.path.join("_build", "js", "debug", "build", "cmd", "cli", "cli.js")


def fallback_launch(root: str):
    p = os.path.join(root, FALLBACK_CLI)
    if not os.path.isfile(p):
        return None
    return {"command": sys.executable and "node", "args": [p, "serve"],
            "source": "FALLBACK(_build/js/.../cli.js)——**已降级，非生产配置**"}


INIT_REQ = {
    "jsonrpc": "2.0", "id": 1, "method": "initialize",
    "params": {"protocolVersion": "2024-11-05", "capabilities": {},
               "clientInfo": {"name": "stdio-purity-probe", "version": "0"}},
}


def spawn_and_talk(launch, reqs, timeout=60):
    """spawn 生产描述，把 reqs 逐行喂进去，返回 (stdout_lines, stderr_text)。"""
    payload = "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in reqs)
    try:
        p = subprocess.Popen(
            [launch["command"]] + launch["args"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding="utf-8", errors="replace", cwd=ROOT,
        )
    except OSError as e:
        return None, "spawn 失败: %s" % e
    try:
        out, err = p.communicate(payload, timeout=timeout)
    except subprocess.TimeoutExpired:
        p.kill()
        out, err = p.communicate()
        return (out or "").splitlines(), (err or "") + "\n[超时 %ss]" % timeout
    return (out or "").splitlines(), err or ""


def l2_l3_dynamic(root: str, launch):
    """返回 (rc, detail)。"""
    reqs = [INIT_REQ,
            {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}},
            # ⚠️ 探针工具必须**零参数、零副作用、纯计算**：`mode_list` 是这类
            #    （真源 `src/ops/ops_modes.mbt`，纯计算只读）。
            #    实测踩过：曾用 `version` —— 它是 **CLI 子命令**不是 MCP 工具，
            #    回执是 `error: Tool not found`，被判成 L3 脏（**假红**）。
            #    判例-32 同族：探针名要先在新鲜样本上标定，不能凭印象挑。
            {"jsonrpc": "2.0", "id": 2, "method": "tools/call",
             "params": {"name": "mode_list", "arguments": {}}}]
    lines, err = spawn_and_talk(launch, reqs)
    if lines is None:
        return RC_BROKEN, {"note": err}

    # ── L2：stdout 的**每一行**都必须是合法 JSON ───────────────────────
    bad = []
    parsed = []
    for i, ln in enumerate(lines):
        if not ln.strip():
            continue
        try:
            parsed.append(json.loads(ln))
        except Exception as e:  # noqa: BLE001
            bad.append((i, ln[:150], str(e)[:70]))
    if not parsed:
        return RC_BROKEN, {"note": "server 没有任何 stdout 输出（起不来？）\nstderr: %s"
                           % err[-600:], "stderr": err}
    if bad:
        return RC_DIRTY, {"layer": "L2", "bad_lines": bad, "stderr": err}

    # ── L3：tools/call 必须拿到 result.content ─────────────────────────
    call = None
    for obj in parsed:
        if isinstance(obj, dict) and obj.get("id") == 2:
            call = obj
            break
    if call is None:
        return RC_BROKEN, {"note": "没拿到 tools/call 的回执（id=2）", "stderr": err}
    if "result" not in call:
        return RC_DIRTY, {"layer": "L3",
                          "note": "tools/call 无 result（R33 的失败形态：KeyError 'content'）",
                          "reply": json.dumps(call, ensure_ascii=False)[:300],
                          "stderr": err}
    res = call.get("result")
    if not isinstance(res, dict) or "content" not in res:
        return RC_DIRTY, {"layer": "L3",
                          "note": "result 里没有 content（客户端会 KeyError）",
                          "reply": json.dumps(call, ensure_ascii=False)[:300],
                          "stderr": err}
    return RC_OK, {"n_stdout": len(parsed), "stderr": err}


def render_static(hits, n_files, n_tools):
    print("[L1 静态] 扫 %d 个产品文件（%d 处 instrumented_tool）" % (n_files, n_tools))
    if hits:
        print("[L1 违例] 这些位置会往 **stdout** 写非 JSON-RPC 内容：")
        for rel, ln, code in hits:
            print("  ✗ %s:%d  %s" % (rel, ln, code))
        print("  ⇒ 改用 `eprintln`（走 stderr）；MCP stdio 的 stdout 是协议通道。")
    else:
        print("[L1] 干净（无写 stdout 的调用）")


def judge(root: str, static_only: bool, allow_fallback: bool):
    hits, n_files, n_tools = l1_scan(root)
    # ④ 反脱锚：src/server 不在 / 一个工具都解析不到 ⇒ 尺子坏了
    if n_files == 0:
        return RC_RULER, {"note": "src/server/ 下没有产品 .mbt ⇒ 尺子坏了（找不到被测对象）"}
    if n_tools == 0:
        return RC_RULER, {"note": "src/server/ 里一个 instrumented_tool 都没解析到 ⇒ 尺子坏了"}

    render_static(hits, n_files, n_tools)
    if hits:
        return RC_DIRTY, {"layer": "L1", "hits": hits, "n_files": n_files, "n_tools": n_tools}

    if static_only:
        print("[L2/L3] 跳过（--static-only）")
        return RC_OK, {"skipped_dynamic": True}

    launch = load_launch(root)
    if launch is None:
        if not allow_fallback:
            return RC_BROKEN, {"note": "拿不到 .mcp.json 的启动描述 ⇒ 无法用生产路径自证（rc=2）。"
                                       "要退回 cli.js 请显式传 --allow-fallback（会明说降级）"}
        launch = fallback_launch(root)
        if launch is None:
            return RC_BROKEN, {"note": "既无 .mcp.json 也无 cli.js 产物 ⇒ 无法自证"}
    print("[L2/L3 动态] 启动描述来源：%s" % launch["source"])
    print("            %s %s" % (launch["command"], " ".join(launch["args"])))
    rc, d = l2_l3_dynamic(root, launch)
    if rc == RC_OK:
        print("[L2] stdout %d 行全部是合法 JSON-RPC ✅" % d["n_stdout"])
        print("[L3] tools/call 的 result.content 存在 ✅")
    elif rc == RC_DIRTY:
        print("[%s 违例] %s" % (d.get("layer", "L2"), d.get("note", "")))
        for i, ln, e in d.get("bad_lines", []):
            print("  ✗ stdout[%d] 非 JSON：%r" % (i, ln))
            print("     解析错误：%s" % e)
        if d.get("reply"):
            print("  ✗ 回执：%s" % d["reply"])
    else:
        print("[FATAL] %s" % d.get("note", ""))
    return rc, d


def selftest() -> int:
    cells = []

    def cell(name, got, want):
        cells.append((name, got, want))
        print("  [%s] %-46s got=%r want=%r"
              % ("OK" if got == want else "FAIL", name, got, want))

    print("[selftest] 1) L1 静态：形态识别（按语义而非字面）")
    on = ["let x = println(\"a\")", "print(\"b\")", "print_char('c')"]
    off = ["eprintln(\"d\")", "eprint(\"e\")", "// println(\"f\")",
           "let s = \"println(\\\"x\\\")\""]
    for i, l in enumerate(on):
        code = strip_strings(l)
        ex = code
        for e in STDOUT_EXEMPT:
            ex = ex.replace(e, "")
        cell("on-%d-%s" % (i, l.split("(")[0]), any(w in ex for w in STDOUT_WRITERS), True)
    for i, l in enumerate(off):
        # ⚠️ 与 l1_scan 同口径：注释行在 code_lines() 里已被**跳过**，
        #    字符串内容在 strip_strings() 里已被**抹掉**。
        #    这里复刻同一条链，而不是各写一份（判例-435：抄写真源会漂）。
        is_comment = l.strip().startswith("//")
        code = strip_strings(l)
        ex = code
        for e in STDOUT_EXEMPT:
            ex = ex.replace(e, "")
        hit = (not is_comment) and any(w in ex for w in STDOUT_WRITERS)
        cell("off-%d-%s" % (i, l[:16].replace(" ", "")), hit, False)

    print("[selftest] 2) ★变异对照：真的往产品文件写 println ⇒ L1 必红")
    # 用临时根造一个 mini src/server
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        os.makedirs(os.path.join(td, "src", "server"), exist_ok=True)
        f = os.path.join(td, "src", "server", "srv.mbt")
        io.open(f, "w", encoding="utf-8").write(
            'pub fn f() -> Unit {\n'
            '  eprintln("ok to stderr")\n'
            '  instrumented_tool(s1, "t", "d", schema({}, []), fn(a) { 1 })\n'
            '}\n')
        h0, nf0, nt0 = l1_scan(td)
        cell("clean-mini-no-hits", len(h0), 0)
        cell("clean-mini-sees-file", nf0, 1)
        cell("clean-mini-sees-tool", nt0 >= 1, True)

        # ★变异：加一行 println
        io.open(f, "w", encoding="utf-8").write(
            'pub fn f() -> Unit {\n'
            '  eprintln("ok to stderr")\n'
            '  println("POLLUTION")\n'
            '  instrumented_tool(s1, "t", "d", schema({}, []), fn(a) { 1 })\n'
            '}\n')
        h1, _n, _t = l1_scan(td)
        cell("MUTATION-println-detected", len(h1), 1)
        cell("MUTATION-names-line", h1 and h1[0][1] == 3, True)

        # ★变异 2：把 println 塞进字符串里 ⇒ **不该**报（去死角）
        io.open(f, "w", encoding="utf-8").write(
            'pub fn f() -> Unit {\n'
            '  let s = "println(\\"decoy\\")"\n'
            '  instrumented_tool(s1, "t", "d", schema({}, []), fn(a) { 1 })\n'
            '}\n')
        h2, _n, _t = l1_scan(td)
        cell("MUTATION-string-decoy-not-reported", len(h2), 0)

        # ★变异 3：注释里的 println ⇒ 不该报
        io.open(f, "w", encoding="utf-8").write(
            'pub fn f() -> Unit {\n'
            '  // println("in comment")\n'
            '  instrumented_tool(s1, "t", "d", schema({}, []), fn(a) { 1 })\n'
            '}\n')
        h3, _n, _t = l1_scan(td)
        cell("MUTATION-comment-not-reported", len(h3), 0)

    print("[selftest] 3) ★反脱锚：找不到 src/server ⇒ rc=4（尺子坏了），不是判绿")
    with tempfile.TemporaryDirectory() as td2:
        rc, d = judge(td2, static_only=True, allow_fallback=False)
        cell("MUTATION-missing-server-dir-rc4", rc, RC_RULER)
    with tempfile.TemporaryDirectory() as td3:
        os.makedirs(os.path.join(td3, "src", "server"), exist_ok=True)
        io.open(os.path.join(td3, "src", "server", "x.mbt"), "w",
                encoding="utf-8").write('pub fn g() -> Unit { ignore(1) }\n')
        rc, d = judge(td3, static_only=True, allow_fallback=False)
        cell("MUTATION-no-tools-rc4", rc, RC_RULER)

    print("[selftest] 4) L2/L3 判据：非 JSON 行 / 缺 content 必须判脏")
    # 直接测判定逻辑（不 spawn）
    def judge_lines(lines):
        bad = []
        parsed = []
        for i, ln in enumerate(lines):
            if not ln.strip():
                continue
            try:
                parsed.append(json.loads(ln))
            except Exception:  # noqa: BLE001
                bad.append(i)
        if not parsed:
            return RC_BROKEN
        if bad:
            return RC_DIRTY
        return RC_OK

    cell("l2-clean-json", judge_lines(['{"jsonrpc":"2.0","id":1,"result":{}}']), RC_OK)
    cell("l2-MUTATION-polluted-line",
         judge_lines(['[fist-mbt] auth_mode = off', '{"jsonrpc":"2.0","id":1,"result":{}}']),
         RC_DIRTY)
    cell("l2-empty-output", judge_lines([]), RC_BROKEN)

    ok = sum(1 for _n, g, w in cells if g == w)
    print("\n[selftest] %d/%d 格通过" % (ok, len(cells)))
    return 0 if ok == len(cells) else 4


def main(argv=None):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--static-only", action="store_true")
    ap.add_argument("--allow-fallback", action="store_true")
    ap.add_argument("--root", default="")
    a = ap.parse_args(argv)
    if a.selftest:
        return selftest()
    root = a.root or ROOT
    try:
        rc, _d = judge(root, a.static_only, a.allow_fallback)
    except Exception as e:  # noqa: BLE001
        print("[FATAL] 判据自己崩了：%r ⇒ rc=4（尺子坏了）" % (e,))
        return RC_RULER
    return rc


if __name__ == "__main__":
    sys.exit(main())
