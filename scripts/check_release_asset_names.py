# -*- coding: utf-8 -*-
"""BUG-103 + BUG-105 + BUG-107 + BUG-109 + BUG-111 + BUG-112 + BUG-113 + BUG-114 判据：资产名/版本真源同源、命令名两类 shell 都可见、200 不等于拿到文件、装完的自检不许假绿、发布作业不许顶掉分发、文档线要 BOM 安全、源码版本常量不许落后于 moon.mod。

（R5/R6/R7/R8 为什么住在"资产名"这个守卫里：本守卫真正管的是**分发面同源**——用户按文档敲的那条命令、
和发布链产出的那个文件名、以及那条命令实际拿回来的字节，三者必须说的是同一件事。
资产名对不上是"下载 404"，命令名对不上是"下载成功却找不到命令"，
源返回 HTML 是"HTTP 200 但装不了"，自检假绿是"安装器自己说装好了、那句诊断还是错的"，
发布作业依赖错是"流水线跑完了却一个资产也没出"，文档线吃 BOM 是"照抄即语法错"，
源码常量落后是"装完了但命令自述上一版"——同一张表面的几类失效，拆成多个守卫只会各看半边。）

要钉的失效形状（本轮实测）：`install_onecmd.ps1` 与 `install.sh` 的默认版本写死 `0.3.0-beta`，
而发布资产名由 `build_release.ps1` 按 moon.mod 的 `0.3.0` 生成 ⇒ 用户跑字面的
`irm … | iex`（不带任何参数）时，两条下载源都指向发布链永远不会产出的文件名。
CI 看不见这条：CI 不发 Release，也不跑安装器。

判据（条数不手写——`--selftest` 的清单与 PASS 行的范围都从正文/已执行格子反解；全部只看文本形状，不联网）：
  R1 安装器不许给版本号写死字面量默认值（`$Version = "0.x"` / `VERSION="0.x"`）；
  R2 两个安装器都要真的从 moon.mod 取版本（出现 moon.mod 且出现解析用的正则/sed）；
  R3 资产名模板三处一致：install_onecmd.ps1 / install.sh / build_release.ps1 必须都是
     `fist-mbt-js-v<版本>.zip`（release.yml 里若也出现资产名，一并比）；
  R4 解析失败必须显式失败（空版本分支里有 exit 1），不许静默用猜的版本号。
  R5 命令名在两类 shell 里都要可见（BUG-105）：Windows 侧除 `.cmd` 外必须再写**无扩展名**的
     `#!/bin/sh` shim 并有"四件齐"的 exit 1 门（POSIX shell 不解析 PATHEXT ⇒ 只给 .cmd
     就等于在 Git Bash / MSYS / agent harness 的 bash 里 `fist` 不存在）；
     WSL/Linux 侧必须有 `cat > "$BIN_DIR/fist"` + `chmod +x`。
  R6 「200 不等于拿到文件」（BUG-107，公网实测）：GitCode 三种 raw 形状（`/-/raw/`、`/raw/`、`raw.` 子域）
     匿名 GET 都返回 HTTP 200 + 一整个 HTML 页 ⇒ 文档首选安装线必须指 GitHub **master** 的 raw 直链
     （写成 main 实测取不到），且两个安装器都要 (a) 对 moon.mod 响应做 HTML 形状检查、
     (b) 下载后验 zip 魔数 `PK`——只按「状态码 200 + 大于 10KB」放行，一页 HTML 就能被当作资产继续解压。
  R7 装完的自检不许假绿（BUG-109，端到端镜像安装实测）：脚本顶部 `$ErrorActionPreference="Stop"`，
     而原生命令的 stderr 经 `2>&1` 会被包成终止错误（NativeCommandError）——node:sqlite 每次启动都打
     `ExperimentalWarning: SQLite is an experimental feature` ⇒ 旧自检里两个 `& node … 2>&1` 的 try
     **必然**进 catch，而紧随其后的 `Write-Host "✅ fist-mbt.js 可执行"` 无条件打印（绿是装饰），
     `& fist version` 那句更把"shim 跑通了"报成"当前会话 PATH 未刷新"（诊断指向不存在的原因）。
     三条子判据：(a) 自检不许留空 `catch { }`（吞错=无从归因）；(b) 原生命令调用必须走
     "临时降 EAP + stderr 隔离"的封装（`$ErrorActionPreference = "Continue"` 与 `2>` 同现）；
     (c) `✅ fist-mbt.js 可执行` 必须挂在版本回执的条件分支上，不许无条件打印。

  R8 发布作业不许顶掉分发（BUG-111，release run 1 实测失败且 Release 零资产；本机快照复跑证明
     JS 三步全通过：`moon build --target js` 0 errors、`patch_esm_main.py` rc=0、zip 374KB 魔数 `PK`）：
     `release` 作业的 needs 必须**含 meta**（它引用 `needs.meta.outputs.version`，不在自己 needs 里就取空值
     ⇒ Release 名与资产名漂成空版本形态），且**不得含 native 作业**（native 不是权威面，
     AGENTS 自己写明权威门槛是 JS 后端；一次 native 编译失败不该让 JS 安装线没资产），
     同时 `build-native-linux` 必须与 windows 侧一样带 `continue-on-error: true`。

  R9 工具链 bootstrap 与 CI 同源（BUG-112，从 run 2 的失败步骤名反解出来的真最后一格）：
     `release.yml` 用 `cli.moonbitlang.com/install/unix`（少 `.sh`）**且从不把 moon 目录写进 `GITHUB_PATH`** ⇒
     runner 每步起新 shell，安装脚本改的是 shell rc，下一步里 `moon` 不在 PATH ⇒ `Build JS target` 红 ⇒
     `release` 作业被 skip ⇒ Release 零资产、默认安装线一直 404。
     判据只看**去掉注释行之后**的代码面（第一版被自家注释里的 "GITHUB_PATH" 喂回针，那格变异不红）。

  R10 文档线必须 BOM 安全（BUG-113）：安装脚本按 BUG-88 带 UTF-8 BOM，`irm` 把 BOM 留成首字符 U+FEFF，
      `iex` 于是把 `param()` 当普通语句解析 ⇒ 用户照 README 粘的那一行当场报「赋值表达式的左侧无效」，
      而同一个脚本用 `-File` 跑一切正常。安装器与 README 两侧的文档线都必须 `TrimStart([char]0xFEFF)`。

  R11 版本自述的**源码常量**必须 == moon.mod（BUG-114）：moon.mod 前进到 0.3.3 之后
      `src/server/server.mbt` 的 `project_version` 仍是 "0.3.0" ⇒ 公网装出来的 `fist version` 回 v0.3.0，
      而安装横幅/README/插件态/moon.mod 四处都说 0.3.3。文档面守卫只比"文档 ↔ moon.mod"，看不见这一格；
      `src/server/fist-mbt_wbtest.mbt` 里那条常驻锁在 master 上一直是红的——红着没人读，等于没锁。
      cmd/cli 侧的版本常量面是**可选面**（CLI 也可以只读 @server.get_version()），扫目录而不是点名文件，
      缺席不报错、在场就必须同源（两格成对：漂移必红 + 无该面不误红）。

自证：写死默认值必红 / 缺 moon.mod 解析必红 / 资产名漂移必红 / 空值不失败必红 /
无扩展名 shim 被摘掉必红 / 不做 HTML 与魔数检查必红 / 文档首选线漂到 main 必红 /
自检退化成空 catch 或无条件 ✅ 或去掉 stderr 隔离必红 /
发布作业 needs 退回顶掉 native 或摘掉 meta 或摘掉 native 容错必红 /
moon 不交给下一步或安装 URL 少 `.sh` 必红 / 文档线退回裸 `irm | iex` 必红 /
源码版本常量落后或真源搬家或基线读不到必红 + 干净输入不误红。
"""
import argparse, io, os, re, sys

ROOT = os.path.normpath(os.path.dirname(os.path.abspath(__file__)) + "/..")
EXPECTED_ASSET = "fist-mbt-js-v"
FILES = {
    "ps1": os.path.join("scripts", "blackbox", "install_onecmd.ps1"),
    "sh": os.path.join("scripts", "blackbox", "install.sh"),
    "build": os.path.join("scripts", "blackbox", "build_release.ps1"),
    "release_yml": os.path.join(".github", "workflows", "release.yml"),
    # R9 要有对照面：ci.yml / fist-ci.yml 里那套 bootstrap 是**跑通过**的形状，release 链只能照它抄
    "ci_yml": os.path.join(".github", "workflows", "ci.yml"),
    "fist_ci_yml": os.path.join(".github", "workflows", "fist-ci.yml"),
    "readme": "README.md",
    # R11 的版本自述**源码面**（BUG-114）：文档面守卫只比"文档 ↔ moon.mod"，看不见源码常量这一格
    "moon_mod": "moon.mod",
    "server_mbt": os.path.join("src", "server", "server.mbt"),
}
CLI_DIR = os.path.join("cmd", "cli")


def collect_cli_version_consts(root=None):
    """cmd/cli 下的 `const *VERSION* = "x.y.z"` 清单 [(文件名, 值)]。

    用"扫目录"而不是 FILES 里点名某个文件：这一面是可选的（CLI 也可以只读 @server.get_version()），
    点名会让它一搬家就静默失检。"""
    d = os.path.join(root or ROOT, CLI_DIR)
    out = []
    if not os.path.isdir(d):
        return out
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".mbt") or fn.endswith("test.mbt"):
            continue
        body = io.open(os.path.join(d, fn), encoding="utf-8", errors="replace").read()
        for m in re.finditer(
                r'(?:pub\s+)?const\s+[A-Z][A-Z0-9_]*VERSION[A-Z0-9_]*\s*(?::\s*String\s*)?=\s*"([^"]*)"', body):
            out.append((os.path.join(CLI_DIR.replace("\\", "/"), fn), m.group(1)))
    return out
# 写死字面量默认版本（注释里出现 0.3.0 不算，只抓赋值形态）
HARDCODED = re.compile(r'(?:^\s*\[string\]\$Version\s*=\s*"[\d][^"]*"|(?:^|\n)\s*VERSION\s*=\s*"[\d][^"]*")', re.M)
ASSET_TMPL = re.compile(r'fist-mbt-js-v[A-Za-z0-9_$\{\}\.\-]*\.zip')


def load(rel):
    p = os.path.join(ROOT, rel)
    if not os.path.isfile(p):
        return None
    return io.open(p, encoding="utf-8-sig", errors="replace").read()


def judge(texts):
    """纯判定：texts = {逻辑名: 正文}。返回问题列表（空=通过）。"""
    problems = []
    ps1, sh = texts.get("ps1"), texts.get("sh")
    build = texts.get("build")
    yml = texts.get("release_yml") or ""
    missing = [k for k, v in (("ps1", ps1), ("sh", sh), ("build", build)) if v is None]
    if missing:
        return ["R0 必读文件缺席：%s（判据无法自证，绝不报绿）" % ", ".join(missing)]
    # R1
    for name, txt in (("install_onecmd.ps1", ps1), ("install.sh", sh)):
        if HARDCODED.search(txt):
            problems.append("R1 %s 给版本号写了字面量默认值：%s" % (
                name, HARDCODED.search(txt).group(0).strip()[:70]))
    # R2
    EMPTY_FAIL = re.compile(
        r'(?:if \[ -z "\$VERSION" \]; then[\s\S]{0,260}?exit 1'
        r'|\$Version -eq ""\) \{[\s\S]{0,260}?exit 1'
        r'|(?:^|\n)\s*if \(\\\$Version\) -eq "" \{[\s\S]{0,260}?exit 1)', re.M)
    for name, txt in (("install_onecmd.ps1", ps1), ("install.sh", sh)):
        if "moon.mod" not in txt:
            problems.append("R2 %s 没从 moon.mod 取版本号（真源漂移回不来）" % name)
        # 解析式必须真的去匹配 moon.mod 里的 `version = "…"`（引号捕获在，才算在读那个字段）
        if not re.search(r'version[^\n]*=[^\n]*"', txt):
            problems.append("R2 %s 里没有针对 moon.mod `version = \"…\"` 的解析式" % name)
    # R3 资产名模板三处一致
    seen = {}
    for name, txt in (("install_onecmd.ps1", ps1), ("install.sh", sh), ("build_release.ps1", build)):
        hits = ASSET_TMPL.findall(txt)
        if not hits:
            problems.append("R3 %s 里找不到 `fist-mbt-js-v…zip` 资产名模板" % name)
            continue
        seen[name] = sorted({h for h in hits})
    if yml and EXPECTED_ASSET not in yml:
        problems.append("R3 release.yml 出现的资产名不含 %s（与安装器不同源）" % EXPECTED_ASSET)
    prefixes = {k: {h[:len(EXPECTED_ASSET)] for h in v} for k, v in seen.items()}
    for k, v in prefixes.items():
        if v != {EXPECTED_ASSET}:
            problems.append("R3 %s 的资产名前缀漂移：%s" % (k, sorted(v)))
    # R4 解析不到版本必须显式失败（空值分支里 260 字内出现 exit 1）
    for name, txt in (("install_onecmd.ps1", ps1), ("install.sh", sh)):
        if not EMPTY_FAIL.search(txt):
            problems.append("R4 %s 缺「版本解析为空即 exit 1」的门（会静默用猜的版本号）" % name)
    # R5 命令名两类 shell 都要可见（BUG-105：POSIX shell 不解析 PATHEXT，只给 .cmd 等于没给命令）
    if "'#!/bin/sh'" not in ps1 and '"#!/bin/sh"' not in ps1:
        problems.append("R5 install_onecmd.ps1 不写 POSIX shim（Git Bash / MSYS 下 `fist` 会 command not found）")
    for nm in ("fist", "fist-mbt"):
        # 闭引号紧跟名字 ⇒ `"$bin\fist"` 不会误命中 `"$bin\fist-mbt"`；
        # 别在 `"` 后加 \b（引号与空格同为非单词字符 ⇒ 那里根本没有边界，针会恒 0）。
        if not re.search(r'Set-Content\s+-Path\s+"\$bin\\%s"' % nm, ps1):
            problems.append('R5 install_onecmd.ps1 缺无扩展名 shim 写入："$bin\\%s"' % nm)
    if not re.search(r'shimMissing[\s\S]{0,260}exit 1', ps1):
        problems.append("R5 install_onecmd.ps1 的「四件齐」门不在（缺件必须显式失败，不许静默装半套）")
    if not re.search(r'cat > "\$BIN_DIR/fist" *<<', sh):
        problems.append("R5 install.sh 没写无扩展名 $BIN_DIR/fist")
    if not re.search(r'chmod \+x "\$BIN_DIR/fist"', sh):
        problems.append("R5 install.sh 忘了 chmod +x（写了 shim 但不可执行）")
    # R6 「200 不等于拿到文件」（BUG-107，公网实测：GitCode 三种 raw 形状都回 HTML 页且状态码 200）
    DOC_GH_MASTER = re.compile(
        r'raw\.githubusercontent\.com/vicTop-cw/FIST-Mbt/master/scripts/blackbox/'
        r'(?:install_onecmd\.ps1|install\.sh)')
    for name, txt in (("install_onecmd.ps1", ps1), ("install.sh", sh)):
        if not DOC_GH_MASTER.search(txt):
            problems.append("R6 %s 文档首选安装线没指 GitHub master 的 raw 直链"
                            "（实测唯一匿名可达；写成 main 或非 GitHub 源会把用户送去 HTML 页）" % name)
    # R10 文档那条线必须 BOM 安全（BUG-113 实测：脚本带 UTF-8 BOM ⇒ `irm | iex` 在 param() 处报
    # 「赋值表达式的左侧无效」，而同一个脚本 `-File` 跑正常 ⇒ 用户粘的是文档线，不是 -File）
    if "TrimStart([char]0xFEFF)" not in ps1:
        problems.append("R10 install_onecmd.ps1 的文档线没有 TrimStart([char]0xFEFF) ⇒ 带 BOM 的脚本被 iex 解析不了")
    if "TrimStart([char]0xFEFF)" not in (texts.get("readme") or ""):
        problems.append("R10 README 的 Windows 安装线没有 TrimStart([char]0xFEFF)（用户照抄即当场失败）")
    if "<(!DOCTYPE|html)" not in ps1:
        problems.append("R6 install_onecmd.ps1 没对 moon.mod 响应做 HTML 形状检查")
    if "0x50" not in ps1 or "0x4B" not in ps1:
        problems.append("R6 install_onecmd.ps1 下载后没验 zip 魔数 PK（HTML 页也可能 >10KB）")
    if '"PK"' not in sh:
        problems.append("R6 install.sh 下载后没验 zip 魔数 PK")
    if "!DOCTYPE" not in sh:
        problems.append("R6 install.sh 没对 moon.mod 响应做 HTML 形状检查")
    # R8 发布作业的依赖面（BUG-111，实测 release run 1 失败且 Release 零资产）：
    # release 作业引用 needs.meta.outputs.version，却没把 meta 列进自己的 needs ⇒ 取不到值；
    # 又把**可选的** native 作业当一票否决项 ⇒ native 编译一红，JS 分发面就没资产。
    if yml:
        m = re.search(r'\n  release:\n([\s\S]{0,500})', yml)
        if not m:
            problems.append("R8 release.yml 里找不到 release 作业（发布链无从核对，判据自拒）")
        else:
            seg = m.group(1)
            mn = re.search(r'needs:\s*\[([^\]]*)\]', seg)
            if not mn:
                problems.append("R8 release 作业没有 needs 清单（引用 needs.meta 会取空值）")
            else:
                needs = mn.group(1)
                if "meta" not in needs:
                    problems.append("R8 release 作业的 needs 里没有 meta，正文却引用 needs.meta.outputs.version"
                                    "（Release 名与资产名会漂成空版本形态）")
                if "native" in needs:
                    problems.append("R8 release 作业的 needs 里含 native 作业"
                                    "（native 不是权威面，一次编译失败就不该顶掉 JS 分发资产的发布）")
        if not re.search(r'build-native-linux:[\s\S]{0,300}?continue-on-error:\s*true', yml):
            problems.append("R8 release.yml 的 build-native-linux 没有 continue-on-error（与 windows 侧不对齐，"
                            "却仍然顶掉发布）")
    else:
        problems.append("R8 读不到 release.yml ⇒ 发布链判据无法自证（不报绿）")
    # R7 装完的自检不许假绿（BUG-109，端到端镜像安装实测）：
    # 顶部 $ErrorActionPreference="Stop" + 原生命令的 stderr ⇒ NativeCommandError（终止错误）。
    # node:sqlite 每次启动都打 ExperimentalWarning ⇒ 旧写法里 `& node … 2>&1` 必进 catch，
    # 而下一句 ✅ 无条件打印；`& fist version` 的 catch 又把"跑通了"说成"PATH 未刷新"。
    if re.search(r'catch\s*\{\s*\}', ps1):
        problems.append("R7 install_onecmd.ps1 有空 catch（吞掉错误=失效无从归因，用户只看到 ⚠️ 却不知原因）")
    if not re.search(r'\$ErrorActionPreference\s*=\s*"Continue"[\s\S]{0,200}?2>\$null', ps1):
        problems.append('R7 install_onecmd.ps1 的原生命令调用没有「临时降 EAP + stderr 隔离」封装'
                        '（Stop 下 ExperimentalWarning 会被当成安装失败，✅ 那行永远打不出来）')
    if not re.search(r'if \(\$jsVer\) \{[\s\S]{0,300}?fist-mbt\.js 可执行', ps1):
        problems.append('R7 install_onecmd.ps1 的「✅ fist-mbt.js 可执行」没挂在版本回执的条件分支上（无条件绿=装饰）')
    # R9 工具链 bootstrap 必须与 ci.yml 同形（BUG-112 实测：release.yml 的安装 URL 少 `.sh`，
    # 且从不把 moon 目录写进 GITHUB_PATH ⇒ runner 每步起新 shell，`moon` 不在 PATH，
    # build-js 红 ⇒ release 作业被 skip ⇒ 默认安装线永远 404。本机装了全局 moon，
    # "在 git archive 快照树里复跑 CI 的三步"因此全绿 —— 这条只在 runner 上现形）
    MOON_CALL = re.compile(r'\bmoon\s+(?:build|test|update|ide|check)\b')
    for wf_name, wf_key in (("release.yml", "release_yml"), ("ci.yml", "ci_yml"), ("fist-ci.yml", "fist_ci_yml")):
        wf = texts.get(wf_key)
        if not wf or not MOON_CALL.search(wf):
            continue
        # 只看**代码面**：注释里出现 "GITHUB_PATH" 不算导出（第一版就被自家说明文字喂回过针——
        # 我在 release.yml 写的注释里有这个词，于是"摘掉导出行"那格变异不红了）。
        wf_code = "\n".join(l for l in wf.split("\n") if not l.lstrip().startswith("#"))
        if "GITHUB_PATH" not in wf_code:
            problems.append("R9 %s 里跑了 moon 却没把工具链目录写进 GITHUB_PATH"
                            "（安装脚本改的是 shell rc，下一步的 shell 看不见 ⇒ moon 不在 PATH）" % wf_name)
        if "cli.moonbitlang.com/install/unix" in wf_code and "cli.moonbitlang.com/install/unix.sh" not in wf_code:
            problems.append("R9 %s 的 unix 安装 URL 少了 `.sh`（与 ci.yml 不同源 ⇒ 装完不等于装对）" % wf_name)
    # R11 版本自述的**源码常量**面必须与 moon.mod 同源（BUG-114 实测：moon.mod 已到 0.3.3，
    # src/server/server.mbt 的 project_version 仍是 "0.3.0" ⇒ 公网装出来的 `fist version` 回 v0.3.0，
    # 而安装横幅、README、插件态、moon.mod 全说 0.3.3。文档面守卫只比"文档 ↔ moon.mod"，看不见这一格；
    # src/server/fist-mbt_wbtest.mbt 里那条常驻锁在 master 上一直是红的——红着没人读，等于没锁）
    mv = re.search(r'^version\s*=\s*"([^"]*)"', texts.get("moon_mod") or "", re.M)
    if not mv:
        problems.append("R11 moon.mod 反解不到 version ⇒ 版本自述判据没有基线，不报绿")
    else:
        ver = mv.group(1)
        srv = texts.get("server_mbt")
        if srv is None:
            problems.append("R11 读不到 src/server/server.mbt ⇒ 自述真源无法核对（判据自拒，不报绿）")
        else:
            hits = re.findall(r'let\s+project_version\s*:\s*String\s*=\s*"([^"]*)"', srv)
            if not hits:
                problems.append('R11 src/server/server.mbt 里没有 `let project_version : String = "…"`'
                                "（对外自述真源搬家了？判据看不见被检面，不报绿）")
            for h in hits:
                if h != ver:
                    problems.append('R11 server.mbt 的 project_version="%s" ≠ moon.mod 的 "%s"'
                                    "（`fist version` 与 status_summary/overview 会一起说谎）" % (h, ver))
        for where, h in (texts.get("cli_version_consts") or []):
            if h != ver:
                problems.append('R11 %s 的版本常量="%s" ≠ moon.mod 的 "%s"' % (where, h, ver))
    return problems


def rule_inventory():
    """判据范围自述**从 judge 正文反解**：手写 "R1-R10" 会变成第二份真源，
    加一条判据忘了改自述就是 AGENTS J10 那一类（声明滞后 / 幻影判据）。"""
    src = io.open(os.path.abspath(__file__), encoding="utf-8").read()
    body = src[src.index("def judge("):src.index("def rule_inventory(")]
    ids = sorted({int(m) for m in re.findall(r'problems\.append\(["\']R(\d+)', body)} - {0})
    return "/".join("R%d" % i for i in ids) or "R?"


def selftest():
    clean_ps1 = io.open(os.path.join(ROOT, FILES["ps1"]), encoding="utf-8-sig").read()
    clean_sh = io.open(os.path.join(ROOT, FILES["sh"]), encoding="utf-8-sig").read()
    clean_build = io.open(os.path.join(ROOT, FILES["build"]), encoding="utf-8-sig").read()
    # R8 判的是 release.yml：干净支必须拿真文件，否则"读不到 release.yml"那条会把干净输入判红
    # （同一个守卫里，缺席即报——所以自证的夹具也得齐件）。
    clean_yml = io.open(os.path.join(ROOT, FILES["release_yml"]), encoding="utf-8-sig").read()
    # R9 的对照面就是这两个工作流：干净支得把它们一起加载，否则 texts.get(...) 为 None 会静默跳过，
    # "能红"的自证就只剩 release.yml 一侧（另一侧坏了没人管）。
    clean_ci = io.open(os.path.join(ROOT, FILES["ci_yml"]), encoding="utf-8-sig").read()
    clean_fci = io.open(os.path.join(ROOT, FILES["fist_ci_yml"]), encoding="utf-8-sig").read()
    clean_moon = io.open(os.path.join(ROOT, FILES["moon_mod"]), encoding="utf-8-sig").read()
    clean_srv = io.open(os.path.join(ROOT, FILES["server_mbt"]), encoding="utf-8-sig").read()
    mv = re.search(r'^version\s*=\s*"([^"]+)"', clean_moon, re.M)
    if not mv:
        print("SELFTEST FAIL moon.mod 反解不到 version ⇒ 自证夹具没有基线")
        return 2
    VER = mv.group(1)
    base = {"ps1": clean_ps1, "sh": clean_sh, "build": clean_build,
            "release_yml": clean_yml, "ci_yml": clean_ci, "fist_ci_yml": clean_fci,
            "moon_mod": clean_moon, "server_mbt": clean_srv,
            "cli_version_consts": collect_cli_version_consts(),
            "readme": io.open(os.path.join(ROOT, FILES["readme"]), encoding="utf-8").read()}
    fails = []
    if judge(dict(base)):
        fails.append("干净输入被误判（本仓现状应通过）：%s" % judge(dict(base))[:2])
    def one(mod_key, old, new, want):
        d = dict(base)
        assert old in d[mod_key], "变异锚不在 %s 里（凭记忆写的串，停）" % mod_key
        d[mod_key] = d[mod_key].replace(old, new)
        probs = judge(d)
        if not any(p.startswith(want) for p in probs):
            return "%s：%s 变异没触发 %s（实得 %s）" % (mod_key, want, want, probs[:1])
        return None
    checks = [
        ("ps1", '  [string]$Version = "",', '  [string]$Version = "0.3.0-beta",', "R1"),
        ("sh", 'VERSION="${FIST_VERSION:-}"', 'VERSION="0.3.0-beta"', "R1"),
        ("ps1", '$rawUrls = @(', '$rawUrls = @()  # moonmod-off', "R2"),
        ("ps1", '"fist-mbt-js-v$Version.zip"', '"fist-mbt-js-$Version-js.zip"', "R3"),
        ("sh", 'ZIP="fist-mbt-js-v${VERSION}.zip"', 'ZIP="fist-js-${VERSION}.zip"', "R3"),
        # 空值分支不再 exit 1 ⇒ 安装器会静默带着猜出来的版本号去下载
        ("sh", '  exit 1', '  exit 0', "R4"),
        # R5 两支：Windows 侧摘掉无扩展名 shim 的写入行 / WSL 侧把 chmod +x 改错文件名
        # （前一手曾写成"换成一行注释"，又被下面的跳过规则挡掉 ⇒ 那一格从没跑过，
        #   而自述行照写 R5×2 —— 纯注释变异不能当对照，删干净才算"摘掉写入"）
        ("ps1", 'Set-Content -Path "$bin\\fist"     -Value $shimSh -Encoding ASCII -NoNewline',
         "", "R5"),
        ("sh", 'chmod +x "$BIN_DIR/fist"', 'chmod +x "$BIN_DIR/fist.cmd"', "R5"),
        # R6 三支：摘掉 zip 魔数检查 / 摘掉 HTML 形状检查 / 文档首选线漂到 main
        ("sh", '[ "$(head -c 2 "$ZIP_PATH" 2>/dev/null)" != "PK" ]', 'false', "R6"),
        ("ps1", "<(!DOCTYPE|html)", "<NO-HTML-SNIFF>", "R6"),
        ("ps1", "FIST-Mbt/master/scripts/blackbox/install_onecmd.ps1",
         "FIST-Mbt/main/scripts/blackbox/install_onecmd.ps1", "R6"),
        # R7 三支（BUG-109 的三种退化）：把 stderr 隔离改回 2>&1 / ✅ 脱离条件分支 / 引入空 catch
        ("ps1", "(& $Exe @ExeArgs 2>$null | Out-String)", "(& $Exe @ExeArgs 2>&1 | Out-String)", "R7"),
        ("ps1", "if ($jsVer) {", "if ($true) {", "R7"),
        ("ps1", "  $prevEap = $ErrorActionPreference",
         "  $prevEap = $ErrorActionPreference\n  try { $null = 1 } catch { }", "R7"),
        # R8 三支（BUG-111 的三种退化）：needs 退回顶掉发布 / 摘掉 meta / 摘掉 native 的容错
        ("release_yml", "needs: [meta, build-js]", "needs: [build-js, build-native-linux]", "R8"),
        ("release_yml", "needs: [meta, build-js]", "needs: [build-js]", "R8"),
        # R9 两支（BUG-112 的两种退化）：moon 目录不交给下一步 / 安装 URL 退回少 `.sh`
        ("release_yml", 'echo "$HOME/.moon/bin" >> "$GITHUB_PATH"', "echo '# (变异：不把 moon 交给下一步)'", "R9"),
        ("release_yml", "cli.moonbitlang.com/install/unix.sh", "cli.moonbitlang.com/install/unix", "R9"),
        # R10 两支：文档线退回裸 `irm … | iex`（安装器侧 / README 侧）
        ("ps1", "TrimStart([char]0xFEFF)", "NO-TRIM", "R10"),
        ("readme", "TrimStart([char]0xFEFF)", "NO-TRIM", "R10"),
        ("release_yml", "    continue-on-error: true\n    runs-on: ubuntu-latest",
         "    runs-on: ubuntu-latest", "R8"),
        # R11 三支（BUG-114 的三种退化）：源码常量落后 / 自述真源搬家 / 基线本身读不到
        ("server_mbt", 'let project_version : String = "%s"' % VER,
         'let project_version : String = "0.9.9"', "R11"),
        ("server_mbt", 'let project_version : String = "%s"' % VER,
         "let moved_away : Int = 1", "R11"),
        ("moon_mod", 'version = "%s"' % VER, 'name = "no-version-line-here"', "R11"),
    ]
    executed = []
    for key, old, new, want in checks:
        if new.strip().startswith("#"):
            fails.append("%s 的变异只改了注释 ⇒ 那格不能当对照（注释喂不出红，见 R9 那一手）" % want)
            continue
        executed.append(want)
        if want == "R2":
            d = dict(base)
            d[key] = d[key].replace("moon.mod", "moonmod")
            probs = judge(d)
            if not any(p.startswith("R2") for p in probs):
                fails.append("R2 变异未红：%s" % (probs[:1],))
            continue
        r = one(key, old, new, want)
        if r:
            fails.append(r)
    # R11 的 cmd/cli 一侧：常量表是"扫目录"得来的，不是文件正文，所以单独两格（一红一不誤红）
    d = dict(base)
    d["cli_version_consts"] = [("cmd/cli/synthetic.mbt", "0.9.9")]
    if not any(p.startswith("R11") for p in judge(d)):
        fails.append("R11 cmd/cli 版本常量漂移未红（该面没人认领时会静默失检）")
    executed.append("R11")
    d = dict(base)
    d["cli_version_consts"] = []          # HEAD 形状：cmd/cli 里没有版本常量面
    probs = judge(d)
    if any(p.startswith("R11") for p in probs):
        fails.append("R11 在 cmd/cli 无版本常量面时误红（那是可选面）：%s" % probs[:1])
    executed.append("R11")
    from collections import Counter
    cnt = Counter(executed)
    inventory = " / ".join("%s×%d" % (k, v) if v > 1 else k for k, v in sorted(
        cnt.items(), key=lambda kv: int(kv[0][1:])))
    for f in fails:
        print("SELFTEST FAIL " + f)
    print("SELFTEST %s（干净不误红 + 变异必红；清单从已执行格子反解：%s）"
          % ("OK" if not fails else "FAIL", inventory))
    return 0 if not fails else 2


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    texts = {k: load(v) for k, v in FILES.items()}
    texts["cli_version_consts"] = collect_cli_version_consts()
    problems = judge(texts)
    for p in problems:
        print("  - " + p)
    if problems:
        print("FAIL 发布资产名/安装器版本真源不一致（用户按 `irm | iex` 装会 404）")
        return 1
    print("PASS 分发面同源（判据范围从正文反解：%s）：资产名三处一致 + 版本真源 moon.mod + 空值即失败 + "
          "命令名两类 shell 都可见 + 200/HTML/魔数检查 + 安装自检不假绿 + 发布作业不顶掉分发 + "
          "工具链 bootstrap 与 CI 同源 + 文档线 BOM 安全 + 源码版本常量与 moon.mod 同源" % rule_inventory())
    return 0


if __name__ == "__main__":
    sys.exit(main())
