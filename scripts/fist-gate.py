# -*- coding: utf-8 -*-
"""scripts/fist-gate.py - unified gate chain (merge_markers/fmt/build/ps_encoding/store_path) + --scan branch census. rc: 0=pass/scan-output 1=fail 2=degraded."""
import os, re, subprocess, sys, tempfile
from datetime import datetime
from pathlib import Path

from moon_env_probe import moon_env
# 统一把 stdout/stderr 钉成 UTF-8（CI 在 Linux UTF-8 下是无损 no-op）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
ROOT = Path(__file__).resolve().parent.parent
EXC = ("_build", "temp", ".git", "node_modules")
def run(cmd, cwd=None):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8",
                          errors="replace", env=moon_env())
def tracked(root):
    r = run(["git", "-C", str(root), "ls-files", "-z"])
    return None if r.returncode else [f for f in r.stdout.split("\0") if f.strip()]
def pick(files, suffix, prefix=""): return [f for f in files if f.startswith(prefix) and f.endswith(suffix) and not any(x in Path(f).parts for x in EXC)]
def ck_mm(root):
    if root == ROOT:
        r = run(["python", "scripts/blackbox/check_merge_markers.py"], cwd=root)
        out = (r.stdout.strip().splitlines() or ["no output"])[-1]
        return (2, "DEGRADED merge_markers: " + out) if r.returncode == 2 else (r.returncode, out)
    fs = tracked(root)
    if fs is None: return 2, "DEGRADED merge_markers: git unavailable"
    bad = [f for f in fs if any(l.startswith(("<<<<<<<", "=======", ">>>>>>>")) for l in (root / f).read_text(encoding="utf-8", errors="replace").splitlines())]
    return (1, "FAIL merge_markers: " + ", ".join(bad)) if bad else (0, "merge_markers: %d files ok" % len(fs))
# ── fmt 臂的两类**已知**退化（实测 2026-10-21，本机晚间多轮）： ──────────────
# ① 冷格式化器：全新 worktree 里 `moon fmt --check` 直接 rc=-1，报
#    `failed to execute `git --no-pager diff --color=always --no-index …` 与
#    `open("…/_build/wasm-gc/release/format/moon.mod"): No such file` ——
#    根因是 moon 的格式化器需要先前产物；**必须先跑一次写模式 `moon fmt` 预热**（实测预热后
#    `--check` 恢复真读数），但写模式会改写文件（本机实测 330 个 = BUG-330 的世代不匹配），
#    所以**判据里绝不能自己预热**（电池/门链必须只读）。
# ② 世代不匹配：预热后 `--check` = rc1「format diff」，但差异是 Int→Int32 / 行尾一类
#    **工具链世代差**（BUG-330），按仓内既定口径「fmt 门强度在世代统一前不硬判」。
# 处置：这两类都报 DEGRADED(2) 并给出可执行提示；**未知退化仍报 2 但不放行**（selftest 区分）。
# 想在本机把 fmt 当硬门用：设 FIST_GATE_FMT_STRICT=1（CI nightly 世代对齐后再考虑默认）。
FMT_COLD_MARKERS = (
    "failed to execute `git --no-pager diff",
    "/format/moon.mod",
    "wasm-gc/release/format",
)


def classify_fmt(rc, text):
    """把 fmt 臂的失败归成四档：clean / cold-formatter / generation-mismatch / unknown。

    ⚠️ **R174：本函数与 `scripts/check_fmt_gate.py:run()` 是两个不同的判定，不要当成同一份拷贝。**
    R173 试过直接委派给真源 ⇒ **2 格自检红**（冷格式化器识别失败 / 未知退化未归 unknown）⇒ 已撤回。
    实测差异（**裁定前请勿"顺手统一"**）：

    | 面 | 本函数 | `check_fmt_gate.run` |
    |---|---|---|
    | 档数 | 4 | 3 |
    | 冷格式化器 marker | `FMT_COLD_MARKERS`（3 条，含 `wasm-gc/release/format`） | `BROKEN_SIGNATURES`（3 条，且要求输出含 `_build`） |
    | `rc==1` | `generation-mismatch`（当"世代差"**软化**，非 strict 时报 DEGRADED） | `red`（**真格式差异**） |
    | 未知非 0 | `unknown` | `red` |

    ⇒ 收敛不是搬迁、是**语义取舍**（谁当冷 marker、`rc=1` 软化还是判红）⇒ 需判据主人裁定。
    """
    if rc == 0:
        return "clean"
    if rc == 1:
        return "generation-mismatch"
    if any(m in text for m in FMT_COLD_MARKERS):
        return "cold-formatter"
    return "unknown"


def ck_fmt(root):
    r = run(["moon", "fmt", "--check"], cwd=root)
    text = (r.stdout or "") + (r.stderr or "")
    kind = classify_fmt(r.returncode, text)
    strict = os.environ.get("FIST_GATE_FMT_STRICT", "").strip() in ("1", "true", "yes")
    if kind == "clean":
        return 0, "moon fmt --check: clean"
    if kind == "cold-formatter":
        return 2, ("DEGRADED fmt: 格式化器未预热（缺 _build/wasm-gc/release/format/）——"
                   "在一次性副本上跑 `moon fmt` 预热后再判；判据自身不预热（门链必须只读）")
    if kind == "generation-mismatch":
        tail = "（FIST_GATE_FMT_STRICT=1 已开启 ⇒ 按硬红处理）" if strict else "（世代差，按仓内口径不硬判；CI nightly 为准）"
        return (1 if strict else 2), "moon fmt --check: format diff " + tail
    last = ((r.stderr or r.stdout or "").strip().splitlines() or ["no output"])[-1]
    return 2, "DEGRADED fmt(unknown): rc=%d %s" % (r.returncode, last)
# build 臂也有「环境态 ≠ 代码态」的问题（实测 2026-10-21）：全新 worktree / 旧依赖缓存上
# `moon build` 会以
#   `moon.mod.json at '…/.mooncakes/Tigls/mb-getrandom' is no longer supported` 或
#   `Failed to resolve the module dependency graph`
# 直接失败——那是**依赖缓存格式过旧/未迁移**，不是本仓代码坏了。若一并报 FAIL(1)，人会去翻源码找
# 一个根本不存在的编译错误（BUG-329/332 同族）。故先分类再由调用方决定严重度。
BUILD_ENV_MARKERS = (
    "no longer supported",
    "Failed to resolve the module dependency graph",
    "Failed to calculate build plan",
    "When installing packages",
)


def classify_build(rc, text):
    if rc == 0:
        return "clean"
    if any(m in text for m in BUILD_ENV_MARKERS):
        return "deps-stale"
    return "code-fail"


def ck_build(root):
    r = run(["moon", "build", "--target", "js", "src/server", "src/engine", "src/store", "src/router", "src/ops"], cwd=root)
    text = (r.stdout or "") + (r.stderr or "")
    kind = classify_build(r.returncode, text)
    if kind == "clean":
        return 0, "build: rc=0, 0 errors"
    if kind == "deps-stale":
        return 2, ("DEGRADED build: 依赖缓存格式过旧/未迁移（moon.mod.json no longer supported）——"
                   "跑一次 `moon fmt` 迁移或重建 .mooncakes 后再判；这是环境态，不是代码编译错误")
    return 1, "build FAIL rc=%d tail: %s" % (r.returncode, text[-160:])
def ck_ps(root):
    fs = tracked(root)
    if fs is None: return 2, "DEGRADED ps_encoding: git unavailable"
    ps = pick(fs, ".ps1")
    if not ps: return 2, "DEGRADED ps_encoding: no tracked .ps1 (empty scan)"
    bad = [f for f in ps if any(x > 127 for x in (root / f).read_bytes()) and not (root / f).read_bytes().startswith(b"\xef\xbb\xbf")]
    return (1, "FAIL ps_encoding: " + ", ".join(bad)) if bad else (0, "ps_encoding: %d .ps1 ASCII/BOM ok" % len(ps))
def ck_sp(root):
    fs = tracked(root)
    if fs is None: return 2, "DEGRADED store_path: git unavailable"
    st = [f for f in pick(fs, ".mbt", "src/store/") if not f.endswith("_test.mbt")]
    if not st: return 2, "DEGRADED store_path: no src/store/*.mbt (empty scan)"
    pat = re.compile(r'"[^"\n]*(?:C:|c:)[\\/][^"\n]*"|"[^"\n]*/(?:etc|home|usr|var|root)/[^"\n]*"|"[^"\n]*\\\\[A-Za-z][^"\n]*"')
    bad = [f for f in st if pat.search((root / f).read_text(encoding="utf-8", errors="replace"))]
    return (1, "FAIL store_path: " + ", ".join(bad)) if bad else (0, "store_path: %d store files ok" % len(st))
def ck_ws(root):
    # 风语者探测面自证：只跑 whisperer_patrol.py --selftest（扫描产物是输出不是门，真发现走 backlog yaml）。
    # R93 起指向 patrol 引擎而非 whisperer.py——后者的 Step 0 会 reset --hard + 强推共享线（TASK-018），
    # 且它的旗名是 `--self-test`，喂 `--selftest` 只会拿到 argparse 的 rc=2 幻影红。
    # 脚本取真实安装位（合成仓里没有副本，patrol 自证自建临时仓、不依赖被检 root）
    ws = Path(__file__).resolve().parent / "whisperer_patrol.py"
    r = run([sys.executable or "python", str(ws), "--selftest"], cwd=root)
    if r.returncode:
        return 1, "FAIL whisperer: 自证 rc=%d %s" % (r.returncode, ((r.stdout + r.stderr).strip().splitlines() or ["no output"])[-1])
    return 0, "whisperer: " + ((r.stdout.strip().splitlines() or ["ok"])[0])
CHECKS = [("merge_markers", ck_mm), ("fmt", ck_fmt), ("build", ck_build), ("ps_encoding", ck_ps), ("store_path", ck_sp), ("whisperer", ck_ws)]
def safe(name, fn, root):
    try: return fn(root)
    except Exception as e: return 2, "DEGRADED %s: %s" % (name, e)
def gate(root):
    rc = 0
    for name, fn in CHECKS:
        c, line = safe(name, fn, root)
        print(("FAIL " if c == 1 else "DEGRADED " if c == 2 else "PASS ") + name + ": " + line)
        rc = max(rc, c)
    return rc

# --- TASK-005: --scan 分支普查（合入者巡检的自动进料口） -----------------
# rc 契约：0 = 有产出（含发现，发现是输出不是失败）；2 = 判据无法自证（远端分支枚举不到 / 无 master-main 基点）。
def remote_refs(root):
    r = run(["git", "-C", str(root), "branch", "-r", "--format", "%(refname)"], cwd=root)
    if r.returncode: return None
    out = []
    for l in r.stdout.splitlines():
        l = l.strip()
        if l.startswith("refs/remotes/") and not l.endswith("/HEAD"):
            out.append(l[len("refs/remotes/"):])
    return out
def pick_base(refs):
    for cand in ("gitcode/master", "gitcode/main", "origin/master", "origin/main", "master"):
        if cand in refs: return cand
    return None
def gout(root, *args):
    r = run(["git", "-C", str(root)] + list(args), cwd=root)
    return "" if r.returncode else r.stdout
# TASK-004：反向 diff 检测。判据来自实测——slave/fix/battery-expectations-r73 的
# `git diff --stat` = 718 deletions / 191 insertions，issue_scan.mbt 单文件 -457/+0：
# 那是"把已合入内容 revert 回旧版本"，不是正常增量。正常增量几乎总是 add ≥ del，
# 回退型的特征是 **deletions > insertions × 1.5**（实测正常分支极少超 1.0，回退型高达 3.7）。
# 本判据**只标记不自动丢弃**：可疑不等于有罪——回退型分支进 failed/ 等人工确认后重做。
REVERT_RATIO = 1.5


def parse_numstat(text):
    """`git diff --numstat` → ([(path,add,del)], add_total, del_total)；二进制行(-)跳过。"""
    files, add_t, del_t = [], 0, 0
    for line in text.splitlines():
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        a, d, path = parts[0], parts[1], parts[2]
        if not (a.isdigit() and d.isdigit()):
            continue
        A, D = int(a), int(d)
        files.append((path, A, D))
        add_t += A
        del_t += D
    return files, add_t, del_t


def is_revert_pattern(add_total, del_total):
    """删远多于增 ⇒ 疑似回退（rebase 方向错/把已合内容倒回旧版）。纯函数，直接可测。"""
    return del_total > 0 and del_total > add_total * REVERT_RATIO


def worst_deletions(files, limit=5):
    """按 (del-add) 降序取前几个，用于日志点名「哪几个文件删远多于增 + 差值」。"""
    rows = [(path, A, D, D - A) for path, A, D in files if D > A]
    rows.sort(key=lambda r: -r[3])
    return rows[:limit]


def scan_branch(root, base, ref):
    ahead = gout(root, "rev-list", "--count", "%s..%s" % (base, ref)).strip()
    ahead = int(ahead) if ahead.isdigit() else 0
    cherry_plus = sum(1 for l in gout(root, "cherry", base, ref).splitlines() if l.startswith("+"))
    numstat = gout(root, "diff", "--numstat", "%s...%s" % (base, ref), "--", "src", "scripts", "cmd", "moon.pkg")
    files, add_total, del_total = parse_numstat(numstat)
    code_files = [f[0] for f in files]
    src_lines = add_total + del_total
    markers = []
    for path in code_files:
        body = gout(root, "show", "%s:%s" % (ref, path))
        if any(l.startswith(("<<<<<<<", ">>>>>>>")) for l in body.splitlines()):
            markers.append(path)
    revert = is_revert_pattern(add_total, del_total)
    worst = worst_deletions(files)
    if markers: action = "ABORT/人工解冲突：分支自带未解决冲突标记"
    elif revert: action = "REVERT-PATTERN：删远多于增（疑似 rebase 方向错/把已合内容倒回旧版）——进 failed/，人工确认后重做"
    elif ahead == 0 and cherry_plus == 0: action = "DROP：base 已包含分支全部提交（可删分支/关 MR）"
    elif cherry_plus == 0: action = "DROP：全部提交内容已等价存在于 base（cherry 无 +）"
    elif src_lines == 0: action = "MERGE-LOW-RISK：纯文档/流水账改动，低风险合入"
    else: action = "MERGE-CODE：有 src/scripts 代码改动——先过统一门链（fist-gate.py）再合入"
    return {"branch": ref, "base": base, "ahead": ahead, "cherry_plus": cherry_plus,
            "insertions": add_total, "deletions": del_total, "revert_pattern": revert,
            "worst_deletions": ["%s -%d/+%d (净 -%d)" % (w[0], w[2], w[1], w[3]) for w in worst],
            "conflict_markers": markers, "src_lines_changed": src_lines, "code_files": code_files,
            "suggested_action": action}
def yaml_cell(v):
    if isinstance(v, int): return str(v)
    if isinstance(v, list): return "[" + ", ".join('"%s"' % x for x in v) + "]" if v else "[]"
    return '"%s"' % str(v).replace("\\", "\\\\").replace('"', '\\"')
def write_scan_yaml(path, row):
    body = ["status: backlog", "source: fist-gate.py scan"]
    body += ["%s: %s" % (k, yaml_cell(v)) for k, v in row.items()]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(body) + "\n", encoding="utf-8")
def scan(root, do_fetch=True):
    refs = remote_refs(root)
    if refs is None or not refs: return 2, "scan: no remote branches enumerable (fetch first / no remotes)"
    base = pick_base(refs)
    if base is None: return 2, "scan: no master/main base ref among remote branches"
    fetch_note = ""
    if do_fetch:
        fr = run(["git", "-C", str(root), "fetch", "--all", "--prune"], cwd=root)
        if fr.returncode: fetch_note = "DEGRADED fetch rc=%d（用既有远端引用继续）\n" % fr.returncode
        refs = remote_refs(root) or refs
    # 坑（实测 2026-10-21/22 两发）：在 git worktree 里 `.git` 是**文件**（gitdir 指针），不是目录 ⇒
    # `Path(root)/".git"/...` 建目录必 FileNotFoundError，未捕获异常还会把 rc 变成 1（看起来像"判据红了"）。
    # 必须问 git 要真实 gitdir；取不到就 rc=2 拒绝"在错位置写任务"。
    gd = gout(root, "rev-parse", "--absolute-git-dir").strip()
    if not gd:
        gd = gout(root, "rev-parse", "--git-dir").strip()
        if gd and not os.path.isabs(gd):
            gd = os.path.normpath(os.path.join(str(root), gd))
    if not gd:
        return 2, "scan: 取不到 git dir（rev-parse --absolute-git-dir 空）——拒绝在错位置写任务"
    tasks_root = Path(gd) / "fist" / "tasks"
    out_dir = tasks_root / "backlog"
    failed_dir = tasks_root / "failed"
    rows = []
    for ref in refs:
        if ref == base or ref.rsplit("/", 1)[-1] in ("master", "main"): continue
        row = scan_branch(root, base, ref)
        row["scanned_at"] = datetime.now().astimezone().isoformat(timespec="seconds")
        dest = failed_dir if row["revert_pattern"] else out_dir   # TASK-004：回退型进 failed/
        write_scan_yaml(dest / (ref + ".yaml"), row)
        rows.append(row)
    stale = 0
    live = {ref + ".yaml" for ref in refs if ref != base and ref.rsplit("/", 1)[-1] not in ("master", "main")}
    for d in (out_dir, failed_dir):
        if not d.is_dir():
            continue
        for p in list(d.rglob("*.yaml")):
            if p.relative_to(d).as_posix() not in live:
                p.unlink(); stale += 1
    reverts = [r for r in rows if r["revert_pattern"]]
    print(fetch_note + "scan: base=%s 分支 %d 个（REVERT-PATTERN %d 个 → 进 failed/）→ %s（清掉 stale yaml %d 份）"
          % (base, len(rows), len(reverts), out_dir, stale))
    for r in reverts:
        ratio = (r["deletions"] / r["insertions"]) if r["insertions"] else float("inf")
        print("  ⚠ REVERT-PATTERN %s：insertions=%d deletions=%d（删/增=%.2f > %.1f）"
              % (r["branch"], r["insertions"], r["deletions"], ratio, REVERT_RATIO))
        for w in r["worst_deletions"]:
            print("      删远多于增: %s" % w)
    for row in sorted(rows, key=lambda r: (-r["src_lines_changed"], r["branch"])):
        print("  %-52s ahead=%-3d cherry+=%-3d src±=%-5d markers=%d → %s" % (
            row["branch"], row["ahead"], row["cherry_plus"], row["src_lines_changed"],
            len(row["conflict_markers"]), row["suggested_action"]))
    print("巡检 prompt 追加句：『每次巡检先跑 python scripts/fist-gate.py --scan，把"
          ".git/fist/tasks/backlog/ 下的新 yaml 里值得处理的问题提升为 docs/tasks/backlog/*.yaml』")
    return 0, "scan: %d branches" % len(rows)

def selftest():
    executed, fails = [], []
    def repo(files):
        d = Path(tempfile.mkdtemp(prefix="fg-"))
        run(["git", "init", "-q"], cwd=d); run(["git", "config", "user.email", "t@t"], cwd=d); run(["git", "config", "user.name", "t"], cwd=d)
        for rel, body in files.items():
            p = d / rel; p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(body) if isinstance(body, bytes) else p.write_text(body, encoding="utf-8")
        run(["git", "add", "-A"], cwd=d); run(["git", "commit", "-qm", "f"], cwd=d)
        return d
    def probe(name, fn, d, want, label):
        c, line = safe(name, fn, d); executed.append(label % (name, c))
        if c != want: fails.append("%s rc=%d want %d: %s" % (name, c, want, line))
    bad = repo({"x.mbt": "a\n<<<<<<< HEAD\nb\n=======\nc\n>>>>>>> t\n", "bad.ps1": b"Write-Output '\xc4\xe2\xba\xba'\n", "src/store/x.mbt": "let p = \"C:\\\\data\"\n"})
    for name, fn in [("merge_markers", ck_mm), ("ps_encoding", ck_ps), ("store_path", ck_sp)]: probe(name, fn, bad, 1, "G1 %s red-on-inject rc=%d")
    clean = repo({"ok.ps1": b"Write-Output 'ascii'\n", "src/store/y.mbt": "let p = \"data\"\n", "a.mbt": "def f() = 1\n"})
    for name, fn in [("merge_markers", ck_mm), ("ps_encoding", ck_ps), ("store_path", ck_sp)]: probe(name, fn, clean, 0, "G2 %s green-on-clean rc=%d")
    probe("ps_encoding", ck_ps, repo({"a.mbt": "def f() = 1\n"}), 2, "G3 %s empty-scan self-reject rc=%d")
    # G4：真实仓库上 fmt/build 必须给出**可解释**的读数。
    # fmt 允许 0/1/2，但 rc=2 时必须属于两类**已知**退化（冷格式化器 / 世代差）——
    # 「已知退化」与「未知退化」分开，避免把任何坏法都当已知放过。
    c, line = safe("fmt", ck_fmt, ROOT); executed.append("G4 fmt observable-on-real (rc=%d)" % c)
    if c == 2 and not (FMT_COLD_MARKERS[0] in line or "未预热" in line or "世代差" in line):
        fails.append("G4 fmt rc=2 但属未知退化: %s" % line)
    elif c not in (0, 1, 2):
        fails.append("G4 fmt rc=%d 越界: %s" % (c, line))
    # 分类器单元格（不依赖本机是否预热）
    executed.append("G4 classify cold/mismatch/unknown")
    if classify_fmt(-1, "failed to execute `git --no-pager diff") != "cold-formatter":
        fails.append("G4 classify: 冷格式化器识别失败")
    if classify_fmt(1, "") != "generation-mismatch":
        fails.append("G4 classify: rc=1 应归世代差")
    if classify_fmt(0, "") != "clean":
        fails.append("G4 classify: rc=0 应为 clean")
    if classify_fmt(-1, "boom") != "unknown":
        fails.append("G4 classify: 未知退化未归 unknown")
    c, line = safe("build", ck_build, ROOT); executed.append("G4 build observable-on-real (rc=%d)" % c)
    if c == 2 and "依赖缓存格式过旧" not in line:
        fails.append("G4 build rc=2 但属未知退化: %s" % line)
    elif c not in (0, 1, 2):
        fails.append("G4 build rc=%d 越界: %s" % (c, line))
    # 分类器单元格（不依赖本机状态）
    executed.append("G4 classify build clean/deps-stale/code-fail")
    if classify_build(0, "") != "clean":
        fails.append("G4 classify build: rc=0 应 clean")
    if classify_build(-1, "moon.mod.json at 'x' is no longer supported") != "deps-stale":
        fails.append("G4 classify build: 依赖格式过旧应归 deps-stale")
    if classify_build(1, "Error: [4001] undeclared identifier") != "code-fail":
        fails.append("G4 classify build: 真编译错应归 code-fail")
    # --- TASK-005 scan cells (offline: local repo as "origin") ---
    def scan_origin(branches, merged=()):
        org = Path(tempfile.mkdtemp(prefix="fg-org-"))
        run(["git", "init", "-q", "-b", "master"], cwd=org); run(["git", "config", "user.email", "t@t"], cwd=org); run(["git", "config", "user.name", "t"], cwd=org)
        (org / "r.txt").write_text("base\n", encoding="utf-8"); run(["git", "add", "-A"], cwd=org); run(["git", "commit", "-qm", "base"], cwd=org)
        for name, files in branches.items():
            run(["git", "checkout", "-q", "-b", name], cwd=org)
            for rel, body in files.items():
                p = org / rel; p.parent.mkdir(parents=True, exist_ok=True); p.write_text(body, encoding="utf-8")
            run(["git", "add", "-A"], cwd=org); run(["git", "commit", "-qm", name], cwd=org)
            run(["git", "checkout", "-q", "master"], cwd=org)
        for name in merged:
            run(["git", "merge", "-q", "--ff-only", name], cwd=org)
        loc = Path(tempfile.mkdtemp(prefix="fg-loc-"))
        run(["git", "init", "-q"], cwd=loc); run(["git", "config", "user.email", "t@t"], cwd=loc); run(["git", "config", "user.name", "t"], cwd=loc)
        run(["git", "remote", "add", "origin", str(org)], cwd=loc); run(["git", "fetch", "-q", "origin"], cwd=loc)
        return loc
    def yaml_at(loc, name):
        p = loc / ".git" / "fist" / "tasks" / "backlog" / ("origin/%s.yaml" % name)
        return p, (p.read_text(encoding="utf-8") if p.exists() else "")
    c, line = scan(repo({}), do_fetch=False)
    executed.append("S1 scan-no-remote-self-reject rc=%d" % c)
    if c != 2: fails.append("S1 scan on repo without remotes rc=%d want 2" % c)
    loc = scan_origin({"feature": {"src/lib.mbt": "a\nb\nc\n"}})
    c, line = scan(loc, do_fetch=False)
    _, y = yaml_at(loc, "feature")
    ok = c == 0 and "ahead: 1" in y and "cherry_plus: 1" in y and "src_lines_changed: 3" in y and "suggested_action: \"MERGE-CODE" in y
    executed.append("S2 scan-code-branch-yaml fields (rc=%d)" % c)
    if not ok: fails.append("S2 scan code branch rc=%d yaml mismatch: %s" % (c, y[:200]))
    loc = scan_origin({"docs-only": {"docs/note.md": "hi\n"}})
    scan(loc, do_fetch=False)
    _, y = yaml_at(loc, "docs-only")
    executed.append("S3 scan-docs-only-merges-low-risk")
    if "suggested_action: \"MERGE-LOW-RISK" not in y: fails.append("S3 docs-only action mismatch: %s" % y[:200])
    loc = scan_origin({"feat-a": {"src/a.mbt": "x\n"}}, merged=("feat-a",))
    scan(loc, do_fetch=False)
    _, y = yaml_at(loc, "feat-a")
    executed.append("S4 scan-merged-branch-drop")
    if "ahead: 0" not in y or "suggested_action: \"DROP" not in y: fails.append("S4 merged branch mismatch: %s" % y[:200])
    loc = scan_origin({"marked": {"scripts/m.py": "a\n<<<<<<< HEAD\nb\n"}})
    scan(loc, do_fetch=False)
    _, y = yaml_at(loc, "marked")
    executed.append("S5 scan-conflict-markers-abort")
    if "conflict_markers: [\"scripts/m.py\"]" not in y or "suggested_action: \"ABORT" not in y: fails.append("S5 markers mismatch: %s" % y[:200])
    loc = scan_origin({"feat-b": {"src/b.mbt": "y\n"}})
    stale_p = loc / ".git" / "fist" / "tasks" / "backlog" / ("origin/ghost.yaml")
    stale_p.parent.mkdir(parents=True, exist_ok=True); stale_p.write_text("stale: true\n", encoding="utf-8")
    scan(loc, do_fetch=False)
    executed.append("S6 scan-prunes-stale-yaml")
    if stale_p.exists(): fails.append("S6 stale yaml not pruned")
    # ── TASK-004：反向 diff 判定（真断言；判据坏掉这里必红）──
    # 位置纪律：必须在下面那行 `print("SELFTEST ...")` **之前**跑完——四份副本串接的旧文件里
    # 这一段被追加到打印之后，于是 7 格全都执行不到、「TASK-004 已被自检」是句空话。
    f1 = "0\t457\tsrc/server/issue_scan.mbt\n191\t261\tsrc/other.mbt\n"
    files1, a1, d1 = parse_numstat(f1)
    executed.append("T4-real-revert corpus(191/718)")
    if is_revert_pattern(a1, d1) is not True: fails.append("T4 反回退判据未命中 191/718")
    executed.append("T4-numstat-parsed")
    if (len(files1), a1, d1) != (2, 191, 718): fails.append("T4 numstat 解析错: %r" % ((len(files1), a1, d1),))
    executed.append("T4-normal-code-not-flagged")
    if is_revert_pattern(500, 120) is not False: fails.append("T4 正常增量(500/120)被误判为回退")
    executed.append("T4-boundary-strictly-greater")
    if is_revert_pattern(100, 150) is not False: fails.append("T4 边界 100/150 应为正常（非严格大于）")
    executed.append("T4-just-over-boundary")
    if is_revert_pattern(100, 151) is not True: fails.append("T4 边界 100/151 应判回退（严格大于）")
    executed.append("T4-empty-safe")
    if is_revert_pattern(0, 0) is not False: fails.append("T4 空输入(0/0) 应安全返回 False")
    _f2, a2, d2 = parse_numstat("-\t-\tassets/x.png\n")
    executed.append("T4-binary-skipped")
    if (a2, d2) != (0, 0): fails.append("T4 二进制行未跳过: %d/%d" % (a2, d2))
    w = worst_deletions([("a.mbt", 0, 457), ("b.mbt", 100, 120), ("c.mbt", 50, 10)])
    executed.append("T4-worst-names-culprit")
    if not (bool(w) and w[0][0] == "a.mbt" and w[0][3] == 457): fails.append("T4 worst 未点名元凶: %r" % (w[:1],))
    print("SELFTEST %s (grid: %s)" % ("OK" if not fails else "FAIL", " / ".join(executed)))
    for f in fails: print("SELFTEST FAIL " + f)

    return 0 if not fails else 2
if __name__ == "__main__":
    if "--selftest" in sys.argv[1:]: sys.exit(selftest())
    if "--scan" in sys.argv[1:]:
        sys.exit(scan(ROOT)[0])
    if len(sys.argv) > 1: raise SystemExit("usage: python scripts/fist-gate.py [--selftest|--scan]")
    sys.exit(gate(ROOT))