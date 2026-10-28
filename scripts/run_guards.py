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
  python scripts/run_guards.py              # 跑全量，逐格先打判定列（PASS/FAIL）再打 rc/期望/口径/尾行
  python scripts/run_guards.py --list       # 只打覆盖表（尺 × CI × 电池）
  python scripts/run_guards.py --selftest   # 合成夹具自证 G1/G2/G3
退出码：0=无失败（允许 SKIP 与预存红按期望命中）/ 1=有格越期望或有尺无人跑 / 2=电池自拒。
"""
import argparse
import inspect
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
# 自锁（R105 同款机理）：本文件自己就在递归宇宙里，电池里放一格「跑电池」= 无限套娃。
SELF = os.path.basename(os.path.abspath(__file__))
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


def tolerant(script, allow, why, *args, kind="diag"):
    """**树态诊断格**：允许若干个"都算正确读数"的 rc（如 0 与 1），且照实打印真实 rc。

    为什么需要它（R49 实测）：`cleanup_artifacts.py --check` 的 rc 反映**工作树脏不脏**，
    不是代码健康：隔离树/空 `temp/` 读 0，`temp/` 有残留或脚本区有 `_` 临时文件读 1。
    原先写死 `expect=1` ⇒ 干净 worktree 里电池**恒 FAIL**（假红）；写死 0 又在真脏树里假绿。
    试过"按 temp/ 是否存在算期望"，两侧实测都不成立（空 `temp/` 目录仍然 CLEAN）——
    判据与脚本看的不是同一个条件，猜状态只会换一种假红。所以此格只报读数、不判健康：
    rc ∈ allow 即通过，`诊断` 标签 + 末尾读数照实打印，人一眼能看到"这次读到几"。
    """
    c = expected(script, allow[0], why, *args, kind=kind)
    c["allow"] = tuple(allow)
    return c


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
    # R59：memory 日志失控闸。只跑 --selftest（真日志可能极大，不在这里全量读）。
    case("check_memory_log_size.py", "--selftest"),
    case("check_tools_sync.py"),
    # 2026-10-25：CLI 入口 `fist.py list-tools` 的计数 ↔ 真源对表。
    # 为什么单立一格：六支文档守卫全部走 `_tool_registry.real_tools()`（读 170）⇒ 永远绿，
    # 而 `fist.py list-tools` 曾自写正则只扫 server.mbt 一个文件、且 `[a-z_]+` 不认点号 ⇒ 只报 152。
    # 守卫绿、入口少 18，用户面看不见（判例-16 家族）。全量跑 + --selftest 两格并存。
    case("check_fist_list_tools_sync.py"),
    case("check_fist_list_tools_sync.py", "--selftest"),
    # —— R106 预存红登记（电池自 770478c1 起跑不起来，这几格的红从没被任何人读到过）：
    #    照写读数 + 成因，不动被检内容。被检内容修好后 got≠expect 当场现形，逼下一位改的人
    #    把期望改回 0——这是本文件自订的律，不是给红脸上色。 ——
    # R106 追记（叠 b465915f 后自查改判）：`check_doc_surface` 那格 J4 的红**不是预存红，是我自己喂的**
    # ——我在 README 抄本④里写「第二处发布版本自述 0.3.9」这类**带版本字面量的说明句**，30 份抄本就把它
    # 放大成 30 处，J4 数的是"README 里出现了几处版本自述"。同基线举证（把 main 的 README 摆回来跑同一尺）
    # 实测 rc=0 ⇒ 成因在我这边，不在主线。已把说明句改成不带版本字面量的写法，两面期望按现读改回 0。
    # 与 `check_scripts_index` 那次「文档写进被检文件名」是同一族：**登记红面的文字本身就是被检面**。
    case("check_doc_surface.py"),
    case("check_doc_surface.py", "--selftest"),
    # —— R126：副机认领入口（docs/2026-10-20-slave-tasks.md）的自证尺。裸跑判「证据锚点指不指
    #    得到真源 + 文首计数自述对不对」，--selftest 判「这把尺能不能发红」（24 格合成树：2026-10-28 补
    #    D4 文件级自述落后 2 格 + B6 整份文件无记号 2 格，其中 B6b 是抗漂移的**反向对照**）。
    #    手写点名两格而不靠自动补格：自动补格只补裸跑，自检格必须点名（本文件既有纪律）。
    case("check_slave_task_list.py"),
    case("check_slave_task_list.py", "--selftest"),
    case("check_mbti_sync.py"),
    case("check_mbti_sync.py", "--selftest"),
    # —— R12：「两面」漂移普查判据（形态 ①②③）——
    # 本仓 6 天内因同一根因踩了 5 次（BUG-420/425、R10 内存vs SQLite、R10 SQL 谓词、BUG-435 抄本）。
    # **覆盖面 3/5**：④消费面的前提、⑤胶水的语义 不在覆盖面内（需人工判据）——
    # 判据自己是运行时输出覆盖率声明的，PASS **不代表无两面**。
    # 自证格含 2 个变异对照（抄本改坏 1 字符 / `<`改`<=`）+ 空扫描自拒 + 覆盖率必须在输出里。
    case("check_two_faces.py", "--selftest"),
    case("check_two_faces.py"),
    # —— R63：空扫描面元判据 —— 喂空目录给每把支持 `--root` 的尺，判它会不会「空转出绿」。
    #    判例-32 同族但更靠前一步：判据最危险的失效不是报错，而是**什么都没扫到却报绿**。
    case("check_empty_scan_face.py"),
    case("check_empty_scan_face.py", "--selftest"),
    # —— R64/R66：参数面元判据 —— 未知旗标必须被拒绝（拼错 `--selftest` 会静默跑真检查并报绿）。
    #    【债已还完】R64 实测 27 把中招 ⇒ R65 还 12 把（单旗标）⇒ R66 还 15 把（多旗标/模块级），
    #    现读 **0 把**（75/75 全部拒绝未知旗标）。按本仓律「被检面修到 0 ⇒ 把期望改回门禁格」。
    case("check_arg_face_strict.py"),
    case("check_arg_face_strict.py", "--selftest"),
    # —— R82/R94：Python 侧死参数判据 —— `check_dead_params.py` 只扫 .mbt，Python 形参此前从未被查过。
    #    【债已清零】R82 建判据（36 条）⇒ R85 加两面口径（真债 12 / NOTE 19）⇒ R86–R94 逐条清完，
    #    现读 **真债 0 条**（1771 个函数）。按本仓律「被检面修到 0 ⇒ 把期望改回门禁格」。
    case("check_dead_params_py.py"),    case("check_dead_params_py.py", "--selftest"),
    # —— BUG-440：docs/plans/ frontmatter 守卫（README:22 承诺了 5 天，守卫文件此前不存在）——
    # 判据：文件名 / frontmatter 必须第 1 行起 / 四强制字段 / status 闭集 / 已定案自洽(含 decisions 记录)。
    # 实测抓出过真违例：4pools 提案的第一个 `---` 块是 AIGC 水印元数据，四字段全缺。
    # 自证 16 格含 3 个变异对照（删字段 / AIGC 伪 frontmatter / 已定案缺 decisions 记录）+ 空扫描自拒。
    case("check_plan_location.py", "--selftest"),
    case("check_plan_location.py"),
    # —— BUG-455：MCP 工具「外壳 + 实现两层」覆盖判据 ——
    # 核心洞察：零覆盖的危害不是「实现没测」，而是「外壳与实现之间那根线没测」。
    # 本会话 3 次实证：BUG-440/453/436 都是「实现层测试全绿、工具照样是坏的」。
    # 判法：A 外壳面（工具名在测试里）**或** B 实现面（映射函数在测试里）；
    #       ⚠️ B 不能替代 A —— execute 底层有测试，但「challenge 参数有没有接上」只有外壳面测得出。
    # 白名单 IMPL_MAP 而非启发式（实测启发式假阳性 13/30）。
    # rc: 0 全有外壳覆盖 / 1 有零覆盖 / 2 无法自证。--selftest 10 格含 1 变异对照。
    # —— R119：登记理由里的**数字**必须与实测一致（R117/R118 连续两轮漂移，机器对表）
    # —— R135：文档引用的**文件路径必须真实存在**（R134 抓出一份从未存在的白盒锁后立尺）
    case("check_doc_paths.py"),
    case("check_registration_numbers.py"),
    case("check_tool_coverage.py", "--selftest"),
    # —— BUG-465：无效 catch 判据（`catch` 对 FFI 抛出的 JS 异常无效）——
    # 语言层边界：MoonBit 的 catch/try·catch 只包 raise 效果；
    # daqing/sqlite / node:sqlite 的函数**无 raise 标注**，抛的是 JS 运行时异常 ⇒ 拦不住。
    # 判法用编译器算好的 `unused_try` 警告（不自己写正则：那要类型信息）。
    # 覆盖面诚实：只判「编译器能证明」的，PASS 不代表「没有无效 catch」。
    case("check_effective_catch.py", "--selftest"),
    # -- BUG-468 R2: handwritten Ed25519 seed judge --
    # Alpha: this lane only removed the manual act; nothing stops a newcomer doing it again.
    # Three-layer rule: (1) shape is a byte literal (2) length in {32,64} -- the only legal Ed25519 seed length is 32
    # (3) the same file mentions ed25519 or seed.
    # Calibrated by full-repo survey: bare byte-literal search => 13 hits, ALL false positives;
    # 16/64-byte-only => 0 hits, misses everything; length!=32 => 1 hit and that one is hex data.
    # The three-layer rule found 12 real seeds with 0 false positives.
    # Intentional leftovers live in INTENTIONAL, registered ONE BY ONE WITH A REASON.
    case("check_handwritten_seed.py", "--selftest"),
    # -- BUG-474: dead-parameter judge (schema promises a param the handler never reads) --
    # Same family as BUG-472 (plan.challenge) and BUG-473 (execute.agent): the caller
    # passes a value that is silently discarded, with NO error surfaced.
    # Encodes the FIVE pitfalls found the hard way; each has a selftest mutation cell:
    #   1 dict setdefault overwrote same-name tools -> under-report (blocks is a list)
    #   2 substring match hit agent_touch_first_seen( -> false-alive (quoted literal only)
    #   3 paren matching did not skip strings -> block closed early -> false-dead (state machine)
    #   4 passthrough foo(args)/engine.y(args) -> false-dead -> reported as opaque, never dead
    #   5 reader whitelist incomplete (jnum/get_json_text/jget/arg_str) -> derived from fn defs
    # ⚠️ 2026-10-28 Lane DB：本格曾是 expected(..., 1) 的 known-red（当时 3 处死参数：
    #   loop_create.items + lock_acquire.ts / lock_renew.ts）。
    #   两个 ts 已由 BUG-33 政策归入「设计如此」（判据按 schema 描述里的「服务端覆盖」识别），
    #   items 也已处理 ⇒ 判据实测 rc=0（死参数 0 / 设计如此 2 / opaque 4）。
    #   known-red 的到期条件就是「修好会变红」，所以改回 case(rc=0)：谁再埋一个死参数就红。
    case("check_dead_params.py"),
    case("check_dead_params.py", "--selftest"),
    case("check_handwritten_seed.py"),
    case("check_effective_catch.py"),
    # 判据本体（2026-10-28 转正门禁）：本格曾是 expected(..., 1) 的 known-red，
    #   当时 22/154 个工具从无任何测试碰过接线面（BUG-455）。同日各 lane 补齐后
    #   判据实测 rc=0（外壳零覆盖 0/154）——known-red 的到期条件就是「修好会变红」，
    #   所以本笔改回 expect 0：待办清单清零，它才有资格当门（谁删测试谁红）。
    #   ⚠️ 100% 只代表「每个工具名在测试文本里出现过」，不代表接线是对的 ——
    #   判据自述：`只判「有没有测试」，不判测试好不好`。
    case("check_tool_coverage.py"),
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
    # —— R141/R155 落仓的两支工具面带自检：render_dsh_patch（模板→本机渲染，
    #    selftest 6 格）、run_light_wt（轻量 worktree 生命周期，selftest 10 格）。
    #    二者落仓时只登记进 scripts/README.md，未接任何执行面 ⇒ run_guards G1 现读
    #    「缺面清单」点名；此处按本文件纪律手写点名自检格（非 check_* 亦须有面）。 ——
    case("render_dsh_patch.py", "--selftest"),
    case("run_light_wt.py", "--selftest"),
    # —— R3（BUG-389(2) 收口）：check_direct_push 是 pre-push 钩子的判定本体，**裸跑格必须禁**——
    #    它从 stdin 读 git 的 pre-push ref 行，电池环境（capture_output 不给 stdin）会挂在管道上
    #    空转到 timeout（R98 口径：尺子不结束不是判据红，是空转）。手写点名 --selftest 后
    #    covered 按脚本名去重，自动发现不再补裸跑格。check_push_guard 裸跑是只读全量判据
    #    （跟踪面 + 本地子进程语义矩阵），自动格即可，与自检格并存。 ——
    case("check_direct_push.py", "--selftest"),
    # —— R106 追记（叠 gitcode/master b465915f 之后现读）：下面三格原来的 expected 非 0 已被主线
    #    修好（账本撞号收敛 + `scripts/merge-prompt.txt` 出跟踪面），got 0 ≠ expect 当场现形 ⇒
    #    按本文件自订的律「预存红被修好 ⇒ 把期望改回 0」转回门禁格。 ——
    case("check_plugin_sync.py"),
    case("gen_plugins.py", "--check"),
    case("gen_plugins.py", "--selftest"),
    case("check_upgrade_installer.py"),
    case("check_plan_landing.py", "--selftest"),
    # —— R84 (TASK-003)：gate 步骤位置纪律 ——
    # 【债已还完】（R185 登记 → R56 还债）：R185 时的「35 条 > 上限 34」已修 —— 给 5 个**确实依赖
    # Migrate** 的步骤补了 position-why 锚点（Cleanliness guard / Heartbeat xproc / Reserve xproc /
    # Native heap gate ×2 / Test (native, j=1)），实测 **30 ≤ 34** ⇒ 判据 rc=0。
    # 按本文件的律「被检内容修好 ⇒ 把期望改回门禁格」，从 known-red 转回 case。
    # **没动 `POSITION_WHY_CEILING`**（上限仍是 34）—— 降的是实测面，不是闸门。
    case("check_ci_step_position.py"),
    case("check_ci_step_position.py", "--selftest"),
    # —— 远端状态读数（2026-10-24）：这两格红的是**远端形态**，不是仓内容债 ——
    # filter-repo 重写历史后，多数通道支与当前 `gitcode/main` 已**无共同祖先**（`git merge`
    # 会拒绝 unrelated histories）⇒ 合并面只能走 cherry-pick（本会话全程即如此）。这不是缺陷
    # 而是要如实点名的合并形态；按 diag 口径把当轮真读数钉住，数字漂移就现形。
    expected("check_branch_ancestry.py", 1,
             "诊断口径：filter-repo 重写后 196 支与 gitcode/main 无共同祖先（merge 拒绝 unrelated "
             "histories）⇒ 合并只能 cherry-pick；本地临时支（test/ work/）已清，剩余为远端通道支",
             kind="diag"),
    # 2026-10-24 追记：`check_diff_scope.pick_base()` 改用「离 HEAD 最近的候选」后，本尺的
    # base 也稳定落到 main ⇒ 「master 落后 1113 提交」那个读数不再出现，实测 **0 个分支有未推送提交**
    # （rc=0）。按本文件自订的律「预存红被修好 ⇒ 把期望改回 0」转回门禁格。
    case("check_delivery_gap.py"),
    # —— R55：blackbox 尺进宇宙也进电池（相对 scripts/ 点名，路径含子目录）——
    case("blackbox/check_merge_markers.py", "--selftest"),
    # —— R179：gitlink(mode 160000) 门（瘦身组报「51 个已注册 worktree = 51 颗雷」）——
    # 两格：① 判据自身 19 格自证（纯函数识别核 + 临时仓端到端：造雷必拦 / 修复命令真能修好 /
    # 护栏装上后 `git add -A` 不再造雷 / 非 git 目录自拒 2）；② **钩子端到端** 9 格——
    # 把真 `.githooks/pre-commit` 拷进临时仓、`core.hooksPath` 指过去，跑真 `git commit`，
    # 证明「gitlink 提交被拒且 HEAD 不动」+「合法提交放行且 HEAD 前进」。
    # ② 存在的理由：钩子写了不等于接上了（`core.hooksPath` 曾长期为空）。它自带 `--selftest`
    # 参数（缺省行为即自证），所以可以直接进电池；夹具全程 `isolated_git_env()`。
    case("check_index_gitlinks.py", "--selftest"),
    case("blackbox/e2e_precommit_gitlink_gate.py", "--selftest"),
    # —— R180：master 镜像判据（同一个「对齐 master」动作人工做了 5 次，治本是立一条命令）——
    # `gitcode/master` 是默认分支镜像，**没有任何自动化维护它**（实测 workflows 里
    # `refs/heads/master` 零命中）⇒ main 一推进它就落后，只看默认分支的人读到的都是旧基线。
    # 本尺判据模式只读；`--apply` 才推，且**只快进**（`merge-base --is-ancestor` 不成立即
    # refuse），**不支持 force**（给 `--force` 直接 rc=1 拒绝）。
    # 电池只跑 `--selftest`：纯函数四态 + 临时裸远端端到端（含「分叉必拒」「dry-run 不推」
    # 两条硬线格），零网络、零写盘、夹具全程 `isolated_git_env()`。
    case("check_master_mirror.py", "--selftest"),
    # —— R182：打包产物「真能跑」判据（BUG-405 / 外部项目 Pentad 报的阻断性 bug）——
    # `package.json` 是 `"type": "module"`，而上游 `daqing/sqlite` 的 JS FFI 用 CJS
    # `require("node:sqlite")` ⇒ ESM 作用域 ReferenceError，`doctor`/`version`/`serve` 全崩。
    # **`moon check` 全绿、`moon build` 也全绿** —— 源码没问题，坏的是产物；
    # 本仓此前**没有任何一格执行过 bundle**。电池只跑 `--selftest`（造好/坏 bundle 各跑一遍）：
    # 真产物档要先 build + patch，太慢且依赖构建态，由 CI 在构建之后调。
    case("check_esm_bundle_runnable.py", "--selftest"),
    # —— R187：判据变异探针（把本会话踩过两次的坑固化成工具）——
    # `scripts/_mutation_probe.py` 是**独立工具**（`--selftest` / `--func` 可命令行跑），
    # 不是「被导入的共享模块」⇒ **不借用 `("_", "内部共享模块")` 那条豁免**，给显式执行面。
    # 它验的事：对判据施语义级变异（S1 `==0→!=0` / S3 `return 0→1` / S4 `if not x→if x`），
    # 跑它的 `--selftest`，并按**三重判定**归类 —— 关键在于 `CRASHED` 这一档：
    # 本会话两次把「脚本没跑起来」（import 崩 / 类型不匹配崩）读成「判据咬住了」，
    # 那一档就是为挡这两个误判而立的（判例-50 / 判例-62）。
    # 电池只跑 `--selftest`（纯函数 + 变异对照 14 格，零外部依赖）。
    case("_mutation_probe.py", "--selftest"),
    # —— R181：worktree 三条件只读判据（诊断尺，「可删」≠「该删」）——
    # 司令-α 实测：11 个禁删 worktree **26 分钟内 4 项变可删** ⇒ 「不可删」不是固有属性，
    # 而是某一时刻的读数；拿旧快照决定删/留必漏。本尺每条随时可跑、一律现读。
    # 它是**诊断尺**：rc=1 表示「发现 N 个可删项，请人看一眼」，不是门禁失败 ⇒ 用 tolerant，
    # 0（无可删）与 1（有可删）都是正确读数；写死 expect 会在另一种树上假红/假绿。
    # **本脚本没有任何删除路径**——只报读数，删除由人/架构决定。
    tolerant("check_worktree_hygiene.py", (0, 1),
             "诊断口径：rc=1 = 发现可删 worktree（≠ 该删），rc=0 = 全部至少不满足一条；"
             "两者都是正确读数，取决于当时工作树脏不脏。判据只读不删",
             kind="diag"),
    # R106 曾登记预存红：主线把某 agent 的 git worktree 以 gitlink(mode 160000) 提交进跟踪面
    # （`.agents/worktrees/fix/display-rank-boundary`，`4a7bf82a` 带入）⇒ 判据读不到正文，L1 后 rc=1。
    # R116 收口：`git rm --cached` 删该条目 + `.gitignore` 忽略 `.agents/worktrees/`，期望按预存红律改回 0。
    case("blackbox/check_merge_markers.py"),
    # —— 诊断型：退出码语义不是门禁，把当轮真读数钉成期望值（数字变了就现形）——
    expected("check_plan_landing.py", 1,
             "诊断口径：判定面 25 条活文档点名落点未落地（BUG-367 A/B/C 三档留裁决）；另有搬家态 3 条单列"
             "（P5，不判红）、存档面 17 条只报不判。读出 0 算这格漂移；判据空转自 R41 起给真 rc=2"
             "（改前 SystemExit(str) 只给 1，那个 2 是幻影 ⇒ BUG-369）",
             kind="diag"),
    case("check_ps_encoding.py"),
    # —— R82：scripts_index 那格按本文件自订的律改记预存红——master 现状 red 的根因是主机
    #    fist-gate.py（454aea3）未在 scripts/README.md 登记（TASK-003/004 施工面，R81 点名）。
    #    主机一登记，got 0 ≠ expect 1 当场现形，逼着把期望改回 0。 ——
    #    R106 追记：这一形**兑现了**——主机把 `scripts/merge-prompt.txt` 从跟踪面删掉（b465915f 系），
    #    现读 got=0 ⇒ 按那条律把期望从 1 改回 0，转回门禁格。
    case("check_scripts_index.py"),
    # —— R136：索引文件的「同名登记块只许一条」尺。R48 立尺后只有电池的自动无参格在跑它
    #    （长度门槛把短副本全滤掉），7 份快照叠出 38 个重名 / 232 块冗余时它仍报「无重复长条目」；
    #    --selftest 与 CI 面都没有它。现按块判（含续行、无门槛），裸跑只读，--selftest 21 格真断言。 ——
    case("check_doc_dup.py"),
    case("check_doc_dup.py", "--selftest"),
    # —— 编码面：R58 期望值回归 0——BUG-355/332 一族已在主仓修完（现读真源：--selftest 绿、
    #    --all 面「该带闸 85 份/已带 85 份」全过）。按本文件自订的律「预存红被修好 ⇒ 下一次
    #    改动的人把期望改回 0，数字变了不改进期望就现形」，此处正是那一次改动。
    #    注：cleanup_artifacts 那格的 expect=1 是**工作树脏**（运行态）而非内容态，隔离树里
    #    读到 0 属环境差异，不改期望（改了会在真脏的共享树反向假绿），留给读数自行说明。 ——
    case("check_py_stdout_encoding.py", "--selftest"),
    case("check_py_stdout_encoding.py", "--all"),
    # —— 依赖临时件的 case：缺前置 ⇒ SKIP 并点名 ——
    # R25（判例-25/33）：两把吃**同一份** `temp/pt27.log` 快照的尺。
    # 旧形状里快照停在 1455、README 也 1455 ⇒ 一致 ⇒ PASS，而现状 1457 ⇒ **判据在说谎**。
    # 现在两把尺都先验 `<快照>.src` 源码面锚点：缺失/过期 ⇒ rc=2（诚实沉默），
    # 于是电池里这两格在本机快照过期时是红的——**红着是诚实的**。
    # `--fresh` 让判据判前真跑一次全仓（实测约 7~9 分钟，一次覆盖整轮电池），跑完重写快照+锚点
    # ⇒ 电池里跑就是真绿或真红，不靠「谁记得手跑一下」。
    # 逃生口 `FIST_BADGE_FRESH=0`：跳过 fresh ⇒ 本格 SKIP，且 SKIP 理由必须写清
    # **跳过了什么能力的证明**（判例-33：不带说明的 SKIP 在汇总里会被读成「这格没问题」）。
    gated("check_badge.py", TESTLOG, TESTLOG, "README.md", "--fresh"),
    gated("check_test_sync.py", TESTLOG, TESTLOG, "--fresh"),
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
    # —— 风语者（TASK-009 / R86）：宇宙并成全集后这两把尺第一次进了账，于是「它有面吗」必须被
    #    回答而不是被跳过。--selftest 离线自证（本机实测 rc=0），故手写点名进电池；裸跑会走
    #    --auto-merge / 写任务池，那是不可逆面，不在判据面里。
    case("whisperer.py", "--selftest"),
    case("whisperer_patrol.py", "--selftest"),
    # ── R118：`audit_branch_delete.py`（分支删除硬门）落仓时漏接线——`run_guards --list` 现读
    #    「缺面清单：audit_branch_delete.py」，它连带 check_battery_count_doc / selftest-inventory
    #    两格一起红。本脚本裸跑要分支参数且会写 <git-dir>/fist/delete-audit.jsonl，只有 --selftest
    #    是只读面（temp 仓自建自清），故手写点名自检格。──
    # —— R54：`moon test` 的环境垫片问题（BUG-380）。**只跑 --selftest**——
    #    真跑全仓测试要 11s 且会起一堆 node 进程，电池必须只读且快。 ——
    case("moon_test_env.py", "--selftest"),
    # ── R125：常驻入口的 moon 子进程统一带 shim（moonc `\\?\` ICE，与 R124 同族第二面）。
    #    裸跑=静态普查 scripts/*.py 的 spawn 面是否接入 moon_env()，只读且快。 ──
    case("moon_env_probe.py"),
    case("moon_env_probe.py", "--selftest"),
    # —— R55：`moon fmt --check` 的可判性闸（BUG-388）。**必须显式只跑 --selftest**：
    #    裸跑在本机恒 DEGRADED(2)，自动补格会把它当红；本表点名后自动格就不再裸跑。 ——
    # —— R57：合并丢行探测。只跑 --selftest（合成仓库造丢行）；真跑要读真 merge 历史。 ——
    case("check_merge_loss.py", "--selftest"),
    # —— R153：自检 hermetic 守卫（把 R151 那条口径「`--selftest` 只许合成夹具」做成常驻判据）。
    #    --selftest 在 temp 里造被检脚本，属只读快格 ⇒ 门禁格；裸跑要扫真仓 scripts/ 全树（递归，含
    #    blackbox/），现读红档 72 处（W=10 / R=48 / G=14，分布在 24 把尺）+ 记账档 5 处（T=4 落约定
    #    temp/、S=1 自 spawn）；立尺这一单不代修那 72 条，按本文件的律「预存红照写期望值 + 依据」登记，
    #    被检面修到 0 之后这一格自己翻红，逼下一位把期望改回 0。 ——
    case("check_selftest_hermetic.py", "--selftest"),
    expected("check_selftest_hermetic.py", 1,
             "R153 立尺；**R117 按实测重写读数**：红档 **90 处 = W 1 / R 61 / G 28**，另记账 10（S 3 / T 7），涉 37 个文件。"
             "（原登记「72 处 / W=10 / R=48 / G=14」已两次过时：R111/R114/R115/R118 还掉写面与误分类，同时期新增读面；**这条 why 每次读数变化都要同批改**——机器对表见 R118 日志的后续单。）"
             "**三档语义不同，别混成一个数字**：W=写探针进真树（**真污染，仅剩 1 处**）；R=读仓库现状面、G=打真仓跑 git —— 这两种**多是集成断言的必要代价**"
             "（例：check_release_asset_names 的 13 处在验「本仓现状必须通过」，换合成夹具就丢掉这条性质）。棘轮只许下降；新增没有该性质的自检不许再涨。"),
    case("check_fmt_gate.py", "--selftest"),
    case("audit_branch_delete.py", "--selftest"),
    # —— R55：`moon fmt --check` 的可判性闸（BUG-381）。只跑 --selftest：
    #    真跑要起 moon 进程，且本机恒 DEGRADED ⇒ 不进电池的判据面。 ——
    case("check_fmt_gate.py", "--selftest"),
    # —— R106：宇宙并成全集后 `--list` 第一次把这三把尺的**现读红**摆出来。按本文件的律，
    #    预存红「照写期望值 + 依据」而不是豁免：被检内容修好之后这一格自己会翻红，逼下一位
    #    改动的人把期望改回 0（数字变了不改进期望就现形）。这里只登记读数，不动被检脚本。
    # ── R110：TASK-001 台账整块重复是本轮手工去重修掉的，「手工」不留常驻面就会长回来 ──
    #    裸跑现读 rc=0（23 份台账 / 违例 0 / 诊断 1），故直接进门禁格；--selftest 也进，
    #    因为 C9 真面变异格是「再有人抄一份」的唯一机器读数。
    case("check_backlog_yaml_integrity.py"),
    case("check_backlog_yaml_integrity.py", "--selftest"),
    # ── R133：2026-10-22 日志被整文件自我追加放大到 91MB / 25770 块仅 56 唯一 ──
    #    手工去重不留机器面就会长回来；去重后裸跑 rc=0，--selftest 8 格含 --fix 无损对照。
    case("check_memory_log_dedupe.py"),
    case("check_memory_log_dedupe.py", "--selftest"),
    # ── 兑现（R117）：R111 那一单把 9 条落差逐条核过转 in_review/done，并把尺内棘轮降到 0；
    #    现读 `扫描面=gitcode/main | 落差 0 条 / 上限 0 条` ⇒ 登记的那条红已不成立。
    #    按本文件自订的律「被检内容修好 ⇒ 把期望改回 0」，转回门禁格，依据一起删。
    case("check_backlog_status_staleness.py"),
    # 【这是债，不是判据坏了】（R185 登记，理由按统帅要求写全）
    # 判据工作正常：它如实数出 N1/N2 命名债仍在棘轮上限之上。红的含义是「命名债没还完」。
    # 出路：把 N1/N2 真正降到上限内（改名 + 同批下调上限）；禁止为了变绿去改上限常量。
    expected("check_scripts_naming.py", 1,
             "预存红（债非坏）：现读 2 条命名判定面 > 棘轮上限（N1 无角色名 + N2 连字符名，"
             "见 scripts/NAMING.md）。**判据工作正常，它正确报告了命名债**——不是判据算错。" "出路：改名还债并同批下调上限；禁止为变绿改常量（放宽是人的决定）。"
             "⚠️ **改名范围本身是 owner 裁决项，别自作主张动手**：NAMING.md 实测全仓改 46 份 =" "1224 处引用、其中 **944 处在归档面**（memory/reports/stories/docs），而本仓定律-3 禁止动归档面" "⇒ 照字面执行会撞定律-3。R110 复核确认此约束，登记在此防止后来者直接开改。",
             kind="known-red"),
    # 【债已还完】（R185 登记 → R55 还债）：R185 时的「判定面 5 条 > 上限 0」已清零 ——
    # 4 处 `raise SystemExit("FATAL…")`（check_badge ×1 / check_test_sync ×3）改成
    # `print(…) + raise SystemExit(2)`（**把码改真**）；check_index_gitlinks 的元组出口补了字面
    # `return 2`（**让已存在的承诺可证**）。实测「判定面归零（上限 0）」⇒ rc=0。
    # 按本文件的律「被检内容修好 ⇒ 把期望改回门禁格」，从 known-red 转回 case。
    # **没动 `CONTRACT_GAP_CEILING`**（仍是 0）。
    case("check_exit_code_contract.py"),
    # ── 兑现（R108）：主线 `866e2e65` 把 dist 快照刷到与 moon.mod 同版 ⇒ 这一格现读 got=0，"
    #    登记的红已不成立。按本文件自订的律「被检内容修好 ⇒ 把期望改回 0」转回门禁格，依据一起删。──
    # ── BUG-428（2026-10-26 立案 / 2026-10-27 收口）：
    #    ① 立案时：版本面一直 PASS，而 dist 快照是 Oct 24 的旧构建（缺 2 条内容面探针）⇒ 现读 got=1，
    #       依据即事故本身：`版本对但代码旧`；当时转成 known-red 预存红。
    #    ② **收口（本笔）**：`python scripts/refresh_dist.py` 真刷新后，`check_dist_snapshot` 现读
    #       `PASS 版本面 0.3.10 == moon.mod 0.3.10 · 内容面 3 条探针全部有调用形`
    #       ⇒ **按本文件自订的律把期望归位到 0**（`expected(...,1)` → `case(...)`）。
    #    ③ 刷新用的源码约束（重要）：必须在 `engine/*` 的 WIP 被提交**之后**跑
    #       —— 否则会把未完成改动打进发布快照。本笔是在 `BUG-432` 提交（`c68f3250`）之后刷的。──
    case("check_dist_snapshot.py"),
    # 内容面格的变异对照在它自己的 --selftest 里（19 格：版本 8 + 内容 6 + 合成 5）；同批接进电池。
    case("check_dist_snapshot.py", "--selftest"),
    # ── BUG-428 P0：部署产物新鲜度（PATH 垫片反解 + 固定候选 × 时间面 + 内容面）。
    #    自检格是门禁（40 格，含 5 处变异对照：内容面/时间面/变形容忍/缓存降级/面去重各有必红格）；
    #    裸跑格是**诊断**：它的 rc 反映这台机器的部署状态（0=全新鲜 / 1=有产物落后 / 2=一个可判面都没有，
    #    例如 Linux CI 没有 fist-mbt 垫片），三读都正确 —— 本机现读 1（部署副本/dist/_release 都落后）。
    #    写死 0 会在任何"改了源码还没重建"的机器上假红；写死 1 会在刚刷新的机器上假绿。故允许 {0,1,2}。──
    case("check_deployment_freshness.py", "--selftest"),
    tolerant("check_deployment_freshness.py", (0, 1, 2),
             "部署新鲜度诊断读数：0=全新鲜 / 1=有产物落后源码（本机现读，刷新后转 0）/ "
             "2=一个可判面都没有（CI 无垫片），三读都正确，本格只报读数。"
             "**这格不是免检牌**：0/1/2 之外的读数（4=探针脱锚/尺子坏、崩溃 traceback、"
             "被改成恒绿）仍判 FAIL；确定性门禁在上一格 --selftest（42 格，含 5 处变异对照）"),
    # —— R49：这一格**只报读数不判健康**。cleanup --check 的 rc 取决于工作树脏不脏
    #    （temp/ 残留、`_` 临时脚本 ⇒ 1；隔离树/空 temp ⇒ 0），不是代码健康。
    #    写死 1 ⇒ 干净 worktree 恒假红；写死 0 ⇒ 真脏树假绿；按 temp/ 存在算期望也不行
    #    （空目录仍 CLEAN，探针与脚本看的不是同一条件——两侧都实测过）。故允许 {0,1} 并照实打印。 ——
    # —— R50：删分支硬门 + 审计尺。**只跑 --selftest**（它不带参数时会读真仓分支并可能删东西吗？
    #    不会——不带参数只判定并写审计；但电池必须只读，故只跑离线自检格）。 ——
    case("audit_branch_delete.py", "--selftest"),
    tolerant("cleanup_artifacts.py", (0, 1),
             "树态诊断：temp/ 残留或 `_` 临时脚本存在时读 1，否则读 0；两读都正确，本格只报读数",
             "--check"),
    # ── 这一格是「预存红被修好 ⇒ 期望改回 0」那条律的一次兑现（不是我们替它改的读数）──
    # R106 现读：判定面 J1 悬空-注释面 0 条，棘轮上限也已在 R76（BUG-373 出路②）归 0 ⇒
    # 原来的 expected(...,1) 依据自写的那句「修到自然转绿后把期望改回 0」到期，转回门禁格。
    case("check_bug_reference_integrity.py"),
    gated("check_skill_inject.py", "fist-mbt.db", "fist-mbt.db"),
    # 2026-10-24：原预存红「fmt 段依赖 git diff 管道，本机退化 rc=-1 ⇒ 按设计 DEGRADED(2)」
    # 已不成立——实测 `moon fmt` 预热出 `_build/wasm-gc/release/format/` 之后，fmt 段判
    # **PASS（moon fmt --check: clean）**，六门全 PASS、rc=0。按本文件自订的律
    # 「被检内容修好 ⇒ 把期望改回 0」转回门禁格（预存红是借条，不是免检牌）。
    # R122：本机 rc=2 是**环境读数**（BUG-388 让 `moon fmt --check` 不可测 ⇒ 下游判据拒绝出数），
    # 不是缺陷；CI（Linux nightly）上应为 0。两种读数都正确 ⇒ 按本文件自订的「树态诊断格」口径
    # 用 tolerant 允许 (0, 2)，标签记「诊断」、末列照实打印真实 rc（人一眼能看到这次读到几）。
    # ⚠️ **不会自己收紧**：`(0, 2)` 里 0 也允许 ⇒ BUG-388 修好后本格**照样绿**。
    # 所以这条依赖人复查（`check_fmt_gate.py` 能出 0/1 时就该把 allow 收窄到 (0,)）；
    # 写在这里而不是假装它自动红 —— 本仓纪律要求把「靠人」的部分明说。
    tolerant("fist-gate.py", (0, 2),
             "诊断口径：本机 `moon fmt --check` 因 BUG-388（工具链 `--check` 管线报 No such file / rc=-1）"
             "不可测 ⇒ `fist-gate.py` 读 2（DEGRADED，拒绝判红也拒绝判绿）；CI Linux nightly 上读 0。"
             "两者都是**正确读数**，缺陷不在判据也不在本仓代码。"),
    # ── R134：轮次号在 reports/ 交付面被不同单元复用（R110/R113/R118/R121 各两组）是
    #    「编号没有认领面」的直接后果——两支各自读开工时刻的远端快照，谁先推谁占号。历史
    #    4 组进 docs/tasks/unit-number-baseline.txt 棘轮；新撞号 / 基线过期 / 悬空认领三态
    #    都红，S9 是「真源现状面必须绿」的活格。
    case("check_unit_number_unique.py"),
    case("check_unit_number_unique.py", "--selftest"),
    # ── BUG-459：写门文档声称覆盖的工具清单 vs 注册面实际调用点——两侧必须相等，
    #    防「文档说三支、代码只接两支」这种漂移再发生。自检 9 格（4 格变异对照：
    #    删代码行 / 只留注释 / 文档多声称 / 代码多接一支），变异点都落在代码行。
    #    注意：本行注释刻意不写被对表的工具名字面，避免模式串自己进判定面。
    case("check_ns_write_gate_coverage.py", "--selftest"),
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
AUTO_CASE_EXACT = {"gen_plugins.py", "fist-gate.py", "check_repo_shape.py"}


# ── 判例-33：性能逃生口 `FIST_BADGE_FRESH=0` ──────────────────────────────────
# 默认开（电池里就真跑，7~9 分钟也值）；显式 0 才关。关的时候必须**说出跳过了什么**，
# 否则「SKIP」在汇总里跟在「这格没问题」长得一样。
def fresh_enabled():
    """`--fresh` 类格子要不要真跑。只有显式 `FIST_BADGE_FRESH=0` 才关（默认开）。"""
    return os.environ.get("FIST_BADGE_FRESH", "").strip() != "0"


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


# —— R106（2026-10-22 实测）：以下三件（+ 上面的 universe_files）本体在 2bd4dbf2（R82/TASK-007）
# 就存在，其后一次「手动解冲突合入」把**定义**删了、把**调用面**留着 ⇒ is_gate / exempt_reason /
# classify 当场 NameError ⇒ `--selftest` 与 `--list` 全起不来，CI（ci.yml 那两步）整条红了一天。
# 定义与调用被拆到两次改动里，正是这类事故的形状；下面的 selftest 格把「宇宙必须是递归的、
# 且含 blackbox 尺」钉成判据，不再靠「跑起来才发现」。
GATE_PREFIXES = ("check_", "e2e_", "run_", "gen_plugins", "cleanup_",
                 "store_isolation", "fist-gate", "cli_flag_probe",
                 "audit_branch_delete")

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
    (
        "tmp_audit_preservation_scan.py",
        "资产保全取证器（一次性只读取证；入库是留史料，不是尺——"
        "它的输出已在 reports/2026-10-24-asset-preservation-proof.md 里逐条落定）",
    ),
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


# R82：登记面——「不该被自动电池跑」的脚本必须在此点名 + why，否则按缺面判红。
# 与 CASES 的分工：CASES 是「要跑的」，REGISTRY 是「在册但不自动跑的」（起服务/需网络/
# 平台前提/一次性补丁/纯辅助库）。点名失效（脚本删了）由 G2 扩展面抓。
REGISTRY = {
    "award_demo.py": "演示脚本（无门禁语义）",
    "blackbox/e2e_assistant_xproc.py": "端到端探针：跨进程起真 assistant，需运行前提，跑法见 scripts/README.md",
    "blackbox/e2e_lock_xproc.py": "端到端探针：跨进程锁竞争，需运行前提，跑法见 scripts/README.md",
    "blackbox/e2e_mirror_install.py": "端到端探针：真下载镜像安装（网络 + 沙箱），跑法见 scripts/README.md",
    "blackbox/e2e_transport_stack_fallback.py": "端到端探针：TLS 换栈真装（网络 + 沙箱），跑法见 scripts/README.md",
    # 2026-10-24（R44）：变异探针要 `git clone --depth 1` 出临时仓并在里面造违例——属
    # 「需平台前提的 e2e」族，进 REGISTRY 而不进自动电池（真跑一次数分钟）。
    # 实测 BITES 5 / BLUNT 0 / SKIP 0，跑法见 scripts/README.md。
    "blackbox/e2e_guard_mutation.py": "端到端探针：「判据会不会咬」变异测试（clone + 造违例 + 复跑），跑法见 scripts/README.md",
    "blackbox/e2e_upgrade_mirror.py": "端到端探针：升级镜像真装（网络 + 沙箱），跑法见 scripts/README.md",
    "blackbox/patch_esm_main.py": "构建辅助：mcp_smoke/demo 启动前幂等注入 require shim（CI 在用，不单独当格跑）",
    # 2026-10-24（R46）：夹具 git 环境隔离的**单一真源**——纯辅助库（只定义 `isolated_git_env()`），
    # 无独立判据语义；它的正确性由 `check_git_sandbox_hygiene.py`（普查棘轮）+ 自身 `--selftest`
    # 8 格 + 8 个接线脚本的 selftest 共同覆盖，故进 REGISTRY 带理由而不单独当格。
    "git_env.py": "辅助库：夹具 git 环境隔离单一真源（isolated_git_env），正确性由沙箱普查棘轮与自身 selftest 覆盖",
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
    # 2026-10-24： /  两条登记已撤——它们指向的脚本
    # **不在跟踪面**（ 第 110/111/135/137 行点名忽略，只存在于本机工作树）。
    # 为什么必须撤：G2 判据「登记面点名的脚本不存在 ⇒ FATAL(rc=2)」在别的机器/CI 上会把
    # **整台电池**卡死在 FATAL ⇒ 90+ 格一个都跑不出来（ 实测就是这条）。
    # 登记表是「在册但不当格跑」的说明，脚本不在仓里就不该在册——与 BUG-373「先入账再引用」同律。
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
    "install_git_hooks.py": "本机 git 钩子安装/体检（--install 写 .git/hooks 与 core.hooksPath；"
                            "--selftest 读的是**这台机器装没装**，副机/CI 上必 rc=1 属环境态不是判据红）",
    "refresh_dist.py": "dist 快照刷新计划/执行（要 moon build 产物并写盘；无 --selftest 旗标，"
                       "跑法见 scripts/README.md 同名条目）",
}


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


def _tracked_scripts():
    """Git 跟踪面里的 `scripts/` 脚本集合（相对 `scripts/` 的路径）。

    **为什么宇宙必须先过这一面**（2026-10-24 实测的整台电池 FATAL）：
    `.gitignore` 里有几份**本机专属**脚本（`pol_keeper_run.py` / `pol_keeper_wrapper.ps1` /
    `pol_keeper_prompt.md` / `fix_esm_require.py`，见 `.gitignore` 第 110/111/135/137 行）。
    旧的 `os.walk` 宇宙把工作树当宇宙 ⇒ 这些「本机有、仓里没有」的文件被要求有执行面，
    G1 报缺面 ⇒ 有人把它们塞进 REGISTRY 图个 rc=0 ⇒ G2「登记点名的脚本不存在」在
    **别的机器/CI 上**把整台电池卡在 FATAL(rc=2)，90+ 格一个跑不出来（`5be75f1e` 的现场）。

    换个方向修：宇宙只该是**仓库里真有、且会被别人克隆到**的那批脚本。工作树里的
    gitignored 文件是「这台机器的私人物件」，不构成「缺面」。取不到 git（非仓 / 无 git）时
    返回 None ⇒ 调用方退回全扫（保持离线可用，不把「读不到」当「没有」）。
    """
    try:
        p = subprocess.run(
            ["git", "-C", ROOT, "ls-files", "-z", "--", "scripts"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if p.returncode != 0:
        return None
    tracked = set()
    for rel in p.stdout.decode("utf-8", "replace").split("\0"):
        if not rel:
            continue
        rel = rel.replace("\\", "/")
        if rel.startswith("scripts/"):
            tracked.add(rel[len("scripts/"):])
    return tracked or None


def universe_files():
    """递归扫描 scripts/ 下全部 .py（相对 scripts/ 路径名，子目录带前缀）。排除 __pycache__。

    本体在 2bd4dbf2（TASK-007 / R82）落过一次，其后一次手动解冲突把它从 `classify()` 的调用面上
    删掉了 ⇒ 全电池 `NameError` 起不来（2026-10-22 实测 `--list` rc=1）。宇宙一旦被改窄或改没，
    G1「无人缺面」就会以 rc=0 的形态骗人，所以这一份清单必须是真源。

    2026-10-24 补：宇宙再叠一道 **Git 跟踪面**过滤（见 `_tracked_scripts`）——gitignored 的
    本机私人物件不算「仓里的脚本」，否则 G1 会要求为它们建执行面、G2 会在别人机器上 FATAL。
    """
    out = []
    if not os.path.isdir(SCRIPTS_DIR):
        return out
    tracked = _tracked_scripts()
    for dirpath, dirnames, filenames in os.walk(SCRIPTS_DIR):
        dirnames[:] = sorted(d for d in dirnames if d != "__pycache__")
        for fn in sorted(filenames):
            if not fn.endswith(".py"):
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, SCRIPTS_DIR).replace(os.sep, "/")
            if UNIVERSE_EXCLUDE_RE.search(rel):
                continue
            if tracked is not None and rel not in tracked:
                continue
            out.append(rel)
    return out


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
    """普查宇宙（G1 的对象）= 递归扫到的**每一份**脚本（R106 把两份并排的设计合起来）。

    `classify()` 的三份（门禁尺 / 豁免带理由 / 未归类）是**记账口径**，不是宇宙本身：
    宇宙只取「前缀像门禁尺」的那些，`whisperer.py` / `refresh_dist.py` 这类新工具就天然在账外，
    「无人缺面」于是变成宇宙被改窄的奖励——R106 那次 NameError（定义被合并删掉、调用面留着）
    正是这条假绿路径的近亲。所以：宇宙 = 全集，一份脚本要么有执行面（CI / 电池 / 登记），
    要么有豁免理由（EXEMPT_RULES / KNOWN_NO_FACE / 常驻），两样都没有 ⇒ 缺面点名报红。
    """
    return universe_files()


def auto_case_for(rel, src, declared_script, declared_argv):
    """R106：把「这一份该不该自动补一格」从循环体里抽成**纯函数**。

    为什么要抽：合并后这台机器在现状树上产 **0 格**——`build_cases()` 已按脚本名给每份可发现
    脚本补了无参格，而本函数按名字排除，于是 `auto_cases()` 恒空。恒空的产物让任何「拿真产物
    反证」的自检格退化成 `all([])` 式的空转绿灯（本仓「空扫描即自拒」的同一口径）。
    入参可控之后，自检用合成宇宙驱动它，机器哪天坏了会自己红，而不是靠产物非空来许愿。
    """
    if rel == SELF or rel in declared_script:
        return None
    if non_gate_reason(rel) or is_resident_src(src):
        return None
    if "--selftest" not in src:
        return None
    if (rel, ("--selftest",)) in declared_argv:
        return None
    return case(rel, "--selftest")


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
        full = os.path.join(SCRIPTS_DIR, rel)
        try:
            src = io.open(full, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        c = auto_case_for(rel, src, declared_script, declared)
        if c is not None:
            out.append(c)
    return out


# R106：自动补格在 import 期一次算完并**留底**。之后第二次再调 auto_cases() 只会得到空表——
# 它以「CASES 里已点名的脚本」为排除集，而自己那批格子此刻已经躺在 CASES 里了。
# 于是任何「运行期再推导一次」的写法（电池汇总的手写/自动拆分、自检格里的反证面）都会读到 0，
# 把一台真在干活的机器读成一格空转。留底就是这台机器的现读凭证。
AUTO_CASES = auto_cases()
CASES = CASES + AUTO_CASES


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


def check_faces(guards, ci_names, case_scripts, missing, existing=None, resident=(), registry=()):
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
    # `g != SELF`：本文件自己就写着 `RESIDENT_MARKERS = ("serve_forever(", "run_forever(")` ⇒
    # 文本嗅探会命中**定义本身**，把尺子报成常驻服务。自锁要显式，不能靠这条意外。
    resident = sorted(g for g in guards_all
                      if g != SELF and g not in battery and is_resident(g))
    rset = set(resident)
    guards = [g for g in guards_all if g not in rset]
    # R106：登记面（REGISTRY）与待接线（KNOWN_NO_FACE）、豁免理由（EXEMPT_RULES）都是账——
    # a86edc36 写的「登记与 CI/电池同权构成执行面」在合并里只剩 check_faces 函数体里的 `registry`，
    # 调用面没传，等于登记不顶用；豁免面同理从没被任何判定读过。
    exempted = {rel for rel, _why in classify()[1]}
    faces = ci | battery | set(REGISTRY) | set(KNOWN_NO_FACE) | exempted
    missing = [g for g in guards if g not in faces]
    rows = [(g, "CI" if g in ci else "-", "电池" if g in battery else "-") for g in guards]
    return rows, missing, ci, battery, guards, resident


CASE_TIMEOUT_SEC = 600

# 记账口径（kind）与判定（ok）是两件事：kind 只说明这格按哪条律记账，不说明它过没过。
KIND_TAG = {"gate": "门禁", "diag": "诊断", "known-red": "预存红"}


def case_line(kind, ok, rc, expect, name, tail):
    r"""逐格读数行：判定列在最前，口径列在后。

    旧写法把标签直接从 kind 取（gate→"OK"），于是一条 rc=1 exp=0 的门禁格照印 "OK"，
    红只出现在末尾汇总——先读这一行的消费者（人和 AI）看到的是一盏绿灯。本仓对这一类
    「一行看不出问题」的形状有名字（R106 的「空产物反证」同源）。
    """
    return "%-4s rc=%-2s exp=%-2s %-56s %s %s" % (
        "PASS" if ok else "FAIL", rc, expect, name, KIND_TAG.get(kind, kind), tail)


def run_battery(case_timeout=CASE_TIMEOUT_SEC):
    rows, missing, ci, battery, guards, resident = face_report()
    rc, lines = check_faces(guards, ci, battery, missing, resident=resident,
                            registry=set(REGISTRY))
    for l in lines:
        print(l)
    if rc == 2:
        return 2
    # R106：自动补格在 import 期就并进 CASES 了（`CASES = CASES + auto_cases()`），
    # 这里再调一次只会把同一批格子算两遍——旧写法 `auto_cases(battery, ci, guards)` 还是
    # 另一版（a86edc36）的三参签名，合并后签名与调用面不同形 ⇒ TypeError，被上面那道
    # 「未捕获异常 ⇒ 4」的门抓出来（这正是那一档要区分的形状）。
    print("\n=== 电池 %d 格 ===" % len(CASES))
    py = sys.executable
    fails, skips = [], []
    for c in CASES:
        # BUG-368：前置既可能是文件（temp/*.json）也可能是目录（temp/ 树态）⇒ 用 exists
        miss = [n for n in c["needs"] if not os.path.exists(os.path.join(ROOT, n))]
        if miss:
            skips.append((c["name"], "缺前置 " + " ".join(miss)))
            print("SKIP  %-56s %s" % (c["name"], "缺前置 " + " ".join(miss)))
            continue
        # 判例-33：性能逃生口。`FIST_BADGE_FRESH=0` 跳过 `--fresh`（判前真跑全仓）时，
        # 本格只证明了「文档 == 快照」，**没有**证明「文档 == 现实」——
        # 不带这句说明的 SKIP，在汇总里会被读成「这格没问题」，那就是又一种假绿。
        if "--fresh" in c["argv"] and not fresh_enabled():
            why = ("SKIP 新鲜度检验（FIST_BADGE_FRESH=0）：本格只证明了「文档 == 快照」，"
                   "未证明「文档 == 现实」——快照可能比代码旧（判例-25）")
            skips.append((c["name"], why))
            print("SKIP  %-56s %s" % (c["name"], why))
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
        # R49：树态诊断格可以声明"多个都正确的读数"（allow），不把环境差异误报成 FAIL。
        allow = c.get("allow")
        ok = p.returncode in allow if allow else (p.returncode == c["expect"])
        print(case_line(c["kind"], ok, p.returncode, c["expect"], c["name"], tail))
        if not ok:
            fails.append((c["name"], p.returncode, c["expect"], c["why"], tail))
    print("\n=== 汇总 ===")
    # 拆分从 import 期的留底读，不在这里二次推导：auto_cases() 的排除集已含它自己的产物。
    # 现状自动格 = 0（build_cases 先按名补齐），读数照实写 0 并给成因——把「自动 0」印成
    # 一行看不出问题的数字，就是下一位读者以为这台机器退休了的开始。
    auto_n = len(AUTO_CASES)
    print("格数 %d（手写 %d + 自动 %d）/ 失败 %d / SKIP %d / 缺执行面 %d"
          % (len(CASES), len(CASES) - auto_n, auto_n,
             len(fails), len(skips), len(missing)))
    if auto_n == 0:
        print("  自动补格 0 的成因：build_cases() 已按脚本名为每份可发现脚本补无参格，"
              "auto_case_for 的名字排除集因此恒命中；机器本身由 --selftest 的 7 格合成对照钉住"
              "（见 selftest），不是退休。")
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
    cell("universe-is-recursive-census",
         guard_files() == universe_files()
         and any(x.startswith("blackbox/") for x in universe_files())
         and not any(UNIVERSE_EXCLUDE_RE.search(x) for x in universe_files()), True)
    cell("classify-partition-alive",
         len(classify()[1]) > 0 and all(is_gate(g) for g in classify()[0]), True)
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
    rows, missing, ci, battery, guards, resident = face_report()
    # 钉的是**自动补格**这条机器。R106：现状树上这台机器产 0 格（`build_cases()` 已按名把每份
    # 可发现脚本补了无参格，排除集于是永远命中），所以反证**不能**落在真产物上——`all(对空表)`
    # 恒真就是一盏没人认领的绿灯。改成合成宇宙驱动纯函数 `auto_case_for`，四种输入各有对错。
    _decl_s = {"check_bare.py", "check_already.py"}
    _decl_a = {("check_already.py", ("--selftest",))}
    _src_st = "def main():\n    pass  # --selftest\n"
    cell("auto-case-produces-selftest-cell",
         list((auto_case_for("check_new.py", _src_st, _decl_s, _decl_a) or {}).get("argv", [])),
         ["--selftest"])
    cell("auto-case-skips-non-gate",
         auto_case_for("demo_tool.py", _src_st, _decl_s, _decl_a), None)
    cell("auto-case-skips-resident",
         auto_case_for("check_bridge.py", "  app.run_forever()\n", _decl_s, _decl_a), None)
    cell("auto-case-skips-already-declared-name",
         auto_case_for("check_bare.py", _src_st, _decl_s, _decl_a), None)
    cell("auto-case-skips-already-declared-argv",
         auto_case_for("check_already.py", _src_st, _decl_s, _decl_a), None)
    cell("auto-case-skips-no-selftest-flag",
         auto_case_for("check_plain.py", "print('ok')\n", _decl_s, _decl_a), None)
    cell("auto-case-skips-self",
         auto_case_for(SELF, _src_st, set(), set()), None)
    cell("non-gate-never-becomes-auto-case",
         non_gate_reason("patch_router_config_caf_field.py") != ""
         and all(not non_gate_reason(c["script"]) for c in AUTO_CASES), True)
    cell("gen-plugins-still-gate", non_gate_reason("gen_plugins.py"), "")
    cell("repo-current-has-no-orphan-guard",
         check_faces(guards, ci, battery, missing, registry=set(REGISTRY))[0], 0)
    cell("known-no-face-not-counted-as-missing",
         all(k not in missing for k in KNOWN_NO_FACE), True)
    cell("census-wider-than-gate-prefix", any(not is_gate(g) for g in guards), True)

    # ── R185：「登记 known-red = 欠债」必须显形且带理由 ──────────────────────────
    # 统帅要求：「理由必须写清『这是债不是坏』——否则每轮有人以为判据坏了去改常量」。
    # 这几格把该要求**变成可执行断言**，而不是只留在注释里：
    #   ① 每个 known-red 格必须带非空 why（空 why = 发了张免检牌，判据不属于任何人）；
    #   ② 只剩**一把**棘轮债在册（`check_scripts_naming` 的命名债）—— 少一条说明有人**删了登记**
    #      而不是把债还了；**还了债的要同批从册上摘掉并转回门禁格**（R55/R56 已摘两把：
    #      `check_exit_code_contract` 判定面归零 / `check_ci_step_position` 35→30）。
    _kr = [c for c in CASES if c.get("kind") == "known-red"]
    cell("known-red-all-have-why", all((c.get("why") or "").strip() for c in _kr), True)
    _kr_scripts = {c.get("script") for c in _kr}
    cell("known-red-covers-remaining-ratchet-debt",
         {"check_scripts_naming.py"} <= _kr_scripts, True)
    # ③ 在册那把的 why 必须写明「债非坏」的口径词（防止有人把理由改成一句"已知红"就交差）
    _kr_why = " ".join((c.get("why") or "") for c in _kr
                       if c.get("script") in ("check_scripts_naming.py",))
    cell("known-red-why-says-debt-not-broken", "债非坏" in _kr_why, True)
    # R106 第二处同形缺陷：run_battery 里 `auto_cases(battery, ci, guards)` 是**另一版**的三参签名，
    # 合并后调用面与定义不同形 ⇒ 只有真跑电池才炸（`--selftest`/`--list` 都摸不到那一行）。
    # arity 对表是这一类「定义与调用被拆到两次改动」最便宜的常驻锁。
    cell("auto-cases-arity-matches-call-site",
         len(inspect.signature(auto_cases).parameters), 0)
    cell("battery-has-no-self-case", any(c["script"] == SELF for c in CASES), False)
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
    # R121 本体：逐格行的判定列必须来自 ok，不是来自 kind。旧写法 gate→"OK" 让红格印成
    # 绿灯（红只在汇总里），三格分别钉住「红不印 OK」「命中印 PASS」「预存红仍带口径标注」。
    _red = case_line("gate", False, 1, 0, "check_x.py", "FATAL: boom")
    _hit = case_line("gate", True, 0, 0, "check_x.py", "PASS 12/12")
    _knw = case_line("known-red", True, 1, 1, "check_y.py", "按登记")
    cell("inline-verdict-red-never-printed-as-ok",
         _red.startswith("FAIL") and "OK" not in _red, True)
    cell("inline-verdict-green-printed-as-pass", _hit.startswith("PASS"), True)
    cell("inline-known-red-still-labeled-by-kind",
         _knw.startswith("PASS") and "预存红" in _knw, True)
    print("  ok  现状读数：%d 把尺 / CI 面 %d / 电池面 %d / 缺面 %d / 常驻豁免 %d"
          % (len(guards), len(ci & set(guards)), len(battery & set(guards)), len(missing),
             len(resident)))

    bad = [(nm, why) for nm, ok, why in cells if not ok]
    if bad:
        print("SELFTEST FAIL：")
        for nm, why in bad:
            print("  - %s：%s" % (nm, why))
        sys.exit(1)  # NO_CALL_FACE J2
    print("SELFTEST OK（%d 格：宇宙=递归全集且排除族不入宇宙 + 分类机器活着 + 覆盖 blackbox 真尺 / "
          "G2 不误判 blackbox stale / G1 抓 blackbox 孤儿 + 带前缀点名 / G1 干净 / G1 抓漏面尺 + 必点名 / "
          "G3 三种空宇宙各自拒 / G2 电池点了不存在的脚本自拒 / 真源现状全绿（登记面入账）/ "
          "待接线不计缺面 / 宇宙宽于门禁前缀清单 / 电池里没有自我递归格 / "
          "自动补格纯函数七面（产格 / 跳非门禁 / 跳常驻 / 跳已点名脚本名 / 跳已点名旗标 / 跳无 selftest / 跳本尺）"
          " + 非门禁族不被自动补格 / gen_plugins 仍是门禁族 / plan_landing 已进电池 / "
          "plan_landing 门禁格与诊断格并存且诊断格 why 带构成 / "
          "常驻分类器咬 serve_forever 与 run_forever 且不误咬干净尺 / 常驻面逐条点名不静默 / "
          "电池里没有裸跑的常驻格 / 有常驻豁免时真孤儿仍判红 / "
          "逐格判定列取自 verdict 而非 kind（红不印成 OK / 命中印 PASS / 预存红仍带口径标注））" % len(cells))
    sys.exit(0)  # NO_CALL_FACE J2


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
        _g, _e, _u = classify()
        print("分类记账：门禁尺 %d / 豁免（带理由）%d / 未归类 %d"
              % (len(_g), len(_e), len(_u)))
        for rel in sorted(set(KNOWN_NO_FACE)):
            print("  待接线 %-42s %s" % (rel, KNOWN_NO_FACE[rel]))
        # 「非判据」= 在宇宙里可见、且**不进电池**。有手写 case 的脚本（哪怕名字不在门禁前缀族）
        # 已在判据面上，不能再出现在这份「不进电池」清单里（R118：audit_branch_delete 同时出现在
        # 门禁尺 56 与「非判据」两处——两份判据用的谓词不同，清单说的是假的）。
        nong = [(s, non_gate_reason(s)) for s in discover_scripts()
                if non_gate_reason(s)
                and os.path.basename(s) not in {os.path.basename(b) for b in battery}]
        print("非判据工具 %d 个（留在宇宙可见、不进电池——电池只读，改码/生成/宿主类工具不在判据面）" % len(nong))
        for s, why in nong[:60]:
            print("  非判据 %-42s %s" % (s, why))
        if missing:
            print("缺面清单：" + " ".join(missing))
            return 1
        return 0
    return run_battery(args.case_timeout)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except BaseException:
        # R106 的形状：一次手动解冲突把 GATE_PREFIXES / EXEMPT_RULES / _match_rule / universe_files
        # 的定义删了、调用面留着 ⇒ 模块 import 期 NameError。旧写法让这种「尺子坏了」长得
        # 和「判据判红」一模一样（都是 1），读日志的人只能靠有没有 traceback 区分。
        import traceback
        traceback.print_exc()
        sys.stderr.write("RULER BROKEN: run_guards.py 未捕获异常 ⇒ 4（不是判红，不冒用 1）" + chr(10))
        sys.exit(4)
