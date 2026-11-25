#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/gateway_guardian.py —— 六服务网关守护器（T0r64 · 接力棒模式）

**管什么**：六个 Agent 服务网关（`scripts/fist_gateway.py` 托管的常驻子进程）
挂死/掉线时自动拉起，并做周期健康检查 + 重启 + 日志。

**怎么管**（口径来自本机监听端口反查父进程得到的地面真相，2026-11-24）：

    python scripts/fist_gateway.py --service-id <id> --port <port> \
        --db .fist-mbt/data/agent-services.db --host 0.0.0.0 \
        --api-key-file .fist-mbt/data/<id>.apikey \
        --audit-log temp/gateway-<id>.log --open-firewall

健康面统一是 `GET http://127.0.0.1:<port>/health` →
`{"service_id": "...", "alive": true, "listen_addr": "...", "pid": N}`。

**三条硬边界**（本脚本自己给自己定的，别在别处放松）：

1. **自动路径不杀不认识的人**：端口被占但 `/health` 不应答时，只有确认占用者
   就是「本守护器此前拉起的那个 pid」（命令行含 `--service-id <id>`）才终止它；
   确认不了就只告警不动手 —— 强杀无关进程是不可逆动作，不做自动化。
   人要在挂死态强杀，走显式 `--force-restart <port> --yes`。
2. **幂等**：起不来重复起会让端口打架。起之前先看端口是否已有人监听，
   已有监听就只重探健康、不 spawn；单实例锁防两个守护器互相补刀。
3. **零新依赖**：仅 Python stdlib；子进程输出重定向到
   `.fist-mbt/data/guardian-logs/svc-<id>.log`（按体积滚动），
   守护器自身日志同目录 `guardian.log`。

用法::

    python scripts/gateway_guardian.py                # 常驻守护（默认 30s 一轮）
    python scripts/gateway_guardian.py --tick 15      # 改巡检周期
    python scripts/gateway_guardian.py --once         # 单轮：检查 + 按需拉起，随后退出
    python scripts/gateway_guardian.py --status       # 只读盘点（绝不重启），rc 0=全活
    python scripts/gateway_guardian.py --force-restart 18644 --yes
    python scripts/gateway_guardian.py --selftest     # 自检（全合成、零网络零副作用）

退出码：``0`` 正常 / 全活；``1`` 有服务不活体或拉起失败；``2`` 参数面拒绝 /
判据无法自证；``4`` 尺子自己坏了（未捕获异常）。
"""

import argparse
import json
import locale
import os
import re
import shutil
import signal
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.request

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(ROOT, ".fist-mbt", "data")
LOG_DIR = os.path.join(DATA_DIR, "guardian-logs")
STATE_PATH = os.path.join(DATA_DIR, "gateway-guardian.state.json")
LOCK_PATH = os.path.join(DATA_DIR, "gateway-guardian.lock")
GATEWAY_SCRIPT = os.path.join(ROOT, "scripts", "fist_gateway.py")
AGENT_SERVICES_DB = os.path.join(DATA_DIR, "agent-services.db")

HEALTH_TIMEOUT = float(os.environ.get("FIST_GUARDIAN_HEALTH_TIMEOUT", "5"))
TICK_SECONDS = int(os.environ.get("FIST_GUARDIAN_TICK", "30"))
STARTUP_GRACE = float(os.environ.get("FIST_GUARDIAN_STARTUP_GRACE", "8"))
BACKOFF_STEPS = (1, 5, 30)          # 连续失败第 1/2/3+ 次的退避（秒），封顶 30
LOG_ROTATE_BYTES = 2 * 1024 * 1024
CHILD_LOG_ROTATE_BYTES = 20 * 1024 * 1024

# 六服务真源：端口 ↔ service_id（2026-11-24 由 agent_service 注册表 +
# 监听端口反查父进程双向核对，两路面一致）
SERVICE_PORTS = (
    (18640, "svc-atomcode"),
    (18641, "svc-codearts"),
    (18643, "svc-freebuff"),
    (18644, "svc-marvis"),
    (18645, "svc-webai"),
    (18649, "svc-agent"),
)

# 巡检触发哨兵（与 fist_gateway._touch_patrol_trigger 写同一文件、同一形状）：
# guardian 在异常重启/挂死检出点也触发巡检唤醒，watcher 只看这一个文件。
PATROL_TRIGGER_PATH = os.path.join(ROOT, "temp", "patrol_trigger.json")

# 健康契约里「活着」的字段名。单独提成模块常量是为了让 --selftest 能真的
# 把它改坏并证明判定会翻面（变异对照，判例-29：机制格 ≠ 实现路径格）。
ALIVE_FIELD = "alive"
SERVICE_ID_FIELD = "service_id"

_OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


# ---------------------------------------------------------------- 基础设施

def emit(level, msg):
    """同时上 stdout 与守护器自身日志（滚动）。级别仅作前缀，不影响判定。"""
    line = "%s [%s] %s" % (time.strftime("%Y-%m-%dT%H:%M:%S"), level, msg)
    print(line, flush=True)
    try:
        _rotate(LOG_DIR, "guardian.log", LOG_ROTATE_BYTES)
        os.makedirs(LOG_DIR, exist_ok=True)
        with open(os.path.join(LOG_DIR, "guardian.log"), "a",
                  encoding="utf-8", errors="replace") as f:
            f.write(line + "\n")
    except OSError:
        pass          # 日志写不进去不该让守护停止


def _rotate(dirpath, name, limit):
    """按体积滚动：超限则把 name 挪成 name.1（只留一代，守护面不需要更长历史）。"""
    path = os.path.join(dirpath, name)
    try:
        if os.path.getsize(path) <= limit:
            return
        prev = path + ".1"
        if os.path.exists(prev):
            os.remove(prev)
        os.replace(path, prev)
    except OSError:
        pass


def load_state():
    try:
        with open(STATE_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_state(state):
    os.makedirs(DATA_DIR, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=DATA_DIR, prefix=".guardian-state-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(state, f, ensure_ascii=False, indent=2, sort_keys=True)
        os.replace(tmp, STATE_PATH)
    except BaseException:
        try:
            os.remove(tmp)
        except OSError:
            pass
        raise


def acquire_lock():
    """单实例锁：拿到返回文件句柄（进程存活期间必须持有），拿不到返回 None。

    用操作系统级文件锁而不是「pid 还活着」的推断：pid 会复用，推断会假绿。
    """
    os.makedirs(DATA_DIR, exist_ok=True)
    path = LOCK_PATH + ".held"
    try:
        f = open(path, "a+", encoding="utf-8")
    except OSError:
        return None
    try:
        if os.name == "nt":
            import msvcrt
            f.seek(0)
            msvcrt.locking(f.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(f.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        f.close()
        return None
    f.write("%d\n" % os.getpid())
    f.flush()
    return f


# ---------------------------------------------------------------- 纯函数面

def service_ids():
    return tuple(sid for _, sid in SERVICE_PORTS)


def expect_sid(port):
    for p, sid in SERVICE_PORTS:
        if p == int(port):
            return sid
    return ""


def health_url(port):
    return "http://127.0.0.1:%d/health" % int(port)


def child_log_path(sid):
    return os.path.join(LOG_DIR, "svc-%s.log" % sid)


def build_argv(port, sid):
    """拉起命令：与本机六服务的地面真相逐字同源（含 --api-key-file/--audit-log）。"""
    return [
        sys.executable,
        GATEWAY_SCRIPT,
        "--service-id", sid,
        "--port", str(int(port)),
        "--db", AGENT_SERVICES_DB,
        "--host", "0.0.0.0",
        "--api-key-file", os.path.join(DATA_DIR, "%s.apikey" % sid),
        "--audit-log", os.path.join("temp", "gateway-%s.log" % sid),
        "--open-firewall",
    ]


def parse_health(text, sid=""):
    """解析 /health 回包。返回 (ok, info, reason)：ok=True 才算活体。

    三条硬要求：JSON 可解析 / 活着字段为真 / 自称身份与服务登记一致。
    第三条不是洁癖：身份不符意味着这个端口后面站着别的服务，拉起它等于叠第二个。
    """
    try:
        info = json.loads(text)
    except (ValueError, TypeError):
        return False, None, "健康回包不是合法 JSON"
    if not isinstance(info, dict):
        return False, None, "健康回包不是 JSON 对象"
    if info.get(ALIVE_FIELD) is not True:
        return False, info, "健康回包 %s 非 true：%r" % (ALIVE_FIELD, info.get(ALIVE_FIELD))
    if sid:
        got = info.get(SERVICE_ID_FIELD)
        if got != sid:
            return False, info, "身份不符：期望 %s，实回 %r" % (sid, got)
    return True, info, ""


def backoff_seconds(fail_count):
    """连续失败第 N 次的退避秒数，阶梯 1/5/30 封顶。"""
    if fail_count <= 0:
        return 0
    return BACKOFF_STEPS[min(fail_count, len(BACKOFF_STEPS)) - 1]


# 通配绑定集合单独提常量：让 --selftest 能真的把它改坏并证明判定会翻面
# （变异对照，判例-29：机制格 ≠ 实现路径格）。
_WILDCARD_HOSTS = ("0.0.0.0", "::", "[::]", "")


def _pid_matches(session_pid, live_pids):
    """会话 pid 是否就是端口监听 pid（活体以进程为准）。"""
    return bool(live_pids) and int(session_pid or 0) in live_pids


def normalize_listen_addr(addr):
    """把会话地址归一成比较形状：**端口是主键**，host 只在两侧都具体时才参与比对。

    地面真相这边读到的几乎总是通配绑定（``0.0.0.0``/``::``），而注册表里可能是
    具体的 ``127.0.0.1``；若把两个方向都按「通配 → ``<any>``」折叠，两侧都是
    具体值时会假差异，所以这里**保留 host 原样、把通配标成哨兵 ``<wild>``**。
    真正的比对在 ``_addr_equivalent``：一侧通配、另一侧具体 ⇒ 视为同口（绑定形态不同
    不算口径漂移）；两侧都具体且不等 ⇒ 真漂移。
    """
    s = (addr or "").strip()
    m = re.match(r"^\[(.+)\]:(\d+)$", s)
    if m:
        host, port = m.group(1), m.group(2)
    else:
        host, _, port = s.rpartition(":")
    if not port.isdigit():
        return ""
    if host in _WILDCARD_HOSTS:
        host = "<wild>"
    return "%s:%s" % (host, port)


def _addr_equivalent(reg_norm, real_norm):
    """两个归一形是否等价（通配 vs 具体不构成差异）。"""
    if not reg_norm or not real_norm:
        return False
    rh, rp = reg_norm.split(":", 1)
    hh, hp = real_norm.split(":", 1)
    if rp != hp:                       # 端口不符 = 真差异（陈旧端口劫持那种）
        return False
    return rh == hh or rh == "<wild>" or hh == "<wild>"


def registry_liveness(db_path, sid, session_pid, session_listen_addr,
                      listen_pids, listen_addr):
    """注册表现实核对（纯函数）：把注册表的 pid/地址与端口地面真相比对。

    返回 ``(pid_ok, addr_ok)`` 两个布尔 —— 判定与写库分离，便于 --selftest 变异对照。
    端口无监听者 ⇒ pid_ok=False（进程死即停）；有监听者但 session_pid 不在其中
    ⇒ 注册表被别的实例劫持或 pid 陈旧 ⇒ pid_ok=False。
    """
    live_pids = {int(p) for p in listen_pids if p}
    pid_ok = _pid_matches(session_pid, live_pids)
    want = normalize_listen_addr(listen_addr)
    got = normalize_listen_addr(session_listen_addr)
    addr_ok = _addr_equivalent(got, want)
    return pid_ok, addr_ok


def check_registry_truth(state):
    """每轮把 ``session_pid`` 与端口真实监听 pid 比对；不一致即置 ``status='stopped'``。

    - 自动路径只改 ``status`` 这一个字段（plan 红线二）：SQL 显式列 status + updated_at。
    - 条件更新 ``WHERE service_id=? AND status='running'``：网关心跳线程每 60s 会把
      ``running`` 连同 pid 一起回写（fist_gateway.heartbeat_loop），无条件更新会与之
      拉锯；写成条件式后一致则不改、不一致则降级为 stopped，网关下一发心跳自愈。
    - 差异与时间戳落 ``guardian.log``（emit 自身落盘）；``session_listen_addr`` 与
      实际不符记 WARNING，但**不**改 status（地址不是活体判据）。
    - 读不到库 / 表不存在（如 svc-workbuddy 未建库）：跳过并 WARN，绝不猜。
    """
    try:
        con = sqlite3.connect("file:%s?mode=ro" % AGENT_SERVICES_DB.replace("\\", "/"),
                              uri=True, timeout=5)
        try:
            rows = con.execute(
                "SELECT service_id, status, session_listen_addr, session_pid "
                "FROM agent_service WHERE status IN ('running','draining')").fetchall()
        finally:
            con.close()
    except (sqlite3.Error, OSError) as e:
        emit("WARN", "注册表现实核对跳过（读库失败：%s）" % e)
        return
    now = time.strftime("%Y-%m-%dT%H:%M:%S")
    for sid, status, reg_addr, reg_pid in rows:
        pair = [(p, s) for p, s in SERVICE_PORTS if s == sid]
        if not pair:
            continue                     # 注册但不在六服务真源内（svc-workbuddy/svc-xiaoquan）
        port = pair[0][0]
        live_pids = _owner_pids_via_psutil(port)
        if not live_pids:                # 含 None（psutil 不可用）与空集（无监听）
            live_pids = set()
        # 实际地址只取端口：绑定 host 归一后由 normalize_listen_addr 吞掉差异，
        # 这里不需要读 /health（监听者即地面真相，读回包反而引入第二份口径）。
        real = "0.0.0.0:%d" % port
        pid_ok, addr_ok = registry_liveness(
            AGENT_SERVICES_DB, sid, reg_pid, reg_addr, live_pids, real)
        rec = state.setdefault(str(port), {})
        if not pid_ok:
            emit("REG", "%s:%d 注册表 pid=%s 与端口监听 %s 不符 ⇒ status→stopped"
                 % (sid, port, reg_pid, sorted(live_pids) or "<无监听>"))
            touch_patrol_trigger("guardian_registry_mismatch", sid)
            try:
                w = sqlite3.connect(AGENT_SERVICES_DB, timeout=5)
                try:
                    cur = w.execute(
                        "UPDATE agent_service SET status='stopped', updated_at=? "
                        "WHERE service_id=? AND status='running'", (now, sid))
                    w.commit()
                    if cur.rowcount:
                        emit("REG", "%s status='running'→'stopped'（pid 不符，条件更新生效）"
                             % sid)
                finally:
                    w.close()
            except (sqlite3.Error, OSError) as e:
                emit("WARN", "%s 置 stopped 写库失败：%s" % (sid, e))
            rec["registry_mismatch"] = {"ts": now, "session_pid": reg_pid,
                                        "listen_pids": sorted(live_pids)}
            continue
        rec.pop("registry_mismatch", None)
        if not addr_ok:
            emit("WARN", "%s:%d 会话地址不符：注册表=%r 实际=%r"
                 % (sid, port, reg_addr, real))


def command_belongs_to(cmdline, sid, port):
    """占用端口的进程是不是本服务的网关（命令行形状判定，纯函数）。"""
    if not cmdline:
        return False
    low = cmdline.replace("\\", "/").lower()
    if "fist_gateway.py" not in low:
        return False
    for token in ("--service-id", "--port"):
        if token not in low:
            return False
    if sid not in cmdline:
        return False
    return ("--port %d" % int(port)) in cmdline or ("--port=%d" % int(port)) in cmdline


# 多实例阈值**单一真源**在下方 P13 判据段（``MULTI_INSTANCE_MIN``，``is_multi_instance`` 消费它）。
# 这里不留第二份常量：同一规则两份实现必然漂移（判例-29「改名不是接线」同族）。
def instance_action(count):
    """端口实例数 → 该做什么（**纯函数**，无 IO、无副作用）。

    口径（计划 `fist-mbt/plan/active/2026-11-25-svc-registry-liveness.md` 工作项 1）：
      ``0``  ⇒ ``"spawn"``  没人听，维持现有拉起链（不新增逻辑）；
      ``1``  ⇒ ``"keep"``   保持现状（这正是 ``port_open()`` 一直在走的路径）；
      ``>=2``⇒ ``"alert"``  **只告警 + 写哨兵，绝不自动杀**
       （杀进程是不可逆动作；`SO_REUSEADDR` 下同端口允许多进程 LISTEN，
        实测 18641 曾 7 个、18643 曾 4 个 —— 但「有几个」不等于「该杀哪个」，
        归属与清理走人工闸门 ``--prune-orphan`` / ``--force-restart``）。

    阈值读的是 ``MULTI_INSTANCE_MIN``（P13 段），**不是本地副本**。
    为什么把「不做决策的 IO」与「决策」分开：守护主链路只需要一个词，
    判定本身必须能被合成夹具零网络地钉死。
    """
    if count is None:
        return "unknown"          # psutil 不可用：计数缺失，**不猜**、不据此动手
    if count <= 0:
        return "spawn"
    if count < MULTI_INSTANCE_MIN:
        return "keep"
    return "alert"


# ---------------------------------------------------------------- P13 活体口径判据
# 三条判据都是**纯函数**：只吃「已经读到的观测」，不做任何 IO、不写盘、不杀进程。
# 这样 --selftest 才能用合成夹具断言它们（零网络零副作用）；真实巡检只做
# 「读观测 → 调判据 → 按结论告警 / 改 status」的接线。

# 同端口监听者数达到它即判多实例（只告警 + 写哨兵，**不自动杀**）。
MULTI_INSTANCE_MIN = 2
# 命令行里认定「这是网关进程」的标记（与 GATEWAY_SCRIPT 同源）。
GATEWAY_SCRIPT_MARKER = "fist_gateway.py"
# 判据三总开关：注册表 pid 必须出现在该端口的真实 LISTEN 集内才算活体。
REQUIRE_PID_IS_LISTENER = True


def distinct_listener_pids(pids):
    """把观测到的 LISTEN pid 归一成去重排序的列表；读不到 ⇒ 空表（不猜）。"""
    try:
        return sorted({int(p) for p in pids if int(p) > 0})
    except (TypeError, ValueError):
        return []


def is_multi_instance(pids):
    """判据一：同端口监听者数 >= ``MULTI_INSTANCE_MIN`` ⇒ 多实例。"""
    return len(distinct_listener_pids(pids)) >= MULTI_INSTANCE_MIN


def parse_gateway_port(cmdline):
    """从命令行解析网关自称的 ``--port``（空格与等号两种写法都认）；解析不到返回 ``None``。"""
    if not cmdline:
        return None
    m = re.search(r"--port[ =](\d+)\b", str(cmdline))
    if not m:
        return None
    try:
        return int(m.group(1))
    except ValueError:
        return None


def is_gateway_cmdline(cmdline):
    """命令行是不是网关进程（按 ``GATEWAY_SCRIPT_MARKER`` 判定，分隔符与大小写不敏感）。"""
    if not cmdline:
        return False
    return GATEWAY_SCRIPT_MARKER in str(cmdline).replace("\\", "/").lower()


def find_orphan_gateway_ports(processes, known_ports=None):
    """判据二：命令行是网关、但端口不在 ``SERVICE_PORTS`` 真源内 ⇒ ``{pid: port}``。

    这就是计划里说的「陈旧端口」：历史上起过、但端口已不在六服务真源里的实例。
    """
    if known_ports is None:
        known = {int(p) for p, _ in SERVICE_PORTS}
    else:
        known = {int(p) for p in known_ports}
    found = {}
    for pid, cmdline in (processes or {}).items():
        if not is_gateway_cmdline(cmdline):
            continue
        port = parse_gateway_port(cmdline)
        if port is not None and port not in known:
            try:
                found[int(pid)] = port
            except (TypeError, ValueError):
                continue
    return found


SERVICE_ID_FLAG = "--service-id"


def parse_service_id(cmdline):
    """从命令行解析网关自称的 ``--service-id``（空格与等号两种写法都认）；解析不到返回 ``""``。

    与 ``parse_gateway_port`` 同族（同一份命令行契约的两个字段），**不是**第二套端口解析。
    """
    if not cmdline:
        return ""
    m = re.search(re.escape(SERVICE_ID_FLAG) + r"[ =](\S+)", str(cmdline))
    return m.group(1).strip('"') if m else ""


def stale_inventory(processes, known_ports=None):
    """盘点（纯函数、零 IO）：进程表 → ``{"ports": {port: [sid, ...]}}``，**只含陈旧端口**。

    「陈旧端口」的判定**整块复用** ``find_orphan_gateway_ports``（P13 判据二，已有
    L5/L6/L7 三格锁）——本文件不许出现第二份「什么算陈旧」的实现（判例：同一规则多份实现）。
    本函数只加一件判据二没做的事：给每个陈旧端口补上命令行自称的 ``--service-id``，
    让盘点行能写出 ``18646 svc-workbuddy`` 这种可点名的一行（否则读者只看到一个光秃秃的端口号）。

    解析不出 sid ⇒ 该行 sid 记 ``""``（打印面显示 ``<未知>``），**不猜**。
    """
    stale = find_orphan_gateway_ports(processes, known_ports)
    ports = {}
    for pid, port in (stale or {}).items():
        cmdline = (processes or {}).get(pid, "") or ""
        sid = parse_service_id(cmdline)
        bucket = ports.setdefault(port, [])
        if sid and sid not in bucket:
            bucket.append(sid)
    return {"ports": ports}


def registry_pid_verdict(session_pid, listener_pids):
    """判据三：注册表 ``session_pid`` 是不是该端口当前的真正监听者。

    返回 ``"alive"`` / ``"dead"`` / ``"unknown"``：

    * 监听集为空 ⇒ ``"unknown"``（读不到就不猜，交探活链裁决，绝不假绿）；
    * ``REQUIRE_PID_IS_LISTENER`` 且 pid 不在监听集内 ⇒ ``"dead"``（进程死即停，
      自动路径据此把 ``status`` 置成 ``'stopped'``）；
    * 其余 ⇒ ``"alive"``。
    """
    listeners = distinct_listener_pids(listener_pids)
    if not listeners:
        return "unknown"
    if not REQUIRE_PID_IS_LISTENER:
        return "alive"
    try:
        return "alive" if int(session_pid) in listeners else "dead"
    except (TypeError, ValueError):
        return "unknown"


# ---------------------------------------------------------------- 系统探测面

def port_open(port):
    """TCP 是否有人监听（纯网络探，不动任何进程）。"""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(1.0)
    try:
        return s.connect_ex(("127.0.0.1", int(port))) == 0
    except OSError:
        return False
    finally:
        s.close()


def probe_health(port, sid):
    """探 /health。返回 (ok, info, reason)；reason 里带原始异常便于日志定位。"""
    url = health_url(port)
    try:
        with _OPENER.open(url, timeout=HEALTH_TIMEOUT) as resp:
            body = resp.read(65536).decode("utf-8", "replace")
    except Exception as e:  # noqa: BLE001 —— 探活失败的原因要如实落到日志
        return False, None, "%s: %s" % (type(e).__name__, e)
    ok, info, why = parse_health(body, sid)
    return ok, info, why


def _run_capture(argv, timeout):
    """跑一条只读查询并**二进制**捕获输出。

    为什么不能用 ``text=True``：本机 Windows 的 powershell 回包是本地代码页
    （GBK），`subprocess` 的文本模式按 UTF-8 解码会直接 UnicodeDecodeError
    —— 实测契约表因此恒空、占用者判定恒假，而假的是「不敢动手」这一侧
    （看着安全，实际功能整个失效）。这里二进制取回后按本地码页 + 替换解码。
    """
    try:
        out = subprocess.run(argv, capture_output=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return ""
    raw = out.stdout or b""
    if not raw:
        return ""
    for enc in ("utf-8", locale.getpreferredencoding(False) or "cp936", "cp936", "latin-1"):
        try:
            return raw.decode(enc)
        except (UnicodeDecodeError, LookupError):
            continue
    return raw.decode("utf-8", "replace")


def _cmdline_via_psutil(pid):
    """返回命令行字符串；psutil 不可用 / 进程不存在 ⇒ 返回 **None**（不返回空串）。

    为什么区分 ``None`` 与 ``""``：``pid_alive`` 靠「取没取到」判生死，
    失败也回空串会让**死进程永远判活**（``"" is not None`` 为真），
    于是「拉起后再探活」会把从没起来的服务读成已恢复。
    """
    try:
        import psutil
    except ImportError:
        return None
    try:
        return " ".join(str(a) for a in psutil.Process(int(pid)).cmdline())
    except Exception:
        return None


def local_process_contract():
    """本机 pid ↔ 命令行映射。

    首选 **psutil 进程内读取**（无子进程、无编码面，已实测可用）；
    不可用时退回 powershell 固定契约（只取 PID/CommandLine 两列，二进制捕获）。
    两条路都拿不到就返回空表 —— 宁可判定链走「不敢动手」分支，也不猜。
    """
    try:
        import psutil
        table = {}
        for p in psutil.process_iter(["pid", "cmdline"]):
            try:
                info = p.info
                argv = info.get("cmdline") or []
                table[int(info["pid"])] = " ".join(str(a) for a in argv)
            except (psutil.Error, ValueError, TypeError):
                continue
        if table:
            return table
    except Exception:
        pass
    if os.name != "nt":
        return {}
    script = ("$ErrorActionPreference='SilentlyContinue';"
              "Get-CimInstance -ClassName Win32_Process | "
              "ForEach-Object { \"$($_.ProcessId)`t$($_.CommandLine)\" }")
    text = _run_capture(
        ["powershell", "-NoProfile", "-NonInteractive",
         "-OutputFormat", "Text", "-Command", script], 40)
    table = {}
    for line in text.splitlines():
        parts = line.split("\t", 1)
        if len(parts) != 2:
            continue
        try:
            table[int(parts[0])] = parts[1]
        except ValueError:
            continue
    return table


def _owner_pids_via_psutil(port):
    """用 psutil 反查监听该端口的 pid（纯读）；没装返回 None。"""
    try:
        import psutil
    except ImportError:
        return None
    pids = set()
    try:
        for c in psutil.net_connections(kind="tcp"):
            if c.status == "LISTEN" and c.laddr and int(c.laddr.port) == int(port):
                if c.pid:
                    pids.add(int(c.pid))
    except Exception:
        return set()
    return pids


def listen_pids(ports):
    """三态读数：``{port: {pid,...}}`` 的**已观测计数**；psutil 不可用 ⇒ ``None``。

    只按端口计数 ``LISTEN`` 套接字，**不做任何归属判定**——同一端口上可能有多个
    pid（``SO_REUSEADDR`` 允许），也可能有非本服务的进程在听（那条走告警，不是静默）。
    与 ``_owner_pids_via_psutil`` 是**同一 ``net_connections`` 口径、同一次枚举**，
    只是这里一次取回全部端口的表，避免每端口各扫一遍全量连接表。
    """
    try:
        import psutil
    except ImportError:
        return None
    wanted = set(int(p) for p in ports)
    table = dict((p, set()) for p in wanted)
    try:
        for c in psutil.net_connections(kind="tcp"):
            if c.status != "LISTEN" or not c.laddr:
                continue
            port = int(c.laddr.port)
            if port in wanted and c.pid:
                table[port].add(int(c.pid))
    except Exception:
        return None
    return table


def find_port_owner(port):
    """反查占用端口的 pid + 命令行。返回 (pid, cmdline)；拿不到返回 (None, "")，**不猜**。

    先用 psutil 定位监听 pid（``net_connections`` 权威面），再用 psutil/契约表
    取该 pid 的命令行做归属比对 —— **按端口定位，不靠遍历全表**（全表扫描会把
    「历史上起过、现已退出但端口被复用」的旧命令行认成当前占用者）。
    """
    if os.name == "nt":
        sid = expect_sid(port)
        pids = _owner_pids_via_psutil(port)
        if pids is not None:
            table = local_process_contract()
            for pid in sorted(pids):
                cmdline = table.get(pid) or _cmdline_via_psutil(pid)
                if command_belongs_to(cmdline, sid, port):
                    return pid, cmdline
            # 端口有人听但不是本服务网关：回第一个 pid 供日志定位，
            # 命令行按实读给出（可能为空串），判定链据 ``mine`` 拒绝动手。
            if pids:
                first = sorted(pids)[0]
                return first, table.get(first) or _cmdline_via_psutil(first)
            return None, ""
        # 无 psutil：退回全表扫描（慢，但归属判定口径不变）
        table = local_process_contract()
        for pid, cmdline in sorted(table.items()):
            if command_belongs_to(cmdline, sid, port):
                return pid, cmdline
        return None, ""
    for tool in (["ss", "-ltnp"], ["lsof", "-nP", "-iTCP:%d" % int(port), "-sTCP:LISTEN"]):
        text = _run_capture(tool, 15)
        import re
        m = re.search(r"pid=(\d+)", text) or re.search(r"\s(\d+)\s+\S+\s+\S+\s*$", text, re.M)
        if m:
            try:
                return int(m.group(1)), text.strip()
            except ValueError:
                pass
    return None, ""


def terminate_pid(pid):
    """温和终止：先 taskkill /PID（等价 SIGTERM），留 5s，还在才 /F 强杀。"""
    try:
        if os.name == "nt":
            subprocess.run(["taskkill", "/PID", str(pid)],
                           capture_output=True, timeout=15)
        else:
            os.kill(int(pid), signal.SIGTERM)
    except (OSError, subprocess.SubprocessError):
        return True       # 杀不动：按「不再持有」处理由后续探活裁决
    deadline = time.time() + 5
    while time.time() < deadline:
        if not pid_alive(pid):
            return True
        time.sleep(0.5)
    try:
        if os.name == "nt":
            subprocess.run(["taskkill", "/F", "/PID", str(pid)],
                           capture_output=True, timeout=15)
        else:
            os.kill(int(pid), signal.SIGKILL)
    except (OSError, subprocess.SubprocessError):
        pass
    return not pid_alive(pid)


def pid_alive(pid):
    """进程是否还在。优先 psutil（无子进程）；退回 OS 原生探测。"""
    cmdline = _cmdline_via_psutil(pid)
    if cmdline is not None:
        return True
    try:
        if os.name == "nt":
            text = _run_capture(
                ["powershell", "-NoProfile", "-NonInteractive", "-Command",
                 "if (Get-Process -Id %d -ErrorAction SilentlyContinue) { 'Y' } else { 'N' }"
                 % int(pid)], 15)
            return "Y" in text
        os.kill(int(pid), 0)
        return True
    except (OSError, ValueError, subprocess.SubprocessError):
        return False


def spawn_gateway(port, sid):
    """起一个网关子进程，输出重定向到滚动日志。返回 Popen 或 None（起不来）。"""
    argv = build_argv(port, sid)
    try:
        os.makedirs(LOG_DIR, exist_ok=True)
        _rotate(LOG_DIR, "svc-%s.log" % sid, CHILD_LOG_ROTATE_BYTES)
        log = open(child_log_path(sid), "a", encoding="utf-8", errors="replace")
    except OSError as e:
        emit("FAIL", "打开子进程日志失败 %s: %s" % (child_log_path(sid), e))
        return None
    try:
        proc = subprocess.Popen(
            argv,
            cwd=ROOT,
            stdout=log,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            creationflags=getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
            | getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
    except OSError as e:
        log.close()
        emit("FAIL", "spawn 失败 %s: %s" % (sid, e))
        return None
    return proc


def touch_patrol_trigger(event, sid):
    """异常重启/挂死检出点写巡检触发哨兵（temp/patrol_trigger.json）。

    与 fist_gateway._touch_patrol_trigger 同一文件、同一 JSON 形状
    （event / service_id / ts / debounce_s），覆盖写 + tmp+os.replace 原子落盘
    （watcher 读不到半写文件）。失败只记日志，绝不阻断守护主链路。
    """
    payload = json.dumps({
        "event": event,
        "service_id": sid,
        "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "debounce_s": 60,
    }, ensure_ascii=False)
    try:
        tdir = os.path.dirname(PATROL_TRIGGER_PATH)
        os.makedirs(tdir, exist_ok=True)
        tmp = os.path.join(tdir, "patrol_trigger.json.tmp%d" % os.getpid())
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(payload)
        os.replace(tmp, PATROL_TRIGGER_PATH)
    except OSError as e:
        emit("WARN", "patrol_trigger 写入失败（不阻断）: %s" % e)
        return
    emit("PATROL", "哨兵已写 %s (%s)" % (event, sid))


def restart_service(port, sid, state):
    """一次「拉起」动作的完整判定链。返回 True 表示该服务事后被确认活体。

    链路：先看端口有没有人听 → 有人听就只重探健康（不叠第二个）；
    没人听就直接起；有人听但不活且**确认是本服务自己的网关占着死端口**
    ⇒ 清理重启（挂死语义）。身份不明 ⇒ 只告警不动手。
    """
    rec = state.setdefault(str(port), {})
    detected_hang = False
    if port_open(port):
        ok, info, why = probe_health(port, sid)
        if ok:
            rec.update(fail_count=0, last_ok=time.time(), pid=(info or {}).get("pid"))
            emit("OK", "%s:%d 存活 pid=%s" % (sid, port, (info or {}).get("pid")))
            return True
        emit("DOWN", "%s:%d 端口有监听但健康不应答（%s）" % (sid, port, why))
        owner_pid, cmdline = find_port_owner(port)
        mine = command_belongs_to(cmdline, sid, port)
        if not mine:
            # 身份不明 = 不敢杀。这里含两种情况：探不到占用者、或占用者是别的进程。
            # 本守护器**只清自己拉起的那个**，绝不强杀无关进程（不可逆动作不做自动化）。
            emit("WARN", "%s:%d 占用者非本服务网关（pid=%s cmd=%s）⇒ 不自动杀，"
                         "请人工核对该端口" % (sid, port, owner_pid, cmdline or "<读不到>"))
            rec["fail_count"] = rec.get("fail_count", 0) + 1
            return False
        # 确认是自己的网关 ⇒ 属「挂死」而非「被抢端口」，自动清理并重启。
        if owner_pid is None:
            emit("WARN", "%s:%d 命令行确认是本服务，但取不到 pid ⇒ 只告警不动手"
                 % (sid, port))
            rec["fail_count"] = rec.get("fail_count", 0) + 1
            return False
        emit("ACT", "%s:%d 清理自己的僵死进程 pid=%s" % (sid, port, owner_pid))
        detected_hang = True
        touch_patrol_trigger("gateway_guardian_hang", sid)
        if not terminate_pid(owner_pid):
            emit("FAIL", "%s:%d 终止 pid=%s 未生效" % (sid, port, owner_pid))
            return False
    else:
        emit("DOWN", "%s:%d 无监听" % (sid, port))

    if not detected_hang:
        touch_patrol_trigger("gateway_guardian_restart", sid)
    proc = spawn_gateway(port, sid)
    if proc is None:
        rec["fail_count"] = rec.get("fail_count", 0) + 1
        return False
    deadline = time.time() + STARTUP_GRACE
    while time.time() < deadline:
        if port_open(port):
            ok, info, why = probe_health(port, sid)
            if ok:
                rec.update(fail_count=0, last_ok=time.time(), pid=proc.pid,
                           spawned_at=time.time())
                emit("UP", "%s:%d 已拉起并确认活体 pid=%s" % (sid, port, proc.pid))
                return True
        time.sleep(1.0)
    ok, info, why = probe_health(port, sid)
    if ok:
        rec.update(fail_count=0, last_ok=time.time(), pid=proc.pid, spawned_at=time.time())
        emit("UP", "%s:%d 已拉起（宽限期末仍活）pid=%s" % (sid, port, proc.pid))
        return True
    rec["fail_count"] = rec.get("fail_count", 0) + 1
    emit("FAIL", "%s:%d 拉起后仍未活体（%s）" % (sid, port, why))
    return False


def check_once(state):
    """单轮巡检：逐个必查（不用 all() 短路——首轮实证会漏检首个挂掉之后的成员）。

    每轮先取一次**全端口 LISTEN 计数**（``listen_pids``，与 ``_owner_pids_via_psutil``
    同一 ``net_connections`` 枚举口径、同一次全表枚举），再逐端口按实例数分流：
    ``spawn`` 走既有拉起链 / ``keep`` 走既有探活 / ``alert`` **只告警 + 写哨兵，不杀**。
    """
    # 注册表现实核对先于端口探测：端口有人听但注册表 pid 已被别的实例顶掉时，
    # 这一轮就要把 status 落回 stopped（否则 autoplan 轮转池会照 running 派发）。
    try:
        check_registry_truth(state)
    except Exception as e:  # noqa: BLE001 —— 核对失败不该让整轮巡检停摆
        emit("ERR", "注册表现实核对异常（不阻断巡检）：%s: %s" % (type(e).__name__, e))
    ports = [p for p, _ in SERVICE_PORTS]
    counts = listen_pids(ports)
    if counts is None:
        emit("WARN", "psutil.net_connections 不可用 ⇒ 本轮跳过实例计数"
                     "（不影响探活/拉起；计数缺失不猜、不动手）")
    results = []
    for port, sid in SERVICE_PORTS:
        count = None if counts is None else len(counts.get(port, ()))
        action = instance_action(count)
        if action == "alert":
            # >=2 个监听者：SO_REUSEADDR 下确有多实例叠加。只告警 + 写哨兵，
            # 绝不自动杀（不可逆动作不做自动化；清理走人工闸门 --prune-orphan / --force-restart）。
            pids = sorted(counts.get(port, ())) if counts else []
            emit("ALERT", "%s:%d 多实例检出：%d 个 LISTEN pid=%s ⇒ 只告警不杀，"
                          "请人工核对（patrol_trigger=guardian_multi_instance）"
                 % (sid, port, count, pids))
            touch_patrol_trigger("guardian_multi_instance", sid)
            rec = state.setdefault(str(port), {})
            rec["multi_instance"] = True
            rec["instance_count"] = count
            rec["last_multi_instance"] = time.time()
            results.append(port_open(port))
            continue
        if counts is not None and count <= 1:
            rec = state.setdefault(str(port), {})
            rec["multi_instance"] = False
            rec["instance_count"] = count
        if port_open(port):
            ok, info, why = probe_health(port, sid)
            rec = state.setdefault(str(port), {})
            if ok:
                rec.update(fail_count=0, last_ok=time.time(),
                           pid=(info or {}).get("pid"))
                emit("OK", "%s:%d alive pid=%s" % (sid, port, (info or {}).get("pid")))
            else:
                rec["fail_count"] = rec.get("fail_count", 0) + 1
                emit("DOWN", "%s:%d %s" % (sid, port, why))
                ok = restart_service(port, sid, state)
            results.append(ok)
        else:
            emit("DOWN", "%s:%d 无监听 ⇒ 拉起" % (sid, port))
            ok = restart_service(port, sid, state)
            results.append(ok)
    save_state(state)
    alive = sum(1 for r in results if r)
    emit("SUM", "%d/%d 活体" % (alive, len(SERVICE_PORTS)))
    return alive == len(SERVICE_PORTS)


def write_status(state):
    """只读盘点：绝不重启、绝不改注册表（本函数除 emit 外零写）。

    每行三列地面真相：``实例`` = 该端口 LISTEN 进程数（多实例叠加是既有告警面）；
    ``注册`` = 注册表 session_pid 是否就是端口监听 pid；
    ``陈旧端口`` = 另起一块逐行点名（端口不在六服务真源内、却仍有 fist_gateway 在跑）。

    为什么陈旧端口**不并进真源那 6 行**：它们不是 ``SERVICE_PORTS`` 的成员，
    没有 sid/verdict/pid 语义；塞进去会把非真源服务算进「活体 N/M」并翻掉退出码。
    独立块只读、只点名，**不改退出码**（rc 仍 = 六真源全 ALIVE）。
    """
    rows = []
    counts = listen_pids([p for p, _ in SERVICE_PORTS])
    stale_ports = stale_inventory(local_process_contract())["ports"]
    reg_rows = {}
    try:
        con = sqlite3.connect("file:%s?mode=ro" % AGENT_SERVICES_DB.replace("\\", "/"),
                              uri=True, timeout=5)
        try:
            reg_rows = {sid: (reg_addr, reg_pid) for sid, reg_addr, reg_pid in con.execute(
                "SELECT service_id, session_listen_addr, session_pid FROM agent_service")}
        finally:
            con.close()
    except (sqlite3.Error, OSError) as e:
        emit("WARN", "盘点读注册表失败（不影响探活）：%s" % e)
    for port, sid in SERVICE_PORTS:
        if port_open(port):
            ok, info, why = probe_health(port, sid)
            verdict, pid = ("ALIVE" if ok else "SICK"), (info or {}).get("pid")
        else:
            verdict, pid, why = "DOWN", None, "no listener"
        count = None if counts is None else len(counts.get(port, ()))
        live_pids = set() if counts is None else {int(p) for p in counts.get(port, ()) if p}
        reg_addr, reg_pid = reg_rows.get(sid, ("", 0))
        pid_ok, addr_ok = registry_liveness(AGENT_SERVICES_DB, sid, reg_pid,
                                            reg_addr, live_pids, "0.0.0.0:%d" % port)
        if not live_pids:
            reg_note = "reg=<无监听>"
        elif pid_ok and addr_ok:
            reg_note = "reg=ok"
        elif pid_ok:
            reg_note = "reg=addr_drift(%s)" % (reg_addr or "<空>")
        else:
            reg_note = "reg=pid_mismatch(%s≠%s)" % (reg_pid, sorted(live_pids))
        rows.append((port, sid, verdict, pid, why, count, reg_note))
    for port, sid, verdict, pid, note, count, reg_note in rows:
        emit("ROW", "%-6s %-14s %-6s pid=%-8s 实例=%-3s %s %s"
             % (port, sid, verdict, pid if pid else "-",
                "-" if count is None else count, reg_note, note))
    emit("SUM", "%d/%d 活体" % (sum(1 for r in rows if r[2] == "ALIVE"), len(rows)))
    for port in sorted(stale_ports):
        sids = ",".join(stale_ports[port]) or "<未知>"
        emit("STALE", "%-6s %s" % (port, sids))
    return rows


# ---------------------------------------------------------------- 自检

def selftest():
    """合成夹具自证：**零网络、零写盘、零 spawn**（全走纯函数面）。

    每格都是真断言；其中两格是**变异对照**——把被测机制改坏，断言判定必须翻红：
      M_ALIVE  : 把 ``ALIVE_FIELD`` 改成不存在的字段名 ⇒ 健康回包必须被判死；
      M_IDENTITY: 身份不符的回包必须被判死（端口后面站着别的服务 ⇒ 不许算活）。
    只断言「正常路径通过」的锁证明不了它真在看，所以这两格不可省。
    """
    fails = []
    ran = []

    def cell(name, cond, detail=""):
        ran.append(name)
        if not cond:
            fails.append((name, detail))

    # ---- G 族：干净必绿 ----
    good = '{"service_id": "svc-marvis", "alive": true, "listen_addr": "0.0.0.0:18644", "pid": 7}'
    ok, info, why = parse_health(good, "svc-marvis")
    cell("G1-alive-true-green", ok and info.get("pid") == 7, why)
    ok, info, why = parse_health(good, "")
    cell("G2-empty-sid-no-identity-check", ok, why)

    # ---- R 族：注册表现实核对（pid ↔ 端口真实监听 pid）----
    # 正常态必绿两格：pid 命中 + 地址命中（含通配绑定的归一）。
    p_ok, a_ok = registry_liveness(AGENT_SERVICES_DB, "svc-marvis", 35616,
                                   "0.0.0.0:18644", [35616], "0.0.0.0:18644")
    cell("R1-pid-match-green", p_ok and a_ok)
    p_ok, a_ok = registry_liveness(AGENT_SERVICES_DB, "svc-marvis", 35616,
                                   "0.0.0.0:18644", [35616], "127.0.0.1:18644")
    cell("R2-wildcard-addr-normalized-green", p_ok and a_ok,
         "通配绑定与具体绑定不该算差异")
    # 违例必红：注册表 pid 与端口监听不是同一个进程 ⇒ 判非活。
    p_ok, _ = registry_liveness(AGENT_SERVICES_DB, "svc-atomcode", 43200,
                                "0.0.0.0:18640", [26296], "0.0.0.0:18640")
    cell("R3-pid-mismatch-red", not p_ok, "注册表 pid 与监听不符却判活 ⇒ 谎报存活")
    p_ok, _ = registry_liveness(AGENT_SERVICES_DB, "svc-marvis", 47364,
                                "0.0.0.0:18644", [], "0.0.0.0:18644")
    cell("R4-no-listener-red", not p_ok, "端口无监听者却判活 ⇒ 进程死即停失效")
    p_ok, _ = registry_liveness(AGENT_SERVICES_DB, "svc-marvis", 0,
                                "0.0.0.0:18644", [35616], "0.0.0.0:18644")
    cell("R5-zero-pid-red", not p_ok, "session_pid=0（未登记）不该被当成命中")
    # 地址不符记 WARNING 但不判死：pid 仍对 ⇒ 活体成立，只是会话地址口径漂移。
    p_ok, a_ok = registry_liveness(AGENT_SERVICES_DB, "svc-marvis", 35616,
                                   "127.0.0.1:18642", [35616], "0.0.0.0:18644")
    cell("R6-addr-drift-not-fatal", p_ok and not a_ok, "地址漂移不该把活体判死")
    # 变异对照（判例-29）：把判定机制本身改坏，上面两格违例必须翻红。
    global _WILDCARD_HOSTS
    saved_wild = _WILDCARD_HOSTS
    try:
        _WILDCARD_HOSTS = ()                      # 通配不再归一
        _, a_ok = registry_liveness(AGENT_SERVICES_DB, "svc-marvis", 35616,
                                    "0.0.0.0:18644", [35616], "127.0.0.1:18644")
        cell("R7-wildcard-mutated-red", not a_ok, "改坏归一后仍判一致 ⇒ 锁恒绿")
    finally:
        _WILDCARD_HOSTS = saved_wild
    saved_match = globals()["_pid_matches"]
    try:
        globals()["_pid_matches"] = lambda session_pid, live_pids: bool(live_pids)
        p_ok, _ = registry_liveness(AGENT_SERVICES_DB, "svc-atomcode", 43200,
                                    "0.0.0.0:18640", [26296], "0.0.0.0:18640")
        cell("R8-match-mutated-red", p_ok,
             "判定改成「有人听就算」后仍判活 ⇒ 锁恒绿（进程死即停失效）")
    finally:
        globals()["_pid_matches"] = saved_match

    # ---- M 族：变异/违例必红 ----
    global ALIVE_FIELD
    saved_field = ALIVE_FIELD
    ALIVE_FIELD = "alive_typo_mutated"
    ok, _, why = parse_health(good, "svc-marvis")
    ALIVE_FIELD = saved_field
    cell("M_ALIVE-mutated-field-red", not ok, "改坏字段名后仍判活 ⇒ 锁恒绿")

    bad_id = '{"service_id": "svc-others", "alive": true, "pid": 9}'
    ok, _, why = parse_health(bad_id, "svc-marvis")
    cell("M_IDENTITY-mismatch-red", not ok, "身份不符却判活 ⇒ 会叠第二个网关")

    ok, _, why = parse_health('{"service_id": "svc-marvis", "alive": false}', "svc-marvis")
    cell("M3-alive-false-red", not ok, why)
    ok, _, why = parse_health("not json at all", "svc-marvis")
    cell("M4-non-json-red", not ok, why)
    ok, _, why = parse_health("[1,2,3]", "svc-marvis")
    cell("M5-non-object-red", not ok, why)
    ok, _, why = parse_health("", "svc-marvis")
    cell("M6-empty-body-red", not ok, why)

    cmd_mine = ('python scripts/fist_gateway.py --service-id svc-marvis --port 18644 '
                '--db .fist-mbt/data/agent-services.db --host 0.0.0.0')
    cmd_other = 'node _build/js/debug/build/cmd/cli/cli.js serve'
    cell("M7-ownership-mine-green", command_belongs_to(cmd_mine, "svc-marvis", 18644))
    cell("M8-ownership-stranger-red",
         not command_belongs_to(cmd_other, "svc-marvis", 18644), "陌生进程被认成自己人")
    cell("M9-ownership-wrong-port-red",
         not command_belongs_to(cmd_mine.replace("--port 18644", "--port 18645"),
                                "svc-marvis", 18644), "端口不符被认成自己人")
    cell("M10-ownership-empty-red", not command_belongs_to("", "svc-marvis", 18644))

    cell("B1-backoff-ladder", [backoff_seconds(n) for n in (1, 2, 3, 4)] == [1, 5, 30, 30])
    cell("B2-backoff-zero", backoff_seconds(0) == 0)

    argv = build_argv(18649, "svc-agent")
    cell("C1-argv-shape",
         argv[:2] == [sys.executable, os.path.join("scripts", "fist_gateway.py")]
         or argv[1].endswith("fist_gateway.py"), argv)
    cell("C2-argv-carries-identity",
         "--service-id" in argv and "svc-agent" in argv
         and "--port" in argv and "18649" in argv, argv)
    cell("C3-argv-carry-apikey-file",
         any(a.endswith(os.path.join("data", "svc-agent.apikey")) for a in argv), argv)
    cell("C4-health-url", health_url(18640) == "http://127.0.0.1:18640/health")
    cell("C5-six-ports-are-the-truth",
         [p for p, _ in SERVICE_PORTS] == [18640, 18641, 18643, 18644, 18645, 18649],
         str(SERVICE_PORTS))
    cell("C6-expect-sid-roundtrip",
         all(expect_sid(p) == s for p, s in SERVICE_PORTS) and expect_sid(9999) == "")
    cell("C7-service-ids-unique", len(set(service_ids())) == len(SERVICE_PORTS))

    # ---- L 族：P13 三条活体口径判据（每判据 = 干净必绿 + 违例必红 + 变异对照） ----
    # 变异对照改的是**被测代码里的真实常量/比较符**，不是注释 —— 改注释的锁恒绿（判例-30）。
    global MULTI_INSTANCE_MIN, GATEWAY_SCRIPT_MARKER, REQUIRE_PID_IS_LISTENER

    cmd_marvis = ('python scripts/fist_gateway.py --service-id svc-marvis '
                  '--port 18644 --db .fist-mbt/data/agent-services.db')
    cmd_stale = ('python scripts/fist_gateway.py --service-id svc-marvis '
                 '--port 18642 --db .fist-mbt/data/agent-services.db')

    cell("L1-multi-one-not-trigger", not is_multi_instance([7001]),
         "单监听者被报多实例")
    cell("L2-multi-two-trigger", is_multi_instance([7001, 7002]),
         "同端口两个 LISTEN pid 未检出")
    cell("L3-multi-dedup-one",
         not is_multi_instance([7001, 7001, 7001]), "同一 pid 重复计数误判多实例")

    saved_min = MULTI_INSTANCE_MIN
    MULTI_INSTANCE_MIN = 1
    multi_bad = is_multi_instance([7001])
    MULTI_INSTANCE_MIN = saved_min
    cell("L4-multi-mutation-red", multi_bad,
         "把阈值改成 1 后单实例必须被判多实例（变异失效 ⇒ 锁恒绿）")

    cell("L5-orphan-stale-port-found",
         find_orphan_gateway_ports({4001: cmd_marvis, 4002: cmd_stale}) == {4002: 18642},
         str(find_orphan_gateway_ports({4001: cmd_marvis, 4002: cmd_stale})))
    cell("L6-orphan-non-gateway-ignored",
         find_orphan_gateway_ports({4003: "node cli.js serve --port 18642"}) == {},
         "非网关进程的端口不算陈旧端口")

    saved_marker = GATEWAY_SCRIPT_MARKER
    GATEWAY_SCRIPT_MARKER = "gateway_typo_mutated"
    orphan_bad = find_orphan_gateway_ports({4002: cmd_stale})
    GATEWAY_SCRIPT_MARKER = saved_marker
    cell("L7-orphan-mutation-red", orphan_bad == {},
         "改坏脚本标记后必须认不出任何网关进程（变异失效 ⇒ 锁恒绿）")

    cell("L8-pid-is-listener-alive",
         registry_pid_verdict(7001, [7001]) == "alive", "真监听者被判死")
    cell("L9-pid-not-listener-dead",
         registry_pid_verdict(47364, [35616]) == "dead",
         "注册表 pid 不在监听集内却判活（计划背景的劫持形态）")
    cell("L10-pid-no-listener-unknown",
         registry_pid_verdict(7001, []) == "unknown", "读不到监听集必须不猜")
    cell("L11-pid-garbage-unknown",
         registry_pid_verdict("not-a-pid", [35616]) == "unknown", "pid 非法必须不猜")

    saved_req = REQUIRE_PID_IS_LISTENER
    REQUIRE_PID_IS_LISTENER = False
    verdict_bad = registry_pid_verdict(47364, [35616])
    REQUIRE_PID_IS_LISTENER = saved_req
    cell("L12-pid-mutation-red", verdict_bad == "alive",
         "关掉 pid∈监听集闸后必须一律判活（变异失效 ⇒ 锁恒绿）")

    # ---- N 族：多实例检出在**本实现路径**上的两格（N=新面，与 L 族不重叠）----
    # L1~L4 钉的是 ``is_multi_instance``（P13 判据一）；这两格钉的是 T0r92 本轮
    # 真正接进 check_once 的那两个新面：``listen_pids`` 的计数口径 与
    # ``instance_action`` 的分流决策。只测「带某机制的调用」不等于测了脚本自己的
    # 实现（判例-29 同族）—— 把 ``check_once`` 里的接线拆掉，L 族照样全绿。

    # N1：合成 psutil 夹具（零网络、零写盘）证明 listen_pids 只数 LISTEN、去重、
    # 且只认真源端口 —— 非 LISTEN / 无关端口 / pid=None 一律不进表。
    class _FakeLaddr(object):
        def __init__(self, ip, port):
            self.ip = ip
            self.port = port

    class _FakeConn(object):
        def __init__(self, status, ip, port, pid):
            self.status = status
            self.laddr = _FakeLaddr(ip, port)
            self.pid = pid

    saved_net_connections = None
    try:
        import psutil as _psutil
        saved_net_connections = _psutil.net_connections
        _psutil.net_connections = lambda kind="tcp": [
            _FakeConn("LISTEN", "0.0.0.0", 18640, 7001),
            _FakeConn("LISTEN", "0.0.0.0", 18640, 7002),   # 同端口第二个 ⇒ 多实例
            _FakeConn("ESTABLISHED", "127.0.0.1", 18640, 7003),  # 非 LISTEN 不进表
            _FakeConn("LISTEN", "0.0.0.0", 9999, 7004),    # 非真源端口不进表
            _FakeConn("LISTEN", "0.0.0.0", 18644, None),   # pid 读不到 ⇒ 不计数
            _FakeConn("LISTEN", "0.0.0.0", 18641, 7005),
            _FakeConn("LISTEN", "0.0.0.0", 18641, 7005),   # 重复 pid ⇒ 去重
        ]
        got = listen_pids([18640, 18641, 18643])
        cell("N1-listen-counts-dedup-shape",
             got == {18640: {7001, 7002}, 18641: {7005}, 18643: set()}, repr(got))
        # N2：三态分流决策 —— 0=spawn / 1=keep / >=2=alert / None=unknown。
        cell("N2-instance-action-ladder",
             [instance_action(c) for c in (0, 1, 2, 7)]
             == ["spawn", "keep", "alert", "alert"]
             and instance_action(None) == "unknown",
             str([instance_action(c) for c in (0, 1, 2, 7, None)]))
        # N3：变异对照 —— 把 MULTI_INSTANCE_MIN 改成 1（真实常量，不是注释），
        # 单实例必须翻成 alert；改回后必须复原。判例-30：改注释的锁恒绿。
        saved_n_min = MULTI_INSTANCE_MIN
        MULTI_INSTANCE_MIN = 1
        mutated = instance_action(1)
        MULTI_INSTANCE_MIN = saved_n_min
        cell("N3-threshold-mutation-red", mutated == "alert" and instance_action(1) == "keep",
             "阈值改坏后单实例未翻 alert，或复原后仍不回 keep ⇒ 锁恒绿")
    finally:
        if saved_net_connections is not None:
            _psutil.net_connections = saved_net_connections

    if fails:
        print("SELFTEST FAIL: %d/%d 格红" % (len(fails), len(ran)))
        for name, detail in fails:
            print("  - %s：%s" % (name, detail))
        return 1
    fam = {}
    for name in ran:
        key = "M" if name.startswith("M") or name.startswith("M_") else name.split("-")[0][0]
        fam[key] = fam.get(key, 0) + 1
    print("SELFTEST OK: %d 格（反解：%s）"
          % (len(ran), " / ".join("%s×%d" % (k, v) if v > 1 else k
                                  for k, v in sorted(fam.items()))))
    return 0


# ---------------------------------------------------------------- 入口

def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    ap = argparse.ArgumentParser(
        description="六服务网关守护器（T0r64）：挂死自动拉起 + 周期健康检查 + 日志")
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--selftest", action="store_true", help="合成自检（零网络零副作用）")
    g.add_argument("--status", action="store_true", help="只读盘点，绝不重启")
    g.add_argument("--once", action="store_true", help="单轮巡检后退出")
    g.add_argument("--force-restart", type=int, metavar="PORT",
                   help="人工强杀并重启指定端口的本服务（需配 --yes）")
    ap.add_argument("--tick", type=int, default=TICK_SECONDS,
                    help="巡检周期秒数（默认 %d）" % TICK_SECONDS)
    ap.add_argument("--yes", action="store_true",
                    help="对 --force-restart 的人工确认（缺它拒绝动手）")
    args = ap.parse_args(argv)

    if args.selftest:
        return selftest()

    if args.force_restart is not None:
        if not args.yes:
            emit("REFUSE", "--force-restart 需要 --yes 显式确认（不可逆动作不做自动化）")
            return 2
        sid = expect_sid(args.force_restart)
        if not sid:
            emit("REFUSE", "端口 %d 不在六服务真源里" % args.force_restart)
            return 2
        state = load_state()
        ok = restart_service(args.force_restart, sid, state)
        save_state(state)
        return 0 if ok else 1

    lock = acquire_lock()
    if lock is None:
        emit("BUSY", "已有另一个 gateway_guardian 在跑（单实例锁被占）")
        return 0

    try:
        if args.status:
            return 0 if _status_only() else 1
        if args.once:
            return 0 if check_once(load_state()) else 1
        emit("RUN", "守护中：六服务 tick=%ds 日志=%s" % (args.tick, LOG_DIR))
        while True:
            try:
                check_once(load_state())
            except Exception as e:  # noqa: BLE001 —— 一轮异常不该让守护整体死掉
                emit("ERR", "巡检轮次异常：%s: %s" % (type(e).__name__, e))
            time.sleep(max(1, args.tick))
    except KeyboardInterrupt:
        emit("STOP", "收到中断，退出（已拉起的网关子进程不受影响）")
        return 0
    finally:
        try:
            if os.name == "nt":
                import msvcrt
                lock.seek(0)
                msvcrt.locking(lock.fileno(), msvcrt.LK_UNLCK, 1)
        except OSError:
            pass
        lock.close()


def _status_only():
    rows = write_status(load_state())
    return all(r[2] == "ALIVE" for r in rows)


if __name__ == "__main__":
    sys.exit(main())

