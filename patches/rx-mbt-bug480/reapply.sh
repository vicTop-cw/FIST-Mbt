#!/usr/bin/env bash
# ============================================================================
# patches/rx-mbt-bug480/reapply.sh — 把 BUG-480 的 `Number(id)` 归一落在 vendored
#                                   `RX-MBT` 的 `monitor/watcher_js.mbt` 上
#
# 背景（Lane DN 2026-10-29）
# ------------------------
# BUG-480：`fs.watch` 句柄泄漏 + node 进程无法自然退出。
#
# 病灶在**上游依赖** `vicTop-cw/RX-MBT` 的 `monitor/watcher_js.mbt`：
#   `ffi_watch_stop` 用 `G.__rxmbt_watch_reg.get(id)` 取句柄，而
#     · `ffi_watch_start` 侧 key 是 `G.__rxmbt_watch_seq++` ⇒ **JS number**
#     · `ffi_watch_stop` 形参 `id : Int64` 进到 JS 是 **BigInt**
#   ⇒ `BigInt(0) !== 0` ⇒ `Map.get` **恒得 undefined** ⇒ `w.close()` **永不执行**
#   ⇒ fs.watch 句柄泄漏 ⇒ **node 进程无法自然退出**
#   （表现：`moon test` 挂住且**不打印 `Total tests:` 汇总行**）。
#
# 上游已修：`../rx-mbt`（本地仓，version = 0.4.0）的 `monitor/watcher_js.mbt:82`
# 已改成 `const key = Number(id); ... get(key)`，并有大段注释解释为什么。
#
# **为什么我们不直接升 0.4.0**
# ---------------------------
# 实测（本单第一步）：**registry 上没有 0.4.0** ——
#   `~/.moon/registry/index/.../RX-MBT` 里最高只有 `0.3.0`
#   （0.1.0 / 0.2.0 / 0.3.0 三条，无 0.4.0）。
# 把 `moon.mod` 改成 `@0.4.0` 后 `moon update` **不报错但也不生效**：
#   `.mooncakes/vicTop-cw/RX-MBT/moon.mod` 仍是 `version = "0.3.0"`，
#   `monitor/watcher_js.mbt` 里仍无 `Number(id)`。
# 本仓的 moon（0.1.20261016）**也不支持 path 依赖**（无 `moon dep` 子命令）。
#   ⇒ 三条路（升级 / 路径依赖 / 本地补丁）里，**只剩本地补丁**可行。
#
# 用法
# ----
#   bash patches/rx-mbt-bug480/reapply.sh            # 幂等；已是最新就不写
#   bash patches/rx-mbt-bug480/reapply.sh --force    # 无脑覆盖
#   bash patches/rx-mbt-bug480/reapply.sh --verify   # 只验不改（rc=1 表示未打）
#
# 退出码
# ------
#   0 = 已是最新（或本次已打好）     1 = 仍未打上 / 校验失败
#   3 = 环境不给量（依赖未解包，moon update 还没跑过）
#
# ⚠️ 这是**临时补丁**：等 0.4.0 上 registry 后**应删除本目录并把 moon.mod 升到 0.4.0**。
#    删除条件：`grep -c 'Number(id)' .mooncakes/vicTop-cw/RX-MBT/monitor/watcher_js.mbt`
#    **无需打补丁就 > 0**（即上游已带修复）。
# ============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TARGET="$ROOT/.mooncakes/vicTop-cw/RX-MBT/monitor/watcher_js.mbt"

FORCE=0
VERIFY=0
for a in "$@"; do
  case "$a" in
    --force) FORCE=1 ;;
    --verify) VERIFY=1 ;;
    -h|--help) sed -n '2,60p' "$0"; exit 0 ;;
    *) echo "未知参数: $a" >&2; exit 3 ;;
  esac
done

if [ ! -f "$TARGET" ]; then
  echo "[rx-mbt-bug480] 环境不给量：找不到 $TARGET"
  echo "  ⇒ 先跑一次 \`moon update\`（该路径是 vendored 依赖，gitignored）"
  exit 3
fi

# 判据：已打好 = 出现 `Number(id)` 归一
#
# ⚠️ **Lane DP 实测修正**：本段原先**无条件早退**，而 `--force` 虽被解析却从未使用
# ⇒ 在「文件已是修复态」时 `--force` 也直接 exit 0，**等于没有 --force**。
# 后果不是数据错误（幂等仍成立），而是**语义撒谎**：CI 里写 `--force` 会以为
# 「我在强制保证补丁在位」，实际只是「看到已修就跳过」。
# 更糟的是它掩盖了唯一能区分两种状态的机会：
#   · **上游已带修复**（0.4.0）⇒ 应报「可删补丁」
#   · **本地补丁已在位**（0.3.0 + 我们打的）
# 这两者 `grep Number(id)` 结果相同。⇒ 用**标记行**区分：打过补丁的文件必含
# `PATCHED-BY-BUG480` 注释；上游原生的不含。`--force` 时**继续往下走**（重打，幂等）。
PATCH_MARK='// PATCHED-BY-BUG480: key normalized to Number(id)'
# ⚠️ 判例-30（自指假绿）实测踩到：标记行**自己就含 `Number(id)`** ⇒
#    `grep -c Number(id)` 会被自己的标记命中 ⇒ 判据恒真。
#    必须**排除标记行**再数（`^// PATCHED-BY-BUG480` 行首锚定）。
count_code() { grep -v '^// PATCHED-BY-BUG480' "$TARGET" | grep -c 'Number(id)' || true; }
if [ "$(count_code)" != "0" ]; then
  if grep -qF "$PATCH_MARK" "$TARGET"; then
    if [ "$VERIFY" = "1" ]; then
      echo "[rx-mbt-bug480] OK 本地补丁已在位（含 $PATCH_MARK）"
      exit 0
    fi
    if [ "$FORCE" = "0" ]; then
      echo "[rx-mbt-bug480] OK 本地补丁已在位（幂等 no-op；要强制重打请加 --force）"
      exit 0
    fi
    echo "[rx-mbt-bug480] --force：补丁已在位，仍继续重打（幂等）"
  else
    echo "[rx-mbt-bug480] OK 上游**原生**已带修复（无本地补丁标记）"
    echo "  ⇒ **可以删除本补丁目录、删除 CI reapply 步，并把 moon.mod 升到 0.4.0**"
    exit 0
  fi
fi

if [ "$VERIFY" = "1" ]; then
  echo "[rx-mbt-bug480] FAIL 未打补丁：$TARGET 里没有 Number(id) 归一"
  exit 1
fi

# 幂等替换：把 `const w = G.__rxmbt_watch_reg.get(id)` 改成 Number 归一
#
# ⚠️ 只匹配**代码**里的那一句（`#|` 行内），不碰注释（判例-30）：
#    注释里也写着 `get(id)` 这个词，全文替换会改到注释 ⇒ 看起来变了、实际没变。
#
# ⚠️ **`--force` 重打必须先「反向还原」**（Lane DP 实测踩到）：
#    第一版 `--force` 直接往下走，但原始行**已被替换过** ⇒ `BEFORE=0`
#    ⇒ 报「找不到待替换的代码行」**rc=1** ⇒ **CI 会红**。
#    更隐蔽：第二次打会把 `delete(key)` 再套一层，`Number(id)` 计数变 2。
#    ⇒ 重打 = **先还原成上游原形，再打**（两个方向都幂等）。
REVERSED=0
if grep -qF "$PATCH_MARK" "$TARGET"; then
  # 已带标记 ⇒ 是本地补丁 ⇒ 先还原
  sed -i 's|const key = Number(id); const w = G\.__rxmbt_watch_reg\.get(key);|const w = G.__rxmbt_watch_reg.get(id);|' "$TARGET"
  sed -i 's|G\.__rxmbt_watch_reg\.delete(key);|G.__rxmbt_watch_reg.delete(id);|' "$TARGET"
  sed -i "/PATCHED-BY-BUG480/d" "$TARGET"
  REVERSED=1
fi

BEFORE=$(grep -c 'const w = G\.__rxmbt_watch_reg\.get(id);' "$TARGET" || true)
if [ "$BEFORE" = "0" ]; then
  echo "[rx-mbt-bug480] FAIL 找不到待替换的代码行（上游形状变了？）"
  echo "  ⇒ 人工核对 $TARGET 的 ffi_watch_stop"
  [ "$REVERSED" = "1" ] && echo "  （已尝试反向还原；若还原后仍无此行，说明上游改了实现）"
  exit 1
fi

cp "$TARGET" "$TARGET.bak480"
sed -i 's|const w = G\.__rxmbt_watch_reg\.get(id);|const key = Number(id); const w = G.__rxmbt_watch_reg.get(key);|' "$TARGET"
# delete 也要用归一后的 key（否则删不掉，reg 会一直涨）
sed -i 's|G\.__rxmbt_watch_reg\.delete(id);|G.__rxmbt_watch_reg.delete(key);|' "$TARGET"
# 打标记：用于区分「本地补丁在位」与「上游原生已修」（两者 grep Number(id) 结果相同）。
# 只在**没有**标记时才加（`--force` 重复跑不会叠多行）。
if ! grep -qF "$PATCH_MARK" "$TARGET"; then
  sed -i "1i ${PATCH_MARK}" "$TARGET"
fi

AFTER=$(count_code)
if [ "$AFTER" = "0" ]; then
  echo "[rx-mbt-bug480] FAIL 替换后仍无 Number(id)，回滚"
  mv "$TARGET.bak480" "$TARGET"
  exit 1
fi

rm -f "$TARGET.bak480"
echo "[rx-mbt-bug480] OK 已打上 Number(id) 归一（1 处 get + 1 处 delete）"
echo "  ⚠️ 临时补丁：0.4.0 上 registry 后请删除本目录"
exit 0
