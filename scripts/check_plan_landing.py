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

**刻意不判**（避免过度拦截）：
  - 文本里指向**尚不存在**的文件是**合法的**（计划本来就会写"新增 X"）⇒ 本工具**不是门禁**，
    `missing` 只是**诊断读数**，退出码 1 表示"有落点未落地"，不代表 CI 该红。
  - 不解析状态列 / 不判断"该不该存在"（散文语义机器判不了；判了就是伪精确）。
  - 只认反引号包裹的路径（本仓文档惯例），裸路径不认（会引入大量误报，如目录名、命令名）。

用法：
  python scripts/check_plan_landing.py                    # 扫 docs/ 下全部 *.md
  python scripts/check_plan_landing.py <文档路径>...      # 只扫指定文档
  python scripts/check_plan_landing.py --selftest         # 合成违例自证
退出码：0=全部落点在跟踪面 / 1=有落点未落地（诊断）/ 2=判据无法自证（FATAL）。
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


def extract_paths(text):
    """从反引号片段里抽出仓内路径（返回去重后有序列表）。"""
    out = []
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
            continue
        if cand not in out:
            out.append(cand)
    return out


def judge(doc_paths, tracked_set, disk_set, tracked_dirs=None):
    """doc_paths = {文档: [点名路径]}。返回 (诊断条目, 检查过的路径数)。
    非 tracked 的才进诊断；disk_set 用来区分「在工作树磁盘上」与「都没有」。
    tracked_dirs 提供时，目录形态的落点也按「跟踪面隐含目录」判定（防已跟踪目录被误报）。"""
    tracked_dirs = tracked_dirs or set()
    findings = []
    n = 0
    for doc in sorted(doc_paths):
        for p in doc_paths[doc]:
            n += 1
            if p in tracked_set or p in tracked_dirs:
                continue
            # 磁盘判定用「精确命中 OR 有子路径」：目录条目可能没进 disk_set（调用方只收了文件），
            # 但 `src/claimguard/xxx.mbt` 的存在足以证明 `src/claimguard` 在工作树里。
            on_disk = p in disk_set or any(x.startswith(p + "/") for x in disk_set)
            if on_disk:
                findings.append((doc, p, "on-disk", "**实现已在工作树磁盘上、只是没进跟踪面** ⇒ 出路是 `git add` 并提交"))
            else:
                findings.append((doc, p, "missing", "跟踪面与磁盘都没有 ⇒ 若计划已说'已完成'则是**虚报**；若说'将新增'则属正常未做"))
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
    print("SELFTEST OK（%d 格：抽取三格 / 干净不误报 / on-disk 必报 / missing 必报 / "
          "**跟踪目录反解+已跟踪目录不误报+未跟踪目录必报** / 空转计数）" % len(cells))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
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
    for d in docs:
        p = os.path.join(ROOT, d)
        if not os.path.isfile(p):
            continue
        with open(p, encoding="utf-8", errors="replace") as f:
            doc_paths[d] = extract_paths(f.read())

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

    # 只报未落地的（tracked 是常态）
    if not findings:
        print("PASS 计划落点核对：%d 份文档的 %d 条仓内点名路径**全部在跟踪面**"
              % (len(doc_paths), n))
        return 0

    on_disk = [x for x in findings if x[2] == "on-disk"]
    missing = [x for x in findings if x[2] == "missing"]
    print("INFO 计划落点核对（%d 份文档、%d 条点名路径）：未在跟踪面 %d 条"
          "（其中磁盘上有 %d 条、都没有 %d 条）"
          % (len(doc_paths), n, len(findings), len(on_disk), len(missing)))
    for doc, p, kind, hint in sorted(findings, key=lambda x: (x[2] != "on-disk", x[0], x[1])):
        print("  - [%s] %s 点名 `%s` ——%s" % (kind, doc, p, hint))
    print("注：本工具是**只读诊断**（计划里写'新增尚不存在的文件'是合法的），退出码 1 只表示有落点未落地，"
          "不代表门禁该红。")
    return 1


if __name__ == "__main__":
    sys.exit(main())
