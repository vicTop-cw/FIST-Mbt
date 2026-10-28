#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_plan_landing.py — 计划文档「点名落点」↔ 跟踪面 存在性 核对（只读诊断，非门禁）。

**为什么需要它（2026-10-13 实测驱动）**：本会话反复遇到"计划说某文件已实现/将新增，但该文件不在 HEAD"：
  - `docs/2026-10-12-fist-mbt-supervisor-tools-plan.md` §5 点名 5 处落点，其中
    `src/server/supervisor_tools_test.mbt` **根本不存在**（测试锁未做），
    另两个新增文件（471 + 622 行）**在磁盘上却不在 HEAD**（已实现、未提交）
  - `docs/2026-10-12-fist-mbt-web-dashboard-plan.md` 的 M0 落地件 `scripts/fist-mbt-web.py`
    **实现完成、README 登记已入库，本体却未跟踪**
人工逐份核对要读十几份文档、几十个路径，且极易漏。本工具把这步机械化。

**判据（窄口径，刻意保守）**：
  P1 扫描指定计划文档里**反引号中的仓内文件路径**（形如 `` `src/foo/bar.mbt` `` /
     `` `scripts/x.py` ``），对每个路径给出四态：
       tracked  = 在 `git ls-files`（跟踪面）
       on-disk  = 在工作树磁盘上存在但不被跟踪  ⇒ **"实现已在工作树、只是没进跟踪面"**
       moved    = 点名处**跟踪面与磁盘都没有**，但跟踪面里存在**同名条目**、其父目录以点名父目录为前缀
                  ⇒ 事实是「搬家」（多为归档动作之后），不是「没落地」；单独出数、不入判定面
       missing  = 跟踪面与磁盘都没有，且没有搬家证据
     只报"非 tracked"的那些（tracked 是常态，报了是噪音）。
  P2 防空转：一份文档都没读到、或全仓零条仓内路径自述 ⇒ FATAL（判据空转 ≠ 没问题）。
  P3 **形状口径**（R40 实测：本守卫自 2026-10-14 落仓起既不在 CI 也不在历轮回归电池里，
     于是坏着躺了一周——它报的 56 条 missing 里 2 条是虚报）：
       - 「路径:行号」引用 `src/x.mbt:108/121/134` 先剥行号后缀再比跟踪面。原来整串当路径，
         而 `os.path.basename("…/134")`="134" 不含点 ⇒ 通过 `base_ok` ⇒ **已跟踪文件被报 missing**。
       - 日期/变量占位（`memory/YYYY-MM-DD.md`、`yyyyMMdd.HH.mm.ss`、`caf-{ns}.json`）与既有的
         `<...>`/`*` 同属**形态说明**，不算落点；但**单独计数控出**（静默丢弃=数字凭空变少，
         下一轮没人知道少的是噪音还是缺陷）。
  P4 **分面出数**（同一批实测：56 条里 17 条落在 `docs/archive/`，那是历史计划的存档，
     其落点在归档面上本就是"当时没做/后来改名"的事实，不是今天的待办）：
     活文档面（计入退出码）与归档面（只报不判）分开打印，两边的数字都在结论行里出现。
  P5 **搬家态**（2026-10-21 实测，BUG-367 的 D 类 3 条）：判定面里点名的
     `docs/2026-10-11-multi-agent-lock-design-v2.md`、`docs/2026-10-11-fist-mbt-upgrade-plan-v2.md`、
     `docs/improvement-plan-20260929.md` **同名文件确实被跟踪**，只是父目录从 `docs/` 变成 `docs/archive/`
     （归档发生在引用写下之后）。三态宇宙里没有「搬家」这一格 ⇒ 它们只能读成 missing，于是**每一轮都要靠人
     肉反查 basename 才能确认「文档没错、是尺子少一格」**。判据取机械可证的窄形：
     `basename 相等` **且** `实际父目录以点名父目录为前缀` **且** 候选在**跟踪面**（磁盘上未跟踪的同名件不算证据）。
     两条刻意的保守：① moved 只**替换 missing**，不吃 on-disk（点名处自己在磁盘上时，`git add` 才是出路，
     不许被远处同名件抢白）；② 点名在顶层（无目录）时**不认 moved**——那时「实际在子目录」是引用没写目录，
     属文档口径问题，工具不替人猜。**moved 只证「同名 + 前缀」，不证「同一份内容」**，所以它单独出数、
     逐条打实际位置，由人确认；它不进判定面，但一条都不会静默消失。
  P6 **判定面棘轮**（BUG-367 建议②）：判定面条数只许下降。`VERDICT_GAP_CEILING` 超出即并红（rc=1）并在
     结论行显式标「超限 + 新增几条」；低于上限**只打印收紧建议、不判红也不自动改数**（同
     `check_deprecated_text_census` 的 R3 口径）。理由：A/B/C 三档裁决（BUG-367）由指挥官裁、节奏不由副机定——
     没有棘轮，裁决慢的那几周里新写的计划文档会继续往判定面里加条，而 28 这个数已经在心里被当成"已知的存量"。

**刻意不判**（避免过度拦截）：
  - 文本里指向**尚不存在**的文件是**合法的**（计划本来就会写"新增 X"）⇒ 本工具**不是门禁**，
    `missing` 只是**诊断读数**，退出码 1 表示"有落点未落地"，不代表 CI 该红。
  - 不解析状态列 / 不判断"该不该存在"（散文语义机器判不了；判了就是伪精确）。
  - 只认反引号包裹的路径（本仓文档惯例），裸路径不认（会引入大量误报，如目录名、命令名）。

用法：
  python scripts/check_plan_landing.py                    # 扫 docs/ 下全部 *.md
  python scripts/check_plan_landing.py <文档路径>...      # 只扫指定文档
  python scripts/check_plan_landing.py --selftest         # 合成违例自证
  python scripts/check_plan_landing.py --all-faces        # 归档面也计入退出码（默认只报不判）
  python scripts/check_plan_landing.py --gate             # 门禁口径：退出码只看棘轮（CI/电池用这个）
退出码：0=活文档面落点全在跟踪面（或有搬家证据的已按 moved 单独出数）/ 1=判定面有落点未落地（诊断）**或**判定面
        条数超出 VERDICT_GAP_CEILING（棘轮，结论行会显式写「超限」）/ 2=判据无法自证（FATAL：三条空转之一、
        git 枚举失败、或 `--gate` 与 `--all-faces` 这种没标定过的模式组合）。
        注：rc=2 这一格在 R41 之前是**幻影**——三处 FATAL 都写成 `raise SystemExit("…")`，而带字符串的
        SystemExit 退出码是 1。本轮实测把它改成真 2。同族面用 ast 数**真调用点**重扫（正则数文本会把
        docstring 里的字样当站点、把 `sys.exit(main())` 这种正常透传当"有整式出口"，两条口径缺陷都踩过）：
        `check_mbti_sync.py`（7 处串式 FATAL）/ `check_pkg_imports.py`（6 处）/ `check_template_ctrl.py`（1 处）
        自述 2 而代码里一条 2 都给不出 ⇒ 同为幻影，本轮未改；`simulate_head_commit.py` 是**半形**——
        moon 超时那条走 `return 2` 真给 2，其余 4 处 FATAL 走串式给 1，其中「PATH 上没有 moon」那条
        **文案里自己写着「（rc=2）」**。四份的处置记 BUG-369。
"""
import argparse
import os
import re
import subprocess
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BACKTICK = re.compile(r"`([^`\n]+)`")
# 只认"看起来是仓内文件路径"的：带目录分隔 + 有已知代码/文档扩展名。
# 目录也认（尾部斜杠），因为计划里常点"新增某目录"。
PATH_EXT = (".mbt", ".py", ".ps1", ".sh", ".md", ".json", ".yml", ".yaml", ".mbti",
            ".toml", ".cfg", ".txt", ".js", ".ts", ".sql", ".c", ".h", ".html")
TOP_DIRS = ("src/", "scripts/", "cmd/", "docs/", "templates/", "plugins/", "patches/",
            "reports/", "memory/", "specs/", "resources/", ".github/")
# P3 形状口径：`src/x.mbt:108/121/134` 这类「路径:行号」引用（本仓文档惯例，指到具体行）。
LINE_SUFFIX = re.compile(r"^(?P<path>.+?):(?P<lines>\d+(?:\s*[/,、-]\s*\d+)*)$")
# 日期/变量形态占位：`YYYY-MM-DD`、`yyyyMMdd.HH.mm.ss`、`caf-{ns}.json` —— 与 `<...>`/`*` 同类。
SHAPE_PLACEHOLDER = re.compile(r"YYYY|yyyy|HH\.mm|mm\.ss|[{}]")
# P4 分面：这些前缀之下的文档是**存档面**，其未落地落点只报不判红（默认）。
# 白名单刻意只收**名字里就写着存档的两族**（archive/ 与 reports/）；`docs/superpowers/plans|specs/`
# 虽然日期很旧，但目录名没自称存档 ⇒ 留在活文档面。把旧文档搬出白名单=拿命名兜底掩盖数字，
# 数字变好而缺陷没变，正是本守卫一周无人跑所暴露的那类失效。
ARCHIVE_DOC_PREFIX = ("docs/archive/", "reports/")

# P6 棘轮上限：判定面（活文档面里非 moved 的未落地条目）条数只许下降。
# 25 = 2026-10-21 实测：判定面 28 − moved 3（BUG-367 的 D 类，同名件确在 docs/archive/）。
# 这一格由 A/B/C 三档裁决（BUG-367 OPEN）决定何时能降，所以**不自动改数**：超限并红、有余量只给建议。
VERDICT_GAP_CEILING = 25


def tracked(root=None):
    root = root or ROOT
    r = subprocess.run(["git", "-C", root, "ls-files", "-z"],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.returncode != 0:
        sys.stderr.write("FATAL git ls-files 退出码 %s —— 拒绝在无枚举时出读数\n" % r.returncode)
        raise SystemExit(2)
    files = [x.replace("\\", "/") for x in (r.stdout or "").split("\0") if x.strip()]
    if not files:
        sys.stderr.write("FATAL git ls-files 返回空清单 —— 拒绝在无枚举时出读数\n")
        raise SystemExit(2)
    return files


def build_tracked_dirs(tracked_set):
    """从跟踪面文件清单反解出隐含的目录集合（git 不跟踪空目录，但跟踪其内文件 ⇒ 目录存在）。
    否则计划里点名的 `src/diff` 这类**已被跟踪的目录**会被误判为不在跟踪面。"""
    dirs = set()
    for f in tracked_set:
        d = os.path.dirname(f).replace("\\", "/")
        while d and d not in dirs:
            dirs.add(d)
            nd = os.path.dirname(d).replace("\\", "/")
            if nd == d:
                break
            d = nd
    return dirs


def extract_paths(text, with_shapes=False):
    """从反引号片段里抽出仓内路径。默认返回去重后有序列表；
    `with_shapes=True` 返回 (路径, 形态说明) —— 后者是被 P3 排除的占位/日期形状，只用于出数，
    不参与跟踪面比对（静默丢掉这批发「写了但机器不认」的形状，等于把尺子的口径变成不可查的私事）。"""
    out = []
    shapes = []
    for m in BACKTICK.finditer(text):
        raw = m.group(1).strip()
        cand = raw
        if cand.startswith("./"):
            cand = cand[2:]
        # 绝对路径（`/src/...`）无需单独拦截：下面 TOP_DIRS 闸要求以 `src/` 等**相对**前缀开头，
        # 以 `/` 开头者天然被排除。--- 变异实测发现原先那行单独的 `startswith("/")` 检查是**死代码**
        # （去掉它行为不变、无格可抓）⇒ 已删；改由 extract-rejects-abs-only 格锁定"绝对路径必须被拒"。
        if not cand.startswith(TOP_DIRS):
            continue                     # 只认仓内顶层目录开头的
        if cand.endswith("/"):
            cand = cand.rstrip("/")
        if not cand:
            continue
        # P3-a 「路径:行号」先剥后缀（R40 实测的虚报面：整串当路径 ⇒ 已跟踪文件报 missing）
        lm = LINE_SUFFIX.match(cand)
        if lm:
            cand = lm.group("path")
        base_ok = cand.endswith(PATH_EXT) or ("." not in os.path.basename(cand))
        if not base_ok:
            continue
        if "/" not in cand and not cand.endswith(PATH_EXT):
            continue                     # 顶层单个名字：太易误报，不认
        # **模板/占位形态不认**（2026-10-14 全仓扫描实测的误捕面）：计划文档常写
        # `docs/<tool>-skill.md` / `memory/research/*.md` / `docs/<lang>/` 这类**形态说明**
        # 而不是具体落点。它们不是"忘了交付"，是全仓误捕噪音（本轮 12 条全是它）。
        # 判据：路径任一片段含 `<...>` 或 `*` ⇒ 形态说明，跳过。
        if "<" in cand or ">" in cand or "*" in cand:
            if raw not in shapes:
                shapes.append(raw)
            continue
        # P3-b 日期/变量形态（R40 实测的第二批噪音：`memory/YYYY-MM-DD.md`、
        # `memory/reviews/yyyyMMdd.HH.mm.ss.md`、`memory/model-router-caf-{ns}.json`）同属形态说明。
        if SHAPE_PLACEHOLDER.search(cand):
            if raw not in shapes:
                shapes.append(raw)
            continue
        if cand not in out:
            out.append(cand)
    return (out, shapes) if with_shapes else out


def is_archive_doc(doc):
    """P4 分面判据：文档自身在存档面上（名字里写着 archive/reports）⇒ 其落点只报不判。"""
    return doc.startswith(ARCHIVE_DOC_PREFIX)


def find_moved(p, universe):
    """P5 搬家判据（纯函数：喂合成宇宙即可考，不需要真 git）。universe = 跟踪面文件 ∪ 跟踪面隐含目录。
    返回点名路径 p 的搬家候选；无候选 ⇒ 空列表，调用方落回 missing。
    三闸窄形：① basename 逐字相等；② p **有父目录**（顶层引用不认搬家，见 docstring 的保守②）；
    ③ 候选父目录等于 p 的父目录、或以 `p 的父目录 + "/"` 为前缀（搬进更深层子目录同样算）。
    磁盘上未跟踪的同名件**不进来**（调用方只喂跟踪面）：那证不了"搬过家"，只证"别处也有个同名文件"。"""
    parent = os.path.dirname(p)
    if not parent:
        return []
    base = os.path.basename(p)
    hits = []
    for x in universe:
        if x == p or os.path.basename(x) != base:
            continue
        xp = os.path.dirname(x)
        if xp == parent or xp.startswith(parent + "/"):
            hits.append(x)
    return sorted(hits)


def ratchet(n, ceiling):
    """P6 纯判据：判定面 n 条 vs 上限 ceiling。返回 (是否并红, 打印文本)。
    n > ceiling ⇒ 并红并写清多出几条；n < ceiling ⇒ **只给收紧建议、不阻断**；相等 ⇒ 无话。
    收紧不自动发生：数字随文档增删浮动，把「降上限」这个动作留给人，免得尺子自己把新盲区吞成合规存量。"""
    if n > ceiling:
        return True, "棘轮超限：判定面 %d 条 > 上限 %d ⇒ 比已核存量多 %d 条未落地" % (n, ceiling, n - ceiling)
    if n < ceiling:
        return False, ("提示：判定面已缩小到 %d 条（上限 %d）⇒ 可把 VERDICT_GAP_CEILING 收紧至 %d；"
                       "本轮不阻断，降与不降由人判" % (n, ceiling, n))
    return False, ""


# P7 B 档：外部宿主文件的**精确路径名单**（BUG-367）。src/adapter.js / src/eac.js / src/eac-login.js /
# src/vault.js 是浏览器扩展等别的宿主用到的件，不是本仓 MoonBit 包的源码；拿本仓跟踪面当分母，
# 计划文档里提到它们必然报 missing。加豁免=改这份常量名单，被 repo 审（绝不按目录/后缀大面豁免）。
EXTERNAL_HOST_FILES = ("src/adapter.js", "src/eac.js", "src/eac-login.js", "src/vault.js")


def exempt_reason(p):
    """P7 纯判据：命中 B/C 档豁免 ⇒ 返回 (态名, 处置话术)；不命中 ⇒ None。
    B 档：精确名单；C 档：scripts/ 下 basename 以 `_` 开头（本仓约定的一次性临时件）。
    只替换 missing（调用方保证 on-disk 优先）；按窄形写，反证在 selftest 里钉死（不误伤 src/foo.js、
    scripts/normal.py 这种非豁免形状）。"""
    if p in EXTERNAL_HOST_FILES:
        return ("external",
                "**外部宿主文件**（BUG-367 B 档：src/adapter.js 等属别的宿主，本仓跟踪面当分母必然报 missing）"
                "⇒ 只出数不判红")
    if p.startswith("scripts/") and os.path.basename(p).startswith("_"):
        return ("scratch",
                "**历史一次性临时件**（BUG-367 C 档：`_` 前缀=本仓约定的临时件，同 cleanup_artifacts 口径）"
                "⇒ 只出数不判红")
    return None


# ── P8/P9 设计性排除（2026-10-26 路 B）────────────────────────────────────────
#
# **为什么这是「设计性排除」而不是「为转绿硬塞豁免」** —— 判据读错了面，不是文档缺了什么：
#
#   P8 `memory/YYYY-MM-DD.md` 日日志：
#     `.gitignore` 明写 `memory/2026-*.md` 被永久排除（理由见其注释：614MB 级膨胀 + 每次合并必撞冲突）。
#     **被 gitignore 的设计性排除面本就不进跟踪面** ⇒ 拿跟踪面当分母问「它在不在」是永远为假的问题。
#     ⚠️ 自愈：本判据每次**现读 .gitignore**，若哪天该规则被移除，排除自动失效 ⇒ 6 条重新计入。
#
#   P9 `docs/proposals/` 提案目录：
#     **提案 ≠ 落地承诺。** 计划说「将新增 X」是对交付的承诺；提案说「建议新增 X」是选项讨论，
#     未被采纳就本不该落地。把提案点名算 missing = 要求「讨论过的每个选项都必须实现」。
#     ⚠️ 触发条件（正向）：**若某条提案被采纳并转成正式计划**（从 proposals/ 移入正式面，
#     或在正式计划里重新点名），P9 不再覆盖它 ⇒ 该点名重新计入判定面。

_RE_DAILY_LOG = re.compile(r"^memory/(?:19|20)\d{2}-\d{2}-\d{2}\.md$")
_GITIGNORE_FILE = ".gitignore"
# P9：提案目录前缀（窄形：只认这一条路径前缀，不按名字含 "proposal" 模糊匹配）
PROPOSAL_DOC_PREFIX = "docs/proposals/"


def _gitignore_excludes_daily_logs(root=None):
    """P8 的**真源现读**：`.gitignore` 里是否确有 `memory/20XX-*.md` 这类日日志排除规则。

    不写死 True：规则被移除 ⇒ 排除自动失效（自愈，不是一次性豁免）。
    读不到 .gitignore ⇒ 返回 False（**保守**：宁可多报，不可错放）。
    只认日日志形态的规则；`memory/` 整目录挡**不算**（本仓刻意逐文件点名，见 .gitignore 注释）。
    """
    root = root or ROOT
    try:
        with open(os.path.join(root, _GITIGNORE_FILE), encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError:
        return False
    for raw in text.splitlines():
        s = raw.strip()
        if not s or s.startswith("#"):
            continue
        if re.match(r"^/?memory/(?:20\d{2}|\*|20\?\?)[-*].*\.md$", s):
            return True
    return False


def design_exempt_reason(p, doc, daily_logs_ignored=None,
                         proposal_prefix=PROPOSAL_DOC_PREFIX):
    """P8/P9 纯判据：命中「设计性排除」⇒ 返回 (态名, 处置话术)；否则 None。

    两个参数都可注入，供 selftest 造夹具与**变异对照**（判例-29/30）：
      daily_logs_ignored : `_gitignore_excludes_daily_logs()` 的结果（None ⇒ 现读）
      proposal_prefix    : 提案目录前缀（变异格可置空，以证明排除真在起作用）
    """
    if daily_logs_ignored is None:
        daily_logs_ignored = _gitignore_excludes_daily_logs()
    if daily_logs_ignored and _RE_DAILY_LOG.match(p):
        return ("ignored-log",
                "**设计性排除面**（`.gitignore` 明确排除 `memory/20XX-*.md` 日日志）"
                "⇒ 它本就不进跟踪面，拿跟踪面当分母问「在不在」恒为假 ⇒ 只出数不判红")
    if proposal_prefix and doc.startswith(proposal_prefix):
        return ("proposal",
                "**提案面**（提案 ≠ 落地承诺：计划说「将新增」是承诺，提案说「建议新增」是选项讨论）"
                "⇒ 未被采纳的提案点名不算未落地；提案转成正式计划后该点名重新计入 ⇒ 只出数不判红")
    return None
    """P2 防空转的三条判据（纯函数，供 `--selftest` 直接考）。任一成立即 FATAL，返回那条因由。
    本轮把它从 main 里三处 `raise SystemExit("FATAL …")` 抽出来，实测顺手抓了一条自己的缺陷：
    **`SystemExit(带字符串)` 的退出码是 1，不是 2**（`python -c` 与真跑双测）⇒ 本文件 docstring 承诺的
    「2=判据无法自证」从来没有生效过，「判据空转」与「有落点未落地」在退出码面上同色，而电池期望文本里
    那句「读出 0 或 2 都算这格漂移」的 2 是不可达的。同族面见 temp/r41_fatal_census.py 的普查（BUG-369）。"""
    if not n_enum:
        return "一份文档都没枚举到 —— 判据空转，拒绝出读数"
    if not n_readable:
        return "一份计划文档都读不到 —— 判据空转，拒绝出读数"
    if not n_paths:
        return "全仓计划文档里一条仓内落点路径都没抽到 —— 判据空转，拒绝出读数"
    return None



def fatal_reason(n_enum, n_readable, n_paths):
    """P2 防空转的三条判据（纯函数，供 `--selftest` 直接考）。任一成立即 FATAL，返回那条因由。
    本轮把它从 main 里三处 `raise SystemExit("FATAL …")` 抽出来，实测顺手抓了一条自己的缺陷：
    **`SystemExit(带字符串)` 的退出码是 1，不是 2**（`python -c` 与真跑双测）⇒ 本文件 docstring 承诺的
    「2=判据无法自证」从来没有生效过，「判据空转」与「有落点未落地」在退出码面上同色，而电池期望文本里
    那句「读出 0 或 2 都算这格漂移」的 2 是不可达的。同族面见 temp/r41_fatal_census.py 的普查（BUG-369）。"""
    if not n_enum:
        return "一份文档都没枚举到 —— 判据空转，拒绝出读数"
    if not n_readable:
        return "一份计划文档都读不到 —— 判据空转，拒绝出读数"
    if not n_paths:
        return "全仓计划文档里一条仓内落点路径都没抽到 —— 判据空转，拒绝出读数"
    return None

def emit_fatal(msg):
    """FATAL 的统一出口：打到 stderr（与改前的 `SystemExit(str)` 同一条流）并**返回整数 2**
    （由 `sys.exit(main())` 落成退出码）。这里刻意不用 `raise SystemExit(msg)` —— 带字符串的
    SystemExit 退出码是 1，正是本轮实测抓到的那条幻影。"""
    sys.stderr.write("FATAL %s\n" % msg)
    return 2


def mode_fatal(gate, all_faces):
    """模式互斥判据：`--gate` 与 `--all-faces` 不许同给（返回 FATAL 文本，None=无冲突）。
    实测依据：同给时判定面从 25 条涨到 38 条（存档面 13 条被拉进来），拿按活文档面标定的上限去比
    等于要求判据回答它没标定过的问题 ⇒ 拒绝出读数，而不是"红得莫名"或"绿得莫名"。"""
    if gate and all_faces:
        return ("--gate 与 --all-faces 互斥：棘轮上限 %d 按默认活文档面口径标定，"
                "存档面拉进判定面后是另一个宇宙（实测 25 → 38 条）⇒ 拒绝在这个组合上出读数"
                % VERDICT_GAP_CEILING)
    return None


def judge(doc_paths, tracked_set, disk_set, tracked_dirs=None,
          daily_logs_ignored=None, proposal_prefix=PROPOSAL_DOC_PREFIX):
    """doc_paths = {文档: [点名路径]}。返回 (诊断条目, 检查过的路径数)。
    非 tracked 的才进诊断；disk_set 用来区分「在工作树磁盘上」与「都没有」；都没有时先问一次
    find_moved，有搬家证据就落 moved（P5），否则落 missing。
    tracked_dirs 提供时，目录形态的落点也按「跟踪面隐含目录」判定（防已跟踪目录被误报），
    并与跟踪文件一起构成 moved 的宇宙。
    daily_logs_ignored / proposal_prefix 透传给 P8/P9 设计性排除，**仅供 selftest 注入夹具与变异对照**；
    main 走默认值（现读 .gitignore / 用 PROPOSAL_DOC_PREFIX）。
    条目 (文档, 路径, 态, 处置话术, 面, 搬家候选)；第 5 位是**面**（"活文档"/"存档面"）——
    判定红只数活文档面那一档，且 moved 不入判定面（第 6 位对非 moved 条目恒为空列表）。"""
    tracked_dirs = tracked_dirs or set()
    moved_universe = set(tracked_set) | set(tracked_dirs)
    findings = []
    n = 0
    for doc in sorted(doc_paths):
        face = "存档面" if is_archive_doc(doc) else "活文档"
        for p in doc_paths[doc]:
            n += 1
            if p in tracked_set or p in tracked_dirs:
                continue
            # 磁盘判定用「精确命中 OR 有子路径」：目录条目可能没进 disk_set（调用方只收了文件），
            # 但 `src/claimguard/xxx.mbt` 的存在足以证明 `src/claimguard` 在工作树里。
            on_disk = p in disk_set or any(x.startswith(p + "/") for x in disk_set)
            if on_disk:
                findings.append((doc, p, "on-disk",
                                 "**实现已在工作树磁盘上、只是没进跟踪面** ⇒ 出路是 `git add` 并提交", face, []))
                continue
            # P7 豁免：外部宿主 / `_` 前缀临时件只替换 missing（on-disk 已优先，见上）。
            ex = exempt_reason(p)
            if ex:
                findings.append((doc, p, ex[0], ex[1], face, []))
                continue
            # P8/P9 设计性排除：gitignore 的日日志面 / 提案面。同样只替换 missing。
            dx = design_exempt_reason(p, doc, daily_logs_ignored=daily_logs_ignored,
                                      proposal_prefix=proposal_prefix)
            if dx:
                findings.append((doc, p, dx[0], dx[1], face, []))
                continue
            mv = find_moved(p, moved_universe)
            if mv:
                findings.append((doc, p, "moved",
                                 "跟踪面存在同名件、父目录在点名父目录之下 ⇒ 事实是**搬家**（多为归档之后），"
                                 "不是未落地。实际位置见本条候选；moved 只证同名+前缀、不证同一份内容，由人确认",
                                 face, mv))
            else:
                findings.append((doc, p, "missing",
                                 "跟踪面与磁盘都没有 ⇒ 若计划已说'已完成'则是**虚报**；若说'将新增'则属正常未做",
                                 face, []))
    return findings, n


def split_faces(findings, all_faces):
    """(判定面, 搬家态, 豁免态, 存档面)。moved **恒不进判定面**（P5），P7 的 external/scratch 与
    P8/P9 的 ignored-log/proposal 同样只出数不判红；`--all-faces` 只把存档面拉进判定面。
    抽成纯函数是为了让「搬家态不判红」「豁免态/设计性排除不判红」这些律都有夹具，
    而不是只活在 main 的某一次打印里。"""
    # 不进判定面的态：moved(P5) + external/scratch(P7) + ignored-log/proposal(P8/P9)
    NON_VERDICT = ("moved", "external", "scratch", "ignored-log", "proposal")
    pool = findings if all_faces else [x for x in findings if x[4] == "活文档"]
    moved = [x for x in pool if x[2] == "moved"]
    exempt = [x for x in pool if x[2] in ("external", "scratch", "ignored-log", "proposal")]
    live = [x for x in pool if x[2] not in NON_VERDICT]
    archived = [x for x in findings if x[4] == "存档面"]
    return live, moved, exempt, archived


def verdict_rc(live_n, over, gate):
    """判定面退出码。两种口径，都不产 2（2 只留给「判据无法自证」的 FATAL）：
      诊断口径（默认）：判定面非空即 1 —— 计划里写"新增尚不存在的文件"是合法的，这个 1 不代表门禁该红。
      门禁口径（--gate）：只看棘轮 ⇒ 超限 1、在上限内 0，即 BUG-367 ④ 那句「存量按声明接受、增量必须归零」。
    把两种口径分开的代价是零：判定面数字与 moved 数在两种模式下都照样打印。"""
    if gate:
        return 1 if over else 0
    return 1 if live_n else 0


def selftest():
    cells = []

    def cell(name, got, want):
        cells.append((name, bool(got) == bool(want), "got=%s want=%s" % (got, want)))

    # 1) 抽取口径：反引号 + 仓内顶层目录 + 已知扩展名 ⇒ 认
    got = extract_paths("见 `src/a/b.mbt` 与 `scripts/x.py`，以及 `docs/y.md`。")
    cell("extract-basic", got == ["src/a/b.mbt", "scripts/x.py", "docs/y.md"], True)
    print("  ok  extract-basic（认三种仓内路径）")

    # 2) 不认绝对路径 / 不认非仓内顶层 / 不认裸命令名（防误报）
    got2 = extract_paths("`/abs/x.mbt`、`other/x.mbt`、`moon check`、`FIST_WEB_PORT`")
    cell("extract-rejects-foreign", got2 == [], True)
    print("  ok  extract-rejects-foreign（绝对路径/非仓内/裸命令名都不认）")

    # 2c) **模板/占位形态不认**（全仓扫描实测的误捕面：12 条 `docs/<tool>-skill.md`、`memory/research/*.md`）
    got2c = extract_paths("按 `docs/<tool>-skill.md` 写文档；归档到 `memory/research/*.md`；示例放 `docs/examples/<lang>/`")
    cell("extract-rejects-placeholder", got2c == [], True)
    print("  ok  extract-rejects-placeholder（`<...>`/`*` 形态说明不认——它不是落点）")

    # 2d) **日期/变量形态**同属说明不是落点（R40 实测的第二批噪音：8 条）。
    got2d = extract_paths("日志写 `memory/YYYY-MM-DD.md`；脉冲写 `memory/reviews/yyyyMMdd.HH.mm.ss.md`；"
                          "路由表 `memory/model-router-caf-{ns}.json`")
    cell("extract-rejects-date-shape", got2d == [], True)
    print("  ok  extract-rejects-date-shape（YYYY/yyyyMMdd/{ns} 形态不认）")

    # 2e) 反证：形态被排除但**必须出数**（静默丢弃=数字凭空少，无人能查少的是噪音还是缺陷）
    paths, shapes = extract_paths(
        "落点 `src/real/file.mbt`；形态 `memory/YYYY-MM-DD.md`；形态 `docs/<tool>-skill.md`",
        with_shapes=True)
    cell("shape-notes-are-counted",
         paths == ["src/real/file.mbt"] and len(shapes) == 2, True)
    print("  ok  shape-notes-are-counted（1 条落点入比对 + 2 条形态单独出数，一个都不静默丢）")

    # 2f) **「路径:行号」剥后缀**（R40 实测的虚报面：`src/server/mcpcf_embed.mbt:108/121/134`
    #     整串当路径 ⇒ basename="134" 不含点、过了 base_ok ⇒ 已跟踪文件被报 missing）。
    got2f = extract_paths("详见 `src/server/mcpcf_embed.mbt:108/121/134` 与 "
                          "`plugins/source/references/omega-verification.md:33/60/65/68`")
    cell("extract-strips-line-suffix",
         got2f == ["src/server/mcpcf_embed.mbt", "plugins/source/references/omega-verification.md"], True)
    print("  ok  extract-strips-line-suffix（`:108/121/134` 剥掉后再比跟踪面）")
    # 反证：行号后缀剥离不能把真落点也吞掉（同一串里既有带行号又有不带的）
    got2g = extract_paths("`src/a/b.mbt:12` 与 `src/c/d.mbt`")
    cell("line-suffix-keeps-plain-paths", got2g == ["src/a/b.mbt", "src/c/d.mbt"], True)
    print("  ok  line-suffix-keeps-plain-paths（带/不带行号的两条都认，且不因剥后缀去重合并）")

    # 2b) 绝对路径单独一格（变异实测发现上面那格抓不住"绝对路径拦截被去掉"：
    #     因为去掉拦截后 `/abs/x.mbt` 仍不以 TOP_DIRS 开头 ⇒ 被下一道闸拦掉，格仍绿）
    got2b = extract_paths("`/src/a/b.mbt`")
    cell("extract-rejects-abs-only", got2b == [], True)
    print("  ok  extract-rejects-abs-only（`/src/...` 绝对路径必须被拦 —— 否则会误认成仓内）")

    # 3) 目录形态（尾部斜杠）认，且去掉斜杠后比对
    got3 = extract_paths("新增 `src/claimguard/` 包")
    cell("extract-dir-form", got3 == ["src/claimguard"], True)
    print("  ok  extract-dir-form（目录形态去斜杠）")

    # 4) 干净输入：路径都在跟踪面 ⇒ 0 诊断
    f, n = judge({"d.md": ["src/a.mbt"]}, {"src/a.mbt"}, set())
    cell("clean-no-findings", len(f) == 0 and n == 1, True)
    print("  ok  clean-no-findings（%d 条路径，0 诊断）" % n)

    # 5) 合成违例一：在磁盘、不在跟踪面 ⇒ on-disk（工作树有、未提交）
    f, n = judge({"d.md": ["src/x.mbt"]}, set(), {"src/x.mbt"})
    cell("on-disk-detected", len(f) == 1 and f[0][2] == "on-disk", True)
    print("  ok  on-disk-detected（磁盘有、跟踪面无 ⇒ 报'出路是 git add'）")

    # 6) 合成违例二：都不在 ⇒ missing
    f, n = judge({"d.md": ["src/y.mbt"]}, set(), set())
    cell("missing-detected", len(f) == 1 and f[0][2] == "missing", True)
    print("  ok  missing-detected（都没有 ⇒ 报 missing）")

    # 6a) **P4 分面**：同一条 missing，写在存档面文档里 ⇒ 面=「存档面」（只报不判），
    #     写在活文档里 ⇒ 面=「活文档」（计入退出码）。56 条实测读数里 17 条属前者。
    f, n = judge({"docs/archive/2026-10-11-plan.md": ["src/never.mbt"],
                  "docs/plan-live.md": ["src/never2.mbt"]}, set(), set())
    live = [x for x in f if x[4] == "活文档"]
    arch = [x for x in f if x[4] == "存档面"]
    cell("face-split", len(live) == 1 and len(arch) == 1, True)
    print("  ok  face-split（同形状按文档所在面分档：活文档 %d 条 / 存档面 %d 条）" % (len(live), len(arch)))
    # 反证：只有存档面有未落地时，判定档为空 ⇒ 不判红（但条目仍在，不静默消失）
    f2, _ = judge({"docs/archive/2026-10-11-plan.md": ["src/never.mbt"]}, set(), set())
    cell("archive-only-not-verdict", len(f2) == 1 and not [x for x in f2 if x[4] == "活文档"], True)
    print("  ok  archive-only-not-verdict（存档面独红 ⇒ 判定档空，条目照报）")
    cell("archive-prefix-not-overbroad",
         is_archive_doc("docs/superpowers/plans/2026-09-24-x.md") is False
         and is_archive_doc("docs/archive/x.md") is True, True)
    print("  ok  archive-prefix-not-overbroad（白名单只收名字自称存档的两族，旧但不自称的留活面）")

    # 6b) 目录判定（首跑实测抓到的自身缺陷）：已跟踪目录不许被误报。
    #     变异实测正是靠这格把「disk_set 只收文件 / tracked_dirs 不生效」抓住。
    td = build_tracked_dirs({"src/diff/diff.mbt", "cmd/cli/main.mbt"})
    cell("tracked-dirs-derived", {"src", "src/diff", "cmd", "cmd/cli"} <= td, True)
    print("  ok  tracked-dirs-derived（从跟踪文件反解隐含目录：%d 个）" % len(td))
    f, n = judge({"d.md": ["src/diff"]}, {"src/diff/diff.mbt"}, set(), td)
    cell("tracked-dir-not-reported", len(f) == 0, True)
    print("  ok  tracked-dir-not-reported（已跟踪目录不误报）")
    # 目录在磁盘、未跟踪 ⇒ 仍报 on-disk。注意 disk_set 里要放**目录条目本身**
    # （主流程的 os.walk 会把目录也收进 disk_set，故这里模拟真实形态）。
    f, n = judge({"d.md": ["src/claimguard"]}, set(), {"src/claimguard"}, set())
    cell("untracked-dir-on-disk", len(f) == 1 and f[0][2] == "on-disk", True)
    print("  ok  untracked-dir-on-disk（目录在磁盘未跟踪 ⇒ 报 on-disk）")

    # 7) 防空转：零路径 ⇒ 由 main 自拒；这里只考 judge 的 n 计数不漏
    f, n = judge({"d.md": []}, set(), set())
    cell("empty-doc-counts-zero", n == 0, True)
    print("  ok  empty-doc-counts-zero（空文档 n=0，供 main 判空转）")

    # 8) P5 搬家态：同名 + 父目录前缀 ⇒ moved，且**不静默消失**（第 6 位给实际位置）
    f, n = judge({"a.md": ["docs/x.md"]}, {"docs/archive/x.md"}, set())
    cell("moved-detected", len(f) == 1 and f[0][2] == "moved" and f[0][5] == ["docs/archive/x.md"], True)
    print("  ok  moved-detected（docs/x.md 点名、真身在 docs/archive/x.md ⇒ 报搬家并给实际位置）")
    # 反证①：父目录不构成前缀 ⇒ 不许认搬家（这是"宽口径豁免"的第一步，BUG-365 的免检牌形状）
    f2, _ = judge({"a.md": ["docs/super/x.md"]}, {"reports/x.md"}, set())
    cell("moved-rejects-nonprefix-parent", len(f2) == 1 and f2[0][2] == "missing", True)
    print("  ok  moved-rejects-nonprefix-parent（同名但父目录不相干 ⇒ 仍 missing）")
    # 反证②：搬进更深层子目录仍算搬家（前缀含 "/"，防 `docs` 匹配 `docsxyz` 那种串面误判）
    f3, _ = judge({"a.md": ["docs/x.md"]}, {"docs/archive/old/x.md"}, set())
    cell("moved-deeper-subdir", len(f3) == 1 and f3[0][2] == "moved", True)
    print("  ok  moved-deeper-subdir（搬进 docs/archive/old/ 仍认搬家）")
    # 反证③：点名在顶层（无父目录）⇒ 不认搬家（引用没写目录是文档口径问题，工具不替人猜）
    f4, _ = judge({"a.md": ["x.md"]}, {"docs/x.md"}, set())
    cell("moved-rejects-top-level-ref", len(f4) == 1 and f4[0][2] == "missing", True)
    print("  ok  moved-rejects-top-level-ref（顶层点名 x.md 不认搬家）")
    # 反证④：搬家不许吃掉 on-disk（点名处自己就在磁盘上 ⇒ 出路仍是 git add）
    f5, _ = judge({"a.md": ["docs/x.md"]}, {"docs/archive/x.md"}, {"docs/x.md"})
    cell("moved-does-not-eat-on-disk", len(f5) == 1 and f5[0][2] == "on-disk", True)
    print("  ok  moved-does-not-eat-on-disk（磁盘上有点名处本体 ⇒ 优先报 on-disk）")
    # 反证⑤：候选只来自跟踪面；磁盘上未跟踪的同名件不算搬家证据
    f6, _ = judge({"a.md": ["docs/x.md"]}, set(), {"docs/archive/x.md"})
    cell("moved-rejects-untracked-candidate", len(f6) == 1 and f6[0][2] == "missing", True)
    print("  ok  moved-rejects-untracked-candidate（未跟踪同名件不给搬家态）")
    # 目录形态也能搬家（宇宙里放跟踪面隐含目录）
    td2 = build_tracked_dirs({"docs/archive/plans/p.md"})
    f7, _ = judge({"a.md": ["docs/plans"]}, {"docs/archive/plans/p.md"}, set(), td2)
    cell("moved-dir-form", len(f7) == 1 and f7[0][2] == "moved", True)
    print("  ok  moved-dir-form（目录形态点名 docs/plans → docs/archive/plans 认搬家）")

    # 9) P5 的下游：搬家态不进判定面（split_faces 是纯函数，故这条律有夹具而非只在打印里）
    mixed = [("l.md", "docs/x.md", "moved", "", "活文档", ["docs/archive/x.md"]),
             ("l.md", "src/gone.mbt", "missing", "", "活文档", []),
             ("l.md", "src/adapter.js", "external", "", "活文档", []),
             ("docs/archive/o.md", "docs/y.md", "moved", "", "存档面", ["docs/archive/y.md"])]
    live, mv, ex, arch = split_faces(mixed, False)
    cell("split-moved-out-of-verdict", len(live) == 1 and len(mv) == 1 and len(ex) == 1 and len(arch) == 1, True)
    print("  ok  split-moved-out-of-verdict（判定面只留 missing %d 条，搬家 %d 条、豁免 %d 条单列）"
          % (len(live), len(mv), len(ex)))
    live_a, mv_a, ex_a, _ = split_faces(mixed, True)
    cell("all-faces-still-excludes-moved",
         len(mv_a) == 2 and len(ex_a) == 1 and not [x for x in live_a if x[2] in ("moved", "external", "scratch")],
         True)
    print("  ok  all-faces-still-excludes-moved（--all-faces 拉进存档面也不拉搬家态/豁免态：%d 条仍单列）"
          % (len(mv_a) + len(ex_a)))

    # 9c) P8/P9 设计性排除（2026-10-26 路 B）：**成对验证** —— 命中格 + 变异对照格（判例-29/30）
    #
    # 变异对照的做法：**注入** daily_logs_ignored False / proposal_prefix ""（而不是改文档、也不是改常量），
    # 这样「排除真在起作用」与「排除失效后条目真的回来」两侧都是同一份代码在同一格里算出来的
    # ⇒ 不是「机制格」，是**实现路径格**（判例-29）。
    f10, _ = judge({"a.md": ["memory/2026-10-12.md"]}, set(), set(),
                   daily_logs_ignored=True)
    cell("p8-ignored-log-detected", len(f10) == 1 and f10[0][2] == "ignored-log", True)
    print("  ok  p8-ignored-log-detected（被 gitignore 的日日志 ⇒ ignored-log 态，不进判定面）")
    # 变异对照 1：注入 daily_logs_ignored=False（模拟「.gitignore 规则被移除」）⇒ 必须回到 missing
    f11, _ = judge({"a.md": ["memory/2026-10-12.md"]}, set(), set(),
                   daily_logs_ignored=False)
    cell("p8-mutation-disabled-falls-back-to-missing",
         len(f11) == 1 and f11[0][2] == "missing", True)
    print("  ok  p8-mutation-disabled-falls-back-to-missing"
          "（变异：关掉 gitignore 判定 ⇒ 该条**重新计入**判定面，证排除真在起作用）")

    f12, _ = judge({"docs/proposals/p.md": ["docs/foo-skill.md"]}, set(), set(),
                   daily_logs_ignored=True)
    cell("p9-proposal-detected", len(f12) == 1 and f12[0][2] == "proposal", True)
    print("  ok  p9-proposal-detected（docs/proposals/ 下的点名 ⇒ proposal 态，不进判定面）")
    # 变异对照 2：注入 proposal_prefix=""（模拟「排除被删掉」）⇒ 必须回到 missing
    f13, _ = judge({"docs/proposals/p.md": ["docs/foo-skill.md"]}, set(), set(),
                   daily_logs_ignored=True, proposal_prefix="")
    cell("p9-mutation-prefix-removed-falls-back-to-missing",
         len(f13) == 1 and f13[0][2] == "missing", True)
    print("  ok  p9-mutation-prefix-removed-falls-back-to-missing"
          "（变异：删掉 proposals 排除 ⇒ 该条**重新计入**判定面）")

    # 反证（防两条排除开成「大面免检牌」）：
    # ① 非日日志形态的 memory/ 件**不许**被 P8 吃掉（memory/lock-config.json 仍是 missing/待判）
    f14, _ = judge({"a.md": ["memory/lock-config.json"]}, set(), set(),
                   daily_logs_ignored=True)
    cell("p8-not-overbroad-non-daily-log", len(f14) == 1 and f14[0][2] != "ignored-log", True)
    print("  ok  p8-not-overbroad-non-daily-log（memory/lock-config.json 非日日志 ⇒ 不被 P8 排除）")
    # ② 非 proposals/ 目录下的提案式名字**不许**被 P9 吃掉（docs/proposal-x.md 不在前缀内）
    f15, _ = judge({"docs/proposal-x.md": ["docs/foo-skill.md"]}, set(), set(),
                   daily_logs_ignored=True)
    cell("p9-not-overbroad-non-proposal-dir", len(f15) == 1 and f15[0][2] != "proposal", True)
    print("  ok  p9-not-overbroad-non-proposal-dir（docs/proposal-x.md 不在 proposals/ 前缀内 ⇒ 不被 P9 排除）")
    # ③ 两态都必须**不进判定面**（split_faces 是纯函数，这条律要有夹具而非只活在打印里）
    mixed2 = [("l.md", "memory/2026-10-12.md", "ignored-log", "", "活文档", []),
              ("docs/proposals/p.md", "docs/foo-skill.md", "proposal", "", "活文档", []),
              ("l.md", "src/gone.mbt", "missing", "", "活文档", [])]
    live2, mv2, ex2, _ = split_faces(mixed2, False)
    cell("split-p8p9-out-of-verdict",
         len(live2) == 1 and len(ex2) == 2 and live2[0][1] == "src/gone.mbt", True)
    print("  ok  split-p8p9-out-of-verdict（判定面只留真正 missing 的 1 条，P8/P9 那 2 条进豁免态）")

    # 9d) P8 的真源自证：`.gitignore` 现读结果本身也要能考（不写死 True）
    cell("p8-gitignore-read-from-truth",
         isinstance(_gitignore_excludes_daily_logs(), bool), True)
    print("  ok  p8-gitignore-read-from-truth（排除依据是**现读 .gitignore**，不是写死常量）")

    # 9b) P7 豁免：外部宿主精确名单 / scripts/ `_` 前缀 ⇒ external/scratch，只出数不判红
    f8, _ = judge({"a.md": ["src/adapter.js"]}, set(), set())
    cell("external-detected", len(f8) == 1 and f8[0][2] == "external", True)
    print("  ok  external-detected（src/adapter.js 属外部宿主 ⇒ external 态）")
    f9, _ = judge({"a.md": ["scripts/_ai_prompt.md"]}, set(), set())
    cell("scratch-detected", len(f9) == 1 and f9[0][2] == "scratch", True)
    print("  ok  scratch-detected（scripts/_ai_prompt.md 属一次性临时件 ⇒ scratch 态）")
    # 反证①：豁免名单外 src/*.js 仍报 missing（不给整目录/后缀开免检牌）
    fa, _ = judge({"a.md": ["src/foo.js"]}, set(), set())
    cell("exempt-not-overbroad-external", len(fa) == 1 and fa[0][2] == "missing", True)
    print("  ok  exempt-not-overbroad-external（src/foo.js 不在名单 ⇒ 仍 missing）")
    # 反证②：scripts/ 下非 `_` 前缀仍报 missing
    fb, _ = judge({"a.md": ["scripts/normal.py"]}, set(), set())
    cell("exempt-not-overbroad-scratch", len(fb) == 1 and fb[0][2] == "missing", True)
    print("  ok  exempt-not-overbroad-scratch（scripts/normal.py 无 `_` 前缀 ⇒ 仍 missing）")
    # 反证③：豁免不抢 on-disk（点名处自己在磁盘 ⇒ 优先报 on-disk，P7 只替换 missing）
    fc, _ = judge({"a.md": ["src/adapter.js"]}, set(), {"src/adapter.js"})
    cell("exempt-does-not-eat-on-disk", len(fc) == 1 and fc[0][2] == "on-disk", True)
    print("  ok  exempt-does-not-eat-on-disk（豁免件点名处自己在磁盘 ⇒ 仍报 on-disk）")

    # 10) P6 棘轮：只许降；超限并红、有余量只给建议
    over, txt = ratchet(26, 25)
    cell("ratchet-over", over is True and "超限" in txt and "1" in txt, True)
    print("  ok  ratchet-over（26 > 25 ⇒ 并红并写明多出几条）")
    over, txt = ratchet(24, 25)
    cell("ratchet-under-hint-only", over is False and "收紧" in txt, True)
    print("  ok  ratchet-under-hint-only（24 < 25 ⇒ 只给收紧建议、不并红）")
    over, txt = ratchet(25, 25)
    cell("ratchet-equal-silent", over is False and txt == "", True)
    print("  ok  ratchet-equal-silent（相等时不产任何噪声）")

    # 11) 两种退出码口径：诊断非空即 1；门禁只看棘轮 ⇒ 存量 0、增量 1；两者都不产 2
    cell("rc-diag-nonempty-1", verdict_rc(25, False, False) == 1, True)
    cell("rc-diag-empty-0", verdict_rc(0, False, False) == 0, True)
    cell("rc-gate-stock-0", verdict_rc(25, False, True) == 0, True)
    cell("rc-gate-over-1", verdict_rc(26, True, True) == 1, True)
    cell("rc-never-2-from-verdict",
         all(verdict_rc(k, o, g) in (0, 1) for k in (0, 25, 26) for o in (False, True) for g in (False, True)), True)
    print("  ok  rc-口径 4 格 + 不产 2（诊断/门禁各自成立，2 只留给 FATAL）")

    # 12) 上限常量与本轮实测存量的关系：不许把上限写成小于已知存量（那等于一落地就假红）
    cell("ceiling-not-below-known-stock", VERDICT_GAP_CEILING >= 18, True)
    print("  ok  ceiling-not-below-known-stock（VERDICT_GAP_CEILING=%d ≥ 本轮实测存量 18（A 档））" % VERDICT_GAP_CEILING)

    # 13) P2 防空转三条各给因由，且顺序固定（枚举 → 可读 → 条数）
    cell("fatal-no-docs-enum", (fatal_reason(0, 0, 0) or "").startswith("一份文档都没枚举到"), True)
    cell("fatal-none-readable", (fatal_reason(3, 0, 0) or "").startswith("一份计划文档都读不到"), True)
    cell("fatal-zero-paths", (fatal_reason(3, 3, 0) or "").startswith("全仓计划文档里一条"), True)
    cell("fatal-clean-gives-no-reason", fatal_reason(3, 3, 25) is None, True)
    print("  ok  fatal-* 4 格（三种空转各有各的因由，干净时不给理由；FATAL 由 main 出 rc=2）")

    # 14) 模式互斥：--gate 与 --all-faces 同给 = 要求判据回答它没标定过的问题
    cell("mode-gate-with-allfaces-refused", "互斥" in (mode_fatal(True, True) or ""), True)
    cell("mode-other-combos-ok",
         mode_fatal(True, False) is None and mode_fatal(False, True) is None and mode_fatal(False, False) is None, True)
    print("  ok  mode-* 2 格（互斥组合自拒，其余三种照常出读数）")

    # 15) FATAL 出口必须给**整数** 2：改前三处 `raise SystemExit("FATAL …")` 实际给 1（带字符串的
    #     SystemExit 退出码恒为 1），docstring 承诺的 rc=2 从未生效。这一格钉的是出口，不是文案。
    cell("fatal-exit-code-is-2",
         emit_fatal("（selftest 夹具：这行是 FATAL 出口的自证打印，打到 stderr，不是违例）") == 2, True)
    print("  ok  fatal-exit-code-is-2（emit_fatal 恒返 2 —— 改前那条幻影在退出码面上读不出来）")

    bad = [(nm, why) for nm, ok, why in cells if not ok]
    if bad:
        print("SELFTEST FAIL：")
        for nm, why in bad:
            print("  - %s：%s" % (nm, why))
        sys.exit(1)  # NO_CALL_FACE J2
    print("SELFTEST OK（%d 格：抽取口径 9 格（`<…>`/`*` 形态、日期与变量占位、形态出数反证、"
          "「路径:行号」剥离 + 同串正反证、绝对路径、目录形态、非仓内）/ 干净不误报 / on-disk 必报 / "
          "missing 必报 / 跟踪目录反解 3 格 / P4 分面 3 格 / 空转计数 / P5 搬家 7 格（检出、深层子目录仍认、"
          "父目录不相干/顶层点名/抢白 on-disk/未跟踪候选 4 条反证、目录形态搬家）/ 搬家+豁免不进判定面 2 格 / "
          "P7 豁免 6 格（external/scratch 检出、名单外/非 `_` 前缀 2 条反证、不抢 on-disk 反证）/ "
          "P6 棘轮 3 格 / 退出码两口径 5 格 / 上限常量 1 格 / P2 空转三条 4 格 / 模式互斥 2 格 / FATAL 出口码 1 格）"
          % len(cells))
    sys.exit(0)  # NO_CALL_FACE J2


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--all-faces", action="store_true",
                    help="存档面（docs/archive/、reports/）的未落地落点也计入退出码；默认只报不判")
    ap.add_argument("--gate", action="store_true",
                    help="门禁口径：退出码只看棘轮（判定面 ≤ VERDICT_GAP_CEILING ⇒ 0，超限 ⇒ 1）；"
                         "不带此开关时是只读诊断（判定面非空即 1，不代表门禁该红）")
    ap.add_argument("docs", nargs="*")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    mf = mode_fatal(args.gate, args.all_faces)
    if mf:
        return emit_fatal(mf)

    files = tracked()
    tracked_set = set(files)
    tracked_dirs = build_tracked_dirs(tracked_set)

    if args.docs:
        docs = [d.replace("\\", "/") for d in args.docs]
    else:
        docs = [f for f in files if f.startswith("docs/") and f.endswith(".md")]

    doc_paths = {}
    shape_notes = []
    for d in docs:
        p = os.path.join(ROOT, d)
        if not os.path.isfile(p):
            continue
        with open(p, encoding="utf-8", errors="replace") as f:
            paths, shapes = extract_paths(f.read(), with_shapes=True)
        doc_paths[d] = paths
        for s in shapes:
            if s not in shape_notes:
                shape_notes.append(s)

    disk_set = set()
    for dp, dn, fn in os.walk(ROOT):
        if any(x in dp for x in (".git", "_build", "node_modules", ".mooncakes", "temp")):
            continue
        for f in fn:
            disk_set.add(os.path.relpath(os.path.join(dp, f), ROOT).replace("\\", "/"))
        # 目录也要进集合：计划里点名的常常是**目录**（如 `src/diff`、`cmd/cli`、`scripts/blackbox`）。
        # 首跑实测抓到的自身缺陷：只收集文件 ⇒ 这些存在的目录被误报 missing（82 条里占了不少）。
        for d in dn:
            disk_set.add(os.path.relpath(os.path.join(dp, d), ROOT).replace("\\", "/"))

    findings, n = judge(doc_paths, tracked_set, disk_set, tracked_dirs)
    # 三条空转判据收进 fatal_reason 一次出（顺序=枚举→可读→条数）。原来这里是两处
    # `raise SystemExit("FATAL …")`，实测发现那样只会给出 rc=1 ⇒ docstring 承诺的 rc=2 是幻影。
    fr = fatal_reason(len(docs), len(doc_paths), n)
    if fr:
        return emit_fatal(fr)

    live, moved, exempt, archived = split_faces(findings, args.all_faces)
    if args.all_faces:
        # 上限是按**默认活文档面**标定的；--all-faces 把存档面拉进判定面后是另一个宇宙（实测 25 → 38）。
        # 这里不比对、只说明 —— 拿没标定过的口径去判红，和红得莫名是同一件事。
        over = False
        rnote = ("棘轮本模式不比对：上限 %d 按默认活文档面口径标定，--all-faces 下的判定面不是那个宇宙"
                 % VERDICT_GAP_CEILING)
    else:
        over, rnote = ratchet(len(live), VERDICT_GAP_CEILING)
    rc = verdict_rc(len(live), over, args.gate)
    # 只报未落地的（tracked 是常态）；搬家态按 P5 单列，不进判定面
    if not live:
        extra = ""
        if archived and not args.all_faces:
            extra = "；存档面另有 %d 条只报不判（--all-faces 可计入）" % len(archived)
        if moved:
            extra += "；另有搬家态 %d 条单独出数（P5，不判红）" % len(moved)
        if exempt:
            extra += "；另有豁免态 %d 条单独出数（P7，外部宿主/临时件不判红）" % len(exempt)
        print("PASS 计划落点核对：%d 份文档的 %d 条仓内点名路径**全部在跟踪面**（形态说明 %d 条不认作落点、单独出数）%s"
              % (len(doc_paths), n, len(shape_notes), extra))
        for doc, p, kind, hint, face, mv in sorted(moved, key=lambda x: (x[1], x[0])):
            print("  - [moved] %s 点名 `%s` → 跟踪面实际位置 %s" % (doc, p, "、".join(mv)))
        return rc

    on_disk = [x for x in live if x[2] == "on-disk"]
    missing = [x for x in live if x[2] == "missing"]
    print("INFO 计划落点核对（%d 份文档、%d 条点名路径、形态说明 %d 条已出数不比对）："
          "判定面未在跟踪面 %d 条（磁盘上有 %d 条、都没有 %d 条）；搬家态另有 %d 条单列入 P5、不进判定面；"
          "豁免态 %d 条单列入 P7、不进判定面；%s"
          % (len(doc_paths), n, len(shape_notes), len(live), len(on_disk), len(missing), len(moved),
             len(exempt),
             ("存档面 %d 条已按 --all-faces 计入判定面" % len(archived)) if args.all_faces
             else ("存档面另有 %d 条只报不判" % len(archived))))
    if rnote:
        print("  %s%s" % (rnote, "" if args.all_faces
                          else "（上限 VERDICT_GAP_CEILING=%d，只许降）" % VERDICT_GAP_CEILING))
    for doc, p, kind, hint, face, mv in sorted(live, key=lambda x: (x[2] != "on-disk", x[0], x[1])):
        print("  - [%s] %s 点名 `%s` ——%s" % (kind, doc, p, hint))
    if moved:
        print("  …搬家态（P5：跟踪面有同名件、其父目录在点名父目录之下 ⇒ 不判红，但逐条给实际位置）%d 条："
              % len(moved))
        for doc, p, kind, hint, face, mv in sorted(moved, key=lambda x: (x[1], x[0])):
            print("  - [moved] %s 点名 `%s` → 跟踪面实际位置 %s" % (doc, p, "、".join(mv)))
    if exempt:
        print("  …豁免态（P7：外部宿主 / `_` 前缀临时件 ⇒ 只出数不判红）%d 条："
              % len(exempt))
        for doc, p, kind, hint, face, mv in sorted(exempt, key=lambda x: (x[1], x[0])):
            print("  - [%s] %s 点名 `%s` ——%s" % (kind, doc, p, hint))
    if archived and not args.all_faces:
        print("  …存档面（docs/archive/、reports/）%d 条，分布在 %d 份文档：%s"
              % (len(archived), len({x[0] for x in archived}),
                 " ".join(sorted({x[0] for x in archived}))[:200]))
    if shape_notes:
        print("  …形态说明（`<…>`/`*`/日期/变量占位，R40 起单独出数、不参与跟踪面比对）%d 条：%s"
              % (len(shape_notes), " ".join(shape_notes)[:200]))
    if args.gate:
        print("注：**门禁口径**（--gate）——判定面在上限内即退出码 0（存量按声明接受、增量必须归零，BUG-367 ④），"
              "超限才给 1；不带 --gate 时本工具是只读诊断，判定面非空即 1，不代表门禁该红。")
    else:
        print("注：本工具是**只读诊断**（计划里写'新增尚不存在的文件'是合法的），退出码 1 只表示判定面有落点未落地，"
              "不代表门禁该红。")
    return rc


if __name__ == "__main__":
    sys.exit(main())
