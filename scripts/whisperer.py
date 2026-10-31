# -*- coding: utf-8 -*-
"""scripts/whisperer.py — 风语者（Whisperer）自动化巡检脚本。
把定时任务 prompt 里的 Step 0-4 装进一个 Python 文件。
用法:
  python scripts/whisperer.py --fast           # P0-1 新增：只跑 Step 0 HEAD 状态门（<3s）
  python scripts/whisperer.py --scan-only      # Step 0-2 + Step 3 扫描，不自动合入
  python scripts/whisperer.py --auto-merge     # Step 0-2 + 自动合入 MERGE-CODE 分支 + Step 3
  python scripts/whisperer.py --self-test      # selftest: 对干净树跑一遍，必须 0 异常
  python scripts/whisperer.py                  # 默认 --scan-only
  python scripts/whisperer.py --sync-mirror    # 附加旗标：巡检时显式把 origin 镜像强推到 gitcode 现值
Step 0 的边界（R120 收口，别把它读回旧口径）：
  落后 / 领先主仓线都是**常态**（本仓整条 slave 工作流活在 feature 分支上），只有
  「互不为祖先的真分叉」与「祖先关系量不到」才是异常。本门**只读数、只出方案**：
  不 checkout、不 reset、不 push 共享线——旧版把 `local != 远端 main` 一律判成篡改，
  并在默认模式里真的 `git reset --hard` + `git push --force HEAD:main HEAD:master`（两远端），
  等于每 15 分钟替所有在feature 分支上工作的人做一次不可逆裁决。
退出码: 0=正常（含 behind/ahead） 1=真分叉或量不到（需人工） 2=脚本自身异常"""
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

# R125 纪律：spawn `moon` 的常驻入口必须带 MOONC_OVERRIDE——干净 PATH + 冷 _build 时
# moonc 会撞 `Sys_error("\\\\?: Invalid argument")` 路径 ICE（工具链缺陷，见 BUG-380 同族），
# 不接线就会把工具链故障记成「分支构建失败」。本脚本的 auto_merge 门② 会真跑 moon build。
from moon_env_probe import moon_env
from git_env import isolated_git_env

def run(cmd, cwd=None, capture=True, env=None):
    r = subprocess.run(cmd, cwd=cwd or ROOT, capture_output=capture, text=True, encoding="utf-8", errors="replace", env=env)
    return r

def sh(*args, cwd=None):
    return run(list(args), cwd=cwd).stdout.strip()

# ============================================================
# Step 0 — HEAD 状态门（R120：落后 ≠ 篡改；本门只读数、只出方案，永不动手）
# ============================================================
# R118：状态件落 **gitignored `temp/`**（本仓明文惯例「临时件放 temp/」）。
# 原来落 `memory/`（曾是跟踪件，每跑一次就 dirty 一个文件；R111 已移出跟踪面）。
HEAD_STATE_FILE = ROOT / "temp" / "whisperer-head.txt"

def _is_ancestor(a, b):
    """a 是 b 的祖先 → True；确认不是 → False；git 答不了 → None。

    「量不到」绝不能折成 False：浅克隆 / 缺 ref 时 git 也回非 0，折成 False 就把
    工具链问题读成「本地被篡改」——那正是 R120 之前这道门开火的形状。
    """
    r = run(["git", "merge-base", "--is-ancestor", a, b])
    if r.returncode == 0:
        return True
    if r.returncode == 1:
        return False
    return None

def _rev_count(spec):
    """rev-list --count；非数字（缺 ref / 浅克隆）回 None，不冒充 0。"""
    out = sh("git", "rev-list", "--count", spec)
    return int(out) if out.strip().isdigit() else None

def classify_head_state(local, gc, anc_local_gc, anc_gc_local):
    """纯函数：只吃已解析的事实，不调 git、不决定任何修复动作。

    state ∈ same / behind / ahead / diverged / unknown。
    R120 的立论：feature 分支上 `local != gc` 是**常态**（本仓整条 slave 工作流就活在
    feature 分支上），旧判据把它一律读成「篡改」，于是巡检拍每 15 分钟就往共享线上打
    一次 `git reset --hard` + 两记 `push --force HEAD:main HEAD:master`。
    """
    if not local or not gc:
        return ("unknown", "本地或远端 ref 解析为空，关系无从判定")
    if local == gc:
        return ("same", "本地 HEAD 与主仓线同一提交")
    if anc_local_gc is None or anc_gc_local is None:
        return ("unknown", "git 未能回答祖先关系（浅克隆 / 缺 ref / 工具链）——按「没量到」处置，不出修复动作")
    if anc_local_gc:
        return ("behind", "本地落后主仓线：主线前进了，本地工作没被改")
    if anc_gc_local:
        return ("ahead", "本地领先主仓线：含未合入提交，feature 分支的常态")
    return ("diverged", "本地与主仓线互不为祖先：真分叉，需人工裁决")

def head_plan_text(state, gc, branch):
    # R86：原第 2 形参 local 零引用（新判据抓到）⇒ 去掉。
    """只出方案（执行权在人）：把「真要动，动的是什么」写清楚，本函数不执行任何东西。"""
    if state == "behind":
        return ("  → 常规处置：git merge " + gc[:7] + "（或 rebase）。当前分支 "
                + (branch or "(detached)") + " 未受影响，本门不会替你动")
    if state == "ahead":
        return ("  → 常规处置：交付面未闭合，push 本分支后由 owner 开 MR；主仓线 " + gc[:7] + " 不受影响")
    if state == "diverged":
        return ("  → 方案（执行权在人）：先 `git log --oneline " + gc[:7] + "..HEAD` 与 `HEAD.." + gc[:7]
                + "` 看清两侧，再决定 rebase/merge；确需回稳的 `git reset --hard` 属不可逆动作，本门拒绝代跑")
    if state == "unknown":
        return "  → 先修工具链 / 补 fetch：祖先关系量不到时，任何修复动作都是盲动"
    return "  → 无需处置"

def step0_head_safety(full=True, sync_mirror=False, state_file=None, log_file=None):
    # R111：`state_file` / `log_file` 可注入 —— 自检原先靠 monkey-patch `globals()` 把
    # ROOT/HEAD_STATE_FILE 指到 tempdir（见自检里那段注释自己记的事故：patch 打到了
    # 另一个模块对象 ⇒ 拿着夹具跑了真仓，还试过对 origin 的 强制推送）。
    # 显式参数比改 globals 可靠，且静态判据（check_selftest_hermetic）能看见路径来自入参。
    state_file = state_file or HEAD_STATE_FILE
    log_file = log_file or (ROOT / "temp" / "whisperer-tamper.log")   # R118：temp/ 同上
    """HEAD 状态门。**只读数、只出方案：不 checkout、不 reset、不 push**（金条四）。

    full=True 为巡检拍，full=False 为 fast（同一判据、更少输出）。
    返回 (head7, status)；status 以 "⚠️" 开头只剩两档：真分叉 / 量不到。
    """
    # ========== 两个远程都 fetch（只读） ==========
    run(["git", "fetch", "gitcode", "main", "master"], capture=True)
    run(["git", "fetch", "origin", "main", "master"], capture=True)

    local = sh("git", "rev-parse", "HEAD")
    gc = sh("git", "rev-parse", "gitcode/main")
    og = sh("git", "rev-parse", "origin/main")
    branch = sh("git", "branch", "--show-current")

    # ========== 主仓定义 ==========
    # gitcode = 主仓（VictorTop/Fist-Mbt），origin = 镜像（vicTop-cw/FIST-Mbt）
    # R120：镜像同步从「默认自动强推」降为「默认只报，显式 --sync-mirror 才动」——
    # 强推共享线是不可逆动作，不该是巡检拍的缺省副作用（owner 口径：GitHub 那边不用管）。
    mirror_note = ""
    if gc and og and gc != og:
        diff_ahead = _rev_count("origin/main..gitcode/main")
        diff_behind = _rev_count("gitcode/main..origin/main")
        print("  🔀 origin/main (%s) ≠ gitcode/main (%s) — 镜像不同步（gitcode 领先 %s / 落后 %s）" % (
            og[:7], gc[:7],
            diff_ahead if diff_ahead is not None else "?",
            diff_behind if diff_behind is not None else "?"))
        if sync_mirror:
            r = run(["git", "push", "origin", "%s:refs/heads/main" % gc, "%s:refs/heads/master" % gc, "--force"])
            ok = r.returncode == 0
            mirror_note = ("镜像已同步 %s→%s" % (og[:7], gc[:7])) if ok else ("镜像同步失败 rc=%s" % r.returncode)
            print("  %s --sync-mirror：origin 指向 %s（%s）" % ("✅" if ok else "❌", gc[:7], mirror_note))
        else:
            mirror_note = "镜像未同步（%s≠%s，需要时加 --sync-mirror）" % (og[:7], gc[:7])
            print("  → 未动镜像：本门默认不强推共享线")

    # 读上次 HEAD 状态（只用来给读数加「动了多久 / 动过没有」的上下文）
    prev_hash = None
    prev_ts = None
    if state_file.exists():
        try:
            prev_line = state_file.read_text(encoding="utf-8").strip()
            prev_hash, prev_ts = prev_line.split("|", 1)
        except Exception:
            pass

    # 写入当前状态
    state_file.parent.mkdir(exist_ok=True)
    state_file.write_text(f"{local}|{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n", encoding="utf-8")

    state, why = classify_head_state(local, gc, _is_ancestor(local, gc), _is_ancestor(gc, local))
    # HEAD 自上次巡检的移动：在 feature 分支上是日常工作，只有真分叉时才是可疑证据
    moved = ""
    if prev_hash and prev_hash != local:
        moved = "（HEAD 自上次巡检 %s → %s）" % (prev_hash[:7], local[:7])

    if state in ("diverged", "unknown"):
        if state == "diverged":
            log_path = log_file
            tamper = sh("git", "log", "-1", "--oneline", local)
            author = sh("git", "log", "-1", "--format=%an <%ae>", local)
            ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            log_path.parent.mkdir(exist_ok=True)
            with open(log_path, "a", encoding="utf-8") as f:
                f.write("[%s] 分叉 本地 HEAD=%s%s: %s | %s 主仓线=%s（只记录不动手，R120）\n" % (
                    ts, local[:7], moved, tamper, author, gc[:7]))
            print("  ⚠️ HEAD 与主仓线分叉！%s%s" % (tamper[:80], moved))
        else:
            print("  ⚠️ HEAD 状态量不到：%s%s" % (why, moved))
        # R87：docstring 承诺 `full=False 为 fast（更少输出）`，但**实现从未用 full** ⇒
        # 两种模式输出完全一样（「文档承诺 ≠ 实现」，新判据 check_dead_params_py 抓到）。
        # 现按承诺实现：fast 模式省掉最冗长的 plan 文本，但**省略必须可见**（SKIP 纪律：
        # 不说明的省略在汇总里跟「没问题」长得一样）。判据面（⚠️ 两档）不受 full 影响。
        if full:
            print(head_plan_text(state, gc, branch))
        else:
            print("  （fast 模式：省略 plan 文本；要看请用 --full）")
        label = "真分叉" if state == "diverged" else "量不到"
        return (local[:7], "⚠️ %s：local=%s remote=%s（%s）" % (label, local[:7], gc[:7], why))

    # same / behind / ahead 都是正常态，不是警报
    if state == "same":
        stable_minutes = 0
        try:
            prev_dt = datetime.strptime(prev_ts, "%Y-%m-%d %H:%M:%S")
            stable_minutes = int((datetime.now() - prev_dt).total_seconds() / 60)
        except Exception:
            pass
        extra = "，稳定 %dmin" % stable_minutes if prev_hash == local else ""
        status = "✅ 与主仓线一致%s" % extra
    else:
        status = "✅ %s%s" % (why, moved)
    if mirror_note:
        status += "（%s）" % mirror_note
    return (local[:7], status)

# ============================================================
# Step 1 — 分支普查（调用 fist_gate.py --scan）
# ============================================================
def step1_branch_scan():
    print("[Step 1] fist_gate.py --scan")
    run(["git", "fetch", "--all", "--prune"])
    r = run(["python", "scripts/fist_gate.py", "--scan"])
    if r.returncode != 0 and "SELFTEST" not in r.stdout:
        print(f"  fist_gate.py 失败: {r.stderr[:200]}")
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
                 "src/store", "src/router", "src/ops"], env=moon_env())
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
    # G1: fist_gate.py --scan 能跑。
    # 三点是实测补的（2026-10-22）：
    #   (a) 必须 cwd=ROOT —— 否则在任何别的目录里跑自检都会「找不到 scripts/fist_gate.py」，
    #       看起来像判据坏了；
    #   (b) 红要自己说清原因：只印 rc=N 等于把「我没量到」和「下游坏了」混成一个红，
    #       人得自己去猜（本项目「红着没人读」的起点就是这个）。这里印末行 + 提示；
    #   (c) rc=2 是 DEGRADED（下游判据拒绝出数），既不是绿也不是"代码坏了"，单列一档。
    r = run(["python", "scripts/fist_gate.py", "--scan"], cwd=ROOT)
    tail = ([l for l in ((r.stdout or "") + (r.stderr or "")).splitlines() if l.strip()] or ["(无输出)"])[-1].strip()
    if r.returncode == 0:
        print("  ✅ G1 fist_gate.py --scan 正常")
    elif r.returncode == 2:
        print(f"  ⚠ G1 fist_gate.py --scan DEGRADED rc=2：{tail[:120]}")
        print("      （下游判据自己拒绝出数，不是本脚本坏了；先修下游再复检）")
    else:
        print(f"  ❌ G1 fist_gate.py --scan rc={r.returncode}：{tail[:160]}")
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
    # ---- H 族（R120）：Step 0 的状态判定与「绝不动手」—— 全部在临时仓库里跑，不碰本仓、不碰网络 ----
    # 立论：旧版 Step 0 把 `local != 远端 main` 一律判成「篡改」，并在**默认模式**里真的
    # `git reset --hard` + `git push 强制旗标 HEAD:main HEAD:master`（两远端）。
    # 本仓整条 slave 工作流活在 feature 分支上 ⇒ 每一次巡检拍都是一次不可逆裁决。
    # 这几格钉的是「落后/领先不再报警」+「任何写动作都不发出」。
    import tempfile as _tf
    import shutil as _sh
    import pathlib as _pl

    hd = _tf.mkdtemp(prefix="whisperer-h-")
    calls = []
    wt = os.path.join(hd, "wt")

    def _git_at(cwd, *a):
        return subprocess.run(["git"] + list(a), cwd=cwd, capture_output=True,
                              text=True, encoding="utf-8", errors="replace")

    def _stub_run(cmd, cwd=None, capture=True):
        """记录每一条 argv，然后**只在临时工作树里**真跑（fetch 走本地裸库，不发网络）。

        签名与被替换的 run() 对齐：cmd 是**已含 "git" 的完整 argv**，这里不许再补一遍
        （补了每条命令都变成 `git git …`，夹具会静默读空、把「量不到」当成正常态）。
        """
        calls.append(list(cmd))
        return subprocess.run(cmd, cwd=wt, capture_output=True, text=True,
                              encoding="utf-8", errors="replace")

    def _reset_calls_since():
        return [c for c in calls if "reset" in c or "checkout" in c or "push" in c]

    def _step(full=True, sync_mirror=False):
        # patch 必须打在**被测函数自己的 globals** 上。G2 那行 `from whisperer import
        # step0_head_safety` 会 import 出第二个模块对象，函数真身活在 whisperer.* 而不是
        # __main__.* —— 早先版本 patch globals() 打的是错的那一份，自检于是拿着夹具的名义
        # 去跑真仓（含一次对 origin 的 强制推送尝试），读数全是真仓的、且随时可能动手。
        g = step0_head_safety.__globals__
        saved = (g["run"], g["ROOT"])
        g["run"] = _stub_run
        g["ROOT"] = _pl.Path(wt)
        try:
            # R111：路径**显式传参**（原先改 globals 里的 HEAD_STATE_FILE，静态判据看不见、
            # 且历史上真出过 patch 打错模块对象的事故）
            return step0_head_safety(
                full=full, sync_mirror=sync_mirror,
                state_file=_pl.Path(wt) / "whisperer-head.txt",
                log_file=_pl.Path(wt) / "memory" / "whisperer-tamper.log",
            )
        finally:
            g["run"], g["ROOT"] = saved

    try:
        # 两个「远端」：gc.git = 主仓线，og.git = 镜像；seed 用来往它们推进 main
        _git_at(hd, "init", "-q", "--bare", "-b", "main", "gc.git")
        _git_at(hd, "init", "-q", "--bare", "-b", "main", "og.git")
        seed = os.path.join(hd, "seed")
        os.makedirs(seed)
        _git_at(seed, "init", "-q", "-b", "main", ".")
        _git_at(seed, "config", "user.email", "t@t")
        _git_at(seed, "config", "user.name", "t")
        io.open(os.path.join(seed, "f.txt"), "w", encoding="utf-8").write("A\n")
        _git_at(seed, "add", "-A")
        _git_at(seed, "commit", "-qm", "A")
        # 真仓两面都有 main + master（Step 0 的 fetch 用的是 `fetch <remote> main master`
        # 多 refspec——缺任一条 git 整条 fetch 直接 rc=128，ref 一步不前进，夹具会伪装成「线没动」）。
        _git_at(seed, "push", "-q", os.path.join(hd, "gc.git"), "main", "main:master")
        _git_at(seed, "push", "-q", os.path.join(hd, "og.git"), "main", "main:master")

        os.makedirs(wt)
        _git_at(wt, "init", "-q", ".")
        _git_at(wt, "config", "user.email", "t@t")
        _git_at(wt, "config", "user.name", "t")
        _git_at(wt, "remote", "add", "gitcode", os.path.join(hd, "gc.git"))
        _git_at(wt, "remote", "add", "origin", os.path.join(hd, "og.git"))
        _git_at(wt, "fetch", "-q", "gitcode")
        _git_at(wt, "fetch", "-q", "origin")
        _git_at(wt, "checkout", "-q", "-b", "slave", "gitcode/main")
        # 在飞工作：一个已跟踪文件的未提交改动 + 一个未跟踪新文件。
        # 旧版 Step 0 的 reset --hard 会抹掉前者（后者只是陪衬，reset 不动未跟踪件）。
        io.open(os.path.join(wt, "f.txt"), "w", encoding="utf-8").write("在飞改动\n")

        def _wip_kept():
            return io.open(os.path.join(wt, "f.txt"), encoding="utf-8").read().strip() == "在飞改动"

        # H1 四态 + 量不到：纯函数面，逐档判定，不许把「量不到」折成篡改
        def _cs(l, g, a1, a2):
            return classify_head_state(l, g, a1, a2)
        h1 = (_cs("x", "x", None, None)[0] == "same"
              and _cs("x", "y", True, False)[0] == "behind"
              and _cs("x", "y", False, True)[0] == "ahead"
              and _cs("x", "y", False, False)[0] == "diverged"
              and _cs("x", "y", None, None)[0] == "unknown"
              and _cs("", "y", True, True)[0] == "unknown"
              and "篡改" not in _cs("x", "y", True, False)[1]
              and "篡改" not in _cs("x", "y", None, None)[1])
        print("  " + ("✅" if h1 else "❌") + " H1 classify_head_state 四态齐备，behind/unknown 文案不含「篡改」")
        if not h1:
            rc = 1

        # H2 落后主线：绿灯 + 零写动作 + HEAD 未动 + 在飞改动没被抹
        _git_at(seed, "commit", "-q", "--allow-empty", "-m", "B")
        _git_at(seed, "push", "-q", os.path.join(hd, "gc.git"), "main", "main:master")
        head_before = _git_at(wt, "rev-parse", "HEAD").stdout.strip()
        del calls[:]
        h2_head, h2_status = _step()
        h2 = (h2_status.startswith("✅") and "落后" in h2_status
              and h2_head == head_before[:7]  # 绊线：读到的必须是夹具 HEAD，不是本仓 HEAD
              and head_before == _git_at(wt, "rev-parse", "HEAD").stdout.strip()
              and _wip_kept() and not _reset_calls_since())
        print("  " + ("✅" if h2 else "❌") + " H2 落后主线=绿灯且零写动作（HEAD 未动、在飞改动仍在、读的是夹具）：%s" % h2_status[:30])
        if not h2:
            rc = 1

        # H3 领先主线（feature 分支含未合入提交）：同样绿灯 —— 旧版在这一档直接 reset，抹掉整条分支工作
        _git_at(wt, "merge", "-q", "--ff-only", "gitcode/main")
        _git_at(wt, "commit", "-q", "--allow-empty", "-m", "C-unit")
        del calls[:]
        h3_head, h3_status = _step()
        h3 = (h3_status.startswith("✅") and "领先" in h3_status
              and _git_at(wt, "rev-parse", "HEAD").stdout.strip()
              != _git_at(wt, "rev-parse", "gitcode/main").stdout.strip()
              and _wip_kept() and not _reset_calls_since())
        print("  " + ("✅" if h3 else "❌") + " H3 领先主线=绿灯（旧版在此 reset --hard 抹掉本分支工作）：%s" % h3_status[:30])
        if not h3:
            rc = 1

        # H4 真分叉才报 ⚠️（互不为祖先），且仍然只出方案、不动手
        _git_at(seed, "checkout", "-q", "-b", "side")
        _git_at(seed, "commit", "-q", "--allow-empty", "-m", "D")
        _git_at(seed, "push", "-q", os.path.join(hd, "gc.git"), "side:main", "side:master")
        del calls[:]
        h4_head, h4_status = _step()
        wrote = _reset_calls_since()
        h4 = (h4_status.startswith("⚠️") and "分叉" in h4_status
              and not [c for c in wrote if c[1] in ("reset", "checkout", "push")]
              and _wip_kept()
              and os.path.exists(os.path.join(wt, "memory", "whisperer-tamper.log")))
        print("  " + ("✅" if h4 else "❌") + " H4 真分叉报 ⚠️、只记日志不改状态（写动作面 %d 条）：%s" % (len(wrote), h4_status[:30]))
        if not h4:
            rc = 1

        # H5 镜像不同步默认不动手；显式 --sync-mirror 才允许 push，且只推 origin、不推主仓线
        del calls[:]
        _step()
        auto_push = [c for c in calls if "push" in c]
        del calls[:]
        _step(sync_mirror=True)
        opt_push = [c for c in calls if "push" in c]
        h5 = (not auto_push and len(opt_push) == 1 and "origin" in opt_push[0]
              and "gitcode" not in opt_push[0])
        print("  " + ("✅" if h5 else "❌") + " H5 镜像强推摘成显式旗标（默认 push=%d 条；--sync-mirror 时 %d 条且只指 origin）" % (len(auto_push), len(opt_push)))
        if not h5:
            rc = 1

        # H6 源码自省：Step 0 里不许再出现 reset/checkout；强制旗标 只许出现在 push origin 那一行；
        #     判定函数必须保持纯（不调 git），否则上面几格的读数不可信。
        s0 = inspect.getsource(step0_head_safety)
        force_lines = [l for l in s0.splitlines() if "--force" in l]
        h6 = ('"reset"' not in s0 and '"checkout"' not in s0
              and bool(force_lines) and all(("push" in l and "origin" in l) for l in force_lines)
              and "sync_mirror" in s0
              and "run(" not in inspect.getsource(classify_head_state)
              and "sh(" not in inspect.getsource(classify_head_state))
        print("  " + ("✅" if h6 else "❌") + " H6 Step 0 无 reset/checkout、--force 只在显式镜像臂、classify 保持纯函数（force 行数=%d）" % len(force_lines))
        if not h6:
            rc = 2
    except Exception as e:
        print("  ❌ H 族执行异常: %r" % (e,))
        rc = 2
    finally:
        # 桩的还原在 _step 的 finally 里按函数真身 globals 做，这里只收尾夹具
        _sh.rmtree(hd, ignore_errors=True)
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
    # R120：镜像强推从 Step 0 的缺省副作用里摘出来，改成显式旗标——
    # 不加它，巡检拍一个 push 都不发；加了它也只推 origin 镜像，永不推主仓线。
    g.add_argument("--sync-mirror", action="store_true",
                   help="显式把 origin 镜像强推到 gitcode/main 现值（默认不做任何 push）")
    args = ap.parse_args()

    if args.self_test:
        sys.exit(selftest())

    if args.fast:
        # ==================== FAST MODE ====================
        print(f"⚡ {datetime.now().strftime('%H:%M:%S')} 风语者 fast HEAD 状态巡检 (<3s)")
        try:
            head, head_status = step0_head_safety(full=False, sync_mirror=args.sync_mirror)
        except Exception as e:
            print(f"FATAL: {e}")
            sys.exit(2)
        print(f"HEAD: {head} | {head_status}")
        print(f"下次 1min（fast）/ 15min（full）")
        # 退出码：真分叉/量不到=1，其余（含落后、领先）=0
        sys.exit(1 if "⚠️" in head_status else 0)

    # ==================== FULL MODE ====================
    print(f"🔍 {datetime.now().strftime('%H:%M:%S')} 风语者巡检")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    try:
        head, head_status = step0_head_safety(full=True, sync_mirror=args.sync_mirror)
        mc, ab, candidates = step1_branch_scan()
        if args.auto_merge and candidates:
            auto_merge(candidates)
        step2_agent_claim()
        step3_issue_scan()
    except Exception as e:
        print(f"FATAL: {e}")
        sys.exit(2)
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print(f"HEAD: {head} | {head_status} | 下次 15min")
    # R120：巡检拍的退出码与 fast 同一口径（旧版这里恒 0，把分叉也吞成绿灯）
    sys.exit(1 if "⚠️" in head_status else 0)

if __name__ == "__main__":
    main()
