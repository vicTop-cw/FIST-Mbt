#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_plan_location.py —— 计划/提案库 frontmatter + 归档位置守卫（BUG-440 + 提案面扩）。

## 覆盖面：**两面同判，一次运行**

| 面 | 目录 | 判什么 |
|---|---|---|
| plans | `docs/plans/`（只本层，`decisions/`、`archived/` 不进判定面） | P1 文件名 + P2 frontmatter 位置 + P3 四强制字段 + P4 `status` 闭集 + P5 `已定案` 自洽 |
| proposals | `docs/proposals/`（只本层） | P1 文件名 + P8 frontmatter 可解析 + P9 `status` 键与闭集 |
| 两面共用 | —— | **P6 告警**（推迟/完成仍留活动目录）/ **P7 判红**（驳回/归档仍留活动目录） |

两面各扫自己一层；`README.md` 与 `TEMPLATE.md` 按名跳过（前者是说明、后者是模板，都不是提案实例），
跳过项**在输出里点名条数**，不静默消失。

**为什么 proposals 面要并进来**（本守卫扩面前的实测）：`docs/proposals/` 两份提案
（`2026-10-22-cross-machine-task-publish-proposal.md`、`2026-10-22-folder-watch-trigger-proposal.md`）
第一行是 `#` 标题、**没有任何 YAML frontmatter**，状态只写在引用行里 ⇒ 旧版只 glob `docs/plans/` 的守卫
**一份都没枚举到它们**，「提案等定案」这件事完全在治理面外。`docs/proposal-process.md` §2 写了提案的
放置与归档纪律，但没有任何尺子读过那两张卡。

**为什么 P7 判红而 P6 只告警**（口径刻意窄，可回退）：
`docs/plans/README.md:45` 早就写着「`plans/archived/` | 已完成/已驳回/已推迟的终态计划」，但
`docs/plans/archived/` **目录此前不存在** —— 承诺的归档位没有，警告自然永远只能停留在警告。
本轮补目录 + 把「**驳回/归档**」这一档从告警提成判红（被驳回的东西留在活动目录＝把已关的议题当在办）。
**推迟 / 完成两档继续只告警**：现网 `2026-10-26-4pools-rhop-roadmap-proposal.md` 是 `已推迟`，
把它一并判红等于用新尺子打一个已有文件（红在落地那一刻，而不是红在违例那一刻，两者都让人不去读规则本身）。

## 判据细节

- **P1 文件名**：两面文档（除 `README.md`/`TEMPLATE.md`）必须形如 `YYYY-MM-DD-<topic>.md`。
  proposals 侧的出处是 `docs/proposal-process.md` §2「目录：`docs/proposals/YYYY-MM-DD-<主题>-proposal.md`」。
- **P2 / P8 frontmatter 必须从第 1 行起且闭合**：行 1 必须恰为 `---`（容忍行尾 `\r`）。
  ⇒ **AIGC 水印块若占第 1 行，判红**（它就是 BUG-440 的真实违例形状）。
- **P3 四字段齐全（plans）**：`status` / `decided_by` / `decided_at` / `decision` 的**键名**必须出现
  （值可空 —— `提案中` 的提案 `decided_by:` 为空是合法的）。
  **这是本判据唯一容易写错的地方**：判「键必须出现」而不是「值必须非空」，才不会把合法提案判红。
- **P9（proposals）只强制 `status` 一键**：proposals 是「议题排队面」，定案前本就没有 decided_* 三件套。
- **P4 / P9 值闭集**：plans 用 `STATUS_CLOSED`（中文，出处 `docs/plans/README.md:25`）；
  proposals 用 `PROPOSAL_STATUS_CLOSED`（英文，出处 `docs/proposals/TEMPLATE.md` 的状态行，
  本轮补入 `rejected`/`deferred` 两值 —— P7 要能判「被驳回的提案留在活动目录」，词表里就必须有这一档）。
  **两侧词表不并集**：并了就会让 plans 侧写 `status: draft` 混过 P4，等于把 P4 判松。
- **P5 `已定案` 的自洽**（plans）：`decided_by` 必须 == `human_steward`；`decided_at` 非空；
  `decision` ∈ `{approved, rejected, deferred}`；且 `decisions/` 下必须有同一日期前缀的记录。
- **P6 告警**：`status` ∈ `TERMINAL_WARN`（`已推迟`/`已完成`/`deferred`）仍在活动目录 ⇒ 只告警。
- **P7 判红**：`status` ∈ `LIVE_FORBIDDEN`（`已驳回`/`已归档`/`rejected`/`archived`）仍在活动目录 ⇒ 违例。
  P6/P7 由同一个纯函数 `terminal_rule()` 算，两面共用一张表（同一规则两份实现就是下一颗漂移雷）。

出处对表（本轮逐条读回树里核过，不是抄巡检报告）：
- plans 侧四字段与中文 status 闭集 = `docs/plans/README.md:22`/`:25`；
  归档位 = `docs/plans/README.md:45`「`plans/archived/` | 已完成/已驳回/已推迟的终态计划」
  —— **本轮之前该目录并不存在**（`ls docs/plans/archived` → No such file），承诺的归档位没有，
  于是 P6 的警告永远只能停留在警告；本轮补目录并把「驳回/归档」提为判红。
- proposals 侧文件名与放置 = `docs/proposal-process.md` §1.2「目录：
  `docs/proposals/YYYY-MM-DD-<主题>-proposal.md`」；归档去向 = 同文 §0 阶段 5 与 §「决策即锁定」
  「决策写入后，proposals/ 里对应提案移 `docs/archive/`」。

## 防空转（「空宇宙骗人」——本仓被烧过多次，这一节是硬要求）

以下四种情况一律 `rc=2` 并打印原因，**绝不因「没找到」报绿**：

1. 任一面目录不存在；
2. 任一面本层枚举到 0 份文档（另一面再干净也不顶）；
3. 两面合计**一个 `status:` 都解析不出来**（文档全是非法 frontmatter ⇒ 尺子没东西可读，
   这时逐条 P2/P8 违例只作为证据打印，结论仍是「拒绝出读数」）；
4. 只给 `--plans-dir` 或只给 `--proposals-dir` 单边覆盖 —— 另一面会照读真仓，读数混宇宙、
   selftest 也不再 hermetic ⇒ 直接自拒（两旗必须同给）。

## rc 契约（与 `check_fmt_gate.py` / `check_two_faces.py` 同口径，不新造）

- `0` 全部合规（告警不改变退出码）
- `1` 有违例（**逐条点名**）
- `2` 判据无法自证（上面四条空转之一）——**参数面也是 2**：本文件用 `argparse`，
  未知旗标由 argparse 直接给 rc=2（R207 的失效形态是「`--selftest` 拼错 ⇒ 静默落进真检查分支」，
  argparse 天生拒绝，selftest 里另有一格 `arg-unknown-flag-rc2` 锁这个行为面）

用法：
    python scripts/check_plan_location.py                      # 判据模式（两面）
    python scripts/check_plan_location.py --selftest           # 自证（合成夹具，含变异对照）
    python scripts/check_plan_location.py --plans-dir <dir> --proposals-dir <dir>
"""

from __future__ import annotations

import argparse
import os
import re
import sys

try:  # Windows cp936 控制台：不 reconfigure 会因 ✓/✗ 抛 UnicodeEncodeError
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLANS = os.path.join(ROOT, "docs", "plans")
PROPOSALS = os.path.join(ROOT, "docs", "proposals")

RC_OK, RC_VIOLATION, RC_BROKEN = 0, 1, 2

STATUS_CLOSED = {"提案中", "已定案", "已驳回", "已推迟", "已完成"}
PROPOSAL_STATUS_CLOSED = {"draft", "under-review", "approved", "rejected", "deferred", "archived"}
DECISION_CLOSED = {"approved", "rejected", "deferred"}

# P7（判红）：被驳回/已归档的卡片不许停在活动目录 —— 两张表都判红，词表两侧（中/英）都覆盖。
LIVE_FORBIDDEN = {"已驳回", "已归档", "rejected", "archived"}
# P6（只告警）：推迟/完成。现网有 `已推迟` 的活卡片（4pools），一并判红就是打已有文件 ⇒ 留告警。
TERMINAL_WARN = {"已推迟", "已完成", "deferred"}

REQUIRED_KEYS = ("status", "decided_by", "decided_at", "decision")
PROPOSAL_KEYS = ("status",)
# 说明/模板不是提案实例：plans 侧 README.md，proposals 侧 README.md + TEMPLATE.md。跳过项**出数点名**。
SKIP_NAMES = ("README.md", "TEMPLATE.md")
NAME_RX = re.compile(r"^\d{4}-\d{2}-\d{2}-.+\.md$")


def _face(name, prefix, fm_code, key_code, val_code, required_keys, status_closed,
          decided_check, remedy):
    """一面（一个目录 + 它自己的规则码与词表）。规则码不同是刻意的：`[P3]` 与 `[P9]` 在输出里
    就能看出是哪一面红的，不必读目录名。"""
    return {
        "name": name, "prefix": prefix, "fm": fm_code, "key": key_code, "val": val_code,
        "required": required_keys, "closed": status_closed, "decided": decided_check,
        "remedy": remedy, "label": "计划文档" if name == "plans" else "提案文档",
    }


FACES = {
    "plans": _face("plans", "docs/plans/", "P2", "P3", "P4", REQUIRED_KEYS, STATUS_CLOSED,
                   True, "docs/plans/archived/"),
    "proposals": _face("proposals", "docs/proposals/", "P8", "P9", "P9", PROPOSAL_KEYS,
                       PROPOSAL_STATUS_CLOSED, False,
                       "docs/archive/（见 docs/proposal-process.md §归档）"),
}


def read(p: str) -> str:
    # newline="" 保留 CRLF：本仓的提案/计划卡全是 CRLF，读时不能悄悄归一化后再判（判例-21 同族）
    with open(p, encoding="utf-8", errors="replace", newline="") as fh:
        return fh.read()


def rel(path: str) -> str:
    """相对仓库根；跨盘（tempfile 在 C:、仓库在 E:）时退回绝对路径，不许抛。"""
    try:
        return os.path.relpath(path, ROOT).replace("\\", "/")
    except ValueError:
        return path.replace("\\", "/")


def norm_line(ln: str) -> str:
    return ln.rstrip("\r\n")


def parse_frontmatter(text: str):
    """返回 (ok, kv, reason)。

    ok=False 的 reason 直说「第 1 行不是 ---」或「没有闭合 ---」——
    这正是 AIGC 水印块被误当 frontmatter、以及 proposals 那两份卡「只有引用行没有头部」的形状。
    """
    lines = text.split("\n")
    if not lines:
        return False, {}, "空文件"
    if norm_line(lines[0]).strip() != "---":
        first = norm_line(lines[0])[:40]
        return False, {}, "第 1 行不是 `---`（实际：%r）" % first
    kv = {}
    for i in range(1, len(lines)):
        ln = norm_line(lines[i])
        if ln.strip() == "---":
            return True, kv, ""
        if ":" in ln and not ln.lstrip().startswith("-"):
            k, _, v = ln.partition(":")
            kv.setdefault(k.strip(), v.strip())
    return False, {}, "frontmatter 没有闭合的 `---`"


def terminal_rule(status, live_forbidden=LIVE_FORBIDDEN, terminal_warn=TERMINAL_WARN):
    """终态 ↔ 位置 的**唯一**判法（纯函数，两面共用）。返回 "forbidden"（判红）/"warn"（告警）/None。

    两个集合都是**形参**（默认取模块常量）：selftest 的变异对照靠注入空集合来证明「这两张表就是
    判据真正读的那把 key」，而不是靠改注释（判例-29/30）。"""
    if not status:
        return None
    if status in live_forbidden:
        return "forbidden"
    if status in terminal_warn:
        return "warn"
    return None


def check_one(path: str, shown: str, decisions: list, face: dict,
              live_forbidden=LIVE_FORBIDDEN, terminal_warn=TERMINAL_WARN):
    """单份文档。返回 (违例, 告警, 解析出的 status 值或 None)；违例/告警都是 (shown, code, msg)。"""
    v, w = [], []
    base = os.path.basename(path)

    if not NAME_RX.match(base):
        v.append((shown, "P1", "文件名不符合 `YYYY-MM-DD-<topic>.md`"))

    text = read(path)
    ok, kv, why = parse_frontmatter(text)
    if not ok:
        v.append((shown, face["fm"], "frontmatter 非法：" + why))
        return v, w, None          # 后面全依赖 kv，没法继续判

    for k in face["required"]:
        if k not in kv:
            v.append((shown, face["key"], "缺强制字段 `%s`" % k))

    st = kv.get("status", "")
    if st and st not in face["closed"]:
        v.append((shown, face["val"],
                  "`status` 值 %r 不在 %s 面闭集 %s" % (st, face["name"], sorted(face["closed"]))))

    if st == "已定案" and face["decided"]:
        if kv.get("decided_by", "") != "human_steward":
            v.append((shown, "P5", "`已定案` 但 `decided_by` != human_steward（实际 %r）"
                      % kv.get("decided_by", "")))
        if not kv.get("decided_at", ""):
            v.append((shown, "P5", "`已定案` 但 `decided_at` 为空"))
        dec = kv.get("decision", "")
        if dec not in DECISION_CLOSED:
            v.append((shown, "P5", "`已定案` 但 `decision` %r 不在 %s"
                      % (dec, sorted(DECISION_CLOSED))))
        date = base[:10]
        if not any(date in d for d in decisions):
            v.append((shown, "P5", "`已定案` 但 `decisions/` 下无 %s 前缀的记录" % date))

    disp = terminal_rule(st, live_forbidden, terminal_warn)
    if disp == "forbidden":
        v.append((shown, "P7", "`status=%s` 是被驳回/已归档的终态，不得留在活动目录 ⇒ 移入 %s"
                  % (st, face["remedy"])))
    elif disp == "warn":
        w.append((shown, "P6", "`status=%s` 是终态，仍留在活动目录（建议移入 %s；本轮只告警不判红）"
                  % (st, face["remedy"])))

    return v, w, (st or None)


def enumerate_docs(d: str, skip_names=SKIP_NAMES):
    """本层 `*.md` 枚举（纯函数，两面共用）。返回 (文档清单, 跳过清单, 自拒原因)。

    **只收本层文件**：`decisions/`（记录面）与 `archived/`（墓地）不进判定面 —— 这正是 P7 的出路：
    卡片移进 `archived/` 就离开活动目录，而不是靠给它开一张暗豁免。"""
    if not os.path.isdir(d):
        return [], [], "`%s` 不存在（该面无法扫描）" % rel(d)
    files, skipped = [], []
    for f in sorted(os.listdir(d)):
        if not f.endswith(".md"):
            continue
        p = os.path.join(d, f)
        if not os.path.isfile(p):
            continue
        if f in skip_names:
            skipped.append(f)
            continue
        files.append((p, f))
    if not files:
        return [], skipped, ("`%s` 下一份文档都没扫到（枚举面为空 ⇒ 拒绝出结论；"
                             "跳过项见本行之后）" % rel(d))
    return files, skipped, ""


def scan(d: str, face: dict, live_forbidden=LIVE_FORBIDDEN, terminal_warn=TERMINAL_WARN):
    """一面扫描。返回 (files, skipped, violations, warns, n_status_parsed, broken_reason)。"""
    files, skipped, broken = enumerate_docs(d)
    if broken:
        return [], skipped, [], [], 0, broken

    decisions = []
    if face["decided"]:
        ddir = os.path.join(d, "decisions")
        if os.path.isdir(ddir):
            decisions = os.listdir(ddir)

    violations, warns, n_status = [], [], 0
    for p, f in files:
        v, w, st = check_one(p, face["prefix"] + f, decisions, face,
                             live_forbidden, terminal_warn)
        violations += v
        warns += w
        if st:
            n_status += 1
    return files, skipped, violations, warns, n_status, ""


def scan_pair(plans_dir: str, proposals_dir: str):
    """「目录对」互锁判据（纯函数）：两面必须**成对**给出。

    只给一面 ⇒ 另一面照读真仓：`--selftest` 会因此不再 hermetic，真跑的读数也会把合成宇宙与
    现状宇宙混在一起打印。自拒（rc=2 那一档），不猜人意图。"""
    if plans_dir and proposals_dir:
        return ""
    if plans_dir or proposals_dir:
        return ("只给了一面覆盖（--plans-dir=%r / --proposals-dir=%r）⇒ 另一面会照读真仓 docs/，"
                "读数混宇宙、selftest 也不再 hermetic。两面必须成对给。"
                % (plans_dir, proposals_dir))
    return ""


def status_census(n_docs, n_status):
    """空宇宙判据（纯函数）：枚举到文档、但一个**非空 `status:` 值**都没解析出来 ⇒ 尺子没东西可读。

    两种形状都会走到这里：头部整个非法（proposals 扩面前那两份卡），或头部能解析但**没有 status 键**
    （AIGC 水印块 —— 键名对不上，值也读不出）。这种情况**不能**读成「P2/P3/P8 违例清单 ⇒ rc=1」就完事：
    那会让下一位把「尺子读不到状态面」当成「状态面有问题」，而真问题可能是头部形状整个换了、
    守卫没跟上（BUG-440 同族）。"""
    if n_docs and not n_status:
        return ("枚举到 %d 份文档，但**一个 `status:` 都解析不出来** ⇒ 状态治理面是空宇宙，"
                "拒绝出结论（逐条 frontmatter 违例见下方证据）" % n_docs)
    return ""


def resolve_dirs(plans_arg: str, proposals_arg: str):
    """目录对解析（纯函数）。返回 (plans_dir, proposals_dir, 自拒原因)。"""
    both = bool(plans_arg) and bool(proposals_arg)
    if not plans_arg and not proposals_arg:
        return PLANS, PROPOSALS, ""
    if not both:
        return "", "", scan_pair(plans_arg, proposals_arg)
    return plans_arg, proposals_arg, ""


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--plans-dir", default="", help="覆盖 plans 面目录（须与 --proposals-dir 同给）")
    ap.add_argument("--proposals-dir", default="", help="覆盖 proposals 面目录（须与 --plans-dir 同给）")
    a = ap.parse_args(argv)

    if a.selftest:
        return selftest()

    plans_dir, proposals_dir, broken = resolve_dirs(a.plans_dir, a.proposals_dir)
    faces = ((FACES["plans"], plans_dir), (FACES["proposals"], proposals_dir))
    if broken:
        print("[FATAL] " + broken)
        print("判据无法自证 —— 拒绝出结论，也拒绝因「没找到」报绿。rc=2")
        return RC_BROKEN

    # 逐面收进**具名字典**而不是靠元组下标：`scan()` 的 6 元组里 files/skipped/violations/warns
    # 长得一模一样（都是 list），下标差一位就会把「跳过清单」当「违例清单」打印 ——
    # 这个形状本文件第一版真踩过（selftest 的 rc=1 变异格当场抓到，见格2~格5）。
    rows = []
    for face, d in faces:
        files, skipped, violations, warns, n_status, broken_reason = scan(d, face)
        rows.append({"face": face, "dir": d, "files": files, "skipped": skipped,
                     "violations": violations, "warns": warns,
                     "n_status": n_status, "broken": broken_reason})

    broken_reasons = [r["broken"] for r in rows if r["broken"]]
    if broken_reasons:
        for r in broken_reasons:
            print("[FATAL] " + r)
        print("判据无法自证 —— 拒绝出结论，也拒绝因「没找到」报绿。rc=2")
        return RC_BROKEN

    n_docs = sum(len(r["files"]) for r in rows)
    n_status = sum(r["n_status"] for r in rows)
    violations = [x for r in rows for x in r["violations"]]
    warns = [x for r in rows for x in r["warns"]]
    census = status_census(n_docs, n_status)
    if census:
        print("[FATAL] " + census)
        for _s, code, msg in violations:
            print("  证据 [%s] %s — %s" % (code, _s, msg))
        print("判据无法自证 —— 拒绝出结论，也拒绝因「没找到」报绿。rc=2")
        return RC_BROKEN

    for r in rows:
        face, skipped, ns = r["face"], r["skipped"], r["n_status"]
        tail = ""
        if skipped:
            tail = "（另按名跳过说明/模板 %d 份：%s）" % (len(skipped), " ".join(skipped))
        print("[扫描] %s 下 %d 份%s%s，其中 %d 份解析到 `status:`"
              % (rel(r["dir"]), len(r["files"]), face["label"], tail, ns))
        for _p, f in r["files"]:
            print("  · " + face["prefix"] + f)

    if warns:
        print("\n[告警] %d 条（不判红 —— 推迟/完成两档的归档由人决定）" % len(warns))
        for _s, code, msg in warns:
            print("  ! [%s] %s — %s" % (code, _s, msg))

    if violations:
        print("\n[违例] %d 条：" % len(violations))
        for _s, code, msg in violations:
            print("  ✗ [%s] %s — %s" % (code, _s, msg))
        print("\n[结论] 有违例（frontmatter 强制字段 / 文件名 / status 闭集 / 已定案自洽 / 终态位置）")
        return RC_VIOLATION

    print("\n[结论] 全部合规：两面 %d 份文档的文件名 / frontmatter / status 闭集 / "
          "已定案自洽 / 终态归档位置" % n_docs)
    return RC_OK


# ── selftest（判例-5 同族：必须给执行面；判例-29/30：必须有变异对照；
#    R153：合成夹具、不读现状面 —— 每一格都走 --plans-dir/--proposals-dir 成对覆盖） ──────
FM_OK = """---
status: 提案中
decided_by:
decided_at:
decision:
---
# 提案：x
"""

FM_DECIDED = """---
status: 已定案
decided_by: human_steward
decided_at: 2026-10-22
decision: approved
---
# 提案：y
"""

FM_AIGC = """---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ReservedCode1: pC4ZdXEB8Gbp9/szeM+c3IuLw0nsYhDYrF3drfnn6LiNR=
---
# 提案：z
"""

FM_MISSING_KEY = """---
status: 提案中
decided_by:
---
# 提案：w
"""

FM_BAD_STATUS = """---
status: 也许吧
decided_by:
decided_at:
decision:
---
# 提案：v
"""

# 终态三档（P6 告警 / P7 判红）——中文侧是 plans 面词表，英文侧是 proposals 面词表
FM_REJECTED = """---
status: 已驳回
decided_by: human_steward
decided_at: 2026-10-29
decision: rejected
---
# 提案：被驳回
"""

FM_DEFERRED = """---
status: 已推迟
decided_by: human_steward
decided_at: 2026-10-30
decision: deferred
---
# 提案：被推迟
"""

FM_DRAFT = """---
status: draft
---
# Proposal: draft
"""

FM_PROPOSAL_NO_FM = """# Proposal: 只有引用行写着「状态」，没有 YAML 头部

> **状态**：`draft`
"""

FM_PROPOSAL_REJECTED = """---
status: rejected
---
# Proposal: rejected
"""

FM_PROPOSAL_BAD_STATUS = """---
status: maybe
---
# Proposal: maybe
"""

FM_PROPOSAL_NO_STATUS = """---
title: 有头部但没有 status 键
---
# Proposal: no status
"""


def selftest() -> int:
    import contextlib
    import io
    import tempfile

    cells = []

    def cell(name, got, want):
        cells.append((name, got, want))
        print("  [%s] %-52s got=%r want=%r" % (
            "OK" if got == want else "FAIL", name, got, want))

    def mk(d, fname, content):
        p = os.path.join(d, fname)
        with open(p, "w", encoding="utf-8", newline="") as fh:
            fh.write(content)
        return p

    def run(plans_dir, proposals_dir):
        with contextlib.redirect_stdout(io.StringIO()) as buf:
            rc = main(["--plans-dir", plans_dir, "--proposals-dir", proposals_dir])
        return rc, buf.getvalue()

    def pair(base, tag, plans_docs=(("2026-10-22-ok-proposal.md", FM_OK),),
             props_events=(("2026-10-22-draft-proposal.md", FM_DRAFT),),
             decisions=(("2026-10-22-001-x.md", "ok\n"),)):
        """造一对合成面（plans + proposals），返回 (plans_dir, proposals_dir)。

        两面默认**各带一份合规文档**：单面违例格要能读出「红的就是那一面」，
        不能靠另一面空转（那会落进 rc=2 自拒、和 rc=1 混色）。"""
        pl = os.path.join(base, "plans-" + tag)
        pr = os.path.join(base, "proposals-" + tag)
        os.makedirs(pl)
        os.makedirs(pr)
        dd = os.path.join(pl, "decisions")
        os.makedirs(dd)
        for name, content in decisions:
            mk(dd, name, content)
        for name, content in plans_docs:
            mk(pl, name, content)
        for name, content in props_events:
            mk(pr, name, content)
        return pl, pr

    print("[selftest] 临时裸目录端到端（两面各自合成夹具，不碰真 docs/）")
    with tempfile.TemporaryDirectory() as td:
        # ── 格1：两面各一份合法 ⇒ rc=0 ──
        pl, pr = pair(td, "clean")
        rc, out = run(pl, pr)
        cell("valid-proposal-rc0", rc, RC_OK)

        # ── 格2（★变异对照1）：把四字段之一删掉 ⇒ 必须 rc=1 且点名 P3 ──
        pl, pr = pair(td, "misskey", plans_docs=(("2026-10-22-missing-key-proposal.md", FM_MISSING_KEY),))
        rc, out = run(pl, pr)
        cell("MUTATION-missing-key-rc1", rc, RC_VIOLATION)
        cell("MUTATION-missing-key-named", "[P3]" in out, True)

        # ── 格3（★变异对照2）：AIGC 水印块当 frontmatter ⇒ 必须 rc=1 且 P3 ──
        pl, pr = pair(td, "aigc", plans_docs=(("2026-10-26-aigc-proposal.md", FM_AIGC),))
        rc, out = run(pl, pr)
        cell("MUTATION-aigc-watermark-rc1", rc, RC_VIOLATION)
        cell("MUTATION-aigc-detected-P3", "[P3]" in out, True)

        # ── 格4：plans status 不在闭集 ⇒ rc=1 且 P4 ──
        pl, pr = pair(td, "badst", plans_docs=(("2026-10-26-bad-status-proposal.md", FM_BAD_STATUS),))
        rc, out = run(pl, pr)
        cell("bad-status-rc1", rc, RC_VIOLATION)
        cell("bad-status-code-P4", "[P4]" in out, True)

        # ── 格5：文件名不合规范 ⇒ rc=1 且 P1 ──
        pl, pr = pair(td, "badname", plans_docs=(("no-date-proposal.md", FM_OK),))
        rc, out = run(pl, pr)
        cell("bad-filename-rc1", rc, RC_VIOLATION)
        cell("bad-filename-code-P1", "[P1]" in out, True)

        # ── 格6：已定案 有 decisions 记录 ⇒ rc=0 ──
        pl, pr = pair(td, "decided", plans_docs=(("2026-10-22-decided-proposal.md", FM_DECIDED),))
        rc, out = run(pl, pr)
        cell("decided-with-record-rc0", rc, RC_OK)

        # ── 格7（★变异对照3）：删掉 decisions 记录 ⇒ 已定案必须 rc=1 且 P5 ──
        pl, pr = pair(td, "nodecision", plans_docs=(("2026-10-22-decided-proposal.md", FM_DECIDED),),
                      decisions=())
        rc, out = run(pl, pr)
        cell("MUTATION-decided-no-record-rc1", rc, RC_VIOLATION)
        cell("MUTATION-decided-no-record-P5", "[P5]" in out, True)

        # ── 格8：plans 面空枚举 ⇒ rc=2 自拒（proposals 面干净也不顶）──
        pl, pr = pair(td, "emptyplans", plans_docs=())
        rc, out = run(pl, pr)
        cell("empty-dir-self-reject-rc2", rc, RC_BROKEN)
        cell("empty-dir-says-FATAL", "[FATAL]" in out, True)

        # ── 格9：CRLF frontmatter 必须被正确解析（本仓卡片全是 CRLF）──
        pl, pr = pair(td, "crlf",
                      plans_docs=(("2026-10-22-crlf-proposal.md", FM_OK.replace("\n", "\r\n")),),
                      props_events=(("2026-10-22-draft-proposal.md", FM_DRAFT.replace("\n", "\r\n")),))
        rc, out = run(pl, pr)
        cell("crlf-frontmatter-rc0", rc, RC_OK)

        # ── 格10：README.md / TEMPLATE.md 必须被跳过（它们不是提案实例）──
        pl, pr = pair(td, "skip")
        mk(pl, "README.md", "# 说明\n不是 frontmatter\n")
        mk(pr, "TEMPLATE.md", "# 模板\n不是 frontmatter\n")
        mk(pr, "README.md", "# 说明\n不是 frontmatter\n")
        rc, out = run(pl, pr)
        cell("readme-skipped-rc0", rc, RC_OK)
        cell("skip-list-is-counted", "跳过说明/模板" in out, True)

        # ── 格11：P6 形状 —— `已推迟` 留在活动目录只告警、不判红（现网有这一档，判红=打已有文件）──
        pl, pr = pair(td, "deferred", plans_docs=(("2026-10-26-deferred-proposal.md", FM_DEFERRED),))
        rc, out = run(pl, pr)
        cell("deferred-in-live-warn-not-red", rc, RC_OK)
        cell("deferred-warn-says-P6", "[P6]" in out, True)

        # ── 格12（★变异对照4）：P7 形状 —— `已驳回` 留在活动目录必须判红 ──
        pl, pr = pair(td, "rejected-live",
                      plans_docs=(("2026-10-24-rejected-proposal.md", FM_REJECTED),))
        rc, out = run(pl, pr)
        cell("MUTATION-rejected-in-live-rc1", rc, RC_VIOLATION)
        cell("MUTATION-rejected-in-live-P7", "[P7]" in out, True)

        # ── 格13：同一份卡片放进 `archived/` 子目录 ⇒ 不许红（出路是搬家，不是暗豁免）──
        pl, pr = pair(td, "rejected-archived")
        os.makedirs(os.path.join(pl, "archived"))
        mk(os.path.join(pl, "archived"), "2026-10-24-rejected-proposal.md", FM_REJECTED)
        rc, out = run(pl, pr)
        cell("archived-rejected-not-red", rc, RC_OK)
        cell("archived-rejected-says-no-P7", "[P7]" in out, False)

        # ── 格14（★变异对照5·代码面）：把 LIVE_FORBIDDEN 掏空 ⇒ 同一夹具必须不红
        #     —— 证明「这张集合就是判据真正读的那把 key」，不是靠改注释（判例-30）──
        pl, pr = pair(td, "rejected-mutated",
                      plans_docs=(("2026-10-24-rejected-proposal.md", FM_REJECTED),))
        _v, _w, _st = check_one(os.path.join(pl, "2026-10-24-rejected-proposal.md"),
                                "docs/plans/2026-10-24-rejected-proposal.md", [], FACES["plans"],
                                live_forbidden=set())
        cell("MUTATION-live-forbidden-emptied-kills-P7",
             any(c == "P7" for _s, c, _m in _v), False)
        _v2, _w2, _st2 = check_one(os.path.join(pl, "2026-10-24-rejected-proposal.md"),
                                   "docs/plans/2026-10-24-rejected-proposal.md", [], FACES["plans"])
        cell("live-forbidden-default-holds-P7", any(c == "P7" for _s, c, _m in _v2), True)

        # ── 格15（★变异对照6·代码面）：把 TERMINAL_WARN 掏空 ⇒ `已推迟` 连告警都不给 ──
        pl, pr = pair(td, "warnmut", plans_docs=(("2026-10-26-deferred-proposal.md", FM_DEFERRED),))
        deferred_doc = os.path.join(pl, "2026-10-26-deferred-proposal.md")
        _v4, _w5, _st3 = check_one(deferred_doc,
                                   "docs/plans/2026-10-26-deferred-proposal.md", [], FACES["plans"],
                                   terminal_warn=set())
        cell("MUTATION-warn-set-emptied-kills-P6", any(c == "P6" for _s, c, _m in _w5), False)
        _v5, _w6, _st4 = check_one(deferred_doc,
                                   "docs/plans/2026-10-26-deferred-proposal.md", [], FACES["plans"])
        cell("warn-set-default-holds-P6", any(c == "P6" for _s, c, _m in _w6), True)

        # ── 格16：terminal_rule 表本身（两面共用一张表；词表两侧都要认）──
        cell("terminal-rule-table",
             (terminal_rule("已驳回"), terminal_rule("rejected"), terminal_rule("archived"),
              terminal_rule("已推迟"), terminal_rule("deferred"), terminal_rule("已完成"),
              terminal_rule("提案中"), terminal_rule("draft"), terminal_rule(""),
              terminal_rule("随便写点啥")) ==
             ("forbidden", "forbidden", "forbidden", "warn", "warn", "warn",
              None, None, None, None), True)

        # ── 格17：proposals 面合规 draft ⇒ rc=0，且输出点名 proposals 那一条 ──
        pl, pr = pair(td, "prop-clean")
        rc, out = run(pl, pr)
        cell("proposal-face-valid-rc0", (rc, "docs/proposals/2026-10-22-draft-proposal.md" in out),
             (RC_OK, True))

        # ── 格18：proposals 卡片没有 YAML 头部（扩面前两份真卡的形状）⇒ rc=1 且 P8 ──
        pl, pr = pair(td, "prop-nofm", props_events=(
            ("2026-10-22-nofm-proposal.md", FM_PROPOSAL_NO_FM),))
        rc, out = run(pl, pr)
        cell("MUTATION-proposal-no-frontmatter-rc1", rc, RC_VIOLATION)
        cell("MUTATION-proposal-no-frontmatter-P8", "[P8]" in out, True)

        # ── 格19：proposals 有头部但没有 status 键 ⇒ rc=1 且 P9 ──
        pl, pr = pair(td, "prop-nostatus", props_events=(
            ("2026-10-22-nostatus-proposal.md", FM_PROPOSAL_NO_STATUS),))
        rc, out = run(pl, pr)
        cell("proposal-missing-status-rc1", rc, RC_VIOLATION)
        cell("proposal-missing-status-P9", "[P9]" in out, True)

        # ── 格20：proposals status 不在英文闭集 ⇒ rc=1 且 P9 ──
        pl, pr = pair(td, "prop-badstatus", props_events=(
            ("2026-10-22-badstatus-proposal.md", FM_PROPOSAL_BAD_STATUS),))
        rc, out = run(pl, pr)
        cell("proposal-bad-status-rc1", rc, RC_VIOLATION)
        cell("proposal-bad-status-P9", "[P9]" in out, True)

        # ── 格21（★变异对照7）：proposals 面 `status: rejected` 留在活动目录 ⇒ rc=1 且 P7 ──
        pl, pr = pair(td, "prop-rejected", props_events=(
            ("2026-10-22-rejected-proposal.md", FM_PROPOSAL_REJECTED),))
        rc, out = run(pl, pr)
        cell("MUTATION-proposal-rejected-in-live-rc1", rc, RC_VIOLATION)
        cell("MUTATION-proposal-rejected-P7", "[P7]" in out, True)

        # ── 格22：proposals 面空枚举 ⇒ rc=2 自拒（plans 面干净也不顶）──
        pl, pr = pair(td, "empty-props", props_events=())
        rc, out = run(pl, pr)
        cell("empty-proposals-self-reject-rc2", rc, RC_BROKEN)
        cell("empty-proposals-says-FATAL", "[FATAL]" in out, True)

        # ── 格23：目录不存在（整面无法扫描）⇒ rc=2 ──
        ghost = os.path.join(td, "no-such-plans")
        pl, pr = pair(td, "ghostdir")
        rc, out = run(ghost, pr)
        cell("missing-dir-self-reject-rc2", rc, RC_BROKEN)

        # ── 格24：两面都只有非法头部 ⇒ 一个 status 都解析不出来 ⇒ rc=2（不是 rc=1 的违例清单）──
        pl, pr = pair(td, "zero-status",
                      plans_docs=(("2026-10-22-aigc-proposal.md", FM_AIGC),),
                      props_events=(("2026-10-22-nofm-proposal.md", FM_PROPOSAL_NO_FM),))
        rc, out = run(pl, pr)
        cell("zero-status-parsed-rc2", rc, RC_BROKEN)
        cell("zero-status-says-FATAL", ("[FATAL]" in out and "空宇宙" in out), True)
        # 反向对照：AIGC 那份头部**能解析**（只是缺四字段）⇒ 同一面配上合法 proposals 时是 rc=1 不是 rc=2
        pl, pr = pair(td, "one-status",
                      plans_docs=(("2026-10-22-aigc-proposal.md", FM_AIGC),))
        rc, out = run(pl, pr)
        cell("one-status-parsed-not-census-refusal", rc, RC_VIOLATION)

        # ── 格25：单边覆盖旗 ⇒ rc=2 自拒（两面必须成对）──
        pl, pr = pair(td, "argface")
        buf = io.StringIO()
        with contextlib.ExitStack() as stack:          # stderr 也要收：argparse 的错语只走 stderr
            stack.enter_context(contextlib.redirect_stdout(buf))
            stack.enter_context(contextlib.redirect_stderr(io.StringIO()))
            try:
                rc_single = main(["--plans-dir", pl])
            except SystemExit as e:      # argparse 路径不该走到这里；走到就是参数面漏了
                rc_single = e.code
        cell("single-face-override-refused-rc2", (rc_single, "[FATAL]" in buf.getvalue()),
             (RC_BROKEN, True))
        cell("scan-pair-pair-required",
             (scan_pair(pl, "") != "" and scan_pair("", pr) != ""
              and scan_pair(pl, pr) == "" and scan_pair("", "") == ""), True)
        cell("resolve-dirs-default-to-repo",
             resolve_dirs("", "") == (PLANS, PROPOSALS, ""), True)
        cell("resolve-dirs-pair-overrides",
             resolve_dirs(pl, pr) == (pl, pr, ""), True)

        # ── 格26（R207 参数面）：未知旗标必须被拒（rc=2），不许静默落进真检查分支 ──
        with contextlib.ExitStack() as stack:
            stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
            stack.enter_context(contextlib.redirect_stderr(io.StringIO()))
            try:
                main(["--definitely-not-a-real-flag"])
                rc_unknown = 0
            except SystemExit as e:
                rc_unknown = e.code
        cell("arg-unknown-flag-rc2", rc_unknown, 2)

        # ── 格27：枚举函数只收本层文件、跳过项点名（纯函数面）──
        pl, pr = pair(td, "enum")
        mk(pl, "README.md", "# 说明\n")
        os.makedirs(os.path.join(pl, "archived"), exist_ok=True)
        mk(os.path.join(pl, "archived"), "2026-10-20-old.md", FM_REJECTED)
        files, skipped, broken = enumerate_docs(pl)
        cell("enumerate-only-this-level",
             (broken == "" and [f for _p, f in files] == ["2026-10-22-ok-proposal.md"]
              and skipped == ["README.md"]), True)

    ok = sum(1 for _n, g, w in cells if g == w)
    print("\n[selftest] %d/%d 格通过" % (ok, len(cells)))
    if ok != len(cells):
        print("[selftest] ✗ 有格未通过 —— 判据自身坏了")
        return 4
    return 0


if __name__ == "__main__":
    sys.exit(main())
