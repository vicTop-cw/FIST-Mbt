#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_scripts_index.py — 工具类辅助代码单一索引守卫（R62，词界判据修复）。

项目整洁 / 工具统一管理：所有「正式」辅助脚本（无 `_` 前缀）都必须在
`scripts/README.md` 中被登记，否则视为「漏登记」——把拳头①「地图一目了然」下沉到
工具层，并防新生脚本不留说明就堆积。

与 check_badge / check_tools_sync / check_test_sync 同一守卫家族，可挂 CI。

判据（本单修复：子串假绿 → 文件名 token 词界匹配）
------------------------------------------------
旧判据 `name in index_text or base in index_text` 是**子串**匹配：fist.py 的基名
`fist` 只要被 `run_fist_mbt_http.py` / `pentad_fist.py` 这类条目的正文子串命中就算「已
登记」，于是最常用的入口 `fist.py` 从未被要求登记。

新判据：完整文件名 **或** 去扩展名基名，都要以「完整词」命中索引——词界 = 前后不紧邻
文件名字符 `[A-Za-z0-9_-]`。于是 `fist` 不再命中 `fist-mbt-http`（其后紧跟 `-`）或
`pentad_fist`（其前紧邻 `_`），但仍是独立出现的 `fist` 或 `fist.py`（其后是 `.`，非文件
名字符）的合法命中。完整文件名同样走词界，`fist.py` 也不会被 `xfist.py` 这类更长的名字
子串喂绿。

用法：
    python scripts/check_scripts_index.py            0=全登记 / 1=有漏登记（逐条打印）
    python scripts/check_scripts_index.py --selftest 0=判据自检全绿 / 1=有对照格未过
"""
import re
import subprocess
import sys
from pathlib import Path

# BUG-58：守卫的“红”必须是判据红。Windows 默认 GBK 控制台下，中文结论里的 ↔ 等字符
# 会让 print 直接 UnicodeEncodeError——拿到 traceback 而不是 verdict，本地就等于“守卫不可信”。
# 统一把 stdout/stderr 钉成 UTF-8（CI 在 Linux UTF-8 下是无损 no-op）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "scripts"
README = SCRIPTS / "README.md"

# 无需登记的固定文件（文档/配套数据，非"工具"）
IGNORE_NAMES = {"README.md", "scoring_rubric.md", "_score_probe.py"}


def exempt_basenames():
    """从 `run_guards.EXEMPT_RULES` 读「**显式文件名**」豁免（只认 base 完全相等的那些）。

    ## 为什么要有这一条（判例-16 的反向：判据面口径不一致）

    `run_guards.py` 的宇宙只扫 `.py`（`if not f.endswith(".py"): continue`），
    而本判据扫 `scripts/` 下**所有被跟踪文件**（含 `.sh`）。同一件事
    「这个脚本是不是正式工具、要不要登记」，两个真源给出不同答案 ——
    `tmp_audit_preservation_scan.py` 就因此被夹在中间：run_guards 说「一次性取证器，豁免」，
    本判据说「没登记，是缺口」。

    ## 为什么只认「显式文件名」不认「前缀族」

    `EXEMPT_RULES` 里有两类：
      · 显式文件名（以 `.py` 结尾，如 `"tmp_audit_preservation_scan.py"`）—— **精确**，可放心复用
      · 前缀族（如 `"probe.py"` / `"simulate_"` / `"score_gate"`）—— **宽**，
        自动豁免它们会连带放过将来新增的同前缀脚本 ⇒ 判据面**过宽**（判据面窄的反向病）
    故这里只收前者，且要求 base **完全相等**（不是前缀匹配，也不是后缀匹配）。

    取不到 run_guards（import 失败 / 无该属性）⇒ 返回空集（**退回严格模式，宁可报红**，
    绝不因为读不到豁免表就让判据静默变宽）。
    """
    try:
        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "_run_guards_for_exempt", str(SCRIPTS / "run_guards.py"))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)          # run_guards 的模块级定义无副作用（只定义常量/函数）
        rules = getattr(mod, "EXEMPT_RULES", None) or ()
    except Exception:
        return {}
    # run_guards._match_rule 对**所有** .py 结尾条目都做前缀匹配
    # （`base == pat or base.startswith(pat[:-3])`）⇒ 每条 .py 规则天生是前缀族。
    # 区别只在于 stem 是不是「有意做前缀的通用词根」。下面的词表就是这条分界：
    # 落在表里的 ⇒ 前缀族（不当作精确豁免）；其余 ⇒ 当作显式文件名。
    # 保守原则：判不准的一律按前缀族处理（= 不豁免 = 判据更严，宁可多报一条红）。
    GENERIC_STEMS = {
        "probe", "demo", "verify", "selfdrive", "tmp", "test", "scan",
        "_verify", "_selfdrive", "scratch", "experiment", "playground",
    }

    def _is_prefix_family(stem):
        """该 stem 是否通用词根（⇒ 规则本意是按前缀覆盖一族文件）。"""
        if stem.startswith("_"):          # 以 _ 开头 = 明确的一族一次性脚本
            return True
        if stem in GENERIC_STEMS:
            return True
        # 单段且过短（<=5）也按通用词根处理：`demo` / `tmp` 这类
        if "_" not in stem and len(stem) <= 5:
            return True
        return False

    out = {}
    for item in rules:
        try:
            pat, why = item
        except (TypeError, ValueError):
            continue
        if not (isinstance(pat, str) and isinstance(why, str) and pat.endswith(".py")):
            continue
        if _is_prefix_family(pat[:-3]):
            continue                      # 前缀族：自动豁免会连带放过一族，不认
        out.setdefault(pat, why)
    return out

# 文件名字符集：文件名里出现的、构成"一个词"的字符（字母/数字/下划线/连字符）。
# 完整文件名 / 基名要作为「完整词」被登记，其前后不得紧邻这些字符——`.`（扩展名分隔）
# / 空格 / 反引号 / CJK 都不是文件名字符，故都视为词界。
_NAME_CHAR = r"[A-Za-z0-9_\-]"


def _whole_name_hit(index_text: str, token: str) -> bool:
    """token 是否以「完整词」形式出现在 index_text 里（前后不紧邻文件名字符）。

    与裸 `token in index_text` 的差异正是要治的子串假绿：`fist` 不再命中
    `fist-mbt-http`（后随 `-`，词界不成立）或 `pentad_fist`（前邻 `_`，词界不成立），
    但仍是独立 `fist` / `fist.py`（后随 `.`，词界成立）的合法命中。
    """
    pat = r"(?<!%s)%s(?!%s)" % (_NAME_CHAR, re.escape(token), _NAME_CHAR)
    return re.search(pat, index_text) is not None


def is_registered(name: str, index_text: str) -> bool:
    """正式脚本 name 是否已在索引登记：完整文件名或去扩展名基名，均需完整词命中。"""
    base = Path(name).stem
    return _whole_name_hit(index_text, name) or _whole_name_hit(index_text, base)


def missing_scripts(names, index_text: str):
    """返回未登记（完整词未命中）的脚本名列表；空列表 = 全登记 = 判绿。"""
    return [n for n in names if not is_registered(n, index_text)]


def _tracked_names():
    """Git 跟踪面里 `scripts/` 下（顶层）的文件名集合。取不到 git（非仓/无 git）返回 None。

    **为什么必须先过这一面**（2026-10-24 实测）：`.gitignore` 第 110/111/135/137 行挡着
    四份**本机专属**脚本（`pol_keeper_run.py` / `pol_keeper_wrapper.ps1` /
    `pol_keeper_prompt.md` / `fix_esm_require.py`）。只扫工作树的旧版会要求「为不在仓库里的
    文件登记」——要么逼人往 README 里写不属于本仓的条目，要么这条判据长期红着没人读。
    口径与 `run_guards.universe_files()` 同源：**宇宙 = 会被别人克隆到的文件**。
    返回 None 时调用方退回原行为（保持离线可用，不把「读不到」当「没有」）。
    """
    try:
        p = subprocess.run(
            ["git", "-C", str(SCRIPTS.parent), "ls-files", "-z", "--", "scripts"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if p.returncode != 0:
        return None
    names = set()
    for rel in p.stdout.decode("utf-8", "replace").split("\0"):
        if not rel:
            continue
        rel = rel.replace("\\", "/")
        if rel.startswith("scripts/") and rel.count("/") == 1:
            names.add(rel[len("scripts/"):])
    return names or None


def formal_scripts():
    """列出 scripts/ 下所有「正式」工具文件名（排除 _ 前缀临时脚本与固定文档）。"""
    tracked = _tracked_names()
    ok = []
    for p in SCRIPTS.iterdir():
        if not p.is_file():
            continue
        name = p.name
        if name in IGNORE_NAMES:
            continue
        if name.startswith("_"):
            continue  # 临时脚本不要求登记（即用即清）
        if tracked is not None and name not in tracked:
            continue  # gitignored 的本机私人物件不是「仓里的脚本」，不要求登记
        ok.append(name)
    return ok


def check() -> int:
    """真判据：扫 scripts/ 正式脚本，对 scripts/README.md 做完整词登记校验。"""
    if not README.exists():
        print(f"FAIL 缺少索引 {README}")
        return 1
    index_text = README.read_text(encoding="utf-8")
    # 判例-16 反向（口径不一致）：run_guards 已判「一次性工具、豁免」的，本判据不再要求登记。
    # 只认显式文件名 —— 前缀族不自动豁免（否则判据面过宽）。豁免必须**打印理由**，不静默。
    exempt = exempt_basenames()
    missing = missing_scripts(formal_scripts(), index_text)
    skipped = [m for m in missing if m in exempt]
    missing = [m for m in missing if m not in exempt]
    for m in skipped:
        print("  豁免（run_guards.EXEMPT_RULES 显式文件名规则）：%s —— %s"
              % (m, exempt[m][:120]))
    if missing:
        print("FAIL 以下正式辅助脚本未在 scripts/README.md 登记（工具统一管理缺口）：")
        for m in missing:
            print("  - " + m)
        return 1
    print("PASS 工具类辅助代码单一索引完整：所有正式脚本均已在 scripts/README.md 登记")
    return 0


def selftest() -> int:
    """判据自检（合成对照，不碰真 README）：证明子串假绿已消除、真登记不误伤。"""
    cells = []


    def cell(name, ok, detail):
        cells.append((name, ok, detail))


    # ── 判例-16 反向：豁免面必须**只认显式文件名**（判据面不得变宽）────────────────
    # ① 显式文件名规则生效（tmp_audit_preservation_scan.py 在 run_guards 里就是这个形状）
    ex = exempt_basenames()
    cell(
        "exempt-explicit-filename-taken",
        ("tmp_audit_preservation_scan.py" in ex),
        "run_guards.EXEMPT_RULES 里的显式文件名条目必须被本判据认到",
    )
    # ② 前缀族规则**不得**被收进来（否则将来新增 probe_xxx.py 会被静默放过）
    cell(
        "exempt-prefix-family-rejected",
        not any(k in ("probe.py", "simulate_", "score_gate") for k in ex.keys()),
        "前缀族规则（probe.py / simulate_ / score_gate）不得自动豁免 —— 判据面过宽",
    )
    # ③ 豁免表里的每个 key 都必须以 .py 结尾（结构护栏：只收显式文件名）
    cell(
        "exempt-all-keys-are-explicit-py",
        all(k.endswith(".py") for k in ex.keys()),
        "豁免表只许含显式文件名（.py 结尾）",
    )

    # ① 本单要求的对照格：子串命中但完整文件名不在索引里 ⇒ 必须判红（判为未登记）。
    #    索引里只有 run_fist_mbt_http.py（fist 是其子串），既无完整文件名 fist.py 也无独立
    #    词 fist ⇒ 旧子串判据会假绿，新词界判据必须把它点名为未登记。
    cell(
        "substring-hit-fullname-not-in-index-must-be-red",
        missing_scripts(["fist.py"], "- `run_fist_mbt_http.py` — HTTP 服务入口。") == ["fist.py"],
        "fist 是 run_fist_mbt_http.py 的子串，但 fist.py 未登记 ⇒ 必须判红（不再假绿）",
    )

    # ② 完整文件名登记（反引号包裹，真实登记形状）⇒ 仍是登记，不误伤。
    cell(
        "full-filename-registered-still-green",
        missing_scripts(["fist.py"], "- `fist.py` — 主入口。") == [],
        "完整文件名 fist.py 在索引里（反引号词界成立）⇒ 仍是登记",
    )

    # ③ 基名作为独立词登记（前后非文件名字符）⇒ 仍是登记，不误伤。
    cell(
        "base-as-whole-word-registered-still-green",
        missing_scripts(["fist.py"], "主入口：fist（见文档）。") == [],
        "基名 fist 前后非文件名字符（独立词）⇒ 仍是登记",
    )

    # ④ 反向对照：完整文件名 / 基名都只是另一条目的子串（前后紧邻文件名字符 _ / -）⇒ 判红。
    cell(
        "base-substring-of-other-entry-must-be-red",
        missing_scripts(["fist.py"], "- `pentad_fist.py` — 衍生项目客户端。") == ["fist.py"],
        "fist 在 pentad_fist 里只是子串（前邻 _，词界不成立）⇒ 不算登记",
    )

    failed = [n for (n, ok, _d) in cells if not ok]
    for (n, ok, d) in cells:
        print(("  OK   " if ok else "  FAIL ") + n + " — " + d)
    if failed:
        print("SELFTEST FAIL %d/%d 未过：%s" % (len(failed), len(cells), ", ".join(failed)))
        sys.exit(1)  # NO_CALL_FACE J2：自检函数自己就是调用面
    print("SELFTEST PASS %d/%d（子串假绿已消除、真登记不误伤）" % (len(cells), len(cells)))
    sys.exit(0)  # NO_CALL_FACE J2：自检函数自己就是调用面


def main() -> int:
    unknown = [a for a in sys.argv[1:] if a.startswith("--") and a != "--selftest"]
    if unknown:
        print("FATAL 未知参数：%s（本尺只接受 --selftest）" % " ".join(unknown))
        sys.exit(2)
    # ↑ 严格参数面（R65）：未知旗标不再被静默忽略（拼错 --selftest 会假绿）
    if "--selftest" in sys.argv[1:]:
        return selftest()
    return check()


if __name__ == "__main__":
    sys.exit(main())
