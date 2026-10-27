#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_plan_location.py —— `docs/plans/` 计划库 frontmatter 守卫（BUG-440）。

## 为什么需要它（这是「承诺的判据从未存在」）

`docs/plans/README.md:22` 写着：

> **头部强制字段**（**缺一即红**，`check_plan_location` 守卫）：
> ```yaml
> ---
> status: 提案中   # 提案中 | 已定案 | 已驳回 | 已推迟 | 已完成
> decided_by:      # 定案人（仅 human_steward）
> decided_at:      # 定案时间戳
> decision:        # approved | rejected | deferred
> ---
> ```

**但本文件曾长期不存在**（BUG-440 实测：`ls scripts/check_plan_location.py` → 无）。
而 README 硬规则 2「未定案禁止发布任务（`plan_publish` 门禁）」**依赖 `status` 字段** ——
字段可以缺失时，那道门禁读什么就是未定义的。

实测后果：`docs/plans/2026-10-26-4pools-rhop-roadmap-proposal.md` 的第一个 `---` 块是
**AIGC 水印元数据**（`ContentProducer` / `ReserveCode1` …），不是 YAML frontmatter ⇒
`status`/`decided_by`/`decided_at`/`decision` 四字段全缺，**无任何判据报红**。

## 判据（窄口径，只判 header 形状，不判内容质量）

- **P1 文件名**：`docs/plans/` 下（不含 `decisions/`、`archived/`）的 `*.md`（除 `README.md`）
  必须形如 `YYYY-MM-DD-<topic>.md`（`-proposal.md` 或计划名）。
- **P2 frontmatter 必须是文件第 1 行起**：行 1 必须恰为 `---`（容忍行尾 `\\r`）。
  ⇒ **AIGC 水印块若占第 1 行，判红**（它就是本次的真实违例形状）。
- **P3 四字段齐全**：`status` / `decided_by` / `decided_at` / `decision` 的**键名**必须出现
  （值可空 —— `决策中` 的提案 `decided_by:` 为空是合法的）。
- **P4 `status` 值 ∈ 闭集**：`{提案中, 已定案, 已驳回, 已推迟, 已完成}`。
- **P5 `已定案` 的自洽**：`decided_by` 必须 == `human_steward`；`decided_at` 非空；
  `decision` ∈ `{approved, rejected, deferred}`；且 `decisions/` 下必须有对应记录
  （文件名含同一日期前缀）。
- **P6 终态归档**：`已已完成` / `已驳回` / `已推迟` 的计划应位于 `archived/`
  ⇒ **只告警不判红**（移动文件是人的决定，不是判据的责任）。

**为什么 P3 只判键名不判值**：`status: 提案中` 时 `decided_by`/`decided_at`/`decision`
本来就该为空（README 自己的模板就是空的）。判「键必须出现」而不是「值必须非空」，
才不会把合法提案判红。**这是本判据唯一容易写错的地方。**

## rc 契约（与 `check_fmt_gate.py` / `check_two_faces.py` 同口径，不新造）

- `0` 全部合规
- `1` 有违例（**逐条点名**）
- `2` 判据无法自证（`docs/plans/` 不存在 / 一份提案都没扫到）
  ⇒ **绝不因「没找到文件」报绿**

用法：
    python scripts/check_plan_location.py             # 判据模式
    python scripts/check_plan_location.py --selftest  # 自证（含变异对照）
    python scripts/check_plan_location.py --plans-dir <dir>  # 指定目录（selftest/调试用）
"""

from __future__ import annotations

import argparse
import os
import re
import sys

try:  # Windows cp936 控制台：不 reconfigure 会因 ✓/✗ 抛 UnicodeEncodeError
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLANS = os.path.join(ROOT, "docs", "plans")

RC_OK, RC_VIOLATION, RC_BROKEN = 0, 1, 2

STATUS_CLOSED = {"提案中", "已定案", "已驳回", "已推迟", "已完成"}
DECISION_CLOSED = {"approved", "rejected", "deferred"}
TERMINAL = {"已驳回", "已推迟", "已完成"}
REQUIRED_KEYS = ("status", "decided_by", "decided_at", "decision")
NAME_RX = re.compile(r"^\d{4}-\d{2}-\d{2}-.+\.md$")


def read(p: str) -> str:
    # newline="" 保留 CRLF：本仓有 2 份提案是 CRLF，读时不能悄悄归一化后再判（判例-21 同族）
    with open(p, encoding="utf-8", errors="replace", newline="") as fh:
        return fh.read()


def rel(path: str) -> str:
    """相对仓库根；跨盘（tempfile 在 C:、仓库在 E:）时退回绝对路径，不许抛。"""
    try:
        return os.path.relpath(path, ROOT).replace("\\", "/")
    except ValueError:
        return path.replace("\\", "/")


def norm_line(ln: str) -> str:
    return ln.rstrip("\r\n")


def parse_frontmatter(text: str):
    """返回 (ok, kv, reason)。

    ok=False 的 reason 直说「第 1 行不是 ---」或「没有闭合 ---」——
    这正是 AIGC 水印块被误当 frontmatter 时的形状。
    """
    lines = text.split("\n")
    if not lines:
        return False, {}, "空文件"
    if norm_line(lines[0]).strip() != "---":
        first = norm_line(lines[0])[:40]
        return False, {}, "第 1 行不是 `---`（实际：%r）" % first
    kv = {}
    for i in range(1, len(lines)):
        ln = norm_line(lines[i])
        if ln.strip() == "---":
            return True, kv, ""
        if ":" in ln and not ln.lstrip().startswith("-"):
            k, _, v = ln.partition(":")
            kv.setdefault(k.strip(), v.strip())
    return False, {}, "frontmatter 没有闭合的 `---`"


def check_one(path: str, rel: str, decisions: list) -> list:
    """返回违例列表 [(rel, code, msg)]。"""
    v = []
    base = os.path.basename(path)

    if not NAME_RX.match(base):
        v.append((rel, "P1", "文件名不符合 `YYYY-MM-DD-<topic>.md`"))

    text = read(path)
    ok, kv, why = parse_frontmatter(text)
    if not ok:
        v.append((rel, "P2", "frontmatter 非法：" + why))
        return v  # 后面全依赖 kv，没法继续判

    for k in REQUIRED_KEYS:
        if k not in kv:
            v.append((rel, "P3", "缺强制字段 `%s`" % k))

    st = kv.get("status", "")
    if st and st not in STATUS_CLOSED:
        v.append((rel, "P4", "`status` 值 %r 不在闭集 %s" % (st, sorted(STATUS_CLOSED))))

    if st == "已定案":
        if kv.get("decided_by", "") != "human_steward":
            v.append((rel, "P5", "`已定案` 但 `decided_by` != human_steward（实际 %r）"
                      % kv.get("decided_by", "")))
        if not kv.get("decided_at", ""):
            v.append((rel, "P5", "`已定案` 但 `decided_at` 为空"))
        dec = kv.get("decision", "")
        if dec not in DECISION_CLOSED:
            v.append((rel, "P5", "`已定案` 但 `decision` %r 不在 %s"
                      % (dec, sorted(DECISION_CLOSED))))
        date = base[:10]
        hit = any(date in d for d in decisions)
        if not hit:
            v.append((rel, "P5", "`已定案` 但 `decisions/` 下无 %s 前缀的记录" % date))

    return v


def scan(plans_dir: str):
    """返回 (files, violations, warns, broken_reason)。"""
    if not os.path.isdir(plans_dir):
        return [], [], [], "`%s` 不存在" % plans_dir

    decisions = []
    ddir = os.path.join(plans_dir, "decisions")
    if os.path.isdir(ddir):
        decisions = os.listdir(ddir)

    files = []
    for f in sorted(os.listdir(plans_dir)):
        if not f.endswith(".md") or f == "README.md":
            continue
        p = os.path.join(plans_dir, f)
        if os.path.isfile(p):
            files.append((p, f))

    if not files:
        return [], [], [], "`%s` 下一份提案都没扫到（空扫描面 ⇒ 拒绝出结论）" % plans_dir

    violations, warns = [], []
    for p, f in files:
        rel = "docs/plans/" + f
        if rel.startswith("docs/plans/", 0):
            pass
        violations += check_one(p, rel, decisions)
        # P6：终态计划应归档（只告警）
        text = read(p)
        ok, kv, _ = parse_frontmatter(text)
        if ok and kv.get("status") in TERMINAL:
            warns.append((rel, "P6", "status=%s 但仍在 plans/ 根（应移到 archived/）"
                          % kv.get("status")))
    return files, violations, warns, ""


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--plans-dir", default="")
    a = ap.parse_args(argv)

    if a.selftest:
        return selftest()

    plans_dir = a.plans_dir or PLANS
    files, violations, warns, broken = scan(plans_dir)

    if broken:
        print("[FATAL] " + broken)
        print("判据无法自证 —— 拒绝出结论，也拒绝因「没找到」报绿。rc=2")
        return RC_BROKEN

    print("[扫描] %s 下 %d 份计划文档" % (rel(plans_dir), len(files)))
    for p, f in files:
        print("  · " + f)

    if warns:
        print("\n[告警] %d 条（不判红 —— 归档是人的决定）" % len(warns))
        for _r, code, msg in warns:
            print("  ! [%s] %s — %s" % (code, _r, msg))

    if violations:
        print("\n[违例] %d 条：" % len(violations))
        for _r, code, msg in violations:
            print("  ✗ [%s] %s — %s" % (code, _r, msg))
        print("\n[结论] 有违例（README:22 承诺的四个强制字段/文件名规范未满足）")
        return RC_VIOLATION

    print("\n[结论] 全部合规：文件名 / frontmatter 位置 / 四字段 / status 闭集 / 已定案自洽")
    return RC_OK


# ── selftest（判例-5 同族：必须给执行面；判例-29/30：必须有变异对照） ──────
FM_OK = """---
status: 提案中
decided_by:
decided_at:
decision:
---
# 提案：x
"""

FM_DECIDED = """---
status: 已定案
decided_by: human_steward
decided_at: 2026-10-22
decision: approved
---
# 提案：y
"""

FM_AIGC = """---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ReservedCode1: pC4ZdXEB8Gbp9/szeM+c3IuLw0nsYhDYrF3drfnn6LiNR=
---
# 提案：z
"""

FM_MISSING_KEY = """---
status: 提案中
decided_by:
---
# 提案：w
"""

FM_BAD_STATUS = """---
status: 也许吧
decided_by:
decided_at:
decision:
---
# 提案：v
"""


def selftest() -> int:
    import contextlib
    import io
    import tempfile

    cells = []

    def cell(name, got, want):
        cells.append((name, got, want))
        print("  [%s] %-46s got=%r want=%r" % (
            "OK" if got == want else "FAIL", name, got, want))

    def mk(td, fname, content):
        p = os.path.join(td, fname)
        with open(p, "w", encoding="utf-8", newline="") as fh:
            fh.write(content)
        return p

    def run(td):
        with contextlib.redirect_stdout(io.StringIO()) as buf:
            rc = main(["--plans-dir", td])
        return rc, buf.getvalue()

    print("[selftest] 临时裸目录端到端（不碰真 docs/plans/）")
    with tempfile.TemporaryDirectory() as td:
        os.makedirs(os.path.join(td, "decisions"))

        # ── 格1：一份合法「提案中」 ⇒ rc=0 ──
        mk(td, "2026-10-22-ok-proposal.md", FM_OK)
        rc, out = run(td)
        cell("valid-proposal-rc0", rc, RC_OK)

        # ── 格2（★变异对照1）：把四字段之一删掉 ⇒ 必须 rc=1 且点名 P3 ──
        os.remove(os.path.join(td, "2026-10-22-ok-proposal.md"))
        mk(td, "2026-10-22-missing-key-proposal.md", FM_MISSING_KEY)
        rc, out = run(td)
        cell("MUTATION-missing-key-rc1", rc, RC_VIOLATION)
        cell("MUTATION-missing-key-named", "[P3]" in out, True)

        # ── 格3（★变异对照2）：AIGC 水印块当 frontmatter ⇒ 必须 rc=1 且 P2 ──
        os.remove(os.path.join(td, "2026-10-22-missing-key-proposal.md"))
        mk(td, "2026-10-26-aigc-proposal.md", FM_AIGC)
        rc, out = run(td)
        cell("MUTATION-aigc-watermark-rc1", rc, RC_VIOLATION)
        cell("MUTATION-aigc-detected-P3", "[P3]" in out, True)

        # ── 格4：status 不在闭集 ⇒ rc=1 且 P4 ──
        os.remove(os.path.join(td, "2026-10-26-aigc-proposal.md"))
        mk(td, "2026-10-26-bad-status-proposal.md", FM_BAD_STATUS)
        rc, out = run(td)
        cell("bad-status-rc1", rc, RC_VIOLATION)
        cell("bad-status-code-P4", "[P4]" in out, True)

        # ── 格5：文件名不合规范 ⇒ rc=1 且 P1 ──
        os.remove(os.path.join(td, "2026-10-26-bad-status-proposal.md"))
        mk(td, "no-date-proposal.md", FM_OK)
        rc, out = run(td)
        cell("bad-filename-rc1", rc, RC_VIOLATION)
        cell("bad-filename-code-P1", "[P1]" in out, True)
        os.remove(os.path.join(td, "no-date-proposal.md"))

        # ── 格6：已定案 有 decisions 记录 ⇒ rc=0 ──
        mk(td, "2026-10-22-decided-proposal.md", FM_DECIDED)
        mk(os.path.join(td, "decisions"), "2026-10-22-001-x.md", "ok\n")
        rc, out = run(td)
        cell("decided-with-record-rc0", rc, RC_OK)

        # ── 格7（★变异对照3）：删掉 decisions 记录 ⇒ 已定案必须 rc=1 且 P5 ──
        os.remove(os.path.join(td, "decisions", "2026-10-22-001-x.md"))
        rc, out = run(td)
        cell("MUTATION-decided-no-record-rc1", rc, RC_VIOLATION)
        cell("MUTATION-decided-no-record-P5", "[P5]" in out, True)

        # ── 格8：空扫描面 ⇒ rc=2 自拒（绝不因没找到报绿）──
        with tempfile.TemporaryDirectory() as empty:
            rc, out = run(empty)
            cell("empty-dir-self-reject-rc2", rc, RC_BROKEN)
            cell("empty-dir-says-FATAL", "[FATAL]" in out, True)

        # ── 格9：CRLF frontmatter 必须被正确解析（本仓 2 份提案是 CRLF）──
        with tempfile.TemporaryDirectory() as td2:
            os.makedirs(os.path.join(td2, "decisions"))
            with open(os.path.join(td2, "2026-10-22-crlf-proposal.md"),
                      "w", encoding="utf-8", newline="") as fh:
                fh.write(FM_OK.replace("\n", "\r\n"))
            rc, out = run(td2)
            cell("crlf-frontmatter-rc0", rc, RC_OK)

        # ── 格10：README.md 必须被跳过（它不是提案）──
        with tempfile.TemporaryDirectory() as td3:
            os.makedirs(os.path.join(td3, "decisions"))
            mk(td3, "2026-10-22-ok-proposal.md", FM_OK)
            mk(td3, "README.md", "# 说明\n不是 frontmatter\n")
            rc, out = run(td3)
            cell("readme-skipped-rc0", rc, RC_OK)

    ok = sum(1 for _n, g, w in cells if g == w)
    print("\n[selftest] %d/%d 格通过" % (ok, len(cells)))
    if ok != len(cells):
        print("[selftest] ✗ 有格未通过 —— 判据自身坏了")
        return 4
    return 0


if __name__ == "__main__":
    sys.exit(main())
