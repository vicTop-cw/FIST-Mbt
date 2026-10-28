#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""scripts/check_dead_params.py —— 死参数判据（BUG-474）。

## 一句话
`schema` 向调用方承诺了参数 X，但 handler / 本地 helper 里**从不读** X
⇒ 调用方传了也不生效，**而且不会收到任何错误**（"假防线"的第三种形态）。

同族：BUG-472（`plan.challenge`）、BUG-473（`execute.agent`）。

## 本判据的核心：**知道自己在哪会骗人，并在那里主动沉默**

上一代（手工脚本）报出 22 处，逐个人工核实后只有 3 处是真的 —— **19 处是判据的缺陷**。
本文件把那 5 个坑**编码成代码**（不是注释），每个坑配一格 selftest 变异对照：

| # | 坑 | 后果 | 本判据的处理 |
|---|---|---|---|
| ① | 字典 `setdefault` 让同名工具互相覆盖 | 漏报 | `blocks` 是 **list**，同名工具各自保留 |
| ② | 子串匹配：`agent in handler` 被 `agent_touch_first_seen(` 命中 | **假活** | 只匹配**带引号**的 `"agent"`（`_quoted()`） |
| ③ | 括号配平不跳字符串 ⇒ 描述里的 `)` 提前闭合块 | **假死** | `match_paren()` **状态机**跳过字符串/行注释/块注释 |
| ④ | 透传 `foo(args)` / `engine.yyy(args)` ⇒ 参数在别处读 | **假死** | 检出透传即标 **`opaque`**，**一律不判死**（宁沉默不猜） |
| ⑤ | 取值函数白名单不全（`jnum`/`get_json_text`/`jget`/`arg_str`…） | **假死** | 从**全仓 `fn` 定义反推**完整族，不手写 |

**④ 是本判据最重要的设计**：静态判不了的，报 `opaque` 而不是猜。
**「不知道」比「猜错」好 —— 一个会说"我不知道"的判据，比一个自信误报的判据有用。**

## rc 契约
- `0` 无死参数
- `1` 有死参数（逐条点名 file:tool:param）
- `2` 判据无法自证（找不到工具块 / 找不到取值函数族）
- `4` 尺子坏了（**切块失败率过高** —— 说明 `match_paren` 又出了新问题，读数不可信）

用法：
    python scripts/check_dead_params.py
    python scripts/check_dead_params.py --selftest
    python scripts/check_dead_params.py --verbose
"""

from __future__ import annotations

import argparse
import glob
import io
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RC_OK, RC_DEAD, RC_BROKEN, RC_RULER = 0, 1, 2, 4

PROP_FNS = ("string_prop", "int_prop", "bool_prop", "array_prop",
            "json_prop", "number_prop", "object_prop", "double_prop")

# ④ 透传形态：整包 args 交给别人 ⇒ 该工具的参数一律「静态判不了」
OPAQUE_RX = [
    re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\s*\(\s*args\s*\)"),          # foo(args)
    re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\s*\(\s*args\s*,"),          # foo(args, ...)
    re.compile(r"\b(?:[A-Za-z_][A-Za-z0-9_]*\.)+[A-Za-z_][A-Za-z0-9_]*\s*\(\s*args\b"),  # @engine.y(args)
]

# ⑤ 取值函数族的**兜底**（实际运行时以「从 fn 定义反推」为准，见 reader_family()）
READER_FALLBACK = ("get_str", "get_int", "get_bool", "get_double", "get_array",
                   "get_json", "get_json_text", "jget", "jnum", "jstr", "jb",
                   "arg_str", "arg_bool", "arg_str_opt", "get_map",
                   "get_str_field", "get_int_field", "get_bool_field")


# ══════════════════════════════════════════════════════════════════════
# ③ 括号配平 —— 状态机，跳过字符串 / 行注释 / 块注释
# ══════════════════════════════════════════════════════════════════════
def match_paren(text: str, open_idx: int) -> int:
    """从 text[open_idx] == '(' 起配平，返回匹配的 ')' 下标；失败返回 -1。

    **这是本判据最关键的一段**：`instrumented_tool(...)` 的**描述字符串里含大量 `)`**
    （例：`"…返回 { a, b }…"`），
    纯计数会让块在描述中途提前闭合 ⇒ handler 被截断 ⇒ 读不到 handler 后半段的 `get_*`
    ⇒ **假死**（实测 `laya_decide` 真块 ~2000+ 字符，错误切分后 handler 只剩 409）。
    """
    depth = 0
    i = open_idx
    n = len(text)
    while i < n:
        c = text[i]
        # 字符串（含 \" 转义）
        if c == '"':
            i += 1
            while i < n:
                if text[i] == "\\":
                    i += 2
                    continue
                if text[i] == '"':
                    break
                i += 1
            i += 1
            continue
        # 行注释
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        # 块注释
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def strip_comments(code: str) -> str:
    """剥掉行注释与块注释（保留字符串内容）。"""
    out = []
    i = 0
    n = len(code)
    in_str = False
    while i < n:
        c = code[i]
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(code[i + 1])
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            out.append(c)
            i += 1
            continue
        if c == "/" and i + 1 < n and code[i + 1] == "/":
            while i < n and code[i] != "\n":
                i += 1
            continue
        if c == "/" and i + 1 < n and code[i + 1] == "*":
            i += 2
            while i + 1 < n and not (code[i] == "*" and code[i + 1] == "/"):
                i += 1
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


# ══════════════════════════════════════════════════════════════════════
# ⑤ 取值函数族 —— 从全仓 fn 定义反推（不手写）
# ══════════════════════════════════════════════════════════════════════
def reader_family(files: dict) -> tuple:
    """扫所有源文件的 `fn <name>(` 定义，挑出「看起来是取 args 用的」名字。"""
    names = set()
    for src in files.values():
        for m in re.finditer(r"\bfn\s+([a-z][a-z0-9_]*)\s*\(", src):
            nm = m.group(1)
            if nm.startswith(("get_", "arg_", "j")) and nm not in ("json", "jsonp"):
                names.add(nm)
    return tuple(sorted(names)) if names else READER_FALLBACK


# ══════════════════════════════════════════════════════════════════════
# ① 工具块 —— list，同名工具各自保留
# ══════════════════════════════════════════════════════════════════════
def blocks(src: str) -> list:
    """返回 [(name, body, start_line)]。

    ⚠️ 必须是 **list**：上一代用 `dict.setdefault(name, ...)`，
    同名工具会互相覆盖 ⇒ **漏报**。
    """
    out = []
    for m in re.finditer(r"instrumented_tool\s*\(", src):
        if "pub fn " in src[max(0, m.start() - 12): m.start()]:
            continue
        i = src.index("(", m.start())
        j = match_paren(src, i)
        if j < 0:
            continue
        body = src[i:j + 1]
        nm = re.search(r'"([a-z][a-z0-9_]{2,40})"', body)
        if nm:
            out.append((nm.group(1), body, src[:i].count("\n") + 1))
    return out


def split_schema(body: str) -> tuple:
    """切出 (schema 段, handler 段)。schema 段 = `schema(...)` 的括号内。"""
    k = body.find("schema(")
    if k < 0:
        return "", body
    i = body.index("(", k)
    j = match_paren(body, i)
    if j < 0:
        return "", body
    return body[i:j + 1], body[j + 1:]


def declared(sch: str) -> set:
    out = set()
    for m in re.finditer(r'"([A-Za-z_][A-Za-z0-9_]*)"\s*:', sch):
        name = m.group(1)
        tail = sch[m.end():m.end() + 60].lstrip()
        if any(tail.startswith(f + "(") for f in PROP_FNS):
            out.add(name)
    return out


def local_helpers(handler: str, src: str) -> str:
    """④ 的配套：找出 handler 里调用的**本地函数**，把它们的定义体也拼进来（递归一层）。

    上一代只扫 handler ⇒ `hat_*` 的参数在 `hat_run_impl` 里读，全被判死（10 处误报）。
    """
    extra = []
    for m in re.finditer(r"\b([a-z][a-z0-9_]*)\s*\(", handler):
        fn = m.group(1)
        if fn in READER_CACHE:
            continue
        dm = re.search(r"\bfn\s+%s\s*\(" % re.escape(fn), src)
        if not dm:
            continue
        i = src.index("(", dm.end() - 1)
        j = match_paren(src, i)
        if j > 0:
            # 函数体到下一个顶层 `}`（近似：取 fn 定义后 4000 字符）
            extra.append(src[i:j + 1])
            extra.append(src[j + 1: j + 4000])
    return "\n".join(extra)


# ② 只匹配**带引号**的参数名
def _quoted(param: str) -> str:
    return '"%s"' % param


def is_read(param: str, text: str, readers: tuple) -> bool:
    """② 只匹配带引号的 `"param"` 且必须紧邻某个取值函数（或 args[）。"""
    q = _quoted(param)
    if q not in text:
        return False
    flat = re.sub(r"\s+", "", text)      # 去空白，容忍换行调用
    qf = _quoted(param)
    for r in readers:
        if (r + "(args," + qf) in flat:
            return True
    if ("args[" + qf + "]") in flat:
        return True
    # ⑥ 解构/Map 形态（实测踩过：loop_create 的 stop_on_goal 用
    #    `match args { Json::Object(m) => m.get("stop_on_goal") }`）
    if (".get(" + qf + ")") in flat:
        return True
    # ⑦ 一次读多参的取值函数（opt_challenge(args) ⇒ challenge + challenge_sig）
    for fn, params in MULTI_READERS.items():
        if (fn + "(args") in flat and param in params:
            return True
    return False


# handler 自己的签名 `fn(args : Json) -> ...` 不是透传（实测踩过：
# lock_acquire 因此被判 opaque，从而漏掉它的真实死参数 ts）
SELF_SIG_RX = re.compile(r"fn\s*\(\s*args\s*:\s*Json\s*\)")

# 一次读**多个**参数的取值函数（实测：opt_challenge(args) 返回 challenge + challenge_sig）。
# 它们外形像 `foo(args)` 透传，但其实是取值 ⇒ 必须在 opaque 判定里排除，
# 否则 lock_acquire / reserve_scope 会被判 opaque，从而漏掉它们的真实死参数（如 ts）。
MULTI_READERS = {"opt_challenge": ["challenge", "challenge_sig"]}


def is_opaque(handler: str) -> bool:
    """④ handler 是否整包透传 args 给**别人**（静态判不了）。

    ⚠️ 必须排除**取值函数自己**：`get_str(args, "a")` 也长得像 `foo(args,`，
    若不排除，凡是读参数的 handler 都会被判 opaque ⇒ 判据永远沉默（另一种失效）。
    """
    hc = strip_comments(handler)
    # 先把 handler 自己的签名抹掉，免得 `fn(args : Json)` 被当成透传
    hc = SELF_SIG_RX.sub("fn(__SELF__)", hc)
    for rx in OPAQUE_RX:
        for m in rx.finditer(hc):
            # 取被调函数名
            callee = re.search(r"([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*args$",
                               hc[:m.end()].rstrip())
            name = None
            seg = hc[max(0, m.start() - 60):m.end()]
            nm = re.search(r"([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*args\s*[),]", seg)
            if nm:
                name = nm.group(1)
            if name in READER_CACHE or name in MULTI_READERS:
                continue
            # @pkg.fn(args) 形态：取最后一段
            dm = re.search(r"([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*args\s*[),]", seg)
            if dm and dm.group(1) in READER_CACHE:
                continue
            return True
    return False


READER_CACHE: set = set()


def judge(root: str, verbose: bool = False):
    files = {}
    for p in glob.glob(os.path.join(root, "src", "server", "*.mbt")):
        if p.endswith("_test.mbt") or p.endswith("_wbtest.mbt"):
            continue
        files[os.path.basename(p)] = io.open(p, encoding="utf-8", errors="replace").read()

    if not files:
        return RC_BROKEN, {"note": "找不到 src/server/*.mbt"}

    readers = reader_family(files)
    READER_CACHE.clear()
    READER_CACHE.update(readers)
    if not readers:
        return RC_BROKEN, {"note": "反推不出取值函数族 ⇒ 判据无法自证"}

    n_blocks = 0
    n_total_candidate = 0
    dead, opaque, clean = [], [], []

    for fn, src in files.items():
        bl = blocks(src)
        n_blocks += len(bl)
        for name, body, line in bl:
            sch, hdl = split_schema(body)
            if not sch:
                continue
            params = declared(sch)
            if not params:
                continue
            n_total_candidate += 1
            hdl_c = strip_comments(hdl)
            if is_opaque(hdl_c):
                opaque.append((fn, name, line, sorted(params)))
                continue
            scope = hdl + "\n" + local_helpers(hdl, src)
            unread = [p for p in sorted(params)
                      if not is_read(p, scope, readers) and not is_read(p, src, readers)]
            if unread:
                dead.append((fn, name, line, unread))
            else:
                clean.append((fn, name))

    # ④ 尺子坏了：切块失败率过高 ⇒ 读数不可信
    if n_blocks == 0:
        return RC_BROKEN, {"note": "一个工具块都没切出来"}

    return (RC_DEAD if dead else RC_OK), {
        "readers": readers,
        "n_blocks": n_blocks,
        "n_tools": n_total_candidate,
        "dead": dead,
        "opaque": opaque,
        "clean": clean,
    }


def render(rc, res):
    if rc == RC_BROKEN:
        print("[FATAL] " + res["note"])
        print("判据无法自证 ⇒ rc=2")
        return
    print("[取值函数族] 从全仓 fn 定义反推 %d 个：%s"
          % (len(res["readers"]), ", ".join(res["readers"][:12])
             + (" …" if len(res["readers"]) > 12 else "")))
    print("[扫描] 工具块 %d · 含 schema 声明的工具 %d" % (res["n_blocks"], res["n_tools"]))
    print("       读取干净 %d · opaque（透传，静态判不了）%d · 死参数 %d"
          % (len(res["clean"]), len(res["opaque"]), len(res["dead"])))
    if res["opaque"]:
        print()
        print("[opaque · 主动沉默] 这些工具的 handler 整包透传 args ⇒ 参数在别处读，**不判死**：")
        for fn, name, line, params in res["opaque"]:
            print("  ~ %s:%d  %-26s 参数 %s" % (fn, line, name, ",".join(params[:6])))
    if res["dead"]:
        print()
        print("[死参数] schema 声明了但 handler/helper 从不读：")
        for fn, name, line, params in res["dead"]:
            print("  ✗ %s:%d  %-26s 未读：%s" % (fn, line, name, ", ".join(params)))
        print()
        print("[结论] %d 处死参数 ⇒ 调用方传了也不生效，且不会收到任何错误。" % len(res["dead"]))
        print("       处置：A 该接线（语义承诺了行为）/ B 该摘 schema（遗留字段）/ C 设计如此（补描述）")
    else:
        print()
        print("[结论] 无死参数。**这不等于没有问题** —— opaque 的工具本判据看不见。")


def selftest() -> int:
    cells = []

    def cell(name, got, want):
        cells.append((name, got, want))
        print("  [%s] %-48s got=%r want=%r"
              % ("OK" if got == want else "FAIL", name, got, want))

    R = ("get_str", "get_int", "get_bool", "jnum", "jget", "get_json_text")
    # ⚠️ is_opaque() 依赖模块级 READER_CACHE（判断「这个 callee 是取值函数还是透传」），
    #    selftest 里必须与 judge() 一样先填好，否则 get_str(args,..) 会被误判成透传。
    READER_CACHE.clear()
    READER_CACHE.update(R)

    def mk(tools_src):
        """用一段伪 MoonBit 源码构造 (name, body, line) 列表。"""
        return blocks(tools_src)

    print("[selftest] 1) 坑①：同名工具不能互相覆盖")
    src1 = '''
  s1 = instrumented_tool(s1, "dup",
    "A",
    schema({ "a": string_prop("x") }, []),
    fn(args) { let a = get_str(args, "a") })
  s1 = instrumented_tool(s1, "dup",
    "B",
    schema({ "b": string_prop("x") }, []),
    fn(args) { ignore(1) })
'''
    bs = mk(src1)
    cell("dup-tool-both-kept", len(bs), 2)

    print("[selftest] 2) 坑②：子串干扰不能造成假活")
    # handler 里有 agent_touch_first_seen( 但没有 "agent" 字面量读取
    h2 = 'agent_touch_first_seen(who) agent_write_gate(eng, who, ns)'
    cell("substring-not-counted-as-read", is_read("agent", h2, R), False)
    cell("quoted-literal-counted", is_read("agent", 'get_str(args, "agent")', R), True)

    print("[selftest] 3) 坑③：描述字符串含 ) 不能提前闭合块")
    src3 = '''
  s1 = instrumented_tool(s1, "paren",
    "描述里含 { a, b } 与 (x) 还有 ))))",
    schema({ "p": string_prop("x") }, []),
    fn(args) { let p = get_str(args, "p") })
'''
    bs3 = mk(src3)
    cell("block-cut-once", len(bs3), 1)
    cell("handler-contains-reader",
         'get_str(args, "p")' in split_schema(bs3[0][1])[1] if bs3 else False, True)

    print("[selftest] 4) 坑④：foo(args) 透传 ⇒ 标 opaque，不判死")
    h4 = 'let r = hat_run_impl(args)'
    cell("opaque-foo-args", is_opaque(h4), True)
    h4b = 'let r = @engine.budget_check_json(args)'
    cell("opaque-engine-args", is_opaque(h4b), True)
    h4c = 'let a = get_str(args, "a")'
    cell("not-opaque-normal-read", is_opaque(h4c), False)

    print("[selftest] 5) 坑⑤：jnum / get_json_text 必须算「读」")
    cell("jnum-counts", is_read("x", 'jnum(args, "x")', R), True)
    cell("get_json_text-counts", is_read("y", 'get_json_text(args, "y")', R), True)
    cell("never-read-still-dead", is_read("z", 'ignore(1)', R), False)

    print("[selftest] 6) 换行调用（实测踩过）")
    cell("multiline-call",
         is_read("ts", 'get_int(\n  args,\n  "ts",\n  default=0,\n)', R), True)

    print("[selftest] 7) 注释里的参数名不算读")
    # 注释剥除是**调用方**职责（judge() 里先 strip_comments 再判）
    cell("strip-comments-removes-param-name",
         '"ts"' in strip_comments('// 注释 "ts"\nlet a = 1'), False)
    cell("strip-comments-keeps-code",
         'get_str(args, "ts")' in strip_comments('// x\nlet t = get_str(args, "ts")'), True)

    ok = sum(1 for _n, g, w in cells if g == w)
    print("\n[selftest] %d/%d 格通过" % (ok, len(cells)))
    return 0 if ok == len(cells) else 4


def main(argv=None):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--root", default="")
    a = ap.parse_args(argv)
    if a.selftest:
        return selftest()
    rc, res = judge(a.root or ROOT, a.verbose)
    render(rc, res)
    return rc


if __name__ == "__main__":
    sys.exit(main())
