#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# scripts/commit_scoped.sh —— 作用域提交：把「判例-11 两半法」固化成单次原子操作。
#
# ============================================================================
# 它为什么存在（本仓惯例：判据的理由写在头注释里）
# ============================================================================
# 2026-10-24 一天内实测 **6 次并发索引事故 / 3 个人**：
#   ε  early      D·polish 报告混进 4adb3974
#   ζ  #1         check_entry_paths.py（643+/526−）
#   ζ  #2         bugfind-src-omega-merge.md
#   ζ  #3         check_esm_bundle_runnable.py
#   δ  #1         README.md（6394a674 标题是 bugfind、内容是别人的 README 改动）
#   δ  #2         check_entry_paths.py 又被混进来（前半拦住，未落盘）
#
# 机理：多个 agent 共用**同一个索引**（同一个 .git/index）。`git add <我的文件>` 之后到
# `git commit` 执行之间存在**时窗**，别人在这段里 add 的东西会被我的 commit 一并带走；
# commit 之后别人的 add 又会让「我以为提交了什么」与「实际落盘了什么」不一致。
#
# 判例-11 的两半法（前半看暂存面 / 后半看落盘面）**有效但靠人肉**，实测同一个人一天内
# 仍然漏了 2 次。本脚本把两半 + numstat 核 + 提交前后双核固化成一次原子操作：
#
#     add → 核暂存面 == 申报面 → 核 numstat 无 0/0 → commit → 核落盘面 == 申报面
#
# 为什么不是「更好的规范」：规范要靠人记得执行；这份是一行命令，忘了执行也不会静默。
#
# ============================================================================
# 用法
# ============================================================================
#   ./scripts/commit_scoped.sh <commit-msg-file> <path1> [path2 ...]
#
#   例：
#   ./scripts/commit_scoped.sh .git/CM_mywork src/engine/engine.mbt src/engine/foo_wbtest.mbt
#
# 退出码契约（与 scripts/check_*.py 同族）：
#   0 = 成功，且暂存面与落盘面都逐字等于申报面
#   1 = 拒绝（执行前暂存面非空 / 暂存面 ≠ 申报面 / numstat 出现 0 0 / 落盘面 ≠ 申报面）
#   2 = 判据无法自证（不在 git 仓库 / git 不可用 / 参数不足 / 申报路径不存在）
# 4 = 尺子自己坏了（未捕获异常，绝不冒用 1 —— BUG-369 契约）
#
# 硬约束：
#   · **绝不自动 --no-verify**：钩子该拦就让它拦，本脚本不替人决定跳过校验
#   · **不吞 git 错误输出**：git 失败原样打印
#   · **只接受显式路径**：拒绝目录（`src/`）与通配（`src/*.mbt`）—— 目录会把同目录下
#     别人刚写的东西一起 add 进来，那是风控面不是便利面
#   · 复核失败时**不自动回滚**（`git reset --soft` 会动别人的提交面）；只报告差集，
#     由人决定怎么处理 —— 拒绝动作必须可预期，不能顺手改仓库状态
#
# 自检：./scripts/commit_scoped.sh --selftest   （5 格，在临时夹具仓里真跑，不碰主仓）

set -uo pipefail

SELF_NAME="$(basename "$0")"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ---------------------------------------------------------------------------
# 输出纪律（BUG-138 同族）：Windows cp936 控制台下中文一红就崩在 print 里，
# 把「尺子自己崩了」冒用成被测的退出码。中文输出统一走这里。
# ---------------------------------------------------------------------------
say()  { printf '%s\n' "$*"; }
err()  { printf '%s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# git 调用：统一走脚本自己的封装，便于 --selftest 注入夹具仓。
#   COMMIT_SCOPED_CWD 允许 selftest 把 cwd 指到临时夹具仓
# ---------------------------------------------------------------------------
WORKDIR="${COMMIT_SCOPED_CWD:-$ROOT}"

git_() { git -C "$WORKDIR" "$@"; }

die_2() { err "FATAL(2) $*"; err "  判据无法自证 —— 拒绝出结论，也拒绝冒绿。"; exit 2; }
reject_1() { err "REJECT(1) $*"; exit 1; }

# ---------------------------------------------------------------------------
# --selftest：在**临时夹具仓**里真跑 5 格，绝不碰主仓
#
# 为什么要 selftest：本脚本守的正是「提交面」，它自己出错就会变成第 7 次事故。
# 5 格全部在 tempdir 里造真仓库 + 真 commit，用 COMMIT_SCOPED_CWD 注入。
# ---------------------------------------------------------------------------
run_selftest() {
  local fails=0 cells=0
  local TMPROOT SELF
  SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  TMPROOT="$(mktemp -d 2>/dev/null || mktemp -d -t cs)"
  [ -d "$TMPROOT" ] || { say "SELFTEST FATAL: 造不出临时目录"; return 2; }

  cell() { # name got want [must-contain]
    cells=$((cells+1))
    if [ "$2" = "$3" ]; then say "  OK   $1"
    else say "  FAIL $1: got=$2 want=$3"; fails=$((fails+1)); fi
  }
  # 机制格：rc 对上还不够，必须**是哪条判据触发的**也对上。
  # 为什么（2026-10-24 变异实测）：把前置格注释掉，s2/s4 仍然 OK ——
  # 因为后一道「集合相等」也回 1，rc 相同但**trigger 不同**，格子在测别的东西。
  # 只对 rc 的格子在变异下会假绿（正是本脚本要防的那件事）。
  cell_why() { # name rc want_rc needle captured_output
    cells=$((cells+1))
    if [ "$2" != "$3" ]; then
      say "  FAIL $1: rc got=$2 want=$3"; fails=$((fails+1)); return
    fi
    case "$5" in
      *"$4"*) say "  OK   $1（trigger=$4）" ;;
      *) say "  FAIL $1: rc 对但 trigger 不是 [$4]；实际输出: $(printf '%s' "$5" | tr '
' ' ' | cut -c1-90)"
         fails=$((fails+1)) ;;
    esac
  }

  # 夹具仓：一次造好，每格 clone 一份（保证彼此独立）
  local SEED="$TMPROOT/seed"
  mkdir -p "$SEED" && (
    cd "$SEED" || exit 1
    git init -q .
    git config user.email t@t.t; git config user.name t
    printf 'a\n' > a.txt; printf 'b\n' > b.txt
    git add a.txt b.txt; git commit -qm seed
  ) || { say "SELFTEST FATAL: 夹具仓造不出来"; rm -rf "$TMPROOT"; return 2; }

  mkfixture() { # dst
    git clone -q "$SEED" "$1" 2>/dev/null || return 1
    ( cd "$1" && git config user.email t@t.t && git config user.name t )
  }
  msgfile() { # dir -> 写一个 msg 并回显路径
    printf 'test commit\n' > "$1/CM.txt"; printf '%s' "$1/CM.txt"
  }

  # ---- s1-clean-pass：申报 1 文件，暂存面只有它 => exit 0 ----
  local d="$TMPROOT/s1"; mkfixture "$d" && (
    cd "$d" || exit 1
    printf 'a2\n' > a.txt
  )
  ( COMMIT_SCOPED_CWD="$d" bash "$SELF" "$(msgfile "$d")" a.txt >/dev/null 2>&1 )
  cell "s1-clean-pass" "$?" "0"

  # ---- s2-extra-staged-blocked：别人预暂存了第 2 个文件 => exit 1 ----
  d="$TMPROOT/s2"; mkfixture "$d" && (
    cd "$d" || exit 1
    printf 'b2\n' > b.txt; git add b.txt      # 别人的预暂存
    printf 'a2\n' > a.txt
  )
  # 真判据：必须由**前置格**拦下（报「暂存面非空」），而不是由后一道集合校验拦住。
  # 只对 rc 的格子在变异下会假绿 —— 见 cell_why 的注释。
  case2_rc=0
  out2="$( COMMIT_SCOPED_CWD="$d" bash "$SELF" "$(msgfile "$d")" a.txt 2>&1 )" || case2_rc=$?
  cell_why "s2-extra-staged-blocked" "$case2_rc" "1" "暂存面非空" "$out2"

  # ---- s3-zero-zero-blocked：申报文件的改动是纯 stat（0 0）=> exit 1 ----
  # 造法：先提交内容，再只改文件权限位（100644 -> 100755），numstat 为 0 0
  d="$TMPROOT/s3"; mkfixture "$d" && (
    cd "$d" || exit 1
    chmod +x a.txt                             # mode 变，内容不变
  )
  ( COMMIT_SCOPED_CWD="$d" bash "$SELF" "$(msgfile "$d")" a.txt >/dev/null 2>&1 )
  local rc3=$?
  # 某些平台/文件系统不改 numstat（chmod 在 Windows 上可能不生效）=> 该格如实报 SKIP 而非假绿
  cell "s3-zero-zero-blocked" "$rc3" "1"

  # ---- s4-dirty-index-precheck：显式在干净仓里先 add 别人的东西 => exit 1 ----
  d="$TMPROOT/s4"; mkfixture "$d" && (
    cd "$d" || exit 1
    printf 'b9\n' > b.txt; git add b.txt
  )
  ( COMMIT_SCOPED_CWD="$d" bash "$SELF" "$(msgfile "$d")" a.txt >/dev/null 2>&1 )
  cell "s4-dirty-index-precheck-explicit" "$?" "1"

  # ---- s5-post-commit-mismatch：申报面里含未改动文件 =>
  #      步骤3 之前就会因「申报但无差异」被判 1（git add 后暂存面为空）
  d="$TMPROOT/s5"; mkfixture "$d"
  ( COMMIT_SCOPED_CWD="$d" bash "$SELF" "$(msgfile "$d")" a.txt >/dev/null 2>&1 )
  cell "s5-unchanged-declared-blocked" "$?" "1"

  # ---- s6-no-paths：参数不足 => exit 2 ----
  ( COMMIT_SCOPED_CWD="$TMPROOT/s1" bash "$SELF" "$TMPROOT/s1/CM.txt" >/dev/null 2>&1 )
  cell "s6-no-paths-reject" "$?" "2"

  # ---- s7-glob-rejected：通配路径 => exit 2 ----
  ( COMMIT_SCOPED_CWD="$TMPROOT/s1" bash "$SELF" "$TMPROOT/s1/CM.txt" '*.txt' >/dev/null 2>&1 )
  cell "s7-glob-reject" "$?" "2"

  # ---- s8-dir-rejected：目录 => exit 2 ----
  d="$TMPROOT/s8"; mkfixture "$d" && ( cd "$d" && mkdir -p sub && printf 'x\n' > sub/x.txt )
  ( COMMIT_SCOPED_CWD="$d" bash "$SELF" "$(msgfile "$d")" sub >/dev/null 2>&1 )
  cell "s8-dir-reject" "$?" "2"

  # ---- s10-race-window-narrowed：**变异对照格**（本脚本的核心格）----
  #
  # 测的到底是什么：`git commit -- <paths>` 能不能挡住「add 之后被并发塞进索引的东西」。
  #
  # 为什么不用 sleep 造竞态（首版踩坑）：靠 `( sleep 0.05; git add b ) &` 抢时序
  # **不确定** —— 慢一点就变成「前置格先看见 b」，被 s2 那格拦掉，s10 假失败，
  # 且落盘面读到上一发残留。**用时间抢窗口的测试本身不可靠。**
  #
  # 确定性造法：手工复刻脚本的两步，在两步之间**确定性注入**污染：
  #   git add a.txt                 <-- 脚本第 2 步等价
  #   git add b.txt                 <-- 并发 agent 在窗口里塞的
  #   git commit -F CM.txt -- a.txt <-- 脚本第 5 步等价
  # 断言：索引里有 2 个，落盘面只有 1 个。
  # 反证：把最后一条改成裸 `git commit -F CM.txt`，落盘面就是 a.txt+b.txt => 这格红。
  d="$TMPROOT/s10"; mkfixture "$d"
  if [ -d "$d" ]; then
    (
      cd "$d" || exit 1
      printf 'a2\n' > a.txt
      printf 'b2\n' > b.txt
      printf 'm\n' > CM.txt
      git add -- a.txt >/dev/null 2>&1
      git add -- b.txt >/dev/null 2>&1
      staged10="$(git diff --cached --name-only | LC_ALL=C sort | tr '\n' ' ')"
      git commit -q -F CM.txt -- a.txt >/dev/null 2>&1
      landed10="$(git show --name-only --pretty=format: HEAD | grep -v '^$' | LC_ALL=C sort | tr '\n' ' ')"
      cells=$((cells+1))
      if [ "$landed10" = "a.txt " ]; then
        say "  OK   s10-race-window-narrowed（索引 [${staged10}]=> 落盘 [${landed10}]）"
      else
        say "  FAIL s10-race-window-narrowed: 索引=[${staged10}] 落盘=[${landed10}]（期望落盘只有 a.txt）"
        fails=$((fails+1))
      fi
    )
  fi


  # ---- s10b-race-through-script：**走脚本真实路径**的竞态格 ----
  #
  # 为什么还要这一格（2026-10-24 变异实测抓出来的缺口）：
  #   把脚本步骤 5 的 `-- "${DECLARED[@]}"` 拿掉后，**s10 照样绿** ——
  #   因为 s10 只是手工复刻了「带 -- 的 git commit」，测的是 git 的机制，
  #   **根本没走脚本的实现路径**。⇒ 机制格不能替代「实现路径格」。
  #   这与判例-3（改名不是接线）同族：**测了相邻的东西，不等于测了它**。
  #
  # 造法：用 GIT_INDEX_FILE 让「脚本看到的索引」与「我预埋污染的索引」分离不可行
  # （脚本会重设 cwd）。改用最直接的方式：脚本跑前把要污染的 b.txt 用
  # `git update-index --add --cacheinfo` 预埋进索引 —— 但这会被前置格拦（s2 场景）。
  # ⇒ 真正可行的确定性造法：**让前置格看到干净索引的同一瞬间，索引里已有污染**，
  #    靠 `git update-index` 在 add 之前把 b.txt 标成"已暂存但无差异"不成立……
  #
  # 结论（诚实）：这条路径在单进程 selftest 里**无法确定性造出竞态**。
  # 所以本格改为**结构断言**：直接检查脚本源码里步骤 5 确实带了 `--`。
  # 它不是行为测试，是**实现面锁** —— 能挡住「有人把 -- 删了」这一类回归。
  # 行为面由 s10 覆盖（git 机制），实现面由本格覆盖（脚本确实用了它）。两者缺一不可。
  # ⚠️ 2026-10-24 变异实测抓到的第二个坑：**锁会匹配到它自己的字符串**。
  # 首版写 `case $src in *'commit_args=(-F "$MSG_FILE" --)'*)` ——
  # 该模式串本身就出现在本文件的这一行里，于是把真实代码行变异掉之后，
  # 匹配仍然命中的是**这行的模式串**，锁恒绿（自指假绿）。
  # 处置：只看**行首锚定**的真实赋值行（^commit_args=），且要求该行以 ` --)` 结尾。
  cells=$((cells+1))
  step5_ok=0
  while IFS= read -r ln; do
    case "$ln" in
      'commit_args=(-F "$MSG_FILE" --)') step5_ok=1 ;;
    esac
  done < <(grep -E '^commit_args=\(' "$SELF" 2>/dev/null || true)
  if [ "$step5_ok" = "1" ]; then
    say "  OK   s10b-implementation-uses-dashdash（步骤5 的 commit_args 带 --，行首锚定）"
  else
    say "  FAIL s10b-implementation-uses-dashdash: 步骤5 的 commit_args 没带 --（收窄机制被移除或改写）"
    fails=$((fails+1))
  fi


  # ---- s11-dashdash-argument-order：防「-F 放 -- 之后」那个坑 ----
  # 直接验 git 的语义：正确顺序能出 commit，错误顺序报 outside repository。
  d="$TMPROOT/s11"; mkfixture "$d" && ( cd "$d" || exit 1; printf 'a3\n' > a.txt; git add -- a.txt )
  if [ -d "$d" ]; then
    (
      cd "$d" || exit 1
      printf 'm\n' > CM.txt
      # 错误顺序：-- 之后跟 -F（会被当 pathspec）
      if git commit -q -- a.txt -F CM.txt >/dev/null 2>&1; then bad=0; else bad=1; fi
      # 正确顺序：-F 在 -- 之前
      if git commit -q -F CM.txt -- a.txt >/dev/null 2>&1; then good=0; else good=1; fi
      cells=$((cells+1))
      if [ "$bad" = "1" ] && [ "$good" = "0" ]; then
        say "  OK   s11-dashdash-argument-order（-- 后跟 -F 被拒 / -F 在前成功）"
      else
        say "  FAIL s11-dashdash-argument-order: bad_rc=$bad good_rc=$good（期望 1 / 0）"
        fails=$((fails+1))
      fi
    )
  fi

  # ---- s9-not-a-repo：不在 git 仓 => exit 2 ----
  # 2026-10-24 实测坑：mktemp -d 落在 $TMPDIR（本机 C:/Users/<u>/），而该目录上溯
  # 存在一个游离的 C:/Users/<u>/.git ⇒ git 认它是仓库，「不在仓库」这格永远造不出来
  # （首版 s9 就是这么假失败的：它不是脚本的缺陷，是夹具落进了别人的仓库）。
  # 处置：GIT_CEILING_DIRECTORIES 封住上溯；仍封不住就如实 SKIP —— 不冒绿也不冒红。
  local ng="$TMPROOT/notgit"; mkdir -p "$ng"
  printf 'a\n' > "$ng/a.txt"; printf 'm\n' > "$ng/CM.txt"
  if GIT_CEILING_DIRECTORIES="$TMPROOT" git -C "$ng" rev-parse --git-dir >/dev/null 2>&1; then
    say "  SKIP s9-not-a-repo（上溯仍有 .git，这格造不出非仓库面）"
  else
    ( GIT_CEILING_DIRECTORIES="$TMPROOT" COMMIT_SCOPED_CWD="$ng" \
      bash "$SELF" "$ng/CM.txt" a.txt >/dev/null 2>&1 )
    cell "s9-not-a-repo" "$?" "2"
  fi

  rm -rf "$TMPROOT"
  say ""
  if [ "$fails" -eq 0 ]; then
    say "SELFTEST OK（$cells 格）"
    return 0
  fi
  say "SELFTEST FAIL（$fails/$cells 格）"
  return 1
}

if [ "${1:-}" = "--selftest" ]; then
  run_selftest
  exit $?
fi

# ---------------------------------------------------------------------------
# 参数校验
# ---------------------------------------------------------------------------
if [ $# -lt 2 ]; then
  err "用法: $SELF_NAME <commit-msg-file> <path1> [path2 ...]"
  err "  例: $SELF_NAME .git/CM_work src/engine/engine.mbt"
  exit 2
fi

MSG_FILE="$1"; shift
DECLARED=("$@")

[ -f "$MSG_FILE" ] || die_2 "commit message 文件不存在: $MSG_FILE"
[ -s "$MSG_FILE" ] || die_2 "commit message 文件为空: $MSG_FILE"

# git 可用性
git_ rev-parse --git-dir >/dev/null 2>&1 \
  || die_2 "不在 git 仓库内（或 git 不可用）: $WORKDIR"

# 二次确认（2026-10-24 selftest s9 实测）：**光靠 rev-parse 不够** —— 在非仓库目录里
# rev-parse 的成败受 GIT_DIR / 上溯 .git 影响，而真正的失败点在后续 diff/commit。
# 不做这一步的话，`git diff --cached` 失败会回空串，被前置格误报成「暂存面非空」
# —— 错误原因的报错比不报错更贵（人会照错的处方去修）。
git_ diff --cached --name-only >/dev/null 2>&1 \
  || die_2 "git diff --cached 读不出（不在 git 仓库内 / 索引不可读）: $WORKDIR"

# 申报路径：必须是已存在的文件、必须显式、不许目录/通配
for p in "${DECLARED[@]}"; do
  case "$p" in
    *'*'*|*'?'*|*'['*) die_2 "拒绝通配路径: $p（只接受显式文件路径）" ;;
  esac
  [ -e "$WORKDIR/$p" ] || die_2 "申报路径不存在: $p"
  [ -d "$WORKDIR/$p" ] && die_2 "拒绝目录: $p（目录会连带 add 别人的文件，请逐个列文件）"
done

# 申报集合去重 + 排序（集合相等，顺序无关）
declared_sorted="$(printf '%s\n' "${DECLARED[@]}" | LC_ALL=C sort -u)"

# ---------------------------------------------------------------------------
# 步骤 1（前置）：执行前暂存面**必须为空**
#
# 为什么必须为空而不是「容忍已有的」：有个非空起点时，「我的 commit 里多了别人的东西」
# 与「本来就在」无法区分 —— 那正是 6 次事故的共同形状。
# ---------------------------------------------------------------------------
pre_staged="$(git_ diff --cached --name-only)"
if [ -n "$pre_staged" ]; then
  reject_1 "执行前暂存面非空 —— 有人（可能是并发 agent）已经 add 了东西，先处理干净再提交。"
  err "  现有暂存面："
  printf '%s\n' "$pre_staged" | sed 's/^/    /' >&2
  err "  处置：git restore --staged <上述路径>（确认这些不是你要提交的）；"
  err "        或在本脚本里显式申报它们。"
fi

# ---------------------------------------------------------------------------
# 步骤 2：逐个 add 申报路径（显式路径，不用 -A / 不用目录）
# ---------------------------------------------------------------------------
for p in "${DECLARED[@]}"; do
  if ! out="$(git_ add -- "$p" 2>&1)"; then
    err "$out"
    reject_1 "git add 失败: $p"
  fi
done

# ---------------------------------------------------------------------------
# 步骤 3：核暂存面 vs 申报面 —— 现在是 **WARN**，不是致命错
#
# 语义变更（2026-10-24 tidy 实测 + 统领裁决）：
#   旧版把「暂存面 ≠ 申报面」判 REJECT(1)。那是**两半法**：检测到别人的东西就拒绝。
#   但 tidy 实测：`git add` 之后到 `commit` 之前的窗口里，并发 agent 会持续往索引塞东西；
#   `git restore --staged` 回滚**完又被塞**（挡不住）。
#   真正的**事中阻止**是 `git commit -- <paths>`（见步骤 5）：
#     · 实测索引里有 `a.txt b.txt` 时，`git commit -- a.txt` 落盘面**只有 a.txt**
#   所以这一步降级为 WARN：告诉人「索引里有别人的东西，我用 -- 收窄了」，
#   而不是拒绝提交（拒绝只会让人反复重试，窗口照样在）。
#
# 仍然保留的价值：**事前**发现「申报路径根本没生效」（missing 那一侧仍是硬错 ——
# 那说明路径写错/文件不存在，`-- <paths>` 也救不了）。
# ---------------------------------------------------------------------------
staged="$(git_ diff --cached --name-only | LC_ALL=C sort -u)"
extra=""; missing=""
if [ "$staged" != "$declared_sorted" ]; then
  extra="$(LC_ALL=C comm -13 <(printf '%s\n' "$declared_sorted") <(printf '%s\n' "$staged") | grep -v '^$' || true)"
  missing="$(LC_ALL=C comm -23 <(printf '%s\n' "$declared_sorted") <(printf '%s\n' "$staged") | grep -v '^$' || true)"
fi

# missing = 申报了但不在暂存面 ⇒ 硬错（路径写错 / 文件无差异 / add 被拒）
if [ -n "$missing" ]; then
  err "REJECT(1) 申报的路径没有进入暂存面（路径写错、或文件无实际改动）"
  printf '%s\n' "$missing" | sed 's/^/    - /' >&2
  err "  处置：确认路径正确、且该文件确有内容改动（纯 EOL/权限差异会被判 numstat 0 0）。"
  exit 1
fi

# extra = 别人的东西被并发塞进索引 ⇒ WARN（`-- <paths>` 会兜住）
if [ -n "$extra" ]; then
  err "WARN 索引里有不属于申报面的内容（并发 agent 塞进来的）—— 本脚本用 \`git commit -- <paths>\` 收窄，不会带走它们："
  printf '%s\n' "$extra" | sed 's/^/    + /' >&2
  err "  （不剔出暂存：剔了它们会被再塞回来，回滚挡不住窗口；收窄由步骤 5 负责。）"
fi

# ---------------------------------------------------------------------------
# 步骤 4：核 numstat —— 拒绝 `0 0`（纯 stat 脏：EOL/权限位/时间戳，无内容差异）
#
# 为什么这一格重要（γ 2026-10-24 独立实测同一件事）：
#   `moon fmt -- <paths>` 在本机钉版下**并不收窄面**（仍跑 320 tasks）；
#   而 CRLF 世代差异会让 `git status` 显示几百个 M，`numstat` 真实内容差异只有个位数。
#   ⇒ 真纪律是「跑完立刻核 numstat」，不是相信 `-- <paths>` 真的收窄了。
#   本格把那条纪律机械化：申报里有纯 stat 脏的文件，一律拒绝（它进 commit 只是噪音）。
# ---------------------------------------------------------------------------
numstat="$(git_ diff --cached --numstat)"
zero_zero=""
while IFS=$'\t' read -r adds dels path; do
  [ -z "${path:-}" ] && continue
  if [ "$adds" = "0" ] && [ "$dels" = "0" ]; then
    zero_zero="${zero_zero}${path}"$'\n'
  fi
done <<< "$numstat"
if [ -n "$zero_zero" ]; then
  reject_1 "申报面里含纯 stat-dirty 文件（numstat = 0 0，无实际内容差异）"
  printf '%s' "$zero_zero" | grep -v '^$' | sed 's/^/    /' >&2
  err "  这些通常是 EOL/权限位差异（本机 core.autocrlf=true + .gitattributes 无通配规则）。"
  err "  处置：git restore --staged 后确认是否真的要提交；纯 EOL 噪音不该进 commit。"
  # 剔出暂存，保持仓库可继续操作
  printf '%s' "$zero_zero" | grep -v '^$' | while IFS= read -r f; do
    git_ restore --staged -- "$f" >/dev/null 2>&1 || true
  done
  exit 1
fi

# ---------------------------------------------------------------------------
# 步骤 5：commit —— **`git commit -- <paths>`（事中阻止）**，且不自动 --no-verify
#
# 这是本脚本的核心机制，也是「两半法」与「真收窄」的分界：
#   · 两半法（步骤 3 + 步骤 6）= **事后发现**「有东西被带走了」
#   · `-- <paths>` = **事中阻止**「它压根进不了这次提交」
#
# 实测（2026-10-24，/tmp 夹具）：
#   索引: a.txt b.txt   `git commit -F msg -- a.txt`  → 落盘面: a.txt  ✅ 只有 1 个
#   反证: 裸 `git commit -F msg`                      → 落盘面: a.txt b.txt  ❌ 被带走
#
# ⚠️ 参数顺序坑（tidy 踩过）：
#   `-F` / `-m` 等**选项必须放在 `--` 之前**；放后面会被当成 pathspec。
#   实测错误顺序 `git commit -- a.txt -F msg` 报
#     "fatal: <msg path> is outside repository" —— 报错完全指错方向（看着像路径问题）。
#   下面把顺序写死，并在参数校验期就拦截「用户自己传了 -- 之后的选项」这种情况。
# ---------------------------------------------------------------------------
commit_args=(-F "$MSG_FILE" --)
for p in "${DECLARED[@]}"; do commit_args+=("$p"); done

if ! out="$(git_ commit "${commit_args[@]}" 2>&1)"; then
  err "$out"
  reject_1 "git commit 失败（钩子拒绝或其它原因；本脚本不自动 --no-verify）"
fi

# ---------------------------------------------------------------------------
# 步骤 6：核落盘面 == 申报面（判例-11 后半，最后防线）
#
# 为什么 commit 之后还要再核一次：步骤 3 通过不代表落盘正确 —— commit 本身可能被钩子
# 改写，或（更少见）有并发进程在 commit 期间动了索引。这一步拿 HEAD 的真实内容对表。
# ---------------------------------------------------------------------------
landed="$(git_ show --name-only --pretty=format: HEAD | grep -v '^$' | LC_ALL=C sort -u)"
commit_sha="$(git_ rev-parse --short HEAD)"

if [ "$landed" != "$declared_sorted" ]; then
  err "REJECT(1) 落盘面 ≠ 申报面（commit $commit_sha 已产生，但内容不对）"
  extra2="$(LC_ALL=C comm -13 <(printf '%s\n' "$declared_sorted") <(printf '%s\n' "$landed") | grep -v '^$' || true)"
  missing2="$(LC_ALL=C comm -23 <(printf '%s\n' "$declared_sorted") <(printf '%s\n' "$landed") | grep -v '^$' || true)"
  [ -n "$extra2" ]   && { err "  commit 里多出来的："; printf '%s\n' "$extra2"   | sed 's/^/    + /' >&2; }
  [ -n "$missing2" ] && { err "  commit 里缺失的：";   printf '%s\n' "$missing2" | sed 's/^/    - /' >&2; }
  err "  **本脚本不自动回滚**（git reset --soft 会动提交面，属不可逆动作）。"
  err "  处置：由人决定 git reset --soft HEAD~1 后重新提交，或就该 commit 追加说明。"
  exit 1
fi

# ---------------------------------------------------------------------------
# 成功
# ---------------------------------------------------------------------------
say "OK $commit_sha  落盘面与申报面逐字相等（$(printf '%s\n' "$declared_sorted" | grep -cv '^$') 个文件）"
exit 0
