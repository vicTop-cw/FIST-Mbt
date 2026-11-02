#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/run_fist_task_pool.py — 任务池 yaml 管理器（.git/fist/tasks/ 文件协议，Tier2 PR2）。

真源：docs/2026-10-21-fist-governance-tier2-plan.md「PR2」节。多机认领协议：
init 建池骨架 → publish 把 yaml 收进 backlog → claim 移入 claimed/<machine-id>/ 并写 owner
→ release 退回 backlog / archive 进 done / fail 进 failed → list 按 status/machine 过滤。

纪律（R207 判例族 / 判例-29/30）：
  - argparse 子解析器：未知旗标、缺参数天生被拒（rc=2），没有手写 argv 分派；
  - `--root DIR` 可把池指到别处（沙箱/自检用），缺省 <repo>/.git/fist；
  - `--selftest` 全程在系统临时目录自建沙箱（tempfile），不碰真实台账，且含**变异对照**：
      M1 owner_guard 变异：把「重复认领必拒」的锁改坏 ⇒ 行为必须随之翻转（第二次认领成功）——
         证明守卫格盯的真是这把锁（判例-30：改坏的是代码行为，不是注释）；
      M2 dup_guard 变异：把「同 task_id 重复 publish 必拒」同样做一遍（判例-29：
         机制格要按机制注入，不靠正则翻自己的源码）。
退出码：0 = 正常 / 自检全绿；1 = 操作失败（die）；2 = argparse 拒绝（未知旗标 / 缺参数）；
4 = 工具自身异常（判据无法自证，不冒用 1）。
"""
import argparse
import io
import re
import shutil
import sys
import tempfile
from contextlib import redirect_stdout
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_BASE = ROOT / ".git" / "fist"
STATUSES = ("backlog", "claimed", "done", "failed")
# 变异对照注入面（判例-29/30）：常态全 False；--selftest 逐个短暂扳 True，把对应的锁改坏，
# 断言行为随之翻转 ⇒ 证明守卫格盯的是真机制（不是恒绿的自说自话）。
FAULT = {"owner_guard": False, "dup_guard": False}


def die(msg):
    print("ERROR " + msg, file=sys.stderr)
    sys.exit(1)


def parse_yaml(text):
    """极简 yaml（同 check_ci_step_position.py 的纪律：不把可用性交给 PyYAML 是否在场）。"""
    d, k = {}, None
    for line in text.splitlines():
        line = line.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        s = line.strip()
        if s.startswith("- "):
            if k is None:
                die("yaml list item outside key: " + line)
            d[k].append(s[2:].strip().strip('"'))
            continue
        m = re.match(r"^(\w+):\s*(.*)$", s)
        if not m:
            die("yaml line unparsed: " + line)
        k, v = m.group(1), m.group(2).strip()
        if v == "":
            d[k], k = [], k
        elif v.startswith("["):
            d[k] = [x.strip().strip('"') for x in v[1:-1].split(",") if x.strip()]
        elif v in ("null", "~"):
            d[k] = None
        elif re.fullmatch(r"-?\d+", v):
            d[k] = int(v)
        else:
            d[k] = v.strip('"')
    return d


def dump_yaml(d):
    def val(v):
        if isinstance(v, list):
            return "[%s]" % ", ".join(str(x) for x in v)
        if v is None:
            return "null"
        return str(v)
    return "\n".join("%s: %s" % (k, val(v)) for k, v in d.items()) + "\n"


class Pool:
    def __init__(self, base):
        self.base = Path(base)
        self.t = self.base / "tasks"
        self.m = self.base / "machines.yaml"

    def init(self):
        for s in STATUSES:
            (self.t / s).mkdir(parents=True, exist_ok=True)
        if not self.m.exists():
            self.m.write_text("machines: {}\n", encoding="utf-8")

    def find(self, tid):
        hits = sorted(self.t.rglob(tid + ".yaml")) if self.t.is_dir() else []
        return hits[0] if hits else None

    def read(self, p):
        d = parse_yaml(p.read_text(encoding="utf-8"))
        return d if d.get("task_id") else dict(d, task_id=p.stem)

    def move(self, tid, sub, machine=None):
        src = self.find(tid)
        if src is None:
            die("task not found: " + tid)
        dst_dir = self.t / "claimed" / machine if sub == "claimed" else self.t / sub
        dst_dir.mkdir(parents=True, exist_ok=True)
        shutil.move(str(src), str(dst_dir / (tid + ".yaml")))
        return dst_dir / (tid + ".yaml")

    def publish(self, yaml_path):
        self.init()
        p = Path(yaml_path)
        if not p.is_file():
            die("no such yaml: " + str(yaml_path))
        d = parse_yaml(p.read_text(encoding="utf-8"))
        if not d.get("task_id"):
            die("yaml missing task_id: " + str(yaml_path))
        dst = self.t / "backlog" / (d["task_id"] + ".yaml")
        if dst.exists() and not FAULT["dup_guard"]:
            die("task already in pool: " + d["task_id"])
        d = dict(d, status=d.get("status") or "backlog")
        dst.write_text(dump_yaml(d), encoding="utf-8")
        print("publish: " + str(dst))

    def claim(self, tid, machine):
        src = self.find(tid)
        if src is None:
            die("task not found: " + tid)
        d = self.read(src)
        if d.get("owner") and not FAULT["owner_guard"]:
            die("task owned by %s: %s" % (d["owner"], tid))
        self.write(src, dict(d, owner=machine, status="claimed"))
        dst = self.move(tid, "claimed", machine)
        print("claim: %s -> %s (%s)" % (tid, machine, dst))

    def release(self, tid):
        src = self.find(tid)
        if src is None or "claimed" not in src.parts:
            die("task not claimed: " + tid)
        self.write(src, dict(self.read(src), owner=None, status="backlog"))
        self.move(tid, "backlog")
        print("release: " + tid)

    def finish(self, tid, status):
        src = self.find(tid)
        if src is None:
            die("task not found: " + tid)
        self.write(src, dict(self.read(src), status=status))
        self.move(tid, status)
        print("%s: %s" % (status, tid))

    def list_tasks(self, status=None, machine=None):
        rows = [self.read(p) for p in sorted(self.t.rglob("*.yaml"))] if self.t.is_dir() else []
        for d in sorted(rows, key=lambda x: str(x.get("created_at") or x.get("task_id") or "")):
            if status and d.get("status") != status:
                continue
            if machine and d.get("owner") != machine:
                continue
            print("%s | %s | owner=%s | %s" % (d.get("task_id"), d.get("status"),
                                               d.get("owner") or "-", d.get("title") or ""))

    def write(self, p, d):
        p.write_text(dump_yaml(d), encoding="utf-8")


class _Parser(argparse.ArgumentParser):
    # argparse 默认 error() 走内部 sys.exit(2)，ast 出口面看不见 ⇒ 承诺 rc=2 会被
    # check_exit_code_contract 判成模块面幻影（R1）。显式字面 sys.exit(2) 把码改真（R42-44 同法）。
    def error(self, message):
        self.print_usage(sys.stderr)
        sys.stderr.write("%s: error: %s\n" % (self.prog, message))
        sys.exit(2)


def build_parser():
    ap = _Parser(
        prog="run_fist_task_pool.py",
        description="任务池 yaml 管理器（.git/fist/tasks/，Tier2 PR2）")
    ap.add_argument("--root", metavar="DIR", default=None,
                    help="池根目录（默认 <repo>/.git/fist；沙箱/自检用）")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("init", help="初始化 tasks/{backlog,claimed,done,failed} + machines.yaml")
    p = sub.add_parser("publish", help="把 yaml 收进 backlog/")
    p.add_argument("yaml")
    p = sub.add_parser("claim", help="认领：移入 claimed/<machine-id>/ 并写 owner")
    p.add_argument("task_id")
    p.add_argument("machine_id")
    for name, help_ in (("release", "退回 backlog（认领超时/放弃）"),
                        ("archive", "移到 done/（PR 已合入）"),
                        ("fail", "移到 failed/（反复打回，需人判断）")):
        p = sub.add_parser(name, help=help_)
        p.add_argument("task_id")
    p = sub.add_parser("list", help="列出任务（可按 status/machine 过滤）")
    p.add_argument("--status", default=None)
    p.add_argument("--machine", default=None)
    return ap


def main(argv=None):
    args = build_parser().parse_args(argv)
    pool = Pool(args.root or DEFAULT_BASE)
    if args.cmd == "init":
        pool.init()
        print("init: " + str(pool.base))
    elif args.cmd == "publish":
        pool.publish(args.yaml)
    elif args.cmd == "claim":
        pool.claim(args.task_id, args.machine_id)
    elif args.cmd == "release":
        pool.release(args.task_id)
    elif args.cmd == "archive":
        pool.finish(args.task_id, "done")
    elif args.cmd == "fail":
        pool.finish(args.task_id, "failed")
    elif args.cmd == "list":
        pool.list_tasks(args.status, args.machine)
    return 0


def _captured(fn):
    """跑一段会 print 的代码，拿回输出（自检不用子进程，保持 hermetic）。"""
    buf = io.StringIO()
    with redirect_stdout(buf):
        fn()
    return buf.getvalue()


def selftest():
    fails, executed = [], []

    def cell(name, cond, detail=""):
        executed.append(name)
        if not cond:
            fails.append((name, detail))

    base = Path(tempfile.mkdtemp(prefix="fist-task-pool-selftest-"))
    pool = Pool(base)
    t1 = base / "T1.yaml"
    t1.write_text('task_id: T1\ntitle: demo one\nfiles_touched:\n  - "a.md"\n', encoding="utf-8")

    # —— G：干净生命周期（init → publish → claim → release/archive/fail → list）——
    pool.init()
    cell("G1-init-creates-pool",
         all((pool.t / s).is_dir() for s in STATUSES) and pool.m.exists())
    pool.publish(t1)
    b1 = pool.t / "backlog" / "T1.yaml"
    cell("G2-publish-lands-backlog", b1.exists() and pool.read(b1).get("status") == "backlog")
    try:
        pool.publish(t1)
        cell("G3-duplicate-publish-rejected", False, "重复 publish 没有被拒")
    except SystemExit:
        cell("G3-duplicate-publish-rejected", True)
    FAULT["dup_guard"] = True
    try:
        _captured(lambda: pool.publish(t1))
        cell("M1-dup-guard-mutation-flips-behavior", True)
    except SystemExit:
        cell("M1-dup-guard-mutation-flips-behavior", False, "锁改坏后行为没翻转 ⇒ 守卫格没盯住机制")
    finally:
        FAULT["dup_guard"] = False
    pool.claim("T1", "m1")
    c1 = pool.t / "claimed" / "m1" / "T1.yaml"
    cell("G4-claim-moves-and-owns", c1.exists() and pool.read(c1).get("owner") == "m1")
    try:
        pool.claim("T1", "m2")
        cell("G5-double-claim-rejected", False, "重复认领没有被拒")
    except SystemExit:
        cell("G5-double-claim-rejected", True)
    FAULT["owner_guard"] = True
    try:
        _captured(lambda: pool.claim("T1", "m2"))
        cell("M2-owner-guard-mutation-flips-behavior", True)
    except SystemExit:
        cell("M2-owner-guard-mutation-flips-behavior", False, "锁改坏后行为没翻转 ⇒ 守卫格没盯住机制")
    finally:
        FAULT["owner_guard"] = False
    cell("M2b-mutation-overwrote-owner", pool.read(pool.find("T1")).get("owner") == "m2",
         "变异后 owner 未被改写 ⇒ 变异没落在机制上（假对照）")
    pool.release("T1")
    r1 = pool.t / "backlog" / "T1.yaml"
    cell("G6-release-returns-backlog", r1.exists(), "backlog/T1.yaml 不在")
    pool.claim("T1", "m1")
    pool.finish("T1", "done")
    cell("G7-archive-moves-done",
         (pool.t / "done" / "T1.yaml").exists() and pool.read(pool.find("T1")).get("status") == "done")
    t2 = base / "T2.yaml"
    t2.write_text("task_id: T2\ntitle: demo two\n", encoding="utf-8")
    pool.publish(t2)
    pool.claim("T2", "m2")
    pool.finish("T2", "failed")
    cell("G8-fail-moves-failed", (pool.t / "failed" / "T2.yaml").exists())
    t3 = base / "T3.yaml"
    t3.write_text("task_id: T3\ntitle: demo three\n", encoding="utf-8")
    pool.publish(t3)
    pool.claim("T3", "m1")
    out = _captured(lambda: pool.list_tasks("claimed", "m1"))
    cell("G9-list-filters-status-and-machine",
         "T3" in out and "T1" not in out and "T2" not in out, repr(out))
    out_all = _captured(lambda: pool.list_tasks())
    cell("G10-list-shows-all-statuses",
         all(x in out_all for x in ("T1 | done", "T2 | failed", "T3 | claimed")), repr(out_all))

    # —— M/R：参数面（argparse 天生拒未知旗标）与解析守卫 ——
    try:
        build_parser().parse_args(["--definitely-not-a-real-flag"])
        cell("R1-unknown-flag-rejected", False, "argparse 没拒未知旗标")
    except SystemExit as e:
        cell("R1-unknown-flag-rejected", e.code == 2, "code=%r" % (e.code,))
    try:
        build_parser().parse_args([])
        cell("R2-missing-subcommand-rejected", False, "argparse 没拒缺子命令")
    except SystemExit as e:
        cell("R2-missing-subcommand-rejected", e.code == 2, "code=%r" % (e.code,))
    try:
        parse_yaml("just a bare line")
        cell("R3-malformed-yaml-rejected", False, "解析器没拒非法行")
    except SystemExit:
        cell("R3-malformed-yaml-rejected", True)

    if fails:
        print("SELFTEST FAIL: %d/%d 格红" % (len(fails), len(executed)))
        for name, detail in fails:
            print("  - %s：%s" % (name, detail))
        return 1
    fam = {}
    for name in executed:
        key = name.split("-")[0]
        fam[key] = fam.get(key, 0) + 1
    print("SELFTEST OK: %d 格（反解：%s，族名取自已执行格子名首段，不手写计数；沙箱 %s）"
          % (len(executed), " / ".join("%s×%d" % (k, v) for k, v in sorted(fam.items())), base))
    return 0


if __name__ == "__main__":
    argv = sys.argv[1:]
    if argv and argv[0] == "--selftest":
        sys.exit(selftest())
    try:
        sys.exit(main(argv))
    except SystemExit:
        raise
    except Exception as e:  # noqa: BLE001 — 工具自身异常走 4 号档，不冒用 1
        sys.stderr.write("FATAL(4): %r\n" % (e,))
        sys.exit(4)
