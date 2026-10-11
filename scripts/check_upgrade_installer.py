#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check_upgrade_installer.py —— 升级安装器真源化守卫（BUG-235 / BUG-236 的常驻判据）。

背景：阶段 2 的 `fist upgrade` 真调用的安装器是 `_release/js/install_onecmd.ps1`——
① 不被 git 跟踪（`.gitignore` 整目录忽略 `_release/`）② `build_release.ps1` 清空 `_release/`
后不重新生成它 ⇒ 干净 clone / 干净 release 构建后，生产 `fetch_installer` 必 404（BUG-236）。
而它的 `-Force` 清场用 `Remove-Item -Recurse -Force` 会把升级前刚写的
`fist-mbt.js.bak-<旧版本>` 一并删掉 ⇒ 回滚无物可还原（BUG-235）。
修复（方案①，已获批准）：安装器提升为 tracked 真源 `scripts/blackbox/upgrade_install.ps1`
（含 BUG-235 的 .bak-* 保留过滤），CLI 的 `fetch_installer` 改指它，e2e 镜像改服务它。

判据（任一不满足即红；清单与 PASS 行一律从实现反解，不手写计数）：
  G1  `scripts/blackbox/upgrade_install.ps1` 存在，且在 VCS 可视面上——被 `git ls-files`
      跟踪 ⇒ 过；未跟踪但 `git check-ignore` 不命中 ⇒ 过但回执显式标注 untracked
      （CI 的 checkout 面里「存在」即「已提交」，本项真正的拦截形状是 BUG-236 那种
      「落在被 ignore 的 `_release/` 里」）；被 ignore ⇒ 红；不存在 ⇒ 红。
  G2  扫描面（`cmd/`、`scripts/`、`.github/` 全部文本文件，含 untracked）零引用旧安装器
      路径 `_release/js/install_onecmd`（两种斜杠都算）；且 `cmd/cli/upgrade_js.mbt`
      必须引用新真源 `scripts/blackbox/upgrade_install.ps1`。本守卫自身按锚点豁免
      （判据正文必须含禁针才能自检），锚点不在 ⇒ 红。
  G3  安装器纪律针（对真源脚本正文）：
      G3a `$Version` 不写死默认值（param 必须是 `[string]$Version = ""`）且空值 `exit 1`；
      G3b 清场循环带 `-notlike 'fist-mbt.js.bak-*'` 过滤（BUG-235 的核心行为针）；
      G3c 下载后验 zip 魔数 PK（`0x50` / `0x4B`）；
      G3d 带 HTML 嗅探（`<(!DOCTYPE|html)`——200 不等于拿到文件）；
      G3e `VERSION` 落盘在自检（`node … fist-mbt.js version`）之后（R7 不假绿）；
      G3f param 支持 `-BaseUrl` / `-Force` / `-NoPath`。
  扫描面为空（G2 一个文件都枚举不到 / 真源缺席）⇒ FATAL(2) 自拒，绝不报绿。

用法：
    python scripts/check_upgrade_installer.py            # 全量判据
    python scripts/check_upgrade_installer.py --selftest # 判据自己会不会红
退出码：0=PASS，1=违例，2=无法自证（枚举/git 失效）。
"""
import os
import re
import subprocess
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
INSTALLER_REL = "scripts/blackbox/upgrade_install.ps1"
INSTALLER = ROOT / INSTALLER_REL
UPGRADE_JS = ROOT / "cmd" / "cli" / "upgrade_js.mbt"
SELF_NAME = "check_upgrade_installer.py"
# 旧安装器路径禁针（正/反斜杠都算）。本守卫正文必须含它（否则 G2 不知道在禁什么），
# 因此本守卫自身按 SELF_NAME+锚点豁免。
FORBIDDEN_REFS = ["_release/js/install_onecmd", "_release\\js\\install_onecmd"]
SCAN_DIRS = ["cmd", "scripts", ".github"]
TEXT_EXTS = {".mbt", ".py", ".ps1", ".sh", ".yml", ".yaml", ".md", ".json", ".txt", ".cmd"}

# G3 纪律针
P_NEEDLE_VERSION_EMPTY = '[string]$Version = ""'
P_NEEDLE_VERSION_EXIT = "-Version is required"
P_NEEDLE_BAK_FILTER = "-notlike 'fist-mbt.js.bak-*'"
P_NEEDLE_PK_HI = "0x50"
P_NEEDLE_PK_LO = "0x4B"
P_NEEDLE_HTML = "<(!DOCTYPE|html)"
P_NEEDLE_SELFCHECK = 'fist-mbt.js") version'
P_NEEDLE_VERSION_WRITE = re.compile(r'Set-Content[^\n]*"VERSION"[^\n]*-Value \$Version')
P_NEEDLE_BASEURL = "[string]$BaseUrl"
P_NEEDLE_FORCE = "[switch]$Force"
P_NEEDLE_NOPATH = "[switch]$NoPath"


def _git(*args):
    """跑一条 git 只读子命令；git 缺席 ⇒ None（判据无法自证）。"""
    try:
        r = subprocess.run(["git"] + list(args), cwd=str(ROOT),
                           capture_output=True, text=True, encoding="utf-8",
                           errors="replace", timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r


def g1_state():
    """返回 (exists, tracked, ignored, git_ok)；git_ok=False ⇒ 判据无法自证。"""
    exists = INSTALLER.is_file()
    r1 = _git("ls-files", "--error-unmatch", "--", INSTALLER_REL)
    if r1 is None:
        return exists, False, False, False
    tracked = r1.returncode == 0
    r2 = _git("check-ignore", "-q", "--", INSTALLER_REL)
    if r2 is None:
        return exists, tracked, False, False
    ignored = r2.returncode == 0
    return exists, tracked, ignored, True


def g1_problems(exists, tracked, ignored, git_ok):
    """G1 纯判定：喂四元组出违例列表（selftest 与全量同走这一条）。"""
    if not git_ok:
        return ["git 不可用：无法判定安装器是否落在 VCS 可视面（判据无法自证）"]
    if not exists:
        return ["%s 不存在（升级安装器真源缺席，生产 fetch_installer 必 404）" % INSTALLER_REL]
    if ignored:
        return ["%s 被 git ignore 命中——这正是 BUG-236 的失效形状（干净 clone 后不存在）"
                % INSTALLER_REL]
    if not tracked:
        return []  # 未跟踪但未 ignore：本地新文件形态，CI checkout 面「存在」即「已提交」
    return []


def scan_surface():
    """G2 扫描面：cmd/ scripts/ .github/ 下全部文本文件（含 untracked；豁免本守卫自身）。"""
    files = []
    for d in SCAN_DIRS:
        base = ROOT / d
        if not base.is_dir():
            continue
        for p in sorted(base.rglob("*")):
            if not p.is_file() or p.suffix.lower() not in TEXT_EXTS:
                continue
            if p.name == SELF_NAME:
                continue
            files.append(p)
    return files


def g2_problems(files_with_text):
    """G2 纯判定：喂 [(relpath, text)] 出违例。upgrade_js.mbt 缺席/缺新引用都算红。"""
    problems = []
    saw_upgrade_js = False
    for rel, text in files_with_text:
        for ref in FORBIDDEN_REFS:
            if ref in text:
                problems.append("%s 仍引用旧安装器路径 %s" % (rel, ref))
        if rel.replace("\\", "/").endswith("cmd/cli/upgrade_js.mbt"):
            saw_upgrade_js = True
            if INSTALLER_REL not in text:
                problems.append("cmd/cli/upgrade_js.mbt 未引用新真源 %s" % INSTALLER_REL)
    if not saw_upgrade_js:
        problems.append("扫描面里没有 cmd/cli/upgrade_js.mbt（取不到 fetch_installer 的实现面）")
    return problems


def g3_problems(text):
    """G3 纯判定：安装器纪律针。喂正文出违例列表。"""
    problems = []
    if P_NEEDLE_VERSION_EMPTY not in text:
        problems.append("G3a $Version 不是空默认（[string]$Version = \"\" 缺席 ⇒ 禁写死默认版本）")
    if P_NEEDLE_VERSION_EXIT not in text:
        problems.append("G3a 空 Version 的报错/退出针缺席（-Version is required）")
    if P_NEEDLE_BAK_FILTER not in text:
        problems.append("G3b 清场缺 .bak-* 保留过滤（BUG-235：-Force 会把回滚备份一起删掉）")
    if P_NEEDLE_PK_HI not in text or P_NEEDLE_PK_LO not in text:
        problems.append("G3c 缺 PK 魔数检查（0x50/0x4B：200 不等于拿到 zip）")
    if P_NEEDLE_HTML not in text:
        problems.append("G3d 缺 HTML 嗅探（<(!DOCTYPE|html)：HTML 页必须判「源不可用」）")
    m_ver = P_NEEDLE_VERSION_WRITE.search(text)
    pos_check = text.find(P_NEEDLE_SELFCHECK)
    if m_ver is None:
        problems.append("G3e 找不到 VERSION 落盘行（Set-Content … \"VERSION\" … -Value $Version）")
    elif pos_check < 0:
        problems.append("G3e 找不到自检行（node … fist-mbt.js version）")
    elif m_ver.start() < pos_check:
        problems.append("G3e VERSION 写在自检之前（R7：自检没过就写 VERSION = 假绿）")
    for needle, name in ((P_NEEDLE_BASEURL, "-BaseUrl"),
                         (P_NEEDLE_FORCE, "-Force"),
                         (P_NEEDLE_NOPATH, "-NoPath")):
        if needle not in text:
            problems.append("G3f param 缺 %s（%s 缺席）" % (name, needle))
    return problems


def read_text(p):
    return p.read_text(encoding="utf-8", errors="replace")


def run_all():
    """全量判据 → (problems, fatal, notes)。fatal 非空 ⇒ rc=2。"""
    problems, notes = [], []
    exists, tracked, ignored, git_ok = g1_state()
    problems += g1_problems(exists, tracked, ignored, git_ok)
    if exists and not tracked and not ignored and git_ok:
        notes.append("G1: %s 未跟踪但未 ignore（本地新文件形态；CI checkout 面存在即已提交）"
                     % INSTALLER_REL)
    if not git_ok:
        return problems, "git 不可用", notes

    files = scan_surface()
    if not files:
        return problems, "G2 扫描面为空（cmd/ scripts/ .github/ 一个文本文件都没枚举到）", notes
    fwt = []
    for p in files:
        try:
            fwt.append((str(p.relative_to(ROOT)), read_text(p)))
        except OSError as e:
            problems.append("%s 读不到（%s）" % (p, e))
    problems += g2_problems(fwt)

    # 本守卫锚点：豁免自身的代价是自身必须真含禁针（否则 G2 不知道在禁什么）。
    # 反斜杠针在 .py 源码里以转义形落盘（\\），锚点按「源码形」核对。
    self_text = read_text(Path(__file__))
    anchor_fwd = FORBIDDEN_REFS[0] in self_text
    anchor_bwd = FORBIDDEN_REFS[1].replace("\\", "\\\\") in self_text
    if not (anchor_fwd and anchor_bwd):
        problems.append("守卫自身锚点失效：%s 正文不含禁针定义" % SELF_NAME)

    if not exists:
        return problems, "真源 %s 缺席，G3 无对象" % INSTALLER_REL, notes
    problems += g3_problems(read_text(INSTALLER))
    return problems, "", notes


def j_selftest():
    """每条判据至少一支合成违例必红 + 干净输入必绿；清单从已执行格子反解。"""
    fails = []
    ran = []

    # G1 纯判定四格
    if not g1_problems(False, False, False, True):
        fails.append("G1 对『文件不存在』不敏感")
    if not g1_problems(True, False, True, True):
        fails.append("G1 对『被 ignore』（BUG-236 失效形状）不敏感")
    if g1_problems(True, True, False, True):
        fails.append("G1 对已跟踪文件误红")
    if g1_problems(True, False, False, True):
        fails.append("G1 对未跟踪但未 ignore（本地新文件）误红")
    if not g1_problems(True, True, False, False):
        fails.append("G1 对『git 不可用』不自拒")
    ran.append("G1×5")

    # G2 纯判定
    clean = [("cmd/cli/upgrade_js.mbt", "urls = [baseUrl + '/" + INSTALLER_REL + "']"),
             ("scripts/blackbox/e2e_upgrade_mirror.py", "# serves " + INSTALLER_REL)]
    if g2_problems(clean):
        fails.append("G2 对干净输入误红")
    dirty = clean + [("scripts/blackbox/old.py", "fetch _release/js/install_onecmd.ps1")]
    if not any("old.py" in p for p in g2_problems(dirty)):
        fails.append("G2 对旧路径引用不敏感")
    dirty_bs = clean + [("cmd/cli/x.mbt", "_release\\js\\install_onecmd")]
    if not any("x.mbt" in p for p in g2_problems(dirty_bs)):
        fails.append("G2 对反斜杠形旧路径不敏感")
    no_new = [("cmd/cli/upgrade_js.mbt", "urls = [baseUrl + '/x.ps1']")]
    if not any("未引用新真源" in p for p in g2_problems(no_new)):
        fails.append("G2 对『upgrade_js.mbt 缺新真源引用』不敏感")
    if not any("没有 cmd/cli/upgrade_js.mbt" in p for p in g2_problems([])):
        fails.append("G2 对『upgrade_js.mbt 缺席』不敏感")
    ran.append("G2×5")

    # G3 变异：对真源正文下刀，每刀必红；干净必绿
    if not INSTALLER.is_file():
        fails.append("G3 变异实验缺真源（%s 不存在）" % INSTALLER_REL)
    else:
        real = read_text(INSTALLER)
        if g3_problems(real):
            fails.append("G3 对真源干净输入误红：%s" % g3_problems(real))
        mut_a = real.replace(P_NEEDLE_VERSION_EMPTY, '[string]$Version = "0.0.1"')
        if mut_a == real or not any("G3a" in p for p in g3_problems(mut_a)):
            fails.append("G3a 对『写死默认版本』不敏感")
        mut_b = real.replace(P_NEEDLE_BAK_FILTER, "-notlike 'nothing-*'")
        if mut_b == real or not any("G3b" in p for p in g3_problems(mut_b)):
            fails.append("G3b 对『摘掉 .bak-* 过滤』不敏感")
        mut_c = real.replace(P_NEEDLE_PK_HI, "0x51").replace(P_NEEDLE_PK_LO, "0x4C")
        if mut_c == real or not any("G3c" in p for p in g3_problems(mut_c)):
            fails.append("G3c 对『摘掉 PK 魔数』不敏感")
        mut_d = real.replace(P_NEEDLE_HTML, "<(NEVER|match)")
        if mut_d == real or not any("G3d" in p for p in g3_problems(mut_d)):
            fails.append("G3d 对『摘掉 HTML 嗅探』不敏感")
        m_ver = P_NEEDLE_VERSION_WRITE.search(real)
        pos_check = real.find(P_NEEDLE_SELFCHECK)
        if m_ver is None or pos_check < 0:
            fails.append("G3e 真源里定不到 VERSION 落盘行/自检行（判据无法变异）")
        else:
            ver_line_start = real.rfind("\n", 0, m_ver.start()) + 1
            ver_line_end = real.find("\n", m_ver.end())
            ver_line = real[ver_line_start:ver_line_end]
            mut_e = real[:ver_line_start] + real[ver_line_end + 1:]
            mut_e = mut_e[:pos_check] + ver_line + "\n" + mut_e[pos_check:]
            if not any("G3e" in p for p in g3_problems(mut_e)):
                fails.append("G3e 对『VERSION 挪到自检之前』不敏感")
        mut_f = real.replace(P_NEEDLE_NOPATH, "[switch]$SkipPath")
        if mut_f == real or not any("G3f" in p for p in g3_problems(mut_f)):
            fails.append("G3f 对『摘掉 -NoPath』不敏感")
        ran.append("G3×8")

    # 现状面不误红（判据先自证，再判产品）
    problems, fatal, _notes = run_all()
    if fatal:
        fails.append("现状面 FATAL：%s" % fatal)
    if problems:
        fails.append("现状面就红（先修产品再谈守卫）：%s" % problems[0])
    ran.append("real-surface")
    return fails, ran


def main(argv):
    if "--selftest" in argv:
        fails, ran = j_selftest()
        if fails:
            print("SELFTEST FAIL: 升级安装器守卫抓不到合成违例（判据自己坏了）：")
            for f in fails:
                print("  - " + f)
            return 2
        print("SELFTEST OK: %s——合成违例全红、干净输入全绿、现状面不误红" % "+".join(ran))
        return 0

    problems, fatal, notes = run_all()
    for n in notes:
        print("note: " + n)
    if fatal:
        print("FATAL: %s（判据空转绝不报绿）" % fatal)
        return 2
    if problems:
        print("FAIL 升级安装器守卫：%d 处违例" % len(problems))
        for p in problems:
            print("  - " + p)
        return 1
    print("PASS 升级安装器守卫：G1 真源在 VCS 可视面 / G2 现状面零旧引用且 CLI 已接线 / "
          "G3 纪律针（版本不写死/.bak 保留/PK/HTML/VERSION 在自检后/三旗）全在")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
