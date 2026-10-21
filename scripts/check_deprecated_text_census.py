#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_deprecated_text_census.py — 弃用调用「判据面 vs 文本面」普查棘轮（BUG-362 建议②）。

要防的事：编译器判据会**静默少报**。2026-10-21 实测 `Json::value` 一族：
`moon check --target js --json` 的 0020 判据面 = 430 处，而按 `git ls-files "*.mbt"`
文本面普查 = 441 处，差的 11 处分散在 8 个文件（`match recv.value("k") {}` 这种
判据不发火的形状）。也就是说：**「判据面归零」这句话本身不构成「弃用调用清零」的证据**
——把 430 条都改完，判据面读到 0，源码里还能剩 11 条。这条尺就是把那 11 处从「没人知道的
盲区」变成「台账里写着上限、超出即红」的已知量。

扫描宇宙必须是 **git 跟踪面**（`git ls-files "*.mbt"`）。文件系统 walk 会把
`.mooncakes/moonbitlang/x/time/weekday.mbt` 里那个**同名不同物**的 `Weekday.value()`
也数进来（实测 +7 ⇒ 448），得到一个假缺口。R1 的「跟踪 .mbt 文件数 ≥ 下限」就是防有人
把宇宙换成 walk 或换成一个空目录——宇宙变了，数字就没有可比性。

判据（表内每族独立评）：
  R0 表内条目必须有非空 `audited`（写下缺口是怎么一处一处审过的）——缺依据的豁免=登记即免检
  R1 输入面哨兵：dump 可解析、`diagnostics` 非空、跟踪面 .mbt ≥ 下限 ⇒ 否则拒绝读数（exit 2）
  R2 反向包含：判据命中的每个 (file,line) 必须被本族文本正则覆盖；判据数 > 文本数也按脱钩算 ⇒ exit 2
     （这两档都是「尺子量不动」，不是「代码坏了」，所以不给红门的 1 而给 2，别冒用被测对象的退出码）
  R3 棘轮：gap = 文本面 − 判据面 ≤ `gap_ceiling`，超出即红（exit 1）并列逐文件差额；
     gap 缩小**不**阻断，只打「可收紧至 N」——理由见下面「为什么收紧不判红」
  R4 死条目：文本面与判据面同时为 0 ⇒ 红（exit 1），整条下线（把表项删掉），不许留着当免检牌

哪些族进不了这张表（实测，不是设想）：本表要求 `text_regex` 是**站点级**代理——判据发火的那个 token
在源码文本里就长得一样。0020 的五个子族里只有两族满足：`Json::value`（文本 441 / 判据 430）与
`Check @encoding/utf8.encode`（`.to_bytes(` 3 / 判据 3，逐行重合）。其余三族的弃用点在**语义**上，
名称级普查给出的读数荒谬：`Show` 族名称级 `\bShow\b` 全仓只有 **2** 处而判据 **8** 处，且那 2 处是
0027 的 `derive(Eq, Debug, Show)` 与一条 `extend StarVerdict with Show::{to_string, output}`，
与 8 个判据行**无一重合**；真实站点分散在 `.to_string()`(435) / `inspect(`(39) / 字符串插值 `\{}`(859)
三种写法里，并集 1333 处对判据 11 处 ⇒ 上限要写到 1322 才不红，棘轮当场失去意义。FFI `Array` 判据
3 处全在 `extern "js" fn` 的形参/字段上，而 `: Array[` 在跟踪面有 953 处——「是否处在 extern 块内」是
跨行事实，行级正则表达不了。隐式提升判据 1 处、`.run(` 7 处，同理。这三族要收口只能按 `error_code`
逐条清（判据面自己就是清单），文本普查替不了它；把它们按名称级写进表也不会被放过——2 < 8 触发 R2
的「判据数多于文本数」，rc=2 而非 rc=0。

为什么收紧不判红（与 check_test_sync 的豁免失效律故意不同）：gap 的具体数字随工具链版本浮动
（判据形状发不发火、正则匹配到的行数会不会被重排），今天 11、明天也许 10；强制「必须等于
表里的上限」会把一次正常升级变成红灯，而红灯被忽略一次，整把尺就废了。所以只写上界，
把「可收紧」当建议打印出来，让人（不是流水线）决定何时下调。

退出码：0=PASS / 1=棘轮超限或死条目 / 2=判据无法自证（宇宙、dump、表形状对不上）。

用法：
    python scripts/check_deprecated_text_census.py temp/chk40.json   # CI/本机复跑
    python scripts/check_deprecated_text_census.py --selftest        # 10 支对照考这把尺自己
"""
import io
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MIN_TRACKED_MBT = 100

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")


# ---------------------------------------------------------------- 族表
# judge = 编译器判据那一侧：error_code + message 子串（子串必须在本 dump 内唯一，
#         否则会把别族的量算进本族，见 BUG-362 的 430/448 分族实测）。
# text  = 源码文本普查那一侧：一行内每次匹配算一处。
FAMILIES = [
    {
        "name": "Json::value(0020 deprecated accessor)",
        "error_code": 20,
        "judge_marker": "Suggestion:",
        "text_regex": r"\.value\(",
        "gap_ceiling": 11,
        "audited": (
            "2026-01 逐处审过 11 处判据不发火的形状：engine_circuit_test.mbt:28 / "
            "engine_contract_test.mbt:20,28,36 / engine_dispatch_test.mbt:47 / "
            "engine_eval_test.mbt:15 / engine_phi_test.mbt:117 / "
            "engine_triage_skill_test.mbt:28 / engine_triage_test.mbt:28,75 / "
            "supervisor_tools_wbtest.mbt:31，全部是 `match recv.value(\"k\") {}` 形态，"
            "确为 Json::value 调用（非同名方法）；反向哨兵 0（判据命中全部落在文本面上）。"
            "上限 11 即这 11 处，改完一处即可收紧，清零后本条目整条下线（R4）。"
        ),
    },
    {
        "name": "Check @encoding/utf8.encode(0020 via String::to_bytes)",
        "error_code": 20,
        "judge_marker": "utf8.encode",
        "text_regex": r"\.to_bytes\(",
        "gap_ceiling": 0,
        "audited": (
            "2026-10-21 普查：判据面 3 处与文本面 3 处逐行重合、缺口 0。站点 "
            "src/router/star_gate.mbt:302 / src/router/star_gate_wbtest.mbt:22,350，"
            "三处都是 `canonical.to_bytes()`——即 BUG-360 记的那条「String 内部 UTF-16LE、"
            "生产签名侧用 UTF-8」验签洞的本体，本条目量的是它还剩几处。名称级正则 "
            "`utf8\\.encode\\(` 在跟踪面只有 1 处（注释里），按它登记会得到负缺口（3 > 1）"
            "⇒ 走 R2 现形，所以这里用站点级代理。上限 0 的已知误红面：若将来在非 String "
            "接收者上新写 `.to_bytes(`（编译器不发判据），R3 会红并列逐文件差额，正确处置是"
            "把正则收窄（带上接收者形状），不是抬上限。BUG-360 修完后两面归 0 ⇒ R4 发红，"
            "那时该做的动作就是把这条整条删掉。"
        ),
    },
]


# ---------------------------------------------------------------- 读数
def tracked_mb_files():
    """扫描宇宙 = git 跟踪的 .mbt（POSIX 分隔的仓库相对路径）。"""
    out = subprocess.run(
        ["git", "ls-files", "*.mbt"],
        cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    if out.returncode != 0:
        raise RuntimeError("git ls-files 失败：%s" % (out.stderr.strip() or "rc=%d" % out.returncode))
    return sorted(p for p in out.stdout.replace("\\r", "").split("\n") if p)


def read_sources(paths):
    src = {}
    for p in paths:
        try:
            src[p] = io.open(os.path.join(ROOT, p), encoding="utf-8", errors="replace").read()
        except OSError as exc:
            raise RuntimeError("跟踪面文件读不到：%s（%s）" % (p, exc))
    return src


def normalize_diags(payload):
    """dump -> [{file, line, code, msg}]，file 一律仓库相对 POSIX；越界的原样保留以便 R1 现形。"""
    recs = []
    for d in payload.get("diagnostics", []):
        path = d.get("path", "")
        rel = os.path.relpath(path, ROOT).replace("\\", "/") if path else ""
        if path and rel.startswith(".."):
            rel = path.replace("\\", "/")
        line = 0
        m = re.match(r"\s*(\d+)", str(d.get("loc", "")))
        if m:
            line = int(m.group(1))
        recs.append({
            "file": rel,
            "line": line,
            "code": d.get("error_code"),
            "msg": str(d.get("message", "")),
        })
    return recs


# ---------------------------------------------------------------- 评级
def judge_hits(family, diags):
    return [r for r in diags
            if r["code"] == family["error_code"] and family["judge_marker"] in r["msg"]]


def text_hits(family, sources):
    """返回 (逐文件出现次数, 逐文件命中行号集合)。"""
    pat = re.compile(family["text_regex"])
    counts, lines = {}, {}
    for p, text in sources.items():
        n = len(pat.findall(text))
        if not n:
            continue
        counts[p] = n
        lines[p] = {i for i, ln in enumerate(text.split("\n"), 1) if pat.search(ln)}
    return counts, lines


def evaluate(families, diags, sources, min_tracked=MIN_TRACKED_MBT):
    """返回 (exit_code, 打印行)。核心判据与 IO 分离，selftest 才能喂合成夹具。"""
    out = []
    fatal = []
    red = []

    if not isinstance(sources, dict) or len(sources) < min_tracked:
        fatal.append(
            "R1 跟踪面 .mbt 文件数 %d < 下限 %d —— 扫描宇宙不是 git 跟踪面（或被换成空目录），"
            "普查数字与表内上限不可比" % (len(sources or {}), min_tracked))
    if not diags:
        fatal.append(
            "R1 诊断面为空 —— moon check 没真跑、dump 截断，或全绿但表里条目还没下线；"
            "三种情况在这把尺上必须分开，不能一律读成 PASS")
    for fam in families:
        if not str(fam.get("audited", "")).strip():
            fatal.append("R0 %s：表内条目没有 audited 依据 —— 缺依据的登记等于「登记即免检」" % fam["name"])
        try:
            re.compile(fam["text_regex"])
        except (re.error, TypeError) as exc:
            fatal.append("R0 %s：text_regex 不可编译（%s）" % (fam["name"], exc))
    if fatal:
        out.append("FATAL 普查不可信，本守卫拒绝给出 PASS/FAIL：")
        out += ["  " + x for x in fatal]
        return 2, out

    for fam in families:
        jh = judge_hits(fam, diags)
        counts, lines = text_hits(fam, sources)
        jn = len(jh)
        tn = sum(counts.values())
        out.append("%s：判据面 %d / 文本面 %d / 缺口 %d（上限 %d）" % (fam["name"], jn, tn, tn - jn, fam["gap_ceiling"]))

        off = [r for r in jh if r["file"] not in sources]
        if off:
            out.append("  FATAL R1 %d 处判据命中落在跟踪面之外，例：%s:%s"
                       % (len(off), off[0]["file"], off[0]["line"]))
            fatal.append("R1 判据面越出跟踪宇宙")
            continue

        miss = [r for r in jh
                if r["line"] not in lines.get(r["file"], set())]
        if miss:
            s = miss[0]
            out.append("  FATAL R2 判据命中未被本族文本正则覆盖，例：%s:%d（msg=%s）"
                       % (s["file"], s["line"], s["msg"][:80]))
            out.append("       —— 表里的 text_regex 与真源形状脱钩，普查侧计数会漏，先修表再谈代码")
            fatal.append("R2 判据/文本形状脱钩")
            continue
        gap = tn - jn
        if gap < 0:
            out.append("  FATAL R2 判据面 %d 多于文本面 %d（同一行多发？计数脱钩）" % (jn, tn))
            fatal.append("R2 判据数多于文本数")
            continue
        if tn == 0 and jn == 0:
            red.append("R4 %s：文本面与判据面双 0 —— 本条目已无对象，须整条从表里下线，不许留着当免检牌"
                       % fam["name"])
            out.append("  FAIL " + red[-1])
            continue
        if gap > fam["gap_ceiling"]:
            red.append("R3 %s：缺口 %d 超上限 %d（新增 %d 处判据静默少报）"
                       % (fam["name"], gap, fam["gap_ceiling"], gap - fam["gap_ceiling"]))
            out.append("  FAIL " + red[-1])
            per = {}
            for p, n in counts.items():
                jc = sum(1 for r in jh if r["file"] == p)
                if n != jc:
                    per[p] = n - jc
            for p, d in sorted(per.items(), key=lambda kv: (-kv[1], kv[0]))[:20]:
                out.append("       %-58s +%d" % (p, d))
            if len(per) > 20:
                out.append("       ……其余 %d 个文件从略" % (len(per) - 20))
        elif gap < fam["gap_ceiling"]:
            out.append("  提示：缺口已缩小到 %d，表内上限可收紧至 %d（本轮不阻断；"
                       "数字随工具链版本浮动，收紧由人决定）" % (gap, gap))
    if fatal:
        out.append("FATAL 判据无法自证：%d 项 —— 修表/修 dump，别让普查替坏尺背书" % len(fatal))
        return 2, out
    if red:
        out.append("FAIL 弃用调用普查棘轮：%d 项违例" % len(red))
        return 1, out
    out.append("PASS 各族缺口均在上限内（棘轮只许缩小；本行数字来自实测，非手写）")
    return 0, out


# ---------------------------------------------------------------- selftest
def fixture_family(**over):
    fam = {
        "name": "FixtureFam",
        "error_code": 20,
        "judge_marker": "Suggestion:",
        "text_regex": r"\.value\(",
        "gap_ceiling": 1,
        "audited": "合成夹具：审过 1 处判据不发火的 match 形状",
    }
    fam.update(over)
    return fam


def fixture_diag(line, code=20, msg="Warning (deprecated): ... Suggestion: x", path="src/a.mbt"):
    return {"file": path, "line": line, "code": code, "msg": msg}


def fixture_sources(n_files=120):
    """120 个跟踪文件，其中 src/a.mbt 有 2 行 .value(（第 10、11 行）。"""
    src = {}
    for i in range(n_files):
        src["src/f%03d.mbt" % i] = "let x = 1\n"
    src["src/a.mbt"] = "let p = 0\n\n\n\n\n\n\n\n\na.value(\"k\")\nb.value(\"j\")\n"
    return src


def run_case(label, families, diags, sources, want_rc, want_tag, min_tracked=MIN_TRACKED_MBT):
    rc, out = evaluate(families, diags, sources, min_tracked=min_tracked)
    joined = "\n".join(out)
    if rc != want_rc:
        print("SELFTEST FAIL %s：期望 rc=%d，实得 rc=%d\n%s" % (label, want_rc, rc, joined))
        return None
    if want_tag and want_tag not in joined:
        print("SELFTEST FAIL %s：结论行里没有指名的判据 %r\n%s" % (label, want_tag, joined))
        return None
    hit = [x for x in out if want_tag and want_tag in x]
    print("  ok %-22s rc=%d  %s" % (label, rc, (hit[0].strip()[:96] if hit else out[-1].strip()[:96])))
    return rc


def selftest():
    done = [0]

    def case(*a, **kw):
        if run_case(*a, **kw) is None:
            return False
        done[0] += 1
        return True

    base = fixture_sources()
    # 1) 干净基线：判据 1 处 + 文本 2 处 = 缺口 1 == 上限 ⇒ PASS
    if not case("baseline-clean", [fixture_family()], [fixture_diag(10)], base, 0, "PASS"):
        return 1
    # 2) R1 空诊断面：不许读成「全绿」
    if not case("R1-empty-diags", [fixture_family()], [], base, 2, "R1 诊断面为空"):
        return 1
    # 3) R1 扫描宇宙被换小（模拟 walk 指错目录 / 非跟踪面）
    if not case("R1-small-universe", [fixture_family()], [fixture_diag(10)],
                fixture_sources(10), 2, "R1 跟踪面 .mbt 文件数"):
        return 1
    # 4) R2 判据命中的行没有文本匹配 ⇒ 表与真源形状脱钩
    if not case("R2-judge-outside-text", [fixture_family()], [fixture_diag(50)], base, 2,
                "R2 判据命中未被本族文本正则覆盖"):
        return 1
    # 5) R2 判据命中落在跟踪面之外
    if not case("R1-judge-off-universe", [fixture_family()], [fixture_diag(10, path="vendor/x.mbt")],
                base, 2, "判据命中落在跟踪面之外"):
        return 1
    # 6) R3 缺口超上限：新增一处静默少报
    bad = dict(base)
    bad["src/a.mbt"] = base["src/a.mbt"] + 'c.value("m")\n'
    if not case("R3-gap-over-ceiling", [fixture_family()], [fixture_diag(10)], bad, 1,
                "R3 FixtureFam：缺口 2 超上限 1"):
        return 1
    # 7) R4 死条目（判据面全树非空、但本族文本+判据双 0 ⇒ 红，豁免牌不许留）
    empty = dict(base)
    empty["src/a.mbt"] = "let p = 0\n"
    other = [fixture_diag(10, code=2, msg="Warning (other): keep the dump non-empty")]
    if not case("R4-retire-exemption", [fixture_family()], other, empty, 1, "R4 FixtureFam：文本面与判据面双 0"):
        return 1
    # 8) R0 条目没有审计依据：缺依据的登记等于免检牌
    if not case("R0-missing-audited", [fixture_family(audited="  ")], [fixture_diag(10)], base, 2,
                "R0 FixtureFam：表内条目没有 audited 依据"):
        return 1
    # 9) 缺口缩小只打印建议，不判红
    if not case("hint-narrow-only", [fixture_family(gap_ceiling=5)], [fixture_diag(10)], base, 0,
                "可收紧至 1"):
        return 1
    # 10) R2 负缺口：同一行两条判据、文本只有一处（实测到的 Show 形状：8 处判据对 2 处 `Show` 文本）
    if not case("R2-judge-over-text",
                [fixture_family(text_regex=r"a\.value\(", gap_ceiling=0)],
                [fixture_diag(10), fixture_diag(10)], base, 2, "判据面 2 多于文本面 1"):
        return 1
    print("SELFTEST PASS %d 个变体各自命中自己指名的判据（计数由 run_case 实测累加，非手写）" % done[0])
    return 0


# ---------------------------------------------------------------- main
def main():
    args = sys.argv[1:]
    if args == ["--selftest"]:
        return selftest()
    if not args:
        print(__doc__)
        print("用法：python scripts/check_deprecated_text_census.py <moon check --json dump>")
        return 2
    dump = args[0]
    try:
        payload = json.loads(io.open(dump, encoding="utf-8", errors="replace").read())
    except (OSError, ValueError) as exc:
        print("FATAL dump 读不出可比较的读数：%s（%s）" % (dump, exc))
        return 2
    if not isinstance(payload, dict) or not isinstance(payload.get("diagnostics"), list):
        print("FATAL dump 形状不是 moon check --json（缺 diagnostics 数组）：%s" % dump)
        return 2
    try:
        paths = tracked_mb_files()
        sources = read_sources(paths)
    except RuntimeError as exc:
        print("FATAL 扫描宇宙取不到：%s" % exc)
        return 2
    diags = normalize_diags(payload)
    print("输入：%s（诊断 %d 条）；扫描宇宙：git 跟踪 .mbt %d 个文件；族表 %d 条"
          % (dump, len(payload["diagnostics"]), len(sources), len(FAMILIES)))
    rc, out = evaluate(FAMILIES, diags, sources)
    for line in out:
        print(line)
    return rc


if __name__ == "__main__":
    sys.exit(main())
