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

两档（沙箱档，2026-09-29 起两臂并列）：
  主档 = README 首选线 `iex ((irm …).ToString().TrimStart([char]0xFEFF))`（irm / .NET 栈）
  兜底档 = README 兜底线 `curl.exe -sSL … -o $env:TEMP\…; powershell … -File $env:TEMP\…`
        （curl.exe / Schannel 栈，BUG-116：本机 TLS 中间盒下 irm 取不到脚本而 curl 取得到）
  真用户面档 --real：装到 %LOCALAPPDATA%\FIST-Mbt，跑前备份现有产物；
        装完 `fist version`/`fist doctor` 不绿就自动还原并如实报 FAIL。

两臂各自独立清场（BUG-117：**每臂一个沙箱、每次跑前 rmtree**，绝不拿上一轮/另一臂的产物顶数），
断言的针完全同一套（版本←moon.mod、资产名、`fist (PATH)`、`POSIX shim, LF`、沙箱产物、PATH 逐字还原）。

红了分两栏报（R12 的规矩：**传输层错误与确定性结论绝不混为一谈**）：
  · 主档因**链路侧**红 → 打「链路侧」告警，并把**同一时刻同一 URL 的 curl.exe 对照回执**贴在旁边；
    这条不拦退出码（BUG-116 的成因不在本仓代码，拦了就是把环境当产品杀），但**绝不因为兜底档绿了就不印**；
  · 主档因**确定性**红（404 / HTML 而不是 zip / 缺针 / 产物不在）→ 照旧拦退出码；
  · 兜底档红 → **一律拦退出码**（BUG-116 的新门：兜底线是"这台机器上装得上"的唯一用户面出路，
    它坏了就是用户照文档抄装不上，没有第二条例外）；判为链路侧时也会打印归类，但退出码照红。
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
BOX_FB = os.path.join(ROOT, "temp", "irm-sandbox-fallback")
REAL_DEST = os.path.expandvars(r"%LOCALAPPDATA%\FIST-Mbt")
README = os.path.join(ROOT, "README.md")


def mod_version():
    """版本基线只从 moon.mod 反解：写死字面量的判据一升版就漂（漂成假红还算好的，漂成假绿最坏）。"""
    m = re.search(r'^version\s*=\s*"([^"]+)"', io.open(
        os.path.join(ROOT, "moon.mod"), encoding="utf-8").read(), re.M)
    if not m:
        raise SystemExit("FATAL moon.mod 反解不到 version ⇒ 判据没有基线，绝不报绿")
    return m.group(1)


VER = mod_version()
ASSET = "fist-mbt-js-v%s.zip" % VER
LINE_RE = re.compile(r'^\s*iex \(\(irm (\S+?)\)\.ToString\(\)\.TrimStart\(\[char\]0xFEFF\)\)\s*$|^'
                     r'\s*irm (\S+?) \| iex\s*$', re.M)
# 兜底线的形状（BUG-116）：curl.exe 把脚本取回磁盘 → powershell -File 跑**那一份**。
# 捕获组 = (curl 旗位原文, URL, -o 落点, -File 实跑路径)。反解不到 ⇒ 兜底档直接红（判据看不见被检面，绝不报绿）。
# 旗位**整段逐字带进被执行的命令**：这条判据的立身之本就是"文档写什么字节、判据就跑什么字节"，
# 重组时丢掉 `--retry …` 就等于测了一条用户根本没在跑的更弱的线（run8 实测丢过，见 documented_fallback）。
# 刻意不接受的写法：`curl … | iex`（BUG-113 的 BOM 只在那条路上咬人）、落点≠实跑路径（文档教 A 装 B）、
# 短旗少掉 `-f`（404 页会被当脚本存盘再交给 powershell，R6「200 不等于拿到文件」的用户面翻版）。
FALLBACK_RE = re.compile(
    r'^\s*curl\.exe\s+((?:(?:--retry\s+\d+|--retry-delay\s+\d+|--retry-all-errors)\s+)*-\S+)'
    r'\s+(\S+)\s+-o\s+(\S+)\s*;\s*powershell\s+-NoProfile\s+-ExecutionPolicy\s+Bypass\s+-File\s+(\S+)\s*$',
    re.M)
FALLBACK_SHORT = "-fsSL"                     # 必须逐字出现的短旗团
FALLBACK_RETRY_VALUE = ("--retry", "--retry-delay")   # 带数值的重试旗
FALLBACK_RETRY_FLAG = "--retry-all-errors"            # 不带数值（curl≥7.71：连接后错误也重试）
# 红了归哪一类（R12：两类绝不混报）。判据只看输出里**已经打出来的**诊断字面量——
# 安装器自己就把"没有 HTTP 响应的传输层失败"标成 `n/a(传输层)`、把确定性结论标成 `HTTP 404` 等。
TRANSPORT_MARKS = ("基础连接已经关闭", "发送时发生错误", "接收时发生错误", "无法连接到远程服务器", "操作超时",
                   "n/a(传输层)", "Recv failure", "Connection was reset", "Could not resolve host",
                   "Failed to connect", "Unable to connect",
                   "curl: (7)", "curl: (28)", "curl: (35)", "curl: (56)")
# 只算**源级**确定性结论（拿到了响应、或产物/文档面自己承认坏了）。
DETERMINISTIC_MARKS = ("HTTP 404", "该源给的不是 zip", "不是 zip", "InvalidLeftHandSide", "赋值表达式",
                       "shim 未全部写出", "zip 里没找到 fist-mbt.js", "产物跑不出版本",
                       "POSIX shim 头不对", "curl: (22)", "CommandNotFoundException")
# 这三条是**各源逐条失败之后**的收尾汇总/镜像已知形状，不是病因：
# 把它们当确定性证据，就等于把 BUG-116 的"链路抖一下"归因成"产品坏了"（R12 的反向误判）。
# 只有在GitHub 一侧什么都没打出来时才拿来兜底归类。
CONSEQUENCE_MARKS = ("无法从 moon.mod 解析版本号", "下载全部失败", "返回 HTML 页")
# 权威面 = GitHub 那一侧（R6 写明 GitCode 匿名 raw 回 HTML、release 直链回 403，那是**已知的镜像形状**；
# 拿镜像的 403 给 GitHub 侧的失效归因，就会把环境读成产品——run4 正是这样红错对象的）。
GH_URL = re.compile(r'(?:raw\.githubusercontent\.com|github\.com)/vicTop-cw/FIST-Mbt', re.I)
URL_IN_LINE = re.compile(r'https?://\S+')
HTTP_STATUS_IN_LINE = re.compile(r'HTTP\s+(\d{3})')


def github_side_text(out):
    """只留下**属于 GitHub 那一侧**的输出行。归属跟着安装器的打印形状走：
    `尝试: <url>` 设定当前源，其后不带 URL 的失败行沿用该源；带 URL 的行按本行 URL 归
    （moon.mod 那一格 `· 取不到 <url> ：<错>` 就是这种）。GitCode 段整体剔掉。"""
    cur, kept = None, []
    for ln in (out or "").split("\n"):
        m = URL_IN_LINE.search(ln)
        if m:
            if GH_URL.search(m.group(0)):
                cur, _ = "gh", kept.append(ln)
            else:
                cur = "mirror"
            continue
        if cur == "gh":
            kept.append(ln)
    return "\n".join(kept)


def classify(out, fails):
    """把一档的红归到「链路侧」或「确定性」两栏之一（R12：两者不许混报，处方完全不同）。

    三条承重顺序：
      ① **先按源归段**——只有 GitHub 那一侧的结论才是产品结论（镜像的 403/HTML 是 R6 记下的已知形状）；
      ② 再认输出里已经打出来的诊断字面量，**传输层排在"缺针"之前**——取脚本那一步一红，安装器
         根本没跑，四格针必然全未命中，那是**后果**不是病因（把缺针排在前面就会把 BUG-116 读成产品红）；
      ③ 两头都认不出来时仍按确定性处理（保守）：宁可错杀环境，绝不放过产品。"""
    gh = github_side_text(out)
    status = HTTP_STATUS_IN_LINE.findall(gh)          # GitHub 侧拿到响应（4xx/5xx）= 确定性结论
    det = [k for k in DETERMINISTIC_MARKS if k in gh]
    if status or det:
        return "deterministic", (["GitHub 侧 HTTP %s" % s for s in status] + det)
    tr = [k for k in TRANSPORT_MARKS if k in gh]
    if tr:
        tail = [k for k in CONSEQUENCE_MARKS if k in (out or "")]
        return "transport", tr + (["（安装器收尾汇总，属后果不是病因：%s）" % "、".join(tail)] if tail else [])
    # GitHub 一侧什么都没打出来 ⇒ 退回全文启发（红发生在装之前：文档线解析层、curl 自己报错等）
    det2 = [k for k in DETERMINISTIC_MARKS if k in (out or "")]
    if det2:
        return "deterministic", det2
    tr2 = [k for k in TRANSPORT_MARKS if k in (out or "")]
    if tr2:
        return "transport", tr2
    prod = [f for f in fails if any(k in f for k in ("回执缺", "沙箱里没有", "version 不是", "doctor 非 0",
                                                     "PATH 还原", "真安装目录", "反解不到", "落点与实跑",
                                                     "不同源"))]
    if prod:
        return "deterministic", ["输出无可识别诊断、判据针未命中：%s" % prod[0][:90]]
    return "deterministic", ["红因无法归类 ⇒ 按确定性处理（判据不认「不知道」当绿灯）"]



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


def documented_fallback(primary_url):
    """从 README 反解**兜底** Windows 安装线，返回 (可执行命令, URL, 问题清单, -o 落点)。
    与主线同一套机制：命令不硬编码，被检的就是文档那一串字节——**旗位整段照抄**，
    重组时丢掉 `--retry …` 会测出一条用户根本没在跑的更弱的线。反解不到 ⇒ 问题清单非空（兜底档红）。"""
    m = FALLBACK_RE.search(io.open(README, encoding="utf-8").read())
    if not m:
        return None, None, ["README 里反解不到兜底 Windows 安装线（形状须为 "
                            "`curl.exe [<重试旗>] -fsSL <url> -o <路径>; "
                            "powershell -NoProfile -ExecutionPolicy Bypass -File <路径>`）"
                            "⇒ 判据看不见被检面，绝不报绿"], None
    flags, url, dst, run = m.group(1), m.group(2), m.group(3), m.group(4)
    problems = []
    if dst != run:
        problems.append("兜底线取到 %s 却跑 %s：落点与实跑路径必须逐字相同（否则文档教装 A、实际跑 B）" % (dst, run))
    if url != primary_url:
        problems.append("兜底线的脚本源 %s 与主线 %s 不同源 ⇒ 两臂不再是「同一份字节、只换传输工具」的对照"
                        % (url, primary_url))
    # 旗位属性检查（R12 搬到取脚本这一发）：短旗必须是 -fsSL，且必须带**有上限**的传输层重试 + 间隔。
    if FALLBACK_SHORT not in flags.split():
        problems.append("兜底线的 curl 短旗不是 -fsSL（实得 %r）：少了 -f 就是把 404 页当脚本存盘再交给 powershell"
                        % flags)
    nval = [int(v) for k, v in re.findall(r'(--retry(?:-delay)?)\s+(\d+)', flags)]
    if len(nval) < 2 or not (3 <= nval[0] <= 10) or not (1 <= nval[-1] <= 30):
        problems.append("兜底线没有「有上限的传输层重试 + 间隔」（实得旗位 %r）：本机 2026-09-29 实测同一 URL "
                        "有的连接被 RST、有的拿 200，单发不成立；但 --retry 也无上限——R12 说确定性错误"
                        "（404/给的不是 zip）一判就换源或换线，不许拿无上限重试拖用户" % flags)
    # 把判据自己**真实执行过**的那串字节交给调用方打印（sandbox() 在档头回显），避免"测的比文档强/弱"。
    cmd = "curl.exe %s %s -o %s; powershell -NoProfile -ExecutionPolicy Bypass -File %s" % (flags, url, dst, run)
    return cmd, url, problems, dst



def curl_control(url, box, env):
    """主档判为链路侧红时，**同一时刻**用 curl.exe 取同一条 URL 做对照（BUG-116 的分栏证据）。
    只落一个 .bin 到沙箱，不装任何东西、不碰真产物。"""
    dst = os.path.join(box, "curl-control.bin")
    try:
        r = subprocess.run(["curl.exe", "-sSL", "-m", "60",
                            "-w", "HTTP=%{http_code} bytes=%{size_download}", "-o", dst, url],
                           capture_output=True, text=True, encoding="utf-8", errors="replace",
                           env=env, cwd=box, timeout=150)
        head = ""
        if os.path.isfile(dst):
            head = " 首字节=%s" % io.open(dst, "rb").read(4).hex().upper()
        bits = [s for s in (("exit=%s" % r.returncode),
                            (r.stdout or "").strip(),
                            (r.stderr or "").strip()) if s]
        return "curl.exe 对照（同一时刻、同一 URL）｜ %s%s ｜ 落点=%s" % (
            " ｜ ".join(bits), head, dst)
    except Exception as e:
        return "curl.exe 对照没跑成：%r" % (e,)



def ps_path():
    return subprocess.run(["powershell", "-NoProfile", "-Command",
                           "[Environment]::GetEnvironmentVariable('PATH','User')"],
                          capture_output=True, text=True, encoding="utf-8", errors="replace").stdout.strip()


def set_path(val):
    subprocess.run(["powershell", "-NoProfile", "-Command",
                    "[Environment]::SetEnvironmentVariable('PATH', '%s', 'User')" % val.replace("'", "")],
                   capture_output=True, text=True, encoding="utf-8", errors="replace")


def _dec(raw):
    """PS 5.1 在重定向的管道上按 **OEM 码页**（本机 936）写它自己的报错，而安装器写的是 UTF-8 中文
    ⇒ 整块按 utf-8 解会得到一串替换字符，红因（「基础连接已经关闭」这类）读不出来＝回执不可复核，
    归类也就看不见 TRANSPORT 字面量。逐行试 utf-8，不行再试 gb18030（936 的超集），两条都不通才 replace。"""
    out = []
    for ln in (raw or b"").split(b"\n"):
        for enc in ("utf-8", "gb18030"):
            try:
                out.append(ln.decode(enc))
                break
            except UnicodeDecodeError:
                continue
        else:
            out.append(ln.decode("utf-8", "replace"))
    return "\n".join(out)


def run_line(cmd_line, env, box, tag):
    """跑文档线，回执**落两份**：沙箱里那份会被下一轮清场抹掉（BUG-117 要的就是清场），
    所以再往 `temp/e2e-irm-receipts/<UTC 时刻>-<档名>.log` 存一份**不覆写**的——
    引用过一次的证据如果会被下一次跑原地顶掉，那条引用就没法复核（本仓在这格上栽过）。"""
    r = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", cmd_line],
                       capture_output=True, env=env, cwd=box, timeout=900)
    out = _dec((r.stdout or b"") + (r.stderr or b""))
    body = "rc=%s\n$ powershell -Command \"%s\"\n=== stdout+stderr ===\n%s" % (r.returncode, cmd_line, out)
    io.open(os.path.join(box, "%s.log" % tag), "w", encoding="utf-8", newline="\n").write(body)
    arc = os.path.join(ROOT, "temp", "e2e-irm-receipts")
    os.makedirs(arc, exist_ok=True)
    path = os.path.join(arc, "%s-%s.log" % (time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()), tag))
    io.open(path, "w", encoding="utf-8", newline="\n").write(body)
    print("   不覆写的归档回执：%s" % os.path.relpath(path, ROOT))
    return r.returncode, out, path


def probe(env, box, label, sbin=None):
    """默认走 PATH；沙箱档必须**点名沙箱那一份**——否则沙箱里没装成时会摸到真用户面的旧产物，
    把"根本没装上"读成"装成了旧版本"（BUG-117 的第二个形态）。"""
    exe = os.path.join(sbin, "fist").replace("\\", "/") if sbin else "fist"
    script = ("if [ -x '%s' ]; then echo '%s'; '%s' version 2>/dev/null; "
              "'%s' doctor >/dev/null 2>&1; echo doctor=$?; else echo 'MISSING %s'; fi") % (exe, exe, exe, exe, exe)
    r = subprocess.run(["bash", "-c", script],
                       capture_output=True, text=True, encoding="utf-8", errors="replace",
                       cwd=box, env=env, timeout=300)
    txt = (r.stdout or "").replace("\r", "").strip()
    # 不打[:170]：一张被截断的回执没法复核（本仓在别处被 [:260] 咬过一次），探针就三行，全量照打。
    print("  %-14s %s" % (label, " | ".join(txt.split("\n"))))
    return txt


def arm(tag, title, line, box, bare=False):
    """一档 = 一次**独立清场**的沙箱安装 + 同一套针 + 点名探针 + HKCU PATH 逐字还原。

    沙箱每次先清空：上一次留下的安装会让文档线（不带 -Force）直接 exit 1，于是判据红的是
    "沙箱脏了"而不是"文档线坏了"——假红比不跑更糟（BUG-117）。两臂各占一棵沙箱，互不顶数。
    返回 (fails, cls, marks, env, sbin, rc)。"""
    print("\n########## %s ##########" % title)
    print("被检面（README 反解）：%s" % line)
    if os.path.isdir(box):
        shutil.rmtree(box, ignore_errors=True)
        print("沙箱已重置（清 %s）" % os.path.relpath(box, ROOT))
    os.makedirs(box, exist_ok=True)
    env = dict(os.environ)
    env["LOCALAPPDATA"] = os.path.join(box, "AppData", "Local")
    env["USERPROFILE"] = os.path.join(box, "User")
    env["TEMP"] = env["TMP"] = os.path.join(box, "Temp")
    sbin = os.path.join(env["USERPROFILE"], ".local", "bin")
    env["PATH"] = sbin + os.pathsep + env.get("PATH", "")
    for d in (env["LOCALAPPDATA"], env["USERPROFILE"], env["TEMP"], sbin):
        os.makedirs(d, exist_ok=True)
    real_before = sha8(os.path.join(REAL_DEST, "fist-mbt.js"))
    path_before = ps_path()
    print("基线：真产物 sha256:%s / 用户 PATH %d 字" % (real_before, len(path_before)))
    fails, rc, out = [], 1, ""
    try:
        rc, out, _rcpt = run_line(line, env, box, tag)
        print("=== %s rc=%d（全文回执落 %s，终端只回显判据相关行且**不截断**）==="
              % (tag, rc, os.path.relpath(os.path.join(box, "%s.log" % tag), ROOT)))
        for ln in out.split("\n"):
            if any(k in ln for k in ("v" + VER, "fist-mbt-js-v", "fist (PATH)", "POSIX shim",
                                     "InvalidLeftHandSide", "赋值表达式", "404", "PK", "❌", "⚠️")):
                print("   " + ln.strip())
        if bare:
            # 旧裸形必须红，且必须能看见"是 iex 解析层红"而不是网络红 ⇒ BUG-113 的复现格
            if rc == 0:
                fails.append("裸 `irm | iex` 竟然成功 ⇒ BUG-113 的成因假设不成立（要重查）")
            if "InvalidLeftHandSide" not in out and "赋值表达式" not in out:
                fails.append("裸形红了但没打出 param() 解析错 ⇒ 红因不是 BOM，归因要重做")
        else:
            if rc != 0:
                fails.append("文档线 rc=%d（应 0）" % rc)
            for needle, why in ((VER, "版本从 moon.mod 反解"),
                                (ASSET, "资产名与发布产物同源"),
                                ("fist (PATH)", "自检经 shim 出回执（BUG-109）"),
                                ("POSIX shim, LF", "无扩展名 shim 门（BUG-105）")):
                print("  %-26s %s（%s）" % (needle, "命中" if needle in out else "未命中", why))
                if needle not in out:
                    fails.append("回执缺 %r（%s）" % (needle, why))
            js = os.path.join(env["LOCALAPPDATA"], "FIST-Mbt", "fist-mbt.js")
            print("  沙箱产物 = %s；bin = %s" % (sha8(js), sorted(os.listdir(sbin))))
            if not os.path.isfile(js):
                fails.append("沙箱里没有产物")
            txt = probe(env, box, "沙箱 bash", sbin)
            if txt.startswith("MISSING"):
                fails.append("沙箱里没有可执行的 fist（探针点名要跑 %s）⇒ 不许摸真用户面的旧产物顶数" % sbin)
            if ("v" + VER) not in txt:
                fails.append("沙箱里 fist version 不是 %s：探针回执=%r" % (VER, txt))
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
    cls, marks = ("clean", []) if not fails else classify(out, fails)
    verdict = "PASS" if not fails else ("FAIL·链路侧" if cls == "transport" else "FAIL·确定性")
    print("=== %s：%s%s ===" % (tag, verdict,
                                "" if not marks else "（归因：%s）" % "；".join(str(m) for m in marks)))
    for f in fails:
        print("  FAIL " + f)
    return fails, cls, marks, env, sbin, rc


def sandbox():
    """两臂并列：主档（irm / .NET 栈）+ 兜底档（curl.exe / Schannel 栈）。
    两档各跑一次、各报各的，**兜底档红一律拦退出码**（BUG-116 的新门），
    主档只有在**判为确定性**红时才拦退出码；链路侧红照印不误并贴 curl 对照。"""
    line, url, bare = documented_line()
    fb_line, fb_url, fb_problems, fb_dst = documented_fallback(url)
    p_fails, p_cls, p_marks, p_env, p_sbin, p_rc = arm(
        "irm", "主档（README 首选线：irm / .NET 栈）", line, BOX, bare)

    print("\n########## 兜底档（README 兜底线：curl.exe 落盘 + powershell -File）##########")
    if fb_problems:
        # 文档面坏了 ⇒ 这一档连被检样本都没有，直接红（不静默跳过，跳过的判据等于没有判据）
        f_fails, f_cls, f_marks, f_env, f_sbin, f_rc = list(fb_problems), "deterministic", [], None, None, None
        for f in f_fails:
            print("  FAIL " + f)
    else:
        f_fails, f_cls, f_marks, f_env, f_sbin, f_rc = arm(
            "irm-fallback", "兜底档（curl.exe / Schannel 栈）", fb_line, BOX_FB)
        # 兜底档的**取回件**回执：点名沙箱里那一份（BUG-117 的教训——回执与探针都不许回落 PATH）。
        rel = fb_dst
        if rel.lower().startswith("$env:temp"):
            rel = os.path.join(BOX_FB, "Temp", os.path.basename(rel.replace("\\", "/")))
        elif not os.path.isabs(rel):
            rel = os.path.join(BOX_FB, rel.replace("\\", os.sep))
        if os.path.isfile(rel):
            body = io.open(rel, "rb").read()
            print("  取回的脚本（沙箱点名）= %s\n    字节=%d 首4字节=%s sha256:%s"
                  % (rel, len(body), body[:4].hex().upper(), hashlib.sha256(body).hexdigest()[:8]))
            if body[:3] == b"\xef\xbb\xbf":
                print("    BOM 仍在（EF BB BF）而 -File 照跑通 ⇒ BUG-113 那一格由 -File 承担，"
                      "兜底线没退回 `iex` 那条路")
        elif not f_fails:
            f_fails, f_cls, f_marks = ["兜底线的 -o 落点不存在：%s（跑通了却没取回件=回执不可复核）" % rel], \
                "deterministic", []
            print("  FAIL " + f_fails[0])

    print("\n########## 两档分栏判定（R12：链路侧与确定性绝不混报）##########")
    print("主档   （irm / .NET）      ：%s %s" % (
        "PASS" if not p_fails else ("FAIL·链路侧" if p_cls == "transport" else "FAIL·确定性"),
        "；".join(str(m) for m in p_marks)))
    print("兜底档 （curl.exe / Schannel）：%s %s" % (
        "PASS" if not f_fails else ("FAIL·链路侧" if f_cls == "transport" else "FAIL·确定性"),
        "；".join(str(m) for m in f_marks)))
    exit_code = 0
    if f_fails:
        exit_code = 1
        print("❌ 兜底档红 ⇒ 拦退出码（BUG-116 的新门：这是这台机器上唯一被文档承诺能装上的那条线，"
              "它坏了就是「照文档抄装不上」）%s" % ("——本档判为链路侧，仍按红处理" if f_cls == "transport" else ""))
    if p_fails:
        if p_cls == "transport":
            print("⚠️ 主档红 = **链路侧**（不是产品红）：不拦退出码，但**绝不因为兜底档绿了就不印**"
                  "——BUG-116 的实测形状正是这一格")
            for f in p_fails:
                print("   主档 FAIL " + f)
            print("   " + curl_control(url, BOX, p_env))
        else:
            exit_code = 1
            print("❌ 主档红 = **确定性**（404 / HTML 而不是 zip / 缺针 / 产物不在）——这一类必须拦退出码")
    io.open(os.path.join(ROOT, "temp", "e2e-irm-last.txt"), "w", encoding="utf-8", newline="\n").write(
        "主档 line=%s\n主档判定=%s %s\n兜底档 line=%s\n兜底档判定=%s %s\n退出码=%s\n" % (
            line, "PASS" if not p_fails else "FAIL", "；".join(p_fails) or "四格命中",
            fb_line or "(反解失败)", "PASS" if not f_fails else "FAIL",
            "；".join(f_fails) or "四格命中", exit_code))
    return exit_code


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
    rc, out, _rcpt = run_line(line, env, ROOT, "irm-real")
    print("=== 真用户面 rc=%d ===" % rc)
    for ln in out.split("\n"):
        if any(k in ln for k in ("v" + VER, "fist (PATH)", "POSIX shim", "❌", "404")):
            print("   " + ln.strip()[:112])
    after = sha8(js)
    print("   真产物：%s → %s" % (before, after))
    txt = probe(env, ROOT, "真面 bash")
    ok = rc == 0 and ("v" + VER) in txt and "doctor=0" in txt
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
