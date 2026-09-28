# -*- coding: utf-8 -*-
r"""端到端装一遍：本机 http.server 当镜像，走**真实下载路径**装进沙箱，再验命令可用（BUG-108 判据）。

为什么要它：`irm … | iex` 的"下载"这一步此前没有任何可跑的法子——没有授权 push ⇒ 没有公网 Release
资产，而 `-LocalZip` 是**跳过**下载，两者不等价：URL 拼装、状态码、HTML sniff、zip 魔数、解压、
ESM patch、shim 写出、PATH 追加、自检**全在被跳过的那一段里**。镜像入口（`-BaseUrl` /
`FIST_BASE_URL`）就是为了让这段可跑，所以这个 e2e 常驻 `scripts/blackbox/`（一次性 temp 脚本守不住它）。

沙箱边界（三条硬约束，脚本自己保证并复核）：
  ① 子进程环境变量里 LOCALAPPDATA / USERPROFILE / TEMP 全指到 temp/b108-sandbox ⇒ 产品与 shim 不落真目录；
  ② HKCU 的用户级 PATH 会被安装器改写 ⇒ 跑之前抓原值，跑完**逐字还原**并复核；
  ③ 真安装目录 %LOCALAPPDATA%\FIST-Mbt 里的产物跑前跑后 sha256 必须相同（绝不动别人已经装好的那份）。
反面对照：镜像里把 zip 换成一个 20KB 的 HTML 页 ⇒ 必须 rc!=0、必须点名"前两字节不是 PK"，
且不得留下已安装产物（失败要停在下载那一步，不能装出半套）。

跑法：`python scripts/blackbox/e2e_mirror_install.py`（Windows + 已装过真产物）。
前置不满足时 rc=3 并点名缺什么——**跳过不是通过**，绝不拿"没法跑"冒充绿。
"""
import hashlib
import io
import os
import socket
import subprocess
import sys
import time
import zipfile

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
BOX = os.path.join(ROOT, "temp", "b108-sandbox")
MIRROR = os.path.join(ROOT, "temp", "b108-mirror")
INSTALLER = os.path.join(ROOT, "scripts", "blackbox", "install_onecmd.ps1")
REAL_DEST = os.path.expandvars(r"%LOCALAPPDATA%\FIST-Mbt")
LOG = os.path.join(BOX, "run.log")  # 正向那一跑的完整回执（反面跑在 neg/run.log）


def sha8(p):
    return hashlib.sha256(io.open(p, "rb").read()).hexdigest()[:8] if os.path.isfile(p) else "(无)"


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    p = s.getsockname()[1]
    s.close()
    return p


def build_mirror(port):
    for d in (MIRROR, os.path.join(MIRROR, "-"), os.path.join(MIRROR, "releases")):
        os.makedirs(d, exist_ok=True)
    asset_dir = os.path.join(MIRROR, "-", "releases", "download", "v0.3.0")
    os.makedirs(asset_dir, exist_ok=True)
    io.open(os.path.join(MIRROR, "moon.mod"), "w", encoding="utf-8", newline="\n").write(
        io.open(os.path.join(ROOT, "moon.mod"), encoding="utf-8").read())
    js = os.path.join(REAL_DEST, "fist-mbt.js")
    assert os.path.isfile(js), "真安装目录里没有产物：先确认已装过"
    zp = os.path.join(asset_dir, "fist-mbt-js-v0.3.0.zip")
    with zipfile.ZipFile(zp, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(js, "fist-mbt.js")
        z.write(os.path.join(ROOT, "scripts", "patch_esm_main.py"), "patch_esm_main.py")
    print("镜像就绪：%s（%d KB，内含 fist-mbt.js sha256:%s）" % (
        os.path.relpath(zp, ROOT).replace("\\", "/"),
        os.path.getsize(zp) // 1024, sha8(js)))
    srv = subprocess.Popen([sys.executable, "-m", "http.server", str(port),
                            "--bind", "127.0.0.1", "--directory", MIRROR],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1.5)
    if srv.poll() is not None:
        raise SystemExit("http.server 起不来")
    return srv, "http://127.0.0.1:%d" % port


def ps_path():
    return subprocess.run(
        ["powershell", "-NoProfile", "-Command",
         "[Environment]::GetEnvironmentVariable('PATH','User')"],
        capture_output=True, text=True, encoding="utf-8", errors="replace").stdout.strip()


def set_path(val):
    subprocess.run(["powershell", "-NoProfile", "-Command",
                    "[Environment]::SetEnvironmentVariable('PATH', '%s', 'User')" % val.replace("'", "")],
                   capture_output=True, text=True, encoding="utf-8", errors="replace")


def run_installer(base, box=BOX, extra=None):
    env = dict(os.environ)
    env["LOCALAPPDATA"] = os.path.join(box, "AppData", "Local")
    env["USERPROFILE"] = os.path.join(box, "User")
    env["TEMP"] = env["TMP"] = os.path.join(box, "Temp")
    sbin = os.path.join(env["USERPROFILE"], ".local", "bin")
    # 沙箱 bin 顶到 PATH 最前：安装器自检里那句 `fist version` 才会解析到**沙箱**那份 shim，
    # 而不是真装好的全局命令（否则它绿的是别人）。
    env["PATH"] = sbin + os.pathsep + env.get("PATH", "")
    for d in (env["LOCALAPPDATA"], env["USERPROFILE"], env["TEMP"], sbin):
        os.makedirs(d, exist_ok=True)
    cmd = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", INSTALLER,
           "-BaseUrl", base] + (extra or [])
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                       errors="replace", env=env, cwd=box, timeout=600)
    io.open(os.path.join(box, "run.log"), "w", encoding="utf-8", newline="\n").write(
        "rc=%s\n=== stdout ===\n%s\n=== stderr ===\n%s\n" % (r.returncode, r.stdout, r.stderr))
    return r.returncode, (r.stdout or "") + (r.stderr or "")


def check(out, base):
    # 针一律挑 ASCII：PS 控制台按 cp936 出，中文那部分到这里常已成 '?'，
    # 拿中文当针会得到"其实成功了却判未命中"的假红（本仓踩过：乱码不是证据）。
    marks = {
        "版本来源=镜像 moon.mod": base + "/moon.mod",
        "资产名按版本拼装": "v0.3.0/fist-mbt-js-v0.3.0.zip",
        "POSIX shim 门通过": "POSIX shim, LF",
        # BUG-109 修好后这行才打得出来：`✅ fist (PATH) → FIST-Mbt v0.3.0`。
        # 旧安装器在 node:sqlite 的 ExperimentalWarning 下必然进 catch ⇒ 针永远不命中，
        # 于是"安装器自检经 shim 跑到 fist"这条主张从来没有被证过（不是探针坏，是产品假绿）。
        "安装器自检经 shim 跑到 fist": "fist (PATH)",
    }
    for k, needle in marks.items():
        print("  %-24s %s" % (k, "命中" if needle in out else "未命中"))
    return all(n in out for n in marks.values())


def main():
    if os.name != "nt":
        print("SKIP 非 Windows：本 e2e 验的是 install_onecmd.ps1（WSL 侧走 install.sh）")
        return 3
    if not os.path.isfile(os.path.join(REAL_DEST, "fist-mbt.js")):
        print("SKIP 真安装目录里没有产物（%s）⇒ 镜像无处取材；先按文档装一次再说" % REAL_DEST)
        return 3
    real_before = sha8(os.path.join(REAL_DEST, "fist-mbt.js"))
    path_before = ps_path()
    print("沙箱外基线：真产物 sha256:%s / 用户 PATH 长度 %d" % (real_before, len(path_before)))
    port = free_port()
    srv, base = build_mirror(port)
    fails = []
    try:
        rc, out = run_installer(base)
        print("=== 正向安装（-BaseUrl %s）rc=%d ===" % (base, rc))
        for ln in out.split("\n"):
            if any(k in ln for k in ("目标版本", "下载成功", "✅", "❌", "不是 zip", "HTML")):
                print("   " + ln.strip()[:110])
        if rc != 0:
            fails.append("正向安装 rc=%d（应 0）" % rc)
        if not check(out, base):
            fails.append("关键回执缺项（见上面命中表）")
        sandbox_js = os.path.join(BOX, "AppData", "Local", "FIST-Mbt", "fist-mbt.js")
        got = sha8(sandbox_js)
        print("  沙箱产物 = %s（应与镜像一致 sha256:%s）" % (got, real_before))
        if got != real_before:
            fails.append("沙箱装出来的产物与镜像不同（%s ≠ %s）" % (got, real_before))
        shims = sorted(os.listdir(os.path.join(BOX, "User", ".local", "bin")))
        print("  沙箱 bin = %s" % shims)
        if sorted(["fist", "fist.cmd", "fist-mbt", "fist-mbt.cmd"]) != shims:
            fails.append("沙箱 shim 不齐：%s" % shims)
        # 沙箱里的命令真跑一次（PATH 指向沙箱 bin，绝不碰真安装）
        sbin = os.path.join(BOX, "User", ".local", "bin")
        for name, cmd in (("bash → 沙箱 fist version", ["bash", "-c", "fist version"]),
                          ("bash → 沙箱 fist doctor", ["bash", "-c", "fist doctor"])):
            e = dict(os.environ)
            e["PATH"] = sbin + os.pathsep + e.get("PATH", "")
            e["FIST_DB_PATH"] = os.path.join(BOX, "verify.db")
            r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                               errors="replace", cwd=BOX, env=e, timeout=180)
            head = (r.stdout or "").split("\n")[0][:60]
            print("  %-28s rc=%d 首行=%r" % (name, r.returncode, head))
            if r.returncode != 0 or not head:
                fails.append("%s 没跑通（rc=%d）" % (name, r.returncode))
        # 反面对照：镜像里放一个 HTML 冒充资产
        asset = os.path.join(MIRROR, "-", "releases", "download", "v0.3.0", "fist-mbt-js-v0.3.0.zip")
        io.open(asset + ".real", "wb").write(io.open(asset, "rb").read())
        io.open(asset, "w", encoding="utf-8", newline="\n").write(
            "<!DOCTYPE html>\n<html><body>not a zip</body></html>\n" + "x" * 20000)
        box2 = os.path.join(BOX, "neg")
        rc2, out2 = run_installer(base, box=box2)
        print("=== 反面对照（另起沙箱 %s，资产换成 HTML 页）rc=%d ===" % (
            os.path.relpath(box2, ROOT).replace("\\", "/"), rc2))
        for ln in out2.split("\n"):
            if any(k in ln for k in ("zip", "HTML", "http://", "v0.3.0")):
                print("   " + ln.strip()[:110])
        if rc2 == 0:
            fails.append("HTML 冒充资产竟然成功（魔数门没承重）")
        if "PK" not in out2 and "3C-" not in out2.upper():
            fails.append("反面对照没打印换源原因（拒绝必须带理由）")
        io.open(asset, "wb").write(io.open(asset + ".real", "rb").read())
        os.remove(asset + ".real")
        if os.path.isfile(os.path.join(box2, "AppData", "Local", "FIST-Mbt", "fist-mbt.js")):
            fails.append("反面对照竟然装出了产物（失败必须停在下载那一步）")
    finally:
        srv.terminate()
        try:
            srv.wait(timeout=10)
        except Exception:
            srv.kill()
        now = ps_path()
        if now != path_before:
            print("!! 用户 PATH 被改写过 ⇒ 逐字还原")
            set_path(path_before)
            time.sleep(0.5)
            back = ps_path()
            if back != path_before:
                fails.append("用户 PATH 还原失败（%d → %d 字）" % (len(now), len(back)))
            else:
                print("   用户 PATH 已还原（%d 字，逐字相同）" % len(back))
        else:
            print("   用户 PATH 未被改写（%d 字相同）" % len(now))
        real_after = sha8(os.path.join(REAL_DEST, "fist-mbt.js"))
        print("   真产物跑前跑后：sha256:%s → %s（必须相同）" % (real_before, real_after))
        if real_after != real_before:
            fails.append("真安装目录被动了（%s ≠ %s）" % (real_after, real_before))
    print("=== 端到端镜像安装：%s ===" % ("PASS" if not fails else "FAIL"))
    for f in fails:
        print("  FAIL " + f)
    print("证据日志 = %s" % os.path.relpath(LOG, ROOT).replace("\\", "/"))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
