#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/badge_anchor.py — 「测试数快照」的源码面锚点（判例-25 的共用真源）。

## 为什么要有这个模块（不是为抽而抽）

`check_badge.py` 与 `check_test_sync.py` 吃的是同一类真源：
`temp/` 下手跑一次的 `moon test` 日志快照。判例-25 实测的病灶是——

    temp/pt27.log  →  Total tests: 1455   （2026-10-24 19:54 手跑一次，之后再无人跑）
    README 徽章    →  tests-1455%2F1455
    真实全仓       →  1457
    check_badge    →  PASS 绿              ← 两个都停在旧值 ⇒「一致」被读成「正确」

**判据只能证明「文档 == 快照」，从没能证明「文档 == 现实」。** 两把尺都踩这一条。

两把尺各自再实现一份锚点 = 两份口径必然漂（一处改口径、另一处没跟上，
就会出现「同一份快照，一把尺说新鲜、另一把说过期」）。所以锚点只在这里定义一次。

## 锚点形状

`<snapshot>.src` 一行：

    code=<最近一笔改动源码面的提交 sha>@<源码面 porcelain 摘要>

**只覆盖源码语义面**：`*.mbt` / `*.pkg` / `*.mod` / `moon.mod`。
文档（`*.md` 等）改动**不**让锚点失效——改文档不会改测试数，让快照失效是误报。

## 刻意不比 mtime

mtime 是**文件系统事实**，不是**代码事实**：
- 文档提交会刷新仓库状态 ⇒ mtime 判「新鲜」而代码没变过；
- `touch` 一下旧快照 ⇒ mtime 判「新鲜」而内容是旧的。
判据的真源若是文件系统事实，必须验证它是否代表语义事实（判例-25 的正文）。

## 退出码（只给 `--selftest` / `--show` 两个面）

    0 = 自证通过 / 取到了锚点
    1 = 自证失败（某格不符预期）
    2 = 判据无法自证（git 不可用 / 不在仓库内）

用法：
    python scripts/badge_anchor.py --selftest        # 考这把小尺自己
    python scripts/badge_anchor.py --show [<snapshot>]  # 打当前锚点（有快照则对比两侧）
"""
import hashlib
import os
import subprocess
import sys
from git_env import isolated_git_env

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 为什么进这条点名账而不是裸进电池（schema-reserved 同款点名预留律）：
# 本模块是**被 import 的库**（`check_badge.py` / `check_test_sync.py` 调它），
# 它的自证面由这两把尺的 selftest 与 `badge_anchor.py --selftest` 覆盖；
# 裸进电池会让同一份锚点自证在电池里跑两遍（本模块 + 两把尺各一次），
# 而电池是「每格一次」的只读面。`run_guards` 的 `EXEMPT_RULES` 已按此理由点名。

# 源码语义面：只有这些改动才可能改变测试数。文档改动一律不影响锚点。
CODE_PATTERNS = ("*.mbt", "*.pkg", "*.mod", "moon.mod")
ANCHOR_SUFFIX = ".src"
ANCHOR_PREFIX = "code="


def _git(args, cwd=None):
    """只读 git 调用（不经 shell）。失败返回 (rc, "", err)，由调用方判 2 而不是崩。"""
    p = subprocess.run(["git"] + list(args), cwd=cwd or ROOT, capture_output=True,
                       text=True, encoding="utf-8", errors="replace",
                       env=isolated_git_env())
    return p.returncode, (p.stdout or ""), (p.stderr or "")


def code_fingerprint(cwd=None):
    """源码语义面的指纹。返回 (head_sha, porcelain_digest)；git 不可用返回 ("", "")。

    纯函数式（只读 git），不做任何判断——判断在 `anchor_problems` 里，
    这样 selftest 能分别考「算得对」与「判得对」。
    """
    rc, out, _ = _git(["log", "-1", "--format=%H", "--"] + list(CODE_PATTERNS), cwd=cwd)
    if rc != 0:
        return "", ""
    head = out.strip()
    rc, out, _ = _git(["status", "--porcelain", "--"] + list(CODE_PATTERNS), cwd=cwd)
    if rc != 0:
        return head, "STATUS-FAILED"
    digest = hashlib.sha256(out.encode("utf-8", "replace")).hexdigest()[:16]
    return head, digest


def anchor_path(snapshot_path):
    return snapshot_path + ANCHOR_SUFFIX


def anchor_line(head, digest):
    """锚点文件的一行。写盘与比对共用这一个形状，避免两处拼串漂移。"""
    return ANCHOR_PREFIX + "%s@%s" % (head or "?", digest or "?")


def current_anchor(cwd=None):
    """现在的锚点行；取不到返回空串（调用方按「无法自证」处理，不猜）。"""
    head, digest = code_fingerprint(cwd=cwd)
    return anchor_line(head, digest) if head else ""


def write_anchor(snapshot_path, cwd=None):
    """把当前源码面指纹写到 `<snapshot>.src`。成功返回写入的行，失败返回空串。"""
    line = current_anchor(cwd=cwd)
    if not line:
        return ""
    try:
        with open(anchor_path(snapshot_path), "w", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        return ""
    return line


def read_anchor(snapshot_path):
    """读 `<snapshot>.src`。缺失/坏形状 ⇒ 空串（调用方按陈旧处理，不猜）。"""
    p = anchor_path(snapshot_path)
    if not os.path.isfile(p):
        return ""
    try:
        with open(p, encoding="utf-8") as f:
            line = f.readline().strip()
    except OSError:
        return ""
    return line if line.startswith(ANCHOR_PREFIX) else ""


def anchor_problems(snapshot_path, cwd=None):
    """快照新鲜度判据。返回 (problems, info)；problems 空 == 同源。

    每项是 (kind, text)，kind 恒为 "reject"——**「快照过期」永远不是违例红**：
    那是「判据证明不了现实」（rc=2，诚实沉默），不是「文档写错了」（rc=1）。
    两件事必须在退出码上分开，否则「我量不出来」会被读成「你写错了」。
    """
    stored = read_anchor(snapshot_path)
    now = current_anchor(cwd=cwd)
    info = {"anchor": stored, "now": now}
    if not now:
        return [("reject", "REJECT 源码面指纹取不到（git 不可用 / 不在仓库内）⇒ rc=2，不猜")], info
    if not stored:
        return [("reject",
                 "REJECT SNAPSHOT-STALE: 快照 %s 没有源码面锚点（缺 %s）"
                 " ⇒ 无从证明它与现在的代码同源。用 `--fresh` 重跑一次生成锚点；"
                 "rc=2，不冒用违例红"
                 % (snapshot_path, os.path.basename(anchor_path(snapshot_path))))], info
    if stored != now:
        return [("reject",
                 "REJECT SNAPSHOT-STALE: 快照源码面 %s ≠ 现在 %s"
                 " ⇒ 本判据只能证明「文档 == 快照」，不能证明「文档 == 现实」⇒ rc=2，拒绝出绿。"
                 "用 `--fresh` 重跑一次" % (stored, now))], info
    return [], info


# ── 自证 ────────────────────────────────────────────────────────────────────


def selftest():
    """考这把小尺自己：算得对 + 判得对 + 只比源码面。

    A1~A3 走**真仓库**（只读 git，零写入）：现状面锚点必须取得到、且连续两次相同（确定性）。
    A4 是判例-25 的关键反证：**只改文档不改锚点** —— 用 cwd 指向一个只动过 .md 的
    git 视图做不到（会碰真仓），所以这里换成**口径断言**：`CODE_PATTERNS` 里不得出现
    `*.md`（模式串来自被测模块本身，靠 import 读，不靠源码文本匹配——判例-30）。
    A5~A7 走临时目录合成锚点文件，考 read/write/anchor_problems 三面。
    """
    import tempfile

    cells, fails = [], []

    def cell(name, got, want):
        cells.append(name)
        if got != want:
            fails.append("%s: got=%r want=%r" % (name, got, want))

    # A1 真仓库取得到锚点
    real = current_anchor(cwd=ROOT)
    cell("A1 真仓库锚点可取得", bool(real) and real.startswith(ANCHOR_PREFIX), True)
    # A2 确定性：连取两次相同（判据不能自己抖）
    cell("A2 锚点确定性", current_anchor(cwd=ROOT), real)
    # A3 形状：code=<sha>@<16 hex>
    parts = real.replace(ANCHOR_PREFIX, "").split("@")
    cell("A3 锚点形状两段", len(parts), 2)
    cell("A3 sha 长 40", len(parts[0]), 40)
    cell("A3 摘要长 16", len(parts[1]), 16)
    # A4 口径（判例-25 的正文）：源码面模式里不许有文档后缀
    cell("A4 源码面不含 .md", any(p.endswith(".md") for p in CODE_PATTERNS), False)
    cell("A4 源码面含 .mbt", any(p.endswith(".mbt") for p in CODE_PATTERNS), True)

    with tempfile.TemporaryDirectory() as td:
        snap = os.path.join(td, "snap.log")
        with open(snap, "w", encoding="utf-8") as f:
            f.write("Total tests: 1, passed: 1, failed: 0\n")
        # A5 缺锚点 ⇒ reject
        probs, _ = anchor_problems(snap, cwd=ROOT)
        cell("A5 缺锚点必 reject", [k for k, _ in probs], ["reject"])
        # A6 写过锚点 ⇒ 同源
        wrote = write_anchor(snap, cwd=ROOT)
        cell("A6 写锚点成功", wrote, real)
        probs6, info6 = anchor_problems(snap, cwd=ROOT)
        cell("A6 同源时无问题", probs6, [])
        # A7 旧锚点 ⇒ reject 且两侧都点名
        with open(anchor_path(snap), "w", encoding="utf-8") as f:
            f.write(ANCHOR_PREFIX + "0" * 40 + "@0123456789abcdef\n")
        probs7, info7 = anchor_problems(snap, cwd=ROOT)
        cell("A7 旧锚点必 reject", [k for k, _ in probs7], ["reject"])
        cell("A7 点名旧值", "0" * 40 in probs7[0][1] if probs7 else False, True)
        cell("A7 点名现值", info7["now"].replace(ANCHOR_PREFIX, "").split("@")[0] in
             (probs7[0][1] if probs7 else ""), True)
        # A8 坏形状锚点（不认）⇒ 按缺失处理
        with open(anchor_path(snap), "w", encoding="utf-8") as f:
            f.write("garbage\n")
        cell("A8 坏形状按缺失", read_anchor(snap), "")

    # A9~A11（判例-25 的核心反证）：**真造一个临时 git 仓**，证明锚点只看源码语义面。
    # 不用 mtime、不碰真仓——用临时仓 + 剥离 GIT_DIR 一族的隔离环境（R44 踩过的坑：
    # 夹具的 git 会越过 cwd 去操作外层真仓）。
    env = dict(os.environ)
    for k in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY",
              "GIT_COMMON_DIR", "GIT_PREFIX", "GIT_NAMESPACE"):
        env.pop(k, None)
    env["GIT_CONFIG_NOSYSTEM"] = "1"

    def g(args, cwd):
        return subprocess.run(["git"] + list(args), cwd=cwd, capture_output=True,
                              text=True, encoding="utf-8", errors="replace",
                              env=env).returncode

    with tempfile.TemporaryDirectory() as td2:
        cell("A9 夹具仓 init", g(["init", "-q"], td2), 0)
        g(["config", "user.email", "t@t"], td2)
        g(["config", "user.name", "t"], td2)
        with open(os.path.join(td2, "a.mbt"), "w", encoding="utf-8") as f:
            f.write("fn a() {}\n")
        with open(os.path.join(td2, "README.md"), "w", encoding="utf-8") as f:
            f.write("doc\n")
        g(["add", "."], td2)
        cell("A9 夹具仓 commit", g(["commit", "-qm", "base"], td2), 0)
        base = current_anchor(cwd=td2)
        cell("A9 夹具仓锚点可取得", bool(base), True)
        # A10 只改文档 ⇒ 锚点**不变**（这是判例-25 最关键的反证）
        with open(os.path.join(td2, "README.md"), "w", encoding="utf-8") as f:
            f.write("doc changed\n")
        cell("A10 只改 .md 锚点不变", current_anchor(cwd=td2), base)
        # A11 改源码 ⇒ 锚点**必变**
        with open(os.path.join(td2, "a.mbt"), "w", encoding="utf-8") as f:
            f.write("fn a() { 1 }\n")
        cell("A11 改 .mbt 锚点必变", current_anchor(cwd=td2) != base, True)

    print("SELFTEST %s (%d cells: %s)"
          % ("OK" if not fails else "FAIL", len(cells), " / ".join(cells)))
    for f in fails:
        print("SELFTEST FAIL " + f)
    return 0 if not fails else 1


def main(argv):
    if "--selftest" in argv:
        return selftest()
    snap = None
    rest = [a for a in argv if a != "--show"]
    if "--show" in argv and rest:
        snap = rest[0]
    now = current_anchor(cwd=ROOT)
    if not now:
        print("REJECT 源码面指纹取不到（git 不可用 / 不在仓库内）⇒ rc=2")
        return 2
    print("现在源码面：%s" % now)
    if snap:
        stored = read_anchor(snap)
        print("快照锚点　：%s" % (stored or "（缺失）"))
        probs, _ = anchor_problems(snap, cwd=ROOT)
        if probs:
            print(probs[0][1])
            return 1
        print("⇒ 同源")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except SystemExit:
        raise
    except Exception as e:  # noqa: BLE001 — 尺子自己坏了走 4，绝不冒用 1
        sys.stderr.write("ANCHOR RULER BROKEN: %r\n" % e)
        sys.exit(4)
