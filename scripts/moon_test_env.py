#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/moon_test_env.py — 让 `moon test` 在本机真的能跑（BUG-380 根因修复的常驻入口）。

## 根因（2026-10-22 实测，R54）
`moon test --target js` 会把测试选择面作为**一整段 JSON 参数**交给测试产物：
```
node --enable-source-maps _build/js/debug/test/src/engine/engine.blackbox_test.js '{"package":…,"file_and_index":[…]}}'
```
本机 PATH 上 `node` 解析到 DSH 桌面端的 **`node.cmd` shim**（`%APPDATA%\\dsh-desktop\\harness\\.desktop-bin\\node.cmd`），
参数经 `cmd.exe` 转发时**引号被吞**，于是测试产物收到残缺 JSON：

    failed to parse args:  Unterminated string in JSON at position 175 (line 1 column 176)
    Error: failed to run test for target Js

**同一 payload 对照实验（决定性）**：
| 调用方式 | 结果 |
|---|---|
| `.desktop-bin\\node.cmd` + 同一 payload | **rc=1** `failed to parse args: Expected property name or '}' in JSON at position 1` |
| `C:\\Program Files\\nodejs\\node.exe` + 同一 payload | **rc=0**，正常打出 `----- BEGIN MOON TEST RESULT -----` |

⇒ 坏的不是 moon、不是本仓、更不是测试代码，而是**经由 `.cmd` 垫片转发时丢失的 JSON 引号**。
把该垫片目录从 PATH 移除后：`moon test --target js` = **1415/1415 passed, rc=0（15s）**。

## 第二道坑（R124）：清干净 PATH 仍可能在编译面炸
`node` 修好之后，`moon test` 的**编译面**还有一颗雷：moon 0.1.20261016 在 Windows 上把
`-o` / `-all-pkgs` 等输出路径写成 `\\?\\F:\\…` 长路径前缀，moonc 打开时直接
`Sys_error("\\\\?: Invalid argument")`（与本仓代码无关，最小工程同样复现；同族见 BUG-388 的
`moon fmt --check` 面）。本机既有绕法是 `MOONC_OVERRIDE` 指向一个**剥离 `\\?\\` 前缀再转发**的 shim。
本脚本在 Windows 上自动发现 `~/.moon-shim/shim.exe`（显式 `MOONC_OVERRIDE` 优先），找不到就照跑，
但一旦输出里出现 ICE 会**点名成因**并给 rc=2——不把它洗成测试红、也不假装绿。

## 这个脚本做什么
1. 递归剔除 PATH 里"含有 `node.cmd` 垫片"的目录（判据是**目录内容**，不是写死路径）；
2. 校验 `node` 现在解析到**真实 `.exe`**（不是 `.cmd`/`.bat`）；解析不到就 rc=2（拒绝出数）；
3. 用清理后的 PATH（+ 可用的 moonc override）跑 `moon test`，把参数原样透传；
4. 按本仓契约出 rc：**0=全绿 / 1=有红 / 2=判据无法自证**，
   并核对汇总行 `Total tests: N, passed: N, failed: 0`（BUG-142：`moon test` 自身退出码不可靠，
   崩了也可能回 0 ⇒ 判绿必须看汇总行，不能只看 rc）；
5. **R126**：静态核对服务端 spawn 原语（`src/server/run_check_js.mbt`）是否也在 spawn 前
   注入同一份 shim 环境——MCP 的 `run_check` 由 server 直连执行，server 被宿主拉起时
   本脚本的 Python 入口不在链路上。

用法：
  python scripts/moon_test_env.py                 # 全仓
  python scripts/moon_test_env.py src/engine      # 只跑某包（参数原样透传给 moon test）
  python scripts/moon_test_env.py moon test --target js   # 容错：完整命令写进来了也行
  python scripts/moon_test_env.py --selftest      # 离线验垫片识别/清理 + 服务端 spawn 面
  python scripts/moon_test_env.py --dry-run       # 只打印将要执行的环境与命令
  python scripts/moon_test_env.py --raw-log <path>   # 把 moon 原始 stdout 完整落盘（BUG-394 修法 A）

## BUG-394 修法 A：英文汇总行原样透传
标准输出的末行是 moon 原始英文汇总行 `Total tests: N, passed: N, failed: F`（判据认的形状，
check_badge / check_test_sync 直接消费它）；中文 `汇总：` 行保留给人类。可选 `--raw-log <path>`
把 moon 原始 stdout 完整落盘到调用方指定路径（判据/审计的原始证据面）。
"""
import os
import re
import shutil
import subprocess
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SHIM_NAMES = ("node.cmd", "node.bat")

# BUG-394：判据认的英文汇总行形状（check_badge / check_test_sync 共用）。
# 修法 A：本脚本把 moon 原始输出里的这条英文行**原样透传**到自己的标准输出，
# 使标准入口的输出能直接被两把尺消费（此前只自印中文 `汇总：` 形状，判据无法自证）。
RX_SUMMARY = re.compile(r"Total tests:\s*(\d+),\s*passed:\s*(\d+),\s*failed:\s*(\d+)")


def split_path(path):
    return [p for p in path.split(os.pathsep) if p.strip()]


def is_shim_dir(d):
    """目录里只要放着 node.cmd / node.bat 垫片，就算垫片目录（按内容判定，不写死路径）。"""
    try:
        return any(os.path.isfile(os.path.join(d, n)) for n in SHIM_NAMES)
    except OSError:
        return False


def clean_path(path):
    """返回 (新 PATH, 被剔除的目录列表, 保留列表)。纯函数，便于自检。"""
    kept, dropped = [], []
    for d in split_path(path):
        if is_shim_dir(d):
            dropped.append(d)
        else:
            kept.append(d)
    return os.pathsep.join(kept), dropped, kept


def resolve_node(clean):
    """在清理后的 PATH 里找 node，返回 (路径, 是否真实 exe, 说明)。"""
    exts = os.environ.get("PATHEXT", ".COM;.EXE;.BAT;.CMD").split(";")
    for d in split_path(clean):
        for ext in [""] + [e.lower() for e in exts] + [e.upper() for e in exts]:
            cand = os.path.join(d, "node" + ext)
            if os.path.isfile(cand):
                real = cand.lower().endswith(".exe")
                return cand, real, ("真实 node.exe" if real else "仍是垫片/脚本（不可用）")
    which = shutil.which("node", path=clean)
    if which:
        return which, which.lower().endswith(".exe"), "shutil.which 命中"
    return "", False, "清理后的 PATH 里找不到 node"


DEFAULT_MOONC_SHIM = os.path.join(os.path.expanduser("~"), ".moon-shim", "shim.exe")
# BUG-416：本常量是「脚本自身所在仓库」的根，**与 cwd 无关**——这正是它作为缺省值的原因
# （本入口被 AGENTS 定为常驻入口，习惯上从仓库任意位置调用，缺省必须落到本仓，而不是调用者站的地方）。
# 但「与 cwd 无关」同时意味着：**在副本 / `git archive` 导出树里跑本脚本，缺省仍会去测本仓**，
# 隔离"从未生效"。要测别的树请显式传 `--root <path>`（见 parse_root / main）。
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SERVER_SPAWN_REL = os.path.join("src", "server", "run_check_js.mbt")


def resolve_root(explicit, default=ROOT):
    """把 `--root` 的入参解析成**实际生效的根**（纯函数，BUG-416）。

    缺省（`explicit` 为 None / 空串）⇒ 原样返回 `default`（= 脚本目录）——**零回归**：
    不传 `--root` 时本函数不改变任何行为。
    显式传入 ⇒ 返回其绝对规范路径；目录不存在时返回 None，由调用方 rc=2 拒载
    （宁可拒绝出数，也不静默回落到脚本目录——那正是 BUG-416 的病灶）。
    """
    if explicit is None or explicit == "":
        return default
    if not os.path.isdir(explicit):
        return None
    return os.path.abspath(explicit)


def parse_root(argv):
    """从 argv 摘出 `--root <path>`（BUG-416）。

    支持 `--root X` 与 `--root=X` 两种写法，与 `parse_raw_log` 同族形态。
    返回 (路径或 None, 剩余 argv)；参数缺失/为空 ⇒ SystemExit 点名，绝不静默吞掉。
    """
    out, path = [], None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--root":
            if i + 1 >= len(argv) or not argv[i + 1].strip():
                raise SystemExit("--root 需要一个非空路径参数")
            path = argv[i + 1].strip()
            i += 2
            continue
        if a.startswith("--root="):
            path = a.split("=", 1)[1].strip()
            if not path:
                raise SystemExit("--root 需要一个非空路径参数")
            i += 1
            continue
        out.append(a)
        i += 1
    return path, out


def pick_moonc_override(env_value, shim_path, shim_exists, is_windows):
    """挑 moonc 覆盖：显式 env 优先；Windows 上发现本机 shim 就用；否则不设（非 Windows 无此 ICE）。"""
    if env_value:
        return env_value, "env"
    if is_windows and shim_exists:
        return shim_path, "discovered"
    return "", "none"


def server_spawn_env_violations(text):
    """服务端 spawn 原语是否在 spawn 前把 moonc shim 环境交给子进程（R126，纯函数）。

    `run_check` 由 server 的 js `spawn` 原语执行；server 被宿主直连 `node cli.js serve`
    拉起时不经过任何 Python 入口，本文件的发现规则必须在原语层再落一次。空文本 =
    判据面缺失，必须点名，绝不把「没读到」当「合规」。
    """
    if not text or not text.strip():
        return ["读不到 src/server/run_check_js.mbt"]
    out = []
    if "moon-shim" not in text or "shim.exe" not in text:
        out.append("未发现 ~/.moon-shim/shim.exe 自动发现")
    if "win32" not in text:
        out.append("未发现 win32 平台门")
    if "!env.MOONC_OVERRIDE" not in text:
        out.append("未发现显式 MOONC_OVERRIDE 优先")
    spawn_lines = [ln for ln in text.splitlines() if re.search(r"spawn\(\s*cmd\s*,\s*args", ln)]
    if not spawn_lines:
        out.append("未找到 spawn(cmd, args, …) 调用点")
    elif not any(re.search(r"\benv\b", ln) for ln in spawn_lines):
        out.append("spawn 选项未带 env（注入的环境不会交给子进程）")
    return out


def read_server_spawn_text(root=ROOT):
    try:
        with open(os.path.join(root, SERVER_SPAWN_REL), encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def parse_raw_log(argv):
    """从 argv 摘出 `--raw-log <path>`（BUG-394 修法 A 的可选参数）。

    返回 (路径或 None, 剩余 argv)。幂等：没有该参数就原样返回 argv，不改变其它参数。
    参数缺失/为空 ⇒ 失败可读（BUG-369），直接 SystemExit 点名，绝不静默吞掉调用方写错的地方。
    """
    if "--raw-log" not in argv:
        return None, argv
    i = argv.index("--raw-log")
    if i + 1 >= len(argv) or not argv[i + 1]:
        raise SystemExit("FATAL: --raw-log 需要一个非空路径参数（用法：--raw-log <path>）")
    return argv[i + 1], [a for j, a in enumerate(argv) if j not in (i, i + 1)]


def english_summary_line(text):
    """从 moon 原始输出里**原样**摘出第一条英文汇总行（判据认的形状，逐字节透传）。

    没有就返回 None（判据会走 rc=2，不冒用 0/1 两档）。纯函数，便于自检。
    """
    if not text:
        return None
    for line in text.splitlines():
        if RX_SUMMARY.search(line):
            return line
    return None


def write_raw_log(path, moon_stdout):
    """把 moon 原始 stdout 完整落盘（BUG-394 修法 A）。失败只点名不改判据（--raw-log 是便利面）。"""
    try:
        with open(path, "w", encoding="utf-8", errors="replace") as f:
            f.write(moon_stdout or "")
    except OSError as e:
        print("  判据警告：--raw-log 落盘失败（%s）：%s —— 原始 stdout 未落盘，不影响判据" % (path, e))


def strip_redundant_moon_prefix(args):
    """容错：调用方若把完整命令 `moon test --target js …` 也传了进来（BUG-394 自证用），
    去掉重复前缀，避免把字面 `moon` 当成包路径喂给 moon test。幂等：不匹配就原样返回。"""
    rest = args
    if rest[:2] == ["moon", "test"]:
        rest = rest[2:]
        if rest[:2] == ["--target", "js"]:
            rest = rest[2:]
    return rest


def _raises_system_exit(fn):
    """自检辅助：调用 fn 是否以 SystemExit 收场（失败可读面：参数写错必须点名，不许静默）。"""
    try:
        fn()
    except SystemExit:
        return True
    return False


def selftest():
    cells = []

    def cell(name, got, want):
        cells.append((name, got == want, "got=%r want=%r" % (got, want)))

    # 用真实临时目录造"垫片目录"与"干净目录"
    import tempfile
    base = tempfile.mkdtemp(prefix="mtea-")
    try:
        shim = os.path.join(base, "bin-shim")
        clean_dir = os.path.join(base, "bin-clean")
        os.makedirs(shim)
        os.makedirs(clean_dir)
        open(os.path.join(shim, "node.cmd"), "w").close()
        open(os.path.join(clean_dir, "node.exe"), "w").close()
        cell("is-shim-dir", is_shim_dir(shim), True)
        cell("is-clean-dir", is_shim_dir(clean_dir), False)
        fake_path = os.pathsep.join([shim, clean_dir, "/does/not/exist"])
        newp, dropped, kept = clean_path(fake_path)
        cell("drops-shim", dropped, [shim])
        cell("keeps-clean", clean_dir in kept, True)
        cell("new-path-lacks-shim", shim not in split_path(newp), True)
        node, real, _why = resolve_node(newp)
        cell("resolves-clean-node", node, os.path.join(clean_dir, "node.exe"))
        cell("marks-real-exe", real, True)
        # 只给垫片目录 ⇒ 必须解析失败（判据自证：不许把垫片当可用 node）
        node2, real2, _ = resolve_node(shim)
        cell("shim-only-not-real", real2, False)
    finally:
        shutil.rmtree(base, ignore_errors=True)

    # moonc 覆盖选择：显式 env 优先 / Windows 自动发现 / 缺失与非 Windows 不设
    fake_shim = os.path.join(base, "shim.exe")
    cell("override-env-wins", pick_moonc_override(r"C:/x/shim.exe", fake_shim, True, True), (r"C:/x/shim.exe", "env"))
    cell("override-discovers-windows", pick_moonc_override("", fake_shim, True, True), (fake_shim, "discovered"))
    cell("override-skipped-when-missing", pick_moonc_override("", fake_shim, False, True), ("", "none"))
    cell("override-skipped-non-windows", pick_moonc_override("", fake_shim, True, False), ("", "none"))

    # R126：服务端 spawn 原语面——正/反四支 + 空面自拒 + 真现状面必须绿
    server_clean = (
        "const env = { ...process.env }\n"
        "if (!env.MOONC_OVERRIDE && process.platform === 'win32') {\n"
        "  const shim = join(homedir(), '.moon-shim', 'shim.exe')\n"
        "  if (existsSync(shim)) env.MOONC_OVERRIDE = shim\n"
        "}\n"
        "child = spawn(cmd, args, { cwd: workdir || '.', stdio: ['ignore', 'pipe', 'pipe'], env })\n"
    )
    cell("server-spawn-clean", server_spawn_env_violations(server_clean), [])
    cell("server-spawn-env-dropped",
         any("env" in v for v in server_spawn_env_violations(server_clean.replace(", env }", " }"))), True)
    cell("server-spawn-shim-dropped",
         any("moon-shim" in v for v in server_spawn_env_violations(server_clean.replace(".moon-shim", ".x"))), True)
    cell("server-spawn-platform-gate-dropped",
         any("win32" in v for v in server_spawn_env_violations(server_clean.replace("'win32'", "'linux'"))), True)
    cell("server-spawn-face-missing", server_spawn_env_violations(""), ["读不到 src/server/run_check_js.mbt"])
    cell("server-spawn-live", server_spawn_env_violations(read_server_spawn_text()), [])

    # BUG-394 修法 A：--raw-log 解析 / 英文汇总行原样透传 / 冗余命令前缀容错
    cell("raw-log-no-arg", parse_raw_log(["a", "b"]), (None, ["a", "b"]))
    cell("raw-log-extract", parse_raw_log(["a", "--raw-log", "/tmp/x", "b"]), ("/tmp/x", ["a", "b"]))
    cell("raw-log-empty-arg-errors",
         _raises_system_exit(lambda: parse_raw_log(["a", "--raw-log"])), True)
    cell("english-summary-found",
         english_summary_line("hello\nTotal tests: 5, passed: 5, failed: 0\nworld"),
         "Total tests: 5, passed: 5, failed: 0")
    cell("english-summary-absent", english_summary_line("no summary here"), None)
    cell("english-summary-empty", english_summary_line(""), None)
    cell("strip-prefix-full", strip_redundant_moon_prefix(["moon", "test", "--target", "js", "src/x"]), ["src/x"])
    cell("strip-prefix-idempotent", strip_redundant_moon_prefix(["src/x"]), ["src/x"])
    cell("strip-prefix-moon-test-only", strip_redundant_moon_prefix(["moon", "test"]), [])

    # BUG-416：--root 解析 + 生效根 + **变异对照**（判例-29/30）
    #
    # 缺陷原形：ROOT 恒为脚本目录、忽略 cwd ⇒ 在副本 / `git archive` 导出树里跑本入口，
    # 会**静默测主树**，隔离从未生效。修法：`--root` 显式指定，缺省仍为脚本目录（零回归），
    # 且 `subprocess.run(..., cwd=root)` 让 `--root` **真正生效**（只打印不切 cwd = 没修）。
    tmp_root = tempfile.mkdtemp(prefix="mte-root-")
    other_root = tempfile.mkdtemp(prefix="mte-root2-")
    try:
        # ① 缺省 ⇒ 原样返回 default（零回归锚：不传 --root 时行为一个字不变）
        cell("root-default-is-script-dir", resolve_root(None), ROOT)
        cell("root-empty-string-is-default", resolve_root(""), ROOT)

        # ② 显式 ⇒ 返回该目录的绝对路径（**这是 --root 的核心语义**）
        cell("root-explicit-switches", resolve_root(tmp_root), os.path.abspath(tmp_root))

        # ③ 两个明显不同的树必须解析成不同根（防「传了但被忽略」）
        cell("root-distinct-trees-differ",
             resolve_root(tmp_root) != resolve_root(other_root), True)

        # ④ 不存在的目录 ⇒ None（调用方 rc=2 拒载；**不静默回落到脚本目录**，那正是本病灶）
        missing = os.path.join(tmp_root, "definitely-not-here")
        cell("root-missing-is-none", resolve_root(missing), None)

        # ⑤ parse_root：两种写法都要认
        cell("parse-root-space-form", parse_root(["--root", tmp_root, "src/x"]),
             (tmp_root, ["src/x"]))
        cell("parse-root-equals-form", parse_root(["--root=" + tmp_root, "src/x"]),
             (tmp_root, ["src/x"]))
        cell("parse-root-absent", parse_root(["src/x"]), (None, ["src/x"]))
        cell("parse-root-empty-arg-errors",
             _raises_system_exit(lambda: parse_root(["--root"])), True)

        # ⑥ **变异对照格（判例-29）**：把 `--root` 接线拆掉（call face 退化成恒用 ROOT），
        #    本格必须红。做法：直接调用 main 的装配路径不可行（会真跑 moon），
        #    改为锁**实现面**：函数体必须真的把 resolve_root 的结果交给 subprocess 的 cwd。
        #    `^` 行首锚定 + 只比对真实代码行（判例-30：防模式串自指 —— 本文件的字符串常量里
        #    也出现过 "cwd=root"，用子串匹配会恒绿）。
        src_text = ""
        try:
            with open(os.path.abspath(__file__), encoding="utf-8", errors="replace") as f:
                src_text = f.read()
        except OSError:
            src_text = ""
        real_line = any(
            ln.startswith("    p = subprocess.run(") and "cwd=root" in ln
            for ln in src_text.splitlines()
        )
        cell("root-wired-into-subprocess-cwd", real_line, True)
        # 变异对照：把真实代码行里的 cwd=root 删掉后，上面的判据必须变红
        mutated = "\n".join(
            ("    p = subprocess.run(cmd, env=env, capture_output=True, text=True, encoding=\"utf-8\", errors=\"replace\")"
             if ln.startswith("    p = subprocess.run(") else ln)
            for ln in src_text.splitlines()
        )
        mutated_ok = any(
            ln.startswith("    p = subprocess.run(") and "cwd=root" in ln
            for ln in mutated.splitlines()
        )
        cell("root-mutation-detected", mutated_ok, False)
    finally:
        shutil.rmtree(tmp_root, ignore_errors=True)
        shutil.rmtree(other_root, ignore_errors=True)

    bad = [(n, w) for n, ok, w in cells if not ok]
    if bad:
        print("SELFTEST FAIL：")
        for n, w in bad:
            print("  - %s：%s" % (n, w))
        return 1
    print("SELFTEST OK（%d 格：垫片目录识别两档 + PATH 清理三档 + node 解析两档 + moonc 覆盖四档 + 服务端 spawn 面六档 + BUG-394 透传九档 + BUG-416 root 十档含变异对照）" % len(cells))
    return 0


def main(argv):
    if "--selftest" in argv:
        return selftest()
    root_arg, argv = parse_root(argv)
    root = resolve_root(root_arg)
    if root is None:
        print("  FATAL --root 不是已存在的目录：%s ⇒ 拒绝出数（rc=2）" % root_arg)
        print("        本入口**不静默回落到脚本目录**——那正是 BUG-416（在副本/导出树里静默测主树）。")
        return 2
    raw_log, argv = parse_raw_log(argv)
    # BUG-416：把**实际生效的根**打出来，让「这一跑测的是哪棵树」一眼可核。
    # 缺省时同时标出「= 脚本目录」，提醒它与 cwd 无关（在副本里跑会测到主树）。
    if root_arg is None:
        print("  ROOT：%s（缺省=脚本目录，与本进程 cwd 无关；要测别的树请加 --root <path>）" % root)
    else:
        print("  ROOT：%s（--root 显式指定）" % root)
    dry = "--dry-run" in argv
    args = strip_redundant_moon_prefix([a for a in argv if a not in ("--dry-run",)])
    clean, dropped, _kept = clean_path(os.environ.get("PATH", ""))
    node, real, why = resolve_node(clean)
    print("  PATH 垫片目录：%d 个%s" % (len(dropped), ("（" + "; ".join(dropped) + "）") if dropped else ""))
    print("  node 解析：%s（%s）" % (node or "(无)", why))
    if not node or not real:
        print("  FATAL 清理后仍拿不到真实 node.exe ⇒ 拒绝出数（rc=2，不冒用 0/1 两档）")
        return 2
    override, owhy = pick_moonc_override(
        os.environ.get("MOONC_OVERRIDE", ""),
        DEFAULT_MOONC_SHIM,
        os.path.isfile(DEFAULT_MOONC_SHIM),
        os.name == "nt",
    )
    if override:
        print("  moonc override：%s（%s）" % (
            override, "环境变量显式指定" if owhy == "env" else r"自动发现本机 shim（剥离 \\?\ 前缀）"))
    elif os.name == "nt":
        print(r"  moonc override：未找到 —— 冷编译可能撞 moonc 的 \\?\ 路径 ICE（工具链缺陷，见 scripts/README.md）")
    env = dict(os.environ)
    env["PATH"] = clean
    if override:
        env["MOONC_OVERRIDE"] = override
    cmd = ["moon", "test", "--target", "js"] + args
    print("  执行：%s" % " ".join(cmd))
    if dry:
        return 0
    # BUG-416：`cwd=root` 是本修的**实质**——只打印 ROOT 而不切 cwd 等于没修
    # （moon 会在调用者 cwd 里跑，副本树仍静默测主树）。缺省 root=脚本目录，
    # 与修前「无 cwd 参数、由调用者 cwd 决定」**不同**：修前从仓库外调用会跑错树，
    # 修后恒定落到脚本所在仓库 ⇒ 这是**修正**，不是回归（见 reports 里的零回归论证）。
    p = subprocess.run(cmd, env=env, cwd=root, capture_output=True, text=True, encoding="utf-8", errors="replace")
    out = (p.stdout or "") + (p.stderr or "")
    if raw_log:
        write_raw_log(raw_log, p.stdout or "")
    tail = [l for l in out.strip().splitlines() if l.strip()][-6:]
    for l in tail:
        print("  | " + l[:150])
    # 2026-10-23：失败时**必须点名是哪条测试**。原先只打最后 6 行，而 moon 的失败行在更早的输出里
    # ⇒ 判据在最需要信息的那一刻恰好把它藏掉了（与 check_scripts_naming 的 `--show` 不可达同族缺陷）。
    # 过滤刻意**只认 moon 的失败形状**，不认 "failed" 泛词：第一版用 `\bfailed\b|error\[` 太松，
    # 把诊断上下文里的源码行（如 `match result.value("failed") {`）也当成失败行打了出来——
    # 面板里混进无关行，就没人知道哪行才是结论。
    RX_TEST_FAIL = re.compile(
        r"(?:\btest\b.*\bfailed:)|(?:\bFAILED:\s)|(?:panicked at)|(?:❌)"
    )
    fail_lines = [l for l in out.splitlines() if RX_TEST_FAIL.search(l)]
    if fail_lines:
        print("  ---- 失败行（摘出，最多 20 条）----")
        for l in fail_lines[:20]:
            print("  F| " + l[:200])
    moon_line = english_summary_line(out)
    m = RX_SUMMARY.search(moon_line) if moon_line else None
    if "failed to parse args" in out:
        print("  判据失败：测试产物收到残缺 JSON（说明 PATH 垫片没清干净或 moon 用了别的 node）")
        return 1
    if "Sys_error" in out and "Invalid argument" in out:
        print(r"  判据无法自证：moonc 撞上 `\\?\` 路径 ICE（工具链缺陷）——设 MOONC_OVERRIDE 指向剥离前缀的 shim，或把编译面交给 CI（Linux）")
        return 2
    if m is None:
        print("  判据无法自证：没有汇总行 `Total tests: …` ⇒ rc=2（BUG-142：不许只凭 moon 的退出码判绿）")
        return 2
    total, passed, failed = int(m.group(1)), int(m.group(2)), int(m.group(3))
    print("  汇总：Total tests %d / passed %d / failed %d" % (total, passed, failed))
    # BUG-394 修法 A：把 moon 原始英文汇总行**原样透传**到标准输出——这是 check_badge /
    # check_test_sync 认的形状。中文 `汇总：` 行保留给人类；英文行才是两把尺能直接消费的入口。
    print(moon_line)
    if failed != 0 or passed != total:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
