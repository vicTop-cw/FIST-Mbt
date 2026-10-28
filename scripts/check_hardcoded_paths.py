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
    形式的家目录，以及**盘符绝对路径形状**（A 面词表 + B 面形状锁，见下）。
    **测试夹具里合成盘符路径（`E:/repo/...`、`E:/proj/...`）不算违例**——那是形状输入，不是
    某台机器的绑定。本判据抓的是「这台机器是谁」，不是「有没有绝对路径」。

  · **B 面形状锁（词表补强，2026-10-24 统帅裁决第二步）**：A 面词表只认 `IDEProjects`/`victo`
    两个 token，实测漏掉了 `.dsh/fist-mbt-plugin/cordis.patch.yml` 里的
    `'F:/AI/Fist-Mbt/...'`——换一台机器就是另一个未知根，**加 token 只是把下一个未知工程名
    漏在外面**。所以补强改成形状判据：**配置面（`.dsh/**`）**出现 `<盘符>:[\\/]` 形状即红。
    为什么只判配置面、不判全扫描面：那个面会被别的克隆者**按字面直接读走并执行**（`args`/`cwd`），
    是"写一次、所有人拿到错误路径"的唯一位置；代码面的盘符绝大多数是测试夹具的合成形
    （`E:/proj/AI/Cypy`、`C:/fist-runs/…`）与判据自身的刻度，判红等于让尺子恒红、变异台失效
    （首版全扫面一跑 102 处、真违例只有 3 条，收窄标定就读实写在 `B_FACE_PREFIXES` 旁）。
    三类豁免（都由合成自检格钉住，见 B1~B4）：
      ① 模板占位符行：含 `{{...}}` 或 `${...}`（模板态的合法形状，值由渲染器注入）；
      ② 反例说明行：注释/docstring 里作为**被禁止的形状**被引述；
      ③ 教学用占位段：`<user>` `<dir>` 这类任何机器都能照抄的段名。

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
from git_env import isolated_git_env

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

# ---- B 面：盘符绝对路径形状锁（词表补强的正身）----
# 为什么是「形状」而不是再加几个 token：`F:/AI/Fist-Mbt` 这类本机根的**目录名**无穷，
# 而它的**形状**是有限的一种。加 token 只是把下一个未知工程名漏在外面（同一个坑换张皮）。
RE_DRIVE_PATH = re.compile(
    r"(?<![A-Za-z0-9])[A-Za-z]:(?:[\\]{1,2}|/)[A-Za-z_.\-<>~$*%]+(?:(?:[\\]{1,2}|/)[A-Za-z_.\-<>~$*%]+)+")
# **B 面只判「会被别的克隆者直接读到并按字面执行」的面——配置面（`.dsh/**`）**。
#
# 收窄过程（2026-10-24，实读标定，不是想当然）：首版对全扫描面判「任何盘符形状」，一跑
# **102 处**、其中真违例只有 3 条；按「两个及以上目录段」收紧后仍有 36 处，绝大多数是
# **测试夹具的合成路径**（`C:/fist-runs/redirected.db`、`E:/proj/AI/Cypy`、`E:/repo/_build/...`）
# 与**判据自身的刻度**（`check_hardcoded_paths.py` 必须写出它要抓的形状）。把这些都判红，
# 等于让尺子在现状面恒红、变异台失效——红着没人读的判据等于没判据。
#
# 之所以**代码面不必**给 B 面：`src/**` `cmd/**` `scripts/**` 里若写出某台机器根，那个根
# 一定要么含本机身份 token（A 面已咬住 `IDEProjects`/`victo`），要么出现在**夹具**里（合成形，
# 不是绑定）。真正「写一次、所有克隆者都拿到错误路径」的只有配置面——这正是本次实测命中
# `F:/AI/Fist-Mbt` 的位置（`.dsh/fist-mbt-plugin/{cordis.patch.yml,locale/*.json}`）。
B_FACE_PREFIXES = (".dsh/",)
# 豁免③：教学用占位段——`<user>` `<dir>` 这类任何机器都能照抄的段名，不构成机器绑定。
RE_PLACEHOLDER_SEG = re.compile(r"<[^<>]+>|\.\.\.|…")

# 豁免②：反例说明行的「引述标记」——剔掉行首注释符之后以这些标记开头，说明这一行的盘符是
# 被**作为反面样本引述**的，不是真的绑定了某台机器。
RE_QUOTE_MARKS = re.compile(r"^[（(《「『\"'`]|^(如|例|反例|例如|形如|写成|不许|禁止|禁|不得)")


def _is_comment_quoted_drive(line: str) -> bool:
    """行内出现「注释里作为反例被引述的盘符形状」⇒ True（豁免②）。

    认三种引出形：`# ... F:/x`、`· ... F:/x`、以及三引号 docstring 行。
    只认「盘符形状之前是引述语境」——一行里同时有真实绑定与引述时，依靠 `_drive_tokens`
    逐个 token 判定，被引述的那个跳过、其余照红。
    """
    stripped = line.lstrip()
    is_comment = stripped.startswith(("#", "·", "//", "*"))
    if not is_comment and not ('"""' in line or "'''" in line):
        return False
    # 该行里每个盘符前面的片段，只要有一个满足「引述标记结尾」就算引述形
    for m in RE_DRIVE_PATH.finditer(line):
        head = line[:m.start()].rstrip().rstrip("#·/").rstrip()
        if RE_QUOTE_MARKS.search(head) or head.endswith(("如", "例", "形如", "写成", "：")):
            return True
    return False


def _drive_violations(rel: str, line: str, lineno: int) -> list[str]:
    """B 面逐 token 判定：返回该行里**未被豁免**的盘符形状违例（只判配置面）。"""
    if not rel.startswith(B_FACE_PREFIXES):
        return []
    if not RE_DRIVE_PATH.search(line):
        return []
    # 豁免①：模板占位符行（值由渲染器注入，不绑定任何机器）
    if "{{" in line or "${" in line:
        return []
    # 豁免②：反例说明行
    if _is_comment_quoted_drive(line):
        return []
    out: list[str] = []
    for m in RE_DRIVE_PATH.finditer(line):
        frag = m.group(0)
        # 豁免③：教学用占位段（`<user>` `<dir>`）
        if RE_PLACEHOLDER_SEG.search(frag):
            continue
        out.append("%s:%d: 出现盘符绝对路径 `%s`（本机根形状：配置面会被别的克隆者按字面读走；"
                   "模板请用 {{占位符}}、配置请用相对路径/环境变量）"
                   % (rel, lineno, frag))
    return out


def current_face(root: Path, env=None) -> list[str]:
    """git 跟踪面里属于「当前面」的文件（正斜杠相对路径）。取不到 git 返回空。

    `env=None` 读宿主（live 的正确语义）；`--selftest` 必须传 `isolated_git_env()`，
    否则在 pre-commit 钩子环境里 git 注入的 `GIT_DIR`/`GIT_INDEX_FILE` 会压过 `-C`，
    夹具读到的是宿主索引（R44 同形地雷，由 `check_git_sandbox_hygiene.py` 普查棘轮钉住）。
    """
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

    两个面（D 面由 slave/clean-dsh-recur-r3 引入，2026-10-24）：
      · A 面（词表）：已知本机身份 token（工程目录名 / 家目录）。
      · D 面（结构锁）：**渲染件永不回跟踪面**——`.dsh/**/cordis.patch.yml`（非 `.tpl`）
        被 git 跟踪即违例，**与盘符字面形状无关**。为什么词表不够：换一台机器写 `F:/`、
        再换一台写 `Z:/`，A 面只认已知 token 就全漏 ⇒ 实测 main 上
        `.dsh/fist-mbt-plugin/cordis.patch.yml` 带着 `F:/AI/Fist-Mbt` 跟踪进仓，
        `check_hardcoded_paths` 判 PASS（本锁正是为这一次假绿立的）。
      · D2：`.dsh/**` 的 YAML 值面出现盘符绝对路径字面量即违例（`{{占位符}}` 与
        `${变量}` 豁免——那是模板态的合法形状）。
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
            # D2：.dsh YAML 的值面盘符锁（`key:` 形与 `- 列表项` 形都要覆盖——
            # 渲染件的 args 路径写在 `- 'F:/...'` 行上，只匹配 `key:` 会漏）。
            if rel.startswith(".dsh/") and rel.endswith((".yml", ".yaml")):
                m2 = re.search(r"(?:^|[\s:\-])['\"]?([A-Za-z]:[\\/]\S*?)['\"]?\s*$", line)
                if m2 and "{{" not in line and "${" not in line:
                    problems.append("%s:%d: `.dsh` YAML 值面出现盘符绝对路径 `%s`"
                                    "（模板只许 {{占位符}}；渲染件不得在跟踪面）"
                                    % (rel, i, m2.group(1)))
            # B 面：全扫描面的盘符形状锁（不限 .dsh/，三类豁免见上方常量注释）
            problems.extend(_drive_violations(rel, line, i))
    return problems


def selftest() -> list[str]:
    """合成 git 仓自证：违例必红、干净必绿、豁免面不误红、空扫描面自拒。"""
    fails: list[str] = []
    done: list[str] = []

    def cell(name: str, ok: bool, note: str = "") -> None:
        if not ok:
            fails.append("%s — %s" % (name, note))
        else:
            done.append(name)

    selftest.count_ok = 0

    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        # R46：夹具里的 git 调用必须带 isolated_git_env()——否则在 pre-commit 钩子环境里，
        # git 注入的 GIT_DIR/GIT_INDEX_FILE 会盖过 cwd，把夹具的 init/config/add 落到**真仓**上
        # （R44 实测：真工作树被连写 9 个 fixture 提交、本仓身份被改成 t/t@t）。
        genv = isolated_git_env()
        subprocess.run(["git", "init", "-q"], cwd=root, capture_output=True, env=genv)
        subprocess.run(["git", "config", "user.email", "t@t"], cwd=root, capture_output=True, env=genv)
        subprocess.run(["git", "config", "user.name", "t"], cwd=root, capture_output=True, env=genv)

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
        # D1 违例：渲染件回跟踪面（未知机器根 Z:/ 也咬得住——结构锁不看词表）
        (root / ".dsh" / "fist-mbt-plugin").mkdir(parents=True)
        (root / ".dsh" / "fist-mbt-plugin" / "cordis.patch.yml").write_text(
            "args:\n  - 'Z:/someone/tool/launch.mjs'\n", encoding="utf-8")
        # D1 合法：模板态（.tpl 带占位符）不判
        (root / ".dsh" / "fist-mbt-plugin" / "cordis.patch.yml.tpl").write_text(
            "args:\n  - '{{FIST_MBT_CLI}}'\ncwd: '{{FIST_MBT_ROOT}}'\n", encoding="utf-8")
        # D2 违例：.dsh YAML 值面盘符（列表项形 `- 'F:/...'`，词表面抓不到的形状）
        (root / ".dsh" / "pkg.yml").write_text("cwd: 'F:/AI/x'\n", encoding="utf-8")
        # ---- B 面（词表补强）合成夹具（配置面）----
        # B1 违例：真实本机根形状（词表里没有任何 token 命中，只有形状锁咬得住）
        (root / ".dsh" / "leak.yml").write_text(
            "args:\n  - 'F:/AI/Fist-Mbt/_build/js/cli.js'\n", encoding="utf-8")
        # B2 豁免①：模板占位符行（值由渲染器注入，不绑定任何机器）
        (root / ".dsh" / "tpl.yml").write_text(
            "args:\n  - '{{FIST_MBT_CLI}}'\ncwd: '${FIST_MBT_ROOT}'\n", encoding="utf-8")
        # B3 豁免②：注释里作为反例被引述的盘符（「不许写成 F:/...」）
        (root / ".dsh" / "quote.yml").write_text(
            "# 不许写成 F:/AI/Fist-Mbt 这样的本机路径，改用相对路径\nok: 1\n", encoding="utf-8")
        # B4 豁免③：教学用占位段（任何机器都能照抄）
        (root / ".dsh" / "doc.yml").write_text(
            "path: 'C:/Users/<user>/AppData/Local/Temp/<dir>'\n", encoding="utf-8")
        # B5 反向对照：同样的盘符写在**代码面**不判（夹具合成形，不是配置绑定）
        (root / "scripts" / "fixture.py").write_text(
            'P = r"E:\\proj\\AI\\Cypy"\nQ = "C:/fist-runs/redirected.db"\n', encoding="utf-8")
        # B6 独立性锁：**非 YAML** 的配置面（`.dsh/**` 的语言包 JSON）——D2 只管 .yml/.yaml，
        # 这一格保证 B 面对配置面的覆盖不依赖 D2：摘掉 B 面必红，摘掉 D2 仍绿。
        (root / ".dsh" / "locale.json").write_text(
            '{"cli": "F:\\\\AI\\\\Fist-Mbt"}\n', encoding="utf-8")
        subprocess.run(["git", "add", "-A"], cwd=root, capture_output=True, env=genv)

        files = current_face(root, env=genv)
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
        # ---- B 面（词表补强）：必红 1 格 + 不误红 4 格 ----
        cell("B1 未知本机根形状（配置面）→红",
             any("leak.yml:" in p and "盘符绝对路径" in p for p in probs), str(probs))
        cell("B2 模板占位符行不误红",
             not any("tpl.yml" in p for p in probs), str(probs))
        cell("B3 注释反例引述不误红",
             not any("quote.yml" in p for p in probs), str(probs))
        cell("B4 教学用占位段不误红",
             not any("doc.yml" in p and "本机根形状" in p for p in probs), str(probs))
        cell("B5 代码面夹具合成形不误红",
             not any("fixture.py" in p for p in probs), str(probs))
        cell("B6 非 YAML 配置面（JSON）→红",
             any("locale.json:" in p and "本机根形状" in p for p in probs), str(probs))
        # C5 变异台：把扫描面收成「只豁免」⇒ 必空，调用方据空自拒（防「削空=假绿」）
        cell("C5 空扫描面可识别", not current_face(root / "reports", env=genv), "应无跟踪文件")

    selftest.executed = done
    return fails


def main(argv: list[str]) -> int:
    unknown = [a for a in argv if a != "--selftest"]
    if unknown:
        print("FATAL 未知参数：%s（本尺只接受 --selftest）" % " ".join(unknown))
        sys.exit(2)
    # ↑ 严格参数面（R65）：未知旗标不再被静默忽略（拼错 --selftest 会假绿）
    if "--selftest" in argv:
        fails = selftest()
        if fails:
            print("SELFTEST FAIL 判据自身有问题：")
            for f in fails:
                print("  - " + f)
            return 1
        # 格数从已执行对照反解，不手写（本轮加了 D1/D1b/D2/B1~B6，手写自述必漂）
        done = getattr(selftest, "executed", [])
        print("SELFTEST OK %d 格全按预期：%s（计数从已执行对照反解，不手写）"
              % (len(done), " / ".join(done)))
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
