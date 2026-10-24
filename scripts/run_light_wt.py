#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""scripts/run_light_wt.py — 轻量 worktree 沙箱的生命周期入口（主机清单 WT-03 的第一格）。

**为什么要有它**（本机实测的形状）：副机与主机共用同一个仓库目录时，多条车道同时
`git checkout` / `git worktree add` 会互相踩工作树；`docs/plan-light-worktree-isolation.md`
为此设计了 light worktree——按任务开一个 **sparse cone** 的沙箱，只铺 1~3 个包，分钟级 TTL，
用完焚掉。plan 的 P1 验收两格就写在这份文件的 §4：`light-wt` 创建出 sparse cone 沙箱且磁盘占用显著
低于全量 checkout；`light-wt-teardown` 幂等回收、`worktree prune` 后无残留。本脚本落的就是这两格
（+ `status` 那一档状态机，供后续 collector 消费）。

**为什么是 Python 而不是 plan §4 里的 PowerShell 主轨**：本仓的守卫宇宙（`scripts/run_guards.py`）
只自动发现 `scripts/**/*.py`，`.ps1` 进不了电池、拿不到 `--selftest` 契约格，也就拿不到「这一格今天真跑过」
的证据；PS 那条轨留给 `bin/`（未落地，见清单 WT-03 的 `部分` 语义差）。这是有意的偏离，不是遗漏。

**为什么叫 `run_` 前缀**：`scripts/NAMING.md` 定律 1 要求角色写在名字两端之一，而判据
`check_scripts_naming.py` 的 N1（无角色名存量 22 份 > 上限 16）是**只许下降的棘轮**——一个新脚本
不该是新增的一条债。`run_`=「编排/跑手：把一串别的脚本跑起来并汇总」正是本体的形状
（串 `git worktree add` / `sparse-checkout set` / `merge-base` / `worktree remove` 并出读数）；
不选 `cleanup_` 因为它还负责创建，不选 `check_` 因为它产出的是动作而非裁决。

**危险面纪律**（本脚本会写盘、会删工作树）：
- 只动自己在 manifest 里登过的路径；目录存在但不在自己账上 ⇒ 拒绝，不删陌生目录；
- 沙箱脏（有未提交改动）或有未并入 base 的提交 ⇒ 默认拒绝回收；`--force` 只对工作树生效，
  **分支一律保留**（删分支是不可逆动作，交回人）；
- 因此它**不进电池裸跑格**：`run_guards` 只点名它的 `--selftest`（见 SPECIAL_CASES）。

子命令：
  create   --repo R --task ID [--cone src/a,src/b] [--base REF] [--root DIR] [--branch NAME] [--ttl-min N]
  teardown --repo R --task ID [--root DIR] [--force] [--keep-branch]
  status   --repo R [--root DIR] [--json]
  --selftest

退出码契约（BUG-369 同族）：
  0 = 动作成功 / 幂等命中（已创建、已回收）
  1 = 被拒（脏沙箱、未并入分支、陌生目录）——这是保护，不是崩溃
  2 = 判据无法自证：参数不认、repo 不是 git 仓库、status 判定面为空（绝不冒绿）
  4 = 尺子自己坏了（未捕获异常，绝不冒用 1 那一档）
"""

import argparse
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

TOOLS = ("create", "teardown", "status")
DEFAULT_TTL_MIN = 240
NO_SPARSE_ENV = "LIGHT_WT_NO_SPARSE"
_SPARSE_OK = None   # 探针缓存：None=还没试过 / True=本机认这面旗 / False=本机不认

# BUG-138：正文有中文与 `⇒`，Windows 默认 cp936 控制台上 print 会先抛 UnicodeEncodeError，
# 把「判据自己的崩」冒用成被测的退出码。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")


def run(argv, cwd=None):
    """git 调用统一走这里：不经 shell、不吃 stdin、utf-8 解码。"""
    return subprocess.run(list(argv), cwd=cwd, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", stdin=subprocess.DEVNULL)


def now_ts():
    return int(time.time())


def root_of(args, repo):
    """沙箱根目录：显式 --root > 环境变量 LIGHT_WT_ROOT > <repo>/../light-wt。"""
    if getattr(args, "root", None):
        return os.path.abspath(os.path.expanduser(args.root))
    env = os.environ.get("LIGHT_WT_ROOT", "").strip()
    if env:
        return os.path.abspath(os.path.expanduser(env))
    return os.path.abspath(os.path.join(repo, "..", "light-wt"))


def manifest_path(root, task):
    return os.path.join(root, "light-wt-%s.json" % task)


def load_manifest(path):
    if not os.path.isfile(path):
        return None
    with io.open(path, encoding="utf-8") as f:
        return json.load(f)


def save_manifest(path, data):
    if not os.path.isdir(os.path.dirname(path)):
        os.makedirs(os.path.dirname(path))
    with io.open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n")


def is_git_repo(repo):
    if not os.path.isdir(repo):
        return False
    r = run(["git", "rev-parse", "--is-inside-work-tree"], cwd=repo)
    return r.returncode == 0 and r.stdout.strip() == "true"


def unknown_option(stderr):
    return "unknown option" in (stderr or "").lower()


def worktree_add_sandbox(repo, path, branch, base):
    """建沙箱，返回 (rc, stderr, route)。

    `--sparse` 让 worktree 从「什么都不铺」起步，但**本机实测用不上**：Git for Windows
    自报 2.51.0.windows.2（git 2.32 就收了这面旗），`worktree add --sparse` 仍回
    rc=129 `unknown option \\`sparse\\``。所以这里探针 + 回退：先按 sparse 走，只有当失败
    形状是「不认识这面旗」才退回普通 add（随后由 `sparse-checkout set --cone` 收窄，
    终态工作树一样是小的，只是创建时多铺一遍）；其它失败（分支已存在、路径被占）一律
    原样报出，**不许把真错伪装成回退**。
    """
    global _SPARSE_OK
    if os.environ.get(NO_SPARSE_ENV, "").strip() in ("1", "true", "yes"):
        _SPARSE_OK = False
    if _SPARSE_OK is not False:
        r = run(["git", "worktree", "add", "--sparse", path, "-b", branch, base], cwd=repo)
        if r.returncode == 0:
            _SPARSE_OK = True
            return 0, r.stderr, "sparse"
        if not unknown_option(r.stderr):
            return r.returncode, r.stderr, "sparse"
    r = run(["git", "worktree", "add", path, "-b", branch, base], cwd=repo)
    if r.returncode == 0:
        _SPARSE_OK = False
    return r.returncode, r.stderr, "plain"


def worktree_count(repo):
    r = run(["git", "worktree", "list", "--porcelain"], cwd=repo)
    if r.returncode != 0:
        raise RuntimeError("git worktree list 失败: %s" % (r.stderr or "").strip())
    return len([ln for ln in r.stdout.splitlines() if ln.startswith("worktree ")])


def tree_bytes(path):
    """工作树磁盘占用（不含 .git 文件本身；沙箱目录里的 .git 只是一个指针文件）。"""
    total = 0
    for dirpath, dirnames, filenames in os.walk(path):
        if os.path.basename(dirpath) == "__pycache__":
            continue
        for fn in filenames:
            fp = os.path.join(dirpath, fn)
            try:
                total += os.path.getsize(fp)
            except OSError:
                pass
    return total


def dirty(path):
    r = run(["git", "status", "--porcelain"], cwd=path)
    if r.returncode != 0:
        return None
    return bool(r.stdout.strip())


def branch_merged_into(repo, branch, base):
    """分支是否已并入 base：只能由 git 说，不靠分支名猜。"""
    r = run(["git", "merge-base", "--is-ancestor", branch, base], cwd=repo)
    if r.returncode == 0:
        return True
    if r.returncode == 1:
        return False
    return None


def cmd_create(args):
    repo = os.path.abspath(os.path.expanduser(args.repo))
    if not is_git_repo(repo):
        sys.stdout.write("REJECT not-a-git-repo: %s\n" % repo)
        return 2
    base = args.base or os.environ.get("FIST_BASE", "").strip() or "HEAD"
    root = root_of(args, repo)
    path = os.path.join(root, args.task)
    mpath = manifest_path(root, args.task)
    branch = args.branch or ("lightwt/%s" % args.task)

    old = load_manifest(mpath)
    if old and os.path.isdir(old["path"]) and is_git_repo(old["path"]):
        old["renewed_at"] = now_ts()
        old["created_at"] = old.get("created_at", now_ts())
        old["ttl_min"] = args.ttl_min
        old["status"] = "fresh"
        save_manifest(mpath, old)
        sys.stdout.write("ALREADY task=%s path=%s branch=%s（幂等续期，未开第二个 worktree）\n"
                         % (args.task, old["path"], old["branch"]))
        return 0
    if os.path.exists(path):
        sys.stdout.write("REJECT path-exists-but-unregistered: %s（不在本工具账上，不删陌生目录）\n" % path)
        return 1

    cone = [c.strip() for c in (args.cone or "").split(",") if c.strip()]
    rc, err, route = worktree_add_sandbox(repo, path, branch, base)
    if rc != 0:
        sys.stdout.write("FAIL worktree-add rc=%d route=%s: %s\n" % (rc, route, (err or "").strip()))
        return 1
    if cone:
        r2 = run(["git", "sparse-checkout", "set", "--cone"] + cone, cwd=path)
        if r2.returncode != 0:
            sys.stdout.write("FAIL sparse-checkout rc=%d: %s\n" % (r2.returncode, (r2.stderr or "").strip()))
            return 1
    save_manifest(mpath, {
        "id": args.task, "repo": repo, "path": path, "branch": branch, "base": base,
        "cone": cone, "created_at": now_ts(), "ttl_min": args.ttl_min, "status": "fresh",
        "sparse_route": route, "tool": "run_light_wt.py",
    })
    sys.stdout.write("CREATED task=%s path=%s branch=%s cone=%d route=%s 磁盘=%d B\n"
                     % (args.task, path, branch, len(cone), route, tree_bytes(path)))
    return 0


def cmd_teardown(args):
    repo = os.path.abspath(os.path.expanduser(args.repo))
    root = root_of(args, repo)
    mpath = manifest_path(root, args.task)
    m = load_manifest(mpath)
    if not m:
        if os.path.isdir(os.path.join(root, args.task)):
            sys.stdout.write("REJECT unregistered-dir: %s（没有 manifest 就不动手）\n"
                             % os.path.join(root, args.task))
            return 1
        sys.stdout.write("GONE task=%s（幂等：账上已无此沙箱）\n" % args.task)
        return 0
    if not is_git_repo(repo):
        sys.stdout.write("REJECT not-a-git-repo: %s（账还在，动手要回仓库）\n" % repo)
        return 2
    path = m["path"]
    if not os.path.isdir(path):
        run(["git", "worktree", "prune"], cwd=repo)
        os.remove(mpath)
        sys.stdout.write("GONE task=%s（目录已不在，顺手 prune + 清账）\n" % args.task)
        return 0

    base = m.get("base", "HEAD")
    merged = branch_merged_into(repo, m["branch"], base)
    d = dirty(path)
    if (d or merged is False) and not args.force:
        why = []
        if d:
            why.append("工作树脏")
        if merged is False:
            why.append("分支未并入 %s" % base)
        sys.stdout.write("REJECT task=%s：%s ⇒ 要回收请显式 --force\n" % (args.task, " / ".join(why)))
        return 1

    cmd = ["git", "worktree", "remove", path] + (["--force"] if args.force else [])
    r = run(cmd, cwd=repo)
    if r.returncode != 0:
        sys.stdout.write("FAIL worktree-remove rc=%d: %s\n" % (r.returncode, (r.stderr or "").strip()))
        return 1
    run(["git", "worktree", "prune"], cwd=repo)
    os.remove(mpath)
    kept = ""
    if not args.keep_branch and merged is True:
        rb = run(["git", "branch", "-d", m["branch"]], cwd=repo)
        kept = "branch=deleted" if rb.returncode == 0 else "branch=kept(%s)" % (rb.stderr or "").strip()[:60]
    else:
        kept = "branch=kept"
    sys.stdout.write("TORN-DOWN task=%s %s\n" % (args.task, kept))
    return 0


def classify(m, repo):
    """状态机（fresh/stale/blocked/merged/abandoned）——判定全部来自 git 与时间戳，不靠猜。"""
    path = m["path"]
    if not os.path.isdir(path):
        return "abandoned", {"reason": "worktree 目录不在，账还留着"}
    merged = branch_merged_into(repo, m["branch"], m.get("base", "HEAD"))
    if merged is True:
        return "merged", {}
    d = dirty(path)
    if d:
        return "blocked", {"reason": "工作树有未提交改动"}
    age_min = (now_ts() - int(m.get("created_at", now_ts()))) / 60.0
    if age_min > m.get("ttl_min", DEFAULT_TTL_MIN):
        return "stale", {"age_min": int(age_min), "ttl_min": m.get("ttl_min")}
    return "fresh", {"age_min": int(age_min)}


def cmd_status(args):
    repo = os.path.abspath(os.path.expanduser(args.repo))
    if not is_git_repo(repo):
        sys.stdout.write("REJECT not-a-git-repo: %s\n" % repo)
        return 2
    root = root_of(args, repo)
    rows = []
    if os.path.isdir(root):
        for fn in sorted(os.listdir(root)):
            if fn.startswith("light-wt-") and fn.endswith(".json"):
                m = load_manifest(os.path.join(root, fn))
                if not m:
                    continue
                st, extra = classify(m, repo)
                rows.append({"task": m["id"], "state": st, "path": m["path"],
                             "branch": m["branch"], "extra": extra})
    if not rows:
        sys.stdout.write("EMPTY 判定面=0（%s 下没有任何 light-wt 账）⇒ 自拒，不报绿\n" % root)
        return 2
    tally = {}
    for r in rows:
        tally[r["state"]] = tally.get(r["state"], 0) + 1
    if args.json:
        sys.stdout.write(json.dumps({"root": root, "sandboxes": rows, "tally": tally},
                                   ensure_ascii=False, sort_keys=True) + "\n")
    else:
        for r in rows:
            sys.stdout.write("%-10s %-28s %s\n" % (r["state"], r["task"], r["path"]))
        sys.stdout.write("汇总：" + " ".join("%s=%d" % kv for kv in sorted(tally.items()))
                         + " / 共 %d 个沙箱\n" % len(rows))
    return 0


# ============================================================
# --selftest：判定面全部在临时仓里跑，绝不碰调用方的工作树
# ============================================================

def fixture_repo():
    """造一个两目录多文件的小仓，返回 (repo, base_branch)。"""
    d = tempfile.mkdtemp(prefix="light-wt-selftest-")
    repo = os.path.join(d, "repo")
    os.makedirs(repo)
    run(["git", "init", "-q", "-b", "master", "."], cwd=repo)
    run(["git", "config", "user.email", "t@t"], cwd=repo)
    run(["git", "config", "user.name", "t"], cwd=repo)
    for sub, n in (("src/keep", 3), ("src/drop", 40)):
        p = os.path.join(repo, *sub.split("/"))
        os.makedirs(p)
        for i in range(n):
            with io.open(os.path.join(p, "f%d.txt" % i), "w", encoding="utf-8", newline="\n") as f:
                f.write(("X" * 400 + "\n") * 8)
    with io.open(os.path.join(repo, "README.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("# fixture\n")
    run(["git", "add", "-A"], cwd=repo)
    r = run(["git", "commit", "-qm", "base"], cwd=repo)
    if r.returncode != 0:
        raise RuntimeError("fixture commit 失败: %s" % (r.stderr or r.stdout))
    return d, repo


class Args(object):
    def __init__(self, **kw):
        for k in ("root", "cone", "base", "branch", "task", "repo", "force",
                  "keep_branch", "json", "ttl_min"):
            setattr(self, k, kw.get(k))
        if self.ttl_min is None:
            self.ttl_min = DEFAULT_TTL_MIN


def selftest():
    checks = []   # (族, 名称, 通过?, 说明)
    d, repo = fixture_repo()
    root = os.path.join(d, "wt")
    try:
        full = tree_bytes(repo)

        # A 族：创建语义
        rc = cmd_create(Args(repo=repo, root=root, task="t1", cone="src/keep"))
        p1 = os.path.join(root, "t1")
        checks.append(("A", "S1 create rc=0", rc == 0, "rc=%d" % rc))
        checks.append(("A", "S2 cone 命中面在场", os.path.isdir(os.path.join(p1, "src", "keep")), ""))
        checks.append(("A", "S3 cone 外目录被裁", not os.path.isdir(os.path.join(p1, "src", "drop")), ""))
        cut = tree_bytes(p1)
        checks.append(("A", "S4 磁盘显著低于全量", cut > 0 and cut * 3 < full,
                       "沙箱 %d B / 全量 %d B" % (cut, full)))

        # B 族：幂等
        wt0 = worktree_count(repo)
        rc = cmd_create(Args(repo=repo, root=root, task="t1", cone="src/keep"))
        checks.append(("B", "S5 二次 create 幂等 rc=0", rc == 0, "rc=%d" % rc))
        checks.append(("B", "S6 未开第二个 worktree", worktree_count(repo) == wt0,
                       "%d → %d" % (wt0, worktree_count(repo))))

        # C 族：回收纪律（脏/未并入/陌生目录一律拒绝）
        with io.open(os.path.join(p1, "src", "keep", "local-edit.txt"), "w",
                     encoding="utf-8", newline="\n") as f:
            f.write("uncommitted\n")
        rc = cmd_teardown(Args(repo=repo, root=root, task="t1", force=None))
        checks.append(("C", "S7 脏沙箱默认拒绝", rc == 1 and os.path.isdir(p1), "rc=%d" % rc))
        rc = cmd_teardown(Args(repo=repo, root=root, task="t1", force=True))
        checks.append(("C", "S8 --force 回收 rc=0", rc == 0 and not os.path.isdir(p1), "rc=%d" % rc))
        checks.append(("C", "S9 回收后再跑幂等", cmd_teardown(Args(repo=repo, root=root, task="t1")) == 0, ""))
        stranger = os.path.join(root, "ghost")
        os.makedirs(stranger)
        rc = cmd_create(Args(repo=repo, root=root, task="ghost", cone="src/keep"))
        checks.append(("C", "S10 陌生目录不接管", rc == 1 and os.path.isdir(stranger), "rc=%d" % rc))
        shutil.rmtree(stranger)

        # D 族：未并入的分支必须留着（删分支是不可逆动作）
        cmd_create(Args(repo=repo, root=root, task="t2", cone="src/keep"))
        p2 = os.path.join(root, "t2")
        with io.open(os.path.join(p2, "src", "keep", "work.txt"), "w",
                     encoding="utf-8", newline="\n") as f:
            f.write("real work\n")
        run(["git", "add", "-A"], cwd=p2)
        run(["git", "commit", "-qm", "branch-work"], cwd=p2)
        rc = cmd_teardown(Args(repo=repo, root=root, task="t2"))
        checks.append(("D", "S11 分支未并入默认拒绝", rc == 1, "rc=%d" % rc))
        rc = cmd_teardown(Args(repo=repo, root=root, task="t2", force=True))
        rb = run(["git", "rev-parse", "--verify", "refs/heads/lightwt/t2"], cwd=repo)
        checks.append(("D", "S12 --force 也只删工作树留分支", rc == 0 and rb.returncode == 0,
                       "rc=%d branch=%s" % (rc, "在场" if rb.returncode == 0 else "被删")))

        # E 族：状态机与自拒面（每条都要真造出那个状态，不靠分支名假装）
        def commit_in(sandbox, name):
            with io.open(os.path.join(sandbox, "src", "keep", name), "w",
                         encoding="utf-8", newline="\n") as f:
                f.write("work on %s\n" % name)
            run(["git", "add", "-A"], cwd=sandbox)
            run(["git", "commit", "-qm", name], cwd=sandbox)

        cmd_create(Args(repo=repo, root=root, task="t3", cone="src/keep", ttl_min=-1))
        commit_in(os.path.join(root, "t3"), "t3-work")   # 有提交 ⇒ 未并入，才谈得上过期
        st3, _ = classify(load_manifest(manifest_path(root, "t3")), repo)
        checks.append(("E", "S13 超 TTL 且未并入落 stale", st3 == "stale", st3))
        cmd_create(Args(repo=repo, root=root, task="t4", cone="src/keep"))
        commit_in(os.path.join(root, "t4"), "t4-work")
        mg = run(["git", "merge", "-q", "--no-edit", "lightwt/t4"], cwd=repo)
        st4, _ = classify(load_manifest(manifest_path(root, "t4")), repo)
        checks.append(("E", "S14 真并入 base 落 merged", mg.returncode == 0 and st4 == "merged",
                       "merge rc=%d / %s" % (mg.returncode, st4)))
        rc = cmd_status(Args(repo=repo, root=os.path.join(d, "nowhere")))
        checks.append(("E", "S15 判定面为空自拒", rc == 2, "rc=%d" % rc))
        rc = cmd_status(Args(repo=repo, root=root))
        checks.append(("E", "S16 status 有账即 rc=0", rc == 0, "rc=%d" % rc))

        # F 族：环境档与尺坏档（拿不到判据面时一律 2/4，绝不冒绿）
        rc = cmd_create(Args(repo=os.path.join(d, "not-a-repo"), root=root, task="t9"))
        checks.append(("F", "S17 非 git 仓 create rc=2", rc == 2, "rc=%d" % rc))
        rc = cmd_status(Args(repo=os.path.join(d, "not-a-repo"), root=root))
        checks.append(("F", "S18 非 git 仓 status rc=2（不再拿 cwd=\\. 兜底）", rc == 2, "rc=%d" % rc))
        try:
            worktree_count(os.path.join(d, "nope"))
            bad = False
        except Exception:
            bad = True
        checks.append(("F", "S19 git 坏 ⇒ 抛错由 main 收口成 rc=4", bad, ""))

        # G 族：--sparse 探针的两条轨（本机 Git for Windows 自报 2.51 却不认这面旗）
        saved = os.environ.get(NO_SPARSE_ENV)
        saved_probe = _SPARSE_OK
        try:
            os.environ[NO_SPARSE_ENV] = "1"
            globals()["_SPARSE_OK"] = None
            rc = cmd_create(Args(repo=repo, root=root, task="t5", cone="src/keep"))
            m5 = load_manifest(manifest_path(root, "t5")) or {}
            p5 = os.path.join(root, "t5")
            checks.append(("G", "S20 强制回退轨可用（plain 建 + cone 仍收窄）",
                           rc == 0 and m5.get("sparse_route") == "plain"
                           and os.path.isdir(os.path.join(p5, "src", "keep"))
                           and not os.path.isdir(os.path.join(p5, "src", "drop")),
                           "rc=%d route=%s" % (rc, m5.get("sparse_route"))))
        finally:
            if saved is None:
                os.environ.pop(NO_SPARSE_ENV, None)
            else:
                os.environ[NO_SPARSE_ENV] = saved
            globals()["_SPARSE_OK"] = saved_probe
        globals()["_SPARSE_OK"] = False   # 钉住回退轨，让「真错不回退」在每个平台都是同一发调用
        rc, err, route = worktree_add_sandbox(repo, os.path.join(root, "ghost-real"),
                                              "master", "master")
        globals()["_SPARSE_OK"] = saved_probe
        checks.append(("G", "S21 真错（分支已存在）不回退、不吞", rc != 0 and route == "plain"
                       and "already exists" in (err or ""),
                       "rc=%d route=%s err=%s" % (rc, route,
                                                  (err or "").strip().splitlines()[-1][:70])))
    finally:
        shutil.rmtree(d, ignore_errors=True)

    fail = [c for c in checks if not c[2]]
    fam = {}
    for f, _, _, _ in checks:
        fam[f] = fam.get(f, 0) + 1
    inv = " / ".join("%s×%d" % kv for kv in sorted(fam.items()))
    for name, ok, note in [(c[1], c[2], c[3]) for c in checks]:
        print("  %s %s%s" % ("OK " if ok else "BAD", name, (" — " + note) if note else ""))
    if fail:
        print("SELFTEST FAIL（%d/%d 格红）" % (len(fail), len(checks)))
        return 1
    print("SELFTEST OK %d 格（反解：%s）" % (len(checks), inv))
    return 0


def main():
    ap = argparse.ArgumentParser(description="light worktree 沙箱生命周期（create/teardown/status）")
    ap.add_argument("--selftest", action="store_true")
    sub = ap.add_subparsers(dest="cmd")
    for name in TOOLS:
        sp = sub.add_parser(name)
        sp.add_argument("--repo", required=True)
        if name != "status":
            sp.add_argument("--task", required=True)
        if name == "create":
            sp.add_argument("--cone", default="")
            sp.add_argument("--base", default="")
            sp.add_argument("--branch", default="")
            sp.add_argument("--ttl-min", type=int, default=DEFAULT_TTL_MIN)
        if name == "teardown":
            sp.add_argument("--force", action="store_true", default=None)
            sp.add_argument("--keep-branch", action="store_true", default=None)
        if name == "status":
            sp.add_argument("--json", action="store_true", default=None)
        sp.add_argument("--root", default="")
    args = ap.parse_args()

    if args.selftest:
        return selftest()
    if args.cmd == "create":
        return cmd_create(args)
    if args.cmd == "teardown":
        return cmd_teardown(args)
    if args.cmd == "status":
        return cmd_status(args)
    sys.stdout.write("USAGE 需要子命令之一：%s（或 --selftest）\n" % " / ".join(TOOLS))
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as e:
        sys.stdout.write("RULER-BROKEN: %r\n" % (e,))
        sys.exit(4)
