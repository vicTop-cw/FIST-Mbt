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
  - --check 模式只报告残留数量（0 = 干净），不删任何文件。

用法：
  python scripts/cleanup_artifacts.py          # 清理 + 打印各文件
  python scripts/cleanup_artifacts.py --check  # 只报告残留数（可作 CI 守卫）
"""
import os, sys

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


def main():
    check_only = "--check" in sys.argv[1:]
    root_stray = stray_root_dbs()
    tfiles = temp_files()
    total = len(root_stray) + len(tfiles)
    if check_only:
        if total != 0:
            print(f"DIRTY: 仓库残留 {len(root_stray)} 个根 .db 生成物 + {len(tfiles)} 个 temp/ 文件（共 {total}）")
            sys.exit(1)
        print("CLEAN: 仓库根仅 fist-mbt.db，temp/ 无残留 — 生成物整洁")
        return
    if total == 0:
        print("CLEAN: 无需清理（仓库根仅 fist-mbt.db，temp/ 无残留）")
        return
    removed = 0
    for name in root_stray:
        p = os.path.join(ROOT, name)
        try:
            os.remove(p)
            print(f"rm  {name}")
            removed += 1
        except OSError as e:
            print(f"!! 删除失败 {name}: {e}")
    for rel in tfiles:
        p = os.path.join(ROOT, rel)
        try:
            os.remove(p)
            print(f"rm  {rel}")
            removed += 1
        except OSError as e:
            print(f"!! 删除失败 {rel}: {e}")
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