# -*- coding: utf-8 -*-
"""BUG-93 判据：入口清单守卫（entry-list guard）。

要钉的失效形状：入口搬家（cmd/main → cmd/cli）后，脚本/文档/CI 仍指旧入口——
于是"E2E 全绿"测的是**不发布**的那棵入口，用户按文档跑的是另一棵。

真源不是硬编码：
  - 可执行入口清单 = 扫 `cmd/*/moon.pkg` 里带 `pkgtype(kind: "executable")` 的包；
  - 发布入口 = `scripts/blackbox/build_release.ps1` 里 `moon build --target … cmd/<pkg>` 的那个 `<pkg>`；
  - 退役入口 = 清单里除发布入口之外的项。
判据：现状面（脚本/文档/CI/根 .md/.mcp*.json/**根入库 .py**，历史面除外）不得引用任何退役入口。

BUG-118（本轮）：扫描面曾不含仓库根 .py ⇒ `watchdog_tick_cron.py` / `pipeline_tick_cron.py`
写死退役入口 `cmd/main/main.js`，本守卫却打印"退役入口引用 0 处"——判据盲区比违例更贵，
所以 --selftest 里给新扫面配了成对格子（真代码行必红 / 只改注释不许红）。

自证（--selftest）格子：合成违例必红 / 干净输入不误红 / 退役清单为空时判"判据空转"FATAL
（没有退役入口就没有可漏的东西，此时报绿是骗人——要么入口真的统一了、守卫该被删，
  要么发现逻辑坏了）/ R2 缺 serve 成对 / 根 .py 入面必红 / 根 .py 只改注释不误红 /
  根 .py 选取（入库才判、未入库点名、取不到 git 反向兜底）。
"""
import argparse, io, os, re, subprocess, sys

# BUG-138（BUG-58 同族）：守卫的红必须是判据红。Windows 默认 cp936 控制台上打印中文结论里的
# ⇒ 等字符会让 print 当场 UnicodeEncodeError——拿到 traceback 而不是 verdict，而且崩在结论行之前
# 留下的 rc 会被读成「缺陷在场」（判据自己的崩不许冒用被测的退出码）。CI 在 Linux UTF-8 下是无损 no-op。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.dirname(os.path.abspath(__file__)) + "/..")

# 历史面只追加，不参与"现状面不得引用退役入口"的判定（改写它们＝伪造历史）。
HISTORY_PREFIXES = ("memory/", "reports/", "docs/superpowers/")
HISTORY_FILES = ("CHANGELOG.md",)
# 退役入口自己的源码合法地写着"运行：moon run cmd/main"——那是它对自己的描述，不是外溢引用。
SELF_DIR_PREFIX = "cmd/"
RELEASE_BUILDER = os.path.join("scripts", "blackbox", "build_release.ps1")
SKIP_DIRNAME = ("__pycache__", ".git", "_build", "temp", "node_modules", "target")
SCAN_ROOTS = ("scripts", "docs", ".github", "templates", "stories", "plugins/source", "cmd")
SCAN_ROOT_FILES = lambda name: name.endswith(".md") or name.startswith(".mcp")
TEXT_EXT = (".py", ".md", ".ps1", ".sh", ".mbt", ".mjs", ".json", ".yaml", ".yml", ".txt")
# 仓库根也要判（BUG-118：扫描面曾不含根 .py ⇒ watchdog_tick_cron.py / pipeline_tick_cron.py
# 写死退役入口 cmd/main，本守卫照样打印"退役入口引用 0 处"——判据盲区，不是没事）。
ROOT_SCAN_EXT = (".py",)
TEMP_PREFIX = "_"          # 本仓约定：`_` 前缀＝临时/诊断脚本，用完即删（与 check_scripts_index 同口径）
DROPPED_ROOT_PY = []       # 每次 candidates() 刷新：仓库根**未入库**因而被放下的 .py（盲区必须可见）
PY_COMMENT_LINE = re.compile(r"^\s*#")   # 只放过**整行**注释（行尾注释连着代码仍判）——见 mentions() 的口径说明



def executable_entries(root):
    """cmd/*/moon.pkg 里声明为 executable 的包名（这就是"有哪些入口"的唯一盘面事实）。"""
    out = []
    cmddir = os.path.join(root, "cmd")
    if not os.path.isdir(cmddir):
        return out
    for name in sorted(os.listdir(cmddir)):
        pkg = os.path.join(cmddir, name, "moon.pkg")
        if not os.path.isfile(pkg):
            continue
        txt = io.open(pkg, encoding="utf-8", errors="replace").read()
        if re.search(r"pkgtype\(\s*kind:\s*\"executable\"\s*\)", txt):
            out.append(name)
    return out


def shipped_entry(root):
    """发布脚本真正 build 的那个 cmd 包——从 build_release.ps1 正文反解，不抄常量。"""
    p = os.path.join(root, RELEASE_BUILDER)
    if not os.path.isfile(p):
        return None
    txt = io.open(p, encoding="utf-8", errors="replace").read()
    m = re.search(r"moon\s+build\s+--target\s+\$?[A-Za-z_]*\s+cmd/([A-Za-z0-9_-]+)", txt)
    return m.group(1) if m else None


def tracked_root_py(root):
    """仓库根**已入库**的 .py 名清单；取不到 git ⇒ 返回 None（调用方反向兜底，绝不静默少判）。"""
    try:
        r = subprocess.run(["git", "ls-files"], cwd=root, capture_output=True,
                           text=True, encoding="utf-8", errors="replace", timeout=30)
    except Exception:
        return None
    if r.returncode != 0:
        return None
    out = set()
    for p in r.stdout.split("\n"):
        p = p.strip().replace("\\", "/")
        if p and "/" not in p and p.endswith(".py"):
            out.add(p)
    return out


def select_root_py(names, tracked):
    """从仓库根盘面文件名里挑出纳入判定的 .py（纯函数，selftest 直接钉这一格）。

    门是"是否入库"：本守卫判的是**现状面**——用户 clone 下来会拿到、会照着跑的那批文件。
    `execute_cron.py` / `_cron_*.py` 被 .gitignore:30-32 挡在仓外 ⇒ CI 的新鲜检出里根本没有它们，
    把本机临时件算进判据面就造出"本机红、CI 绿"两套口径（比漏判更坏：没人再信这条绿）。
    `_` 前缀另按本仓约定（临时脚本，与 check_scripts_index 同口径）永久豁免。
    tracked=None（取不到 git）时反向兜底：除 `_` 前缀外全判 ⇒ 宁可多判，绝不多绿。
    返回 (纳入的相对路径, 被放下的名字)。
    """
    pys = [n for n in names if n.endswith(ROOT_SCAN_EXT)]
    live = [n for n in pys if not n.startswith(TEMP_PREFIX)]
    if tracked is None:
        return list(live), []
    keep = [n for n in live if n in tracked]
    return keep, sorted(set(live) - set(keep))


def candidates(root):
    rels = []
    for base in SCAN_ROOTS:
        bdir = os.path.join(root, base)
        if not os.path.isdir(bdir):
            continue
        for dirpath, dirnames, filenames in os.walk(bdir):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRNAME]
            for fn in filenames:
                if not fn.endswith(TEXT_EXT):
                    continue
                rel = os.path.relpath(os.path.join(dirpath, fn), root).replace("\\", "/")
                rels.append(rel)
    for name in sorted(os.listdir(root)):
        fp = os.path.join(root, name)
        if os.path.isfile(fp) and SCAN_ROOT_FILES(name):
            rels.append(name)
    keep, dropped = select_root_py(sorted(os.listdir(root)), tracked_root_py(root))
    DROPPED_ROOT_PY[:] = dropped
    rels.extend(keep)
    return sorted(set(rels))


def mentions(rel, text, retired):
    """命中退役入口**且这行是可执行指向**（命令 / 产物路径）才算引用。

    为什么不做子串全量匹配：本仓的历史叙述合法地写着"moonc 当年对 cmd/main 输出 ESM"，
    那是事实陈述不是操作路径；把散文也算进来，守卫会逼着后人去改写叙述面（＝伪造历史）。
    反过来说：只认命令与路径形状，就意味着"退役入口出现在纯散文里"是本守卫**不覆盖**的
    范围（见下方 scope 自述），不是漏网即安全的结论。

    .py 的**整行注释**（行首 `#`）同一条口径豁免：注释不会被任何 shell 执行，
    把"解释搬家历史的注释"判红只会逼人删掉解释（历史面同理）。行尾注释**不豁免**——
    那一行的代码部分照样承重；`# cmd/main/main.js` 之外的一切形状照旧判。
    """
    hits = []
    is_py = rel.endswith(".py")
    for e in retired:
        needle = "cmd/" + e
        for i, line in enumerate(text.split("\n"), 1):
            norm = line.replace("\\", "/")
            if needle not in norm:
                continue
            if is_py and PY_COMMENT_LINE.match(norm):
                continue
            if not ACTIONABLE.search(norm):
                continue
            hits.append((needle, i, line.strip()[:110]))
    return hits


# 范围自述（J10 口径）：本守卫判的是"现状面的命令/产物路径是否仍指向退役入口"，
# 现状面 = SCAN_ROOTS 各目录 + 仓库根 .md/.mcp* + **仓库根已入库的 .py**（BUG-118 补的盲区，
# 未入库的根 .py 会在输出里点名"放倒了哪几份"，不静默）。
# 不检自身（夹具必须含违例样本，逐字出现退役入口＝必然命中），不判散文叙述、
# .py 的整行注释（`# ...`）、不判历史面（memory/ reports/ CHANGELOG.md）。
SELF_EXEMPT = ("scripts/check_entry_paths.py",)
ACTIONABLE = re.compile(
    r"moon\s+(build|run|check|test|info|fmt|package)|_build/|node\s|--target|\.(js|exe)\b")


def judge(root, retired, files):
    """纯判定：返回 (问题列表, 扫描面文件数, 命中明细)。"""
    if not retired:
        return (["判据空转：退役入口清单为空 ⇒ 本守卫无事可做。"
                 "入口若真已统一就该删掉本守卫，否则就是发现逻辑坏了。"], 0, [])
    problems, scanned, detail = [], 0, []
    for rel in files:
        if rel in HISTORY_FILES or rel.startswith(HISTORY_PREFIXES) or rel in SELF_EXEMPT:
            continue
        # 每个入口包自己的目录只许提自己（cmd/main/main.mbt 写 "moon run cmd/main" 是对的）
        m = re.match(r"^cmd/([A-Za-z0-9_-]+)/", rel)
        skip_self = m.group(1) if m else None
        p = os.path.join(root, rel)
        if not os.path.isfile(p):
            continue
        scanned += 1
        txt = io.open(p, encoding="utf-8", errors="replace").read()
        for needle, ln, snippet in mentions(rel, txt,
                                           [e for e in retired if e != skip_self]):
            problems.append("R1 %s:%d 引用退役入口 %s：%s" % (rel, ln, needle, snippet))
            detail.append((rel, ln, needle))
    return (problems, scanned, detail)


def collect_files(root):
    return candidates(root)


POPEN_SEG = re.compile(r"Popen\(\s*(\[[^]]{0,240}\])", re.S)


def launcher_serve_check(root, files):
    """R2：`Popen([...cli.js 产物...])` 的 argv 里必须出现 "serve" 字面量。

    为什么值得钉：cmd/main 裸跑＝直接起 server，cmd/cli 裸跑＝只打印 help。
    入口搬家只改路径不够——argv 少一个 serve，客户端拿到的第一行是
    `FIST-Mbt Help v0.3.0 (129 MCP tools)` 而不是 JSON-RPC 回执（本轮 scripts/mcp_smoke.py 实测）。
    范围声明：只看 Popen 的第一个列表字面量，不经 shell/变量间接传递的 argv 不在此列；
    它保证"这个启动点带了 serve"，不保证协议往返一定成功（那是巡回实测的活）。
    """
    problems = []
    for rel in files:
        if rel in SELF_EXEMPT:
            continue
        p = os.path.join(root, rel)
        if not rel.endswith(".py") or not os.path.isfile(p):
            continue
        txt = io.open(p, encoding="utf-8", errors="replace").read()
        if "cli.js" not in txt and "main.js" not in txt:
            continue
        for m in POPEN_SEG.finditer(txt):
            seg = m.group(1)
            if "MAIN" not in seg and "main_js" not in seg and ".js" not in seg:
                continue
            if "serve" in seg:
                continue
            ln = txt[:m.start()].count("\n") + 1
            problems.append("R2 %s:%d 启动 MCP 产物的 argv 未带 serve：%s" % (
                rel, ln, " ".join(seg.split())[:90]))
    return problems


ROOT_NAME = r"(?:ROOT|_FIST_ROOT|FIST_ROOT|REPO_ROOT|WORKDIR)"
BARE_ART = re.compile(r"""['"]((?:_build|target)/[^'"]*\.js)['"]""")
ART_VAR = re.compile(r"^\s*(\w+)\s*=\s*['\"](?:_build|target)/[^'\"]*\.js['\"]\s*$")
ART_LIST = re.compile(r"^\s*(\w+)\s*=\s*\[(.*?)\]", re.S)
LOOP_VAR = re.compile(r"^\s*for\s+(\w+)\s+in\s+(\w+)\s*:")
JOINED = re.compile(r"os\.path\.join\(\s*" + ROOT_NAME + r"\b")
CWD_ROOT = re.compile(r"cwd\s*=\s*" + ROOT_NAME + r"\b")
EXISTS_CALL = re.compile(r"os\.path\.(?:exists|isfile|stat)\(\s*([^()]*)\)")
SPAWN_LINE = re.compile(r"(?:Popen|subprocess\.(?:run|call|check_output|check_call))\(")
RETURN_BARE = re.compile(r"^\s*return\s+(\w+)\s*$")


def _rel_artifact_names(text):
    """收集"装着裸相对产物路径"的名字：直接赋值、列表字面量、以及对前两者取迭代的 for 变量。

    只做一层传播（for v in NAME），不做跨函数数据流——本仓的产物寻址都在模块常量与
    紧邻的消费点里，真要跨函数传相对路径，那已经不是本守卫的形状了。
    """
    names = set()
    for line in text.split("\n"):
        m = ART_VAR.match(line)
        if m:
            names.add(m.group(1))
    for m in ART_LIST.finditer(text):
        if BARE_ART.search(m.group(2)):
            names.add(m.group(1))
    changed = True
    while changed:
        changed = False
        for line in text.split("\n"):
            m = LOOP_VAR.match(line)
            if m and m.group(2) in names and m.group(1) not in names:
                names.add(m.group(1))
                changed = True
    return names


def cwd_relative_artifact_check(root, files):
    """R3：产物路径若以**裸相对路径**被消费，判据就按调用方当前目录解释 ⇒ 发红。

    为什么值得钉（R159 实测形状）：`scripts/fist.py` / `scripts/mcp_smoke.py` 的 `find_main()`
    把候选写成 `"_build/js/debug/build/cmd/cli/cli.js"` 再 `os.path.exists(p)`——从仓库根跑正常，
    从别的目录跑就报「未找到构建产物」，而产物**确实在那儿**（主仓该文件 exists=True 时旧码仍回 `''`）。
    宿主按绝对路径调用入口脚本是常规用法，所以这一格坏掉时，报错文案会把人引去重跑构建。

    合法形状两种（都不红）：①消费点被 `os.path.join(ROOT|_FIST_ROOT|…)` 包住；
    ②起进程时 `cwd=ROOT|_FIST_ROOT|…`（子进程的相对路径按那个目录解释，构造上就对了）。
    范围声明：整行注释豁免（与 R1 同口径，注释不参与执行）；只认 `.js` 产物形状；
    跨函数把相对路径传出去、或经 shell 字符串间接起进程的，不在本判据面内。
    """
    problems = []
    for rel in files:
        if rel in SELF_EXEMPT or not rel.endswith(".py"):
            continue
        p = os.path.join(root, rel)
        if not os.path.isfile(p):
            continue
        txt = io.open(p, encoding="utf-8", errors="replace").read()
        if not BARE_ART.search(txt):
            continue
        names = _rel_artifact_names(txt)
        for i, line in enumerate(txt.split("\n"), 1):
            if PY_COMMENT_LINE.match(line.replace("\\", "/")):
                continue
            for m in EXISTS_CALL.finditer(line):
                arg = m.group(1).strip()
                if not arg or JOINED.search(arg):
                    continue
                if arg in names or BARE_ART.search(arg):
                    problems.append(
                        "R3 %s:%d 裸相对产物路径按调用方 CWD 判存在：%s（修法：os.path.join(<仓库根>, …) 或起进程时钉 cwd=<仓库根>）"
                        % (rel, i, line.strip()[:110]))
            if SPAWN_LINE.search(line) and not CWD_ROOT.search(line):
                seg = line[line.index("("):]
                for m in BARE_ART.finditer(seg):
                    problems.append("R3 %s:%d 起进程的 argv 里产物是裸相对路径且未钉 cwd=<仓库根>：%s"
                                    % (rel, m.start(), line.strip()[:110]))
            for m in RETURN_BARE.finditer(line):
                if m.group(1) in names:
                    problems.append("R3 %s:%d 把裸相对产物路径当结果返回给调用方：%s"
                                    % (rel, i, line.strip()[:110]))
    return problems


def r3_surface(files):
    """R3 的扫描面计数：参与产物寻址判定的 .py 份数（0 份 ⇒ 主程序必须自拒，不许冒绿）。"""
    return len([f for f in files if f.endswith(".py")])


def selftest():
    """逐格自证；**格子清单从实际执行的那一格记一笔**，末行按记下来的名单打印
    （手写计数出过幻影：R5 那格因"变异只改注释"被跳过，自述里却照写 R5×2）。"""
    _entry_probe()
    ok = True
    ran = []
    import tempfile, shutil
    box = tempfile.mkdtemp(prefix="entry-guard-st_")
    try:
        d = os.path.join(box, "scripts")
        os.makedirs(d)
        with io.open(os.path.join(d, "x.py"), "w", encoding="utf-8") as f:
            f.write('A = "cmd/main/main.js"\nB = 1\nC = "moon build --target js cmd/main"\n')
        files = ["scripts/x.py"]
        bad, scanned, _ = judge(box, ["main"], files)
        ran.append("R1 夹具命中 2")
        if not bad:
            print("SELFTEST FAIL：judge 没能力发红（夹具含 2 处可执行指向，却 0 问题）")
            ok = False
        elif len(bad) != 2:
            print("SELFTEST FAIL：夹具应命中 2 处，实得 %d：%s" % (len(bad), bad[:2]))
            ok = False
        clean = os.path.join(d, "clean.md")
        with io.open(clean, "w", encoding="utf-8") as f:
            f.write('运行 `moon build --target js cmd/cli` 后 node _build/js/debug/build/cmd/cli/cli.js\n'
                    '另注：moonc 当年对 cmd/main 输出 ESM bundle（散文叙述，不是操作路径）。\n')
        txt = io.open(clean, encoding="utf-8").read()
        ran.append("干净不误红")
        if mentions("scripts/clean.md", txt, ["main"]):
            print("SELFTEST FAIL：干净输入被误判（cmd/cli 与散文式历史叙述都不该命中）")
            ok = False
        empty, _, _ = judge(box, [], files)
        ran.append("空清单报空转")
        if not empty or "判据空转" not in empty[0]:
            print("SELFTEST FAIL：退役清单为空时必须报「判据空转」，实得 %r" % (empty[:1],))
            ok = False
        # R2 成对：缺 serve 必红、带 serve 不误红
        with io.open(os.path.join(d, "no_serve.py"), "w", encoding="utf-8") as f:
            f.write('MAIN = "_build/js/debug/build/cmd/cli/cli.js"\n'
                    'proc = subprocess.Popen([NODE, MAIN], cwd=ROOT)\n')
        with io.open(os.path.join(d, "has_serve.py"), "w", encoding="utf-8") as f:
            f.write('MAIN = "_build/js/debug/build/cmd/cli/cli.js"\n'
                    'proc = subprocess.Popen([NODE, MAIN, "serve"], cwd=ROOT)\n')
        r2 = launcher_serve_check(box, ["scripts/no_serve.py", "scripts/has_serve.py"])
        ran.append("R2 成对")
        if len(r2) != 1 or "no_serve.py" not in r2[0]:
            print("SELFTEST FAIL：R2 应只报 no_serve.py，实得 %r" % (r2,))
            ok = False
        # ---- 格 5：仓库根 .py 入面（BUG-118 补的盲区，必须能自己发红）----
        # 夹具形状就是本轮实测抓到的那两行（无人值守驱动器把产物路径写进模块常量）。
        with io.open(os.path.join(box, "tick_cron.py"), "w", encoding="utf-8") as f:
            f.write('MCP_SERVER = r"D:\\Repo\\_build\\js\\debug\\build\\cmd\\main\\main.js"\n'
                    'WORKDIR = r"D:\\Repo"\n')
        keep = select_root_py(["tick_cron.py", "scratch.py", "_tmp.py"], {"tick_cron.py"})
        ran.append("根 .py 选取(入库留/未入库点名)")
        if keep[0] != ["tick_cron.py"] or keep[1] != ["scratch.py"]:
            print("SELFTEST FAIL：根 .py 选取错（入库的必须留、未入库的必须点名放下、`_` 前缀永不判）：%r" % (keep,))
            ok = False
        # 走**真采集路径**（不是手抄文件清单）：桩掉 git 查询，钉 candidates() 确实把根 .py 接了进来
        real_git = tracked_root_py
        try:
            globals()["tracked_root_py"] = lambda root: {"tick_cron.py"}
            cs = candidates(box)
            bad5, _, _ = judge(box, ["main"], cs)
            # ---- 格 6：同一份文件**只把注释改了**不许红（否则红是注释带来的，判据不承重）----
            with io.open(os.path.join(box, "tick_cron.py"), "w", encoding="utf-8") as f:
                f.write('# 曾指退役入口 _build/js/debug/build/cmd/main/main.js（历史说明，不执行）\n'
                        'MCP_SERVER = os.path.join(ROOT, "_build", "js", "cmd", "cli", "cli.js")\n')
            bad6, _, _ = judge(box, ["main"], candidates(box))
        finally:
            globals()["tracked_root_py"] = real_git
        if "tick_cron.py" not in cs:
            print("SELFTEST FAIL：candidates() 没把根 .py 接进扫描面（加宽不承重）：%s" % (cs,))
            ok = False
        if not any("tick_cron.py" in p and p.startswith("R1") for p in bad5):
            print("SELFTEST FAIL：根 .py 违例未被发红 ⇒ 加宽扫描面是假的：%s" % (bad5,))
            ok = False
        ran.append("根 .py 入面且活代码必红")
        # ---- 格 6：同一份文件**只把注释改了**不许红（否则红是注释带来的，判据不承重）----
        if any("tick_cron.py" in p for p in bad6):
            print("SELFTEST FAIL：只改注释就把它判红了（注释不参与执行，红必须来自活代码）：%s" % (bad6,))
            ok = False
        ran.append("根 .py 只改注释不误红")
        # ---- 格 7：取不到 git 时反向兜底（宁可多判，绝不"少判成绿"）----
        keep7, drop7 = select_root_py(["tick_cron.py", "_tmp.py"], None)
        if keep7 != ["tick_cron.py"] or drop7 != []:
            print("SELFTEST FAIL：tracked=None 时必须把非 `_` 根 .py 全判，实得 %r %r" % (keep7, drop7))
            ok = False
        ran.append("取不到 git 反向兜底")
        # ---- R3 成组自证（R159 实测形状：违例必红 / 两种合法形状不误红 / 只改注释不误红 / 计数逻辑承重）----
        with io.open(os.path.join(d, "r3_bad.py"), "w", encoding="utf-8") as f:
            f.write('MAIN_CANDIDATES = [\n    "_build/js/debug/build/cmd/cli/cli.js",\n]\n'
                    'def find_main():\n'
                    '    for p in MAIN_CANDIDATES:\n'
                    '        if os.path.exists(p):\n'
                    '            return p\n'
                    '    return ""\n')
        with io.open(os.path.join(d, "r3_join.py"), "w", encoding="utf-8") as f:
            f.write('MAIN_CANDIDATES = [\n    "_build/js/debug/build/cmd/cli/cli.js",\n]\n'
                    'def find_main():\n'
                    '    for p in MAIN_CANDIDATES:\n'
                    '        if os.path.exists(os.path.join(_FIST_ROOT, p)):\n'
                    '            return os.path.join(_FIST_ROOT, p)\n'
                    '    return ""\n')
        with io.open(os.path.join(d, "r3_cwd.py"), "w", encoding="utf-8") as f:
            f.write('MAIN = "_build/js/debug/build/cmd/cli/cli.js"\n'
                    'proc = subprocess.Popen([NODE, MAIN, "serve"], cwd=ROOT)\n')
        with io.open(os.path.join(d, "r3_comment.py"), "w", encoding="utf-8") as f:
            f.write('# 旧形状：os.path.exists(p) 里的 p 来自 "_build/js/debug/build/cmd/cli/cli.js"（历史说明，不执行）\n'
                    'MAIN = "_build/js/debug/build/cmd/cli/cli.js"\n'
                    'proc = subprocess.Popen([NODE, os.path.join(ROOT, MAIN), "serve"], cwd=ROOT)\n')
        r3 = cwd_relative_artifact_check(box, ["scripts/r3_bad.py", "scripts/r3_join.py",
                                              "scripts/r3_cwd.py", "scripts/r3_comment.py"])
        ran.append("R3 裸相对产物必红")
        if not any("r3_bad.py" in x for x in r3):
            print("SELFTEST FAIL：R3 抓不到「候选是裸相对路径 + exists/return 直接用」⇒ R159 那类缺陷会重犯：%s" % (r3,))
            ok = False
        ran.append("R3 合法 join / cwd=ROOT 不误红")
        if any("r3_join.py" in x or "r3_cwd.py" in x for x in r3):
            print("SELFTEST FAIL：R3 把两种合法形状判红了（ROOT 拼接、cwd=ROOT 都构造上正确）：%s" % (r3,))
            ok = False
        ran.append("R3 只改注释不误红")
        if any("r3_comment.py" in x for x in r3):
            print("SELFTEST FAIL：R3 红在注释上（注释不参与执行，红必须来自活代码）：%s" % (r3,))
            ok = False
        ran.append("R3 扫描面计数承重")
        if r3_surface(["scripts/a.py", "docs/b.md", "scripts/c.mbt"]) != 1 or r3_surface(["README.md"]) != 0:
            print("SELFTEST FAIL：r3_surface 计数错 ⇒ 主程序的「空面自拒」门形同虚设")
            ok = False
    finally:
        shutil.rmtree(box, ignore_errors=True)
    print("SELFTEST %s（%d 格：%s）" % (
        "OK" if ok else "FAIL", len(ran), " / ".join(ran)))
    return 0 if ok else 2



def _entry_probe() -> None:
    """入口面自证（R171 口径）：自检必须把入口纳入调用图。

    为什么要有这一格：R158 交付 check_diff_scope.py 时 `--selftest` 全绿而**现状面一跑就崩**
    （clean 分支少传一个实参抛 TypeError，冒出来的 rc=1 和「有违例」一模一样）。自检只考纯函数、
    不碰入口，照不出「自检面与入口面脱钩」。本探测**零副作用**：只验证入口存在且可调用，
    不起服务、不碰网络、不跑真桥。
    """
    if not callable(main):
        raise SystemExit("入口 main 不可调用（自检面与入口面脱钩）")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()

    entries = executable_entries(ROOT)
    ship = shipped_entry(ROOT)
    if not ship:
        print("FATAL 发布入口反解失败：%s 里找不到 `moon build --target … cmd/<pkg>`" % RELEASE_BUILDER)
        return 2
    if ship not in entries:
        print("FATAL 发布入口 cmd/%s 不在可执行入口清单 %s 里（发现逻辑与发布脚本分叉）" % (
            ship, ", ".join("cmd/" + e for e in entries)))
        return 2
    retired = [e for e in entries if e != ship]
    files = collect_files(ROOT)
    problems, scanned, detail = judge(ROOT, retired, files)
    problems = problems + launcher_serve_check(
        ROOT, [r for r in files
               if r not in HISTORY_FILES and not r.startswith(HISTORY_PREFIXES)])
    r3_files = [r for r in files
                if r not in HISTORY_FILES and not r.startswith(HISTORY_PREFIXES)]
    if r3_surface(r3_files) == 0:
        print("FATAL R3 扫描面为空：没有任何 .py 参与产物寻址判定 ⇒ 缺样本＝没测，拒绝报绿")
        return 2
    problems = problems + cwd_relative_artifact_check(ROOT, r3_files)
    print("入口清单：%s｜发布 cmd/%s｜退役 cmd/%s｜扫描面 %d 份（历史面除外）" % (
        ", ".join("cmd/" + e for e in entries), ship,
        ", ".join(retired) if retired else "（无）", scanned))
    if DROPPED_ROOT_PY:
        print("  注：仓库根另有 %d 份未入库的 .py 未判（本机临时件，CI 检出里不存在）：%s" % (
            len(DROPPED_ROOT_PY), ", ".join(DROPPED_ROOT_PY)))
    if scanned == 0:
        print("FATAL 扫描面为 0 份 ⇒ 判据无事可做，绝不报绿")
        return 2
    for p in problems[:40]:
        print("  - " + p)
    if len(problems) > 40:
        print("  …（共 %d 条，仅列前 40）" % len(problems))
    if problems:
        print("FAIL 现状面仍有 %d 处违例（发布入口是 cmd/%s，用户按这些说明跑的是另一棵 / 裸跑只打印 help）" % (
            len(problems), ship))
        return 1
    print("PASS R1 退役入口引用 0 处、R2 缺 serve 启动器 0 个、R3 裸相对产物寻址 0 处（扫描面 %d 份文件，历史面与守卫自身除外）"
          % scanned)
    return 0


if __name__ == "__main__":
    sys.exit(main())
