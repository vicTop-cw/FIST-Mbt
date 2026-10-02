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
exit 0 = N 次全部跑完 ⇒ 本轮样本里没复现，CI 的 native 全量测试这一步才会跑；exit 1 = 至少一次
被信号打死 ⇒ 缺陷在场，红话点名 BUG-133 与转正前置。
（0xc0000374 / SIGSEGV / SIGABRT 三个形态在实测里都出现过，见账本 BUG-130 追记。）

**0/N 不等于「已修」**：这是概率性失效。**同一支尺、同一次会话里连跑两发**就给出过 `3/12` 与 `0/12`
两端（2026-10-02 WSL ubuntu-22.04，读数原件与逐跑 rc 分解见账本 BUG-133 追记），所以这一格是**抽检门**，
不是关闭条件——BUG-133 的关闭条件收紧成两格：① 抽检连发都 0 崩溃，② `git archive HEAD` 干净树上
`moon test --target native` 全量通过。

退出码是契约的一部分（`ci.yml` 与 `fist-ci.yml` 的 native 臂都把它当门前置，只有 0 才放行
`Test (native)`；后者还按这四档各写一条 `::error::` 注解，2026-10-01 owner 裁决③）：
  0 = N 次全跑完（本轮样本未复现）→ CI 继续跑 native 全量测试；不等于「已修」
  1 = 有崩溃（缺陷在场）  → CI 红，红话点名 BUG-133 与转正前置
  3 = 平台/工具链不给量   → 拒绝出数，**不是**「跑过」也不是「没问题」
  4 = 尺子自己坏了    → 与产品红分开报：探针编译不过，或判据自身未捕获异常（超时/编码/路径）。
      Python 默认给崩掉的脚本 rc=1，而 1 在本契约里是「缺陷在场」——不隔这一层，「我没跑成」
      就会被 CI 读成「BUG-133 又复现了」（既往同类脚本两次把「没跑成」读成「全红」）。

用法
----
  python scripts/blackbox/e2e_native_heap_probe.py --runs 12
  python scripts/blackbox/e2e_native_heap_probe.py --selftest   # 验尺子自己会数 rc + rc 隔离 + 构建门真跑
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
SELFTEST_DIR = ROOT / "temp" / "native_heap_probe_selftest"

# 退出码口径（CI 的 native 臂按这三档分流，红话必须能归因）：
#   0 = N 次全跑完 ⇒ 缺陷不在场，native 全量测试许当常规门槛
#   1 = 至少一次被信号打死 ⇒ 缺陷在场（BUG-133），点名它
#   3 = 平台/工具链不给量（非 POSIX 或没有 moon）⇒ 拒绝出数，不等于跑过
#   4 = 探针自己编译不过 ⇒ 尺子坏了，绝不把「没跑成」数成「全红」
RC_OK, RC_CRASH, RC_REFUSE, RC_RULER = 0, 1, 3, 4


def force_utf8_output() -> None:
    """判据的正文就是读数，先保住输出通道。

    Windows 默认 cp936 控制台上打印 `⇒` 会抛 UnicodeEncodeError，脚本**崩在结论行之前**留下
    rc=1 —— 而 1 在本契约里是「缺陷在场」，等于尺子自己坏了却顶替产品报案（2026-10-01 实测：
    同一份 `--selftest` 不带 PYTHONIOENCODING 时 rc=1，带 utf8 时 rc=0）。
    """
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:  # noqa: BLE001 - 通道换不动就是读数丢失，宁可显式判「尺子坏了」
            sys.stderr.write("VERDICT: ruler broken (output channel unavailable)\n")
            raise SystemExit(RC_RULER)


def run_guarded(body, label: str = "") -> int:
    """把「尺子自己崩了」与「缺陷在场」分开：判据的未捕获异常一律 RC_RULER，不许冒用 rc=1。

    超时（`subprocess.TimeoutExpired`）、路径、编码这几类崩法都发生在本判据自己身上，
    而 Python 默认给 rc=1 —— 那正好是 CI 里「BUG-133 在场」那一档。SystemExit 原样透传，
    否则「拒绝出数」（rc=3）会被吞成 0。
    """
    try:
        return body()
    except SystemExit:
        raise
    except BaseException as exc:  # noqa: BLE001 - 这里要的正是"任何崩法都归到尺子那一档"
        print(f"VERDICT: 尺子坏了（{label}判据自身异常 {type(exc).__name__}: {exc}）"
              "⇒ 红的是判据，不是产品，先修判据再读 native 面。")
        return RC_RULER

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


def moon(cmd: list, timeout: int = 600):
    env = dict(os.environ)
    # 探针不碰 FIST 台账，但子进程一律带改道针（BUG-122 那条纪律对所有 spawn 都成立）
    env["FIST_DB_PATH"] = str(ROOT / "temp" / "native_heap_probe_isolated.db")
    return subprocess.run(cmd, cwd=str(ROOT), env=env, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=timeout)


def precompile(pkg: str, label: str = "探针") -> int:
    """起手一道预编译门：探针自己编译不过 ⇒ 判「尺子坏了」。

    既往同类脚本两次因自身语法问题把「没跑成」读成「全红」（账本 BUG-130 追记），
    所以这一档必须与「缺陷在场」（rc=1）分开——CI 的 native 臂按退出码四档分流。
    `label` 让自检那一次真跑能说清「这是对照，不是本判据坏了」，否则 CI 日志里会躺着一行
    「尺子坏了」而它其实是绿色的那一格在证明自己能红。
    """
    r = moon(["moon", "build", "--target", "native", pkg])
    if r.returncode != 0:
        tail = (r.stdout + r.stderr).strip().replace("\n", " | ")[-300:]
        print(f"预编译门：{label}编译不过 rc={r.returncode} :: {tail}")
        print(f"VERDICT: 尺子坏了（{label}既不是缺陷在场，也不是 native 门槛通过）——先修判据再读 native 面。")
    return r.returncode


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


def run_native(runs: int, pkg: str) -> dict:
    tally: dict = {}
    for k in range(1, runs + 1):
        r = moon(["moon", "run", "--target", "native", pkg])
        # 崩溃那一次必须留可核对的现场，但**不许**因为留现场而改变计数口径
        tag = classify(r.returncode)
        tally[tag] = tally.get(tag, 0) + 1
        if tag != "ok":
            tail = (r.stdout + r.stderr).strip().replace("\n", " | ")[-240:]
            print(f"  run{k} rc={r.returncode} {tag} :: {tail}")
        else:
            print(f"  run{k} rc=0 ok")
    return tally


BROKEN_MBT = 'fn main {\n  let wrong : Int = "这不是 Int"\n  println(wrong)\n}\n'


def selftest() -> int:
    """尺子的尺子。

    四组：① classify 的 rc 分解（期望值写死在这里，不引用实现里的任何常量）；
    ② 计数口径的正负对照（纯 ok 必须 0、掺一次 SIGSEGV 必须 1）；
    ③ rc 隔离的成对对照（判据自己抛超时 ⇒ 必须归 4；`SystemExit(3)` 必须原样透传，不被吞成 0）；
    ④ **构建门真跑**：故意喂一份明知编译不过的探针，要求 precompile 报非零。
    ④ 没有 moon/非 POSIX 时跑不了，就**显式打 SKIPPED** 并把「只跑了前三格」写进结论行——
    拿「函数有 docstring / 常量等于 4」当承重证明是恒真式装饰，既往同类判据就是这么自喂自己的。
    """
    cases = [(0, "ok"), (139, "sigsegv"), (134, "sigabort"), (137, "signal-9"), (1, "fail-1")]
    bad = [f"{rc}->{classify(rc)}!={want}" for rc, want in cases if classify(rc) != want]
    if bad:
        print("SELFTEST FAIL:")
        for b in bad:
            print("  " + b)
        return 2
    # 正向对照：纯 ok 的计数里不该出现崩溃（走的就是承重的那个函数）
    # 负向对照：掺一次 SIGSEGV 必须被数出来（否则这判据恒绿）
    clean_ok, dirty = crash_count({"ok": 3}), crash_count({"ok": 2, "sigsegv": 1})
    if clean_ok != 0 or dirty != 1:
        print(f"SELFTEST FAIL: 计数口径坏了 clean_ok={clean_ok} dirty={dirty}（期望 0 与 1）")
        return 2
    # rc 隔离对照（成对）：判据自己崩 ⇒ 必须归 4，不许冒用「缺陷在场」的 1；
    # 而「拒绝出数」的 SystemExit(3) 必须原样透传，不能被兜底的 except 吞成 0。
    # 期望值写死成字面 4/3，不引用 RC_RULER/RC_REFUSE——拿实现自己的常量当期望是恒真式装饰。
    ruler_rc = run_guarded(lambda: (_ for _ in ()).throw(subprocess.TimeoutExpired("moon", 0)),
                           label="自检对照（故意让判据自己抛超时，报 4 才算这一格真跑过）：")
    try:
        run_guarded(lambda: (_ for _ in ()).throw(SystemExit(RC_REFUSE)))
        exit_rc = "被吞掉(无异常)"
    except SystemExit as e:
        exit_rc = e.code
    if ruler_rc != 4 or exit_rc != 3:
        print(f"SELFTEST FAIL: rc 隔离坏了 崩={ruler_rc}（期望 4）/ 拒={exit_rc}（期望 3）")
        return 2
    gate = "SKIPPED（非 POSIX 或无 moon ⇒ 构建门这一格没跑到，别把前三格当四格读）"
    if os.name == "posix" and shutil.which("moon"):
        SELFTEST_DIR.mkdir(parents=True, exist_ok=True)
        try:
            (SELFTEST_DIR / "moon.pkg").write_text(MOON_PKG, encoding="utf-8")
            (SELFTEST_DIR / "main.mbt").write_text(BROKEN_MBT, encoding="utf-8")
            got = precompile(SELFTEST_DIR.relative_to(ROOT).as_posix(),
                               label="自检对照（故意喂进去的坏探针，报非零才算这一格真跑过）")
            if got == 0:
                print("SELFTEST FAIL: 明知编译不过的探针被构建门放过了 ⇒ 这一档恒绿")
                return 2
            gate = f"真跑 OK（故意喂编译不过的探针 ⇒ rc={got}，没被数成崩溃）"
        finally:
            shutil.rmtree(SELFTEST_DIR, ignore_errors=True)
    print(f"SELFTEST OK（rc 分解 {len(cases)} 格 + 计数口径正负对照 2 支 + rc 隔离对照 2 支"
          f"（判据自身崩⇒{RC_RULER} / 拒绝出数⇒{RC_REFUSE} 原样透传）+ 构建门 1 格：{gate}）")
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
        return RC_REFUSE
    if shutil.which("moon") is None:
        print("拒绝出数：PATH 上没有 moon")
        return RC_REFUSE
    write_probe()
    try:
        pkg = PROBE_DIR.relative_to(ROOT).as_posix()
        if precompile(pkg) != 0:
            return RC_RULER
        tally = run_native(a.runs, pkg)
    finally:
        cleanup()
    crashes = crash_count(tally)
    print(f"\nTALLY {tally} ｜ crashes={crashes}/{a.runs}")
    if crashes == 0:
        print(f"VERDICT: {a.runs} 次采样未复现 ⇒ 本步放行，native 全量测试继续跑。"
              "但 0/N **不等于缺陷已修**——同一支尺、同一次会话连跑两发就给出过 3/12 与 0/12 两端，"
              "这是概率性失效；真正的关闭条件在账本 BUG-133（抽检连发 0 崩溃 + 干净树 native 全量通过）。")
        return RC_OK
    print("VERDICT: 缺陷在场 ⇒ BUG-133（mizchi/sqlite native FFI 裸指针/Bytes 越界）未修，"
          "BUG-130 的 CI 红是该缺陷的读面。")
    return RC_CRASH


if __name__ == "__main__":
    force_utf8_output()
    sys.exit(run_guarded(main))
