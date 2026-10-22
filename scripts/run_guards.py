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

    BUG-368：前置可以是**目录**（如 `temp/` 树态）；且树态相关格的期望值可能不是 0
    （运行态树里 cleanup --check 正确读 rc=1），故 expect/why 做成显式入参。"""
    return {"name": "%s %s" % (script, " ".join(args)), "script": script,
            "argv": list(args), "expect": expect, "needs": [need], "why": why,
            "kind": kind}


def discover_scripts():
    """扫描 scripts/ + scripts/blackbox/ 的全部 .py 脚本（TASK-007：宇宙不限于 check_*）。
    排除：__init__.py / test_* / verify_* / selfdrive_* / run_guards.py（纯测试/工具脚本），
    以及长驻服务脚本（R84 实测：fist-mbt-http.py 进电池即起 serve 永不退出——
    e2e_http_contract 外的裸跑无终止路径，电池整轮挂死；CI 只跑 --selftest/--list 不受影响）。
    返回相对 scripts/ 的路径名（blackbox 子目录带 `blackbox/` 前缀）。"""
    EXCLUDE_EXACT = {"__init__.py", "run_guards.py", "fist-mbt-http.py", "fist-mbt-web.py"}
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


RESIDENT_MARKERS = ("serve_forever(", "run_forever(")


def is_resident_src(src):
    """纯函数版分类器：源码里有常驻循环旗标 ⇒ 这脚本自己不会结束。
    从源码现读而不抄名单：新写一个 server 自动归类，改名/搬目录都不会漏。"""
    return any(m in src for m in RESIDENT_MARKERS)


def is_resident(rel):
    try:
        with io.open(os.path.join(SCRIPTS_DIR, rel), encoding="utf-8", errors="replace") as f:
            return is_resident_src(f.read())
    except OSError:
        return False


SPECIAL_CASES = [
    # —— 判据面（纯静态，跨平台稳定）——
    case("check_tools_sync.py"),
    case("check_doc_surface.py"),
    case("check_doc_surface.py", "--selftest"),
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
    # —— R84 (TASK-003)：gate 步骤位置纪律 ——
    case("check_ci_step_position.py"),
    case("check_ci_step_position.py", "--selftest"),
    # —— R55：blackbox 尺进宇宙也进电池（相对 scripts/ 点名，路径含子目录）——
    case("blackbox/check_merge_markers.py", "--selftest"),
    case("blackbox/check_merge_markers.py"),
    # —— 诊断型：退出码语义不是门禁，把当轮真读数钉成期望值（数字变了就现形）——
    expected("check_plan_landing.py", 1,
             "诊断口径：判定面 36 条活文档点名落点未落地（BUG-367 A/B/C 三档留裁决；R72 在 master 基点现读，36>25 棘轮超限属预存内容红）；另有搬家态 3 条单列"
             "（P5，不判红）、存档面 17 条只报不判。读出 0 算这格漂移；判据空转自 R41 起给真 rc=2"
             "（改前 SystemExit(str) 只给 1，那个 2 是幻影 ⇒ BUG-369）",
             kind="diag"),
    case("check_ps_encoding.py"),
    # —— R82：scripts_index 那格按本文件自订的律改记预存红——master 现状 red 的根因是主机
    #    fist-gate.py（454aea3）未在 scripts/README.md 登记（TASK-003/004 施工面，R81 点名）。
    #    主机一登记，got 0 ≠ expect 1 当场现形，逼着把期望改回 0。 ——
    expected("check_scripts_index.py", 1,
             "预存红：fist-gate.py 未在 scripts/README.md 登记（TASK-003/004 面，主机在办；"
             "修好后此格期望改回 0）"),
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
    # —— 会改跟踪面的补丁脚本：只跑有界自检，不许裸跑（脚本名一旦被本表点名，自动补格就不再裸跑）。
    #    R98 全量电池实测：这格裸跑打的是 rc=0 绿灯，却往 src/router 的 struct literal 里再插一份
    #    同名字段（幂等门查错行）⇒ 盘面编译必红。自检格不碰盘，改的是「尺子能不能自证」。
    case("patch_router_config_caf_field.py", "--selftest"),
    expected("cleanup_artifacts.py", 1,
             "预存红：工作树 DIRTY（temp/ 与 *.db 是运行物，本仓不 git clean 它们）", "--check"),
    # ── 本轮（电池只读缺陷）按实测事实补的三格：不硬凑 0 ──
    expected("check_bug_reference_integrity.py", 1,
             "已知棘轮超限：现读 17 条悬空注释引用 > 上限 1（BUG-373 待逐条修）；修到 1 条后自然转绿"),
    gated("check_skill_inject.py", "fist-mbt.db", "fist-mbt.db"),
    expected("fist-gate.py", 2,
             "fmt 段依赖 git diff 管道，本机退化 rc=-1 ⇒ 按设计 DEGRADED(2)；实体机/CI 复跑"),
]


# ── BUG（本轮实测）：电池必须**只读**，且不许把一次性工具当门禁跑 ──
# 现象：TASK-007 把 scripts/ 下全部 .py 都补成电池格后，实测 96 格 / 45 红，且**改工作树**——
# `patch_router_config_caf_field.py` 是把 `use_caf_memory` 写进 src/router/*.mbt 的改码工具，
# 被当门禁执行后 `git status` 多出两处 M（src/router/router_state.mbt、model_router_wbtest.mbt）。
# 判据的解释：**电池是判据面，不是工具跑场**——它必须满足「跑完工作树不变」这条不变量；
# 一次性工具（改码/生成/迁移/标定/演示/宿主客户端）留在宇宙里（可见、可点名），但不进电池。
NON_GATE_RULES = (
    ("patch_", "改码/注入工具（会写工作树，电池只读不变量不许跑）"),
    ("migrate_", "一次性迁移工具（会写文件）"),
    ("calibrate_", "一次性标定工具（会写文件）"),
    ("gen_", "生成器：只有 gen_plugins 是可核对的判据，其余生成即写盘"),
    ("caf_", "CAF 离线回放/预演（一次性验证，写报告）"),
    ("fist", "CLI 网关/HTTP/Web 宿主入口（需宿主进程）"),
    ("mcp_", "MCP 冒烟/演练（需宿主进程）"),
    ("demo", "演示脚本（会写演示库）"),
    ("simulate_", "一次性模拟工具"),
    ("probe", "一次性探针（人工按需）"),
    ("score_gate", "评分辅助（人工按需）"),
    ("issue_scan.py", "MCP 工具薄封装（人工调用）"),
    ("output_validate.py", "MCP 工具薄封装（人工调用）"),
    ("laya_decide.py", "MCP 工具薄封装（人工调用）"),
    ("_verify.py", "一次性验收演示（跑完即弃）"),
)
GEN_PLUGINS_GATE = "gen_plugins.py"


# 自动进电池的门禁族（白名单）。**默认排除**比"默认全进 + 事后排除"安全：
# 默认全进会把改码工具/演示脚本跑起来（实测改过 src/router/*.mbt），
# 而"新脚本默认不进电池"最多是漏检——漏检由 --list 的非判据清单兜底（可见 + 有理由）。
AUTO_CASE_PREFIXES = ("check_", "cleanup_")
AUTO_CASE_EXACT = {"gen_plugins.py", "fist-gate.py"}


def non_gate_reason(script):
    """非「自动进电池」的门禁族时给出理由（空串=是门禁，进电池）。

    注意**不判断脚本会不会写盘**——靠名字猜副作用不可靠；改为白名单：
    只有明确的门禁族（check_/e2e_/cleanup_ + gen_plugins/fist-gate）才自动进电池，
    其余全部列进 --list 的「非判据」清单，由人决定要不要显式加 case。
    """
    base = os.path.basename(script)
    if base in AUTO_CASE_EXACT:
        return ""
    if any(base.startswith(x) for x in AUTO_CASE_PREFIXES):
        return ""
    if base.startswith("e2e_"):
        return "e2e 探针：需宿主进程/网络/发布物或 POSIX 平台，CI 另有观测臂；不进本地电池"
    return "非门禁族（演示/一次性/宿主/辅助）——如需进电池请显式加 case 并写明理由"


def build_cases():
    """自动构建 CASES：SPECIAL_CASES + 对每个未发现脚本补一条 case(script)。
    已有手写的脚本（SPECIAL_CASES 里出现过的）不重复补。
    R98 追修：自动补格时**跳过常驻服务型脚本**——裸跑 `serve_forever()` 的脚本永不退出，
    一格就把整轮电池挂死（TASK-007 自动扫描把 http/web 两个 bridge 卷进来实测卡死 6 分钟）。
    手写的格子（带旗标的有界跑法）不受影响。"""
    covered = {c["script"] for c in SPECIAL_CASES}
    cases = list(SPECIAL_CASES)
    skipped = []
    for script in discover_scripts():
        if script in covered:
            continue
        why = non_gate_reason(script)
        if why:
            skipped.append((script, why))   # 留在宇宙里（--list 可见），但不进电池
            continue
        cases.append(case(script))
    return cases


CASES = build_cases()


# —— R94：无参兜底格普查（TASK-007 自动发现的反面一课）——
# 自动发现给每支未点名脚本补的是一格**无参**跑法。脚本若带不可逆动作（强推共享线、
# reset --hard、开 MR 后 merge），跑守卫电池就等于替所有人跑了它。cef1e9c 上
# whisperer.py 与 fist-pr-automator.py 正是这样进电池的——前者 Step 0 会
# `git push --force HEAD:main HEAD:master` 打两个远端。排除表靠人想起加，
# 所以这条纪律本身要做成判据，而不是只写在注释里。
HAZARD_RE = re.compile(r"reset --hard|--force|\"push\"|/merge\b")


def bare_cells():
    """自动发现会补的无参格 = 宇宙 − SPECIAL_CASES 点名面。"""
    covered = set(c["script"] for c in SPECIAL_CASES)
    return [s for s in discover_scripts() if s not in covered]


def script_texts(names):
    """按名字取脚本正文（blackbox/ 前缀走子目录；读不到的给空串，由普查自行跳过）。"""
    out = {}
    for name in names:
        path = os.path.join(SCRIPTS_DIR, *name.split("/"))
        try:
            with io.open(path, encoding="utf-8", errors="replace") as f:
                out[name] = f.read()
        except IOError:
            out[name] = ""
    return out


def hazard_violations(texts, bare):
    """纯函数普查：texts={脚本名: 正文}，bare=拿无参格的脚本名集合 ⇒ 返回该收口的名字。
    判定面空不许冒绿——调用方给了 bare 名单却一个正文都没读到，返回哨兵名由 selftest 判红。"""
    hit = sorted(n for n in bare if HAZARD_RE.search(texts.get(n, "")))
    return hit


def ci_referred():
    """现读 .github/workflows/*.yml 里引用过的 scripts/*.py（不抄清单）。
    R82：正则从「check_*/gen_plugins/cleanup 白名单」放宽到任意 `scripts/...py` 路径引用——
    CI 里真实引用着 e2e 探针 ×5 / cli_flag_probe / store_isolation_probe / mcp_tool_tour /
    patch_esm_main / run_guards 本身，旧正则全都看不见，这批被误判成缺面。"""
    names = set()
    if not os.path.isdir(WORKFLOWS):
        return names
    for fn in sorted(os.listdir(WORKFLOWS)):
        if not fn.endswith((".yml", ".yaml")):
            continue
        with io.open(os.path.join(WORKFLOWS, fn), encoding="utf-8", errors="replace") as f:
            for m in re.finditer(r"scripts/([A-Za-z0-9_/.-]+\.py)", f.read()):
                names.add(m.group(1))
    return names


# R82（TASK-007）：宇宙从「check_*.py 顶层+blackbox」扩到 **scripts/**/*.py 递归自动扫描**
# ——风语者实测 26 把尺 vs 88 份 .py，漏 64；根因是宇宙定义写死了 check_ 前缀。
# 排除族（测试/一次性/内部辅助，不进宇宙）：
#   `_` 前缀（一次性临时件，如 _run_check_t0r21.py / _tool_registry.py）、
#   `test_` / `verify_` 前缀与 `*_verify.py` / `*_selfdrive*.py`（实验/自驱验证脚本族）。
# 三种执行面（G1 的对象）：CI（.github/workflows 现读）/ 电池（CASES + 自动格）/ 登记（REGISTRY）。
UNIVERSE_EXCLUDE_RE = re.compile(r"(^_|^test_|^verify_|^selfdrive_|_verify\.py$|_selfdrive)")


# R82：登记面——「不该被自动电池跑」的脚本必须在此点名 + why，否则按缺面判红。
# 与 CASES 的分工：CASES 是「要跑的」，REGISTRY 是「在册但不自动跑的」（起服务/需网络/
# 平台前提/一次性补丁/纯辅助库）。点名失效（脚本删了）由 G2 扩展面抓。
REGISTRY = {
    "award_demo.py": "演示脚本（无门禁语义）",
    "blackbox/e2e_assistant_xproc.py": "端到端探针：跨进程起真 assistant，需运行前提，跑法见 scripts/README.md",
    "blackbox/e2e_lock_xproc.py": "端到端探针：跨进程锁竞争，需运行前提，跑法见 scripts/README.md",
    "blackbox/e2e_mirror_install.py": "端到端探针：真下载镜像安装（网络 + 沙箱），跑法见 scripts/README.md",
    "blackbox/e2e_transport_stack_fallback.py": "端到端探针：TLS 换栈真装（网络 + 沙箱），跑法见 scripts/README.md",
    "blackbox/e2e_upgrade_mirror.py": "端到端探针：升级镜像真装（网络 + 沙箱），跑法见 scripts/README.md",
    "blackbox/patch_esm_main.py": "构建辅助：mcp_smoke/demo 启动前幂等注入 require shim（CI 在用，不单独当格跑）",
    "caf_offline_replay.py": "CAF 实验重放（长跑/需语料）",
    "caf_p2c_ab_preflight.py": "CAF A/B 预检（长跑/需语料）",
    "caf_p2d_coldstart_ab.py": "CAF 冷启动 A/B（长跑/需语料）",
    "calibrate_goal_drift.py": "goal_drift 阈值标定（一次性标定，读数已固化入 goal_drift_check）",
    "fist-gate.py": "统一门链（merge_markers/fmt/build/ps_encoding/store_path）：CI/本地单独跑；"
                    "进自动电池会在 fmt 环境差异（本地钉版 vs nightly）上假红",
    "fist-mbt-http.py": "HTTP 服务入口（起服务长跑）",
    "fist-mbt-web.py": "Web 面板入口（起服务长跑）",
    "fist.py": "FIST CLI 主入口（交互/长跑）",
    "fist_mbt_mcp_client.py": "MCP 客户端演示（需 server 活着）",
    "gen_apply_pdf.py": "按需生成器（产出报告 PDF，无门禁语义）",
    "gen_help_docs.py": "按需生成器（产出帮助文档，drift 由 doc_surface 面另判）",
    "issue_scan.py": "MCP issue_scan 的 CLI 辅助入口（能力面由 src/server 白盒锁覆盖）",
    "laya_decide.py": "Laya 决策 CLI（无门禁语义）",
    "mcp_bug_loop.py": "MCP bug 闭环长跑（需 server 活着）",
    "mcp_smoke.py": "MCP 冒烟（需构建产物 + node，CI 由 run_check 面另跑）",
    "ns_route_probe.py": "ns 路由探针（需 server 活着）",
    "output_validate.py": "交付物硬门 CLI（对给定 artifacts 运行，无固定入参；语义由 server 侧白盒锁覆盖）",
    "patch_router_config_caf_field.py": "一次性补丁（patch_ 语义，跑完即退场）",
    "pentad_fist.py": "Pentad 外部项目驱动器（长跑）",
    "score_gate.py": "评分器 CLI（读数型，无门禁语义）",
    "simulate_head_commit.py": "辅助库（check_bug_reference_integrity 引用其 simulate_head_commit，不单独跑）",
}


def guard_files():
    """普查宇宙 = **门禁尺**（discover_scripts 去掉非判据工具）。

    R55：子目录不豁免；TASK-007：全量 .py 而非仅 check_*。本轮（电池只读缺陷）再加一层：
    改码/生成/迁移/宿主类一次性工具**不是判据**，它们进 --list 的「非判据」清单（带理由）
    但不进 G1 的缺面统计——否则 G1 会把"没给一次性工具安排执行面"当成缺陷报红，
    逼着人把 patch_*/gen_* 塞进电池（正是工作树被改动的来源）。
    """
    return [s for s in discover_scripts() if not non_gate_reason(s)]


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
    """「文件系统上有哪些脚本」与 guard_files() 同形：scripts/**/*.py 全集（递归）。"""
    existing = set()
    for dirpath, dirnames, filenames in os.walk(SCRIPTS_DIR):
        dirnames[:] = [d for d in dirnames if d not in ("__pycache__",)]
        rel = os.path.relpath(dirpath, SCRIPTS_DIR).replace(os.sep, "/")
        for f in filenames:
            if f.endswith(".py"):
                existing.add(f if rel == "." else rel + "/" + f)
    return existing


def check_faces(guards, ci_names, case_scripts, missing, existing=None, resident=()):
    """G1/G2/G3 的纯函数版（selftest 喂合成集合，含合成的"文件系统上有哪些脚本"）。
    existing=None 时现读真目录（scripts/**/*.py 递归，与 guard_files 同形）。
    registry=R82 登记面（脚本名集合）：与 CI/电池同权构成执行面。"""
    if not guards:
        return 2, ["FATAL G3：宇宙解析到 0 份脚本 —— 宇宙被换小，拒绝出'无人缺面'的读数"]
    if not ci_names:
        return 2, ["FATAL G3：CI 面一把尺都没解析到 —— workflows 缺失/改名，拒绝出数"]
    if not case_scripts:
        return 2, ["FATAL G3：电池为空 —— 判据空转，拒绝出数"]
    if existing is None:
        existing = _existing_scripts()
    stale = sorted(s for s in case_scripts if s not in existing)
    stale_reg = sorted(s for s in registry if s not in existing)
    if stale:
        return 2, ["FATAL G2：电池点名的脚本不存在：%s" % " ".join(stale)]
    if stale_reg:
        return 2, ["FATAL G2：登记面点名的脚本不存在（脚本删了登记没删）：%s" % " ".join(stale_reg)]
    if missing:
        lines = ["G1 缺执行面 %d 份脚本（CI / 电池 / 登记三面皆无）：" % len(missing)]
        for g in missing:
            lines.append("  - %s ⇒ 挂进 CI、进本电池 CASES，或在 REGISTRY 点名+why，别留'写了就没人跑'" % g)
        return 1, lines
    line = ("G1 通过：%d 把尺全部有执行面（CI %d / 电池 %d）"
            % (len(guards), len(ci_names & set(guards)), len(case_scripts & set(guards))))
    if resident:
        line += "；常驻服务 %d 把不裸跑（serve_forever，逐条点名）：%s" % (len(resident), " ".join(resident))
    return 0, [line]


def face_report():
    ci = ci_referred()
    battery = {c["script"] for c in CASES}
    guards_all = guard_files()
    # 常驻服务：只有「没有手写有界格子」的那些才豁免；一旦有人给它补了带旗标的一格，
    # 它就回到宇宙里当尺使（豁免是形状豁免，不是身份豁免）。
    resident = sorted(g for g in guards_all if g not in battery and is_resident(g))
    rset = set(resident)
    guards = [g for g in guards_all if g not in rset]
    missing = [g for g in guards if g not in ci and g not in battery]
    rows = [(g, "CI" if g in ci else "-", "电池" if g in battery else "-") for g in guards]
    return rows, missing, ci, battery, guards, resident


CASE_TIMEOUT_SEC = 600


def run_battery(case_timeout=CASE_TIMEOUT_SEC):
    rows, missing, ci, battery, guards, resident = face_report()
    rc, lines = check_faces(guards, ci, battery, missing, resident=resident)
    for l in lines:
        print(l)
    if rc == 2:
        return 2
    cases_all = CASES + auto_cases(battery, ci, guards)
    if len(cases_all) > len(CASES):
        print("\n（R82 自动补格 %d：宇宙里新落的无 CI 面静态尺，见 auto_cases）"
              % (len(cases_all) - len(CASES)))
    print("\n=== 电池 %d 格 ===" % len(cases_all))
    py = sys.executable
    fails, skips = [], []
    for c in CASES:
        # BUG-368：前置既可能是文件（temp/*.json）也可能是目录（temp/ 树态）⇒ 用 exists
        miss = [n for n in c["needs"] if not os.path.exists(os.path.join(ROOT, n))]
        if miss:
            skips.append((c["name"], "缺前置 " + " ".join(miss)))
            print("SKIP  %-56s %s" % (c["name"], "缺前置 " + " ".join(miss)))
            continue
        tmo = c.get("timeout") or case_timeout
        try:
            p = subprocess.run([py, os.path.join(SCRIPTS_DIR, c["script"])] + c["argv"],
                               capture_output=True, text=True, encoding="utf-8",
                               errors="replace", cwd=ROOT, timeout=tmo)
        except subprocess.TimeoutExpired:
            # R98：尺子不结束不等于判据红，更不等于可以整轮挂着——限时判红并点名，
            # 否则下一位跑电池的人只会看到"没输出"（本仓空转即自拒的同一口径）。
            fails.append((c["name"], "TIMEOUT", c["expect"], c["why"],
                          "限时 %ds 未结束" % tmo))
            print("TIMEOUT %-56s 限时 %ds 未结束（尺子不结束 ⇒ 判红点名）" % (c["name"], tmo))
            continue
        out = ((p.stdout or "") + ("\n" + p.stderr if p.stderr else "")).strip().splitlines()
        tail = out[-1][:120] if out else ""
        ok = p.returncode == c["expect"]
        tag = {"gate": "OK", "diag": "诊断", "known-red": "预存红"}[c["kind"]]
        print("rc=%-2s exp=%-2s %-56s %s %s" % (p.returncode, c["expect"], c["name"], tag, tail))
        if not ok:
            fails.append((c["name"], p.returncode, c["expect"], c["why"], tail))
    print("\n=== 汇总 ===")
    print("格数 %d（手写 %d + 自动 %d）/ 失败 %d / SKIP %d / 缺执行面 %d"
          % (len(cases_all), len(CASES), len(cases_all) - len(CASES),
             len(fails), len(skips), len(missing)))
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
    rows0, missing0, ci0, battery0, guards0, resident0 = face_report()
    cell("g2-not-false-stale-on-blackbox",
         check_faces(guards0, ci0, battery0, missing0, resident=resident0)[0] != 2, True)
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
    cell("non-gate-never-becomes-case",
         non_gate_reason("patch_router_config_caf_field.py") != ""
         and all(not non_gate_reason(c["script"]) for c in CASES), True)
    cell("gen-plugins-still-gate", non_gate_reason("gen_plugins.py"), "")
    cell("repo-current-has-no-orphan-guard", check_faces(guards, ci, battery, missing)[0], 0)
    cell("battery-covers-plan-landing", "check_plan_landing.py" in battery, True)
    # 6) R98 本体：常驻服务型脚本（自己不会结束）既不能被裸跑进电池，也不能悄悄从宇宙里消失
    cell("resident-src-flags-serve-forever",
         is_resident_src("def main():\n    server.serve_forever()\n"), True)
    cell("resident-src-flags-run-forever", is_resident_src("    app.run_forever()\n"), True)
    cell("resident-src-clean-guard-not-flagged", is_resident_src("print('ok')\n"), False)
    cell("resident-face-is-named-not-silent", len(resident) > 0, True)
    cell("battery-has-no-bare-resident-case",
         any(c["script"] in set(resident) and not c["argv"] for c in CASES), False)
    cell("g1-still-red-for-real-orphan-with-resident-exempt",
         check_faces(guards + ["check_orphan.py"], ci, battery, missing + ["check_orphan.py"],
                     resident=resident)[0], 1)
    print("  ok  现状读数：%d 把尺 / CI 面 %d / 电池面 %d / 缺面 %d / 常驻豁免 %d"
          % (len(guards), len(ci & set(guards)), len(battery & set(guards)), len(missing),
             len(resident)))

    bad = [(nm, why) for nm, ok, why in cells if not ok]
    if bad:
        print("SELFTEST FAIL：")
        for nm, why in bad:
            print("  - %s：%s" % (nm, why))
        return 1
    print("SELFTEST OK（%d 格：宇宙覆盖 blackbox 真尺 + G2 不误判其 stale / G1 抓 blackbox 孤儿 + 带前缀点名 / G1 干净 / G1 抓漏面尺 + 必点名 / G3 三种空宇宙各自拒 / "
          "G2 电池点了不存在的脚本自拒 / 真源现状全绿 / plan_landing 已进电池 / "
          "plan_landing 门禁格与诊断格并存且诊断格 why 带构成 / "
          "常驻分类器咬 serve_forever 与 run_forever 且不误咬干净尺 / 常驻面逐条点名不静默 / "
          "电池里没有裸跑的常驻格 / 有常驻豁免时真孤儿仍判红）" % len(cells))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--list", action="store_true", help="只打覆盖表，不跑")
    ap.add_argument("--case-timeout", type=int, default=CASE_TIMEOUT_SEC,
                    help="单格限时（秒）：尺子不结束就判红点名，不许挂住整轮")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if args.list:
        rows, missing, ci, battery, guards, resident = face_report()
        for g, a, b in rows:
            print("%-42s CI=%-3s 电池=%-3s" % (g, a, b))
        print("\n尺 %d 把 / CI 面 %d / 电池面 %d / 缺执行面 %d"
              % (len(rows), len(ci & set(guards)), len(battery & set(guards)), len(missing)))
        nong = [(s, non_gate_reason(s)) for s in discover_scripts() if non_gate_reason(s)]
        print("非判据工具 %d 个（留在宇宙可见、不进电池——电池只读，改码/生成/宿主类工具不在判据面）" % len(nong))
        for s, why in nong[:60]:
            print("  非判据 %-42s %s" % (s, why))
        if missing:
            print("缺面清单：" + " ".join(missing))
            return 1
        return 0
    return run_battery(args.case_timeout)


if __name__ == "__main__":
    sys.exit(main())
