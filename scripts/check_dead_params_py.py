#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_dead_params_py.py —— **Python 侧**死参数判据（R82）。

## 为什么要有这一把

`check_dead_params.py` 现读「无死参数」，但它**只扫 `.mbt`**。R81 实测：`mcp_tool_tour.py` 的
`build_args(tool, schema, ctx, read_only)` 里 `read_only` **函数体从未使用**，而调用方认真传了
`a.plane == "read"` 表达意图 ⇒ **意图被静默丢弃**，而没有任何判据看得见。

**⇒ 判据的覆盖面比它的结论窄** —— 与「GREEN 但 26 个工具从未被调用」同族。

## 判据面（AST，不靠正则）

对 `scripts/**/*.py` 的每个函数：收集形参名（位置/仅位置/仅关键字），
若某形参在**函数体内零引用**（不含它的 `ast.Name` Load）⇒ 记为死参数。

**豁免口径**（每条都有实测理由，宁可少报也不制造噪声）：

| 豁免 | 理由 |
|---|---|
| `self` / `cls` | 方法约定 |
| 以 `_` 开头 | 「本参数有意不用」的通用写法（PEP 8） |
| `*args` / `**kwargs` | 收集器，天然可能不用 |
| 函数体里出现 `locals()` / `vars()` | 动态取参，静态看不见 |
| 回调签名白名单（`sig`/`frame`/`handler`/`event`/`exc`…） | 协议要求签名，参数由框架填 |
| 函数体只有 `...` / `pass` / docstring | 桩函数（抽象方法/占位实现） |

## 退出码

- `0` = 无死参数（且至少扫到 1 个函数）
- `1` = 有死参数（逐条点名）
- `2` = 判据无法自证（一个函数都没解析到）
- `4` = 尺子自己坏了

## 自证（判例-29/30）

`--selftest` 用**合成源码串**验：① 有死参数必须被抓；② 用了的不许误报；
③ 豁免口径（`_x` / `self` / `**kw` / 回调名）不许误报；④ 桩函数不许误报。
"""
import argparse
import ast
import glob
import io
import os
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.dirname(os.path.abspath(__file__)) + "/..")
SCAN_GLOB = os.path.join(ROOT, "scripts", "**", "*.py")

CALLBACK_PARAMS = {
    "sig", "frame", "event", "exc", "exception", "tb", "value", "key",
    "handler", "callback", "cb", "args", "kwargs", "request", "response",
}
STUB_ONLY = (ast.Pass, ast.Expr)
PRINT_CAP = 25

# 带理由的豁免表（键 = (相对路径, 函数名, 形参名)）。每条都必须写清「为什么不删」，
# 否则就成了免检牌。R83 实测第一例：夹具类要**保签名 drop-in**，参数按设计不用。
EXEMPT = {
    ("scripts/mcp_tool_tour.py", "raw", "params"):
        "夹具类方法：靠 self.spec 查表返回固定回执，params 保留是为了与真客户端 drop-in 同签名",
}


def _is_stub(body):
    """函数体是否只有 docstring / pass / ...（占位实现）"""
    real = []
    for node in body:
        if isinstance(node, ast.Expr) and isinstance(node.value, ast.Constant):
            continue           # docstring / ...
        if isinstance(node, ast.Pass):
            continue
        real.append(node)
    return not real


def _dynamic_locals(body):
    """body 是**语句列表**（不是 AST 节点）⇒ 必须逐语句 walk（R82 实测：直接 ast.walk(list)
    会抛 `AttributeError: 'list' object has no attribute '_fields'`）。"""
    for stmt in body:
        for node in ast.walk(stmt):
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) \
                    and node.func.id in ("locals", "vars"):
                return True
    return False


def scan_source(src, rel="<src>"):
    """纯函数：返回 [(rel, func, param, lineno)]。"""
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return []
    out = []
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        a = node.args
        params = []
        for p in list(getattr(a, "posonlyargs", [])) + list(a.args) + list(a.kwonlyargs):
            params.append((p.arg, getattr(p, "lineno", node.lineno)))
        # *args / **kwargs 不收：收集器天然可能不用，且它们的「使用」形态与普通形参不同
        # （R82 自证 exempt 格实测：把它们当普通形参 ⇒ `**kw` 被误报）。
        if not params:
            continue
        if _is_stub(node.body) or _dynamic_locals(node.body):
            continue
        used = {n.id for n in ast.walk(node) if isinstance(n, ast.Name)
                and isinstance(n.ctx, ast.Load)}
        for name, lineno in params:
            if name in ("self", "cls") or name.startswith("_"):
                continue
            if name in CALLBACK_PARAMS:
                continue
            if name not in used:
                out.append((rel, node.name, name, lineno))
    return out


def scan(root=ROOT):
    """返回 (findings, n_funcs)。"""
    findings = []
    n_funcs = 0
    for path in sorted(glob.glob(os.path.join(root, "scripts", "**", "*.py"), recursive=True)):
        if "__pycache__" in path:
            continue
        rel = os.path.relpath(path, root).replace("\\", "/")
        try:
            src = io.open(path, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        try:
            tree = ast.parse(src)
        except SyntaxError:
            continue
        n_funcs += sum(1 for n in ast.walk(tree)
                       if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)))
        got = scan_source(src, rel)
        got = [x for x in got if (x[0], x[1], x[2]) not in EXEMPT]
        findings.extend(got)
    return findings, n_funcs


def selftest():
    cells, fails = [], []

    def cell(name, ok):
        cells.append(name)
        if not ok:
            fails.append(name)

    dead = "def f(a, b):\n    return a\n"
    used = "def f(a, b):\n    return a + b\n"
    exempt = ("def f(self, _x, **kw):\n    return 1\n"
              "def cb(sig, frame):\n    return 2\n")
    stub = "def f(a):\n    'doc'\n    ...\n"

    cell("dead-param-flagged", [x[2] for x in scan_source(dead)] == ["b"])
    cell("used-param-not-flagged", scan_source(used) == [])
    cell("exempt-not-flagged", scan_source(exempt) == [])
    cell("stub-not-flagged", scan_source(stub) == [])
    cell("syntax-error-returns-empty", scan_source("def f(a:\n") == [])
    # 端到端：真实扫描面必须非空（否则判据饿死）
    findings, n = scan(ROOT)
    cell("real-face-nonempty", n > 0)

    print("SELFTEST %s（%d 格：%s）" % ("OK" if not fails else "FAIL", len(cells), " ".join(cells)))
    print("  真实扫描面：%d 个函数，死参数 %d 条" % (n, len(findings)))
    for f in fails:
        print("SELFTEST FAIL " + f)
    return 0 if not fails else 1


def main(argv):
    ap = argparse.ArgumentParser(description="Python 侧死参数判据（AST）")
    ap.add_argument("--selftest", action="store_true", help="自证（合成源码串，判例-29/30）")
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()
    findings, n = scan(ROOT)
    if n == 0:
        print("FATAL 判据无法自证：一个函数都没解析到 ⇒ 拒绝出绿")
        return 2
    print("扫描面：%d 个函数（scripts/**/*.py）" % n)
    if findings:
        print("FAIL Python 死参数 %d 条（形参在函数体内零引用 ⇒ 调用方传了也没人用）："
              % len(findings))
        for rel, func, param, ln in findings[:PRINT_CAP]:
            print("  - %s:%d %s() 参数 %s 未被使用" % (rel, ln, func, param))
        if len(findings) > PRINT_CAP:
            print("  …（共 %d 条，只列前 %d）" % (len(findings), PRINT_CAP))
        print("处置：删掉该形参并同步调用点，或按职责补上使用；确属协议要求则在签名里改名 `_x`。")
        return 1
    print("PASS Python 面无死参数：%d 个函数全部形参都有引用" % n)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except SystemExit:
        raise
    except Exception as exc:  # 尺子自己坏了：4
        print("FATAL 判据未捕获异常：%r" % (exc,))
        sys.exit(4)
