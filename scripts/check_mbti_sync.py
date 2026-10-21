#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_mbti_sync.py — `.mbti` 接口声明 ↔ 源文件定义 一致性守卫。

**为什么需要它（2026-10-13 第二次 master 坏状态实测）**：
HEAD 的 `src/server/pkg.generated.mbti`（`moon info` 生成的接口面，文件头写明 DON'T EDIT IT）
声明了 4 个**源文件里并不存在**的 pub fn：
  `do_evolve_asset_register_with_search` / `parse_search_lines` /
  `register_supervisor_tools` / `self_search_runner_default`
而这些实现只在工作树（`.mbt` 未提交）⇒ 干净树 `moon check` 报
`The value identifier … is unbound`（共 20 errors），CI 红在 `Migrate` 步、其后全部步 skip。

这与上一轮的 `src/diff` 悬空 import 同族：**"接口面先提交、实现面未提交"**。
`check_pkg_imports` 只能判"包目录是否存在"，**判不了符号级缺失**——本判据补的正是这一格。

**判据**（窄口径，只判确定性问题）：
  M1 每个 `<pkg>/pkg.generated.mbti` 里的 `pub fn <name>` 声明，**同包的 `.mbt` 文件里
     必须能找到 `pub fn <name>` 定义**（文本级：同名顶层 pub fn 即算）。找不到即红，
     并点名"接口面声明了但实现未提交"。
     派生方法例外：`\w+` 在 `pub fn T::m(...)` 上只收到 `T`，而 `derive(Eq, Debug)` 生成的
     方法在源码里没有 `fn` 文本 ⇒ 源侧把**带 derive 标注的类型名**也收进 `fn` 定义集
     （`collect_defs` 的 derive 承载格）。类型没带 derive 时照红，真缺实现不放水。
  待确认：`pub let` / `pub const` / `pub type` 等其它声明形状**本轮不判**（先只在 `pub fn` 上做实）。

**刻意不判**（避免误红）：
  - 非 pub 的 fn（内部函数不进 `.mbti`）
  - 无 `.mbti` 的包、无 `.mbt` 的包（`omega/pkg.generated.mbti` 这类历史遗留，本轮不参与）
  - `.mbti` 与源里同名但签名不同（签名一致性属 `moon info` 的职责，本判据只判"名字在不在"）

**防空转**：一份 `.mbti` 都枚举不到、或全仓零条 `pub fn` 声明 ⇒ FATAL（判据空转 ≠ 没问题）。

用法：
  python scripts/check_mbti_sync.py [--selftest]
  0=PASS / 1=违例 / 2=判据无法自证（FATAL）
"""
import argparse
import os
import re
import subprocess
import sys

# BUG-138 同族：中文结论里的 ⇒ 在 Windows 默认 cp936 控制台会先崩掉 print（rc 被读成「缺陷在场」）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MBTI_NAME = "pkg.generated.mbti"
# `moon info` 的接口面只列 pub 项。本判据按**形状**分别收集并比对（2026-10-13 扩展：
# 先只在 `pub fn` 上做实，随后预判"健康树零误报"通过后扩到 6 种形状）。
# 形状 → (.mbti 里的声明正则, 源 .mbt 里的定义正则)
#   源侧允许 `pub` / `pub(all)` / 无前缀三种写法（`.mbti` 只列 pub 项，但源码里可能写 pub(all)）。
SHAPES = {
    "fn":     (re.compile(r"^\s*pub fn (\w+)"),
               re.compile(r"^\s*(?:pub(?:\(all\))? )?fn (\w+)")),
    "struct": (re.compile(r"^\s*pub (?:all\()?struct (\w+)"),
               re.compile(r"^\s*(?:pub(?:\(all\))? )?struct (\w+)")),
    "enum":   (re.compile(r"^\s*pub (?:all\()?enum (\w+)"),
               re.compile(r"^\s*(?:pub(?:\(all\))? )?enum (\w+)")),
    "const":  (re.compile(r"^\s*pub const (\w+)"),
               re.compile(r"^\s*(?:pub(?:\(all\))? )?const (\w+)")),
    "let":    (re.compile(r"^\s*pub let (\w+)"),
               re.compile(r"^\s*(?:pub(?:\(all\))? )?let (\w+)")),
    "trait":  (re.compile(r"^\s*pub trait (\w+)"),
               re.compile(r"^\s*(?:pub(?:\(all\))? )?trait (\w+)")),
}
# `derive(...)` 的两种落点：闭合行 `} derive(Eq, Debug)` 与一行式 `pub type T = Int derive(Eq)`。
TYPE_HDR = re.compile(r"^\s*(?:pub(?:\(all\))? )?(?:struct|enum|trait|type|abstract)\s+(\w+)\b")
DERIVE_TAIL = re.compile(r"^\s*\}.*\bderive\(")
<<<<<<< HEAD


def emit_fatal(msg):
    """判据无法自证 ⇒ **真给 2**（写 stderr，由调用点的 `raise SystemExit(emit_fatal(…))` 落成退出码）。

    BUG-369：改前本份有 7 处 `raise SystemExit("FATAL …")`，而带字符串的 SystemExit 退出码是 **1**
    ⇒ 第 34 行自述的「2=判据无法自证（FATAL）」从来没有生效过，「尺子坏了」与「接口面有违例」
    在退出码面上同色（CI 与电池里按 2 写的期望文本也一直对着一个不存在的码）。刻意不用 `raise SystemExit(msg)`。
    """
    sys.stderr.write(msg + "\n")
    return 2
=======
>>>>>>> df8ba1a1 (fix(idiom): 清零 0079 implicit_impl_as_method 全族 63 条 + 修守卫 derive 盲区)


def tracked(root=None):
    root = root or ROOT
    try:
        r = subprocess.run(["git", "-C", root, "ls-files", "-z"],
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
    except Exception as e:
        raise SystemExit(emit_fatal("FATAL 无法调用 git ls-files（%s）—— 拒绝在无枚举时出绿灯" % e))
    if r.returncode != 0:
        raise SystemExit(emit_fatal("FATAL git ls-files 退出码 %s" % r.returncode))
    files = [x.replace("\\", "/") for x in (r.stdout or "").split("\0") if x.strip()]
    if not files:
        raise SystemExit(emit_fatal("FATAL git ls-files 返回空清单 —— 拒绝在无枚举时出绿灯"))
    return files


def collect_decls(text):
    """从 .mbti 正文收集 {形状: {声明名}}（只认 .mbti 侧正则）。"""
    out = {}
    for shape, (pat, _) in SHAPES.items():
        names = set()
        for l in text.splitlines():
            m = pat.match(l)
            if m:
                names.add(m.group(1))
        out[shape] = names
    return out


def collect_defs(text):
    """从源 .mbt 正文收集 {形状: {定义名}}（只认源侧正则，允许 pub(all)/无前缀）。

    `fn` 形状额外收下**带 `derive(...)` 的类型名**：`.mbti` 里 `pub fn T::to_repr(...)`
    这类行按现有正则两侧都只收到 `T`（`\w+` 停在 `::` 前），而 derive 生成的方法在源码里
    没有 `fn` 文本、只有闭合行上的 `derive(Eq, Debug)` 标注。不收这一格，`0079`
    的 `pub extend T with ...::{...}` 修复就会让"只有派生方法、没有手写方法"的类型误红
    （实测 12 个类型）。收进来之后仍然判得住真正的缺实现：类型没带 derive ⇒ 照红。
    """
    out = {}
    for shape, (_, pat) in SHAPES.items():
        names = set()
        for l in text.splitlines():
            m = pat.match(l)
            if m:
                names.add(m.group(1))
        out[shape] = names
    pending = None
    for l in text.splitlines():
        h = TYPE_HDR.match(l)
        if h:
            pending = h.group(1)
            if "derive(" in l:      # 一行式：`pub type T = Int derive(Eq)`
                out["fn"].add(pending)
                pending = None
            continue
        if pending and DERIVE_TAIL.match(l):
            out["fn"].add(pending)
            pending = None
    return out


def judge(pkg_decls, pkg_defs, wt_defs=None):
    """pkg_decls = {pkg_dir: {形状: {声明名}}}；pkg_defs = {pkg_dir: {形状: {定义名}}}。
    返回 (问题列表, 检查过的声明数)。

    形状逐个比（2026-10-13 从 pub fn 单形状扩到 6 种）：先只在 fn 上做实，
    随后经"健康树零误报"预判（`temp/feasibility_shapes.py`：struct 57 / enum 21 /
    const 12 / let 5 / trait 2 在健康树里缺口均为 0）才扩面。

    `wt_defs`（可选）= 同一形状结构、取自**工作树磁盘**的定义集。给了它就能在红文案里
    **分流出路**（2026-10-13 加）：「实现已在工作树、只是没提交」vs「跟踪面与工作树都找不到 ⇒ 真缺失」
    —— 前者出路是 commit，后者出路是写实现；两者文案相同会让读的人走错方向（本会话就踩过：
    工作树明明有实现，却按"未实现"去找代码）。不给 wt_defs 时保持原文案（向后兼容）。"""
    problems = []
    n = 0
    for d in sorted(pkg_decls):
        # 用 .get 而非 `if d not in pkg_defs: continue`：后者被变异去掉时会 KeyError 崩掉，
        # 而"判据自己崩"按本仓纪律属"尺子坏了"档，不该被读成读数。.get 让缺包直接体现为
        # 「声明集 − 空集」；该保护由 selftest 的 no-mbt-package-skipped 格反向锁定。
        defs = pkg_defs.get(d)
        if defs is None:
            continue      # 无 .mbt 的包：本轮不判（如历史遗留的 omega/pkg.generated.mbti）
        for shape in sorted(SHAPES):
            a = pkg_decls[d].get(shape, set())
            b = defs.get(shape, set())
            for name in sorted(a - b):
                n += 1   # 缺的也算检查过（否则防空转门会失效）
                hint = "接口面声明了但实现未提交（干净树 moon check 会报 unbound/not found）"
                if wt_defs is not None:
                    wt_b = (wt_defs.get(d) or {}).get(shape, set())
                    if name in wt_b:
                        hint = ("**实现已在工作树磁盘上、只是没进跟踪面** ⇒ 出路是 `git add` 该文件并提交"
                                "（不是缺实现）；判据按跟踪面判，故此处仍红")
                    else:
                        hint = ("**跟踪面与工作树磁盘都找不到该定义** ⇒ 出路是补实现"
                                "（或从 .mbti 里撤掉这条声明）")
                problems.append(
                    "M1 %s/%s 声明了 `pub %s %s`，但同包 .mbt 里找不到该定义 ——%s"
                    % (d, MBTI_NAME, shape, name, hint)
                )
            n += len(a & b)
    return problems, n


def selftest():
    """合成违例自证：判据必须先证明它会红，且干净输入不误红。"""
    cells = []
    def cell(name, got, want):
        cells.append((name, bool(got) == bool(want), "got=%s want=%s" % (got, want)))

    def safe_judge(name, decls, defs):
        """judge() 抛异常 ⇒ 记成"尺子坏了"这一格失败（不冒用读数，也不让 traceback 冒充红）。
        变异实测正是靠它把「去掉 .get 保护」那一处抓住：改回直接下标会 KeyError。"""
        try:
            return judge(decls, defs)
        except Exception as e:
            cells.append((name + "-judge-crashed", False,
                          "judge() 抛 %s: %s（尺子坏了，不是接口面缺陷）" % (type(e).__name__, e)))
            return set(), 0

    # 1) 干净：声明与定义齐备 ⇒ 0 违例
    p, n = safe_judge("clean-no-false-positive",
                      {'src/a': {'fn': {'foo', 'bar'}}}, {'src/a': {'fn': {'foo', 'bar', 'baz'}}})
    cell("clean-no-false-positive", len(p) == 0, True)
    print("  ok  clean-no-false-positive（%d 条声明，0 违例）" % n)

    # 2) 合成违例：fn 声明多一个 ⇒ 必红
    p, n = safe_judge("synthetic-violation-caught",
                      {'src/a': {'fn': {'foo', 'ghost'}}}, {'src/a': {'fn': {'foo'}}})
    cell("synthetic-violation-caught", any('ghost' in x for x in p), True)
    print("  ok  synthetic-violation-caught（%s）" % (p[0][:76] if p else "未编制"))

    # 2b) 扩展形状的合成违例：struct 声明多一个 ⇒ 必红（证明 6 形状面各自可红）
    p, n = safe_judge("struct-violation-caught",
                      {'src/a': {'struct': {'Foo'}, 'fn': set()}}, {'src/a': {'struct': set(), 'fn': set()}})
    cell("struct-violation-caught", any('struct Foo' in x for x in p), True)
    print("  ok  struct-violation-caught（扩展形状可红）")

    # 3) 真实形状：本轮 HEAD 的 4 个缺符号 ⇒ 必红（用真实名字）
    real = {'src/server': {'fn': {'do_evolve_asset_register_with_search', 'parse_search_lines',
                                  'register_supervisor_tools', 'self_search_runner_default'}}}
    p, n = safe_judge("real-shape-4-symbols-caught", real, {'src/server': {'fn': set()}})
    cell("real-shape-4-symbols-caught", len(p) == 4, True)
    print("  ok  real-shape-4-symbols-caught（master 第二次坏状态原形：4 个符号全点名）")

    # 4) 非 pub 的内部函数不进 .mbti ⇒ 不得被当缺定义（本判据只收集 pub 项，天然不误红）
    p, n = safe_judge("private-fn-not-considered",
                      {'src/a': {'fn': {'foo'}}}, {'src/a': {'fn': {'foo'}}})
    cell("private-fn-not-considered", len(p) == 0, True)
    print("  ok  private-fn-not-considered")

    # 5) 无 .mbt 的包不判（omega 那类历史遗留）
    p, n = safe_judge("no-mbt-package-skipped", {'omega': {'fn': {'x'}}}, {})
    cell("no-mbt-package-skipped", len(p) == 0 and n == 0, True)
    print("  ok  no-mbt-package-skipped（无 .mbt 的包不参与）")

    # 6) 口径守卫：.mbti 侧只收 `pub fn`（内部 fn 不进 .mbti）。
    #    变异实测暴露过这处覆盖缺口：把 .mbti 侧正则放宽成 `(?:pub )?fn` 时，上面各格全绿 ⇒ 判据变假绿。
    got_pub = collect_decls("pub fn a() -> Unit\nfn b() -> Unit\n  fn c() -> Unit\n")["fn"]
    cell("only-pub-fn-collected", got_pub == {"a"}, True)
    print("  ok  only-pub-fn-collected（.mbti 侧只收 `pub fn a`，内部 fn 不入声明集）")

    # 6b) 源侧允许 `pub(all)`：collect_defs 必须认得 `pub(all) struct Foo` 这类写法，
    #     否则真定义会被当成"缺失"而误红（这是扩到 6 形状后新增的误报面）。
    src = 'pub(all) struct Foo {\n}\npub fn bar() -> Unit\nstruct Baz {\n}\n'
    dsrc = collect_defs(src)
    cell("src-pub-all-recognized", dsrc["struct"] == {"Foo", "Baz"}, True)
    print("  ok  src-pub-all-recognized（源侧 pub(all)/无前缀都认，防扩展误红）")

    # 6c) derive 承载格（清零 0079 时实测到的误红面）：`.mbti` 里 `pub fn T::to_repr(...)`
    #     这类行两侧正则都只收到 `T`（`\w+` 停在 `::` 前），而 derive 生成的方法在源码里没有
    #     `fn` 文本、只有闭合行上的 `} derive(Eq, Debug)`。不收这一格，"只有派生方法、没有手写
    #     方法"的类型在补 `pub extend` 后会集体误红（实发 12 个类型）；收了之后，同型不带 derive
    #     仍必须照红——否则这一格会把真缺实现一并放过。
    dsrc_derive = collect_defs("pub struct Foo {\n  x : Int\n} derive(Eq, Debug)\n")
    cell("derive-carrier-collected", "Foo" in dsrc_derive["fn"], True)
    p_d, _ = safe_judge("derive-carrier-no-false-positive",
                        {'src/a': {'fn': {'Foo'}}}, {'src/a': dsrc_derive})
    cell("derive-carrier-no-false-positive", len(p_d) == 0, True)
    dsrc_plain = collect_defs("pub struct Bar {\n  x : Int\n}\n")
    p_nd, _ = safe_judge("no-derive-carrier-still-red",
                         {'src/a': {'fn': {'Bar'}}}, {'src/a': dsrc_plain})
    cell("no-derive-carrier-still-red", any("Bar" in x for x in p_nd), True)
    print("  ok  derive-carrier 三格（带 derive 不误红 / 不带 derive 照红 / 类型名收进 fn 集）")

    # 7) 缺声明必须计入 n（否则"判据空转"门会失效：全缺时把 n 算成 0 就自拒不报红了）。
    _, n_miss = safe_judge("missing-counted-in-n",
                           {'src/z': {'fn': {'ghost'}}}, {'src/z': {'fn': set()}})
    cell("missing-counted-in-n", n_miss >= 1, True)
    print("  ok  missing-counted-in-n（缺的也算检查过，防空转门失效）")

    # 8) 出路分流（2026-10-13 新增）：给了 wt_defs 时，红文案必须区分
    #    「实现在工作树、未提交」与「跟踪面+工作树都找不到 ⇒ 真缺失」——两者出路不同
    #    （commit vs 补实现），文案相同会让读者走错方向。
    p_none = judge({'src/a': {'fn': {'ghost'}}}, {'src/a': {'fn': set()}}, wt_defs={'src/a': {'fn': set()}})[0]
    p_wt = judge({'src/a': {'fn': {'ghost'}}}, {'src/a': {'fn': set()}}, wt_defs={'src/a': {'fn': {'ghost'}}})[0]
    cell("hint-split-not-in-wt", any('都找不到该定义' in x for x in p_none), True)
    print("  ok  hint-split-not-in-wt（工作树也没有 ⇒ 报'出路是补实现'）")
    cell("hint-split-in-wt-uncommitted", any('已在工作树磁盘上、只是没进跟踪面' in x for x in p_wt), True)
    print("  ok  hint-split-in-wt-uncommitted（工作树有 ⇒ 报'出路是 git add 并提交'）")
    # 不给 wt_defs 时保持向后兼容（原文案）
    p_compat = judge({'src/a': {'fn': {'ghost'}}}, {'src/a': {'fn': set()}})[0]
    cell("hint-compat-without-wt", any('接口面声明了但实现未提交' in x for x in p_compat), True)
    print("  ok  hint-compat-without-wt（不给 wt_defs 时保持原文案）")

    # 9) 出口码自证（BUG-369 建议① / R43：改行为必须同时补一支「FATAL 的码真是 2」格）。
    #    本份原先 7 处 `raise SystemExit("FATAL …")` 全给 1，而承诺面第 34 行写着 2 ⇒ 空转与违例同色。
    #    这里考的是**进程退出码**，不是函数返回值 —— 返回值对不等于 rc 对。
    cell("emit-fatal-returns-2", emit_fatal("（自检探针，非违例）") == 2, True)
    print("  ok  emit-fatal-returns-2")
    import subprocess
    import tempfile
    d = tempfile.mkdtemp(prefix="mbti-fatal-")
    try:
        child = os.path.join(d, "child_fatal_rc.py")
        with open(child, "w", encoding="utf-8") as fh:
            fh.write("import importlib.util, sys\n"
                     "spec = importlib.util.spec_from_file_location('ms', %r)\n"
                     "m = importlib.util.module_from_spec(spec)\n"
                     "spec.loader.exec_module(m)\n"
                     "m.MBTI_NAME = 'no-such-mbti-face.mbti'\n"
                     "sys.argv = ['check_mbti_sync.py']\n"
                     "sys.exit(m.main())\n"
                     % os.path.abspath(__file__))
        pr = subprocess.run((sys.executable, child), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        cell("fatal-empty-scan-face-rc-is-really-2", pr.returncode == 2, True)
        print("  ok  fatal-empty-scan-face-rc-is-really-2（子进程实测 rc=%s；改前同一条只给 1）%s"
              % (pr.returncode,
                 "" if pr.returncode == 2 else "  ← stderr：%s"
                 % pr.stderr.decode("utf-8", "replace").strip()[-160:]))
    finally:
        import shutil
        shutil.rmtree(d, ignore_errors=True)

    bad_cells = [(nm, why) for nm, ok, why in cells if not ok]
    if bad_cells:
        print("SELFTEST FAIL：")
        for nm, why in bad_cells:
            print("  - %s：%s" % (nm, why))
        return 1
    print("SELFTEST OK（%d 格：干净不误红 / 合成违例必红 / 扩展形状(struct)可红 / 真实 4 符号必红 / "
          "私有函数不误 / 无 .mbt 包跳过 / .mbti 侧只收 pub 项 / 源侧认 pub(all) / "
          "derive 承载三格（带 derive 不误红、不带照红）/ 缺额计入空转门 / "
<<<<<<< HEAD
          "**出路分流两格（工作树有=未提交 / 工作树无=真缺失）+ 向后兼容一格** / "
          "**判据空转的退出码真是 2（两格：emit_fatal 返 2 + 子进程 rc 是 2）**）"
=======
          "**出路分流两格（工作树有=未提交 / 工作树无=真缺失）+ 向后兼容一格**）"
>>>>>>> df8ba1a1 (fix(idiom): 清零 0079 implicit_impl_as_method 全族 63 条 + 修守卫 derive 盲区)
          % len(cells))
    return 0


def read_tracked(rel):
    """读跟踪面里某文件的正文。读不到 ⇒ FATAL(2)：判据无法自证，绝不冒用 1 那一档。"""
    p = os.path.join(ROOT, rel)
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError as e:
        raise SystemExit(emit_fatal("FATAL 跟踪面里的 %s 读不到（%s）—— 判据无法自证，拒绝出读数" % (rel, e)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()

    files = tracked()
    mbti = [f for f in files if f.endswith(MBTI_NAME)]
    if not mbti:
        raise SystemExit(emit_fatal("FATAL 跟踪面里一份 %s 都没枚举到 —— 判据空转，拒绝报绿" % MBTI_NAME))

    pkg_decls = {}
    for p in mbti:
        pkg_decls[os.path.dirname(p)] = collect_decls(read_tracked(p))

    pkg_defs = {}
    for f in files:
        if not f.endswith(".mbt"):
            continue
        d = os.path.dirname(f)
        if d not in pkg_decls:
            continue
        cur = pkg_defs.setdefault(d, {})
        for shape, names in collect_defs(read_tracked(f)).items():
            cur.setdefault(shape, set()).update(names)

    # 工作树磁盘上的定义集（用于红文案的出路分流）：只在包目录里枚举 *.mbt。
    # 只读、不写；读不到的单个文件跳过（不影响判据主体判定）。
    wt_defs = {}
    for d in pkg_decls:
        absd = os.path.join(ROOT, d)
        if not os.path.isdir(absd):
            continue
        cur = wt_defs.setdefault(d, {})
        for fn in os.listdir(absd):
            if not fn.endswith(".mbt"):
                continue
            try:
                with open(os.path.join(absd, fn), encoding="utf-8", errors="replace") as f:
                    txt = f.read()
            except OSError:
                continue
            for shape, names in collect_defs(txt).items():
                cur.setdefault(shape, set()).update(names)

    # 尺子坏了必须自报（不可冒用 1 那一档）：judge() 自身若抛（如实现被改成直接下标而缺包），
    # 那是判据异常，不是"接口面有缺陷"。变异实测正是靠这一格把「去掉 .get 保护」那一处抓住。
    try:
        problems, n = judge(pkg_decls, pkg_defs, wt_defs=wt_defs)
    except Exception as e:
        raise SystemExit(emit_fatal("FATAL 判据自身异常（%s: %s）—— 尺子坏了，先修判据再读读数"
                                    % (type(e).__name__, e)))

    if n == 0:
        raise SystemExit(emit_fatal("FATAL 全仓 .mbti 里一条 pub 声明都没有 —— 判据空转，拒绝报绿"))
    if problems:
        print("FAIL .mbti 接口声明 ↔ 源定义 一致性守卫（扫 %d 份 .mbti、%d 条 pub 声明、%d 种形状）："
              % (len(pkg_decls), n, len(SHAPES)))
        for x in problems:
            print("  - " + x)
        return 1
    print("PASS .mbti 接口声明 ↔ 源定义一致：%d 份 .mbti 的 %d 条 pub 声明（%d 种形状）在同包 .mbt 里都有定义"
          % (len(pkg_decls), n, len(SHAPES)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
