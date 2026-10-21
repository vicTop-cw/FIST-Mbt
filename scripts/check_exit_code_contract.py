#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""scripts/check_exit_code_contract.py — 「退出码契约」承诺面 ↔ 实现面 守卫（BUG-369 建议①②）。

**为什么要有它**：R40/R41 实测抓到 `check_plan_landing` 自述 `2=判据无法自证`，而代码里的
`raise SystemExit("中文串")` **实给 1**（`SystemExit` 带字符串 ⇒ 打印该串、退出码 1，`python -c` 与真跑双测）
⇒ 「判据空转」与「有落点未落地」在退出码面上同色，而电池与 CI 的期望文本按 2 写。入账 BUG-369 后用 ast
重扫全仓，真相是**没有任何一面机器核过 scripts/ 里自述契约的脚本**。承诺与实现之间没有门，
下一把新尺照样可以写个假契约躺一周（BUG-366 同形：零执行面的尺 = 坏着的尺）。

**判定面（逐条点名，共用一个棘轮，只许下降）**：
  R1 模块面幻影 = 承诺面声明了码 N（N≥2）而 ast 实现面一个 N 都给不出。
      刻意不判 N∈{0,1}：0 恒可得（正常返回），1 是 Python 未捕获异常的默认码，任何脚本都能给出
      ⇒ 判它必假红。这是**按形状的保守**，不是按文件的豁免。
  R2 站点类指派矛盾 = 出口站点文本属「判据失灵」类（含 FATAL/空转/无法自证/拒绝报绿/尺子坏），
      承诺面把该类指派给码 M，而站点实给码集里没有 M。典型：`raise SystemExit("FATAL …")`（实给 1）
      配 `2=判据无法自证（FATAL）`。
  R3 站点自述码不符 = 站点文本自己写了 `rc=N` 而该站点实给码集里没有 N。
      这条抓的是**模块面看不见的假**：别处确有 `return 2` 时 R1 为 0，但这一处串式站点在文案里谎称自己给 2
      —— BUG-369 记的 `simulate_head_commit` 半形正是这形状。
**只报不判（必须出数：静默丢弃 = 数字凭空少，下轮无人能查少的是噪音还是缺陷）**：
  S 沉默出口 = 实现面能给出 N（N≥2）而承诺面没写；
  U 未认作契约 = 有出口站点但整份没有 `N=` 契约块（含 `0 全绿；1 有违例` 这类无等号写法 —— 文法不认，如实出数）；
  O 不透明出口 = ast 给不出码的站点，含 `sys.exit(p.returncode)` 这类**外部件透传**：它确实能给 2，
     只是那个 2 不在本仓字面里 ⇒ R1 对此类**主动让位**，但让位必须留名。

**校准（尺子必须先对着已知真相校，三条口径缺陷就是这么抓出来的）**：
  check_plan_landing ⇒ R1/R2/R3 全 0（emit_fatal 返 2 + `sys.exit(main())` 透传，真契约）
<<<<<<< HEAD
  check_mbti_sync / check_pkg_imports ⇒ R1 各一条 + R2 若干（纯幻影）
  simulate_head_commit ⇒ R1 为 0（别处真给 2）但 R3 一条（半形）
=======
  check_template_ctrl ⇒ 立判据时 R1 一条（R42 已修，calib 格改为「必须归零」）
  check_mbti_sync ⇒ 立判据时 R1 一条 + R2 七条（R43 已修，同上）
  check_pkg_imports ⇒ 立判据时 R1 一条 + R2 六条（R44 已修，同上）
  simulate_head_commit ⇒ 立判据时 R3 一条（半形：别处 `return 2` 真给 2，4 处串式 FATAL 只给 1，
                         其中一条文案自写「（rc=2）」）；R45 已修，calib 格改为「必须归零」—— 它是判定面上最后一把尺
>>>>>>> 57f24264 (fix: simulate_head_commit 的 4 处 FATAL 出口真给 rc=2，退出码棘轮 1→0（BUG-369 / T0r26）)
  普查第一版 `temp/r42_census.py` 因①「退出码」块跨行只吃到行尾 ②不认名字传播，
  把 `check_plan_landing` 判成「承诺 1 给不出」的**假红**；第二版 `temp/r42_census2.py` 又把
  `"FATAL …" % e` 算成不透明（check_pkg_imports 真 6 处串式只读出 4 处）⇒ 三条都由标注集抓出，写进上面文法。

用法：
  python scripts/check_exit_code_contract.py                # 全量（判定面 ≤ 上限 ⇒ 0，超限 ⇒ 1）
  python scripts/check_exit_code_contract.py --selftest     # 合成夹具 + 标注集自证（尺子必须先证明自己会红）
  python scripts/check_exit_code_contract.py --all-faces    # S/U/O 三面也计入退出码（现状必红，诊断用）
  python scripts/check_exit_code_contract.py --show-ceiling # 只打印上限与当前判定面读数
退出码：0=判定面在棘轮上限内 / 1=判定面超限（R1+R2+R3），或 --all-faces 下三面非空 / 2=判据无法自证（FATAL，真给 2）。
"""
import argparse
import ast
import io
import os
import re
import subprocess
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
README = os.path.join(ROOT, "scripts", "README.md")

# 棘轮：判定面（R1+R2+R3）条数上限，**只许下降**。放宽上限（改这个常量）是人的决定。
#
<<<<<<< HEAD
# 16 = 2026-10-21 现读真源，逐条对上 BUG-369 的标定面（`--selftest` 的 calib 格钉住这个构成）：
#   check_mbti_sync      R1×1 + R2×7 = 8
#   check_pkg_imports    R1×1 + R2×6 = 7
#   simulate_head_commit R3×1       = 1
#   check_template_ctrl  0（R42 本轮已修真 rc=2）｜check_plan_landing 0
# 每修好一把尺，这里必须跟着降；降到 0 才算 BUG-369 关闭。
CONTRACT_GAP_CEILING = 16
=======
# 这一档的构成（2026-10-21 R45 现读真源，逐条对上 BUG-369 的标定面；`--selftest` 的 calib 格钉住这个构成）：
#   simulate_head_commit 清零（R45 修真：4 处串式 FATAL 全改 emit_fatal ⇒ 「文案自写（rc=2）而站点实给 1」那条半形消失）
#   check_pkg_imports    清零（R44 修真：6 处串式）｜check_mbti_sync 清零（R43 修真：7 处串式）
#   check_template_ctrl  清零（R42 修真：1 处串式）｜check_plan_landing 立判据时本就 0
# 合计归零 ⇒ 当前上限 0：BUG-369 立案时那四把尺的存量全部清完，此后任何一条新假契约都必红（上限 0 没有容忍带）。
# 历史档位 16（R42 立判据时）→ 8（R43）→ 1（R44）→ 0（R45）；每修好一把尺这里必须跟着降。
#
# 降档必须核承重：判定面少 N 条要回头对 O/S/U 三面 —— 条数**搬家**（R1 让位给外部件透传）不等于消失。
# R45 现读 `simulate_head_commit` 的实现面含 2（emit_fatal 交回；moon 超时那支的 `return 2` 本来就在），
# 这一问由 `fixed-ruler-gives-two-in-impl-face` 一格钉住：五把修过的尺一起考。
#
# 上限归零后棘轮两格的写法：必须从常量导出（R44 定律），且「低于上限」这一档已不存在 ⇒ 走
# `tightening-not-applicable-at-zero-ceiling` 那条分支。**不许靠删格子维持绿**，也不许把上限调回正数。
#
# 写法约束：这段是「举例」不是「承诺」，所以**没有任何行首写成「数字等号」**——那是本判据认的契约头形状，
# 上一版开头是「8 = 2026-10-21 …」，于是自家注释把自己读成了一份新契约（有契约块的脚本 31→32）。
# 按既有定律：改写文本，不给判据开「跳过注释」的口子。`--selftest` 有格钉住这个形状。
CONTRACT_GAP_CEILING = 0
>>>>>>> 57f24264 (fix: simulate_head_commit 的 4 处 FATAL 出口真给 rc=2，退出码棘轮 1→0（BUG-369 / T0r26）)
MAX_CODE = 9
MAX_DEPTH = 8           # 值集解析的递归水位；断环靠 _busy，水位只防灾利性深链

FATAL_KEYS = ("FATAL", "判据无法自证", "判据自身失灵", "空转", "拒绝报绿", "尺子坏")
PAIR_AT = re.compile(r"(\d+)\s*=\s*")
HEAD_RE = re.compile(r"^\s*(?:退\s*出\s*码(?:契约)?|用\s*法(?:（[^）]*）)?|(?<![\d:])\d+\s*=)\s*[：:]?\s*")
RC_TEXT_RE = re.compile(r"rc\s*[=＝]\s*(\d)")
# 行首的文档装饰（docstring 三引号、注释符、缩进、markdown 强调符）不算承诺面的"非头"字符：
# 单行 docstring 里直接写契约、契约列表写在 `#` 注释块里（e2e_native_heap_probe 就是这种），
# 都是本仓库的真实形状。注意代价：形状识别分不出「举例」和「承诺」——注释里照抄一个
# 「数字等号说明」的例子会被当真契约读进来（本判据在自家注释上被抓到过一次，读数 16→17），
# 要举例就避开这个形状，别给判据开豁免面。
LEAD_JUNK = re.compile(r"^[\s\"'#*`>|~-]*")


def emit_fatal(msg):
    """判据无法自证 ⇒ **真给 2**（写 stderr，由 `sys.exit(main())` 落成退出码）。

    刻意不用 `raise SystemExit(msg)`：带字符串的 SystemExit 退出码是 1，正是本判据在抓的那条幻影。
    """
    sys.stderr.write(msg + "\n")
    return 2


# ---------------------------------------------------------------- 承诺面

def pairs_from(text):
    """把一段文本切成 [(码, 说明)]，说明吃到下一个 `N=` 之前为止。"""
    ms = list(PAIR_AT.finditer(text))
    out = []
    for i, m in enumerate(ms):
        nxt = ms[i + 1].start() if i + 1 < len(ms) else len(text)
        code = int(m.group(1))
        if code > MAX_CODE:
            continue
        out.append((code, text[m.end():nxt].strip()))
    return out


def contract_blocks(text):
    """承诺面抽取：从 `退出码`/`用法`/裸 `N=` 行起，吃到下一个不再含 `N=` 的行或空行为止（封顶 8 行）。

    口径缺陷①（跨行块）：check_plan_landing 的 0/1/2 写在两行，只吃行尾会把 2 漏出承诺面、
      反过来把 1 判成幻影 ⇒ **假红**。
    口径缺陷②（无标题契约行）：check_mbti_sync 的契约是缩进的 `  0=PASS / 1=违例 / 2=判据无法自证（FATAL）`，
      只认「退出码」标题会把真承诺读成没承诺 ⇒ **漏判**。
    """
    lines = text.splitlines()
    blocks, i = [], 0
    while i < len(lines):
        if not HEAD_RE.match(LEAD_JUNK.sub("", lines[i])):
            i += 1
            continue
        buf, j = [lines[i]], i + 1
        while j < len(lines) and (j - i) <= 8:
            nxt = lines[j]
            if not nxt.strip() or not PAIR_AT.search(nxt):
                break
            buf.append(nxt)
            j += 1
        blocks.append(" ".join(buf))
        i = max(j, i + 1)
    return blocks


def promise_face(text):
    """返回 (承诺码集合, 被判据失灵类指派的码集合, 全部 (码,说明) 对)。契约块必须含 `0=`。"""
    codes, fatal_codes, pairs = set(), set(), []
    for blk in contract_blocks(text):
        pp = pairs_from(blk)
        if not any(c == 0 for c, _ in pp):
            continue
        for c, desc in pp:
            codes.add(c)
            pairs.append((c, desc))
            if any(k in desc for k in FATAL_KEYS):
                fatal_codes.add(c)
    return codes, fatal_codes, pairs


def readme_slice(readme, base):
    """README 条目面：只吃 `- \`<base>\`` 起、到下一条条目止（别处对本名的提及不得记进本账）。"""
    lines = readme.splitlines()
    start = None
    for idx, line in enumerate(lines):
        if re.match(r"^\s*[-*]\s*`%s`" % re.escape(base), line):
            start = idx
            break
    if start is None:
        return ""
    out = [lines[start]]
    for line in lines[start + 1:]:
        if re.match(r"^\s*[-*]\s*`[^`]+`", line) or line.startswith("#"):
            break
        out.append(line)
    return "\n".join(out)


# ---------------------------------------------------------------- 实现面

def const_int(node):
    if isinstance(node, ast.Constant) and isinstance(node.value, int) \
            and not isinstance(node.value, bool):
        return node.value
    return None


def call_name(node):
    f = getattr(node, "func", None)
    if isinstance(f, ast.Attribute):
        return f.attr
    if isinstance(f, ast.Name):
        return f.id
    return None


def is_stringy(node):
    """SystemExit/exit 的**字符串实参**三种形状：字面量、`"…" % (…)`、f-string。

    口径缺陷③：普查 v2 把后两种算成「不透明」⇒ 串式 FATAL 少计（check_pkg_imports 真 6 处只读出 4 处）。
    """
    if isinstance(node, ast.Constant):
        return isinstance(node.value, str)
    if isinstance(node, ast.JoinedStr):
        return True
    if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Mod, ast.Mult)):
        return is_stringy(node.left)
    return False


def site_text(node):
    if isinstance(node, ast.Constant):
        return node.value if isinstance(node.value, str) else ""
    if isinstance(node, ast.JoinedStr):
        return " ".join(site_text(v) if isinstance(v, ast.Constant) else ast.unparse(v)
                        for v in node.values)
    if isinstance(node, ast.BinOp):
        return site_text(node.left) + " " + site_text(node.right)
    return ast.unparse(node)[:120]


class Analyzer:
    def __init__(self, tree):
        self.tree = tree
        self.funcs = {}
        for n in ast.walk(tree):
            if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
                self.funcs.setdefault(n.name, n)
        self.sites = []          # (lineno, 实给码集 or None, 文本, 外部件透传)
        self.impl = set()
        self.opaque = []
        self._busy = set()
        self._cache = {}
        self._mod = None

    def module_names(self):
        """模块作用域的名字表：`RC_RULER = 4` 这类常量，与顶层 `rc = main()` 这类透传变量。

        校准抓出的四条假红都出自这里：`laya_decide` / `e2e_native_heap_probe` 用常量当出口码，
        `store_isolation_probe` 用顶层 `sys.exit(rc)`（rc 来自 `main()`），
        `e2e_assistant_xproc` 的 `return 0 if ok else 2` 被深度上限截断 ⇒ 一律被误判成幻影。
        常量表**只吃模块作用域**（不进函数体），函数内的局部赋值另走 `names_of`。

        一并吃下元组解包 `RC_OK, RC_CRASH = 0, 1`（按位配对，两端都得是整数面才认）：
        `e2e_native_heap_probe.py` 就靠这一行喂给 `raise SystemExit(RC_RULER)`，
        漏了它 ⇒ 该文件实现面读成空、两条 R1 幻影假红。
        """
        if self._mod is not None:
            return self._mod
        out = {}
        stack = list(self.tree.body)
        while stack:
            n = stack.pop(0)
            if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                continue
            if isinstance(n, ast.AnnAssign) and isinstance(n.target, ast.Name):
                c = const_int(n.value)
                if c is not None:
                    out.setdefault(n.target.id, set()).add(c)
            if isinstance(n, ast.Assign) and n.value is not None:
                c = const_int(n.value)
                for t in n.targets:
                    if isinstance(t, ast.Name):
                        if c is not None:
                            out.setdefault(t.id, set()).add(c)
                        elif isinstance(n.value, ast.Call):
                            got = self.return_codes(call_name(n.value))
                            if got:
                                out.setdefault(t.id, set()).update(got)
                    elif isinstance(t, ast.Tuple) and isinstance(n.value, ast.Tuple):
                        for sub, val in zip(t.elts, n.value.elts):
                            if not isinstance(sub, ast.Name):
                                continue
                            sc = const_int(val)
                            if sc is not None:
                                out.setdefault(sub.id, set()).add(sc)
            stack.extend(ast.iter_child_nodes(n))
        self._mod = out
        return out

    def names_of(self, fname):
        """函数内赋过字面整数的名字 → 值集（够用的名字传播：`rc = 2 … return rc`）。

        本判据在自家宇宙（读它自己这份源码）上先崩过一次：`names_of` 里递归回 `expr_codes` 时
        把深度**归零**，遇上 `x = f(...)` 且 f 体内又有赋值时互为递归 ⇒ RecursionError（被
        `except RuntimeError` 接住给了 rc=2，因为 RecursionError 是 RuntimeError 的子类）。
        现在三处递归共用水位：深度透传 + `_busy` 断环 + 结果按函数名缓存（重入即当"看不出来"处理，不判红）。
        """
        fn = self.funcs.get(fname)
        if fn is None:
            return {}
        key = ("names", fname)
        if key in self._cache:
            return self._cache[key]
        if key in self._busy:
            return {}
        self._busy.add(key)
        out = {}
        for n in ast.walk(fn):
            if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) and n is not fn:
                continue
            if isinstance(n, ast.Assign):
                v = self.expr_codes(n.value, fname, 1)
                if v:
                    for t in n.targets:
                        if isinstance(t, ast.Name):
                            out.setdefault(t.id, set()).update(v)
        self._busy.discard(key)
        self._cache[key] = out
        return out

    def expr_codes(self, node, fname, depth):
        if node is None or depth > MAX_DEPTH:
            return set()
        c = const_int(node)
        if c is not None:
            return {c}
        if isinstance(node, ast.IfExp):
            return self.expr_codes(node.body, fname, depth + 1) | \
                self.expr_codes(node.orelse, fname, depth + 1)
        if isinstance(node, ast.BoolOp):
            s = set()
            for v in node.values:
                s |= self.expr_codes(v, fname, depth + 1)
            return s
        if isinstance(node, ast.Name):
            local = self.names_of(fname).get(node.id) if fname else None
            if local:
                return set(local)
            return set(self.module_names().get(node.id, set()))
        if isinstance(node, ast.Call):
            got = self.return_codes(call_name(node), depth + 1)
            # 调用点上的高阶透传：`sys.exit(run_guarded(main))` 的 0/1/3 从 `main` 穿过来，
            # `run_guarded` 自己只显式给 rc=4 ⇒ 只读被调函数会把承诺的 rc=3 判成幻影（假红）。
            for a in node.args:
                if isinstance(a, ast.Name) and a.id in self.funcs:
                    got |= self.return_codes(a.id, depth + 1)
            return got
        return set()

    def return_codes(self, fname, depth=0):
        """函数能交出去的退出码集：`return <expr>`（含名字传播与被调函数）。

        也算上「把函数名当实参递出去」的高阶透传：`sys.exit(run_guarded(main))` 里
        `run_guarded` 只显式返回 RC_RULER=4，真正的 0/1/3 从 `main` 穿过来。看不见这一层 ⇒
        承诺的 rc=3 被读成幻影（假红）。方向上这是**放宽实现面**：R1 只判"承诺了但给不出"，
        所以实现面多算只会少判红、不会多判红；代价是高阶包装上的漏判，记在下面的口径注释里。
        """
        fn = self.funcs.get(fname)
        if fn is None or depth > MAX_DEPTH:
            return set()
        key = ("ret", fname)
        if key in self._cache:
            return self._cache[key]
        if key in self._busy:
            return set()
        self._busy.add(key)
        out = set()
        for n in ast.walk(fn):
            if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) and n is not fn:
                continue
            if isinstance(n, ast.Return):
                out |= self.expr_codes(n.value, fname, depth + 1)
            elif isinstance(n, ast.Call):
                for a in n.args:
                    if isinstance(a, ast.Name) and a.id in self.funcs:
                        out |= self.return_codes(a.id, depth + 1)
        self._busy.discard(key)
        self._cache[key] = out
        return out

    def collect_sites(self):
        self._busy = set()
        self._cache = {}
        for n in ast.walk(self.tree):
            call = None
            if isinstance(n, ast.Raise) and isinstance(n.exc, ast.Call) \
                    and getattr(n.exc.func, "id", None) == "SystemExit":
                call = n.exc
            elif isinstance(n, ast.Expr) and isinstance(n.value, ast.Call) \
                    and call_name(n.value) == "exit":
                call = n.value
            if call is None:
                continue
            if not call.args:
                self.sites.append((n.lineno, {0}, "", False))
                continue
            a = call.args[0]
            txt = site_text(a)
            stringy = is_stringy(a)
            unp = ast.unparse(a)
            external = (not stringy) and ("returncode" in unp or "retcode" in unp)
            codes = {1} if stringy else self.expr_codes(a, None, 0)
            if not codes and isinstance(a, ast.Call):
                codes = self.return_codes(call_name(a))
            if not codes:
                self.opaque.append((n.lineno, unp[:70], external))
                self.sites.append((n.lineno, None, txt, external))
                continue
            self.sites.append((n.lineno, set(codes), txt, external))

        # 模块顶层 `sys.exit(main())` 透传：被调函数的 return 码即程序可给出的码
        for n in ast.walk(self.tree):
            if isinstance(n, ast.Expr) and isinstance(n.value, ast.Call) \
                    and call_name(n.value) == "exit" and n.value.args \
                    and isinstance(n.value.args[0], ast.Call):
                got = self.return_codes(call_name(n.value.args[0]))
                if got:
                    self.impl |= got

    def verdict(self, promised, fatal_codes, promised_pairs):
        self.collect_sites()
        for _, codes, _, _ in self.sites:
            if codes:
                self.impl |= codes
        bad, yielded = [], []
        has_external = any(ext for _, _, _, ext in self.sites)
        for n in sorted(c for c in promised if c >= 2):
            if n in self.impl:
                continue
            desc = next((d for c, d in promised_pairs if c == n), "")
            if has_external:
                yielded.append("R1 让位：承诺 rc=%d（%s）而实现面给不出，但该脚本有子进程 returncode "
                               "透传形状 ⇒ 计入不透明面、不判红" % (n, desc or "无说明"))
                continue
            bad.append("R1 模块面幻影：承诺 rc=%d（%s）但 ast 出口面给不出 —— 实现面=%s"
                       % (n, desc or "无说明", sorted(self.impl) or "空"))
        for lineno, codes, txt, _ in self.sites:
            if codes is None or not txt:
                continue
            if not any(k in txt for k in FATAL_KEYS):
                continue
            for m in sorted(fatal_codes):
                if m not in codes:
                    bad.append("R2 站点类指派矛盾：L%d 文本属判据失灵类（含 %s），承诺面把该类指派给 rc=%d，"
                               "站点实给 %s —— `SystemExit(带字符串)` 的退出码是 1，不是 %d"
                               % (lineno, next(k for k in FATAL_KEYS if k in txt), m,
                                  sorted(codes), m))
        for lineno, codes, txt, _ in self.sites:
            if codes is None:
                continue
            for m in sorted({int(x) for x in RC_TEXT_RE.findall(txt)}):
                if m not in codes:
                    bad.append("R3 站点自述码不符：L%d 文案自写 rc=%d，该站点实给 %s"
                               % (lineno, m, sorted(codes)))
        silent = sorted(c for c in self.impl if c >= 2 and c not in promised)
        return bad, silent, (bool(self.sites) and not promised), self.opaque, yielded


def analyze_source(rel, src, readme_entry):
    try:
        tree = ast.parse(src)
    except SyntaxError as e:
        return None, "SKIP(parse) %s: %s" % (rel, e)
    p_src, f_src, pr_src = promise_face(src)
    p_rd, f_rd, pr_rd = promise_face(readme_entry) if readme_entry else (set(), set(), [])
    pairs = list(pr_src) + [x for x in pr_rd if x not in pr_src]
    az = Analyzer(tree)
    bad, silent, undeclared, opaque, yielded = az.verdict(p_src | p_rd, f_src | f_rd, pairs)
    return {"rel": rel, "promised": p_src | p_rd, "fatal_codes": f_src | f_rd,
            "impl": az.impl, "bad": bad, "silent": silent, "undeclared": undeclared,
            "opaque": opaque, "yielded": yielded, "p_src": p_src, "p_rd": p_rd}, ""


# ---------------------------------------------------------------- 宇宙（现读跟踪面）

def tracked_scripts():
    p = subprocess.run(("git", "ls-files", "scripts"), cwd=ROOT,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if p.returncode != 0:
        raise RuntimeError("git ls-files scripts 失败（rc=%s）：%s"
                           % (p.returncode, p.stderr.decode("utf-8", "replace").strip()[:160]))
    files = [f.replace("\\", "/") for f in p.stdout.decode("utf-8", "replace").splitlines()
             if f.endswith(".py")]
    if not files:
        raise RuntimeError("跟踪面 scripts/**/*.py 一条都没枚举到 —— 判据看不见样本，拒绝报绿")
    return files


def census():
    if not os.path.isfile(README):
        raise RuntimeError("scripts/README.md 读不到 —— 承诺面的条目侧无从核对")
    readme = io.open(README, encoding="utf-8", errors="replace").read()
    rows, skipped = [], []
    for rel in tracked_scripts():
        path = os.path.join(ROOT, rel.replace("/", os.sep))
        try:
            src = io.open(path, encoding="utf-8", errors="replace").read()
        except OSError as e:
            raise RuntimeError("%s 读不到（%s）—— 判据无法自证" % (rel, e))
        r, note = analyze_source(rel, src, readme_slice(readme, rel.split("/")[-1]))
        if r is None:
            skipped.append(note)
            continue
        rows.append(r)
    if not rows:
        raise RuntimeError("解析后宇宙为空（全部 .py 都 SyntaxError？）—— 拒绝出读数")
    return rows, skipped


def show(rows, skipped):
    bad = [(r["rel"], b) for r in rows for b in r["bad"]]
    silent = [(r["rel"], c) for r in rows for c in r["silent"]]
    undecl = [r["rel"] for r in rows if r["undeclared"]]
    opaque = [(r["rel"], o) for r in rows for o in r["opaque"]]
    yielded = [(r["rel"], y) for r in rows for y in r["yielded"]]
    print("宇宙：%d 份 scripts/**.py（git 跟踪面，解析跳过 %d）｜有 `N=` 契约块的脚本：%d 份"
          % (len(rows), len(skipped), sum(1 for r in rows if r["promised"])))
    for note in skipped:
        print("  %s" % note)
    print()
    print("判定面（R1 模块面幻影 + R2 站点类指派 + R3 站点自述码）= %d 条" % len(bad))
    for rel, b in bad:
        print("  - %s：%s" % (rel, b))
    print()
    print("只报不判：%d 条（S 沉默出口 %d ｜ U 未认作契约 %d ｜ O 不透明/让位 %d）"
          % (len(silent) + len(undecl) + len(opaque) + len(yielded),
             len(silent), len(undecl), len(opaque) + len(yielded)))
    for rel, c in silent:
        print("  S - %s：实现面能给出 rc=%d，承诺面没写" % (rel, c))
    for rel in undecl:
        print("  U - %s：有出口站点但整份没有 `N=` 契约块" % rel)
    for rel, (lineno, unp, ext) in opaque:
        print("  O - %s：L%d 实参 `%s` 给不出确定的码%s"
              % (rel, lineno, unp, "（外部件 returncode 透传）" if ext else ""))
    for rel, y in yielded:
        print("  O - %s：%s" % (rel, y))
    return len(bad), len(silent) + len(undecl) + len(opaque) + len(yielded)


def verdict_rc(count, ceiling, extra=0):
    return 0 if count <= ceiling and not extra else 1


def hint(count, ceiling):
    if count < ceiling:
        return "提示：判定面已降到 %d 条（上限 %d）—— 可以把 CONTRACT_GAP_CEILING 收紧到 %d" \
               "（改常量是人的决定，本判据不自动改数）。" % (count, ceiling, count)
    if count > ceiling:
        return "FAIL：判定面 %d 条 > 棘轮上限 %d —— 新增的假契约必须当场修，不许放宽上限绕过。" % (count, ceiling)
    if ceiling == 0:
        return "判定面归零（上限 0）：BUG-369 立案那批存量已清完 ⇒ 没有容忍带，任何一条新假契约都必红。"
    return "判定面 %d 条 = 棘轮上限 %d（存量按声明接受、增量必须归零）。" % (count, ceiling)


# ---------------------------------------------------------------- 自检

FIX = {
    "clean": '"""退出码：0=PASS / 1=违例 / 2=判据无法自证（FATAL）。"""\n'
             'import sys\ndef fatal(m):\n    sys.stderr.write(m)\n    return 2\ndef main():\n'
             '    if 0:\n        return fatal("FATAL x")\n    return 0\nsys.exit(main())\n',
    "multiline": '"""\n退出码：0=活文档面全在 / 1=判定面未落地\n  （棘轮超限亦给 1）/ 2=判据无法自证（FATAL）\n"""\n'
                 'import sys\ndef main():\n    if 0:\n        return 2\n    return 0\nsys.exit(main())\n',
    "headless": '"""\n用法：\n  python scripts/x.py\n  0=PASS / 1=违例 / 2=判据无法自证（FATAL）\n"""\n'
                'raise SystemExit("FATAL x —— 判据空转，拒绝报绿")\n',
    "stringy": '"""退出码：0=PASS / 1=违例 / 2=判据无法自证（FATAL）。"""\n'
               'raise SystemExit("FATAL 读不到 —— 判据无法自证")\n',
    "percent": '"""退出码：0=PASS / 1=违例 / 2=判据无法自证（FATAL）。"""\n'
               'e = 1\nraise SystemExit("FATAL git 失败（%s）" % e)\nraise SystemExit(f"FATAL 空转 {e}")\n',
    "names": '"""退出码：0=PASS / 1=违例 / 2=判据无法自证。"""\n'
             'import sys\ndef main():\n    rc = 0\n    if 0:\n        rc = 2\n    return rc\nsys.exit(main())\n',
    "external": '"""退出码：0=PASS / 1=违例 / 2=前置不满足。"""\n'
                'import subprocess, sys\np = subprocess.run(["moon"])\nsys.exit(p.returncode)\n',
    "silent": '"""退出码：0=PASS / 1=违例。"""\nimport sys\ndef main():\n'
              '    if 0:\n        sys.exit(3)\n    return 0\nsys.exit(main())\n',
    "r3lie": '"""退出码：0=通过 / 1=仍红 / 2=前置不满足。"""\nimport sys\ndef main():\n'
             '    if 0:\n        return 2\n'
             '    raise SystemExit("FATAL PATH 上没有 moon —— 拒绝出结论（rc=2）")\n    return 0\nsys.exit(main())\n',
    "undeclared": 'import sys\ndef main():\n    return 0\nsys.exit(main())\n',
    "bool": '"""退出码：0=PASS / 1=违例 / 2=FATAL。"""\nimport sys\ndef main():\n'
            '    if 0:\n        return True\n    return 0\nsys.exit(main())\n',
}


def probe(key, readme=""):
    r, note = analyze_source("fixture.py", FIX[key], readme)
    if r is None:
        raise AssertionError(note)
    return r


def selftest():
    cells = []

    def cell(name, ok, detail=""):
        cells.append((name, bool(ok), detail))
        print("  %s  %s%s" % ("ok" if ok else "FAIL", name,
                              ("（%s）" % detail) if detail else ""))

    r = probe("multiline")
    cell("block-spans-two-lines", r["promised"] == {0, 1, 2} and not r["bad"],
         "承诺=%s 判定=%d 条；跨行块只吃行尾会把 2 漏掉、把 1 判成幻影"
         % (sorted(r["promised"]), len(r["bad"])))

    r = probe("headless")
    cell("headless-bare-pair-line-is-promise", 2 in r["promised"], "承诺=%s" % sorted(r["promised"]))
    cell("headless-phantom-caught-by-R1", any(b.startswith("R1") for b in r["bad"]), str(r["bad"]))

    r = probe("clean")
    cell("real-contract-no-false-positive", not r["bad"] and 2 in r["impl"],
         "实现面=%s" % sorted(r["impl"]))

    r = probe("stringy")
    hit = [b for b in r["bad"] if b.startswith("R2")]
    cell("stringy-fatal-gives-R2-with-construction",
         len(hit) == 1 and "指派给 rc=2" in hit[0] and "实给 [1]" in hit[0], str(r["bad"]))

    r = probe("percent")
    cell("percent-and-fstring-are-stringy", len([b for b in r["bad"] if b.startswith("R2")]) == 2,
         "两处串式站点各计一条 R2（合计判定 %d 条）" % len(r["bad"]))

    r = probe("names")
    cell("name-propagation-sees-return-2", 2 in r["impl"], "实现面=%s" % sorted(r["impl"]))

    r = probe("external")
    cell("external-returncode-yields-R1-but-leaves-a-trace",
         not [b for b in r["bad"] if b.startswith("R1")] and bool(r["yielded"] or r["opaque"]),
         "让位留名 %d 条" % (len(r["yielded"]) + len(r["opaque"])))

    r = probe("silent")
    cell("silent-exit-reported-not-judged", not r["bad"] and 3 in r["silent"], "S 面=%s" % r["silent"])

    r = probe("r3lie")
    cell("site-rc-text-lie-caught-by-R3-not-R1",
         any(b.startswith("R3") for b in r["bad"]) and not any(b.startswith("R1") for b in r["bad"]),
         str(r["bad"]))

    r = probe("undeclared")
    cell("no-contract-goes-to-U-face", not r["bad"] and r["undeclared"], "有站点、无契约块 ⇒ 只报不判")

    r = probe("bool")
    cell("bool-return-is-not-code-1", 1 not in r["impl"],
         "实现面=%s；`return True` 不该被当成码 1" % sorted(r["impl"]))

    r = probe("clean", readme="- `fixture.py`\n  退出码：0=PASS，1=违例，2=判据空转 FATAL\n")
    cell("readme-entry-side-promise-counts", 2 in r["p_rd"] and 2 in r["p_src"] and not r["bad"],
         "正文承诺=%s 条目承诺=%s" % (sorted(r["p_src"]), sorted(r["p_rd"])))

    # 已知盲区，上账不装看不见：README 的条目**现实形状是一整行**（`- \`x.py\` — …用法：…（0=PASS，1=违例，2=…）`），
    # 本判据的承诺面只认行首标题 ⇒ 条目行内的 `N=` 现在读不到。实测开启行内识别会把判定面从 16 抬到 39
    # （check_desc_enum_sync / cleanup_artifacts / award_demo / e2e_lock_xproc 等 10 份新面），
    # 未逐条核过真伪就开门 = 拿假红教人无视这把尺。下一轮先逐条核这 23 条，再决定开与不开。
    blind = probe("clean", readme="- `fixture.py` — 说明。**用法：`python scripts/fixture.py`"
                                 "（0=PASS，1=违例，2=判据空转 FATAL）**")
    cell("readme-inline-entry-is-a-declared-blind-face", not blind["p_rd"],
         "条目行内 `N=` 当前**不读**（开启后实测判定面 16→39，真伪未核 ⇒ 本轮不开）")

    sl = readme_slice("- `a.py` — 甲\n- `b.py` — 乙：见 `a.py` 的用法（0=PASS，1=违例，2=FATAL）\n- `c.py` — 丙\n",
                      "b.py")
    cell("readme-slice-stops-at-next-entry", sl.startswith("- `b.py`") and "c.py" not in sl,
         "切片=%r" % sl[:56])

    # 形状识别的锋利面（自咬实录：本判据曾在自家注释里被自己的例子判红，读数 16→17）：
    # 「举例」和「承诺」同形 ⇒ 注释里抄一个契约样子就会进承诺面。这里**上账不豁免**。
    sharp = probe("clean")
    quoted = ('"""doc"""\n# 退出码：0=PASS / 1=违例 / 9=本判据举的例子，不是承诺\n'
              'import sys\ndef main():\n    return 0\nsys.exit(main())\n')
    r_q, _ = analyze_source("prose.py", quoted, "")
    cell("prose-lookalike-enters-promise-face-by-design",
         9 in r_q["promised"] and any(b.startswith("R1") for b in r_q["bad"]) and not sharp["bad"],
         "注释里的例子被当真承诺读进来（R1 追一条）—— 已知代价，靠改写文本消，不开豁免面")

    n = len(probe("stringy")["bad"]) + len(probe("headless")["bad"])
    cell("ratchet-over-ceiling-is-red",
<<<<<<< HEAD
         verdict_rc(CONTRACT_GAP_CEILING + 1, CONTRACT_GAP_CEILING) == 1 and
         verdict_rc(n, CONTRACT_GAP_CEILING) == 0,
         "合成 %d 条在上限内=0；上限+1 必=1" % n)
    cell("tightening-is-a-suggestion-not-a-verdict",
         "收紧" in hint(3, CONTRACT_GAP_CEILING) and "FAIL" not in hint(3, CONTRACT_GAP_CEILING),
         "读数低于上限只给建议，不判红也不判绿")
=======
         verdict_rc(at, at) == 0 and verdict_rc(at + 1, at) == 1 and verdict_rc(0, at) == 0,
         "三点判法：等于上限给 0 / 上限+1 给 1 / 零条给 0（三点都由常量导出，上限怎么降都不失配）")
    below = at - 1
    if below >= 0:
        cell("tightening-is-a-suggestion-not-a-verdict",
             "收紧" in hint(below, at) and "FAIL" not in hint(below, at) and verdict_rc(below, at) == 0,
             "上限-%d 那一档只给建议：含「收紧」、不含 FAIL、rc=0（收紧是人的决定，判据不自动改数）" % below)
    else:
        # 上限降到 0 之后「低于上限」这一档不存在了，格子改为钉「等于 0 时的读法」而不是留一支必红的旧期望。
        cell("tightening-not-applicable-at-zero-ceiling",
             "收紧" not in hint(0, 0) and "FAIL" not in hint(0, 0) and verdict_rc(0, 0) == 0
             and verdict_rc(1, 0) == 1,
             "上限已归零：hint(0,0) 不该再提收紧，且任何一条新增假契约都得红")
>>>>>>> 57f24264 (fix: simulate_head_commit 的 4 处 FATAL 出口真给 rc=2，退出码棘轮 1→0（BUG-369 / T0r26）)

    rows, skipped = census()
    total = sum(len(r["bad"]) for r in rows)
    cell("ceiling-matches-live-reading", total == CONTRACT_GAP_CEILING,
         "现算判定面 %d 条 vs 上限常量 %d —— 不等即判据或被测面动过，必须重数并核对"
         % (total, CONTRACT_GAP_CEILING))

    by = {r["rel"]: r for r in rows}
    calib = (
        ("check_plan_landing.py", lambda r: not r["bad"], "R1/R2/R3 全 0（emit_fatal 真给 2，是契约不是幻影）"),
<<<<<<< HEAD
        ("check_mbti_sync.py", lambda r: any(b.startswith("R1") for b in r["bad"])
            and len([b for b in r["bad"] if b.startswith("R2")]) >= 6,
            "R1 一条 + R2 ≥6（BUG-369 记 7 处串式 FATAL）"),
        ("check_pkg_imports.py", lambda r: any(b.startswith("R1") for b in r["bad"])
            and len([b for b in r["bad"] if b.startswith("R2")]) >= 5,
            "R1 一条 + R2 ≥5（记 6 处串式，v2 普查只读出 4 处）"),
        ("simulate_head_commit.py", lambda r: any(b.startswith("R3") for b in r["bad"])
            and not any(b.startswith("R1") for b in r["bad"]), "R1=0（别处真给 2）但 R3 一条 —— 半形"),
=======
        ("check_mbti_sync.py", lambda r: not r["bad"],
         "R43 已修（7 处串式 FATAL 改 emit_fatal）⇒ 必须归零；再被判红就是尺子或被测面回退了"),
        ("check_pkg_imports.py", lambda r: not r["bad"],
         "R44 已修（6 处串式 FATAL 改 emit_fatal）⇒ 必须归零；再被判红就是尺子或被测面回退了"),
        ("simulate_head_commit.py", lambda r: not r["bad"],
         "R45 已修（4 处串式 FATAL 改 emit_fatal，那条自写「（rc=2）」的文案从此说实话）⇒ 必须归零；"
         "再被 R3 判红就是尺子回退了"),
>>>>>>> 57f24264 (fix: simulate_head_commit 的 4 处 FATAL 出口真给 rc=2，退出码棘轮 1→0（BUG-369 / T0r26）)
        ("check_template_ctrl.py", lambda r: not r["bad"], "R42 已修 ⇒ 必须归零（修过的尺不许再被判红）"),
    )
    for base, want, why in calib:
        r = by.get("scripts/" + base)
        cell("calib:%s" % base, r is not None and want(r),
             why if r is not None else "不在宇宙里")

<<<<<<< HEAD
=======
    # 降档的承重力问的是「2 从哪来」，不是「判定面小没小」：R43 的 M3 变异实测过一条反差
    # （把 emit_fatal 改回 return 1，第 8 条不在判定面、搬进 O 面留名）。修过的尺一起考实现面。
    fixed = ("check_plan_landing.py", "check_template_ctrl.py", "check_mbti_sync.py",
             "check_pkg_imports.py", "simulate_head_commit.py")
    no_two = [b for b in fixed if not (by.get("scripts/" + b) or {}).get("impl")
              or 2 not in by["scripts/" + b]["impl"]]
    cell("fixed-ruler-gives-two-in-impl-face", not no_two,
         "%d 把修过的尺的 ast 实现面都得真含 2；缺的是 %s —— 判定面归零但实现面给不出 2 ⇒ 那是让位不是修好"
         % (len(fixed), ", ".join(no_two) or "无"))

>>>>>>> 57f24264 (fix: simulate_head_commit 的 4 处 FATAL 出口真给 rc=2，退出码棘轮 1→0（BUG-369 / T0r26）)
    cell("own-fatal-exit-is-2", emit_fatal("（自检探针，非违例）") == 2,
         "emit_fatal 恒返 2 —— 本判据不用被抓者的缺陷给自己开门")

    import tempfile
    d = tempfile.mkdtemp(prefix="ecc-")
    try:
        env = dict(os.environ, GIT_DIR=os.path.join(d, "not-a-repo.git"), PYTHONIOENCODING="utf-8")
        p = subprocess.run((sys.executable, os.path.join(ROOT, "scripts", "check_exit_code_contract.py")),
                           cwd=d, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        cell("empty-universe-fatal-rc-2", p.returncode == 2,
             "子进程 rc=%s；stderr=%s" % (p.returncode,
                                        p.stderr.decode("utf-8", "replace").strip()[-90:]))
    finally:
        import shutil
        shutil.rmtree(d, ignore_errors=True)

    fails = [(nm, w) for nm, ok, w in cells if not ok]
    if fails:
        print("SELFTEST FAIL（%d/%d）：" % (len(fails), len(cells)))
        for nm, w in fails:
            print("  - %s：%s" % (nm, w))
        return emit_fatal("判据自检不通过 —— 尺子坏了，先修判据再读读数")
    print("SELFTEST OK（%d 格：承诺面与条目切片 6｜实现面 4｜判定 R1/R2/R3 各 1｜只报不判与让位 3｜"
          "棘轮 2｜标注集校准 5｜自指 3）" % len(cells))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--all-faces", action="store_true",
                    help="把只报不判的 S/U/O 三面也计入退出码（现状必红，诊断用）")
    ap.add_argument("--show-ceiling", action="store_true", help="只打印上限与当前判定面读数")
    args = ap.parse_args()
    if args.selftest:
        return selftest()

    try:
        rows, skipped = census()
    except RuntimeError as e:
        return emit_fatal("FATAL %s —— 判据无法自证，拒绝出读数" % e)
    except OSError as e:
        return emit_fatal("FATAL 读不到样本（%s）—— 拒绝出读数" % e)

    n_bad, n_report = show(rows, skipped)
    if args.show_ceiling:
        print("CONTRACT_GAP_CEILING=%d  当前判定面=%d 条  只报不判=%d 条"
              % (CONTRACT_GAP_CEILING, n_bad, n_report))
        return 0
    print()
    print(hint(n_bad, CONTRACT_GAP_CEILING))
    print("注：判定面每一条都是「自述与实现不同色」，出路只有两条 —— 把码改真，或把承诺改真；"
          "改上限常量绕过不算出路（放宽是人的决定，本判据不自动改数）。")
    if args.all_faces and n_report:
        print("--all-faces：只报不判的 %d 条本次计入退出码 ⇒ 1（默认口径下不影响红绿）。" % n_report)
        return 1
    return verdict_rc(n_bad, CONTRACT_GAP_CEILING)


if __name__ == "__main__":
    sys.exit(main())
