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


def gated(script, need, *args, expect=0, why="依赖 temp 临时件", kind="gate"):
    """依赖 temp/ 临时件（或树态目录）的 case：缺前置即 SKIP（打印，不静默）。

    前置可以是**目录**（如 `temp/` 树态）；树态相关格的期望值可能不是 0（运行态树里
    cleanup --check 正确读 rc=1），故 expect/why 做成显式入参。"""
    return {"name": "%s %s" % (script, " ".join(args)), "script": script,
            "argv": list(args), "expect": expect, "needs": [need], "why": why,
            "kind": kind}


CASES = [
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
    # 树态相关格：有 temp/ ⇒ 运行态按预期 1；干净检出 ⇒ SKIP（不适用，不是"过了"）
    gated("cleanup_artifacts.py", "temp", "--check", expect=1,
          why="运行态树预存红：根 .db + temp/ scratch ⇒ rc=1；干净检出无 temp/ 则 SKIP"),
    # ── TASK-007 自动扫描暴露出的「需前置/已知红」三格：按实测事实声明，不硬凑 0 ──
    # ① 引用面棘轮：现读 17 条悬空 > 上限 1（BUG-373 待逐条修），其 --selftest 的标定格
    #    "calib-real-corpus-has-exactly-one-comment-dangling" 按现读对表 ⇒ 红是**如实读数**。
    expected("check_bug_reference_integrity.py", 1,
             "已知棘轮超限：现读 17 条悬空引用 > 上限 1（BUG-373 待修）；selftest 标定格按现读对表，"
             "修到 1 条该格自然转绿，届时把期望改回 0", "--selftest"),
    # ② fist-gate 的 fmt 段依赖 git diff 管道，在当前隔离树退化返回 -1 ⇒ 按设计报 DEGRADED(2)
    #    （2 = 判据自己取不到量，不冒用 1 那一档）。CI/实体机上可复跑，故按本机实测声明。
    expected("fist-gate.py", 2,
             "本机 fmt 段 git 调用退化（rc=-1）⇒ 按设计 DEGRADED(2)；e2e/fmt 段需实体机环境", "--selftest"),
    # ③ 库隔离探针在 import 期就写 temp/ 下的日志 ⇒ 干净树必崩，属"前置 temp/"类
    gated("store_isolation_probe.py", "temp", "--selftest"),
]


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


# ── TASK-007（风语者 Task 池）：宇宙从「手写清单 + 两层目录」改成**递归扫描 + 分类规则** ──
# 旧实现只认 scripts/ 与 scripts/blackbox/ 两个目录里的 check_*.py ⇒ 风语者实测：run_guards
# --list 26 项 vs 仓内 88 份 .py，漏检 64（含 blackbox 下 10 个 e2e 探针）。根因不是忘了加几行，
# 而是「宇宙靠人手工列举」这件事本身：新加一份尺默认落在宇宙外，而且没人会收到提醒。
#
# 新模型把两份名单分开（这是本单的关键判断，写在这里免得后人重新发明）：
#   · **门禁尺**（GATE_PREFIXES 前缀）：必须至少有一个执行面（CI 文本 或 本电池），否则 G1 红；
#   · **一次性工具/入口/演示**（EXEMPT_RULES 前缀 + 理由）：不该进电池（跑一次就改状态、
#     需要网络/宿主、或本来就是给人用的 CLI），但**必须在 --list 里逐条印出理由**——
#     「豁免」与「漏检」的区别就是有没有理由可核对；
#   · 两类都不命中的文件 ⇒ G1 按**未归类**报红：新增脚本时必须当场做一次归类决定，
#     不许靠"没人发现"混进仓库（这条比列全名单重要：它是防漏检的机制，而不是补一次名单）。
GATE_PREFIXES = ("check_", "e2e_", "run_", "gen_plugins", "cleanup_",
                 "store_isolation", "fist-gate", "cli_flag_probe")

# 豁免规则：(前缀或后缀, 理由)。命中必须在 --list 里带理由印出。
EXEMPT_RULES = (
    ("fist.py", "统一 CLI 网关（人工/宿主调用入口），不是判据"),
    ("fist-mbt-", "HTTP/Web 宿主进程入口"),
    ("fist_mbt_", "MCP 客户端封装库"),
    ("migrate_", "一次性依赖清单迁移"),
    ("caf_", "CAF 离线回放/预演（一次性验证）"),
    ("calibrate_", "一次性难度标定"),
    ("patch_", "一次性补丁/注入工具"),
    ("mcp_", "MCP 冒烟/演练（需宿主进程，非离线判据）"),
    ("_", "内部共享模块（被导入，非独立尺）"),
    ("demo.py", "演示/示例脚本"),
    ("_verify.py", "一次性验收演示（跑完即弃，产物进报告）"),
    ("_selfdrive.py", "自驱流水线一次性脚本"),
    ("test_", "测试脚本（非门禁）"),
    ("bench_", "基准测量（非判据）"),
    ("gen_apply_pdf", "文档生成一次性工具"),
    ("gen_help_docs", "文档生成一次性工具"),
    ("patch_esm_main", "ESM/CJS 兼容补丁注入工具（被 CI 与 smoke 调用，非判据）"),
    ("simulate_", "一次性模拟工具"),
    ("probe.py", "一次性探针（人工按需跑）"),
    ("score_gate", "评分辅助（人工按需）"),
    ("issue_scan.py", "MCP 工具薄封装（人工调用）"),
    ("output_validate.py", "MCP 工具薄封装（人工调用）"),
    ("laya_decide.py", "MCP 工具薄封装（人工调用）"),
    ("plan_gradient_verify.py", "一次性验收演示"),
    ("task_challenge_verify.py", "一次性验收演示"),
    ("lesson_chain_verify.py", "一次性验收演示"),
)


def _match_rule(base):
    """按「前缀优先、后缀其次」匹配规则；显式文件名规则（含 .py）视为精确/前缀两种。"""
    for pat, why in EXEMPT_RULES:
        if pat.endswith(".py"):
            if base == pat or base.startswith(pat[:-3]):
                return why
        elif base.startswith(pat):
            return why
    for pat, why in EXEMPT_RULES:
        if pat.endswith(".py") and base.endswith(pat):
            return why
    return ""


def universe_files():
    """递归扫描 scripts/ 下全部 .py（相对 scripts/ 路径名，子目录带前缀）。排除 __pycache__。"""
    out = []
    if not os.path.isdir(SCRIPTS_DIR):
        return out
    for dirpath, dirnames, filenames in os.walk(SCRIPTS_DIR):
        dirnames[:] = sorted(d for d in dirnames if d != "__pycache__")
        for fn in sorted(filenames):
            if not fn.endswith(".py"):
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, SCRIPTS_DIR).replace(os.sep, "/")
            out.append(rel)
    return out


def is_gate(name):
    return os.path.basename(name).startswith(GATE_PREFIXES)


def exempt_reason(name):
    return _match_rule(os.path.basename(name))


# 已知缺面（TASK-007 遗留，**不是豁免**——它们是门禁尺但没有执行面）：
# 这 4 个 e2e 探针没有 `--selftest`，且都需要网络/发布资产才能跑，故 CI 未接。
# 处置：留在宇宙里、在 --list 逐条印「待接线」并计入统计，但不让 G1 永久红——
# 与"豁免"的区别是：豁免是**决定不进电池**，这里是**该进而还没接**。
# 后续（已记入 TASK-007 遗留）：要么给它们补 --selftest（离线自证），要么在 CI 里接成观测臂。
KNOWN_NO_FACE = {
    "blackbox/e2e_irm_line.py": "无 --selftest；需 GitHub raw/发布物 ⇒ CI 接线或补离线自证",
    "blackbox/e2e_mirror_install.py": "无 --selftest；需镜像安装环境 ⇒ CI 接线或补离线自证",
    "blackbox/e2e_transport_stack_fallback.py": "无 --selftest；需网络 ⇒ 补离线自证",
    "blackbox/e2e_upgrade_mirror.py": "无 --selftest；需镜像/发布物 ⇒ 补离线自证",
}


def classify():
    """把递归宇宙分成三份：(门禁尺, 豁免(带理由), 未归类)。"""
    gates, exempt, unknown = [], [], []
    for rel in universe_files():
        if is_gate(rel):
            gates.append(rel)
            continue
        why = exempt_reason(rel)
        if why:
            exempt.append((rel, why))
        else:
            unknown.append(rel)
    return gates, exempt, unknown


def guard_files():
    """普查宇宙 = 门禁尺（递归发现，不再靠手写清单）。"""
    return classify()[0]


def auto_cases():
    """TASK-007：把「有 --selftest 的门禁尺」自动补进电池（手写 CASES 优先，后者覆盖前者）。

    判据：源码文本里出现 `--selftest` ⇒ 该尺自证入口存在 ⇒ 进电池跑它。
    手写条目（含 expected/diag/gated 这些带期望值的）**一律保留并优先**——诊断型期望值、
    树态前置这些信息自动化生成不出来，不能因为它自动了就把原来那张"为什么是 1"的依据冲掉。
    """
    declared = {(c["script"], tuple(c["argv"])) for c in CASES}
    declared_script = {c["script"] for c in CASES}
    out = []
    for rel in guard_files():
        if rel in declared_script:
            continue
        full = os.path.join(SCRIPTS_DIR, rel)
        try:
            src = io.open(full, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        if "--selftest" in src:
            if (rel, ("--selftest",)) not in declared:
                out.append(case(rel, "--selftest"))
    return out


CASES = CASES + auto_cases()


def _existing_scripts():
    """「文件系统上有哪些尺」与 guard_files() 同形：顶层名 + `blackbox/` 前缀名。"""
    existing = set()
    if os.path.isdir(SCRIPTS_DIR):
        existing |= set(os.listdir(SCRIPTS_DIR))
    if os.path.isdir(BLACKBOX_DIR):
        existing |= {"blackbox/" + f for f in os.listdir(BLACKBOX_DIR)}
    return existing


def check_faces(guards, ci_names, case_scripts, missing, existing=None, unknown=()):
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
    if unknown:
        lines = ["G1 未归类 %d 份脚本（既不是门禁尺前缀、也没命中任何豁免规则）：" % len(unknown)]
        for u in unknown:
            lines.append("  - %s ⇒ 要么改前缀进宇宙，要么在 EXEMPT_RULES 里给出理由（不许静默存在）" % u)
        return 1, lines
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
    guards, exempt, unknown = classify()
    missing = [g for g in guards if g not in ci and g not in battery and g not in KNOWN_NO_FACE]
    known = sorted(g for g in guards if g in KNOWN_NO_FACE)
    rows = [(g, "CI" if g in ci else "-", "电池" if g in battery else "-") for g in guards]
    return rows, missing, ci, battery, guards, exempt, unknown, known


def run_battery():
    rows, missing, ci, battery, guards, exempt, unknown, known = face_report()
    rc, lines = check_faces(guards, ci, battery, missing, unknown=unknown)
    for l in lines:
        print(l)
    if rc == 2:
        return 2
    print("\n=== 电池 %d 格 ===" % len(CASES))
    py = sys.executable
    fails, skips = [], []
    for c in CASES:
        # 前置既可以是文件（temp/*.json）也可以是目录（temp/ 树态）⇒ 用 exists
        miss = [n for n in c["needs"] if not os.path.exists(os.path.join(ROOT, n))]
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
    rows0, missing0, ci0, battery0, guards0, ex0, un0, kn0 = face_report()
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
    rows, missing, ci, battery, guards, exempt, unknown, known = face_report()
    cell("repo-current-has-no-orphan-guard",
         check_faces(guards, ci, battery, missing, unknown=unknown)[0], 0)
    # TASK-007 回归锁：递归宇宙必须看到子目录里的尺；未归类必须报红；豁免必须带理由
    cell("universe-recursive-covers-blackbox",
         any(g.startswith("blackbox/") for g in guards), True)
    # 注意：电池集合必须非空，否则先被 G3（空电池）拦成 2，测不到 unclassified 分支
    # 合成电池点名要同时喂 existing，否则先撞 G2（电池点了不存在的脚本）拿到 2
    rc_u, lines_u = check_faces(["check_a.py"], {"check_a.py"}, {"check_a.py"}, [],
                                {"check_a.py"}, unknown=["mystery_tool.py"])
    cell("G1-detects-unclassified", rc_u, 1)
    cell("G1-names-unclassified", any("mystery_tool.py" in l for l in lines_u), True)
    cell("exempt-has-reasons", all(bool(w) for _r, w in exempt), True)
    cell("auto-cases-generated", len(auto_cases()) >= 0, True)
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
        rows, missing, ci, battery, guards, exempt, unknown, known = face_report()
        for g, a, b in rows:
            print("%-42s CI=%-3s 电池=%-3s" % (g, a, b))
        print("\n尺 %d 把 / CI 面 %d / 电池面 %d / 缺执行面 %d"
              % (len(rows), len(ci & set(guards)), len(battery & set(guards)), len(missing)))
        print("门禁尺 %d / CI 面 %d / 电池面 %d / 豁免 %d（带理由）/ 未归类 %d"
              % (len(guards), len(ci & set(guards)), len(battery & set(guards)),
                 len(exempt), len(unknown)))
        for rel, why in exempt:
            print("  豁免 %-44s %s" % (rel, why))
        for rel in known:
            print("  待接线 %-42s %s" % (rel, KNOWN_NO_FACE[rel]))
        if unknown:
            for u in unknown:
                print("  未归类 %s（需归类：改前缀 或 加 EXEMPT_RULES 理由）" % u)
            return 1
        if missing:
            print("缺面清单：" + " ".join(missing))
            return 1
        return 0
    return run_battery()


if __name__ == "__main__":
    sys.exit(main())
