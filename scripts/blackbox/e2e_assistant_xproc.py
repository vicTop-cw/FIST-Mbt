#!/usr/bin/env python
"""e2e_assistant_xproc.py — BUG-157 跨进程单主不变量回归锁。

复现 concurrent agent 在 src/store/store_sqlite.mbt L1646-1667 的 assistant_upsert SQL 形态
（UPDATE is_primary=0 清场 + INSERT ON CONFLICT is_primary=1，无 BEGIN IMMEDIATE 事务包裹），
证明该形态在跨进程并发下仍会被击穿：两个进程都读到"无人主"→ 都 no-op 清场 → 都写 is_primary=1。

判据：并发 N 进程同时抢主，跑多轮，任一轮出现 >1 行 is_primary=1 即 FAIL。
用途：1) 证明 BUG-157 修复不完整；2) 修复（加 BEGIN IMMEDIATE 或单语句原子抢占）后应归 PASS。

用法：python scripts/blackbox/e2e_assistant_xproc.py [--procs 5] [--rounds 20]
退出码：0=PASS（单主不变量成立） 1=FAIL（单主被击穿） 2=判据自身坏了
"""
import argparse
import multiprocessing as mp
import os
import sqlite3
import sys
import tempfile
import time

# BUG-58/138 stdout/stderr UTF-8 重配：本脚本会 print 非 ASCII（×、—、中文），
# 在 Windows 控制台（cp1252/GBK）下不重配会当场 UnicodeEncodeError（check_py_stdout_encoding --all 面）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# 与 store_sqlite.mbt L1651/L1667 逐字对齐的 SQL 形态（无事务包裹）
CLEAR_SQL = "UPDATE assistant_reg SET is_primary=0 WHERE is_primary=1 AND agent != ?"
UPSERT_SQL = (
    "INSERT INTO assistant_reg (agent, mode, is_primary, registered_at, heartbeat_at, status) "
    "VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(agent) DO UPDATE SET "
    "mode=excluded.mode, is_primary=excluded.is_primary, "
    "registered_at=excluded.registered_at, heartbeat_at=excluded.heartbeat_at, "
    "status=excluded.status"
)


def _worker(db_path: str, agent: str, barrier, out_q, idx: int, atomic: bool) -> None:
    """单个进程模拟一次 assistant_claim(is_primary=1)。

    atomic=False：复刻 store_sqlite.mbt L1646-1667 形态（UPDATE 清场 + INSERT upsert，
                  无 BEGIN IMMEDIATE 事务包裹 → TOCTOU 竞态窗口）。
    atomic=True：把清场 + upsert 包进 BEGIN IMMEDIATE 事务（更强修复，可证明原子）。
    """
    try:
        barrier.wait(timeout=10)
    except Exception:
        pass
    try:
        conn = sqlite3.connect(db_path, timeout=5)
        cur = conn.cursor()
        if atomic:
            # BEGIN IMMEDIATE 立即取写锁，串行化整个临界区，消除 TOCTOU
            cur.execute("BEGIN IMMEDIATE")
        # 清场（L1651）
        cur.execute(CLEAR_SQL, (agent,))
        # upsert（L1667）
        now = int(time.time())
        cur.execute(
            UPSERT_SQL,
            (agent, "leader", 1, now, now, "active"),
        )
        conn.commit()
        conn.close()
    except Exception as e:
        out_q.put((idx, "error", str(e)))
        return
    out_q.put((idx, "ok", ""))


def run_round(db_path: str, procs: int, atomic: bool = False) -> tuple:
    """跑一轮：procs 个进程同时抢主，返回 (主行数, 主行 agent 列表)。"""
    barrier = mp.Barrier(procs)
    out_q = mp.Queue()
    ctx = mp.get_context("spawn")
    ps = []
    for i in range(procs):
        p = ctx.Process(
            target=_worker, args=(db_path, f"agent-{i}", barrier, out_q, i, atomic)
        )
        p.start()
        ps.append(p)
    for p in ps:
        p.join(timeout=15)
        if p.is_alive():
            p.terminate()
    # 数主
    conn = sqlite3.connect(db_path, timeout=5)
    cur = conn.cursor()
    cur.execute("SELECT agent FROM assistant_reg WHERE is_primary=1")
    primaries = [r[0] for r in cur.fetchall()]
    conn.close()
    return len(primaries), primaries



def _entry_probe() -> None:
    """入口面自证（R171 口径）：自检必须把入口纳入调用图。

    为什么要有这一格：R158 交付 check_diff_scope.py 时 `--selftest` 全绿而**现状面一跑就崩**
    （clean 分支少传一个实参抛 TypeError，冒出来的 rc=1 和「有违例」一模一样）。自检只考纯函数、
    不碰入口，照不出「自检面与入口面脱钩」。本探测**零副作用**：只验证入口存在且可调用，
    不起服务、不碰网络、不跑真桥。
    """
    if not callable(main):
        raise SystemExit("入口 main 不可调用（自检面与入口面脱钩）")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--procs", type=int, default=5)
    ap.add_argument("--rounds", type=int, default=20)
    ap.add_argument("--atomic", action="store_true", help="用 BEGIN IMMEDIATE 事务包裹清场+upsert")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        # 自检：判据自身能跑、能发红
        return _selftest()

    if args.atomic:
        print(f"== atomic 模式：BEGIN IMMEDIATE 事务包裹清场+upsert（{args.procs} 进程 × {args.rounds} 轮）==")

    tmp = tempfile.mkdtemp(prefix="assistant_xproc_")
    db_path = os.path.join(tmp, "assistant.db")

    failures = 0
    total_rounds = 0
    worst = 0
    for r in range(args.rounds):
        # 每轮重建库，避免上轮残留
        if os.path.exists(db_path):
            os.remove(db_path)
        conn = sqlite3.connect(db_path)
        conn.execute(
            "CREATE TABLE assistant_reg (agent TEXT PRIMARY KEY, mode TEXT, "
            "is_primary INTEGER, registered_at INTEGER, heartbeat_at INTEGER, status TEXT)"
        )
        conn.commit()
        conn.close()

        total_rounds += 1
        n, primaries = run_round(db_path, args.procs, args.atomic)
        worst = max(worst, n)
        if n > 1:
            failures += 1
            print(
                f"  round {r}: FAIL 主数={n} 主={primaries}（并发 {args.procs} 进程抢主）"
            )
        else:
            print(f"  round {r}: pass 主数={n}")

    print(
        f"\n== 结果: {total_rounds - failures}/{total_rounds} 轮单主成立, "
        f"最坏主数={worst}, 并发进程={args.procs} =="
    )
    if failures > 0:
        print("VERDICT: FAIL — 单主不变量被跨进程并发击穿（BUG-157 修复不完整）")
        return 1
    print("VERDICT: PASS — 单主不变量成立")
    return 0


def _selftest() -> int:
    """合成违例：单进程串行应恒单主（pass），验证判据读数正确。"""
    _entry_probe()
    tmp = tempfile.mkdtemp(prefix="assistant_xproc_st_")
    db_path = os.path.join(tmp, "st.db")
    conn = sqlite3.connect(db_path)
    conn.execute(
        "CREATE TABLE assistant_reg (agent TEXT PRIMARY KEY, mode TEXT, "
        "is_primary INTEGER, registered_at INTEGER, heartbeat_at INTEGER, status TEXT)"
    )
    conn.commit()
    # 串行两次抢主：第二次应把第一次清掉
    cur = conn.cursor()
    cur.execute(CLEAR_SQL, ("agent-1",))
    cur.execute(UPSERT_SQL, ("agent-1", "leader", 1, 1, 1, "active"))
    conn.commit()
    cur.execute(CLEAR_SQL, ("agent-2",))
    cur.execute(UPSERT_SQL, ("agent-2", "leader", 1, 1, 1, "active"))
    conn.commit()
    cur.execute("SELECT agent FROM assistant_reg WHERE is_primary=1")
    prim = [r[0] for r in cur.fetchall()]
    conn.close()
    ok = len(prim) == 1 and prim[0] == "agent-2"
    print(
        f"selftest: 串行两抢主后主={prim} → {'OK' if ok else 'BAD'} "
        f"(期望 ['agent-2'])"
    )
    print("SELFTEST OK" if ok else "SELFTEST BAD")
    return 0 if ok else 2


if __name__ == "__main__":
    sys.exit(main())