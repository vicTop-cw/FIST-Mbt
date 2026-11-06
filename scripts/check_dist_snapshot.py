#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""scripts/check_dist_snapshot.py — 仓内发布快照 `dist/fist-mbt.js` 的**版本面 + 内容面 + 描述面**守卫。

**版本面（R 轮既有）**：
`dist/fist-mbt.js` 是**仓内跟踪的发布快照**，而 `scripts/mcp_compat_shim.js` 的默认服务端就是它
（`node dist/fist-mbt.js serve`）、README 也把它当"发布版"引用。实测它曾内嵌 `project__version = "0.3.9"`，
而 `moon.mod` 已是 **0.3.10** ⇒ 任何照 shim 文档连过去的人/agent 拿到的是**旧版本 + 旧工具集**
（shim 注释里甚至写着 148 工具/v0.3.8）。`release.yml` 构建的是新鲜产物（`_release/js/fist-mbt.js`），
但**仓内这份快照没有任何守卫覆盖**——`check_release_asset_names` 明确不扫 dist。

**内容面（BUG-428，high —— 本格是这次事故的直接产物）**：
2026-10-26 实测：修复 commit `72986aa7`（20:40，BUG-417）落地后，`dist/fist-mbt.js` 是 **Oct 24 06:16**
的旧构建，而**本尺打的是 `PASS 快照版本 0.3.10 == moon.mod 0.3.10`** —— 版本对得上，代码是旧的。
代价是一次误判：调用方被 Omega 门拦下后认定「判定逻辑有缺陷」，查了 40 分钟。
⇒ 加一格内容面：快照正文里必须能找到 `KEY_SYMBOLS` 每条符号的**调用形**；缺则红，并点名
**「版本对但代码旧」**（这一句是本次事故的确诊语句，不许被"版本 PASS"盖住）。
探针从 `scripts/_deployment_symbols.py` 取（与 `check_deployment_freshness.py` **同一真源**，不抄第二份表）：
容忍 MoonBit 的 `_`→`__` 名字变形、且要求命中后紧跟 `(`（裸 substring 在**新鲜**产物上也会 0 命中，见该模块实测一）。

**描述面（第三面 · BUG-578 遗留② —— 2026-11-06 刚收过的那次滞后）**：
`dist/fist-mbt.js` 内嵌 `src/server/server.mbt` 的**工具描述串字面量**（tools/list 的正文就来自它）。
实测：`agent_register_key` 的描述早在 BUG-577 批就改口，dist 却仍烤着旧句
「已有公钥且与本次不同 ⇒ 拒绝（需走轮换，尚未实现）」，直到 `python scripts/refresh_dist.py` 重投影
（commit `e4667f851`）。**上面两面谁也看不见这一格**：
1. 本尺前两面的判据是「内嵌版本号」与「符号调用形」⇒ 描述串既不是版本也不是符号，
   于是「版本对、符号在、句子旧」照样 rc=0；
2. `check_stale_self_claim.py` 的 `SKIP_PATH_PARTS` 第一项就是 `dist/`（生成/孪生面不扫）
   ⇒ §4.1 门抓得住 src 的谎，抓不住 dist 里**源码已经删掉**的残句 —— 那是**差集**问题，不是主张真伪问题；
3. `release.yml` 的资产来自 CI 现烤的 `_build/js/…/cli.js`，不读 dist
   ⇒ 「CI 恒绿」与「dist 恒旧」可以长期并存。真正吃到旧句的是克隆者/agent 侧
   （`mcp_compat_shim.js` 默认连 `dist/fist-mbt.js` serve）。

**取数与抽样口径（为什么不是「182 条逐一比」）**：
- 宇宙：`src/server/*.mbt` 非测试面里 `= instrumented_tool(` 注册进来的 `(name, 描述串)` 对
  （现读 178 条 / 175 个唯一名，`wt_*` 三对同名各 2 次是 deprecated 块）；
  描述串**原文**由深度-1 字面量扫描器取出（`+` 连接的长句取第一段，比对用的是 substring，取段即够）。
- **可判形闸门**：只判**不含反斜杠**的描述串。含 `\"` / `\{…}`（插值 ⇒ bundle 里变 `${…}`）的字面量
  在 bundle 里**可能不同形**，逐一比会假红。实测口径（2026-11-06 现读）：178 条里只有 3 条含反斜杠，
  且这 3 条在 bundle 里**恰好也是原形**（`\"` 被保留）—— 但这一格没有任何上游契约钉住，
  moonc 换世代就可能翻形，所以本尺**宁可少判**：含转义的一律挡在闸门外并报数（残留缺口见下）。
  ⇒ 判据强度不靠抽样比例换：**现读 175/178 条无转义、全部进判定面**（不是 15 条的小样本）。
- **S2 关注面**沿用 `check_stale_self_claim.py` 的判据函数（`claim_lines` / `clauses` / `symbols_in`，
  即「含负面句式 NEG_PHRASES 或含反引号具名符号」）：**只用来给缺句排优先级 + 报关注面计数**，
  不用来收窄判定面 —— 同一规则两处实现是本仓判例族点名的形状，所以这里 import 而不是另写一份。
- **反向面（差集的另一半）**：从 bundle 反解调用点的 `(name, desc)`（正则见 `RE_DIST_CALL`，
  函数定义行因第二项不是字面量而天然不匹配），要求 **dist 里的工具名不得多出 src 没有的**
  ⇒ 抓到「src 已删工具、dist 还整条烤着」。**描述级的反向不判**：bundle 会把 `+` 连接的句子**合并**，
  逐句反查必然假红（实测 `agent_revoke_key` / `agent_issue_challenge` 两条就是这样）。
- **空宇宙/脱锚自拒（rc=2，绝不冒用 1）**：src 一条都解析不到 / dist 正文空 / bundle 反解不到调用点 /
  可判形抽样数为 0 / **缺句率 ≥80% 且判定面 ≥10 条**（这不是「dist 旧」，这是打包形态变了、本尺失明）。

判定（三面）：
  版本面：快照内嵌版本 != moon.mod ⇒ rc=1（对用户而言"版本说谎"是硬伤）；
  内容面：版本对但缺探针符号 ⇒ rc=1（"版本对但代码旧"）；
  描述面：src 的当前句子在 dist 找不到 ⇒ rc=1 并点名**「src 已改口、dist 还烤着旧句」**；
          dist 多出 src 已删的工具名 ⇒ rc=1（同一处置：跑 refresh_dist.py）；
  任一面读不到样本 ⇒ rc=2（判据无法自证，不冒用 1）；三面都过 ⇒ rc=0。
刷新用 `python scripts/refresh_dist.py`（构建 + patch_esm_main + 拷贝）。

参数面：`--selftest`（自检）/ `--list`（只打印抽样与关注面清单）；**未知旗标 ⇒ rc=2**（R207 族）。
"""
import io
import os
import re
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from _deployment_symbols import (  # noqa: E402 — 同目录共享模块（`_` 前缀，豁免登记）
    KEY_SYMBOLS,
    count_calls,
    missing_symbols,
)

# S2 运行时字面量面的判据函数：**从 check_stale_self_claim 复用，不抄第二份**
# （claim_lines/clauses/symbols_in 就是「负面句式 ↔ 反引号具名符号」那条规则的唯一实现）。
from check_stale_self_claim import (  # noqa: E402
    TEST_SUFFIXES,
    claim_lines,
    clauses,
    symbols_in,
)

ROOT = os.path.normpath(os.path.join(HERE, ".."))
DIST = os.path.join(ROOT, "dist", "fist-mbt.js")
VERSION_RE = re.compile(r'project__version = "([0-9]+\.[0-9]+\.[0-9]+)"')

BS = chr(92)   # 反斜杠：不写字面量，免得本文件的变异对照锚点（扫自己的源码行）被注释喂针
DQ = chr(34)   # 双引号：同上
SRC_SERVER_DIR = os.path.join(ROOT, "src", "server")
RE_REGISTER = re.compile(r"=\s*instrumented_tool\(")
NAME_RE = re.compile(r"[a-z][a-z0-9_]{2,}\Z")
# bundle 侧调用点：`…instrumented__tool(<第一实参>, "name", "desc"`。
# 函数定义行 `instrumented__tool(s, name, description` 的第二个位置是**标识符**不是字面量 ⇒ 天然不匹配。
RE_DIST_CALL = re.compile(
    'instrumented__tool\\(\\s*[^,()]*,\\s*'
    '"([a-z][a-z0-9_]{2,})"\\s*,\\s*'
    '"((?:[^"\\\\]|\\\\.)*?)"'
)


def moon_version(root=ROOT):
    p = os.path.join(root, "moon.mod")
    if not os.path.isfile(p):
        return None
    m = re.search(r'version\s*=\s*"([^"]+)"', io.open(p, encoding="utf-8").read())
    return m.group(1) if m else None


def dist_versions(text):
    """快照里出现的所有内嵌版本（去重保序）。纯函数，selftest 直接喂合成文本。"""
    seen = []
    for v in VERSION_RE.findall(text or ""):
        if v not in seen:
            seen.append(v)
    return seen


def judge(text, want):
    """版本面。返回 (rc, 说明)。纯函数：
    0 = 快照版本 == moon.mod；1 = 快照版本落后/不一致；2 = 快照里读不到版本（判据无样本）。
    """
    got = dist_versions(text)
    if not want:
        return 2, "moon.mod 读不到 version —— 判据没有基线，拒绝出结论"
    if not got:
        return 2, "快照里读不到 project__version —— 判据没有样本，拒绝出结论"
    if got == [want]:
        return 0, "快照版本 %s == moon.mod %s" % (got[0], want)
    return 1, "快照版本 %s != moon.mod %s（照 shim 文档连过去的人会拿到旧版本/旧工具集）" % (
        "/".join(got), want)


def judge_content(text, symbols=KEY_SYMBOLS):
    """内容面。返回 (rc, 说明)。纯函数：
    0 = 探针符号全部有调用形；1 = 缺符号（**版本对但代码旧**）；2 = 空样本（拒绝出结论）。
    """
    if not text:
        return 2, "快照正文为空 —— 判据没有样本，拒绝出结论"
    missing = missing_symbols(text, symbols)
    if missing:
        return 1, "缺 %s（**版本对但代码旧** —— BUG-428 的形状：只比版号的守卫在这里是绿的）" % (
            " / ".join(missing))
    return 0, "%d 条探针全部有调用形（%s）" % (
        len(symbols), " / ".join(s.name for s in symbols))


def judge_snapshot(text, want, symbols=KEY_SYMBOLS):
    """两面合成（main 用的就是它，自检也考它 —— 判例-29：测的是实现路径）。返回 (rc, 行列表)。"""
    rc, why = judge(text, want)
    if rc != 0:
        return rc, ["版本面：%s" % why]
    lines = ["版本面：%s" % why]
    crc, cwhy = judge_content(text, symbols)
    lines.append("内容面：%s" % cwhy)
    return crc, lines


def _mb_literals_at_depth1(text, start):
    """从 `instrumented_tool(` 之后扫描，取**深度 1** 上的 MoonBit 字符串字面量**原文**。

    返回的是引号之间那一段的**源码写法**（含 `\\"` 这类转义），不是求值结果 ——
    描述面比的就是「同一段原文有没有被原样搬进 bundle」，故必须保留写法。
    行注释 `//` 会整行跳过（注释里的 `instrumented_tool(` 与引号都不作数）。
    """
    i = start
    depth = 1
    out = []
    while i < len(text):
        c = text[i]
        if c == DQ:
            j = i + 1
            buf = []
            while j < len(text):
                ch = text[j]
                if ch == BS:
                    buf.append(text[j:j + 2])
                    j += 2
                    continue
                if ch == DQ:
                    break
                buf.append(ch)
                j += 1
            out.append("".join(buf))
            i = j + 1
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                break
        elif text[i:i + 2] == "//":
            k = text.find("\n", i)
            i = len(text) if k < 0 else k
            continue
        i += 1
    return out


def on_s2_face(desc):
    """这条描述串在不在 S2 关注面上（负面句式 / 反引号具名符号）。判据**逐字复用** check_stale_self_claim。

    喂进去的是 `"…desc…"`（补上引号 ⇒ claim_lines 才认它是运行时字面量面而非注释面）。
    """
    quoted = DQ + desc + DQ
    if claim_lines(quoted):
        return True
    return any(symbols_in(cl) for cl in clauses(quoted))


def src_tool_pairs(server_dir=SRC_SERVER_DIR):
    """反解 src/server/*.mbt（非测试面）里 `= instrumented_tool(` 注册的 (name, 描述串原文)。

    返回 (pairs, unparsed)：`unparsed` 是「注册点找到、但前两个深度-1 字面量凑不齐/名字不像工具名」
    的条数 —— 那是**注册形态变了**，本尺不判红、只报数并挡在判定面外（否则任何非常规注册形
    都会把尺子变成恒红灯，而恒红的判据没人读 = 没锁）。
    """
    pairs = []
    unparsed = 0
    if not os.path.isdir(server_dir):
        return pairs, unparsed
    for fn in sorted(os.listdir(server_dir)):
        if not fn.endswith(".mbt") or fn.endswith(TEST_SUFFIXES):
            continue
        text = io.open(os.path.join(server_dir, fn), encoding="utf-8", errors="replace").read()
        for m in RE_REGISTER.finditer(text):
            ls = text.rfind("\n", 0, m.start()) + 1
            if text[ls:m.start()].lstrip().startswith("//"):
                continue  # 注释里写的 `= instrumented_tool(` 不是注册点
            lits = _mb_literals_at_depth1(text, m.end())
            if len(lits) < 2 or not NAME_RE.match(lits[0]):
                unparsed += 1
                continue
            pairs.append((lits[0], lits[1]))
    return pairs, unparsed


def dist_tool_pairs(text):
    """从 bundle 正文反解调用点的 (name, desc 原文)。正则失配 ⇒ 返回空表（由调用方自拒）。"""
    return [(n, d) for n, d in RE_DIST_CALL.findall(text or "")]


def judge_desc(pairs, dist_text, unparsed=0):
    """描述面（第三面）。返回 (rc, 行列表, 统计 dict)。

    0 = 判定面全部原样命中且 dist 不多出工具名；1 = 有旧句/残句；2 = 没有可判样本（拒绝出结论）。
    纯函数：pairs 与 dist_text 都可由 selftest 喂合成夹具，不碰真仓。
    """
    stats = {"src": len(pairs), "unparsed": unparsed, "judged": 0, "escaped": 0, "blank": 0,
             "s2": 0, "dist": 0, "missing": 0, "extra": 0}
    if not pairs:
        return 2, ["描述面：src/server 一条 instrumented_tool 注册都没解析到"
                   "（unparsed=%d）⇒ 判据没有样本，拒绝出结论" % unparsed], stats
    if not dist_text:
        return 2, ["描述面：dist 正文为空 —— 判据没有样本，拒绝出结论"], stats
    dpairs = dist_tool_pairs(dist_text)
    stats["dist"] = len(dpairs)
    if not dpairs:
        return 2, ["描述面：bundle 反解不到任何 instrumented__tool 调用点 —— 打包形态变了，本尺失明，"
                   "拒绝出结论（不许把这报成『dist 旧』）"], stats

    judged = []
    missing = []
    for name, desc in pairs:
        if not desc.strip():
            # 空描述串**绝不进判定面**：空串在任何正文里都「原样命中」，放进来了就是一台假绿发生器
            stats["blank"] += 1
            continue
        is_s2 = on_s2_face(desc)
        if is_s2:
            stats["s2"] += 1
        if BS in desc:
            stats["escaped"] += 1
            continue
        judged.append((name, desc, is_s2))
        if desc in dist_text:
            continue
        missing.append((name, desc, is_s2))
    stats["judged"] = len(judged)
    if not judged:
        return 2, ["描述面：可判形抽样数为 0（%d 条里转义闸门挡掉 %d 条、空串挡掉 %d 条）"
                   "⇒ 判据没有样本，拒绝出结论" % (len(pairs), stats["escaped"], stats["blank"])], stats
    stats["missing"] = len(missing)
    # 「几乎全不命中」不是 dist 旧，是**这把尺对不上打包形态**：报 2 让人来核尺，别把 rc=1 的解释权
    # 留给「跑一次 refresh_dist.py 就好」那个错误结论。
    if len(missing) >= 10 and len(missing) * 5 >= len(judged) * 4:
        return 2, ["描述面：%d/%d 条描述串在 dist 找不到（≥80%%）—— 这不是「dist 烤着旧句」，"
                   "是打包形态与本尺脱锚 ⇒ 拒绝出结论，请核 RE_DIST_CALL/字面量扫描器" % (
                       len(missing), len(judged))], stats

    src_names = {}
    for name, _d in pairs:
        src_names[name] = src_names.get(name, 0) + 1
    dist_names = {}
    for name, _d in dpairs:
        dist_names[name] = dist_names.get(name, 0) + 1
    extra = sorted(n for n, c in dist_names.items() if c > src_names.get(n, 0))
    stats["extra"] = len(extra)

    # 缺句按危害排序：S2 关注面（带负面句式/具名符号 ⇒ 会误导调用方的那批）先报
    missing.sort(key=lambda x: (not x[2], x[0]))
    if not missing and not extra:
        return 0, ["描述面：%d/%d 条描述串在 dist 原样命中（S2 关注面 %d 条、含转义被闸门挡掉 %d 条、"
                   "注册形态解析不出 %d 条）；dist 未多出 src 之外的工具名" % (
                       len(judged), len(pairs), stats["s2"], stats["escaped"], unparsed)], stats
    lines = []
    for name, desc, is_s2 in missing:
        lines.append(
            "✗ 描述面：`%s` 的描述串在 dist 未命中%s —— **src 已改口、dist 还烤着旧句**"
            "（跑 `python scripts/refresh_dist.py`）：%.72s…" % (
                name, "（S2 关注面）" if is_s2 else "", desc))
    if extra:
        lines.append("✗ 描述面：dist 里注册了 %d 个 src 已不再注册的工具名 —— **src 已删、dist 还整条烤着**"
                     "（跑 `python scripts/refresh_dist.py`）：%s" % (
                         len(extra), " / ".join(extra[:12])))
    lines.append("描述面：判定 %d 条 · 命中 %d · 旧句 %d · 残句 %d（S2 关注面 %d · 转义闸门 %d · 未解析 %d）" % (
        len(judged), len(judged) - len(missing), len(missing), len(extra),
        stats["s2"], stats["escaped"], unparsed))
    return 1, lines, stats


def _worst(rcs):
    """三面合码：2（无法自证）压过 1（违例）压过 0。绝不把 2 冒用成 1。"""
    if 2 in rcs:
        return 2
    return 1 if 1 in rcs else 0


def selftest():
    _entry_probe()
    cells = []          # (name, group, ok, 诊断) —— group 用于**反解** PASS 行的范围自述（J10）

    def cell(name, got, want, group=None):
        cells.append((name, group or name.split("-")[0], got == want, "got=%r want=%r" % (got, want)))

    def bool_cell(name, cond, why="", group=None):
        cells.append((name, group or name.split("-")[0], bool(cond), why))

    # ---- 版本面 ----
    cell("versions-parse", dist_versions('x\nproject__version = "0.3.10";\ny'), ["0.3.10"], "版本解析")
    cell("versions-dedup", dist_versions('a project__version = "0.3.9"; b project__version = "0.3.9";'),
         ["0.3.9"], "版本解析")
    cell("versions-multi", dist_versions('project__version = "0.3.9"; project__version = "0.3.10";'),
         ["0.3.9", "0.3.10"], "版本解析")
    cell("judge-same", judge('project__version = "0.3.10";', "0.3.10")[0], 0, "版本判定")
    cell("judge-stale-is-1", judge('project__version = "0.3.9";', "0.3.10")[0], 1, "版本判定")
    cell("judge-mixed-is-1", judge('project__version = "0.3.9"; project__version = "0.3.10";', "0.3.10")[0],
         1, "版本判定")
    cell("judge-no-sample-is-2", judge("nothing here", "0.3.10")[0], 2, "版本判定")
    cell("judge-no-baseline-is-2", judge('project__version = "0.3.10";', None)[0], 2, "版本判定")

    # ---- 内容面（BUG-428）：变异对照 + 变形容忍 + 字面量不喂绿 ----
    sym = (KEY_SYMBOLS[0],)
    fresh = 'project__version = "0.3.10";\nfunction _M0FP411x14omega__orphan__of__archived__parent(t) {}\n'
    plain = 'project__version = "0.3.10";\nfunction omega_orphan_of_archived_parent(t) {}\n'
    stale = 'project__version = "0.3.10";\nfunction something_else(t) {}\n'
    literal = 'project__version = "0.3.10";\n{"name":"omega_orphan_of_archived_parent","ok":1}\n'
    cell("content-fresh-mangled-is-0", judge_content(fresh, sym)[0], 0, "内容面")
    cell("content-fresh-plain-is-0", judge_content(plain, sym)[0], 0, "内容面")
    cell("content-stale-is-1", judge_content(stale, sym)[0], 1, "内容面")
    cell("content-string-literal-is-1", judge_content(literal, sym)[0], 1, "内容面")
    cell("content-empty-is-2", judge_content("", sym)[0], 2, "内容面")
    cell("count-calls-mangled", count_calls(fresh, sym[0].name), 1, "内容面")

    # ---- 两面合成（事故确诊句：版本 PASS ≠ 代码新）----
    cell("snapshot-both-ok-is-0", judge_snapshot(fresh, "0.3.10", sym)[0], 0, "两面合成")
    cell("snapshot-version-ok-code-old-is-1", judge_snapshot(stale, "0.3.10", sym)[0], 1, "两面合成")
    rc, lines = judge_snapshot(stale, "0.3.10", sym)
    bool_cell("snapshot-names-code-old", any("版本对但代码旧" in ln for ln in lines),
              "lines=%r" % (lines,), "两面合成")
    cell("snapshot-version-bad-is-1", judge_snapshot(stale, "0.3.9", sym)[0], 1, "两面合成")
    cell("snapshot-no-version-is-2", judge_snapshot("no version here", "0.3.10", sym)[0], 2, "两面合成")

    # ============================ 描述面（第三面 · BUG-578 遗留②）============================
    # D_NEW 带「尚未实现」+ 反引号具名符号 ⇒ 它必须被判在 S2 关注面上（复用 claim_lines 的口径）
    D_NEW = "登记公钥；已有公钥且与本次不同 ⇒ 拒绝，须走轮换（自动轮换尚未实现，需先 `agent_revoke_key`）。"
    D_OLD = "已有公钥且与本次不同 ⇒ 拒绝（需走轮换，尚未实现）。"
    D_PLAIN = "普通描述，不带负面句式也不带反引号具名符号。"
    D_ESC = '参数 by(可选，默认 \\"human_steward\\")。'      # 源码写法含反斜杠 ⇒ 应被转义闸门挡掉
    D_BLANK = ""                                            # 空串：任何正文都「原样命中」= 假绿发生器

    def mk_dist(name, desc):
        return ('project__version = "0.3.10";\n'
                's1 = _M0FP411vicTop_2dcw10fist_2dmbt3src6server18instrumented__tool('
                '_tmp$158, "%s", "%s", schema([]), (args, _cont) => {});\n' % (name, desc))

    dist_ok = mk_dist("agent_register_key", D_NEW)
    # (i) 变异对照 · 换成旧句 ⇒ 必红，并点名 refresh_dist.py
    rc1, l1, s1 = judge_desc([("agent_register_key", D_NEW)], mk_dist("agent_register_key", D_OLD))
    cell("desc-old-sentence-is-1", rc1, 1, "描述面")
    bool_cell("desc-names-refresh", any("refresh_dist.py" in ln for ln in l1), "lines=%r" % (l1,), "描述面")
    bool_cell("desc-names-changed-verb", any("src 已改口、dist 还烤着旧句" in ln for ln in l1),
              "lines=%r" % (l1,), "描述面")
    # (i-续) 变异对照 · 把那句从 bundle 里抽平（整条调用点换成无关文本）⇒ 必红
    rc1b, _l1b, _sb = judge_desc(
        [("agent_register_key", D_NEW)],
        'project__version = "0.3.10";\ns1 = _M0FP411x18instrumented__tool(_t, "other_tool", "无关句子。", s);\n')
    cell("desc-flattened-is-1", rc1b, 1, "描述面")
    # (ii) src 夹具与 dist 夹具一致 ⇒ 不红
    rc0, l0, s0 = judge_desc([("agent_register_key", D_NEW)], dist_ok)
    cell("desc-equal-fixtures-is-0", rc0, 0, "描述面")
    bool_cell("desc-clean-line-counts", any("1/1 条描述串在 dist 原样命中" in ln for ln in l0),
              "lines=%r" % (l0,), "描述面")
    # S2 关注面判据确实**来自** check_stale_self_claim（负面句式 / 反引号具名符号 / 都不带）
    bool_cell("s2-face-neg-phrase", on_s2_face(D_NEW), "", "S2 复用")
    bool_cell("s2-face-backtick-symbol", on_s2_face("请先 `store_open` 再发布。"), "", "S2 复用")
    bool_cell("s2-face-plain-not-flagged", not on_s2_face(D_PLAIN), "", "S2 复用")
    bool_cell("s2-face-counted-in-stats", s0["s2"] == 1, "stats=%r" % (s0,), "S2 复用")
    # 转义闸门：src 写法含反斜杠、bundle 写法不同形 ⇒ 不判（假红防线），且必须**报数**
    rcE, _lE, sE = judge_desc([("t_a", D_PLAIN), ("t_b", D_ESC)],
                              mk_dist("t_a", D_PLAIN) + mk_dist("t_b", '参数 by(可选，默认 "human_steward")。'))
    cell("desc-escaped-not-judged-is-0", rcE, 0, "转义闸门")
    bool_cell("desc-escaped-counted", sE["escaped"] == 1 and sE["judged"] == 1, "stats=%r" % (sE,), "转义闸门")
    # 空描述串绝不进判定面（空串在任何正文里都「原样命中」= 假绿发生器）
    rcB, _lB, sB = judge_desc([("t_a", D_PLAIN), ("t_b", "   ")], mk_dist("t_a", D_PLAIN) + mk_dist("t_b", "有内容。"))
    bool_cell("desc-blank-excluded", sB["blank"] == 1 and sB["judged"] == 1, "stats=%r" % (sB,), "转义闸门")
    cell("desc-blank-is-0", rcB, 0, "转义闸门")
    # (iii) 三档自拒：src 无样本 / dist 正文空 / bundle 反解不到调用点
    cell("desc-no-src-pairs-is-2", judge_desc([], dist_ok)[0], 2, "自拒档")
    cell("desc-no-dist-text-is-2", judge_desc([("t", D_PLAIN)], "")[0], 2, "自拒档")
    cell("desc-no-callsite-is-2", judge_desc([("t", D_PLAIN)], "var x = 1; // 没有注册点\n")[0], 2, "自拒档")
    cell("desc-all-escaped-is-2", judge_desc([("t", D_ESC)], dist_ok)[0], 2, "自拒档")
    # 反向面（差集的另一半）：dist 多出 src 已删的工具名 ⇒ 红，且点名「src 已删、dist 还整条烤着」
    rcX, lX, sX = judge_desc([("t_a", D_PLAIN)], mk_dist("t_a", D_PLAIN) + mk_dist("t_ghost", D_PLAIN))
    cell("desc-extra-tool-in-dist-is-1", rcX, 1, "反向面")
    bool_cell("desc-extra-names-ghost", any("t_ghost" in ln for ln in lX), "lines=%r" % (lX,), "反向面")
    bool_cell("desc-extra-wording", any("src 已删、dist 还整条烤着" in ln for ln in lX),
              "lines=%r" % (lX,), "反向面")
    # 脱锚自拒：几乎全不命中 ≠「dist 旧」，那是尺子对不上打包形态 ⇒ 2，绝不冒用 1
    many = [("t%02d" % i, "描述句子 %d。" % i) for i in range(12)]
    cell("desc-total-desync-is-2", judge_desc(many, mk_dist("t00", "别的句子。"))[0], 2, "自拒档")
    # 取数面自证：真 src 与真 bundle 都反解得出来（地板不是读数，掉到地板就是解析器脱锚）
    rpairs, runparsed = src_tool_pairs()
    bool_cell("src-parse-anchor-ge-50", len(rpairs) >= 50, "解析到 %d 条（unparsed=%d）" % (len(rpairs), runparsed),
              "取数面")
    bool_cell("src-parse-names-are-tool-names",
              all(NAME_RE.match(n) for n, _d in rpairs), "有名字不像工具名", "取数面")
    dtext = io.open(DIST, encoding="utf-8", errors="replace").read() if os.path.isfile(DIST) else ""
    bool_cell("dist-parse-anchor-ge-50", len(dist_tool_pairs(dtext)) >= 50,
              "bundle 反解到 %d 个调用点" % len(dist_tool_pairs(dtext)), "取数面")
    # 现状面自证（不判红不判绿，只证明三面合码的优先级：2 压过 1）
    cell("worst-2-beats-1", _worst((1, 2, 0)), 2, "合码")
    cell("worst-1-beats-0", _worst((1, 0)), 1, "合码")
    cell("worst-all-0", _worst((0, 0)), 0, "合码")

    # ---- 变异对照：改坏**真代码行**（判例-30：改注释不算变异），替换点必须恰 1 处 ----
    self_lines = io.open(os.path.abspath(__file__), encoding="utf-8").read().split("\n")

    def mutate(target, repl):
        idx = [i for i, ln in enumerate(self_lines) if ln.strip() == target]
        if len(idx) != 1:
            return None, len(idx)
        out = list(self_lines)
        indent = len(self_lines[idx[0]]) - len(self_lines[idx[0]].lstrip())
        out[idx[0]] = " " * indent + repl
        return "\n".join(out), len(idx)

    SELF = os.path.abspath(__file__)

    def exec_mutated(src_text, tag):
        ns = dict(globals())
        ns["__name__"] = tag
        exec(compile(src_text, tag, "exec"), ns)
        return ns

    m1, n1 = mutate("if desc in dist_text:", "if True:")
    bool_cell("mutation-membership-anchor-exactly-one", m1 is not None and n1 == 1,
              "命中数=%d（要求恰 1）；候选行样例：%s" % (
                  n1, [ln.strip()[:52] for ln in self_lines if "in dist_text" in ln][:4]), "变异对照")
    if m1 is not None:
        ns1 = exec_mutated(m1, "mut_membership")
        got_rc = ns1["judge_desc"]([("agent_register_key", D_NEW)],
                                   mk_dist("agent_register_key", D_OLD))[0]
        # 闸门摘掉 ⇒ 旧句夹具不再红 ⇒ 证明那一行就是「看不看得到旧句」的承重件
        bool_cell("mutation-membership-really-fires", got_rc == 0,
                  "摘掉命中判定后夹具 rc=%r（期望 0 = 尺失明）" % (got_rc,), "变异对照")

    m2, n2 = mutate("if BS in desc:", "if False:")
    bool_cell("mutation-escape-gate-anchor-exactly-one", m2 is not None and n2 == 1,
              "命中数=%d（要求恰 1）；候选行样例：%s" % (
                  n2, [ln.strip()[:52] for ln in self_lines if "BS in desc" in ln][:4]), "变异对照")
    if m2 is not None:
        ns2 = exec_mutated(m2, "mut_escape_gate")
        got_rc2 = ns2["judge_desc"]([("t_a", D_PLAIN), ("t_b", D_ESC)],
                                    mk_dist("t_a", D_PLAIN) + mk_dist("t_b", "参数 by(可选，默认 \"human_steward\")。"))[0]
        # 闸门摘掉 ⇒ 转义不同形的句子被判成旧句 ⇒ 假红 ⇒ 证明闸门在承重
        bool_cell("mutation-escape-gate-really-fires", got_rc2 == 1,
                  "摘掉转义闸门后夹具 rc=%r（期望 1 = 假红）" % (got_rc2,), "变异对照")

    m3, n3 = mutate("if not desc.strip():", "if False:")
    bool_cell("mutation-blank-gate-anchor-exactly-one", m3 is not None and n3 == 1,
              "命中数=%d（要求恰 1）" % (n3,), "变异对照")
    if m3 is not None:
        ns3 = exec_mutated(m3, "mut_blank_gate")
        rc3 = ns3["judge_desc"]([("t_a", D_BLANK)], mk_dist("t_a", "任何句子。"))[0]
        # 空串闸门摘掉 ⇒ 空描述串进判定面 ⇒ rc=0（假绿）；有闸门时是 rc=2（无样本，拒绝出结论）
        bool_cell("mutation-blank-gate-really-fires",
                  rc3 == 0 and judge_desc([("t_a", D_BLANK)], mk_dist("t_a", "任何句子。"))[0] == 2,
                  "摘掉空串闸门后 rc=%r（期望 0 = 假绿发生器被放行）" % (rc3,), "变异对照")

    m4, n4 = mutate("if len(missing) >= 10 and len(missing) * 5 >= len(judged) * 4:", "if False:")
    bool_cell("mutation-desync-gate-anchor-exactly-one", m4 is not None and n4 == 1,
              "命中数=%d（要求恰 1）" % (n4,), "变异对照")
    if m4 is not None:
        ns4 = exec_mutated(m4, "mut_desync_gate")
        got_rc4 = ns4["judge_desc"](many, mk_dist("t00", "别的句子。"))[0]
        bool_cell("mutation-desync-gate-really-fires", got_rc4 == 1,
                  "摘掉脱锚闸后 rc=%r（期望 1 = 把尺子坏了冒报成 dist 旧）" % (got_rc4,), "变异对照")

    # ---- 调用面（四档退出码必须由真 run() 给出，不是另造一个解析器）----
    unk_rc, unk_out = _quiet_run(["--definitely-not-real"])
    cell("call-face-unknown-flag-rc2", unk_rc, 2, "调用面")
    bool_cell("call-face-unknown-flag-names-whitelist", "--selftest" in unk_out and "--list" in unk_out,
              "拒绝未知旗标时没点名白名单：%r" % (unk_out[:120],), "调用面")
    # `--self-test`（多一个连字符）必须**同样被拒**，否则 R207 那一族又回来了
    cell("call-face-selftest-hyphen-not-accepted", _quiet_run(["--self-test"])[0], 2, "调用面")
    # --list 走真仓（只读），rc 必须是 0/1/2 中的一档且**绝不**是 4（尺子自己坏了）
    list_rc, list_out = _quiet_run(["--list"])
    cell("call-face-list-rc-not-4", list_rc in (0, 1, 2), True, "调用面")
    bool_cell("call-face-list-prints-clauses", "S2 关注面" in list_out,
              "清单面没打印关注面计数（rc=%r）" % (list_rc,), "调用面")

    bad = [(n, w) for n, _g, ok, w in cells if not ok]
    groups = []
    for _n, g, _ok, _w in cells:
        if g not in groups:
            groups.append(g)
    scope = " + ".join("%s %d" % (g, sum(1 for _n, gg, _o, _w in cells if gg == g)) for g in groups)
    if bad:
        print("SELFTEST FAIL（%d/%d）：" % (len(bad), len(cells)))
        for n, w in bad:
            print("  - %s：%s" % (n, w))
        return 1
    # 范围自述**从已执行格子反解**，不手写计数（J10：少写=声明滞后、多写=幻影判据）
    print("SELFTEST OK（%d 格：%s，全部真断言；变异对照见「变异对照」组）" % (len(cells), scope))
    return 0


def _entry_probe() -> None:
    """入口面自证（R171 口径）：自检必须把入口纳入调用图。

    为什么要有这一格：R158 交付 check_diff_scope.py 时 `--selftest` 全绿而**现状面一跑就崩**
    （clean 分支少传一个实参抛 TypeError，冒出来的 rc=1 和「有违例」一模一样）。自检只考纯函数、
    不碰入口，照不出「自检面与入口面脱钩」。本探测**零副作用**：只验证入口存在且可调用，
    不起服务、不碰网络、不跑真桥。
    """
    if not callable(main):
        raise SystemExit("入口 main 不可调用（自检面与入口面脱钩）")


_KNOWN_FLAGS = ("--selftest", "--list")


def run(argv):
    """参数面 + 三面判定。argv 是**已切掉 argv[0]** 的参数表（自检的调用面格直接喂它）。"""
    unknown = [a for a in argv if a.startswith("-") and a not in _KNOWN_FLAGS]
    if unknown:
        print("[FATAL] 未知参数 %s —— 已知：%s（rc=2）" % (" ".join(unknown), " / ".join(_KNOWN_FLAGS)))
        return 2
    # ↑ 严格参数面（R65/R207）：未知旗标不再被静默忽略（`--self-test` 拼错会假绿）
    if "--selftest" in argv:
        return selftest()
    if not os.path.isfile(DIST):
        print("FATAL 找不到 dist/fist-mbt.js —— 判据无样本，拒绝报绿")
        return 2
    text = io.open(DIST, encoding="utf-8", errors="replace").read()
    rc_snap, lines = judge_snapshot(text, moon_version())
    pairs, unparsed = src_tool_pairs()
    rc_desc, dlines, st = judge_desc(pairs, text, unparsed)
    rc = _worst((rc_snap, rc_desc))
    lines = lines + dlines
    tag = {0: "PASS", 1: "FAIL", 2: "FATAL"}[rc]
    print("%s dist 快照：" % tag)
    for line in lines:
        print("  %s" % line)
    if "--list" in argv:
        s2 = [n for n, d in pairs if on_s2_face(d) and BS not in d]
        print("  [清单] S2 关注面 %d 条：%s" % (len(s2), " / ".join(sorted(s2))))
        print("  [清单] 转义闸门挡掉 %d 条：%s" % (
            st["escaped"], " / ".join(sorted(n for n, d in pairs if BS in d and d.strip()))))
        print("  [清单] 空串挡掉 %d 条 · 注册形态未解析 %d 条 · bundle 调用点 %d 个" % (
            st["blank"], unparsed, st["dist"]))
    if rc == 1:
        print("  刷新（一条命令，重建+注入 ESM shim+拷贝）：python scripts/refresh_dist.py")
        print("  注意：当前 moonc 世代产出的 bundle 比仓内快照大（实测 release 108k 行 vs 快照 83k 行），"
              "刷新会带来大 diff 属预期——快照本就该由发布流程产出。")
    if rc == 2 and rc_desc == 2:
        print("  [说明] 描述面回的是 rc=2（判据无法自证），不是「dist 旧」——"
              "先看上面那一行的原因，再决定是核尺还是刷快照。")
    return rc


def _quiet_run(argv):
    """静音跑真 run()，返回 (rc, 捕获的 stdout)。调用面格子用它，免得自检输出被真仓读数刷满。

    走的是**真 run()**（含真参数面与四档出口），不是另造一个解析器（判例-29：机制格 ≠ 实现路径格）。
    """
    import contextlib

    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            rc = run(argv)
    except SystemExit as exc:
        rc = int(exc.code if exc.code is not None else 0)
    return rc, buf.getvalue()


def main():
    return run(sys.argv[1:])


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as exc:  # noqa
        import traceback
        traceback.print_exc()
        print("[FATAL] 尺子自己坏了：%r ⇒ rc=4（绝不冒用 1 那一档）" % (exc,))
        sys.exit(4)

