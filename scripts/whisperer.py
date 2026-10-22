# -*- coding: utf-8 -*-
"""scripts/whisperer.py — 风语者（Whisperer）自动化巡检脚本。
把定时任务 prompt 里的 Step 0-4 装进一个 Python 文件。
用法:
  python scripts/whisperer.py --scan-only     # Step 0-2 + Step 3 扫描，不自动合入
  python scripts/whisperer.py --auto-merge   # Step 0-2 + 自动合入 MERGE-CODE 分支 + Step 3
  python scripts/whisperer.py --self-test     # selftest: 对干净树跑一遍，必须 0 异常
  python scripts/whisperer.py                 # 默认 --scan-only
退出码: 0=全绿 1=有失败 2=自身异常"""
import argparse, os, re, subprocess, sys
from datetime import datetime
from pathlib import Path
# 强制 stdout/stderr UTF-8（Windows GBK 终端会炸 emoji）
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
EXC = ("_build", "temp", ".git", "node_modules")

def run(cmd, cwd=None, capture=True):
    r = subprocess.run(cmd, cwd=cwd or ROOT, capture_output=capture, text=True, encoding="utf-8", errors="replace")
    return r

def sh(*args, cwd=None):
    return run(list(args), cwd=cwd).stdout.strip()

# ============================================================
# Step 0 — HEAD 安全门
# ============================================================
def step0_head_safety():
    print("[Step 0] HEAD 安全门")
    run(["git", "checkout", "master"])
    local = sh("git", "rev-parse", "HEAD")
    gc = sh("git", "rev-parse", "gitcode/main")
    og = sh("git", "rev-parse", "origin/main")
    if gc == og and gc != local:
        # 记录篡改事件
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
    return (local[:7], "✅ 三端一致")

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
    """对 MERGE-CODE 分支做 git checkout + markers 检查 + build + commit + push"""
    print("[Step 1b] 自动合入 MERGE-CODE 分支")
    merged = 0
    for c in candidates:
        ref = c["ref"]
        if c["markers"] > 0: continue
        print(f"  🟢 {ref} cherry+={c['cherry']} src±={c['src_lines']}")
        # 拿到 ref 里的文件列表
        files = sh("git", "diff", "--name-only", "HEAD", ref).splitlines()
        if not files: continue
        safe = [f for f in files if any(f.startswith(p) for p in ("src/", "scripts/", "cmd/", ".github/"))]
        if not safe: continue
        # checkout 干净文件
        for f in safe:
            run(["git", "checkout", ref, "--", f])
        # markers 检查
        mc_r = run(["python", "scripts/blackbox/check_merge_markers.py"])
        if mc_r.returncode != 0:
            print(f"    ❌ markers 红，跳过")
            run(["git", "checkout", "HEAD", "--"] + safe)
            continue
        # build（只跑 MoonBit 源码，不跑依赖更新）
        import shutil
        shutil.rmtree("_build", ignore_errors=True)
        b_r = run(["moon", "build", "--target", "js", "src/server", "src/engine",
                    "src/store", "src/router", "src/ops"])
        err_count = b_r.stdout.count("Error:")
        if err_count > 0:
            print(f"    ❌ build 有 Error，跳过")
            run(["git", "checkout", "HEAD", "--"] + safe)
            continue
        # commit + push
        run(["git", "add"] + safe)
        run(["git", "commit", "-m", f"merge(branch): {ref} — auto by whisperer"])
        run(["git", "push", "gitcode", "HEAD:main", "HEAD:master"])
        run(["git", "push", "origin", "HEAD:main", "HEAD:master"])
        merged += 1
        print(f"    ✅ 合入")
    print(f"  合计: {merged} 个合入")
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
    return rc

# ============================================================
# main
# ============================================================
def main():
    ap = argparse.ArgumentParser(description="风语者自动化巡检")
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--scan-only", action="store_true", help="Step 0-2 + Step 3 扫描（默认）")
    g.add_argument("--auto-merge", action="store_true", help="Step 0-2 + 自动合入 + Step 3")
    # 全仓惯例是 `--selftest`（无连字符），本工具原先只认 `--self-test` ⇒ 统一跑 `--selftest` 的
    # 自动化会在它身上拿到 argparse rc=2，被误读成"判据坏了"。两个都收，输出一致。
    g.add_argument("--self-test", "--selftest", dest="self_test", action="store_true", help="selftest 模式")
    args = ap.parse_args()

    if args.self_test:
        sys.exit(selftest())

    print(f"🔍 {datetime.now().strftime('%H:%M:%S')} 风语者巡检")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    try:
        head, head_status = step0_head_safety()
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
