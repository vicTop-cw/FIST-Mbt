#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""BUG-538 心跳落盘 · 黑盒 e2e 判据（真 spawn `node cli.js serve` 调用面）。

为什么它是黑盒脚本而不是单元测试：
  - 单元测试 i4（server_log_js 侧）用 30ms 假间隔直调 FFI，结构上照不到
    「run_server 接线读了 env、装了 setInterval、真进程活着时行真的落盘」这条链；
  - 缺陷本体若在接线（env 名拼错 / off 门写反 / pid 取错进程），假间隔夹具照样全绿。

被测事实（从源码反解，不在本文件抄第二份常量）：
  - 接线：src/server/server.mbt run_server 内 `server_log_path()` 读 `FIST_SERVER_LOG`
    （=off 关闭；未设则 `<FIST_DB_PATH 所在目录>/server.log`），非空即装
    崩溃钩子 + `server_log_heartbeat_start(slog_path)`；
  - 间隔：`SERVER_LOG_HEARTBEAT_MS = 60_000` **写死常量、无 env 可调**
    （源码明注「没有 FIST_HEARTBEAT_MS env」——过度设计防线）⇒ 本判据老实等：
    首拍上限 100s，正常应在 ~60s 出现；
  - 行形状：`server_log_line()` ⇒ `<ISO:YYYY-MM-DDTHH:MM:SSZ> [fist-mbt] heartbeat alive pid=<pid>`
    （pid = node 真实 OS-PID，`globalThis.process.pid`）。

隔离（BUG-122/90 仓规）：
  - `FIST_DB_PATH` 指沙箱库，绝不碰仓库根自举台账 fist-mbt.db；
  - `FIST_SERVER_LOG` 指沙箱内日志；沙箱 = `temp/slh-heartbeat-box/`，每次清场（BUG-117）；
  - 子进程先 taskkill 树杀（Windows）/ terminate→kill（POSIX），finally 兜底不留孤儿 node。

用法：
  moon build --target js cmd/cli          # 产物缺失时先构建
  python scripts/patch_esm_main.py _build/js/debug/build/cmd/cli/cli.js
  python scripts/blackbox/e2e_server_log_heartbeat.py

退出码（契约，勿改档）：
  0 = 心跳真落盘且 pid 对上（含实测间隔读数）
  1 = 违例（超时无心跳 / 行形状坏 / pid 不符 / server 提前死亡）——被测对象的结论
  2 = 判据无法自证（产物缺失 / ESM patch 失败 / 无 node / 日志文件压根不存在），
      绝不让「接入没通」冒充「缺陷在场」。

自检面（`--selftest`）：不起进程、不碰产物，只考纯判定函数会不会红——
每格正反对照，格子清单从已执行对照反解打印（不手写计数）。
参数面：argparse（未知旗标天生被拒，R207）。
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import time

# BUG-138（BUG-58 同族）：Windows 默认 cp936 控制台上打印中文结论里的 ⇒ 等字符会让
# print 当场 UnicodeEncodeError——崩在结论行之前留下的 rc=1 会被读成「缺陷在场」。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", ".."))
# R3（check_entry_paths）：产物候选一律 `os.path.join(ROOT, …)` 包住消费点，
# 不做裸相对路径按调用方 cwd 寻址。debug 产物是仓内权威跑法（mcp_smoke/各 xproc 同源）。
MAIN_CANDIDATES = [
    os.path.join(ROOT, "_build", "js", "debug", "build", "cmd", "cli", "cli.js"),
    os.path.join(ROOT, "target", "js", "release", "build", "cmd", "cli", "cli.js"),
]
SANDBOX = os.path.join(ROOT, "temp", "slh-heartbeat-box")
DB = os.path.join(SANDBOX, "fist-mbt.db")
LOG = os.path.join(SANDBOX, "server.log")
NODE = os.environ.get("FIST_NODE", "node")

# 心跳间隔源码写死 60s（SERVER_LOG_HEARTBEAT_MS，无 env）⇒ 首拍 ~60s，等窗给足余量。
FIRST_BEAT_TIMEOUT_S = 100.0
POLL_S = 2.0

# 行形状真源 = server_log_line(ts, "heartbeat", "alive pid=" + pid)：
#   `<ISO> [fist-mbt] heartbeat alive pid=<pid>\n`，ISO 由 now_default() 给
#   YYYY-MM-DDTHH:MM:SSZ（UTC、无毫秒）。整行锚定（^…$），比任务书转述多钉
#   「秒级 ISO、标签带方括号、事件与 detail 空格分隔」——形状松一格就是假绿一格。
HEARTBEAT_PAT = (r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"
                 r" \[fist-mbt\] heartbeat alive pid=(\d+)$")
HEARTBEAT_RE = re.compile(HEARTBEAT_PAT)
# server.start 行（取时间戳算实测首拍间隔用；非判定承重面）
START_RE = re.compile(r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z) \[fist-mbt\] server\.start ")


def heartbeat_pid(line):
    """一行日志 ⇒ 命中心跳形状时回 pid 字符串，否则 None（纯）。"""
    m = HEARTBEAT_RE.match(line.rstrip("\r\n"))
    return m.group(1) if m else None


def judge_log(content, want_pid):
    """纯判定：日志内容 + 期望 pid ⇒ (rc, 明细/命中的心跳行列表)。

    rc 契约与 main 同档：2=文件不存在（无法自证）／1=违例／0=命中。
    main 与 --selftest 共用本函数——判定漂了自检当场红。
    """
    if content is None:
        return 2, "日志文件不存在（server 起了却一行没写？）"
    lines = [ln for ln in content.splitlines() if ln.strip()]
    if not lines:
        return 1, "日志存在但 0 行"
    hits = [ln for ln in lines if heartbeat_pid(ln) is not None]
    if not hits:
        return 1, ("%d 行里无一行匹配心跳形状（首行=%r）"
                   % (len(lines), lines[0][:120]))
    good = [ln for ln in hits if heartbeat_pid(ln) == str(want_pid)]
    if not good:
        seen = sorted({heartbeat_pid(ln) for ln in hits})
        return 1, ("心跳形状命中但 pid 不符：日志 pid=%s ≠ 子进程 pid=%s"
                   % (seen, want_pid))
    return 0, good


def _iso_to_epoch(ts):
    """server 行的 UTC ISO ⇒ epoch 秒（只为本判据算间隔读数；解析失败回 None）。"""
    try:
        import calendar
        import datetime
        dt = datetime.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ")
        return calendar.timegm(dt.timetuple())
    except ValueError:
        return None


def say(k, v):
    print("%-30s %s" % (k, v), flush=True)


def find_main():
    for p in MAIN_CANDIDATES:
        if os.path.isfile(p):
            return p
    return ""


def kill_tree(p):
    """不留孤儿 node：Windows 先 taskkill 树杀，POSIX terminate→kill，层层兜底。"""
    try:
        if os.name == "nt":
            subprocess.run(["taskkill", "/PID", str(p.pid), "/T", "/F"],
                           capture_output=True, timeout=10)
        else:
            p.terminate()
    except Exception:
        pass
    try:
        p.kill()
    except Exception:
        pass
    try:
        p.wait(timeout=10)
    except Exception:
        pass


def clean_sandbox():
    shutil.rmtree(SANDBOX, ignore_errors=True)
    os.makedirs(SANDBOX, exist_ok=True)


def ensure_patched_esm(cli):
    """重建产物没有 CJS require shim（mizchi/sqlite 的 JS 桩用 require）⇒
    点名补本判据要用那份（e2e_heartbeat_xproc 同一手，2026-09-29 实测教训）。"""
    r = subprocess.run(
        [sys.executable, os.path.join(ROOT, "scripts", "patch_esm_main.py"), cli],
        capture_output=True, text=True)
    if r.returncode != 0:
        say("REFUSED rc=2", "patch_esm_main.py 失败 rc=%s：%s"
            % (r.returncode, ((r.stderr or "") + (r.stdout or ""))[-200:]))
        return False
    say("ESM shim 已点名补齐", os.path.relpath(cli, ROOT))
    return True


def main():
    cli = find_main()
    if not cli:
        say("REFUSED rc=2", "产物不存在（找过 %s）" % ", ".join(
            os.path.relpath(p, ROOT) for p in MAIN_CANDIDATES))
        print("  出路：moon build --target js cmd/cli")
        return 2
    if shutil.which(NODE) is None and not os.path.isfile(NODE):
        say("REFUSED rc=2", "PATH 上没有可用 node（FIST_NODE=%s）" % NODE)
        return 2
    if not ensure_patched_esm(cli):
        return 2

    clean_sandbox()
    env = dict(os.environ)
    env["FIST_DB_PATH"] = DB            # BUG-122：沙箱库，绝不碰仓库根自举台账
    env["FIST_SERVER_LOG"] = LOG        # BUG-538：心跳落点显式指进沙箱
    say("被检产物", os.path.relpath(cli, ROOT))
    say("沙箱", SANDBOX)
    say("隔离库", os.path.relpath(DB, ROOT))
    say("日志", os.path.relpath(LOG, ROOT))
    say("等窗", "首拍上限 %.0fs（间隔源码写死 60s，无 env 可调）" % FIRST_BEAT_TIMEOUT_S)

    p = subprocess.Popen(
        [NODE, cli, "serve"], stdin=subprocess.PIPE,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        cwd=SANDBOX, env=env)
    t0 = time.time()
    rc, detail, content = 2, "", None
    try:
        while time.time() - t0 < FIRST_BEAT_TIMEOUT_S:
            if p.poll() is not None:
                rc, detail = 1, ("server 提前退出 rc=%s（心跳等窗内进程死亡）" % p.returncode)
                break
            try:
                with open(LOG, "rb") as f:
                    content = f.read().decode("utf-8", "replace")
            except OSError:
                content = None
            rc, detail = judge_log(content, p.pid)
            if rc == 0:
                break
            if rc == 2:
                detail = "日志还没出现（已等 %.0fs）" % (time.time() - t0)
            time.sleep(POLL_S)
        else:
            rc = 2 if content is None else 1
            detail = ("超时 %.0fs：%s" % (FIRST_BEAT_TIMEOUT_S, detail))
    finally:
        kill_tree(p)
        # 沙箱清场放 kill 之后、退出码定格之前：删不掉不算违例（Windows 文件占用竞态）
        shutil.rmtree(SANDBOX, ignore_errors=True)

    if rc != 0:
        print("E2E-SERVER-LOG-HEARTBEAT FAIL: %s" % detail, flush=True)
        return rc
    first_beat = detail[0]
    say("子进程 pid", p.pid)
    say("等了", "%.1fs" % (time.time() - t0))
    say("实测首拍间隔", _beat_interval(content) or "(取不到 server.start 时间戳，不判红只披露)")
    say("心跳行原文", first_beat)
    print("=== E2E-SERVER-LOG-HEARTBEAT PASS：serve 调用面心跳真落盘（%d 行形状+pid 双对） ==="
          % len(detail), flush=True)
    return 0


def _beat_interval(content):
    """实测间隔读数：server.start 与第一行心跳的时间戳差（秒）。纯披露，不进判定。"""
    if not content:
        return None
    start_ts, beat_ts = None, None
    for ln in content.splitlines():
        if start_ts is None:
            m = START_RE.match(ln)
            if m:
                start_ts = m.group(1)
        if beat_ts is None and heartbeat_pid(ln) is not None:
            beat_ts = ln.split(" ", 1)[0]
        if start_ts and beat_ts:
            break
    a, b = _iso_to_epoch(start_ts) if start_ts else None, \
        _iso_to_epoch(beat_ts) if beat_ts else None
    if a is None or b is None or b < a:
        return None
    return "%ds（server.start → 首拍；源码常量 60s）" % (b - a)


def _entry_probe():
    """入口面自证（R171 口径）：main 可调用，自检面与入口面不脱钩。零副作用。"""
    if not callable(main):
        raise SystemExit("入口 main 不可调用（自检面与入口面脱钩）")


def selftest():
    """判据先证明自己会红：纯判定函数正反对照 + 正则变异对照，不起进程不碰产物。"""
    _entry_probe()
    executed, fails = [], []

    def check(name, ok, why=""):
        executed.append(name)
        if not ok:
            fails.append("%s：%s" % (name, why))

    good_line = "2026-11-02T10:45:47Z [fist-mbt] heartbeat alive pid=4242"
    start_line = ("2026-11-02T10:44:47Z [fist-mbt] server.start version=0.3.11 "
                  "pid=4242 auth_mode=off")
    clean_content = start_line + "\n" + good_line + "\n"

    # G1 合成正确心跳：解析必绿（判定 0 + 回传命中行）
    rc, detail = judge_log(clean_content, 4242)
    check("G1-ok-合成正确行必绿", rc == 0 and detail == [good_line],
          "rc=%r detail=%r" % (rc, detail))
    # G1b 噪声行（server.exit 等）不误伤、多行心跳全收
    multi = clean_content + "2026-11-02T10:46:47Z [fist-mbt] heartbeat alive pid=4242\n"
    rc, detail = judge_log(multi, 4242)
    check("G1b-ok-多行心跳必绿", rc == 0 and len(detail) == 2,
          "rc=%r n=%r" % (rc, len(detail) if rc == 0 else detail))

    # M-file 无日志文件必自拒（rc=2，绝不冒充违例 1）
    rc, _ = judge_log(None, 4242)
    check("M-file-无文件必自拒2", rc == 2, "rc=%r" % rc)
    # M-empty 日志存在但 0 行 ⇒ 违例 1
    rc, _ = judge_log("", 4242)
    check("M-empty-零行必红1", rc == 1, "rc=%r" % rc)
    # M-shape 只有 server.start、无心跳行 ⇒ 违例 1
    rc, _ = judge_log(start_line + "\n", 4242)
    check("M-shape-无心跳行必红1", rc == 1, "rc=%r" % rc)

    # M-pid 心跳在场但 pid 不是子进程的 ⇒ 违例 1
    other = good_line.replace("pid=4242", "pid=9999")
    rc, detail = judge_log(start_line + "\n" + other + "\n", 4242)
    check("M-pid-pid不符必红1", rc == 1 and "9999" in str(detail),
          "rc=%r detail=%r" % (rc, detail))

    # M-regex 形状逐项变异：任何一格被放行 = 形状检查假绿
    mutants = {
        "事件拼错": good_line.replace("heartbeat", "heatbeat"),
        "标签丢方括号": good_line.replace("[fist-mbt]", "fist-mbt"),
        "pid非数字": good_line.replace("pid=4242", "pid=abc"),
        "时间戳缺T": good_line.replace("T10:45:47Z", " 10:45:47Z"),
        "缺alive": good_line.replace("alive ", ""),
        "前缀杂质": "noise " + good_line,
    }
    for tag, bad in mutants.items():
        check("M-regex-%s必红1" % tag,
              heartbeat_pid(bad) is None and judge_log(bad + "\n", 4242)[0] == 1,
              "变异行 %r 被放行 pid=%r" % (bad[:60], heartbeat_pid(bad)))

    # M-mut 正则本体变异对照（判例-29/30）：把形状正则改坏一笔，
    # 正确行必须**不再**被它命中 ⇒ 证明这把形状锁承重，不是恒绿橡皮章。
    mut = HEARTBEAT_PAT.replace("heartbeat", "heartbeatX", 1)
    check("M-mut-改坏正则抓不到正确行",
          mut != HEARTBEAT_PAT and re.match(mut, good_line) is None,
          "变异后仍命中=%r（正则不承重）" % (re.match(mut, good_line) is not None))

    # M-iso 间隔读数解析器：合法对出数、残行不出数（纯披露面，坏了只哑不打歪）
    check("M-iso-间隔解析出数",
          (_beat_interval(clean_content) or "").startswith("60s"),
          "got=%r" % _beat_interval(clean_content))
    check("M-iso-残行不出数", _beat_interval("garbage") is None,
          "got=%r" % _beat_interval("garbage"))

    print("SELFTEST %s（格子从已执行对照反解：%d 格 —— %s）"
          % ("OK" if not fails else "FAIL", len(executed), " / ".join(executed)))
    for f in fails:
        print("SELFTEST FAIL " + f)
    return 0 if not fails else 1


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="BUG-538 心跳落盘黑盒 e2e")
    ap.add_argument("--selftest", action="store_true",
                    help="不起进程：纯判定函数正反对照 + 正则变异对照")
    a = ap.parse_args()
    sys.exit(selftest() if a.selftest else main())
