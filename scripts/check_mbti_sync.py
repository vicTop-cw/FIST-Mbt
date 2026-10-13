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
PAT_PUB_FN = re.compile(r"^\s*pub fn (\w+)")
# `moon info` 生成的接口面在同一模块里只声明 pub 项；本判据只取 pub fn 这一形状。


def tracked(root=None):
    root = root or ROOT
    try:
        r = subprocess.run(["git", "-C", root, "ls-files", "-z"],
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
    except Exception as e:
        raise SystemExit("FATAL 无法调用 git ls-files（%s）—— 拒绝在无枚举时出绿灯" % e)
    if r.returncode != 0:
        raise SystemExit("FATAL git ls-files 退出码 %s" % r.returncode)
    files = [x.replace("\\", "/") for x in (r.stdout or "").split("\0") if x.strip()]
    if not files:
        raise SystemExit("FATAL git ls-files 返回空清单 —— 拒绝在无枚举时出绿灯")
    return files


def collect_pub_fn(text):
    out = set()
    for l in text.splitlines():
        m = PAT_PUB_FN.match(l)
        if m:
            out.add(m.group(1))
    return out


def judge(pkg_decls, pkg_defs):
    """pkg_decls = {pkg_dir: {声明名}}；pkg_defs = {pkg_dir: {源里的 pub fn 名}}。
    返回 (问题列表, 检查过的声明数)。"""
    problems = []
    n = 0
    for d in sorted(pkg_decls):
        # 用 .get 而非 `if d not in pkg_defs: continue`：后者被变异去掉时会 KeyError 崩掉，
        # 而"判据自己崩"按本仓纪律属"尺子坏了"档，不该被读成读数。.get 让缺包直接体现为
        # 「声明集 − 空集」；该保护由 selftest 的 no-mbt-package-skipped 格反向锁定。
        defs = pkg_defs.get(d)
        if defs is None:
            continue      # 无 .mbt 的包：本轮不判（如历史遗留的 omega/pkg.generated.mbti）
        miss = pkg_decls[d] - defs
        for name in sorted(miss):
            n += 1   # 缺的也算检查过（否则防空转门会失效）
            problems.append(
                "M1 %s/%s 声明了 `pub fn %s`，但同包 .mbt 里找不到该定义 "
                "——接口面声明了但实现未提交（干净树 moon check 会报 unbound）"
                % (d, MBTI_NAME, name)
            )
        n += len(pkg_decls[d] & defs)
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
    p, n = safe_judge("clean-no-false-positive", {'src/a': {'foo', 'bar'}}, {'src/a': {'foo', 'bar', 'baz'}})
    cell("clean-no-false-positive", len(p) == 0, True)
    print("  ok  clean-no-false-positive（%d 条声明，0 违例）" % n)

    # 2) 合成违例：声明多一个 ⇒ 必红
    p, n = safe_judge("synthetic-violation-caught", {'src/a': {'foo', 'ghost'}}, {'src/a': {'foo'}})
    cell("synthetic-violation-caught", any('ghost' in x for x in p), True)
    print("  ok  synthetic-violation-caught（%s）" % (p[0][:76] if p else "未编制"))

    # 3) 真实形状：本轮 HEAD 的 4 个缺符号 ⇒ 必红（用真实名字）
    real = {'src/server': {'do_evolve_asset_register_with_search', 'parse_search_lines',
                           'register_supervisor_tools', 'self_search_runner_default'},
            }
    p, n = safe_judge("real-shape-4-symbols-caught", real, {'src/server': set()})
    cell("real-shape-4-symbols-caught", len(p) == 4, True)
    print("  ok  real-shape-4-symbols-caught（master 第二次坏状态原形：4 个符号全点名）")

    # 4) 非 pub 的内部函数不进 .mbti ⇒ 不得被当缺定义（本判据只收集 pub fn，天然不误红）
    p, n = safe_judge("private-fn-not-considered", {'src/a': {'foo'}}, {'src/a': {'foo'}})
    cell("private-fn-not-considered", len(p) == 0, True)
    print("  ok  private-fn-not-considered")

    # 5) 无 .mbt 的包不判（omega 那类历史遗留）
    p, n = safe_judge("no-mbt-package-skipped", {'omega': {'x'}}, {})
    cell("no-mbt-package-skipped", len(p) == 0 and n == 0, True)
    print("  ok  no-mbt-package-skipped（无 .mbt 的包不参与）")

    # 6) 口径守卫：本判据只收 `pub fn`（内部 fn 不进 .mbti）。
    #    变异实测暴露过这处覆盖缺口：把正则放宽成 `(?:pub )?fn` 时，上面 5 格全绿 ⇒ 判据变假绿。
    got_pub = collect_pub_fn("pub fn a() -> Unit\nfn b() -> Unit\n  fn c() -> Unit\n")
    cell("only-pub-fn-collected", got_pub == {"a"}, True)
    print("  ok  only-pub-fn-collected（只收 `pub fn a`，内部 fn 不入声明集）")

    # 7) 缺声明必须计入 n（否则"判据空转"门会失效：全缺时把 n 算成 0 就自拒不报红了）。
    _, n_miss = safe_judge("missing-counted-in-n", {'src/z': {'ghost'}}, {'src/z': set()})
    cell("missing-counted-in-n", n_miss >= 1, True)
    print("  ok  missing-counted-in-n（缺的也算检查过，防空转门失效）")

    bad_cells = [(nm, why) for nm, ok, why in cells if not ok]
    if bad_cells:
        print("SELFTEST FAIL：")
        for nm, why in bad_cells:
            print("  - %s：%s" % (nm, why))
        return 1
    print("SELFTEST OK（%d 格：干净不误红 / 合成违例必红 / 真实 4 符号必红 / 私有函数不误 / 无 .mbt 包跳过 / 只收 pub fn / 缺额计入空转门）"
          % len(cells))
    return 0


def read_tracked(rel):
    """读跟踪面里某文件的正文。读不到 ⇒ FATAL(2)：判据无法自证，绝不冒用 1 那一档。"""
    p = os.path.join(ROOT, rel)
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError as e:
        raise SystemExit("FATAL 跟踪面里的 %s 读不到（%s）—— 判据无法自证，拒绝出读数" % (rel, e))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()

    files = tracked()
    mbti = [f for f in files if f.endswith(MBTI_NAME)]
    if not mbti:
        raise SystemExit("FATAL 跟踪面里一份 %s 都没枚举到 —— 判据空转，拒绝报绿" % MBTI_NAME)

    pkg_decls = {}
    for p in mbti:
        pkg_decls[os.path.dirname(p)] = collect_pub_fn(read_tracked(p))

    pkg_defs = {}
    for f in files:
        if not f.endswith(".mbt"):
            continue
        d = os.path.dirname(f)
        if d not in pkg_decls:
            continue
        pkg_defs.setdefault(d, set()).update(collect_pub_fn(read_tracked(f)))

    # 尺子坏了必须自报（不可冒用 1 那一档）：judge() 自身若抛（如实现被改成直接下标而缺包），
    # 那是判据异常，不是"接口面有缺陷"。变异实测正是靠这一格把「去掉 .get 保护」那一处抓住。
    try:
        problems, n = judge(pkg_decls, pkg_defs)
    except Exception as e:
        raise SystemExit("FATAL 判据自身异常（%s: %s）—— 尺子坏了，先修判据再读读数"
                         % (type(e).__name__, e))

    if n == 0:
        raise SystemExit("FATAL 全仓 .mbti 里一条 pub fn 声明都没有 —— 判据空转，拒绝报绿")
    if problems:
        print("FAIL .mbti 接口声明 ↔ 源定义 一致性守卫（扫 %d 份 .mbti、%d 条 pub fn 声明）："
              % (len(pkg_decls), n))
        for x in problems:
            print("  - " + x)
        return 1
    print("PASS .mbti 接口声明 ↔ 源定义一致：%d 份 .mbti 的 %d 条 pub fn 声明在同包 .mbt 里都有定义"
          % (len(pkg_decls), n))
    return 0


if __name__ == "__main__":
    sys.exit(main())
