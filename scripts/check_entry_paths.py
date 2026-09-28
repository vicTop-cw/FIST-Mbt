# -*- coding: utf-8 -*-
"""BUG-93 判据：入口清单守卫（entry-list guard）。

要钉的失效形状：入口搬家（cmd/main → cmd/cli）后，脚本/文档/CI 仍指旧入口——
于是"E2E 全绿"测的是**不发布**的那棵入口，用户按文档跑的是另一棵。

真源不是硬编码：
  - 可执行入口清单 = 扫 `cmd/*/moon.pkg` 里带 `pkgtype(kind: "executable")` 的包；
  - 发布入口 = `scripts/blackbox/build_release.ps1` 里 `moon build --target … cmd/<pkg>` 的那个 `<pkg>`；
  - 退役入口 = 清单里除发布入口之外的项。
判据：现状面（脚本/文档/CI/根 .md/.mcp*.json，历史面除外）不得引用任何退役入口。

自证（--selftest）三格：合成违例必红 / 干净输入不误红 / 退役清单为空时判"判据空转"FATAL
（没有退役入口就没有可漏的东西，此时报绿是骗人——要么入口真的统一了、守卫该被删，
  要么发现逻辑坏了）。
"""
import argparse, io, os, re, sys

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
    return sorted(set(rels))


def mentions(rel, text, retired):
    """命中退役入口**且这行是可执行指向**（命令 / 产物路径）才算引用。

    为什么不做子串全量匹配：本仓的历史叙述合法地写着"moonc 当年对 cmd/main 输出 ESM"，
    那是事实陈述不是操作路径；把散文也算进来，守卫会逼着后人去改写叙述面（＝伪造历史）。
    反过来说：只认命令与路径形状，就意味着"退役入口出现在纯散文里"是本守卫**不覆盖**的
    范围（见下方 scope 自述），不是漏网即安全的结论。
    """
    hits = []
    for e in retired:
        needle = "cmd/" + e
        for i, line in enumerate(text.split("\n"), 1):
            norm = line.replace("\\", "/")
            if needle not in norm:
                continue
            if not ACTIONABLE.search(norm):
                continue
            hits.append((needle, i, line.strip()[:110]))
    return hits


# 范围自述（J10 口径）：本守卫判的是"现状面的命令/产物路径是否仍指向退役入口"，
# 不检自身（夹具必须含违例样本，逐字出现退役入口＝必然命中），不判散文叙述、
# 不判历史面（memory/ reports/ CHANGELOG.md）。
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


def selftest():
    """四格：合成违例必红 / 干净不误红 / 退役清单为空判空转 / R2 缺 serve 必红。"""
    ok = True
    import tempfile, shutil
    box = tempfile.mkdtemp(prefix="entry-guard-st_")
    try:
        d = os.path.join(box, "scripts")
        os.makedirs(d)
        with io.open(os.path.join(d, "x.py"), "w", encoding="utf-8") as f:
            f.write('A = "cmd/main/main.js"\nB = 1\nC = "moon build --target js cmd/main"\n')
        files = ["scripts/x.py"]
        bad, scanned, _ = judge(box, ["main"], files)
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
        if mentions("scripts/clean.md", txt, ["main"]):
            print("SELFTEST FAIL：干净输入被误判（cmd/cli 与散文式历史叙述都不该命中）")
            ok = False
        empty, _, _ = judge(box, [], files)
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
        if len(r2) != 1 or "no_serve.py" not in r2[0]:
            print("SELFTEST FAIL：R2 应只报 no_serve.py，实得 %r" % (r2,))
            ok = False
    finally:
        shutil.rmtree(box, ignore_errors=True)
    print("SELFTEST %s（四格：R1 夹具命中 2 / 干净不误红 / 空清单报空转 / R2 成对）" % (
        "OK" if ok else "FAIL"))
    return 0 if ok else 2


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
    print("入口清单：%s｜发布 cmd/%s｜退役 cmd/%s｜扫描面 %d 份（历史面除外）" % (
        ", ".join("cmd/" + e for e in entries), ship,
        ", ".join(retired) if retired else "（无）", scanned))
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
    print("PASS R1 退役入口引用 0 处、R2 缺 serve 启动器 0 个（扫描面 %d 份文件，历史面与守卫自身除外）"
          % scanned)
    return 0


if __name__ == "__main__":
    sys.exit(main())
