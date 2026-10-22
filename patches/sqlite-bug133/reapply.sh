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
# BUG-380（2026-10-22）：v0.3.10 把 native 后端从 `mizchi/sqlite` 换成
# `daqing/sqlite@0.4.0`（不透明外部类型 `type Sqlite3` + `#borrow`，133 那族缺陷
# 大概率不存在）。换后端后 `.mooncakes/mizchi/…/stub.c` **永远不会出现**，而旧版
# 本脚本在 TARGET 缺失时无条件硬失败 ⇒ CI native 双臂每跑必停在「Reapply」步，
# 把 owner 裁决③设的 `Native heap gate` 判据挡在门口——native 覆盖「断且沉默」。
# 本版加**后端分类**（与 fist-gate 的「环境态 vs 代码红」同纪律）：
#   确证 moon.mod 已不声明 mizchi/sqlite ⇒ 打 SKIP 并 exit 0，放行到 heap gate 真验；
#   仍声明 mizchi 却没解包（或读不到 moon.mod 无法判定）⇒ 维持硬失败，绝不掩盖真问题。
#
# 用法
# ----
#   bash patches/sqlite-bug133/reapply.sh            # 幂等；已是最新就不写
#   bash patches/sqlite-bug133/reapply.sh --force    # 无脑覆盖
#   bash patches/sqlite-bug133/reapply.sh --verify   # 只验「目标 == 修复版」，不写
#   bash patches/sqlite-bug133/reapply.sh --selftest # 合成树驱动后端分类四格
#
# 退出码：0 = 已是修复版 / 覆写成功 / 后端已换（SKIP，补丁不适用）；
#         1 = 仍依赖 mizchi 却没解包 / --verify 不一致 / 无法判定后端（保守失败）。
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

FIXED_STUB="$SCRIPT_DIR/stub.c"
TARGET_STUB="$REPO_ROOT/.mooncakes/mizchi/sqlite/stub.c"
MOON_MOD="$REPO_ROOT/moon.mod"

MODE="apply"   # apply | force | verify | selftest
SELFTEST_RUN=0

for arg in "$@"; do
  case "$arg" in
    --force)        MODE="force" ;;
    --verify)       MODE="verify" ;;
    --selftest)     MODE="selftest" ;;
    --selftest-run) SELFTEST_RUN=1 ;;
    --help|-h)
      echo "usage: $0 [--force|--verify|--selftest]"; exit 0
      ;;
  esac
done

fail() { echo "::error::$1" >&2; exit 1; }

# 后端判定：moon.mod 是否仍声明 mizchi/sqlite。
#   mizchi    → 仍需本补丁
#   switched  → 已换别的 sqlite 后端，补丁不适用
#   unknown   → 读不到 moon.mod，无法判定（保守：不得猜成"已换"而掩盖真·未解包）
backend_state() {
  if [[ ! -r "$MOON_MOD" ]]; then
    echo unknown
  elif grep -q "mizchi/sqlite" "$MOON_MOD"; then
    echo mizchi
  else
    echo switched
  fi
}

# TARGET stub 缺失时的分流。绝不把「后端已换」与「还没解包」混成一类红。
missing_target_verdict() {
  local state
  state="$(backend_state)"
  case "$state" in
    switched)
      echo "SKIP: $MOON_MOD 已不声明 mizchi/sqlite —— BUG-133 补丁对现后端不适用。"
      echo "      （native 覆盖的权威判据是 heap gate 探针 e2e_native_heap_probe.py，"
      echo "       它现在能真的跑起来了；daqing/sqlite 是否也崩由它说话，不在此自证。）"
      return 0 ;;
    mizchi)
      fail "找不到目标 stub.c：$TARGET_STUB
  ⇒ 依赖仍是 mizchi/sqlite 却尚未解包。注意：先跑 moon update 不够（2026-10-13 实测
    纠正：update 只刷新注册表索引，.mooncakes 是惰性解包，update 之后目录根本不存在）；
    请先跑一次能触发解包的构建，例如 \`moon check --target native\`。
    CI 顺序见 ci.yml / fist-ci.yml 的 native 臂：migrate → reapply → heap gate → check。" ;;
    *)
      fail "找不到目标 stub.c：$TARGET_STUB，且无法从 $MOON_MOD 判定后端（读不到/不可读）—— 保守判失败：不猜测为「已换」而跳过（那会掩盖真·未解包）。" ;;
  esac
}

# --selftest：合成树逐格驱动后端分类断言（rc + 关键句），任一不符整体 rc=1。
selftest() {
  local tmp rc=0
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  run_case() {
    local name="$1" want_rc="$2" want_grep="$3" root="$4"
    local out got_rc
    set +e
    out="$(REPO_ROOT_OVERRIDE="$root" bash "$SCRIPT_DIR/reapply.sh" --selftest-run 2>&1)"
    got_rc=$?
    set -e
    if [[ "$got_rc" != "$want_rc" ]]; then
      echo "  FAIL $name：rc=$got_rc 期望 $want_rc"
      echo "  ---- 输出 ----"; echo "$out"; echo "  ---------------"
      rc=1; return
    fi
    if [[ -n "$want_grep" ]] && ! printf '%s' "$out" | grep -q "$want_grep"; then
      echo "  FAIL $name：输出缺关键句「$want_grep」"
      echo "  ---- 输出 ----"; echo "$out"; echo "  ---------------"
      rc=1; return
    fi
    echo "  OK   $name (rc=$got_rc)"
  }

  # S1 后端已换（moon.mod 无 mizchi）+ 无 stub ⇒ SKIP rc=0
  mkdir -p "$tmp/s1/.mooncakes"
  printf 'dependencies = ["daqing/sqlite@0.4.0"]\n' > "$tmp/s1/moon.mod"
  # S2 仍 mizchi + 无 stub ⇒ 未解包硬失败 rc=1（旧语义保留，且提示仍是纠正后的版本）
  mkdir -p "$tmp/s2/.mooncakes"
  printf 'dependencies = ["mizchi/sqlite@0.3.1"]\n' > "$tmp/s2/moon.mod"
  # S3 读不到 moon.mod + 无 stub ⇒ 保守失败 rc=1（unknown ≠ switched）
  mkdir -p "$tmp/s3/.mooncakes"
  # S4 仍 mizchi + stub 已是修复版 ⇒ 无需覆写 rc=0（positive control：正常路径没被分类改动伤到）
  mkdir -p "$tmp/s4/.mooncakes/mizchi/sqlite"
  printf 'dependencies = ["mizchi/sqlite@0.3.1"]\n' > "$tmp/s4/moon.mod"
  cp "$FIXED_STUB" "$tmp/s4/.mooncakes/mizchi/sqlite/stub.c"

  echo "selftest（reapply 后端分类，四格 S1/S2/S3/S4）："
  run_case "S1 后端已换⇒SKIP"          0 "SKIP"     "$tmp/s1" || true
  run_case "S2 仍mizchi未解包⇒硬失败"   1 "尚未解包" "$tmp/s2" || true
  run_case "S3 读不到moon.mod⇒保守失败" 1 "无法从"   "$tmp/s3" || true
  run_case "S4 已是修复版⇒跳过"         0 "已是修复版" "$tmp/s4" || true

  if [[ "$rc" == 0 ]]; then
    echo "SELFTEST OK（四格全绿；S1=0 与 S2=1 的**差异**即分类在起作用的自证，无需额外变异格）"
  else
    echo "SELFTEST FAIL"
  fi
  return "$rc"
}

if [[ "$MODE" == "selftest" ]]; then
  selftest
  exit $?
fi

if [[ ! -f "$FIXED_STUB" ]]; then
  fail "找不到修复版 stub.c：$FIXED_STUB"
fi

# 自检单格驱动：只走真实判定路径，不碰仓库根。
if [[ "$SELFTEST_RUN" == "1" ]]; then
  if [[ ! -f "$TARGET_STUB" ]]; then
    missing_target_verdict
    exit 0
  fi
  if cmp -s "$FIXED_STUB" "$TARGET_STUB"; then
    echo "目标已是修复版，跳过"
    exit 0
  fi
  cp "$FIXED_STUB" "$TARGET_STUB"
  echo "已覆写 $TARGET_STUB（BUG-133 C stub 修复）[selftest-run]"
  exit 0
fi

if [[ ! -f "$TARGET_STUB" ]]; then
  # 2026-10-22（BUG-380）：先分流「后端已换 vs 尚未解包」，再决定 SKIP 或失败。
  missing_target_verdict
  exit 0
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
