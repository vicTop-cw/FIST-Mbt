#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_hardcoded_paths.py — 「当前面不得写出本机身份路径」守卫（硬编码回归锁）。

为什么需要它：`.dsh/fist-mbt-plugin/cordis.patch.yml` 曾经把 `E:/<本机>/_build/...` 直接写进
跟踪面，宿主读到的就是「写它的那台机器」的路径——别的克隆者拿到即 `server is disconnected`。
同类坏味道还有：把某个用户的 home、某个人的工程目录名写进脚本/文档/测试注释。一次修干净
不够，得有尺子拦下一次回归（本仓口径：修一处必配一把尺）。

判据（当前面 = 会被执行 / 会被别的使用者读到的面）：
  · 扫描面：git 跟踪文件，限定 `.dsh/**` `scripts/**` `src/**` `cmd/**` `plugins/**`
    `.github/**` 与根级现状文档（README/AGENTS/USAGE/AI-DEVELOPMENT-STANDARD/docs/SOP.md/
    docs/2026-10-20-slave-dev-playbook.md/本仓 MCP 配置/moon.mod）。
  · 豁免面（**只追加的叙述历史**，改了等于伪造历史）：`CHANGELOG.md` `reports/**` `memory/**`
    `docs/archive/**`；`dist/**`（构建产物，随发布重建）；`.agents/**` `temp/**`（本地产物）；
    `*.mbti`（生成接口）。
  · 违例 token（机器身份，不是「所有绝对路径」）：`E:/IDEProjects` 类工程目录名、`Users/<user>`
    形式的家目录。**测试夹具里合成盘符路径（`E:/repo/...`）不算违例**——那是形状输入，不是
    某台机器的绑定。本判据抓的是「这台机器是谁」，不是「有没有绝对路径」。

退出码契约：0 = 当前面无本机身份路径 / 1 = 命中违例（逐条点名文件:行） / 2 = 判据无法自证
（git 取不到跟踪面 / 扫描面为空）。

用法：
    python scripts/check_hardcoded_paths.py            # 全量判据
    python scripts/check_hardcoded_paths.py --selftest # 合成仓自证可红可绿
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent

# 扫描面（现状面，会被执行或被使用者读到）
SCAN_PREFIXES = (
    ".dsh/", "scripts/", "src/", "cmd/", "plugins/", ".github/",
)
SCAN_ROOT_FILES = {
    "README.md", "AGENTS.md", "USAGE.md", "AI-DEVELOPMENT-STANDARD.md",
    "docs/SOP.md", "docs/2026-10-20-slave-dev-playbook.md",
    "moon.mod", "default-fist.mcp.json", ".mcp.dev.json",
}
# 豁免面（只追加的叙述历史 / 构建产物 / 本地产物 / 生成接口）
EXEMPT_PREFIXES = (
    "CHANGELOG.md", "reports/", "memory/", "docs/archive/", "dist/",
    ".agents/", "temp/",
)
EXEMPT_SUFFIXES = (".mbti",)

# 机器身份 token：构造时拆成两段，避免守望脚本自己命中自己（本仓 issue_scan 规则表同款处理）
_MACHINE_DIRS = ("IDE" + "Projects",)
_HOME_USERS = ("victo",)
PATTERNS = [
    re.compile(re.escape(d)) for d in _MACHINE_DIRS
] + [
    re.compile(r"Users[\\/]" + re.escape(u), re.I) for u in _HOME_USERS
]


def current_face(root: Path) -> list[str]:
    """git 跟踪面里属于「当前面」的文件（正斜杠相对路径）。取不到 git 返回空。"""
    try:
        out = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z"],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
        )
    except Exception:
        return []
    if out.returncode != 0:
        return []
    files: list[str] = []
    for rel in (out.stdout or "").split("\0"):
        if not rel:
            continue
        rel = rel.replace("\\", "/")
        if rel.startswith(EXEMPT_PREFIXES) or rel.endswith(EXEMPT_SUFFIXES):
            continue
        if rel.startswith(SCAN_PREFIXES) or rel in SCAN_ROOT_FILES:
            files.append(rel)
    return files


def scan(root: Path, files: list[str]) -> list[str]:
    """逐文件逐行找机器身份 token。返回 `rel:lineno: 命中词` 形状的违例清单。"""
    problems: list[str] = []
    for rel in files:
        p = root / rel
        if not p.is_file():
            continue
        try:
            text = p.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        for i, line in enumerate(text.splitlines(), 1):
            for rx in PATTERNS:
                m = rx.search(line)
                if m:
                    problems.append("%s:%d: `%s`（当前面不得写出本机身份路径）"
                                    % (rel, i, m.group(0)))
    return problems


def selftest() -> list[str]:
    """合成 git 仓自证：违例必红、干净必绿、豁免面不误红、空扫描面自拒。"""
    fails: list[str] = []

    def cell(name: str, ok: bool, note: str = "") -> None:
        if not ok:
            fails.append("%s — %s" % (name, note))

    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        subprocess.run(["git", "init", "-q"], cwd=root, capture_output=True)
        subprocess.run(["git", "config", "user.email", "t@t"], cwd=root, capture_output=True)
        subprocess.run(["git", "config", "user.name", "t"], cwd=root, capture_output=True)

        (root / "scripts").mkdir()
        (root / "reports").mkdir()
        # C1 违例：当前面写出工程目录名
        (root / "scripts" / "bad.py").write_text('PROJ = "E:/IDEProjects/AI/x"\n', encoding="utf-8")
        # C2 豁免面：报告里的历史路径不判
        (root / "reports" / "old.md").write_text("E:/IDEProjects/AI/x\n", encoding="utf-8")
        # C3 干净：合成盘符形状（不是某台机器的绑定）
        (root / "scripts" / "ok.py").write_text('P = "E:/repo/proj"\n', encoding="utf-8")
        # C4 家目录形状
        (root / "scripts" / "home.py").write_text('H = r"C:\\Users\\victo\\.dsh"\n', encoding="utf-8")
        subprocess.run(["git", "add", "-A"], cwd=root, capture_output=True)

        files = current_face(root)
        cell("C0 扫描面非空", bool(files), "git ls-files 取不到当前面")
        probs = scan(root, files)
        cell("C1 工程目录名→红", any("bad.py:" in p for p in probs), str(probs))
        cell("C2 豁免面不误红", not any("old.md" in p for p in probs), str(probs))
        cell("C3 合成盘符不误红", not any("ok.py" in p for p in probs), str(probs))
        cell("C4 家目录→红", any("home.py:" in p for p in probs), str(probs))
        # C5 变异台：把扫描面收成「只豁免」⇒ 必空，调用方据空自拒（防「削空=假绿」）
        cell("C5 空扫描面可识别", not current_face(root / "reports") , "应无跟踪文件")

    return fails


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        fails = selftest()
        if fails:
            print("SELFTEST FAIL 判据自身有问题：")
            for f in fails:
                print("  - " + f)
            return 1
        print("SELFTEST OK 硬编码回归锁可红可绿（工程目录名/家目录 必红；"
              "豁免历史面/合成盘符形状 不误红；空扫描面可识别）")
        return 0

    files = current_face(ROOT)
    if not files:
        print("FATAL 扫描面为空（git 跟踪面取不到）——拒绝出结论，不静默绿")
        return 2
    problems = scan(ROOT, files)
    if problems:
        print("FAIL 当前面出现本机身份路径（改用配置/相对路径/环境变量）：")
        for p in problems[:60]:
            print("  - " + p)
        if len(problems) > 60:
            print("  …（共 %d 处）" % len(problems))
        return 1
    print("PASS 当前面无本机身份路径（扫描 %d 个跟踪文件；豁免面=只追加历史/构建产物/本地产物）"
          % len(files))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
