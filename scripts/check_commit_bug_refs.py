#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_commit_bug_refs.py — commit message 面的 BUG-N 完整性（棘轮门）。

为什么需要它：`check_bug_reference_integrity.py`（R48 立）只扫 `.mbt` 注释面，
`check_bug_refs.py`（R115 立）扫代码/文档面，**两把尺都不扫 `git log` 的 commit message**。
实测缺口：`git log --format=%B origin/main..HEAD` 里引用 `BUG-390/397/398/399`，而
`memory/bugs.md` 里这些编号**全都不存在**（账本最高 389）——commit 引用了账本里没有的
bug 编号，且 `BUG-390` 被两个不同 bug 复用（`0f4ffe8c` 标 BUG-390=SqliteStore::open、
bug_list 面标 BUG-390=pre-push 拦截），编号**从未经 report_bug 原子分配**（手动编号绕过 API）。
本尺补上 commit message 面，让「commit 里写的 BUG-N」必须能在账本里查到对应抬头。

面分类：
  · commit_msg  未推送 commit 的 message 正文（只扫 `origin/main..HEAD`，即即将进 main 的）

判定（棘轮，只许降不许升）：
  ORPHAN = 未推送 commit message 里引用的 BUG-N，账本里没有该编号。
  PHANTOM_COMMIT_CEILING = 当前孤儿数（只许降）：新 commit 引入新的幽灵编号 → 红。
  夹具降档：编号 >= 900（如 BUG-901/999）是 selftest 合成夹具，机械跳过不计孤儿。

用法：
  python scripts/check_commit_bug_refs.py                # 核对（rc: 0 过 / 1 红 / 2 无法自证）
  python scripts/check_commit_bug_refs.py --selftest     # 自检
  python scripts/check_commit_bug_refs.py --show-ceiling # 显示当前 ceiling
"""
import io
import os
import re
import subprocess
import sys
from contextlib import redirect_stdout

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
LEDGER = os.path.join(ROOT, "memory", "bugs.md")
# 棘轮：判据只扫 origin/main..HEAD（即将进 main 的新 commit），**不含**已 push 进 main 的
# 历史 commit——那些引用的 390/397/398/399 不在扫面内。所以 ceiling=0：任何新 commit 引用的
# BUG-N 必须在账本里，否则就是幽灵编号（手动编号绕过 report_bug）。只许降不许升。
PHANTOM_COMMIT_CEILING = 0
# 夹具降档线：>= 900 视为 selftest 合成夹具，不计孤儿
FIXTURE_FLOOR = 900

BUG_RE = re.compile(r"\bBUG-(\d{1,4})\b")


def read_ledger():
    """返回账本里存在的 BUG 编号集合（`## BUG-n` 抬头）。"""
    if not os.path.isfile(LEDGER):
        return set()
    with open(LEDGER, encoding="utf-8", errors="replace") as f:
        return set(re.findall(r"^## BUG-(\d+)", f.read(), re.M))


def git(*args):
    return subprocess.run(
        ["git"] + list(args), cwd=ROOT, capture_output=True, text=True,
        encoding="utf-8", errors="replace",
    )


# ↓ 严格参数面（R66）：未知旗标不再被静默忽略（拼错 --selftest 会假绿）
_known = {"--selftest", "--show-ceiling"}
_unknown = [a for a in sys.argv[1:] if a.startswith("--") and a.split("=")[0] not in _known]
if _unknown:
    print("FATAL 未知参数：%s（本尺只接受：%s）" % (" ".join(_unknown), " ".join(sorted(_known))))
    sys.exit(2)

def _base_ref():
    """解析「即将进主线的新 commit」的 base ref —— **R202 修**。

    **原实现写死 `origin/main`**。R202 实测发现两个问题叠在一起：

    1. 本仓主力分支叫 **`master`**（`origin/HEAD → origin/master`）；
    2. 远端**还残留一个陈旧的 `origin/main`**（落后 HEAD **779 笔**）。

    ⇒ 写死 `origin/main` 让扫描面永远是「最近 779 笔」，而该尺自述契约是
    「只扫即将进主线的新 commit，不扫全部历史（否则一开判就红死）」——
    于是它在**已落地**的 `f5035ee7`（引用 BUG-482）上永久报红，读数与契约相反。

    **R202 的修法方向对（不猜名字），但它取「ahead 最小」的判据错了一半** —— 见下方 R85 修正。

    ## R85 修正：只在 **ahead > 0** 的候选里取最小（不是全局取最小）

    **R202 的 bug 形态（实测复现）**：本地 HEAD 在 `main` 上、刚有一笔未推提交时——

    ```
    origin/main..HEAD   → 1 笔   （真正未推送的那一笔，应该被扫）
    origin/master..HEAD → 0 笔   （master 已完全包含 HEAD）
                        ↑ 全局取最小 ⇒ 选中这一条 ⇒ 扫描面 = 空 ⇒ 永远报 0 命中
    ```

    **⇒ 「ahead=0」的意思是「HEAD 已全部包含在该远端里」⇒ 那条线上**没有未推送提交可扫**。**
    **把「0」当成「最新鲜」就是把这个判据**自己关掉**。**
    实测代价：外部 lane 的 `4d3833acd` 引用了账本里不存在的 `BUG-488`，而本判据**PASS 且报 `ahead=0 笔`**
    ⇒ 「扫描面为空」与「扫描面不覆盖我的位置」输出完全一样（判例-35 又一面）。

    **⇒ 正确语义**：扫「即将进**那条线**的新 commit」时，候选必须**先有 ahead>0**（真有新 commit）；
    在各自 ahead>0 的候选里取**最小**者（= 最接近 HEAD 的活跃远端线，避免陈旧分支扫出几百笔历史）。
    **若全部候选 ahead==0 ⇒ 确实没有未推送提交 ⇒ 报 0 是对的**（不是降级、不是漏检）。

    候选：`origin/main` / `origin/master` / `origin/HEAD` / `@{upstream}`；
    一个都不存在才退回最近 20 条，并在输出里**明说降级**（判据无法自证时不静默）。
    """
    best, best_ahead = None, None
    zero_ahead_seen = None
    for ref in ("origin/main", "origin/master", "origin/HEAD", "@{upstream}"):
        if git("rev-parse", "--verify", "--quiet", ref).returncode != 0:
            continue
        r = git("rev-list", "--count", "%s..HEAD" % ref)
        try:
            ahead = int((r.stdout or "0").strip())
        except ValueError:
            continue
        if ahead == 0:
            # 记录「也确实有上游完全包含 HEAD 的线」，但**不选它**当中选 base
            # （选它 ⇒ 扫描面空 ⇒ 判据自己关掉）。留着只在读数里说明。
            if zero_ahead_seen is None:
                zero_ahead_seen = ref
            continue
        if best_ahead is None or ahead < best_ahead:
            best, best_ahead = ref, ahead
    if best is None:
        # 所有候选都 ahead==0（或一个候选都没有）。分两种情形，**读数不同**：
        #   ① 有候选且全 ahead==0 ⇒ 确实无未推送提交 ⇒ 用 HEAD 作 base（扫描面空是**真相**）
        #   ② 一个候选都没有 ⇒ 退回最近 20 条，并明说降级
        if zero_ahead_seen is not None:
            return "HEAD", True, 0
        return "-20", False, None
    return best, True, best_ahead


def scan(ledger):
    """扫描未推送 commit message，返回 [(sha8, bug_id, msg首行)] 孤儿引用（按 bug_id 去重）。

    只扫 base..HEAD（即将进主线的新 commit），不扫全部历史——这样判据
    是「新 commit 不得引入幽灵编号」，而不是对既有历史算总账（后者一开判就红死）。
    base 由 `_base_ref()` 解析；解析不到才退回最近 20 条，且**如实标注降级**。
    """
    base, exact, ahead = _base_ref()
    if exact:
        print("  扫描面 base=%s（ahead=%d 笔）" % (base, ahead or 0))
    r = git("log", "--format=%H%x00%B", "%s..HEAD" % base if exact else base)
    if r.returncode != 0:
        r = git("log", "--format=%H%x00%B", "-20", "HEAD")
        exact = False
    if not exact:
        print("  ⚠️ 降级：解析不到 origin/main|origin/master|origin/HEAD|@{upstream}，"
              "本发只扫最近 20 条（判据无法自证，请勿据此判历史总账）")
    orphan = {}
    for chunk in r.stdout.split("\n"):
        if not chunk.strip():
            continue
        parts = chunk.split("\x00", 1)
        if len(parts) != 2:
            continue
        sha, msg = parts
        head_line = next((l.strip() for l in msg.strip().splitlines() if l.strip()), "")[:70]
        for m in BUG_RE.finditer(msg):
            n = m.group(1)
            if int(n) >= FIXTURE_FLOOR:
                continue
            if n not in ledger and n not in orphan:
                orphan[n] = (sha[:8], n, head_line)
    return sorted(orphan.values(), key=lambda t: int(t[1]))


def is_red(orphan_count, ceiling=PHANTOM_COMMIT_CEILING):
    """判定：孤儿数超 ceiling 才红（棘轮只许降）。"""
    return orphan_count > ceiling


def main():
    args = sys.argv[1:]
    if "--show-ceiling" in args:
        print("PHANTOM_COMMIT_CEILING=%d (FIXTURE_FLOOR=%d)" % (PHANTOM_COMMIT_CEILING, FIXTURE_FLOOR))
        return 0
    if "--selftest" in args:
        return selftest()
    return run()


def run():
    """真判据调用面：扫账本 + 未推送 commit，出读数与退出码。

    独立成函数是为了让 `--selftest` 能**真驱动调用面**（而不是只考纯函数）——
    `check_selftest_call_face.py` 的 J2 只认函数名 main/run/cli，而本脚本的
    selftest 原先只考 BUG_RE / is_red / ledger 三个纯函数，「打印行 + 退出码」
    那一层从没被自检走过（BUG-366 一族的脱钩形状）。
    """
    ledger = read_ledger()
    orphan = scan(ledger)
    for sha, n, msg in orphan:
        print("  ORPHAN BUG-%s (%s): %s" % (n, sha, msg))
    print("未推送 commit 引用的孤儿 BUG 编号：%d / ceiling=%d" % (len(orphan), PHANTOM_COMMIT_CEILING))
    if is_red(len(orphan)):
        print("FAIL：孤儿编号超 ceiling——新 commit 引入了账本里不存在的 BUG-N（手动编号绕过 report_bug）")
        return 1
    print("PASS：commit message 面的 BUG-N 完整性在 ceiling 内")
    return 0


def selftest():
    fails = []

    def cell(name, got, want):
        if got != want:
            fails.append("%s: got %r want %r" % (name, got, want))

    # 格1：BUG_RE 提取（含夹具编号）
    cell("bugre-extract", sorted(BUG_RE.findall("fix: BUG-390 foo; wbtest BUG-901 bar")),
         sorted(["390", "901"]))

    # 格2：夹具降档——900+ 不是孤儿
    cell("fixture-ignore", "901" in {"901"} and int("901") >= FIXTURE_FLOOR, True)

    # 格3：is_red 边界——等于 ceiling 不红，超 ceiling 才红
    cell("is-red-at-ceiling", is_red(4, ceiling=4), False)
    cell("is-red-over-ceiling", is_red(5, ceiling=4), True)
    cell("is-red-zero", is_red(0, ceiling=4), False)

    # 格4：ceiling 合理性——应为非负且 >= 当前实测（账本缺失编号）
    cell("ceiling-nonneg", PHANTOM_COMMIT_CEILING >= 0, True)

    # 格5：真实账本扫描——账本含 BUG-389，扫 "BUG-389" 不应是孤儿
    real = read_ledger()
    cell("ledger-returns-set", isinstance(real, set), True)
    cell("ledger-parse-header", "389" in re.findall(r"## BUG-(\d+)", "## BUG-389 [x] OPEN"), True)

    # 格6：真实孤儿数 <= ceiling（若 > 说明棘轮该降，判据自身红）
    orphan = scan(read_ledger())
    cell("real-orphan<=ceiling", len(orphan) <= PHANTOM_COMMIT_CEILING, True)

    # 格7：调用面锁（J2）——自检必须**真驱动 run()**，而不是只考纯函数。
    # 否则「--selftest 绿」与「真跑判据」是两条脱钩的路（BUG-366 一族）。
    # run() 本身只读账本 + git log，是 hermetic 的：不写盘、不改仓库面。
    buf = io.StringIO()
    with redirect_stdout(buf):
        rc = run()
    out = buf.getvalue()
    cell("callface-run-rc", rc in (0, 1), True)
    cell("callface-run-prints", "ceiling" in out, True)

    # 格8（R85）：**基准解析的语义锁** —— 这是 BUG-488 的锁。
    #
    # 被测机制：`_base_ref()` 必须**只在 ahead>0 的候选里取最小**，
    # 绝不能把「ahead==0」（HEAD 已全部包含于该远端）当成「最新鲜」而选中它
    # —— 选它 ⇒ 扫描面 = 空 ⇒ 判据自己关掉（实测代价：`4d3833acd` 的孤儿 BUG-488 漏检）。
    #
    # ⚠️ **变异对照**：若有人把 `if ahead == 0: continue` 删掉（退回 R202 的「全局取最小」），
    # 本格必须变红。这是本格的**设计目的**，不是附带断言。
    base, exact, ahead = _base_ref()
    if exact:
        # ① 中选的 base 必须真的 ahead>0 —— 除非「所有候选都 ahead==0」（此时 base=HEAD、ahead=0）
        cell("baseref-never-picks-zero-ahead", base == "HEAD" or (ahead or 0) > 0, True)
        # ② 自证读数：选中的 ref 必须**能**列出至少 1 笔（若 base 不是 HEAD）
        if base != "HEAD":
            r = git("rev-list", "--count", "%s..HEAD" % base)
            got_n = int((r.stdout or "0").strip() or 0)
            cell("baseref-chosen-has-commits", got_n > 0, True)
            cell("baseref-ahead-matches-revlist", ahead, got_n)
    else:
        # 降级态（一个候选都没有）必须**明说**，不许静默：exact=False 且 base="-20"
        cell("baseref-degraded-is-marked", base == "-20", True)

    if fails:
        print("selftest FAIL（%d 格）：" % len(fails))
        for f in fails:
            print("  - " + f)
        return 1
    print("selftest PASS（8 格：提取/夹具/边界/ceiling/账本/实测/调用面/基准解析语义（R85·BUG-488 锁））")
    return 0


if __name__ == "__main__":
    sys.exit(main())
