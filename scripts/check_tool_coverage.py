#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_tool_coverage.py —— MCP 工具「外壳 + 实现两层」覆盖判据（BUG-455）。

## 为什么需要它（BUG-455 的核心洞察）

**零覆盖的危害不是「实现没测」，而是「外壳与实现之间那根线没测」。**

本会话已发生 3 次「实现层 208 格测试全绿、工具照样是坏的」：

| BUG | 症状 | 实现层 | 外壳层 |
|---|---|---|---|
| BUG-440 | 承诺了 `check_plan_location` 守卫，文件从未存在 | — | **零测试** |
| BUG-453 | `execute` 声明 `challenge` 参数但从不调 `opt_challenge` | 有 | **零测试** |
| BUG-436 | ACL 判定身份取错字段（`executor` 缺省 `manual`） | 有 | **零测试** |
| BUG-439 | 熔断器内存后端占位 ⇒ `state` 恒 closed，回执看不出来 | 有 | **零测试** |

## 判法（这是本判据的全部价值）

一个工具算「有覆盖」，当且仅当**下面两条至少一条成立**：

- **A 外壳面**：工具名出现在任何 `*_test.mbt` / `*_wbtest.mbt` 里
  （说明有人测了「这个工具的接线/回执」）
- **B 实现面**：该工具 handler 调用的**引擎函数**出现在测试里
  （说明它背后的逻辑被单独测过 —— 但这**不能**替代 A）

**⚠️ 为什么 B 单独不够**：`BUG-453` 的 `execute` 底层 `execute_task` 有测试，
**但「`challenge` 参数有没有被接上」这件事只有外壳面测得出**。
所以本判据把 A / B **分开列**，A 缺失即报「外壳零覆盖」，B 缺失报「实现层也零覆盖」。

## 工具名 → 实现函数 的映射（可维护方案）

**不做启发式猜测**，用一张**显式白名单** `IMPL_MAP`（工具名 → 实现包里被调用的函数名）。
理由：自动从 handler 里抽 `@pkg.fn` 会混入 `@mcp.*`（注册宏）与 `get_str` 等工具函数，
本轮实测假阳性 13/30 —— **启发式在这个面上不可靠，白名单可靠且可增删**。

白名单**不需要覆盖全部**：不在表里的工具，判据只查 A 面（外壳），
并在输出里标 `impl=unmapped`（**诚实标注未映射，不假装查过**）。

## rc 契约（与 `check_fmt_gate.py` / `check_plan_location.py` 同口径）

- `0` = 全部工具有外壳覆盖
- `1` = 有工具外壳零覆盖（逐条点名）
- `2` = 判据无法自证（`server.mbt` 读不到 / 一个工具都没抽到）

**⚠️ 本判据只判「有没有测试」，不判「测试好不好」。**
外壳有测试但只断言字符串存在的，本判据**放行** —— 那是 `check_two_faces.py` 与人工的活。

用法：
    python scripts/check_tool_coverage.py            # 判据模式
    python scripts/check_tool_coverage.py --selftest # 自证（含变异对照）
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
RC_OK, RC_VIOLATION, RC_BROKEN = 0, 1, 2

# ── 工具名 → 实现函数 白名单（只列「实现包确实有测试」的那些）────────────────
# 维护方式：发现某个工具被误报「实现层零覆盖」，把它的实现函数名加进来。
IMPL_MAP = {
    # @diff
    "text_diff": ["diff_lines"],
    # @display
    "rank_of": ["rank_of", "leaf_label"],
    "staff_label_of": ["staff_label"],
    "soldier_type_of": ["soldier_type_of"],
    # @ops
    "audit_permission": ["enforce"],
    "mode_templates": ["mode_template_path"],
    "evolve_snapshot": ["snapshot"],
    # @store
    "assistant_resign": ["assistant_set_status"],
    "assistant_status": ["assistant_list", "assistant_active_primary"],
    "lock_status": ["locks_get"],
    "reserve_check": ["rsv_get"],
    "reserve_release": ["rsv_release"],
    "lock_release": ["locks_release"],
    # 纯计算
    "github_issue_webhook_parse": ["github_webhook_parse"],
    "executor_auction": ["auction_pick"],
    # @server · wt_tools.mbt（R103：三个 worktree 工具的**实现已迁出 server.mbt**，
    # 此处映到工具所依赖的**纯函数核心**——A 面查工具名、B 面查这些核心函数是否被试过）
    "wt_create": ["wt_task_ok", "wt_branch_default", "wt_entry_json", "wt_path_ok"],
    "wt_status": ["wt_state_of", "wt_tally", "wt_parse_porcelain", "wt_reclaimable"],
    "wt_destroy": ["wt_path_ok", "wt_state_of"],
}

TOOL_RX = re.compile(
    r'(?:instrumented_tool|tool)\(\s*(?:s\d*\s*,\s*)?"([a-z][a-z0-9_]*)"'
)


def read(p):
    return io.open(p, encoding="utf-8", errors="replace").read()


def all_test_text(root):
    out = []
    for f in glob.glob(os.path.join(root, "src", "**", "*_test.mbt"), recursive=True):
        out.append(read(f))
    for f in glob.glob(os.path.join(root, "src", "**", "*_wbtest.mbt"), recursive=True):
        out.append(read(f))
    return "\n".join(out)


def extract_tools(root):
    srv = os.path.join(root, "src", "server", "server.mbt")
    if not os.path.isfile(srv):
        return None
    return sorted({m.group(1) for m in TOOL_RX.finditer(read(srv))})


def judge(root):
    tools = extract_tools(root)
    if not tools:
        return RC_BROKEN, {"note": "抽不到任何工具名（server.mbt 不在或注册形状变了）"}
    tests = all_test_text(root)
    if not tests.strip():
        return RC_BROKEN, {"note": "一份测试文件都没读到（空扫描面 ⇒ 拒绝出结论）"}

    shell_ok, impl_ok, unmapped = [], [], []
    shell_missing = []
    for t in tools:
        if t in tests:
            shell_ok.append(t)
        else:
            shell_missing.append(t)
        fns = IMPL_MAP.get(t)
        if not fns:
            unmapped.append(t)
        elif any(fn in tests for fn in fns):
            impl_ok.append(t)

    return (RC_OK if not shell_missing else RC_VIOLATION), {
        "tools": tools,
        "shell_ok": shell_ok,
        "shell_missing": shell_missing,
        "impl_ok": impl_ok,
        "impl_map_size": len(IMPL_MAP),
        "unmapped": unmapped,
        "tests_chars": len(tests),
    }


def render(res):
    n = len(res["tools"])
    miss = len(res["shell_missing"])
    cover = n - miss
    print("[覆盖面] 本判据只判「有没有测试」，**不判测试好不好**：")
    print("  ✅ A 外壳面：工具名出现在测试里（能抓接线/回执类缺陷，如 BUG-453/436/439）")
    print("  ✅ B 实现面：工具映射到的实现函数出现在测试里（**不能替代 A**）")
    print("  ❌ 不判：测试是否断言行为（只断言字符串的也放行 → 那要人工/check_two_faces）")
    print("  ？未映射：工具不在 IMPL_MAP 白名单里 → 只查 A 面，**不假装查过 B**")
    print()
    print("[扫描] 工具 %d 个 · 测试文本 %d 字符" % (n, res["tests_chars"]))
    print()
    print("[A 外壳面] 有覆盖 %d / %d" % (cover, n))
    if res["shell_missing"]:
        print("  外壳零覆盖 %d 个：" % miss)
        for t in res["shell_missing"]:
            mapped = "impl=unmapped" if t in res["unmapped"] else "impl=mapped"
            print("    - %-30s %s" % (t, mapped))
    else:
        print("  （无）")
    print()
    print("[B 实现面] 已映射 %d 个工具，其中实现函数在测试里出现 %d 个"
          % (len(IMPL_MAP), len(res["impl_ok"])))
    print("[结论] 外壳零覆盖 %d / %d（%.1f%%）；覆盖率 %.1f%%"
          % (miss, n, 100.0 * miss / n if n else 0, 100.0 * cover / n if n else 0))
    if miss == 0:
        print("[PASS] 全部工具有外壳覆盖。**这不代表工具是对的** —— 只代表「有人碰过它」。")
    else:
        print("[FAIL] 有 %d 个工具从未被任何测试碰过 —— 它们坏了没人知道。" % miss)


def selftest():
    import contextlib
    import tempfile

    cells = []

    def cell(name, got, want):
        cells.append((name, got, want))
        print("  [%s] %-44s got=%r want=%r"
              % ("OK" if got == want else "FAIL", name, got, want))

    def mk(root, tools, test_body, srv_body=None):
        os.makedirs(os.path.join(root, "src", "server"), exist_ok=True)
        with io.open(os.path.join(root, "src", "server", "server.mbt"), "w",
                     encoding="utf-8") as f:
            f.write(srv_body if srv_body is not None
                    else "".join('instrumented_tool(s1, "%s", "d", schema({}, []), fn)\n' % t
                                 for t in tools))
        with io.open(os.path.join(root, "src", "server", "x_test.mbt"), "w",
                     encoding="utf-8") as f:
            f.write(test_body)

    print("[selftest] 临时裸目录端到端（不碰真 src/）")
    with tempfile.TemporaryDirectory() as td:
        # 格1：两个工具都有外壳测试 ⇒ rc=0
        mk(td, ["tool_a", "tool_b"], 'test "x" {\n  tool_a();\n  tool_b();\n}\n')
        rc, res = judge(td)
        cell("all-covered-rc0", rc, RC_OK)
        cell("all-covered-missing0", len(res["shell_missing"]), 0)

        # 格2（★变异对照）：删掉 tool_b 的测试引用 ⇒ rc=1 且点名 tool_b
        mk(td, ["tool_a", "tool_b"], 'test "x" {\n  tool_a();\n}\n')
        rc2, res2 = judge(td)
        cell("MUTATION-removed-test-rc1", rc2, RC_VIOLATION)
        cell("MUTATION-names-tool_b", "tool_b" in res2["shell_missing"], True)

        # 格3：只有实现层测试、没有外壳测试 ⇒ **仍然报零覆盖**（B 不能替代 A）
        mk(td, ["text_diff"], 'test "y" {\n  diff_lines();\n}\n')
        rc3, res3 = judge(td)
        cell("impl-only-still-missing", "text_diff" in res3["shell_missing"], True)
        cell("impl-only-rc1", rc3, RC_VIOLATION)
        cell("impl-layer-detected", "text_diff" in res3["impl_ok"], True)

        # 格4：空扫描面 ⇒ rc=2 自拒
        with tempfile.TemporaryDirectory() as e:
            os.makedirs(os.path.join(e, "src", "server"), exist_ok=True)
            rc4, res4 = judge(e)
            cell("empty-self-reject-rc2", rc4, RC_BROKEN)

        # 格5：输出必须自带覆盖率声明（不只写在 docstring）
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            render({"tools": ["a"], "shell_ok": ["a"], "shell_missing": [],
                    "impl_ok": [], "unmapped": ["a"], "impl_map_size": 0,
                    "tests_chars": 10})
        out = buf.getvalue()
        cell("coverage-note-in-output", "不判测试好不好" in out, True)
        cell("pass-not-correct-in-output", "不代表工具是对的" in out, True)

    ok = sum(1 for _n, g, w in cells if g == w)
    print("\n[selftest] %d/%d 格通过" % (ok, len(cells)))
    sys.exit(0 if ok == len(cells) else 4)  # NO_CALL_FACE J2


def main(argv=None):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--root", default="")
    a = ap.parse_args(argv)
    if a.selftest:
        return selftest()
    root = a.root or ROOT
    rc, res = judge(root)
    if rc == RC_BROKEN:
        print("[FATAL] " + res["note"])
        print("判据无法自证 —— 拒绝出结论，也拒绝因「没找到」报绿。rc=2")
        return RC_BROKEN
    render(res)
    return rc if not res["shell_missing"] else RC_VIOLATION


if __name__ == "__main__":
    sys.exit(main())
