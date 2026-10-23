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
  · D 面结构锁（2026-10-24 R3 引入，抓「换一台机器写别的盘符」这类词表漏网）：
      D1 `.dsh/**/cordis.patch.yml`（非 .tpl）**被 git 跟踪即违例**，与内容/盘符形状无关——
         合并通道曾把某台机的渲染件重新跟踪回 main，词表面只认已知 token 会漏未知根；
      D2 `.dsh/**` 的 YAML 里 args/cwd/env 标量值含盘符绝对路径即违例（`{{占位符}}` /
         `${变量}` 豁免——模板态的合法形状）。

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
import sys as _sys
_sys.path.insert(0, str(Path(__file__).resolve().parent))
from git_sandbox import sandbox_env  # 沙箱 git 隔离（R4：selftest 在钩子下不读宿主索引）

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
# 自指与临时件豁免（2026-10-24 实测补充）：
# - **判据自身**必须能写出它要抓的 token——`PATTERNS` 是把 `IDEProjects` 拆成两段构造的，
#   但文档/自检夹具里仍会出现整词；不豁免就等于「要求尺子不许写自己的刻度」。
# - `scripts/_*.py` 是本机一次性脚本（`_` 前缀，其它判据族同款豁免），不是仓的现状面。
EXEMPT_FILES = {"scripts/check_hardcoded_paths.py"}
EXEMPT_NAME_PREFIXES = ("scripts/_",)

# 机器身份 token：构造时拆成两段，避免守望脚本自己命中自己（本仓 issue_scan 规则表同款处理）
_MACHINE_DIRS = ("IDE" + "Projects",)
_HOME_USERS = ("victo",)
PATTERNS = [
    re.compile(re.escape(d)) for d in _MACHINE_DIRS
] + [
    re.compile(r"Users[\\/]" + re.escape(u), re.I) for u in _HOME_USERS
]


def current_face(root: Path, env=None) -> list[str]:
    """git 跟踪面里属于「当前面」的文件（正斜杠相对路径）。取不到 git 返回空。
    env=None 读宿主（live 正确语义）；selftest 传 sandbox_env()，否则钩子环境下
    `git -C <临时目录>` 被 GIT_DIR 压过 ⇒ 读到宿主索引（同一形地雷，R4 普查锁钉住）。"""
    try:
        out = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z"],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            env=env,
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
        if rel in EXEMPT_FILES or rel.startswith(EXEMPT_NAME_PREFIXES):
            continue
        if rel.startswith(SCAN_PREFIXES) or rel in SCAN_ROOT_FILES:
            files.append(rel)
    return files


def scan(root: Path, files: list[str]) -> list[str]:
    """逐文件逐行找机器身份 token。返回 `rel:lineno: 命中词` 形状的违例清单。

    两个面（2026-10-24 R3 升级）：
      · A 面（词表）：本机身份 token（工程目录名 / 家目录）。
      · D 面（结构锁）：**渲染件永不回跟踪面**——`.dsh/**/cordis.patch.yml`（非 .tpl）
        被 git 跟踪即违例，**与盘符形状无关**（换一台机写 `F:/`、再换一台写 `Z:/` 都咬得住；
        词表面只认已知 token，会漏未知机器的根，这是它抓不到本次回归的原因）。
      · D2：`.dsh/**` 的 YAML 里 args/cwd/env 的标量值含盘符绝对路径字面量即违例
        （`{{...}}` 模板占位与 `${...}` 宿主变量豁免——那是模板态的合法形状）。
    """
    problems: list[str] = []
    for rel in files:
        p = root / rel
        if not p.is_file():
            continue
        # D1：渲染件回跟踪面（结构锁，不看内容）
        if (rel.startswith(".dsh/") and rel.endswith("cordis.patch.yml")
                and not rel.endswith(".tpl")):
            problems.append("%s:1: 渲染件被重新跟踪（`.dsh/**/cordis.patch.yml` 必须是本地产物，"
                            "跟踪真源只有 .tpl）" % rel)
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
            # D2：.dsh YAML 的值面盘符锁（key: 形与 - 列表项形都要覆盖——
            # 渲染件的 args 路径写在 `- 'F:/...'` 行上，只匹配 `key:` 会漏）。
            if rel.startswith(".dsh/") and rel.endswith((".yml", ".yaml")):
                m2 = re.search(r"(?:^|[\s:\-])['\"]?([A-Za-z]:[\\/]\S*?)['\"]?\s*$", line)
                if m2 and "{{" not in line and "${" not in line:
                    problems.append("%s:%d: `.dsh` YAML 值面出现盘符绝对路径 `%s`"
                                    "（模板只许 {{占位符}}；渲染件不得在跟踪面）"
                                    % (rel, i, m2.group(1)))
    return problems


def selftest() -> list[str]:
    """合成 git 仓自证：违例必红、干净必绿、豁免面不误红、空扫描面自拒。"""
    fails: list[str] = []

    def cell(name: str, ok: bool, note: str = "") -> None:
        if not ok:
            fails.append("%s — %s" % (name, note))

    senv = sandbox_env()
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        subprocess.run(["git", "init", "-q"], cwd=root, capture_output=True, env=senv)
        subprocess.run(["git", "config", "user.email", "t@t"], cwd=root, capture_output=True, env=senv)
        subprocess.run(["git", "config", "user.name", "t"], cwd=root, capture_output=True, env=senv)

        (root / "scripts").mkdir()
        (root / "reports").mkdir()
        (root / ".dsh" / "fist-mbt-plugin").mkdir(parents=True)
        # C1 违例：当前面写出工程目录名
        (root / "scripts" / "bad.py").write_text('PROJ = "E:/IDEProjects/AI/x"\n', encoding="utf-8")
        # C2 豁免面：报告里的历史路径不判
        (root / "reports" / "old.md").write_text("E:/IDEProjects/AI/x\n", encoding="utf-8")
        # C3 干净：合成盘符形状（不是某台机器的绑定）
        (root / "scripts" / "ok.py").write_text('P = "E:/repo/proj"\n', encoding="utf-8")
        # C4 家目录形状
        (root / "scripts" / "home.py").write_text('H = r"C:\\Users\\victo\\.dsh"\n', encoding="utf-8")
        # D1 违例：渲染件回跟踪面（未知机器根 Z:/ 也咬得住——结构锁不看词表）
        (root / ".dsh" / "fist-mbt-plugin" / "cordis.patch.yml").write_text(
            "args:\n  - 'Z:/someone/tool/launch.mjs'\n", encoding="utf-8")
        # D1 合法：模板态（.tpl 带占位符）不判
        (root / ".dsh" / "fist-mbt-plugin" / "cordis.patch.yml.tpl").write_text(
            "args:\n  - '{{FIST_MBT_LAUNCHER}}'\ncwd: '{{FIST_MBT_ROOT}}'\n", encoding="utf-8")
        # D2 违例：.dsh YAML 值面盘符（列表项形 `- 'F:/...'`，词表面抓不到的形状）
        (root / ".dsh" / "pkg.yml").write_text("cwd: 'F:/AI/x'\n", encoding="utf-8")
        subprocess.run(["git", "add", "-A"], cwd=root, capture_output=True, env=senv)

        files = current_face(root, env=senv)
        cell("C0 扫描面非空", bool(files), "git ls-files 取不到当前面")
        probs = scan(root, files)
        cell("C1 工程目录名→红", any("bad.py:" in p for p in probs), str(probs))
        cell("C2 豁免面不误红", not any("old.md" in p for p in probs), str(probs))
        cell("C3 合成盘符不误红", not any("ok.py" in p for p in probs), str(probs))
        cell("C4 家目录→红", any("home.py:" in p for p in probs), str(probs))
        cell("D1 渲染件回跟踪→红", any("渲染件被重新跟踪" in p for p in probs), str(probs))
        cell("D1b 模板态不误红", not any("cordis.patch.yml.tpl" in p for p in probs), str(probs))
        cell("D2 值面盘符（列表/key 形）→红",
             any("值面出现盘符" in p for p in probs), str(probs))
        # C5 变异台：把扫描面收成「只豁免」⇒ 必空，调用方据空自拒（防「削空=假绿」）
        cell("C5 空扫描面可识别", not current_face(root / "reports", env=senv) , "应无跟踪文件")

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
