#!/usr/bin/env bash
# scripts/migrate_mooncakes_modjson.sh — 把 `.mooncakes` 里被新版 moon 判过期的旧 `moon.mod.json` 就地迁到 `moon.mod`。
#
# 出处（2026-10-13 实测，非纸面推断）：moon 0.1.20261012+ 解析依赖图时对旧格式清单直接报
#   Error: Failed to resolve the module dependency graph
#     1: `moon.mod.json` at '<repo>/.mooncakes/Tigls/mb-getrandom' is no longer supported.
#        Run `moon fmt` to migrate to `moon.mod`.
# ⇒ release.yml run#6（tag v0.3.8 首发）build-js 红在 `Build JS target`、Release 零资产；
#   本机 moon 钉在 0.1.20260920（老版）复现不出来——与 BUG-112「本机装了全局 moon，快照复跑是绿的」同形。
#
# 为什么必须「循环」而不是一次性 find 全量迁移：依赖是**惰性解包**的——每次 build 只把当前
# 解析需要的包释放进 `.mooncakes`、并只报第一个过期件。WSL 隔离副本（moon 0.1.20261012，
# 与 CI 同版）实测收敛序列：iter1 `Tigls/mb-getrandom` → iter2 `mizchi/sqlite` → iter3 build rc=0
# （原件 temp/final5_direct.txt：old_json=0 new_toml=8）。一次性 find 覆盖不到还没解包的那些。
#
# 为什么在被点名的依赖目录里跑 `moon fmt` 而不是仓库根：仓库根 `moon fmt` **不递归** `.mooncakes`
# （实测残留照旧），还会顺手重写仓库自己的 .mbt 文件（mtime 变化，CI 里制造 diff 噪音）。
# 官方报错的语义就是「把**这个模块**的清单迁成新格式」——就地 fmt 实测产出 moon.mod 并删掉旧 json
# （warning 原文：Migrating to moon.mod at module root '…' , deprecated moon.mod.json is removed）。
#
# 纪律与 patches/sqlite-bug133/reapply.sh 同族：`.mooncakes/` 在 .gitignore 里、`moon update` 会
# 重生成 ⇒ 本步必须跟在 `moon update` 之后、`moon build` 之前跑。老版 moon（本地）第一轮 build
# 即 rc=0 ⇒ 天然 no-op，零回归。
#
# 用法：bash scripts/migrate_mooncakes_modjson.sh ["build 命令"，默认 "moon build --target js"]
# 退出码：0 = build 通过（迁完或本就不需要）；1 = 撞到非迁移错误 / 报错路径不存在 / 迭代耗尽。
set -u
MAX_ITER="${MAX_ITER:-12}"
BUILD_CMD="${1:-moon build --target js}"

i=0
while [ "$i" -lt "$MAX_ITER" ]; do
  i=$((i + 1))
  if out=$($BUILD_CMD 2>&1); then
    if [ "$i" -gt 1 ]; then
      echo "migrate: build 通过（第 $i 轮，共迁移 $((i - 1)) 处依赖清单）"
    else
      echo "migrate: 无需迁移（首轮 build 即过 ⇒ 本版 moon 接受现状或依赖已全部解包迁移）"
    fi
    exit 0
  fi
  path=$(printf '%s\n' "$out" | grep -oP "at '\K[^']+(?=' is no longer supported)" | head -n 1)
  if [ -z "${path:-}" ]; then
    echo "migrate: 第 $i 轮撞到**非迁移**错误，原样透传（绝不吞掉真错误）："
    printf '%s\n' "$out" | tail -n 15
    exit 1
  fi
  if [ ! -d "$path" ]; then
    echo "migrate: 报错里的路径不存在，迁移器失灵：$path"
    exit 1
  fi
  echo "migrate: 第 $i 轮就地迁移 $path"
  if ! (cd "$path" && moon fmt >/dev/null); then
    echo "migrate: 依赖目录内 moon fmt 失败：$path"
    exit 1
  fi
done
echo "migrate: $MAX_ITER 轮仍未收敛（每轮都冒出新过期件？）"
exit 1
