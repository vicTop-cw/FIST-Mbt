#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""scripts/check_slave_task_list.py — 副机任务清单「认领入口」自证守卫（R126）。

**为什么要有它**（实测驱动，2026-10-22 R122）：`docs/2026-10-20-slave-tasks.md` 是副机 agent
开工时读的第一件东西——它是**认领入口**，不是存档。R122 对账前那里 28 行全标 `[ ]`，其中 8 行
早已进主线并挂进 CI 与电池：入口不可信，下一位就会把已经做完的活再做一遍。R122 逐行改判之后
把读数写进文首（结构级 41 / 内容级 40 / 失配 0），但那两个数当时是**我从一次性脚本的输出手抄**的
——这正是本仓 J10 点名的「声明滞后 / 幻影判据」形状，也是 R122 报告「遗留风险 2」自己认的那条。
本尺把那两句承诺变成机器每次重算的事实：**入口的每一行要么有可复核的证据，要么当场发红。**

**判定面（逐条点名）**：
  A1 干净不误红       = 证据列锚点全部可解析、状态词合法、自述与实算一致 ⇒ 0。
  B1 文件缺失         = 锚点指到的文件在跟踪面（读不到 git 时退化为文件系统存在性）里不存在 ⇒ 红。
  B2 行号越界         = 锚点行号 > 该文件实际行数 ⇒ 红（R122 实测：一次合入把 `server.mbt` 的行
                        推 7066→7067，"越界"与"漂移"是同一把尺能看的两格）。
  B3 记号不在那一行   = 锚点紧跟的括号里点了记号（反引号串 / 引号串 / 像标识符的 ASCII 词），
                        而那一行不含任何一个 ⇒ 红。「文件还在、但那行不是那件事」比文件缺失更常见。
  B4 锚点指到空行     = 锚点行存在但内容为空（或只有空白）⇒ 红。B1/B2/B3 都抓不到这一形：文件在、
                        行号在界内、括号里没点名记号，于是"指向一行空白"就白拿一条在场证据。
  B5 范围锚点两端都核 = `file:4-10` 是在声称一个范围，尺把上端也当一条锚点核对；只核下端等于放过
                        写错的上端（R126 实测：本清单 WT-05 原来就写 `:4-10`，而下端恰是一行空白）。
  C1 已落地无据       = 状态 `已落地` 而证据列没有任何**指得到在场真源**的指认（`文件:行` 锚点或整份
                        文件都在都算据），或证据列为空 ⇒ 红。口径沿用 R119 的 `UNPROVEN-DONE 不许无据`
                        与 `bug_list.open_with_linked_done`（账本说没修、任务库说修完了）——入口面此前
                        没人认领这条。
  C2 状态词表越界     = 状态列不在闭集 `已落地 / 部分 / 未开工 / 作废 / 无法取证` 之内 ⇒ 红。
                        词表一散，"done" 与 "done-ish" 就分不开，分布自述也无从对表。
  D1 结构级/失配自述落后 = 文首写 `结构级 N 条` 或 `失配 N`，而尺实算不是 N ⇒ 红。
  D2 内容级自述落后   = 文首写 `内容级 M 条`，而尺反解到「带点名记号」的锚点数不是 M ⇒ 红。
  D3 分布/行数自述落后 = 文首写 `已落地 a / 部分 b / 未开工 c / 作废 d` 与 `实读编号行是 **R**`，
                        与状态列实算不一致 ⇒ 红（登记文字自身是被检面）。
  E1 空扫描面自拒     = 一行任务都没解析到 ⇒ 2，绝不冒用「0 违例」的绿灯。
  E2 读不到就自拒     = 清单文件缺失 / 根目录不存在 ⇒ 2。

**口径为什么这么窄（三条都是实测逼出来的）**：
  ① 判定面**只吃表格行 `现读证据` 列**里的 `文件:行` 锚点。「最近的前一个文件名」这类启发式在散文里
     会把账记到错的行上，而入口清单的散文与表格同字重——假红比漏红更坏。
  ② 内容级只在「锚点紧跟括号且括号里有可抽记号」时成立；抽不到记号的锚点记为**只查结构**并单独计数。
     记号由**文档自己**给出，脚本里没有一张硬编码 token 表——加了锚点就自动多一道内容核对，
     删了锚点也不会留下一条永远为真的断言（那是幻影判据的另一半）。
  ③ `无法取证` 是合法状态，但尺要求证据列非空；语义不猜。

**与其它尺的分工**：`check_doc_surface.py` 管文档表面（工具计数/规范正文/旧口径），`check_plan_landing.py`
管 plan 落点，本尺只管**这一份认领入口**的内部一致（锚点↔真源、状态↔证据、自述↔实算）。判据面不重叠。

用法：
  python scripts/check_slave_task_list.py                 # 对表现网清单（裸跑即可进电池）
  python scripts/check_slave_task_list.py --selftest      # 尺子先证明自己会红
  python scripts/check_slave_task_list.py --show-face     # 补打判定面真实文件路径与根目录
  python scripts/check_slave_task_list.py --doc <路径> --root <目录>   # 自测用的合成树

退出码：0=判定面全过 / 1=违例（逐条点名）/ 2=判据无法自证（读不到清单、空扫描面）/ 4=尺子自己坏了。
"""
import io
import os
import re
import subprocess
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

SELF = os.path.basename(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_DOC = os.path.join("docs", "2026-10-20-slave-tasks.md")

STATUS_WORDS = (u"已落地", u"部分", u"未开工", u"作废", u"无法取证")
ROW_ID_RE = re.compile(r"^\|\s*((?:CAF|GUARD|MULTI|WEB|WT|SHIP|POLISH|MISC|SHELF|OPS)-\d+)\s*\|")
# 带扩展名的 文件:行（允许 .github 这类点目录与相对 ./ 前缀）；只认已知扩展名，
# 免得把「docs/xxx.md §6.2」这种没有行号的指认误判成越界。
FILE_LINE_RE = re.compile(
    r"((?:\.?/?[A-Za-z0-9_][A-Za-z0-9_./\-]*)\.(?:mbt|mbti|py|yml|yaml|md|ps1|sh|js|html|json|jsonl|txt|c|h|go|java|rs|ts))"
    r":(\d+)(?![0-9])"
)
# 同文件续引：`, :798` / `、:950`（前面不能是文件名字符，否则抢 FILE_LINE_RE 的活）
BARE_LINE_RE = re.compile(r"(?<![A-Za-z0-9_./\-]):(\d+)(?![0-9])")
# 只点文件、不点行的锚点（安装三面这类「整份文件都在」的证据）
FILE_BARE_RE = re.compile(
    r"(?:\.?/?[A-Za-z0-9_][A-Za-z0-9_./\-]*)\.(?:mbt|mbti|py|yml|yaml|md|ps1|sh|js|html|json|jsonl|txt|c|h|go|java|rs|ts)"
)
IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_./\-]{3,}")
BACKTICK_RE = re.compile(r"`([^`]+)`")
QUOTED_RE = re.compile(r"[\"“]([^\"”]{3,})[\"”]")
NOISE_TOKENS = {"true", "false", "none", "http", "https", "json", "mcp", "name", "path", "type",
                "list", "impl", "utf", "github", "gitcode", "node", "file", "line", "code",
                "serve", "temp", "docs", "src", "with", "that", "this", "from", "main", "test",
                "js", "jsonl", "mbt", "step", "runs", "jobs", "when", "then", "steps"}

CLAIM_STRUCT = re.compile(u"结构级\\s*(\\d+)\\s*条")
CLAIM_CONTENT = re.compile(u"内容级\\s*(\\d+)\\s*条")
CLAIM_MISMATCH = re.compile(u"失配\\s*(\\d+)")
CLAIM_DIST = re.compile(u"已落地\\s*(\\d+)\\s*/\\s*部分\\s*(\\d+)\\s*/\\s*未开工\\s*(\\d+)\\s*/\\s*作废\\s*(\\d+)")
CLAIM_ROWS = re.compile(u"实读编号行是\\s*\\*\\*(\\d+)\\*\\*")


def tracked_files(root):
    """跟踪面文件名集合；git 不可用 / 不是仓库 ⇒ None（调用方退化为 fs 存在性）。"""
    try:
        p = subprocess.run(["git", "-C", root, "ls-files"], capture_output=True, timeout=60)
    except Exception:
        return None
    if p.returncode != 0:
        return None
    lines = [l.strip().replace("\\", "/") for l in p.stdout.decode("utf-8", "replace").splitlines()]
    return set(lines) if lines else None


def read_lines(root, rel):
    """按仓内相对路径读行。返回 (lines|None, 原因|None)。"""
    norm = rel.replace("\\", "/")
    while norm.startswith("./"):
        norm = norm[2:]
    if norm.startswith("../") or os.path.isabs(norm):
        return None, u"锚点路径越出仓根"
    ap = os.path.join(root, *norm.split("/"))
    if not os.path.isfile(ap):
        return None, u"文件不存在"
    try:
        with io.open(ap, encoding="utf-8", errors="replace") as f:
            return f.read().splitlines(), None
    except OSError as e:
        return None, u"读不到：%s" % e


def norm_rel(rel):
    norm = rel.replace("\\", "/")
    while norm.startswith("./"):
        norm = norm[2:]
    return norm


def paren_tokens(cell, end):
    """锚点之后**紧跟**的分组里抽「被声称的记号」。

    分组指 `（…）` 或 `「…」`，两者之间允许 ≤6 个字的连接语（` 逐字写`、` 起于`）。
    `（…）` 只取其中的反引号串 / 引号串 / 像标识符的 ASCII 词（括号在本文里多半是散文说明）；
    `「…」` 整段当一个候选——本仓写「逐字」时给的就是原文，它应当直接落在那一行上。
    记号全部来自文档自己，尺内没有硬编码 token 表。
    """
    cands = []
    p = end
    for _ in range(2):  # 最多连吃两组：`（G7）「仍未实现…」` 这类先括号后引号
        while p < len(cell) and cell[p] in "` \t":
            p += 1
        if p >= len(cell) or (cell[p] != u"（" and cell[p] != u"「"):
            opener = None
            for k in range(1, 7):  # 允许 ≤6 字连接语
                if p + k >= len(cell):
                    break
                if cell[p + k] in (u"（", u"「"):
                    opener = cell[p + k]
                    p += k
                    break
                if cell[p + k] in (u"：", u":", u"，"):
                    break
            if opener is None:
                break
        closer = u"）" if cell[p] == u"（" else u"」"
        j = cell.find(closer, p + 1)
        if j < 0:
            break
        body = cell[p + 1:j]
        if cell[p] == u"「":
            t = body.strip()
            if len(t) >= 2:
                cands.append(t)
        for rx in (BACKTICK_RE, QUOTED_RE):
            for m in rx.finditer(body):
                tt = m.group(1).strip()
                if len(tt) >= 3:
                    cands.append(tt)
        if not cands:
            for m in IDENT_RE.finditer(body):
                tt = m.group(0)
                if len(tt) >= 4 and tt.lower() not in NOISE_TOKENS:
                    cands.append(tt)
        p = j + 1
    seen, uniq = set(), []
    for t in cands:
        if t not in seen:
            seen.add(t)
            uniq.append(t)
    return uniq


def parse_rows(doc_text):
    rows = []
    for raw in doc_text.splitlines():
        m = ROW_ID_RE.match(raw)
        if not m:
            continue
        cols = [c.strip() for c in raw.split("|")[1:-1]]
        rows.append({"id": m.group(1), "cols": cols,
                     "status": cols[3] if len(cols) > 3 else u"",
                     "evidence": cols[4] if len(cols) > 4 else u""})
    return rows


def status_word(cell):
    t = cell.replace("`", u"").strip()
    for w in STATUS_WORDS:
        if t.startswith(w):
            return w, True
    return t, False


def collect_anchors(rows, root, tracked):
    """从每行证据列反解锚点。返回 (anchors, 结构级数, 内容级数, {行号: 文件级证据})。"""
    anchors, struct_n, content_n = [], 0, 0
    fileface = {}
    cache = {}
    for r in rows:
        cell = r["evidence"]
        events = []
        for m in FILE_LINE_RE.finditer(cell):
            events.append((m.start(), m.end(), m.group(1), int(m.group(2))))
            rng = re.match(r"-(\d+)", cell[m.end():m.end() + 8])
            if rng:
                # `file:4-10` 是在声称一个**范围**：两端都得核，只核下端等于放过写错的上端
                events.append((m.end() + 1, m.end() + 1 + len(rng.group(1)), None, int(rng.group(1))))
        for m in BARE_LINE_RE.finditer(cell):
            events.append((m.start(), m.end(), None, int(m.group(1))))
        events.sort()
        # 文件级证据：把「文件:行」整段抹掉后，剩下的带扩展名路径就是「整份文件都在」那一类指认
        masked = FILE_LINE_RE.sub(lambda m: " " * (m.end() - m.start()), cell)
        bare = []
        for m in FILE_BARE_RE.finditer(masked):
            rel = norm_rel(m.group(0))
            if rel in [b[0] for b in bare]:
                continue
            if rel not in cache:
                cache[rel] = read_lines(root, rel)
            lines, _why = cache[rel]
            bare.append((rel, lines is not None and (tracked is None or rel in tracked)))
        fileface[r["id"]] = bare
        last_file = None
        for st, en, fl, ln in events:
            if fl:
                last_file = fl
            if not last_file:
                continue  # 裸行号出现在首个文件名之前：无从归属，不判
            struct_n += 1
            rel = norm_rel(last_file)
            if rel not in cache:
                cache[rel] = read_lines(root, rel)
            lines, why = cache[rel]
            a = {"row": r["id"], "file": rel, "line": ln, "ok": False,
                 "code": u"B1", "why": u""}
            if lines is None:
                a["why"] = why or u"读不到"
            elif tracked is not None and rel not in tracked:
                a["code"] = u"B1"
                a["why"] = u"文件在磁盘上但不在跟踪面"
            elif ln < 1 or ln > len(lines):
                a["code"] = u"B2"
                a["why"] = u"行号越界（该文件共 %d 行）" % len(lines)
            else:
                a["ok"] = True
                a["text"] = lines[ln - 1]
                if not a["text"].strip():
                    a["blank"] = True  # 指向空行：文件在、那行什么都不是
                toks = paren_tokens(cell, en)
                if toks:
                    content_n += 1
                    a["content"] = True
                    a["tokens"] = toks
                    a["content_ok"] = any(t in a["text"] for t in toks)
            anchors.append(a)
    return anchors, struct_n, content_n, fileface


def evaluate(doc_text, rows, anchors, struct_n, content_n, fileface):
    """判定面。返回 (违例去重列表, 自拒理由列表)。"""
    viol, selfref = [], []
    bad = [a for a in anchors if not a["ok"]]
    content_bad = [a for a in anchors if a.get("content") and not a["content_ok"]]
    blanks = [a for a in anchors if a["ok"] and a.get("blank")]
    mismatch_n = len(bad) + len(content_bad) + len(blanks)
    counts = dict((w, 0) for w in STATUS_WORDS)
    for r in rows:
        w, legal = status_word(r["status"])
        if legal:
            counts[w] += 1

    for a in bad:
        viol.append(u"%s %s：%s:%s —— %s" % (a["code"], a["row"], a["file"], a["line"], a["why"]))
    for a in content_bad:
        viol.append(u"B3 %s：%s:%s —— 锚点后括号点了记号 %s，那一行一个都不含（真读到的是：%s）"
                    % (a["row"], a["file"], a["line"],
                       u" / ".join(u"`%s`" % t for t in a["tokens"]),
                       a["text"].strip()[:60]))
    for a in blanks:
        viol.append(u"B4 %s：%s:%s —— 锚点指到**空行**：文件在、行也没越界，但那一行什么都没有，"
                    u"等于没给证据（B3 抓不到它，因为括号里没点名记号）"
                    % (a["row"], a["file"], a["line"]))
    for r in rows:
        w, legal = status_word(r["status"])
        if not legal:
            viol.append(u"C2 %s：状态 `%s` 不在闭集 %s 之内"
                        % (r["id"], r["status"], u" / ".join(STATUS_WORDS)))
            continue
        if not r["evidence"].strip():
            viol.append(u"C1 %s：状态 `%s` 但证据列为空——认领入口不许留「按任务名自己猜」的行"
                        % (r["id"], w))
        elif w == u"已落地":
            hit_anchor = [a for a in anchors if a["row"] == r["id"] and a["ok"]]
            hit_file = [f for f in fileface.get(r["id"], []) if f[1]]
            if not hit_anchor and not hit_file:
                cited = [f[0] for f in fileface.get(r["id"], [])]
                tail = u"——点名的文件都读不到：%s" % u", ".join(cited) if cited else u""
                viol.append(u"C1 %s：判 `已落地` 但没有任何一条指得到在场真源%s"
                            u"（UNPROVEN-DONE 不许无据）" % (r["id"], tail))

    for m in CLAIM_STRUCT.finditer(doc_text):
        if int(m.group(1)) != struct_n:
            viol.append(u"D1 文首写「结构级 %s 条」，尺从证据列实算 %d 条（手抄读数落后）"
                        % (m.group(1), struct_n))
    for m in CLAIM_CONTENT.finditer(doc_text):
        if int(m.group(1)) != content_n:
            viol.append(u"D2 文首写「内容级 %s 条」，尺实算 %d 条（只有点名了记号的锚点算内容级）"
                        % (m.group(1), content_n))
    for m in CLAIM_MISMATCH.finditer(doc_text):
        if int(m.group(1)) != mismatch_n:
            viol.append(u"D1 文首写「失配 %s」，尺实算失配 %d 条" % (m.group(1), mismatch_n))
    for m in CLAIM_DIST.finditer(doc_text):
        got = tuple(int(m.group(i)) for i in (1, 2, 3, 4))
        exp = (counts[u"已落地"], counts[u"部分"], counts[u"未开工"], counts[u"作废"])
        if got != exp:
            viol.append(u"D3 文首写「已落地 %d / 部分 %d / 未开工 %d / 作废 %d」，状态列实算 %d / %d / %d / %d"
                        % (got + exp))
    for m in CLAIM_ROWS.finditer(doc_text):
        if int(m.group(1)) != len(rows):
            viol.append(u"D3 文首写「实读编号行是 %s」，尺实算 %d 行"
                        u"（切片小计与行数互不印证时，入口就靠不住）" % (m.group(1), len(rows)))

    if not rows:
        selfref.append(u"判定面为空：一行任务都没解析到（列名/行首格式改了或清单被清空）")
    seen, uniq = set(), []
    for v in viol:
        if v not in seen:
            seen.add(v)
            uniq.append(v)
    return uniq, selfref


def run(doc_path, root, sink):
    """主判定：读数逐行 append 进 `sink`，交回**裸**退出码（2=自拒 / 1=违例 / 0=全过）。

    码与文本分家不是洁癖：串式 `return 2, 文本` 里那个 2 在
    `check_exit_code_contract.py` 的 ast 实现面上是隐形的（它只认非元组的出口），
    承诺 rc=2 而实现面给不出 = R1 模块面幻影 = BUG-369 抓过的假契约。
    """
    if not os.path.isdir(root):
        sink.append(u"自拒：根目录不存在 %s" % root)
        return 2
    if not os.path.isfile(doc_path):
        sink.append(u"自拒：清单不存在 %s" % doc_path)
        return 2
    with io.open(doc_path, encoding="utf-8", errors="replace") as f:
        doc_text = f.read()

    tracked = tracked_files(root)
    face = u"跟踪面=git ls-files" if tracked is not None else u"跟踪面=文件系统（git 不可用，退化）"
    rows = parse_rows(doc_text)
    anchors, struct_n, content_n, fileface = collect_anchors(rows, root, tracked)
    viol, selfref = evaluate(doc_text, rows, anchors, struct_n, content_n, fileface)

    counts = dict((w, 0) for w in STATUS_WORDS)
    for r in rows:
        w, legal = status_word(r["status"])
        if legal:
            counts[w] += 1
    file_n = sum(1 for k in fileface for f in fileface[k] if f[1])

    out = [u"清单 %s | %s" % (norm_rel(os.path.relpath(doc_path, root)), face),
           u"判定面：任务行 %d / 证据锚点 %d（其中内容级 %d）/ 文件级在场 %d"
           % (len(rows), struct_n, content_n, file_n),
           u"状态分布（尺实算，非手抄）：" + u" / ".join(u"%s %d" % (w, counts[w]) for w in STATUS_WORDS)]
    if selfref:
        out.append(u"自拒：" + u"；".join(selfref))
        sink.extend(out)
        return 2
    if viol:
        out.append(u"FAIL 违例 %d 条：" % len(viol))
        for v in viol:
            out.append(u"  - " + v)
        sink.extend(out)
        return 1
    out.append(u"PASS 认领入口自证通过：锚点全部可解析、内容级记号逐行命中、`已落地` 全部带据、"
               u"文首自述与尺实算逐键一致")
    sink.extend(out)
    return 0


# ───────────────────────────── 自测 ─────────────────────────────
def _write(path, text):
    d = os.path.dirname(path)
    if d and not os.path.isdir(d):
        os.makedirs(d, exist_ok=True)
    with io.open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def _doc(evidence=None, status=u"已落地", struct=None, content=1, mis=0, dist=True, rows=1, body=None):
    """造一份与真源同构的最小清单；默认那份应当**全绿**。"""
    head = u"# 清单\n\n"
    if struct is not None:
        head += (u"> 自证读数：**结构级 %d 条**（文件存在 + 行号不越界）失配 %d；"
                 u"**内容级 %d 条**（那一行确实含所声称的记号）失配 %d。\n"
                 % (struct, mis, content, mis))
    if dist:
        head += u"> 改判后的分布是 **已落地 1 / 部分 0 / 未开工 0 / 作废 0**\n"
    head += u"> 实读编号行是 **%d**\n" % rows
    ev = evidence if evidence is not None else u"src/a.mbt:2（`beta_marker` 在场）"
    head += (u"\n| # | 任务 | 分支名 | 状态 | 现读证据 | bug_id | plan | 验收 |\n"
             u"|---|---|---|---|---|---|---|---|\n")
    if body is not None:
        return head + body
    return head + (u"| CAF-01 | 样例 | `b` | `%s` | %s | 新 | - | - |\n" % (status, ev))


def selftest():
    import shutil
    import tempfile
    base = tempfile.mkdtemp(prefix="slave-list-r123-")
    cases = []
    try:
        _write(os.path.join(base, "src", "a.mbt"),
               u"let alpha_marker = 1\nlet beta_marker = 2\n\n// gamma\n")
        _write(os.path.join(base, ".github", "workflows", "ci.yml"),
               u"jobs:\n  step:\n    - name: Model-auth-no-key guard\n")
        doc = os.path.join(base, "docs", "list.md")

        def go(text):
            _write(doc, text)
            sink = []
            return run(doc, base, sink), u"\n".join(sink)

        cases.append((u"A1 干净不误红", go(_doc(struct=1, rows=1)), 0, None))
        cases.append((u"A2 文件级证据不误红",
                      go(_doc(struct=0, content=0, rows=1, evidence=u"`src/a.mbt` 整份在场")),
                      0, None))
        cases.append((u"B1 文件缺失必红",
                      go(_doc(struct=1, content=0, mis=1, rows=1,
                             evidence=u"src/nope.mbt:2（`beta_marker`）")),
                      1, u"文件不存在"))
        cases.append((u"B2 行号越界必红",
                      go(_doc(struct=1, content=0, mis=1, rows=1,
                             evidence=u"src/a.mbt:99（`beta_marker`）")),
                      1, u"行号越界"))
        cases.append((u"B3 记号不在那一行必红",
                      go(_doc(struct=1, mis=1, rows=1, evidence=u"src/a.mbt:4（`beta_marker`）")),
                      1, u"那一行一个都不含"))
        cases.append((u"B4 锚点指到空行必红",
                      go(_doc(struct=1, content=0, mis=1, rows=1,
                             evidence=u"src/a.mbt:3（该行什么都没有）")),
                      1, u"指到**空行**"))
        cases.append((u"B5 范围锚点上端越界也必红",
                      go(_doc(struct=2, content=0, mis=1, rows=1, evidence=u"src/a.mbt:2-99 四档")),
                      1, u"src/a.mbt:99"))
        cases.append((u"C1 已落地无锚点必红",
                      go(_doc(struct=0, content=0, rows=1, evidence=u"看着像做完了，没给地方")),
                      1, u"没有任何一条指得到在场真源"))
        cases.append((u"C1c 已落地只指不存在的文件必红",
                      go(_doc(struct=0, content=0, rows=1, evidence=u"`src/gone.mbt` 整份在场")),
                      1, u"点名的文件都读不到"))
        cases.append((u"C1b 证据列为空必红",
                      go(_doc(struct=0, content=0, rows=1, evidence=u"")),
                      1, u"证据列为空"))
        cases.append((u"C2 状态词表越界必红",
                      go(_doc(struct=1, rows=1, dist=False, status=u"done")),
                      1, u"不在闭集"))
        cases.append((u"D1 结构级自述落后必红",
                      go(_doc(struct=9, rows=1)),
                      1, u"结构级 9 条"))
        cases.append((u"D2 内容级自述落后必红",
                      go(_doc(struct=1, content=4, rows=1)),
                      1, u"内容级 4 条"))
        cases.append((u"D3 分布自述落后必红",
                      go(_doc(struct=1, rows=1).replace(u"已落地 1 / 部分 0", u"已落地 7 / 部分 0")),
                      1, u"状态列实算 1 / 0"))
        cases.append((u"D3b 行数自述落后必红",
                      go(_doc(struct=1, rows=8)),
                      1, u"实读编号行是 8"))
        cases.append((u"A3 点目录路径不误红",
                      go(_doc(struct=1, rows=1,
                              evidence=u".github/workflows/ci.yml:3（`Model-auth-no-key guard`）")),
                      0, None))
        cases.append((u"E1 空扫描面必自拒",
                      go(u"# 空清单\n\n没有表格行。\n"),
                      2, u"判定面为空"))
        sink = []
        rc = run(os.path.join(base, "docs", "nope.md"), base, sink)
        cases.append((u"E2 读不到清单必自拒", (rc, u"\n".join(sink)), 2, u"清单不存在"))
    finally:
        shutil.rmtree(base, ignore_errors=True)

    fails = []
    for name, (rc, out), want, needle in cases:
        first = out.splitlines()[0] if out else u""
        if rc != want:
            fails.append(u"%s：期望 rc=%s，实得 rc=%s ｜ %s" % (name, want, rc, first))
            continue
        if want == 1 and needle and needle not in out:
            fails.append(u"%s：rc 对但读数里没有点名句 `%s`（红没红在该红的地方）" % (name, needle))
        if want == 1 and needle and needle not in out:
            fails.append(u"%s：rc 对但读数里没有点名句 `%s`（红没红在该红的地方）" % (name, needle))

    fam = {}
    for c in cases:
        f = re.match(r"^([A-Z])", c[0]).group(1)
        fam[f] = fam.get(f, 0) + 1
    clist = " / ".join(u"%s×%d" % (k, fam[k]) for k in sorted(fam))

    if fails:
        print(u"SELFTEST FAIL（%d/%d 支对照未发红）：" % (len(fails), len(cases)))
        for f in fails:
            print(u"  - " + f)
        return 1
    print(u"SELFTEST OK（%d 格：清单从已执行格子反解：%s）—— 不误红对照 / 必红对照 / 自拒对照三类齐备；"
          u"格数从已执行 cases 实测累加，非手写计数" % (len(cases), clist))
    return 0


def main(argv):
    doc, root, show_face, suggest = None, ROOT, False, False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--selftest":
            return selftest()
        elif a == "--show-face":
            show_face = True
        elif a == "--suggest-anchors":
            suggest = True
        elif a == "--doc":
            i += 1
            doc = argv[i]
        elif a == "--root":
            i += 1
            root = argv[i]
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
        i += 1
    doc_path = doc if (doc and os.path.isabs(doc)) else os.path.join(root, doc or DEFAULT_DOC)
    if suggest:
        # 只读建议器：**不改文档**，只打印每条失配锚点"按现状该指哪儿"。
        # 为什么只建议不自动改：R63 实测自动改会连环翻车——行号挪了、括号里的记号还是旧名，
        # 下一轮把新行号配旧记号再报一次红；更糟的是把记号指到"也含它但语义无关"的行就能骗过判据（R61 踩过）。
        rows = parse_rows(io.open(doc_path, encoding="utf-8", errors="replace").read())
        anchors, _s, _c, _f = collect_anchors(rows, os.path.abspath(root), tracked_files(root))
        tips = []
        for a in anchors:
            # 三类都要给建议：结构坏(B1/B2)、指到空行(B4)、**内容记号不在那一行(B3)**。
            # 第一版只挑前两类，B3 全被漏掉——那正是失配的大头（实测 20 条里 17 条是 B3）。
            if a["ok"] and not a.get("blank") and not (a.get("content") and not a.get("content_ok")):
                continue
            rel, ln = a["file"], a["line"]
            ap = os.path.join(os.path.abspath(root), *rel.replace("\\", "/").split("/"))
            if not os.path.isfile(ap):
                tips.append((a["row"], rel, ln, u"文件不存在"))
                continue
            src = io.open(ap, encoding="utf-8", errors="replace").read().splitlines()
            toks = a.get("tokens") or []
            cands = []
            for tk in toks:
                cands += [i + 1 for i, l in enumerate(src) if tk in l]
            if not cands:
                cands = [i + 1 for i, l in enumerate(src) if l.strip()]
            if not cands:
                tips.append((a["row"], rel, ln, u"文件里没有可用锚点"))
                continue
            best = min(cands, key=lambda x: abs(x - ln))
            uniq = [tk for tk in toks if sum(1 for l in src if tk in l) == 1]
            if uniq:
                tip = u"%s#%s（内容锚，记号唯一）" % (rel, uniq[0])
            elif toks:
                tip = u"%s:%d（记号多处出现，内容锚不可用，只能行号锚）" % (rel, best)
            else:
                tip = u"%s:%d（原锚点无记号，建议补一个唯一记号）" % (rel, best)
            tips.append((a["row"], rel, ln, tip))
        if not tips:
            print(u"  没有失配锚点，无需建议")
            return 0
        print(u"  失配锚点建议（**只读，未改文档**；落笔前请按语义确认）：")
        for rid, rel, ln, tip in tips:
            print(u"    %-14s %s:%s → %s" % (rid, rel, ln, tip))
        return 0
    sink = []
    rc = run(doc_path, os.path.abspath(root), sink)
    print(u"\n".join(sink))
    if show_face:
        print(u"—— 尺读的到底是哪一份：%s ｜ 根目录：%s" % (doc_path, root))
    return rc


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as e:  # 尺子自己坏了不许冒用 1 号档
        print(u"FAIL 判据异常：%r" % e)
        sys.exit(4)
