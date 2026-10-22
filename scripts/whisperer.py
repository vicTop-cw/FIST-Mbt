# -*- coding: utf-8 -*-
"""scripts/whisperer.py — 风语者（Whisperer）自动化巡检脚本。
把定时任务 prompt 里的 Step 0-4 装进一个 Python 文件。
用法:
  python scripts/whisperer.py --fast           # P0-1 新增：只跑 Step 0 HEAD 安全门（<3s）
  python scripts/whisperer.py --scan-only      # Step 0-2 + Step 3 扫描，不自动合入
  python scripts/whisperer.py --auto-merge    # Step 0-2 + 自动合入 MERGE-CODE 分支 + Step 3
  python scripts/whisperer.py --self-test      # selftest: 对干净树跑一遍，必须 0 异常
  python scripts/whisperer.py                  # 默认 --scan-only
退出码: 0=全绿 1=有失败 2=自身异常"""
import argparse, os, re, subprocess, sys
from datetime import datetime
from pathlib import Path

from moon_env_probe import moon_env
# 强制 stdout/stderr UTF-8（Windows GBK 终端会炸 emoji）
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
EXC = ("_build", "temp", ".git", "node_modules")

def run(cmd, cwd=None, capture=True):
    r = subprocess.run(cmd, cwd=cwd or ROOT, capture_output=capture, text=True, encoding="utf-8",
                       errors="replace", env=moon_env())
    return r

def sh(*args, cwd=None):
    return run(list(args), cwd=cwd).stdout.strip()

# ============================================================
# Step 0 — HEAD 安全门（拆分 fast + full）
# ============================================================
HEAD_STATE_FILE = ROOT / "memory" / "whisperer-head.txt"

def step0_head_safety(full=True):
    """HEAD 安全门。full=True 全量（fetch+reset 篡改），full=False fast 模式（<5s，含 fetch）"""
    # ========== 两个远程都 fetch ==========
    run(["git", "fetch", "gitcode", "main", "master"], capture=True)
    run(["git", "fetch", "origin", "main", "master"], capture=True)

    local = sh("git", "rev-parse", "HEAD")
    gc = sh("git", "rev-parse", "gitcode/main")
    og = sh("git", "rev-parse", "origin/main")

    # ========== 主仓定义 ==========
    # gitcode = 主仓（VictorTop/Fist-Mbt），origin = 镜像（vicTop-cw/FIST-Mbt）
    # 策略：origin 任何时候落后 gitcode → 自动同步（--force 安全：gitcode 不会落后）
    mirror_fixed = False
    mirror_reason = ""
    if gc != og:
        diff_ahead = sh("git", "rev-list", "--count", f"origin/main..gitcode/main").strip()
        diff_behind = sh("git", "rev-list", "--count", f"gitcode/main..origin/main").strip()
        diff_ahead = int(diff_ahead) if diff_ahead.isdigit() else 0
        diff_behind = int(diff_behind) if diff_behind.isdigit() else 0
        if diff_ahead > 0 or diff_behind > 0:
            print(f"  🔀 origin/main ({og[:7]}) ≠ gitcode/main ({gc[:7]}) — 镜像不同步！")
            print(f"     gitcode 领先 {diff_ahead} / 落后 {diff_behind}")
            run(["git", "push", "origin", f"{gc}:refs/heads/main", f"{gc}:refs/heads/master", "--force"])
            mirror_fixed = True
            mirror_reason = f"origin 镜像已同步 {og[:7]}→{gc[:7]} (+{diff_ahead}/-{diff_behind})"
            og = gc

    # 读上次 HEAD 状态（fast 模式用来检测"最近有没有被碰"）
    prev_hash = None
    prev_ts = None
    if HEAD_STATE_FILE.exists():
        try:
            prev_line = HEAD_STATE_FILE.read_text(encoding="utf-8").strip()
            prev_hash, prev_ts = prev_line.split("|", 1)
        except Exception:
            pass

    # 写入当前状态
    HEAD_STATE_FILE.parent.mkdir(exist_ok=True)
    HEAD_STATE_FILE.write_text(f"{local}|{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n", encoding="utf-8")

    tampered = False
    tamper_reason = ""
    if gc != og:
        tampered = True
        tamper_reason = f"两个远程 main 不一致（gitcode={gc[:7]} origin={og[:7]}）"
    elif gc != local:
        tampered = True
        tamper_reason = "本地 HEAD 与远端 main 不一致（篡改）"
    elif prev_hash and prev_hash != local and local != gc:
        tampered = True
        tamper_reason = f"HEAD 从 {prev_hash[:7]} 变到 {local[:7]}（非风语者触发）"

    if tampered and full:
        # 篡改事件记录 + 自动恢复
        log_path = ROOT / "memory" / "whisperer-tamper.log"
        tamper = sh("git", "log", "-1", "--oneline", local)
        author = sh("git", "log", "-1", "--format=%an <%ae>", local)
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_line = f"[{ts}] 本地 HEAD={local[:7]} 被篡改: {tamper} | {author} → 恢复到 {gc[:7]}\n"
        log_path.parent.mkdir(exist_ok=True)
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(log_line)
        print(f"  ⚠️ HEAD 被篡改！{tamper[:80]}")
        print(f"  → 恢复到 {gc[:7]}，篡改记录写入 memory/whisperer-tamper.log")
        run(["git", "reset", "--hard", gc])
        run(["git", "push", "gitcode", "HEAD:main", "HEAD:master", "--force"])
        run(["git", "push", "origin", "HEAD:main", "HEAD:master", "--force"])
        return (gc[:7], f"⚠️ HEAD被篡改已恢复 ({tamper[:40]})")
    elif tampered and not full:
        # fast 模式只告警，不恢复
        print(f"  ⚠️ {tamper_reason}")
        print(f"  → 跑 --scan-only 恢复，或手动 git reset --hard {gc[:7]}")
        return (local[:7], f"⚠️ HEAD 不一致: local={local[:7]} remote={gc[:7]}")

    if prev_hash and prev_hash == local and local == gc:
        # HEAD 稳定：计数
        stable_minutes = 0
        try:
            prev_dt = datetime.strptime(prev_ts, "%Y-%m-%d %H:%M:%S")
            stable_minutes = int((datetime.now() - prev_dt).total_seconds() / 60)
        except Exception:
            pass
        status = f"✅ 三端一致，稳定 {stable_minutes}min"
    else:
        status = "✅ 三端一致"
    if mirror_fixed:
        status += f"（{mirror_reason}）"
    return (local[:7], status)

# ============================================================
# Step 1 — 分支普查（调用 fist-gate.py --scan）
# ============================================================
def step1_branch_scan():
    print("[Step 1] fist-gate.py --scan")
    run(["git", "fetch", "--all", "--prune"])
    r = run(["python", "scripts/fist-gate.py", "--scan"])
    if r.returncode != 0 and "SELFTEST" not in r.stdout:
        print(f"  fist-gate.py 失败: {r.stderr[:200]}")
        return (0, 0, [])
    lines = r.stdout.splitlines()
    mc = sum(1 for l in lines if "MERGE-CODE" in l)
    ab = sum(1 for l in lines if "ABORT" in l)
    drops = sum(1 for l in lines if "DROP" in l)
    merge_candidates = []
    for l in lines:
        if "MERGE-CODE" in l:
            m = re.match(r"\s*(\S+)\s+ahead=(\d+)\s+cherry\+=(\d+).*src±=(\d+).*markers=(\d+)", l)
            if m:
                merge_candidates.append({
                    "ref": m.group(1), "ahead": int(m.group(2)),
                    "cherry": int(m.group(3)), "src_lines": int(m.group(4)),
                    "markers": int(m.group(5))})
    print(f"  MERGE-CODE={mc}, ABORT={ab}, DROP={drops}")
    return (mc, ab, merge_candidates)

def auto_merge(candidates):
    """对 MERGE-CODE 分支做**三方 cherry-pick**（R43 起，取代整文件覆盖）。

    为什么改（2026-10-22 实测取证）：旧实现用 `git checkout <ref> -- <file>` 把分支上的
    **整份文件**搬到 HEAD。分支若落后于 master，这会把 master 上更新的行**原样删回去**——
    实测 `slave/fix/dist-snapshot-guard` 的 `scripts/README.md` 会删掉 master 的
    「### 2026-10-22 登记：whisperer.py」整段（-37/+5 的形状），`pre-commit-marker-gate` 同族。
    这正是 TASK-004「REVERT-PATTERN」在**自动合并器自己身上**的实例：覆盖式合并会把
    "合并"做成"回退"。改成 cherry-pick 独有提交后，改动以三方合并落盘，master 的新内容不会被抹掉。

    纪律不变（只增不减）：
      - 工作树必须干净，否则不动手（宁可不合，不可猜）；
      - 分支自带冲突标记（markers>0）→ 跳过；
      - pick 冲突时：**memory/reports/plugins/docs 取 theirs**（append-only 面，取远端更安全），
        其余冲突 → `cherry-pick --abort` + `reset --hard`，整支跳过留人工（不硬塞、不覆盖）；
      - markers 判据 + `moon build` 两道门，任一不过 → `reset --hard` 回滚本支。
    """
    print("[Step 1b] 自动合入 MERGE-CODE 分支（三方 cherry-pick）")
    import shutil

    merged = 0
    for c in candidates:
        ref = c["ref"]
        if c["markers"] > 0:
            print(f"  ⚠ 跳过 {ref}：自带未解决冲突标记")
            continue
        if sh("git", "status", "--porcelain").strip():
            print("  ⚠ 工作树不干净（有未提交改动）→ 本轮不合入，避免把别人的改动卷进来")
            break
        unique = [h for h in sh("git", "rev-list", "--reverse", f"HEAD..{ref}").split() if h]
        if not unique:
            print(f"  = 跳过 {ref}：无独有提交（内容已在 HEAD 里）")
            continue
        print(f"  🟢 {ref} cherry+={c['cherry']} src±={c['src_lines']}（{len(unique)} 个提交）")
        picked, failed = 0, False
        for h in unique:
            msg = sh("git", "log", "-1", "--format=%s", h).strip()
            r = run(["git", "cherry-pick", h])
            if r.returncode != 0:
                conf = sh("git", "diff", "--name-only", "--diff-filter=U").split()
                soft = [f for f in conf if f.startswith(("memory/", "reports/", "plugins/", "docs/"))]
                hard = [f for f in conf if f not in soft]
                if soft and not hard:
                    for f in soft:
                        run(["git", "checkout", "--theirs", f])
                        print(f"      theirs: {f}")
                    run(["git", "add", "-A"])
                    r2 = subprocess.run(["git", "-c", "core.editor=true", "cherry-pick", "--continue"],
                                        cwd=ROOT, capture_output=True, text=True)
                    if r2.returncode == 0:
                        picked += 1
                        continue
                run(["git", "cherry-pick", "--abort"])
                run(["git", "reset", "--hard", "HEAD"])
                print(f"    ❌ 冲突于 {h[:7]}（{msg[:40]}；硬冲突: {', '.join(hard) or '-'}）→ 整支跳过，留人工")
                failed = True
                break
            picked += 1
        if failed:
            continue
        # 门①：仓库内冲突标记判据（live）
        mc = run(["python", "scripts/blackbox/check_merge_markers.py"])
        if mc.returncode != 0:
            run(["git", "reset", "--hard", f"HEAD~{picked}"])
            print("    ❌ markers 红 → 回滚本支")
            continue
        # 门②：构建
        shutil.rmtree("_build", ignore_errors=True)
        b = run(["moon", "build", "--target", "js", "src/server", "src/engine",
                 "src/store", "src/router", "src/ops"])
        if b.stdout.count("Error:") > 0:
            run(["git", "reset", "--hard", f"HEAD~{picked}"])
            print("    ❌ build 有 Error → 回滚本支")
            continue
        run(["git", "push", "gitcode", "HEAD:main", "HEAD:master"])
        run(["git", "push", "origin", "HEAD:main", "HEAD:master"])
        merged += 1
        print(f"    ✅ 合入 {picked} 个提交")
    print(f"  合计: {merged} 个分支合入")
    return merged

# ============================================================
# Step 2 — Agent 认领检测
# ============================================================
def step2_agent_claim():
    print("[Step 2] Agent 认领检测")
    yamls = list((ROOT / "docs" / "tasks" / "backlog").glob("*.yaml"))
    claimed = 0
    for y in yamls:
        content = y.read_text(encoding="utf-8")
        if not re.search(r"status:\s*backlog", content):
            claimed += 1
    slaves = sh("git", "branch", "-r").splitlines()
    slaves = [s.strip() for s in slaves if "gitcode/slave/" in s]
    has_tasks = sum(1 for s in slaves
                    if subprocess.run(["git", "ls-tree", "-r", s, "--name-only"],
                                       capture_output=True, text=True).stdout.find("docs/tasks/") >= 0)
    print(f"  docs/tasks: {claimed}/{len(yamls)} 认领")
    print(f"  slave/* 有 docs/tasks/: {has_tasks}/{len(slaves)}")
    return claimed, len(yamls)

# ============================================================
# Step 3 — 问题扫描 → 自动写 TASK yaml
# ============================================================
def step3_issue_scan():
    print("[Step 3] 问题扫描")
    issues = []
    # 3a: scripts/whisperer.py 存在吗？（TASK-009 自己的 scope）
    if not (ROOT / "scripts" / "whisperer.py").exists():
        issues.append(("scripts/whisperer.py 不存在（TASK-009 scope）", "P2"))
    # 3b: .mooncakes 里还有 moon.mod.json 吗？（依赖格式迁移）
    mc_old = list((ROOT / ".mooncakes").rglob("moon.mod.json"))
    if mc_old:
        issues.append((f".mooncakes 里还有 {len(mc_old)} 个 moon.mod.json（新 clone 机器 moon build 会崩）", "P1"))
    # 3c: whisperer.py 自己有没有 TODO/FIXME？
    wp = ROOT / "scripts" / "whisperer.py"
    if wp.exists():
        todos = wp.read_text(encoding="utf-8").count("TODO") + wp.read_text(encoding="utf-8").count("FIXME")
        if todos > 0:
            issues.append((f"whisperer.py 有 {todos} 个 TODO/FIXME", "P3"))
    for desc, pri in issues:
        print(f"  🟡 {pri}: {desc}")
    return issues

# ============================================================
# selftest
# ============================================================
def selftest():
    print("[self-test] 风语者自检")
    rc = 0
    # G1: fist-gate.py --scan 能跑。
    # 三点是实测补的（2026-10-22）：
    #   (a) 必须 cwd=ROOT —— 否则在任何别的目录里跑自检都会「找不到 scripts/fist-gate.py」，
    #       看起来像判据坏了；
    #   (b) 红要自己说清原因：只印 rc=N 等于把「我没量到」和「下游坏了」混成一个红，
    #       人得自己去猜（本项目「红着没人读」的起点就是这个）。这里印末行 + 提示；
    #   (c) rc=2 是 DEGRADED（下游判据拒绝出数），既不是绿也不是"代码坏了"，单列一档。
    r = run(["python", "scripts/fist-gate.py", "--scan"], cwd=ROOT)
    tail = ([l for l in ((r.stdout or "") + (r.stderr or "")).splitlines() if l.strip()] or ["(无输出)"])[-1].strip()
    if r.returncode == 0:
        print("  ✅ G1 fist-gate.py --scan 正常")
    elif r.returncode == 2:
        print(f"  ⚠ G1 fist-gate.py --scan DEGRADED rc=2：{tail[:120]}")
        print("      （下游判据自己拒绝出数，不是本脚本坏了；先修下游再复检）")
    else:
        print(f"  ❌ G1 fist-gate.py --scan rc={r.returncode}：{tail[:160]}")
        if "FileNotFoundError" in tail or "No such file" in tail:
            print("      提示：常见根因在 **git worktree** 里 `.git` 是文件而非目录；"
                  "scan 已改用 `git rev-parse --absolute-git-dir`，若仍红请看上面的 traceback")
        rc = 2
    # G2: HEAD 安全门逻辑 import 不崩
    try:
        from whisperer import step0_head_safety, step1_branch_scan, step2_agent_claim, step3_issue_scan
        print(f"  ✅ G2 import 不崩")
    except Exception as e:
        print(f"  ❌ G2 import 崩: {e}"); rc = 2
    # G3: auto_merge 不许再用"整文件覆盖"（R43）。这不是风格洁癖——
    # 覆盖式合并实测会把 master 更新的行删回去（scripts/README.md 一次 -37/+5），
    # 即"合并"做成"回退"。用源码自省钉住：把 checkout <ref> -- <file> 改回来这里必红。
    import inspect
    src = inspect.getsource(auto_merge)
    if '"checkout", ref, "--"' in src or "'checkout', ref, '--'" in src:
        print("  ❌ G3 auto_merge 仍含整文件覆盖（git checkout <ref> -- <file>）——会回退 master 内容")
        rc = 2
    elif "cherry-pick" not in src:
        print("  ❌ G3 auto_merge 里找不到 cherry-pick（判据失去锚点，无法自证）")
        rc = 2
    else:
        print("  ✅ G3 auto_merge 用三方 cherry-pick，无整文件覆盖")
    # G4: 行为级自证 —— 在临时仓库里把"整文件覆盖"与"cherry-pick"各跑一遍：
    #     覆盖会丢掉 master 后加的行（这就是它把"合并"做成"回退"的机理），cherry-pick 不会。
    import tempfile
    import shutil as _shutil
    d = tempfile.mkdtemp(prefix="whisperer-g4-")

    def g(*a):
        return subprocess.run(["git"] + list(a), cwd=d, capture_output=True, text=True,
                              encoding="utf-8", errors="replace")

    try:
        g("init", "-q", "-b", "master", ".")
        g("config", "user.email", "t@t")
        g("config", "user.name", "t")
        io = __import__("io")
        io.open(os.path.join(d, "README.md"), "w", encoding="utf-8").write("A\n")
        g("add", "-A"); g("commit", "-qm", "base")
        # 分支：在 base 上加 C
        g("checkout", "-q", "-b", "slave")
        io.open(os.path.join(d, "README.md"), "w", encoding="utf-8").write("A\nC\n")
        g("commit", "-qam", "branch-C")
        # master：在 base 上加 B（模拟 master 前进）
        g("checkout", "-q", "master")
        io.open(os.path.join(d, "README.md"), "w", encoding="utf-8").write("A\nB\n")
        g("commit", "-qam", "master-B")
        # (1) 旧行为：整文件覆盖
        g("checkout", "slave", "--", "README.md")
        overlay = io.open(os.path.join(d, "README.md"), encoding="utf-8").read()
        g("checkout", "HEAD", "--", "README.md")
        # (2) 新行为：cherry-pick 分支独有提交
        head = g("rev-parse", "HEAD").stdout.strip()
        g("cherry-pick", "--no-commit", "slave")
        g("commit", "-qm", "pick-C")
        picked = io.open(os.path.join(d, "README.md"), encoding="utf-8").read()
        if "B\n" in overlay:
            print("  ❌ G4 夹具失效：整文件覆盖竟然保留了 master 的 B 行（判据无法自证）")
            rc = 2
        elif "B\n" not in picked or "C\n" not in picked:
            print(f"  ❌ G4 cherry-pick 未同时保留 B 与 C：{picked!r}")
            rc = 2
        else:
            print("  ✅ G4 覆盖式合并丢 master 行（已证缺陷真实）/ cherry-pick 同时保留 B+C")
    except Exception as e:
        print(f"  ❌ G4 执行异常: {e}")
        rc = 2
    finally:
        _shutil.rmtree(d, ignore_errors=True)
    return rc

# ============================================================
# main
# ============================================================
def main():
    ap = argparse.ArgumentParser(description="风语者自动化巡检")
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--fast", action="store_true", help="P0-1: 只跑 Step 0 HEAD 安全门，<3s")
    g.add_argument("--scan-only", action="store_true", help="Step 0-2 + Step 3 扫描（默认）")
    g.add_argument("--auto-merge", action="store_true", help="Step 0-2 + 自动合入 + Step 3")
    # 全仓惯例是 `--selftest`（无连字符），本工具原先只认 `--self-test` ⇒ 统一跑 `--selftest` 的
    # 自动化会在它身上拿到 argparse rc=2，被误读成"判据坏了"。两个都收，输出一致。
    g.add_argument("--self-test", "--selftest", dest="self_test", action="store_true", help="selftest 模式")
    args = ap.parse_args()

    if args.self_test:
        sys.exit(selftest())

    if args.fast:
        # ==================== FAST MODE ====================
        print(f"⚡ {datetime.now().strftime('%H:%M:%S')} 风语者 fast HEAD 巡检 (<3s)")
        try:
            head, head_status = step0_head_safety(full=False)
        except Exception as e:
            print(f"FATAL: {e}")
            sys.exit(2)
        print(f"HEAD: {head} | {head_status}")
        print(f"下次 1min（fast）/ 15min（full）")
        # 退出码：不一致=1，一致=0
        sys.exit(1 if "⚠️" in head_status else 0)

    # ==================== FULL MODE ====================
    print(f"🔍 {datetime.now().strftime('%H:%M:%S')} 风语者巡检")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    try:
        head, head_status = step0_head_safety(full=True)
        mc, ab, candidates = step1_branch_scan()
        if args.auto_merge and candidates:
            auto_merge(candidates)
        step2_agent_claim()
        step3_issue_scan()
    except Exception as e:
        print(f"FATAL: {e}")
        sys.exit(2)
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print(f"HEAD: {head} | 下次 15min")
    sys.exit(0)

if __name__ == "__main__":
    main()
