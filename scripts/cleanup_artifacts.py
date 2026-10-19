#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/cleanup_artifacts.py — 项目整洁：清理 gitignore 的代码生成物/临时脚本残留。

背景（目标 pillar：项目整洁干净《临时脚本任务完清理策略、代码生成物清理》）。
测试与自驱脚本会在仓库根留下大量被 gitignore 的 SQLite 生成物（watchdog_*.db、wal-*.db、
smoke_*.db、decompose_persist.db、alpha.db 等 .db / -shm / -wal），并在 temp/ 留下 scratch 库。
这些不进 git，但污染任意检出的工作树，干扰"任意机器结果可复现"。

本脚本（幂等、安全）：
  - 删除仓库根"除 fist-mbt.db（唯一被 git 跟踪的交付 数据库快照）之外"的全部 *.db / *.db-shm / *.db-wal；
  - 清空 temp/（scratch 临时库区）；
  - 把 scripts/ 下 `_` 前缀的**未跟踪**临时脚本（任务完即清策略）移入 temp/，使正式工具目录干净；
  - **BUG-334：git 跟踪的 `_` 脚本是正式资产**（如 `scripts/_tool_registry.py` 工具注册单一真源，
    被 check_tools_sync / check_plugin_sync / gen_plugins / check_doc_surface / mcp_smoke 等 7 处导入），
    一律不动——只清 `git ls-files --others`（untracked），从根上避免误删已跟踪临时文件；
  - --check 模式只报告残留数量（0 = 干净），不删任何文件。

用法：
  python scripts/cleanup_artifacts.py          # 清理 + 打印各文件
  python scripts/cleanup_artifacts.py --check  # 只报告残留数（可作 CI 守卫）
"""
import os, sys, subprocess

# BUG-138（BUG-58 同族）：守卫的红必须是判据红。Windows 默认 cp936 控制台上打印中文结论里的
# ⇒ 等字符会让 print 当场 UnicodeEncodeError——拿到 traceback 而不是 verdict，而且崩在结论行之前
# 留下的 rc 会被读成「缺陷在场」（判据自己的崩不许冒用被测的退出码）。CI 在 Linux UTF-8 下是无损 no-op。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
KEEP = {"fist-mbt.db"}            # 唯一被 git 跟踪的交付数据库，绝不删
# fist-mbt.db 在 SQLite WAL 模式下的瞬时 sidecar，随下次打开必然重建，不算残留
KEEP_SIDECAR = {"fist-mbt.db-shm", "fist-mbt.db-wal"}
SUFFIXES = (".db", ".db-shm", ".db-wal")


def stray_root_dbs():
    """仓库根下应删的生成物（排除 KEEP）。返回相对路径列表。"""
    out = []
    for name in sorted(os.listdir(ROOT)):
        full = os.path.join(ROOT, name)
        if not os.path.isfile(full):
            continue
        if name in KEEP or name in KEEP_SIDECAR:
            continue
        if name.endswith(SUFFIXES):
            out.append(name)
    return out


def temp_files():
    """temp/ 下应清理的 scratch 生成物。返回相对路径列表。"""
    out = []
    tdir = os.path.join(ROOT, "temp")
    if not os.path.isdir(tdir):
        return out
    for name in sorted(os.listdir(tdir)):
        full = os.path.join(tdir, name)
        if os.path.isfile(full) or os.path.islink(full):
            out.append(os.path.join("temp", name))
    return out


# 临时脚本的扩展名（任务完即清策略的对象）
_TMP_SCRIPT_EXT = (".py", ".ps1", ".sh")


def is_git_tracked(relpath):
    """relpath 是否被 git 跟踪。跟踪=正式资产，cleanup 一律不动（BUG-334）。"""
    try:
        r = subprocess.run(
            ["git", "ls-files", "--error-unmatch", "--", relpath],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=ROOT,
        )
        return r.returncode == 0
    except OSError:
        return False


def stray_underscore_scripts():
    """scripts/ 下 `_` 前缀的**未跟踪**临时脚本（正式工具目录不应留）。返回绝对路径+相对名列表。

    BUG-334：git 跟踪的 `_` 脚本是正式资产（如 `scripts/_tool_registry.py` 工具注册单一真源，
    被 7 个守卫/生成器导入），移走即当场 ImportError 红一片。故此处只放行 untracked。
    """
    sdir = os.path.join(ROOT, "scripts")
    out = []
    if not os.path.isdir(sdir):
        return out
    for name in sorted(os.listdir(sdir)):
        full = os.path.join(sdir, name)
        if not (
            name.startswith("_")
            and os.path.isfile(full)
            and name.endswith(_TMP_SCRIPT_EXT)
        ):
            continue
        rel = os.path.join("scripts", name)
        if is_git_tracked(rel):
            continue
        out.append((full, rel))
    return out


def selftest():
    """BUG-334 回归锁（判据无法自证绝不报绿）：`_`前缀规则必须豁免 git 跟踪资产、仍抓真临时脚本。

    - S1 tracked 识别：`is_git_tracked("scripts/_tool_registry.py")` 必须为 True
      （该文件是 git 跟踪的工具注册单一真源，若 git 探测坏了则后续豁免全失效）。
    - S2 豁免生效：`stray_underscore_scripts()` 不得包含 `_tool_registry.py`。
    - S3 仍抓真临时脚本：新建一个 untracked `_` 脚本，必须出现在候选中（否则规则被豁免规则误杀）。
    """
    fails = []
    # S1
    if not is_git_tracked(os.path.join("scripts", "_tool_registry.py")):
        fails.append("S1: is_git_tracked('scripts/_tool_registry.py') 应为 True（git 探测失效）")
    # S2
    rels = [rel for _abs, rel in stray_underscore_scripts()]
    if os.path.join("scripts", "_tool_registry.py") in rels:
        fails.append("S2: _tool_registry.py 被误判为临时脚本（BUG-334 复现）")
    # S3
    tmp_name = "_cleanup_selftest_tmp.py"
    tmp_abs = os.path.join(ROOT, "scripts", tmp_name)
    created = False
    try:
        with open(tmp_abs, "w", encoding="utf-8") as fh:
            fh.write("# selftest probe\n")
        created = True
        rels2 = [rel for _abs, rel in stray_underscore_scripts()]
        if os.path.join("scripts", tmp_name) not in rels2:
            fails.append("S3: 真 `_` 临时脚本未被捕获（豁免规则误杀）")
    except OSError as e:
        fails.append(f"S3: 无法创建探针临时脚本：{e}")
    finally:
        if created:
            try:
                os.remove(tmp_abs)
            except OSError:
                pass
    if fails:
        print("SELFTEST FAIL: " + "; ".join(fails))
        return 1
    print("SELFTEST PASS: S1 tracked 识别 / S2 `_tool_registry.py` 豁免 / S3 真临时脚本仍被抓")
    return 0


def main():
    if "--selftest" in sys.argv[1:]:
        sys.exit(selftest())
    check_only = "--check" in sys.argv[1:]
    root_stray = stray_root_dbs()
    tfiles = temp_files()
    uscripts = stray_underscore_scripts()
    # 已跨到 temp/ 的临时脚本也算 temp 残留（一并清掉，幂等）
    for _abs, rel in uscripts:
        moved = os.path.join(ROOT, "temp", os.path.basename(rel))
        if moved not in tfiles:
            tfiles.append(moved)
    total = len(root_stray) + len(tfiles)
    if check_only:
        if total != 0 or uscripts:
            print(
                f"DIRTY: 仓库残留 {len(root_stray)} 个根 .db + {len(tfiles)} 个 temp/ 文件 "
                f"+ {len(uscripts)} 个 scripts/ `_` 临时脚本（共 {total + len(uscripts)}）"
            )
            sys.exit(1)
        print("CLEAN: 仓库根仅 fist-mbt.db，temp/ 无残留，scripts/ 无 `_` 临时脚本 — 整洁")
        return
    if total == 0 and not uscripts:
        print("CLEAN: 无需清理（仓库根仅 fist-mbt.db，temp/ 无残留，scripts/ 无临时脚本）")
        return
    removed = 0
    # 将 scripts/ 下 `_` 临时脚本移入 temp/（任务完即清，移走后正式工具目录干净）
    for abs_p, rel in uscripts:
        dst = os.path.join(ROOT, "temp", os.path.basename(rel))
        try:
            os.makedirs(os.path.join(ROOT, "temp"), exist_ok=True)
            os.replace(abs_p, dst)
            print(f"mv  {rel} → temp/")
            removed += 1
        except OSError as e:
            print(f"!! 移入失败 {rel}: {e}")
    # 移入后 temp/ 有了这些文件，走统一 temp 清理（若为临时脚本则一并删除）
    tfiles2 = temp_files()
    for rel in tfiles2:
        p = os.path.join(ROOT, rel)
        try:
            os.remove(p)
            print(f"rm  {rel}")
            removed += 1
        except OSError as e:
            print(f"!! 删除失败 {rel}: {e}")
    for name in root_stray:
        p = os.path.join(ROOT, name)
        try:
            os.remove(p)
            print(f"rm  {name}")
            removed += 1
        except OSError as e:
            print(f"!! 删除失败 {name}: {e}")
    # 清空 temp 目录保留目录本身（若存在且已空）
    tdir = os.path.join(ROOT, "temp")
    try:
        if os.path.isdir(tdir) and not os.listdir(tdir):
            os.rmdir(tdir)
            print("rmdir temp/")
    except OSError:
        pass
    print(f"清理完成：共移除 {removed} 个生成物（保留交付库 fist-mbt.db）")


if __name__ == "__main__":
    main()