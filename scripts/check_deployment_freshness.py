#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""scripts/check_deployment_freshness.py — 「部署产物是否落后于源码」判据（BUG-428，high）。

## 为什么需要它（2026-10-26 实测，代价 40 分钟 + 一次误判）
修复 commit `72986aa7`（20:40，BUG-417 孤儿 Omega 任务不再被归档门误拦）落地后，**三份部署产物全是旧代码**：

    PATH 上的 fist-mbt -> %LOCALAPPDATA%/FIST-Mbt/fist-mbt.js   Oct 26 11:59
    dist/fist-mbt.js                                            Oct 24 06:16
    _release/js/fist-mbt.js                                     Oct 18 16:34

而**现有的版本守卫打的是 PASS**：`check_dist_snapshot.py` 只比内嵌版本字符串
（`PASS 快照版本 0.3.10 == moon.mod 0.3.10`）—— 版本对得上，代码是旧的。
**实际损失不是"少跑一格"**：调用方调 MCP `archive` 被 Omega 门拦下 ⇒ **误判为「判定逻辑有缺陷」**，
花 40 分钟逐条查 orphan 判定的四个条件（全部正常），最后靠 A/B 对照才定位到是旧构建。
⇒ 需要一把按**内容**判新鲜度的尺，而不是再比一次版本号。

## 判定面（两个正交面 × 每份**存在的**产物；同一份产物只算一格）
- **时间面**：产物 mtime < `max(mtime of src/**/*.mbt, cmd/**/*.mbt, moon.pkg, moon.mod)` ⇒ 落后 lag 秒。
  （`cmd/**/*.mbt` 超出了题面给的 `src/**`：入口薄壳也进产物，只改 `cmd/` 同样该重建；这是**收紧**不是放宽。
  `*_test.mbt` / `*_wbtest.mbt` **不进基线**：它们只在 `moon test` 下编译，改测试不需要重建部署产物 ——
  算进去等于"跑几个测试就把部署面判红"。）
- **内容面**：产物正文里 grep 不到任一 `KEY_SYMBOLS` 的**调用形** ⇒ 代码旧。
  探针容忍 MoonBit 的 `_`→`__` 名字变形、且要求命中后紧跟 `(`（详见 `_deployment_symbols.py` 的两条实测）。

**产物面**（只有存在的才算一格；一个都没有 ⇒ 判据无法自证）：
1. PATH 里每个 `fist-mbt` 垫片（`.cmd` / `.bat` / `.ps1` / 无扩展名全认）→ 反解出它**真正执行**的 `.js`；
2. `%LOCALAPPDATA%/FIST-Mbt/fist-mbt.js`（可用 `FIST_DEPLOY_JS` 覆盖；POSIX 退 `~/.local/share/FIST-Mbt/`）；
3. 仓内 `dist/fist-mbt.js`、`_release/js/fist-mbt.js`；
4. `--artifact PATH` 追加的显式面。

## 两级严重度（为什么不是"落后就一律红"）
- **FAIL（驱动 rc=1）**：内容面缺符号（任何产物面）；**部署面**的时间面落后。
- **WARN（不驱动 rc）**：路径含 `_build/` 的**构建缓存**的时间面落后 —— 它是 `moon build` 的输出，
  按需重建、滞后是常态（改一行源码就落后）。把缓存滞后判成门禁红，等于让这把尺在正常开发中恒红；
  **恒红的判据没人读**（本仓 `check_hardcoded_paths` 收窄标定的同一条教训）。内容面对缓存照样硬判。

## 退出码（承诺面 = 实现面，逐档都有真出口）
`0` = 所有已判面新鲜 / `1` = 检出违规（内容面旧 / 部署面时间落后）/ `2` = **判据无法自证**（一个产物面都没有、
垫片解析不出目标、或源码基线读不到 —— 读不到数就无权说"新鲜"，绝不冒用 0）/ `4` = 尺子自己坏了
（探针脱锚：`KEY_SYMBOLS` 里的符号在今天的源码里已经没有 `fn <name>(` 定义；或未捕获异常）。

优先级 `4 > 1 > 2 > 0`：先保证尺子本身可信，再报违规，再谈"能不能判绿"。

## 用法
    python scripts/check_deployment_freshness.py                 # 判当前工作区（裸跑即可进电池）
    python scripts/check_deployment_freshness.py --selftest      # 尺子先证明自己会红（含变异对照）
    python scripts/check_deployment_freshness.py --symbols       # 打印探针表与它的维护面
    python scripts/check_deployment_freshness.py --artifact PATH # 追加一个面
"""
import argparse
import io
import os
import re
import shutil
import sys
import tempfile
import time

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from _deployment_symbols import (  # noqa: E402 — 同目录共享模块（`_` 前缀，豁免登记）
    KEY_SYMBOLS,
    KeySymbol,
    anchor_problems,
    count_calls,
    describe_symbols,
    found_report,
    missing_symbols,
    read_artifact,
    source_definitions,
)

ROOT = os.path.dirname(HERE)
SELF = os.path.basename(os.path.abspath(__file__))

# 垫片名的解析序：Windows 的 PATHEXT 里 .CMD 优先于无扩展名，故 .cmd 排前面（读数与人读一致）。
SHIM_NAMES = ("fist-mbt.cmd", "fist-mbt.bat", "fist-mbt.ps1", "fist-mbt")
# 构建缓存标记：命中 ⇒ 时间面落后只算 WARN（见模块文档「两级严重度」）。
BUILD_CACHE_MARKERS = ("_build/",)
BASELINE_DIRS = ("src", "cmd")
WALK_EXCLUDE = {"_build", ".git", ".mooncakes", "node_modules", "temp", "__pycache__",
                ".moon", ".moon-lock", "dist", "_release"}

# `node <旗标>* <路径.js|.cjs|.mjs>`: path may be quoted or bare.
# `(?<![A-Za-z0-9_.-])` keeps `node_modules` from matching.
# BUG-438 (1): extension widened from only `.js` to `.js/.cjs/.mjs` -- after BUG-437 the
#   PATH entry is `serve-launcher.cjs`, and the old vocabulary only knew `.js`, so both
#   shims reported UNPROVABLE forever. Those two lines are exactly the ones most worth
#   checking (precedent-33: a self-check must test the configuration wire).
# BUG-438 (2): the program token may be a variable, not only a literal `node` --
#   this repo's `.cmd` shim does `set "FIST_NODE=%ProgramFiles%\\nodejs\\node.exe"` then
#   `"%FIST_NODE%" "...\\serve-launcher.cjs"`. A literal-only regex never matches it.
RE_NODE_JS_CALL = re.compile(
    r'''(?<![A-Za-z0-9_.\-])'''
    r'''"?'''
    r'''(?:node(?:\.exe)?|%[A-Za-z_][A-Za-z0-9_]*%|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?)'''
    r'''"?'''
    r'''(?:\s+-{1,2}[^\s"']+)*\s+'''
    r'''(?:"([^"]+\.(?:js|cjs|mjs))"|'([^']+\.(?:js|cjs|mjs))'|([^\s"']+\.(?:js|cjs|mjs)))''',
    re.I,
)
RE_WIN_ABS = re.compile(r"^(?:[A-Za-z]:[\\/]|\\\\)")


# ---------------------------------------------------------------------------
# 面解析（纯函数 + 少量 IO）
# ---------------------------------------------------------------------------
def parse_shim_target(text, shim_dir=None):
    """纯函数：从垫片正文反解它**真正执行**的 `.js` 产物路径；解析不出 ⇒ None。

    只认「`node` 后跟一个 `.js` 实参」这一形状（本仓的 `.cmd` 与 POSIX sh 垫片就这一种）；
    中间允许旗标（`node --no-warnings "x.js"`）。`%~dp0` / `$PSScriptRoot` 是「相对垫片自身目录」
    的写法，给了 `shim_dir` 就拼成绝对形，不给就返回 None（宁可不判，也不猜一个错的）。
    两个路径时取**第一个**：垫片只执行第一个。
    """
    if not text:
        return None
    m = RE_NODE_JS_CALL.search(text)
    if not m:
        return None
    raw = (m.group(1) or m.group(2) or m.group(3) or "").strip()
    if not raw:
        return None
    for token in ("%~dp0", "$PSScriptRoot/", "$PSScriptRoot\\"):
        if raw.startswith(token):
            rest = raw[len(token):].lstrip("\\/")
            if shim_dir and rest:
                return os.path.normpath(os.path.join(shim_dir, rest.replace("\\", "/")))
            return None
    if RE_WIN_ABS.match(raw) or os.path.isabs(raw):
        return raw
    # BUG-438: `%LOCALAPPDATA%\FIST-Mbt\serve-launcher.cjs` style env placeholders must be
    # expanded, otherwise the path is never absolute and the shim face stays UNPROVABLE
    # forever. This is exactly the shape of the repo `.cmd` shim.
    expanded = os.path.expandvars(raw)
    if expanded != raw and (RE_WIN_ABS.match(expanded) or os.path.isabs(expanded)):
        return os.path.normpath(expanded)
    if shim_dir:
        return os.path.normpath(os.path.join(shim_dir, raw.replace("\\", "/")))
    return raw


def path_dirs(env):
    """PATH 目录列表（Windows 的 `Path` 大小写两种都认）。"""
    raw = env.get("PATH") or env.get("Path") or ""
    return [d for d in raw.split(os.pathsep) if d]


def deploy_js_path(env):
    """「部署副本」候选路径。`FIST_DEPLOY_JS` 覆盖；Windows 走 `%LOCALAPPDATA%`；POSIX 退 XDG 惯例路径。

    **不写死任何本机身份路径**：路径一律由环境变量拼出（`check_hardcoded_paths` 的 A 面律）。
    """
    override = env.get("FIST_DEPLOY_JS")
    if override:
        return override
    local = env.get("LOCALAPPDATA")
    if local:
        return os.path.join(local, "FIST-Mbt", "fist-mbt.js")
    data = env.get("XDG_DATA_HOME")
    if data:
        return os.path.join(data, "FIST-Mbt", "fist-mbt.js")
    home = env.get("HOME") or env.get("USERPROFILE")
    if home:
        return os.path.join(home, ".local", "share", "FIST-Mbt", "fist-mbt.js")
    return None


def shim_faces(env):
    """PATH 上的 `fist-mbt` 垫片 ⇒ 候选面。返回 (faces, unprovable)。"""
    faces, unprovable, seen = [], [], set()
    for d in path_dirs(env):
        for name in SHIM_NAMES:
            path = os.path.join(d, name)
            try:
                if not os.path.isfile(path):
                    continue
            except OSError:
                continue
            key = os.path.normcase(os.path.normpath(path))
            if key in seen:
                continue
            seen.add(key)
            text = read_artifact(path)
            if text is None:
                unprovable.append({"label": "PATH 垫片 %s" % path, "artifact": path,
                                   "why": "垫片读不到正文（权限/编码）"})
                continue
            target = parse_shim_target(text, shim_dir=d)
            if not target:
                unprovable.append({"label": "PATH 垫片 %s" % path, "artifact": path,
                                   "why": "垫片正文解析不出它执行的 .js/.cjs（形状不在判据词表内）"})
                continue
            # **BUG-438 跟随一跳**：垫片指向的可能是**启动器包装**（`.cjs`，如 BUG-437 的
            # `serve-launcher.cjs`），它自己不是生产物、必含不了业务符号 ⇒ 直接拿它评符号
            # 会恒报「缺符号」（假红）。这里把它**再解析一层**到它真正加载的 `cli.js`；
            # 解析不出就原样保留（不猜），但标 `wrapper=True` 让上层知道它不可当产物判。
            wrapper = target.lower().endswith((".cjs", ".mjs"))
            followed = None
            if wrapper:
                ttext = read_artifact(target)
                profiles = launcher_profiles(ttext) if ttext else []
                if profiles:
                    _prof, followed = choose_bundle(ROOT, profiles)
            if followed:
                faces.append({"kind": "path-shim", "label": "PATH 垫片 %s（经 %s 跳转）"
                              % (path, os.path.basename(target)),
                              "shim": path, "artifact": followed})
            else:
                faces.append({"kind": "path-shim", "label": "PATH 垫片 %s" % path,
                              "shim": path, "artifact": target, "wrapper": wrapper})
    return faces, unprovable


MIN_BUNDLE_BYTES = 100 * 1000


def _stat_bundle(path):
    """复刻 launcher 的 `statBundle`：存在 + 是文件 + ≥100KB ⇒ 返回 size，否则 None。

    **必须复刻而不是只看存在性**（BUG-438）：launcher 的 `chooseBundle` 会跳过
    「不存在 / 不是文件 / 小于 100KB」的候选再去试下一个 profile。
    判据若只按「文件在不在」挑，就会挑到 launcher **实际不会选**的那一个（判例-34 同族）。
    """
    try:
        if not os.path.isfile(path):
            return None
        size = os.path.getsize(path)
        return size if size >= MIN_BUNDLE_BYTES else None
    except OSError:
        return None


def choose_bundle(root, profiles):
    """复刻 launcher 的 `chooseBundle`：按 profiles 顺序取第一个 statBundle 通过的。

    返回 (profile, path)；全不通过 ⇒ (None, None)。
    """
    for profile in profiles:
        p = os.path.normpath(os.path.join(
            root, "_build", "js", profile, "build", "cmd", "cli", "cli.js"))
        if _stat_bundle(p):
            return profile, p
    return None, None


def launcher_profiles(text):
    """从 `serve-launcher.cjs` 正文反解它**候选 profile 的解析顺序**。

    真源是 launcher 自己：`CANDIDATES` 列出的 name 顺序 + `want = FIST_MBT_PROFILE || 'debug'`
    决定的实际尝试顺序。这里做**保守**解析：拿到 CANDIDATES 里的 name 列表，
    再按「`FIST_MBT_PROFILE` 默认值优先」把它排前面（默认取 `debug`）。
    解析不出任何 profile ⇒ 返回空（宁可不判，不猜）。
    """
    if not text:
        return []
    names = re.findall(
        r"""\{\s*name\s*:\s*['"]([A-Za-z0-9_-]+)['"]\s*,\s*file\s*:\s*path\.join\(""", text)
    if not names:
        return []
    # 默认 profile：`process.env.FIST_MBT_PROFILE || '<x>'`
    m = re.search(r"""FIST_MBT_PROFILE\s*\|\|\s*['"]([A-Za-z0-9_-]+)['"]""", text)
    want = m.group(1) if m else "debug"
    order = [want] + [n for n in names if n != want]
    return order


def launcher_faces(root):
    """PATH 实际入口 `serve-launcher.cjs` ⇒ 它**真会执行**的那一个产物面。

    找不到 launcher（未按 BUG-437 部署）⇒ 返回空（本面不出现，不影响其它面）。
    """
    candidates = [os.path.join(root, "serve-launcher.cjs")]
    local = os.environ.get("LOCALAPPDATA") or ""
    if local:
        candidates.append(os.path.join(local, "FIST-Mbt", "serve-launcher.cjs"))
    out, seen = [], set()
    for p in candidates:
        try:
            if not os.path.isfile(p):
                continue
        except OSError:
            continue
        key = os.path.normcase(os.path.normpath(p))
        if key in seen:
            continue
        seen.add(key)
        text = read_artifact(p)
        if text is None:
            continue
        profiles = launcher_profiles(text)
        if not profiles:
            continue
        profile, chosen = choose_bundle(root, profiles)
        if not chosen:
            continue
        out.append({"kind": "runtime-entry",
                    "label": "运行产物(%s，launcher 实际执行)" % profile,
                    "shim": p, "artifact": chosen})
    return out


def fixed_faces(root, env, extra=()):
    """固定候选面（存在与否交给 assess 判，不存在不算面）。"""
    out = []
    # **BUG-438**：PATH 入口真实产物排第一 —— 它才是「用户拿到什么」的那一格。
    out.extend(launcher_faces(root))
    js = deploy_js_path(env)
    if js:
        # **BUG-438**：旧「部署副本」降为 informational —— BUG-437 后 PATH 已不走它，
        # 它过期不说明用户拿到旧版。保留显示（人要看得到），但不计入 FAIL。
        out.append({"kind": "deploy-copy-legacy", "informational": True,
                    "label": "部署副本（旧位，BUG-437 后已非运行路径）", "artifact": js})
    out.append({"kind": "repo-dist", "label": "仓内快照",
                "artifact": os.path.join(root, "dist", "fist-mbt.js")})
    # **BUG-438**：`_release/` 是 `build_release.ps1` 生成的**发布包快照**（供 `install.ps1 -Source`），
    # 本就该停在发版那一刻 ⇒ 判它「必须新鲜」是把发布包当开发产物，降为 informational。
    out.append({"kind": "repo-release", "informational": True, "label": "release 产物（发布包快照）",
                "artifact": os.path.join(root, "_release", "js", "fist-mbt.js")})
    for p in extra or ():
        out.append({"kind": "extra", "label": "指定面", "artifact": p})
    return out


def collect_faces(root, env, extra=()):
    """全部候选面 → (存在的 faces, unprovable)。

    - 不存在的不算面（但**零面**会被判 2）；
    - **同一份产物只算一格**：POSIX 垫片与「部署副本」常常指同一个文件（本机实测就是这样），
      重复计数会把一条违规读成两条 ⇒ 按规范化路径合并、标签并起来（说清"谁在调它"）。
    """
    raw, unprovable = shim_faces(env)
    raw.extend(fixed_faces(root, env, extra))
    merged, order = {}, []
    for face in raw:
        path = face["artifact"]
        if not os.path.isfile(path):
            if face["kind"] in ("path-shim", "extra"):
                # 垫片在、它指的产物不在 ⇒ 这是"读不到"，不是"面不存在"：不许当新鲜放过。
                # `--artifact` 同理：显式点名的面缺席必须出声，否则一个打错的路径会静默变成空转。
                unprovable.append({"label": face["label"], "artifact": path,
                                   "why": "垫片指向的产物不存在" if face["kind"] == "path-shim"
                                          else "显式点名的产物不存在"})
            continue
        key = os.path.normcase(os.path.normpath(path))
        if key in merged:
            if face["label"] not in merged[key]["label"]:
                merged[key]["label"] = merged[key]["label"] + " ／ " + face["label"]
            continue
        merged[key] = dict(face)
        order.append(key)
    return [merged[k] for k in order], unprovable


# ---------------------------------------------------------------------------
# 源码基线
# ---------------------------------------------------------------------------
# 只算**进产物**的源码：`*_test.mbt` / `*_wbtest.mbt` 只在 `moon test` 下编译，改它们不需要重建部署产物
# —— 把它们算进基线，等于让"跑了几个测试"就把部署面判红（假红的经典来源，本仓判例-31 同族）。
BASELINE_SKIP_SUFFIXES = ("_test.mbt", "_wbtest.mbt")


def iter_baseline_files(root):
    """基线文件：`src/**` 与 `cmd/**` 的**产品** `.mbt`、全部 `moon.pkg`、根 `moon.mod`。"""
    for sub in BASELINE_DIRS:
        base = os.path.join(root, sub)
        if not os.path.isdir(base):
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = sorted(d for d in dirnames if d not in WALK_EXCLUDE)
            for fname in sorted(filenames):
                if fname.endswith(".mbt") and not fname.endswith(BASELINE_SKIP_SUFFIXES):
                    yield os.path.join(dirpath, fname)
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in WALK_EXCLUDE)
        for fname in sorted(filenames):
            if fname == "moon.pkg":
                yield os.path.join(dirpath, fname)
    mod = os.path.join(root, "moon.mod")
    if os.path.isfile(mod):
        yield mod


def source_baseline(root):
    """源码基线：`{"mtime", "path", "count"}`；一份都读不到 ⇒ None（判据无基線）。"""
    best, count = None, 0
    for path in iter_baseline_files(root):
        try:
            mt = os.path.getmtime(path)
        except OSError:
            continue
        count += 1
        if best is None or mt > best["mtime"]:
            best = {"mtime": mt, "path": path}
    if best is None:
        return None
    best["count"] = count
    return best


# ---------------------------------------------------------------------------
# 判面
# ---------------------------------------------------------------------------
def is_build_cache(path):
    norm = path.replace("\\", "/")
    return any(marker in norm for marker in BUILD_CACHE_MARKERS)


def fmt_dur(sec):
    if sec < 90:
        return "%.0f 秒" % sec
    if sec < 5400:
        return "%.0f 分钟" % (sec / 60.0)
    if sec < 172800:
        return "%.1f 小时" % (sec / 3600.0)
    return "%.1f 天" % (sec / 86400.0)


def fmt_ts(mtime):
    return time.strftime("%Y-%m-%d %H:%M", time.localtime(mtime))


def assess_face(face, baseline, symbols=KEY_SYMBOLS):
    """判一格面 → row（含 fails / warns / state）。不存在或读不到 ⇒ UNPROVABLE（不冒判）。

    **`informational=True`（BUG-438）**：该面**不以「必须新鲜」判定** ——
    它可能是发布包快照（`_release/`）或旧运行位（BUG-437 前的 `%LOCALAPPDATA%` 副本），
    过期是**正常状态**。这类面照常算 `lag` / `missing` 供人读，但结论一律进 `warns`，**不进 `fails`**
    ⇒ 不会把整体判红。**为什么必须区分**：一条永远红、且红的理由已失效的守卫，
    不只是「没有守卫」，是「让人去修错的东西」（判例-34）。
    """
    row = dict(face)
    informational = bool(face.get("informational"))
    row.update({"mtime": None, "lag": None, "missing": [], "hits": {},
                "fails": [], "warns": [], "state": "UNPROVABLE", "why": "",
                "informational": informational})
    path = face["artifact"]
    try:
        row["mtime"] = os.path.getmtime(path)
    except OSError as exc:
        row["why"] = "读不到 mtime（%r）" % (exc,)
        return row
    text = read_artifact(path)
    if text is None:
        row["why"] = "读不到产物正文（权限/编码）"
        return row
    row["hits"] = found_report(text, symbols)
    row["missing"] = missing_symbols(text, symbols)
    # **BUG-438 关键修正**：`runtime-entry` / `path-shim` 是**用户实际运行的那个文件**
    # （经 launcher 解析出来），即使它在 `_build/` 下也**不能按构建缓存降级为 WARN** ——
    # 它旧了用户就拿到旧版，这正是本判据存在的理由。
    # 实测反例（本单变异对照）：把 launcher 实际执行的 cli.js mtime 改到 2020 年，
    # 旧逻辑只出 `WARN … 构建缓存，按需重建` ⇒ **判据对「用户拿到旧版」沉默**。
    runtime = face.get("kind") in ("runtime-entry", "path-shim")
    cache = is_build_cache(path) and not runtime
    row["cache"] = cache
    # informational 面的结论一律落 warns；其它面按原两级严重度落 fails/warns。
    def _note(msg):
        if informational:
            row["warns"].append(msg + "（informational：过期属正常，不计 FAIL）")
        elif cache:
            row["warns"].append(msg + "（构建缓存，按需重建 ⇒ WARN）")
        else:
            row["fails"].append(msg)

    if baseline is not None:
        row["lag"] = baseline["mtime"] - row["mtime"]
        if row["lag"] > 0:
            _note("时间面落后 %s（源码最新改动 %s @ %s）" % (
                fmt_dur(row["lag"]), baseline["path"], fmt_ts(baseline["mtime"])))
    if row["missing"]:
        _note("内容面缺符号：%s（产物里连一次调用形都没有）"
              % " / ".join(row["missing"]))
    row["state"] = "FAIL" if row["fails"] else ("WARN" if row["warns"] else "FRESH")
    if informational and row["state"] == "WARN":
        row["state"] = "INFO"
    return row


def decide(rows, unprovable=()):
    """纯函数：面 → (rc, fails, warns, un;)。`4`（尺子坏）由上层在锚检查处提前返回。"""
    fails, warns = [], []
    for row in rows:
        fails.extend(row.get("fails") or [])
        warns.extend(row.get("warns") or [])
    un = list(unprovable) + [r for r in rows if r["state"] == "UNPROVABLE"]
    if fails:
        return 1, fails, warns, un
    if un or not rows:
        return 2, fails, warns, un
    return 0, fails, warns, un


# ---------------------------------------------------------------------------
# 入口面（selftest 也走这里 —— 判例-29：自检必须经过脚本自己这条实现路径）
# ---------------------------------------------------------------------------
def run(root, env=None, extra=(), symbols=KEY_SYMBOLS, sink=print):
    """判一个 root。返回 rc（0/1/2/4）。所有输出走 `sink`，selftest 收进列表断言。"""
    env = dict(os.environ) if env is None else dict(env)
    sink("[deployment-freshness] root=%s" % root)

    anchored = anchor_problems(root, symbols)
    if anchored:
        sink("RULER ANCHOR LOST：探针 %s 在今天的源码里找不到 `fn <name>(` 定义 ⇒ "
             "这条探针不再钉住现役代码（尺子坏了，不是产物旧）。"
             % " / ".join(anchored))
        sink("  修法：更新 scripts/_deployment_symbols.py 的 KEY_SYMBOLS（换一条仍在产的符号），"
             "不要靠删探针变绿。")
        return 4

    baseline = source_baseline(root)
    if baseline is None:
        sink("FATAL 源码基线读不到（src/cmd 下没有 .mbt，也没有 moon.pkg / moon.mod）"
             " ⇒ 判据无法自证，拒绝报绿")
        return 2
    sink("源码基线 max(mtime)=%s @ %s（%d 份：src/cmd 的 .mbt + moon.pkg + moon.mod）"
         % (fmt_ts(baseline["mtime"]), baseline["path"], baseline["count"]))

    faces, unprovable = collect_faces(root, env, extra)
    rows = [assess_face(face, baseline, symbols) for face in faces]

    for row in rows:
        hits = sum(1 for v in row["hits"].values() if v > 0)
        sink("  [%s] %s" % (row["state"], row["label"]))
        sink("      产物 : %s" % row["artifact"])
        if row["mtime"] is not None:
            sink("      mtime: %s%s" % (fmt_ts(row["mtime"]),
                                        "" if row["lag"] is None else
                                        "（lag=%+.1f 小时）" % (row["lag"] / 3600.0)))
        if row["hits"]:
            sink("      内容 : %d/%d 符号有调用形" % (hits, len(row["hits"])))
        for line in row["fails"]:
            sink("      FAIL %s" % line)
        for line in row["warns"]:
            sink("      WARN %s" % line)
        if row["state"] == "UNPROVABLE":
            sink("      无法自证 %s" % row["why"])
    for item in unprovable:
        sink("  [UNPROVABLE] %s :: %s" % (item["label"], item["why"]))

    rc, fails, warns, un = decide(rows, unprovable)
    if rc == 0:
        sink("PASS %d 面全部新鲜（内容面 %d 条探针 × 时间面）"
             % (len(rows), len(symbols)))
        return 0
    if rc == 1:
        sink("FAIL 检出 %d 条违规（%d 面 / %d 面另有 WARN）"
             % (len(fails), len(rows), len([r for r in rows if r["warns"]])))
        sink("  刷新：python scripts/refresh_dist.py（仓内快照）｜ 部署副本按安装流程重装；"
             "PATH 垫片指到 dev 构建时跑一次 moon build --target js cmd/cli")
        return 1
    sink("FATAL 判据无法自证：%d 处读不到（一个可判的产物面都没有 ⇒ 既不判红也不判绿）" % len(un))
    sink("  期望的面：PATH 上的 fist-mbt 垫片 / %s / dist/fist-mbt.js / _release/js/fist-mbt.js"
         % (deploy_js_path(env) or "FIST_DEPLOY_JS"))
    return 2


# ---------------------------------------------------------------------------
# 自检（含变异对照；夹具全是真文件，不 sleep、不靠时序）
# ---------------------------------------------------------------------------
def _write(path, text, mtime=None):
    parent = os.path.dirname(path)
    if parent and not os.path.isdir(parent):
        os.makedirs(parent)
    with io.open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    if mtime is not None:
        os.utime(path, (mtime, mtime))
    return path


FIX_SYM = KeySymbol("fixture_fresh_probe", "selftest（合成）",
                    "夹具专用探针：不依赖真仓符号，自检才确定")
FIX_SYMBOLS = (FIX_SYM,)
FIX_MANGLED = "function _M0FP411x14fixture__fresh__probe(t) {\n  return !0;\n}\n"
FIX_PLAIN = "function fixture_fresh_probe(t) {\n  return !0;\n}\n"
FIX_STALE = "function something_else(t) {\n  return !0;\n}\n"


def _fixture(tmp, name, src_mtime, art_mtime, art_text, src_text=None):
    """造一个最小仓：moon.mod + src/engine/x.mbt + dist/fist-mbt.js。返回 root。"""
    root = os.path.join(tmp, name)
    _write(os.path.join(root, "moon.mod"), 'name = "fixture/x"\nversion = "0.0.0"\n', src_mtime)
    _write(os.path.join(root, "src", "engine", "x.mbt"),
           src_text if src_text is not None else
           "pub fn fixture_fresh_probe(t : Int) -> Bool {\n  true\n}\n", src_mtime)
    if art_text is not None:
        _write(os.path.join(root, "dist", "fist-mbt.js"), art_text, art_mtime)
    return root


def selftest():
    cells = []

    def cell(name, got, want):
        cells.append((name, got == want, "got=%r want=%r" % (got, want)))

    def truth(name, cond, detail=""):
        cells.append((name, bool(cond), detail or "cond=False"))

    # ---- P 族：垫片反解（纯函数）----
    cell("P1-cmd-quoted", parse_shim_target(
        '@echo off\r\nREM shim\r\nnode "C:/shims/fist-mbt.js" %*\r\n'), "C:/shims/fist-mbt.js")
    cell("P2-sh-quoted", parse_shim_target(
        '#!/bin/sh\nexec node "D:\\opt\\fist\\fist-mbt.js" "$@"\n'), "D:\\opt\\fist\\fist-mbt.js")
    cell("P3-dp0-relative", parse_shim_target(
        'node "%~dp0..\\lib\\fist-mbt.js" %*', shim_dir="X:/shims"),
        os.path.normpath(os.path.join("X:/shims", "..", "lib", "fist-mbt.js")))
    cell("P4-flag-then-path", parse_shim_target(
        'node --no-warnings "C:/a/b.js" %*'), "C:/a/b.js")
    cell("P5-no-node", parse_shim_target("@echo off\necho fist-mbt\n"), None)
    cell("P6-first-of-two", parse_shim_target(
        'node "C:/a/first.js" "C:/a/second.js"'), "C:/a/first.js")

    # ---- R 族（BUG-438）：PATH 实际入口 launcher 的解析与跟随 ----
    # 判例-34：判据必须检查「用户实际运行的那个文件」，不是随便一个同名副本。
    # 这三格钉住三点：.cjs 能解析（旧词表只认 .js ⇒ 两条垫片恒 UNPROVABLE）、
    # %VAR% 节点名能解析（.cmd 垫片用 set "FIST_NODE=..."）、%LOCALAPPDATA% 能展开。
    cell("R1-launcher-cjs-literal", parse_shim_target(
        'node "C:/shims/serve-launcher.cjs" %*'), "C:/shims/serve-launcher.cjs")
    cell("R2-cmd-var-program", parse_shim_target(
        'set "FIST_NODE=%ProgramFiles%\\nodejs\\node.exe"\r\n'
        '"%FIST_NODE%" "C:/shims/serve-launcher.cjs" %*\r\n'), "C:/shims/serve-launcher.cjs")
    cell("R3-env-placeholder-expanded", parse_shim_target(
        '"%FIST_NODE%" "%LOCALAPPDATA%\\FIST-Mbt\\serve-launcher.cjs" %*',
        shim_dir="X:/shims"),
        os.path.normpath(os.path.expandvars("%LOCALAPPDATA%\\FIST-Mbt\\serve-launcher.cjs")))
    # R4：launcher 正文的 profile 解析顺序（FIST_MBT_PROFILE 默认 debug 优先）
    cell("R4-launcher-profile-order", launcher_profiles(
        "const REPO = process.env.FIST_MBT_REPO || 'E:\\\\repo';\n"
        "const want = (process.env.FIST_MBT_PROFILE || 'debug').toLowerCase();\n"
        "const CANDIDATES = [\n"
        "  { name: 'debug', file: path.join(REPO, '_build', 'js', 'debug', 'build', 'cmd', 'cli', 'cli.js') },\n"
        "  { name: 'release', file: path.join(REPO, '_build', 'js', 'release', 'build', 'cmd', 'cli', 'cli.js') },\n"
        "];\n"), ["debug", "release"])
    # R5（变异对照，informational 面）：把 _release 当 informational ⇒ 它落后只进 warns、
    # 绝不进 fails（否则「发布包快照该停在发版那一刻」这条语义就又退回到假红）。
    # 判例-29：本格直接走 assess_face 这条实现路径，不另写一份判断。
    _rel = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "..", "_release", "js", "fist-mbt.js")
    _info = assess_face({"kind": "repo-release", "informational": True, "label": "L",
                         "artifact": _rel}, {"mtime": time.time() + 1e6, "path": "src/x.mbt"})
    cell("R5-informational-never-fails",
         (len(_info.get("fails") or []) == 0, len(_info.get("warns") or []) > 0), (True, True))
    # R6（正向对照）：同一落后量，非 informational 面必须进 fails。
    _hard = assess_face({"kind": "extra", "label": "H", "artifact": _rel},
                        {"mtime": time.time() + 1e6, "path": "src/x.mbt"})
    cell("R6-non-informational-does-fail", len(_hard.get("fails") or []) > 0, True)

    # ---- S 族：源码基线（真文件系统）----
    tmp = tempfile.mkdtemp(prefix="deploy-fresh-self-")
    try:
        s1 = _fixture(tmp, "s1", 1000, None, None)
        _write(os.path.join(s1, "src", "b.mbt"), "pub fn b() -> Unit {}\n", 3000)
        base = source_baseline(s1)
        cell("S1-max-mtime", (base or {}).get("mtime"), 3000)
        truth("S1-names-newest", (base or {}).get("path", "").replace("\\", "/").endswith("src/b.mbt"),
              "path=%r" % ((base or {}).get("path"),))

        s2 = _fixture(tmp, "s2", 1000, None, None)
        _write(os.path.join(s2, "src", "moon.pkg"), "// pkg\n", 5000)
        base2 = source_baseline(s2)
        cell("S2-moonpkg-counts", (base2 or {}).get("mtime"), 5000)

        s3 = os.path.join(tmp, "s3")
        _write(os.path.join(s3, "dist", "fist-mbt.js"), FIX_PLAIN, 9000)
        cell("S3-empty-baseline", source_baseline(s3), None)

        s4 = _fixture(tmp, "s4", 1000, None, None)
        _write(os.path.join(s4, "_build", "js", "gen.mbt"), "pub fn gen() -> Unit {}\n", 9000)
        cell("S4-build-cache-excluded", (source_baseline(s4) or {}).get("mtime"), 1000)

        s5 = _fixture(tmp, "s5", 1000, None, None)
        _write(os.path.join(s5, "src", "engine", "x_wbtest.mbt"),
               "test \"t\" {\n  assert_true(true)\n}\n", 9000)
        cell("S5-test-files-excluded", (source_baseline(s5) or {}).get("mtime"), 1000)

        # ---- F 族：端到端真夹具（含变异对照；全部走 run()）----
        env0 = {"PATH": "", "LOCALAPPDATA": ""}

        f1 = _fixture(tmp, "f1", 3000, 1000, FIX_STALE)
        lines1 = []
        cell("F1-stale-is-1", run(f1, env0, (), FIX_SYMBOLS, lines1.append), 1)
        blob1 = "\n".join(lines1)
        truth("F1-names-artifact", "dist" in blob1 and "fist-mbt.js" in blob1, blob1[-400:])
        truth("F1-names-content-gap", "内容面缺符号" in blob1 and FIX_SYM.name in blob1, blob1[-400:])

        f2 = _fixture(tmp, "f2", 1000, 3000, FIX_MANGLED)
        cell("F2-fresh-mangled-is-0", run(f2, env0, (), FIX_SYMBOLS, lambda _l: None), 0)

        # 变异对照②：同一夹具把产物换回「无该符号」⇒ 必须红（改的是产物代码，不是注释）
        f2b = _fixture(tmp, "f2b", 1000, 3000, FIX_STALE)
        cell("F2b-fresh-mtime-stale-code-is-1",
             run(f2b, env0, (), FIX_SYMBOLS, lambda _l: None), 1)

        f3 = _fixture(tmp, "f3", 1000, 3000, FIX_STALE)
        lines3 = []
        cell("F3-content-only-is-1", run(f3, env0, (), FIX_SYMBOLS, lines3.append), 1)
        truth("F3-no-mtime-claim", "内容面缺符号" in "\n".join(lines3)
              and "时间面落后" not in "\n".join(lines3), "\n".join(lines3)[-400:])

        f4 = _fixture(tmp, "f4", 3000, 1000, FIX_MANGLED)
        lines4 = []
        cell("F4-mtime-only-is-1", run(f4, env0, (), FIX_SYMBOLS, lines4.append), 1)
        truth("F4-content-clean", "内容面缺符号" not in "\n".join(lines4)
              and "时间面落后" in "\n".join(lines4), "\n".join(lines4)[-400:])

        f5 = _fixture(tmp, "f5", 1000, None, None)
        cell("F5-no-face-is-2", run(f5, env0, (), FIX_SYMBOLS, lambda _l: None), 2)

        # 显式 --artifact 打错路径 ⇒ 不许静默空转（F10）
        lines10 = []
        cell("F10-bad-artifact-is-2",
             run(f5, env0, (os.path.join(tmp, "no-such-artifact.js"),), FIX_SYMBOLS, lines10.append), 2)
        truth("F10-names-missing-artifact", "不存在" in "\n".join(lines10), "\n".join(lines10)[-400:])

        f6 = _fixture(tmp, "f6", 1000, 3000, FIX_MANGLED)
        shims = os.path.join(f6, "shims")
        _write(os.path.join(shims, "fist-mbt.cmd"), "@echo off\necho no-node-here\n", 3000)
        lines6 = []
        cell("F6-unparsable-shim-is-2",
             run(f6, {"PATH": shims, "LOCALAPPDATA": ""}, (), FIX_SYMBOLS, lines6.append), 2)
        truth("F6-says-unprovable", "解析不出" in "\n".join(lines6), "\n".join(lines6)[-400:])

        f7 = _fixture(tmp, "f7", 1000, 3000, FIX_MANGLED,
                      src_text="pub fn some_other_fn() -> Unit {}\n")
        cell("F7-anchor-lost-is-4", run(f7, env0, (), FIX_SYMBOLS, lambda _l: None), 4)

        # 构建缓存的时间面落后 ⇒ WARN 不驱动 rc（F8）
        f8 = _fixture(tmp, "f8", 3000, None, None)
        cache_js = _write(os.path.join(f8, "_build", "js", "cli.js"), FIX_MANGLED, 1000)
        lines8 = []
        cell("F8-cache-lag-is-warn-not-fail",
             run(f8, env0, (cache_js,), FIX_SYMBOLS, lines8.append), 0)
        truth("F8-warn-named", "WARN" in "\n".join(lines8), "\n".join(lines8)[-400:])

        # 同一份产物被两个面指到（POSIX 垫片 + 部署副本）⇒ 只算一格（本机实测就是这个形状）
        f9 = _fixture(tmp, "f9", 1000, 3000, FIX_MANGLED)
        shims9 = os.path.join(f9, "shims")
        _write(os.path.join(shims9, "fist-mbt"),
               '#!/bin/sh\nexec node "%s" "$@"\n'
               % os.path.join(f9, "dist", "fist-mbt.js").replace("\\", "/"), 3000)
        lines9 = []
        run(f9, {"PATH": shims9, "LOCALAPPDATA": ""}, (), FIX_SYMBOLS, lines9.append)
        cell("F9-same-artifact-one-row",
             len([ln for ln in lines9 if ln.startswith("  [")]), 1)

        # ---- D 族：面 → 裁决（纯函数）----
        def _row(state, fails=(), warns=(), label="X", artifact="X/y.js"):
            return {"label": label, "artifact": artifact, "state": state,
                    "fails": list(fails), "warns": list(warns),
                    "missing": [], "hits": {}, "mtime": 1.0, "lag": 0.0, "why": ""}

        cell("D1-content-fail-is-1",
             decide([_row("FAIL", fails=["内容面缺符号：x"])])[0], 1)
        cell("D2-mtime-fail-is-1",
             decide([_row("FAIL", fails=["时间面落后 1 小时"])])[0], 1)
        cell("D3-warn-only-is-0",
             decide([_row("WARN", warns=["构建缓存滞后"])])[0], 0)
        cell("D4-all-fresh-is-0", decide([_row("FRESH"), _row("FRESH")])[0], 0)
        cell("D5-no-face-is-2", decide([])[0], 2)
        cell("D6-unprovable-refuses-green",
             decide([_row("FRESH")], [{"label": "P", "artifact": "P", "why": "读不到"}])[0], 2)

        # ---- A 族：符号探针本体（含判例-30 的注释/字面量对照）----
        truth("A1-raw-call-hits", count_calls("x fixture_fresh_probe(t) y", FIX_SYM.name) == 1)
        truth("A2-mangled-call-hits",
              count_calls("function _M0X14fixture__fresh__probe(t) {", FIX_SYM.name) == 1,
              "MoonBit 把 `_` 写成 `__`；裸 substring 在这里会假红")
        truth("A3-string-literal-not-counted",
              count_calls('{"name":"fixture_fresh_probe","ok":1}', FIX_SYM.name) == 0,
              "后跟 `,` 不是 `(` ⇒ 不算代码")
        a4 = os.path.join(tmp, "a4")
        _write(os.path.join(a4, "src", "note.mbt"),
               "// fixture_fresh_probe( 只是注释里提了一句\n/// pub fn fixture_fresh_probe(x) -> Unit {}\n")
        truth("A4-comment-is-not-definition",
              "fixture_fresh_probe" not in source_definitions(a4, ["fixture_fresh_probe"]),
              "判例-30：注释里出现名字不算定义")
        a5 = os.path.join(tmp, "a5")
        _write(os.path.join(a5, "src", "real.mbt"),
               "pub fn fixture_fresh_probe(x : Int) -> Bool {\n  true\n}\n")
        truth("A5-real-definition-anchors",
              "fixture_fresh_probe" in source_definitions(a5, ["fixture_fresh_probe"]))
        truth("A6-table-hygiene",
              len(KEY_SYMBOLS) >= 1
              and len(set(s.name for s in KEY_SYMBOLS)) == len(KEY_SYMBOLS)
              and all(s.name and s.origin and s.why for s in KEY_SYMBOLS),
              "KEY_SYMBOLS 每条都要有 name/origin/why 且名字不重复")
    finally:
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)

    bad = [(n, d) for n, ok, d in cells if not ok]
    fams = {}
    for name, _ok, _d in cells:
        head = re.match(r"[A-Za-z]+", name)
        key = head.group(0) if head else name
        fams[key] = fams.get(key, 0) + 1
    inventory = " / ".join("%s×%d" % (k, v) if v > 1 else k
                           for k, v in sorted(fams.items()))
    if bad:
        print("SELFTEST FAIL：%d/%d 格红" % (len(bad), len(cells)))
        for name, detail in bad:
            print("  - %s：%s" % (name, detail))
        return 1
    print("SELFTEST OK：%d 格" % len(cells))
    print("清单从已执行格子反解：%d 格（%s）" % (len(cells), inventory))
    return 0


# ---------------------------------------------------------------------------
# main（`return 4` 必须落在 except 里 —— check_selftest_call_face 的 J1）
# ---------------------------------------------------------------------------
def main(argv=None):
    parser = argparse.ArgumentParser(add_help=True, description="部署产物新鲜度判据（BUG-428）")
    parser.add_argument("--selftest", action="store_true", help="先证明这把尺会红（含变异对照）")
    parser.add_argument("--symbols", action="store_true", help="打印探针表与它的维护面")
    parser.add_argument("--root", default=ROOT, help="判哪个仓（默认本仓根）")
    parser.add_argument("--artifact", action="append", default=[], metavar="PATH",
                        help="追加一个产物面（可重复）")
    args = parser.parse_args(list(sys.argv[1:] if argv is None else argv))
    if args.selftest:
        return selftest()
    if args.symbols:
        print(describe_symbols())
        return 0
    try:
        return run(args.root, os.environ, args.artifact)
    except Exception as exc:  # noqa: BLE001 — 尺子自己坏了：真给 4，绝不冒用 1（判据红）
        sys.stderr.write("RULER BROKEN：未捕获异常 %r\n" % (exc,))
        return 4


if __name__ == "__main__":
    sys.exit(main())
