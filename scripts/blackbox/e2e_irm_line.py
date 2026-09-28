# -*- coding: utf-8 -*-
r"""端到端跑**用户照抄的那一行**：从 README 反解 Windows 安装线，原样喂给 powershell 执行（BUG-113 常驻判据）。

为什么单开这一条（而不是复用 BUG-108 的镜像 e2e）：
  · 镜像 e2e 走的是 `powershell -File <脚本> -BaseUrl <本机镜像>`——它证的是"下载段可用"；
  · 用户实际做的是把 README 那一行贴进终端：`irm … | iex` 形态，**输入面完全不同**。
    BUG-113 就是这么漏的：安装器按 `check_ps_encoding`（BUG-88）带 UTF-8 BOM，
    `irm` 把 BOM 留成首字符 U+FEFF，`iex` 于是把 `param()` 当普通语句解析 ⇒ InvalidLeftHandSide，
    而同一个脚本用 `-File` 跑一切正常 ⇒ 全绿的 e2e 照不出用户那一条。

所以这里刻意**不硬编码命令**：从 README 里反解那一行来执行。
文档改坏 ⇒ 这条直接红；文档写对 ⇒ 用户和判据跑的是同一串字节。

两档：
  默认 沙箱档：子进程 env 把 LOCALAPPDATA/USERPROFILE/TEMP 指到 temp/irm-sandbox，沙箱 bin 顶 PATH，
        HKCU 用户级 PATH 跑前抓原值、跑完逐字还原，真安装目录只读并核 sha256 不变。
  --real 真用户面档：装到 %LOCALAPPDATA%\FIST-Mbt，跑前备份现有产物；
        装完 `fist version`/`fist doctor` 不绿就自动还原并如实报 FAIL。
"""
import argparse
import hashlib
import io
import os
import re
import shutil
import subprocess
import sys
import time

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
BOX = os.path.join(ROOT, "temp", "irm-sandbox")
REAL_DEST = os.path.expandvars(r"%LOCALAPPDATA%\FIST-Mbt")
README = os.path.join(ROOT, "README.md")
LINE_RE = re.compile(r'^\s*iex \(\(irm (\S+?)\)\.ToString\(\)\.TrimStart\(\[char\]0xFEFF\)\)\s*$|^'
                     r'\s*irm (\S+?) \| iex\s*$', re.M)


def sha8(p):
    return hashlib.sha256(io.open(p, "rb").read()).hexdigest()[:8] if os.path.isfile(p) else "(无)"


def documented_line():
    """从 README 反解 Windows 安装线；反解不出来就自拒（判据看不见样本＝判据坏了）。"""
    t = io.open(README, encoding="utf-8").read()
    m = LINE_RE.search(t)
    if not m:
        raise SystemExit("FATAL README 里反解不到 Windows 安装线 ⇒ 判据看不见被检面，绝不报绿")
    url = m.group(1) or m.group(2)
    bare = bool(m.group(2))
    if bare:
        # 旧形（裸 `irm | iex`）原样执行——这正是 BUG-113 的复现路径：应当 FAIL 且原因可见。
        return "irm %s | iex" % url, url, True
    return "iex ((irm %s).ToString().TrimStart([char]0xFEFF))" % url, url, False


def ps_path():
    return subprocess.run(["powershell", "-NoProfile", "-Command",
                           "[Environment]::GetEnvironmentVariable('PATH','User')"],
                          capture_output=True, text=True, encoding="utf-8", errors="replace").stdout.strip()


def set_path(val):
    subprocess.run(["powershell", "-NoProfile", "-Command",
                    "[Environment]::SetEnvironmentVariable('PATH', '%s', 'User')" % val.replace("'", "")],
                   capture_output=True, text=True, encoding="utf-8", errors="replace")


def run_line(cmd_line, env, box, tag):
    r = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", cmd_line],
                       capture_output=True, text=True, encoding="utf-8", errors="replace",
                       env=env, cwd=box, timeout=900)
    out = (r.stdout or "") + (r.stderr or "")
    io.open(os.path.join(box, "%s.log" % tag), "w", encoding="utf-8", newline="\n").write(
        "rc=%s\n$ powershell -Command \"%s\"\n=== stdout+stderr ===\n%s" % (r.returncode, cmd_line, out))
    return r.returncode, out


def probe(env, box, label):
    r = subprocess.run(["bash", "-c", "command -v fist; fist version 2>/dev/null; fist doctor >/dev/null 2>&1; echo doctor=$?"],
                       capture_output=True, text=True, encoding="utf-8", errors="replace",
                       cwd=box, env=env, timeout=300)
    txt = (r.stdout or "").replace("\r", "").strip()
    print("  %-14s %s" % (label, " | ".join(txt.split("\n"))[:170]))
    return txt


def sandbox():
    line, url, bare = documented_line()
    print("被检面（README 反解）：%s\n  目标 URL：%s\n  旧裸形：%s" % (line, url, bare))
    os.makedirs(BOX, exist_ok=True)
    env = dict(os.environ)
    env["LOCALAPPDATA"] = os.path.join(BOX, "AppData", "Local")
    env["USERPROFILE"] = os.path.join(BOX, "User")
    env["TEMP"] = env["TMP"] = os.path.join(BOX, "Temp")
    sbin = os.path.join(env["USERPROFILE"], ".local", "bin")
    env["PATH"] = sbin + os.pathsep + env.get("PATH", "")
    for d in (env["LOCALAPPDATA"], env["USERPROFILE"], env["TEMP"], sbin):
        os.makedirs(d, exist_ok=True)
    real_before = sha8(os.path.join(REAL_DEST, "fist-mbt.js"))
    path_before = ps_path()
    print("基线：真产物 sha256:%s / 用户 PATH %d 字" % (real_before, len(path_before)))
    fails = []
    try:
        rc, out = run_line(line, env, BOX, "irm")
        print("=== 沙箱档 rc=%d ===" % rc)
        for ln in out.split("\n"):
            if any(k in ln for k in ("v0.3.3", "fist-mbt-js-v", "fist (PATH)", "POSIX shim", "InvalidLeftHandSide",
                                     "赋值表达式", "404", "PK", "❌")):
                print("   " + ln.strip()[:112])
        if bare:
            # 旧裸形必须红，且必须能看见"是 iex 解析层红"而不是网络红 ⇒ BUG-113 的复现格
            if rc == 0:
                fails.append("裸 `irm | iex` 竟然成功 ⇒ BUG-113 的成因假设不成立（要重查）")
            if "InvalidLeftHandSide" not in out and "赋值表达式" not in out:
                fails.append("裸形红了但没打出 param() 解析错 ⇒ 红因不是 BOM，归因要重做")
        else:
            if rc != 0:
                fails.append("文档线 rc=%d（应 0）" % rc)
            for needle, why in (("0.3.3", "版本从 moon.mod 反解"),
                                ("fist-mbt-js-v0.3.3.zip", "资产名与发布产物同源"),
                                ("fist (PATH)", "自检经 shim 出回执（BUG-109）"),
                                ("POSIX shim, LF", "无扩展名 shim 门（BUG-105）")):
                print("  %-26s %s（%s）" % (needle, "命中" if needle in out else "未命中", why))
                if needle not in out:
                    fails.append("回执缺 %r（%s）" % (needle, why))
            js = os.path.join(env["LOCALAPPDATA"], "FIST-Mbt", "fist-mbt.js")
            print("  沙箱产物 = %s；bin = %s" % (sha8(js), sorted(os.listdir(sbin))))
            if not os.path.isfile(js):
                fails.append("沙箱里没有产物")
            txt = probe(env, BOX, "沙箱 bash")
            if "v0.3.3" not in txt:
                fails.append("沙箱里 fist version 不是 0.3.3：%r" % txt[:70])
            if "doctor=0" not in txt:
                fails.append("沙箱里 fist doctor 非 0")
    finally:
        now = ps_path()
        if now != path_before:
            set_path(path_before)
            time.sleep(0.4)
            back = ps_path()
            print("   用户 PATH 还原：%s（%d 字）" % ("逐字相同" if back == path_before else "失败", len(back)))
            if back != path_before:
                fails.append("用户 PATH 还原失败")
        else:
            print("   用户 PATH 未被改写")
        real_after = sha8(os.path.join(REAL_DEST, "fist-mbt.js"))
        print("   真产物未动：%s → %s" % (real_before, real_after))
        if real_after != real_before:
            fails.append("真安装目录被动了")
    print("=== 沙箱档：%s ===" % ("PASS" if not fails else "FAIL"))
    for f in fails:
        print("  FAIL " + f)
    io.open(os.path.join(ROOT, "temp", "e2e-irm-last.txt"), "w", encoding="utf-8", newline="\n").write(
        "line=%s\nrc=%s\n%s\n%s" % (line, "见上", "；".join(fails) or "四格命中",
                                    "PASS" if not fails else "FAIL"))
    return 1 if fails else 0


def real():
    line, url, bare = documented_line()
    if bare:
        print("README 还是裸形 ⇒ 真面档拒绝执行（那是已知会红的 BUG-113 形）")
        return 2
    js = os.path.join(REAL_DEST, "fist-mbt.js")
    before = sha8(js)
    bak = os.path.join(BOX, "backup-%s.js" % before)
    os.makedirs(BOX, exist_ok=True)
    if os.path.isfile(js) and not os.path.isfile(bak):
        shutil.copy2(js, bak)
    print("真面档：现产物 %s（备份 temp/irm-sandbox/backup-%s.js）" % (before, before))
    env = dict(os.environ)
    rc, out = run_line(line, env, ROOT, "irm-real")
    print("=== 真用户面 rc=%d ===" % rc)
    for ln in out.split("\n"):
        if any(k in ln for k in ("v0.3.3", "fist (PATH)", "POSIX shim", "❌", "404")):
            print("   " + ln.strip()[:112])
    after = sha8(js)
    print("   真产物：%s → %s" % (before, after))
    txt = probe(env, ROOT, "真面 bash")
    ok = rc == 0 and "v0.3.3" in txt and "doctor=0" in txt
    if not ok and os.path.isfile(bak):
        print("   不绿 ⇒ 自动还原备份")
        shutil.copy2(bak, js)
        print("   还原后 = %s（应回 %s）" % (sha8(js), before))
        probe(env, ROOT, "还原后")
    print("=== 真面档：%s ===" % ("PASS" if ok else "FAIL（已尽力还原）"))
    io.open(os.path.join(ROOT, "temp", "e2e-irm-real.txt"), "w", encoding="utf-8", newline="\n").write(
        "line=%s\n产物=%s→%s\nprobe=%s\n判定=%s" % (line, before, after, txt, "PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--real", action="store_true")
    a = ap.parse_args()
    sys.exit(real() if a.real else sandbox())
