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
#       bash scripts/migrate_mooncakes_modjson.sh --selftest   # 用合成 build 命令验分流表自己会发红
# 退出码：0 = build 通过（迁完或本就不需要）；1 = 撞到非迁移错误 / 报错路径不存在 / 迭代耗尽。
#         --selftest 的 0/1 = 分流表是否每条对照都能发红/发绿（与本步能否迁移无关）。
set -u
MAX_ITER="${MAX_ITER:-12}"
BUILD_CMD="${1:-moon build --target js}"

# --selftest：分流表不能只在真撞错时才第一次被读到——那条兜底分支此前含反引号命令替换
# （`Error: [xxxx]` 在双引号里被 bash 当命令执行 ⇒ "line 64: Error:: command not found"
#  且指路正文被吃掉），而它恰恰是唯一会在 ICE/未知错时说话的分支。本自检用合成 build
# 命令逐条驱动分流表，验「该发红的发红、该指对路的指对路、任何一格都不许漏出 shell 自己的错」。
run_selftest() {
  local script_dir tmp fail=0 n=0
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  # 合成 build 命令：打印正文到 stderr（与 moon 一致）后按档退出
  mkfake() { printf '#!/usr/bin/env bash\ncat >&2 <<%%FAKE%%\n%s\n%%FAKE%%\nexit %s\n' "$1" "$2" > "$tmp/$3"; chmod +x "$tmp/$3"; }
  mkdir -p "$tmp/dep_exists"
  mkfake 'Oops, the compiler has encountered an unexpected situation.
This is a bug in the compiler.
Error: Sys_error("\\\\?: Invalid argument")' 1 f_ice
  mkfake 'Error: [4100]
at src/x.mbt:3:5: unexpected token' 1 f_srcerr
  mkfake "Error: Failed to solve package relationship
1: Cannot find import 'vicTop-cw/fist-mbt/src/ghost'" 1 f_import
  mkfake 'Error: [4021] unbound value foo' 1 f_mbti
  mkfake 'Build finished. time to parse 0.01s' 0 f_ok
  mkfake "Error: Failed to resolve the module dependency graph
2: \`moon.mod.json\` at '$tmp/dep_missing' is no longer supported. Run \`moon fmt\` to migrate to \`moon.pkg\`." 1 f_legacy_gone
  mkfake "Error: Failed to resolve the module dependency graph
2: \`moon.mod.json\` at '$tmp/dep_exists' is no longer supported." 1 f_legacy_here

  # 每格 = 名字|合成脚本|期望 rc|期望出现在输出里的指路 substring
  local cases=(
    "ICE 归工具链|f_ice|1|[编译器 ICE"
    "源码错归文件:行|f_srcerr|1|源码编译错误"
    "缺包归跟踪面|f_import|1|跟踪面缺包目录"
    "mbti 归声明面|f_mbti|1|接口面声明了但实现不存在"
    "首轮即过归无需迁移|f_ok|0|无需迁移"
    "旧清单+路径失灵|f_legacy_gone|1|路径不存在，迁移器失灵"
    "旧清单+就地迁移|f_legacy_here|1|就地迁移"
  )
  local entry name fake want_rc want_sub out rc
  for entry in "${cases[@]}"; do
    n=$((n + 1))
    IFS='|' read -r name fake want_rc want_sub <<< "$entry"
    out="$(MAX_ITER=2 bash "$script_dir" "bash $tmp/$fake" 2>&1)"
    rc=$?
    if [ "$rc" != "$want_rc" ]; then
      echo "selftest FAIL [$name] 退出码 $rc ≠ 期望 $want_rc"
      fail=$((fail + 1))
    elif ! printf '%s\n' "$out" | grep -qF "$want_sub"; then
      echo "selftest FAIL [$name] 输出缺指路 substring: $want_sub"
      fail=$((fail + 1))
    elif printf '%s\n' "$out" | grep -qE 'command not found|syntax error|unbound variable'; then
      echo "selftest FAIL [$name] 输出漏出 shell 自身错误（判据自己坏了）"
      fail=$((fail + 1))
    else
      echo "selftest ok  [$name]"
    fi
  done
  if [ "$n" -eq 0 ]; then
    echo "selftest FAIL: 一格对照都没跑 ⇒ 判据无法自证，绝不报绿"
    exit 2
  fi
  if [ "$fail" -ne 0 ]; then
    echo "SELFTEST FAILED: $fail/$n 格红"
    exit 1
  fi
  echo "SELFTEST OK: $n 格分流对照全绿（含 ICE 归工具链、兜底分支无命令替换残留）"
  exit 0
}

if [ "${1:-}" = "--selftest" ]; then
  run_selftest
fi

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
    # 根因分流（2026-10-13 加，连续三轮 CI 实证促成）：本步是"依赖图/编译"这条链上的**第一个
    # 会红的步**，于是多种彼此无关的坏状态都在这里现身，而 print 的 `Failed to calculate build plan`
    # 极易被读成"依赖迁移问题"。按错误文本分流指路，省得读的人走错方向：
    #   ① Cannot find import '<本地包>'      ⇒ 跟踪面缺包目录（跑 check_pkg_imports.py）
    #   ② Error: [4021/4032/4015/4024] …      ⇒ .mbti 声明了源里没有的符号（跑 check_mbti_sync.py）
    #   ③ is no longer supported              ⇒ 依赖清单旧格式（本脚本本该处理；走到这里说明 grep 失灵）
    #   ④ Oops/The compiler has encountered an unexpected situation ⇒ 编译器 ICE（工具链缺陷，改源码无用）
    #   ⑤ 其它 Error: [xxxx]                  ⇒ 源码编译错误（按文件:行 去修）
    echo "migrate: ── 根因分流（按错误文本指路，别把编译/跟踪面问题读成依赖迁移问题）──"
    if printf '%s\n' "$out" | grep -qE "Cannot find import '[^']+'"; then
      echo "migrate:   ⇒ [跟踪面缺包目录] 报错含 'Cannot find import <本地包>'：某个 moon.pkg import 了"
      echo "migrate:     跟踪面里不存在的包目录 ⇒ 跑 python scripts/check_pkg_imports.py 会点名是谁"
    elif printf '%s\n' "$out" | grep -qE "Error: \[(4021|4032|4015|4024)\]"; then
      echo "migrate:   ⇒ [接口面声明了但实现不存在] 报错含 unbound/not found 类错误码：某个"
      echo "migrate:     pkg.generated.mbti 声明了源里找不到的符号 ⇒ 跑 python scripts/check_mbti_sync.py"
      echo "migrate:     会点名是谁（若提示'已在工作树、只是没进跟踪面'，出路是 git add 并提交）"
    elif printf '%s\n' "$out" | grep -q "is no longer supported"; then
      echo "migrate:   ⇒ [依赖清单旧格式] 报错含 is no longer supported：本脚本的 grep 没抓到路径 ⇒ 看上面原文"
    elif printf '%s\n' "$out" | grep -qE "encountered an unexpected situation|This is a bug in the compiler"; then
      echo "migrate:   ⇒ [编译器 ICE／工具链缺陷] 原文里是编译器自己崩了（Oops + 'This is a bug in the compiler'），"
      echo "migrate:     不是本仓源码写错：照着 文件:行 去改源码只会改错东西。先对表 moon/moonc 版本与本仓钉版"
      echo "migrate:     （见 AGENTS.md「Tooling」与 moon.mod 依赖面），必要时换工具链版本复跑；"
      echo "migrate:     本步只能透传，绝不在迁移器里掩盖（对齐 BUG-142「退出码不可靠、判绿要看读数」）"
    else
      echo "migrate:   ⇒ [源码编译错误] 上面原文里 'Error: [xxxx]' 点的文件:行 就是根因，直接去修那一处"
    fi
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
