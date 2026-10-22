#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""scripts/check_backlog_status_staleness.py — 「任务池状态 ↔ 主线盖章证据」对表判据（R102）。

为什么要有这把尺（实测驱动，2026-10-22）：`docs/tasks/backlog/TASK-*.yaml` 是主机派给副机的任务池真源，
每份带 `id:` / `status:`。副机与 AtomCode 把活干完并合入主线之后，**commit subject 里点名了 TASK-0NN，
而 yaml 的 `status` 还停在 `backlog`**。本轮实测到 4 条这种落差（TASK-001 / TASK-005 / TASK-006 / TASK-009）。
后果不是不好看：状态是 `backlog` 意味着下一轮巡检（`fist-gate.py --scan`、`whisperer.py`）还会把这单当未做
再派一次，而它已经在线上了——重复派单正是本仓反复抓的那类「账面说没做、线上说做完了」（与 `bug_list`
的 `open_with_linked_done` 同形，只是发生在任务池面而非缺陷账本面）。

判据三条（窄口径，刻意保守）：
  R1 STALE   主线 commit subject 点名该 id，而 yaml `status` 仍是 `backlog` ⇒ 状态落后于事实。
  R2 虚报    `status: done` 但主线没有任何点名该 id 的 commit ⇒ 「done」无据（终态必须有据）。
  R3 OPEN    从未被点名且 `status: backlog` ⇒ **只报不判**（这一单确实还没做，是正常的）。
判定面 = R1 条数 + R2 条数，**棘轮只许下降**（`STALE_CEILING`）：超出即红（rc=1）；低于上限只打印
收紧建议、**不判红也不自动改数**（放宽是人的决定，与 `check_plan_landing` P6 / `check_deprecated_text_census`
R3 同一口径）。

扫描面：优先 `gitcode/main`，其次 `git/main`，都取不到才退回 HEAD——本地在任何副机分支上、CI 在 main 的
checkout 上，读到的必须是**同一条线**，否则基线数字会随分支漂（本轮就实测到过：副机分支上 TASK-004 未点名
= 4 条，main 上已盖章 = 少一条）。`--rev <rev>` 可显式指定。

用法：
  python scripts/check_backlog_status_staleness.py                # 对表并出数（裸跑即可进电池）
  python scripts/check_backlog_status_staleness.py --selftest     # 尺子先证明自己会红
  python scripts/check_backlog_status_staleness.py --rev HEAD --show-open

退出码：0=判定面未超上限（含棘轮收紧提示）/ 1=超出上限（逐条点名）/ 2=判据无法自证（backlog 目录读不到、
一份 yaml 都解析不出、git 取不到＝什么都没测到，空扫描必自拒不冒用 1）/ 4=尺子自己坏了（未捕获异常）。
"""
import os
import re
import subprocess
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

BACKLOG_DIR = os.path.join("docs", "tasks", "backlog")
# 2026-10-22 在 `gitcode/main` 面实测：R1 = TASK-001 / TASK-005 / TASK-006 / TASK-009 四条（各自点名 commit
# 逐条印在读数里），R2 = 0 条（TASK-007 的 done 有 `chore(tasks): TASK-007 -> done` 为据）。
# 这 4 条是**存量落差**，等 owner 盖章就自然下降；新增一条就红。
STALE_CEILING = 4
UNSTAMPED = ("backlog",)


def parse_yaml(text):
    """从一份 backlog yaml 里取机械可证的三件：id / status / priority。取不到 id 返回 None（这份不算数）。"""
    tid = re.search(r"^id:\s*(TASK-\d+)\s*$", text, re.M)
    if not tid:
        return None
    st = re.search(r"^status:\s*([A-Za-z_]\w*)\s*$", text, re.M)
    pr = re.search(r"^priority:\s*(\S+)\s*$", text, re.M)
    return {
        "id": tid.group(1),
        "status": st.group(1) if st else "",
        "priority": pr.group(1) if pr else "",
    }


def citations(subjects):
    """commit subject 清单 -> {TASK-0NN: 首个点名它的 subject}。只认 subject，不认正文（盖章就在 subject 上）。"""
    out = {}
    for s in subjects:
        for m in re.findall(r"TASK-\d+", s):
            out.setdefault(m, s)
    return out


def judge(tasks, cited, ceiling=STALE_CEILING, rules=("R1", "R2")):
    """纯函数：任务面 + 点名面 -> (判定清单, 收紧建议清单, 正常清单)。空清单 = 判定面未超上限。"""
    verdicts, clean = [], []
    stale = [t["id"] for t in tasks if t["id"] in cited and t["status"] in UNSTAMPED]
    unfixed = [t["id"] for t in tasks if t["status"] == "done" and t["id"] not in cited]
    if "R1" in rules:
        for tid in stale:
            verdicts.append("STALE %s status=backlog 已被主线点名 -> 应转 in_review/done :: %s" % (tid, cited[tid][:70]))
    if "R2" in rules:
        for tid in unfixed:
            verdicts.append("UNPROVEN-DONE %s status=done 但主线无任何点名该 id 的 commit" % tid)
    n = len(verdicts)
    if n > ceiling:
        return verdicts, [], clean + ["判定面 %d 条 > 上限 %d ⇒ 超 %d 条" % (n, ceiling, n - ceiling)]
    over = []
    if n < ceiling:
        over.append("RATCHET 判定面 %d 条 < 上限 %d ⇒ 存量被盖章了，请把 STALE_CEILING 降到 %d（人不改数、尺不自动改）" % (n, ceiling, n))
    return [], over, clean


def synth_tasks(rows):
    return [{"id": i, "status": s, "priority": "P0"} for (i, s) in rows]


def selftest():
    fails = []

    def cell(name, ok):
        if ok:
            print("  OK   %s" % name)
        else:
            print("  FAIL %s" % name)
            fails.append(name)

    cited = {"TASK-001": "feat(merge): TASK-001 前置门", "TASK-007": "chore(tasks): TASK-007 -> done"}
    # 1) R1 违例必红
    v, _, _ = judge(synth_tasks([("TASK-001", "backlog")]), cited, ceiling=0)
    cell("violation-stale-status-is-named", len(v) == 1 and v[0].startswith("STALE TASK-001"))
    # 2) R2 违例必红
    v, _, _ = judge(synth_tasks([("TASK-009", "done")]), {}, ceiling=0)
    cell("violation-unproven-done-is-named", len(v) == 1 and v[0].startswith("UNPROVEN-DONE TASK-009"))
    # 3) 超限必红（同一批存量在上限内不红、上限降一格就红）
    rows = [("TASK-00%d" % i, "backlog") for i in (1, 2, 3, 4)]
    c2 = {("TASK-00%d" % i): "cited" for i in (1, 2, 3, 4)}
    v4, _, _ = judge(synth_tasks(rows), c2, ceiling=4)
    v5, _, _ = judge(synth_tasks(rows), c2, ceiling=3)
    cell("violation-ceiling-exceeded-turns-red", v4 == [] and len(v5) == 4)
    # 4-6) 反向对照：合法态不许误红
    v, _, _ = judge(synth_tasks([("TASK-001", "in_review")]), cited, ceiling=9)
    cell("reverse-stamped-in_review-not-red", v == [])
    v, _, _ = judge(synth_tasks([("TASK-007", "done")]), cited, ceiling=9)
    cell("reverse-proven-done-not-red", v == [])
    v, _, _ = judge(synth_tasks([("TASK-003", "backlog")]), {}, ceiling=9)
    cell("reverse-never-cited-backlog-is-open-not-red", v == [])
    # 收紧建议那一格：低于上限只提示、不入判定面
    v, over, _ = judge(synth_tasks([("TASK-001", "backlog")]), cited, ceiling=4)
    cell("reverse-under-ceiling-prints-tightening-only", v == [] and len(over) == 1)
    # 7-8) 规则失明对照：摘掉承重规则，同一份违例必须变成「看不见」
    v, _, _ = judge(synth_tasks([("TASK-001", "backlog")]), cited, ceiling=0, rules=("R2",))
    cell("mutation-rule-blind-R1", v == [])
    v, _, _ = judge(synth_tasks([("TASK-009", "done")]), {}, ceiling=0, rules=("R1",))
    cell("mutation-rule-blind-R2", v == [])
    # 解析面自证：非可解析形状必须判「不算数」，否则空文件会被读成 status 空串而悄悄进判定
    cell("parser-rejects-yaml-without-id", parse_yaml("title: x\nstatus: backlog\n") is None)
    cell("parser-reads-id-status-priority", parse_yaml("id: TASK-042\npriority: P1\nstatus: backlog\n")
         == {"id": "TASK-042", "status": "backlog", "priority": "P1"})
    return fails, 11


def fatal(msg):
    """判据无法自证 -> **真给 2**（写 stderr，由 `sys.exit(main())` 落成）。
    刻意不用 `raise SystemExit("串")`——带字符串的 SystemExit 实给 1（BUG-369 抓的幻影）。"""
    sys.stderr.write("FATAL: %s\n" % msg)
    return 2


def resolve_rev(explicit):
    if explicit:
        return explicit, 0
    for cand in ("gitcode/main", "git/main", "HEAD"):
        r = subprocess.run(["git", "rev-parse", "--verify", "-q", cand], capture_output=True)
        if r.returncode == 0:
            return cand, 0
    return None, 2


def main(argv):
    args = list(argv)
    if "--selftest" in args:
        fails, n = selftest()
        if fails:
            print("SELFTEST FAIL: %d/%d 格红 -> %s" % (len(fails), n, ",".join(fails)))
            return 1
        print("SELFTEST OK: %d 格（合成违例必红 3 + 反向对照不误红 4 + 规则失明对照 2 + 解析面自证 2）" % n)
        return 0

    show_open = "--show-open" in args
    rev = None
    if "--rev" in args:
        i = args.index("--rev")
        if i + 1 >= len(args):
            return fatal("--rev 后面没给修订")
        rev = args[i + 1]
    rev, rc = resolve_rev(rev)
    if rc != 0:
        return fatal("git 面取不到（gitcode/main / git/main / HEAD 都解析不了），无基线可对比")

    backlog = os.environ.get("FIST_BACKLOG_DIR", BACKLOG_DIR)
    if not os.path.isdir(backlog):
        return fatal("backlog 目录不存在：%s" % backlog)
    tasks = []
    for fn in sorted(os.listdir(backlog)):
        if not fn.endswith(".yaml"):
            continue
        rec = parse_yaml(open(os.path.join(backlog, fn), encoding="utf-8", errors="replace").read())
        if rec:
            tasks.append(rec)
    if not tasks:
        return fatal("%s 里一份可解析的 TASK-*.yaml 都没有，判据空转不报绿" % backlog)

    logres = subprocess.run(["git", "log", "--format=%s", rev], capture_output=True, text=True,
                            encoding="utf-8", errors="replace")
    if logres.returncode != 0:
        return fatal("`git log %s` 取不到 subject" % rev)
    subjects = logres.stdout.splitlines()
    if not subjects:
        return fatal("%s 一条 commit 都没有，点名面无从谈起" % rev)

    cited = citations(subjects)
    verdicts, tighten, _ = judge(tasks, cited)
    bad = ([t["id"] for t in tasks if t["id"] in cited and t["status"] in UNSTAMPED]
           + [t["id"] for t in tasks if t["status"] == "done" and t["id"] not in cited])
    over = max(0, len(bad) - STALE_CEILING)
    print("扫描面=%s | backlog %d 份 | 主线点名到的 TASK id %d 个 | 落差 %d 条 / 上限 %d 条 / 超限 %d 条"
          % (rev, len(tasks), len(cited), len(bad), STALE_CEILING, over))
    if show_open:
        for t in tasks:
            mark = "STALE" if (t["id"] in cited and t["status"] in UNSTAMPED) else (
                "DONE?" if t["status"] == "done" else "OPEN")
            print("  %-8s %-9s %-4s %s" % (mark, t["id"], t["priority"], t["status"]))
    for line in tighten:
        print(line)
    for t in tasks:
        if t["id"] in cited and t["status"] in UNSTAMPED:
            print("  落差 STALE %s status=backlog :: %s" % (t["id"], cited[t["id"]][:70]))
    for t in tasks:
        if t["status"] == "done" and t["id"] not in cited:
            print("  落差 UNPROVEN-DONE %s status=done 但主线无点名该 id 的 commit" % t["id"])
    if over:
        for line in verdicts:
            print(line)
        print("BACKLOG_STALENESS=exceed 落差 %d 条 > 上限 %d ⇒ 超 %d 条（判定面只许下降）"
              % (len(bad), STALE_CEILING, over))
        return 1
    print("BACKLOG_STALENESS=within 落差 %d 条 <= 上限 %d（存量等 owner 盖章即下降；新增一条就红）"
          % (len(bad), STALE_CEILING))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as e:  # noqa: BLE001 — 尺子自己坏了 -> 真给 4，绝不冒用 1（判据红）
        sys.stderr.write("RULER BROKEN: %r\n" % e)
        sys.exit(4)
