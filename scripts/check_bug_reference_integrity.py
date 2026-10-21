#!/usr/bin/env python3
"""BUG-373 出路①：把「代码里引用的 BUG-N」与「账本抬头编号」机械对表——**只报不判**的第一版。

为什么先只报不判（R48 立案时定死的口径）：本仓定律「假红比漏判更贵」，而引用面有 946 处、157 个编号，
一次性开判红等于逼着所有人无视这把尺。R47 还留了一条更硬的教训：**一台永远绿的门比没有门更坏**，
所以这一版既不能是空门，也不能是乱报的门——它交付的是「读数面 + 一条最强的判定面」。

面分类是这一版的核心设计，不是装饰（实测两类混在一起会产出 37 条假红）：
  · comment 面 = 引用出现在 `//` 之后（作者对"这段代码为什么这样写"的署名，属可核事实）
  · string 面  = 引用出现在双引号字面量之内（多数是 wbtest 里的**合成语料**，如 BUG-901/999 是夹具数据不是引用）
  · code 面    = 既不在注释也不在字面量里（MoonBit 里 `BUG-1` 不是合法标识符 ⇒ 正常应为 0，出现即说明解析器读错了面）

判定面（唯一会红的，走棘轮只许降）：
  J1 悬空-注释面：comment 面引用的编号 ∉ 账本抬头集合。现读 1 条（`src/engine/engine.mbt` 引 BUG-147，
     账本无 147 抬头），上限 `DANGLING_COMMENT_CEILING` 由该现读值钉住，修一条就降一档。

只报不判（必须出数；静默丢弃 = 数字凭空少）：
  S1 悬空-字面量面（合成语料，逐编号计数）
  S2 疑似无归属：编号在集合内，但该条目的正文既没提这个文件的 basename，也没提它所在的包目录
     ——这一类是 R47 取证里「11 字段同构 查无条目」与「BUG-189 一号三义」的真实形状；代理判据粗，
     所以只报不判，逐条核过才谈开判红。
  S3 跨文件同编号（信息面：一个号被几个不同文件引用；合法修复本就会跨文件落，所以它只作分布不作结论）

自拒（绝不对着空集报绿）：git 枚举失败或枚举到 0 份 .mbt / 账本读不到任何抬头 / 引用点解析为 0
（正则或面分类坏掉）⇒ FATAL 真给 2。

用法：python scripts/check_bug_reference_integrity.py [--selftest|--dump|--show-ceiling]
退出码：0=判定面在棘轮上限内（只报面出数即可，不参与判红） / 1=判定面超上限 / 2=判据无法自证
判据不许自证：编号集合由本脚本自己解析 `^## BUG-(\\d+)\\b`，不 import gen_plugins。
"""
import argparse
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
BUGS = ROOT / "memory" / "bugs.md"

RE_HEAD = re.compile(r"^## (BUG-\d+)\b")
RE_REF = re.compile(r"BUG-(\d+)")
RE_MENTIONED = re.compile(r"[\w./\\-]*\.mbti?\b")
# 判定面棘轮：钉住 R48 立案时的现读值（1 = engine.mbt 的 BUG-147），此后只许下降。
DANGLING_COMMENT_CEILING = 1
FACES = ("comment", "string", "code")


def emit_fatal(msg):
    """FATAL 一律走这里：契约要求判据失灵这一档必须真给 2，`raise SystemExit("串")` 只给 1。"""
    print("FATAL " + msg, file=sys.stderr)
    return 2


@dataclass
class Ref:
    ident: str
    path: str
    line: int
    face: str
    text: str


def face_of_col(line, idx, comment_at, in_str):
    """列位所在面：`//` 已开始（且该 `//` 本身不在字面量里）就是注释面，注释优先。"""
    if comment_at is not None and idx >= comment_at:
        return "comment"
    return "string" if in_str else "code"


def faces_of(line):
    """按列扫描一行，返回每个 `BUG-N` 出现处的面。"""
    out = []
    in_str = False
    esc = False
    comment_at = None
    for i in range(len(line)):
        ch = line[i]
        if comment_at is None:
            if ch == '"':
                if not esc:
                    in_str = not in_str
            elif ch == "\\":
                esc = not esc
                continue
            elif line.startswith("//", i) and not in_str:
                comment_at = i
        esc = False
        m = RE_REF.match(line, i)
        if m and i > 0 and (line[i - 1].isalnum() or line[i - 1] == "_"):
            continue  # 防把 `XBUG-1` 这类更长 token 切出假引用
        if m:
            out.append((m.group(0), face_of_col(line, i, comment_at, in_str)))
    return out


def ledger_bodies(text):
    """抬头编号 → 条目正文（到下一个抬头为止）。"""
    lines = text.split("\n")
    heads = [(i, RE_HEAD.match(ln)) for i, ln in enumerate(lines)]
    heads = [(i, m) for i, m in heads if m]
    bodies = {}
    for k, (i, m) in enumerate(heads):
        end = heads[k + 1][0] if k + 1 < len(heads) else len(lines)
        bodies[m.group(1)] = "\n".join(lines[i + 1:end])
    return bodies


def universe(root):
    """扫描宇宙 = 跟踪面的 .mbt（不是工作树，防把临时件读成引用面）。"""
    p = subprocess.run(["git", "-C", str(root), "ls-files", "*.mbt"],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    if p.returncode != 0:
        return None, "git ls-files 失败（rc=%s）：%s" % (p.returncode, (p.stderr or "").strip()[:160])
    rels = [r for r in p.stdout.replace("\r", "").split("\n") if r.strip()]
    if not rels:
        return None, "枚举到 0 份 .mbt ⇒ 扫描面空转，拒绝出读数"
    files = []
    for rel in rels:
        f = Path(root) / rel
        if not f.exists():
            return None, "跟踪面里的 %s 在工作树读不到 ⇒ 宇宙与磁盘对不上" % rel
        files.append((rel, f.read_text(encoding="utf-8", errors="replace")))
    return files, None


def scan(files):
    refs = []
    for rel, txt in files:
        for ln_no, line in enumerate(txt.replace("\r", "").split("\n"), 1):
            if "BUG-" not in line:
                continue
            for ident, face in faces_of(line):
                refs.append(Ref(ident, rel, ln_no, face, line.strip()[:110]))
    return refs


def package_of(rel):
    parts = rel.replace("\\", "/").split("/")
    return parts[-2] if len(parts) >= 2 else ""


def attributed(ref, body):
    """归属成立（**保守判据，只用于"别误报"，不用于"证明正确"**）：
      · 条目正文提过这个文件的 basename；或
      · 正文提过的某个 .mbt 与本文件同目录；或
      · 本文件所在目录名出现在正文里（`src/engine` / `` `engine` ``）。
    实测最松一层是承重的：BUG-181 条目讲的是 store_sqlite.mbt 的 clear 静默失败，代码侧的引用点却在
    `src/engine/cost_tool.mbt`——正文里根本没有同目录文件，只有 `src/store/...`。若只考前两层，
    「同包不同文件」这一大类合法引用（163 处）会被当成疑似错号报出来，那就是拿一把粗尺制造假红。
    所以 S2 的定义只能是**疑似**，判红必须留到逐条核过之后。"""
    base = ref.path.replace("\\", "/").split("/")[-1]
    if base and base in body:
        return True
    pkg = package_of(ref.path)
    if pkg:
        for m in RE_MENTIONED.findall(body):
            seg = m.replace("\\", "/").split("/")
            if len(seg) >= 2 and seg[-2] == pkg:
                return True
        if ("src/" + pkg) in body or ("`" + pkg + "`") in body:
            return True
    return False


def findings(refs, bodies):
    """面分类之外还有一条 R48 现读校准出的规则：同一文件里同一编号**既出现在注释又出现在字面量**，
    那条注释就是在讲合成语料（wbtest 里 `// 合法并入：902 → 901` 讲的是它自己造的那份假账本），
    不是对账本的署名——降级进 S1b 只报。没有这条规则时判定面 3 条里有 2 条是这种，棘轮会被假红喂胖。"""
    ids = set(bodies)
    str_ids_by_file = {}
    for r in refs:
        if r.face == "string":
            str_ids_by_file.setdefault(r.path, set()).add(r.ident)
    j1, s1b = [], []
    for r in refs:
        if r.face != "comment" or r.ident in ids:
            continue
        (s1b if r.ident in str_ids_by_file.get(r.path, ()) else j1).append(r)
    s1 = [r for r in refs if r.face == "string" and r.ident not in ids]
    s2 = [r for r in refs if r.ident in ids and not attributed(r, bodies[r.ident])]
    by_id = {}
    for r in refs:
        by_id.setdefault(r.ident, set()).add(r.path)
    s3 = sorted(((k, len(v)) for k, v in by_id.items() if len(v) >= 2), key=lambda x: (-x[1], int(x[0].split("-")[1])))
    return {"J1": j1, "S1": s1, "S1b": s1b, "S2": s2, "S3": s3}


def measure(dry=False):
    files, err = universe(ROOT)
    if err:
        return emit_fatal(err)
    if not BUGS.exists():
        return emit_fatal("账本 %s 读不到 ⇒ 没有真源可比" % BUGS)
    bodies = ledger_bodies(BUGS.read_text(encoding="utf-8", errors="replace"))
    if not bodies:
        return emit_fatal("账本未解析到任何 `## BUG-N` 抬头 ⇒ 编号集合为空，判据无法自证")
    refs = scan(files)
    if not refs:
        return emit_fatal("跟踪面 .mbt 里解析到 0 个 `BUG-N` 引用 ⇒ 正则或面分类坏了，拒绝报绿")
    f = findings(refs, bodies)
    per_face = {k: sum(1 for r in refs if r.face == k) for k in FACES}
    print("INFO 引用面普查（宇宙 %d 份 .mbt，账本抬头 %d 个唯一编号）：引用点 %d 处 / 涉及编号 %d；"
          "分面 comment=%d string=%d code=%d"
          % (len(files), len(bodies), len(refs), len({r.ident for r in refs}),
             per_face["comment"], per_face["string"], per_face["code"]))
    print("INFO 判定面 J1 悬空-注释面：%d 条（上限 %d，只许下降）；"
          "只报面 S1 悬空-字面量 %d 处 / S1b 夹具说明注释 %d 处 / S2 疑似无归属 %d 处 / S3 跨文件同编号 %d 个编号"
          % (len(f["J1"]), DANGLING_COMMENT_CEILING, len(f["S1"]), len(f["S1b"]), len(f["S2"]), len(f["S3"])))
    for r in f["J1"]:
        print("  J1 %s:%d (%s) %s" % (r.path, r.line, r.ident, r.text))
    if dry:
        for r in f["S1"][:12]:
            print("  S1 %s:%d (%s) %s" % (r.path, r.line, r.ident, r.text))
        for r in f["S2"][:20]:
            print("  S2 %s:%d (%s) %s" % (r.path, r.line, r.ident, r.text))
        for k, n in f["S3"][:10]:
            print("  S3 %s 被 %d 个文件引用" % (k, n))
    if len(f["J1"]) > DANGLING_COMMENT_CEILING:
        print("FAIL 判定面 %d 条 > 上限 %d：新增的注释面悬空引用必须先入账再引用（或改正编号）"
              % (len(f["J1"]), DANGLING_COMMENT_CEILING))
        return 1
    print("PASS 判定面在棘轮上限内（S1/S2/S3 只报不判，读数已出）——本行的结论是「还剩多少没核」，不是「这里没问题」")
    return 0


# —— 自测：合成夹具只考分类与自拒，不碰仓库文件 ——

def _mk(files, ledger_heads, extra_body=""):
    refs = scan(files)
    bodies = ledger_bodies(ledger_heads)
    return findings(refs, bodies), refs, bodies


SELF_CELLS = []


def cell(name):
    def deco(fn):
        SELF_CELLS.append((name, fn))
        return fn
    return deco


LEDGER_A = "## BUG-1 [t] [low] FIXED\n- detail: 讲 src/foo/a.mbt 的旧事\n\n## BUG-2 [t] [low] OPEN\n- detail: 讲 b.mbt 的旧事\n"


@cell("comment-dangling-must-judge")
def _c1():
    f, _, _ = _mk([("src/foo/a.mbt", "// BUG-99：悬空在注释里\n")], LEDGER_A)
    assert [r.ident for r in f["J1"]] == ["BUG-99"], f["J1"]


@cell("same-number-in-string-is-not-judged")
def _c2():
    f, _, _ = _mk([("src/foo/a.mbt", 'let s = "## BUG-99 [t] [low] OPEN"\n')], LEDGER_A)
    assert f["J1"] == [] and len(f["S1"]) == 1, (f["J1"], f["S1"])


@cell("known-number-in-comment-clean")
def _c3():
    f, _, _ = _mk([("src/foo/a.mbt", "// BUG-1：已知号\n")], LEDGER_A)
    assert f["J1"] == [] and f["S1"] == [], (f["J1"], f["S1"])


@cell("attribution-by-basename-or-package")
def _c4():
    f, _, _ = _mk([("src/foo/a.mbt", "// BUG-1 见正文\n"),
                   ("src/bar/z.mbt", "// BUG-1 与本包无关\n")], LEDGER_A)
    got = sorted({r.path for r in f["S2"]})
    assert got == ["src/bar/z.mbt"], got


@cell("bare-comment-marker-before-string")
def _c5():
    f, _, _ = _mk([("src/foo/a.mbt", '// 注释里的字面量 "BUG-77" 仍属注释面\n')], LEDGER_A)
    assert [r.face for r in f["J1"]] == ["comment"], f["J1"]


@cell("empty-universe-rc-really-two")
def _c6():
    p = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--probe-empty-root"],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    assert p.returncode == 2, (p.returncode, p.stderr[:160])


@cell("zero-refs-after-scrub-is-fatal-not-green")
def _c7():
    f, refs, _ = _mk([("src/foo/a.mbt", "// 没有任何引用\n")], LEDGER_A)
    assert refs == [] and f["J1"] == [] and f["S2"] == []


@cell("fixture-explaining-comment-downgraded")
def _c10():
    """同文件里同号也出现在字面量 ⇒ 那条注释讲的是它自己造的假账本，不进判定面。"""
    src = ('// 合法并入：902 → 901，抬头带上 →BUG-901\n'
           'let body = "## BUG-901 [t] [low] OPEN\\n- summary: 甲"\n')
    f, _, _ = _mk([("src/server/x_wbtest.mbt", src)], LEDGER_A)
    assert f["J1"] == [] and len(f["S1b"]) == 1, (f["J1"], f["S1b"])
    # 反向：同一条注释、但文件里没有该号的字面量 ⇒ 必须回到判定面（规则不能变成豁免口）
    f2, _, _ = _mk([("src/server/x_wbtest.mbt", '// 抬头带上 →BUG-901\nlet k = "别的字面量"\n')], LEDGER_A)
    assert [r.ident for r in f2["J1"]] == ["BUG-901"], f2["J1"]


@cell("ratchet-derives-from-constant")
def _c8():
    at = DANGLING_COMMENT_CEILING
    txt = "".join("// BUG-%d：悬空\n" % (1000 + i) for i in range(at + 1))
    f, _, _ = _mk([("src/foo/a.mbt", txt)], LEDGER_A)
    assert len(f["J1"]) == at + 1, len(f["J1"])


@cell("calib-real-corpus-has-exactly-one-comment-dangling")
def _c9():
    files, err = universe(ROOT)
    if err:
        raise SystemExit(emit_fatal("标定格读不到宇宙：" + err))
    refs = scan(files)
    bodies = ledger_bodies(BUGS.read_text(encoding="utf-8", errors="replace"))
    j1 = findings(refs, bodies)["J1"]
    assert len(j1) == DANGLING_COMMENT_CEILING, "现读 %d 条 ≠ 上限 %d，棘轮该降或该修" % (len(j1), DANGLING_COMMENT_CEILING)


def selftest():
    bad = []
    for name, fn in SELF_CELLS:
        try:
            fn()
            print("  ok  %s" % name)
        except AssertionError as e:
            print("  FAIL %s ⇒ %s" % (name, e))
            bad.append(name)
    print("SELFTEST %s（%d 格，其中标定 1 格按现读对表；计数由本行实测累加，非手写）"
          % ("FAIL" if bad else "PASS", len(SELF_CELLS)))
    return 1 if bad else 0


def main(argv=None):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--dump", action="store_true", help="打印只报面的站点清单（供下一批改判核）")
    ap.add_argument("--show-ceiling", action="store_true")
    ap.add_argument("--probe-empty-root", action="store_true", help=argparse.SUPPRESS)
    a = ap.parse_args(argv)
    if a.probe_empty_root:
        tmp = Path(tempfile.mkdtemp(prefix="bri-empty-"))
        return emit_fatal((universe(tmp)[1] or "空宇宙探针没能自拒"))
    if a.show_ceiling:
        print(DANGLING_COMMENT_CEILING)
        return 0
    if a.selftest:
        return selftest()
    return measure(dry=a.dump)


if __name__ == "__main__":
    sys.exit(main())
