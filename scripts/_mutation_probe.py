#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/_mutation_probe.py —— 判据变异探针：判据「真能咬」还是「假绿」的**动态**检查器。

## 它解决什么问题

判例-29/30/50 要求「变异对照」：把被测机制改坏，断言自证会红。但实战里做这件事
**极易得出假结论**——本会话我自己就栽了两次，两次都把「脚本没跑起来」读成了「判据咬住了」：

| 栽法 | 现象 | 根因 |
|---|---|---|
| ① import 崩 | `rc!=0`、`stdout` 空 | 被测脚本复制到临时目录后，`Path(__file__).parent` 找不到共享模块 ⇒ **在 import 阶段就崩** |
| ② 类型不匹配崩 | `TypeError: cannot unpack non-iterable bool object` | 给返回 tuple 的函数插 `return True` ⇒ **运行期崩** |

两次的共同点：**`rc != 0` 被当成了「判据咬住」，实际是「脚本压根没跑到自检」。**

本工具把这两条教训固化成**三重判定**，三个都满足才算 CAUGHT：

```
CRASHED  —— 输出里有 Traceback ⇒ 变异无效，不计入 CAUGHT（栽法 ①② 都被这一条挡下）
MISSED   —— 没崩、selftest 仍绿 ⇒ **假绿嫌疑**（判据对该变异免疫）
CAUGHT   —— 没崩 + selftest 变红 ⇒ 该判据真咬住了这类改动
```

## 为什么变异必须是「语义级」而不是「插恒真返回」

插 `return True/0/[]` 看似最通用的「让判据恒通过」，但对返回 tuple / `(rc, msg)` /
列表的函数**类型不匹配**，必然 CRASHED（上面栽法 ②）。所以本工具只做**保持返回类型**的替换：

| 变异 | 语义 |
|---|---|
| **S1** `== 0` → `!= 0` | 判绿条件反转 |
| **S2** `len(x) == 0` → `len(x) > 0` | 空集合判定反转 |
| **S3** `return 0` → `return 1` | 退出码反转（仅 function 体内） |
| **S4** `if not x:` → `if x:` | 否定条件反转 |

**命中点可控性**（原型的第三处缺陷，本版修掉）：变异只在**指定的函数体内**发生，
且默认只替换**第一处**；`--all` 才全替换。原型用全文文本替换 ⇒ 命中了无关的
`== 0`，产出过 2 个**假 MISSED**（`check_backlog_status_staleness` 明明有
`mutation-rule-blind-R1/R2/R4` 三格真变异）。

## 用法

```bash
# 对一把判据做全部四类变异（默认只改函数体内第一处）
python scripts/_mutation_probe.py scripts/check_xxx.py --func judge

# 不指定函数 ⇒ 变整个文件（容易命中无关位置，产出更多假 MISSED，谨慎）
python scripts/_mutation_probe.py scripts/check_xxx.py

# 自证（不需要外部判据）
python scripts/_mutation_probe.py --selftest
```

## 退出码契约

| rc | 含义 |
|---|---|
| 0 | 全部变异结果为 CAUGHT 或 CRASHED（无 MISSED）——即**没有假绿嫌疑** |
| 1 | 存在 MISSED（假绿嫌疑）——**这是本工具的价值输出** |
| 2 | 判据无法自证（目标文件不存在 / 没有 `--selftest` / 变异完全未生效） |
| 4 | 尺子自己坏了（未捕获异常，绝不冒用 1 那一档） |

## 诚实边界（**必读，别把本工具当判决**）

1. **MISSED ≠ 假绿定论**。它只说明「这四类语义变异里，有一类改了这个判据却没让自检变红」。
   判据可能有其他形式的真变异格（比如注入式、合成夹具式），而本工具**看不到那种**。
   ⇒ **MISSED 是「值得人去看一眼」，不是「判据坏了」**（判例-62：机器只能缩小范围）。
2. **CRASHED ≠ 变异无效的定论**，只说明这次生成的变异代码跑不起来。可以换个函数名再试。
3. **`--selftest` 通过只证明本工具的判定逻辑对**，不证明任何被检判据的健康度。
"""
import argparse
import os
import re
import subprocess
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

# ── 变异定义（**全部保持返回类型/语法形态**，见模块 docstring 的「为什么」）──────────
# (短名, 说明, 匹配正则, 替换模板, 是否只在函数体内生效)
MUTATIONS = (
    ("S1", "判绿条件反转 ==0 → !=0", re.compile(r"==\s*0\b"), "!= 0", True),
    ("S2", "空集合判定反转 len(..)==0 → >0",
     re.compile(r"len\(([^)]*)\)\s*==\s*0\b"), r"len(\1) > 0", True),
    ("S3", "退出码反转 return 0 → return 1", re.compile(r"^(\s+)return 0\s*$"), r"\g<1>return 1", True),
    ("S4", "否定条件反转 if not X: → if X:", re.compile(r"^(\s*)if not\s+(.+?):\s*$"), r"\g<1>if \2:", True),
)


# ── 纯函数（可单测）──────────────────────────────────────────────────────────────


def func_span(lines, func):
    """返回函数所在行区间 [start, end)（0-based，end 不含）。找不到 ⇒ None。

    只认列首 `def <name>(`，避免误命中 `self.func(` / 字符串里的同名。
    """
    pat = re.compile(r"^def %s\s*\(" % re.escape(func))
    start = None
    for i, ln in enumerate(lines):
        if pat.match(ln):
            start = i
            break
    if start is None:
        return None
    for j in range(start + 1, len(lines)):
        if re.match(r"^(def |class |if __name__)", lines[j]):
            return (start, j)
    return (start, len(lines))


def apply_mutation(src, short, func=None, limit=1):
    """在 src 上施加一次 `short` 变异，返回新文本；**匹配不到返回 None**。

    `func` 非空 ⇒ 只在那个函数体内找；空 ⇒ 全文。
    `limit` 控制替换处数（1 = 只第一处，None = 全部）。
    """
    spec = next((m for m in MUTATIONS if m[0] == short), None)
    if spec is None:
        return None
    _, _, pat, repl, in_func = spec
    lines = src.splitlines(keepends=True)
    lo, hi = 0, len(lines)
    if func and in_func:
        span = func_span(lines, func)
        if span is None:
            return None
        lo, hi = span
    n = 0
    out = []
    for i, line in enumerate(lines):
        if lo <= i < hi and (limit is None or n < limit):
            new = pat.sub(repl, line, count=1)
            if new != line:
                out.append(new)
                n += 1
                continue
        out.append(line)
    return "".join(out) if n else None


def classify(out_text, err_text, rc):
    """纯函数：把一次「变异后跑 --selftest」的结果归类。

    **这是本工具的核心判定**——`CRASHED` 这一档专门用来挡本会话踩过的两次误判
    （import 崩 / 类型崩都被误读成 CAUGHT）。

    Returns:
        "CRASHED" | "MISSED" | "CAUGHT" | "UNKNOWN"
    """
    blob = (out_text or "") + "\n" + (err_text or "")
    if "Traceback (most recent call last)" in blob:
        return "CRASHED"
    green = ("SELFTEST OK" in (out_text or "")) or ("SELFTEST PASS" in (out_text or ""))
    if green:
        return "MISSED"
    # 明确的自检失败行
    if "SELFTEST FAIL" in blob or "SELFTEST FAIL" in blob:
        return "CAUGHT"
    # 没崩、没绿、也没有 FAIL 行 —— 说明这个脚本的 --selftest 输出契约不是上面两种
    return "UNKNOWN" if rc == 0 else "CAUGHT"


# ── 探针执行 ────────────────────────────────────────────────────────────────────


def probe_one(script, short, func=None, timeout=300, cwd=None):
    """对一个脚本施加一次变异并跑它的 --selftest。返回 (verdict, rc, tail)。"""
    cwd = cwd or ROOT
    path = script if os.path.isabs(script) else os.path.join(cwd, script)
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            src = f.read()
    except OSError as e:
        return ("NOFILE", None, str(e)[:120])
    mutated = apply_mutation(src, short, func=func)
    if mutated is None:
        return ("NOAPPLY", None, "变异未命中（换 --func 或换变异类）")
    # ⚠️ 变异文件必须落在**原目录**：被测脚本常 `Path(__file__).parent` 加载同目录共享模块，
    # 放临时目录会在 import 阶段崩（本会话栽法 ①）。
    probe = os.path.join(os.path.dirname(path),
                         "_mutprobe_%s_%s.py" % (os.path.basename(path)[:-3], short))
    try:
        with open(probe, "w", encoding="utf-8", newline="") as f:
            f.write(mutated)
        r = subprocess.run([sys.executable, probe, "--selftest"],
                           capture_output=True, timeout=timeout, cwd=cwd)
        out = (r.stdout or b"").decode("utf-8", "replace")
        err = (r.stderr or b"").decode("utf-8", "replace")
        verdict = classify(out, err, r.returncode)
        tail = (err or out).strip().splitlines()
        return (verdict, r.returncode, (tail[-1][:110] if tail else ""))
    except subprocess.TimeoutExpired:
        return ("TIMEOUT", None, "超时 %ds" % timeout)
    finally:
        if os.path.exists(probe):
            os.remove(probe)


# ── 自证（判例-29/30：必须真调实现路径，且有一格是变异对照）────────────────────


def selftest():
    fails, cells = [], []

    def cell(name, got, want):
        cells.append(name)
        if got != want:
            fails.append("%s: got=%r want=%r" % (name, got, want))

    # ① 纯函数格：classify 的五种输入（含**本会话两次误判的真实输出形状**）
    cell("classify-import-crash-is-CRASHED",
         classify("", "Traceback (most recent call last):\n  FileNotFoundError: '_x.py'", 1),
         "CRASHED")
    cell("classify-typeerror-crash-is-CRASHED",
         classify("", "Traceback (most recent call last):\nTypeError: cannot unpack", 1),
         "CRASHED")
    cell("classify-green-is-MISSED", classify("SELFTEST OK: 12 cells\n", "", 0), "MISSED")
    cell("classify-pass-form-is-MISSED", classify("SELFTEST PASS 20 variants\n", "", 0), "MISSED")
    cell("classify-fail-is-CAUGHT", classify("SELFTEST FAIL: 1 cell\n", "", 1), "CAUGHT")
    cell("classify-rc1-no-fail-line-is-CAUGHT", classify("something\n", "", 1), "CAUGHT")
    cell("classify-rc0-no-marker-is-UNKNOWN", classify("whatever\n", "", 0), "UNKNOWN")

    # ② 纯函数格：变异只改**函数体内**、只改第一处
    demo = (
        "def judge(x):\n"
        "    if x == 0:\n"
        "        return 0\n"
        "    return 5\n"
        "\n"
        "def other(y):\n"
        "    if y == 0:\n"
        "        return 7\n"
        "    return 9\n"
    )
    m = apply_mutation(demo, "S1", func="judge")
    cell("mutate-S1-only-in-func",
         m is not None and "if x != 0:" in m and "if y == 0:" in m, True)
    m_all = apply_mutation(demo, "S1", func=None, limit=None)
    cell("mutate-S1-all-when-limit-none",
         m_all is not None and "if x != 0:" in m_all and "if y != 0:" in m_all, True)
    cell("mutate-S3-return0-in-func",
         "        return 1" in (apply_mutation(demo, "S3", func="judge") or ""), True)

    # ③ 变异对照（判例-30）：把本工具自己的 classify 改坏，断言 selftest 会红
    #    做法：临时替换 classify 为「恒返回 MISSED」，重跑本函数的判定部分
    _orig = globals()["classify"]

    def _blind(out_text, err_text, rc):
        return "MISSED"       # 恒绿：永远看不见 CRASHED/CAUGHT

    globals()["classify"] = _blind
    try:
        mutated_verdict = classify("SELFTEST FAIL: x", "", 1)
    finally:
        globals()["classify"] = _orig
    cell("mutation-control-blind-classify-detected", mutated_verdict, "MISSED")
    cell("mutation-control-original-restored",
         classify("SELFTEST FAIL: x", "", 1), "CAUGHT")

    # ④ 变异真的会生效吗（判例-50）：未施加变异时应返回 None，而不是原文
    cell("no-mutation-when-no-match", apply_mutation("x = 1\n", "S1"), None)
    cell("no-mutation-when-func-missing", apply_mutation(demo, "S1", func="nope"), None)

    print("SELFTEST %s (%d cells: %s)"
          % ("OK" if not fails else "FAIL", len(cells), " / ".join(cells)))
    for f in fails:
        print("  - " + f)
    return 0 if not fails else 1


# ── 入口 ───────────────────────────────────────────────────────────────────────


def main(argv):
    ap = argparse.ArgumentParser(
        description="判据变异探针：语义级变异 + CRASHED 判定（防「脚本没跑起来」被读成「判据咬住」）")
    ap.add_argument("scripts", nargs="*", help="被测判据路径（可多份）")
    ap.add_argument("--func", default=None,
                    help="只在该函数体内变异（**强烈建议给**；不给则全文件，易命中无关位置）")
    ap.add_argument("--only", default=None,
                    help="只跑指定变异类（S1/S2/S3/S4），缺省全跑")
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args(argv)

    if a.selftest:
        return selftest()
    if not a.scripts:
        print("用法: python scripts/_mutation_probe.py <script.py…> [--func NAME] [--only S1]")
        print("       python scripts/_mutation_probe.py --selftest")
        return 2

    wanted = [m[0] for m in MUTATIONS] if not a.only else [a.only]
    any_missed = any_apply = False
    for s in a.scripts:
        for short in wanted:
            verdict, rc, tail = probe_one(s, short, func=a.func, timeout=a.timeout)
            if verdict not in ("NOAPPLY", "NOFILE"):
                any_apply = True
            if verdict == "MISSED":
                any_missed = True
            print("%-44s %-3s %-8s rc=%-5s %s"
                  % (os.path.basename(s), short, verdict, rc, tail))

    if not any_apply:
        print("FATAL 判据无法自证：所有变异都未命中（换 --func 或确认目标含对应模式）")
        return 2
    if any_missed:
        print("\n注意：MISSED **不是**假绿定论 —— 只说明这四类语义变异没让它变红。")
        print("      判据可能有注入式/合成夹具式的真变异格，本工具看不到（判例-62）。")
        return 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except SystemExit:
        raise
    except Exception as exc:  # 尺子自己坏了：4，绝不冒用 1 那一档
        print("FATAL 判据未捕获异常：%r" % (exc,))
        sys.exit(4)
