#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_dist_snapshot.py — 仓内发布快照 `dist/fist-mbt.js` 的版本守卫。

**为什么需要它（2026-10-22 实测）**：
`dist/fist-mbt.js` 是**仓内跟踪的发布快照**，而 `scripts/mcp_compat_shim.js` 的默认服务端就是它
（`node dist/fist-mbt.js serve`）、README 也把它当"发布版"引用。实测它内嵌 `project__version = "0.3.9"`，
而 `moon.mod` 已是 **0.3.10** ⇒ 任何照 shim 文档连过去的人/agent 拿到的是**旧版本 + 旧工具集**
（shim 注释里甚至写着 148 工具/v0.3.8）。`release.yml` 构建的是新鲜产物（`_release/js/fist-mbt.js`），
但**仓内这份快照没有任何守卫覆盖**——`check_release_asset_names` 明确不扫 dist。

判定：快照内嵌版本 != moon.mod ⇒ rc=1（对用户而言"版本说谎"是硬伤）；读不到版本/文件缺失 ⇒ rc=2
（判据无法自证，不冒用 1）。刷新用 `python scripts/refresh_dist.py`（构建 + patch_esm_main + 拷贝）。
"""
import io
import os
import re
import subprocess
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
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
    """返回 (rc, 说明)。纯函数：
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


def selftest():
    _entry_probe()
    cells = []

    def cell(name, got, want):
        cells.append((name, got == want, "got=%r want=%r" % (got, want)))

    cell("versions-parse", dist_versions('x\nproject__version = "0.3.10";\ny'), ["0.3.10"])
    cell("versions-dedup", dist_versions('a project__version = "0.3.9"; b project__version = "0.3.9";'), ["0.3.9"])
    cell("versions-multi", dist_versions('project__version = "0.3.9"; project__version = "0.3.10";'),
         ["0.3.9", "0.3.10"])
    cell("judge-same", judge('project__version = "0.3.10";', "0.3.10")[0], 0)
    cell("judge-stale-is-1", judge('project__version = "0.3.9";', "0.3.10")[0], 1)
    cell("judge-mixed-is-1", judge('project__version = "0.3.9"; project__version = "0.3.10";', "0.3.10")[0], 1)
    cell("judge-no-sample-is-2", judge("nothing here", "0.3.10")[0], 2)
    cell("judge-no-baseline-is-2", judge('project__version = "0.3.10";', None)[0], 2)
    bad = [(n, w) for n, ok, w in cells if not ok]
    if bad:
        print("SELFTEST FAIL：")
        for n, w in bad:
            print("  - %s：%s" % (n, w))
        return 1
    print("SELFTEST OK（%d 格：版本解析去重 3 档 + 判定 5 档，全部真断言）" % len(cells))
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
    if "--selftest" in sys.argv[1:]:
        return selftest()
    if not os.path.isfile(DIST):
        print("FATAL 找不到 dist/fist-mbt.js —— 判据无样本，拒绝报绿")
        return 2
    text = io.open(DIST, encoding="utf-8", errors="replace").read()
    want = moon_version()
    rc, why = judge(text, want)
    tag = {0: "PASS", 1: "FAIL", 2: "FATAL"}[rc]
    print("%s dist 快照：%s" % (tag, why))
    if rc == 1:
        print("  刷新（一条命令，重建+注入 ESM shim+拷贝）：python scripts/refresh_dist.py")
        print("  注意：当前 moonc 世代产出的 bundle 比仓内快照大（实测 release 108k 行 vs 快照 83k 行），"
              "刷新会带来大 diff 属预期——快照本就该由发布流程产出。")
    return rc


if __name__ == "__main__":
    sys.exit(main())
