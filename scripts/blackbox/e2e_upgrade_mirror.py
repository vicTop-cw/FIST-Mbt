#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
e2e_upgrade_mirror.py — fist-mbt upgrade 写盘路径五格端到端（设计文档 §6.3 五格真跑）

五格（每格 PASS/FAIL）：
  C1 升级成功       : 已装 v0.3.7 → 远端 v0.3.9；`.bak-0.3.7` 存在；VERSION=0.3.9
  C2 已是最新不重装 : 已装 v0.3.9 = 远端 v0.3.9；镜像未发生 `/releases/download/` 下载；无 `.bak`
  C3 损坏回滚       : 资产 zip 换成 20KB HTML 页；rc!=0；fist-mbt.js 仍 v0.3.7；`.bak-0.3.7` 保留
  C4 无网络不假绿   : --base-url 指死端口 127.0.0.1:9（latest 探测真传输层失败，不用 mock）；rc=3；stderr 命中「无法检测最新版本」；绝不「已是最新」
  C5 VERSION 兼容回退: 删 VERSION；`read_local` 反解 `node fist-mbt.js version`；仍得 v0.3.7；升级成功

真实约束（本判据与实现的接线）：
  * `cmd/cli/upgrade_js.mbt` 的 `js_fetch_latest` 尊重 `--base-url`（BUG-C 已修复）：
    base_url 非空时打镜像 `/releases/latest` 取 tag，空才走 api.github.com。
    其余格（C1/C2/C3/C5）仍用一个 `NODE_OPTIONS=--import=<shim>` 的 fetch 补丁拦截目标
    URL 那一次调用（让 latest 探测确定命中镜像 tag；只拦截 cfg.target 子串命中的调用，其余 fetch 原样）。
    **格 4 不用 mock**：改指 `--base-url http://127.0.0.1:9`（死端口），让 latest 探测在真实
    传输层失败——这才是「网络断/远端指错」不假绿的硬证据（mock 只能证明「拦截到的那次 fetch 失败」）。
    镜像按实现真源服务 `/scripts/blackbox/upgrade_install.ps1`（新 tracked 安装器真源，
    BUG-236 修复：升级安装器提升为 tracked 脚本）与 `/-/releases/download/vX/fist-mbt-js-vX.zip`
    （新安装器实际请求的 zip 形状，与 irm 安装器同源）；另保留 `/releases/latest` 与
    `/releases/download/vX/...` 两个文档形（BUG-C 已修复：`js_fetch_latest` 尊重 `--base-url`
    走镜像 `/releases/latest`——见 `--audit-mirror-shapes`）。旧 `/_release/...` 形已删
    （`_release/` 不再持久升级安装器）。
  * 沙箱把 LOCALAPPDATA/USERPROFILE/TEMP 指 `temp/upg-e2e-sandbox`，绝不碰真 `%LOCALAPPDATA%\FIST-Mbt`；
    用户级 PATH 跑前抓原值、跑完逐字还原并复核；真安装目录产物 sha256 跑前跑后必须相同。
  * 每次跑沙箱清场（BUG-117 同型：上一轮的旧产物会让判据红在旧状态上）。

用法：python scripts/blackbox/e2e_upgrade_mirror.py [--cli <cli.js>] [--keep-sandbox] [--audit-mirror-shapes]
前置不满足（非 Windows / cli.js 未构建）⇒ rc=3 并报缺什么。
"""
import hashlib
import io
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# BUG-58/138：本脚本会 print 中文结论；Windows 默认 cp936 控制台上不重配 UTF-8 会在
# 打印结论行时抛 UnicodeEncodeError，留下 traceback + rc=1（冒用「缺陷在场」档）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_CLI = os.path.join(ROOT, "_build", "js", "debug", "build", "cmd", "cli", "cli.js")
SANDBOX = os.path.join(ROOT, "temp", "upg-e2e-sandbox")
REAL_DEST = os.path.join(os.environ.get("LOCALAPPDATA", ""), "FIST-Mbt")
INSTALLER = os.path.join(ROOT, "scripts", "blackbox", "upgrade_install.ps1")

# 五格统一远端 tag（设计文档 §6.3 示例；mock 与镜像都用它）
REMOTE = "0.3.9"
LOCAL_INSTALL = "0.3.7"   # 沙箱初始已装版本
HTML_PAGE = ("<!doctype html><html><body>" + "x" * 20000 + "</body></html>")


def sha8(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(65536), b""):
            h.update(b)
    return h.hexdigest()[:8]


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    p = s.getsockname()[1]
    s.close()
    return p


def ps_get_user_path():
    return subprocess.run(
        ["powershell", "-NoProfile", "-Command",
         "[Environment]::GetEnvironmentVariable('Path','User')"],
        capture_output=True, text=True, encoding="utf-8", errors="replace").stdout.strip()


def ps_set_user_path(val):
    subprocess.run(["powershell", "-NoProfile", "-Command",
                    "[Environment]::SetEnvironmentVariable('Path', '%s', 'User')"
                    % val.replace("'", "")],
                   capture_output=True, text=True, encoding="utf-8", errors="replace")


def write_text(p, content):
    io.open(p, "w", encoding="utf-8", newline="\n").write(content)


def read_text(p):
    with open(p, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def make_stub_js(version):
    """CJS 桩：`node fist-mbt.js help`/`version` 退出 0；version 回 `FIST-Mbt v<ver>`。"""
    return (
        "'use strict';\n"
        "const VERSION = '%s';\n"
        "const args = process.argv.slice(2);\n"
        "if (args[0] === 'version') { console.log('FIST-Mbt v' + VERSION); process.exit(0); }\n"
        "if (args[0] === 'help') { console.log('fist-mbt stub help'); process.exit(0); }\n"
        "console.log('fist-mbt stub (no command)'); process.exit(0);\n"
        "module.exports = { VERSION: VERSION };\n" % version
    )


def make_mock_shim(path):
    """fetch 补丁 shim：仅拦截 cfg.target 一次调用；cfg.fail=true 时模拟网络断。"""
    write_text(path, """\
import fs from 'node:fs'
const cfgPath = process.env.FIST_UPGRADE_MOCK_API
let cfg = { target: '', tag: '', fail: false }
if (cfgPath) { try { cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8')) } catch (e) {} }
const realFetch = globalThis.fetch
globalThis.fetch = async function (url, opts) {
  let u = ''
  try { u = typeof url === 'string' ? url : String(url) } catch (e) {}
  if (cfg.target && u.indexOf(cfg.target) !== -1) {
    if (cfg.fail) { throw new Error('fetch failed: mock network unreachable (ECONNREFUSED)') }
    const status = cfg.status ? cfg.status : 200
    const body = status === 200
      ? JSON.stringify({ tag_name: cfg.tag })
      : JSON.stringify({ message: 'Not Found' })
    return new Response(body, { status: status, headers: { 'Content-Type': 'application/json' } })
  }
  return realFetch.call(this, url, opts)
}
""")


def make_zip_src(dirpath, version):
    os.makedirs(dirpath, exist_ok=True)
    write_text(os.path.join(dirpath, "fist-mbt.js"), make_stub_js(version))
    write_text(os.path.join(dirpath, "patch_esm_main.py"), "# stub patch (no-op)\n")
    return dirpath


def ps_zip(src_dir, zip_path):
    # Compress-Archive: 让 fist-mbt.js 在 zip 根
    r = subprocess.run(
        ["powershell", "-NoProfile", "-Command",
         "Compress-Archive -Path '%s\\*' -DestinationPath '%s' -Force"
         % (src_dir.replace("'", ""), zip_path.replace("'", ""))],
        capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.returncode


class Mirror:
    """本地镜像：服务安装器 + 资产 zip + 文档形三个面；记录每次请求。
    `versions` 支持多版本资产（格 1 预装 v0.3.7 需 `fist-mbt-js-v0.3.7.zip`）。"""

    def __init__(self, mirror_dir, remote, versions=None):
        self.dir = mirror_dir
        self.remote = remote
        self.versions = list(set([remote] + list(versions or [])))
        self.requests = []          # (method, path, status)
        self.zip_ok = True          # False ⇒ 资产换成 HTML 页（格 3）
        self._lock = threading.Lock()
        self.zip_path = os.path.join(self.dir, "fist-mbt-js-v%s.zip" % remote)
        self._prep()

    def _prep(self):
        os.makedirs(self.dir, exist_ok=True)
        # 安装器（真实脚本，从仓库 tracked 真源取；CLI 的 fetch_installer 走这个）
        shutil.copyfile(INSTALLER, os.path.join(self.dir, "upgrade_install.ps1"))
        for ver in self.versions:
            src = os.path.join(self.dir, "_src-%s" % ver)
            zip_p = os.path.join(self.dir, "fist-mbt-js-v%s.zip" % ver)
            make_zip_src(src, ver)
            if ps_zip(src, zip_p) != 0:
                raise RuntimeError("Compress-Archive 失败，无法造资产 zip v%s" % ver)
            shutil.rmtree(src, ignore_errors=True)

    def latest_json(self):
        return json.dumps({"tag_name": "v" + self.remote, "name": "v" + self.remote}).encode()

    def start(self):
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), self._handler())
        self.port = self.httpd.server_address[1]
        self.base = "http://127.0.0.1:%d" % self.port
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()
        return self.base

    def _handler(self):
        mirror = self

        class H(BaseHTTPRequestHandler):
            def log_message(self, *a, **k):
                pass

            def _record(self, status):
                with mirror._lock:
                    mirror.requests.append((self.command, self.path, status))

            def do_GET(self):
                p = self.path.split("?")[0]
                if p == "/releases/latest":
                    body = mirror.latest_json()
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                    self._record(200)
                    return
                if p == "/scripts/blackbox/upgrade_install.ps1":
                    fp = os.path.join(mirror.dir, "upgrade_install.ps1")
                    body = open(fp, "rb").read()
                    self.send_response(200)
                    self.send_header("Content-Type", "text/plain")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                    self._record(200)
                    return
                # 资产：实现真源（新安装器实际请求）`/-/releases/download/vX/fist-mbt-js-vX.zip`
                # + 文档形 `/releases/download/vX/...`（旧 `/_release/...` 形已随 BUG-236 删除）
                zip_for = None
                m1 = re.match(r"^/-/releases/download/v([0-9.]+)/fist-mbt-js-v\1\.zip$", p)
                m2 = re.match(r"^/releases/download/v([0-9.]+)/fist-mbt-js-v\1\.zip$", p)
                if m1:
                    zip_for = m1.group(1)
                elif m2:
                    zip_for = m2.group(1)
                if zip_for is not None:
                    if zip_for not in mirror.versions:
                        self.send_response(404)
                        self.send_header("Content-Length", "0")
                        self.end_headers()
                        self._record(404)
                        return
                    if not mirror.zip_ok:
                        body = HTML_PAGE.encode()
                    else:
                        body = open(os.path.join(mirror.dir, "fist-mbt-js-v%s.zip" % zip_for), "rb").read()
                    self.send_response(200)
                    self.send_header("Content-Type", "application/zip")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                    self._record(200)
                    return
                self.send_response(404)
                self.send_header("Content-Length", "0")
                self.end_headers()
                self._record(404)

        return H

    def stop(self):
        try:
            self.httpd.shutdown()
            self.httpd.server_close()
        except Exception:
            pass

    def hits(self, prefix):
        return [p for (_m, p, _s) in self.requests if p.startswith(prefix)]

    def download_hits(self):
        return [p for (_m, p, _s) in self.requests if "/releases/download/" in p]

    def clear_hits(self):
        """清掉已记录的请求（预装本身也会下载一次资产 zip，格 2 的
        「已是最新不该下载」断言必须排除预装自己那一发，否则是假红）。"""
        del self.requests[:]


class Box:
    """沙箱：把 LOCALAPPDATA/USERPROFILE/TEMP 指到 temp/upg-e2e-sandbox/<cell>。"""

    def __init__(self, name):
        self.root = os.path.join(SANDBOX, name)
        self.install_root = os.path.join(self.root, "AppData", "Local", "FIST-Mbt")
        self.env = dict(os.environ)

    def fresh(self):
        shutil.rmtree(self.root, ignore_errors=True)
        # 注意：**不要**预建 install_root（upgrade_install.ps1 非 -Force 时见 $InstallRoot
        # 存在即 "Already installed ... Use -Force to reinstall." 退出 0 —— 上一轮实测踩到，
        # 五格全部假红在"没真装"上）。只建 sandbox 骨架目录。
        for d in (os.path.join(self.root, "AppData", "Local"),
                  os.path.join(self.root, "User"),
                  os.path.join(self.root, "Temp"),
                  os.path.join(self.root, "bin")):
            os.makedirs(d, exist_ok=True)
        self.env["LOCALAPPDATA"] = os.path.join(self.root, "AppData", "Local")
        self.env["USERPROFILE"] = os.path.join(self.root, "User")
        self.env["TEMP"] = self.env["TMP"] = os.path.join(self.root, "Temp")
        # 沙箱 bin 顶到 PATH 最前，防止解析到真已装的全局 fist.cmd
        self.env["PATH"] = os.path.join(self.root, "bin") + os.pathsep + self.env.get("PATH", "")
        # mock API 配置路径：让 fetch 补丁读得到（子进程 env 继承）
        self.env["FIST_UPGRADE_MOCK_API"] = ""

    def set_mock(self, cfg, shim_path):
        write_text(os.path.join(self.root, "mockapi.json"), json.dumps(cfg))
        self.env["FIST_UPGRADE_MOCK_API"] = os.path.join(self.root, "mockapi.json")
        # NODE_OPTIONS=--import=file:///... （Node ESM loader 只认 file: URL）
        url = "file:///" + shim_path.replace("\\", "/").lstrip("/")
        self.env["NODE_OPTIONS"] = "--import=" + url

    def js_bin(self):
        return os.path.join(self.install_root, "fist-mbt.js")

    def version_file(self):
        return os.path.join(self.install_root, "VERSION")

    def bak(self, v):
        return os.path.join(self.install_root, "fist-mbt.js.bak-" + v)

    def read_installed(self):
        """读沙箱已装版本：VERSION 优先，否则反解 node version。"""
        vf = self.version_file()
        if os.path.isfile(vf):
            v = read_text(vf).strip()
            if v:
                return v
        r = subprocess.run(["node", self.js_bin(), "version"],
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
        if r.returncode == 0:
            import re
            m = re.search(r"FIST-Mbt v([^\s]+)", r.stdout)
            if m:
                return m.group(1)
        return None

    def run_cli(self, cli, args):
        """跑 cli.js upgrade <args>，返回 (rc, stdout, stderr)。"""
        r = subprocess.run(["node", cli, "upgrade"] + args,
                           capture_output=True, text=True, encoding="utf-8",
                           errors="replace", env=self.env, cwd=self.root, timeout=600)
        return r.returncode, r.stdout or "", r.stderr or ""


class Cell:
    """一格：setup 后 run，返回 (passed, detail)。"""

    def __init__(self, cli, shim):
        self.cli = cli
        self.shim = shim

    # ---- 工具 ----
    def install_into(self, box, base, version, extra=None):
        """用真安装器把版本 version 装进沙箱（写 VERSION + fist-mbt.js）。"""
        box.fresh()
        cmd = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", INSTALLER,
               "-BaseUrl", base, "-Version", version, "-NoPath"] + (extra or [])
        r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                           errors="replace", env=box.env, cwd=box.root, timeout=600)
        write_text(os.path.join(box.root, "install.log"),
                   "rc=%d\n=== stdout ===\n%s\n=== stderr ===\n%s\n"
                   % (r.returncode, r.stdout, r.stderr))
        return r.returncode, (r.stdout or "") + (r.stderr or "")

    # ---- 格 1：升级成功 ----
    def cell1(self):
        mirror = Mirror(os.path.join(SANDBOX, "mirror-1"), REMOTE, versions=[LOCAL_INSTALL])
        base = mirror.start()
        box = Box("c1")
        rc, out = self.install_into(box, base, LOCAL_INSTALL)
        detail = ["mirror=%s" % base]
        fails = []
        if rc != 0:
            fails.append("预安装 rc=%d" % rc)
        if box.read_installed() != LOCAL_INSTALL:
            fails.append("预装版本 %r != %r" % (box.read_installed(), LOCAL_INSTALL))
        # mock API：拦截 base_url 下 `/releases/latest` 那一次 fetch，返回远端 tag
        # （BUG-C 已修复：js_fetch_latest 尊重 --base-url，镜像形即 CLI 真走的路径）
        box.set_mock({"target": base + "/releases/latest",
                      "tag": "v" + REMOTE, "fail": False}, self.shim)
        crc, so, se = box.run_cli(self.cli, ["--base-url", base, "--no-path"])
        detail.append("upgrade rc=%d" % crc)
        detail.append("upgrade stdout: %s" % so.replace("\n", " | ").strip())
        detail.append("upgrade stderr: %s" % se.replace("\n", " | ").strip())
        detail.append("[diag] install_root 内文件: %s"
                      % os.listdir(box.install_root)
                      if os.path.isdir(box.install_root) else "[no dir]")
        # 关键诊断：upgrade 阶段的镜像下载是否发生（run_installer 传 -Force；安装器清场
        # 时保留 fist-mbt.js.bak-*（BUG-235），zip 应命中 /-/releases/download/ 形）
        detail.append("[diag] mirror 全请求: %s" % mirror.requests)
        detail.append("[diag] mirror 资产下载 %d: %s" % (len(mirror.download_hits()), mirror.download_hits()))
        if crc != 0:
            fails.append("upgrade rc=%d（应 0）" % crc)
        if "升级成功" not in so:
            fails.append("缺「升级成功」回执")
        if box.read_installed() != REMOTE:
            fails.append("装后版本 %r != %r" % (box.read_installed(), REMOTE))
        if not os.path.isfile(box.bak(LOCAL_INSTALL)):
            fails.append("缺备份 .bak-%s" % LOCAL_INSTALL)
        if not os.path.isfile(box.js_bin()):
            fails.append("缺 fist-mbt.js")
        # 镜像下载命中（应为 1：资产 zip）
        dl = mirror.download_hits()
        detail.append("mirror 资产下载命中 %d: %s" % (len(dl), dl))
        mirror.stop()
        return not fails, detail, fails

    # ---- 格 2：已是最新不重装 ----
    def cell2(self):
        mirror = Mirror(os.path.join(SANDBOX, "mirror-2"), REMOTE, versions=[LOCAL_INSTALL])
        base = mirror.start()
        box = Box("c2")
        rc, out = self.install_into(box, base, REMOTE)
        # 预装本身会下载一次资产 zip，清掉预装的请求，让格 2 的「不下载」只量 upgrade 自己
        mirror.clear_hits()
        detail = ["mirror=%s" % base]
        fails = []
        if rc != 0:
            fails.append("预装 rc=%d" % rc)
        if box.read_installed() != REMOTE:
            fails.append("预装版本 %r != %r" % (box.read_installed(), REMOTE))
        box.set_mock({"target": base + "/releases/latest",
                      "tag": "v" + REMOTE, "fail": False}, self.shim)
        crc, so, se = box.run_cli(self.cli, ["--base-url", base, "--no-path"])
        detail.append("upgrade rc=%d" % crc)
        detail.append("upgrade stdout: %s" % so.replace("\n", " | ").strip())
        detail.append("upgrade stderr: %s" % se.replace("\n", " | ").strip())
        detail.append("[diag] install_root 内文件: %s"
                      % os.listdir(box.install_root)
                      if os.path.isdir(box.install_root) else "[no dir]")
        # 关键诊断：upgrade 阶段的镜像下载是否发生（run_installer 传 -Force；安装器清场
        # 时保留 fist-mbt.js.bak-*（BUG-235），zip 应命中 /-/releases/download/ 形）
        detail.append("[diag] mirror 全请求: %s" % mirror.requests)
        detail.append("[diag] mirror 资产下载 %d: %s" % (len(mirror.download_hits()), mirror.download_hits()))
        if crc != 0:
            fails.append("upgrade rc=%d（应 0）" % crc)
        if "已是最新" not in so:
            fails.append("缺「已是最新」回执")
        dl = mirror.download_hits()
        detail.append("mirror 资产下载命中 %d: %s" % (len(dl), dl))
        if dl:
            fails.append("已是最新仍发生下载 %d 次：%s" % (len(dl), dl))
        if os.path.exists(box.bak(LOCAL_INSTALL)) or \
           os.path.exists(box.bak(REMOTE)) or \
           [f for f in os.listdir(box.install_root)
            if f.startswith("fist-mbt.js.bak-")] != []:
            fails.append("已是最新却产生了 .bak 备份")
        mirror.stop()
        return not fails, detail, fails

    # ---- 格 3：损坏回滚 ----
    def cell3(self):
        mirror = Mirror(os.path.join(SANDBOX, "mirror-3"), REMOTE, versions=[LOCAL_INSTALL])
        base = mirror.start()
        box = Box("c3")
        # 先预装（镜像正常），装完才把资产换成 HTML 页 ⇒ 损坏只打在 upgrade 这一发
        rc, out = self.install_into(box, base, LOCAL_INSTALL)
        mirror.zip_ok = False     # 资产换成 HTML 页
        detail = ["mirror=%s" % base]
        fails = []
        if rc != 0:
            fails.append("预装 rc=%d" % rc)
        if box.read_installed() != LOCAL_INSTALL:
            fails.append("预装版本 %r != %r" % (box.read_installed(), LOCAL_INSTALL))
        box.set_mock({"target": base + "/releases/latest",
                      "tag": "v" + REMOTE, "fail": False}, self.shim)
        crc, so, se = box.run_cli(self.cli, ["--base-url", base, "--no-path"])
        detail.append("upgrade rc=%d" % crc)
        detail.append("upgrade stdout: %s" % so.replace("\n", " | ").strip())
        detail.append("upgrade stderr: %s" % se.replace("\n", " | ").strip())
        detail.append("[diag] install_root 内文件: %s"
                      % os.listdir(box.install_root)
                      if os.path.isdir(box.install_root) else "[no dir]")
        # 关键诊断：upgrade 阶段的镜像下载是否发生（run_installer 传 -Force；安装器清场
        # 时保留 fist-mbt.js.bak-*（BUG-235），zip 应命中 /-/releases/download/ 形）
        detail.append("[diag] mirror 全请求: %s" % mirror.requests)
        detail.append("[diag] mirror 资产下载 %d: %s" % (len(mirror.download_hits()), mirror.download_hits()))
        if crc == 0:
            fails.append("upgrade rc=0（应 !=0；损坏资产必须失败）")
        if "已是最新" in so:
            fails.append("损坏格不得打「已是最新」（假绿）")
        if box.read_installed() != LOCAL_INSTALL:
            fails.append("回滚后版本 %r != %r" % (box.read_installed(), LOCAL_INSTALL))
        if not os.path.isfile(box.bak(LOCAL_INSTALL)):
            fails.append("损坏格也应保留 .bak-%s（换入失败才还原，但备份不应被删）"
                         % LOCAL_INSTALL)
        mirror.stop()
        return not fails, detail, fails

    # ---- 格 4：无网络不假绿 ----
    def cell4(self):
        # 强化（②）：不再用 mock 拦截，改用 --base-url 指向一个**死端口**（127.0.0.1:9，
        # 无服务监听）。BUG-C 修复后 js_fetch_latest 尊重 --base-url，会去
        # http://127.0.0.1:9/releases/latest 取远端 tag —— 连接被拒（真传输层失败），
        # CLI 必须回 rc=3 + stderr「无法检测最新版本」，绝不假绿「已是最新」。
        # 这覆盖了 BUG-C 修复后的真实路径（mock 只证「网络断不假绿」，死端口证「base-url 指错不假绿」）。
        dead = "http://127.0.0.1:9"
        mirror = Mirror(os.path.join(SANDBOX, "mirror-4"), REMOTE, versions=[LOCAL_INSTALL])
        base = mirror.start()
        box = Box("c4")
        rc, out = self.install_into(box, base, LOCAL_INSTALL)
        detail = ["install_mirror=%s" % base, "dead_base_url=%s" % dead]
        fails = []
        if rc != 0:
            fails.append("预装 rc=%d" % rc)
        # 注意：本格**不设 mock**——mock 拦截的是镜像 /releases/latest，而这里 CLI 的
        # --base-url 指死端口，latest 探测根本不会碰镜像。mock 在此是死代码，去掉以贴近真实。
        crc, so, se = box.run_cli(self.cli, ["--base-url", dead, "--no-path"])
        detail.append("upgrade rc=%d" % crc)
        detail.append("upgrade stdout: %s" % so.replace("\n", " | ").strip())
        detail.append("upgrade stderr: %s" % se.replace("\n", " | ").strip())
        detail.append("[diag] install_root 内文件: %s"
                      % os.listdir(box.install_root)
                      if os.path.isdir(box.install_root) else "[no dir]")
        # 诊断：死端口下 latest 探测失败 ⇒ 不应有任何升级下载动作
        detail.append("[diag] mirror 资产下载 %d: %s" % (len(mirror.download_hits()), mirror.download_hits()))
        if crc != 3:
            fails.append("upgrade rc=%d（应 3：无法检测最新版本）" % crc)
        if "无法检测最新版本" not in se:
            fails.append("stderr 缺「无法检测最新版本」（死端口下 js_fetch_latest 应报传输层失败）")
        if "已是最新" in so or "已是最新" in se:
            fails.append("网络断/死端口却打「已是最新」（假绿）")
        if box.read_installed() != LOCAL_INSTALL:
            fails.append("探测失败后已装版本被改动：%r" % box.read_installed())
        mirror.stop()
        return not fails, detail, fails

    # ---- 格 5：VERSION 兼容回退 ----
    def cell5(self):
        mirror = Mirror(os.path.join(SANDBOX, "mirror-5"), REMOTE, versions=[LOCAL_INSTALL])
        base = mirror.start()
        box = Box("c5")
        rc, out = self.install_into(box, base, LOCAL_INSTALL)
        detail = ["mirror=%s" % base]
        fails = []
        if rc != 0:
            fails.append("预装 rc=%d" % rc)
        if box.read_installed() != LOCAL_INSTALL:
            fails.append("预装版本 %r != %r" % (box.read_installed(), LOCAL_INSTALL))
        # 删 VERSION ⇒ read_local 走 `node fist-mbt.js version` 反解
        if os.path.isfile(box.version_file()):
            os.remove(box.version_file())
        box.set_mock({"target": base + "/releases/latest",
                      "tag": "v" + REMOTE, "fail": False}, self.shim)
        crc, so, se = box.run_cli(self.cli, ["--base-url", base, "--no-path"])
        detail.append("upgrade rc=%d" % crc)
        detail.append("upgrade stdout: %s" % so.replace("\n", " | ").strip())
        detail.append("upgrade stderr: %s" % se.replace("\n", " | ").strip())
        detail.append("[diag] install_root 内文件: %s"
                      % os.listdir(box.install_root)
                      if os.path.isdir(box.install_root) else "[no dir]")
        # 关键诊断：upgrade 阶段的镜像下载是否发生（run_installer 传 -Force；安装器清场
        # 时保留 fist-mbt.js.bak-*（BUG-235），zip 应命中 /-/releases/download/ 形）
        detail.append("[diag] mirror 全请求: %s" % mirror.requests)
        detail.append("[diag] mirror 资产下载 %d: %s" % (len(mirror.download_hits()), mirror.download_hits()))
        if crc != 0:
            fails.append("upgrade rc=%d（应 0）" % crc)
        if "升级成功" not in so:
            fails.append("缺「升级成功」回执")
        if box.read_installed() != REMOTE:
            fails.append("装后版本 %r != %r" % (box.read_installed(), REMOTE))
        if not os.path.isfile(box.bak(LOCAL_INSTALL)):
            fails.append("缺备份 .bak-%s（VERSION 回退后应仍按 v%s 备份）"
                         % (LOCAL_INSTALL, LOCAL_INSTALL))
        mirror.stop()
        return not fails, detail, fails


# ---- 文档形面审计（CLI 到底用没用镜像的 /releases/latest） ----
def audit_mirror_shapes(cli, shim):
    """把镜像文档形面全部备齐，跑一次 `upgrade --check --base-url <mirror>`，
    正向验证 CLI 真的走镜像 `/releases/latest` 取 tag（BUG-C 已修复：
    js_fetch_latest 尊重 --base-url，base_url 非空即打镜像形）。"""
    mirror = Mirror(os.path.join(SANDBOX, "mirror-audit"), REMOTE, versions=[LOCAL_INSTALL])
    base = mirror.start()
    box = Box("c-audit")
    box.fresh()
    box.set_mock({"target": base + "/releases/latest",
                  "tag": "v" + REMOTE, "fail": False}, shim)
    crc, so, se = box.run_cli(cli, ["--check", "--base-url", base])
    dl = mirror.download_hits()
    print("  [audit] 镜像请求 %d 条，其中 /releases/latest 命中 %d，资产下载 %d"
          % (len(mirror.requests),
             len(mirror.hits("/releases/latest")), len(dl)))
    for (m, p, s) in mirror.requests:
        print("    %s %s → %d" % (m, p, s))
    print("  [audit] --check rc=%d" % crc)
    print("  [audit] --check stdout: %s" % so.strip().replace("\n", " | "))
    print("  [audit] --check stderr: %s" % se.strip().replace("\n", " | "))
    mirror.stop()
    # 结论（BUG-C 修复后为正向断言）：CLI 走镜像 `/releases/latest` 取 tag 并拿到「远端最新」
    # = 镜像文档形 `/releases/latest` 已被阶段 2 使用（js_fetch_latest 尊重 --base-url）。
    if mirror.hits("/releases/latest") and ("远端最新" in so):
        return True
    return False


def main():
    cli = DEFAULT_CLI
    audit = False
    keep = False
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--cli":
            i += 1
            cli = args[i]
        elif args[i] == "--audit-mirror-shapes":
            audit = True
        elif args[i] == "--keep-sandbox":
            keep = True
        else:
            print("用法: e2e_upgrade_mirror.py [--cli <cli.js>] [--audit-mirror-shapes] [--keep-sandbox]")
            return 2
        i += 1

    if os.name != "nt":
        print("SKIP 非 Windows：upgrade 走 pwsh -File upgrade_install.ps1，仅 Windows 可跑")
        return 3
    if not os.path.isfile(cli):
        print("SKIP cli.js 不存在：%s（先 `moon build --target js cmd/cli`）" % cli)
        return 3
    if not os.path.isfile(INSTALLER):
        print("SKIP 安装器不存在：%s" % INSTALLER)
        return 3

    # 沙箱外基线：真安装产物 sha256 + 用户 PATH 原值
    real_js = os.path.join(REAL_DEST, "fist-mbt.js") if REAL_DEST else ""
    real_before = sha8(real_js) if os.path.isfile(real_js) else ""
    path_before = ps_get_user_path()
    print("== fist-mbt upgrade 五格端到端 ==")
    print("cli:      %s" % cli)
    print("沙箱:      %s" % SANDBOX)
    print("真产物基线: sha256=%s 存在=%s" % (real_before, os.path.isfile(real_js)))
    print("用户 PATH 长度: %d" % len(path_before))

    shutil.rmtree(SANDBOX, ignore_errors=True)
    os.makedirs(SANDBOX, exist_ok=True)
    shim_path = os.path.join(SANDBOX, "mock_fetch.mjs")
    make_mock_shim(shim_path)

    results = []
    try:
        cells = [("C1 升级成功", Cell(cli, shim_path).cell1),
                 ("C2 已是最新不重装", Cell(cli, shim_path).cell2),
                 ("C3 损坏回滚", Cell(cli, shim_path).cell3),
                 ("C4 无网络不假绿", Cell(cli, shim_path).cell4),
                 ("C5 VERSION 兼容回退", Cell(cli, shim_path).cell5)]
        for name, fn in cells:
            print("\n--- %s ---" % name)
            passed, detail, fails = fn()
            for d in detail:
                print("  " + d)
            if fails:
                for f in fails:
                    print("  [FAIL] " + f)
            results.append((name, passed, fails))
            print("  判定: %s" % ("PASS" if passed else "FAIL"))

        if audit:
            print("\n--- 审计：镜像文档形三面是否被 CLI 使用 ---")
            used = audit_mirror_shapes(cli, shim_path)
            print("  结论: CLI 用镜像 /releases/latest 取 tag 并拿到「远端最新」= %s"
                  % ("是（BUG-C 已修复：js_fetch_latest 尊重 --base-url）" if used
                     else "否"))

        n_pass = sum(1 for (_n, p, _f) in results if p)
        print("\n===== 汇总: %d/5 PASS =====" % n_pass)
        for name, passed, fails in results:
            print("  %-22s %s%s" % (name, "PASS" if passed else "FAIL",
                                   "" if passed else " <- " + "; ".join(fails)))
        # 沙箱后置核对
        real_after = sha8(real_js) if os.path.isfile(real_js) else ""
        path_after = ps_get_user_path()
        print("真产物 sha256: before=%s after=%s same=%s"
              % (real_before, real_after, real_before == real_after))
        print("用户 PATH 还原: same=%s" % (path_before == path_after))
        if real_before != real_after:
            print("  [FAIL] 真安装目录产物被改动！")
        if path_before != path_after:
            print("  [FAIL] 用户 PATH 未逐字还原！")
            ps_set_user_path(path_before)
        if not keep:
            shutil.rmtree(SANDBOX, ignore_errors=True)
            print("沙箱已清场: %s" % (not os.path.exists(SANDBOX)))
        return 0 if n_pass == 5 and real_before == real_after and path_before == path_after else 1
    finally:
        pass


if __name__ == "__main__":
    sys.exit(main())