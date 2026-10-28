#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_dist_snapshot.py — 仓内发布快照 `dist/fist-mbt.js` 的**版本面 + 内容面**守卫。

**版本面（R 轮既有）**：
`dist/fist-mbt.js` 是**仓内跟踪的发布快照**，而 `scripts/mcp_compat_shim.js` 的默认服务端就是它
（`node dist/fist-mbt.js serve`）、README 也把它当"发布版"引用。实测它曾内嵌 `project__version = "0.3.9"`，
而 `moon.mod` 已是 **0.3.10** ⇒ 任何照 shim 文档连过去的人/agent 拿到的是**旧版本 + 旧工具集**
（shim 注释里甚至写着 148 工具/v0.3.8）。`release.yml` 构建的是新鲜产物（`_release/js/fist-mbt.js`），
但**仓内这份快照没有任何守卫覆盖**——`check_release_asset_names` 明确不扫 dist。

**内容面（BUG-428，high —— 本格是这次事故的直接产物）**：
2026-10-26 实测：修复 commit `72986aa7`（20:40，BUG-417）落地后，`dist/fist-mbt.js` 是 **Oct 24 06:16**
的旧构建，而**本尺打的是 `PASS 快照版本 0.3.10 == moon.mod 0.3.10`** —— 版本对得上，代码是旧的。
代价是一次误判：调用方被 Omega 门拦下后认定「判定逻辑有缺陷」，查了 40 分钟。
⇒ 加一格内容面：快照正文里必须能找到 `KEY_SYMBOLS` 每条符号的**调用形**；缺则红，并点名
**「版本对但代码旧」**（这一句是本次事故的确诊语句，不许被"版本 PASS"盖住）。
探针从 `scripts/_deployment_symbols.py` 取（与 `check_deployment_freshness.py` **同一真源**，不抄第二份表）：
容忍 MoonBit 的 `_`→`__` 名字变形、且要求命中后紧跟 `(`（裸 substring 在**新鲜**产物上也会 0 命中，见该模块实测一）。

判定：
  版本面：快照内嵌版本 != moon.mod ⇒ rc=1（对用户而言"版本说谎"是硬伤）；
  内容面：版本对但缺探针符号 ⇒ rc=1（"版本对但代码旧"）；两面都过 ⇒ rc=0；
  读不到版本 / 文件缺失 ⇒ rc=2（判据无法自证，不冒用 1）。
刷新用 `python scripts/refresh_dist.py`（构建 + patch_esm_main + 拷贝）。
"""
import io
import os
import re
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from _deployment_symbols import (  # noqa: E402 — 同目录共享模块（`_` 前缀，豁免登记）
    KEY_SYMBOLS,
    count_calls,
    missing_symbols,
)

ROOT = os.path.normpath(os.path.join(HERE, ".."))
DIST = os.path.join(ROOT, "dist", "fist-mbt.js")
VERSION_RE = re.compile(r'project__version = "([0-9]+\.[0-9]+\.[0-9]+)"')


def moon_version(root=ROOT):
    p = os.path.join(root, "moon.mod")
    if not os.path.isfile(p):
        return None
    m = re.search(r'version\s*=\s*"([^"]+)"', io.open(p, encoding="utf-8").read())
    return m.group(1) if m else None


def dist_versions(text):
    """快照里出现的所有内嵌版本（去重保序）。纯函数，selftest 直接喂合成文本。"""
    seen = []
    for v in VERSION_RE.findall(text or ""):
        if v not in seen:
            seen.append(v)
    return seen


def judge(text, want):
    """版本面。返回 (rc, 说明)。纯函数：
    0 = 快照版本 == moon.mod；1 = 快照版本落后/不一致；2 = 快照里读不到版本（判据无样本）。
    """
    got = dist_versions(text)
    if not want:
        return 2, "moon.mod 读不到 version —— 判据没有基线，拒绝出结论"
    if not got:
        return 2, "快照里读不到 project__version —— 判据没有样本，拒绝出结论"
    if got == [want]:
        return 0, "快照版本 %s == moon.mod %s" % (got[0], want)
    return 1, "快照版本 %s != moon.mod %s（照 shim 文档连过去的人会拿到旧版本/旧工具集）" % (
        "/".join(got), want)


def judge_content(text, symbols=KEY_SYMBOLS):
    """内容面。返回 (rc, 说明)。纯函数：
    0 = 探针符号全部有调用形；1 = 缺符号（**版本对但代码旧**）；2 = 空样本（拒绝出结论）。
    """
    if not text:
        return 2, "快照正文为空 —— 判据没有样本，拒绝出结论"
    missing = missing_symbols(text, symbols)
    if missing:
        return 1, "缺 %s（**版本对但代码旧** —— BUG-428 的形状：只比版号的守卫在这里是绿的）" % (
            " / ".join(missing))
    return 0, "%d 条探针全部有调用形（%s）" % (
        len(symbols), " / ".join(s.name for s in symbols))


def judge_snapshot(text, want, symbols=KEY_SYMBOLS):
    """两面合成（main 用的就是它，自检也考它 —— 判例-29：测的是实现路径）。返回 (rc, 行列表)。"""
    rc, why = judge(text, want)
    if rc != 0:
        return rc, ["版本面：%s" % why]
    lines = ["版本面：%s" % why]
    crc, cwhy = judge_content(text, symbols)
    lines.append("内容面：%s" % cwhy)
    return crc, lines


def selftest():
    _entry_probe()
    cells = []

    def cell(name, got, want):
        cells.append((name, got == want, "got=%r want=%r" % (got, want)))

    # ---- 版本面 ----
    cell("versions-parse", dist_versions('x\nproject__version = "0.3.10";\ny'), ["0.3.10"])
    cell("versions-dedup", dist_versions('a project__version = "0.3.9"; b project__version = "0.3.9";'), ["0.3.9"])
    cell("versions-multi", dist_versions('project__version = "0.3.9"; project__version = "0.3.10";'),
         ["0.3.9", "0.3.10"])
    cell("judge-same", judge('project__version = "0.3.10";', "0.3.10")[0], 0)
    cell("judge-stale-is-1", judge('project__version = "0.3.9";', "0.3.10")[0], 1)
    cell("judge-mixed-is-1", judge('project__version = "0.3.9"; project__version = "0.3.10";', "0.3.10")[0], 1)
    cell("judge-no-sample-is-2", judge("nothing here", "0.3.10")[0], 2)
    cell("judge-no-baseline-is-2", judge('project__version = "0.3.10";', None)[0], 2)

    # ---- 内容面（BUG-428）：变异对照 + 变形容忍 + 字面量不喂绿 ----
    sym = (KEY_SYMBOLS[0],)
    fresh = 'project__version = "0.3.10";\nfunction _M0FP411x14omega__orphan__of__archived__parent(t) {}\n'
    plain = 'project__version = "0.3.10";\nfunction omega_orphan_of_archived_parent(t) {}\n'
    stale = 'project__version = "0.3.10";\nfunction something_else(t) {}\n'
    literal = 'project__version = "0.3.10";\n{"name":"omega_orphan_of_archived_parent","ok":1}\n'
    cell("content-fresh-mangled-is-0", judge_content(fresh, sym)[0], 0)
    cell("content-fresh-plain-is-0", judge_content(plain, sym)[0], 0)
    cell("content-stale-is-1", judge_content(stale, sym)[0], 1)
    cell("content-string-literal-is-1", judge_content(literal, sym)[0], 1)
    cell("content-empty-is-2", judge_content("", sym)[0], 2)
    cell("count-calls-mangled", count_calls(fresh, sym[0].name), 1)

    # ---- 两面合成（事故确诊句：版本 PASS ≠ 代码新）----
    cell("snapshot-both-ok-is-0", judge_snapshot(fresh, "0.3.10", sym)[0], 0)
    cell("snapshot-version-ok-code-old-is-1", judge_snapshot(stale, "0.3.10", sym)[0], 1)
    rc, lines = judge_snapshot(stale, "0.3.10", sym)
    cells.append(("snapshot-names-code-old", any("版本对但代码旧" in ln for ln in lines),
                  "lines=%r" % (lines,)))
    cell("snapshot-version-bad-is-1", judge_snapshot(stale, "0.3.9", sym)[0], 1)
    cell("snapshot-no-version-is-2", judge_snapshot("no version here", "0.3.10", sym)[0], 2)

    bad = [(n, w) for n, ok, w in cells if not ok]
    if bad:
        print("SELFTEST FAIL：")
        for n, w in bad:
            print("  - %s：%s" % (n, w))
        return 1
    print("SELFTEST OK（%d 格：版本解析去重 3 档 + 版本判定 5 档 + 内容面 6 档 + 两面合成 5 档，全部真断言）"
          % len(cells))
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


def main():
    unknown = [a for a in sys.argv[1:] if a.startswith("--") and a != "--selftest"]
    if unknown:
        print("FATAL 未知参数：%s（本尺只接受 --selftest）" % " ".join(unknown))
        sys.exit(2)
    # ↑ 严格参数面（R65）：未知旗标不再被静默忽略（拼错 --selftest 会假绿）
    if "--selftest" in sys.argv[1:]:
        return selftest()
    if not os.path.isfile(DIST):
        print("FATAL 找不到 dist/fist-mbt.js —— 判据无样本，拒绝报绿")
        return 2
    text = io.open(DIST, encoding="utf-8", errors="replace").read()
    rc, lines = judge_snapshot(text, moon_version())
    tag = {0: "PASS", 1: "FAIL", 2: "FATAL"}[rc]
    print("%s dist 快照：" % tag)
    for line in lines:
        print("  %s" % line)
    if rc == 1:
        print("  刷新（一条命令，重建+注入 ESM shim+拷贝）：python scripts/refresh_dist.py")
        print("  注意：当前 moonc 世代产出的 bundle 比仓内快照大（实测 release 108k 行 vs 快照 83k 行），"
              "刷新会带来大 diff 属预期——快照本就该由发布流程产出。")
    return rc


if __name__ == "__main__":
    sys.exit(main())
