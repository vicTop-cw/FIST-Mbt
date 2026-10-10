#!/usr/bin/env bash
# ============================================================================
# patches/sqlite-bug133/reapply.sh — 把 BUG-133 的 C stub 修复落到 `.mooncakes`
#
# 背景
# ----
# BUG-133 的根在 vendored 依赖 `mizchi/sqlite`（`.mooncakes/`，gitignored）的
# `stub.c`：C 侧把 `sqlite3*` / `sqlite3_stmt*` 裸指针直接当 MoonBit 对象回传，
# 另有 6 个函数把 `const char*` 直接声明成 `-> Bytes`（MoonBit 的 Bytes 要读长度
# 前缀，等于按随机长度读内存）。
# 修复版 stub.c 已存到 `patches/sqlite-bug133/stub.c`。
#
# 为什么不能只改 `.mooncakes`
# --------------------------
# `.mooncakes/` 在 `.gitignore` 里，`moon update` / `moon add` 会把它整个重生成，
# 直接改等于「改一次、失效一次」。本脚本把修复作为 repo 内资产，谁需要谁跑一次。
#
# 用法
# ----
#   bash patches/sqlite-bug133/reapply.sh            # 幂等；已是最新就不写
#   bash patches/sqlite-bug133/reapply.sh --force    # 无脑覆盖
#   bash patches/sqlite-bug133/reapply.sh --verify   # 只验「目标 == 修复版」，不写
#
# 退出码：0 = 目标已是修复版（或已成功覆写）；1 = 目标不存在或 --verify 发现不一致。
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

FIXED_STUB="$SCRIPT_DIR/stub.c"
TARGET_STUB="$REPO_ROOT/.mooncakes/mizchi/sqlite/stub.c"

MODE="apply"   # apply | force | verify

for arg in "$@"; do
  case "$arg" in
    --force)  MODE="force" ;;
    --verify) MODE="verify" ;;
    --help|-h)
      sed -n '1,10p' "$0" | head -1 >/dev/null
      echo "usage: $0 [--force|--verify]"; exit 0
      ;;
  esac
done

fail() { echo "::error::$1" >&2; exit 1; }

if [[ ! -f "$FIXED_STUB" ]]; then
  fail "找不到修复版 stub.c：$FIXED_STUB"
fi

if [[ ! -f "$TARGET_STUB" ]]; then
  fail "找不到目标 stub.c：$TARGET_STUB（先跑 moon update 让依赖落地）"
fi

# --verify 只校验、不写
if [[ "$MODE" == "verify" ]]; then
  if cmp -s "$FIXED_STUB" "$TARGET_STUB"; then
    echo "OK: 目标已是 BUG-133 修复版"
    exit 0
  else
    echo "MISMATCH: 目标不是修复版（需要跑 reapply.sh 落地）"
    exit 1
  fi
fi

# --force 或无脑写
if [[ "$MODE" == "force" ]] || ! cmp -s "$FIXED_STUB" "$TARGET_STUB"; then
  cp "$FIXED_STUB" "$TARGET_STUB"
  echo "已覆写 $TARGET_STUB（BUG-133 C stub 修复）"
else
  echo "目标已是修复版，跳过"
fi