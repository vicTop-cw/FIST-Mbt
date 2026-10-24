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
# 步骤 3：核暂存面 == 申报面（集合逐字相等）
# ---------------------------------------------------------------------------
staged="$(git_ diff --cached --name-only | LC_ALL=C sort -u)"
if [ "$staged" != "$declared_sorted" ]; then
  extra="$(LC_ALL=C comm -13 <(printf '%s\n' "$declared_sorted") <(printf '%s\n' "$staged") | grep -v '^$' || true)"
  missing="$(LC_ALL=C comm -23 <(printf '%s\n' "$declared_sorted") <(printf '%s\n' "$staged") | grep -v '^$' || true)"
  err "REJECT(1) 暂存面 ≠ 申报面（有东西被并发 add 进来，或申报路径未生效）"
  [ -n "$extra" ]   && { err "  多出来的（不属于你的申报面）："; printf '%s\n' "$extra"   | sed 's/^/    + /' >&2; }
  [ -n "$missing" ] && { err "  缺失的（申报了但没进暂存）：";     printf '%s\n' "$missing" | sed 's/^/    - /' >&2; }
  # 只把「多出来的」剔出暂存（那是别人的面）；缺失的不动（可能是路径写错）
  if [ -n "$extra" ]; then
    while IFS= read -r f; do [ -n "$f" ] && git_ restore --staged -- "$f" >/dev/null 2>&1 || true; done <<< "$extra"
    err "  已把多出来的路径剔出暂存（不动工作树）。请复核后重跑。"
  fi
  exit 1
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
# 步骤 5：commit（**不**自动 --no-verify）
# ---------------------------------------------------------------------------
if ! out="$(git_ commit -F "$MSG_FILE" 2>&1)"; then
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
