#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/_single_exit_gate.py — 「唯一出口合规」自检尺（P21 工作项五 / T0r141）。

**判什么**（计划真源 `fist-mbt/plan/active/2026-11-25-global-net-exit.md` §五）：

> 自检脚本枚举当前所有隧道/映射，断言映射集合 == {fist-auto}；断言 api-key 鉴权生效；
> 断言其余 8 个服务端口在公网侧不可达。

**观测面（三条路交叉，任一单独可用时都可能假绿 ⇒ 必须合起来）**：

| 面 | 读法 | 为什么不能只信它 |
|---|---|---|
| A 台账 | `.fist-mbt/data/tunnels.json` | `global_tunnel down` 会清空台账，而隧道进程**不会被它停掉** ⇒ 台账为空 ≠ 无映射 |
| B 凭据残留 | `.fist-mbt/data/tunnel-logs/creds-<port>.json` | 2026-11-25 实测：该目录仍留 6 份旧凭据，而 `tunnels.json` 已不存在 |
| C 活进程命令行 | `powershell Get-CimInstance Win32_Process -Filter "Name='cloudflared.exe'"` | **唯一能看见「此刻真有公网映射」的面**；Windows 上 wmic 不可用（实测），故用 PowerShell |

三者并集 = 「观测到的映射端口」。断言 = 并集 == 白名单。

**退出码契约（本仓判据族同口径）**：
  0 = 合规（映射集合 ⊆ 白名单 且 api-key 鉴权生效 且 白名单端口自身可出数）
  1 = **不合规**（发现白名单外的对外映射；或 api-key 未强制鉴权）
  2 = 判据无法自证（扫描面为空 / cloudflared 不可见 / 读取异常）——绝不冒用 0 或 1

**只读**：全程不 kill 进程、不改台账、不发对外请求（只打本机端点）。

**参数面**：只有 `--selftest` / `--timeout` / `--probe-port` / `--json`。
argparse 默认 `allow_abbrev=True`（实测会把 `--selftes` 当 `--selftest` 静默走自检分支，
T0r117）⇒ 显式关掉。未知旗标一律 rc=2。

用法：
  python scripts/_single_exit_gate.py             # 真跑（本机；rc 见上）
  python scripts/_single_exit_gate.py --selftest  # 纯函数 + 合成违例自检
  python scripts/_single_exit_gate.py --json      # 机器可读（不影响 rc 契约）
"""

import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(ROOT, ".fist-mbt", "data")
TUNNELS_JSON = os.path.join(DATA_DIR, "tunnels.json")
CREDS_GLOB = os.path.join(DATA_DIR, "tunnel-logs", "creds-*.json")
CREDTEST_GLOB = os.path.join(os.environ.get("TEMP", "/tmp"), "credtest.json")

CLOUDFLARED = shutil.which("cloudflared") or ""
CLOUDFLARED_EXE = "cloudflared.exe"

# ── 白名单：计划一（出口架构定案）尚未定案 ⇒ 现读**两条权威自述**取交集口径：
#   ① T0r124 设计报告 §1.3 的结论「A1 的 18651 撞车 ⇒ fist-auto 端口取 18654」
#   ② docs/2026-11-25-fist-auto-public-access.md 全文以 fist-auto 为唯一对外端点名
# 因此「合法映射端口」== {18654}。⚠️ 这是**从文档反解**的期望值，不是从计划正文抄的：
# 计划正文只说「只允许包含 fist-auto 端口」，而 fist-auto 的端口在计划一落地前有过一次漂移
# （18651→18654）。本文件把该期望写成常量并在 --selftest 里锁住其来源，
# 计划一定案后只需改这一处 + 同批更新 README 条目。
ALLOWED_PUBLIC_PORTS = (18654,)
REQUIRED_SOURCES = ("tunnels.json", "creds", "process")
# 日志 mtime 超过这个小时数就不算「近期注册证据」：旧空转日志不该长期决定合规结论。
MAX_LOG_AGE_HOURS = 6.0

SERVICE_PORTS_DEFAULT = (18640, 18641, 18643, 18644, 18645, 18646, 18649)
PROBE_PORTS_DEFAULT = tuple(sorted(set(SERVICE_PORTS_DEFAULT) - set(ALLOWED_PUBLIC_PORTS)))

PS_CMDLET = (
    "Get-CimInstance Win32_Process -Filter \"Name='%s'\" "
    "| ForEach-Object { $_.ProcessId.ToString() + '|' + $_.CommandLine }" % CLOUDFLARED_EXE
)


class JudgeFault(Exception):
    """判据自身坏了（不给 0 也不给 1）。"""


_PORT_RE = re.compile(r":(\d{2,5})(?=[/?#\s]|$)")


def parse_port(text):
    """从「URL / 命令行文本」里抽**服务端口**：取所有 `:PORT` 候选的最后一个。

    取最后一个的理由（实测）：进程命令行形如
    `--url http://127.0.0.1:18640 --protocol http2 00000000-…-000000000000`
    ⇒ `:18640` 之后只有 UUID；`https://host:443/path` 这类只命中一个。
    取最后一个 = 总是拿 `--url` 的目标端口。抽不到返回 None。
    """
    if not text:
        return None
    cands = _PORT_RE.findall(str(text))
    return int(cands[-1]) if cands else None


def parse_port_first(text):
    """变异对照用：取**第一个**候选端口的错实现（会被 URL 之外的冒号骗到）。"""
    if not text:
        return None
    cands = _PORT_RE.findall(str(text))
    return int(cands[0]) if cands else None


def classify_cred_tid(tid):
    """凭据的 TunnelID -> 'real' / 'all-zero-test'。

    实测两种形态都在现场：`00000000-...-000000000000` 是**凭据测试产物**
    （配合 `%TEMP%\\credtest.json`，T0r128 一档留的验证残件），不是 CF 侧真隧道；
    真 ID 形如 `ef299452-09e5-406b-9715-2d1776222b18`。
    判成 all-zero 只影响**报告措辞**，不影响合规结论（映射本身已在进程面现形）。
    """
    t = (tid or "").strip()
    if not t:
        return "unknown"
    if set(t.replace("-", "")) <= {"0"}:
        return "all-zero-test"
    return "real"


def read_tunnels_json(path=TUNNELS_JSON):
    """台账面。返回 dict（可能空）；文件不存在/坏 JSON 返回 {}。"""
    try:
        with open(path, encoding="utf-8") as fh:
            obj = json.load(fh)
        return obj if isinstance(obj, dict) else {}
    except Exception:
        return {}


def _as_int(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


def ports_from_tunnels(state):
    """台账条目 -> [(port, detail)]。容忍 `{"18640": {...}}` 与 `{port: {...}}` 两种键型，
    以及 T0r140 台账新增的 `backend_port` 字段（该字段比 URL 更可靠）。"""
    out = []
    for key, val in (state or {}).items():
        if not isinstance(val, dict):
            continue
        p = (_as_int(key) or _as_int(val.get("backend_port"))
             or parse_port(str(val.get("url", "")))
             or parse_port(str(val.get("origin", ""))))
        if p:
            out.append((p, str(val.get("url") or "")))
    return out


def cred_paths(pattern=CREDS_GLOB, extra_pattern=CREDTEST_GLOB):
    """凭据文件路径 -> (port, path)。与 `creds_ports` 同口径（抓文件名最后一段数字）。"""
    out, seen = [], set()
    for path in sorted(glob.glob(pattern)) + sorted(glob.glob(extra_pattern)):
        nums = re.findall(r"(\d{2,5})", os.path.basename(path))
        if not nums:
            continue
        port = int(nums[-1])
        if port in seen:
            continue
        seen.add(port)
        out.append((port, path))
    return out


def creds_ports(pattern=CREDS_GLOB, extra_pattern=CREDTEST_GLOB):
    """凭据残留面。返回 [(port, detail)]。

    文件名形态：`creds-18640.json`（旧）与 `creds-t0r140-18651.json`（T0r140 的新命名，
    实测在目录里）⇒ 必须抓**最后一个**数字段，否则会读成 140。
    `%TEMP%\\credtest.json` 不含端口数字 ⇒ **不是服务端口证据**，单独标注为测试产物。
    """
    out, seen = [], set()
    for port, path in cred_paths(pattern, extra_pattern):
        tid = ""
        try:
            with open(path, encoding="utf-8") as fh:
                tid = (json.load(fh) or {}).get("TunnelID", "")
        except Exception:
            pass
        kind = classify_cred_tid(tid)
        out.append((port, "tid_kind=%s src=%s" % (kind,
                                                  "temp-test" if "credtest" in path else "data")))
    for path in sorted(glob.glob(extra_pattern)):
        if "credtest" in os.path.basename(path).lower():
            out.append((None, "tid_kind=test-artifact src=temp-test（非服务端口）"))
    return out


LOGS_GLOB = os.path.join(DATA_DIR, "tunnel-logs", "tunnel-*.log")
REGISTERED_RE = re.compile(r"(?i)registered tunnel connection")
ZERO_TID = set("0")


def registered_ports(pattern=LOGS_GLOB):
    """**注册证据面**：哪些端口真的把隧道注册到了 CF 边缘。

    为什么必须有这一面（实测依据）：进程命令行里有 `--protocol http2`，本机 cloudflared
    对它的历史表现是打印 help 后退出 —— 「进程活着」不等于「隧道通了」。日志里出现
    `Registered tunnel connection` 才是边缘真的接受了这条映射（L4 实测读数）。

    返回 (registered:set[int], mentions:set[int])：
      registered = 该端口的日志**近期**出现过注册串；
      mentions   = 日志文件存在（含历史上失败过的空转日志 ⇒ 只作参考，不构成违规证据）。
    日志 mtime 超过 `max_age_hours` 视为陈旧、不计入 registered（否则旧日志会长期留绿/留红）。
    """
    registered, mentions = set(), set()
    now = _now_ts()
    for path in sorted(glob.glob(pattern)):
        nums = re.findall(r"(\d{2,5})", os.path.basename(path))
        if not nums:
            continue
        port = int(nums[-1])
        mentions.add(port)
        try:
            age_h = (now - os.path.getmtime(path)) / 3600.0
            if age_h > MAX_LOG_AGE_HOURS:
                continue
            with open(path, encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except OSError:
            continue
        if REGISTERED_RE.search(text):
            registered.add(port)
    return registered, mentions


def _now_ts():
    import time
    return time.time()


def process_mappings(timeout=10.0):
    """活进程面：cloudflared 进程命令行 -> [(port, detail)]。

    Windows 用 PowerShell（wmic 实测不存在）；非 Windows 回退 ps。
    返回 [] 且 `cloudflared` 不在 PATH ⇒ 调用方判「面不可用」（不静默放行）。
    """
    if not CLOUDFLARED and sys.platform != "win32":
        return []
    if sys.platform == "win32":
        cmd = ["powershell", "-NoProfile", "-NonInteractive", "-Command", PS_CMDLET]
    else:
        cmd = ["ps", "-eo", "pid=,command="]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True,
                              timeout=timeout, encoding="utf-8", errors="replace")
    except FileNotFoundError:
        return []
    except (subprocess.TimeoutExpired, OSError):
        raise JudgeFault("进程枚举失败：%s" % " ".join(cmd[:2]))
    rows = []
    for line in (proc.stdout or "").splitlines():
        line = line.strip()
        if CLOUDFLARED_EXE.lower() not in line.lower():
            continue
        pid = None
        if "|" in line:
            pid = line.partition("|")[0].strip() or None
        port = parse_port(line)
        tid = ""
        m = re.search(r"\b([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\b",
                      line, re.I)
        if m:
            tid = m.group(1)
        rows.append((port, "pid=%s tid=%s" % (pid, tid or "(n/a)")))
    return rows


def union_mapping_ports(sources):
    """三面并集。sources: {面名: [(port, detail), ...]}（**统一为二元组**，避免按行号取字段
    而漏读——本文件首版把进程面写成四元组、另两面二元组，实测真跑时并集读到空集）。
    返回 (ports:set[int], 各面计数 dict, 细节 list)。"""
    ports, detail, counts = set(), [], {}
    for name in REQUIRED_SOURCES:
        rows = sources.get(name, [])
        counts[name] = len(rows)
        seen = set()
        for row in rows:
            p = row[0] if row else None
            if isinstance(p, int) and p not in seen:
                seen.add(p)
                ports.add(p)
                detail.append("%s:%d(%s)" % (name, p, row[1] if len(row) > 1 else ""))
        if seen:
            counts[name + ":ports"] = len(seen)
    return ports, counts, detail


def evaluate(mapping_ports, allowed=ALLOWED_PUBLIC_PORTS):
    """核心断言（纯函数，`--selftest` 直接钉它）。返回 (verdict, offenders)。"""
    allowed_set = set(allowed)
    offenders = sorted(set(mapping_ports) - allowed_set)
    verdict = "compliant" if not offenders else "violation"
    return verdict, offenders


def describe_auth_state(code):
    """端点匿名响应 -> 档位（与 check_ofm_endpoint.classify_status 同口径）。"""
    if code in (200, 201, 204):
        return "accepts-anonymous"
    if code in (401, 403):
        return "rejects-anonymous"
    if code == 404 or 500 <= code < 600:
        return "unexpected"
    return "other"


def probe(url, timeout):
    """GET 一发，返回 (档位, 'HTTP n')。传输层失败归 unreachable。"""
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    try:
        with urllib.request.build_opener().open(req, timeout=timeout) as resp:
            return describe_auth_state(resp.getcode()), "HTTP %s" % resp.getcode()
    except urllib.error.HTTPError as e:
        return describe_auth_state(e.code), "HTTP %s" % e.code
    except (urllib.error.URLError, OSError, TimeoutError) as e:
        return "unreachable", "unreachable: %s" % (e,)
    except Exception as e:  # 判据自身异常不许冒用 0/1
        raise JudgeFault("探针异常：%r" % (e,))


def auth_check(port, timeout):
    """api-key 强制面：`/health` 是免鉴权心跳（§4.1 口径），故探 `/v1/models`。

    档位语义：rejects-anonymous = 鉴权生效（合规）；accepts-anonymous = 未强制（不合规）。
    """
    tier, detail = probe("http://127.0.0.1:%d/v1/models" % port, timeout)
    return tier, detail


def selftest():
    """纯函数 + 合成违例自检。含变异对照（判例-29/30：机制格必须钉实现，不是钉注释）。"""
    checks = []

    # ── 正向：解析
    checks.append(("parse_url_port basic", parse_port("http://127.0.0.1:18640/") == 18640))
    checks.append(("parse_url_port no_slash", parse_port("http://127.0.0.1:18654") == 18654))
    checks.append(("parse_url_port none", parse_port("") is None))
    checks.append(("parse_url_port host_only", parse_port("https://x.trycloudflare.com") is None))

    # ── 凭据分类
    checks.append(("tid real", classify_cred_tid("ef299452-09e5-406b-9715-2d1776222b18") == "real"))
    checks.append(("tid zero", classify_cred_tid("00000000-0000-0000-0000-000000000000")
                   == "all-zero-test"))
    checks.append(("tid empty", classify_cred_tid("") == "unknown"))

    # ── 台账解析（两种键型）
    st = {"18640": {"url": "https://a.trycloudflare.com"}, 18651: {"url": "https://b.trycloudflare.com"}}
    ps = sorted(p for p, _ in ports_from_tunnels(st))
    checks.append(("tunnels_json parse both key types", ps == [18640, 18651]))

    # ── 核心断言
    checks.append(("eval compliant", evaluate({18654}) == ("compliant", [])))
    checks.append(("eval violation 18640", evaluate({18640, 18654})
                   == ("violation", [18640])))
    checks.append(("eval empty_is_compliant", evaluate(set()) == ("compliant", [])))
    checks.append(("eval sorted_offenders", evaluate({18649, 18640})[1] == [18640, 18649]))

    # ── 合成违例：把凭据面造出一个白名单外端口，必须被判违规
    fake_sources = {
        "tunnels.json": [(18654, "https://ok.trycloudflare.com")],
        "creds": [(18640, "tid_kind=real")],
        "process": [(18654, "pid=1 tid=b07cfef1-820d-4051-a995-a006baa1d22a")],
    }
    u_ports, _, _ = union_mapping_ports(fake_sources)
    v, off = evaluate(u_ports)
    checks.append(("synthetic leftover creds must violate", (v, off) == ("violation", [18640])))
    # 反向对照：三面都干净时不许误红
    clean_sources = {
        "tunnels.json": [(18654, "https://ok.trycloudflare.com")],
        "creds": [],
        "process": [(18654, "pid=1 tid=(n/a)")],
    }
    c_ports, _, _ = union_mapping_ports(clean_sources)
    cv, coff = evaluate(c_ports)
    checks.append(("clean synthetic stays compliant", (cv, coff) == ("compliant", [])))

    # ── 变异对照 M1：把 `evaluate` 的「减去白名单」改成「只看是否非空」必须被抓住
    def mutant_evaluate(mapping_ports, allowed=ALLOWED_PUBLIC_PORTS):
        return ("compliant", []) if not mapping_ports else ("violation", sorted(mapping_ports))

    m1_violation = mutant_evaluate({18640, 18654})
    m1_should_be = evaluate({18640, 18654})
    checks.append(("M1 mutation detected (mutant ignores whitelist)",
                   m1_violation != m1_should_be))

    # ── 变异对照 M2：把 `parse_port` 换成「取第一个候选端口」的错实现必须被抓住。
    #    错实现会把命令行 `--url http://127.0.0.1:18640 ...` 里的前导冒号候选读错
    #    （`-NoProfile`/`-Filter` 之类不含冒号时退化为恰好同值，故用带前导端口的
    #    合成串确保两侧必然分叉——否则变异不红就是「锁没在看」）。
    cmdline = "cloudflared.exe tunnel run --url http://127.0.0.1:9999 --protocol http2 " \
              "http://127.0.0.1:18640"
    checks.append(("M2 parse_port first-vs-last divergence",
                   parse_port_first(cmdline) != parse_port(cmdline)))
    checks.append(("parse_port last picks url target", parse_port(cmdline) == 18640))
    checks.append(("parse_port_first picks leading", parse_port_first(cmdline) == 9999))

    # ── 鉴权档位
    checks.append(("auth 401 rejects", describe_auth_state(401) == "rejects-anonymous"))
    checks.append(("auth 403 rejects", describe_auth_state(403) == "rejects-anonymous"))
    checks.append(("auth 200 accepts", describe_auth_state(200) == "accepts-anonymous"))
    checks.append(("auth 404 unexpected", describe_auth_state(404) == "unexpected"))
    checks.append(("auth 500 unexpected", describe_auth_state(500) == "unexpected"))

    # ── 面计数：扫描面为空必须能被识别（自拒不报绿）
    empty_counts = union_mapping_ports({n: [] for n in REQUIRED_SOURCES})[1]
    checks.append(("empty scan face detectable", all(empty_counts[n] == 0 for n in REQUIRED_SOURCES)))

    # ── 凭据命名解析：`creds-t0r140-18651.json` 必须读成 18651（抓最后一段数字）
    with tempfile.TemporaryDirectory() as td:
        for name in ("creds-18640.json", "creds-t0r140-18651.json"):
            p = os.path.join(td, name)
            with open(p, "w", encoding="utf-8") as fh:
                json.dump({"TunnelID": "ef299452-09e5-406b-9715-2d1776222b18"}, fh)
        got = [port for port, _ in creds_ports(pattern=os.path.join(td, "creds-*.json"),
                                               extra_pattern="")]
        checks.append(("creds naming t0r140 suffix", sorted(got) == [18640, 18651]))
        # 临时凭据文件不得被当成服务端口证据
        tp = os.path.join(td, "credtest.json")
        with open(tp, "w", encoding="utf-8") as fh:
            json.dump({"TunnelID": "64e15197-16b8-41e4-8ced-28378a83d015"}, fh)
        trows = creds_ports(pattern=os.path.join(td, "creds-*.json"),
                            extra_pattern=os.path.join(td, "credtest.json"))
        checks.append(("temp credtest not a service port",
                       any(port is None and "src=temp-test" in d for port, d in trows)))
        # None 端口行必须能被格式化（首版 `%d` 在这条路径上 TypeError ⇒ 真跑崩、rc=1 但无结论）
        try:
            "port=%s" % (trows[-1][0] if trows[-1][0] is not None else "-")
            fmt_ok = True
        except TypeError:
            fmt_ok = False
        checks.append(("none-port row formats", fmt_ok))
    # ── 注册证据面：日志出现注册串才算边缘真收（进程面单独不算）
    with tempfile.TemporaryDirectory() as td:
        p = os.path.join(td, "tunnel-18640.log")
        with open(p, "w", encoding="utf-8") as fh:
            fh.write("INF Registered tunnel connection connIndex=0\n")
        reg, men = registered_ports(pattern=os.path.join(td, "tunnel-*.log"))
        checks.append(("registered_ports picks registration", (reg, men) == ({18640}, {18640})))
    with tempfile.TemporaryDirectory() as td:
        # 只有「进程在跑」形状的日志（无注册串）⇒ 不得算已注册
        p = os.path.join(td, "tunnel-18651.log")
        with open(p, "w", encoding="utf-8") as fh:
            fh.write("INF Starting tunnel tunnelID=c7b52290-...\n")
        reg, men = registered_ports(pattern=os.path.join(td, "tunnel-*.log"))
        checks.append(("no-registration log is not registered", reg == set() and men == {18651}))

    bad = [n for n, ok in checks if not ok]
    if bad:
        print("SELFTEST FAIL: %s" % ", ".join(bad))
        return 2
    print("SELFTEST OK: %d checks (2 mutation controls)" % len(checks))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description="unique public egress compliance gate (T0r141)")
    ap.add_argument("--selftest", action="store_true", help="pure-function selftest")
    ap.add_argument("--timeout", type=float, default=6.0, help="per-probe timeout seconds")
    ap.add_argument("--probe-port", type=int, action="append", default=None,
                    help="api-key auth-check port (repeatable); default = first allowed port")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    # allow_abbrev=False：`--selftes` 不被静默当 `--selftest`（T0r117 / R207 族）
    ap.allow_abbrev = False
    args = ap.parse_args(argv)

    if args.selftest:
        return selftest()

    report = {"allowed": list(ALLOWED_PUBLIC_PORTS)}

    # ── 面 A/B/C
    state = read_tunnels_json()
    tunnel_rows = ports_from_tunnels(state)
    cred_rows = creds_ports()
    try:
        proc_rows = process_mappings(timeout=max(args.timeout, 5.0))
    except JudgeFault as e:
        print("JUDGE FAULT: %s" % e)
        return 2

    report["face_counts"] = {"tunnels.json": len(tunnel_rows), "creds": len(cred_rows),
                             "process": len(proc_rows)}
    report["tunnels_json_exists"] = os.path.exists(TUNNELS_JSON)

    if not tunnel_rows and not cred_rows and not proc_rows:
        # 三面全空可能是「真的零映射」，也可能是三个面同时失效 ⇒ 不判绿也不判红。
        print("INCONCLUSIVE: 三个观测面（tunnels.json / creds / 进程）同时为空；"
              "cloudflared=%s —— 拒绝出数，不判红不判绿" % (CLOUDFLARED or "(not on PATH)"))
        return 2

    mapping_ports, counts, detail = union_mapping_ports(
        {"tunnels.json": tunnel_rows, "creds": cred_rows, "process": proc_rows})
    verdict, offenders = evaluate(mapping_ports)
    registered, log_mentions = registered_ports()
    report.update({"mapping_ports": sorted(mapping_ports), "detail": detail,
                   "offenders": offenders, "egress_verdict": verdict,
                   "registered_ports": sorted(registered),
                   "log_only_ports": sorted(log_mentions - set(mapping_ports))})

    lines = []
    lines.append("观测面: tunnels.json=%d creds=%d process=%d 已注册=%d" %
                 (len(tunnel_rows), len(cred_rows), len(proc_rows), len(registered)))
    lines.append("观测到的对外映射端口: %s" % (sorted(mapping_ports) or "(空)"))
    for port, detail_txt in cred_rows:
        lines.append("  creds   port=%s %s" % (port if port is not None else "-", detail_txt))
    for port, detail_txt in proc_rows:
        lines.append("  process port=%s %s" % (port, detail_txt))
    for port in sorted(registered):
        lines.append("  edge    port=%d 日志含 Registered tunnel connection（边缘真收）" % port)
    if log_mentions - set(mapping_ports):
        lines.append("  仅日志出现（无进程/台账）端口: %s"
                     % sorted(log_mentions - set(mapping_ports)))
    lines.append("白名单: %s" % (list(ALLOWED_PUBLIC_PORTS),))
    if offenders:
        lines.append("不合规：发现白名单外的对外映射 -> %s" % offenders)

    # ── api-key 强制面
    probe_ports = args.probe_port or list(ALLOWED_PUBLIC_PORTS)
    auth = {}
    for p in probe_ports:
        try:
            tier, reading = auth_check(p, args.timeout)
        except JudgeFault as e:
            print("JUDGE FAULT: %s" % e)
            return 2
        auth[str(p)] = {"tier": tier, "reading": reading}
        lines.append("api-key @127.0.0.1:%d /v1/models 匿名 -> %s (%s)" % (p, tier, reading))
    report["auth"] = auth
    auth_ok = bool(auth) and all(v["tier"] == "rejects-anonymous" for v in auth.values())

    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print("\n".join(lines))

    if offenders:
        return 1
    if not auth_ok:
        # 白名单端口自身没在跑 / 匿名可进 —— 都是缺陷面，不是「判据坏了」
        print("不合规：api-key 鉴权未生效（档位需全为 rejects-anonymous）")
        return 1
    print("合规：映射集合 ⊆ %s 且 api-key 强制生效" % (list(ALLOWED_PUBLIC_PORTS),))
    return 0


if __name__ == "__main__":
    sys.exit(main())
