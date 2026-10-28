#!/usr/bin/env python3
r"""moon 子进程环境探针（R125）：moonc `\\?\` ICE 的本机绕法单一真源。

本仓有多个常驻入口自己 spawn `moon build/check`（fist.py 的 BUG-32 自动重建、web 桥、
fist-gate、风语者、合支检查、HEAD 模拟、release 快照、演示）。干净 PATH 且 `_build`
冷缓存时，它们会撞 moonc 的 `Sys_error("\\\\?: Invalid argument")`，把工具链缺陷
报成业务失败。R124 已在 `moon_test_env.py` 里为 `moon test` 做了同一件事；本模块把
那条发现规则收成可复用件：显式 `MOONC_OVERRIDE` 优先；Windows 且
`~/.moon-shim/shim.exe` 存在则自动使用；其他情况原样透传。

用法（入口脚本）：
    from moon_env_probe import moon_env
    subprocess.run(["moon", "build", ...], env=moon_env(), ...)

不带参数：静态普查 scripts/ 下 spawn `["moon"` 的顶层 .py 是否都接入了本模块
（未接线的点名 rc=1；扫描面为空自拒 rc=2）。
`--selftest`：离线自证发现规则与普查判据。
"""
import argparse
import json
import os
import re
import sys
import tempfile
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

SCRIPTS_DIR = Path(__file__).resolve().parent
SELF = Path(__file__).name
SHIM_REL = Path(".moon-shim") / "shim.exe"
SPAWN_RE = re.compile(r"""\[\s*["']moon["']""")

# 不接线的既有面：理由必须非空（selftest 盯这一格）。新增条目 = 一次显式决定。
ALLOWLIST = {
    "moon_test_env.py": "R124 自带同一发现逻辑；为避免改动其 12 格自检面，去重收敛留后续单",
    "check_fmt_gate.py": "只 spawn `moon fmt --check`，不经 moonc 编译面",
    "check_exit_code_contract.py": '`["moon"]` 出现在生成的夹具字符串里，不是真 spawn',
}


def moonc_override(env_value=None, shim_path=None, shim_exists=None, is_windows=None):
    """显式 env 优先；Windows 且垫片存在才自动发现；其余返回 None（纯函数）。"""
    if env_value:
        return env_value
    if shim_path is None:
        shim_path = Path.home() / SHIM_REL
    if is_windows is None:
        is_windows = os.name == "nt"
    if not is_windows:
        return None
    if shim_exists is None:
        try:
            shim_exists = Path(shim_path).is_file()
        except OSError:
            shim_exists = False
    return str(shim_path) if shim_exists else None


def moon_env(base=None, shim_path=None, shim_exists=None, is_windows=None):
    """返回交给 moon 子进程的环境副本；不改 os.environ，跨平台零回归。"""
    env = dict(os.environ if base is None else base)
    if not env.get("MOONC_OVERRIDE"):
        picked = moonc_override(env.get("MOONC_OVERRIDE"), shim_path, shim_exists, is_windows)
        if picked:
            env["MOONC_OVERRIDE"] = picked
    return env


def spawn_lines(text):
    return [i + 1 for i, line in enumerate(text.splitlines()) if SPAWN_RE.search(line)]


def audit(scripts_dir, texts=None):
    """普查 scripts/*.py：spawn moon 且未接 moon_env 的脚本点名。texts 供自检注入。"""
    if texts is None:
        texts = {}
        for path in sorted(Path(scripts_dir).glob("*.py")):
            if path.name == SELF:
                continue
            try:
                texts[path.name] = path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
    violations = []
    allowlisted = []
    scanned = 0
    for name in sorted(texts):
        if name == SELF:
            continue
        text = texts[name]
        lines = spawn_lines(text)
        if not lines:
            continue
        scanned += 1
        if "moon_env_probe" in text or "moon_env(" in text:
            continue
        if name in ALLOWLIST:
            allowlisted.append(name)
            continue
        violations.append({"script": name, "lines": lines})
    return {"scanned": scanned, "violations": violations, "allowlisted": allowlisted}


def decide(result):
    if result["scanned"] == 0:
        return 2
    return 1 if result["violations"] else 0


def selftest():
    cells = []

    def cell(cid, ok, detail=""):
        cells.append((cid, bool(ok)))
        print(("PASS " if ok else "FAIL ") + cid + ((" " + detail) if detail else ""))

    shim = "C:/Users/x/.moon-shim/shim.exe"
    cell("D1", moonc_override("D:/explicit.exe", shim, True, True) == "D:/explicit.exe",
         "显式 env 优先")
    cell("D2", moonc_override(None, shim, True, True) == shim, "Windows+垫片自动发现")
    cell("D3", moonc_override(None, shim, True, False) is None, "非 Windows 不设")
    cell("D4", moonc_override(None, shim, False, True) is None, "垫片缺失不设")
    base = {"A": "1"}
    injected = moon_env(base, shim, True, True)
    kept = moon_env({"MOONC_OVERRIDE": "D:/keep.exe"}, shim, True, True)
    cell("D5", injected.get("MOONC_OVERRIDE") == shim and "MOONC_OVERRIDE" not in base
         and kept.get("MOONC_OVERRIDE") == "D:/keep.exe",
         "moon_env 注入且不改 base / 保留显式值")

    dirty = {"x.py": 'import subprocess\nsubprocess.run(["moon", "build"])\n'}
    clean = {"y.py": 'import subprocess\nfrom moon_env_probe import moon_env\n'
                     'subprocess.run(["moon", "build"], env=moon_env())\n'}
    r_dirty = audit(".", dirty)
    r_clean = audit(".", clean)
    cell("A1", r_dirty["violations"] == [{"script": "x.py", "lines": [2]}],
         "未接线必点名")
    cell("A2", r_clean["violations"] == [] and r_clean["scanned"] == 1,
         "已接线不误红")
    r_allow = audit(".", {"check_fmt_gate.py": 'run(["moon", "fmt", "--check"])\n'})
    cell("A3", r_allow["violations"] == [] and r_allow["allowlisted"] == ["check_fmt_gate.py"],
         "白名单带理由放行")
    with tempfile.TemporaryDirectory() as tmp:
        empty = audit(tmp, {})
    cell("A4", empty["scanned"] == 0 and decide(empty) == 2, "空扫描面自拒")

    live = audit(SCRIPTS_DIR)
    cell("L1", decide(live) == 0 and live["scanned"] >= 8,
         "真现状面 %d 份接线 / 违例 %d" % (live["scanned"], len(live["violations"])))
    cell("L2", all(reason.strip() for reason in ALLOWLIST.values()), "白名单理由非空")

    failed = [cid for cid, ok in cells if not ok]
    if failed:
        print("SELFTEST FAIL: %d/%d（%s）" % (len(failed), len(cells), ", ".join(failed)))
        sys.exit(1)  # NO_CALL_FACE J2
    order = []
    for cid, _ in cells:
        if cid[0] not in order:
            order.append(cid[0])
    inv = " / ".join("%s×%d" % (f, sum(1 for c, _ in cells if c[0] == f)) for f in order)
    print("SELFTEST OK: %d 格（反解：%s）" % (len(cells), inv))
    sys.exit(0)  # NO_CALL_FACE J2


def main(argv=None):
    parser = argparse.ArgumentParser(description="moon 子进程环境探针（R125）")
    parser.add_argument("--selftest", action="store_true", help="离线自证发现规则与普查判据")
    args = parser.parse_args(argv)
    if args.selftest:
        return selftest()

    result = audit(SCRIPTS_DIR)
    rc = decide(result)
    result["moonc_override"] = moonc_override()
    result["shim_expected"] = str(Path.home() / SHIM_REL)
    result["rc"] = rc
    print(json.dumps(result, ensure_ascii=False))
    if rc == 2:
        print("MOON-ENV PROBE REFUSED: 扫描面为空（scripts/*.py 一个 spawn 面都没读到）")
    elif rc == 1:
        for item in result["violations"]:
            print("  - %s:%s spawn moon 但未接 moon_env()" %
                  (item["script"], ",".join(str(n) for n in item["lines"])))
    else:
        print("MOON-ENV PROBE OK: %d 份接线 / %d 份白名单 / 违例 0" %
              (result["scanned"], len(result["allowlisted"])))
    return rc


if __name__ == "__main__":
    sys.exit(main())
