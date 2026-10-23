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
`-o` / `-all-pkgs` 等输出路径写成 `\\?\F:\…` 长路径前缀，moonc 打开时直接
`Sys_error("\\\\?: Invalid argument")`（与本仓代码无关，最小工程同样复现；同族见 BUG-388 的
`moon fmt --check` 面）。本机既有绕法是 `MOONC_OVERRIDE` 指向一个**剥离 `\\?\` 前缀再转发**的 shim。
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
  python scripts/moon_test_env.py --selftest      # 离线验垫片识别/清理 + 服务端 spawn 面
  python scripts/moon_test_env.py --dry-run       # 只打印将要执行的环境与命令
"""
import os
import re
import shutil
import subprocess
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SHIM_NAMES = ("node.cmd", "node.bat")


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
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SERVER_SPAWN_REL = os.path.join("src", "server", "run_check_js.mbt")


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

    bad = [(n, w) for n, ok, w in cells if not ok]
    if bad:
        print("SELFTEST FAIL：")
        for n, w in bad:
            print("  - %s：%s" % (n, w))
        return 1
    print("SELFTEST OK（%d 格：垫片目录识别两档 + PATH 清理三档 + node 解析两档 + moonc 覆盖四档 + 服务端 spawn 面六档）" % len(cells))
    return 0


def main(argv):
    if "--selftest" in argv:
        return selftest()
    args = [a for a in argv if a not in ("--dry-run",)]
    dry = "--dry-run" in argv
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
    p = subprocess.run(cmd, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace")
    out = (p.stdout or "") + (p.stderr or "")
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
    m = None
    for line in out.splitlines():
        mm = re.search(r"Total tests:\s*(\d+),\s*passed:\s*(\d+),\s*failed:\s*(\d+)", line)
        if mm:
            m = mm
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
    if failed != 0 or passed != total:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
