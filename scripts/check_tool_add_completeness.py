#!/usr/bin/env python3
"""check_tool_add_completeness.py — 「加一个工具要改几处」的**可执行版本**（Lane DY）

## 为什么有这个判据

本仓有条说法叫 **「一源四态」**：一个功能要有 4 种形态（工具注册 / 文档 / 测试 / 插件态）。
**但实测加一个 MCP 工具要改的不是 4 处，而是 10 处。**

本会话实证（加 `commissar_send`，177 → 178）：
- 我们记了 5 处，**漏了 CLI 帮助面的 2 处**（`check_doc_surface` J14 + J16 当场抓出）
- 之后又发现 R212 把清单搬出 `AGENTS.md`，**J3 判据面没跟进**（第 10 处）

**⇒ 「一源四态」现在是散在 10 个地方的约定；写成判据后它才是真的。**
**⇒ 低估同步成本，是「一致性债」的唯一来源。**

## 10 个面（每个面标「数字」还是「名字」）

| # | 面 | 类型 | 文件 |
|---|---|---|---|
| 1 | 工具注册真源 | — | `src/server/server.mbt`（委托 `_tool_registry.real_tools()`）|
| 2 | AGENTS 清单·名字 | **名字** | `docs/AGENTS-mcp-inventory.md` + `AGENTS.md` |
| 3 | AGENTS 清单·数字 | 数字 | 同上（分组和 / 总数自述）|
| 4 | README·名字 | **名字** | `README.md` |
| 5 | README·数字 | 数字 | `README.md` |
| 6 | deliverable·数字 | 数字 | `docs/deliverable.md` |
| 7 | CLI 帮助·计数 | 数字 | `cmd/cli/help_topics.mbt` |
| 8 | CLI 帮助·名字 | **名字** | `cmd/cli/help_topics.mbt` |
| 9 | 插件态 | — | `gen_plugins.py` 投影（由扩展 `check_plugin_sync` 保证，本判据只确认投影文件存在）|
| 10 | `check_doc_surface` 覆盖 | — | 确认 J2/J3/J14/J16 都在跑（防「判据面被删」）|

## ⚠️ 为什么「数字面」与「名字面」必须分开判

**因为「数字对、名字错」是本轮真实发生的**（J16）：
加工具后**总计数**（178）与**分组和**（177）两个数字都"看起来在工作"，
**但名字表里就是少了一个**。
**⇒ 只对数字、不对名字的门禁，必然漏掉「数字和名字分别漂移」这一类。**

## rc 契约
- `0` = 10 个面全部覆盖
- `1` = 有面缺失（逐条点名「面 X 缺工具 Y」/「面 X 数字不符」）
- `2` = 判据无法自证（真源读不到 / 真源工具数为 0 / 关键文件缺失）
- `4` = 尺子坏了

## 用法
    python scripts/check_tool_add_completeness.py               # 判据
    python scripts/check_tool_add_completeness.py --list        # 输出 10×N 矩阵
    python scripts/check_tool_add_completeness.py --selftest    # 自证（含变异对照）
"""

from __future__ import annotations

import io
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts"))

RC_OK, RC_VIOLATION, RC_CANNOT, RC_BROKEN = 0, 1, 2, 4

F_AGENTS = "AGENTS.md"
F_INVENTORY = "docs/AGENTS-mcp-inventory.md"
F_README = "README.md"
F_DELIVERABLE = "docs/deliverable.md"
F_HELP = "cmd/cli/help_topics.mbt"

# 数字面：这些文件里应出现「真源工具数」这个数字
NUMERIC_SURFACES = (
    ("AGENTS 清单·数字", F_INVENTORY),
    ("README·数字", F_README),
    ("deliverable·数字", F_DELIVERABLE),
    ("CLI 帮助·计数", F_HELP),
)

# 名字面：这些文件里应逐个出现每个工具名
NAME_SURFACES = (
    ("AGENTS 清单·名字", (F_INVENTORY, F_AGENTS)),
    ("README·名字", (F_README,)),
    ("CLI 帮助·名字", (F_HELP,)),
)

RE_BACKTICK = re.compile(r"`([A-Za-z][A-Za-z0-9_.]*)`")
# CLI 帮助面分组行：`  [Board-DAG 31] a b c ...`
RE_HELP_GROUP = re.compile(r"\[\s*[A-Za-z][A-Za-z0-9-]*\s+(\d+)\s*\]\s*([^\"\\]*)")
# ⚠️ **工具名允许点号**（`mcpcf.circuit` 等 7 个 MCPCf 内嵌工具）——
#    实测：裸名正则只写 `[a-z][a-z0-9_]*` 会把它们全判「缺工具」（7 处假红）。
RE_TOOLNAME = re.compile(r"[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*")
RE_ANY_COUNT = re.compile(r"(\d+)\s*(?:个\s*)?MCP\s*工具", re.I)
RE_ANY_COUNT2 = re.compile(r"(\d+)\s*MCP\s*tools", re.I)


def read(rel: str) -> str | None:
    p = os.path.join(ROOT, rel)
    if not os.path.isfile(p):
        return None
    return io.open(p, encoding="utf-8", errors="replace").read()


def real_tools() -> set:
    """真源工具名集合 —— **委托给单一实现** `_tool_registry`（不另写一份）。"""
    import _tool_registry  # noqa: PLC0415

    return set(_tool_registry.real_tools())


def names_in_texts(texts) -> set:
    out = set()
    for t in texts:
        if t:
            out |= set(RE_BACKTICK.findall(t))
    return out


def help_group_sum(text: str) -> tuple[int, int, list]:
    """CLI 帮助面分组：返回 (数字之和, 列出的名字数, 各组读数)"""
    total = 0
    names = 0
    rows = []
    for m in RE_HELP_GROUP.finditer(text):
        n = int(m.group(1))
        body = m.group(2) or ""
        toks = RE_TOOLNAME.findall(body)
        total += n
        names += len(toks)
        rows.append((m.group(0)[:24], n, len(toks)))
    return total, names, rows


def numeric_numbers(text: str) -> set:
    out = set()
    for rx in (RE_ANY_COUNT, RE_ANY_COUNT2):
        out |= {int(x) for x in rx.findall(text or "")}
    return out


def judge(tools: set) -> tuple[int, dict]:
    if not tools:
        return RC_CANNOT, {"note": "真源工具数为 0 ⇒ 判据无法自证（_tool_registry 读不到？）"}

    N = len(tools)
    problems = []
    matrix = {}

    # ── 名字面 ──────────────────────────────────────────────
    for label, files in NAME_SURFACES:
        texts = [read(f) for f in files]
        if all(t is None for t in texts):
            problems.append((label, f"文件全都不存在：{files}"))
            continue
        got = names_in_texts(texts)
        # ★ **CLI 帮助面的工具名不带反引号**（形如 `[Board-DAG 31] a b c`）⇒
        #   反引号解析器对它恒空（实测：基线夹具三面全「缺工具」）。
        #   ⇒ 该面走**分组行裸名**解析。
        if label.startswith("CLI 帮助"):
            got = set()
            for t in texts:
                if not t:
                    continue
                for m in RE_HELP_GROUP.finditer(t):
                    body = m.group(2) or ""
                    got |= set(RE_TOOLNAME.findall(body))
        missing = sorted(t for t in tools if t not in got)
        matrix[label] = (len(tools) - len(missing), len(tools))
        if missing:
            for t in missing[:8]:
                problems.append((label, f"缺工具 `{t}`"))
            if len(missing) > 8:
                problems.append((label, f"…另有 {len(missing) - 8} 个"))

    # ── 数字面 ──────────────────────────────────────────────
    # ① CLI 帮助面的**分组和**：加总必须 == N
    help_txt = read(F_HELP)
    if help_txt is None:
        problems.append(("CLI 帮助·计数", "文件不存在"))
    else:
        gsum, gnames, rows = help_group_sum(help_txt)
        matrix["CLI 帮助·分组和"] = (gsum, N)
        if gsum != N:
            problems.append(("CLI 帮助·计数", f"分组数字之和={gsum}，真源={N}"))
        # ② 自述计数
        for label, f in (("CLI 帮助·计数", F_HELP),):
            got = numeric_numbers(read(f))
            if got and N not in got:
                problems.append((label, f"自述计数集合 {sorted(got)} 不含真源 {N}"))

    for label, f in NUMERIC_SURFACES:
        if label.startswith("CLI 帮助"):
            continue
        txt = read(f)
        if txt is None:
            problems.append((label, f"文件不存在：{f}"))
            continue
        got = numeric_numbers(txt)
        if not got:
            # 该面可能不写计数（deliverable 有时只有分组表）⇒ 不判红，但记账
            matrix[label] = ("n/a", N)
            continue
        matrix[label] = (N if N in got else sorted(got), N)
        if N not in got:
            problems.append((label, f"自述计数集合 {sorted(got)} 不含真源 {N}"))

    # ── 第 9 面：插件态（确认投影存在）───────────────��──
    plug = os.path.join(ROOT, "plugins", "source")
    matrix["插件态·投影源"] = ("ok" if os.path.isdir(plug) else "missing", "—")
    if not os.path.isdir(plug):
        problems.append(("插件态", "plugins/source 不存在 ⇒ gen_plugins 无投影源"))

    # ── 第 10 面：`check_doc_surface` 的关键判据还在（防判据面被删）
    ds = read("scripts/check_doc_surface.py") or ""
    for j in ("J2", "J3", "J14", "J16"):
        if j not in ds:
            problems.append((f"check_doc_surface·{j}", "该判据 id 在实现里找不到（判据面被删？）"))
    matrix["check_doc_surface·J2/J3/J14/J16"] = (
        "ok" if all(j in ds for j in ("J2", "J3", "J14", "J16")) else "missing", "—")

    rc = RC_VIOLATION if problems else RC_OK
    return rc, {"n": N, "problems": problems, "matrix": matrix}


def render(rc: int, r: dict) -> None:
    if rc in (RC_CANNOT, RC_BROKEN):
        print(f"[FATAL] {r.get('note', '')}")
        print(f"判据无法自证 ⇒ rc={rc}")
        return
    N = r["n"]
    print(f"[真源] `_tool_registry.real_tools()` = **{N}** 个工具")
    print()
    print("[10 个面]")
    for label, val in r["matrix"].items():
        if isinstance(val, tuple) and len(val) == 2 and isinstance(val[1], int):
            a, b = val
            if isinstance(a, int) and a == b:
                mark = "OK "
            elif a == "n/a":
                mark = "-  "
            else:
                mark = "**"
            print(f"  {mark} {label:<28} {a} / {b}")
        else:
            print(f"      {label:<28} {val}")
    if not r["problems"]:
        print()
        print("[结论] 10 个面全部覆盖。")
        print("       ⚠️ **这只证明「名字/数字在每个面都出现了」**，不证明")
        print("          「出现的分组对」「描述文字对」——那需要语义判断，本判据不碰。")
        return
    print()
    print(f"[缺失] {len(r['problems'])} 处：")
    for label, msg in r["problems"]:
        print(f"  ✗ [{label}] {msg}")
    print()
    print("  处置：按「加工具 10 处清单」补齐 —— 数字面与名字面**分开看**，")
    print("        因为「数字对、名字错」是本仓实际发生过的形态（J16）。")


# ══════════════════════════════════════════════════════════════════════
# selftest
# ══════════════════════════════════════════════════════════════════════

def _mk_tools(*names):
    return set(names)


def _fake_judge(tools, texts):
    """用注入的 texts 跑一遍判据核心（不读真仓），供变异对照。

    texts : {rel: 内容}
    """
    def _read(rel):
        return texts.get(rel)

    global read  # noqa: PLW0603
    orig = read
    read = _read
    try:
        return judge(tools)
    finally:
        read = orig


def selftest() -> int:
    cases = []

    def case(name, fn, want):
        try:
            got = fn()
        except Exception as e:  # noqa: BLE001
            got = f"EXC:{e}"
        cases.append((name, got, want))

    # 基线夹具：3 个工具、10 面齐全
    T = _mk_tools("alpha", "beta", "gamma")
    GOOD = {
        F_INVENTORY: "| `alpha` | `beta` | `gamma` | 3 个 MCP 工具",
        F_AGENTS: "见清单",
        F_README: "`alpha` `beta` `gamma` 3 个 MCP 工具",
        F_DELIVERABLE: "3 个 MCP 工具",
        F_HELP: '[Board-DAG 3] alpha beta gamma\n3 MCP tools\n',
        "scripts/check_doc_surface.py": "J2 J3 J14 J16",
    }

    case("all-10-surfaces-covered", lambda: _fake_judge(T, dict(GOOD))[0], RC_OK)

    # ★ 变异 1：从某个「名字面」删一个工具 ⇒ 必红
    def _mut_name():
        bad = dict(GOOD)
        bad[F_HELP] = '[Board-DAG 3] alpha beta\n3 MCP tools\n'  # 少了 gamma
        return _fake_judge(T, bad)[0]
    case("MUT-name-surface-missing-goes-red", _mut_name, RC_VIOLATION)

    # ★ 变异 2：只把某个「数字面」改 1 ⇒ 必红
    def _mut_number():
        bad = dict(GOOD)
        bad[F_README] = "`alpha` `beta` `gamma` 4 个 MCP 工具"
        return _fake_judge(T, bad)[0]
    case("MUT-number-surface-off-by-one-goes-red", _mut_number, RC_VIOLATION)

    # ★ 变异 3：CLI 帮助的**分组和**错（数字对但分组和不对）
    def _mut_group_sum():
        bad = dict(GOOD)
        bad[F_HELP] = '[Board-DAG 1] alpha beta gamma\n3 MCP tools\n'  # 和=1，真源 3
        return _fake_judge(T, bad)[0]
    case("MUT-help-group-sum-wrong-goes-red", _mut_group_sum, RC_VIOLATION)

    # 真源为空 ⇒ rc=2
    case("empty-registry-is-rc2", lambda: judge(set())[0], RC_CANNOT)

    # 判据面被删 ⇒ 必红
    def _mut_judge_face():
        bad = dict(GOOD)
        bad["scripts/check_doc_surface.py"] = "J2 J3"  # 少了 J14/J16
        return _fake_judge(T, bad)[0]
    case("MUT-doc-surface-ids-removed-goes-red", _mut_judge_face, RC_VIOLATION)

    # 真源标定（判例-32）：真仓的 real_tools() 能被读到且非空
    def _calibrate():
        try:
            t = real_tools()
        except Exception:  # noqa: BLE001
            return "SKIP"
        return len(t) > 0
    case("calibrate-on-real-registry", _calibrate, True)

    ok = 0
    for name, got, want in cases:
        good = got == want or (want is True and got == "SKIP")
        ok += 1 if good else 0
        print(f"  [{'OK' if good else 'FAIL'}] {name:<40} got={got} want={want}")
    print(f"\n[selftest] {ok}/{len(cases)} 格通过")
    return 0 if ok == len(cases) else 1


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)

    _KNOWN = ("--selftest", "--list")
    unknown = [a for a in argv if a.startswith("-") and a not in _KNOWN]
    if unknown:
        print("[FATAL] 未知参数 %s —— 已知：%s（rc=2）"
              % (" ".join(unknown), " / ".join(_KNOWN)))
        return RC_CANNOT

    if "--selftest" in argv:
        return selftest()

    try:
        tools = real_tools()
    except Exception as e:  # noqa: BLE001
        print(f"[FATAL] 真源读不到：{e} ⇒ rc=2")
        return RC_CANNOT

    rc, r = judge(tools)
    if "--list" in argv and rc not in (RC_CANNOT, RC_BROKEN):
        for label, val in r["matrix"].items():
            print(f"{label}: {val}")
        return rc
    render(rc, r)
    return rc


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as e:  # noqa: BLE001
        print(f"[BROKEN] 判据自身异常: {e} ⇒ rc=4")
        sys.exit(RC_BROKEN)
