#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""scripts/check_deprecated_site_list.py — 语义族「站点清单 + 结构归属」读数器（BUG-362 追记 / R38）。

为什么还要第三支尺。`check_deprecated_text_census.py` 的族表只收**语法族**（判据发火的那个 token
在源码文本里就长得一样），它的 `--dump-distribution` 回答「每个形状几处」。剩下六族既进不了那张表、
形状读数也不够拍板——owner 要裁「改 / 不改 / 挂账」，需要的是**每一处到底长在什么结构上**。
本工具把判据行逐个落成 `file:line:col` + 精确源码切片 + 结构归属，出一份可裁决的证据单。

实测（2026-10-21，`temp/chk44.json` = `moon check --target js --json`，489 诊断 / 0 error）：
  0020 `Use Debug instead of Show ...`        判据行 8 / 站点 8
  0020 `Use @debug.Debug instead ... collections` 判据行 3 / 站点 3——**三处全部与前 8 处重合**
      ⇒ Show 并集站点是 **8 个**而不是 11 个。清掉这 8 个站点，11 条判据行一起消失。
      行级普查的两种失真在这里同框：静默少报（判据 < 文本，BUG-362 本体）与重复计费（行数 > 站点数）。
  0020 `Array` in JavaScript FFI              3 处，全在 `extern "js" fn` 的形参行上，而这**三行本身
      没有 extern token**（抬头在其上 1 行）⇒ 行级正则「读得到形状、读不到归属」，正是上一单说的那个跨行事实。
  0020 `run` 隐式提升                          1 处：`ex.run(task, ctx)`，判据文本自己点名来源 impl
  0027 `derive(Show)`                          1 处：`} derive(Eq, Debug, Show)`——**Debug 已经在 derive 列表里**，
      所以这一处的改法是删一个 token，不是补一套实现。
  0078 `Result[T, E]`                          3 处，全是**私有**转换辅助（`fn to_result` / `fn to_ids_result`）的返回类型

六族合计（本工具自己在 chk44 上的表头读数）：**判据行 19 / 站点 16 / 文件 11**。
另有 3 条 utf8 (`Check @encoding/utf8.encode`) 判据行**不在本清单**——那族能进棘轮表，由
`check_deprecated_text_census.py` 判红；两支尺收同一个族，一旦其中一支改口径就会互相掩盖。
（同一份 dump 若按 code∈{20,27,78} 且剔除 Json::value 去数，是 22 行 / 19 站点，多的正是那 3 条。）

扫描宇宙必须是 git 跟踪面（`git ls-files "*.mbt"`），与普查棘轮同一条律：宇宙变了数字就没有可比性。
S3「站点文件不在跟踪面内」在这支尺上比在那支上更要紧——本工具**每个站点都要开文件切片**，宇宙指错会
当场现形而不是悄悄少几处。

判据（全部是「能不能读」，没有一条是「读得好不好」）：
  S1 dump 可解析、`diagnostics` 是非空数组 ⇒ 否则 rc=2（上一单实测：一份新 dump 的 `messages` 键是空的、
     489 条在 `diagnostics` 里，按错键读得到「判据 0 处」的静默假绿——本工具把键名形状钉成硬前置）
  S2 跟踪面 .mbt 文件数 ≥ 下限 ⇒ 否则 rc=2
  S3 站点文件越出跟踪面 ⇒ rc=2 并点名
  S4 loc 的行号越界 / 列切片为空 ⇒ rc=2 并点名（防 dump 与源码不同步，读出来的是不存在的站点）
  S5 某族所有站点的切片都不含本族点名的符号 ⇒ rc=2 并说明「loc 口径漂移」（列语义若从「起始列」改成别的，
     切片会指向错位字符而不只是少几处；这一格让尺子在**读歪**时自拒，而不是拿歪读数出一份漂亮清单）
  S6 族读到 0 处 ⇒ 照常 rc=0，但打印「不构成已清空」的免责句——本工具不判红，也不替读者把「没读到」翻译成「没有」

退出码：只可能 0 或 2，**永远不给 1，不挂 CI**。与 `--dump-distribution` 同一条律：一份报告没有资格判红，
把「读到了什么」和「这算不算缺陷」分开，才不能让一次工具链升级用红门的形式说出「大概没事」。

两支真数据变异对照（`temp/chk44.json` 各 489 条，不是合成件）：
  M1 判据文本漂移（把 6 族 marker 各改一个字母，命中 19 条）⇒ rc=0，但打出「全清单 6 族都读到 0 处，
     而诊断面非空 ⇒ 大概率是判据文本漂移而不是族已清空」并把读者指回 `--dump-distribution` 对 code 面。
     这是本清单与棘轮表的**故意不同**：表持有上限，marker 漂移会让 R2/R3 现形；清单不持有上限，
     所以只能把「没读到」这一读法本身点名，没有资格判红。
  M2 列口径漂移（表内族 loc 的起止列整体 +3）⇒ rc=2，`FATAL S5 本族全部 3 个站点的切片都不含本族点名的
     符号（期望 'Array'）`。一条实测出的不对称：只有**判据文本点名的符号可对撞**的族（Array / Show(0027) /
     Result）能自证列口径；Show 的 0020 判据不点名 token，同样这份变异里它 8 个站点全读成「未分类」——
     数字不会自拒，但小结会一片「未分类」，那就是进料信号。

用法：
    python scripts/check_deprecated_site_list.py temp/chk44.json   # 出证据单
    python scripts/check_deprecated_site_list.py --selftest        # 20 支对照考这把尺自己
"""
import io
import json
import os
import re
import subprocess
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MIN_TRACKED_MBT = 100

EMPTY_DIAGS_MSG = (
    "S1 诊断面为空 —— moon check 没真跑、dump 截断，或这份 dump 里确实没有本清单的族；"
    "三种情况在这把尺上必须分开，不能一律读成「都改完了」")

# 本清单只收**进不了文本棘轮表**的族（语义族 / 跨行归属族 / 缺席型族）。
# 能进表的（Json::value、utf8.encode）由 check_deprecated_text_census.py 判红，这里不收——
# 两支尺收同一个族，一旦其中一支改口径就会互相掩盖。
SITE_FAMILIES = [
    {
        "key": "show-debug",
        "error_code": 20,
        "judge_marker": "Use Debug instead of Show",
        "resolver": "show",
        "bucket": "形状",
        "slice_expect": None,
        "target_form": "@debug.Debug（或手写 Show 实现）",
        "why_untabled": (
            "弃用点在语义（这个表达式的值被 Show 打印），不在名称：`\\bShow\\b` 全仓 2 处对判据 8 处，"
            "且那 2 处与判据行无一重合；站点散在 .to_string() / 插值 / inspect() 三种写法。"),
    },
    {
        "key": "show-collections",
        "error_code": 20,
        "judge_marker": "instead of `Show` for collections",
        "resolver": "show",
        "bucket": "形状",
        "slice_expect": None,
        "target_form": "@debug.Debug",
        "why_untabled": (
            "同上，且与 show-debug 打在**同一批站点**上（实测 3/3 重合）——按行登记会把同一次改动计费两遍。"),
    },
    {
        "key": "js-ffi-array",
        "error_code": 20,
        "judge_marker": "Using `Array` in JavaScript FFI",
        "resolver": "ffi",
        "bucket": "行级正则能否单独判定",
        "slice_expect": r"Array",
        "target_form": "FixedArray[T]",
        "why_untabled": (
            "归属是跨行事实：判据落在形参行 `args : Array[String],` 上，extern \"js\" 抬头在其上 1 行；"
            "而 `: Array[` 全仓 953 处（绝大多数不是 FFI），站点并集入表会得到荒谬缺口。"),
    },
    {
        "key": "implicit-promotion",
        "error_code": 20,
        "judge_marker": "is implicitly promoted from",
        "resolver": "promotion",
        "bucket": "站点是否在 impl 体内",
        "slice_expect": None,
        "target_form": "显式限定调用（`Type::method(recv, ...)` 或 trait 限定）",
        "why_untabled": (
            "判据只 1 处，文本面 `.run(` 有 7 处且其中 6 处不是提升调用——隐式提升由「方法只存在于 impl」"
            "这一语义决定，行级正则判不了哪一个才是提升来的。"),
    },
    {
        "key": "derive-show",
        "error_code": 27,
        "judge_marker": "`derive(Show)` is deprecated",
        "resolver": "derive",
        "bucket": "Debug 已在列表",
        "slice_expect": r"Show",
        "target_form": "derive(Debug) 已有则删 Show；否则补 Show 实现",
        "why_untabled": (
            "本族是**语法族**却仍不收进表：0027 与 0020 是两个 code，判据形状不同；且实测照字面写 "
            "`derive(Show)` 普查读 0（真身是 `derive(Eq, Debug, Show)`），必须 `derive\\([^)]*\\bShow\\b` 才对得上。"),
    },
    {
        "key": "result-error-return",
        "error_code": 78,
        "judge_marker": "Prefer `T raise E`",
        "resolver": "result",
        "bucket": "可见性",
        "slice_expect": r"Result",
        "target_form": "`T raise E`（失败用异常）或保留 Result（需写明为何要当普通数据表示）",
        "why_untabled": (
            "缺席型判据：0078 报的是「该用 raise 而没用」，判据面 3 对全仓 `Result[` 437 处——"
            "文本面无法代理语义面，判据面自己才是清单。"),
    },
]


def tracked_mb_files():
    """扫描宇宙 = git 跟踪的 .mbt（POSIX 分隔的仓库相对路径），与普查棘轮同源同律。"""
    out = subprocess.run(
        ["git", "ls-files", "*.mbt"],
        cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    if out.returncode != 0:
        raise RuntimeError("git ls-files 失败：%s" % (out.stderr.strip() or "rc=%d" % out.returncode))
    return sorted(p for p in out.stdout.replace("\\r", "").split("\n") if p)


def rel_of(path):
    p = os.path.normpath(str(path)).replace("\\", "/")
    root = os.path.normpath(ROOT).replace("\\", "/")
    return p[len(root) + 1:] if p.startswith(root + "/") else p


LOC_RE = re.compile(r"^\s*(\d+):(\d+)-(\d+):(\d+)")
# 顶层条目抬头：MoonBit 的 item 关键字都写在 0 缩进处，缩进行只可能是续行。
ITEM_RE = re.compile(
    r"^(pub |private |const |)(test|extern|impl|fn|struct|enum|type|abstract|extension|method|let|const|include|import)\b")


def item_header(lines, idx):
    """自站点行（0 基 idx）向上找最近的顶层条目抬头。读不到返回 None，不猜。"""
    for i in range(idx, -1, -1):
        line = lines[i]
        m = ITEM_RE.match(line)
        if not m:
            continue
        kind = m.group(2)
        name = ""
        if kind == "impl":
            t = re.search(r"\bimpl\s+([\w.]+)\s+for\s+([\w.]+)", line)
            name = "%s for %s" % (t.group(1), t.group(2)) if t else line.strip()[:40]
        elif kind == "test":
            t = re.search(r"test\s+\"([^\"]*)\"", line)
            name = t.group(1)[:40] if t else "test"
        else:
            t = re.search(r"\b(?:fn|method|struct|enum|type|trait)\s+(?:#[^\s]*\s+)?([\w.:#]+)", line)
            name = t.group(1) if t else line.strip()[:40]
        return {"kind": kind, "name": name, "line": i + 1,
                "text": line.rstrip()[:100], "public": line.startswith("pub ")}
    return None


def norm_rows(payload):
    """dump -> 行字典列表。列语义按 loc 的「行:起始列-行:结束列」，切片用 line[c1-1:c2]（实测与真源逐字对齐）。"""
    rows = []
    for d in payload.get("diagnostics", []):
        m = LOC_RE.match(str(d.get("loc", "")))
        if not m:
            continue
        rows.append({
            "file": rel_of(d.get("path", "")),
            "line": int(m.group(1)), "c1": int(m.group(2)), "c2": int(m.group(4)),
            "same_line": m.group(1) == m.group(3),
            "code": int(d.get("error_code") or -1),
            "msg": str(d.get("message", "")),
        })
    return rows


def next_item_line(lines, hdr_line):
    """某顶层条目的粗界：下一个顶层条目起始行（1 基），没有就给文件末行 +1。"""
    for i in range(hdr_line, len(lines)):
        if ITEM_RE.match(lines[i]):
            return i + 1
    return len(lines) + 1


def backquote(msg, pattern):
    m = re.search(pattern, msg)
    return m.group(1) if m else ""


# ------------------------- 结构归属解算 -------------------------

def resolve_show(site, fam, lines, msg):
    line = lines[site["line"] - 1]
    tok = site["token"]
    prefix = line[: site["c1"] - 1]
    hdr = item_header(lines, site["line"] - 1)
    if tok.startswith("to_string("):
        shape = "to_string() 调用"
        obj = backquote(line[: site["c2"]], r"([\w.\[\]]+)\.to_string\(") or "(接收者不可辨)"
    elif "\\{" in prefix and tok.rstrip().endswith("}"):
        shape = "字符串插值 \\{...}"
        obj = tok.rstrip()[:-1].lstrip("\\{") or "(空插值)"
    elif prefix.rstrip().endswith("inspect("):
        shape = "inspect() 实参"
        obj = tok.rstrip(",")
    elif prefix.rstrip().endswith("("):
        shape = "函数实参"
        obj = tok.rstrip(",")
    else:
        shape = "未分类（本清单没见过这种写法）"
        obj = tok
    face = "测试面" if hdr and hdr["kind"] == "test" else "生产面"
    return {
        "形状": shape,
        "被 Show 打印的对象": obj,
        "所在条目": ("%s %s（第 %d 行，%s）" % (hdr["kind"], hdr["name"], hdr["line"], "pub" if hdr["public"] else "私有")) if hdr else "读不到条目抬头",
        "改动波及": "%s｜%s" % (face, "只动断言/快照文本" if face == "测试面" else "动用户可见输出"),
    }


def resolve_ffi(site, fam, lines, msg):
    line = lines[site["line"] - 1]
    hdr = item_header(lines, site["line"] - 1)
    is_extern = bool(hdr) and hdr["kind"] == "extern"
    depth = (site["line"] - hdr["line"]) if hdr else -1
    tok = site["token"].rstrip(",")
    prefix = line[: site["c1"] - 1]
    param = re.search(r"([a-z_][\w]*)\s*:\s*$", prefix)
    span = re.match(r"([A-Za-z]+)\[([^\]]*)\]", tok)
    return {
        "归属": ("extern \"js\" 形参" if is_extern else "抬头不是 extern（本族判据不该落在这里，需人工看）"),
        "抬头": ("第 %d 行 `%s`" % (hdr["line"], hdr["text"])) if hdr else "读不到抬头",
        "跨行距离": "%d 行" % depth,
        "行级正则能否单独判定": ("能（extern 与本行同行）" if depth == 0 else
                          "不能（本行无 extern token，归属在上方 %d 行）" % depth),
        "形参": param.group(1) if param else "(未识别)",
        "类型": "%s[%s]" % (span.group(1), span.group(2)) if span else tok,
        "建议替换": "%s[%s]" % ("FixedArray", span.group(2)) if span else "(形状不可辨)",
    }


def resolve_promotion(site, fam, lines, msg):
    method = backquote(msg, r"The method `([^`]+)`")
    impl_src = backquote(msg, r"implicitly promoted from `([^`]+)`")
    target = backquote(msg, r"either use `([^`]+)`")
    hdr = item_header(lines, site["line"] - 1)
    t = re.match(r"impl\s+([\w.]+)\s+for\s+([\w.]+)", impl_src)
    defs = []
    if t:
        pat = re.compile(r"^impl\s+%s\s+for\s+%s\b" % (re.escape(t.group(1)), re.escape(t.group(2))))
        for i, l in enumerate(lines):
            if pat.match(l):
                defs.append(i + 1)
    spans = [(d, next_item_line(lines, d) - 1) for d in defs]
    inside = [x for x in spans if x[0] <= site["line"] <= x[1]]
    return {
        "被提升的方法": method or "(判据文本没点名)",
        "提升来源（判据自述）": impl_src or "(判据文本没给)",
        "trait/type": ("%s ← %s" % (t.group(1), t.group(2))) if t else "(不可解析)",
        "该 impl 在本文件内的行": ",".join(str(x) for x in defs) if defs else "本文件内没找到（impl 在别处）",
        "站点所在条目": ("%s %s（第 %d 行）" % (hdr["kind"], hdr["name"], hdr["line"])) if hdr else "读不到条目抬头",
        "站点是否在 impl 体内": ("是" if inside else ("否" if spans else "未判（本文件找不到判据自述的 impl）")),
        "impl 段落（粗界）": " / ".join("第 %d–%d 行" % x for x in spans) if spans else "-",
        "建议替换": target or "(判据文本没给)",
    }


def resolve_derive(site, fam, lines, msg):
    line = lines[site["line"] - 1]
    hdr = item_header(lines, site["line"] - 1)
    d = re.search(r"derive\(([^)]*)\)", line)
    items = [x.strip() for x in d.group(1).split(",")] if d else []
    return {
        "derive 列表": ", ".join(items) if items else "(本行没有 derive(...))",
        "条目": ("%s %s（第 %d 行）" % (hdr["kind"], hdr["name"], hdr["line"])) if hdr else "读不到条目抬头",
        "Debug 已在列表": ("是" if "Debug" in items else "否"),
        "改法": ("删掉 Show 一个 token 即可，不用补实现" if "Debug" in items
                 else "要么换成 Debug，要么手写 Show 实现"),
        "建议替换": backquote(msg, r"Use `([^`]+)`") or "(判据文本没给)",
    }


def resolve_result(site, fam, lines, msg):
    hdr = item_header(lines, site["line"] - 1)
    return {
        "所在函数": ("%s（第 %d 行）" % (hdr["name"], hdr["line"])) if hdr else "读不到抬头",
        "可见性": ("pub（对外契约面）" if hdr and hdr["public"] else "私有（内部转换辅助）") if hdr else "未判",
        "跨行距离": "%d 行" % (site["line"] - hdr["line"]) if hdr else "-",
        "返回类型切片": site["token"].strip(),
        "站点在签名还是体": ("签名返回类型" if "->" in lines[site["line"] - 1][: site["c1"] - 1] + site["token"]
                     else "其他位置"),
        "建议替换": "`T raise E`（或说明为何必须把成功/失败当普通数据）",
    }


RESOLVERS = {
    "show": resolve_show,
    "ffi": resolve_ffi,
    "promotion": resolve_promotion,
    "derive": resolve_derive,
    "result": resolve_result,
}


# ------------------------- 主读数 -------------------------

def site_list(families, diags, universe, sources, min_tracked=MIN_TRACKED_MBT):
    """返回 (rc, 行列表)。rc 只可能是 0 或 2——见 docstring「报告和裁决分开」。"""
    out = []
    fatal = []
    if not diags:
        return 2, [EMPTY_DIAGS_MSG]
    if len(universe) < min_tracked:
        return 2, ["S2 跟踪面 .mbt 文件数 = %d < 下限 %d —— 宇宙被换小或 git 不可用，读数没有可比性"
                   % (len(universe), min_tracked)]
    uni = set(universe)

    # 站点归并：同一 (file,line,c1,c2) 被多条判据文本命中，只算一个站点。
    rows_all = []
    for fam in families:
        for r in diags:
            if r["code"] == fam["error_code"] and fam["judge_marker"] in r["msg"]:
                rows_all.append((fam, r))
    by_key = {}
    for fam, r in rows_all:
        key = (r["file"], r["line"], r["c1"], r["c2"], r["same_line"])
        by_key.setdefault(key, {"rows": [], "fams": []})
        if fam["key"] not in [f["key"] for f in by_key[key]["fams"]]:
            by_key[key]["fams"].append(fam)
        by_key[key]["rows"].append(r["msg"])
    sites = {}
    for key, v in by_key.items():
        sites[key] = {"file": key[0], "line": key[1], "c1": key[2], "c2": key[3],
                      "same_line": key[4], "fams": v["fams"], "n_msgs": len(v["rows"]),
                      "msgs": v["rows"]}
    for key, s in sites.items():
        if s["file"] not in uni:
            fatal.append("S3 站点文件越出跟踪面：%s:%d" % (s["file"], s["line"]))
            continue
        text = sources.get(s["file"])
        if text is None:
            fatal.append("S4 站点文件读不到：%s" % s["file"])
            continue
        lines = text.splitlines()
        if not (1 <= s["line"] <= len(lines)):
            fatal.append("S4 行号越界：%s:%d（文件只有 %d 行）—— dump 与源码不同步"
                         % (s["file"], s["line"], len(lines)))
            continue
        line = lines[s["line"] - 1]
        if not s["same_line"]:
            fatal.append("S4 站点跨行（本清单只收单行站点，跨行需另行判读）：%s:%d" % (s["file"], s["line"]))
            continue
        tok = line[s["c1"] - 1:s["c2"]]
        if not tok.strip():
            fatal.append("S4 列切片为空：%s:%d:%d-%d 行文本=%r"
                         % (s["file"], s["line"], s["c1"], s["c2"], line[:60]))
            continue
        s["token"] = tok
        s["lines"] = lines

    if fatal:
        out.append("FATAL 站点清单读不出可比读数（%d 格）：" % len(fatal))
        for f in fatal:
            out.append("  " + f)
        out.append("  注：这是「尺子量不动」，不是「代码坏了」，所以给 2 不给 1")
        return 2, out

    out.append("站点清单（语义族 / 跨行归属族 / 缺席型族）—— 只读数，不判红")
    out.append("扫描宇宙 %d 个跟踪 .mbt；判据面命中 %d 行 / %d 个站点 / %d 个文件"
               % (len(uni), len(rows_all), len(sites), len({s["file"] for s in sites.values()})))
    dupes = [s for s in sites.values() if len(s["fams"]) > 1]
    if not rows_all:
        out.append("  全清单 %d 族都读到 0 处，而诊断面非空 ⇒ 大概率是判据文本漂移而不是族已清空；"
                   "先跑 check_deprecated_text_census.py --dump-distribution 对 code 面" % len(families))
    if dupes:
        out.append("其中 %d 个站点被本清单内多个族同时命中（行数>站点数的那部分，改一处消多行）：" % len(dupes))
        for s in sorted(dupes, key=lambda v: (v["file"], v["line"])):
            out.append("  %s:%d:%d  族=%s  判据文本 %d 条"
                       % (s["file"], s["line"], s["c1"], "+".join(f["key"] for f in s["fams"]), s["n_msgs"]))

    for fam in families:
        mine = sorted([s for s in sites.values() if any(f["key"] == fam["key"] for f in s["fams"])],
                      key=lambda v: (v["file"], v["line"], v["c1"]))
        n_rows = len([1 for f, r in rows_all if f["key"] == fam["key"]])
        out.append("")
        out.append("### 族 %s ｜ code %04d ｜ 判据文本「%s」" % (fam["key"], fam["error_code"], fam["judge_marker"]))
        out.append("  判据行 %d 处 / 站点 %d 个 / 文件 %d 个 ｜ 建议目标形态：%s"
                   % (n_rows, len(mine), len({s['file'] for s in mine}), fam["target_form"]))
        out.append("  为何进不了文本表：%s" % fam["why_untabled"])
        if not mine:
            out.append("  本族读到 0 处 —— 这不构成「已清空」的证据（dump 族面变了、marker 漂移，两种读法在这里同形）")
            continue
        buckets = {}
        drift = 0
        for s in mine:
            facts = RESOLVERS[fam["resolver"]](s, fam, s["lines"], s["msgs"][0])
            if fam["slice_expect"] and not re.search(fam["slice_expect"], s["token"]):
                drift += 1
            extra = ""
            if len(s["fams"]) > 1:
                others = [f["key"] for f in s["fams"] if f["key"] != fam["key"]]
                extra = "  〔同站还有 %s〕" % "+".join(others)
            out.append("  - %s:%d:%d-%d  切片 `%s`%s" % (s["file"], s["line"], s["c1"], s["c2"], s["token"], extra))
            for k, v in facts.items():
                out.append("      %s = %s" % (k, v))
            b = facts.get(fam["bucket"], "(缺分档)")
            buckets[b] = buckets.get(b, 0) + 1
        if drift == len(mine):
            out.append("  FATAL S5 本族全部 %d 个站点的切片都不含本族点名的符号（期望 %r）"
                       % (len(mine), fam["slice_expect"]))
            return 2, out
        out.append("  小结：" + " ｜ ".join("%s ×%d" % (k, v) for k, v in sorted(buckets.items())))

    out.append("")
    out.append("REPORT 站点清单读数完成（本工具不判红：只可能返回 0 或 2，且不挂 CI）")
    return 0, out


def load_dump(path):
    try:
        payload = json.loads(io.open(path, encoding="utf-8", errors="replace").read())
    except (OSError, ValueError) as exc:
        print("FATAL dump 读不出可比较的读数：%s（%s）" % (path, exc))
        return None
    if not isinstance(payload, dict) or not isinstance(payload.get("diagnostics"), list):
        print("FATAL dump 形状不是 moon check --json（缺 diagnostics 数组）：%s" % path)
        return None
    return payload


# ------------------------- 自检 -------------------------

def fx_diag(file, line, c1, c2, code, msg):
    return {"file": file, "line": line, "c1": c1, "c2": c2, "same_line": True,
            "code": code, "msg": msg}


def fx_show_src():
    return {
        "t/main.mbt": (
            "pub fn main() {\n"
            "  println(\n"
            "    \"ok \\{pub_res.to_string()}\",\n"
            "  )\n"
            "}\n"),
        "t/concat.mbt": (
            "test \"x\" {\n"
            "  abort(\"实际 \" + r3.to_string())\n"
            "}\n"),
        "t/interp.mbt": (
            "test \"y\" {\n"
            "  abort(\"偏好应保留，实际 \\{back2.prefs}\")\n"
            "}\n"),
        "t/inspect.mbt": (
            "test \"z\" {\n"
            "  inspect(p.verdict, content=\"Some(Valid)\")\n"
            "}\n"),
    }


def fx_uni(src):
    """夹具宇宙：真实夹具文件 + 填充名，必须越过 S2 下限，否则每支对照都先撞 S2。"""
    return sorted(src) + ["pad/p%03d.mbt" % i for i in range(120)]


def fx_fam(key):
    for f in SITE_FAMILIES:
        if f["key"] == key:
            return [f]
    raise AssertionError("no family " + key)


SHOW_DEBUG = "Warning (deprecated): Use Debug instead of Show for debugging purposes."
SHOW_COLL = "Warning (deprecated): Use `@debug.Debug` instead of `Show` for collections"


def scase(label, families, diags, sources, want_rc, want_tags):
    rc, out = site_list(families, diags, fx_uni(sources), sources)
    joined = "\n".join(out)
    tags = [want_tags] if isinstance(want_tags, str) else list(want_tags)
    if rc != want_rc:
        print("SELFTEST FAIL %s：期望 rc=%d，实得 rc=%d\n%s" % (label, want_rc, rc, joined))
        return False
    for t in tags:
        if t not in joined:
            print("SELFTEST FAIL %s：读数里没有指名的判据 %r\n%s" % (label, t, joined))
            return False
    hit = [x for x in out if any(t in x for t in tags)]
    print("  ok %-24s rc=%d  %s" % (label, rc, (hit[0].strip()[:100] if hit else out[-1].strip()[:100])))
    return True


def selftest():
    _entry_probe()
    done = [0]

    def case(*a):
        if not scase(*a):
            return False
        done[0] += 1
        return True

    src = fx_show_src()
    # 1) to_string() 站点被两条判据文本命中 ⇒ 2 行 1 站
    if not case("S-show-double-fire", SITE_FAMILIES, [
            fx_diag("t/main.mbt", 3, 19, 28, 20, SHOW_DEBUG),
            fx_diag("t/main.mbt", 3, 19, 28, 20, SHOW_COLL)], src, 0,
            ["判据面命中 2 行 / 1 个站点", "同站还有 show-collections"]):
        return 1
    # 2) 三种 Show 写法各归各类
    if not case("S-show-shapes", fx_fam("show-debug"), [
            fx_diag("t/concat.mbt", 2, 20, 29, 20, SHOW_DEBUG),
            fx_diag("t/interp.mbt", 2, 21, 32, 20, SHOW_DEBUG),
            fx_diag("t/inspect.mbt", 2, 11, 20, 20, SHOW_DEBUG)], src, 0,
            ["to_string() 调用", "字符串插值", "inspect() 实参"]):
        return 1
    # 3) 测试面 / 生产面分档（决定改动波及的是断言文本还是用户可见输出）
    if not case("S-show-faces", fx_fam("show-debug"), [
            fx_diag("t/main.mbt", 3, 19, 28, 20, SHOW_DEBUG),
            fx_diag("t/concat.mbt", 2, 20, 29, 20, SHOW_DEBUG)], src, 0,
            ["生产面", "测试面"]):
        return 1
    # 4) 未知形状不许被硬塞进已知三档
    if not case("S-show-unknown-shape", fx_fam("show-debug"),
                [fx_diag("t/concat.mbt", 2, 3, 8, 20, SHOW_DEBUG)], src, 0,
                ["未分类"]):
        return 1
    # 5) FFI Array：抬头在上一行 ⇒ 行级正则拿不到归属（本工具的核心卖点）
    ffi2 = {"a/b.mbt": "extern \"js\" fn js_batch(\n  commands : Array[String],\n) -> Unit {}\n"}
    ffi_diag = [fx_diag("a/b.mbt", 2, 14, 27, 20,
                        "Warning (deprecated): Using `Array` in JavaScript FFI is deprecated. Use `FixedArray` instead.")]
    if not case("S-ffi-crossline", fx_fam("js-ffi-array"), ffi_diag, ffi2, 0,
                ["不能（本行无 extern token，归属在上方 1 行）", "建议替换 = FixedArray[String]"]):
        return 1
    # 6) 反证：同行 extern 的站点行级就能判 ⇒ 上一条的「读不到」是条件不是口号
    ffi1 = {"a/c.mbt": "extern \"js\" fn js_one(args : Array[String]) -> Unit {}\n"}
    if not case("S-ffi-same-line", fx_fam("js-ffi-array"),
                [fx_diag("a/c.mbt", 1, 30, 42, 20, ffi_diag[0]["msg"])], ffi1, 0,
                ["能（extern 与本行同行）"]):
        return 1
    # 7) 隐式提升：从判据文本解出来源 impl，再回本文件找 impl 定义行
    promo = {"p/x.mbt": (
        "impl Executor for McpDelegateExecutor with fn run(self, t : Task) -> Unit {\n"
        "  println(\"x\")\n"
        "}\n"
        "///|\n"
        "pub fn delegate_execute(t : Task) -> Unit {\n"
        "  let ex = McpDelegateExecutor::new()\n"
        "  ex.run(t)\n"
        "}\n")}
    if not case("S-promotion-impl", fx_fam("implicit-promotion"), [fx_diag(
            "p/x.mbt", 7, 6, 9, 20,
            "Warning (deprecated): The method `run` is implicitly promoted from "
            "`impl Executor for McpDelegateExecutor`. This behavior is deprecated, "
            "either use `McpDelegateExecutor::run(ex, t)` instead.")], promo, 0,
            ["Executor ← McpDelegateExecutor", "该 impl 在本文件内的行 = 1",
            "站点是否在 impl 体内 = 否", "impl 段落（粗界） = 第 1–4 行"]):
        return 1
    # 8) derive(Show)：Debug 已在列表 ⇒ 改法是删一个 token
    der = {"d/y.mbt": "pub enum Verdict {\n  A\n  Valid\n} derive(Eq, Debug, Show)\n"}
    if not case("S-derive-has-debug", fx_fam("derive-show"), [fx_diag(
            "d/y.mbt", 4, 21, 25, 27,
            "Warning (deprecated_syntax): `derive(Show)` is deprecated. Use `derive(Debug)` or manually implement the `Show` trait instead.")],
            der, 0, ["Debug 已在列表 = 是", "改法 = 删掉 Show 一个 token 即可，不用补实现"]):
        return 1
    # 9) 0078：私有转换辅助 vs 对外契约面
    res = {"s/z.mbt": "///|\nfn to_result(\n  r : Result[Int, String],\n) -> Result[@mcp.ToolResult, @mcp.MCPError] {\n  r\n}\n"}
    if not case("S-result-private", fx_fam("result-error-return"), [fx_diag(
            "s/z.mbt", 4, 6, 43, 78,
            "Warning (result_error_return): Prefer `T raise E` for failable APIs. Return `Result[T, E]` only when...")],
            res, 0, ["可见性 = 私有（内部转换辅助）", "所在函数 = to_result（第 2 行）"]):
        return 1
    if not case("S-result-pub", fx_fam("result-error-return"), [fx_diag(
            "s/z.mbt", 4, 6, 24, 78, "Warning (result_error_return): Prefer `T raise E` for failable APIs.")],
            {"s/z.mbt": "///|\npub fn to_result(\n  r : Result[Int, String],\n) -> Result[Int, String] {\n  r\n}\n"}, 0,
            ["可见性 = pub（对外契约面）"]):
        return 1
    # 10) S1 空诊断面
    if not case("S1-empty-diags", SITE_FAMILIES, [], src, 2, "S1 诊断面为空"):
        return 1
    # 11) S2 宇宙被换小
    rc, out = site_list(SITE_FAMILIES, [fx_diag("t/main.mbt", 3, 19, 28, 20, SHOW_DEBUG)],
                        ["a.mbt", "b.mbt"], fx_show_src(), min_tracked=100)
    if rc != 2 or "S2 跟踪面" not in "\n".join(out):
        print("SELFTEST FAIL S2-small-universe：%s" % "\n".join(out))
        return 1
    print("  ok %-24s rc=%d  %s" % ("S2-small-universe", rc, [x for x in out if "S2" in x][0].strip()[:90]))
    done[0] += 1
    # 12) S3 站点越出跟踪面
    bad_src = dict(fx_show_src())
    bad_src["t/outside.mbt"] = "pub fn f() {\n  println(\"\\{a.to_string()}\")\n}\n"
    if not case("S3-site-outside-universe", fx_fam("show-debug"),
                [fx_diag("t/outside.mbt", 2, 16, 25, 20, SHOW_DEBUG)],
                {k: v for k, v in bad_src.items() if k != "t/outside.mbt"}, 2, "S3 站点文件越出跟踪面"):
        return 1
    # 13) S4 行号越界（dump 与源码不同步）
    if not case("S4-line-out-of-range", fx_fam("show-debug"),
                [fx_diag("t/concat.mbt", 99, 18, 27, 20, SHOW_DEBUG)], src, 2, "S4 行号越界"):
        return 1
    # 14) S4 列切片为空
    if not case("S4-empty-slice", fx_fam("show-debug"),
                [fx_diag("t/concat.mbt", 2, 40, 45, 20, SHOW_DEBUG)], src, 2, "S4 列切片为空"):
        return 1
    # 15) S4 跨行站点不作数
    if not case("S4-multiline-site", fx_fam("show-debug"),
                [{"file": "t/concat.mbt", "line": 2, "c1": 18, "c2": 5, "same_line": False,
                  "code": 20, "msg": SHOW_DEBUG}], src, 2, "S4 站点跨行"):
        return 1
    # 16) S5 切片与本族点名符号对不上（loc 口径漂移）⇒ 尺子自拒
    if not case("S5-token-drift", fx_fam("js-ffi-array"),
                [fx_diag("a/b.mbt", 2, 3, 10, 20,
                         "Warning (deprecated): Using `Array` in JavaScript FFI is deprecated.")], ffi2, 2,
                "S5 本族全部 1 个站点的切片都不含本族点名的符号"):
        return 1
    # 17) S6 族读 0 处 ⇒ rc 仍是 0，但要打免责句
    if not case("S6-zero-family-read", fx_fam("derive-show"), [fx_diag("t/concat.mbt", 2, 20, 29, 20, SHOW_DEBUG)],
                src, 0, "这不构成「已清空」的证据"):
        return 1
    # 18) 报告永不给 1：再多违例形状也只出读数
    if not case("S-report-not-verdict", SITE_FAMILIES, [
            fx_diag("t/main.mbt", 3, 19, 28, 20, SHOW_DEBUG),
            fx_diag("t/main.mbt", 3, 19, 28, 20, SHOW_COLL),
            fx_diag("t/interp.mbt", 2, 21, 32, 20, SHOW_DEBUG)], src, 0,
            ["本工具不判红：只可能返回 0 或 2"]):
        return 1
    # 20) 诊断面非空但全清单 0 处 ⇒ rc 仍 0，但要把「判据文本漂移」这一读法点名出来
    if not case("S-all-zero-pointer", SITE_FAMILIES,
                [fx_diag("t/concat.mbt", 2, 20, 29, 21, "Warning (something_else): totally unrelated")],
                src, 0, "全清单 6 族都读到 0 处"):
        return 1
    print("SELFTEST PASS（%d 支）" % done[0])
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


def main():
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    if args[0] == "--selftest":
        return selftest()
    dump = args[0]
    payload = load_dump(dump)
    if payload is None:
        return 2
    try:
        universe = tracked_mb_files()
    except RuntimeError as exc:
        print("FATAL 跟踪面读不出：%s" % exc)
        return 2
    diags = norm_rows(payload)
    files = sorted({r["file"] for r in diags if r["file"]})
    sources = {}
    for p in files:
        if p not in set(universe):
            continue
        try:
            sources[p] = io.open(os.path.join(ROOT, p), encoding="utf-8", errors="replace").read()
        except OSError as exc:
            print("FATAL 站点文件读不到：%s（%s）" % (p, exc))
            return 2
    print("读取 dump %s（diagnostics %d 条 / 宇宙 %d 个跟踪 .mbt / 站点文件 %d 个）"
          % (dump, len(payload["diagnostics"]), len(universe), len(sources)))
    rc, out = site_list(SITE_FAMILIES, diags, universe, sources)
    for line in out:
        print(line)
    return rc


if __name__ == "__main__":
    sys.exit(main())
