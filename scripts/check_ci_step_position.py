import sys
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_ci_step_position.py - CI「gate 步骤位置」守卫（TASK-003，R84）。

背景（TASK-003 / CI #275 实证）：`Migrate mooncakes dep manifests` 一步失败会 skip 其后全部步骤——
CI #98/#99 起这是本仓两次 master 级坏状态的公共放大器。merge-marker gate 第一次接线就踩过
（放在 Migrate 之后 → Migrate 崩时最需要它出声的时刻它沉默）。本判据把「位置纪律」机械化：

判定面（F1，红）：对每个含 `Migrate mooncakes` 步骤的 job，凡被分类为 gate 的步骤
（name 命中 gate/guard/守卫/门禁，或 run 块引用 scripts/check_*.py）位置在 Migrate **之后**
且步骤块内没有 `position-why:` 锚点 ⇒ 违例。锚点必须在步骤块内（该步 `- name:` 行到下一
`- name:` 行之间）——放在块外前一行属于上一步的块，判不到。

只报面（必须出数，静默丢弃=数字凭空少）：
- F2 带 `continue-on-error: true` 的步骤（不限 gate 名——fmt 降门那两格史档的步骤名
  不含 gate/guard，按名字分类会漏；不判红：均有据可查，但每次出现都点名，防「降门」
  悄悄蔓延成默认）。
- F3 无 Migrate 步骤的 workflow 里的 gate 步骤（没有 skip 放大器，位置纪律不适用，
  豁免说明只出数、不进棘轮计数）。

棘轮：违例总数（只含 F1）≤ POSITION_WHY_CEILING，只许降不许升（与 BUG-362/367 先例
同律）——本轮按存量标定（首跑实测 34），后续把步骤逐个前移或补锚点即可降档；升档是人的决定。

rc：0 = 违例在棘轮上限内 / 1 = 超上限 / 2 = 判据无法自证（workflows 读不到 / 0 份步骤）。
--selftest 用合成 workflow 自证九格（T1-T9），不碰网络不碰真文件（T9 只跑真源一次做现状锁定）。
"""
import os, re, sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WF_DIR = os.path.join(ROOT, ".github", "workflows")
GATE_NAME_RE = re.compile(r"gate|guard|守卫|门禁", re.I)
CHECK_SCRIPT_RE = re.compile(r"scripts/check_[A-Za-z0-9_]+\.py")
STEP_RE = re.compile(r"^(\s*)-\s+name:\s*(.*)$")
JOB_RE = re.compile(r"^  ([A-Za-z0-9_-]+):\s*$")
MIGRATE_PREFIX = "Migrate mooncakes"
ANCHOR = "position-why:"
COE_RE = re.compile(r"continue-on-error:\s*true")
POSITION_WHY_CEILING = 34  # R84 存量标定（首跑实测 34 条 F1）；只许降


def analyze(text):
    """解析一段 workflow 文本，返回 {findings, coes, steps, migrate_count, jobs}。"""
    lines = text.splitlines()
    job = None
    jobs = []  # [{"name", "migrate_lineno", "steps":[{name, start, lines}]}]
    for i, line in enumerate(lines, 1):
        m = JOB_RE.match(line)
        if m:
            job = {"name": m.group(1), "migrate_lineno": None, "steps": []}
            jobs.append(job)
            continue
        m = STEP_RE.match(line)
        if not m:
            continue
        step = {"name": m.group(2).strip(), "start": i, "lines": []}
        if job is None:
            job = {"name": "(top)", "migrate_lineno": None, "steps": []}
            jobs.append(job)
        if job["steps"]:
            job["steps"][-1]["lines"] = lines[job["steps"][-1]["start"]:i - 1]
        job["steps"].append(step)
        if step["name"].startswith(MIGRATE_PREFIX):
            job["migrate_lineno"] = i
    if jobs and jobs[-1]["steps"]:
        jobs[-1]["steps"][-1]["lines"] = lines[jobs[-1]["steps"][-1]["start"]:]
    findings, coes, f3 = [], [], []
    n_steps = 0
    for j in jobs:
        for s in j["steps"]:
            n_steps += 1
            if COE_RE.search("\n".join(s["lines"])):
                coes.append("%s / %s" % (j["name"], s["name"]))
        if j["migrate_lineno"] is None:
            for s in j["steps"]:
                if is_gate(s):
                    f3.append("%s / %s" % (j["name"], s["name"]))
            continue
        for s in j["steps"]:
            if not is_gate(s):
                continue
            body = "\n".join(s["lines"])
            if s["start"] > j["migrate_lineno"] and ANCHOR not in body:
                findings.append(("F1", j["name"], s["name"], s["start"]))
    return {"findings": findings, "f3": f3, "coes": coes, "steps": n_steps,
            "migrate_count": sum(1 for j in jobs if j["migrate_lineno"]),
            "jobs": len(jobs)}


def is_gate(step):
    body = "\n".join(step["lines"])
    return bool(GATE_NAME_RE.search(step["name"]) or CHECK_SCRIPT_RE.search(body))


def run_all():
    if not os.path.isdir(WF_DIR):
        print("FATAL workflows 目录不存在：%s" % WF_DIR)
        return 2
    files = sorted(f for f in os.listdir(WF_DIR) if f.endswith((".yml", ".yaml")))
    if not files:
        print("FATAL workflows 目录里没有 .yml/.yaml（空扫描不出绿）")
        return 2
    findings, coes, f3_all, n_steps, n_migrate = [], [], [], 0, 0
    for f in files:
        with open(os.path.join(WF_DIR, f), encoding="utf-8", errors="replace") as fh:
            r = analyze(fh.read())
        if r["steps"] == 0:
            print("FATAL %s 解析不到任何步骤（判据空转）" % f)
            return 2
        n_steps += r["steps"]
        n_migrate += r["migrate_count"]
        for kind, job, name, lineno in r["findings"]:
            findings.append("%s:%d job=%s 步骤=%s 在 Migrate 之后且无 position-why 锚点" % (f, lineno, job, name))
        for x in r["f3"]:
            f3_all.append("%s: %s" % (f, x))
        for c in r["coes"]:
            coes.append("%s: %s" % (f, c))
    if n_migrate == 0:
        print("FATAL 全部 workflow 都没有 %s 锚点步骤（判据基准面为空）" % MIGRATE_PREFIX)
        return 2
    for x in findings:
        print("  - %s" % x)
    print("position-why 锚点面：%d 份 workflow / %d 步骤 / %d 个 Migrate 基准；缺锚点违例 %d（上限 %d，只许降）"
          % (len(files), n_steps, n_migrate, len(findings), POSITION_WHY_CEILING))
    print("continue-on-error 步骤（F2 只报不判，防降门蔓延）：%d 处%s"
          % (len(coes), ("：" + "；".join(coes)) if coes else ""))
    print("无 Migrate workflow 的 gate 步骤（F3 豁免位置纪律，只出数）：%d 处%s"
          % (len(f3_all), ("：" + "；".join(f3_all)) if f3_all else ""))
    if len(findings) > POSITION_WHY_CEILING:
        print("FAIL 棘轮超限：%d > %d（升档是人的决定，先给理由再改常量）" % (len(findings), POSITION_WHY_CEILING))
        return 1
    print("PASS gate 步骤位置纪律在棘轮上限内")
    return 0


def selftest():
    executed, fails = [], []
    def wf(body):
        return "name: t\non: [push]\njobs:\n  j1:\n    runs-on: ubuntu\n    steps:\n" + body
    MIG = "      - name: Migrate mooncakes dep manifests\n        run: bash x.sh\n"
    def probe(label, text, want_rc, needle=None):
        r = analyze(text)
        n_f1 = sum(1 for f in r["findings"] if f[0] == "F1")
        rc = 1 if n_f1 > 0 else 0
        executed.append("%s (F1=%d)" % (label, n_f1))
        if rc != want_rc:
            fails.append("%s want rc=%d got F1=%d" % (label, want_rc, n_f1))
        elif needle and needle not in repr(r["findings"]):
            fails.append("%s 点名缺失：%s" % (label, needle))
    probe("T1 后置无锚必红",
          wf(MIG + "      - name: Merge-marker gate\n        run: python3 scripts/check_mm.py\n"), 1, "Merge-marker gate")
    probe("T2 后置有锚不红",
          wf(MIG + "      - name: Merge-marker gate\n        # position-why: 示例\n        run: python3 scripts/check_mm.py\n"), 0)
    probe("T3 前置无锚不红",
          wf("      - name: Merge-marker gate\n        run: python3 scripts/check_mm.py\n" + MIG), 0)
    probe("T4 无 Migrate 豁免",
          wf("      - name: Badge guard\n        run: python3 scripts/check_badge.py\n"), 0)
    probe("T7 非 gate 步骤不抓",
          wf(MIG + "      - name: Test (js)\n        run: moon test\n"), 0)
    probe("T8 check_ 脚本引用也算 gate",
          wf(MIG + "      - name: Some step\n        run: python3 scripts/check_pkg_imports.py\n"), 1, "Some step")
    r = analyze(wf(MIG + "      - name: Format check\n        continue-on-error: true\n        run: moon fmt --check\n"))
    executed.append("T5 continue-on-error 出数不判红 (F1=%d,coe=%d)" % (sum(1 for f in r["findings"] if f[0] == "F1"), len(r["coes"])))
    if r["coes"] != ["j1 / Format check"]: fails.append("T5 continue-on-error 未出数: %r" % r["coes"])
    r = analyze("")
    executed.append("T6 空文本零步骤 (steps=%d)" % r["steps"])
    if r["steps"] != 0: fails.append("T6 空文本应解析到 0 步骤")
    c, _ = 0, None
    real = run_all()
    executed.append("T9 真源现状 rc=%d（上限内=0）" % real)
    if real not in (0,): fails.append("T9 真源现状 rc=%d 不在棘轮上限内" % real)
    print("SELFTEST %s (grid: %s)" % ("OK" if not fails else "FAIL", " / ".join(executed)))
    for f in fails:
        print("SELFTEST FAIL " + f)
    sys.exit(0 if not fails else 2)  # NO_CALL_FACE J2


if __name__ == "__main__":
    if "--selftest" in sys.argv[1:]:
        sys.exit(selftest())
    sys.exit(run_all())
