#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_plan_landing.py — 计划文档「点名落点」↔ 跟踪面 存在性 核对（只读诊断，非门禁）。

**为什么需要它（2026-10-13 实测驱动）**：本会话反复遇到"计划说某文件已实现/将新增，但该文件不在 HEAD"：
  - `docs/2026-10-12-fist-mbt-supervisor-tools-plan.md` §5 点名 5 处落点，其中
    `src/server/supervisor_tools_test.mbt` **根本不存在**（测试锁未做），
    另两个新增文件（471 + 622 行）**在磁盘上却不在 HEAD**（已实现、未提交）
  - `docs/2026-10-12-fist-mbt-web-dashboard-plan.md` 的 M0 落地件 `scripts/fist-mbt-web.py`
    **实现完成、README 登记已入库，本体却未跟踪**
人工逐份核对要读十几份文档、几十个路径，且极易漏。本工具把这步机械化。

**判据（窄口径，刻意保守）**：
  P1 扫描指定计划文档里**反引号中的仓内文件路径**（形如 `` `src/foo/bar.mbt` `` /
     `` `scripts/x.py` ``），对每个路径给出三态：
       tracked  = 在 `git ls-files`（跟踪面）
       on-disk  = 在工作树磁盘上存在但不被跟踪  ⇒ **"实现已在工作树、只是没进跟踪面"**
       missing  = 跟踪面与磁盘**都没有**
     只报"非 tracked"的那些（tracked 是常态，报了是噪音）。
  P2 防空转：一份文档都没读到、或全仓零条仓内路径自述 ⇒ FATAL（判据空转 ≠ 没问题）。
  P3 **形状口径**（R40 实测：本守卫自 2026-10-14 落仓起既不在 CI 也不在历轮回归电池里，
     于是坏着躺了一周——它报的 56 条 missing 里 2 条是虚报）：
       - 「路径:行号」引用 `src/x.mbt:108/121/134` 先剥行号后缀再比跟踪面。原来整串当路径，
         而 `os.path.basename("…/134")`="134" 不含点 ⇒ 通过 `base_ok` ⇒ **已跟踪文件被报 missing**。
       - 日期/变量占位（`memory/YYYY-MM-DD.md`、`yyyyMMdd.HH.mm.ss`、`caf-{ns}.json`）与既有的
         `<...>`/`*` 同属**形态说明**，不算落点；但**单独计数控出**（静默丢弃=数字凭空变少，
         下一轮没人知道少的是噪音还是缺陷）。
  P4 **分面出数**（同一批实测：56 条里 17 条落在 `docs/archive/`，那是历史计划的存档，
     其落点在归档面上本就是"当时没做/后来改名"的事实，不是今天的待办）：
     活文档面（计入退出码）与归档面（只报不判）分开打印，两边的数字都在结论行里出现。

**刻意不判**（避免过度拦截）：
  - 文本里指向**尚不存在**的文件是**合法的**（计划本来就会写"新增 X"）⇒ 本工具**不是门禁**，
    `missing` 只是**诊断读数**，退出码 1 表示"有落点未落地"，不代表 CI 该红。
  - 不解析状态列 / 不判断"该不该存在"（散文语义机器判不了；判了就是伪精确）。
  - 只认反引号包裹的路径（本仓文档惯例），裸路径不认（会引入大量误报，如目录名、命令名）。

用法：
  python scripts/check_plan_landing.py                    # 扫 docs/ 下全部 *.md
  python scripts/check_plan_landing.py <文档路径>...      # 只扫指定文档
  python scripts/check_plan_landing.py --selftest         # 合成违例自证
  python scripts/check_plan_landing.py --all-faces        # 归档面也计入退出码（默认只报不判）
退出码：0=活文档面落点全在跟踪面 / 1=活文档面有落点未落地（诊断）/ 2=判据无法自证（FATAL）。
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

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BACKTICK = re.compile(r"`([^`\n]+)`")
# 只认"看起来是仓内文件路径"的：带目录分隔 + 有已知代码/文档扩展名。
# 目录也认（尾部斜杠），因为计划里常点"新增某目录"。
PATH_EXT = (".mbt", ".py", ".ps1", ".sh", ".md", ".json", ".yml", ".yaml", ".mbti",
            ".toml", ".cfg", ".txt", ".js", ".ts", ".sql", ".c", ".h", ".html")
TOP_DIRS = ("src/", "scripts/", "cmd/", "docs/", "templates/", "plugins/", "patches/",
            "reports/", "memory/", "specs/", "resources/", ".github/")
# P3 形状口径：`src/x.mbt:108/121/134` 这类「路径:行号」引用（本仓文档惯例，指到具体行）。
LINE_SUFFIX = re.compile(r"^(?P<path>.+?):(?P<lines>\d+(?:\s*[/,、-]\s*\d+)*)$")
# 日期/变量形态占位：`YYYY-MM-DD`、`yyyyMMdd.HH.mm.ss`、`caf-{ns}.json` —— 与 `<...>`/`*` 同类。
SHAPE_PLACEHOLDER = re.compile(r"YYYY|yyyy|HH\.mm|mm\.ss|[{}]")
# P4 分面：这些前缀之下的文档是**存档面**，其未落地落点只报不判红（默认）。
# 白名单刻意只收**名字里就写着存档的两族**（archive/ 与 reports/）；`docs/superpowers/plans|specs/`
# 虽然日期很旧，但目录名没自称存档 ⇒ 留在活文档面。把旧文档搬出白名单=拿命名兜底掩盖数字，
# 数字变好而缺陷没变，正是本守卫一周无人跑所暴露的那类失效。
ARCHIVE_DOC_PREFIX = ("docs/archive/", "reports/")


def tracked(root=None):
    root = root or ROOT
    r = subprocess.run(["git", "-C", root, "ls-files", "-z"],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.returncode != 0:
        raise SystemExit("FATAL git ls-files 退出码 %s —— 拒绝在无枚举时出读数" % r.returncode)
    files = [x.replace("\\", "/") for x in (r.stdout or "").split("\0") if x.strip()]
    if not files:
        raise SystemExit("FATAL git ls-files 返回空清单 —— 拒绝在无枚举时出读数")
    return files


def build_tracked_dirs(tracked_set):
    """从跟踪面文件清单反解出隐含的目录集合（git 不跟踪空目录，但跟踪其内文件 ⇒ 目录存在）。
    否则计划里点名的 `src/diff` 这类**已被跟踪的目录**会被误判为不在跟踪面。"""
    dirs = set()
    for f in tracked_set:
        d = os.path.dirname(f).replace("\\", "/")
        while d and d not in dirs:
            dirs.add(d)
            nd = os.path.dirname(d).replace("\\", "/")
            if nd == d:
                break
            d = nd
    return dirs


def extract_paths(text, with_shapes=False):
    """从反引号片段里抽出仓内路径。默认返回去重后有序列表；
    `with_shapes=True` 返回 (路径, 形态说明) —— 后者是被 P3 排除的占位/日期形状，只用于出数，
    不参与跟踪面比对（静默丢掉这批发「写了但机器不认」的形状，等于把尺子的口径变成不可查的私事）。"""
    out = []
    shapes = []
    for m in BACKTICK.finditer(text):
        raw = m.group(1).strip()
        cand = raw
        if cand.startswith("./"):
            cand = cand[2:]
        # 绝对路径（`/src/...`）无需单独拦截：下面 TOP_DIRS 闸要求以 `src/` 等**相对**前缀开头，
        # 以 `/` 开头者天然被排除。--- 变异实测发现原先那行单独的 `startswith("/")` 检查是**死代码**
        # （去掉它行为不变、无格可抓）⇒ 已删；改由 extract-rejects-abs-only 格锁定"绝对路径必须被拒"。
        if not cand.startswith(TOP_DIRS):
            continue                     # 只认仓内顶层目录开头的
        if cand.endswith("/"):
            cand = cand.rstrip("/")
        if not cand:
            continue
        # P3-a 「路径:行号」先剥后缀（R40 实测的虚报面：整串当路径 ⇒ 已跟踪文件报 missing）
        lm = LINE_SUFFIX.match(cand)
        if lm:
            cand = lm.group("path")
        base_ok = cand.endswith(PATH_EXT) or ("." not in os.path.basename(cand))
        if not base_ok:
            continue
        if "/" not in cand and not cand.endswith(PATH_EXT):
            continue                     # 顶层单个名字：太易误报，不认
        # **模板/占位形态不认**（2026-10-14 全仓扫描实测的误捕面）：计划文档常写
        # `docs/<tool>-skill.md` / `memory/research/*.md` / `docs/<lang>/` 这类**形态说明**
        # 而不是具体落点。它们不是"忘了交付"，是全仓误捕噪音（本轮 12 条全是它）。
        # 判据：路径任一片段含 `<...>` 或 `*` ⇒ 形态说明，跳过。
        if "<" in cand or ">" in cand or "*" in cand:
            if raw not in shapes:
                shapes.append(raw)
            continue
        # P3-b 日期/变量形态（R40 实测的第二批噪音：`memory/YYYY-MM-DD.md`、
        # `memory/reviews/yyyyMMdd.HH.mm.ss.md`、`memory/model-router-caf-{ns}.json`）同属形态说明。
        if SHAPE_PLACEHOLDER.search(cand):
            if raw not in shapes:
                shapes.append(raw)
            continue
        if cand not in out:
            out.append(cand)
    return (out, shapes) if with_shapes else out


def is_archive_doc(doc):
    """P4 分面判据：文档自身在存档面上（名字里写着 archive/reports）⇒ 其落点只报不判。"""
    return doc.startswith(ARCHIVE_DOC_PREFIX)


def judge(doc_paths, tracked_set, disk_set, tracked_dirs=None):
    """doc_paths = {文档: [点名路径]}。返回 (诊断条目, 检查过的路径数)。
    非 tracked 的才进诊断；disk_set 用来区分「在工作树磁盘上」与「都没有」。
    tracked_dirs 提供时，目录形态的落点也按「跟踪面隐含目录」判定（防已跟踪目录被误报）。
    条目第 5 位是**面**（"活文档"/"存档面"）——判定红只数活文档面那一档。"""
    tracked_dirs = tracked_dirs or set()
    findings = []
    n = 0
    for doc in sorted(doc_paths):
        face = "存档面" if is_archive_doc(doc) else "活文档"
        for p in doc_paths[doc]:
            n += 1
            if p in tracked_set or p in tracked_dirs:
                continue
            # 磁盘判定用「精确命中 OR 有子路径」：目录条目可能没进 disk_set（调用方只收了文件），
            # 但 `src/claimguard/xxx.mbt` 的存在足以证明 `src/claimguard` 在工作树里。
            on_disk = p in disk_set or any(x.startswith(p + "/") for x in disk_set)
            if on_disk:
                findings.append((doc, p, "on-disk", "**实现已在工作树磁盘上、只是没进跟踪面** ⇒ 出路是 `git add` 并提交", face))
            else:
                findings.append((doc, p, "missing", "跟踪面与磁盘都没有 ⇒ 若计划已说'已完成'则是**虚报**；若说'将新增'则属正常未做", face))
    return findings, n


def selftest():
    cells = []

    def cell(name, got, want):
        cells.append((name, bool(got) == bool(want), "got=%s want=%s" % (got, want)))

    # 1) 抽取口径：反引号 + 仓内顶层目录 + 已知扩展名 ⇒ 认
    got = extract_paths("见 `src/a/b.mbt` 与 `scripts/x.py`，以及 `docs/y.md`。")
    cell("extract-basic", got == ["src/a/b.mbt", "scripts/x.py", "docs/y.md"], True)
    print("  ok  extract-basic（认三种仓内路径）")

    # 2) 不认绝对路径 / 不认非仓内顶层 / 不认裸命令名（防误报）
    got2 = extract_paths("`/abs/x.mbt`、`other/x.mbt`、`moon check`、`FIST_WEB_PORT`")
    cell("extract-rejects-foreign", got2 == [], True)
    print("  ok  extract-rejects-foreign（绝对路径/非仓内/裸命令名都不认）")

    # 2c) **模板/占位形态不认**（全仓扫描实测的误捕面：12 条 `docs/<tool>-skill.md`、`memory/research/*.md`）
    got2c = extract_paths("按 `docs/<tool>-skill.md` 写文档；归档到 `memory/research/*.md`；示例放 `docs/examples/<lang>/`")
    cell("extract-rejects-placeholder", got2c == [], True)
    print("  ok  extract-rejects-placeholder（`<...>`/`*` 形态说明不认——它不是落点）")

    # 2d) **日期/变量形态**同属说明不是落点（R40 实测的第二批噪音：8 条）。
    got2d = extract_paths("日志写 `memory/YYYY-MM-DD.md`；脉冲写 `memory/reviews/yyyyMMdd.HH.mm.ss.md`；"
                          "路由表 `memory/model-router-caf-{ns}.json`")
    cell("extract-rejects-date-shape", got2d == [], True)
    print("  ok  extract-rejects-date-shape（YYYY/yyyyMMdd/{ns} 形态不认）")

    # 2e) 反证：形态被排除但**必须出数**（静默丢弃=数字凭空少，无人能查少的是噪音还是缺陷）
    paths, shapes = extract_paths(
        "落点 `src/real/file.mbt`；形态 `memory/YYYY-MM-DD.md`；形态 `docs/<tool>-skill.md`",
        with_shapes=True)
    cell("shape-notes-are-counted",
         paths == ["src/real/file.mbt"] and len(shapes) == 2, True)
    print("  ok  shape-notes-are-counted（1 条落点入比对 + 2 条形态单独出数，一个都不静默丢）")

    # 2f) **「路径:行号」剥后缀**（R40 实测的虚报面：`src/server/mcpcf_embed.mbt:108/121/134`
    #     整串当路径 ⇒ basename="134" 不含点、过了 base_ok ⇒ 已跟踪文件被报 missing）。
    got2f = extract_paths("详见 `src/server/mcpcf_embed.mbt:108/121/134` 与 "
                          "`plugins/source/references/omega-verification.md:33/60/65/68`")
    cell("extract-strips-line-suffix",
         got2f == ["src/server/mcpcf_embed.mbt", "plugins/source/references/omega-verification.md"], True)
    print("  ok  extract-strips-line-suffix（`:108/121/134` 剥掉后再比跟踪面）")
    # 反证：行号后缀剥离不能把真落点也吞掉（同一串里既有带行号又有不带的）
    got2g = extract_paths("`src/a/b.mbt:12` 与 `src/c/d.mbt`")
    cell("line-suffix-keeps-plain-paths", got2g == ["src/a/b.mbt", "src/c/d.mbt"], True)
    print("  ok  line-suffix-keeps-plain-paths（带/不带行号的两条都认，且不因剥后缀去重合并）")

    # 2b) 绝对路径单独一格（变异实测发现上面那格抓不住"绝对路径拦截被去掉"：
    #     因为去掉拦截后 `/abs/x.mbt` 仍不以 TOP_DIRS 开头 ⇒ 被下一道闸拦掉，格仍绿）
    got2b = extract_paths("`/src/a/b.mbt`")
    cell("extract-rejects-abs-only", got2b == [], True)
    print("  ok  extract-rejects-abs-only（`/src/...` 绝对路径必须被拦 —— 否则会误认成仓内）")

    # 3) 目录形态（尾部斜杠）认，且去掉斜杠后比对
    got3 = extract_paths("新增 `src/claimguard/` 包")
    cell("extract-dir-form", got3 == ["src/claimguard"], True)
    print("  ok  extract-dir-form（目录形态去斜杠）")

    # 4) 干净输入：路径都在跟踪面 ⇒ 0 诊断
    f, n = judge({"d.md": ["src/a.mbt"]}, {"src/a.mbt"}, set())
    cell("clean-no-findings", len(f) == 0 and n == 1, True)
    print("  ok  clean-no-findings（%d 条路径，0 诊断）" % n)

    # 5) 合成违例一：在磁盘、不在跟踪面 ⇒ on-disk（工作树有、未提交）
    f, n = judge({"d.md": ["src/x.mbt"]}, set(), {"src/x.mbt"})
    cell("on-disk-detected", len(f) == 1 and f[0][2] == "on-disk", True)
    print("  ok  on-disk-detected（磁盘有、跟踪面无 ⇒ 报'出路是 git add'）")

    # 6) 合成违例二：都不在 ⇒ missing
    f, n = judge({"d.md": ["src/y.mbt"]}, set(), set())
    cell("missing-detected", len(f) == 1 and f[0][2] == "missing", True)
    print("  ok  missing-detected（都没有 ⇒ 报 missing）")

    # 6a) **P4 分面**：同一条 missing，写在存档面文档里 ⇒ 面=「存档面」（只报不判），
    #     写在活文档里 ⇒ 面=「活文档」（计入退出码）。56 条实测读数里 17 条属前者。
    f, n = judge({"docs/archive/2026-10-11-plan.md": ["src/never.mbt"],
                  "docs/plan-live.md": ["src/never2.mbt"]}, set(), set())
    live = [x for x in f if x[4] == "活文档"]
    arch = [x for x in f if x[4] == "存档面"]
    cell("face-split", len(live) == 1 and len(arch) == 1, True)
    print("  ok  face-split（同形状按文档所在面分档：活文档 %d 条 / 存档面 %d 条）" % (len(live), len(arch)))
    # 反证：只有存档面有未落地时，判定档为空 ⇒ 不判红（但条目仍在，不静默消失）
    f2, _ = judge({"docs/archive/2026-10-11-plan.md": ["src/never.mbt"]}, set(), set())
    cell("archive-only-not-verdict", len(f2) == 1 and not [x for x in f2 if x[4] == "活文档"], True)
    print("  ok  archive-only-not-verdict（存档面独红 ⇒ 判定档空，条目照报）")
    cell("archive-prefix-not-overbroad",
         is_archive_doc("docs/superpowers/plans/2026-09-24-x.md") is False
         and is_archive_doc("docs/archive/x.md") is True, True)
    print("  ok  archive-prefix-not-overbroad（白名单只收名字自称存档的两族，旧但不自称的留活面）")

    # 6b) 目录判定（首跑实测抓到的自身缺陷）：已跟踪目录不许被误报。
    #     变异实测正是靠这格把「disk_set 只收文件 / tracked_dirs 不生效」抓住。
    td = build_tracked_dirs({"src/diff/diff.mbt", "cmd/cli/main.mbt"})
    cell("tracked-dirs-derived", {"src", "src/diff", "cmd", "cmd/cli"} <= td, True)
    print("  ok  tracked-dirs-derived（从跟踪文件反解隐含目录：%d 个）" % len(td))
    f, n = judge({"d.md": ["src/diff"]}, {"src/diff/diff.mbt"}, set(), td)
    cell("tracked-dir-not-reported", len(f) == 0, True)
    print("  ok  tracked-dir-not-reported（已跟踪目录不误报）")
    # 目录在磁盘、未跟踪 ⇒ 仍报 on-disk。注意 disk_set 里要放**目录条目本身**
    # （主流程的 os.walk 会把目录也收进 disk_set，故这里模拟真实形态）。
    f, n = judge({"d.md": ["src/claimguard"]}, set(), {"src/claimguard"}, set())
    cell("untracked-dir-on-disk", len(f) == 1 and f[0][2] == "on-disk", True)
    print("  ok  untracked-dir-on-disk（目录在磁盘未跟踪 ⇒ 报 on-disk）")

    # 7) 防空转：零路径 ⇒ 由 main 自拒；这里只考 judge 的 n 计数不漏
    f, n = judge({"d.md": []}, set(), set())
    cell("empty-doc-counts-zero", n == 0, True)
    print("  ok  empty-doc-counts-zero（空文档 n=0，供 main 判空转）")

    bad = [(nm, why) for nm, ok, why in cells if not ok]
    if bad:
        print("SELFTEST FAIL：")
        for nm, why in bad:
            print("  - %s：%s" % (nm, why))
        return 1
    print("SELFTEST OK（%d 格：抽取口径 9 格（`<…>`/`*` 形态、日期与变量占位、形态出数反证、"
          "「路径:行号」剥离 + 同串正反证、绝对路径、目录形态、非仓内）/ 干净不误报 / on-disk 必报 / "
          "missing 必报 / 跟踪目录反解 3 格 / P4 分面 3 格 / 空转计数）" % len(cells))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--all-faces", action="store_true",
                    help="存档面（docs/archive/、reports/）的未落地落点也计入退出码；默认只报不判")
    ap.add_argument("docs", nargs="*")
    args = ap.parse_args()
    if args.selftest:
        return selftest()

    files = tracked()
    tracked_set = set(files)
    tracked_dirs = build_tracked_dirs(tracked_set)

    if args.docs:
        docs = [d.replace("\\", "/") for d in args.docs]
    else:
        docs = [f for f in files if f.startswith("docs/") and f.endswith(".md")]

    if not docs:
        raise SystemExit("FATAL 一份文档都没枚举到 —— 判据空转，拒绝出读数")

    doc_paths = {}
    shape_notes = []
    for d in docs:
        p = os.path.join(ROOT, d)
        if not os.path.isfile(p):
            continue
        with open(p, encoding="utf-8", errors="replace") as f:
            paths, shapes = extract_paths(f.read(), with_shapes=True)
        doc_paths[d] = paths
        for s in shapes:
            if s not in shape_notes:
                shape_notes.append(s)

    if not doc_paths:
        raise SystemExit("FATAL 一份计划文档都读不到 —— 判据空转，拒绝出读数")

    disk_set = set()
    for dp, dn, fn in os.walk(ROOT):
        if any(x in dp for x in (".git", "_build", "node_modules", ".mooncakes", "temp")):
            continue
        for f in fn:
            disk_set.add(os.path.relpath(os.path.join(dp, f), ROOT).replace("\\", "/"))
        # 目录也要进集合：计划里点名的常常是**目录**（如 `src/diff`、`cmd/cli`、`scripts/blackbox`）。
        # 首跑实测抓到的自身缺陷：只收集文件 ⇒ 这些存在的目录被误报 missing（82 条里占了不少）。
        for d in dn:
            disk_set.add(os.path.relpath(os.path.join(dp, d), ROOT).replace("\\", "/"))

    findings, n = judge(doc_paths, tracked_set, disk_set, tracked_dirs)
    if n == 0:
        raise SystemExit("FATAL 全仓计划文档里一条仓内落点路径都没抽到 —— 判据空转，拒绝出读数")

    live = findings if args.all_faces else [x for x in findings if x[4] == "活文档"]
    archived = [x for x in findings if x[4] == "存档面"]
    # 只报未落地的（tracked 是常态）
    if not live:
        extra = ("；存档面另有 %d 条只报不判（--all-faces 可计入）" % len(archived)) if archived else ""
        print("PASS 计划落点核对：%d 份文档的 %d 条仓内点名路径**全部在跟踪面**（形态说明 %d 条不认作落点、单独出数）%s"
              % (len(doc_paths), n, len(shape_notes), extra))
        return 0

    on_disk = [x for x in live if x[2] == "on-disk"]
    missing = [x for x in live if x[2] == "missing"]
    print("INFO 计划落点核对（%d 份文档、%d 条点名路径、形态说明 %d 条已出数不比对）："
          "判定面未在跟踪面 %d 条（磁盘上有 %d 条、都没有 %d 条）；存档面另有 %d 条只报不判"
          % (len(doc_paths), n, len(shape_notes), len(live), len(on_disk), len(missing), len(archived)))
    for doc, p, kind, hint, face in sorted(live, key=lambda x: (x[2] != "on-disk", x[0], x[1])):
        print("  - [%s] %s 点名 `%s` ——%s" % (kind, doc, p, hint))
    if archived:
        print("  …存档面（docs/archive/、reports/）%d 条，分布在 %d 份文档：%s"
              % (len(archived), len({x[0] for x in archived}),
                 " ".join(sorted({x[0] for x in archived}))[:200]))
    if shape_notes:
        print("  …形态说明（`<…>`/`*`/日期/变量占位，R40 起单独出数、不参与跟踪面比对）%d 条：%s"
              % (len(shape_notes), " ".join(shape_notes)[:200]))
    print("注：本工具是**只读诊断**（计划里写'新增尚不存在的文件'是合法的），退出码 1 只表示判定面有落点未落地，"
          "不代表门禁该红。")
    return 1


if __name__ == "__main__":
    sys.exit(main())
