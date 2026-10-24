#!/usr/bin/env bash
# .github/workflows/sync-from-gitcode.simulate.sh
#
# 为什么存在：GitHub Actions 跑不了，但「失败读数有没有真出来」必须有**真跑**的证据，
# 不能靠读 YAML 自述。本脚本把 workflow 里 `run: |` 的 bash **原样抽出**原地跑：
#   · cwd 在临时目录里（不碰真仓，`git_env.isolated_git_env` 口径：剥 GIT_DIR 一族）
#   · 远端 `gh` = 本机 `git init --bare` 出来的假远端
#   · 唯一替换：Actions 表达式 `${{ … }}`（本机 bash 会报 bad substitution）⇒ SIM_ACTIONS_EXPR，
#     逐行打印出来，让「改写了几行」成为可见事实
#
# 三个用例：
#   ① 现行段在「3 支可推 + 1 支必失败」夹具上（4 支推、1 支被非快进拒）⇒ OK=3 FAIL=1 + 点名
#   ② 远端整体只读 ⇒ 全失败面 ⇒ 必须 OK=0 FAIL=3 + 三支全点名 + master 失败逐字点名
#   ③ 反证：旧写法 `git push ... || echo` 在同一夹具上**必须假绿**（rc=0 且无聚合读数）
#      —— 尺子先证明自己会红：夹具若照不出旧缺陷，前面两格的绿不算数。
#
# 用法：bash .github/workflows/sync-from-gitcode.simulate.sh
# 退出码：0=全格符合期望 / 1=有格越期望 / 2=判据无法自证（抽不到段、夹具造不出来）
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
WF="$HERE/sync-from-gitcode.yml"

# ── 抽段：只取含 `cd /tmp/repo` 的那一个 run: | 正文（= sync 段，不是 flag 检查段）──────
SEG_RAW=$(python - "$WF" <<'PY'
import io, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # Windows cp936 控制台会炸在中文/⇒ 上
lines = io.open(sys.argv[1], encoding="utf-8").read().splitlines()
blocks = []
for i, ln in enumerate(lines):
    if ln.strip() != "run: |":
        continue
    body = []
    for x in lines[i + 1:]:
        if x.strip() == "":
            body.append("")
            continue
        if not x.startswith("          "):
            break
        body.append(x[10:])
    blocks.append(body)
hits = [b for b in blocks if any("cd /tmp/repo" in x for x in b)]
if len(hits) != 1:
    sys.exit("expected exactly one sync run block, got %d" % len(hits))
sys.stdout.write("\n".join(hits[0]))
PY
) || { echo "FATAL 抽不到 sync 段"; exit 2; }
[ -n "$SEG_RAW" ] || { echo "FATAL 抽出来是空的"; exit 2; }
for pat in 'for b in' '"master:master"' 'for t in'; do
  printf '%s\n' "$SEG_RAW" | grep -qF "$pat" || { echo "FATAL 段里缺关键行: $pat（抽错段）"; exit 2; }
done
SEG=$(printf '%s\n' "$SEG_RAW" | sed 's/\${{[^}]*}}/SIM_ACTIONS_EXPR/g')
echo "----- 校准清单（唯一改写：Actions 表达式 → SIM_ACTIONS_EXPR）-----"
nc=0
while IFS= read -r ln; do
  case "$ln" in *'SIM_ACTIONS_EXPR'*) nc=$((nc+1)); echo "    | $ln" ;; esac
done <<< "$SEG"
echo "    | 改写行数=$nc（其余行与 workflow 逐字相同；段长 $(printf '%s\n' "$SEG" | wc -l) 行）"

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/syncsim.XXXXXX") || exit 2
trap 'rm -rf "$ROOT"' EXIT
export GIT_CONFIG_NOSYSTEM=1
# 环境隔离（与 scripts/git_env.py 同口径）：剥掉仓库定位变量，夹具 git 不会越过 cwd 碰真仓
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES \
      GIT_COMMON_DIR GIT_PREFIX GIT_NAMESPACE GIT_CEILING_DIRECTORIES 2>/dev/null || true

G="git -c user.name=t -c user.email=t@t -c init.defaultBranch=master"

# 夹具：bare 假远端 + 工作仓（只用 direct git，不经过被测段）
#   分支：br-ok-1（远端无此支 ⇒ 可推）、master（与远端同历史 ⇒ 可推）、br-bad-gone（必失败）
#   br-bad-gone 的失败成因与真 GitHub 同形：远端已有该分支且开了 denyNonFastForwards，
#   本地同名分支又被改指到一棵不相关历史 ⇒ force 也拒（"不允许非快进"）。
make_fixture() {
  local d=$1
  mkdir -p "$d/remote.git" "$d/work" || { echo "mkidx fail"; return 1; }
  $G -C "$d" init -q --bare remote.git || { echo "bare init fail"; return 1; }
  $G -C "$d" init -q work || { echo "init fail"; return 1; }
  $G -C "$d/work" config user.name t || return 1
  $G -C "$d/work" config user.email t@t || return 1
  echo base > "$d/work/f.txt" || return 1
  $G -C "$d/work" add f.txt || { echo "add fail"; return 1; }
  $G -C "$d/work" commit -qm base || { echo "commit fail"; return 1; }
  $G -C "$d/work" branch br-ok-1 || { echo "branch fail"; return 1; }
  $G -C "$d/work" tag tag-ok-1 || return 1
  $G -C "$d/work" tag tag-ok-2 || return 1
  $G -C "$d/work" remote add gh "$d/remote.git" || { echo "remote fail"; return 1; }
  $G -C "$d/work" branch br-bad-gone || { echo "branch2 fail"; return 1; }
  $G -C "$d/work" push -q gh "br-bad-gone:refs/heads/br-bad-gone" || { echo "seed push fail"; return 1; }
  $G -C "$d/remote.git" config receive.denyNonFastForwards true || return 1
  $G -C "$d/work" checkout -q --orphan other || { echo "orphan fail"; return 1; }
  $G -C "$d/work" rm -q -r --cached . >/dev/null 2>&1 || true
  rm -f "$d/work/f.txt" || return 1
  echo side > "$d/work/s.txt" || return 1
  $G -C "$d/work" add s.txt || return 1
  $G -C "$d/work" commit -qm side || { echo "commit2 fail"; return 1; }
  $G -C "$d/work" branch -f br-bad-gone other || return 1
  $G -C "$d/work" checkout -q master || { echo "back to master fail"; return 1; }
  return 0
}

# 跑抽取面：cwd = 夹具工作仓；`gh` = 假远端（段内 `git remote add gh` 会把 cwd 切到不存在的
# /tmp/repo，所以先真 `cd /tmp/repo` 会被 stub 掉——`cd` 也 stub 成 no-op）。
run_segment() {
  local wd=$1 segfile="$ROOT/seg.sh"
  printf '%s\n' "$SEG" > "$segfile"
  (
    cd "$wd" || exit 1
    SIM_SEG="$segfile"
    # 只保留 push/for-each-ref 走真 git；clone/remote add/fetch/config/rm/checkout/add/commit
    # 是网络与「工作流保面」步骤，与本改正无关 ⇒ no-op。
    # `cd` 也 no-op：段里的 `cd /tmp/repo` 是 Actions 专属路径。
    git() {
      case "$1" in
        push | for-each-ref) command git "$@" ;;
        *) return 0 ;;
      esac
    }
    cd() { return 0; }
    . "$SIM_SEG"
  )
}

CELLS=0; FAILS=0
chk() {
  CELLS=$((CELLS + 1))
  if [ "$2" = "$3" ]; then echo "  [ok]   $1 = $2"
  else echo "  [FAIL] $1: got=$2 want=$3"; FAILS=$((FAILS + 1)); fi
}
contains() { case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac; }
# for-each-ref 是字节序，点名顺序不固定 ⇒ 逐名核在场，不核顺序
allfour() {
  local o=$1 n=0
  for b in br-ok-1 br-bad-gone master other; do
    case "$o" in *"failed branches:"*"$b"*) n=$((n + 1)) ;; esac
  done
  case "$o" in *"::warning::failed branches:"*) [ "$n" -eq 4 ] && echo yes || echo "no($n/4)" ;; *) echo no ;; esac
}
field() {
  # $1=输出 $2=1(OK)|2(FAIL)
  if [ "$2" = "1" ]; then
    printf '%s\n' "$1" | sed -n 's/.*branch sync: OK=\([0-9]*\) FAIL=.*/\1/p' | head -1
  else
    printf '%s\n' "$1" | sed -n 's/.*branch sync: OK=[0-9]* FAIL=\([0-9]*\).*/\1/p' | head -1
  fi
}

echo
echo "===== 1) 现行段真跑：3 支可推 + 1 支必失败 ====="
F1="$ROOT/f1"; make_fixture "$F1" || { echo "FATAL 夹具造不出来（格1）"; exit 2; }
OUT1=$(run_segment "$F1/work" 2>&1); RC1=$?
printf '%s\n' "$OUT1" | sed 's/^/    | /'
echo "    | (exit=$RC1)"
chk "聚合读数行存在" "$(contains "$OUT1" '::notice::branch sync: OK=')" "yes"
chk "OK=3（br-ok-1 + master + other）" "$(field "$OUT1" 1)" "3"
chk "FAIL=1（br-bad-gone）" "$(field "$OUT1" 2)" "1"
chk "失败分支被点名" "$(contains "$OUT1" '::warning::failed branches: br-bad-gone')" "yes"
chk "master 成功读数" "$(contains "$OUT1" '::notice::master synced')" "yes"
chk "标签聚合读数行" "$(contains "$OUT1" '::notice::tag sync: OK=')" "yes"
chk "rc 语义不变（失败不阻断 ⇒ 0）" "$RC1" "0"

echo
echo "===== 2) 全失败面（远端 pre-receive 一律拒 ⇒ 每一次 push 都失败） ====="
F2="$ROOT/f2"; make_fixture "$F2" || { echo "FATAL 夹具造不出来（格2）"; exit 2; }
printf '#!/bin/sh
echo "fixture: remote rejects every push" >&2
exit 1
' > "$F2/remote.git/hooks/pre-receive"
chmod +x "$F2/remote.git/hooks/pre-receive" 2>/dev/null || true
OUT2=$(run_segment "$F2/work" 2>&1); RC2=$?
printf '%s\n' "$OUT2" | sed 's/^/    | /'
echo "    | (exit=$RC2)"
chk "全失败时 OK=0" "$(field "$OUT2" 1)" "0"
chk "全失败时 FAIL=4" "$(field "$OUT2" 2)" "4"
chk "四支全部点名" "$(allfour "$OUT2")" "yes"
chk "master 失败逐字点名" "$(contains "$OUT2" '::warning::master sync FAILED')" "yes"
chk "rc 语义不变（全失败也不阻断 ⇒ 0）" "$RC2" "0"

echo
echo "===== 3) 反证：旧写法 || echo 在同一夹具上必须假绿 ====="
OUT3=$( cd "$F1/work" && (
    git() { case "$1" in push | for-each-ref) command git "$@" ;; *) return 0 ;; esac; }
    set +e
    for b in $(git for-each-ref --format='%(refname:short)' refs/heads); do
      git push --force gh "$b:$b" 2>&1 || echo "push failed on $b"
    done
    echo "OLD_RC=$?"
  ) 2>&1 )
printf '%s\n' "$OUT3" | sed 's/^/    | /'
chk "旧写法确实遇到了失败" "$(printf '%s\n' "$OUT3" | grep -c 'push failed on br-bad-gone')" "1"
chk "旧写法 rc 仍 0（即假绿）" "$(printf '%s\n' "$OUT3" | sed -n 's/^OLD_RC=//p')" "0"
chk "旧写法无聚合读数" "$(contains "$OUT3" 'OK=')" "no"
chk "旧写法无 ::warning 点名" "$(contains "$OUT3" '::warning::failed branches:')" "no"

echo
echo "===== 汇总 ====="
echo "cells=$CELLS fails=$FAILS"
if [ "$FAILS" -eq 0 ]; then echo "SIMULATE OK（$CELLS 格全过）"; exit 0; fi
echo "SIMULATE FAIL（$FAILS/$CELLS 格越期望）"; exit 1
