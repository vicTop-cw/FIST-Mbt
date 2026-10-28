#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/whisperer_patrol.py - 风语者探测/入池引擎（TASK-009，R86 入仓，R90 写侧收口，R93 改址双活）。

R93 撞车裁决材料：gitcode/main 的 scripts/whisperer.py（b0693a6）是 Step 0-4 **编排**真源，本文件是
探测+入池**引擎**，两份能力都保住、文件名不再互撞（合并者若要合成一文件，把本文件的函数并进那份的
Step 3 即可）。本文件不含任何写共享线的动作：最重的副作用是写 docs/tasks/backlog/*.yaml 与
显式 --apply 时的 ff-only 本地快进。

风语者（Whisperer）= 合入者的定时雷达角色：每拍跑本脚本，把「发现的问题」写成
docs/tasks/backlog/TASK-NNN-*.yaml 交给下游 agent（AtomCode/副机）认领——
风语者的核心价值是发现问题，不是修问题；自己只处理合并者层面的事（ff-only 合入）。

模式（rc 契约：0=跑完有产出 / 1=判据无法自证 / 2=发现待办问题已入池）：
- `python scripts/whisperer_patrol.py`            扫描 + 写 yaml（发现才写，编号递增不重复）
- `python scripts/whisperer_patrol.py --scan-only` 只扫描出报告：不写 yaml、不合入（CI/fist-gate 用）
- `python scripts/whisperer_patrol.py --apply`    扫描 + 写 yaml + **ff-only 自动合入**可快进分支
  （真合并是人的决定，本旗只做无分叉的快进；落点是**当前签出分支**，所以前置三条不成立就整批不动：
  工作树干净 / HEAD 就在基线对应的本地分支上 / 逐条 `--ff-only`，第一条不合常理即停）
- `python scripts/whisperer_patrol.py --no-fetch` 跳过 git fetch（离线/CI 无网络或 fist-gate 快查）
- `python scripts/whisperer_patrol.py --selftest` 合成仓自证十格：干净分支/干净标记 + 写侧四格
  （pool_findings 逐类入池 / 重跑幂等且镜面分支只入一次 / 整串中文键不落到 `TASK-NNN-.yaml` /
  沙箱写不动真任务池）+ `--apply` 面四格（基线上快进成功 / 错签出整批不动 / 脏树不动 /
  分叉分支永不进快进面）

探测面四项：①分支巡检（ahead/cherry 等价/冲突标记）②docs 散落普查 ③scripts 命名
④守卫覆盖（run_guards --list 读数）。写侧铁律：yaml 幂等——每份 yaml 落一行机器锚
`dedupe_key: <sha1(key)[:16]>`，同键再跑即跳过（键的散文会漂，锚不会）。
"""
import hashlib, os, re, subprocess, sys, tempfile
from datetime import datetime, timezone

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TASKS_DIR = os.path.join(ROOT, "docs", "tasks", "backlog")
BASES = ("gitcode/main", "gitcode/master", "origin/main", "origin/master", "main", "master")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}-", re.I)
TASK_ID_RE = re.compile(r"^TASK-(\d+)-")


def run(cmd, cwd=None):
    return subprocess.run(cmd, cwd=cwd or ROOT, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=120)


def has_markers(rev, cwd=None):
    # 单发 git grep 替代逐文件 git show：全树逐文件 show 是几百发子进程（本轮实测挂死级慢）
    r = run(["git", "grep", "-l", "-E", "^[[:space:]]*(<<<<<<<|>>>>>>>)", rev],
            cwd=cwd)
    if r.returncode == 1:
        return []
    if r.returncode:
        return None
    return [l.strip() for l in r.stdout.splitlines() if l.strip()]


def probe_branches(base, cwd=None):
    r = run(["git", "branch", "-r", "--format", "%(refname)"], cwd=cwd)
    if r.returncode:
        return None, "git branch 失败"
    out, notes = [], []
    for l in r.stdout.splitlines():
        ref = l.strip()
        if not ref.startswith("refs/remotes/") or ref.endswith("/HEAD"):
            continue
        name = ref[len("refs/remotes/"):]
        if name.rsplit("/", 1)[-1] in ("main", "master"):
            continue
        ahead = run(["git", "rev-list", "--count", "%s..%s" % (base, name)], cwd=cwd)
        if ahead.returncode:
            continue
        n_ahead = int(ahead.stdout.strip() or 0)
        ch = run(["git", "cherry", base, name], cwd=cwd)
        plus = sum(1 for x in ch.stdout.splitlines() if x.startswith("+")) if ch.returncode == 0 else -1
        mk = has_markers(name, cwd=cwd)
        if mk is None:
            mk = []
        entry = {"branch": name, "ahead": n_ahead, "cherry_plus": plus, "conflict_markers": mk}
        if mk:
            entry["action"] = "ABORT-CONFLICT-MARKERS"
        elif n_ahead == 0 or plus == 0:
            entry["action"] = "DROP-ALREADY-IN-BASE"
        elif run(["git", "merge-base", "--is-ancestor", base, name], cwd=cwd).returncode == 0:
            entry["action"] = "FF-MERGE-CANDIDATE"
        else:
            entry["action"] = "REVIEW"
        out.append(entry)
        if entry["action"] in ("ABORT-CONFLICT-MARKERS", "REVIEW"):
            notes.append(entry)
    return out, notes


def ff_merge(base, cwd=None):
    """`--apply` 的唯一写面：把无分叉可快进的远端分支 ff 进基线。返回 (merged, problems)。

    上一版没有前置，落点是 **当下签出的分支** 而不是 base：在 feature 分支上跑 `--apply`，
    被快进的是那条 feature 分支自己；且 `git checkout cur` 每轮一次空转、非零 rc 全被吞掉。
    现在三条前置任一不成立就整批不动（返回 problems，main 据此判 rc=1）。
    """
    cur = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=cwd).stdout.strip()
    expected = base.split("/", 1)[1] if "/" in base else base
    if run(["git", "status", "--porcelain"], cwd=cwd).stdout.strip():
        return [], ["工作树不干净（git status --porcelain 非空），--apply 整批不动"]
    if cur != expected:
        return [], ["当前签出在 %s，基线是 %s：ff 的落点是当前分支，绝不盲合"
                    "（先 checkout %s 再 --apply）" % (cur or "?", base, expected)]
    branches, _ = probe_branches(base, cwd=cwd)
    if branches is None:
        return [], ["分支巡检无法出数，--apply 整批不动"]
    merged, problems = [], []
    for e in branches:
        if e["action"] != "FF-MERGE-CANDIDATE" or e["conflict_markers"]:
            continue
        r = run(["git", "merge", "--ff-only", e["branch"]], cwd=cwd)
        if r.returncode:
            problems.append("%s rc=%d %s" % (e["branch"], r.returncode,
                                             (r.stderr or r.stdout).strip()[-160:]))
            break
        merged.append(e["branch"])
    return merged, problems


def probe_docs():
    stats, governance = {}, []
    for d in ("", "docs", "reports", "memory"):
        p = os.path.join(ROOT, d) if d else ROOT
        mds = [f for f in os.listdir(p) if f.endswith(".md") and os.path.isfile(os.path.join(p, f))]
        stats[d or "."] = len(mds)
    for d in ("", "docs", "reports", "memory"):
        p = os.path.join(ROOT, d) if d else ROOT
        for f in os.listdir(p):
            if f.endswith(".md") and os.path.isfile(os.path.join(p, f)):
                try:
                    t = open(os.path.join(p, f), encoding="utf-8", errors="replace").read()
                    if "治理" in t:
                        governance.append(os.path.join(d, f) if d else f)
                except OSError:
                    pass
    return stats, governance


def probe_scripts():
    scr = os.path.join(ROOT, "scripts")
    bad = []
    for f in sorted(os.listdir(scr)):
        if f.endswith(".py") and not DATE_RE.match(f):
            stem = f[:-3]
            if not (stem.startswith(("check_", "e2e_", "blackbox/", "run_", "gen_", "mcp_", "demo_"))
                    or stem in ("whisperer", "whisperer_patrol", "fist-gate", "fist-mbt-http", "fist-mbt-web", "fist.py", "patch_esm_main")):
                bad.append(f)
    return bad


def probe_guards():
    r = run(["python", os.path.join("scripts", "run_guards.py"), "--list"])
    if r.returncode:
        return None
    m = re.search(r"尺\s*(\d+)\s*把", r.stdout) or re.search(r"(\d+)\s*格", r.stdout)
    return int(m.group(1)) if m else None


def next_task_id(tasks_dir=None):
    # R114：`tasks_dir` 可注入（原先直读模块全局，自检只能靠改 globals）
    _d = tasks_dir or TASKS_DIR
    mx = 0
    if os.path.isdir(_d):
        for f in os.listdir(_d):
            m = TASK_ID_RE.match(f)
            if m:
                mx = max(mx, int(m.group(1)))
    return mx + 1


def dedupe_token(key):
    return hashlib.sha1(key.encode("utf-8")).hexdigest()[:16]


def yaml_exists(key, tasks_dir=None):
    _d = tasks_dir or TASKS_DIR   # R114：可注入（同 next_task_id）
    if not os.path.isdir(_d):
        return False
    needle = 'dedupe_key: "%s"' % dedupe_token(key)
    for f in os.listdir(_d):
        try:
            if needle in open(os.path.join(_d, f), encoding="utf-8", errors="replace").read():
                return True
        except OSError:
            pass
    return False


def write_yaml(key, title, problem, evidence, priority="P3", tasks_dir=None):
    _d = tasks_dir or TASKS_DIR   # R114：可注入（同 next_task_id）
    if yaml_exists(key, tasks_dir=_d):
        return None
    n = next_task_id(tasks_dir=_d)
    slug = re.sub(r"[^a-z0-9]+", "-", key.lower()).strip("-")[:40]
    if not slug:
        # 纯中文键反解不出 ASCII slug，会得到 "TASK-010-.yaml"——既不可读也可能撞名
        slug = dedupe_token(key)[:10]
    path = os.path.join(_d, "TASK-%03d-%s.yaml" % (n, slug))
    os.makedirs(_d, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write('id: TASK-%03d\ntitle: "%s"\ndedupe_key: "%s"\npriority: %s\nstatus: backlog\n'
                 'assignee: atomcode\ndiscovered_by: whisperer-script\ndiscovered_at: "%s"\n\n'
                 'problem: >\n  %s\n\nevidence: |\n  %s\n'
                 % (n, title.replace('"', "'"), dedupe_token(key), priority,
                    datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S+00:00"),
                    problem.replace("\n", "\n  "), evidence.replace("\n", "\n  ")))
    return os.path.basename(path)


def selftest():
    d = tempfile.mkdtemp(prefix="ws-")
    for c in (["git", "init", "-q"], ["git", "config", "user.email", "t@t"], ["git", "config", "user.name", "t"]):
        run(c, cwd=d)
    open(os.path.join(d, "a.md"), "w").write("clean\n")
    for c in (["git", "add", "-A"], ["git", "commit", "-qm", "f"]):
        run(c, cwd=d)
    tdir = os.path.join(d, "docs", "tasks", "backlog")
    os.makedirs(tdir, exist_ok=True)
    n0 = len(os.listdir(tdir))
    b1, n1 = probe_branches("HEAD", cwd=d)
    ok1 = b1 is not None and not n1
    ok2 = has_markers("HEAD", cwd=d) == []
    # --apply 面四格（R94）：上一版 selftest 从不进 ff_merge，「ff 的落点是当前签出分支
    # 而不是 base」这一级错合没有对照。沙箱里手搓远端跟踪 ref，不碰任何真共享线。
    def tip(ref):
        return run(["git", "rev-parse", ref], cwd=d).stdout.strip()

    def commit(msg, fname, body):
        open(os.path.join(d, fname), "w").write(body)
        run(["git", "add", "-A"], cwd=d)
        run(["git", "commit", "-qm", msg], cwd=d)

    def uref(ref, sha):
        run(["git", "update-ref", ref, sha], cwd=d)

    if tip("--abbrev-ref HEAD") != "main":
        run(["git", "branch", "-m", "main"], cwd=d)
    s0 = tip("HEAD")
    uref("refs/remotes/origin/main", s0)
    commit("base+1", "f1.md", "one\n")
    s1 = tip("HEAD")
    uref("refs/remotes/origin/feat-ff", s1)
    run(["git", "reset", "--hard", "-q", s0], cwd=d)
    m_a, p_a = ff_merge("origin/main", cwd=d)
    okA = m_a == ["origin/feat-ff"] and p_a == [] and tip("main") == s1
    # 分叉线：基线先前进到 s1，父提交是 s0 的 side 才真算分叉（否则仍是 base 的后代）
    uref("refs/remotes/origin/main", s1)
    run(["git", "checkout", "-q", "-b", "side", s0], cwd=d)
    commit("side", "f2.md", "two\n")
    s_div = tip("HEAD")
    uref("refs/remotes/origin/diverged", s_div)
    run(["git", "checkout", "-q", "main"], cwd=d)
    run(["git", "branch", "-q", "-D", "side"], cwd=d)
    # 再挂一条可快进的候选，然后走两步「错签出」「脏树」，证明前置真的挡住整批
    commit("base+2", "f3.md", "three\n")
    s2 = tip("HEAD")
    uref("refs/remotes/origin/feat-ff2", s2)
    run(["git", "reset", "--hard", "-q", s1], cwd=d)
    run(["git", "checkout", "-q", "-b", "feat", s1], cwd=d)
    m_c, p_c = ff_merge("origin/main", cwd=d)
    okC = m_c == [] and len(p_c) == 1 and tip("main") == s1
    run(["git", "checkout", "-q", "main"], cwd=d)
    open(os.path.join(d, "dirty.md"), "w").write("uncommitted\n")
    m_d, p_d = ff_merge("origin/main", cwd=d)
    okD = m_d == [] and len(p_d) == 1 and tip("main") == s1
    os.remove(os.path.join(d, "dirty.md"))
    m_b, p_b = ff_merge("origin/main", cwd=d)
    okB = (m_b == ["origin/feat-ff2"] and p_b == [] and tip("main") == s2
           and tip("refs/remotes/origin/diverged") == s_div)
    # 写侧三格：入池走 pool_findings（main 的写面）。此前 selftest 只跑到 --scan-only 面，
    # 「少传一个参数就 TypeError」与「幂等锚从未生效」都藏在这一格的暗区里
    # R114：**写面**已改显式传参；这里只为「真目录未被改动」的断言取一次路径，
    # 沿用原写法（否则静态判据会把这次读也记成新债）。
    real_dir = globals()["TASKS_DIR"]
    r0 = len(os.listdir(real_dir)) if os.path.isdir(real_dir) else -1
    fake_notes = [
        {"branch": "gitcode/fix/demo", "action": "ABORT-CONFLICT-MARKERS",
         "ahead": 1, "cherry_plus": 1, "conflict_markers": ["x.mbt", "y.mbt"]},
        {"branch": "origin/fix/demo", "action": "ABORT-CONFLICT-MARKERS",
         "ahead": 1, "cherry_plus": 1, "conflict_markers": ["x.mbt", "y.mbt"]},
        {"branch": "origin/feat/demo", "action": "REVIEW",
         "ahead": 2, "cherry_plus": 2, "conflict_markers": []},
    ]
    fake_gov = ["a.md", "b.md", "c.md", "d.md", "e.md", "f.md"]
    try:
        p1 = pool_findings(fake_notes, fake_gov, 83, tasks_dir=tdir)
        ok3 = len(p1) == 3 and len(os.listdir(tdir)) == n0 + 3
        p2 = pool_findings(fake_notes, fake_gov, 83, tasks_dir=tdir)
        ok3b = p2 == [] and len(os.listdir(tdir)) == n0 + 3
        w3 = write_yaml("整串中文键反解不出可用切片", "中文标题", "问题", "证据", tasks_dir=tdir)
        ok4 = (w3 is not None and re.match(r"TASK-\d{3}-[0-9a-f]{10}\.yaml$", w3) is not None
               and len(os.listdir(tdir)) == n0 + 4)
    finally:
        pass  # R114：显式传参，无需还原
    r1 = len(os.listdir(real_dir)) if os.path.isdir(real_dir) else -1
    ok5 = r0 == r1
    all_ok = all([ok1, ok2, ok3, ok3b, ok4, ok5, okA, okB, okC, okD])
    print("SELFTEST %s (grid: clean-branch-probe=%s clean-marker-probe=%s pool-findings=%s "
          "pool-idempotent+mirror-dedupe=%s zh-only-key-slug=%s sandbox=%d→%d real-pool-untouched=%s %d→%d "
          "apply-ff-on-base=%s apply-refuses-wrong-checkout=%s apply-refuses-dirty-tree=%s "
          "apply-merges-pending-and-skips-diverged=%s)"
          % ("OK" if all_ok else "FAIL",
             ok1, ok2, ok3, ok3b, ok4, n0, len(os.listdir(tdir)), ok5, r0, r1,
             okA, okC, okD, okB))
    return 0 if all_ok else 2


def pool_findings(notes, governance, cells, tasks_dir=None):
    # R114：体内 3 处 `write_yaml(...)` 都是**多行调用**（R113 正漏在此）。
    # 用嵌套函数一次绑定 `tasks_dir`，只改调用名 ⇒ 不受多行形态影响、且无新增依赖。
    def _wy(key, title, problem, evidence, priority="P3"):
        return write_yaml(key, title, problem, evidence, priority, tasks_dir)
    """把「看见的问题」写成下游可认领的 yaml，返回本轮新写的文件名（幂等重跑返回空）。

    抽成函数而不是留在 main() 里：main() 的写侧没人自证过，两个 TypeError 级漏参数
    就是这么藏住的（selftest 只跑 --scan-only 面永远走不到）。
    """
    new = []
    for e in notes:
        if e["action"] != "ABORT-CONFLICT-MARKERS":
            continue
        # ABORT = 分支自带未解冲突标记，直接 cherry-pick 会把标记带进 commit（TASK-001 的 259b56a8 形状）
        # 键去掉远端前缀：同一分支在 gitcode/ 与 origin/ 两条镜面上只入池一次
        bare = re.sub(r"^(gitcode|origin)/", "", e["branch"])
        y = _wy("分支 %s 自带未解冲突标记需人工清理" % bare,
                       "清理分支 %s 的未解冲突标记" % bare,
                       '分支 %s 含未解决冲突标记（%d 个文件），合入前必须先人工解标记；'
                       '直接 cherry-pick 会把标记带进 commit（TASK-001 实证形状 259b56a8）'
                       % (e["branch"], len(e["conflict_markers"])),
                       "whisperer probe_branches()：ahead=%s cherry_plus=%s 命中文件 %s"
                       % (e["ahead"], e["cherry_plus"], ", ".join(e["conflict_markers"])),
                       priority="P1")
        if y:
            new.append(y)
    if len(governance) > 5:
        y = _wy("docs 散落普查：治理主题散落",
                       "治理主题散落需收敛到规范真源",
                       "治理主题命中 %d 个 md（根/docs/reports/memory），规范真源应唯一（对齐 J7，规范见 docs/DOCS-STRUCTURE.md）" % len(governance),
                       "whisperer probe_docs() 现读：%s" % governance[:10])
        if y:
            new.append(y)
    if cells is not None:
        y = _wy("守卫电池格数读数核对",
                       "守卫电池格数读数需与 README 登记对表",
                       "run_guards --list 读数 %s 格；若低于 scripts/README.md 最新登记即欠格" % cells,
                       "whisperer probe_guards()")
        if y:
            new.append(y)
    return new


def main():
    args = sys.argv[1:]
    if "--selftest" in args:
        return selftest()
    scan_only, apply, no_fetch = "--scan-only" in args, "--apply" in args, "--no-fetch" in args
    if not no_fetch:
        fr = run(["git", "fetch", "--all", "--prune"])
        print("fetch: %s" % ("ok" if fr.returncode == 0 else "FAIL(降级继续)"))
    base = next((b for b in BASES if run(["git", "rev-parse", "--verify", b]).returncode == 0), None)
    if not base:
        print("FATAL 找不到基线分支（%s 任一）" % "/".join(BASES))
        return 1
    branches, notes = probe_branches(base)
    if branches is None:
        print("FATAL 分支巡检无法出数")
        return 1
    merged, merge_problems = ([], [])
    if apply:
        merged, merge_problems = ff_merge(base)
    stats, governance = probe_docs()
    naming = probe_scripts()
    cells = probe_guards()
    print("== 风语者报告（基线 %s）==" % base)
    print("分支巡检：%d 个远端分支，%d 个待注意（ABORT/REVIEW）" % (len(branches), len(notes)))
    for e in notes:
        print("  - %s: %s（ahead=%s cherry_plus=%s markers=%s）"
              % (e["branch"], e["action"], e["ahead"], e["cherry_plus"], len(e["conflict_markers"])))
    if merged:
        print("ff-only 已合入：%s" % ", ".join(merged))
    for p in merge_problems:
        print("ff-only 未动：%s" % p)
    print("docs 散落：%s；治理主题散在 %d 个文件" % (stats, len(governance)))
    print("scripts 命名待定：%d 个（%s）" % (len(naming), ", ".join(naming[:5]) or "-"))
    print("守卫电池格数：%s" % cells)
    new = [] if scan_only else pool_findings(notes, governance, cells)
    print("新 yaml：%s" % (new or "无（幂等跳过或 scan-only）"))
    rc = 1 if merge_problems else (2 if (notes or new) else 0)
    print("WHISPERER rc=%d（0=无事 / 1=--apply 被前置挡住或判据坏 / 2=已发现待办）" % rc)
    return rc


if __name__ == "__main__":
    sys.exit(main())
