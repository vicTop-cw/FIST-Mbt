#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""e2e_transport_stack_fallback.py — 「安装器内部取数必须能换 TLS 栈」承重判据（BUG-116 内部半 / 判据 R14）。

要证的命题不是「文档那条线能取到脚本」，而是**安装器内部的两发**（moon.mod 与资产 zip）：
本机走系统代理时 .NET 栈（irm/Invoke-WebRequest）会瞬时抛「基础连接已经关闭」，同一时刻 curl.exe
（Schannel 栈）取同一个 URL 却得 200 + 正确字节。旧版只把 curl 兜底放在文档线，内部这两发仍单栈
⇒ 活证据形态是「脚本取回来了、红在内部那一发（无法从 moon.mod 解析版本号）」。

三格（同一镜像、同一套沙箱纪律——复用 e2e_mirror_install 的 harness：env 指沙箱、PATH 顶沙箱 bin、
跑完逐字还原用户 PATH、真安装产物 sha256 只读核对）：
  A 变异 = 内部两处 .NET 取数一律抛**没有 Response 的** WebException（=传输层），curl 在 PATH
           ⇒ 必须 rc=0，且回执里出现 ASCII 记号 curl-fallback（否则绿不是换栈挣来的）。
  B 变异 = 同 A，但把 $script:CurlExe 置空（等价于这台机器没有 curl.exe）⇒ 必须 rc!=0，
           证明 A 的绿是兜底臂挣来的，不是镜像本身好取。
  C 干净 = 不改 installer，正向安装 ⇒ 必须 rc=0（证明 A/B 的夹具没把真路径改坏）。
A 与 B 的**唯一差别**是兜底臂可用性；两格同态 ⇒ 变量没起作用，判据坏，照样红。

两条本仓踩过的口径（都在这份判据自己身上红过一次）：
  · 针一律挑 ASCII：PS 控制台按 cp936 出，中文到这里常已成 "?"，拿中文当针会得到
    "其实成功了却判未命中"的假红（乱码不是证据）。
  · 写变异副本必须带 UTF-8 BOM：含中文的 .ps1 无 BOM 时 PS5.1 按 ANSI 读 ⇒ 字符串字面量在解析期就坏
    （BUG-88；第一版正因缺 BOM 把三格——包括没被变异的 C 格——全跑红，那次是尺子坏不是产品坏）。
  · PowerShell 里 `throw` 是语句不是表达式：`(throw ...).Content` 直接 ParserError，
    必须包成 `(& { throw ... })`。

前置不满足（非 Windows / 真安装目录没产物 ⇒ 镜像无处取材）⇒ rc=3 并报缺什么，跳过不算通过。
用法：python scripts/blackbox/e2e_transport_stack_fallback.py
"""
import importlib.util
import io
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
E2E = os.path.join(HERE, "e2e_mirror_install.py")

# 变异锚：installer 里那两句 .NET 取数 + 兜底臂注册行（逐字，从真源核过，命中数必须各为 1）
ANCHOR_MOD = "Invoke-WebRequest -Uri $r -UseBasicParsing -TimeoutSec 20"
ANCHOR_ZIP = "Invoke-WebRequest -Uri $u -OutFile $zipPath -UseBasicParsing -TimeoutSec 60"
CURL_ANCHOR = ('$script:CurlExe = if (Get-Command curl.exe -ErrorAction SilentlyContinue) '
               '{ (Get-Command curl.exe).Source } else { "" }')
# 传输层形状 = Response 为 null；404/403 带 Response，那时 R12 的闸要求"直接换源、不许重试"
THROW = ('(& { throw (New-Object System.Net.WebException("simulated transport failure", '
         '[System.Net.WebExceptionStatus]::TrustFailure)) })')
MARK = "curl-fallback"


def load_harness():
    spec = importlib.util.spec_from_file_location("mirror_harness", E2E)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def mutated(src_text, curl_off):
    t = src_text.replace(ANCHOR_MOD, THROW, 1)
    t = t.replace(ANCHOR_ZIP, THROW, 1)
    if curl_off:
        t = t.replace(CURL_ANCHOR, '$script:CurlExe = ""  # (变异 B：这台机器没有 curl.exe)', 1)
    return t


def main():
    if os.name != "nt":
        print("SKIP 非 Windows：验的是 install_onecmd.ps1 的内部取数")
        return 3
    h = load_harness()
    if not os.path.isfile(os.path.join(h.REAL_DEST, "fist-mbt.js")):
        print("SKIP 真安装目录里没有产物（%s）⇒ 镜像无处取材（先按文档装一次）" % h.REAL_DEST)
        return 3
    src = io.open(os.path.join(ROOT, "scripts", "blackbox", "install_onecmd.ps1"),
                  encoding="utf-8-sig").read()
    for anchor in (ANCHOR_MOD, ANCHOR_ZIP, CURL_ANCHOR):
        if src.count(anchor) != 1:
            print("FATAL 变异锚命中 %d 次（应为 1）：%s ⇒ 判据看不见被检面，不自证"
                  % (src.count(anchor), anchor[:52]))
            return 2

    boxdir = os.path.join(ROOT, "temp", "r14-canary")
    os.makedirs(boxdir, exist_ok=True)
    cells = [("A", mutated(src, False), 0), ("B", mutated(src, True), None), ("C", src, 0)]
    port = h.free_port()
    real_before = h.sha8(os.path.join(h.REAL_DEST, "fist-mbt.js"))
    path_before = h.ps_path()
    print("沙箱外基线：真产物 sha256:%s / 用户 PATH 长度 %d" % (real_before, len(path_before)))
    srv, base = h.build_mirror(port)
    results, fails = [], []
    try:
        for tag, text, want in cells:
            inst = os.path.join(boxdir, "installer_%s.ps1" % tag)
            io.open(inst, "w", encoding="utf-8-sig", newline="\n").write(text)
            h.INSTALLER = inst
            box = os.path.join(boxdir, "box_" + tag)
            rc, out = h.run_installer(base, box=box)
            hit = MARK in out
            results.append((tag, rc, hit))
            print("=== 格 %s（期望 rc=%s）实得 rc=%s  ASCII 记号 %s 命中=%s"
                  % (tag, "0" if want == 0 else "≠0", rc, MARK, hit))
            if want == 0 and rc != 0:
                fails.append("格 %s：应 rc=0，实得 %s（正文见 %s）"
                             % (tag, rc, os.path.join(box, "run.log")))
            if tag == "A" and rc == 0 and not hit:
                fails.append("格 A：装通了却没有换栈记号 ⇒ 绿不是兜底臂挣来的（变异没生效？）")
            # B 的负门要的是「一个真非零退出码」：rc=None（超时/没起跑）同样算判据坏，
            # 否则安装器根本没跑起来也会被读成「B 如预期红了」。
            if tag == "B" and (rc == 0 or rc is None or not isinstance(rc, int)):
                fails.append("格 B：curl 不可用却得到 rc=%r ⇒ A 的绿与兜底臂无关（或这一格根本没起跑），判据不承重"
                             % (rc,))
    finally:
        srv.terminate()
        try:
            srv.wait(timeout=10)
        except Exception:
            srv.kill()
        now = h.ps_path()
        if now != path_before:
            print("!! 用户 PATH 被改写过 ⇒ 逐字还原")
            h.set_path(path_before)
            time.sleep(0.5)
            back = h.ps_path()
            if back != path_before:
                fails.append("用户 PATH 还原失败（%d → %d 字）" % (len(now), len(back)))
            else:
                print("   用户 PATH 已还原（%d 字，逐字相同）" % len(back))
        else:
            print("   用户 PATH 未被改写（%d 字相同）" % len(path_before))
        real_after = h.sha8(os.path.join(h.REAL_DEST, "fist-mbt.js"))
        print("   真产物跑前跑后：sha256:%s → %s（必须相同）" % (real_before, real_after))
        if real_after != real_before:
            fails.append("真安装目录被动了（%s ≠ %s）" % (real_after, real_before))

    a_rc = next((r[1] for r in results if r[0] == "A"), None)
    b_rc = next((r[1] for r in results if r[0] == "B"), None)
    if a_rc is None or b_rc is None or (a_rc == 0) == (b_rc == 0):
        fails.append("A/B 两格同态（rc 序列 %s）⇒ 唯一变量没起作用，判据坏"
                     % ([r[1] for r in results],))
    for f in fails:
        print("VIOLATION " + f)
    if fails:
        print("=== 端到端传输层换栈判据：FAIL ===")
        return 1
    print("=== 端到端传输层换栈判据：PASS（A 换栈装通 / B 无 curl 必红 / C 正向不误伤）===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
