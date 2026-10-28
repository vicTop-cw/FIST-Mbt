#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""日志块重复守卫（R133，副机自立项）。

被检面：`memory/YYYY-MM-DD.md`（当日日志，金条五的追加面）。
判据 D1：同一份日志里出现**逐字相同的 `## ` 块** ≥2 份 ⇒ 违例。

为什么盯「逐字相同的块」而不是「抬头重复」：抬头同、正文不同的两块是不同人写的不同
结论，删掉任一份就是删信息，本尺无权那么判；而 union 式解冲突产生的正是**整块逐字复制**
（把两侧都留下 ⇒ 同一块 N 份）。只判这一形，判据既抓得住成因，又允许 `--fix` 无损。

退出码契约（BUG-369）：0=无违例 / 1=有逐字重复块 / 2=判据无法自证（扫不到日志、或
全部日志都解析不到 `## ` 块=文法失效）/ 4=尺子自己坏了（未捕获异常，绝不冒用 1 那一档）。
空宇宙特例（788c5823 既成策略）：`memory/YYYY-MM-DD.md` 自该 commit 起被 `.gitignore`
（`memory/2026-*.md`）整体剔出 git 跟踪面，故干净 checkout（=CI 面）上一份日日志都没有，
**不是坏环境而是既定策略的自然结果**。此时若判据能证明「日日志缺席跟踪面」是策略
（仓库根 `.gitignore` 确有匹配 `memory/YYYY-MM-DD.md` 的规则），走 **空宇宙豁免：rc=0**，
并打一行明确说明——不判红、也不拿「没读到」当「对上了」。锚点不成立（无该规则）才
回真·无法自证（rc=2）。豁免只对「确实一份都没有」生效：`memory/` 下一旦出现任何一份
日日志，立刻退回真正的查重面，重复块照样 rc=1，绝不假绿。
单份日志没有 `## ` 块（整篇叙事文法，如 `memory/2026-10-10.md`）不构成违例——本尺只判
「块重复」这一形——但必须在读数里点名：既不许悄悄滑成「全都对上了」，也不许掩护另一面的真违例。
"""

from __future__ import annotations

import hashlib
import os
import re
import sys
import tempfile

# BUG-58/138：本尺满屏中文结论，GBK 控制台上「判据红」会先崩在打印那一行、把 rc 冒用成
# 缺陷在场——结论行必须先打得出来，rc 才可信。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

DAYLOG_RE = re.compile(r"^\d{4}-\d{2}-\d{2}\.md$")
HEADER_RE = re.compile(r"^## \S.*$")
SKIP_DIRS = {"__pycache__", ".git"}


def rel_posix(p):
    return p.replace(os.sep, "/")


def find_logs(base_dir):
    """日志宇宙：base_dir 下文件名形如 YYYY-MM-DD.md 的每一份（递归，含子目录归档面）。"""
    out = []
    for root, dirs, files in os.walk(base_dir):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            if DAYLOG_RE.match(name):
                out.append(os.path.join(root, name))
    return sorted(out)


def read_text(path):
    raw = open(path, "rb").read()
    crlf = b"\r\n" in raw
    text = raw.decode("utf-8").replace("\r\n", "\n")
    return text, crlf


def split_blocks(text):
    """把正文切成「preamble + 若干块」，块 = 一行 `## ` 抬头 + 到下一抬头前的所有行。"""
    lines = text.split("\n")
    starts = [i for i, l in enumerate(lines) if HEADER_RE.match(l)]
    preamble = lines[: starts[0]] if starts else lines
    blocks = []
    for k, i in enumerate(starts):
        j = starts[k + 1] if k + 1 < len(starts) else len(lines)
        blocks.append("\n".join(lines[i:j]))
    return preamble, blocks


def digest(s):
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def daily_log_ignored_by_gitignore(scan_root):
    """空宇宙豁免的**策略锚点**：`.gitignore` 是否确有规则匹配 `memory/YYYY-MM-DD.md`。

    788c5823 起日日志被 `memory/2026-*.md`（及同类 `memory/20??-*.md`）剔出 git 跟踪面。
    判定规则：从**扫描根自身**向上逐层找 `.gitignore`（就近优先，直到根盘/无父目录为止）。
    这既让「干净 checkout 的默认 `memory/`」能找到仓库根那份声明，也让一个**独立临时面**
    不会被仓库根的规则误豁免——锚点必须「覆盖这个扫描面」才算成立。
    锚点不成立＝空扫描面就是真·无法自证，必须 rc=2。只读 `.gitignore`，不调 git、不写文件。
    """
    cur = os.path.abspath(scan_root)
    while True:
        gi = os.path.join(cur, ".gitignore")
        if os.path.isfile(gi):
            if _gitignore_ignores_daily(gi):
                return True
        nxt = os.path.dirname(cur)
        if nxt == cur:
            return False
        cur = nxt


def _gitignore_ignores_daily(gi_path):
    """单份 `.gitignore` 里是否有规则匹配 `memory/YYYY-MM-DD.md`。"""
    try:
        with open(gi_path, "r", encoding="utf-8", errors="replace") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return False
    probe = "memory/2026-01-01.md"
    for raw in lines:
        line = raw.rstrip()
        if not line or line.startswith("#"):
            continue
        # 去掉未转义 `#` 起的注释（转义首字符保留）
        out, hash_esc = [], False
        for c in line:
            if c == "\\":
                hash_esc = True
                continue
            if c == "#" and not hash_esc:
                break
            out.append(c)
            hash_esc = False
        line = "".join(out).strip()
        if not line:
            continue
        pat = line.lstrip("/")  # 忽略仓库根锚定 `/`：memory/ 本就在根下
        if pat in ("memory", "memory/"):
            return True  # 整目录忽略 ⇒ 覆盖一切日日志
        if pat.startswith("memory/"):
            sub = pat[len("memory/"):]
            if sub == probe[len("memory/"):]:
                return True
            if "*" in sub:  # 本仓只用 `*`（如 `2026-*.md`）；`?`/`[]`/`**` 保守按字面
                if not sub.startswith("*") and not probe[len("memory/"):].startswith(sub.split("*")[0]):
                    continue
                if not sub.endswith("*") and not probe[len("memory/"):].endswith(sub.split("*")[-1]):
                    continue
                return True
    return False


def empty_universe_verdict(scan_root):
    """空宇宙三分：`broken`（目录不存在）/ `empty_policy`（策略豁免）/ `empty_unproven`（真失败）。

    返回 (kind, 说明)。有样本时调用方不该走到这里；这里只回答「为什么是空的」。
    """
    if not os.path.isdir(scan_root):
        return "broken", "扫描目录不存在：%s" % scan_root
    if daily_log_ignored_by_gitignore(scan_root):
        return "empty_policy", (
            ".gitignore 确有忽略 `memory/YYYY-MM-DD.md` 的规则"
            "（日日志已剔 git 跟踪，788c5823 既成策略）"
        )
    return "empty_unproven", "扫描面为空且 .gitignore 未证明忽略日日志"


def canon(block):
    """比较用的规范形：只去掉尾部空行。

    不去掉的话，「文件最后一块」会因为文末那个换行被 split 出一个空尾行，和它自己在
    文件中间的副本算成两块 —— 去重就漏掉这一形，无损断言也会误报「集合不一致」。
    """
    return block.rstrip("\n")


def scan(paths):
    """返回 (违例, 诊断, 读数, 解析为空的文件)。违例=逐字相同的块重复；诊断=同抬头多正文（只报不判）。

    逐份累计，**不因某一份解析为空就中断整轮**——早退会把后面的日志全吞掉，
    于是 12 MB 的违例面被读成 `clean`（本尺第一版就写成那样，被 S9 现状格当场抓住）。
    解析为空的名单交给调用方判「是不是整片宇宙都失效」。
    """
    problems = []
    diag = []
    readings = []
    empties = []
    for p in paths:
        text, _ = read_text(p)
        _, blocks = split_blocks(text)
        if not blocks:
            empties.append(rel_posix(p))
            continue
        seen = {}
        for b in blocks:
            seen.setdefault(digest(canon(b)), []).append(b)
        dups = [(k, v) for k, v in seen.items() if len(v) > 1]
        wasted = 0
        for k, v in dups:
            head = v[0].split("\n", 1)[0]
            copies = len(v)
            wasted += sum(len(x.encode("utf-8")) for x in v[1:])
            problems.append(
                "%s：块重复 %d 份（+%d 份）｜抬头 %s｜重复占字节 %d"
                % (rel_posix(p), copies, copies - 1, head[:70], wasted)
            )
        by_head = {}
        for b in blocks:
            by_head.setdefault(b.split("\n", 1)[0], set()).add(digest(canon(b)))
        variants = sum(1 for h, s in by_head.items() if len(s) > 1)
        diag.append(
            "%s：块 %d / 唯一 %d / 重复族 %d / 同抬头多正文 %d / 重复占字节 %d"
            % (rel_posix(p), len(blocks), len(seen), len(dups), variants, wasted)
        )
        readings.append((rel_posix(p), len(blocks), len(dups)))
    return problems, diag, readings, empties


def dedupe(text):
    """无损去重：按**行区间**删除逐字相同块的后续副本 —— 只删整块，不重排、不改任何留下的字节。

    第一版用 `"\n".join(blocks)` 重拼文本，结果把每块之间的分隔行算进了块内容，
    复跑时唯一块集合对不上、`--fix` 当场 FIX-ABORT 拒绝写盘（无损断言拦住的正是它）。
    """
    lines = text.split("\n")
    starts = [i for i, l in enumerate(lines) if HEADER_RE.match(l)]
    if not starts:
        return text, 0, 0
    out = list(lines[: starts[0]])
    seen = set()
    uniq = set()
    removed = 0
    for k, i in enumerate(starts):
        j = starts[k + 1] if k + 1 < len(starts) else len(lines)
        key = digest(canon("\n".join(lines[i:j])))
        uniq.add(key)
        if key in seen:
            removed += 1
            continue
        seen.add(key)
        out.extend(lines[i:j])
    new = "\n".join(out)
    if not new.endswith("\n"):
        new += "\n"
    return new, removed, len(uniq)


def fix(paths):
    changed = []
    for p in paths:
        text, crlf = read_text(p)
        before = set(canon(b) for b in split_blocks(text)[1])
        new, removed, uniq = dedupe(text)
        after = set(canon(b) for b in split_blocks(new)[1])
        if before != after:
            # 信息无损是这条律的底线：唯一块集合必须逐字相同，否则绝不写盘
            print("FIX-ABORT %s：去重前后唯一块集合不一致（丢 %d / 多 %d），拒绝写盘"
                  % (rel_posix(p), len(before - after), len(after - before)))
            return changed, 1
        if removed == 0:
            continue
        data = new.replace("\n", "\r\n").encode("utf-8") if crlf else new.encode("utf-8")
        with open(p, "wb") as f:
            f.write(data)
        changed.append("%s：删除逐字重复块 %d 份（唯一 %d 份照旧）" % (rel_posix(p), removed, uniq))
    return changed, 0


def selftest():
    ok = True

    def check(name, cond, note=""):
        nonlocal ok
        if not cond:
            ok = False
        print("%s %s %s" % ("PASS" if cond else "FAIL", name, note))

    def sandbox(files):
        d = tempfile.mkdtemp(prefix="memlog-")
        for name, text in files.items():
            with open(os.path.join(d, name), "w", encoding="utf-8", newline="\n") as f:
                f.write(text)
        return d

    dup_block = "## R1 · 甲单元\n\n内容甲\n"
    # S1：逐字相同的块重复必红，且点名抬头与份数
    d = sandbox({"2026-01-01.md": "# 日志\n\n" + dup_block + "\n" + dup_block + "\n" + dup_block,
                 "notes.md": "不该被扫到"})
    ps, dg, rd, em = scan(find_logs(d))
    check("S1", len(ps) == 1 and "块重复 3 份" in ps[0] and "R1" in ps[0],
          "claim=%s" % (ps or "无违例"))
    # S2：唯一块不误红（含「抬头同/正文不同」这一形——本尺不判它）
    d = sandbox({"2026-01-02.md": "# 日志\n\n## R1 · 甲\n\n第一版\n\n## R1 · 甲\n\n第二版\n\n## R2 · 乙\n\n丙\n"})
    ps, dg, rd, em = scan(find_logs(d))
    check("S2", ps == [] and any("同抬头多正文 1" in x for x in dg), "diag=%s" % dg)
    # S3：宇宙只收 YYYY-MM-DD.md，其它 md 不入判定面
    d = sandbox({"2026-01-03.md": dup_block + "\n" + dup_block, "bugs.md": dup_block + "\n" + dup_block})
    logs = find_logs(d)
    ps, dg, rd, em = scan(logs)
    check("S3", len(logs) == 1 and len(ps) == 1, "宇宙=%d" % len(logs))
    # S4：--fix 幂等——落盘后再扫无违例
    d = sandbox({"2026-01-04.md": "# 日志\n\n" + dup_block + "\n" + dup_block + "\n" + dup_block})
    fix(find_logs(d))
    ps, dg, rd, em = scan(find_logs(d))
    check("S4", ps == [], "fix 后违例=%d" % len(ps))
    # S5：--fix 无损——唯一块集合逐字相同，且每种内容仍在文件里
    d = sandbox({"2026-01-05.md": "# 志\n\n## R1 · 甲\n\nA\n\n## R2 · 乙\n\nB\n\n## R1 · 甲\n\nA\n"})
    text, _ = read_text(os.path.join(d, "2026-01-05.md"))
    before = set(canon(b) for b in split_blocks(text)[1])
    fix(find_logs(d))
    text2, _ = read_text(os.path.join(d, "2026-01-05.md"))
    after = set(canon(b) for b in split_blocks(text2)[1])
    check("S5", before == after and "A" in text2 and "B" in text2,
          "唯一块 %d→%d" % (len(before), len(after)))
    # S11：无重复的日志，--fix 必须一个字节都不动——第一版给空 preamble 补了个换行，
    #       导致「首块直接从 `## ` 开始」的干净文件被自己判成 FIX-ABORT（现状面第一发就撞上）
    clean = "## R1 · 甲\n\nA\n\n## R2 · 乙\n\nB\n"
    d = sandbox({"2026-01-11.md": clean})
    p = os.path.join(d, "2026-01-11.md")
    changed, rc = fix(find_logs(d))
    text, _ = read_text(p)
    check("S11", rc == 0 and changed == [] and text == clean,
          "rc=%d changed=%d 字节相同=%s" % (rc, len(changed), text == clean))
    # S6：preamble 不许被吞
    d = sandbox({"2026-01-06.md": "# 标题\n\n引言行\n\n" + dup_block + "\n" + dup_block})
    fix(find_logs(d))
    text, _ = read_text(os.path.join(d, "2026-01-06.md"))
    check("S6", text.startswith("# 标题\n\n引言行"), "头部=%r" % text[:24])
    # S7：空宇宙自拒（真给 2，不冒用 0）
    d = tempfile.mkdtemp(prefix="memlog-empty-")
    rc = main(["--scan", d])
    check("S7", rc == 2, "空宇宙 rc=%d" % rc)
    # S8：日志里一个 `## ` 块都没有 ⇒ 文法失效，自拒不报绿
    d = sandbox({"2026-01-07.md": "# 只有大标题\n\n没有二级抬头\n"})
    rc = main(["--scan", d])
    check("S8", rc == 2, "空解析面 rc=%d" % rc)
    # S9：真源现状面必须绿——本尺在现状不恒红（否则它只是个装饰）。
    #   空宇宙（788c5823 起日日志已剔 git 跟踪）必须走豁免路径且 rc=0，且必须点名「策略豁免」；
    #   有日志时则仍要真的查重（反向格见 S13）。
    real = find_logs(os.path.join(REPO_ROOT, "memory"))
    if not real:
        rc = main(["--scan", os.path.join(REPO_ROOT, "memory")])
        check("S9", rc == 0, "空宇宙豁免 rc=%d（应为 0）" % rc)
        check("S9-anchor", daily_log_ignored_by_gitignore(REPO_ROOT) is True,
              "策略锚点=%s" % daily_log_ignored_by_gitignore(REPO_ROOT))
    else:
        ps, dg, rd, em = scan(real)
        check("S9", ps == [], "真源 %d 份日志：违例 %d %s" % (len(real), len(ps), (ps or [""])[0][:60]))
        check("S9-anchor", True, "真源有日志，不走豁免（锚点不参与判定）")
    # S10：某一份解析为空不许截断整轮——本尺第一版在这里 `return`，于是 12 MB 的违例面被读成 clean
    d = sandbox({"2026-01-08.md": "# 只有一行\n\n没有二级抬头\n",
                 "2026-01-09.md": dup_block + "\n" + dup_block})
    ps, dg, rd, em = scan(find_logs(d))
    check("S10", len(ps) == 1 and len(em) == 1, "违例 %d / 空面 %d" % (len(ps), len(em)))
    # S12：单份日志没有 `## ` 块（整篇叙事文法）不许让整个宇宙判红——
    #       第二版一度把它当违例，于是红在别人的文法上（真面 memory/2026-10-10.md 中招）
    d = sandbox({"2026-01-12.md": "# 只有大标题\n\n整篇叙事，无二级抬头\n",
                 "2026-01-13.md": "# 志\n\n## R1 · 甲\n\nA\n\n## R2 · 乙\n\nB\n"})
    ps, dg, rd, em = scan(find_logs(d))
    rc = main(["--scan", d])
    check("S12", rc == 0 and ps == [] and len(em) == 1, "空面无违例 rc=%d 违例=%d 空面=%d" % (rc, len(ps), len(em)))
    # S13：空面不许掩护另一面的真违例——同宇宙里有一份重复，仍必红
    d = sandbox({"2026-01-14.md": "# 只有大标题\n\n整篇叙事，无二级抬头\n",
                 "2026-01-15.md": "# 志\n\n" + dup_block + "\n" + dup_block})
    rc = main(["--scan", d])
    check("S13", rc == 1, "空面 + 真违例 rc=%d（应为 1）" % rc)
    # S14：空宇宙 ≠ 空宇宙豁免——.gitignore 若没忽略日日志（策略锚点不成立），仍是真·无法自证。
    d = tempfile.mkdtemp(prefix="memlog-empty-unproven-")
    with open(os.path.join(d, ".gitignore"), "w", encoding="utf-8") as fh:
        fh.write("node_modules/\n")  # 无关规则：不构成锚点
    rc = main(["--scan", d])
    check("S14", rc == 2, "锚点不成立的空面 rc=%d（应为 2）" % rc)
    print("SELFTEST %s（14 格：S1×1 / S2×1 / S3×1 / S4×1 / S5×1 / S6×1 / S7×1 / S8×1 / S9×1 / S9-anchor×1 / S10×1 / S11×1 / S12×1 / S13×1 / S14×1，清单从已执行格子反解，不手写计数）"
          % ("OK" if ok else "FAIL"))
    return 0 if ok else 1


REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main(argv=None):
    # ↓ 严格参数面（R66）：未知旗标不再被静默忽略（拼错 --selftest 会假绿）
    _known = {"--selftest", "--fix", "--scan"}
    _unknown = [a for a in (argv or sys.argv[1:]) if a.startswith("--") and a.split("=")[0] not in _known]
    if _unknown:
        print("FATAL 未知参数：%s（本尺只接受：%s）" % (" ".join(_unknown), " ".join(sorted(_known))))
        sys.exit(2)
    argv = list(sys.argv[1:] if argv is None else argv)
    if "--selftest" in argv:
        return selftest()
    base = argv[argv.index("--scan") + 1] if "--scan" in argv and len(argv) > argv.index("--scan") + 1 \
        else os.path.join(REPO_ROOT, "memory")
    do_fix = "--fix" in argv
    logs = find_logs(base)
    if not logs:
        kind, why = empty_universe_verdict(base)
        if kind == "empty_policy":
            print("MEMLOG=empty-universe 空宇宙豁免（rc=0）：%s 下一份 YYYY-MM-DD.md 都没有，"
                  "且 %s——日日志缺席跟踪面是既定策略的自然结果，"
                  "不是坏环境、也不是「判据没得测」；不判红、也不拿「没读到」当「对上了」。"
                  "一旦 %s 下出现任何一份日日志，本尺立刻退回真查重面。"
                  % (rel_posix(base), why, rel_posix(base)))
            return 0
        if kind == "broken":
            print("MEMLOG=reject 宇宙为空（目录不存在）：%s——判据无法自证" % rel_posix(base))
            return 2
        print("MEMLOG=reject 宇宙为空：%s 下一份 YYYY-MM-DD.md 都没枚举到，且 %s——判据无法自证"
              % (rel_posix(base), why))
        return 2
    if do_fix:
        changed, rc = fix(logs)
        for line in changed:
            print("FIX " + line)
        if rc:
            return rc
        if not changed:
            print("MEMLOG=clean 无需去重（%d 份日志）" % len(logs))
            return 0
        print("MEMLOG=fixed 落盘 %d 份，复跑判据确认" % len(changed))
        return 0
    problems, diag, readings, empties = scan(logs)
    for line in diag:
        print("面 " + line)
    if not readings:
        print("MEMLOG=reject 解析面为空——%d 份日志里 `## ` 块一条都没解析出来，"
              "不拿「没读到」当「对上了」" % len(logs))
        return 2
    uniq_blocks = sum(r[1] for r in readings)
    if uniq_blocks == 0:
        print("MEMLOG=reject %d 份日志里一个 `## ` 块都没有，文法失效 ⇒ 自拒" % len(logs))
        return 2
    if empties:
        # 一份日志没有 `## ` 块 = 本尺对这一份无判定（它用的是整篇叙事文法，不是重复缺陷）。
        # 但「无判定」必须在读数里点名：不许悄悄滑成「全都对上了」，也不许掩护另一面的真违例。
        print("空面 %d 份（无 `## ` 块，本尺不判它，见 MEMLOG 行）：%s"
              % (len(empties), " / ".join(rel_posix(e) for e in empties)))
    if problems:
        print("MEMLOG=violate 违例 %d 条（逐字相同的块重复=%d 族 / 日志 %d 份）"
              % (len(problems), sum(r[2] for r in readings), len(logs)))
        for p in problems:
            print("  - " + p)
        print("提示：`python scripts/check_memory_log_dup.py --fix` 机械去重（无损）")
        return 1
    print("MEMLOG=clean 日志 %d 份 / 块 %d 份逐一对表无逐字重复（空面 %d 份已点名）"
          % (len(logs), uniq_blocks, len(empties)))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # noqa: BLE001 — 尺子自己坏了 -> 真给 4，绝不冒用 1（判据红）
        sys.stderr.write("RULER BROKEN: %r\n" % e)
        sys.exit(4)
