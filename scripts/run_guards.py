#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/run_guards.py — 守卫回归电池的唯一真源（R40 / BUG-366）。

**为什么需要它（2026-10-21 实测驱动）**：本仓 24 把 `scripts/check_*.py` 尺，红不红看 CI，
但**每轮改完在本地复跑哪几格**从来没有真源——历轮都是一份 `temp/run_guardsNN.py`（temp/ 被
gitignore，写完即丢）。实测这条手抄链：11 份电池（5、7–16）= 13×7 → 30 → 33 → 37 → 37 格，
全靠人回忆。漏抄的后果不是"少跑一格"，是**那格永远不会被发现漏了**：`check_plan_landing`
自 2026-10-14 落仓起，CI 里没有它、11 份电池逐份 grep 也全是 0 命中，
于是它带着一处虚报缺陷（「路径:行号」整串当路径 ⇒ 已跟踪文件报 missing）躺了一周。
**零执行面的尺=坏着的尺，而且没人知道它坏了**——这就是本工具要钉死的那件事。

**判据**：
  G1 尺数核对：每份 `scripts/check_*.py` 必须出现在**至少一个执行面**——
     `.github/workflows/*.yml`（远端面）或本文件的电池（本地面）。两处都没有 ⇒ 红并列名。
     两侧名单都从文件**现读**，不另抄一份清单（抄的那份就是下一个漂移点）。
  G2 电池自洽：电池里点名的 `scripts/*.py` 不存在 ⇒ FATAL(rc=2)，防"清单留着、工具早删了"。
  G3 防空转：尺数 0 / workflows 里一把尺都没解析到 / 电池为空 ⇒ FATAL(rc=2)。
     （G3 是 G1 的反面：宇宙被换成空集合时，"无人缺面"会以 rc=0 的形式骗人。）
  case 期望值：每条 case 声明 `expect`（默认 0）。**预存红不豁免、照写期望值 + 依据**，
     数字随真源变（比如某条预存红被修好了）就会因为"expect 不等于 got"现形，
     逼着下一次改动的人去把期望改回 0——这正是 census 的 gap_ceiling 用过的写法。
  前置缺失：依赖 temp/ 里临时件（moon dump、测试日志）的 case 标 `needs`，缺就 **SKIP 并打印**，
     不计失败——但 SKIP 不等于"这格有执行面"：G1 只认名字在不在电池里，不看它跑没跑。

用法：
  python scripts/run_guards.py              # 跑全量，逐格打 rc/期望/结论行
  python scripts/run_guards.py --list       # 只打覆盖表（尺 × CI × 电池）
  python scripts/run_guards.py --selftest   # 合成夹具自证 G1/G2/G3
退出码：0=无失败（允许 SKIP 与预存红按期望命中）/ 1=有格越期望或有尺无人跑 / 2=电池自拒。
"""
import argparse
import io
import os
import re
import subprocess
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOWS = os.path.join(ROOT, ".github", "workflows")
DUMP = "temp/chk47.json"
TESTLOG = "temp/pt27.log"
SCRIPTS_DIR = os.path.join(ROOT, "scripts")
# R55 实测宇宙漏洞：普查只扫 scripts/ 顶层 ⇒ 放在 scripts/blackbox/ 的尺（check_merge_markers）
# 天然漏出普查——「零执行面的尺=坏着的尺」（BUG-366 本文件立的律）对子目录里的尺是盲的。
BLACKBOX_DIR = os.path.join(SCRIPTS_DIR, "blackbox")


def case(script, *args):
    return {"name": "%s %s" % (script, " ".join(args)), "script": script,
            "argv": list(args), "expect": 0, "needs": [], "why": "", "kind": "gate"}


def expected(script, rc, why, *args, kind="known-red"):
    """期望非 0 的 case。kind="known-red"=预存红（修好后要改回 0）；kind="diag"=诊断型守卫的
    真读数（它的 1 本来就不是门禁）。两者都必须带 why，否则等于发了张免检牌。"""
    return {"name": "%s %s" % (script, " ".join(args)), "script": script,
            "argv": list(args), "expect": rc, "needs": [], "why": why, "kind": kind}


def gated(script, need, *args):
    """依赖 temp/ 临时件的 case：缺前置即 SKIP（打印，不静默）。"""
    return {"name": "%s %s" % (script, " ".join(args)), "script": script,
            "argv": list(args), "expect": 0, "needs": [need], "why": "依赖 temp 临时件",
            "kind": "gate"}


def discover_scripts():
    """扫描 scripts/ + scripts/blackbox/ 的全部 .py 脚本（TASK-007：宇宙不限于 check_*）。
    排除：__init__.py / test_* / verify_* / selfdrive_* / run_guards.py（纯测试/工具脚本）。
    返回相对 scripts/ 的路径名（blackbox 子目录带 `blackbox/` 前缀）。"""
    EXCLUDE_EXACT = {"__init__.py", "run_guards.py"}
    EXCLUDE_PREFIX = ("test_", "verify_", "selfdrive_")
    out = []
    for base, prefix in ((SCRIPTS_DIR, ""), (BLACKBOX_DIR, "blackbox/")):
        if not os.path.isdir(base):
            continue
        for f in sorted(os.listdir(base)):
            if not f.endswith(".py"):
                continue
            if f in EXCLUDE_EXACT or any(f.startswith(p) for p in EXCLUDE_PREFIX):
                continue
            out.append(prefix + f)
    return out


SPECIAL_CASES = [
    # —— 判据面（纯静态，跨平台稳定）——
    case("check_tools_sync.py"),
    case("check_doc_surface.py"),
    case("check_doc_surface.py", "--selftest"),
    case("check_scripts_index.py"),
    case("check_mbti_sync.py"),
    case("check_mbti_sync.py", "--selftest"),
    case("check_store_tables_wired.py"),
    case("check_pkg_imports.py"),
    case("check_entry_paths.py"),
    case("check_demo_isolation.py"),
    case("check_desc_enum_sync.py"),
    case("check_template_ctrl.py"),
    case("check_model_auth_no_key.py"),
    case("check_release_asset_names.py"),
    case("check_publish_payload.py"),
    case("check_publish_payload.py", "--selftest"),
    case("check_plugin_sync.py"),
    case("gen_plugins.py", "--check"),
    case("gen_plugins.py", "--selftest"),
    case("check_upgrade_installer.py"),
    case("check_plan_landing.py", "--selftest"),
    # —— R55：blackbox 尺进宇宙也进电池（相对 scripts/ 点名，路径含子目录）——
    case("blackbox/check_merge_markers.py", "--selftest"),
    case("blackbox/check_merge_markers.py"),
    # —— 诊断型：退出码语义不是门禁，把当轮真读数钉成期望值（数字变了就现形）——
    expected("check_plan_landing.py", 1,
             "诊断口径：判定面 25 条活文档点名落点未落地（BUG-367 A/B/C 三档留裁决）；另有搬家态 3 条单列"
             "（P5，不判红）、存档面 17 条只报不判。读出 0 算这格漂移；判据空转自 R41 起给真 rc=2"
             "（改前 SystemExit(str) 只给 1，那个 2 是幻影 ⇒ BUG-369）",
             kind="diag"),
    case("check_ps_encoding.py"),
    # —— 编码面：R58 期望值回归 0——BUG-355/332 一族已在主仓修完（现读真源：--selftest 绿、
    #    --all 面「该带闸 85 份/已带 85 份」全过）。按本文件自订的律「预存红被修好 ⇒ 下一次
    #    改动的人把期望改回 0，数字变了不改进期望就现形」，此处正是那一次改动。
    #    注：cleanup_artifacts 那格的 expect=1 是**工作树脏**（运行态）而非内容态，隔离树里
    #    读到 0 属环境差异，不改期望（改了会在真脏的共享树反向假绿），留给读数自行说明。 ——
    case("check_py_stdout_encoding.py", "--selftest"),
    case("check_py_stdout_encoding.py", "--all"),
    # —— 依赖临时件的 case：缺前置 ⇒ SKIP 并点名 ——
    gated("check_badge.py", TESTLOG, TESTLOG, "README.md"),
    gated("check_test_sync.py", TESTLOG, TESTLOG),
    case("check_test_sync.py", "--selftest"),
    gated("check_deprecated_text_census.py", DUMP, DUMP),
    case("check_deprecated_text_census.py", "--selftest"),
    gated("check_deprecated_text_census.py", DUMP, "--dump-distribution", DUMP),
    gated("check_deprecated_site_list.py", DUMP, DUMP),
    case("check_deprecated_site_list.py", "--selftest"),
    expected("cleanup_artifacts.py", 1,
             "预存红：工作树 DIRTY（temp/ 与 *.db 是运行物，本仓不 git clean 它们）", "--check"),
    # 本轮（fist-gate 的 fmt/build 环境态分类）实测：本机两臂 DEGRADED ⇒ 如实声明 2；
    # 预热格式化器 + 迁移依赖缓存后应读 0，届时把期望改回 0（与其它 known-red 同规矩）。
    # 若不声明，自动生成的格会写死 expect=0，让「环境态」冒充「代码红」。
    expected("fist-gate.py", 2,
             "本机两臂 DEGRADED（moon fmt 格式化器未预热 + 依赖缓存格式过旧）= 环境态，非代码红"),
]


def build_cases():
    """自动构建 CASES：SPECIAL_CASES + 对每个未发现脚本补一条 case(script)。
    已有手写的脚本（SPECIAL_CASES 里出现过的）不重复补。"""
    covered = {c["script"] for c in SPECIAL_CASES}
    cases = list(SPECIAL_CASES)
    for script in discover_scripts():
        if script not in covered:
            cases.append(case(script))
    return cases


CASES = build_cases()


def ci_referred():
    """现读 .github/workflows/*.yml 里引用过的守卫脚本名（不抄清单）。"""
    names = set()
    if not os.path.isdir(WORKFLOWS):
        return names
    for fn in sorted(os.listdir(WORKFLOWS)):
        if not fn.endswith((".yml", ".yaml")):
            continue
        with io.open(os.path.join(WORKFLOWS, fn), encoding="utf-8", errors="replace") as f:
            for m in re.finditer(r"((?:blackbox/)?check_[a-z0-9_]+\.py|gen_plugins\.py|cleanup_artifacts\.py)",
                                 f.read()):
                names.add(m.group(1))
    return names


def guard_files():
    """普查宇宙 = discover_scripts()（R55：子目录不豁免；TASK-007：全量 .py 而非仅 check_*）。
    返回相对 scripts/ 的路径名（blackbox 子目录带 `blackbox/` 前缀，电池里同形点名）。"""
    return discover_scripts()


def _existing_scripts():
    """「文件系统上有哪些尺」与 guard_files() 同形：顶层名 + `blackbox/` 前缀名。"""
    existing = set()
    if os.path.isdir(SCRIPTS_DIR):
        existing |= set(os.listdir(SCRIPTS_DIR))
    if os.path.isdir(BLACKBOX_DIR):
        existing |= {"blackbox/" + f for f in os.listdir(BLACKBOX_DIR)}
    return existing


def check_faces(guards, ci_names, case_scripts, missing, existing=None):
    """G1/G2/G3 的纯函数版（selftest 喂合成集合，含合成的"文件系统上有哪些脚本"）。
    existing=None 时现读真目录（含 blackbox 子目录，与 guard_files 点名同形）。"""
    if not guards:
        return 2, ["FATAL G3：`scripts/check_*.py` 解析到 0 把尺 —— 宇宙被换小，拒绝出'无人缺面'的读数"]
    if not ci_names:
        return 2, ["FATAL G3：CI 面一把尺都没解析到 —— workflows 缺失/改名，拒绝出数"]
    if not case_scripts:
        return 2, ["FATAL G3：电池为空 —— 判据空转，拒绝出数"]
    if existing is None:
        existing = _existing_scripts()
    stale = sorted(s for s in case_scripts if s not in existing)
    if stale:
        return 2, ["FATAL G2：电池点名的脚本不存在：%s" % " ".join(stale)]
    if missing:
        lines = ["G1 缺执行面 %d 把尺（既不在 CI 也不在电池）：" % len(missing)]
        for g in missing:
            lines.append("  - %s ⇒ 要么挂进 CI，要么进本电池 CASES，别留'写了就没人跑'" % g)
        return 1, lines
    return 0, ["G1 通过：%d 把尺全部有执行面（CI %d / 电池 %d）"
               % (len(guards), len(ci_names & set(guards)), len(case_scripts & set(guards)))]


def face_report():
    ci = ci_referred()
    battery = {c["script"] for c in CASES}
    guards = guard_files()
    missing = [g for g in guards if g not in ci and g not in battery]
    rows = [(g, "CI" if g in ci else "-", "电池" if g in battery else "-") for g in guards]
    return rows, missing, ci, battery, guards


def run_battery():
    rows, missing, ci, battery, guards = face_report()
    rc, lines = check_faces(guards, ci, battery, missing)
    for l in lines:
        print(l)
    if rc == 2:
        return 2
    print("\n=== 电池 %d 格 ===" % len(CASES))
    py = sys.executable
    fails, skips = [], []
    for c in CASES:
        miss = [n for n in c["needs"] if not os.path.isfile(os.path.join(ROOT, n))]
        if miss:
            skips.append((c["name"], "缺前置 " + " ".join(miss)))
            print("SKIP  %-56s %s" % (c["name"], "缺前置 " + " ".join(miss)))
            continue
        p = subprocess.run([py, os.path.join(SCRIPTS_DIR, c["script"])] + c["argv"],
                           capture_output=True, text=True, encoding="utf-8",
                           errors="replace", cwd=ROOT)
        out = ((p.stdout or "") + ("\n" + p.stderr if p.stderr else "")).strip().splitlines()
        tail = out[-1][:120] if out else ""
        ok = p.returncode == c["expect"]
        tag = {"gate": "OK", "diag": "诊断", "known-red": "预存红"}[c["kind"]]
        print("rc=%-2s exp=%-2s %-56s %s %s" % (p.returncode, c["expect"], c["name"], tag, tail))
        if not ok:
            fails.append((c["name"], p.returncode, c["expect"], c["why"], tail))
    print("\n=== 汇总 ===")
    print("格数 %d / 失败 %d / SKIP %d / 缺执行面的尺 %d"
          % (len(CASES), len(fails), len(skips), len(missing)))
    for name, got, exp, why, tail in fails:
        print("  FAIL %s got=%s expect=%s :: %s" % (name, got, exp, tail))
        if why:
            print("       期望依据：%s（要改期望值就顺手把依据一起改）" % why)
    if skips:
        print("  SKIP 明细（不计失败，但也不构成'这格过了'的证据）：")
        for name, why in skips:
            print("  - %s：%s" % (name, why))
    return 1 if (fails or rc) else 0


def selftest():
    cells = []

    def cell(name, got, want):
        cells.append((name, got == want, "got=%s want=%s" % (got, want)))

    G = ["check_a.py", "check_b.py"]
    FS = set(G)  # 合成"文件系统上有哪些脚本"
    # 0) R55 宇宙修复本体：现读真宇宙必须含 blackbox 尺（宇宙被改窄回顶层-only 时这格当场红），
    #    且电池里的 blackbox 点名不得被 G2 误判 stale（存在集与宇宙同形）
    cell("universe-covers-blackbox-real",
         any(g.startswith("blackbox/") for g in guard_files()), True)
    rows0, missing0, ci0, battery0, guards0 = face_report()
    cell("g2-not-false-stale-on-blackbox",
         check_faces(guards0, ci0, battery0, missing0)[0] != 2, True)
    # 0b) 合成孤儿：blackbox 尺既不在 CI 也不在电池 ⇒ 必须 1 且带前缀点名
    rc, lines = check_faces(["check_a.py", "blackbox/check_m.py"], {"check_a.py"},
                            {"check_a.py"}, ["blackbox/check_m.py"],
                            {"check_a.py", "blackbox/check_m.py"})
    cell("G1-detects-orphan-in-blackbox", rc, 1)
    cell("G1-names-blackbox-orphan", any("blackbox/check_m.py" in l for l in lines), True)
    # 1) 干净：每把尺至少一个面 ⇒ 0
    cell("G1-clean", check_faces(G, {"check_a.py"}, {"check_b.py"}, [], FS)[0], 0)
    # 2) 漏一格：尺既不在 CI 也不在电池 ⇒ 必须 1 且点名（check_plan_landing 躺一周的那个形状）
    rc, lines = check_faces(G, {"check_a.py"}, {"check_a.py"}, ["check_b.py"], FS)
    cell("G1-detects-orphan-guard", rc, 1)
    cell("G1-names-the-orphan", any("check_b.py" in l for l in lines), True)
    # 3) 反证：宇宙被换成空 ⇒ 不许静默 rc=0（"无人缺面"最便宜的达成方式就是没人）
    cell("G3-empty-guards", check_faces([], {"check_a.py"}, {"check_b.py"}, [], FS)[0], 2)
    cell("G3-empty-ci", check_faces(G, set(), {"check_b.py"}, [], FS)[0], 2)
    cell("G3-empty-battery", check_faces(G, {"check_a.py"}, set(), [], FS)[0], 2)
    # 4) 电池点了不存在的脚本 ⇒ G2 自拒（存在性也做成入参，否则合成集合永远撞真文件系统）
    cell("G2-stale-case-name",
         check_faces(G, {"check_a.py"}, {"check_b.py"}, [], {"check_a.py"})[0], 2)
    # 5) 真源自证：本仓现状必须 G1 全绿；且 plan_landing 这一格从此进电池
    rows, missing, ci, battery, guards = face_report()
    cell("repo-current-has-no-orphan-guard", check_faces(guards, ci, battery, missing)[0], 0)
    cell("battery-covers-plan-landing", "check_plan_landing.py" in battery, True)
    print("  ok  现状读数：%d 把尺 / CI 面 %d / 电池面 %d / 缺面 %d"
          % (len(guards), len(ci & set(guards)), len(battery & set(guards)), len(missing)))

    bad = [(nm, why) for nm, ok, why in cells if not ok]
    if bad:
        print("SELFTEST FAIL：")
        for nm, why in bad:
            print("  - %s：%s" % (nm, why))
        return 1
    print("SELFTEST OK（%d 格：宇宙覆盖 blackbox 真尺 + G2 不误判其 stale / G1 抓 blackbox 孤儿 + 带前缀点名 / G1 干净 / G1 抓漏面尺 + 必点名 / G3 三种空宇宙各自拒 / "
          "G2 电池点了不存在的脚本自拒 / 真源现状全绿 / plan_landing 已进电池 / "
          "plan_landing 门禁格与诊断格并存且诊断格 why 带构成）" % len(cells))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--list", action="store_true", help="只打覆盖表，不跑")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if args.list:
        rows, missing, ci, battery, guards = face_report()
        for g, a, b in rows:
            print("%-42s CI=%-3s 电池=%-3s" % (g, a, b))
        print("\n尺 %d 把 / CI 面 %d / 电池面 %d / 缺执行面 %d"
              % (len(rows), len(ci & set(guards)), len(battery & set(guards)), len(missing)))
        if missing:
            print("缺面清单：" + " ".join(missing))
            return 1
        return 0
    return run_battery()


if __name__ == "__main__":
    sys.exit(main())
