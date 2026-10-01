#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""BUG-130/BUG-133 常驻判据：native 后端内存安全探针（不含任何 FIST 业务码）。

它证明什么
----------
`mizchi/sqlite` 在 native 后端把 C 侧的 `sqlite3*` / `sqlite3_stmt*` 裸指针**直接**当
MoonBit 抽象类型的值返回（`stub.c` 里没有 `moonbit_make_external_object`），另有三个函数
（`sqlite_errmsg` / `sqlite_db_filename` / `sqlite_expanded_sql`）C 侧回 `const char*`
而 MoonBit 声明成 `-> Bytes`（`Bytes` 要读长度前缀，包内注释自己写了这是 UB）。
本探针只用它的**公开 API**（open/exec/prepare/bind/step/column/finalize/close）反复开关库
并制造分配压力，把「崩」从一个 CI 读数变成一条本机可数的曲线。

判据方向（有意反向）
--------------------
exit 0 = N 次全部跑完 ⇒ 该缺陷**已消失**，此时 BUG-130 那条 CI native 臂的「已知红」就该转正、
不再许用 continue-on-error 遮；exit 非 0 = 至少一次被信号打死 ⇒ 缺陷在场，并给出 rc 分解。
（0xc0000374 / SIGSEGV / SIGABRT 三个形态在实测里都出现过，见账本 BUG-130 追记。）

用法
----
  python scripts/blackbox/e2e_native_heap_probe.py --runs 12
  python scripts/blackbox/e2e_native_heap_probe.py --selftest   # 只验尺子自己会数 rc
只在 POSIX + 已装 moon 工具链 + 系统 sqlite3 开发库的环境上能出真读数；Windows 侧
需要先走 `scripts/native-env.ps1`，否则脚本会显式拒绝出数（不拿"没跑成"当"跑过"）。
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROBE_DIR = ROOT / "temp" / "native_heap_probe"

MOON_PKG = """import {
  "mizchi/sqlite",
  "moonbitlang/x/fs",
  "moonbitlang/x/encoding",
}

pkgtype(kind: "executable")

supported_targets = "js+native"

options(
  link: { "native": { "cc-link-flags": "-lsqlite3" } },
)
"""

MAIN_MBT = r'''/// BUG-130 最小复现体：只走 mizchi/sqlite 的公开 API。
fn pad(n : Int) -> Int {
  let buf : Array[Bytes] = []
  for k = 0; k < n; k = k + 1 {
    buf.push(@encoding.encode(UTF8, "padding-padding-0123456789"))
  }
  buf.length()
}

fn one_round(round : Int) -> Int {
  let path = "temp/probe_\{(round % 4).to_string()}.db"
  let db = match @sqlite.Database::open(path) {
    None => abort("open failed: " + path)
    Some(d) => d
  }
  ignore(db.exec("CREATE TABLE IF NOT EXISTS p (a INTEGER, b TEXT)"))
  let ins = match db.prepare("INSERT INTO p(a, b) VALUES (?1, ?2)") {
    None => abort("prepare insert failed")
    Some(s) => s
  }
  ignore(ins.bind(1, @sqlite.SqlValue::Int(round)))
  ignore(
    ins.bind(
      2,
      @sqlite.SqlValue::Text(@encoding.encode(UTF8, "value-" + round.to_string())),
    ),
  )
  ignore(ins.execute())
  ins.finalize()
  let sel = match db.query("SELECT a, b FROM p") {
    None => abort("query failed")
    Some(s) => s
  }
  let mut touched = 0
  while sel.step() {
    let v = sel.column(2)
    match v {
      @sqlite.Text(b) => touched = touched + b.length()
      _ => touched = touched + 1
    }
  }
  sel.finalize()
  db.close()
  touched
}

fn main {
  @fs.create_dir("temp") catch {
    _ => ()
  }
  let mut total = 0
  for r = 0; r < 300; r = r + 1 {
    total = total + one_round(r)
    total = total + pad(400)
  }
  println("PROBE DONE total=\{total}")
}
'''


def write_probe() -> None:
    PROBE_DIR.mkdir(parents=True, exist_ok=True)
    (PROBE_DIR / "moon.pkg").write_text(MOON_PKG, encoding="utf-8")
    (PROBE_DIR / "main.mbt").write_text(MAIN_MBT, encoding="utf-8")


def cleanup() -> None:
    if PROBE_DIR.exists():
        shutil.rmtree(PROBE_DIR, ignore_errors=True)
    for p in (ROOT / "temp").glob("probe_*.db"):
        try:
            p.unlink()
        except OSError:
            pass


def classify(rc: int) -> str:
    """把退出码分成 跑完 / SIGSEGV / SIGABRT / 其它信号 / 普通失败。"""
    if rc == 0:
        return "ok"
    if rc > 128:
        sig = rc - 128
        return {11: "sigsegv", 6: "sigabort"}.get(sig, f"signal-{sig}")
    return f"fail-{rc}"


def crash_count(tally: dict) -> int:
    return sum(v for k, v in tally.items() if k != "ok")


def run_native(runs: int) -> dict:
    env = dict(os.environ)
    # 探针不碰 FIST 台账，但子进程一律带改道针（BUG-122 那条纪律对所有 spawn 都成立）
    env["FIST_DB_PATH"] = str(ROOT / "temp" / "native_heap_probe_isolated.db")
    pkg = PROBE_DIR.relative_to(ROOT).as_posix()
    tally: dict = {}
    for k in range(1, runs + 1):
        r = subprocess.run(
            ["moon", "run", "--target", "native", pkg],
            cwd=str(ROOT), env=env, capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=600,
        )
        # 崩溃那一次必须留可核对的现场，但**不许**因为留现场而改变计数口径
        tag = classify(r.returncode)
        tally[tag] = tally.get(tag, 0) + 1
        if tag != "ok":
            tail = (r.stdout + r.stderr).strip().replace("\n", " | ")[-240:]
            print(f"  run{k} rc={r.returncode} {tag} :: {tail}")
        else:
            print(f"  run{k} rc=0 ok")
    return tally


def selftest() -> int:
    """尺子的尺子：classify 的期望值全部写死在这里，不引用实现里的任何常量。"""
    cases = [(0, "ok"), (139, "sigsegv"), (134, "sigabort"), (137, "signal-9"), (1, "fail-1")]
    bad = [f"{rc}->{classify(rc)}!={want}" for rc, want in cases if classify(rc) != want]
    # 正向对照：纯 ok 的计数里不该出现崩溃（走的就是承重的那个函数）
    clean_ok = crash_count({"ok": 3})
    # 负向对照：掺一次 SIGSEGV 必须被数出来（否则这判据恒绿）
    dirty = crash_count({"ok": 2, "sigsegv": 1})
    if bad:
        print("SELFTEST FAIL:")
        for b in bad:
            print("  " + b)
        return 2
    if clean_ok != 0 or dirty != 1:
        print(f"SELFTEST FAIL: 计数口径坏了 clean_ok={clean_ok} dirty={dirty}（期望 0 与 1）")
        return 2
    print("SELFTEST OK（5 格 rc 分解 + 计数口径正负对照全过）")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=12)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--dry", action="store_true", help="只打印将生成的探针，不起进程")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if a.dry:
        write_probe()
        print(f"DRY: 探针落在 {PROBE_DIR}（moon.pkg + main.mbt），未起任何进程")
        return 0
    if os.name != "posix":
        print("拒绝出数：本判据要 POSIX 上的 native 工具链（Windows 侧先装载 "
              "scripts/native-env.ps1，或在 WSL 里跑）。没跑成 ≠ 跑过。")
        return 3
    if shutil.which("moon") is None:
        print("拒绝出数：PATH 上没有 moon")
        return 3
    write_probe()
    try:
        tally = run_native(a.runs)
    finally:
        cleanup()
    crashes = crash_count(tally)
    print(f"\nTALLY {tally} ｜ crashes={crashes}/{a.runs}")
    if crashes == 0:
        print("VERDICT: 探针全跑完 ⇒ native FFI 内存安全缺陷**不在场**；"
              "BUG-130 的 CI native 臂此时不许再挂 continue-on-error，应转正为常规门槛。")
        return 0
    print("VERDICT: 缺陷在场 ⇒ BUG-133（mizchi/sqlite native FFI 裸指针/Bytes 越界）未修，"
          "BUG-130 的 CI 红是该缺陷的读面。")
    return 1


if __name__ == "__main__":
    sys.exit(main())
