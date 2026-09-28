# -*- coding: utf-8 -*-
"""BUG-103 判据：发布资产名 ↔ 安装器 ↔ moon.mod 三者一致。

要钉的失效形状（本轮实测）：`install_onecmd.ps1` 与 `install.sh` 的默认版本写死 `0.3.0-beta`，
而发布资产名由 `build_release.ps1` 按 moon.mod 的 `0.3.0` 生成 ⇒ 用户跑字面的
`irm … | iex`（不带任何参数）时，两条下载源都指向发布链永远不会产出的文件名。
CI 看不见这条：CI 不发 Release，也不跑安装器。

判据（四条，全部只看文本形状，不联网）：
  R1 安装器不许给版本号写死字面量默认值（`$Version = "0.x"` / `VERSION="0.x"`）；
  R2 两个安装器都要真的从 moon.mod 取版本（出现 moon.mod 且出现解析用的正则/sed）；
  R3 资产名模板三处一致：install_onecmd.ps1 / install.sh / build_release.ps1 必须都是
     `fist-mbt-js-v<版本>.zip`（release.yml 里若也出现资产名，一并比）；
  R4 解析失败必须显式失败（空版本分支里有 exit 1），不许静默用猜的版本号。

自证四格：写死默认值必红 / 缺 moon.mod 解析必红 / 资产名漂移必红 / 干净输入不误红。
"""
import argparse, io, os, re, sys

ROOT = os.path.normpath(os.path.dirname(os.path.abspath(__file__)) + "/..")
EXPECTED_ASSET = "fist-mbt-js-v"
FILES = {
    "ps1": os.path.join("scripts", "blackbox", "install_onecmd.ps1"),
    "sh": os.path.join("scripts", "blackbox", "install.sh"),
    "build": os.path.join("scripts", "blackbox", "build_release.ps1"),
    "release_yml": os.path.join(".github", "workflows", "release.yml"),
}
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
    return problems


def selftest():
    clean_ps1 = io.open(os.path.join(ROOT, FILES["ps1"]), encoding="utf-8-sig").read()
    clean_sh = io.open(os.path.join(ROOT, FILES["sh"]), encoding="utf-8-sig").read()
    clean_build = io.open(os.path.join(ROOT, FILES["build"]), encoding="utf-8-sig").read()
    base = {"ps1": clean_ps1, "sh": clean_sh, "build": clean_build, "release_yml": ""}
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
    ]
    for key, old, new, want in checks:
        if key == "ps1" and new.strip().startswith("#"):
            continue
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
    for f in fails:
        print("SELFTEST FAIL " + f)
    print("SELFTEST %s（干净不误红 + 变异必红：R1×2 / R2 / R3×2 / R4×1）" % ("OK" if not fails else "FAIL"))
    return 0 if not fails else 2


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    texts = {k: load(v) for k, v in FILES.items()}
    problems = judge(texts)
    for p in problems:
        print("  - " + p)
    if problems:
        print("FAIL 发布资产名/安装器版本真源不一致（用户按 `irm | iex` 装会 404）")
        return 1
    print("PASS 三处资产名同源、两个安装器都从 moon.mod 取版本且空值即失败")
    return 0


if __name__ == "__main__":
    sys.exit(main())
