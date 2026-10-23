#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""render_dsh_patch.py —— DSH 插件安装面「模板 → 本机渲染」（路径硬编码清零的落点）。

背景（本 PR 修的病灶）：`.dsh/fist-mbt-plugin/cordis.patch.yml` 从前直接写着
`E:/IDEProjects/...` 这发本机绝对路径。`@deepseek-ai/dsh-mcp-client` 的 stdio 通道把
`args`/`cwd` 当字面 argv 交给 spawn，**宿主不做 `${...}` 插值**——绝对路径进跟踪面
= 每个克隆者的 `server is disconnected`。反过来，纯相对路径也不行：DSH Host 的进程
cwd 不是本仓（`check_host_installable.py` D1 严格档正是为此而设，T1 格钉死）。

所以安装面拆成两态：
  · 跟踪真源  `.dsh/fist-mbt-plugin/cordis.patch.yml.tpl` —— 模板，禁止任何绝对路径，
    只含 `{{FIST_MBT_CLI}}` / `{{FIST_MBT_ROOT}}` 两个占位符；
  · 本地产物  `.dsh/fist-mbt-plugin/cordis.patch.yml` —— 本脚本渲染，已 gitignore，
    `package.json` 的 `dsh.bundle.patch` 指向的正是它（安装面形状不变，DSH 照旧读）。

路径来源全部由「本仓自身位置」推导，零硬编码，优先级从高到低：
  CLI：`--cli` > env `FIST_MBT_CLI` > `<root>/_build/js/debug/build/cmd/cli/cli.js`
        > `<root>/_build/js/release/build/cmd/cli/cli.js` > `_build/js/*/build/cmd/*/cli.js` 兜底
  根：  `--root` > env `FIST_MBT_HOME` > 由本脚本位置反推（scripts/ 的上一层）

用法：
  python scripts/render_dsh_patch.py            # 渲染（内容没变则不写盘，幂等）
  python scripts/render_dsh_patch.py --check    # 只校验渲染件与模板+本机路径是否一致
  python scripts/render_dsh_patch.py --selftest # 离线自证（沙箱在 temp，零副作用）
退出码契约（本仓口径）：0 成功 / 1 违例（产物缺失、漂移、模板硬编码）/ 2 判据无法自证。
"""
import argparse
import os
import re
import sys
import tempfile
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO_ROOT = Path(__file__).resolve().parents[1]
TPL_REL = ".dsh/fist-mbt-plugin/cordis.patch.yml.tpl"
OUT_REL = ".dsh/fist-mbt-plugin/cordis.patch.yml"
PLACEHOLDERS = ("{{FIST_MBT_CLI}}", "{{FIST_MBT_ROOT}}")

# 绝对路径形状：盘符 `X:/` 或 `X:\\`、POSIX 前导 `/`、UNC `\\host\share`。
ABS_RE = re.compile(r"^(?:[A-Za-z]:[\\/]|/|\\\\)")
# 模板里出现即视为「机器路径泄漏」——正斜杠/反斜杠盘符都抓。
DRIVE_LEAK_RE = re.compile(r"[A-Za-z]:[\\/]")
# Unix 家目录泄漏（模板注释里出现 /home/ 或 /Users/ 也算红）。
HOME_LEAK_RE = re.compile(r"(?:^|[\s'\"])(?:/home/|/Users/|[A-Za-z]:[\\\\/]Users)")


def to_posix(p: Path | str) -> str:
    """统一正斜杠形态：Windows 的 `E:\\x` 与 POSIX 的 `/x` 都归一（与 bug_fix 台账同口径）。"""
    s = str(Path(p))
    if len(s) >= 3 and s[0].isalpha() and s[1] == ":":
        # Windows 盘符：`\\?\` 前缀（若有）剥掉，反斜杠整体转正斜杠。
        s = s.replace("\\\\?\\", "").replace("\\", "/")
    return s.replace(os.sep, "/")


def find_cli(root: Path, cli_override: str | None) -> tuple[str | None, str]:
    """按优先级找 JS 可执行产物。返回 (正斜杠绝对路径或 None, 来源说明)。"""
    if cli_override:
        p = Path(cli_override)
        if not p.is_absolute():
            p = root / p
        p = p.resolve()
        if p.exists():
            return to_posix(p), "--cli"
        return None, f"--cli 指向的产物不存在: {to_posix(p)}"
    env = os.environ.get("FIST_MBT_CLI", "").strip()
    if env:
        p = Path(env)
        if not p.is_absolute():
            p = (root / p).resolve()
        if p.exists():
            return to_posix(p), "env FIST_MBT_CLI"
        return None, f"env FIST_MBT_CLI 指向的产物不存在: {to_posix(p)}"
    for rel in ("_build/js/debug/build/cmd/cli/cli.js",
                "_build/js/release/build/cmd/cli/cli.js"):
        p = root / rel
        if p.exists():
            return to_posix(p), rel
    cands = sorted(root.glob("_build/js/*/build/cmd/*/cli.js"))
    if cands:
        newest = max(cands, key=lambda c: c.stat().st_mtime)
        return to_posix(newest), f"_build glob 兜底({newest.parent.parent.parent.name})"
    return None, "找不到 _build/js/*/build/cmd/*/cli.js——先 `moon build --target js` 再渲染"


def render_text(tpl: str, cli: str, root: str) -> str:
    out = tpl.replace(PLACEHOLDERS[0], cli).replace(PLACEHOLDERS[1], root)
    return out


def template_problems(tpl: str) -> list[str]:
    """模板态判据：占位符齐全 + 机器路径零泄漏。真源必须与任何一台机器解耦。"""
    problems: list[str] = []
    for ph in PLACEHOLDERS:
        if ph not in tpl:
            problems.append(f"模板缺占位符 {ph}（渲染件将原样漏值或残留占位符）")
    if DRIVE_LEAK_RE.search(tpl):
        m = DRIVE_LEAK_RE.search(tpl)
        line = tpl[:m.start()].count("\n") + 1
        problems.append(f"模板第 {line} 行泄漏盘符绝对路径 `{m.group(0)}…`（模板禁止任何本机路径）")
    if HOME_LEAK_RE.search(tpl):
        problems.append("模板泄漏家目录形状路径（/home/ 或 /Users/）——同上，模板不得绑定某台机器")
    return problems


def rendered_problems(text: str) -> list[str]:
    """渲染件判据：占位符已全消 + 安装面必须绝对（D1 严格档同语义：相对 `_build/...` 按 Host cwd 解析 → disconnected）。"""
    problems: list[str] = []
    for ph in PLACEHOLDERS:
        if ph in text:
            problems.append(f"渲染件残留占位符 {ph}")
    # args 首元素与 cwd 的真值检查（行级小解析，不依赖 PyYAML，保证 selftest 面稳定）
    m = re.search(r"^\s*-\s+'(.*)'\s*$", text, re.M)
    m_args = re.findall(r"args:\n((?:\s+-\s+'.*'\n)+)", text)
    if m_args:
        first = re.search(r"-\s+'([^']+)'", m_args[0])
        if first and not ABS_RE.match(first.group(1)):
            problems.append(f"渲染件 args 首元素不是绝对路径：`{first.group(1)}`")
    m_cwd = re.search(r"^\s*cwd:\s*'([^']*)'", text, re.M)
    if m_cwd and not ABS_RE.match(m_cwd.group(1)):
        problems.append(f"渲染件 cwd 不是绝对路径：`{m_cwd.group(1)}`")
    return problems


def selftest() -> list[str]:
    fails: list[str] = []

    def cell(name: str, ok: bool, note: str = "") -> None:
        if not ok:
            fails.append(f"{name} — {note}")

    # ① 模板判据咬人：盘符泄漏必红
    bad_tpl = "cwd: 'E:/somewhere/repo'\nargs:\n  - '{{FIST_MBT_CLI}}'\n  - 'serve'\n"
    cell("T1 模板盘符泄漏→红", any("盘符" in p for p in template_problems(bad_tpl)))
    # ② 干净模板→绿
    clean_tpl = ("args:\n  - '{{FIST_MBT_CLI}}'\n  - 'serve'\ncwd: '{{FIST_MBT_ROOT}}'\n")
    cell("T2 干净模板→绿", not template_problems(clean_tpl), str(template_problems(clean_tpl)))
    # ③ 缺占位符→红
    cell("T3 缺 CLI 占位符→红",
         any("FIST_MBT_CLI" in p for p in template_problems("cwd: '{{FIST_MBT_ROOT}}'")))
    # ④ 渲染件残留占位符→红
    cell("T4 渲染件残留占位符→红",
         any("残留占位符" in p for p in rendered_problems("cwd: '{{FIST_MBT_ROOT}}'")))
    # ⑤ 渲染件相对安装面→红（D1 语义在渲染面复现）
    cell("T5 渲染件相对路径→红",
         any("不是绝对路径" in p for p in
             rendered_problems("args:\n  - '_build/js/debug/build/cmd/cli/cli.js'\n  - 'serve'\ncwd: '.'\n")))
    # ⑥ 渲染件绝对→绿
    cell("T6 渲染件绝对→绿",
         not rendered_problems("args:\n  - 'E:/repo/_build/js/debug/build/cmd/cli/cli.js'\n  - 'serve'\ncwd: 'E:/repo'\n"),
         str(rendered_problems("args:\n  - 'E:/repo/_build/js/debug/build/cmd/cli/cli.js'\n  - 'serve'\ncwd: 'E:/repo'\n")))
    # ⑦ to_posix 归一：反斜杠盘符转正斜杠
    cell("T7 to_posix 归一", to_posix("C:\\Users\\x\\repo") == "C:/Users/x/repo",
         to_posix("C:\\Users\\x\\repo"))
    # ⑧ 渲染幂等：同输入两次逐字节相等
    r1 = render_text(clean_tpl, "E:/r/cli.js", "E:/r")
    r2 = render_text(clean_tpl, "E:/r/cli.js", "E:/r")
    cell("T8 渲染幂等", r1 == r2)
    # ⑨ find_cli：--cli 优先、产物缺失点名出路
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        fake = root / "custom" / "cli.js"
        fake.parent.mkdir(parents=True)
        fake.write_text("// fake", encoding="utf-8")
        got, src = find_cli(root, str(fake))
        cell("T9 --cli 覆盖生效", got is not None and src == "--cli", f"got={got} src={src}")
        got2, why = find_cli(root, None)
        cell("T10 无产物→None+出路点名", got2 is None and "moon build" in why, f"why={why}")
        # ⑪ 默认 debug 路径命中
        dflt = root / "_build/js/debug/build/cmd/cli/cli.js"
        dflt.parent.mkdir(parents=True, exist_ok=True)
        dflt.write_text("//", encoding="utf-8")
        got3, src3 = find_cli(root, None)
        cell("T11 默认 debug 产物命中", got3 is not None and "debug" in src3, f"src={src3}")
        # ⑫ 模板+渲染真源现状：仓库里那份 tpl 必须过模板判据
        tpl_p = REPO_ROOT / TPL_REL
        if tpl_p.exists():
            cell("T13 仓内模板无泄漏", not template_problems(tpl_p.read_text(encoding="utf-8")),
                 str(template_problems(tpl_p.read_text(encoding="utf-8"))))

    if fails:
        return fails
    return []


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", default=None, help="仓库根（缺省 env FIST_MBT_HOME 或由脚本位置反推）")
    ap.add_argument("--cli", default=None, help="JS 可执行产物路径（缺省按优先级探测）")
    ap.add_argument("--out", default=None, help="渲染件路径（缺省 .dsh/fist-mbt-plugin/cordis.patch.yml）")
    ap.add_argument("--check", action="store_true", help="只校验：渲染件 == 模板渲染结果？")
    ap.add_argument("--selftest", action="store_true", help="离线自证（temp 沙箱，零副作用）")
    args = ap.parse_args(argv)

    if args.selftest:
        fails = selftest()
        if fails:
            print("SELFTEST FAIL：渲染判据自身有问题")
            for f in fails:
                print("  - " + f)
            return 1
        print("SELFTEST OK 渲染判据可红可绿（模板泄漏/缺占位符/渲染件残留/相对安装面 必红；"
              "干净模板/绝对渲染件/幂等/覆盖优先级 不误红）")
        return 0

    root = Path(args.root or os.environ.get("FIST_MBT_HOME") or REPO_ROOT).resolve()
    tpl_p = root / TPL_REL
    out_p = Path(args.out) if args.out else root / OUT_REL
    if not tpl_p.exists():
        print(f"FATAL 模板缺失：{tpl_p}（跟踪真源不在场，判据无法自证）")
        return 2
    tpl = tpl_p.read_text(encoding="utf-8")

    tprob = template_problems(tpl)
    if tprob:
        print("FAIL 模板态违例（真源不得绑定任何机器）：")
        for p in tprob:
            print("  - " + p)
        return 1

    cli, why = find_cli(root, args.cli)
    if cli is None:
        if args.check:
            print(f"FAIL --check 需要真产物在场：{why}")
            return 1
        print(f"FAIL 可执行产物缺失：{why}")
        return 1

    rendered = render_text(tpl, cli, to_posix(root))
    rprob = rendered_problems(rendered)
    if rprob:
        print("FAIL 渲染态违例：")
        for p in rprob:
            print("  - " + p)
        return 1

    if args.check:
        if not out_p.exists():
            print(f"FAIL --check：渲染件不存在 {out_p}（跑一次本脚本生成）")
            return 1
        cur = out_p.read_text(encoding="utf-8")
        if cur != rendered:
            print(f"FAIL --check：渲染件与「模板×本机路径」漂移：{out_p}")
            print("      （重跑 python scripts/render_dsh_patch.py 即可）")
            return 1
        print(f"PASS --check 渲染件与模板+本机路径一致（cli 来源={why}）")
        return 0

    changed = (not out_p.exists()) or out_p.read_text(encoding="utf-8") != rendered
    if changed:
        out_p.parent.mkdir(parents=True, exist_ok=True)
        out_p.write_text(rendered, encoding="utf-8")
        print(f"RENDERED → {to_posix(out_p)}")
    else:
        print(f"UP-TO-DATE {to_posix(out_p)}（内容一致，未写盘）")
    print(f"  cli = {cli}  (来源: {why})")
    print(f"  cwd = {to_posix(root)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
