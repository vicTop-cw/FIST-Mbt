#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""scripts/check_ns_write_gate_coverage.py — ns 写门「文档声称的覆盖清单 ↔ 实际调用点清单」对表守卫（BUG-459）。

## 为什么需要它（BUG-459 的病灶不是漏一行，是**没有对表**）

`src/server/write_gate.mbt` 的文档写着 ns 写门「只拦**新建**（publish / publish_parallel /
dag_publish）」，而全仓实际调用点长期只有 `publish` 一处（`server.mbt:1905`）。
文档与代码各说各话，**没有第二条命**去发现它们分叉：`publish_parallel` 走 engine 自带的
default 拒绝还能兜住一半，`dag_publish` 干脆一路畅通——客户端换个工具名就能把任务写进
default.db（跨项目污染，T0r1 止血要治的正是这个面）。

漏一次是缺陷，**漏了没人知道**才是根因。所以本尺不测「某一行代码在不在」，
它测**两个清单是不是同一个集合**：

  - 文档侧清单：`write_gate.mbt` 里 `只拦**新建**（A / B / C）` 括号内的工具名；
  - 代码侧清单：`server.mbt` 里每个 `instrumented_tool(...)` 注册块体内**非注释行**是否出现
    `ns_write_gate(` 调用。

两侧集合必须相等。少一支 ⇒ rc=1 点名；多一支（代码里有门、文档没声称）⇒ 同样 rc=1 点名
（**文档落后也是漂移**，下一个人会照文档以为只有三支）；文档清单读不到 / 注册块解析不出
⇒ rc=2「判据无法自证」，不把「我读不到」冒充成「代码没调用」（判例-30 的反面：假红与假绿都坏）。

## 为什么必须跳过注释行（判例-30 的直接后果）

「注释里写了 `ns_write_gate(ns)`」与「真调了门」在字符面无法区分，本尺只认**代码行**
（`lstrip()` 后不以 `//` 开头）。这条不是洁癖：上一轮有人把变异改在注释上 ⇒ 锁恒绿
（看起来在工作：有匹配、有断言）。自检的 M2 格就锁这一条。

## 为什么不查 handler 闭包的行为面（诚实标注）

`publish` / `publish_parallel` / `dag_publish` 的 handler 是 `run_server()` 里的**匿名闭包**，
测试无法注入（`src/server/tool_cov_lane_c_test.mbt` 头注已记为结构性残差）⇒ 行为面只能靠
`ns_write_gate` 的语义锁（`src/server/server_bug458_459_wbtest.mbt`）+ 本尺的**静态接线对表**。
本尺不声称覆盖「门被调用后是否真的在拒绝」——那是语义锁的活。

## 用法

    python scripts/check_ns_write_gate_coverage.py               # 对表（裸跑即可进电池）
    python scripts/check_ns_write_gate_coverage.py --selftest    # 尺子先证明自己会红
    python scripts/check_ns_write_gate_coverage.py --root <dir>   # 指到别处（自证用合成面）

## 退出码

0 = 两侧清单相等（逐支点名打印）
1 = 有违例（逐条点名缺门/多门/块外调用）
2 = 判据无法自证（文档或注册面读不到、文档清单解析为空、注册块为空）
4 = 尺子自己坏了（未捕获异常；`--selftest` 有格未过同样落到这一档，可证伪）
"""
from __future__ import annotations

import argparse
import contextlib
import io
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

# BUG-138 残余面：Windows 默认 cp936 控制台下中文结论一红就崩在 print 里，
# traceback + rc=1 会被读成「缺陷在场」那一档——那是尺子自己坏了。先把两条流钉 UTF-8。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent

DOC_FILE = "src/server/write_gate.mbt"
WIRE_FILE = "src/server/server.mbt"

# 文档那行的形状：``/// 只拦**新建**（publish / publish_parallel / dag_publish）：…``
CLAIM_RE = re.compile(r"只拦\*\*新建\*\*（([^）]+)）")
TOOL_NAME_RE = re.compile(r"^[a-z][a-z0-9_]*$")
# 注册块起点：`  s1 = instrumented_tool(`（server.mbt 里全部是 s1 链式注册）
BLOCK_START_RE = re.compile(r"^\s*\w+\s*=\s*instrumented_tool\($")
# 链式 `.tool(` 形态也算块边界：不认它就会把下一个工具的块体并进上一个（误判「谁调了门」）
CHAIN_START_RE = re.compile(r"^\s*\.tool\(")
# 「真调用」的唯一判据：代码行里出现 `ns_write_gate(` —— 注释行另行剔除
GATE_CALL_RE = re.compile(r"\bns_write_gate\s*\(")
# 注册块里工具名那一行：`    "dag_publish",`
NAME_LINE_RE = re.compile(r'^\s*"([^"]+)",\s*$')

PASS_LABEL = "PASS"
FAIL_LABEL = "FAIL"


def is_comment(line: str) -> bool:
    """该行是否注释（判例-30：注释不算接线）。"""
    return line.lstrip().startswith("//")


def is_code_gate(line: str) -> bool:
    """该行是否是**代码里的** `ns_write_gate(` 调用点（注释行一律不算）。"""
    if is_comment(line):
        return False
    return GATE_CALL_RE.search(line) is not None


def parse_claimed(doc_text: str):
    """从文档里解析「声称覆盖的工具清单」；读不到返回 None（⇒ rc=2，不冒充「没调用」）。"""
    for line in doc_text.splitlines():
        m = CLAIM_RE.search(line)
        if not m:
            continue
        names = []
        for part in m.group(1).split("/"):
            cand = part.strip()
            if TOOL_NAME_RE.match(cand):
                names.append(cand)
        if names:
            return names
        return None
    return None


def parse_blocks(wire_text: str):
    """解析 `instrumented_tool` 注册块。

    返回 ``(blocks, strays)``：
      - ``blocks``: ``{工具名: [块体行…]}``（块体到下一个块起点为止）；
      - ``strays``: 落在任何注册块**之外**的 ``ns_write_gate(`` 代码调用（行号, 文本）——
        这类调用不属于任何工具 ⇒ 单独点名（可能是把门挪到 helper 里去了，行为面已变）。
    """
    lines = wire_text.splitlines()
    blocks: dict[str, list[str]] = {}
    spans: list[tuple[int, int]] = []  # 每条已识别块的 [start, end)
    i = 0
    total = len(lines)
    while i < total:
        if not BLOCK_START_RE.match(lines[i]):
            i += 1
            continue
        start = i
        j = i + 1
        # 找 `    s1,` 行；撞到下一个块起点说明本块没有该行（注册形变了）
        while j < total and lines[j].strip() != "s1,":
            if BLOCK_START_RE.match(lines[j]) or CHAIN_START_RE.match(lines[j]):
                break
            j += 1
        if j >= total or lines[j].strip() != "s1,":
            i = j if j > i else i + 1
            continue
        k = j + 1
        while k < total and lines[k].strip() == "":
            k += 1
        name = None
        if k < total:
            m = NAME_LINE_RE.match(lines[k])
            if m:
                name = m.group(1)
        end = start + 1
        start_indent = len(lines[start]) - len(lines[start].lstrip())
        while end < total:
            if BLOCK_START_RE.match(lines[end]) or CHAIN_START_RE.match(lines[end]):
                break
            # 块以同缩进的 `)` 收口。**必须认这个收口行**：只靠「撞到下一个块起点」切块的话，
            # 最后一个块会把文件尾部（helper fn、块外调用）一并吞进去 ⇒ 块外调用被误算成
            # 「最后那个工具调了门」（本尺的 M7 格就是这么抓出来的假绿）。
            stripped = lines[end].strip()
            cur_indent = len(lines[end]) - len(lines[end].lstrip())
            if stripped == ")" and cur_indent <= start_indent:
                break
            end += 1
        spans.append((start, end))
        if name:
            blocks[name] = lines[start:end]
        i = end
    strays = []
    for idx, line in enumerate(lines):
        if not is_code_gate(line):
            continue
        if any(s <= idx < e for s, e in spans):
            continue
        strays.append((idx + 1, line.strip()))
    return blocks, strays


def judge(root: Path) -> int:
    """真判据：两侧清单对表。返回 0/1/2（4 由 main 的未捕获异常兜）。"""
    doc_path = root / DOC_FILE
    wire_path = root / WIRE_FILE
    for p, what in ((doc_path, DOC_FILE), (wire_path, WIRE_FILE)):
        if not p.is_file():
            print("%s 判据无法自证：读不到真源 %s（缺文件不等于没调用）" % (FAIL_LABEL, what))
            return 2
    doc_text = doc_path.read_text(encoding="utf-8", errors="replace")
    wire_text = wire_path.read_text(encoding="utf-8", errors="replace")

    claimed = parse_claimed(doc_text)
    if not claimed:
        print(
            "%s 判据无法自证：%s 里找不到「只拦**新建**（A / B / C）」覆盖清单，无法对表"
            % (FAIL_LABEL, DOC_FILE)
        )
        return 2

    blocks, strays = parse_blocks(wire_text)
    if not blocks:
        print(
            "%s 判据无法自证：%s 里解析不到任何 instrumented_tool 注册块（注册形变了？）"
            % (FAIL_LABEL, WIRE_FILE)
        )
        return 2

    missing_blocks = [t for t in claimed if t not in blocks]
    if missing_blocks:
        print(
            "%s 判据无法自证：文档声称覆盖 %s，但 %s 里解析不到其注册块"
            "（工具不存在或注册形变了 ⇒ 不冒充「没调用」）"
            % (FAIL_LABEL, " / ".join(missing_blocks), WIRE_FILE)
        )
        return 2

    gated = {name for name, body in blocks.items() if any(is_code_gate(l) for l in body)}

    problems = []
    ungated = [t for t in claimed if t not in gated]
    for t in ungated:
        problems.append("文档声称覆盖但实际未调用 ns_write_gate：%s（%s 里有注册块、块内无门）" % (t, WIRE_FILE))
    extra = [t for t in gated if t not in claimed]
    for t in extra:
        problems.append(
            "代码里调了 ns_write_gate 但文档未声称：%s（文档落后于实现，同属漂移）" % t
        )
    for lineno, text in strays:
        problems.append(
            "%s:%d 的 ns_write_gate 调用落在任何工具注册块之外：%s" % (WIRE_FILE, lineno, text)
        )

    if problems:
        print(
            "%s ns 写门覆盖面对表不通过（文档声称 %d 支 / 注册块内有门 %d 支 / 块外调用 %d 处）："
            % (FAIL_LABEL, len(claimed), len(gated), len(strays))
        )
        for p in problems:
            print("  - " + p)
        return 1

    print(
        "%s ns 写门覆盖面对表：文档声称 == 实际调用点（%d 支：%s）"
        % (PASS_LABEL, len(claimed), " / ".join(claimed))
    )
    return 0


def main(argv=None) -> int:
    """调用面（承诺的 rc 四档在这里收口）。"""
    parser = argparse.ArgumentParser(
        description="ns 写门：write_gate.mbt 文档声称清单 ↔ server.mbt 实际调用点清单 对表"
    )
    parser.add_argument("--root", default=str(ROOT), help="仓库根（缺省=脚本所在仓）")
    parser.add_argument("--selftest", action="store_true", help="跑尺子自检（合成对照）")
    try:
        args = parser.parse_args(argv)
        if args.selftest:
            return selftest()
        return judge(Path(args.root))
    except SystemExit:
        raise
    except Exception as exc:  # 尺子自己坏了：绝不冒用 1 那一档
        print("%s 尺子自己坏了：%r" % (FAIL_LABEL, exc), file=sys.stderr)
        return 4


# ---------------------------------------------------------------------------
# 自检（合成夹具，不读真仓现状面 —— R153 hermetic 口径）
# ---------------------------------------------------------------------------

FIX_DOC = """///|
/// ns 写门（夹具）
///
/// 只拦**新建**（__CLAIM__）：claim/execute/submit 是状态迁移，不设门。
pub fn ns_write_gate(ns : String) -> Result[Unit, String] {
  Ok(())
}
"""

FIX_BLOCK = """  s1 = instrumented_tool(
    s1,
    "__NAME__",
    "夹具工具 __NAME__",
    schema({"project_dir": string_prop("项目目录")}, ["project_dir"]),
    fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
__GATE__      let ns = get_str(args, "namespace", default="default")
      Ok(@mcp.ToolResult::text("{}"))
    },
  )
"""

FIX_GATE = (
    "      let g = ns_write_gate(ns)\n"
    "      if g is Err(ge) {\n"
    "        return Err(@mcp.ToolError(ge))\n"
    "      }\n"
)
# M2 用：注释里保留同样的调用串，但**不是**接线（判例-30）
FIX_GATE_COMMENT = "      // 历史注释：ns_write_gate(ns) 曾在此\n"

# 现有三支（与真仓文档一致）
CLAIM3 = ["publish", "publish_parallel", "dag_publish"]


def write_fixture(base: str, name: str, doc_text: str, server_text: str) -> str:
    """写一份合成夹具（doc + server 两份真源），返回夹具根目录。"""
    d = os.path.join(base, name)
    os.makedirs(os.path.join(d, "src", "server"), exist_ok=True)
    with io.open(os.path.join(d, DOC_FILE), "w", encoding="utf-8", newline="\n") as f:
        f.write(doc_text)
    with io.open(os.path.join(d, WIRE_FILE), "w", encoding="utf-8", newline="\n") as f:
        f.write(server_text)
    return d


def build_server(blocks) -> str:
    """按 (工具名, 是否带门) 列表拼 server.mbt 夹具。"""
    parts = []
    for name, gated in blocks:
        parts.append(
            FIX_BLOCK.replace("__NAME__", name).replace(
                "__GATE__", FIX_GATE if gated else ""
            )
        )
    return "\n".join(parts)


def build_doc(claim) -> str:
    return FIX_DOC.replace("__CLAIM__", " / ".join(claim))


def run_case(base: str, name: str, claim, blocks) -> tuple[int, str]:
    """跑一格：写夹具 → 走 main(["--root", …])（调用面，不是只考 judge）。"""
    d = write_fixture(base, name, build_doc(claim), build_server(blocks))
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = main(["--root", d])
    return rc, buf.getvalue()


def selftest() -> int:
    """自检：干净格 + 变异对照（改坏点在**代码**，不在注释）+ 空扫描自拒。"""
    base = tempfile.mkdtemp(prefix="nswg_selftest_")
    cells = []

    def cell(name, ok, detail):
        cells.append((name, ok, detail))

    try:
        # ── 格 1：干净夹具不误红（三支都真调了门）──────────────────────────────
        rc, out = run_case(
            base,
            "clean",
            CLAIM3,
            [("publish", True), ("publish_parallel", True), ("dag_publish", True)],
        )
        cell(
            "clean-3-gated-rc0",
            rc == 0 and PASS_LABEL in out,
            "三支都真调门 ⇒ rc=0（实际 rc=%d / %r）" % (rc, out.strip()[:120]),
        )

        # ── 格 2（变异对照 M1）：删掉 dag_publish 块里**真实的调用行** ⇒ 必须 rc=1 并点名 ──
        broken = build_server(
            [("publish", True), ("publish_parallel", True), ("dag_publish", False)]
        )
        # 断言变异真的落在代码而不是注释上：被删的那行原本是代码行
        if FIX_GATE.strip().splitlines()[0].lstrip().startswith("//"):
            cell("mutation-is-on-code", False, "夹具的「门」本身就在注释里 —— 这格不成立")
        else:
            cell("mutation-is-on-code", True, "变异删的是 FIX_GATE 的代码行（非注释）")
        d = write_fixture(base, "m1_drop_code", build_doc(CLAIM3), broken)
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = main(["--root", d])
        out = buf.getvalue()
        cell(
            "M1-drop-code-line-rc1",
            rc == 1 and "dag_publish" in out,
            "删掉 dag_publish 的真调用 ⇒ rc=1 点名（实际 rc=%d / %r）" % (rc, out.strip()[:160]),
        )

        # ── 格 3（变异对照 M2）：只留注释、没有真调用 ⇒ 仍必须 rc=1（判例-30）──
        blocks = [
            ("publish", True),
            ("publish_parallel", True),
        ]
        server = build_server(blocks) + FIX_BLOCK.replace("__NAME__", "dag_publish").replace(
            "__GATE__", FIX_GATE_COMMENT
        )
        d = write_fixture(base, "m2_comment_only", build_doc(CLAIM3), server)
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = main(["--root", d])
        out = buf.getvalue()
        cell(
            "M2-comment-is-not-wiring-rc1",
            rc == 1 and "dag_publish" in out,
            "注释里写了调用串 ⇒ 仍 rc=1（实际 rc=%d / %r）" % (rc, out.strip()[:160]),
        )

        # ── 格 4（变异对照 M3）：文档多声称一支、代码那支无门 ⇒ rc=1 ──
        rc, out = run_case(
            base,
            "m3_claim_extra",
            CLAIM3 + ["batch_publish"],
            [
                ("publish", True),
                ("publish_parallel", True),
                ("dag_publish", True),
                ("batch_publish", False),
            ],
        )
        cell(
            "M3-doc-claims-more-rc1",
            rc == 1 and "batch_publish" in out,
            "文档多声称 batch_publish ⇒ rc=1 点名（实际 rc=%d / %r）" % (rc, out.strip()[:160]),
        )

        # ── 格 5（变异对照 M4）：代码多一支带门的工具、文档没声称 ⇒ rc=1（文档落后也是漂移）──
        rc, out = run_case(
            base,
            "m4_extra_gated",
            CLAIM3,
            [
                ("publish", True),
                ("publish_parallel", True),
                ("dag_publish", True),
                ("store_open", True),
            ],
        )
        cell(
            "M4-code-extra-gated-rc1",
            rc == 1 and "store_open" in out,
            "代码多一支门 ⇒ rc=1 点名（实际 rc=%d / %r）" % (rc, out.strip()[:160]),
        )

        # ── 格 6：文档清单行缺失 ⇒ rc=2（不把「读不到」冒充成「没调用」）──
        d = write_fixture(
            base,
            "m5_no_doc_line",
            "/// ns 写门（夹具，文档忘了写覆盖清单）\n" + "/// 只拦新建（无星号锚点，不算清单）\n",
            build_server([("publish", True)]),
        )
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = main(["--root", d])
        out = buf.getvalue()
        cell(
            "M5-doc-line-missing-rc2",
            rc == 2,
            "文档没有「只拦**新建**（…）」清单 ⇒ rc=2（实际 rc=%d / %r）" % (rc, out.strip()[:160]),
        )

        # ── 格 7：文档声称的工具在注册面找不到块 ⇒ rc=2（注册形变/工具不存在）──
        rc, out = run_case(
            base,
            "m6_block_missing",
            CLAIM3,
            [("publish", True), ("publish_parallel", True)],
        )
        cell(
            "M6-claimed-block-missing-rc2",
            rc == 2,
            "文档声称 dag_publish 但注册块缺失 ⇒ rc=2（实际 rc=%d / %r）" % (rc, out.strip()[:160]),
        )

        # ── 格 8：块外的门调用（挪到 helper 里）⇒ rc=1 点名行号 ──
        server = build_server(
            [("publish", True), ("publish_parallel", True), ("dag_publish", True)]
        ) + "\nfn helper_outsider(ns : String) -> Result[Unit, String] {\n  ns_write_gate(ns)\n}\n"
        d = write_fixture(base, "m7_stray_call", build_doc(CLAIM3), server)
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = main(["--root", d])
        out = buf.getvalue()
        cell(
            "M7-stray-outside-block-rc1",
            rc == 1 and "之外" in out,
            "门被挪到注册块外 ⇒ rc=1 点名（实际 rc=%d / %r）" % (rc, out.strip()[:160]),
        )
    finally:
        shutil.rmtree(base, ignore_errors=True)

    failed = [c for c in cells if not c[1]]
    for name, ok, detail in cells:
        print("  [%s] %-34s %s" % ("ok" if ok else "RED", name, detail))
    print(
        "自检：%d 格 / 通过 %d / 未过 %d（清单从已执行格子反解：%d 格）"
        % (len(cells), len(cells) - len(failed), len(failed), len(cells))
    )
    if failed:
        print("%s --selftest 有格未过 ⇒ 尺子自己坏了（rc=4），不冒用 1 那一档" % FAIL_LABEL)
        return 4
    print("%s --selftest 全过" % PASS_LABEL)
    return 0


if __name__ == "__main__":
    sys.exit(main())
