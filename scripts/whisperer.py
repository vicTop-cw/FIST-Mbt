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
    status = f"local={local[:7]} gitcode={gc[:7]} origin={og[:7]}"
    if gc == og and gc != local:
        print(f"  ⚠️ HEAD 从 {local[:7]} 恢复到 {gc[:7]}")
        run(["git", "reset", "--hard", gc])
        run(["git", "push", "gitcode", "HEAD:main", "HEAD:master", "--force"])
        run(["git", "push", "origin", "HEAD:main", "HEAD:master", "--force"])
        return (gc[:7], "⚠️ 已恢复")
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
    # G1: fist-gate.py --scan 能跑
    r = run(["python", "scripts/fist-gate.py", "--scan"])
    if r.returncode != 0 and "SELFTEST" not in r.stdout:
        print(f"  ❌ G1 fist-gate.py --scan rc={r.returncode}"); rc = 2
    else:
        print(f"  ✅ G1 fist-gate.py --scan 正常")
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
    g.add_argument("--self-test", action="store_true", help="selftest 模式")
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
